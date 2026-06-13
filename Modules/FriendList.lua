-- =========================================================
-- VuloClassicUI / Modules / FriendList (UI Reskin)
-- Polishes the Friends list:
--   - class-coloured names + a class icon per online WoW friend
--     (in-game and Battle.net)
--   - a status dot (green/yellow/red/grey) trailing the name
--   - the friend note shown inline under the name
--   - faction accent on the realm/zone line + a subtle row tint
--   - optional auto-accept of Battle.net friend invites
--   - optional auto-accept of group invites coming from a friend
-- Hooks the Blizzard per-button update -> no taint, fully reversible
-- (module off hides the extras and asks Blizzard to redraw defaults).
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("friendlist", {
    name        = "Friends List",
    group       = "UI Reskin",
    description = "Class-coloured names, class icons, status dots, inline notes, faction tint and optional auto-accept.",
    defaults    = {
        enabled         = true,
        classColorNames = true,
        classIcons      = true,
        iconStyle       = "circle",   -- "circle" | "square"
        statusDot       = true,
        showNotes       = true,
        factionAccent   = true,       -- tint the realm/zone TEXT
        factionTint     = true,       -- subtle row BACKGROUND tint
        autoAccept      = false,      -- Battle.net friend requests
        autoAcceptGroup = false,      -- party/raid invites from friends
    },
})

-- =========================================================
-- Class lookup
-- =========================================================
local CLASS_CIRCLE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CLASS_SQUARE = "Interface\\WorldStateFrame\\Icons-Classes"

local classToken = {}   -- localized class name -> token (MAGE, ...)
local function buildClassMap()
    if next(classToken) then return end
    for token, name in pairs(_G.LOCALIZED_CLASS_NAMES_MALE   or {}) do classToken[name] = token end
    for token, name in pairs(_G.LOCALIZED_CLASS_NAMES_FEMALE or {}) do classToken[name] = token end
end

local function tokenFor(className)
    if not className or className == "" then return nil end
    buildClassMap()
    return classToken[className]
end

local function classColor(token)
    return token and (_G.RAID_CLASS_COLORS or {})[token]
end

-- =========================================================
-- Status dot textures (built-in glossy orbs, present in every client)
-- =========================================================
local ORB = {
    online  = "Interface\\COMMON\\Indicator-Green",
    afk     = "Interface\\COMMON\\Indicator-Yellow",
    dnd     = "Interface\\COMMON\\Indicator-Red",
    offline = "Interface\\COMMON\\Indicator-Gray",
}

-- =========================================================
-- Friend info resolution
-- =========================================================
local FBTYPE_WOW  = _G.FRIENDS_BUTTON_TYPE_WOW  or 2
local FBTYPE_BNET = _G.FRIENDS_BUTTON_TYPE_BNET or 1

-- Resolve (classToken, factionGroup, status, note) for a button's friend.
-- status is one of "online" | "afk" | "dnd" | "offline".
local function buttonFriendInfo(button)
    if button.buttonType == FBTYPE_WOW then
        local info = C_FriendList and C_FriendList.GetFriendInfoByIndex
            and C_FriendList.GetFriendInfoByIndex(button.id)
        if info then
            local status = info.dnd and "dnd" or info.afk and "afk"
                or (info.connected and "online" or "offline")
            local token   = info.connected and tokenFor(info.className) or nil
            -- WoW (non-BNet) friends are necessarily your own faction
            local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
            return token, faction, status, info.notes
        end
    elseif button.buttonType == FBTYPE_BNET then
        local acc = C_BattleNet and C_BattleNet.GetFriendAccountInfo
            and C_BattleNet.GetFriendAccountInfo(button.id)
        if acc then
            local g       = acc.gameAccountInfo
            local online  = g and g.isOnline
            local status  = online and (acc.isDND and "dnd" or acc.isAFK and "afk" or "online") or "offline"
            local token, faction
            if online and (g.clientProgram == "WoW" or g.clientProgram == _G.BNET_CLIENT_WOW) then
                token   = tokenFor(g.className)
                faction = g.factionName
            end
            return token, faction, status, acc.note
        end
    end
    return nil
end

-- =========================================================
-- Per-button textures (created lazily, parked on the button)
-- =========================================================
local function ensureClassIcon(button)
    if button._vcClassIcon then return button._vcClassIcon end
    local t = button:CreateTexture(nil, "OVERLAY")
    t:SetSize(15, 15)
    if button.name then
        t:SetPoint("RIGHT", button.name, "LEFT", -2, 0)
    else
        t:SetPoint("LEFT", button, "LEFT", 30, 0)
    end
    t:Hide()
    button._vcClassIcon = t
    return t
end

local function ensureOrb(button)
    if button._vcOrb then return button._vcOrb end
    local t = button:CreateTexture(nil, "OVERLAY")
    t:SetSize(12, 12)
    t:Hide()
    button._vcOrb = t
    return t
end

local function ensureFactionBg(button)
    if button._vcFactionBg then return button._vcFactionBg end
    local t = button:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(button)
    t:Hide()
    button._vcFactionBg = t
    return t
end

-- =========================================================
-- Per-button restyle (cosmetic only -> never tainting)
-- =========================================================
local function restyleButton(button)
    if not button or not button.name then return end
    local on = mod._enabled

    local token, faction, status, note
    if on then token, faction, status, note = buttonFriendInfo(button) end

    -- name colour ------------------------------------------------------------
    if on and mod.db.classColorNames and token then
        local c = classColor(token)
        if c then button.name:SetTextColor(c.r, c.g, c.b) end
    end

    -- realm/zone line: faction text accent + inline note ---------------------
    if button.info then
        if on and mod.db.factionAccent and faction then
            if faction == "Horde" then button.info:SetTextColor(0.92, 0.36, 0.36)
            elseif faction == "Alliance" then button.info:SetTextColor(0.45, 0.60, 0.98)
            else button.info:SetTextColor(0.69, 0.69, 0.69) end
        end
        if on and mod.db.showNotes and note and note ~= "" then
            local base = button.info:GetText() or ""
            -- strip a previously-appended note so repeated restyles don't stack
            base = base:match("^(.-)%s*|cff8a8a8a") or base
            if base ~= "" then
                button.info:SetText(base .. "  |cff8a8a8a" .. note .. "|r")
            else
                button.info:SetText("|cff8a8a8a" .. note .. "|r")
            end
        end
    end

    -- status dot -------------------------------------------------------------
    local orb = button._vcOrb
    if on and mod.db.statusDot and status then
        orb = ensureOrb(button)
        orb:SetTexture(ORB[status] or ORB.offline)
        orb:ClearAllPoints()
        local w = button.name:GetStringWidth() or 0
        orb:SetPoint("LEFT", button.name, "LEFT", w + 4, 0)
        orb:SetAlpha(status == "offline" and 0.5 or 1)
        orb:Show()
    elseif orb then
        orb:Hide()
    end

    -- subtle faction row tint (online only, so offline rows stay clean) ------
    local bg = button._vcFactionBg
    if on and mod.db.factionTint and faction and status ~= "offline" then
        bg = ensureFactionBg(button)
        if faction == "Horde" then
            bg:SetColorTexture(0.60, 0.10, 0.10, 0.16); bg:Show()
        elseif faction == "Alliance" then
            bg:SetColorTexture(0.10, 0.22, 0.55, 0.16); bg:Show()
        else
            bg:Hide()
        end
    elseif bg then
        bg:Hide()
    end

    -- class icon -------------------------------------------------------------
    local icon = button._vcClassIcon
    if on and mod.db.classIcons and token and (_G.CLASS_ICON_TCOORDS or {})[token] then
        icon = ensureClassIcon(button)
        icon:SetTexture(mod.db.iconStyle == "square" and CLASS_SQUARE or CLASS_CIRCLE)
        icon:SetTexCoord(unpack(_G.CLASS_ICON_TCOORDS[token]))
        icon:Show()
    elseif icon then
        icon:Hide()
    end
end

-- After Blizzard rebuilds the list, restyle every row.
local function restyleAll()
    if not _G.FriendsFrame or not _G.FriendsFrame:IsShown() then return end
    local scroll = _G.FriendsListFrameScrollFrame
    local buttons = scroll and scroll.buttons
    if buttons then
        for _, b in ipairs(buttons) do restyleButton(b) end
    end
end

-- =========================================================
-- Auto-accept Battle.net FRIEND invites
-- =========================================================
local function acceptInvites()
    if not mod._enabled or not mod.db.autoAccept then return end
    local n = (BNGetNumFriendInvites and BNGetNumFriendInvites()) or 0
    for i = n, 1, -1 do
        local inviteID = BNGetFriendInviteInfo and BNGetFriendInviteInfo(i)
        if inviteID and BNAcceptFriendInvite then
            pcall(BNAcceptFriendInvite, inviteID)
        end
    end
end

-- =========================================================
-- Auto-accept GROUP invites from someone on the friends list
-- =========================================================
local function nameKey(n)
    if not n or n == "" then return nil end
    n = n:match("^([^-]+)") or n   -- drop "-Realm" suffix
    return n:lower()
end

-- Is `name` a WoW friend, or the current character of a BNet friend?
local function isFriendName(name)
    local key = nameKey(name)
    if not key then return false end

    local numWoW = (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends()) or 0
    for i = 1, numWoW do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name and nameKey(info.name) == key then return true end
    end

    if C_BattleNet and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends then
        local numBN = BNGetNumFriends() or 0
        for i = 1, numBN do
            local acc = C_BattleNet.GetFriendAccountInfo(i)
            local g = acc and acc.gameAccountInfo
            if g and g.isOnline and g.characterName and nameKey(g.characterName) == key then
                return true
            end
        end
    end
    return false
end

local function onPartyInvite(_, name)
    if not mod._enabled or not mod.db.autoAcceptGroup then return end
    if IsInGroup and IsInGroup() then return end
    if name and isFriendName(name) then
        if AcceptGroup then AcceptGroup() end
        if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
local hooked = false
local function installHooks()
    if hooked then return end
    -- Per-button hook is the cleanest; fall back to the list update.
    if type(_G.FriendsFrame_UpdateFriendButton) == "function" then
        hooksecurefunc("FriendsFrame_UpdateFriendButton", restyleButton)
        hooked = true
    elseif type(_G.FriendsFrame_UpdateFriends) == "function" then
        hooksecurefunc("FriendsFrame_UpdateFriends", restyleAll)
        hooked = true
    end
end

function mod:OnEnable()
    installHooks()
    ns:RegisterEvent("FRIENDLIST_UPDATE",                 restyleAll)
    ns:RegisterEvent("BN_FRIEND_INFO_CHANGED",            restyleAll)
    ns:RegisterEvent("BN_FRIEND_INVITE_ADDED",            acceptInvites)
    ns:RegisterEvent("BN_FRIEND_INVITE_LIST_INITIALIZED", acceptInvites)
    ns:RegisterEvent("PARTY_INVITE_REQUEST",              onPartyInvite)
    restyleAll()
    acceptInvites()
end

function mod:OnDisable()
    ns:UnregisterEvent("FRIENDLIST_UPDATE",                 restyleAll)
    ns:UnregisterEvent("BN_FRIEND_INFO_CHANGED",            restyleAll)
    ns:UnregisterEvent("BN_FRIEND_INVITE_ADDED",            acceptInvites)
    ns:UnregisterEvent("BN_FRIEND_INVITE_LIST_INITIALIZED", acceptInvites)
    ns:UnregisterEvent("PARTY_INVITE_REQUEST",              onPartyInvite)
    -- hooksecurefunc can't be removed; restyleButton no-ops while disabled,
    -- so ask Blizzard to redraw with default colours / hide our extras.
    if _G.FriendsList_Update then pcall(_G.FriendsList_Update) end
    restyleAll()
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local function tgl(key, label, tooltip)
        return { type = "toggle", label = label, tooltip = tooltip,
            get = function() return mod.db[key] end,
            set = function(_, v) mod.db[key] = v; restyleAll() end }
    end

    return {
        { type = "header", text = L["Display"] },
        tgl("classColorNames", L["Class color names"],
            L["Colors each online friend's name by their class."]),
        tgl("classIcons", L["Show class icons"],
            L["Shows a class icon next to online WoW friends (in-game and Battle.net)."]),
        { type = "dropdown", label = L["Class icon style"], width = 240,
          values = {
              { value = "circle", text = L["Circles"] },
              { value = "square", text = L["Squares"] },
          },
          get = function() return mod.db.iconStyle end,
          set = function(_, v) mod.db.iconStyle = v; restyleAll() end },
        tgl("statusDot", L["Show status dot"],
            L["A coloured dot after the name: green online, yellow away, red busy, grey offline."]),
        tgl("showNotes", L["Show friend notes"],
            L["Shows your saved note for the friend in grey under their name."]),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Faction"] },
        tgl("factionAccent", L["Faction accent on realm line"],
            L["Tints the realm/zone line red (Horde) or blue (Alliance)."]),
        tgl("factionTint", L["Faction row tint"],
            L["Adds a subtle red/blue background tint to each online friend's row."]),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Invites"] },
        tgl("autoAccept", L["Auto-accept Battle.net friend invites"],
            L["Automatically accepts incoming Battle.net friend requests."]),
        tgl("autoAcceptGroup", L["Auto-accept group invites from friends"],
            L["Automatically joins a group when the invite comes from someone on your friends list."]),
    }
end
