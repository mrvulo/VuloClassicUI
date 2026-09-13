# Combat Meter, Teil 5: Spec-Symbol, Trefferstatistik, aktive Zeit, Anzeige, Instanz-Reset

Stand 13.09.2026, Reihenfolge vom Nutzer mit „mach weiter" abgenommen.
Grundlage: Vergleich mit den vier meistgenutzten Metern; gebaut wird, was
dort Alltag ist und uns fehlte.

## 1. Symbol auf dem Balken

Aus dem Schalter „Klassensymbol anzeigen" wird ein Klappmenü **Balkensymbol**:
Aus, Klasse, Spec. Gespeichert als `barIcon` (`off | class | spec`); ein
gespeichertes `showClassIcon = false` wird beim Aktivieren einmal in
`barIcon = "off"` überführt.

Bei „Spec" zeigt der Balken das Symbol des dominanten Talentbaums, solange
die Spec bekannt ist, sonst das Klassensymbol. Begleiter tragen das Symbol des
Besitzers (Klasse). Der Tooltip nennt die Spec in seiner ersten Zeile.

Drei Quellen, je Spieler die stärkste gewinnt (Quelle 2 überschreibt 1, 1
überschreibt den Vorrat):

0. **Vorrat**: kontoweiter Speicher `global.meterSpecs[name] = { class, tree, t }`,
   damit beim nächsten Raid die Symbole schon beim Pull stehen; Einträge
   älter als 30 Tage fallen beim Aktivieren weg.
1. **Signaturzauber**: talentexklusive Zauber je Klasse (Basis-IDs, per
   `GetSpellInfo` zum Namen aufgelöst, damit jeder Rang zählt). Aus
   `SPELL_CAST_SUCCESS`, `SPELL_DAMAGE`, `SPELL_HEAL` eines Gruppenmitglieds.
   Nur Zauber, die es in genau einem Baum gibt.
2. **Inspektion / eigene Talente**: der eigene Charakter über
   `ns:DominantTalentTree()`. Gruppenmitglieder über eine Warteschlange: alle
   2 s ein `NotifyInspect` an ein Mitglied ohne bestätigte Spec, das in
   Reichweite steht (`CanInspect` + `CheckInteractDistance(unit, 1)`), nur
   außerhalb des Kampfes und nur, wenn das Inspektionsfenster nicht offen ist.
   `INSPECT_READY(guid)` liest die Punkte der drei Bäume über
   `C_SpecializationInfo.GetSpecializationInfo(i, true, false, unit)`; der
   Baum mit den meisten Punkten gewinnt. Danach `ClearInspectPlayer()`, sofern
   kein Inspektionsfenster offen ist. Fehlversuche werden nach fünf Minuten
   wiederholt.

Symbole und Namen je Klasse und Baum kommen aus
`C_SpecializationInfo.GetSpecializationInfoForClassID(classID, tree)`; keine
neue Textur.

## 2. Trefferstatistik

Die Engine zählt je Spieler und Zauber Treffer, kritische Treffer, Minimum
und Maximum (`spellStats` für Schaden, `healStats` für Heilung), aus dem
Kritisch-Feld des Protokolls (Schwung 18, Zauber 21, Heilung 18). Sichtbar
im Tooltip einer Zeile der Aufschlüsselung: Treffer, Kritisch (Anzahl und
Prozent), Durchschnitt, Minimum, Maximum.

## 3. Aktive Zeit

Je Spieler laufende Summe der Sekunden, in denen zwischen zwei eigenen
Ereignissen höchstens drei Sekunden lagen. Option **Basis pro Sekunde**:
Kampfzeit (bisher) oder aktive Zeit; wirkt auf DPS, HPS und die
„pro Sekunde"-Zeile des Tooltips. Der Tooltip zeigt die aktive Zeit immer,
mit ihrem Anteil an der Kampfzeit.

## 4. Anzeige

- **Balkenfarbe**: Klassenfarbe (bisher) oder eigene Farbe mit Farbwähler.
- **Fensterhintergrund**: Farbe und Deckkraft.
- **Balkenabstand**: 0 bis 6 Pixel (der Wert `barGap` gab es schon, ohne Regler).
- **Balken wachsen nach oben**: Titelzeile unten, Zeilen von unten nach oben.
- **Skalierung je Fenster**: Regler in der Fensterzeile der Optionsseite,
  50 bis 150 Prozent, über den vorhandenen Mover-Maßstab.

## 5. Zurücksetzen beim Betreten einer Instanz

Klappmenü Nie / Fragen / Immer. Beim Weltbeitritt wird die Instanz-ID
gemerkt; ändert sie sich zu einer Gruppen- oder Schlachtzugsinstanz, wird
„gesamt" zurückgesetzt (im Kampf erst nach dessen Ende) oder ein
Bestätigungsdialog gezeigt.

## 6. Ausblenden in Arena und auf Schlachtfeldern

Schalter neben „Nur in Gruppe" (das den Alleingang schon abdeckt). Neu
bewertet beim Weltbeitritt.

## Dateien

`Modules/Meter.lua` (Spec-Erkennung, Statistik, aktive Zeit, Instanz-Reset),
`Modules/MeterWindow.lua` (Symbol, Farben, Wuchsrichtung, Tooltips,
Sichtbarkeit), `Modules/MeterOptions.lua` (Regler und Menüs), neun
Sprachdateien, Changelog 1.62.0.

## Bewusst nicht gebaut

Sync zwischen Spielern, Plugin-Architektur, Verlaufsgraph, Buff-Laufzeit,
Vermeidungsmodus, Bossfilter, Manaquellen (aus dem Vergleich benannt, nicht
in der abgenommenen Reihenfolge).

## Prüfliste (Spiel)

- Spec-Symbol am eigenen Balken sofort; am Gruppenmitglied nach einem
  Signaturzauber oder nach der Inspektion; Klassensymbol als Rückfall.
- Inspektion darf das offene Inspektionsfenster nicht stören.
- Tooltip einer Aufschlüsselungszeile zeigt Treffer/Kritisch/Schnitt/Min/Max.
- DPS-Basis „aktive Zeit" verändert die Werte plausibel.
- Balken nach oben: Titel unten, Reihenfolge stimmt, Scrollen stimmt.
- Instanz-Reset „Fragen" zeigt den Dialog genau einmal je Instanz.
