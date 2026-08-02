-- Shaman totem bar (class tool).
local _, ns = ...
local L = ns.L

local csMod = ns.modules and ns.modules.vtmanadisplay
if not csMod or not csMod.RegisterClassTool then return end

local TOTEM_DEFAULTS = {
    layout      = "icons",
    style       = "vulo",
    flyoutDirection = "auto",
    flyoutInCombat  = true,
    hoverTooltip    = true,
    showFire    = true,
    showEarth   = true,
    showWater   = true,
    showAir     = true,
    warnSeconds = 5,
    colorText   = true,
    expirySound = true,
    dimOutOfRange = true,
    shadowBorder = true,
    barWidth    = 150,
    barHeight   = 22,
    iconSize    = 36,
    spacing     = 4,
    fontSize    = 12,
    x           = -250,
    y           = 0,
    unlocked    = false,
    sets        = {},
    setOrder    = {},
    activeSet   = "",
    lastCast    = {},
    learned     = {},
}

local TOTEMS = {
    { key = "fire",  slot = _G.FIRE_TOTEM_SLOT  or 1, toggle = "showFire",  label = "Fire",  color = { 0.95, 0.35, 0.10 }, icon = "Interface\\Icons\\Spell_Fire_SearingTotem" },
    { key = "earth", slot = _G.EARTH_TOTEM_SLOT or 2, toggle = "showEarth", label = "Earth", color = { 0.70, 0.50, 0.25 }, icon = "Interface\\Icons\\Spell_Nature_StoneClawTotem" },
    { key = "water", slot = _G.WATER_TOTEM_SLOT or 3, toggle = "showWater", label = "Water", color = { 0.20, 0.55, 0.95 }, icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem" },
    { key = "air",   slot = _G.AIR_TOTEM_SLOT   or 4, toggle = "showAir",   label = "Air",   color = { 0.60, 0.80, 0.95 }, icon = "Interface\\Icons\\Spell_Nature_InvisibilityTotem" },
}
local SLOT_KEY = {}
for _, t in ipairs(TOTEMS) do SLOT_KEY[t.slot] = t.key end

-- Representative spell IDs per element; "known" = GetSpellInfo(name) resolves.
local TOTEM_IDS = {
    fire  = { 3599, 1535, 8187, 8227, 8181, 30706, 2894 },        -- Searing, Fire Nova, Magma, Flametongue, Frost Resist, Totem of Wrath, Fire Elemental
    earth = { 2484, 5730, 8071, 8075, 8143, 2062 },               -- Earthbind, Stoneclaw, Stoneskin, Strength of Earth, Tremor, Earth Elemental
    water = { 5394, 5675, 16190, 8166, 8170, 8184 },              -- Healing Stream, Mana Spring, Mana Tide, Poison Cleansing, Disease Cleansing, Fire Resist
    air   = { 8512, 8835, 8177, 10595, 15107, 6495, 25908, 3738 },-- Windfury, Grace of Air, Grounding, Nature Resist, Windwall, Sentry, Tranquil Air, Wrath of Air
}
-- Totemic Call / Recall (all totems, middle-click) - 36936 on TBC and Classic Era.
local TOTEMIC_CALL_IDS = { 36936 }
local function totemicRecallSpell()
    for _, id in ipairs(TOTEMIC_CALL_IDS) do
        if GetSpellInfo(id) and (not IsSpellKnown or IsSpellKnown(id)) then return id end
    end
end

-- The multi-cast calls summon a whole saved totem set at once. They exist from
-- Wrath onwards; on the builds this addon ships for GetSpellInfo returns nil for
-- all three, so nothing below ever comes into being there.
-- Deliberately NOT part of TOTEMS: a call has no totem slot, no timer and no
-- choice of totem, so leaving it out means every existing loop over TOTEMS skips
-- it without needing a single guard.
local CALL_IDS = { 66842, 66843, 66844 }   -- Elements, Ancestors, Spirits
local function callSpell()
    for _, id in ipairs(CALL_IDS) do
        if GetSpellInfo(id) and (not IsSpellKnown or IsSpellKnown(id)) then return id end
    end
end
-- No toggle on purpose. Knowing the spell IS the switch; an option would sit
-- dead in the settings for every player on a build that has no such spell.
-- No `label` field: the four entries above carry one and nothing in this file
-- ever reads it. The tooltip takes its text from the spell itself.
local CALL = {
    key = "call",
    color = { 0.85, 0.75, 0.35 }, icon = "Interface\\Icons\\Spell_Nature_TremorTotem",
    call = true, spellFn = callSpell,
}

-- Totemic Recall as its own VISIBLE button, only where the client's native
-- totem bar shows one (Wrath). On TBC and Era it stays on middle-click of the
-- element buttons -- the shipped variants keep their look. Same `call` shape
-- as above, so every totem-only code path skips it for the same reason.
local RECALL = {
    key = "recall",
    color = { 0.55, 0.85, 0.55 }, icon = "Interface\\Icons\\Spell_Unused",
    call = true, spellFn = totemicRecallSpell,
}

local WARN_COLOR  = { 1.0, 0.25, 0.25 }
local BAR_TEX     = "Interface\\Buttons\\WHITE8X8"
local SPARK_TEX   = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FONT        = "Fonts\\FRIZQT__.TTF"
local EXPIRE_SOUND = 567458

local function isVulo() return (csMod.db.totems and csMod.db.totems.style) ~= "classic" end
local function fontPath()
    if isVulo() and ns.UI and ns.UI.FONT_PATH then return ns.UI.FONT_PATH end
    return FONT
end

local container
local rows         = {}
local throttle     = 0
local pendingAttr  = false  -- secure attr update queued for end of combat
local showTotemMenu  -- forward decls (upvalue order matters)
local rebuildFlyouts
local paintTotemTooltip
local hoverBtn

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

local function buttonSpell(t)
    local d = db()
    local set = d.sets[d.activeSet]
    local chosen = set and set[t.key]
    if chosen and chosen ~= "" then return chosen end
    if d.lastCast[t.key] then return d.lastCast[t.key] end
    for _, id in ipairs(TOTEM_IDS[t.key] or {}) do
        local name = GetSpellInfo(id)
        if name and GetSpellInfo(name) then return name end
    end
end

local function knownTotemsFor(key)
    local out, seen = {}, {}
    local function add(name)
        if not name or name == "" or seen[name] then return end
        if not select(3, GetSpellInfo(name)) then return end
        seen[name] = true
        out[#out + 1] = name
    end
    for _, id in ipairs(TOTEM_IDS[key] or {}) do
        local name = GetSpellInfo(id)
        if name and GetSpellInfo(name) then add(name) end
    end
    local learned = db().learned and db().learned[key]
    if learned then
        for name in pairs(learned) do add(name) end
    end
    table.sort(out)
    return out
end

-- Ranked display names from GetTotemInfo are not castable; reduce to the base name (casts the highest rank).
local function castableName(name, key)
    if not name or name == "" then return name end
    for _, id in ipairs(TOTEM_IDS[key] or {}) do
        local base = GetSpellInfo(id)
        if base and (name == base or name:find(base, 1, true) == 1) then
            return base
        end
    end
    return name
end

-- Cast by numeric spell ID: this client is unreliable casting totems by name. Out of combat only.
local function applyButtonSpells()
    if InCombatLockdown and InCombatLockdown() then pendingAttr = true; return end
    pendingAttr = false
    for _, t in ipairs(TOTEMS) do
        local row = rows[t.key]
        if row then
            local name = castableName(buttonSpell(t), t.key)
            local id   = name and select(7, GetSpellInfo(name))
            row:SetAttribute("*spell1", id or name)
            row:SetAttribute("*spell3", totemicRecallSpell())
        end
    end
    -- The call button casts by id and has nothing on middle-click: recall would
    -- undo exactly what it just summoned.
    if rows.call then
        local id = callSpell()
        rows.call:SetAttribute("*spell1", id)
        rows.call:SetAttribute("*spell3", nil)
        -- paintTotemTooltip reads totemName first; without it the tooltip would
        -- fall through to buttonSpell(), which only knows totems.
        rows.call.totemName = id and GetSpellInfo(id) or nil
    end
    if rows.recall then
        local id = totemicRecallSpell()
        rows.recall:SetAttribute("*spell1", id)
        rows.recall:SetAttribute("*spell3", nil)
        rows.recall.totemName = id and GetSpellInfo(id) or nil
    end
end

local function learnActiveTotems()
    local d = db()
    local changed = false
    for _, t in ipairs(TOTEMS) do
        local have, name = GetTotemInfo(t.slot)
        if have and name and name ~= "" then
            name = castableName(name, t.key)
            if d.lastCast[t.key] ~= name then d.lastCast[t.key] = name; changed = true end
            d.learned[t.key] = d.learned[t.key] or {}
            if not d.learned[t.key][name] then d.learned[t.key][name] = true; changed = true end
        end
    end
    if changed then applyButtonSpells() end
end

local function createRow(totem)
    -- Secure enter/leave: the flyout parents protected buttons, so only secure snippets may show/move it in combat.
    local row = CreateFrame("Button", "VCUI_TotemBtn_" .. totem.key, container,
        "SecureActionButtonTemplate,SecureHandlerEnterLeaveTemplate")
    row:RegisterForClicks("AnyUp", "AnyDown")
    row:SetAttribute("_onenter", [=[
        if self:GetAttribute("combatlock") == 1 and self:GetAttribute("flyincombat") == 0 then
            return
        end
        for i = 1, 4 do
            local o = self:GetFrameRef("fly" .. i)
            if o then o:Hide() end
        end
        local fl = self:GetFrameRef("flyout")
        if fl then
            fl:ClearAllPoints()
            fl:SetPoint(self:GetAttribute("flypoint") or "LEFT", self,
                        self:GetAttribute("flyrelpoint") or "RIGHT", 0, 0)
            fl:Show()
        end
    ]=])
    -- Secure mouse-out close: runs in the restricted environment, so it works in combat too.
    row:SetAttribute("_onleave", [=[
        local fl = self:GetFrameRef("flyout")
        if fl and fl:IsShown() and fl.IsUnderMouse and not fl:IsUnderMouse(true) then
            fl:Hide()
        end
    ]=])
    -- driver feeds combatlock as numbers 1/0
    if RegisterAttributeDriver then
        RegisterAttributeDriver(row, "combatlock", "[combat] 1; 0")
    end
    -- Close the picker after a cast; right-click is exempt (it is what opens the picker).
    if SecureHandlerWrapScript then
        SecureHandlerWrapScript(row, "OnClick", row, [=[
            if not down and button ~= "RightButton" then
                local fl = self:GetFrameRef("flyout")
                if fl then fl:Hide() end
            end
        ]=])
    end
    -- This client only fires the protected cast through the wildcard attributes (*type1/*spell1).
    row:SetAttribute("*type1", "spell")
    row:SetAttribute("*type3", "spell")
    row:SetScript("PostClick", function(self, button, down)
        -- A call has no choice of totem, so it gets no flyout and no menu.
        if self.totem.call then return end
        if button == "RightButton" and not down then showTotemMenu(self.totem) end
    end)
    row:HookScript("OnEnter", function(self)
        if not self.totem.call then showTotemMenu(self.totem) end
        paintTotemTooltip(self)
    end)
    row:HookScript("OnLeave", function(self)
        if hoverBtn == self then hoverBtn = nil end
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)

    row.shadow = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.shadow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    row.shadow:SetBlendMode("BLEND")
    row.shadow:SetVertexColor(0, 0, 0, 0.7)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetTexture(totem.icon)

    row.border = row:CreateTexture(nil, "BORDER")
    row.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")

    row.ring = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.ring:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    row.ring:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    row.ring:SetColorTexture(0.25, 0.25, 0.3, 1)
    if row.ring.SetSnapToPixelGrid then
        row.ring:SetSnapToPixelGrid(false); row.ring:SetTexelSnappingBias(0)
    end
    if row.icon.SetSnapToPixelGrid then
        row.icon:SetSnapToPixelGrid(false); row.icon:SetTexelSnappingBias(0)
    end
    row.ring:Hide()
    row.elem = row:CreateTexture(nil, "OVERLAY")
    row.elem:SetHeight(2)
    row.elem:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMLEFT", 0, 0)
    row.elem:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 0, 0)
    row.elem:SetColorTexture(totem.color[1], totem.color[2], totem.color[3], 0.9)
    row.elem:Hide()

    -- No Cooldown frame: hiding a child frame every tick from insecure code taints the secure button.

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

    row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    row.shadow:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -5, 5)
    row.shadow:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 5, -5)
    row.border:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -3, 3)
    row.border:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 3, -3)

    row.totem  = totem
    row.warned = false
    return row
end

local function applyLayout()
    if not container then return end
    if InCombatLockdown and InCombatLockdown() then pendingAttr = true; return end
    local d = db()

    local active = {}
    for _, t in ipairs(TOTEMS) do
        if rows[t.key] then active[#active + 1] = t end
    end
    -- Last, so the four elements keep the order players know.
    if rows.call   then active[#active + 1] = CALL   end
    if rows.recall then active[#active + 1] = RECALL end

    if #active == 0 then
        container:SetSize(1, 1)
        return
    end

    local vulo = isVulo()
    local zoom = vulo and 0.07 or 0.08

    if d.layout == "icons" then
        local s = d.iconSize
        for i, t in ipairs(active) do
            local row = rows[t.key]
            row:ClearAllPoints()
            row:SetSize(s, s)
            row:SetPoint("LEFT", container, "LEFT", (i - 1) * (s + d.spacing), 0)

            local inset = vulo and 1 or (d.shadowBorder and 3 or 0)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -inset)
            row.icon:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -inset, inset)
            row.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            row.icon:Show()
            row.bg:Hide(); row.fill:Hide(); row.spark:Hide()

            row.time:ClearAllPoints()
            row.time:SetPoint("BOTTOM", row, "BOTTOM", 0, 1)
            row.time:SetFont(fontPath(), d.fontSize, "OUTLINE")
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
            row.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            row.icon:Show()

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
            row.time:SetFont(fontPath(), d.fontSize, "OUTLINE")
        end
        container:SetSize(iconW + w, #active * h + (#active - 1) * d.spacing)
    end

    for _, t in ipairs(active) do
        local row = rows[t.key]
        if row then
            row.shadow:SetShown(not vulo and d.shadowBorder)
            row.border:SetShown(not vulo and d.shadowBorder)
            row.ring:SetShown(vulo)
            row.elem:SetShown(vulo and d.layout == "icons")
        end
    end
end

-- Range to a totem cannot be measured on this client: there is no position for
-- a totem, only GetTotemInfo's timer. What IS observable is the aura the totem
-- pulses onto you, which drops a few seconds after you walk out of its radius.
--
-- Self-calibrating, so it needs no per-spell table: the first time a totem's
-- aura is seen we remember that this totem grants one. From then on, aura gone
-- = out of range. A totem whose aura is never seen (Searing, Magma, Tremor and
-- the other non-buffing ones) is simply never dimmed, because for those we
-- genuinely cannot tell -- better silent than wrong.
-- Rescanned only when the player's auras actually changed (UNIT_AURA sets the
-- flag); the 0.1s ticker used to walk all 40 slots on every tick while idle.
local playerAuraIcons = {}
local playerAurasDirty = true
local function refreshPlayerAuraIcons()
    if not playerAurasDirty then return end
    playerAurasDirty = false
    wipe(playerAuraIcons)
    for i = 1, 40 do
        local name, icon = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if icon then playerAuraIcons[icon] = true end
    end
end
local function onPlayerAura(_, unit)
    if unit == "player" then playerAurasDirty = true end
end

local totemSeen = {}   -- slot -> { start = <cast time>, saw = <aura observed> }

local function totemInRange(t, have, startTime, icon)
    if not (have and icon) then return true end
    local st = totemSeen[t.slot]
    if not st or st.start ~= startTime then
        st = { start = startTime, saw = false }
        totemSeen[t.slot] = st
    end
    if playerAuraIcons[icon] then
        st.saw = true
        return true
    end
    return not st.saw      -- never seen an aura for it -> unknowable -> leave lit
end

local function updateRow(row, preview)
    local d = db()
    local t = row.totem

    -- A call is an ability, not a totem: it has no slot to ask about and no
    -- duration to run down. Everything below describes a totem's life and none
    -- of it applies -- including GetTotemInfo, which would be handed a nil slot.
    if t.call then
        local spell = t.spellFn and t.spellFn() or callSpell()
        row.icon:SetTexture((spell and select(3, GetSpellInfo(spell))) or t.icon)
        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 1, 1)
        row.border:SetVertexColor(1, 1, 1)
        row.ring:SetColorTexture(t.color[1], t.color[2], t.color[3], 1)
        row.elem:SetColorTexture(t.color[1], t.color[2], t.color[3], 0.9)
        row.time:SetText("")
        row.time:Hide()
        if d.layout ~= "icons" then row.fill:Hide(); row.spark:Hide() end
        return
    end

    local have, _, startTime, duration, icon = GetTotemInfo(t.slot)
    if preview then have, startTime, duration = true, GetTime(), 60 end

    if not (have and icon) then
        local spell = buttonSpell(t)
        local sIcon = spell and select(3, GetSpellInfo(spell))
        icon = sIcon or t.icon
    end
    row.icon:SetTexture(icon or t.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    local remaining = 0
    if have and duration and duration > 0 then
        remaining = (startTime + duration) - GetTime()
        if remaining < 0 then remaining = 0 end
    end

    if have and remaining > 0 then
        local frac = remaining / duration
        if frac > 1 then frac = 1 end
        local warn = remaining <= d.warnSeconds

        if warn and not row.warned then
            row.warned = true
            if d.expirySound and not preview then PlaySoundFile(EXPIRE_SOUND, "Master") end
        elseif not warn then
            row.warned = false
        end

        -- Out of range: colour drains but the timer keeps running, so the totem
        -- still reads as active - you just cannot see the difference at a glance
        -- between "expired" and "too far away", which is the point.
        local inRange = true
        if d.dimOutOfRange and not preview then
            inRange = totemInRange(t, have, startTime, icon)
        end
        row.icon:SetDesaturated(not inRange)
        if inRange then
            row.icon:SetVertexColor(1, 1, 1)
            if warn then
                row.border:SetVertexColor(1, 0.4, 0.4)
                row.ring:SetColorTexture(WARN_COLOR[1], WARN_COLOR[2], WARN_COLOR[3], 1)
            else
                row.border:SetVertexColor(1, 1, 1)
                row.ring:SetColorTexture(t.color[1], t.color[2], t.color[3], 1)
            end
            row.elem:SetColorTexture(t.color[1], t.color[2], t.color[3], 0.9)
        else
            row.icon:SetVertexColor(0.5, 0.5, 0.5)
            row.border:SetVertexColor(0.5, 0.5, 0.5)
            row.ring:SetColorTexture(0.28, 0.28, 0.32, 1)
            row.elem:SetColorTexture(t.color[1], t.color[2], t.color[3], 0.35)
        end

        if remaining < 10 then
            row.time:SetText(string.format("%.1f", remaining))
        else
            row.time:SetText(string.format("%d", remaining + 0.5))
        end
        row.time:Show()
        if not inRange then
            row.time:SetTextColor(0.6, 0.6, 0.62)
        elseif d.colorText and warn then
            row.time:SetTextColor(WARN_COLOR[1], WARN_COLOR[2], WARN_COLOR[3])
        else
            row.time:SetTextColor(1, 1, 1)
        end

        if d.layout ~= "icons" then
            local fw = d.barWidth * frac
            if fw < 1 then fw = 1 end
            row.fill:SetWidth(fw)
            if not inRange then
                row.fill:SetVertexColor(0.45, 0.45, 0.48, 0.9)
            elseif warn then
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
        row.warned = false
        row.icon:SetDesaturated(true)
        row.icon:SetVertexColor(0.55, 0.55, 0.55)
        row.border:SetVertexColor(0.55, 0.55, 0.55)
        row.ring:SetColorTexture(0.22, 0.22, 0.26, 1)
        row.elem:SetColorTexture(t.color[1], t.color[2], t.color[3], 0.35)
        row.time:SetText("")
        row.time:Hide()
        if d.layout ~= "icons" then
            row.fill:Hide()
            row.spark:Hide()
        end
    end
end

local function refresh()
    if not container then return end
    if db().dimOutOfRange then refreshPlayerAuraIcons() end
    -- container parents secure buttons -> only Show() out of combat
    if not container:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
        container:Show()
    end
    local preview = db().unlocked or ns:IsMoverEditMode()
    for _, t in ipairs(TOTEMS) do
        local row = rows[t.key]
        if row and row:IsShown() then updateRow(row, preview) end
    end
    if rows.call   and rows.call:IsShown()   then updateRow(rows.call, preview)   end
    if rows.recall and rows.recall:IsShown() then updateRow(rows.recall, preview) end
    if hoverBtn then
        if GameTooltip and GameTooltip:IsOwned(hoverBtn) and hoverBtn:IsVisible() then
            paintTotemTooltip(hoverBtn)
        else
            hoverBtn = nil
        end
    end
end

local function fmtCD(s)
    if s >= 60 then return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60)) end
    return string.format("%ds", math.ceil(s))
end

local TIP_ANCHOR = { BOTTOM = "ANCHOR_BOTTOM", TOP = "ANCHOR_TOP",
                     LEFT = "ANCHOR_LEFT", RIGHT = "ANCHOR_RIGHT" }

paintTotemTooltip = function(btn)
    if db().hoverTooltip == false or not GameTooltip then return end
    local name = btn.totemName
        or (btn.totem and castableName(buttonSpell(btn.totem), btn.totem.key))
    if not name or name == "" then return end
    local id = select(7, GetSpellInfo(name))
    hoverBtn = btn
    local anchor = "ANCHOR_RIGHT"
    if btn.totem then
        anchor = TIP_ANCHOR[btn:GetAttribute("flypoint")] or "ANCHOR_BOTTOM"
    end
    -- The remaining-cooldown line is recomputed while the mouse rests here, so
    -- the tooltip is opened rather than described.
    if not ns.UI:OpenTooltip(btn, anchor) then return end
    GameTooltip:SetText(name, 1, 1, 1)
    local start, dur = GetSpellCooldown(id or name)
    if start and dur and start > 0 and dur > 1.5 then  -- > 1.5 filters the GCD
        local remain = (start + dur) - GetTime()
        if remain > 0 then
            GameTooltip:AddLine((_G.COOLDOWN_REMAINING or "Cooldown remaining:")
                .. " " .. fmtCD(remain), 1, 0.35, 0.35)
        end
    end
    GameTooltip:Show()
end

-- Icon flyout: one panel per element, fully pre-built out of combat (button geometry/attributes are protected).
local flyouts = {}

-- This client lacks the template :SetFrameRef method; fall back through every known mechanism.
local function setSecureRef(owner, label, target)
    if SecureHandlerSetFrameRef then
        SecureHandlerSetFrameRef(owner, label, target)
    elseif owner.SetFrameRef then
        owner:SetFrameRef(label, target)
    elseif GetFrameHandle then
        owner:SetAttribute("frameref-" .. label, GetFrameHandle(target))
    end
end

local function ensureFlyout(key)
    local fl = flyouts[key]
    if fl then return fl end
    fl = CreateFrame("Frame", "VCUI_TotemFlyout_" .. key, UIParent,
        BackdropTemplateMixin and "SecureHandlerEnterLeaveTemplate,BackdropTemplate"
                               or "SecureHandlerEnterLeaveTemplate")
    fl:SetFrameStrata("DIALOG")
    if fl.SetBackdrop then
        fl:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    end
    fl:SetAttribute("_onleave", [=[
        if self.IsUnderMouse and not self:IsUnderMouse(true) then
            self:Hide()
        end
    ]=])
    fl.btns  = {}
    fl.count = 0
    fl:Hide()
    fl:SetScript("OnUpdate", function(self)
        -- out-of-combat backup; in combat the secure _onleave snippets close it
        if InCombatLockdown and InCombatLockdown() then return end
        if not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then
            self:Hide()
        end
    end)
    flyouts[key] = fl
    return fl
end

local function styleFlyoutPanel(fl)
    if not fl.SetBackdropColor then return end
    local vulo = isVulo()
    if vulo then
        local bg = ns.COLORS and ns.COLORS.bg
        local bd = ns.COLORS and (ns.COLORS.accentDim or ns.COLORS.border)
        if bg then fl:SetBackdropColor(bg.r, bg.g, bg.b, 0.96)
        else fl:SetBackdropColor(0.05, 0.05, 0.08, 0.96) end
        if bd then fl:SetBackdropBorderColor(bd.r, bd.g, bd.b, 1)
        else fl:SetBackdropBorderColor(0.3, 0.3, 0.35, 1) end
        if not fl._vcShadow and ns.UI and ns.UI.CreateShadow then
            ns.UI:CreateShadow(fl)
        end
    else
        fl:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
        fl:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    end
    if fl._vcShadow then
        for _, t in ipairs(fl._vcShadow) do t:SetShown(vulo) end
    end
end

local function styleFlyoutButton(b, selected)
    local vulo = isVulo()
    b.frame:SetShown(not vulo)
    b.ring:SetShown(vulo)
    local zoom = vulo and 0.07 or 0.08
    b.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    local inset = vulo and 1 or 3
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
    if vulo then
        b.sel:Hide()
        local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
        if selected then
            b.ring:SetColorTexture(ac.r, ac.g, ac.b, 1)
        else
            b.ring:SetColorTexture(0.22, 0.22, 0.26, 1)
        end
        b._vcuiSelected = selected and true or false
    else
        b.sel:SetShown(selected and true or false)
    end
end

-- Protected operations -> out of combat only; callers defer via pendingAttr.
local function rebuildFlyout(t)
    if InCombatLockdown and InCombatLockdown() then pendingAttr = true; return end
    local fl = ensureFlyout(t.key)
    local d = db()
    local names = knownTotemsFor(t.key)
    fl.count = #names

    local slot = rows[t.key]
    local dir = d.flyoutDirection or "auto"
    local p, rp
    if dir == "up" then p, rp = "BOTTOM", "TOP"
    elseif dir == "down"  then p, rp = "TOP", "BOTTOM"
    elseif dir == "left"  then p, rp = "RIGHT", "LEFT"
    elseif dir == "right" then p, rp = "LEFT", "RIGHT"
    elseif slot then
        if d.layout == "icons" then
            local _, sy = slot:GetCenter()
            local h = UIParent:GetHeight()
            if sy and h and sy < h * 0.5 then p, rp = "BOTTOM", "TOP" else p, rp = "TOP", "BOTTOM" end
        else
            local sx = slot:GetCenter()
            local w = UIParent:GetWidth()
            if sx and w and sx > w * 0.5 then p, rp = "RIGHT", "LEFT" else p, rp = "LEFT", "RIGHT" end
        end
    end
    p, rp = p or "LEFT", rp or "RIGHT"
    local upwards = (p == "BOTTOM")

    local size, pad = math.max(28, d.iconSize), 4
    for i, name in ipairs(names) do
        local b = fl.btns[i]
        if not b then
            b = CreateFrame("Button", nil, fl,
                "SecureActionButtonTemplate,SecureHandlerEnterLeaveTemplate")
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:SetAttribute("*type1", "spell")
            b:SetAttribute("_onleave", [=[
                local fp = self:GetParent()
                if fp and fp.IsUnderMouse and not fp:IsUnderMouse(true) then
                    fp:Hide()
                end
            ]=])
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if b.icon.SetSnapToPixelGrid then
                b.icon:SetSnapToPixelGrid(false); b.icon:SetTexelSnappingBias(0)
            end
            b.frame = b:CreateTexture(nil, "BORDER")
            b.frame:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            b.frame:SetAllPoints(b)
            b.ring = b:CreateTexture(nil, "BACKGROUND", nil, -1)
            b.ring:SetAllPoints(b)
            b.ring:SetColorTexture(0.22, 0.22, 0.26, 1)
            if b.ring.SetSnapToPixelGrid then
                b.ring:SetSnapToPixelGrid(false); b.ring:SetTexelSnappingBias(0)
            end
            b.ring:Hide()
            b.sel = b:CreateTexture(nil, "OVERLAY")
            b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
            b.sel:SetBlendMode("ADD"); b.sel:SetAllPoints(b); b.sel:Hide()
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            b:HookScript("OnEnter", function(self)
                if self.ring:IsShown() and not self._vcuiSelected then
                    self.ring:SetColorTexture(1, 1, 1, 0.9)
                end
                paintTotemTooltip(self)
            end)
            b:HookScript("OnLeave", function(self)
                if self.ring:IsShown() and not self._vcuiSelected then
                    self.ring:SetColorTexture(0.22, 0.22, 0.26, 1)
                end
                if hoverBtn == self then hoverBtn = nil end
                if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
            end)
            -- Secure wrap hides the flyout after the cast (legal in combat); global form, template method missing.
            if SecureHandlerWrapScript then
                SecureHandlerWrapScript(b, "OnClick", fl, [=[
                    if not down then self:GetParent():Hide() end
                ]=])
            end
            b:SetScript("PostClick", function(self, button, down)
                if down then return end
                local dd = db()
                local s = dd.sets[dd.activeSet] or { fire = "", earth = "", water = "", air = "" }
                dd.sets[dd.activeSet] = s
                s[self.elementKey] = self.totemName
                applyButtonSpells(); refresh()
            end)
            fl.btns[i] = b
        end
        local _, _, icon, _, _, _, id = GetSpellInfo(name)
        b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.totemName  = name
        b.elementKey = t.key
        b:SetAttribute("*spell1", id or name)
        b:SetSize(size, size)
        b:ClearAllPoints()
        if upwards then
            b:SetPoint("BOTTOM", fl, "BOTTOM", 0, pad + (i - 1) * (size + 2))
        else
            b:SetPoint("TOP", fl, "TOP", 0, -(pad + (i - 1) * (size + 2)))
        end
        b:Show()
    end
    for i = #names + 1, #fl.btns do fl.btns[i]:Hide() end

    fl:SetSize(size + pad * 2, math.max(1, #names * (size + 2) - 2 + pad * 2))
    styleFlyoutPanel(fl)

    if slot then
        slot:SetAttribute("flypoint", p)
        slot:SetAttribute("flyrelpoint", rp)
        slot:SetAttribute("flyincombat", d.flyoutInCombat ~= false and 1 or 0)
        setSecureRef(slot, "flyout", fl)
    end
end

rebuildFlyouts = function()
    if InCombatLockdown and InCombatLockdown() then pendingAttr = true; return end
    for _, t in ipairs(TOTEMS) do
        if rows[t.key] then rebuildFlyout(t) end
    end
    -- every slot gets refs to all flyouts so its _onenter can close the others
    for _, t in ipairs(TOTEMS) do
        local slot = rows[t.key]
        if slot then
            for i, t2 in ipairs(TOTEMS) do
                if flyouts[t2.key] then
                    setSecureRef(slot, "fly" .. i, flyouts[t2.key])
                end
            end
        end
    end
end

showTotemMenu = function(t)
    -- The protected flyout is shown/moved by the slots' secure _onenter; this part only refreshes content.
    local inCombat = InCombatLockdown and InCombatLockdown()
    if not inCombat then
        rebuildFlyout(t)
    end
    local fl = flyouts[t.key]
    if not fl then return end
    if fl.count == 0 then
        if not inCombat then fl:Hide() end
        return
    end

    local d = db()
    local set = d.sets[d.activeSet] or { fire = "", earth = "", water = "", air = "" }
    d.sets[d.activeSet] = set

    for i = 1, fl.count do
        local b = fl.btns[i]
        if b then styleFlyoutButton(b, set[t.key] == b.totemName) end
    end

    fl.anchor = rows[t.key]
end

local function onUpdate(self, elapsed)
    throttle = throttle + elapsed
    if throttle < 0.1 then return end
    throttle = 0
    refresh()
end

local function build()
    if container then return end

    container = CreateFrame("Frame", "VCUI_ShamanTotems", UIParent)
    container:SetSize(150, 40)
    container:SetPoint("CENTER", UIParent, "CENTER", db().x, db().y)
    container:SetFrameStrata("MEDIUM")

    -- Never Show/Hide a secure button from insecure code -> only create enabled elements (toggling needs /reload).
    for _, t in ipairs(TOTEMS) do
        if db()[t.toggle] then
            rows[t.key] = createRow(t)
        end
    end
    -- Same rule, and it is why knowing the spell is checked HERE rather than
    -- every frame: the button either exists for this session or it does not.
    -- On the builds we ship for no call spell resolves, so it never exists.
    if callSpell() then rows.call = createRow(CALL) end
    -- Only on Wrath-family clients (Titan included): that is where the native
    -- bar shows a recall button and where the report came from. The spell also
    -- exists on TBC/Era, but there it stays middle-click only.
    if ns.Wrath.hasTotemicRecall and totemicRecallSpell() then rows.recall = createRow(RECALL) end

    container.mover = ns:CreateMover(container, {
        key    = "totems",
        label  = L["|cffffffffTOTEMS|r"],
        db     = db(),
        width  = 160,
        height = 50,
        onMove = function(x, y)
            ns:Print(string.format(L["Totems: x=%.0f, y=%.0f"], x, y))
        end,
        editPreview = function() refresh() end,
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

-- Apply queued layout / secure-attribute changes once combat ends.
local function applyPending()
    if pendingAttr then
        applyLayout()
        applyButtonSpells()
        rebuildFlyouts()
    end
end

-- named upvalue: Events.lua unregisters by identity
local function onSpellsChanged()
    applyButtonSpells()
    rebuildFlyouts()
end

local function onEnable()
    ensureDB()
    build()
    playerAurasDirty = true   -- auras may have changed while UNIT_AURA was unregistered
    container:SetScript("OnUpdate", onUpdate)
    csMod:RegisterEvent("PLAYER_TOTEM_UPDATE",   learnActiveTotems)
    csMod:RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
    csMod:RegisterEvent("PLAYER_REGEN_ENABLED",  applyPending)
    csMod:RegisterEvent("SPELLS_CHANGED",        onSpellsChanged)
    csMod:RegisterEvent("UNIT_AURA",             onPlayerAura)
    learnActiveTotems()
    refresh()
    rebuildFlyouts()
end

local function onDisable()
    if container then
        container:SetScript("OnUpdate", nil)
        if container.mover then container.mover:Hide() end
        container:Hide()
    end
end

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
    if #d.setOrder <= 1 then return end
    local name = d.activeSet
    d.sets[name] = nil
    for i, n in ipairs(d.setOrder) do
        if n == name then table.remove(d.setOrder, i); break end
    end
    d.activeSet = d.setOrder[1]
    applyButtonSpells()
end

local function renameActiveSet(newName)
    local d = db()
    newName = tostring(newName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if newName == "" then return end
    local old = d.activeSet
    if newName == old or d.sets[newName] then return end
    d.sets[newName] = d.sets[old]
    d.sets[old]     = nil
    for i, n in ipairs(d.setOrder) do
        if n == old then d.setOrder[i] = newName; break end
    end
    d.activeSet = newName
end

local function rebuildOptions()
    if ns.UI and ns.UI.BuildOptionsPage then
        ns.UI:BuildOptionsPage("vtmanadisplay", ns.UI.currentTab)
    end
end

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

    items[#items + 1] = { type = "header", text = L["Appearance"] }
    items[#items + 1] = { type = "dropdown", label = L["Layout"],
        values = { { value = "icons", text = L["Icons"] }, { value = "bars", text = L["Bars"] } },
        get = function() return d.layout end,
        set = function(_, v) d.layout = v; applyLayout(); rebuildFlyouts(); refresh() end }
    items[#items + 1] = { type = "dropdown", label = L["Style"],
        values = {
            { value = "vulo",    text = L["VuloUI (dark)"] },
            { value = "classic", text = L["Classic (metal)"] },
        },
        get = function() return d.style or "vulo" end,
        set = function(_, v) d.style = v; applyLayout(); rebuildFlyouts(); refresh() end }
    items[#items + 1] = { type = "dropdown", label = L["Flyout direction"],
        tooltip = L["Which way the totem picker opens when you hover a slot. Automatic picks the side away from the screen edge."],
        values = {
            { value = "auto",  text = L["Automatic"] },
            { value = "up",    text = L["Upwards"] },
            { value = "down",  text = L["Downwards"] },
            { value = "left",  text = L["To the left"] },
            { value = "right", text = L["To the right"] },
        },
        get = function() return d.flyoutDirection or "auto" end,
        set = function(_, v) d.flyoutDirection = v; rebuildFlyouts() end }
    items[#items + 1] = { type = "toggle", label = L["Open flyout in combat"],
        tooltip = L["Off = hovering a slot never opens the totem picker while you are fighting (clicks still cast). The picker now also closes itself on mouse-out and after every cast, even in combat."],
        get = function() return d.flyoutInCombat ~= false end,
        set = function(_, v) d.flyoutInCombat = v and true or false; rebuildFlyouts() end }
    items[#items + 1] = { type = "toggle", label = L["Tooltip with cooldown on hover"],
        tooltip = L["Hovering a totem slot or a picker icon shows the totem name and its remaining cooldown."],
        get = function() return d.hoverTooltip ~= false end,
        set = function(_, v) d.hoverTooltip = v and true or false end }
    items[#items + 1] = { type = "toggle", label = L["Sound before a totem expires"],
        get = function() return d.expirySound end,
        set = function(_, v) d.expirySound = v end }
    items[#items + 1] = { type = "toggle", label = L["Grey out when you walk out of range"],
        tooltip = L["Drains the colour while you are outside a totem's radius, and restores it when you step back in. Recognised from the buff the totem puts on you, so totems that grant no buff (Searing, Magma, Tremor, ...) always stay lit."],
        get = function() return d.dimOutOfRange ~= false end,
        set = function(_, v) d.dimOutOfRange = v and true or false; refresh() end }
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

csMod:RegisterClassTool("SHAMAN", {
    onEnable   = onEnable,
    onDisable  = onDisable,
    getOptions = getOptions,
})
