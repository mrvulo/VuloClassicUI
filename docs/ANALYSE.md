# VuloClassicUI – Architektur-Vergleich mit DragonflightUI, Konsolidierungsplan & Edit-Mode-Design

> Erstellt aus einer Tiefenanalyse beider Addons (7 Lese-Agents). Stand: 2026-06-28.

---

## 1. Architektur-Vergleich auf einen Blick

| Thema | DragonflightUI | VuloClassicUI |
|---|---|---|
| Framework | Ace3 (AceAddon/AceDB/AceConfig/AceLocale/AceSerializer) | Eigenes, leichtes `ns`-Framework (Ace-Nachbau, 0 Ace-Abhängigkeit) |
| Modul-System | `DF:NewModule` + Shared-Mixin `DragonflightUIModulesMixin` | `ns:RegisterModule(key, def)` mit `OnEnable/OnDisable/GetOptions` |
| Datei-Layout | **1 Ordner pro Modul** + `Load.xml` + **1 `.mixin.lua` pro Frame** | Flach: meist 1 Datei pro Modul |
| Lua-Dateien | **~120** (z. B. Unitframe = 12 Lua) | **~73** (70 in Modules/, 3 in Trinkets/) |
| DB | 1 AceDB, pro Modul ein Namespace | 2 SavedVars: `…DB` (Profile/Settings) + `…CharDB` (nur Enable pro Char) |
| Optionen | Ace-Options-Tabellen (zwei Systeme parallel) | Deklaratives DSL `{type="toggle", get, set, subOptions}` + eigener OptionsBuilder mit Widget-Pooling & 2-Spalten-Cards |
| Profile | komplett AceDB + Import/Export (Serialize+Deflate) | Eigenes Profil-System + **Profil-pro-Klasse-Zuweisung** |
| Edit Mode | Vollausgebautes, eigenes HUD (1028+1653+604 Z.) | Basis-Mover (`Core/Mover.lua`, 296 Z.) + `UnlockMode`-Frontbutton |

### Kern-Erkenntnis
**DFUI hat MEHR Dateien als ihr, nicht weniger.** Sein „1 Ordner + 1 Mixin pro Frame"-Muster ist sauber, treibt die Dateizahl aber *nach oben* (Unitframe allein = 12 Lua). Würdet ihr DFUIs Struktur 1:1 kopieren, hättet ihr **mehr** Luas, nicht weniger. Euer „zu viele Luas"-Problem löst man also **nicht** durch Nachahmen von DFUI, sondern durch gezieltes Zusammenführen eurer eigenen Mikro-Dateien (Abschnitt 2).

VuloClassicUI ist architektonisch **sehr ordentlich** – pcall-Isolation pro Modul, kluger „Enable-pro-Char / Settings-geteilt"-Split, Live-Locale, eigene Widgets gegen buggy Classic-APIs. Was DFUI klar besser kann, ist **nur** der Edit Mode (Abschnitt 3).

---

## 2. Konsolidierungsplan: ~73 → ~56 Lua-Dateien

Euer Modulsystem koppelt rein über `ns:RegisterModule` (nicht über Dateinamen). Mehrere `RegisterModule`-Aufrufe dürfen in **einer** Datei stehen → Zusammenführen ist sehr risikoarm. Einzige echte Falle: **Ladereihenfolge** (Container/Pages nach ihren Mitgliedern; Daten-Plugins nach ihrer Engine) – beim Mergen in eine Datei automatisch durch Textreihenfolge erfüllt. **Beide TOCs synchron halten.**

| # | Zusammenführung | Aus → Nach | Aufwand / Risiko | Gespart |
|---|---|---|---|---|
| 1 | Alle `Fix*.lua` (×6) + Container → `Bugfixes.lua` | 7 → 1 | niedrig / niedrig | **6** |
| 2 | `Modules/Arena/` (×7, = EIN Modul `arenaframes`) → `Arena.lua` | 7 → 1 | mittel / niedrig | **6** |
| 3 | `CharacterPanel_Impl.lua` → `CharacterPanel.lua` | 2 → 1 | niedrig / niedrig | **1** |
| 4 | `Classes/Priest.lua` + `Classes/Warlock.lua` (reine DoT-Daten) → ans Ende `VTManaDisplay.lua` | 3 → 1* | niedrig / niedrig | **2** |
| 5 | `QoL.lua` + `Pages.lua` (reine Sidebar-Layout-Dateien) → 1 | 2 → 1 | niedrig / niedrig | **1** |
| 6 | `GoldTracker.lua` + `AutoItemBuy.lua` → `GoldVendors.lua` | 2 → 1 | niedrig / niedrig | **1** |
| 7 | (optional) `VTData.lua` → `VulTraining.lua` | 2 → 1 | niedrig / niedrig | **1** |

\* `Classes/Shaman.lua` (38 KB, vollwertige Totembar) bleibt getrennt → `Classes/`-Ordner verschwindet trotzdem.

**Ergebnis: ~17–18 Dateien weniger (~25 %), zwei Unterordner (`Arena/`, `Classes/`) verschwinden – ohne ein Feature oder einen Sidebar-Eintrag zu verlieren.**

### Bewusst NICHT anfassen (Trennung ist hier ein Vorteil)
- Große Einzelfeatures: `Loadouts.lua` (74 KB), `CooldownManager.lua` (56 KB), `TooltipIDs.lua` (40 KB), `ProfessionWindow.lua` (37 KB), `PlayerCastbar.lua` (37 KB), `CombatText.lua`, `ButtonSkin.lua`, `SwingTimer.lua`, `CooldownPulse.lua`.
- `Trinkets/*` – eingebettete Fremd-Engine, bei Updates 1:1 austauschbar halten.
- `FlightTimesDB.lua` – reine generierte Datentabelle (Daten/Logik-Trennung korrekt).
- `VulTraining/Classes/*` (9 Klassen) – laden nur die eigene Klasse (`if currentClass ~= "MAGE" then return end`); ein Merge zu ~90 KB würde bei jedem Spieler ALLE Klassen parsen.
- `MiscQoL.lua` (51 KB) ist bereits selbst eine Sammeldatei. **Kein Overlap mit `QoL.lua`** (das ist nur der 909-B-Container-Aufruf).

### Empfohlene Reihenfolge
1→4→3→5→6 (alles trivial), dann 2 (Arena, größter Einzelgewinn, mit In-Game-Test: Arena betreten).

---

## 3. Edit Mode – „wie DFUI, nur besser und in unserem Stil"

### 3.0 Leitidee
Ein einziges globales **Edit Mode-HUD** im lila EUI-Stil, das ein **echtes Superset** des heutigen `ns:CreateMover`/`ns:SetMoversEditMode` ist – die guten DFUI-Ideen übernehmen, die schlechten weglassen.

**Von DFUI übernehmen (das Gute):**
- **Overlay = Kind des Ziel-Frames**, full-bleed verankert → trackt Größe/Position automatisch, null Buchhaltung.
- **Auto-generiertes Pro-Frame-Settings-Panel** aus EINER Quelle (bei uns: unser deklaratives Item-DSL + `Widgets.lua`).
- **Grid-Overlay** (gepoolte Lines, DPI-genau via `PixelUtil`), lila Mittelkreuz.
- **Linke-Alt-Cycle** durch gestapelte Frames (löst „Frame liegt unter anderem").
- **Combat-Auto-Exit** (`PLAYER_REGEN_DISABLED/ENABLED`).
- Skalierungs-bewusstes Grid-Snapping.
- „Layouts" über ein Dropdown.

**Von DFUI weglassen (das Schlechte):**
- Die **1654 Zeilen handgebauten Fake-Preview-Frames** → wir zeigen stattdessen den **echten** Frame kurz an / füllen ihn fake.
- **Globale Namens-Kollisionen** (alle Options-Frames hießen `DragonflightUIEditModeFrame`).
- **Drei überlappende State-Bits** (`advanced`/`EditModeActive`/`DFEditMode`).
- Das **„alles auf CENTER/UIParent umschreiben"**-Modell → wir behalten den **gewählten Anker** jedes Frames.
- LibEditModeOverride-Kopplung.

**Harte Grenze (wichtig):** Addons dürfen Blizzards Edit Mode **nicht** selbst öffnen (Taint über `TargetUnit`/`SpellStopCasting` → FORBIDDEN). Unser HUD ist daher **voll eigenständig**; wir *spiegeln* Blizzards Edit Mode nur dort, wo der Client einen hat (Anniversary) – genau wie `ns:HookBlizzardEditMode` heute.

**DFUI-Schwäche, die wir besser machen:** DFUI hat **keine** Element-zu-Element-Magnetismus und **kein** Pfeiltasten-Nudging (beides auskommentiert/fehlt). Beides bauen wir ein → unser Alleinstellungsmerkmal.

### 3.1 Datenmodell
Normalisierter „Edit-Record" pro Frame (behält den Anker, anders als DFUI):
```lua
{ point="CENTER", relPoint="CENTER", relTo="UIParent", x=0, y=0, scale=1.0 }
```
**Layouts** = benannte Positions-Sätze im Profil-DB (reisen mit dem Profil):
```lua
ns.db.profile.editmode = {
  activeLayout = "Default",
  layouts = {
    ["Default"] = {
      grid   = { show=false, size=32, snap=true, snapEdges=true },
      frames = { ["powerbar"]={point="CENTER",relTo="UIParent",x=0,y=-180,scale=1}, … },
    },
  },
}
```
Live-Position bleibt zusätzlich in der Modul-DB (`mod.db`), damit bestehender Code & normale Options-Seiten unverändert weiterlaufen. Beim Layout-Wechsel/Login wird der Record in `mod.db` kopiert + `applyPos` aufgerufen. Beim Drag-Stop wird in **beide** geschrieben.

**Migration** (`ns:MigrateEditMode()` einmalig in `InitDB`): bestehende `db.x/db.y` → automatisch in den `Default`-Layout-Record synthetisiert. Ad-hoc-Module liefern einen 3-Zeilen-`migrate`-Adapter. Non-destruktiv (via `ApplyDefaults`), mehrfach ausführbar.

### 3.2 Registrierungs-API (einmal andocken)
EINE neue Funktion. Alte `ns:CreateMover`-Aufrufer brauchen **null** Änderung (Shim registriert sie automatisch).
```lua
ns:RegisterEditFrame(key, {
  frame    = myFrame,          -- echtes Frame (Pflicht)
  label    = "POWER BAR",      -- Overlay + Panel (Pflicht)
  scope    = "cooldownmanager",-- optionaler Sub-Scope (/cdedit)
  db       = mod.db,           -- bequem: Engine nutzt db.editPos
  get/set  = function …,       -- alternativ: eigener Record-Zugriff
  default  = { point="CENTER", relTo="UIParent", x=0, y=-180, scale=1 },
  migrate  = function(db) return record end,  -- nur Ad-hoc-Module
  applyPos, onMove, editPreview,              -- Verhaltens-Hooks
  scalable = true, minWidth=140, minHeight=44,
  editPanel = function() return { {type="toggle", …}, … } end, -- Modul-eigene Extra-Optionen
})
```
`ns:CreateMover(target, opts)` wird zum dünnen Wrapper darüber → **alle 8 bestehenden Call-Sites laufen unverändert**. Die ~7 Ad-hoc-Module (eigenes `StartMoving`) wandern auf einen `RegisterEditFrame`-Aufruf + Mini-`migrate` und löschen dabei ihren Duplikat-Code (v. a. CombatText eigenes `OnKeyDown`).

### 3.3 Das HUD (neue Datei `UI/EditMode.lua`)
Komplett aus euren vorhandenen Helpern (`StyleBackdrop`, `CreateShadow`, `SetGradient`, `Font`, `CreateButton/Dropdown/Slider/Toggle/EditBox`), Farben aus `ns.COLORS.accent`.
- **Dim-Overlay**: Vollbild `0,0,0,0.35`, fängt Hintergrund-Klicks (Deselect).
- **Grid**: gepoolte Lines, lila Mittelkreuz, via `PixelUtil` scharf, Rebuild auf `DISPLAY_SIZE_CHANGED`/`UI_SCALE_CHANGED`.
- **Toolbar** (oben mittig, ziehbar): **Exit** (Akzent) · **Grid**-Toggle · **Snap**-Toggle · **Layouts**-Dropdown (+ Neu/Kopieren/Umbenennen/Löschen via `ns:ShowPopupMenu`) · **Alles zurücksetzen** (StaticPopup-Bestätigung) · Titelstreifen „EDIT MODE" mit Akzent-Gradient.
- **Pro-Frame-Panel** (rechts angedockt, bei Auswahl): **generiert**, nicht handgebaut – X/Y-EditBox, Scale-Slider, Anker-Dropdown, „Dieses Frame zurücksetzen" + die `editPanel()`-Items des Moduls. Gepoolt/wiederverwendet (keine Namens-Kollision).

### 3.4 Auswahl, Snapping, Tastatur
- **Auswahl**: Linksklick → `ns:SelectEditFrame(mover)`; Overlay-Zustände idle/highlighted/selected im Akzent-Lila. Hintergrund-Klick/Esc = Deselect.
- **Grid-Snap**: `floor((v+g/2)/g)*g` mit `g = gridSize / GetEffectiveScale()` (scale-aware), live beim Ziehen + beim Loslassen, Master-Toggle „Snap".
- **Magnetismus (unser Plus)**: `ns:ComputeMagnetSnap` – innerhalb ~8px an Kanten/Mitte anderer Edit-Frames + UIParent-Mittellinien/Screen-Kanten einrasten; 1px-Akzent-Hilfslinie zeigen, dann ausblenden.
- **Scale zentral**: `target:SetScale(record.scale)` in `applyPos`; Slider + Ctrl+Mausrad. Ersetzt LazyVulo/Arena-Eigenlösungen.
- **Tastatur (eine Implementierung)**: Pfeile 1px / Shift 5px / Ctrl+Pfeil = Grid-Schritt, getrieben von `ns._selectedMover`. CombatText-Duplikat löschen.
- **Linke-Alt-Cycle**: throttled OnUpdate sammelt Movers unter dem Cursor; bei >1 Tag „(N) Frames hier — Alt zum Wechseln" + Raise/Lower.
- **Combat**: `PLAYER_REGEN_DISABLED` Auto-Exit (merkt Zustand), `PLAYER_REGEN_ENABLED` Restore; alle geschützten Calls hinter `InCombatLockdown()`.

### 3.5 Layout-API
`ns:GetLayoutNames / GetActiveLayout / SetActiveLayout / NewLayout / CopyLayout / RenameLayout / DeleteLayout / ResetLayout / ResetEditFrame`. `SetActiveLayout` kopiert je Frame den Record in die Modul-DB + `applyPos`.

### 3.6 Dateien (minimal gehalten)
- **Geändert** `Core/Mover.lua` – die Engine (Registry, Selektion, Snapping, Layouts, Migration, Combat). `CreateMover` wird Wrapper.
- **NEU** `UI/EditMode.lua` – das HUD (Dim, Grid, Toolbar, Panel).
- **Geändert** `Modules/UnlockMode.lua` – Button ruft `ns:SetEditMode` statt nacktem `SetMoversEditMode`.
- **Geändert** `Core/Database.lua` – `editmode`-Defaults, `MigrateEditMode()`, Layout-Reapply bei `LoadProfile`.
- **Geändert** `Locales/enUS.lua` + `deDE.lua`, **beide TOCs** (`UI\EditMode.lua` nach `UI\OptionsBuilder.lua`).
- **Optional** je 3-Zeilen-`migrate`: CombatText, CooldownPulse, LazyVulo, VulLFG, DisenchantQueue, Arena/Core, MainFrame.

### 3.7 Rollout
1. **Engine + HUD-Kern**: Overlay-als-Kind, Selektion, Toolbar, Dim, Grid, Grid-Snap, Scale, Panel (X/Y/Scale/Anker), Layouts, Migration. `CreateMover`-Shim hält die 8 Module am Laufen.
2. **Magnetismus + Hilfslinien**, Alt-Cycle, CombatText/Duplikat-Tastatur falten, 7 Ad-hoc-Module andocken.
3. **Multi-Select** (Shift+Klick), **Layout-Export/Import-String** (trivial, da Layouts explizite Tabellen sind – das konnte DFUI nicht), `editPreview`-Politur (echte Frames statt Fake-Klone).
