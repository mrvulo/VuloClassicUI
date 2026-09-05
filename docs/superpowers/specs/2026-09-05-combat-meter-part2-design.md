# Combat Meter, Teil 2: Fenster, Zahnrad, Aufschlüsselung, neue Modi

Stand 05.09.2026, Design vom Nutzer abgenommen. Baut auf Teil 1
(`2026-09-04-combat-meter-part1-design.md`) auf; Teil 1 ist noch nicht
ausgeliefert, darum dürfen Standardwerte und Profilfelder ohne Migration
geändert werden.

## Ziel

1. **Mehrere Fenster**, frei anlegbar, jedes mit eigenem Modus und Abschnitt;
   Aussehen und Sichtbarkeit geteilt.
2. **Zahnrad** in der Titelzeile, das die Optionsseite des Moduls öffnet.
3. **Balken im Referenz-Look**: Klassensymbol links, `1. Name`, rechts
   `184.2k (1.9k)`; Prozent standardmäßig aus.
4. **Vier neue Modi**: erlittener Schaden, Unterbrechungen, Bannungen, Tode.
5. **Tooltip mit Aufschlüsselung**: die stärksten Fähigkeiten je Spieler, mit
   Symbol, Wert und Anteil; je Modus passend.

## Datenmodell

Ein Spielereintrag im Abschnitt wächst um Zähler und um Untertabellen, die
erst beim ersten Ereignis ihrer Art angelegt werden (eine Tabellenanlage je
Spieler und Art, nie je Ereignis):

```lua
[sourceGUID] = {
    name, class,
    damage = 0, heal = 0, overheal = 0,          -- Teil 1
    taken = 0, interrupts = 0, dispels = 0, deaths = 0,
    spells   = nil | { [spellId] = amount },      -- verursachter Schaden je Zauber
    heals    = nil | { [spellId] = amount },      -- wirksame Heilung je Zauber (Rohheilung minus Überheilung)
    takenBy  = nil | { [spellId] = amount },      -- erlittener Schaden je Zauber
    kicks    = nil | { [spellId] = count },       -- unterbrochene Zauber
    purges   = nil | { [spellId] = count },       -- entfernte Effekte
    deathLog = nil | { { t = Sekunden, spell = spellId, amount = n, src = "Name" }, ... },
    lastSpell, lastAmount, lastSrc,              -- letzter Treffer, nur im laufenden Abschnitt
}
```

- Nahkampf (`SWING_DAMAGE`) läuft unter der Zauber-ID 6603 (Auto-Angriff),
  damit Name und Symbol aus dem Spiel kommen.
- `deathLog` hält je Abschnitt höchstens 20 Einträge, die neuesten gewinnen.
- Einfalten in „gesamt": Zähler addieren, Untertabellen je Zauber-ID
  addieren, Todesliste anhängen und auf 20 kappen. `lastSpell/lastAmount/lastSrc`
  werden nicht eingefaltet.
- „gesamt" liegt weiter in `VuloClassicUICharDB.meter.overall`; die
  Untertabellen werden mitgesichert. Ein Zurücksetzen leert alles.

## Protokoll-Leser

Der Leser liest je Feuern einmal `CombatLogGetCurrentEventInfo()` und
reicht jetzt sechs Felder weiter: `src, srcName, dst, a12, a15, a16`.
`srcName` (Feld 5) ist eine bereits existierende Zeichenkette, keine
Anlage.

| Unterereignis | Bedingung | Wirkung |
|---|---|---|
| `SWING_DAMAGE` | Quelle zählt | `damage`, `spells[6603]`; öffnet Abschnitt wie bisher |
| `SWING_DAMAGE` | Ziel in Gruppenliste | `taken`, `takenBy[6603]`, letzter Treffer |
| `RANGE/SPELL/SPELL_PERIODIC_DAMAGE`, `DAMAGE_SHIELD`, `DAMAGE_SPLIT` | Quelle zählt | `damage`, `spells[spellId]` |
| dieselben | Ziel in Gruppenliste | `taken`, `takenBy[spellId]`, letzter Treffer |
| `SPELL_HEAL`, `SPELL_PERIODIC_HEAL` | Quelle zählt | `heal`, `overheal`, `heals[spellId] += amount - overheal` |
| `SPELL_INTERRUPT` | Quelle zählt | `interrupts`, `kicks[extraSpellId]` |
| `SPELL_DISPEL`, `SPELL_STOLEN` | Quelle zählt | `dispels`, `purges[extraSpellId]` |
| `UNIT_DIED` | Ziel in Gruppenliste (kein Begleiter), nicht `UnitIsFeignDeath` | `deaths`, Todeseintrag aus dem letzten Treffer |
| `SPELL_SUMMON` | wie bisher | Begleiter-Karte |

„Quelle zählt" ist die Teil-1-Regel (Gruppenliste oder Besitzer in der
Gruppenliste). „Ziel in Gruppenliste" meint nur Spieler, keine Begleiter.
Erlittener Schaden, Heilung, Unterbrechungen, Bannungen und Tode öffnen
keinen Abschnitt; sie zählen nur, wenn `current` existiert. Ein Ereignis, das
sowohl Quelle als auch Ziel in der Gruppe hat (Spiegelbild, Fehlschuss),
zählt auf beiden Seiten.

Der Todeseintrag: `t = GetTime() - current.start`, `spell/amount/src` aus dem
letzten Treffer des Toten (fehlt er, `spell = nil`, Anzeige „Unbekannt").

## Fenster

Das Profil hält eine Liste:

```lua
windows = {
    [i] = { mode = "damage", segment = "current",
            x = 0, y = 0, width = 220, height = 160, scale = 1, unlocked = false },
}
```

- `defaults.windows = {}`. Beim Start mit leerer Liste legt das Fenster-Modul
  Fenster 1 an und übernimmt einmalig die Teil-1-Felder (`x, y, width, height,
  scale, unlocked, defaultMode, defaultSegment`), die danach aus den
  Standardwerten verschwinden.
- Je Listenplatz `i` ein Rahmen `VuloClassicUIMeter<i>` mit eigenem Mover
  (Schlüssel `meter<i>`, Beschriftung „Combat Meter <i>"), Titelzeile,
  Balkenzeilen, Sortier- und Scrollzustand. Rahmen werden gepoolt: ein
  geschlossenes Fenster versteckt seinen Rahmen, ein neues nimmt den
  nächsten freien Platz. Beim Schließen rückt die Liste auf; die Rahmen
  werden danach neu an ihre Listenplätze gebunden (Mover-`opts.db` zeigt auf
  die neue Fenstertabelle).
- Titelmenü je Fenster: die acht Modi, die zwei Abschnitte, „Neues Fenster"
  als Untermenü mit den Modi (neues Fenster erscheint 30 px versetzt zum
  Quellfenster, mit dessen Abschnitt und Größe), „Fenster schließen" (nur
  wenn mehr als ein Fenster offen ist), Zurücksetzen.
- Ein Ticker (0,5 s im Kampf) aktualisiert alle Fenster; jedes Fenster
  sortiert seine eigene Reihenfolge-Tabelle.
- Sichtbarkeitsregeln, Balkenhöhe, Abstand, Schrift, Textur und die
  Anzeigeschalter kommen aus `mod.db` und gelten für alle Fenster.
- Mausrad auf dem Titel wechselt den Modus des Fensters zyklisch durch alle
  acht.

## Titelzeile

Rechts drei Symbole: Zahnrad (`gear.tga`, Tooltip „Settings"), Zurücksetzen,
Klappmenü. Das Zahnrad öffnet das Optionsfenster, falls zu, und wechselt auf
die Seite `meter` (`ns.UI:ToggleMainFrame`, `ns.UI:ShowModulePage`).

## Balken

- Links ein quadratisches Klassensymbol (Kante = Balkenhöhe minus 2) aus
  `ns:GetClassIcon(class)`, Schalter `showClassIcon` (Standard an). Ohne
  Symbol rückt der Text an den linken Rand.
- Links `1. Name` (Rang per Schalter wie bisher).
- Rechts, je Modusgruppe:
  - Mengenmodi (Schaden, Heilung, erlittener Schaden): `Gesamt (pro Sekunde)`;
    mit Prozent `Gesamt (pro Sekunde, 21.3%)`; ohne Klammerwert `Gesamt`
    bzw. `Gesamt (21.3%)`.
  - Sekundenmodi (DPS, HPS): Haupt- und Klammerwert getauscht, wie bisher.
  - Zählmodi (Unterbrechungen, Bannungen, Tode): `12`, mit Prozent `12 (21.3%)`.
- `showPercent` Standard **aus**.

## Tooltip

Beim Überfahren eines Balkens, `ANCHOR_RIGHT`:

- Titel: Spielername in Klassenfarbe (`color` im Tooltip-Spec).
- Block 1, je Modus, höchstens `tooltipRows` Zeilen (Option 3 bis 10, Standard 5),
  absteigend sortiert; Zauberzeilen als **zweispaltige Zeile**: links
  `|T<Symbol>:14:14:0:0:64:64:5:59:5:59|t Name`, rechts Wert und Anteil:
  - Schaden/DPS: `spells`, rechts `12.3k (34.5%)`, Anteil am eigenen Schaden.
  - Heilung/HPS: `heals`, Anteil an der eigenen wirksamen Heilung.
  - Erlittener Schaden: `takenBy`, Anteil am eigenen erlittenen Schaden.
  - Unterbrechungen: `kicks`, rechts die Anzahl.
  - Bannungen: `purges`, rechts die Anzahl.
  - Tode: `deathLog`, neueste zuerst, links `2:15 Todesstoß-Zauber`, rechts
    `12.3k · Quelle`.
  Leere Untertabelle: eine graue Zeile „No details yet".
- Leerzeile, dann Block 2 wie in Teil 1: Gesamt, pro Sekunde (nur
  Mengenmodi), Anteil, Überheilung (Heilmodi), Kampfdauer.
- Zaubername und Symbol über `GetSpellInfo(id)`, je ID einmal
  zwischengespeichert. Unbekannte ID: Text `#<id>` ohne Symbol.

**Gerüstausbau** (`UI/Tooltip.lua`): eine Zeilentabelle mit Feld `right`
wird per `AddDoubleLine` gezeichnet; die Farbfelder 2–4 gelten für beide
Seiten, `right` ist immer weiß. Bestehende Aufrufer bleiben unberührt.

## Optionsseite

- **Anzeige**: wie Teil 1, plus Schalter „Show class icon" (nach „Show rank")
  und Regler „Abilities in tooltip" (3–10). Der Regler liegt flach unter den
  Schaltern: es gibt kein Elternteil, bei dem er nichts täte.
- **Sichtbarkeit**: unverändert.
- **Fenster** (neuer Abschnitt, ersetzt „Verhalten"): je Fenster eine Zeile
  „Window <i>" mit Klappmenü Modus (Breite 150), Klappmenü Abschnitt
  (Breite 150), Knopf „Close" (nur bei mehr als einem Fenster); darunter
  Knopf „New window". Danach der Schalter „Reset overall when joining a new
  group".
- **Position**: Entsperren/Zurücksetzen für alle Fenster (Zurücksetzen setzt
  jedes Fenster auf `0, 0` plus 30 px Versatz je Platz).

Standardwerte nach Teil 2:

```lua
defaults = {
    enabled = true,
    barHeight = 18, barGap = 1, fontSize = 11, texture = "Atrocity",
    showRank = true, showClassIcon = true, showPerSecond = true,
    showPercent = false, highlightSelf = true, tooltipRows = 5,
    onlyInGroup = false, hideInCombat = false, hideOutOfCombat = false, hideDelay = 10,
    resetOnNewGroup = true,
    windows = {},
}
```

## Sprachschlüssel (neu, englische Schlüssel)

`Damage taken`, `Interrupts`, `Dispels`, `Deaths`, `Windows`, `Window %d`,
`New window`, `Close window`, `Close`, `Show class icon`,
`Abilities in tooltip`, `No details yet`, `Unknown`, `Combat Meter %d`.
Vorhandene wiederverwenden: `Settings`, `Reset`, `Total`, `Per second`,
`Share`, `Overhealing`, `Fight duration`, `Current fight`, `Overall`.

## Bewusst NICHT gebaut

Ziele im Tooltip, Klick-Aufschlüsselung als eigene Liste, Verlauf und
Chat-Bericht (Teil 4), Absorptionen, Fenster-Anker aneinander, je Fenster
eigenes Aussehen.

## Prüfliste (Spiel)

1. Übungspuppe: Tooltip zeigt die eigenen Zauber mit Symbol, Anteile summieren
   sich sinnvoll; Auto-Angriff erscheint mit Namen; Prozent ist aus; Klassen-
   symbol sitzt im Balken.
2. Zahnrad öffnet die Optionsseite des Meters.
3. Neues Fenster per Menü (Heilung), versetzt sichtbar; eigener Mover
   „Combat Meter 2"; Schließen über Menü und über die Optionsseite; `/reload`
   hält beide Fenster mit Modus und Position.
4. Fünfergruppe: erlittener Schaden beim Tank, Unterbrechung beim Kicker mit
   dem unterbrochenen Zauber im Tooltip, Bannung beim Priester, ein Tod mit
   Zeit und Todesstoß; Totstellen des Jägers zählt nicht.
5. Checker: `node tools/check.js`, `node tools/optcheck.cjs`.

## Nachtrag 05.09.2026: Schloss und Andocken

Vom Nutzer nach der Abnahme gewünscht, im selben Zug gebaut.

- **Schloss** in der Titelzeile (links vom Zahnrad, `lock.tga` / `lock_open.tga`
  aus dem Lucide-Satz). Je Fenster `locked` (Standard an). Entsperrt: Linksziehen
  auf Titel, Fläche oder Balken verschiebt das Fenster, das Schloss leuchtet in
  Akzentfarbe. Gesperrt: kein Ziehen; der Bearbeiten-Modus-Mover bewegt weiter.
  Das Rechtsziehen am Titel entfällt.
- **Andocken** über das Titelmenü „Ankern an": Untermenü mit „Keine" und je
  anderem Fenster vier Einträgen (Unten, Oben, Links, Rechts). Nutzt die
  Mover-Links des Gerüsts (`ns:SetMoverLink` + `SetMoverLinkSide(side, 0)` +
  `ApplyMoverLink` + `OnMoverRepositioned`), also dieselbe Verankerung wie im
  Bearbeiten-Modus. Verschieben eines Fensters trägt Angedockte mit
  (`OnMoverRepositioned` in `savePosition`), Größenänderung ebenso
  (`RepositionMoverChildren`).
- **Schließen mit Links**: Mover-Schlüssel sind Platznummern; beim Schließen
  werden die Link-Einträge im Profil (`moverLinks`) auf die verschobenen
  Schlüssel umgeschrieben, Links auf das geschlossene Fenster verworfen,
  danach `ApplyAllMoverLinks`.
- Neue Schlüssel: `Lock position`, `Unlock position`; Modulbeschreibung und
  Fenster-Zeile der Versionshinweise angepasst.
