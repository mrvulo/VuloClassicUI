# Combat Meter Teil 4: Bedrohung, Kampfverlauf, Chat-Bericht

Stand 12.09.2026. Baut auf Teil 1–3 (v1.60.x) auf: `Modules/Meter.lua`
(Engine), `Modules/MeterWindow.lua` (Fenster), `Modules/MeterOptions.lua`.

## Ziel

Drei Dinge, die jedem Meter fehlen, bis sie da sind:

1. **Bedrohungs-Modus** — ein neunter Modus, der die Bedrohungsliste des
   aktuellen Ziels live zeigt (Tank oben, jeder andere in Prozent des Tanks).
2. **Kampfverlauf** — die letzten N beendeten Kämpfe bleiben wählbar; ein
   Fenster kann einen vergangenen Kampf zeigen, ohne die Gesamtsumme zu
   bemühen.
3. **Chat-Bericht** — Top N des angezeigten Fensters in einen Kanal senden
   (Sagen, Gruppe, Schlachtzug, Gilde, Offizier, Flüstern).

## Bedrohungs-Modus

- Modus-Schlüssel `threat`. Nur vorhanden, wenn `UnitDetailedThreatSituation`
  existiert (`Meter.HAS_THREAT`); ein gespeichertes Fenster mit `threat` auf
  einem Client ohne API fällt wie jeder unbekannte Modus auf `damage`.
- Datenquelle ist NICHT das Kampfprotokoll, sondern ein Schnappschuss
  `Meter:ThreatSnapshot()`: für jede Rostereinheit und deren Begleiter
  `UnitDetailedThreatSituation(unit, "target")`. Ergebnis liegt in einem
  wiederverwendeten Segment-Tisch `threatSeg` (`title` = Zielname,
  `players[guid] = { name, class, threat, pct, status, tanking }`).
  `threat` = Rohwert / 100 (die API liefert Hundertstel), `pct` = Prozent
  relativ zum Tank (rawPercentage). Begleiter erscheinen als eigene Zeile in
  der Klassenfarbe des Besitzers. Einträge ohne Bedrohung (nil) fehlen.
- Segment (aktuell / gesamt / Verlauf) ist im Bedrohungs-Modus bedeutungslos;
  Titel: `Bedrohung · <Zielname>` oder `Bedrohung · Kein Ziel`.
- Rechter Text immer `Wert (Prozent)`, unabhängig von den Klammer-Schaltern.
  Tooltip: Bedrohung, Prozent des Tanks, Status (Tank / über dem Tank / sicher).
- Aktualisierung nur, solange mindestens ein gebundenes Fenster im
  Bedrohungs-Modus steht: dann sind `UNIT_THREAT_LIST_UPDATE` (nur wenn die
  Einheit unser Ziel ist), `UNIT_THREAT_SITUATION_UPDATE` und
  `PLAYER_TARGET_CHANGED` registriert (direkt über `ns:RegisterEvent`, wieder
  abgemeldet, sobald kein Fenster mehr den Modus hat oder das Modul abschaltet).
  Ereignisse setzen nur ein Flag; ein 0,25-s-Sammler macht Schnappschuss und
  Neuzeichnen. `PLAYER_TARGET_CHANGED` zeichnet sofort.
- Der Bedrohungs-Modus nimmt am Fenster-Ticker nicht teil (der läuft nur im
  Kampf; Bedrohung kommt über die eigenen Ereignisse).

## Kampfverlauf

- Engine hält `history` (neuester zuerst), Kappe `mod.db.historySize`
  (Standard 10, Regler 0–30; 0 = kein Verlauf). `closeSegment` legt den
  beendeten Kampf vorn ab und kürzt. `Meter:Reset()` leert den Verlauf.
  Nicht persistiert (nur die Gesamtsumme überlebt /reload — wie bisher).
- `Meter:GetHistory()`, `Meter:HistoryIndex(seg)` (nil = nicht mehr im
  Verlauf). `Meter:GetSegment(which)` nimmt zusätzlich einen Segment-Tisch:
  ist er noch im Verlauf, kommt er zurück, sonst `current or last`.
- Fenster: `w.segment` darf ein Segment-Tisch sein (Sitzungszustand;
  `w.db.segment` bleibt `current`/`overall`, weil der Verlauf einen /reload
  nicht überlebt). Fällt der Tisch aus dem Verlauf, springt das Fenster still
  auf `w.db.segment` zurück (Prüfung in `refresh`).
- Titelmenü: unter „Aktueller Kampf / Gesamt" ein Untermenü „Vorherige
  Kämpfe" (nur wenn Verlauf nicht leer): je Eintrag `<Bossname oder Kampf n>
  (m:ss)`, Häkchen am gewählten. Ein neu beginnender Kampf lässt ein auf
  einen alten Kampf gestelltes Fenster dort stehen.
- Optionsseite: Regler „Kämpfe im Verlauf" unter Fenster.

## Chat-Bericht

- Titelmenü-Eintrag „Bericht" mit Untermenü: Sagen, Gruppe, Schlachtzug,
  Gilde, Offizier, Flüstern an… Gruppe/Schlachtzug/Gilde/Offizier sind
  ausgegraut, wenn nicht verfügbar (`IsInGroup`, `IsInRaid`, `IsInGuild`,
  `CanEditOfficerNote` als Näherung für Offizierschat: nein — der Kanal
  OFFICER geht auch ohne Notizrecht; ausgegraut nur ohne Gilde).
- Inhalt aus dem Fensterzustand (`w.order`/`w.vals`, komplett, nicht nur die
  sichtbaren Zeilen): Kopfzeile `VuloClassicUI · <Modus> · <Segment> (m:ss)`,
  dann `mod.db.reportRows` Zeilen (Standard 10, Regler 3–25) im Format
  `n. Name  Wert (Wert/s, Anteil%)`; Zählmodi `n. Name  Zahl`; Bedrohung
  `n. Name  Wert (Prozent%)`. Zahlen über `short()`.
- Versand mit `SendChatMessage(text, kanal, nil, ziel)`, eine Nachricht je
  Zeile; Flüstern öffnet ein StaticPopup mit Namensfeld
  (`VCUI_METER_WHISPER`, Muster wie das Umbenennen im Cooldown Manager).
- Ein leeres Fenster berichtet nichts (nur die Kopfzeile fällt weg, es wird
  gar nichts gesendet).
- Optionsseite: Regler „Zeilen im Bericht" unter neuem Abschnitt „Bericht".

## Sprachschlüssel (neu, deDE zuerst, dann acht Sprachen)

Threat, No target, Tanking, Above the tank, Safe, Percent of tank,
Previous fights, Fight %d, Report, Say, Party, Raid, Officer, Whisper to...,
Fights to keep, Rows in report, Whisper the report to whom?

Vorhanden und wiederverwendet: Guild, Whisper, Target, Reset, Unknown.

## Prüfliste im Spiel

- Übungspuppe anvisieren, Fenster auf Bedrohung: eigene Zeile 100 %,
  Begleiter als eigene Zeile; Ziel wechseln → Titel folgt sofort; kein Ziel →
  „Kein Ziel", keine Zeilen. Fünfergruppe: Tank oben, Prozentwerte
  plausibel, kein Ruckeln (Sammler).
- Zwei Kämpfe an der Puppe: Untermenü „Vorherige Kämpfe" zeigt beide mit
  Dauer; Fenster auf Kampf 2 stellen, dritten Kampf beginnen → Fenster bleibt
  auf Kampf 2; Verlauf auf 1 stellen → Fenster springt auf den aktuellen.
- Bericht an Gruppe an der Puppe (solo → Gruppe ausgegraut, Sagen geht);
  Flüstern an sich selbst; Zeilenanzahl folgt dem Regler; leeres Fenster sendet
  nichts.
