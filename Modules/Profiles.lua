-- Profiles: profile manager module — switch, create, copy, delete, rename profiles, assign per class.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("profiles", {
    name        = "Profiles",
    group       = "Account",
    description = "Manage profiles with different settings. A default profile can be assigned per class and is loaded automatically on login.",
    noToggle    = true,  -- no power button in the sidebar
    -- The nine class rows are the reason: without a shared grid the ninth sits
    -- alone on full width and each dropdown box starts a few pixels off the one
    -- above it. See UI._grid in UI/OptionsBuilder.
    optionsGrid = true,
    defaults    = {
        enabled = true,
    },
})

-- This "module" has no lifecycle logic of its own
function mod:OnEnable() end

local CLASS_LIST = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local CLASS_LABELS
ns.OnLocaleReady(function()
CLASS_LABELS = {
    WARRIOR = L["Warrior"], PALADIN = L["Paladin"], HUNTER = L["Hunter"], ROGUE = L["Rogue"],
    PRIEST = L["Priest"], SHAMAN = L["Shaman"], MAGE = L["Mage"], WARLOCK = L["Warlock"],
    DRUID = L["Druid"],
}
end)

-- Buffers for UI input (not saved in the DB)
local newProfileNameBuffer = ""
local copyFromBuffer       = nil
local renameNewBuffer      = ""
local manageBuffer         = nil   -- profile selected in the manage section

-- This page is reachable two ways: directly via /vcui profiles, and - the only
-- way anyone actually finds it - as the "Profile" tab of Global Settings, where
-- currentModule is "globalsettings". Checking for "profiles" alone meant every
-- refresh here did nothing on the path people use, leaving all dropdowns stale.
local function refreshUI()
    local UI = ns.UI
    if not (UI and UI.BuildOptionsPage and UI._currentBuildKey) then return end
    if UI._currentBuildKey == "profiles" or UI._currentBuildKey == "globalsettings" then
        UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
    end
end

ns.OnLocaleReady(function()
StaticPopupDialogs["VCUI_PROFILE_RELOAD"] = {
    text = L["Profile changed. Reload the UI now so every module picks it up?"],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
end)
local function askReload()
    StaticPopup_Show("VCUI_PROFILE_RELOAD")
end

ns.OnLocaleReady(function()
StaticPopupDialogs["VCUI_PROFILE_DELETE"] = {
    text = L["Delete profile '%s'? This cannot be undone."],
    button1 = L["Delete"],
    button2 = CANCEL,
    OnAccept = function(self, data)
        local wasActive = ns:GetActiveProfileName() == data
        local ok, err = ns:DeleteProfile(data)
        if not ok then ns:Print("|cffff5555%s|r", err or L["Error."]) end
        if manageBuffer == data then manageBuffer = nil end
        refreshUI()
        if ok and wasActive then askReload() end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    showAlert = 1,
}

StaticPopupDialogs["VCUI_PROFILE_RESET"] = {
    text = L["Reset profile '%s' to the default settings? This cannot be undone."],
    button1 = L["Reset"],
    button2 = CANCEL,
    OnAccept = function(self, data)
        local ok, err = ns:ResetProfile(data)
        if not ok then ns:Print("|cffff5555%s|r", err or L["Error."]) end
        refreshUI()
        if ok and ns:GetActiveProfileName() == data then askReload() end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    showAlert = 1,
}
end)

local popupEditBox = ns.PopupEditBox

ns.OnLocaleReady(function()
StaticPopupDialogs["VCUI_PROFILE_EXPORT"] = {
    text = L["Copy the profile string (Ctrl+C):"],
    button1 = CLOSE,
    hasEditBox = 1, editBoxWidth = 280,
    OnShow = function(self, data)
        local eb = popupEditBox(self)
        if eb then
            eb:SetMaxLetters(0)
            eb:SetText(data or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    EditBoxOnEnterPressed  = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

StaticPopupDialogs["VCUI_PROFILE_IMPORT"] = {
    text = L["Paste the profile string:"],
    button1 = L["Import"],
    button2 = CANCEL,
    hasEditBox = 1, editBoxWidth = 280,
    OnShow = function(self)
        local eb = popupEditBox(self)
        if eb then eb:SetMaxLetters(0); eb:SetText(""); eb:SetFocus() end
    end,
    OnAccept = function(self)
        local eb = popupEditBox(self)
        local name, err = ns:ImportProfileString(eb and eb:GetText() or "")
        if not name then
            ns:Print("|cffff5555%s|r", err or L["Error."])
            -- truthy return keeps the dialog (and the pasted text) open
            return true
        end
        ns:Print(L["Profile '%s' imported. Activate it via 'Switch Profile'."], name)
        refreshUI()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
end)

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

function mod:GetOptions()
    local items = {}
    local activeName = ns:GetActiveProfileName()
    local myClass    = ns:GetMyClassKey()

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
            local prev = ns:GetActiveProfileName()
            ns:SwitchProfile(v)
            -- Persist the switch so it survives relog. A pinned character keeps
            -- its pin in step; otherwise the choice sticks at CLASS scope (the
            -- default scope) — without this the class assignment written on
            -- first login would silently revert the switch at the next login.
            if ns:GetCharAssignment() then
                ns:AssignCharToProfile(v)
            else
                ns:AssignClassToProfile(ns:GetMyClassKey(), v)
            end
            refreshUI()
            if v ~= prev then askReload() end
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

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
                refreshUI()
                askReload()
            else
                refreshUI()
            end
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

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
            askReload()
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

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

    table.insert(items, { type = "header", text = L["Share Profile"] })
    table.insert(items, {
        type = "desc",
        text = L["|cffaaaaaaExport the current profile as a text string - as a backup or to share it. Importing always creates a NEW profile and never overwrites anything.|r"],
    })
    table.insert(items, {
        type = "group", layout = "row", gap = 6,
        items = {
            { type = "button", label = L["Export as string"], width = 180,
              onClick = function()
                  local s = ns:ExportProfileString()
                  if s then
                      StaticPopup_Show("VCUI_PROFILE_EXPORT", nil, nil, s)
                  end
              end },
            { type = "button", label = L["Import from string"], width = 180,
              onClick = function()
                  StaticPopup_Show("VCUI_PROFILE_IMPORT")
              end },
        },
    })

    table.insert(items, { type = "spacer", height = 12 })

    table.insert(items, { type = "header", text = L["Manage Profiles"] })

    -- Read at the moment a button is pressed, never captured. Rename, Delete and
    -- Reset all act on this name, so a copy taken while the page was built would
    -- point at whatever was selected back then - and rename does its work without
    -- a confirmation dialog, so the wrong profile would be renamed unnoticed.
    local function managedName()
        local n = manageBuffer
        if not n or not ns:ProfileExists(n) then return ns:GetActiveProfileName() end
        return n
    end

    table.insert(items, {
        type = "dropdown", label = L["Profile"], width = 220,
        values = getProfileValues(),
        get = function() return managedName() end,
        set = function(_, v) manageBuffer = v; refreshUI() end,
    })

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
                    local oldName = managedName()
                    local ok, err = ns:RenameProfile(oldName, newName)
                    if not ok then
                        ns:Print("|cffff5555%s|r", err or L["Error."])
                    else
                        renameNewBuffer = ""
                        if manageBuffer == oldName then manageBuffer = newName end
                        refreshUI()
                    end
                end,
            },
        },
    })

    table.insert(items, {
        type = "group", layout = "row", gap = 6,
        items = {
            { type = "button", label = L["Delete..."], width = 130,
              onClick = function()
                  local name = managedName()
                  if name == "Default" then
                      ns:Print(L["|cffff5555Default profile cannot be deleted.|r"])
                      return
                  end
                  StaticPopup_Show("VCUI_PROFILE_DELETE", name, nil, name)
              end },
            { type = "button", label = L["Reset to defaults..."], width = 200,
              onClick = function()
                  local name = managedName()
                  StaticPopup_Show("VCUI_PROFILE_RESET", name, nil, name)
              end },
        },
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

    -- Per-talent-group values for individual settings, so a second build does
    -- not need a duplicate profile. Engine in Core/TalentOverrides.lua.
    -- Gated on the API existing, NOT on a group count: the client offers no way
    -- to ask how many talent groups a character has.
    if ns.HasTalentGroups and ns:HasTalentGroups() then
        local active = ns:ActiveTalentGroup()

        table.insert(items, { type = "spacer", height = 10 })
        table.insert(items, { type = "header", text = L["Talent Overrides"] })
        table.insert(items, { type = "desc", text = L["Overrides apply on their own when you switch talent groups. This client has no specialisations, so the dual talent system is the axis."] })
        table.insert(items, { type = "desc", text = "|cff888888" .. ns:TalentGroupText(active) .. "|r" })

        local groups = ns:OverrideGroups()
        local any = false
        for id, g in pairs(groups) do
            any = true
            table.insert(items, { type = "spacer", height = 6 })
            table.insert(items, {
                type  = "desc",
                text  = "|cffffffff" .. g.name .. "|r  |cff666666"
                        .. string.format(L["%d settings overridden"], ns:CountOverrides(id)) .. "|r",
            })
            table.insert(items, {
                type    = "checkbox",
                label   = L["Owns the current talent group"],
                -- noOverride: the override machinery must never record its own
                -- controls, or turning one on would store it as a value.
                noOverride = true,
                get = function() return (g.members and g.members[active]) and true or false end,
                set = function(_, v)
                    ns:AssignTalentGroup(active, v and id or nil)
                    if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
                end,
            })
            table.insert(items, { type = "group", layout = "row", noCard = true, items = {
                { type = "button", label = L["Forget all overrides for this talent group"],
                  onClick = function()
                      ns:ClearOverrides(id)
                      if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
                  end },
                { type = "button", label = L["Delete this group"],
                  onClick = function()
                      ns:DeleteOverrideGroup(id)
                      if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
                  end },
            } })
        end

        if not any then
            table.insert(items, { type = "desc", text = "|cff888888" .. L["No groups yet."] .. "|r" })
        end

        table.insert(items, {
            type  = "button",
            label = L["New group..."],
            onClick = function() StaticPopup_Show("VCUI_OVERRIDE_GROUP_NEW") end,
        })
    end

    return items
end
