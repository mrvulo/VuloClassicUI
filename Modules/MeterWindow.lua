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
