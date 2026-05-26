-- =========================================================
-- VuloClassicUI / Core / Database
-- SavedVariables with profile system.
--
-- Structure:
--   VuloClassicUIDB.global              -- account-wide settings (debug, migration flags)
--   VuloClassicUIDB.profiles[name]      -- each profile contains modules.X.* settings
--   VuloClassicUIDB.classAssignments    -- "WARRIOR" -> "Warrior PvP"
--   VuloClassicUIDB.activeProfile       -- currently loaded profile (for char-specific overrides)
--
--   ns.db.profile.modules[key]          -- pointer to the current profile (same as before)
-- =========================================================
local _, ns = ...
local L = ns.L

ns.defaults = {
    global = {
        debug = false,
    },
    profile = {
        ui = {
            mainFramePos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
            scale = 1.0,
        },
        modules = {
            -- populated dynamically from mod.defaults
        },
    },
}

local DEFAULT_PROFILE = "Default"

-- =========================================================
-- Helpers
-- =========================================================
local function getCharKey()
    local name, realm = UnitName("player"), GetRealmName()
    return (name or "?") .. " - " .. (realm or "?")
end

local function getClassKey()
    local _, class = UnitClass("player")
    return class or "UNKNOWN"
end

-- =========================================================
-- Init after ADDON_LOADED
-- =========================================================
function ns:InitDB()
    VuloClassicUIDB     = VuloClassicUIDB     or {}
    VuloClassicUICharDB = VuloClassicUICharDB or {}

    -- Migration: old structure (db.profile.modules.X) to new (db.profiles.Default.modules.X)
    if VuloClassicUIDB.profile and not VuloClassicUIDB.profiles then
        VuloClassicUIDB.profiles = {
            [DEFAULT_PROFILE] = VuloClassicUIDB.profile,
        }
        VuloClassicUIDB.profile = nil
        ns:Print(L["Settings migrated to profile system (all settings are in profile '%s')."], DEFAULT_PROFILE)
    end

    VuloClassicUIDB.global            = VuloClassicUIDB.global            or {}
    VuloClassicUIDB.profiles          = VuloClassicUIDB.profiles          or {}
    VuloClassicUIDB.classAssignments  = VuloClassicUIDB.classAssignments  or {}

    -- Global defaults
    VuloClassicUIDB.global = ns:ApplyDefaults(VuloClassicUIDB.global, ns.defaults.global)

    -- Make sure the Default profile exists
    if not VuloClassicUIDB.profiles[DEFAULT_PROFILE] then
        VuloClassicUIDB.profiles[DEFAULT_PROFILE] = {}
    end
    VuloClassicUIDB.profiles[DEFAULT_PROFILE] = ns:ApplyDefaults(
        VuloClassicUIDB.profiles[DEFAULT_PROFILE], ns.defaults.profile
    )

    -- Determine active profile:
    --   1. Class assignment
    --   2. Fallback: last active profile
    --   3. Fallback: Default
    local classKey   = getClassKey()
    local assigned   = VuloClassicUIDB.classAssignments[classKey]
    local activeName = assigned or VuloClassicUIDB.activeProfile or DEFAULT_PROFILE

    -- If the profile no longer exists: use Default
    if not VuloClassicUIDB.profiles[activeName] then
        activeName = DEFAULT_PROFILE
    end

    ns:LoadProfile(activeName)

    -- Char DB
    VuloClassicUICharDB = ns:ApplyDefaults(VuloClassicUICharDB, ns.defaults.char or {})

    ns.db.global = VuloClassicUIDB.global
    ns.db.char   = VuloClassicUICharDB

    -- Migrate old standalone addon SVs (one-time only)
    ns:MigrateLegacyDBs()
end

-- =========================================================
-- Load profile (sets ns.db.profile to the selected profile)
-- =========================================================
function ns:LoadProfile(profileName)
    local profileData = VuloClassicUIDB.profiles[profileName]
    if not profileData then
        ns:Print(L["|cffff5555Profile '%s' does not exist.|r"], profileName)
        return false
    end

    -- Apply defaults to the profile (for new settings the profile doesn't know yet)
    profileData = ns:ApplyDefaults(profileData, ns.defaults.profile)

    -- Apply module-specific defaults
    for key, mod in pairs(ns.modules or {}) do
        profileData.modules[key] = ns:ApplyDefaults(
            profileData.modules[key], mod.defaults or {}
        )
    end

    VuloClassicUIDB.profiles[profileName] = profileData
    VuloClassicUIDB.activeProfile = profileName

    ns.db = ns.db or {}
    ns.db.profile = profileData

    -- Re-link modules with their mod.db
    for key, mod in pairs(ns.modules or {}) do
        mod.db = profileData.modules[key]
    end

    return true
end

-- =========================================================
-- Profile API
-- =========================================================
function ns:GetActiveProfileName()
    return VuloClassicUIDB and VuloClassicUIDB.activeProfile or DEFAULT_PROFILE
end

function ns:GetProfileNames()
    local list = {}
    if not VuloClassicUIDB or not VuloClassicUIDB.profiles then return list end
    for name in pairs(VuloClassicUIDB.profiles) do table.insert(list, name) end
    table.sort(list)
    return list
end

function ns:ProfileExists(name)
    return VuloClassicUIDB and VuloClassicUIDB.profiles and VuloClassicUIDB.profiles[name] ~= nil
end

function ns:CreateProfile(name, copyFrom)
    if not name or name == "" then return false, L["Name cannot be empty."] end
    if ns:ProfileExists(name) then return false, L["Profile already exists."] end

    local newProfile
    if copyFrom and ns:ProfileExists(copyFrom) then
        newProfile = ns:DeepCopy(VuloClassicUIDB.profiles[copyFrom])
    else
        newProfile = ns:DeepCopy(ns.defaults.profile)
    end

    VuloClassicUIDB.profiles[name] = newProfile
    ns:Print(L["Profile '%s' created%s."], name, copyFrom and string.format(L[" (copy of '%s')"], copyFrom) or "")
    return true
end

function ns:DeleteProfile(name)
    if name == DEFAULT_PROFILE then return false, L["Default profile cannot be deleted."] end
    if not ns:ProfileExists(name) then return false, L["Profile does not exist."] end

    VuloClassicUIDB.profiles[name] = nil

    -- Clean up class assignments
    for classKey, assigned in pairs(VuloClassicUIDB.classAssignments) do
        if assigned == name then
            VuloClassicUIDB.classAssignments[classKey] = nil
        end
    end

    -- If active profile was deleted: revert to Default
    if ns:GetActiveProfileName() == name then
        ns:LoadProfile(DEFAULT_PROFILE)
        ns:Print(L["Active profile deleted. Default loaded. /reload recommended."])
    end

    ns:Print(L["Profile '%s' deleted."], name)
    return true
end

function ns:RenameProfile(oldName, newName)
    if oldName == DEFAULT_PROFILE then return false, L["Default profile cannot be renamed."] end
    if not ns:ProfileExists(oldName) then return false, L["Profile does not exist."] end
    if not newName or newName == "" then return false, L["Name cannot be empty."] end
    if ns:ProfileExists(newName) then return false, L["New name already exists."] end

    VuloClassicUIDB.profiles[newName] = VuloClassicUIDB.profiles[oldName]
    VuloClassicUIDB.profiles[oldName] = nil

    for classKey, assigned in pairs(VuloClassicUIDB.classAssignments) do
        if assigned == oldName then
            VuloClassicUIDB.classAssignments[classKey] = newName
        end
    end

    if ns:GetActiveProfileName() == oldName then
        VuloClassicUIDB.activeProfile = newName
    end

    ns:Print(L["Profile '%s' renamed to '%s'."], oldName, newName)
    return true
end

function ns:SwitchProfile(name)
    if not ns:ProfileExists(name) then
        ns:Print(L["|cffff5555Profile '%s' does not exist.|r"], name)
        return false
    end
    if ns:GetActiveProfileName() == name then return true end

    ns:LoadProfile(name)
    ns:Print(L["Profile '%s' loaded. |cffffff00/reload|r recommended so all modules use the new settings."], name)
    return true
end

function ns:AssignClassToProfile(classKey, profileName)
    if profileName and profileName ~= "" and not ns:ProfileExists(profileName) then
        return false
    end
    if profileName == "" or profileName == nil then
        VuloClassicUIDB.classAssignments[classKey] = nil
    else
        VuloClassicUIDB.classAssignments[classKey] = profileName
    end
    return true
end

function ns:GetClassAssignment(classKey)
    return VuloClassicUIDB and VuloClassicUIDB.classAssignments
        and VuloClassicUIDB.classAssignments[classKey]
end

function ns:GetMyClassKey() return getClassKey() end

-- =========================================================
-- Migration of old standalone addons (one-time, moves into Default profile)
-- =========================================================
function ns:MigrateLegacyDBs()
    if ns.db.global.migratedLegacy then return end

    local defaultProfile = VuloClassicUIDB.profiles[DEFAULT_PROFILE]

    if VuloFontBarsDB and ns.modules.fontbars then
        local src = VuloFontBarsDB
        local dst = defaultProfile.modules.fontbars
        if src.healthSize      then dst.healthSize      = src.healthSize end
        if src.powerSize       then dst.powerSize       = src.powerSize end
        if src.petFeedbackSize then dst.petFeedbackSize = src.petFeedbackSize end
        if src.onlyTheseBars ~= nil then dst.onlyTheseBars = src.onlyTheseBars end
        ns:Print(L["Settings imported from VuloFontBars."])
    end

    if ArenaEnemyEditDB and ns.modules.arenaframes then
        local src = ArenaEnemyEditDB
        local dst = defaultProfile.modules.arenaframes
        if src.pos        then dst.pos        = src.pos end
        if src.scale      then dst.scale      = src.scale end
        if src.healthSize then dst.healthSize = src.healthSize end
        if src.powerSize  then dst.powerSize  = src.powerSize end
        ns:Print(L["Settings imported from ArenaEnemyEdit."])
    end

    if BetterBlizzQueueDB and ns.modules.queuetimer then
        local src = BetterBlizzQueueDB
        local dst = defaultProfile.modules.queuetimer
        if src.queueTimerAudio   ~= nil then dst.queueTimerAudio   = src.queueTimerAudio end
        if src.queueTimerWarning ~= nil then dst.queueTimerWarning = src.queueTimerWarning end
        if src.hideOtherTimers   ~= nil then dst.hideOtherTimers   = src.hideOtherTimers end
        ns:Print(L["Settings imported from BetterBlizzQueue."])
    end

    if idTipConfig and ns.modules.tooltipids then
        local src = idTipConfig
        local dst = defaultProfile.modules.tooltipids
        if src.enabled ~= nil then dst.enabled = src.enabled end
        local idTipKinds = ns.modules.tooltipids.kinds
        if idTipKinds then
            for kind in pairs(idTipKinds) do
                local v = src[kind .. "Enabled"]
                if type(v) == "boolean" then dst[kind] = v end
            end
        end
        ns:Print(L["Settings imported from idTip."])
    end

    ns.db.global.migratedLegacy = true
end

-- =========================================================
-- Convenience accessor
-- =========================================================
function ns:GetModuleDB(key)
    if not ns.db or not ns.db.profile then return nil end
    return ns.db.profile.modules[key]
end
