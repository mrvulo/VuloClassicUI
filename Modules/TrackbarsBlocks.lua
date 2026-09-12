-- VuloClassicUI / Modules / TrackbarsBlocks: die Block-Fabriken der Trackbars.
local _, ns = ...
local L   = ns.L
local UI  = ns.UI
local mod = ns.modules.trackbars

local function instKey(prefix, b, bar) return prefix .. ":" .. bar.id .. ":" .. b.id end

local function blockColor(b)
    if b.useAccent and ns.COLORS and ns.COLORS.accent then
        local a = ns.COLORS.accent
        return a.r, a.g, a.b
    end
    local c = b.color
    if c and c.r then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Textblock-Geruest: FontString + optionales Icon links, Herzschlag und/oder
-- Events, Relayout nur wenn sich die gemessene Breite aendert.
-- def = { icon=texturePfad|nil, events={...}|nil, interval=1|n|nil (Herzschlag
--         alle n Ticks; nil = kein Herzschlag), text=function(b) -> string,
--         onEnter/onLeave/onClick = function(self, b)|nil, fontScale=0.5 }
local function textBlockFontSize(bar, def)
    return math.floor((bar.thickness or 26) * (def.fontScale or 0.5) *
        ((bar.fontScale or 100) / 100) + 0.5)
end

local function MakeTextBlock(prefix, def)
    return function(b, slot, content, bar)
        local inst = { _key = instKey(prefix, b, bar) }
        local fs = content:CreateFontString(nil, "OVERLAY")
        UI.FontFor("trackbars", fs, textBlockFontSize(bar, def))
        fs:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        local icon
        if def.icon then
            icon = content:CreateTexture(nil, "ARTWORK")
            local isz = math.floor((bar.thickness or 26) * 0.62 + 0.5)
            icon:SetSize(isz, isz)
            icon:SetPoint("RIGHT", fs, "LEFT", -4, 0)
            icon:SetTexture(def.icon)
        end
        inst.fs, inst.icon = fs, icon
        function inst:Restyle()
            UI.FontFor("trackbars", fs, textBlockFontSize(bar, def))
            if icon then
                local isz = math.floor((bar.thickness or 26) * 0.62 + 0.5)
                icon:SetSize(isz, isz)
            end
        end
        local lastLen = -1
        function inst:Refresh()
            local r, g, bl = blockColor(b)
            fs:SetTextColor(r, g, bl)
            if icon then icon:SetVertexColor(r, g, bl) end
            fs:SetText(def.text(b) or "")
            local len = self:GetAutoLength()
            -- content bekommt die gemessene Groesse, sonst haengt der RIGHT-Anker
            -- des FontStrings an einem 0-breiten Frame und der Text steht schief
            content:SetSize(math.max(len, 1), bar.thickness or 26)
            if len ~= lastLen then lastLen = len; mod.RequestLayout(bar.id) end
        end
        function inst:GetAutoLength()
            local w = fs:GetStringWidth() or 0
            if w <= 0 then return 0 end
            if icon then w = w + (icon:GetWidth() or 0) + 4 end
            return math.ceil(w)
        end
        local evFrame
        function inst:Enable()
            if def.interval then
                local n, c = def.interval, 0
                mod.RegisterHeartbeat(self._key, function()
                    c = c + 1
                    if c >= n then c = 0; inst:Refresh() end
                end)
            end
            -- CAUTION if instances ever get re-Enabled: this guard keeps the
            -- frame but Disable() cleared its events, so a second Enable of
            -- the SAME instance would leave them unregistered. Today every
            -- Enable runs on a fresh instance (engine rebuilds on re-enable),
            -- so the frame is always new here.
            if def.events and not evFrame then
                evFrame = CreateFrame("Frame")
                for _, ev in ipairs(def.events) do pcall(evFrame.RegisterEvent, evFrame, ev) end
                evFrame:SetScript("OnEvent", function() inst:Refresh() end)
            end
            if def.onEnter or def.onClick then
                -- Maus auf dem SLOT, nicht der Leiste; Klicks nur wo noetig
                slot:EnableMouse(true)
                slot:SetScript("OnEnter", def.onEnter and function(s) def.onEnter(s, b) end or nil)
                slot:SetScript("OnLeave", def.onLeave or function() GameTooltip:Hide() end)
                if def.onClick then
                    slot:SetScript("OnMouseUp", function(s, btn) def.onClick(s, b, btn) end)
                end
            end
        end
        function inst:Disable()
            mod.UnregisterHeartbeat(self._key)
            if evFrame then evFrame:UnregisterAllEvents(); evFrame:SetScript("OnEvent", nil) end
            slot:EnableMouse(false)
        end
        return inst
    end
end

local function addType(key, labelKey, defaults, factory)
    mod.BLOCK_DEFAULTS[key] = defaults or {}
    table.insert(mod.BLOCK_TYPES, { key = key, label = function() return L[labelKey] end })
    mod.BlockFactories[key] = factory
end

-- Abstandshalter: feste Breite, kein Text
addType("spacer", "Spacer", { width = 20 }, function(b, slot, content, bar)
    local inst = {}
    function inst:Refresh() end
    function inst:GetAutoLength() return b.settings.width or 20 end
    function inst:Enable() end
    function inst:Disable() end
    return inst
end)

-- Uhr: Herzschlag 1s; lokale oder Serverzeit, 24h-Schalter
local function formatClock(h, m, hour24)
    if hour24 then return string.format("%02d:%02d", h, m) end
    local suf = (h >= 12) and " PM" or " AM"
    h = h % 12; if h == 0 then h = 12 end
    return string.format("%d:%02d%s", h, m, suf)
end

addType("clock", "Clock", { hour24 = true, source = "local" }, MakeTextBlock("clock", {
    interval = 1, fontScale = 0.55,
    text = function(b)
        local s = b.settings
        if s.source == "server" then
            local h, m = GetGameTime()
            return formatClock(h, m, s.hour24)
        end
        local t = date("*t")
        return formatClock(t.hour, t.min, s.hour24)
    end,
    onEnter = function(self, b)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Clock"])
        local h, m = GetGameTime()
        GameTooltip:AddDoubleLine(L["Server time"], string.format("%02d:%02d", h, m), 1,1,1, 1,1,1)
        GameTooltip:AddDoubleLine(L["Local time"], date("%H:%M"), 1,1,1, 1,1,1)
        GameTooltip:Show()
    end,
}))

-- FPS: alle 3 Herzschlaege
addType("fps", "FPS", {}, MakeTextBlock("fps", {
    interval = 3, fontScale = 0.5,
    text = function() return string.format("%d %s", math.floor(GetFramerate() + 0.5), L["fps"]) end,
}))

-- Latenz: 1s-Herzschlag, GetNetStats cached ~30s -> Text aendert sich selten,
-- Refresh ist trotzdem billig (ein format + SetText nur bei Breitenwechsel via MakeTextBlock)
addType("ms", "Latency", { world = true }, MakeTextBlock("ms", {
    interval = 1, fontScale = 0.5,
    text = function(b)
        local _, _, home, world = GetNetStats()
        if b.settings.world then return string.format("%d/%d %s", home or 0, world or 0, L["ms"]) end
        return string.format("%d %s", home or 0, L["ms"])
    end,
}))

-- Haltbarkeit: Event-getrieben, Minimum ueber alle Slots
local DUR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
addType("durability", "Durability", {}, MakeTextBlock("dur", {
    events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_ENTERING_WORLD" },
    fontScale = 0.5,
    text = function()
        local worst = 1
        for _, slot in ipairs(DUR_SLOTS) do
            local cur, max = GetInventoryItemDurability(slot)
            if cur and max and max > 0 then
                local p = cur / max
                if p < worst then worst = p end
            end
        end
        return string.format("%d%% %s", math.floor(worst * 100 + 0.5), L["Dur"])
    end,
    onEnter = function(self, b)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Durability"])
        for _, slot in ipairs(DUR_SLOTS) do
            local cur, max = GetInventoryItemDurability(slot)
            if cur and max and max > 0 then
                local link = GetInventoryItemLink("player", slot)
                local name = link and link:match("%[(.-)%]") or tostring(slot)
                local p = cur / max
                GameTooltip:AddDoubleLine(name, string.format("%d%%", math.floor(p * 100 + 0.5)),
                    1,1,1, 1 - (1 - p) * 0.8, p, 0.2)
            end
        end
        GameTooltip:Show()
    end,
}))

-- Gold: shared session ledger across all gold block instances and an
-- account-wide character store.
local goldLedger = { profit = 0, spent = 0, last = nil }
local function goldStore()
    VuloClassicUIDB.global.trackbarsGold = VuloClassicUIDB.global.trackbarsGold or {}
    return VuloClassicUIDB.global.trackbarsGold
end
local function goldCharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end
local function goldLedgerUpdate()
    local money = GetMoney() or 0
    if goldLedger.last then
        local d = money - goldLedger.last
        if d > 0 then goldLedger.profit = goldLedger.profit + d
        elseif d < 0 then goldLedger.spent = goldLedger.spent - d end
    end
    goldLedger.last = money
    local _, class = UnitClass("player")
    local store = goldStore()
    local key = goldCharKey()
    local entry = store[key]
    if entry then
        entry.money, entry.class = money, class
    else
        store[key] = { money = money, class = class }
    end
end

addType("gold", "Gold", { showBagSlots = false, shorten = false }, MakeTextBlock("gold", {
    events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "BAG_UPDATE" },
    fontScale = 0.5,
    text = function(b)
        goldLedgerUpdate()
        local money = GetMoney() or 0
        local txt
        if b.settings.shorten then
            txt = string.format("%d|cffffd700g|r", math.floor(money / 10000))
        else
            txt = GetCoinTextureString(money)
        end
        if b.settings.showBagSlots then
            local free = 0
            for bag = 0, 4 do free = free + (GetContainerNumFreeSlots(bag) or 0) end
            txt = txt .. string.format(" (%d)", free)
        end
        return txt
    end,
    onEnter = function(self, b)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Gold"])
        GameTooltip:AddDoubleLine(L["Session earned"], GetCoinTextureString(goldLedger.profit), 1,1,1, 1,1,1)
        GameTooltip:AddDoubleLine(L["Session spent"], GetCoinTextureString(goldLedger.spent), 1,1,1, 1,1,1)
        local net = goldLedger.profit - goldLedger.spent
        GameTooltip:AddDoubleLine(L["Session profit"], GetCoinTextureString(math.abs(net)),
            1,1,1, net >= 0 and 0.3 or 0.9, net >= 0 and 0.9 or 0.3, 0.3)
        GameTooltip:AddLine(" ")
        local rows, total = {}, 0
        for key, e in pairs(goldStore()) do
            table.insert(rows, { key = key, money = e.money or 0, class = e.class })
            total = total + (e.money or 0)
        end
        table.sort(rows, function(a, bb) return a.money > bb.money end)
        for i, r in ipairs(rows) do
            if i > 10 then GameTooltip:AddLine(string.format(L["+%d more"], #rows - 10), 0.6,0.6,0.6); break end
            local cc = r.class and RAID_CLASS_COLORS[r.class]
            GameTooltip:AddDoubleLine(r.key:match("^(.-)%-") or r.key, GetCoinTextureString(r.money),
                cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1, 1,1,1)
        end
        GameTooltip:AddDoubleLine(L["Total"], GetCoinTextureString(total), 1,0.82,0, 1,1,1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Left-Click: bags -- Ctrl+Right-Click: reset session"], 0.5, 0.7, 1)
        GameTooltip:Show()
    end,
    onClick = function(self, b, btn)
        if btn == "LeftButton" then
            if OpenAllBags then OpenAllBags() end
        elseif btn == "RightButton" and IsControlKeyDown() then
            goldLedger.profit, goldLedger.spent = 0, 0
            goldLedger.last = GetMoney()
        end
    end,
}))

-- Bag slots: standalone block for free-slot count without the gold suffix.
addType("bags", "Bag slots", {}, MakeTextBlock("bags", {
    events = { "BAG_UPDATE", "PLAYER_ENTERING_WORLD" },
    fontScale = 0.5,
    text = function()
        local free, total = 0, 0
        for bag = 0, 4 do
            free  = free  + (GetContainerNumFreeSlots(bag) or 0)
            total = total + (GetContainerNumSlots(bag) or 0)
        end
        return string.format("%d/%d %s", free, total, L["free"])
    end,
    onClick = function() if OpenAllBags then OpenAllBags() end end,
}))

-- Zone and coordinates block.
addType("zone", "Zone", { showCoords = true }, MakeTextBlock("zone", {
    interval = 1,
    events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
    fontScale = 0.5,
    text = function(b)
        local zone = GetMinimapZoneText() or GetRealZoneText() or ""
        if b.settings.showCoords and C_Map and C_Map.GetBestMapForUnit then
            local map = C_Map.GetBestMapForUnit("player")
            local pos = map and C_Map.GetPlayerMapPosition(map, "player")
            if pos then
                local x, y = pos:GetXY()
                return string.format("%s %.0f, %.0f", zone, x * 100, y * 100)
            end
        end
        return zone
    end,
    onClick = function() if ToggleWorldMap then ToggleWorldMap() end end,
}))

-- XP and reputation progress block. The text sits above a four-pixel bar,
-- with a second overlaid bar for rested XP.
addType("xprep", "XP / Reputation", { mode = "auto" }, function(b, slot, content, bar)
    local inst = { _key = instKey("xprep", b, bar) }
    local fs = content:CreateFontString(nil, "OVERLAY")
    UI.FontFor("trackbars", fs, math.floor((bar.thickness or 26) * 0.42 * ((bar.fontScale or 100) / 100) + 0.5))
    fs:SetPoint("TOP", content, "TOP", 0, -1)
    local sb = CreateFrame("StatusBar", nil, content)
    sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    sb:SetHeight(4)
    sb:SetPoint("TOP", fs, "BOTTOM", 0, -2)
    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(sb); track:SetColorTexture(1, 1, 1, 0.10)
    local rest = CreateFrame("StatusBar", nil, content)
    rest:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    rest:SetStatusBarColor(0.3, 0.3, 1, 0.5)
    rest:SetAllPoints(sb)
    rest:SetFrameLevel(sb:GetFrameLevel() - 1)
    local lastLen = -1

    function inst:Restyle()
        UI.FontFor("trackbars", fs, math.floor((bar.thickness or 26) * 0.42 * ((bar.fontScale or 100) / 100) + 0.5))
    end

    -- The TOC targets both 20505 and 38001; never hardcode max level to 70.
    local function maxLevel()
        return (GetMaxPlayerLevel and GetMaxPlayerLevel())
            or (MAX_PLAYER_LEVEL_TABLE and GetAccountExpansionLevel
                and MAX_PLAYER_LEVEL_TABLE[GetAccountExpansionLevel()])
            or 70
    end
    local function currentMode()
        local m = b.settings.mode
        if m == "xp" or m == "rep" then return m end
        if UnitLevel("player") >= maxLevel() then return "rep" end
        return "xp"
    end

    function inst:Refresh()
        local mode = currentMode()
        local a = ns.COLORS and ns.COLORS.accent or { r = 0.61, g = 0.42, b = 1 }
        if mode == "xp" then
            local cur, max = UnitXP("player"), UnitXPMax("player")
            if UnitLevel("player") >= maxLevel() then
                fs:SetText(L["Max level (Right-Click: reputation)"])
                fs:SetTextColor(0.6, 0.6, 0.6)
                sb:Hide(); rest:Hide()
            else
                fs:SetTextColor(blockColor(b))
                fs:SetFormattedText("%s: %d%%", L["XP"], math.floor(cur / math.max(max, 1) * 100 + 0.5))
                sb:SetMinMaxValues(0, max); sb:SetValue(cur)
                sb:SetStatusBarColor(a.r, a.g, a.b)
                local exh = GetXPExhaustion()
                rest:SetMinMaxValues(0, max)
                rest:SetValue(math.min(max, cur + (exh or 0)))
                sb:Show(); rest:SetShown(exh and exh > 0)
            end
        else
            local name, _, minV, maxV, value = GetWatchedFactionInfo()
            if not name then
                fs:SetText(L["No reputation tracked"])
                fs:SetTextColor(0.6, 0.6, 0.6)
                sb:Hide(); rest:Hide()
            else
                fs:SetTextColor(blockColor(b))
                fs:SetFormattedText("%s: %d%%", name,
                    math.floor((value - minV) / math.max(maxV - minV, 1) * 100 + 0.5))
                sb:SetMinMaxValues(0, maxV - minV); sb:SetValue(value - minV)
                sb:SetStatusBarColor(a.r, a.g, a.b)
                sb:Show(); rest:Hide()
            end
        end
        local len = inst:GetAutoLength()
        if len ~= lastLen then lastLen = len; mod.RequestLayout(bar.id) end
    end
    function inst:GetAutoLength()
        local w = fs:GetStringWidth() or 0
        if w <= 0 then return 0 end
        sb:SetWidth(w + 30)
        content:SetSize(math.max(math.ceil(w + 30), 1), bar.thickness or 26)
        return math.ceil(w + 30)
    end
    local evFrame
    function inst:Enable()
        evFrame = evFrame or CreateFrame("Frame")
        for _, ev in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP",
                              "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }) do
            pcall(evFrame.RegisterEvent, evFrame, ev)
        end
        evFrame:SetScript("OnEvent", function() inst:Refresh() end)
        slot:EnableMouse(true)
        slot:SetScript("OnMouseUp", function(_, btn)
            if btn == "RightButton" then
                b.settings.mode = (currentMode() == "xp") and "rep" or "xp"
                inst:Refresh()
            end
        end)
        slot:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            if currentMode() == "xp" then
                GameTooltip:SetText(L["XP"])
                GameTooltip:AddDoubleLine(L["Current"], string.format("%d / %d", UnitXP("player"), UnitXPMax("player")), 1,1,1, 1,1,1)
                local exh = GetXPExhaustion()
                if exh then GameTooltip:AddDoubleLine(L["Rested"], tostring(exh), 1,1,1, 0.4,0.4,1) end
            else
                local name, standing, minV, maxV, value = GetWatchedFactionInfo()
                GameTooltip:SetText(name or L["Reputation"])
                if name then
                    GameTooltip:AddDoubleLine(_G["FACTION_STANDING_LABEL" .. (standing or 4)] or "",
                        string.format("%d / %d", value - minV, maxV - minV), 1,1,1, 1,1,1)
                end
            end
            GameTooltip:AddLine(L["Right-Click: toggle XP / reputation"], 0.5, 0.7, 1)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    function inst:Disable()
        if evFrame then evFrame:UnregisterAllEvents(); evFrame:SetScript("OnEvent", nil) end
        slot:EnableMouse(false)
    end
    return inst
end)

-- ---------------------------------------------------------------------------
-- Micro menu: a strip of micro buttons inside a data bar.
--
-- Buttons whose Blizzard twin toggles its panel in an OnClick handler get a
-- SecureActionButtonTemplate with click redirection (*type1 = "click",
-- clickbutton1 = the real button): the panel-open then runs entirely in
-- Blizzard's stack, never in ours. That is mandatory for the spellbook --
-- opening it from addon Lua taints SpellBookFrame.bookType and CastSpell is
-- refused until reload (see the MODERN_MICRO catalog notes in
-- Modules/ActionBars.lua).
--
-- Buttons whose twin acts in OnMouseUp behind an IsMouseOver check get NO
-- redirection: a forwarded Click() only fires OnClick and would be a no-op.
-- On this client that is character, lfg and menu (verified against the
-- anniversary UI source, Blizzard_MicroMenu/Classic). Those are plain
-- buttons with a direct, taint-uncritical call; their twin is still
-- resolved so its tooltipText can be shown.
--
-- Secure buttons are protected frames: create, position, show and hide them
-- only out of combat. In lockdown everything defers via inst._deferred and
-- is caught up on PLAYER_REGEN_ENABLED; until built, GetAutoLength() is 0.
-- ---------------------------------------------------------------------------
local MM_ICON = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\"
-- twins = candidate globals, first hit wins (also feeds the tooltip).
-- action present  -> plain button with a direct call.
-- action absent   -> secure click redirection onto the resolved twin.
-- Neither a resolvable twin nor an action -> the key is skipped.
local MM_BUTTONS = {
    { key = "character", icon = "micro\\character", twins = { "CharacterMicroButton" },
      -- twin toggles in OnMouseUp, so it gets a direct call; same call the
      -- action bar micro menu uses, safe from addon Lua
      action = function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end },
    { key = "spellbook", icon = "micro\\spellbook", twins = { "SpellbookMicroButton" } },
    { key = "talents",   icon = "micro\\talents",   twins = { "TalentMicroButton" } },
    { key = "quests",    icon = "micro\\questlog",  twins = { "QuestLogMicroButton" } },
    { key = "social",    icon = "micro\\socials",   twins = { "SocialsMicroButton", "GuildMicroButton" } },
    { key = "lfg",       icon = "micro\\lfg",       twins = { "LFGMicroButton" },
      -- twin toggles in OnMouseUp as well; PVEFrame_ToggleFrame is the call
      -- its own handler makes on this client, older clients keep the
      -- LFGParentFrame names
      action = function()
          if PVEFrame_ToggleFrame then PVEFrame_ToggleFrame()
          elseif ToggleLFGParentFrame then ToggleLFGParentFrame()
          elseif _G.LFGParentFrame then
              local f = _G.LFGParentFrame
              if f:IsShown() then HideUIPanel(f) else ShowUIPanel(f) end
          end
      end },
    { key = "map",       icon = "micro\\map",       twins = { "WorldMapMicroButton" },
      action = function() if ToggleWorldMap then ToggleWorldMap() end end },
    { key = "help",      icon = "micro\\help",      twins = { "HelpMicroButton" } },
    { key = "menu",      icon = "gear",             twins = { "MainMenuMicroButton" },
      action = function()
          local gm = _G.GameMenuFrame
          if not gm then return end
          if gm:IsShown() then HideUIPanel(gm)
          else
              if CloseMenus then CloseMenus() end
              if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
              ShowUIPanel(gm)
          end
      end },
}

addType("micromenu", "Micro menu",
    { character = true, spellbook = true, talents = true, quests = true,
      social = true, lfg = true, map = true, menu = true, help = false, spacing = 2 },
    function(b, slot, content, bar)
        local inst = { _key = instKey("mm", b, bar), _buttons = {}, _width = 0 }
        local function resolveTwin(def)
            for _, n in ipairs(def.twins or {}) do
                if _G[n] then return _G[n] end
            end
        end
        local function ensureButtons()
            if inst._built then return true end
            if InCombatLockdown() then inst._deferred = true; return false end
            local sz = math.floor((bar.thickness or 26) * 0.72 + 0.5)
            for _, def in ipairs(MM_BUTTONS) do
                local twin = resolveTwin(def)
                if twin or def.action then
                    local btn
                    if def.action then
                        -- plain button, direct call; twin (if any) only feeds
                        -- the tooltip below
                        btn = CreateFrame("Button", nil, content)
                        btn:SetScript("OnClick", def.action)
                    else
                        -- secure click redirection; house recipe for 20505:
                        -- wildcard *type1, clickbutton1 without asterisk
                        btn = CreateFrame("Button",
                            "VuloTrackbarMM" .. bar.id .. "_" .. b.id .. "_" .. def.key,
                            content, "SecureActionButtonTemplate")
                        btn:RegisterForClicks("AnyUp", "AnyDown")
                        btn:SetAttribute("*type1", "click")
                        btn:SetAttribute("clickbutton1", twin)
                    end
                    btn:SetSize(sz, sz)
                    local tex = btn:CreateTexture(nil, "ARTWORK")
                    tex:SetAllPoints(btn)
                    tex:SetTexture(MM_ICON .. def.icon)
                    tex:SetVertexColor(0.85, 0.85, 0.85)
                    btn:SetScript("OnEnter", function(s)
                        local a = ns.COLORS and ns.COLORS.accent
                        if a then tex:SetVertexColor(a.r, a.g, a.b)
                        else tex:SetVertexColor(1, 1, 1) end
                        local tip = twin and twin.tooltipText
                        if tip then
                            GameTooltip:SetOwner(s, "ANCHOR_TOP")
                            GameTooltip:SetText(tip); GameTooltip:Show()
                        end
                    end)
                    btn:SetScript("OnLeave", function()
                        tex:SetVertexColor(0.85, 0.85, 0.85)
                        GameTooltip:Hide()
                    end)
                    inst._buttons[def.key] = btn
                end
            end
            inst._built = true
            return true
        end
        local function layoutButtons()
            -- the secure buttons are protected: never Show/Hide/SetPoint them
            -- in combat; defer and catch up on PLAYER_REGEN_ENABLED
            if InCombatLockdown() then inst._deferred = true; return end
            local sz = math.floor((bar.thickness or 26) * 0.72 + 0.5)
            local gap = b.settings.spacing or 2
            local x = 0
            for _, def in ipairs(MM_BUTTONS) do
                local btn = inst._buttons[def.key]
                if btn then
                    if b.settings[def.key] then
                        btn:SetSize(sz, sz)
                        btn:Show()
                        btn:ClearAllPoints()
                        btn:SetPoint("LEFT", content, "LEFT", x, 0)
                        x = x + sz + gap
                    else
                        btn:Hide()
                    end
                end
            end
            inst._width = (x > 0) and (x - gap) or 0
            content:SetSize(math.max(inst._width, 1), sz)
        end
        function inst:Refresh()
            if ensureButtons() then layoutButtons() end
            mod.RequestLayout(bar.id)
        end
        function inst:GetAutoLength() return inst._built and inst._width or 0 end
        local evFrame
        function inst:Enable()
            content:Show()
            evFrame = evFrame or CreateFrame("Frame")
            evFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            evFrame:SetScript("OnEvent", function()
                if inst._deferred then inst._deferred = nil; inst:Refresh() end
            end)
        end
        function inst:Disable()
            if evFrame then evFrame:UnregisterAllEvents() end
            -- hide via the insecure parent: btn:Hide() on a protected button
            -- would be blocked in combat
            content:Hide()
        end
        return inst
    end)

-- ---------------------------------------------------------------------------
-- Combat timer: seconds in the current fight, or the last fight's length out
-- of combat. Heartbeat-driven; the two regen events make the flip immediate.
-- ---------------------------------------------------------------------------
local combatStart, lastFight = nil, 0
local function combatClock()
    local inCombat = UnitAffectingCombat("player")
    local now = GetTime()
    if inCombat and not combatStart then
        combatStart = now
    elseif not inCombat and combatStart then
        lastFight = now - combatStart
        combatStart = nil
    end
    local sec = combatStart and (now - combatStart) or lastFight
    sec = math.floor(sec + 0.5)
    return combatStart ~= nil, string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

addType("combattimer", "Combat timer", { showLast = true }, MakeTextBlock("combat", {
    interval = 1, fontScale = 0.5,
    events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" },
    text = function(b)
        local fighting, txt = combatClock()
        if fighting then return L["Combat"] .. " " .. txt end
        if b.settings.showLast and lastFight > 0 then
            return "|cff888888" .. L["Last fight"] .. " " .. txt .. "|r"
        end
        return ""
    end,
}))

-- ---------------------------------------------------------------------------
-- Hearthstone: a secure item button (using it is a protected action, so the
-- click runs in the client's own stack), the bind location or the cooldown
-- as text beside it. Same combat rules as the micro menu: created, shown and
-- placed only out of combat, deferred through PLAYER_REGEN_ENABLED.
-- ---------------------------------------------------------------------------
local HEARTHSTONE_ID = 6948
local function itemCooldown(itemID)
    if _G.GetItemCooldown then return GetItemCooldown(itemID) end
    if C_Item and C_Item.GetItemCooldown then
        local s, d = C_Item.GetItemCooldown(itemID)
        return s, d
    end
    if C_Container and C_Container.GetItemCooldown then return C_Container.GetItemCooldown(itemID) end
    return 0, 0
end
local function itemIcon(itemID)
    if _G.GetItemIcon then return GetItemIcon(itemID) end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    return "Interface\\Icons\\INV_Misc_Rune_01"
end
local function cooldownText(start, dur)
    if not start or not dur or dur <= 0 then return nil end
    local left = start + dur - GetTime()
    if left <= 0 then return nil end
    left = math.floor(left + 0.5)
    if left >= 60 then return string.format("%d:%02d", math.floor(left / 60), left % 60) end
    return tostring(left)
end

addType("hearth", "Hearthstone", { showLocation = true }, function(b, slot, content, bar)
    local inst = { _key = instKey("hearth", b, bar), _width = 0 }
    local fs = content:CreateFontString(nil, "OVERLAY")
    UI.FontFor("trackbars", fs, textBlockFontSize(bar, {}))
    fs:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    fs:SetWordWrap(false)
    local btn
    local function ensureButton()
        if btn then return true end
        if InCombatLockdown() then inst._deferred = true; return false end
        btn = CreateFrame("Button", "VuloTrackbarHearth" .. bar.id .. "_" .. b.id, content, "SecureActionButtonTemplate")
        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:SetAttribute("type", "item")
        -- the secure item action uses the item by NAME; the id string is the
        -- fallback until the client has the item cached (Refresh retries)
        btn:SetAttribute("item", GetItemInfo(HEARTHSTONE_ID) or ("item:" .. HEARTHSTONE_ID))
        local sz = math.floor((bar.thickness or 26) * 0.72 + 0.5)
        btn:SetSize(sz, sz)
        btn:SetPoint("RIGHT", fs, "LEFT", -4, 0)
        btn.tex = btn:CreateTexture(nil, "ARTWORK")
        btn.tex:SetAllPoints(btn)
        btn.tex:SetTexture(itemIcon(HEARTHSTONE_ID))
        btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:SetText(L["Hearthstone"])
            GameTooltip:AddLine(GetBindLocation() or "", 1, 1, 1)
            local cd = cooldownText(itemCooldown(HEARTHSTONE_ID))
            if cd then GameTooltip:AddDoubleLine(L["Cooldown"], cd, 1,1,1, 1,0.6,0.3) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return true
    end
    function inst:Restyle()
        UI.FontFor("trackbars", fs, textBlockFontSize(bar, {}))
        if btn and not InCombatLockdown() then
            local sz = math.floor((bar.thickness or 26) * 0.72 + 0.5)
            btn:SetSize(sz, sz)
        end
    end
    local lastLen = -1
    function inst:Refresh()
        ensureButton()
        if btn and not btn._named and not InCombatLockdown() then
            local name = GetItemInfo(HEARTHSTONE_ID)
            if name then btn:SetAttribute("item", name); btn._named = true end
        end
        local r, g, bl = blockColor(b)
        local cd = cooldownText(itemCooldown(HEARTHSTONE_ID))
        if cd then
            fs:SetTextColor(1, 0.6, 0.3)
            fs:SetText(cd)
        elseif b.settings.showLocation then
            fs:SetTextColor(r, g, bl)
            fs:SetText(GetBindLocation() or "")
        else
            fs:SetText("")
        end
        if btn then btn.tex:SetVertexColor(cd and 0.5 or 1, cd and 0.5 or 1, cd and 0.5 or 1) end
        local len = self:GetAutoLength()
        content:SetSize(math.max(len, 1), bar.thickness or 26)
        if len ~= lastLen then lastLen = len; mod.RequestLayout(bar.id) end
    end
    function inst:GetAutoLength()
        if not btn then return 0 end
        local w = btn:GetWidth() or 0
        local tw = fs:GetStringWidth() or 0
        if tw > 0 then w = w + 4 + tw end
        return math.ceil(w)
    end
    local evFrame
    function inst:Enable()
        content:Show()
        mod.RegisterHeartbeat(self._key, function() inst:Refresh() end)
        evFrame = evFrame or CreateFrame("Frame")
        for _, ev in ipairs({ "PLAYER_REGEN_ENABLED", "HEARTHSTONE_BOUND", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_COOLDOWN" }) do
            pcall(evFrame.RegisterEvent, evFrame, ev)
        end
        evFrame:SetScript("OnEvent", function(_, ev)
            if ev == "PLAYER_REGEN_ENABLED" and inst._deferred then inst._deferred = nil end
            inst:Refresh()
        end)
    end
    function inst:Disable()
        mod.UnregisterHeartbeat(self._key)
        if evFrame then evFrame:UnregisterAllEvents(); evFrame:SetScript("OnEvent", nil) end
        content:Hide()
    end
    return inst
end)

-- ---------------------------------------------------------------------------
-- Professions: one icon per profession with its rank; a crafting profession's
-- icon is a secure spell button that opens its window (a protected cast), a
-- gathering one just shows the rank. Primary professions are the abandonable
-- skill lines, secondary ones are matched by the names of their spells.
-- ---------------------------------------------------------------------------
local PROF_SPELLS = { 2259, 2018, 7411, 4036, 2366, 2108, 2575, 8613, 3908, 25229, 45357 }
local SECONDARY_SPELLS = { 2550, 3273, 7620 }
local profIcons        -- spell name -> icon, built lazily (spell data is late)
local secondaryNames   -- spell name -> true
local function buildProfMaps()
    if profIcons then return end
    profIcons, secondaryNames = {}, {}
    for _, id in ipairs(PROF_SPELLS) do
        local name, _, icon = GetSpellInfo(id)
        if name then profIcons[name] = icon end
    end
    for _, id in ipairs(SECONDARY_SPELLS) do
        local name, _, icon = GetSpellInfo(id)
        if name then profIcons[name] = icon; secondaryNames[name] = true end
    end
end

-- The professions this character has: { name, rank, max, secondary, icon }.
-- A collapsed header in the skill window hides its lines from this API, so
-- collapsed headers are expanded first; that fires SKILL_LINES_CHANGED once,
-- and the second pass finds nothing left to expand.
local lastExpand = 0
local function professions(includeSecondary)
    buildProfMaps()
    local out = {}
    if not GetNumSkillLines then return out end
    -- Rate-limited: the expand fires SKILL_LINES_CHANGED, which refreshes
    -- this block; a header the client refuses to expand must not bounce the
    -- two into a loop.
    if ExpandSkillHeader and GetTime() - lastExpand > 5 then
        for i = 1, GetNumSkillLines() do
            local _, isHeader, isExpanded = GetSkillLineInfo(i)
            if isHeader and not isExpanded then
                lastExpand = GetTime()
                ExpandSkillHeader(0)
                break
            end
        end
    end
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, _, maxRank, isAbandonable = GetSkillLineInfo(i)
        if name and not isHeader then
            local secondary = secondaryNames[name] == true
            if isAbandonable or (secondary and includeSecondary) then
                out[#out + 1] = { name = name, rank = rank or 0, max = maxRank or 0,
                                  secondary = secondary,
                                  icon = profIcons[name] or "Interface\\Icons\\INV_Misc_Book_09" }
            end
        end
    end
    return out
end

addType("professions", "Professions", { showSecondary = false, showRank = true, spacing = 6 },
function(b, slot, content, bar)
    local inst = { _key = instKey("prof", b, bar), _rows = {}, _width = 0 }
    -- Rows are keyed by profession NAME, not by position: learning or
    -- dropping a profession must not hand a crafting spell button to a
    -- gathering skill (or the other way round). A row that no longer has a
    -- profession is hidden and kept.
    local function ensureRow(p)
        local row = inst._rows[p.name]
        if row then return row end
        if InCombatLockdown() then inst._deferred = true; return nil end
        row = {}
        -- a known spell of the same name opens a window; gathering has none
        local opens = GetSpellInfo(p.name) ~= nil
        inst._rowCount = (inst._rowCount or 0) + 1
        local i = inst._rowCount
        if opens then
            row.btn = CreateFrame("Button", "VuloTrackbarProf" .. bar.id .. "_" .. b.id .. "_" .. i,
                content, "SecureActionButtonTemplate")
            row.btn:RegisterForClicks("AnyUp", "AnyDown")
            row.btn:SetAttribute("type", "spell")
        else
            row.btn = CreateFrame("Button", nil, content)
        end
        row.secure = opens
        row.tex = row.btn:CreateTexture(nil, "ARTWORK")
        row.tex:SetAllPoints(row.btn)
        row.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.fs = content:CreateFontString(nil, "OVERLAY")
        row.fs:SetWordWrap(false)
        row.btn:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:SetText(row.name or "")
            GameTooltip:AddLine(string.format("%d / %d", row.rank or 0, row.max or 0), 1, 1, 1)
            GameTooltip:Show()
        end)
        row.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        inst._rows[p.name] = row
        return row
    end
    local function layoutRows()
        if InCombatLockdown() then inst._deferred = true; return end
        local list = professions(b.settings.showSecondary)
        local sz = math.floor((bar.thickness or 26) * 0.72 + 0.5)
        local gap = b.settings.spacing or 6
        local x = 0
        local r, g, bl = blockColor(b)
        local shown = {}
        for _, p in ipairs(list) do
            local row = ensureRow(p)
            if not row then break end
            shown[p.name] = true
            row.name, row.rank, row.max = p.name, p.rank, p.max
            if row.secure and not row.spellSet then
                row.btn:SetAttribute("spell", p.name)
                row.spellSet = true
            end
            row.tex:SetTexture(p.icon)
            row.btn:SetSize(sz, sz)
            row.btn:ClearAllPoints()
            row.btn:SetPoint("LEFT", content, "LEFT", x, 0)
            row.btn:Show()
            x = x + sz
            UI.FontFor("trackbars", row.fs, textBlockFontSize(bar, {}))
            if b.settings.showRank then
                row.fs:SetTextColor(r, g, bl)
                row.fs:SetFormattedText("%d", p.rank)
                row.fs:ClearAllPoints()
                row.fs:SetPoint("LEFT", content, "LEFT", x + 3, 0)
                row.fs:Show()
                x = x + 3 + math.ceil(row.fs:GetStringWidth() or 0)
            else
                row.fs:Hide()
            end
            x = x + gap
        end
        for name, row in pairs(inst._rows) do
            if not shown[name] then row.btn:Hide(); row.fs:Hide() end
        end
        inst._width = (x > 0) and (x - gap) or 0
        content:SetSize(math.max(inst._width, 1), bar.thickness or 26)
    end
    local lastLen = -1
    function inst:Refresh()
        layoutRows()
        local len = self:GetAutoLength()
        if len ~= lastLen then lastLen = len; mod.RequestLayout(bar.id) end
    end
    function inst:GetAutoLength() return inst._width end
    local evFrame
    function inst:Enable()
        content:Show()
        evFrame = evFrame or CreateFrame("Frame")
        for _, ev in ipairs({ "PLAYER_REGEN_ENABLED", "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD" }) do
            pcall(evFrame.RegisterEvent, evFrame, ev)
        end
        evFrame:SetScript("OnEvent", function(_, ev)
            if ev == "PLAYER_REGEN_ENABLED" then
                if inst._deferred then inst._deferred = nil; inst:Refresh() end
            else
                inst:Refresh()
            end
        end)
    end
    function inst:Disable()
        if evFrame then evFrame:UnregisterAllEvents(); evFrame:SetScript("OnEvent", nil) end
        content:Hide()
    end
    return inst
end)

-- Broker-Plugin: zeigt ein Datenobjekt, das ein anderes Addon ueber die
-- eingebettete Broker-Bibliothek registriert hat. Aktualisierung rein ueber
-- deren Attribut-Callbacks -- die Bibliothek feuert bei JEDER Aenderung,
-- ein Herzschlag wuerde nur dasselbe noch einmal malen. Jeder Griff in
-- Plugin-Code laeuft durch pcall: ein kaputtes Fremd-Plugin darf die
-- Leiste nicht mitreissen.
addType("broker", "Broker plugin", { plugin = "", stripColors = false, maxWidth = 0 },
function(b, slot, content, bar)
    local inst = { _key = instKey("broker", b, bar) }
    local ldb = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    local fs = content:CreateFontString(nil, "OVERLAY")
    UI.FontFor("trackbars", fs, textBlockFontSize(bar, {}))
    fs:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    fs:SetWordWrap(false)
    local icon = content:CreateTexture(nil, "ARTWORK")
    local isz = math.floor((bar.thickness or 26) * 0.62 + 0.5)
    icon:SetSize(isz, isz)
    icon:SetPoint("RIGHT", fs, "LEFT", -4, 0)
    icon:Hide()
    inst.fs, inst.icon = fs, icon

    local function obj()
        local name = b.settings.plugin
        if not ldb or not name or name == "" then return nil, name end
        return ldb:GetDataObjectByName(name), name
    end

    -- Die Callbacks folgen dem KONFIGURIERTEN Namen, nicht dem Namen zur
    -- Enable-Zeit: ein Plugin-Wechsel im Klappmenue laeuft nur ueber
    -- ApplyBar -> Refresh (die Engine ruft Enable nie ein zweites Mal),
    -- und ohne Umregistrierung friert der Block bis zum /reload ein
    -- (Review-Fund). false = noch nie registriert, nil = registriert
    -- ohne Plugin -- die beiden muessen sich unterscheiden, sonst wuerde
    -- der allererste Lauf ohne Plugin gar nichts registrieren.
    local regName = false
    local function ensureCallbacks()
        if not ldb then return end
        local name = b.settings.plugin
        if name == "" then name = nil end
        if name == regName then return end
        ldb.UnregisterAllCallbacks(inst)
        if name then
            ldb.RegisterCallback(inst, "LibDataBroker_AttributeChanged_" .. name,
                function() inst:Refresh() end)
        end
        ldb.RegisterCallback(inst, "LibDataBroker_DataObjectCreated",
            function() inst:Refresh() end)
        regName = name
    end

    function inst:Restyle()
        UI.FontFor("trackbars", fs, textBlockFontSize(bar, {}))
        local sz = math.floor((bar.thickness or 26) * 0.62 + 0.5)
        icon:SetSize(sz, sz)
    end

    local lastLen = -1
    function inst:Refresh()
        ensureCallbacks()
        local o, name = obj()
        local r, g, bl = blockColor(b)
        fs:SetTextColor(r, g, bl)
        local txt
        if o then
            -- tostring: ein Plugin, das eine Zahl in .text schreibt, darf
            -- den Block nicht crashen (Review-Haertung)
            txt = tostring(o.text or o.label or name or "")
            if b.settings.stripColors then
                txt = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            end
            local tex = o.icon
            if type(tex) == "string" or type(tex) == "number" then
                icon:SetTexture(tex)
                local c = o.iconCoords
                if type(c) == "table" and c[4] then
                    icon:SetTexCoord(c[1], c[2], c[3], c[4])
                else
                    icon:SetTexCoord(0, 1, 0, 1)
                end
                icon:Show()
            else
                icon:Hide()
            end
        else
            -- konfiguriert, aber (noch) nicht registriert: Name ausgegraut,
            -- der DataObjectCreated-Callback unten holt den Block dann ab
            txt = "|cff888888" .. ((name and name ~= "" and name) or L["Broker plugin"]) .. "|r"
            icon:Hide()
        end
        -- vor JEDER Messung die natuerliche Breite herstellen, sonst misst
        -- GetStringWidth nach einem frueheren Kappen falsch weiter
        fs:SetWidth(0)
        fs:SetText(txt or "")
        local mw = b.settings.maxWidth or 0
        local natural = fs:GetStringWidth() or 0
        if mw > 0 and natural > mw then fs:SetWidth(mw) end
        local len = self:GetAutoLength()
        content:SetSize(math.max(len, 1), bar.thickness or 26)
        if len ~= lastLen then lastLen = len; mod.RequestLayout(bar.id) end
    end

    function inst:GetAutoLength()
        local w = fs:GetStringWidth() or 0
        local mw = b.settings.maxWidth or 0
        if mw > 0 and w > mw then w = mw end
        if w <= 0 then return 0 end
        if icon:IsShown() then w = w + (icon:GetWidth() or 0) + 4 end
        return math.ceil(w)
    end

    function inst:Enable()
        ensureCallbacks()
        slot:EnableMouse(true)
        slot:SetScript("OnMouseUp", function(s, btn)
            local o = obj()
            if o and type(o.OnClick) == "function" then pcall(o.OnClick, s, btn) end
        end)
        slot:SetScript("OnEnter", function(s)
            local o, name = obj()
            if o and type(o.OnTooltipShow) == "function" then
                GameTooltip:SetOwner(s, "ANCHOR_TOP")
                pcall(o.OnTooltipShow, GameTooltip)
                GameTooltip:Show()
            elseif o and type(o.OnEnter) == "function" then
                pcall(o.OnEnter, s)
            elseif name and name ~= "" then
                GameTooltip:SetOwner(s, "ANCHOR_TOP")
                GameTooltip:SetText(name)
                GameTooltip:Show()
            end
        end)
        slot:SetScript("OnLeave", function(s)
            local o = obj()
            if o and type(o.OnLeave) == "function" then pcall(o.OnLeave, s) end
            GameTooltip:Hide()
        end)
    end

    function inst:Disable()
        if ldb then ldb.UnregisterAllCallbacks(inst) end
        regName = false
        -- Skripte mit abraeumen: der Slot wird von der Engine je Block-Kennung
        -- wiederverwendet, und ein Nachmieter anderen Typs setzt nicht
        -- zwingend alle drei neu (Review-Haertung)
        slot:SetScript("OnMouseUp", nil)
        slot:SetScript("OnEnter", nil)
        slot:SetScript("OnLeave", nil)
        slot:EnableMouse(false)
    end

    return inst
end)
