-- Equipment slot flyout / picker; settings are surfaced on the Loadouts page, hence group "_hidden".
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("slotpicker", {
    name        = "Slot Picker",
    group       = "_hidden",
    description = "Hover an equipment slot for a compact flyout of compatible bag items, or modifier-click for a larger picker. Click an item to equip it.",
    defaults = {
        enabled     = true,
        hoverFlyout = true,
        modifier    = "right",  -- "right" | "shift-right" | "alt-right" | "ctrl-right"
        cols        = 8,
        autoClose   = true,
    },
})

-- C_Container namespace on newer clients, globals on older ones
local GetContainerItemID    = (C_Container and C_Container.GetContainerItemID)    or _G.GetContainerItemID
local GetContainerItemLink  = (C_Container and C_Container.GetContainerItemLink)  or _G.GetContainerItemLink
local GetContainerNumSlots  = (C_Container and C_Container.GetContainerNumSlots)  or _G.GetContainerNumSlots
local UseContainerItem      = (C_Container and C_Container.UseContainerItem)      or _G.UseContainerItem
local GetItemInfoInstant    = _G.GetItemInfoInstant
local EquipItemByName       = (C_Item and C_Item.EquipItemByName)                or _G.EquipItemByName

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

-- The three weapon slots are the only ones that sit in a ROW, at the bottom of
-- the paper doll. A flyout beside them lands on their own neighbours: two icons
-- for the main hand covered the off hand and the ranged slot. These open
-- downward instead. The column slots keep the sideways opening -- there, beside
-- them is the only direction that is free.
local DOWNWARD_SLOTS = { [16] = true, [17] = true, [18] = true }

local SLOT_FRAME_NAMES = {
    [1]  = "Head",    [2]  = "Neck",     [3]  = "Shoulder", [15] = "Back",
    [5]  = "Chest",   [9]  = "Wrist",    [10] = "Hands",    [6]  = "Waist",
    [7]  = "Legs",    [8]  = "Feet",
    [11] = "Finger0", [12] = "Finger1",
    [13] = "Trinket0",[14] = "Trinket1",
    [16] = "MainHand", [17] = "SecondaryHand", [18] = "Ranged",
}

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

    local UI = ns.UI
    if UI and UI.StyleBackdrop then
        UI:StyleBackdrop(popup, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border })
    elseif popup.SetBackdrop then
        popup:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        popup:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        popup:SetBackdropBorderColor(0.4, 0.3, 0.6, 1)
    end
    if UI and UI.CreateShadow then UI:CreateShadow(popup) end
    local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
    local strip = popup:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    if UI and UI.SetGradient then
        UI.SetGradient(strip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)
    end
    tinsert(UISpecialFrames, "VCUI_SlotPickerPopup")

    -- must exist before the title: the title anchors its RIGHT edge to this button
    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)
    local cx = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cx:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    if UI and UI.Font then UI.Font(cx, 16) end
    cx:SetText("×")
    cx:SetTextColor(0.7, 0.7, 0.75)
    closeBtn:SetScript("OnEnter", function() cx:SetTextColor(ac.r, ac.g, ac.b) end)
    closeBtn:SetScript("OnLeave", function() cx:SetTextColor(0.7, 0.7, 0.75) end)
    closeBtn:SetScript("OnClick", function() popup:Hide() end)
    popup.closeBtn = closeBtn

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -8)
    title:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    if UI and UI.Font then UI.Font(title, 12) end
    title:SetTextColor(0.95, 0.95, 1)
    popup.title = title

    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(self)
        self.pinned = true
        self:StartMoving()
    end)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

    popup:SetScript("OnUpdate", function(self, elapsed)
        local auto = self._compact or (mod.db and mod.db.autoClose ~= false)
        if not auto then return end
        if self.pinned and not self._compact then return end
        local overSelf   = self:IsMouseOver(8, -8, -8, 8)   -- grace margin bridges the gap to the slot
        local overAnchor = self.anchorBtn and self.anchorBtn.IsMouseOver
                           and self.anchorBtn:IsMouseOver()
        if overSelf then self.armed = true end
        if overSelf or overAnchor then
            self.outTime = 0
        elseif self._compact or self.armed then
            self.outTime = (self.outTime or 0) + elapsed
            if self.outTime > (self._compact and 0.35 or 0.5) then self:Hide() end
        end
    end)
    popup:SetScript("OnShow", function(self)
        self.armed = false
        self.outTime = 0
    end)

    return popup
end

local function slotLabel(slotID)
    local suffix = SLOT_FRAME_NAMES[slotID]
    if not suffix then return string.format("Slot %d", slotID) end
    return _G[string.upper(suffix) .. "SLOT"] or suffix
end

local function getItemButton(idx)
    local btn = itemButtons[idx]
    if btn then return btn end
    btn = CreateFrame("Button", nil, popup, "ItemButtonTemplate")
    if not btn.icon then
        -- older ItemButtonTemplate revisions don't expose .icon
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints(btn)
    end
    btn:SetSize(BTN_SIZE, BTN_SIZE)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    btn.ring = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    btn.ring:SetAllPoints(btn)
    btn.ring:SetColorTexture(0.25, 0.25, 0.3, 1)
    if btn.ring.SetSnapToPixelGrid then
        btn.ring:SetSnapToPixelGrid(false); btn.ring:SetTexelSnappingBias(0)
    end
    if btn.icon then
        btn.icon:ClearAllPoints()
        btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if btn.icon.SetSnapToPixelGrid then
            btn.icon:SetSnapToPixelGrid(false); btn.icon:SetTexelSnappingBias(0)
        end
    end
    btn.ilvl = btn:CreateFontString(nil, "OVERLAY")
    btn.ilvl:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    if ns.UI and ns.UI.FONT_PATH then
        btn.ilvl:SetFont(ns.UI.FONT_PATH, 10, "OUTLINE")
    else
        btn.ilvl:SetFontObject("NumberFontNormalSmall")
    end
    btn.ilvl:SetTextColor(1, 1, 1)
    btn:SetScript("OnEnter", function(self)
        self.ring:SetColorTexture(1, 1, 1, 0.9)
        if self.bag and self.slot and ns.UI:OpenTooltip(self, "ANCHOR_RIGHT") then
            GameTooltip:SetBagItem(self.bag, self.slot)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.ring:SetColorTexture(self._qr or 0.25, self._qg or 0.25, self._qb or 0.3, 1)
        ns.UI:HideTooltip()
    end)
    btn:SetScript("OnClick", function(self, button)
        if InCombatLockdown() then
            ns:Print(L["Cannot change equipment in combat."])
            return
        end
        if button == "LeftButton" and self.bag and self.slot then
            local link = GetContainerItemLink and GetContainerItemLink(self.bag, self.slot)
            -- EquipItemByName honours the exact slot (lower ring/trinket) and keeps the BoE bind prompt
            if self.equipSlot and EquipItemByName and link then
                pcall(EquipItemByName, link, self.equipSlot)
            elseif self.equipSlot and ns.EquipBagItemToSlot then
                ns:EquipBagItemToSlot(self.bag, self.slot, self.equipSlot)
            elseif UseContainerItem then
                pcall(UseContainerItem, self.bag, self.slot)
            end
            popup:Hide()
        end
    end)
    itemButtons[idx] = btn
    return btn
end

local function applyItemLook(btn)
    local q, lvl
    if btn.itemID then
        local _, _, quality, level = GetItemInfo(btn.itemID)
        q, lvl = quality, level
        if q == nil and C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, btn.itemID)
        end
    end
    if q and q >= 2 and GetItemQualityColor then
        btn._qr, btn._qg, btn._qb = GetItemQualityColor(q)
    else
        btn._qr, btn._qg, btn._qb = 0.25, 0.25, 0.3
    end
    -- don't stomp the hover highlight when the cursor is on this button (deferred repaint)
    if btn.IsMouseOver and btn:IsMouseOver() then
        btn.ring:SetColorTexture(1, 1, 1, 0.9)
    else
        btn.ring:SetColorTexture(btn._qr, btn._qg, btn._qb, 1)
    end
    btn.ilvl:SetText(lvl and lvl > 1 and tostring(lvl) or "")
end

local function showSlotPicker(slotID, anchorBtn, compact)
    if not GetItemInfoInstant then
        if not compact then ns:Print(L["Item scanning API not available on this client."]) end
        return
    end

    createPopup()

    -- flyout and click picker share one pooled popup; never hijack a click popup
    if compact and popup:IsShown() and (popup.pinned or not popup._compact) then
        return
    end

    local results = scanBagsForSlot(slotID)

    if compact and #results == 0 then
        popup:Hide()
        return
    end

    popup._compact = compact and true or nil
    if compact then
        popup.title:Hide()
        if popup.closeBtn then popup.closeBtn:Hide() end
    else
        popup.title:Show()
        if popup.closeBtn then popup.closeBtn:Show() end
        popup.title:SetText(string.format(L["Items for: %s"], slotLabel(slotID))
            .. string.format(" |cff888888(%d)|r", #results))
    end

    for _, b in ipairs(itemButtons) do b:Hide() end

    -- click popup keeps a constant full-grid width so it never jumps between slots
    local btnPad    = 4
    local padding   = compact and 6 or 10
    local gridStart = compact and 6 or 30
    local cols
    if compact then
        cols = math.min(mod.db.cols or 8, math.max(1, math.ceil(math.sqrt(#results))))
    else
        cols = mod.db.cols or 8
    end
    local width
    if compact then
        width = cols * (BTN_SIZE + btnPad) - btnPad + padding * 2
    else
        width = math.max(cols * (BTN_SIZE + btnPad) - btnPad + padding * 2, 240)
    end

    if #results == 0 then
        popup:SetSize(width, 64)
        if not popup.noItemsText then
            popup.noItemsText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            popup.noItemsText:SetPoint("CENTER", popup, "CENTER", 0, -8)
            popup.noItemsText:SetTextColor(0.7, 0.7, 0.7)
            if ns.UI and ns.UI.Font then ns.UI.Font(popup.noItemsText, 11) end
        end
        popup.noItemsText:SetText(L["No matching items in your bags."])
        popup.noItemsText:Show()
    else
        if popup.noItemsText then popup.noItemsText:Hide() end

        local rows   = math.ceil(#results / cols)
        local height = gridStart + rows * (BTN_SIZE + btnPad) - btnPad + padding

        popup:SetSize(width, height)

        for i, entry in ipairs(results) do
            local btn = getItemButton(i)
            btn:Show()
            btn.bag      = entry.bag
            btn.slot     = entry.slot
            btn.itemID   = entry.itemID
            btn.equipSlot = slotID

            local iconTex = entry.icon
            if not iconTex then
                local _, _, _, _, ic = GetItemInfoInstant(entry.itemID)
                iconTex = ic
            end
            if btn.icon and iconTex then
                btn.icon:SetTexture(iconTex)
            end
            if SetItemButtonTexture then
                pcall(SetItemButtonTexture, btn, iconTex)
            end
            applyItemLook(btn)

            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", popup, "TOPLEFT",
                padding + col * (BTN_SIZE + btnPad),
                -(gridStart + row * (BTN_SIZE + btnPad)))
        end

        -- one deferred pass for items the client hadn't cached yet
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function()
                if not popup:IsShown() then return end
                for _, b in ipairs(itemButtons) do
                    if b:IsShown() then applyItemLook(b) end
                end
            end)
        end
    end

    -- open on the far side of the slot when it sits in the right screen half
    popup.pinned = false
    popup.armed  = false
    popup.anchorBtn = anchorBtn
    popup:ClearAllPoints()
    if anchorBtn and anchorBtn.GetCenter then
        local x = anchorBtn:GetCenter()
        local mid = UIParent:GetWidth() * 0.5
        -- Which EDGES are aligned, in both directions: the popup grows away from
        -- the screen centre, so it cannot run off the near side.
        local corner = (x and x > mid) and "RIGHT" or "LEFT"
        if DOWNWARD_SLOTS[slotID] then
            -- Measured, not assumed: the character window can be dragged to the
            -- bottom of the screen, and a flyout below it would render
            -- off-screen and be unreachable. It goes above then -- same belt as
            -- the gem picker on the socket strip. The size is already set above,
            -- so the height asked for here is the real one.
            local bottom = anchorBtn.GetBottom and anchorBtn:GetBottom()
            if bottom and (bottom - popup:GetHeight() - 6) < 0 then
                popup:SetPoint("BOTTOM" .. corner, anchorBtn, "TOP" .. corner, 0, 6)
            else
                popup:SetPoint("TOP" .. corner, anchorBtn, "BOTTOM" .. corner, 0, -6)
            end
        elseif corner == "RIGHT" then
            popup:SetPoint("TOPRIGHT", anchorBtn, "TOPLEFT", -6, 2)
        else
            popup:SetPoint("TOPLEFT", anchorBtn, "TOPRIGHT", 6, 2)
        end
    elseif CharacterFrame and CharacterFrame:IsShown() then
        popup:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 4, 0)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    popup:Show()
end

function ns:ScanBagsForSlot(slotID)
    return scanBagsForSlot(slotID)
end

local _hooked = false

-- generation token: brushing across slots must not spawn a flyout on each one
local hoverGen = 0
local function scheduleFlyout(slotID, btn)
    if not (mod._enabled and mod.db and mod.db.hoverFlyout) then return end
    hoverGen = hoverGen + 1
    local myGen = hoverGen
    if not (C_Timer and C_Timer.After) then
        showSlotPicker(slotID, btn, true); return
    end
    C_Timer.After(0.15, function()
        if myGen ~= hoverGen then return end
        if not (mod._enabled and mod.db and mod.db.hoverFlyout) then return end
        if btn.IsMouseOver and btn:IsMouseOver() then
            showSlotPicker(slotID, btn, true)
        end
    end)
end

local function hookSlots()
    if _hooked then return end
    for slotID, frameName in pairs(SLOT_FRAME_NAMES) do
        local slotBtn = _G["Character" .. frameName .. "Slot"]
        if slotBtn then
            slotBtn:HookScript("OnClick", function(self, button)
                if not mod._enabled then return end
                if checkModifier(button) then
                    showSlotPicker(slotID, self)
                end
            end)
            slotBtn:HookScript("OnEnter", function(self)
                scheduleFlyout(slotID, self)
            end)
            slotBtn:HookScript("OnLeave", function()
                hoverGen = hoverGen + 1
            end)
        end
    end
    _hooked = true
end

function mod:OnEnable()
    if not mod.db then return end

    -- one-time migration off the old "shift-right" default
    if not mod.db._defaultMigrated_v2 then
        if mod.db.modifier == "shift-right" then
            mod.db.modifier = "right"
        end
        mod.db._defaultMigrated_v2 = true
    end

    hookSlots()
end

-- The two options Loadouts embeds on its page as well. Built HERE so adding
-- one later cannot silently leave the other page stale; getDB returns the
-- slot-picker db (may be nil from the Loadouts side before first init).
function ns.SlotPickerOptionItems(getDB)
    return {
        { type = "dropdown", label = L["Activation modifier"],
          tooltip = L["Choose which key combination opens the item picker when you click an equipment slot."],
          values = {
              { value = "right",       text = L["Right-click only"] },
              { value = "shift-right", text = L["Shift + Right-click"] },
              { value = "alt-right",   text = L["Alt + Right-click"] },
              { value = "ctrl-right",  text = L["Ctrl + Right-click"] },
          },
          get = function() local d = getDB(); return (d and d.modifier) or "right" end,
          set = function(_, v) local d = getDB(); if d then d.modifier = v end end },
        { type = "slider", label = L["Grid columns"],
          tooltip = L["How many item icons per row in the picker popup."],
          min = 4, max = 14, step = 1,
          get = function() local d = getDB(); return (d and d.cols) or 8 end,
          set = function(_, v) local d = getDB(); if d then d.cols = v end end },
    }
end

function mod:GetOptions()
    local spShared = ns.SlotPickerOptionItems(function() return mod.db end)
    return {
        { type = "header", text = L["Slot Picker"] },
        { type = "desc", text = L["Hover an equipment slot in the Character frame for a compact flyout of compatible bag items, or modifier-click for a larger pinnable picker. Click an item to equip it (out-of-combat)."] },

        { type = "spacer", height = 6 },
        { type = "toggle", label = L["Flyout on hover"],
          tooltip = L["Hovering an equipment slot pops out a compact strip of items you can swap in — the paperdoll flyout look. Turn off to use only the modifier-click picker."],
          get = function() return mod.db.hoverFlyout ~= false end,
          set = function(_, v) mod.db.hoverFlyout = v and true or false end },

        spShared[1], spShared[2],

        { type = "toggle", label = L["Close automatically on mouse-out"],
          tooltip = L["The picker closes itself shortly after the mouse leaves it. Drag it once to pin it open until you close it manually."],
          get = function() return mod.db.autoClose ~= false end,
          set = function(_, v) mod.db.autoClose = v and true or false end },
    }
end
