# Combat Meter, Teil 1: Engine und Fenster

Stand 04.09.2026, Design vom Nutzer abgenommen (Bauweise 1: drei Dateien,
Engine im Modul).

## Ziel

Ein leichtgewichtiges Schadens- und Heilungsmeter als eigenes Modul. Teil 1
liefert die Kampfprotokoll-Engine und ein Balkenfenster mit vier Modi
(Schaden, Schaden pro Sekunde, Heilung, Heilung pro Sekunde) und zwei
Abschnitten (aktueller Kampf, gesamt). Der Alltagsblick „wer macht wie viel"
muss damit allein schon nützlich sein.

Das Gesamtvorhaben ist in vier Teile geschnitten, jeder mit eigener
Spezifikation und eigenem Bauplan:

1. **Engine und Fenster** (diese Spezifikation).
2. **Aufschlüsselung**: Klick auf einen Balken öffnet die Zauberliste des
   Spielers (Anteil, Treffer, kritisch, Durchschnitt) und dahinter die Ziele.
3. **Ereignisse**: Tode mit den letzten Sekunden davor, Unterbrechungen,
   Bannungen, erlittener Schaden als weitere Modi.
4. **Verlauf und Bericht**: Bosskampf-Historie mit mehreren gespeicherten
   Abschnitten, Zahlen per Klick in den Chat schicken, ggf. Abgleich mit
   anderen Spielern.

Physikalische Grenze für alle Teile: das Meter sieht nur, was das eigene
Kampfprotokoll sieht. Ohne Abgleich (Teil 4) fehlt alles außerhalb der
Protokollreichweite.

## Lieferumfang

1. **`Modules/Meter.lua`** (neu): Modul `meter`, Anzeigename „Combat Meter",
   Gruppe `HUD`. Enthält Gruppenliste, Begleiter-Zuordnung,
   Kampfprotokoll-Leser, Abschnittsverwaltung, Sicherung von „gesamt". Stellt
   eine Lese-Schnittstelle für das Fenster bereit (siehe Engine-Schnittstelle).
   Kennt das Fenster nicht.
2. **`Modules/MeterWindow.lua`** (neu): Balkenfenster mit Titelzeile,
   Klappmenü, Mausrad, Tooltip, Mover-Anbindung, Sichtbarkeitsregeln,
   Aktualisierungs-Ticker.
3. **`Modules/MeterOptions.lua`** (neu): `mod:GetOptions()` nach den
   Hausregeln der Optionsseiten.
4. **TOC**: die drei Dateien in dieser Reihenfolge nach `Modules\CombatText.lua`
   eintragen, in beiden TOC-Dateien, falls es zwei gibt.
5. **Locales ×9**: neue Schlüssel für Modulname, Beschreibung, Modi,
   Abschnitte, Menüeinträge, Optionsbeschriftungen, Tooltip-Zeilen und den
   Leerhinweis. Vorhandene Schlüssel wiederverwenden; die tote Schlüsselliste
   mitprüfen (Lehre v1.58.3).
6. **Changelog-Eintrag** im Hausformat.

## Datenmodell

Die Engine hält genau zwei lebende Abschnitte:

- **`current`**: der laufende Kampf; `nil` außerhalb des Kampfes.
- **`overall`**: Summe aller beendeten Kämpfe seit dem letzten Zurücksetzen.

Nach dem Kampfende bleibt der zuletzt beendete Abschnitt als „aktueller Kampf"
sichtbar, bis ein neuer beginnt. `InCombat()` ist ab dem Schließen `false`.

Ein Abschnitt:

```lua
{
    title    = "Boss-Name" oder nil,   -- nur aus ENCOUNTER_START
    start    = GetTime()-Stempel,      -- Kampfbeginn
    duration = Sekunden,               -- current: laufend berechnet; overall: Summe der Kampfdauern
    players  = {
        [sourceGUID] = {
            name     = "Name",
            class    = "WARRIOR",       -- Klassen-Token aus der Gruppenliste
            damage   = 0,
            heal     = 0,               -- Rohheilung inklusive Überheilung
            overheal = 0,
        },
    },
}
```

Angezeigte Heilung ist `heal - overheal`. Wert pro Sekunde ist Wert geteilt
durch `duration`; in „gesamt" ist `duration` die Summe der Kampfdauern, nicht
die Wanduhr. Beim Einfalten von `current` in `overall` werden je Spieler die
drei Zähler addiert, `duration` addiert, `title` bleibt in `overall` leer.

Mehr Felder gibt es in Teil 1 nicht. Teil 2 hängt je Spieler eine
Zaubertabelle an, Teil 3 weitere Zähler; beide erweitern die Verteiltabelle
des Protokoll-Lesers, ohne seinen Rumpf zu ändern.

## Gruppenliste und Begleiter

- **Gruppenliste** `roster[guid] = { unit = "raid7", name, class }`. Aufbau bei
  Modulstart, `GROUP_ROSTER_UPDATE`, `PLAYER_ENTERING_WORLD`. Enthält immer den
  eigenen Spieler. Allein gilt: nur der eigene Spieler zählt.
- **Begleiter-Karte** `owners[petGUID] = ownerGUID`. Zwei Quellen:
  1. `UNIT_PET` und der Listenaufbau: für jede Gruppeneinheit die zugehörige
     Begleiter-Einheit (`pet`, `partypetN`, `raidpetN`) per `UnitGUID`.
  2. `SPELL_SUMMON` im Protokoll: Quelle in der Gruppenliste, Ziel-GUID wird
     dem Quell-GUID zugeordnet. Deckt Totems, Wasserelementar, Wächter ab.
- **Zählregel**: ein Ereignis zählt, wenn `sourceGUID` in der Gruppenliste
  steht, sonst wenn `owners[sourceGUID]` in der Gruppenliste steht (der Wert
  geht auf den Besitzer). Alles andere wird verworfen. Ein Begleiter ohne
  bekannten Besitzer wird verworfen, nie als eigener Eintrag geführt.
- Die Begleiter-Karte wird beim Listenaufbau nicht geleert (Beschwörungen
  überleben Gruppenänderungen); Einträge, deren Besitzer die Gruppe verlässt,
  fallen durch die Zählregel heraus. Beim Zurücksetzen von „gesamt" wird die
  Karte geleert.

## Kampfprotokoll-Leser

Ein Handler auf `COMBAT_LOG_EVENT_UNFILTERED` über `mod:RegisterEvent` (läuft
im ungeschützten Hot-Pfad von `Core/Events.lua`). Er ruft
`CombatLogGetCurrentEventInfo()` genau einmal und liest die Felder in lokale
Variablen. Verteilung über eine Tabelle `HANDLERS[subevent] = fn`; Unterereignisse
ohne Eintrag werden mit einem Tabellenzugriff verworfen.

Teil-1-Einträge:

| Unterereignis            | Feld          | Zähler   |
|--------------------------|---------------|----------|
| `SWING_DAMAGE`           | amount (12)   | damage   |
| `RANGE_DAMAGE`           | amount (15)   | damage   |
| `SPELL_DAMAGE`           | amount (15)   | damage   |
| `SPELL_PERIODIC_DAMAGE`  | amount (15)   | damage   |
| `DAMAGE_SHIELD`          | amount (15)   | damage   |
| `DAMAGE_SPLIT`           | amount (15)   | damage   |
| `SPELL_HEAL`             | amount, overheal (15, 16) | heal, overheal |
| `SPELL_PERIODIC_HEAL`    | amount, overheal (15, 16) | heal, overheal |
| `SPELL_SUMMON`           | –             | Begleiter-Karte |

Nicht in Teil 1: Absorptionen (`SPELL_ABSORBED`; im Bauplan prüfen, ob das
Unterereignis auf Anniversary feuert), Umgebungsschaden, `SPELL_BUILDING_*`.

Kosten-Regeln für den Handler:

- Keine Tabellenanlage je Ereignis. Der Spielereintrag entsteht nur beim
  ersten Auftauchen eines Spielers im Abschnitt.
- Keine Zeichenketten-Operationen im Handler. Name und Klasse kommen aus der
  Gruppenliste, nicht aus dem Ereignis.
- Der Handler setzt nur `dirty = true`; er ruft nie das Fenster.
- Ein Schadensereignis, das bei fehlendem `current` zählt, öffnet den
  Abschnitt (siehe Grenzen).

## Abschnittsgrenzen

Start (öffnet `current`, wenn keiner läuft):

- `PLAYER_REGEN_DISABLED`.
- Erstes gezähltes Schadensereignis (nicht Heilung: Vorkampf-Heilung öffnet
  keinen Abschnitt).
- `ENCOUNTER_START`: schließt einen laufenden Abschnitt sofort und öffnet einen
  frischen mit dem Bossnamen als `title`.

Ende (faltet `current` in `overall`, sichert, setzt `current = nil`):

- `ENCOUNTER_END`: sofort.
- Sonst: `PLAYER_REGEN_ENABLED` startet einen Ticker mit 0,5 s (`ns:AddTicker`),
  der alle Gruppeneinheiten mit `UnitAffectingCombat` prüft. Findet er zweimal
  hintereinander niemanden im Kampf, endet der Abschnitt. Findet er jemanden,
  läuft er weiter. Wird der Spieler wieder in den Kampf gezogen
  (`PLAYER_REGEN_DISABLED`), wird der Ticker abgebrochen und der Abschnitt
  läuft weiter. Der Ticker existiert nur in dieser Wartephase.
- `ENCOUNTER_END` ohne laufenden Abschnitt: nichts. `ENCOUNTER_START` bei
  laufendem Abschnitt: der laufende wird regulär beendet, dann der neue
  geöffnet.

`duration` von `current` ist `GetTime() - start`, beim Ende eingefroren.

## Sicherung und Zurücksetzen

- `overall` IST die Tabelle `VuloClassicUICharDB.meter.overall`; sie wird beim
  Modulstart übernommen (fehlende Felder ergänzt) und lebt dort. Es gibt keine
  Kopie am Kampfende und keinen Logout-Haken. Im Kampf wird nichts geschrieben,
  weil der laufende Abschnitt eine eigene Tabelle ist, die erst am Ende
  eingefaltet wird.
- Zurücksetzen (Menü) leert `overall`, `current` und die Begleiter-Karte,
  löscht die Sicherung.
- Option `resetOnNewGroup` (Standard an): beim Wechsel von „keine Gruppe" zu
  „Gruppe" oder bei Wechsel der Gruppenart (Gruppe zu Schlachtzug) wird
  „gesamt" ohne Nachfrage zurückgesetzt. Nicht beim Beitritt einzelner
  Mitglieder.

## Engine-Schnittstelle (für das Fenster)

Damit ein späterer Umzug nach `Core` ein Verschieben bleibt:

```lua
ns.Meter:GetSegment("current" | "overall")   -- laufender oder letzter Kampf / gesamt
ns.Meter:Duration(seg)                         -- laufende Dauer beim offenen Abschnitt
ns.Meter:IsDirty() / ns.Meter:ClearDirty()
ns.Meter:InCombat()                            -- true, solange ein Abschnitt offen ist
ns.Meter:SetListener(fn)                       -- fn("start" | "end" | "reset")
ns.Meter:PlayerGUID()
ns.Meter:Reset()
```

Das Fenster liest über diese Griffe und schreibt nie in die
Abschnittstabellen.

## Fenster

- **Rahmen**: ein Fenster, Haus-Mover (`ns:CreateMover`, Schlüssel `meter`),
  im Bearbeiten-Modus in Breite und Höhe ziehbar. Balkenzahl =
  `floor((Höhe - Titelhöhe) / (Balkenhöhe + Abstand))`. Das Fenster wächst nie
  mit dem Inhalt.
- **Titelzeile**: links Text „<Modus> · <Abschnitt>", bei Bosstitel
  „<Modus> · <Bossname>". Rechts zwei Symbole: Zurücksetzen und Klappmenü.
  Linksklick auf den Titel öffnet `ns:ShowPopupMenu` mit drei Blöcken: die vier
  Modi, die zwei Abschnitte, Zurücksetzen. Mausrad auf der Titelzeile wechselt
  den Modus zyklisch. Rechtsklick-Ziehen auf der Titelzeile verschiebt das
  Fenster auch außerhalb des Bearbeiten-Modus.
- **Balken**: Aufbau „klassisch": Rang, Name, rechts Gesamtwert und in Klammern
  Wert pro Sekunde und Anteil, z. B. `184.2k (1.9k, 21.3%)`. In den Modi „pro
  Sekunde" ist der Hauptwert der Sekundenwert und in der Klammer stehen
  Gesamtwert und Anteil. Klassenfarbe aus `ns.CLASS_COLORS`, Balkenlänge
  relativ zum Ersten, eigener Balken mit dezenter Umrandung in Akzentfarbe.
  Anteil ist Anteil an der Summe aller gezählten Spieler im Abschnitt.
- **Zahlenkürzung**: ab 1.000 `1.2k`, ab 1.000.000 `1.2m`. Der Formatierer hält
  einen Zwischenspeicher je Ganzzahlwert, geleert bei Abschnittsende.
- **Tooltip** beim Überfahren eines Balkens: Gesamt, pro Sekunde, Anteil,
  Kampfdauer; bei Heilmodi zusätzlich Überheilung als Prozent der Rohheilung.
- **Mausrad** über den Balken scrollt die Liste um eine Zeile; die Titelzeile
  zeigt bei gescrollter Liste „7 von 25".
- **Balkenrahmen** werden einmal je sichtbarer Zeile angelegt und
  wiederverwendet; es gibt keinen Rahmen je Spieler.
- **Leerzustand**: Titelzeile bleibt, darunter grau der Hinweis „No combat
  data" (lokalisiert).

## Aktualisierung

- Im Kampf läuft ein Ticker mit 0,5 s. Er prüft `IsDirty()`, sortiert bei
  Bedarf die Spieler des angezeigten Abschnitts nach dem Moduswert absteigend
  in eine wiederverwendete Reihenfolge-Tabelle und zeichnet die sichtbaren
  Zeilen. Ohne Flag zeichnet er nur die Sekundenwerte neu (Dauer läuft).
- Außerhalb des Kampfes steht der Ticker. Moduswechsel, Abschnittswechsel,
  Scrollen, Zurücksetzen und Optionsänderungen zeichnen einmal von Hand.
- Sortierung: `table.sort` auf der Reihenfolge-Tabelle mit einer vorab
  angelegten Vergleichsfunktion, keine Closure je Aufruf.

## Sichtbarkeit

Optionen, alle als Schalter:

- `onlyInGroup` (Standard aus): allein ausblenden.
- `hideInCombat` (Standard aus).
- `hideOutOfCombat` (Standard aus) mit Nachlaufzeit `hideDelay` (Sekunden,
  Standard 10) hinter dem Zahnrad.
- `scale` (0,5 bis 2,0, Standard 1,0).

Sichtbarkeit wird an `PLAYER_REGEN_*`, `GROUP_ROSTER_UPDATE` und dem
Abschnittsende neu bewertet. Im Bearbeiten-Modus ist das Fenster immer
sichtbar.

## Optionsseite

Nach den Hausregeln: Zeilen fluchten, Symbolstreifen rechts reserviert,
Auswahl als Klappmenü, Unteroptionen nur hinter dem Zahnrad, Abschnitte
klappen nicht.

- **Aktivieren** als Modulschalter oben.
- **Anzeige**: Balkenhöhe (12–30, Standard 18), Schriftgröße (8–16, Standard
  11), Balkentextur (Medienliste, Standard wie Schwungtimer), Skalierung.
  Danach vier flache Schalter `showRank`, `showPerSecond`, `showPercent`,
  `highlightSelf` (alle Standard an); sie haben kein Elternteil, hinter dem
  sie nichts täten.
- **Sichtbarkeit**: die drei Schalter oben; Zahnrad: `hideDelay`.
- **Verhalten**: `defaultMode` (Klappmenü mit den vier Modi, Standard Schaden),
  `defaultSegment` (Klappmenü, Standard aktueller Kampf), `resetOnNewGroup`.
- **Position**: Entsperren und Zurücksetzen, verbunden mit dem Mover.

Textur, Balkenhöhe, Schriftgröße, Skalierung und die Anzeige-Schalter greifen
sofort. Alles liegt im Profil (`mod.db`), nur `overall` liegt in der
Charakter-Datenbank.

Profil-Standardwerte:

```lua
defaults = {
    enabled         = true,
    width           = 220,
    height          = 160,
    barHeight       = 18,
    barGap          = 1,
    fontSize        = 11,
    texture         = "Atrocity",
    scale           = 1.0,
    showRank        = true,
    showPerSecond   = true,
    showPercent     = true,
    highlightSelf   = true,
    onlyInGroup     = false,
    hideInCombat    = false,
    hideOutOfCombat = false,
    hideDelay       = 10,
    defaultMode     = "damage",      -- damage | dps | heal | hps
    defaultSegment  = "current",     -- current | overall
    resetOnNewGroup = true,
    x = 0, y = 0, unlocked = false,
}
```

## Fehlerfälle

- **Kampfbeginn ohne Gruppenliste**: Liste wird bei `OnEnable` gebaut, nicht
  erst beim ersten Gruppenereignis.
- **Begleiter ohne Besitzer**: verworfen.
- **Spieler verlässt die Gruppe im Kampf**: bleibt im laufenden Abschnitt,
  neue Ereignisse zählen nicht mehr.
- **Reload im Kampf**: `current` verloren, `overall` vom letzten Kampfende,
  Fenster startet mit `defaultMode`/`defaultSegment`.
- **Begegnungs-Ereignisse in falscher Reihenfolge**: siehe Abschnittsgrenzen.
- **Unbekanntes Unterereignis**: ein Tabellenzugriff, kein Fehler.
- **Verunreinigung**: das Fenster fasst keine geschützten Rahmen an; keine
  Verunreinigungsfläche.

## Bewusst NICHT gebaut (YAGNI)

- Zauber- und Ziel-Aufschlüsselung (Teil 2).
- Tode, Unterbrechungen, Bannungen, erlittener Schaden (Teil 3).
- Verlauf mehrerer Abschnitte, Chat-Bericht, Abgleich (Teil 4).
- Absorptionen, Bedrohung.
- Mehrere Fenster, Fenster-Anker aneinander.
- Eigener Trackbars-Block für den eigenen Sekundenwert (Kandidat für später).
- Diagramme, Zeitreihen, Sicherung während des Kampfes.

## Prüfliste (Spiel)

1. **Allein am Übungspuppen-Gegner**: Abschnitt öffnet beim ersten Treffer,
   schließt etwa eine Sekunde nach dem letzten; Gesamtschaden stimmt mit dem
   Kampfprotokoll des Spiels überein; Moduswechsel per Menü und Mausrad;
   Zurücksetzen leert beides; `/reload` bringt „gesamt" zurück.
2. **Fünfergruppe**: Begleiter (Jäger-Tier, Hexer-Dämon, Totems) landen beim
   Besitzer; Kampf endet erst, wenn der Tank draußen ist; Gruppenbeitritt
   setzt „gesamt" zurück; Verlassen der Gruppe stoppt das Zählen.
3. **Schlachtzug mit Profiler**: Kosten je Ereignis unter dem
   Kampftext-Modul, das denselben Strom liest; Bossbegegnung erhält den
   Bossnamen im Titel und schließt am Begegnungsende sofort; Mausrad-Scrollen
   über 25 Einträge.
4. **Checker** vor dem Commit: keine toten Sprachschlüssel, keine ungenutzten
   Locals, Optionszeilen fluchten.
