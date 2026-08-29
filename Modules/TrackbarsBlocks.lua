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
local function MakeTextBlock(prefix, def)
    return function(b, slot, content, bar)
        local inst = { _key = instKey(prefix, b, bar) }
        local fs = content:CreateFontString(nil, "OVERLAY")
        UI.FontFor("trackbars", fs, math.floor((bar.thickness or 26) * (def.fontScale or 0.5) + 0.5))
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
addType("clock", "Clock", { hour24 = true, source = "local" }, MakeTextBlock("clock", {
    interval = 1, fontScale = 0.55,
    text = function(b)
        local s = b.settings
        if s.source == "server" then
            local h, m = GetGameTime()
            if not s.hour24 then
                local suf = (h >= 12) and " PM" or " AM"
                h = h % 12; if h == 0 then h = 12 end
                return string.format("%d:%02d%s", h, m, suf)
            end
            return string.format("%02d:%02d", h, m)
        end
        return date(s.hour24 and "%H:%M" or "%I:%M %p")
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
    goldStore()[goldCharKey()] = { money = money, class = class }
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
    UI.FontFor("trackbars", fs, math.floor((bar.thickness or 26) * 0.42 + 0.5))
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
        sb:SetWidth(w + 30); return math.ceil(w + 30)
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
