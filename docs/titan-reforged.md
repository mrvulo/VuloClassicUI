# Titan Reforged (China) — Stand, Messungen, offene Punkte

Register für alles, was diesen Client betrifft. **Verhalten steht in
`Core/Wrath.lua`, Geschichte steht hier.** Bei jeder neuen Runde unten anhängen,
mit Datum.

## Was Titan Reforged ist

Offiziell von Blizzard und NetEase, exklusiv China, kein privater Server.
Angekündigt 17.07.2025, gestartet 18.11.2025. Vanilla, The Burning Crusade und
Wrath zu einem Pfad bis Stufe 80 verschmolzen: neu entworfene Schlachtzüge,
überarbeitete Klassensets, aufwertbare legendäre Waffen, ein kontoweiter
Machtpfad neben der Charakterstufe, elf von den Spielern gemeinsam
freigeschaltete Phasen. **Regelwerk und Talentbäume sind Wrath 3.4.3.**

Nicht mit dem gleichnamigen Addon verwechseln. Der Name ist erlaubt: Titan
Reforged ist eine Blizzard-Spielversion, kein fremdes Addon, und steht nicht auf
der Verbotsliste in `tools/check.js`.

## Die technischen Zahlen — gemessen, nicht angenommen

| | |
|---|---|
| Interface | **38002** (vorher 38001), beide in unserer TOC-Liste |
| Client-Version | 3.80.0 / 3.80.1 / 3.80.2 |
| `WOW_PROJECT_ID` | **11** = `WOW_PROJECT_WRATH_CLASSIC` |
| `select(4, GetBuildInfo())` | **38002** |

Bestätigt am 30.07.2026 durch eine `/dump`-Zeile des Melders:

```
WOW_PROJECT_ID = 11        select(4, GetBuildInfo()) = 38002
VuloClassicUI.isBCC = false   VuloClassicUI.isEra = false
```

**Eine TOC reicht.** Die Dateiendung entscheidet nur, welche Datei geladen wird;
die Interface-Liste nur, ob der Client sie veraltet nennt. Eine `_Wrath.toc` war
nie nötig — der BigWigs-Packer liest die Komma-Liste und bietet die Variante an.

**Erkennung:** `Core/Namespace.lua` entscheidet zuerst über die Kennung, danach
über die Build-Nummer (11xxx Era, 2xxxx BCC, 3xxxx Wrath **inkl. Titan**, 4xxxx
Cata). Eine Zahlenspanne ist variantenfest, eine Konstantenliste nicht: vorher
ließ eine unbekannte Kennung ALLE Flaggen falsch, was schlechter ist als gar
keine Kennung.

## Was hier nicht hingehört

Die meisten Fehler aus den Titan-Berichten waren keine Titan-Fehler. Titan war
der Bote:

- der Verzauberungs-Filter kannte nur englische und deutsche Präfixe — kaputt für
  jeden chinesischen, koreanischen und russischen Spieler;
- das Klappmenü, das nicht ans Ende scrollte — alle 114 Klappmenüs, jeder Client
  mit niedrigem Bildschirm;
- der Einstellungs-Tod an einer nicht-endlichen Zahl — jedes Profil.

Solche Fixe stehen bei ihrem Feature und gelten überall. Sie hier oder in
`Core/Wrath.lua` abzulegen würde dem nächsten Leser verbergen, dass sie
allgemein sind.

## Die Fähigkeiten in `Core/Wrath.lua`

Acht Verzweigungen im ganzen Addon fragen nach dieser Client-Generation. Sie
fragen alle über `ns.Wrath.*`, damit die Antwort an einer Stelle steht:

| Fähigkeit | Wahr auf | Wer fragt |
|---|---|---|
| `hasRatings` | BCC + Wrath | `Modules/CharacterPanel.lua` |
| `hasWideQuestLog` | Wrath + Cata | `Modules/General.lua` (2×) |
| `hasDeathKnight` | Wrath | `Modules/GlobalSettings.lua` |
| `hasRunicPower` | Wrath | `Modules/GlobalSettings.lua` |
| `hasMovableLoot` | Wrath | `Modules/UnlockMode.lua` |
| `hasTotemicRecall` | Wrath | `Modules/Classes/Shaman.lua` |
| `hasTalentTrees` | Wrath | `Modules/TalentView.lua` |

Ein Feature, das es **nur** dort gibt, bekommt weiterhin eine eigene Datei mit
einem Modultor am Kopf — `Modules/TalentView.lua` ist das Muster.

## Chronik

### 30.07.2026 — Diagnose und erste Fixe (`870dd58`)

Ein Melder zeigte per Bild ein **leeres Charakterfenster**. Ursache gefunden und
belegt: `Modules/CharacterPanel.lua` hatte eine Positivliste
(`if not (ns.isBCC or ns.isEra) then return end`). Auf Wrath sind beide falsch,
das ganze Modul stieg aus.

Umgesetzt:

1. Das Modultor fragt jetzt nach `PaperDollItemSlotButton_Update`, der einzigen
   harten Abhängigkeit, statt nach einer Namensliste.
2. `Core/Namespace.lua` — Kennung zuerst, dann Build-Nummer als Rückfall.
3. Drei Wertungszeilen: `ns.isBCC` → `hasRatings`. Hier bleibt eine Namensliste
   **mit Absicht** — die Frage ist, ob das SPIEL die Wertung hat, nicht ob der
   Client die Funktion kennt.
4. `38001, 38002` in die Interface-Liste beider TOCs.

### 31.07.2026 — Bericht zu Client 3.80.2, vier Fixe

1. **Questlog-Knöpfe verschoben** bei „Größeres Questlog": unsere Vergrößerung
   ist auf die einspaltige Anatomie geeicht, Wrath hat nativ das breite
   Zweispalten-Log. Die Vergrößerung steigt aus, die Optionszeile wird gar nicht
   angeboten.
2. **Cooldown-Manager, gleichnamige Zauber fremder Klassen** (zhCN 复生 /
   自然迅捷): Klassentor vor dem Namensabgleich, Adoption per Zauber-ID.
   Restlücke bewusst: klassenlose Alteinträge mit ungelernter Rang-ID adoptiert
   niemand mehr per Name, sonst käme der Fehler zurück. Der Melder musste zwei
   falsch gestempelte Einträge einmal von Hand löschen.
3. **Klappmenü scrollte nicht ans Ende** bei 100+ Texturen: Fensterhöhe kam von
   der Bildschirmhöhe, öffnete aber immer nach unten. Jetzt wird der Platz unter
   dem Knopf gemessen und bei mehr Platz nach oben geöffnet. Betrifft alle 114
   Klappmenüs, auf jedem Client.
4. **Shift-Klick-Link zeigte den Questnamen der Gegenstandsstufe**: der
   zhCN-Client verarbeitet Linktexte gegen eigene Daten nach. Stufe steht jetzt
   außerhalb des Links, dazu eine Doppellauf-Sicherung.

### 01.08.2026 — der große Bericht ④–⑨ plus Persistenz

- **Persistenz (der kritische):** die SavedVariables-Datei starb an einer
  nicht-endlichen Zahl (nan/inf → Datei lädt nicht → Client legt `.bak` an →
  Werkszustand kontoweit). `ns:ScrubSavedVariables()` beim Abmelden entfernt
  solche Werte und Schlüssel; der Zähler landet in `global.scrubbedNonFinite`
  und wird beim nächsten Anmelden gemeldet.
  **Offen: existiert beim Melder eine `VuloClassicUI.lua.bak`?** Das bestätigt
  die Diagnose. Fehlende `.bak` plus unverändertes Dateidatum würde stattdessen
  heißen, dass der Client gar nicht schreibt.
- **④** Cooldown-Manager: Eintragsliste als Zahnrad-Zeilen, Eintrag parken,
  „Nur eigene" je Eintrag.
- **⑤** Charakterfenster: der zhCN-Kernfehler war der Grüne-Zeilen-Filter mit
  nur EN/DE-Präfixen — auf zhCN verdrängte die Sockelbonus-Zeile die echte
  Verzauberung. Jetzt lokalisierungsfest über Client-Globals, dazu UTF-8-sichere
  Kürzung (CJK zählt zwei Einheiten).
- **⑥** Totem-Rückruf: eigener sichtbarer Knopf, nur auf dieser Generation.
- **⑦** Neu `Modules/TalentView.lua`: drei Bäume nebeneinander, Ränge live,
  Klick lernt, ersetzt Blizzards Fenster. Bricht bei unplausiblen Shim-Formen ab
  und lässt Blizzards Oberfläche in Ruhe.
- **⑧** Freundesliste: Breitenregler.
- **⑨** Beutefenster verschiebbar (`direct`-Pfad in `Modules/UnlockMode.lua`).

### 01.08.2026, zweite Runde — Talentfenster-Nachbericht (`f53f89f`)

Der Melder bestätigt, dass das Talentfenster normal öffnet. Zwei Restfehler
behoben:

1. **Tooltip zeigte nur „TalentID: n"**: der 3.80.x-Shim beantwortet
   `GameTooltip:SetTalent(tab, index)` OHNE Fehler mit einem Platzhalter — der
   `pcall`-Erfolg war also kein Beweis. Jetzt wird die erste Tooltipzeile
   validiert, danach `GetTalentLink`, zuletzt ein selbst gebauter Tooltip.
2. **Taste schloss das Fenster nicht**: Blizzards Umschalter sieht nur sein
   eigenes, von uns verstecktes Fenster, also ist jeder Druck ein Öffnen. Der
   Hook behandelt „unser Fenster ist schon offen" jetzt als zweite Hälfte des
   Umschaltens.

### 02.08.2026 — dieses Register und `Core/Wrath.lua`

Die acht Variantenverzweigungen fragen jetzt über `ns.Wrath.*` statt die
Flaggen direkt. Verhalten unverändert; die Datei ist der eine Ort, an dem
Neues zu dieser Client-Generation dazukommt.

## Offene Punkte

- **Cata und der Todesritter.** `hasDeathKnight` und `hasRunicPower` sind
  bewusst nur auf Wrath wahr, weil die beiden Farblisten das vorher so hielten.
  Auf einem Cata-Client wären sie ebenfalls wahr. Verhalten zu ändern ist eine
  eigene Entscheidung; wenn wir je für Cata ausliefern, gehört das geprüft.
- **`.bak`-Frage an den Melder** (siehe Persistenz oben) — bestätigt oder
  widerlegt die Diagnose zum Werkszustand.
- **Beim nächsten Release nachsehen**, ob der Packer die Titan-Variante wirklich
  anbietet (Flavours im Lauf-Log von CurseForge und Wago). Das ist die einzige
  Stelle, die diese Änderung praktisch bestätigen kann.
- **Feature-Wunsch offen:** „Nur eigene Zauber" im Cooldown-Manager je
  Einzelzauber statt global — inzwischen gebaut (④), aber der ursprüngliche
  Anwendungsfall (fremdes Focus Magic auf mir verfolgen) ist im Spiel ungeprüft.
- **Alles aus den Runden 31.07. und 01.08. ist im Spiel ungeprüft.** Wir können
  diesen Client nicht selbst testen: Regionssperre, chinesisches Konto. Jede
  Bestätigung kommt vom Melder.
