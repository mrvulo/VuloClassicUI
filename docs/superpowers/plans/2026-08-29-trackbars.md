# Trackbars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein Datenleisten-Modul „Trackbars": beliebig viele vom Nutzer erstellte Infoleisten (Uhr, Gold, EP/Ruf, FPS, Latenz, Haltbarkeit, Taschenplätze, Zone/Koordinaten, Mikromenü, Abstandshalter), erstellt aus Vorlagen-Karten, konfiguriert über eine eigene Optionsseite.

**Architecture:** Drei Dateien nach dem Muster Runtime/Blocks/Options (wie Nameplates + NameplatesOptions): `Modules/Trackbars.lua` (Engine: Leisten-Frames, Layout, Herzschlag, Block-Registry, Vorlagen), `Modules/TrackbarsBlocks.lua` (Block-Fabriken), `Modules/TrackbarsOptions.lua` (Optionsseite über `mod.optionsBridge`). Updates laufen über einen geteilten 1-Sekunden-Herzschlag plus Events — **kein OnUpdate im Renderpfad**. Blöcke werden in drei Eimern (links/zentriert/rechts) gepackt; das Mikromenü nutzt Secure-Klick-Umleitung auf Blizzards echte Mikroknöpfe.

**Tech Stack:** VuloClassicUI-Hausgerüst (`ns:RegisterModule`, `ns:CreateMover`, `UI:BuildOptionsPage`, `UI.FontFor`, `UI:StyleBackdrop`-Farben), Anniversary-Client 20505 (TBC).

## Global Constraints

- **Namensregel:** Die Referenz-Addons werden NIRGENDS genannt — nicht in Code, Kommentaren, Locale, Commits, Docs. `node tools/check.js` prüft das (Abschnitt „third-party addon names").
- **Modulschlüssel:** `trackbars`, Anzeigename `Trackbars`, Gruppe `HUD`, `enabled = false` (Opt-in wie SwingTimer).
- **Kein OnUpdate** an Leisten oder Blöcken; Aktualisierung nur über den geteilten 1s-Herzschlag und Events. Relayout wird über `C_Timer.After(0, …)` auf eins pro Frame zusammengefasst.
- **Taint:** Zauberbuch/Talente/Questlog NIE über Lua-Funktionsaufruf öffnen (`ToggleSpellBook` aus unserem Stack verseucht `SpellBookFrame.bookType` → `CastSpell` verweigert bis /reload, dokumentiert in [Modules/ActionBars.lua:918-925](../../Modules/ActionBars.lua)). Stattdessen Secure-Klick-Umleitung: `SecureActionButtonTemplate` mit `*type1 = "click"` und `*clickbutton1 = <BlizzKnopf>`. Secure-Knöpfe nur außerhalb des Kampfes erstellen, im Lockdown zurückstellen und bei `PLAYER_REGEN_ENABLED` nachholen.
- **Schrift:** immer `ns.UI.FontFor("trackbars", fs, size, flags)` — nie `SetFont` direkt, damit die Modul-Schriftübersteuerung (v1.57) greift.
- **Farben:** `ns.COLORS.accent` zur Laufzeit lesen, nie `9b6cff` als Literal in Code.
- **Locale:** englische Schlüssel `L["…"]`, deutsche Werte in `Locales/deDE.lua` — deutsche Werte ohne rohes ASCII-`"` (nur „ " oder '). `L[...]` nie auf Dateiebene auswerten — Beschriftungstabellen lazy in Funktionen bauen.
- **Git:** Der Baum enthält UNCOMMITTETE fremde Änderungen (Performance-Sweep über 13 Dateien). Jeder Commit addet AUSSCHLIESSLICH die im Task genannten Dateien per explizitem Pfad, niemals `git add -A` oder `git add .`.
- **Verifikation je Task:** `node tools/check.js` muss grün sein; nach Codeänderungen `graphify update .`. In-Game-Prüfung (per `/reload` + `/run`-Sonden ≤255 Zeichen) ist dem Nutzer vorbehalten — die Sonden werden im Task notiert.
- **Optionsseiten-Hausregeln:** Symbolstreifen rechts reserviert (feste Plätze für Zahnrad und ⓘ); die einzige Aufklapp-Mechanik ist das Zahnrad an der Zeile; Mehrfachauswahl = Klappmenü (`dropdown`), keine Knopfreihen.

---

### Task 1: Engine-Grundgerüst (Leisten-Frames, DB, Mover, Herzschlag)

**Files:**
- Create: `Modules/Trackbars.lua`
- Modify: `VuloClassicUI.toc` (drei Zeilen nach `Modules\SwingTimer.lua`, Zeile 63)

**Interfaces:**
- Produces: `ns.modules.trackbars` mit `mod.db` (Profil-Tabelle), `mod.BarCfg(id) -> cfg|nil`, `mod.EnsureBarFrame(cfg) -> frame`, `mod.ApplyBar(id)`, `mod.ApplyAll()`, `mod.RequestLayout(id)`, `mod.RegisterHeartbeat(key, fn)`, `mod.UnregisterHeartbeat(key)`, `mod.optionsBridge = {}` (Task 7 füllt ihn).
- DB-Schema (Profil, `db = ns.db.profile.modules.trackbars`):

```lua
defaults = {
    enabled   = false,
    nextBarId = 1,
    bars      = {},   -- Array von Leisten-Tabellen (siehe unten)
}
-- Leisten-Schema (angelegt von mod.NewBarCfg in Task 6, hier verbindlich):
-- { id=1, name="Leiste 1",
--   lengthMode="custom"|"full", length=400, thickness=26,
--   edge="bottom"|"top", edgeOffset=0,      -- nur lengthMode="full"
--   x=0, y=-200,                            -- nur lengthMode="custom" (Mover, CENTER-Offsets)
--   sizingMode="auto"|"even", fontScale=100,
--   bg={r=0.05,g=0.05,b=0.06,a=0.90}, hideBorder=false,
--   mouseoverOnly=false, strata="MEDIUM",
--   nextBlockId=1, blocks={} }
```

- [ ] **Step 1: Moduldatei mit Registrierung, Herzschlag und Leisten-Frame-Bau schreiben**

```lua
-- VuloClassicUI / Modules / Trackbars: Engine der Datenleisten. Leisten-Frames,
-- Layout und der geteilte Herzschlag. Block-Fabriken: TrackbarsBlocks.lua,
-- Optionsseite: TrackbarsOptions.lua (liest mod.optionsBridge, laedt danach).
local _, ns = ...
local L  = ns.L
local UI = ns.UI

local mod = ns:RegisterModule("trackbars", {
    name        = "Trackbars",
    group       = "HUD",
    description = "User-built info bars: clock, gold, XP, micro menu and more.",
    defaults    = {
        enabled   = false,
        nextBarId = 1,
        bars      = {},
    },
})

mod.optionsBridge = {}
mod.BlockFactories = {}   -- typeKey -> function(blockCfg, slot, content, bar) -> inst

-- Geteilter 1s-Herzschlag: existiert nur solange Zuhoerer existieren.
local hbListeners, hbTicker = {}, nil
local function hbTick()
    for _, fn in pairs(hbListeners) do pcall(fn) end
end
function mod.RegisterHeartbeat(key, fn)
    hbListeners[key] = fn
    if not hbTicker then hbTicker = C_Timer.NewTicker(1, hbTick) end
end
function mod.UnregisterHeartbeat(key)
    hbListeners[key] = nil
    if hbTicker and not next(hbListeners) then hbTicker:Cancel(); hbTicker = nil end
end

function mod.BarCfg(id)
    for _, cfg in ipairs(mod.db.bars) do
        if cfg.id == id then return cfg end
    end
end

-- id -> { frame=Frame, insts={blockId->inst}, slots={blockId->slot} }
local barRecs = {}
mod._barRecs = barRecs   -- fuer Blocks/Options

local function applyBarPosition(cfg, f)
    f:ClearAllPoints()
    if cfg.lengthMode == "full" then
        local edge = (cfg.edge == "top") and "TOP" or "BOTTOM"
        local off  = cfg.edgeOffset or 0
        f:SetPoint(edge .. "LEFT",  UIParent, edge .. "LEFT",  0, (edge == "TOP") and -off or off)
        f:SetPoint(edge .. "RIGHT", UIParent, edge .. "RIGHT", 0, (edge == "TOP") and -off or off)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or 0)
        f:SetWidth(cfg.length or 400)
    end
    f:SetHeight(cfg.thickness or 26)
end

function mod.EnsureBarFrame(cfg)
    local rec = barRecs[cfg.id]
    if not rec then
        local f = CreateFrame("Frame", "VuloTrackbar" .. cfg.id, UIParent)
        f:EnableMouse(false)         -- die Leiste selbst faengt nie Maus
        f:SetClampedToScreen(true)
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints(f)
        f.border = f:CreateTexture(nil, "OVERLAY", nil, 7)
        rec = { frame = f, insts = {}, slots = {} }
        barRecs[cfg.id] = rec
    end
    local f = rec.frame
    f:SetFrameStrata(cfg.strata or "MEDIUM")
    local c = cfg.bg or {}
    f.bg:SetColorTexture(c.r or 0.05, c.g or 0.05, c.b or 0.06, c.a or 0.90)
    -- 1px-Rahmen unten+oben als zwei Linien waere teurer; eine umlaufende
    -- 1px-Kante via SetBackdrop auf einem Kind-Frame:
    if not f.edgeFrame then
        f.edgeFrame = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate")
        f.edgeFrame:SetAllPoints(f)
        if f.edgeFrame.SetBackdrop then
            f.edgeFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        end
    end
    if f.edgeFrame.SetBackdropBorderColor then
        local b = ns.COLORS and ns.COLORS.border or { r = 0, g = 0, b = 0 }
        f.edgeFrame:SetBackdropBorderColor(b.r or 0, b.g or 0, b.b or 0, cfg.hideBorder and 0 or 0.8)
    end
    applyBarPosition(cfg, f)
    -- Mover nur fuer frei stehende Leisten; Vollbreite wird ueber edge/edgeOffset gestellt
    if cfg.lengthMode ~= "full" and not f.mover then
        f.mover = ns:CreateMover(f, {
            key   = "trackbars" .. cfg.id,
            label = "|cffffffff" .. (cfg.name or ("Trackbar " .. cfg.id)) .. "|r",
            db    = cfg,
        })
    end
    f:Show()
    return f
end

function mod.ApplyAll()
    for _, cfg in ipairs(mod.db.bars) do mod.ApplyBar(cfg.id) end
    -- verwaiste Frames (geloeschte Leisten) verstecken
    for id, rec in pairs(barRecs) do
        if not mod.BarCfg(id) then rec.frame:Hide() end
    end
end

function mod:OnEnable()
    mod.ApplyAll()
end

function mod:OnDisable()
    for _, rec in pairs(barRecs) do rec.frame:Hide() end
    for key in pairs(hbListeners) do mod.UnregisterHeartbeat(key) end
end
```

`mod.ApplyBar` ist in diesem Task ein Platzhalter, der nur `EnsureBarFrame` ruft (Task 2 ersetzt ihn durch den echten Abgleich):

```lua
function mod.ApplyBar(id)
    local cfg = mod.BarCfg(id)
    if not cfg then return end
    mod.EnsureBarFrame(cfg)
end
function mod.RequestLayout(id) end   -- Task 2 fuellt das
```

- [ ] **Step 2: TOC erweitern** — nach `Modules\SwingTimer.lua` (Zeile 63) einfügen:

```
Modules\Trackbars.lua
Modules\TrackbarsBlocks.lua
Modules\TrackbarsOptions.lua
```

(Die zwei noch nicht existierenden Dateien in diesem Task als Ein-Zeilen-Stubs `local _, ns = ...` anlegen, damit der Client nicht über fehlende Dateien meckert.)

- [ ] **Step 3: check.js laufen lassen**

Run: `node tools/check.js`
Expected: grün, keine neuen Warnungen.

- [ ] **Step 4: Commit (nur die Task-Dateien!)**

```bash
git add Modules/Trackbars.lua Modules/TrackbarsBlocks.lua Modules/TrackbarsOptions.lua VuloClassicUI.toc
git commit -m "Trackbars: Engine-Grundgeruest -- Leisten-Frames, Herzschlag, Mover"
```

In-Game-Sonde (für den Nutzer, nicht blockierend):
`/run local m=VuloClassicUI and VuloClassicUI.modules.trackbars; table.insert(m.db.bars,{id=1,lengthMode="custom",length=400,thickness=26,x=0,y=-200,blocks={},nextBlockId=1}); m.ApplyAll()`
→ dunkle 400×26-Leiste in Bildschirmmitte unterhalb der Mitte.

---

### Task 2: Layout (Eimer links/zentriert/rechts), Block-Slots, Block-API

**Files:**
- Modify: `Modules/Trackbars.lua`

**Interfaces:**
- Consumes: `mod.EnsureBarFrame`, `mod._barRecs`, `mod.BlockFactories` aus Task 1.
- Produces (verbindlich für Tasks 3–7):
  - Block-Fabrik-Vertrag: `mod.BlockFactories[typeKey] = function(blockCfg, slot, content, bar) -> inst`; Instanzmethoden `inst:Refresh()`, `inst:Enable()`, `inst:Disable()` (idempotent), `inst:GetAutoLength() -> px` (**0 = eingeklappt**, wird nicht gelayoutet), optional `inst:Destroy()`.
  - `mod.AddBlock(barId, typeKey) -> blockCfg`, `mod.RemoveBlock(barId, blockId)`, `mod.MoveBlock(barId, blockId, delta)` (delta ±1, innerhalb des Arrays), `mod.BlockCfg(barId, blockId)`.
  - `mod.BLOCK_TYPES` = geordnetes Array `{ key, label() }` und `mod.BLOCK_DEFAULTS[typeKey]` = `settings`-Saat.
  - Block-Schema: `{ id, type, side="left"|"center"|"right", gap=10, scale=100, color=nil, useAccent=false, settings={...} }`.
  - `mod.RequestLayout(barId)` — koalesziert auf einen Durchlauf pro Frame.

- [ ] **Step 1: Block-Verwaltung und Layout implementieren**

```lua
mod.BLOCK_DEFAULTS = {}   -- TrackbarsBlocks.lua traegt je Typ ein
mod.BLOCK_TYPES    = {}   -- dito: { key="clock", label=function() return L["Clock"] end }

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = deepCopy(v) end
    return r
end

function mod.BlockCfg(barId, blockId)
    local cfg = mod.BarCfg(barId)
    if not cfg then return end
    for i, b in ipairs(cfg.blocks) do
        if b.id == blockId then return b, i end
    end
end

function mod.AddBlock(barId, typeKey)
    local cfg = mod.BarCfg(barId)
    if not (cfg and mod.BlockFactories[typeKey]) then return end
    local b = {
        id = cfg.nextBlockId, type = typeKey, side = "left",
        gap = 10, scale = 100,
        settings = deepCopy(mod.BLOCK_DEFAULTS[typeKey] or {}),
    }
    cfg.nextBlockId = cfg.nextBlockId + 1
    table.insert(cfg.blocks, b)
    mod.ApplyBar(barId)
    return b
end

function mod.RemoveBlock(barId, blockId)
    local cfg = mod.BarCfg(barId)
    if not cfg then return end
    for i, b in ipairs(cfg.blocks) do
        if b.id == blockId then table.remove(cfg.blocks, i); break end
    end
    mod.ApplyBar(barId)
end

function mod.MoveBlock(barId, blockId, delta)
    local cfg = mod.BarCfg(barId)
    if not cfg then return end
    local _, i = mod.BlockCfg(barId, blockId)
    local j = i and (i + delta)
    if not (i and j and j >= 1 and j <= #cfg.blocks) then return end
    cfg.blocks[i], cfg.blocks[j] = cfg.blocks[j], cfg.blocks[i]
    mod.RequestLayout(barId)
end
```

Slots + Abgleich (ersetzt den Task-1-Platzhalter von `mod.ApplyBar`):

```lua
local function ensureSlot(rec, b)
    local slot = rec.slots[b.id]
    if not slot then
        slot = CreateFrame("Frame", nil, rec.frame)
        slot.content = CreateFrame("Frame", nil, slot)
        slot.content:SetPoint("CENTER")
        rec.slots[b.id] = slot
    end
    slot:SetHeight(rec.frame:GetHeight())
    slot.content:SetScale((b.scale or 100) / 100)
    return slot
end

function mod.ApplyBar(id)
    local cfg = mod.BarCfg(id)
    if not cfg then return end
    local rec = barRecs[cfg.id] or {}
    mod.EnsureBarFrame(cfg)
    rec = barRecs[cfg.id]
    -- 1) Abriss: Instanzen, deren Block weg ist oder den Typ wechselte
    for blockId, inst in pairs(rec.insts) do
        local b = mod.BlockCfg(id, blockId)
        if not b or b.type ~= inst._type then
            inst:Disable()
            if inst.Destroy then inst:Destroy() end
            rec.insts[blockId] = nil
            if rec.slots[blockId] then rec.slots[blockId]:Hide() end
        end
    end
    -- 2) Aufbau: fehlende Instanzen erzeugen
    for _, b in ipairs(cfg.blocks) do
        if not rec.insts[b.id] then
            local factory = mod.BlockFactories[b.type]
            if factory then
                local slot = ensureSlot(rec, b)
                slot:Show()
                local inst = factory(b, slot, slot.content, cfg)
                inst._type = b.type
                rec.insts[b.id] = inst
                inst:Enable()
                inst:Refresh()
            end
        end
    end
    mod.RequestLayout(id)
end
```

Layout — Eimer-Packung, koalesziert:

```lua
local pendingLayout = {}
function mod.RequestLayout(barId)
    if pendingLayout[barId] then return end
    pendingLayout[barId] = true
    C_Timer.After(0, function()
        pendingLayout[barId] = nil
        mod.LayoutBar(barId)
    end)
end

function mod.LayoutBar(barId)
    local cfg, rec = mod.BarCfg(barId), barRecs[barId]
    if not (cfg and rec) then return end
    local f = rec.frame
    local W = f:GetWidth()
    if not W or W < 1 then return end

    -- sichtbare Blocks mit Breite einsammeln (Reihenfolge = Array-Reihenfolge)
    local buckets = { left = {}, center = {}, right = {} }
    for _, b in ipairs(cfg.blocks) do
        local inst, slot = rec.insts[b.id], rec.slots[b.id]
        if inst and slot then
            local len = inst:GetAutoLength() or 0
            if len > 0 then
                local w = len * ((b.scale or 100) / 100) + (b.gap or 10)
                table.insert(buckets[b.side or "left"], { b = b, slot = slot, w = w })
            else
                slot:Hide()
            end
        end
    end

    if cfg.sizingMode == "even" then
        -- Gleichverteilung ueber ALLE sichtbaren Blocks in Array-Reihenfolge
        local all = {}
        for _, side in ipairs({ "left", "center", "right" }) do
            for _, e in ipairs(buckets[side]) do table.insert(all, e) end
        end
        local n = #all
        if n == 0 then return end
        local share = W / n
        for i, e in ipairs(all) do
            e.slot:Show(); e.slot:ClearAllPoints()
            e.slot:SetWidth(share)
            e.slot:SetPoint("LEFT", f, "LEFT", (i - 1) * share, 0)
        end
        return
    end

    -- auto: links vorwaerts, rechts rueckwaerts, Mitte zentriert als Gruppe
    local x = 0
    for _, e in ipairs(buckets.left) do
        e.slot:Show(); e.slot:ClearAllPoints()
        e.slot:SetWidth(e.w)
        e.slot:SetPoint("LEFT", f, "LEFT", x, 0)
        x = x + e.w
    end
    local xr = 0
    for i = #buckets.right, 1, -1 do
        local e = buckets.right[i]
        e.slot:Show(); e.slot:ClearAllPoints()
        e.slot:SetWidth(e.w)
        e.slot:SetPoint("RIGHT", f, "RIGHT", -xr, 0)
        xr = xr + e.w
    end
    local cw = 0
    for _, e in ipairs(buckets.center) do cw = cw + e.w end
    local cx = (W - cw) / 2
    for _, e in ipairs(buckets.center) do
        e.slot:Show(); e.slot:ClearAllPoints()
        e.slot:SetWidth(e.w)
        e.slot:SetPoint("LEFT", f, "LEFT", cx, 0)
        cx = cx + e.w
    end
end
```

- [ ] **Step 2: check.js + graphify**

Run: `node tools/check.js` → grün; `graphify update .`

- [ ] **Step 3: Commit**

```bash
git add Modules/Trackbars.lua
git commit -m "Trackbars: Eimer-Layout, Block-Slots und Block-API"
```

---

### Task 3: Block-Gerüst + erste Blöcke (Abstandshalter, Uhr, FPS, Latenz, Haltbarkeit)

**Files:**
- Modify: `Modules/TrackbarsBlocks.lua` (Stub aus Task 1 ersetzen)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua` (neue Schlüssel, siehe Task 8 für die Sammelliste)

**Interfaces:**
- Consumes: den Fabrik-Vertrag, `mod.RegisterHeartbeat/UnregisterHeartbeat`, `mod.RequestLayout` aus Task 2.
- Produces: `mod.BlockFactories.spacer/clock/fps/ms/durability`; gemeinsame Helfer `MakeTextBlock` (unten) für alle Text-Blöcke; `blockColor(b) -> r,g,b` (nil-Farbe = Weiß, `useAccent` liest `ns.COLORS.accent` zur Laufzeit).

- [ ] **Step 1: Gemeinsames Gerüst schreiben**

```lua
-- VuloClassicUI / Modules / TrackbarsBlocks: die Block-Fabriken der Trackbars.
local _, ns = ...
local L   = ns.L
local UI  = ns.UI
local mod = ns.modules.trackbars

local function instKey(prefix, b, bar) return prefix .. ":" .. bar.id .. ":" .. b.id end

local function blockColor(b)
    if b.useAccent and ns.COLORS and ns.COLORS.accent then
        local a = ns.COLORS.accent
        return a.r, a.g, a.b
    end
    local c = b.color
    if c and c.r then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Textblock-Gerüst: FontString + optionales Icon links, Herzschlag und/oder
-- Events, Relayout nur wenn sich die gemessene Breite aendert.
-- def = { icon=texturePfad|nil, events={...}|nil, interval=1|n|nil (Herzschlag
--         alle n Ticks; nil = kein Herzschlag), text=function(b) -> string,
--         onEnter/onLeave/onClick = function(self, b)|nil, fontScale=0.5 }
local function MakeTextBlock(prefix, def)
    return function(b, slot, content, bar)
        local inst = { _key = instKey(prefix, b, bar) }
        local fs = content:CreateFontString(nil, "OVERLAY")
        UI.FontFor("trackbars", fs, math.floor((bar.thickness or 26) * (def.fontScale or 0.5) + 0.5))
        fs:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        local icon
        if def.icon then
            icon = content:CreateTexture(nil, "ARTWORK")
            local isz = math.floor((bar.thickness or 26) * 0.62 + 0.5)
            icon:SetSize(isz, isz)
            icon:SetPoint("RIGHT", fs, "LEFT", -4, 0)
            icon:SetTexture(def.icon)
        end
        inst.fs, inst.icon = fs, icon
        local lastLen = -1
        function inst:Refresh()
            local r, g, bl = blockColor(b)
            fs:SetTextColor(r, g, bl)
            if icon then icon:SetVertexColor(r, g, bl) end
            fs:SetText(def.text(b) or "")
            local len = self:GetAutoLength()
            -- content bekommt die gemessene Groesse, sonst haengt der RIGHT-Anker
            -- des FontStrings an einem 0-breiten Frame und der Text steht schief
            content:SetSize(math.max(len, 1), bar.thickness or 26)
            if len ~= lastLen then lastLen = len; mod.RequestLayout(bar.id) end
        end
        function inst:GetAutoLength()
            local w = fs:GetStringWidth() or 0
            if w <= 0 then return 0 end
            if icon then w = w + (icon:GetWidth() or 0) + 4 end
            return math.ceil(w)
        end
        local evFrame
        function inst:Enable()
            if def.interval then
                local n, c = def.interval, 0
                mod.RegisterHeartbeat(self._key, function()
                    c = c + 1
                    if c >= n then c = 0; inst:Refresh() end
                end)
            end
            if def.events and not evFrame then
                evFrame = CreateFrame("Frame")
                for _, ev in ipairs(def.events) do pcall(evFrame.RegisterEvent, evFrame, ev) end
                evFrame:SetScript("OnEvent", function() inst:Refresh() end)
            end
            if def.onEnter or def.onClick then
                -- Maus auf dem SLOT, nicht der Leiste; Klicks nur wo noetig
                slot:EnableMouse(true)
                slot:SetScript("OnEnter", def.onEnter and function(s) def.onEnter(s, b) end or nil)
                slot:SetScript("OnLeave", def.onLeave or function() GameTooltip:Hide() end)
                if def.onClick then
                    slot:SetScript("OnMouseUp", function(s, btn) def.onClick(s, b, btn) end)
                end
            end
        end
        function inst:Disable()
            mod.UnregisterHeartbeat(self._key)
            if evFrame then evFrame:UnregisterAllEvents(); evFrame:SetScript("OnEvent", nil) end
            slot:EnableMouse(false)
        end
        return inst
    end
end

local function addType(key, labelKey, defaults, factory)
    mod.BLOCK_DEFAULTS[key] = defaults or {}
    table.insert(mod.BLOCK_TYPES, { key = key, label = function() return L[labelKey] end })
    mod.BlockFactories[key] = factory
end
```

- [ ] **Step 2: Die fünf Blöcke definieren**

```lua
-- Abstandshalter: feste Breite, kein Text
addType("spacer", "Spacer", { width = 20 }, function(b, slot, content, bar)
    local inst = {}
    function inst:Refresh() end
    function inst:GetAutoLength() return b.settings.width or 20 end
    function inst:Enable() end
    function inst:Disable() end
    return inst
end)

-- Uhr: Herzschlag 1s; lokale oder Serverzeit, 24h-Schalter
addType("clock", "Clock", { hour24 = true, source = "local" }, MakeTextBlock("clock", {
    interval = 1, fontScale = 0.55,
    text = function(b)
        local s = b.settings
        if s.source == "server" then
            local h, m = GetGameTime()
            if not s.hour24 then
                local suf = (h >= 12) and " PM" or " AM"
                h = h % 12; if h == 0 then h = 12 end
                return string.format("%d:%02d%s", h, m, suf)
            end
            return string.format("%02d:%02d", h, m)
        end
        return date(s.hour24 and "%H:%M" or "%I:%M %p")
    end,
    onEnter = function(self, b)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Clock"])
        local h, m = GetGameTime()
        GameTooltip:AddDoubleLine(L["Server time"], string.format("%02d:%02d", h, m), 1,1,1, 1,1,1)
        GameTooltip:AddDoubleLine(L["Local time"], date("%H:%M"), 1,1,1, 1,1,1)
        GameTooltip:Show()
    end,
}))

-- FPS: alle 3 Herzschlaege
addType("fps", "FPS", {}, MakeTextBlock("fps", {
    interval = 3, fontScale = 0.5,
    text = function() return string.format("%d %s", math.floor(GetFramerate() + 0.5), L["fps"]) end,
}))

-- Latenz: 1s-Herzschlag, GetNetStats cached ~30s -> Text aendert sich selten,
-- Refresh ist trotzdem billig (ein format + SetText nur bei Breitenwechsel via MakeTextBlock)
addType("ms", "Latency", { world = true }, MakeTextBlock("ms", {
    interval = 1, fontScale = 0.5,
    text = function(b)
        local _, _, home, world = GetNetStats()
        if b.settings.world then return string.format("%d/%d %s", home or 0, world or 0, L["ms"]) end
        return string.format("%d %s", home or 0, L["ms"])
    end,
}))

-- Haltbarkeit: Event-getrieben, Minimum ueber alle Slots
local DUR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
addType("durability", "Durability", {}, MakeTextBlock("dur", {
    events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_ENTERING_WORLD" },
    fontScale = 0.5,
    text = function()
        local worst = 1
        for _, slot in ipairs(DUR_SLOTS) do
            local cur, max = GetInventoryItemDurability(slot)
            if cur and max and max > 0 then
                local p = cur / max
                if p < worst then worst = p end
            end
        end
        return string.format("%d%% %s", math.floor(worst * 100 + 0.5), L["Dur"])
    end,
    onEnter = function(self, b)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Durability"])
        for _, slot in ipairs(DUR_SLOTS) do
            local cur, max = GetInventoryItemDurability(slot)
            if cur and max and max > 0 then
                local link = GetInventoryItemLink("player", slot)
                local name = link and link:match("%[(.-)%]") or tostring(slot)
                local p = cur / max
                GameTooltip:AddDoubleLine(name, string.format("%d%%", math.floor(p * 100 + 0.5)),
                    1,1,1, 1 - (1 - p) * 0.8, p, 0.2)
            end
        end
        GameTooltip:Show()
    end,
}))
```

- [ ] **Step 3: check.js + Commit**

```bash
node tools/check.js
git add Modules/TrackbarsBlocks.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "Trackbars: Textblock-Geruest und die Bloecke Uhr, FPS, Latenz, Haltbarkeit, Abstand"
```

---

### Task 4: Gold-, Taschen-, Zonen/Koordinaten- und EP/Ruf-Block

**Files:**
- Modify: `Modules/TrackbarsBlocks.lua`
- Modify: `Core/Database.lua` NICHT — der Goldspeicher liegt unter `VuloClassicUIDB.global` und wird lazy angelegt.

**Interfaces:**
- Consumes: `MakeTextBlock`, `addType`, `blockColor`, `instKey` aus Task 3.
- Produces: `mod.BlockFactories.gold/bags/zone/xprep`. Goldspeicher: `VuloClassicUIDB.global.trackbarsGold["Name-Realm"] = { money = <copper>, class = "MAGE" }` (Konto-Ebene, außerhalb der Profile — Profilexporte verraten keine Alt-Goldstände).

- [ ] **Step 1: Gold-Block**

Sitzungs-Bilanz auf Engine-Ebene (ein Zustand für alle Gold-Instanzen), Kontospeicher, Tooltip mit Sitzungszeile, Charakterliste (klassengefärbt, reichste zuerst, Summe), Strg-Rechtsklick setzt die Sitzung zurück, Linksklick öffnet die Taschen:

```lua
local goldLedger = { profit = 0, spent = 0, last = nil }
local function goldStore()
    VuloClassicUIDB.global.trackbarsGold = VuloClassicUIDB.global.trackbarsGold or {}
    return VuloClassicUIDB.global.trackbarsGold
end
local function goldCharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end
local function goldLedgerUpdate()
    local money = GetMoney() or 0
    if goldLedger.last then
        local d = money - goldLedger.last
        if d > 0 then goldLedger.profit = goldLedger.profit + d
        elseif d < 0 then goldLedger.spent = goldLedger.spent - d end
    end
    goldLedger.last = money
    local _, class = UnitClass("player")
    goldStore()[goldCharKey()] = { money = money, class = class }
end

addType("gold", "Gold", { showBagSlots = false, shorten = false }, MakeTextBlock("gold", {
    events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "BAG_UPDATE" },
    fontScale = 0.5,
    text = function(b)
        goldLedgerUpdate()
        local money = GetMoney() or 0
        local txt
        if b.settings.shorten then
            txt = string.format("%d|cffffd700g|r", math.floor(money / 10000))
        else
            txt = GetCoinTextureString(money)
        end
        if b.settings.showBagSlots then
            local free = 0
            for bag = 0, 4 do free = free + (GetContainerNumFreeSlots(bag) or 0) end
            txt = txt .. string.format(" (%d)", free)
        end
        return txt
    end,
    onEnter = function(self, b)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Gold"])
        GameTooltip:AddDoubleLine(L["Session earned"], GetCoinTextureString(goldLedger.profit), 1,1,1, 1,1,1)
        GameTooltip:AddDoubleLine(L["Session spent"], GetCoinTextureString(goldLedger.spent), 1,1,1, 1,1,1)
        local net = goldLedger.profit - goldLedger.spent
        GameTooltip:AddDoubleLine(L["Session profit"], GetCoinTextureString(math.abs(net)),
            1,1,1, net >= 0 and 0.3 or 0.9, net >= 0 and 0.9 or 0.3, 0.3)
        GameTooltip:AddLine(" ")
        local rows, total = {}, 0
        for key, e in pairs(goldStore()) do
            table.insert(rows, { key = key, money = e.money or 0, class = e.class })
            total = total + (e.money or 0)
        end
        table.sort(rows, function(a, bb) return a.money > bb.money end)
        for i, r in ipairs(rows) do
            if i > 10 then GameTooltip:AddLine(string.format(L["+%d more"], #rows - 10), 0.6,0.6,0.6); break end
            local cc = r.class and RAID_CLASS_COLORS[r.class]
            GameTooltip:AddDoubleLine(r.key:match("^(.-)%-") or r.key, GetCoinTextureString(r.money),
                cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1, 1,1,1)
        end
        GameTooltip:AddDoubleLine(L["Total"], GetCoinTextureString(total), 1,0.82,0, 1,1,1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Left-Click: bags -- Ctrl+Right-Click: reset session"], 0.5, 0.7, 1)
        GameTooltip:Show()
    end,
    onClick = function(self, b, btn)
        if btn == "LeftButton" then
            if OpenAllBags then OpenAllBags() end
        elseif btn == "RightButton" and IsControlKeyDown() then
            goldLedger.profit, goldLedger.spent = 0, 0
            goldLedger.last = GetMoney()
        end
    end,
}))
```

- [ ] **Step 2: Taschenplätze-Block** (eigenständig, für wen Gold ohne Suffix will)

```lua
addType("bags", "Bag slots", {}, MakeTextBlock("bags", {
    events = { "BAG_UPDATE", "PLAYER_ENTERING_WORLD" },
    fontScale = 0.5,
    text = function()
        local free, total = 0, 0
        for bag = 0, 4 do
            free  = free  + (GetContainerNumFreeSlots(bag) or 0)
            total = total + (GetContainerNumSlots(bag) or 0)
        end
        return string.format("%d/%d %s", free, total, L["free"])
    end,
    onClick = function() if OpenAllBags then OpenAllBags() end end,
}))
```

- [ ] **Step 3: Zone/Koordinaten-Block**

```lua
addType("zone", "Zone", { showCoords = true }, MakeTextBlock("zone", {
    interval = 1,
    events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
    fontScale = 0.5,
    text = function(b)
        local zone = GetMinimapZoneText() or GetRealZoneText() or ""
        if b.settings.showCoords and C_Map and C_Map.GetBestMapForUnit then
            local map = C_Map.GetBestMapForUnit("player")
            local pos = map and C_Map.GetPlayerMapPosition(map, "player")
            if pos then
                local x, y = pos:GetXY()
                return string.format("%s %.0f, %.0f", zone, x * 100, y * 100)
            end
        end
        return zone
    end,
    onClick = function() if ToggleWorldMap then ToggleWorldMap() end end,
}))
```

(Ohne Koordinaten entfällt der Herzschlag-Nutzen nicht — `interval=1` bleibt, der Text ändert sich dann nur bei Zonenwechsel und `MakeTextBlock` layoutet nur bei Breitenänderung.)

- [ ] **Step 4: EP/Ruf-Block — echter Fortschrittsbalken, kein reiner Text**

Eigene Fabrik (nicht `MakeTextBlock`): FontString oben, 4px-StatusBar darunter, zweite überlagerte Bar für Erholungs-EP. Rechtsklick wechselt den Modus dauerhaft; expliziter Modus rendert bei Leere einen grauen Platzhalter statt einzuklappen (sonst ist der Rückweg-Klick unmöglich — ein eingeklappter Block hat keine Trefffläche):

```lua
addType("xprep", "XP / Reputation", { mode = "auto" }, function(b, slot, content, bar)
    local inst = { _key = instKey("xprep", b, bar) }
    local fs = content:CreateFontString(nil, "OVERLAY")
    UI.FontFor("trackbars", fs, math.floor((bar.thickness or 26) * 0.42 + 0.5))
    fs:SetPoint("TOP", content, "TOP", 0, -1)
    local sb = CreateFrame("StatusBar", nil, content)
    sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    sb:SetHeight(4)
    sb:SetPoint("TOP", fs, "BOTTOM", 0, -2)
    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(sb); track:SetColorTexture(1, 1, 1, 0.10)
    local rest = CreateFrame("StatusBar", nil, content)
    rest:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    rest:SetStatusBarColor(0.3, 0.3, 1, 0.5)
    rest:SetAllPoints(sb)
    rest:SetFrameLevel(sb:GetFrameLevel() - 1)
    local lastLen = -1

    -- TOC traegt 20505 UND 38001 -- Maxlevel nie hart auf 70 setzen
    local function maxLevel()
        return (GetMaxPlayerLevel and GetMaxPlayerLevel())
            or (MAX_PLAYER_LEVEL_TABLE and GetAccountExpansionLevel
                and MAX_PLAYER_LEVEL_TABLE[GetAccountExpansionLevel()])
            or 70
    end
    local function currentMode()
        local m = b.settings.mode
        if m == "xp" or m == "rep" then return m end
        if UnitLevel("player") >= maxLevel() then return "rep" end
        return "xp"
    end

    function inst:Refresh()
        local mode = currentMode()
        local a = ns.COLORS and ns.COLORS.accent or { r = 0.61, g = 0.42, b = 1 }
        if mode == "xp" then
            local cur, max = UnitXP("player"), UnitXPMax("player")
            if UnitLevel("player") >= maxLevel() then
                fs:SetText(L["Max level (Right-Click: reputation)"])
                fs:SetTextColor(0.6, 0.6, 0.6)
                sb:Hide(); rest:Hide()
            else
                fs:SetTextColor(blockColor(b))
                fs:SetFormattedText("%s: %d%%", L["XP"], math.floor(cur / math.max(max, 1) * 100 + 0.5))
                sb:SetMinMaxValues(0, max); sb:SetValue(cur)
                sb:SetStatusBarColor(a.r, a.g, a.b)
                local exh = GetXPExhaustion()
                rest:SetMinMaxValues(0, max)
                rest:SetValue(math.min(max, cur + (exh or 0)))
                sb:Show(); rest:SetShown(exh and exh > 0)
            end
        else
            local name, _, minV, maxV, value = GetWatchedFactionInfo()
            if not name then
                fs:SetText(L["No reputation tracked"])
                fs:SetTextColor(0.6, 0.6, 0.6)
                sb:Hide(); rest:Hide()
            else
                fs:SetTextColor(blockColor(b))
                fs:SetFormattedText("%s: %d%%", name,
                    math.floor((value - minV) / math.max(maxV - minV, 1) * 100 + 0.5))
                sb:SetMinMaxValues(0, maxV - minV); sb:SetValue(value - minV)
                sb:SetStatusBarColor(a.r, a.g, a.b)
                sb:Show(); rest:Hide()
            end
        end
        local len = inst:GetAutoLength()
        if len ~= lastLen then lastLen = len; mod.RequestLayout(bar.id) end
    end
    function inst:GetAutoLength()
        local w = fs:GetStringWidth() or 0
        if w <= 0 then return 0 end
        sb:SetWidth(w + 30); return math.ceil(w + 30)
    end
    local evFrame
    function inst:Enable()
        evFrame = evFrame or CreateFrame("Frame")
        for _, ev in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP",
                              "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }) do
            pcall(evFrame.RegisterEvent, evFrame, ev)
        end
        evFrame:SetScript("OnEvent", function() inst:Refresh() end)
        slot:EnableMouse(true)
        slot:SetScript("OnMouseUp", function(_, btn)
            if btn == "RightButton" then
                b.settings.mode = (currentMode() == "xp") and "rep" or "xp"
                inst:Refresh()
            end
        end)
        slot:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            if currentMode() == "xp" then
                GameTooltip:SetText(L["XP"])
                GameTooltip:AddDoubleLine(L["Current"], string.format("%d / %d", UnitXP("player"), UnitXPMax("player")), 1,1,1, 1,1,1)
                local exh = GetXPExhaustion()
                if exh then GameTooltip:AddDoubleLine(L["Rested"], tostring(exh), 1,1,1, 0.4,0.4,1) end
            else
                local name, standing, minV, maxV, value = GetWatchedFactionInfo()
                GameTooltip:SetText(name or L["Reputation"])
                if name then
                    GameTooltip:AddDoubleLine(_G["FACTION_STANDING_LABEL" .. (standing or 4)] or "",
                        string.format("%d / %d", value - minV, maxV - minV), 1,1,1, 1,1,1)
                end
            end
            GameTooltip:AddLine(L["Right-Click: toggle XP / reputation"], 0.5, 0.7, 1)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    function inst:Disable()
        if evFrame then evFrame:UnregisterAllEvents(); evFrame:SetScript("OnEvent", nil) end
        slot:EnableMouse(false)
    end
    return inst
end)
```

- [ ] **Step 5: check.js + Commit**

```bash
node tools/check.js
git add Modules/TrackbarsBlocks.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "Trackbars: Gold mit Sitzungsbilanz und Kontoliste, Taschen, Zone, EP/Ruf-Balken"
```

---

### Task 5: Mikromenü-Block (Secure-Klick-Umleitung)

**Files:**
- Modify: `Modules/TrackbarsBlocks.lua`

**Interfaces:**
- Consumes: `addType`, `instKey`; Icons aus `Interface\AddOns\VuloClassicUI\Media\Icons\micro\*` (vorhanden — character, spellbook, talents, questlog, map, socials, lfg, help; dazu `gear` für das Hauptmenü). **Keine neuen Icons nötig.**
- Produces: `mod.BlockFactories.micromenu`. Settings: `{ character=true, spellbook=true, talents=true, quests=true, social=true, lfg=true, map=true, menu=true, help=false, spacing=2 }`.

**Taint-Regeln (verbindlich):**
1. Knöpfe mit Blizzard-Zwilling (character, spellbook, talents, quests, social, lfg, help) sind `SecureActionButtonTemplate`-Knöpfe mit `*type1="click"` + `SetAttribute("clickbutton1", _G[name])`. Der Klick läuft dann in Blizzards Stack — kein Taint, auch beim Zauberbuch. Auf 20505 gilt das Wildcard-Rezept: `RegisterForClicks("AnyUp","AnyDown")` und `*type1` (nicht `type1`).
2. Knöpfe ohne brauchbaren Zwilling (map → `ToggleWorldMap()`, menu → GameMenu wie [Modules/ActionBars.lua:952-963](../../Modules/ActionBars.lua)) sind einfache Buttons mit direktem Aufruf — diese Funktionen sind unkritisch.
3. Zwillings-Auflösung defensiv über `_G`: `MM_BUTTONS`-Katalog mit Kandidatenliste je Schlüssel (`social = { "SocialsMicroButton", "GuildMicroButton" }`); existiert kein Kandidat, wird der Knopf übersprungen. Kollidiert NICHT mit dem modernen Mikromenü der Aktionsleisten (das adoptiert Frames; wir klicken sie nur).
4. Secure-Knöpfe nur außerhalb des Kampfes erstellen: `EnsureButtons` bricht im Lockdown ab, merkt `inst._deferred` und holt es bei `PLAYER_REGEN_ENABLED` nach; bis dahin meldet `GetAutoLength()` 0.

- [ ] **Step 1: Katalog + Fabrik schreiben**

```lua
local MM_ICON = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\"
local MM_BUTTONS = {
    { key = "character", icon = "micro\\character", twins = { "CharacterMicroButton" } },
    { key = "spellbook", icon = "micro\\spellbook", twins = { "SpellbookMicroButton" } },
    { key = "talents",   icon = "micro\\talents",   twins = { "TalentMicroButton" } },
    { key = "quests",    icon = "micro\\questlog",  twins = { "QuestLogMicroButton" } },
    { key = "social",    icon = "micro\\socials",   twins = { "SocialsMicroButton", "GuildMicroButton" } },
    { key = "lfg",       icon = "micro\\lfg",       twins = { "LFGMicroButton" } },
    { key = "map",       icon = "micro\\map",       action = function() if ToggleWorldMap then ToggleWorldMap() end end },
    { key = "help",      icon = "micro\\help",      twins = { "HelpMicroButton" } },
    { key = "menu",      icon = "gear",
      action = function()
          local gm = _G.GameMenuFrame
          if not gm then return end
          if gm:IsShown() then HideUIPanel(gm)
          else
              if CloseMenus then CloseMenus() end
              if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
              ShowUIPanel(gm)
          end
      end },
}

addType("micromenu", "Micro menu",
    { character = true, spellbook = true, talents = true, quests = true,
      social = true, lfg = true, map = true, menu = true, help = false, spacing = 2 },
    function(b, slot, content, bar)
        local inst = { _key = instKey("mm", b, bar), _buttons = {} }
        local function resolveTwin(def)
            for _, n in ipairs(def.twins or {}) do
                if _G[n] then return _G[n] end
            end
        end
        local function ensureButtons()
            if inst._built then return true end
            if InCombatLockdown() then inst._deferred = true; return false end
            local sz = math.floor((bar.thickness or 26) * 0.72 + 0.5)
            for _, def in ipairs(MM_BUTTONS) do
                local twin = def.twins and resolveTwin(def)
                if twin or def.action then
                    local btn
                    if twin then
                        btn = CreateFrame("Button", "VuloTrackbarMM" .. bar.id .. b.id .. def.key,
                            content, "SecureActionButtonTemplate")
                        btn:RegisterForClicks("AnyUp", "AnyDown")
                        btn:SetAttribute("*type1", "click")
                        btn:SetAttribute("clickbutton1", twin)
                    else
                        btn = CreateFrame("Button", nil, content)
                        btn:SetScript("OnClick", def.action)
                    end
                    btn:SetSize(sz, sz)
                    local tex = btn:CreateTexture(nil, "ARTWORK")
                    tex:SetAllPoints(btn)
                    tex:SetTexture(MM_ICON .. def.icon)
                    tex:SetVertexColor(0.85, 0.85, 0.85)
                    btn:SetScript("OnEnter", function(s)
                        tex:SetVertexColor(1, 1, 1)
                        local a = ns.COLORS and ns.COLORS.accent
                        if a then tex:SetVertexColor(a.r, a.g, a.b) end
                        local tip = twin and twin.tooltipText
                        if tip then
                            GameTooltip:SetOwner(s, "ANCHOR_TOP")
                            GameTooltip:SetText(tip); GameTooltip:Show()
                        end
                    end)
                    btn:SetScript("OnLeave", function()
                        tex:SetVertexColor(0.85, 0.85, 0.85)
                        GameTooltip:Hide()
                    end)
                    inst._buttons[def.key] = btn
                end
            end
            inst._built = true
            return true
        end
        local function layoutButtons()
            local sz = math.floor((bar.thickness or 26) * 0.72 + 0.5)
            local gap = b.settings.spacing or 2
            local x = 0
            for _, def in ipairs(MM_BUTTONS) do
                local btn = inst._buttons[def.key]
                if btn then
                    if b.settings[def.key] then
                        btn:Show()
                        btn:ClearAllPoints()
                        btn:SetPoint("LEFT", content, "LEFT", x, 0)
                        x = x + sz + gap
                    else
                        btn:Hide()
                    end
                end
            end
            inst._width = (x > 0) and (x - gap) or 0
            content:SetSize(math.max(inst._width, 1), sz)
        end
        function inst:Refresh()
            if ensureButtons() then layoutButtons() end
            mod.RequestLayout(bar.id)
        end
        function inst:GetAutoLength() return inst._built and inst._width or 0 end
        local evFrame
        function inst:Enable()
            evFrame = evFrame or CreateFrame("Frame")
            evFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            evFrame:SetScript("OnEvent", function()
                if inst._deferred then inst._deferred = nil; inst:Refresh() end
            end)
        end
        function inst:Disable()
            if evFrame then evFrame:UnregisterAllEvents() end
            for _, btn in pairs(inst._buttons) do btn:Hide() end
        end
        return inst
    end)
```

- [ ] **Step 2: check.js + Commit**

```bash
node tools/check.js
git add Modules/TrackbarsBlocks.lua
git commit -m "Trackbars: Mikromenue-Block mit Secure-Klick-Umleitung auf Blizzards Mikroknoepfe"
```

In-Game-Sonden (Nutzer): Zauberbuch über den Block öffnen, dann einen Zauber wirken (kein „Interface-Aktion fehlgeschlagen"); dasselbe im Kampf (Klick muss funktionieren, Erstellung darf im Kampf nicht crashen: Block im Kampf zu einer Leiste hinzufügen → erscheint erst nach Kampfende).

---

### Task 6: Vorlagen + Leisten anlegen/umbenennen/löschen

**Files:**
- Modify: `Modules/Trackbars.lua`

**Interfaces:**
- Consumes: `mod.AddBlock`, `mod.ApplyBar`, `mod.ApplyAll`.
- Produces: `mod.TEMPLATES` (geordnetes Array), `mod.CreateBar(templateKey) -> cfg`, `mod.DeleteBar(barId)`, `mod.RenameBar(barId, name)`. Vorlagen-Schlüssel: `empty`, `bottom`, `minimapc`, `microstrip`.

- [ ] **Step 1: Vorlagen-Tabelle + CreateBar/DeleteBar/RenameBar**

```lua
-- Vorlagen: label() lazy (Locale-Regel), blocks = { {type, side, settings-Overrides} }
mod.TEMPLATES = {
    { key = "empty", label = function() return L["Start empty"] end,
      desc = function() return L["An empty bar to build from scratch."] end,
      cfg = { lengthMode = "custom", length = 400, thickness = 26, x = 0, y = -250 } },
    { key = "bottom", label = function() return L["Top/Bottom info bar"] end,
      desc = function() return L["Full-width bar with the classic info blocks."] end,
      cfg = { lengthMode = "full", edge = "bottom", edgeOffset = 0, thickness = 24 },
      blocks = {
          { type = "micromenu", side = "left" },
          { type = "zone",      side = "left" },
          { type = "clock",     side = "center" },
          { type = "durability", side = "right" },
          { type = "gold",      side = "right" },
          { type = "fps",       side = "right" },
          { type = "ms",        side = "right" },
      } },
    { key = "minimapc", label = function() return L["Minimap companion"] end,
      desc = function() return L["Compact clock and FPS readout."] end,
      cfg = { lengthMode = "custom", length = 200, thickness = 20, sizingMode = "even",
              x = math.floor((UIParent and UIParent:GetWidth() or 1920) / 2) - 110, y = 180 },
      blocks = { { type = "clock" }, { type = "fps" }, { type = "ms" } } },
    { key = "microstrip", label = function() return L["Micro menu strip"] end,
      desc = function() return L["Just the micro menu buttons."] end,
      cfg = { lengthMode = "custom", length = 300, thickness = 30, x = 0, y = -300 },
      blocks = { { type = "micromenu", side = "center" } } },
}

function mod.NewBarCfg()
    local cfg = {
        id = mod.db.nextBarId, name = string.format(L["Bar %d"], mod.db.nextBarId),
        lengthMode = "custom", length = 400, thickness = 26,
        edge = "bottom", edgeOffset = 0, x = 0, y = -250,
        sizingMode = "auto", fontScale = 100,
        bg = { r = 0.05, g = 0.05, b = 0.06, a = 0.90 }, hideBorder = false,
        mouseoverOnly = false, strata = "MEDIUM",
        nextBlockId = 1, blocks = {},
    }
    mod.db.nextBarId = mod.db.nextBarId + 1
    return cfg
end

function mod.CreateBar(templateKey)
    local tpl
    for _, t in ipairs(mod.TEMPLATES) do
        if t.key == templateKey then tpl = t; break end
    end
    local cfg = mod.NewBarCfg()
    if tpl then
        for k, v in pairs(tpl.cfg or {}) do
            cfg[k] = (type(v) == "table") and deepCopy(v) or v
        end
        table.insert(mod.db.bars, cfg)
        for _, bt in ipairs(tpl.blocks or {}) do
            local b = mod.AddBlock(cfg.id, bt.type)
            if b then
                b.side = bt.side or b.side
                for sk, sv in pairs(bt.settings or {}) do b.settings[sk] = sv end
            end
        end
    else
        table.insert(mod.db.bars, cfg)
    end
    mod.ApplyBar(cfg.id)
    return cfg
end

function mod.DeleteBar(barId)
    for i, cfg in ipairs(mod.db.bars) do
        if cfg.id == barId then table.remove(mod.db.bars, i); break end
    end
    local rec = barRecs[barId]
    if rec then
        for blockId, inst in pairs(rec.insts) do
            inst:Disable()
            if inst.Destroy then inst:Destroy() end
            rec.insts[blockId] = nil
        end
        rec.frame:Hide()
    end
end

function mod.RenameBar(barId, name)
    local cfg = mod.BarCfg(barId)
    if not cfg then return end
    cfg.name = name
    local rec = barRecs[barId]
    if rec and rec.frame.mover and rec.frame.mover.label then
        rec.frame.mover.label:SetText("|cffffffff" .. name .. "|r")
    end
end
```

Anmerkung Vollbreite + Kampf: `applyBarPosition` läuft aus `EnsureBarFrame` auch mitten im Spiel; die Leisten-Frames sind insecure (nur die Mikromenü-KINDER sind secure) — Umpositionieren im Kampf ist damit erlaubt und braucht keine Verzögerung.

- [ ] **Step 2: check.js + Commit**

```bash
node tools/check.js
git add Modules/Trackbars.lua
git commit -m "Trackbars: vier Vorlagen und die Leisten-Verwaltung"
```

---

### Task 7: Optionsseite

**Files:**
- Modify: `Modules/TrackbarsOptions.lua` (Stub aus Task 1 ersetzen)
- Modify: `Modules/Trackbars.lua` (nur: `mod.optionsBridge` befüllen)

**Interfaces:**
- Consumes: alles aus Tasks 1–6 über `mod.optionsBridge = { BarCfg, CreateBar, DeleteBar, RenameBar, AddBlock, RemoveBlock, MoveBlock, ApplyBar, RequestLayout, TEMPLATES, BLOCK_TYPES, BLOCK_DEFAULTS }` (in Trackbars.lua am Dateiende zuweisen).
- Produces: `mod.GetOptions()` — die Seite erscheint automatisch in der Seitenleiste (Gruppe HUD).

**Seitenaufbau (Hausregeln beachten: Klappmenüs für Auswahl, Zahnrad-Aufklappen nur an Zeilen, Symbolstreifen rechts):**

1. `desc`-Zeile (graue Kurzbeschreibung) + `toggle` „Enable Trackbars" (`ns:IsModuleEnabled`/`ns:ToggleModule` wie [Modules/SwingTimer.lua:485-487](../../Modules/SwingTimer.lua)).
2. **Null Leisten** → Vorlagen-Kartenzustand: je `mod.TEMPLATES`-Eintrag ein `button` (Label + Tooltip aus `desc()`), `onClick = CreateBar(key) + refreshPage()`.
3. **Sonst:** `dropdown` „Bar" (Werte aus `db.bars`, `label = cfg.name`), daneben in einer `row`-Gruppe die Knöpfe „New bar…" (öffnet die Vorlagenwahl als PopupMenu über `ns.PopupMenu` oder als zweite Klappmenü-Zeile), „Rename" (`UI/StringDialog`), „Delete" (mit Bestätigung über `StaticPopup` NICHT auf Dateiebene registriert — lazy).
4. **Abschnitt „Bar Settings"** für die gewählte Leiste: `dropdown` Länge (`full`/`custom`), bei `full` ein `dropdown` Kante (`bottom`/`top`) + `slider` Kantenabstand (0–500), bei `custom` `slider` Breite (100–2000, Schritt 10) + Knopf „Unlock / Move" (`ns:ToggleMoverEditMode` bzw. das Unlock-Muster von SwingTimer `setUnlocked`); `slider` Höhe (16–48); `dropdown` Verteilung (`auto`/`even`); `slider` Schriftskalierung (50–150); `color` Hintergrund (mit Alpha); `toggle` Rahmen ausblenden; `toggle` nur bei Mauskontakt zeigen.
5. **Je Block ein Abschnitt** in Array-Reihenfolge: `header` mit Blocklabel, rechts im Symbolstreifen drei `iconButton`s (▲ = `MoveBlock(-1)`, ▼ = `MoveBlock(+1)`, × = `RemoveBlock` — feste Plätze); darunter `dropdown` Seite (links/zentriert/rechts), `slider` Abstand (0–40), `slider` Skalierung (50–200), `color` Textfarbe + `toggle` Akzentfarbe verwenden; danach die typspezifischen `settings`-Widgets:
   - clock: `toggle` 24-Stunden, `dropdown` Quelle (lokal/Server)
   - ms: `toggle` Weltlatenz mitzeigen
   - gold: `toggle` Taschenplätze anzeigen, `toggle` verkürzt (nur Gold)
   - zone: `toggle` Koordinaten
   - xprep: `dropdown` Modus (auto/EP/Ruf)
   - spacer: `slider` Breite (4–200)
   - micromenu: je Knopf ein `toggle` (2-spaltige `row`-Gruppen), `slider` Abstand (0–10)
6. Unten `button` „Add block" → Klappmenü/PopupMenu mit `mod.BLOCK_TYPES`-Labels → `AddBlock` + `refreshPage()`.

Jeder Setter endet mit `mod.ApplyBar(cfg.id)` (Strukturänderung) oder `mod.RequestLayout(cfg.id)` (nur Layout). Seiten-Neuaufbau nach Strukturänderung: `ns.UI:RebuildCurrentPage()` (Muster [Modules/ActionRingOptions.lua:22-24](../../Modules/ActionRingOptions.lua)).

- [ ] **Step 1: `mod.optionsBridge` in Trackbars.lua am Dateiende befüllen** (exakt die oben genannten 12 Einträge).

- [ ] **Step 2: `mod:GetOptions()` in TrackbarsOptions.lua nach dem Seitenaufbau oben implementieren.** Seitenzustand (gewählte Leiste) als Datei-lokale Variable `selectedBarId` mit Klemm-Logik wie `clampSelection` in ActionRingOptions.

- [ ] **Step 3: check.js + Commit**

```bash
node tools/check.js
git add Modules/Trackbars.lua Modules/TrackbarsOptions.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "Trackbars: Optionsseite mit Vorlagen-Karten, Leistenwahl und Block-Abschnitten"
```

---

### Task 8: Locale-Sammelpass, Review, Wiki

**Files:**
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua` (alle Schlüssel aus Tasks 3–7 vollständig; die übrigen 7 Sprachen laufen beim Release über die locale-translate-Skill)

- [ ] **Step 1: Schlüssel-Inventur** — jede `L["…"]`-Stelle in den drei Trackbars-Dateien gegen enUS/deDE abgleichen (`node tools/check.js` meldet fehlende Schlüssel). Deutsche Werte ohne rohes ASCII-`"`.

- [ ] **Step 2: adversarial-review-Skill auf die drei Dateien** mit Ground-Truth: Anniversary-Clientquelle (GitHub-Zweig `classic_anniversary`, `Blizzard_MicroMenu/Classic/`) und die installierte Referenz. Schwerpunkte der Angriffsliste: Taint (Mikromenü im Kampf, Erstellung im Lockdown), Herzschlag-Leck bei Modul-Disable, Layout-Endlosschleife (Refresh→Relayout→Refresh), Gold-Ledger bei Login vor `PLAYER_ENTERING_WORLD`, Mover-Kollision mit Vollbreiten-Leisten, gelöschte Leiste mit lebenden Event-Frames. CONFIRMED-Funde fixen, checker erneut.

- [ ] **Step 3: `graphify update .` + Abschluss-Commit**

```bash
node tools/check.js && graphify update .
git add Modules/Trackbars.lua Modules/TrackbarsBlocks.lua Modules/TrackbarsOptions.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "Trackbars: Locale-Sammelpass und Review-Fixes"
```

- [ ] **Step 4: Spielprüfungs-Liste für den Nutzer notieren** (nicht blockierend): alle vier Vorlagen einmal anlegen; Zauberbuch-Klick + Zauber wirken; /reload mit 2 Leisten; Profilwechsel; Modul aus/an ohne /reload (Herzschlag muss stehen bleiben, Frames verschwinden).

---

## Nicht in v1 (bewusst verschoben)

- Vertikale Leisten, Kanten-Snap links/rechts, Sichtbarkeit „im Kampf"
- Berufe-Block (Classic-Fertigkeitszeilen), Ruhestein/Reise-Block (Secure-Cast), Kampf-Timer
- Drag&Drop-Sortierung im Vorschaustreifen (Pfeile decken v1)
- Blizzards eigene Mikroleiste ausblenden (macht bereits das Aktionsleisten-Modul; keine Doppelmechanik)
