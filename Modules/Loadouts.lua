-- =========================================================
-- VuloClassicUI / Modules / Loadouts
-- ItemRack-style equipment set manager.
-- Save current gear as a named "loadout" and quickly swap between sets.
--
-- Equipping in Anniversary is restricted (AutoEquipCursorItem is protected),
-- so we use UseContainerItem(bag, slot) which acts as a normal "use" on
-- equipable items → swap works out-of-combat for items located in bags.
--
-- Slash: /loadout (or /lo) save <name> | equip <name> | delete <name> | list
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("loadouts", {
    name        = L["Loadouts"],
    group       = "QoL",
    description = L["Save and quickly equip gear sets for different specs, content, or roles."],
    defaults = {
        enabled       = true,
        loadouts      = {},   -- { [name] = { slots = { [slotID] = itemLink, ... }, createdAt = epoch } }
        confirmDelete = true,
    },
})

-- =========================================================
-- API compat (Anniversary uses C_Container namespace)
-- =========================================================
local GetContainerItemID    = (C_Container and C_Container.GetContainerItemID)    or _G.GetContainerItemID
local GetContainerNumSlots  = (C_Container and C_Container.GetContainerNumSlots)  or _G.GetContainerNumSlots
local UseContainerItem      = (C_Container and C_Container.UseContainerItem)      or _G.UseContainerItem

-- Equipment slots we capture (skip shirt=4 and tabard=19)
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- =========================================================
-- Helpers
-- =========================================================
local function getItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function captureCurrentEquipment()
    local set = {}
    for _, slot in ipairs(EQUIP_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then set[slot] = link end
    end
    return set
end

local function findItemInBags(targetItemID)
    if not GetContainerItemID or not GetContainerNumSlots then return nil end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            if GetContainerItemID(bag, slot) == targetItemID then
                return bag, slot
            end
        end
    end
    return nil
end

local function countSlots(loadout)
    local n = 0
    if loadout and loadout.slots then
        for _ in pairs(loadout.slots) do n = n + 1 end
    end
    return n
end

local function sortedLoadoutNames()
    local names = {}
    if mod.db and mod.db.loadouts then
        for name in pairs(mod.db.loadouts) do
            table.insert(names, name)
        end
        table.sort(names)
    end
    return names
end

-- =========================================================
-- Core operations
-- =========================================================
local function saveAs(name)
    if not name or name == "" then
        ns:Print(L["Please provide a name for the loadout."])
        return
    end
    mod.db.loadouts[name] = {
        slots     = captureCurrentEquipment(),
        createdAt = time(),
    }
    ns:Print(string.format(L["Loadout '%s' saved (%d items)."],
        name, countSlots(mod.db.loadouts[name])))
end

local function deleteLoadout(name)
    if not mod.db.loadouts[name] then
        ns:Print(string.format(L["Loadout '%s' does not exist."], name))
        return
    end
    mod.db.loadouts[name] = nil
    ns:Print(string.format(L["Loadout '%s' deleted."], name))
end

local function equipLoadout(name)
    if InCombatLockdown() then
        ns:Print(L["Cannot change equipment in combat."])
        return
    end
    local loadout = mod.db.loadouts[name]
    if not loadout then
        ns:Print(string.format(L["Loadout '%s' does not exist."], name))
        return
    end
    if not UseContainerItem then
        ns:Print(L["Equipment swap API not available on this client."])
        return
    end

    local swapped, missing = 0, 0
    for slot, link in pairs(loadout.slots) do
        local currentLink = GetInventoryItemLink("player", slot)
        if currentLink ~= link then
            local itemID = getItemIDFromLink(link)
            if itemID then
                local bag, bagSlot = findItemInBags(itemID)
                if bag and bagSlot then
                    pcall(UseContainerItem, bag, bagSlot)
                    swapped = swapped + 1
                else
                    missing = missing + 1
                end
            end
        end
    end

    if swapped > 0 then
        if missing > 0 then
            ns:Print(string.format(L["Loadout '%s' equipped (%d swapped, %d missing from bags)."],
                name, swapped, missing))
        else
            ns:Print(string.format(L["Loadout '%s' equipped (%d items swapped)."], name, swapped))
        end
    elseif missing > 0 then
        ns:Print(string.format(L["Loadout '%s': %d items missing from bags, nothing swapped."],
            name, missing))
    else
        ns:Print(string.format(L["Loadout '%s' already equipped."], name))
    end
end

local function listLoadouts()
    local names = sortedLoadoutNames()
    if #names == 0 then
        ns:Print(L["No loadouts saved yet."])
        return
    end
    ns:Print(L["Saved loadouts:"])
    for _, name in ipairs(names) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  |cffffd100%s|r (%d %s)",
            name, countSlots(mod.db.loadouts[name]), L["items"]))
    end
end

-- =========================================================
-- StaticPopups
-- =========================================================
StaticPopupDialogs["VCUI_LOADOUT_SAVE"] = {
    text = L["Save current equipment as a new loadout. Enter name:"],
    button1 = SAVE or L["Save"],
    button2 = CANCEL or L["Cancel"],
    hasEditBox = true,
    maxLetters = 32,
    OnAccept = function(self)
        saveAs(self.editBox:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        saveAs(self:GetText())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["VCUI_LOADOUT_DELETE"] = {
    text = L["Delete loadout '%s'?"],
    button1 = YES or L["Yes"],
    button2 = NO  or L["No"],
    OnAccept = function(_, data) deleteLoadout(data) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- =========================================================
-- Slash commands
-- =========================================================
_G.SLASH_VCUILOADOUT1 = "/loadout"
_G.SLASH_VCUILOADOUT2 = "/lo"
_G.SlashCmdList["VCUILOADOUT"] = function(msg)
    msg = msg or ""
    local cmd, arg = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "save" then
        saveAs(arg)
    elseif cmd == "equip" or cmd == "" then
        if arg ~= "" then
            equipLoadout(arg)
        else
            ns:Print(L["Usage: /loadout equip <name> | save <name> | delete <name> | list"])
        end
    elseif cmd == "delete" or cmd == "del" or cmd == "remove" or cmd == "rm" then
        if arg == "" then
            ns:Print(L["Usage: /loadout delete <name>"])
        elseif mod.db.confirmDelete then
            local dlg = StaticPopup_Show("VCUI_LOADOUT_DELETE", arg)
            if dlg then dlg.data = arg end
        else
            deleteLoadout(arg)
        end
    elseif cmd == "list" or cmd == "ls" then
        listLoadouts()
    else
        -- Treat unknown first word as a loadout name to equip
        if mod.db.loadouts[msg] then
            equipLoadout(msg)
        else
            ns:Print(L["Usage: /loadout equip <name> | save <name> | delete <name> | list"])
        end
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    if not mod.db then return end
    -- Defensive: ensure table exists even if profile is fresh
    mod.db.loadouts = mod.db.loadouts or {}
end

-- =========================================================
-- Options UI
-- =========================================================
function mod:GetOptions()
    local items = {
        { type = "header", text = L["Loadouts"] },
        { type = "desc", text = L["Save your current equipment as named gear sets and quickly switch between them. Equipping requires you to be out of combat — items in your bags are auto-equipped via Use."] },

        { type = "spacer", height = 6 },
        { type = "button", label = L["Save current equipment as new loadout..."], width = 320,
          onClick = function() StaticPopup_Show("VCUI_LOADOUT_SAVE") end },
        { type = "toggle", label = L["Confirm before deleting a loadout"],
          get = function() return mod.db.confirmDelete ~= false end,
          set = function(_, v) mod.db.confirmDelete = v end },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Saved Loadouts"] },
    }

    local names = sortedLoadoutNames()
    if #names == 0 then
        table.insert(items, { type = "desc", text = L["|cffaaaaaaNo loadouts saved yet. Use the button above to save your current gear.|r"] })
    else
        for _, name in ipairs(names) do
            local capturedName = name  -- closure capture
            local slotCount = countSlots(mod.db.loadouts[name])
            table.insert(items, { type = "group", layout = "row", gap = 6,
                items = {
                    { type = "desc", text = string.format("|cffffd100%s|r |cff888888(%d %s)|r",
                        name, slotCount, L["items"]) },
                    { type = "button", label = L["Equip"], width = 80,
                      onClick = function() equipLoadout(capturedName) end },
                    { type = "button", label = L["Overwrite"], width = 100,
                      onClick = function()
                          mod.db.loadouts[capturedName] = {
                              slots = captureCurrentEquipment(),
                              createdAt = time(),
                          }
                          ns:Print(string.format(L["Loadout '%s' updated with current gear."], capturedName))
                      end },
                    { type = "button", label = L["Delete"], width = 80,
                      onClick = function()
                          if mod.db.confirmDelete then
                              local dlg = StaticPopup_Show("VCUI_LOADOUT_DELETE", capturedName)
                              if dlg then dlg.data = capturedName end
                          else
                              deleteLoadout(capturedName)
                          end
                      end },
                },
            })
        end
    end

    table.insert(items, { type = "spacer", height = 8 })
    table.insert(items, { type = "desc", text = L["|cffaaaaaaSlash commands: /loadout save <name>, /loadout equip <name>, /loadout delete <name>, /loadout list. Short alias: /lo|r"] })

    return items
end
