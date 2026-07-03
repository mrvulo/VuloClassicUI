-- =========================================================
-- VuloClassicUI / Modules / Bank  (Phase 4 STAGE-1 — core bank window)
-- Companion to Modules/Bags.lua: same module key "bags", same options page,
-- shared profile db. Opens on BANKFRAME_OPENED (and auto-opens the bag window),
-- closes on BANKFRAME_CLOSED, and ends the server-side bank session
-- (CloseBankFrame) when the user closes it manually (X / Escape).
--
-- TAINT DISCIPLINE (same rules as Bags.lua):
--   * every ITEM slot inherits Blizzard's own "ContainerFrameItemButtonTemplate"
--     (global name required on Classic). Pickup/use/split is the template's own
--     handler, which on these clients routes through C_Container with the
--     parent's bag id — including -1, exactly like Blizzard's own bank buttons
--     (Blizzard_UIPanels_Game/Vanilla/BankFrame.lua: BankFrameItemButtonGeneric_
--     OnClick -> C_Container.PickupContainerItem(-1, slot) / UseContainerItem).
--     We NEVER SetScript OnClick/OnDragStart. OnEnter/OnLeave ARE replaced —
--     that is tooltip-only, not a secure path, and mirrors Blizzard's own
--     BankFrameItemButton_OnEnter (the -1 container is inventory-slot-backed
--     for tooltips: BankButtonIDToInvSlotID + SetInventoryItem).
--   * bag id lives on the button's PARENT (SetID), slot id on the button.
--   * bank-bag-bar buttons are PLAIN insecure buttons: PutItemInBag,
--     PickupBagFromSlot, PurchaseSlot, GetNumBankSlots, GetBankSlotCost are all
--     unprotected on Classic (Blizzard calls PurchaseSlot from a plain
--     StaticPopup OnAccept). Disabled in combat, where bag pickup/drop fails.
--   * the default BankFrame is suppressed by REPARENTING to a hidden frame and
--     clearing its OnEvent/OnShow/OnHide (it is NOT a protected frame on
--     Classic). NEVER BankFrame:Hide() — that fires BANKFRAME_CLOSED and kills
--     the live session. Fully restored on module disable.
--
-- LOCALS BUDGET: exactly 8 top-level locals (_, ns, L, mod, BTN, GAP, PAD,
-- bank). ALL other state/functions are fields of `bank`, resolved through the
-- table at call time — so this file needs NO forward declarations at all.
-- =========================================================
local _, ns = ...
local L   = ns.L
local mod = ns.modules.bags   -- Bags.lua loads first (TOC order). mod.db is NOT
                              -- valid at file scope — read it only in handlers.
local BTN, GAP, PAD = 37, 4, 12   -- same grid metrics as the bag window

local bank = {
    frame        = nil,       -- the bank window (built at PLAYER_ENTERING_WORLD)
    buttons      = {},        -- pooled item buttons, by visual position
    indexFrames  = {},        -- [bagID] = plain Frame carrying SetID(bagID)
    bags         = {},        -- ordered container ids: -1 then 5..N (filled below)
    btnCounter   = 0,         -- global-name counter ("VuloClassicUIBankItem"..n)
    open         = false,     -- true between BANKFRAME_OPENED and (first) CLOSED
    autoOpenedBags   = false, -- we auto-opened the bag window -> auto-close it
    refreshScheduled = false,
    pendingRelayout  = false, -- combat-blocked layout; rerun on REGEN_ENABLED
    suppressed   = false,     -- default BankFrame currently suppressed
    origParent   = {},        -- [7..13] original ContainerFrame parents
    origScripts  = nil,       -- BankFrame's original parent + scripts (restore)
    hiddenHost   = nil,       -- permanently hidden parent (created below)
    mover        = nil,
    TOP          = 40,        -- title row (equip/purchase lives in the filter strip)
    BOTTOM       = 38,        -- footer (26) + bottom padding (12)
}

-- Bank container ids: -1 (BANK_CONTAINER, the 24/28 generic slots) plus the
-- bank bags NUM_BAG_SLOTS+1 .. NUM_BAG_SLOTS+NUM_BANKBAGSLOTS (5..10 on Era,
-- 5..11 on TBC). NEVER use Enum.BagIndex.BankBag_1..7 here — on the Classic
-- clients that enum still carries values from an old retail layout (6..12).
bank.bags[1] = _G.BANK_CONTAINER or -1
for i = 1, (_G.NUM_BANKBAGSLOTS or 6) do
    bank.bags[#bank.bags + 1] = (_G.NUM_BAG_SLOTS or 4) + i
end

bank.hiddenHost = CreateFrame("Frame")
bank.hiddenHost:Hide()

-- Cost-confirm for buying the next bank bag slot. We need our OWN dialog:
-- Blizzard's CONFIRM_BUY_BANK_SLOT dialog reads BankFrame.nextSlotCost, which
-- only BankFrame's OnEvent sets — and we clear that script while suppressing
-- the default bank. PurchaseSlot() is NOT protected on Classic (Blizzard calls
-- it from a plain StaticPopup OnAccept), so an insecure dialog is safe.
StaticPopupDialogs["VCUI_BANK_BUY_SLOT"] = {
    text = CONFIRM_BUY_BANK_SLOT,   -- Blizzard's already-localized confirm text
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

-- ---------------------------------------------------------
-- db / gates
-- ---------------------------------------------------------
function bank.db()
    local root = mod.db
    if not root then return { enabled = false } end   -- pre-init call: inert
    local d = root.bank
    if not d then   -- belt+suspenders; defaults normally merge this in
        d = { enabled = true, x = -280, y = 0, scale = 1.0, columns = 14, hiddenBags = {} }
        root.bank = d
    end
    d.hiddenBags = d.hiddenBags or {}
    return d
end

-- STAGE-2: the DISPLAYED container list (user can hide individual bank bags).
function bank.visibleBags()
    local hidden = bank.db().hiddenBags
    local out = {}
    for _, bag in ipairs(bank.bags) do
        if not hidden[bag] then out[#out + 1] = bag end
    end
    return out
end

-- Localized display name for a bank container (the -1 main bank / a bank bag).
function bank.bagName(bag)
    if bag == (_G.BANK_CONTAINER or -1) then return L["Bank"] end
    local i = bag - (_G.NUM_BAG_SLOTS or 4)   -- bank bag index 1..N
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

-- ---------------------------------------------------------
-- Default bank suppression (reparent + clear scripts; restore on disable).
-- BankFrame's OnEvent would ShowUIPanel it — and then CloseBankFrame() if it
-- isn't shown; its OnHide calls CloseBankFrame(). Both must be silenced so the
-- session belongs to OUR window. Bags.lua already handles ContainerFrame1..6;
-- the bank bags open into ContainerFrame7..13.
-- ---------------------------------------------------------
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
        -- if a race let the default bank open before we suppressed (e.g. module
        -- re-enable without /reload), clear its shown-flag now — safe: OnHide is
        -- already nil'd, so no CloseBankFrame fires and the session survives.
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
        -- never hand back a stranded-shown frame: hide while the scripts are
        -- still nil'd (no OnHide side effects), THEN restore parent + scripts.
        if bf:IsShown() then bf:Hide() end
        bf:SetParent(bank.origScripts.parent or UIParent)
        bf:SetScript("OnEvent", bank.origScripts.OnEvent)
        bf:SetScript("OnShow",  bank.origScripts.OnShow)
        bf:SetScript("OnHide",  bank.origScripts.OnHide)
    end
end

-- ---------------------------------------------------------
-- Item buttons (visuals mirror Bags.lua's updateButton, minus search dimming —
-- the bank has no search box in this stage)
-- ---------------------------------------------------------
function bank.updateButton(btn)
    local bag  = btn:GetParent():GetID()
    local slot = btn:GetID()
    -- the container API accepts -1 here — Blizzard's own bank reads item info
    -- exactly this way (BankFrame.lua: BankFrameItemButton_Update)
    local icon, count, locked, quality, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)

    SetItemButtonTexture(btn, icon)
    SetItemButtonCount(btn, count)
    SetItemButtonDesaturated(btn, locked)

    local ng = btn.NewItemTexture or _G[btn:GetName() .. "NewItemTexture"]
    if ng and ng:IsShown() then ng:Hide() end
    local bp = btn.BattlepayItemTexture or _G[btn:GetName() .. "BattlepayItemTexture"]
    if bp and bp:IsShown() then bp:Hide() end

    -- quality border + item level: same recipe as the bag window (crisp 1px
    -- edge for uncommon+; ilvl on weapons/armor, quality-coloured)
    local qf = btn._qborder
    if qf then
        if mod.db.qualityBorders ~= false and quality and quality >= 2 and GetItemQualityColor then
            local r, g, b = GetItemQualityColor(quality)
            qf:SetColorTexture(r, g, b, 1)
            qf:Show()
        else
            qf:Hide()
        end
    end
    local fs = btn._ilvl
    if fs then
        local lvl
        if mod.db.showItemLevel ~= false and link and GetItemInfoInstant then
            local _, _, _, equipLoc, _, classID = GetItemInfoInstant(link)
            if (classID == 2 or classID == 4) and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" then
                lvl = (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link))
                    or (GetItemInfo and select(4, GetItemInfo(link)))
            end
        end
        if lvl and lvl > 1 then
            -- same font/size as the stack-count numbers (follows the option live)
            if ns.UI and ns.UI.FONT_PATH then
                pcall(fs.SetFont, fs, ns.UI.FONT_PATH, mod.db.countFontSize or 12, "OUTLINE")
            end
            fs:SetText(lvl)   -- plain white (set at creation)
            fs:Show()
        else
            fs:Hide()
        end
    end

    local cnt = _G[btn:GetName() .. "Count"]
    if cnt and ns.UI and ns.UI.FONT_PATH then
        pcall(cnt.SetFont, cnt, ns.UI.FONT_PATH, mod.db.countFontSize or 12, "OUTLINE")
    end

    local cd = _G[btn:GetName() .. "Cooldown"]
    if cd then
        local start, dur, enable = GetContainerItemCooldown(bag, slot)
        if start and dur and dur > 0 then
            CooldownFrame_Set(cd, start, dur, enable)
        elseif cd.Hide then
            cd:Hide()
        end
    end

    -- STAGE-2: search dimming (same shared matcher as the bag window; alpha
    -- only — never Enable/Hide, so the secure click paths stay intact)
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

-- -1 tooltips: the bank main container is inventory-slot-backed, so the
-- template's own OnEnter (SetBagItem) is wrong for it. We REPLACE OnEnter/
-- OnLeave (tooltip-only scripts, not a secure path) and point UpdateTooltip at
-- the same function — the game calls button.UpdateTooltip directly to refresh
-- a held tooltip, which would otherwise bypass any hook. This mirrors
-- Blizzard's own BankFrameItemButton_OnEnter.
function bank.onEnterItem(self)
    local parent = self:GetParent()
    if parent and parent:GetID() == -1 and BankButtonIDToInvSlotID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(self:GetID())) then
            GameTooltip:Show()
        else
            GameTooltip:Hide()   -- empty -1 slot: no tooltip
        end
    elseif self._origOnEnter then
        self._origOnEnter(self)                  -- the template's own handler, captured at creation
    elseif ContainerFrameItemButton_OnEnter then
        ContainerFrameItemButton_OnEnter(self)   -- regular bank bags: template path
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")   -- last-resort: plain bag tooltip
        GameTooltip:SetBagItem(parent and parent:GetID(), self:GetID())
        GameTooltip:Show()
    end
end

function bank.onLeaveItem(self)
    local parent = self:GetParent()
    if parent and parent:GetID() == -1 then
        GameTooltip:Hide()
        if ResetCursor then ResetCursor() end
    elseif self._origOnLeave then
        self._origOnLeave(self)
    elseif ContainerFrameItemButton_OnLeave then
        ContainerFrameItemButton_OnLeave(self)
    else
        GameTooltip:Hide()
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
    -- capture the template's own tooltip handlers before replacing, so the
    -- non--1 branch can delegate to exactly what would have run anyway
    btn._origOnEnter = btn:GetScript("OnEnter")
    btn._origOnLeave = btn:GetScript("OnLeave")
    btn:SetScript("OnEnter", bank.onEnterItem)
    btn:SetScript("OnLeave", bank.onLeaveItem)
    btn.UpdateTooltip = bank.onEnterItem
    -- clean dark slots — same strip as the bag window (suppressed default bags
    -- mean "new item" flags never clear, so every overlay must go)
    local bname = btn:GetName()
    if btn.SetNormalTexture then pcall(btn.SetNormalTexture, btn, nil) end
    local nt = _G[bname .. "NormalTexture"]; if nt then nt:SetTexture(nil); nt:Hide() end
    if btn.GetNormalTexture then local g = btn:GetNormalTexture(); if g then g:SetTexture(nil); g:Hide() end end
    if btn.flashAnim and btn.flashAnim.Stop then btn.flashAnim:Stop() end
    if btn.newitemglowAnim and btn.newitemglowAnim.Stop then btn.newitemglowAnim:Stop() end
    local newTex = btn.NewItemTexture or _G[bname .. "NewItemTexture"]
    if newTex then newTex:Hide() end
    local bpTex = btn.BattlepayItemTexture or _G[bname .. "BattlepayItemTexture"]
    if bpTex then bpTex:Hide() end
    for r = 1, select("#", btn:GetRegions()) do
        local reg = select(r, btn:GetRegions())
        if reg and reg.GetObjectType and reg:GetObjectType() == "Texture" and reg.GetAtlas then
            local a = reg:GetAtlas()
            if type(a) == "string" and a:find("glow", 1, true) then reg:Hide() end
        end
    end
    local sb = btn:CreateTexture(nil, "BACKGROUND")
    sb:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    sb:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    sb:SetColorTexture(0.10, 0.10, 0.13, 0.55)
    -- quality border + item level (same recipe as the bag window: a full-button
    -- colour layer behind the 1px-inset icon — a filled ring can never drop a
    -- side and stays evenly thin at every resolution/scale)
    local qb = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    qb:SetAllPoints(btn)
    -- no pixel snapping on ring/icon: anti-aliased edges keep the ring evenly
    -- thick on all sides (see the bag window's note)
    if qb.SetSnapToPixelGrid then qb:SetSnapToPixelGrid(false); qb:SetTexelSnappingBias(0) end
    qb:Hide()
    btn._qborder = qb
    local iconTex = _G[bname .. "IconTexture"] or btn.icon
    if iconTex then
        iconTex:ClearAllPoints()
        iconTex:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        iconTex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- crop the icon's own dark bevel
        if iconTex.SetSnapToPixelGrid then iconTex:SetSnapToPixelGrid(false); iconTex:SetTexelSnappingBias(0) end
    end
    local il = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    il:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    il:SetTextColor(1, 1, 1)
    il:Hide()
    btn._ilvl = il
    btn:Hide()
    bank.buttons[n] = btn
    return btn
end

-- Pre-allocate index frames + item buttons for the CURRENT bank size. Called
-- out of combat (login build + BANKFRAME_OPENED — bankers can't be used in
-- combat). Container SIZES are readable already at OPENED (Blizzard reads them
-- there); only item CONTENT reads are deferred a frame (bank.refresh).
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

-- (The old in-window equip/purchase bag row was removed: the filter strip above
-- the window covers show/hide, equip/pickup AND purchase — see build().)

-- ---------------------------------------------------------
-- Frame construction (out of combat; built eagerly at PLAYER_ENTERING_WORLD so
-- even a first-ever banker visit that happens mid-combat has a window ready)
-- ---------------------------------------------------------
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

    -- Manual close (X / Escape via UISpecialFrames) must END the server bank
    -- session, or right-click deposits keep working with no window and no fresh
    -- BANKFRAME_OPENED can arrive. Guarded by bank.open so the
    -- BANKFRAME_CLOSED -> Hide() path doesn't re-call it.
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

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -7)
    local cx = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cx:SetPoint("CENTER"); cx:SetText("x"); cx:SetTextColor(0.7, 0.7, 0.75)
    close:SetScript("OnEnter", function() cx:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b) end)
    close:SetScript("OnLeave", function() cx:SetTextColor(0.7, 0.7, 0.75) end)
    close:SetScript("OnClick", function() f:Hide() end)   -- OnHide ends the session

    -- STAGE-2: search box (mirrors the bag window's; dims non-matches only)
    local sb = CreateFrame("EditBox", nil, f)
    f.search = sb
    sb:SetAutoFocus(false)
    sb:SetSize(120, 18)
    sb:SetPoint("RIGHT", close, "LEFT", -8, 0)
    if UI and UI.FONT_PATH then sb:SetFont(UI.FONT_PATH, 11, "") end
    sb:SetMaxLetters(40)
    sb:SetTextInsets(22, 8, 0, 0)
    sb:SetTextColor(0.9, 0.9, 0.95)
    local sbBg = sb:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints(sb); sbBg:SetColorTexture(0.04, 0.04, 0.055, 0.95)
    local sbIcon = sb:CreateTexture(nil, "OVERLAY")
    sbIcon:SetSize(11, 11)
    sbIcon:SetPoint("LEFT", sb, "LEFT", 6, 0)
    sbIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    sbIcon:SetVertexColor(0.55, 0.55, 0.62)
    local sbBorder = CreateFrame("Frame", nil, sb, BackdropTemplateMixin and "BackdropTemplate")
    sbBorder:SetAllPoints(sb)
    if sbBorder.SetBackdrop then
        sbBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        sbBorder:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    end
    sb:SetScript("OnEditFocusGained", function()
        if sbBorder.SetBackdropBorderColor then sbBorder:SetBackdropBorderColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1) end
    end)
    sb:SetScript("OnEditFocusLost", function()
        if sbBorder.SetBackdropBorderColor then sbBorder:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1) end
    end)
    sb:SetScript("OnTextChanged", function(self)
        bank.searchText = (self:GetText() or ""):lower()
        bank.refresh()
    end)
    sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    sb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)

    -- STAGE-2: sort button (left of the search box). Uses the shared machinery
    -- + settings from the bag window; native bank sort when the client has one.
    local sortBtn = CreateFrame("Button", nil, f)
    sortBtn:SetSize(18, 18)
    sortBtn:SetPoint("RIGHT", sb, "LEFT", -8, 0)
    local si = sortBtn:CreateTexture(nil, "ARTWORK")
    si:SetAllPoints(); si:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    si:SetVertexColor(0.7, 0.7, 0.75)
    sortBtn:SetScript("OnEnter", function()
        si:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        if GameTooltip then
            GameTooltip:SetOwner(sortBtn, "ANCHOR_TOP")
            GameTooltip:SetText(L["Sort bank"])
            GameTooltip:Show()
        end
    end)
    sortBtn:SetScript("OnLeave", function() si:SetVertexColor(0.7, 0.7, 0.75); if GameTooltip then GameTooltip:Hide() end end)
    sortBtn:SetScript("OnClick", function()
        if not bank.open then return end
        if ns.RunBagSort then
            ns.RunBagSort(bank.bags,
                (_G.C_Container and _G.C_Container.SortBankBags) or _G.SortBankBags)
        end
    end)

    -- STAGE-2: bank-bag filter button (left of sort) — checkable menu with the
    -- main bank (-1) + every equipped bank bag; hidden ones aren't rendered.
    local bagsBtn = CreateFrame("Button", nil, f)
    bagsBtn:SetSize(18, 18)
    bagsBtn:SetPoint("RIGHT", sortBtn, "LEFT", -8, 0)
    local bfi = bagsBtn:CreateTexture(nil, "ARTWORK")
    bfi:SetAllPoints(); bfi:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
    bfi:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bfi:SetVertexColor(0.7, 0.7, 0.75)
    bagsBtn:SetScript("OnEnter", function()
        bfi:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        if GameTooltip then
            GameTooltip:SetOwner(bagsBtn, "ANCHOR_TOP")
            GameTooltip:SetText(L["Show or hide bags"])
            GameTooltip:Show()
        end
    end)
    bagsBtn:SetScript("OnLeave", function() bfi:SetVertexColor(0.7, 0.7, 0.75); if GameTooltip then GameTooltip:Hide() end end)

    -- STAGE-2: visual filter strip (same UX as the bag window) — icons for the
    -- main bank + every bank bag SLOT. It replaces the old in-window equip row:
    --   left-click  = show/hide that container in the grid (hidden = dimmed)
    --   right-click = pick up / equip the bag, or BUY the next slot (green)
    --   drag a bag onto an owned slot = equip it
    -- Plain insecure buttons; equip/purchase APIs are unprotected on Classic
    -- but fail in combat -> handlers combat-guard themselves.
    local fbar = CreateFrame("Frame", nil, f)
    f.filterBar = fbar
    fbar:SetSize(#bank.bags * (26 + GAP) - GAP + 12, 34)
    fbar:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
    if UI and UI.StyleBackdrop then UI:StyleBackdrop(fbar, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border }) end
    fbar:Hide()
    fbar._icons = {}
    local function slotIndexOf(bag)   -- bank bag index 1..N; nil for the -1 container
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
                tex = "Interface\\Icons\\INV_Box_02"            -- the main bank
            elseif i <= owned then
                local inv = BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(i, 1)
                local t = inv and GetInventoryItemTexture("player", inv)
                if t then tex = t else desat = true end          -- owned but empty slot
            elseif i == owned + 1 then
                vr, vg, vb = 0.4, 1, 0.4                         -- next purchasable
            else
                vr, vg, vb, desat = 1, 0.25, 0.25, true          -- locked
            end
            ic._tex:SetTexture(tex)
            ic._tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            ic._tex:SetDesaturated(desat or not on)
            ic._tex:SetVertexColor(vr, vg, vb, on and 1 or 0.35)
        end
    end
    local function equipOrBuy(b)   -- right-click / drag action for one strip icon
        if InCombatLockdown() then return end
        local i = slotIndexOf(b)
        if not i then return end                                 -- -1: nothing to equip
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
            if CursorHasItem and CursorHasItem() then equipOrBuy(b); return end  -- click-with-bag = equip
            local hidden = bank.db().hiddenBags
            hidden[b] = not hidden[b] or nil
            bank.updateFilterBar()
            bank.refresh()
        end)
        ic:SetScript("OnReceiveDrag", function() if CursorHasItem and CursorHasItem() then equipOrBuy(b) end end)
        ic:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
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
        ic:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
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
    f.content:SetSize(100, 100)   -- real size set by layout()

    f.free = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.free:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 8)

    -- STAGE-2: money display (bottom right, mirrors the bag window) + the
    -- account-gold tooltip on mouseover
    f.money = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 8)
    local moneyBtn = CreateFrame("Button", nil, f)
    moneyBtn:SetPoint("TOPLEFT", f.money, "TOPLEFT", -4, 2)
    moneyBtn:SetPoint("BOTTOMRIGHT", f.money, "BOTTOMRIGHT", 4, -2)
    moneyBtn:SetScript("OnEnter", function(self)
        if ns.ShowGoldTooltip then ns.ShowGoldTooltip(self) end
    end)
    moneyBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    bank.updateMoney()

    -- movable + scalable via our mover; SEPARATE db keys (mod.db.bank.*) so the
    -- bank never collides with the bag window's coordinates. The distinct frame
    -- name also gives layouts/export a distinct key.
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
        local x, y = ns:GetCenterOffsets(self)   -- canonical scale-aware capture
        if x and y then
            local d = bank.db()
            d.x, d.y = x, y
            if ns.ApplyMover and bank.mover then ns:ApplyMover(bank.mover) end
        end
    end)

    bank.preallocate()
    return f
end

-- ---------------------------------------------------------
-- Layout: one flat grid across -1 then each purchased bank bag, in slot order.
-- (Categories/search/keyring are later stages.)
-- ---------------------------------------------------------
function bank.layout()
    if not (bank.frame and bank.open) then return end
    local cols = bank.db().columns or 14
    if cols < 1 then cols = 1 end
    local f = bank.frame

    -- Height cap: a fully-bagged bank (TBC: 28 + 7 big bags) at a low column
    -- setting would push the window past the screen edges (movers don't clamp),
    -- leaving the close button unreachable. If the user's column count would
    -- exceed ~70% of the screen height, raise the EFFECTIVE column count for
    -- this layout only — the saved setting stays untouched.
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
        -- (gated above); unpurchased/empty bag slots return 0 and don't render.
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
        bank.frame.money:SetText(GetCoinTextureString(GetMoney() or 0))
    end
end

-- coalesce event bursts into ONE relayout next frame. This also covers the
-- "item data lags BANKFRAME_OPENED" rule: never scan in the event itself.
function bank.refresh()
    if not (bank.open and bank.frame and bank.frame:IsShown()) then return end
    if bank.refreshScheduled then return end
    bank.refreshScheduled = true
    local function run()
        bank.refreshScheduled = false
        if bank.open and bank.frame and bank.frame:IsShown() then bank.layout() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

-- ---------------------------------------------------------
-- Events
-- ---------------------------------------------------------
function bank.onEvent(event, arg1, arg2)
    -- lifecycle / combat first: these run even while the bank is closed
    if event == "PLAYER_ENTERING_WORLD" then
        -- suppress BEFORE the first banker visit: Blizzard's BankFrame OnEvent
        -- (registered long before ours) would otherwise ShowUIPanel on the very
        -- BANKFRAME_OPENED we react to. Idempotent; zoning re-fires are no-ops.
        -- Build the window eagerly too (out of combat here), so even a
        -- first-ever banker visit that lands mid-combat has a frame ready.
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
        -- suppression/restore may have been combat-deferred in either direction
        if bank.enabled() and not bank.suppressed then
            bank.suppressDefault()
        elseif bank.suppressed and not bank.enabled() then
            bank.restoreDefault()
        end
        if bank.pendingRelayout then bank.pendingRelayout = false; bank.refresh() end
        return
    end

    if event == "BANKFRAME_OPENED" then
        if not bank.enabled() then return end   -- leave the default bank alone
        bank.open = true
        bank.suppressDefault()
        if not bank.frame then bank.build() end -- normally pre-built at login
        if not bank.frame then bank.open = false; return end
        bank.preallocate()   -- sizes are readable at OPENED; contents come a frame later
        bank.frame:Show()
        if bank.updateFilterBar then bank.updateFilterBar() end
        bank.refresh()   -- one-frame deferral: item data lags BANKFRAME_OPENED
        if not mod:IsOpen() then bank.autoOpenedBags = true; mod:Open() end
        return
    end
    if event == "BANKFRAME_CLOSED" then
        -- fires TWICE, and also when just walking away; everything here is
        -- idempotent. Clear bank.open FIRST so OnHide skips CloseBankFrame.
        bank.open = false
        -- a bank sort can't move items once the session is gone; stop it
        -- (leaves a running BAG sort alone — that one doesn't cover -1)
        if ns.SortEngine and ns.SortEngine.CancelContaining then
            ns.SortEngine.CancelContaining(-1)
        end
        if bank.frame and bank.frame.search then bank.frame.search:SetText("") end
        if bank.frame and bank.frame:IsShown() then bank.frame:Hide() end
        if bank.autoOpenedBags then bank.autoOpenedBags = false; mod:Close() end
        return
    end

    -- content events — only while our bank window is live and shown
    if not (bank.open and bank.frame and bank.frame:IsShown()) then return end
    if event == "PLAYERBANKBAGSLOTS_CHANGED" then
        if bank.updateFilterBar then bank.updateFilterBar() end   -- a bag slot was purchased
        bank.refresh()
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        -- arg1 <= NUM_BANKGENERIC_SLOTS: a -1 slot changed. Above that: an
        -- equipped bank BAG changed (equip/remove) -> bar icons + grid size.
        -- The event bursts one-per-slot; refresh() coalesces to one relayout.
        if arg1 and arg1 > (_G.NUM_BANKGENERIC_SLOTS or 24) then
            if bank.updateFilterBar then bank.updateFilterBar() end
        end
        bank.refresh()
    elseif event == "BAG_UPDATE" then
        -- only bank bags concern this window (contents of -1 come via
        -- PLAYERBANKSLOTS_CHANGED, never BAG_UPDATE); bags 0..4 are the bag
        -- window's business.
        if arg1 and arg1 > (_G.NUM_BAG_SLOTS or 4) then bank.refresh() end
    elseif event == "ITEM_LOCK_CHANGED" then
        -- container locks pass (bagID, slot); equipment locks pass a nil slot.
        -- Lock changes for the bank main container arrive with bagID == -1.
        if arg2 and (arg1 == (_G.BANK_CONTAINER or -1) or arg1 > (_G.NUM_BAG_SLOTS or 4)) then
            bank.refresh()
        end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        bank.refresh()
    end
end

-- ---------------------------------------------------------
-- Published hooks for Bags.lua (options splice + module disable)
-- ---------------------------------------------------------
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
                if bank.frame and bank.frame:IsShown() then bank.frame:Hide() end -- ends a live session
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
                ns:MoverSetCenter(bank.mover, -280, 0)   -- stage-1 default offset
            else
                local d = bank.db(); d.x, d.y = -280, 0  -- window not built yet
            end
        end,
    })
    return items
end

-- Published: repaint the bank grid (used by shared appearance options in
-- Bags.lua — quality borders / item levels / count size affect both windows).
function ns.BankRefresh()
    bank.refresh()
end

-- Called from mod:OnEnable() in Bags.lua — a module re-enable without /reload
-- must re-suppress the default bank immediately (PLAYER_ENTERING_WORLD won't
-- re-fire until the next loading screen, and Blizzard's BankFrame would win
-- the next BANKFRAME_OPENED otherwise).
function ns.BankOnEnable()
    if bank.enabled() then
        bank.suppressDefault()
        bank.build()
    end
end

-- Called from mod:OnDisable() in Bags.lua — hide our window (which ends any
-- live bank session via OnHide) and give Blizzard's default bank back.
function ns.BankOnDisable()
    if bank.frame and bank.frame:IsShown() then bank.frame:Hide() end
    bank.restoreDefault()
end

-- ---------------------------------------------------------
-- Event wiring — LAST in the file, so every bank.* handler above is defined.
-- Registered through the central dispatcher (Core/Events.lua), the same one
-- the bag module's own handler hangs off; handlers are pcall-isolated there.
-- Everything gates at runtime on mod.active + mod.db.bank.enabled, so a
-- disabled module/feature leaves the default bank completely alone.
-- ---------------------------------------------------------
for _, ev in ipairs({
    "PLAYER_ENTERING_WORLD",           -- suppress the default bank BEFORE first use
    "PLAYER_REGEN_ENABLED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED",         -- -1 contents AND equipped-bank-bag swaps
    "PLAYERBANKBAGSLOTS_CHANGED",      -- fires only when a bag slot is purchased
    "BAG_UPDATE", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
    "PLAYER_MONEY",                    -- STAGE-2: money display bottom right
}) do
    ns:RegisterEvent(ev, bank.onEvent)
end
