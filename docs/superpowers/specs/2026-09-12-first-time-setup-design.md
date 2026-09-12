# Ersteinrichtung (First-time setup)

Stand 12.09.2026. Neue Datei `UI/Setup.lua`, Einhängungen in `Core/Init.lua`,
`Core/Database.lua`, `Modules/GlobalSettings.lua`.

## Ziel

Ein neuer Nutzer sieht beim ersten Login ein Fenster mit drei Schritten und
ist danach fertig, ohne 22 Kapseln unter Allgemein zu lesen: Vorlage wählen,
Schrift und Skalierung setzen, neu laden. Jederzeit erneut erreichbar über
`/vcui setup` und einen Knopf in den Globalen Einstellungen.

## Wann es erscheint

- `ns.defaults.global.setupDone = true` (Bestand sieht nie ein Fenster).
  `InitDB` merkt sich, ob `VuloClassicUIDB` beim Laden noch fehlte; nur dann
  wird `global.setupDone = false` gesetzt.
- `PLAYER_LOGIN` → `ns:MaybeShowSetup()`: eine Sekunde später, nicht im Kampf,
  nur wenn `setupDone == false`. Überspringen, Fertig und Später setzen die
  Marke auf `true`. `ns:ShowSetup()` öffnet ohne Bedingung.

## Vorlagen (Schritt 1)

Vier Karten, eine ausgewählt (Akzentrand). Eine Vorlage ist eine Liste von
Modulen, die AN oder AUS gehen; alles andere behält den registrierten
Standard (`mod.defaults.enabled`). Standard setzt also die Union aller
Vorlagen-Schlüssel auf ihren Standard zurück, damit ein zweiter Durchlauf
eine frühere Wahl aufhebt.

- **Standard** — alles wie ausgeliefert.
- **Minimal** — nur der Anstrich. AUS: meter, cooldownmanager, actionring,
  combattext, reminders, trackbars, powerbar, actionbars, nameplates,
  playercastbar, cooldownpulse, fontbars, swingtimer, vtmanadisplay,
  arenaframes, lazyvulo, vulfishing, disenchantqueue, goldtracker, trinkets,
  vullfg, queuetimer, autoitembuy, loadouts.
- **Heiler** — Standard plus AN: powerbar, reminders, combattext; das erste
  Meter-Fenster steht auf Heilung.
- **PvP** — Standard plus AN: arenaframes, trinkets, powerbar, reminders,
  combattext; das erste Meter-Fenster auf Schaden.

Schreibweise: Modulzustand lebt je Charakter (`CharDB.modEnabled`) mit dem
Profilstandard dahinter. Die Vorlage schreibt `mod.db.enabled` im AKTIVEN
Profil und im Profil „Default" (der Saat für neue Klassen) und löscht die
Charakter-Übersteuerung des Schlüssels, damit die Wahl für die Klasse und
für später angelegte Klassen gilt; der Saat-Eintrag wird angelegt, weil die
Abmelde-Bereinigung sie leer hält. Das Meter: nur der Modus des ERSTEN Fensters folgt der Vorlage (Standard und
Minimal setzen ihn auf Schaden), Liste und Positionen bleiben. Die Vorlage
wird erst am Ende geschrieben (Jetzt neu laden / Später), nie beim Weiter;
Überspringen, X und ESC schreiben nichts. Die gewählte Vorlage steht danach
in `global.setupTemplate` und ist beim nächsten Aufruf vorausgewählt.
Nichts wird live umgeschaltet; der Abschluss lädt neu.

## Aussehen (Schritt 2)

Globale Schriftart (Klappmenü aus `ns.MediaFontValues`), Konturmodus
(Klappmenü), UI-Skalierung (Regler 0,40–1,15, wirkt sofort) und die drei
Knöpfe Pixelgenau / 1080p / 1440p. Nutzt die Helfer aus GlobalSettings, die
dafür als `ns.ApplyGlobalFont`, `ns.ApplyUIScale`, `ns.PixelPerfectScale`
freigegeben werden.

## Abschluss (Schritt 3)

Zusammenfassung (gewählte Vorlage, Schrift, Skalierung), Hinweis auf
`/vcui setup`, Knöpfe „Jetzt neu laden" (ReloadUI) und „Später".

## Fußzeile

Links „Überspringen" (Schritt 1, schließt ohne Änderung, Marke gesetzt),
„Zurück", rechts „Weiter" / „Fertig". ESC schließt wie Später.

## Prüfliste

- Frisches Konto (SavedVariables der Addon-Datei umbenennen): Fenster kommt
  eine Sekunde nach Login; Bestandskonto: kein Fenster.
- Minimal wählen, neu laden: HUD-Module aus, Anstrich an; `/vcui setup`,
  Standard wählen, neu laden: alles wieder wie ausgeliefert.
- Heiler: erstes Meter-Fenster zeigt Heilung; zweite Klasse einloggen: erbt
  die Vorlage (Default-Saat).
- Schrift und Skalierung: Regler wirkt live, nach Neuladen bleibt beides.
- Überspringen: nichts geändert, Fenster kommt nicht wieder.
