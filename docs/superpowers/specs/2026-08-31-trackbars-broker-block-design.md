# Trackbars: Broker-Plugin-Block (LibDataBroker-Anzeige)

Stand 31.08.2026, Design vom Nutzer abgenommen (Ansatz A: Bibliothek einbetten).

## Ziel

Ein neuer Trackbars-Blocktyp „Broker-Plugin": zeigt ein beliebiges
LibDataBroker-1.1-Datenobjekt (registriert von Fremd-Addons) als nativen
Block — Symbol, Text, Klicks und Tooltip durchgereicht. Zwei Passform-Regler:
Farbcodes entfernen und maximale Breite. Mehrere Broker-Blöcke je Leiste sind
möglich (je Block ein Plugin, über die vorhandenen `b.settings`).

## Lieferumfang

1. **`Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua`** (neu, gemeinfrei,
   Original-Wortlaut Minor 4). Benötigt LibStub + CallbackHandler-1.0 — beide
   liegen schon in `Libs/` und stehen im TOC davor. TOC-Eintrag in BEIDEN
   TOC-Dateien direkt nach CallbackHandler. Fremd-Addons mit eigener Kopie
   teilen sich per LibStub-Versionsvergleich dieselbe Instanz.
2. **`Modules/TrackbarsBlocks.lua`**: `addType("broker", …)` mit EIGENER
   Fabrik (nicht `MakeTextBlock` — das Symbol ist dynamisch und die Quelle
   sind Callbacks statt Herzschlag/Events).
3. **`Modules/TrackbarsOptions.lua`**: Einstellungs-Widgets für den Typ
   „broker" im vorhandenen Muster (Widgets je Blocktyp, Schlüssel spiegeln
   `BLOCK_DEFAULTS`).
4. **Locales ×9**: ~6 neue Schlüssel (Typ-Beschriftung, Plugin, Hinweis
   „keine gefunden", Farbcodes entfernen, Maximale Breite, 0-=-automatisch-
   Tooltip). Vorhandene Schlüssel werden wiederverwendet, wo es sie gibt —
   auch in der TOTEN Schlüsselliste nachsehen (Lehre v1.58.3).

## Blockverhalten

- **Standardwerte** `BLOCK_DEFAULTS.broker = { plugin = "", stripColors = false, maxWidth = 0 }`.
- **Aufbau** wie die Textblöcke: FontString rechts, Symbol links davon
  (Größe 0,62 × Leistendicke), Leisten-Schrift über `UI.FontFor("trackbars")`,
  Blockfarbe färbt den Text NICHT um, wenn der Text eigene Farbcodes trägt —
  die Grundfarbe kommt aus `blockColor(b)` wie überall, Farbcodes des Plugins
  gewinnen im String.
- **Textquelle**: `obj.text`, sonst `obj.label`, sonst der Plugin-Name.
- **Symbol**: `obj.icon` (Pfad oder Datei-Kennung, `SetTexture` nimmt beides);
  `obj.iconCoords` wird per `SetTexCoord` angewendet, wenn gesetzt; ohne
  `icon` wird die Textur versteckt und misst 0.
- **stripColors**: entfernt `|cXXXXXXXX`- und `|r`-Sequenzen aus dem
  angezeigten Text (gsub), sonst nichts.
- **maxWidth** (> 0): kappt die TEXTbreite auf den Wert (`fs:SetWidth`,
  Überstand wird geklippt); `GetAutoLength` meldet min(natürlich, maxWidth)
  plus Symbol. 0 = natürliche Breite (`fs:SetWidth(0)`).
- **Aktualisierung**: KEIN Herzschlag, kein Polling. Callback
  `LibDataBroker_AttributeChanged_<name>` → Refresh (Text/Symbol/Breite).
  Callback `LibDataBroker_DataObjectCreated` → Refresh, damit ein
  konfiguriertes, aber erst später ladendes Plugin anspringt; bis dahin zeigt
  der Block den Plugin-Namen ausgegraut. Instanztabelle ist das
  Callback-Self; `Disable()` ruft `UnregisterAllCallbacks(inst)`.
- **Klick**: `slot`-OnMouseUp → `pcall(obj.OnClick, slot, button)`, nur wenn
  Funktion vorhanden.
- **Tooltip** (Broker-Konvention, in dieser Reihenfolge):
  1. `obj.OnTooltipShow`: GameTooltip am Slot verankern (`SetOwner` mit
     `ANCHOR_TOP` — dieselbe Verankerung wie JEDER andere Trackbars-Block;
     der GameTooltip klemmt sich selbst an den Bildschirm),
     `pcall(obj.OnTooltipShow, GameTooltip)`, `Show`.
  2. sonst `obj.OnEnter`/`obj.OnLeave`: `pcall(obj.OnEnter, slot)` bzw. Leave.
  3. sonst: GameTooltip mit dem Plugin-Namen.
  OnLeave versteckt den GameTooltip immer zusätzlich.
- **Fehlerkapselung**: JEDER Aufruf in Plugin-Code (OnClick, OnTooltipShow,
  OnEnter, OnLeave) läuft durch `pcall` — ein kaputtes Fremd-Plugin darf die
  Leiste nicht mitreißen. Fehler still schlucken (kein Chat-Spam auf Hover).

## Einstellungs-Widgets (Optionsseite)

- **Klappmenü „Plugin"**: alphabetische Liste aller registrierten
  Datenobjekte (`ldb:DataObjectIterator()`); das konfigurierte, aber nicht
  registrierte Plugin erscheint zusätzlich ausgegraut mit Vermerk; leeres
  Register → eine einzelne, nicht wählbare Hinweiszeile („keine
  Broker-Plugins gefunden") — der Blocktyp bleibt IMMER in der Typenliste
  (Nutzerentscheid: sichtbar mit Hinweis).
- **Schalter „Farbcodes entfernen"** (stripColors, Standard aus).
- **Regler „Maximale Breite"** 0–400, Schritt 10, Tooltip „0 = automatisch"
  in der Formulierung der vorhandenen 0-=-Zeilen.

## Bewusst NICHT gebaut (YAGNI)

Minimap-Knöpfe schlucken, automatische Blöcke für jedes Plugin,
Tablet-/Qtip-Tooltip-Bibliotheken, Label+Text kombiniert, Symbol rechts,
eigene Farbübersteuerung je Plugin.

## Prüfliste (Spiel)

Block ohne Plugin-Addon anlegen (Hinweis im Klappmenü), ein Broker-Addon
installieren → Plugin wählen, Text/Symbol erscheinen und aktualisieren sich
ohne /reload; Klick und Tooltip am Plugin; stripColors an/aus; maxWidth
kappt; Leiste aus/an (Callbacks sauber ab-/anmelden); /reload mit
konfiguriertem, aber fehlendem Plugin → ausgegrauter Name, kein Fehler.
