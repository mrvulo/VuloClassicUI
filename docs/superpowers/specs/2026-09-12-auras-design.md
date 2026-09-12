# Auren-Anzeige

Stand 12.09.2026. `Modules/Auras.lua`, Modul `auras` (HUD, ab Werk AUS wie
Trackbars: neue Fläche, die die Fenster des Spiels ersetzt).

## Grundlage (Anniversary-Quelle, `Blizzard_RestrictedAddOnEnvironment/SecureGroupHeaders.lua`)

- `SecureAuraHeaderTemplate` erzeugt je Aura einen sicheren Knopf aus der
  XML-Vorlage in `template`, sortiert (`sortMethod` INDEX/NAME/TIME,
  `sortDirection`, `separateOwn`), bricht um (`wrapAfter`, `wrapYOffset`,
  `maxWraps`) und setzt je Knopf `index` + `filter`; Waffenverzauberungen
  über `includeWeapons=1` + `weaponTemplate` mit `target-slot`.
- Wir geben als Vorlage `SecureActionButtonTemplate` (existiert, braucht
  keine eigene XML) und kleiden jeden Knopf beim ersten Malen selbst ein
  (Symbol, Pixelrand, Zähler, Restzeit, Tooltip). `initialConfigFunction`
  setzt `type2 = cancelaura` im restricted Umfeld; die Aktion liest `index`/
  `filter` bzw. `target-slot` (`SecureTemplates.lua` L468).
- Hook auf `SecureAuraHeader_Update`: neue Knöpfe bekommen ihre Größe
  (außerhalb des Kampfes), dann ein `_refresh`-Attribut im nächsten Bild,
  damit die Kopfzeile mit der echten Knopfgröße neu anordnet.

## Kampfregeln

Attribute, Größen, Show/Hide der Kopfzeile nur außerhalb des Kampfes;
Änderungen im Kampf setzen `pending` und laufen bei PLAYER_REGEN_ENABLED.
Texturen und Text jederzeit. Ein im Kampf geborener Knopf bleibt nackt bis
zum Kampfende.

## Aussehen

Symbol mit Zuschnitt, 1-px-Rand (Schwächungen in der Dispel-Farbe,
Verzauberungen violett), Zähler unten rechts, Restzeit unter dem Symbol
(rot unter 10 s, Eimer-Text). Optionen: Symbolgröße, Abstand, Symbole je
Reihe, Schriftgröße, Wachstum links/rechts, Sortierung, eigene zuerst,
Restzeit an/aus. Zwei Mover-Kästen (`auras.buffs`, `auras.debuffs`).

## Spielfenster

BuffFrame, DebuffFrame (und TemporaryEnchantFrame, falls vorhanden) wandern
unter einen versteckten Schattenrahmen; Abschalten hängt sie zurück.

## Prüfliste im Spiel

- Modul einschalten: eigene Reihen erscheinen, die des Spiels verschwinden;
  Rechtsklick bricht eine Stärkung ab (außerhalb des Kampfes und im Kampf).
- Waffenöl/Gift: Knopf mit Waffensymbol und Restzeit; Rechtsklick entfernt.
- Im Kampf: neue Auren erscheinen (nackt, falls im Kampf geboren), nach dem
  Kampf eingekleidet; kein Fehler „geschützte Funktion".
- Optionen: Größe/Abstand/Reihe live außerhalb des Kampfes; im Kampf
  verzögert bis Kampfende.
- Edit Mode: beide Kästen ziehbar; Position bleibt nach /reload.
- Modul aus: Fenster des Spiels wieder da.

## Nachtrag Gegenpruefung (12.09.)

- Rechtsklick war nie registriert (SecureActionButtonTemplate registriert keine Klicks) → `RegisterForClicks("RightButtonUp")` beim Einkleiden.
- Einschalten im Kampf: der Mover-Anker ist ein geschuetzter Schreibzugriff → laeuft jetzt in `applyAll` mit, also erst nach dem Kampf.
- Kein `SetSize` auf die Kopfzeile (sie misst sich selbst bei jedem Update); im Kampf geborene Knoepfe setzen `pending`, der Regen-Lauf gibt ihnen die Groesse.
- UnlockMode verdrahtet den BUFFS-Kasten nicht, solange das Modul an ist.
- Unverifiziert: Taint auf `index`/`filter` durch den unsicheren Attribut-Schreibzugriff (bei ADDON_ACTION_BLOCKED im Kampf hier suchen); `SecureAuraHeaderTemplate` als versteckt angenommen.
