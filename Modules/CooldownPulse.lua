-- =========================================================
-- VuloClassicUI / Modules / CooldownPulse
-- Portiert aus Doom_CooldownPulse.
-- Blitzt das Icon eines Spells/Items kurz groß in der Bildschirmmitte
-- wenn dessen Cooldown abläuft.
--
-- Portiert für TBC 2.5.5 (keine C_Spell / C_Container / Settings APIs).
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("cooldownpulse", {
    name        = "Cooldown Pulse",
    group       = "Unit Frames",
    description = "Zeigt das Icon eines abgelaufenen Cooldowns als kurz pulsierende Animation in der Bildschirmmitte (basierend auf Doom_CooldownPulse).",
    defaults = {
        enabled       = false,  -- default AUS
        iconSize      = 75,
        fadeInTime    = 0.3,
        fadeOutTime   = 0.7,
        maxAlpha      = 0.7,
        holdTime      = 0,
        animScale     = 1.5,
        remainingTime = 0,      -- Cooldown muss UNTER diesem Wert sein um zu triggern
        showSpellName = false,
        unlocked      = false,
        x             = nil,    -- wird beim ersten Run gesetzt (Bildschirmmitte)
        y             = nil,
        ignoredSpells = "",     -- komma-separiert
        invertIgnored = false,  -- false = Blacklist, true = Whitelist
    },
})

-- =========================================================
-- API-Compat: GetItemCooldown ist in 2.5.5 nicht global verfügbar.
-- Mögliche Stellen je nach Client-Version:
--   - global GetItemCooldown (Classic Era)
--   - C_Item.GetItemCooldown (Retail 10.2+)
--   - C_Container.GetItemCooldown (Retail 10.0+)
-- Fallback: über Bags scannen mit GetContainerItemCooldown.
-- =========================================================
local function getItemCooldown(itemID)
    if not itemID then return 0, 0, 0 end

    if _G.GetItemCooldown then
        return GetItemCooldown(itemID)
    end
    if _G.C_Item and _G.C_Item.GetItemCooldown then
        local s, d, e = C_Item.GetItemCooldown(itemID)
        return s, d, (e == true and 1) or (e == false and 0) or e
    end
    if _G.C_Container and _G.C_Container.GetItemCooldown then
        return C_Container.GetItemCooldown(itemID)
    end

    -- Fallback: durch alle Bags scannen
    local getContainerItemInfo = _G.GetContainerItemInfo
    local getContainerItemCooldown = _G.GetContainerItemCooldown
    if _G.C_Container then
        getContainerItemInfo = getContainerItemInfo or C_Container.GetContainerItemInfo
        getContainerItemCooldown = getContainerItemCooldown or C_Container.GetContainerItemCooldown
    end
    if not getContainerItemCooldown then return 0, 0, 0 end

    for bag = 0, 4 do
        local slots = (_G.GetContainerNumSlots and GetContainerNumSlots(bag))
                   or (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag))
                   or 0
        for slot = 1, slots do
            local link
            if _G.GetContainerItemID then
                if GetContainerItemID(bag, slot) == itemID then
                    return getContainerItemCooldown(bag, slot)
                end
            elseif C_Container and C_Container.GetContainerItemID then
                if C_Container.GetContainerItemID(bag, slot) == itemID then
                    return getContainerItemCooldown(bag, slot)
                end
            end
        end
    end
    return 0, 0, 0
end

local function getContainerItemID(bag, slot)
    if _G.GetContainerItemID then return GetContainerItemID(bag, slot) end
    if _G.C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bag, slot)
    end
    return nil
end

-- =========================================================
-- Lokale State
-- =========================================================
local cooldowns = {}   -- [id] = getCooldownDetailsFn
local animating = {}   -- queue von {texture, isPet, name}
local watching  = {}   -- [id] = {startTime, type, ref}
local itemSpells = {}  -- [spellID] = itemID

local DCP        -- main frame
local DCPT       -- texture child
local TextFrame  -- font string child

-- =========================================================
-- Helper
-- =========================================================
local function tcount(tab)
    local n = 0
    for _ in pairs(tab) do n = n + 1 end
    return n
end

local function memoize(fn)
    local cached, hasValue = nil, false
    local m = {}
    local function get()
        if not hasValue then
            cached = fn()
            hasValue = true
        end
        return cached
    end
    m.resetCache = function() cached = nil; hasValue = false end
    setmetatable(m, { __call = get })
    return m
end

local function getPetActionIndexByName(name)
    if not name or not NUM_PET_ACTION_SLOTS then return nil end
    for i = 1, NUM_PET_ACTION_SLOTS do
        if GetPetActionInfo(i) == name then return i end
    end
    return nil
end

local function parseIgnoredSpells()
    local set = {}
    local raw = mod.db.ignoredSpells or ""
    for _, v in ipairs({ strsplit(",", raw) }) do
        local trimmed = strtrim(v)
        if trimmed ~= "" then set[trimmed] = true end
    end
    return set
end

local function isAnimatingByName(name)
    for _, details in pairs(animating) do
        if details[3] == name then return true end
    end
    return false
end

local function trackItemSpell(itemID)
    if not itemID then return false end
    local _, spellID = GetItemSpell(itemID)
    if spellID then
        itemSpells[spellID] = itemID
        return true
    end
    return false
end

-- =========================================================
-- Cooldown/Animation Update (OnUpdate)
-- =========================================================
local elapsed = 0
local runtimer = 0
local function OnUpdate(_, update)
    elapsed = elapsed + update
    if elapsed > 0.05 then
        local ignored = parseIgnoredSpells()

        for id, v in pairs(watching) do
            if GetTime() >= v[1] + 0.5 then
                local getDetails
                if v[2] == "spell" then
                    getDetails = memoize(function()
                        local name, _, texture = GetSpellInfo(v[3])
                        local start, duration, enabled = GetSpellCooldown(v[3])
                        return {
                            name     = name,
                            texture  = texture,
                            start    = start,
                            duration = duration,
                            enabled  = enabled,
                        }
                    end)
                elseif v[2] == "item" then
                    getDetails = memoize(function()
                        local start, duration, enabled = getItemCooldown(id)
                        return {
                            name     = GetItemInfo(id),
                            texture  = v[3],
                            start    = start,
                            duration = duration,
                            enabled  = enabled,
                        }
                    end)
                elseif v[2] == "pet" then
                    getDetails = memoize(function()
                        local name, texture = GetPetActionInfo(v[3])
                        local start, duration, enabled = GetPetActionCooldown(v[3])
                        return {
                            name     = name,
                            texture  = texture,
                            isPet    = true,
                            start    = start,
                            duration = duration,
                            enabled  = enabled,
                        }
                    end)
                end

                if getDetails then
                    local cd = getDetails()
                    local isFiltered = (ignored[cd.name or ""] ~= nil or ignored[tostring(id)] ~= nil)
                    if isFiltered ~= mod.db.invertIgnored then
                        watching[id] = nil
                    else
                        if cd.enabled and cd.enabled ~= 0 then
                            if cd.duration and cd.duration > 2.0 and cd.texture then
                                cooldowns[id] = getDetails
                            end
                        end
                        if not (cd.enabled == 0 and v[2] == "spell") then
                            watching[id] = nil
                        end
                    end
                end
            end
        end

        for i, getDetails in pairs(cooldowns) do
            local cd = getDetails()
            if cd.start then
                local remaining = cd.duration - (GetTime() - cd.start)
                if remaining <= (mod.db.remainingTime or 0) then
                    if not isAnimatingByName(cd.name) then
                        tinsert(animating, { cd.texture, cd.isPet, cd.name })
                    end
                    cooldowns[i] = nil
                end
            else
                cooldowns[i] = nil
            end
        end

        elapsed = 0
        if #animating == 0 and tcount(watching) == 0 and tcount(cooldowns) == 0 then
            DCP:SetScript("OnUpdate", nil)
            return
        end
    end

    if #animating > 0 then
        runtimer = runtimer + update
        local fadeInTime  = mod.db.fadeInTime  or 0.3
        local fadeOutTime = mod.db.fadeOutTime or 0.7
        local holdTime    = mod.db.holdTime    or 0
        local maxAlpha    = mod.db.maxAlpha    or 0.7
        local iconSize    = mod.db.iconSize    or 75
        local animScale   = mod.db.animScale   or 1.5

        if runtimer > (fadeInTime + holdTime + fadeOutTime) then
            tremove(animating, 1)
            runtimer = 0
            TextFrame:SetText(nil)
            DCPT:SetTexture(nil)
            DCPT:SetVertexColor(1, 1, 1)
        else
            if not DCPT:GetTexture() then
                if animating[1][3] and mod.db.showSpellName then
                    TextFrame:SetText(animating[1][3])
                end
                DCPT:SetTexture(animating[1][1])
            end
            local alpha = maxAlpha
            if runtimer < fadeInTime then
                alpha = maxAlpha * (runtimer / fadeInTime)
            elseif runtimer >= fadeInTime + holdTime then
                alpha = maxAlpha - (maxAlpha * ((runtimer - holdTime - fadeInTime) / fadeOutTime))
            end
            DCP:SetAlpha(alpha)
            local scale = iconSize + (iconSize * ((animScale - 1) * (runtimer / (fadeInTime + holdTime + fadeOutTime))))
            DCP:SetWidth(scale)
            DCP:SetHeight(scale)
        end
    end
end

-- =========================================================
-- Frame-Setup
-- =========================================================
local function ensureFrame()
    if DCP then return DCP end

    DCP = CreateFrame("Frame", "VCUI_CooldownPulse", UIParent)
    DCP:SetMovable(true)
    DCP:RegisterForDrag("LeftButton")
    DCP:SetScript("OnDragStart", function(self) self:StartMoving() end)
    DCP:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        mod.db.x = self:GetLeft() + self:GetWidth() / 2
        mod.db.y = self:GetBottom() + self:GetHeight() / 2
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mod.db.x, mod.db.y)
    end)

    TextFrame = DCP:CreateFontString(nil, "ARTWORK")
    TextFrame:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    TextFrame:SetShadowOffset(2, -2)
    TextFrame:SetPoint("CENTER", DCP, "CENTER")
    TextFrame:SetWidth(185)
    TextFrame:SetJustifyH("CENTER")
    TextFrame:SetTextColor(1, 1, 1)

    DCPT = DCP:CreateTexture(nil, "BACKGROUND")
    DCPT:SetAllPoints(DCP)

    -- Default-Position: Mitte
    if not mod.db.x then mod.db.x = UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2 end
    if not mod.db.y then mod.db.y = UIParent:GetHeight() * UIParent:GetEffectiveScale() / 2 end
    DCP:SetWidth(mod.db.iconSize or 75)
    DCP:SetHeight(mod.db.iconSize or 75)
    DCP:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mod.db.x, mod.db.y)
    DCP:SetAlpha(0)
    DCP:EnableMouse(false)

    return DCP
end

local function setUnlocked(state)
    mod.db.unlocked = state
    ensureFrame()
    if state then
        DCP:SetScript("OnUpdate", nil)
        DCP:SetAlpha(1)
        DCPT:SetTexture("Interface\\Icons\\Spell_Nature_Earthbind")
        DCP:EnableMouse(true)
        DCP:SetWidth(mod.db.iconSize)
        DCP:SetHeight(mod.db.iconSize)
        ns:Print("Cooldown Pulse Unlock aktiv — Icon ziehen zum Verschieben.")
    else
        DCP:SetAlpha(0)
        DCPT:SetTexture(nil)
        DCP:EnableMouse(false)
        ns:Print("Cooldown Pulse Unlock deaktiviert.")
    end
end

-- =========================================================
-- Events
-- =========================================================
local function triggerSpell(spellID)
    watching[spellID] = { GetTime(), "spell", spellID }
    if DCP and not DCP:IsMouseEnabled() then
        DCP:SetScript("OnUpdate", OnUpdate)
    end
end

local function triggerItem(itemID)
    if not itemID then return end
    -- texture aus GetItemInfo holen (Index 10 = icon)
    local texture = select(10, GetItemInfo(itemID))
    watching[itemID] = { GetTime(), "item", texture }
    itemSpells[itemID] = nil
    if DCP and not DCP:IsMouseEnabled() then
        DCP:SetScript("OnUpdate", OnUpdate)
    end
end

local eventFrame
local function setupEvents()
    if eventFrame then return end

    eventFrame = CreateFrame("Frame")

    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if not mod._enabled then return end

        if event == "SPELL_UPDATE_COOLDOWN" then
            for _, getDetails in pairs(cooldowns) do
                getDetails.resetCache()
            end

        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, _, spellID = ...
            if unit ~= "player" then return end
            local itemID = itemSpells[spellID]
            if itemID then
                triggerItem(itemID)
            else
                triggerSpell(spellID)
            end

        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            local _, e, _, _, _, sourceFlags, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
            if e == "SPELL_CAST_SUCCESS" and sourceFlags and spellID then
                local isPet = (bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PET or 0) ~= 0)
                local mine  = (bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE or 0) ~= 0)
                if isPet and mine then
                    local name = GetSpellInfo(spellID)
                    local index = getPetActionIndexByName(name)
                    if index and not select(6, GetPetActionInfo(index)) then
                        watching[spellID] = { GetTime(), "pet", index }
                        if DCP and not DCP:IsMouseEnabled() then
                            DCP:SetScript("OnUpdate", OnUpdate)
                        end
                    elseif not index and spellID then
                        triggerSpell(spellID)
                    end
                end
            end

        elseif event == "PLAYER_ENTERING_WORLD" then
            -- In Arena: clear queue (Animationen sind distracting)
            local inInstance, instanceType = IsInInstance()
            if inInstance and instanceType == "arena" then
                if DCP then DCP:SetScript("OnUpdate", nil) end
                wipe(cooldowns)
                wipe(watching)
            end
        end
    end)

    -- Hooks für Item-Usage (Action-Bars, Bag-Slots, Inventory)
    if UseAction then
        hooksecurefunc("UseAction", function(slot)
            if not mod._enabled then return end
            local actionType, itemID = GetActionInfo(slot)
            if actionType == "item" and itemID and not trackItemSpell(itemID) then
                local texture = GetActionTexture(slot)
                watching[itemID] = { GetTime(), "item", texture }
                if DCP and not DCP:IsMouseEnabled() then
                    DCP:SetScript("OnUpdate", OnUpdate)
                end
            end
        end)
    end

    if UseInventoryItem then
        hooksecurefunc("UseInventoryItem", function(slot)
            if not mod._enabled then return end
            local itemID = GetInventoryItemID("player", slot)
            if itemID and not trackItemSpell(itemID) then
                local texture = GetInventoryItemTexture("player", slot)
                watching[itemID] = { GetTime(), "item", texture }
                if DCP and not DCP:IsMouseEnabled() then
                    DCP:SetScript("OnUpdate", OnUpdate)
                end
            end
        end)
    end

    -- UseContainerItem: globaler Hook (in 2.5.5 global, ab Retail 10.0+ in C_Container)
    if _G.UseContainerItem then
        hooksecurefunc("UseContainerItem", function(bag, slot)
            if not mod._enabled then return end
            local itemID = getContainerItemID(bag, slot)
            if itemID and not trackItemSpell(itemID) then
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
                watching[itemID] = { GetTime(), "item", texture }
                if DCP and not DCP:IsMouseEnabled() then
                    DCP:SetScript("OnUpdate", OnUpdate)
                end
            end
        end)
    elseif _G.C_Container and C_Container.UseContainerItem then
        hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
            if not mod._enabled then return end
            local itemID = getContainerItemID(bag, slot)
            if itemID and not trackItemSpell(itemID) then
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
                watching[itemID] = { GetTime(), "item", texture }
                if DCP and not DCP:IsMouseEnabled() then
                    DCP:SetScript("OnUpdate", OnUpdate)
                end
            end
        end)
    end
end

-- =========================================================
-- Test-Animation
-- =========================================================
local function testAnimation()
    ensureFrame()
    if mod.db.unlocked then setUnlocked(false) end
    tinsert(animating, { "Interface\\Icons\\Spell_Nature_Earthbind", nil, "Test Spell" })
    DCP:SetScript("OnUpdate", OnUpdate)
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    ensureFrame()
    setupEvents()
    if mod.db.unlocked then setUnlocked(true) end
end

function mod:OnDisable()
    if DCP then
        DCP:SetScript("OnUpdate", nil)
        DCP:SetAlpha(0)
        DCP:EnableMouse(false)
    end
    wipe(animating)
    wipe(cooldowns)
    wipe(watching)
end

-- =========================================================
-- Options-Page
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = "Position" },
        {
            type = "group", layout = "row", gap = 8,
            items = {
                {
                    type = "button", label = "Unlock",
                    tooltip = "Zeigt ein Test-Icon das du verschieben kannst.",
                    width = 90,
                    onClick = function() setUnlocked(not mod.db.unlocked) end,
                },
                {
                    type = "button", label = "Test-Pulse", width = 110,
                    tooltip = "Spielt eine Test-Animation ab.",
                    onClick = testAnimation,
                },
                {
                    type = "button", label = "Position zurücksetzen", width = 170,
                    onClick = function()
                        mod.db.x = UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2
                        mod.db.y = UIParent:GetHeight() * UIParent:GetEffectiveScale() / 2
                        if DCP then
                            DCP:ClearAllPoints()
                            DCP:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mod.db.x, mod.db.y)
                        end
                        ns:Print("Cooldown Pulse Position zurückgesetzt.")
                    end,
                },
            },
        },

        { type = "spacer", height = 8 },
        { type = "header", text = "Aussehen" },

        {
            type = "slider", label = "Icon-Größe",
            min = 30, max = 125, step = 5,
            get = function() return mod.db.iconSize end,
            set = function(_, v)
                mod.db.iconSize = v
                if DCP and DCP:IsMouseEnabled() then
                    DCP:SetWidth(v); DCP:SetHeight(v)
                end
            end,
        },
        {
            type = "slider", label = "Max Deckkraft",
            min = 0.1, max = 1.0, step = 0.05,
            get = function() return mod.db.maxAlpha end,
            set = function(_, v) mod.db.maxAlpha = v end,
        },
        {
            type = "slider", label = "Animations-Skalierung",
            min = 1.0, max = 2.5, step = 0.1,
            get = function() return mod.db.animScale end,
            set = function(_, v) mod.db.animScale = v end,
        },
        {
            type = "slider", label = "Einblend-Zeit (s)",
            min = 0, max = 1.5, step = 0.1,
            get = function() return mod.db.fadeInTime end,
            set = function(_, v) mod.db.fadeInTime = v end,
        },
        {
            type = "slider", label = "Halten-Zeit (s)",
            min = 0, max = 1.5, step = 0.1,
            get = function() return mod.db.holdTime end,
            set = function(_, v) mod.db.holdTime = v end,
        },
        {
            type = "slider", label = "Ausblend-Zeit (s)",
            min = 0, max = 1.5, step = 0.1,
            get = function() return mod.db.fadeOutTime end,
            set = function(_, v) mod.db.fadeOutTime = v end,
        },
        {
            type = "slider", label = "Anzeige vor Verfügbarkeit (s)",
            tooltip = "Triggert die Animation X Sekunden BEVOR der Cooldown abläuft. 0 = exakt bei Cooldown-Ende.",
            min = 0, max = 3, step = 0.1,
            get = function() return mod.db.remainingTime end,
            set = function(_, v) mod.db.remainingTime = v end,
        },

        { type = "spacer", height = 8 },
        { type = "header", text = "Spell-Filter" },

        {
            type = "toggle", label = "Spell-Namen anzeigen",
            tooltip = "Zeigt den Namen des Spells unter dem Icon.",
            get = function() return mod.db.showSpellName end,
            set = function(_, v) mod.db.showSpellName = v end,
        },
        {
            type = "toggle", label = "Filter umkehren (Whitelist statt Blacklist)",
            tooltip = "Aus: Liste = ignorierte Spells. An: Liste = NUR diese Spells zeigen.",
            get = function() return mod.db.invertIgnored end,
            set = function(_, v) mod.db.invertIgnored = v end,
        },
        {
            type = "editbox", label = "Spell-Liste (komma-getrennt)",
            width = 400,
            tooltip = "Spell-Namen exakt wie im Spiel, komma-getrennt. Auch Spell-IDs möglich.",
            get = function() return mod.db.ignoredSpells end,
            set = function(_, v) mod.db.ignoredSpells = v end,
        },
    }
end

-- =========================================================
-- Slash-Commands
-- =========================================================
SLASH_VCUI_DCP1 = "/dcp"
SLASH_VCUI_DCP2 = "/cooldownpulse"
SlashCmdList.VCUI_DCP = function() SlashCmdList["VULOCLASSICUI"]("cooldownpulse") end
