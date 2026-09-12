-- VuloClassicUI / Modules / Auras: your buffs and debuffs as two rows of
-- dark icons with a duration underneath, in place of the game's own frames.
--
-- The rows are the client's own secure aura headers (SecureAuraHeaderTemplate,
-- verified against the anniversary UI source): the header creates one secure
-- button per aura, sorts, wraps and anchors them, and its "cancelaura" action
-- is the one way an addon may cancel a buff. We give the header the plain
-- SecureActionButtonTemplate as its button template and dress every button
-- ourselves -- icon, border, count, duration -- the moment the header has
-- created it. Nothing protected is touched in combat: attributes and points
-- are written out of combat only, and a change made in combat waits for
-- PLAYER_REGEN_ENABLED. Textures and text are free at any time.
local _, ns = ...
local L  = ns.L
local UI = ns.UI

local mod = ns:RegisterModule("auras", {
    name        = "Auras",
    group       = "HUD",
    description = "Your buffs and debuffs as rows of dark icons with the time left underneath, replacing the game's own frames. Right-click cancels a buff. Ships disabled: switch it on here.",
    defaults    = {
        enabled       = false,
        iconSize      = 30,
        spacing       = 4,
        perRow        = 10,
        growLeft      = true,
        sortMethod    = "TIME",
        separateOwn   = true,
        showDuration  = true,
        fontSize      = 11,
        buffs         = { x = 0, y = 0 },
        debuffs       = { x = 0, y = 0 },
    },
})

local CreateFrame       = CreateFrame
local InCombatLockdown  = InCombatLockdown
local UnitAura          = UnitAura
local GetTime           = GetTime
local GetWeaponEnchantInfo     = GetWeaponEnchantInfo
local GetInventoryItemTexture  = GetInventoryItemTexture
local floor, format     = math.floor, string.format

local TEX_FLAT = "Interface\\Buttons\\WHITE8X8"
local headers  = {}      -- kind -> header frame
local shadow             -- hidden parent that swallows the game's own frames
local pending  = false   -- a layout change waited for combat to end
local ticker

------------------------------------------------------------------------
-- Duration text
------------------------------------------------------------------------
local function timeText(left)
    if left >= 3600 then return format("%dh", floor(left / 3600 + 0.5)) end
    if left >= 60   then return format("%dm", floor(left / 60 + 0.5)) end
    if left >= 10   then return format("%d", floor(left + 0.5)) end
    return format("%.1f", left)
end

------------------------------------------------------------------------
-- Dressing a button. Regions are created once, out of combat, on the
-- first paint after the header made the button; a button first seen in
-- combat stays bare until the fight ends and is dressed on the next pass.
------------------------------------------------------------------------
local function dress(btn)
    if btn._vcDressed then return true end
    if InCombatLockdown() then return false end
    local db = mod.db
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- pixel border from the house helper (four edge textures keyed by side)
    btn.edges = ns.MakeEdges and ns.MakeEdges(btn, "OVERLAY") or nil
    if not btn.edges then
        btn.border = CreateFrame("Frame", nil, btn, BackdropTemplateMixin and "BackdropTemplate")
        btn.border:SetAllPoints(btn)
        if btn.border.SetBackdrop then btn.border:SetBackdrop({ edgeFile = TEX_FLAT, edgeSize = 1 }) end
    end
    btn.count = btn:CreateFontString(nil, "OVERLAY")
    UI.FontFor("auras", btn.count, db.fontSize, "OUTLINE")
    btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.duration = btn:CreateFontString(nil, "OVERLAY")
    UI.FontFor("auras", btn.duration, db.fontSize, "OUTLINE")
    btn.duration:SetPoint("TOP", btn, "BOTTOM", 0, -1)
    btn:SetScript("OnEnter", function(self)
        if not self._vcUnit then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        if self._vcSlot then
            GameTooltip:SetInventoryItem("player", self._vcSlot)
        else
            GameTooltip:SetUnitAura("player", self._vcIndex, self._vcFilter)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- The plain action template registers no clicks of its own; without this
    -- the right button never reaches type2 and nothing ever cancels.
    btn:RegisterForClicks("RightButtonUp")
    btn._vcDressed = true
    return true
end

local function setBorder(btn, r, g, b)
    if btn.edges and ns.LayoutEdges then
        ns.LayoutEdges(btn.edges, btn, 1, r, g, b, 1, 0)
    elseif btn.border and btn.border.SetBackdropBorderColor then
        btn.border:SetBackdropBorderColor(r, g, b, 1)
    end
end

-- One aura button: reads the aura the header assigned and paints it.
local function paintAura(btn, unit, kind)
    local slot = btn:GetAttribute("target-slot")
    if slot then
        -- temporary weapon enchant: icon of the weapon, purple border, timer
        -- from GetWeaponEnchantInfo (milliseconds)
        local tex = GetInventoryItemTexture("player", slot)
        btn.icon:SetTexture(tex)
        setBorder(btn, 0.5, 0.2, 0.8)
        btn.count:SetText("")
        btn._vcUnit, btn._vcSlot, btn._vcIndex, btn._vcFilter = unit, slot, nil, nil
        local mh, mhExp, _, _, oh, ohExp = GetWeaponEnchantInfo()
        local exp = (slot == 16) and (mh and mhExp) or (slot == 17 and oh and ohExp) or nil
        btn._vcExpire = exp and (GetTime() + exp / 1000) or nil
        return
    end
    local index  = btn:GetAttribute("index")
    local filter = btn:GetAttribute("filter")
    if not index then return end
    local name, icon, count, debuffType, duration, expirationTime = UnitAura(unit, index, filter)
    if not name then
        btn._vcUnit = nil
        return
    end
    btn.icon:SetTexture(icon)
    btn._vcUnit, btn._vcSlot, btn._vcIndex, btn._vcFilter = unit, nil, index, filter
    if count and count > 1 then btn.count:SetText(count) else btn.count:SetText("") end
    if kind == "debuffs" then
        local c = debuffType and DebuffTypeColor and DebuffTypeColor[debuffType]
        if c then setBorder(btn, c.r, c.g, c.b) else setBorder(btn, 0.8, 0.1, 0.1) end
    else
        local b = ns.COLORS.border
        setBorder(btn, b.r, b.g, b.b)
    end
    btn._vcExpire = (duration and duration > 0 and expirationTime and expirationTime > 0) and expirationTime or nil
end

-- Called after every header update. Walks the children the header holds.
local function paintHeader(header)
    local kind = header._vcKind
    local unit = "player"
    local i = 1
    while true do
        local btn = header:GetAttribute("child" .. i)
        if not btn then break end
        if btn:IsShown() and dress(btn) then paintAura(btn, unit, kind) end
        i = i + 1
    end
    for w = 1, 2 do
        local btn = header:GetAttribute("tempEnchant" .. w)
        if btn and btn:IsShown() and dress(btn) then paintAura(btn, unit, kind) end
    end
end

-- Duration texts: a tenth of a second, only while a header is shown.
local function tick()
    local now = GetTime()
    local show = mod.db.showDuration
    for _, header in pairs(headers) do
        if header:IsShown() then
            local i = 1
            while true do
                local btn = header:GetAttribute("child" .. i)
                if not btn then break end
                if btn._vcDressed and btn:IsShown() then
                    local exp = btn._vcExpire
                    if show and exp then
                        local left = exp - now
                        if left > 0 then
                            local bucket = left >= 10 and floor(left) or floor(left * 10)
                            if btn._vcBucket ~= bucket then
                                btn._vcBucket = bucket
                                btn.duration:SetText(timeText(left))
                                if left < 10 then btn.duration:SetTextColor(1, 0.4, 0.4) else btn.duration:SetTextColor(1, 1, 1) end
                            end
                        else
                            btn._vcBucket = nil
                            btn.duration:SetText("")
                        end
                    else
                        btn._vcBucket = nil
                        btn.duration:SetText("")
                    end
                end
                i = i + 1
            end
            for w = 1, 2 do
                local btn = header:GetAttribute("tempEnchant" .. w)
                if btn and btn._vcDressed and btn:IsShown() and show and btn._vcExpire then
                    local left = btn._vcExpire - now
                    btn.duration:SetText(left > 0 and timeText(left) or "")
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Headers: attributes are protected writes, so they happen out of combat.
------------------------------------------------------------------------
local function applyHeader(kind)
    local h  = headers[kind]
    local db = mod.db
    if not h or InCombatLockdown() then pending = true; return end
    local size, gap = db.iconSize, db.spacing
    local step = size + gap
    local rowH = size + gap + (db.showDuration and (db.fontSize + 4) or 0)
    h:SetAttribute("_ignore", true)
    h:SetAttribute("unit", "player")
    h:SetAttribute("filter", kind == "debuffs" and "HARMFUL" or "HELPFUL")
    h:SetAttribute("template", "SecureActionButtonTemplate")
    h:SetAttribute("point", db.growLeft and "TOPRIGHT" or "TOPLEFT")
    h:SetAttribute("xOffset", db.growLeft and -step or step)
    h:SetAttribute("yOffset", 0)
    h:SetAttribute("wrapAfter", db.perRow)
    h:SetAttribute("wrapXOffset", 0)
    h:SetAttribute("wrapYOffset", -rowH)
    h:SetAttribute("maxWraps", 4)
    h:SetAttribute("minWidth", db.perRow * step)
    h:SetAttribute("minHeight", rowH)
    h:SetAttribute("sortMethod", db.sortMethod or "TIME")
    h:SetAttribute("sortDirection", "-")
    h:SetAttribute("separateOwn", db.separateOwn and 1 or 0)
    if kind == "buffs" then
        h:SetAttribute("includeWeapons", 1)
        h:SetAttribute("weaponTemplate", "SecureActionButtonTemplate")
    end
    -- Every button the header creates: right-click cancels through the
    -- secure action; the restricted snippet runs once per new button.
    h:SetAttribute("initialConfigFunction", [[ self:SetAttribute("type2", "cancelaura") ]])
    -- button geometry the header does not know about
    local i = 1
    while true do
        local btn = h:GetAttribute("child" .. i)
        if not btn then break end
        btn:SetSize(size, size)
        btn._vcSized = true
        if btn._vcDressed then
            UI.FontFor("auras", btn.count, db.fontSize, "OUTLINE")
            UI.FontFor("auras", btn.duration, db.fontSize, "OUTLINE")
        end
        i = i + 1
    end
    for w = 1, 2 do
        local btn = h:GetAttribute("tempEnchant" .. w)
        if btn then btn:SetSize(size, size); btn._vcSized = true end
    end
    h:SetAttribute("_ignore", nil)
    h:SetAttribute("_refresh", GetTime())   -- any change re-runs the header's update
    -- no SetSize here: the header sizes itself from its children on every
    -- update, floored by minWidth/minHeight; a size of ours only fought it
end

local function ensureHeader(kind)
    if headers[kind] then return headers[kind] end
    local h = CreateFrame("Frame", "VuloAuras_" .. kind, UIParent, "SecureAuraHeaderTemplate")
    h._vcKind = kind
    h:SetFrameStrata("LOW")
    headers[kind] = h
    local fdb = mod.db[kind]
    h.mover = ns:CreateMover(h, {
        key   = "auras." .. kind,
        db    = fdb,
        label = kind == "buffs" and L["Buffs"] or L["Debuffs"],
    })
    -- Buttons are born SecureActionButtonTemplate-sized (nothing); the
    -- header sizes its rect from them, so they get their size at creation
    -- through the paint pass, and applyHeader keeps them in step.
    return h
end

-- Everything protected in one place: attributes, sizes, the anchor the mover
-- gives the header, the show. In combat it all waits for the regen event.
local function applyAll()
    if InCombatLockdown() then pending = true; return end
    pending = false
    for kind in pairs(headers) do
        applyHeader(kind)
        ns:ApplyMover(headers[kind].mover)
        headers[kind]:Show()
    end
end

------------------------------------------------------------------------
-- Hooks and the game's own frames
------------------------------------------------------------------------
local hooked = false
local function installHook()
    if hooked or not _G.SecureAuraHeader_Update then return end
    hooked = true
    hooksecurefunc("SecureAuraHeader_Update", function(header)
        if not mod.active or not header._vcKind then return end
        -- new buttons need a size before the header can lay them out; the
        -- header lays out on this very call, so size them and ask for a
        -- second pass once (out of combat only, sizing is protected)
        local db = mod.db
        local resized = false
        if InCombatLockdown() then
            -- a button born in combat stays 0 x 0 until the fight ends;
            -- the regen pass sizes every child
            local i = 1
            while true do
                local btn = header:GetAttribute("child" .. i)
                if not btn then break end
                if not btn._vcSized then pending = true; break end
                i = i + 1
            end
        else
            local i = 1
            while true do
                local btn = header:GetAttribute("child" .. i)
                if not btn then break end
                if not btn._vcSized then
                    btn:SetSize(db.iconSize, db.iconSize)
                    btn._vcSized = true
                    resized = true
                end
                i = i + 1
            end
            for w = 1, 2 do
                local btn = header:GetAttribute("tempEnchant" .. w)
                if btn and not btn._vcSized then
                    btn:SetSize(db.iconSize, db.iconSize)
                    btn._vcSized = true
                    resized = true
                end
            end
        end
        paintHeader(header)
        if resized and not header._vcRelayout then
            header._vcRelayout = true
            C_Timer.After(0, function()
                header._vcRelayout = nil
                if mod.active and not InCombatLockdown() then header:SetAttribute("_refresh", GetTime()) end
            end)
        end
    end)
end

local function hideBlizzard()
    if not shadow then
        shadow = CreateFrame("Frame", "VuloAurasShadow", UIParent)
        shadow:SetAllPoints(UIParent)
        shadow:Hide()
    end
    for _, name in ipairs({ "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }) do
        local f = _G[name]
        if f and f:GetParent() ~= shadow then
            f._vcParent = f:GetParent()
            f:SetParent(shadow)
        end
    end
end

local function showBlizzard()
    for _, name in ipairs({ "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }) do
        local f = _G[name]
        if f and f._vcParent then
            f:SetParent(f._vcParent)
            f._vcParent = nil
        end
    end
end

function mod:OnEnable()
    installHook()
    ensureHeader("buffs")
    ensureHeader("debuffs")
    hideBlizzard()
    applyAll()
    if not ticker then ticker = ns:AddTicker(0.1, tick, nil, "auras") end
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if pending then applyAll() end end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() if not InCombatLockdown() then applyAll() end end)
end

function mod:OnDisable()
    if ticker then ns:CancelTicker(ticker); ticker = nil end
    for _, h in pairs(headers) do
        if not InCombatLockdown() then h:Hide() end
    end
    showBlizzard()
end

function mod:GetOptions()
    local db = self.db
    local function apply() applyAll() end
    local items = {}
    items[#items + 1] = { type = "toggle", label = L["Enable auras"],
        get = function() return ns:IsModuleEnabled("auras") end,
        set = function(_, v) ns:ToggleModule("auras", v) end }
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Display"] }
    items[#items + 1] = { type = "slider", label = L["Icon size"], min = 20, max = 48, step = 1,
        get = function() return db.iconSize end, set = function(_, v) db.iconSize = v; apply() end }
    items[#items + 1] = { type = "slider", label = L["Spacing"], min = 0, max = 12, step = 1,
        get = function() return db.spacing end, set = function(_, v) db.spacing = v; apply() end }
    items[#items + 1] = { type = "slider", label = L["Icons per row"], min = 4, max = 20, step = 1,
        get = function() return db.perRow end, set = function(_, v) db.perRow = v; apply() end }
    items[#items + 1] = { type = "slider", label = L["Font size"], min = 8, max = 16, step = 1,
        get = function() return db.fontSize end, set = function(_, v) db.fontSize = v; apply() end }
    items[#items + 1] = { type = "toggle", label = L["Grow to the left"],
        tooltip = L["New icons appear to the left of the first one, as the game does it; off grows to the right."],
        get = function() return db.growLeft end, set = function(_, v) db.growLeft = v; apply() end }
    items[#items + 1] = { type = "dropdown", label = L["Sort by"], width = 200,
        values = { { value = "TIME", text = "Time left" }, { value = "NAME", text = "Name" }, { value = "INDEX", text = "Order applied" } },
        get = function() return db.sortMethod end, set = function(_, v) db.sortMethod = v; apply() end }
    items[#items + 1] = { type = "toggle", label = L["Own auras first"],
        get = function() return db.separateOwn end, set = function(_, v) db.separateOwn = v; apply() end }
    items[#items + 1] = { type = "toggle", label = L["Show time left"],
        get = function() return db.showDuration end, set = function(_, v) db.showDuration = v; apply() end }
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Position"] }
    items[#items + 1] = { type = "desc",
        text = L["|cffaaaaaaBuffs and debuffs are two boxes in edit mode; drag each where you want it.|r"] }
    items[#items + 1] = {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", width = 180,
              label = ns:IsMoverEditMode() and L["Stop moving"] or L["Unlock / Move"],
              onClick = function()
                  ns:SetMoversEditMode(not ns:IsMoverEditMode())
                  if ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
              end },
        },
    }
    return items
end
