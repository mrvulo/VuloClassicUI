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

-- Representative spell ID per totem, so the picker can list the totems you KNOW
-- without you having to cast each one first. (TBC data from SUI's _TotemIcons.)
-- "Known" is checked by name lookup (GetSpellInfo by name = nil if not learned).
local TOTEM_IDS = {
    fire  = { 3599, 1535, 8187, 8227, 8181, 30706, 2894 },        -- Searing, Fire Nova, Magma, Flametongue, Frost Resist, Totem of Wrath, Fire Elemental
    earth = { 2484, 5730, 8071, 31634, 8143, 2062 },              -- Earthbind, Stoneclaw, Stoneskin, Strength of Earth, Tremor, Earth Elemental
    water = { 5394, 5675, 16190, 8166, 8170, 8184 },              -- Healing Stream, Mana Spring, Mana Tide, Poison Cleansing, Disease Cleansing, Fire Resist
    air   = { 8512, 8835, 8177, 10595, 15107, 6495, 25908, 3738 },-- Windfury, Grace of Air, Grounding, Nature Resist, Windwall, Sentry, Tranquil Air, Wrath of Air
}
local TOTEMIC_CALL_ID = 36936  -- "Totemic Call" (recall all totems) — middle-click

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
    if d.lastCast[t.key] then return d.lastCast[t.key] end
    -- fall back to the first totem of this element the player knows, so a click
    -- always casts something even before you pick one.
    for _, id in ipairs(TOTEM_IDS[t.key] or {}) do
        local name = GetSpellInfo(id)
        if name and GetSpellInfo(name) then return name end
    end
end

-- All totems of an element the player KNOWS (resolved to the highest-rank name),
-- merged with any learned-by-casting names. Used by the right-click picker.
local function knownTotemsFor(key)
    local out, seen = {}, {}
    -- only add a totem we can actually show an icon for (no empty squares)
    local function add(name)
        if not name or name == "" or seen[name] then return end
        if not select(3, GetSpellInfo(name)) then return end  -- no icon -> skip
        seen[name] = true
        out[#out + 1] = name
    end
    for _, id in ipairs(TOTEM_IDS[key] or {}) do
        local name = GetSpellInfo(id)
        if name and GetSpellInfo(name) then add(name) end       -- known by name
    end
    local learned = db().learned and db().learned[key]
    if learned then
        for name in pairs(learned) do add(name) end             -- learned by casting
    end
    table.sort(out)
    return out
end

-- Push the cast spell onto each secure button (out of combat only).
local function applyButtonSpells()
    if InCombatLockdown and InCombatLockdown() then pendingAttr = true; return end
    pendingAttr = false
    local recall = GetSpellInfo(TOTEMIC_CALL_ID) or ""
    for _, t in ipairs(TOTEMS) do
        local row = rows[t.key]
        if row then
            row:SetAttribute("spell", buttonSpell(t) or "")
            row:SetAttribute("spell3", recall)
        end
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
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    row:SetAttribute("type", "spell")    -- left/any click casts this element's totem (spell)
    row:SetAttribute("type2", "")         -- right-click: no cast -> opens the totem picker
    row:SetAttribute("type3", "spell")    -- middle-click: Totemic Call / recall all (spell3)
    row:SetAttribute("unit", "none")     -- totems self-cast: don't aim the spell at your target
    row:SetScript("PostClick", function(self, button)
        if button == "RightButton" then showTotemMenu(self.totem) end
    end)
    -- Hover a slot to open the icon picker (also reachable via right-click).
    row:HookScript("OnEnter", function(self) showTotemMenu(self.totem) end)

    -- WeakAura-style soft drop shadow behind the icon
    row.shadow = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.shadow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    row.shadow:SetBlendMode("BLEND")
    row.shadow:SetVertexColor(0, 0, 0, 0.7)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetTexture(totem.icon)

    -- action-bar style metal border BEHIND the icon, so the icon shows on top and
    -- only the slot frame rim is visible around it (tinted by state in updateRow)
    row.border = row:CreateTexture(nil, "BORDER")
    row.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")

    row.cd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cd:SetDrawEdge(false)
    if row.cd.SetDrawSwipe then row.cd:SetDrawSwipe(false) end   -- no swipe overlay (the timer text is the countdown)
    if row.cd.SetDrawBling then row.cd:SetDrawBling(false) end   -- no end-flash (it flickered when a totem hit 0)
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
    row.border:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -3, 3)
    row.border:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 3, -3)

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

            -- inset the icon when the frame is on, so the metal border rim shows
            local inset = d.shadowBorder and 3 or 0
            row.icon:ClearAllPoints()
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -inset)
            row.icon:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -inset, inset)
            row.icon:Show()
            row.cd:ClearAllPoints(); row.cd:SetAllPoints(row.icon)
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
    row.icon:SetTexture(icon or t.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- remaining time; 0 once the totem is gone or has expired
    local remaining = 0
    if have and duration and duration > 0 then
        remaining = (startTime + duration) - GetTime()
        if remaining < 0 then remaining = 0 end
    end

    -- treat <= 0 as "down" so there's no bright "0.0" frame before it dims
    if have and remaining > 0 then
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
        if warn then
            row.border:SetVertexColor(1, 0.4, 0.4)  -- expiring
        else
            row.border:SetVertexColor(1, 1, 1)       -- active = normal/bright
        end

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
            row.cd:Hide()  -- no cooldown swipe; the number is the countdown
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
        row.border:SetVertexColor(0.55, 0.55, 0.55)  -- not down = dimmed
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

-- Icon flyout: hovering (or right-clicking) a slot opens a column of totem ICONS
-- to pick from. It hides itself when the mouse leaves both it and the slot.
local flyout
showTotemMenu = function(t)
    local d = db()
    local names = knownTotemsFor(t.key)
    if #names == 0 then if flyout then flyout:Hide() end return end
    local set = d.sets[d.activeSet] or { fire = "", earth = "", water = "", air = "" }
    d.sets[d.activeSet] = set

    if not flyout then
        flyout = CreateFrame("Frame", "VCUI_TotemFlyout", UIParent, BackdropTemplateMixin and "BackdropTemplate")
        flyout:SetFrameStrata("DIALOG")
        flyout:SetClampedToScreen(true)
        if flyout.SetBackdrop then
            flyout:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            flyout:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
            flyout:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
        end
        flyout.btns = {}
        flyout:Hide()
        flyout:SetScript("OnUpdate", function(self)
            if not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then
                self:Hide()
            end
        end)
    end

    local size, pad = math.max(28, d.iconSize), 4
    for i, name in ipairs(names) do
        local b = flyout.btns[i]
        if not b then
            b = CreateFrame("Button", nil, flyout)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.frame = b:CreateTexture(nil, "BORDER")
            b.frame:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            b.frame:SetAllPoints(b)
            b.sel = b:CreateTexture(nil, "OVERLAY")
            b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
            b.sel:SetBlendMode("ADD"); b.sel:SetAllPoints(b); b.sel:Hide()
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            b:SetScript("OnClick", function(self)
                local dd = db()
                local s = dd.sets[dd.activeSet] or { fire = "", earth = "", water = "", air = "" }
                dd.sets[dd.activeSet] = s
                s[self.elementKey] = self.totemName
                applyButtonSpells(); refresh()
                flyout:Hide()
            end)
            flyout.btns[i] = b
        end
        local _, _, icon = GetSpellInfo(name)
        b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.totemName  = name
        b.elementKey = t.key
        b.sel:SetShown(set[t.key] == name)
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOP", flyout, "TOP", 0, -(pad + (i - 1) * (size + 2)))
        b:Show()
    end
    for i = #names + 1, #flyout.btns do flyout.btns[i]:Hide() end

    flyout:SetSize(size + pad * 2, #names * (size + 2) - 2 + pad * 2)
    flyout.anchor = rows[t.key]
    flyout:ClearAllPoints()
    if d.layout == "icons" then
        -- horizontal bar: drop the column straight down from the slot
        flyout:SetPoint("TOP", rows[t.key], "BOTTOM", 0, 1)
    else
        -- vertical bar: open the column to the right so it can't cover other slots
        flyout:SetPoint("LEFT", rows[t.key], "RIGHT", -1, 0)
    end
    flyout:Show()
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

-- Debug: /run VCUI_TotemDebug()  -> prints each slot's secure cast state.
function VCUI_TotemDebug()
    for _, t in ipairs(TOTEMS) do
        local row = rows[t.key]
        if not row then
            ns:Print(t.key .. ": no row")
        else
            ns:Print(string.format("%s | spell=[%s] type=[%s] unit=[%s] shown=%s mouse=%s w=%.0f",
                t.key, tostring(row:GetAttribute("spell")), tostring(row:GetAttribute("type")),
                tostring(row:GetAttribute("unit")), tostring(row:IsShown()),
                tostring(row:IsMouseEnabled()), row:GetWidth() or 0))
        end
    end
end

local function onEnable()
    ensureDB()
    build()
    container:SetScript("OnUpdate", onUpdate)
    ns:RegisterEvent("PLAYER_TOTEM_UPDATE",   learnActiveTotems)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",  applyPending)
    ns:RegisterEvent("SPELLS_CHANGED",        function() applyButtonSpells() end)
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

-- Rename the active set to a custom name (e.g. "PvP", "Magma", "Burst").
local function renameActiveSet(newName)
    local d = db()
    newName = tostring(newName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if newName == "" then return end
    local old = d.activeSet
    if newName == old or d.sets[newName] then return end  -- empty / unchanged / taken
    d.sets[newName] = d.sets[old]
    d.sets[old]     = nil
    for i, n in ipairs(d.setOrder) do
        if n == old then d.setOrder[i] = newName; break end
    end
    d.activeSet = newName
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
        { type = "desc",   text = L["|cffaaaaaa|cffffffffLeft-click|r an icon to (re)cast that element's totem, |cffffffffhover|r a slot to pick which totem from the icon list, |cffffffffmiddle-click|r to recall all totems. The icon border turns red just before the totem expires.|r"] },
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
    items[#items + 1] = { type = "editbox", label = L["Set name"], width = 280,
        get = function() return d.activeSet end,
        set = function(_, v) renameActiveSet(v); applyButtonSpells(); refresh(); rebuildOptions() end }
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
    items[#items + 1] = { type = "toggle", label = L["Icon border (action-bar style)"],
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
