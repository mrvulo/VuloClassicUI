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
