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
        skinFrame       = true,       -- dark window skin (whole FriendsFrame)
        classColorNames = true,
        classIcons      = true,
        iconStyle       = "blizzard", -- "blizzard" | "vulo" | "circle" | "square"
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
-- the character-creation crest sheet — same 4x4 grid as CLASS_ICON_TCOORDS
local CLASS_CREATE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

-- Own class art (Media\classes); non-classic tokens included for completeness.
-- The files are GENUINE 32-bit TGA (power-of-two, square): the client picks
-- its image decoder by file extension, so PNG bytes in a .tga name never load.
local CLASS_ART_PATH = "Interface\\AddOns\\VuloClassicUI\\Media\\classes\\"
local CLASS_ART = {
    WARRIOR = "warrior.tga", PALADIN     = "paladin.tga", HUNTER = "hunter.tga",
    ROGUE   = "rogue.tga",   PRIEST      = "priest.tga",  SHAMAN = "shaman.tga",
    MAGE    = "mage.tga",    WARLOCK     = "warlock.tga", DRUID  = "druid.tga",
    DEATHKNIGHT = "dk.tga",  DEMONHUNTER = "dh.tga",      MONK   = "monk.tga",
    EVOKER  = "evoker.tga",
}

-- Optional LOCAL-ONLY sprite sheets (Media\Alle-Klassen — gitignored, never
-- distributed): 1024px sheets on an 8x8 grid of 128px cells. Their dropdown
-- entries appear only when the files exist on this installation; everyone
-- else silently falls back to the Blizzard crests.
local SHEET_PATH = "Interface\\AddOns\\VuloClassicUI\\Media\\Alle-Klassen\\"
local SHEETS = {
    vulomodern = SHEET_PATH .. "vulomodern.tga",
    vulostyle  = SHEET_PATH .. "vulostlye.tga",
}
local SHEET_COORDS = {
    WARRIOR     = { 0,     0.125, 0,     0.125 },
    MAGE        = { 0.125, 0.25,  0,     0.125 },
    ROGUE       = { 0.25,  0.375, 0,     0.125 },
    DRUID       = { 0.375, 0.5,   0,     0.125 },
    EVOKER      = { 0.5,   0.625, 0,     0.125 },
    HUNTER      = { 0,     0.125, 0.125, 0.25  },
    SHAMAN      = { 0.125, 0.25,  0.125, 0.25  },
    PRIEST      = { 0.25,  0.375, 0.125, 0.25  },
    WARLOCK     = { 0.375, 0.5,   0.125, 0.25  },
    PALADIN     = { 0,     0.125, 0.25,  0.375 },
    DEATHKNIGHT = { 0.125, 0.25,  0.25,  0.375 },
    MONK        = { 0.25,  0.375, 0.25,  0.375 },
    DEMONHUNTER = { 0.375, 0.5,   0.25,  0.375 },
}

-- does a texture file exist on THIS installation? (memoized; nil API -> yes)
local fileOKCache = {}
local function fileOK(path)
    local hit = fileOKCache[path]
    if hit ~= nil then return hit end
    local ok = true
    if GetFileIDFromPath then ok = GetFileIDFromPath(path) ~= nil end
    fileOKCache[path] = ok
    return ok
end

-- Battle.net presence often reports the class name UNLOCALIZED (English) on
-- this client, so the localized map alone misses every BNet friend. Seed with
-- the English names, then let the client's localized tables extend/override.
local ENGLISH_CLASS = {
    ["Warrior"] = "WARRIOR", ["Paladin"] = "PALADIN", ["Hunter"] = "HUNTER",
    ["Rogue"] = "ROGUE", ["Priest"] = "PRIEST", ["Shaman"] = "SHAMAN",
    ["Mage"] = "MAGE", ["Warlock"] = "WARLOCK", ["Druid"] = "DRUID",
    ["Death Knight"] = "DEATHKNIGHT", ["Monk"] = "MONK",
    ["Demon Hunter"] = "DEMONHUNTER", ["Evoker"] = "EVOKER",
}

local classToken = {}   -- class name (localized or English) -> token (MAGE, ...)
local function buildClassMap()
    if next(classToken) then return end
    for name, token in pairs(ENGLISH_CLASS) do classToken[name] = token end
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
-- real FrameXML values: DIVIDER=1, BNET=2, WOW=3
local FBTYPE_WOW  = _G.FRIENDS_BUTTON_TYPE_WOW  or 3
local FBTYPE_BNET = _G.FRIENDS_BUTTON_TYPE_BNET or 2

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
                -- classID first: locale-proof, works even when className is
                -- missing or unlocalized; name lookup is only the fallback
                if g.classID and g.classID > 0 and GetClassInfo then
                    local _, classFile = GetClassInfo(g.classID)
                    token = classFile
                end
                token   = token or tokenFor(g.className)
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
    -- anchored to the ROW BUTTON, not the name FontString: an anchor left of
    -- the name hangs out of the row and gets clipped by the scroll frame.
    -- Size/position are per-state (class art vs mirrored game icon).
    local t = button:CreateTexture(nil, "OVERLAY")
    t:Hide()
    button._vcClassIcon = t
    return t
end

-- =========================================================
-- Row layout: big square icon slot on the left, texts shifted right —
-- fully reversible so turning the option off restores Blizzard's layout.
-- =========================================================
local function snapPoints(r)
    local pts = {}
    for i = 1, r:GetNumPoints() do pts[#pts + 1] = { r:GetPoint(i) } end
    return pts
end

local function restorePoints(r, pts)
    if not pts or not pts[1] then return end
    r:ClearAllPoints()
    for _, p in ipairs(pts) do r:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
end

local function rowHeight(button)
    -- round: fractional heights under UI scale would put the art off-pixel
    local h = math.floor((button:GetHeight() or 0) + 0.5)
    if h < 20 then h = 34 end
    return h
end

local function applyRowLayout(button, styled)
    if (button._vcRowStyled or false) == (styled or false) then return end
    button._vcRowStyled = styled or false
    local name, info = button.name, button.info
    local st, gi = button.status, button.gameIcon
    if styled then
        local x0 = 4 + (rowHeight(button) - 10) + 6   -- right edge of the icon slot
        -- right bounds keep long text off the travelPass "+" button (24px +
        -- edge inset + gap = 28; the name gets 16 more so the status orb
        -- after it clears too). TOPRIGHT/BOTTOMRIGHT, NOT "RIGHT": a RIGHT
        -- point pins the vertical center and would stretch the FontString
        -- over the info line. No wrapping — bounded text must truncate.
        if name then
            button._vcNamePts = button._vcNamePts or snapPoints(name)
            name:ClearAllPoints()
            name:SetPoint("TOPLEFT", button, "TOPLEFT", x0, -4)
            name:SetPoint("TOPRIGHT", button, "TOPRIGHT", -44, -4)
            name:SetWordWrap(false)
        end
        if info then
            button._vcInfoPts = button._vcInfoPts or snapPoints(info)
            info:ClearAllPoints()
            info:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", x0, 5)
            info:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -28, 5)
            info:SetWordWrap(false)
        end
    else
        if name then restorePoints(name, button._vcNamePts); name:SetWordWrap(true) end
        if info then restorePoints(info, button._vcInfoPts); info:SetWordWrap(true) end
        if st then st:SetAlpha(1) end
        if gi then gi:SetAlpha(1) end
    end
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
    -- mod.active, not mod._enabled: the framework sets active BEFORE OnEnable
    -- runs, so the initial restyle pass inside OnEnable actually styles
    local on = mod.active

    -- non-friend rows (dividers, pending invites) keep Blizzard's layout —
    -- but under the dark skin their background must match the friend rows
    if button.buttonType ~= FBTYPE_WOW and button.buttonType ~= FBTYPE_BNET then
        if on and mod.db.skinFrame ~= false and button.background then
            button.background:SetColorTexture(1, 1, 1, 0.02)
        end
        applyRowLayout(button, false)
        if button._vcClassIcon then button._vcClassIcon:Hide() end
        if button._vcOrb then button._vcOrb:Hide() end
        if button._vcFactionBg then button._vcFactionBg:Hide() end
        return
    end

    local token, faction, status, note
    if on then token, faction, status, note = buttonFriendInfo(button) end

    -- name colour ------------------------------------------------------------
    if on and mod.db.classColorNames and token then
        local c = classColor(token)
        if c then
            button.name:SetTextColor(c.r, c.g, c.b)
            -- BNet rows wrap the "(CharName)" part in INLINE |cff codes which
            -- SetTextColor cannot touch — rewrite those to the class color
            local txt = button.name:GetText()
            if txt and txt:find("|c", 1, true) then
                local hex = string.format("%02x%02x%02x",
                    c.r * 255 + 0.5, c.g * 255 + 0.5, c.b * 255 + 0.5)
                button.name:SetText((txt:gsub("|c[fF][fF]%x%x%x%x%x%x", "|cff" .. hex)))
            end
        end
    end

    -- realm/zone line: faction text accent + inline note ---------------------
    -- factionName can arrive localized ("Allianz" on deDE); "Horde" is the
    -- same word in German
    local alliance = (faction == "Alliance" or faction == "Allianz")
    if button.info then
        if on and mod.db.factionAccent then
            -- no 'and faction': a recycled row whose faction is now nil must hit
            -- the else and reset, not keep a stale red/blue tint
            if faction == "Horde" then button.info:SetTextColor(0.92, 0.36, 0.36)
            elseif alliance then button.info:SetTextColor(0.45, 0.60, 0.98)
            else button.info:SetTextColor(0.69, 0.69, 0.69) end
            button._vcInfoTinted = true
        elseif button._vcInfoTinted then
            -- feature just turned off: hand the line back to Blizzard's gray
            -- (SetTextColor overrides survive Blizzard updates otherwise)
            button._vcInfoTinted = nil
            local gc = _G.GRAY_FONT_COLOR
            if gc then button.info:SetTextColor(gc.r, gc.g, gc.b)
            else button.info:SetTextColor(0.5, 0.5, 0.5) end
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
        -- clamp to the FontString's actual width: GetStringWidth() reports the
        -- UNtruncated text, which would park the orb past a truncated name
        local w = button.name:GetStringWidth() or 0
        local mw = button.name:GetWidth() or 0
        if mw > 0 and w > mw then w = mw end
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
        elseif alliance then
            bg:SetColorTexture(0.10, 0.22, 0.55, 0.16); bg:Show()
        else
            bg:Hide()
        end
    elseif bg then
        bg:Hide()
    end

    -- dark-skin row dressing: neutral row fill + accent hover/selection ------
    if on and mod.db.skinFrame ~= false then
        if not button._vcRowSkin then
            button._vcRowSkin = true
            if button.highlight and button.highlight.SetVertexColor then
                local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
                button.highlight:SetVertexColor(ac.r, ac.g, ac.b, 0.35)
            end
        end
        if button.background then
            -- every pass: Blizzard re-tints this per friend type (gold/blue/gray)
            button.background:SetColorTexture(1, 1, 1, 0.03)
        end
    end

    -- left icon slot (class art / mirrored game icon / offline) with the
    -- row texts shifted right of the slot ------------------------------------
    local style = mod.db.iconStyle
    -- local-only styles degrade to the crests when their files are absent
    -- (fresh installs, or a profile carried to another machine)
    if (SHEETS[style] and not fileOK(SHEETS[style]))
       or (style == "vulo" and not fileOK(CLASS_ART_PATH .. "mage.tga")) then
        style = "blizzard"
    end
    local icon = button._vcClassIcon
    if on and mod.db.classIcons then
        icon = ensureClassIcon(button)
        applyRowLayout(button, true)
        -- EVERY pass, not just on layout change: Blizzard re-sets the game
        -- icon's alpha (e.g. dimmed for app friends) on each of its updates,
        -- which would bring the right-side icon back after the first paint
        if button.status then button.status:SetAlpha(0) end
        if button.gameIcon then button.gameIcon:SetAlpha(0) end
        local slot = rowHeight(button) - 10
        local shown = true
        if token and SHEETS[style] and SHEET_COORDS[token] then
            icon:SetSize(slot, slot)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", button, "LEFT", 4, 0)
            icon:SetTexture(SHEETS[style])
            local c = SHEET_COORDS[token]
            icon:SetTexCoord(c[1], c[2], c[3], c[4])
            icon:SetDesaturated(false); icon:SetAlpha(1)
        elseif token and style == "vulo" and CLASS_ART[token] then
            icon:SetSize(slot, slot)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", button, "LEFT", 4, 0)
            icon:SetTexture(CLASS_ART_PATH .. CLASS_ART[token])
            icon:SetTexCoord(0, 1, 0, 1)   -- recycled rows may carry atlas coords
            icon:SetDesaturated(false); icon:SetAlpha(1)
        elseif token and style ~= "vulo" and not SHEETS[style]
           and (_G.CLASS_ICON_TCOORDS or {})[token] then
            icon:SetSize(slot, slot)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", button, "LEFT", 4, 0)
            icon:SetTexture(style == "square" and CLASS_SQUARE
                or style == "circle" and CLASS_CIRCLE or CLASS_CREATE)
            icon:SetTexCoord(unpack(_G.CLASS_ICON_TCOORDS[token]))
            icon:SetDesaturated(false); icon:SetAlpha(1)
        else
            -- no class known: mirror the game icon into the slot (BNet logo
            -- for "In App", the game's icon otherwise), grayed when offline
            local small = math.floor(slot * 0.75)
            icon:SetSize(small, small)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", button, "LEFT", 4 + math.floor((slot - small) / 2), 0)
            local gi = button.gameIcon
            local tex = status ~= "offline" and gi and gi:IsShown() and gi:GetTexture()
            if tex then
                icon:SetTexture(tex)
                icon:SetTexCoord(0, 1, 0, 1)
                icon:SetDesaturated(false); icon:SetAlpha(1)
            elseif button.buttonType == FBTYPE_BNET then
                icon:SetTexture("Interface\\FriendsFrame\\Battlenet-Battleneticon")
                icon:SetTexCoord(0, 1, 0, 1)
                icon:SetDesaturated(true); icon:SetAlpha(0.5)
            else
                shown = false
            end
        end
        icon:SetShown(shown)
    else
        if icon then icon:Hide() end
        applyRowLayout(button, false)
    end
end

-- =========================================================
-- Dark window skin for the whole FriendsFrame (covers all its tabs — the
-- subframes are setAllPoints children). Texture strips are session-permanent,
-- so turning the option off asks for a /reload. Element names verified
-- against the 2.5.5/1.15.8 client UI source.
-- =========================================================
local frameSkinned = false
local installHooks   -- fwd decl (lifecycle section) — restyleAll retries it

-- classic ButtonFrameTemplate chrome + FriendsFrame extras + scroll rail art
local CHROME = {
    "FriendsFrameBg", "FriendsFrameTitleBg", "FriendsFramePortrait",
    "FriendsFramePortraitFrame", "FriendsFrameIcon",
    "FriendsFrameTopRightCorner", "FriendsFrameTopLeftCorner",
    "FriendsFrameTopBorder", "FriendsFrameTopTileStreaks",
    "FriendsFrameBotLeftCorner", "FriendsFrameBotRightCorner",
    "FriendsFrameBottomBorder", "FriendsFrameLeftBorder", "FriendsFrameRightBorder",
    "FriendsFrameBtnCornerLeft", "FriendsFrameBtnCornerRight",
    "FriendsFrameButtonBottomBorder", "FriendsFrameInsetBg",
    "FriendsFrameFriendsScrollFrameTop", "FriendsFrameFriendsScrollFrameMiddle",
    "FriendsFrameFriendsScrollFrameBottom",
    "IgnoreListFrameTop", "IgnoreListFrameMiddle", "IgnoreListFrameBottom",
}

local function hideRegion(r)
    if not r then return end
    if r.SetTexture and r.IsObjectType and r:IsObjectType("Texture") then r:SetTexture(nil) end
    if r.SetAlpha then r:SetAlpha(0) end
end

local function skinFriendsFrame()
    if frameSkinned or mod.db.skinFrame == false or not mod.active then return end
    local ff, UI = _G.FriendsFrame, ns.UI
    if not (ff and UI and UI.StyleBackdrop) then return end
    frameSkinned = true

    local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
    local bc = ns.COLORS and (ns.COLORS.borderDark or ns.COLORS.border) or { r = 0.15, g = 0.15, b = 0.18 }

    local function stripTextures(region)
        for _, r in ipairs({ region:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then hideRegion(r) end
        end
    end

    -- chrome off: named pieces, then any unnamed leftovers on the frame itself
    for _, n in ipairs(CHROME) do hideRegion(_G[n]) end
    stripTextures(ff)
    if ff.Inset and ff.Inset.NineSlice then ff.Inset.NineSlice:SetAlpha(0) end
    local wi = _G.WhoFrameListInset
    if wi then
        if wi.Bg then hideRegion(wi.Bg) end
        if wi.NineSlice then wi.NineSlice:SetAlpha(0) end
    end

    -- our panel: dark fill, 1px border, soft shadow, accent hairline on top
    UI:StyleBackdrop(ff, { bg = ns.COLORS and ns.COLORS.bg, border = bc })
    if UI.CreateShadow then UI:CreateShadow(ff) end
    local gstrip = ff:CreateTexture(nil, "ARTWORK")
    gstrip:SetPoint("TOPLEFT", ff, "TOPLEFT", 0, 0)
    gstrip:SetPoint("TOPRIGHT", ff, "TOPRIGHT", 0, 0)
    gstrip:SetHeight(2)
    if UI.SetGradient then
        UI.SetGradient(gstrip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)
    end

    local title = _G.FriendsFrameTitleText
    if title then
        if UI.Font then UI.Font(title, 13) end
        title:SetTextColor(0.95, 0.95, 1)
    end

    -- close button -> flat ×
    local cb = _G.FriendsFrameCloseButton
    if cb then
        stripTextures(cb)
        local x = cb:CreateFontString(nil, "OVERLAY")
        if UI.Font then UI.Font(x, 16) else x:SetFontObject("GameFontNormalLarge") end
        x:SetPoint("CENTER", cb, "CENTER", 0, 0)
        x:SetText("×")
        x:SetTextColor(0.8, 0.8, 0.85)
        cb:HookScript("OnEnter", function() x:SetTextColor(ac.r, ac.g, ac.b) end)
        cb:HookScript("OnLeave", function() x:SetTextColor(0.8, 0.8, 0.85) end)
    end

    -- battletag pill -> dark inset
    local bn = _G.FriendsFrameBattlenetFrame
    if bn then
        stripTextures(bn)
        UI:StyleBackdrop(bn, { bg = { r = 0.07, g = 0.07, b = 0.1, a = 0.9 }, border = bc })
        if bn.Tag and UI.Font then UI.Font(bn.Tag, 12) end
    end

    -- panel buttons (friends + ignore + who tab)
    local fontN = _G.VCUI_FriendsFontNormal or CreateFont("VCUI_FriendsFontNormal")
    local fontH = _G.VCUI_FriendsFontHighlight or CreateFont("VCUI_FriendsFontHighlight")
    local fontD = _G.VCUI_FriendsFontDisabled or CreateFont("VCUI_FriendsFontDisabled")
    if UI.FONT_PATH then
        fontN:SetFont(UI.FONT_PATH, 12, "")
        fontH:SetFont(UI.FONT_PATH, 12, "")
        fontD:SetFont(UI.FONT_PATH, 12, "")
    end
    fontN:SetTextColor(0.9, 0.9, 0.95)
    fontH:SetTextColor(ac.r, ac.g, ac.b)
    fontD:SetTextColor(0.45, 0.45, 0.5)

    local function skinPanelButton(b)
        if not b or b._vcuiSkin then return end
        b._vcuiSkin = true
        stripTextures(b)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(b)
        bg:SetColorTexture(0.13, 0.13, 0.16, 1)
        local edges = {}
        for i = 1, 4 do
            local t = b:CreateTexture(nil, "BORDER")
            t:SetColorTexture(bc.r, bc.g, bc.b, 1)
            edges[i] = t
        end
        edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
        edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
        edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
        edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
        local function setEdges(c, a)
            for _, t in ipairs(edges) do t:SetColorTexture(c.r, c.g, c.b, a or 1) end
        end
        b:SetNormalFontObject(fontN)
        b:SetHighlightFontObject(fontH)
        b:SetDisabledFontObject(fontD)
        b:HookScript("OnEnter", function() bg:SetColorTexture(0.19, 0.19, 0.23, 1); setEdges(ac, 0.9) end)
        b:HookScript("OnLeave", function() bg:SetColorTexture(0.13, 0.13, 0.16, 1); setEdges(bc, 1) end)
    end
    skinPanelButton(_G.FriendsFrameAddFriendButton)
    skinPanelButton(_G.FriendsFrameSendMessageButton)
    skinPanelButton(_G.FriendsFrameIgnorePlayerButton)
    skinPanelButton(_G.FriendsFrameUnsquelchButton)
    skinPanelButton(_G.WhoFrameWhoButton)
    skinPanelButton(_G.WhoFrameAddFriendButton)
    skinPanelButton(_G.WhoFrameGroupInviteButton)

    -- tabs (top: Friends/Ignore, bottom: Friends/Who/Guild/Raid): flat plates
    -- around the label, accent text + underline for the active one
    local function skinTab(tab)
        if not tab or tab._vcuiSkin then return end
        tab._vcuiSkin = true
        local fs = tab.Text or (tab.GetName and _G[(tab:GetName() or "") .. "Text"])
            or (tab.GetFontString and tab:GetFontString())
        for _, r in ipairs({ tab:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then hideRegion(r) end
        end
        tab._vcText = fs
        if fs then
            local bg = tab:CreateTexture(nil, "BACKGROUND")
            bg:SetPoint("TOPLEFT", fs, "TOPLEFT", -8, 5)
            bg:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 8, -5)
            bg:SetColorTexture(0.10, 0.10, 0.13, 0.95)
            tab._vcBgTex = bg
            local ul = tab:CreateTexture(nil, "ARTWORK")
            ul:SetHeight(2)
            ul:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
            ul:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
            ul:SetColorTexture(ac.r, ac.g, ac.b, 0.9)
            tab._vcUnderline = ul
        end
    end

    local headerTabs = { _G.FriendsTabHeaderTab1, _G.FriendsTabHeaderTab2 }
    local frameTabs  = { _G.FriendsFrameTab1, _G.FriendsFrameTab2, _G.FriendsFrameTab3, _G.FriendsFrameTab4 }
    for _, t in ipairs(headerTabs) do skinTab(t) end
    for _, t in ipairs(frameTabs)  do skinTab(t) end

    local function paintTabs(owner, tabs)
        local sel = owner and owner.selectedTab or 1
        for i, tab in ipairs(tabs) do
            local fs = tab and tab._vcText
            if fs then
                -- re-apply the font too: tab switches swap Blizzard FontObjects.
                -- 11px, not larger: PanelTemplates sized the tab from its own
                -- font metrics, and wider text would overflow long deDE labels
                if UI.Font then UI.Font(fs, 11) end
                if i == sel then
                    fs:SetTextColor(ac.r, ac.g, ac.b)
                    if tab._vcUnderline then tab._vcUnderline:Show() end
                    if tab._vcBgTex then tab._vcBgTex:SetColorTexture(0.14, 0.14, 0.18, 0.95) end
                else
                    fs:SetTextColor(0.72, 0.72, 0.78)
                    if tab._vcUnderline then tab._vcUnderline:Hide() end
                    if tab._vcBgTex then tab._vcBgTex:SetColorTexture(0.10, 0.10, 0.13, 0.95) end
                end
            end
        end
    end
    local function repaintTabs()
        paintTabs(_G.FriendsTabHeader, headerTabs)
        paintTabs(_G.FriendsFrame, frameTabs)
    end
    if type(_G.PanelTemplates_SetTab) == "function" then
        hooksecurefunc("PanelTemplates_SetTab", function(owner)
            if owner == _G.FriendsTabHeader or owner == _G.FriendsFrame then repaintTabs() end
        end)
    end
    if type(_G.PanelTemplates_UpdateTabs) == "function" then
        hooksecurefunc("PanelTemplates_UpdateTabs", function(owner)
            if owner == _G.FriendsTabHeader or owner == _G.FriendsFrame then repaintTabs() end
        end)
    end
    repaintTabs()

    -- scrollbar: flat thumb + our arrow glyphs
    local thumb = _G.FriendsFrameFriendsScrollFrameScrollBarThumbTexture
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumb:SetVertexColor(0.28, 0.28, 0.34, 0.9)
        thumb:SetWidth(6)
    end
    local function skinArrow(b, dir)
        if not b or b._vcuiSkin then return end
        b._vcuiSkin = true
        stripTextures(b)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER", b, "CENTER", 0, 0)
        icon:SetSize(12, 12)
        icon:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\arrow_" .. dir .. ".tga")
        icon:SetVertexColor(0.6, 0.6, 0.68, 1)
        b:HookScript("OnEnter", function() icon:SetVertexColor(ac.r, ac.g, ac.b, 1) end)
        b:HookScript("OnLeave", function() icon:SetVertexColor(0.6, 0.6, 0.68, 1) end)
    end
    skinArrow(_G.FriendsFrameFriendsScrollFrameScrollBarScrollUpButton, "up")
    skinArrow(_G.FriendsFrameFriendsScrollFrameScrollBarScrollDownButton, "down")
end

-- After Blizzard rebuilds the list, restyle every row. The scroll container
-- differs by client vintage: HybridScroll (.buttons) or a ScrollBox.
local function restyleAll()
    installHooks()   -- retry path: cheap no-op once hooked
    skinFriendsFrame()
    if not _G.FriendsFrame or not _G.FriendsFrame:IsShown() then return end
    local scroll = _G.FriendsListFrameScrollFrame or _G.FriendsFrameFriendsScrollFrame
    if scroll and scroll.buttons then
        for _, b in ipairs(scroll.buttons) do restyleButton(b) end
        return
    end
    local box = _G.FriendsListFrame and _G.FriendsListFrame.ScrollBox
    if box and box.EnumerateFrames then
        for _, b in box:EnumerateFrames() do restyleButton(b) end
    end
end

-- =========================================================
-- Auto-accept Battle.net FRIEND invites
-- =========================================================
local function acceptInvites()
    if not mod.active or not mod.db.autoAccept then return end
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
    if not mod.active or not mod.db.autoAcceptGroup then return end
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
installHooks = function()
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
    -- one-shot: move profiles still on the old default ("circle") to the art icons
    if not self.db.iconStyleUpgraded then
        self.db.iconStyleUpgraded = true
        if self.db.iconStyle == "circle" then self.db.iconStyle = "vulo" end
    end
    -- one-shot: default moved again, "vulo" art -> Blizzard's crest sheet
    if not self.db.iconStyleUpgraded2 then
        self.db.iconStyleUpgraded2 = true
        if self.db.iconStyle == "vulo" then self.db.iconStyle = "blizzard" end
    end
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
-- Debug: /friendstate — dump what the client actually reports per friend,
-- so "no class icon" cases can be told apart (no character online vs the
-- data simply not being sent, e.g. friends on another WoW project).
-- =========================================================
_G.SLASH_VCUIFRIENDSTATE1 = "/friendstate"
_G.SlashCmdList["VCUIFRIENDSTATE"] = function()
    print("|cffffff00[VuloClassicUI Friend State]|r")
    local numBN = (BNGetNumFriends and BNGetNumFriends()) or 0
    for i = 1, numBN do
        local acc = C_BattleNet and C_BattleNet.GetFriendAccountInfo
            and C_BattleNet.GetFriendAccountInfo(i)
        local g = acc and acc.gameAccountInfo
        if g and g.isOnline then
            local token
            if g.classID and g.classID > 0 and GetClassInfo then
                token = select(2, GetClassInfo(g.classID))
            end
            token = token or tokenFor(g.className)
            print(string.format(
                "  BN %s: client=%s char=%s class=%s classID=%s project=%s faction=%s -> token=%s",
                tostring(acc.accountName), tostring(g.clientProgram),
                tostring(g.characterName), tostring(g.className),
                tostring(g.classID), tostring(g.wowProjectID),
                tostring(g.factionName), tostring(token)))
        end
    end
    local numWoW = (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends()) or 0
    for i = 1, numWoW do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected then
            print(string.format("  WoW %s: class=%s -> token=%s",
                tostring(info.name), tostring(info.className), tostring(tokenFor(info.className))))
        end
    end
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local function tgl(key, label, tooltip)
        return { type = "toggle", label = label, tooltip = tooltip,
            get = function() return mod.db[key] end,
            set = function(_, v)
                mod.db[key] = v
                -- ask Blizzard for a clean repaint first, so turning a
                -- feature OFF actually clears it from the open frame
                if _G.FriendsList_Update then pcall(_G.FriendsList_Update) end
                restyleAll()
            end }
    end

    return {
        { type = "header", text = L["Display"] },
        tgl("skinFrame", L["Dark window skin"],
            L["Restyles the whole friends window dark with purple accents. Turning it off needs a /reload to restore Blizzard's frame."]),
        tgl("classColorNames", L["Class color names"],
            L["Colors each online friend's name by their class."]),
        tgl("classIcons", L["Show class icons"],
            L["Shows a class icon next to online WoW friends (in-game and Battle.net)."]),
        { type = "dropdown", label = L["Class icon style"], width = 240,
          values = (function()
              -- local-only styles are offered only where their files exist
              local v = { { value = "blizzard", text = L["Blizzard crests"] } }
              if fileOK(SHEETS.vulomodern) then
                  v[#v + 1] = { value = "vulomodern", text = L["Vulo Modern"] }
              end
              if fileOK(SHEETS.vulostyle) then
                  v[#v + 1] = { value = "vulostyle", text = L["Vulo Style"] }
              end
              if fileOK(CLASS_ART_PATH .. "mage.tga") then
                  v[#v + 1] = { value = "vulo", text = L["Vulo icons"] }
              end
              v[#v + 1] = { value = "circle", text = L["Circles"] }
              v[#v + 1] = { value = "square", text = L["Squares"] }
              return v
          end)(),
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
