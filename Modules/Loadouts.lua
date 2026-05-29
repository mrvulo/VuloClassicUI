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
        loadouts      = {},   -- { [name] = { slots = { [slotID] = itemLink, ... }, createdAt = epoch, formIdx = nil } }
        confirmDelete = true,
        -- Minimap button
        minimap = { hidden = false, angle = 45 },
        -- Auto-switch on stance/form change: [formIndex] = "loadoutName"
        autoSwitchEnabled = true,
        formMapping       = {},
        -- Character-frame sidebar
        sidebarEnabled    = true,
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
local function saveAs(name, slotList)
    if not name or name == "" then
        ns:Print(L["Please provide a name for the loadout."])
        return
    end
    mod.db.loadouts[name] = {
        slots     = captureCurrentEquipment(slotList),
        createdAt = time(),
    }
    ns:Print(string.format(L["Loadout '%s' saved (%d items)."],
        name, countSlots(mod.db.loadouts[name])))
end

-- Pending slot list for the StaticPopup (popups have no parameter passing on Show)
local _pendingSaveSlots = nil

local function promptSaveWithSlots(slotList)
    _pendingSaveSlots = slotList
    StaticPopup_Show("VCUI_LOADOUT_SAVE")
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
    if not UseContainerItem and not _G.EquipItemByName then
        ns:Print(L["Equipment swap API not available on this client."])
        return
    end

    local swapped, missing = 0, 0
    -- Two-pass strategy:
    --   Pass 1 — for symmetric slots (rings 11/12, trinkets 13/14),
    --            UseContainerItem always picks slot 11 / 13 → wrong.
    --            We use EquipItemByName(link, targetSlot) which respects the slot.
    --   Pass 2 — for everything else, UseContainerItem is fine (only one valid slot).
    for slot, link in pairs(loadout.slots) do
        local currentLink = GetInventoryItemLink("player", slot)
        if currentLink ~= link then
            local itemID = getItemIDFromLink(link)
            if itemID then
                local bag, bagSlot = findItemInBags(itemID)
                if bag and bagSlot then
                    -- Prefer EquipItemByName with explicit slot — it's the only API
                    -- that lets us target slot 12 or 14 specifically.
                    if _G.EquipItemByName then
                        pcall(_G.EquipItemByName, link, slot)
                    else
                        pcall(UseContainerItem, bag, bagSlot)
                    end
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
        GameTooltip:AddLine("|cff9b6cffLoadouts|r")
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
        local _, name = pcall(GetShapeshiftFormInfo, formIdx)
        if type(name) == "string" and name ~= "" then return name end
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
    if not mod.db.formMapping then return end
    for loadoutName, formIdx in pairs(mod.db.formMapping) do
        if formIdx == currentForm and mod.db.loadouts[loadoutName] then
            equipLoadout(loadoutName)
            return
        end
    end
end

-- =========================================================
-- Character-frame sidebar (ItemRack-style)
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

    local results  = ns:ScanBagsForSlot(targetSlot)
    local slotName = SLOT_NAMES[targetSlot] or ("Slot " .. targetSlot)
    local entries  = {
        { title = true, text = string.format(L["Replace: %s"], slotName) },
    }

    local GetContainerItemLink_ = (C_Container and C_Container.GetContainerItemLink) or _G.GetContainerItemLink
    if #results == 0 then
        table.insert(entries, { text = L["No matching items in your bags."], disabled = true })
    else
        for _, entry in ipairs(results) do
            local link = GetContainerItemLink_ and GetContainerItemLink_(entry.bag, entry.slot)
            if link then
                local capturedLink = link
                local itemName     = link:match("|h%[(.-)%]|h") or link
                table.insert(entries, {
                    text = "  " .. itemName,
                    func = function()
                        if mod.db.loadouts[loadoutName] then
                            mod.db.loadouts[loadoutName].slots[targetSlot] = capturedLink
                            refreshSidebar()
                            ns:Print(string.format(L["Loadout '%s': slot updated."], loadoutName))
                        end
                    end,
                })
            end
        end
    end

    table.insert(entries, { separator = true })
    table.insert(entries, { text = L["Remove from set"], func = function()
        if mod.db.loadouts[loadoutName] then
            mod.db.loadouts[loadoutName].slots[targetSlot] = nil
            refreshSidebar()
        end
    end })

    ns:ShowPopupMenu(entries, anchor)
end

local function getSetIcon(name)
    local loadout = mod.db and mod.db.loadouts and mod.db.loadouts[name]
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
        local loadout = mod.db.loadouts[self.setName]
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
            ns:ShowPopupMenu({
                { title = true, text = self.setName },
                { text = L["Equip"], func = function() equipLoadout(self.setName) end },
                { text = L["Overwrite"], func = function()
                    local oldSlots = mod.db.loadouts[self.setName].slots or {}
                    local slotList = {}
                    for s in pairs(oldSlots) do table.insert(slotList, s) end
                    mod.db.loadouts[self.setName] = {
                        slots     = captureCurrentEquipment(#slotList > 0 and slotList or nil),
                        createdAt = time(),
                    }
                    ns:Print(string.format(L["Loadout '%s' updated with current gear."], self.setName))
                    refreshSidebar()
                end },
                { separator = true },
                { text = L["Delete"], func = function()
                    if mod.db.confirmDelete then
                        local dlg = StaticPopup_Show("VCUI_LOADOUT_DELETE", self.setName)
                        if dlg then dlg.data = self.setName end
                    else
                        deleteLoadout(self.setName)
                        refreshSidebar()
                    end
                end },
            }, self)
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
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
            GameTooltip:Show()
        end
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
            if self.loadoutName and self.targetSlot and mod.db.loadouts[self.loadoutName] then
                mod.db.loadouts[self.loadoutName].slots[self.targetSlot] = nil
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

local function renderItemRow(row, loadoutName)
    local loadout = mod.db.loadouts and mod.db.loadouts[loadoutName]
    if not loadout or not loadout.slots then
        row:SetHeight(0)
        return
    end

    -- Hide leftover item buttons
    for _, b in ipairs(row.items) do b:Hide() end

    -- Sort slots ascending for consistent display
    local slotEntries = {}
    for slot, link in pairs(loadout.slots) do
        table.insert(slotEntries, { slot = slot, link = link })
    end
    table.sort(slotEntries, function(a, b) return a.slot < b.slot end)

    for i, entry in ipairs(slotEntries) do
        local b = getItemButton(row, i)
        b.loadoutName = loadoutName
        b.targetSlot  = entry.slot
        b.link        = entry.link
        local icon
        if GetItemInfoInstant then
            local _, _, _, _, ic = GetItemInfoInstant(entry.link)
            icon = ic
        end
        b.iconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        local col = (i - 1) % ITEM_COLS
        local rowIdx = math.floor((i - 1) / ITEM_COLS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", row, "TOPLEFT",
            col * (ITEM_SIZE + ITEM_PAD),
            -(rowIdx * (ITEM_SIZE + ITEM_PAD)))
        b:Show()
    end

    local rows = math.max(1, math.ceil(#slotEntries / ITEM_COLS))
    row:SetHeight(rows * (ITEM_SIZE + ITEM_PAD) + 2)
end

refreshSidebar = function()
    if not sidebar then return end

    -- Validate selection / expansion
    if sidebarSelected and not (mod.db.loadouts and mod.db.loadouts[sidebarSelected]) then
        sidebarSelected = nil
    end
    if sidebarExpanded and not (mod.db.loadouts and mod.db.loadouts[sidebarExpanded]) then
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
    sidebar:SetPoint("TOPLEFT",    CharacterFrame, "TOPRIGHT", -4, -12)
    sidebar:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMRIGHT", -4, 28)
    sidebar:SetFrameStrata("HIGH")
    sidebar:Hide()

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
            local oldSlots = mod.db.loadouts[sidebarSelected].slots or {}
            local slotList = {}
            for s in pairs(oldSlots) do table.insert(slotList, s) end
            mod.db.loadouts[sidebarSelected] = {
                slots     = captureCurrentEquipment(#slotList > 0 and slotList or nil),
                createdAt = time(),
            }
            ns:Print(string.format(L["Loadout '%s' updated with current gear."], sidebarSelected))
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

    -- Hook CharacterFrame show/hide
    CharacterFrame:HookScript("OnShow", function()
        if mod._enabled and mod.db and mod.db.sidebarEnabled ~= false then
            sidebar:Show()
            refreshSidebar()
        end
    end)
    CharacterFrame:HookScript("OnHide", function() sidebar:Hide() end)

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

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    if not mod.db then return end
    -- Defensive: ensure tables exist even if profile is fresh
    mod.db.loadouts    = mod.db.loadouts    or {}
    mod.db.formMapping = mod.db.formMapping or {}
    mod.db.minimap     = mod.db.minimap     or { hidden = false, angle = -45 }

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

    _lastForm = getCurrentForm()
end

function mod:OnDisable()
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORM",  onShapeshiftChange)
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS", onShapeshiftChange)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",    onShapeshiftChange)
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
        { type = "header", text = L["Auto-Switch on Stance/Form"] },
        { type = "toggle", label = L["Enable auto-switching"],
          tooltip = L["Automatically equips a loadout when your stance/form changes (warrior stances, druid forms). Out-of-combat only — if a stance change happens in combat, the swap is deferred until combat ends."],
          get = function() return mod.db.autoSwitchEnabled ~= false end,
          set = function(_, v) mod.db.autoSwitchEnabled = v end },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Saved Loadouts"] },
    }

    local names = sortedLoadoutNames()
    if #names == 0 then
        table.insert(items, { type = "desc", text = L["|cffaaaaaaNo loadouts saved yet. Use the button above to save your current gear.|r"] })
    else
        local formValues = buildFormDropdownValues()
        local hasForms = #formValues > 1  -- 1 = only "None" → no stance class

        for _, name in ipairs(names) do
            local capturedName = name  -- closure capture
            local slotCount = countSlots(mod.db.loadouts[name])

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
                      onClick = function()
                          -- Preserve the original slot mask when overwriting
                          local oldSlots = mod.db.loadouts[capturedName].slots or {}
                          local slotList = {}
                          for s in pairs(oldSlots) do table.insert(slotList, s) end
                          mod.db.loadouts[capturedName] = {
                              slots     = captureCurrentEquipment(#slotList > 0 and slotList or nil),
                              createdAt = time(),
                          }
                          ns:Print(string.format(L["Loadout '%s' updated with current gear."], capturedName))
                      end },
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

            -- Row 3: Auto-equip on form dropdown (only show if class has forms)
            if hasForms then
                table.insert(items, { type = "dropdown",
                    label = L["Auto-equip on form"],
                    tooltip = L["Equip this loadout automatically when the chosen stance/form is activated."],
                    values = formValues,
                    get = function() return (mod.db.formMapping and mod.db.formMapping[capturedName]) or 0 end,
                    set = function(_, v)
                        mod.db.formMapping = mod.db.formMapping or {}
                        -- Clear any other loadout currently mapped to this form (1:1 mapping)
                        if v and v ~= 0 then
                            for other, formIdx in pairs(mod.db.formMapping) do
                                if formIdx == v and other ~= capturedName then
                                    mod.db.formMapping[other] = nil
                                end
                            end
                        end
                        mod.db.formMapping[capturedName] = (v ~= 0) and v or nil
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
