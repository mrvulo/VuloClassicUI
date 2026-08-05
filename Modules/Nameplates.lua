-- VuloClassicUI / Modules / Nameplates
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("nameplates", {
    -- Strict grid (user request, 31.07.2026): the tabs render two-up; the
    -- options file marks its gear rows pairable in one sweep.
    optionsGrid = true,
    name        = "Nameplates",
    group       = "Unit Frames",
    description = "Custom enemy & NPC nameplates with a live preview: health bar, cast bar, name and health text, reaction / class colours, target highlight and threat colouring.",
    defaults = {
        enabled = true,

        healthWidth   = 120,
        healthHeight  = 10,
        pixelPerfect  = false,
        healthTexture = "Atrocity",
        bgAlpha       = 0.85,
        bgColor       = { r = 0.05, g = 0.05, b = 0.06 },
        borderSize    = 1,
        borderStyle   = "lines",
        borderTexture = "Blizzard Tooltip",
        borderColor   = { r = 0.067, g = 0.067, b = 0.067 },
        showSpark     = true,
        sparkWidth    = 10,
        roundedBars   = false,

        lowHpGlow   = false,
        lowHpPct    = 35,
        colLowHp    = { r = 1.00, g = 0.20, b = 0.20 },

        showAbsorb  = true,
        absorbStyle = "flat",
        colAbsorb   = { r = 0.70, g = 0.85, b = 1.00 },
        absorbAlpha = 0.55,

        execLine       = false,
        execPct        = 20,
        colExec        = { r = 1.00, g = 0.35, b = 0.35 },
        execTargetOnly = true,

        targetBarColor = false,
        colTargetBar   = { r = 0.75, g = 0.55, b = 1.00 },
        hoverHighlight = false,
        hoverAlpha     = 12,
        targetScale    = 100,

        hitboxPctW = 100,
        hitboxPctH = 100,

        globalScale  = 100,
        plateOffsetY = 0,

        showName        = true,
        nameSize        = 10,
        showLevel       = false,
        showLevelMod    = true,
        levelSize       = 0,
        showHealthText  = true,
        healthTextMode  = "percent",
        healthTextFormat = "%s (%s)",
        healthTextShort  = false,
        healthTextPercentSign = true,
        healthSmooth = false,
        bgTintByBar  = false,
        fontSize        = 9,
        fontFace        = "",
        fontOutline     = "OUTLINE",
        healthTextSize  = 0,
        castTextSize    = 0,
        castTimerSize   = 0,
        titleSize       = 0,

        colHostile  = { r = 0.85, g = 0.20, b = 0.20 },
        colNeutral  = { r = 0.90, g = 0.80, b = 0.20 },
        colFriendly = { r = 0.25, g = 0.70, b = 0.35 },
        colTapped   = { r = 0.55, g = 0.55, b = 0.55 },
        classColorEnemy    = true,
        classColorFriendly = false,
        darkenOOC          = false,
        darkenOOCPct       = 45,

        showCastbar   = true,
        castInFront   = false,
        castHeight    = 12,
        castTexture   = "Atrocity",
        showCastIcon  = true,
        showCastText  = true,
        colCast              = { r = 0.70, g = 0.40, b = 0.90 },
        kickReadyColorOn     = false,
        colCastKickReady     = { r = 0.20, g = 0.85, b = 0.25 },
        castChannelColor     = false,
        colCastChannel       = { r = 0.24, g = 0.75, b = 0.30 },
        castYouColorOn       = false,
        colCastYou           = { r = 1, g = 0.15, b = 0.15 },
        castInterrupter      = false,
        colCastNoInterrupt   = { r = 0.55, g = 0.55, b = 0.55 },
        castTimer            = false,
        castTargetText       = false,
        castTargetSize       = 0,
        castTargetX          = 6,
        castTargetY          = 0,
        kickColorOn          = false,
        colCastKickCd        = { r = 0.35, g = 0.35, b = 0.60 },
        castOffsetX          = 0,
        castOffsetY          = 0,
        castWidth            = 0,
        castBgAlpha          = 0,
        castBgColor          = { r = 0.05, g = 0.05, b = 0.06 },
        castIconScale        = 100,
        -- Percent, like the scale beside it -- NOT the fraction the aura rows
        -- store. Both show percent in the options; this block just keeps its own
        -- unit rather than being the one value here that is read in hundredths.
        -- 8 is what the cast icon hardcoded before, so a profile without the key
        -- draws exactly as it did.
        castIconCrop         = 8,
        castIconX            = 0,
        castIconY            = 0,
        castIconRight        = false,
        showCastShield       = true,
        castKickTick         = false,
        colKickTick          = { r = 0.30, g = 1.00, b = 0.40 },
        castInterruptFlash   = true,
        colInterruptFlash    = { r = 1.00, g = 0.25, b = 0.20 },
        castTextColor        = { r = 1, g = 1, b = 1 },
        castTimerSide        = "right",
        castTimerColor       = { r = 1, g = 1, b = 1 },
        hideNameWhileCasting = false,
        castEmphasis         = false,
        castEmphScale        = 110,
        castEmphAlpha        = 100,

        nameOffsetX       = 0,
        nameOffsetY       = 0,
        nameInBar         = false,
        healthTextOffsetX = 0,
        healthTextOffsetY = 0,
        auraOffsetX       = 0,
        auraOffsetY       = 0,

        targetHighlight = true,
        colTarget       = { r = 1, g = 1, b = 1 },
        targetArrows    = false,
        targetArrowSize = 14,
        targetArrowGap  = 4,
        colTargetArrow  = { r = 1, g = 1, b = 1 },
        nonTargetAlpha  = 1.0,

        focusHighlight  = true,
        colFocus        = { r = 0.20, g = 0.60, b = 1.00 },
        focusMark       = false,
        focusMarkText   = "F",
        focusMarkAnchor = "CENTER",
        focusMarkSize   = 0,
        focusMarkX      = 0,
        focusMarkY      = 0,
        colFocusMark    = { r = 0.20, g = 0.60, b = 1.00 },

        threatEnabled = false,
        threatRole    = "dps",
        colThreatGood = { r = 0.25, g = 0.75, b = 0.30 },
        colThreatWarn = { r = 0.95, g = 0.80, b = 0.20 },
        colThreatBad  = { r = 0.95, g = 0.25, b = 0.20 },

        showClassPower = true,
        cpSize         = 8,
        cpSpacing      = 3,
        cpColor        = { r = 1.0, g = 0.85, b = 0.20 },
        cpShape        = "square",
        cpPos          = "below",
        cpOffsetX      = 0,
        cpOffsetY      = 0,

        showRaidMarker = true,
        raidMarkerSize = 18,
        raidMarkerPos  = "left",
        raidMarkerX    = 0,
        raidMarkerY    = 0,

        friendlyShow      = true,
        friendlyPlayers   = "nameonly",
        friendlyNPCs      = "nameonly",
        friendlyNameColor = { r = 0.60, g = 0.80, b = 1.00 },
        friendlyNPCColor  = { r = 0.60, g = 1.00, b = 0.60 },
        showNPCTitle      = true,

        showDebuffs    = true,
        debuffsAll     = false,
        maxDebuffs     = 5,
        debuffSize     = 22,
        showBuffs      = false,
        maxBuffs       = 4,
        buffSize       = 20,
        showCC         = true,
        maxCC          = 2,
        ccSize         = 28,
        ccWidth        = 0,
        ccHeight       = 0,
        ccMatchBar     = false,
        auraSpacing    = 2,
        auraSwipe      = true,
        auraBorder     = true,
        auraTypeBorder = true,
        auraExpireFlash = true,
        auraExpirePct  = 30,

        -- Your own harmful auras on their own row. Not a spell-id whitelist:
        -- "cast by you" is what makes a refresh timer useful, and it can't miss
        -- a spell the way a curated DoT list inevitably would.
        showDots = false,
        maxDots  = 5,
        dotSize  = 22,

        -- Per-row placement. side = which end of the plate the row sits on,
        -- grow = which way the icons run from the anchor, perRow = 0 is one line.
        auraRows = {
            debuff = { side = "top",    x = 0, y = 0, grow = "center", spacing = 2, perRow = 0, filter = "all" },
            dot    = { side = "top",    x = 0, y = 0, grow = "center", spacing = 2, perRow = 0 },
            buff   = { side = "top",    x = 0, y = 0, grow = "center", spacing = 2, perRow = 0, filter = "all" },
            cc     = { side = "top",    x = 0, y = 0, grow = "center", spacing = 2, perRow = 0 },
        },
        showDispelGlow = true,
        dispelGlowBySchool = false,
        colDispel      = { r = 0.60, g = 0.40, b = 1.00 },
        showAuraTimer  = true,
        auraTimerDecimals = true,
        showAuraStacks = true,
        auraTimerSize  = 10,
        auraStackSize  = 9,
    },
})

local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitName, UnitReaction, UnitClass = UnitName, UnitReaction, UnitClass
local UnitIsPlayer, UnitCanAttack, UnitIsUnit = UnitIsPlayer, UnitCanAttack, UnitIsUnit
local UnitIsTapDenied = UnitIsTapDenied
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local UnitThreatSituation, UnitAffectingCombat = UnitThreatSituation, UnitAffectingCombat
local format, floor = string.format, math.floor

local DEFAULT_TEXTURE = "Atrocity"
local lsmStatusbar   = ns.MediaStatusbar
local textureValues  = ns.MediaStatusbarValues

local function lsmBorder(name)
    if ns.LSM and name then
        local hash = ns.LSM:HashTable("border")
        local path = hash and hash[name]
        if path and path ~= "" then return path end
    end
    return "Interface\\Buttons\\WHITE8X8"
end
local function borderTextureValues()
    local v = {}
    if ns.LSM and ns.LSM.List then
        for _, n in ipairs(ns.LSM:List("border")) do v[#v + 1] = { value = n, text = n } end
    end
    if #v == 0 then v[1] = { value = "Blizzard Tooltip", text = "Blizzard Tooltip" } end
    return v
end

local function db() return mod.db end

-- ---------------------------------------------------------------------------
-- Text slots: the same "one thing per slot" model the aura rows use, for the
-- texts ON the plate (user request, 02.08.2026).
--
-- Four slots -- above the bar, and left/centre/right INSIDE it -- and two things
-- that can fill them: the unit name and the health text. The level is not a slot
-- content: it rides at the name's left edge and reads as part of it, which is a
-- relationship a slot cannot express.
--
-- Stored per ELEMENT, not per slot, exactly like auraRows: the option page asks
-- "what is in this slot" by scanning, so an element can never be in two slots
-- and a slot can never hold two elements.
local TEXT_SLOT_ANCHOR = {
    -- slot -> point on the text, point on the health bar, x, y
    top    = { "BOTTOM", "TOP",    0,  3 },
    left   = { "LEFT",   "LEFT",   4,  0 },
    right  = { "RIGHT",  "RIGHT", -4,  0 },
    center = { "CENTER", "CENTER", 0,  0 },
}

function ns:NameplateTextCfg(key)
    local d = db()
    if type(d.textRows) ~= "table" then d.textRows = {} end
    local r = d.textRows[key]
    if type(r) ~= "table" then
        r = { slot = (key == "name") and "top" or "center", x = 0, y = 0 }
        d.textRows[key] = r
    end
    return r
end
local textCfg = function(key) return ns:NameplateTextCfg(key) end

-- One-time per profile, from the three switches that used to say the same thing
-- in longhand. nameInBar is the whole of it: on meant name left inside the bar
-- and the health text on the right, off meant name above and health centred --
-- which is exactly two slot assignments. A hidden element gets slot "none"
-- rather than being left pointing at a slot it does not occupy.
local function migrateTextSlots()
    local d = db()
    if not d or d.textRowsMigrated then return end
    local nameCfg, hpCfg = ns:NameplateTextCfg("name"), ns:NameplateTextCfg("health")
    if d.nameInBar then
        nameCfg.slot, hpCfg.slot = "left", "right"
    else
        nameCfg.slot, hpCfg.slot = "top", "center"
    end
    if d.showName == false then nameCfg.slot = "none" end
    if d.showHealthText == false or d.healthTextMode == "none" then hpCfg.slot = "none" end
    -- the old per-element offsets keep their meaning, just on the slot now
    nameCfg.x, nameCfg.y = d.nameOffsetX or 0, d.nameOffsetY or 0
    hpCfg.x,   hpCfg.y   = d.healthTextOffsetX or 0, d.healthTextOffsetY or 0
    d.textRowsMigrated = true      -- only after the work, never before
end
ns.MigrateNameplateTextSlots = migrateTextSlots

-- ---------------------------------------------------------------------------
-- General text: every text ON an aura icon or ON the cast bar carries a
-- POSITION now, and "none" is what switches it off (user request, 02.08.2026).
-- Four booleans became four pickers; migrateTextPositions below turns each old
-- answer into the place that text already occupied, so nothing moves by itself.
local AURA_TEXT_ANCHOR = {
    topleft     = { "TOPLEFT",     "TOPLEFT",      1, -1 },
    topright    = { "TOPRIGHT",    "TOPRIGHT",    -1, -1 },
    bottomleft  = { "BOTTOMLEFT",  "BOTTOMLEFT",   1,  1 },
    bottomright = { "BOTTOMRIGHT", "BOTTOMRIGHT",  2, -1 },
    center      = { "CENTER",      "CENTER",       0,  0 },
}
ns.NameplateAuraTextAnchor = AURA_TEXT_ANCHOR

-- The cast bar is one line, so its texts get sides rather than corners.
local CAST_TEXT_SIDE = { left = true, right = true, center = true }

local AURA_TEXT_ROWS = { "debuff", "dot", "buff", "cc" }

local function migrateTextPositions()
    local d = db()
    if not d or d.textPosMigrated then return end
    -- The duration was ONE setting for every row; it becomes one per row, all
    -- starting from the answer that setting already gave.
    local durPos = (d.showAuraTimer == false) and "none" or "center"
    for _, key in ipairs(AURA_TEXT_ROWS) do
        local c = ns:NameplateRowCfg(key)
        if c.timerPos == nil then c.timerPos = durPos end
    end
    if d.auraStackPos == nil then
        d.auraStackPos = (d.showAuraStacks == false) and "none" or "bottomright"
    end
    -- The cast name filled the bar; the target sat off its right edge.
    if d.castNameSide   == nil then d.castNameSide   = (d.showCastText == false) and "none" or "center" end
    if d.castTargetSide == nil then d.castTargetSide = d.castTargetText and "right" or "none" end
    d.textPosMigrated = true      -- only after the work, never before
end
ns.MigrateNameplateTextPositions = migrateTextPositions

local function auraTextPos(key)
    migrateTextPositions()
    return ns:NameplateRowCfg(key).timerPos or "center"
end

local function auraStackPos()
    migrateTextPositions()
    return db().auraStackPos or "bottomright"
end

-- Anchors one text into its slot. Returns whether it is shown, so the caller can
-- keep the aura queue's top reservation honest.
local function placeSlotText(fs, bar, key)
    migrateTextSlots()
    local cfg = textCfg(key)
    local a = TEXT_SLOT_ANCHOR[cfg.slot or "none"]
    if not a then fs:Hide(); return false end
    fs:ClearAllPoints()
    fs:SetPoint(a[1], bar, a[2], a[3] + (cfg.x or 0), a[4] + (cfg.y or 0))
    fs:Show()
    return true
end

-- The name shares the bar with the health value as soon as both sit inside it,
-- and a long name ran straight through the numbers (user report, 05.08.2026).
-- The client trims a font string with an ellipsis by itself once it has a width
-- and no word wrap, so all this does is hand it the width that is actually free.
--
-- The cap is only applied when the name would OVERFLOW. Left at width 0 the box
-- is the text, which is what keeps the level number -- anchored to the name's
-- left edge -- glued to the name instead of hanging off an oversized box. Once
-- the text is trimmed it fills the box exactly, so the edge is the text again.
local function clampNameWidth(f)
    if not (f and f.name and f.health) then return end
    local slot = textCfg("name").slot
    -- Above the bar, in no slot at all, or on a plate showing nothing but the
    -- name: nothing to stay clear of.
    if f._mode == "nameonly" or f._mode == "hidden"
        or (slot ~= "left" and slot ~= "right" and slot ~= "center") then
        if f._nameW ~= 0 then f._nameW = 0; f.name:SetWidth(0) end
        return
    end
    local budget = math.floor((f.health:GetWidth() or 0) - 8)
    local hslot = textCfg("health").slot
    -- Only a health value on the OTHER end takes room away. Sharing one slot is
    -- the user stacking them on purpose, and no width can fix that.
    if hslot ~= "none" and hslot ~= slot and f.healthText and f.healthText:IsShown() then
        budget = budget - math.ceil(f.healthText:GetStringWidth() or 0) - 6
    end
    if budget < 20 then budget = 20 end
    local w = ((f.name:GetStringWidth() or 0) > budget) and budget or 0
    -- Compared before it is written: this runs on every health change, and the
    -- answer only moves when the name, the numbers or the bar do.
    if f._nameW ~= w then f._nameW = w; f.name:SetWidth(w) end
end

-- No API for a unit's subname: scan line 2 of a hidden tooltip.
local scanTip = CreateFrame("GameTooltip", "VCUINameplateScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

local function getNPCTitle(unit)
    if not unit or UnitIsPlayer(unit) then return nil end
    scanTip:ClearLines()
    scanTip:SetUnit(unit)
    local fs = _G["VCUINameplateScanTipTextLeft2"]
    local txt = fs and fs:GetText()
    if not txt or txt == "" then return nil end
    if txt:find("%d") or txt:find("%?%?") then return nil end
    if LEVEL and txt:find(LEVEL) then return nil end
    return txt
end

-- Custom class colours have to win, and the table has to be looked up when the
-- colour is needed. The old version took RAID_CLASS_COLORS first - which is
-- always defined, so the custom branch was unreachable - and did it once at file
-- load, before an addon providing custom colours had necessarily loaded.
local function classColor(class)
    if not class then return nil end
    local t = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
    local c = t and t[class]
    if c then return c.r, c.g, c.b end
    return nil
end

local function reactionColor(d, ctx)
    if ctx.tapped then
        local c = d.colTapped; return c.r, c.g, c.b
    end
    if ctx.player and ctx.class then
        if ctx.enemy and d.classColorEnemy then
            local r, g, b = classColor(ctx.class); if r then return r, g, b end
        elseif (not ctx.enemy) and d.classColorFriendly then
            local r, g, b = classColor(ctx.class); if r then return r, g, b end
        end
    end
    local reaction = ctx.reaction or (ctx.enemy and 2 or 5)
    local c
    if reaction <= 3 then     c = d.colHostile
    elseif reaction == 4 then c = d.colNeutral
    else                      c = d.colFriendly end
    return c.r, c.g, c.b
end

-- UnitThreatSituation: 0 = not tanking, 1 = higher not tanking, 2 = tanking insecure, 3 = tanking secure.
local function threatColor(d, sit)
    if d.threatRole == "tank" then
        if sit == 3 then return d.colThreatGood
        elseif sit == 1 or sit == 2 then return d.colThreatWarn
        else return d.colThreatBad end
    else
        if sit >= 2 then return d.colThreatBad
        elseif sit == 1 then return d.colThreatWarn end
    end
    return nil
end

local function healthColor(d, ctx)
    local r, g, b
    if d.targetBarColor and ctx.isTarget then
        local c = d.colTargetBar
        r, g, b = c.r, c.g, c.b
    elseif d.threatEnabled and ctx.threat ~= nil then
        local c = threatColor(d, ctx.threat)
        if c then r, g, b = c.r, c.g, c.b end
    end
    if not r then r, g, b = reactionColor(d, ctx) end

    -- Dimming an enemy that is not fighting anyone pushes the ones that ARE
    -- forward without adding a second colour to read. Applied LAST, to whatever
    -- colour won above, so it works with reaction, class and threat colouring
    -- alike. Never on your own target: that one you meant to look at.
    if d.darkenOOC and ctx.enemy and not ctx.inCombat and not ctx.isTarget then
        local f = (d.darkenOOCPct or 45) / 100
        r, g, b = r * f, g * f, b * f
    end
    return r, g, b
end

local SPARK_TEX  = "Interface\\CastingBar\\UI-CastingBar-Spark"
local MASK_ROUND = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\csquare_mask.tga"

-- Dispel-school tints for aura borders. Blizzard's own table exists on this
-- client but is missing entries on some builds, so keep our own fallbacks.
local DISPEL_COLORS = {
    Magic   = { r = 0.20, g = 0.60, b = 1.00 },
    Curse   = { r = 0.60, g = 0.00, b = 1.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}
local function dispelColor(kind)
    if not kind or kind == "" then return nil end
    local bliz = _G.DebuffTypeColor and _G.DebuffTypeColor[kind]
    if bliz and bliz.r then return bliz end
    return DISPEL_COLORS[kind]
end

-- promoted to Core/Utils; these aliases keep the many local call sites short
local makeEdges, layoutEdges = ns.MakeEdges, ns.LayoutEdges

local function buildVisuals(f)
    f.health = CreateFrame("StatusBar", nil, f)
    f.healthBG = f.health:CreateTexture(nil, "BACKGROUND")
    f.healthBG:SetAllPoints(f.health)
    f.healthBG:SetColorTexture(0.05, 0.05, 0.06, 0.85)
    f.healthBorder = makeEdges(f.health, "BORDER")
    f.healthBD     = CreateFrame("Frame", nil, f.health, BackdropTemplateMixin and "BackdropTemplate")
    f.healthBD:SetAllPoints(f.health)
    f.healthBD:Hide()
    f.targetGlow   = makeEdges(f.health, "OVERLAY")
    f.focusGlow    = makeEdges(f.health, "OVERLAY")
    f.lowHpGlow    = makeEdges(f.health, "OVERLAY")
    f.absorb = f.health:CreateTexture(nil, "ARTWORK", nil, 2)
    f.absorb:Hide()
    f.execLine = f.health:CreateTexture(nil, "ARTWORK", nil, 3)
    f.execLine:Hide()
    f.cutaway = f.health:CreateTexture(nil, "ARTWORK", nil, 1)
    f.cutaway:SetColorTexture(1, 1, 1, 0.45)
    f.cutaway:Hide()
    f.hover = f.health:CreateTexture(nil, "ARTWORK", nil, 4)
    f.hover:SetAllPoints(f.health)
    f.hover:SetColorTexture(1, 1, 1, 0.12)   -- restated per apply, see applyLook
    f.hover:Hide()
    -- Glow riding the fill edge; tinted with the bar colour in paintHealth.
    f.spark = f.health:CreateTexture(nil, "ARTWORK", nil, 5)
    f.spark:SetTexture(SPARK_TEX)
    f.spark:SetBlendMode("ADD")
    f.spark:Hide()

    -- Name, level and title do NOT parent to the health bar: name-only mode
    -- hides that bar, and a text parented to a hidden frame goes with it.
    --
    -- But they cannot sit on the plate root either. The health bar is a CHILD
    -- of the root, so everything the bar draws -- its fill above all -- covers
    -- anything the root draws, and draw layers do not reach across frames. That
    -- stayed invisible while the name only ever sat ABOVE the bar; the moment a
    -- text slot puts it INSIDE, the name vanishes behind the fill while the
    -- health value beside it stays readable, because THAT one is created on the
    -- bar. Reported 03.08.2026 with a screenshot: name gone, value fine.
    --
    -- A sibling frame one level above the bar keeps both properties at once.
    f.textLayer = CreateFrame("Frame", nil, f)
    f.textLayer:SetAllPoints(f)
    f.textLayer:SetFrameLevel(f.health:GetFrameLevel() + 3)

    f.name = f.textLayer:CreateFontString(nil, "OVERLAY")
    f.name:SetPoint("BOTTOM", f.health, "TOP", 0, 3)
    -- Without this a name that hits the width clampNameWidth gives it would wrap
    -- onto a second line instead of being trimmed with an ellipsis.
    f.name:SetWordWrap(false)
    f.level = f.textLayer:CreateFontString(nil, "OVERLAY")
    f.level:SetPoint("RIGHT", f.name, "LEFT", -3, 0)
    f.level:Hide()
    f.title = f.textLayer:CreateFontString(nil, "OVERLAY")
    f.title:Hide()
    f.healthText = f.health:CreateFontString(nil, "OVERLAY")
    f.healthText:SetPoint("CENTER", f.health, "CENTER", 0, 0)

    f.cast = CreateFrame("StatusBar", nil, f)
    f.castBG = f.cast:CreateTexture(nil, "BACKGROUND")
    f.castBG:SetAllPoints(f.cast)
    f.castBG:SetColorTexture(0.05, 0.05, 0.06, 0.85)
    f.castBorder = makeEdges(f.cast, "BORDER")
    f.castBD     = CreateFrame("Frame", nil, f.cast, BackdropTemplateMixin and "BackdropTemplate")
    f.castBD:SetAllPoints(f.cast)
    f.castBD:Hide()
    f.castIcon = f.cast:CreateTexture(nil, "ARTWORK")
    f.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.castTarget = f.cast:CreateFontString(nil, "OVERLAY")
    f.castTarget:SetJustifyH("LEFT")
    f.castTarget:SetWordWrap(false)
    f.castTarget:Hide()
    f.castText = f.cast:CreateFontString(nil, "OVERLAY")
    f.castText:SetPoint("LEFT", f.cast, "LEFT", 3, 0)
    f.castText:SetPoint("RIGHT", f.cast, "RIGHT", -3, 0)
    f.castText:SetJustifyH("LEFT")
    f.castTimer = f.cast:CreateFontString(nil, "OVERLAY")
    f.castTimer:SetPoint("RIGHT", f.cast, "RIGHT", -3, 0)
    f.castTimer:SetJustifyH("RIGHT")
    f.castShield = f.cast:CreateTexture(nil, "OVERLAY", nil, 2)
    f.castShield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
    f.castShield:SetTexCoord(0, 36 / 64, 0, 1)
    f.castShield:Hide()
    f.kickTick = f.cast:CreateTexture(nil, "ARTWORK", nil, 3)
    f.kickTick:Hide()
    f.castSpark = f.cast:CreateTexture(nil, "ARTWORK", nil, 5)
    f.castSpark:SetTexture(SPARK_TEX)
    f.castSpark:SetBlendMode("ADD")
    f.castSpark:Hide()
    f.cast:Hide()

    f.debuffGroup = CreateFrame("Frame", nil, f); f.debuffGroup:SetSize(1, 1)
    f.dotGroup    = CreateFrame("Frame", nil, f); f.dotGroup:SetSize(1, 1)
    f.buffGroup   = CreateFrame("Frame", nil, f); f.buffGroup:SetSize(1, 1)
    f.ccGroup     = CreateFrame("Frame", nil, f); f.ccGroup:SetSize(1, 1)

    f.raidIcon = f:CreateTexture(nil, "OVERLAY")
    f.raidIcon:Hide()

    f.cpGroup = CreateFrame("Frame", nil, f); f.cpGroup:SetSize(1, 1)
    f.cpGroup.pips = {}
    f.cpGroup:Hide()
end

-- Rounded bars: one mask per bar, shared by the fill and everything riding on
-- it, so they all clip to the same shape. Tracked per texture because
-- SetStatusBarTexture hands back a different object when the texture changes.
local function maskApply(t, mask)
    if not (t and t.AddMaskTexture) then return end
    if t._vcMasked == mask then return end
    if t._vcMasked and t.RemoveMaskTexture then pcall(t.RemoveMaskTexture, t, t._vcMasked) end
    pcall(t.AddMaskTexture, t, mask)
    t._vcMasked = mask
end

local function maskClear(t)
    if not (t and t._vcMasked) then return end
    if t.RemoveMaskTexture then pcall(t.RemoveMaskTexture, t, t._vcMasked) end
    t._vcMasked = nil
end

-- The round shape does not fill its own image. Measured 02.08.2026 on
-- csquare_mask.tga: 128x128 with the shape at x=10..117, so a transparent border
-- of 10 px -- 7.8% -- runs all the way round it. SetAllPoints stretches that
-- border with the rest, which on a 120x15 health bar means about 11 px of dead
-- bar at each END and barely 1 px above and below. That is why it reads as a gap
-- on the left and the right only, and it is exactly what was reported.
--
-- The cure is to hang the mask OUT past the bar by the width of its own border,
-- so the shape lands on the bar's edges instead of inside them. Anchors only --
-- the shared mask file is not touched, so sliders, cooldown icons and the dark
-- skin keep the look they have.
--
-- NOT a fact about the client, and therefore deliberately NOT in Core/Wrath.lua:
-- the border is in the file and the gap appears wherever rounded bars are
-- switched on. It is scoped to this client generation by the owner's decision
-- (02.08.2026), taken with the measurement above on the table. Widening it later
-- is this one condition.
local MASK_SHAPE = 108 / 128     -- the shape's share of the mask image, per axis
local MASK_GROW  = (1 / MASK_SHAPE - 1) / 2

local function anchorRoundMask(bar)
    local m = bar._vcMask
    if not m then return end
    m:ClearAllPoints()
    local w, h = bar:GetWidth(), bar:GetHeight()
    -- Sizes are not always known the first time round; OnSizeChanged brings us
    -- back with real ones, and until then this is exactly today's behaviour.
    if not ns.Wrath.is or not w or not h or w <= 0 or h <= 0 then
        m:SetAllPoints(bar)
        return
    end
    local gx, gy = w * MASK_GROW, h * MASK_GROW
    m:SetPoint("TOPLEFT",     bar, "TOPLEFT",     -gx,  gy)
    m:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT",  gx, -gy)
end

-- Varargs, not a list: GetStatusBarTexture() can return nil, and a nil hole
-- would stop ipairs early and strand masks on the later textures.
local function applyBarRounding(bar, on, ...)
    if not bar then return end
    local mask
    if on and bar.CreateMaskTexture then
        if not bar._vcMask then
            bar._vcMask = bar:CreateMaskTexture()
            bar._vcMask:SetTexture(MASK_ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            -- The width and height sliders resize the bar without coming back
            -- through here, so the mask has to follow the bar itself.
            if not bar._vcMaskFollows then
                bar._vcMaskFollows = true
                bar:HookScript("OnSizeChanged", anchorRoundMask)
            end
        end
        anchorRoundMask(bar)
        mask = bar._vcMask
    end
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if t then
            if mask then maskApply(t, mask) else maskClear(t) end
        end
    end
end

local function applyBarBorder(bar, edges, bdFrame, d)
    local c = d.borderColor or ns.COLORS.borderDark or { r = 0, g = 0, b = 0 }
    local sz = d.borderSize or 1
    if d.borderStyle == "texture" and sz > 0 and bdFrame and bdFrame.SetBackdrop then
        if edges then for _, t in pairs(edges) do t:Hide() end end
        bdFrame:SetBackdrop({ edgeFile = lsmBorder(d.borderTexture), edgeSize = sz })
        bdFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        bdFrame:Show()
    else
        if bdFrame then bdFrame:Hide() end
        layoutEdges(edges, bar, sz, c.r, c.g, c.b, 1, 0)
    end
end

local function applyBarBorders(f, d)
    applyBarBorder(f.health, f.healthBorder, f.healthBD, d)
    -- The cast bar has its OWN border now (user request, 02.08.2026): its own
    -- thickness and its own colour, both falling back to the health bar's while
    -- they are absent -- so an untouched profile draws exactly what it did.
    -- Size 0 is what switches it off; there is no separate on/off, because a
    -- border of no thickness IS no border.
    --
    -- Overlaid on d rather than copied: applyBarBorder reads borderStyle and
    -- borderTexture too, and those stay shared -- two bars on one plate wearing
    -- different border STYLES is not a look anyone asked for.
    local castD = d
    local cs, cc = d.castBorderSize, d.castBorderColor
    -- One-time: the on/off switch this replaces, straight into a thickness.
    if cs == nil and d.borderOnCast == false then cs = 0 end
    if cs ~= nil or cc ~= nil then
        castD = setmetatable({
            borderSize  = cs or d.borderSize,
            borderColor = cc or d.borderColor,
        }, { __index = d })
    end
    applyBarBorder(f.cast, f.castBorder, f.castBD, castD)
end

-- f._castExtra widens the cast row while this plate is the target (set by paintTarget).
local function layoutCastRow(f, d)
    local w  = ns:PixelSnap(d.healthWidth, f)
    local ch = ns:PixelSnap(d.castHeight, f)
    local extra = f._castExtra or 0
    f.cast:ClearAllPoints()
    local castY = -(4 + ns:Pixel(f, d.borderSize)) + (d.castOffsetY or 0)
    local iconSz = ch * ((d.castIconScale or 100) / 100)
    if d.showCastIcon then
        if d.castIconRight then
            f.cast:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", (d.castOffsetX or 0) - extra / 2, castY)
        else
            f.cast:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", (d.castOffsetX or 0) + extra / 2, castY)
        end
    else
        f.cast:SetPoint("TOP", f.health, "BOTTOM", d.castOffsetX or 0, castY)
    end
    local cw = ((d.castWidth or 0) > 0 and ns:PixelSnap(d.castWidth, f) or w) + extra
    f.cast:SetSize(cw - (d.showCastIcon and (iconSz + 2) or 0), ch)
    return iconSz
end

local function layoutPlate(f)
    local d = db()
    local w  = ns:PixelSnap(d.healthWidth, f)
    local hh = ns:PixelSnap(d.healthHeight, f)
    local ch = ns:PixelSnap(d.castHeight, f)

    -- Vertical offset rides the plate root against its Blizzard anchor; the
    -- preview has no such parent, so it stays put.
    if f.unit then
        local host = f:GetParent()
        if host then
            f:ClearAllPoints()
            f:SetPoint("CENTER", host, "CENTER", 0, d.plateOffsetY or 0)
        end
    end

    f.health:ClearAllPoints()
    f.health:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.health:SetSize(w, hh)

    local iconSz = layoutCastRow(f, d)

    -- The slot decides where this sits now, not nameInBar (02.08.2026). The old
    -- pairing (name left -> health right, name above -> health centred) is what
    -- migrateTextSlots writes into the slots on first load, so nothing moves for
    -- a profile that never touches the new rows.
    placeSlotText(f.healthText, f.health, "health")
    clampNameWidth(f)      -- the bar it has to fit into may just have changed width

    f.castIcon:ClearAllPoints()
    if d.castIconRight then
        f.castIcon:SetPoint("LEFT", f.cast, "RIGHT", 2 + (d.castIconX or 0), d.castIconY or 0)
    else
        f.castIcon:SetPoint("RIGHT", f.cast, "LEFT", -2 + (d.castIconX or 0), d.castIconY or 0)
    end
    f.castIcon:SetSize(iconSz, iconSz)
    -- Set here, not at creation: this runs on every settings change, and the
    -- crop is the one thing about the icon a profile can now move.
    local iconCrop = (d.castIconCrop or 8) / 100
    f.castIcon:SetTexCoord(iconCrop, 1 - iconCrop, iconCrop, 1 - iconCrop)

    if f.castBG then
        local cbc = d.castBgColor or { r = 0.05, g = 0.05, b = 0.06 }
        f.castBG:SetColorTexture(cbc.r, cbc.g, cbc.b, 1)
        f.castBG:SetAlpha((d.castBgAlpha or 0) > 0 and d.castBgAlpha or (d.bgAlpha or 0.85))
    end

    if f.castShield then
        f.castShield:ClearAllPoints()
        f.castShield:SetSize(math.max(12, ch + 4), math.max(12, ch + 4))
        if d.showCastIcon then
            f.castShield:SetPoint("CENTER", f.castIcon, "CENTER", 0, -2)
        else
            f.castShield:SetPoint("CENTER", f.cast, "LEFT", 0, -2)
        end
    end

    if f.castTimer then
        migrateTextPositions()
        f.castTimer:ClearAllPoints()
        f.castText:ClearAllPoints()
        -- The name still spans whatever the timer leaves of the bar -- that part
        -- is unchanged. What the side picker adds is which END of that space the
        -- text sits at (user request, 02.08.2026); "none" hides it further down.
        if d.castTimerSide == "left" then
            f.castTimer:SetPoint("LEFT", f.cast, "LEFT", 3, 0)
            f.castTimer:SetJustifyH("LEFT")
            f.castText:SetPoint("LEFT", f.cast, "LEFT", d.castTimer and 30 or 3, 0)
            f.castText:SetPoint("RIGHT", f.cast, "RIGHT", -3, 0)
        else
            f.castTimer:SetPoint("RIGHT", f.cast, "RIGHT", -3, 0)
            f.castTimer:SetJustifyH("RIGHT")
            f.castText:SetPoint("LEFT", f.cast, "LEFT", 3, 0)
            f.castText:SetPoint("RIGHT", f.cast, "RIGHT", d.castTimer and -30 or -3, 0)
        end
        local side = d.castNameSide or "center"
        f.castText:SetJustifyH(CAST_TEXT_SIDE[side] and side:upper() or "CENTER")
    end

    applyBarBorders(f, d)
end

-- "SHADOW" is our own pseudo-flag: no outline, drop shadow instead.
local function plateFont(fs, size, flags)
    local d = db()
    local want = flags or d.fontOutline or "OUTLINE"
    local shadow = (want == "SHADOW")
    local realFlags = shadow and "" or want
    local face = d.fontFace
    local done = false
    if face and face ~= "" and ns.LSM then
        local path = ns.LSM:Fetch("font", face, true)
        if path then
            fs:SetFont(path, size, realFlags)
            done = true
        end
    end
    if not done and ns.UI and ns.UI.Font then ns.UI.Font(fs, size, realFlags) end
    if fs.SetShadowOffset then
        fs:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, shadow and 1 or 0) end
    end
end

local function skinPlate(f)
    local d = db()
    f.health:SetStatusBarTexture(lsmStatusbar(d.healthTexture))
    f.cast:SetStatusBarTexture(lsmStatusbar(d.castTexture))
    f.healthBG:SetAlpha(d.bgAlpha or 0.85)
    f.castBG:SetAlpha(d.bgAlpha or 0.85)

    -- must run after SetStatusBarTexture: that call can swap the texture object
    applyBarRounding(f.health, d.roundedBars, f.health:GetStatusBarTexture(),
        f.healthBG, f.absorb, f.cutaway, f.hover)
    applyBarRounding(f.cast, d.roundedBars, f.cast:GetStatusBarTexture(), f.castBG)

    do
        local function pick(own, fallback) return (own and own > 0) and own or fallback end
        plateFont(f.name, d.nameSize)
        plateFont(f.title, pick(d.titleSize, math.max(7, d.nameSize - 2)))
        plateFont(f.healthText, pick(d.healthTextSize, d.fontSize))
        plateFont(f.castText, pick(d.castTextSize, d.fontSize))
        if f.castTimer then plateFont(f.castTimer, pick(d.castTimerSize, d.fontSize)) end
        if f.castTarget then plateFont(f.castTarget, pick(d.castTargetSize, d.fontSize)) end
        if f.level then plateFont(f.level, pick(d.levelSize, d.nameSize)) end
    end
    if f.hover then
        -- Set here and not only at creation: the plates come from a pool, so a
        -- frame built before the slider was touched would keep the old value
        -- for the rest of the session.
        f.hover:SetColorTexture(1, 1, 1, (d.hoverAlpha or 12) / 100)
    end
    if f.cast then
        -- In a pull, plates overlap and a cast bar can end up behind the plate
        -- of the mob standing in front. Lifting the bar one strata takes every
        -- cast bar above every plate at once -- what matters is not being
        -- covered, and that is a question between plates, not inside one.
        f.cast:SetFrameStrata(d.castInFront and "HIGH" or "MEDIUM")
    end
    f.title:SetTextColor(0.72, 0.72, 0.78)
    migrateTextPositions()
    -- The SLOT decides whether these two are drawn -- "none" is the off. They
    -- used to be gated on showName/showHealthText as well, which meant two
    -- owners for one answer: placeSlotText showed the text and this line hid it
    -- again. With the switches gone from the page (02.08.2026) that would also
    -- have stranded anyone whose profile had one of them off.
    f.name:SetShown(textCfg("name").slot ~= "none")
    f.healthText:SetShown(textCfg("health").slot ~= "none")
    f.castIcon:SetShown(d.showCastbar and d.showCastIcon)
    f.castText:SetShown(d.showCastbar and (d.castNameSide or "center") ~= "none")
    do
        local tc = d.castTextColor or { r = 1, g = 1, b = 1 }
        f.castText:SetTextColor(tc.r, tc.g, tc.b)
    end
    if f.castTimer then
        f.castTimer:SetShown(d.showCastbar and d.castTimer)
        local tc = d.castTimerColor or { r = 1, g = 1, b = 1 }
        f.castTimer:SetTextColor(tc.r, tc.g, tc.b)
    end
    if f.castTarget then
        -- Anchored to the cast bar's right end and pushed by its own offsets, so
        -- it can be parked under or beside the bar without fighting the spell
        -- name, which owns the inside of the bar.
        local ts = d.castTargetSide or "none"
        local ox, oy = d.castTargetX or 0, d.castTargetY or 0
        f.castTarget:ClearAllPoints()
        if ts == "left" then
            f.castTarget:SetPoint("RIGHT", f.cast, "LEFT", -6 + ox, oy)
            f.castTarget:SetJustifyH("RIGHT")
        elseif ts == "center" then
            -- Under the bar rather than on it: the inside belongs to the name.
            f.castTarget:SetPoint("TOP", f.cast, "BOTTOM", ox, -2 + oy)
            f.castTarget:SetJustifyH("CENTER")
        else
            f.castTarget:SetPoint("LEFT", f.cast, "RIGHT", 6 + ox, oy)
            f.castTarget:SetJustifyH("LEFT")
        end
        f.castTarget:SetShown(d.showCastbar and ts ~= "none")
    end
end

local function fmtShortNum(v)
    if v >= 1e6 then return format("%.1fm", v / 1e6)
    elseif v >= 1e4 then return format("%.1fk", v / 1e3) end
    return tostring(v)
end

-- Unshortened values read in groups of three (7,400), like the reference row
-- the user pointed at. The double reverse puts the commas from the right; the
-- final gsub strips the leading comma a 3/6/9-digit value would keep.
local function fmtGroupNum(v)
    local g = tostring(v):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (g:gsub("^,", ""))
end

local function healthTextString(d, cur, max)
    if d.healthTextMode == "none" or max <= 0 then return "" end
    local short = d.healthTextShort
    local pct = floor(cur / max * 100 + 0.5)
        .. (d.healthTextPercentSign ~= false and "%" or "")
    local curS = short and fmtShortNum(cur) or fmtGroupNum(cur)
    if d.healthTextMode == "current" then
        return curS
    elseif d.healthTextMode == "currentmax" then
        return curS .. "/" .. (short and fmtShortNum(max) or fmtGroupNum(max))
    elseif d.healthTextMode == "both" then
        return format(d.healthTextFormat or "%s (%s)", curS, pct)
    end
    return pct
end

-- OnUpdate lives on the health bar; the plate root's OnUpdate belongs to the cast bar.
local function smoothHealthTo(f, cur)
    local hb = f.health
    f._hGoal = cur
    if f._hShow == nil or math.abs(f._hShow - cur) < 0.5 then
        f._hShow = cur
        hb:SetValue(cur)
        hb:SetScript("OnUpdate", nil)
        if f.cutaway then f.cutaway:Hide() end
        return
    end
    hb:SetScript("OnUpdate", function(bar, e)
        local goal = f._hGoal or 0
        f._hShow = f._hShow + (goal - f._hShow) * math.min(1, (e or 0) * 14)
        if math.abs(goal - f._hShow) < 0.5 then
            f._hShow = goal
            bar:SetScript("OnUpdate", nil)
            if f.cutaway then f.cutaway:Hide() end
        end
        bar:SetValue(f._hShow)
        local ct = f.cutaway
        if ct then
            local _, mx = bar:GetMinMaxValues()
            local w = bar:GetWidth() or 0
            if f._hShow > goal + 0.5 and mx > 0 and w > 0 then
                local a = goal / mx
                ct:ClearAllPoints()
                ct:SetPoint("TOPLEFT", bar, "TOPLEFT", w * a, 0)
                ct:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", w * a, 0)
                ct:SetWidth(math.max(1, w * (f._hShow / mx - a)))
                ct:Show()
            else
                ct:Hide()
            end
        end
    end)
end

-- Glow pinned to the fill edge and tinted with the bar colour. Anchoring to the
-- status bar's own texture means it tracks the fill without any OnUpdate; it is
-- re-anchored on every paint because changing the bar texture swaps that object.
-- goalValue overrides the bar's live value: with smooth health the bar is still
-- animating towards 0, and the glow must vanish on the killing blow, not later.
local function paintSpark(bar, spark, r, g, b, show, width, hideAtZero, goalValue)
    if not spark then return end
    local tex = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local h = bar and bar:GetHeight() or 0
    if not (show and tex and h > 0) then spark:Hide(); return end
    local mn, mx = bar:GetMinMaxValues()
    local v = goalValue or bar:GetValue() or 0
    if mx <= mn then spark:Hide(); return end
    -- a dead unit shouldn't glow at the left edge; a cast legitimately starts there
    if hideAtZero and v <= mn then spark:Hide(); return end
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", tex, "RIGHT", 0, 0)
    spark:SetSize(math.max(2, width or 10), h * 1.6)
    spark:SetVertexColor(r, g, b, 0.85)
    spark:Show()
end

local function paintHealth(f, ctx, cur, max)
    local d = db()
    if max <= 0 then max = 1 end
    f.health:SetMinMaxValues(0, max)
    if d.healthSmooth and f.unit then
        smoothHealthTo(f, cur)
    else
        f._hShow = nil
        f.health:SetValue(cur)
        f.health:SetScript("OnUpdate", nil)
        if f.cutaway then f.cutaway:Hide() end
    end
    local r, g, b = healthColor(d, ctx)
    f.health:SetStatusBarColor(r, g, b)
    if f.healthBG then
        if d.bgTintByBar then
            f.healthBG:SetColorTexture(r * 0.28, g * 0.28, b * 0.28, 0.9)
        else
            -- The plain shade is a SETTING now (style section, 02.08.2026); the
            -- default is the 0.05/0.05/0.06 it was hardcoded to, so an untouched
            -- profile paints the same pixel. Alpha stays out of it -- bgAlpha
            -- already rides on the texture's own frame (see applyPlateStyle).
            local bc = d.bgColor
            f.healthBG:SetColorTexture((bc and bc.r) or 0.05, (bc and bc.g) or 0.05,
                                       (bc and bc.b) or 0.06, 0.85)
        end
    end
    paintSpark(f.health, f.spark, r, g, b, d.showSpark, d.sparkWidth, true, cur)
    -- The slot again, not the retired switch: with showHealthText still read
    -- here, a profile that had it off would show an empty text in a slot that
    -- says it is on -- and nothing on the page could put the text back.
    if textCfg("health").slot ~= "none" then
        f.healthText:SetText(healthTextString(d, cur, max))
    end
    -- After the numbers, not before: how much room the name has left depends on
    -- what they now read.
    clampNameWidth(f)

    -- A ring around the bar once the unit drops below the mark. Painted here
    -- rather than on a ticker: this runs on every health change anyway, which is
    -- exactly when the answer can change.
    if f.lowHpGlow then
        if d.lowHpGlow and (cur / max) <= ((d.lowHpPct or 35) / 100) then
            local c = d.colLowHp or { r = 1, g = 0.2, b = 0.2 }
            layoutEdges(f.lowHpGlow, f.health, 2, c.r, c.g, c.b, 1, 1)
        else
            for _, t in pairs(f.lowHpGlow) do t:Hide() end
        end
    end
end

local function paintAbsorb(f, cur, max, absorb)
    local d = db()
    local ab = f.absorb
    if not d.showAbsorb or not absorb or absorb <= 0 or max <= 0 then ab:Hide(); return end
    local w = f.health:GetWidth() or 0
    if w <= 0 then ab:Hide(); return end
    local startFrac = cur / max
    if startFrac > 1 then startFrac = 1 end
    local absorbFrac = absorb / max
    if startFrac + absorbFrac > 1 then absorbFrac = 1 - startFrac end
    if absorbFrac <= 0 then ab:Hide(); return end
    -- The style IS the texture, same as where this idea comes from. "flat" keeps
    -- the old plain fill; anything else is one of our bar textures, tinted with
    -- the absorb colour. Resolved through the same helper the bars use, so a
    -- texture that exists for the health bar exists here too -- no second list
    -- of paths that could rot on its own.
    local c = d.colAbsorb
    local a = d.absorbAlpha or 0.55
    local style = d.absorbStyle or "flat"
    if style == "flat" then
        ab:SetTexture(nil)
        ab:SetColorTexture(c.r, c.g, c.b, a)
    else
        ab:SetTexture(lsmStatusbar(style))
        ab:SetVertexColor(c.r, c.g, c.b, a)
    end
    ab:ClearAllPoints()
    ab:SetPoint("TOPLEFT", f.health, "TOPLEFT", w * startFrac, 0)
    ab:SetPoint("BOTTOMLEFT", f.health, "BOTTOMLEFT", w * startFrac, 0)
    ab:SetWidth(w * absorbFrac)
    ab:Show()
end

local function paintExec(f, isTarget)
    local d = db()
    local ln = f.execLine
    if not ln then return end
    if not d.execLine or (d.execTargetOnly and not isTarget) then ln:Hide(); return end
    local w = f.health:GetWidth() or 0
    if w <= 0 then ln:Hide(); return end
    local x = w * (d.execPct or 20) / 100
    local c = d.colExec
    ln:SetColorTexture(c.r, c.g, c.b, 0.9)
    ln:ClearAllPoints()
    ln:SetPoint("TOPLEFT", f.health, "TOPLEFT", x - 1, 0)
    ln:SetPoint("BOTTOMLEFT", f.health, "BOTTOMLEFT", x - 1, 0)
    ln:SetWidth(2)
    ln:Show()
end

-- One scale chain for every plate: host normalization × global × target ×
-- casting.
--
-- The normalization lands every plate in UIPARENT units (cal = UIParent ES /
-- actual host ES). Measured on the live client (/dump rounds, 01.08.2026):
-- the client scales the SELECTED target's host up by ~1.16, which stacked on
-- top of our own target-scale option and made the target plate fatter than
-- the configured numbers. Dividing by the real host scale removes every such
-- quirk and puts plates in the same units as the rest of the interface --
-- which is also exactly the reference's PROPORTION at its pinned UI scale,
-- at every window size. (A first attempt calibrated plates to physical
-- pixels instead; on a small game window that made them dwarf the rest of
-- the UI -- user screenshot, 01.08.2026. Physical-pixel purists get that
-- look by setting the UI scale itself to 768/screen height.)
-- The base scale plates render at. Default: UI units, same as the rest of
-- the interface. Pixel-perfect option: 768/screen height -- 1 setting unit
-- == 1 physical pixel on any monitor and UI scale, which is the space the
-- "Modern" numbers were tuned in.
local function plateBaseScale(d)
    if d and d.pixelPerfect then
        local _, physH = GetPhysicalScreenSize()
        if physH and physH > 0 then return 768 / physH end
    end
    local ui = UIParent:GetEffectiveScale() or 1
    if ui <= 0 then ui = 1 end
    return ui
end

local function applyPlateScale(f, isTarget)
    if not f.unit then return end
    local d = db()
    local base = plateBaseScale(d)
    local cal
    if f.SetIgnoreParentScale then
        -- Decouple from the host entirely: with ignore-parent-scale our own
        -- scale IS the effective scale, so plates sit at UI units no matter
        -- what the host runs at or WHEN it changes. The division fallback
        -- below is a snapshot and measured 2x off when the host rescaled
        -- after we read it (dump: 33 px for a height of 27).
        -- Asserted UNCONDITIONALLY: onPlateAdded re-parents pooled frames on
        -- every add, and whether SetParent preserves the ignore flag is
        -- engine behavior we cannot read from source. A stale "already set"
        -- guard would turn that quirk into intermittently smaller plates;
        -- one C call per add is cheaper than that bug (review find).
        f:SetIgnoreParentScale(true)
        cal = base
    else
        local host = f:GetParent()
        local hostES = (host and host.GetEffectiveScale and host:GetEffectiveScale()) or 1
        if hostES <= 0 then hostES = 1 end
        cal = base / hostES
        if cal ~= cal or cal <= 0 then cal = 1 end
        if cal < 0.4 then cal = 0.4 elseif cal > 2 then cal = 2 end
    end
    local s = cal * (d.globalScale or 100) / 100
    if isTarget == nil then isTarget = UnitIsUnit(f.unit, "target") end
    if isTarget then s = s * (d.targetScale or 100) / 100 end
    if d.castEmphasis and f._casting then s = s * (d.castEmphScale or 100) / 100 end
    if s <= 0 then s = 1 end
    if math.abs((f:GetScale() or 1) - s) > 0.001 then f:SetScale(s) end
end

-- Single source of truth for a plate's alpha; cast start/stop call it directly
-- so a caster brightens the moment it starts, not at the next target change.
local function applyPlateAlpha(f, haveTarget)
    local d = db()
    if haveTarget == nil then haveTarget = UnitExists("target") end
    local a = 1
    if haveTarget and d.nonTargetAlpha < 1
        and not (f.unit and UnitIsUnit(f.unit, "target")) then
        a = d.nonTargetAlpha
    end
    if d.castEmphasis and f._casting then
        a = math.max(a, (d.castEmphAlpha or 100) / 100)
    end
    f:SetAlpha(a)
end

-- Two arrows pointing IN at the target's bar, one per side.
--
-- ChatFrameExpandArrow rather than something prettier: it ships with every
-- client this addon covers, so there is no path that can silently render
-- nothing. The left one is the same texture mirrored -- one asset, two sides.
local ARROW_TEX = "Interface\\ChatFrame\\ChatFrameExpandArrow"

local function paintTargetArrows(f, isTarget)
    local d = db()
    local on = d.targetArrows and isTarget
    if not f.arrowL then
        if not on then return end                 -- nothing to hide, nothing to build
        f.arrowL = f.health:CreateTexture(nil, "OVERLAY")
        f.arrowR = f.health:CreateTexture(nil, "OVERLAY")
        f.arrowL:SetTexture(ARROW_TEX)
        f.arrowR:SetTexture(ARROW_TEX)
        f.arrowR:SetTexCoord(1, 0, 0, 1)          -- mirrored, so it points inward too
    end
    if not on then
        f.arrowL:Hide(); f.arrowR:Hide()
        return
    end
    local size = d.targetArrowSize or 14
    local gap  = d.targetArrowGap or 4
    local c    = d.colTargetArrow or { r = 1, g = 1, b = 1 }
    for _, t in ipairs({ f.arrowL, f.arrowR }) do
        t:SetSize(size, size)
        t:SetVertexColor(c.r, c.g, c.b)
        t:Show()
    end
    f.arrowL:ClearAllPoints()
    f.arrowL:SetPoint("RIGHT", f.health, "LEFT", -gap, 0)
    f.arrowR:ClearAllPoints()
    f.arrowR:SetPoint("LEFT", f.health, "RIGHT", gap, 0)
end

local function paintTarget(f, isTarget)
    local d = db()
    paintTargetArrows(f, isTarget)
    if d.targetHighlight and isTarget then
        local c = d.colTarget
        layoutEdges(f.targetGlow, f.health, math.max(1, d.borderSize + 1),
            c.r, c.g, c.b, 1, d.borderSize)
    else
        if f.targetGlow then for _, t in pairs(f.targetGlow) do t:Hide() end end
    end
    local extra = 0
    if d.targetHighlight and isTarget and (d.castWidth or 0) == 0 then
        extra = 2 * ns:Pixel(f.health, math.max(1, d.borderSize + 1))
    end
    if (f._castExtra or 0) ~= extra then
        f._castExtra = extra
        layoutCastRow(f, d)
    end
    applyPlateScale(f, isTarget)
end

-- A short mark on the focus target's plate -- one letter by default, because
-- that reads at a glance and costs no room. A ring around the bar says "this
-- one is special"; the letter says WHICH special, which matters as soon as the
-- target ring is on too.
local function paintFocusMark(f, isFocus)
    local d = db()
    local on = d.focusMark and isFocus
    if not f.focusMark then
        if not on then return end
        f.focusMark = f.health:CreateFontString(nil, "OVERLAY")
        f.focusMark:SetWordWrap(false)
    end
    if not on then f.focusMark:Hide(); return end

    local c = d.colFocusMark or d.colFocus or { r = 0.2, g = 0.6, b = 1 }
    f.focusMark:SetText(d.focusMarkText ~= "" and d.focusMarkText or "F")
    f.focusMark:SetTextColor(c.r, c.g, c.b)
    plateFont(f.focusMark, (d.focusMarkSize or 0) > 0 and d.focusMarkSize or d.nameSize)
    f.focusMark:ClearAllPoints()
    local p = d.focusMarkAnchor or "CENTER"
    f.focusMark:SetPoint(p, f.health, p, d.focusMarkX or 0, d.focusMarkY or 0)
    f.focusMark:Show()
end

local function paintFocus(f, isFocus)
    local d = db()
    paintFocusMark(f, isFocus)
    if d.focusHighlight and isFocus then
        local c = d.colFocus
        local thick = math.max(1, d.borderSize + 1)
        layoutEdges(f.focusGlow, f.health, thick,
            c.r, c.g, c.b, 1, d.borderSize + thick + 1)
    else
        if f.focusGlow then for _, t in pairs(f.focusGlow) do t:Hide() end end
    end
end

local KICK_IDS = {
    ROGUE   = { 38768, 1769, 1768, 1767, 1766 },
    WARRIOR = { 6554, 6552, 29704, 1672, 1671, 72 },
    MAGE    = { 2139 },
    SHAMAN  = { 25454, 10414, 10413, 10412, 8046, 8045, 8044, 8042 },
}
local kickSpell
local function findKickSpell()
    kickSpell = nil
    local _, class = UnitClass("player")
    local list = KICK_IDS[class]
    if not list then return end
    for _, id in ipairs(list) do
        if (IsPlayerSpell and IsPlayerSpell(id))
            or (not IsPlayerSpell and IsSpellKnown and IsSpellKnown(id)) then
            kickSpell = id
            return
        end
    end
end
local function kickOnCooldown()
    if not kickSpell then return false end
    local start, dur = GetSpellCooldown(kickSpell)
    return (start or 0) > 0 and (dur or 0) > 1.5
end

local function castColor(d, notInterruptible, f)
    if notInterruptible then return d.colCastNoInterrupt end
    if d.castYouColorOn and f and f.unit and UnitIsUnit(f.unit .. "target", "player") then
        return d.colCastYou
    end
    if d.kickColorOn and kickOnCooldown() then return d.colCastKickCd end
    if d.kickReadyColorOn and kickSpell and not kickOnCooldown() then return d.colCastKickReady end
    if d.castChannelColor and f and f._castChannel then return d.colCastChannel end
    return d.colCast
end

-- Who the caster is casting AT. Read through the unit's own target token, and
-- only when that token actually resolves: whether a nameplate token accepts the
-- "target" suffix is a client question, and the honest answer to "it might not"
-- is an empty line, not an error. It is your OWN name that matters most here,
-- so that case is coloured instead of just spelled out.
local function paintCastTarget(f)
    local fs = f.castTarget
    if not fs then return end
    local d = db()
    migrateTextPositions()
    if (d.castTargetSide or "none") == "none" or not f.unit then fs:Hide(); return end

    local tu = f.unit .. "target"
    if not UnitExists(tu) then fs:SetText(""); fs:Show(); return end

    fs:SetText(UnitName(tu) or "")
    if UnitIsUnit(tu, "player") then
        local c = d.colCastYou or { r = 1, g = 0.15, b = 0.15 }
        fs:SetTextColor(c.r, c.g, c.b)
    else
        fs:SetTextColor(0.85, 0.85, 0.88)
    end
    fs:Show()
end

local function paintCast(f, name, icon, notInterruptible)
    local d = db()
    local c = castColor(d, notInterruptible, f)
    f.cast:SetStatusBarColor(c.r, c.g, c.b)
    paintSpark(f.cast, f.castSpark, c.r, c.g, c.b, d.showSpark, d.sparkWidth)
    if (d.castNameSide or "center") ~= "none" then f.castText:SetText(name or "") end
    if d.showCastIcon then f.castIcon:SetTexture(icon) end
    paintCastTarget(f)
end

local UnitAura = UnitAura     -- Compat.lua guarantees this exists on this client
local wipe = wipe

local _dbuf, _bbuf, _ccbuf, _dotbuf = {}, {}, {}, {}   -- scratch aura lists (single-threaded reuse)
local _harm = {}   -- one full HARMFUL scan per update; the harmful rows derive from it

-- No CROWD_CONTROL aura filter on this client, so CC is matched by spell id.
local CC_SPELLS = {}
for _, id in ipairs({
    -- Mage
    118, 12824, 12825, 12826, 28271, 28272, 61305, 61721, 61780,
    122, 865, 6131, 10230, 27088,
    33395,
    31661, 33041, 33042, 33043,
    12355,
    -- Warlock
    5782, 6213, 6215, 6789, 17925, 17926, 27223,
    5484, 17928,
    6358,
    710, 18647,
    30283, 30413, 30414,
    -- Priest
    8122, 8124, 10888, 10890,
    9484, 9485, 10955,
    605, 10911, 10912,
    -- Rogue
    6770, 2070, 11297,
    2094,
    1776, 1777, 8629, 11285, 11286, 38764,
    408, 8643,
    1833,
    -- Druid
    33786,
    2637, 18657, 18658,
    339, 1062, 5195, 5196, 9852, 9853, 26989,
    19970, 19971, 19972, 19973, 19974, 19975,
    5211, 6798, 8983,
    9005, 9823, 9827, 27006,
    22570,
    -- Hunter
    3355, 14308, 14309,
    19386, 24132, 24133, 27068,
    19503,
    24394,
    1513, 14326, 14327,
    -- Paladin
    853, 5588, 5589, 10308,
    20066,
    10326,
    -- Warrior
    5246,
    12809,
    7922,
    20253, 20614, 20615, 25274,
    -- Racials / misc / pets
    20549,
    1098, 11725, 11726,
}) do CC_SPELLS[id] = true end

-- Classes that can remove a Magic buff from an enemy; UnitAura's isStealable flags such buffs.
local CAN_REMOVE_MAGIC = { MAGE = true, PRIEST = true, SHAMAN = true, WARLOCK = true }
local playerCanSteal = false   -- set in OnEnable from the player's class

local function fmtAuraTime(s)
    if s >= 3600 then return floor(s / 3600 + 0.5) .. "h"
    elseif s >= 60 then return floor(s / 60 + 0.5) .. "m"
    elseif s >= 10 then return tostring(floor(s))
    elseif s > 0 then
        if db().auraTimerDecimals ~= false then return format("%.1f", s) end
        return tostring(math.ceil(s))
    end
    return ""
end

-- mode: nil = all, "skipcc" = exclude CC spells, "cconly" = only CC spells.
-- skipMine drops auras you cast yourself, so the debuff row can hand those over
-- to the dedicated own-debuff row instead of showing each one twice.
-- The entry tables are recycled per buffer and per position. Wiping the buffer
-- threw the old entries away, so every aura on every plate on every UNIT_AURA
-- allocated a fresh table - with two scans of up to forty slots per plate, this
-- was the largest allocator in the addon. Lua 5.1 has no generational collector,
-- so that is what turns into a periodic hitch on a big pull. The buffers are a
-- fixed set of module-level tables, and nothing holds an entry past the layout
-- call that consumes it, so position-keyed reuse is safe. The pool cannot live
-- on the buffer itself: wipe() would clear it too.
local auraRecPools = {}

local function auraRec(out, n)
    local pool = auraRecPools[out]
    if not pool then pool = {}; auraRecPools[out] = pool end
    local rec = pool[n]
    if not rec then rec = {}; pool[n] = rec end
    return rec
end

local function collectAuras(unit, filter, max, out, mode, skipMine)
    wipe(out)
    local n = 0
    for i = 1, 40 do
        local name, icon, count, dispelType, duration, expiration, caster,
              stealable, _, spellId = UnitAura(unit, i, filter)
        if not name then break end
        local isCC = spellId and CC_SPELLS[spellId] or false
        local mine = (caster == "player")
        local keep = true
        if mode == "skipcc" then keep = not isCC
        elseif mode == "cconly" then keep = isCC end
        if keep and skipMine and mine then keep = false end
        if keep then
            n = n + 1
            local rec = auraRec(out, n)
            rec.icon       = icon
            rec.count      = count or 0
            rec.duration   = duration or 0
            rec.expiration = expiration or 0
            rec.dispelType = dispelType
            rec.mine       = mine
            rec.isCC       = isCC
            rec.dispel     = (stealable and playerCanSteal) and true or false
            out[n] = rec
            if n >= max then break end
        end
    end
    return out
end

local function makeAuraIcon(container)
    local ic = CreateFrame("Frame", nil, container)
    ic.tex = ic:CreateTexture(nil, "ARTWORK")
    ic.tex:SetAllPoints(ic)
    ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic.cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
    ic.cd:SetAllPoints(ic.tex)
    ic.cd:SetHideCountdownNumbers(true)
    ic.cd:SetDrawEdge(false)
    ic.border = makeEdges(ic, "OVERLAY")
    ic.dispelGlow = makeEdges(ic, "OVERLAY")
    ic.top = CreateFrame("Frame", nil, ic)
    ic.top:SetAllPoints(ic)
    ic.top:SetFrameLevel(ic.cd:GetFrameLevel() + 5)
    ic.timer = ic.top:CreateFontString(nil, "OVERLAY")
    ic.timer:SetPoint("CENTER", ic, "CENTER", 0, 0)
    ic.count = ic.top:CreateFontString(nil, "OVERLAY")
    ic.count:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 2, -1)
    return ic
end

local function hideGroup(g)
    if not g then return end
    g:SetScript("OnUpdate", nil)
    g._active = 0
    if g.icons then for _, ic in ipairs(g.icons) do ic:Hide() end end
end

-- One shared handler instead of a fresh closure per row per UNIT_AURA: on a big
-- pull the closures were the last remaining allocator in this path (the entry
-- tables are pooled above). Everything it needs lives on the group/icons.
local function auraGroupOnUpdate(self, elapsed)
    self._t  = (self._t or 0) + elapsed
    self._tt = (self._tt or 0) + elapsed
    local doPulse = self._flash and self._t >= 0.05
    local doText  = self._showTimer and self._tt >= 0.1
    if not (doPulse or doText) then return end
    if doPulse then self._t = 0 end
    if doText  then self._tt = 0 end
    local now = GetTime()
    local pct = ((db().auraExpirePct or 30)) / 100
    for i = 1, (self._active or 0) do
        local ic = self.icons[i]
        local rem = (ic._exp and ic._exp > 0) and (ic._exp - now) or nil
        if doText then
            -- repaint only when the displayed value can have changed
            local bucket = false
            if ic._showTimer and rem and rem > 0 then
                bucket = (rem >= 10) and math.floor(rem) or math.floor(rem * 10)
            end
            if ic._timerBucket ~= bucket then
                ic._timerBucket = bucket
                ic.timer:SetText(bucket and fmtAuraTime(rem) or "")
            end
        end
        if doPulse then
            if rem and rem > 0 and (ic._dur or 0) > 0 and rem <= (ic._dur * pct) then
                ic:SetAlpha(0.45 + 0.55 * math.abs(math.sin(now * 4)))
            elseif ic:GetAlpha() ~= 1 then
                ic:SetAlpha(1)
            end
        end
    end
end

local function renderAuraGroup(g, list, o)
    local d = db()
    local n = #list
    g.icons = g.icons or {}
    for i = #g.icons + 1, n do g.icons[i] = makeAuraIcon(g) end

    local size    = o.size or 22
    local spacing = o.spacing or 2
    -- How much of each edge the icon trims. The client bakes a border into the
    -- icon art, and how much of it to cut is taste, not a constant -- so every
    -- aura row carries its own. Absent means the 0.08 every plate icon used to
    -- hardcode, which is why an untouched profile draws exactly as before.
    local crop    = o.crop or 0.08
    local showTimer, showStacks, swipe = o.showTimer, o.showStacks, o.swipe
    local iw, ih = (o.w and o.w > 0) and o.w or size, (o.h and o.h > 0) and o.h or size
    local perRow = (o.perRow or 0) > 0 and o.perRow or n
    local grow   = o.grow or "center"
    local lines  = math.max(1, math.ceil(n / perRow))
    -- The aura border has its own switch and its own colour. Off is thickness
    -- zero, so nothing else in the layout has to know about it; the THICKNESS
    -- still comes from the module-wide border size, because an icon rim that
    -- disagreed with every other rim on the plate would read as a mistake.
    local bc = d.auraBorderColor or ns.COLORS.borderDark or { r = 0, g = 0, b = 0 }
    local bsz = (d.auraBorder == false) and 0 or (d.borderSize or 0)
    for i, ic in ipairs(g.icons) do
        local a = list[i]
        if a then
            local line = math.floor((i - 1) / perRow)          -- 0 = nearest the plate
            local col  = (i - 1) % perRow
            local inLine = math.min(perRow, n - line * perRow) -- last line can be short
            local dx, dy
            local onSide = (o.side == "left" or o.side == "right")
            if o.vertical then
                -- A column, centred on its anchor. Above the plate it stacks
                -- upward (first aura nearest the bar), everywhere else
                -- downward -- which for the side slots is the shape this
                -- always drew.
                if     grow == "right" and not onSide then dx =  0.5 * (iw + spacing)
                elseif grow == "left"  and not onSide then dx = -0.5 * (iw + spacing)
                else   dx = 0 end
                dy = ((o.side == "top") and 1 or -1) * ((i - 1) - (n - 1) / 2) * (ih + spacing)
            elseif onSide then
                -- A row BESIDE the plate (cfg.orient = "h"): the block hangs
                -- centred on the bar's edge, so lines centre too -- mirrored,
                -- first aura nearest the plate.
                local m = (o.side == "left") and -1 or 1
                dx = m * (col - (inLine - 1) / 2) * (iw + spacing)
                dy = -(line - (lines - 1) / 2) * (ih + spacing)
            else
                if     grow == "right" then dx =  (col + 0.5) * (iw + spacing)
                elseif grow == "left"  then dx = -(col + 0.5) * (iw + spacing)
                else   dx = (col - (inLine - 1) / 2) * (iw + spacing) end
                -- extra lines stack away from the plate, whichever side the row is on
                dy = line * (ih + spacing) * ((o.side == "bottom") and -1 or 1)
                   - (lines - 1) * (ih + spacing) / 2 * ((o.side == "bottom") and -1 or 1)
            end
            ic:SetSize(iw, ih)
            ic:ClearAllPoints()
            ic:SetPoint("CENTER", g, "CENTER", dx, dy)
            ic.tex:SetTexture(a.icon)
            -- Compared before it is written: this loop runs per icon per row per
            -- UNIT_AURA, and the value only ever changes when a slider moves.
            if ic._crop ~= crop then
                ic._crop = crop
                ic.tex:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
            end
            -- Border takes the dispel school's colour so you can read what is
            -- removable at a glance; plain dark border when there is no school.
            -- Thickness is never forced: border size 0 means the user wants none.
            local ec = (d.auraTypeBorder and dispelColor(a.dispelType)) or bc
            layoutEdges(ic.border, ic, bsz, ec.r, ec.g, ec.b, 1, 0)
            if d.showDispelGlow and a.dispel then
                -- Either one colour for "you can remove this", or the aura's own
                -- school -- magic blue, curse purple, disease orange, poison
                -- green. The school is the more useful of the two once you play
                -- a class that can remove more than one kind.
                local gc = d.colDispel
                if d.dispelGlowBySchool then
                    gc = dispelColor(a.dispelType) or gc
                end
                layoutEdges(ic.dispelGlow, ic, 2, gc.r, gc.g, gc.b, 1, 1)
            else
                for _, t in pairs(ic.dispelGlow) do t:Hide() end
            end
            if swipe and a.duration > 0 and a.expiration > 0 then
                ic.cd:SetCooldown(a.expiration - a.duration, a.duration); ic.cd:Show()
            else
                ic.cd:Hide()
            end
            -- Re-anchored only on a change: this loop runs per icon per row per
            -- aura event, and a position only moves when a dropdown does.
            if ic._timerPos ~= o.timerPos then
                ic._timerPos = o.timerPos
                local a2 = AURA_TEXT_ANCHOR[o.timerPos or "center"]
                if a2 then
                    ic.timer:ClearAllPoints()
                    ic.timer:SetPoint(a2[1], ic, a2[2], a2[3], a2[4])
                end
            end
            if ic._stackPos ~= o.stackPos then
                ic._stackPos = o.stackPos
                local a2 = AURA_TEXT_ANCHOR[o.stackPos or "bottomright"]
                if a2 then
                    ic.count:ClearAllPoints()
                    ic.count:SetPoint(a2[1], ic, a2[2], a2[3], a2[4])
                end
            end
            plateFont(ic.timer, d.auraTimerSize)
            plateFont(ic.count, d.auraStackSize)
            -- Absent = white, which is what both drew before they had a colour
            -- of their own. Set here rather than once at creation because
            -- plateFont above can rebuild the font object.
            local tc = d.auraTimerColor
            ic.timer:SetTextColor((tc and tc.r) or 1, (tc and tc.g) or 1, (tc and tc.b) or 1)
            local sc = d.auraStackColor
            ic.count:SetTextColor((sc and sc.r) or 1, (sc and sc.g) or 1, (sc and sc.b) or 1)
            ic.count:SetText((showStacks and a.count > 1) and a.count or "")
            ic.timer:SetText("")
            ic._timerBucket = false
            ic._exp, ic._showTimer = a.expiration, showTimer
            ic._dur = a.duration
            ic:SetAlpha(1)
            ic:Show()
        else
            ic:Hide()
        end
    end
    g._active = n
    local flash = d.auraExpireFlash and (d.auraExpirePct or 30) > 0
    -- Two clocks: the pulse needs to be smooth, the countdown text does not.
    -- Rebuilding the text at pulse rate would triple the string churn.
    g._flash, g._showTimer = flash, showTimer
    if n > 0 and (showTimer or flash) then
        g:SetScript("OnUpdate", auraGroupOnUpdate)
    else
        g:SetScript("OnUpdate", nil)
    end
end

-- Draw order top to bottom within a side; each row carries its own placement.
local AURA_ROWS = {
    { key = "debuff", group = "debuffGroup", show = "showDebuffs", size = "debuffSize" },
    { key = "dot",    group = "dotGroup",    show = "showDots",    size = "dotSize"    },
    { key = "buff",   group = "buffGroup",   show = "showBuffs",   size = "buffSize"   },
    { key = "cc",     group = "ccGroup",     show = "showCC",      size = "ccSize",
      w = "ccWidth", h = "ccHeight" },
}

-- Heals rather than handing back a shared constant: the option setters write
-- straight into whatever this returns, so a shared table would have the first
-- drag of a slider overwrite the defaults for every row at once. A profile can
-- arrive with a non-table here via import, which ApplyDefaults will not repair.
function ns:NameplateRowCfg(key)
    local d = db()
    if type(d.auraRows) ~= "table" then d.auraRows = {} end
    local r = d.auraRows[key]
    if type(r) ~= "table" then
        r = { side = "top", x = 0, y = 0, grow = "center",
              spacing = 2, perRow = 0, filter = "all" }
        d.auraRows[key] = r
    end
    return r
end
local rowCfg = function(key) return ns:NameplateRowCfg(key) end

-- One-time per profile: the CC row used to be the only one with its own offset.
-- Folded into the per-row model so switching to that profile does not make the
-- row jump. Called from applyAuras too, because switching profiles repoints
-- mod.db without re-running OnEnable.
local function migrateAuraRows()
    local d = db()
    if not d or d.auraRowsMigrated then return end
    local cc = ns:NameplateRowCfg("cc")
    if (d.ccOffsetX or 0) ~= 0 then cc.x = d.ccOffsetX end
    if (d.ccOffsetY or 0) ~= 0 then cc.y = d.ccOffsetY end
    d.auraRowsMigrated = true      -- only after the work, never before
    -- Nothing reads these again; the per-row placement controls own the offsets
    -- now. Leaving them behind makes them look like settings with no control.
    d.ccOffsetX, d.ccOffsetY = nil, nil
end

-- Scratch tables, refilled per call: applyAuras runs per plate per UNIT_AURA,
-- and neither table outlives the call (renderAuraGroup copies what it needs).
local _used, _ro = {}, {}

local function applyAuras(f, lists)
    local d = db()
    migrateAuraRows()
    -- Rows on the same side queue outward from the plate; the two sides are
    -- independent, so moving one row to the bottom never shifts the other.
    -- The bottom side has to clear the cast bar, which hangs below the health
    -- bar. Reserved whenever the cast bar is enabled rather than only while it
    -- is visible, so rows do not jump every time the target starts casting.
    local castRoom = 4
    if d.showCastbar then
        castRoom = castRoom + (d.castHeight or 12) + (d.borderSize or 1) + 4
            - math.min(0, d.castOffsetY or 0)
    end
    local used = _used
    -- Only the name ABOVE the bar takes room from the aura rows. Once it can sit
    -- inside the bar (text slots, 02.08.2026) the old `showName` test would have
    -- left a name-sized gap over a plate whose name is not up there at all.
    local nameAbove = textCfg("name").slot == "top"
    used.top    = (nameAbove and (d.nameSize + 6) or 4) + (d.auraOffsetY or 0)
    used.bottom = castRoom - (d.auraOffsetY or 0)
    -- The two side columns queue OUTWARD from the bar's edges, the same idea as
    -- top and bottom but along the other axis. Started at a small gap rather
    -- than 0 so the first column does not touch the border.
    used.left   = 4 - (d.auraOffsetX or 0)
    used.right  = 4 + (d.auraOffsetX or 0)
    for _, row in ipairs(AURA_ROWS) do
        local group = f[row.group]
        local list  = lists[row.key]
        local cfg   = rowCfg(row.key)
        if group and d[row.show] and list and #list > 0 then
            local size = d[row.size] or 22
            local w = row.w and d[row.w] or nil
            local h = row.h and d[row.h] or nil
            -- The crowd-control row can take its size from the health bar
            -- instead of its own sliders: one square icon exactly as tall as the
            -- bar it stands beside. Pixel-snapped through the same call the bar
            -- itself goes through, or the two ends would miss each other by the
            -- fraction the snap removes. Width and height step aside for it --
            -- kept in the profile, so switching the option back off returns to
            -- the shape that was there before.
            if row.key == "cc" and d.ccMatchBar then
                size, w, h = ns:PixelSnap(d.healthHeight or 10, f), nil, nil
            end
            local iw = (w and w > 0) and w or size
            local ih = (h and h > 0) and h or size
            local spacing = cfg.spacing or d.auraSpacing or 2
            local perRow  = (cfg.perRow or 0)
            local rawSide = cfg.side or "top"
            local sideways = (rawSide == "left" or rawSide == "right")
            -- The stacking axis used to be welded to the slot (beside the
            -- plate = column, above/below = row). cfg.orient overrides it:
            -- "h"/"v", absent = the automatic verdict (user request,
            -- 31.07.2026). The slot still decides WHERE the block hangs.
            local vertical
            if cfg.orient == "h" then vertical = false
            elseif cfg.orient == "v" then vertical = true
            else vertical = sideways end
            local n = #list
            local side, blockH, blockW

            if vertical then
                -- One column, so the icon count IS the line count and the block
                -- reaches along the other axis. perRow is ignored here on
                -- purpose: a column that wrapped would grow into a second one
                -- and push over whatever it sits beside.
                blockH = n * ih + (n - 1) * spacing
                blockW = iw
            else
                local lines = (perRow > 0) and math.ceil(n / perRow) or 1
                local cols  = (perRow > 0) and math.min(perRow, n) or n
                blockH = lines * ih + (lines - 1) * spacing
                blockW = cols * iw + (cols - 1) * spacing
            end
            side = sideways and rawSide or ((rawSide == "bottom") and "bottom" or "top")

            group:ClearAllPoints()
            if sideways then
                local dx = used[side] + blockW / 2 + (cfg.x or 0)
                if side == "left" then
                    group:SetPoint("CENTER", f.health, "LEFT",  -dx, (cfg.y or 0))
                else
                    group:SetPoint("CENTER", f.health, "RIGHT",  dx, (cfg.y or 0))
                end
                used[side] = used[side] + blockW + spacing
            else
                -- Left/right growth pins to the matching plate edge so the row
                -- lines up with the bar; centred growth stays on the midline.
                local grow = cfg.grow or "center"
                local hp, gp = "CENTER", "CENTER"
                if     grow == "right" then hp, gp = "LEFT",  "LEFT"
                elseif grow == "left"  then hp, gp = "RIGHT", "RIGHT" end

                local dy = used[side] + blockH / 2 + (cfg.y or 0)
                if side == "bottom" then
                    group:SetPoint(gp, f.health, hp == "CENTER" and "BOTTOM"
                        or (hp == "LEFT" and "BOTTOMLEFT" or "BOTTOMRIGHT"),
                        (d.auraOffsetX or 0) + (cfg.x or 0), -dy)
                else
                    group:SetPoint(gp, f.health, hp == "CENTER" and "TOP"
                        or (hp == "LEFT" and "TOPLEFT" or "TOPRIGHT"),
                        (d.auraOffsetX or 0) + (cfg.x or 0), dy)
                end
                used[side] = used[side] + blockH + spacing
            end

            -- every field set anew: the table is reused across rows
            _ro.size, _ro.w, _ro.h, _ro.spacing = size, w, h, spacing
            _ro.grow, _ro.perRow, _ro.side = cfg.grow or "center", perRow, side
            _ro.vertical = vertical
            _ro.crop = cfg.crop
            -- "none" IS the off switch now; the old booleans became these
            -- positions in migrateTextPositions.
            _ro.timerPos = auraTextPos(row.key)
            _ro.stackPos = auraStackPos()
            _ro.showTimer   = _ro.timerPos ~= "none"
            _ro.showStacks  = _ro.stackPos ~= "none"
            _ro.swipe = d.auraSwipe
            renderAuraGroup(group, list, _ro)
        elseif group then
            hideGroup(group)
        end
    end
end

-- Drops entries a row's filter rejects, then trims to max. The client filter
-- string cannot express "removable", so it has to happen here -- and it has to
-- happen BEFORE the cap, or a target whose first entries are all unremovable
-- yields an empty row while a removable aura sits just past the cut.
local function applyRowFilter(list, filter, max)
    if not list then return list end
    if filter and filter ~= "all" then
        local keep = 0
        for i = 1, #list do
            local a = list[i]
            local ok = true
            if filter == "dispel" then
                -- harmful auras carry a school; enemy buffs carry the steal flag
                ok = (a.dispelType ~= nil and a.dispelType ~= "") or a.dispel == true
            elseif filter == "mine" then
                ok = a.mine == true
            end
            if ok then
                keep = keep + 1
                list[keep] = a
            end
        end
        for i = #list, keep + 1, -1 do list[i] = nil end
    end
    if max and max > 0 then
        for i = #list, max + 1, -1 do list[i] = nil end
    end
    return list
end

local _lists = {}

-- The debuff, own-debuff and CC rows are all views of the same HARMFUL list;
-- scanning it once and deriving the three rows here replaces up to three full
-- UnitAura sweeps of the same unit per event with one. mineOnly matches the
-- client's PLAYER filter (those auras carry caster == "player"), and mineOnly
-- and skipMine are never requested together. dst entries are references into
-- _harm, which stays untouched until the next scan.
local function deriveHarm(dst, ccOnly, skipCC, mineOnly, skipMine, max)
    local n = 0
    for i = 1, #_harm do
        local a = _harm[i]
        local keep
        if ccOnly then keep = a.isCC
        else keep = not (skipCC and a.isCC) end
        if keep and mineOnly and not a.mine then keep = false end
        if keep and skipMine and a.mine then keep = false end
        if keep then
            n = n + 1
            dst[n] = a
            if max and max > 0 and n >= max then break end
        end
    end
    for i = #dst, n + 1, -1 do dst[i] = nil end
    return dst
end

local function plateUpdateAuras(f)
    if not f.unit then return end
    if f._mode and f._mode ~= "full" then
        hideGroup(f.debuffGroup); hideGroup(f.dotGroup)
        hideGroup(f.buffGroup);   hideGroup(f.ccGroup)
        return
    end
    local d = db()
    -- Filters and caps interact, so collect wide (40 is the scan ceiling anyway)
    -- and let applyRowFilter do the trimming.
    local WIDE = 40
    wipe(_lists)
    if d.showDebuffs or d.showDots or d.showCC then
        collectAuras(f.unit, "HARMFUL", WIDE, _harm)
    end
    if d.showDebuffs then
        local cfg = rowCfg("debuff")
        local wantsMine = (cfg.filter == "mine")
        -- Your own auras belong to the dedicated row while it is on, or the two
        -- rows show an identical list twice on stock settings. A row explicitly
        -- set to "only mine" keeps them.
        local handOff = d.showDots and not wantsMine
        local mineOnly = wantsMine or (not d.debuffsAll and not handOff)
        deriveHarm(_dbuf, false, d.showCC, mineOnly, handOff)
        applyRowFilter(_dbuf, cfg.filter, d.maxDebuffs)
        _lists.debuff = _dbuf
    end
    if d.showDots then
        deriveHarm(_dotbuf, false, d.showCC, true, false)
        applyRowFilter(_dotbuf, nil, d.maxDots)
        _lists.dot = _dotbuf
    end
    if d.showBuffs then
        local cfg = rowCfg("buff")
        collectAuras(f.unit, "HELPFUL", WIDE, _bbuf)
        applyRowFilter(_bbuf, cfg.filter, d.maxBuffs)
        _lists.buff = _bbuf
    end
    if d.showCC then
        deriveHarm(_ccbuf, true, false, false, false, d.maxCC)
        _lists.cc = _ccbuf
    end
    applyAuras(f, _lists)
end

ns.plates = ns.plates or {}          -- unit token -> our plate frame  (side table, taint-safe)
local platePool = {}
local hookedUFs = {}
local offParent

local function ensureOffParent()
    if offParent then return offParent end
    offParent = CreateFrame("Frame", nil, UIParent)
    offParent:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -500)
    offParent:SetSize(1, 1)
    offParent:Hide()
    return offParent
end

-- Some UnitFrame children are flagged ignore-parent-alpha and render through alpha 0; un-flag them.
local function suppressChild(uf, r)
    if not (r and r.SetIgnoreParentAlpha) then return end
    pcall(r.SetIgnoreParentAlpha, r, false)
    if not hookedUFs[r] then
        hookedUFs[r] = true
        local locked = false
        hooksecurefunc(r, "SetIgnoreParentAlpha", function(self, v)
            if locked or not v then return end
            local u = uf.unit or (uf.GetUnit and uf:GetUnit())
            if not u or not ns.plates[u] then return end
            locked = true; pcall(self.SetIgnoreParentAlpha, self, false); locked = false
        end)
    end
end

local function hideBlizzard(nameplate)
    local uf = nameplate and nameplate.UnitFrame
    if not uf then return end
    uf:SetAlpha(0)
    -- Alpha alone is not enough: hide the frame and keep it hidden while our plate owns the unit.
    uf:Hide()
    suppressChild(uf, uf.HealthBarsContainer)
    suppressChild(uf, uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
    suppressChild(uf, uf.healthBar)
    suppressChild(uf, uf.name)
    suppressChild(uf, uf.castBar)
    suppressChild(uf, uf.AurasFrame)
    if not hookedUFs[uf] then
        hookedUFs[uf] = true
        uf:HookScript("OnShow", function(self)
            local u = self.unit or (self.GetUnit and self:GetUnit())
            if u and ns.plates[u] then self:Hide() end
        end)
        local locked = false
        hooksecurefunc(uf, "SetAlpha", function(self, a)
            if locked or a == 0 then return end
            local u = self.unit or (self.GetUnit and self:GetUnit())
            if not u or not ns.plates[u] then return end
            locked = true; self:SetAlpha(0); locked = false
        end)
    end
end

local function plateCastStop(f)
    f._casting = nil
    applyPlateScale(f)
    applyPlateAlpha(f)
    f.cast:Hide()
    f.cast:SetAlpha(1)
    if f.castShield then f.castShield:Hide() end
    if f.kickTick then f.kickTick:Hide() end
    if db().hideNameWhileCasting and f._mode == "full" then
        f.name:SetShown(db().showName)
    end
    f:SetScript("OnUpdate", nil)
end

-- CLEU and the UI event can arrive in either order, so both sides check the other.
local lastInterrupt = { guid = nil, name = nil, t = 0 }
local function onCombatLogEvent()
    if not db().castInterrupter then return end
    local _, sub, _, _, srcName, _, _, dstGUID = CombatLogGetCurrentEventInfo()
    if sub ~= "SPELL_INTERRUPT" or not dstGUID then return end
    lastInterrupt.guid, lastInterrupt.name, lastInterrupt.t = dstGUID, srcName, GetTime()
    for _, f in pairs(ns.plates) do
        if f._flashUntil and f._flashUntil > GetTime()
            and f.unit and UnitGUID(f.unit) == dstGUID and srcName then
            f.castText:SetFormattedText(L["Interrupted by %s"], srcName)
            f.castText:Show()
        end
    end
end

-- Shared handlers instead of one fresh closure per cast/flash: every mob that
-- starts a cast allocated one, constant churn in caster packs. State lives on
-- the frame (_flashUntil, _castEnd, ...).
local function castFlashOnUpdate(self)
    local left = (self._flashUntil or 0) - GetTime()
    if left <= 0 then self._flashUntil = nil; return plateCastStop(self) end
    self.cast:SetAlpha(math.min(1, left / 0.6))
end

local function plateCastFlash(f)
    local d = db()
    if not d.castInterruptFlash or not f._casting then return plateCastStop(f) end
    f._casting = nil
    if f.castShield then f.castShield:Hide() end
    if f.kickTick then f.kickTick:Hide() end
    if d.hideNameWhileCasting and f._mode == "full" then
        f.name:SetShown(textCfg("name").slot ~= "none")
    end
    local c = d.colInterruptFlash
    if f.castSpark then f.castSpark:Hide() end
    f.cast:SetMinMaxValues(0, 1)
    f.cast:SetValue(1)
    f.cast:SetStatusBarColor(c.r, c.g, c.b)
    f.cast:SetAlpha(1)
    f.cast:Show()
    local untilT = GetTime() + 0.8
    f._flashUntil = untilT
    if d.castInterrupter and f.unit and lastInterrupt.name
        and lastInterrupt.guid == UnitGUID(f.unit)
        and GetTime() - lastInterrupt.t < 1 then
        f.castText:SetFormattedText(L["Interrupted by %s"], lastInterrupt.name)
        f.castText:Show()
    end
    f:SetScript("OnUpdate", castFlashOnUpdate)
end

local function updateKickTick(f)
    local d = db()
    local tk = f.kickTick
    if not tk then return end
    if not d.castKickTick or f._castNoInt or not kickSpell or not f._casting then tk:Hide(); return end
    local s, du = GetSpellCooldown(kickSpell)
    if not s or s == 0 or (du or 0) <= 1.5 then tk:Hide(); return end
    local ready = s + du
    if ready >= f._castEnd then tk:Hide(); return end
    local frac = (ready - f._castStart) / (f._castEnd - f._castStart)
    if frac < 0 then frac = 0 end
    local w = f.cast:GetWidth() or 0
    if w <= 0 then tk:Hide(); return end
    local c = d.colKickTick
    tk:SetColorTexture(c.r, c.g, c.b, 0.95)
    tk:ClearAllPoints()
    tk:SetPoint("TOPLEFT", f.cast, "TOPLEFT", w * frac - 1, 0)
    tk:SetPoint("BOTTOMLEFT", f.cast, "BOTTOMLEFT", w * frac - 1, 0)
    tk:SetWidth(2)
    tk:Show()
end

local function castOnUpdate(self, elapsed)
    if not self._casting then return end
    local now = GetTime()
    if now >= self._castEnd then return plateCastStop(self) end
    self.cast:SetValue(self._castChannel and (self._castStart + (self._castEnd - now)) or now)
    if self.castTimer and self.castTimer:IsShown() then
        self.castTimer:SetFormattedText("%.1f", self._castEnd - now)
    end
    if not self._castNoInt then
        local d2 = db()
        if d2.kickColorOn or d2.kickReadyColorOn or d2.castKickTick or d2.castYouColorOn then
            self._kickAcc = (self._kickAcc or 0) + (elapsed or 0)
            if self._kickAcc > 0.2 then
                self._kickAcc = 0
                if d2.kickColorOn or d2.kickReadyColorOn or d2.castYouColorOn then
                    local c = castColor(d2, false, self)
                    self.cast:SetStatusBarColor(c.r, c.g, c.b)
                end
                if d2.castKickTick then updateKickTick(self) end
            end
        end
    end
end

local function plateCastStart(f)
    local d = db()
    if f._mode and f._mode ~= "full" then return plateCastStop(f) end
    if not d.showCastbar or not f.unit then return end
    local name, _, icon, startMs, endMs, _, _, notInterruptible = UnitCastingInfo(f.unit)
    local channel = false
    if not name then
        name, _, icon, startMs, endMs, _, notInterruptible = UnitChannelInfo(f.unit)
        channel = true
    end
    if not name then return plateCastStop(f) end
    f._casting  = true
    f._castStart = startMs / 1000
    f._castEnd   = endMs / 1000
    f._castChannel = channel
    f._castNoInt   = notInterruptible and true or false
    f._kickAcc     = 0
    applyPlateScale(f)
    applyPlateAlpha(f)
    f.cast:SetMinMaxValues(f._castStart, f._castEnd)
    -- seed the fill before painting so the edge glow anchors at the right spot
    f.cast:SetValue(channel and f._castEnd or f._castStart)
    paintCast(f, name, icon, notInterruptible)
    f.cast:SetAlpha(1)
    f.cast:Show()
    if f.castShield then f.castShield:SetShown(d.showCastShield and notInterruptible) end
    if d.hideNameWhileCasting then f.name:Hide() end
    updateKickTick(f)
    f:SetScript("OnUpdate", castOnUpdate)
end

local function plateModeFor(d, enemy, isPlayer)
    if enemy then return "full" end
    return isPlayer and d.friendlyPlayers or d.friendlyNPCs
end

local function applyPlateMode(f, mode)
    f._mode = mode
    local d = db()
    if mode == "hidden" then
        f.health:Hide(); f.cast:Hide(); f.name:Hide(); f.title:Hide()
        if f.level then f.level:Hide() end
        hideGroup(f.debuffGroup); hideGroup(f.dotGroup); hideGroup(f.buffGroup); hideGroup(f.ccGroup)
    elseif mode == "nameonly" then
        f.health:Hide(); f.cast:Hide()
        hideGroup(f.debuffGroup); hideGroup(f.dotGroup); hideGroup(f.buffGroup); hideGroup(f.ccGroup)
        f.name:ClearAllPoints()
        f.name:SetPoint("CENTER", f, "CENTER", 0, 0)
        f.name:Show()
        f.title:ClearAllPoints()
        f.title:SetPoint("TOP", f.name, "BOTTOM", 0, -1)
    else
        f.health:Show()
        -- The slot owns the placement; showName still owns whether it is drawn
        -- at all, so the switch on the page keeps working and an element parked
        -- in no slot stays hidden either way.
        local placed = placeSlotText(f.name, f.health, "name")
        f.name:SetShown(placed)
        clampNameWidth(f)      -- the slot decides whether there is anything to clear
        f.title:Hide()
    end
end

-- Level plus a one-glyph rank so rare/elite reads at a glance:
-- + elite, R rare, R+ rare elite, B world boss. Coloured by relative difficulty,
-- with gold for anything above normal rank.
local CLASS_TAGS = {
    elite     = "+",
    rare      = "R",
    rareelite = "R+",
    worldboss = "B",
}

local function paintLevel(f, unit)
    local fs = f.level
    if not fs then return end
    local d = db()
    if not d.showLevel then fs:Hide(); return end
    -- no unit = the options preview; show a representative elite sample
    local lvl  = unit and (UnitLevel(unit) or 0) or 70
    local rank = unit and (UnitClassification and UnitClassification(unit) or "normal")
        or "elite"
    local tag  = d.showLevelMod and CLASS_TAGS[rank] or nil
    local txt  = (lvl and lvl > 0) and tostring(lvl) or "??"
    if tag then txt = txt .. tag end
    fs:SetText(txt)
    local r, g, b = 0.85, 0.85, 0.85
    if lvl and lvl > 0 and GetCreatureDifficultyColor then
        local ok, col = pcall(GetCreatureDifficultyColor, lvl)
        if ok and col and col.r then r, g, b = col.r, col.g, col.b end
    elseif lvl == -1 then
        r, g, b = 1, 0.2, 0.2
    end
    if tag then r, g, b = 1, 0.82, 0.25 end
    fs:SetTextColor(r, g, b)
    fs:Show()
end

local function applyNameColor(f, d, unit, enemy, isPlayer)
    if enemy then f.name:SetTextColor(1, 1, 1); return end
    if isPlayer and d.classColorFriendly then
        local _, class = UnitClass(unit)
        local r, g, b = classColor(class)
        if r then f.name:SetTextColor(r, g, b); return end
    end
    local c = isPlayer and d.friendlyNameColor or d.friendlyNPCColor
    f.name:SetTextColor(c.r, c.g, c.b)
end

local function positionRaidIcon(f)
    local d = db()
    local ic = f.raidIcon
    ic:SetSize(d.raidMarkerSize, d.raidMarkerSize)
    local anchor = (f._mode == "nameonly") and f.name or f.health
    ic:ClearAllPoints()
    local pos, ox, oy = d.raidMarkerPos, d.raidMarkerX or 0, d.raidMarkerY or 0
    if pos == "left" then
        -- Both the marker and the level text sit left of the name in name-only
        -- mode; queue the marker outside the level so they don't stack up.
        if anchor == f.name and f.level and f.level:IsShown() then anchor = f.level end
        ic:SetPoint("RIGHT", anchor, "LEFT", -4 + ox, oy)
    elseif pos == "right" then
        ic:SetPoint("LEFT", anchor, "RIGHT", 4 + ox, oy)
    else
        ic:SetPoint("BOTTOM", anchor, "TOP", ox, 4 + oy)
    end
end

local function setRaidIcon(ic, idx)
    if SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(ic, idx)
    else
        ic:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. idx)
    end
end

local function updateRaidIcon(f)
    local d = db()
    local ic = f.raidIcon
    if not d.showRaidMarker or f._mode == "hidden" or not f.unit then ic:Hide(); return end
    local idx = GetRaidTargetIndex(f.unit)
    if not idx then ic:Hide(); return end
    setRaidIcon(ic, idx)
    positionRaidIcon(f)
    ic:Show()
end

local MAX_CP = MAX_COMBO_POINTS or 5

local function makePip(g)
    local p = g:CreateTexture(nil, "OVERLAY")
    p:SetColorTexture(1, 1, 1, 1)
    return p
end

local PIP_TEX = {
    circle   = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\pip_circle.tga",
    diamond  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\pip_diamond.tga",
    triangle = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\pip_triangle.tga",
}

local function renderComboPips(f, count)
    local d = db()
    local g = f.cpGroup
    if not d.showClassPower or count <= 0 or (f._mode and f._mode ~= "full") then
        for _, p in ipairs(g.pips) do p:Hide() end
        g:Hide(); return
    end
    for i = #g.pips + 1, MAX_CP do g.pips[i] = makePip(g) end
    local size, sp = d.cpSize, d.cpSpacing
    local ox, oy = d.cpOffsetX or 0, d.cpOffsetY or 0
    g:ClearAllPoints()
    if d.cpPos == "above" then
        g:SetPoint("BOTTOM", f.health, "TOP", ox, 3 + oy)
    else
        local anchor = (d.showCastbar and f.cast) or f.health
        g:SetPoint("TOP", anchor, "BOTTOM", ox, -3 + oy)
    end
    g:Show()
    local c = d.cpColor
    local tex = PIP_TEX[d.cpShape]
    for i = 1, MAX_CP do
        local p = g.pips[i]
        p:SetSize(size, size)
        p:ClearAllPoints()
        p:SetPoint("CENTER", g, "CENTER", (i - (MAX_CP + 1) / 2) * (size + sp), 0)
        if tex then
            p:SetTexture(tex)
            if i <= count then p:SetVertexColor(c.r, c.g, c.b, 1)
            else p:SetVertexColor(0.25, 0.25, 0.25, 0.6) end
        else
            if i <= count then p:SetColorTexture(c.r, c.g, c.b, 1)
            else p:SetColorTexture(0.25, 0.25, 0.25, 0.6) end
        end
        p:Show()
    end
    for i = MAX_CP + 1, #g.pips do g.pips[i]:Hide() end
end

local function getComboPoints()
    if not GetComboPoints then return 0 end
    local ok, cp = pcall(GetComboPoints, "player", "target")
    return (ok and cp) or 0
end

local function updateAllComboPips()
    local cp = getComboPoints()
    for _, f in pairs(ns.plates) do
        renderComboPips(f, (f.unit and UnitIsUnit(f.unit, "target")) and cp or 0)
    end
end

local function refreshPlate(f)
    local unit = f.unit
    if not unit then return end
    f._ctxMode = nil
    local d = db()
    local isPlayer = UnitIsPlayer(unit)
    local enemy    = UnitCanAttack("player", unit) and true or false
    local mode     = plateModeFor(d, enemy, isPlayer)
    applyPlateMode(f, mode)
    -- before updateRaidIcon: the marker queues outside the level text when both
    -- sit left of the name, so its visibility has to be settled first
    if mode ~= "hidden" then paintLevel(f, unit) end
    updateRaidIcon(f)
    if mode == "hidden" then return end

    f.name:SetText(UnitName(unit) or "")
    clampNameWidth(f)
    applyNameColor(f, d, unit, enemy, isPlayer)

    if mode == "nameonly" and not enemy and not isPlayer and d.showNPCTitle and f._npcTitle then
        f.title:SetText(f._npcTitle); f.title:Show()
    else
        f.title:Hide()
    end
    if mode ~= "full" then return end

    local _, class = UnitClass(unit)
    local isTarget = UnitIsUnit(unit, "target")
    -- Kept on the frame and refilled rather than built fresh: this runs for every
    -- plate on every health change, and the health-only path below reuses it.
    local ctx = f._ctx
    if not ctx then ctx = {}; f._ctx = ctx end
    ctx.player   = isPlayer
    ctx.enemy    = enemy
    ctx.class    = class
    ctx.isTarget = isTarget
    ctx.reaction = UnitReaction(unit, "player")
    ctx.tapped   = UnitIsTapDenied(unit) and true or false
    ctx.threat   = UnitAffectingCombat("player") and UnitThreatSituation("player", unit) or nil
    -- Read once here, with everything else about the unit, rather than inside
    -- the colour function: that one runs again on the health-only path, where
    -- the unit is not at hand.
    ctx.inCombat = UnitAffectingCombat(unit) and true or false
    f._ctxMode   = "full"

    local hp, hpmax = UnitHealth(unit) or 0, UnitHealthMax(unit) or 1
    paintHealth(f, ctx, hp, hpmax)
    paintAbsorb(f, hp, hpmax, (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0)
    paintTarget(f, isTarget)
    paintExec(f, isTarget)
    paintFocus(f, UnitIsUnit(unit, "focus"))
end

-- UNIT_HEALTH is the most frequent unit event there is in a raid, and none of
-- what it changes needs the plate mode re-decided, the name re-set, the level
-- and raid marker re-anchored or the colour context re-derived - only the bar.
-- Sending it through the full refresh cost about 25 API calls and a fresh table
-- for every point of damage anyone in range took. Anything that does change the
-- context (threat, target, faction, aura) still goes the full way.
local function refreshPlateHealth(f)
    if f._ctxMode ~= "full" or not f._ctx then return refreshPlate(f) end
    local unit = f.unit
    if not unit then return end
    local hp, hpmax = UnitHealth(unit) or 0, UnitHealthMax(unit) or 1
    paintHealth(f, f._ctx, hp, hpmax)
    paintAbsorb(f, hp, hpmax, (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0)
end

local function restyleAllPlates()
    for _, f in pairs(ns.plates) do
        applyPlateScale(f)
        layoutPlate(f); skinPlate(f); refreshPlate(f); plateUpdateAuras(f)
        -- Re-skinning swaps the cast bar's texture object; only plateCastStart
        -- re-anchors the edge glow to it, so an in-flight cast must be re-armed.
        if f._casting then plateCastStart(f) end
    end
end

local function updateFades()
    local haveTarget = UnitExists("target")
    for _, f in pairs(ns.plates) do
        applyPlateAlpha(f, haveTarget)
        paintTarget(f, f.unit and UnitIsUnit(f.unit, "target"))
    end
end

local onPlateRemoved   -- forward decl (onPlateAdded releases a stale frame via it)

local function acquirePlate()
    local f = table.remove(platePool)
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(150, 40)
    buildVisuals(f)
    f:SetScript("OnEvent", function(self, event)
        if not self.unit then return end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
            or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
            refreshPlateHealth(self)
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            plateCastStart(self)
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            plateCastFlash(self)
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
            or event == "UNIT_SPELLCAST_FAILED" then
            plateCastStop(self)
        elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_FACTION" then
            refreshPlate(self)
        elseif event == "UNIT_THREAT_LIST_UPDATE" then
            refreshPlate(self)
        elseif event == "UNIT_AURA" then
            plateUpdateAuras(self)
        end
    end)
    return f
end

local function onPlateAdded(_, unit)
    if not unit or UnitIsUnit(unit, "player") then return end
    local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return end

    -- Guard a double-add: release the stale frame so exactly one plate owns a unit.
    if ns.plates[unit] then onPlateRemoved(nil, unit) end

    local f = acquirePlate()
    f.unit = unit
    f._npcTitle = getNPCTitle(unit)   -- scanned once; NPC subnames don't change
    ns.plates[unit] = f
    f:SetParent(nameplate)
    f:ClearAllPoints()
    f:SetPoint("CENTER", nameplate, "CENTER", 0, 0)
    f:SetFrameLevel(nameplate:GetFrameLevel() + 2)
    -- scale FIRST: layoutPlate pixel-snaps against the frame's effective
    -- scale, so sizing before the calibration lands off the physical grid
    applyPlateScale(f)
    layoutPlate(f); skinPlate(f)
    f:Show()

    hideBlizzard(nameplate)

    f._hShow = nil   -- reused frame: snap the smooth-health value to the new unit
    f._ctxMode = nil -- and force the next refresh to rebuild the colour context

    f:RegisterUnitEvent("UNIT_HEALTH", unit)
    f:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
    -- Absorbs and the threat list do not exist on every flavour we ship to, and
    -- registering an unknown event throws. This runs for every plate that
    -- appears, so an unguarded call would break nameplates outright rather than
    -- just dropping one feature. The absorb value itself is already guarded
    -- where it is read; only the registration was not.
    pcall(f.RegisterUnitEvent, f, "UNIT_ABSORB_AMOUNT_CHANGED", unit)
    f:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    f:RegisterUnitEvent("UNIT_FACTION", unit)
    pcall(f.RegisterUnitEvent, f, "UNIT_THREAT_LIST_UPDATE", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
    f:RegisterUnitEvent("UNIT_AURA", unit)

    -- refreshPlate first: it establishes _mode, which plateCastStart needs in
    -- order to paint a unit that is already casting when it comes into range.
    refreshPlate(f)
    plateCastStart(f)
    plateUpdateAuras(f)
    updateFades()
    updateAllComboPips()
end

function onPlateRemoved(_, unit)
    local f = unit and ns.plates[unit]
    if not f then return end
    ns.plates[unit] = nil
    f:UnregisterAllEvents()
    plateCastStop(f)
    hideGroup(f.debuffGroup); hideGroup(f.dotGroup); hideGroup(f.buffGroup); hideGroup(f.ccGroup)
    f.raidIcon:Hide()
    f.absorb:Hide()
    f.title:Hide()
    paintFocus(f, false)
    renderComboPips(f, 0)
    f.unit = nil
    f._npcTitle = nil
    -- A pooled frame must not carry its old plate mode: the next unit may start
    -- mid-cast, and plateCastStart bails on a stale non-full mode.
    f._mode = nil
    f:Hide()
    f:SetParent(UIParent)
    f:ClearAllPoints()
    table.insert(platePool, f)
end

local function onTargetChanged()
    updateFades()
    updateAllComboPips()
    local d = db()
    for unit, f in pairs(ns.plates) do
        if f._mode == "full" then
            if d.targetBarColor then
                refreshPlate(f)
            else
                local isT = UnitIsUnit(unit, "target")
                paintTarget(f, isT)
                paintExec(f, isT)
            end
        end
    end
end

local hoverTicker
local function updateHoverTicker()
    local on = mod.db and mod.db.hoverHighlight
    if on then
        if not hoverTicker then
            hoverTicker = CreateFrame("Frame")
            hoverTicker._acc = 0
            hoverTicker:SetScript("OnUpdate", function(self, e)
                self._acc = self._acc + e
                if self._acc < 0.15 then return end
                self._acc = 0
                for unit, f in pairs(ns.plates) do
                    if f.hover then
                        f.hover:SetShown(f._mode == "full" and UnitIsUnit(unit, "mouseover"))
                    end
                end
            end)
        end
        hoverTicker:Show()
    elseif hoverTicker then
        hoverTicker:Hide()
        for _, f in pairs(ns.plates) do if f.hover then f.hover:Hide() end end
    end
end

local function onRaidTargetUpdate()
    for _, f in pairs(ns.plates) do updateRaidIcon(f) end
end

local function updateAllFocus()
    for _, f in pairs(ns.plates) do
        local on = f.unit and (f._mode == nil or f._mode == "full") and UnitIsUnit(f.unit, "focus")
        paintFocus(f, on)
    end
end

-- No combo-point event on 2.5.x; combo changes ride UNIT_POWER_UPDATE for the player.
local function onComboUpdate(_, unit)
    if unit ~= "player" then return end
    updateAllComboPips()
end

local previewFrame

local PREVIEW_CTX = {
    player = false, enemy = true, class = "WARRIOR",
    reaction = 2, tapped = false, threat = 0,
}

local function stickPreview()
    local f = ns.UI and ns.UI.mainFrame
    if not (previewFrame and previewFrame:IsShown() and f and f.scroll) then return end
    -- As a pinned page header the preview no longer scrolls with the page;
    -- the follow re-anchor would drag it out of its host.
    if previewFrame._pinned then return end
    local host = previewFrame
    if not host._natY then
        local _, _, _, _, py = host:GetPoint(1)
        host._natY = py and -py or 10
    end
    local off = f.scroll:GetVerticalScroll() or 0
    local d = math.max(host._natY, off + 8)
    host:ClearAllPoints()
    host:SetPoint("TOP", host:GetParent(), "TOP", 0, -d)
end

local function stickPreviewSoon()
    ns.NextFrame(stickPreview)
end

local function buildPreview(parent)
    if previewFrame then
        previewFrame:SetParent(parent)
        previewFrame:SetFrameLevel((parent:GetFrameLevel() or 1) + 100)   -- SetParent resets it
        previewFrame:ClearAllPoints()
        previewFrame:SetPoint("TOP", parent, "TOP", 0, -10)
        previewFrame._natY = nil
        previewFrame:Show()
        previewFrame:Update()
        stickPreviewSoon()
        return previewFrame
    end

    local host = CreateFrame("Frame", "VCUINameplatePreview", parent)
    -- 170, not the old 210: the mock needs ~150px (aura stack, plate, cast
    -- bar, pips) and the rest was dead air (user feedback, 31.07.2026)
    host:SetSize(420, 170)
    -- Must sit above every page widget while pinned over the scrolled content.
    host:SetFrameLevel((parent:GetFrameLevel() or 1) + 100)
    local mf = ns.UI and ns.UI.mainFrame
    if mf and mf.scroll and not mf.scroll._vcuiNPStick then
        mf.scroll._vcuiNPStick = true
        mf.scroll:HookScript("OnVerticalScroll", stickPreview)
    end
    local bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(host)
    bg:SetColorTexture(0.05, 0.05, 0.065, 1)
    for _, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = host:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.15, 0.15, 0.19, 1)
        if s == "TOP" or s == "BOTTOM" then t:SetPoint(s .. "LEFT"); t:SetPoint(s .. "RIGHT"); t:SetHeight(1)
        else t:SetPoint("TOP" .. s); t:SetPoint("BOTTOM" .. s); t:SetWidth(1) end
    end
    local caption = host:CreateFontString(nil, "OVERLAY")
    if ns.UI and ns.UI.Font then ns.UI.Font(caption, 11, "OUTLINE") end
    caption:SetPoint("TOP", host, "TOP", 0, -6)
    caption:SetText(L["Live preview"])
    caption:SetTextColor(0.62, 0.62, 0.70)

    local plate = CreateFrame("Frame", nil, host)
    plate:SetSize(160, 46)
    -- Only far enough below centre to clear the caption band at the top. The
    -- -28 this replaces was measured against the old 170-tall card; once that
    -- came down to 118 the same offset pushed the combo pips onto the card's
    -- bottom edge (user report, 02.08.2026).
    plate:SetPoint("CENTER", host, "CENTER", 0, -8)
    buildVisuals(plate)
    plate.unit = nil
    plate.cast:Show()

    local function scanAndScroll(title)
        local UIW = ns.UI
        local f = UIW and UIW.mainFrame
        local sc, sf = f and f.scrollChild, f and f.scroll
        if not (sc and sf) then return false end
        local wanted = string.upper(title)
        for _, child in ipairs({ sc:GetChildren() }) do
            if child._vcType == "collapsible" then
                for _, r in ipairs({ child:GetRegions() }) do
                    if r.GetText and r:GetText() == wanted then
                        local top, scTop = child:GetTop(), sc:GetTop()
                        if top and scTop then
                            local off = scTop - top - 4
                            local max = (sc:GetHeight() or 0) - (sf:GetHeight() or 0)
                            if max < 0 then max = 0 end
                            if off < 0 then off = 0 elseif off > max then off = max end
                            sf:SetVerticalScroll(off)
                        end
                        return true
                    end
                end
            end
        end
        return false
    end

    local function jumpToSection(title)
        local UIW = ns.UI
        if not (UIW and UIW.mainFrame and UIW._currentBuildKey and UIW.BuildOptionsPage) then return end
        -- Sections no longer fold, so on the right tab this is a pure scroll.
        if scanAndScroll(title) then return end
        -- Every preview zone targets a display-tab section; clicked from the
        -- colour or general tab the heading is not on this page. Switch over,
        -- then scroll once the rebuild has laid the sections out.
        if UIW.currentTab ~= "display" then
            UIW:BuildOptionsPage(UIW._currentBuildKey, "display")
            ns.NextFrame(function()
                if not scanAndScroll(title) then
                    ns:Debug("preview zone: no section titled %q", tostring(title))
                end
            end)
            return
        end
        -- Already on the display tab and the heading is not there: the zone
        -- points at a section that no longer exists. Says so instead of eating
        -- the click -- three zones did exactly that for a day.
        ns:Debug("preview zone: no section titled %q", tostring(title))
    end

    local function makeZone(title, level)
        local z = CreateFrame("Button", nil, plate)
        z:SetFrameLevel(plate:GetFrameLevel() + (level or 20))
        local hl = z:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(z)
        hl:SetColorTexture(1, 1, 1, 0.08)
        z:SetScript("OnClick", function() jumpToSection(title) end)
        ns.UI:AttachTooltip(z, {
            title = title,
            lines = { { L["Click: open these settings"], 0.7, 0.7, 0.75 } },
        })
        return z
    end
    local function clickZone(region, title, level)
        if not region then return end
        makeZone(title, level):SetAllPoints(region)
    end
    -- These titles are looked up by TEXT against the sections the page actually
    -- built. Rename or remove a section and every zone pointing at it stops
    -- doing anything, silently -- which is exactly what happened when the page
    -- was reorganised on 02.08.2026 (user report: clicking the cast bar and the
    -- combo points did nothing). Any section renamed here has to be renamed
    -- there in the same commit.
    clickZone(plate.health,   L["Health and cast bar"], 25)
    clickZone(plate.cast,     L["Health and cast bar"], 25)
    clickZone(plate.name,     L["Main text positions"], 25)
    clickZone(plate.raidIcon, L["Extra indicators"],    25)
    local fitted = {}
    local function fittedZone(g, key, title, level)
        if not g then return end
        local z = makeZone(title, level)
        z:Hide()
        fitted[#fitted + 1] = { zone = z, group = g, key = key }
    end
    -- The aura rows are placed from the slot section now, so that is where a
    -- click on one of them belongs.
    fittedZone(plate.debuffGroup, "icons", L["Main positions"],     20)
    fittedZone(plate.dotGroup,    "icons", L["Your Own Debuffs"],   20)
    fittedZone(plate.buffGroup,   "icons", L["Main positions"],     20)
    fittedZone(plate.ccGroup,     "icons", L["Extra indicators"],   20)
    fittedZone(plate.cpGroup,     "pips",  L["Extra indicators"],   20)
    function plate:_FitZones()
        for _, e in ipairs(fitted) do
            local g, z = e.group, e.zone
            local first, last
            local list = g and g[e.key]
            if g and g:IsShown() and list then
                for _, ic in ipairs(list) do
                    if ic:IsShown() then first = first or ic; last = ic end
                end
            end
            if first then
                z:ClearAllPoints()
                z:SetPoint("TOPLEFT", first, "TOPLEFT", -2, 2)
                z:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 2, -2)
                z:Show()
            else
                z:Hide()
            end
        end
    end

    function plate:Update()
        -- Divide by the PARENT's effective scale, not our own (ours already
        -- includes SetScale). Real plates render at plateBaseScale
        -- (applyPlateScale), so landing the preview at the same base shows
        -- exactly what a real plate renders -- including pixel-perfect mode.
        local pes = plateBaseScale(db())
        local parentES = self:GetParent():GetEffectiveScale()
        if parentES > 0 then self:SetScale(pes / parentES) end
        layoutPlate(self); skinPlate(self)
        local d = db()
        local enemy = PREVIEW_CTX.enemy
        local mode = enemy and "full" or d.friendlyPlayers
        applyPlateMode(self, mode)

        if enemy then
            self.name:SetText(L["Target Dummy"]); self.name:SetTextColor(1, 1, 1)
        else
            self.name:SetText(L["Friendly Name"])
            local c = d.friendlyNameColor; self.name:SetTextColor(c.r, c.g, c.b)
        end
        if mode == "nameonly" and not enemy and d.showNPCTitle then
            self.title:SetText(L["<Innkeeper>"]); self.title:Show()
        else
            self.title:Hide()
        end

        -- mirrors refreshPlate: level first, the marker queues outside it
        if mode ~= "hidden" then paintLevel(self) else self.level:Hide() end
        if d.showRaidMarker and mode ~= "hidden" then
            setRaidIcon(self.raidIcon, 8)
            positionRaidIcon(self)
            self.raidIcon:Show()
        else
            self.raidIcon:Hide()
        end
        if mode ~= "full" then return end

        paintHealth(self, PREVIEW_CTX, 68, 100)
        paintAbsorb(self, 68, 100, 20)
        if d.showCastbar then
            self.cast:SetMinMaxValues(0, 1); self.cast:SetValue(0.6)
            paintCast(self, L["Fireball"], "Interface\\Icons\\Spell_Fire_FlameBolt", false)
            self.cast:Show()
        else
            self.cast:Hide()
        end
        paintTarget(self, true)
        paintFocus(self, true)

        local now = GetTime()
        -- schools + a nearly-expired aura so the school border and the expiry
        -- pulse both have something to show in the preview
        local dl = {
            { icon = "Interface\\Icons\\Spell_Fire_Immolation",       count = 0, duration = 12, expiration = now + 8,
              dispelType = "Magic" },
            { icon = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", count = 3, duration = 18, expiration = now + 2,
              dispelType = "Curse" },
        }
        local bl = {
            { icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",  count = 0, duration = 30, expiration = now + 22, dispel = true },
        }
        local cl = {
            { icon = "Interface\\Icons\\Spell_Nature_Polymorph",      count = 0, duration = 10, expiration = now + 7,
              dispelType = "Magic" },
        }
        local dotl = {
            { icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", count = 0, duration = 24, expiration = now + 19 },
            { icon = "Interface\\Icons\\Spell_Shadow_AbominationExplosion", count = 0, duration = 18, expiration = now + 4 },
        }
        applyAuras(self, {
            debuff = d.showDebuffs and dl   or nil,
            dot    = d.showDots   and dotl or nil,
            buff   = d.showBuffs  and bl   or nil,
            cc     = d.showCC     and cl   or nil,
        })

        renderComboPips(self, 3)
    end

    local baseUpdate = plate.Update
    function plate:Update()
        baseUpdate(self)
        -- The card is sized for the factor-1 mock. Pixel-perfect mode on a
        -- small window renders the mock LARGER than the options space -- grow
        -- the card with it, and clip as the last line of defence, so the
        -- preview can never paint over the option rows around it.
        local pf = plateBaseScale(db()) / (UIParent:GetEffectiveScale() or 1)
        -- 170 was sized for the tallest thing the mock can be -- a plate with
        -- every aura row filled. With the usual two rows it left a hand's width
        -- of empty card above and below (user report, 02.08.2026). 118 still
        -- clears the raid marker above the bar and the combo pips below it; the
        -- pixel-perfect factor still grows it, and the clip below is what keeps
        -- an over-tall mock inside the card.
        host:SetHeight(math.floor(118 * math.max(1, pf) + 0.5))
        if self._FitZones then self:_FitZones() end
    end
    if host.SetClipsChildren then host:SetClipsChildren(true) end

    host.Update = function() plate:Update() end
    previewFrame = host
    host:SetPoint("TOP", parent, "TOP", 0, -10)
    host._natY = nil
    plate:Update()
    stickPreviewSoon()
    return host
end

local function refreshPage()
    if ns.UI and ns.UI.IsModuleActive and ns.UI:IsModuleActive("nameplates") then
        ns.UI:BuildOptionsPage("nameplates", ns.UI.currentTab)
    end
end

-- Nameplate CVars are combat-locked.
local function applyFriendlyCVar()
    if InCombatLockdown and InCombatLockdown() then return end
    pcall(SetCVar, "nameplateShowFriends", db().friendlyShow and "1" or "0")
end

-- Measured on the live client (/dump, 01.08.2026): the plate HOST ran at
-- 1.16x UIParent for the target -- Blizzard's distance ramp and
-- selected-target scaling ride ON TOP of our scale chain, which distorts the
-- pixel calibration and double-scales the target on top of our own
-- "target scale" option. Pin the three responsible CVars to 1 (exactly what
-- the reference calibration assumes); our globalScale/targetScale/castEmphasis
-- options are then the ONE scale chain. Writes only when a value differs --
-- this also runs at every combat end for the retry, and must not dirty the
-- config on each one.
local function applyScaleCVars()
    if InCombatLockdown and InCombatLockdown() then return end
    if not (GetCVar and SetCVar) then return end
    for _, name in ipairs({ "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale" }) do
        local ok, cur = pcall(GetCVar, name)
        if ok and cur ~= nil and tonumber(cur) ~= 1 then
            pcall(SetCVar, name, 1)
        end
    end
end

local function applyAndRefresh()
    if mod.active then restyleAllPlates(); updateFades(); updateAllComboPips() end
    if previewFrame then previewFrame:Update() end
end

-- The clickable area, as a PERCENTAGE.
--
-- MEASURED, not assumed. There is no getter for the default hitbox --
-- C_NamePlate.GetNamePlateEnemySize does not exist on this client -- but the
-- base nameplate frame IS that area, so its own size answers the question:
--
--     /run local p=C_NamePlate.GetNamePlateForUnit("target")
--          if p then print(p:GetSize()) end   --> 152.0001  54.99999
--
-- Read while both sliders sat at 100, i.e. while the setter had never been
-- called, so that size is the client's own. The first guess here was 128x32 and
-- the height was off by nearly three quarters.
--
-- 100 still computes nothing: it means "do not call the setter at all", which
-- leaves the client's size untouched no matter what these numbers say.
local HITBOX_BASE_W, HITBOX_BASE_H = 152, 55

local function applyHitbox()
    if InCombatLockdown() then return end
    if not (C_NamePlate and C_NamePlate.SetNamePlateEnemySize) then return end
    local pw = mod.db.hitboxPctW or 100
    local ph = mod.db.hitboxPctH or 100
    -- No calibration factor here: the click box is sized in HOST units, and
    -- with the scale CVars pinned to 1 the host runs at UIParent's scale --
    -- the same units the normalized visuals land in.
    if pw == 100 and ph == 100 then return end
    pcall(C_NamePlate.SetNamePlateEnemySize,
        math.floor(HITBOX_BASE_W * pw / 100 + 0.5),
        math.floor(HITBOX_BASE_H * ph / 100 + 0.5))
end

-- One-time per profile: the two settings used to be absolute pixels, with 0
-- meaning "leave it alone". Same shape as migrateAuraRows -- flag written only
-- after the work, and the old keys removed rather than left looking like
-- settings without a control.
local function migrateHitbox()
    local d = db()
    if not d or d.hitboxPctMigrated then return end
    if (d.hitboxW or 0) > 0 then
        d.hitboxPctW = math.floor(d.hitboxW / HITBOX_BASE_W * 100 + 0.5)
        d.hitboxPctH = ((d.hitboxH or 0) > 0)
            and math.floor(d.hitboxH / HITBOX_BASE_H * 100 + 0.5) or 100
    end
    d.hitboxPctMigrated = true
    d.hitboxW, d.hitboxH = nil, nil
end

function mod:OnEnable()
    if mod.db.healthTexture == nil then mod.db.healthTexture = DEFAULT_TEXTURE end
    migrateAuraRows()
    migrateHitbox()
    local _, cls = UnitClass("player")
    playerCanSteal = CAN_REMOVE_MAGIC[cls] or false
    findKickSpell()
    mod:RegisterEvent("SPELLS_CHANGED", findKickSpell)
    applyHitbox()
    updateHoverTicker()
    ensureOffParent()
    -- Mirror Blizzard's current setting; only write the CVar when the user flips the option.
    local cur = GetCVar and GetCVar("nameplateShowFriends")
    if cur ~= nil then mod.db.friendlyShow = (cur == "1" or cur == 1) end
    mod:RegisterEvent("NAME_PLATE_UNIT_ADDED", onPlateAdded)
    mod:RegisterEvent("NAME_PLATE_UNIT_REMOVED", onPlateRemoved)
    -- The pixel calibration depends on resolution (and the preview also on
    -- UI scale); both can change mid-session and every shown plate keeps its
    -- scale until re-asked. applyAndRefresh (not restyleAllPlates) so the
    -- options preview follows.
    local function recalibrate()
        applyAndRefresh()
    end
    mod:RegisterEvent("UI_SCALE_CHANGED", recalibrate)
    mod:RegisterEvent("DISPLAY_SIZE_CHANGED", recalibrate)
    applyScaleCVars()
    -- combat-locked at enable time (combat /reload): retry when combat ends;
    -- no-ops once the values sit at 1
    mod:RegisterEvent("PLAYER_REGEN_ENABLED", applyScaleCVars)
    mod:RegisterEvent("PLAYER_TARGET_CHANGED", onTargetChanged)
    mod:RegisterEvent("PLAYER_FOCUS_CHANGED", updateAllFocus)
    mod:RegisterEvent("RAID_TARGET_UPDATE", onRaidTargetUpdate)
    mod:RegisterEvent("UNIT_POWER_UPDATE", onComboUpdate)
    mod:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCombatLogEvent)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, p in ipairs(C_NamePlate.GetNamePlates()) do
            local u = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
            if u then onPlateAdded(nil, u) end
        end
    end
end

function mod:OnDisable()
    if hoverTicker then hoverTicker:Hide() end
    for unit in pairs(ns.plates) do onPlateRemoved(nil, unit) end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, p in ipairs(C_NamePlate.GetNamePlates()) do
            if p.UnitFrame then p.UnitFrame:SetAlpha(1); p.UnitFrame:Show() end
        end
    end
end

-- The options page lives in Modules/NameplatesOptions.lua. Measured before the
-- split: it reaches back for exactly these ten names out of the 153 this file
-- declares, and nothing travels the other way. Keeping the list in one table is
-- what makes that still checkable a year from now.
--
-- updatePreview is a function and not the frame itself: previewFrame stays nil
-- until the options page is built for the first time, so a copy taken at load
-- would be nil forever.
mod.optionsBridge = {
    textureValues       = textureValues,
    borderTextureValues = borderTextureValues,
    buildPreview        = buildPreview,
    previewCtx          = PREVIEW_CTX,
    updatePreview       = function() if previewFrame then previewFrame:Update() end end,
    refreshPage         = refreshPage,
    applyAndRefresh     = applyAndRefresh,
    applyFriendlyCVar   = applyFriendlyCVar,
    applyHitbox         = applyHitbox,
    updateHoverTicker   = updateHoverTicker,
}
