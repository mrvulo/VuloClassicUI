-- SavedVariables: VuloClassicUIDB holds global/profiles[name]/classAssignments/activeProfile; ns.db.profile points at the active profile.
local _, ns = ...
local L = ns.L

ns.defaults = {
    global = {
        debug = false,
        -- account-wide so layouts are shared across profiles and characters
        editLayouts = {},
        -- Vulslot's named snapshots. Account-wide for the same reason, and for
        -- a second one worth writing down: a new class profile is a DeepCopy of
        -- Default (see InitDB), so anything stored per profile is duplicated the
        -- first time each class logs in. Seven profiles held seven byte-identical
        -- copies of one 17 KB snapshot library -- 37 % of the saved file. The
        -- snapshots carry the class they were taken on and Vulslot warns on a
        -- mismatch, so they were never per-class data to begin with.
        vulslotProfiles = {},
        -- Fonts and custom colors are a LOOK, not a playstyle: account-wide on
        -- purpose, like the edit layouts above. Colors hold only overrides --
        -- an absent token means "client default".
        fonts = { font = "Expressway", outline = "NONE", gameText = false },
        classColors = {},
        powerColors = {},
        -- Per-profile hotkeys are account-wide bindings, not profile data.
        -- The key is the profile name; the value is WoW's binding token.
        profileKeybinds = {},
        -- Stable short button ids keep frame names valid even for old profiles
        -- with long or non-ASCII names.
        profileKeybindButtonIds = {},
        nextProfileKeybindButtonId = 0,
    },
    profile = {
        ui = {
            mainFramePos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
            -- Scale of the settings window alone, not the game's interface.
            mainFrameScale = 1,
        },
        editmode = {
            grid = { show = false, snap = true, size = 32 },
        },
        -- window-to-window pins: [childMoverKey] = { to, dx, dy } (Core/Mover.lua)
        moverLinks = {},
        moverSizeLinks = {},
        modules = {
            -- filled from mod.defaults at load
        },
    },
}

local DEFAULT_PROFILE = "Default"

-- Migrations report through this instead of printing: they run at ADDON_LOADED,
-- where a chat message can be scrolled away by the login sequence before anyone
-- reads it. Core/Init.lua empties the list at PLAYER_LOGIN.
ns.migrationNotes = ns.migrationNotes or {}
local function note(msg, ...)
    ns.migrationNotes[#ns.migrationNotes + 1] = { msg, ... }
end

-- Value equality, used to decide whether two same-named snapshots from two
-- profiles are the same snapshot. Order-independent: it compares keys, not the
-- order pairs() happened to hand them over in.
local function sameValue(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not sameValue(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- Stored schema version. Bump it and add an entry to MIGRATIONS whenever a
-- stored shape or a default VALUE changes.
--
-- Why this has to exist: saving strips anything equal to the current default,
-- so "the player deliberately chose this value" and "the player never touched
-- it" are indistinguishable afterwards. Change a default and everyone who had
-- picked that exact value silently moves with it. A numbered migration is the
-- only chance to tell the two apart - at the moment of the change, while the
-- old default is still known.
--
-- Before this there were five hand-written one-shot booleans, each with its own
-- account and per-character guard. Those stay as they are; they work and are
-- idempotent. New ones belong here instead.
--
-- Entries run in ascending order for every version above the stored one, and
-- receive nothing: they operate on the saved tables directly. An install that
-- has never been stamped is stamped at the current version WITHOUT running
-- anything -- a fresh install has no old shape to convert.
local SCHEMA = 4
local MIGRATIONS = {
    -- Vulslot's snapshot library moves from every account profile into global.
    --
    -- NOTHING IS DROPPED. Same name and same content across profiles collapses
    -- into one entry. Same name but DIFFERENT content keeps both: the second one
    -- is stored under "name (profile)", because the alternative is deciding for
    -- the player which of their two snapshots was the real one.
    [2] = function()
        local g = VuloClassicUIDB.global
        g.vulslotProfiles = g.vulslotProfiles or {}
        local lib = g.vulslotProfiles

        -- Deterministic order, so a re-run or a second install lands the same
        -- way instead of depending on pairs().
        local profileNames = {}
        for name in pairs(VuloClassicUIDB.profiles or {}) do
            profileNames[#profileNames + 1] = name
        end
        table.sort(profileNames)

        local moved, merged, renamed = 0, 0, 0
        for _, profName in ipairs(profileNames) do
            local prof = VuloClassicUIDB.profiles[profName]
            local vs   = prof and prof.modules and prof.modules.vulslot
            local old  = vs and vs.profiles
            if type(old) == "table" then
                local snapNames = {}
                for n in pairs(old) do snapNames[#snapNames + 1] = n end
                table.sort(snapNames)

                for _, snapName in ipairs(snapNames) do
                    local snap = old[snapName]
                    if type(snap) == "table" then
                        if lib[snapName] == nil then
                            lib[snapName] = snap
                            moved = moved + 1
                        elseif sameValue(lib[snapName], snap) then
                            merged = merged + 1
                        else
                            local alt, n = snapName .. " (" .. profName .. ")", 2
                            while lib[alt] ~= nil and not sameValue(lib[alt], snap) do
                                alt = snapName .. " (" .. profName .. " " .. n .. ")"
                                n = n + 1
                            end
                            if lib[alt] == nil then
                                lib[alt] = snap
                                renamed = renamed + 1
                            else
                                merged = merged + 1
                            end
                        end
                    end
                end
                vs.profiles = nil
            end
        end

        if moved + merged + renamed > 0 then
            note(L["Bar setups are now stored once for the whole account: %d kept, %d duplicates merged."],
                moved, merged)
            if renamed > 0 then
                note(L["%d snapshot(s) had the same name but different contents and were kept under a new name."],
                    renamed)
            end
        end
    end,

    -- Arena: racial, PvP trinket and the DR row shared no coordinate system. Each
    -- carried its own edge and its own X/Y offsets, so they were positioned by
    -- hand against each other; they are laid out as one strip now.
    --
    -- The side is the only choice worth carrying over, and only the trinket ever
    -- expressed one - the racial simply took the other edge. A stored trinket edge
    -- therefore becomes the strip's edge, and its former partner moves next to it,
    -- which is exactly what the strip is for. Everything else was a nudge around a
    -- collision that no longer exists, so the old keys are dropped rather than
    -- left behind as values nothing reads.
    --
    -- slotSpacing moves from 6 to 28 in the same release and is DELIBERATELY not
    -- stamped here, which is the one exception to the rule at the top of this
    -- block. The rule protects a value the player chose and watched work. This
    -- one never worked: the arena layout hooks were installed against globals
    -- that do not exist yet at login, so the flag was set and the hooks never
    -- were, and no spacing this module stored has ever moved a frame. There is
    -- no observed behaviour to preserve, so everyone gets the new default.
    [3] = function()
        local DEAD = {
            "trinketAnchor", "trinketOffsetX", "trinketOffsetY",
            "drAnchor", "drOffsetX", "drOffsetY",
            "racialOffsetX", "racialOffsetY",
        }
        local moved = 0
        for _, prof in pairs(VuloClassicUIDB.profiles or {}) do
            local a = prof.modules and prof.modules.arenaframes
            if type(a) == "table" then
                if a.iconSide == nil and (a.trinketAnchor == "LEFT" or a.trinketAnchor == "RIGHT") then
                    a.iconSide = a.trinketAnchor
                    moved = moved + 1
                end
                for i = 1, #DEAD do a[DEAD[i]] = nil end
            end
        end
        if moved > 0 then
            note(L["Arena: racial, PvP trinket and the DR row now share one icon strip; your chosen side was kept."])
        end
    end,

    -- The power bar ships OFF from now on. For an install that already exists
    -- that changes nothing: the switch was on while its owner set their interface
    -- up, and they have watched the bar work ever since -- which is precisely the
    -- value the rule at the top of this block protects, whether or not they ever
    -- touched a switch to get it.
    --
    -- Writing the explicit true is what makes it hold. With the default now
    -- false, a stored true is no longer equal to the default and stops being
    -- stripped out on save; leaving the key absent would hand the profile the new
    -- default at the next login and the bar would vanish.
    --
    -- A profile with no power bar table at all gets one: no table means nothing
    -- was ever changed about the bar, which is the case where it has been ON the
    -- whole time. A fresh install never reaches this at all -- it is stamped
    -- current without running anything (see the note above runMigrations).
    [4] = function()
        for _, prof in pairs(VuloClassicUIDB.profiles or {}) do
            if type(prof.modules) == "table" then
                local p = prof.modules.powerbar
                if type(p) == "table" then
                    if p.enabled == nil then p.enabled = true end
                else
                    prof.modules.powerbar = { enabled = true }
                end
            end
        end
    end,
}

-- A database that has never been written carries no profile with module
-- settings in it. Anything that has been played with does -- that is the only
-- tell available, and it is enough for the question below.
local function looksUsed()
    for _, prof in pairs(VuloClassicUIDB.profiles or {}) do
        if type(prof) == "table" and type(prof.modules) == "table"
            and next(prof.modules) then
            return true
        end
    end
    return false
end

local function runMigrations()
    local g = VuloClassicUIDB.global
    local from = tonumber(g.schema)
    if not from then
        -- No stamp means one of TWO things that need opposite treatment: a fresh
        -- install, where there is nothing to migrate -- or an install from BEFORE
        -- the stamp existed, where everything is still to be migrated. Both used
        -- to be stamped at the current schema and skipped, so the older one lost
        -- every migration in silence, bar setups in their old place included.
        -- That is exactly the kind of loss the promise at the top of this file
        -- rules out.
        --
        -- Starting such an install at zero is safe: the migrations are written to
        -- survive a re-run (see the note on deterministic order in [2]), and an
        -- install without a stamp is by definition older than all of them.
        if not looksUsed() then
            g.schema = SCHEMA
            VuloClassicUICharDB.schema = VuloClassicUICharDB.schema or SCHEMA
            return
        end
        from = 0
        g.schema = 0
    end
    if from >= SCHEMA then return end
    for v = from + 1, SCHEMA do
        local fn = MIGRATIONS[v]
        if fn then
            local ok, err = pcall(fn)
            if not ok then
                ns:Print(L["|cffff5555Settings migration %s failed:|r %s"], tostring(v), tostring(err))
                return                 -- stop at the first failure; schema stays put
            end
        end
        g.schema = v
    end
    VuloClassicUICharDB.schema = SCHEMA
end

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

    -- The logout scrub parks its count here; saying it out loud is the whole
    -- point — a player whose settings kept resetting needs to see the cause.
    local scrubbed = tonumber(VuloClassicUIDB.global.scrubbedNonFinite)
    if scrubbed and scrubbed > 0 then
        note(L["%d broken numeric values were removed from the settings so they can be saved again."], scrubbed)
        VuloClassicUIDB.global.scrubbedNonFinite = nil
    end

    if not VuloClassicUIDB.profiles[DEFAULT_PROFILE] then
        VuloClassicUIDB.profiles[DEFAULT_PROFILE] = {}
    end
    VuloClassicUIDB.profiles[DEFAULT_PROFILE] = ns:ApplyDefaults(
        VuloClassicUIDB.profiles[DEFAULT_PROFILE], ns.defaults.profile
    )

    ns:MigrateUnitFramesMerge()
    ns:MigrateDarkSkinMerge()
    runMigrations()

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

    -- Last, and it has to be: it needs ns.db.global and ns.db.char, and it has
    -- to happen before any module is enabled. See Trinkets/TrinketsStore.lua.
    if ns.BindTrinketStore then ns:BindTrinketStore() end
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
    -- hard type check: an imported profile may carry arbitrary values here
    if not (c and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number") then
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
    if ns.GetProfileKeybind and ns:GetProfileKeybind(name)
       and InCombatLockdown and InCombatLockdown() then
        return false, L["Not possible in combat."]
    end

    VuloClassicUIDB.profiles[name] = nil
    if ns.RemoveProfileKeybind then ns:RemoveProfileKeybind(name) end

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
    if ns.GetProfileKeybind and ns:GetProfileKeybind(oldName)
       and InCombatLockdown and InCombatLockdown() then
        return false, L["Not possible in combat."]
    end
    if not newName or newName == "" then return false, L["Name cannot be empty."] end
    if ns:ProfileExists(newName) then return false, L["New name already exists."] end

    VuloClassicUIDB.profiles[newName] = VuloClassicUIDB.profiles[oldName]
    VuloClassicUIDB.profiles[oldName] = nil
    if ns.RenameProfileKeybind then ns:RenameProfileKeybind(oldName, newName) end

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
    local prev = ns:GetActiveProfileName()
    if prev == name then return true end

    -- an imported profile can hold junk that makes LoadProfile throw halfway
    -- (activeProfile already flipped, mod.db not repointed) — roll back
    local ok, err = pcall(ns.LoadProfile, ns, name)
    if not ok then
        pcall(ns.LoadProfile, ns, prev)
        ns:Print(L["|cffff5555Profile '%s' could not be loaded:|r %s"], name, tostring(err))
        return false
    end
    -- The new profile carries its own talent overrides; the ones from the old
    -- profile are still sitting in the live settings until these run.
    if ns.ApplyOverrides and ns.ActiveTalentGroup then
        pcall(ns.ApplyOverrides, ns, ns:ActiveTalentGroup())
    end
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

-- ---------------------------------------------------------------------------
-- Profile keybinds
--
-- Bindings are intentionally account-wide. A binding activates a named profile,
-- then offers the normal reload prompt; no protected actionbar or frame work is
-- attempted while in combat. Frame names use stable short ids so old, long or
-- non-ASCII profile names cannot create invalid or colliding global frame names.
local PROFILE_BIND_PREFIX = "VCUIProfileBind_"
local profileBindButtons = {}

function ns:GetProfileKeybindValues()
    local values = { { value = "", text = L["- none -"] } }
    for i = 1, 12 do
        values[#values + 1] = { value = "F" .. i, text = "F" .. i }
    end
    for _, mod in ipairs({ "SHIFT", "CTRL", "ALT" }) do
        for i = 1, 12 do
            local key = mod .. "-F" .. i
            values[#values + 1] = { value = key, text = key }
        end
    end
    return values
end

local function profileBindButtonName(profileName)
    local g = VuloClassicUIDB.global
    g.profileKeybindButtonIds = g.profileKeybindButtonIds or {}
    local id = g.profileKeybindButtonIds[profileName]
    if not id then
        g.nextProfileKeybindButtonId = (tonumber(g.nextProfileKeybindButtonId) or 0) + 1
        id = g.nextProfileKeybindButtonId
        g.profileKeybindButtonIds[profileName] = id
    end
    return PROFILE_BIND_PREFIX .. tostring(id)
end

local function canChangeProfileBinding()
    return not (InCombatLockdown and InCombatLockdown())
end

local function showProfileReloadPrompt()
    if StaticPopupDialogs and StaticPopupDialogs["VCUI_PROFILE_RELOAD"] then
        StaticPopup_Show("VCUI_PROFILE_RELOAD")
    else
        ns:Print(L["Profile changed. Use /reload when you are out of combat."])
    end
end

local function ensureProfileBindButton(profileName)
    local btn = profileBindButtons[profileName]
    if btn then return btn end

    btn = CreateFrame("Button", profileBindButtonName(profileName), UIParent)
    btn:RegisterForClicks("AnyUp")
    btn:Hide()
    btn._profileName = profileName
    btn:SetScript("OnClick", function(self)
        local name = self._profileName
        if not canChangeProfileBinding() then
            ns:Print(L["Not possible in combat."])
            return
        end
        if ns:GetActiveProfileName() == name then return end
        if ns:SwitchProfile(name) then showProfileReloadPrompt() end
    end)
    profileBindButtons[profileName] = btn
    return btn
end

function ns:GetProfileKeybind(profileName)
    local g = VuloClassicUIDB and VuloClassicUIDB.global
    local bindings = g and g.profileKeybinds
    return bindings and bindings[profileName] or nil
end

function ns:SetProfileKeybind(profileName, key)
    if not ns:ProfileExists(profileName) then return false, L["Profile does not exist."] end
    if not canChangeProfileBinding() then return false, L["Not possible in combat."] end

    local g = VuloClassicUIDB.global
    g.profileKeybinds = g.profileKeybinds or {}

    -- One physical key must have one owner. Leaving the old owner in the table
    -- would make the winner depend on pairs() order after the next login.
    if key and key ~= "" then
        for otherName, otherKey in pairs(g.profileKeybinds) do
            if otherName ~= profileName and otherKey == key then
                local otherBtn = ensureProfileBindButton(otherName)
                ClearOverrideBindings(otherBtn)
                g.profileKeybinds[otherName] = nil
            end
        end
    end

    local btn = ensureProfileBindButton(profileName)
    ClearOverrideBindings(btn)

    if key and key ~= "" then
        SetOverrideBindingClick(btn, true, key, btn:GetName())
        g.profileKeybinds[profileName] = key
    else
        g.profileKeybinds[profileName] = nil
    end
    return true
end

function ns:RestoreProfileKeybinds()
    if not canChangeProfileBinding() then return end
    local g = VuloClassicUIDB and VuloClassicUIDB.global
    local bindings = g and g.profileKeybinds
    if type(bindings) ~= "table" then return end
    local names, claimed = {}, {}
    for profileName in pairs(bindings) do names[#names + 1] = profileName end
    table.sort(names)
    for _, profileName in ipairs(names) do
        local key = bindings[profileName]
        if ns:ProfileExists(profileName) and type(key) == "string" and key ~= "" and not claimed[key] then
            local btn = ensureProfileBindButton(profileName)
            ClearOverrideBindings(btn)
            SetOverrideBindingClick(btn, true, key, btn:GetName())
            claimed[key] = true
        else
            bindings[profileName] = nil
        end
    end
end

function ns:RemoveProfileKeybind(profileName)
    local g = VuloClassicUIDB and VuloClassicUIDB.global
    if g and g.profileKeybinds then g.profileKeybinds[profileName] = nil end
    if g and g.profileKeybindButtonIds then g.profileKeybindButtonIds[profileName] = nil end
    local btn = profileBindButtons[profileName]
    if btn and canChangeProfileBinding() then ClearOverrideBindings(btn) end
    profileBindButtons[profileName] = nil
end

function ns:RenameProfileKeybind(oldName, newName)
    local g = VuloClassicUIDB and VuloClassicUIDB.global
    local bindings = g and g.profileKeybinds
    if not bindings then return end
    local key = bindings[oldName]
    if not key then return end

    local bindId = g.profileKeybindButtonIds and g.profileKeybindButtonIds[oldName]
    local btn = profileBindButtons[oldName]
    if btn and canChangeProfileBinding() then ClearOverrideBindings(btn) end
    profileBindButtons[oldName] = nil
    bindings[oldName] = nil
    if g.profileKeybindButtonIds then g.profileKeybindButtonIds[oldName] = nil end

    bindings[newName] = key
    if bindId then g.profileKeybindButtonIds[newName] = bindId end
    if btn then
        btn._profileName = newName
        profileBindButtons[newName] = btn
        if canChangeProfileBinding() then
            SetOverrideBindingClick(btn, true, key, btn:GetName())
        end
    else
        self:SetProfileKeybind(newName, key)
    end
end

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

-- ---------------------------------------------------------------------------
-- Slim SavedVariables + profile strings

-- ns.defaults.profile plus every registered module's defaults, as one tree
local function fullProfileDefaults()
    local d = ns:DeepCopy(ns.defaults.profile)
    d.modules = d.modules or {}
    for key, mod in pairs(ns.modules or {}) do
        d.modules[key] = ns:DeepCopy(mod.defaults or {})
    end
    return d
end

-- Removes every value equal to its default; ApplyDefaults refills the gaps on
-- the next load, so this is lossless. Only keys present in the defaults tree
-- are touched — user data (entries, custom categories) is never stripped.
local function stripDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then return end
    for k, dv in pairs(defaults) do
        local tv = target[k]
        if type(dv) == "table" then
            if type(tv) == "table" then
                stripDefaults(tv, dv)
                if next(tv) == nil then target[k] = nil end
            end
        elseif tv == dv then
            target[k] = nil
        end
    end
end

function ns:StripProfileDefaults()
    if not (VuloClassicUIDB and VuloClassicUIDB.profiles) then return end
    local defs = fullProfileDefaults()
    for _, profile in pairs(VuloClassicUIDB.profiles) do
        stripDefaults(profile, defs)
    end
end

-- One non-finite number poisons the WHOLE account: the client serializes NaN
-- and ±inf as tokens that are not valid Lua literals, the next load of the
-- SavedVariables file fails as a unit, the client shelves it as .bak and every
-- setting reverts to defaults. That is exactly the picture reported from the
-- Titan client (3.80.2) after edit-mode sessions: save confirmed in-session,
-- factory state after every /reload. The scrub runs at logout, BEFORE the file
-- is written, so a bad value from any source (a division by a zero scale is
-- the classic one) can never cost the account its settings. Values are removed
-- rather than zeroed: ApplyDefaults refills the gap with the default on the
-- next load, which is the honest outcome for a number that never meant
-- anything. Keys are removed with their value — a NaN KEY breaks the file
-- just the same.
local function scrubNonFinite(t, seen)
    if type(t) ~= "table" or seen[t] then return 0 end
    seen[t] = true
    local removed = 0
    local badKeys
    for k, v in pairs(t) do
        -- Keys: only ±inf is possible here. A NaN KEY cannot exist in a Lua
        -- table (inserting one throws), and deleting one would throw too
        -- ("table index is NaN") -- so it is deliberately not tested for.
        if type(k) == "number" and (k == math.huge or k == -math.huge) then
            badKeys = badKeys or {}
            badKeys[#badKeys + 1] = k
        elseif type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then
            badKeys = badKeys or {}
            badKeys[#badKeys + 1] = k
        elseif type(v) == "table" then
            removed = removed + scrubNonFinite(v, seen)
        end
    end
    if badKeys then
        for i = 1, #badKeys do t[badKeys[i]] = nil end
        removed = removed + #badKeys
    end
    return removed
end

function ns:ScrubSavedVariables()
    local n = 0
    local seen = {}
    n = n + scrubNonFinite(VuloClassicUIDB, seen)
    n = n + scrubNonFinite(VuloClassicUICharDB, seen)
    if n > 0 and VuloClassicUIDB and VuloClassicUIDB.global then
        -- Printing here would vanish with the session; the count is parked and
        -- reported at the NEXT login through the migration-notes channel, so
        -- the player (and a bug report) can see that broken values existed.
        VuloClassicUIDB.global.scrubbedNonFinite =
            (VuloClassicUIDB.global.scrubbedNonFinite or 0) + n
    end
    return n
end

-- at logout the session is over — stripping the live tables is safe
local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    ns:ScrubSavedVariables()
    ns:StripProfileDefaults()
    if ns.UnbindTrinketStore then ns:UnbindTrinketStore() end
end)

function ns:ResetProfile(name)
    name = name or ns:GetActiveProfileName()
    if not ns:ProfileExists(name) then return false, L["Profile does not exist."] end
    VuloClassicUIDB.profiles[name] = ns:DeepCopy(ns.defaults.profile)
    if ns:GetActiveProfileName() == name then
        ns:LoadProfile(name)
    end
    return true
end

-- Profile strings: own compact serializer + base64, no external libs. Values
-- equal to the defaults are stripped first, so the strings stay short.
local SERIALIZABLE = { number = true, boolean = true, string = true, table = true }

local function serialize(v, out)
    local t = type(v)
    if t == "number" then
        -- NaN/Inf stringify unparseably and would brick the whole string
        if v ~= v or v == math.huge or v == -math.huge then v = 0 end
        out[#out + 1] = "n" .. tostring(v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "t" or "f"
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            if SERIALIZABLE[type(k)] and SERIALIZABLE[type(val)] then
                serialize(k, out)
                serialize(val, out)
            end
        end
        out[#out + 1] = "}"
    end
end

-- returns value, nextPos; nextPos == nil signals a corrupt stream (a plain
-- nil value is legal for booleans-false keys, so nil alone is not the marker)
local function deserialize(str, pos)
    local c = str:sub(pos, pos)
    if c == "t" then return true, pos + 1 end
    if c == "f" then return false, pos + 1 end
    if c == "n" then
        local semi = str:find(";", pos + 1, true)
        if not semi then return nil, nil end
        local num = tonumber(str:sub(pos + 1, semi - 1))
        if num == nil then return nil, nil end
        return num, semi + 1
    end
    if c == "s" then
        local colon = str:find(":", pos + 1, true)
        if not colon then return nil, nil end
        local len = tonumber(str:sub(pos + 1, colon - 1))
        if not len or len < 0 then return nil, nil end
        local s = str:sub(colon + 1, colon + len)
        if #s ~= len then return nil, nil end
        return s, colon + len + 1
    end
    if c == "{" then
        local tbl = {}
        pos = pos + 1
        while true do
            if str:sub(pos, pos) == "}" then return tbl, pos + 1 end
            if pos > #str then return nil, nil end
            local k, v
            k, pos = deserialize(str, pos)
            if pos == nil then return nil, nil end
            v, pos = deserialize(str, pos)
            if pos == nil then return nil, nil end
            if k ~= nil then tbl[k] = v end
        end
    end
    return nil, nil
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64REV

local function b64encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=")
            .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function b64decode(s)
    if not B64REV then
        B64REV = {}
        for i = 1, 64 do B64REV[B64:byte(i)] = i - 1 end
    end
    local out = {}
    for i = 1, #s, 4 do
        local c1, c2, c3, c4 = s:byte(i, i + 3)
        local v1, v2 = c1 and B64REV[c1], c2 and B64REV[c2]
        if not (v1 and v2) then return nil end
        local v3 = c3 and B64REV[c3]   -- nil on '=' padding
        local v4 = c4 and B64REV[c4]
        local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if v3 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if v4 then out[#out + 1] = string.char(n % 256) end
    end
    return table.concat(out)
end

local PROFILE_STRING_PREFIX  = "!VCUI1"   -- legacy: serializer + plain base64
local PROFILE_STRING_PREFIX2 = "!VCUI2"   -- serializer + deflate + printable encoding
local LibDeflate = _G.LibStub and _G.LibStub:GetLibrary("LibDeflate", true)

-- the name travels inside the string: strip UI escapes/control chars and
-- cap the length before it becomes a table key and dropdown label
local function sanitizeProfileName(raw)
    local base = type(raw) == "string" and raw or ""
    base = base:gsub("|", ""):gsub("%c", ""):sub(1, 48):match("^%s*(.-)%s*$")
    if base == "" then base = L["Imported"] end
    return base
end

-- What a profile carries besides .modules; "interface layout" in the export UI.
local PROFILE_LAYOUT_KEYS = { "ui", "editmode", "moverLinks", "moverSizeLinks" }

-- opts: nil = the whole profile, the classic string (version 1).
--   { modules = set-of-keys|nil, layout = bool, overrides = bool, look = bool }
-- Any subsetting turns the string into VERSION 2: an old client would have
-- built a holes-filled-with-defaults profile out of a subset, silently wrong,
-- so it must refuse instead. The look block (account-wide fonts and colors)
-- rides along version-neutrally -- an old importer ignores fields it does not
-- know, and getting the profile without the look is the right degradation.
-- Packing a table into a string people can paste is no longer the profile's
-- private business -- the bar setups share the same way -- so the packing lives
-- here once instead of being copied.
--
-- Compressed strings are a fraction of the size (they fit in a chat message);
-- the plain base64 path stays as the fallback so a missing library can never
-- take an export button with it.
--
-- BOTH prefixes belong to the CALLER, and that is the point: a bar-setup string
-- and a profile string must never be mistakable for one another, so each
-- feature brings its own pair rather than sharing one namespace.
function ns:EncodeShareString(plainPrefix, packedPrefix, payload)
    local out = {}
    serialize(payload, out)
    local raw = table.concat(out)
    if LibDeflate then
        local packed  = LibDeflate:CompressDeflate(raw)
        local encoded = packed and LibDeflate:EncodeForPrint(packed)
        if encoded then return packedPrefix .. encoded end
    end
    return plainPrefix .. b64encode(raw)
end

-- The other half. Deliberately hands back a REASON CODE rather than a sentence:
-- the framework does not know what the caller was expecting, and "this is not a
-- bar setup string" has to be said by whoever asked for one.
--   nil, "foreign"  -- neither prefix matched; somebody else's string
--   nil, "damaged"  -- our prefix, but it does not survive unpacking
function ns:DecodeShareString(plainPrefix, packedPrefix, text)
    text = tostring(text or ""):gsub("%s+", "")
    local raw
    if text:sub(1, #packedPrefix) == packedPrefix then
        -- A missing library counts as damage, not as a foreign string: the
        -- prefix already proved whose string this is.
        if not LibDeflate then return nil, "damaged" end
        local packed = LibDeflate:DecodeForPrint(text:sub(#packedPrefix + 1))
        raw = packed and LibDeflate:DecompressDeflate(packed)
    elseif text:sub(1, #plainPrefix) == plainPrefix then
        raw = b64decode(text:sub(#plainPrefix + 1))
    else
        return nil, "foreign"
    end
    if not raw then return nil, "damaged" end
    local payload, pos = deserialize(raw, 1)
    if pos == nil or type(payload) ~= "table" then return nil, "damaged" end
    return payload
end

function ns:ExportProfileString(name, opts)
    name = name or ns:GetActiveProfileName()
    local profile = VuloClassicUIDB.profiles and VuloClassicUIDB.profiles[name]
    if not profile then return nil end
    local copy = ns:DeepCopy(profile)
    stripDefaults(copy, fullProfileDefaults())

    local partial = false
    if opts then
        if opts.modules then
            partial = true
            for k in pairs(copy.modules or {}) do
                if not opts.modules[k] then copy.modules[k] = nil end
            end
        end
        if opts.layout == false then
            partial = true
            for _, k in ipairs(PROFILE_LAYOUT_KEYS) do copy[k] = nil end
        end
        if opts.overrides == false then
            partial = true
            copy.overrideGroups = nil
        end
    end

    local payload = { v = partial and 2 or 1, n = name, d = copy }
    if partial then payload.p = true end
    if opts and opts.look and ns.db and ns.db.global then
        payload.g = ns:DeepCopy({
            fonts       = ns.db.global.fonts,
            classColors = ns.db.global.classColors,
            powerColors = ns.db.global.powerColors,
        })
    end
    return ns:EncodeShareString(PROFILE_STRING_PREFIX, PROFILE_STRING_PREFIX2, payload)
end

-- Decodes a profile string WITHOUT importing anything -- the import preview
-- is built from this. Returns payload + summary, or nil + error text.
function ns:DecodeProfileString(text)
    text = tostring(text or ""):gsub("%s+", "")
    local raw
    if text:sub(1, #PROFILE_STRING_PREFIX2) == PROFILE_STRING_PREFIX2 then
        -- Missing library counts as damage, not as a foreign string: the
        -- prefix already proved whose string this is.
        if not LibDeflate then return nil, L["The profile string is damaged."] end
        local packed = LibDeflate:DecodeForPrint(text:sub(#PROFILE_STRING_PREFIX2 + 1))
        raw = packed and LibDeflate:DecompressDeflate(packed)
    elseif text:sub(1, #PROFILE_STRING_PREFIX) == PROFILE_STRING_PREFIX then
        raw = b64decode(text:sub(#PROFILE_STRING_PREFIX + 1))
    else
        return nil, L["This is not a VuloClassicUI profile string."]
    end
    if not raw then return nil, L["The profile string is damaged."] end
    local payload, pos = deserialize(raw, 1)
    if pos == nil or type(payload) ~= "table"
        or (payload.v ~= 1 and payload.v ~= 2)
        or type(payload.d) ~= "table" then
        return nil, L["The profile string is damaged."]
    end

    local d = payload.d
    local moduleKeys = {}
    if type(d.modules) == "table" then
        for k, v in pairs(d.modules) do
            if type(k) == "string" and type(v) == "table" then
                moduleKeys[#moduleKeys + 1] = k
            end
        end
    end
    table.sort(moduleKeys)
    local hasLayout = false
    for _, k in ipairs(PROFILE_LAYOUT_KEYS) do
        if d[k] ~= nil then hasLayout = true; break end
    end
    return payload, {
        name         = sanitizeProfileName(payload.n),
        partial      = payload.p and true or false,
        moduleKeys   = moduleKeys,
        hasLayout    = hasLayout,
        hasOverrides = d.overrideGroups ~= nil,
        hasLook      = type(payload.g) == "table",
    }
end

-- Creates a NEW profile from a decoded payload (never merges into an existing
-- one); returns the profile name, or nil + error text. opts narrows what the
-- string may bring in:
--   { name = string?, modules = set-of-keys?, layout = bool?, overrides = bool?, look = bool? }
-- nil opts = take everything, the classic behavior. Dropping content at import
-- time flips the build to the partial rule below, for the same reason the
-- exporter does: holes filled with defaults would hand the importer a profile
-- that silently reset every setting the unticked part carried.
function ns:ImportProfilePayload(payload, opts)
    if type(payload) ~= "table" or type(payload.d) ~= "table" then
        return nil, L["The profile string is damaged."]
    end
    local data = ns:DeepCopy(payload.d)
    local partial = payload.p and true or false

    -- The pipeline exists to accept strings from strangers, so every slot a
    -- crafted payload can reach is type-checked before it is iterated or
    -- stored -- junk here would either error the import click or detonate
    -- later at profile switch.
    if data.modules ~= nil and type(data.modules) ~= "table" then data.modules = nil end
    if type(data.modules) == "table" then
        for k, v in pairs(data.modules) do
            if type(k) ~= "string" or type(v) ~= "table" then data.modules[k] = nil end
        end
    end
    for _, k in ipairs(PROFILE_LAYOUT_KEYS) do
        if data[k] ~= nil and type(data[k]) ~= "table" then data[k] = nil end
    end
    if data.overrideGroups ~= nil and type(data.overrideGroups) ~= "table" then
        data.overrideGroups = nil
    end

    if opts then
        if opts.modules and type(data.modules) == "table" then
            for k in pairs(data.modules) do
                if not opts.modules[k] then data.modules[k] = nil; partial = true end
            end
        end
        if opts.layout == false then
            for _, k in ipairs(PROFILE_LAYOUT_KEYS) do
                if data[k] ~= nil then data[k] = nil; partial = true end
            end
        end
        if opts.overrides == false and data.overrideGroups ~= nil then
            data.overrideGroups = nil
            partial = true
        end
    end

    local base = sanitizeProfileName(opts and opts.name or payload.n)
    local name = base
    local i = 2
    while ns:ProfileExists(name) do
        name = base .. " " .. i
        i = i + 1
    end

    -- Partial strings merge onto a COPY of the active profile:
    -- filling the gaps with defaults instead would hand the importer a profile
    -- that silently dropped every setting the string did not carry.
    if partial then
        local active = VuloClassicUIDB.profiles[ns:GetActiveProfileName()]
        local merged = active and ns:DeepCopy(active) or {}
        merged.modules = merged.modules or {}
        for k, v in pairs(data.modules or {}) do merged.modules[k] = v end
        for _, k in ipairs(PROFILE_LAYOUT_KEYS) do
            if data[k] ~= nil then merged[k] = data[k] end
        end
        if data.overrideGroups ~= nil then merged.overrideGroups = data.overrideGroups end
        data = merged
    end

    -- defaults are refilled by LoadProfile when the profile gets activated
    VuloClassicUIDB.profiles[name] = data

    -- Account-wide look data travels outside the profile; its presence in the
    -- string (plus the preview checkbox, when the UI offered one) is the
    -- consent to apply it right away. Same rule as
    -- ApplyThemeColor: an imported string may carry ARBITRARY values, and a
    -- malformed color entry written into the ns.CLASS_COLORS book would break
    -- every consumer and re-poison itself from the SV at each login -- so only
    -- well-formed entries get in, everything else is dropped.
    if (not opts or opts.look ~= false)
        and type(payload.g) == "table" and ns.db and ns.db.global then
        local g = ns.db.global
        local function cleanColors(t)
            if type(t) ~= "table" then return nil end
            local out = {}
            for k, c in pairs(t) do
                if type(k) == "string" and type(c) == "table"
                   and type(c.r) == "number" and type(c.g) == "number"
                   and type(c.b) == "number" then
                    out[k] = {
                        r = math.min(1, math.max(0, c.r)),
                        g = math.min(1, math.max(0, c.g)),
                        b = math.min(1, math.max(0, c.b)),
                    }
                end
            end
            return out
        end
        local fonts = payload.g.fonts
        if type(fonts) == "table" and type(g.fonts) == "table" then
            if type(fonts.font) == "string" then g.fonts.font = fonts.font end
            if fonts.outline == "NONE" or fonts.outline == "OUTLINE"
               or fonts.outline == "THICKOUTLINE" then
                g.fonts.outline = fonts.outline
            end
            g.fonts.gameText = fonts.gameText and true or false
        end
        local cc = cleanColors(payload.g.classColors)
        if cc then g.classColors = cc end
        local pc = cleanColors(payload.g.powerColors)
        if pc then g.powerColors = pc end
        if ns.ApplyLookSettings then ns.ApplyLookSettings() end
    end
    return name
end

-- The classic one-call entry: decode + import everything the string carries.
function ns:ImportProfileString(text)
    local payload, err = ns:DecodeProfileString(text)
    if not payload then return nil, err end
    return ns:ImportProfilePayload(payload)
end
