-- =========================================================
-- VuloClassicUI / Core / Database
-- SavedVariables mit Profile-System.
--
-- Struktur:
--   VuloClassicUIDB.global              -- account-wide settings (debug, migration flags)
--   VuloClassicUIDB.profiles[name]      -- jedes Profil enthält modules.X.* settings
--   VuloClassicUIDB.classAssignments    -- "WARRIOR" -> "Krieger PvP"
--   VuloClassicUIDB.activeProfile       -- aktuell geladenes Profil (für Char-spezifische Overrides)
--
--   ns.db.profile.modules[key]          -- pointer auf das aktuelle Profil (so wie vorher)
-- =========================================================
local _, ns = ...

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
            -- wird dynamisch aufgefüllt aus mod.defaults
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
-- Init nach ADDON_LOADED
-- =========================================================
function ns:InitDB()
    VuloClassicUIDB     = VuloClassicUIDB     or {}
    VuloClassicUICharDB = VuloClassicUICharDB or {}

    -- Migration: alte Struktur (db.profile.modules.X) auf neue (db.profiles.Default.modules.X)
    if VuloClassicUIDB.profile and not VuloClassicUIDB.profiles then
        VuloClassicUIDB.profiles = {
            [DEFAULT_PROFILE] = VuloClassicUIDB.profile,
        }
        VuloClassicUIDB.profile = nil
        ns:Print("Settings auf Profile-System migriert (alle Settings sind im Profil '%s').", DEFAULT_PROFILE)
    end

    VuloClassicUIDB.global            = VuloClassicUIDB.global            or {}
    VuloClassicUIDB.profiles          = VuloClassicUIDB.profiles          or {}
    VuloClassicUIDB.classAssignments  = VuloClassicUIDB.classAssignments  or {}

    -- Globale Defaults
    VuloClassicUIDB.global = ns:ApplyDefaults(VuloClassicUIDB.global, ns.defaults.global)

    -- Sicherstellen dass das Default-Profil existiert
    if not VuloClassicUIDB.profiles[DEFAULT_PROFILE] then
        VuloClassicUIDB.profiles[DEFAULT_PROFILE] = {}
    end
    VuloClassicUIDB.profiles[DEFAULT_PROFILE] = ns:ApplyDefaults(
        VuloClassicUIDB.profiles[DEFAULT_PROFILE], ns.defaults.profile
    )

    -- Aktives Profil bestimmen:
    --   1. Klassen-Zuweisung
    --   2. Fallback: zuletzt aktives Profil
    --   3. Fallback: Default
    local classKey   = getClassKey()
    local assigned   = VuloClassicUIDB.classAssignments[classKey]
    local activeName = assigned or VuloClassicUIDB.activeProfile or DEFAULT_PROFILE

    -- Falls das Profil nicht (mehr) existiert: Default nehmen
    if not VuloClassicUIDB.profiles[activeName] then
        activeName = DEFAULT_PROFILE
    end

    ns:LoadProfile(activeName)

    -- Char-DB
    VuloClassicUICharDB = ns:ApplyDefaults(VuloClassicUICharDB, ns.defaults.char or {})

    ns.db.global = VuloClassicUIDB.global
    ns.db.char   = VuloClassicUICharDB

    -- Migration alter Standalone-Addon-SVs (nur einmalig)
    ns:MigrateLegacyDBs()
end

-- =========================================================
-- Profile laden (setzt ns.db.profile auf das gewählte Profil)
-- =========================================================
function ns:LoadProfile(profileName)
    local profileData = VuloClassicUIDB.profiles[profileName]
    if not profileData then
        ns:Print("|cffff5555Profil '%s' existiert nicht.|r", profileName)
        return false
    end

    -- Defaults aufs Profil anwenden (für neue Settings die das Profil noch nicht kennt)
    profileData = ns:ApplyDefaults(profileData, ns.defaults.profile)

    -- Modul-spezifische Defaults rein
    for key, mod in pairs(ns.modules or {}) do
        profileData.modules[key] = ns:ApplyDefaults(
            profileData.modules[key], mod.defaults or {}
        )
    end

    VuloClassicUIDB.profiles[profileName] = profileData
    VuloClassicUIDB.activeProfile = profileName

    ns.db = ns.db or {}
    ns.db.profile = profileData

    -- Module mit ihrem mod.db neu verknüpfen
    for key, mod in pairs(ns.modules or {}) do
        mod.db = profileData.modules[key]
    end

    return true
end

-- =========================================================
-- Profile-API
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
    if not name or name == "" then return false, "Name darf nicht leer sein." end
    if ns:ProfileExists(name) then return false, "Profil existiert bereits." end

    local newProfile
    if copyFrom and ns:ProfileExists(copyFrom) then
        newProfile = ns:DeepCopy(VuloClassicUIDB.profiles[copyFrom])
    else
        newProfile = ns:DeepCopy(ns.defaults.profile)
    end

    VuloClassicUIDB.profiles[name] = newProfile
    ns:Print("Profil '%s' erstellt%s.", name, copyFrom and (" (Kopie von '" .. copyFrom .. "')") or "")
    return true
end

function ns:DeleteProfile(name)
    if name == DEFAULT_PROFILE then return false, "Default-Profil kann nicht gelöscht werden." end
    if not ns:ProfileExists(name) then return false, "Profil existiert nicht." end

    VuloClassicUIDB.profiles[name] = nil

    -- Klassen-Zuweisungen aufräumen
    for classKey, assigned in pairs(VuloClassicUIDB.classAssignments) do
        if assigned == name then
            VuloClassicUIDB.classAssignments[classKey] = nil
        end
    end

    -- Falls aktives Profil gelöscht wurde: zurück auf Default
    if ns:GetActiveProfileName() == name then
        ns:LoadProfile(DEFAULT_PROFILE)
        ns:Print("Aktives Profil gelöscht. Default geladen. /reload empfohlen.")
    end

    ns:Print("Profil '%s' gelöscht.", name)
    return true
end

function ns:RenameProfile(oldName, newName)
    if oldName == DEFAULT_PROFILE then return false, "Default-Profil kann nicht umbenannt werden." end
    if not ns:ProfileExists(oldName) then return false, "Profil existiert nicht." end
    if not newName or newName == "" then return false, "Name darf nicht leer sein." end
    if ns:ProfileExists(newName) then return false, "Neuer Name existiert bereits." end

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

    ns:Print("Profil '%s' umbenannt zu '%s'.", oldName, newName)
    return true
end

function ns:SwitchProfile(name)
    if not ns:ProfileExists(name) then
        ns:Print("|cffff5555Profil '%s' existiert nicht.|r", name)
        return false
    end
    if ns:GetActiveProfileName() == name then return true end

    ns:LoadProfile(name)
    ns:Print("Profil '%s' geladen. |cffffff00/reload|r empfohlen damit alle Module die neuen Settings nutzen.", name)
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
-- Migration alter Standalone-Addons (einmalig, wandert in Default-Profil)
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
        ns:Print("Settings aus VuloFontBars übernommen.")
    end

    if ArenaEnemyEditDB and ns.modules.arenaframes then
        local src = ArenaEnemyEditDB
        local dst = defaultProfile.modules.arenaframes
        if src.pos        then dst.pos        = src.pos end
        if src.scale      then dst.scale      = src.scale end
        if src.healthSize then dst.healthSize = src.healthSize end
        if src.powerSize  then dst.powerSize  = src.powerSize end
        ns:Print("Settings aus ArenaEnemyEdit übernommen.")
    end

    if BetterBlizzQueueDB and ns.modules.queuetimer then
        local src = BetterBlizzQueueDB
        local dst = defaultProfile.modules.queuetimer
        if src.queueTimerAudio   ~= nil then dst.queueTimerAudio   = src.queueTimerAudio end
        if src.queueTimerWarning ~= nil then dst.queueTimerWarning = src.queueTimerWarning end
        if src.hideOtherTimers   ~= nil then dst.hideOtherTimers   = src.hideOtherTimers end
        ns:Print("Settings aus BetterBlizzQueue übernommen.")
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
        ns:Print("Settings aus idTip übernommen.")
    end

    ns.db.global.migratedLegacy = true
end

-- =========================================================
-- Komfort-Accessor
-- =========================================================
function ns:GetModuleDB(key)
    if not ns.db or not ns.db.profile then return nil end
    return ns.db.profile.modules[key]
end
