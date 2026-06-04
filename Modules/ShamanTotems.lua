-- =========================================================
-- VuloClassicUI / Modules / ShamanTotems
-- Shaman totem timer — plugs into the "Class Specific" module (Shaman tab).
-- Clean, easy-to-configure bars or icons for the four totem elements with the
-- remaining time and a "recast soon" warning. Reads GetTotemInfo(slot); no taint.
-- Settings live under the Class Specific module's db (csMod.db.totems).
-- =========================================================
local _, ns = ...
local L = ns.L

-- Plug into the Class Specific container module.
local csMod = ns.modules and ns.modules.vtmanadisplay
if not csMod or not csMod.RegisterClassTool then return end

local TOTEM_DEFAULTS = {
    layout      = "bars",   -- "bars" | "icons"
    showFire    = true,
    showEarth   = true,
    showWater   = true,
    showAir     = true,
    warnSeconds = 5,
    colorText   = true,
    barWidth    = 150,
    barHeight   = 18,
    iconSize    = 32,
    spacing     = 3,
    fontSize    = 12,
    x           = -250,
    y           = 0,
    unlocked    = false,
}

-- Slot order: Fire(1), Earth(2), Water(3), Air(4). Blizzard globals with fallback.
local TOTEMS = {
    { key = "fire",  slot = _G.FIRE_TOTEM_SLOT  or 1, toggle = "showFire",  color = { 0.95, 0.35, 0.10 }, icon = "Interface\\Icons\\Spell_Fire_SearingTotem" },
    { key = "earth", slot = _G.EARTH_TOTEM_SLOT or 2, toggle = "showEarth", color = { 0.70, 0.50, 0.25 }, icon = "Interface\\Icons\\Spell_Nature_StoneClawTotem" },
    { key = "water", slot = _G.WATER_TOTEM_SLOT or 3, toggle = "showWater", color = { 0.20, 0.55, 0.95 }, icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem" },
    { key = "air",   slot = _G.AIR_TOTEM_SLOT   or 4, toggle = "showAir",   color = { 0.60, 0.80, 0.95 }, icon = "Interface\\Icons\\Spell_Nature_InvisibilityTotem" },
}

local WARN_COLOR = { 1.0, 0.25, 0.25 }
local BAR_TEX    = "Interface\\Buttons\\WHITE8X8"
local SPARK_TEX  = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FONT       = "Fonts\\FRIZQT__.TTF"

local container
local rows     = {}
local throttle = 0

-- Settings table (created with defaults on first use; safe for non-shamans who
-- merely open the Shaman options tab).
local function ensureDB()
    csMod.db.totems = ns:ApplyDefaults(csMod.db.totems, TOTEM_DEFAULTS)
    return csMod.db.totems
end
local function db() return csMod.db.totems end

-- ---------------------------------------------------------
-- Row creation (holds both bar + icon visuals)
-- ---------------------------------------------------------
local function createRow(totem)
    local row = CreateFrame("Frame", nil, container)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetTexture(totem.icon)

    row.cd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cd:SetDrawEdge(true)
    if row.cd.SetHideCountdownNumbers then row.cd:SetHideCountdownNumbers(true) end
    row.cd:Hide()

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetTexture(BAR_TEX)
    row.bg:SetVertexColor(0.08, 0.08, 0.08, 0.85)

    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetTexture(BAR_TEX)
    row.fill:SetVertexColor(totem.color[1], totem.color[2], totem.color[3], 0.9)

    row.spark = row:CreateTexture(nil, "OVERLAY")
    row.spark:SetTexture(SPARK_TEX)
    row.spark:SetBlendMode("ADD")
    row.spark:SetWidth(16)

    row.time = row:CreateFontString(nil, "OVERLAY")
    row.time:SetFont(FONT, db().fontSize, "OUTLINE")

    row.totem = totem
    return row
end

-- ---------------------------------------------------------
-- Layout (positions + sizes per current layout)
-- ---------------------------------------------------------
local function applyLayout()
    if not container then return end
    local d = db()

    local active = {}
    for _, t in ipairs(TOTEMS) do
        if d[t.toggle] then active[#active + 1] = t end
    end

    for _, row in pairs(rows) do row:Hide() end

    if #active == 0 then
        container:SetSize(1, 1)
        return
    end

    if d.layout == "icons" then
        local s = d.iconSize
        for i, t in ipairs(active) do
            local row = rows[t.key]
            row:ClearAllPoints()
            row:SetSize(s, s)
            row:SetPoint("LEFT", container, "LEFT", (i - 1) * (s + d.spacing), 0)

            row.icon:ClearAllPoints(); row.icon:SetAllPoints(row); row.icon:Show()
            row.cd:ClearAllPoints(); row.cd:SetAllPoints(row)
            row.bg:Hide(); row.fill:Hide(); row.spark:Hide()

            row.time:ClearAllPoints()
            row.time:SetPoint("BOTTOM", row, "BOTTOM", 0, 1)
            row.time:SetFont(FONT, d.fontSize, "OUTLINE")

            row:Show()
        end
        container:SetSize(#active * s + (#active - 1) * d.spacing, s)
    else -- bars
        local h, w = d.barHeight, d.barWidth
        local iconW = h
        for i, t in ipairs(active) do
            local row = rows[t.key]
            row:ClearAllPoints()
            row:SetSize(iconW + w, h)
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * (h + d.spacing))

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
            row.time:SetFont(FONT, d.fontSize, "OUTLINE")

            row:Show()
        end
        container:SetSize(iconW + w, #active * h + (#active - 1) * d.spacing)
    end
end

-- ---------------------------------------------------------
-- Per-row update from GetTotemInfo (or preview)
-- ---------------------------------------------------------
local function updateRow(row, preview)
    local d = db()
    local t = row.totem
    local have, startTime, duration, icon

    if preview then
        have, startTime, duration, icon = true, GetTime(), 60, t.icon
    else
        local h, _, st, dur, ic = GetTotemInfo(t.slot)
        have, startTime, duration, icon = h, st, dur, ic
    end

    if have and duration and duration > 0 then
        local remaining = (startTime + duration) - GetTime()
        if remaining < 0 then remaining = 0 end
        local frac = remaining / duration
        if frac > 1 then frac = 1 end
        local warn = remaining <= d.warnSeconds

        if icon then row.icon:SetTexture(icon) end
        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 1, 1)

        if remaining < 10 then
            row.time:SetText(string.format("%.1f", remaining))
        else
            row.time:SetText(string.format("%d", remaining + 0.5))
        end
        row.time:Show()
        if d.colorText and warn then
            row.time:SetTextColor(WARN_COLOR[1], WARN_COLOR[2], WARN_COLOR[3])
        else
            row.time:SetTextColor(1, 1, 1)
        end

        if d.layout == "icons" then
            row.cd:SetCooldown(startTime, duration)
            row.cd:Show()
        else
            local fw = d.barWidth * frac
            if fw < 1 then fw = 1 end
            row.fill:SetWidth(fw)
            if warn then
                row.fill:SetVertexColor(WARN_COLOR[1], WARN_COLOR[2], WARN_COLOR[3], 0.9)
            else
                row.fill:SetVertexColor(t.color[1], t.color[2], t.color[3], 0.9)
            end
            row.fill:Show()
            row.spark:ClearAllPoints()
            row.spark:SetPoint("CENTER", row.fill, "RIGHT", 0, 0)
            if frac > 0.02 and frac < 0.99 then row.spark:Show() else row.spark:Hide() end
        end
    else
        -- No totem of this element down -> dim
        row.icon:SetTexture(t.icon)
        row.icon:SetDesaturated(true)
        row.icon:SetVertexColor(0.5, 0.5, 0.5)
        row.time:SetText("")
        row.time:Hide()
        if d.layout == "icons" then
            row.cd:Hide()
        else
            row.fill:Hide()
            row.spark:Hide()
        end
    end
end

-- ---------------------------------------------------------
-- Visibility + scan
-- ---------------------------------------------------------
local function anyTotemActive()
    for _, t in ipairs(TOTEMS) do
        if db()[t.toggle] then
            local have = GetTotemInfo(t.slot)
            if have then return true end
        end
    end
    return false
end

local function refresh()
    if not container then return end

    if db().unlocked then
        container:Show()
        for _, t in ipairs(TOTEMS) do
            local row = rows[t.key]
            if row and row:IsShown() then updateRow(row, true) end
        end
        return
    end

    -- Declutter: hide the whole display while no enabled totem is down.
    if not anyTotemActive() then
        container:Hide()
        return
    end

    container:Show()
    for _, t in ipairs(TOTEMS) do
        local row = rows[t.key]
        if row and row:IsShown() then updateRow(row, false) end
    end
end

local function onUpdate(self, elapsed)
    throttle = throttle + elapsed
    if throttle < 0.1 then return end
    throttle = 0
    refresh()
end

-- ---------------------------------------------------------
-- Build / mover
-- ---------------------------------------------------------
local function build()
    if container then return end

    container = CreateFrame("Frame", "VCUI_ShamanTotems", UIParent)
    container:SetSize(150, 80)
    container:SetPoint("CENTER", UIParent, "CENTER", db().x, db().y)
    container:SetFrameStrata("MEDIUM")

    for _, t in ipairs(TOTEMS) do
        rows[t.key] = createRow(t)
    end

    container.mover = ns:CreateMover(container, {
        label  = L["|cffffffffTOTEMS|r"],
        db     = db(),
        width  = 160,
        height = 50,
        onMove = function(x, y)
            ns:Print(string.format(L["Totems: x=%.0f, y=%.0f"], x, y))
        end,
    })

    applyLayout()
end

local function setUnlocked(state)
    db().unlocked = state
    if not container then build() end
    if state then
        container:Show()
        container.mover:Show()
        applyLayout()
        refresh()
        ns:Print(L["Totem timer mover active. |cff9b6cffDrag|r or |cff9b6cffarrow keys|r (SHIFT = 5px)."])
    else
        container.mover:Hide()
        refresh()
        ns:Print(L["Totem timer mover disabled."])
    end
end

-- ---------------------------------------------------------
-- Class tool lifecycle (called by the Class Specific module for shamans)
-- ---------------------------------------------------------
local function onEnable()
    ensureDB()
    build()
    container:SetScript("OnUpdate", onUpdate)
    ns:RegisterEvent("PLAYER_TOTEM_UPDATE",   refresh)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
    refresh()
end

local function onDisable()
    ns:UnregisterEvent("PLAYER_TOTEM_UPDATE",   refresh)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", refresh)
    if container then
        container:SetScript("OnUpdate", nil)
        if container.mover then container.mover:Hide() end
        container:Hide()
    end
end

-- ---------------------------------------------------------
-- Options (Shaman tab)
-- ---------------------------------------------------------
local function getOptions()
    ensureDB()
    local isShaman = select(2, UnitClass("player")) == "SHAMAN"
    local items = {
        { type = "header", text = L["Totem Timer"] },
        { type = "desc",   text = L["|cffaaaaaaShows the remaining time of your four totems as bars or icons, with a warning when one is about to expire. The display hides itself while no totem is down.|r"] },
    }

    if not isShaman then
        items[#items + 1] = { type = "spacer", height = 4 }
        items[#items + 1] = { type = "desc", text = L["|cffff8800Only active while playing a Shaman.|r"] }
    end

    items[#items + 1] = { type = "spacer", height = 4 }
    items[#items + 1] = {
        type = "dropdown", label = L["Layout"],
        values = {
            { value = "bars",  text = L["Bars"]  },
            { value = "icons", text = L["Icons"] },
        },
        get = function() return db().layout end,
        set = function(_, v) db().layout = v; applyLayout(); refresh() end,
    }

    items[#items + 1] = { type = "header", text = L["Tracked totems"] }
    items[#items + 1] = { type = "toggle", label = L["Fire"],
        get = function() return db().showFire end,
        set = function(_, v) db().showFire = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Earth"],
        get = function() return db().showEarth end,
        set = function(_, v) db().showEarth = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Water"],
        get = function() return db().showWater end,
        set = function(_, v) db().showWater = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Air"],
        get = function() return db().showAir end,
        set = function(_, v) db().showAir = v; applyLayout(); refresh() end }

    items[#items + 1] = { type = "header", text = L["Appearance"] }
    items[#items + 1] = { type = "slider", label = L["Warning (seconds left)"],
        min = 1, max = 15, step = 1,
        get = function() return db().warnSeconds end,
        set = function(_, v) db().warnSeconds = v end }
    items[#items + 1] = { type = "slider", label = L["Bar width"],
        min = 80, max = 300, step = 5,
        get = function() return db().barWidth end,
        set = function(_, v) db().barWidth = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Bar height"],
        min = 10, max = 36, step = 1,
        get = function() return db().barHeight end,
        set = function(_, v) db().barHeight = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Icon size"],
        min = 18, max = 56, step = 1,
        get = function() return db().iconSize end,
        set = function(_, v) db().iconSize = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Spacing"],
        min = 0, max = 12, step = 1,
        get = function() return db().spacing end,
        set = function(_, v) db().spacing = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Font size"],
        min = 8, max = 24, step = 1,
        get = function() return db().fontSize end,
        set = function(_, v) db().fontSize = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Color the timer text"],
        get = function() return db().colorText end,
        set = function(_, v) db().colorText = v end }

    items[#items + 1] = { type = "spacer", height = 4 }
    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "button", label = L["Unlock / Position"], width = 200,
          onClick = function() setUnlocked(not db().unlocked) end },
        { type = "button", label = L["Reset position"], width = 200,
          onClick = function()
              db().x, db().y = -250, 0
              if container then
                  container:ClearAllPoints()
                  container:SetPoint("CENTER", UIParent, "CENTER", db().x, db().y)
              end
          end },
    } }

    return items
end

-- ---------------------------------------------------------
-- Register with the Class Specific module
-- ---------------------------------------------------------
csMod:RegisterClassTool("SHAMAN", {
    onEnable   = onEnable,
    onDisable  = onDisable,
    getOptions = getOptions,
})
