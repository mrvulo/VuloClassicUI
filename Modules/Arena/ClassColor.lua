-- =========================================================
-- VuloClassicUI / Modules / Arena / ClassColor
-- Klassen-farbige Health-Bar, Klassen-Icon statt Portrait, Name in Klassen-Farbe.
-- =========================================================
local _, ns = ...
local mod = ns.ArenaModule
local H = mod.helpers

-- =========================================================
-- Klassen-Icon Texture-Coords (Blizzards UI-Charactercreate-Classes)
-- =========================================================
local CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS or {
    ["WARRIOR"]     = { 0,    0.25, 0,    0.25 },
    ["MAGE"]        = { 0.25, 0.49, 0,    0.25 },
    ["ROGUE"]       = { 0.49, 0.73, 0,    0.25 },
    ["DRUID"]       = { 0.73, 0.97, 0,    0.25 },
    ["HUNTER"]      = { 0,    0.25, 0.25, 0.5 },
    ["SHAMAN"]      = { 0.25, 0.49, 0.25, 0.5 },
    ["PRIEST"]      = { 0.49, 0.73, 0.25, 0.5 },
    ["WARLOCK"]     = { 0.73, 0.97, 0.25, 0.5 },
    ["PALADIN"]     = { 0,    0.25, 0.5,  0.75 },
    ["DEATHKNIGHT"] = { 0.25, 0.49, 0.5,  0.75 },
    ["MONK"]        = { 0.49, 0.73, 0.5,  0.75 },
    ["DEMONHUNTER"] = { 0.73, 0.97, 0.5,  0.75 },
}

local CLASS_ICON_TEXTURE = "Interface\\WorldStateFrame\\Icons-Classes"

-- =========================================================
-- Klassen-Farbe holen
-- =========================================================
local function classColor(class)
    if not class then return nil end
    -- RAID_CLASS_COLORS ist in TBC 2.5.5 verfügbar
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- =========================================================
-- Pro Frame anwenden
-- =========================================================
local applyClassToFrame  -- forward declaration

local function applyToFrame(frame, i)
    local unit = H.GetUnit(i)
    if not UnitExists(unit) then
        -- Test-Mode: nutze irgendeine Klasse als Demo, sonst nichts
        if mod:IsUnlocked() then
            local demoClasses = { "WARRIOR", "MAGE", "ROGUE", "DRUID", "PRIEST" }
            local demo = demoClasses[i] or "WARRIOR"
            applyClassToFrame(frame, demo)
        end
        return
    end

    local _, class = UnitClass(unit)
    applyClassToFrame(frame, class)
end

applyClassToFrame = function(frame, class)  -- ist die forward-deklarierte local
    if not class then return end
    local r, g, b = classColor(class)

    -- Health-Bar einfärben
    if mod.db.classColorHealth then
        local health = H.GetArenaBars(frame)
        if health then
            health:SetStatusBarColor(r, g, b)
            -- Verhindern dass Blizzard zurückfärbt
            if health.SetForceStatusColor then health:SetForceStatusColor(r, g, b) end
        end
    end

    -- Name einfärben
    if mod.db.classColorName then
        local nameText = H.GetNameText(frame)
        if nameText then nameText:SetTextColor(r, g, b) end
    end

    -- Klassen-Icon statt Portrait
    if mod.db.classIconPortrait then
        local portrait = H.GetPortrait(frame)
        if portrait then
            portrait:SetTexture(CLASS_ICON_TEXTURE)
            local coords = CLASS_ICON_TCOORDS[class]
            if coords then
                portrait:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
            if portrait.SetVertexColor then portrait:SetVertexColor(1, 1, 1) end
        end
    end
end

-- Wenn Settings ausgeschaltet werden → originale Werte wiederherstellen
local function restoreFrame(frame, i)
    local unit = H.GetUnit(i)
    local health = H.GetArenaBars(frame)
    if health then
        -- Standard-Power-Type-Farbe (für Health: einfach generisches Grün, das ist Blizzards Default)
        health:SetStatusBarColor(0, 1, 0)
    end
    local nameText = H.GetNameText(frame)
    if nameText then nameText:SetTextColor(1, 0.82, 0) end

    -- Portrait: wenn Unit existiert, lass Blizzard es regenerieren
    local portrait = H.GetPortrait(frame)
    if portrait and UnitExists(unit) and SetPortraitTexture then
        portrait:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(portrait, unit)
    end
end

local function applyAll()
    H.ForEach(applyToFrame)
end

local function restoreAll()
    H.ForEach(restoreFrame)
end

mod.ApplyClassColors   = applyAll
mod.RestoreClassColors = restoreAll

-- =========================================================
-- Hooks + Events
-- =========================================================
mod:OnArenaFramesReady(function(frame, i)
    applyToFrame(frame, i)
end)

-- Blizzard schreibt Bar-Farbe bei TextStatusBar_UpdateTextString und Update zurück.
-- Wir hooken die wichtigsten Update-Pfade.
local classColorHooked = false
local function installHooks()
    if classColorHooked or not hooksecurefunc then return end
    classColorHooked = true

    if _G.ArenaEnemyFrames_UpdatePlayer then
        hooksecurefunc("ArenaEnemyFrames_UpdatePlayer", function()
            if not mod._enabled then return end
            applyAll()
        end)
    end
    if _G.UnitFrame_OnEvent then
        -- Riskanter Hook; nicht nötig wenn _UpdatePlayer reicht
    end
end

-- UNIT_PORTRAIT_UPDATE / PORTRAITS_UPDATED feuern wenn Blizzard das Portrait neu zeichnet
ns:RegisterEvent("UNIT_PORTRAIT_UPDATE", function(_, unit)
    if not mod._enabled then return end
    if unit and unit:match("^arena[1-5]$") then
        local i = tonumber(unit:match("arena(%d)"))
        local frame = _G["ArenaEnemyFrame" .. i]
        if frame then applyToFrame(frame, i) end
    end
end)

ns:RegisterEvent("ARENA_OPPONENT_UPDATE", function()
    if not mod._enabled then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, applyAll)
    else
        applyAll()
    end
end)

-- Setze Hooks bei Modul-Activate
mod:RegisterOnEnable(function()
    installHooks()
end)

-- =========================================================
-- Options-Section
-- =========================================================
mod:AddOptionsSection("classcolor", function()
    return {
        { type = "header", text = "Klassen-Optik" },
        {
            type = "checkbox", label = "Klassen-farbige Health-Bars",
            tooltip = "Färbt die Health-Bar in der Klassenfarbe des Spielers.",
            get = function() return mod.db.classColorHealth end,
            set = function(_, v)
                mod.db.classColorHealth = v
                if v then applyAll() else restoreAll() end
            end,
        },
        {
            type = "checkbox", label = "Klassen-farbiger Name",
            get = function() return mod.db.classColorName end,
            set = function(_, v) mod.db.classColorName = v; applyAll() end,
        },
        {
            type = "checkbox", label = "Klassen-Icon statt Portrait",
            tooltip = "Ersetzt das 3D-Portrait durch ein Klassen-Symbol.",
            get = function() return mod.db.classIconPortrait end,
            set = function(_, v)
                mod.db.classIconPortrait = v
                if v then applyAll() else restoreAll() end
            end,
        },
    }
end)
