-- =========================================================
-- VuloClassicUI / Modules / CombatText
-- Two on-screen systems sharing one position:
--   1. NOTIFICATIONS (combatStart / combatEnd / lowDurability)
--      flash in place and stack vertically, centred on the anchor.
--      lowDurability is persistent (stays until the gear is repaired).
--      A Preview mode shows all three at once for styling/positioning.
--   2. SCROLLING combat-log text (interrupts / dispels / misses)
--      floats upward and fades, like classic FCT.
-- Anniversary disabled Blizzard's old player FCT, hence the custom engine.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("combattext", {
    name        = "Combat Text",
    group       = "HUD",
    description = "Flashing combat notifications (with live preview) plus a scrolling combat-log text engine.",
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
        -- The three notification events also carry an editable `text`.
        events = {
            combatStart    = { enabled = true, text = "", color = { r = 0.93, g = 0.26, b = 0.0 }, size = 0, outline = true, shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            combatEnd      = { enabled = true, text = "", color = { r = 0.6, g = 0.9, b = 0.6 }, size = 0, outline = true, shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            spellInterrupt = { enabled = true, color = { r = 1.0, g = 1.0, b = 0.3 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            dispels        = { enabled = true, color = { r = 0.6, g = 0.9, b = 1.0 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            missed         = { enabled = true, color = { r = 1.0, g = 0.7, b = 0.2 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            lowDurability  = { enabled = true, text = "", color = { r = 1.0, g = 0.3, b = 0.3 }, size = 0, outline = true, shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
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
        flashDuration  = 1.5,           -- notification flash fade time
        fontOutlineMode = "THICKOUTLINE", -- NONE | OUTLINE | THICKOUTLINE
        fontOutline    = true,          -- legacy fallback for fontOutlineMode
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
-- Shared state + forward declarations (resolve def-order cycles)
-- =========================================================
local container       -- anchor frame (both systems centre on it)
local moverFrame      -- mover for position
local POOL_SIZE = 20
local fontStringPool = {}
local activeMessages = {}   -- scrolling messages
local notifyFrames   = {}   -- key -> flash/persistent notification frame
local isPreview      = false

local NOTIFY_TYPES   = { "combatStart", "combatEnd", "lowDurability" }
local NOTIFY_SET     = { combatStart = true, combatEnd = true, lowDurability = true }
local NOTIFY_SPACING = 6

local showNotify, hideNotify, doCheckDurability, scheduleDurabilityCheck

-- =========================================================
-- Fonts
-- =========================================================
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

-- Resolve an outline override (per-event boolean, explicit string, or nil ->
-- the global dropdown) into a SetFont flag string.
local function resolveOutline(outlineOverride)
    local mode
    if type(outlineOverride) == "string" then mode = outlineOverride
    elseif outlineOverride == true       then mode = "THICKOUTLINE"
    elseif outlineOverride == false      then mode = "NONE"
    else mode = mod.db.fontOutlineMode or (mod.db.fontOutline and "THICKOUTLINE" or "OUTLINE") end
    return (mode == "NONE") and "" or mode
end

local function applyStyleToFS(fs, size, outlineOverride, shadowOverride, shadowColor, shadowX, shadowY)
    local shadow = (shadowOverride ~= nil) and shadowOverride or mod.db.fontShadow
    local flags  = resolveOutline(outlineOverride)
    fs:SetFont(getActiveFontPath(), size or mod.db.fontSize or 18, flags)
    if shadow then
        local sc = shadowColor or { r = 0, g = 0, b = 0 }
        fs:SetShadowColor(sc.r or 0, sc.g or 0, sc.b or 0, 1)
        fs:SetShadowOffset(shadowX or mod.db.shadowX or 2, shadowY or mod.db.shadowY or -2)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- =========================================================
-- Scrolling engine
-- =========================================================
local function createContainer()
    if container then return container end
    container = CreateFrame("Frame", "VCUI_CombatTextContainer", UIParent)
    container:SetSize(200, 1)
    container:SetFrameStrata("HIGH")
    container:Show()
    for i = 1, POOL_SIZE do
        local fs = container:CreateFontString(nil, "OVERLAY")
        applyStyleToFS(fs)
        fs:Hide()
        table.insert(fontStringPool, fs)
    end
    return container
end

-- Animates active scroll messages; self-detaches when the list empties.
local function animateMessages(self, elapsed)
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
    if #activeMessages == 0 then
        self:SetScript("OnUpdate", nil)
    end
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

-- Mapping event key -> master category toggle
local EVENT_CATEGORY = {
    combatStart    = "showCombatState",
    combatEnd      = "showCombatState",
    spellInterrupt = "showCombatLog",
    dispels        = "showCombatLog",
    missed         = "showCombatLog",
    lowDurability  = "showDurability",
}

local function spawnScroll(eventKey, text)
    if not text or text == "" then return end
    if isPreview then return end
    local ev = mod.db.events and mod.db.events[eventKey]
    if not ev or ev.enabled == false then return end
    local cat = EVENT_CATEGORY[eventKey]
    if cat and mod.db[cat] == false then return end
    createContainer()
    local fs = table.remove(fontStringPool)
    if not fs then
        local oldest = table.remove(activeMessages, 1)
        if oldest then fs = oldest.fs else return end
    end
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
    container:SetScript("OnUpdate", animateMessages)
end

-- =========================================================
-- Notification engine (flash + stack, centred on the container)
-- =========================================================
local FALLBACK_TEXT = {
    combatStart   = L["+Combat"],
    combatEnd     = L["-Combat"],
    lowDurability = L["LOW DURABILITY"],
}

local function notifyText(key)
    local ev = mod.db.events and mod.db.events[key]
    if ev and ev.text and ev.text ~= "" then return ev.text end
    return FALLBACK_TEXT[key] or ""
end

local function getNotifyFrame(key)
    if notifyFrames[key] then return notifyFrames[key] end
    createContainer()
    local f = CreateFrame("Frame", nil, container)
    f:SetSize(200, 30)
    f:Hide()
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetAllPoints(f)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    f.text = fs
    f.gen  = 0
    notifyFrames[key] = f
    return f
end

-- Style + size a notification frame to its text. Outline follows the global
-- dropdown (pass nil), shadow stays per-event.
local function styleNotify(f, key)
    local ev = mod.db.events and mod.db.events[key] or {}
    local sz = (ev.size and ev.size > 0) and ev.size or (mod.db.fontSize or 18)
    applyStyleToFS(f.text, sz, nil, ev.shadow, ev.shadowColor, ev.shadowX, ev.shadowY)
    f.text:SetText(notifyText(key))
    local c = ev.color or { r = 1, g = 1, b = 1 }
    f.text:SetTextColor(c.r or 1, c.g or 1, c.b or 1, 1)
    local w = math.max(f.text:GetStringWidth() or 0, 50)
    local h = math.max(f.text:GetStringHeight() or 0, 14)
    f:SetSize(w + 6, h + 2)
end

-- Stack the visible notifications as a vertically-centred block.
local function arrangeNotify()
    if not container then return end
    local visible, totalH = {}, 0
    for _, k in ipairs(NOTIFY_TYPES) do
        local f = notifyFrames[k]
        if f and f:IsShown() then
            visible[#visible + 1] = f
            totalH = totalH + f:GetHeight()
        end
    end
    if #visible == 0 then return end
    totalH = totalH + NOTIFY_SPACING * (#visible - 1)
    local cursor = totalH / 2
    for _, f in ipairs(visible) do
        local h = f:GetHeight()
        f:ClearAllPoints()
        f:SetPoint("CENTER", container, "CENTER", 0, cursor - h / 2)
        cursor = cursor - h - NOTIFY_SPACING
    end
end

showNotify = function(key)
    if not mod._enabled or isPreview then return end
    local ev = mod.db.events and mod.db.events[key]
    if not ev or ev.enabled == false then return end
    local cat = EVENT_CATEGORY[key]
    if cat and mod.db[cat] == false then return end
    createContainer()
    local f = getNotifyFrame(key)
    styleNotify(f, key)
    if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(f) end
    f:SetAlpha(1)
    f:Show()
    arrangeNotify()
    if key ~= "lowDurability" then
        -- transient flash -> fade out and hide
        f.gen = f.gen + 1
        local myGen = f.gen
        local dur = mod.db.flashDuration or 1.5
        if UIFrameFadeOut then UIFrameFadeOut(f, dur, 1, 0) end
        C_Timer.After(dur, function()
            if f.gen == myGen and not isPreview then
                f:Hide()
                arrangeNotify()
            end
        end)
    end
end

hideNotify = function(key)
    local f = notifyFrames[key]
    if not f then return end
    if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(f) end
    f:Hide()
    arrangeNotify()
end

local function applyFontToNotify()
    for k, f in pairs(notifyFrames) do
        if f.text then styleNotify(f, k) end
    end
    arrangeNotify()
end

-- ── Preview (Options page) ──────────────────────────────────────────────
local function showPreview()
    if not mod.db then return end
    createContainer()
    isPreview = true
    for _, k in ipairs(NOTIFY_TYPES) do
        local f = getNotifyFrame(k)
        if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(f) end
        styleNotify(f, k)
        f:SetAlpha(1)
        f:Show()
    end
    arrangeNotify()
end

local function hidePreview()
    isPreview = false
    for _, k in ipairs(NOTIFY_TYPES) do
        local f = notifyFrames[k]
        if f then
            if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(f) end
            f:Hide()
        end
    end
    arrangeNotify()
    -- restore the real persistent low-durability state
    if not InCombatLockdown() then scheduleDurabilityCheck() end
end

local function isPreviewOn() return isPreview end

local function applyFontToPool()
    local size = mod.db.fontSize or 18
    for _, fs in ipairs(fontStringPool) do applyStyleToFS(fs, size) end
    for _, m in ipairs(activeMessages) do applyStyleToFS(m.fs, size) end
end

-- =========================================================
-- Durability (persistent notification while out of combat)
-- =========================================================
local playerGUID
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18 }
local _durabilityPending = false

doCheckDurability = function()
    if not mod._enabled or not mod.db then return end
    if isPreview then return end
    local ev = mod.db.events and mod.db.events.lowDurability
    if not ev or ev.enabled == false or mod.db.showDurability == false then
        hideNotify("lowDurability"); return
    end
    if InCombatLockdown() then hideNotify("lowDurability"); return end

    local threshold = (mod.db.durabilityThreshold or 15) / 100
    local hasLow = false
    for _, slot in ipairs(EQUIP_SLOTS) do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 and (current / maximum) < threshold then
            hasLow = true
            break
        end
    end

    if hasLow then showNotify("lowDurability") else hideNotify("lowDurability") end
end

scheduleDurabilityCheck = function()
    if _durabilityPending then return end
    _durabilityPending = true
    C_Timer.After(0.5, function()
        _durabilityPending = false
        doCheckDurability()
    end)
end

-- =========================================================
-- Combat events
-- =========================================================
local function onCombatStart()
    if not mod._enabled then return end
    hideNotify("lowDurability")   -- never warn during combat
    showNotify("combatStart")
end

local function onCombatEnd()
    if not mod._enabled then return end
    showNotify("combatEnd")
    scheduleDurabilityCheck()
end

-- Only these subevents ever produce combat text. Reading just the subevent
-- first lets the hot path bail before the full 18-value destructure.
local CLEU_WANTED = {
    SPELL_INTERRUPT = true, SPELL_DISPEL = true, SPELL_STOLEN = true,
    SWING_MISSED    = true, RANGE_MISSED = true, SPELL_MISSED = true,
}
local function onCLEU()
    if not mod._enabled then return end
    if not CLEU_WANTED[select(2, CombatLogGetCurrentEventInfo())] then return end
    if not playerGUID then
        playerGUID = UnitGUID("player")
        if not playerGUID then return end
    end
    local _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _,
          _, spellName, _, extraSpellId, extraSpellName, _, missType
          = CombatLogGetCurrentEventInfo()

    if subEvent == "SPELL_INTERRUPT" and sourceGUID == playerGUID then
        spawnScroll("spellInterrupt", L["Interrupted: "] .. (extraSpellName or spellName or "?"))
    elseif subEvent == "SPELL_DISPEL" and sourceGUID == playerGUID then
        spawnScroll("dispels", L["Dispelled: "] .. (extraSpellName or "?"))
    elseif subEvent == "SPELL_STOLEN" and sourceGUID == playerGUID then
        spawnScroll("dispels", L["Purged: "] .. (extraSpellName or "?"))
    elseif (subEvent == "SWING_MISSED" or subEvent == "RANGE_MISSED" or subEvent == "SPELL_MISSED")
        and destGUID == playerGUID then
        local realMissType
        if subEvent == "SWING_MISSED" then
            realMissType = select(12, CombatLogGetCurrentEventInfo())
        else
            realMissType = select(15, CombatLogGetCurrentEventInfo())
        end
        local label = realMissType or "Missed"
        if label == "PARRY"  then label = L["Parried"]
        elseif label == "DODGE" then label = L["Dodged"]
        elseif label == "MISS"  then label = L["Missed"]
        elseif label == "BLOCK" then label = L["Blocked"]
        elseif label == "ABSORB" then label = L["Absorbed"]
        end
        spawnScroll("missed", label)
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

-- Blizzard mob FCT font (DAMAGE_TEXT_FONT global + CombatTextFont)
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
-- Mover (position of both systems)
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
    arrangeNotify()
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
        -- show the notifications too so the user sees what they're positioning
        showPreview()
        ns:Print(L["Combat Text mover active. Drag or arrow keys (SHIFT=5px)."])
    else
        moverFrame:Hide()
        hidePreview()
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    if not mod.db then return end
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

    C_Timer.After(2.0, scheduleDurabilityCheck)
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED", onCombatStart)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",  onCombatEnd)
    ns:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    ns:UnregisterEvent("UPDATE_INVENTORY_DURABILITY", scheduleDurabilityCheck)
    hidePreview()
    for _, f in pairs(notifyFrames) do f:Hide() end
    if container then container:Hide() end
    if moverFrame then moverFrame:Hide() end
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

-- Auto-stop the preview when the options window closes.
local function ensurePreviewAutoStop()
    local f = _G.VuloClassicUIMainFrame
    if f and not f._vcCTPreviewHooked then
        f._vcCTPreviewHooked = true
        f:HookScript("OnHide", function() hidePreview() end)
    end
end

-- key:       events table key
-- previewText: text shown by the Test button (scroll events only)
-- opts:      { notify = bool (flash, editable text, no outline toggle) }
local function eventSection(key, previewText, opts)
    opts = opts or {}
    local function ev() return mod.db.events[key] end
    local items = {}

    if opts.notify then
        items[#items + 1] = { type = "editbox", label = L["Text"],
            width = 280, editWidth = 170, commitOnFocusLost = true,
            get = function() return notifyText(key) end,
            set = function(_, v) ev().text = v; applyFontToNotify() end }
    end

    -- Row 1: Enabled + colour buttons + Test
    local row = {
        { type = "toggle", label = L["Enabled"],
          get = function() return ev().enabled end,
          set = function(_, v) ev().enabled = v end },
        { type = "button", label = L["Text color..."], width = 110,
          onClick = function()
              openColorPicker(function() return ev().color end,
                  function(c) ev().color = c; applyFontToNotify() end)
          end },
        { type = "button", label = L["Shadow color..."], width = 130,
          onClick = function()
              openColorPicker(function() return ev().shadowColor end,
                  function(c) ev().shadowColor = c; applyFontToNotify() end)
          end },
        { type = "button", label = L["Test"], width = 70,
          onClick = function()
              if opts.notify then showNotify(key) else spawnScroll(key, previewText) end
          end },
    }
    items[#items + 1] = { type = "group", layout = "row", gap = 6, items = row }

    items[#items + 1] = { type = "slider", label = L["Font Size (0 = global)"],
        min = 0, max = 32, step = 1,
        get = function() return ev().size or 0 end,
        set = function(_, v) ev().size = v; applyFontToNotify() end }

    -- Outline toggle only for scroll events; notifications follow the global dropdown.
    local toggles = {
        { type = "toggle", label = L["Shadow"],
          get = function() return ev().shadow end,
          set = function(_, v) ev().shadow = v; applyFontToNotify() end },
    }
    if not opts.notify then
        table.insert(toggles, 1, { type = "toggle", label = L["Outline"],
            get = function() return ev().outline end,
            set = function(_, v) ev().outline = v end })
    end
    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = toggles }

    items[#items + 1] = { type = "slider", label = L["Shadow X Offset"],
        min = -10, max = 10, step = 1,
        get = function() return ev().shadowX or 2 end,
        set = function(_, v) ev().shadowX = v; applyFontToNotify() end }
    items[#items + 1] = { type = "slider", label = L["Shadow Y Offset"],
        min = -10, max = 10, step = 1,
        get = function() return ev().shadowY or -2 end,
        set = function(_, v) ev().shadowY = v; applyFontToNotify() end }
    return items
end

function mod:GetOptions()
    ensurePreviewAutoStop()

    local items = {
        { type = "header", text = L["Combat Text"] },
        { type = "desc",
          text = L["|cffaaaaaaNotifications (+/- Combat, Low Durability) flash centred and stack; combat-log events (interrupts, dispels, misses) scroll upward. Use Preview to position and style them.|r"] },

        -- Preview + master test
        { type = "spacer", height = 4 },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "toggle", label = L["Show Preview"],
              tooltip = L["Shows all three notification messages on screen so you can position and style them. Turns off automatically when you close this window."],
              get = function() return isPreviewOn() end,
              set = function(_, v) if v then showPreview() else hidePreview() end end },
            { type = "button", label = L["Test (all events)"], width = 170,
              onClick = function()
                  showNotify("combatStart")
                  C_Timer.After(0.4, function() spawnScroll("spellInterrupt", L["Interrupted: Frostbolt"]) end)
                  C_Timer.After(0.8, function() spawnScroll("dispels",        L["Dispelled: Curse"]) end)
                  C_Timer.After(1.2, function() spawnScroll("missed",         L["Parried"]) end)
              end },
        } },

        -- Master categories
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
                set = function(_, v) mod.db.showDurability = v; scheduleDurabilityCheck() end },
          },
        },
    }

    -- Global defaults (collapsed)
    table.insert(items, { type = "section", title = L["Global Defaults"], collapsed = true, items = {
        { type = "dropdown", label = L["Font"],
          tooltip = L["Font for our combat text engine. Also used for Blizzard's mob FCT (DAMAGE_TEXT_FONT) when enabled below."],
          values = FONT_VALUES,
          get = function() return getActiveFontPath() end,
          set = function(_, v)
              mod.db.fontFace = v
              applyFontToPool(); applyFontToNotify()
              applySharpFonts(); applyDamageTextFont()
          end },
        { type = "toggle", label = L["Also apply font to Blizzard mob FCT"],
          tooltip = L["Additionally sets DAMAGE_TEXT_FONT globally - changes the font of the damage numbers above mobs/pets. Requires /reload to take effect."],
          get = function() return mod.db.applyToMobFCT ~= false end,
          set = function(_, v) mod.db.applyToMobFCT = v; applyDamageTextFont() end },
        { type = "slider", label = L["Default Font Size"],
          min = 10, max = 32, step = 1,
          get = function() return mod.db.fontSize end,
          set = function(_, v) mod.db.fontSize = v; applyFontToPool(); applyFontToNotify() end },
        { type = "dropdown", label = L["Outline Style"],
          values = {
              { value = "NONE",         text = L["None"] },
              { value = "OUTLINE",      text = L["Outline"] },
              { value = "THICKOUTLINE", text = L["Thick Outline"] },
          },
          get = function() return mod.db.fontOutlineMode or "THICKOUTLINE" end,
          set = function(_, v) mod.db.fontOutlineMode = v; applyFontToPool(); applyFontToNotify() end },
        { type = "toggle", label = L["Default: Shadow"],
          get = function() return mod.db.fontShadow end,
          set = function(_, v) mod.db.fontShadow = v; applyFontToNotify() end },
        { type = "slider", label = L["Flash Duration (sec.)"],
          min = 0.5, max = 5.0, step = 0.1,
          tooltip = L["How long the +/- Combat flash stays before fading."],
          get = function() return mod.db.flashDuration or 1.5 end,
          set = function(_, v) mod.db.flashDuration = v end },
        { type = "slider", label = L["Scroll Duration (sec.)"],
          min = 0.5, max = 5.0, step = 0.1,
          get = function() return mod.db.scrollDuration end,
          set = function(_, v) mod.db.scrollDuration = v end },
        { type = "slider", label = L["Scroll Distance (px)"],
          min = 20, max = 200, step = 5,
          get = function() return mod.db.scrollDistance end,
          set = function(_, v) mod.db.scrollDistance = v end },
    } })

    -- Notifications (flash + stack, editable text)
    table.insert(items, { type = "spacer", height = 8 })
    table.insert(items, { type = "header", text = L["Notifications (flash & stack)"] })

    -- One "Combat" section holding both the enter (+) and exit (−) messages.
    -- Literal labels so it reads "Combat" in every locale (the on-screen text
    -- defaults stay localized via the editable Text fields below).
    local combatItems = { { type = "header", text = "+ Combat" } }
    for _, it in ipairs(eventSection("combatStart", nil, { notify = true })) do
        combatItems[#combatItems + 1] = it
    end
    combatItems[#combatItems + 1] = { type = "spacer", height = 8 }
    combatItems[#combatItems + 1] = { type = "header", text = "− Combat" }
    for _, it in ipairs(eventSection("combatEnd", nil, { notify = true })) do
        combatItems[#combatItems + 1] = it
    end
    table.insert(items, { type = "section", title = "Combat", collapsed = true, items = combatItems })

    local lowDuraItems = eventSection("lowDurability", nil, { notify = true })
    table.insert(lowDuraItems, { type = "slider", label = L["Durability Threshold (%)"],
        min = 5, max = 50, step = 1,
        tooltip = L["Warning appears when at least one equipped item is below this value (after combat exit)."],
        get = function() return mod.db.durabilityThreshold or 15 end,
        set = function(_, v) mod.db.durabilityThreshold = v; scheduleDurabilityCheck() end })
    table.insert(items, { type = "section", title = L["Low Durability"], collapsed = true, items = lowDuraItems })

    -- Scrolling combat-log events
    table.insert(items, { type = "spacer", height = 8 })
    table.insert(items, { type = "header", text = L["Combat Log (scrolling)"] })
    table.insert(items, { type = "section", title = L["Interrupted"], collapsed = true,
        items = eventSection("spellInterrupt", L["Interrupted: Frostbolt"]) })
    table.insert(items, { type = "section", title = L["Dispelled/Purged"], collapsed = true,
        items = eventSection("dispels", L["Dispelled: Curse"]) })
    table.insert(items, { type = "section", title = L["Parried/Dodged/Missed"], collapsed = true,
        items = eventSection("missed", L["Parried"]) })

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
