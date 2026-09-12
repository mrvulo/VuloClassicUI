# Fernkampf-Balken im Swing Timer

Stand 12.09.2026. Verabredet am 09.08. (Notiz „Fernkampf-Balken"), gebaut in
`Core/SwingTracker.lua` (Uhr) und `Modules/SwingTimer.lua` (Balken).

## Uhr (SwingTracker)

- Dritter Zustand `ra` neben Haupt- und Schildhand; `ns:GetSwing("ranged")`,
  `ns:SwingRemaining("ranged")`, `ns:HasRangedWeapon()`.
- Geschwindigkeit über `UnitRangedDamage("player")` (nil ohne Fernkampfwaffe).
- Schuss = `UNIT_SPELLCAST_SUCCEEDED` auf Auto-Schuss (75) oder Zauberstab-
  Schuss (5019): Uhr auf volle Waffengeschwindigkeit. `START_AUTOREPEAT_SPELL`
  startet nichts (der erste Schuss meldet sich selbst), `STOP_AUTOREPEAT_SPELL`
  beendet die Uhr. Halter werden mit hand = "ranged" benachrichtigt; die
  Paladin-Konsumenten filtern auf "mainhand".
- Zielfenster `AIM_WINDOW = 0,7 s` (`ns.RANGED_AIM_WINDOW`): Bewegung
  (`GetUnitSpeed`) oder ein laufender Zauber (`UnitCastingInfo`) innerhalb des
  Fensters hält die Uhr an dessen Kante (`holdRanged`, gelesen auf dem
  Konsumentenpfad, nie per eigenem Ereignis). Hast (`UNIT_RANGEDDAMAGE`)
  skaliert den Rest wie bei den Nahkampfhänden, aber NICHT innerhalb des
  Fensters. Veraltet nach 2 s wie die anderen Hände.
- Nicht übernommen (bewusst): Hast über Aura-Namen, Abfrage in jedem Bild,
  vorhergesagte Wirkbalken für Zielen/Mehrfachschuss (Stufe 2).

## Balken (SwingTimer)

- Dritter Balken „FK" unter Haupt-/Schildhand, sichtbar mit
  `showRanged` (Standard an) und angelegter Fernkampfwaffe; Vorschau 2,9 s.
- `showAimWindow` (Standard an) hellt das letzte Stück des Balkens auf
  (Breite = Fenster / Waffengeschwindigkeit).
- Das Modul lässt jetzt auch Jäger und Zauberstab-Träger zu: die Sperre greift
  nur noch, wenn weder Nahkampf-Spec noch Fernkampfwaffe da ist. Der Balken
  bleibt ab Werk AUS (Nutzerwunsch für den ganzen Swing Timer).

## Prüfliste im Spiel

- Jäger an der Puppe: Auto-Schuss an → Balken läuft, füllt sich je Schuss neu;
  im hellen Fenster loslaufen → Balken hält an der Kante, stehen bleiben →
  Schuss kommt; Zielschuss im Fenster → hält bis Zauberende.
- Auto-Schuss aus → Balken verschwindet (bei „nur beim Angreifen").
- Bogen ablegen → Balken weg, anlegen → wieder da; Zauberstab-Priester sieht den
  Balken beim Schießen.
- Krieger ohne Fernkampfwaffe: nichts verändert (kein dritter Balken).

## Nachtrag aus der Gegenprüfung (12.09.)

- Engine schließt den laufenden Kampf bei `PLAYER_LOGOUT`, sonst fehlte der Gesamtsumme die Dauer dieses Kampfes (Meter).
- Sperre beim Kaltstart: Jäger oder ein Gegenstand im Fernkampf-Platz gelten als „nicht beurteilen“, weil `UnitRangedDamage` bei ADDON_LOADED noch 0 melden kann.
- Kanalisierung (`UnitChannelInfo`) hält die Uhr wie ein Zauber; Hast-Gegenprobe alle 0,1 s auf dem Konsumentenpfad.
- Nahkampfbalken bei Jägern/Zauberstab-Trägern nur, solange ein Schwung läuft; Balken stapeln sich lückenlos.
- Offen am Client: ob das Zielfenster 0,5 s oder 0,7 s misst (Vorlage sagte 0,7; Zauberzeit von Auto-Schuss ist 0,5).
