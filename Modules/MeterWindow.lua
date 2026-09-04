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
    Meter:SetListener(onEngine)
    self:ApplyWindow()
    if Meter:InCombat() then startTicker() end
end

function mod:WindowDisable()
    stopTicker()
    Meter:SetListener(nil)
    if win then win:Hide() end
end
