-- VuloClassicUI / Modules / GuildBank
-- UIParent's own GUILDBANKFRAME_OPENED handler calls CloseGuildBankFrame() whenever
-- GuildBankFrame isn't visible, so UIParent must be unregistered (restored on disable).
-- GuildBankFrame lives in the LoD addon Blizzard_GuildBankUI (needs an ADDON_LOADED watcher).
-- All guild bank APIs are unprotected: the item buttons are plain insecure buttons.
-- Item data arrives via GUILDBANKBAGSLOTS_CHANGED only after QueryGuildBankTab(tab).
local _, ns = ...
local L   = ns.L
local mod = ns.modules.bags   -- loads after Bags.lua; mod.db is only valid inside handlers
local BTN, GAP, PAD = 37, 4, 12

-- no guild bank API on this client -> whole file inert
if not (_G.GetGuildBankItemInfo and _G.QueryGuildBankTab) then return end

local gb = {
    frame        = nil,
    buttons      = {},
    tabButtons   = {},
    open         = false,
    currentTab   = 1,
    refreshScheduled = false,
    pendingSuppress  = false,
    suppressed   = false,
    uipDisarmed  = false,
    origScripts  = nil,
    hiddenHost   = nil,
    hooksInstalled = false,
    bindTypeCache = {},
    dirtyTabs    = {},
    tabSig       = nil,
    mover        = nil,
    searchText   = "",
    SLOTS        = 98,
    TOP          = 76,
    BOTTOM       = 54,
}

gb.hiddenHost = CreateFrame("Frame")
gb.hiddenHost:Hide()

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

function gb.capable()
    if C_GuildBank and C_GuildBank.IsGuildBankEnabled then
        return C_GuildBank.IsGuildBankEnabled() and true or false
    end
    return true
end

function gb.enabled()
    return mod.active and gb.db().enabled ~= false and gb.capable()
end

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
    -- combat-legal event surgery - never defer, or UIParent's OPENED fallback kills the session
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
    -- OnHide FIRST: reparenting hides the frame and the live OnHide would CloseGuildBankFrame()
    local wasShown = f:IsShown()
    f:SetScript("OnHide", nil)
    f:SetScript("OnShow", nil)
    f:SetScript("OnEvent", nil)
    f:SetParent(gb.hiddenHost)
    if wasShown then
        f:Hide()
        if CloseGuildBankFrame then CloseGuildBankFrame() end
    end
end

function gb.restoreDefault()
    gb.rearmUIParent()
    if InCombatLockdown() then gb.pendingSuppress = true; return end
    local f = _G.GuildBankFrame
    if f and gb.suppressed and gb.origScripts then
        if f:IsShown() then f:Hide() end
        f:SetParent(gb.origScripts.parent or UIParent)
        f:SetScript("OnEvent", gb.origScripts.OnEvent)
        f:SetScript("OnShow",  gb.origScripts.OnShow)
        f:SetScript("OnHide",  gb.origScripts.OnHide)
    end
    gb.suppressed = false
end

-- Own money dialogs (Blizzard's read the neutered frame). Amounts are typed in gold.
function gb.popupAmount(self)
    local box = ns.PopupEditBox(self)
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

-- GetGuildBankWithdrawMoney() returns -1 for unlimited: sign-check before clamping.
function gb.withdrawable()
    local guildMoney = (GetGuildBankMoney and GetGuildBankMoney()) or 0
    local w = (GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()) or 0
    if w < 0 then return guildMoney end
    return math.min(w, guildMoney)
end

function gb.itemMatches(tab, slot, q)
    if not q or q == "" then return true end
    local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
    if not link then return false end
    if ns.ItemSearchMatch then
        local _, _, _, _, quality = GetGuildBankItemInfo(tab, slot)
        if quality and quality < 0 then quality = nil end
        return ns.ItemSearchMatch(link, quality, q)
    end
    return link:lower():find(q, 1, true) and true or false
end

-- Item buttons: plain insecure, base ItemButtonTemplate (the guild template is in the LoD addon).
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
    btn.SplitStack = function(b, split)
        if gb.open and SplitGuildBankItem and split and split > 0 then
            SplitGuildBankItem(b.tabIndex, b:GetID(), split)
        end
    end
    ns.BagsStripButtonGlow(btn)
    ns.BagsSkinItemButton(btn)
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
    SetItemButtonDesaturated(btn, locked)

    if (not quality or quality < 0) and link and GetItemInfo then
        quality = select(3, GetItemInfo(link))
    end
    ns.BagsPaintQuality(btn, quality, link)
    ns.BagsApplyCountFont(btn, mod.db)
    -- guild bank items are never soulbound, so isBound is simply nil here
    local itemID = link and tonumber(link:match("item:(%d+)"))
    ns.BagsPaintBindTag(btn, link, itemID, nil, mod.db, gb.bindTypeCache)

    if (gb.searchText or "") == "" then
        btn:SetAlpha(1)
    else
        btn:SetAlpha(gb.itemMatches(tab, slot, gb.searchText) and 1 or 0.25)
    end
end

-- Tab strip is rebuilt only when the tab meta changed (rapid clicks would hit released buttons).
function gb.selectTab(i)
    if not gb.open then return end
    local _, _, viewable = GetGuildBankTabInfo(i)
    if not viewable then return end
    if gb.cancelSort then gb.cancelSort() end
    if SetCurrentGuildBankTab then SetCurrentGuildBankTab(i) end
    if QueryGuildBankTab then QueryGuildBankTab(i) end
    gb.currentTab = i
    gb.tabSig = nil
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

    gb.tabSig = sig
end

-- Money log lives at pseudo-tab MAX_GUILDBANK_TABS+1; data arrives via GUILDBANKLOG_UPDATE.
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
    -- TOP insert mode + oldest-first adds puts the newest entry at the visual top.
    if msgs.SetInsertMode and _G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP then
        msgs:SetInsertMode(_G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP)
    end
    msgs:EnableMouseWheel(true)
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
        QueryGuildBankLog((_G.MAX_GUILDBANK_TABS or 6) + 1)
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
        gb.updateLog()
    end
end

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

    -- manual close must end the server interaction; the close path clears gb.open first
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

    local close = UI:CreateCloseX(f, function() f:Hide() end)

    local sb = UI:CreateSearchBox(f, {
        onText = function(self)
            gb.searchText = (self:GetText() or ""):lower()
            gb.refresh()
        end,
    })
    f.search = sb
    sb:SetPoint("RIGHT", close, "LEFT", -8, 0)

    local sortBtn = CreateFrame("Button", nil, f)
    sortBtn:SetSize(18, 18)
    sortBtn:SetPoint("RIGHT", sb, "LEFT", -8, 0)
    sortBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local si = sortBtn:CreateTexture(nil, "ARTWORK")
    si:SetAllPoints(); si:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\broom.tga")
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

    local logBtn = CreateFrame("Button", nil, f)
    logBtn:SetSize(18, 18)
    logBtn:SetPoint("RIGHT", sortBtn, "LEFT", -8, 0)
    local li = logBtn:CreateTexture(nil, "ARTWORK")
    li:SetAllPoints(); li:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\goldtracker.tga")
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

    for i = 1, gb.SLOTS do
        if not gb.acquireButton(i) then break end
    end
    return f
end

function gb.layout()
    if not (gb.frame and gb.open) then return end
    local f = gb.frame
    if GetCurrentGuildBankTab then
        local cur = GetCurrentGuildBankTab()
        if cur and cur >= 1 then gb.currentTab = cur end
    end
    gb.updateTabs()

    local num = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
    local cols = gb.db().columns or 14
    if cols < 1 then cols = 1 end
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
    if f.withdrawBtn and f.withdrawBtn._fs then
        if gb.withdrawable() > 0 then
            f.withdrawBtn._fs:SetTextColor(0.85, 0.85, 0.9)
        else
            f.withdrawBtn._fs:SetTextColor(0.4, 0.4, 0.45)
        end
    end
end

-- Coalesce bursts into ONE relayout; also re-query source tabs of cross-tab moves.
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
        -- current tab LAST: change events only stream for the last-queried tab
        if didDirty and cur and QueryGuildBankTab then QueryGuildBankTab(cur) end
        gb.layout()
    end
    ns.NextFrame(run)
end

-- Remember the source tab of every pickup/split so the next refresh re-queries it.
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

-- Physical sort of the CURRENT tab through the shared engine's comparator; moves use
-- PickupGuildBankItem and wait for GUILDBANKBAGSLOTS_CHANGED (1s fallback) per step.
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
            local q = (quality and quality >= 0) and quality or nil
            if not q and GetItemInfo then q = select(3, GetItemInfo(link)) end
            entry.quality    = q
            entry.hasNoValue = false
        end
        slots[slot] = entry
    end
    return slots
end

-- Merge the smallest partial stack onto the largest: the partial count strictly decreases.
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
            PickupGuildBankItem(tab, largest.slot)
            ClearCursor()
            fired = fired + 1
        end
    end
    return fired, incomplete
end

function gb.sortOrderStep(tab, method, reverse)
    local SE = ns.SortEngine
    if not (SE and SE.AddSortKeys and SE.OrderOneListOffline) then return "complete", 0 end
    local slots = gb.sortScan(tab)
    local oneList, anyLocked = {}, false
    for slot, e in ipairs(slots) do
        e.from = slot
        if e.locked then anyLocked = true end
        if e.itemID then
            e.index = slot
            oneList[#oneList + 1] = e
        end
    end
    if #oneList == 0 then return "complete", 0 end
    SE.AddSortKeys(oneList)
    local sorted, incomplete = SE.OrderOneListOffline(oneList, method, reverse)
    if incomplete then return "itemdata", 0 end

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
                PickupGuildBankItem(tab, want.from)
                PickupGuildBankItem(tab, dest)
                if cur and cur.itemID then
                    PickupGuildBankItem(tab, want.from)
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
    if method == "blizzard" then method = "type" end
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
        -- a user tab switch mid-sort must cancel, never silently re-target
        if GetCurrentGuildBankTab and GetCurrentGuildBankTab() ~= tab then return finish() end
        attempts = attempts + 1
        if attempts > 150 then return finish() end
        local ok, status, queued = pcall(function()
            -- never fire moves with something already on the cursor
            if CursorHasItem and CursorHasItem() then return "unlock", 0 end
            if combining then
                local fired, inc = gb.sortCombineStep(tab)
                if fired > 0 then return "move", fired end
                if inc then return "itemdata", 0 end
                combining = false
            end
            return gb.sortOrderStep(tab, method, reverse)
        end)
        if not ok or status == "complete" then return finish() end
        if status == "move" then
            if queued == lastQueued then sameCount = sameCount + 1 else sameCount = 0; lastQueued = queued end
            if sameCount >= 4 then return finish() end
            gb.sortWaiting = true
            -- generation counter: a stale fallback timer must not consume a later wait cycle
            gb.sortWaitGen = (gb.sortWaitGen or 0) + 1
            local gen = gb.sortWaitGen
            if C_Timer and C_Timer.After then
                C_Timer.After(1, function()
                    if token == gb.sortToken and gb.sortWaiting and gen == gb.sortWaitGen then
                        gb.sortWaiting = false
                        step()
                    end
                end)
            end
        else
            if C_Timer and C_Timer.After then C_Timer.After(0.05, step) else step() end
        end
    end
    gb.sortStep = step
    step()
end

-- Open / close is idempotent: PIM and legacy events may both fire.
function gb.onOpen()
    if gb.open then return end
    if not gb.enabled() then return end
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
        -- combat-blocked first build with the default UI neutered: end the session
        gb.open = false
        if CloseGuildBankFrame then CloseGuildBankFrame() end
        return
    end
    gb.currentTab = (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) or 1
    if gb.currentTab < 1 then gb.currentTab = 1 end
    -- query every viewable tab, CURRENT LAST so the final burst is the displayed tab
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
    if gb.logPanel and gb.logPanel:IsShown() then
        gb.queryLog()
        gb.updateLog()
    end
    gb.refresh()
end

function gb.onClose()
    if not gb.open then
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
        if gb.enabled() and not gb.frame then gb.build() end
        gb.tabSig = nil
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

    if not (gb.open and gb.frame and gb.frame:IsShown()) then return end
    if event == "GUILDBANKBAGSLOTS_CHANGED" then
        if gb.sortWaiting and gb.sortStep then
            gb.sortWaiting = false
            local s = gb.sortStep
            ns.NextFrame(s)
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
        gb.refresh()
    elseif event == "GUILDBANKLOG_UPDATE" then
        gb.updateLog()
    end
end

function ns.GuildBankOptions()
    local items = {}
    if not gb.capable() then return items end
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
                if gb.frame and gb.frame:IsShown() then gb.frame:Hide() end
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
    if gb.frame and gb.frame:IsShown() then gb.frame:Hide() end
    gb.restoreDefault()
end

-- Wired LAST: every gb.* handler above must already be defined.
for _, ev in ipairs({
    "PLAYER_ENTERING_WORLD",
    "ADDON_LOADED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
    "GUILDBANKBAGSLOTS_CHANGED",
    "GUILDBANK_UPDATE_TABS",
    "GUILDBANK_UPDATE_MONEY", "GUILDBANK_UPDATE_WITHDRAWMONEY",
    "GUILDBANK_ITEM_LOCK_CHANGED",
    "GET_ITEM_INFO_RECEIVED",
    "GUILDBANKLOG_UPDATE",
}) do
    ns:RegisterEvent(ev, gb.onEvent)
end
