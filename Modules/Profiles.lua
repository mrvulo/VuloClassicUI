-- =========================================================
-- VuloClassicUI / Modules / Profiles
-- Profile manager as its own "module" in the sidebar.
-- Allows: switch, create, copy, delete, rename profiles, assign per class.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("profiles", {
    name        = "Profiles",
    group       = "Account",
    description = "Manage profiles with different settings. A default profile can be assigned per class and is loaded automatically on login.",
    noToggle    = true,  -- no power button in the sidebar
    defaults    = {
        enabled = true,
    },
})

-- This "module" has no lifecycle logic of its own
function mod:OnEnable() end

-- =========================================================
-- Data for UI
-- =========================================================
local CLASS_LIST = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local CLASS_LABELS = {
    WARRIOR = L["Warrior"], PALADIN = L["Paladin"], HUNTER = L["Hunter"], ROGUE = L["Rogue"],
    PRIEST = L["Priest"], SHAMAN = L["Shaman"], MAGE = L["Mage"], WARLOCK = L["Warlock"],
    DRUID = L["Druid"],
}

-- Buffers for UI input (not saved in the DB)
local newProfileNameBuffer = ""
local copyFromBuffer       = nil
local renameNewBuffer      = ""

-- Helper functions
local function getProfileValues()
    local values = {}
    for _, name in ipairs(ns:GetProfileNames()) do
        table.insert(values, { value = name, text = name })
    end
    return values
end

local function getProfileValuesWithNone()
    local values = { { value = "", text = L["- none -"] } }
    for _, name in ipairs(ns:GetProfileNames()) do
        table.insert(values, { value = name, text = name })
    end
    return values
end

local function refreshUI()
    if ns.UI and ns.UI.currentModule == "profiles" then
        ns.UI:BuildOptionsPage("profiles", "default")
    end
end

-- =========================================================
-- Options page
-- =========================================================
function mod:GetOptions()
    local items = {}
    local activeName = ns:GetActiveProfileName()
    local myClass    = ns:GetMyClassKey()

    -- =========================================================
    -- Section: Active Profile
    -- =========================================================
    table.insert(items, { type = "header", text = L["Active Profile"] })

    table.insert(items, {
        type = "desc",
        text = string.format(L["You are currently using: |cff9b6cff%s|r  (Class: %s)"],
            activeName, CLASS_LABELS[myClass] or myClass)
    })

    table.insert(items, {
        type = "dropdown", label = L["Switch Profile"],
        width = 220,
        values = getProfileValues(),
        get = function() return ns:GetActiveProfileName() end,
        set = function(_, v)
            ns:SwitchProfile(v)
            -- a pinned character profile would silently revert the switch at
            -- the next login — keep the pin in step with a manual switch
            if ns:GetCharAssignment() then ns:AssignCharToProfile(v) end
            refreshUI()
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

    -- =========================================================
    -- Section: Per-character assignment (beats the class assignment)
    -- =========================================================
    table.insert(items, { type = "header", text = L["Profile for this character"] })
    table.insert(items, {
        type = "desc",
        text = L["|cffaaaaaaPins a profile to THIS character only. At login it beats the class assignment and the account-wide selection - so every character can keep its own minimap, bars and window settings.|r"],
    })
    table.insert(items, {
        type = "dropdown", label = UnitName and UnitName("player") or L["This character"],
        width = 220,
        values = getProfileValuesWithNone(),
        get = function() return ns:GetCharAssignment() or "" end,
        set = function(_, v)
            ns:AssignCharToProfile(v)
            if v ~= "" and v ~= ns:GetActiveProfileName() then
                ns:SwitchProfile(v)
            end
            refreshUI()
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

    -- =========================================================
    -- Section: Per-class quick setup
    -- =========================================================
    table.insert(items, { type = "header", text = L["Per-class profile (quick setup)"] })
    table.insert(items, {
        type = "desc",
        text = L["|cffaaaaaaOne click: makes a profile named after your class (copied from the current one) and loads it for this class automatically. Run it once on each character — every class then keeps its own cooldown bars, frames and settings.|r"],
    })
    table.insert(items, {
        type = "button", primary = true, width = 320,
        label = string.format(L["Set up a %s profile"], CLASS_LABELS[myClass] or myClass),
        onClick = function()
            local pname = CLASS_LABELS[myClass] or myClass
            if not ns:ProfileExists(pname) then
                ns:CreateProfile(pname, ns:GetActiveProfileName())
            end
            ns:SwitchProfile(pname)
            ns:AssignClassToProfile(myClass, pname)
            -- a character pin would override the class profile at login —
            -- the explicit class setup wins, so drop the pin
            ns:AssignCharToProfile(nil)
            ns:Print(L["'%s' is now the %s profile. |cffffff00/reload|r to apply."],
                pname, CLASS_LABELS[myClass] or myClass)
            refreshUI()
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

    -- =========================================================
    -- Section: Create Profile
    -- =========================================================
    table.insert(items, { type = "header", text = L["Create New Profile"] })

    table.insert(items, {
        type = "editbox", label = L["Name"],
        width = 220,
        get = function() return newProfileNameBuffer end,
        set = function(_, v) newProfileNameBuffer = v end,
    })

    table.insert(items, {
        type = "dropdown", label = L["Copy Settings From"],
        width = 220,
        values = (function()
            local v = { { value = "", text = L["- empty profile (defaults) -"] } }
            for _, name in ipairs(ns:GetProfileNames()) do
                table.insert(v, { value = name, text = name })
            end
            return v
        end)(),
        get = function() return copyFromBuffer or "" end,
        set = function(_, v) copyFromBuffer = (v ~= "" and v) or nil end,
    })

    table.insert(items, {
        type = "button", label = L["Create Profile"], width = 160,
        onClick = function()
            local name = (newProfileNameBuffer or ""):match("^%s*(.-)%s*$")
            if not name or name == "" then
                ns:Print(L["|cffff5555Please enter a name.|r"])
                return
            end
            local ok, err = ns:CreateProfile(name, copyFromBuffer)
            if not ok then
                ns:Print("|cffff5555%s|r", err or L["Error."])
            else
                newProfileNameBuffer = ""
                copyFromBuffer = nil
                refreshUI()
            end
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

    -- =========================================================
    -- Section: Manage Active Profile
    -- =========================================================
    table.insert(items, { type = "header", text = L["Manage Current Profile"] })

    table.insert(items, {
        type = "group", layout = "row", gap = 6,
        items = {
            {
                type = "editbox", label = L["Rename to"],
                width = 180,
                get = function() return renameNewBuffer end,
                set = function(_, v) renameNewBuffer = v end,
            },
            {
                type = "button", label = L["Rename"], width = 110,
                onClick = function()
                    local newName = (renameNewBuffer or ""):match("^%s*(.-)%s*$")
                    if not newName or newName == "" then
                        ns:Print(L["|cffff5555Please enter a new name.|r"])
                        return
                    end
                    local ok, err = ns:RenameProfile(ns:GetActiveProfileName(), newName)
                    if not ok then
                        ns:Print("|cffff5555%s|r", err or L["Error."])
                    else
                        renameNewBuffer = ""
                        refreshUI()
                    end
                end,
            },
        },
    })

    table.insert(items, {
        type = "button", label = L["Delete Active Profile"], width = 200,
        onClick = function()
            local active = ns:GetActiveProfileName()
            if active == "Default" then
                ns:Print(L["|cffff5555Default profile cannot be deleted.|r"])
                return
            end
            local ok, err = ns:DeleteProfile(active)
            if not ok then ns:Print("|cffff5555%s|r", err or L["Error."]) end
            refreshUI()
        end,
    })

    table.insert(items, {
        type = "button", label = L["Apply to Active Class"], width = 220,
        tooltip = string.format(L["Sets the current profile as the default for %s."],
            CLASS_LABELS[myClass] or myClass),
        onClick = function()
            ns:AssignClassToProfile(myClass, ns:GetActiveProfileName())
            ns:Print(L["'%s' is now the default profile for %s."],
                ns:GetActiveProfileName(), CLASS_LABELS[myClass] or myClass)
            refreshUI()
        end,
    })

    table.insert(items, { type = "spacer", height = 14 })

    -- =========================================================
    -- Section: Class assignments
    -- =========================================================
    table.insert(items, { type = "header", text = L["Profile Assignment per Class"] })

    table.insert(items, {
        type = "desc",
        text = L["Choose a default profile for each class. When logging in with a character of that class, the profile will be loaded automatically."],
    })

    local values = getProfileValuesWithNone()

    for _, classKey in ipairs(CLASS_LIST) do
        table.insert(items, {
            type = "dropdown", label = CLASS_LABELS[classKey] or classKey,
            width = 200,
            values = values,
            get = function() return ns:GetClassAssignment(classKey) or "" end,
            set = function(_, v) ns:AssignClassToProfile(classKey, v) end,
        })
    end

    return items
end
