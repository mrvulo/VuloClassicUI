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

local RAISE_FRAMES = {
    { name = "PlayerFrameGroupIndicator", lift = 1 },
    { name = "PetFrame",                  lift = 2 },
    { name = "TotemFrame",                lift = 3 },
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

local function applyPlayerStyle()
    if not capturePlayerDefaults() then return end
    local s = STYLES[mod.db.playerStyle]
    if not s then
        restorePlayerDefaults()
        return
    end

    local tex = _G.PlayerFrameTexture
    if not tex then return end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", _G.PlayerFrame, "TOPLEFT", BASE_X + s.ox, BASE_Y + s.oy)
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
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", onWorldEnter)
    refreshTargetFrames()

    -- The level text gets re-anchored by the default UI; hooksecurefunc is permanent, so install it once.
    if not anchorHooked and _G.PlayerFrame_UpdateLevelTextAnchor then
        anchorHooked = true
        hooksecurefunc("PlayerFrame_UpdateLevelTextAnchor", applyPlayerTextPositions)
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", onWorldEnter)
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
