-- =========================================================
-- VuloClassicUI / Modules / SlotPicker
-- Shift+Right-click on a character equipment slot → popup with all
-- compatible items from your bags. Click an item to equip it.
--
-- Equipping uses UseContainerItem (works out-of-combat in Anniversary,
-- same approach as Loadouts).
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("slotpicker", {
    name        = L["Slot Picker"],
    group       = "QoL",
    description = L["Shift+Right-click an equipment slot to show all compatible items from your bags. Click to equip."],
    defaults = {
        enabled  = true,
        modifier = "right",  -- "right" | "shift-right" | "alt-right" | "ctrl-right"
        cols     = 8,
    },
})

-- =========================================================
-- API compat
-- =========================================================
local GetContainerItemID    = (C_Container and C_Container.GetContainerItemID)    or _G.GetContainerItemID
local GetContainerItemLink  = (C_Container and C_Container.GetContainerItemLink)  or _G.GetContainerItemLink
local GetContainerNumSlots  = (C_Container and C_Container.GetContainerNumSlots)  or _G.GetContainerNumSlots
local UseContainerItem      = (C_Container and C_Container.UseContainerItem)      or _G.UseContainerItem
local GetItemInfoInstant    = _G.GetItemInfoInstant

-- =========================================================
-- Slot → INVTYPE mapping
-- =========================================================
-- For each character slot ID, which INVTYPEs are valid?
local SLOT_INVTYPES = {
    [1]  = { INVTYPE_HEAD     = true },
    [2]  = { INVTYPE_NECK     = true },
    [3]  = { INVTYPE_SHOULDER = true },
    [5]  = { INVTYPE_CHEST    = true, INVTYPE_ROBE = true },
    [6]  = { INVTYPE_WAIST    = true },
    [7]  = { INVTYPE_LEGS     = true },
    [8]  = { INVTYPE_FEET     = true },
    [9]  = { INVTYPE_WRIST    = true },
    [10] = { INVTYPE_HAND     = true },
    [11] = { INVTYPE_FINGER   = true },
    [12] = { INVTYPE_FINGER   = true },
    [13] = { INVTYPE_TRINKET  = true },
    [14] = { INVTYPE_TRINKET  = true },
    [15] = { INVTYPE_CLOAK    = true },
    [16] = { INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true },
    [17] = { INVTYPE_WEAPONOFFHAND  = true, INVTYPE_WEAPON = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true },
    [18] = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true },
}

-- Map slot ID → character-frame name suffix (so we can hook the right button)
local SLOT_FRAME_NAMES = {
    [1]  = "Head",    [2]  = "Neck",     [3]  = "Shoulder", [15] = "Back",
    [5]  = "Chest",   [9]  = "Wrist",    [10] = "Hands",    [6]  = "Waist",
    [7]  = "Legs",    [8]  = "Feet",
    [11] = "Finger0", [12] = "Finger1",
    [13] = "Trinket0",[14] = "Trinket1",
    [16] = "MainHand", [17] = "SecondaryHand", [18] = "Ranged",
}

-- =========================================================
-- Modifier check
-- =========================================================
local function checkModifier(button)
    local mode = mod.db.modifier or "right"
    if mode == "right" then
        return button == "RightButton"
    elseif mode == "shift-right" then
        return button == "RightButton" and IsShiftKeyDown()
    elseif mode == "alt-right" then
        return button == "RightButton" and IsAltKeyDown()
    elseif mode == "ctrl-right" then
        return button == "RightButton" and IsControlKeyDown()
    end
    return false
end

-- =========================================================
-- Scan bags for items matching a slot
-- Exposed as ns:ScanBagsForSlot so other modules (Loadouts) can reuse it
-- =========================================================
local function scanBagsForSlot(slotID)
    local validTypes = SLOT_INVTYPES[slotID]
    if not validTypes or not GetContainerNumSlots or not GetItemInfoInstant then
        return {}
    end

    local results = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local itemID
            if GetContainerItemID then
                itemID = GetContainerItemID(bag, slot)
            elseif GetContainerItemLink then
                local link = GetContainerItemLink(bag, slot)
                if link then itemID = tonumber(link:match("item:(%d+)")) end
            end
            if itemID then
                local _, _, _, equipLoc, icon = GetItemInfoInstant(itemID)
                if equipLoc and validTypes[equipLoc] then
                    table.insert(results, {
                        bag    = bag,
                        slot   = slot,
                        itemID = itemID,
                        icon   = icon,
                    })
                end
            end
        end
    end
    return results
end

-- =========================================================
-- Popup with item grid
-- =========================================================
local popup
local itemButtons = {}
local BTN_SIZE = 36

local function createPopup()
    if popup then return popup end
    popup = CreateFrame("Frame", "VCUI_SlotPickerPopup", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")
    popup:SetFrameStrata("DIALOG")
    popup:SetSize(360, 80)
    popup:Hide()
    popup:EnableMouse(true)
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    if popup.SetBackdrop then
        popup:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        popup:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        popup:SetBackdropBorderColor(0.4, 0.3, 0.6, 1)
    end
    tinsert(UISpecialFrames, "VCUI_SlotPickerPopup")

    -- Draggable via title bar
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, -6)
    title:SetTextColor(1, 0.82, 0)
    popup.title = title

    -- Close button (X)
    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Drag area = title bar (top 24px)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

    return popup
end

local function getItemButton(idx)
    local btn = itemButtons[idx]
    if btn then return btn end
    btn = CreateFrame("Button", nil, popup, "ItemButtonTemplate")
    if not btn.icon then
        -- Fallback in case ItemButtonTemplate doesn't expose .icon
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints(btn)
    end
    btn:SetSize(BTN_SIZE, BTN_SIZE)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnEnter", function(self)
        if self.bag and self.slot then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetBagItem(self.bag, self.slot)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function(self, button)
        if InCombatLockdown() then
            ns:Print(L["Cannot change equipment in combat."])
            return
        end
        if button == "LeftButton" and self.bag and self.slot and UseContainerItem then
            pcall(UseContainerItem, self.bag, self.slot)
            popup:Hide()
        end
    end)
    itemButtons[idx] = btn
    return btn
end

local function showSlotPicker(slotID)
    if not GetItemInfoInstant then
        ns:Print(L["Item scanning API not available on this client."])
        return
    end

    createPopup()

    local results = scanBagsForSlot(slotID)
    local slotName = SLOT_FRAME_NAMES[slotID] or string.format("Slot %d", slotID)
    popup.title:SetText(string.format(L["Items for: %s"], slotName)
        .. string.format(" |cff888888(%d)|r", #results))

    -- Hide leftover buttons
    for _, b in ipairs(itemButtons) do b:Hide() end

    if #results == 0 then
        popup:SetSize(280, 60)
        -- Show "no items" message inline
        if not popup.noItemsText then
            popup.noItemsText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            popup.noItemsText:SetPoint("CENTER", popup, "CENTER", 0, -8)
            popup.noItemsText:SetTextColor(0.7, 0.7, 0.7)
        end
        popup.noItemsText:SetText(L["No matching items in your bags."])
        popup.noItemsText:Show()
    else
        if popup.noItemsText then popup.noItemsText:Hide() end

        local cols = mod.db.cols or 8
        local rows = math.ceil(#results / cols)
        local padding   = 8
        local gridStart = 28  -- below title bar
        local btnPad    = 4

        local width  = cols * (BTN_SIZE + btnPad) - btnPad + padding * 2
        local height = gridStart + rows * (BTN_SIZE + btnPad) - btnPad + padding

        popup:SetSize(math.max(width, 180), height)

        for i, entry in ipairs(results) do
            local btn = getItemButton(i)
            btn:Show()
            btn.bag    = entry.bag
            btn.slot   = entry.slot
            btn.itemID = entry.itemID

            -- Set icon
            local iconTex = entry.icon
            if not iconTex then
                local _, _, _, _, ic = GetItemInfoInstant(entry.itemID)
                iconTex = ic
            end
            if btn.icon and iconTex then
                btn.icon:SetTexture(iconTex)
            end
            if _G[btn:GetName() and (btn:GetName() .. "IconTexture")] then
                _G[btn:GetName() .. "IconTexture"]:SetTexture(iconTex)
            end
            if SetItemButtonTexture then
                pcall(SetItemButtonTexture, btn, iconTex)
            end

            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", popup, "TOPLEFT",
                padding + col * (BTN_SIZE + btnPad),
                -(gridStart + row * (BTN_SIZE + btnPad)))
        end
    end

    -- Position next to the character frame
    popup:ClearAllPoints()
    if CharacterFrame and CharacterFrame:IsShown() then
        popup:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 4, 0)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    popup:Show()
end

-- Public API — Loadouts uses this to populate its expandable item picker
function ns:ScanBagsForSlot(slotID)
    return scanBagsForSlot(slotID)
end

-- =========================================================
-- Hook character slot buttons
-- =========================================================
local _hooked = false

local function hookSlots()
    if _hooked then return end
    for slotID, frameName in pairs(SLOT_FRAME_NAMES) do
        local slotBtn = _G["Character" .. frameName .. "Slot"]
        if slotBtn then
            slotBtn:HookScript("OnClick", function(self, button)
                if not mod._enabled then return end
                if checkModifier(button) then
                    showSlotPicker(slotID)
                end
            end)
        end
    end
    _hooked = true
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    if not mod.db then return end

    -- One-time migration: previous default modifier was "shift-right".
    -- Switch existing users to the new "right" default. If a user actively
    -- prefers shift/alt/ctrl, they can change it back in the dropdown.
    if not mod.db._defaultMigrated_v2 then
        if mod.db.modifier == "shift-right" then
            mod.db.modifier = "right"
        end
        mod.db._defaultMigrated_v2 = true
    end

    hookSlots()
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = L["Slot Picker"] },
        { type = "desc", text = L["Modifier-click an equipment slot in the Character frame to open a popup with all compatible items from your bags. Click an item to equip it (out-of-combat)."] },

        { type = "spacer", height = 6 },
        { type = "dropdown", label = L["Activation modifier"],
          tooltip = L["Choose which key combination opens the item picker when you click an equipment slot."],
          values = {
              { value = "right",       text = L["Right-click only"] },
              { value = "shift-right", text = L["Shift + Right-click"] },
              { value = "alt-right",   text = L["Alt + Right-click"] },
              { value = "ctrl-right",  text = L["Ctrl + Right-click"] },
          },
          get = function() return mod.db.modifier or "right" end,
          set = function(_, v) mod.db.modifier = v end },

        { type = "slider", label = L["Grid columns"],
          tooltip = L["How many item icons per row in the picker popup."],
          min = 4, max = 14, step = 1,
          get = function() return mod.db.cols or 8 end,
          set = function(_, v) mod.db.cols = v end },
    }
end
