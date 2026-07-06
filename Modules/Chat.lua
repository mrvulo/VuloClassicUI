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
    description = "Polishes Blizzard's chat: a dark panel with an icon sidebar, timestamps, class-coloured names, clickable links, dark tabs, idle fade and history that survives a /reload. Every part is optional.",
    defaults = {
        enabled         = true,
        timestamps      = true,
        timestampFormat = "%H:%M",
        classColors     = true,
        urls            = true,
        tabStyle        = true,
        bgPanel         = true,    -- dark panel behind chat + chrome-less input + tab bar above
        font            = true,    -- our font on chat, tabs and input
        topFade         = true,    -- top-edge fade so old lines melt into the panel
        sidebar         = true,    -- slim icon sidebar (copy / settings / scroll)
        friendsCounter  = true,    -- online-friends count at the top of the sidebar
        idleFade        = false,   -- opt-in: it dims the chat when idle
        idleFadeDelay   = 15,
        idleFadeOpacity = 35,      -- % minimum alpha when idle (0..90)
        copyButton      = false,   -- standalone copy button (the sidebar carries copy instead)
        history         = true,
        historyMax      = 150,
        scrollbackLines = 512,     -- SetMaxLines per window (Blizzard default 128)
        linkItemLevel   = true,    -- append (ilvl) to equipment links in chat
        tabFontSize     = 12,      -- ONE uniform size for every chat-tab label (8..16)
        chatFontSize    = 0,       -- chat message font override; 0 = keep each window's Blizzard size
        panelOpacity    = 78,      -- dark panel background alpha, % (0..100)
        indent          = true,    -- indented word wrap (hanging indent on wrapped lines)
    },
})

-- We can't use mod._enabled during the first OnEnable (the core sets it true only
-- AFTER OnEnable returns), so we flip our own flag.
local active = false

-- forward refs (the idle-fade driver in section 6 fades the sidebar, which is
-- built in section 9; the bg panel + top fade are children of the chat frame so
-- they fade automatically when the chat frame's alpha changes)
local sidebarFrame
local alignDockScroll   -- forward ref (defined in the panel section; updateTabs re-runs it on every dock relayout)
local createChatWindow  -- forward ref (defined after the apply fns; used by the sidebar + options)

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
    -- No leading-space pad: proportional spaces only nudge the first physical
    -- line and never line up with the wrapped continuation column, which is what
    -- made the indent look wrong. The clean hanging indent comes purely from
    -- SetIndentedWordWrap (see applyIndentWrap), so the time and wrap columns match.
    pcall(SetCVar, "showTimestamps", fmt .. " ")
end

-- Indented word wrap: long messages wrap with their continuation lines indented
-- under the message start, giving a clean hanging-indent text column (the
-- closest native match to a polished chat look). This is the whole indent
-- feature now -- there is no separate leading-space pad. SetIndentedWordWrap is
-- a ScrollingMessageFrame method present on these Classic clients; guarded just
-- in case.
local function applyIndentWrap()
    local on = (active and mod.db.indent) and true or false
    eachChatFrame(function(cf)
        if cf.SetIndentedWordWrap then pcall(cf.SetIndentedWordWrap, cf, on) end
    end)
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
-- 3. Message filter: clickable URLs
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

-- One filter for every text-bearing event: URL linkify on the message body.
-- Returns the full rewritten arg list so trailing args (GUID etc.) survive --
-- dropping them would break class colour / menus.
-- We ONLY ever rewrite the message body (arg 3). The channel name (arg 5) is
-- load-bearing for Blizzard's routing to dedicated single-channel windows
-- (e.g. a Trade-only tab) -- rewriting it to a bare number makes those windows
-- match nothing and show no text, so we never touch it. Channel-tag shortening
-- can't be done safely from a message filter; it would need the chat frame
-- replaced, which this enhancer deliberately does not do.
-- append the item level to EQUIPMENT links: [Sword] -> [Sword (45)]. The
-- added text sits inside the |h..|h display part, so the link keeps working
-- and inherits its quality colour. Cache-safe: uncached items stay untouched
-- (the GetItemInfo probe doubles as the async cache request). Quality-gated to
-- uncommon (green) and up, so grey/white trash doesn't clutter chat with a
-- pointless low item level.
local function addItemLevels(msg)
    if not msg:find("|Hitem:", 1, true) then return msg end
    return (msg:gsub("(|Hitem:[^|]+|h%[)(.-)(%]|h)", function(pre, name, post)
        local itemString = pre:match("|H(item:[^|]+)|h")
        if itemString and GetItemInfoInstant then
            local _, _, _, equipLoc, _, classID = GetItemInfoInstant(itemString)
            if (classID == 2 or classID == 4) and equipLoc and equipLoc ~= ""
               and equipLoc ~= "INVTYPE_BAG"
               -- a loot/GDKP addon may already have put an item level in
               -- brackets/parens on the link name — don't stack a second
               -- number on top of it
               and not name:find("[%[%(]%s*%d+%s*[%]%)]%s*$") then
                -- quality (pos 3) + item level (pos 4) from GetItemInfo; if the
                -- item isn't cached yet quality is nil and we skip (untouched)
                local quality, ilvl
                if GetItemInfo then
                    local _, _, q, il = GetItemInfo(itemString)
                    quality, ilvl = q, il
                end
                local lvl = ilvl or (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(itemString))
                if quality and quality >= 2 and lvl and lvl > 1 then
                    return pre .. name .. " (" .. lvl .. ")" .. post
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
    "CHAT_MSG_LOOT",   -- item links in loot lines get the (ilvl) suffix too
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

    -- One-time geometry fix: a uniform height, and zero out Blizzard's stray
    -- y-offset on docked tabs (3+) so every tab sits on the SAME line.
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

    -- Force ONE uniform label size + CENTER anchor on EVERY pass. This is the
    -- core alignment fix: Blizzard gives the permanent docked tabs (1-2) a
    -- larger font object than the created windows (3-4); a bigger CENTER-anchored
    -- glyph also drops lower, so the tabs read as different sizes AND heights.
    -- We never read the tab's own size back (that preserved the inequality) --
    -- we set the same configurable size for all of them. Family follows the font
    -- toggle; size is always equalized, so it works even with the font toggle off.
    -- Lives in the tab-styling path (not applyFont) so the two never fight.
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
    -- restoring Blizzard's stripped tab textures isn't reliable; a /reload brings
    -- them back. We just hide our additions so the feature reads as "off".
end

local function updateTabs()
    -- Blizzard relays the dock out on tab select/close/open (FCFDock_UpdateTabs),
    -- which re-drops the scroll frame ~5px and pushes the scroll-child tabs
    -- (whisper/trade) below the primary tabs again. updateTabs runs on all those
    -- events, so re-assert the alignment here. Panel-gated, independent of tab
    -- styling; idempotent (no-op once aligned).
    if active and mod.db.bgPanel and alignDockScroll then alignDockScroll() end
    if not (active and mod.db.tabStyle) then
        for i = 1, NUM do unstyleOneTab(i) end
        if underline then underline:Hide() end
        return
    end
    for i = 1, NUM do
        -- Gate on the TAB's visibility, not the chat frame's: docked tabs stay
        -- shown even when their content is hidden behind the active tab, so
        -- every docked tab gets styled + re-centred, not just the active one.
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and tab:IsShown() then styleOneTab(i) end
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
    -- Re-style/re-equalise newly opened temporary windows (whispers, etc.).
    -- This is the reference-proven taint-safe catch -- deliberately NOT hooking
    -- FCFTab_UpdateColors / FCFDock_UpdateTabs (those run inside the secure
    -- temp-window chain and taint it even when deferred).
    if _G.FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
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
    local ic = b:CreateTexture(nil, "OVERLAY")
    ic:SetPoint("CENTER"); ic:SetSize(14, 14)
    ic:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\copy.tga")
    ic:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.9)
    b:SetScript("OnEnter", function()
        ic:SetVertexColor(1, 1, 1, 1)
        if GameTooltip then
            GameTooltip:SetOwner(b, "ANCHOR_LEFT")
            GameTooltip:SetText(L["Copy chat"])
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() ic:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.9); if GameTooltip then GameTooltip:Hide() end end)
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
-- A translucent near-black panel for the chat. Deliberately NOT the addon's
-- opaque option-window colour (ns.COLORS.bg, ~0.96 alpha) -- a chat panel at
-- that opacity is a solid black wall once Blizzard's own chrome is stripped.
-- Lower alpha lets the game world show through, so it reads as a subtle dark
-- tint behind the text, the way a polished chat panel should.
local BG  = { r = 0.04, g = 0.045, b = 0.055, a = 0.78 }
local panelBuilt = false

local function chatFontSize(i)
    -- user override wins (one size for every window = uniform body text)
    local ovr = mod.db and mod.db.chatFontSize
    if ovr and ovr > 0 then return ovr end
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

-- Hidden parent for Blizzard widgets we want gone (reparenting beats Hide() —
-- Blizzard re-Shows some of them on update; a hidden parent keeps them gone).
local hiddenHost = CreateFrame("Frame")
hiddenHost:Hide()

-- Blizzard chat widgets we hide/restore as a set (named lists so de- and
-- re-Blizzard stay in sync).
local SCROLL_BTN_SUFFIX = { "BottomButton", "DownButton", "UpButton", "MinimizeButton" }
local SOCIAL_BUTTONS = {
    "QuickJoinToastButton", "ChatFrameMenuButton", "ChatFrameChannelButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
}

-- Strip Blizzard's own chat chrome so only our panel + sidebar show: the scroll
-- button cluster, scroll-to-bottom, minimize, and the frame's own background /
-- border textures. Our textures live on child frames, so cf:GetRegions() never
-- returns them. Taint-safe (insecure chat widgets) and per-frame one-shot.
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

    -- On some clients the real chat background lives on a child frame
    -- (cf.Background) rather than a direct region -- hide it too.
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

-- Hide Blizzard's social/menu/voice buttons that float at the chat's left.
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

-- Reverse de-Blizzard enough that turning the module OFF mid-session hands the
-- player back Blizzard's *functional* chat buttons (scroll / scroll-to-bottom /
-- minimize / social / menu / voice) without forcing a /reload. The stripped
-- frame textures and the moved dock + combat-log bar only return on /reload --
-- Blizzard's original texture paths / anchors aren't recorded, so we don't fake
-- them (a /reload restores them exactly).
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

-- The Combat Log's filter bar ("Meine Aktionen…") is its own frame with a
-- mismatched background — strip it and give it the panel colour so it blends in.
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
    -- Anchor the bar flush above ChatFrame2 at the panel's width so it reads as
    -- one piece with the panel instead of a narrower, offset band.
    local cf2 = _G.ChatFrame2
    if cf2 then
        pcall(qbf.ClearAllPoints, qbf)
        pcall(qbf.SetPoint, qbf, "BOTTOMLEFT", cf2, "TOPLEFT", -10, 3)
        pcall(qbf.SetPoint, qbf, "BOTTOMRIGHT", cf2, "TOPRIGHT", 6, 3)
        pcall(qbf.SetHeight, qbf, 24)
    end
    local bgt = qbf:CreateTexture(nil, "BACKGROUND")
    bgt:SetAllPoints()
    bgt:SetColorTexture(BG.r, BG.g, BG.b, BG.a or 0.9)
end

-- Blizzard anchors GeneralDockManagerScrollFrame a few px BELOW the dock
-- manager, so tabs in the scroll child (the created windows, e.g. Whisper/Trade)
-- sit lower than the primary tabs that anchor to the dock manager directly --
-- the tab-row misalignment. Pull the scroll frame's bottom flush with the dock
-- manager's bottom so EVERY tab (incl. future ones) shares one baseline. Done
-- deferred (positions must be settled to measure) and idempotent (the >0.5 gate
-- means a second pass, once aligned, does nothing).
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
    -- defer the scroll-frame alignment so GDM's new position is settled first
    if C_Timer and C_Timer.After then C_Timer.After(0, alignDockScroll) else alignDockScroll() end
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

-- Same look as makeSidebarIcon but draws a text glyph (e.g. "+") instead of a
-- texture -- we have no plus icon in Media, and a glyph tints cleanly.
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
        if tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(tip)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        fs:SetTextColor(1, 1, 1, ICON_IDLE)
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Online-friends counter (top of the sidebar): character friends + Battle.net.
-- Reads only cached counts; the server list is requested via ShowFriends() on
-- login + a slow ticker, and FRIENDLIST_UPDATE/BN_* events push updates here.
local function updateFriendsCount()
    local sb = sidebarFrame
    if not (sb and sb._friendsCount) then return end
    local wow = (C_FriendList and C_FriendList.GetNumOnlineFriends
                 and C_FriendList.GetNumOnlineFriends()) or 0
    local bn = 0
    if BNGetNumFriends then
        local ok, _, online = pcall(BNGetNumFriends)   -- (numFriends, numOnline)
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

-- Show/hide the counter per option and re-anchor the icon column below it.
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

-- Align the sidebar flush with the dark chat panel (same top + bottom edges, so
-- it sits level with the chat instead of poking up beside the tab row). Falls
-- back to the chat frame itself when the bg panel is off.
local function positionSidebar()
    local sb, cf1 = sidebarFrame, _G.ChatFrame1
    if not (sb and cf1) then return end
    local d = FD(cf1)
    sb:ClearAllPoints()
    if d.bg and active and mod.db.bgPanel then
        -- x = 0: flush against the panel's LEFT edge — the same horizontal spot
        -- as the old cf1-relative anchor (panel left == cf1 left - 10), so the
        -- sidebar never slides further left / off-screen. Only the vertical
        -- alignment comes from the panel.
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
    -- 1px divider on the chat side
    local div = sb:CreateTexture(nil, "OVERLAY")
    div:SetWidth(1)
    div:SetColorTexture(1, 1, 1, 0.06)
    div:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
    div:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)

    -- friends-online counter at the very top: icon + live count below it; click
    -- opens the friends list. Tooltip shows the character/Battle.net breakdown.
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
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(L["Friends online"])
            GameTooltip:AddLine(string.format("%s: %d", _G.FRIENDS or "Friends", sb._friendsWow or 0), 1, 1, 1)
            if BNGetNumFriends then
                GameTooltip:AddLine(string.format("Battle.net: %d", sb._friendsBN or 0), 1, 1, 1)
            end
            GameTooltip:Show()
        end
    end)
    -- keep the cached counts fresh even without list events: request the server
    -- friends list once a minute while the counter is visible (cheap, standard).
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
    -- copyBtn's TOP anchor is owned by applyFriendsCounter (below the counter
    -- when it's on, at the sidebar top when off)

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
    applyFriendsCounter()   -- anchors copyBtn + shows/hides the counter per option
end

local function applySidebar()
    if active and mod.db.sidebar then
        buildSidebar()
        if sidebarFrame then sidebarFrame:Show() end
        positionSidebar()   -- re-evaluate panel-vs-chat anchoring (bgPanel may have toggled)
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
            -- styleEditBox is one-shot (panelBuilt); on an OFF→ON toggle the
            -- Blizzard input chrome was restored, so re-hide it here.
            for _, suf in ipairs(EB_CHROME) do
                local t = _G["ChatFrame" .. i .. "EditBox" .. suf]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            deBlizzardChrome(cf, i)   -- self-guarded: hide native scroll/menu chrome + strip textures
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
        reBlizzardChrome()   -- give Blizzard's functional chat buttons back
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
        -- Tab labels are owned by styleOneTab (uniform size + centre), NOT here,
        -- so the two never fight over the tab font. A font-toggle change calls
        -- updateTabs() to refresh the tab family.
    end)
end

-- Push the configured panel opacity into BG.a and refresh every panel texture
-- that bakes it in (per-frame backgrounds, the shared chrome, the top fade).
local function applyPanelOpacity()
    BG.a = (mod.db.panelOpacity or 78) / 100
    eachChatFrame(function(cf)
        local d = fdata[cf]
        if d and d.bgTex then d.bgTex:SetColorTexture(BG.r, BG.g, BG.b, BG.a) end
    end)
    applyPanel()     -- rebuilds the shared panel / combat-log / sidebar chrome with new BG.a
    applyTopFade()   -- the vertical gradient bakes BG.a, so refresh it too
end

-- Create a brand-new Blizzard chat window (docked + selected). This is exactly
-- what Blizzard's own "Create New Window" does -- FCF_OpenNewWindow is insecure
-- chat code, so calling it from our button is taint-safe. The new frame's panel
-- background was pre-built for all NUM_CHAT_WINDOWS and shows via its OnShow
-- hook; we defer a re-style so its tab, font and dock alignment land too.
-- (Forward-declared near the top so the sidebar's button can reference it.)
function createChatWindow()
    if not FCF_OpenNewWindow then
        if ns.Print then ns:Print(L["This client can't create extra chat windows."]) end
        return
    end
    pcall(FCF_OpenNewWindow)
    local function restyle()
        -- a freshly initialised window re-creates its Blizzard button chrome, so
        -- clear the per-frame de-blizzard guard and let applyPanel strip it again
        -- (per-frame, idempotent). Then font + tab + dock alignment.
        for i = 1, NUM do
            local cf = _G["ChatFrame" .. i]
            local d = cf and fdata[cf]
            if d then d.deblizzed = nil end
        end
        applyPanel(); applyFont(); updateTabs()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, restyle) else restyle() end
end

-- =========================================================
-- Scrollback: raise Blizzard's 128-line cap per window. GetMaxLines guard is
-- LOAD-BEARING — SetMaxLines wipes the window's backlog, so it must only run
-- when the value actually changes (and before the history replay at login).
-- =========================================================
local function applyScrollback()
    local want = mod.db.scrollbackLines or 128
    if not active or want < 128 then want = 128 end   -- disable -> Blizzard default
    for i = 1, NUM do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.SetMaxLines and cf.GetMaxLines and cf:GetMaxLines() ~= want then
            cf:SetMaxLines(want)
        end
    end
end

-- =========================================================
-- Apply everything
-- =========================================================
local function applyAll()
    applyScrollback()   -- FIRST: a later SetMaxLines would wipe restored lines
    applyTimestamps()
    applyClassColors()
    if mod.db.panelOpacity then BG.a = mod.db.panelOpacity / 100 end  -- honour saved opacity
    applyPanel()
    applyFont()
    applyIndentWrap()
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
        -- friends-online counter: the server pushes FRIENDLIST_UPDATE after a
        -- ShowFriends() request and on list changes; BN_* cover Battle.net.
        -- ns:RegisterEvent pcall-guards unknown events, so missing BN_* on a
        -- client is silently skipped.
        for _, ev in ipairs({
            "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED",
            "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
            "BN_CONNECTED", "BN_DISCONNECTED",
        }) do
            ns:RegisterEvent(ev, function() if active then updateFriendsCount() end end)
        end
        ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
            applyTimestamps()
            applyClassColors()
            -- request the friends list once the world is in (BNet may connect a
            -- moment later; the BN_* events above catch up)
            if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
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
    -- module turns off without a /reload. Reverse the live-visible effects.
    -- Scrollback is deliberately NOT reverted here: SetMaxLines(128) would
    -- wipe every visible chat line on a mid-session toggle. The raised cap is
    -- harmless while disabled and reverts on the next /reload.
    applyTimestamps()    -- restores the user's own showTimestamps value
    applyClassColors()   -- clears colorNameByClass
    applyPanel()         -- hides bg panel / sidebar / top fade, restores input chrome
    applyFont()          -- back to Blizzard's chat font
    applyIndentWrap()    -- back to Blizzard's word wrap
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
