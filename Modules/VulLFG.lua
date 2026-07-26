-- Group board: scans chat for group-forming messages and lists them per instance.
local _, ns = ...

local mod = ns:RegisterModule("vullfg", {
    name        = "Group Board",
    group       = "QoL",
    description = "Scans chat for people forming groups and lists them by Classic/TBC instance in a window (/vlfg or the minimap button).",
    defaults = {
        enabled    = true,
        window     = 20,     -- minutes a request stays listed
        minimap    = true,
        mmAngle    = 200,    -- degrees
        scanWorld  = true,
        scanGuild  = true,
        scanSay    = true,
        point      = nil,
    },
})

local floor, format, strlower, strfind = math.floor, string.format, string.lower, string.find
local ipairs, pairs = ipairs, pairs
local GetTime, GetActivity = GetTime, (C_LFGList and C_LFGList.GetActivityInfoTable)
local ACCENT = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }

local L = ns.L

-- id = LFG activity id (source of the localized name + level range); abbr = curated chat keywords.
local CAT_ORDER = ns.isEra and { "cd", "cr" } or { "cd", "cr", "bd", "br" }
local CAT_NAME = {}
ns.OnLocaleReady(function()
    CAT_NAME.cd = L["Classic Dungeons"]; CAT_NAME.cr = L["Classic Raids"]
    CAT_NAME.bd = L["Burning Crusade Dungeons"]; CAT_NAME.br = L["Burning Crusade Raids"]
end)

local DUNGEONS = {
    { key="RFC",  id=798, cat="cd", abbr="rfc ragefire chasm" },
    { key="WC",   id=796, cat="cd", abbr="wc wailing caverns" },
    { key="DM",   id=799, cat="cd", abbr="vc deadmines deadmine dm defias" },
    { key="SFK",  id=800, cat="cd", abbr="sfk shadowfang" },
    { key="STK",  id=802, cat="cd", abbr="stockade stockades stocks" },
    { key="BFD",  id=801, cat="cd", abbr="bfd blackfathom fathom" },
    { key="GNO",  id=803, cat="cd", abbr="gno gnomeregan gnome" },
    { key="RFK",  id=804, cat="cd", abbr="rfk razorfen kraul kraul" },
    { key="SM",   id=805, cat="cd", abbr="sm scarlet monastery graveyard library armory cathedral smg sml sma smc", zone=189 },
    { key="RFD",  id=806, cat="cd", abbr="rfd razorfen downs downs" },
    { key="ULD",  id=807, cat="cd", abbr="uld uldaman" },
    { key="ZF",   id=808, cat="cd", abbr="zf zulfarrak farrak" },
    { key="MAR",  id=809, cat="cd", abbr="mar maraudon maru" },
    { key="ST",   id=810, cat="cd", abbr="st sunken temple atalhakkar" },
    { key="BRD",  id=811, cat="cd", abbr="brd blackrock depths depths" },
    { key="DML",  id=813, cat="cd", abbr="dire diremaul dme dmw dmn tribute", zone=429 },
    { key="LBRS", id=812, cat="cd", abbr="lbrs lower spire" },
    { key="UBRS", id=837, cat="cd", abbr="ubrs upper spire" },
    { key="STR",  id=816, cat="cd", abbr="strat stratholme baron ud undead living" },
    { key="SCH",  id=797, cat="cd", abbr="sch scholo scholomance" },
    { key="ZG",   id=836, cat="cr", abbr="zg zulgurub gurub" },
    { key="ONY",  id=838, cat="cr", abbr="ony onyxia" },
    { key="MC",   id=839, cat="cr", abbr="mc molten core" },
    { key="BWL",  id=840, cat="cr", abbr="bwl blackwing lair" },
    { key="AQ20", id=842, cat="cr", abbr="aq20 ruins aqr" },
    { key="AQ40", id=843, cat="cr", abbr="aq40 temple aqt" },
    { key="NAXX", id=841, cat="cr", abbr="naxx naxxramas" },
    { key="RAMPS",id=913, cat="bd", abbr="ramps ramparts hellfire ramp" },
    { key="BF",   id=912, cat="bd", abbr="bf blood furnace bloodfurnace" },
    { key="SP",   id=909, cat="bd", abbr="sp slave pens slave" },
    { key="UB",   id=911, cat="bd", abbr="ub underbog bog" },
    { key="MT",   id=904, cat="bd", abbr="mt mana tombs manatombs" },
    { key="AC",   id=903, cat="bd", abbr="ac crypts crypt auchenai" },
    { key="SETH", id=905, cat="bd", abbr="seth sethekk" },
    { key="SL",   id=906, cat="bd", abbr="sl shadow labyrinth labs labyrinth" },
    { key="SV",   id=910, cat="bd", abbr="sv steamvault steam" },
    { key="MECH", id=916, cat="bd", abbr="mech mechanar" },
    { key="BOT",  id=918, cat="bd", abbr="bot botanica" },
    { key="ARC",  id=915, cat="bd", abbr="arc arcatraz" },
    { key="OHB",  id=908, cat="bd", abbr="ohb hillsbrad durnholde escape" },
    { key="BM",   id=907, cat="bd", abbr="bm morass blackmorass" },
    { key="SH",   id=914, cat="bd", abbr="sh shattered shatteredhalls" },
    { key="MGT",  id=917, cat="bd", abbr="mgt magisters terrace" },
    { key="KARA", id=844, cat="br", abbr="kara karazhan kz" },
    { key="GL",   id=846, cat="br", abbr="gruul gruuls gl" },
    { key="MAG",  id=845, cat="br", abbr="mag magtheridon magth" },
    { key="SSC",  id=848, cat="br", abbr="ssc serpentshrine vashj" },
    { key="EYE",  id=847, cat="br", abbr="tk tempest eye kael" },
    { key="HYJAL",id=849, cat="br", abbr="hyjal mh" },
    { key="BT",   id=850, cat="br", abbr="bt blacktemple illidan" },
    { key="SWP",  id=852, cat="br", abbr="swp sunwell plateau" },
    { key="ZA",   id=851, cat="br", abbr="za zulaman aman" },
}
local byKey = {}
for _, d in ipairs(DUNGEONS) do byKey[d.key] = d end

-- On Classic Era the TBC activity ids don't exist, so drop the bd/br entries.
local ACTIVE = {}
for _, d in ipairs(DUNGEONS) do
    if not (ns.isEra and (d.cat == "bd" or d.cat == "br")) then ACTIVE[#ACTIVE + 1] = d end
end

local SEARCH = "lfg lfm lf lf1m lf2m lf3m lf4m lf5m group grp need lf dps heal heals healer healers tank tanks dd boost run runs wts wtb"
    .. " suche sucht suchen gesucht such gruppe grp brauche heiler dd go"
local HEROIC = { h=true, hc=true, heroic=true, hero=true, ["hero"]=true, hcc=true }

-- word -> list of instance keys, since a word like "dm" can hit more than one
local tagList = {}
local searchWords = {}
local levelText = {}
local nameOf = {}
local built = false

local function addTag(word, key)
    if not word or #word < 2 then return end
    local t = tagList[word]
    if not t then t = {}; tagList[word] = t end
    for _, k in ipairs(t) do if k == key then return end end
    t[#t + 1] = key
end

local function buildTags()
    if built then return end
    for word in (SEARCH):gmatch("%S+") do searchWords[word] = true end
    for _, d in ipairs(ACTIVE) do
        local name, lo, hi
        if d.zone and GetRealZoneText then name = GetRealZoneText(d.zone) end
        if GetActivity then
            local info = GetActivity(d.id)
            if info then
                if not name or name == "" then
                    name = (info.shortName ~= "" and info.shortName) or info.fullName
                    if name then name = name:gsub("%s*%b()%s*$", "") end  -- strip "(Heroic)" etc.
                end
                lo, hi = info.minLevel, info.maxLevel
            end
        end
        name = (name and name ~= "" and name) or d.key
        nameOf[d.key] = name
        if lo and hi and lo > 0 then levelText[d.key] = (lo == hi) and format(" |cff808080(%d)|r", lo) or format(" |cff808080(%d-%d)|r", lo, hi) end
        for word in (d.abbr or ""):gmatch("%S+") do addTag(strlower(word), d.key) end
        for word in strlower(name):gmatch("[%a]+") do
            if #word >= 4 then addTag(word, d.key) end
        end
    end
    built = true
end

local function words(msg)
    local norm = strlower(msg):gsub("[%p%c]", " ")
    local out, seen = {}, {}
    for w in norm:gmatch("%S+") do if not seen[w] then seen[w] = true; out[#out + 1] = w end end
    return out
end

-- requests[key] = { [sender] = { msg, time, channel, heroic } }
local requests = {}

local function handleMessage(msg, sender, fromWorld)
    if not msg or not sender or sender == "" then return end
    if sender == (UnitName and UnitName("player")) then return end
    local hits, hasSearch, hasHeroic
    for _, w in ipairs(words(msg)) do
        if searchWords[w] then hasSearch = true end
        if HEROIC[w] then hasHeroic = true end
        local keys = tagList[w]
        if keys then
            hits = hits or {}
            for _, k in ipairs(keys) do hits[k] = true end
        end
    end
    if not hits then return end
    -- world/LFG channels count as group-forming by themselves; elsewhere require intent words
    if not fromWorld and not hasSearch then return end
    local now = GetTime()
    for k in pairs(hits) do
        requests[k] = requests[k] or {}
        requests[k][sender] = { msg = msg, time = now, channel = fromWorld, heroic = hasHeroic }
    end
    if mod._frame and mod._frame:IsShown() then mod._refreshSoon() end
end

local function prune()
    local cutoff = GetTime() - (mod.db.window or 20) * 60
    for k, byS in pairs(requests) do
        for s, r in pairs(byS) do if r.time < cutoff then byS[s] = nil end end
    end
end

local function timeAgo(t)
    local s = floor(GetTime() - t)
    if s < 60 then return L["now"] end
    return floor(s / 60) .. "m"
end

local rows = {}
local function getRow(parent, i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, parent)
    r:SetHeight(16)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.left:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.left:SetJustifyH("LEFT")
    r.left:SetWordWrap(false)
    if ns.UI and ns.UI.Font then ns.UI.Font(r.left, 12) end
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.right:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.right:SetJustifyH("RIGHT")
    if ns.UI and ns.UI.Font then ns.UI.Font(r.right, 11) end
    r.msg = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.msg:SetPoint("LEFT", r.left, "RIGHT", 8, 0)
    r.msg:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
    r.msg:SetJustifyH("LEFT")
    r.msg:SetWordWrap(false)
    if ns.UI and ns.UI.Font then ns.UI.Font(r.msg, 11) end
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
    r:SetScript("OnClick", function(self, button)
        if not self._sender then return end
        if button == "RightButton" then
            ns:ShowPopupMenu({
                { title = true, text = self._sender:gsub("%-.*", "") },
                { text = L["Whisper"], func = function() ChatFrame_SendTell(self._sender) end },
                { text = L["Invite"],  func = function() if InviteUnit then InviteUnit(self._sender) end end },
                { text = L["Who"],     func = function() if SendWho then SendWho('n-"' .. self._sender:gsub("%-.*", "") .. '"') end end },
            }, self)
        else
            ChatFrame_SendTell(self._sender)
        end
    end)
    r:SetScript("OnEnter", function(self)
        if not self._fullmsg or self._fullmsg == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._sender then
            GameTooltip:AddLine(self._sender:gsub("%-.*", ""), ACCENT.r, ACCENT.g, ACCENT.b)
        end
        GameTooltip:AddLine(self._fullmsg, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function refresh()
    local f = mod._frame
    if not f or not f:IsShown() then return end
    prune()
    local child = f.child
    local i, y, total = 0, -4, 0

    local function header(text)
        i = i + 1; local r = getRow(child, i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y); r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        r:SetHeight(18); r:Disable(); r._sender = nil; r._fullmsg = nil
        r.left:SetText("|cff" .. format("%02x%02x%02x", ACCENT.r*255, ACCENT.g*255, ACCENT.b*255) .. text .. "|r")
        r.right:SetText(""); r.msg:SetText("")
        r:Show(); y = y - 19
    end

    for _, cat in ipairs(CAT_ORDER) do
        local catPrinted = false
        for _, d in ipairs(ACTIVE) do
            if d.cat == cat and requests[d.key] then
                local list = {}
                for s, rq in pairs(requests[d.key]) do list[#list + 1] = { s = s, rq = rq } end
                if #list > 0 then
                    table.sort(list, function(a, b) return a.rq.time > b.rq.time end)
                    if not catPrinted then header(CAT_NAME[cat] or cat); catPrinted = true end
                    i = i + 1; local h = getRow(child, i)
                    h:ClearAllPoints(); h:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y); h:SetPoint("RIGHT", child, "RIGHT", 0, 0)
                    h:SetHeight(16); h:Disable(); h._sender = nil; h._fullmsg = nil
                    h.left:SetText(format("|cffffd200%s|r%s", nameOf[d.key] or d.key, levelText[d.key] or ""))
                    h.right:SetText("|cff888888" .. #list .. "|r"); h.msg:SetText("")
                    h:Show(); y = y - 16
                    for _, e in ipairs(list) do
                        i = i + 1; local r = getRow(child, i)
                        r:ClearAllPoints(); r:SetPoint("TOPLEFT", child, "TOPLEFT", 18, y); r:SetPoint("RIGHT", child, "RIGHT", -2, 0)
                        r:SetHeight(15); r:Enable(); r._sender = e.s; r._fullmsg = e.rq.msg
                        local nm = e.s:gsub("%-.*", "")
                        r.left:SetText((e.rq.heroic and "|cffff8800[" .. L["H"] .. "]|r " or "") .. nm)
                        r.right:SetText(timeAgo(e.rq.time))
                        r.msg:SetText(e.rq.msg)
                        r:Show(); y = y - 15
                        total = total + 1
                    end
                end
            end
        end
    end

    for j = i + 1, #rows do rows[j]:Hide() end
    if total == 0 then
        i = i + 1; local r = getRow(child, i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", child, "TOPLEFT", 8, -8); r:Disable(); r._sender = nil; r._fullmsg = nil
        r.left:SetText("|cff888888" .. L["No groups forming right now."] .. "|r"); r.right:SetText(""); r.msg:SetText(""); r:Show()
        y = y - 20
    end
    child:SetHeight(math.max(1, -y + 4))
    f.title:SetText(format("%s  |cff888888(%d)|r", L["Group Board"], total))
end

local refreshPending
function mod._refreshSoon()
    if refreshPending then return end
    refreshPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function() refreshPending = false; refresh() end)
    else refreshPending = false; refresh() end
end

local function buildWindow()
    if mod._frame then return end
    local f = CreateFrame("Frame", "VulLFGFrame", UIParent)
    f:SetSize(440, 420)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    -- one-time migration of the legacy point-anchor save to a CENTER offset
    if mod.db.point then
        f:ClearAllPoints()
        f:SetPoint(mod.db.point[1] or "CENTER", UIParent, mod.db.point[2] or "CENTER",
            mod.db.point[3] or 0, mod.db.point[4] or 0)
        local fx, fy = f:GetCenter()
        local px, py = UIParent:GetCenter()
        if fx and px then mod.db.x, mod.db.y = fx - px, fy - py end
        mod.db.point = nil
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
    f:Hide()
    ns:CreateMover(f, { key = "groupboard", label = "|cffffffffGROUP BOARD|r", db = mod.db, width = 440, height = 420,
        scalable = true, anchorable = true })
    ns.UI:StyleBackdrop(f, {
        bg     = { r = 0.06, g = 0.06, b = 0.08, a = 0.97 },
        border = ACCENT,
    })

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -8); f.title:SetText(L["Group Board"])
    if ns.UI and ns.UI.Font then ns.UI.Font(f.title, 14) end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -28)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 8)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, d)
        local cur, maxs = self:GetVerticalScroll(), self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maxs, cur - d * 28)))
    end)
    local child = CreateFrame("Frame", nil, scroll); child:SetSize(1, 1); scroll:SetScrollChild(child)
    child:SetWidth(420)
    f.child = child
    f:SetScript("OnSizeChanged", function(_, w) if child then child:SetWidth(math.max(1, (w or 440) - 20)) end end)
    f:SetScript("OnShow", refresh)
    mod._frame = f
end

function mod:Toggle()
    buildWindow()
    if mod._frame:IsShown() then mod._frame:Hide() else buildTags(); mod._frame:Show() end
end

local function buildMinimap()
    if mod._mm or not Minimap then return end
    local b = CreateFrame("Button", "VulLFGMinimapButton", Minimap)
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    local overlay = b:CreateTexture(nil, "OVERLAY"); overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); overlay:SetPoint("TOPLEFT")
    local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetSize(19, 19); icon:SetPoint("CENTER", -1, 1)
    icon:SetTexture("Interface\\LFGFrame\\BattlenetWorking0")
    icon:SetTexture("Interface\\GossipFrame\\BattleMasterGossipIcon")
    b.icon = icon
    local function place()
        local a = (mod.db.mmAngle or 200)
        local rad = a * math.pi / 180
        b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(rad), 80 * math.sin(rad))
    end
    place()
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function() b:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter(); local px, py = GetCursorPosition(); local s = Minimap:GetEffectiveScale()
        px, py = px / s, py / s
        mod.db.mmAngle = math.deg(math.atan2(py - my, px - mx)); place()
    end) end)
    b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() mod:Toggle() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText(L["Group Board"])
        GameTooltip:AddLine(L["/vlfg toggles the group board."], 0.7, 0.7, 0.7); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    mod._mm = b
end

local function isWorldChannel(cn)
    return strfind(cn, "lookingforgroup") or strfind(cn, "suchenachgruppe")
        or strfind(cn, "world") or strfind(cn, "welt")
        or strfind(cn, "general") or strfind(cn, "allgemein")
        or strfind(cn, "trade") or strfind(cn, "handel")
end

local function onChannel(_, text, sender, _, channel)
    if mod.db.scanWorld == false then return end
    local cn = channel and strlower(channel:gsub("[%s%d]", "")) or ""
    handleMessage(text, sender, isWorldChannel(cn) and true or false)
end
local function onGuild(_, text, sender) if mod.db.scanGuild ~= false then handleMessage(text, sender, false) end end
local function onSay(_, text, sender) if mod.db.scanSay ~= false then handleMessage(text, sender, false) end end

function mod:OnEnable()
    buildTags()
    ns:RegisterEvent("CHAT_MSG_CHANNEL", onChannel)
    ns:RegisterEvent("CHAT_MSG_GUILD", onGuild)
    ns:RegisterEvent("CHAT_MSG_SAY", onSay)
    ns:RegisterEvent("CHAT_MSG_YELL", onSay)
    if mod.db.minimap ~= false then buildMinimap() end
    if mod._mm then mod._mm:SetShown(mod.db.minimap ~= false) end
    if not mod._prune and C_Timer and C_Timer.NewTicker then
        mod._prune = C_Timer.NewTicker(30, function()
            if mod._frame and mod._frame:IsShown() then refresh() end
        end)
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("CHAT_MSG_CHANNEL", onChannel)
    ns:UnregisterEvent("CHAT_MSG_GUILD", onGuild)
    ns:UnregisterEvent("CHAT_MSG_SAY", onSay)
    ns:UnregisterEvent("CHAT_MSG_YELL", onSay)
    if mod._mm then mod._mm:Hide() end
    if mod._frame then mod._frame:Hide() end
end

SLASH_VULLFG1 = "/vlfg"
SLASH_VULLFG2 = "/lfgboard"
SlashCmdList.VULLFG = function() mod:Toggle() end

function mod:GetOptions()
    return {
        { type = "desc", text = "|cffaaaaaa" .. L["/vlfg toggles the group board."] .. "|r" },
        { type = "slider", label = L["Keep requests for (minutes)"], min = 5, max = 60, step = 5,
          get = function() return mod.db.window or 20 end, set = function(_, v) mod.db.window = v end },
        { type = "toggle", label = L["Show minimap button"],
          get = function() return mod.db.minimap end,
          set = function(_, v) mod.db.minimap = v; if v then buildMinimap() end; if mod._mm then mod._mm:SetShown(v) end end },
        { type = "toggle", label = L["Scan world / trade / LFG channels"], get = function() return mod.db.scanWorld end, set = function(_, v) mod.db.scanWorld = v end },
        { type = "toggle", label = L["Scan guild chat"], get = function() return mod.db.scanGuild end, set = function(_, v) mod.db.scanGuild = v end },
        { type = "toggle", label = L["Scan say / yell"],   get = function() return mod.db.scanSay ~= false end, set = function(_, v) mod.db.scanSay = v end },
    }
end
