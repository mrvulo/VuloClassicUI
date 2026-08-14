# Aktionsring: Live-Vorschau in der Optionsseite

Datum: 2026-08-14 · Status: abgenommen

## Ziel

Ein Vorschaubereich auf der Aktionsring-Optionsseite, der den gerade gewählten
Ring mit seinen Einträgen in der echten Anordnung zeigt und sich bei jeder
Einstellungsänderung sofort aktualisiert. Der bestehende „Vorschau"-Knopf
(öffnet den echten Ring) bleibt unverändert — er ist die zweite Hälfte der
Vorschau („Beides").

## Entscheidungen (mit dem Nutzer geklärt)

- **Miniatur in der Seite + echter-Ring-Knopf** (der Knopf existiert schon).
- **Anzeige + Plus-Knopf**: Tooltip je Eintrag, ein Plus öffnet den
  bestehenden Eintrags-Wähler; bearbeitet wird weiter in der Eintragsliste.
- **Platzierung**: eigener Abschnitt „Vorschau" zwischen „Einträge" und
  „Layout", volle Seitenbreite.

## Bauplan

### 1. Gemeinsame Layout-Quelle (Modules/ActionRing.lua)

Neue reine Funktion `previewLayout(index)` neben den bestehenden
Geometrie-Helfern, exportiert über `mod.optionsBridge`:

- Liest `PA(index)` (geteiltes Profil + Ring-Übersteuerung, dieselbe Sicht wie
  der echte Ring) und die Slots des Rings (ungefiltert, gekappt auf MAX_SLOTS).
- Rechnet je Layout-Modell mit denselben Helfern wie `openRing`:
  - **Bogen (ANGULAR)**: `arcGeom` + `ringRadius`, Position per sin/cos.
  - **Gitter (POINTER)**: `gridDims` + `gridBase`.
  - **Leiste (SCROLL)**: `fanFold`/`fanWindow`/`fanHoriz` um Ziel 1, mit
    derselben Fenster-Beschneidung wie im Spiel.
- Liefert: Modell, Icongröße, Skalierung, showActionText, Liste
  `{ slot, x, y }` (zentrumsrelativ) und eine Plus-Position:
  Bogen → Mitte (0,0); Gitter → die nächste freie Zelle; Leiste → eine
  Zellteilung hinter dem letzten sichtbaren Eintrag; leerer Ring → Mitte.
- Keine Kopie der Mathematik: nur Aufrufe der vorhandenen lokalen Funktionen.

### 2. Vorschau-Panel (Modules/ActionRingOptions.lua)

`buildPreviewPanel(parent)` nach dem Muster von `buildEntriesPanel`
(modullokales, gecachtes Panel mit `refresh()`), Höhe `PREVIEW_H = 210`:

- Innerer Halter-Frame in der Mitte; die Kacheln liegen in echter Geometrie
  darin, der Halter wird per `SetScale` eingepasst:
  `holderScale = p.scale * min(1, verfügbar / benötigt)` — nie über die echte
  Größe hinaus vergrößert, Proportionen bleiben wahr.
- Kacheln im Look der echten Ring-Slices (BackdropTemplate, dunkler Grund,
  1-px-Rand 0.22/0.22/0.27, Icon-TexCoord 0.08–0.92), gepoolt und
  wiederverwendet. Beschriftung unter dem Icon nur bei `showActionText`,
  wie im Spiel.
- Tooltip je Kachel über `br.slotDisplay(slot)`.
- Plus-Knopf an der gelieferten Plus-Position, öffnet `openPicker("entries")`,
  Tooltip = vorhandener Schlüssel „Add entry".
- Breiten-Messung nach dem ersten Zeichnen (OnShow/OnUpdate-Einmal-Muster wie
  im Eintrags-Panel).

### 3. Einhängen in die Seite

In `GetOptions()` zwischen dem Einträge-Panel und dem Layout-Kopf:
Spacer + Header (vorhandener Schlüssel „Preview") + `custom`-Eintrag mit
`buildPreviewPanel`.

### 4. Live-Aktualisierung

Kommt über den bestehenden Weg: jeder Setter der Seite ruft `refreshPage()`
(auch während des Regler-Ziehens), der Neuaufbau ruft `buildPreviewPanel` →
`refresh()`. Kein neuer Ereignisweg nötig. Die Übersteuerung je Ring ist
automatisch richtig, weil die Vorschau durch `PA(index)` liest.

## Nicht enthalten

- Hover-/Auswahl-Steuerung, Öffnen-bei-Position, Cooldowns, Nutzbarkeits-Tint
  — dafür gibt es den echten-Ring-Knopf.
- Neue Sprachschlüssel: keine — „Preview" und „Add entry" existieren bereits.

## Risiken

- Nur unsichere Frames, kein Berühren der Secure-Seite → kampf-/taint-frei.
- `gridDims` bei 0 Einträgen nicht aufrufen (Division durch 0 in `rows`);
  der leere Ring zeigt nur das Plus in der Mitte.

## Prüfung

- Statisch: Syntaxprüfung; danach adversarial-review über die zwei Dateien.
- Im Spiel: alle drei Layouts, Regler ziehen (Radius, Icongröße, Abstand,
  Bogenwinkel, Drehung, Spalten, Ausrichtung), Ring-Wechsel im Klappmenü,
  Übersteuerung an/aus, leerer Ring, 16 Einträge, Plus-Knopf.
