-- =========================================================
-- VuloClassicUI / Modules / FriendList (UI Reskin)
-- Polishes the Friends list: class-coloured names, a class icon per
-- online WoW friend (in-game + Battle.net), faction accent on the
-- realm/zone line, and optional auto-accept of Battle.net friend
-- invites. Hooks the Blizzard per-button update -> no taint, fully
-- reversible (module off restores the default colours on next update).
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("friendlist", {
    name        = "Friends List",
    group       = "UI Reskin",
    description = "Class-coloured friend names, class icons, faction accent and optional auto-accept for Battle.net invites.",
    defaults    = {
        enabled         = true,
        classColorNames = true,
        classIcons      = true,
        iconStyle       = "circle",   -- "circle" | "square"
        factionAccent   = true,
        autoAccept      = false,
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
    local c = token and (_G.RAID_CLASS_COLORS or {})[token]
    return c
end

-- =========================================================
-- Per-button restyle
-- =========================================================
local FBTYPE_WOW  = _G.FRIENDS_BUTTON_TYPE_WOW  or 2
local FBTYPE_BNET = _G.FRIENDS_BUTTON_TYPE_BNET or 1

-- Resolve (classToken, factionGroup) for the friend a button represents.
local function buttonClassInfo(button)
    if button.buttonType == FBTYPE_WOW then
        local info = C_FriendList and C_FriendList.GetFriendInfoByIndex
            and C_FriendList.GetFriendInfoByIndex(button.id)
        if info and info.connected then
            return tokenFor(info.className), nil
        end
    elseif button.buttonType == FBTYPE_BNET then
        local acc = C_BattleNet and C_BattleNet.GetFriendAccountInfo
            and C_BattleNet.GetFriendAccountInfo(button.id)
        local g = acc and acc.gameAccountInfo
        if g and g.isOnline and (g.clientProgram == "WoW" or g.clientProgram == _G.BNET_CLIENT_WOW) then
            return tokenFor(g.className), g.factionName
        end
    end
    return nil
end

local function ensureClassIcon(button)
    if button._vcClassIcon then return button._vcClassIcon end
    local t = button:CreateTexture(nil, "OVERLAY")
    t:SetSize(15, 15)
    -- left of the name, in the gap after the Blizzard game/status icon
    if button.name then
        t:SetPoint("RIGHT", button.name, "LEFT", -2, 0)
    else
        t:SetPoint("LEFT", button, "LEFT", 30, 0)
    end
    t:Hide()
    button._vcClassIcon = t
    return t
end

local function restyleButton(button)
    if not button or not button.name then return end

    local token, faction = nil, nil
    if mod._enabled then token, faction = buttonClassInfo(button) end

    -- name colour
    if mod._enabled and mod.db.classColorNames and token then
        local c = classColor(token)
        if c then button.name:SetTextColor(c.r, c.g, c.b) end
    end

    -- faction accent on the info (realm/zone) line
    if button.info then
        if mod._enabled and mod.db.factionAccent and faction then
            if faction == "Horde" then button.info:SetTextColor(0.85, 0.30, 0.30)
            elseif faction == "Alliance" then button.info:SetTextColor(0.40, 0.55, 0.95)
            else button.info:SetTextColor(0.69, 0.69, 0.69) end
        end
    end

    -- class icon
    local icon = button._vcClassIcon
    if mod._enabled and mod.db.classIcons and token and (_G.CLASS_ICON_TCOORDS or {})[token] then
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
-- Auto-accept Battle.net friend invites
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
    ns:RegisterEvent("FRIENDLIST_UPDATE",         restyleAll)
    ns:RegisterEvent("BN_FRIEND_INFO_CHANGED",    restyleAll)
    ns:RegisterEvent("BN_FRIEND_INVITE_ADDED",    acceptInvites)
    ns:RegisterEvent("BN_FRIEND_INVITE_LIST_INITIALIZED", acceptInvites)
    restyleAll()
    acceptInvites()
end

function mod:OnDisable()
    ns:UnregisterEvent("FRIENDLIST_UPDATE",         restyleAll)
    ns:UnregisterEvent("BN_FRIEND_INFO_CHANGED",    restyleAll)
    ns:UnregisterEvent("BN_FRIEND_INVITE_ADDED",    acceptInvites)
    ns:UnregisterEvent("BN_FRIEND_INVITE_LIST_INITIALIZED", acceptInvites)
    -- hooksecurefunc can't be removed; restyleButton no-ops while disabled,
    -- so ask Blizzard to redraw with default colours.
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
        tgl("factionAccent", L["Faction accent on realm line"],
            L["Tints the realm/zone line red (Horde) or blue (Alliance)."]),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Invites"] },
        tgl("autoAccept", L["Auto-accept Battle.net friend invites"],
            L["Automatically accepts incoming Battle.net friend requests."]),
    }
end
