-- VuloClassicUI / Modules / UnitFrames
-- Player & target frames, font bars, player castbar and cooldown pulse in
-- one file (30.07.2026). Each merged submodule runs in its own IIFE so
-- file-level locals and top-level early-returns stay isolated.

(function(...)
-- Cosmetic only: hooksecurefunc plus own textures, never touching secure unit-frame state, so nothing taints.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("unitframes", {
    name        = "Player & Target Frame",
    group       = "Unit Frames",
    description = "Elite dragon border for your player frame, plus real health, threat display and the rare-elite border for the target and focus frames.",
    defaults    = {
        enabled       = true,
        playerStyle   = "elite",
        realHealth    = true,
        threatNumeric = true,
        threatGlow    = true,
        rareElite     = true,
        classIcon     = true,
        focus         = true,
    },
})

-- Offsets for the player-frame elements as the 2.5.5 client re-laid them out.
--
-- These used to be branched on ns.isEra, because Era had kept the original
-- layout. Patch 1.15.9 ended that: Era, Hardcore and Season of Discovery now
-- load the very same Blizzard_UnitFrame/Classic/PlayerFrame.xml as Anniversary,
-- so the Era branch was placing the border and the level number against a frame
-- that no longer exists. One set of numbers for both flavors is now correct --
-- and a reminder to test what the client actually offers instead of branching on
-- which flavor it is.
local BASE_X, BASE_Y = -17.5, -3.5
local LEVEL_X, LEVEL_Y = 52.5 + BASE_X, -67 + BASE_Y

local STYLES = {
    elite = {
        file = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
        w = 232, h = 101, l = 256 / 256, r = 24 / 256, t = 0, b = 101 / 128,
        ox = 0, oy = 0,
    },
    rareelite = {
        file = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
        w = 232, h = 101, l = 256 / 256, r = 24 / 256, t = 0, b = 101 / 128,
        ox = 0, oy = 0,
    },
    rare = {
        file = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
        w = 226, h = 101, l = 250 / 256, r = 24 / 256, t = 0, b = 101 / 128,
        ox = 6, oy = 0,
    },
}

-- Only frames that are NOT protected may be listed here.
--
-- PetFrame and TotemFrame used to sit in this list. Writing a frame level onto
-- a protected unit frame from here marks it as ours for the rest of the
-- session, and the next time Blizzard's own PetFrame_Update runs in combat its
-- PetFrame:Show() is refused -- ADDON_ACTION_BLOCKED naming this addon, from a
-- stack that is pure Blizzard code (user report 01.08.2026). Neither one needs
-- the lift: both are CHILD frames of PlayerFrame, so they already draw above
-- every texture the player style swaps out, which are all layers of PlayerFrame
-- itself.
local RAISE_FRAMES = {
    { name = "PlayerFrameGroupIndicator", lift = 1 },
}

local captured

local function capturePoints(frame)
    local pts = {}
    for i = 1, frame:GetNumPoints() do
        pts[i] = { frame:GetPoint(i) }
    end
    return pts
end

local function restorePoints(frame, pts)
    if not pts or #pts == 0 then return end
    frame:ClearAllPoints()
    for _, p in ipairs(pts) do
        frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
end

local function capturePlayerDefaults()
    if captured then return true end
    local tex   = _G.PlayerFrameTexture
    local level = _G.PlayerLevelText
    if not tex or not level then return false end

    captured = {
        tex = {
            points   = capturePoints(tex),
            file     = tex:GetTexture(),
            texCoord = { tex:GetTexCoord() },
            width    = tex:GetWidth(),
            height   = tex:GetHeight(),
        },
        levelPoints = capturePoints(level),
        restPoints  = _G.PlayerRestIcon and capturePoints(_G.PlayerRestIcon) or nil,
        levels      = {},
    }
    for _, def in ipairs(RAISE_FRAMES) do
        local f = _G[def.name]
        if f then captured.levels[def.name] = f:GetFrameLevel() end
    end
    return true
end

local function restorePlayerDefaults()
    if not captured then return end
    local tex = _G.PlayerFrameTexture
    if tex then
        restorePoints(tex, captured.tex.points)
        if captured.tex.file then tex:SetTexture(captured.tex.file) end
        local tc = captured.tex.texCoord
        if tc and #tc == 8 then tex:SetTexCoord(unpack(tc)) end
        tex:SetSize(captured.tex.width, captured.tex.height)
    end
    if _G.PlayerLevelText then restorePoints(_G.PlayerLevelText, captured.levelPoints) end
    if _G.PlayerRestIcon and captured.restPoints then
        restorePoints(_G.PlayerRestIcon, captured.restPoints)
    end
    for _, def in ipairs(RAISE_FRAMES) do
        local f = _G[def.name]
        local lvl = captured.levels[def.name]
        if f and lvl then f:SetFrameLevel(lvl) end
    end
end

local function playerStyleActive()
    return mod.active and mod.db.playerStyle ~= "off" and STYLES[mod.db.playerStyle] ~= nil
end

local function applyPlayerTextPositions()
    if not playerStyleActive() or not captured then return end
    local level = _G.PlayerLevelText
    if level then
        level:ClearAllPoints()
        level:SetPoint("CENTER", _G.PlayerFrame, "TOPLEFT", LEVEL_X, LEVEL_Y)
    end
    local rest = _G.PlayerRestIcon
    if rest and level then
        rest:ClearAllPoints()
        rest:SetPoint("CENTER", level, "CENTER", 0, 1)
    end
end

-- Where the replacement art has to sit, derived from what the CLIENT itself set
-- up rather than from a hardcoded pair of numbers.
--
-- Both sheets are drawn 1:1 (one texel = one screen unit), so the two texture
-- coordinate rects can be compared directly: the horizontal distance between
-- the client's own left texel and ours, added to where the client put its own
-- top-left corner, is where ours belongs. On 2.5.6 this reproduces the values
-- that were hardcoded here before (-17.5 / -3.5) exactly, and it keeps working
-- on any client whose player frame is laid out differently -- which is the
-- assumption that just broke on Era with patch 1.15.9.
local function styleOffset(s)
    local c = captured and captured.tex
    if not (c and c.points and c.points[1] and c.texCoord and #c.texCoord >= 8) then
        return BASE_X + s.ox, BASE_Y + s.oy   -- nothing captured: the known-good pair
    end
    -- capturePoints stores {point, relativeTo, relativePoint, x, y}
    local p = c.points[1]
    if p[1] ~= "CENTER" and p[1] ~= "TOPLEFT" then
        return BASE_X + s.ox, BASE_Y + s.oy
    end
    local dx, dy = p[4] or 0, p[5] or 0
    if p[1] == "CENTER" then
        -- CENTER of the parent, so its top-left corner is half a frame away
        local pw = (_G.PlayerFrame and _G.PlayerFrame:GetWidth())  or 232
        local ph = (_G.PlayerFrame and _G.PlayerFrame:GetHeight()) or 100
        dx = pw / 2 + dx - (c.width  or 0) / 2
        dy = -ph / 2 + dy + (c.height or 0) / 2
    end
    -- GetTexCoord returns the four CORNERS (ULx,ULy, LLx,LLy, URx,URy, LRx,LRy),
    -- not a left/right/top/bottom tuple: upper-left x is 1, upper-right x is 5.
    local l0, r0, t0 = c.texCoord[1], c.texCoord[5], c.texCoord[2]
    -- both sheets are 256 x 128; max() picks the left edge regardless of mirroring
    local ox = dx + (math.max(l0, r0) - math.max(s.l, s.r)) * 256
    local oy = dy + (t0 - s.t) * 128
    return ox, oy
end

local function applyPlayerStyle()
    if not capturePlayerDefaults() then return end
    local s = STYLES[mod.db.playerStyle]
    if not s then
        restorePlayerDefaults()
        return
    end

    local tex = _G.PlayerFrameTexture
    if not tex then return end
    local ox, oy = styleOffset(s)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", _G.PlayerFrame, "TOPLEFT", ox, oy)
    tex:SetTexture(s.file)
    tex:SetTexCoord(s.l, s.r, s.t, s.b)
    tex:SetSize(s.w, s.h)

    applyPlayerTextPositions()

    local base = tex:GetParent():GetFrameLevel()
    for _, def in ipairs(RAISE_FRAMES) do
        local f = _G[def.name]
        if f then f:SetFrameLevel(base + def.lift) end
    end
end

-- Border texture is <Frame>TextureFrameTexture on 2.5.5; older clients expose frame.borderTexture.
local function borderTexOf(frame)
    if frame.borderTexture then return frame.borderTexture end
    local name = frame.GetName and frame:GetName()
    return name and _G[name .. "TextureFrameTexture"]
end

local function abbrev(v)
    if v >= 1e6 then return string.format("%.1fm", v / 1e6)
    elseif v >= 1e4 then return string.format("%.1fk", v / 1e3)
    else return tostring(v) end
end

-- Fallback table for clients without GetThreatStatusColor.
local THREAT_COLOR = { [0] = { 0.69, 0.69, 0.69 }, [1] = { 1, 1, 0.47 }, [2] = { 1, 0.6, 0 }, [3] = { 1, 0, 0 } }
local function threatColor(status)
    if GetThreatStatusColor then
        local r, g, b = GetThreatStatusColor(status or 0)
        if r then return r, g, b end
    end
    local c = THREAT_COLOR[status or 0] or THREAT_COLOR[0]
    return c[1], c[2], c[3]
end

local function unitForFrame(frame)
    if frame == _G.TargetFrame then return "target" end
    if frame == _G.FocusFrame  then return "focus"  end
    return frame and frame.unit
end

local indicators = {}

local pulsing = {}
local pulseDriver = CreateFrame("Frame")
pulseDriver:Hide()
pulseDriver:SetScript("OnUpdate", function()
    local g = 0.30 - 0.30 * math.cos(GetTime() * 6)
    for _, border in pairs(pulsing) do border:SetVertexColor(1, g, g) end
end)

local function createIndicator(frame)
    if indicators[frame] then return indicators[frame] end

    local ind = CreateFrame("Frame", nil, frame)
    ind:SetPoint("BOTTOM", frame, "TOP", -31, -24)
    ind:SetSize(49, 18)
    ind:Hide()
    ind.frame = frame

    ind.bg = ind:CreateTexture(nil, "BACKGROUND")
    ind.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    ind.bg:SetPoint("TOP", 0, -3)
    ind.bg:SetSize(37, 14)

    ind.text = ind:CreateFontString(nil, "BACKGROUND", "GameFontHighlight")
    ind.text:SetDrawLayer("BACKGROUND", 1)
    ind.text:SetPoint("TOP", 0, -4)
    ind.text:SetText("0%")

    local border = ind:CreateTexture(nil, "ARTWORK")
    border:SetTexture("Interface\\TargetingFrame\\NumericThreatBorder")
    border:SetTexCoord(0, 0.765625, 0, 0.5625)
    border:SetAllPoints(ind)

    indicators[frame] = ind
    return ind
end

local function updateIndicator(frame)
    local ind = indicators[frame]
    if not ind then return end

    local unit    = unitForFrame(frame)
    local isFocus = (frame == _G.FocusFrame)
    local allowed = mod.active and (not isFocus or mod.db.focus)
    local numeric = allowed and mod.db.threatNumeric
    local glowOn  = allowed and mod.db.threatGlow

    if (numeric or glowOn) and unit and UnitExists(unit) and UnitDetailedThreatSituation then
        local tanking, status, _, percent = UnitDetailedThreatSituation("player", unit)
        local r, g, b = threatColor(status or 0)

        if numeric then
            if tanking and UnitThreatPercentageOfLead then
                percent = UnitThreatPercentageOfLead("player", unit)
            end
            if percent and percent > 0 then
                if percent > 999 then percent = 999 end  -- the threat API spikes above 999
                ind.text:SetFormattedText("%.0f%%", percent)
                ind.bg:SetVertexColor(r, g, b)
                ind:Show()
            else
                ind:Hide()
            end
        else
            ind:Hide()
        end

        local border = borderTexOf(frame)
        if border then
            if glowOn and status and status >= 3 then
                pulsing[frame] = border
            elseif glowOn and status and status > 0 then
                pulsing[frame] = nil
                border:SetVertexColor(r, g, b)
            else
                pulsing[frame] = nil
                border:SetVertexColor(1, 1, 1)
            end
        end
    else
        ind:Hide()
        pulsing[frame] = nil
        local border = borderTexOf(frame)
        if border then border:SetVertexColor(1, 1, 1) end
    end
    if next(pulsing) then pulseDriver:Show() else pulseDriver:Hide() end
end

local classIcons = {}
local function ensureClassIcon(frame)
    if classIcons[frame] then return classIcons[frame] end
    local fname = frame:GetName() or ""
    -- Must host on the texture frame with a raised level, or the badge draws behind the metal border.
    local host  = _G[fname .. "TextureFrame"] or frame
    local badge = CreateFrame("Frame", nil, host)
    badge:SetSize(26, 26)
    badge:SetFrameLevel((host:GetFrameLevel() or 0) + 5)
    local portrait = _G[fname .. "Portrait"]
    if portrait then badge:SetPoint("CENTER", portrait, "TOPLEFT", 8, -2)
    else badge:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10) end

    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetPoint("CENTER")
    badge.icon:SetSize(17, 17)

    badge.ring = badge:CreateTexture(nil, "OVERLAY")
    badge.ring:SetTexture("Interface\\Common\\RingBorder")
    badge.ring:SetAllPoints(badge)

    badge:Hide()
    classIcons[frame] = badge
    return badge
end

local function updateClassIcon(frame)
    local badge = classIcons[frame]
    if not badge then return end
    local unit    = unitForFrame(frame)
    local isFocus = (frame == _G.FocusFrame)
    if mod.active and mod.db.classIcon and (not isFocus or mod.db.focus)
        and unit and UnitExists(unit) and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            badge.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            badge.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            badge:Show()
            return
        end
    end
    badge:Hide()
end

local function updateAll()
    for frame in pairs(indicators) do
        updateIndicator(frame)
        updateClassIcon(frame)
    end
end

local RARE_ELITE_TEX = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite"

local function applyClassification(frame, lock)
    if not (mod.active and mod.db.rareElite) then return end
    if frame ~= _G.TargetFrame and frame ~= _G.FocusFrame then return end
    if frame == _G.FocusFrame and not mod.db.focus then return end
    local unit = unitForFrame(frame)
    if not lock and unit and UnitExists(unit) and UnitClassification(unit) == "rareelite" then
        local border = borderTexOf(frame)
        if border and border.SetTexture then border:SetTexture(RARE_ELITE_TEX) end
    end
end

local function refreshClassification()
    if _G.TargetFrame and _G.TargetFrame:IsShown() then
        if _G.TargetFrame_CheckClassification then
            pcall(_G.TargetFrame_CheckClassification, _G.TargetFrame)
        elseif _G.TargetFrame.CheckClassification then
            pcall(_G.TargetFrame.CheckClassification, _G.TargetFrame)
        end
    end
end

-- UnitHealth already returns true NPC values on 2.5.5; only the bar text is obfuscated.
local function healthUnitFor(bar)
    if bar == _G.TargetFrameHealthBar then return "target" end
    if bar == _G.FocusFrameHealthBar  then return "focus"  end
    return nil
end

local function applyRealHealth(bar)
    if not (mod.active and mod.db.realHealth) then return end
    local unit = healthUnitFor(bar)
    if not unit then return end
    if unit == "focus" and not mod.db.focus then return end
    if not UnitExists(unit) then return end
    -- Enemy players stay percentage-obfuscated server-side; nothing to rewrite.
    if UnitIsPlayer(unit) and not (UnitIsUnit(unit, "player") or UnitInParty(unit)
        or UnitInRaid(unit) or UnitIsFriend("player", unit)) then
        return
    end
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if not (cur and max and max > 0) then return end
    local pct = math.floor(cur / max * 100 + 0.5)
    local function fs(field, suffix)
        return bar[field] or (bar.GetName and _G[(bar:GetName() or "") .. suffix])
    end
    local left, right, ts = fs("LeftText", "LeftText"), fs("RightText", "RightText"), fs("TextString", "TextString")
    if left and right then
        left:SetText(pct .. "%");   left:Show()
        right:SetText(abbrev(cur)); right:Show()
        if ts then ts:SetText("") end
    elseif ts then
        ts:SetText(pct .. "%  " .. abbrev(cur))
    end
end

local function refreshHealth()
    local function up(bar)
        if not bar then return end
        if bar.UpdateTextString then pcall(bar.UpdateTextString, bar)
        elseif _G.TextStatusBar_UpdateTextString then pcall(_G.TextStatusBar_UpdateTextString, bar) end
    end
    up(_G.TargetFrameHealthBar)
    up(_G.FocusFrameHealthBar)
end

local hooked, realHealthHooked, anchorHooked = false, false, false

local function ensureSetup()
    if not _G.TargetFrame then return end

    createIndicator(_G.TargetFrame)
    ensureClassIcon(_G.TargetFrame)
    if _G.FocusFrame then createIndicator(_G.FocusFrame); ensureClassIcon(_G.FocusFrame) end

    for frame, ind in pairs(indicators) do
        if not ind._wired then
            ind._wired = true
            local unit = unitForFrame(frame)
            if frame == _G.TargetFrame then ind:RegisterEvent("PLAYER_TARGET_CHANGED") end
            if frame == _G.FocusFrame  then ind:RegisterEvent("PLAYER_FOCUS_CHANGED")  end
            if unit then
                -- RegisterUnitEvent is missing on older clients; fall back to the unfiltered event.
                if ind.RegisterUnitEvent then
                    pcall(ind.RegisterUnitEvent, ind, "UNIT_THREAT_LIST_UPDATE", unit)
                    pcall(ind.RegisterUnitEvent, ind, "UNIT_THREAT_SITUATION_UPDATE", unit)
                else
                    ind:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
                end
            end
            ind:SetScript("OnEvent", function(self) updateIndicator(self.frame); updateClassIcon(self.frame) end)
        end
    end

    if not hooked then
        hooked = true
        if _G.TargetFrame_CheckClassification then
            hooksecurefunc("TargetFrame_CheckClassification", applyClassification)
        elseif _G.TargetFrame.CheckClassification then
            hooksecurefunc(_G.TargetFrame, "CheckClassification", function(self, lock) applyClassification(self, lock) end)
            if _G.FocusFrame and _G.FocusFrame.CheckClassification then
                hooksecurefunc(_G.FocusFrame, "CheckClassification", function(self, lock) applyClassification(self, lock) end)
            end
        end
    end

    -- On 2.5.5 the bar text comes from the bar's own mixin method; older clients only have the global.
    if not realHealthHooked then
        local hb = _G.TargetFrameHealthBar
        local function hookBar(bar)
            if not bar then return end
            if bar.UpdateTextStringWithValues then
                hooksecurefunc(bar, "UpdateTextStringWithValues", function(self) applyRealHealth(self) end)
            end
            if bar.UpdateTextString then
                hooksecurefunc(bar, "UpdateTextString", function(self) applyRealHealth(self) end)
            end
        end
        if hb and (hb.UpdateTextStringWithValues or hb.UpdateTextString) then
            realHealthHooked = true
            hookBar(hb)
            hookBar(_G.FocusFrameHealthBar)
        elseif _G.TextStatusBar_UpdateTextString then
            realHealthHooked = true
            hooksecurefunc("TextStatusBar_UpdateTextString", applyRealHealth)
        end
    end
end

local function refreshTargetFrames()
    updateAll()
    refreshClassification()
    refreshHealth()
end

local function onWorldEnter()
    if not mod.active then return end
    applyPlayerStyle()
    ensureSetup()
    refreshTargetFrames()
end

function mod:OnEnable()
    applyPlayerStyle()
    ensureSetup()
    mod:RegisterEvent("PLAYER_ENTERING_WORLD", onWorldEnter)
    refreshTargetFrames()

    -- The level text gets re-anchored by the default UI; hooksecurefunc is permanent, so install it once.
    if not anchorHooked and _G.PlayerFrame_UpdateLevelTextAnchor then
        anchorHooked = true
        hooksecurefunc("PlayerFrame_UpdateLevelTextAnchor", applyPlayerTextPositions)
    end
end

function mod:OnDisable()
    restorePlayerDefaults()

    pulseDriver:Hide()
    for frame, ind in pairs(indicators) do
        ind:Hide()
        pulsing[frame] = nil
        local b = borderTexOf(frame); if b then b:SetVertexColor(1, 1, 1) end
        if classIcons[frame] then classIcons[frame]:Hide() end
    end
    refreshHealth()
    -- Hooks cannot be removed; they stay installed and gate on mod.active.
end

function mod:GetOptions()
    local function apply() refreshTargetFrames() end
    return {
        { type = "header", text = L["Player & Target Frame"] },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Player Frame"] },
        { type = "desc",
          text = L["|cffaaaaaaPuts the golden elite dragon (or the rare variants) around your player portrait — the look elite mobs have on the target frame.|r"] },
        { type = "dropdown", label = L["Frame style"], width = 240,
          values = {
              { value = "elite",     text = L["Elite (golden dragon)"] },
              { value = "rareelite", text = L["Rare-Elite (silver dragon)"] },
              { value = "rare",      text = L["Rare (silver)"] },
              { value = "off",       text = L["Off (default frame)"] },
          },
          get = function() return mod.db.playerStyle end,
          set = function(_, v)
              mod.db.playerStyle = v
              applyPlayerStyle()
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Target & Focus Frame"] },
        { type = "desc",
          text = L["|cffaaaaaaAdds the modern Target/Focus frame extras the default Anniversary UI is missing - all cosmetic, no taint.|r"] },

        { type = "toggle", label = L["Show real NPC health"],
          tooltip = L["Shows the true health value on NPCs instead of the obfuscated percentage (enemy players stay %)."],
          get = function() return mod.db.realHealth end,
          set = function(_, v) mod.db.realHealth = v; apply() end },
        { type = "toggle", label = L["Class icon on player targets"],
          tooltip = L["Shows the target's class crest on the frame when you target a player."],
          get = function() return mod.db.classIcon end,
          set = function(_, v) mod.db.classIcon = v; apply() end },

        { type = "toggle", label = L["Numeric threat %"],
          tooltip = L["Shows your threat percentage on the target (and focus) above the frame, coloured by threat status."],
          get = function() return mod.db.threatNumeric end,
          set = function(_, v) mod.db.threatNumeric = v; apply() end },
        { type = "toggle", label = L["Threat glow"],
          tooltip = L["Glows the target (and focus) frame in yellow/orange/red as your threat rises."],
          get = function() return mod.db.threatGlow end,
          set = function(_, v) mod.db.threatGlow = v; apply() end },

        { type = "toggle", label = L["Rare-Elite border"],
          tooltip = L["Shows the winged silver-dragon Rare-Elite border on rare-elite mobs."],
          get = function() return mod.db.rareElite end,
          set = function(_, v) mod.db.rareElite = v; apply() end },
        { type = "toggle", label = L["Also apply to the Focus frame"],
          get = function() return mod.db.focus end,
          set = function(_, v) mod.db.focus = v; apply() end },
    }
end
end)(...);

(function(...)
-- FontBars: smaller font sizes on Player/Target/Pet Health & Mana bars, plus permanently hiding the TargetFrameBackground.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fontbars", {
    name        = "Font Bars",
    group       = "Unit Frames",
    description = "Smaller font sizes for Player/Target/Pet Health & Mana bars, optionally hide TargetFrameBackground.",
    defaults = {
        healthSize       = 11,
        powerSize        = 11,
        petFeedbackSize  = 11,
        onlyTheseBars    = true,
        hideTargetBackground = true,
    },
})

local function isOurBar(bar)
    if not mod.db.onlyTheseBars then return true end
    return bar == PlayerFrameHealthBar
        or bar == PlayerFrameManaBar
        or bar == TargetFrameHealthBar
        or bar == TargetFrameManaBar
        or bar == PetFrameHealthBar
        or bar == PetFrameManaBar
end

-- Original sizes per FontString, captured before the first change so
-- OnDisable can put them back (the hooks themselves cannot be removed).
local origSizes = {}
local function remember(fs)
    if fs and origSizes[fs] == nil and fs.GetFont then
        local _, size = fs:GetFont()
        origSizes[fs] = size or false
    end
end
local function setBarSize(bar, size)
    if not bar then return end
    remember(bar.TextString or ns:SafeGetFontString(bar, "Text"))
    remember(bar.LeftText   or ns:SafeGetFontString(bar, "TextLeft"))
    remember(bar.RightText  or ns:SafeGetFontString(bar, "TextRight"))
    ns:SetBarTextFontSize(bar, size)
end

local function applyPetFeedbackFont()
    if not mod.active then return end
    local size = tonumber(mod.db.petFeedbackSize) or 11
    local fs = PetFrameFeedbackText
        or (PetFrame and (PetFrame.FeedbackText or PetFrame.feedbackText))
        or _G["PetFrameFeedbackText"]
    if not fs or not fs.GetFont or not fs.SetFont then return end
    local font, _, flags = fs:GetFont()
    if not font then return end
    remember(fs)
    fs:SetFont(font, size, flags)
end

local function applyAll()
    if not mod.active then return end
    local hs = mod.db.healthSize
    local ps = mod.db.powerSize

    setBarSize(PlayerFrameHealthBar, hs)
    setBarSize(PlayerFrameManaBar,   ps)
    setBarSize(TargetFrameHealthBar, hs)
    setBarSize(TargetFrameManaBar,   ps)
    setBarSize(PetFrameHealthBar,    hs)
    setBarSize(PetFrameManaBar,      ps)

    -- NO direct TextStatusBar_UpdateTextString calls here any more: running
    -- Blizzard's updater from OUR context stamps the bars' text-state members
    -- with addon taint, and when Blizzard's own pet update later reads them
    -- the whole execution turns insecure -- PetFrame:Show() then gets BLOCKED
    -- in combat (ADDON_ACTION_BLOCKED, user report 31.07.2026). The text
    -- repaints itself on the next UNIT_HEALTH/UNIT_POWER tick anyway, which
    -- follows within a beat of any slider change.

    applyPetFeedbackFont()
end

local function hideTargetBackground()
    if not mod.active then return end
    if not mod.db.hideTargetBackground then return end
    if TargetFrameBackground then TargetFrameBackground:Hide() end
end

mod.applyAll = applyAll  -- exposed for slider live updates

local hooksInstalled = false
local function installHooks()
    if hooksInstalled or not hooksecurefunc then return end
    hooksInstalled = true

    if TextStatusBar_UpdateTextString then
        hooksecurefunc("TextStatusBar_UpdateTextString", function(bar)
            if not mod.active then return end
            if not bar or not isOurBar(bar) then return end
            if bar == PlayerFrameHealthBar or bar == TargetFrameHealthBar or bar == PetFrameHealthBar then
                setBarSize(bar, mod.db.healthSize)
            elseif bar == PlayerFrameManaBar or bar == TargetFrameManaBar or bar == PetFrameManaBar then
                setBarSize(bar, mod.db.powerSize)
            end
        end)
    end

    if PetFrame_Update then
        hooksecurefunc("PetFrame_Update", function() applyPetFeedbackFont() end)
    end
    if PetFrame_UpdateStatus then
        hooksecurefunc("PetFrame_UpdateStatus", function() applyPetFeedbackFont() end)
    end
    if TargetFrame_CheckDead then
        hooksecurefunc("TargetFrame_CheckDead", function() hideTargetBackground() end)
    end
    if TargetFrame_Update then
        hooksecurefunc("TargetFrame_Update", function() hideTargetBackground() end)
    end
end

-- named handlers so OnDisable can unregister them, and re-enable doesn't stack
-- duplicate anonymous closures (ns:RegisterEvent doesn't dedupe)
local function fbOnPEW()
    applyAll()
    hideTargetBackground()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() applyAll(); hideTargetBackground() end)
        C_Timer.After(1, function() applyAll(); hideTargetBackground() end)
    end
end
local function fbOnTarget() applyAll(); hideTargetBackground() end
local function fbOnPet() applyAll() end

function mod:OnEnable()
    installHooks()
    mod:RegisterEvent("PLAYER_ENTERING_WORLD", fbOnPEW)
    mod:RegisterEvent("PLAYER_TARGET_CHANGED", fbOnTarget)
    mod:RegisterEvent("UNIT_PET", fbOnPet)
    applyAll()
    hideTargetBackground()
end

function mod:OnDisable()
    for fs, size in pairs(origSizes) do
        if size and fs.GetFont then
            local font, _, flags = fs:GetFont()
            if font then fs:SetFont(font, size, flags) end
        end
    end
    if TargetFrameBackground then TargetFrameBackground:Show() end
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Font Sizes"] },
        {
            type = "slider", label = L["Health Bar Text"],
            min = 6, max = 24, step = 1,
            tooltip = L["Font size on health bars (Player/Target/Pet)."],
            get = function() return mod.db.healthSize end,
            set = function(_, v) mod.db.healthSize = v; applyAll() end,
        },
        {
            type = "slider", label = L["Power Bar Text"],
            min = 6, max = 24, step = 1,
            tooltip = L["Font size on mana/power bars."],
            get = function() return mod.db.powerSize end,
            set = function(_, v) mod.db.powerSize = v; applyAll() end,
        },
        {
            type = "slider", label = L["Pet Combat Feedback Text"],
            min = 6, max = 24, step = 1,
            tooltip = L["Font size for 'Damage', 'Dodge', 'Miss' on the pet."],
            get = function() return mod.db.petFeedbackSize end,
            set = function(_, v) mod.db.petFeedbackSize = v; applyAll() end,
        },
        { type = "spacer" },
        { type = "header", text = L["Behavior"] },
        {
            type = "checkbox", label = L["Only affect Player/Target/Pet bars"],
            tooltip = L["If off: all TextStatusBars in the UI are overridden with the sizes above (may interfere with other addons)."],
            get = function() return mod.db.onlyTheseBars end,
            set = function(_, v) mod.db.onlyTheseBars = v; applyAll() end,
        },
        {
            type = "checkbox", label = L["Hide TargetFrame background"],
            tooltip = L["Permanently hides the dark background element of the TargetFrame."],
            get = function() return mod.db.hideTargetBackground end,
            set = function(_, v)
                mod.db.hideTargetBackground = v
                if v then hideTargetBackground()
                elseif TargetFrameBackground then TargetFrameBackground:Show() end
            end,
        },
    }
end
end)(...);

(function(...)
-- Player castbar in two modes: "blizzard" extends the default bar, "custom" draws our own.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("playercastbar", {
    name        = "Player Castbar",
    group       = "Unit Frames",
    description = "Player castbar with two modes: Original (Blizzard bar extended) or Custom castbar (VUI style).",
    defaults = {
        enabled       = true,
        mode          = "blizzard",
        showTimeText  = true,
        timeTextMode  = "both",
        showTicks     = true,
        showClipMarker = true,
        showPushback  = true,
        mergeCrafts   = true,
        showSpellName = true,
        showIcon      = true,
        fillMode      = "texture",
        width         = 240,
        height        = 18,
        iconSize      = 14,
        iconGap       = 3,
        iconX         = 0,
        iconY         = 0,
        x             = 0,
        y             = -180,
        unlocked      = false,
        accentColor   = { r = 0.608, g = 0.424, b = 1.000, a = 0.90 },
        channelColor  = { r = 0.608, g = 0.424, b = 1.000, a = 1.00 },
        successColor  = { r = 0.40, g = 0.85, b = 0.40, a = 1.00 },
        failColor     = { r = 0.90, g = 0.25, b = 0.25, a = 1.00 },

        -- The modern-mode engine features (31.07.2026); all inert by default,
        -- so the two established modes render exactly as before.
        barTexture    = "",      -- shared-media statusbar name; "" = built-in art
        borderSize    = 0,
        borderColor   = { r = 0, g = 0, b = 0 },
        lastTickOn    = false,
        lastTickColor = { r = 0.85, g = 0.70, b = 0.10 },
        latencyText   = false,
    },
})

local TEX_PATH    = "Interface\\AddOns\\VuloClassicUI\\Media\\Castbar\\"
local TEX_BG      = TEX_PATH .. "CastingBarBackground"
local TEX_FILL    = TEX_PATH .. "CastingBarStandard"
local TEX_CHANNEL = TEX_PATH .. "CastingBarChannel"
local TEX_SPARK   = TEX_PATH .. "CastingBarSpark"
local TEX_MASK    = TEX_PATH .. "CastingBarMask"

-- Keyed by real localized client spell names; a miss silently falls back to ~1 tick/second.
local CHANNEL_TICKS = {
    ["Mind Flay"]            = 3,
    ["Gedankenschinden"]     = 3,
    ["Mind Sear"]            = 5,
    ["Drain Life"]           = 5,
    ["Blutsauger"]           = 5,
    ["Drain Mana"]           = 5,
    ["Manasauger"]           = 5,
    ["Drain Soul"]           = 5,
    ["Seelendieb"]           = 5,
    ["Health Funnel"]        = 10,
    ["Gesundheitskanal"]     = 10,
    ["Rain of Fire"]         = 4,
    ["Feuerregen"]           = 4,
    ["Hellfire"]             = 15,
    ["H\195\182llenfeuer"]   = 15,
    ["Arcane Missiles"]      = 5,
    ["Arkane Geschosse"]     = 5,
    ["Evocation"]            = 4,
    ["Hervorrufung"]         = 4,
    ["Blizzard"]             = 8,
    ["Tranquility"]          = 4,
    ["Gelassenheit"]         = 4,
    ["Hurricane"]            = 10,
    ["Orkan"]                = 10,
    ["Volley"]               = 6,
    ["Salve"]                = 6,
}

-- Non-tick channels: excluded so the ~1/s fallback doesn't turn them into a barcode.
local NO_TICKS = {
    ["Fishing"] = true,             ["Angeln"] = true,
    ["First Aid"] = true,           ["Erste Hilfe"] = true,
    ["Disenchant"] = true,          ["Entzaubern"] = true,
    ["Hearthstone"] = true,         ["Ruhestein"] = true,
    ["Astral Recall"] = true,       ["Astralruf"] = true,
    ["Ritual of Summoning"] = true, ["Ritual der Beschw\195\182rung"] = true,
    ["Summoning Stone"] = true,     ["Beschw\195\182rungsstein"] = true,
}

-- The 1.5-15s window keeps the fallback off long utility channels; every real tick spell above 15s is in the table.
local function tickCountFor(name, duration, isTradeSkill)
    if name and NO_TICKS[name] then return nil end
    local c = name and CHANNEL_TICKS[name]
    if c then return c end
    if isTradeSkill then return nil end
    if duration and duration >= 1.5 and duration <= 15 then
        return math.floor(duration + 0.5)
    end
    return nil
end

-- Casts use the spell-queue CVar (not latency); channels use world latency.
local function clipSeconds(forCast)
    if forCast and GetCVar then
        local q = tonumber(GetCVar("SpellQueueWindow") or "")
        if q and q > 0 then return q / 1000 end
    end
    return (select(4, GetNetStats()) or 0) / 1000
end

local function fmtTime(remaining, duration)
    local m = mod.db.timeTextMode or "both"
    if m == "seconds" then
        return tostring(math.ceil(remaining))
    elseif m == "both" and duration and duration > 0 then
        return string.format("%.1f / %.1f", remaining, duration)
    end
    return string.format("%.1f", remaining)
end

local craftSeries   -- { name, total, done, stamp }; armed by the craft hooks, counted by the tracker below

local function seriesLabel(castName)
    if mod.db.mergeCrafts == false or not craftSeries or not castName then return nil end
    if craftSeries.name ~= castName or (craftSeries.total or 1) <= 1 then return nil end
    local done = craftSeries.done or 0
    if done < 1 then done = 1 end
    if done > craftSeries.total then done = craftSeries.total end
    return string.format("%s %d/%d", castName, done, craftSeries.total)
end

local function armCraftHooks()
    if mod._craftHooked then return end
    mod._craftHooked = true
    if type(_G.DoTradeSkill) == "function" and type(_G.GetTradeSkillInfo) == "function" then
        hooksecurefunc("DoTradeSkill", function(index, num)
            local name = GetTradeSkillInfo(index)
            if type(name) == "string" then
                craftSeries = { name = name, total = tonumber(num) or 1, done = 0, stamp = GetTime() }
            end
        end)
    end
    -- Craft API is always single-cast; hooked anyway so a different craft clears a stale series.
    if type(_G.DoCraft) == "function" and type(_G.GetCraftInfo) == "function" then
        hooksecurefunc("DoCraft", function(index)
            local name = GetCraftInfo(index)
            if type(name) == "string" then
                craftSeries = { name = name, total = 1, done = 0, stamp = GetTime() }
            end
        end)
    end
end

local Blizzard = {}

local FALLBACK_W, FALLBACK_H = 260, 18

local function bz_getBar()
    return _G.PlayerCastingBarFrame or _G.CastingBarFrame
end

local function bz_walkAndCollect(frame, depth, statusbars, textures)
    if not frame or depth > 5 then return end
    if frame.GetObjectType and frame:GetObjectType() == "StatusBar" then
        table.insert(statusbars, frame)
    end
    if frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "Texture" then
                local cr, cg, cb, ca = 1, 1, 1, 1
                if r.GetVertexColor then cr, cg, cb, ca = r:GetVertexColor() end
                table.insert(textures, { tex = r, origR = cr, origG = cg, origB = cb, origA = ca })
            end
        end
    end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do
            bz_walkAndCollect(c, depth + 1, statusbars, textures)
        end
    end
end

local function bz_ensureStatusBars(bar)
    if bar._vcui_statusbars then return end
    bar._vcui_statusbars = {}
    bar._vcui_textures   = {}
    bz_walkAndCollect(bar, 0, bar._vcui_statusbars, bar._vcui_textures)
    bar._vcui_origColors = {}
    for i, sb in ipairs(bar._vcui_statusbars) do
        local r, g, b, a = 1, 1, 1, 1
        if sb.GetStatusBarColor then r, g, b, a = sb:GetStatusBarColor() end
        bar._vcui_origColors[i] = { r = r, g = g, b = b, a = a }
    end
end

local function bz_setChannelColor(bar, isChannel)
    if not bar or not bar._vcui_statusbars then return end
    local c = mod.db.accentColor or { r = 0.75, g = 0.35, b = 1.00, a = 0.90 }

    if isChannel then
        for _, sb in ipairs(bar._vcui_statusbars) do
            if sb.SetStatusBarColor then
                sb:SetStatusBarColor(c.r, c.g, c.b, c.a or 0.9)
            end
        end
        for _, t in ipairs(bar._vcui_textures or {}) do
            if t.tex and t.tex.SetVertexColor then
                t.tex:SetVertexColor(c.r, c.g, c.b, c.a or 0.9)
            end
        end
    else
        for i, sb in ipairs(bar._vcui_statusbars) do
            local orig = bar._vcui_origColors and bar._vcui_origColors[i]
            if sb.SetStatusBarColor and orig then
                sb:SetStatusBarColor(orig.r, orig.g, orig.b, orig.a)
            end
        end
        for _, t in ipairs(bar._vcui_textures or {}) do
            if t.tex and t.tex.SetVertexColor then
                t.tex:SetVertexColor(t.origR or 1, t.origG or 1, t.origB or 1, t.origA or 1)
            end
        end
    end
end

local function bz_ensureOverlay(bar)
    if bar._vcui_overlay then return bar._vcui_overlay end
    local o = CreateFrame("Frame", nil, bar)
    o:SetAllPoints(bar)

    o.timeText = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local font, size, flags = o.timeText:GetFont()
    o.timeText:SetFont(font, (size or 10) + 2, flags)
    o.timeText:SetTextColor(1, 1, 1, 1)
    o.timeText:SetPoint("RIGHT", o, "RIGHT", -10, 3)
    o.timeText:SetJustifyH("RIGHT")
    o.timeText:SetText("")

    o.pushText = o:CreateFontString(nil, "OVERLAY")
    o.pushText:SetFont(font, (size or 10) + 2, "OUTLINE")
    o.pushText:SetPoint("BOTTOM", o, "TOP", 0, 4)
    o.pushText:SetTextColor(1, 0.25, 0.25, 1)
    o.pushText:Hide()

    o.ticks = {}

    bar._vcui_overlay = o
    return o
end

local function bz_hideAllTicks(bar)
    local o = bar and bar._vcui_overlay
    if not o or not o.ticks then return end
    for i = 1, #o.ticks do
        o.ticks[i]:Hide()
        o.ticks[i]:ClearAllPoints()
    end
    if o.clip then o.clip:Hide() end
end

-- Marks the completion end: channels drain leftward, casts fill rightward.
local function bz_showClip(bar, duration, atRight)
    local o = bar and bar._vcui_overlay
    if not o then return end
    if not (mod.db.showClipMarker and duration and duration > 0) then
        if o.clip then o.clip:Hide() end
        return
    end
    if not o.clip then
        o.clip = o:CreateTexture(nil, "ARTWORK", nil, 1)
        o.clip:SetColorTexture(1, 0.82, 0.20, 0.30)
    end
    local barW = bar:GetWidth(); if not barW or barW <= 1 then barW = FALLBACK_W end
    local barH = bar:GetHeight(); if not barH or barH <= 1 then barH = FALLBACK_H end
    local frac = clipSeconds(atRight) / duration
    if frac < 0.05 then frac = 0.05 elseif frac > 0.5 then frac = 0.5 end
    o.clip:ClearAllPoints()
    if atRight then
        o.clip:SetPoint("RIGHT", o, "RIGHT", 0, 3)
    else
        o.clip:SetPoint("LEFT", o, "LEFT", 0, 3)
    end
    o.clip:SetSize(barW * frac, barH)
    o.clip:Show()
end

local function bz_showTicks(bar, count)
    local o = bar and bar._vcui_overlay
    if not o or not mod.db.showTicks then return end
    bz_hideAllTicks(bar)
    if not count or count <= 1 then return end

    local linesToDraw = count - 1
    local barW = bar:GetWidth()
    local barH = bar:GetHeight()
    if not barW or barW <= 1 then barW = FALLBACK_W end
    if not barH or barH <= 1 then barH = FALLBACK_H end
    local tickH = barH

    for i = 1, linesToDraw do
        local t = o.ticks[i]
        if not t then
            t = o:CreateTexture(nil, "OVERLAY")
            t:SetWidth(2)
            o.ticks[i] = t
        end
        t:SetColorTexture(1, 1, 1, 0.9)
        t:SetHeight(tickH)
        t:ClearAllPoints()
        t:SetPoint("CENTER", o, "LEFT", barW * (i / count), 3)
        t:Show()
    end
end

function Blizzard:Enable()
    local bar = bz_getBar()
    if not bar then return end
    bz_ensureStatusBars(bar)
    bz_ensureOverlay(bar)

    if bar._vcui_hookedUpdate then return end
    bar._vcui_hookedUpdate = true
    local acc = 0
    bar:HookScript("OnUpdate", function(self, elapsed)
        if not mod._enabled or mod.db.mode ~= "blizzard" then return end
        acc = acc + (elapsed or 0)
        if acc < 0.03 then return end
        acc = 0

        local o = self._vcui_overlay
        if not o then return end

        if o._pushUntil then
            local rem = o._pushUntil - GetTime()
            if rem <= 0 then
                o._pushUntil = nil
                o.pushText:Hide()
            else
                o.pushText:SetAlpha(rem > 0.4 and 1 or (rem / 0.4))
            end
        end

        if not self:IsShown() then
            o.timeText:SetText("")
            bz_hideAllTicks(self)
            bz_setChannelColor(self, false)
            return
        end

        local cname, _, _, cstartMS, cendMS, cTrade = UnitChannelInfo("player")
        if cname and cendMS then
            local remaining = (cendMS - (GetTime() * 1000)) / 1000
            if remaining < 0 then remaining = 0 end
            local dur = cstartMS and (cendMS - cstartMS) / 1000
            if mod.db.showTimeText then
                o.timeText:SetText(fmtTime(remaining, dur))
            else
                o.timeText:SetText("")
            end
            local count = tickCountFor(cname, dur, cTrade)
            if count then
                bz_showTicks(self, count)
                bz_showClip(self, dur, false)
            else
                bz_hideAllTicks(self)
            end
            bz_setChannelColor(self, true)
            return
        end

        local name, _, _, startMS, endMS = UnitCastingInfo("player")
        if name and endMS then
            local remaining = (endMS - (GetTime() * 1000)) / 1000
            if remaining < 0 then remaining = 0 end
            local dur = startMS and (endMS - startMS) / 1000
            if mod.db.showTimeText then
                o.timeText:SetText(fmtTime(remaining, dur))
            else
                o.timeText:SetText("")
            end
            bz_hideAllTicks(self)
            bz_showClip(self, dur, true)
            local lbl = seriesLabel(name)
            if lbl and self.Text and self.Text.SetText then
                self.Text:SetText(lbl)
            end
            bz_setChannelColor(self, false)
            return
        end

        o.timeText:SetText("")
        bz_hideAllTicks(self)
        bz_setChannelColor(self, false)
    end)

    bar:HookScript("OnHide", function(self)
        if self._vcui_overlay then
            self._vcui_overlay.timeText:SetText("")
            bz_hideAllTicks(self)
        end
        bz_setChannelColor(self, false)
    end)

    bar:Show()
end

function Blizzard:Disable()
    local bar = bz_getBar()
    if not bar then return end
    if bar._vcui_overlay then
        bar._vcui_overlay.timeText:SetText("")
        bz_hideAllTicks(bar)
    end
    bz_setChannelColor(bar, false)
end

local Custom = {}
local cFrame
local castInfo
local c_showTestContent   -- forward declaration: the mover's editPreview closes over this

-- Puts the rounded end-cap mask on or takes it off a region, tracked per
-- object: modern is a plain rectangle, the established modes wear the mask,
-- and the user can switch between them without a /reload.
local function c_setRegionMask(region, want)
    if not (cFrame and cFrame._mask and region and region.AddMaskTexture) then return end
    if want and not region._vcui_masked then
        region:AddMaskTexture(cFrame._mask)
        region._vcui_masked = true
    elseif not want and region._vcui_masked then
        region:RemoveMaskTexture(cFrame._mask)
        region._vcui_masked = nil
    end
end

local function c_hideAllTicks()
    if not cFrame or not cFrame.ticks then return end
    for i = 1, #cFrame.ticks do
        cFrame.ticks[i]:Hide()
        cFrame.ticks[i]:ClearAllPoints()
    end
    if cFrame.clip then cFrame.clip:Hide() end
    if cFrame.clipText then cFrame.clipText:Hide() end
end

local function c_showClip(duration, atRight)
    if not (cFrame and cFrame.bar) then return end
    if not (mod.db.showClipMarker and duration and duration > 0) then
        if cFrame.clip then cFrame.clip:Hide() end
        if cFrame.clipText then cFrame.clipText:Hide() end
        return
    end
    if not cFrame.clip then
        cFrame.clip = cFrame.bar:CreateTexture(nil, "OVERLAY", nil, 6)
        cFrame.clip:SetColorTexture(1, 0.82, 0.20, 0.25)
    end
    -- Needs the fill's rounded-corner mask or the square block overhangs the
    -- end cap; modern has no cap, so there it stays bare.
    c_setRegionMask(cFrame.clip, mod.db.mode ~= "modern")
    local barW = cFrame.bar:GetWidth(); if not barW or barW <= 1 then barW = mod.db.width or 240 end
    local barH = cFrame.bar:GetHeight(); if not barH or barH <= 1 then barH = mod.db.height or 18 end
    local frac = clipSeconds(atRight) / duration
    if frac < 0.05 then frac = 0.05 elseif frac > 0.5 then frac = 0.5 end
    cFrame.clip:ClearAllPoints()
    if atRight then
        cFrame.clip:SetPoint("RIGHT", cFrame.bar, "RIGHT", 0, 0)
    else
        cFrame.clip:SetPoint("LEFT", cFrame.bar, "LEFT", 0, 0)
    end
    cFrame.clip:SetSize(barW * frac, barH)
    cFrame.clip:Show()
    -- The measured window in milliseconds beside the shaded zone (modern
    -- mode); hidden whenever the zone is.
    if mod.db.latencyText then
        if not cFrame.clipText then
            cFrame.clipText = cFrame.bar:CreateFontString(nil, "OVERLAY")
            if ns.UI and ns.UI.Font then ns.UI.Font(cFrame.clipText, 9, "OUTLINE") end
            cFrame.clipText:SetTextColor(1, 0.82, 0.20)
        end
        cFrame.clipText:ClearAllPoints()
        if atRight then
            cFrame.clipText:SetPoint("RIGHT", cFrame.clip, "LEFT", -2, 0)
        else
            cFrame.clipText:SetPoint("LEFT", cFrame.clip, "RIGHT", 2, 0)
        end
        cFrame.clipText:SetFormattedText("%d ms", clipSeconds(atRight) * 1000 + 0.5)
        cFrame.clipText:Show()
    elseif cFrame.clipText then
        cFrame.clipText:Hide()
    end
end

local function c_showTicks(count)
    if not cFrame or not mod.db.showTicks then return end
    c_hideAllTicks()
    if not count or count <= 1 then return end

    local linesToDraw = count - 1
    local barW = cFrame.bar:GetWidth()
    local barH = cFrame.bar:GetHeight()
    if not barW or barW <= 1 then barW = mod.db.width or 240 end
    if not barH or barH <= 1 then barH = mod.db.height or 18 end
    local tickH = barH

    for i = 1, linesToDraw do
        local t = cFrame.ticks[i]
        if not t then
            -- Parented to the bar, not cFrame, so it draws above the StatusBar texture.
            t = cFrame.bar:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetWidth(2)
            cFrame.ticks[i] = t
        end
        -- The LAST tick may carry its own colour (modern mode): it is the one
        -- worth watching -- clipping past it costs the final tick.
        local lc = (mod.db.lastTickOn and i == linesToDraw) and mod.db.lastTickColor or nil
        if lc then
            t:SetColorTexture(lc.r, lc.g, lc.b, 0.9)
        else
            t:SetColorTexture(1, 1, 1, 0.7)
        end
        t:SetHeight(tickH)
        t:ClearAllPoints()
        t:SetPoint("CENTER", cFrame.bar, "LEFT", barW * (i / count), 0)
        t:Show()
    end
end

local function c_applyColor(color)
    if not cFrame or not color then return end
    cFrame.bar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
end

-- Near-white base for the tintable fill modes; the yellow/green art muddies any color multiplied onto it.
local TEX_NEUTRAL = "Interface\\AddOns\\VuloClassicUI\\Media\\textures\\matte"

-- Solid edges around the whole bar, the power-bar recipe; size 0 keeps them
-- hidden, which is what the two established modes ship with.
local function c_applyBorder()
    if not cFrame then return end
    if not cFrame.edges then
        if (mod.db.borderSize or 0) <= 0 then return end
        cFrame.edges = ns.MakeEdges(cFrame, "OVERLAY")
    end
    local c = mod.db.borderColor or { r = 0, g = 0, b = 0 }
    ns.LayoutEdges(cFrame.edges, cFrame, mod.db.borderSize or 0, c.r, c.g, c.b, 1, 0)
end

-- A chosen shared-media texture beats the built-in art in EVERY fill mode;
-- "" keeps the classic look.
local function c_lsmTexture()
    local name = mod.db.barTexture
    if name and name ~= "" and ns.MediaStatusbar then
        return ns.MediaStatusbar(name)
    end
end

local function c_applyFill(isChannel)
    if not (cFrame and cFrame.bar) then return end
    c_applyBorder()
    local fm = mod.db.fillMode or "texture"
    if fm == "texture" then
        cFrame.bar:SetStatusBarTexture(c_lsmTexture() or (isChannel and TEX_CHANNEL or TEX_FILL))
        if cFrame._applyMask then cFrame._applyMask() end
        c_applyColor({ r = 1, g = 1, b = 1, a = 1 })
        return
    end
    cFrame.bar:SetStatusBarTexture(c_lsmTexture() or TEX_NEUTRAL)
    local t = cFrame.bar:GetStatusBarTexture()
    if t then
        if t.SetHorizTile then t:SetHorizTile(false) end
        if t.SetVertTile  then t:SetVertTile(false)  end
    end
    if cFrame._applyMask then cFrame._applyMask() end
    local c
    if fm == "class" then
        local _, token = UnitClass("player")
        c = token and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    end
    c = c or mod.db.accentColor or { r = 0.608, g = 0.424, b = 1.000 }
    c_applyColor({ r = c.r, g = c.g, b = c.b, a = 1 })
end

-- Modern wears the flat preview look (user request, 31.07.2026): spell name
-- and timer ON the bar, plain dark background, borderless icon, no spark.
-- The two established modes keep their classic dress -- texts below the bar,
-- Blizzard background art, 1px icon frame. Runs on create, layout changes
-- and every mode switch.
local function c_applySkin()
    if not cFrame then return end
    local modern = (mod.db.mode == "modern")
    cFrame.nameText:ClearAllPoints()
    cFrame.timeText:ClearAllPoints()
    cFrame.nameText:SetWordWrap(false)
    if modern then
        cFrame.timeText:SetPoint("RIGHT", cFrame.bar, "RIGHT", -4, 0)
        cFrame.nameText:SetPoint("LEFT", cFrame.bar, "LEFT", 4, 0)
        -- capped at the timer so a long spell name truncates instead of
        -- running underneath it (the timer keeps its anchor while hidden)
        cFrame.nameText:SetPoint("RIGHT", cFrame.timeText, "LEFT", -4, 0)
        if ns.UI and ns.UI.Font then
            ns.UI.Font(cFrame.nameText, 11, "OUTLINE")
            ns.UI.Font(cFrame.timeText, 11, "OUTLINE")
        end
        -- reset the classic dress's gray vertex tint first: it would multiply
        -- into the flat color and turn the background pure black
        cFrame.bg:SetVertexColor(1, 1, 1, 1)
        cFrame.bg:SetColorTexture(0.05, 0.05, 0.06, 0.85)
        cFrame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        cFrame.spark:Hide()
    else
        cFrame.nameText:SetPoint("TOPLEFT", cFrame, "BOTTOMLEFT", 2, -2)
        cFrame.timeText:SetPoint("TOPRIGHT", cFrame, "BOTTOMRIGHT", -2, -2)
        cFrame.nameText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        cFrame.timeText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        cFrame.bg:SetTexture(TEX_BG)
        cFrame.bg:SetVertexColor(0.1, 0.1, 0.1, 0.85)
        cFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- a cast that is running through a modern->custom switch gets its
        -- leading spark back (channels never show one)
        cFrame.spark:SetShown(castInfo ~= nil and not castInfo.isChannel and not castInfo.fadeOut)
    end
    -- re-evaluates the icon frame: modern shows the icon without the 1px edges
    cFrame.setIconShown(mod.db.showIcon)
end

local function c_create()
    if cFrame then return cFrame end

    cFrame = CreateFrame("Frame", "VCUI_PlayerCastbar", UIParent)
    cFrame:SetSize(mod.db.width, mod.db.height)
    cFrame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)
    cFrame:SetFrameStrata("MEDIUM")
    cFrame:SetMovable(true)
    cFrame:SetClampedToScreen(false)
    cFrame:Hide()

    cFrame.mover = ns:CreateMover(cFrame, {
        key    = "castbar",
        label  = L["|cffffffffCASTBAR|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = mod.db,
        width  = math.max(mod.db.width + 60, 200),
        height = math.max(60, mod.db.height + 40),
        onMove = function(x, y)
            ns:Print(string.format(L["Castbar position: x=%.0f, y=%.0f"], x, y))
        end,
        editPreview = function(show)
            if show then c_showTestContent()
            elseif not castInfo and not mod.db.unlocked then cFrame:Hide() end
        end,
    })

    -- Mouse stays off cFrame itself; it would conflict with the mover overlay.
    cFrame:EnableMouse(false)

    cFrame.icon = cFrame:CreateTexture(nil, "BORDER")
    cFrame.icon:SetSize(mod.db.iconSize, mod.db.iconSize)
    cFrame.icon:SetPoint("RIGHT", cFrame, "LEFT",
        -(mod.db.iconGap or 3) + (mod.db.iconX or 0), (mod.db.iconY or 0))
    cFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local function makeIconEdge()
        local t = cFrame:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        return t
    end
    cFrame.iconBorderT = makeIconEdge()
    cFrame.iconBorderT:SetPoint("BOTTOMLEFT",  cFrame.icon, "TOPLEFT",  -1, 0)
    cFrame.iconBorderT:SetPoint("BOTTOMRIGHT", cFrame.icon, "TOPRIGHT",  1, 0)
    cFrame.iconBorderT:SetHeight(1)

    cFrame.iconBorderB = makeIconEdge()
    cFrame.iconBorderB:SetPoint("TOPLEFT",     cFrame.icon, "BOTTOMLEFT",  -1, 0)
    cFrame.iconBorderB:SetPoint("TOPRIGHT",    cFrame.icon, "BOTTOMRIGHT",  1, 0)
    cFrame.iconBorderB:SetHeight(1)

    cFrame.iconBorderL = makeIconEdge()
    cFrame.iconBorderL:SetPoint("TOPRIGHT",    cFrame.icon, "TOPLEFT",     0,  1)
    cFrame.iconBorderL:SetPoint("BOTTOMRIGHT", cFrame.icon, "BOTTOMLEFT",  0, -1)
    cFrame.iconBorderL:SetWidth(1)

    cFrame.iconBorderR = makeIconEdge()
    cFrame.iconBorderR:SetPoint("TOPLEFT",     cFrame.icon, "TOPRIGHT",    0,  1)
    cFrame.iconBorderR:SetPoint("BOTTOMLEFT",  cFrame.icon, "BOTTOMRIGHT", 0, -1)
    cFrame.iconBorderR:SetWidth(1)

    cFrame.setIconShown = function(state)
        cFrame.icon:SetShown(state)
        -- the 1px frame belongs to the classic dress; modern is borderless
        local edge = state and mod.db.mode ~= "modern"
        cFrame.iconBorderT:SetShown(edge)
        cFrame.iconBorderB:SetShown(edge)
        cFrame.iconBorderL:SetShown(edge)
        cFrame.iconBorderR:SetShown(edge)
    end

    cFrame.bar = CreateFrame("StatusBar", nil, cFrame)
    cFrame.bar:SetAllPoints(cFrame)
    cFrame.bar:SetStatusBarTexture(TEX_FILL)
    cFrame.bar:SetMinMaxValues(0, 1)
    cFrame.bar:SetValue(0)
    -- Just an initial value on a frame that is still hidden: every cast runs
    -- c_applyFill before showing it, so this is never what anyone sees. It used
    -- to read a saved castColor, which is why that setting could not be exposed
    -- as an option - it would have been a control with nothing to change.
    c_applyColor({ r = 1, g = 1, b = 1, a = 1 })

    cFrame.bg = cFrame.bar:CreateTexture(nil, "BACKGROUND")
    cFrame.bg:SetAllPoints(cFrame.bar)
    cFrame.bg:SetTexture(TEX_BG)
    cFrame.bg:SetVertexColor(0.1, 0.1, 0.1, 0.85)

    local function applyMask()
        local fillTex = cFrame.bar:GetStatusBarTexture()
        if fillTex and fillTex.AddMaskTexture and not cFrame._mask then
            cFrame._mask = cFrame.bar:CreateMaskTexture()
            cFrame._mask:SetTexture(TEX_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            cFrame._mask:SetAllPoints(cFrame.bar)
        end
        -- The StatusBar reuses its texture object across SetStatusBarTexture,
        -- so the helper tracks each object; modern strips the mask everywhere
        -- for its plain-rectangle look, the established modes wear it.
        local want = mod.db.mode ~= "modern"
        c_setRegionMask(fillTex, want)
        c_setRegionMask(cFrame.bg, want)
        c_setRegionMask(cFrame.pushFlash, want)
        c_setRegionMask(cFrame.clip, want)
    end
    cFrame._applyMask = applyMask
    applyMask()

    cFrame.spark = cFrame.bar:CreateTexture(nil, "OVERLAY")
    cFrame.spark:SetTexture(TEX_SPARK)
    cFrame.spark:SetBlendMode("ADD")
    cFrame.spark:SetSize(16, mod.db.height + 8)

    local font = "Fonts\\FRIZQT__.TTF"
    -- The texts live on their own layer ABOVE the bar: cFrame's regions draw
    -- under the child StatusBar, so on-bar texts (modern) would be buried
    -- beneath the fill. Above the bar's ticks/clip too, so the name reads
    -- over a crossing tick line instead of being cut by it.
    cFrame.textFrame = CreateFrame("Frame", nil, cFrame.bar)
    cFrame.textFrame:SetAllPoints(cFrame.bar)
    cFrame.textFrame:SetFrameLevel(cFrame.bar:GetFrameLevel() + 2)

    cFrame.nameText = cFrame.textFrame:CreateFontString(nil, "OVERLAY")
    cFrame.nameText:SetFont(font, 11, "OUTLINE")
    cFrame.nameText:SetPoint("TOPLEFT", cFrame, "BOTTOMLEFT", 2, -2)
    cFrame.nameText:SetJustifyH("LEFT")
    cFrame.nameText:SetTextColor(1, 1, 1)

    cFrame.timeText = cFrame.textFrame:CreateFontString(nil, "OVERLAY")
    cFrame.timeText:SetFont(font, 11, "OUTLINE")
    cFrame.timeText:SetPoint("TOPRIGHT", cFrame, "BOTTOMRIGHT", -2, -2)
    cFrame.timeText:SetJustifyH("RIGHT")
    cFrame.timeText:SetTextColor(1, 1, 1)

    cFrame.pushText = cFrame:CreateFontString(nil, "OVERLAY")
    cFrame.pushText:SetFont(font, 12, "OUTLINE")
    cFrame.pushText:SetPoint("BOTTOM", cFrame, "TOP", 0, 3)
    cFrame.pushText:SetTextColor(1, 0.25, 0.25)
    cFrame.pushText:Hide()

    cFrame.pushFlash = cFrame.bar:CreateTexture(nil, "OVERLAY", nil, 5)
    cFrame.pushFlash:SetAllPoints(cFrame.bar)
    cFrame.pushFlash:SetColorTexture(1, 0.2, 0.2, 0.35)
    c_setRegionMask(cFrame.pushFlash, mod.db.mode ~= "modern")
    cFrame.pushFlash:Hide()

    cFrame.ticks = {}

    cFrame:SetScript("OnUpdate", function(self, elapsed)
        if self._pushUntil then
            local rem = self._pushUntil - GetTime()
            if rem <= 0 then
                self._pushUntil = nil
                self.pushText:Hide()
                self.pushFlash:Hide()
            else
                local a = rem > 0.4 and 1 or (rem / 0.4)
                self.pushText:SetAlpha(a)
                self.pushFlash:SetAlpha(a * 0.35)
            end
        end

        if not castInfo then
            if not (mod.db.unlocked or ns:IsMoverEditMode()) then self:Hide() end
            return
        end
        local nowMS = GetTime() * 1000

        if castInfo.fadeOut then
            castInfo.fadeTimer = (castInfo.fadeTimer or 0) - elapsed
            if castInfo.fadeTimer <= 0 then
                castInfo = nil
                if not (mod.db.unlocked or ns:IsMoverEditMode()) then self:Hide() end
                return
            end
            self:SetAlpha(castInfo.fadeTimer / 0.5)
            return
        end

        local sMS, eMS = castInfo.startMS, castInfo.endMS
        local duration = (eMS - sMS) / 1000
        if duration <= 0 then duration = 0.01 end

        local progress, remaining
        if castInfo.isChannel then
            remaining = math.max(0, (eMS - nowMS) / 1000)
            progress  = remaining / duration
        else
            local el = math.max(0, (nowMS - sMS) / 1000)
            if el > duration then el = duration end
            progress  = el / duration
            remaining = math.max(0, duration - el)
        end

        -- Glide at bounded speed so pushback/clipping jumps don't snap.
        local disp = castInfo.disp
        if disp == nil then
            disp = progress
        else
            local diff = progress - disp
            local maxStep = (elapsed or 0) * math.max(4, 2 / duration)
            if diff > maxStep then disp = disp + maxStep
            elseif diff < -maxStep then disp = disp - maxStep
            else disp = progress end
        end
        castInfo.disp = disp

        self.bar:SetValue(disp)
        self.spark:ClearAllPoints()
        self.spark:SetPoint("CENTER", self.bar, "LEFT", self.bar:GetWidth() * disp, 0)

        self._textAcc = (self._textAcc or 0) + elapsed
        if self._textAcc >= 0.05 then
            self._textAcc = 0
            local str = mod.db.showTimeText and fmtTime(remaining, duration) or ""
            if str ~= self._lastTimeText then
                self._lastTimeText = str
                self.timeText:SetText(str)
            end
        end

        if (not castInfo.isChannel and progress >= 1)
        or (castInfo.isChannel and progress <= 0) then
            castInfo.fadeOut = true
            castInfo.fadeTimer = 0.5
        end
    end)

    c_applySkin()
    return cFrame
end

local function c_startCast(isChannel)
    c_create()
    local name, _, icon, sMS, eMS, cTrade
    if isChannel then
        name, _, icon, sMS, eMS, cTrade = UnitChannelInfo("player")
    else
        name, _, icon, sMS, eMS = UnitCastingInfo("player")
    end
    if not name or not sMS or not eMS then return end

    castInfo = { name = name, icon = icon, startMS = sMS, endMS = eMS, isChannel = isChannel }
    cFrame._textAcc, cFrame._lastTimeText = 1, nil
    cFrame:SetAlpha(1)
    cFrame:Show()
    cFrame.icon:SetTexture(icon)
    cFrame.setIconShown(mod.db.showIcon)
    cFrame.nameText:SetText(mod.db.showSpellName and (seriesLabel(name) or name) or "")

    c_applyFill(isChannel)
    if isChannel then
        local cdur  = sMS and eMS and (eMS - sMS) / 1000
        local count = tickCountFor(name, cdur, cTrade)
        if count then
            c_showTicks(count)
            c_showClip(cdur, false)
        else
            c_hideAllTicks()
        end
        cFrame.spark:Hide()
    else
        local dur = sMS and eMS and (eMS - sMS) / 1000
        c_hideAllTicks()
        c_showClip(dur, true)
        -- the flat modern look has no spark
        cFrame.spark:SetShown(mod.db.mode ~= "modern")
    end
end

local function c_stopCast(success)
    if not cFrame or not castInfo then return end
    -- A late event inside the 0.5s fade window must not restart or recolor it.
    if castInfo.fadeOut then return end
    c_applyColor(success and mod.db.successColor or mod.db.failColor)
    c_hideAllTicks()
    cFrame.spark:Hide()
    -- Snap to the completed state so the fade doesn't start from a mid-frame value.
    if success then cFrame.bar:SetValue(castInfo.isChannel and 0 or 1) end
    castInfo.fadeOut = true
    castInfo.fadeTimer = 0.5
end

local c_eventFrame
function Custom:Enable()
    c_create()
    if not c_eventFrame then
        c_eventFrame = CreateFrame("Frame")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START",          "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED",        "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP",           "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",      "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",         "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET",   "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED",    "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START",  "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP",   "player")

        c_eventFrame:SetScript("OnEvent", function(_, event, unit, castGUIDorSpellID, spellID)
            if unit ~= "player" or not mod._enabled or (mod.db.mode ~= "custom" and mod.db.mode ~= "modern") then return end

            if event == "UNIT_SPELLCAST_START" then
                c_startCast(false)
            elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
                c_startCast(true)
            elseif event == "UNIT_SPELLCAST_DELAYED" then
                if castInfo and not castInfo.isChannel then
                    local _, _, _, s, e = UnitCastingInfo("player")
                    if s and e then castInfo.startMS = s; castInfo.endMS = e end
                end
            elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
                if castInfo and castInfo.isChannel then
                    local _, _, _, s, e = UnitChannelInfo("player")
                    if s and e then castInfo.startMS = s; castInfo.endMS = e end
                end
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                if castInfo and not castInfo.isChannel then c_stopCast(true) end
            elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
                c_stopCast(true)
            elseif event == "UNIT_SPELLCAST_STOP" then
                -- STOP also fires on pushback, so confirm the cast is really over.
                if castInfo and not castInfo.isChannel and not castInfo.fadeOut then
                    local stillCasting = UnitCastingInfo("player")
                    if not stillCasting then
                        c_stopCast(true)
                    end
                end
            elseif event == "UNIT_SPELLCAST_FAILED"
                or event == "UNIT_SPELLCAST_FAILED_QUIET" then
                -- FAILED_QUIET often fires for attempts during an ongoing cast; only abort if nothing is running.
                if castInfo and not castInfo.fadeOut then
                    local stillCasting = UnitCastingInfo("player") or UnitChannelInfo("player")
                    if not stillCasting then
                        c_stopCast(false)
                    end
                end
            elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
                if castInfo then c_stopCast(false) end
            end
        end)
    end

    local b = bz_getBar()
    if b then
        if b.UnregisterAllEvents then b:UnregisterAllEvents() end
        if b.Hide then b:Hide() end
        if not b._vcui_hideHooked then
            b._vcui_hideHooked = true
            b:HookScript("OnShow", function(self)
                if mod._enabled and (mod.db.mode == "custom" or mod.db.mode == "modern") then self:Hide() end
            end)
        end
    end
end

function Custom:Disable()
    if cFrame then cFrame:Hide() end
    castInfo = nil
end

local function c_applyLayout()
    if not cFrame then return end
    cFrame:SetSize(mod.db.width, mod.db.height)
    cFrame:ClearAllPoints()
    cFrame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)
    cFrame.icon:SetSize(mod.db.iconSize, mod.db.iconSize)
    cFrame.icon:ClearAllPoints()
    cFrame.icon:SetPoint("RIGHT", cFrame, "LEFT",
        -(mod.db.iconGap or 3) + (mod.db.iconX or 0), (mod.db.iconY or 0))
    cFrame.spark:SetHeight(mod.db.height + 8)
    c_applySkin()
end

c_showTestContent = function()
    cFrame:Show()
    cFrame:SetAlpha(1)
    cFrame.bar:SetValue(0.7)
    cFrame.nameText:SetText(L["|cff9b6cffMind Flay|r"])
    cFrame.timeText:SetText("1.5 / 2.0")
    cFrame.icon:SetTexture("Interface\\Icons\\Spell_Nature_Earthbind")
    cFrame.setIconShown(mod.db.showIcon)
    c_applyFill(true)
    c_showTicks(3)
    c_showClip(3, false)
end

local function c_setUnlocked(state)
    mod.db.unlocked = state
    c_create()
    if state then
        c_showTestContent()
        cFrame.mover:Show()
        ns:Print(L["Castbar mover active. |cff9b6cffDrag purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Test' again to finish."])
    else
        cFrame.mover:Hide()
        c_hideAllTicks()
        if not castInfo then cFrame:Hide() end
        ns:Print(L["Castbar mover disabled."])
    end
end

-- Keeps its own end-time snapshots: event order between this and the mode handlers is undefined.
local function showPushback(txt)
    if mod.db.showPushback == false then return end
    if (mod.db.mode == "custom" or mod.db.mode == "modern") then
        if cFrame and cFrame.pushText and cFrame:IsShown() then
            cFrame.pushText:SetText(txt)
            cFrame.pushText:SetAlpha(1)
            cFrame.pushText:Show()
            cFrame.pushFlash:SetAlpha(0.35)
            cFrame.pushFlash:Show()
            cFrame._pushUntil = GetTime() + 0.9
        end
    else
        local bar = bz_getBar()
        local o = bar and bar._vcui_overlay
        if o and o.pushText and bar:IsShown() then
            o.pushText:SetText(txt)
            o.pushText:SetAlpha(1)
            o.pushText:Show()
            o._pushUntil = GetTime() + 0.9
        end
    end
end

local tracker
local function ensureTracker()
    if tracker then return end
    tracker = CreateFrame("Frame")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_START",          "player")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_STOP",           "player")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED",        "player")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START",  "player")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP",   "player")
    tracker:SetScript("OnEvent", function(self, event)
        if not mod._enabled then return end

        if event == "UNIT_SPELLCAST_STOP" then
            self.castEnd = nil     -- a stale snapshot would fake a pushback
            return
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            self.chanEnd = nil
            return
        end

        if event == "UNIT_SPELLCAST_START" then
            local name, _, _, _, endMS = UnitCastingInfo("player")
            self.castEnd = endMS
            if craftSeries and name then
                if name == craftSeries.name and (GetTime() - craftSeries.stamp) < 30 then
                    craftSeries.done  = (craftSeries.done or 0) + 1
                    craftSeries.stamp = GetTime()
                else
                    craftSeries = nil
                end
                -- The custom bar may have painted its label before this handler ran, so repaint it.
                if (mod.db.mode == "custom" or mod.db.mode == "modern") and cFrame and castInfo
                   and not castInfo.isChannel and mod.db.showSpellName then
                    cFrame.nameText:SetText(seriesLabel(name) or name)
                end
            end

        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            self.chanEnd = select(5, UnitChannelInfo("player"))

        elseif event == "UNIT_SPELLCAST_DELAYED" then
            local _, _, _, _, endMS = UnitCastingInfo("player")
            if endMS and self.castEnd and endMS > self.castEnd + 10 then
                showPushback(string.format("+%.1fs", (endMS - self.castEnd) / 1000))
            end
            if endMS then self.castEnd = endMS end

        elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            local endMS = select(5, UnitChannelInfo("player"))
            if endMS and self.chanEnd and endMS < self.chanEnd - 10 then
                showPushback(string.format("-%.1fs", (self.chanEnd - endMS) / 1000))
            end
            if endMS then self.chanEnd = endMS end
        end
    end)
end

local function switchMode(newMode)
    -- "modern" runs on the SAME engine as "custom" (the VUI bar) -- the mode
    -- exists so its options page can grow the reference-style surface without
    -- touching the custom mode's familiar one.
    if newMode ~= "blizzard" and newMode ~= "custom" and newMode ~= "modern" then return end
    mod.db.mode = newMode

    if newMode == "blizzard" then
        Custom:Disable()
        -- The default bar's events cannot be re-registered without a /reload.
        Blizzard:Enable()
    else
        Blizzard:Disable()
        Custom:Enable()
        -- Redress a bar that already exists: custom<->modern switches swap the
        -- whole skin (text anchors, mask, background) without a /reload.
        c_applySkin()
        if castInfo then c_applyFill(castInfo.isChannel)
        elseif mod.db.unlocked then c_showTestContent() end
    end
end

function mod:OnEnable()
    -- A saved unlock keeps the castbar visible when nothing is being cast, and
    -- setUnlocked - the only thing that shows the mover - never runs on load.
    if mod.db then mod.db.unlocked = false end
    ensureTracker()
    armCraftHooks()
    local function isOldDefault(c)
        return c and math.abs((c.r or 0) - 0.75) < 0.01
                 and math.abs((c.g or 0) - 0.35) < 0.01
                 and math.abs((c.b or 0) - 1.00) < 0.01
    end
    if isOldDefault(mod.db.channelColor) then
        mod.db.channelColor = { r = 0.608, g = 0.424, b = 1.000, a = 1.00 }
    end
    if isOldDefault(mod.db.accentColor) then
        mod.db.accentColor = { r = 0.608, g = 0.424, b = 1.000, a = 0.90 }
    end

    if (mod.db.mode == "custom" or mod.db.mode == "modern") then
        Custom:Enable()
    else
        Blizzard:Enable()
    end
end

function mod:OnDisable()
    Custom:Disable()
    Blizzard:Disable()
end

-- ---------------------------------------------------------------------------
-- Options-page live preview: a mock castbar pinned above the scroll area,
-- styled from the same db keys the real bar reads -- fill and timer are fake
-- (2.5 of 3.0 seconds), so there is something to see without casting.

local pv

local function pvStyle()
    if not (pv and pv:IsVisible()) then return end
    local d = mod.db
    local hostW = pv:GetWidth() or 500
    local w = math.min(d.width or 240, math.max(160, hostW - 60))
    local h = math.min(d.height or 18, 30)
    pv.holder:SetSize(w, h)
    -- Mirrors c_applyFill: a chosen shared-media texture beats the built-in
    -- art in every fill mode; the fill colour follows the mode.
    local lsm
    if d.barTexture and d.barTexture ~= "" and ns.MediaStatusbar then
        lsm = ns.MediaStatusbar(d.barTexture)
    end
    local fm = d.fillMode or "texture"
    if fm == "texture" then
        pv.bar:SetStatusBarTexture(lsm or TEX_FILL)
        pv.bar:SetStatusBarColor(1, 1, 1)
    else
        pv.bar:SetStatusBarTexture(lsm or TEX_NEUTRAL)
        local c
        if fm == "class" then
            local _, token = UnitClass("player")
            c = token and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
        end
        c = c or d.accentColor or { r = 0.608, g = 0.424, b = 1 }
        pv.bar:SetStatusBarColor(c.r, c.g, c.b)
    end
    pv.bar:SetMinMaxValues(0, 3)
    pv.bar:SetValue(2.5)
    pv.bg:SetColorTexture(0.05, 0.05, 0.06, 0.85)
    -- the modern border, same recipe as the real bar
    if not pv.edges then pv.edges = ns.MakeEdges(pv.holder, "OVERLAY") end
    local bc = d.borderColor or { r = 0, g = 0, b = 0 }
    ns.LayoutEdges(pv.edges, pv.holder, d.borderSize or 0, bc.r, bc.g, bc.b, 1, 0)
    pv.icon:SetShown(d.showIcon ~= false)
    pv.icon:SetSize(h, h)
    if ns.UI and ns.UI.Font then
        ns.UI.Font(pv.name, 11, "OUTLINE")
        ns.UI.Font(pv.timer, 11, "OUTLINE")
    end
    pv.name:SetShown(d.showSpellName ~= false)
    pv.timer:SetShown(d.showTimeText ~= false)
    pv.timer:SetText(d.timeTextMode == "seconds" and "3"
        or d.timeTextMode == "remaining" and "2.5" or "2.5 / 3.0")
end

function mod.BuildPreview(host)
    -- Modern only (user request, 31.07.2026): the mock IS the modern dress --
    -- in the other two modes it would promise a look they do not render.
    -- 0 hides the header.
    if mod.db.mode ~= "modern" then
        if pv then pv:Hide() end
        return 0
    end
    if not pv then
        pv = CreateFrame("Frame", nil, host)
        pv.holder = CreateFrame("Frame", nil, pv)
        pv.holder:SetPoint("CENTER", pv, "CENTER", 8, 0)
        pv.bg = pv.holder:CreateTexture(nil, "BACKGROUND")
        pv.bg:SetAllPoints(pv.holder)
        pv.bar = CreateFrame("StatusBar", nil, pv.holder)
        pv.bar:SetAllPoints(pv.holder)
        pv.icon = pv.holder:CreateTexture(nil, "ARTWORK")
        pv.icon:SetPoint("RIGHT", pv.holder, "LEFT", -3, 0)
        pv.icon:SetTexture("Interface\\Icons\\Spell_Fire_FlameBolt")
        pv.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        pv.name = pv.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        pv.name:SetPoint("LEFT", pv.bar, "LEFT", 4, 0)
        pv.name:SetText(L["Spell name"])
        pv.timer = pv.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        pv.timer:SetPoint("RIGHT", pv.bar, "RIGHT", -4, 0)

        -- Click-to-navigate (user request, 31.07.2026): this page announces
        -- its groups with plain HEADER rows, not sections, so the jump scans
        -- header widgets -- the sibling of the nameplate preview's section
        -- scan. Matches raw and upper-cased text, whichever the widget shows.
        local function scrollToHeader(title)
            local UIW = ns.UI
            local mf = UIW and UIW.mainFrame
            local sc, sf = mf and mf.scrollChild, mf and mf.scroll
            if not (sc and sf) then return end
            local up = string.upper(title)
            for _, child in ipairs({ sc:GetChildren() }) do
                -- headers on the classic pages, section widgets on the modern
                if child._vcType == "header" or child._vcType == "collapsible" then
                    for _, r in ipairs({ child:GetRegions() }) do
                        if r.GetText then
                            local t = r:GetText()
                            if t == title or t == up then
                                local top, scTop = child:GetTop(), sc:GetTop()
                                if top and scTop then
                                    local off = scTop - top - 4
                                    local max = (sc:GetHeight() or 0) - (sf:GetHeight() or 0)
                                    if max < 0 then max = 0 end
                                    if off < 0 then off = 0 elseif off > max then off = max end
                                    sf:SetVerticalScroll(off)
                                end
                                return
                            end
                        end
                    end
                end
            end
        end
        -- Title resolved at CLICK time: the target differs per mode (modern
        -- has its own sections, the VUI mode its headers).
        local function makeZone(region, titleFn)
            local z = CreateFrame("Button", nil, pv)
            z:SetAllPoints(region)
            z:SetFrameLevel((pv.holder:GetFrameLevel() or 1) + 10)
            local hl = z:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(z)
            hl:SetColorTexture(1, 1, 1, 0.08)
            z:SetScript("OnClick", function() scrollToHeader(titleFn()) end)
            ns.UI:AttachTooltip(z, function()
                return { title = titleFn(),
                    lines = { { L["Click: open these settings"], 0.7, 0.7, 0.75 } } }
            end)
        end
        makeZone(pv.icon, function()
            return mod.db.mode == "modern" and L["Layout"] or L["VUI Style: Position & Size"]
        end)
        makeZone(pv.holder, function()
            return mod.db.mode == "modern" and L["Display"] or L["General"]
        end)

        pv._acc = 0
        pv:SetScript("OnUpdate", function(self, e)
            self._acc = self._acc + e
            if self._acc < 0.25 then return end
            self._acc = 0
            pvStyle()
        end)
    end
    pv:SetParent(host)
    pv:ClearAllPoints()
    pv:SetPoint("TOPLEFT", host, "TOPLEFT", 14, -4)
    pv:SetPoint("TOPRIGHT", host, "TOPRIGHT", -14, -4)
    pv:SetHeight(44)
    pv:Show()
    pvStyle()
    return 44
end

function mod:GetOptions()
    local items = {}

    table.insert(items, { type = "header", text = L["Mode"] })
    -- The two-choice dropdown, back by request (31.07.2026) after a short
    -- detour as a button pair. One addition over the original: the page
    -- rebuilds on switch, so the mode's own sections appear immediately.
    table.insert(items, {
        type = "dropdown", label = L["Castbar Variant"],
        width = 320,
        tooltip = L["Switch between Original (Blizzard bar extended) and Custom castbar (VUI style with icon, spell name below bar)."],
        values = {
            { value = "blizzard", text = L["Original (Blizzard bar extended)"] },
            { value = "custom",   text = L["Custom Castbar (VUI style)"] },
            { value = "modern",   text = L["Modern"] },
        },
        get = function() return mod.db.mode end,
        set = function(_, v)
            switchMode(v)
            if v == "blizzard" then
                ns:Print(L["Castbar mode switched to |cff9b6cffOriginal|r. |cffffff00/reload|r recommended so the default bar works normally again."])
            else
                ns:Print(L["Castbar mode switched to |cff9b6cffVUI Style|r."])
            end
            if ns.UI then ns.UI:RebuildCurrentPage() end
        end,
    })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaMode switch: A /reload may be required after switching so the default bar works normally again.|r"] })

    -- Modern gets its own reference-grouped page below; the flat General
    -- block belongs to the two established modes.
    if mod.db.mode ~= "modern" then
    table.insert(items, { type = "spacer", height = 8 })
    table.insert(items, { type = "header", text = L["General"] })

    table.insert(items, {
        type = "toggle", label = L["Show spell name"],
        get = function() return mod.db.showSpellName end,
        set = function(_, v) mod.db.showSpellName = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show cast timer"],
        get = function() return mod.db.showTimeText end,
        set = function(_, v) mod.db.showTimeText = v end,
    })
    table.insert(items, {
        type = "dropdown", label = L["Timer format"],
        width = 280,
        values = {
            { value = "both",      text = L["Remaining / total (1.5 / 2.0)"] },
            { value = "remaining", text = L["Remaining only (1.5)"] },
            { value = "seconds",   text = L["Whole seconds (2)"] },
        },
        get = function() return mod.db.timeTextMode or "both" end,
        set = function(_, v) mod.db.timeTextMode = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show channel ticks"],
        tooltip = L["Shows vertical lines at tick points (Mind Flay, Drain Soul, Hellfire, etc.)"],
        get = function() return mod.db.showTicks end,
        set = function(_, v) mod.db.showTicks = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show clip window"],
        tooltip = L["Shades your latency at the end of the bar: on channels the moment to recast without losing the last tick, on casts the spell-queue window where the next cast can already be pressed."],
        get = function() return mod.db.showClipMarker end,
        set = function(_, v) mod.db.showClipMarker = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show pushback"],
        tooltip = L["Briefly shows the time lost to spell pushback in red above the bar."],
        get = function() return mod.db.showPushback ~= false end,
        set = function(_, v) mod.db.showPushback = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Merge crafting casts"],
        tooltip = L["When crafting several items in a row the bar shows a counter like 3/20 instead of single casts."],
        get = function() return mod.db.mergeCrafts ~= false end,
        set = function(_, v) mod.db.mergeCrafts = v end,
    })

    end

    if mod.db.mode == "custom" then
        table.insert(items, { type = "spacer", height = 8 })
        table.insert(items, { type = "header", text = L["VUI Style: Position & Size"] })
        table.insert(items, {
            type = "group", layout = "row", gap = 8,
            items = {
                { type = "button", label = L["Unlock / Test"], width = 130,
                  onClick = function() c_setUnlocked(not mod.db.unlocked) end },
                { type = "button", label = L["Center Position"], width = 170,
                  onClick = function()
                      mod.db.x = 0; mod.db.y = -180
                      c_applyLayout()
                  end },
            },
        })
        table.insert(items, { type = "desc",
            text = L["|cffaaaaaaTip: Hold |cffffffffSHIFT|r and drag the castbar with the left mouse button during a cast to move it. Or use 'Unlock / Test' for a permanent test bar for positioning.|r"] })
        table.insert(items, {
            type = "toggle", label = L["Show icon"],
            get = function() return mod.db.showIcon end,
            set = function(_, v)
                mod.db.showIcon = v
                if cFrame then cFrame.setIconShown(v) end
            end,
        })
        table.insert(items, {
            type = "dropdown", label = L["Fill color"],
            width = 280,
            tooltip = L["Bar textures = the classic yellow/green art. Accent or class color tint a neutral bar instead."],
            values = {
                { value = "texture", text = L["Bar textures (yellow/green)"] },
                { value = "accent",  text = L["Accent color"] },
                { value = "class",   text = L["Class color"] },
            },
            get = function() return mod.db.fillMode or "texture" end,
            set = function(_, v)
                mod.db.fillMode = v
                if cFrame and cFrame:IsShown() then
                    if castInfo then c_applyFill(castInfo.isChannel)
                    elseif mod.db.unlocked then c_showTestContent() end
                end
            end,
        })
        table.insert(items, { type = "section", title = L["Size & offsets"], items = {
            { type = "slider", label = L["Width"],
              min = 120, max = 400, step = 5,
              get = function() return mod.db.width end,
              set = function(_, v) mod.db.width = v; c_applyLayout() end },
            { type = "slider", label = L["Height"],
              min = 12, max = 36, step = 1,
              get = function() return mod.db.height end,
              set = function(_, v) mod.db.height = v; c_applyLayout() end },
            { type = "slider", label = L["Icon Size"],
              min = 16, max = 48, step = 1,
              get = function() return mod.db.iconSize end,
              set = function(_, v) mod.db.iconSize = v; c_applyLayout() end },
            { type = "slider", label = L["Icon X Offset"],
              min = -100, max = 100, step = 1,
              tooltip = L["Moves the icon horizontally. Negative = left, positive = right."],
              get = function() return mod.db.iconX or 0 end,
              set = function(_, v) mod.db.iconX = v; c_applyLayout() end },
            { type = "slider", label = L["Icon Y Offset"],
              min = -50, max = 50, step = 1,
              tooltip = L["Moves the icon vertically. Positive = up, negative = down."],
              get = function() return mod.db.iconY or 0 end,
              set = function(_, v) mod.db.iconY = v; c_applyLayout() end },
            { type = "slider", label = L["Icon gap"],
              min = 0, max = 20, step = 1,
              tooltip = L["Distance between the icon and the bar."],
              get = function() return mod.db.iconGap or 3 end,
              set = function(_, v) mod.db.iconGap = v; c_applyLayout() end },
        } })

        table.insert(items, { type = "section", title = L["Colours"], items = {
            { type = "color", label = L["Accent colour"],
              tooltip = L["Used for the bar while the fill mode is not a texture, and for channelled casts on Blizzard's own castbar."],
              get = function() return mod.db.accentColor end,
              set = function(r, g, b)
                  local a = (mod.db.accentColor and mod.db.accentColor.a) or 0.90
                  mod.db.accentColor = { r = r, g = g, b = b, a = a }
                  c_applyFill(false)
              end },
            { type = "color", label = L["Cast finished"],
              tooltip = L["The bar flashes in this colour when a cast completes."],
              get = function() return mod.db.successColor end,
              set = function(r, g, b) mod.db.successColor = { r = r, g = g, b = b, a = 1 } end },
            { type = "color", label = L["Cast interrupted"],
              tooltip = L["The bar flashes in this colour when a cast is interrupted or fails."],
              get = function() return mod.db.failColor end,
              set = function(r, g, b) mod.db.failColor = { r = r, g = g, b = b, a = 1 } end },
        } })
    end

    -- The MODERN page: the same engine keys as the VUI mode, arranged the way
    -- the reference groups them -- Layout, Display (fill colours as a swatch
    -- run), Behaviour (ticks, the latency clip window, pushback). New visual
    -- features (border style, bar texture, latency text) join here once the
    -- engine grows them.
    if mod.db.mode == "modern" then
        table.insert(items, { type = "spacer", height = 8 })
        table.insert(items, { type = "section", title = L["Layout"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "button", label = L["Unlock / Test"], width = 130,
                  onClick = function() c_setUnlocked(not mod.db.unlocked) end },
                { type = "button", label = L["Center Position"], width = 170,
                  onClick = function() mod.db.x = 0; mod.db.y = -180; c_applyLayout() end },
            } },
            { type = "slider", label = L["Width"], min = 120, max = 400, step = 5,
              get = function() return mod.db.width end,
              set = function(_, v) mod.db.width = v; c_applyLayout() end },
            { type = "slider", label = L["Height"], min = 12, max = 36, step = 1,
              get = function() return mod.db.height end,
              set = function(_, v) mod.db.height = v; c_applyLayout() end },
            { type = "toggle", label = L["Show icon"],
              get = function() return mod.db.showIcon end,
              set = function(_, v)
                  mod.db.showIcon = v
                  if cFrame then cFrame.setIconShown(v) end
              end,
              subOptions = {
                  { type = "slider", label = L["Icon Size"], min = 16, max = 48, step = 1,
                    get = function() return mod.db.iconSize end,
                    set = function(_, v) mod.db.iconSize = v; c_applyLayout() end },
                  { type = "slider", label = L["Icon gap"], min = 0, max = 20, step = 1,
                    tooltip = L["Distance between the icon and the bar."],
                    get = function() return mod.db.iconGap or 3 end,
                    set = function(_, v) mod.db.iconGap = v; c_applyLayout() end },
                  { type = "slider", label = L["Icon X Offset"], min = -100, max = 100, step = 1,
                    get = function() return mod.db.iconX or 0 end,
                    set = function(_, v) mod.db.iconX = v; c_applyLayout() end },
                  { type = "slider", label = L["Icon Y Offset"], min = -50, max = 50, step = 1,
                    get = function() return mod.db.iconY or 0 end,
                    set = function(_, v) mod.db.iconY = v; c_applyLayout() end },
              } },
        } })
        table.insert(items, { type = "section", title = L["Display"], items = {
            { type = "dropdown", label = L["Fill color"], width = 280,
              tooltip = L["Bar textures = the classic yellow/green art. Accent or class color tint a neutral bar instead."],
              values = {
                  { value = "texture", text = L["Bar textures (yellow/green)"] },
                  { value = "accent",  text = L["Accent color"] },
                  { value = "class",   text = L["Class color"] },
              },
              get = function() return mod.db.fillMode or "texture" end,
              set = function(_, v)
                  mod.db.fillMode = v
                  if cFrame and cFrame:IsShown() then
                      if castInfo then c_applyFill(castInfo.isChannel)
                      elseif mod.db.unlocked then c_showTestContent() end
                  end
              end },
            { type = "color", label = L["Accent colour"],
              tooltip = L["Used for the bar while the fill mode is not a texture, and for channelled casts on Blizzard's own castbar."],
              get = function() return mod.db.accentColor end,
              set = function(r, g, b)
                  local a = (mod.db.accentColor and mod.db.accentColor.a) or 0.90
                  mod.db.accentColor = { r = r, g = g, b = b, a = a }
                  c_applyFill(false)
              end },
            { type = "color", label = L["Cast finished"],
              tooltip = L["The bar flashes in this colour when a cast completes."],
              get = function() return mod.db.successColor end,
              set = function(r, g, b) mod.db.successColor = { r = r, g = g, b = b, a = 1 } end },
            { type = "color", label = L["Cast interrupted"],
              tooltip = L["The bar flashes in this colour when a cast is interrupted or fails."],
              get = function() return mod.db.failColor end,
              set = function(r, g, b) mod.db.failColor = { r = r, g = g, b = b, a = 1 } end },
            { type = "dropdown", label = L["Bar texture"], width = 280,
              values = (function()
                  local vals = { { value = "", text = L["Bar textures (yellow/green)"] } }
                  for _, v in ipairs(ns.MediaStatusbarValues and ns.MediaStatusbarValues() or {}) do
                      vals[#vals + 1] = v
                  end
                  return vals
              end)(),
              get = function() return mod.db.barTexture or "" end,
              set = function(_, v)
                  mod.db.barTexture = v
                  if cFrame and cFrame:IsShown() then
                      if castInfo then c_applyFill(castInfo.isChannel)
                      elseif mod.db.unlocked then c_showTestContent() end
                  end
              end },
            { type = "slider", label = L["Border thickness (px)"], min = 0, max = 4, step = 1,
              get = function() return mod.db.borderSize or 0 end,
              set = function(_, v) mod.db.borderSize = v; c_applyBorder() end },
            { type = "color", label = L["Border colour"],
              get = function() return mod.db.borderColor end,
              set = function(r, g, b) mod.db.borderColor = { r = r, g = g, b = b }; c_applyBorder() end },
            { type = "toggle", label = L["Show spell name"],
              get = function() return mod.db.showSpellName end,
              set = function(_, v) mod.db.showSpellName = v end },
            { type = "toggle", label = L["Show cast timer"],
              get = function() return mod.db.showTimeText end,
              set = function(_, v) mod.db.showTimeText = v end,
              subOptions = {
                  { type = "dropdown", label = L["Timer format"], width = 280,
                    values = {
                        { value = "both",      text = L["Remaining / total (1.5 / 2.0)"] },
                        { value = "remaining", text = L["Remaining only (1.5)"] },
                        { value = "seconds",   text = L["Whole seconds (2)"] },
                    },
                    get = function() return mod.db.timeTextMode or "both" end,
                    set = function(_, v) mod.db.timeTextMode = v end },
              } },
        } })
        table.insert(items, { type = "section", title = L["Behaviour"], items = {
            { type = "toggle", label = L["Show channel ticks"],
              tooltip = L["Shows vertical lines at tick points (Mind Flay, Drain Soul, Hellfire, etc.)"],
              get = function() return mod.db.showTicks end,
              set = function(_, v) mod.db.showTicks = v end,
              subOptions = {
                  { type = "checkbox", label = L["Colour the last tick"],
                    get = function() return mod.db.lastTickOn end,
                    set = function(_, v) mod.db.lastTickOn = v end },
                  { type = "color", label = L["Mark colour"],
                    get = function() return mod.db.lastTickColor end,
                    set = function(r, g, b) mod.db.lastTickColor = { r = r, g = g, b = b } end },
              } },
            { type = "toggle", label = L["Show clip window"],
              tooltip = L["Shades your latency at the end of the bar: on channels the moment to recast without losing the last tick, on casts the spell-queue window where the next cast can already be pressed."],
              get = function() return mod.db.showClipMarker end,
              set = function(_, v) mod.db.showClipMarker = v end,
              subOptions = {
                  { type = "checkbox", label = L["Show latency text"],
                    get = function() return mod.db.latencyText end,
                    set = function(_, v) mod.db.latencyText = v end },
              } },
            { type = "toggle", label = L["Show pushback"],
              tooltip = L["Briefly shows the time lost to spell pushback in red above the bar."],
              get = function() return mod.db.showPushback ~= false end,
              set = function(_, v) mod.db.showPushback = v end },
            { type = "toggle", label = L["Merge crafting casts"],
              tooltip = L["When crafting several items in a row the bar shows a counter like 3/20 instead of single casts."],
              get = function() return mod.db.mergeCrafts ~= false end,
              set = function(_, v) mod.db.mergeCrafts = v end },
        } })
    end

    -- Swing timer is a hidden module; embedding its options here avoids a second sidebar entry.
    local sw = ns.modules and ns.modules.swingtimer
    if sw and sw.GetOptions and sw.db then
        table.insert(items, { type = "spacer", height = 10 })
        table.insert(items, {
            type = "section", title = L["Swing Timer"],
            items = sw:GetOptions(),
        })
    end

    return items
end

ns:RegisterSlash({ key = "CASTBARTEST", commands = { "/scttest" },
    desc = "Run a test cast to check the cast bar.",
    module = "playercastbar",
})
ns.Slash.CASTBARTEST = function()
    if (mod.db.mode == "custom" or mod.db.mode == "modern") then
        c_setUnlocked(not mod.db.unlocked)
    else
        ns:Print(L["Test only available in 'Custom Castbar' mode."])
    end
end
end)(...);

(function(...)
-- VuloClassicUI / Modules / CooldownPulse
-- Ported for TBC 2.5.5 (no C_Spell / C_Container / Settings APIs).
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("cooldownpulse", {
    name        = "Cooldown Pulse",
    group       = "Unit Frames",
    description = "Shows the icon of an expired cooldown as a brief pulsing animation in the screen center (based on Doom_CooldownPulse).",
    defaults = {
        enabled       = false,
        iconSize      = 75,
        fadeInTime    = 0.3,
        fadeOutTime   = 0.7,
        maxAlpha      = 0.7,
        holdTime      = 0,
        animScale     = 1.5,
        remainingTime = 0,      -- Cooldown must be UNDER this value to trigger
        showSpellName = false,
        x             = nil,
        y             = nil,
        ignoredSpells = "",
        invertIgnored = false,  -- false = blacklist, true = whitelist
    },
})

-- GetItemCooldown lives in different places per client: global (Classic Era),
-- C_Item (Retail 10.2+), C_Container (Retail 10.0+); else scan bags with GetContainerItemCooldown.
local function getItemCooldown(itemID)
    if not itemID then return 0, 0, 0 end

    if _G.GetItemCooldown then
        return GetItemCooldown(itemID)
    end
    if _G.C_Item and _G.C_Item.GetItemCooldown then
        local s, d, e = C_Item.GetItemCooldown(itemID)
        return s, d, (e == true and 1) or (e == false and 0) or e
    end
    if _G.C_Container and _G.C_Container.GetItemCooldown then
        return C_Container.GetItemCooldown(itemID)
    end

    local getContainerItemInfo = _G.GetContainerItemInfo
    local getContainerItemCooldown = _G.GetContainerItemCooldown
    if _G.C_Container then
        getContainerItemInfo = getContainerItemInfo or C_Container.GetContainerItemInfo
        getContainerItemCooldown = getContainerItemCooldown or C_Container.GetContainerItemCooldown
    end
    if not getContainerItemCooldown then return 0, 0, 0 end

    for bag = 0, 4 do
        local slots = (_G.GetContainerNumSlots and GetContainerNumSlots(bag))
                   or (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag))
                   or 0
        for slot = 1, slots do
            if _G.GetContainerItemID then
                if GetContainerItemID(bag, slot) == itemID then
                    return getContainerItemCooldown(bag, slot)
                end
            elseif C_Container and C_Container.GetContainerItemID then
                if C_Container.GetContainerItemID(bag, slot) == itemID then
                    return getContainerItemCooldown(bag, slot)
                end
            end
        end
    end
    return 0, 0, 0
end

local function getContainerItemID(bag, slot)
    if _G.GetContainerItemID then return GetContainerItemID(bag, slot) end
    if _G.C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bag, slot)
    end
    return nil
end

local cooldowns = {}
local animating = {}   -- queue of {texture, isPet, name}
local watching  = {}   -- [id] = {startTime, type, ref}
local itemSpells = {}

local DCP
local DCPT
local TextFrame

local function tcount(tab)
    local n = 0
    for _ in pairs(tab) do n = n + 1 end
    return n
end

local function memoize(fn)
    local cached, hasValue = nil, false
    local m = {}
    local function get()
        if not hasValue then
            cached = fn()
            hasValue = true
        end
        return cached
    end
    m.resetCache = function() cached = nil; hasValue = false end
    setmetatable(m, { __call = get })
    return m
end

local function getPetActionIndexByName(name)
    if not name or not NUM_PET_ACTION_SLOTS then return nil end
    for i = 1, NUM_PET_ACTION_SLOTS do
        if GetPetActionInfo(i) == name then return i end
    end
    return nil
end

-- Cached by the raw editbox string so the 0.05s OnUpdate only re-parses when it changes.
local _ignoredCache, _ignoredRaw
local function parseIgnoredSpells()
    local raw = mod.db.ignoredSpells or ""
    if _ignoredCache and _ignoredRaw == raw then return _ignoredCache end
    local set = {}
    for _, v in ipairs({ strsplit(",", raw) }) do
        local trimmed = strtrim(v)
        if trimmed ~= "" then set[trimmed] = true end
    end
    _ignoredCache, _ignoredRaw = set, raw
    return set
end

local function isAnimatingByName(name)
    for _, details in pairs(animating) do
        if details[3] == name then return true end
    end
    return false
end

local function trackItemSpell(itemID)
    if not itemID then return false end
    local _, spellID = GetItemSpell(itemID)
    if spellID then
        itemSpells[spellID] = itemID
        return true
    end
    return false
end

local elapsed = 0
local runtimer = 0
local function OnUpdate(_, update)
    elapsed = elapsed + update
    if elapsed > 0.05 then
        local ignored = parseIgnoredSpells()

        for id, v in pairs(watching) do
            if GetTime() >= v[1] + 0.5 then
                -- Built once per entry, reset here per tick: rebuilding the
                -- memoize every tick allocated five objects per watched id at
                -- 20 Hz, continuously while buttons were being pressed. The
                -- details table is reused too - no consumer keeps it.
                local getDetails = v.getDetails
                if getDetails then
                    getDetails.resetCache()
                else
                    local function fill()
                        local t = v.details
                        if not t then t = {}; v.details = t end
                        return t
                    end
                    if v[2] == "spell" then
                        getDetails = memoize(function()
                            local t = fill()
                            local name, _, texture = GetSpellInfo(v[3])
                            local start, duration, enabled = GetSpellCooldown(v[3])
                            t.name, t.texture, t.isPet = name, texture, nil
                            t.start, t.duration, t.enabled = start, duration, enabled
                            return t
                        end)
                    elseif v[2] == "item" then
                        getDetails = memoize(function()
                            local t = fill()
                            local start, duration, enabled = getItemCooldown(id)
                            t.name, t.texture, t.isPet = GetItemInfo(id), v[3], nil
                            t.start, t.duration, t.enabled = start, duration, enabled
                            return t
                        end)
                    elseif v[2] == "pet" then
                        getDetails = memoize(function()
                            local t = fill()
                            local name, texture = GetPetActionInfo(v[3])
                            local start, duration, enabled = GetPetActionCooldown(v[3])
                            t.name, t.texture, t.isPet = name, texture, true
                            t.start, t.duration, t.enabled = start, duration, enabled
                            return t
                        end)
                    end
                    v.getDetails = getDetails
                end

                if getDetails then
                    local cd = getDetails()
                    local isFiltered = (ignored[cd.name or ""] ~= nil or ignored[tostring(id)] ~= nil)
                    if isFiltered ~= mod.db.invertIgnored then
                        watching[id] = nil
                    else
                        if cd.enabled and cd.enabled ~= 0 then
                            if cd.duration and cd.duration > 2.0 and cd.texture then
                                cooldowns[id] = getDetails
                            end
                        end
                        if not (cd.enabled == 0 and v[2] == "spell") then
                            watching[id] = nil
                        end
                    end
                end
            end
        end

        for i, getDetails in pairs(cooldowns) do
            local cd = getDetails()
            if cd.start then
                local remaining = cd.duration - (GetTime() - cd.start)
                if remaining <= (mod.db.remainingTime or 0) then
                    if not isAnimatingByName(cd.name) then
                        tinsert(animating, { cd.texture, cd.isPet, cd.name })
                    end
                    cooldowns[i] = nil
                end
            else
                cooldowns[i] = nil
            end
        end

        elapsed = 0
        if #animating == 0 and tcount(watching) == 0 and tcount(cooldowns) == 0 then
            DCP:SetScript("OnUpdate", nil)
            return
        end
    end

    if #animating > 0 then
        runtimer = runtimer + update
        local fadeInTime  = mod.db.fadeInTime  or 0.3
        local fadeOutTime = mod.db.fadeOutTime or 0.7
        local holdTime    = mod.db.holdTime    or 0
        local maxAlpha    = mod.db.maxAlpha    or 0.7
        local iconSize    = mod.db.iconSize    or 75
        local animScale   = mod.db.animScale   or 1.5

        if runtimer > (fadeInTime + holdTime + fadeOutTime) then
            tremove(animating, 1)
            runtimer = 0
            TextFrame:SetText(nil)
            DCPT:SetTexture(nil)
            DCPT:SetVertexColor(1, 1, 1)
        else
            if not DCPT:GetTexture() then
                if animating[1][3] and mod.db.showSpellName then
                    TextFrame:SetText(animating[1][3])
                end
                DCPT:SetTexture(animating[1][1])
            end
            local alpha = maxAlpha
            if runtimer < fadeInTime then
                alpha = maxAlpha * (runtimer / fadeInTime)
            elseif runtimer >= fadeInTime + holdTime then
                alpha = maxAlpha - (maxAlpha * ((runtimer - holdTime - fadeInTime) / fadeOutTime))
            end
            DCP:SetAlpha(alpha)
            local scale = iconSize + (iconSize * ((animScale - 1) * (runtimer / (fadeInTime + holdTime + fadeOutTime))))
            DCP:SetWidth(scale)
            DCP:SetHeight(scale)
        end
    end
end

local function ensureFrame()
    if DCP then return DCP end

    DCP = CreateFrame("Frame", "VCUI_CooldownPulse", UIParent)

    TextFrame = DCP:CreateFontString(nil, "ARTWORK")
    TextFrame:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    TextFrame:SetShadowOffset(2, -2)
    TextFrame:SetPoint("CENTER", DCP, "CENTER")
    TextFrame:SetWidth(185)
    TextFrame:SetJustifyH("CENTER")
    TextFrame:SetTextColor(1, 1, 1)

    DCPT = DCP:CreateTexture(nil, "BACKGROUND")
    DCPT:SetAllPoints(DCP)

    DCP:SetWidth(mod.db.iconSize or 75)
    DCP:SetHeight(mod.db.iconSize or 75)

    -- One-time migration of the legacy BOTTOMLEFT-pixel position to a CENTER offset.
    if mod.db.x and not mod.db._cmoffset then
        DCP:ClearAllPoints()
        DCP:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mod.db.x, mod.db.y)
        local fx, fy = DCP:GetCenter()
        local px, py = UIParent:GetCenter()
        if fx and px then mod.db.x, mod.db.y = fx - px, fy - py end
    end
    mod.db._cmoffset = true
    DCP:ClearAllPoints()
    DCP:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
    DCP:SetAlpha(0)
    DCP:EnableMouse(false)

    -- Frame is invisible (alpha 0), so editPreview shows a sample icon and enables mouse, which also drives the DCP:IsMouseEnabled() "being moved" guards.
    DCP.mover = ns:CreateMover(DCP, {
        key    = "cooldownpulse",
        label  = "|cffffffffCOOLDOWN PULSE|r",
        db     = mod.db,
        width  = mod.db.iconSize or 75,
        height = mod.db.iconSize or 75,
        anchorable = true,
        editPreview = function(show)
            if show then
                DCP:SetScript("OnUpdate", nil)
                DCP:SetAlpha(1)
                DCPT:SetTexture("Interface\\Icons\\Spell_Nature_Earthbind")
                DCP:EnableMouse(true)
                DCP:SetWidth(mod.db.iconSize); DCP:SetHeight(mod.db.iconSize)
            else
                DCP:SetAlpha(0)
                DCPT:SetTexture(nil)
                DCP:EnableMouse(false)
            end
        end,
    })

    return DCP
end

local function triggerSpell(spellID)
    watching[spellID] = { GetTime(), "spell", spellID }
    if DCP and not DCP:IsMouseEnabled() then
        DCP:SetScript("OnUpdate", OnUpdate)
    end
end

local function triggerItem(itemID)
    if not itemID then return end
    -- GetItemInfo index 10 = icon
    local texture = select(10, GetItemInfo(itemID))
    watching[itemID] = { GetTime(), "item", texture }
    itemSpells[itemID] = nil
    if DCP and not DCP:IsMouseEnabled() then
        DCP:SetScript("OnUpdate", OnUpdate)
    end
end

local eventFrame
local function setupEvents()
    if eventFrame then return end

    eventFrame = CreateFrame("Frame")

    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if not mod._enabled then return end

        if event == "SPELL_UPDATE_COOLDOWN" then
            for _, getDetails in pairs(cooldowns) do
                getDetails.resetCache()
            end

        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, _, spellID = ...
            if unit ~= "player" then return end
            local itemID = itemSpells[spellID]
            if itemID then
                triggerItem(itemID)
            else
                triggerSpell(spellID)
            end

        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            -- Hot path: bail on the cheap subevent read before UnitExists and the full destructure.
            if select(2, CombatLogGetCurrentEventInfo()) ~= "SPELL_CAST_SUCCESS" then return end
            if not UnitExists("pet") then return end
            local _, _, _, _, _, sourceFlags, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
            if sourceFlags and spellID then
                local isPet = (bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PET or 0) ~= 0)
                local mine  = (bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE or 0) ~= 0)
                if isPet and mine then
                    local name = GetSpellInfo(spellID)
                    local index = getPetActionIndexByName(name)
                    if index and not select(6, GetPetActionInfo(index)) then
                        watching[spellID] = { GetTime(), "pet", index }
                        if DCP and not DCP:IsMouseEnabled() then
                            DCP:SetScript("OnUpdate", OnUpdate)
                        end
                    elseif not index and spellID then
                        triggerSpell(spellID)
                    end
                end
            end

        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Clear the queue in arena.
            local inInstance, instanceType = IsInInstance()
            if inInstance and instanceType == "arena" then
                if DCP then DCP:SetScript("OnUpdate", nil) end
                wipe(cooldowns)
                wipe(watching)
            end
        end
    end)

    if UseAction then
        hooksecurefunc("UseAction", function(slot)
            if not mod._enabled then return end
            local actionType, itemID = GetActionInfo(slot)
            if actionType == "item" and itemID and not trackItemSpell(itemID) then
                local texture = GetActionTexture(slot)
                watching[itemID] = { GetTime(), "item", texture }
                if DCP and not DCP:IsMouseEnabled() then
                    DCP:SetScript("OnUpdate", OnUpdate)
                end
            end
        end)
    end

    if UseInventoryItem then
        hooksecurefunc("UseInventoryItem", function(slot)
            if not mod._enabled then return end
            local itemID = GetInventoryItemID("player", slot)
            if itemID and not trackItemSpell(itemID) then
                local texture = GetInventoryItemTexture("player", slot)
                watching[itemID] = { GetTime(), "item", texture }
                if DCP and not DCP:IsMouseEnabled() then
                    DCP:SetScript("OnUpdate", OnUpdate)
                end
            end
        end)
    end

    -- UseContainerItem is global in 2.5.5, in C_Container as of Retail 10.0+.
    if _G.UseContainerItem then
        hooksecurefunc("UseContainerItem", function(bag, slot)
            if not mod._enabled then return end
            local itemID = getContainerItemID(bag, slot)
            if itemID and not trackItemSpell(itemID) then
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
                watching[itemID] = { GetTime(), "item", texture }
                if DCP and not DCP:IsMouseEnabled() then
                    DCP:SetScript("OnUpdate", OnUpdate)
                end
            end
        end)
    elseif _G.C_Container and C_Container.UseContainerItem then
        hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
            if not mod._enabled then return end
            local itemID = getContainerItemID(bag, slot)
            if itemID and not trackItemSpell(itemID) then
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
                watching[itemID] = { GetTime(), "item", texture }
                if DCP and not DCP:IsMouseEnabled() then
                    DCP:SetScript("OnUpdate", OnUpdate)
                end
            end
        end)
    end
end

local function testAnimation()
    ensureFrame()
    tinsert(animating, { "Interface\\Icons\\Spell_Nature_Earthbind", nil, L["Test Spell"] })
    DCP:SetScript("OnUpdate", OnUpdate)
end

function mod:OnEnable()
    ensureFrame()
    setupEvents()
end

function mod:OnDisable()
    if DCP then
        DCP:SetScript("OnUpdate", nil)
        DCP:SetAlpha(0)
        DCP:EnableMouse(false)
    end
    wipe(animating)
    wipe(cooldowns)
    wipe(watching)
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Position"] },
        {
            type = "group", layout = "row", gap = 8,
            items = {
                {
                    type = "button", label = L["Open Edit Mode"],
                    tooltip = L["Move it in the unified Edit Mode (/vedit)."],
                    width = 140,
                    onClick = function()
                        if ns.SetEditMode then ns:SetEditMode(not ns:IsEditModeActive()) end
                    end,
                },
                {
                    type = "button", label = L["Test Pulse"], width = 110,
                    tooltip = L["Plays a test animation."],
                    onClick = testAnimation,
                },
                {
                    type = "button", label = L["Reset Position"], width = 170,
                    onClick = function()
                        mod.db.x, mod.db.y = 0, 0
                        if DCP then
                            DCP:ClearAllPoints()
                            DCP:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                        end
                        ns:Print(L["Cooldown Pulse position reset."])
                    end,
                },
            },
        },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Appearance"] },

        {
            type = "slider", label = L["Icon Size"],
            min = 30, max = 125, step = 5,
            get = function() return mod.db.iconSize end,
            set = function(_, v)
                mod.db.iconSize = v
                if DCP and DCP:IsMouseEnabled() then
                    DCP:SetWidth(v); DCP:SetHeight(v)
                end
            end,
        },
        {
            type = "slider", label = L["Max Opacity"],
            min = 0.1, max = 1.0, step = 0.05,
            get = function() return mod.db.maxAlpha end,
            set = function(_, v) mod.db.maxAlpha = v end,
        },
        {
            type = "slider", label = L["Animation Scale"],
            min = 1.0, max = 2.5, step = 0.1,
            get = function() return mod.db.animScale end,
            set = function(_, v) mod.db.animScale = v end,
        },
        {
            type = "slider", label = L["Fade-In Time (s)"],
            min = 0, max = 1.5, step = 0.1,
            get = function() return mod.db.fadeInTime end,
            set = function(_, v) mod.db.fadeInTime = v end,
        },
        {
            type = "slider", label = L["Hold Time (s)"],
            min = 0, max = 1.5, step = 0.1,
            get = function() return mod.db.holdTime end,
            set = function(_, v) mod.db.holdTime = v end,
        },
        {
            type = "slider", label = L["Fade-Out Time (s)"],
            min = 0, max = 1.5, step = 0.1,
            get = function() return mod.db.fadeOutTime end,
            set = function(_, v) mod.db.fadeOutTime = v end,
        },
        {
            type = "slider", label = L["Show Before Available (s)"],
            tooltip = L["Triggers the animation X seconds BEFORE the cooldown expires. 0 = exactly at cooldown end."],
            min = 0, max = 3, step = 0.1,
            get = function() return mod.db.remainingTime end,
            set = function(_, v) mod.db.remainingTime = v end,
        },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Spell Filter"] },

        {
            type = "toggle", label = L["Show spell names"],
            tooltip = L["Shows the name of the spell under the icon."],
            get = function() return mod.db.showSpellName end,
            set = function(_, v) mod.db.showSpellName = v end,
        },
        {
            type = "toggle", label = L["Invert filter (whitelist instead of blacklist)"],
            tooltip = L["Off: List = ignored spells. On: List = show ONLY these spells."],
            get = function() return mod.db.invertIgnored end,
            set = function(_, v) mod.db.invertIgnored = v end,
        },
        {
            type = "editbox", label = L["Spell List (comma-separated)"],
            width = 400,
            tooltip = L["Spell names exactly as in-game, comma-separated. Spell IDs also work."],
            get = function() return mod.db.ignoredSpells end,
            set = function(_, v) mod.db.ignoredSpells = v end,
        },
    }
end

ns:RegisterSlash({ key = "COOLDOWNPULSE", commands = { "/dcp", "/cooldownpulse" },
    desc = "Open the cooldown pulse settings.",
    module = "cooldownpulse",
})
ns.Slash.COOLDOWNPULSE = function() ns.Slash.OPTIONS("cooldownpulse") end

-- ---------------------------------------------------------------------------
-- Container: one sidebar row holding the player/target frames, the font bars,
-- the player castbar and this cooldown pulse as tabs (30.07.2026, user
-- request). Nameplates keep a row of their own, so they are excluded by key.
--
-- The call sits in the LAST capsule of this file because the factory scans
-- ns.moduleOrder at call time -- every member registers in the capsules above,
-- so the merge made the ordering self-contained. A member moved OUT of this
-- file must load before it in the TOC, or its tab silently vanishes.
local ufc = ns:MakeGroupContainer({
    key      = "unitframesgroup",
    name     = "Unit Frames",
    group    = "Unit Frames",
    firstKey = "unitframes",
    exclude  = { nameplates = true },
})

-- The player-castbar tab pins its live preview above the scroll area; the
-- castbar capsule owns the widget, this is just the hand-over.
function ufc.BuildPageHeader(host, tabId)
    if tabId == "playercastbar" then
        local m = ns.modules and ns.modules.playercastbar
        if m and m.BuildPreview then return m.BuildPreview(host) end
    end
    return 0
end
end)(...);
