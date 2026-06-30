-- =========================================================
-- VuloClassicUI / Modules / Chat
-- A chat ENHANCER built on top of Blizzard's own chat frames (we never replace
-- the message display or the dock). Every feature is individually toggleable.
--
--   * Timestamps      — drives the showTimestamps CVar (no per-line work)
--   * Class colours   — drives ChatTypeInfo[type].colorNameByClass (Blizzard's
--                       own GUID→class name colouring)
--   * Clickable URLs  — AddMessageEventFilter wraps links + a SetItemRef hook
--                       opens a copy popup
--   * Short channels  — [1. General] → [1] (rewrites the channel tag only)
--   * Tab styling     — flat dark tab background + an accent underline on the
--                       active tab (textures stripped, glow kept)
--   * Idle fade       — the whole chat dims after a while, wakes on a new
--                       message / hover / typing
--   * Copy button     — reads the active window on demand into a copy popup
--   * History         — per-character ring buffer re-shown after a /reload
--
-- TAINT DISCIPLINE (this is why it stays safe on a live client):
--   * never overwrite a global Blizzard function — only ChatFrame_AddMessage-
--     EventFilter (sanctioned message interception) and hooksecurefunc
--   * never write our own fields onto Blizzard chat tables — all per-frame state
--     lives in a weak-keyed side table (FD)
--   * only touch the permanent docked frames 1..NUM_CHAT_WINDOWS
--   * SetCVar for timestamps; tab restyle deferred out of any secure chain
-- =========================================================
local _, ns = ...
local L  = ns.L
local UI = ns.UI

local mod = ns:RegisterModule("chat", {
    name        = "Chat",
    group       = "UI Reskin",
    description = "Polishes Blizzard's chat: a dark panel with an icon sidebar, timestamps, class-coloured names, clickable links, short channel tags, dark tabs, idle fade and history that survives a /reload. Every part is optional.",
    defaults = {
        enabled         = true,
        timestamps      = true,
        timestampFormat = "%H:%M",
        classColors     = true,
        urls            = true,
        shortenChannels = true,
        tabStyle        = true,
        bgPanel         = true,    -- dark panel behind chat + chrome-less input + tab bar above
        font            = true,    -- our font on chat, tabs and input
        topFade         = true,    -- top-edge fade so old lines melt into the panel
        sidebar         = true,    -- slim icon sidebar (copy / settings / scroll)
        idleFade        = false,   -- opt-in: it dims the chat when idle
        idleFadeDelay   = 15,
        idleFadeOpacity = 35,      -- % minimum alpha when idle (0..90)
        copyButton      = false,   -- standalone copy button (the sidebar carries copy instead)
        history         = true,
        historyMax      = 150,
    },
})

-- We can't use mod._enabled during the first OnEnable (the core sets it true only
-- AFTER OnEnable returns), so we flip our own flag.
local active = false

-- forward refs (the idle-fade driver in section 6 fades the sidebar, which is
-- built in section 9; the bg panel + top fade are children of the chat frame so
-- they fade automatically when the chat frame's alpha changes)
local sidebarFrame

local ACCENT     = ns.COLORS.accent
local NUM        = _G.NUM_CHAT_WINDOWS or 10
local URL_LINK   = "vcuiurl"           -- our custom hyperlink type
local URL_HEX    = "ff3b9dff"          -- link colour (a calm blue)

-- Weak-keyed per-frame side table — keeps ALL our state OFF Blizzard's tables.
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

-- =========================================================
-- 1. Timestamps  (drive Blizzard's showTimestamps CVar; save/restore the user's
--    own value so turning the feature off gives them back what they had)
-- =========================================================
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

-- =========================================================
-- 2. Class-coloured names  (drive ChatTypeInfo[type].colorNameByClass — this is
--    exactly the flag Blizzard's own "Use class colors" checkbox sets, read by
--    GetColoredName which resolves the class from the sender GUID)
-- =========================================================
local CLASS_TYPES = {
    "SAY", "YELL", "EMOTE", "WHISPER", "WHISPER_INFORM",
    "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
    "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "CHANNEL",
}
local function applyClassColors()
    local on = (active and mod.db.classColors) and true or false
    -- The chatClassColorOverride CVar can FORCE class colouring off ("1"), which
    -- would make our per-type flag a silent no-op. When we want colours on, make
    -- sure the override defers to the per-type flag instead of forcing off.
    if on and GetCVar and GetCVar("chatClassColorOverride") == "1" then
        pcall(SetCVar, "chatClassColorOverride", "2")
    end
    if type(ChatTypeInfo) ~= "table" then return end
    for _, t in ipairs(CLASS_TYPES) do
        local info = ChatTypeInfo[t]
        if info then info.colorNameByClass = on end
    end
end

-- =========================================================
-- 3 + 4. Message filter: clickable URLs + short channel tags
-- =========================================================
local function linkifyURL(url)
    return string.format("|c%s|H%s:%s|h[%s]|h|r", URL_HEX, URL_LINK, url, url)
end

-- Wrap bare URLs in a clickable link. Cheap literal pre-check first (the 99%
-- fast path), and we skip any line that already carries a hyperlink so we never
-- touch item/spell/achievement links.
local function wrapURLs(text)
    if text:find("|H", 1, true) then return text end
    if not (text:find("://", 1, true) or text:find("www.", 1, true)) then return text end
    -- scheme://host/path first (this may itself add |H...|h around a www. inside)
    text = text:gsub("(%a[%w%+%.%-]*://[%w@:%%%._%+~#=/%-%?&]+)", linkifyURL)
    -- bare www.host/path that has NO scheme — guard on the preceding char so we
    -- never re-wrap a www. that sits inside the link we just made (".../www" or
    -- markup chars) or inside a longer domain (sub.www…)
    text = text:gsub("(.?)(www%.[%w@:%%%._%+~#=/%-%?&]+)", function(prev, u)
        if prev == "/" or prev == "." or prev == "|" or prev == ":" then return prev .. u end
        return prev .. linkifyURL(u)
    end)
    return text
end

-- One filter for every text-bearing event: URL linkify (msg) + channel shorten
-- (channelName, CHANNEL only). Returns the full rewritten arg list so trailing
-- args (GUID etc.) survive — dropping them would break class colour / menus.
local function msgFilter(self, event, msg, author, lang, channelName, ...)
    if not active then return false end
    local newMsg, newChannel = msg, channelName

    if mod.db.urls and type(msg) == "string" and not isSecret(msg) then
        newMsg = wrapURLs(msg)
    end

    if mod.db.shortenChannels and event == "CHAT_MSG_CHANNEL"
       and type(channelName) == "string" then
        local num = channelName:match("^(%d+)%.")   -- "1. General" → "1" (locale-safe)
        if num then newChannel = num end
    end

    if newMsg ~= msg or newChannel ~= channelName then
        return false, newMsg, author, lang, newChannel, ...
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
}

-- =========================================================
-- Shared read-only text popup (used by URL click + Copy chat)
-- =========================================================
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
        -- read-only: snap the text back if anything tries to change it
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

-- URL click handler (taint-safe post-hook; any |H...|h click routes here)
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

-- =========================================================
-- 5. Tab styling: flat dark tab background + accent underline on the active tab.
--    Textures are stripped but the GLOW frame is kept (new-message alert flash).
-- =========================================================
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
    -- restoring Blizzard's stripped tab textures isn't reliable; a /reload brings
    -- them back. We just hide our additions so the feature reads as "off".
end

local function updateTabs()
    if not (active and mod.db.tabStyle) then
        for i = 1, NUM do unstyleOneTab(i) end
        if underline then underline:Hide() end
        return
    end
    for i = 1, NUM do
        local cf = _G["ChatFrame" .. i]
        if cf and cf:IsShown() then styleOneTab(i) end
    end
    -- accent underline under the active tab (lives on UIParent, never a child of
    -- the protected tab — only anchored to it)
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
    -- restyle after the dock changes the selected window (deferred so we run
    -- OUTSIDE the secure chain that opens temporary windows)
    if _G.FCFDock_SelectWindow then
        hooksecurefunc("FCFDock_SelectWindow", function()
            if C_Timer and C_Timer.After then C_Timer.After(0, updateTabs) else updateTabs() end
        end)
    end
    if _G.FCF_Close then
        hooksecurefunc("FCF_Close", function()
            if C_Timer and C_Timer.After then C_Timer.After(0, updateTabs) else updateTabs() end
        end)
    end
end

-- =========================================================
-- 6. Idle fade: one lerp driver dims the whole chat after a delay; any new
--    message / hover / typing wakes it. No chat-frame OnEvent hooks (those taint
--    the C dispatcher) — a standalone event frame + a hover overlay + edit-box
--    focus hooks drive it.
-- =========================================================
local fadeDriver = CreateFrame("Frame")
fadeDriver:Hide()
local curAlpha, targetAlpha = 1, 1
local idleTimer
local engaged = 0       -- >0 while hovering or typing
local FADE_IN, FADE_OUT = 0.30, 1.5

local function applyFadeAlpha(a)
    eachChatFrame(function(cf, i)
        cf:SetAlpha(a)   -- cascades to our bg panel + top fade (children of cf)
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then eb:SetAlpha(a) end
    end)
    if _G.GeneralDockManager then GeneralDockManager:SetAlpha(a) end
    if underline then underline:SetAlpha(a) end
    if sidebarFrame then sidebarFrame:SetAlpha(a) end   -- parented to UIParent, fade it too
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

-- activity events (a standalone frame — never the chat frame's OnEvent).
-- MONSTER_* events are excluded on purpose (their sender can be a secret value).
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
    h:SetPoint("TOPLEFT", ChatFrame1, "TOPLEFT", -12, 34)     -- include the tab row
    h:SetPoint("BOTTOMRIGHT", ChatFrame1, "BOTTOMRIGHT", 14, -8)
    h:EnableMouse(false)            -- don't eat clicks (links still work)
    h:EnableMouseMotion(true)       -- but do see hover
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

-- =========================================================
-- 7. Copy button: read the active window's rendered lines on demand.
-- =========================================================
local function stripEscapes(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")   -- hyperlink → its display text
    s = s:gsub("|T.-|t", "")           -- inline textures
    s = s:gsub("|A.-|a", "")           -- atlas markup
    s = s:gsub("|K.-|k", "")           -- secret placeholders
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
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER"); fs:SetText("C"); fs:SetTextColor(ACCENT.r, ACCENT.g, ACCENT.b)
    b:SetScript("OnEnter", function()
        fs:SetTextColor(1, 1, 1)
        if GameTooltip then
            GameTooltip:SetOwner(b, "ANCHOR_LEFT")
            GameTooltip:SetText(L["Copy chat"])
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() fs:SetTextColor(ACCENT.r, ACCENT.g, ACCENT.b); if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function() showTextPopup(L["Copy chat"], readActiveChat()) end)
end

local function applyCopyButton()
    -- the sidebar already carries a copy icon, so suppress the standalone button
    -- whenever the sidebar is on
    if active and mod.db.copyButton and not mod.db.sidebar then
        ensureCopyButton()
        if copyButton then copyButton:Show() end
    elseif copyButton then
        copyButton:Hide()
    end
end

-- =========================================================
-- 8. History: a per-character ring buffer, captured by a standalone event frame
--    and re-shown once after a /reload (never by hooking the chat frame).
-- =========================================================
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

    -- near-tail dedup (same sender + body as the last entry)
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

-- =========================================================
-- 9. Chat panel: one dark background behind chat + input, a chrome-less
--    input line flush in it, the tab bar above it, a top-edge fade, and a slim
--    icon sidebar. All our own frames / cosmetic setters — taint-safe. A /reload
--    fully restores Blizzard's default positions when turned off.
-- =========================================================
local BG  = ns.COLORS.bg
local panelBuilt = false

local function chatFontSize(i)
    if FCF_GetChatWindowInfo then
        local ok, _, size = pcall(FCF_GetChatWindowInfo, i)
        if ok and type(size) == "number" and size > 0 then return size end
    end
    return 13
end

-- A dark panel behind each docked frame (so every tab shows the same panel).
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

-- Put the tab bar (dock) directly above the panel.
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
end

-- Top-edge fade: a vertical gradient over the top of the chat (opaque panel
-- colour at the very top → transparent below) so scrolled-up lines melt away.
local topFadeTex
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
    -- (bottom rgba) transparent  →  (top rgba) opaque panel colour
    UI.SetGradient(t, "VERTICAL", BG.r, BG.g, BG.b, 0, BG.r, BG.g, BG.b, BG.a or 0.9)
    topFadeTex = host
end

local function applyTopFade()
    if active and mod.db.topFade then
        ensureTopFade()
        if topFadeTex then topFadeTex:Show() end
    elseif topFadeTex then
        topFadeTex:Hide()
    end
end

-- Slim icon sidebar to the left of the chat: copy / settings / scroll-to-bottom.
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
        if tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(tip)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        ic:SetVertexColor(1, 1, 1, ICON_IDLE)
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function buildSidebar()
    if sidebarFrame or not _G.ChatFrame1 then return end
    local cf1 = _G.ChatFrame1
    local sb = CreateFrame("Frame", "VCUIChatSidebar", UIParent)
    sidebarFrame = sb
    sb:SetWidth(28)
    sb:SetPoint("TOPRIGHT", cf1, "TOPLEFT", -10, 4)
    sb:SetPoint("BOTTOMRIGHT", cf1, "BOTTOMLEFT", -10, -6)
    sb:SetFrameStrata(cf1:GetFrameStrata())
    sb:SetFrameLevel(cf1:GetFrameLevel() + 2)
    local bgt = sb:CreateTexture(nil, "BACKGROUND")
    bgt:SetAllPoints()
    bgt:SetColorTexture(BG.r, BG.g, BG.b, BG.a or 0.9)
    -- 1px divider on the chat side
    local div = sb:CreateTexture(nil, "OVERLAY")
    div:SetWidth(1)
    div:SetColorTexture(1, 1, 1, 0.06)
    div:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
    div:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)

    local copyBtn = makeSidebarIcon(sb, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
        L["Copy chat"], function() showTextPopup(L["Copy chat"], readActiveChat()) end)
    copyBtn:SetPoint("TOP", sb, "TOP", 0, -10)

    local gearBtn = makeSidebarIcon(sb, "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\gear.tga",
        L["Settings"], function()
            if ns.UI and ns.UI.ToggleMainFrame then
                if not (ns.UI.mainFrame and ns.UI.mainFrame:IsShown()) then ns.UI:ToggleMainFrame() end
                if ns.UI.ShowModulePage then ns.UI:ShowModulePage("chat") end
            end
        end)
    gearBtn:SetPoint("TOP", copyBtn, "BOTTOM", 0, -12)

    local scrollBtn = makeSidebarIcon(sb, "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\arrow_down.tga",
        L["Scroll to bottom"], function()
            local cf = (_G.FCFDock_GetSelectedWindow and _G.GENERAL_CHAT_DOCK
                        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)) or _G.ChatFrame1
            if cf and cf.ScrollToBottom then pcall(cf.ScrollToBottom, cf) end
        end)
    scrollBtn:SetPoint("BOTTOM", sb, "BOTTOM", 0, 10)
end

local function applySidebar()
    if active and mod.db.sidebar then
        buildSidebar()
        if sidebarFrame then sidebarFrame:Show() end
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
            -- styleEditBox is one-shot (panelBuilt); on an OFF→ON toggle the
            -- Blizzard input chrome was restored, so re-hide it here.
            for _, suf in ipairs(EB_CHROME) do
                local t = _G["ChatFrame" .. i .. "EditBox" .. suf]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
        end)
        positionDock()
    else
        eachChatFrame(function(cf, i)
            local d = fdata[cf]
            if d and d.bg then d.bg:Hide() end
            restoreEditBoxChrome(i)
        end)
    end
    applyTopFade()
    applySidebar()
end

-- Our font on the chat text, tabs and input (family only — keep each frame's
-- own size). Reversible to Blizzard's ChatFontNormal on disable.
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
        local tab = _G["ChatFrame" .. i .. "Tab"]
        local txt = tab and (tab.Text or _G["ChatFrame" .. i .. "TabText"])
        if txt and txt.SetFont then
            local _, tsize, tflags = txt:GetFont()
            if use then pcall(txt.SetFont, txt, UI.FONT_PATH, tsize or 12, tflags or "")
            elseif fallback then pcall(txt.SetFont, txt, fallback, tsize or 12, tflags or "") end
        end
    end)
end

-- =========================================================
-- Apply everything
-- =========================================================
local function applyAll()
    applyTimestamps()
    applyClassColors()
    applyPanel()
    applyFont()
    updateTabs()
    applyIdleFade()
    applyCopyButton()
    applyHistory()
end

-- =========================================================
-- Lifecycle
-- =========================================================
local _filtersInstalled = false
local _eventsWired = false

function mod:OnEnable()
    active = true

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

    if not _eventsWired then
        _eventsWired = true
        -- Blizzard can reset timestamp CVar / class-colour flags / tabs during
        -- login; re-assert after the world is in. Restore history once.
        ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
            applyTimestamps()
            applyClassColors()
            if C_Timer and C_Timer.After then
                -- the chat frames/dock settle a moment after login; build the
                -- panel + font then so anchors land on final positions
                C_Timer.After(0.5, function() applyPanel(); applyFont() end)
                C_Timer.After(1, updateTabs)
                C_Timer.After(2, function() applyTimestamps(); applyClassColors(); applyPanel(); applyFont() end)
                C_Timer.After(2, restoreHistory)
            else
                applyPanel(); applyFont(); updateTabs(); restoreHistory()
            end
        end)
    end

    applyAll()
end

function mod:OnDisable()
    active = false
    -- Filters / hooks stay installed but no-op via the `active` gate, so the
    -- module turns off without a /reload. Reverse the live-visible effects:
    applyTimestamps()    -- restores the user's own showTimestamps value
    applyClassColors()   -- clears colorNameByClass
    applyPanel()         -- hides bg panel / sidebar / top fade, restores input chrome
    applyFont()          -- back to Blizzard's chat font
    updateTabs()         -- hides our tab additions + underline
    applyIdleFade()      -- unregisters activity, restores full alpha
    applyCopyButton()    -- hides the copy button
    applyHistory()       -- stops capturing
    -- (input/dock POSITIONS revert on next /reload)
end

-- =========================================================
-- Options
-- =========================================================
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

    -- Timestamps
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

    -- Names & links
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
    table.insert(items, {
        type = "toggle", label = L["Short channel tags"],
        tooltip = L["Shows just the channel number, e.g. [1. General] becomes [1]."],
        get = function() return mod.db.shortenChannels end,
        set = function(_, v) mod.db.shortenChannels = v end,
    })

    -- Appearance
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
        tooltip = L["A slim bar left of the chat with copy, settings and scroll-to-bottom icons."],
        get = function() return mod.db.sidebar end,
        set = function(_, v) mod.db.sidebar = v; applySidebar(); applyCopyButton() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Use VuloUI font"],
        tooltip = L["Applies the VuloUI font to the chat text, tabs and input line."],
        get = function() return mod.db.font end,
        set = function(_, v) mod.db.font = v; applyFont() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Style chat tabs"],
        tooltip = L["Flat dark tab background with an accent underline on the active tab."],
        get = function() return mod.db.tabStyle end,
        set = function(_, v) mod.db.tabStyle = v; updateTabs() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Copy button (standalone)"],
        tooltip = L["A small copy button above the chat. Off by default since the sidebar already has a copy icon; turn the sidebar off to use this instead."],
        get = function() return mod.db.copyButton end,
        set = function(_, v) mod.db.copyButton = v; applyCopyButton() end,
    })

    -- Idle fade
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

    -- History
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
