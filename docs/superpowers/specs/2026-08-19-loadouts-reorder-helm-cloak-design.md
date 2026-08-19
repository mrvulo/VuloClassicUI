# Sets sortieren per Drag-and-drop + Helm/Umhang je Set

Datum: 19.08.2026 · Modul: `Modules/Loadouts.lua` · vom Nutzer freigegeben (Design im Gespräch bestätigt)

## Ziel

Zwei Erweiterungen der Set-Seitenleiste im Charakterfenster:

1. Die Set-Zeilen lassen sich per Drag-and-drop umsortieren; die Reihenfolge wird gespeichert.
2. Jedes Set kann Helm und Umhang beim Anlegen ein- oder ausblenden — dreistufig
   (Zeigen / Verstecken / Nicht ändern), Standard „Nicht ändern".

## 1. Drag-and-drop-Reihenfolge

### Datenmodell

- Jedes Set (Eintrag in `LO()`, per Charakter) bekommt ein Feld `order` (Zahl).
- `sortedLoadoutNames()` sortiert nach `order`, bei Gleichstand nach Name.
- Migration ohne Sprung: Sets ohne `order` erhalten beim ersten Sortieraufruf ihre
  bisherige alphabetische Position als `order`. Bis zum ersten Ziehen ändert sich
  sichtbar nichts.
- Neue Sets (`saveAs`) hängen sich hinten an: `order` = Maximum + 1.
- Löschen lässt Lücken stehen; Lücken sind egal, nur die relative Ordnung zählt.
  Beim Ablegen wird die gesamte Liste neu von 1..n durchnummeriert.

### Zieh-Mechanik

- Die Set-Zeilen (`createSetRow`) registrieren `RegisterForDrag("LeftButton")`.
  `OnDragStart` feuert erst ab Blizzards Zieh-Schwelle, daher bleiben unberührt:
  Einfachklick (Auswahl), Doppelklick (Anlegen), Rechtsklickmenü, Ausklapp-Knopf.
- `OnDragStart`: ein schwebender Geist (eigener Frame, Symbol + Name, ~60 %
  Deckkraft, `SetFrameStrata("TOOLTIP")`) folgt per `OnUpdate` dem Mauszeiger.
- Während des Ziehens: Zielindex aus den Y-Mitten der sichtbaren **Set**-Zeilen
  (Skalierung über `GetEffectiveScale` berücksichtigen). Ausgeklappte Item-Zeilen
  sind keine Ziele; die Einfügeposition kann aber unter ihnen liegen (nach dem
  ausgeklappten Set). Eine dünne Linie in der Akzentfarbe zeigt die
  Einfügeposition zwischen den Zeilen.
- `OnDragStop`: liegt der Mauszeiger über der Leiste, wird das Set an der
  Linienposition eingefügt, alle `order`-Felder neu 1..n vergeben,
  `refreshSidebar()` gerufen. Liegt er außerhalb der Leiste, wird abgebrochen
  (keine Änderung). Geist und Linie verschwinden in beiden Fällen.
- Während des Ziehens ist der Zeilen-Tooltip unterdrückt.

## 2. Helm/Umhang je Set

### Datenmodell

- Zwei Felder je Set: `helm` und `cloak`, Werte `"show"` | `"hide"` | `nil`.
- `nil` = Nicht ändern (Standard). Bestehende Sets verhalten sich exakt wie bisher.

### Menü

- Im Rechtsklickmenü der Set-Zeile zwei Untermenü-Einträge „Helm" und „Umhang"
  (Mechanik `submenu` aus `Core/PopupMenu.lua`), eingeordnet nach
  „Symbol ändern…"/„Umbenennen…", vor der Talent-Bindung.
- Jedes Untermenü: drei Radio-Einträge (`radio = true`, `checked`-Funktion)
  Zeigen / Verstecken / Nicht ändern. Klick setzt das Feld und schließt das Menü.

### Anwenden

- Am Ende von `equipLoadout()` (nach der Slot-Schleife, vor den Meldungen):
  ist `helm` gesetzt, `ShowHelm(helm == "show")`; ist `cloak` gesetzt,
  `ShowCloak(cloak == "show")`. Nur rufen, wenn sich der Zustand tatsächlich
  ändert (`ShowingHelm()`/`ShowingCloak()` vorher lesen), damit kein unnötiger
  CVar-Schreibzugriff passiert.
- API gegen die Clientquelle verifiziert: `wow-ui-source-2.5.x` ruft selbst
  `ShowHelm(value)`/`ShowCloak(value)` (Blizzard_SettingsDefinitions_Frame/
  Classic/InterfaceOverrides.lua:30/46). Nicht geschützt, kein Taint-Risiko.
  `equipLoadout` blockt Kampf bereits am Anfang.
- Falls der 1.15-Client (Classic-Era-Anniversary) `ShowHelm` nicht kennt:
  Existenz prüfen (`if ShowHelm then`), Menüeinträge nur zeigen, wenn die API da
  ist.

### Tooltip

- Der Zeilen-Tooltip zeigt bei gesetztem Wert je eine Zeile, z. B.
  „Helm: verborgen" / „Umhang: sichtbar", in gedämpftem Grau unter der
  Slot-Liste.

## Sprachschlüssel

Neue Schlüssel (englische Basis, 9 Übersetzungen über die Locale-Pipeline):
„Helm", „Cloak" (falls nicht vorhanden), „Show", „Hide", „Don't change",
Tooltip-Formate „Helm: %s" / „Cloak: %s", „shown" / „hidden".
Genauer Bestand wird beim Bau gegen `Locales/` abgeglichen.

## Nicht-Ziele

- Kein Umsortieren per Menü (nur Drag-and-drop).
- Keine Schulter-/sonstige Anzeige-Umschalter — nur Helm und Umhang.
- Kein Einfangen des aktuellen Anzeige-Zustands beim Speichern (bewusst gegen
  die Alternative entschieden: dreistufig manuell im Menü).

## Prüfung

- `tools/check.js` (statisch) muss sauber bleiben.
- Spielprüfung: Umsortieren mit 2+ Sets (auch mit ausgeklappter Item-Zeile),
  Reload-Beständigkeit der Reihenfolge, Anlegen eines Sets mit
  Helm=Verstecken/Umhang=Zeigen, Sets ohne Felder unverändert.
