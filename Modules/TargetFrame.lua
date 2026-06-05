-- =========================================================
-- VuloClassicUI / Modules / TargetFrame
-- Re-adds the "modern" TargetFrame/FocusFrame extras that the default TBC
-- Anniversary UI is missing, natively (no external addon needed):
--   * Numeric threat % readout above the frame
--   * Coloured threat glow around the frame
--   * The winged Rare-Elite border for rare-elite mobs
-- All purely cosmetic: hooksecurefunc + our own textures / fontstrings, so no
-- taint and no secure actions are touched. Threat runs off Blizzard's native
-- ThreatAPI (present on 2.5.5) — no LibThreatClassic.
-- (Real-NPC-health text is handled separately once we confirm what the default
--  frame shows for a normal mob.)
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("targetframe", {
    name        = "Target Frame",
    group       = "Unit Frames",
    description = "Adds a numeric threat %, a coloured threat glow and the winged Rare-Elite border to the Target and Focus frames - the bits the default Anniversary UI leaves out.",
    defaults = {
        enabled       = true,
        realHealth    = true,   -- show the real HP value for NPCs (default shows %)
        threatNumeric = true,   -- numeric threat % above the frame
        threatGlow    = true,   -- tint the frame border by threat status
        rareElite     = true,   -- winged Rare-Elite border for rare-elite mobs
        focus         = true,   -- apply all of the above to the Focus frame too
    },
})

-- The frame's border ("classification") texture. On the 2.5.5 Classic frame this
-- is <Frame>TextureFrameTexture; older paths used frame.borderTexture.
local function borderTexOf(frame)
    if frame.borderTexture then return frame.borderTexture end
    local name = frame.GetName and frame:GetName()
    return name and _G[name .. "TextureFrameTexture"]
end

-- Short HP like 120, 3.4k, 1.2m
local function abbrev(v)
    if v >= 1e6 then return string.format("%.1fm", v / 1e6)
    elseif v >= 1e4 then return string.format("%.1fk", v / 1e3)
    else return tostring(v) end
end

-- Threat status colours (fallback if GetThreatStatusColor is ever missing).
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

-- ---------------------------------------------------------
-- Threat indicator (numeric box above the frame + glow on the frame)
-- ---------------------------------------------------------
local indicators = {}  -- [frame] = indicator

-- Border pulse while at full aggro (status 3): oscillate the border colour
-- red <-> light red on a single shared OnUpdate.
local pulsing = {}     -- [frame] = border texture
local pulseDriver = CreateFrame("Frame")
pulseDriver:Hide()
pulseDriver:SetScript("OnUpdate", function()
    local g = 0.30 - 0.30 * math.cos(GetTime() * 6)  -- 0 .. 0.6, ~1s period
    for _, border in pairs(pulsing) do border:SetVertexColor(1, g, g) end
end)

local function createIndicator(frame)
    if indicators[frame] then return indicators[frame] end

    -- Numeric box. Anchors tuned to the 2.5.5 Anniversary frame geometry.
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
    local allowed = mod._enabled and (not isFocus or mod.db.focus)
    local numeric = allowed and mod.db.threatNumeric
    local glowOn  = allowed and mod.db.threatGlow

    if (numeric or glowOn) and unit and UnitExists(unit) and UnitDetailedThreatSituation then
        local tanking, status, _, percent = UnitDetailedThreatSituation("player", unit)
        local r, g, b = threatColor(status or 0)

        -- Numeric %
        if numeric then
            if tanking and UnitThreatPercentageOfLead then
                percent = UnitThreatPercentageOfLead("player", unit)
            end
            if percent and percent > 0 then
                if percent > 999 then percent = 999 end  -- clamp the known API spike
                ind.text:SetFormattedText("%.0f%%", percent)
                ind.bg:SetVertexColor(r, g, b)
                ind:Show()
            else
                ind:Hide()
            end
        else
            ind:Hide()
        end

        -- Glow = tint the frame's metal border by threat colour; pulse at full aggro
        local border = borderTexOf(frame)
        if border then
            if glowOn and status and status >= 3 then
                pulsing[frame] = border            -- pulse red (driver animates it)
            elseif glowOn and status and status > 0 then
                pulsing[frame] = nil
                border:SetVertexColor(r, g, b)     -- static yellow / orange
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

local function updateAll()
    for frame in pairs(indicators) do updateIndicator(frame) end
end

-- ---------------------------------------------------------
-- Rare-Elite border (winged dragon) for rare-elite mobs
-- ---------------------------------------------------------
local RARE_ELITE_TEX = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite"

local function applyClassification(frame, lock)
    if not (mod._enabled and mod.db.rareElite) then return end
    if frame ~= _G.TargetFrame and frame ~= _G.FocusFrame then return end
    if frame == _G.FocusFrame and not mod.db.focus then return end
    local unit = unitForFrame(frame)
    if not lock and unit and UnitExists(unit) and UnitClassification(unit) == "rareelite" then
        local border = borderTexOf(frame)
        if border and border.SetTexture then border:SetTexture(RARE_ELITE_TEX) end
    end
end

local function refreshClassification()
    -- Re-run the default check so our hook re-applies (or the default reverts).
    if _G.TargetFrame and _G.TargetFrame:IsShown() then
        if _G.TargetFrame_CheckClassification then
            pcall(_G.TargetFrame_CheckClassification, _G.TargetFrame)
        elseif _G.TargetFrame.CheckClassification then
            pcall(_G.TargetFrame.CheckClassification, _G.TargetFrame)
        end
    end
end

-- ---------------------------------------------------------
-- Real NPC health text (the default obfuscates NPCs to a %, but UnitHealth
-- already returns the true value on 2.5.5 — we just rewrite the bar text).
-- ---------------------------------------------------------
local function healthUnitFor(bar)
    if bar == _G.TargetFrameHealthBar then return "target" end
    if bar == _G.FocusFrameHealthBar  then return "focus"  end
    return nil
end

local function applyRealHealth(bar)
    if not (mod._enabled and mod.db.realHealth) then return end
    local unit = healthUnitFor(bar)
    if not unit then return end
    if unit == "focus" and not mod.db.focus then return end
    if not UnitExists(unit) then return end
    -- Enemy players (and their summons) stay percentage-obfuscated — unchangeable.
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
        -- percent on the left, real value on the right (Show: the default hides them)
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

-- ---------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------
local hooked, realHealthHooked = false, false

local function ensureSetup()
    if not _G.TargetFrame then return end

    -- One indicator per frame.
    createIndicator(_G.TargetFrame)
    if _G.FocusFrame then createIndicator(_G.FocusFrame) end

    -- Drive threat updates off the native events, unit-filtered.
    for frame, ind in pairs(indicators) do
        if not ind._wired then
            ind._wired = true
            local unit = unitForFrame(frame)
            if frame == _G.TargetFrame then ind:RegisterEvent("PLAYER_TARGET_CHANGED") end
            if frame == _G.FocusFrame  then ind:RegisterEvent("PLAYER_FOCUS_CHANGED")  end
            if unit then
                if ind.RegisterUnitEvent then
                    pcall(ind.RegisterUnitEvent, ind, "UNIT_THREAT_LIST_UPDATE", unit)
                    pcall(ind.RegisterUnitEvent, ind, "UNIT_THREAT_SITUATION_UPDATE", unit)
                else
                    ind:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
                end
            end
            ind:SetScript("OnEvent", function(self) updateIndicator(self.frame) end)
        end
    end

    -- Rare-Elite: hook the default classification check (global fn or mixin).
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

    -- Real NPC health: rewrite the bar text with the true value. On the
    -- Anniversary client the text is set by the bar's TextStatusBarMixin method,
    -- so hook that on the bar directly; fall back to the global on older paths.
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

function mod:OnEnable()
    ensureSetup()
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        ensureSetup(); updateAll(); refreshClassification(); refreshHealth()
    end)
    updateAll()
    refreshClassification()
    refreshHealth()
end

function mod:OnDisable()
    pulseDriver:Hide()
    for frame, ind in pairs(indicators) do
        ind:Hide()
        pulsing[frame] = nil
        local b = borderTexOf(frame); if b then b:SetVertexColor(1, 1, 1) end
    end
    refreshHealth()  -- restore the default % text
    -- Hooks stay installed but are gated by mod._enabled; a /reload fully reverts.
end

-- ---------------------------------------------------------
-- Options
-- ---------------------------------------------------------
function mod:GetOptions()
    local function apply() updateAll(); refreshClassification(); refreshHealth() end
    return {
        { type = "header", text = L["Target Frame"] },
        { type = "desc",   text = L["|cffaaaaaaAdds the modern Target/Focus frame extras the default Anniversary UI is missing - all cosmetic, no taint.|r"] },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Health"] },
        { type = "toggle", label = L["Show real NPC health"],
          tooltip = L["Shows the true health value on NPCs instead of the obfuscated percentage (enemy players stay %)."],
          get = function() return mod.db.realHealth end,
          set = function(_, v) mod.db.realHealth = v; apply() end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Threat"] },
        { type = "toggle", label = L["Numeric threat %"],
          tooltip = L["Shows your threat percentage on the target (and focus) above the frame, coloured by threat status."],
          get = function() return mod.db.threatNumeric end,
          set = function(_, v) mod.db.threatNumeric = v; apply() end },
        { type = "toggle", label = L["Threat glow"],
          tooltip = L["Glows the target (and focus) frame in yellow/orange/red as your threat rises."],
          get = function() return mod.db.threatGlow end,
          set = function(_, v) mod.db.threatGlow = v; apply() end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Classification"] },
        { type = "toggle", label = L["Rare-Elite border"],
          tooltip = L["Shows the winged silver-dragon Rare-Elite border on rare-elite mobs."],
          get = function() return mod.db.rareElite end,
          set = function(_, v) mod.db.rareElite = v; apply() end },

        { type = "spacer", height = 6 },
        { type = "toggle", label = L["Also apply to the Focus frame"],
          get = function() return mod.db.focus end,
          set = function(_, v) mod.db.focus = v; apply() end },
    }
end
