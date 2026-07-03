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

-- Registered as a hidden module: its settings live inside the Loadouts
-- ("Equipment Sets") page, not as a separate sidebar entry. The module still
-- runs (hooks slots, exposes ns:ScanBagsForSlot) — it's just not shown on its own.
local mod = ns:RegisterModule("slotpicker", {
    name        = "Slot Picker",
    group       = "_hidden",
    description = "Shift+Right-click an equipment slot to show all compatible items from your bags. Click to equip.",
    defaults = {
        enabled   = true,
        modifier  = "right",  -- "right" | "shift-right" | "alt-right" | "ctrl-right"
        cols      = 8,
        autoClose = true,     -- hide shortly after the mouse leaves the popup
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

    -- house look: dark panel + accent border, soft shadow, gradient strip
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

    -- Close button (styled ×) — created BEFORE the title so the title can
    -- end-elide against it instead of overflowing (truncated titles)
    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)
    local cx = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cx:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    if UI and UI.Font then UI.Font(cx, 13) end
    cx:SetText("×")
    cx:SetTextColor(0.7, 0.7, 0.75)
    closeBtn:SetScript("OnEnter", function() cx:SetTextColor(ac.r, ac.g, ac.b) end)
    closeBtn:SetScript("OnLeave", function() cx:SetTextColor(0.7, 0.7, 0.75) end)
    closeBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Title: our font, white, elides at the END against the close button
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -8)
    title:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    if UI and UI.Font then UI.Font(title, 12) end
    title:SetTextColor(0.95, 0.95, 1)
    popup.title = title

    -- Drag to move; dragging pins the popup (auto-close stands down until
    -- it is closed and reopened)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(self)
        self.pinned = true
        self:StartMoving()
    end)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

    -- Flyout feel: close shortly after the mouse leaves popup + anchor slot.
    -- Arms only once the mouse has actually been over the popup, so it never
    -- vanishes before you reach it.
    popup:SetScript("OnUpdate", function(self, elapsed)
        if not (mod.db and mod.db.autoClose ~= false) or self.pinned then return end
        local overSelf   = self:IsMouseOver(6, -6, -6, 6)   -- small grace margin
        local overAnchor = self.anchorBtn and self.anchorBtn.IsMouseOver
                           and self.anchorBtn:IsMouseOver()
        if overSelf then
            self.armed = true
            self.outTime = 0
        elseif self.armed and not overAnchor then
            self.outTime = (self.outTime or 0) + elapsed
            if self.outTime > 0.5 then self:Hide() end
        end
    end)
    popup:SetScript("OnShow", function(self)
        self.armed = false
        self.outTime = 0
    end)

    return popup
end

-- Localized slot label ("Hands" -> HANDSSLOT global -> "Hände" on deDE);
-- falls back to the English frame suffix when the global is missing.
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
        -- Fallback in case ItemButtonTemplate doesn't expose .icon
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints(btn)
    end
    btn:SetSize(BTN_SIZE, BTN_SIZE)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- house look: hide the template's metal rim, draw a filled quality ring
    -- behind a 1px-inset icon (the proven bag-button recipe)
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
        if self.bag and self.slot then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetBagItem(self.bag, self.slot)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.ring:SetColorTexture(self._qr or 0.25, self._qg or 0.25, self._qb or 0.3, 1)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self, button)
        if InCombatLockdown() then
            ns:Print(L["Cannot change equipment in combat."])
            return
        end
        if button == "LeftButton" and self.bag and self.slot then
            -- Use the slot-aware equip helper (honours the exact target slot,
            -- so picking for the lower ring/trinket slot works correctly).
            if self.equipSlot and ns.EquipBagItemToSlot then
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

-- Quality ring + item level per button; uncached item data self-heals via
-- the deferred repaint in showSlotPicker (the request is fired here).
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
        btn._qr, btn._qg, btn._qb = 0.25, 0.25, 0.3   -- neutral (grey/white gear)
    end
    -- don't stomp the white hover highlight when the cursor is sitting on
    -- this button (deferred repaint / popup reuse)
    if btn.IsMouseOver and btn:IsMouseOver() then
        btn.ring:SetColorTexture(1, 1, 1, 0.9)
    else
        btn.ring:SetColorTexture(btn._qr, btn._qg, btn._qb, 1)
    end
    btn.ilvl:SetText(lvl and lvl > 1 and tostring(lvl) or "")
end

local function showSlotPicker(slotID, anchorBtn)
    if not GetItemInfoInstant then
        ns:Print(L["Item scanning API not available on this client."])
        return
    end

    createPopup()

    local results = scanBagsForSlot(slotID)
    popup.title:SetText(string.format(L["Items for: %s"], slotLabel(slotID))
        .. string.format(" |cff888888(%d)|r", #results))

    -- Hide leftover buttons
    for _, b in ipairs(itemButtons) do b:Hide() end

    -- CONSTANT width: always the full grid width, no matter how many items —
    -- the popup never jumps sizes between slots (and the title never clips)
    local cols      = mod.db.cols or 8
    local padding   = 10
    local gridStart = 30  -- below title bar
    local btnPad    = 4
    local width     = math.max(cols * (BTN_SIZE + btnPad) - btnPad + padding * 2, 240)

    if #results == 0 then
        popup:SetSize(width, 64)
        -- Show "no items" message inline
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
            btn.equipSlot = slotID  -- the character slot this picker is for

            -- Set icon
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

        -- one deferred pass for quality/ilvl of items the client hadn't
        -- cached yet (requests were fired in applyItemLook)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function()
                if not popup:IsShown() then return end
                for _, b in ipairs(itemButtons) do
                    if b:IsShown() then applyItemLook(b) end
                end
            end)
        end
    end

    -- Open DIRECTLY at the clicked slot: to its right, or to its left when
    -- the slot sits in the right half of the screen (right slot column /
    -- right-positioned character window). Clamped to the screen either way.
    popup.pinned = false
    popup.armed  = false
    popup.anchorBtn = anchorBtn
    popup:ClearAllPoints()
    if anchorBtn and anchorBtn.GetCenter then
        local x = anchorBtn:GetCenter()
        local mid = UIParent:GetWidth() * 0.5
        if x and x > mid then
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
                    showSlotPicker(slotID, self)   -- anchor the popup to this slot
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

        { type = "toggle", label = L["Close automatically on mouse-out"],
          tooltip = L["The picker closes itself shortly after the mouse leaves it. Drag it once to pin it open until you close it manually."],
          get = function() return mod.db.autoClose ~= false end,
          set = function(_, v) mod.db.autoClose = v and true or false end },
    }
end
