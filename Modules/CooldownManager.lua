-- =========================================================
-- VuloClassicUI / Modules / CooldownManager
-- Retail-style cooldown bars for Classic, organised into GROUPS:
-- make one bar for procs/buffs, one for defensive CDs, one for
-- offensive CDs... each group is its own movable bar with its own
-- spell list and layout. Add entries by typing a name/ID, shift-
-- clicking a spell into the box, or dragging onto an unlocked bar.
-- Icons only DISPLAY cooldowns (no casting) -> no secure/taint issues.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("cooldownmanager", {
    name        = "Cooldown Manager",
    group       = "HUD",
    description = "Movable cooldown bars grouped however you like (procs, defensives, offensives ...) — like the retail cooldown manager.",
    defaults    = {
        enabled  = true,
        groups   = {},   -- array of group tables (see defaultGroup)
        selected = 1,    -- group index currently shown in the options
    },
})

-- =========================================================
-- API compat (2.5.5 has no C_Spell / global GetItemCooldown reliably)
-- =========================================================
local GetSpellCooldown = _G.GetSpellCooldown or (C_Spell and C_Spell.GetSpellCooldown)
local GetSpellInfo     = _G.GetSpellInfo
local GetItemIcon      = _G.GetItemIcon or (C_Item and C_Item.GetItemIconByID)

local function getItemCooldown(itemID)
    if not itemID then return 0, 0, 0 end
    if _G.GetItemCooldown then return GetItemCooldown(itemID) end
    if C_Item and C_Item.GetItemCooldown then
        local s, d, e = C_Item.GetItemCooldown(itemID)
        return s, d, (e == true and 1) or (e == false and 0) or e
    end
    if C_Container and C_Container.GetItemCooldown then
        return C_Container.GetItemCooldown(itemID)
    end
    return 0, 0, 0
end

local function spellCooldown(id)
    if not GetSpellCooldown then return 0, 0, 1 end
    local a, b, c = GetSpellCooldown(id)
    if type(a) == "table" then
        return a.startTime or 0, a.duration or 0, a.isEnabled ~= false and 1 or 0
    end
    return a or 0, b or 0, c or 1
end

local GCD_MAX = 1.5
local FONT = "Fonts\\FRIZQT__.TTF"

-- Custom reorder arrows (white chevrons, tinted by the icon button)
local ARROW_LEFT  = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\arrow_left.tga"
local ARROW_RIGHT = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\arrow_right.tga"

-- Icon-shape masks (square = plain white = no visible mask)
local MASK_ROUNDED = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\csquare_mask.tga"
local MASK_CIRCLE  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\circle_mask.tga"
local MASK_SQUARE  = "Interface\\Buttons\\WHITE8X8"

local function shapeMask(shape)
    if shape == "circle"  then return MASK_CIRCLE  end
    if shape == "rounded" then return MASK_ROUNDED end
    return MASK_SQUARE
end

-- Corner -> { anchor point, x inset, y inset } for the stack/reagent number.
local STACK_INSETS = {
    BOTTOMRIGHT = { "BOTTOMRIGHT", -1,  1 },
    BOTTOMLEFT  = { "BOTTOMLEFT",   1,  1 },
    TOPRIGHT    = { "TOPRIGHT",    -1, -1 },
    TOPLEFT     = { "TOPLEFT",      1, -1 },
    TOP         = { "TOP",          0, -1 },
    BOTTOM      = { "BOTTOM",       0,  1 },
    CENTER      = { "CENTER",       0,  0 },
}

-- Whole-second countdown (no decimals); minutes above 60s.
local function fmtRemain(remain)
    if remain >= 60 then return math.floor(remain / 60 + 0.5) .. "m" end
    return tostring(math.ceil(remain))
end

local AURA_COLORS = {
    yellow = { 1, 0.85, 0.10 }, gold = { 1, 0.70, 0.20 }, green = { 0.25, 1, 0.35 },
    purple = { 0.70, 0.40, 1 }, red = { 1, 0.25, 0.25 }, blue = { 0.35, 0.60, 1 },
    white  = { 1, 1, 1 },
}

-- =========================================================
-- State
-- =========================================================
-- barOf maps a group TABLE to its runtime bar frame (NOT stored in the DB,
-- which can't hold frames). Group tables keep their identity across reorders,
-- so a bar stays bound to its group even when indices shift.
local barOf   = {}
local allBars = {}   -- every bar ever created (for blanket hide on rebuild)
local throttle = 0
local driver
local inCombat = false

local function db() return mod.db end

-- Per-group visibility conditions (all default off). While a group is unlocked
-- for positioning it always shows so it can be dragged.
local function barVisible(group)
    if group.unlocked then return true end
    if group.onlyInCombat and not inCombat then return false end
    if group.hideMounted and IsMounted and IsMounted() then return false end
    if group.onlyInInstance and IsInInstance and not IsInInstance() then return false end
    local hasTarget = UnitExists("target")
    if group.hideNoTarget and not hasTarget then return false end
    if group.hideNoEnemy and not (hasTarget and UnitCanAttack("player", "target")) then return false end
    return true
end

-- =========================================================
-- Groups
-- =========================================================
local function defaultGroup(name)
    return {
        name           = name or L["Cooldowns"],
        mode           = "cooldown",   -- "cooldown" | "aura" (buffs/procs)
        auraStyle      = "glow",       -- "glow" | "border" | "none"
        auraColor      = "yellow",
        entries        = {},
        iconSize       = 40,
        spacing        = 4,
        perRow         = 12,
        growth         = "RIGHT",
        minDuration    = 1.5,    -- hide cooldowns at/under this (1.5 = GCD); 0 = show all
        onlyOnCooldown = false,
        showText       = true,
        showStacks     = true,   -- stack-count number on stacking buffs/procs
        showReagents   = false,  -- each spell's OWN reagent count (Soul Shard, Infernal Stone, ...)
        stackPos       = "BOTTOMRIGHT",          -- corner for the stack/reagent number
        stackSize      = 13,                     -- stack/reagent font size
        stackColor     = { r = 1, g = 0.95, b = 0.6 },
        desaturate     = true,
        readyFlash     = true,
        iconShape      = "square",  -- square | rounded | circle
        iconZoom       = 0.08,      -- texcoord crop (0 = full icon)
        swipeAlpha     = 0.6,       -- cooldown sweep darkness (0 = none)
        -- visibility conditions (all default off = always shown)
        onlyInCombat   = false,
        hideNoTarget   = false,
        hideNoEnemy    = false,
        hideMounted    = false,
        onlyInInstance = false,
        unlocked       = false,
        anchorTo       = nil,      -- id of another group's bar to anchor to (nil = free)
        anchorSide     = "BELOW",  -- BELOW | ABOVE | LEFT | RIGHT of the target
        x              = 0,        -- free: center offset from screen; anchored: fine-tune offset
        y              = -160,
    }
end

-- Stable per-group id so anchors survive renames / reordering.
local function ensureGroupIDs()
    local d = db()
    d.nextId = d.nextId or 1
    for _, g in ipairs(d.groups) do
        if not g.id then g.id = d.nextId; d.nextId = d.nextId + 1 end
    end
end

local function newGroupID()
    local d = db()
    d.nextId = (d.nextId or 1)
    local id = d.nextId
    d.nextId = id + 1
    return id
end

-- Migration from the old single-bar layout + ensure one group always exists.
local function ensureGroups()
    local d = db()
    d.groups = d.groups or {}
    if #d.groups == 0 then
        local g = defaultGroup()
        -- carry over the pre-groups flat config, if present
        if type(d.entries) == "table" then g.entries = d.entries end
        for _, k in ipairs({ "iconSize", "spacing", "perRow", "growth",
            "onlyOnCooldown", "showText", "desaturate", "readyFlash", "x", "y" }) do
            if d[k] ~= nil then g[k] = d[k] end
        end
        d.groups[1] = g
        d.entries = nil
    end
    for _, g in ipairs(d.groups) do
        g.mode      = g.mode or "cooldown"   -- older groups predate aura mode
        g.auraStyle = g.auraStyle or "glow"
        g.auraColor = g.auraColor or "yellow"
        if g.showStacks == nil then g.showStacks = true end
        if g.showReagents == nil then g.showReagents = (g.reagentItem or 0) > 0 end
        g.reagentItem = nil   -- replaced by per-spell auto-detection
        g.anchorSide = g.anchorSide or "BELOW"
        g.iconShape  = g.iconShape or "square"
        if g.iconZoom   == nil then g.iconZoom   = 0.08 end
        if g.swipeAlpha == nil then g.swipeAlpha = 0.8 end
        g.stackPos   = g.stackPos or "BOTTOMRIGHT"
        if g.minDuration == nil then g.minDuration = 1.5 end
        if g.stackSize  == nil then g.stackSize  = 13 end
        if type(g.stackColor) ~= "table" then g.stackColor = { r = 1, g = 0.95, b = 0.6 } end
    end
    ensureGroupIDs()
    if d.selected < 1 then d.selected = 1 end
    if d.selected > #d.groups then d.selected = #d.groups end
end

local function curGroup()
    local d = db()
    return d.groups[d.selected]
end

-- =========================================================
-- Entry resolution
-- =========================================================
-- Resolve a (localized) spell NAME to its spellID by scanning the spellbook.
-- 2.5.5's GetSpellInfo(name) frequently returns NO spellID (7th value), so a
-- typed name like "Feuerbrunst" (Conflagrate) wouldn't resolve otherwise.
local function spellIDByName(name)
    if not name or name == "" or not GetSpellBookItemName then return nil end
    local lname = name:lower()
    local i = 1
    while true do
        local sname = GetSpellBookItemName(i, "spell")
        if not sname then break end
        if sname:lower() == lname then
            local _, sid = GetSpellBookItemInfo(i, "spell")
            if sid then return sid end
        end
        i = i + 1
    end
    return nil
end

local function resolveInput(text)
    if not text or text == "" then return nil end
    local sid = text:match("|Hspell:(%d+)")
    if sid then return "spell", tonumber(sid) end
    local iid = text:match("|Hitem:(%d+)")
    if iid then return "item", tonumber(iid) end

    local num = tonumber(text)
    if num then
        if GetSpellInfo(num) then return "spell", num end
        if GetItemInfo(num) then return "item", num end
        return nil
    end

    -- by name: prefer a real spellID (GetSpellInfo's 7th, else spellbook scan);
    -- if neither yields one, fall back to the NAME itself — GetSpellInfo and
    -- GetSpellCooldown both accept a name in 2.5.5, so tracking still works.
    local sName, _, _, _, _, _, sId = GetSpellInfo(text)
    if sName then
        return "spell", sId or spellIDByName(sName) or sName
    end

    local _, link = GetItemInfo(text)
    if link then
        local id = tonumber(link:match("item:(%d+)"))
        if id then return "item", id end
    end
    return nil
end

local function entryInfo(e)
    if e.kind == "spell" then
        local name, _, icon = GetSpellInfo(e.id)
        return name, icon
    else
        local name = GetItemInfo(e.id)
        return name, (GetItemIcon and GetItemIcon(e.id))
    end
end

local function entryCooldown(e)
    if e.kind == "spell" then return spellCooldown(e.id) end
    return getItemCooldown(e.id)
end

local function groupHas(group, kind, id)
    for _, e in ipairs(group.entries) do
        if e.kind == kind and e.id == id then return true end
    end
    return false
end

-- Which spells the CURRENT character actually has. Cooldown groups live in an
-- account-wide profile, so without this a Warlock's spells would render (stuck
-- "ready") on a Hunter. Matched by NAME so every rank counts. Rebuilt on login
-- / SPELLS_CHANGED. Items are never filtered (equipped trinkets don't count in
-- bags, and gear is shared between characters anyway).
local knownSpells = {}   -- lowercased spell name -> true
local function rebuildKnownSpells()
    wipe(knownSpells)
    if not GetSpellBookItemName then return end
    local i = 1
    while true do
        local sname = GetSpellBookItemName(i, "spell")
        if not sname then break end
        knownSpells[sname:lower()] = true
        i = i + 1
    end
end

local function entryUsable(e)
    if e.kind ~= "spell" then return true end
    if not next(knownSpells) then rebuildKnownSpells() end
    local name = entryInfo(e)
    return name ~= nil and knownSpells[name:lower()] == true
end

local relayoutGroup, refreshGroup, refreshAll, layoutIcons  -- forward

-- Player buff snapshot, rebuilt once per refresh (name + spellID keyed) so
-- aura groups don't scan 40 buffs per icon. UnitAura spellId is the 10th
-- return in 2.5.5 (same as VTManaDisplay relies on).
local auraByName, auraByID = {}, {}
local recPool = {}   -- reused rec tables (per slot) -> no per-tick allocation
local function scanPlayerAuras()
    wipe(auraByName); wipe(auraByID)
    for i = 1, 40 do
        local name, _, count, _, duration, expiration, _, _, _, sid = UnitAura("player", i, "HELPFUL")
        if not name then break end
        local rec = recPool[i]
        if not rec then rec = {}; recPool[i] = rec end
        rec.dur, rec.exp, rec.count = duration, expiration, count
        auraByName[name] = rec
        if sid then auraByID[sid] = rec end
    end
end

-- Spells that consume a reagent: base spell id -> reagent item id. Resolved to
-- the localized NAME at runtime, so it's locale-independent and covers every
-- rank. Spells NOT listed (e.g. Howl of Terror) show no reagent.
local SPELL_REAGENT_IDS = {
    -- Soul Shard (6265)
    [6353]  = 6265,  -- Soul Fire
    [17877] = 6265,  -- Shadowburn
    [29858] = 6265,  -- Soulshatter
    [697]   = 6265,  -- Summon Voidwalker
    [712]   = 6265,  -- Summon Succubus
    [691]   = 6265,  -- Summon Felhunter
    [30146] = 6265,  -- Summon Felguard
    [6201]  = 6265,  -- Create Healthstone
    [693]   = 6265,  -- Create Soulstone
    [2362]  = 6265,  -- Create Spellstone
    [6366]  = 6265,  -- Create Firestone
    [29893] = 6265,  -- Ritual of Souls
    -- Infernal Stone (5565)
    [1122]  = 5565,  -- Inferno
    -- Demonic Figurine (18796)
    [18540] = 18796, -- Ritual of Doom
}
local reagentByName = {}   -- localized spell name -> reagent item id
local function buildReagentMap()
    wipe(reagentByName)
    for spellID, itemID in pairs(SPELL_REAGENT_IDS) do
        local n = GetSpellInfo(spellID)
        if n then reagentByName[n] = itemID end
    end
end

-- The number drawn in the icon corner. For a spell that actually consumes a
-- reagent (Soul Shards on Soul Fire, Infernal Stone on Inferno) that reagent's
-- count is shown; otherwise the live aura stack count (>1). Gated by the
-- per-group "Show stacks" eye.
local function applyStack(group, f)
    if not group.showStacks then f.stack:Hide(); return end
    local e = f.entry
    if group.showReagents and e and e.kind == "spell" then
        local itemID = f.entryName and reagentByName[f.entryName]
        if itemID then
            f.stack:SetText((GetItemCount and GetItemCount(itemID)) or 0)
            f.stack:Show()
            return
        end
    end
    local rec = (e and auraByID[e.id]) or (f.entryName and auraByName[f.entryName])
    if rec and rec.count and rec.count > 1 then
        f.stack:SetText(rec.count); f.stack:Show()
    else
        f.stack:Hide()
    end
end

local function addEntry(group, input)
    if not group then return false end
    local kind, id = resolveInput(input)
    if not kind then
        ns:Print(L["Cooldown Manager: '%s' is not a known spell or item."], tostring(input))
        return false
    end
    if groupHas(group, kind, id) then
        ns:Print(L["Cooldown Manager: already tracking that."])
        return false
    end
    group.entries[#group.entries + 1] = { kind = kind, id = id }
    relayoutGroup(group)
    local name = entryInfo(group.entries[#group.entries])
    ns:Print(L["Cooldown Manager: added %s."], name or ("#" .. id))
    return true
end

-- =========================================================
-- Icons + bar
-- =========================================================
local function makeIcon(bar, i)
    local f = CreateFrame("Frame", nil, bar)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- icon-shape mask (texture set per group in relayoutGroup)
    if f.CreateMaskTexture and f.tex.AddMaskTexture then
        f.mask = f:CreateMaskTexture()
        f.mask:SetAllPoints(f.tex)
        f.tex:AddMaskTexture(f.mask)
    end

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetAllPoints(f)
    f.border:SetColorTexture(0, 0, 0, 1)

    -- soft proc glow ring (aura mode); the 5px overhang shows around the icon
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 5)
    f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 5, -5)
    f.glow:Hide()

    -- animated spell-activation "proc" glow (the golden shimmer border)
    f.proc = f:CreateTexture(nil, "OVERLAY")
    f.proc:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    f.proc:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    f.proc:SetBlendMode("ADD")
    f.proc:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.proc:Hide()
    if f.proc.CreateAnimationGroup then
        local ok, ag = pcall(function() return f.proc:CreateAnimationGroup() end)
        if ok and ag then
            ag:SetLooping("REPEAT")
            local a1 = ag:CreateAnimation("Alpha")
            a1:SetFromAlpha(1.0); a1:SetToAlpha(0.45); a1:SetDuration(0.55); a1:SetOrder(1)
            local a2 = ag:CreateAnimation("Alpha")
            a2:SetFromAlpha(0.45); a2:SetToAlpha(1.0); a2:SetDuration(0.55); a2:SetOrder(2)
            f.procAnim = ag
        end
    end

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.tex)
    f.cd:SetDrawEdge(true)
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    f.cd.noCooldownCount = true

    -- number on its own frame ABOVE the cooldown sweep so it stays crisp
    f.textHost = CreateFrame("Frame", nil, f)
    f.textHost:SetAllPoints(f)
    f.textHost:SetFrameLevel(f.cd:GetFrameLevel() + 5)

    f.text = f.textHost:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(FONT, 16, "OUTLINE")
    f.text:SetPoint("CENTER", f.textHost, "CENTER", 0, 0)
    f.text:SetShadowColor(0, 0, 0, 1)
    f.text:SetShadowOffset(1, -1)

    -- stack count (aura mode) in the bottom-right corner
    f.stack = f.textHost:CreateFontString(nil, "OVERLAY")
    f.stack:SetFont(FONT, 13, "OUTLINE")
    f.stack:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.stack:SetTextColor(1, 0.95, 0.6)
    f.stack:Hide()

    f.flash = f.textHost:CreateTexture(nil, "OVERLAY")
    f.flash:SetTexture("Interface\\Cooldown\\star4")
    f.flash:SetBlendMode("ADD")
    f.flash:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.flash:Hide()
    return f
end

local function onReceiveDrag(bar)
    if not mod._enabled or not bar._group then return end
    local ctype, a, b = GetCursorInfo()
    if ctype == "spell" then
        local id = select(4, GetCursorInfo())
        if not id and b and GetSpellBookItemInfo then
            id = select(2, GetSpellBookItemInfo(a, b))
        end
        if id then addEntry(bar._group, tostring(id)) end
    elseif ctype == "item" and a then
        addEntry(bar._group, tostring(a))
    end
    ClearCursor()
end

local function ensureBar(group)
    local bar = barOf[group]
    if bar then bar._group = group; return bar end

    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetSize(group.iconSize, group.iconSize)
    bar:SetPoint("CENTER", UIParent, "CENTER", group.x or 0, group.y or -160)
    bar:SetFrameStrata("MEDIUM")
    bar._icons = {}
    bar._group = group
    bar:SetScript("OnReceiveDrag", function(self) onReceiveDrag(self) end)

    bar.mover = ns:CreateMover(bar, {
        label  = group.name,
        db     = group,   -- per-group x/y/unlocked live here
        width  = 150,
        height = 34,
        -- a manual drag writes an absolute screen position, so it detaches
        -- the bar from any anchor (drag = free; fine-tune anchored = sliders)
        onMove = function(x, y) group.x, group.y = x, y; group.anchorTo = nil end,
    })

    barOf[group] = bar
    allBars[#allBars + 1] = bar
    return bar
end

-- =========================================================
-- Bar anchoring (chain bars to each other; they then follow automatically)
-- =========================================================
-- Blizzard frames a bar can pin to (2.5.5 has no Edit Mode, so we offer the
-- common unit frames + minimap directly). Only listed if they exist.
local ANCHOR_FRAMES = {
    { frame = "PlayerFrame", label = L["Player Frame"] },
    { frame = "TargetFrame", label = L["Target Frame"] },
    { frame = "FocusFrame",  label = L["Focus Frame"] },
    { frame = "PetFrame",    label = L["Pet Frame"] },
    { frame = "Minimap",     label = L["Minimap"] },
}

local function groupByID(id)
    if not id then return nil end
    for _, g in ipairs(db().groups) do if g.id == id then return g end end
    return nil
end

-- The frame this group anchors to: a Blizzard frame ("f:PlayerFrame") or
-- another group's bar (numeric id). nil = free / not anchored.
local function anchorTargetFrame(group)
    local a = group.anchorTo
    if not a then return nil end
    if type(a) == "string" then
        local fname = a:match("^f:(.+)$")
        return fname and _G[fname] or nil
    end
    local g = groupByID(a)
    if g and g ~= group then return barOf[g] end
    return nil
end

-- Would anchoring `group` to `targetId` create a loop? Walk the target's own
-- anchor chain; if we arrive back at `group`, it would cycle.
local function wouldCycle(group, targetId)
    local seen, cur = {}, groupByID(targetId)
    while cur do
        if cur == group then return true end
        if seen[cur] then break end
        seen[cur] = true
        cur = groupByID(cur.anchorTo)
    end
    return false
end

local ANCHOR_SIDES = {
    BELOW = { "TOP", "BOTTOM" },
    ABOVE = { "BOTTOM", "TOP" },
    LEFT  = { "RIGHT", "LEFT" },
    RIGHT = { "LEFT", "RIGHT" },
}

local function positionBar(group)
    local bar = barOf[group]
    if not bar then return end
    bar:ClearAllPoints()
    local target = anchorTargetFrame(group)
    local side = ANCHOR_SIDES[group.anchorSide or "BELOW"]
    if target and side then
        -- anchored: x/y act as a fine-tune offset from the chosen edge
        bar:SetPoint(side[1], target, side[2], group.x or 0, group.y or 0)
    else
        -- free: x/y is the offset from the screen centre
        bar:SetPoint("CENTER", UIParent, "CENTER", group.x or 0, group.y or -160)
    end
end

-- Position an ordered list of icon frames in the group's grid (positive
-- bounding box, cell order flipped for LEFT/UP growth).
layoutIcons = function(group, list)
    local bar = ensureBar(group)
    local size, pad = group.iconSize, group.spacing
    local count  = #list
    local perRow = math.max(1, group.perRow)
    local horiz  = (group.growth == "RIGHT" or group.growth == "LEFT")
    local posN   = math.min(math.max(count, 1), perRow)
    local lineN  = math.max(1, math.ceil(math.max(count, 1) / perRow))
    local totalCols = horiz and posN or lineN
    local totalRows = horiz and lineN or posN
    local step = size + pad
    for i = 1, count do
        local idx  = i - 1
        local line = math.floor(idx / perRow)
        local pos  = idx % perRow
        local col  = horiz and pos or line
        local rowi = horiz and line or pos
        if group.growth == "LEFT" then col  = (totalCols - 1) - col end
        if group.growth == "UP"   then rowi = (totalRows - 1) - rowi end
        local f = list[i]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", bar, "TOPLEFT", col * step, -rowi * step)
    end
    bar:SetSize(totalCols * size + (totalCols - 1) * pad,
                totalRows * size + (totalRows - 1) * pad)
end

relayoutGroup = function(group)
    local bar = ensureBar(group)
    local size = group.iconSize
    local entries = group.entries
    local icons = bar._icons

    for i, e in ipairs(entries) do
        local f = icons[i]
        if not f then f = makeIcon(bar, i); icons[i] = f end
        local ename, icon = entryInfo(e)
        f.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local z = group.iconZoom or 0.08
        f.tex:SetTexCoord(z, 1 - z, z, 1 - z)
        if f.mask then
            f.mask:SetTexture(shapeMask(group.iconShape), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        -- cooldown swipe transparency. SetSwipeColor's alpha can be a no-op in
        -- 2.5.5, so we also dim the whole cooldown frame (always reliable):
        -- 0 = no dark overlay at all (just the icon + countdown number).
        if f.cd.SetSwipeColor then f.cd:SetSwipeColor(0, 0, 0, 1) end
        f.cd:SetAlpha(group.swipeAlpha or 0.8)
        f.text:SetFont(FONT, math.max(8, math.floor(size * 0.4)), "OUTLINE")
        -- stack / reagent number position, size, colour
        local si = STACK_INSETS[group.stackPos or "BOTTOMRIGHT"] or STACK_INSETS.BOTTOMRIGHT
        f.stack:ClearAllPoints()
        f.stack:SetPoint(si[1], f, si[1], si[2], si[3])
        f.stack:SetFont(FONT, group.stackSize or 13, "OUTLINE")
        local sc = group.stackColor or { r = 1, g = 0.95, b = 0.6 }
        f.stack:SetTextColor(sc.r or 1, sc.g or 0.95, sc.b or 0.6)
        f.entry     = e
        f.entryName = ename
        f.prevRemain = 0
        f.flashT = nil
        f.border:SetColorTexture(0, 0, 0, 1)  -- reset; aura refresh restyles
        f.glow:Hide()
        if f.proc then
            f.proc:Hide(); f.proc:SetSize(size * 1.4, size * 1.4)
            if f.procAnim and f.procAnim:IsPlaying() then f.procAnim:Stop() end
        end
        f.stack:Hide()
        f.usable = entryUsable(e)
        f:SetSize(size, size)
        if f.usable then f:Show() else f:Hide() end
    end
    for i = #entries + 1, #icons do icons[i]:Hide() end

    if group.mode == "aura" then
        -- visibility + packing happen per refresh (only active procs show)
        scanPlayerAuras()
        refreshGroup(group, GetTime())
    else
        local all = {}
        for i = 1, #entries do
            local f = icons[i]
            if f.usable then all[#all + 1] = f else f:Hide() end
        end
        if #all == 0 then bar:SetSize(size, size) else layoutIcons(group, all) end
    end
end

local function updateIcon(group, f, now)
    local e = f.entry
    if not e then return end
    local start, duration, enabled = entryCooldown(e)
    -- ignore the global cooldown (and any short CD under the group's threshold)
    local minDur = group.minDuration or GCD_MAX
    local onCD = enabled ~= 0 and duration and duration > minDur
        and start and (start + duration - now) > 0

    if onCD then
        local remain = start + duration - now
        f.cd:SetCooldown(start, duration)
        if group.showText then
            f.text:SetText(fmtRemain(remain))
            if remain <= 3 then f.text:SetTextColor(1, 0.4, 0.4)
            else f.text:SetTextColor(1, 1, 1) end
            f.text:Show()
        else
            f.text:Hide()
        end
        if group.desaturate then f.tex:SetDesaturated(true); f.tex:SetVertexColor(0.6, 0.6, 0.6)
        else f.tex:SetDesaturated(false); f.tex:SetVertexColor(1, 1, 1) end
        f.prevRemain = remain
        if group.onlyOnCooldown then f:Show() end
    else
        f.cd:Clear()
        f.text:Hide()
        f.tex:SetDesaturated(false)
        f.tex:SetVertexColor(1, 1, 1)
        if group.readyFlash and (f.prevRemain or 0) > 0 then
            f.flashT = 0
            f.flash:SetAlpha(0.9)
            f.flash:Show()
        end
        f.prevRemain = 0
        if group.onlyOnCooldown then f:Hide() end
    end

    if f.flashT then
        f.flashT = f.flashT + 0.1
        local p = f.flashT / 0.45
        if p >= 1 then f.flash:Hide(); f.flashT = nil
        else
            local s = f:GetWidth() * (1.6 + p * 0.6)
            f.flash:SetSize(s, s)
            f.flash:SetAlpha(0.9 * (1 - p))
        end
    end

    -- stack / reagent number (e.g. Soul Shards on Soul Fire). The shared aura
    -- snapshot is scanned in refreshAll when needed; reagent counts poll bags.
    applyStack(group, f)
end

-- Border / glow highlight for active aura icons
local function stopProc(f)
    if f.proc then
        f.proc:Hide()
        if f.procAnim and f.procAnim:IsPlaying() then f.procAnim:Stop() end
    end
end

local function applyAuraStyle(group, f)
    local style = group.auraStyle or "glow"
    local c = AURA_COLORS[group.auraColor or "yellow"] or AURA_COLORS.yellow
    if style == "proc" then
        f.glow:Hide(); f.border:SetColorTexture(0, 0, 0, 1)
        if f.proc then
            f.proc:SetVertexColor(c[1], c[2], c[3], 1)
            f.proc:Show()
            if f.procAnim and not f.procAnim:IsPlaying() then f.procAnim:Play() end
        end
    elseif style == "glow" then
        stopProc(f)
        f.glow:SetVertexColor(c[1], c[2], c[3], 0.9); f.glow:Show()
        f.border:SetColorTexture(0, 0, 0, 1)
    elseif style == "border" then
        stopProc(f)
        f.glow:Hide(); f.border:SetColorTexture(c[1], c[2], c[3], 1)
    else
        stopProc(f)
        f.glow:Hide(); f.border:SetColorTexture(0, 0, 0, 1)
    end
end

-- Aura mode: the icon is only ever shown while the buff/proc is active.
-- Draw a draining sweep for the remaining time + stacks.
local function updateAuraIcon(group, f, rec, now)
    f.tex:SetDesaturated(false)
    f.tex:SetVertexColor(1, 1, 1)
    applyAuraStyle(group, f)
    if rec.exp and rec.dur and rec.dur > 0 then
        f.cd:SetCooldown(rec.exp - rec.dur, rec.dur)
        local remain = rec.exp - now
        if group.showText and remain > 0 then
            f.text:SetText(fmtRemain(remain))
            if remain <= 3 then f.text:SetTextColor(1, 0.4, 0.4)
            else f.text:SetTextColor(1, 1, 1) end
            f.text:Show()
        else
            f.text:Hide()
        end
    else
        f.cd:Clear()       -- permanent / no timed duration
        f.text:Hide()
    end
    applyStack(group, f)
end

refreshGroup = function(group, now)
    local bar = barOf[group]
    if not bar then return end
    local icons = bar._icons

    if group.mode == "aura" then
        local active = {}
        for i = 1, #group.entries do
            local f = icons[i]
            if f then
                local e = f.entry
                local rec = (e and auraByID[e.id]) or (f.entryName and auraByName[f.entryName])
                if rec then
                    active[#active + 1] = f
                    f._rec = rec
                    f:Show()
                else
                    f.stack:Hide()
                    f:Hide()
                end
            end
        end
        layoutIcons(group, active)          -- pack only the active procs
        for _, f in ipairs(active) do updateAuraIcon(group, f, f._rec, now) end
        return
    end

    -- cooldown mode
    for i = 1, #group.entries do
        local f = icons[i]
        if f and f.usable and (f:IsShown() or group.onlyOnCooldown) then
            updateIcon(group, f, now)
        end
    end
end

refreshAll = function()
    if not mod._enabled then return end
    local now = GetTime()
    local groups = db().groups
    -- one shared aura scan if any group needs aura data (aura mode, or a
    -- cooldown group that shows stack counts on its tracked spells)
    local needAuras = false
    for _, g in ipairs(groups) do
        if g.mode == "aura" or g.showStacks then needAuras = true; break end
    end
    if needAuras then scanPlayerAuras() end
    for _, group in ipairs(groups) do
        local bar = barOf[group]
        local vis = barVisible(group)
        if bar then bar:SetShown(vis) end
        -- hidden bars skip the per-icon work entirely (cooldown sweeps keep
        -- animating on their own; they're re-synced when shown again)
        if vis then refreshGroup(group, now) end
    end
end

local function onUnitAura(_, unit)
    if unit == "player" then refreshAll() end
end

local function onCombat(_, event)
    inCombat = (event == "PLAYER_REGEN_DISABLED")
    refreshAll()
end

-- Rebuild every bar: hide all, then (re)lay-out each current group.
local function rebuildBars()
    rebuildKnownSpells()
    buildReagentMap()
    ensureGroupIDs()
    for _, b in ipairs(allBars) do b:Hide() end
    for _, group in ipairs(db().groups) do
        local bar = ensureBar(group)
        bar:Show()
        if bar.mover and bar.mover.label then bar.mover.label:SetText(group.name) end
        relayoutGroup(group)
    end
    -- position after every bar exists, so anchors can target any other bar
    for _, group in ipairs(db().groups) do positionBar(group) end
    refreshAll()
end

local function setUnlocked(group, state)
    if not group then return end
    group.unlocked = state
    local bar = ensureBar(group)
    bar:EnableMouse(state)
    if state then
        bar.mover:Show()
        ns:Print(L["Cooldown group '%s' unlocked. Drag spells/items onto it; |cff9b6cffdrag|r to move."], group.name)
    else
        bar.mover:Hide()
        ns:Print(L["Cooldown group '%s' locked."], group.name)
    end
end

-- True if ANY group's bar is currently unlocked (edit mode active).
local function anyUnlocked()
    for _, g in ipairs(db().groups) do
        if g.unlocked then return true end
    end
    return false
end

-- 2.5.5 has no Blizzard Edit Mode, so this is our own: unlock/lock EVERY bar
-- at once for free dragging (anchoring stays in the per-group options).
local function setAllUnlocked(state)
    for _, g in ipairs(db().groups) do
        g.unlocked = state
        local bar = ensureBar(g)
        bar:EnableMouse(state)
        if bar.mover then
            if state then bar.mover:Show() else bar.mover:Hide() end
        end
    end
    if state then
        ns:Print(L["Cooldown edit mode |cff44ff44ON|r — drag any bar to move it. Toggle again to lock."])
    else
        ns:Print(L["Cooldown edit mode |cffff5555OFF|r — all bars locked."])
    end
    refreshAll()
end

-- /cdedit toggles the edit mode without opening the options window.
SLASH_VCUICDEDIT1 = "/cdedit"
SlashCmdList["VCUICDEDIT"] = function()
    if not mod._enabled then return end
    setAllUnlocked(not anyUnlocked())
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    ensureGroups()
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", function(_, elapsed)
            throttle = throttle + elapsed
            if throttle < 0.1 then return end
            throttle = 0
            refreshAll()
        end)
    end
    inCombat = InCombatLockdown() and true or false
    driver:Show()
    rebuildBars()
    ns:RegisterEvent("SPELL_UPDATE_COOLDOWN", refreshAll)
    ns:RegisterEvent("BAG_UPDATE_COOLDOWN",   refreshAll)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", refreshAll)
    ns:RegisterEvent("SPELLS_CHANGED",        rebuildBars)
    ns:RegisterEvent("UNIT_AURA",             onUnitAura)  -- snappy proc show/hide
    ns:RegisterEvent("PLAYER_REGEN_DISABLED", onCombat)    -- visibility conditions
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",  onCombat)
    ns:RegisterEvent("PLAYER_TARGET_CHANGED", refreshAll)
end

function mod:OnDisable()
    ns:UnregisterEvent("SPELL_UPDATE_COOLDOWN", refreshAll)
    ns:UnregisterEvent("BAG_UPDATE_COOLDOWN",   refreshAll)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", refreshAll)
    ns:UnregisterEvent("SPELLS_CHANGED",        rebuildBars)
    ns:UnregisterEvent("UNIT_AURA",             onUnitAura)
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED", onCombat)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",  onCombat)
    ns:UnregisterEvent("PLAYER_TARGET_CHANGED", refreshAll)
    if driver then driver:Hide() end
    for _, b in ipairs(allBars) do
        if b.mover then b.mover:Hide() end
        b:Hide()
    end
end

-- =========================================================
-- Options
-- =========================================================
local addInput = ""

local function rebuildPage()
    if ns.UI and ns.UI.BuildOptionsPage then ns.UI:BuildOptionsPage("cooldownmanager") end
end

local function openColorPicker(getCurrent, setNew)
    local c = getCurrent() or { r = 1, g = 1, b = 1 }
    local function apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        setNew({ r = r, g = g, b = b })
    end
    local info = {
        r = c.r, g = c.g, b = c.b, opacity = false,
        swatchFunc = apply, cancelFunc = function(prev) if prev then setNew(prev) end end,
    }
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    elseif _G.OpenColorPicker then
        _G.OpenColorPicker(info)
    end
end

function mod:GetOptions()
    ensureGroups()
    local d = mod.db
    local group = curGroup()

    -- Group selector
    local groupValues = {}
    for i, g in ipairs(d.groups) do
        groupValues[#groupValues + 1] = { value = i, text = g.name }
    end

    local items = {
        { type = "header", text = L["Cooldown Manager"] },
        { type = "desc",
          text = L["|cffaaaaaaMovable cooldown bars grouped however you like — e.g. one for procs/buffs, one for defensive cooldowns, one for offensives. Pick or create a group below, then add spells/trinkets to it.|r"] },
        { type = "spacer", height = 4 },

        -- Edit mode: unlock EVERY bar at once (2.5.5 has no Blizzard Edit Mode)
        { type = "button", width = 340, primary = true,
          label = anyUnlocked() and L["Stop editing — lock all bars"]
                                 or  L["Edit mode — unlock all bars to move"],
          tooltip = L["Unlocks every cooldown bar at once so you can drag them all into place. Anchoring is set per group in 'Anchor'."],
          onClick = function() setAllUnlocked(not anyUnlocked()); rebuildPage() end },
        { type = "spacer", height = 6 },

        { type = "header", text = L["Groups"] },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "dropdown", label = L["Edit group"], width = 240,
              values = groupValues,
              get = function() return d.selected end,
              set = function(_, v) d.selected = v; rebuildPage() end },
            { type = "button", label = L["New group"], width = 120, primary = true,
              onClick = function()
                  local g = defaultGroup(string.format(L["Group %d"], #d.groups + 1))
                  g.id = newGroupID()
                  d.groups[#d.groups + 1] = g
                  d.selected = #d.groups
                  rebuildBars(); rebuildPage()
              end },
        } },
    }

    if not group then return items end

    -- Selected group: name + delete
    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "editbox", label = L["Name"], width = 260, editWidth = 170,
          get = function() return group.name end,
          set = function(_, v)
              group.name = (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
              if group.name == "" then group.name = L["Cooldowns"] end
              rebuildBars(); rebuildPage()
          end },
        { type = "button", label = L["Delete group"], width = 130,
          onClick = function()
              local bar = barOf[group]
              if bar then bar:Hide(); if bar.mover then bar.mover:Hide() end end
              -- detach any bars anchored to the one being deleted
              for _, g in ipairs(d.groups) do
                  if g.anchorTo == group.id then g.anchorTo = nil end
              end
              table.remove(d.groups, d.selected)
              if d.selected > #d.groups then d.selected = #d.groups end
              rebuildBars(); rebuildPage()
          end },
    } }
    items[#items + 1] = { type = "dropdown", label = L["Group type"], width = 280,
        values = {
            { value = "cooldown", text = L["Cooldowns"] },
            { value = "aura",     text = L["Buffs & Procs (only show while active)"] },
        },
        get = function() return group.mode end,
        set = function(_, v) group.mode = v; rebuildBars(); rebuildPage() end }
    items[#items + 1] = { type = "desc",
        text = (group.mode == "aura")
            and L["|cffaaaaaaIcons appear only while their buff/proc is on you; the bar is empty otherwise. Add the BUFF (e.g. Clearcasting) by name or ID.|r"]
            or  L["|cffaaaaaaIcons show the cooldown of each spell/trinket.|r"] }
    items[#items + 1] = { type = "spacer", height = 6 }

    -- Add entry (commit on focus loss so clicking Add works without Enter;
    -- Enter in the box also submits directly)
    local function doAdd()
        local txt = addInput:gsub("^%s+", ""):gsub("%s+$", "")
        if txt ~= "" and addEntry(group, txt) then addInput = ""; rebuildPage() end
    end
    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "editbox", label = L["Add (name / ID)"], width = 280, editWidth = 190,
          commitOnFocusLost = true,
          get = function() return addInput end,
          set = function(_, v) addInput = tostring(v or "") end,
          onEnter = function() doAdd() end },
        { type = "button", label = L["Add"], width = 80, primary = true,
          onClick = doAdd },
    } }
    items[#items + 1] = { type = "spacer", height = 4 }

    -- Tracked list: a collapsible "Tracked" section (its gear shows/hides the
    -- whole list). Each row has the icon + name and ALWAYS-visible move/remove
    -- controls — no per-entry expand, so nothing can get stuck open. Arrows
    -- follow the bar's orientation (←/→ horizontal, ↑/↓ vertical).
    local trackedItems = {}
    if #group.entries == 0 then
        trackedItems[1] = { type = "desc", text = L["|cff888888Nothing in this group yet.|r"] }
    else
        local n = #group.entries
        for i, e in ipairs(group.entries) do
            local nm, icon = entryInfo(e)
            local label = (icon and ("|T" .. icon .. ":18:18:0:0:64:64:5:59:5:59|t  ") or "")
                .. (nm or ("#" .. tostring(e.id)))
            if e.kind == "item" then label = label .. L["  |cff888888(item)|r"] end
            if e.kind == "spell" and not entryUsable(e) then label = label .. L["  |cffaa5555(other class)|r"] end

            trackedItems[#trackedItems + 1] = { type = "group", layout = "row", gap = 6, items = {
                { type = "desc", text = label, width = 300 },
                { type = "iconbutton", icon = ARROW_LEFT, width = 28, height = 28, iconInset = 7,
                  tooltip = L["Move earlier"],
                  onClick = function()
                      if i > 1 then
                          group.entries[i], group.entries[i-1] = group.entries[i-1], group.entries[i]
                          relayoutGroup(group); rebuildPage()
                      end
                  end },
                { type = "iconbutton", icon = ARROW_RIGHT, width = 28, height = 28, iconInset = 7,
                  tooltip = L["Move later"],
                  onClick = function()
                      if i < n then
                          group.entries[i], group.entries[i+1] = group.entries[i+1], group.entries[i]
                          relayoutGroup(group); rebuildPage()
                      end
                  end },
                { type = "button", label = L["Remove"], width = 110, height = 28,
                  onClick = function()
                      table.remove(group.entries, i); relayoutGroup(group); rebuildPage()
                  end },
            } }
        end
    end
    -- Unlock / position lives INSIDE the section, so it collapses with it
    trackedItems[#trackedItems + 1] = { type = "spacer", height = 4 }
    trackedItems[#trackedItems + 1] = { type = "button", label = L["Unlock / Position"], width = 200,
        onClick = function() setUnlocked(group, not group.unlocked) end }
    items[#items + 1] = { type = "section", title = L["Tracked"], collapsed = false, items = trackedItems }

    -- Anchor this bar to another group's bar (it then follows + fine-tune offset)
    do
        local anchorVals = { { value = 0, text = L["None (free)"] } }
        for _, f in ipairs(ANCHOR_FRAMES) do
            if _G[f.frame] then anchorVals[#anchorVals + 1] = { value = "f:" .. f.frame, text = f.label } end
        end
        for _, g in ipairs(d.groups) do
            if g ~= group then anchorVals[#anchorVals + 1] = { value = g.id, text = g.name } end
        end
        local anchorItems = {
            { type = "dropdown", label = L["Anchor to"], width = 240,
              tooltip = L["Pin this bar to a unit frame, the minimap, or another group's bar — it then moves with it. Drag the bar to detach."],
              values = anchorVals,
              get = function() return group.anchorTo or 0 end,
              set = function(_, v)
                  local prev = group.anchorTo
                  if v == 0 then
                      group.anchorTo = nil
                  elseif type(v) == "string" then
                      group.anchorTo = v          -- Blizzard frame, no cycle possible
                  elseif wouldCycle(group, v) then
                      ns:Print(L["Cooldown Manager: can't anchor there — it would loop."])
                  else
                      group.anchorTo = v
                  end
                  if group.anchorTo and group.anchorTo ~= prev then
                      group.x, group.y = 0, 0     -- snap adjacent, then fine-tune
                  end
                  positionBar(group); rebuildPage()
              end },
        }
        if group.anchorTo then
            anchorItems[#anchorItems + 1] = { type = "dropdown", label = L["Side"], width = 200,
                values = {
                    { value = "BELOW", text = L["Below"] }, { value = "ABOVE", text = L["Above"] },
                    { value = "LEFT",  text = L["Left of"] }, { value = "RIGHT", text = L["Right of"] },
                },
                get = function() return group.anchorSide or "BELOW" end,
                set = function(_, v) group.anchorSide = v; positionBar(group) end }
            anchorItems[#anchorItems + 1] = { type = "slider", label = L["X offset"], min = -200, max = 200, step = 1,
                get = function() return group.x or 0 end,
                set = function(_, v) group.x = v; positionBar(group) end }
            anchorItems[#anchorItems + 1] = { type = "slider", label = L["Y offset"], min = -200, max = 200, step = 1,
                get = function() return group.y or 0 end,
                set = function(_, v) group.y = v; positionBar(group) end }
        end
        items[#items + 1] = { type = "section", title = L["Anchor"], collapsed = true, items = anchorItems }
    end

    -- Layout (collapsed by default -> short, fast page)
    items[#items + 1] = { type = "section", title = L["Layout"], collapsed = true, items = {
        { type = "slider", label = L["Icon size"], min = 20, max = 64, step = 1,
          get = function() return group.iconSize end,
          set = function(_, v) group.iconSize = v; relayoutGroup(group) end },
        { type = "slider", label = L["Spacing"], min = 0, max = 16, step = 1,
          get = function() return group.spacing end,
          set = function(_, v) group.spacing = v; relayoutGroup(group) end },
        { type = "slider", label = L["Icons per row"], min = 1, max = 20, step = 1,
          get = function() return group.perRow end,
          set = function(_, v) group.perRow = v; relayoutGroup(group) end },
        { type = "dropdown", label = L["Growth direction"], width = 220,
          values = {
              { value = "RIGHT", text = L["Right"] }, { value = "LEFT", text = L["Left"] },
              { value = "DOWN",  text = L["Down"]  }, { value = "UP",   text = L["Up"]   },
          },
          get = function() return group.growth end,
          set = function(_, v) group.growth = v; relayoutGroup(group) end },
        { type = "dropdown", label = L["Icon shape"], width = 220,
          values = {
              { value = "square",  text = L["Square"]  },
              { value = "rounded", text = L["Rounded"] },
              { value = "circle",  text = L["Circle"]  },
          },
          get = function() return group.iconShape or "square" end,
          set = function(_, v) group.iconShape = v; relayoutGroup(group) end },
        { type = "slider", label = L["Icon zoom"], min = 0, max = 0.30, step = 0.01,
          get = function() return group.iconZoom or 0.08 end,
          set = function(_, v) group.iconZoom = v; relayoutGroup(group) end },
        { type = "slider", label = L["Cooldown swipe darkness"], min = 0, max = 1, step = 0.05,
          get = function() return group.swipeAlpha or 0.8 end,
          set = function(_, v) group.swipeAlpha = v; relayoutGroup(group) end },
    } }

    -- Visibility conditions (collapsed)
    items[#items + 1] = { type = "section", title = L["Visibility"], collapsed = true, items = {
        { type = "toggle", label = L["Only in combat"],
          get = function() return group.onlyInCombat end,
          set = function(_, v) group.onlyInCombat = v; refreshAll() end },
        { type = "toggle", label = L["Only with a target"],
          get = function() return group.hideNoTarget end,
          set = function(_, v) group.hideNoTarget = v; refreshAll() end },
        { type = "toggle", label = L["Only with an attackable target"],
          get = function() return group.hideNoEnemy end,
          set = function(_, v) group.hideNoEnemy = v; refreshAll() end },
        { type = "toggle", label = L["Hide while mounted"],
          get = function() return group.hideMounted end,
          set = function(_, v) group.hideMounted = v; refreshAll() end },
        { type = "toggle", label = L["Only in instances"],
          get = function() return group.onlyInInstance end,
          set = function(_, v) group.onlyInInstance = v; refreshAll() end },
    } }

    -- Display (collapsed by default)
    local displayItems = {
        { type = "toggle", label = L["Show countdown text"],
          get = function() return group.showText end,
          set = function(_, v) group.showText = v; refreshAll() end },
        { type = "toggle", style = "eye", label = L["Show stacks"],
          get = function() return group.showStacks ~= false end,
          set = function(_, v) group.showStacks = v; refreshAll() end },
        { type = "toggle", label = L["Show reagent counts"],
          tooltip = L["Shows each spell's OWN reagent count — Soul Shards on Soul Fire, Infernal Stone on Inferno, etc. Spells without a reagent show nothing. Needs 'Show stacks' on."],
          get = function() return group.showReagents end,
          set = function(_, v) group.showReagents = v; refreshAll() end },
        { type = "dropdown", label = L["Stack / reagent position"], width = 220,
          values = {
              { value = "BOTTOMRIGHT", text = L["Bottom right"] }, { value = "BOTTOMLEFT", text = L["Bottom left"] },
              { value = "TOPRIGHT",    text = L["Top right"]    }, { value = "TOPLEFT",    text = L["Top left"]    },
              { value = "CENTER",      text = L["Center"]       },
          },
          get = function() return group.stackPos or "BOTTOMRIGHT" end,
          set = function(_, v) group.stackPos = v; relayoutGroup(group) end },
        { type = "slider", label = L["Stack / reagent size"], min = 8, max = 24, step = 1,
          get = function() return group.stackSize or 13 end,
          set = function(_, v) group.stackSize = v; relayoutGroup(group) end },
        { type = "button", label = L["Stack / reagent color..."], width = 180,
          onClick = function()
              openColorPicker(function() return group.stackColor end,
                  function(c) group.stackColor = c; relayoutGroup(group) end)
          end },
    }
    if group.mode == "aura" then
        displayItems[#displayItems + 1] = { type = "dropdown", label = L["Highlight"], width = 220,
            values = {
                { value = "proc",   text = L["Proc glow (animated)"] },
                { value = "glow",   text = L["Glow"] },
                { value = "border", text = L["Colored border"] },
                { value = "none",   text = L["None"] },
            },
            get = function() return group.auraStyle end,
            set = function(_, v) group.auraStyle = v; refreshAll() end,
            -- gear -> extra settings (highlight color)
            subOptions = {
                { type = "dropdown", label = L["Highlight color"], width = 220,
                  values = {
                      { value = "yellow", text = L["Yellow"] }, { value = "gold",   text = L["Gold"] },
                      { value = "green",  text = L["Green"]  }, { value = "purple", text = L["Purple"] },
                      { value = "red",    text = L["Red"]    }, { value = "blue",   text = L["Blue"] },
                      { value = "white",  text = L["White"]  },
                  },
                  get = function() return group.auraColor end,
                  set = function(_, v) group.auraColor = v; refreshAll() end },
            } }
    else
        displayItems[#displayItems + 1] = { type = "slider", label = L["Hide cooldowns under (sec)"],
            min = 0, max = 5, step = 0.5,
            tooltip = L["Cooldowns at or below this are ignored. 1.5 hides the global cooldown; raise it to also hide short cooldowns; 0 shows everything."],
            get = function() return group.minDuration or 1.5 end,
            set = function(_, v) group.minDuration = v; refreshAll() end }
        displayItems[#displayItems + 1] = { type = "toggle", label = L["Only show while on cooldown"],
            tooltip = L["Hides ready icons; they reappear when on cooldown."],
            get = function() return group.onlyOnCooldown end,
            set = function(_, v) group.onlyOnCooldown = v; relayoutGroup(group); refreshAll() end }
        displayItems[#displayItems + 1] = { type = "toggle", label = L["Dim icon while on cooldown"],
            get = function() return group.desaturate end,
            set = function(_, v) group.desaturate = v; refreshAll() end }
        displayItems[#displayItems + 1] = { type = "toggle", label = L["Flash when ready"],
            get = function() return group.readyFlash end,
            set = function(_, v) group.readyFlash = v end }
    end
    items[#items + 1] = { type = "section", title = L["Display"], collapsed = true, items = displayItems }

    return items
end
