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

mod.BLOCK_DEFAULTS = {}   -- TrackbarsBlocks.lua fills one entry per type
mod.BLOCK_TYPES    = {}   -- likewise: { key="clock", label=function() return L["Clock"] end }

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
    -- 1) Teardown: instances whose block is gone or whose type changed
    for blockId, inst in pairs(rec.insts) do
        local b = mod.BlockCfg(id, blockId)
        if not b or b.type ~= inst._type then
            inst:Disable()
            if inst.Destroy then inst:Destroy() end
            rec.insts[blockId] = nil
            if rec.slots[blockId] then rec.slots[blockId]:Hide() end
        end
    end
    -- 2) Build: create missing instances
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

local pendingLayout = {}
function mod.RequestLayout(barId)
    if pendingLayout[barId] then return end
    pendingLayout[barId] = true
    C_Timer.After(0, function()
        pendingLayout[barId] = nil
        mod.LayoutBar(barId)
    end)
end

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

function mod.LayoutBar(barId)
    local cfg, rec = mod.BarCfg(barId), barRecs[barId]
    if not (cfg and rec) then return end
    local f = rec.frame
    local W = f:GetWidth()
    if not W or W < 1 then return end

    -- collect visible blocks with width (order = array order)
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
        -- equal split across ALL visible blocks in array order
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

    -- auto: left forward, right backward, center as a centered group
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
