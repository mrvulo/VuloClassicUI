-- =========================================================
-- VuloClassicUI / Modules / Loadouts
-- Equipment set manager.
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
    name        = "Loadouts",
    group       = "QoL",
    description = "Save and quickly equip gear sets for different specs, content, or roles.",
    defaults = {
        enabled       = true,
        loadouts      = {},   -- { [name] = { slots = { [slotID] = itemLink, ... }, createdAt = epoch, formIdx = nil } }
        confirmDelete = true,
        -- Minimap button
        minimap = { hidden = false, angle = 45 },
        -- Auto-switch on stance/form change: [formIndex] = "loadoutName"
        autoSwitchEnabled = true,
        formMapping       = {},
        -- Auto-switch on talent spec (dominant talent tab): [tabIndex] = "loadoutName"
        specSwitchEnabled = true,
        specMapping       = {},
        -- Character-frame sidebar
        sidebarEnabled      = true,
        sidebarTopOffset    = -14,  -- fine-tune top edge (px) vs CharacterFrame
        sidebarBottomOffset = 45,   -- fine-tune bottom edge (px) vs CharacterFrame
        sidebarPos          = { x = 0, y = 0 },  -- edit-mode drag offset from the char window
    },
})

-- =========================================================
-- Per-character storage. Loadouts (and their spec/form bindings) reference
-- this character's gear, so they live in VuloClassicUICharDB (per-character),
-- NOT in mod.db (account-wide). The old account-wide loadouts still sit in
-- mod.db.loadouts as a legacy pool that "/loadout import" copies onto the
-- current character (one-time migration for users upgrading from <= 1.8.0).
-- =========================================================
local function charDB()
    _G.VuloClassicUICharDB = _G.VuloClassicUICharDB or {}
    return _G.VuloClassicUICharDB
end
local function LO()
    local c = charDB(); c.loadouts = c.loadouts or {}; return c.loadouts
end
local function specMap()
    local c = charDB(); c.specMapping = c.specMapping or {}; return c.specMapping
end
local function formMap()
    local c = charDB(); c.formMapping = c.formMapping or {}; return c.formMapping
end

-- =========================================================
-- API compat (Anniversary uses C_Container namespace)
-- =========================================================
local GetContainerItemID    = (C_Container and C_Container.GetContainerItemID)    or _G.GetContainerItemID
local GetContainerNumSlots  = (C_Container and C_Container.GetContainerNumSlots)  or _G.GetContainerNumSlots
local UseContainerItem      = (C_Container and C_Container.UseContainerItem)      or _G.UseContainerItem

-- Equipment slots we capture (skip shirt=4 and tabard=19)
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- Slot display names (for UI / pickers)
local SLOT_NAMES = {
    [1]  = L["Head"],    [2]  = L["Neck"],     [3]  = L["Shoulder"],
    [5]  = L["Chest"],   [6]  = L["Waist"],    [7]  = L["Legs"],
    [8]  = L["Feet"],    [9]  = L["Wrist"],    [10] = L["Hands"],
    [11] = L["Finger 1"], [12] = L["Finger 2"],
    [13] = L["Trinket 1"], [14] = L["Trinket 2"],
    [15] = L["Back"],
    [16] = L["Main Hand"], [17] = L["Off Hand"], [18] = L["Ranged"],
}

-- Pre-defined slot groups for quick-save
local SLOT_GROUPS = {
    all      = EQUIP_SLOTS,
    trinkets = { 13, 14 },
    weapons  = { 16, 17, 18 },
    rings    = { 11, 12 },
    armor    = { 1, 3, 5, 6, 7, 8, 9, 10, 15 },
}

-- =========================================================
-- Helpers
-- =========================================================
local function getItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function captureCurrentEquipment(slotList)
    slotList = slotList or EQUIP_SLOTS
    local set = {}
    for _, slot in ipairs(slotList) do
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

-- =========================================================
-- Equip a bag item into a SPECIFIC inventory slot.
-- UseContainerItem ignores the destination slot and always picks the first
-- valid one — that's why paired slots (rings 11/12, trinkets 13/14) always
-- ended up in the upper slot. EquipCursorItem(slot) is the only reliable API
-- that honours the exact target slot: pick the item onto the cursor, then
-- equip the cursor into the requested slot.
-- Shared with SlotPicker via ns:EquipBagItemToSlot.
-- =========================================================
local _PickupContainerItem = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem

function ns:EquipBagItemToSlot(bag, bagSlot, equipSlot)
    if InCombatLockdown() then return false, "combat" end
    if not _PickupContainerItem or not _G.EquipCursorItem then return false, "noapi" end

    ClearCursor()
    _PickupContainerItem(bag, bagSlot)
    -- Verify the pickup actually grabbed something
    if CursorHasItem and not CursorHasItem() then
        return false, "pickup"
    end
    -- EquipCursorItem honours the explicit slot (unlike UseContainerItem)
    local ok = pcall(_G.EquipCursorItem, equipSlot)
    -- Only clear if something is still stuck on the cursor (e.g. equip failed).
    -- A BoE-confirm popup leaves the item reserved — don't yank it back, let
    -- the player confirm. If equip succeeded the cursor is already empty.
    if CursorHasItem and CursorHasItem() then
        ClearCursor()
    end
    return ok
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
    if mod.db and LO() then
        for name in pairs(LO()) do
            table.insert(names, name)
        end
        table.sort(names)
    end
    return names
end

-- =========================================================
-- Core operations
-- =========================================================
-- Copy a slot-id list (used as the intended mask)
local function copySlotList(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

local function saveAs(name, slotList)
    if not name or name == "" then
        ns:Print(L["Please provide a name for the loadout."])
        return
    end
    LO()[name] = {
        slots     = captureCurrentEquipment(slotList),
        slotMask  = copySlotList(slotList or EQUIP_SLOTS),
        createdAt = time(),
    }
    ns:Print(string.format(L["Loadout '%s' saved (%d items)."],
        name, countSlots(LO()[name])))
end

-- Pending slot list for the StaticPopup (popups have no parameter passing on Show)
local _pendingSaveSlots = nil

local function promptSaveWithSlots(slotList)
    _pendingSaveSlots = slotList
    StaticPopup_Show("VCUI_LOADOUT_SAVE")
end

-- Overwrite an existing loadout with current gear, preserving the original
-- slot mask. THIS IS THE KEY HELPER — previously every "save current as ..."
-- button iterated over loadout.slots which only has slots that had an item
-- at the time of the original save, so missing items (e.g. Head/Neck/Shoulder
-- not equipped at save time) would never be re-captured.
local function overwriteLoadout(name)
    local loadout = LO()[name]
    if not loadout then return end
    -- Prefer slotMask (intended slots, set at save time). Fall back to existing
    -- slots keys for legacy data without a mask.
    local slotList = loadout.slotMask
    if not slotList or #slotList == 0 then
        slotList = {}
        for s in pairs(loadout.slots or {}) do table.insert(slotList, s) end
    end
    if #slotList == 0 then slotList = EQUIP_SLOTS end  -- ultimate fallback: all slots
    LO()[name] = {
        slots     = captureCurrentEquipment(slotList),
        slotMask  = copySlotList(slotList),
        createdAt = time(),
    }
    ns:Print(string.format(L["Loadout '%s' updated with current gear."], name))
end

local function deleteLoadout(name)
    if not LO()[name] then
        ns:Print(string.format(L["Loadout '%s' does not exist."], name))
        return
    end
    LO()[name] = nil
    ns:Print(string.format(L["Loadout '%s' deleted."], name))
end

local function equipLoadout(name)
    if InCombatLockdown() then
        ns:Print(L["Cannot change equipment in combat."])
        return
    end
    local loadout = LO()[name]
    if not loadout then
        ns:Print(string.format(L["Loadout '%s' does not exist."], name))
        return
    end
    if not _PickupContainerItem and not UseContainerItem then
        ns:Print(L["Equipment swap API not available on this client."])
        return
    end

    local swapped, missing = 0, 0
    -- Sorted ascending so paired slots resolve predictably (11 before 12,
    -- 13 before 14). We equip via ns:EquipBagItemToSlot which uses
    -- EquipCursorItem(slot) — that honours the exact destination slot, so
    -- ring2/trinket2 land in slot 12/14 instead of always the upper slot.
    local sortedSlots = {}
    for slot in pairs(loadout.slots) do table.insert(sortedSlots, slot) end
    table.sort(sortedSlots)

    for _, slot in ipairs(sortedSlots) do
        local link = loadout.slots[slot]
        local currentLink = GetInventoryItemLink("player", slot)
        if currentLink ~= link then
            local itemID = getItemIDFromLink(link)
            if itemID then
                local bag, bagSlot = findItemInBags(itemID)
                if bag and bagSlot then
                    local ok = ns:EquipBagItemToSlot(bag, bagSlot, slot)
                    if not ok and UseContainerItem then
                        -- Fallback for non-paired slots if cursor method failed
                        ok = pcall(UseContainerItem, bag, bagSlot)
                    end
                    if ok then swapped = swapped + 1 else missing = missing + 1 end
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
            name, countSlots(LO()[name]), L["items"]))
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
        saveAs(self.editBox:GetText(), _pendingSaveSlots)
        _pendingSaveSlots = nil
    end,
    EditBoxOnEnterPressed = function(self)
        saveAs(self:GetText(), _pendingSaveSlots)
        _pendingSaveSlots = nil
        self:GetParent():Hide()
    end,
    OnCancel = function() _pendingSaveSlots = nil end,
    EditBoxOnEscapePressed = function(self)
        _pendingSaveSlots = nil
        self:GetParent():Hide()
    end,
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
    elseif cmd == "spec" then
        -- Debug: show dual-spec state
        local active = (GetActiveTalentGroup and select(1, pcall(GetActiveTalentGroup))) and GetActiveTalentGroup() or "?"
        local numG   = (GetNumTalentGroups  and select(1, pcall(GetNumTalentGroups)))  and GetNumTalentGroups()  or "?"
        DEFAULT_CHAT_FRAME:AddMessage("|cff9b6cff[Loadouts spec debug]|r")
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  GetActiveTalentGroup() = %s", tostring(active)))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  GetNumTalentGroups()   = %s", tostring(numG)))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  specSwitchEnabled      = %s", tostring(mod.db.specSwitchEnabled)))
        local anyMap = false
        for name, g in pairs(specMap() or {}) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  mapping: '%s' -> spec %d", name, g))
            anyMap = true
        end
        if not anyMap then
            DEFAULT_CHAT_FRAME:AddMessage("  |cffff8800No spec bindings set — bind a set to a spec in the settings.|r")
        end
        if mod._forceSpecCheck then mod._forceSpecCheck() end
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
    elseif cmd == "import" then
        if mod.ImportLegacy then mod.ImportLegacy() end
    elseif cmd == "debug" then
        if mod._debugSizes then mod._debugSizes() else ns:Print("Sidebar not created yet.") end
    elseif cmd == "tune" then
        -- /loadout tune top <n>  |  /loadout tune bottom <n>
        local which, valStr = arg:match("^(%S+)%s*(%-?%d*)$")
        local val = tonumber(valStr)
        if which == "top" and val then
            mod.db.sidebarTopOffset = val
            if mod._reanchorSidebar then mod._reanchorSidebar() end
            ns:Print(string.format("Sidebar top offset = %d", val))
        elseif which == "bottom" and val then
            mod.db.sidebarBottomOffset = val
            if mod._reanchorSidebar then mod._reanchorSidebar() end
            ns:Print(string.format("Sidebar bottom offset = %d", val))
        elseif which == "reset" then
            mod.db.sidebarTopOffset = 0
            mod.db.sidebarBottomOffset = 0
            if mod._reanchorSidebar then mod._reanchorSidebar() end
            ns:Print("Sidebar offsets reset to 0.")
        else
            ns:Print("Usage: /loadout tune top <n> | tune bottom <n> | tune reset")
        end
    else
        -- Treat unknown first word as a loadout name to equip
        if LO()[msg] then
            equipLoadout(msg)
        else
            ns:Print(L["Usage: /loadout equip <name> | save <name> | delete <name> | list"])
        end
    end
end

-- =========================================================
-- Minimap button
-- =========================================================
local mmBtn

local function updateMinimapPos()
    if not mmBtn then return end
    local angle = (mod.db.minimap and mod.db.minimap.angle) or -45
    local rad = math.rad(angle)
    local r = 80  -- distance from minimap center
    local x = r * math.cos(rad)
    local y = r * math.sin(rad)
    mmBtn:ClearAllPoints()
    mmBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Forward declarations (resolves circular references between popup menu and settings opener)
local openLoadoutsSettings

-- Loadouts dropdown — uses ns:ShowPopupMenu (shared helper, EasyMenu replacement)
local function showLoadoutMenu(anchor)
    local entries = {
        { title = true, text = L["Loadouts"] },
    }

    local names = sortedLoadoutNames()
    if #names == 0 then
        table.insert(entries, { text = "  " .. L["No loadouts saved yet."], disabled = true })
    else
        for _, name in ipairs(names) do
            local capturedName = name
            table.insert(entries, {
                text = "  " .. name,
                func = function() equipLoadout(capturedName) end,
            })
        end
    end

    table.insert(entries, { separator = true })
    table.insert(entries, { text = L["Save current as new..."], func = function() promptSaveWithSlots(nil) end })
    table.insert(entries, { text = L["Save trinkets only..."],  func = function() promptSaveWithSlots(SLOT_GROUPS.trinkets) end })
    table.insert(entries, { text = L["Save weapons only..."],   func = function() promptSaveWithSlots(SLOT_GROUPS.weapons)  end })
    table.insert(entries, { separator = true })
    table.insert(entries, { text = L["Settings..."],
        func = function() openLoadoutsSettings() end })

    ns:ShowPopupMenu(entries, anchor)
end

-- Helper: open the Loadouts settings (prefer direct tab open, fall back to main frame)
-- Assigned to forward-declared local (declared near showLoadoutMenu)
function openLoadoutsSettings()
    if ns.OpenConfig then
        ns:OpenConfig("loadouts")
    elseif ns.UI and ns.UI.ToggleMainFrame then
        ns.UI:ToggleMainFrame()
    end
end

local function createMinimapButton()
    if mmBtn then return end
    if not Minimap then return end

    -- LibDBIcon standard layout: 31x31 button, 53x53 border at TOPLEFT (0,0),
    -- icon 17x17 at TOPLEFT(7, -6), background 20x20 at TOPLEFT(7, -5).
    mmBtn = CreateFrame("Button", "VCUI_LoadoutsMinimapButton", Minimap)
    mmBtn:SetFrameStrata("MEDIUM")
    mmBtn:SetFrameLevel(8)
    mmBtn:SetSize(31, 31)
    mmBtn:SetMovable(true)
    mmBtn:RegisterForClicks("AnyUp")
    mmBtn:RegisterForDrag("LeftButton")

    -- Background (the dark circle behind the icon)
    local background = mmBtn:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)

    -- Icon (equipment armor)
    local icon = mmBtn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Chest_Plate06")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- crop default Blizzard icon border

    -- Round border (Blizzard minimap-tracking style) — standard LibDBIcon offset
    local border = mmBtn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)

    -- Hover highlight
    mmBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    -- Drag to reposition around minimap (saved as angle)
    mmBtn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            if not mx then return end
            local sx, sy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale() or 1
            sx, sy = sx / scale, sy / scale
            local angle = math.deg(math.atan2(sy - my, sx - mx))
            mod.db.minimap = mod.db.minimap or {}
            mod.db.minimap.angle = angle
            updateMinimapPos()
        end)
    end)
    mmBtn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- Click handlers — Left = quick switcher menu, Right = settings
    mmBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            showLoadoutMenu(self)
        elseif button == "RightButton" then
            openLoadoutsSettings()
        end
    end)

    mmBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff9b6cff" .. L["Loadouts"] .. "|r")
        GameTooltip:AddLine(L["Left-click: switch set"],   1, 1, 1)
        GameTooltip:AddLine(L["Right-click: settings"],    1, 1, 1)
        GameTooltip:AddLine(L["Drag: reposition"],         0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updateMinimapPos()

    if mod.db.minimap and mod.db.minimap.hidden then
        mmBtn:Hide()
    end
end

local function applyMinimapVisibility()
    if not mmBtn then return end
    if mod.db.minimap and mod.db.minimap.hidden then
        mmBtn:Hide()
    else
        mmBtn:Show()
    end
end

-- =========================================================
-- Stance/Form auto-switching
-- =========================================================
local _lastForm = -1

local function getCurrentForm()
    if not GetShapeshiftForm then return 0 end
    return GetShapeshiftForm() or 0
end

local function getFormName(formIdx)
    if formIdx == 0 then return L["No Form"] end
    if GetShapeshiftFormInfo then
        -- returns (icon, name, ...); pcall prepends ok, so the name is the 3rd value
        local ok, _icon, fname = pcall(GetShapeshiftFormInfo, formIdx)
        if ok and type(fname) == "string" and fname ~= "" then return fname end
    end
    return string.format(L["Form %d"], formIdx)
end

local function onShapeshiftChange()
    if not mod._enabled or not mod.db then return end
    if not mod.db.autoSwitchEnabled then return end
    if InCombatLockdown() then return end

    local currentForm = getCurrentForm()
    if currentForm == _lastForm then return end
    _lastForm = currentForm

    -- formMapping is keyed by loadout name → form index (1:1).
    -- Reverse-look up to find which loadout is bound to the current form.
    if not formMap() then return end
    for loadoutName, formIdx in pairs(formMap()) do
        if formIdx == currentForm and LO()[loadoutName] then
            equipLoadout(loadoutName)
            return
        end
    end
end

-- =========================================================
-- Dual-spec auto-switching
-- Anniversary backported the WotLK dual-spec system. We use the real spec
-- group APIs (GetActiveTalentGroup + ACTIVE_TALENT_GROUP_CHANGED) so switching
-- between Spec 1 and Spec 2 in-game instantly equips the bound loadout.
-- =========================================================
local _lastSpecGroup = -1

local function getActiveSpecGroup()
    if GetActiveTalentGroup then
        local ok, g = pcall(GetActiveTalentGroup)
        if ok and g then return g end
    end
    return 1
end

local function getNumSpecGroups()
    if GetNumTalentGroups then
        local ok, n = pcall(GetNumTalentGroups)
        if ok and n then return n end
    end
    return 1
end

-- Points spent in a talent tab FOR A SPECIFIC spec group (4th param = talentGroup).
local function getTabPoints(tab, group)
    if GetTalentTabInfo then
        local _, _, pointsSpent = GetTalentTabInfo(tab, false, false, group)
        if type(pointsSpent) == "number" then return pointsSpent end
    end
    local total = 0
    local numTalents = (GetNumTalents and GetNumTalents(tab)) or 0
    for t = 1, numTalents do
        local rank = select(5, GetTalentInfo(tab, t, false, false, group))
        total = total + (tonumber(rank) or 0)
    end
    return total
end

-- Label for a spec group: "Spec 1 (Shadow)" using the dominant talent tab name.
local function getSpecGroupLabel(group)
    local numTabs = (GetNumTalentTabs and GetNumTalentTabs()) or 0
    local bestName, bestPoints = nil, -1
    for tab = 1, numTabs do
        local pts = getTabPoints(tab, group)
        if pts > bestPoints then
            bestPoints = pts
            local name = GetTalentTabInfo and GetTalentTabInfo(tab, false, false, group)
            if type(name) == "string" and name ~= "" then bestName = name else bestName = nil end
        end
    end
    local base = string.format(L["Spec %d"], group)
    if bestName and bestPoints > 0 then
        return string.format("%s (%s)", base, bestName)
    end
    return base
end

local function onTalentChange()
    if not mod._enabled or not mod.db then return end
    if not mod.db.specSwitchEnabled then return end
    if InCombatLockdown() then return end

    local currentGroup = getActiveSpecGroup()
    if currentGroup == _lastSpecGroup then return end
    _lastSpecGroup = currentGroup

    -- specMapping is keyed by loadout name → spec group index (1:1)
    if not specMap() then return end
    for loadoutName, groupIdx in pairs(specMap()) do
        if groupIdx == currentGroup and LO()[loadoutName] then
            equipLoadout(loadoutName)
            return
        end
    end
end

-- Force a spec re-check (clears the cached group so it always re-evaluates).
-- Used by /loadout spec and as the polling fallback.
mod._forceSpecCheck = function()
    _lastSpecGroup = -1
    onTalentChange()
end

-- Event-independent polling fallback: some Anniversary builds don't fire
-- ACTIVE_TALENT_GROUP_CHANGED reliably, so we also poll every 2s.
local _specPoller
local function startSpecPolling()
    if _specPoller or not (C_Timer and C_Timer.NewTicker) then return end
    _specPoller = C_Timer.NewTicker(2, function()
        if not mod._enabled or not mod.db or not mod.db.specSwitchEnabled then return end
        if InCombatLockdown() then return end
        local g = getActiveSpecGroup()
        if g ~= _lastSpecGroup then
            onTalentChange()  -- group changed since last check → switch
        end
    end)
end

-- =========================================================
-- Character-frame sidebar (loadout buttons)
-- =========================================================
local sidebar
local sidebarSetButtons = {}
local sidebarItemRows   = {}    -- pool of expanded-item-row frames
local sidebarSelected           -- currently highlighted loadout name
local sidebarExpanded           -- name of currently expanded loadout (only one at a time)
local refreshSidebar            -- forward declaration

-- =========================================================
-- Bag-item picker for replacing a slot in a loadout (uses SlotPicker's scan API)
-- =========================================================
local function showSlotReplacePicker(loadoutName, targetSlot, anchor)
    if not ns.ScanBagsForSlot then
        ns:Print(L["SlotPicker module is required for editing item slots."])
        return
    end

    local GetContainerItemLink_ = (C_Container and C_Container.GetContainerItemLink) or _G.GetContainerItemLink

    -- Build a unified candidate list:
    --   1) Currently equipped item in that slot (if any) — common case where
    --      the desired item is on the character, not in a bag
    --   2) For Trinkets/Rings (paired slots), the OTHER slot's equipped item too
    --      (you may want trinket1 to be what's currently in trinket2)
    --   3) All compatible items found in bags by ns:ScanBagsForSlot
    -- De-dupes by itemID so we don't show the same physical item twice.
    local candidates = {}  -- ordered list of { link, label, sourceTag }
    local seenItemID = {}

    local function addCandidate(link, label)
        if not link then return end
        local itemID = tonumber(link:match("item:(%d+)"))
        if not itemID or seenItemID[itemID] then return end
        seenItemID[itemID] = true
        table.insert(candidates, { link = link, label = label })
    end

    -- 1) Currently equipped at this slot
    local currentLink = GetInventoryItemLink("player", targetSlot)
    if currentLink then
        local name = currentLink:match("|h%[(.-)%]|h") or currentLink
        addCandidate(currentLink, name .. " |cff66ff66" .. L["(equipped)"] .. "|r")
    end

    -- 2) Paired slot for symmetric pairs (rings 11/12, trinkets 13/14)
    local PAIRS = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }
    local pairedSlot = PAIRS[targetSlot]
    if pairedSlot then
        local pairedLink = GetInventoryItemLink("player", pairedSlot)
        if pairedLink then
            local name = pairedLink:match("|h%[(.-)%]|h") or pairedLink
            addCandidate(pairedLink, name .. " |cff8888ffin " .. (SLOT_NAMES[pairedSlot] or "?") .. "|r")
        end
    end

    -- 3) Bag scan
    local bagResults = ns:ScanBagsForSlot(targetSlot)
    for _, entry in ipairs(bagResults) do
        local link = GetContainerItemLink_ and GetContainerItemLink_(entry.bag, entry.slot)
        if link then
            local name = link:match("|h%[(.-)%]|h") or link
            addCandidate(link, name)
        end
    end

    local slotName = SLOT_NAMES[targetSlot] or ("Slot " .. targetSlot)
    local entries  = {
        { title = true, text = string.format(L["Replace: %s"], slotName) },
    }

    if #candidates == 0 then
        table.insert(entries, { text = L["No matching items in your bags."], disabled = true })
    else
        for _, c in ipairs(candidates) do
            local capturedLink = c.link
            table.insert(entries, {
                text = "  " .. c.label,
                func = function()
                    if LO()[loadoutName] then
                        LO()[loadoutName].slots[targetSlot] = capturedLink
                        refreshSidebar()
                        ns:Print(string.format(L["Loadout '%s': slot updated."], loadoutName))
                    end
                end,
            })
        end
    end

    table.insert(entries, { separator = true })
    table.insert(entries, { text = L["Remove from set"], func = function()
        if LO()[loadoutName] then
            LO()[loadoutName].slots[targetSlot] = nil
            refreshSidebar()
        end
    end })

    ns:ShowPopupMenu(entries, anchor)
end

local function getSetIcon(name)
    local loadout = mod.db and LO() and LO()[name]
    if not loadout or not loadout.slots then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    if loadout.iconOverride then return loadout.iconOverride end
    -- Auto-pick first item's icon
    if GetItemInfoInstant then
        for _, link in pairs(loadout.slots) do
            local _, _, _, _, icon = GetItemInfoInstant(link)
            if icon then return icon end
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- =========================================================
-- Set-icon picker popup
-- Grid of: [Auto] + every item icon in the set + a few generic role icons.
-- Click sets loadout.iconOverride (or clears it for Auto).
-- =========================================================
local _iconPicker
local _iconBtns = {}
local ICON_SIZE = 30
local ICON_COLS = 6
local ICON_PAD  = 3

-- A few hand-picked generic icons (roles/specs) so a set can use a symbol
-- that isn't one of its items.
local GENERIC_ICONS = {
    "Interface\\Icons\\Spell_Holy_PowerWordShield",
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    "Interface\\Icons\\Spell_Holy_HolyBolt",
    "Interface\\Icons\\Spell_Nature_Lightning",
    "Interface\\Icons\\Ability_Warrior_OffensiveStance",
    "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    "Interface\\Icons\\Ability_Rogue_Sprint",
    "Interface\\Icons\\Spell_Frost_FrostBolt02",
    "Interface\\Icons\\Spell_Fire_FlameBolt",
    "Interface\\Icons\\Spell_Nature_HealingTouch",
    "Interface\\Icons\\INV_Sword_27",
    "Interface\\Icons\\INV_Shield_06",
    "Interface\\Icons\\INV_Misc_Gem_Diamond_03",
    "Interface\\Icons\\Achievement_PVP_A_A",
}

local function getIconPickerButton(idx)
    local b = _iconBtns[idx]
    if b then return b end
    b = CreateFrame("Button", nil, _iconPicker)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(b)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(b)
    b.hl:SetColorTexture(0.4, 0.3, 0.6, 0.4)
    b:RegisterForClicks("LeftButtonUp")
    _iconBtns[idx] = b
    return b
end

local function showIconPicker(loadoutName, anchor)
    local loadout = LO()[loadoutName]
    if not loadout then return end

    if not _iconPicker then
        _iconPicker = CreateFrame("Frame", "VCUI_LoadoutIconPicker", UIParent,
            BackdropTemplateMixin and "BackdropTemplate")
        _iconPicker:SetFrameStrata("FULLSCREEN_DIALOG")
        _iconPicker:Hide()
        _iconPicker:EnableMouse(true)
        _iconPicker:SetClampedToScreen(true)
        if _iconPicker.SetBackdrop then
            _iconPicker:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets   = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            _iconPicker:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
            _iconPicker:SetBackdropBorderColor(0.4, 0.3, 0.6, 1)
        end
        tinsert(UISpecialFrames, "VCUI_LoadoutIconPicker")
        _iconPicker.title = _iconPicker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        _iconPicker.title:SetPoint("TOPLEFT", _iconPicker, "TOPLEFT", 8, -6)
        _iconPicker.title:SetTextColor(1, 0.82, 0)
    end

    _iconPicker.title:SetText(string.format(L["Icon for: %s"], loadoutName))

    -- Build the icon list: Auto first, then set items, then generics (de-duped)
    local icons = {}           -- { tex = path or nil (=auto), isAuto = bool }
    local seen  = {}
    table.insert(icons, { isAuto = true })
    if GetItemInfoInstant and loadout.slots then
        -- stable order by slot
        local slots = {}
        for s in pairs(loadout.slots) do table.insert(slots, s) end
        table.sort(slots)
        for _, s in ipairs(slots) do
            local _, _, _, _, ic = GetItemInfoInstant(loadout.slots[s])
            if ic and not seen[ic] then
                seen[ic] = true
                table.insert(icons, { tex = ic })
            end
        end
    end
    for _, ic in ipairs(GENERIC_ICONS) do
        if not seen[ic] then
            seen[ic] = true
            table.insert(icons, { tex = ic })
        end
    end

    -- Hide leftover buttons
    for _, b in ipairs(_iconBtns) do b:Hide() end

    local startY = 24
    for i, entry in ipairs(icons) do
        local b = getIconPickerButton(i)
        b:Show()
        if entry.isAuto then
            b.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            b.tex:SetVertexColor(0.7, 0.7, 0.7)
            b._iconValue = nil  -- nil = auto
        else
            b.tex:SetTexture(entry.tex)
            b.tex:SetVertexColor(1, 1, 1)
            b._iconValue = entry.tex
        end
        b:SetScript("OnClick", function(self)
            loadout.iconOverride = self._iconValue  -- nil → auto
            _iconPicker:Hide()
            refreshSidebar()
        end)
        local col = (i - 1) % ICON_COLS
        local row = math.floor((i - 1) / ICON_COLS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", _iconPicker, "TOPLEFT",
            6 + col * (ICON_SIZE + ICON_PAD),
            -(startY + row * (ICON_SIZE + ICON_PAD)))
    end

    local numRows = math.ceil(#icons / ICON_COLS)
    _iconPicker:SetSize(
        ICON_COLS * (ICON_SIZE + ICON_PAD) + 12,
        startY + numRows * (ICON_SIZE + ICON_PAD) + 8)

    _iconPicker:ClearAllPoints()
    if anchor and anchor.GetLeft then
        _iconPicker:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
    else
        _iconPicker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    _iconPicker:Show()
end

local function createSetRow(parent, index)
    local btn = sidebarSetButtons[index]
    if btn then return btn end

    btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(32)

    -- Icon (left)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(26, 26)
    btn.icon:SetPoint("LEFT", btn, "LEFT", 4, 0)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Expand button (right) — toggles inline item view
    btn.expand = CreateFrame("Button", nil, btn)
    btn.expand:SetSize(18, 18)
    btn.expand:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    btn.expand.icon = btn.expand:CreateTexture(nil, "ARTWORK")
    btn.expand.icon:SetAllPoints(btn.expand)
    btn.expand.icon:SetTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Up")
    btn.expand:SetHighlightTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Highlight")
    btn.expand:SetScript("OnClick", function()
        if sidebarExpanded == btn.setName then
            sidebarExpanded = nil
        else
            sidebarExpanded = btn.setName
        end
        refreshSidebar()
    end)

    -- Name text (between icon and expand button)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
    btn.text:SetPoint("RIGHT", btn.expand, "LEFT", -4, 0)
    btn.text:SetJustifyH("LEFT")

    -- Selection background
    btn.selection = btn:CreateTexture(nil, "BACKGROUND")
    btn.selection:SetAllPoints(btn)
    btn.selection:SetColorTexture(0.4, 0.3, 0.6, 0.45)
    btn.selection:Hide()

    -- Hover highlight
    btn.hl = btn:CreateTexture(nil, "BACKGROUND")
    btn.hl:SetAllPoints(btn)
    btn.hl:SetColorTexture(0.25, 0.2, 0.35, 0.4)
    btn.hl:Hide()

    btn:SetScript("OnEnter", function(self)
        if not self.isSelected then self.hl:Show() end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local loadout = LO()[self.setName]
        if loadout then
            GameTooltip:AddLine(self.setName, 1, 0.82, 0)
            GameTooltip:AddLine(string.format("%d %s", countSlots(loadout), L["items"]),
                0.6, 0.6, 0.6)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Left-click: select"], 1, 1, 1)
            GameTooltip:AddLine(L["Double-click / Right-click menu: equip"], 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local setName = self.setName
            local menu = {
                { title = true, text = setName },
                { text = L["Equip"], func = function() equipLoadout(setName) end },
                { text = L["Overwrite"], func = function()
                    overwriteLoadout(setName)
                    refreshSidebar()
                end },
                { text = L["Change icon..."], func = function()
                    showIconPicker(setName, self)
                end },
            }

            -- Spec-binding entries — only when dual spec is active
            if getNumSpecGroups() >= 2 then
                table.insert(menu, { separator = true })
                for g = 1, getNumSpecGroups() do
                    local group = g
                    table.insert(menu, {
                        text    = string.format(L["Bind to %s"], getSpecGroupLabel(group)),
                        checked = function() return specMap() and specMap()[setName] == group end,
                        func    = function()
                            if specMap()[setName] == group then
                                -- toggle off
                                specMap()[setName] = nil
                                ns:Print(string.format(L["'%s' unbound from spec."], setName))
                            else
                                -- 1:1 — clear any other set on this group
                                for other, gi in pairs(specMap()) do
                                    if gi == group and other ~= setName then specMap()[other] = nil end
                                end
                                specMap()[setName] = group
                                ns:Print(string.format(L["'%s' bound to %s."], setName, getSpecGroupLabel(group)))
                            end
                        end,
                    })
                end
            end

            table.insert(menu, { separator = true })
            table.insert(menu, { text = L["Delete"], func = function()
                if mod.db.confirmDelete then
                    local dlg = StaticPopup_Show("VCUI_LOADOUT_DELETE", setName)
                    if dlg then dlg.data = setName end
                else
                    deleteLoadout(setName)
                    refreshSidebar()
                end
            end })

            ns:ShowPopupMenu(menu, self)
        else
            -- Detect double-click via timestamp
            local now = GetTime()
            if self._lastClick and (now - self._lastClick) < 0.35 then
                equipLoadout(self.setName)
                self._lastClick = 0
            else
                sidebarSelected = self.setName
                self._lastClick = now
                refreshSidebar()
            end
        end
    end)

    sidebarSetButtons[index] = btn
    return btn
end

-- =========================================================
-- Expanded item-row (grid of item icons under a set when expanded)
-- =========================================================
local ITEM_COLS = 6
local ITEM_SIZE = 26
local ITEM_PAD  = 3

local function getItemButton(row, idx)
    local b = row.items[idx]
    if b then return b end
    b = CreateFrame("Button", nil, row)
    b:SetSize(ITEM_SIZE, ITEM_SIZE)
    b.iconTex = b:CreateTexture(nil, "ARTWORK")
    b.iconTex:SetAllPoints(b)
    b.iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.iconBorder = b:CreateTexture(nil, "OVERLAY")
    b.iconBorder:SetAllPoints(b)
    b.iconBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.iconBorder:SetBlendMode("ADD")
    b.iconBorder:Hide()
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if self.link then
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        else
            local slotName = SLOT_NAMES[self.targetSlot] or ("Slot " .. tostring(self.targetSlot))
            GameTooltip:AddLine(string.format(L["Empty: %s"], slotName), 1, 0.82, 0)
            GameTooltip:AddLine(L["Left-click to pick an item from your bags"], 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
        self.iconBorder:Show()
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.iconBorder:Hide()
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- Quick-remove
            if self.loadoutName and self.targetSlot and LO()[self.loadoutName] then
                LO()[self.loadoutName].slots[self.targetSlot] = nil
                refreshSidebar()
            end
        else
            -- Left-click → bag-item picker for this slot
            if self.loadoutName and self.targetSlot then
                showSlotReplacePicker(self.loadoutName, self.targetSlot, self)
            end
        end
    end)
    row.items[idx] = b
    return b
end

local function getItemRow(parent, index)
    local row = sidebarItemRows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, parent)
    row.items = {}
    sidebarItemRows[index] = row
    return row
end

-- Default empty-slot placeholder texture
local EMPTY_SLOT_ICON = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

local function renderItemRow(row, loadoutName)
    local loadout = LO() and LO()[loadoutName]
    if not loadout then
        row:SetHeight(0)
        return
    end

    -- Hide leftover item buttons
    for _, b in ipairs(row.items) do b:Hide() end

    -- Build display order from slotMask (intended slots) — fall back to slot keys for old data
    local displaySlots = loadout.slotMask
    if not displaySlots or #displaySlots == 0 then
        displaySlots = {}
        for slot in pairs(loadout.slots or {}) do
            table.insert(displaySlots, slot)
        end
    end
    -- Sorted copy so display order is stable
    local sortedSlots = {}
    for _, s in ipairs(displaySlots) do table.insert(sortedSlots, s) end
    table.sort(sortedSlots)

    for i, slot in ipairs(sortedSlots) do
        local b = getItemButton(row, i)
        local link = loadout.slots and loadout.slots[slot]
        b.loadoutName = loadoutName
        b.targetSlot  = slot
        b.link        = link

        if link then
            local icon
            if GetItemInfoInstant then
                local _, _, _, _, ic = GetItemInfoInstant(link)
                icon = ic
            end
            b.iconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.iconTex:SetVertexColor(1, 1, 1)
        else
            -- Empty slot: show placeholder + dim color so it reads as "click to fill"
            b.iconTex:SetTexture(EMPTY_SLOT_ICON)
            b.iconTex:SetVertexColor(0.6, 0.6, 0.6)
        end

        local col = (i - 1) % ITEM_COLS
        local rowIdx = math.floor((i - 1) / ITEM_COLS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", row, "TOPLEFT",
            col * (ITEM_SIZE + ITEM_PAD),
            -(rowIdx * (ITEM_SIZE + ITEM_PAD)))
        b:Show()
    end

    local rows = math.max(1, math.ceil(#sortedSlots / ITEM_COLS))
    row:SetHeight(rows * (ITEM_SIZE + ITEM_PAD) + 2)
end

refreshSidebar = function()
    if not sidebar then return end

    -- Validate selection / expansion
    if sidebarSelected and not (LO() and LO()[sidebarSelected]) then
        sidebarSelected = nil
    end
    if sidebarExpanded and not (LO() and LO()[sidebarExpanded]) then
        sidebarExpanded = nil
    end

    -- Hide leftover buttons + item rows
    for _, b in ipairs(sidebarSetButtons) do b:Hide() end
    for _, r in ipairs(sidebarItemRows)   do r:Hide() end

    local names = sortedLoadoutNames()
    if not sidebarSelected and #names > 0 then sidebarSelected = names[1] end

    local y = -32  -- below action bar (which is at top)
    for i, name in ipairs(names) do
        local btn = createSetRow(sidebar, i)
        btn.setName = name
        btn.text:SetText(name)
        btn.icon:SetTexture(getSetIcon(name))
        btn.isSelected = (name == sidebarSelected)
        if btn.isSelected then
            btn.selection:Show()
            btn.text:SetTextColor(1, 0.82, 0)
        else
            btn.selection:Hide()
            btn.text:SetTextColor(1, 1, 1)
        end
        -- Expand button icon: up-arrow when expanded (collapse), down-arrow when collapsed
        if sidebarExpanded == name then
            btn.expand.icon:SetTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
        else
            btn.expand.icon:SetTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Up")
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  4, y)
        btn:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -4, y)
        btn:Show()
        y = y - 33

        -- If expanded, render the item icons below this row
        if sidebarExpanded == name then
            local row = getItemRow(sidebar, i)
            renderItemRow(row, name)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  6, y)
            row:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -6, y)
            row:Show()
            y = y - row:GetHeight() - 4
        end
    end

    if #names == 0 then
        if not sidebar.emptyText then
            sidebar.emptyText = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            sidebar.emptyText:SetPoint("TOP", sidebar, "TOP", 0, -48)
            sidebar.emptyText:SetTextColor(0.6, 0.6, 0.6)
            sidebar.emptyText:SetText(L["No loadouts saved yet."])
        end
        sidebar.emptyText:Show()
    elseif sidebar.emptyText then
        sidebar.emptyText:Hide()
    end

    -- Enable/disable action buttons
    if sidebar.equipBtn then
        if sidebarSelected then
            sidebar.equipBtn:Enable()
            sidebar.saveBtn:Enable()
        else
            sidebar.equipBtn:Disable()
            sidebar.saveBtn:Disable()
        end
    end
end

local function createSidebar()
    if sidebar then return sidebar end
    if not CharacterFrame then return end

    sidebar = CreateFrame("Frame", "VCUI_LoadoutsSidebar", CharacterFrame,
        BackdropTemplateMixin and "BackdropTemplate")
    sidebar:SetWidth(190)
    sidebar:SetFrameStrata("HIGH")
    sidebar:Hide()

    -- Anchor BOTH corners to CharacterFrame. This makes the sidebar height
    -- track the character window dynamically and exactly — whatever the real
    -- height is (even if another addon resizes CharacterFrame), top and bottom
    -- always line up. No GetHeight() snapshot that can be measured at the wrong
    -- time. The user-tunable offsets compensate if the frame bounds differ from
    -- the visible backdrop on a given client.
    local function anchorToCharacterFrame()
        if not sidebar or not CharacterFrame then return end
        local pos    = mod.db and mod.db.sidebarPos
        local px     = (pos and pos.x) or 0   -- edit-mode drag offset (x)
        local py     = (pos and pos.y) or 0   -- edit-mode drag offset (y)
        local topOff = ((mod.db and mod.db.sidebarTopOffset)    or 0) + py
        local botOff = ((mod.db and mod.db.sidebarBottomOffset) or 0) + py
        sidebar:ClearAllPoints()
        sidebar:SetPoint("TOPLEFT",    CharacterFrame, "TOPRIGHT", -4 + px, topOff)
        sidebar:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMRIGHT", -4 + px, botOff)
    end
    anchorToCharacterFrame()
    sidebar._reanchor = anchorToCharacterFrame
    mod._reanchorSidebar = anchorToCharacterFrame

    -- Debug: print real top/bottom/height of CharacterFrame vs the sidebar
    mod._debugSizes = function()
        local function dump(label, f)
            if not f then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s: |cffff5555nil|r", label))
                return
            end
            local top    = f.GetTop    and f:GetTop()
            local bottom = f.GetBottom and f:GetBottom()
            local height = f.GetHeight and f:GetHeight()
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "  %s: top=%s bottom=%s height=%s",
                label,
                top    and string.format("%.0f", top)    or "?",
                bottom and string.format("%.0f", bottom) or "?",
                height and string.format("%.0f", height) or "?"))
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff9b6cff[Loadouts size debug]|r")
        dump("CharacterFrame",      _G.CharacterFrame)
        dump("CharacterFrameInset", _G.CharacterFrameInset)
        dump("PaperDollFrame",      _G.PaperDollFrame)
        dump("Sidebar",             sidebar)
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  Offsets: top=%d bottom=%d",
            mod.db.sidebarTopOffset or 0, mod.db.sidebarBottomOffset or 0))
    end

    if sidebar.SetBackdrop then
        sidebar:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        sidebar:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        sidebar:SetBackdropBorderColor(0.4, 0.3, 0.6, 1)
    end

    -- Action buttons (top row)
    local equipBtn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    equipBtn:SetSize(86, 22)
    equipBtn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, -4)
    equipBtn:SetText(L["Equip"])
    equipBtn:SetScript("OnClick", function()
        if sidebarSelected then equipLoadout(sidebarSelected) end
    end)
    sidebar.equipBtn = equipBtn

    local saveBtn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    saveBtn:SetSize(86, 22)
    saveBtn:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -4, -4)
    saveBtn:SetText(L["Save"])
    saveBtn:SetScript("OnClick", function()
        if sidebarSelected then
            overwriteLoadout(sidebarSelected)
            refreshSidebar()
        end
    end)
    sidebar.saveBtn = saveBtn

    -- New Set button (bottom)
    local newBtn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    newBtn:SetSize(178, 24)
    newBtn:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, 4)
    newBtn:SetText("+ " .. L["New Set"])
    newBtn:SetScript("OnClick", function() promptSaveWithSlots(nil) end)
    sidebar.newBtn = newBtn

    -- Edit-mode mover: drag the sidebar to an offset from the character window.
    -- It STAYS anchored to CharacterFrame (keeps tracking the window height and
    -- shows/hides with it), so instead of the default screen-centre drag we store
    -- only an x/y offset and re-anchor live while dragging. Arrow keys + the
    -- right-click popup (incl. reset) work through applyPos = anchorToCharacterFrame.
    mod.db.sidebarPos = mod.db.sidebarPos or { x = 0, y = 0 }
    sidebar.mover = ns:CreateMover(sidebar, {
        label    = L["|cffffffffLOADOUTS SIDEBAR|r\n|cffaaaaaaDrag or arrow keys|r"],
        db       = mod.db.sidebarPos,
        width    = 168,
        height   = 44,
        applyPos = anchorToCharacterFrame,
    })
    sidebar.mover:SetFrameLevel((sidebar:GetFrameLevel() or 1) + 20)  -- above the set buttons
    do
        -- Replace the default screen-centre drag with offset tracking so the
        -- two-point anchor (and height tracking) is never broken.
        local mvr = sidebar.mover
        mvr:SetScript("OnDragStart", function(self)
            local cx, cy = GetCursorPosition()
            self._dragX, self._dragY = cx, cy
            self._origX, self._origY = mod.db.sidebarPos.x or 0, mod.db.sidebarPos.y or 0
            self:SetScript("OnUpdate", function()
                local nx, ny = GetCursorPosition()
                local s = UIParent:GetEffectiveScale()
                if s and s > 0 then
                    mod.db.sidebarPos.x = self._origX + (nx - self._dragX) / s
                    mod.db.sidebarPos.y = self._origY + (ny - self._dragY) / s
                    anchorToCharacterFrame()
                end
            end)
        end)
        mvr:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    end

    -- Hook CharacterFrame show/hide
    CharacterFrame:HookScript("OnShow", function()
        if mod._enabled and mod.db and mod.db.sidebarEnabled ~= false then
            sidebar:Show()
            anchorToCharacterFrame()  -- re-sync size in case CharacterFrame changed
            refreshSidebar()
            -- the mover only makes sense while the window is open; sync its state
            if sidebar.mover then
                if ns:IsMoverEditMode() then sidebar.mover:Show() else sidebar.mover:Hide() end
            end
        end
    end)
    CharacterFrame:HookScript("OnHide", function() sidebar:Hide() end)

    if ns:IsMoverEditMode() then sidebar.mover:Show() end
    return sidebar
end

local function applySidebarVisibility()
    if not sidebar then return end
    if mod.db.sidebarEnabled == false then
        sidebar:Hide()
    elseif CharacterFrame and CharacterFrame:IsShown() then
        sidebar:Show()
        refreshSidebar()
    end
end

-- Refresh sidebar after save/delete operations
local _origSaveAs    = saveAs
local _origDelete    = deleteLoadout
saveAs = function(name, slotList)
    _origSaveAs(name, slotList)
    if sidebar then
        sidebarSelected = name
        refreshSidebar()
    end
end
deleteLoadout = function(name)
    _origDelete(name)
    if sidebar then
        if sidebarSelected == name then sidebarSelected = nil end
        refreshSidebar()
    end
end

-- One-time migration: copy the old account-wide loadouts (mod.db.*) onto the
-- CURRENT character. Names that already exist on this character are skipped.
function mod.ImportLegacy()
    local legacy = mod.db and mod.db.loadouts
    if not (legacy and next(legacy)) then
        ns:Print(L["No account-wide loadouts to import."])
        return
    end
    local lo, n = LO(), 0
    for name, data in pairs(legacy) do
        if not lo[name] then
            lo[name] = (CopyTable and CopyTable(data)) or data
            n = n + 1
        end
    end
    for name, g in pairs(mod.db.specMapping or {}) do
        if not specMap()[name] then specMap()[name] = g end
    end
    for name, g in pairs(mod.db.formMapping or {}) do
        if not formMap()[name] then formMap()[name] = g end
    end
    ns:Print(string.format(L["Imported %d account-wide loadout(s) onto this character."], n))
    refreshSidebar()
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    if not mod.db then return end
    -- Ensure per-character tables exist (the accessors create them lazily)
    LO(); formMap(); specMap()
    mod.db.minimap     = mod.db.minimap     or { hidden = false, angle = -45 }

    -- Migration: legacy loadouts without slotMask → derive from currently saved slots
    for _, loadout in pairs(LO()) do
        if loadout and not loadout.slotMask then
            local mask = {}
            for slot in pairs(loadout.slots or {}) do
                table.insert(mask, slot)
            end
            table.sort(mask)
            loadout.slotMask = mask
        end
    end

    -- Migration: bump sidebar offsets from old 0/0 default to the tuned -14/45
    -- (one-time; users who deliberately set their own values keep them via the flag)
    if not mod.db._offsetMigrated then
        if (mod.db.sidebarTopOffset or 0) == 0 and (mod.db.sidebarBottomOffset or 0) == 0 then
            mod.db.sidebarTopOffset    = -14
            mod.db.sidebarBottomOffset = 45
        end
        mod.db._offsetMigrated = true
    end

    -- One-time hint (per character): this character has no loadouts yet, but the
    -- old account-wide pool still holds some (user upgrading from <= 1.8.0).
    -- Shown once per character so other chars don't get nagged every login.
    if not next(LO()) and not charDB()._importHintShown
       and mod.db.loadouts and next(mod.db.loadouts) then
        charDB()._importHintShown = true
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function()
                if not next(LO()) and mod.db.loadouts and next(mod.db.loadouts) then
                    ns:Print(L["You have account-wide loadouts from an older version. Type /lo import to copy them onto this character."])
                end
            end)
        end
    end

    -- Create minimap button (deferred so Minimap definitely exists)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, createMinimapButton)
        C_Timer.After(0.5, createSidebar)
    else
        createMinimapButton()
        createSidebar()
    end

    -- Hook stance/form events
    ns:RegisterEvent("UPDATE_SHAPESHIFT_FORM",  onShapeshiftChange)
    ns:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", onShapeshiftChange)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",    onShapeshiftChange)  -- retry leaving combat

    -- Hook every plausible dual-spec event — Anniversary builds vary on which
    -- one actually fires. Plus a 2s polling fallback (startSpecPolling) covers
    -- builds where none of them fire reliably.
    ns:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", onTalentChange)
    ns:RegisterEvent("PLAYER_TALENT_UPDATE",        onTalentChange)
    ns:RegisterEvent("CHARACTER_POINTS_CHANGED",    onTalentChange)
    ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", onTalentChange)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD",       onTalentChange)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",        onTalentChange)  -- retry after combat

    _lastForm = getCurrentForm()
    -- Defer initial spec read — spec group may not be available immediately on login
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function() _lastSpecGroup = getActiveSpecGroup() end)
    end
    startSpecPolling()
end

function mod:OnDisable()
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORM",  onShapeshiftChange)
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS", onShapeshiftChange)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",    onShapeshiftChange)
    ns:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED", onTalentChange)
    ns:UnregisterEvent("PLAYER_TALENT_UPDATE",        onTalentChange)
    ns:UnregisterEvent("CHARACTER_POINTS_CHANGED",    onTalentChange)
    ns:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED", onTalentChange)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD",       onTalentChange)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",        onTalentChange)
    if _specPoller then _specPoller:Cancel(); _specPoller = nil end
    if mmBtn then mmBtn:Hide() end
end

-- =========================================================
-- Options UI
-- =========================================================
-- Build a list of available form indices for dropdown values
local function buildFormDropdownValues()
    local values = { { value = 0, text = L["None"] } }
    -- Add all known shapeshift forms (max 6 in Anniversary classes)
    local numForms = (GetNumShapeshiftForms and GetNumShapeshiftForms()) or 0
    for i = 1, numForms do
        table.insert(values, { value = i, text = getFormName(i) })
    end
    return values
end

-- Build a list of spec groups (dual-spec) for dropdown values
local function buildSpecDropdownValues()
    local values = { { value = 0, text = L["None"] } }
    local numGroups = getNumSpecGroups()
    for g = 1, numGroups do
        table.insert(values, { value = g, text = getSpecGroupLabel(g) })
    end
    return values
end

function mod:GetOptions()
    local items = {
        { type = "header", text = L["Loadouts"] },
        { type = "desc", text = L["Save your current equipment as named gear sets and quickly switch between them. Equipping requires you to be out of combat — items in your bags are auto-equipped via Use."] },

        { type = "spacer", height = 6 },
        { type = "group", layout = "row", gap = 6,
          items = {
              { type = "button", label = L["Save All..."], width = 130,
                onClick = function() promptSaveWithSlots(nil) end },
              { type = "button", label = L["Save Trinkets..."], width = 130,
                onClick = function() promptSaveWithSlots(SLOT_GROUPS.trinkets) end },
              { type = "button", label = L["Save Weapons..."], width = 130,
                onClick = function() promptSaveWithSlots(SLOT_GROUPS.weapons) end },
          },
        },
        { type = "toggle", label = L["Confirm before deleting a loadout"],
          get = function() return mod.db.confirmDelete ~= false end,
          set = function(_, v) mod.db.confirmDelete = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Character Frame Sidebar"] },
        { type = "toggle", label = L["Show sidebar on character frame"],
          tooltip = L["Attach a quick-access sidebar to the right of the character window. Click a set to select, double-click or button to equip, right-click for context menu."],
          get = function() return mod.db.sidebarEnabled ~= false end,
          set = function(_, v)
              mod.db.sidebarEnabled = v
              applySidebarVisibility()
          end },
        { type = "desc", text = L["|cffaaaaaaTip: with the character window open, enable edit mode (Unlock) to drag the sidebar; right-click the purple box to reset its position.|r"] },

        -- Slot Picker (formerly its own module, now integrated here)
        { type = "spacer", height = 6 },
        { type = "section", title = L["Slot Picker"], collapsed = false, items = {
            { type = "desc", text = L["|cffaaaaaaRight-click an equipment slot in the character window to see all compatible items from your bags and click one to equip it.|r"] },
            { type = "toggle", label = L["Enable slot picker"],
              get = function() return ns:IsModuleEnabled("slotpicker") end,
              set = function(_, v) if ns.ToggleModule then ns:ToggleModule("slotpicker", v) end end },
            { type = "dropdown", label = L["Activation modifier"],
              tooltip = L["Choose which key combination opens the item picker when you click an equipment slot."],
              values = {
                  { value = "right",       text = L["Right-click only"] },
                  { value = "shift-right", text = L["Shift + Right-click"] },
                  { value = "alt-right",   text = L["Alt + Right-click"] },
                  { value = "ctrl-right",  text = L["Ctrl + Right-click"] },
              },
              get = function() local sp = ns.modules and ns.modules.slotpicker; return (sp and sp.db and sp.db.modifier) or "right" end,
              set = function(_, v) local sp = ns.modules and ns.modules.slotpicker; if sp and sp.db then sp.db.modifier = v end end },
            { type = "slider", label = L["Grid columns"],
              tooltip = L["How many item icons per row in the picker popup."],
              min = 4, max = 14, step = 1,
              get = function() local sp = ns.modules and ns.modules.slotpicker; return (sp and sp.db and sp.db.cols) or 8 end,
              set = function(_, v) local sp = ns.modules and ns.modules.slotpicker; if sp and sp.db then sp.db.cols = v end end },
        } },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Minimap Button"] },
        { type = "toggle", label = L["Show minimap button"],
          tooltip = L["Left-click for a quick set-switcher menu, right-click to open settings, drag to reposition."],
          get = function() return not (mod.db.minimap and mod.db.minimap.hidden) end,
          set = function(_, v)
              mod.db.minimap = mod.db.minimap or {}
              mod.db.minimap.hidden = not v
              applyMinimapVisibility()
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Auto-Switch on Dual Spec"] },
        { type = "toggle", label = L["Enable spec auto-switching"],
          tooltip = L["Automatically equips a loadout when you switch between Spec 1 and Spec 2 (dual spec). Bind each loadout to a spec below. Requires dual spec to be active."],
          get = function() return mod.db.specSwitchEnabled ~= false end,
          set = function(_, v) mod.db.specSwitchEnabled = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Auto-Switch on Stance/Form"] },
        { type = "toggle", label = L["Enable auto-switching"],
          tooltip = L["Automatically equips a loadout when your stance/form changes (warrior stances, druid forms). Out-of-combat only — if a stance change happens in combat, the swap is deferred until combat ends."],
          get = function() return mod.db.autoSwitchEnabled ~= false end,
          set = function(_, v) mod.db.autoSwitchEnabled = v end },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Saved Loadouts"] },
    }

    -- Legacy import (upgraders from <= 1.8.0): only shown while old account-wide
    -- loadouts still exist. Loadouts are now per-character, so this copies the
    -- old shared sets onto THIS character. Inserted at the top (after header+desc).
    if mod.db.loadouts and next(mod.db.loadouts) then
        table.insert(items, 3, { type = "section", title = L["Import from older version"], collapsed = false, items = {
            { type = "desc", text = L["|cffaaaaaaYou have gear sets saved account-wide by an older version. Loadouts are now per-character — import copies them onto THIS character.|r"] },
            { type = "button", label = L["Import account-wide loadouts"], width = 240,
              onClick = function() mod.ImportLegacy() end },
        } })
    end

    local names = sortedLoadoutNames()
    if #names == 0 then
        table.insert(items, { type = "desc", text = L["|cffaaaaaaNo loadouts saved yet. Use the button above to save your current gear.|r"] })
    else
        local formValues = buildFormDropdownValues()
        local hasForms = #formValues > 1  -- 1 = only "None" → no stance class
        local specValues = buildSpecDropdownValues()
        local hasSpecs = getNumSpecGroups() >= 2  -- only show when dual spec is active

        for _, name in ipairs(names) do
            local capturedName = name  -- closure capture
            local slotCount = countSlots(LO()[name])

            -- Row 1: name + item count (full width, separate line)
            table.insert(items, { type = "desc",
                text = string.format("|cffffd100%s|r |cff888888(%d %s)|r",
                    name, slotCount, L["items"]) })

            -- Row 2: action buttons (under the name, fits properly in content width)
            table.insert(items, { type = "group", layout = "row", gap = 6,
                items = {
                    { type = "button", label = L["Equip"], width = 100,
                      onClick = function() equipLoadout(capturedName) end },
                    { type = "button", label = L["Overwrite"], width = 130,
                      onClick = function() overwriteLoadout(capturedName) end },
                    { type = "button", label = L["Delete"], width = 100,
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

            -- Row 3: Auto-equip on talent spec dropdown
            if hasSpecs then
                table.insert(items, { type = "dropdown",
                    label = L["Auto-equip on spec"],
                    tooltip = L["Equip this loadout automatically when you switch to this spec."],
                    values = specValues,
                    get = function() return (specMap() and specMap()[capturedName]) or 0 end,
                    set = function(_, v)
                        -- 1:1 mapping — clear any other loadout on this spec tab
                        if v and v ~= 0 then
                            for other, tabIdx in pairs(specMap()) do
                                if tabIdx == v and other ~= capturedName then
                                    specMap()[other] = nil
                                end
                            end
                        end
                        specMap()[capturedName] = (v ~= 0) and v or nil
                    end,
                })
            end

            -- Row 4: Auto-equip on form dropdown (only show if class has forms)
            if hasForms then
                table.insert(items, { type = "dropdown",
                    label = L["Auto-equip on form"],
                    tooltip = L["Equip this loadout automatically when the chosen stance/form is activated."],
                    values = formValues,
                    get = function() return (formMap() and formMap()[capturedName]) or 0 end,
                    set = function(_, v)
                        -- Clear any other loadout currently mapped to this form (1:1 mapping)
                        if v and v ~= 0 then
                            for other, formIdx in pairs(formMap()) do
                                if formIdx == v and other ~= capturedName then
                                    formMap()[other] = nil
                                end
                            end
                        end
                        formMap()[capturedName] = (v ~= 0) and v or nil
                    end,
                })
            end

            -- Separator before next loadout
            table.insert(items, { type = "spacer", height = 4 })
        end
    end

    table.insert(items, { type = "spacer", height = 8 })
    table.insert(items, { type = "desc", text = L["|cffaaaaaaSlash commands: /loadout save <name>, /loadout equip <name>, /loadout delete <name>, /loadout list. Short alias: /lo|r"] })

    return items
end
