# Combat Meter Teil 2 (Fenster, Zahnrad, Aufschlüsselung, neue Modi) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mehrere frei anlegbare Meter-Fenster mit eigenem Modus, ein Zahnrad zur Optionsseite, Balken im Referenz-Look (Klassensymbol, `184.2k (1.9k)`, Prozent aus), vier neue Modi (erlittener Schaden, Unterbrechungen, Bannungen, Tode) und ein Tooltip mit Zauber-Aufschlüsselung.

**Architecture:** Die Engine (`Modules/Meter.lua`) bekommt je Spieler lazy angelegte Untertabellen und fünf neue Handler in der bestehenden Verteiltabelle; der Leser reicht ein sechstes Feld (`srcName`) weiter. Das Fenster (`Modules/MeterWindow.lua`) wird von einem Einzelrahmen zu einem Rahmen-Pool über `mod.db.windows`; jeder Rahmen trägt seinen eigenen Sortier- und Scrollzustand, ein gemeinsamer Ticker zeichnet alle. Das Tooltip-Gerüst lernt zweispaltige Zeilen.

**Tech Stack:** WoW-Classic-Addon-Lua (Anniversary), Hausgerüst (`ns:RegisterModule`, `ns:AddTicker`, `ns:CreateMover`, `ns:ShowPopupMenu` mit `submenu`, `ns.UI:ShowTooltip`, `ns:GetClassIcon`, `ns.ClassColor`), Prüfwerkzeuge `node tools/check.js`, `node tools/optcheck.cjs`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-05-combat-meter-part2-design.md`.
- KEINE Fremd-Addon-Namen in Code, Kommentaren, Beschriftungen, Commits oder Doku.
- Locale-Schlüssel SIND die englischen Texte; `L[...]` nie auf Dateiebene auswerten.
- Beide TOC-Dateien bleiben gleich (keine neuen Dateien in diesem Teil).
- Protokoll-Leser: keine Tabellenanlage je Ereignis (Untertabellen nur beim ersten Ereignis je Spieler und Art), keine Zeichenketten-Operationen, `CombatLogGetCurrentEventInfo()` genau einmal.
- Optionsseite: Zeilen fluchten, Auswahl als Klappmenü, Abschnitte klappen nicht, `subOptions` nur hinter einem Elternteil, bei dem die Zeile sonst nichts täte.
- Teil 1 ist unreleased: Standardwerte und Profilfelder dürfen ohne Migration wechseln.
- Nach jeder Aufgabe `node tools/check.js` → `RESULT: OK`; nach Aufgabe 5 zusätzlich `node tools/optcheck.cjs`.
- Commit-Botschaften: deutsch, keine Abkürzungen, mit der vorgegebenen Co-Authored-By-Zeile.

## Dateistruktur

| Datei | Änderung |
|---|---|
| `UI/Tooltip.lua` | `fill()`: Zeilentabelle mit `right` → `AddDoubleLine`. Kopfkommentar ergänzen. |
| `Modules/Meter.lua` | Standardwerte (Teil-2-Satz), Spielereintrag mit neuen Zählern, `fold` mit Untertabellen und Todesliste, Leser mit `srcName`, Handler für erlittenen Schaden, Unterbrechung, Bannung, Tod; Zauber-Aufschlüsselung in den bestehenden Handlern. |
| `Modules/MeterWindow.lua` | Rahmen-Pool über `db.windows`, Bindung Rahmen↔Fenstertabelle, acht Modi, Rechtstext je Modusgruppe, Klassensymbol, Zahnrad, Menü mit Neues/Schließen, Tooltip mit Aufschlüsselung, Ticker über alle Rahmen. |
| `Modules/MeterOptions.lua` | Abschnitt „Fenster", Schalter Klassensymbol, Regler Tooltip-Zeilen, Position für alle Fenster. |
| `Locales/*.lua` (9) | 14 neue Schlüssel. |
| `CHANGELOG.md`, generierte Spielnotizen, Locale-Zeilen | 1.60.0-Block erweitern. |

---

### Task 1: Tooltip-Gerüst — zweispaltige Zeilen

**Files:** Modify `UI/Tooltip.lua` (`fill`, Kopfkommentar).

- [ ] In `fill`: `elseif type(line) == "table"` → wenn `line.right` gesetzt, `tip:AddDoubleLine(line[1], line.right, r, g, b, 1, 1, 1)`, sonst wie bisher.
- [ ] Kopfkommentar: Beispielzeile `{ "Frostbolt", nil, nil, nil, nil, right = "12.3k (34%)" }`.
- [ ] `node tools/check.js`, Commit.

### Task 2: Engine — Untertabellen, neue Zähler, neue Handler

**Files:** Modify `Modules/Meter.lua`.

**Produces:** Spielereintrag nach Spec-Datenmodell; `Meter.HANDLERS` um `SPELL_INTERRUPT`, `SPELL_DISPEL`, `SPELL_STOLEN`, `UNIT_DIED`; Leser reicht `(src, srcName, dst, a12, a15, a16)`.

- [ ] Standardwerte auf den Teil-2-Satz umstellen (`windows = {}`, `showClassIcon`, `tooltipRows`, `showPercent = false`; `x/y/width/height/scale/unlocked/defaultMode/defaultSegment` raus).
- [ ] `entry()` und `fold()` mit den neuen Feldern; Hilfsfunktion `bump(p, key, id, n)` legt die Untertabelle beim ersten Aufruf an; `foldDeaths` kappt auf 20.
- [ ] `addDamage(src, amount, spellId)`; `addTaken(dst, srcName, amount, spellId)` nur bei `current` und `roster[dst]`; Handler für Swing (6603) und Zauber (a12 = spellId, a15 = amount) rufen beide.
- [ ] `spellHeal`: `heals[spellId] += amount - overheal`.
- [ ] `SPELL_INTERRUPT`, `SPELL_DISPEL`/`SPELL_STOLEN` (a15 = extraSpellId), `UNIT_DIED` (Gruppenliste, `UnitIsFeignDeath(unit)` prüfen, Eintrag aus dem letzten Treffer).
- [ ] `onCLEU` liest Feld 5 mit und reicht sechs Felder.
- [ ] `node tools/check.js`, Commit.

### Task 3: Fenster — Rahmen-Pool, acht Modi, Balken-Look, Zahnrad, Menü

**Files:** Modify `Modules/MeterWindow.lua`.

**Consumes:** `mod.db.windows`, Spielerfelder aus Task 2.
**Produces:** `mod:ApplyWindow()`, `mod:WindowEnable()`, `mod:WindowDisable()`, `mod:AddWindow(mode, fromIndex)`, `mod:CloseWindow(index)`, `mod:SetMode(index, mode)`, `mod:SetSegment(index, seg)`.

- [ ] Modulzustand in einen Rahmen-Datensatz verschieben: `frames[i] = { frame, db, rows, order, vals, scroll, mode, segment, mover, lastTitle, lastCount }`; alle Funktionen nehmen den Datensatz als ersten Parameter.
- [ ] `ensureWindows()`: leere Liste → Fenster 1 aus den Teil-1-Feldern; `bind(f, wdb)` setzt `f.db`, `mover.opts.db`, Größe, Position; `syncFrames()` bindet Platz i an `windows[i]`, versteckt überzählige.
- [ ] MODES auf acht; `valueOf`, `rightText` je Modusgruppe; Klassensymbol in `createRow`/`layoutRows` (`ns:GetClassIcon`).
- [ ] Titelzeile: Zahnrad vor Zurücksetzen; Menü mit Untermenü „New window" und „Close window".
- [ ] Ticker/Listener/Sichtbarkeit über alle Rahmen.
- [ ] `node tools/check.js`, Commit.

### Task 4: Tooltip mit Aufschlüsselung

**Files:** Modify `Modules/MeterWindow.lua` (`rowEnter`).

- [ ] Zauber-Zwischenspeicher `spellName(id)`, `spellIcon(id)` über `GetSpellInfo`.
- [ ] Sortier-Hilfstabelle für die Untertabelle (wiederverwendet), Block 1 je Modus nach Spec, Block 2 wie Teil 1.
- [ ] `node tools/check.js`, Commit.

### Task 5: Optionsseite

**Files:** Modify `Modules/MeterOptions.lua`.

- [ ] Anzeige: „Show class icon", Regler „Abilities in tooltip".
- [ ] Abschnitt „Windows" nach Spec; „Behavior" entfällt, `resetOnNewGroup` wandert unter die Fensterliste.
- [ ] Position: Entsperren und Zurücksetzen für alle Fenster.
- [ ] `node tools/check.js`, `node tools/optcheck.cjs`, Commit.

### Task 6: Sprachen, Changelog, Spielnotizen

- [ ] 14 Schlüssel × 9 Sprachen (locale-translate-Pipeline).
- [ ] `CHANGELOG.md` 1.60.0-Block erweitern (changelog-Skill), Spielnotizen erzeugen, Notiz-Zeilen übersetzen.
- [ ] `node tools/check.js`, Commit.

### Task 7: Gegenprüfung

- [ ] adversarial-review über die drei Meter-Dateien und `UI/Tooltip.lua`; bestätigte Funde fixen, Checker, Commit.
- [ ] Spielprüfung nach der Spec-Prüfliste (Nutzer).
