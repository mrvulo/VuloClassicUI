-- VuloClassicUI / Modules / CharacterPanelSockets
--
-- A strip of every socket on the equipped gear, hung under the character
-- window, plus the socketing that goes with it: click a socket, pick a gem out
-- of your bags, done. The per-slot socket icons in CharacterPanel.lua stay
-- exactly as they are -- they say WHAT is socketed, this says WHERE a gem is
-- still missing and lets you fix it without hunting through the bags.
--
-- WHY ITS OWN FILE
--   CharacterPanel.lua is already the longest module in the addon and is about
--   the paper doll's own anatomy. This is a self-contained surface that only
--   borrows the module's db, so it stays separable.
--
-- CROSS-CLIENT
--   Nothing here asks which flavour is running. Every socketing call is probed
--   once and falls back from C_ItemSocketInfo to the bare global; the socket
--   data itself comes from the item tooltip and the item link, which every
--   client answers the same way. On Era there are no gems at all -- the scan
--   finds nothing and the strip never shows, without a flavour test saying so.
--
-- TAINT
--   Every frame here is ours. Blizzard frames are only read (GetBottom, width)
--   and used as parent/anchor. The socketing sequence runs from a real click
--   and touches only unprotected API.
--
-- The binding-gem confirmation the sequence can raise is a client bug on 2.5.5
-- and is re-added by its own option in General.lua; nothing to do here.

(function(...)
local _, ns = ...
local L = ns.L

--------------------------------------------------------------------------------
--  Client capabilities
--------------------------------------------------------------------------------
-- Probe-and-fall-back, never a flavour test: these calls live under
-- C_ItemSocketInfo on the newer clients and as bare globals on the older ones.
-- Whatever is missing simply yields nil, and the strip degrades to read-only.
local CIS = _G.C_ItemSocketInfo
local SocketInventoryItemFn = (CIS and CIS.SocketInventoryItem) or _G.SocketInventoryItem
local GetNumSocketsFn       = (CIS and CIS.GetNumSockets)       or _G.GetNumSockets
local ClickSocketButtonFn   = (CIS and CIS.ClickSocketButton)   or _G.ClickSocketButton
local AcceptSocketsFn       = (CIS and CIS.AcceptSockets)       or _G.AcceptSockets
local CloseSocketInfoFn     = (CIS and CIS.CloseSocketInfo)     or _G.CloseSocketInfo
-- Names the item the open session belongs to. Not required to socket, but it is
-- the proof that a session is the one our click asked for; where it is missing
-- we simply never touch a session we cannot identify.
local GetSocketItemInfoFn   = (CIS and CIS.GetSocketItemInfo)   or _G.GetSocketItemInfo

local CAN_SOCKET = (SocketInventoryItemFn and GetNumSocketsFn
    and ClickSocketButtonFn and AcceptSocketsFn) and true or false

--------------------------------------------------------------------------------
--  Constants
--------------------------------------------------------------------------------
local ICON     = 18   -- socket icon edge
local GAP      = 3
local BAR_PAD  = 5
local GEM_SIZE = 30   -- gem button in the picker
local GEM_PAD  = 4
local GEM_COLS = 6

-- Item class of a gem. Enum is absent on the older clients; 3 is the class id
-- on every one of them.
local GEM_CLASS = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Gem) or 3

-- The item tooltip carries one texture per socket. Four is the most any item
-- has, and the same number the per-slot display reads -- anything beyond it
-- would not be a socket, and would become a phantom icon that opens a session
-- for a socket index the item does not have. Ten get CLEARED, though: leftovers
-- from an earlier scan of a different item are what this guards against.
local MAX_SOCKETS      = 4
local MAX_TIP_TEXTURES = 10

-- Built from the globals, so a client that lacks a slot simply contributes
-- nothing. Sorted by inventory id: roughly head to feet, with the cloak sitting
-- late (it is id 15) rather than next to the shoulders. Order of the strip only.
local SLOTS = {}
do
    local names = {
        "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HAND", "WAIST",
        "LEGS", "FEET", "FINGER1", "FINGER2", "TRINKET1", "TRINKET2",
        "MAINHAND", "OFFHAND", "RANGED",
    }
    for _, n in ipairs(names) do
        local id = _G["INVSLOT_" .. n]
        if id then SLOTS[#SLOTS + 1] = id end
    end
    table.sort(SLOTS)
end

--------------------------------------------------------------------------------
--  Options access
--------------------------------------------------------------------------------
local function cpMod() return ns.modules and ns.modules.characterpanel end

local function cpOpt(key, default)
    local m = cpMod()
    local d = m and m.db
    if d and d[key] ~= nil then return d[key] end
    return default
end

local function barWanted()
    local m = cpMod()
    if not (m and m.active) then return false end
    return cpOpt("showSocketBar", true) and true or false
end

local function confirmWanted()
    return cpOpt("confirmSocketOverwrite", true) and true or false
end

--------------------------------------------------------------------------------
--  Reading the sockets
--------------------------------------------------------------------------------
local scanTip

local function ensureScanTip()
    if scanTip then return scanTip end
    scanTip = CreateFrame("GameTooltip", "VCUISocketScanTooltip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTip
end

-- One texture per socket, in socket order: the gem's icon where a gem sits, the
-- empty-socket art where none does. ClearLines does NOT reliably hide tooltip
-- textures, so a socketless item scanned after a gemmed one would inherit its
-- icons -- hide them by hand first (same trap the per-slot display hit).
local function socketTexturesFor(slot)
    local tip = ensureScanTip()
    for i = 1, MAX_TIP_TEXTURES do
        local t = _G["VCUISocketScanTooltipTexture" .. i]
        if t then t:Hide() end
    end
    tip:ClearLines()
    tip:SetInventoryItem("player", slot)

    local out = {}
    for i = 1, MAX_SOCKETS do
        local t = _G["VCUISocketScanTooltipTexture" .. i]
        if t and t:IsShown() then
            out[#out + 1] = t:GetTexture()
        end
    end
    return out
end

-- The gem ids are fields 3..6 of the item string, so field 3+index for socket
-- `index`. The extra parens around select() are required: it returns every
-- value from that position onward, and the next one would become tonumber's
-- base argument.
local function gemIDAt(link, index)
    if not link then return nil end
    local itemString = link:match("item[%-?%d:]+")
    if not itemString then return nil end
    local id = tonumber((select(3 + index, strsplit(":", itemString))))
    if id and id > 0 then return id end
    return nil
end

local sockets = {}   -- ordered: { slot, index, gemID, texture, itemLink }

local function rebuildSocketList()
    for i = #sockets, 1, -1 do sockets[i] = nil end

    for _, slot in ipairs(SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local textures = socketTexturesFor(slot)
            for i = 1, #textures do
                sockets[#sockets + 1] = {
                    slot     = slot,
                    index    = i,
                    gemID    = gemIDAt(link, i),
                    texture  = textures[i],
                    itemLink = link,
                }
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Bag gems
--------------------------------------------------------------------------------
local function bagGems()
    local out, seen = {}, {}
    if not (GetContainerNumSlots and GetItemInfoInstant) then return out end

    for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
        local n = GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            -- GetContainerItemID reads the slot directly and answers even for an
            -- item this client has never cached (a gem straight out of the
            -- mailbox), which GetContainerItemInfo does not.
            local id = GetContainerItemID and GetContainerItemID(bag, slot)
            if id and not seen[id] then
                local _, _, _, _, icon, classID = GetItemInfoInstant(id)
                if classID == GEM_CLASS then
                    seen[id] = true
                    out[#out + 1] = { itemID = id, bag = bag, slot = slot, icon = icon }
                end
            end
        end
    end
    return out
end

local function findBagSlot(itemID)
    if not GetContainerNumSlots then return nil end
    for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
        local n = GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            if GetContainerItemID and GetContainerItemID(bag, slot) == itemID then
                return bag, slot
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
--  The socketing sequence (event-driven, no timers)
--------------------------------------------------------------------------------
local pending       -- in-flight action
local pendingToken  -- rises with every action, so a late timer knows it is stale
local ourSession    -- a socketing session WE opened may still be live
local picker       -- forward: the gem picker frame
local refreshBar, queueRefresh       -- forward
local watchSession, unwatchSession   -- forward: the session event frame

local function closeOurSession()
    if CloseSocketInfoFn then CloseSocketInfoFn() end
    -- Belt for a client where the close call is a silent no-op: hide the window,
    -- whose own OnHide ends the session. Never left invisible-but-alive -- a live
    -- session blocks every further socket click with no way to end it.
    local f = _G.ItemSocketingFrame
    if f and f:IsShown() and not InCombatLockdown() and _G.HideUIPanel then
        _G.HideUIPanel(f)
    end
end

-- Everything that ends an action ends it HERE, so no path can leave the pending
-- action and the session listener behind. A left-behind action is not a dead
-- feature, it is a live trap: the next socketing session the PLAYER opens by
-- hand would be answered by our handler, which would put our old gem into their
-- item and accept it for them.
local function abandonPending()
    pending = nil
    ourSession = false
    unwatchSession()
end

local function doSocket(rec, gemItemID)
    if not CAN_SOCKET then return end
    if InCombatLockdown() then
        ns:Print(L["Cannot socket gems in combat."])
        return
    end
    if CursorHasItem and CursorHasItem() then return end   -- never hijack a held item

    local f = _G.ItemSocketingFrame
    if f and f:IsShown() then
        if ourSession then
            -- Left over from our own last action (the accept never closed it):
            -- end it now, so socketing is not silently dead until the player
            -- closes the window by hand. Deliberately NOT reopening in the same
            -- click -- the old session's close event would wipe the new pending
            -- action mid-flight. The next click goes through cleanly.
            closeOurSession()
        else
            ns:Print(L["Close the socketing window first."])
        end
        return
    end

    -- The item name is read BEFORE the call, so the update handler can prove the
    -- session it is looking at is the one this click asked for.
    local wantName
    if GetItemInfo then
        wantName = GetItemInfo(GetInventoryItemLink("player", rec.slot) or "")
    end

    local token = (pendingToken or 0) + 1
    pendingToken = token
    pending = {
        slot      = rec.slot,
        index     = rec.index,
        gemItemID = gemItemID,
        itemName  = wantName,
        token     = token,
        acted     = false,
    }
    ourSession = true
    -- The session events get their OWN listener, live from here until the
    -- session ends. They must not travel with the strip: opening the socketing
    -- window is a UI panel opening, and the panel manager may well push the
    -- character window out for it -- which would take the strip's listener down
    -- with it and leave the sequence waiting for an update it never hears.
    watchSession()
    SocketInventoryItemFn(rec.slot)
    if picker then picker:Hide() end

    -- The call above opens nothing at all when the slot has been emptied under
    -- the open picker, or the item turns out not to be socketable. No event ever
    -- arrives then, so nothing would clear the action -- this does. The token
    -- makes it a no-op once the action it was armed for is over.
    if C_Timer and C_Timer.After then
        C_Timer.After(5, function()
            if pending and pending.token == token and not pending.acted then
                abandonPending()
            end
        end)
    end
end

-- Runs inside SOCKET_INFO_UPDATE, once the session is actually ready.
local function onSocketInfoUpdate()
    if not pending then return end

    if pending.acted then
        -- Updates keep arriving after we act (the picked-up gem landing in the
        -- socket UI is one). If the first accept raced ahead of the gem
        -- registering, no accept event ever comes and the window sits waiting
        -- for a manual click -- re-issue it, bounded, so a genuinely
        -- unacceptable state cannot loop.
        --
        -- Never while a confirmation is standing: accepting again is exactly
        -- what that dialog's own Yes button does, so a re-accept here would
        -- answer a "this will bind the item to you" question on the player's
        -- behalf.
        if pending.awaitConfirm then return end
        local n = pending.reaccepts or 0
        if n < 3 and AcceptSocketsFn then
            pending.reaccepts = n + 1
            AcceptSocketsFn()
        end
        return
    end

    -- Is this session even ours? A click that opened nothing leaves the action
    -- standing (the timer above clears it, but not instantly), and without this
    -- test the next session the player opens BY HAND would be socketed and
    -- accepted for them. Comparing the item is the proof; where the client will
    -- not name the item in the session, the session is left alone entirely.
    if not GetInventoryItemLink("player", pending.slot) then
        abandonPending()   -- the slot was emptied under the open picker
        return
    end
    if GetSocketItemInfoFn then
        local sessionName = GetSocketItemInfoFn()
        if not sessionName or (pending.itemName and sessionName ~= pending.itemName) then
            return
        end
    elseif not ourSession then
        return
    end

    local numSockets = GetNumSocketsFn and GetNumSocketsFn()
    if not numSockets or pending.index > numSockets then
        return   -- session not ready yet; the next update tries again. No timer.
    end
    pending.acted = true

    -- Located now, not at click time: the bags can reshuffle between the click
    -- and the session opening.
    local bag, slot = findBagSlot(pending.gemItemID)
    if not bag then
        abandonPending()
        closeOurSession()
        return
    end

    if PickupContainerItem then PickupContainerItem(bag, slot) end
    -- A locked bag slot (a swap still in flight) makes the pickup a silent
    -- no-op, and an empty-handed socket click REMOVES the proposed gem instead
    -- of placing one. Nothing is lost either way, but there is no point
    -- accepting an empty proposal.
    if CursorHasItem and not CursorHasItem() then
        pending.acted = false
        return
    end
    ClickSocketButtonFn(pending.index)
    if ClearCursor then ClearCursor() end
    AcceptSocketsFn()
    -- No force-close: the client owns its bind/refund confirmations from here.
end

--------------------------------------------------------------------------------
--  Overwriting a socket that already holds a gem
--------------------------------------------------------------------------------
-- Socketing over a gem DESTROYS the one that comes out, and the strip puts that
-- one click away -- so a gemmed socket asks first.
--
-- What is remembered is the slot, the socket index and the gem that was in it,
-- never the record the click came from: the dialog outlives that click, and
-- every bag or equipment event throws the whole record list away and builds a
-- new one. At accept time the socket is read again from the live item link, and
-- the action is dropped when it no longer holds what the question was about --
-- otherwise a gear swap under a standing dialog would answer for a socket the
-- player never looked at.
local overwrite   -- { slot, index, gemItemID, hadGemID }

-- The link where the client has one: it carries the quality colour, and the
-- question is much easier to read in the two gem colours than in bare names.
local function gemLabel(id)
    if not id then return UNKNOWN or "?" end
    local name, link = GetItemInfo(id)
    return link or name or (UNKNOWN or "?")
end

local function acceptOverwrite()
    local o = overwrite
    overwrite = nil
    if not o then return end

    local link = GetInventoryItemLink("player", o.slot)
    if not link or gemIDAt(link, o.index) ~= o.hadGemID then
        ns:Print(L["That socket has changed — nothing was socketed."])
        return
    end
    -- A fresh minimal record on purpose: doSocket only reads slot and index, and
    -- the one from the click may long have been replaced by a rebuild.
    doSocket({ slot = o.slot, index = o.index }, o.gemItemID)
end

ns.OnLocaleReady(function()
    StaticPopupDialogs["VCUI_SOCKET_OVERWRITE"] = {
        text           = L["Replace %s with %s? The gem that comes out is destroyed."],
        button1        = YES or "Yes",
        button2        = NO or "No",
        timeout        = 0,
        whileDead      = true,
        hideOnEscape   = true,
        preferredIndex = 3,
        OnAccept = acceptOverwrite,
        -- Every other way out of the dialog drops the action. Left standing it
        -- would be armed for the NEXT confirmation, whose accept would then
        -- socket a gem the player did not pick.
        OnCancel = function() overwrite = nil end,
        OnHide   = function() overwrite = nil end,
    }
end)

-- The one door from the picker into the socketing sequence: an empty socket goes
-- straight through, a gemmed one only through the question.
local function requestSocket(rec, gemItemID)
    if not (rec.gemID and confirmWanted()) then
        doSocket(rec, gemItemID)
        return
    end

    overwrite = {
        slot      = rec.slot,
        index     = rec.index,
        gemItemID = gemItemID,
        hadGemID  = rec.gemID,
    }
    -- No dialog to ask with (the registration runs on locale ready, and a client
    -- without StaticPopup would never get one): the click still does what it
    -- says rather than dying silently.
    if not (StaticPopupDialogs and StaticPopupDialogs["VCUI_SOCKET_OVERWRITE"]
        and StaticPopup_Show) then
        acceptOverwrite()
        return
    end
    if picker then picker:Hide() end
    StaticPopup_Show("VCUI_SOCKET_OVERWRITE", gemLabel(rec.gemID), gemLabel(gemItemID))
end

--------------------------------------------------------------------------------
--  The gem picker
--------------------------------------------------------------------------------
local gemButtons = {}

local function accent()
    return (ns.COLORS and ns.COLORS.accent) or { r = 0.608, g = 0.424, b = 1 }
end

local function createPicker()
    if picker then return picker end

    local UI = ns.UI
    picker = CreateFrame("Frame", "VCUI_SocketGemPicker", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")
    picker:SetFrameStrata("DIALOG")
    picker:SetSize(240, 80)
    picker:EnableMouse(true)
    picker:SetClampedToScreen(true)
    picker:Hide()

    if UI and UI.StyleBackdrop then
        UI:StyleBackdrop(picker, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border })
    end
    if UI and UI.CreateShadow then UI:CreateShadow(picker) end

    local ac = accent()
    local strip = picker:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", picker, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    if UI and UI.SetGradient then
        UI.SetGradient(strip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)
    end
    tinsert(UISpecialFrames, "VCUI_SocketGemPicker")

    local closeBtn = CreateFrame("Button", nil, picker)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -4, -4)
    local cx = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cx:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    if UI and UI.Font then UI.Font(cx, 16) end
    cx:SetText("×")
    cx:SetTextColor(0.7, 0.7, 0.75)
    closeBtn:SetScript("OnEnter", function() cx:SetTextColor(ac.r, ac.g, ac.b) end)
    closeBtn:SetScript("OnLeave", function() cx:SetTextColor(0.7, 0.7, 0.75) end)
    closeBtn:SetScript("OnClick", function() picker:Hide() end)

    local title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", picker, "TOPLEFT", 10, -8)
    title:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    if UI and UI.Font then UI.Font(title, 12) end
    title:SetTextColor(0.95, 0.95, 1)
    picker.title = title

    -- Closes itself once the cursor has been inside and then left, with a grace
    -- margin that bridges the gap back to the socket icon. Same behaviour as the
    -- item flyout on the paper doll, so both read the same way.
    picker:SetScript("OnShow", function(self) self.armed = false; self.outTime = 0 end)
    picker:SetScript("OnUpdate", function(self, elapsed)
        local overSelf = self:IsMouseOver(8, -8, -8, 8)
        local overIcon = self.anchorBtn and self.anchorBtn.IsMouseOver and self.anchorBtn:IsMouseOver()
        if overSelf then self.armed = true end
        if overSelf or overIcon then
            self.outTime = 0
        elseif self.armed then
            self.outTime = (self.outTime or 0) + elapsed
            if self.outTime > 0.5 then self:Hide() end
        end
    end)

    return picker
end

local function acquireGemButton(i)
    local btn = gemButtons[i]
    if btn then return btn end

    local UI = ns.UI
    btn = CreateFrame("Button", nil, picker)
    btn:SetSize(GEM_SIZE, GEM_SIZE)

    btn.ring = btn:CreateTexture(nil, "BACKGROUND")
    btn.ring:SetAllPoints(btn)
    btn.ring:SetColorTexture(0.25, 0.25, 0.3, 1)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    btn.count = btn:CreateFontString(nil, "OVERLAY")
    btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    if UI and UI.FONT_PATH then
        btn.count:SetFont(UI.FONT_PATH, 10, "OUTLINE")
    else
        btn.count:SetFontObject("NumberFontNormalSmall")
    end
    btn.count:SetTextColor(1, 1, 1)

    local hov = btn:CreateTexture(nil, "HIGHLIGHT")
    hov:SetAllPoints(btn)
    hov:SetColorTexture(1, 1, 1, 0.12)

    btn:SetScript("OnEnter", function(self)
        if not (self.bag and self.slot) then return end
        if not ns.UI:OpenTooltip(self, "ANCHOR_RIGHT") then return end
        GameTooltip:SetBagItem(self.bag, self.slot)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
    btn:SetScript("OnClick", function(self)
        if not (picker and picker.rec and self.itemID) then return end
        requestSocket(picker.rec, self.itemID)
    end)

    gemButtons[i] = btn
    return btn
end

local function populatePicker(rec, anchorBtn)
    createPicker()

    picker.rec = rec
    picker.anchorBtn = anchorBtn
    picker.title:SetText(L["Choose a gem"])

    local gems = bagGems()
    for _, b in ipairs(gemButtons) do b:Hide() end

    local top = 28
    if #gems == 0 then
        if not picker.emptyText then
            picker.emptyText = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            picker.emptyText:SetPoint("CENTER", picker, "CENTER", 0, -10)
            picker.emptyText:SetTextColor(0.7, 0.7, 0.7)
            if ns.UI and ns.UI.Font then ns.UI.Font(picker.emptyText, 11) end
        end
        picker.emptyText:SetText(L["No gems in your bags."])
        picker.emptyText:Show()
        picker:SetSize(200, top + 30)
    else
        if picker.emptyText then picker.emptyText:Hide() end

        local cols = math.min(GEM_COLS, #gems)
        local rows = math.ceil(#gems / cols)
        picker:SetSize(
            math.max(200, cols * (GEM_SIZE + GEM_PAD) - GEM_PAD + 20),
            top + rows * (GEM_SIZE + GEM_PAD) - GEM_PAD + 10)

        for i, g in ipairs(gems) do
            local btn = acquireGemButton(i)
            btn.itemID, btn.bag, btn.slot = g.itemID, g.bag, g.slot

            local icon = g.icon
            local _, _, quality = GetItemInfo(g.itemID)
            if quality == nil and C_Item and C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, g.itemID)
            end
            btn.icon:SetTexture(icon)
            -- Only the first three returns: the fourth is the colour as a hex
            -- STRING, and passing it on would land as the alpha argument.
            if quality and quality >= 2 and GetItemQualityColor then
                local qr, qg, qb = GetItemQualityColor(quality)
                btn.ring:SetColorTexture(qr, qg, qb, 1)
            else
                btn.ring:SetColorTexture(0.25, 0.25, 0.3, 1)
            end

            local count = (GetItemCount and GetItemCount(g.itemID)) or 1
            btn.count:SetText(count > 1 and tostring(count) or "")

            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", picker, "TOPLEFT",
                10 + col * (GEM_SIZE + GEM_PAD),
                -(top + row * (GEM_SIZE + GEM_PAD)))
            btn:Show()
        end
    end

    picker:ClearAllPoints()
    -- Below the icon, flipped above when it would run off the screen bottom.
    local bottom = anchorBtn:GetBottom() or 0
    if bottom - picker:GetHeight() - 6 < 0 then
        picker:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", 0, 4)
    else
        picker:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -4)
    end
    picker:Show()
end

--------------------------------------------------------------------------------
--  The strip
--------------------------------------------------------------------------------
local bar
local icons = {}

local function acquireIcon(i)
    local btn = icons[i]
    if btn then return btn end

    btn = CreateFrame("Button", nil, bar)
    btn:SetSize(ICON, ICON)

    btn.ring = btn:CreateTexture(nil, "BACKGROUND")
    btn.ring:SetAllPoints(btn)
    btn.ring:SetColorTexture(0.25, 0.25, 0.3, 1)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)

    local hov = btn:CreateTexture(nil, "HIGHLIGHT")
    hov:SetAllPoints(btn)
    hov:SetColorTexture(1, 1, 1, 0.15)

    btn:SetScript("OnEnter", function(self)
        local rec = self.rec
        if not rec then return end
        if not ns.UI:OpenTooltip(self, "ANCHOR_RIGHT") then return end
        if rec.gemID then
            GameTooltip:SetHyperlink("item:" .. rec.gemID)
            -- The strip has always let a gemmed socket be clicked; until now
            -- nothing said so, and nothing said what it costs.
            if CAN_SOCKET then
                GameTooltip:AddLine(L["Click to replace the gem — the old one is destroyed."],
                    0.7, 0.7, 0.75, true)
            end
        else
            GameTooltip:AddLine(L["Empty socket"], 1, 1, 1)
            if CAN_SOCKET then
                GameTooltip:AddLine(L["Click to pick a gem from your bags."], 0.7, 0.7, 0.75, true)
            end
        end
        if rec.itemLink then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(rec.itemLink, 0.6, 0.6, 0.65)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
    btn:SetScript("OnClick", function(self)
        if not (CAN_SOCKET and self.rec) then return end
        if InCombatLockdown() then
            ns:Print(L["Cannot socket gems in combat."])
            return
        end
        -- Clicking the icon whose picker is already up closes it again.
        if picker and picker:IsShown() and picker.anchorBtn == self then
            picker:Hide()
            return
        end
        populatePicker(self.rec, self)
    end)

    icons[i] = btn
    return btn
end

-- Where the strip hangs, and how wide it may grow.
--
-- The loadouts column is the target when it is up: it is the rightmost thing on
-- the character window, it is already exactly as wide as a strip wants to be,
-- and the space under it is free. Anchoring to CharacterFrame instead was wrong
-- in the modern style, where BOTH the stats panel and that column sit OUTSIDE
-- the frame -- the strip then landed under the paper doll, halfway across the
-- window, on top of the player frame.
-- How far the content has to move in from the frame's edge. Classic+ wears
-- Blizzard's dialog border, which is 32 pixels of artwork against a one-pixel
-- edge -- without the surcharge the first icon of every row sits ON the frame.
-- The number is not ours: it comes from the loadouts column, so the two can
-- never disagree about how much room their shared frame takes.
local function chromeInset()
    return (ns.LoadoutsWindowInset and ns.LoadoutsWindowInset()) or 0
end

local sidebarHooked = false

local function anchorTarget()
    local sb = _G.VCUI_LoadoutsSidebar
    -- That column is built lazily and comes and goes with its own module, and
    -- neither move fires anything the strip already listens to. Hooked on first
    -- sight, so the strip follows it instead of waiting for the next equipment
    -- change to notice the ground moved.
    if sb and not sidebarHooked then
        sidebarHooked = true
        sb:HookScript("OnShow", function() queueRefresh() end)
        sb:HookScript("OnHide", function() queueRefresh() end)
    end
    if sb and sb:IsShown() then return sb, true end
    return _G.CharacterFrame, false
end

-- Measured, not guessed: the tabs hang below the frame by a different amount on
-- every client generation and every reskin, and a fixed offset would drop the
-- strip on top of them somewhere. The loadouts column has no tabs under it, so
-- that measurement only applies to the fallback.
local function anchorBar()
    local target, onSidebar = anchorTarget()
    if not (bar and target) then return end

    local drop = 0
    if not onSidebar then
        local cfBottom = target.GetBottom and target:GetBottom()
        if cfBottom then
            for i = 1, 8 do
                local tab = _G["CharacterFrameTab" .. i]
                if tab and tab:IsShown() and tab.GetBottom then
                    local tb = tab:GetBottom()
                    if tb then
                        local d = cfBottom - tb
                        if d > drop then drop = d end
                    end
                end
            end
        end
    end

    bar:ClearAllPoints()

    -- Below is where it belongs, but the character window can be moved, and a
    -- strip under a window that already sits near the screen edge would render
    -- off-screen and be unreachable. It goes above then.
    local bottom = target.GetBottom and target:GetBottom()
    local needed = (drop + 4) + (bar:GetHeight() or 0)
    local above  = bottom and (bottom - needed) < 0

    -- BOTH corners on the loadouts column, so the strip is exactly as wide as it
    -- by construction. A measured width would be a snapshot, and that column
    -- re-sets its own width on every style switch (the classic look wears a
    -- 32-pixel border and grows by it) -- the strip would then keep yesterday's
    -- number. The column itself anchors its two corners for the same reason.
    if onSidebar then
        -- Classic+ lets the two frames TOUCH: the dialog border is drawn inward
        -- from the edge, so a gap would put two runs of artwork with a stripe of
        -- world between them. The flat look wants the gap, or its two one-pixel
        -- edges read as one thick line.
        local gap = (chromeInset() > 0) and 0 or 4
        if above then
            bar:SetPoint("BOTTOMLEFT",  target, "TOPLEFT",  0, gap)
            bar:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", 0, gap)
        else
            bar:SetPoint("TOPLEFT",  target, "BOTTOMLEFT",  0, -gap)
            bar:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 0, -gap)
        end
        return
    end

    if above then
        bar:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", 0, 4)
    else
        bar:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 0, -(drop + 4))
    end
end

-- Flat fallback, kept in the SAME mechanism as the styled paint. Two mechanisms
-- on one frame would mean hiding one set of pieces to show the other on every
-- style switch, instead of one repaint.
local FLAT_BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- Repainted on every layout, not once at creation: the style switch has to land
-- without a /reload, and both looks are one SetBackdrop call on the same frame.
-- Deliberately no drop shadow -- the strip is meant to read as the last section
-- of the column above it, and a shadow makes it a second, floating window.
local function paintBar()
    if not (bar and bar.SetBackdrop) then return end
    if ns.StyleLoadoutsWindow then
        ns.StyleLoadoutsWindow(bar)
        return
    end
    local bg = ns.COLORS.bg
    local bd = ns.COLORS.accentDim or ns.COLORS.border
    bar:SetBackdrop(FLAT_BACKDROP)
    bar:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
    bar:SetBackdropBorderColor(bd.r, bd.g, bd.b, bd.a or 1)
end

local function ensureBar()
    if bar then return bar end
    local cf = _G.CharacterFrame
    if not cf then return nil end

    -- Parented to the paper doll where there is one, so the strip comes and goes
    -- with the tab instead of hanging under the reputation page.
    local parent = _G.PaperDollFrame or cf
    bar = CreateFrame("Frame", "VCUI_SocketBar", parent,
        BackdropTemplateMixin and "BackdropTemplate")
    bar:SetFrameStrata(cf:GetFrameStrata())
    bar:SetFrameLevel((cf:GetFrameLevel() or 1) + 20)
    bar:SetSize(ICON + BAR_PAD * 2, ICON + BAR_PAD * 2)
    bar:Hide()

    return bar
end

local function paintIcon(btn, rec)
    btn.rec = rec
    btn.icon:SetTexture(rec.texture)

    if rec.gemID then
        -- A gem icon is normal icon art: crop its baked-in dark edge.
        btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        btn.ring:SetColorTexture(0.25, 0.25, 0.3, 1)
        btn:SetAlpha(1)
    else
        -- The empty-socket art brings its own frame; showing it cropped cuts it.
        btn.icon:SetTexCoord(0, 1, 0, 1)
        if cpOpt("markEmptySockets", true) then
            btn.ring:SetColorTexture(0.85, 0.15, 0.15, 1)   -- same red as the slot marker
        else
            btn.ring:SetColorTexture(0.25, 0.25, 0.3, 1)
        end
        btn:SetAlpha(0.95)
    end
end

local function layoutBar()
    if not bar then return end

    for i = #sockets + 1, #icons do icons[i]:Hide() end

    local n = #sockets
    if n == 0 then
        if picker then picker:Hide() end
        bar:Hide()
        return
    end

    -- Classic-era gear carries far more sockets than one row of the window it
    -- hangs under, so the strip wraps downward instead of running off the edge.
    -- The width it may use is the width of whatever it is anchored to.
    local target, onSidebar = anchorTarget()
    local avail = (target and target.GetWidth and target:GetWidth()) or 320
    -- The strip GROWS by the frame it wears rather than paying for it out of its
    -- content: the column it hangs under does exactly the same, so the usable
    -- width inside stays the same in both looks and the row count does not jump
    -- when the style changes.
    local pad = BAR_PAD + chromeInset()
    local perRow = math.floor((avail - pad * 2 + GAP) / (ICON + GAP))
    if perRow < 1 then perRow = 1 end
    if perRow > n then perRow = n end
    local rows = math.ceil(n / perRow)

    -- Under the loadouts column the two anchor points on that column's bottom
    -- corners are what give the strip its width; the width set here is the same
    -- number, so it does not matter which of the two the client prefers, and a
    -- width left over from the fallback layout cannot survive the switch.
    local height = rows * (ICON + GAP) - GAP + pad * 2
    bar:SetSize(onSidebar and avail
        or (perRow * (ICON + GAP) - GAP + pad * 2), height)
    paintBar()
    if target and target.GetFrameStrata then
        bar:SetFrameStrata(target:GetFrameStrata())
    end

    for i, rec in ipairs(sockets) do
        local btn = acquireIcon(i)
        paintIcon(btn, rec)
        local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", bar, "TOPLEFT",
            pad + col * (ICON + GAP),
            -(pad + row * (ICON + GAP)))
        btn:Show()
    end

    -- The rebuild threw away the record the open picker was holding, and the
    -- icon it hangs off is pooled -- both would keep pointing at a socket that
    -- has moved. Re-find the same slot and index; if it is gone, so is the
    -- picker. Without this the gem goes into whatever inherited the position.
    if picker and picker:IsShown() and picker.rec then
        local want = picker.rec
        local found
        for i, rec in ipairs(sockets) do
            if rec.slot == want.slot and rec.index == want.index then
                found = i
                break
            end
        end
        if found then
            picker.rec = sockets[found]
            picker.anchorBtn = icons[found]
        else
            picker:Hide()
        end
    end

    anchorBar()
    bar:Show()
end

--------------------------------------------------------------------------------
--  Refresh + lifecycle
--------------------------------------------------------------------------------
local events
local eventsOn = false

-- Registered only while the strip is up: everything here is about keeping what
-- is drawn in step with the gear and the bags.
local SHOWN_EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED",
    "UNIT_INVENTORY_CHANGED",
    "BAG_UPDATE_DELAYED",
    "ITEM_CHANGED",          -- absent on the older clients; the register is pcall'd
    "PLAYER_REGEN_DISABLED",
}

local function registerShownEvents()
    if eventsOn or not events then return end
    eventsOn = true
    for _, ev in ipairs(SHOWN_EVENTS) do
        pcall(events.RegisterEvent, events, ev)
    end
end

local function unregisterShownEvents()
    if not (eventsOn and events) then return end
    eventsOn = false
    for _, ev in ipairs(SHOWN_EVENTS) do
        pcall(events.UnregisterEvent, events, ev)
    end
end

refreshBar = function()
    if not barWanted() then
        if picker then picker:Hide() end
        unregisterShownEvents()
        if bar then bar:Hide() end
        return
    end
    if not ensureBar() then return end
    if not (bar:GetParent() and bar:GetParent():IsVisible()) then
        unregisterShownEvents()
        bar:Hide()
        return
    end

    registerShownEvents()
    rebuildSocketList()
    layoutBar()
end

-- Several of these arrive together for one player action (equipping an item
-- fires two, a durability tick fires one per hit), and the character panel calls
-- in on the same events from its own listener. Rebuilding costs a tooltip scan
-- of all seventeen slots, so the calls are folded into one pass at the end of
-- the frame instead of one pass each.
local refreshQueued = false

queueRefresh = function()
    if refreshQueued then return end
    if not (C_Timer and C_Timer.After) then
        refreshBar()
        return
    end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        refreshBar()
    end)
end

local function onEvent(_, event, arg1)
    if event == "PLAYER_REGEN_DISABLED" then
        if picker then picker:Hide() end
        return
    elseif event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then
        return
    elseif event == "BAG_UPDATE_DELAYED" then
        -- A bag change cannot move a socket on an equipped item; only the gem
        -- list and its counts. Repainting the whole strip for it was seventeen
        -- tooltip scans for nothing.
        if picker and picker:IsShown() and picker.rec and picker.anchorBtn then
            populatePicker(picker.rec, picker.anchorBtn)
        end
        return
    end

    -- Anything else here means the gear itself moved. The open picker points at
    -- a socket of the item that was there a moment ago, so it goes: keeping it
    -- would put the gem into whatever now occupies that slot and index.
    if picker then picker:Hide() end
    queueRefresh()
end

--------------------------------------------------------------------------------
--  Session events
--  Their own frame, live only between the click that opens a session and its
--  close, so nothing about them depends on the character window still standing.
--------------------------------------------------------------------------------
local sessionFrame

local SESSION_EVENTS = {
    "SOCKET_INFO_UPDATE",
    "SOCKET_INFO_ACCEPT",
    "SOCKET_INFO_CLOSE",
    "SOCKET_INFO_FAILURE",
    -- The two confirmations are watched for one reason only: to stop the
    -- re-accept from answering them. See onSocketInfoUpdate.
    "SOCKET_INFO_BIND_CONFIRM",
    "SOCKET_INFO_REFUNDABLE_CONFIRM",
}

local function onSessionEvent(_, event)
    if event == "SOCKET_INFO_UPDATE" then
        onSocketInfoUpdate()
        return
    end

    if event == "SOCKET_INFO_BIND_CONFIRM" or event == "SOCKET_INFO_REFUNDABLE_CONFIRM" then
        if pending then pending.awaitConfirm = true end
        return
    end

    if event == "SOCKET_INFO_FAILURE" then
        -- The action did not happen and no close is coming for it.
        abandonPending()
        return
    end

    local wasOurs = pending ~= nil
    pending = nil
    if event == "SOCKET_INFO_CLOSE" then
        ourSession = false
        unwatchSession()
    end

    -- Socketing rewrites the equipped item's link IN PLACE, so the equipment
    -- event stays silent and an immediate re-read still sees the old gems on the
    -- clients without ITEM_CHANGED. One deferred pass covers those.
    queueRefresh()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, refreshBar)
    end

    if event == "SOCKET_INFO_ACCEPT" and wasOurs then
        closeOurSession()
    end
end

watchSession = function()
    if not sessionFrame then
        sessionFrame = CreateFrame("Frame")
        sessionFrame:SetScript("OnEvent", onSessionEvent)
    end
    for _, ev in ipairs(SESSION_EVENTS) do
        pcall(sessionFrame.RegisterEvent, sessionFrame, ev)
    end
end

unwatchSession = function()
    if not sessionFrame then return end
    for _, ev in ipairs(SESSION_EVENTS) do
        pcall(sessionFrame.UnregisterEvent, sessionFrame, ev)
    end
end

-- The character panel calls this on every one of its own updates, which is why
-- it goes through the same fold as our events rather than straight to the
-- rebuild. Safe before login: the event listener does not exist yet and the
-- register step simply stands down.
ns.RefreshSocketBar = queueRefresh

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()

    events = CreateFrame("Frame")
    events:SetScript("OnEvent", onEvent)

    if _G.PaperDollFrame then
        _G.PaperDollFrame:HookScript("OnShow", refreshBar)
        _G.PaperDollFrame:HookScript("OnHide", function()
            if picker then picker:Hide() end
            unregisterShownEvents()
            if bar then bar:Hide() end
        end)
    end
    if _G.CharacterFrame then
        _G.CharacterFrame:HookScript("OnShow", refreshBar)
        _G.CharacterFrame:HookScript("OnHide", function()
            if picker then picker:Hide() end
            unregisterShownEvents()
        end)
    end
end)

end)(...);
