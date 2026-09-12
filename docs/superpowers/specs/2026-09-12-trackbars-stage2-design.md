# Trackbars Stufe 2: senkrechte Leisten, Berufe, Ruhestein, Kampf-Timer

Stand 12.09.2026. Die vier Punkte, die beim Bau von v1 (29.08.) bewusst auf
Stufe 2 geschoben wurden. Dateien: `Modules/Trackbars.lua` (Engine),
`Modules/TrackbarsBlocks.lua` (Fabriken), `Modules/TrackbarsOptions.lua`.

## Senkrechte Leisten

- `cfg.orientation = "vertical"`: `length` wird zur Höhe, `breadth` (neu,
  Standard 160) zur Breite, `thickness` bleibt die Zeilenhöhe, nach der jeder
  Block Schrift und Symbole bemisst. Vollmodus pinnt an den linken oder
  rechten Bildschirmrand (`edge = left|right`, `edgeOffset` waagerecht).
- Layout: Seite „links" füllt von oben, „rechts" von unten, „Mitte" sitzt in
  der Mitte; jede Zeile = Zeilenhöhe + Block-Abstand, der Block ist in seiner
  Zeile zentriert. Gleichverteilung teilt die Höhe.
- Optionen: Klappmenü Ausrichtung; die Zeilen darunter wechseln ihre
  Beschriftung (Volle Höhe, Links/Rechts, Höhe statt Breite, Breite der
  Leiste, Zeilenhöhe). Ein Wechsel der Ausrichtung schiebt eine Kante auf die
  passende Achse.
- Fünfte Vorlage „Seitenleiste": links, volle Höhe, Berufe, Ruhestein,
  Kampf-Timer, Uhr.

## Blöcke

- **Kampf-Timer** (`combattimer`): Textblock, Herzschlag 1 s plus Regen-
  Ereignisse; im Kampf „Kampf m:ss", außerhalb optional „Letzter Kampf m:ss"
  gedimmt, sonst leer (Block verschwindet).
- **Ruhestein** (`hearth`): sicherer Gegenstandsknopf (`type=item`,
  `item:6948`), daneben Bindeort oder laufende Abklingzeit; Symbol gedimmt,
  solange sie läuft. Erzeugung, Größe und Platzierung nur außerhalb des
  Kampfes, Nachholen über PLAYER_REGEN_ENABLED (Muster Mikromenü).
- **Berufe** (`professions`): je Beruf ein Symbol mit Rang; abbrechbare
  Fertigkeitszeilen sind die Hauptberufe, Nebenberufe über die Namen der
  Zauber Kochen/Erste Hilfe/Angeln (Option). Handwerk = sicherer Zauberknopf
  (öffnet das Fenster), Sammeln = einfacher Knopf. Option Rang, Abstand.

## Prüfliste im Spiel

- Neue Leiste aus der Vorlage Seitenleiste: steht links, volle Höhe, vier
  Blöcke gestapelt; Kante rechts wechseln; Ausrichtung zurück auf waagerecht
  und die Kante landet unten.
- Berufe: Symbole und Ränge stimmen; Klick auf Handwerk öffnet das Fenster,
  auch direkt nach dem Login; Nebenberufe zuschalten.
- Ruhestein: Klick nutzt den Stein (außerhalb des Kampfes), Abklingzeit läuft
  im Text, Ort erscheint nach Ablauf; im Kampf keine Fehlermeldung.
- Kampf-Timer: läuft an der Puppe, zeigt danach den letzten Kampf.
