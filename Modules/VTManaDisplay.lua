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
        -- Shadow DoT tracker (Priest → Shadow)
        dots = {
            layout      = "bars",   -- "bars" | "icons"
            showSWP     = true,
            showVT      = true,
            showDP      = false,  -- Undead only; off by default
            warnSeconds = 3,
            colorText   = true,
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

local function onCLEU()
    if not vtSpellName then return end
    if not playerGUID then
        playerGUID = UnitGUID("player")
        if not playerGUID then return end
    end

    -- Cheap pre-filter: read only source + subevent, bail before the full
    -- destructure for anything that isn't our tracked event from us.
    local _, subEvent, _, sourceGUID = CombatLogGetCurrentEventInfo()
    if sourceGUID ~= playerGUID then return end
    local kind = TRACKED_EVENTS[subEvent]
    if not kind then return end

    local _, _, _, _, _, _, _, destGUID, _, _, _,
          _, spellName, _, amount, _, school = CombatLogGetCurrentEventInfo()

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
    else -- "damage"
        if vtTargets[destGUID] and amount and amount > 0 and school == SHADOW_SCHOOL then
            local mana = amount * 0.05
            totalMana = totalMana + mana
            lastTick  = mana
            updateFrame()
        end
    end
end

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
-- base = approximate base damage over the full duration; coef = spell-power
-- coefficient over the full duration. Exact values barely matter: the
-- "is a recast stronger now?" check is relative (each DoT vs its OWN snapshot),
-- so base/coef only weight spell power against % buffs when the two move in
-- opposite directions. Rough TBC values.
local dotDefs = {
    { key = "swp", id = 589,   toggle = "showSWP", color = { 0.62, 0.40, 0.94 }, base = 1236, coef = 1.10 }, -- Shadow Word: Pain
    { key = "vt",  id = 34917, toggle = "showVT",  color = { 0.85, 0.30, 0.85 }, base = 850,  coef = 1.00 }, -- Vampiric Touch
    { key = "dp",  id = 2944,  toggle = "showDP",  color = { 0.40, 0.78, 0.36 }, base = 1216, coef = 1.00 }, -- Devouring Plague (Undead)
}

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

-- Shadow spell power right now (6 = shadow school index for GetSpellBonusDamage).
local function dotsCurrentPower()
    return (GetSpellBonusDamage and GetSpellBonusDamage(6)) or 0
end

-- Product of active caster-side % spell-damage buffs (1.0 if none).
local function dotsDamageMult()
    local m = 1
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
        if not name then break end
        local b = spellId and DOT_DMG_BUFFS[spellId]
        if b then m = m * b end
    end
    return m
end

-- Estimated DoT damage = (base + spellpower * coef) * % damage multiplier.
-- AffDots-style: snapshot this at cast, then compare to the live value.
local function dotsFactor(dot, sp, mult)
    return (dot.base + sp * dot.coef) * mult
end

-- Would recasting this DoT on the current target hit harder than the value it
-- snapshotted at cast? TBC DoTs freeze spell power AND caster % buffs on cast,
-- so if either is higher now a fresh cast deals more damage. (0.5% margin
-- avoids flicker from rounding.)
local function dotsBetter(dot, sp, mult)
    local guid = UnitGUID("target")
    if not guid then return false end
    local snap = dotsSnapshots[guid .. dot.key]
    if not snap then return false end
    return dotsFactor(dot, sp, mult) > snap * 1.005
end

-- Record the spell-power snapshot when we (re)apply a tracked DoT, and drop it
-- again when the DoT falls off (or the target dies). Keeps dotsSnapshots from
-- growing unbounded and prevents stale snapshots on recycled GUIDs.
local function dotsOnCLEU()
    if not playerGUID then return end
    local _, sub, _, srcGUID, _, _, _, destGUID, _, _, _, _, spellName =
        CombatLogGetCurrentEventInfo()
    if srcGUID ~= playerGUID then return end
    local apply  = (sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH")
    local remove = (sub == "SPELL_AURA_REMOVED")
    if not (apply or remove) then return end
    for _, dot in ipairs(dotDefs) do
        if dot.name and spellName == dot.name then
            dotsSnapshots[destGUID .. dot.key] =
                apply and dotsFactor(dot, dotsCurrentPower(), dotsDamageMult()) or nil
            return
        end
    end
end

local function dotsRefreshSpellData()
    for _, dot in ipairs(dotDefs) do
        local n, _, icon = GetSpellInfo(dot.id)
        dot.name = n
        dot.icon = icon
        if dotsRows[dot.key] and icon then
            dotsRows[dot.key].icon:SetTexture(icon)
        end
    end
end

-- Find the player's own debuff by name; verify caster == "player".
local function dotsFindAura(unit, name)
    if not name then return nil end
    for i = 1, 40 do
        local aName, _, _, _, dur, exp, source = UnitAura(unit, i, "HARMFUL")
        if not aName then return nil end
        if aName == name and source == "player" then
            return dur, exp
        end
    end
    return nil
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

            row:Show()
        end
        dotsContainer:SetSize(iconW + w, #active * h + (#active - 1) * db.spacing)
    end
end

local function dotsUpdateRow(row, hasTarget, preview, sp, mult)
    local db  = mod.db.dots
    local dot = row.dot
    local dur, exp

    if preview then
        dur = 10
        exp = GetTime() + (dot.key == "vt" and 7 or 10)
    elseif hasTarget then
        dur, exp = dotsFindAura("target", dot.name)
    end

    if dur and exp and dur > 0 then
        local remaining = exp - GetTime()
        if remaining < 0 then remaining = 0 end
        local frac = remaining / dur
        if frac > 1 then frac = 1 end
        local warn   = remaining <= db.warnSeconds
        local better = (hasTarget and not preview) and dotsBetter(dot, sp, mult) or false

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
    local sp, mult = dotsCurrentPower(), dotsDamageMult()
    for _, dot in ipairs(dotDefs) do
        local row = dotsRows[dot.key]
        if row and row:IsShown() then dotsUpdateRow(row, true, false, sp, mult) end
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
        label  = L["|cffffffffSHADOW DOTS|r"],
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

    -- Priests only
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return end

    playerGUID  = UnitGUID("player")
    vtSpellName = GetSpellInfo(VT_SPELL_ID_BASE)

    createFrame()
    if mod.db.showFrame then cFrame:Show() else cFrame:Hide() end

    ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    ns:RegisterEvent("PLAYER_REGEN_DISABLED",       resetCombat)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",        reportChat)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD",       resetCombat)
    ns:RegisterEvent("SPELLS_CHANGED",              refreshSpell)

    -- Shadow DoT tracker: migrate the old standalone "shadowdots" module
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
    ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", dotsOnCLEU)
    ns:RegisterEvent("SPELLS_CHANGED",        dotsRefreshSpellData)
    ns:RegisterEvent("PLAYER_TARGET_CHANGED", dotsRefresh)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", dotsRefresh)
    dotsRefresh()
end

function mod:OnDisable()
    ns:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED",       resetCombat)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",        reportChat)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD",       resetCombat)
    ns:UnregisterEvent("SPELLS_CHANGED",              refreshSpell)
    if cFrame then cFrame:Hide() end

    -- Shadow DoT tracker
    ns:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED", dotsOnCLEU)
    ns:UnregisterEvent("SPELLS_CHANGED",        dotsRefreshSpellData)
    ns:UnregisterEvent("PLAYER_TARGET_CHANGED", dotsRefresh)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", dotsRefresh)
    if dotsContainer then
        dotsContainer:SetScript("OnUpdate", nil)
        if dotsContainer.mover then dotsContainer.mover:Hide() end
        dotsContainer:Hide()
    end
end

-- =========================================================
-- Options
-- =========================================================
-- Priest tab: Shadow → Vampiric Touch mana tracker
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

    -- -----------------------------------------------------
    -- Shadow DoT tracker
    -- -----------------------------------------------------
    table.insert(items, { type = "spacer", height = 10 })
    table.insert(items, { type = "header", text = L["Shadow DoT Tracker"] })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaTracks your Shadow DoTs on the target. |cff44ff44Green|r = a buff is up that makes it hit harder if you recast now (TBC snapshot); |cffff4444red|r = about to expire.|r"] })

    table.insert(items, { type = "dropdown", label = L["Layout"],
        values = {
            { value = "bars",  text = L["Bars"]  },
            { value = "icons", text = L["Icons"] },
        },
        get = function() return mod.db.dots.layout end,
        set = function(_, v) mod.db.dots.layout = v; dotsApplyLayout(); dotsRefresh() end })

    table.insert(items, { type = "toggle", label = L["Shadow Word: Pain"],
        get = function() return mod.db.dots.showSWP end,
        set = function(_, v) mod.db.dots.showSWP = v; dotsApplyLayout(); dotsRefresh() end })
    table.insert(items, { type = "toggle", label = L["Vampiric Touch"],
        get = function() return mod.db.dots.showVT end,
        set = function(_, v) mod.db.dots.showVT = v; dotsApplyLayout(); dotsRefresh() end })
    table.insert(items, { type = "toggle", label = L["Devouring Plague"],
        get = function() return mod.db.dots.showDP end,
        set = function(_, v) mod.db.dots.showDP = v; dotsApplyLayout(); dotsRefresh() end })

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

function mod:GetOptions(tabId)
    if tabId == "priest" or tabId == "default" or tabId == nil then
        return priestOptions()
    end
    -- Other classes: placeholder until tools exist for them
    return {
        { type = "header", text = L["No tools yet"] },
        { type = "desc", text = L["|cffaaaaaaNo class-specific tools for this class yet. Got an idea? Let me know!|r"] },
    }
end
