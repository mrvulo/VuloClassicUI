-- VuloClassicUI / Modules / CombatText: flashing notifications + scrolling combat-log text.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("combattext", {
    name        = "Combat Text",
    group       = "HUD",
    description = "Flashing combat notifications (with live preview) plus a scrolling combat-log text engine.",
    defaults    = {
        enabled        = true,
        showCombatState     = true,
        showCombatLog       = true,
        showDurability      = true,
        fontFace       = "Interface\\AddOns\\VuloClassicUI\\Media\\Fonts\\Expressway.TTF",
        applyToMobFCT  = true,
        showSpellIcons = true,
        events = {
            combatStart    = { enabled = true, text = "", color = { r = 0.93, g = 0.26, b = 0.0 }, size = 0, outline = true, shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            combatEnd      = { enabled = true, text = "", color = { r = 1.0, g = 1.0, b = 1.0 }, size = 0, outline = true, shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            spellInterrupt = { enabled = true, color = { r = 1.0, g = 0.82, b = 0.2 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            purged         = { enabled = true, color = { r = 0.608, g = 0.424, b = 1.0 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            dispels        = { enabled = true, color = { r = 1.0, g = 0.45, b = 0.75 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            dispelledBy    = { enabled = true, color = { r = 1.0, g = 0.6, b = 0.85 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            buffGiven      = { enabled = true, color = { r = 0.75, g = 0.65, b = 1.0 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            buffReceived   = { enabled = true, color = { r = 0.6, g = 0.8, b = 1.0 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            reflected      = { enabled = true, color = { r = 1.0, g = 0.6, b = 0.3 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            partyDeath     = { enabled = true, color = { r = 1.0, g = 0.3, b = 0.3 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            missed         = { enabled = true, color = { r = 1.0, g = 0.7, b = 0.2 }, size = 0, outline = true,  shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
            lowDurability  = { enabled = true, text = "", color = { r = 1.0, g = 0.3, b = 0.3 }, size = 0, outline = true, shadow = true, shadowColor = { r = 0, g = 0, b = 0 }, shadowX = 2, shadowY = -2 },
        },
        durabilityThreshold = 15,
        deathClassColor = true,
        worldTextScale = 1.0,
        sharpFonts     = true,
        fontSize       = 18,
        color          = { r = 1, g = 1, b = 0 },
        scrollDuration = 2.0,
        scrollDistance = 80,
        flashDuration  = 1.5,
        fontOutlineMode = "THICKOUTLINE", -- NONE | OUTLINE | THICKOUTLINE
        fontOutline    = true,          -- legacy fallback for fontOutlineMode
        fontShadow     = true,
        shadowX        = 2,
        shadowY        = -2,
        x              = 0,
        y              = 180,
        unlocked       = false,
        anchorTo       = "UIParent",
        anchorFrom     = "CENTER",
        anchorPoint    = "CENTER",
        strata         = "HIGH",
        messageSpacing = 6,
        shadowColor    = { r = 0, g = 0, b = 0 },
    },
})

local container
local POOL_SIZE = 20
local fontStringPool = {}
local activeMessages = {}
local notifyFrames   = {}
local isPreview      = false

local NOTIFY_TYPES   = { "combatStart", "combatEnd", "lowDurability" }
local NOTIFY_SPACING = 6

-- Forward declarations: these are referenced by closures defined before them.
local showNotify, hideNotify, doCheckDurability, scheduleDurabilityCheck

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
        local sc = shadowColor or mod.db.shadowColor or { r = 0, g = 0, b = 0 }
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
    for i = 1, POOL_SIZE do
        local fs = container:CreateFontString(nil, "OVERLAY")
        applyStyleToFS(fs)
        fs:Hide()
        table.insert(fontStringPool, fs)
    end
    return container
end

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
            m.fs:SetPoint("CENTER", container, "CENTER", 0, (m.offset or 0) + p * m.dist)
            m.fs:SetAlpha(1 - p)
        end
    end
    if #activeMessages == 0 then
        self:SetScript("OnUpdate", nil)
    end
end

local ANCHOR_FRAMES = {
    { value = "UIParent",    text = L["Screen (UIParent)"] },
    { value = "PlayerFrame", text = L["Player Frame"] },
    { value = "TargetFrame", text = L["Target Frame"] },
    { value = "Minimap",     text = L["Minimap"] },
}
local function anchorTargetFrame()
    return _G[mod.db.anchorTo or "UIParent"] or UIParent
end

local function reAnchorContainer()
    if not container then return end
    container:ClearAllPoints()
    container:SetPoint(mod.db.anchorFrom or "CENTER", anchorTargetFrame(),
        mod.db.anchorPoint or "CENTER", mod.db.x or 0, mod.db.y or 0)
    container:SetFrameStrata(mod.db.strata or "HIGH")
end

local EVENT_CATEGORY = {
    combatStart    = "showCombatState",
    combatEnd      = "showCombatState",
    spellInterrupt = "showCombatLog",
    purged         = "showCombatLog",
    dispels        = "showCombatLog",
    dispelledBy    = "showCombatLog",
    buffGiven      = "showCombatLog",
    buffReceived   = "showCombatLog",
    reflected      = "showCombatLog",
    partyDeath     = "showCombatLog",
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
    applyStyleToFS(fs, sz, nil, nil, nil, nil, nil)
    fs:SetText(text)
    local c = ev.color or mod.db.color or { r = 1, g = 1, b = 1 }
    fs:SetTextColor(c.r or 1, c.g or 1, c.b or 1, 1)
    fs:SetAlpha(1)
    -- Stagger a burst: start one line-height below the newest still-rising line.
    local startOffset = 0
    local newest = activeMessages[#activeMessages]
    if newest then
        local curY  = (newest.offset or 0) + (newest.t / newest.dur) * newest.dist
        local lineH = (fs:GetStringHeight() or (mod.db.fontSize or 18))
                    + (mod.db.messageSpacing or NOTIFY_SPACING)
        startOffset = math.min(0, curY - lineH)
    end
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", container, "CENTER", 0, startOffset)
    fs:Show()
    table.insert(activeMessages, {
        fs = fs, t = 0,
        dur = mod.db.scrollDuration or 2.0,
        dist = mod.db.scrollDistance or 80,
        offset = startOffset,
    })
    container:SetScript("OnUpdate", animateMessages)
end

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

local function styleNotify(f, key)
    local ev = mod.db.events and mod.db.events[key] or {}
    local sz = (ev.size and ev.size > 0) and ev.size or (mod.db.fontSize or 18)
    applyStyleToFS(f.text, sz, nil, nil, nil, nil, nil)
    f.text:SetText(notifyText(key))
    local c = ev.color or { r = 1, g = 1, b = 1 }
    f.text:SetTextColor(c.r or 1, c.g or 1, c.b or 1, 1)
    local w = math.max(f.text:GetStringWidth() or 0, 50)
    local h = math.max(f.text:GetStringHeight() or 0, 14)
    f:SetSize(w + 6, h + 2)
end

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
    local spacing = mod.db.messageSpacing or NOTIFY_SPACING
    totalH = totalH + spacing * (#visible - 1)
    local cursor = totalH / 2
    for _, f in ipairs(visible) do
        local h = f:GetHeight()
        f:ClearAllPoints()
        f:SetPoint("CENTER", container, "CENTER", 0, cursor - h / 2)
        cursor = cursor - h - spacing
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
    if not InCombatLockdown() then scheduleDurabilityCheck() end
end

local function isPreviewOn() return isPreview end

local function applyFontToPool()
    local size = mod.db.fontSize or 18
    for _, fs in ipairs(fontStringPool) do applyStyleToFS(fs, size) end
    for _, m in ipairs(activeMessages) do applyStyleToFS(m.fs, size) end
end

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

local function iconTag(spellId)
    if mod.db.showSpellIcons == false then return "" end
    local tex = spellId and GetSpellTexture and GetSpellTexture(spellId)
    if not tex then return "" end
    return "|T" .. tex .. ":0|t "
end

local function richMsg(label, spellId, spellName, nameFirst)
    if not spellName then return label end
    local namePart = iconTag(spellId) .. "|cffffffff[" .. spellName .. "]|r"
    if nameFirst then return namePart .. " " .. label end
    return label .. " " .. namePart
end

local function isPlayerGUID(guid)
    return guid and guid:find("^Player%-") ~= nil
end

-- Per-(event, spell) throttle: raid-wide buffs would otherwise flood the pool.
local _lastRich = {}
local function throttled(eventKey, spellId)
    local k = eventKey .. ":" .. (spellId or 0)
    local now = GetTime()
    if _lastRich[k] and (now - _lastRich[k]) < 2 then return true end
    _lastRich[k] = now
    return false
end

-- Death announcements: at most 4 in 10s.
local _deathStamps = {}
local function deathThrottled()
    local now = GetTime()
    for i = #_deathStamps, 1, -1 do
        if now - _deathStamps[i] > 10 then table.remove(_deathStamps, i) end
    end
    if #_deathStamps >= 4 then return true end
    _deathStamps[#_deathStamps + 1] = now
    return false
end

-- GUID -> group unit token (nil if not in our party/raid).
local function groupUnitByGUID(guid)
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and UnitGUID(u) == guid then return u end
        end
    else
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and UnitGUID(u) == guid then return u end
        end
    end
    return nil
end

local CLEU_WANTED = {
    SPELL_INTERRUPT = true, SPELL_DISPEL = true, SPELL_STOLEN = true,
    SWING_MISSED    = true, RANGE_MISSED = true, SPELL_MISSED = true,
    SPELL_AURA_APPLIED = true, UNIT_DIED = true,
}
local function onCLEU()
    if not mod._enabled then return end
    if not CLEU_WANTED[select(2, CombatLogGetCurrentEventInfo())] then return end
    if not playerGUID then
        playerGUID = UnitGUID("player")
        if not playerGUID then return end
    end
    -- Slots: 12=spellId/SWING missType, 15=extraSpellId/SPELL missType/auraType(APPLIED), 18=auraType(DISPEL/STOLEN).
    local _, subEvent, _, sourceGUID, _, _, _, destGUID, destName, _, _,
          arg12, spellName, _, arg15, extraSpellName, _, auraType18
          = CombatLogGetCurrentEventInfo()

    if subEvent == "UNIT_DIED" then
        if not destGUID or destGUID == playerGUID or not isPlayerGUID(destGUID) then return end
        local unit = groupUnitByGUID(destGUID)
        if not unit then return end
        -- a feigning hunter also fires UNIT_DIED
        if UnitIsFeignDeath and UnitIsFeignDeath(unit) then return end
        if deathThrottled() then return end
        local name = destName and destName:match("^[^%-]+") or "?"
        if mod.db.deathClassColor ~= false and GetPlayerInfoByGUID then
            local _, classToken = GetPlayerInfoByGUID(destGUID)
            local cc = classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
            if cc then
                local hex = cc.colorStr or string.format("ff%02x%02x%02x",
                    math.floor(cc.r * 255 + 0.5), math.floor(cc.g * 255 + 0.5),
                    math.floor(cc.b * 255 + 0.5))
                name = "|c" .. hex .. name .. "|r"
            end
        end
        spawnScroll("partyDeath", string.format(L["%s died"], name))
        return
    end

    if subEvent == "SPELL_AURA_APPLIED" then
        -- external player buffs only: no self-buffs, no NPC auras
        if arg15 ~= "BUFF" then return end
        if destGUID == playerGUID and sourceGUID and sourceGUID ~= playerGUID
           and isPlayerGUID(sourceGUID) then
            if not throttled("buffReceived", arg12) then
                spawnScroll("buffReceived", richMsg(L["gave you"], arg12, spellName))
            end
        elseif sourceGUID == playerGUID and destGUID ~= playerGUID
           and isPlayerGUID(destGUID) then
            if not throttled("buffGiven", arg12) then
                spawnScroll("buffGiven", richMsg(L["You gave"], arg12, spellName))
            end
        end
        return
    end

    if subEvent == "SPELL_INTERRUPT" and sourceGUID == playerGUID then
        spawnScroll("spellInterrupt",
            richMsg(L["Interrupted"], arg15, extraSpellName or spellName))
    elseif subEvent == "SPELL_DISPEL" then
        -- slot-18 auraType: BUFF off an enemy = purge, DEBUFF off a friend = cleanse
        if sourceGUID == playerGUID then
            if auraType18 == "BUFF" then
                spawnScroll("purged", richMsg(L["Purged"], arg15, extraSpellName))
            else
                spawnScroll("dispels", richMsg(L["Dispelled"], arg15, extraSpellName))
            end
        elseif destGUID == playerGUID and auraType18 == "BUFF" then
            spawnScroll("dispelledBy", richMsg(L["dispelled"], arg15, extraSpellName))
        end
    elseif subEvent == "SPELL_STOLEN" and sourceGUID == playerGUID then
        spawnScroll("purged", richMsg(L["Purged"], arg15, extraSpellName))
    elseif (subEvent == "SWING_MISSED" or subEvent == "RANGE_MISSED" or subEvent == "SPELL_MISSED") then
        local realMissType = (subEvent == "SWING_MISSED") and arg12 or arg15
        -- SWING_MISSED excluded: its slot 13 is not a spell name
        if realMissType == "REFLECT" and subEvent ~= "SWING_MISSED" then
            if destGUID == playerGUID or sourceGUID == playerGUID then
                spawnScroll("reflected", richMsg(L["reflected"], arg12, spellName, true))
            end
            return
        end
        if destGUID ~= playerGUID then return end
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

local function applyDamageTextFont()
    if not mod.db or mod.db.applyToMobFCT == false then return end
    local path = getActiveFontPath()
    _G.DAMAGE_TEXT_FONT = path
    if _G.CombatTextFont and _G.CombatTextFont.SetFont then
        pcall(_G.CombatTextFont.SetFont, _G.CombatTextFont, path, 120, "")
    end
end

-- The scale belongs to the client, not to us. Mirror whatever the player has
-- set and only write when they move our slider. Applying it on every login
-- silently reset a value they may have chosen in Blizzard's own options, with
-- no setting here to explain it or put it back.
local function readWorldTextScale()
    local v = tonumber(GetCVar and GetCVar("WorldTextScale"))
    if v and v > 0 then mod.db.worldTextScale = v end
end

local function applyWorldTextScale()
    local v = tonumber(mod.db.worldTextScale)
    if not v or v <= 0 then return end
    v = tostring(v)
    pcall(SetCVar, "WorldTextScale",  v)
    pcall(SetCVar, "damageTextScale", v)
end

local function applyMoverPosition()
    reAnchorContainer()
    arrangeNotify()
end

-- Raw screen coords of a named point; valid only because both frames share UIParent scale.
local function pointOf(frame, point)
    local l, b, w, h = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    if not (l and b and w and h) then return nil end
    local x = (point:find("LEFT") and l) or (point:find("RIGHT") and (l + w)) or (l + w / 2)
    local y = (point:find("BOTTOM") and b) or (point:find("TOP") and (b + h)) or (b + h / 2)
    return x, y
end

-- Translate the mover's CENTER-offset drop back into our anchorFrom/anchorPoint model.
local function moverOnMove()
    local from = mod.db.anchorFrom  or "CENTER"
    local pt   = mod.db.anchorPoint or "CENTER"
    local tgt  = anchorTargetFrame()
    local fx, fy = pointOf(container, from)
    local tx, ty = pointOf(tgt, pt)
    if fx and tx then
        mod.db.x = fx - tx
        mod.db.y = fy - ty
    end
    reAnchorContainer()
    arrangeNotify()
end

local function setupMover()
    if mod._mover then return end
    createContainer()
    mod._mover = ns:CreateMover(container, {
        key    = "combattext",
        label  = "|cffffffffCOMBAT TEXT|r",
        db     = mod.db,
        width  = 220, height = 56,
        applyPos    = applyMoverPosition,
        onMove      = moverOnMove,
        editPreview = function(show) if show then showPreview() else hidePreview() end end,
    })
end

function mod:OnEnable()
    if not mod.db then return end
    mod.db.unlocked = false   -- clear stale saved unlock so the box only shows in /vedit

    -- Migration: retint only events still on their OLD default color.
    local function isNear(c, r, g, b)
        return c and math.abs((c.r or 0) - r) < 0.01
                 and math.abs((c.g or 0) - g) < 0.01
                 and math.abs((c.b or 0) - b) < 0.01
    end
    local ev = mod.db.events or {}
    if ev.combatEnd and isNear(ev.combatEnd.color, 0.6, 0.9, 0.6) then
        ev.combatEnd.color = { r = 1, g = 1, b = 1 }
    end
    if ev.dispels and isNear(ev.dispels.color, 0.6, 0.9, 1.0) then
        ev.dispels.color = { r = 1.0, g = 0.45, b = 0.75 }
    end
    if ev.spellInterrupt and isNear(ev.spellInterrupt.color, 1.0, 1.0, 0.3) then
        ev.spellInterrupt.color = { r = 1.0, g = 0.82, b = 0.2 }
    end
    playerGUID = UnitGUID("player")
    createContainer()
    if container then container:Show() end   -- createContainer early-returns after a disable->enable cycle
    reAnchorContainer()
    setupMover()
    applySharpFonts()
    readWorldTextScale()
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
end

local function ensurePreviewAutoStop()
    local f = _G.VuloClassicUIMainFrame
    if f and not f._vcCTPreviewHooked then
        f._vcCTPreviewHooked = true
        f:HookScript("OnHide", function()
            -- keep the preview alive if /vedit is still driving it
            if not (ns.IsEditModeActive and ns:IsEditModeActive()) then hidePreview() end
        end)
    end
end

local function eventColorSet(key)
    return function(r, g, b)
        mod.db.events[key].color = { r = r, g = g, b = b }
        applyFontToNotify()
    end
end
local function msgSection(key, title, hasText)
    local secItems = {
        { type = "toggle", label = L["Enabled"],
          get = function() return mod.db.events[key].enabled end,
          set = function(_, v) mod.db.events[key].enabled = v; applyFontToNotify() end },
        { type = "color", label = L["Color"],
          get = function() return mod.db.events[key].color end,
          set = eventColorSet(key) },
    }
    if hasText then
        secItems[#secItems + 1] = { type = "editbox", label = L["Text"],
            editWidth = 220, commitOnFocusLost = true,
            get = function() return notifyText(key) end,
            set = function(_, v) mod.db.events[key].text = v; applyFontToNotify() end }
    end
    return { type = "section", title = title, collapsed = false, items = secItems }
end

function mod:GetOptions()
    ensurePreviewAutoStop()
    local SLW = 180

    local function reapplyFont()
        applyFontToPool(); applyFontToNotify(); applySharpFonts(); applyDamageTextFont()
    end

    local STRATA = {}
    for _, s in ipairs({ "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }) do
        STRATA[#STRATA + 1] = { value = s, text = s }
    end
    local POINTS = {}
    for _, p in ipairs({ "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        POINTS[#POINTS + 1] = { value = p, text = p }
    end

    local lowDura = msgSection("lowDurability", L["Low Durability Warning"], true)
    lowDura.items[#lowDura.items + 1] = { type = "slider", label = L["Threshold (%)"],
        min = 5, max = 50, step = 1,
        get = function() return mod.db.durabilityThreshold or 15 end,
        set = function(_, v) mod.db.durabilityThreshold = v; scheduleDurabilityCheck() end }

    return {
        { type = "section", title = L["Display Settings"], collapsed = false, items = {
            { type = "toggle", label = L["Enable Combat Messages"],
              get = function() return ns:IsModuleEnabled("combattext") end,
              set = function(_, v) if ns.ToggleModule then ns:ToggleModule("combattext", v) end end },
            { type = "toggle", label = L["Show Preview"],
              get = function() return isPreviewOn() end,
              set = function(_, v) if v then showPreview() else hidePreview() end end },
            { type = "group", layout = "columns", columns = 2, items = {
                { type = "slider", label = L["Fade Duration"], min = 0.5, max = 5.0, step = 0.1, width = SLW,
                  get = function() return mod.db.flashDuration or 1.5 end,
                  set = function(_, v) mod.db.flashDuration = v; mod.db.scrollDuration = v end },
                { type = "slider", label = L["Message Spacing"], min = 0, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.messageSpacing or 6 end,
                  set = function(_, v) mod.db.messageSpacing = v; arrangeNotify() end },
            } },
        } },

        -- These three change things outside our own frames (two client CVars and
        -- a global font). They used to be applied with no control anywhere in the
        -- panel, so the player could neither see nor undo them.
        { type = "section", title = L["Engine FCT (above mob/pet)"], collapsed = true, items = {
            { type = "toggle", label = L["Sharper hit indicator font (Friz Quadrata)"],
              get = function() return mod.db.sharpFonts ~= false end,
              set = function(_, v) mod.db.sharpFonts = v; applySharpFonts() end },
            { type = "toggle", label = L["Also apply font to Blizzard mob FCT"],
              tooltip = L["Additionally sets DAMAGE_TEXT_FONT globally - changes the font of the damage numbers above mobs/pets. Requires /reload to take effect."],
              get = function() return mod.db.applyToMobFCT ~= false end,
              set = function(_, v) mod.db.applyToMobFCT = v; applyDamageTextFont() end },
            { type = "slider", label = L["Engine FCT Scale"], min = 0.5, max = 2.0, step = 0.05, width = SLW,
              tooltip = L["Damage numbers above mob/pet — bitmap scaling."],
              get = function() return tonumber(mod.db.worldTextScale) or 1.0 end,
              set = function(_, v) mod.db.worldTextScale = v; applyWorldTextScale() end },
        } },

        { type = "section", title = L["Position Settings"], collapsed = false, items = {
            { type = "button", label = L["Open Edit Mode"], width = 140,
              tooltip = L["Drag the combat-text box in the unified Edit Mode (/vedit)."],
              onClick = function()
                  if ns.SetEditMode then ns:SetEditMode(not ns:IsEditModeActive()) end
              end },
            { type = "dropdown", label = L["Anchored To"], values = ANCHOR_FRAMES,
              get = function() return mod.db.anchorTo or "UIParent" end,
              set = function(_, v) mod.db.anchorTo = v; applyMoverPosition() end },
            { type = "dropdown", label = L["Strata"], values = STRATA,
              get = function() return mod.db.strata or "HIGH" end,
              set = function(_, v) mod.db.strata = v; reAnchorContainer() end },
            { type = "dropdown", label = L["Anchor From"], values = POINTS,
              get = function() return mod.db.anchorFrom or "CENTER" end,
              set = function(_, v) mod.db.anchorFrom = v; applyMoverPosition() end },
            { type = "dropdown", label = L["To Frame's"], values = POINTS,
              get = function() return mod.db.anchorPoint or "CENTER" end,
              set = function(_, v) mod.db.anchorPoint = v; applyMoverPosition() end },
            { type = "group", layout = "columns", columns = 2, items = {
                { type = "slider", label = L["X Offset"], min = -800, max = 800, step = 1, width = SLW,
                  get = function() return mod.db.x or 0 end,
                  set = function(_, v) mod.db.x = v; applyMoverPosition() end },
                { type = "slider", label = L["Y Offset"], min = -800, max = 800, step = 1, width = SLW,
                  get = function() return mod.db.y or 0 end,
                  set = function(_, v) mod.db.y = v; applyMoverPosition() end },
            } },
        } },

        { type = "section", title = L["Font Settings"], collapsed = false, items = {
            { type = "dropdown", label = L["Font"], values = FONT_VALUES,
              get = function() return getActiveFontPath() end,
              set = function(_, v) mod.db.fontFace = v; reapplyFont() end },
            { type = "dropdown", label = L["Outline"],
              values = {
                  { value = "NONE",         text = L["None"] },
                  { value = "OUTLINE",      text = L["Outline"] },
                  { value = "THICKOUTLINE", text = L["Thick Outline"] },
              },
              get = function() return mod.db.fontOutlineMode or "THICKOUTLINE" end,
              set = function(_, v) mod.db.fontOutlineMode = v; reapplyFont() end },
            { type = "group", layout = "columns", columns = 2, items = {
                { type = "slider", label = L["Font Size"], min = 10, max = 32, step = 1, width = SLW,
                  get = function() return mod.db.fontSize end,
                  set = function(_, v) mod.db.fontSize = v; reapplyFont() end },
            } },
            { type = "toggle", label = L["Enable Shadow"],
              get = function() return mod.db.fontShadow end,
              set = function(_, v) mod.db.fontShadow = v; reapplyFont() end },
            { type = "color", label = L["Shadow Color"],
              get = function() return mod.db.shadowColor end,
              set = function(r, g, b) mod.db.shadowColor = { r = r, g = g, b = b }; reapplyFont() end },
            { type = "group", layout = "columns", columns = 2, items = {
                { type = "slider", label = L["Shadow X"], min = -10, max = 10, step = 1, width = SLW,
                  get = function() return mod.db.shadowX or 2 end,
                  set = function(_, v) mod.db.shadowX = v; reapplyFont() end },
                { type = "slider", label = L["Shadow Y"], min = -10, max = 10, step = 1, width = SLW,
                  get = function() return mod.db.shadowY or -2 end,
                  set = function(_, v) mod.db.shadowY = v; reapplyFont() end },
            } },
        } },

        msgSection("combatStart", L["Enter Combat Message"], true),
        msgSection("combatEnd",   L["Exit Combat Message"], true),
        lowDura,
        msgSection("spellInterrupt", L["Interrupted"], false),
        msgSection("purged",         L["Purged (enemy buff removed)"], false),
        msgSection("dispels",        L["Dispelled (by you)"], false),
        msgSection("dispelledBy",    L["Dispelled (your buff lost)"], false),
        msgSection("buffGiven",      L["Buff given"], false),
        msgSection("buffReceived",   L["Buff received"], false),
        msgSection("reflected",      L["Reflected"], false),
        (function()
            local sec = msgSection("partyDeath", L["Party member died"], false)
            table.insert(sec.items, { type = "toggle", label = L["Class color names"],
                get = function() return mod.db.deathClassColor ~= false end,
                set = function(_, v) mod.db.deathClassColor = v end })
            return sec
        end)(),
        msgSection("missed",         L["Parried/Dodged/Missed"], false),

        { type = "toggle", label = L["Show spell icons"],
          tooltip = L["Shows the spell icon inline next to the spell name."],
          get = function() return mod.db.showSpellIcons ~= false end,
          set = function(_, v) mod.db.showSpellIcons = v end },

        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Test (all events)"], width = 170,
              onClick = function()
                  showNotify("combatStart")
                  C_Timer.After(0.3, function() spawnScroll("spellInterrupt", richMsg(L["Interrupted"], 116, GetSpellInfo and GetSpellInfo(116) or "Frostbolt")) end)
                  C_Timer.After(0.6, function() spawnScroll("purged",         richMsg(L["Purged"], 1459, GetSpellInfo and GetSpellInfo(1459) or "Arcane Intellect")) end)
                  C_Timer.After(0.9, function() spawnScroll("dispels",        richMsg(L["Dispelled"], 687, GetSpellInfo and GetSpellInfo(687) or "Demon Skin")) end)
                  C_Timer.After(1.2, function() spawnScroll("dispelledBy",    richMsg(L["dispelled"], 1459, GetSpellInfo and GetSpellInfo(1459) or "Arcane Intellect")) end)
                  C_Timer.After(1.5, function() spawnScroll("buffReceived",   richMsg(L["gave you"], 1459, GetSpellInfo and GetSpellInfo(1459) or "Arcane Intellect")) end)
                  C_Timer.After(1.8, function() spawnScroll("reflected",      richMsg(L["reflected"], 133, GetSpellInfo and GetSpellInfo(133) or "Fireball", true)) end)
                  C_Timer.After(2.1, function() spawnScroll("missed",         L["Parried"]) end)
                  C_Timer.After(2.4, function() spawnScroll("partyDeath",     string.format(L["%s died"], "|cfff58cbaVulo|r")) end)
              end },
        } },
    }
end
