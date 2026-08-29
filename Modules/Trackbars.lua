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

function mod.ApplyBar(id)
    local cfg = mod.BarCfg(id)
    if not cfg then return end
    mod.EnsureBarFrame(cfg)
end
function mod.RequestLayout(id) end   -- Task 2 fuellt das

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
