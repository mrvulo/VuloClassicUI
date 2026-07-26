-- VuloClassicUI / Modules / Nameplates
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("nameplates", {
    name        = "Nameplates",
    group       = "Unit Frames",
    description = "Custom enemy & NPC nameplates with a live preview: health bar, cast bar, name and health text, reaction / class colours, target highlight and threat colouring.",
    defaults = {
        enabled = true,

        healthWidth   = 120,
        healthHeight  = 10,
        healthTexture = "Atrocity",
        bgAlpha       = 0.85,
        borderSize    = 1,
        borderStyle   = "lines",
        borderTexture = "Blizzard Tooltip",
        borderColor   = { r = 0.067, g = 0.067, b = 0.067 },
        showSpark     = true,
        sparkWidth    = 10,
        roundedBars   = false,

        showAbsorb  = true,
        colAbsorb   = { r = 0.70, g = 0.85, b = 1.00 },
        absorbAlpha = 0.55,

        execLine       = false,
        execPct        = 20,
        colExec        = { r = 1.00, g = 0.35, b = 0.35 },
        execTargetOnly = true,

        targetBarColor = false,
        colTargetBar   = { r = 0.75, g = 0.55, b = 1.00 },
        hoverHighlight = false,
        targetScale    = 100,

        hitboxW = 0,
        hitboxH = 0,

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

        showCastbar   = true,
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
        kickColorOn          = false,
        colCastKickCd        = { r = 0.35, g = 0.35, b = 0.60 },
        castOffsetX          = 0,
        castOffsetY          = 0,
        castWidth            = 0,
        castBgAlpha          = 0,
        castBgColor          = { r = 0.05, g = 0.05, b = 0.06 },
        castIconScale        = 100,
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
        healthTextOffsetX = 0,
        healthTextOffsetY = 0,
        auraOffsetX       = 0,
        auraOffsetY       = 0,

        targetHighlight = true,
        colTarget       = { r = 1, g = 1, b = 1 },
        nonTargetAlpha  = 1.0,

        focusHighlight  = true,
        colFocus        = { r = 0.20, g = 0.60, b = 1.00 },

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
        auraSpacing    = 2,
        auraSwipe      = true,
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
    if d.targetBarColor and ctx.isTarget then
        local c = d.colTargetBar
        return c.r, c.g, c.b
    end
    if d.threatEnabled and ctx.threat ~= nil then
        local c = threatColor(d, ctx.threat)
        if c then return c.r, c.g, c.b end
    end
    return reactionColor(d, ctx)
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

local function makeEdges(parent, layer)
    local e = {}
    for _, side in ipairs({ "top", "bot", "lft", "rgt" }) do
        local t = parent:CreateTexture(nil, layer or "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        e[side] = t
    end
    return e
end

-- Border of n physical pixels around anchor, offset pad outward; n <= 0 hides it.
local function layoutEdges(edges, anchor, n, r, g, b, a, pad)
    if not edges then return end
    if n <= 0 then for _, t in pairs(edges) do t:Hide() end; return end
    local th  = ns:Pixel(anchor, n)
    local off = ns:Pixel(anchor, pad or 0)
    local top, bot, lft, rgt = edges.top, edges.bot, edges.lft, edges.rgt
    for _, t in pairs(edges) do t:SetColorTexture(r, g, b, a or 1); t:Show() end
    top:ClearAllPoints(); top:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -th - off, off); top:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", th + off, off); top:SetHeight(th)
    bot:ClearAllPoints(); bot:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -th - off, -off); bot:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", th + off, -off); bot:SetHeight(th)
    lft:ClearAllPoints(); lft:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -off, off); lft:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", -off, -off); lft:SetWidth(th)
    rgt:ClearAllPoints(); rgt:SetPoint("TOPLEFT", anchor, "TOPRIGHT", off, off); rgt:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", off, -off); rgt:SetWidth(th)
end

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
    f.absorb = f.health:CreateTexture(nil, "ARTWORK", nil, 2)
    f.absorb:Hide()
    f.execLine = f.health:CreateTexture(nil, "ARTWORK", nil, 3)
    f.execLine:Hide()
    f.cutaway = f.health:CreateTexture(nil, "ARTWORK", nil, 1)
    f.cutaway:SetColorTexture(1, 1, 1, 0.45)
    f.cutaway:Hide()
    f.hover = f.health:CreateTexture(nil, "ARTWORK", nil, 4)
    f.hover:SetAllPoints(f.health)
    f.hover:SetColorTexture(1, 1, 1, 0.12)
    f.hover:Hide()
    -- Glow riding the fill edge; tinted with the bar colour in paintHealth.
    f.spark = f.health:CreateTexture(nil, "ARTWORK", nil, 5)
    f.spark:SetTexture(SPARK_TEX)
    f.spark:SetBlendMode("ADD")
    f.spark:Hide()

    -- Name parents to the plate root, not the health bar, so name-only mode can hide the bar.
    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetPoint("BOTTOM", f.health, "TOP", 0, 3)
    f.level = f:CreateFontString(nil, "OVERLAY")
    f.level:SetPoint("RIGHT", f.name, "LEFT", -3, 0)
    f.level:Hide()
    f.title = f:CreateFontString(nil, "OVERLAY")
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

-- Varargs, not a list: GetStatusBarTexture() can return nil, and a nil hole
-- would stop ipairs early and strand masks on the later textures.
local function applyBarRounding(bar, on, ...)
    if not bar then return end
    local mask
    if on and bar.CreateMaskTexture then
        if not bar._vcMask then
            bar._vcMask = bar:CreateMaskTexture()
            bar._vcMask:SetTexture(MASK_ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            bar._vcMask:SetAllPoints(bar)
        end
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
    applyBarBorder(f.cast,   f.castBorder,   f.castBD,   d)
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

    f.healthText:ClearAllPoints()
    f.healthText:SetPoint("CENTER", f.health, "CENTER",
        d.healthTextOffsetX or 0, d.healthTextOffsetY or 0)

    f.castIcon:ClearAllPoints()
    if d.castIconRight then
        f.castIcon:SetPoint("LEFT", f.cast, "RIGHT", 2 + (d.castIconX or 0), d.castIconY or 0)
    else
        f.castIcon:SetPoint("RIGHT", f.cast, "LEFT", -2 + (d.castIconX or 0), d.castIconY or 0)
    end
    f.castIcon:SetSize(iconSz, iconSz)

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
        f.castTimer:ClearAllPoints()
        f.castText:ClearAllPoints()
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
        if f.level then plateFont(f.level, pick(d.levelSize, d.nameSize)) end
    end
    f.title:SetTextColor(0.72, 0.72, 0.78)
    f.name:SetShown(d.showName)
    f.healthText:SetShown(d.showHealthText)
    f.castIcon:SetShown(d.showCastbar and d.showCastIcon)
    f.castText:SetShown(d.showCastbar and d.showCastText)
    do
        local tc = d.castTextColor or { r = 1, g = 1, b = 1 }
        f.castText:SetTextColor(tc.r, tc.g, tc.b)
    end
    if f.castTimer then
        f.castTimer:SetShown(d.showCastbar and d.castTimer)
        local tc = d.castTimerColor or { r = 1, g = 1, b = 1 }
        f.castTimer:SetTextColor(tc.r, tc.g, tc.b)
    end
end

local function fmtShortNum(v)
    if v >= 1e6 then return format("%.1fm", v / 1e6)
    elseif v >= 1e4 then return format("%.1fk", v / 1e3) end
    return tostring(v)
end

local function healthTextString(d, cur, max)
    if d.healthTextMode == "none" or max <= 0 then return "" end
    local short = d.healthTextShort
    local pct = floor(cur / max * 100 + 0.5)
        .. (d.healthTextPercentSign ~= false and "%" or "")
    local curS = short and fmtShortNum(cur) or tostring(cur)
    if d.healthTextMode == "current" then
        return curS
    elseif d.healthTextMode == "currentmax" then
        return curS .. "/" .. (short and fmtShortNum(max) or tostring(max))
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
            f.healthBG:SetColorTexture(0.05, 0.05, 0.06, 0.85)
        end
    end
    paintSpark(f.health, f.spark, r, g, b, d.showSpark, d.sparkWidth, true, cur)
    if d.showHealthText then f.healthText:SetText(healthTextString(d, cur, max)) end
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
    local c = d.colAbsorb
    ab:SetColorTexture(c.r, c.g, c.b, d.absorbAlpha or 0.55)
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

-- One scale chain for every plate: global × target × casting. The preview keeps
-- its pixel-exact 1.0 scale, so real plates only (f.unit).
local function applyPlateScale(f, isTarget)
    if not f.unit then return end
    local d = db()
    local s = (d.globalScale or 100) / 100
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

local function paintTarget(f, isTarget)
    local d = db()
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

local function paintFocus(f, isFocus)
    local d = db()
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

local function paintCast(f, name, icon, notInterruptible)
    local d = db()
    local c = castColor(d, notInterruptible, f)
    f.cast:SetStatusBarColor(c.r, c.g, c.b)
    paintSpark(f.cast, f.castSpark, c.r, c.g, c.b, d.showSpark, d.sparkWidth)
    if d.showCastText then f.castText:SetText(name or "") end
    if d.showCastIcon then f.castIcon:SetTexture(icon) end
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
    local showTimer, showStacks, swipe = o.showTimer, o.showStacks, o.swipe
    local iw, ih = (o.w and o.w > 0) and o.w or size, (o.h and o.h > 0) and o.h or size
    local perRow = (o.perRow or 0) > 0 and o.perRow or n
    local grow   = o.grow or "center"
    local lines  = math.max(1, math.ceil(n / perRow))
    local bc = ns.COLORS.borderDark or { r = 0, g = 0, b = 0 }
    local bsz = d.borderSize or 0
    for i, ic in ipairs(g.icons) do
        local a = list[i]
        if a then
            local line = math.floor((i - 1) / perRow)          -- 0 = nearest the plate
            local col  = (i - 1) % perRow
            local inLine = math.min(perRow, n - line * perRow) -- last line can be short
            local dx
            if     grow == "right" then dx =  (col + 0.5) * (iw + spacing)
            elseif grow == "left"  then dx = -(col + 0.5) * (iw + spacing)
            else   dx = (col - (inLine - 1) / 2) * (iw + spacing) end
            -- extra lines stack away from the plate, whichever side the row is on
            local dy = line * (ih + spacing) * ((o.side == "bottom") and -1 or 1)
                     - (lines - 1) * (ih + spacing) / 2 * ((o.side == "bottom") and -1 or 1)
            ic:SetSize(iw, ih)
            ic:ClearAllPoints()
            ic:SetPoint("CENTER", g, "CENTER", dx, dy)
            ic.tex:SetTexture(a.icon)
            -- Border takes the dispel school's colour so you can read what is
            -- removable at a glance; plain dark border when there is no school.
            -- Thickness is never forced: border size 0 means the user wants none.
            local ec = (d.auraTypeBorder and dispelColor(a.dispelType)) or bc
            layoutEdges(ic.border, ic, bsz, ec.r, ec.g, ec.b, 1, 0)
            if d.showDispelGlow and a.dispel then
                local gc = d.colDispel
                layoutEdges(ic.dispelGlow, ic, 2, gc.r, gc.g, gc.b, 1, 1)
            else
                for _, t in pairs(ic.dispelGlow) do t:Hide() end
            end
            if swipe and a.duration > 0 and a.expiration > 0 then
                ic.cd:SetCooldown(a.expiration - a.duration, a.duration); ic.cd:Show()
            else
                ic.cd:Hide()
            end
            plateFont(ic.timer, d.auraTimerSize)
            plateFont(ic.count, d.auraStackSize)
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
    used.top    = (d.showName and (d.nameSize + 6) or 4) + (d.auraOffsetY or 0)
    used.bottom = castRoom - (d.auraOffsetY or 0)
    for _, row in ipairs(AURA_ROWS) do
        local group = f[row.group]
        local list  = lists[row.key]
        local cfg   = rowCfg(row.key)
        if group and d[row.show] and list and #list > 0 then
            local size = d[row.size] or 22
            local w = row.w and d[row.w] or nil
            local h = row.h and d[row.h] or nil
            local iw = (w and w > 0) and w or size
            local ih = (h and h > 0) and h or size
            local spacing = cfg.spacing or d.auraSpacing or 2
            local perRow  = (cfg.perRow or 0)
            local lines   = (perRow > 0) and math.ceil(#list / perRow) or 1
            local blockH  = lines * ih + (lines - 1) * spacing
            local side    = (cfg.side == "bottom") and "bottom" or "top"

            -- Left/right growth pins to the matching plate edge so the row lines
            -- up with the bar; centred growth stays on the bar's midline.
            local grow = cfg.grow or "center"
            local hp, gp = "CENTER", "CENTER"
            if     grow == "right" then hp, gp = "LEFT",  "LEFT"
            elseif grow == "left"  then hp, gp = "RIGHT", "RIGHT" end

            local dy = used[side] + blockH / 2 + (cfg.y or 0)
            group:ClearAllPoints()
            if side == "bottom" then
                group:SetPoint(gp, f.health, hp == "CENTER" and "BOTTOM"
                    or (hp == "LEFT" and "BOTTOMLEFT" or "BOTTOMRIGHT"),
                    (d.auraOffsetX or 0) + (cfg.x or 0), -dy)
            else
                group:SetPoint(gp, f.health, hp == "CENTER" and "TOP"
                    or (hp == "LEFT" and "TOPLEFT" or "TOPRIGHT"),
                    (d.auraOffsetX or 0) + (cfg.x or 0), dy)
            end
            -- every field set anew: the table is reused across rows
            _ro.size, _ro.w, _ro.h, _ro.spacing = size, w, h, spacing
            _ro.grow, _ro.perRow, _ro.side = grow, perRow, side
            _ro.showTimer, _ro.showStacks = d.showAuraTimer, d.showAuraStacks
            _ro.swipe = d.auraSwipe
            renderAuraGroup(group, list, _ro)
            used[side] = used[side] + blockH + spacing
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
    if d.hideNameWhileCasting and f._mode == "full" then f.name:SetShown(d.showName) end
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
        f.name:ClearAllPoints()
        f.name:SetPoint("BOTTOM", f.health, "TOP",
            d.nameOffsetX or 0, 3 + (d.nameOffsetY or 0))
        f.name:SetShown(d.showName)
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
    if C_Timer and C_Timer.After then C_Timer.After(0, stickPreview) else stickPreview() end
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
    host:SetSize(420, 210)
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
    plate:SetPoint("CENTER", host, "CENTER", 0, -38)
    buildVisuals(plate)
    plate.unit = nil
    plate.cast:Show()

    local function jumpToSection(title)
        local UIW = ns.UI
        local f = UIW and UIW.mainFrame
        if not (f and UIW._currentBuildKey and UIW.BuildOptionsPage) then return end
        local stateKey = UIW._currentBuildKey .. "/" .. (UIW.currentTab or "") .. "/" .. title
        UIW.sectionCollapsed[stateKey] = false
        UIW:BuildOptionsPage(UIW._currentBuildKey, UIW.currentTab)
        local sc, sf = f.scrollChild, f.scroll
        if not (sc and sf) then return end
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
                        return
                    end
                end
            end
        end
    end

    local function makeZone(title, level)
        local z = CreateFrame("Button", nil, plate)
        z:SetFrameLevel(plate:GetFrameLevel() + (level or 20))
        local hl = z:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(z)
        hl:SetColorTexture(1, 1, 1, 0.08)
        z:SetScript("OnClick", function() jumpToSection(title) end)
        z:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(title, 1, 1, 1)
                GameTooltip:AddLine(L["Click: open these settings"], 0.7, 0.7, 0.75)
                GameTooltip:Show()
            end
        end)
        z:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        return z
    end
    local function clickZone(region, title, level)
        if not region then return end
        makeZone(title, level):SetAllPoints(region)
    end
    clickZone(plate.health,   L["Health Bar"],  25)
    clickZone(plate.cast,     L["Cast Bar"],    25)
    clickZone(plate.name,     L["Text"],        25)
    clickZone(plate.raidIcon, L["Raid Marker"], 25)
    local fitted = {}
    local function fittedZone(g, key, title, level)
        if not g then return end
        local z = makeZone(title, level)
        z:Hide()
        fitted[#fitted + 1] = { zone = z, group = g, key = key }
    end
    fittedZone(plate.debuffGroup, "icons", L["Auras"],         20)
    fittedZone(plate.dotGroup,    "icons", L["Your Own Debuffs"], 20)
    fittedZone(plate.buffGroup,   "icons", L["Auras"],         20)
    fittedZone(plate.ccGroup,     "icons", L["Crowd Control"], 20)
    fittedZone(plate.cpGroup,     "pips",  L["Combo Points"],  20)
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
        -- Divide by the PARENT's effective scale, not our own (ours already includes SetScale).
        local pes = UIParent:GetEffectiveScale()
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
        if self._FitZones then self:_FitZones() end
    end

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

local function applyAndRefresh()
    if mod.active then restyleAllPlates(); updateFades(); updateAllComboPips() end
    if previewFrame then previewFrame:Update() end
end

local function applyHitbox()
    if InCombatLockdown() then return end
    local w, h = mod.db.hitboxW or 0, mod.db.hitboxH or 0
    if w > 0 and C_NamePlate and C_NamePlate.SetNamePlateEnemySize then
        pcall(C_NamePlate.SetNamePlateEnemySize, w, h > 0 and h or 32)
    end
end

function mod:OnEnable()
    if mod.db.healthTexture == nil then mod.db.healthTexture = DEFAULT_TEXTURE end
    migrateAuraRows()
    local _, cls = UnitClass("player")
    playerCanSteal = CAN_REMOVE_MAGIC[cls] or false
    findKickSpell()
    ns:RegisterEvent("SPELLS_CHANGED", findKickSpell)
    applyHitbox()
    updateHoverTicker()
    ensureOffParent()
    -- Mirror Blizzard's current setting; only write the CVar when the user flips the option.
    local cur = GetCVar and GetCVar("nameplateShowFriends")
    if cur ~= nil then mod.db.friendlyShow = (cur == "1" or cur == 1) end
    ns:RegisterEvent("NAME_PLATE_UNIT_ADDED", onPlateAdded)
    ns:RegisterEvent("NAME_PLATE_UNIT_REMOVED", onPlateRemoved)
    ns:RegisterEvent("PLAYER_TARGET_CHANGED", onTargetChanged)
    ns:RegisterEvent("PLAYER_FOCUS_CHANGED", updateAllFocus)
    ns:RegisterEvent("RAID_TARGET_UPDATE", onRaidTargetUpdate)
    ns:RegisterEvent("UNIT_POWER_UPDATE", onComboUpdate)
    ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCombatLogEvent)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, p in ipairs(C_NamePlate.GetNamePlates()) do
            local u = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
            if u then onPlateAdded(nil, u) end
        end
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("SPELLS_CHANGED", findKickSpell)
    if hoverTicker then hoverTicker:Hide() end
    ns:UnregisterEvent("NAME_PLATE_UNIT_ADDED", onPlateAdded)
    ns:UnregisterEvent("NAME_PLATE_UNIT_REMOVED", onPlateRemoved)
    ns:UnregisterEvent("PLAYER_TARGET_CHANGED", onTargetChanged)
    ns:UnregisterEvent("PLAYER_FOCUS_CHANGED", updateAllFocus)
    ns:UnregisterEvent("RAID_TARGET_UPDATE", onRaidTargetUpdate)
    ns:UnregisterEvent("UNIT_POWER_UPDATE", onComboUpdate)
    ns:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCombatLogEvent)
    for unit in pairs(ns.plates) do onPlateRemoved(nil, unit) end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, p in ipairs(C_NamePlate.GetNamePlates()) do
            if p.UnitFrame then p.UnitFrame:SetAlpha(1); p.UnitFrame:Show() end
        end
    end
end

local function fontValues()
    local vals = { { value = "", text = L["Addon font (default)"] } }
    if ns.LSM then
        for _, name in ipairs(ns.LSM:List("font") or {}) do
            vals[#vals + 1] = { value = name, text = name }
        end
    end
    return vals
end

local function textModeValues()
    return {
        { value = "none",       text = L["No text"] },
        { value = "percent",    text = L["Percent"] },
        { value = "current",    text = L["Current value"] },
        { value = "currentmax", text = L["Current / Max"] },
        { value = "both",       text = L["Value + percent"] },
    }
end

local function reactionPreviewValues()
    return {
        { value = "hostile",  text = L["Hostile"] },
        { value = "neutral",  text = L["Neutral"] },
        { value = "friendly", text = L["Friendly"] },
    }
end

local function friendlyModeValues()
    return {
        { value = "nameonly", text = L["Name only"] },
        { value = "full",     text = L["Full plate"] },
        { value = "hidden",   text = L["Hidden"] },
    }
end

local function markerPosValues()
    return {
        { value = "left",  text = L["Left"] },
        { value = "right", text = L["Right"] },
        { value = "top",   text = L["Above"] },
    }
end

local function borderStyleValues()
    return {
        { value = "lines",   text = L["Thin lines"] },
        { value = "texture", text = L["Texture"] },
    }
end

local function rowSideValues()
    return {
        { value = "top",    text = L["Above the plate"] },
        { value = "bottom", text = L["Below the plate"] },
    }
end

local function rowGrowValues()
    return {
        { value = "center", text = L["Centred"] },
        { value = "right",  text = L["To the right"] },
        { value = "left",   text = L["To the left"] },
    }
end

local function rowFilterValues()
    return {
        { value = "all",    text = L["Everything"] },
        { value = "mine",   text = L["Only mine"] },
        { value = "dispel", text = L["Only removable"] },
    }
end

-- Placement controls shared by every aura row; `key` selects which row's
-- settings the widgets read and write. withFilter is off for the rows whose
-- contents are already defined by what they collect (crowd control, your DoTs).
local function rowPlacementItems(key, SLW, applyAndRefresh, withFilter)
    local function cfg() return ns:NameplateRowCfg(key) end
    local items = {
        { type = "group", layout = "row", gap = 8, items = {
            { type = "dropdown", label = L["Side"], width = 200, values = rowSideValues(),
              tooltip = L["Which end of the plate this row sits on. Rows on the same side queue up outward."],
              get = function() return cfg().side or "top" end,
              set = function(_, v) cfg().side = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Grow"], width = 200, values = rowGrowValues(),
              tooltip = L["Which way the icons run. Left and right line the row up with the matching edge of the health bar."],
              get = function() return cfg().grow or "center" end,
              set = function(_, v) cfg().grow = v; applyAndRefresh() end },
        } },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "slider", label = L["Offset X"], min = -150, max = 150, step = 1, width = SLW,
              get = function() return cfg().x or 0 end,
              set = function(_, v) cfg().x = v; applyAndRefresh() end },
            { type = "slider", label = L["Offset Y"], min = -100, max = 100, step = 1, width = SLW,
              get = function() return cfg().y or 0 end,
              set = function(_, v) cfg().y = v; applyAndRefresh() end },
        } },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "slider", label = L["Icon spacing"], min = 0, max = 12, step = 1, width = SLW,
              get = function() return cfg().spacing or 2 end,
              set = function(_, v) cfg().spacing = v; applyAndRefresh() end },
            { type = "slider", label = L["Icons per line"], min = 0, max = 12, step = 1, width = SLW,
              tooltip = L["0 = one line. Otherwise the row wraps after this many icons."],
              get = function() return cfg().perRow or 0 end,
              set = function(_, v) cfg().perRow = v; applyAndRefresh() end },
        } },
    }
    if withFilter then
        items[#items + 1] = { type = "dropdown", label = L["Limit to"], width = 300, values = rowFilterValues(),
            tooltip = L["Narrows this row to auras you cast yourself, or to ones that can be removed."],
            get = function() return cfg().filter or "all" end,
            set = function(_, v) cfg().filter = v; applyAndRefresh() end }
    end
    return items
end

local function outlineValues()
    return {
        { value = "OUTLINE",      text = L["Outline"] },
        { value = "THICKOUTLINE", text = L["Thick outline"] },
        { value = "SHADOW",       text = L["Shadow"] },
        { value = "",             text = L["None"] },
    }
end

function mod:GetOptions()
    local SLW = 180
    return {
        { type = "desc",
          text = L["|cffaaaaaaCustom nameplates for enemies and NPCs. Configure below — the live preview updates as you change each option.|r"] },

        { type = "custom", height = 214, build = function(parent) return buildPreview(parent) end },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "dropdown", label = L["Preview reaction"], width = 300, values = reactionPreviewValues(),
              get = function()
                  if PREVIEW_CTX.reaction >= 5 then return "friendly"
                  elseif PREVIEW_CTX.reaction == 4 then return "neutral" end
                  return "hostile"
              end,
              set = function(_, v)
                  PREVIEW_CTX.reaction = (v == "friendly" and 5) or (v == "neutral" and 4) or 2
                  PREVIEW_CTX.enemy    = (v ~= "friendly")
                  if previewFrame then previewFrame:Update() end
              end },
        } },

        { type = "section", title = L["Health Bar"], collapsed = false, items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Width"], min = 60, max = 240, step = 2, width = SLW,
                  get = function() return mod.db.healthWidth end,
                  set = function(_, v) mod.db.healthWidth = v; applyAndRefresh() end },
                { type = "slider", label = L["Height"], min = 4, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.healthHeight end,
                  set = function(_, v) mod.db.healthHeight = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Smooth health changes"],
                  tooltip = L["The bar glides to the new value; a bright trail marks health draining away."],
                  get = function() return mod.db.healthSmooth end,
                  set = function(_, v) mod.db.healthSmooth = v; applyAndRefresh() end },
                { type = "checkbox", label = L["Tint background with bar colour"],
                  tooltip = L["The empty part of the bar shows a darkened shade of the bar colour instead of plain dark grey."],
                  get = function() return mod.db.bgTintByBar end,
                  set = function(_, v) mod.db.bgTintByBar = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Glow at the bar edge"],
                  tooltip = L["A soft glow rides the end of the fill, tinted in the bar's own colour. Also applies to the cast bar."],
                  get = function() return mod.db.showSpark end,
                  set = function(_, v) mod.db.showSpark = v; applyAndRefresh() end },
                { type = "checkbox", label = L["Rounded bar corners"],
                  tooltip = L["Clips the fill and background to a rounded shape. The line border stays square, so a thin border may show slightly at the corners."],
                  get = function() return mod.db.roundedBars end,
                  set = function(_, v) mod.db.roundedBars = v; applyAndRefresh() end },
            } },
            { type = "slider", label = L["Edge glow width"], min = 2, max = 40, step = 1, width = SLW,
              get = function() return mod.db.sparkWidth end,
              set = function(_, v) mod.db.sparkWidth = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Bar texture"], width = 300, values = textureValues(),
              get = function() return mod.db.healthTexture end,
              set = function(_, v) mod.db.healthTexture = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Border style"], width = 300, values = borderStyleValues(),
              get = function() return mod.db.borderStyle end,
              set = function(_, v) mod.db.borderStyle = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Border texture"], width = 300, values = borderTextureValues(),
              get = function() return mod.db.borderTexture end,
              set = function(_, v) mod.db.borderTexture = v; applyAndRefresh() end },
            { type = "color", label = L["Border colour"], width = 200,
              get = function() return mod.db.borderColor end,
              set = function(r, g, b) mod.db.borderColor = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "slider", label = L["Border thickness (px)"], min = 0, max = 12, step = 1,
              get = function() return mod.db.borderSize end,
              set = function(_, v) mod.db.borderSize = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Overall plate scale (%)"], min = 50, max = 200, step = 5, width = SLW,
                  tooltip = L["Scales every plate at once, on top of each individual size."],
                  get = function() return mod.db.globalScale or 100 end,
                  set = function(_, v) mod.db.globalScale = v; applyAndRefresh() end },
                { type = "slider", label = L["Vertical offset"], min = -100, max = 100, step = 1, width = SLW,
                  tooltip = L["Moves every plate up or down relative to its unit."],
                  get = function() return mod.db.plateOffsetY or 0 end,
                  set = function(_, v) mod.db.plateOffsetY = v; applyAndRefresh() end },
            } },
            { type = "checkbox", label = L["Show absorb shield"],
              tooltip = L["Overlays damage-absorption shields (e.g. Power Word: Shield) on the health bar."],
              get = function() return mod.db.showAbsorb end,
              set = function(_, v) mod.db.showAbsorb = v; applyAndRefresh() end },
            { type = "color", label = L["Absorb colour"], width = 200,
              get = function() return mod.db.colAbsorb end,
              set = function(r, g, b) mod.db.colAbsorb = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "slider", label = L["Absorb opacity"], min = 10, max = 100, step = 5,
              get = function() return floor((mod.db.absorbAlpha or 0.55) * 100 + 0.5) end,
              set = function(_, v) mod.db.absorbAlpha = v / 100; applyAndRefresh() end },
            { type = "checkbox", label = L["Execute line"],
              tooltip = L["A thin marker line on the bar at the chosen health percentage (e.g. 20 for Execute)."],
              get = function() return mod.db.execLine end,
              set = function(_, v) mod.db.execLine = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Execute line only on your target"],
              get = function() return mod.db.execTargetOnly end,
              set = function(_, v) mod.db.execTargetOnly = v; applyAndRefresh() end },
            { type = "color", label = L["Execute line colour"], width = 200,
              get = function() return mod.db.colExec end,
              set = function(r, g, b) mod.db.colExec = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "slider", label = L["Execute line percent"], min = 5, max = 90, step = 1,
              get = function() return mod.db.execPct or 20 end,
              set = function(_, v) mod.db.execPct = v; applyAndRefresh() end },
        } },

        { type = "section", title = L["Text"], collapsed = false, items = {
            { type = "dropdown", label = L["Font"], width = 300, values = fontValues(),
              tooltip = L["The typeface for every text on the plates (name, health, cast, auras)."],
              get = function() return mod.db.fontFace or "" end,
              set = function(_, v) mod.db.fontFace = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Font outline"], width = 300, values = outlineValues(),
              tooltip = L["How plate text is lifted off the background."],
              get = function() return mod.db.fontOutline or "OUTLINE" end,
              set = function(_, v) mod.db.fontOutline = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Show name"],
              get = function() return mod.db.showName end,
              set = function(_, v) mod.db.showName = v; refreshPage(); applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Show level"],
                  tooltip = L["Shows the unit level to the left of the name; ?? means the level is far above yours."],
                  get = function() return mod.db.showLevel end,
                  set = function(_, v) mod.db.showLevel = v; applyAndRefresh() end },
                { type = "checkbox", label = L["Mark rare and elite"],
                  tooltip = L["Appends a rank to the level and turns it gold: + elite, R rare, R+ rare elite, B world boss."],
                  get = function() return mod.db.showLevelMod ~= false end,
                  set = function(_, v) mod.db.showLevelMod = v; applyAndRefresh() end },
            } },
            { type = "slider", label = L["Level size"], min = 0, max = 20, step = 1, width = SLW,
              tooltip = L["0 = uses the name size."],
              get = function() return mod.db.levelSize or 0 end,
              set = function(_, v) mod.db.levelSize = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Show health text"],
              get = function() return mod.db.showHealthText end,
              set = function(_, v) mod.db.showHealthText = v; refreshPage(); applyAndRefresh() end },
            { type = "dropdown", label = L["Health text"], width = 300, values = textModeValues(),
              get = function() return mod.db.healthTextMode end,
              set = function(_, v) mod.db.healthTextMode = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Value + percent layout"], width = 300,
              values = {
                  { value = "%s (%s)", text = "12.3k (45%)" },
                  { value = "%s | %s", text = "12.3k | 45%" },
                  { value = "%s - %s", text = "12.3k - 45%" },
                  { value = "%s %s",   text = "12.3k 45%" },
              },
              get = function() return mod.db.healthTextFormat or "%s (%s)" end,
              set = function(_, v) mod.db.healthTextFormat = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Short values (12.3k)"],
                  get = function() return mod.db.healthTextShort end,
                  set = function(_, v) mod.db.healthTextShort = v; applyAndRefresh() end },
                { type = "checkbox", label = L["Show percent sign"],
                  get = function() return mod.db.healthTextPercentSign ~= false end,
                  set = function(_, v) mod.db.healthTextPercentSign = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Name size"], min = 6, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.nameSize end,
                  set = function(_, v) mod.db.nameSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Text size"], min = 6, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.fontSize end,
                  set = function(_, v) mod.db.fontSize = v; applyAndRefresh() end },
            } },
            { type = "slider", label = L["Health text size"], min = 0, max = 20, step = 1, width = SLW,
              tooltip = L["0 = uses the general text size."],
              get = function() return mod.db.healthTextSize or 0 end,
              set = function(_, v) mod.db.healthTextSize = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Name offset X"], min = -100, max = 100, step = 1, width = SLW,
                  get = function() return mod.db.nameOffsetX or 0 end,
                  set = function(_, v) mod.db.nameOffsetX = v; applyAndRefresh() end },
                { type = "slider", label = L["Name offset Y"], min = -40, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.nameOffsetY or 0 end,
                  set = function(_, v) mod.db.nameOffsetY = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Health text offset X"], min = -100, max = 100, step = 1, width = SLW,
                  get = function() return mod.db.healthTextOffsetX or 0 end,
                  set = function(_, v) mod.db.healthTextOffsetX = v; applyAndRefresh() end },
                { type = "slider", label = L["Health text offset Y"], min = -40, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.healthTextOffsetY or 0 end,
                  set = function(_, v) mod.db.healthTextOffsetY = v; applyAndRefresh() end },
            } },
        } },

        { type = "section", title = L["Colours"], collapsed = false, items = {
            { type = "checkbox", label = L["Class colour for enemy players"],
              get = function() return mod.db.classColorEnemy end,
              set = function(_, v) mod.db.classColorEnemy = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Class colour for friendly players"],
              get = function() return mod.db.classColorFriendly end,
              set = function(_, v) mod.db.classColorFriendly = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "color", label = L["Hostile"], width = 160,
                  get = function() return mod.db.colHostile end,
                  set = function(r, g, b) mod.db.colHostile = { r = r, g = g, b = b }; applyAndRefresh() end },
                { type = "color", label = L["Neutral"], width = 160,
                  get = function() return mod.db.colNeutral end,
                  set = function(r, g, b) mod.db.colNeutral = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "color", label = L["Friendly"], width = 160,
                  get = function() return mod.db.colFriendly end,
                  set = function(r, g, b) mod.db.colFriendly = { r = r, g = g, b = b }; applyAndRefresh() end },
                { type = "color", label = L["Tapped"], width = 160,
                  get = function() return mod.db.colTapped end,
                  set = function(r, g, b) mod.db.colTapped = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
        } },

        { type = "section", title = L["Cast Bar"], collapsed = false, items = {
            { type = "checkbox", label = L["Show cast bar"],
              get = function() return mod.db.showCastbar end,
              set = function(_, v) mod.db.showCastbar = v; refreshPage(); applyAndRefresh() end },
            { type = "checkbox", label = L["Show cast icon"],
              get = function() return mod.db.showCastIcon end,
              set = function(_, v) mod.db.showCastIcon = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Show cast text"],
              get = function() return mod.db.showCastText end,
              set = function(_, v) mod.db.showCastText = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Cast bar texture"], width = 300, values = textureValues(),
              get = function() return mod.db.castTexture end,
              set = function(_, v) mod.db.castTexture = v; applyAndRefresh() end },
            { type = "color", label = L["Cast colour"], width = 200,
              get = function() return mod.db.colCast end,
              set = function(r, g, b) mod.db.colCast = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "color", label = L["Non-interruptible"], width = 200,
              get = function() return mod.db.colCastNoInterrupt end,
              set = function(r, g, b) mod.db.colCastNoInterrupt = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "checkbox", label = L["Show remaining cast time"],
              get = function() return mod.db.castTimer end,
              set = function(_, v) mod.db.castTimer = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Own colour while your interrupt is on cooldown"],
              tooltip = L["Interruptible casts paint differently while YOUR interrupt ability is still on cooldown — you see at a glance whether kicking is even possible."],
              get = function() return mod.db.kickColorOn end,
              set = function(_, v) mod.db.kickColorOn = v; applyAndRefresh() end },
            { type = "color", label = L["Interrupt-on-cooldown colour"], width = 220,
              get = function() return mod.db.colCastKickCd end,
              set = function(r, g, b) mod.db.colCastKickCd = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Own colour while your interrupt is ready"],
                  tooltip = L["Interruptible casts paint in this colour while your interrupt is off cooldown — kick at will."],
                  get = function() return mod.db.kickReadyColorOn end,
                  set = function(_, v) mod.db.kickReadyColorOn = v; applyAndRefresh() end },
                { type = "color", label = L["Interrupt-ready colour"], width = 160,
                  get = function() return mod.db.colCastKickReady end,
                  set = function(r, g, b) mod.db.colCastKickReady = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Own colour while channelling"],
                  get = function() return mod.db.castChannelColor end,
                  set = function(_, v) mod.db.castChannelColor = v; applyAndRefresh() end },
                { type = "color", label = L["Channel colour"], width = 160,
                  get = function() return mod.db.colCastChannel end,
                  set = function(r, g, b) mod.db.colCastChannel = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Own colour when the cast targets YOU"],
                  tooltip = L["The bar turns this colour while the caster's target is you."],
                  get = function() return mod.db.castYouColorOn end,
                  set = function(_, v) mod.db.castYouColorOn = v; applyAndRefresh() end },
                { type = "color", label = L["Targets-you colour"], width = 160,
                  get = function() return mod.db.colCastYou end,
                  set = function(r, g, b) mod.db.colCastYou = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
            { type = "checkbox", label = L["Show who interrupted"],
              tooltip = L["The interrupt flash shows the name of whoever landed the interrupt."],
              get = function() return mod.db.castInterrupter end,
              set = function(_, v) mod.db.castInterrupter = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Cast bar height"], min = 4, max = 30, step = 1, width = SLW,
                  get = function() return mod.db.castHeight end,
                  set = function(_, v) mod.db.castHeight = v; applyAndRefresh() end },
                { type = "slider", label = L["Cast bar width"], min = 0, max = 250, step = 2, width = SLW,
                  tooltip = L["0 = match the health bar width."],
                  get = function() return mod.db.castWidth or 0 end,
                  set = function(_, v) mod.db.castWidth = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Cast text size"], min = 0, max = 20, step = 1, width = SLW,
                  tooltip = L["0 = uses the general text size."],
                  get = function() return mod.db.castTextSize or 0 end,
                  set = function(_, v) mod.db.castTextSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Cast timer size"], min = 0, max = 20, step = 1, width = SLW,
                  tooltip = L["0 = uses the general text size."],
                  get = function() return mod.db.castTimerSize or 0 end,
                  set = function(_, v) mod.db.castTimerSize = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Offset X"], min = -100, max = 100, step = 1, width = SLW,
                  get = function() return mod.db.castOffsetX or 0 end,
                  set = function(_, v) mod.db.castOffsetX = v; applyAndRefresh() end },
                { type = "slider", label = L["Offset Y"], min = -60, max = 60, step = 1, width = SLW,
                  get = function() return mod.db.castOffsetY or 0 end,
                  set = function(_, v) mod.db.castOffsetY = v; applyAndRefresh() end },
            } },
            { type = "color", label = L["Cast background colour"], width = 220,
              get = function() return mod.db.castBgColor end,
              set = function(r, g, b) mod.db.castBgColor = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "slider", label = L["Cast background opacity"], min = 0, max = 100, step = 5, width = SLW,
              tooltip = L["0 = uses the global background opacity."],
              get = function() return floor((mod.db.castBgAlpha or 0) * 100 + 0.5) end,
              set = function(_, v) mod.db.castBgAlpha = v / 100; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Icon scale"], min = 50, max = 200, step = 5, width = SLW,
                  get = function() return mod.db.castIconScale or 100 end,
                  set = function(_, v) mod.db.castIconScale = v; applyAndRefresh() end },
                { type = "checkbox", label = L["Icon on the right"],
                  get = function() return mod.db.castIconRight end,
                  set = function(_, v) mod.db.castIconRight = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Icon offset X"], min = -40, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.castIconX or 0 end,
                  set = function(_, v) mod.db.castIconX = v; applyAndRefresh() end },
                { type = "slider", label = L["Icon offset Y"], min = -40, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.castIconY or 0 end,
                  set = function(_, v) mod.db.castIconY = v; applyAndRefresh() end },
            } },
            { type = "checkbox", label = L["Shield on uninterruptible casts"],
              get = function() return mod.db.showCastShield end,
              set = function(_, v) mod.db.showCastShield = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Tick where your interrupt becomes ready"],
              tooltip = L["Marks the spot on the enemy cast bar where YOUR interrupt comes off cooldown — everything after the tick is kickable."],
              get = function() return mod.db.castKickTick end,
              set = function(_, v) mod.db.castKickTick = v; applyAndRefresh() end },
            { type = "color", label = L["Tick colour"], width = 200,
              get = function() return mod.db.colKickTick end,
              set = function(r, g, b) mod.db.colKickTick = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "checkbox", label = L["Flash when a cast is interrupted"],
              get = function() return mod.db.castInterruptFlash end,
              set = function(_, v) mod.db.castInterruptFlash = v; applyAndRefresh() end },
            { type = "color", label = L["Flash colour"], width = 200,
              get = function() return mod.db.colInterruptFlash end,
              set = function(r, g, b) mod.db.colInterruptFlash = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "color", label = L["Cast text colour"], width = 200,
              get = function() return mod.db.castTextColor end,
              set = function(r, g, b) mod.db.castTextColor = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "dropdown", label = L["Timer side"], width = 220,
              values = {
                  { value = "right", text = L["Right"] },
                  { value = "left",  text = L["Left"] },
              },
              get = function() return mod.db.castTimerSide or "right" end,
              set = function(_, v) mod.db.castTimerSide = v; applyAndRefresh() end },
            { type = "color", label = L["Timer colour"], width = 200,
              get = function() return mod.db.castTimerColor end,
              set = function(r, g, b) mod.db.castTimerColor = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "checkbox", label = L["Hide name while casting"],
              get = function() return mod.db.hideNameWhileCasting end,
              set = function(_, v) mod.db.hideNameWhileCasting = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Emphasise casting units"],
              tooltip = L["While a unit casts, its plate grows a little and stays readable even when something else is targeted."],
              get = function() return mod.db.castEmphasis end,
              set = function(_, v) mod.db.castEmphasis = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Casting scale (%)"], min = 100, max = 160, step = 5, width = SLW,
                  get = function() return mod.db.castEmphScale or 110 end,
                  set = function(_, v) mod.db.castEmphScale = v; applyAndRefresh() end },
                { type = "slider", label = L["Casting opacity (%)"], min = 10, max = 100, step = 5, width = SLW,
                  get = function() return mod.db.castEmphAlpha or 100 end,
                  set = function(_, v) mod.db.castEmphAlpha = v; applyAndRefresh() end },
            } },
        } },

        { type = "section", title = L["Target & Threat"], collapsed = false, items = {
            { type = "checkbox", label = L["Highlight your target"],
              get = function() return mod.db.targetHighlight end,
              set = function(_, v) mod.db.targetHighlight = v; applyAndRefresh() end },
            { type = "color", label = L["Target highlight colour"], width = 220,
              get = function() return mod.db.colTarget end,
              set = function(r, g, b) mod.db.colTarget = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "checkbox", label = L["Own bar colour on your target"],
              tooltip = L["Your current target's health bar uses this colour instead of reaction / class / threat colours."],
              get = function() return mod.db.targetBarColor end,
              set = function(_, v) mod.db.targetBarColor = v; applyAndRefresh() end },
            { type = "color", label = L["Target bar colour"], width = 220,
              get = function() return mod.db.colTargetBar end,
              set = function(r, g, b) mod.db.colTargetBar = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "checkbox", label = L["Mouseover highlight"],
              tooltip = L["Lightens the health bar of the plate under your mouse cursor."],
              get = function() return mod.db.hoverHighlight end,
              set = function(_, v) mod.db.hoverHighlight = v; updateHoverTicker() end },
            { type = "slider", label = L["Target plate scale"], min = 100, max = 150, step = 5,
              tooltip = L["Your target's plate is drawn this much larger (100 = off)."],
              get = function() return mod.db.targetScale or 100 end,
              set = function(_, v) mod.db.targetScale = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Highlight your focus"],
              tooltip = L["A second, distinct glow ring on your focus target's nameplate."],
              get = function() return mod.db.focusHighlight end,
              set = function(_, v) mod.db.focusHighlight = v; applyAndRefresh() end },
            { type = "color", label = L["Focus highlight colour"], width = 220,
              get = function() return mod.db.colFocus end,
              set = function(r, g, b) mod.db.colFocus = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "slider", label = L["Non-target opacity"], min = 20, max = 100, step = 5, width = SLW,
              get = function() return floor((mod.db.nonTargetAlpha or 1) * 100 + 0.5) end,
              set = function(_, v) mod.db.nonTargetAlpha = v / 100; applyAndRefresh() end },
            { type = "checkbox", label = L["Colour by threat"],
              tooltip = L["Colour the health bar by your threat on the unit — coloured for your role. Useful in dungeons."],
              get = function() return mod.db.threatEnabled end,
              set = function(_, v) mod.db.threatEnabled = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Your role"], width = 300, values = {
                  { value = "dps",  text = L["DPS / Healer"] },
                  { value = "tank", text = L["Tank"] },
              },
              get = function() return mod.db.threatRole end,
              set = function(_, v) mod.db.threatRole = v; applyAndRefresh() end },
            { type = "color", label = L["Secure (tank has aggro)"], width = 220,
              get = function() return mod.db.colThreatGood end,
              set = function(r, g, b) mod.db.colThreatGood = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "color", label = L["Warning (gaining / losing)"], width = 220,
              get = function() return mod.db.colThreatWarn end,
              set = function(r, g, b) mod.db.colThreatWarn = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "color", label = L["Danger (pulled / lost)"], width = 220,
              get = function() return mod.db.colThreatBad end,
              set = function(r, g, b) mod.db.colThreatBad = { r = r, g = g, b = b }; applyAndRefresh() end },
        } },

        { type = "section", title = L["Auras"], collapsed = false, items = {
            { type = "checkbox", label = L["Show debuffs"],
              get = function() return mod.db.showDebuffs end,
              set = function(_, v) mod.db.showDebuffs = v; refreshPage(); applyAndRefresh() end },
            { type = "checkbox", label = L["Show all debuffs (not just yours)"],
              tooltip = L["Off: only debuffs you applied. On: every debuff on the unit."],
              get = function() return mod.db.debuffsAll end,
              set = function(_, v) mod.db.debuffsAll = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Debuff icon size"], min = 12, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.debuffSize end,
                  set = function(_, v) mod.db.debuffSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Max debuffs"], min = 1, max = 8, step = 1, width = SLW,
                  get = function() return mod.db.maxDebuffs end,
                  set = function(_, v) mod.db.maxDebuffs = v; applyAndRefresh() end },
            } },
            { type = "checkbox", label = L["Show buffs"],
              get = function() return mod.db.showBuffs end,
              set = function(_, v) mod.db.showBuffs = v; refreshPage(); applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Buff icon size"], min = 12, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.buffSize end,
                  set = function(_, v) mod.db.buffSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Max buffs"], min = 1, max = 8, step = 1, width = SLW,
                  get = function() return mod.db.maxBuffs end,
                  set = function(_, v) mod.db.maxBuffs = v; applyAndRefresh() end },
            } },
            -- Spacing moved into each row's own section; a global control here
            -- would be dead, since every row now carries its own value.
            { type = "checkbox", label = L["Cooldown swipe"],
              get = function() return mod.db.auraSwipe end,
              set = function(_, v) mod.db.auraSwipe = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Glow stealable / dispellable buffs"],
              tooltip = L["Glows enemy buffs you can remove (Spellsteal / Purge / Dispel Magic). Only for classes that can."],
              get = function() return mod.db.showDispelGlow end,
              set = function(_, v) mod.db.showDispelGlow = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Colour border by school"],
              tooltip = L["Aura borders take the colour of their school: magic blue, curse purple, disease orange, poison green."],
              get = function() return mod.db.auraTypeBorder ~= false end,
              set = function(_, v) mod.db.auraTypeBorder = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Flash before running out"],
              tooltip = L["The icon pulses over the last part of its duration, so you can see when to refresh."],
              get = function() return mod.db.auraExpireFlash ~= false end,
              set = function(_, v) mod.db.auraExpireFlash = v; applyAndRefresh() end },
            { type = "slider", label = L["Flash below (%)"], min = 5, max = 60, step = 5, width = SLW,
              tooltip = L["Share of the remaining duration at which the pulse starts."],
              get = function() return mod.db.auraExpirePct or 30 end,
              set = function(_, v) mod.db.auraExpirePct = v; applyAndRefresh() end },
            { type = "color", label = L["Dispel glow colour"], width = 220,
              get = function() return mod.db.colDispel end,
              set = function(r, g, b) mod.db.colDispel = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "checkbox", label = L["Show timer text"],
              get = function() return mod.db.showAuraTimer end,
              set = function(_, v) mod.db.showAuraTimer = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Timer decimals below 10 seconds"],
              tooltip = L["On: 9.9, 3.4 … Off: whole seconds (9, 3)."],
              get = function() return mod.db.auraTimerDecimals ~= false end,
              set = function(_, v) mod.db.auraTimerDecimals = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Show stacks"],
              get = function() return mod.db.showAuraStacks end,
              set = function(_, v) mod.db.showAuraStacks = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Timer text size"], min = 6, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.auraTimerSize end,
                  set = function(_, v) mod.db.auraTimerSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Stack text size"], min = 6, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.auraStackSize end,
                  set = function(_, v) mod.db.auraStackSize = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Aura offset X"], min = -100, max = 100, step = 1, width = SLW,
                  tooltip = L["Nudges every aura row at once, on top of each row's own offset."],
                  get = function() return mod.db.auraOffsetX or 0 end,
                  set = function(_, v) mod.db.auraOffsetX = v; applyAndRefresh() end },
                { type = "slider", label = L["Aura offset Y"], min = -40, max = 60, step = 1, width = SLW,
                  tooltip = L["Nudges every aura row at once, on top of each row's own offset."],
                  get = function() return mod.db.auraOffsetY or 0 end,
                  set = function(_, v) mod.db.auraOffsetY = v; applyAndRefresh() end },
            } },
        } },

        { type = "section", title = L["Debuff Row"], collapsed = true, items =
            rowPlacementItems("debuff", SLW, applyAndRefresh, true) },

        { type = "section", title = L["Buff Row"], collapsed = true, items =
            rowPlacementItems("buff", SLW, applyAndRefresh, true) },

        { type = "section", title = L["Crowd Control"], collapsed = false, items = {
            { type = "checkbox", label = L["Show crowd control (separate row)"],
              tooltip = L["A separate, prominent row for crowd-control effects (Polymorph, Fear, Sap, …) on the unit, from anyone."],
              get = function() return mod.db.showCC end,
              set = function(_, v) mod.db.showCC = v; refreshPage(); applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["CC icon size"], min = 12, max = 48, step = 1, width = SLW,
                  get = function() return mod.db.ccSize end,
                  set = function(_, v) mod.db.ccSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Max CC"], min = 1, max = 5, step = 1, width = SLW,
                  get = function() return mod.db.maxCC end,
                  set = function(_, v) mod.db.maxCC = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["CC icon width"], min = 0, max = 64, step = 1, width = SLW,
                  tooltip = L["0 = square (uses the icon size)."],
                  get = function() return mod.db.ccWidth or 0 end,
                  set = function(_, v) mod.db.ccWidth = v; applyAndRefresh() end },
                { type = "slider", label = L["CC icon height"], min = 0, max = 64, step = 1, width = SLW,
                  tooltip = L["0 = square (uses the icon size)."],
                  get = function() return mod.db.ccHeight or 0 end,
                  set = function(_, v) mod.db.ccHeight = v; applyAndRefresh() end },
            } },
            unpack(rowPlacementItems("cc", SLW, applyAndRefresh, false)),
        } },

        { type = "section", title = L["Your Own Debuffs"], collapsed = true, items = {
            { type = "desc",
              text = L["|cffaaaaaaA separate row for the harmful auras you cast yourself - your damage-over-time timers, kept away from everything else on the target.|r"] },
            { type = "checkbox", label = L["Show your own debuffs (separate row)"],
              get = function() return mod.db.showDots end,
              set = function(_, v) mod.db.showDots = v; refreshPage(); applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Icon size"], min = 12, max = 48, step = 1, width = SLW,
                  get = function() return mod.db.dotSize end,
                  set = function(_, v) mod.db.dotSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Max icons"], min = 1, max = 12, step = 1, width = SLW,
                  get = function() return mod.db.maxDots end,
                  set = function(_, v) mod.db.maxDots = v; applyAndRefresh() end },
            } },
            unpack(rowPlacementItems("dot", SLW, applyAndRefresh, false)),
        } },

        { type = "section", title = L["Friendly Plates"], collapsed = false, items = {
            { type = "checkbox", label = L["Show friendly nameplates"],
              tooltip = L["Sets Blizzard's friendly-nameplate option (cannot change in combat)."],
              get = function() return mod.db.friendlyShow end,
              set = function(_, v) mod.db.friendlyShow = v; applyFriendlyCVar(); applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "dropdown", label = L["Friendly players"], width = 300, values = friendlyModeValues(),
                  get = function() return mod.db.friendlyPlayers end,
                  set = function(_, v) mod.db.friendlyPlayers = v; applyAndRefresh() end },
                { type = "dropdown", label = L["Friendly NPCs"], width = 300, values = friendlyModeValues(),
                  get = function() return mod.db.friendlyNPCs end,
                  set = function(_, v) mod.db.friendlyNPCs = v; applyAndRefresh() end },
            } },
            { type = "slider", label = L["NPC title size"], min = 0, max = 20, step = 1, width = SLW,
              tooltip = L["0 = slightly smaller than the name."],
              get = function() return mod.db.titleSize or 0 end,
              set = function(_, v) mod.db.titleSize = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Show NPC title"],
              tooltip = L["Shows a friendly NPC's subtitle (e.g. <Innkeeper>) under its name in name-only mode."],
              get = function() return mod.db.showNPCTitle end,
              set = function(_, v) mod.db.showNPCTitle = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "color", label = L["Friendly player name"], width = 220,
                  get = function() return mod.db.friendlyNameColor end,
                  set = function(r, g, b) mod.db.friendlyNameColor = { r = r, g = g, b = b }; applyAndRefresh() end },
                { type = "color", label = L["Friendly NPC name"], width = 220,
                  get = function() return mod.db.friendlyNPCColor end,
                  set = function(r, g, b) mod.db.friendlyNPCColor = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
        } },

        { type = "section", title = L["Raid Marker"], collapsed = false, items = {
            { type = "checkbox", label = L["Show target markers"],
              tooltip = L["Shows the raid target icon (skull, cross, …) that is set on the unit."],
              get = function() return mod.db.showRaidMarker end,
              set = function(_, v) mod.db.showRaidMarker = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Marker position"], width = 300, values = markerPosValues(),
              get = function() return mod.db.raidMarkerPos end,
              set = function(_, v) mod.db.raidMarkerPos = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Marker size"], min = 8, max = 48, step = 1, width = SLW,
                  get = function() return mod.db.raidMarkerSize end,
                  set = function(_, v) mod.db.raidMarkerSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Marker offset X"], min = -40, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.raidMarkerX end,
                  set = function(_, v) mod.db.raidMarkerX = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Marker offset Y"], min = -40, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.raidMarkerY end,
                  set = function(_, v) mod.db.raidMarkerY = v; applyAndRefresh() end },
            } },
        } },

        { type = "section", title = L["Combo Points"], collapsed = false, items = {
            { type = "checkbox", label = L["Show combo points"],
              tooltip = L["Shows your combo points on the target's nameplate (Rogue, or Druid in cat form)."],
              get = function() return mod.db.showClassPower end,
              set = function(_, v) mod.db.showClassPower = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Pip size"], min = 4, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.cpSize end,
                  set = function(_, v) mod.db.cpSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Pip spacing"], min = 0, max = 12, step = 1, width = SLW,
                  get = function() return mod.db.cpSpacing end,
                  set = function(_, v) mod.db.cpSpacing = v; applyAndRefresh() end },
            } },
            { type = "color", label = L["Point colour"], width = 200,
              get = function() return mod.db.cpColor end,
              set = function(r, g, b) mod.db.cpColor = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "dropdown", label = L["Point shape"], width = 220,
              values = {
                  { value = "square",   text = L["Square"] },
                  { value = "circle",   text = L["Circle"] },
                  { value = "diamond",  text = L["Diamond"] },
                  { value = "triangle", text = L["Triangle"] },
              },
              get = function() return mod.db.cpShape or "square" end,
              set = function(_, v) mod.db.cpShape = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Position"], width = 220,
              values = {
                  { value = "below", text = L["Below the bar"] },
                  { value = "above", text = L["Above the bar"] },
              },
              get = function() return mod.db.cpPos or "below" end,
              set = function(_, v) mod.db.cpPos = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Offset X"], min = -60, max = 60, step = 1, width = SLW,
                  get = function() return mod.db.cpOffsetX or 0 end,
                  set = function(_, v) mod.db.cpOffsetX = v; applyAndRefresh() end },
                { type = "slider", label = L["Offset Y"], min = -40, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.cpOffsetY or 0 end,
                  set = function(_, v) mod.db.cpOffsetY = v; applyAndRefresh() end },
            } },
        } },

        { type = "section", title = L["Behaviour"], collapsed = true, items = {
            { type = "desc",
              text = L["|cffaaaaaaThese are the game's own nameplate settings, changed live (not part of the profile). Not changeable in combat.|r"] },
            { type = "dropdown", label = L["Plate motion"], width = 260,
              values = {
                  { value = "0", text = L["Overlapping"] },
                  { value = "1", text = L["Stacking"] },
              },
              get = function() return GetCVar and tostring(GetCVar("nameplateMotion")) or "0" end,
              set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateMotion", v) end end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Stacked spacing"], min = 4, max = 20, step = 1, width = SLW,
                  tooltip = L["Vertical distance between stacked plates (a tenth of the game value)."],
                  get = function() return floor((tonumber(GetCVar and GetCVar("nameplateOverlapV")) or 1.1) * 10 + 0.5) end,
                  set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateOverlapV", v / 10) end end },
                { type = "slider", label = L["Line-of-sight opacity"], min = 0, max = 100, step = 5, width = SLW,
                  tooltip = L["Opacity of plates whose unit is out of your line of sight."],
                  get = function() return floor((tonumber(GetCVar and GetCVar("nameplateOccludedAlphaMult")) or 0.4) * 100 + 0.5) end,
                  set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateOccludedAlphaMult", v / 100) end end },
            } },
            { type = "slider", label = L["Plate view distance"], min = 20, max = 60, step = 1,
              get = function() return floor(tonumber(GetCVar and GetCVar("nameplateMaxDistance")) or 41) end,
              set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateMaxDistance", v) end end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Hitbox width"], min = 0, max = 200, step = 5, width = SLW,
                  tooltip = L["Clickable plate area (0 = the game's default). Stored in the profile."],
                  get = function() return mod.db.hitboxW or 0 end,
                  set = function(_, v) mod.db.hitboxW = v; applyHitbox() end },
                { type = "slider", label = L["Hitbox height"], min = 0, max = 100, step = 5, width = SLW,
                  get = function() return mod.db.hitboxH or 0 end,
                  set = function(_, v) mod.db.hitboxH = v; applyHitbox() end },
            } },
        } },
    }
end
