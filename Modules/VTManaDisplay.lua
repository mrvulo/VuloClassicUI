-- =========================================================
-- VuloClassicUI / Modules / VTManaDisplay (Class Specific)
-- Container module for class-specific tools, organized by class tabs.
-- Currently: Priest → Shadow → Vampiric Touch mana tracker
--   (tracks 5% of shadow damage per tick given back to the group as mana).
-- Built to be extended: add a class to CLASS_TABS to give it its own tab.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("vtmanadisplay", {
    name        = "Class Specific",
    group       = "QoL",
    description = "Class-specific tools, grouped by class. Currently includes the Priest Vampiric Touch mana tracker (Shadow).",
    defaults    = {
        enabled    = true,
        showFrame  = true,
        showInChat = false,
        x          = 0,
        y          = -220,
        fontSize   = 14,
        unlocked   = false,
        -- DoT tracker (Priest → Shadow, Warlock → Affliction/Destruction)
        dots = {
            layout      = "bars",   -- "bars" | "icons"
            -- Priest
            showSWP     = true,
            showVT      = true,
            showDP      = false,  -- Undead only; off by default
            -- Warlock
            showCorruption = true,
            showCoA        = true,
            showUA         = true,
            showSiphon     = true,
            showImmolate   = true,
            showCoDoom     = false,  -- long/niche; off by default
            warnSeconds = 3,
            colorText   = true,
            showGain    = true,   -- "+12%" recast-gain readout next to the timer
            barWidth    = 150,
            barHeight   = 18,
            iconSize    = 32,
            spacing     = 3,
            fontSize    = 12,
            x           = 250,
            y           = 0,
            unlocked    = false,
        },
    },
})

-- One tab per class. Priest first (it has tools), the rest alphabetical.
-- Classes without tools show a placeholder; add their options in GetOptions
-- as more class tools are built.
mod.tabs = {
    { id = "priest",  label = "Priest"  },
    { id = "druid",   label = "Druid"   },
    { id = "hunter",  label = "Hunter"  },
    { id = "mage",    label = "Mage"    },
    { id = "paladin", label = "Paladin" },
    { id = "rogue",   label = "Rogue"   },
    { id = "shaman",  label = "Shaman"  },
    { id = "warlock", label = "Warlock" },
    { id = "warrior", label = "Warrior" },
}

-- Pluggable per-class tools. Other files (e.g. ShamanTotems) register here,
-- keyed by class token ("SHAMAN"). Each tool: { onEnable, onDisable, getOptions }.
mod.classTools = {}
function mod:RegisterClassTool(classToken, def)
    self.classTools[classToken] = def
end

-- Per-class DoT sets live in their own file (Modules/Classes/<Class>.lua) and
-- register here at load. The DoT *engine* (rendering, snapshots, options) is
-- shared below — class files only contribute data, so nothing is duplicated.
local DOT_SETS     = {}   -- classToken -> { dot defs }
local DOT_SET_META = {}   -- classToken -> { desc = "..." }
local dotDefs      = {}   -- the active set, chosen by class in OnEnable

function mod:RegisterDotSet(classToken, dots, meta)
    DOT_SETS[classToken] = dots
    if meta then DOT_SET_META[classToken] = meta end
end

local VT_SPELL_ID_BASE = 34914  -- Vampiric Touch base (TBC)
local SHADOW_SCHOOL    = 32

-- =========================================================
-- Runtime state
-- =========================================================
local playerGUID
local vtSpellName          -- localized name, filters all ranks
local vtTargets  = {}      -- destGUID -> true (active VTs)
local totalMana  = 0
local lastTick   = 0
local cFrame              -- display frame

-- =========================================================
-- Helpers
-- =========================================================
local function updateFrame()
    if not cFrame or not cFrame.text then return end
    cFrame.text:SetText(string.format(L["|cff9b6cffVT Mana:|r %d"], math.floor(totalMana)))
end

local function resetCombat()
    totalMana = 0
    lastTick  = 0
    updateFrame()
end

local function reportChat()
    if not mod.db.showInChat then return end
    if totalMana <= 0 then return end
    ns:Print(L["Vampiric Touch: %d mana given to the group."], math.floor(totalMana))
end

local function refreshSpell()
    vtSpellName = GetSpellInfo(VT_SPELL_ID_BASE)
end

-- =========================================================
-- Combat log handler
-- Anniversary uses the modern backend — args via CombatLogGetCurrentEventInfo().
-- Lookup table instead of multiple string compares per event (hot-path filter).
-- =========================================================
local TRACKED_EVENTS = {
    SPELL_AURA_APPLIED    = "apply",
    SPELL_AURA_REMOVED    = "remove",
    SPELL_DAMAGE          = "damage",
    SPELL_PERIODIC_DAMAGE = "damage",
}

-- NOTE: combat-log handling lives in onCombatLog further down — ONE shared
-- handler for VT mana AND the DoT snapshots. The combat log is the hottest
-- event there is; two separate handlers would destructure every log line
-- twice (dispatch + CombatLogGetCurrentEventInfo each).

-- =========================================================
-- Frame + mover
-- =========================================================
local function createFrame()
    if cFrame then return cFrame end

    cFrame = CreateFrame("Frame", "VCUI_VTManaFrame", UIParent)
    cFrame:SetSize(180, 22)
    cFrame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)
    cFrame:SetFrameStrata("LOW")
    cFrame:SetMovable(true)
    cFrame:SetClampedToScreen(false)

    cFrame.text = cFrame:CreateFontString(nil, "OVERLAY")
    cFrame.text:SetFont("Fonts\\FRIZQT__.TTF", mod.db.fontSize, "OUTLINE")
    cFrame.text:SetPoint("CENTER", cFrame, "CENTER", 0, 0)
    cFrame.text:SetTextColor(1, 1, 1, 1)
    cFrame.text:SetText(L["|cff9b6cffVT Mana:|r 0"])

    cFrame.mover = ns:CreateMover(cFrame, {
        label  = L["|cffffffffVT MANA|r"],
        db     = mod.db,
        width  = 200,
        height = 40,
        onMove = function(x, y)
            ns:Print(string.format(L["VT mana frame: x=%.0f, y=%.0f"], x, y))
        end,
    })

    return cFrame
end

local function setUnlocked(state)
    mod.db.unlocked = state
    if not cFrame then createFrame() end
    if state then
        cFrame:Show()
        cFrame.mover:Show()
        ns:Print(L["VT mana mover active. |cff9b6cffDrag|r or |cff9b6cffarrow keys|r (SHIFT = 5px)."])
    else
        cFrame.mover:Hide()
        if not mod.db.showFrame then cFrame:Hide() end
        ns:Print(L["VT mana mover disabled."])
    end
end

-- =========================================================
-- Shadow DoT tracker (Priest → Shadow)
-- Tracks YOUR Shadow Word: Pain / Vampiric Touch / Devouring Plague
-- on the current target, as bars or icons, with a refresh warning.
-- Reads UnitAura duration/expiration (caster = player), matched by name
-- so every rank is covered. No Mastery/Pandemic API exists in 2.5.5.
-- =========================================================
-- DoT defs (base / coef / school / color / toggle) live in the per-class
-- files and arrive via mod:RegisterDotSet. base = approx base damage over the
-- full duration; coef = spell-power coefficient over the full duration;
-- school = GetSpellBonusDamage index (6 = Shadow, 3 = Fire). Exact values
-- barely matter — the "is a recast stronger now?" check is relative (each DoT
-- vs its OWN snapshot), so base/coef only weight spell power against % buffs.
-- DOT_SETS / dotDefs are declared up top next to the registration API.

-- Caster-side TEMPORARY % spell-damage buffs that snapshot onto a DoT at cast.
-- Target debuffs (Shadow Weaving / Misery) are dynamic -> NOT here. Constant
-- modifiers (Shadowform / Darkness) cancel out in the comparison -> also skip.
-- spellId -> multiplier. Extend as needed.
local DOT_DMG_BUFFS = {
    [34457] = 1.03, [34459] = 1.03, [34460] = 1.03,  -- Ferocious Inspiration (+3%)
}
local DOT_WARN_COLOR = { 1.0, 0.25, 0.25 }
local DOT_BAR_TEX    = "Interface\\Buttons\\WHITE8X8"
local DOT_SPARK_TEX  = "Interface\\CastingBar\\UI-CastingBar-Spark"
local DOT_FONT       = "Fonts\\FRIZQT__.TTF"

local dotsContainer
local dotsRows     = {}
local dotsThrottle = 0

local DOT_GREEN     = { 0.20, 1.00, 0.20 }
local dotsSnapshots = {}  -- destGUID..dotKey -> damage-estimate snapshot at cast

-- Spell power right now for a given school (6 = Shadow, 3 = Fire).
local function dotsCurrentPower(school)
    return (GetSpellBonusDamage and GetSpellBonusDamage(school or 6)) or 0
end

-- Product of active caster-side % spell-damage buffs (1.0 if none).
-- Cached: scanning 40 player buffs 10x/second from OnUpdate is wasted work —
-- the value only changes on UNIT_AURA("player"), so recompute it there.
local dotsMultCache = 1

local function dotsDamageMult()
    return dotsMultCache
end

local function dotsRecomputeMult()
    local m = 1
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
        if not name then break end
        local b = spellId and DOT_DMG_BUFFS[spellId]
        if b then m = m * b end
    end
    dotsMultCache = m
end

local function dotsOnUnitAura(_, unit)
    if unit == "player" then dotsRecomputeMult() end
end

-- Estimated DoT damage = (base + spellpower[school] * coef) * % damage mult.
-- AffDots-style: snapshot this at cast, then compare to the live value.
-- Spell power is read per the DoT's own school (Shadow vs Fire).
local function dotsFactor(dot, mult)
    return (dot.base + dotsCurrentPower(dot.school) * dot.coef) * mult
end

-- How much would a recast on the current target gain (in %) vs. the value the
-- running DoT snapshotted at cast? TBC DoTs freeze spell power AND caster
-- % buffs on cast, so with a spell-power proc up a fresh cast deals more.
-- Returns a percentage (+14 = recast hits 14% harder, -8 = the running DoT
-- is 8% stronger than a fresh cast would be), or nil without a snapshot.
local function dotsGain(dot, mult)
    local guid = UnitGUID("target")
    if not guid then return nil end
    local snap = dotsSnapshots[guid .. dot.key]
    if not snap or snap <= 0 then return nil end
    return (dotsFactor(dot, mult) / snap - 1) * 100
end

-- ONE combat-log handler for both trackers. VT mana: count shadow damage on
-- VT'd targets (5% -> mana). DoT snapshots: record the spell-power estimate
-- when a tracked DoT is (re)applied, drop it when it falls off — keeps
-- dotsSnapshots from growing unbounded and avoids stale recycled GUIDs.
local function onCombatLog()
    if not playerGUID then
        playerGUID = UnitGUID("player")
        if not playerGUID then return end
    end

    -- Cheap pre-filter: read only subevent + source, bail before the full
    -- destructure for anything that isn't ours.
    local _, subEvent, _, sourceGUID = CombatLogGetCurrentEventInfo()
    if sourceGUID ~= playerGUID then return end

    local kind   = vtSpellName and TRACKED_EVENTS[subEvent]
    local apply  = (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH")
    local remove = (subEvent == "SPELL_AURA_REMOVED")
    if not kind and not apply and not remove then return end

    local _, _, _, _, _, _, _, destGUID, _, _, _,
          _, spellName, _, amount, _, school = CombatLogGetCurrentEventInfo()

    -- VT mana tracking
    if kind == "apply" then
        if spellName == vtSpellName then
            vtTargets[destGUID] = true
            lastTick = 0
        end
    elseif kind == "remove" then
        if spellName == vtSpellName then
            vtTargets[destGUID] = nil
            totalMana = totalMana + lastTick
            updateFrame()
        end
    elseif kind then -- "damage"
        if vtTargets[destGUID] and amount and amount > 0 and school == SHADOW_SCHOOL then
            local mana = amount * 0.05
            totalMana = totalMana + mana
            lastTick  = mana
            updateFrame()
        end
    end

    -- DoT snapshots
    if apply or remove then
        for _, dot in ipairs(dotDefs) do
            if dot.name and spellName == dot.name then
                dotsSnapshots[destGUID .. dot.key] =
                    apply and dotsFactor(dot, dotsDamageMult()) or nil
                return
            end
        end
    end
end

local dotsWanted  = {}   -- spell name -> true (the DoTs we track)
local dotsAuraDur = {}   -- spell name -> duration   (refreshed per scan)
local dotsAuraExp = {}   -- spell name -> expiration

local function dotsRefreshSpellData()
    for k in pairs(dotsWanted) do dotsWanted[k] = nil end
    for _, dot in ipairs(dotDefs) do
        local n, _, icon = GetSpellInfo(dot.id)
        dot.name = n
        dot.icon = icon
        if n then dotsWanted[n] = true end
        if dotsRows[dot.key] and icon then
            dotsRows[dot.key].icon:SetTexture(icon)
        end
    end
end

-- ONE pass over the target's debuffs for ALL tracked DoTs (instead of one
-- 40-slot scan per row per tick). Results land in the reused name-keyed
-- tables — no per-tick table allocations, no GC churn.
local function dotsScanTarget()
    for k in pairs(dotsAuraDur) do dotsAuraDur[k] = nil end
    for k in pairs(dotsAuraExp) do dotsAuraExp[k] = nil end
    for i = 1, 40 do
        local aName, _, _, _, dur, exp, source = UnitAura("target", i, "HARMFUL")
        if not aName then break end
        if source == "player" and dotsWanted[aName] then
            dotsAuraDur[aName] = dur
            dotsAuraExp[aName] = exp
        end
    end
end

local function dotsCreateRow(dot)
    local row = CreateFrame("Frame", nil, dotsContainer)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if dot.icon then row.icon:SetTexture(dot.icon) end

    row.cd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cd:SetDrawEdge(true)
    if row.cd.SetHideCountdownNumbers then
        row.cd:SetHideCountdownNumbers(true)  -- we draw our own timer text
    end
    row.cd:Hide()

    row.glow = row:CreateTexture(nil, "BACKGROUND")
    row.glow:SetTexture(DOT_BAR_TEX)
    row.glow:Hide()

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetTexture(DOT_BAR_TEX)
    row.bg:SetVertexColor(0.08, 0.08, 0.08, 0.85)

    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetTexture(DOT_BAR_TEX)
    row.fill:SetVertexColor(dot.color[1], dot.color[2], dot.color[3], 0.9)

    row.spark = row:CreateTexture(nil, "OVERLAY")
    row.spark:SetTexture(DOT_SPARK_TEX)
    row.spark:SetBlendMode("ADD")
    row.spark:SetWidth(16)

    row.time = row:CreateFontString(nil, "OVERLAY")
    row.time:SetFont(DOT_FONT, mod.db.dots.fontSize, "OUTLINE")

    -- Recast-gain readout ("+12%"): how much harder a fresh cast would hit
    row.pct = row:CreateFontString(nil, "OVERLAY")
    row.pct:SetFont(DOT_FONT, mod.db.dots.fontSize, "OUTLINE")
    row.pct:Hide()

    row.dot = dot
    return row
end

local function dotsApplyLayout()
    if not dotsContainer then return end
    local db = mod.db.dots

    local active = {}
    for _, dot in ipairs(dotDefs) do
        if db[dot.toggle] then active[#active + 1] = dot end
    end

    for _, row in pairs(dotsRows) do row:Hide() end

    if #active == 0 then
        dotsContainer:SetSize(1, 1)
        return
    end

    if db.layout == "icons" then
        local s = db.iconSize
        for i, dot in ipairs(active) do
            local row = dotsRows[dot.key]
            row:ClearAllPoints()
            row:SetSize(s, s)
            row:SetPoint("LEFT", dotsContainer, "LEFT", (i - 1) * (s + db.spacing), 0)

            row.icon:ClearAllPoints(); row.icon:SetAllPoints(row); row.icon:Show()
            row.cd:ClearAllPoints(); row.cd:SetAllPoints(row)
            row.glow:ClearAllPoints()
            row.glow:SetPoint("TOPLEFT", row, "TOPLEFT", -2, 2)
            row.glow:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 2, -2)
            row.bg:Hide(); row.fill:Hide(); row.spark:Hide(); row.glow:Hide()

            row.time:ClearAllPoints()
            row.time:SetPoint("BOTTOM", row, "BOTTOM", 0, 1)
            row.time:SetFont(DOT_FONT, db.fontSize, "OUTLINE")

            row.pct:ClearAllPoints()
            row.pct:SetPoint("BOTTOM", row, "TOP", 0, 2)
            row.pct:SetFont(DOT_FONT, db.fontSize - 1, "OUTLINE")

            row:Show()
        end
        dotsContainer:SetSize(#active * s + (#active - 1) * db.spacing, s)
    else -- bars
        local h, w = db.barHeight, db.barWidth
        local iconW = h
        for i, dot in ipairs(active) do
            local row = dotsRows[dot.key]
            row:ClearAllPoints()
            row:SetSize(iconW + w, h)
            row:SetPoint("TOPLEFT", dotsContainer, "TOPLEFT", 0, -(i - 1) * (h + db.spacing))

            row.icon:ClearAllPoints()
            row.icon:SetSize(h, h)
            row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.icon:Show()

            row.cd:Hide()
            row.glow:Hide()

            row.bg:ClearAllPoints()
            row.bg:SetPoint("TOPLEFT", row, "TOPLEFT", iconW + 1, 0)
            row.bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            row.bg:Show()

            row.fill:ClearAllPoints()
            row.fill:SetPoint("LEFT", row, "LEFT", iconW + 1, 0)
            row.fill:SetSize(w, h)
            row.fill:Show()

            row.spark:SetHeight(h + 6)

            row.time:ClearAllPoints()
            row.time:SetPoint("RIGHT", row, "RIGHT", -3, 0)
            row.time:SetFont(DOT_FONT, db.fontSize, "OUTLINE")

            row.pct:ClearAllPoints()
            row.pct:SetPoint("LEFT", row, "LEFT", iconW + 4, 0)
            row.pct:SetFont(DOT_FONT, db.fontSize - 1, "OUTLINE")

            row:Show()
        end
        dotsContainer:SetSize(iconW + w, #active * h + (#active - 1) * db.spacing)
    end
end

local function dotsUpdateRow(row, hasTarget, preview, mult)
    local db  = mod.db.dots
    local dot = row.dot
    local dur, exp

    if preview then
        dur = 10
        exp = GetTime() + (dot.key == "vt" and 7 or 10)
    elseif hasTarget and dot.name then
        dur, exp = dotsAuraDur[dot.name], dotsAuraExp[dot.name]
    end

    if dur and exp and dur > 0 then
        local remaining = exp - GetTime()
        if remaining < 0 then remaining = 0 end
        local frac = remaining / dur
        if frac > 1 then frac = 1 end
        local warn = remaining <= db.warnSeconds
        local gain
        if preview then
            gain = 12  -- sample value while positioning
        elseif hasTarget then
            gain = dotsGain(dot, mult)
        end
        local better = (gain and gain > 0.5) and true or false

        if remaining < 10 then
            row.time:SetText(string.format("%.1f", remaining))
        else
            row.time:SetText(string.format("%d", remaining + 0.5))
        end
        row.time:Show()
        if db.colorText and better then
            row.time:SetTextColor(DOT_GREEN[1], DOT_GREEN[2], DOT_GREEN[3])
        elseif db.colorText and warn then
            row.time:SetTextColor(DOT_WARN_COLOR[1], DOT_WARN_COLOR[2], DOT_WARN_COLOR[3])
        else
            row.time:SetTextColor(1, 1, 1)
        end

        -- "+12%" = a fresh cast right now hits 12% harder than the running DoT
        -- (spell-power/damage procs vs. its snapshot). Negative = keep the DoT.
        if db.showGain and gain and math.abs(gain) >= 1 then
            row.pct:SetText(string.format("%+.0f%%", gain))
            if gain > 0 then
                row.pct:SetTextColor(DOT_GREEN[1], DOT_GREEN[2], DOT_GREEN[3])
            else
                row.pct:SetTextColor(0.62, 0.62, 0.68)
            end
            row.pct:Show()
        else
            row.pct:Hide()
        end

        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 1, 1)
        if db.layout == "icons" then
            row.cd:SetCooldown(exp - dur, dur)
            row.cd:Show()
            if better then
                row.glow:SetVertexColor(DOT_GREEN[1], DOT_GREEN[2], DOT_GREEN[3], 1)
                row.glow:Show()
            elseif warn then
                row.glow:SetVertexColor(DOT_WARN_COLOR[1], DOT_WARN_COLOR[2], DOT_WARN_COLOR[3], 1)
                row.glow:Show()
            else
                row.glow:Hide()
            end
        else
            local fw = db.barWidth * frac
            if fw < 1 then fw = 1 end
            row.fill:SetWidth(fw)
            if better then
                row.fill:SetVertexColor(DOT_GREEN[1], DOT_GREEN[2], DOT_GREEN[3], 0.9)
            elseif warn then
                row.fill:SetVertexColor(DOT_WARN_COLOR[1], DOT_WARN_COLOR[2], DOT_WARN_COLOR[3], 0.9)
            else
                row.fill:SetVertexColor(dot.color[1], dot.color[2], dot.color[3], 0.9)
            end
            row.fill:Show()
            row.spark:ClearAllPoints()
            row.spark:SetPoint("CENTER", row.fill, "RIGHT", 0, 0)
            if frac > 0.02 and frac < 0.99 then row.spark:Show() else row.spark:Hide() end
        end
    else
        row.time:SetText("")
        row.time:Hide()
        row.pct:Hide()
        row.icon:SetDesaturated(true)
        row.icon:SetVertexColor(0.5, 0.5, 0.5)
        row.glow:Hide()
        if db.layout == "icons" then
            row.cd:Hide()
        else
            row.fill:Hide()
            row.spark:Hide()
        end
    end
end

local function dotsTargetValid()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDead("target")
end

local function dotsRefresh()
    if not dotsContainer then return end

    if mod.db.dots.unlocked then
        dotsContainer:Show()
        for _, dot in ipairs(dotDefs) do
            local row = dotsRows[dot.key]
            if row and row:IsShown() then dotsUpdateRow(row, false, true) end
        end
        return
    end

    if not dotsTargetValid() then
        dotsContainer:Hide()
        return
    end

    dotsContainer:Show()
    dotsScanTarget()  -- one debuff pass for all rows
    local mult = dotsDamageMult()
    for _, dot in ipairs(dotDefs) do
        local row = dotsRows[dot.key]
        if row and row:IsShown() then dotsUpdateRow(row, true, false, mult) end
    end
end

local function dotsOnUpdate(self, elapsed)
    dotsThrottle = dotsThrottle + elapsed
    if dotsThrottle < 0.1 then return end
    dotsThrottle = 0
    if not mod._enabled then return end
    dotsRefresh()
end

local function dotsBuild()
    if dotsContainer then return end

    dotsContainer = CreateFrame("Frame", "VCUI_ShadowDots", UIParent)
    dotsContainer:SetSize(150, 60)
    dotsContainer:SetPoint("CENTER", UIParent, "CENTER", mod.db.dots.x, mod.db.dots.y)
    dotsContainer:SetFrameStrata("MEDIUM")

    for _, dot in ipairs(dotDefs) do
        dotsRows[dot.key] = dotsCreateRow(dot)
    end

    dotsContainer.mover = ns:CreateMover(dotsContainer, {
        label  = L["|cffffffffDOTS|r"],
        db     = mod.db.dots,
        width  = 160,
        height = 50,
        onMove = function(x, y)
            ns:Print(string.format(L["Shadow DoTs: x=%.0f, y=%.0f"], x, y))
        end,
    })

    dotsRefreshSpellData()
    dotsApplyLayout()
end

local function dotsSetUnlocked(state)
    mod.db.dots.unlocked = state
    if not dotsContainer then dotsBuild() end
    if state then
        dotsContainer:Show()
        dotsContainer.mover:Show()
        dotsApplyLayout()
        dotsRefresh()
        ns:Print(L["Shadow DoTs mover active. |cff9b6cffDrag|r or |cff9b6cffarrow keys|r (SHIFT = 5px)."])
    else
        dotsContainer.mover:Hide()
        dotsRefresh()
        ns:Print(L["Shadow DoTs mover disabled."])
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    -- Migration: take over old settings under "vampirictouchmana"
    if ns.db and ns.db.profile and ns.db.profile.modules then
        local old = ns.db.profile.modules.vampirictouchmana
        if old then
            for k, v in pairs(old) do
                if mod.db[k] == nil or k == "x" or k == "y" then
                    mod.db[k] = v
                end
            end
            ns.db.profile.modules.vampirictouchmana = nil
        end
    end

    -- Run any registered per-class tool for this class (e.g. Shaman totems)
    local _, class = UnitClass("player")
    local tool = mod.classTools and mod.classTools[class]
    if tool and tool.onEnable then
        local ok, err = pcall(tool.onEnable)
        if not ok then ns:Print(L["|cffff5555Class tool error:|r %s"], tostring(err)) end
    end

    -- Pick the DoT set for this class. VT mana stays Priest-only; the DoT
    -- tracker runs for any class that has a set (Priest + Warlock).
    local hasDots  = DOT_SETS[class] ~= nil
    dotDefs = DOT_SETS[class] or {}
    local isPriest = class == "PRIEST"
    if not isPriest and not hasDots then return end

    playerGUID = UnitGUID("player")

    -- Priest: Vampiric Touch mana frame
    if isPriest then
        vtSpellName = GetSpellInfo(VT_SPELL_ID_BASE)
        createFrame()
        if mod.db.showFrame then cFrame:Show() else cFrame:Hide() end
        ns:RegisterEvent("PLAYER_REGEN_DISABLED", resetCombat)
        ns:RegisterEvent("PLAYER_REGEN_ENABLED",  reportChat)
        ns:RegisterEvent("PLAYER_ENTERING_WORLD", resetCombat)
        ns:RegisterEvent("SPELLS_CHANGED",        refreshSpell)
    end

    -- DoT tracker (Priest + Warlock). The combat-log handler also feeds the
    -- VT mana counter, so it's registered whenever either system is active.
    if hasDots then
        ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCombatLog)

        -- migrate the old standalone "shadowdots" module
        if ns.db and ns.db.profile and ns.db.profile.modules then
            local oldDots = ns.db.profile.modules.shadowdots
            if oldDots then
                for k, v in pairs(oldDots) do
                    if k ~= "enabled" and mod.db.dots[k] ~= nil then
                        mod.db.dots[k] = v
                    end
                end
                ns.db.profile.modules.shadowdots = nil
            end
        end

        dotsBuild()
        dotsContainer:SetScript("OnUpdate", dotsOnUpdate)
        ns:RegisterEvent("UNIT_AURA",             dotsOnUnitAura)
        ns:RegisterEvent("SPELLS_CHANGED",        dotsRefreshSpellData)
        ns:RegisterEvent("PLAYER_TARGET_CHANGED", dotsRefresh)
        ns:RegisterEvent("PLAYER_ENTERING_WORLD", dotsRefresh)
        dotsRecomputeMult()
        dotsRefresh()
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCombatLog)
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED",       resetCombat)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",        reportChat)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD",       resetCombat)
    ns:UnregisterEvent("SPELLS_CHANGED",              refreshSpell)
    if cFrame then cFrame:Hide() end

    -- Shadow DoT tracker
    ns:UnregisterEvent("UNIT_AURA",             dotsOnUnitAura)
    ns:UnregisterEvent("SPELLS_CHANGED",        dotsRefreshSpellData)
    ns:UnregisterEvent("PLAYER_TARGET_CHANGED", dotsRefresh)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", dotsRefresh)
    if dotsContainer then
        dotsContainer:SetScript("OnUpdate", nil)
        if dotsContainer.mover then dotsContainer.mover:Hide() end
        dotsContainer:Hide()
    end

    -- Per-class tool teardown
    local _, class = UnitClass("player")
    local tool = mod.classTools and mod.classTools[class]
    if tool and tool.onDisable then pcall(tool.onDisable) end
end

-- =========================================================
-- Options
-- =========================================================
local CLASS_NAME = { PRIEST = L["Priest"], WARLOCK = L["Warlock"] }

-- Shared DoT-tracker options, built for a specific class' DoT set. Used by
-- both the Priest and Warlock tabs. The tracker only RUNS for the player's
-- own class, so a note is shown when viewing another class' tab.
local function appendDotTracker(items, forClass)
    table.insert(items, { type = "spacer", height = 10 })
    table.insert(items, { type = "header", text = L["DoT Tracker"] })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaTracks your DoTs on the target. |cff44ff44Green|r = a buff is up that makes it hit harder if you recast now (TBC snapshot); |cffff4444red|r = about to expire.|r"] })

    if select(2, UnitClass("player")) ~= forClass then
        table.insert(items, { type = "desc",
            text = string.format(L["|cffff8800Only active while playing a %s.|r"], CLASS_NAME[forClass] or forClass) })
    end

    table.insert(items, { type = "dropdown", label = L["Layout"],
        values = {
            { value = "bars",  text = L["Bars"]  },
            { value = "icons", text = L["Icons"] },
        },
        get = function() return mod.db.dots.layout end,
        set = function(_, v) mod.db.dots.layout = v; dotsApplyLayout(); dotsRefresh() end })

    -- One toggle per DoT in this class' set
    for _, dot in ipairs(DOT_SETS[forClass] or {}) do
        local toggleKey = dot.toggle
        table.insert(items, { type = "toggle", label = L[dot.label],
            get = function() return mod.db.dots[toggleKey] end,
            set = function(_, v) mod.db.dots[toggleKey] = v; dotsApplyLayout(); dotsRefresh() end })
    end

    table.insert(items, { type = "slider", label = L["Warning (seconds left)"],
        min = 1, max = 6, step = 1,
        get = function() return mod.db.dots.warnSeconds end,
        set = function(_, v) mod.db.dots.warnSeconds = v end })
    table.insert(items, { type = "slider", label = L["Bar width"],
        min = 80, max = 300, step = 5,
        get = function() return mod.db.dots.barWidth end,
        set = function(_, v) mod.db.dots.barWidth = v; dotsApplyLayout(); dotsRefresh() end })
    table.insert(items, { type = "slider", label = L["Bar height"],
        min = 10, max = 36, step = 1,
        get = function() return mod.db.dots.barHeight end,
        set = function(_, v) mod.db.dots.barHeight = v; dotsApplyLayout(); dotsRefresh() end })
    table.insert(items, { type = "slider", label = L["Icon size"],
        min = 18, max = 56, step = 1,
        get = function() return mod.db.dots.iconSize end,
        set = function(_, v) mod.db.dots.iconSize = v; dotsApplyLayout(); dotsRefresh() end })
    table.insert(items, { type = "slider", label = L["Spacing"],
        min = 0, max = 12, step = 1,
        get = function() return mod.db.dots.spacing end,
        set = function(_, v) mod.db.dots.spacing = v; dotsApplyLayout(); dotsRefresh() end })
    table.insert(items, { type = "slider", label = L["Font size"],
        min = 8, max = 24, step = 1,
        get = function() return mod.db.dots.fontSize end,
        set = function(_, v) mod.db.dots.fontSize = v; dotsApplyLayout(); dotsRefresh() end })
    table.insert(items, { type = "toggle", label = L["Color the timer text"],
        get = function() return mod.db.dots.colorText end,
        set = function(_, v) mod.db.dots.colorText = v end })
    table.insert(items, { type = "toggle", label = L["Show recast gain %"],
        tooltip = L["Shows how much harder a fresh cast would hit right now (e.g. +12% with a spell power proc up). Negative values mean the running DoT snapshotted stronger — keep it."],
        get = function() return mod.db.dots.showGain end,
        set = function(_, v) mod.db.dots.showGain = v; dotsRefresh() end })

    table.insert(items, { type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", label = L["Unlock / Position"], width = 200,
              onClick = function() dotsSetUnlocked(not mod.db.dots.unlocked) end },
            { type = "button", label = L["Reset position"], width = 200,
              onClick = function()
                  mod.db.dots.x, mod.db.dots.y = 250, 0
                  if dotsContainer then
                      dotsContainer:ClearAllPoints()
                      dotsContainer:SetPoint("CENTER", UIParent, "CENTER", mod.db.dots.x, mod.db.dots.y)
                  end
              end },
        },
    })
    return items
end

-- Priest tab: Shadow → Vampiric Touch mana tracker + DoT tracker
local function priestOptions()
    local isPriest = select(2, UnitClass("player")) == "PRIEST"
    local items = {
        { type = "header", text = L["Shadow"] },
        { type = "desc",
          text = L["|cffaaaaaaVampiric Touch mana tracker — shows live how much mana you've given to the group (5% of shadow damage per tick, per mana user).|n|cffffffffReset automatically on combat start.|r|r"] },
    }

    if not isPriest then
        table.insert(items, { type = "spacer", height = 6 })
        table.insert(items, { type = "desc",
            text = L["|cffff8800These tools are only active while playing a Priest.|r"] })
    end

    table.insert(items, { type = "spacer", height = 4 })
    table.insert(items, { type = "toggle", label = L["Show frame"],
        get = function() return mod.db.showFrame end,
        set = function(_, v)
            mod.db.showFrame = v
            if cFrame then if v then cFrame:Show() else cFrame:Hide() end end
        end })

    table.insert(items, { type = "toggle", label = L["Print to chat at combat end"],
        tooltip = L["Writes a summary in chat after each fight."],
        get = function() return mod.db.showInChat end,
        set = function(_, v) mod.db.showInChat = v end })

    table.insert(items, { type = "slider", label = L["Font size"],
        min = 8, max = 32, step = 1,
        get = function() return mod.db.fontSize end,
        set = function(_, v)
            mod.db.fontSize = v
            if cFrame and cFrame.text then
                cFrame.text:SetFont("Fonts\\FRIZQT__.TTF", v, "OUTLINE")
            end
        end })

    table.insert(items, { type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", label = L["Unlock / Position"], width = 200,
              onClick = function() setUnlocked(not mod.db.unlocked) end },
            { type = "button", label = L["Reset manually"], width = 200,
              onClick = function()
                  totalMana = 0
                  lastTick  = 0
                  updateFrame()
                  ns:Print(L["VT mana reset."])
              end },
        },
    })

    -- Shadow DoT tracker (shared engine, Priest set)
    appendDotTracker(items, "PRIEST")
    return items
end

-- Tab id -> display label (from mod.tabs), for generic class option headers.
local TAB_LABEL = {}
for _, t in ipairs(mod.tabs) do TAB_LABEL[t.id] = t.label end

function mod:GetOptions(tabId)
    if tabId == "priest" or tabId == "default" or tabId == nil then
        return priestOptions()
    end

    local classToken = tabId and tabId:upper() or ""

    -- A custom class tool (e.g. the Shaman totem bar) supplies its own options.
    local tool = self.classTools and self.classTools[classToken]
    if tool and tool.getOptions then
        return tool.getOptions()
    end

    -- Any class that registered a DoT set gets the generic DoT tracker page.
    if DOT_SETS[classToken] then
        local label = TAB_LABEL[tabId] or classToken
        local items = { { type = "header", text = L[label] or label } }
        local meta = DOT_SET_META[classToken]
        if meta and meta.desc then
            table.insert(items, { type = "desc", text = meta.desc })
        end
        appendDotTracker(items, classToken)
        return items
    end

    -- Nothing class-specific yet.
    return {
        { type = "header", text = L["No tools yet"] },
        { type = "desc", text = L["|cffaaaaaaNo class-specific tools for this class yet. Got an idea? Let me know!|r"] },
    }
end
