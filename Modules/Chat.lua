-- VuloClassicUI / Modules / Chat
-- Taint: no global overwrites (only AddMessageEventFilter + hooksecurefunc), no fields on Blizzard tables (state lives in FD).
local _, ns = ...
local L  = ns.L
local UI = ns.UI

local mod = ns:RegisterModule("chat", {
    name        = "Chat",
    group       = "Chat & Social",
    description = "Polishes Blizzard's chat: a dark panel with an icon sidebar, timestamps, class-coloured names, clickable links, dark tabs, idle fade and history that survives a /reload. Every part is optional.",
    defaults = {
        enabled         = true,
        timestamps      = true,
        timestampFormat = "%H:%M",
        classColors     = true,
        urls            = true,
        tabStyle        = true,
        bgPanel         = true,
        font            = true,
        topFade         = true,
        sidebar         = true,
        friendsCounter  = true,
        idleFade        = false,
        idleFadeDelay   = 15,
        idleFadeOpacity = 35,
        copyButton      = false,
        history         = true,
        historyMax      = 150,
        scrollbackLines = 512,
        linkItemLevel   = true,
        tabFontSize     = 12,
        -- Edit-Mode position for ChatFrame1; moved=false leaves Blizzard in charge
        chatPos         = { moved = false, x = 0, y = 0 },
        chatFontSize    = 0,       -- 0 = keep each window's Blizzard size
        panelOpacity    = 78,
        indent          = true,
    },
})

-- mod._enabled is only set true AFTER OnEnable returns, so we track our own flag.
local active = false

-- forward declarations: assigned far below, but captured as upvalues by functions in between
local sidebarFrame
local alignDockScroll
local createChatWindow

local ACCENT     = ns.COLORS.accent
local NUM        = _G.NUM_CHAT_WINDOWS or 10
local URL_LINK   = "vcuiurl"
local URL_HEX    = "ff3b9dff"

local fdata = setmetatable({}, { __mode = "k" })
local function FD(frame)
    local t = fdata[frame]
    if not t then t = {}; fdata[frame] = t end
    return t
end

local function isSecret(v)
    return issecretvalue and issecretvalue(v)
end

local function eachChatFrame(fn)
    for i = 1, NUM do
        local cf = _G["ChatFrame" .. i]
        if cf then fn(cf, i) end
    end
end

local _tsOrig
local function applyTimestamps()
    if not (active and mod.db.timestamps) then
        if _tsOrig ~= nil then pcall(SetCVar, "showTimestamps", _tsOrig); _tsOrig = nil end
        return
    end
    if _tsOrig == nil then _tsOrig = GetCVar and GetCVar("showTimestamps") or "none" end
    local fmt = mod.db.timestampFormat
    if not fmt or fmt == "" then fmt = "%H:%M" end
    pcall(SetCVar, "showTimestamps", fmt .. " ")
end

local function applyIndentWrap()
    local on = (active and mod.db.indent) and true or false
    eachChatFrame(function(cf)
        if cf.SetIndentedWordWrap then pcall(cf.SetIndentedWordWrap, cf, on) end
    end)
end

local CLASS_TYPES = {
    "SAY", "YELL", "EMOTE", "WHISPER", "WHISPER_INFORM",
    "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
    "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "CHANNEL",
}
local function applyClassColors()
    local on = (active and mod.db.classColors) and true or false
    -- chatClassColorOverride "1" forces colouring off and silently voids the per-type flag
    if on and GetCVar and GetCVar("chatClassColorOverride") == "1" then
        pcall(SetCVar, "chatClassColorOverride", "2")
    end
    if type(ChatTypeInfo) ~= "table" then return end
    for _, t in ipairs(CLASS_TYPES) do
        local info = ChatTypeInfo[t]
        if info then info.colorNameByClass = on end
    end
end

local function linkifyURL(url)
    return string.format("|c%s|H%s:%s|h[%s]|h|r", URL_HEX, URL_LINK, url, url)
end

local function wrapURLs(text)
    if text:find("|H", 1, true) then return text end
    if not (text:find("://", 1, true) or text:find("www.", 1, true)) then return text end
    text = text:gsub("(%a[%w%+%.%-]*://[%w@:%%%._%+~#=/%-%?&]+)", linkifyURL)
    -- prev-char guard: don't re-wrap a www. inside the link just made or a longer domain
    text = text:gsub("(.?)(www%.[%w@:%%%._%+~#=/%-%?&]+)", function(prev, u)
        if prev == "/" or prev == "." or prev == "|" or prev == ":" then return prev .. u end
        return prev .. linkifyURL(u)
    end)
    return text
end

-- Only rewrite the message body (arg 3); the channel name (arg 5) is load-bearing for Blizzard's channel-window routing.
--
-- The level lands AFTER the closing |h, outside the hyperlink, not inside the
-- bracketed link text. It used to sit inside ("[Name (232)]"), and the Chinese
-- client re-processes chat links against their own data: a link text that no
-- longer matches the item turned into the NAME OF THE QUEST with that number
-- as its id. Outside the link the client's text is byte-identical to what it
-- produced, so any re-resolution keeps working -- and the display is the same
-- one glyph further right.
local function addItemLevels(msg)
    if not msg:find("|Hitem:", 1, true) then return msg end
    -- Our own suffix from an earlier pass: "]|h (123)" only ever comes out of
    -- this function. Since the level moved OUTSIDE the brackets, the guard on
    -- the link text below cannot see it anymore -- without this line a message
    -- run through the filter twice would stack " (232) (232)".
    if msg:find("%]|h %(%d+%)") then return msg end
    return (msg:gsub("(|Hitem:[^|]+|h%[)(.-)(%]|h)", function(pre, name, post)
        local itemString = pre:match("|H(item:[^|]+)|h")
        if itemString and GetItemInfoInstant then
            local _, _, _, equipLoc, _, classID = GetItemInfoInstant(itemString)
            if (classID == 2 or classID == 4) and equipLoc and equipLoc ~= ""
               and equipLoc ~= "INVTYPE_BAG"
               -- another addon may already have appended an item level; don't stack
               and not name:find("[%[%(]%s*%d+%s*[%]%)]%s*$") then
                -- uncached item -> quality nil -> skip; the probe requests the cache fill
                local quality, ilvl
                if GetItemInfo then
                    local _, _, q, il = GetItemInfo(itemString)
                    quality, ilvl = q, il
                end
                local lvl = ilvl or (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(itemString))
                if quality and quality >= 2 and lvl and lvl > 1 then
                    return pre .. name .. post .. " (" .. lvl .. ")"
                end
            end
        end
        return pre .. name .. post
    end))
end

local function msgFilter(self, event, msg, author, lang, channelName, ...)
    if not active then return false end

    if type(msg) == "string" and not isSecret(msg) then
        local newMsg = msg
        if mod.db.linkItemLevel ~= false then newMsg = addItemLevels(newMsg) end
        if mod.db.urls then newMsg = wrapURLs(newMsg) end
        if newMsg ~= msg then
            -- must return the FULL arg list; dropping trailing args (GUID) breaks class colour/menus
            return false, newMsg, author, lang, channelName, ...
        end
    end
    return false
end

local FILTER_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_LOOT",
}

local textPopup
local function showTextPopup(title, text)
    if not textPopup then
        local p = CreateFrame("Frame", "VCUIChatCopyPopup", UIParent)
        textPopup = p
        p:SetSize(560, 360)
        p:SetPoint("CENTER")
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:EnableMouse(true)
        p:SetMovable(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", p.StartMoving)
        p:SetScript("OnDragStop",  p.StopMovingOrSizing)
        if UI and UI.StyleBackdrop then UI:StyleBackdrop(p, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim }) end
        if UI and UI.CreateShadow then UI:CreateShadow(p) end
        if _G.tinsert and _G.UISpecialFrames then tinsert(UISpecialFrames, "VCUIChatCopyPopup") end

        local strip = p:CreateTexture(nil, "ARTWORK")
        strip:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
        strip:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
        strip:SetHeight(2)
        if UI and UI.SetGradient then
            UI.SetGradient(strip, "HORIZONTAL", ACCENT.r, ACCENT.g, ACCENT.b, 0.0, ACCENT.r, ACCENT.g, ACCENT.b, 0.9)
        end

        p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if UI and UI.Font then UI.Font(p.title, 13) end
        p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -11)
        p.title:SetTextColor(ACCENT.r, ACCENT.g, ACCENT.b)

        local close = CreateFrame("Button", nil, p)
        close:SetSize(22, 22)
        close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -6, -8)
        local cfs = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        cfs:SetPoint("CENTER"); cfs:SetText("x"); cfs:SetTextColor(0.7, 0.7, 0.75)
        close:SetScript("OnEnter", function() cfs:SetTextColor(ACCENT.r, ACCENT.g, ACCENT.b) end)
        close:SetScript("OnLeave", function() cfs:SetTextColor(0.7, 0.7, 0.75) end)
        close:SetScript("OnClick", function() p:Hide() end)

        local scroll = CreateFrame("ScrollFrame", "VCUIChatCopyScroll", p, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -34)
        scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -32, 38)

        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject("ChatFontNormal")
        eb:SetWidth(500)
        eb:EnableMouse(true)
        eb:SetScript("OnEscapePressed", function() p:Hide() end)
        eb:SetScript("OnTextChanged", function(self)
            if self._locked and self:GetText() ~= self._locked then
                self:SetText(self._locked)
                self:HighlightText()
            end
        end)
        scroll:SetScrollChild(eb)
        p.editBox = eb

        local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 14)
        hint:SetText(L["Ctrl+A to select all, Ctrl+C to copy."])
    end

    textPopup.title:SetText(title or L["Copy"])
    local eb = textPopup.editBox
    eb._locked = nil
    eb:SetText(text or "")
    eb._locked = text or ""
    textPopup:Show()
    eb:SetFocus()
    eb:HighlightText()
    eb:SetCursorPosition(0)
end

local _urlHooked = false
local function installURLHandler()
    if _urlHooked or type(_G.SetItemRef) ~= "function" then return end
    _urlHooked = true
    hooksecurefunc("SetItemRef", function(link)
        if type(link) ~= "string" then return end
        local url = link:match("^" .. URL_LINK .. ":(.+)$")
        if url then showTextPopup(L["Link"], url) end
    end)
end

-- stripped tab textures; the GLOW frame is deliberately kept (new-message flash)
local TAB_SUFFIX = {
    "Left", "Middle", "Right",
    "SelectedLeft", "SelectedMiddle", "SelectedRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
    "ActiveLeft", "ActiveMiddle", "ActiveRight",
}
local underline

local function selectedChatIndex()
    local sel = _G.FCFDock_GetSelectedWindow and _G.GENERAL_CHAT_DOCK
                and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    if sel and sel.GetID then return sel:GetID() end
    return 1
end

local function styleOneTab(i)
    local tab = _G["ChatFrame" .. i .. "Tab"]
    if not tab then return end
    local d = FD(tab)

    for _, suf in ipairs(TAB_SUFFIX) do
        local t = _G["ChatFrame" .. i .. "Tab" .. suf]
        if t and t.SetTexture then t:SetTexture(nil) end
    end

    -- Blizzard gives docked tabs (3+) a stray y-offset; zero it so all tabs share a line
    if not d.normalized then
        d.normalized = true
        if tab.SetHeight then tab:SetHeight(24) end
        if tab.SetPushedTextOffset then tab:SetPushedTextOffset(0, 0) end
        if tab:GetID() and tab:GetID() >= 3 and tab.SetPoint then
            local guard = false
            hooksecurefunc(tab, "SetPoint", function(self, point, rel, relPoint, x, y)
                if guard then return end
                if point == "LEFT" and relPoint == "LEFT" and y and y ~= 0 then
                    guard = true
                    self:SetPoint(point, rel, relPoint, x or 0, 0)
                    guard = false
                end
            end)
        end
    end

    -- Force uniform size + CENTER every pass; never read the tab's own size back (tabs 1-2 carry a larger font object). Owned here, not applyFont.
    local txt = tab.Text or _G["ChatFrame" .. i .. "TabText"]
    if txt then
        if txt.SetFont then
            local fallback = _G.ChatFontNormal and select(1, ChatFontNormal:GetFont())
            local fam = (mod.db.font and UI.FONT_PATH) or fallback
            local sz  = mod.db.tabFontSize or 12
            if fam then pcall(txt.SetFont, txt, fam, sz, "") end
        end
        if txt.ClearAllPoints then
            txt:ClearAllPoints()
            txt:SetPoint("CENTER", tab, "CENTER", 0, 0)
            if txt.SetJustifyH then txt:SetJustifyH("CENTER") end
        end
    end

    if not d.bg then
        d.bg = tab:CreateTexture(nil, "BACKGROUND")
        d.bg:SetPoint("TOPLEFT", tab, "TOPLEFT", 2, -3)
        d.bg:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 3)
    end
    local selected = (i == selectedChatIndex())
    d.bg:SetColorTexture(0.05, 0.05, 0.07, selected and 0.92 or 0.45)
    d.bg:Show()
end

local function unstyleOneTab(i)
    local tab = _G["ChatFrame" .. i .. "Tab"]
    if not tab then return end
    local d = fdata[tab]
    if d and d.bg then d.bg:Hide() end
    -- stripped tab textures only come back on /reload
end

local function updateTabs()
    -- Blizzard relays the dock on select/close/open and re-drops the scroll frame; re-assert
    if active and mod.db.bgPanel and alignDockScroll then alignDockScroll() end
    if not (active and mod.db.tabStyle) then
        for i = 1, NUM do unstyleOneTab(i) end
        if underline then underline:Hide() end
        return
    end
    for i = 1, NUM do
        -- gate on the TAB's visibility, not the chat frame's (docked tabs stay shown)
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and tab:IsShown() then styleOneTab(i) end
    end
    -- underline lives on UIParent, never a child of the protected tab
    if not underline then
        underline = UIParent:CreateTexture(nil, "OVERLAY")
        underline:SetHeight(2)
        underline:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.9)
    end
    local tab = _G["ChatFrame" .. selectedChatIndex() .. "Tab"]
    if tab then
        underline:ClearAllPoints()
        underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 6, 1)
        underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 1)
        underline:Show()
    else
        underline:Hide()
    end
end

local _tabHooked = false
local function installTabHooks()
    if _tabHooked then return end
    _tabHooked = true
    -- all restyles deferred so they run OUTSIDE the secure temp-window chain
    if _G.FCFDock_SelectWindow then
        hooksecurefunc("FCFDock_SelectWindow", function()
            ns.NextFrame(updateTabs)
        end)
    end
    if _G.FCF_Close then
        hooksecurefunc("FCF_Close", function()
            ns.NextFrame(updateTabs)
        end)
    end
    -- never hook FCFTab_UpdateColors / FCFDock_UpdateTabs: they taint even when deferred
    if _G.FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            ns.NextFrame(updateTabs)
        end)
    end
end

-- Idle fade: never hook a chat frame's OnEvent (taints the C dispatcher); driven by a standalone event frame + hover overlay + focus hooks.
local fadeDriver = CreateFrame("Frame")
fadeDriver:Hide()
local curAlpha, targetAlpha = 1, 1
local idleTimer
local engaged = 0       -- >0 while hovering or typing
local FADE_IN, FADE_OUT = 0.30, 1.5

local function applyFadeAlpha(a)
    eachChatFrame(function(cf, i)
        cf:SetAlpha(a)
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then eb:SetAlpha(a) end
    end)
    if _G.GeneralDockManager then GeneralDockManager:SetAlpha(a) end
    if underline then underline:SetAlpha(a) end
    if sidebarFrame then sidebarFrame:SetAlpha(a) end   -- parented to UIParent, not cf
end

local function setFadeTarget(a)
    if a == targetAlpha and a == curAlpha then return end
    targetAlpha = a
    fadeDriver:Show()
end

local function startIdleFade()
    if active and mod.db.idleFade and engaged == 0 then
        local minA = (mod.db.idleFadeOpacity or 35) / 100
        if minA < 0 then minA = 0 elseif minA > 0.9 then minA = 0.9 end
        setFadeTarget(minA)
    end
end

local function wakeChat()
    if idleTimer then idleTimer:Cancel(); idleTimer = nil end
    setFadeTarget(1)
    if active and mod.db.idleFade and engaged == 0 and C_Timer and C_Timer.NewTimer then
        idleTimer = C_Timer.NewTimer(mod.db.idleFadeDelay or 15, startIdleFade)
    end
end

fadeDriver:SetScript("OnUpdate", function(self, dt)
    self._acc = (self._acc or 0) + dt
    if self._acc < 0.03 then return end
    local step = self._acc; self._acc = 0
    if curAlpha == targetAlpha then self:Hide(); return end
    local rate = (targetAlpha > curAlpha) and (1 / FADE_IN) or (1 / FADE_OUT)
    if targetAlpha > curAlpha then
        curAlpha = math.min(targetAlpha, curAlpha + rate * step)
    else
        curAlpha = math.max(targetAlpha, curAlpha - rate * step)
    end
    applyFadeAlpha(curAlpha)
end)

-- MONSTER_* excluded on purpose: their sender can be a secret value
local activityFrame = CreateFrame("Frame")
local ACTIVITY_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_SYSTEM",
}
activityFrame:SetScript("OnEvent", function()
    if active and mod.db.idleFade then wakeChat() end
end)

local hoverOverlay
local function ensureHoverOverlay()
    if hoverOverlay or not _G.ChatFrame1 then return end
    local h = CreateFrame("Frame", nil, UIParent)
    hoverOverlay = h
    h:SetFrameStrata("BACKGROUND")
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", ChatFrame1, "TOPLEFT", -12, 34)
    h:SetPoint("BOTTOMRIGHT", ChatFrame1, "BOTTOMRIGHT", 14, -8)
    h:EnableMouse(false)            -- don't eat clicks; links must stay usable
    h:EnableMouseMotion(true)
    h:SetScript("OnEnter", function()
        engaged = engaged + 1
        if idleTimer then idleTimer:Cancel(); idleTimer = nil end
        setFadeTarget(1)
    end)
    h:SetScript("OnLeave", function()
        engaged = math.max(0, engaged - 1)
        wakeChat()
    end)
end

local function installFadeEditHooks()
    eachChatFrame(function(_, i)
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb and not FD(eb).fadeHooked then
            FD(eb).fadeHooked = true
            eb:HookScript("OnEditFocusGained", function()
                engaged = engaged + 1
                if idleTimer then idleTimer:Cancel(); idleTimer = nil end
                setFadeTarget(1)
            end)
            eb:HookScript("OnEditFocusLost", function()
                engaged = math.max(0, engaged - 1)
                wakeChat()
            end)
        end
    end)
end

local function applyIdleFade()
    if active and mod.db.idleFade then
        ensureHoverOverlay()
        installFadeEditHooks()
        for _, ev in ipairs(ACTIVITY_EVENTS) do pcall(activityFrame.RegisterEvent, activityFrame, ev) end
        wakeChat()
    else
        activityFrame:UnregisterAllEvents()
        if idleTimer then idleTimer:Cancel(); idleTimer = nil end
        engaged = 0
        setFadeTarget(1)
    end
end

local function stripEscapes(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    s = s:gsub("|K.-|k", "")
    s = s:gsub("||", "|")
    return s
end

local function readActiveChat()
    local cf = (_G.FCFDock_GetSelectedWindow and _G.GENERAL_CHAT_DOCK
                and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)) or _G.ChatFrame1
    if not (cf and cf.GetNumMessages) then return "" end
    local out = {}
    local n = cf:GetNumMessages() or 0
    for i = 1, n do
        local ok, text = pcall(cf.GetMessageInfo, cf, i)
        if ok and type(text) == "string" and not isSecret(text) then
            out[#out + 1] = stripEscapes(text)
        end
    end
    return table.concat(out, "\n")
end

local copyButton
local function ensureCopyButton()
    if copyButton or not _G.ChatFrame1 then return end
    local b = CreateFrame("Button", "VCUIChatCopyButton", UIParent)
    copyButton = b
    b:SetSize(20, 20)
    b:SetFrameStrata("HIGH")
    b:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 2, 4)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b); bg:SetColorTexture(0.05, 0.05, 0.07, 0.8)
    local ic = b:CreateTexture(nil, "OVERLAY")
    ic:SetPoint("CENTER"); ic:SetSize(14, 14)
    ic:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\copy.tga")
    ic:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.9)
    b:SetScript("OnEnter", function()
        ic:SetVertexColor(1, 1, 1, 1)
        UI:ShowTooltip(b, { anchor = "ANCHOR_LEFT", title = L["Copy chat"] })
    end)
    b:SetScript("OnLeave", function() ic:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.9); UI:HideTooltip() end)
    b:SetScript("OnClick", function() showTextPopup(L["Copy chat"], readActiveChat()) end)
end

local function applyCopyButton()
    if active and mod.db.copyButton and not mod.db.sidebar then
        ensureCopyButton()
        if copyButton then copyButton:Show() end
    elseif copyButton then
        copyButton:Hide()
    end
end

local function histStore()
    if not (ns.db and ns.db.char) then return nil end
    ns.db.char.chathistory = ns.db.char.chathistory or { lines = {} }
    if type(ns.db.char.chathistory.lines) ~= "table" then ns.db.char.chathistory.lines = {} end
    return ns.db.char.chathistory
end

local HIST_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
}
local histFrame = CreateFrame("Frame")

local function histCapture(_, event, msg, author, _, channelName)
    if not (active and mod.db.history) then return end
    if type(msg) ~= "string" or msg == "" then return end
    if isSecret(msg) or isSecret(author) or isSecret(channelName) then return end
    local store = histStore(); if not store then return end
    local lines = store.lines

    local last = lines[#lines]
    if last and last.m == msg and last.a == author and last.e == event then return end

    lines[#lines + 1] = {
        ts = (GetServerTime and GetServerTime()) or (time and time()) or 0,
        e  = event,
        a  = author,
        m  = (#msg > 4096) and msg:sub(1, 4096) or msg,
        c  = (event == "CHAT_MSG_CHANNEL") and channelName or nil,
    }
    local maxN = mod.db.historyMax or 150
    if maxN < 20 then maxN = 20 elseif maxN > 500 then maxN = 500 end
    while #lines > maxN do table.remove(lines, 1) end
end

local function shortType(event)
    return (event:gsub("^CHAT_MSG_", ""))
end

local _restored = false
local function restoreHistory()
    if _restored then return end
    _restored = true
    if not (active and mod.db.history) then return end
    local store = histStore(); if not (store and store.lines[1]) then return end
    local cf = _G.ChatFrame1
    if not (cf and cf.AddMessage) then return end

    cf:AddMessage("|cff707070" .. L["--- chat history ---"] .. "|r")
    for _, e in ipairs(store.lines) do
        local who = e.a and e.a:gsub("%-.*$", "") or ""
        local body
        if e.c and e.c ~= "" then
            local c = e.c:match("^(%d+)%.") or e.c
            body = "[" .. c .. "] " .. (who ~= "" and (who .. ": ") or "") .. e.m
        elseif who ~= "" then
            body = who .. ": " .. e.m
        else
            body = e.m
        end
        local stamp = (e.ts and e.ts > 0 and date) and ("|cff707070[" .. date("%H:%M", e.ts) .. "]|r ") or ""
        local info = (type(ChatTypeInfo) == "table") and ChatTypeInfo[shortType(e.e)] or nil
        local r, g, b = 0.7, 0.7, 0.72
        if info then r, g, b = info.r or r, info.g or g, info.b or b end
        cf:AddMessage(stamp .. body, r, g, b)
    end
end

local function applyHistory()
    if active and mod.db.history then
        for _, ev in ipairs(HIST_EVENTS) do pcall(histFrame.RegisterEvent, histFrame, ev) end
    else
        histFrame:UnregisterAllEvents()
    end
end
histFrame:SetScript("OnEvent", histCapture)

local BG  = { r = 0.04, g = 0.045, b = 0.055, a = 0.78 }
local panelBuilt = false

local function chatFontSize(i)
    local ovr = mod.db and mod.db.chatFontSize
    if ovr and ovr > 0 then return ovr end
    if FCF_GetChatWindowInfo then
        local ok, _, size = pcall(FCF_GetChatWindowInfo, i)
        if ok and type(size) == "number" and size > 0 then return size end
    end
    return 13
end

local function ensureFrameBG(cf, i)
    local d = FD(cf)
    if d.bg then return d.bg end
    local eb = _G["ChatFrame" .. i .. "EditBox"]
    local bg = CreateFrame("Frame", nil, cf)
    bg:SetPoint("TOPLEFT", cf, "TOPLEFT", -10, 4)
    bg:SetPoint("BOTTOMRIGHT", eb or cf, "BOTTOMRIGHT", 6, eb and -4 or -6)
    bg:SetFrameStrata(cf:GetFrameStrata())
    bg:SetFrameLevel(math.max(0, cf:GetFrameLevel() - 1))
    local tex = bg:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(BG.r, BG.g, BG.b, BG.a or 0.9)
    d.bg, d.bgTex = bg, tex
    if not cf:IsShown() then
        bg:Hide()
        cf:HookScript("OnShow", function() if active and mod.db.bgPanel then bg:Show() end end)
    end
    return bg
end

local EB_CHROME = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
local function styleEditBox(cf, i)
    local eb = _G["ChatFrame" .. i .. "EditBox"]
    if not eb then return end
    local d = FD(eb)
    if d.styled then return end
    d.styled = true
    for _, suf in ipairs(EB_CHROME) do
        local t = _G["ChatFrame" .. i .. "EditBox" .. suf]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -8, -6)
    eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 6, -6)
    eb:SetHeight(22)
    if eb.SetTextInsets then eb:SetTextInsets(10, 10, 0, 0) end
end

local function restoreEditBoxChrome(i)
    for _, suf in ipairs(EB_CHROME) do
        local t = _G["ChatFrame" .. i .. "EditBox" .. suf]
        if t and t.SetAlpha then t:SetAlpha(1) end
    end
end

-- reparenting beats Hide(): Blizzard re-Shows some of these on update
local hiddenHost = CreateFrame("Frame")
hiddenHost:Hide()

local SCROLL_BTN_SUFFIX = { "BottomButton", "DownButton", "UpButton", "MinimizeButton" }
local SOCIAL_BUTTONS = {
    "QuickJoinToastButton", "ChatFrameMenuButton", "ChatFrameChannelButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
}

-- Safe to blanket-strip cf:GetRegions(): our own textures live on child frames.
local function deBlizzardChrome(cf, i)
    local d = FD(cf)
    if d.deblizzed then return end
    d.deblizzed = true
    local name = "ChatFrame" .. i

    local bf = _G[name .. "ButtonFrame"]
    if bf then bf:SetParent(hiddenHost) end
    for _, suf in ipairs(SCROLL_BTN_SUFFIX) do
        local b = _G[name .. suf]
        if b then
            if b.SetAlpha then b:SetAlpha(0) end
            if b.EnableMouse then b:EnableMouse(false) end
        end
    end
    if cf.ScrollToBottomButton then cf.ScrollToBottomButton:SetParent(hiddenHost) end

    if cf.GetRegions then
        for r = 1, select("#", cf:GetRegions()) do
            local region = select(r, cf:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                pcall(region.SetTexture, region, "")
                if region.SetAtlas then pcall(region.SetAtlas, region, "") end
                if region.SetAlpha then region:SetAlpha(0) end
            end
        end
    end

    -- on some clients the real background is a child frame, not a direct region
    if cf.Background then
        if cf.Background.SetAlpha then cf.Background:SetAlpha(0) end
        if cf.Background.GetRegions then
            for r = 1, select("#", cf.Background:GetRegions()) do
                local region = select(r, cf.Background:GetRegions())
                if region and region.IsObjectType and region:IsObjectType("Texture")
                   and region.SetAlpha then
                    region:SetAlpha(0)
                end
            end
        end
    end
end

local _socialHidden = false
local function hideSocialButtons()
    if _socialHidden then return end
    _socialHidden = true
    for _, n in ipairs(SOCIAL_BUTTONS) do
        local f = _G[n]
        if f then
            if f.SetAlpha then f:SetAlpha(0) end
            if f.EnableMouse then f:EnableMouse(false) end
        end
    end
end

-- Restores only the functional buttons; stripped textures and moved anchors aren't recorded and come back on /reload.
local function reBlizzardChrome()
    eachChatFrame(function(cf, i)
        local d = fdata[cf]
        if not (d and d.deblizzed) then return end
        d.deblizzed = nil
        local name = "ChatFrame" .. i
        local bf = _G[name .. "ButtonFrame"]
        if bf then bf:SetParent(cf) end
        for _, suf in ipairs(SCROLL_BTN_SUFFIX) do
            local b = _G[name .. suf]
            if b then
                if b.SetAlpha then b:SetAlpha(1) end
                if b.EnableMouse then b:EnableMouse(true) end
            end
        end
        if cf.ScrollToBottomButton then cf.ScrollToBottomButton:SetParent(cf) end
    end)
    if _socialHidden then
        _socialHidden = false
        for _, n in ipairs(SOCIAL_BUTTONS) do
            local f = _G[n]
            if f then
                if f.SetAlpha then f:SetAlpha(1) end
                if f.EnableMouse then f:EnableMouse(true) end
            end
        end
    end
end

local function styleCombatLog()
    local qbf = _G.CombatLogQuickButtonFrame_Custom or _G.CombatLogQuickButtonFrame
    if not qbf then return end
    local d = FD(qbf)
    if d.styled then return end
    d.styled = true
    if qbf.GetRegions then
        for r = 1, select("#", qbf:GetRegions()) do
            local region = select(r, qbf:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                if region.SetAlpha then region:SetAlpha(0) end
            end
        end
    end
    -- anchor to the same reference as the tab dock so both rows match exactly
    local cf1 = _G.ChatFrame1
    local bg = cf1 and FD(cf1).bg
    if bg then
        pcall(qbf.ClearAllPoints, qbf)
        pcall(qbf.SetPoint, qbf, "TOPLEFT", bg, "TOPLEFT", 0, 0)
        pcall(qbf.SetPoint, qbf, "TOPRIGHT", bg, "TOPRIGHT", 0, 0)
        pcall(qbf.SetHeight, qbf, 24)
    else
        local cf2 = _G.ChatFrame2
        if cf2 then
            pcall(qbf.ClearAllPoints, qbf)
            pcall(qbf.SetPoint, qbf, "BOTTOMLEFT", cf2, "TOPLEFT", -10, 3)
            pcall(qbf.SetPoint, qbf, "BOTTOMRIGHT", cf2, "TOPRIGHT", 6, 3)
            pcall(qbf.SetHeight, qbf, 24)
        end
    end
    local bgt = qbf:CreateTexture(nil, "BACKGROUND")
    bgt:SetAllPoints()
    bgt:SetColorTexture(BG.r, BG.g, BG.b, BG.a or 0.9)
    qbf._vcuiBg = bgt   -- so the opacity slider can repaint this strip too
end

-- Blizzard anchors GeneralDockManagerScrollFrame below the dock manager, misaligning scroll-child tabs. Must run deferred (positions must be settled to measure); the >0.5 gate keeps it idempotent.
function alignDockScroll()
    local gdm = _G.GeneralDockManager
    local sf  = _G.GeneralDockManagerScrollFrame
    if not (gdm and sf and gdm.GetBottom and sf.GetBottom and sf.GetNumPoints) then return end
    local gb, sb = gdm:GetBottom(), sf:GetBottom()
    if not (gb and sb) then return end
    local dy = gb - sb
    if math.abs(dy) < 0.5 then return end
    local pts = {}
    for pi = 1, sf:GetNumPoints() do pts[pi] = { sf:GetPoint(pi) } end
    for _, pt in ipairs(pts) do
        sf:SetPoint(pt[1], pt[2], pt[3], pt[4] or 0, (pt[5] or 0) + dy)
    end
end

local function positionDock()
    local gdm = _G.GeneralDockManager
    local cf1 = _G.ChatFrame1
    if not (gdm and cf1 and FD(cf1).bg) then return end
    gdm:ClearAllPoints()
    gdm:SetPoint("BOTTOMLEFT", FD(cf1).bg, "TOPLEFT", 4, 0)
    gdm:SetPoint("BOTTOMRIGHT", FD(cf1).bg, "TOPRIGHT", 0, 0)
    gdm:SetHeight(24)
    if _G.GeneralDockManagerScrollFrame then _G.GeneralDockManagerScrollFrame:SetHeight(24) end
    if _G.GeneralDockManagerScrollFrameChild then _G.GeneralDockManagerScrollFrameChild:SetHeight(24) end
    ns.NextFrame(alignDockScroll)
end

local topFadeTex
-- Kept separately from the host frame: the gradient bakes BG.a, so changing the
-- panel opacity has to repaint it. ensureTopFade returns early once the host
-- exists, so without this reference the fade stayed at whatever opacity it was
-- first built with.
local topFadeGrad

local function ensureTopFade()
    local cf1 = _G.ChatFrame1
    if topFadeTex or not cf1 then return end
    local host = CreateFrame("Frame", nil, cf1)
    host:SetFrameLevel(cf1:GetFrameLevel() + 1)
    host:SetPoint("TOPLEFT", cf1, "TOPLEFT", 0, 2)
    host:SetPoint("TOPRIGHT", cf1, "TOPRIGHT", 0, 2)
    host:SetHeight(26)
    local t = host:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    UI.SetGradient(t, "VERTICAL", BG.r, BG.g, BG.b, 0, BG.r, BG.g, BG.b, BG.a or 0.9)
    topFadeTex  = host
    topFadeGrad = t
end

local function repaintTopFade()
    if topFadeGrad then
        UI.SetGradient(topFadeGrad, "VERTICAL", BG.r, BG.g, BG.b, 0, BG.r, BG.g, BG.b, BG.a or 0.9)
    end
end

local function applyTopFade()
    if active and mod.db.topFade then
        ensureTopFade()
        if topFadeTex then topFadeTex:Show() end
    elseif topFadeTex then
        topFadeTex:Hide()
    end
end

local ICON_IDLE, ICON_HOVER = 0.45, 0.95
local function makeSidebarIcon(parent, tex, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetAllPoints()
    ic:SetTexture(tex)
    ic:SetVertexColor(1, 1, 1, ICON_IDLE)
    b._icon = ic
    b:SetScript("OnEnter", function(self)
        ic:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, ICON_HOVER)
        if tip then UI:ShowTooltip(self, { anchor = "ANCHOR_LEFT", title = tip }) end
    end)
    b:SetScript("OnLeave", function()
        ic:SetVertexColor(1, 1, 1, ICON_IDLE)
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function makeSidebarGlyph(parent, glyph, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    local fs = b:CreateFontString(nil, "ARTWORK")
    if UI and UI.Font then UI.Font(fs, 18) else fs:SetFontObject("GameFontNormalLarge") end
    fs:SetAllPoints()
    fs:SetJustifyH("CENTER"); fs:SetJustifyV("MIDDLE")
    fs:SetText(glyph)
    fs:SetTextColor(1, 1, 1, ICON_IDLE)
    b._fs = fs
    b:SetScript("OnEnter", function(self)
        fs:SetTextColor(ACCENT.r, ACCENT.g, ACCENT.b, ICON_HOVER)
        if tip then UI:ShowTooltip(self, { anchor = "ANCHOR_LEFT", title = tip }) end
    end)
    b:SetScript("OnLeave", function()
        fs:SetTextColor(1, 1, 1, ICON_IDLE)
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- reads cached counts only; ShowFriends() requests the server list
local function updateFriendsCount()
    local sb = sidebarFrame
    if not (sb and sb._friendsCount) then return end
    local wow = (C_FriendList and C_FriendList.GetNumOnlineFriends
                 and C_FriendList.GetNumOnlineFriends()) or 0
    local bn = 0
    if BNGetNumFriends then
        local ok, _, online = pcall(BNGetNumFriends)   -- returns numFriends, numOnline
        if ok then bn = online or 0 end
    end
    sb._friendsWow, sb._friendsBN = wow, bn
    local total = wow + bn
    sb._friendsCount:SetText(total)
    if total > 0 then
        sb._friendsCount:SetTextColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.95)
    else
        sb._friendsCount:SetTextColor(1, 1, 1, 0.35)
    end
end

local function applyFriendsCounter()
    local sb = sidebarFrame
    if not (sb and sb._friendsBtn and sb._copyBtn) then return end
    local on = active and mod.db.friendsCounter ~= false
    sb._friendsBtn:SetShown(on)
    sb._friendsCount:SetShown(on)
    sb._copyBtn:ClearAllPoints()
    if on then
        sb._copyBtn:SetPoint("TOP", sb._friendsCount, "BOTTOM", 0, -12)
        if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
        updateFriendsCount()
    else
        sb._copyBtn:SetPoint("TOP", sb, "TOP", 0, -10)
    end
end

local function positionSidebar()
    local sb, cf1 = sidebarFrame, _G.ChatFrame1
    if not (sb and cf1) then return end
    local d = FD(cf1)
    sb:ClearAllPoints()
    if d.bg and active and mod.db.bgPanel then
        -- x = 0: panel left already equals cf1 left - 10, so no extra offset
        sb:SetPoint("TOPRIGHT", d.bg, "TOPLEFT", 0, 0)
        sb:SetPoint("BOTTOMRIGHT", d.bg, "BOTTOMLEFT", 0, 0)
    else
        sb:SetPoint("TOPRIGHT", cf1, "TOPLEFT", -10, 4)
        sb:SetPoint("BOTTOMRIGHT", cf1, "BOTTOMLEFT", -10, -6)
    end
end

local function buildSidebar()
    if sidebarFrame or not _G.ChatFrame1 then return end
    local cf1 = _G.ChatFrame1
    local sb = CreateFrame("Frame", "VCUIChatSidebar", UIParent)
    sidebarFrame = sb
    sb:SetWidth(28)
    positionSidebar()
    sb:SetFrameStrata(cf1:GetFrameStrata())
    sb:SetFrameLevel(cf1:GetFrameLevel() + 2)
    local bgt = sb:CreateTexture(nil, "BACKGROUND")
    bgt:SetAllPoints()
    bgt:SetColorTexture(BG.r, BG.g, BG.b, BG.a or 0.9)
    sb._vcuiBg = bgt   -- so the opacity slider can repaint the icon strip too
    local div = sb:CreateTexture(nil, "OVERLAY")
    div:SetWidth(1)
    div:SetColorTexture(1, 1, 1, 0.06)
    div:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
    div:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)

    local friendsBtn = makeSidebarIcon(sb, "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\friends.tga",
        nil, function() if ToggleFriendsFrame then ToggleFriendsFrame(1) end end)
    friendsBtn:SetPoint("TOP", sb, "TOP", 0, -10)
    local fc = friendsBtn:CreateFontString(nil, "OVERLAY")
    if UI and UI.Font then UI.Font(fc, 11) else fc:SetFontObject("GameFontNormalSmall") end
    fc:SetPoint("TOP", friendsBtn, "BOTTOM", 0, -2)
    fc:SetJustifyH("CENTER")
    fc:SetText("0")
    fc:SetTextColor(1, 1, 1, 0.35)
    sb._friendsBtn, sb._friendsCount = friendsBtn, fc
    friendsBtn:SetScript("OnEnter", function(self)
        self._icon:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, ICON_HOVER)
        -- OnLeave stays the factory's: it hides the tooltip and resets the icon.
        local lines = { { string.format("%s: %d", _G.FRIENDS or "Friends", sb._friendsWow or 0), 1, 1, 1 } }
        if BNGetNumFriends then
            lines[2] = { string.format("Battle.net: %d", sb._friendsBN or 0), 1, 1, 1 }
        end
        UI:ShowTooltip(self, { anchor = "ANCHOR_LEFT", title = L["Friends online"], lines = lines })
    end)
    if C_Timer and C_Timer.NewTicker then
        sb._friendsTicker = C_Timer.NewTicker(60, function()
            if active and mod.db.friendsCounter ~= false and sb:IsShown()
               and C_FriendList and C_FriendList.ShowFriends then
                pcall(C_FriendList.ShowFriends)
            end
        end)
    end

    local copyBtn = makeSidebarIcon(sb, "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\copy.tga",
        L["Copy chat"], function() showTextPopup(L["Copy chat"], readActiveChat()) end)
    sb._copyBtn = copyBtn
    -- copyBtn's TOP anchor is owned by applyFriendsCounter

    local gearBtn = makeSidebarIcon(sb, "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\gear.tga",
        L["Settings"], function()
            if ns.UI and ns.UI.ToggleMainFrame then
                if not (ns.UI.mainFrame and ns.UI.mainFrame:IsShown()) then ns.UI:ToggleMainFrame() end
                if ns.UI.ShowModulePage then ns.UI:ShowModulePage("chat") end
            end
        end)
    gearBtn:SetPoint("TOP", copyBtn, "BOTTOM", 0, -12)

    local plusBtn = makeSidebarGlyph(sb, "+", L["New chat window"],
        function() if createChatWindow then createChatWindow() end end)
    plusBtn:SetPoint("TOP", gearBtn, "BOTTOM", 0, -10)

    local scrollBtn = makeSidebarIcon(sb, "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\arrow_down.tga",
        L["Scroll to bottom"], function()
            local cf = (_G.FCFDock_GetSelectedWindow and _G.GENERAL_CHAT_DOCK
                        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)) or _G.ChatFrame1
            if cf and cf.ScrollToBottom then pcall(cf.ScrollToBottom, cf) end
        end)
    scrollBtn:SetPoint("BOTTOM", sb, "BOTTOM", 0, 10)
    applyFriendsCounter()
end

local function applySidebar()
    if active and mod.db.sidebar then
        buildSidebar()
        if sidebarFrame then sidebarFrame:Show() end
        positionSidebar()
        applyFriendsCounter()
    elseif sidebarFrame then
        sidebarFrame:Hide()
    end
end

local function buildPanel()
    if panelBuilt or not _G.ChatFrame1 then return end
    panelBuilt = true
    eachChatFrame(function(cf, i)
        ensureFrameBG(cf, i)
        styleEditBox(cf, i)
    end)
    positionDock()
end

local function applyPanel()
    if active and mod.db.bgPanel then
        buildPanel()
        eachChatFrame(function(cf, i)
            local d = fdata[cf]
            if d and d.bg then
                d.bgTex:SetColorTexture(BG.r, BG.g, BG.b, BG.a or 0.9)
                if cf:IsShown() then d.bg:Show() end
            end
            -- styleEditBox is one-shot, so re-hide the input chrome on an OFF->ON toggle
            for _, suf in ipairs(EB_CHROME) do
                local t = _G["ChatFrame" .. i .. "EditBox" .. suf]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            deBlizzardChrome(cf, i)
        end)
        hideSocialButtons()
        styleCombatLog()
        positionDock()
    else
        eachChatFrame(function(cf, i)
            local d = fdata[cf]
            if d and d.bg then d.bg:Hide() end
            restoreEditBoxChrome(i)
        end)
        reBlizzardChrome()
    end
    applyTopFade()
    applySidebar()
end

local function applyFont()
    local use = active and mod.db.font
    local fallback = _G.ChatFontNormal and select(1, ChatFontNormal:GetFont())
    eachChatFrame(function(cf, i)
        local size = chatFontSize(i)
        if cf.SetFont then
            if use then pcall(cf.SetFont, cf, UI.FONT_PATH, size, "")
            elseif fallback then pcall(cf.SetFont, cf, fallback, size, "") end
        end
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb and eb.SetFont then
            if use then pcall(eb.SetFont, eb, UI.FONT_PATH, size, "")
            elseif fallback then pcall(eb.SetFont, eb, fallback, size, "") end
        end
        -- tab labels are owned by styleOneTab, not here, so the two never fight
    end)
end

local function applyPanelOpacity()
    BG.a = (mod.db.panelOpacity or 78) / 100
    eachChatFrame(function(cf)
        local d = fdata[cf]
        if d and d.bgTex then d.bgTex:SetColorTexture(BG.r, BG.g, BG.b, BG.a) end
    end)
    applyPanel()
    applyTopFade()
    -- Three more pieces carry the same background and were built once, so only
    -- the message area followed the slider: the top fade, the icon strip and the
    -- combat log button bar stayed at their original opacity and left a hard
    -- edge in the wrong shade.
    repaintTopFade()
    if sidebarFrame and sidebarFrame._vcuiBg then
        sidebarFrame._vcuiBg:SetColorTexture(BG.r, BG.g, BG.b, BG.a)
    end
    local qbf = _G.CombatLogQuickButtonFrame_Custom or _G.CombatLogQuickButtonFrame
    if qbf and qbf._vcuiBg then
        qbf._vcuiBg:SetColorTexture(BG.r, BG.g, BG.b, BG.a)
    end
end

-- FCF_OpenNewWindow is insecure chat code, so calling it from our button is taint-safe
function createChatWindow()
    if not FCF_OpenNewWindow then
        if ns.Print then ns:Print(L["This client can't create extra chat windows."]) end
        return
    end
    pcall(FCF_OpenNewWindow)
    local function restyle()
        -- a new window re-creates its Blizzard chrome; clear the guard so applyPanel re-strips
        for i = 1, NUM do
            local cf = _G["ChatFrame" .. i]
            local d = cf and fdata[cf]
            if d then d.deblizzed = nil end
        end
        applyPanel(); applyFont(); updateTabs()
    end
    ns.NextFrame(restyle)
end

-- The GetMaxLines guard is load-bearing: SetMaxLines wipes the window's backlog, so it must only run on an actual change.
local function applyScrollback()
    local want = mod.db.scrollbackLines or 128
    if not active or want < 128 then want = 128 end
    for i = 1, NUM do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.SetMaxLines and cf.GetMaxLines and cf:GetMaxLines() ~= want then
            cf:SetMaxLines(want)
        end
    end
end

local function applyAll()
    applyScrollback()   -- must stay FIRST: a later SetMaxLines would wipe restored lines
    applyTimestamps()
    applyClassColors()
    if mod.db.panelOpacity then BG.a = mod.db.panelOpacity / 100 end
    applyPanel()
    applyFont()
    applyIndentWrap()
    updateTabs()
    applyIdleFade()
    applyCopyButton()
    applyHistory()
end

local _filtersInstalled = false

-- Chat window mover: drives ChatFrame1 (docked tabs follow it). Blizzard keeps
-- control of the position until the first drag; from then on our saved CENTER
-- offset wins, re-asserted after Blizzard's own position restore.
local chatMover
local _chatPosHooked = false

local function applyChatPos()
    if not mod.active then return end
    local db = mod.db and mod.db.chatPos
    local f = _G.ChatFrame1
    if not (db and db.moved and f) then return end
    f:SetMovable(true)
    if f.SetUserPlaced then pcall(f.SetUserPlaced, f, true) end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 0)
end

local function ensureChatMover()
    if chatMover then return end
    local f = _G.ChatFrame1
    if not (f and ns.CreateMover) then return end
    local db = mod.db.chatPos
    if type(db) ~= "table" then
        db = { moved = false, x = 0, y = 0 }
        mod.db.chatPos = db
    end
    if not db.moved then
        -- seed from the live position so the first drag doesn't teleport
        local x, y = ns:GetCenterOffsets(f)
        if x then db.x, db.y = x, y end
    end
    chatMover = ns:CreateMover(f, {
        key      = "chatframe",
        label    = L["Chat"],
        db       = db,
        fill     = true,   -- overlay covers the whole chat window, not a small box
        onMove   = function() db.moved = true end,
        applyPos = applyChatPos,
    })
    -- ChatFrame1 is only the message area; the visible "window" is our dark panel,
    -- which reaches past it (and down to the edit box). Match that exact region so
    -- the whole thing is grabbable, not just the narrower text strip.
    if chatMover then
        local eb = _G["ChatFrame1EditBox"]
        chatMover:ClearAllPoints()
        chatMover:SetPoint("TOPLEFT", f, "TOPLEFT", -10, 4)
        chatMover:SetPoint("BOTTOMRIGHT", eb or f, "BOTTOMRIGHT", 6, eb and -4 or -6)
        -- ChatFrame1 captures clicks over its text (hyperlinks/menu) at its own high
        -- stack position, so a HIGH child mover never sees the right-click. Lift the
        -- mover clear above it so right-click reaches our handler (-> settings panel).
        chatMover:SetFrameStrata("DIALOG")
        chatMover:SetToplevel(true)
    end

    if not _chatPosHooked then
        _chatPosHooked = true
        -- Blizzard re-applies its own chat layout on login/resize; re-assert ours
        if _G.FCF_RestorePositionAndDimensions then
            hooksecurefunc("FCF_RestorePositionAndDimensions", function(frame)
                if frame == _G.ChatFrame1 then applyChatPos() end
            end)
        end
    end
end

-- Named, file-scope handlers so the registry can take them back out again.
local FRIEND_EVENTS = {
    "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED",
    "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
    "BN_CONNECTED", "BN_DISCONNECTED",
}

local function onFriendsChanged()
    updateFriendsCount()
end

local function onEnteringWorld()
    applyTimestamps()
    applyClassColors()
    if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
    if C_Timer and C_Timer.After then
        -- chat frames/dock settle after login; delay so anchors land on final positions
        C_Timer.After(0.5, function() applyPanel(); applyFont(); applyChatPos() end)
        C_Timer.After(1, updateTabs)
        C_Timer.After(2, function() applyTimestamps(); applyClassColors(); applyPanel(); applyFont() end)
        C_Timer.After(2, restoreHistory)
    else
        applyPanel(); applyFont(); updateTabs(); restoreHistory()
    end
end

function mod:OnEnable()
    active = true
    ensureChatMover()

    if not _filtersInstalled then
        _filtersInstalled = true
        if ChatFrame_AddMessageEventFilter then
            for _, ev in ipairs(FILTER_EVENTS) do
                ChatFrame_AddMessageEventFilter(ev, msgFilter)
            end
        end
        installURLHandler()
        installTabHooks()
    end

    -- ns:RegisterEvent pcall-guards unknown events, so BN_* missing on a client
    -- is skipped. One shared named handler for all six friend events: the loop
    -- used to build a fresh anonymous closure per event, which could never be
    -- taken back out by identity -- so the module left seven live handlers
    -- behind when it was switched off, kept quiet only by the `active` flag.
    for _, ev in ipairs(FRIEND_EVENTS) do
        self:RegisterEvent(ev, onFriendsChanged)
    end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", onEnteringWorld)

    applyAll()
end

function mod:OnDisable()
    active = false
    -- Filters/hooks stay installed and no-op via `active`. Scrollback is NOT reverted: SetMaxLines(128) would wipe visible lines.
    applyTimestamps()
    applyClassColors()
    applyPanel()
    applyFont()
    applyIndentWrap()
    updateTabs()
    applyIdleFade()
    applyCopyButton()
    applyHistory()
end

local TS_VALUES = {
    { value = "%H:%M",    text = "14:30" },
    { value = "%H:%M:%S", text = "14:30:45" },
    { value = "%I:%M",    text = "02:30" },
}

function mod:GetOptions()
    local items = {}

    table.insert(items, { type = "header", text = L["Chat"] })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaPolishes Blizzard's own chat — nothing is replaced, so it stays light and compatible. Every option below is independent.|r"] })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Timestamps"] })
    table.insert(items, {
        type = "toggle", label = L["Show timestamps"],
        tooltip = L["Prefixes each line with the time, using the game's own timestamp setting."],
        get = function() return mod.db.timestamps end,
        set = function(_, v) mod.db.timestamps = v; applyTimestamps() end,
    })
    table.insert(items, {
        type = "dropdown", label = L["Time format"], width = 200, values = TS_VALUES,
        get = function() return mod.db.timestampFormat end,
        set = function(_, v) mod.db.timestampFormat = v; applyTimestamps() end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Names & links"] })
    table.insert(items, {
        type = "toggle", label = L["Class-coloured names"],
        tooltip = L["Colours player names by their class in say, party, raid, guild, whisper and channels."],
        get = function() return mod.db.classColors end,
        set = function(_, v) mod.db.classColors = v; applyClassColors() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Clickable links"],
        tooltip = L["Turns web links into clickable links that open a copy box."],
        get = function() return mod.db.urls end,
        set = function(_, v) mod.db.urls = v end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Appearance"] })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaThe panel, input and sidebar reposition Blizzard's chat. Turning them off here hides them immediately; a |cffffffff/reload|r restores the exact original positions.|r"] })
    table.insert(items, {
        type = "toggle", label = L["Dark background panel"],
        tooltip = L["A dark panel behind the chat and input line, with the tab bar above it — one cohesive block."],
        get = function() return mod.db.bgPanel end,
        set = function(_, v) mod.db.bgPanel = v; applyPanel() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Top fade"],
        tooltip = L["Fades old lines into the panel at the top edge of the chat."],
        get = function() return mod.db.topFade end,
        set = function(_, v) mod.db.topFade = v; applyTopFade() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Icon sidebar"],
        tooltip = L["A slim bar left of the chat with copy, settings, new-window and scroll-to-bottom icons."],
        get = function() return mod.db.sidebar end,
        set = function(_, v) mod.db.sidebar = v; applySidebar(); applyCopyButton() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show online friends"],
        tooltip = L["Show how many friends are online at the top of the sidebar; click the icon to open the friends list."],
        get = function() return mod.db.friendsCounter ~= false end,
        set = function(_, v) mod.db.friendsCounter = v and true or false; applyFriendsCounter() end,
    })
    table.insert(items, {
        type = "button", label = L["Create new chat window"], width = 200,
        onClick = function() createChatWindow() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Use VuloUI font"],
        tooltip = L["Applies the VuloUI font to the chat text, tabs and input line."],
        get = function() return mod.db.font end,
        set = function(_, v) mod.db.font = v; applyFont(); updateTabs() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Style chat tabs"],
        tooltip = L["Flat dark tab background with an accent underline on the active tab."],
        get = function() return mod.db.tabStyle end,
        set = function(_, v) mod.db.tabStyle = v; updateTabs() end,
    })
    table.insert(items, {
        type = "slider", label = L["Tab label size"], min = 8, max = 16, step = 1,
        tooltip = L["One uniform font size for every chat tab label."],
        get = function() return mod.db.tabFontSize end,
        set = function(_, v) mod.db.tabFontSize = v; updateTabs() end,
    })
    table.insert(items, {
        type = "slider", label = L["Chat font size (0 = Blizzard)"], min = 0, max = 18, step = 1,
        tooltip = L["Overrides the message font size for every chat window. 0 keeps each window's own Blizzard size."],
        get = function() return mod.db.chatFontSize end,
        set = function(_, v) mod.db.chatFontSize = v; applyFont() end,
    })
    table.insert(items, {
        type = "slider", label = L["Scrollback (lines per window)"], min = 128, max = 1024, step = 128,
        tooltip = L["How many lines each chat window keeps for scrolling (Blizzard default: 128). More lines use a little more memory; changing this clears the currently shown lines once."],
        get = function() return mod.db.scrollbackLines or 512 end,
        set = function(_, v) mod.db.scrollbackLines = v; applyScrollback() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Item levels in chat links"],
        tooltip = L["Appends the item level to equipment links: [Sword] becomes [Sword (45)]."],
        get = function() return mod.db.linkItemLevel ~= false end,
        set = function(_, v) mod.db.linkItemLevel = v and true or false end,
    })
    table.insert(items, {
        type = "slider", label = L["Panel opacity (%)"], min = 0, max = 100, step = 5,
        tooltip = L["Transparency of the dark background panel behind the chat."],
        get = function() return mod.db.panelOpacity end,
        set = function(_, v) mod.db.panelOpacity = v; applyPanelOpacity() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Indent wrapped lines"],
        tooltip = L["Wraps long messages with continuation lines indented under the message start, for a cleaner column."],
        get = function() return mod.db.indent end,
        set = function(_, v) mod.db.indent = v; applyIndentWrap() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Copy button (standalone)"],
        tooltip = L["A small copy button above the chat. Off by default since the sidebar already has a copy icon; turn the sidebar off to use this instead."],
        get = function() return mod.db.copyButton end,
        set = function(_, v) mod.db.copyButton = v; applyCopyButton() end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Idle fade"] })
    table.insert(items, {
        type = "toggle", label = L["Fade chat when idle"],
        tooltip = L["Dims the chat after a while with no activity. A new message, hovering it or typing brings it back."],
        get = function() return mod.db.idleFade end,
        set = function(_, v) mod.db.idleFade = v; applyIdleFade() end,
    })
    table.insert(items, {
        type = "slider", label = L["Idle delay (seconds)"], min = 3, max = 60, step = 1,
        get = function() return mod.db.idleFadeDelay end,
        set = function(_, v) mod.db.idleFadeDelay = v; wakeChat() end,
    })
    table.insert(items, {
        type = "slider", label = L["Faded opacity (%)"], min = 0, max = 90, step = 5,
        get = function() return mod.db.idleFadeOpacity end,
        set = function(_, v) mod.db.idleFadeOpacity = v; if engaged == 0 then startIdleFade() end end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["History"] })
    table.insert(items, {
        type = "toggle", label = L["Keep chat history"],
        tooltip = L["Remembers recent chat per character and re-shows it after a /reload."],
        get = function() return mod.db.history end,
        set = function(_, v) mod.db.history = v; applyHistory() end,
    })
    table.insert(items, {
        type = "slider", label = L["Lines to keep"], min = 20, max = 500, step = 10,
        get = function() return mod.db.historyMax end,
        set = function(_, v) mod.db.historyMax = v end,
    })
    table.insert(items, {
        type = "button", label = L["Clear history"], width = 200,
        onClick = function()
            local store = histStore()
            if store then wipe(store.lines) end
            ns:Print(L["Chat history cleared."])
        end,
    })

    return items
end
