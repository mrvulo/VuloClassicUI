-- =========================================================
-- VuloClassicUI / Modules / CombatText
-- Custom scrolling combat text engine.
-- Anniversary disabled Blizzard's old player FCT, hence custom:
--   - FontString pool, animated scroll + fade
--   - CLEU + REGEN events trigger spawnMessage
-- Additionally: WorldTextScale (engine FCT above mob/pet) stays.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("combattext", {
    name        = "Combat Text",
    group       = "QoL",
    description = "Custom floating combat text engine with configurable events, color, size and position.",
    defaults    = {
        enabled        = true,
        -- Master categories (quick on/off, do NOT override per-event enabled)
        showCombatState     = true,   -- combatStart + combatEnd
        showCombatLog       = true,   -- spellInterrupt + dispels + missed
        showDurability      = true,   -- lowDurability
        -- Font (global) — path as value
        fontFace       = "Interface\\AddOns\\VuloClassicUI\\Media\\Fonts\\Expressway.TTF",
        -- Change DAMAGE_TEXT_FONT (Blizzard's mob FCT) at the same time as fontFace
        applyToMobFCT  = true,
        -- Per-event customization (color, size, outline, shadow + shadowColor + shadowOffset)
        events = {
            combatStart    = { enabled = true, color = { r = 1.0, g = 0.4, b = 0.4 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            combatEnd      = { enabled = true, color = { r = 0.6, g = 0.9, b = 0.6 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            spellInterrupt = { enabled = true, color = { r = 1.0, g = 1.0, b = 0.3 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            dispels        = { enabled = true, color = { r = 0.6, g = 0.9, b = 1.0 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            missed         = { enabled = true, color = { r = 1.0, g = 0.7, b = 0.2 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            lowDurability  = { enabled = true, color = { r = 1.0, g = 0.3, b = 0.3 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
        },
        -- Low durability threshold (percent)
        durabilityThreshold = 15,
        -- Engine FCT
        worldTextScale = 1.0,
        sharpFonts     = true,
        -- Global defaults (for events with size=0 or outline/shadow=nil)
        fontSize       = 18,
        color          = { r = 1, g = 1, b = 0 },
        scrollDuration = 2.0,
        scrollDistance = 80,
        fontOutline    = true,
        fontShadow     = true,
        shadowX        = 2,
        shadowY        = -2,
        -- Position
        x              = 0,
        y              = 0,
        unlocked       = false,
        centerOnScreen = false,
    },
})

-- =========================================================
-- Custom scrolling text engine
-- =========================================================
local container       -- anchor frame
local moverFrame      -- mover for position
local POOL_SIZE = 20
local fontStringPool = {}
local activeMessages = {}

-- Available fonts (Expressway + Blizzard built-ins, always available)
local EXPRESSWAY_PATH = "Interface\\AddOns\\VuloClassicUI\\Media\\Fonts\\Expressway.TTF"
local FONT_VALUES = {
    { value = EXPRESSWAY_PATH,         text = L["Expressway (Default)"] },
    { value = "Fonts\\FRIZQT__.TTF",   text = L["Friz Quadrata (Blizzard)"] },
    { value = "Fonts\\ARIALN.TTF",     text = L["Arial Narrow"] },
    { value = "Fonts\\MORPHEUS.TTF",   text = L["Morpheus"] },
    { value = "Fonts\\skurri.ttf",     text = L["Skurri"] },
}

local function getActiveFontPath()
    local saved = mod.db and mod.db.fontFace
    if saved and saved ~= "" then return saved end
    return EXPRESSWAY_PATH
end

local function applyStyleToFS(fs, size, outlineOverride, shadowOverride, shadowColor, shadowX, shadowY)
    local outline = (outlineOverride ~= nil) and outlineOverride or mod.db.fontOutline
    local shadow  = (shadowOverride  ~= nil) and shadowOverride  or mod.db.fontShadow
    local flags = outline and "THICKOUTLINE" or ""
    fs:SetFont(getActiveFontPath(), size or mod.db.fontSize or 18, flags)
    if shadow then
        local sc = shadowColor or { r = 0, g = 0, b = 0 }
        fs:SetShadowColor(sc.r or 0, sc.g or 0, sc.b or 0, 1)
        fs:SetShadowOffset(shadowX or mod.db.shadowX or 2, shadowY or mod.db.shadowY or -2)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function createContainer()
    if container then return container end
    container = CreateFrame("Frame", "VCUI_CombatTextContainer", UIParent)
    container:SetSize(200, 1)
    container:SetFrameStrata("HIGH")
    container:Show()
    -- Pre-create FontStrings (pool)
    for i = 1, POOL_SIZE do
        local fs = container:CreateFontString(nil, "OVERLAY")
        applyStyleToFS(fs)
        fs:Hide()
        table.insert(fontStringPool, fs)
    end
    -- OnUpdate animates all active messages
    container:SetScript("OnUpdate", function(_, elapsed)
        for i = #activeMessages, 1, -1 do
            local m = activeMessages[i]
            m.t = m.t + elapsed
            local p = m.t / m.dur
            if p >= 1 then
                m.fs:Hide()
                m.fs:ClearAllPoints()
                table.insert(fontStringPool, m.fs)
                table.remove(activeMessages, i)
            else
                m.fs:ClearAllPoints()
                m.fs:SetPoint("CENTER", container, "CENTER", 0, p * m.dist)
                m.fs:SetAlpha(1 - p)
            end
        end
    end)
    return container
end

local function getAnchor()
    if mod.db.centerOnScreen then return UIParent end
    return _G.PlayerFrameHealthBar or _G.PlayerFrame or UIParent
end

local function reAnchorContainer()
    if not container then return end
    local anchor = getAnchor()
    container:ClearAllPoints()
    if mod.db.centerOnScreen then
        container:SetPoint("CENTER", anchor, "CENTER", mod.db.x or 0, mod.db.y or 0)
    else
        container:SetPoint("BOTTOM", anchor, "TOP", mod.db.x or 0, 25 + (mod.db.y or 0))
    end
end

local function applyFontToPool()
    local size = mod.db.fontSize or 18
    for _, fs in ipairs(fontStringPool) do applyStyleToFS(fs, size) end
    for _, m in ipairs(activeMessages) do applyStyleToFS(m.fs, size) end
end

-- Mapping event key -> master category toggle
local EVENT_CATEGORY = {
    combatStart    = "showCombatState",
    combatEnd      = "showCombatState",
    spellInterrupt = "showCombatLog",
    dispels        = "showCombatLog",
    missed         = "showCombatLog",
    lowDurability  = "showDurability",
}

local function spawnEvent(eventKey, text)
    if not text or text == "" then return end
    local ev = mod.db.events and mod.db.events[eventKey]
    if not ev or ev.enabled == false then return end
    -- Master category filter (quick on/off)
    local cat = EVENT_CATEGORY[eventKey]
    if cat and mod.db[cat] == false then return end
    createContainer()
    local fs = table.remove(fontStringPool)
    if not fs then
        local oldest = table.remove(activeMessages, 1)
        if oldest then fs = oldest.fs else return end
    end
    -- Per-event style: size override + outline + shadow + shadowColor + offsets
    local sz = (ev.size and ev.size > 0) and ev.size or nil
    applyStyleToFS(fs, sz, ev.outline, ev.shadow, ev.shadowColor, ev.shadowX, ev.shadowY)
    fs:SetText(text)
    local c = ev.color or mod.db.color or { r = 1, g = 1, b = 1 }
    fs:SetTextColor(c.r or 1, c.g or 1, c.b or 1, 1)
    fs:SetAlpha(1)
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", container, "CENTER", 0, 0)
    fs:Show()
    table.insert(activeMessages, {
        fs = fs, t = 0,
        dur = mod.db.scrollDuration or 2.0,
        dist = mod.db.scrollDistance or 80,
    })
end

-- =========================================================
-- Event handlers
-- =========================================================
local playerGUID

-- Equipment slots for durability check
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18 }
local _durabilityPending = false
local _wasLowDurability  = false

local function doCheckDurability()
    if not mod._enabled or not mod.db then return end
    local ev = mod.db.events and mod.db.events.lowDurability
    if not ev or ev.enabled == false then return end
    -- Don't warn in combat (comes after REGEN_ENABLED)
    if InCombatLockdown() then return end

    local threshold = (mod.db.durabilityThreshold or 15) / 100
    local hasLow = false
    for _, slot in ipairs(EQUIP_SLOTS) do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            if (current / maximum) < threshold then
                hasLow = true
                break
            end
        end
    end

    -- Edge-triggered: only spawn if previously OK and now low (no spam)
    if hasLow and not _wasLowDurability then
        spawnEvent("lowDurability", L["LOW DURABILITY"])
    end
    _wasLowDurability = hasLow
end

local function scheduleDurabilityCheck()
    if _durabilityPending then return end
    _durabilityPending = true
    C_Timer.After(0.5, function()
        _durabilityPending = false
        doCheckDurability()
    end)
end

local function onCombatStart()
    if not mod._enabled then return end
    spawnEvent("combatStart", L["+Combat"])
end
local function onCombatEnd()
    if not mod._enabled then return end
    spawnEvent("combatEnd", L["-Combat"])
    -- Check durability after combat exit
    scheduleDurabilityCheck()
end

local function onCLEU()
    if not mod._enabled then return end
    if not playerGUID then
        playerGUID = UnitGUID("player")
        if not playerGUID then return end
    end
    local _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _,
          _, spellName, _, extraSpellId, extraSpellName, _, missType
          = CombatLogGetCurrentEventInfo()

    if subEvent == "SPELL_INTERRUPT" and sourceGUID == playerGUID then
        spawnEvent("spellInterrupt", L["Interrupted: "] .. (extraSpellName or spellName or "?"))
    elseif subEvent == "SPELL_DISPEL" and sourceGUID == playerGUID then
        spawnEvent("dispels", L["Dispelled: "] .. (extraSpellName or "?"))
    elseif subEvent == "SPELL_STOLEN" and sourceGUID == playerGUID then
        spawnEvent("dispels", L["Purged: "] .. (extraSpellName or "?"))
    elseif (subEvent == "SWING_MISSED" or subEvent == "RANGE_MISSED" or subEvent == "SPELL_MISSED")
        and destGUID == playerGUID then
        local realMissType
        if subEvent == "SWING_MISSED" then
            -- SWING_MISSED payload: missType(12), isOffHand(13), amount(14)
            realMissType = select(12, CombatLogGetCurrentEventInfo())
        else
            -- SPELL_MISSED / RANGE_MISSED payload: spellId(12), spellName(13),
            -- spellSchool(14), missType(15). The earlier destructure read the
            -- wrong field, so spell/ranged misses always showed "Missed".
            realMissType = select(15, CombatLogGetCurrentEventInfo())
        end
        local label = realMissType or "Missed"
        if label == "PARRY"  then label = L["Parried"]
        elseif label == "DODGE" then label = L["Dodged"]
        elseif label == "MISS"  then label = L["Missed"]
        elseif label == "BLOCK" then label = L["Blocked"]
        elseif label == "ABSORB" then label = L["Absorbed"]
        end
        spawnEvent("missed", label)
    end
end

-- =========================================================
-- Hit indicator font sharpening (PetHitIndicator, NumberFont*)
-- =========================================================
local FONTS_TO_SHARPEN = {
    "NumberFont_Outline_Huge", "NumberFont_Outline_Large", "NumberFont_Outline_Med",
    "NumberFontNormalHuge", "PetHitIndicator", "PlayerHitIndicator",
}

local function applySharpFonts()
    if not mod.db.sharpFonts then return end
    local font = getActiveFontPath()
    for _, name in ipairs(FONTS_TO_SHARPEN) do
        local f = _G[name]
        if f and f.SetFont and f.GetFont then
            local _, size, flags = f:GetFont()
            size = size or 16
            flags = flags or "OUTLINE"
            if not flags:find("OUTLINE") then
                flags = flags .. ",OUTLINE"
            end
            pcall(f.SetFont, f, font, size, flags)
        end
    end
end

-- Blizzard mob FCT font (DAMAGE_TEXT_FONT global + CombatTextFont) — like VuloUI
local function applyDamageTextFont()
    if not mod.db or mod.db.applyToMobFCT == false then return end
    local path = getActiveFontPath()
    _G.DAMAGE_TEXT_FONT = path
    if _G.CombatTextFont and _G.CombatTextFont.SetFont then
        pcall(_G.CombatTextFont.SetFont, _G.CombatTextFont, path, 120, "")
    end
end

local function applyWorldTextScale()
    local v = tostring(mod.db.worldTextScale or 1.0)
    pcall(SetCVar, "WorldTextScale",  v)
    pcall(SetCVar, "damageTextScale", v)
end

-- =========================================================
-- Mover (for position of the custom engine)
-- =========================================================
local function applyMoverPosition()
    if moverFrame then
        local anchor = getAnchor()
        moverFrame:ClearAllPoints()
        if mod.db.centerOnScreen then
            moverFrame:SetPoint("CENTER", anchor, "CENTER", mod.db.x or 0, mod.db.y or 0)
        else
            moverFrame:SetPoint("BOTTOM", anchor, "TOP", mod.db.x or 0, 25 + (mod.db.y or 0))
        end
    end
    reAnchorContainer()
end

local function createMover()
    if moverFrame then return moverFrame end
    moverFrame = CreateFrame("Frame", "VCUI_CombatTextMover", UIParent)
    moverFrame:SetSize(200, 60)
    moverFrame:SetFrameStrata("HIGH")
    moverFrame:EnableMouse(true)
    moverFrame:SetMovable(true)
    moverFrame:Hide()

    local bg = moverFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(moverFrame)
    bg:SetColorTexture(0.6, 0.4, 1.0, 0.4)
    moverFrame.label = moverFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    moverFrame.label:SetPoint("CENTER", moverFrame, "CENTER", 0, 0)
    moverFrame.label:SetText(L["|cffffffffCOMBAT TEXT|r"])

    moverFrame:RegisterForDrag("LeftButton")
    moverFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    moverFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a = getAnchor()
        if not a then return end
        local mx, my = self:GetCenter()
        local ax, ay = a:GetCenter()
        local _, ah = a:GetSize()
        local _, mh = self:GetSize()
        if mod.db.centerOnScreen then
            mod.db.x = mx - ax
            mod.db.y = my - ay
        else
            mod.db.x = mx - ax
            mod.db.y = my - ay - ah/2 - 25 - mh/2
        end
        applyMoverPosition()
    end)

    moverFrame:EnableKeyboard(true)
    moverFrame:SetPropagateKeyboardInput(true)
    moverFrame:SetScript("OnKeyDown", function(self, key)
        if not mod.db.unlocked then
            self:SetPropagateKeyboardInput(true); return
        end
        local step = IsShiftKeyDown() and 5 or 1
        local dx, dy = 0, 0
        if     key == "UP"    then dy =  step
        elseif key == "DOWN"  then dy = -step
        elseif key == "LEFT"  then dx = -step
        elseif key == "RIGHT" then dx =  step
        else self:SetPropagateKeyboardInput(true); return end
        self:SetPropagateKeyboardInput(false)
        mod.db.x = (mod.db.x or 0) + dx
        mod.db.y = (mod.db.y or 0) + dy
        applyMoverPosition()
    end)
    return moverFrame
end

local function setUnlocked(state)
    mod.db.unlocked = state
    createMover()
    applyMoverPosition()
    if state then
        moverFrame:Show()
        ns:Print(L["Combat Text mover active. Drag or arrow keys (SHIFT=5px)."])
    else
        moverFrame:Hide()
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    if not mod.db then return end  -- defensive: DB not initialized
    playerGUID = UnitGUID("player")
    createContainer()
    reAnchorContainer()
    applySharpFonts()
    applyWorldTextScale()
    applyDamageTextFont()

    ns:RegisterEvent("PLAYER_REGEN_DISABLED", onCombatStart)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",  onCombatEnd)
    ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    ns:RegisterEvent("UPDATE_INVENTORY_DURABILITY", scheduleDurabilityCheck)

    -- Initial durability check (delayed, so inventory is loaded)
    C_Timer.After(2.0, scheduleDurabilityCheck)
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED", onCombatStart)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",  onCombatEnd)
    ns:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    ns:UnregisterEvent("UPDATE_INVENTORY_DURABILITY", scheduleDurabilityCheck)
    if container then container:Hide() end
    if moverFrame then moverFrame:Hide() end  -- don't leave the mover orphaned
end

-- =========================================================
-- Options
-- =========================================================
local function openColorPicker(getCurrent, setNew)
    local c = getCurrent() or { r = 1, g = 1, b = 1 }
    local function onChange()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        setNew({ r = r, g = g, b = b })
    end
    local function onCancel(prev) if prev then setNew(prev) end end
    local info = {
        r = c.r, g = c.g, b = c.b,
        swatchFunc = onChange, cancelFunc = onCancel, opacity = false,
    }
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    elseif _G.OpenColorPicker then
        _G.OpenColorPicker(info)
    end
end

local function eventSection(key, label, previewText)
    local function ev() return mod.db.events[key] end
    return {
        { type = "group", layout = "row", gap = 6,
          items = {
              { type = "toggle", label = L["Enabled"],
                get = function() return ev().enabled end,
                set = function(_, v) ev().enabled = v end },
              { type = "button", label = L["Text color..."], width = 110,
                onClick = function()
                    openColorPicker(function() return ev().color end,
                        function(c) ev().color = c end)
                end },
              { type = "button", label = L["Shadow color..."], width = 130,
                onClick = function()
                    openColorPicker(function() return ev().shadowColor end,
                        function(c) ev().shadowColor = c end)
                end },
              { type = "button", label = L["Test"], width = 70,
                onClick = function() spawnEvent(key, previewText) end },
          },
        },
        { type = "slider", label = L["Font Size (0 = global)"],
          min = 0, max = 32, step = 1,
          get = function() return ev().size or 0 end,
          set = function(_, v) ev().size = v end },
        { type = "group", layout = "row", gap = 8,
          items = {
              { type = "toggle", label = L["Outline"],
                get = function() return ev().outline end,
                set = function(_, v) ev().outline = v end },
              { type = "toggle", label = L["Shadow"],
                get = function() return ev().shadow end,
                set = function(_, v) ev().shadow = v end },
          },
        },
        { type = "slider", label = L["Shadow X Offset"],
          min = -10, max = 10, step = 1,
          get = function() return ev().shadowX or 2 end,
          set = function(_, v) ev().shadowX = v end },
        { type = "slider", label = L["Shadow Y Offset"],
          min = -10, max = 10, step = 1,
          get = function() return ev().shadowY or -2 end,
          set = function(_, v) ev().shadowY = v end },
    }
end

function mod:GetOptions()
    local items = {
        { type = "header", text = L["Combat Text"] },
        { type = "desc",
          text = L["|cffaaaaaaCustom scrolling text engine above the player. Anniversary disabled Blizzard's old player FCT. Each event can have its own color + size + outline/shadow.|r"] },

        -- Master categories (quick on/off — do not override per-event, but add a filter on top)
        { type = "spacer", height = 6 },
        { type = "header", text = L["Categories (Quick on/off)"] },
        { type = "group", layout = "row", gap = 8,
          items = {
              { type = "toggle", label = L["Combat State (+/- Combat)"],
                tooltip = L["Combat start and combat end messages."],
                get = function() return mod.db.showCombatState ~= false end,
                set = function(_, v) mod.db.showCombatState = v end },
              { type = "toggle", label = L["Combat Log Events"],
                tooltip = L["Interrupts, dispels, misses (Parry/Dodge/Block)."],
                get = function() return mod.db.showCombatLog ~= false end,
                set = function(_, v) mod.db.showCombatLog = v end },
              { type = "toggle", label = L["Durability Warning"],
                tooltip = L["Low durability after combat exit."],
                get = function() return mod.db.showDurability ~= false end,
                set = function(_, v) mod.db.showDurability = v end },
          },
        },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Global Defaults"] },
        -- Font dropdown (adopts the VuloUI pattern)
        { type = "dropdown", label = L["Font"],
          tooltip = L["Font for our combat text engine. Also used for Blizzard's mob FCT (DAMAGE_TEXT_FONT) when enabled below."],
          values = FONT_VALUES,
          get = function() return getActiveFontPath() end,
          set = function(_, v)
              mod.db.fontFace = v
              applyFontToPool()
              applySharpFonts()
              applyDamageTextFont()
          end },
        { type = "toggle", label = L["Also apply font to Blizzard mob FCT"],
          tooltip = L["Additionally sets DAMAGE_TEXT_FONT globally - changes the font of the damage numbers above mobs/pets. Requires /reload to take effect."],
          get = function() return mod.db.applyToMobFCT ~= false end,
          set = function(_, v) mod.db.applyToMobFCT = v; applyDamageTextFont() end },
        { type = "slider", label = L["Default Font Size"],
          min = 10, max = 32, step = 1,
          get = function() return mod.db.fontSize end,
          set = function(_, v) mod.db.fontSize = v; applyFontToPool() end },
        { type = "toggle", label = L["Default: Thick Outline"],
          get = function() return mod.db.fontOutline end,
          set = function(_, v) mod.db.fontOutline = v end },
        { type = "toggle", label = L["Default: Shadow"],
          get = function() return mod.db.fontShadow end,
          set = function(_, v) mod.db.fontShadow = v end },
        { type = "slider", label = L["Scroll Duration (sec.)"],
          min = 0.5, max = 5.0, step = 0.1,
          get = function() return mod.db.scrollDuration end,
          set = function(_, v) mod.db.scrollDuration = v end },
        { type = "slider", label = L["Scroll Distance (px)"],
          min = 20, max = 200, step = 5,
          get = function() return mod.db.scrollDistance end,
          set = function(_, v) mod.db.scrollDistance = v end },
        { type = "button", label = L["Test (all events)"], width = 200,
          onClick = function()
              spawnEvent("combatStart",    L["+Combat"])
              C_Timer.After(0.4, function() spawnEvent("spellInterrupt", L["Interrupted: Frostbolt"]) end)
              C_Timer.After(0.8, function() spawnEvent("dispels",        L["Dispelled: Curse"]) end)
              C_Timer.After(1.2, function() spawnEvent("missed",         L["Parried"]) end)
          end },
    }

    -- Per-event customization — each event is a collapsed section (click to expand)
    table.insert(items, { type = "spacer", height = 8 })
    table.insert(items, { type = "header", text = L["Per-Event Customization"] })
    table.insert(items, { type = "section", title = L["+Combat"],        collapsed = true,
        items = eventSection("combatStart",    L["+Combat"],        L["+Combat"]) })
    table.insert(items, { type = "section", title = L["-Combat"],        collapsed = true,
        items = eventSection("combatEnd",      L["-Combat"],        L["-Combat"]) })
    table.insert(items, { type = "section", title = L["Interrupted"],    collapsed = true,
        items = eventSection("spellInterrupt", L["Interrupted"],    L["Interrupted: Frostbolt"]) })
    table.insert(items, { type = "section", title = L["Dispelled/Purged"], collapsed = true,
        items = eventSection("dispels",        L["Dispelled/Purged"], L["Dispelled: Curse"]) })
    table.insert(items, { type = "section", title = L["Parried/Dodged/Missed"], collapsed = true,
        items = eventSection("missed",         L["Parried/Dodged/Missed"], L["Parried"]) })

    -- Low durability section includes its threshold slider
    local lowDuraItems = eventSection("lowDurability", L["Low Durability"], L["LOW DURABILITY"])
    table.insert(lowDuraItems, { type = "slider", label = L["Durability Threshold (%)"],
        min = 5, max = 50, step = 1,
        tooltip = L["Warning appears when at least one equipped item is below this value (after combat exit)."],
        get = function() return mod.db.durabilityThreshold or 15 end,
        set = function(_, v)
            mod.db.durabilityThreshold = v
            _wasLowDurability = false
            scheduleDurabilityCheck()
        end })
    table.insert(items, { type = "section", title = L["Low Durability"], collapsed = true, items = lowDuraItems })

    -- Engine FCT (collapsed)
    table.insert(items, { type = "section", title = L["Engine FCT (above mob/pet)"], collapsed = true, items = {
        { type = "toggle", label = L["Sharper hit indicator font (Friz Quadrata)"],
          get = function() return mod.db.sharpFonts end,
          set = function(_, v) mod.db.sharpFonts = v; applySharpFonts() end },
        { type = "slider", label = L["Engine FCT Scale"],
          min = 1.0, max = 2.5, step = 0.1,
          tooltip = L["Damage numbers above mob/pet — bitmap scaling."],
          get = function() return mod.db.worldTextScale end,
          set = function(_, v) mod.db.worldTextScale = v; applyWorldTextScale() end },
    } })

    -- Position (collapsed)
    table.insert(items, { type = "section", title = L["Position"], collapsed = true, items = {
        { type = "toggle", label = L["Center"],
          tooltip = L["Keeps the horizontal position and only centers vertically in the screen center."],
          get = function() return mod.db.centerOnScreen end,
          set = function(_, v)
              local prev = mod.db.centerOnScreen
              mod.db.centerOnScreen = v
              local ct = container
              if v and not prev and ct then
                  local fcx = ct:GetCenter()
                  local px  = UIParent:GetCenter()
                  if fcx and px then mod.db.x = fcx - px; mod.db.y = 0 end
              elseif not v and prev and ct then
                  local anchor = _G.PlayerFrameHealthBar or _G.PlayerFrame
                  local fcx, fcy = ct:GetCenter()
                  if anchor and fcx and fcy then
                      local acx, atop = anchor:GetCenter(), anchor:GetTop()
                      if acx and atop then
                          mod.db.x = fcx - acx
                          mod.db.y = fcy - atop - 25
                      end
                  end
              end
              applyMoverPosition()
          end },
        { type = "group", layout = "row", gap = 8,
          items = {
              { type = "button", label = L["Unlock / Position"], width = 200,
                onClick = function() setUnlocked(not mod.db.unlocked) end },
              { type = "button", label = L["Reset Position"], width = 180,
                onClick = function()
                    mod.db.x = 0; mod.db.y = 0
                    applyMoverPosition()
                end },
          },
        },
    } })

    return items
end
