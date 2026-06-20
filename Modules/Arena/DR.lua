-- =========================================================
-- VuloClassicUI / Modules / Arena / DR (Diminishing Returns)
-- Tracks DR categories per arena opponent and shows icon + timer.
--
-- TBC DR system: Full -> 1/2 -> 1/4 -> Immune
-- Reset after ~15-18 seconds without a new cast of the same category.
-- =========================================================
local _, ns = ...
local L = ns.L
local mod = ns.ArenaModule

local DR_RESET_TIME = 18  -- TBC

-- =========================================================
-- DR categories (order determines ID mapping in DR_SPELLS)
-- Source: warcraft.wiki.gg/wiki/Diminishing_returns (TBC entry)
-- =========================================================

-- Spell -> category. Intentionally trimmed to the most important TBC spells.
-- You can extend the list. For spells with rank variants, usually
-- only the final rank ID is here; add more if needed.
local DR_SPELLS = {
    -- Stuns
    [408]   = "stun",          -- Kidney Shot
    [1833]  = "stun",          -- Cheap Shot
    [5211]  = "stun",          -- Bash (Druid)
    [12809] = "stun",          -- Concussion Blow
    [20549] = "stun",          -- War Stomp (Tauren racial)
    [22703] = "stun",          -- Inferno Effect (Warlock Pet)
    [25274] = "stun",          -- Intercept
    [30283] = "stun",          -- Shadowfury (TBC)
    [12355] = "stun",          -- Impact (Mage stun proc)
    [19577] = "stun",          -- Intimidation (Hunter Pet)

    -- Incapacitate (Polymorph, Sap, Repentance, Freezing Trap, etc.)
    [118]   = "incapacitate",  -- Polymorph
    [12826] = "incapacitate",  -- Polymorph (Rank 4)
    [28272] = "incapacitate",  -- Polymorph: Pig
    [28271] = "incapacitate",  -- Polymorph: Turtle
    [6770]  = "incapacitate",  -- Sap
    [11297] = "incapacitate",  -- Sap (Rank 2)
    [3355]  = "incapacitate",  -- Freezing Trap Effect
    [9484]  = "incapacitate",  -- Shackle Undead
    [20066] = "incapacitate",  -- Repentance
    [2637]  = "incapacitate",  -- Hibernate

    -- Disorient
    [2094]  = "disorient",     -- Blind

    -- Fear
    [5782]  = "fear",          -- Fear (Warlock)
    [6358]  = "fear",          -- Seduction (Succubus)
    [5484]  = "fear",          -- Howl of Terror
    [8122]  = "fear",          -- Psychic Scream
    [5246]  = "fear",          -- Intimidating Shout
    [10326] = "fear",          -- Turn Evil

    -- Silence
    [15487] = "silence",       -- Silence (Priest)
    [18498] = "silence",       -- Silenced (Warrior Shield Bash effect)
    [24259] = "silence",       -- Spell Lock
    [25046] = "silence",       -- Arcane Torrent (Blood Elf racial)

    -- Root
    [122]   = "root",          -- Frost Nova
    [339]   = "root",          -- Entangling Roots
    [19185] = "root",          -- Entrapment
    [13099] = "root",          -- Net-o-Matic

    -- Cyclone (own category in TBC)
    [33786] = "cyclone",
}

-- =========================================================
-- DR state per unit
-- =========================================================
-- drState[unit][category] = { applied = number, expires = number }
local drState = {}

-- One row of DR icons per slot
-- drFrames[slot] = { container = Frame, icons = { [category] = icon } }
local drFrames = {}

-- =========================================================
-- Create DR icon frame
-- =========================================================
local function createDRContainer(parent, slotIndex)
    local container = CreateFrame("Frame", "VCUIArenaDR" .. slotIndex, parent)
    container:SetSize(120, mod.db.drSize or 24)
    container.icons = {}
    return container
end

local function createDRIcon(parent, category)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(mod.db.drSize or 24, mod.db.drSize or 24)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Border (shows DR level: yellow = 1/2, orange = 1/4, red = immune)
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    f.border:SetColorTexture(0, 1, 0, 1)  -- start: full
    f.border:SetDrawLayer("BACKGROUND")

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(true)

    f.category = category
    f:Hide()
    return f
end

-- =========================================================
-- Update DR display
-- =========================================================
local function getDRColor(level)
    -- level: 1 = full, 2 = half, 3 = quarter, 4 = immune
    if level == 1 then return 0, 1, 0 end
    if level == 2 then return 1, 1, 0 end
    if level == 3 then return 1, 0.5, 0 end
    return 1, 0, 0
end

local function getDRLevel(applied)
    if applied <= 1 then return 1 end
    if applied == 2 then return 2 end
    if applied == 3 then return 3 end
    return 4
end

local function updateDRDisplay(unit)
    if not mod.db.drEnabled then return end
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local arenaFrame = _G["ArenaEnemyFrame" .. i]
    if not arenaFrame then return end

    local container = drFrames[i]
    if not container then
        container = createDRContainer(arenaFrame, i)
        drFrames[i] = container
        container:ClearAllPoints()
        container:SetPoint("LEFT", arenaFrame, "RIGHT", 8, 0)
    end

    -- Arrange visible icons in a row
    local state = drState[unit] or {}
    local visible = {}
    for cat, data in pairs(state) do
        if data.expires > GetTime() then
            table.insert(visible, { cat = cat, data = data })
        end
    end
    -- Stable sort (alphabetical)
    table.sort(visible, function(a, b) return a.cat < b.cat end)

    -- Hide all
    for _, icon in pairs(container.icons) do icon:Hide() end

    local x = 0
    for _, entry in ipairs(visible) do
        local icon = container.icons[entry.cat]
        if not icon then
            icon = createDRIcon(container, entry.cat)
            container.icons[entry.cat] = icon
        end
        icon:SetSize(mod.db.drSize, mod.db.drSize)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", container, "LEFT", x, 0)

        -- Texture: resolved once per icon from a cached category->spell map,
        -- instead of rescanning DR_SPELLS + GetSpellInfo every 0.5s tick
        if not icon._texSet then
            mod._drCatFirst = mod._drCatFirst or (function()
                local t = {}
                for sid, c in pairs(DR_SPELLS) do if not t[c] then t[c] = sid end end
                return t
            end)()
            local sid = mod._drCatFirst[entry.cat]
            if sid then
                local _, _, iconTex = GetSpellInfo(sid)
                if iconTex then icon.icon:SetTexture(iconTex); icon._texSet = true end
            end
        end

        local level = getDRLevel(entry.data.applied)
        icon.border:SetColorTexture(getDRColor(level))

        icon.cd:SetCooldown(entry.data.appliedTime, DR_RESET_TIME)
        icon:Show()

        x = x + mod.db.drSize + 2
    end
end

-- =========================================================
-- Process DR event
-- =========================================================
local function onAuraApplied(destUnit, spellId)
    local cat = DR_SPELLS[spellId]
    if not cat then return end

    drState[destUnit] = drState[destUnit] or {}
    local entry = drState[destUnit][cat]
    if not entry then
        entry = { applied = 0, expires = 0, appliedTime = 0 }
        drState[destUnit][cat] = entry
    end

    -- If the previous entry has expired, reset
    if entry.expires < GetTime() then
        entry.applied = 0
    end

    entry.applied = math.min(entry.applied + 1, 4)
    entry.appliedTime = GetTime()
    entry.expires = GetTime() + DR_RESET_TIME

    updateDRDisplay(destUnit)
end

-- =========================================================
-- Combat log
-- =========================================================
local function onCombatLog()
    local _, subevent, _, _, _, _, _, destGUID, _, _, _, spellId =
        CombatLogGetCurrentEventInfo()

    if subevent ~= "SPELL_AURA_APPLIED" and subevent ~= "SPELL_AURA_REFRESH" then return end
    if not DR_SPELLS[spellId] then return end

    for i = 1, 5 do
        local unit = "arena" .. i
        if UnitExists(unit) and UnitGUID(unit) == destGUID then
            onAuraApplied(unit, spellId)
            return
        end
    end
end

-- =========================================================
-- Periodic update (for expiration)
-- =========================================================
local updaterFrame
local function ensureUpdater()
    if updaterFrame then return end
    updaterFrame = CreateFrame("Frame")
    updaterFrame.timer = 0
    updaterFrame:SetScript("OnUpdate", function(self, elapsed)
        self.timer = self.timer + elapsed
        if self.timer < 0.5 then return end
        self.timer = 0
        if not mod.db.drEnabled or not mod._enabled then return end
        for unit in pairs(drState) do
            updateDRDisplay(unit)
        end
    end)
end

-- =========================================================
-- Reset
-- =========================================================
local function resetAll()
    drState = {}
    for _, container in pairs(drFrames) do
        for _, icon in pairs(container.icons) do icon:Hide() end
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
-- Named handler so the (very hot) combat log can be registered only while
-- inside an arena. Otherwise it would fire a pcall for every combat-log line
-- in raids / dungeons / the open world, even though DR only shows in arenas.
local function onCLEU()
    if not mod._enabled or not mod.db.drEnabled then return end
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
    resetAll()
    local inArena = false
    if IsInInstance then
        local _, instanceType = IsInInstance()
        inArena = (instanceType == "arena")
    end
    if inArena then ensureUpdater() end
    setCombatLog(inArena)
end)

-- =========================================================
-- Options
-- =========================================================
mod:AddOptionsSection("dr", function()
    return {
        { type = "header", text = L["Diminishing Returns Tracker"] },
        { type = "desc",   text = L["Shows icons to the right of each arena frame for active DR categories (Stun, Fear, Polymorph etc.) with color indicator: |cff00ff00green|r = full, |cffffff00yellow|r = 1/2, |cffff8000orange|r = 1/4, |cffff0000red|r = immune."] },
        {
            type = "checkbox", label = L["Enable DR tracking"],
            get = function() return mod.db.drEnabled end,
            set = function(_, v)
                mod.db.drEnabled = v
                if not v then resetAll() end
            end,
        },
        {
            type = "slider", label = L["Icon size"],
            min = 16, max = 40, step = 1,
            get = function() return mod.db.drSize end,
            set = function(_, v) mod.db.drSize = v end,
        },
    }
end)
