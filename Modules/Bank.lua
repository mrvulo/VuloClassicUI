-- VuloClassicUI / Modules / Bank
local _, ns = ...
local L   = ns.L
local mod = ns.modules.bags   -- loads after Bags.lua; mod.db is only valid inside handlers
local BTN, GAP, PAD = 37, 4, 12

local bank = {
    frame        = nil,
    buttons      = {},
    indexFrames  = {},
    bags         = {},
    btnCounter   = 0,
    open         = false,
    autoOpenedBags   = false,
    refreshScheduled = false,
    pendingRelayout  = false,
    suppressed   = false,
    origParent   = {},
    origScripts  = nil,
    hiddenHost   = nil,
    mover        = nil,
    bindTypeCache = {},
    TOP          = 40,
    BOTTOM       = 38,
}

-- Bank containers: -1 plus NUM_BAG_SLOTS+1..N. Never Enum.BagIndex.BankBag_* (stale retail values on Classic).
bank.bags[1] = _G.BANK_CONTAINER or -1
for i = 1, (_G.NUM_BANKBAGSLOTS or 6) do
    bank.bags[#bank.bags + 1] = (_G.NUM_BAG_SLOTS or 4) + i
end

bank.hiddenHost = CreateFrame("Frame")
bank.hiddenHost:Hide()

-- Own dialog: Blizzard's reads BankFrame.nextSlotCost, which only the OnEvent we clear sets. PurchaseSlot is unprotected.
StaticPopupDialogs["VCUI_BANK_BUY_SLOT"] = {
    text = CONFIRM_BUY_BANK_SLOT,
    button1 = YES, button2 = NO,
    hasMoneyFrame = 1,
    OnShow = function(self)
        local mf = self.moneyFrame or _G[self:GetName() .. "MoneyFrame"]
        if mf and MoneyFrame_Update then
            local owned = GetNumBankSlots() or 0
            MoneyFrame_Update(mf, GetBankSlotCost(owned) or 0)
        end
    end,
    OnAccept = function() PurchaseSlot() end,
    timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
}

function bank.db()
    local root = mod.db
    if not root then return { enabled = false } end
    local d = root.bank
    if not d then
        d = { enabled = true, x = -280, y = 0, scale = 1.0, columns = 14, hiddenBags = {} }
        root.bank = d
    end
    d.hiddenBags = d.hiddenBags or {}
    return d
end

function bank.visibleBags()
    local hidden = bank.db().hiddenBags
    local out = {}
    for _, bag in ipairs(bank.bags) do
        if not hidden[bag] then out[#out + 1] = bag end
    end
    return out
end

function bank.bagName(bag)
    if bag == (_G.BANK_CONTAINER or -1) then return L["Bank"] end
    local i = bag - (_G.NUM_BAG_SLOTS or 4)
    if BankButtonIDToInvSlotID and GetInventoryItemLink then
        local inv  = BankButtonIDToInvSlotID(i, 1)
        local link = inv and GetInventoryItemLink("player", inv)
        local name = link and link:match("%[(.-)%]")
        if name then return name end
    end
    return string.format(L["Bag %d"], i)
end

function bank.enabled()
    return mod.active and bank.db().enabled ~= false
end

-- Suppress the default bank: reparent + clear scripts (restored on disable).
-- Never BankFrame:Hide() with live scripts - OnHide/OnEvent call CloseBankFrame.
function bank.suppressDefault()
    if bank.suppressed or InCombatLockdown() then return end
    bank.suppressed = true
    for i = 7, 13 do
        local cf = _G["ContainerFrame" .. i]
        if cf then
            bank.origParent[i] = bank.origParent[i] or cf:GetParent()
            cf:SetParent(bank.hiddenHost)
        end
    end
    local bf = _G.BankFrame
    if bf then
        if not bank.origScripts then
            bank.origScripts = {
                parent  = bf:GetParent(),
                OnEvent = bf:GetScript("OnEvent"),
                OnShow  = bf:GetScript("OnShow"),
                OnHide  = bf:GetScript("OnHide"),
            }
        end
        bf:SetParent(bank.hiddenHost)
        bf:SetScript("OnEvent", nil)
        bf:SetScript("OnShow", nil)
        bf:SetScript("OnHide", nil)
        -- safe: OnHide is already nil'd, so no CloseBankFrame fires
        if bf:IsShown() then bf:Hide() end
    end
end

function bank.restoreDefault()
    if not bank.suppressed or InCombatLockdown() then return end
    bank.suppressed = false
    for i = 7, 13 do
        local cf = _G["ContainerFrame" .. i]
        if cf then cf:SetParent(bank.origParent[i] or UIParent) end
    end
    local bf = _G.BankFrame
    if bf and bank.origScripts then
        -- hide while the scripts are still nil'd, then restore
        if bf:IsShown() then bf:Hide() end
        bf:SetParent(bank.origScripts.parent or UIParent)
        bf:SetScript("OnEvent", bank.origScripts.OnEvent)
        bf:SetScript("OnShow",  bank.origScripts.OnShow)
        bf:SetScript("OnHide",  bank.origScripts.OnHide)
    end
end

function bank.updateButton(btn)
    local bag  = btn:GetParent():GetID()
    local slot = btn:GetID()
    -- the container API accepts -1 here, like Blizzard's own bank
    ns.BagsPaintContainerButton(btn, bag, slot, mod.db, bank.bindTypeCache)

    -- alpha only - never Enable/Hide, so the secure click paths stay intact
    if (bank.searchText or "") == "" then
        btn:SetAlpha(1)
    else
        local match = ns.BagItemMatchesSearch and ns.BagItemMatchesSearch(bag, slot, bank.searchText)
        btn:SetAlpha(match ~= false and 1 or 0.25)
    end
end

function bank.ensureIndexFrame(bag)
    local f = bank.indexFrames[bag]
    if not f then
        if InCombatLockdown() then return nil end
        f = CreateFrame("Frame", nil, bank.frame.content)
        f:SetAllPoints(bank.frame.content)
        bank.indexFrames[bag] = f
    end
    f:SetID(bag)
    return f
end

-- The -1 container is inventory-slot-backed, so the template's OnEnter is wrong for it.
-- OnEnter/OnLeave are tooltip-only; UpdateTooltip must point at the same function.
function bank.onEnterItem(self)
    local parent = self:GetParent()
    if parent and parent:GetID() == -1 and BankButtonIDToInvSlotID then
        ns.UI:OpenTooltip(self, "ANCHOR_RIGHT")
        if GameTooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(self:GetID())) then
            GameTooltip:Show()
        else
            ns.UI:HideTooltip()
        end
    elseif self._origOnEnter then
        self._origOnEnter(self)
    elseif ContainerFrameItemButton_OnEnter then
        ContainerFrameItemButton_OnEnter(self)
    else
        ns.UI:OpenTooltip(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(parent and parent:GetID(), self:GetID())
        GameTooltip:Show()
    end
end

function bank.onLeaveItem(self)
    local parent = self:GetParent()
    if parent and parent:GetID() == -1 then
        ns.UI:HideTooltip()
        if ResetCursor then ResetCursor() end
    elseif self._origOnLeave then
        self._origOnLeave(self)
    elseif ContainerFrameItemButton_OnLeave then
        ContainerFrameItemButton_OnLeave(self)
    else
        ns.UI:HideTooltip()
        if ResetCursor then ResetCursor() end
    end
end

function bank.acquireButton(n)
    local btn = bank.buttons[n]
    if btn then return btn end
    if InCombatLockdown() then return nil end
    bank.btnCounter = bank.btnCounter + 1
    btn = CreateFrame("Button", "VuloClassicUIBankItem" .. bank.btnCounter,
        bank.frame.content, "ContainerFrameItemButtonTemplate")
    btn:SetSize(BTN, BTN)
    btn._origOnEnter = btn:GetScript("OnEnter")
    btn._origOnLeave = btn:GetScript("OnLeave")
    btn:SetScript("OnEnter", bank.onEnterItem)
    btn:SetScript("OnLeave", bank.onLeaveItem)
    btn.UpdateTooltip = bank.onEnterItem
    ns.BagsStripButtonGlow(btn)
    ns.BagsSkinItemButton(btn)
    btn:Hide()
    bank.buttons[n] = btn
    return btn
end

-- Container sizes are readable at BANKFRAME_OPENED; item reads are deferred a frame.
function bank.preallocate()
    if not bank.frame or InCombatLockdown() then return end
    local need = 8
    for _, bag in ipairs(bank.bags) do
        need = need + (GetContainerNumSlots(bag) or 0)
        bank.ensureIndexFrame(bag)
    end
    for i = #bank.buttons + 1, need do
        if not bank.acquireButton(i) then break end
    end
end

-- Built eagerly at PLAYER_ENTERING_WORLD so a mid-combat first visit has a window.
function bank.build()
    if bank.frame or InCombatLockdown() then return bank.frame end
    local UI = ns.UI
    local f = CreateFrame("Frame", "VuloClassicUIBankFrame", UIParent)
    bank.frame = f
    f:SetFrameStrata("HIGH")
    f:SetSize(420, 300)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:Hide()
    if UI and UI.StyleBackdrop then UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border }) end
    if UI and UI.CreateShadow then UI:CreateShadow(f) end
    if _G.tinsert and _G.UISpecialFrames then tinsert(UISpecialFrames, "VuloClassicUIBankFrame") end

    -- Manual close must END the server bank session; bank.open guards the reverse path.
    f:HookScript("OnHide", function()
        if bank.open and CloseBankFrame then CloseBankFrame() end
    end)

    local strip = f:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    if UI and UI.SetGradient then
        local a = ns.COLORS.accent
        UI.SetGradient(strip, "HORIZONTAL", a.r, a.g, a.b, 0.1, a.r, a.g, a.b, 0.9)
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if UI and UI.Font then UI.Font(f.title, 14) end
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -9)
    f.title:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    f.title:SetText(L["Bank"])

    local close = UI:CreateCloseX(f, function() f:Hide() end)

    local sb = UI:CreateSearchBox(f, {
        onText = function(self)
            bank.searchText = (self:GetText() or ""):lower()
            bank.refresh()
        end,
    })
    f.search = sb
    sb:SetPoint("RIGHT", close, "LEFT", -8, 0)

    local sortBtn = CreateFrame("Button", nil, f)
    sortBtn:SetSize(18, 18)
    sortBtn:SetPoint("RIGHT", sb, "LEFT", -8, 0)
    local si = sortBtn:CreateTexture(nil, "ARTWORK")
    si:SetAllPoints(); si:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\broom.tga")
    si:SetVertexColor(0.7, 0.7, 0.75)
    sortBtn:SetScript("OnEnter", function()
        si:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        ns.UI:ShowTooltip(sortBtn, { anchor = "ANCHOR_TOP", title = L["Sort bank"] })
    end)
    sortBtn:SetScript("OnLeave", function() si:SetVertexColor(0.7, 0.7, 0.75); ns.UI:HideTooltip() end)
    sortBtn:SetScript("OnClick", function()
        if not bank.open then return end
        if ns.RunBagSort then
            ns.RunBagSort(bank.bags,
                (_G.C_Container and _G.C_Container.SortBankBags) or _G.SortBankBags)
        end
    end)

    local bagsBtn = CreateFrame("Button", nil, f)
    bagsBtn:SetSize(18, 18)
    bagsBtn:SetPoint("RIGHT", sortBtn, "LEFT", -8, 0)
    local bfi = bagsBtn:CreateTexture(nil, "ARTWORK")
    bfi:SetAllPoints(); bfi:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\bags.tga")
    bfi:SetVertexColor(0.7, 0.7, 0.75)
    bagsBtn:SetScript("OnEnter", function()
        bfi:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        ns.UI:ShowTooltip(bagsBtn, { anchor = "ANCHOR_TOP", title = L["Show or hide bags"] })
    end)
    bagsBtn:SetScript("OnLeave", function() bfi:SetVertexColor(0.7, 0.7, 0.75); ns.UI:HideTooltip() end)

    -- Filter strip: left-click show/hide, right-click equip/buy. Equip and purchase APIs are unprotected but fail in combat.
    local fbar = CreateFrame("Frame", nil, f)
    f.filterBar = fbar
    fbar:SetSize(#bank.bags * (26 + GAP) - GAP + 12, 34)
    fbar:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
    if UI and UI.StyleBackdrop then UI:StyleBackdrop(fbar, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border }) end
    fbar:Hide()
    fbar._icons = {}
    local function slotIndexOf(bag)
        if bag == (_G.BANK_CONTAINER or -1) then return nil end
        return bag - (_G.NUM_BAG_SLOTS or 4)
    end
    function bank.updateFilterBar()
        if not (f.filterBar and f.filterBar:IsShown()) then return end
        local hidden = bank.db().hiddenBags
        local owned  = GetNumBankSlots() or 0
        for _, ic in ipairs(fbar._icons) do
            local on = not hidden[ic._bag]
            local i  = slotIndexOf(ic._bag)
            local tex, vr, vg, vb, desat = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag", 1, 1, 1, false
            if not i then
                tex = "Interface\\Icons\\INV_Box_02"
            elseif i <= owned then
                local inv = BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(i, 1)
                local t = inv and GetInventoryItemTexture("player", inv)
                if t then tex = t else desat = true end
            elseif i == owned + 1 then
                vr, vg, vb = 0.4, 1, 0.4
            else
                vr, vg, vb, desat = 1, 0.25, 0.25, true
            end
            ic._tex:SetTexture(tex)
            ic._tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            ic._tex:SetDesaturated(desat or not on)
            ic._tex:SetVertexColor(vr, vg, vb, on and 1 or 0.35)
        end
    end
    local function equipOrBuy(b)
        if InCombatLockdown() then return end
        local i = slotIndexOf(b)
        if not i then return end
        local owned = GetNumBankSlots() or 0
        if i > owned then
            if i == owned + 1 then StaticPopup_Show("VCUI_BANK_BUY_SLOT") end
            return
        end
        local inv = BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(i, 1)
        if not inv then return end
        if CursorHasItem() then PutItemInBag(inv) else PickupBagFromSlot(inv) end
        bank.updateFilterBar()
    end
    for i, bag in ipairs(bank.bags) do
        local b = bag
        local ic = CreateFrame("Button", nil, fbar)
        ic:SetSize(26, 26)
        ic:SetPoint("LEFT", fbar, "LEFT", 6 + (i - 1) * (26 + GAP), 0)
        local bg2 = ic:CreateTexture(nil, "BACKGROUND")
        bg2:SetAllPoints(ic); bg2:SetColorTexture(0.10, 0.10, 0.13, 0.55)
        ic._tex = ic:CreateTexture(nil, "ARTWORK")
        ic._tex:SetPoint("TOPLEFT", 1, -1); ic._tex:SetPoint("BOTTOMRIGHT", -1, 1)
        ic._tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ic._bag = b
        ic:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        ic:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then equipOrBuy(b); return end
            if CursorHasItem and CursorHasItem() then equipOrBuy(b); return end
            local hidden = bank.db().hiddenBags
            hidden[b] = not hidden[b] or nil
            bank.updateFilterBar()
            bank.refresh()
        end)
        ic:SetScript("OnReceiveDrag", function() if CursorHasItem and CursorHasItem() then equipOrBuy(b) end end)
        ic:SetScript("OnEnter", function(self)
            -- SetTooltipMoney has to land between the lines and the Show, which
            -- no spec table can express -- so this one opens the tooltip itself.
            if not ns.UI:OpenTooltip(self, "ANCHOR_TOP") then return end
            local i2 = slotIndexOf(b)
            local owned = GetNumBankSlots() or 0
            GameTooltip:SetText(bank.bagName(b))
            GameTooltip:AddLine(L["Left-click: show or hide."], 0.7, 0.7, 0.7)
            if i2 then
                if i2 <= owned then
                    GameTooltip:AddLine(L["Right-click: pick up or equip the bag."], 0.7, 0.7, 0.7)
                elseif i2 == owned + 1 then
                    GameTooltip:AddLine(L["Right-click: buy this bag slot."], 0.7, 0.7, 0.7)
                    if SetTooltipMoney then SetTooltipMoney(GameTooltip, GetBankSlotCost(owned) or 0) end
                else
                    GameTooltip:AddLine(L["Buy the previous slot first."], 0.9, 0.35, 0.35)
                end
            end
            GameTooltip:Show()
        end)
        ic:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
        fbar._icons[#fbar._icons + 1] = ic
    end
    bagsBtn:SetScript("OnClick", function()
        local show = not fbar:IsShown()
        fbar:SetShown(show)
        bank.db().bagBarShown = show
        if show then bank.updateFilterBar() end
    end)
    if bank.db().bagBarShown then fbar:Show() end

    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -bank.TOP)
    f.content:SetSize(100, 100)

    f.free = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.free:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 8)

    -- House font at 13 instead of the small template (~10px): the money line
    -- was hard to read at a glance (user request, 31.07.2026). The coin icons
    -- get the matching height where the text is built.
    f.money = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if ns.UI and ns.UI.Font then ns.UI.Font(f.money, 13) end
    f.money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 8)
    local moneyBtn = CreateFrame("Button", nil, f)
    moneyBtn:SetPoint("TOPLEFT", f.money, "TOPLEFT", -4, 2)
    moneyBtn:SetPoint("BOTTOMRIGHT", f.money, "BOTTOMRIGHT", 4, -2)
    moneyBtn:SetScript("OnEnter", function(self)
        if ns.ShowGoldTooltip then ns.ShowGoldTooltip(self) end
    end)
    moneyBtn:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
    bank.updateMoney()

    -- separate db keys (mod.db.bank.*) so bank and bag positions never collide
    if ns.CreateMover then
        bank.mover = ns:CreateMover(f, {
            db = bank.db(), scalable = true, anchorable = true,
            label = "|cffffffffBANK|r", width = 160, height = 40,
        })
        if ns.ApplyMover then ns:ApplyMover(bank.mover) end
    end

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = ns:GetCenterOffsets(self)
        if x and y then
            local d = bank.db()
            d.x, d.y = x, y
            if ns.ApplyMover and bank.mover then ns:ApplyMover(bank.mover) end
        end
    end)

    bank.preallocate()
    return f
end

function bank.layout()
    if not (bank.frame and bank.open) then return end
    local cols = bank.db().columns or 14
    if cols < 1 then cols = 1 end
    local f = bank.frame

    -- Height cap: raise the EFFECTIVE column count (saved setting untouched).
    local shown = bank.visibleBags()
    local total = 0
    for _, bag in ipairs(shown) do total = total + (GetContainerNumSlots(bag) or 0) end
    local maxRows = math.floor((UIParent:GetHeight() * 0.7 - bank.TOP - bank.BOTTOM) / (BTN + GAP))
    if maxRows < 1 then maxRows = 1 end
    if total > 0 and math.ceil(total / cols) > maxRows then
        cols = math.ceil(total / maxRows)
    end

    local n, blocked = 0, false
    for _, bag in ipairs(shown) do
        -- GetContainerNumSlots(-1) is only valid while the bank session is open
        local slots = GetContainerNumSlots(bag) or 0
        if slots > 0 then
            local idx = bank.ensureIndexFrame(bag)
            if not idx then blocked = true; break end
            for slot = 1, slots do
                n = n + 1
                local btn = bank.acquireButton(n)
                if not btn then n = n - 1; blocked = true; break end
                btn:SetParent(idx)
                btn:SetID(slot)
                local col = (n - 1) % cols
                local row = math.floor((n - 1) / cols)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", f.content, "TOPLEFT",
                    col * (BTN + GAP), -row * (BTN + GAP))
                btn:Show()
                bank.updateButton(btn)
            end
        end
        if blocked then break end
    end
    for i = n + 1, #bank.buttons do bank.buttons[i]:Hide() end
    if blocked then bank.pendingRelayout = true end

    local rows = math.max(1, math.ceil(math.max(n, 1) / cols))
    local contentW = cols * (BTN + GAP) - GAP
    local contentH = rows * (BTN + GAP) - GAP
    f.content:SetSize(contentW, contentH)
    f:SetSize(PAD + contentW + PAD, bank.TOP + contentH + bank.BOTTOM)
    bank.updateFree()
end

function bank.updateFree()
    if not (bank.frame and bank.frame.free) then return end
    local free = 0
    for _, bag in ipairs(bank.visibleBags()) do
        free = free + (GetContainerNumFreeSlots(bag) or 0)
    end
    bank.frame.free:SetText(string.format(L["%d free"], free))
end

function bank.updateMoney()
    if bank.frame and bank.frame.money and GetCoinTextureString then
        bank.frame.money:SetText(GetCoinTextureString(GetMoney() or 0, 13))
    end
end

-- Coalesce event bursts into ONE relayout next frame; item data lags the events.
function bank.refresh()
    if not (bank.open and bank.frame and bank.frame:IsShown()) then return end
    if bank.refreshScheduled then return end
    bank.refreshScheduled = true
    local function run()
        bank.refreshScheduled = false
        if bank.open and bank.frame and bank.frame:IsShown() then
            bank.layout()
            bank.snapshotMirror()
        end
    end
    ns.NextFrame(run)
end

-- Offline mirror: per-character snapshot plus a read-only viewer usable anywhere.
function bank.snapshotMirror(closing)
    if not bank.open then return end
    _G.VuloClassicUICharDB = _G.VuloClassicUICharDB or {}
    local mir = { when = time and time() or 0, free = 0, items = 0, bags = {} }
    for _, bag in ipairs(bank.bags) do
        local n = GetContainerNumSlots(bag) or 0
        if n > 0 then
            local b = { name = bank.bagName(bag), slots = {} }
            for slot = 1, n do
                local icon, count, _, quality, _, _, link = GetContainerItemInfo(bag, slot)
                if link then
                    b.slots[#b.slots + 1] = { l = link, c = count or 1, q = quality or 1, i = icon }
                    mir.items = mir.items + 1
                else
                    mir.free = mir.free + 1
                end
            end
            if #b.slots > 0 then mir.bags[#mir.bags + 1] = b end
        end
    end

    local old = _G.VuloClassicUICharDB.bankMirror
    if closing then
        -- final pass: a post-drop scan reads fewer items - keep the good one
        if old and (old.items or 0) > mir.items then return end
    elseif (bank.mirrorScans or 0) == 0 and old and (old.items or 0) > mir.items then
        -- first scan can lag OPENED: don't clobber a good mirror, rescan shortly
        bank.mirrorScans = 1
        if C_Timer and C_Timer.After then
            C_Timer.After(0.7, function() if bank.open then bank.snapshotMirror() end end)
            return
        end
    end
    bank.mirrorScans = (bank.mirrorScans or 0) + 1
    _G.VuloClassicUICharDB.bankMirror = mir
    if bank.mirrorFrame and bank.mirrorFrame:IsShown() then bank.renderMirror() end
end

function bank.mirrorButton(i)
    local f = bank.mirrorFrame
    local b = f.btns[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b:SetSize(30, 30)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.border:SetColorTexture(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetScript("OnEnter", function(self)
        if self.link and ns.UI:OpenTooltip(self, "ANCHOR_RIGHT") then
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
    f.btns[i] = b
    return b
end

function bank.mirrorHeader(i)
    local f = bank.mirrorFrame
    local h = f.heads[i]
    if h then return h end
    h = f:CreateFontString(nil, "OVERLAY")
    if ns.UI and ns.UI.Font then ns.UI.Font(h, 11) else h:SetFontObject(GameFontNormalSmall) end
    h:SetJustifyH("LEFT")
    local ac = ns.COLORS.accent
    h:SetTextColor(ac.r, ac.g, ac.b, 1)
    f.heads[i] = h
    return h
end

function bank.mirrorApplySearch()
    local f = bank.mirrorFrame
    if not f then return end
    local q = f.search and f.search:GetText() or ""
    q = q:lower():gsub("^%s+", ""):gsub("%s+$", "")
    for _, b in ipairs(f.btns) do
        if b:IsShown() then
            local match = (q == "")
                or (ns.ItemSearchMatch and ns.ItemSearchMatch(b.link, b.quality, q))
            b:SetAlpha(match and 1 or 0.25)
        end
    end
end

function bank.renderMirror()
    local f = bank.mirrorFrame
    if not f then return end
    local mir = _G.VuloClassicUICharDB and _G.VuloClassicUICharDB.bankMirror
    local S, G, COLS = 30, 3, 12
    local left, top = PAD, 64
    local width = PAD * 2 + COLS * (S + G) - G

    for _, b in ipairs(f.btns) do b:Hide() end
    for _, h in ipairs(f.heads) do h:Hide() end

    if not (mir and mir.bags and #mir.bags > 0) then
        f.hint:Show()
        f.sub:SetText("")
        f:SetSize(width, 120)
        return
    end
    f.hint:Hide()

    local bi, hi = 0, 0
    local y = top
    for _, bagData in ipairs(mir.bags) do
        hi = hi + 1
        local h = bank.mirrorHeader(hi)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", f, "TOPLEFT", left, -y)
        h:SetText(bagData.name or "")
        h:Show()
        y = y + 16
        local col = 0
        for _, it in ipairs(bagData.slots) do
            bi = bi + 1
            local b = bank.mirrorButton(bi)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", left + col * (S + G), -y)
            b.link, b.quality = it.l, it.q
            b.icon:SetTexture(it.i or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.count:SetText((it.c or 1) > 1 and it.c or "")
            local r, g, bl = 0, 0, 0
            if (it.q or 1) > 1 and GetItemQualityColor then
                r, g, bl = GetItemQualityColor(it.q)
            end
            b.border:SetColorTexture(r or 0, g or 0, bl or 0, 1)
            b:SetAlpha(1)
            b:Show()
            col = col + 1
            if col >= COLS then col = 0; y = y + S + G end
        end
        if col > 0 then y = y + S + G end
        y = y + 6
    end

    if mir.when and mir.when > 0 and date then
        f.sub:SetText(string.format(L["As of: %s"], date("%d.%m.%Y %H:%M", mir.when))
            .. "  |cff888888" .. string.format(L["%d free slots"], mir.free or 0) .. "|r")
    else
        f.sub:SetText("")
    end

    f:SetSize(width, y + PAD)
    bank.mirrorApplySearch()
end

function bank.buildMirror()
    if bank.mirrorFrame then return bank.mirrorFrame end
    local f = CreateFrame("Frame", "VCUI_BankMirror", UIParent)
    bank.mirrorFrame = f
    f.btns, f.heads = {}, {}
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local d = bank.db()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux then d.mirrorX, d.mirrorY = cx - ux, cy - uy end
    end)
    f:SetScript("OnHide", function(self) self:StopMovingOrSizing() end)
    if ns.UI and ns.UI.StyleBackdrop then
        ns.UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border })
    end
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY")
    if ns.UI and ns.UI.Font then ns.UI.Font(f.title, 13) else f.title:SetFontObject(GameFontNormal) end
    f.title:SetPoint("TOPLEFT", PAD, -10)
    f.title:SetTextColor(1, 1, 1, 1)
    f.title:SetText(L["Bank contents"])

    f.sub = f:CreateFontString(nil, "OVERLAY")
    if ns.UI and ns.UI.Font then ns.UI.Font(f.sub, 10) else f.sub:SetFontObject(GameFontDisableSmall) end
    f.sub:SetPoint("TOPLEFT", PAD, -28)
    f.sub:SetTextColor(0.7, 0.7, 0.75, 1)

    f.hint = f:CreateFontString(nil, "OVERLAY")
    if ns.UI and ns.UI.Font then ns.UI.Font(f.hint, 11) else f.hint:SetFontObject(GameFontDisableSmall) end
    f.hint:SetPoint("TOPLEFT", PAD, -64)
    f.hint:SetTextColor(0.7, 0.7, 0.75, 1)
    f.hint:SetText(L["No bank visit recorded on this character yet."])
    f.hint:Hide()

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -6, -6)
    close.x = close:CreateFontString(nil, "OVERLAY")
    if ns.UI and ns.UI.Font then ns.UI.Font(close.x, 14) else close.x:SetFontObject(GameFontNormal) end
    close.x:SetPoint("CENTER")
    close.x:SetText("x")
    close.x:SetTextColor(0.7, 0.7, 0.75, 1)
    close:SetScript("OnEnter", function() close.x:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1) end)
    close:SetScript("OnLeave", function() close.x:SetTextColor(0.7, 0.7, 0.75, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)

    f.search = CreateFrame("EditBox", nil, f)
    f.search:SetSize(180, 18)
    f.search:SetPoint("TOPLEFT", PAD + 2, -42)
    f.search:SetAutoFocus(false)
    -- an EditBox WITHOUT a font hard-errors on input
    if ns.UI and ns.UI.Font then ns.UI.Font(f.search, 11)
    else f.search:SetFontObject(_G.ChatFontNormal or GameFontNormalSmall) end
    f.search:SetTextColor(0.9, 0.9, 0.95, 1)
    local sline = f:CreateTexture(nil, "ARTWORK")
    sline:SetPoint("TOPLEFT", f.search, "BOTTOMLEFT", -2, -2)
    sline:SetPoint("TOPRIGHT", f.search, "BOTTOMRIGHT", 2, -2)
    sline:SetHeight(1)
    sline:SetColorTexture(0.3, 0.3, 0.35, 1)
    f.search:SetScript("OnTextChanged", function() bank.mirrorApplySearch() end)
    f.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    f.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    table.insert(UISpecialFrames, "VCUI_BankMirror")
    return f
end

function ns.ToggleBankMirror()
    local f = bank.buildMirror()
    if f:IsShown() then f:Hide(); return end
    local d = bank.db()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", d.mirrorX or 300, d.mirrorY or 0)
    bank.renderMirror()
    f:Show()
end

function bank.onEvent(event, arg1, arg2)
    if event == "PLAYER_ENTERING_WORLD" then
        -- suppress BEFORE the first banker visit: Blizzard's BankFrame OnEvent would otherwise ShowUIPanel on the very BANKFRAME_OPENED we react to
        if bank.enabled() then
            bank.suppressDefault()
            bank.build()
        end
        return
    end
    if event == "PLAYER_MONEY" then
        bank.updateMoney()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if bank.enabled() and not bank.suppressed then
            bank.suppressDefault()
        elseif bank.suppressed and not bank.enabled() then
            bank.restoreDefault()
        end
        if bank.pendingRelayout then bank.pendingRelayout = false; bank.refresh() end
        return
    end

    if event == "BANKFRAME_OPENED" then
        if not bank.enabled() then return end
        bank.open = true
        bank.mirrorScans = 0
        bank.suppressDefault()
        if not bank.frame then bank.build() end
        if not bank.frame then bank.open = false; return end
        bank.preallocate()
        bank.frame:Show()
        if bank.updateFilterBar then bank.updateFilterBar() end
        bank.refresh()   -- item data lags BANKFRAME_OPENED
        if not mod:IsOpen() then bank.autoOpenedBags = true; mod:Open() end
        return
    end
    if event == "BANKFRAME_CLOSED" then
        -- fires TWICE and on walking away; idempotent. Snapshot first, then clear bank.open so OnHide skips CloseBankFrame.
        bank.snapshotMirror(true)
        bank.open = false
        if ns.SortEngine and ns.SortEngine.CancelContaining then
            ns.SortEngine.CancelContaining(-1)
        end
        if bank.frame and bank.frame.search then bank.frame.search:SetText("") end
        if bank.frame and bank.frame:IsShown() then bank.frame:Hide() end
        if bank.autoOpenedBags then bank.autoOpenedBags = false; mod:Close() end
        return
    end

    if not (bank.open and bank.frame and bank.frame:IsShown()) then return end
    if event == "PLAYERBANKBAGSLOTS_CHANGED" then
        if bank.updateFilterBar then bank.updateFilterBar() end
        bank.refresh()
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        -- arg1 above NUM_BANKGENERIC_SLOTS means an equipped bank BAG changed
        if arg1 and arg1 > (_G.NUM_BANKGENERIC_SLOTS or 24) then
            if bank.updateFilterBar then bank.updateFilterBar() end
        end
        bank.refresh()
    elseif event == "BAG_UPDATE" then
        if arg1 and arg1 > (_G.NUM_BAG_SLOTS or 4) then bank.refresh() end
    elseif event == "ITEM_LOCK_CHANGED" then
        -- equipment locks pass a nil slot
        if arg2 and (arg1 == (_G.BANK_CONTAINER or -1) or arg1 > (_G.NUM_BAG_SLOTS or 4)) then
            bank.refresh()
        end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        bank.refresh()
    end
end

function ns.BankOptions()
    local items = {}
    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Bank"] })
    table.insert(items, {
        type = "toggle", label = L["Replace the bank window"],
        tooltip = L["Show your bank in a matching window when you visit a banker. Off = the default bank window."],
        get = function() return bank.db().enabled ~= false end,
        set = function(_, v)
            bank.db().enabled = v and true or false
            if v then
                if mod.active then bank.suppressDefault() end
            else
                if bank.frame and bank.frame:IsShown() then bank.frame:Hide() end
                bank.restoreDefault()
            end
        end,
    })
    table.insert(items, {
        type = "slider", label = L["Bank window scale"], min = 50, max = 150, step = 5,
        get = function() return (bank.db().scale or 1) * 100 end,
        set = function(_, v)
            bank.db().scale = v / 100
            if bank.mover and ns.MoverSetScale then ns:MoverSetScale(bank.mover, v / 100)
            elseif bank.frame then bank.frame:SetScale(v / 100) end
        end,
    })
    table.insert(items, {
        type = "slider", label = L["Bank grid columns"], min = 8, max = 24, step = 1,
        get = function() return bank.db().columns or 14 end,
        set = function(_, v)
            bank.db().columns = v
            if bank.open and bank.frame and bank.frame:IsShown() then bank.refresh() end
        end,
    })
    table.insert(items, {
        type = "button", label = L["Reset bank position"], width = 200,
        onClick = function()
            if bank.mover and ns.MoverSetCenter then
                ns:MoverSetCenter(bank.mover, -280, 0)
            else
                local d = bank.db(); d.x, d.y = -280, 0
            end
        end,
    })
    return items
end

function ns.BankRefresh()
    bank.refresh()
end

-- Bag search mirrors into an OPEN bank window; SetText routes through OnTextChanged, so there is no recursion back to bags.
function ns.BankMirrorSearch(text)
    if not (bank.open and bank.frame and bank.frame:IsShown() and bank.frame.search) then return end
    if bank.frame.search:GetText() ~= text then
        bank.frame.search:SetText(text)
    end
end

-- A re-enable without /reload must re-suppress now: PLAYER_ENTERING_WORLD won't re-fire until the next loading screen.
function ns.BankOnEnable()
    if bank.enabled() then
        bank.suppressDefault()
        bank.build()
    end
end

function ns.BankOnDisable()
    if bank.frame and bank.frame:IsShown() then bank.frame:Hide() end
    bank.restoreDefault()
end

-- Wired LAST: every bank.* handler above must already be defined.
for _, ev in ipairs({
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED",
    "PLAYERBANKBAGSLOTS_CHANGED",
    "BAG_UPDATE", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
    "PLAYER_MONEY",
}) do
    ns:RegisterEvent(ev, bank.onEvent)
end
