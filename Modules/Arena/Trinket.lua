-- =========================================================
-- VuloClassicUI / Modules / Arena / Trinket
-- PvP trinket cooldown tracker per arena opponent.
-- Detects the cast via COMBAT_LOG_EVENT_UNFILTERED and shows icon + timer.
-- =========================================================
local _, ns = ...
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

-- =========================================================
-- TBC PvP trinket spells and their cooldowns
-- =========================================================
local TRINKET_SPELLS = {
    -- PvP trinket item spells (all same effect, all 2 min CD in TBC)
    [42292] = 120,  -- PvP Trinket (Gladiator/Arena/Honor)
    [7744]  = 120,  -- Will of the Forsaken (Undead)
    [59752] = 120,  -- Will to Survive / Every Man for Himself (Human, retail)
    [20594] = 120,  -- Stoneform (Dwarf) - actually Bleed/Disease/Poison removal, but shares CD-like
}

-- Icons for the trinkets (atlas doesn't work everywhere in TBC, so TexturePath)
local TRINKET_TEXTURE = "Interface\\Icons\\INV_Jewelry_TrinketPVP_02"

-- One trinket frame per slot
local trinketFrames = {}

-- =========================================================
-- Create trinket frame
-- =========================================================
local function createTrinketFrame(parent, slotIndex)
    local f = CreateFrame("Frame", "VCUIArenaTrinket" .. slotIndex, parent)
    f:SetSize(mod.db.trinketSize or 28, mod.db.trinketSize or 28)

    -- Icon
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexture(TRINKET_TEXTURE)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Border
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(0, 0, 0, 0.8)
    f.border:SetDrawLayer("BACKGROUND")

    -- Cooldown spiral
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(true)
    f.cd:SetHideCountdownNumbers(false)

    -- Tooltip
    f:EnableMouse(false)  -- not clickable, otherwise combat issues

    f:Hide()
    return f
end

local function ensureTrinketFrame(arenaFrame, i)
    if trinketFrames[i] then return trinketFrames[i] end
    local tf = createTrinketFrame(arenaFrame, i)
    trinketFrames[i] = tf
    return tf
end

-- =========================================================
-- Anchor + display
-- =========================================================
local function anchorTrinketFrame(tf, arenaFrame)
    if not tf or not arenaFrame then return end
    tf:ClearAllPoints()
    tf:SetSize(mod.db.trinketSize, mod.db.trinketSize)
    if mod.db.trinketAnchor == "LEFT" then
        tf:SetPoint("RIGHT", arenaFrame, "LEFT",  mod.db.trinketOffsetX,  mod.db.trinketOffsetY)
    else
        tf:SetPoint("LEFT",  arenaFrame, "RIGHT", -mod.db.trinketOffsetX, mod.db.trinketOffsetY)
    end
end

local function applyToFrame(arenaFrame, i)
    local tf = ensureTrinketFrame(arenaFrame, i)
    anchorTrinketFrame(tf, arenaFrame)
    if mod.db.trinketEnabled then
        tf:Show()
        if mod:IsUnlocked() then
            -- Test: show icon without cooldown
            tf.cd:Hide()
            tf.icon:SetDesaturated(false)
        end
    else
        tf:Hide()
    end
end

mod.RefreshTrinkets = function()
    H.ForEach(applyToFrame)
end

-- =========================================================
-- Trigger cooldown
-- =========================================================
local activeCDs = {}  -- arenaUnit -> { startTime, duration }

local function startCooldown(unit, duration)
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local arenaFrame = _G["ArenaEnemyFrame" .. i]
    if not arenaFrame then return end
    local tf = ensureTrinketFrame(arenaFrame, i)
    anchorTrinketFrame(tf, arenaFrame)

    tf.cd:SetCooldown(GetTime(), duration)
    tf.icon:SetDesaturated(true)
    if mod.db.trinketEnabled then tf:Show() end

    activeCDs[unit] = { start = GetTime(), duration = duration }

    -- Brighten again after expiry
    if C_Timer and C_Timer.After then
        C_Timer.After(duration + 0.1, function()
            if activeCDs[unit] and activeCDs[unit].start + activeCDs[unit].duration <= GetTime() then
                tf.icon:SetDesaturated(false)
                activeCDs[unit] = nil
            end
        end)
    end
end

-- =========================================================
-- Combat log: detect trinket cast
-- =========================================================
local function onCombatLog()
    local _, subevent, _, sourceGUID, _, sourceFlags, _, _, _, _, _, spellId =
        CombatLogGetCurrentEventInfo()

    if subevent ~= "SPELL_CAST_SUCCESS" then return end
    if not TRINKET_SPELLS[spellId] then return end

    -- Which arena slot is it?
    for i = 1, 5 do
        local unit = "arena" .. i
        if UnitExists(unit) and UnitGUID(unit) == sourceGUID then
            startCooldown(unit, TRINKET_SPELLS[spellId])
            return
        end
    end
end

-- =========================================================
-- On arena start: reset all CDs
-- =========================================================
local function resetAllCDs()
    activeCDs = {}
    for i, tf in pairs(trinketFrames) do
        if tf and tf.cd then
            tf.cd:Clear()
            tf.icon:SetDesaturated(false)
        end
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
mod:OnArenaFramesReady(function(frame, i)
    applyToFrame(frame, i)
end)

-- Named handler so the (very hot) combat log can be registered only while
-- inside an arena. Otherwise it would fire a pcall for every combat-log line
-- in raids / dungeons / the open world, even though this only shows in arenas.
local function onCLEU()
    if not mod._enabled or not mod.db.trinketEnabled then return end
    onCombatLog()
end

local cleuActive = false
local function setCombatLog(active)
    if active == cleuActive then return end
    cleuActive = active
    if active then
        ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    else
        ns:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    end
end

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    local inArena = false
    if IsInInstance then
        local _, instanceType = IsInInstance()
        inArena = (instanceType == "arena")
    end
    if not inArena then resetAllCDs() end  -- left the arena -> clear
    setCombatLog(inArena)
end)
ns:RegisterEvent("ARENA_OPPONENT_UPDATE", function(_, _, eventType)
    -- "seen" = new opponents; reset on match start
    if eventType == "seen" then resetAllCDs() end
end)

-- =========================================================
-- Options section
-- =========================================================
mod:AddOptionsSection("trinket", function()
    return {
        { type = "header", text = L["PvP Trinket Tracker"] },
        {
            type = "checkbox", label = L["Show PvP trinket cooldown"],
            tooltip = L["Shows an icon with cooldown spiral next to the arena frame when the opponent used their PvP trinket."],
            get = function() return mod.db.trinketEnabled end,
            set = function(_, v) mod.db.trinketEnabled = v; mod.RefreshTrinkets() end,
        },
        {
            type = "slider", label = L["Icon size"],
            min = 16, max = 48, step = 1,
            get = function() return mod.db.trinketSize end,
            set = function(_, v) mod.db.trinketSize = v; mod.RefreshTrinkets() end,
        },
        {
            type = "dropdown", label = L["Position"],
            values = {
                { value = "LEFT",  text = L["Left of frame"] },
                { value = "RIGHT", text = L["Right of frame"] },
            },
            get = function() return mod.db.trinketAnchor end,
            set = function(_, v) mod.db.trinketAnchor = v; mod.RefreshTrinkets() end,
        },
        {
            type = "slider", label = L["Offset X"],
            min = -50, max = 50, step = 1,
            get = function() return mod.db.trinketOffsetX end,
            set = function(_, v) mod.db.trinketOffsetX = v; mod.RefreshTrinkets() end,
        },
        {
            type = "slider", label = L["Offset Y"],
            min = -50, max = 50, step = 1,
            get = function() return mod.db.trinketOffsetY end,
            set = function(_, v) mod.db.trinketOffsetY = v; mod.RefreshTrinkets() end,
        },
    }
end)
