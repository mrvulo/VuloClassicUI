-- VuloClassicUI / Modules / FriendList (UI Reskin)
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("friendlist", {
    name        = "Friends List",
    group       = "UI Reskin",
    description = "Class-coloured names, class icons, status dots, inline notes, faction tint and optional auto-accept.",
    defaults    = {
        enabled         = true,
        skinFrame       = true,
        skinCommunities = true,
        classColorNames = true,
        classIcons      = true,
        iconStyle       = "blizzard", -- blizzard | vuloepic | vulofantasy1/2 | circle | square
        statusDot       = true,
        showNotes       = true,
        factionAccent   = true,
        factionTint     = true,
        autoAccept      = false,
        autoAcceptGroup = false,
    },
})

local CLASS_CIRCLE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CLASS_SQUARE = "Interface\\WorldStateFrame\\Icons-Classes"
local CLASS_CREATE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

-- Sheets must be genuine 32-bit power-of-two TGA; the client picks its decoder by file extension.
-- Everything here ships and carries its licence in Media/ClassSheets/LICENSE.txt.
local SHEETS = {
    vulofantasy1 = "Interface\\AddOns\\VuloClassicUI\\Media\\ClassSheets\\vulofantasy1.tga",
    vulofantasy2 = "Interface\\AddOns\\VuloClassicUI\\Media\\ClassSheets\\vulofantasy2.tga",
    vuloepic     = "Interface\\AddOns\\VuloClassicUI\\Media\\ClassSheets\\vuloepic.tga",
}
-- Shared with the override button in UI/MainFrame: one grid, one place.
local SHEET_COORDS = ns.CLASS_SHEET_COORDS

local fileOKCache = {}
local function fileOK(path)
    local hit = fileOKCache[path]
    if hit ~= nil then return hit end
    local ok = true
    if GetFileIDFromPath then ok = GetFileIDFromPath(path) ~= nil end
    fileOKCache[path] = ok
    return ok
end

-- Battle.net presence often reports class names unlocalized, so seed English before the localized tables.
local ENGLISH_CLASS = {
    ["Warrior"] = "WARRIOR", ["Paladin"] = "PALADIN", ["Hunter"] = "HUNTER",
    ["Rogue"] = "ROGUE", ["Priest"] = "PRIEST", ["Shaman"] = "SHAMAN",
    ["Mage"] = "MAGE", ["Warlock"] = "WARLOCK", ["Druid"] = "DRUID",
    ["Death Knight"] = "DEATHKNIGHT", ["Monk"] = "MONK",
    ["Demon Hunter"] = "DEMONHUNTER", ["Evoker"] = "EVOKER",
}

local classToken = {}
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

local ORB = {
    online  = "Interface\\COMMON\\Indicator-Green",
    afk     = "Interface\\COMMON\\Indicator-Yellow",
    dnd     = "Interface\\COMMON\\Indicator-Red",
    offline = "Interface\\COMMON\\Indicator-Gray",
}

-- FrameXML values: DIVIDER=1, BNET=2, WOW=3
local FBTYPE_WOW  = _G.FRIENDS_BUTTON_TYPE_WOW  or 3
local FBTYPE_BNET = _G.FRIENDS_BUTTON_TYPE_BNET or 2

local function buttonFriendInfo(button)
    if button.buttonType == FBTYPE_WOW then
        local info = C_FriendList and C_FriendList.GetFriendInfoByIndex
            and C_FriendList.GetFriendInfoByIndex(button.id)
        if info then
            local status = info.dnd and "dnd" or info.afk and "afk"
                or (info.connected and "online" or "offline")
            local token   = info.connected and tokenFor(info.className) or nil
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

local function ensureClassIcon(button)
    if button._vcClassIcon then return button._vcClassIcon end
    -- anchor to the row button, not the name FontString: left of the name gets clipped by the scroll frame
    local t = button:CreateTexture(nil, "OVERLAY")
    t:Hide()
    button._vcClassIcon = t
    return t
end

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
        local x0 = 4 + (rowHeight(button) - 10) + 6
        -- TOPRIGHT/BOTTOMRIGHT, not "RIGHT": a RIGHT point pins the vertical center and stretches the FontString over the info line.
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

local function restyleButton(button)
    if not button or not button.name then return end
    -- mod.active, not mod._enabled: active is set BEFORE OnEnable, so the initial pass inside OnEnable styles
    local on = mod.active

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

    if on and mod.db.classColorNames and token then
        local c = classColor(token)
        if c then
            button.name:SetTextColor(c.r, c.g, c.b)
            -- BNet rows wrap "(CharName)" in inline |cff codes that SetTextColor cannot touch
            local txt = button.name:GetText()
            if txt and txt:find("|c", 1, true) then
                local hex = string.format("%02x%02x%02x",
                    c.r * 255 + 0.5, c.g * 255 + 0.5, c.b * 255 + 0.5)
                button.name:SetText((txt:gsub("|c[fF][fF]%x%x%x%x%x%x", "|cff" .. hex)))
            end
        end
    end

    -- factionName can arrive localized ("Allianz" on deDE); "Horde" is identical in German
    local alliance = (faction == "Alliance" or faction == "Allianz")
    if button.info then
        if on and mod.db.factionAccent then
            -- no 'and faction': a recycled row with nil faction must reset, not keep a stale tint
            if faction == "Horde" then button.info:SetTextColor(0.92, 0.36, 0.36)
            elseif alliance then button.info:SetTextColor(0.45, 0.60, 0.98)
            else button.info:SetTextColor(0.69, 0.69, 0.69) end
            button._vcInfoTinted = true
        elseif button._vcInfoTinted then
            button._vcInfoTinted = nil
            local gc = _G.GRAY_FONT_COLOR
            if gc then button.info:SetTextColor(gc.r, gc.g, gc.b)
            else button.info:SetTextColor(0.5, 0.5, 0.5) end
        end
        if on and mod.db.showNotes and note and note ~= "" then
            local base = button.info:GetText() or ""
            base = base:match("^(.-)%s*|cff8a8a8a") or base
            if base ~= "" then
                button.info:SetText(base .. "  |cff8a8a8a" .. note .. "|r")
            else
                button.info:SetText("|cff8a8a8a" .. note .. "|r")
            end
        end
    end

    local orb = button._vcOrb
    if on and mod.db.statusDot and status then
        orb = ensureOrb(button)
        orb:SetTexture(ORB[status] or ORB.offline)
        orb:ClearAllPoints()
        -- GetStringWidth reports UNtruncated text; clamp so the orb isn't parked past a truncated name
        local w = button.name:GetStringWidth() or 0
        local mw = button.name:GetWidth() or 0
        if mw > 0 and w > mw then w = mw end
        orb:SetPoint("LEFT", button.name, "LEFT", w + 4, 0)
        orb:SetAlpha(status == "offline" and 0.5 or 1)
        orb:Show()
    elseif orb then
        orb:Hide()
    end

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

    local style = mod.db.iconStyle
    if SHEETS[style] and not fileOK(SHEETS[style]) then style = "blizzard" end
    -- Styles that no longer exist. A saved profile keeps pointing at one long
    -- after the art is gone, and without this it would fall through to the
    -- generic branch below and quietly draw something else.
    if style == "vulo" or style == "vuloclasses" or style == "vulomodern"
        or style == "vulostyle" then
        style = "blizzard"
    end
    local icon = button._vcClassIcon
    if on and mod.db.classIcons then
        icon = ensureClassIcon(button)
        applyRowLayout(button, true)
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
        elseif token and not SHEETS[style]
           and (_G.CLASS_ICON_TCOORDS or {})[token] then
            icon:SetSize(slot, slot)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", button, "LEFT", 4, 0)
            icon:SetTexture(style == "square" and CLASS_SQUARE
                or style == "circle" and CLASS_CIRCLE or CLASS_CREATE)
            icon:SetTexCoord(unpack(_G.CLASS_ICON_TCOORDS[token]))
            icon:SetDesaturated(false); icon:SetAlpha(1)
        else
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

-- Texture strips are session-permanent, so turning the skin off needs a /reload.
local frameSkinned = false
local installHooks   -- fwd decl: defined in the lifecycle section, called by restyleAll

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

    for _, n in ipairs(CHROME) do hideRegion(_G[n]) end
    stripTextures(ff)
    if ff.Inset and ff.Inset.NineSlice then ff.Inset.NineSlice:SetAlpha(0) end
    local wi = _G.WhoFrameListInset
    if wi then
        if wi.Bg then hideRegion(wi.Bg) end
        if wi.NineSlice then wi.NineSlice:SetAlpha(0) end
    end

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

    local bn = _G.FriendsFrameBattlenetFrame
    if bn then
        stripTextures(bn)
        UI:StyleBackdrop(bn, { bg = { r = 0.07, g = 0.07, b = 0.1, a = 0.9 }, border = bc })
        if bn.Tag and UI.Font then UI.Font(bn.Tag, 12) end
    end

    local fontN, fontH, fontD = ns.UI:PanelButtonFonts("VCUI_FriendsFont")

    local function skinPanelButton(b)
        ns.UI:SkinPanelButton(b, { fonts = { fontN, fontH, fontD }, border = bc })
    end
    skinPanelButton(_G.FriendsFrameAddFriendButton)
    skinPanelButton(_G.FriendsFrameSendMessageButton)
    skinPanelButton(_G.FriendsFrameIgnorePlayerButton)
    skinPanelButton(_G.FriendsFrameUnsquelchButton)
    skinPanelButton(_G.WhoFrameWhoButton)
    skinPanelButton(_G.WhoFrameAddFriendButton)
    skinPanelButton(_G.WhoFrameGroupInviteButton)

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
                -- re-apply the font (tab switches swap FontObjects); keep 11px or deDE labels overflow
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

    local af = _G.AddFriendFrame
    if af then
        stripTextures(af)
        if af.Border then
            if af.Border.SetAlpha then af.Border:SetAlpha(0) end
            if af.Border.GetRegions then
                for _, r in ipairs({ af.Border:GetRegions() }) do hideRegion(r) end
            end
        end
        UI:StyleBackdrop(af, { bg = ns.COLORS and ns.COLORS.bg, border = bc })
        if UI.CreateShadow then UI:CreateShadow(af) end
        local afStrip = af:CreateTexture(nil, "ARTWORK")
        afStrip:SetPoint("TOPLEFT", af, "TOPLEFT", 0, 0)
        afStrip:SetPoint("TOPRIGHT", af, "TOPRIGHT", 0, 0)
        afStrip:SetHeight(2)
        if UI.SetGradient then
            UI.SetGradient(afStrip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)
        end
        for _, n in ipairs({ "AddFriendEntryFrameTitle", "AddFriendEntryFrameOrLabel",
                             "AddFriendEntryFrameLeftTitle", "AddFriendEntryFrameRightTitle",
                             "AddFriendEntryFrameLeftDescription", "AddFriendEntryFrameRightDescription" }) do
            local fs = _G[n]
            if fs and UI.Font then UI.Font(fs, n == "AddFriendEntryFrameTitle" and 13 or 11) end
        end
        local afTitle = _G.AddFriendEntryFrameTitle
        if afTitle then afTitle:SetTextColor(ac.r, ac.g, ac.b) end
        local eb = _G.AddFriendNameEditBox
        if eb then
            hideRegion(_G.AddFriendNameEditBoxLeft)
            hideRegion(_G.AddFriendNameEditBoxMiddle)
            hideRegion(_G.AddFriendNameEditBoxRight)
            local ebBg = CreateFrame("Frame", nil, eb, BackdropTemplateMixin and "BackdropTemplate")
            ebBg:SetPoint("TOPLEFT", eb, "TOPLEFT", -6, 2)
            ebBg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 2, -2)
            ebBg:SetFrameLevel(math.max(0, eb:GetFrameLevel() - 1))
            if ebBg.SetBackdrop then
                ebBg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                                   edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                ebBg:SetBackdropColor(0.07, 0.07, 0.1, 0.95)
                ebBg:SetBackdropBorderColor(bc.r, bc.g, bc.b, 1)
            end
        end
        skinPanelButton(_G.AddFriendEntryFrameAcceptButton)
        skinPanelButton(_G.AddFriendEntryFrameCancelButton)
        skinPanelButton(_G.AddFriendInfoFrameContinueButton)
    end
end

local function restyleAll()
    installHooks()
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

-- CommunitiesFrame is not load-on-demand here; its border is the explicit texture set (NineSlice inert).
local commSkinned = false

local function commStrip(region)
    if not region then return end
    for _, r in ipairs({ region:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then hideRegion(r) end
    end
end

-- No one-shot latch for the recolors: Blizzard's initializer re-sets Background/Selection on every refresh.
local function skinCommEntry(btn)
    if not btn or not btn.GetObjectType then return end
    local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
    -- the template anchors Background/Selection/Highlight beyond the button rect, so solid colors bleed
    local function pin(t)
        if not t then return end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -1)
        t:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 2)
    end
    if btn.Background then
        if not btn._vcuiPinned then pin(btn.Background) end
        btn.Background:SetTexture(nil)
        btn.Background:SetColorTexture(0.085, 0.085, 0.11, 0.9)
    end
    if btn.Selection then
        if not btn._vcuiPinned then pin(btn.Selection) end
        btn.Selection:SetTexture(nil)
        btn.Selection:SetColorTexture(ac.r, ac.g, ac.b, 0.22)
    end
    if btn.IconRing then btn.IconRing:SetAlpha(0) end
    if not btn._vcuiSkin then
        btn._vcuiSkin = true
        local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
        if hl then
            pin(hl)
            hl:SetTexture(nil)
            hl:SetColorTexture(1, 1, 1, 0.06)
            hl:SetBlendMode("BLEND")   -- template ships ADD; a solid tint needs BLEND
        end
        if btn.Name and ns.UI and ns.UI.Font then ns.UI.Font(btn.Name, 12) end
        btn._vcuiPinned = true
    end
end

local function skinCommMemberRow(row)
    if not row or not row.GetObjectType then return end
    local nt = row.GetNormalTexture and row:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    if not row._vcuiRowSkin then
        row._vcuiRowSkin = true
        local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
        local hl = row.GetHighlightTexture and row:GetHighlightTexture()
        if hl then
            hl:SetTexture(nil)
            hl:SetColorTexture(ac.r, ac.g, ac.b, 0.12)
            hl:SetBlendMode("BLEND")
        end
    end
end

-- ScrollUtil arg order differs per callback path; the registered owner is never a frame, so this is unambiguous.
local function acquiredFrameOf(a, b)
    if type(a) == "table" and a.GetObjectType then return a end
    if type(b) == "table" and b.GetObjectType then return b end
    return nil
end

local function skinCommunitiesFrame()
    if commSkinned or mod.db.skinCommunities == false or not mod.active then return end
    local cf, UI = _G.CommunitiesFrame, ns.UI
    if not (cf and UI and UI.StyleBackdrop) then return end
    commSkinned = true

    local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
    local bc = ns.COLORS and (ns.COLORS.borderDark or ns.COLORS.border) or { r = 0.15, g = 0.15, b = 0.18 }

    for _, k in ipairs({ "Bg", "TitleBg", "PortraitFrame", "TopLeftCorner",
        "TopRightCorner", "TopBorder", "TopTileStreaks", "BotLeftCorner",
        "BotRightCorner", "BottomBorder", "LeftBorder", "RightBorder",
        "portrait" }) do
        hideRegion(cf[k])
    end
    hideRegion(_G.CommunitiesFrameBtnCornerLeft)
    hideRegion(_G.CommunitiesFrameBtnCornerRight)
    hideRegion(_G.CommunitiesFrameButtonBottomBorder)
    if cf.NineSlice then cf.NineSlice:SetAlpha(0) end
    if cf.PortraitContainer then commStrip(cf.PortraitContainer) end
    if cf.Inset then
        if cf.Inset.Bg then hideRegion(cf.Inset.Bg) end
        if cf.Inset.NineSlice then cf.Inset.NineSlice:SetAlpha(0) end
    end

    UI:StyleBackdrop(cf, { bg = ns.COLORS and ns.COLORS.bg, border = bc })
    if UI.CreateShadow then UI:CreateShadow(cf) end
    local gstrip = cf:CreateTexture(nil, "ARTWORK")
    gstrip:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
    gstrip:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 0, 0)
    gstrip:SetHeight(2)
    if UI.SetGradient then
        UI.SetGradient(gstrip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)
    end
    if cf.TitleText then
        if UI.Font then UI.Font(cf.TitleText, 13) end
        cf.TitleText:SetTextColor(0.95, 0.95, 1)
    end
    local cb = cf.CloseButton
    if cb and not cb._vcuiSkin then
        cb._vcuiSkin = true
        commStrip(cb)
        local x = cb:CreateFontString(nil, "OVERLAY")
        if UI.Font then UI.Font(x, 16) else x:SetFontObject("GameFontNormalLarge") end
        x:SetPoint("CENTER", cb, "CENTER", 0, 0)
        x:SetText("×")
        x:SetTextColor(0.8, 0.8, 0.85)
        cb:HookScript("OnEnter", function() x:SetTextColor(ac.r, ac.g, ac.b) end)
        cb:HookScript("OnLeave", function() x:SetTextColor(0.8, 0.8, 0.85) end)
    end

    -- alpha, not Hide: it survives Blizzard's Show/SetPortraitToTexture calls
    if cf.PortraitOverlay then cf.PortraitOverlay:SetAlpha(0) end

    local mm = cf.MaximizeMinimizeFrame
    if mm then
        for _, key in ipairs({ "MaximizeButton", "MinimizeButton" }) do
            local b = mm[key]
            if b and not b._vcuiSkin then
                b._vcuiSkin = true
                commStrip(b)
                local g = b:CreateFontString(nil, "OVERLAY")
                if UI.Font then UI.Font(g, 14) else g:SetFontObject("GameFontNormal") end
                g:SetPoint("CENTER", b, "CENTER", 0, 0)
                g:SetText(key == "MaximizeButton" and "+" or "–")
                g:SetTextColor(0.8, 0.8, 0.85)
                b:HookScript("OnEnter", function() g:SetTextColor(ac.r, ac.g, ac.b) end)
                b:HookScript("OnLeave", function() g:SetTextColor(0.8, 0.8, 0.85) end)
            end
        end
    end

    local acb = cf.AddToChatButton
    if acb then
        local fs = (acb.GetFontString and acb:GetFontString()) or acb.Text
        if fs then
            if UI.Font then UI.Font(fs, 11) end
            fs:SetTextColor(0.9, 0.9, 0.95)
        end
    end
    local sd = cf.StreamDropdown
    if sd and sd.Text then
        if UI.Font then UI.Font(sd.Text, 12) end
        sd.Text:SetTextColor(0.9, 0.9, 0.95)
    end

    local cl = cf.CommunitiesList
    if cl then
        hideRegion(cl.Bg)
        hideRegion(cl.TopFiligree)
        hideRegion(cl.BottomFiligree)
        if cl.FilligreeOverlay then commStrip(cl.FilligreeOverlay) end
        if cl.InsetFrame then
            commStrip(cl.InsetFrame)
            if cl.InsetFrame.NineSlice then cl.InsetFrame.NineSlice:SetAlpha(0) end
        end
        local colbg = cl:CreateTexture(nil, "BACKGROUND")
        colbg:SetAllPoints(cl)
        colbg:SetColorTexture(0.05, 0.05, 0.065, 0.95)
        local div = cl:CreateTexture(nil, "BORDER")
        div:SetPoint("TOPRIGHT", cl, "TOPRIGHT", 0, 0)
        div:SetPoint("BOTTOMRIGHT", cl, "BOTTOMRIGHT", 0, 0)
        div:SetWidth(1)
        div:SetColorTexture(bc.r, bc.g, bc.b, 1)
        if cl.ScrollBox and _G.ScrollUtil then
            -- Initialized before Acquired: Blizzard's initializer repaints the entry after acquire
            local add = ScrollUtil.AddInitializedFrameCallback or ScrollUtil.AddAcquiredFrameCallback
            if add then
                pcall(add, cl.ScrollBox, function(a, b)
                    local f = acquiredFrameOf(a, b)
                    if f and mod.active and mod.db.skinCommunities ~= false then skinCommEntry(f) end
                end, mod, true)   -- owner MUST NOT be a frame (see acquiredFrameOf)
            end
        end
    end

    local ml = cf.MemberList
    if ml then
        if ml.WatermarkFrame then ml.WatermarkFrame:SetAlpha(0) end
        if ml.MemberCount then
            if UI.Font then UI.Font(ml.MemberCount, 11) end
            ml.MemberCount:SetTextColor(0.65, 0.65, 0.7)
        end
        for _, k in ipairs({ "InsetBorderTopLeft", "InsetBorderTopRight",
            "InsetBorderBottomLeft", "InsetBorderBottomRight",
            "InsetBorderTop", "InsetBorderBottom", "InsetBorderLeft",
            "InsetBorderRight", "InsetBorderTop2", "InsetBorderLeft2" }) do
            hideRegion(ml[k])
        end
        if ml.InsetFrame then
            commStrip(ml.InsetFrame)
            if ml.InsetFrame.NineSlice then ml.InsetFrame.NineSlice:SetAlpha(0) end
        end
        if ml.ScrollBar and ml.ScrollBar.Background then hideRegion(ml.ScrollBar.Background) end
        local cd = ml.ColumnDisplay
        if cd then
            hideRegion(cd.Background)
            hideRegion(cd.TopTileStreaks)
            local function skinHeaders()
                for _, child in ipairs({ cd:GetChildren() }) do
                    if child.IsObjectType and child:IsObjectType("Button") and not child._vcuiSkin then
                        child._vcuiSkin = true
                        local chl = child.GetHighlightTexture and child:GetHighlightTexture()
                        for _, r in ipairs({ child:GetRegions() }) do
                            if r.IsObjectType and r:IsObjectType("Texture") and r ~= chl then
                                hideRegion(r)
                            end
                        end
                        if chl then
                            chl:SetTexture(nil)
                            chl:SetColorTexture(1, 1, 1, 0.06)
                            chl:SetBlendMode("BLEND")
                            chl:ClearAllPoints()
                            chl:SetAllPoints(child)
                        end
                        local bg = child:CreateTexture(nil, "BACKGROUND")
                        bg:SetAllPoints(child)
                        bg:SetColorTexture(0.1, 0.1, 0.13, 0.9)
                        local ln = child:CreateTexture(nil, "BORDER")
                        ln:SetPoint("BOTTOMLEFT", child, "BOTTOMLEFT", 0, 0)
                        ln:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", 0, 0)
                        ln:SetHeight(1)
                        ln:SetColorTexture(ac.r, ac.g, ac.b, 0.4)
                    end
                end
            end
            skinHeaders()
            if type(cd.LayoutColumns) == "function" then
                hooksecurefunc(cd, "LayoutColumns", function()
                    if mod.active and mod.db.skinCommunities ~= false then skinHeaders() end
                end)
            end
        end
        if ml.ScrollBox and _G.ScrollUtil then
            local add = ScrollUtil.AddInitializedFrameCallback or ScrollUtil.AddAcquiredFrameCallback
            if add then
                pcall(add, ml.ScrollBox, function(a, b)
                    local f = acquiredFrameOf(a, b)
                    if f and mod.active and mod.db.skinCommunities ~= false then skinCommMemberRow(f) end
                end, mod, true)   -- owner MUST NOT be a frame
            end
        end
    end

    if cf.Chat and cf.Chat.InsetFrame then
        commStrip(cf.Chat.InsetFrame)
        if cf.Chat.InsetFrame.NineSlice then cf.Chat.InsetFrame.NineSlice:SetAlpha(0) end
    end
    local eb = cf.ChatEditBox
    if eb then
        hideRegion(eb.Left); hideRegion(eb.Right); hideRegion(eb.Mid)
        local ebg = eb:CreateTexture(nil, "BACKGROUND")
        ebg:SetPoint("TOPLEFT", eb, "TOPLEFT", 0, -4)
        ebg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 0, 4)
        ebg:SetColorTexture(0.04, 0.04, 0.055, 0.95)
        local line = eb:CreateTexture(nil, "BORDER")
        line:SetPoint("BOTTOMLEFT", eb, "BOTTOMLEFT", 0, 2)
        line:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 0, 2)
        line:SetHeight(1)
        line:SetColorTexture(0.3, 0.3, 0.35, 1)
    end

    local function skinSideTab(tab)
        if not tab or tab._vcuiSkin then return end
        tab._vcuiSkin = true
        local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
        local ck = tab.GetCheckedTexture and tab:GetCheckedTexture()
        for _, r in ipairs({ tab:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture")
               and r ~= tab.Icon and r ~= tab.IconOverlay and r ~= hl and r ~= ck then
                hideRegion(r)
            end
        end
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(tab)
        bg:SetColorTexture(0.09, 0.09, 0.115, 0.95)
        if hl then
            hl:SetTexture(nil); hl:SetColorTexture(1, 1, 1, 0.08)
            hl:SetBlendMode("BLEND")   -- template ships ADD
        end
        if ck then
            ck:SetTexture(nil); ck:SetColorTexture(ac.r, ac.g, ac.b, 0.3)
            ck:SetBlendMode("BLEND")
        end
    end
    skinSideTab(cf.ChatTab)
    skinSideTab(cf.RosterTab)
    skinSideTab(cf.GuildBenefitsTab)
    skinSideTab(cf.GuildInfoTab)

    local fontN, fontH, fontD = ns.UI:PanelButtonFonts("VCUI_FriendsFont")
    local function skinCommButton(b)
        ns.UI:SkinPanelButton(b, { fonts = { fontN, fontH, fontD }, border = bc })
    end
    skinCommButton(cf.InviteButton)
    skinCommButton(cf.GuildLogButton)
    if cf.CommunitiesControlFrame then
        skinCommButton(cf.CommunitiesControlFrame.GuildControlButton)
        skinCommButton(cf.CommunitiesControlFrame.GuildRecruitmentButton)
        skinCommButton(cf.CommunitiesControlFrame.CommunitiesSettingsButton)
    end
end

local function onCommAddonLoaded(_, addonName)
    if addonName == "Blizzard_Communities" then skinCommunitiesFrame() end
end

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

local function nameKey(n)
    if not n or n == "" then return nil end
    n = n:match("^([^-]+)") or n   -- drop "-Realm" suffix
    return n:lower()
end

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

local hooked = false
installHooks = function()
    if hooked then return end
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
    skinCommunitiesFrame()
    mod:RegisterEvent("ADDON_LOADED",                      onCommAddonLoaded)
    mod:RegisterEvent("FRIENDLIST_UPDATE",                 restyleAll)
    mod:RegisterEvent("BN_FRIEND_INFO_CHANGED",            restyleAll)
    mod:RegisterEvent("BN_FRIEND_INVITE_ADDED",            acceptInvites)
    mod:RegisterEvent("BN_FRIEND_INVITE_LIST_INITIALIZED", acceptInvites)
    mod:RegisterEvent("PARTY_INVITE_REQUEST",              onPartyInvite)
    restyleAll()
    acceptInvites()
end

function mod:OnDisable()
    -- hooksecurefunc can't be removed; ask Blizzard to redraw defaults instead
    if _G.FriendsList_Update then pcall(_G.FriendsList_Update) end
    restyleAll()
end

ns:RegisterSlash({ key = "FRIENDSTATE", commands = { "/friendstate" },
    desc = "Print what the friends list skin is doing.",
    hidden = true,
})
ns.Slash.FRIENDSTATE = function()
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

function mod:GetOptions()
    local function tgl(key, label, tooltip)
        return { type = "toggle", label = label, tooltip = tooltip,
            get = function() return mod.db[key] end,
            set = function(_, v)
                mod.db[key] = v
                if _G.FriendsList_Update then pcall(_G.FriendsList_Update) end
                restyleAll()
            end }
    end

    return {
        { type = "header", text = L["Display"] },
        tgl("skinFrame", L["Dark window skin"],
            L["Restyles the whole friends window dark with purple accents. Turning it off needs a /reload to restore Blizzard's frame."]),
        { type = "toggle", label = L["Dark guild & communities window"],
          tooltip = L["Restyles the guild and communities window to the same dark look. Turning it off needs a /reload."],
          get = function() return mod.db.skinCommunities ~= false end,
          set = function(_, v)
              mod.db.skinCommunities = v
              if v then skinCommunitiesFrame() end
          end },
        tgl("classColorNames", L["Class color names"],
            L["Colors each online friend's name by their class."]),
        tgl("classIcons", L["Show class icons"],
            L["Shows a class icon next to online WoW friends (in-game and Battle.net)."]),
        { type = "dropdown", label = L["Class icon style"], width = 240,
          values = (function()
              local v = { { value = "blizzard", text = L["Blizzard crests"] } }
              v[#v + 1] = { value = "vuloepic", text = L["Vulo Epic"] }
              v[#v + 1] = { value = "vulofantasy1", text = L["Vulo Fantasy 1"] }
              v[#v + 1] = { value = "vulofantasy2", text = L["Vulo Fantasy 2"] }
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
