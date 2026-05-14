-- =========================================================
-- VuloClassicUI / Modules / Arena / Trinket
-- PvP-Trinket-Cooldown-Tracker pro Arena-Gegner.
-- Erkennt den Cast über COMBAT_LOG_EVENT_UNFILTERED und zeigt Icon + Timer.
-- =========================================================
local _, ns = ...
local mod = ns.ArenaModule
local H = mod.helpers

-- =========================================================
-- TBC PvP Trinket Spells und ihre Cooldowns
-- =========================================================
local TRINKET_SPELLS = {
    -- PvP Trinket Item-Spells (alle gleicher Effekt, alle 2 min CD in TBC)
    [42292] = 120,  -- PvP Trinket (Gladiator/Arena/Honor)
    [7744]  = 120,  -- Will of the Forsaken (Undead)
    [59752] = 120,  -- Will to Survive / Every Man for Himself (Human, retail)
    [20594] = 120,  -- Stoneform (Dwarf) - eigentlich Bleed/Disease/Poison Removal, aber teilt sich CD-ähnlich
}

-- Icons für die Trinkets (Atlas geht in TBC nicht überall, daher TexturePath)
local TRINKET_TEXTURE = "Interface\\Icons\\INV_Jewelry_TrinketPVP_02"

-- Pro Slot ein Trinket-Frame
local trinketFrames = {}

-- =========================================================
-- Trinket-Frame erstellen
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

    -- Cooldown-Spiral
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(true)
    f.cd:SetHideCountdownNumbers(false)

    -- Tooltip
    f:EnableMouse(false)  -- nicht klickbar, sonst Combat-Probleme

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
-- Anchor + Anzeige
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
            -- Test: zeige Icon ohne Cooldown
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
-- Cooldown auslösen
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

    -- Nach Ablauf wieder hell
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
-- Combat Log: Trinket-Cast erkennen
-- =========================================================
local function onCombatLog()
    local _, subevent, _, sourceGUID, _, sourceFlags, _, _, _, _, _, spellId =
        CombatLogGetCurrentEventInfo()

    if subevent ~= "SPELL_CAST_SUCCESS" then return end
    if not TRINKET_SPELLS[spellId] then return end

    -- Welcher Arena-Slot ist das?
    for i = 1, 5 do
        local unit = "arena" .. i
        if UnitExists(unit) and UnitGUID(unit) == sourceGUID then
            startCooldown(unit, TRINKET_SPELLS[spellId])
            return
        end
    end
end

-- =========================================================
-- Bei Arena-Start: alle CDs zurücksetzen
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

ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
    if not mod._enabled or not mod.db.trinketEnabled then return end
    onCombatLog()
end)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    -- Beim Zone-Wechsel weg von Arena → reset
    if IsInInstance then
        local _, instanceType = IsInInstance()
        if instanceType ~= "arena" then resetAllCDs() end
    end
end)
ns:RegisterEvent("ARENA_OPPONENT_UPDATE", function(_, _, eventType)
    -- "seen" = neue Gegner; bei Match-Start reset
    if eventType == "seen" then resetAllCDs() end
end)

-- =========================================================
-- Options-Section
-- =========================================================
mod:AddOptionsSection("trinket", function()
    return {
        { type = "header", text = "PvP-Trinket Tracker" },
        {
            type = "checkbox", label = "PvP-Trinket-Cooldown anzeigen",
            tooltip = "Zeigt ein Icon mit Cooldown-Spiral neben dem Arena-Frame an, wenn der Gegner sein PvP-Trinket benutzt hat.",
            get = function() return mod.db.trinketEnabled end,
            set = function(_, v) mod.db.trinketEnabled = v; mod.RefreshTrinkets() end,
        },
        {
            type = "slider", label = "Icon-Größe",
            min = 16, max = 48, step = 1,
            get = function() return mod.db.trinketSize end,
            set = function(_, v) mod.db.trinketSize = v; mod.RefreshTrinkets() end,
        },
        {
            type = "dropdown", label = "Position",
            values = {
                { value = "LEFT",  text = "Links vom Frame" },
                { value = "RIGHT", text = "Rechts vom Frame" },
            },
            get = function() return mod.db.trinketAnchor end,
            set = function(_, v) mod.db.trinketAnchor = v; mod.RefreshTrinkets() end,
        },
        {
            type = "slider", label = "Offset X",
            min = -50, max = 50, step = 1,
            get = function() return mod.db.trinketOffsetX end,
            set = function(_, v) mod.db.trinketOffsetX = v; mod.RefreshTrinkets() end,
        },
        {
            type = "slider", label = "Offset Y",
            min = -50, max = 50, step = 1,
            get = function() return mod.db.trinketOffsetY end,
            set = function(_, v) mod.db.trinketOffsetY = v; mod.RefreshTrinkets() end,
        },
    }
end)
