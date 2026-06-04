-- =========================================================
-- VuloClassicUI / Modules / ShamanTotems
-- Shaman totem bar — plugs into the "Class Specific" module (Shaman tab).
-- Like TotemTimer but cleaner / easier to configure:
--   * timer bars or icons for the 4 elements (Fire/Earth/Water/Air)
--   * the icons are clickable SECURE buttons -> one click recasts the totem
--   * totems are learned automatically from what you cast (per element)
--   * per-element totem selection + named totem sets
--   * optional sound when a totem is about to expire
-- Reads GetTotemInfo(slot); casting goes through SecureActionButtonTemplate so
-- there is no taint. Secure attributes are only changed out of combat (queued
-- otherwise). Settings live under the Class Specific db (csMod.db.totems).
-- =========================================================
local _, ns = ...
local L = ns.L

local csMod = ns.modules and ns.modules.vtmanadisplay
if not csMod or not csMod.RegisterClassTool then return end

local TOTEM_DEFAULTS = {
    layout      = "icons",  -- "bars" | "icons"
    showFire    = true,
    showEarth   = true,
    showWater   = true,
    showAir     = true,
    warnSeconds = 5,
    colorText   = true,
    expirySound = true,
    shadowBorder = true,
    barWidth    = 150,
    barHeight   = 22,
    iconSize    = 36,
    spacing     = 4,
    fontSize    = 12,
    x           = -250,
    y           = 0,
    unlocked    = false,
    sets        = {},   -- [name] = { fire=spell, earth=spell, water=spell, air=spell }
    setOrder    = {},   -- ordered set names
    activeSet   = "",
    lastCast    = {},   -- [elementKey] = last totem name cast in that slot
    learned     = {},   -- [elementKey] = { [totemName]=true }
}

-- Slot order: Fire(1), Earth(2), Water(3), Air(4). Blizzard globals + fallback.
local TOTEMS = {
    { key = "fire",  slot = _G.FIRE_TOTEM_SLOT  or 1, toggle = "showFire",  label = "Fire",  color = { 0.95, 0.35, 0.10 }, icon = "Interface\\Icons\\Spell_Fire_SearingTotem" },
    { key = "earth", slot = _G.EARTH_TOTEM_SLOT or 2, toggle = "showEarth", label = "Earth", color = { 0.70, 0.50, 0.25 }, icon = "Interface\\Icons\\Spell_Nature_StoneClawTotem" },
    { key = "water", slot = _G.WATER_TOTEM_SLOT or 3, toggle = "showWater", label = "Water", color = { 0.20, 0.55, 0.95 }, icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem" },
    { key = "air",   slot = _G.AIR_TOTEM_SLOT   or 4, toggle = "showAir",   label = "Air",   color = { 0.60, 0.80, 0.95 }, icon = "Interface\\Icons\\Spell_Nature_InvisibilityTotem" },
}
local SLOT_KEY = {}
for _, t in ipairs(TOTEMS) do SLOT_KEY[t.slot] = t.key end

local WARN_COLOR  = { 1.0, 0.25, 0.25 }
local BAR_TEX     = "Interface\\Buttons\\WHITE8X8"
local SPARK_TEX   = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FONT        = "Fonts\\FRIZQT__.TTF"
local EXPIRE_SOUND = 567458  -- same alert used by the queue timer

local container
local rows         = {}
local throttle     = 0
local pendingAttr  = false  -- secure attr update queued for end of combat
local showTotemMenu         -- forward decl (defined after refresh)

-- ---------------------------------------------------------
-- Settings (created with defaults on first use)
-- ---------------------------------------------------------
local function ensureDB()
    local d = ns:ApplyDefaults(csMod.db.totems, TOTEM_DEFAULTS)
    if not next(d.sets) then
        d.sets["Default"] = { fire = "", earth = "", water = "", air = "" }
        d.setOrder = { "Default" }
        d.activeSet = "Default"
    end
    if not d.activeSet or not d.sets[d.activeSet] then
        d.activeSet = d.setOrder[1] or "Default"
    end
    csMod.db.totems = d
    return d
end
local function db() return csMod.db.totems end

-- Spell the button for this element should cast: the active set's choice, or
-- (auto) the last totem you actually cast in that element slot.
local function buttonSpell(t)
    local d = db()
    local set = d.sets[d.activeSet]
    local chosen = set and set[t.key]
    if chosen and chosen ~= "" then return chosen end
    return d.lastCast[t.key]
end

-- Push the cast spell onto each secure button (out of combat only).
local function applyButtonSpells()
    if InCombatLockdown and InCombatLockdown() then pendingAttr = true; return end
    pendingAttr = false
    for _, t in ipairs(TOTEMS) do
        local row = rows[t.key]
        if row then row:SetAttribute("spell1", buttonSpell(t) or "") end
    end
end

-- Learn the totems currently down (called on PLAYER_TOTEM_UPDATE).
local function learnActiveTotems()
    local d = db()
    local changed = false
    for _, t in ipairs(TOTEMS) do
        local have, name = GetTotemInfo(t.slot)
        if have and name and name ~= "" then
            if d.lastCast[t.key] ~= name then d.lastCast[t.key] = name; changed = true end
            d.learned[t.key] = d.learned[t.key] or {}
            if not d.learned[t.key][name] then d.learned[t.key][name] = true; changed = true end
        end
    end
    if changed then applyButtonSpells() end
end

-- ---------------------------------------------------------
-- Row creation (a secure button with icon + timer visuals)
-- ---------------------------------------------------------
local function createRow(totem)
    local row = CreateFrame("Button", "VCUI_TotemBtn_" .. totem.key, container, "SecureActionButtonTemplate")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetAttribute("type1", "spell")  -- left-click casts (spell1 set later, out of combat)
    row:SetAttribute("type2", "")        -- right-click: no cast -> opens the totem picker
    row:SetScript("PostClick", function(self, button)
        if button == "RightButton" then showTotemMenu(self.totem) end
    end)

    -- WeakAura-style soft drop shadow behind the icon
    row.shadow = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.shadow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    row.shadow:SetBlendMode("BLEND")
    row.shadow:SetVertexColor(0, 0, 0, 0.7)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetTexture(totem.icon)

    -- thin dark border around the icon (WeakAura look)
    row.border = CreateFrame("Frame", nil, row, BackdropTemplateMixin and "BackdropTemplate")
    if row.border.SetBackdrop then
        row.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1.2 })
        row.border:SetBackdropBorderColor(0, 0, 0, 1)
    end

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

    -- a subtle hover highlight so it reads as clickable
    row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- shadow + border follow the icon's size/position
    row.shadow:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -5, 5)
    row.shadow:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 5, -5)
    row.border:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    row.border:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)

    row.totem  = totem
    row.warned = false
    return row
end

-- ---------------------------------------------------------
-- Layout (combat-guarded: secure frames can't move in combat)
-- ---------------------------------------------------------
local function applyLayout()
    if not container then return end
    if InCombatLockdown and InCombatLockdown() then pendingAttr = true; return end
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

    -- WeakAura-style shadow + border per icon (runs out of combat -> safe)
    for _, t in ipairs(active) do
        local row = rows[t.key]
        if row then
            row.shadow:SetShown(d.shadowBorder)
            row.border:SetShown(d.shadowBorder)
        end
    end
end

-- ---------------------------------------------------------
-- Per-row display update (combat-safe; only textures/text)
-- ---------------------------------------------------------
local function updateRow(row, preview)
    local d = db()
    local t = row.totem

    -- Icon to show: the active totem's icon, else the configured/last spell's
    -- icon (so you can see what a click would cast), else the element default.
    local have, _, startTime, duration, icon = GetTotemInfo(t.slot)
    if preview then have, startTime, duration = true, GetTime(), 60 end

    if not (have and icon) then
        local spell = buttonSpell(t)
        local sIcon = spell and select(3, GetSpellInfo(spell))
        icon = sIcon or t.icon
    end
    row.icon:SetTexture(icon or t.icon)

    if have and duration and duration > 0 then
        local remaining = (startTime + duration) - GetTime()
        if remaining < 0 then remaining = 0 end
        local frac = remaining / duration
        if frac > 1 then frac = 1 end
        local warn = remaining <= d.warnSeconds

        -- expiry sound: once as it crosses into the warning window
        if warn and not row.warned then
            row.warned = true
            if d.expirySound and not preview then PlaySoundFile(EXPIRE_SOUND, "Master") end
        elseif not warn then
            row.warned = false
        end

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
        -- No totem down -> dimmed icon (still clickable to cast)
        row.warned = false
        row.icon:SetDesaturated(true)
        row.icon:SetVertexColor(0.55, 0.55, 0.55)
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
-- Refresh / loop. The bar is always shown (so you can always click to cast).
-- ---------------------------------------------------------
local function refresh()
    if not container then return end
    -- The container parents secure buttons, so Show() is protected in combat.
    -- Only ever show it out of combat; it then stays shown across the fight.
    if not container:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
        container:Show()
    end
    local preview = db().unlocked
    for _, t in ipairs(TOTEMS) do
        local row = rows[t.key]
        if row and row:IsShown() then updateRow(row, preview) end
    end
end

-- Right-click picker: choose which totem this element's button casts.
showTotemMenu = function(t)
    local d = db()
    local set = d.sets[d.activeSet] or { fire = "", earth = "", water = "", air = "" }
    d.sets[d.activeSet] = set
    local entries = {
        { title = true, text = L[t.label] },
        { text = L["(auto: last cast)"],
          checked = function() return (set[t.key] or "") == "" end,
          func = function() set[t.key] = ""; applyButtonSpells(); refresh() end },
    }
    local names = {}
    if d.learned[t.key] then
        for name in pairs(d.learned[t.key]) do names[#names + 1] = name end
    end
    table.sort(names)
    if #names == 0 then
        entries[#entries + 1] = { text = L["|cff888888(cast a totem to add it here)|r"], disabled = true }
    else
        for _, name in ipairs(names) do
            entries[#entries + 1] = {
                text    = name,
                checked = function() return set[t.key] == name end,
                func    = function() set[t.key] = name; applyButtonSpells(); refresh() end,
            }
        end
    end
    ns:ShowPopupMenu(entries, rows[t.key])
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
    container:SetSize(150, 40)
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
    applyButtonSpells()
end

local function setUnlocked(state)
    if state and InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Not possible in combat."])
        return
    end
    db().unlocked = state
    if not container then build() end
    if state then
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
-- Apply queued layout / secure-attribute changes once combat ends.
local function applyPending()
    if pendingAttr then
        applyLayout()
        applyButtonSpells()
    end
end

local function onEnable()
    ensureDB()
    build()
    container:SetScript("OnUpdate", onUpdate)
    ns:RegisterEvent("PLAYER_TOTEM_UPDATE",   learnActiveTotems)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",  applyPending)
    learnActiveTotems()
    refresh()
end

local function onDisable()
    ns:UnregisterEvent("PLAYER_TOTEM_UPDATE",   learnActiveTotems)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", refresh)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",  applyPending)
    if container then
        container:SetScript("OnUpdate", nil)
        if container.mover then container.mover:Hide() end
        container:Hide()
    end
end

-- ---------------------------------------------------------
-- Set helpers
-- ---------------------------------------------------------
local function newSet()
    local d = db()
    local n, name = 1
    repeat
        name = "Set " .. n
        n = n + 1
    until not d.sets[name]
    d.sets[name] = { fire = "", earth = "", water = "", air = "" }
    d.setOrder[#d.setOrder + 1] = name
    d.activeSet = name
    applyButtonSpells()
end

local function deleteActiveSet()
    local d = db()
    if #d.setOrder <= 1 then return end  -- keep at least one
    local name = d.activeSet
    d.sets[name] = nil
    for i, n in ipairs(d.setOrder) do
        if n == name then table.remove(d.setOrder, i); break end
    end
    d.activeSet = d.setOrder[1]
    applyButtonSpells()
end

-- Re-render the current options page (keeps the active class tab).
local function rebuildOptions()
    if ns.UI and ns.UI.BuildOptionsPage then
        ns.UI:BuildOptionsPage("vtmanadisplay", ns.UI.currentTab)
    end
end

-- ---------------------------------------------------------
-- Options (Shaman tab)
-- ---------------------------------------------------------
local function getOptions()
    ensureDB()
    local d = db()
    local isShaman = select(2, UnitClass("player")) == "SHAMAN"
    local items = {
        { type = "header", text = L["Totem Bar"] },
        { type = "desc",   text = L["|cffaaaaaa|cffffffffLeft-click|r an icon to (re)cast that element's totem, |cffffffffright-click|r to pick which totem. Totems are learned from what you cast. A warning (and optional sound) plays before a totem expires.|r"] },
    }
    if not isShaman then
        items[#items + 1] = { type = "spacer", height = 4 }
        items[#items + 1] = { type = "desc", text = L["|cffff8800Only active while playing a Shaman.|r"] }
    end

    -- Sets
    items[#items + 1] = { type = "header", text = L["Totem set"] }
    local setValues = {}
    for _, name in ipairs(d.setOrder) do setValues[#setValues + 1] = { value = name, text = name } end
    items[#items + 1] = { type = "dropdown", label = L["Active set"],
        values = setValues,
        get = function() return d.activeSet end,
        set = function(_, v) d.activeSet = v; applyButtonSpells(); refresh(); rebuildOptions() end }
    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "button", label = L["New set"], width = 150,
          onClick = function() newSet(); rebuildOptions() end },
        { type = "button", label = L["Delete set"], width = 150,
          onClick = function() deleteActiveSet(); rebuildOptions() end },
    } }

    -- Which elements to show
    items[#items + 1] = { type = "header", text = L["Shown elements"] }
    items[#items + 1] = { type = "toggle", label = L["Fire"],
        get = function() return d.showFire end,
        set = function(_, v) d.showFire = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Earth"],
        get = function() return d.showEarth end,
        set = function(_, v) d.showEarth = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Water"],
        get = function() return d.showWater end,
        set = function(_, v) d.showWater = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Air"],
        get = function() return d.showAir end,
        set = function(_, v) d.showAir = v; applyLayout(); refresh() end }

    -- Appearance
    items[#items + 1] = { type = "header", text = L["Appearance"] }
    items[#items + 1] = { type = "dropdown", label = L["Layout"],
        values = { { value = "icons", text = L["Icons"] }, { value = "bars", text = L["Bars"] } },
        get = function() return d.layout end,
        set = function(_, v) d.layout = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Sound before a totem expires"],
        get = function() return d.expirySound end,
        set = function(_, v) d.expirySound = v end }
    items[#items + 1] = { type = "toggle", label = L["Shadow border (WeakAura style)"],
        get = function() return d.shadowBorder end,
        set = function(_, v) d.shadowBorder = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Warning (seconds left)"],
        min = 1, max = 15, step = 1,
        get = function() return d.warnSeconds end,
        set = function(_, v) d.warnSeconds = v end }
    items[#items + 1] = { type = "slider", label = L["Icon size"],
        min = 18, max = 56, step = 1,
        get = function() return d.iconSize end,
        set = function(_, v) d.iconSize = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Bar width"],
        min = 80, max = 300, step = 5,
        get = function() return d.barWidth end,
        set = function(_, v) d.barWidth = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Bar height"],
        min = 10, max = 36, step = 1,
        get = function() return d.barHeight end,
        set = function(_, v) d.barHeight = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Spacing"],
        min = 0, max = 12, step = 1,
        get = function() return d.spacing end,
        set = function(_, v) d.spacing = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "slider", label = L["Font size"],
        min = 8, max = 24, step = 1,
        get = function() return d.fontSize end,
        set = function(_, v) d.fontSize = v; applyLayout(); refresh() end }
    items[#items + 1] = { type = "toggle", label = L["Color the timer text"],
        get = function() return d.colorText end,
        set = function(_, v) d.colorText = v end }

    items[#items + 1] = { type = "spacer", height = 4 }
    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "button", label = L["Unlock / Position"], width = 200,
          onClick = function() setUnlocked(not d.unlocked) end },
        { type = "button", label = L["Reset position"], width = 200,
          onClick = function()
              d.x, d.y = -250, 0
              if container and not (InCombatLockdown and InCombatLockdown()) then
                  container:ClearAllPoints()
                  container:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
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
