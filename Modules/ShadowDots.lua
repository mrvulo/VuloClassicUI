-- =========================================================
-- VuloClassicUI / Modules / ShadowDots
-- Shadow Priest DoT uptime tracker for the current target.
-- Tracks YOUR Shadow Word: Pain / Vampiric Touch / Devouring Plague
-- as bars or icons, with a "refresh soon" colour warning.
--
-- TBC note: no Mastery / Pandemic / specialization API exists in 2.5.5 —
-- this purely reads UnitAura duration/expiration for the player's own
-- debuffs (matched by name, so every rank is covered). Inspired by the
-- idea behind Warlock DoT trackers, rebuilt natively on our own infra.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("shadowdots", {
    name        = "Shadow DoTs",
    group       = "QoL",
    description = "Shadow Priest DoT tracker: Shadow Word: Pain, Vampiric Touch and Devouring Plague on your target, as bars or icons, with a refresh-soon warning.",
    defaults    = {
        enabled     = true,
        layout      = "bars",   -- "bars" | "icons"
        showSWP     = true,
        showVT      = true,
        showDP      = true,
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
})

-- DoT definitions. The base-rank id is only used to fetch the localized
-- name + icon; auras are matched by name, which covers every rank.
local DOTS = {
    { key = "swp", id = 589,   toggle = "showSWP", color = { 0.62, 0.40, 0.94 } }, -- Shadow Word: Pain
    { key = "vt",  id = 34914, toggle = "showVT",  color = { 0.85, 0.30, 0.85 } }, -- Vampiric Touch
    { key = "dp",  id = 2944,  toggle = "showDP",  color = { 0.40, 0.78, 0.36 } }, -- Devouring Plague
}

local WARN_COLOR = { 1.0, 0.25, 0.25 }
local BAR_TEX    = "Interface\\Buttons\\WHITE8X8"
local SPARK_TEX  = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FONT       = "Fonts\\FRIZQT__.TTF"

local container        -- the moved frame (parent of all rows)
local rows = {}        -- key -> row frame
local throttle = 0

-- ---------------------------------------------------------
-- Localized names / icons (refreshed on SPELLS_CHANGED)
-- ---------------------------------------------------------
local function refreshSpellData()
    for _, dot in ipairs(DOTS) do
        local n, _, icon = GetSpellInfo(dot.id)
        dot.name = n
        dot.icon = icon
        if rows[dot.key] and icon then
            rows[dot.key].icon:SetTexture(icon)
        end
    end
end

-- ---------------------------------------------------------
-- Find the player's own debuff by name on a unit.
-- Iterates HARMFUL auras and verifies caster == "player"
-- (robust across Classic UnitAura filter quirks).
-- Returns duration, expirationTime or nil.
-- ---------------------------------------------------------
local function findAura(unit, name)
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

-- ---------------------------------------------------------
-- Create a row frame (holds both bar and icon visuals;
-- applyLayout decides which parts are shown).
-- ---------------------------------------------------------
local function createRow(dot)
    local row = CreateFrame("Frame", nil, container)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if dot.icon then row.icon:SetTexture(dot.icon) end

    row.cd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cd:SetDrawEdge(true)
    if row.cd.SetHideCountdownNumbers then
        row.cd:SetHideCountdownNumbers(true)  -- we draw our own timer text
    end
    row.cd:Hide()

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetTexture(BAR_TEX)
    row.bg:SetVertexColor(0.08, 0.08, 0.08, 0.85)

    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetTexture(BAR_TEX)
    row.fill:SetVertexColor(dot.color[1], dot.color[2], dot.color[3], 0.9)

    row.spark = row:CreateTexture(nil, "OVERLAY")
    row.spark:SetTexture(SPARK_TEX)
    row.spark:SetBlendMode("ADD")
    row.spark:SetWidth(16)

    row.time = row:CreateFontString(nil, "OVERLAY")
    row.time:SetFont(FONT, mod.db.fontSize, "OUTLINE")

    row.dot = dot
    return row
end

-- ---------------------------------------------------------
-- (Re)position + size everything for the current layout.
-- ---------------------------------------------------------
local function applyLayout()
    if not container then return end
    local db = mod.db

    local active = {}
    for _, dot in ipairs(DOTS) do
        if db[dot.toggle] then active[#active + 1] = dot end
    end

    for _, row in pairs(rows) do row:Hide() end

    if #active == 0 then
        container:SetSize(1, 1)
        return
    end

    if db.layout == "icons" then
        local s = db.iconSize
        for i, dot in ipairs(active) do
            local row = rows[dot.key]
            row:ClearAllPoints()
            row:SetSize(s, s)
            row:SetPoint("LEFT", container, "LEFT", (i - 1) * (s + db.spacing), 0)

            row.icon:ClearAllPoints()
            row.icon:SetAllPoints(row)
            row.icon:Show()

            row.cd:ClearAllPoints()
            row.cd:SetAllPoints(row)

            row.bg:Hide(); row.fill:Hide(); row.spark:Hide()

            row.time:ClearAllPoints()
            row.time:SetPoint("BOTTOM", row, "BOTTOM", 0, 1)
            row.time:SetFont(FONT, db.fontSize, "OUTLINE")

            row:Show()
        end
        container:SetSize(#active * s + (#active - 1) * db.spacing, s)
    else -- bars
        local h, w = db.barHeight, db.barWidth
        local iconW = h
        for i, dot in ipairs(active) do
            local row = rows[dot.key]
            row:ClearAllPoints()
            row:SetSize(iconW + w, h)
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * (h + db.spacing))

            row.icon:ClearAllPoints()
            row.icon:SetSize(h, h)
            row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.icon:Show()

            row.cd:Hide()

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
            row.time:SetFont(FONT, db.fontSize, "OUTLINE")

            row:Show()
        end
        container:SetSize(iconW + w, #active * h + (#active - 1) * db.spacing)
    end
end

-- ---------------------------------------------------------
-- Update a single row from aura data (or preview).
-- ---------------------------------------------------------
local function updateRow(row, hasTarget, preview)
    local db  = mod.db
    local dot = row.dot
    local dur, exp

    if preview then
        dur = 10
        exp = GetTime() + (dot.key == "vt" and 7 or 10)
    elseif hasTarget then
        dur, exp = findAura("target", dot.name)
    end

    if dur and exp and dur > 0 then
        local remaining = exp - GetTime()
        if remaining < 0 then remaining = 0 end
        local frac = remaining / dur
        if frac > 1 then frac = 1 end
        local warn = remaining <= db.warnSeconds

        if remaining < 10 then
            row.time:SetText(string.format("%.1f", remaining))
        else
            row.time:SetText(string.format("%d", remaining + 0.5))
        end
        row.time:Show()
        if db.colorText and warn then
            row.time:SetTextColor(WARN_COLOR[1], WARN_COLOR[2], WARN_COLOR[3])
        else
            row.time:SetTextColor(1, 1, 1)
        end

        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 1, 1)
        if db.layout == "icons" then
            row.cd:SetCooldown(exp - dur, dur)
            row.cd:Show()
        else
            local fw = db.barWidth * frac
            if fw < 1 then fw = 1 end
            row.fill:SetWidth(fw)
            if warn then
                row.fill:SetVertexColor(WARN_COLOR[1], WARN_COLOR[2], WARN_COLOR[3], 0.9)
            else
                row.fill:SetVertexColor(dot.color[1], dot.color[2], dot.color[3], 0.9)
            end
            row.fill:Show()
            row.spark:ClearAllPoints()
            row.spark:SetPoint("CENTER", row.fill, "RIGHT", 0, 0)
            if frac > 0.02 and frac < 0.99 then row.spark:Show() else row.spark:Hide() end
        end
    else
        -- Not present → dim, no timer
        row.time:SetText("")
        row.time:Hide()
        row.icon:SetDesaturated(true)
        row.icon:SetVertexColor(0.5, 0.5, 0.5)
        if db.layout == "icons" then
            row.cd:Hide()
        else
            row.fill:Hide()
            row.spark:Hide()
        end
    end
end

-- ---------------------------------------------------------
-- Visibility + scan loop
-- ---------------------------------------------------------
local function targetIsValid()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDead("target")
end

local function refresh()
    if not container then return end

    if mod.db.unlocked then
        container:Show()
        for _, dot in ipairs(DOTS) do
            local row = rows[dot.key]
            if row and row:IsShown() then updateRow(row, false, true) end
        end
        return
    end

    if not targetIsValid() then
        container:Hide()
        return
    end

    container:Show()
    for _, dot in ipairs(DOTS) do
        local row = rows[dot.key]
        if row and row:IsShown() then updateRow(row, true, false) end
    end
end

local function onUpdate(self, elapsed)
    throttle = throttle + elapsed
    if throttle < 0.1 then return end
    throttle = 0
    if not mod._enabled then return end
    refresh()
end

-- ---------------------------------------------------------
-- Build / mover
-- ---------------------------------------------------------
local function build()
    if container then return end

    container = CreateFrame("Frame", "VCUI_ShadowDots", UIParent)
    container:SetSize(150, 60)
    container:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)
    container:SetFrameStrata("MEDIUM")

    for _, dot in ipairs(DOTS) do
        rows[dot.key] = createRow(dot)
    end

    container.mover = ns:CreateMover(container, {
        label  = L["|cffffffffSHADOW DOTS|r"],
        db     = mod.db,
        width  = 160,
        height = 50,
        onMove = function(x, y)
            ns:Print(string.format(L["Shadow DoTs: x=%.0f, y=%.0f"], x, y))
        end,
    })

    refreshSpellData()
    applyLayout()
end

local function setUnlocked(state)
    mod.db.unlocked = state
    if not container then build() end
    if state then
        container:Show()
        container.mover:Show()
        applyLayout()
        refresh()
        ns:Print(L["Shadow DoTs mover active. |cff9b6cffDrag|r or |cff9b6cffarrow keys|r (SHIFT = 5px)."])
    else
        container.mover:Hide()
        refresh()
        ns:Print(L["Shadow DoTs mover disabled."])
    end
end

-- ---------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------
function mod:OnEnable()
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return end

    build()
    container:SetScript("OnUpdate", onUpdate)

    ns:RegisterEvent("SPELLS_CHANGED",        refreshSpellData)
    ns:RegisterEvent("PLAYER_TARGET_CHANGED", refresh)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", refresh)

    refresh()
end

function mod:OnDisable()
    ns:UnregisterEvent("SPELLS_CHANGED",        refreshSpellData)
    ns:UnregisterEvent("PLAYER_TARGET_CHANGED", refresh)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", refresh)
    if container then
        container:SetScript("OnUpdate", nil)
        if container.mover then container.mover:Hide() end
        container:Hide()
    end
end

-- ---------------------------------------------------------
-- Options
-- ---------------------------------------------------------
function mod:GetOptions()
    local isPriest = select(2, UnitClass("player")) == "PRIEST"
    local items = {
        { type = "header", text = L["Shadow DoT Tracker"] },
        { type = "desc",   text = L["|cffaaaaaaTracks your own Shadow Word: Pain, Vampiric Touch and Devouring Plague on the current target. Choose bars or icons; the bar/icon turns red shortly before the DoT expires.|r"] },
    }

    if not isPriest then
        items[#items + 1] = { type = "spacer", height = 4 }
        items[#items + 1] = { type = "desc", text = L["|cffff8800Only active while playing a Priest.|r"] }
    end

    items[#items + 1] = { type = "spacer", height = 4 }
    items[#items + 1] = {
        type = "dropdown", label = L["Layout"],
        values = {
            { value = "bars",  text = L["Bars"]  },
            { value = "icons", text = L["Icons"] },
        },
        get = function() return mod.db.layout end,
        set = function(_, v) mod.db.layout = v; applyLayout(); refresh() end,
    }

    items[#items + 1] = { type = "header", text = L["Tracked DoTs"] }
    items[#items + 1] = { type = "toggle", label = L["Shadow Word: Pain"],
        get = function() return mod.db.showSWP end,
        set = function(_, v) mod.db.showSWP = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Vampiric Touch"],
        get = function() return mod.db.showVT end,
        set = function(_, v) mod.db.showVT = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Devouring Plague"],
        get = function() return mod.db.showDP end,
        set = function(_, v) mod.db.showDP = v; applyLayout(); refresh() end }

    items[#items + 1] = { type = "header", text = L["Appearance"] }
    items[#items + 1] = { type = "slider", label = L["Warning (seconds left)"],
        min = 1, max = 6, step = 1,
        get = function() return mod.db.warnSeconds end,
        set = function(_, v) mod.db.warnSeconds = v end }
    items[#items + 1] = { type = "slider", label = L["Bar width"],
        min = 80, max = 300, step = 5,
        get = function() return mod.db.barWidth end,
        set = function(_, v) mod.db.barWidth = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Bar height"],
        min = 10, max = 36, step = 1,
        get = function() return mod.db.barHeight end,
        set = function(_, v) mod.db.barHeight = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Icon size"],
        min = 18, max = 56, step = 1,
        get = function() return mod.db.iconSize end,
        set = function(_, v) mod.db.iconSize = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Spacing"],
        min = 0, max = 12, step = 1,
        get = function() return mod.db.spacing end,
        set = function(_, v) mod.db.spacing = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Font size"],
        min = 8, max = 24, step = 1,
        get = function() return mod.db.fontSize end,
        set = function(_, v) mod.db.fontSize = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Color the timer text"],
        get = function() return mod.db.colorText end,
        set = function(_, v) mod.db.colorText = v end }

    items[#items + 1] = { type = "spacer", height = 4 }
    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "button", label = L["Unlock / Position"], width = 200,
          onClick = function() setUnlocked(not mod.db.unlocked) end },
        { type = "button", label = L["Reset position"], width = 200,
          onClick = function()
              mod.db.x, mod.db.y = 250, 0
              if container then
                  container:ClearAllPoints()
                  container:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)
              end
          end },
    } }

    return items
end
