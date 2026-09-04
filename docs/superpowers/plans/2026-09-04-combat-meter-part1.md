# Combat Meter Teil 1 (Engine und Fenster) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein leichtgewichtiges Schadens- und Heilungsmeter als Modul `meter`: Kampfprotokoll-Engine mit zwei lebenden Abschnitten (aktueller Kampf, gesamt) und ein festes Balkenfenster mit vier Modi, Klappmenü, Mausrad und Optionsseite.

**Architecture:** Drei Dateien nach dem Trackbars-Muster. `Modules/Meter.lua` ist die Engine (Gruppenliste, Begleiter-Karte, Protokoll-Leser als Verteiltabelle je Unterereignis, Abschnittsgrenzen, Sicherung) und stellt `ns.Meter` als Lese-Schnittstelle bereit. `Modules/MeterWindow.lua` ist das Fenster; es hängt sich über `mod:WindowEnable()` an die Engine, liest nur über `ns.Meter` und zeichnet im Kampf per Halbsekunden-Ticker. `Modules/MeterOptions.lua` ist die Optionsseite. Die Engine setzt nur ein Flag und ruft ein einziges Listener-Callback (`start`/`end`/`reset`); sie kennt das Fenster nicht.

**Tech Stack:** WoW-Classic-Addon-Lua (Anniversary 2.5.x-Klasse, Wrath-TOC 3.8.x mitgeführt), Hausgerüst (`ns:RegisterModule`, `ns:AddTicker`, `ns:CreateMover`, `ns:ShowPopupMenu`, `ns.UI:ShowTooltip`, `ns.MediaStatusbar`, `ns.ClassColor`); Prüfwerkzeuge `node tools/check.js` und `node tools/optcheck.cjs`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-04-combat-meter-part1-design.md`.
- KEINE Fremd-Addon-Namen in Code, Kommentaren, Beschriftungen, Commits oder Doku (Prüfliste = `FORBIDDEN`-Regex in `tools/check.js`).
- Locale-Schlüssel SIND die englischen Texte; `L[...]` nie auf Dateiebene auswerten (alle `L[]`-Stellen liegen in Funktionen). `mod.name` und `mod.description` sind rohe englische Schlüssel, das Gerüst übersetzt sie live.
- Beide TOC-Dateien (`VuloClassicUI.toc`, `VuloClassicUI_Vanilla.toc`) führen dieselbe Dateiliste; `check.js` vergleicht sie.
- `COMBAT_LOG_EVENT_UNFILTERED` läuft im ungeschützten Hot-Pfad von `Core/Events.lua`: keine Tabellenanlage je Ereignis, keine Zeichenketten-Operationen im Handler, `CombatLogGetCurrentEventInfo()` genau einmal je Feuern.
- Optionsseiten: Zeilen fluchten, Auswahl als Klappmenü (`dropdown`), Unteroptionen (`subOptions`) nur, wenn die Zeile bei ausgeschaltetem Elternteil buchstäblich nichts tut; ein Element in einer `layout = "row"`-Gruppe kann kein Zahnrad tragen.
- Nach jeder Aufgabe: `node tools/check.js` muss `RESULT: OK` melden; nach Aufgabe 6 zusätzlich `node tools/optcheck.cjs`.
- Commit-Botschaften: deutsch, keine Abkürzungen, kein Co-Authored-By.
- Spieltests: `/run` bricht bei 255 Zeichen stumm ab; Sondenzeilen unten sind darauf gekürzt.

## Abweichungen von der Spezifikation (beim Planen entschieden, in Aufgabe 1 in die Spec eingetragen)

1. **„gesamt" lebt direkt in der Charakter-Datenbank.** `VuloClassicUICharDB.meter.overall` IST die Abschnittstabelle; es gibt keine Kopie am Kampfende und keinen `PLAYER_LOGOUT`-Haken. Zurücksetzen leert die Tabelle an Ort und Stelle.
2. **Nach Kampfende bleibt der letzte Kampf sichtbar.** `GetSegment("current")` liefert den laufenden Kampf oder, außerhalb des Kampfes, den zuletzt beendeten. `InCombat()` bleibt `false`, sobald der Abschnitt geschlossen ist. Ohne diese Regel stünde das Fenster nach jedem Kampf auf „No combat data".
3. **Zwei weitere Griffe in der Engine-Schnittstelle:** `Meter:SetListener(fn)` (ein Callback, `fn("start"|"end"|"reset")`) und `Meter:Duration(seg)` (laufende Dauer für den offenen Abschnitt, gespeicherte für die anderen) sowie `Meter:PlayerGUID()`.
4. **Anzeige-Schalter liegen flach**, nicht hinter einem Zahnrad: Rang, Klammerwert, Anteil und Eigenhervorhebung tun bei keiner Elternzeile „nichts", also gibt es kein Elternteil (Hausregel). Nur `hideDelay` bleibt hinter dem Zahnrad von `hideOutOfCombat`.
5. **Größengriff** ist ein Kind des Mover-Kastens und damit genau dann sichtbar, wenn der Mover es ist (Bearbeiten-Modus).

## Dateistruktur

| Datei | Verantwortung |
|---|---|
| `Modules/Meter.lua` (neu) | Modulregistrierung mit Standardwerten, Gruppenliste, Begleiter-Karte, Abschnitte, Protokoll-Leser, Grenzen, Sicherung, `ns.Meter`-Schnittstelle. Ruft `mod:WindowEnable()`/`mod:WindowDisable()`, wenn vorhanden. |
| `Modules/MeterWindow.lua` (neu) | Fensterrahmen, Titelzeile, Balkenzeilen, Sortierung, Zahlenformat, Tooltip, Mausrad, Klappmenü, Ticker, Sichtbarkeit, Mover, Größengriff. Definiert `mod:WindowEnable()`, `mod:WindowDisable()`, `mod:ApplyWindow()`, `mod:SetMode()`, `mod:SetSegment()`. |
| `Modules/MeterOptions.lua` (neu) | `mod:GetOptions()`. |
| `VuloClassicUI.toc`, `VuloClassicUI_Vanilla.toc` | Drei Zeilen nach `Modules\CombatText.lua`. |
| `Locales/*.lua` (9 Dateien) | Neue Schlüssel, siehe Aufgabe 7. |
| `Media/Icons/modules/meter.tga` (neu) | Seitenleisten-Symbol. |
| `CHANGELOG.md` + generierte Versionshinweise | Aufgabe 7. |

---

### Task 1: Engine-Datei anlegen — Modul, Gruppenliste, Begleiter, Abschnittsmodell, Schnittstelle, TOC

**Files:**
- Create: `Modules/Meter.lua`
- Modify: `VuloClassicUI.toc` (nach der Zeile `Modules\CombatText.lua`)
- Modify: `VuloClassicUI_Vanilla.toc` (nach der Zeile `Modules\CombatText.lua`, Zeile 110)
- Modify: `docs/superpowers/specs/2026-09-04-combat-meter-part1-design.md` (Abweichungen eintragen)

**Interfaces:**
- Consumes: `ns:RegisterModule(key, def)` (Core/Modules.lua), `mod:RegisterEvent(event, fn)` mit `fn(event, ...)`, `ns:AddTicker(interval, fn, arg, label)` / `ns:CancelTicker(handle)` (Core/Schedule.lua), `VuloClassicUICharDB` (existiert ab `ADDON_LOADED`, vor `EnableModules`).
- Produces: `ns.Meter` mit `GetSegment(which)`, `Duration(seg)`, `IsDirty()`, `ClearDirty()`, `InCombat()`, `SetListener(fn)`, `PlayerGUID()`, `Reset()`, `HANDLERS` (Tabelle Unterereignis → Funktion, in Aufgabe 2 gefüllt). Abschnittsform `{ title, start, duration, players = { [guid] = { name, class, damage, heal, overheal } } }`. Modul-Haken `mod.WindowEnable`/`mod.WindowDisable` (Aufgabe 3 definiert sie).

- [ ] **Step 1: `Modules/Meter.lua` schreiben** (Protokoll-Leser und Grenzen kommen in Aufgabe 2; die Datei ist danach schon lauffähig):

```lua
-- VuloClassicUI / Modules / Meter: combat meter engine. Counts damage and
-- healing per group member (pets credited to their owner) in two live
-- segments -- the running fight and the overall total -- and hands the window
-- a read-only view through ns.Meter. Knows nothing about bars; those live in
-- Modules/MeterWindow.lua and attach through mod:WindowEnable().
-- No L here on purpose: the engine has no text of its own.
local _, ns = ...

local mod = ns:RegisterModule("meter", {
    name        = "Combat Meter",
    group       = "HUD",
    description = "Lightweight damage and healing meter: who did how much, per fight and overall. Left-click the title for mode and segment, mouse wheel on the title cycles modes, right-drag the title to move.",
    defaults    = {
        enabled         = true,
        width           = 220,
        height          = 160,
        barHeight       = 18,
        barGap          = 1,
        fontSize        = 11,
        texture         = "Atrocity",
        scale           = 1.0,
        showRank        = true,
        showPerSecond   = true,
        showPercent     = true,
        highlightSelf   = true,
        onlyInGroup     = false,
        hideInCombat    = false,
        hideOutOfCombat = false,
        hideDelay       = 10,
        defaultMode     = "damage",      -- damage | dps | heal | hps
        defaultSegment  = "current",     -- current | overall
        resetOnNewGroup = true,
        x = 0, y = 0, unlocked = false,
    },
})

local GetTime             = GetTime
local UnitGUID            = UnitGUID
local UnitName            = UnitName
local UnitClass           = UnitClass
local UnitAffectingCombat = UnitAffectingCombat
local IsInRaid            = IsInRaid
local IsInGroup           = IsInGroup
local GetNumGroupMembers  = GetNumGroupMembers
local wipe                = wipe
local pairs               = pairs
local type, tonumber      = type, tonumber

local Meter = {}
ns.Meter = Meter

------------------------------------------------------------------------
-- Group roster and pet owners
------------------------------------------------------------------------
-- roster[guid] = { unit, name, class }; only these (and their pets) count.
local roster = {}
-- owners[petGUID] = ownerGUID; filled from the group's pet units and from
-- SPELL_SUMMON, so totems, elementals and guardians credit their owner.
local owners = {}
local playerGUID

local PET_UNIT = { player = "pet" }
for i = 1, 4  do PET_UNIT["party" .. i] = "partypet" .. i end
for i = 1, 40 do PET_UNIT["raid"  .. i] = "raidpet"  .. i end

local function addUnit(unit)
    local guid = UnitGUID(unit)
    if not guid then return end
    local _, class = UnitClass(unit)
    local e = roster[guid]
    if not e then e = {}; roster[guid] = e end
    e.unit, e.name, e.class = unit, UnitName(unit), class
    local petUnit = PET_UNIT[unit]
    if petUnit then
        local petGUID = UnitGUID(petUnit)
        if petGUID then owners[petGUID] = guid end
    end
end

-- Rebuilt whole on every roster change. Segment entries copy name and class,
-- so a member who leaves mid-fight keeps their bar; only new events stop.
local function rebuildRoster()
    wipe(roster)
    addUnit("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do addUnit("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do addUnit("party" .. i) end
    end
end

local function groupKind()
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return "solo"
end

------------------------------------------------------------------------
-- Segments
------------------------------------------------------------------------
local function newSegment()
    return { title = nil, start = 0, duration = 0, players = {} }
end

local current               -- the running fight, nil outside combat
local last                  -- the last finished fight, shown until the next starts
local overall = newSegment() -- swapped for the saved table in OnEnable
local dirty = false
local listener              -- window callback: fn("start" | "end" | "reset")

local function notify(what)
    if listener then listener(what) end
end

-- Only called after resolve() confirmed roster[guid] exists.
local function entry(seg, guid)
    local p = seg.players[guid]
    if not p then
        local r = roster[guid]
        p = { name = r.name, class = r.class, damage = 0, heal = 0, overheal = 0 }
        seg.players[guid] = p
    end
    return p
end

-- Source GUID -> the roster GUID it counts for, or nil when nobody we track.
local function resolve(guid)
    if roster[guid] then return guid end
    local o = owners[guid]
    if o and roster[o] then return o end
    return nil
end

local function fold(dst, src)
    for guid, p in pairs(src.players) do
        local d = dst.players[guid]
        if not d then
            d = { name = p.name, class = p.class, damage = 0, heal = 0, overheal = 0 }
            dst.players[guid] = d
        end
        d.damage   = d.damage   + p.damage
        d.heal     = d.heal     + p.heal
        d.overheal = d.overheal + p.overheal
    end
    dst.duration = dst.duration + src.duration
end

------------------------------------------------------------------------
-- Public read interface (the window reads through this and never writes)
------------------------------------------------------------------------
function Meter:GetSegment(which)
    if which == "overall" then return overall end
    return current or last
end

function Meter:Duration(seg)
    if seg == current then return GetTime() - seg.start end
    return seg.duration or 0
end

function Meter:IsDirty()     return dirty end
function Meter:ClearDirty()  dirty = false end
function Meter:InCombat()    return current ~= nil end
function Meter:SetListener(fn) listener = fn end
function Meter:PlayerGUID()  return playerGUID end

function Meter:Reset()
    wipe(overall.players)
    overall.duration = 0
    if current then
        wipe(current.players)
        current.start = GetTime()
    end
    last = nil
    wipe(owners)
    rebuildRoster()
    dirty = true
    notify("reset")
end

-- Parts 2 and 3 add their own subevent entries here.
Meter.HANDLERS = {}

------------------------------------------------------------------------
-- Enable / disable
------------------------------------------------------------------------
function mod:OnEnable()
    playerGUID = UnitGUID("player")
    local cdb = VuloClassicUICharDB
    if cdb then
        cdb.meter = cdb.meter or {}
        local saved = cdb.meter.overall
        if type(saved) ~= "table" then
            saved = newSegment()
            cdb.meter.overall = saved
        end
        saved.players  = saved.players or {}
        saved.duration = tonumber(saved.duration) or 0
        overall = saved
    end
    rebuildRoster()
    if self.EngineEnable then self:EngineEnable() end
    if self.WindowEnable then self:WindowEnable() end
end

function mod:OnDisable()
    if self.EngineDisable then self:EngineDisable() end
    if self.WindowDisable then self:WindowDisable() end
end
```

- [ ] **Step 2: TOC-Zeile eintragen** — in BEIDEN TOC-Dateien direkt nach `Modules\CombatText.lua` genau diese eine Zeile (die Zeilen für `MeterWindow.lua` und `MeterOptions.lua` kommen in Aufgabe 3 und 6, wenn die Dateien existieren):

```
Modules\Meter.lua
```

- [ ] **Step 3: Spec-Abweichungen eintragen** — in der Spec-Datei unter `## Sicherung und Zurücksetzen` den ersten Punkt ersetzen durch:

```markdown
- `overall` IST die Tabelle `VuloClassicUICharDB.meter.overall`; sie wird beim
  Modulstart übernommen (fehlende Felder ergänzt) und lebt dort. Es gibt keine
  Kopie am Kampfende und keinen Logout-Haken. Im Kampf wird nichts geschrieben,
  weil der laufende Abschnitt eine eigene Tabelle ist, die erst am Ende
  eingefaltet wird.
```

Unter `## Datenmodell` nach dem ersten Absatz ergänzen:

```markdown
Nach dem Kampfende bleibt der zuletzt beendete Abschnitt als „aktueller Kampf"
sichtbar, bis ein neuer beginnt. `InCombat()` ist ab dem Schließen `false`.
```

Unter `## Engine-Schnittstelle (für das Fenster)` den Codeblock ersetzen durch:

```lua
ns.Meter:GetSegment("current" | "overall")   -- laufender oder letzter Kampf / gesamt
ns.Meter:Duration(seg)                         -- laufende Dauer beim offenen Abschnitt
ns.Meter:IsDirty() / ns.Meter:ClearDirty()
ns.Meter:InCombat()                            -- true, solange ein Abschnitt offen ist
ns.Meter:SetListener(fn)                       -- fn("start" | "end" | "reset")
ns.Meter:PlayerGUID()
ns.Meter:Reset()
```

Unter `## Optionsseite` im Punkt **Anzeige** den Satz „Zahnrad: `showRank`, …" ersetzen durch: „Danach vier flache Schalter `showRank`, `showPerSecond`, `showPercent`, `highlightSelf` (alle Standard an); sie haben kein Elternteil, hinter dem sie nichts täten."

- [ ] **Step 4: Checker laufen lassen**

Run: `cd tools && node check.js`
Expected: `RESULT: OK`. Die Locals `entry`, `resolve`, `fold`, `UnitAffectingCombat` sind in dieser Zwischenstufe noch ungenutzt (Aufgabe 2 nutzt sie); meldet der Checker sie, bleibt das stehen und wird in der Commit-Botschaft genannt. Alles andere beheben.

- [ ] **Step 5: Spielprüfung (nach `/reload`)** — `_G.VuloClassicUI` ist der Addon-Namensraum (`Core/Namespace.lua:4`), also:

```
/run local M=VuloClassicUI.Meter; local o=VuloClassicUICharDB.meter and VuloClassicUICharDB.meter.overall; print(M and "engine ok", o and "chardb ok", o and o.duration)
```

Expected: `engine ok chardb ok 0` und keine Fehler.

- [ ] **Step 6: Commit**

```bash
git add Modules/Meter.lua VuloClassicUI.toc VuloClassicUI_Vanilla.toc docs/superpowers/specs/2026-09-04-combat-meter-part1-design.md
git commit -m "Combat Meter: Engine-Geruest -- Modul meter mit Standardwerten, Gruppenliste mit Begleiter-Karte, zwei lebende Abschnitte (laufender Kampf, gesamt in der Charakter-Datenbank), Lese-Schnittstelle ns.Meter; Spezifikation um die beim Planen entschiedenen Abweichungen ergaenzt"
```

---

### Task 2: Protokoll-Leser und Abschnittsgrenzen

**Files:**
- Modify: `Modules/Meter.lua` (Block zwischen `Meter._internal = { ... }` und `function mod:OnEnable()` einfügen, dazu `EngineEnable`/`EngineDisable`)

**Interfaces:**
- Consumes: `Meter._internal` aus Aufgabe 1, `CombatLogGetCurrentEventInfo` (Core/Compat.lua stellt den Alias sicher), `mod:RegisterEvent`, `ns:AddTicker`/`ns:CancelTicker`.
- Produces: gefüllte `Meter.HANDLERS`, `mod:EngineEnable()`, `mod:EngineDisable()`; Abschnittsgrenzen wie in der Spec; `notify("start")` beim Öffnen, `notify("end")` beim Schließen.

- [ ] **Step 1: Grenzen und Leser einfügen** — direkt VOR `function mod:OnEnable()`:

```lua
------------------------------------------------------------------------
-- Segment boundaries
------------------------------------------------------------------------
local CLGetInfo = CombatLogGetCurrentEventInfo
local waitTicker, clearChecks
local pendingReset = false
local kind                     -- "solo" | "party" | "raid", for resetOnNewGroup

local function stopWait()
    if waitTicker then
        ns:CancelTicker(waitTicker)
        waitTicker = nil
    end
end

local function closeSegment()
    if not current then return end
    stopWait()
    current.duration = GetTime() - current.start
    fold(overall, current)
    last, current = current, nil
    if pendingReset then
        pendingReset = false
        Meter:Reset()
    end
    dirty = true
    notify("end")
end

local function anyoneInCombat()
    for _, r in pairs(roster) do
        if UnitAffectingCombat(r.unit) then return true end
    end
    return false
end

-- Runs only between our own PLAYER_REGEN_ENABLED and the group's last exit
-- from combat. Two clear checks in a row (about one second) close the fight.
local function waitTick()
    if anyoneInCombat() then
        clearChecks = 0
        return
    end
    clearChecks = clearChecks + 1
    if clearChecks >= 2 then closeSegment() end
end

local function beginWait()
    if not current or waitTicker then return end
    clearChecks = 0
    waitTicker = ns:AddTicker(0.5, waitTick, nil, "meter-wait")
end

local function openSegment(title)
    if current then return end
    current = newSegment()
    current.start = GetTime()
    current.title = title
    dirty = true
    notify("start")
    -- Opened by the log while we stand outside combat (a healer at the pull):
    -- no PLAYER_REGEN_ENABLED will ever come for us, so the wait starts now.
    if not UnitAffectingCombat("player") then beginWait() end
end

local function onRegenDisabled()
    stopWait()
    openSegment(nil)
end

local function onRegenEnabled()
    beginWait()
end

-- ENCOUNTER_START(encounterID, encounterName, difficultyID, groupSize)
local function onEncounterStart(_, _, name)
    closeSegment()
    openSegment(name)
end

local function onEncounterEnd()
    closeSegment()
end

local function onRoster()
    rebuildRoster()
    local k = groupKind()
    if k ~= kind then
        -- Solo -> group and party -> raid start a fresh overall; a member
        -- joining or leaving does not. Mid-fight the reset waits for the end.
        if kind and k ~= "solo" and mod.db.resetOnNewGroup then
            if current then pendingReset = true else Meter:Reset() end
        end
        kind = k
    end
end

-- UNIT_PET(unit): the pet of a group unit changed.
local function onUnitPet(_, unit)
    local petUnit = PET_UNIT[unit]
    if not petUnit then return end
    local guid = UnitGUID(unit)
    if not (guid and roster[guid]) then return end
    local petGUID = UnitGUID(petUnit)
    if petGUID then owners[petGUID] = guid end
end

------------------------------------------------------------------------
-- Combat log reader: one CombatLogGetCurrentEventInfo per firing, one table
-- lookup per subevent, no allocation on the hot path.
------------------------------------------------------------------------
local HANDLERS = Meter.HANDLERS

local function addDamage(src, amount)
    if not amount or amount <= 0 then return end
    local owner = resolve(src)
    if not owner then return end
    if not current then openSegment(nil) end
    local p = entry(current, owner)
    p.damage = p.damage + amount
    dirty = true
end

-- SWING_DAMAGE: amount is field 12. Spell-prefixed subevents carry spellId,
-- spellName, spellSchool in 12-14 and amount in 15.
HANDLERS.SWING_DAMAGE = function(src, _, a12) addDamage(src, a12) end
local function spellDamage(src, _, _, a15) addDamage(src, a15) end
HANDLERS.RANGE_DAMAGE          = spellDamage
HANDLERS.SPELL_DAMAGE          = spellDamage
HANDLERS.SPELL_PERIODIC_DAMAGE = spellDamage
HANDLERS.DAMAGE_SHIELD         = spellDamage
HANDLERS.DAMAGE_SPLIT          = spellDamage

-- Healing never opens a fight (pre-pull heals are not combat); field 16 is
-- overhealing.
local function spellHeal(src, _, _, a15, a16)
    if not current or not a15 then return end
    local owner = resolve(src)
    if not owner then return end
    local p = entry(current, owner)
    p.heal     = p.heal + a15
    p.overheal = p.overheal + (a16 or 0)
    dirty = true
end
HANDLERS.SPELL_HEAL          = spellHeal
HANDLERS.SPELL_PERIODIC_HEAL = spellHeal

HANDLERS.SPELL_SUMMON = function(src, dst)
    if dst and roster[src] then owners[dst] = src end
end

local function onCLEU()
    local _, sub, _, src, _, _, _, dst, _, _, _, a12, _, _, a15, a16 = CLGetInfo()
    local h = HANDLERS[sub]
    if h then h(src, dst, a12, a15, a16) end
end

function mod:EngineEnable()
    kind = groupKind()
    self:RegisterEvent("GROUP_ROSTER_UPDATE",         onRoster)
    self:RegisterEvent("PLAYER_ENTERING_WORLD",       onRoster)
    self:RegisterEvent("UNIT_PET",                    onUnitPet)
    self:RegisterEvent("PLAYER_REGEN_DISABLED",       onRegenDisabled)
    self:RegisterEvent("PLAYER_REGEN_ENABLED",        onRegenEnabled)
    self:RegisterEvent("ENCOUNTER_START",             onEncounterStart)
    self:RegisterEvent("ENCOUNTER_END",               onEncounterEnd)
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
end

function mod:EngineDisable()
    closeSegment()
    stopWait()
end
```

Die Grenzen liegen in derselben Datei wie das Abschnittsmodell und greifen direkt auf dessen Upvalues (`current`, `last`, `overall`, `dirty`, `roster`, `owners`) zu; deshalb steht dieser Block VOR `mod:OnEnable()` und NACH `Meter.HANDLERS = {}`.

- [ ] **Step 2: Checker**

Run: `cd tools && node check.js`
Expected: `RESULT: OK`, keine ungenutzten Locals mehr.

- [ ] **Step 3: Spielprüfung am Übungspuppen-Gegner** (`/reload`, dann angreifen, etwa zehn Sekunden, aufhören, zwei Sekunden warten):

```
/run local M=VuloClassicUI.Meter; local s=M:GetSegment("current"); for g,p in pairs(s.players) do print(p.name, p.damage, M:Duration(s)) end
```

Expected: eine Zeile mit deinem Namen, Schaden > 0, Dauer ungefähr die Kampfzeit. Dann:

```
/run local M=VuloClassicUI.Meter; local s=M:GetSegment("overall"); print(s.duration, M:InCombat()); for g,p in pairs(s.players) do print(p.name, p.damage) end
```

Expected: `InCombat()` ist `false`, „gesamt" enthält denselben Schaden. `/reload`, dann die zweite Zeile erneut: der Schaden ist noch da (Charakter-Datenbank). Danach `/run VuloClassicUI.Meter:Reset()` und erneut: leer.

- [ ] **Step 4: Commit**

```bash
git add Modules/Meter.lua
git commit -m "Combat Meter: Protokoll-Leser und Abschnittsgrenzen -- Verteiltabelle je Unterereignis fuer Nah-, Fern-, Zauber- und periodischen Schaden, Schadensschild, geteilten Schaden sowie direkte und periodische Heilung mit Ueberheilung; Beschwoerungen fuellen die Begleiter-Karte; Abschnitt oeffnet bei eigenem Kampfbeginn, erstem gezaehlten Schadensereignis oder Begegnungsstart und schliesst bei Begegnungsende oder wenn ein Halbsekunden-Ticker zweimal niemanden im Kampf findet; Gruppenwechsel setzt gesamt zurueck, im Kampf erst am Ende"
```

---

### Task 3: Fensterrahmen, Titelzeile, Mover, Größengriff, Leerzustand

**Files:**
- Create: `Modules/MeterWindow.lua`
- Modify: `VuloClassicUI.toc` und `VuloClassicUI_Vanilla.toc` (Zeile `Modules\MeterWindow.lua` nach `Modules\Meter.lua`)

**Interfaces:**
- Consumes: `ns.Meter` (Aufgabe 1/2), `ns:CreateMover(target, opts)` mit `opts.db`, `opts.key`, `opts.scalable`, `opts.label`, `opts.width`, `opts.height`; `ns:ApplyMover(mover)`; `ns:RefreshMoverGeometry(mover)`; `ns:GetCenterOffsets(frame)`; `ns.UI.FontFor(modKey, fs, size)`; `ns.UI:ShowTooltip(owner, spec)`/`HideTooltip()`; `ns.COLORS.accent`/`.border`; `ns:IsEditModeActive()`.
- Produces: `mod:WindowEnable()`, `mod:WindowDisable()`, `mod:ApplyWindow()`; Datei-Locals `win`, `mover`, `rows`, `layoutRows`, `refresh`, `applyVisibility`, die Aufgabe 4 und 5 erweitern. Rahmenname `VuloClassicUIMeter`.

- [ ] **Step 1: `Modules/MeterWindow.lua` schreiben** (Aufgabe 4 ersetzt die Stummel `layoutRows` und `refresh`, Aufgabe 5 ergänzt Menü und Modus-Wechsel):

```lua
-- VuloClassicUI / Modules / MeterWindow: the bar window for the combat meter.
-- Reads the engine through ns.Meter and never writes into its tables.
local _, ns = ...
local L     = ns.L
local UI    = ns.UI
local mod   = ns.modules.meter
local Meter = ns.Meter

local GetTime             = GetTime
local floor               = math.floor
local max                 = math.max
local min                 = math.min
local format              = string.format
local sort                = table.sort
local wipe                = wipe
local pairs               = pairs
local IsInGroup           = IsInGroup
local UnitAffectingCombat = UnitAffectingCombat
local CreateFrame         = CreateFrame

local TITLE_H  = 20
local PAD      = 2
local MODES    = { "damage", "dps", "heal", "hps" }
local MODE_IDX = { damage = 1, dps = 2, heal = 3, hps = 4 }
local ICONS    = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\"
local TEX_FLAT = "Interface\\Buttons\\WHITE8X8"

local win, mover
local rows  = {}     -- one StatusBar per visible slot, reused across players
local order = {}     -- guids sorted by the current mode's value
local vals  = {}     -- guid -> value for the comparator
local mode, segment, scroll = "damage", "current", 0
local ticker
local lastCombatEnd  = 0
local hideTimerArmed = false

-- Forward declarations; filled in further down (and replaced in Task 4/5).
local layoutRows, refresh, applyVisibility, openMenu, onWheel, onTitleWheel, rowEnter

------------------------------------------------------------------------
-- Labels
------------------------------------------------------------------------
local function modeLabel(m)
    if m == "damage" then return L["Damage"] end
    if m == "dps"    then return L["DPS"] end
    if m == "heal"   then return L["Healing"] end
    return L["HPS"]
end

local function segmentLabel(seg)
    if segment == "overall" then return L["Overall"] end
    if seg and seg.title then return seg.title end
    return L["Current fight"]
end

------------------------------------------------------------------------
-- Stubs replaced in Task 4
------------------------------------------------------------------------
layoutRows = function() end
refresh = function()
    if not win then return end
    win.titleText:SetText(modeLabel(mode) .. " \194\183 " .. segmentLabel(Meter:GetSegment(segment)))
    win.count:SetText("")
    win.empty:Show()
end
onWheel      = function() end
onTitleWheel = function() end
rowEnter     = function() end
openMenu     = function() end

------------------------------------------------------------------------
-- Visibility
------------------------------------------------------------------------
applyVisibility = function()
    if not win then return end
    local db = mod.db
    if ns.IsEditModeActive and ns:IsEditModeActive() then
        win:Show()
        return
    end
    local inCombat = Meter:InCombat() or UnitAffectingCombat("player")
    local show = true
    if db.onlyInGroup and not IsInGroup() then show = false end
    if db.hideInCombat and inCombat then show = false end
    if show and db.hideOutOfCombat and not inCombat then
        local left = (db.hideDelay or 0) - (GetTime() - lastCombatEnd)
        if left > 0 then
            if not hideTimerArmed then
                hideTimerArmed = true
                C_Timer.After(left + 0.1, function()
                    hideTimerArmed = false
                    applyVisibility()
                end)
            end
        else
            show = false
        end
    end
    win:SetShown(show)
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------
local function iconButton(parent, tex, tipText, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(12, 12)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(b)
    b.tex:SetTexture(ICONS .. tex)
    b.tex:SetVertexColor(0.6, 0.6, 0.65)
    b.tipText = tipText
    b:SetScript("OnEnter", function(self)
        self.tex:SetVertexColor(1, 1, 1)
        UI:ShowTooltip(self, self.tipText)
    end)
    b:SetScript("OnLeave", function(self)
        self.tex:SetVertexColor(0.6, 0.6, 0.65)
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function savePosition()
    local x, y = ns:GetCenterOffsets(win)
    if x and y then
        mod.db.x, mod.db.y = x, y
        if mover then ns:ApplyMover(mover) end
    end
end

local function build()
    if win then return end
    local db = mod.db
    local accent = ns.COLORS.accent

    win = CreateFrame("Frame", "VuloClassicUIMeter", UIParent)
    win:SetSize(db.width, db.height)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:SetResizable(true)
    if win.SetResizeBounds then
        win:SetResizeBounds(120, 60)
    elseif win.SetMinResize then
        win:SetMinResize(120, 60)
    end
    win:SetFrameStrata("LOW")

    win.bg = win:CreateTexture(nil, "BACKGROUND")
    win.bg:SetAllPoints(win)
    win.bg:SetColorTexture(0.05, 0.05, 0.06, 0.90)
    win.edge = CreateFrame("Frame", nil, win, BackdropTemplateMixin and "BackdropTemplate")
    win.edge:SetAllPoints(win)
    if win.edge.SetBackdrop then
        win.edge:SetBackdrop({ edgeFile = TEX_FLAT, edgeSize = 1 })
        local b = ns.COLORS.border or { r = 0, g = 0, b = 0 }
        win.edge:SetBackdropBorderColor(b.r or 0, b.g or 0, b.b or 0, 0.8)
    end

    -- Title bar: left-click = menu, wheel = mode, right-drag = move.
    local title = CreateFrame("Frame", nil, win)
    title:SetPoint("TOPLEFT",  win, "TOPLEFT",  0, 0)
    title:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    title:SetHeight(TITLE_H)
    title.bg = title:CreateTexture(nil, "BACKGROUND")
    title.bg:SetAllPoints(title)
    title.bg:SetColorTexture(1, 1, 1, 0.04)
    title:EnableMouse(true)
    title:EnableMouseWheel(true)
    title:RegisterForDrag("RightButton")
    title:SetScript("OnDragStart", function() win:StartMoving() end)
    title:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        savePosition()
    end)
    title:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then openMenu() end
    end)
    title:SetScript("OnMouseWheel", function(_, delta) onTitleWheel(delta) end)
    win.title = title

    win.menuBtn = iconButton(title, "arrow_down.tga", L["Mode, segment and reset"], function() openMenu() end)
    win.menuBtn:SetPoint("RIGHT", title, "RIGHT", -5, 0)
    win.resetBtn = iconButton(title, "reset.tga", L["Reset"], function() Meter:Reset() end)
    win.resetBtn:SetPoint("RIGHT", win.menuBtn, "LEFT", -4, 0)

    win.count = title:CreateFontString(nil, "OVERLAY")
    UI.FontFor("meter", win.count, 9)
    win.count:SetPoint("RIGHT", win.resetBtn, "LEFT", -6, 0)
    win.count:SetTextColor(0.55, 0.55, 0.6)

    win.titleText = title:CreateFontString(nil, "OVERLAY")
    UI.FontFor("meter", win.titleText, 11)
    win.titleText:SetPoint("LEFT",  title, "LEFT", 6, 0)
    win.titleText:SetPoint("RIGHT", win.count, "LEFT", -4, 0)
    win.titleText:SetJustifyH("LEFT")
    win.titleText:SetWordWrap(false)
    win.titleText:SetTextColor(accent.r, accent.g, accent.b)

    -- Body: the bar rows live here (Task 4); wheel scrolls.
    win.body = CreateFrame("Frame", nil, win)
    win.body:SetPoint("TOPLEFT",     win, "TOPLEFT",     PAD, -(TITLE_H + PAD))
    win.body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, PAD)
    win.body:EnableMouseWheel(true)
    win.body:SetScript("OnMouseWheel", function(_, delta) onWheel(delta) end)

    win.empty = win.body:CreateFontString(nil, "OVERLAY")
    UI.FontFor("meter", win.empty, 11)
    win.empty:SetPoint("TOP", win.body, "TOP", 0, -8)
    win.empty:SetTextColor(0.5, 0.5, 0.55)
    win.empty:SetText(L["No combat data"])

    -- Mover box (edit mode); the resize grip is its child, so it shows and
    -- hides with the box and never needs its own edit-mode hook.
    mover = ns:CreateMover(win, {
        db = db, key = "meter", scalable = true,
        label = L["Combat Meter"], width = 220, height = 40,
    })
    ns:ApplyMover(mover)

    local grip = CreateFrame("Button", nil, mover)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(mover:GetFrameLevel() + 5)
    grip.tex = grip:CreateTexture(nil, "OVERLAY")
    grip.tex:SetAllPoints(grip)
    grip.tex:SetTexture(ICONS .. "expand.tga")
    grip.tex:SetVertexColor(accent.r, accent.g, accent.b, 0.9)
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        win:StopMovingOrSizing()
        -- mod.db, not the captured db: a profile switch swaps the table.
        mod.db.width  = floor(win:GetWidth()  + 0.5)
        mod.db.height = floor(win:GetHeight() + 0.5)
        savePosition()
        if mover then ns:RefreshMoverGeometry(mover) end
        layoutRows()
        refresh()
    end)
    win.grip = grip

    if ns.RegisterEditModeHook then
        ns:RegisterEditModeHook(function() applyVisibility() end)
    end
end

------------------------------------------------------------------------
-- Module hooks (called from Modules/Meter.lua)
------------------------------------------------------------------------
function mod:ApplyWindow()
    if not win then return end
    local db = self.db
    win:SetSize(db.width, db.height)
    ns:ApplyMover(mover)
    layoutRows()
    refresh()
    applyVisibility()
end

function mod:WindowEnable()
    build()
    local db = self.db
    mode    = MODE_IDX[db.defaultMode] and db.defaultMode or "damage"
    segment = (db.defaultSegment == "overall") and "overall" or "current"
    scroll  = 0
    self:RegisterEvent("PLAYER_REGEN_DISABLED", applyVisibility)
    self:RegisterEvent("PLAYER_REGEN_ENABLED",  applyVisibility)
    self:RegisterEvent("GROUP_ROSTER_UPDATE",   applyVisibility)
    self:ApplyWindow()
end

function mod:WindowDisable()
    if ticker then
        ns:CancelTicker(ticker)
        ticker = nil
    end
    Meter:SetListener(nil)
    if win then win:Hide() end
end
```

- [ ] **Step 2: TOC-Zeile** `Modules\MeterWindow.lua` in BEIDEN TOC-Dateien direkt nach `Modules\Meter.lua`.

- [ ] **Step 3: Checker**

Run: `cd tools && node check.js`
Expected: `RESULT: OK`. Ungenutzte Locals in dieser Zwischenstufe (`max`, `min`, `format`, `sort`, `wipe`, `pairs`, `rows`, `order`, `vals`, `rowEnter`, `ticker` als Schreibziel): meldet der Checker sie, bleiben sie stehen, weil Aufgabe 4 sie benutzt — dann den Commit trotzdem machen und die Meldung in der Commit-Botschaft nennen. Meldet der Checker `RESULT: FAIL` wegen etwas anderem, beheben.

- [ ] **Step 4: Spielprüfung** (`/reload`): das Fenster steht in der Bildschirmmitte, Titel „Damage · Current fight", darunter grau „No combat data". Rechtsklick-Ziehen auf den Titel verschiebt es; nach `/reload` steht es an der neuen Stelle. Bearbeiten-Modus öffnen (`/vcui`, Entsperren): der Mover-Kasten „Combat Meter" liegt über dem Fenster, unten rechts der Griff; Ziehen am Griff ändert die Größe, nach dem Loslassen bleibt sie erhalten.

- [ ] **Step 5: Commit**

```bash
git add Modules/MeterWindow.lua VuloClassicUI.toc VuloClassicUI_Vanilla.toc
git commit -m "Combat Meter: Fensterrahmen -- Titelzeile mit Zuruecksetzen- und Menue-Symbol, Rechtsklick-Ziehen zum Verschieben, Haus-Mover mit Groessengriff als Kind des Mover-Kastens, Sichtbarkeitsregeln (nur in Gruppe, im Kampf, ausserhalb des Kampfes mit Nachlauf), Leerhinweis"
```

---

### Task 4: Balkenzeilen, Sortierung, Zahlenformat, Tooltip, Mausrad, Ticker

**Files:**
- Modify: `Modules/MeterWindow.lua` (den Block `-- Stubs replaced in Task 4` ersetzen; Listener und Ticker ergänzen; `WindowEnable` erweitern)

**Interfaces:**
- Consumes: `Meter:GetSegment`, `Meter:Duration`, `Meter:IsDirty`/`ClearDirty`, `Meter:InCombat`, `Meter:SetListener`, `Meter:PlayerGUID`; `ns.MediaStatusbar(name, fallback)`; `ns.ClassColor(token)` → `{ r, g, b }`.
- Produces: `layoutRows()`, `refresh()`, `onWheel(delta)`, `rowEnter(self)`, Datei-Locals `startTicker()`/`stopTicker()`, `onEngine(what)`; `short(n)`, `clock(sec)`.

- [ ] **Step 1: Stummel-Block ersetzen** — den Block von `-- Stubs replaced in Task 4` bis einschließlich `openMenu = function() end` durch Folgendes ersetzen (`openMenu` und `onTitleWheel` bleiben bis Aufgabe 5 Stummel und stehen am Ende dieses Blocks):

```lua
------------------------------------------------------------------------
-- Numbers
------------------------------------------------------------------------
-- Integer -> short string, cached: the same totals repeat across ticks and
-- rows, and a raid fight would otherwise mint thousands of strings.
local fmtCache, fmtCount = {}, 0
local function short(n)
    n = floor(n + 0.5)
    local s = fmtCache[n]
    if s then return s end
    if n >= 1000000 then
        s = format("%.2fm", n / 1000000)
    elseif n >= 1000 then
        s = format("%.1fk", n / 1000)
    else
        s = tostring(n)
    end
    fmtCount = fmtCount + 1
    if fmtCount > 4000 then
        wipe(fmtCache)
        fmtCount = 0
    end
    fmtCache[n] = s
    return s
end

local function clock(sec)
    sec = floor(sec + 0.5)
    return format("%d:%02d", floor(sec / 60), sec % 60)
end

local function valueOf(p, dur)
    if mode == "damage" then return p.damage end
    if mode == "heal"   then return p.heal - p.overheal end
    if dur <= 0 then return 0 end
    if mode == "dps" then return p.damage / dur end
    return (p.heal - p.overheal) / dur
end

-- Ties break on the guid so equal values keep a stable order between ticks.
local function byValue(a, b)
    local va, vb = vals[a], vals[b]
    if va == vb then return a < b end
    return va > vb
end

local function rightText(p, v, total, dur)
    local db  = mod.db
    local pct = total > 0 and (v / total * 100) or 0
    local secondary
    if mode == "damage" then
        secondary = dur > 0 and p.damage / dur or 0
    elseif mode == "heal" then
        secondary = dur > 0 and (p.heal - p.overheal) / dur or 0
    elseif mode == "dps" then
        secondary = p.damage
    else
        secondary = p.heal - p.overheal
    end
    local main = short(v)
    if db.showPerSecond and db.showPercent then
        return format("%s (%s, %.1f%%)", main, short(secondary), pct)
    elseif db.showPerSecond then
        return format("%s (%s)", main, short(secondary))
    elseif db.showPercent then
        return format("%s (%.1f%%)", main, pct)
    end
    return main
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------
local function rowSlots()
    local db = mod.db
    return max(1, floor((db.height - TITLE_H - PAD * 2) / (db.barHeight + db.barGap)))
end

local function texturePath()
    return ns.MediaStatusbar(mod.db.texture, "Atrocity")
end

local tipLines = {}
local tipSpec  = { title = "", lines = tipLines, anchor = "ANCHOR_RIGHT" }

rowEnter = function(self)
    local seg = Meter:GetSegment(segment)
    local p = seg and self.guid and seg.players[self.guid]
    if not p then return end
    local dur   = Meter:Duration(seg)
    local v     = vals[self.guid] or 0
    local total = 0
    for i = 1, #order do total = total + (vals[order[i]] or 0) end
    local isHeal = (mode == "heal" or mode == "hps")
    local amount = isHeal and (p.heal - p.overheal) or p.damage
    wipe(tipLines)
    tipLines[1] = format("%s: %s", L["Total"], short(amount))
    tipLines[2] = format("%s: %s", L["Per second"], short(dur > 0 and amount / dur or 0))
    tipLines[3] = format("%s: %.1f%%", L["Share"], total > 0 and v / total * 100 or 0)
    if isHeal then
        tipLines[4] = format("%s: %.1f%%", L["Overhealing"], p.heal > 0 and p.overheal / p.heal * 100 or 0)
    end
    tipLines[#tipLines + 1] = format("%s: %s", L["Fight duration"], clock(dur))
    tipSpec.title = p.name
    UI:ShowTooltip(self, tipSpec)
end

onWheel = function(delta)
    scroll = max(0, scroll - delta)
    refresh()
end

local function createRow()
    local r = CreateFrame("StatusBar", nil, win.body)
    r:SetMinMaxValues(0, 1)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints(r)
    r.bg:SetColorTexture(1, 1, 1, 0.05)
    r.left = r:CreateFontString(nil, "OVERLAY")
    r.left:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.left:SetJustifyH("LEFT")
    r.left:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY")
    r.right:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.right:SetJustifyH("RIGHT")
    r.left:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
    r.hl = CreateFrame("Frame", nil, r, BackdropTemplateMixin and "BackdropTemplate")
    r.hl:SetAllPoints(r)
    if r.hl.SetBackdrop then
        r.hl:SetBackdrop({ edgeFile = TEX_FLAT, edgeSize = 1 })
        local a = ns.COLORS.accent
        r.hl:SetBackdropBorderColor(a.r, a.g, a.b, 0.9)
    end
    r.hl:Hide()
    r:EnableMouse(true)
    r:EnableMouseWheel(true)
    r:SetScript("OnEnter", rowEnter)
    r:SetScript("OnLeave", function() UI:HideTooltip() end)
    r:SetScript("OnMouseWheel", function(_, delta) onWheel(delta) end)
    return r
end

layoutRows = function()
    if not win then return end
    local db  = mod.db
    local n   = rowSlots()
    local tex = texturePath()
    local step = db.barHeight + db.barGap
    for i = 1, n do
        local r = rows[i]
        if not r then
            r = createRow()
            rows[i] = r
        end
        r:SetStatusBarTexture(tex)
        local t = r:GetStatusBarTexture()
        if t and t.SetHorizTile then
            t:SetHorizTile(false)
            t:SetVertTile(false)
        end
        r:SetHeight(db.barHeight)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",  win.body, "TOPLEFT",  0, -((i - 1) * step))
        r:SetPoint("TOPRIGHT", win.body, "TOPRIGHT", 0, -((i - 1) * step))
        UI.FontFor("meter", r.left,  db.fontSize)
        UI.FontFor("meter", r.right, db.fontSize)
        r:Hide()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
end

------------------------------------------------------------------------
-- Refresh: sort once, paint the visible slots, update the title.
------------------------------------------------------------------------
local lastTitle, lastCount

local function setTitle(seg, first, lastIdx, n)
    local t = modeLabel(mode) .. " \194\183 " .. segmentLabel(seg)
    if t ~= lastTitle then
        win.titleText:SetText(t)
        lastTitle = t
    end
    local c = ""
    if n > 0 and n > (lastIdx - first + 1) then
        c = format("%d-%d / %d", first, lastIdx, n)
    end
    if c ~= lastCount then
        win.count:SetText(c)
        lastCount = c
    end
end

refresh = function()
    if not win then return end
    local db  = mod.db
    local seg = Meter:GetSegment(segment)
    local n   = 0
    local dur = 0
    if seg then
        dur = Meter:Duration(seg)
        for guid, p in pairs(seg.players) do
            n = n + 1
            order[n] = guid
            vals[guid] = valueOf(p, dur)
        end
    end
    for i = n + 1, #order do order[i] = nil end

    if n == 0 then
        for i = 1, #rows do rows[i]:Hide() end
        win.empty:Show()
        setTitle(seg, 0, 0, 0)
        return
    end
    win.empty:Hide()

    sort(order, byValue)
    local slots = rowSlots()
    local maxScroll = max(0, n - slots)
    if scroll > maxScroll then scroll = maxScroll end

    local total = 0
    for i = 1, n do total = total + vals[order[i]] end
    local top = vals[order[1]]
    local me  = Meter:PlayerGUID()

    for i = 1, slots do
        local r    = rows[i]
        local idx  = i + scroll
        local guid = order[idx]
        if r and guid then
            local p = seg.players[guid]
            local v = vals[guid]
            r:SetValue(top > 0 and v / top or 0)
            local c = ns.ClassColor(p.class)
            if c then
                r:SetStatusBarColor(c.r, c.g, c.b, 0.85)
            else
                r:SetStatusBarColor(0.6, 0.6, 0.6, 0.85)
            end
            if db.showRank then
                r.left:SetFormattedText("%d. %s", idx, p.name)
            else
                r.left:SetText(p.name)
            end
            r.right:SetText(rightText(p, v, total, dur))
            r.hl:SetShown(db.highlightSelf and guid == me)
            r.guid = guid
            r:Show()
        elseif r then
            r.guid = nil
            r:Hide()
        end
    end
    setTitle(seg, scroll + 1, min(scroll + slots, n), n)
end

------------------------------------------------------------------------
-- Ticker: only while a fight is open. Dirty -> full repaint; otherwise the
-- per-second modes still move with the clock.
------------------------------------------------------------------------
local function tick()
    if Meter:IsDirty() then
        Meter:ClearDirty()
        refresh()
    elseif mode == "dps" or mode == "hps" then
        refresh()
    end
end

local function startTicker()
    if ticker then return end
    ticker = ns:AddTicker(0.5, tick, nil, "meter-window")
end

local function stopTicker()
    if ticker then
        ns:CancelTicker(ticker)
        ticker = nil
    end
end

local function onEngine(what)
    if what == "start" then
        scroll = 0
        Meter:ClearDirty()
        refresh()
        startTicker()
        applyVisibility()
    elseif what == "end" then
        stopTicker()
        lastCombatEnd = GetTime()
        Meter:ClearDirty()
        refresh()
        applyVisibility()
        wipe(fmtCache)
        fmtCount = 0
    else
        scroll = 0
        Meter:ClearDirty()
        refresh()
    end
end

-- Stubs replaced in Task 5
onTitleWheel = function() end
openMenu     = function() end
```

WICHTIG zur Reihenfolge in der Datei: `applyVisibility` steht in Aufgabe 3 NACH dem Stummel-Block, wird aber in `onEngine` gebraucht. Das ist durch die Vorwärtsdeklaration (`local layoutRows, refresh, applyVisibility, ...` ganz oben) gedeckt: `onEngine` liest die Upvalue zur Laufzeit. Nichts umstellen.

- [ ] **Step 2: `WindowEnable` und `WindowDisable` erweitern** — in `mod:WindowEnable()` VOR `self:ApplyWindow()` einfügen:

```lua
    Meter:SetListener(onEngine)
```

und NACH `self:ApplyWindow()`:

```lua
    if Meter:InCombat() then startTicker() end
```

In `mod:WindowDisable()` die vier Zeilen `if ticker then ... end` durch `stopTicker()` ersetzen.

- [ ] **Step 3: Checker**

Run: `cd tools && node check.js`
Expected: `RESULT: OK`, keine ungenutzten Locals mehr außer `openMenu`/`onTitleWheel` als Stummel.

- [ ] **Step 4: Spielprüfung am Übungspuppen-Gegner** (`/reload`, angreifen): Nach dem ersten Treffer erscheint dein Balken in Klassenfarbe mit Akzent-Umrandung, Text `1. Name` links, rechts `12.3k (1.2k, 100.0%)`; der Wert steigt etwa alle halbe Sekunde. Nach dem Kampf bleibt der Balken stehen, Titel „Damage · Current fight". Überfahren zeigt den Tooltip mit Total, Per second, Share, Fight duration. Mit einem Begleiter (Jäger, Hexer): der Begleiterschaden landet auf deinem Balken, es gibt keinen zweiten. Mausrad über den Balken bei nur einem Eintrag tut nichts.

- [ ] **Step 5: Commit**

```bash
git add Modules/MeterWindow.lua
git commit -m "Combat Meter: Balkenzeilen -- je sichtbarem Platz ein wiederverwendeter Balken in Klassenfarbe mit Rang, Name, Wert und Klammer (pro Sekunde, Anteil), eigener Balken mit Akzentrahmen; Sortierung mit vorab angelegtem Vergleicher, gekuerzte Zahlen mit Zwischenspeicher, Tooltip mit Gesamt, pro Sekunde, Anteil, Ueberheilung und Kampfdauer; Mausrad scrollt; Halbsekunden-Ticker nur im Kampf, ausserhalb zeichnet der Listener einmal"
```

---

### Task 5: Klappmenü, Moduswechsel per Mausrad, Modus- und Abschnittsgriffe

**Files:**
- Modify: `Modules/MeterWindow.lua` (den Block `-- Stubs replaced in Task 5` ersetzen, `mod:SetMode`/`mod:SetSegment` ergänzen)

**Interfaces:**
- Consumes: `ns:ShowPopupMenu(entries, anchor, owner)` — Einträge `{ text=, func=, checked=fn, separator=true }` (Core/PopupMenu.lua).
- Produces: `mod:SetMode(m)`, `mod:SetSegment(s)` (Aufgabe 6 nutzt sie nicht, aber die Titelzeile und das Menü).

- [ ] **Step 1: Stummel ersetzen** — den Block `-- Stubs replaced in Task 5` mit seinen zwei Zeilen durch Folgendes ersetzen:

```lua
------------------------------------------------------------------------
-- Mode / segment switching and the title menu
------------------------------------------------------------------------
function mod:SetMode(m)
    if not MODE_IDX[m] then return end
    mode   = m
    scroll = 0
    refresh()
end

function mod:SetSegment(s)
    segment = (s == "overall") and "overall" or "current"
    scroll  = 0
    refresh()
end

-- Wheel up = previous mode, wheel down = next, wrapping around.
onTitleWheel = function(delta)
    local i = MODE_IDX[mode] - delta
    if i < 1 then i = #MODES elseif i > #MODES then i = 1 end
    mod:SetMode(MODES[i])
end

local function isMode(m)    return function() return mode == m end end
local function setMode(m)   return function() mod:SetMode(m) end end

local function menuEntries()
    local e = {}
    for i = 1, #MODES do
        local m = MODES[i]
        e[#e + 1] = { text = modeLabel(m), checked = isMode(m), func = setMode(m) }
    end
    e[#e + 1] = { separator = true }
    e[#e + 1] = { text = L["Current fight"],
                  checked = function() return segment == "current" end,
                  func = function() mod:SetSegment("current") end }
    e[#e + 1] = { text = L["Overall"],
                  checked = function() return segment == "overall" end,
                  func = function() mod:SetSegment("overall") end }
    e[#e + 1] = { separator = true }
    e[#e + 1] = { text = L["Reset"], func = function() Meter:Reset() end }
    return e
end

openMenu = function()
    ns:ShowPopupMenu(menuEntries(), "cursor", win.title)
end
```

- [ ] **Step 2: Checker**

Run: `cd tools && node check.js`
Expected: `RESULT: OK`, keine ungenutzten Locals.

- [ ] **Step 3: Spielprüfung**: Linksklick auf den Titel öffnet das Menü mit vier Modi (Häkchen am aktiven), zwei Abschnitten, Reset. Mausrad auf dem Titel wechselt den Modus und der Titeltext folgt. „Overall" zeigt die Summe mehrerer Kämpfe; Reset leert beides und zeigt „No combat data". Im Modus DPS steht der Sekundenwert vorn, die Klammer zeigt den Gesamtwert.

- [ ] **Step 4: Commit**

```bash
git add Modules/MeterWindow.lua
git commit -m "Combat Meter: Klappmenue am Titel mit Modi, Abschnitten und Zuruecksetzen; Mausrad auf der Titelzeile wechselt den Modus zyklisch; Griffe SetMode und SetSegment"
```

---

### Task 6: Optionsseite

**Files:**
- Create: `Modules/MeterOptions.lua`
- Modify: `VuloClassicUI.toc` und `VuloClassicUI_Vanilla.toc` (Zeile `Modules\MeterOptions.lua` nach `Modules\MeterWindow.lua`)

**Interfaces:**
- Consumes: `mod:ApplyWindow()` (Aufgabe 3), `ns.MediaStatusbarValues()` → `{ { value=, text= }, ... }`, `ns:IsMoverEditMode()`/`ns:SetMoversEditMode(state)`, `ns.UI:RebuildCurrentPage()`, `ns:IsModuleEnabled`/`ns:ToggleModule`.
- Produces: `mod:GetOptions()`.

- [ ] **Step 1: `Modules/MeterOptions.lua` schreiben**

```lua
-- VuloClassicUI / Modules / MeterOptions: options page for the combat meter.
-- The module description (rendered by the options builder) already carries
-- the usage hints, so the page starts with the enable switch.
local _, ns = ...
local L   = ns.L
local mod = ns.modules.meter

local function apply()
    if mod.ApplyWindow then mod:ApplyWindow() end
end

local function refreshPage()
    if ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
end

local function modeValues()
    return {
        { value = "damage", text = L["Damage"] },
        { value = "dps",    text = L["DPS"] },
        { value = "heal",   text = L["Healing"] },
        { value = "hps",    text = L["HPS"] },
    }
end

local function segmentValues()
    return {
        { value = "current", text = L["Current fight"] },
        { value = "overall", text = L["Overall"] },
    }
end

local function toggle(label, key, tooltip)
    return {
        type = "toggle", label = label, tooltip = tooltip,
        get = function() return mod.db[key] end,
        set = function(_, v) mod.db[key] = v; apply() end,
    }
end

function mod:GetOptions()
    local items = {}

    items[#items + 1] = { type = "toggle", label = L["Enable combat meter"],
        get = function() return ns:IsModuleEnabled("meter") end,
        set = function(_, v) ns:ToggleModule("meter", v) end }

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Display"] }
    items[#items + 1] = { type = "slider", label = L["Bar height"], min = 12, max = 30, step = 1,
        get = function() return mod.db.barHeight end,
        set = function(_, v) mod.db.barHeight = v; apply() end }
    items[#items + 1] = { type = "slider", label = L["Font size"], min = 8, max = 16, step = 1,
        get = function() return mod.db.fontSize end,
        set = function(_, v) mod.db.fontSize = v; apply() end }
    items[#items + 1] = { type = "dropdown", label = L["Texture"], width = 240,
        values = ns.MediaStatusbarValues(),
        get = function() return mod.db.texture end,
        set = function(_, v) mod.db.texture = v; apply() end }
    items[#items + 1] = { type = "slider", label = L["Scale"], min = 50, max = 200, step = 5,
        get = function() return math.floor((mod.db.scale or 1) * 100 + 0.5) end,
        set = function(_, v) mod.db.scale = v / 100; apply() end }
    items[#items + 1] = toggle(L["Show rank"], "showRank")
    items[#items + 1] = toggle(L["Show value in brackets"], "showPerSecond",
        L["Per-second value next to the total. In the per-second modes the brackets show the total instead."])
    items[#items + 1] = toggle(L["Show percent"], "showPercent")
    items[#items + 1] = toggle(L["Highlight your own bar"], "highlightSelf")

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Visibility"] }
    items[#items + 1] = toggle(L["Only in group"], "onlyInGroup")
    items[#items + 1] = toggle(L["Hide in combat"], "hideInCombat")
    items[#items + 1] = {
        type = "toggle", label = L["Hide out of combat"],
        get = function() return mod.db.hideOutOfCombat end,
        set = function(_, v) mod.db.hideOutOfCombat = v; apply() end,
        subOptions = {
            { type = "slider", label = L["Hide delay (seconds)"], min = 0, max = 60, step = 1,
              get = function() return mod.db.hideDelay end,
              set = function(_, v) mod.db.hideDelay = v; apply() end },
        },
    }

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Behavior"] }
    items[#items + 1] = { type = "dropdown", label = L["Default mode"], width = 200,
        values = modeValues(),
        get = function() return mod.db.defaultMode end,
        set = function(_, v) mod.db.defaultMode = v end }
    items[#items + 1] = { type = "dropdown", label = L["Default segment"], width = 200,
        values = segmentValues(),
        get = function() return mod.db.defaultSegment end,
        set = function(_, v) mod.db.defaultSegment = v end }
    items[#items + 1] = toggle(L["Reset overall when joining a new group"], "resetOnNewGroup")

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Position"] }
    items[#items + 1] = {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", width = 180,
              label = ns:IsMoverEditMode() and L["Stop moving"] or L["Unlock / Move"],
              onClick = function()
                  ns:SetMoversEditMode(not ns:IsMoverEditMode())
                  refreshPage()
              end },
            { type = "button", width = 150, label = L["Reset position"],
              onClick = function()
                  mod.db.x, mod.db.y = 0, 0
                  apply()
              end },
        },
    }

    return items
end
```

- [ ] **Step 2: TOC-Zeile** `Modules\MeterOptions.lua` in BEIDEN TOC-Dateien nach `Modules\MeterWindow.lua`.

- [ ] **Step 3: Beide Checker**

Run: `cd tools && node check.js && node optcheck.cjs`
Expected: beide `OK`; optcheck meldet keine Zahnrad-Falle (nur ein `subOptions`, nicht in einer Reihen-Gruppe, Beschriftung eindeutig).

- [ ] **Step 4: Spielprüfung**: `/vcui`, Seite „Combat Meter" unter HUD. Balkenhöhe und Schriftgröße greifen sofort, Textur-Wechsel ebenso, Skalierung über den Regler und im Bearbeiten-Modus über den Mover-Regler stimmen überein. „Hide out of combat" mit Nachlauf 3: Fenster verschwindet drei Sekunden nach Kampfende, erscheint beim nächsten Kampfbeginn. „Unlock / Move" öffnet den Bearbeiten-Modus, Beschriftung wechselt auf „Stop moving". „Reset position" zentriert das Fenster.

- [ ] **Step 5: Commit**

```bash
git add Modules/MeterOptions.lua VuloClassicUI.toc VuloClassicUI_Vanilla.toc
git commit -m "Combat Meter: Optionsseite -- Anzeige (Balkenhoehe, Schriftgroesse, Textur, Skalierung, vier flache Schalter), Sichtbarkeit (Nachlaufzeit hinter dem Zahnrad), Verhalten (Standardmodus und -abschnitt als Klappmenue, Zuruecksetzen bei neuer Gruppe), Position"
```

---

### Task 7: Sprachdateien, Seitenleisten-Symbol, Changelog, Graph

**Files:**
- Modify: `Locales/deDE.lua`, `esES.lua`, `frFR.lua`, `itIT.lua`, `koKR.lua`, `ptBR.lua`, `ruRU.lua`, `zhCN.lua`, `zhTW.lua`
- Create: `Media/Icons/modules/meter.tga`
- Modify: `CHANGELOG.md`, `Modules/ChangelogData.lua` (generiert), `tools/make_module_icons.js` (MAP-Eintrag)

**Interfaces:**
- Consumes: Vorgehensweisen `locale-translate` (Schlüsselliste → neun Sprachdateien mit validierendem Merge), `make-icon` (Lucide → echtes 32-Bit-TGA), `changelog` (Hausformat, Versionshinweise, Locale-Einträge).
- Produces: alle neuen `L[]`-Schlüssel in neun Sprachen; `meter.tga`; Changelog-Eintrag für die nächste Version.

- [ ] **Step 1: Schlüsselliste anlegen** — `keys.txt` im Scratchpad mit genau diesen Zeilen (das sind alle neuen `L[]`-Stellen aus Aufgabe 1 bis 6; die schon vorhandenen Schlüssel `Healing`, `Display`, `Scale`, `Reset`, `Unlock / Move`, `Stop moving`, `Font size`, `Visibility`, `Position`, `Total`, `Texture`, `Behavior`, `Bar height`, `Reset position` stehen NICHT darin):

```
Combat Meter
Lightweight damage and healing meter: who did how much, per fight and overall. Left-click the title for mode and segment, mouse wheel on the title cycles modes, right-drag the title to move.
Damage
DPS
HPS
Overall
Current fight
No combat data
Mode, segment and reset
Per second
Share
Overhealing
Fight duration
Enable combat meter
Show rank
Show value in brackets
Per-second value next to the total. In the per-second modes the brackets show the total instead.
Show percent
Highlight your own bar
Only in group
Hide in combat
Hide out of combat
Hide delay (seconds)
Default mode
Default segment
Reset overall when joining a new group
```

Vor dem Übersetzen jeden Schlüssel gegen `Locales/deDE.lua` prüfen (`grep -n '^\s*\["<key>"\]'`); ein Treffer heißt: Zeile aus der Liste streichen. Die tote Schlüsselliste (`docs/` oder Gedächtnis „Tote Sprachschlüssel") ebenfalls prüfen: ein dort gelöschter Schlüssel darf nicht als Neu-Übersetzung zurückkommen, wenn die alte Übersetzung im Git-Verlauf liegt (`git log -S'["Damage"]' -- Locales/deDE.lua`).

- [ ] **Step 2: Vorgehensweise `locale-translate` mit der Schlüsselliste ausführen** — Ergebnis: neun Sprachdateien mit je genau so vielen neuen Zeilen wie Schlüssel in der Liste; `node tools/check.js` meldet keinen unerreichbaren Schlüssel.

- [ ] **Step 3: Symbol** — in `tools/make_module_icons.js` in `MAP` eintragen:

```js
  meter:              'chart-bar-big',
```

Dann Vorgehensweise `make-icon` für den Modulschlüssel `meter` ausführen (erzeugt `Media/Icons/modules/meter.tga`, echtes 32-Bit-TGA, weiß auf transparent, 64 px). Existiert `chart-bar-big` in Lucide nicht, `chart-bar` nehmen. Im Spiel: Seitenleiste zeigt das Symbol neben „Combat Meter"; ein leeres Feld heißt PNG-in-TGA (siehe Texturregeln), dann neu erzeugen.

- [ ] **Step 4: Changelog** — Vorgehensweise `changelog` mit diesem Inhalt (Hausformat, keine Fremd-Addon-Namen):

Neues Modul **Combat Meter** (HUD): leichtgewichtiges Schadens- und Heilungsmeter. Zählt Schaden und Heilung je Gruppenmitglied, Begleiter beim Besitzer, Überheilung getrennt; zwei Abschnitte (aktueller Kampf, gesamt), „gesamt" überlebt /reload; Kampfabschnitte gruppenweit mit Bossnamen aus den Begegnungs-Ereignissen; festes Balkenfenster mit vier Modi, Klappmenü am Titel, Mausrad zum Scrollen und Moduswechsel, Tooltip je Balken; Optionsseite mit Anzeige, Sichtbarkeit, Verhalten, Position.

- [ ] **Step 5: Checker und Graph**

Run: `cd tools && node check.js && node optcheck.cjs && cd .. && graphify update .`
Expected: beide `OK`; Graph aktualisiert.

- [ ] **Step 6: Commit**

```bash
git add Locales/ Media/Icons/modules/meter.tga tools/make_module_icons.js CHANGELOG.md Modules/ChangelogData.lua graphify-out/
git commit -m "Combat Meter: 26 neue Texte in allen neun Sprachen, Seitenleisten-Symbol, Changelog-Eintrag"
```

---

### Task 8: Gegenprüfung und Schlachtzugs-Messung

**Files:**
- Modify: nur, was die Gegenprüfung als CONFIRMED meldet.

- [ ] **Step 1: Vorgehensweise `adversarial-review`** über `Modules/Meter.lua`, `Modules/MeterWindow.lua`, `Modules/MeterOptions.lua` mit dieser Angriffsliste:

1. `onCLEU` mit einem Unterereignis ohne `a15` (z. B. `SWING_MISSED`): kein Eintrag in `HANDLERS`, kein Zugriff — stimmt das für JEDEN Eintrag der Tabelle?
2. `entry()` ohne vorheriges `resolve()`: gibt es einen Aufrufer, der `roster[guid]` nicht garantiert?
3. `waitTick` schließt den Abschnitt und bricht den eigenen Ticker ab — der Treiber in `Core/Schedule.lua` verträgt Selbst-Abbruch (Kommentar dort), aber wird `waitTicker` danach `nil`, so dass `beginWait` wieder starten kann?
4. `ENCOUNTER_START` ohne vorherigen Kampf, `ENCOUNTER_END` ohne Start, `ENCOUNTER_END` gefolgt von `PLAYER_REGEN_ENABLED`: kein doppeltes Schließen, kein leerer Zweitabschnitt.
5. `Meter:Reset()` im Kampf: `current` bleibt offen mit neuer Startzeit; das Fenster zeigt keinen Zustand mit `order` voller alter GUIDs.
6. `refresh()` mit `rows[i] == nil` (Fenster kleiner als ein Balken, `rowSlots()` liefert 1, `layoutRows` noch nicht gelaufen): der `if r and guid`-Zweig deckt das ab — auch der Leer-Zweig?
7. Profilwechsel: `mod.db` zeigt auf eine neue Tabelle; `build()` hat `db` als Upvalue eingefangen und gibt es dem Mover als `opts.db`. Der Mover liest danach die alte Tabelle — dasselbe Verhalten wie bei allen Modulen mit `ns:CreateMover` (Taschen, Aktionsleisten), also kein Fund, sofern `build()` selbst sonst nirgends `db` nach dem Aufbau liest. Prüfen: `win:SetSize(db.width, db.height)` läuft nur einmal beim Aufbau, `ApplyWindow` nimmt `self.db`. Der Größengriff und `savePosition()` schreiben in `mod.db`.
8. `UNIT_PET` für eine Einheit, die nicht in `PET_UNIT` steht (`target`, `focus`): wird verworfen?
9. `hideOutOfCombat` mit `hideDelay = 0`: `left` ist negativ, sofort versteckt, kein Timer.
10. `short()` mit negativen Zahlen (Schaden ist nie negativ, aber `valueOf` bei `heal - overheal` könnte durch fehlerhafte Protokolldaten negativ werden): `floor` funktioniert, `tostring` liefert `-12`; die Balkenlänge `v / top` bei `top <= 0` ist 0 — bestätigen.
11. Fremd-Addon-Namen: `grep -rn` über die drei Dateien mit der `FORBIDDEN`-Regex aus `tools/check.js`.

CONFIRMED-Funde beheben, Checker erneut laufen lassen, committen mit Botschaft „Combat Meter: Gegenpruefungs-Fixes -- <Liste>".

- [ ] **Step 2: Schlachtzugs-Messung** (Spielprüfung Stufe 3, kann der Nutzer erst später machen): Profiler aktivieren (Gedächtnis „Messen im Spiel"), einen Bosskampf mit 25 Spielern, danach Modulkosten je Ereignis vergleichen: `meter` muss unter `combattext` liegen. Bossname erscheint im Titel, Abschnitt schließt beim Begegnungsende sofort. Mausrad über 25 Einträge zeigt „8-14 / 25" im Titel.

- [ ] **Step 3: Gedächtnis** — `open-next-session.md` aktualisieren: Combat Meter Teil 1 gebaut, Spielprüfung Stufe 1–3 offen/erledigt, Teil 2 (Aufschlüsselung) als Nächstes.
