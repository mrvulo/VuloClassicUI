-- =========================================================
-- VuloClassicUI / Modules / GuildBank
-- Companion to Modules/Bags.lua + Bank.lua: same module key "bags", same
-- options page, shared profile db. Replaces the default guild bank window
-- (TBC Anniversary has guild banks; on Classic Era this file stays inert).
--
-- KEY FACTS (verified against the 2.5.5 client UI source + a live
-- implementation shipping on this exact client):
--   * open/close is driven by PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE with
--     Enum.PlayerInteractionType.GuildBanker; GUILDBANKFRAME_OPENED/CLOSED are
--     registered as idempotent fallbacks only.
--   * UIParent's own GUILDBANKFRAME_OPENED handler calls CloseGuildBankFrame()
--     whenever GuildBankFrame isn't visible after ShowUIPanel — with the frame
--     reparented away that would kill EVERY session. UIParent:UnregisterEvent
--     for both events at enable is therefore mandatory (restored on disable).
--   * GuildBankFrame lives in the LoadOnDemand addon Blizzard_GuildBankUI —
--     suppression needs an ADDON_LOADED watcher plus an immediate pass when
--     the addon is already loaded. OnHide is nil'ed FIRST (it calls
--     CloseGuildBankFrame), then OnShow/OnEvent, then reparent to hidden host.
--   * ALL guild bank data/action APIs are plain UNPROTECTED globals — the item
--     buttons are plain insecure Buttons (base ItemButtonTemplate) with our own
--     handlers. No taint or hardware-event concerns anywhere in this flow.
--   * PickupGuildBankItem(tab, slot) is pickup AND place/deposit/swap in one;
--     AutoStoreGuildBankItem = right-click withdraw-to-bags; item data arrives
--     via GUILDBANKBAGSLOTS_CHANGED only AFTER QueryGuildBankTab(tab), and
--     only for the server-side CURRENT tab.
--
-- LOCALS BUDGET: exactly 8 top-level locals (_, ns, L, mod, BTN, GAP, PAD,
-- gb). All other state/functions are fields of `gb`, so no forward decls.
-- =========================================================
local _, ns = ...
local L   = ns.L
local mod = ns.modules.bags   -- Bags.lua loads first (TOC order). mod.db is NOT
                              -- valid at file scope — read it only in handlers.
local BTN, GAP, PAD = 37, 4, 12

-- hard gate: no guild bank API surface on this client -> whole file inert
if not (_G.GetGuildBankItemInfo and _G.QueryGuildBankTab) then return end

local gb = {
    frame        = nil,
    buttons      = {},        -- pooled item buttons, by slot 1..98
    tabButtons   = {},        -- pooled tab-strip buttons
    open         = false,
    currentTab   = 1,
    refreshScheduled = false,
    pendingSuppress  = false, -- combat-deferred neuter/restore
    suppressed   = false,     -- GuildBankFrame currently neutered
    uipDisarmed  = false,     -- UIParent's GUILDBANKFRAME_* events unregistered
    origScripts  = nil,       -- GuildBankFrame's original parent + scripts
    hiddenHost   = nil,
    hooksInstalled = false,
    bindTypeCache = {},       -- [itemID] = bindType (0 = binds never/other)
    dirtyTabs    = {},        -- source tabs of cross-tab moves -> re-query
    tabSig       = nil,       -- last tab-bar snapshot (skip pointless rebuilds)
    mover        = nil,
    searchText   = "",
    SLOTS        = 98,        -- MAX_GUILDBANK_SLOTS_PER_TAB on 2.5.5
    TOP          = 76,        -- title row (40) + tab strip (36)
    BOTTOM       = 54,        -- two footer rows: money/allowance + buttons
}

gb.hiddenHost = CreateFrame("Frame")
gb.hiddenHost:Hide()

-- ---------------------------------------------------------
-- db / gates
-- ---------------------------------------------------------
function gb.db()
    local root = mod.db
    if not root then return { enabled = false } end
    local d = root.guildBank
    if not d then
        d = { enabled = true, x = 280, y = 0, scale = 1.0, columns = 14 }
        root.guildBank = d
    end
    return d
end

-- capability: Blizzard's own gate; exists on 2.5.5 AND 1.15.8 (false there).
-- Re-evaluated at every call so a mid-phase unlock is picked up.
function gb.capable()
    if C_GuildBank and C_GuildBank.IsGuildBankEnabled then
        return C_GuildBank.IsGuildBankEnabled() and true or false
    end
    return true   -- API surface exists (file-top gate) but no capability probe
end

function gb.enabled()
    return mod.active and gb.db().enabled ~= false and gb.capable()
end

-- ---------------------------------------------------------
-- Default guild bank suppression.
-- Step 1: disarm UIParent's GUILDBANKFRAME_* handlers (its OPENED fallback
--         closes the session when the neutered frame isn't visible).
-- Step 2: neuter GuildBankFrame itself once Blizzard_GuildBankUI is loaded.
-- Both fully restored on disable.
-- ---------------------------------------------------------
function gb.disarmUIParent()
    if gb.uipDisarmed or not UIParent then return end
    gb.uipDisarmed = true
    UIParent:UnregisterEvent("GUILDBANKFRAME_OPENED")
    UIParent:UnregisterEvent("GUILDBANKFRAME_CLOSED")
end

function gb.rearmUIParent()
    if not gb.uipDisarmed or not UIParent then return end
    gb.uipDisarmed = false
    UIParent:RegisterEvent("GUILDBANKFRAME_OPENED")
    UIParent:RegisterEvent("GUILDBANKFRAME_CLOSED")
end

function gb.suppressDefault()
    -- the UIParent disarm is just event surgery — combat-legal, never defer it
    -- (a deferred disarm would let UIParent's OPENED fallback kill the session)
    gb.disarmUIParent()
    if InCombatLockdown() then gb.pendingSuppress = true; return end
    local f = _G.GuildBankFrame
    if not f or gb.suppressed then return end
    gb.suppressed = true
    if not gb.origScripts then
        gb.origScripts = {
            parent  = f:GetParent(),
            OnEvent = f:GetScript("OnEvent"),
            OnShow  = f:GetScript("OnShow"),
            OnHide  = f:GetScript("OnHide"),
        }
    end
    -- OnHide FIRST: reparenting to a hidden host hides the frame, and the
    -- live OnHide would CloseGuildBankFrame() and end the session.
    local wasShown = f:IsShown()
    f:SetScript("OnHide", nil)
    f:SetScript("OnShow", nil)
    f:SetScript("OnEvent", nil)
    f:SetParent(gb.hiddenHost)
    if wasShown then
        f:Hide()   -- safe: scripts already nil'd
        -- the DEFAULT window was open mid-session (option flipped on at the
        -- banker): end the session cleanly instead of leaving it headless
        if CloseGuildBankFrame then CloseGuildBankFrame() end
    end
end

function gb.restoreDefault()
    gb.rearmUIParent()   -- combat-legal, never defer
    if InCombatLockdown() then gb.pendingSuppress = true; return end
    local f = _G.GuildBankFrame
    if f and gb.suppressed and gb.origScripts then
        if f:IsShown() then f:Hide() end   -- while scripts are still nil'd
        f:SetParent(gb.origScripts.parent or UIParent)
        f:SetScript("OnEvent", gb.origScripts.OnEvent)
        f:SetScript("OnShow",  gb.origScripts.OnShow)
        f:SetScript("OnHide",  gb.origScripts.OnHide)
    end
    gb.suppressed = false
end

-- ---------------------------------------------------------
-- Money popups: our own dialogs (Blizzard's read the neutered frame's state).
-- Deposit/WithdrawGuildBankMoney are plain unprotected globals. Amounts are
-- typed in GOLD and converted to copper.
-- ---------------------------------------------------------
function gb.popupAmount(self)
    local box = self.editBox or _G[self:GetName() .. "EditBox"]
    local g = box and tonumber(box:GetText() or "")
    if not g or g <= 0 then return 0 end
    return math.floor(g * 10000)
end

StaticPopupDialogs["VCUI_GBANK_DEPOSIT"] = {
    text = "%s", button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = 1, timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
    EditBoxOnEnterPressed = function(box)
        local p = box:GetParent()
        local b1 = p.button1 or (p.GetName and _G[p:GetName() .. "Button1"])
        if b1 then b1:Click() end
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    OnAccept = function(self)
        if InCombatLockdown() then return end
        local copper = gb.popupAmount(self)
        if copper > 0 and DepositGuildBankMoney then
            DepositGuildBankMoney(math.min(copper, GetMoney() or 0))
        end
    end,
}

StaticPopupDialogs["VCUI_GBANK_WITHDRAW"] = {
    text = "%s", button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = 1, timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
    EditBoxOnEnterPressed = function(box)
        local p = box:GetParent()
        local b1 = p.button1 or (p.GetName and _G[p:GetName() .. "Button1"])
        if b1 then b1:Click() end
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    OnAccept = function(self)
        if InCombatLockdown() then return end
        local copper = gb.popupAmount(self)
        if copper > 0 and WithdrawGuildBankMoney then
            WithdrawGuildBankMoney(math.min(copper, gb.withdrawable()))
        end
    end,
}

StaticPopupDialogs["VCUI_GBANK_BUY_TAB"] = {
    text = "%s", button1 = YES, button2 = NO,
    hasMoneyFrame = 1, timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self)
        local mf = self.moneyFrame or _G[self:GetName() .. "MoneyFrame"]
        if mf and MoneyFrame_Update and GetGuildBankTabCost then
            MoneyFrame_Update(mf, GetGuildBankTabCost() or 0)
        end
    end,
    OnAccept = function() if BuyGuildBankTab then BuyGuildBankTab() end end,
}

-- money the player may take out right now: sign-check BEFORE any clamping —
-- GetGuildBankWithdrawMoney() returns -1 for "unlimited" (guild master).
function gb.withdrawable()
    local guildMoney = (GetGuildBankMoney and GetGuildBankMoney()) or 0
    local w = (GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()) or 0
    if w < 0 then return guildMoney end
    return math.min(w, guildMoney)
end

-- ---------------------------------------------------------
-- Search (own matcher: the shared one reads container APIs)
-- ---------------------------------------------------------
function gb.itemMatches(tab, slot, q)
    if not q or q == "" then return true end
    local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
    if not link then return false end
    -- shared smart matcher (plain terms + q:/typ:/ilvl> filters)
    if ns.ItemSearchMatch then
        local _, _, _, _, quality = GetGuildBankItemInfo(tab, slot)
        if quality and quality < 0 then quality = nil end
        return ns.ItemSearchMatch(link, quality, q)
    end
    return link:lower():find(q, 1, true) and true or false
end

-- ---------------------------------------------------------
-- Item buttons: plain insecure, base ItemButtonTemplate (always available —
-- the guild template lives in the LoD addon). Visuals mirror the bank window.
-- ---------------------------------------------------------
function gb.onClickItem(self, mouseButton)
    local tab, slot = self.tabIndex, self:GetID()
    if not (gb.open and tab and slot) then return end
    local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
    if link and HandleModifiedItemClick and HandleModifiedItemClick(link) then return end
    if GetCurrentGuildBankTab and GetCurrentGuildBankTab() ~= tab and SetCurrentGuildBankTab then
        SetCurrentGuildBankTab(tab)   -- moves act on the server-side current tab
    end
    if IsModifiedClick and IsModifiedClick("SPLITSTACK") and not (CursorHasItem and CursorHasItem()) then
        local _, count, locked = GetGuildBankItemInfo(tab, slot)
        if not locked and count and count > 1 and OpenStackSplitFrame then
            OpenStackSplitFrame(count, self, "BOTTOMLEFT", "TOPLEFT")
        end
        return
    end
    local ctype, cmoney = GetCursorInfo()
    if ctype == "money" then
        if DepositGuildBankMoney then DepositGuildBankMoney(cmoney) end
        ClearCursor()
        return
    elseif ctype == "guildbankmoney" then
        if DropCursorMoney then DropCursorMoney() end
        ClearCursor()
        return
    end
    if mouseButton == "RightButton" then
        if AutoStoreGuildBankItem then AutoStoreGuildBankItem(tab, slot) end
        if GameTooltip then GameTooltip:Hide() end
        return
    end
    if PickupGuildBankItem then PickupGuildBankItem(tab, slot) end
end

function gb.onDragItem(self)
    local tab, slot = self.tabIndex, self:GetID()
    if not (gb.open and tab and slot) then return end
    if GetCurrentGuildBankTab and GetCurrentGuildBankTab() ~= tab and SetCurrentGuildBankTab then
        SetCurrentGuildBankTab(tab)
    end
    if PickupGuildBankItem then PickupGuildBankItem(tab, slot) end
end

function gb.onEnterItem(self)
    if not (gb.open and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetGuildBankItem(self.tabIndex, self:GetID())
end

function gb.onLeaveItem()
    if GameTooltip then GameTooltip:Hide() end
    if ResetCursor then ResetCursor() end
end

function gb.acquireButton(n)
    local btn = gb.buttons[n]
    if btn then return btn end
    if InCombatLockdown() then return nil end
    btn = CreateFrame("Button", "VuloClassicUIGuildItem" .. n, gb.frame.content, "ItemButtonTemplate")
    btn:SetSize(BTN, BTN)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnClick", gb.onClickItem)
    btn:SetScript("OnDragStart", gb.onDragItem)
    btn:SetScript("OnReceiveDrag", gb.onDragItem)
    btn:SetScript("OnEnter", gb.onEnterItem)
    btn:SetScript("OnLeave", gb.onLeaveItem)
    btn.UpdateTooltip = gb.onEnterItem
    -- the split popup calls button:SplitStack(amount) on OK
    btn.SplitStack = function(b, split)
        if gb.open and SplitGuildBankItem and split and split > 0 then
            SplitGuildBankItem(b.tabIndex, b:GetID(), split)
        end
    end
    -- clean dark slot look (same strip + ring recipe as the bank window)
    local bname = btn:GetName()
    if btn.SetNormalTexture then pcall(btn.SetNormalTexture, btn, nil) end
    local nt = _G[bname .. "NormalTexture"]; if nt then nt:SetTexture(nil); nt:Hide() end
    if btn.GetNormalTexture then local g = btn:GetNormalTexture(); if g then g:SetTexture(nil); g:Hide() end end
    local sb = btn:CreateTexture(nil, "BACKGROUND")
    sb:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    sb:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    sb:SetColorTexture(0.10, 0.10, 0.13, 0.55)
    local qb = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    qb:SetAllPoints(btn)
    if qb.SetSnapToPixelGrid then qb:SetSnapToPixelGrid(false); qb:SetTexelSnappingBias(0) end
    qb:Hide()
    btn._qborder = qb
    local iconTex = _G[bname .. "IconTexture"] or btn.icon
    if iconTex then
        iconTex:ClearAllPoints()
        iconTex:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        iconTex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if iconTex.SetSnapToPixelGrid then iconTex:SetSnapToPixelGrid(false); iconTex:SetTexelSnappingBias(0) end
    end
    local il = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    il:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    il:SetTextColor(1, 1, 1)
    il:Hide()
    btn._ilvl = il
    local bm = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    bm:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    bm:SetTextColor(0.45, 0.75, 1)
    bm:Hide()
    btn._bind = bm
    btn:Hide()
    gb.buttons[n] = btn
    return btn
end

function gb.updateButton(btn)
    local tab, slot = btn.tabIndex, btn:GetID()
    local texture, count, locked, _, quality = GetGuildBankItemInfo(tab, slot)
    local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)

    SetItemButtonTexture(btn, texture)
    SetItemButtonCount(btn, count)
    SetItemButtonDesaturated(btn, locked)   -- read LIVE every paint

    -- quality can be -1/nil on uncached guild items; derive from the link then
    if (not quality or quality < 0) and link and GetItemInfo then
        quality = select(3, GetItemInfo(link))
    end
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
            if ns.UI and ns.UI.FONT_PATH then
                pcall(fs.SetFont, fs, ns.UI.FONT_PATH, mod.db.countFontSize or 12, "OUTLINE")
            end
            fs:SetText(lvl)
            fs:Show()
        else
            fs:Hide()
        end
    end
    local cnt = _G[btn:GetName() .. "Count"]
    if cnt and ns.UI and ns.UI.FONT_PATH then
        pcall(cnt.SetFont, cnt, ns.UI.FONT_PATH, mod.db.countFontSize or 12, "OUTLINE")
    end

    -- bind marker: guild-banked items are never soulbound, so every BoE/BoU
    -- equipment piece here is tradeable by definition
    local bm = btn._bind
    if bm then
        local tag
        local itemID = link and tonumber(link:match("item:(%d+)"))
        if mod.db.bindMarker ~= false and link and itemID and GetItemInfo then
            local bindType = gb.bindTypeCache[itemID]
            if bindType == nil then
                local iname = GetItemInfo(link)
                if iname then
                    bindType = select(14, GetItemInfo(link)) or 0
                    gb.bindTypeCache[itemID] = bindType
                end
            end
            if bindType == 2 or bindType == 3 then
                local _, _, _, equipLoc, _, classID = GetItemInfoInstant(link)
                if (classID == 2 or classID == 4) and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" then
                    tag = (bindType == 2) and "BoE" or "BoU"
                end
            end
        end
        if tag then
            if ns.UI and ns.UI.FONT_PATH then
                pcall(bm.SetFont, bm, ns.UI.FONT_PATH,
                    math.max(8, (mod.db.countFontSize or 12) - 2), "OUTLINE")
            end
            bm:SetText(tag)
            bm:Show()
        else
            bm:Hide()
        end
    end

    if (gb.searchText or "") == "" then
        btn:SetAlpha(1)
    else
        btn:SetAlpha(gb.itemMatches(tab, slot, gb.searchText) and 1 or 0.25)
    end
end

-- ---------------------------------------------------------
-- Tab strip: one icon button per guild bank tab + optional buy button.
-- Rebuilt only when the tab meta actually changed (rapid clicks would other-
-- wise land on released buttons).
-- ---------------------------------------------------------
function gb.selectTab(i)
    if not gb.open then return end
    local _, _, viewable = GetGuildBankTabInfo(i)
    if not viewable then return end
    if gb.cancelSort then gb.cancelSort() end   -- never re-target a running sort
    if SetCurrentGuildBankTab then SetCurrentGuildBankTab(i) end
    if QueryGuildBankTab then QueryGuildBankTab(i) end
    gb.currentTab = i
    gb.tabSig = nil          -- active-tab highlight must repaint
    gb.updateTabs()
    gb.refresh()
end

function gb.updateTabs()
    local f = gb.frame
    if not f then return end
    local num = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
    local canBuy = gb.open and IsGuildLeader and IsGuildLeader()
        and num < (_G.MAX_BUY_GUILDBANK_TABS or 6)
        and GetGuildBankTabCost and GetGuildBankTabCost() ~= nil

    local sig = num .. "|" .. tostring(gb.currentTab) .. "|" .. tostring(canBuy)
    for i = 1, num do
        local name, icon, viewable = GetGuildBankTabInfo(i)
        sig = sig .. "|" .. tostring(name) .. "," .. tostring(icon) .. "," .. tostring(viewable)
    end
    if sig == gb.tabSig then return end

    local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
    local shownCount = 0
    for i = 1, num do
        local name, icon, viewable = GetGuildBankTabInfo(i)
        local tb = gb.tabButtons[i]
        if not tb then
            -- plain insecure buttons: creation is combat-legal, no bail needed
            tb = CreateFrame("Button", nil, f)
            tb:SetSize(30, 30)
            local ring = tb:CreateTexture(nil, "BACKGROUND")
            ring:SetAllPoints(tb)
            ring:SetColorTexture(0.22, 0.22, 0.26, 1)
            if ring.SetSnapToPixelGrid then ring:SetSnapToPixelGrid(false); ring:SetTexelSnappingBias(0) end
            tb._ring = ring
            local tex = tb:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", 1, -1); tex:SetPoint("BOTTOMRIGHT", -1, 1)
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            tb._tex = tex
            tb:SetScript("OnClick", function(self) gb.selectTab(self._tab) end)
            tb:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                local n2, _, v2, canDeposit, _, remaining = GetGuildBankTabInfo(self._tab)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(n2 or "")
                if not v2 then
                    GameTooltip:AddLine(L["This tab cannot be viewed."], 0.9, 0.35, 0.35)
                else
                    GameTooltip:AddLine(canDeposit and L["Deposits allowed."] or L["No deposits."], 0.7, 0.7, 0.7)
                    if remaining then
                        local txt = remaining < 0 and L["unlimited"] or tostring(remaining)
                        GameTooltip:AddLine(string.format(L["Withdrawals left: %s"], txt), 0.7, 0.7, 0.7)
                    end
                end
                GameTooltip:Show()
            end)
            tb:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            gb.tabButtons[i] = tb
        end
        tb._tab = i
        tb:ClearAllPoints()
        tb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * (30 + GAP), -40)
        tb._tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        tb._tex:SetDesaturated(not viewable)
        tb._tex:SetVertexColor(1, 1, 1, viewable and 1 or 0.4)
        if i == gb.currentTab then
            tb._ring:SetColorTexture(ac.r, ac.g, ac.b, 1)
        else
            tb._ring:SetColorTexture(0.22, 0.22, 0.26, 1)
        end
        tb:Show()
        shownCount = i
    end
    for i = num + 1, #gb.tabButtons do gb.tabButtons[i]:Hide() end

    -- buy-tab button right of the last tab (guild leader only)
    if canBuy then
        local bb = gb.buyBtn
        if not bb then
            bb = CreateFrame("Button", nil, f)
            bb:SetSize(30, 30)
            local ring = bb:CreateTexture(nil, "BACKGROUND")
            ring:SetAllPoints(bb); ring:SetColorTexture(0.22, 0.22, 0.26, 1)
            local plus = bb:CreateFontString(nil, "OVERLAY")
            if ns.UI and ns.UI.Font then ns.UI.Font(plus, 18) else plus:SetFontObject("GameFontNormalLarge") end
            plus:SetPoint("CENTER"); plus:SetText("+")
            plus:SetTextColor(0.4, 1, 0.4)
            bb:SetScript("OnClick", function()
                if not gb.open then return end
                StaticPopup_Show("VCUI_GBANK_BUY_TAB", L["Buy a guild bank tab?"])
            end)
            bb:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L["Buy a guild bank tab"])
                if SetTooltipMoney and GetGuildBankTabCost then
                    SetTooltipMoney(GameTooltip, GetGuildBankTabCost() or 0)
                end
                GameTooltip:Show()
            end)
            bb:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            gb.buyBtn = bb
        end
        if bb then
            bb:ClearAllPoints()
            bb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + shownCount * (30 + GAP), -40)
            bb:Show()
        end
    elseif gb.buyBtn then
        gb.buyBtn:Hide()
    end

    -- latch LAST: the strip is now known-complete for this signature
    gb.tabSig = sig
end

-- ---------------------------------------------------------
-- Money log: side panel with Blizzard's own localized log lines (the exact
-- "%s zahlte ... ein ( vor N Tagen )" strings). The money log lives at
-- pseudo-tab MAX_GUILDBANK_TABS+1; data arrives via GUILDBANKLOG_UPDATE.
-- ---------------------------------------------------------
function gb.buildLog()
    if gb.logPanel then return gb.logPanel end
    local UI = ns.UI
    local p = CreateFrame("Frame", nil, gb.frame)
    gb.logPanel = p
    p:SetWidth(340)
    p:SetPoint("TOPLEFT", gb.frame, "TOPRIGHT", 6, 0)
    p:SetPoint("BOTTOMLEFT", gb.frame, "BOTTOMRIGHT", 6, 0)
    if UI and UI.StyleBackdrop then UI:StyleBackdrop(p, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border }) end
    if UI and UI.CreateShadow then UI:CreateShadow(p) end
    p:Hide()

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if UI and UI.Font then UI.Font(title, 13) end
    title:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -10)
    title:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    title:SetText(L["Money log"])

    local msgs = CreateFrame("ScrollingMessageFrame", nil, p)
    p.msgs = msgs
    msgs:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -34)
    msgs:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -PAD, 10)
    if UI and UI.FONT_PATH then msgs:SetFont(UI.FONT_PATH, 12, "")
    else msgs:SetFontObject("GameFontHighlightSmall") end
    msgs:SetJustifyH("LEFT")
    msgs:SetFading(false)
    msgs:SetMaxLines(128)
    -- Blizzard's money log combo: TOP insert mode + ASCENDING adds (i=1..num).
    -- AddMessage push-fronts, and TOP mode paints buffer index 1 (= the LAST
    -- added message) at the visual top — so adding oldest-first puts the
    -- newest entry on top, exactly like the original.
    if msgs.SetInsertMode and _G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP then
        msgs:SetInsertMode(_G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP)
    end
    msgs:EnableMouseWheel(true)
    -- under TOP insert mode the mixin's buffer-relative Up/Down are visually
    -- mirrored: offset+1 (ScrollUp) moves the window DOWN the rendered list
    msgs:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if IsShiftKeyDown() then self:ScrollToBottom() else self:ScrollDown() end
        else
            if IsShiftKeyDown() then self:ScrollToTop() else self:ScrollUp() end
        end
    end)
    return p
end

function gb.queryLog()
    if QueryGuildBankLog then
        QueryGuildBankLog((_G.MAX_GUILDBANK_TABS or 6) + 1)   -- the money log
    end
end

function gb.updateLog()
    local p = gb.logPanel
    if not (p and p:IsShown() and p.msgs) then return end
    p.msgs:Clear()
    local num = (GetNumGuildBankMoneyTransactions and GetNumGuildBankMoneyTransactions()) or 0
    if num == 0 then
        p.msgs:AddMessage(L["No transactions yet."], 0.55, 0.55, 0.6)
        return
    end
    -- Blizzard's own recipe: localized format globals + RecentTimeDate.
    -- ASCENDING: with TOP insert mode the last add lands at the visual top,
    -- so oldest-first adds put the newest transaction on top (see buildLog)
    for i = 1, num do
        local kind, name, amount, year, month, day, hour = GetGuildBankMoneyTransaction(i)
        name = name or _G.UNKNOWN or "?"
        name = (_G.NORMAL_FONT_COLOR_CODE or "|cffffd200") .. name .. (_G.FONT_COLOR_CODE_CLOSE or "|r")
        local money = (GetDenominationsFromCopper and GetDenominationsFromCopper(amount or 0))
            or tostring(amount or 0)
        local msg
        if kind == "deposit" and _G.GUILDBANK_DEPOSIT_MONEY_FORMAT then
            msg = string.format(GUILDBANK_DEPOSIT_MONEY_FORMAT, name, money)
        elseif kind == "withdraw" and _G.GUILDBANK_WITHDRAW_MONEY_FORMAT then
            msg = string.format(GUILDBANK_WITHDRAW_MONEY_FORMAT, name, money)
        elseif kind == "repair" and _G.GUILDBANK_REPAIR_MONEY_FORMAT then
            msg = string.format(GUILDBANK_REPAIR_MONEY_FORMAT, name, money)
        elseif kind == "withdrawForTab" and _G.GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT then
            msg = string.format(GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT, name, money)
        elseif kind == "buyTab" then
            if (amount or 0) > 0 and _G.GUILDBANK_BUYTAB_MONEY_FORMAT then
                msg = string.format(GUILDBANK_BUYTAB_MONEY_FORMAT, name, money)
            elseif _G.GUILDBANK_UNLOCKTAB_FORMAT then
                msg = string.format(GUILDBANK_UNLOCKTAB_FORMAT, name)
            end
        elseif kind == "depositSummary" and _G.GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT then
            msg = string.format(GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT, money)
        end
        if msg then
            if _G.GUILD_BANK_LOG_TIME and RecentTimeDate then
                msg = msg .. GUILD_BANK_LOG_TIME:format(RecentTimeDate(year, month, day, hour))
            end
            p.msgs:AddMessage(msg, 0.82, 0.82, 0.87)
        end
    end
end

function gb.toggleLog()
    local p = gb.buildLog()
    if not p then return end
    if p:IsShown() then
        p:Hide()
    else
        p:Show()
        gb.queryLog()
        gb.updateLog()   -- paint from cache now; the event repaints when fresh
    end
end

-- ---------------------------------------------------------
-- Frame construction (eager at PLAYER_ENTERING_WORLD, out of combat)
-- ---------------------------------------------------------
function gb.build()
    if gb.frame or InCombatLockdown() then return gb.frame end
    local UI = ns.UI
    local f = CreateFrame("Frame", "VuloClassicUIGuildBankFrame", UIParent)
    gb.frame = f
    f:SetFrameStrata("HIGH")
    f:SetSize(420, 300)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:Hide()
    if UI and UI.StyleBackdrop then UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border }) end
    if UI and UI.CreateShadow then UI:CreateShadow(f) end
    if _G.tinsert and _G.UISpecialFrames then tinsert(UISpecialFrames, "VuloClassicUIGuildBankFrame") end

    -- manual close (X / Escape) must end the server interaction; the
    -- close-event path clears gb.open FIRST so this doesn't double-fire
    f:HookScript("OnHide", function()
        if gb.open and CloseGuildBankFrame then CloseGuildBankFrame() end
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
    f.title:SetText(L["Guild Bank"])

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -7)
    local cx = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cx:SetPoint("CENTER"); cx:SetText("x"); cx:SetTextColor(0.7, 0.7, 0.75)
    close:SetScript("OnEnter", function() cx:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b) end)
    close:SetScript("OnLeave", function() cx:SetTextColor(0.7, 0.7, 0.75) end)
    close:SetScript("OnClick", function() f:Hide() end)

    -- search box (same shape as the bank window's)
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
        gb.searchText = (self:GetText() or ""):lower()
        gb.refresh()
    end)
    sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    sb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)

    -- sort button (left of the search box): engine sort of the current tab.
    -- Left-click sorts, right-click flips the shared sort direction.
    local sortBtn = CreateFrame("Button", nil, f)
    sortBtn:SetSize(18, 18)
    sortBtn:SetPoint("RIGHT", sb, "LEFT", -8, 0)
    sortBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local si = sortBtn:CreateTexture(nil, "ARTWORK")
    si:SetAllPoints(); si:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    si:SetVertexColor(0.7, 0.7, 0.75)
    sortBtn:SetScript("OnEnter", function()
        si:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        if GameTooltip then
            GameTooltip:SetOwner(sortBtn, "ANCHOR_TOP")
            GameTooltip:SetText(L["Sort tab"])
            GameTooltip:AddLine(L["Sorts the current tab (mode from the bag options). Needs withdraw rights on the tab."], 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end
    end)
    sortBtn:SetScript("OnLeave", function() si:SetVertexColor(0.7, 0.7, 0.75); if GameTooltip then GameTooltip:Hide() end end)
    sortBtn:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            mod.db.sortReverse = not mod.db.sortReverse
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(mod.db.sortReverse and L["Sort order: reversed"] or L["Sort order: normal"], 0.6, 0.8, 1)
            end
        end
        gb.runSort()
    end)

    -- money-log toggle (left of the sort button)
    local logBtn = CreateFrame("Button", nil, f)
    logBtn:SetSize(18, 18)
    logBtn:SetPoint("RIGHT", sortBtn, "LEFT", -8, 0)
    local li = logBtn:CreateTexture(nil, "ARTWORK")
    li:SetAllPoints(); li:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    li:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    li:SetVertexColor(0.7, 0.7, 0.75)
    logBtn:SetScript("OnEnter", function()
        li:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        if GameTooltip then
            GameTooltip:SetOwner(logBtn, "ANCHOR_TOP")
            GameTooltip:SetText(L["Money log"])
            GameTooltip:AddLine(L["Shows who deposited or withdrew guild money."], 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    logBtn:SetScript("OnLeave", function() li:SetVertexColor(0.7, 0.7, 0.75); if GameTooltip then GameTooltip:Hide() end end)
    logBtn:SetScript("OnClick", function() gb.toggleLog() end)

    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -gb.TOP)
    f.content:SetSize(100, 100)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("CENTER", f.content, "CENTER", 0, 0)
    f.hint:Hide()

    -- footer, two rows with FIXED anchors (a money-width-dependent anchor
    -- would make the buttons jump sideways on every balance change):
    --   row 1 (upper): guild money left, withdraw allowance right
    --   row 2 (lower): deposit / withdraw buttons left
    f.guildMoney = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.guildMoney:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 30)

    local function miniButton(text, onClick)
        local b = CreateFrame("Button", nil, f)
        local fsb = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if UI and UI.Font then UI.Font(fsb, 11) end
        fsb:SetPoint("CENTER")
        fsb:SetText(text)
        fsb:SetTextColor(0.85, 0.85, 0.9)
        b:SetSize(fsb:GetStringWidth() + 14, 18)
        local bg2 = b:CreateTexture(nil, "BACKGROUND")
        bg2:SetAllPoints(b); bg2:SetColorTexture(0.13, 0.13, 0.16, 1)
        b:SetScript("OnEnter", function()
            fsb:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        end)
        b:SetScript("OnLeave", function() fsb:SetTextColor(0.85, 0.85, 0.9) end)
        b:SetScript("OnClick", onClick)
        b._fs = fsb
        return b
    end
    f.depositBtn = miniButton(L["Deposit"], function()
        if not gb.open or InCombatLockdown() then return end
        StaticPopup_Show("VCUI_GBANK_DEPOSIT", L["Deposit gold (amount in gold):"])
    end)
    f.depositBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 7)
    f.withdrawBtn = miniButton(L["Withdraw"], function()
        if not gb.open or InCombatLockdown() then return end
        if gb.withdrawable() <= 0 then return end
        StaticPopup_Show("VCUI_GBANK_WITHDRAW", L["Withdraw gold (amount in gold):"])
    end)
    f.withdrawBtn:SetPoint("LEFT", f.depositBtn, "RIGHT", 6, 0)

    f.allowance = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.allowance:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 30)

    -- movable + scalable; own db sub-table so it never collides with bags/bank
    if ns.CreateMover then
        gb.mover = ns:CreateMover(f, {
            db = gb.db(), scalable = true, anchorable = true,
            label = "|cffffffffGUILD BANK|r", width = 180, height = 40,
        })
        if ns.ApplyMover then ns:ApplyMover(gb.mover) end
    end
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = ns:GetCenterOffsets(self)
        if x and y then
            local d = gb.db()
            d.x, d.y = x, y
            if ns.ApplyMover and gb.mover then ns:ApplyMover(gb.mover) end
        end
    end)

    -- pre-build the full 98-slot pool out of combat
    for i = 1, gb.SLOTS do
        if not gb.acquireButton(i) then break end
    end
    return f
end

-- ---------------------------------------------------------
-- Layout: the CURRENT tab's 98 slots as one grid.
-- ---------------------------------------------------------
function gb.layout()
    if not (gb.frame and gb.open) then return end
    local f = gb.frame
    -- the server can shift the current tab under us — resync every repaint
    if GetCurrentGuildBankTab then
        local cur = GetCurrentGuildBankTab()
        if cur and cur >= 1 then gb.currentTab = cur end
    end
    gb.updateTabs()

    local num = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
    local cols = gb.db().columns or 14
    if cols < 1 then cols = 1 end
    -- height cap: at low column counts 98 slots would grow past small screens;
    -- raise the EFFECTIVE column count (saved setting untouched)
    local maxRows = math.floor((UIParent:GetHeight() * 0.7 - gb.TOP - gb.BOTTOM) / (BTN + GAP))
    if maxRows < 1 then maxRows = 1 end
    if math.ceil(gb.SLOTS / cols) > maxRows then
        cols = math.ceil(gb.SLOTS / maxRows)
    end
    local shown = 0
    if num > 0 then
        local _, _, viewable = GetGuildBankTabInfo(gb.currentTab)
        if viewable then
            for slot = 1, gb.SLOTS do
                local btn = gb.acquireButton(slot)
                if not btn then break end
                btn.tabIndex = gb.currentTab
                btn:SetID(slot)
                local col = (slot - 1) % cols
                local row = math.floor((slot - 1) / cols)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", f.content, "TOPLEFT",
                    col * (BTN + GAP), -row * (BTN + GAP))
                btn:Show()
                gb.updateButton(btn)
                shown = slot
            end
        end
    end
    for i = shown + 1, #gb.buttons do gb.buttons[i]:Hide() end

    -- hint text: no tabs at all, or the displayed tab is not viewable
    if f.hint then
        if num == 0 then
            f.hint:SetText(L["Your guild has no bank tabs yet."]); f.hint:Show()
        elseif shown == 0 then
            f.hint:SetText(L["This tab cannot be viewed."]); f.hint:Show()
        else
            f.hint:Hide()
        end
    end

    local rows = math.max(1, math.ceil(math.max(shown, cols) / cols))
    local contentW = cols * (BTN + GAP) - GAP
    local contentH = rows * (BTN + GAP) - GAP
    f.content:SetSize(contentW, contentH)
    f:SetSize(PAD + contentW + PAD, gb.TOP + contentH + gb.BOTTOM)
    gb.updateMoney()
end

function gb.updateMoney()
    local f = gb.frame
    if not f then return end
    if f.guildMoney and GetCoinTextureString and GetGuildBankMoney then
        f.guildMoney:SetText(string.format(L["Guild: %s"],
            GetCoinTextureString(GetGuildBankMoney() or 0)))
    end
    if f.allowance then
        local w = (GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()) or 0
        if w < 0 then
            f.allowance:SetText(string.format(L["Withdrawable: %s"], L["unlimited"]))
        elseif GetCoinTextureString then
            f.allowance:SetText(string.format(L["Withdrawable: %s"],
                GetCoinTextureString(gb.withdrawable())))
        end
    end
    -- dim the withdraw button when nothing can be taken out (its click is a
    -- deliberate no-op then — the label must say so)
    if f.withdrawBtn and f.withdrawBtn._fs then
        if gb.withdrawable() > 0 then
            f.withdrawBtn._fs:SetTextColor(0.85, 0.85, 0.9)
        else
            f.withdrawBtn._fs:SetTextColor(0.4, 0.4, 0.45)
        end
    end
end

-- coalesce event bursts into ONE relayout next frame; also re-query source
-- tabs of cross-tab moves (the changed event only covers the current tab)
function gb.refresh()
    if not (gb.open and gb.frame and gb.frame:IsShown()) then return end
    if gb.refreshScheduled then return end
    gb.refreshScheduled = true
    local function run()
        gb.refreshScheduled = false
        if not (gb.open and gb.frame and gb.frame:IsShown()) then return end
        local cur = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
        local didDirty = false
        for t in pairs(gb.dirtyTabs) do
            gb.dirtyTabs[t] = nil
            if t ~= cur and QueryGuildBankTab then
                QueryGuildBankTab(t)
                didDirty = true
            end
        end
        -- current tab LAST: change events only stream for the last-queried
        -- (server-side current) tab — the displayed one must stay live
        if didDirty and cur and QueryGuildBankTab then QueryGuildBankTab(cur) end
        gb.layout()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

-- cross-tab move staleness: remember the source tab of every pickup/split so
-- the next refresh re-queries it (installed once, act only while live)
function gb.installHooks()
    if gb.hooksInstalled then return end
    gb.hooksInstalled = true
    if type(_G.PickupGuildBankItem) == "function" then
        hooksecurefunc("PickupGuildBankItem", function(tab)
            if gb.open and tab then gb.dirtyTabs[tab] = true end
        end)
    end
    if type(_G.SplitGuildBankItem) == "function" then
        hooksecurefunc("SplitGuildBankItem", function(tab)
            if gb.open and tab then gb.dirtyTabs[tab] = true end
        end)
    end
end

-- ---------------------------------------------------------
-- Physical sort of the CURRENT tab, driven by the shared sort engine's
-- comparator (ns.SortEngine.AddSortKeys/OrderOneListOffline are pure data —
-- only the moves differ: PickupGuildBankItem instead of the container API).
-- Same driver recipe as the engine: stack-combine first, then ordering
-- steps; wait for GUILDBANKBAGSLOTS_CHANGED (or 1s fallback) between steps;
-- pcall-contained; stuck detection (no progress = likely missing withdraw
-- rights on the tab -> abort quietly); cancel on close/tab switch.
-- ---------------------------------------------------------
function gb.cancelSort()
    gb.sortToken = (gb.sortToken or 0) + 1
    gb.sortInFlight = false
    gb.sortWaiting = false
    gb.sortStep = nil
end

function gb.sortScan(tab)
    local slots = {}
    for slot = 1, gb.SLOTS do
        local _, count, locked, _, quality = GetGuildBankItemInfo(tab, slot)
        local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
        local entry = { locked = locked and true or false }
        local itemID = link and tonumber(link:match("item:(%d+)"))
        if link and itemID then
            entry.itemLink  = link
            entry.itemID    = itemID
            entry.itemCount = count or 1
            -- the guild API reports -1/nil on uncached items; fall back to the
            -- link (the GetItemInfo call also requests the cache load)
            local q = (quality and quality >= 0) and quality or nil
            if not q and GetItemInfo then q = select(3, GetItemInfo(link)) end
            entry.quality    = q
            entry.hasNoValue = false   -- the guild API has no noValue flag
        end
        slots[slot] = entry
    end
    return slots
end

-- merge the smallest partial stack of an item onto its largest partial: the
-- number of partial stacks strictly decreases every merge -> terminates.
-- Distinct item groups touch disjoint slot pairs, so one batch per step is
-- safe. Returns the number of merges fired.
function gb.sortCombineStep(tab)
    local slots = gb.sortScan(tab)
    local partials, occurrences, incomplete = {}, {}, false
    for _, e in ipairs(slots) do
        if e.itemID and not e.locked then
            occurrences[e.itemID] = (occurrences[e.itemID] or 0) + 1
        end
    end
    for slot, e in ipairs(slots) do
        if e.itemID and not e.locked then
            local maxStack = GetItemInfo and select(8, GetItemInfo(e.itemID))
            if maxStack and maxStack > 1 and e.itemCount < maxStack then
                local t = partials[e.itemID]
                if not t then t = {}; partials[e.itemID] = t end
                t[#t + 1] = { slot = slot, count = e.itemCount }
            elseif not maxStack and (occurrences[e.itemID] or 0) >= 2 then
                -- uncached stack size on a potentially mergeable item: the
                -- GetItemInfo call above doubles as the cache request — retry
                incomplete = true
            end
        end
    end
    local fired = 0
    for _, list in pairs(partials) do
        if #list >= 2 then
            table.sort(list, function(a, b) return a.count < b.count end)
            local smallest, largest = list[1], list[#list]
            PickupGuildBankItem(tab, smallest.slot)
            PickupGuildBankItem(tab, largest.slot)   -- merges; remainder on cursor
            ClearCursor()                            -- remainder returns home
            fired = fired + 1
        end
    end
    return fired, incomplete
end

-- one ordering step: fresh scan, engine order, junk (grey) to the far end,
-- fire every non-overlapping move. Returns status ("complete"|"move"|
-- "unlock"|"itemdata") plus the number of moves fired.
function gb.sortOrderStep(tab, method, reverse)
    local SE = ns.SortEngine
    if not (SE and SE.AddSortKeys and SE.OrderOneListOffline) then return "complete", 0 end
    local slots = gb.sortScan(tab)
    local oneList, anyLocked = {}, false
    for slot, e in ipairs(slots) do
        e.from = slot
        if e.locked then anyLocked = true end
        if e.itemID then
            e.index = slot   -- stable tie-break across steps
            oneList[#oneList + 1] = e
        end
    end
    if #oneList == 0 then return "complete", 0 end
    SE.AddSortKeys(oneList)
    local sorted, incomplete = SE.OrderOneListOffline(oneList, method, reverse)
    if incomplete then return "itemdata", 0 end

    -- junk split (grey to the end), same visual rule as the bag engine
    local main, junk = {}, {}
    for _, it in ipairs(sorted) do
        if (it.quality or 1) == 0 then junk[#junk + 1] = it else main[#main + 1] = it end
    end
    local target = {}
    for i, it in ipairs(main) do target[i] = it end
    for i, it in ipairs(junk) do target[gb.SLOTS - #junk + i] = it end

    local used, moves = {}, 0
    for dest = 1, gb.SLOTS do
        local want = target[dest]
        if want and want.from ~= dest and not used[dest] and not used[want.from] then
            local src, cur = slots[want.from], slots[dest]
            if not (src and src.locked) and not (cur and cur.locked) then
                used[dest], used[want.from] = true, true
                PickupGuildBankItem(tab, want.from)      -- lift
                PickupGuildBankItem(tab, dest)           -- place / swap
                if cur and cur.itemID then
                    PickupGuildBankItem(tab, want.from)  -- complete the swap
                end
                ClearCursor()
                moves = moves + 1
            end
        end
    end
    if moves > 0 then return "move", moves end
    if anyLocked then return "unlock", 0 end
    return "complete", 0
end

function gb.runSort()
    if gb.sortInFlight or not gb.open then return end
    local tab = (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) or gb.currentTab or 1
    local _, _, viewable = GetGuildBankTabInfo(tab)
    if not viewable then return end
    local method  = mod.db and mod.db.sortMode or "type"
    if method == "blizzard" then method = "type" end   -- no native guild sort
    local reverse = mod.db and mod.db.sortReverse and true or false

    gb.sortInFlight = true
    gb.sortToken = (gb.sortToken or 0) + 1
    local token = gb.sortToken
    local attempts, lastQueued, sameCount = 0, -1, 0
    local combining = true

    local function finish()
        if token == gb.sortToken then gb.cancelSort() end
        gb.refresh()
    end
    local function step()
        if token ~= gb.sortToken then return end
        if not gb.open then return finish() end
        -- moves act on the server-side current tab; a user tab switch mid-
        -- sort must cancel, never silently re-target
        if GetCurrentGuildBankTab and GetCurrentGuildBankTab() ~= tab then return finish() end
        attempts = attempts + 1
        if attempts > 150 then return finish() end
        local ok, status, queued = pcall(function()
            -- never fire moves with something already on the cursor (the first
            -- pickup would deposit the user's held item into the guild bank)
            if CursorHasItem and CursorHasItem() then return "unlock", 0 end
            if combining then
                local fired, inc = gb.sortCombineStep(tab)
                if fired > 0 then return "move", fired end
                if inc then return "itemdata", 0 end   -- stay in the combine phase
                combining = false
            end
            return gb.sortOrderStep(tab, method, reverse)
        end)
        if not ok or status == "complete" then return finish() end
        if status == "move" then
            if queued == lastQueued then sameCount = sameCount + 1 else sameCount = 0; lastQueued = queued end
            if sameCount >= 4 then return finish() end   -- no progress (no rights?)
            gb.sortWaiting = true
            -- generation counter: a stale fallback timer from an earlier wait
            -- cycle must never consume a LATER cycle's wait (the event kick
            -- would then be suppressed and the driver degrade to timer pacing)
            gb.sortWaitGen = (gb.sortWaitGen or 0) + 1
            local gen = gb.sortWaitGen
            if C_Timer and C_Timer.After then
                C_Timer.After(1, function()   -- fallback if the event never comes
                    if token == gb.sortToken and gb.sortWaiting and gen == gb.sortWaitGen then
                        gb.sortWaiting = false
                        step()
                    end
                end)
            end
        else   -- "unlock" / "itemdata": data settles quickly
            if C_Timer and C_Timer.After then C_Timer.After(0.05, step) else step() end
        end
    end
    gb.sortStep = step
    step()
end

-- ---------------------------------------------------------
-- Open / close (idempotent — PIM and legacy events may both fire)
-- ---------------------------------------------------------
function gb.onOpen()
    if gb.open then return end
    if not gb.enabled() then return end   -- leave the default guild bank alone
    -- classic quirk: the interaction opens even without a guild
    if IsInGuild and not IsInGuild() then
        if UIErrorsFrame and _G.ERR_GUILD_PLAYER_NOT_IN_GUILD then
            UIErrorsFrame:AddMessage(_G.ERR_GUILD_PLAYER_NOT_IN_GUILD, 1, 0.2, 0.2)
        end
        if CloseGuildBankFrame then CloseGuildBankFrame() end
        return
    end
    gb.open = true
    gb.suppressDefault()
    gb.installHooks()
    if not gb.frame then gb.build() end
    if not gb.frame then
        -- combat-blocked first build: nothing can show and the default UI is
        -- neutered — END the session, or it stays open headless on the server
        gb.open = false
        if CloseGuildBankFrame then CloseGuildBankFrame() end
        return
    end
    gb.currentTab = (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) or 1
    if gb.currentTab < 1 then gb.currentTab = 1 end
    -- full scan: query every viewable tab, CURRENT LAST so the final answer
    -- burst leaves the server on the displayed tab
    local num = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
    for i = 1, num do
        local _, _, viewable = GetGuildBankTabInfo(i)
        if viewable and i ~= gb.currentTab and QueryGuildBankTab then
            QueryGuildBankTab(i)
        end
    end
    if QueryGuildBankTab then QueryGuildBankTab(gb.currentTab) end
    gb.tabSig = nil
    gb.frame:Show()
    gb.updateTabs()
    -- log panel left open last session: refresh it for THIS session's data
    if gb.logPanel and gb.logPanel:IsShown() then
        gb.queryLog()
        gb.updateLog()
    end
    gb.refresh()   -- one-frame deferral: item data lags the open event
end

function gb.onClose()
    if not gb.open then
        -- still hide a stray window (e.g. option toggled off mid-session)
        if gb.frame and gb.frame:IsShown() then gb.frame:Hide() end
        return
    end
    gb.open = false   -- FIRST: OnHide must not CloseGuildBankFrame again
    gb.cancelSort()
    if gb.frame and gb.frame.search then gb.frame.search:SetText("") end
    gb.searchText = ""
    for t in pairs(gb.dirtyTabs) do gb.dirtyTabs[t] = nil end
    if gb.frame and gb.frame:IsShown() then gb.frame:Hide() end
end

-- ---------------------------------------------------------
-- Events
-- ---------------------------------------------------------
function gb.onEvent(event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        if gb.enabled() then
            gb.disarmUIParent()
            if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_GuildBankUI") then
                gb.suppressDefault()
            end
            gb.build()
        end
        return
    end
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_GuildBankUI" and gb.enabled() then
            gb.suppressDefault()
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if gb.pendingSuppress then
            gb.pendingSuppress = false
            if gb.enabled() then gb.suppressDefault() else gb.restoreDefault() end
        end
        -- a combat PEW left the window unbuilt: catch up now
        if gb.enabled() and not gb.frame then gb.build() end
        gb.tabSig = nil   -- belt: never trust a strip painted around combat
        return
    end

    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if Enum and Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.GuildBanker then
            gb.onOpen()
        end
        return
    end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if Enum and Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.GuildBanker then
            gb.onClose()
        end
        return
    end
    if event == "GUILDBANKFRAME_OPENED" then gb.onOpen(); return end
    if event == "GUILDBANKFRAME_CLOSED" then gb.onClose(); return end

    -- content events — only while our window is live and shown
    if not (gb.open and gb.frame and gb.frame:IsShown()) then return end
    if event == "GUILDBANKBAGSLOTS_CHANGED" then
        -- a waiting sort step continues on the first event of the burst
        if gb.sortWaiting and gb.sortStep then
            gb.sortWaiting = false
            local s = gb.sortStep
            if C_Timer and C_Timer.After then C_Timer.After(0, s) else s() end
        end
        gb.refresh()
    elseif event == "GUILDBANK_UPDATE_TABS" then
        gb.tabSig = nil
        gb.updateTabs()
        gb.refresh()
    elseif event == "GUILDBANK_UPDATE_MONEY" or event == "GUILDBANK_UPDATE_WITHDRAWMONEY" then
        gb.updateMoney()
    elseif event == "GUILDBANK_ITEM_LOCK_CHANGED" then
        gb.refresh()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- quality borders / ilvls on uncached items pop in once the data lands
        gb.refresh()
    elseif event == "GUILDBANKLOG_UPDATE" then
        gb.updateLog()
    end
end

-- ---------------------------------------------------------
-- Published hooks for Bags.lua (options splice + lifecycle)
-- ---------------------------------------------------------
function ns.GuildBankOptions()
    local items = {}
    if not gb.capable() then return items end   -- Era: no guild bank, no options
    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Guild Bank"] })
    table.insert(items, {
        type = "toggle", label = L["Replace the guild bank window"],
        tooltip = L["Show the guild bank in a matching window with tabs and search. Off = the default guild bank."],
        get = function() return gb.db().enabled ~= false end,
        set = function(_, v)
            gb.db().enabled = v and true or false
            if v then
                if mod.active then
                    gb.disarmUIParent()
                    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_GuildBankUI") then
                        gb.suppressDefault()
                    end
                end
            else
                if gb.frame and gb.frame:IsShown() then gb.frame:Hide() end -- ends a live session
                gb.restoreDefault()
            end
        end,
    })
    table.insert(items, {
        type = "slider", label = L["Guild bank window scale"], min = 50, max = 150, step = 5,
        get = function() return (gb.db().scale or 1) * 100 end,
        set = function(_, v)
            gb.db().scale = v / 100
            if gb.mover and ns.MoverSetScale then ns:MoverSetScale(gb.mover, v / 100)
            elseif gb.frame then gb.frame:SetScale(v / 100) end
        end,
    })
    table.insert(items, {
        type = "slider", label = L["Guild bank grid columns"], min = 7, max = 24, step = 1,
        get = function() return gb.db().columns or 14 end,
        set = function(_, v)
            gb.db().columns = v
            if gb.open and gb.frame and gb.frame:IsShown() then gb.refresh() end
        end,
    })
    table.insert(items, {
        type = "button", label = L["Reset guild bank position"], width = 200,
        onClick = function()
            if gb.mover and ns.MoverSetCenter then
                ns:MoverSetCenter(gb.mover, 280, 0)
            else
                local d = gb.db(); d.x, d.y = 280, 0
            end
        end,
    })
    return items
end

function ns.GuildBankRefresh()
    gb.refresh()
end

-- Published: the bag window's search mirrors into an OPEN guild bank window
-- (same non-recursive SetText -> OnTextChanged route as the bank).
function ns.GuildBankMirrorSearch(text)
    if not (gb.open and gb.frame and gb.frame:IsShown() and gb.frame.search) then return end
    if gb.frame.search:GetText() ~= text then
        gb.frame.search:SetText(text)
    end
end

function ns.GuildBankOnEnable()
    if gb.enabled() then
        gb.disarmUIParent()
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_GuildBankUI") then
            gb.suppressDefault()
        end
        gb.build()
    end
end

function ns.GuildBankOnDisable()
    gb.cancelSort()
    if gb.frame and gb.frame:IsShown() then gb.frame:Hide() end   -- ends a live session
    gb.restoreDefault()
end

-- ---------------------------------------------------------
-- Event wiring — LAST in the file (every gb.* above is defined). The central
-- dispatcher pcall-isolates handlers; unknown events on a flavor are guarded
-- there too. Everything gates at runtime on mod.active + db + capability.
-- ---------------------------------------------------------
for _, ev in ipairs({
    "PLAYER_ENTERING_WORLD",
    "ADDON_LOADED",                        -- Blizzard_GuildBankUI is LoadOnDemand
    "PLAYER_REGEN_ENABLED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",   -- legacy fallbacks
    "GUILDBANKBAGSLOTS_CHANGED",           -- THE item repaint driver (current tab)
    "GUILDBANK_UPDATE_TABS",
    "GUILDBANK_UPDATE_MONEY", "GUILDBANK_UPDATE_WITHDRAWMONEY",
    "GUILDBANK_ITEM_LOCK_CHANGED",
    "GET_ITEM_INFO_RECEIVED",              -- late item data -> borders/ilvl pop in
    "GUILDBANKLOG_UPDATE",                 -- money-log panel repaint
}) do
    ns:RegisterEvent(ev, gb.onEvent)
end
