-- =========================================================
-- VuloClassicUI / Modules / Nameplates
-- Custom enemy/NPC nameplates: our own health bar + cast bar + name + text
-- are attached onto Blizzard's C_NamePlate anchor, and Blizzard's own
-- UnitFrame is suppressed. This is iteration 1 (core): health bar, cast bar,
-- name / health text, reaction & class colours, target highlight and threat.
--
-- Taint discipline: we NEVER store custom keys on Blizzard's C_NamePlate frame
-- (that taints it). Every plate<->unit link lives in the side table ns.plates.
-- The Options screen carries a pixel-accurate LIVE PREVIEW built from the exact
-- same paint helpers, so what you configure is what you see on real plates.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("nameplates", {
    name        = "Nameplates",
    group       = "Unit Frames",
    description = "Custom enemy & NPC nameplates with a live preview: health bar, cast bar, name and health text, reaction / class colours, target highlight and threat colouring.",
    defaults = {
        enabled = true,

        -- Health bar
        healthWidth   = 120,
        healthHeight  = 10,
        healthTexture = "Atrocity",
        bgAlpha       = 0.85,
        borderSize    = 1,
        borderStyle   = "lines",             -- lines | texture
        borderTexture = "Blizzard Tooltip",  -- SharedMedia "border" name (texture style)
        borderColor   = { r = 0.067, g = 0.067, b = 0.067 },

        -- Absorb shield overlay on the health bar
        showAbsorb  = true,
        colAbsorb   = { r = 0.70, g = 0.85, b = 1.00 },
        absorbAlpha = 0.55,

        -- Name + health text
        showName        = true,
        nameSize        = 10,
        showHealthText  = true,
        healthTextMode  = "percent",     -- none | percent | current | currentmax
        fontSize        = 9,

        -- Reaction colours
        colHostile  = { r = 0.85, g = 0.20, b = 0.20 },
        colNeutral  = { r = 0.90, g = 0.80, b = 0.20 },
        colFriendly = { r = 0.25, g = 0.70, b = 0.35 },
        colTapped   = { r = 0.55, g = 0.55, b = 0.55 },
        classColorEnemy    = true,       -- enemy players use their class colour
        classColorFriendly = false,      -- friendly players use their class colour

        -- Cast bar
        showCastbar   = true,
        castHeight    = 12,
        castTexture   = "Atrocity",
        showCastIcon  = true,
        showCastText  = true,
        colCast              = { r = 0.70, g = 0.40, b = 0.90 },
        colCastNoInterrupt   = { r = 0.55, g = 0.55, b = 0.55 },

        -- Target highlight
        targetHighlight = true,
        colTarget       = { r = 1, g = 1, b = 1 },
        nonTargetAlpha  = 1.0,           -- fade non-target plates when you have a target

        -- Focus highlight (a second, distinct glow ring)
        focusHighlight  = true,
        colFocus        = { r = 0.20, g = 0.60, b = 1.00 },

        -- Threat (role-aware bar colouring; useful in dungeons)
        threatEnabled = false,
        threatRole    = "dps",                          -- dps | tank
        colThreatGood = { r = 0.25, g = 0.75, b = 0.30 }, -- tank: securely tanking
        colThreatWarn = { r = 0.95, g = 0.80, b = 0.20 }, -- transition (gaining/losing)
        colThreatBad  = { r = 0.95, g = 0.25, b = 0.20 }, -- dps pulled / tank lost aggro

        -- Class power (combo points on the target — Rogue / Druid in cat form)
        showClassPower = true,
        cpSize         = 8,
        cpSpacing      = 3,
        cpColor        = { r = 1.0, g = 0.85, b = 0.20 },

        -- Raid target markers (skull, cross, …)
        showRaidMarker = true,
        raidMarkerSize = 18,
        raidMarkerPos  = "left",             -- top | left | right
        raidMarkerX    = 0,
        raidMarkerY    = 0,

        -- Friendly plates
        friendlyShow      = true,            -- drives the nameplateShowFriends CVar
        friendlyPlayers   = "nameonly",      -- nameonly | full | hidden
        friendlyNPCs      = "nameonly",
        friendlyNameColor = { r = 0.60, g = 0.80, b = 1.00 },
        friendlyNPCColor  = { r = 0.60, g = 1.00, b = 0.60 },
        showNPCTitle      = true,            -- <subname> under a friendly NPC's name

        -- Auras
        showDebuffs    = true,
        debuffsAll     = false,          -- false = only your own debuffs
        maxDebuffs     = 5,
        debuffSize     = 22,
        showBuffs      = false,
        maxBuffs       = 4,
        buffSize       = 20,
        showCC         = true,           -- separate crowd-control row (prominent)
        maxCC          = 2,
        ccSize         = 28,
        auraSpacing    = 2,
        auraSwipe      = true,
        showDispelGlow = true,           -- glow buffs you can steal/dispel
        colDispel      = { r = 0.60, g = 0.40, b = 1.00 },
        showAuraTimer  = true,
        showAuraStacks = true,
        auraTimerSize  = 10,
        auraStackSize  = 9,
    },
})

-- =========================================================
-- Upvalues / constants
-- =========================================================
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitName, UnitReaction, UnitClass = UnitName, UnitReaction, UnitClass
local UnitIsPlayer, UnitCanAttack, UnitIsUnit = UnitIsPlayer, UnitCanAttack, UnitIsUnit
local UnitIsTapDenied = UnitIsTapDenied
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local UnitThreatSituation, UnitAffectingCombat = UnitThreatSituation, UnitAffectingCombat
local CLASS_COLORS = RAID_CLASS_COLORS or CUSTOM_CLASS_COLORS
local format, floor = string.format, math.floor

local BUNDLED_TEXTURES = {
    "Atrocity", "Beautiful", "Divide", "Fade", "Glass", "Gradient",
    "Matte", "Melli", "Plating", "Sheer", "Soft Line",
}
local DEFAULT_TEXTURE = "Atrocity"

local function lsmStatusbar(name)
    if ns.LSM and name then
        local hash = ns.LSM:HashTable("statusbar")
        local path = hash and hash[name]
        if path and path ~= "" then return path end
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end
local function textureValues()
    local v = {}
    for _, n in ipairs(BUNDLED_TEXTURES) do v[#v + 1] = { value = n, text = n } end
    return v
end

-- SharedMedia "border" edge file (falls back to a clean solid edge).
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

-- Hidden tooltip to read an NPC's subname (<Innkeeper> etc.). There is no direct
-- API for the unit subtitle, so we scan line 2 of its tooltip.
local scanTip = CreateFrame("GameTooltip", "VCUINameplateScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

local function getNPCTitle(unit)
    if not unit or UnitIsPlayer(unit) then return nil end
    scanTip:ClearLines()
    scanTip:SetUnit(unit)
    local fs = _G["VCUINameplateScanTipTextLeft2"]
    local txt = fs and fs:GetText()
    if not txt or txt == "" then return nil end
    -- Reject the level line: it has digits, or "??" for a skull-level unit, or
    -- the localized LEVEL word. A real subname has none of these.
    if txt:find("%d") or txt:find("%?%?") then return nil end
    if LEVEL and txt:find(LEVEL) then return nil end
    return txt
end

-- =========================================================
-- Colour resolution (shared by real plates and the preview)
-- ctx = { player=bool, enemy=bool, class="MAGE", reaction=1..8,
--         tapped=bool, threat=0..3 }
-- =========================================================
local function classColor(class)
    local c = class and CLASS_COLORS and CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return nil
end

local function reactionColor(d, ctx)
    -- Tapped mobs first (someone else's kill)
    if ctx.tapped then
        local c = d.colTapped; return c.r, c.g, c.b
    end
    -- Class colour for players, when enabled for that side
    if ctx.player and ctx.class then
        if ctx.enemy and d.classColorEnemy then
            local r, g, b = classColor(ctx.class); if r then return r, g, b end
        elseif (not ctx.enemy) and d.classColorFriendly then
            local r, g, b = classColor(ctx.class); if r then return r, g, b end
        end
    end
    -- Reaction fallback
    local reaction = ctx.reaction or (ctx.enemy and 2 or 5)
    local c
    if reaction <= 3 then     c = d.colHostile
    elseif reaction == 4 then c = d.colNeutral
    else                      c = d.colFriendly end
    return c.r, c.g, c.b
end

-- Role-aware threat colour from UnitThreatSituation (0..3), or nil to fall back
-- to reaction colour. sit: 0 on table not tanking, 1 higher-not-tanking,
-- 2 tanking-insecure, 3 tanking-secure.
local function threatColor(d, sit)
    if d.threatRole == "tank" then
        if sit == 3 then return d.colThreatGood      -- securely tanking = good
        elseif sit == 1 or sit == 2 then return d.colThreatWarn
        else return d.colThreatBad end               -- sit 0 = lost aggro = bad
    else -- dps / healer: any tanking = you pulled = bad
        if sit >= 2 then return d.colThreatBad
        elseif sit == 1 then return d.colThreatWarn end
    end
    return nil                                        -- no aggro concern → reaction
end

-- Final health colour: threat overrides reaction when enabled and in combat.
local function healthColor(d, ctx)
    if d.threatEnabled and ctx.threat ~= nil then
        local c = threatColor(d, ctx.threat)
        if c then return c.r, c.g, c.b end
    end
    return reactionColor(d, ctx)
end

-- =========================================================
-- Visual construction — one recipe, used by real plates AND the preview
-- =========================================================
local function makeEdges(parent, layer)
    local e = {}
    for _, side in ipairs({ "top", "bot", "lft", "rgt" }) do
        local t = parent:CreateTexture(nil, layer or "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        e[side] = t
    end
    return e
end

-- Lay a 4-edge border exactly `n` physical pixels thick around `anchor`,
-- offset `pad` pixels outward. n<=0 hides it.
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

-- Build the sub-frames of a plate onto `f` (a Frame). Called once per frame.
local function buildVisuals(f)
    -- Health bar
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
    -- Absorb overlay: a segment drawn on the bar just past the current health.
    f.absorb = f.health:CreateTexture(nil, "ARTWORK", nil, 2)
    f.absorb:Hide()

    -- Name: parented to the plate ROOT (not the health bar) so name-only mode
    -- can hide the bar without hiding the name. Health text stays on the bar.
    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetPoint("BOTTOM", f.health, "TOP", 0, 3)
    f.title = f:CreateFontString(nil, "OVERLAY")   -- friendly NPC subname (name-only)
    f.title:Hide()
    f.healthText = f.health:CreateFontString(nil, "OVERLAY")
    f.healthText:SetPoint("CENTER", f.health, "CENTER", 0, 0)

    -- Cast bar (below the bar)
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
    f.cast:Hide()

    -- Aura rows (debuffs + buffs + CC). 1px anchor points; icons hang off centre.
    f.debuffGroup = CreateFrame("Frame", nil, f); f.debuffGroup:SetSize(1, 1)
    f.buffGroup   = CreateFrame("Frame", nil, f); f.buffGroup:SetSize(1, 1)
    f.ccGroup     = CreateFrame("Frame", nil, f); f.ccGroup:SetSize(1, 1)

    -- Raid target marker (root-parented so it shows in name-only mode too)
    f.raidIcon = f:CreateTexture(nil, "OVERLAY")
    f.raidIcon:Hide()

    -- Class-power pips (combo points) — centred row below the bar
    f.cpGroup = CreateFrame("Frame", nil, f); f.cpGroup:SetSize(1, 1)
    f.cpGroup.pips = {}
    f.cpGroup:Hide()
end

-- Border for one bar: either our thin colour edges, or a SharedMedia edge-file
-- backdrop. Whichever is active hides the other.
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
        layoutEdges(edges, bar, d.borderSize, c.r, c.g, c.b, 1, 0)
    end
end

local function applyBarBorders(f, d)
    applyBarBorder(f.health, f.healthBorder, f.healthBD, d)
    applyBarBorder(f.cast,   f.castBorder,   f.castBD,   d)
end

-- Position everything from the current settings (unit-independent).
local function layoutPlate(f)
    local d = db()
    local w  = ns:PixelSnap(d.healthWidth, f)
    local hh = ns:PixelSnap(d.healthHeight, f)
    local ch = ns:PixelSnap(d.castHeight, f)

    f.health:ClearAllPoints()
    f.health:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.health:SetSize(w, hh)

    f.cast:ClearAllPoints()
    f.cast:SetPoint("TOP", f.health, "BOTTOM", 0, -(4 + ns:Pixel(f, d.borderSize)))
    f.cast:SetSize(w - (d.showCastIcon and (ch + 2) or 0), ch)

    f.castIcon:ClearAllPoints()
    f.castIcon:SetPoint("RIGHT", f.cast, "LEFT", -2, 0)
    f.castIcon:SetSize(ch, ch)

    -- borders track the bars (thin lines or a SharedMedia edge texture)
    applyBarBorders(f, d)
end

-- Static skin: textures, fonts, background, visibility (unit-independent).
local function skinPlate(f)
    local d = db()
    f.health:SetStatusBarTexture(lsmStatusbar(d.healthTexture))
    f.cast:SetStatusBarTexture(lsmStatusbar(d.castTexture))
    f.healthBG:SetAlpha(d.bgAlpha or 0.85)
    f.castBG:SetAlpha(d.bgAlpha or 0.85)

    if ns.UI and ns.UI.Font then
        ns.UI.Font(f.name, d.nameSize, "OUTLINE")
        ns.UI.Font(f.title, math.max(7, d.nameSize - 2), "OUTLINE")
        ns.UI.Font(f.healthText, d.fontSize, "OUTLINE")
        ns.UI.Font(f.castText, d.fontSize, "OUTLINE")
    end
    f.title:SetTextColor(0.72, 0.72, 0.78)
    f.name:SetShown(d.showName)
    f.healthText:SetShown(d.showHealthText)
    f.castIcon:SetShown(d.showCastbar and d.showCastIcon)
    f.castText:SetShown(d.showCastbar and d.showCastText)
end

local function healthTextString(d, cur, max)
    if d.healthTextMode == "none" or max <= 0 then return "" end
    if d.healthTextMode == "current" then
        return tostring(cur)
    elseif d.healthTextMode == "currentmax" then
        return format("%d/%d", cur, max)
    end
    return floor(cur / max * 100 + 0.5) .. "%"   -- percent (default)
end

-- Paint health value + colour + text from a data context.
local function paintHealth(f, ctx, cur, max)
    local d = db()
    if max <= 0 then max = 1 end
    f.health:SetMinMaxValues(0, max)
    f.health:SetValue(cur)
    local r, g, b = healthColor(d, ctx)
    f.health:SetStatusBarColor(r, g, b)
    if d.showHealthText then f.healthText:SetText(healthTextString(d, cur, max)) end
end

-- Absorb shield: a coloured segment on the bar from the current health point,
-- extending by the absorb amount (clamped to the bar's right edge).
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

-- Target highlight edges (accent) sit just outside the health bar.
local function paintTarget(f, isTarget)
    local d = db()
    if d.targetHighlight and isTarget then
        local c = d.colTarget
        layoutEdges(f.targetGlow, f.health, math.max(1, d.borderSize + 1),
            c.r, c.g, c.b, 1, d.borderSize)
    else
        if f.targetGlow then for _, t in pairs(f.targetGlow) do t:Hide() end end
    end
end

-- Focus highlight: a second ring, own colour, sitting just OUTSIDE the target
-- ring so both can show when the focus is also the target. The offset tracks the
-- target ring's outer edge so they never overlap at thick borders.
local function paintFocus(f, isFocus)
    local d = db()
    if d.focusHighlight and isFocus then
        local c = d.colFocus
        local thick = math.max(1, d.borderSize + 1)
        layoutEdges(f.focusGlow, f.health, thick,
            c.r, c.g, c.b, 1, d.borderSize + thick + 1)   -- just past the target ring
    else
        if f.focusGlow then for _, t in pairs(f.focusGlow) do t:Hide() end end
    end
end

-- =========================================================
-- Cast bar (real plates + preview share the visual; feeding differs)
-- =========================================================
local function paintCast(f, name, icon, notInterruptible)
    local d = db()
    local c = notInterruptible and d.colCastNoInterrupt or d.colCast
    f.cast:SetStatusBarColor(c.r, c.g, c.b)
    if d.showCastText then f.castText:SetText(name or "") end
    if d.showCastIcon then f.castIcon:SetTexture(icon) end
end

-- =========================================================
-- Auras (debuffs + buffs) — shared by real plates and the preview
-- =========================================================
local UnitAura = UnitAura     -- Compat.lua guarantees this exists on this client
local wipe = wipe

local _dbuf, _bbuf, _ccbuf = {}, {}, {}   -- scratch aura lists (single-threaded reuse)

-- Crowd-control spell IDs (TBC 2.5.x). There is no CROWD_CONTROL aura filter on
-- this client, so CC is recognised by spell id. Extendable — add ranks/spells.
local CC_SPELLS = {}
for _, id in ipairs({
    -- Mage
    118, 12824, 12825, 12826, 28271, 28272, 61305, 61721, 61780,   -- Polymorph (+ variants)
    122, 865, 6131, 10230, 27088,                                  -- Frost Nova (root)
    33395,                                                         -- Freeze (water elemental)
    -- Warlock
    5782, 6213, 6215, 6789, 17925, 17926,                          -- Fear / Death Coil
    5484, 17928,                                                   -- Howl of Terror
    6358,                                                          -- Seduction
    710, 18647,                                                    -- Banish
    -- Priest
    8122, 8124, 10888, 10890,                                      -- Psychic Scream
    9484, 9485, 10955,                                             -- Shackle Undead
    605,                                                           -- Mind Control
    -- Rogue
    6770, 2070, 11297,                                             -- Sap
    2094,                                                          -- Blind
    1776, 1777, 8629, 11285, 11286, 38764,                         -- Gouge
    408, 8643,                                                     -- Kidney Shot
    1833,                                                          -- Cheap Shot
    -- Druid
    33786,                                                         -- Cyclone
    2637, 18657, 18658,                                            -- Hibernate
    339, 1062, 5195, 5196, 9852, 9853, 26989,                      -- Entangling Roots
    5211, 6798, 8983,                                              -- Bash
    22570,                                                         -- Maim
    -- Hunter
    3355, 14308, 14309,                                            -- Freezing Trap
    19386, 24132, 24133, 27068,                                    -- Wyvern Sting
    19503,                                                         -- Scatter Shot
    24394,                                                         -- Intimidation
    1513, 14326, 14327,                                            -- Scare Beast
    -- Paladin
    853, 5588, 5589, 10308,                                        -- Hammer of Justice
    20066,                                                         -- Repentance
    10326,                                                         -- Turn Evil
    -- Warrior
    5246,                                                          -- Intimidating Shout
    -- Misc / pets
    1098, 11725, 11726,                                            -- Enslave Demon
}) do CC_SPELLS[id] = true end

-- Classes that can remove a Magic buff from an ENEMY (Spellsteal / Purge /
-- Dispel Magic / Devour Magic). `isStealable` from UnitAura flags such buffs.
local CAN_REMOVE_MAGIC = { MAGE = true, PRIEST = true, SHAMAN = true, WARLOCK = true }
local playerCanSteal = false   -- set in OnEnable from the player's class

local function fmtAuraTime(s)
    if s >= 3600 then return floor(s / 3600 + 0.5) .. "h"
    elseif s >= 60 then return floor(s / 60 + 0.5) .. "m"
    elseif s >= 10 then return tostring(floor(s))
    elseif s > 0  then return format("%.1f", s) end
    return ""
end

-- Fill `out` with up to `max` auras matching `filter` on `unit`.
-- mode: nil = all, "skipcc" = exclude CC spells, "cconly" = only CC spells.
local function collectAuras(unit, filter, max, out, mode)
    wipe(out)
    for i = 1, 40 do
        local name, icon, count, _, duration, expiration, _, stealable, _, spellId = UnitAura(unit, i, filter)
        if not name then break end
        local isCC = spellId and CC_SPELLS[spellId] or false
        local keep = true
        if mode == "skipcc" then keep = not isCC
        elseif mode == "cconly" then keep = isCC end
        if keep then
            out[#out + 1] = { icon = icon, count = count or 0,
                              duration = duration or 0, expiration = expiration or 0,
                              dispel = (stealable and playerCanSteal) and true or false }
            if #out >= max then break end
        end
    end
    return out
end

local function makeAuraIcon(container)
    local ic = CreateFrame("Frame", nil, container)
    ic.tex = ic:CreateTexture(nil, "ARTWORK")
    ic.tex:SetAllPoints(ic)                  -- fill the frame; border hugs the icon
    ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic.cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
    ic.cd:SetAllPoints(ic.tex)
    ic.cd:SetHideCountdownNumbers(true)      -- we draw our own timer
    ic.cd:SetDrawEdge(false)
    ic.border = makeEdges(ic, "OVERLAY")
    ic.dispelGlow = makeEdges(ic, "OVERLAY")   -- shown around stealable/dispellable buffs
    -- text overlay above the cooldown swipe so it never gets darkened
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

-- Draw `list` into `g`'s pooled icon row, centred on g.
local function renderAuraGroup(g, list, size, spacing, showTimer, showStacks, swipe)
    local d = db()
    local n = #list
    g.icons = g.icons or {}
    for i = #g.icons + 1, n do g.icons[i] = makeAuraIcon(g) end

    local bc = ns.COLORS.borderDark or { r = 0, g = 0, b = 0 }
    local bsz = d.borderSize or 0     -- 0 = borderless, consistent with the bars
    for i, ic in ipairs(g.icons) do
        local a = list[i]
        if a then
            ic:SetSize(size, size)
            ic:ClearAllPoints()
            ic:SetPoint("CENTER", g, "CENTER", (i - (n + 1) / 2) * (size + spacing), 0)
            ic.tex:SetTexture(a.icon)
            layoutEdges(ic.border, ic, bsz, bc.r, bc.g, bc.b, 1, 0)
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
            if ns.UI and ns.UI.Font then
                ns.UI.Font(ic.timer, d.auraTimerSize, "OUTLINE")
                ns.UI.Font(ic.count, d.auraStackSize, "OUTLINE")
            end
            ic.count:SetText((showStacks and a.count > 1) and a.count or "")
            ic.timer:SetText("")
            ic._exp, ic._showTimer = a.expiration, showTimer
            ic:Show()
        else
            ic:Hide()
        end
    end
    g._active = n
    if n > 0 and showTimer then
        g:SetScript("OnUpdate", function(self, elapsed)
            self._t = (self._t or 0) + elapsed
            if self._t < 0.1 then return end
            self._t = 0
            local now = GetTime()
            for i = 1, (self._active or 0) do
                local ic = self.icons[i]
                if ic._showTimer and ic._exp and ic._exp > 0 then
                    local rem = ic._exp - now
                    ic.timer:SetText(rem > 0 and fmtAuraTime(rem) or "")
                else
                    ic.timer:SetText("")
                end
            end
        end)
    else
        g:SetScript("OnUpdate", nil)
    end
end

-- Position + draw the aura rows (debuffs, buffs, CC) stacked upward from the
-- bar. Each list is nil/empty → that row is hidden and doesn't take space.
local function applyAuras(f, debuffList, buffList, ccList)
    local d = db()
    local y = (d.showName and (d.nameSize + 6) or 4)   -- running height above the bar
    local function place(group, list, enabled, size)
        if enabled and list and #list > 0 then
            group:ClearAllPoints()
            group:SetPoint("BOTTOM", f.health, "TOP", 0, y + size / 2)
            renderAuraGroup(group, list, size, d.auraSpacing,
                d.showAuraTimer, d.showAuraStacks, d.auraSwipe)
            y = y + size + d.auraSpacing
        else
            hideGroup(group)
        end
    end
    place(f.debuffGroup, debuffList, d.showDebuffs, d.debuffSize)
    place(f.buffGroup,   buffList,   d.showBuffs,   d.buffSize)
    place(f.ccGroup,     ccList,     d.showCC,      d.ccSize)   -- CC on top, prominent
end

-- Real plate: scan the unit and draw.
local function plateUpdateAuras(f)
    if not f.unit then return end
    if f._mode and f._mode ~= "full" then
        hideGroup(f.debuffGroup); hideGroup(f.buffGroup); hideGroup(f.ccGroup); return
    end
    local d = db()
    local dl, bl, cl
    if d.showDebuffs then
        -- exclude CC spells from the debuff row when the CC row is on (no dupes)
        collectAuras(f.unit, d.debuffsAll and "HARMFUL" or "HARMFUL|PLAYER", d.maxDebuffs, _dbuf,
            d.showCC and "skipcc" or nil)
        dl = _dbuf
    end
    if d.showBuffs then
        collectAuras(f.unit, "HELPFUL", d.maxBuffs, _bbuf)
        bl = _bbuf
    end
    if d.showCC then
        collectAuras(f.unit, "HARMFUL", d.maxCC, _ccbuf, "cconly")
        cl = _ccbuf
    end
    applyAuras(f, dl, bl, cl)
end

-- =========================================================
-- REAL PLATE ENGINE
-- =========================================================
ns.plates = ns.plates or {}          -- unit token -> our plate frame  (side table, taint-safe)
local platePool = {}                 -- released frames waiting for reuse
local hookedUFs = {}                 -- Blizzard UnitFrames we've hooked
local offParent                      -- offscreen parent for suppressed Blizzard bits

local function ensureOffParent()
    if offParent then return offParent end
    offParent = CreateFrame("Frame", nil, UIParent)
    offParent:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -500)
    offParent:SetSize(1, 1)
    offParent:Hide()
    return offParent
end

-- Suppress Blizzard's own nameplate UnitFrame so only ours shows.
local function hideBlizzard(nameplate)
    local uf = nameplate and nameplate.UnitFrame
    if not uf then return end
    uf:SetAlpha(0)
    if not hookedUFs[uf] then
        hookedUFs[uf] = true
        local locked = false
        hooksecurefunc(uf, "SetAlpha", function(self, a)
            if locked or a == 0 then return end
            local u = self.unit or (self.GetUnit and self:GetUnit())
            if not u or not ns.plates[u] then return end   -- no VCUI plate owns it now
            locked = true; self:SetAlpha(0); locked = false
        end)
    end
end

-- --- cast handling on a plate -----------------------------------------------
local function plateCastStop(f)
    f._casting = nil
    f.cast:Hide()
    f:SetScript("OnUpdate", nil)
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
    f.cast:SetMinMaxValues(f._castStart, f._castEnd)
    paintCast(f, name, icon, notInterruptible)
    f.cast:Show()
    f:SetScript("OnUpdate", function(self)
        if not self._casting then return end
        local now = GetTime()
        if now >= self._castEnd then return plateCastStop(self) end
        self.cast:SetValue(self._castChannel and (self._castStart + (self._castEnd - now)) or now)
    end)
end

-- --- plate mode (full / name-only / hidden) ----------------------------------
-- Enemies are always "full". Friendly players/NPCs follow their own setting.
local function plateModeFor(d, enemy, isPlayer)
    if enemy then return "full" end
    return isPlayer and d.friendlyPlayers or d.friendlyNPCs
end

local function applyPlateMode(f, mode)
    f._mode = mode
    local d = db()
    if mode == "hidden" then
        f.health:Hide(); f.cast:Hide(); f.name:Hide(); f.title:Hide()
        hideGroup(f.debuffGroup); hideGroup(f.buffGroup); hideGroup(f.ccGroup)
    elseif mode == "nameonly" then
        f.health:Hide(); f.cast:Hide()
        hideGroup(f.debuffGroup); hideGroup(f.buffGroup); hideGroup(f.ccGroup)
        f.name:ClearAllPoints()
        f.name:SetPoint("CENTER", f, "CENTER", 0, 0)
        f.name:Show()
        f.title:ClearAllPoints()
        f.title:SetPoint("TOP", f.name, "BOTTOM", 0, -1)   -- shown/hidden in refreshPlate
    else -- full
        f.health:Show()
        f.name:ClearAllPoints()
        f.name:SetPoint("BOTTOM", f.health, "TOP", 0, 3)
        f.name:SetShown(d.showName)
        f.title:Hide()
    end
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

-- --- raid target marker (skull, cross, …) ------------------------------------
local function positionRaidIcon(f)
    local d = db()
    local ic = f.raidIcon
    ic:SetSize(d.raidMarkerSize, d.raidMarkerSize)
    local anchor = (f._mode == "nameonly") and f.name or f.health
    ic:ClearAllPoints()
    local pos, ox, oy = d.raidMarkerPos, d.raidMarkerX or 0, d.raidMarkerY or 0
    if pos == "left" then
        ic:SetPoint("RIGHT", anchor, "LEFT", -4 + ox, oy)
    elseif pos == "right" then
        ic:SetPoint("LEFT", anchor, "RIGHT", 4 + ox, oy)
    else -- top
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

-- --- class-power pips (combo points) -----------------------------------------
local MAX_CP = MAX_COMBO_POINTS or 5

local function makePip(g)
    local p = g:CreateTexture(nil, "OVERLAY")
    p:SetColorTexture(1, 1, 1, 1)
    return p
end

-- Draw `count` filled pips (of MAX_CP) on the plate; hide the row at 0 / off /
-- non-full mode.
local function renderComboPips(f, count)
    local d = db()
    local g = f.cpGroup
    if not d.showClassPower or count <= 0 or (f._mode and f._mode ~= "full") then
        for _, p in ipairs(g.pips) do p:Hide() end
        g:Hide(); return
    end
    for i = #g.pips + 1, MAX_CP do g.pips[i] = makePip(g) end
    local size, sp = d.cpSize, d.cpSpacing
    local anchor = (d.showCastbar and f.cast) or f.health
    g:ClearAllPoints()
    g:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
    g:Show()
    local c = d.cpColor
    for i = 1, MAX_CP do
        local p = g.pips[i]
        p:SetSize(size, size)
        p:ClearAllPoints()
        p:SetPoint("CENTER", g, "CENTER", (i - (MAX_CP + 1) / 2) * (size + sp), 0)
        if i <= count then p:SetColorTexture(c.r, c.g, c.b, 1)
        else p:SetColorTexture(0.25, 0.25, 0.25, 0.6) end
        p:Show()
    end
    for i = MAX_CP + 1, #g.pips do g.pips[i]:Hide() end
end

local function getComboPoints()
    if not GetComboPoints then return 0 end
    local ok, cp = pcall(GetComboPoints, "player", "target")
    return (ok and cp) or 0
end

-- Combo points live on the current target → only that plate shows pips.
local function updateAllComboPips()
    local cp = getComboPoints()
    for _, f in pairs(ns.plates) do
        renderComboPips(f, (f.unit and UnitIsUnit(f.unit, "target")) and cp or 0)
    end
end

-- --- refresh a live plate from its unit --------------------------------------
local function refreshPlate(f)
    local unit = f.unit
    if not unit then return end
    local d = db()
    local isPlayer = UnitIsPlayer(unit)
    local enemy    = UnitCanAttack("player", unit) and true or false
    local mode     = plateModeFor(d, enemy, isPlayer)
    applyPlateMode(f, mode)
    updateRaidIcon(f)
    if mode == "hidden" then return end

    f.name:SetText(UnitName(unit) or "")
    applyNameColor(f, d, unit, enemy, isPlayer)

    -- Friendly NPC subname under the name (name-only mode only)
    if mode == "nameonly" and not enemy and not isPlayer and d.showNPCTitle and f._npcTitle then
        f.title:SetText(f._npcTitle); f.title:Show()
    else
        f.title:Hide()
    end
    if mode ~= "full" then return end

    local _, class = UnitClass(unit)
    local ctx = {
        player   = isPlayer,
        enemy    = enemy,
        class    = class,
        reaction = UnitReaction(unit, "player"),
        tapped   = UnitIsTapDenied(unit) and true or false,
        threat   = UnitAffectingCombat("player") and UnitThreatSituation("player", unit) or nil,
    }
    local hp, hpmax = UnitHealth(unit) or 0, UnitHealthMax(unit) or 1
    paintHealth(f, ctx, hp, hpmax)
    paintAbsorb(f, hp, hpmax, (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0)
    paintTarget(f, UnitIsUnit(unit, "target"))
    paintFocus(f, UnitIsUnit(unit, "focus"))
end

local function refreshAllPlates()
    for _, f in pairs(ns.plates) do refreshPlate(f) end
end

-- Re-apply static appearance to every live plate (after an options change).
local function restyleAllPlates()
    for _, f in pairs(ns.plates) do
        layoutPlate(f); skinPlate(f); refreshPlate(f); plateUpdateAuras(f)
    end
end

-- Non-target fade when you have a target selected.
local function updateFades()
    local d = db()
    local haveTarget = UnitExists("target")
    for _, f in pairs(ns.plates) do
        local a = 1
        if haveTarget and d.nonTargetAlpha < 1 and not (f.unit and UnitIsUnit(f.unit, "target")) then
            a = d.nonTargetAlpha
        end
        f:SetAlpha(a)
        paintTarget(f, f.unit and UnitIsUnit(f.unit, "target"))
    end
end

-- --- pooled plate lifecycle --------------------------------------------------
local onPlateRemoved   -- forward decl (onPlateAdded releases a stale frame via it)

local function acquirePlate()
    local f = table.remove(platePool)
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(150, 40)
    buildVisuals(f)
    -- per-plate unit events for health + cast
    f:SetScript("OnEvent", function(self, event)
        if not self.unit then return end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
            or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
            refreshPlate(self)
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            plateCastStart(self)
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
            or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
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
    if not unit or UnitIsUnit(unit, "player") then return end   -- skip personal plate
    local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return end

    -- Guard against a double-add for the same token (adoption loop + a live
    -- NAME_PLATE_UNIT_ADDED, or a missed REMOVED): release the stale frame
    -- first so exactly one plate ever owns a unit.
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

    f:RegisterUnitEvent("UNIT_HEALTH", unit)
    f:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
    f:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit)
    f:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    f:RegisterUnitEvent("UNIT_FACTION", unit)
    f:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
    f:RegisterUnitEvent("UNIT_AURA", unit)

    plateCastStart(f)      -- catch a cast already in progress
    refreshPlate(f)
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
    hideGroup(f.debuffGroup); hideGroup(f.buffGroup); hideGroup(f.ccGroup)
    f.raidIcon:Hide()
    f.absorb:Hide()
    f.title:Hide()
    paintFocus(f, false)
    renderComboPips(f, 0)
    f.unit = nil
    f._npcTitle = nil
    f:Hide()
    f:SetParent(UIParent)
    f:ClearAllPoints()
    table.insert(platePool, f)
end

local function onTargetChanged()
    updateFades()
    updateAllComboPips()   -- combo points follow the new target
end

-- Raid markers change without any unit event → refresh every plate's icon.
local function onRaidTargetUpdate()
    for _, f in pairs(ns.plates) do updateRaidIcon(f) end
end

-- Focus changed → repaint every plate's focus ring (only full-mode plates).
local function updateAllFocus()
    for _, f in pairs(ns.plates) do
        local on = f.unit and (f._mode == nil or f._mode == "full") and UnitIsUnit(f.unit, "focus")
        paintFocus(f, on)
    end
end

-- Combo points changed → repaint the target plate's pips. On 2.5.x there is no
-- dedicated combo-point event; combo gain/spend always coincides with a player
-- power (energy) change, so we ride UNIT_POWER_UPDATE filtered to the player.
local function onComboUpdate(_, unit)
    if unit ~= "player" then return end
    updateAllComboPips()
end

-- =========================================================
-- LIVE PREVIEW (Options screen)
-- A cosmetic plate built from the same helpers, updated in place.
-- =========================================================
local previewFrame

local PREVIEW_CTX = {
    player = false, enemy = true, class = "WARRIOR",
    reaction = 2, tapped = false, threat = 0,
}

local function buildPreview(parent)
    if previewFrame then
        previewFrame:SetParent(parent)
        previewFrame:ClearAllPoints()
        previewFrame:SetPoint("TOP", parent, "TOP", 0, -10)
        previewFrame:Show()
        previewFrame:Update()
        return previewFrame
    end

    local host = CreateFrame("Frame", "VCUINameplatePreview", parent)
    host:SetSize(420, 210)   -- tall enough for the full aura stack + cast + pips
    -- panel backing so the preview reads as its own card
    local bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(host)
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.9)
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

    -- The actual plate, sitting low in the box so the upward aura stack (debuffs
    -- + buffs + CC + marker) has room and the whole thing stays centred.
    local plate = CreateFrame("Frame", nil, host)
    plate:SetSize(160, 46)
    plate:SetPoint("CENTER", host, "CENTER", 0, -38)
    buildVisuals(plate)
    plate.unit = nil          -- preview: no real unit
    plate.cast:Show()

    function plate:Update()
        -- Render at UIParent's effective scale so 1px matches a real nameplate.
        -- Divide by the PARENT's effective scale (not our own — our own already
        -- includes our SetScale, which would make this oscillate).
        local pes = UIParent:GetEffectiveScale()
        local parentES = self:GetParent():GetEffectiveScale()
        if parentES > 0 then self:SetScale(pes / parentES) end
        layoutPlate(self); skinPlate(self)
        local d = db()
        local enemy = PREVIEW_CTX.enemy
        -- friendly preview follows the friendly-players setting; enemies are full
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

        -- sample raid marker (skull) — visible in name-only preview too
        if d.showRaidMarker and mode ~= "hidden" then
            setRaidIcon(self.raidIcon, 8)
            positionRaidIcon(self)
            self.raidIcon:Show()
        else
            self.raidIcon:Hide()
        end
        if mode ~= "full" then return end

        paintHealth(self, PREVIEW_CTX, 68, 100)
        paintAbsorb(self, 68, 100, 20)   -- sample 20% absorb shield
        if d.showCastbar then
            self.cast:SetMinMaxValues(0, 1); self.cast:SetValue(0.6)
            paintCast(self, L["Fireball"], "Interface\\Icons\\Spell_Fire_FlameBolt", false)
            self.cast:Show()
        else
            self.cast:Hide()
        end
        paintTarget(self, true)     -- preview always shows the target highlight
        paintFocus(self, true)      -- and the focus ring (for colour feedback)

        -- sample auras (fresh expirations each paint so the timers stay lively)
        local now = GetTime()
        local dl = {
            { icon = "Interface\\Icons\\Spell_Fire_Immolation",       count = 0, duration = 12, expiration = now + 8 },
            { icon = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", count = 3, duration = 18, expiration = now + 14 },
        }
        local bl = {
            { icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",  count = 0, duration = 30, expiration = now + 22, dispel = true },
        }
        local cl = {
            { icon = "Interface\\Icons\\Spell_Nature_Polymorph",      count = 0, duration = 10, expiration = now + 7 },
        }
        applyAuras(self, d.showDebuffs and dl or nil, d.showBuffs and bl or nil, d.showCC and cl or nil)

        renderComboPips(self, 3)   -- sample 3 / 5 combo points
    end

    host.Update = function() plate:Update() end
    previewFrame = host
    host:SetPoint("TOP", parent, "TOP", 0, -10)
    plate:Update()
    return host
end

-- Rebuild the open options page → the custom item's build() re-runs → preview
-- repaints. Used by every setter so the preview tracks live.
local function refreshPage()
    if ns.UI and ns.UI.IsModuleActive and ns.UI:IsModuleActive("nameplates") then
        ns.UI:BuildOptionsPage("nameplates", ns.UI.currentTab)
    end
end

-- Drive Blizzard's friendly-nameplate CVar from our toggle (out of combat only;
-- nameplate CVars are combat-locked). Applied again on the next OnEnable/toggle.
local function applyFriendlyCVar()
    if InCombatLockdown and InCombatLockdown() then return end
    pcall(SetCVar, "nameplateShowFriends", db().friendlyShow and "1" or "0")
end

-- After a settings change: restyle live plates AND repaint the preview.
local function applyAndRefresh()
    if mod.active then restyleAllPlates(); updateFades(); updateAllComboPips() end
    if previewFrame then previewFrame:Update() end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    if mod.db.healthTexture == nil then mod.db.healthTexture = DEFAULT_TEXTURE end
    local _, cls = UnitClass("player")
    playerCanSteal = CAN_REMOVE_MAGIC[cls] or false
    ensureOffParent()
    -- Mirror the toggle to Blizzard's CURRENT setting instead of forcing it —
    -- we only write the CVar when the user flips the option themselves.
    local cur = GetCVar and GetCVar("nameplateShowFriends")
    if cur ~= nil then mod.db.friendlyShow = (cur == "1" or cur == 1) end
    ns:RegisterEvent("NAME_PLATE_UNIT_ADDED", onPlateAdded)
    ns:RegisterEvent("NAME_PLATE_UNIT_REMOVED", onPlateRemoved)
    ns:RegisterEvent("PLAYER_TARGET_CHANGED", onTargetChanged)
    ns:RegisterEvent("PLAYER_FOCUS_CHANGED", updateAllFocus)
    ns:RegisterEvent("RAID_TARGET_UPDATE", onRaidTargetUpdate)
    ns:RegisterEvent("UNIT_POWER_UPDATE", onComboUpdate)
    -- adopt any plates already on screen (e.g. /reload in combat)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, p in ipairs(C_NamePlate.GetNamePlates()) do
            local u = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
            if u then onPlateAdded(nil, u) end
        end
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("NAME_PLATE_UNIT_ADDED", onPlateAdded)
    ns:UnregisterEvent("NAME_PLATE_UNIT_REMOVED", onPlateRemoved)
    ns:UnregisterEvent("PLAYER_TARGET_CHANGED", onTargetChanged)
    ns:UnregisterEvent("PLAYER_FOCUS_CHANGED", updateAllFocus)
    ns:UnregisterEvent("RAID_TARGET_UPDATE", onRaidTargetUpdate)
    ns:UnregisterEvent("UNIT_POWER_UPDATE", onComboUpdate)
    for unit in pairs(ns.plates) do onPlateRemoved(nil, unit) end
    -- restore Blizzard plates that were suppressed
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, p in ipairs(C_NamePlate.GetNamePlates()) do
            if p.UnitFrame then p.UnitFrame:SetAlpha(1) end
        end
    end
end

-- =========================================================
-- Options
-- =========================================================
local function textModeValues()
    return {
        { value = "none",       text = L["No text"] },
        { value = "percent",    text = L["Percent"] },
        { value = "current",    text = L["Current value"] },
        { value = "currentmax", text = L["Current / Max"] },
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

function mod:GetOptions()
    local SLW = 180
    return {
        { type = "desc",
          text = L["|cffaaaaaaCustom nameplates for enemies and NPCs. Configure below — the live preview updates as you change each option.|r"] },

        -- Live preview + which reaction to preview
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

        -- ---- Health bar ---------------------------------------------------
        { type = "section", title = L["Health Bar"], collapsed = false, items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Width"], min = 60, max = 240, step = 2, width = SLW,
                  get = function() return mod.db.healthWidth end,
                  set = function(_, v) mod.db.healthWidth = v; applyAndRefresh() end },
                { type = "slider", label = L["Height"], min = 4, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.healthHeight end,
                  set = function(_, v) mod.db.healthHeight = v; applyAndRefresh() end },
            } },
            -- dropdowns + colours auto-arrange into even 2-column rows
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
            -- border thickness: solo slider, full width (never mixed with a dropdown)
            { type = "slider", label = L["Border thickness (px)"], min = 0, max = 12, step = 1,
              get = function() return mod.db.borderSize end,
              set = function(_, v) mod.db.borderSize = v; applyAndRefresh() end },
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
        } },

        -- ---- Text ---------------------------------------------------------
        { type = "section", title = L["Text"], collapsed = false, items = {
            { type = "checkbox", label = L["Show name"],
              get = function() return mod.db.showName end,
              set = function(_, v) mod.db.showName = v; refreshPage(); applyAndRefresh() end },
            { type = "checkbox", label = L["Show health text"],
              get = function() return mod.db.showHealthText end,
              set = function(_, v) mod.db.showHealthText = v; refreshPage(); applyAndRefresh() end },
            { type = "dropdown", label = L["Health text"], width = 300, values = textModeValues(),
              get = function() return mod.db.healthTextMode end,
              set = function(_, v) mod.db.healthTextMode = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Name size"], min = 6, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.nameSize end,
                  set = function(_, v) mod.db.nameSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Text size"], min = 6, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.fontSize end,
                  set = function(_, v) mod.db.fontSize = v; applyAndRefresh() end },
            } },
        } },

        -- ---- Colours ------------------------------------------------------
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

        -- ---- Cast bar -----------------------------------------------------
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
            { type = "slider", label = L["Cast bar height"], min = 4, max = 30, step = 1,
              get = function() return mod.db.castHeight end,
              set = function(_, v) mod.db.castHeight = v; applyAndRefresh() end },
        } },

        -- ---- Target & threat ---------------------------------------------
        { type = "section", title = L["Target & Threat"], collapsed = false, items = {
            { type = "checkbox", label = L["Highlight your target"],
              get = function() return mod.db.targetHighlight end,
              set = function(_, v) mod.db.targetHighlight = v; applyAndRefresh() end },
            { type = "color", label = L["Target highlight colour"], width = 220,
              get = function() return mod.db.colTarget end,
              set = function(r, g, b) mod.db.colTarget = { r = r, g = g, b = b }; applyAndRefresh() end },
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

        -- ---- Auras --------------------------------------------------------
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
            { type = "slider", label = L["Icon spacing"], min = 0, max = 8, step = 1, width = SLW,
              get = function() return mod.db.auraSpacing end,
              set = function(_, v) mod.db.auraSpacing = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Cooldown swipe"],
              get = function() return mod.db.auraSwipe end,
              set = function(_, v) mod.db.auraSwipe = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Glow stealable / dispellable buffs"],
              tooltip = L["Glows enemy buffs you can remove (Spellsteal / Purge / Dispel Magic). Only for classes that can."],
              get = function() return mod.db.showDispelGlow end,
              set = function(_, v) mod.db.showDispelGlow = v; applyAndRefresh() end },
            { type = "color", label = L["Dispel glow colour"], width = 220,
              get = function() return mod.db.colDispel end,
              set = function(r, g, b) mod.db.colDispel = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "checkbox", label = L["Show timer text"],
              get = function() return mod.db.showAuraTimer end,
              set = function(_, v) mod.db.showAuraTimer = v; applyAndRefresh() end },
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
        } },

        -- ---- Friendly plates ---------------------------------------------
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

        -- ---- Raid marker -------------------------------------------------
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

        -- ---- Class power (combo points) ----------------------------------
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
        } },
    }
end
