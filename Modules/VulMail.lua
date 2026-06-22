-- =========================================================
-- VuloClassicUI / Modules / VulMail
-- "Open All" mailbox button: collects every attachment + coin from your inbox
-- with one click. Mail actions are throttled and async, so it runs a small
-- state machine — take one thing, wait for the mailbox to actually change,
-- then move on — skipping CoD and GM mail and respecting a free-bag-space
-- reserve. Improvements over the classic version: a looted summary, a watchdog
-- so a stuck take can never hang the queue, and a clean options block.
-- Registered as a QoL sub-module.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("vulmail", {
    name        = "Mail",
    group       = "QoL",
    description = "Adds an 'Open All' button to your mailbox that collects every attachment and coin in one click.",
    defaults = {
        enabled     = true,
        attachments = true,   -- take item attachments
        gold        = true,   -- take money
        keepFree    = 0,      -- keep this many free bag slots
        openSpeed   = 0.15,   -- seconds between mail actions (server throttle)
        verbose     = true,   -- print a looted summary
        recipients  = true,   -- recipient dropdown on the Send tab
    },
})

local format = string.format
local ATTACH_MAX = ATTACHMENTS_MAX_RECEIVE or 16
local NUM_BAGS = NUM_BAG_SLOTS or 4

-- ---------------------------------------------------------
-- Localization
-- ---------------------------------------------------------
local L = {
    OPEN_ALL    = "Open All",
    IN_PROGRESS = "In Progress",
    SUMMARY     = "Mail emptied: looted %s%s.",
    AND_ITEMS   = " and %d item(s)",
    BAGS_FULL   = "Bags are full — some items were left in the mail.",
    MORE_MAIL   = "Not all mail is shown — reopen the mailbox and click again for the rest.",
    DESC        = "|cffaaaaaaAdds an 'Open All' button to the mailbox. It takes every attachment and coin, skipping CoD and GM mail. Shift-click the button to ignore the filters and take everything.|r",
    O_ATTACH    = "Take item attachments",
    O_GOLD      = "Take money",
    O_KEEP      = "Keep this many bag slots free",
    O_SPEED     = "Speed (seconds between actions)",
    O_VERBOSE   = "Print a looted summary",
    O_RECIP     = "Recipient dropdown on the Send tab",
    MB_RECENT   = "Recently mailed",
    MB_CHARS    = "Your characters",
    MB_FRIENDS  = "Friends",
    MB_GUILD    = "Guild",
    MB_EMPTY    = "No contacts yet",
}
if GetLocale() == "deDE" then
    L.OPEN_ALL    = "Alle öffnen"
    L.IN_PROGRESS = "Läuft …"
    L.SUMMARY     = "Post geleert: %s%s erbeutet."
    L.AND_ITEMS   = " und %d Gegenstand/Gegenstände"
    L.BAGS_FULL   = "Taschen voll — einige Gegenstände blieben in der Post."
    L.MORE_MAIL   = "Es wird nicht die gesamte Post angezeigt — Briefkasten neu öffnen und nochmal klicken."
    L.DESC        = "|cffaaaaaaFügt dem Briefkasten einen 'Alle öffnen'-Knopf hinzu. Nimmt alle Anhänge und Münzen, überspringt Nachnahme- und GM-Post. Shift-Klick ignoriert die Filter und nimmt alles.|r"
    L.O_ATTACH    = "Gegenstands-Anhänge nehmen"
    L.O_GOLD      = "Geld nehmen"
    L.O_KEEP      = "So viele Taschenplätze frei lassen"
    L.O_SPEED     = "Tempo (Sekunden zwischen Aktionen)"
    L.O_VERBOSE   = "Beute-Zusammenfassung ausgeben"
    L.O_RECIP     = "Empfänger-Dropdown im Versenden-Tab"
    L.MB_RECENT   = "Zuletzt gemailt"
    L.MB_CHARS    = "Deine Charaktere"
    L.MB_FRIENDS  = "Freunde"
    L.MB_GUILD    = "Gilde"
    L.MB_EMPTY    = "Noch keine Kontakte"
end

-- ---------------------------------------------------------
-- Bag helpers
-- ---------------------------------------------------------
local function countItemsAndMoney()
    local items = 0
    for bag = 0, NUM_BAGS do
        local n = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local _, count = GetContainerItemInfo(bag, slot)
            if count then items = items + count end
        end
    end
    return items, GetMoney()
end

local function freeBagSlots()
    local free = 0
    for bag = 0, NUM_BAGS do
        local f, fam = GetContainerNumFreeSlots(bag)
        if fam == 0 then free = free + (f or 0) end
    end
    return free
end

local function moneyString(c)
    if GetMoneyString then return GetMoneyString(c) end
    return format("%d", math.floor((c or 0) / 10000)) .. "g"
end

-- ---------------------------------------------------------
-- State machine
-- ---------------------------------------------------------
local button
local idx, aIdx, waiting, lastItems, lastGold, lastFinal, invFull, running, override, waitTries, waitStart
local startGold, startItems
local step, processCurrent, finish, openAll

local pump = CreateFrame("Frame")
pump:Hide()
pump:SetScript("OnUpdate", function(self, e)
    self.t = (self.t or 0) - e
    if self.t <= 0 then self:Hide(); step() end
end)
local function schedule()
    pump.t = mod.db and mod.db.openSpeed or 0.15
    pump:Show()
end

function step()
    if not running then return end
    if idx <= 0 then return finish() end

    if waiting then
        local items, gold = countItemsAndMoney()
        -- on a confirmed change, advance and process the NEXT take immediately:
        -- the throttle gap already elapsed while we waited for this confirmation,
        -- so we don't add a second full wait per attachment (that ~doubled the time)
        if gold ~= lastGold then
            waiting = false; idx = idx - 1; aIdx = ATTACH_MAX; return step()
        elseif items ~= lastItems then
            waiting = false; aIdx = aIdx - 1
            if lastFinal then lastFinal = false; idx = idx - 1; aIdx = ATTACH_MAX end
            return step()
        else
            -- time-based watchdog: only give up if the take genuinely stalled
            -- (robust whether step() is driven by the timer or MAIL_INBOX_UPDATE)
            if GetTime() - (waitStart or 0) > 3 then
                waiting = false
                idx = idx - 1; aIdx = ATTACH_MAX
                return schedule()
            end
            return schedule()
        end
    end
    waitTries = 0
    return processCurrent()
end

function processCurrent()
    local sender, subject, money, cod, _, itemCount, _, _, _, _, isGM = select(3, GetInboxHeaderInfo(idx))
    money = money or 0
    cod = cod or 0

    -- skip CoD + GM mail
    if cod > 0 or isGM then idx = idx - 1; aIdx = ATTACH_MAX; return step() end

    local takeItems = override or mod.db.attachments
    local takeGold  = override or mod.db.gold

    -- nothing wanted in this mail
    if not (takeItems and itemCount and itemCount > 0) and not (takeGold and money > 0) then
        idx = idx - 1; aIdx = ATTACH_MAX; return step()
    end

    -- find next attachment, scanning backwards
    while aIdx > 0 and not GetInboxItemLink(idx, aIdx) do aIdx = aIdx - 1 end

    -- free-space reserve
    if aIdx > 0 and not invFull and (mod.db.keepFree or 0) > 0 then
        if freeBagSlots() <= mod.db.keepFree then invFull = true end
    end

    if aIdx > 0 and takeItems and not invFull then
        lastItems, lastGold = countItemsAndMoney()
        TakeInboxItem(idx, aIdx)
        waiting = true; waitStart = GetTime()
        -- is this the final thing to take from this mail?
        local a2 = aIdx - 1
        while a2 > 0 and not GetInboxItemLink(idx, a2) do a2 = a2 - 1 end
        if a2 == 0 and not (takeGold and money > 0) then lastFinal = true end
        return schedule()
    elseif takeGold and money > 0 then
        lastItems, lastGold = countItemsAndMoney()
        TakeInboxMoney(idx)
        waiting = true; waitStart = GetTime()
        return schedule()
    else
        idx = idx - 1; aIdx = ATTACH_MAX; return step()
    end
end

function finish()
    pump:Hide()
    local shown, total = GetInboxNumItems()
    -- more mail than is currently loaded: refresh and keep going automatically,
    -- so a full inbox (>50) opens completely in one click (bounded retries)
    if total and shown and total > shown and not invFull and (mod._continues or 0) < 12 then
        mod._continues = (mod._continues or 0) + 1
        waiting = false
        mod._awaitRefresh = true
        CheckInbox()           -- mod._onInbox reopens once the inbox has refreshed
        return
    end
    running = false
    mod._continues = nil
    mod._awaitRefresh = nil
    ns:UnregisterEvent("UI_ERROR_MESSAGE", mod._onError)
    ns:UnregisterEvent("MAIL_INBOX_UPDATE", mod._onInbox)
    if button then button:SetText(L.OPEN_ALL); button:Enable() end
    if InboxFrame_Update then InboxFrame_Update() end

    if mod.db.verbose then
        local gold = GetMoney() - (startGold or GetMoney())
        local items = (select(1, countItemsAndMoney())) - (startItems or 0)
        if gold > 0 or items > 0 then
            local itemStr = items > 0 and format(L.AND_ITEMS, items) or ""
            ns:Print(format(L.SUMMARY, moneyString(gold), itemStr))
        end
    end
    if invFull then ns:Print(L.BAGS_FULL) end
end

function openAll(isRecursive)
    if running and not isRecursive then return end
    idx = (GetInboxNumItems()) or 0
    aIdx = ATTACH_MAX
    invFull = false; waiting = false; lastFinal = false; waitStart = nil
    if not isRecursive then
        override = IsShiftKeyDown()
        if idx == 0 then return end
        running = true
        startGold = GetMoney()
        startItems = (select(1, countItemsAndMoney()))
        mod._continues = 0
        if button then button:SetText(L.IN_PROGRESS); button:Disable() end
        -- confirm each take off MAIL_INBOX_UPDATE (server-paced + reliable);
        -- the pump timer is only a fallback. Registered once per session.
        ns:RegisterEvent("UI_ERROR_MESSAGE", mod._onError)
        ns:RegisterEvent("MAIL_INBOX_UPDATE", mod._onInbox)
    end
    step()
end

function mod._onInbox()
    if not running then return end
    if mod._awaitRefresh then
        mod._awaitRefresh = false
        return openAll(true)   -- reopen from the now-larger inbox
    end
    if waiting then step() end  -- a take just confirmed -> advance immediately
end

function mod._onError(_, arg1, arg2)
    local msg = arg2 or arg1   -- classic sends (message); newer sends (errorType, message)
    if msg == ERR_INV_FULL then
        invFull = true; waiting = false
    elseif ERR_ITEM_MAX_COUNT and msg == ERR_ITEM_MAX_COUNT then
        aIdx = aIdx - 1; waiting = false
    end
end

-- ---------------------------------------------------------
-- Recipient book on the Send tab: recently mailed + your own characters
-- (recorded account-wide) + live friends + guild. Click a name to fill it in.
-- ---------------------------------------------------------
local sendButton
local sendHooked

local function mailStore()
    if not VuloClassicUIDB then return nil end
    -- top-level (account-wide) so it survives profile switches and ApplyDefaults
    VuloClassicUIDB.mailBook = VuloClassicUIDB.mailBook or { alts = {}, recent = {} }
    return VuloClassicUIDB.mailBook
end

local function recordAlt()
    local s = mailStore(); if not s then return end
    local name, realm = UnitName("player"), GetRealmName()
    local faction = UnitFactionGroup("player")
    if not name or not realm then return end
    for _, a in ipairs(s.alts) do
        if a.name == name and a.realm == realm then return end
    end
    s.alts[#s.alts + 1] = { name = name, realm = realm, faction = faction }
    table.sort(s.alts, function(a, b) return a.name < b.name end)
end

local function recordRecent(recipient)
    local s = mailStore(); if not s then return end
    recipient = recipient and strtrim(recipient) or ""
    if recipient == "" then return end
    for i = #s.recent, 1, -1 do if s.recent[i] == recipient then table.remove(s.recent, i) end end
    table.insert(s.recent, 1, recipient)
    for i = #s.recent, 13, -1 do table.remove(s.recent, i) end
end

local function fillRecipient(name)
    if not SendMailNameEditBox then return end
    SendMailNameEditBox:SetText(name)
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetFocus() end
end

local function addNames(entries, titleText, names, cap)
    if #names == 0 then return end
    if #entries > 0 then entries[#entries + 1] = { separator = true } end
    entries[#entries + 1] = { title = true, text = titleText }
    for i = 1, (cap and math.min(#names, cap) or #names) do
        local n = names[i]
        entries[#entries + 1] = { text = n, func = function() fillRecipient(n) end }
    end
end

local function buildRecipientMenu()
    local s = mailStore() or { alts = {}, recent = {} }
    local entries = {}
    local me, myRealm, myFaction = UnitName("player"), GetRealmName(), UnitFactionGroup("player")

    addNames(entries, L.MB_RECENT, s.recent)

    local chars = {}
    for _, a in ipairs(s.alts) do
        if a.name ~= me and a.realm == myRealm and a.faction == myFaction then chars[#chars + 1] = a.name end
    end
    addNames(entries, L.MB_CHARS, chars, 30)

    local friends = {}
    local nF = (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends())
        or (GetNumFriends and GetNumFriends()) or 0
    for i = 1, nF do
        local info = C_FriendList and C_FriendList.GetFriendInfoByIndex and C_FriendList.GetFriendInfoByIndex(i)
        local fname = (info and info.name) or (GetFriendInfo and GetFriendInfo(i))
        if fname then friends[#friends + 1] = fname end
    end
    addNames(entries, L.MB_FRIENDS, friends, 30)

    if IsInGuild and IsInGuild() then
        -- ask for a fresh roster (async); this open uses cached data, next is fresh
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
        elseif GuildRoster then GuildRoster() end
        local guild = {}
        local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
        for i = 1, n do
            local gname, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if gname and online then
                gname = gname:match("^[^%-]+") or gname
                if gname ~= me then guild[#guild + 1] = gname end
            end
        end
        table.sort(guild)
        addNames(entries, L.MB_GUILD, guild, 30)
    end

    if #entries == 0 then entries[#entries + 1] = { disabled = true, text = L.MB_EMPTY } end
    return entries
end

local function createSendButton()
    if sendButton or not SendMailFrame or not SendMailNameEditBox then return end
    sendButton = CreateFrame("Button", "VulMailToButton", SendMailFrame)
    sendButton:SetSize(24, 24)
    sendButton:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 0, 1)
    sendButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    sendButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round")
    sendButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    sendButton:SetFrameLevel(sendButton:GetFrameLevel() + 1)
    sendButton:SetScript("OnClick", function(self) ns:ShowPopupMenu(buildRecipientMenu(), self) end)
end

local function applySendButton()
    createSendButton()
    if sendButton then sendButton:SetShown(mod.db.recipients ~= false) end
end

-- ---------------------------------------------------------
-- Button on the inbox
-- ---------------------------------------------------------
local function createButton()
    if button or not InboxFrame then return end
    button = CreateFrame("Button", "VulMailOpenAll", InboxFrame, "UIPanelButtonTemplate")
    button:SetSize(120, 25)
    if OpenAllMail then
        button:SetAllPoints(OpenAllMail)
    else
        button:SetPoint("CENTER", InboxFrame, "TOP", -36, -399)
    end
    button:SetText(L.OPEN_ALL)
    button:SetFrameLevel(button:GetFrameLevel() + 1)
    button:SetScript("OnClick", function() openAll() end)
end

local function onMailShow()
    createButton()
    applySendButton()
    if OpenAllMail then OpenAllMail:Hide() end
    if button then button:Show() end
end
local function onMailClosed()
    running = false
    pump:Hide()
    waiting = false
    ns:UnregisterEvent("UI_ERROR_MESSAGE", mod._onError)
    if button then button:SetText(L.OPEN_ALL); button:Enable() end
end

-- ---------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------
function mod:OnEnable()
    createButton()
    recordAlt()
    applySendButton()
    if not sendHooked and SendMail then
        hooksecurefunc("SendMail", function(recipient) recordRecent(recipient) end)
        sendHooked = true
    end
    ns:RegisterEvent("MAIL_SHOW", onMailShow)
    ns:RegisterEvent("MAIL_CLOSED", onMailClosed)
    if button then button:Show() end
end

function mod:OnDisable()
    onMailClosed()
    ns:UnregisterEvent("MAIL_SHOW", onMailShow)
    ns:UnregisterEvent("MAIL_CLOSED", onMailClosed)
    if button then button:Hide() end
    if sendButton then sendButton:Hide() end
    if OpenAllMail then OpenAllMail:Show() end
end

function mod:GetOptions()
    return {
        { type = "desc", text = L.DESC },
        { type = "toggle", label = L.O_ATTACH,
          get = function() return mod.db.attachments end,
          set = function(_, v) mod.db.attachments = v end },
        { type = "toggle", label = L.O_GOLD,
          get = function() return mod.db.gold end,
          set = function(_, v) mod.db.gold = v end },
        { type = "toggle", label = L.O_VERBOSE,
          get = function() return mod.db.verbose end,
          set = function(_, v) mod.db.verbose = v end },
        { type = "toggle", label = L.O_RECIP,
          get = function() return mod.db.recipients end,
          set = function(_, v) mod.db.recipients = v; applySendButton() end },
        { type = "slider", label = L.O_KEEP, min = 0, max = 12, step = 1,
          get = function() return mod.db.keepFree or 0 end,
          set = function(_, v) mod.db.keepFree = v end },
        { type = "slider", label = L.O_SPEED, min = 0.05, max = 1.0, step = 0.05,
          get = function() return mod.db.openSpeed or 0.15 end,
          set = function(_, v) mod.db.openSpeed = v end },
    }
end
