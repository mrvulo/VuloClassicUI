-- SavedVariables: VuloClassicUIDB holds global/profiles[name]/classAssignments/activeProfile; ns.db.profile points at the active profile.
local _, ns = ...
local L = ns.L

ns.defaults = {
    global = {
        debug = false,
        -- account-wide so layouts are shared across profiles and characters
        editLayouts = {},
    },
    profile = {
        ui = {
            mainFramePos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
            scale = 1.0,
        },
        editmode = {
            grid = { show = false, snap = true, size = 32 },
        },
        modules = {
            -- filled from mod.defaults at load
        },
    },
}

local DEFAULT_PROFILE = "Default"

local function getClassKey()
    local _, class = UnitClass("player")
    return class or "UNKNOWN"
end

-- Must stay in sync with CLASS_LABELS in Modules/Profiles.lua so the auto per-class profile name matches the button.
local CLASS_ENGLISH = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock",
    DRUID = "Druid",
}
function ns:GetClassProfileName(classKey)
    local eng = CLASS_ENGLISH[classKey]
    return (eng and L[eng]) or classKey
end

-- Runs on ADDON_LOADED, once SavedVariables exist.
function ns:InitDB()
    VuloClassicUIDB     = VuloClassicUIDB     or {}
    VuloClassicUICharDB = VuloClassicUICharDB or {}

    if ns.RefreshLocale then ns:RefreshLocale() end

    -- Migration: single db.profile -> db.profiles.Default
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

    VuloClassicUIDB.global = ns:ApplyDefaults(VuloClassicUIDB.global, ns.defaults.global)

    if not VuloClassicUIDB.profiles[DEFAULT_PROFILE] then
        VuloClassicUIDB.profiles[DEFAULT_PROFILE] = {}
    end
    VuloClassicUIDB.profiles[DEFAULT_PROFILE] = ns:ApplyDefaults(
        VuloClassicUIDB.profiles[DEFAULT_PROFILE], ns.defaults.profile
    )

    ns:MigrateUnitFramesMerge()
    ns:MigrateDarkSkinMerge()

    -- Precedence: char assignment > class assignment > this char's own auto-created class profile, so class settings never bleed onto another class.
    local charAssigned = VuloClassicUICharDB.profileOverride
    if charAssigned and not VuloClassicUIDB.profiles[charAssigned] then
        VuloClassicUICharDB.profileOverride = nil
        charAssigned = nil
    end
    local classKey   = getClassKey()
    local assigned   = VuloClassicUIDB.classAssignments[classKey]
    if assigned and not VuloClassicUIDB.profiles[assigned] then
        -- deleted/renamed elsewhere — self-heal, a fresh class profile is made below
        VuloClassicUIDB.classAssignments[classKey] = nil
        assigned = nil
    end
    local activeName = charAssigned or assigned

    if not activeName then
        -- Seed the per-class profile from Default on that class's first login, so existing users keep their look; it diverges freely afterwards.
        if classKey ~= "UNKNOWN" then
            activeName = ns:GetClassProfileName(classKey)
            if not VuloClassicUIDB.profiles[activeName] then
                VuloClassicUIDB.profiles[activeName] =
                    ns:DeepCopy(VuloClassicUIDB.profiles[DEFAULT_PROFILE])
            end
            VuloClassicUIDB.classAssignments[classKey] = activeName
        else
            activeName = VuloClassicUIDB.activeProfile or DEFAULT_PROFILE
        end
    end

    if not VuloClassicUIDB.profiles[activeName] then
        activeName = DEFAULT_PROFILE
    end

    ns:LoadProfile(activeName)

    -- needs the active profile loaded
    ns:MigrateDarkSkinPerChar()

    VuloClassicUICharDB = ns:ApplyDefaults(VuloClassicUICharDB, ns.defaults.char or {})

    ns.db.global = VuloClassicUIDB.global
    ns.db.char   = VuloClassicUICharDB

    ns:MigrateLegacyDBs()
end

function ns:LoadProfile(profileName)
    local profileData = VuloClassicUIDB.profiles[profileName]
    if not profileData then
        ns:Print(L["|cffff5555Profile '%s' does not exist.|r"], profileName)
        return false
    end

    profileData = ns:ApplyDefaults(profileData, ns.defaults.profile)

    for key, mod in pairs(ns.modules or {}) do
        profileData.modules[key] = ns:ApplyDefaults(
            profileData.modules[key], mod.defaults or {}
        )
    end

    VuloClassicUIDB.profiles[profileName] = profileData
    VuloClassicUIDB.activeProfile = profileName

    ns.db = ns.db or {}
    ns.db.profile = profileData

    for key, mod in pairs(ns.modules or {}) do
        mod.db = profileData.modules[key]
    end

    -- theme color rides the profile — must run BEFORE modules paint anything
    if ns.ApplyThemeColor then ns:ApplyThemeColor() end

    return true
end

-- Mutates the ns.COLORS tables IN PLACE so modules holding a reference pick the color up; already-painted textures keep the old color until /reload.
function ns:ApplyThemeColor()
    local gs = ns.db and ns.db.profile and ns.db.profile.modules
        and ns.db.profile.modules.globalsettings
    local c = gs and gs.themeColor
    if not (c and c.r and c.g and c.b) then
        c = { r = 0.608, g = 0.424, b = 1.000 }
    end
    local A = ns.COLORS.accent
    A.r, A.g, A.b = c.r, c.g, c.b
    local D = ns.COLORS.accentDim
    D.r, D.g, D.b = c.r * 0.5, c.g * 0.47, c.b * 0.5
    if ns.C then
        ns.C.accent = string.format("|cff%02x%02x%02x",
            math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5),
            math.floor(c.b * 255 + 0.5))
        ns.PREFIX = ns.C.accent .. "VuloClassicUI|r"
    end
end

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

    for classKey, assigned in pairs(VuloClassicUIDB.classAssignments) do
        if assigned == name then
            VuloClassicUIDB.classAssignments[classKey] = nil
        end
    end
    if VuloClassicUICharDB and VuloClassicUICharDB.profileOverride == name then
        VuloClassicUICharDB.profileOverride = nil
    end

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
    if VuloClassicUICharDB and VuloClassicUICharDB.profileOverride == oldName then
        VuloClassicUICharDB.profileOverride = newName
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

-- Lives in the char SavedVariables and beats the class assignment at login.
function ns:AssignCharToProfile(profileName)
    if profileName and profileName ~= "" and not ns:ProfileExists(profileName) then
        return false
    end
    VuloClassicUICharDB.profileOverride = (profileName ~= "" and profileName) or nil
    return true
end

function ns:GetCharAssignment()
    return VuloClassicUICharDB and VuloClassicUICharDB.profileOverride
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

function ns:MigrateLegacyDBs()
    if ns.db.global.migratedLegacy then return end

    -- Import into the ACTIVE profile (what every mod.db is linked to), not Default. Runs after LoadProfile.
    local target = ns.db and ns.db.profile
    if not target or not target.modules then return end

    if VuloFontBarsDB and ns.modules.fontbars then
        local src = VuloFontBarsDB
        local dst = target.modules.fontbars
        if src.healthSize      then dst.healthSize      = src.healthSize end
        if src.powerSize       then dst.powerSize       = src.powerSize end
        if src.petFeedbackSize then dst.petFeedbackSize = src.petFeedbackSize end
        if src.onlyTheseBars ~= nil then dst.onlyTheseBars = src.onlyTheseBars end
        ns:Print(L["Settings imported from VuloFontBars."])
    end

    if ArenaEnemyEditDB and ns.modules.arenaframes then
        local src = ArenaEnemyEditDB
        local dst = target.modules.arenaframes
        if src.pos        then dst.pos        = src.pos end
        if src.scale      then dst.scale      = src.scale end
        if src.healthSize then dst.healthSize = src.healthSize end
        if src.powerSize  then dst.powerSize  = src.powerSize end
        ns:Print(L["Settings imported from ArenaEnemyEdit."])
    end

    if BetterBlizzQueueDB and ns.modules.queuetimer then
        local src = BetterBlizzQueueDB
        local dst = target.modules.queuetimer
        if src.queueTimerAudio   ~= nil then dst.queueTimerAudio   = src.queueTimerAudio end
        if src.queueTimerWarning ~= nil then dst.queueTimerWarning = src.queueTimerWarning end
        if src.hideOtherTimers   ~= nil then dst.hideOtherTimers   = src.hideOtherTimers end
        ns:Print(L["Settings imported from BetterBlizzQueue."])
    end

    if idTipConfig and ns.modules.tooltipids then
        local src = idTipConfig
        local dst = target.modules.tooltipids
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

-- One-time migration: "targetframe" + "elitevuloframe" merged into "unitframes". Must run before the active profile loads.
function ns:MigrateUnitFramesMerge()
    -- profiles live account-wide, so one account-wide flag guards all of them
    if not VuloClassicUIDB.global.migratedUnitFrames then
        for _, profile in pairs(VuloClassicUIDB.profiles or {}) do
            local m = profile.modules
            if m and (m.targetframe or m.elitevuloframe) and not m.unitframes then
                local uf = {}
                local tf, el = m.targetframe, m.elitevuloframe
                if tf then
                    for _, k in ipairs({ "realHealth", "threatNumeric", "threatGlow",
                                         "rareElite", "classIcon", "focus" }) do
                        if tf[k] ~= nil then uf[k] = tf[k] end
                    end
                end
                if el and el.style ~= nil then uf.playerStyle = el.style end
                -- on if EITHER old module was on; elite border off alone only drops the dragon
                local tfOn = not tf or tf.enabled ~= false
                local elOn = not el or el.enabled ~= false
                uf.enabled = tfOn or elOn
                if not elOn then uf.playerStyle = "off" end
                m.unitframes = uf
            end
        end
        VuloClassicUIDB.global.migratedUnitFrames = true
    end

    -- Needs its own per-char guard: the account flag above is set by whoever logs in first and would skip everyone else's override.
    if not VuloClassicUICharDB.migratedUnitFrames then
        local me = VuloClassicUICharDB.modEnabled
        if me and me.unitframes == nil then
            local t, e = me.targetframe, me.elitevuloframe
            if t ~= nil or e ~= nil then
                me.unitframes = not (t == false and e == false)
            end
        end
        VuloClassicUICharDB.migratedUnitFrames = true
    end
end

-- One-time migration: "buttonskin" + "darkmode" merged into "darkskin"; old Dark Mode settings become the "dm*" keys.
function ns:MigrateDarkSkinMerge()
    if VuloClassicUIDB.global.migratedDarkSkin then return end

    for _, profile in pairs(VuloClassicUIDB.profiles or {}) do
        local m = profile.modules
        if m and (m.buttonskin or m.darkmode) and not m.darkskin then
            local ds = {}
            local bs, dm = m.buttonskin, m.darkmode
            if bs then
                for _, k in ipairs({ "style", "waStyle", "skinPetStance", "skinBars",
                                     "barIconSize", "skinWeakAuras", "hideWABorder", "enabled" }) do
                    if bs[k] ~= nil then ds[k] = bs[k] end
                end
            end
            if dm then
                if dm.desaturate    ~= nil then ds.dmDesaturate    = dm.desaturate end
                if dm.color         ~= nil then ds.dmColor         = dm.color end
                if dm.unitframes    ~= nil then ds.dmUnitframes    = dm.unitframes end
                if dm.minimap       ~= nil then ds.dmMinimap       = dm.minimap end
                if dm.actionbars    ~= nil then ds.dmActionbars    = dm.actionbars end
                if dm.actionButtons ~= nil then ds.dmActionButtons = dm.actionButtons end
                if dm.bags          ~= nil then ds.dmBags          = dm.bags end
                -- dm.enabled is deliberately skipped: the real per-character on/off is carried over in MigrateDarkSkinPerChar.
            end
            m.darkskin = ds
        end
    end

    VuloClassicUIDB.global.migratedDarkSkin = true
end

-- Per-character half of the Dark Skin merge. Must run after LoadProfile so ns.db.profile is set.
function ns:MigrateDarkSkinPerChar()
    if VuloClassicUICharDB.migratedDarkSkin then return end
    local me = VuloClassicUICharDB.modEnabled
    if me then
        -- Only write when the char actually overrode one of the old modules; otherwise fall through to the profile default.
        if me.darkskin == nil and (me.buttonskin ~= nil or me.darkmode ~= nil) then
            local bsOn = (me.buttonskin ~= false)
            local dmOn = (me.darkmode == true)
            me.darkskin = bsOn or dmOn
        end
        if me.darkmode == true then
            local mods = ns.db and ns.db.profile and ns.db.profile.modules
            local ds = mods and mods.darkskin
            if ds then ds.darkMode = true end
        end
    end
    VuloClassicUICharDB.migratedDarkSkin = true
end

function ns:GetModuleDB(key)
    if not ns.db or not ns.db.profile then return nil end
    return ns.db.profile.modules[key]
end
