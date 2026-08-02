-- VuloClassicUI / Modules / CooldownManager
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("cooldownmanager", {
    name        = "Cooldown Manager",
    group       = "HUD",
    -- Two columns throughout, and a setting without a partner keeps its half
    -- rather than stretching across the page. See UI._grid in UI/OptionsBuilder.
    optionsGrid = true,
    description = "Movable cooldown bars grouped however you like — procs, defensives, offensives, each with its own look and position.",
    defaults    = {
        enabled  = true,
        groups   = {},
        selected = 1,
    },
})

-- API compat: 2.5.5 has neither C_Spell nor a reliable global GetItemCooldown
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

local function fontPath()
    return (ns.UI and ns.UI.FONT_PATH) or FONT
end

local ARROW_LEFT  = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\arrow_left.tga"
local ARROW_RIGHT = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\arrow_right.tga"

local MASK_ROUNDED = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\csquare_mask.tga"
local MASK_CIRCLE  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\circle_mask.tga"
local MASK_SQUARE  = "Interface\\Buttons\\WHITE8X8"

local function shapeMask(shape)
    if shape == "circle"  then return MASK_CIRCLE  end
    if shape == "rounded" then return MASK_ROUNDED end
    return MASK_SQUARE
end

local STACK_INSETS = {
    BOTTOMRIGHT = { "BOTTOMRIGHT", -1,  1 },
    BOTTOMLEFT  = { "BOTTOMLEFT",   1,  1 },
    TOPRIGHT    = { "TOPRIGHT",    -1, -1 },
    TOPLEFT     = { "TOPLEFT",      1, -1 },
    TOP         = { "TOP",          0, -1 },
    BOTTOM      = { "BOTTOM",       0,  1 },
    CENTER      = { "CENTER",       0,  0 },
}

local function fmtRemain(remain)
    if remain >= 60 then return math.floor(remain / 60 + 0.5) .. "m" end
    return tostring(math.ceil(remain))
end

local AURA_COLORS = {
    yellow = { 1, 0.85, 0.10 }, gold = { 1, 0.70, 0.20 }, green = { 0.25, 1, 0.35 },
    purple = { 0.70, 0.40, 1 }, red = { 1, 0.25, 0.25 }, blue = { 0.35, 0.60, 1 },
    white  = { 1, 1, 1 },
}

local function borderVisible(group)
    local i = group.borderSize
    if i == nil then i = 1 end
    return i > 0
end

local function groupBorderColor(group)
    if group.borderClassColor then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end
    local c = group.borderColor
    return (c and c.r) or 0, (c and c.g) or 0, (c and c.b) or 0
end

local function applyTimerColor(group, fs, remain)
    local thr = group.lowThreshold
    if thr == nil then thr = 3 end
    local c
    if thr > 0 and remain <= thr then
        c = group.textLowColor
        fs:SetTextColor((c and c.r) or 1, (c and c.g) or 0.4, (c and c.b) or 0.4)
    else
        c = group.textColor
        fs:SetTextColor((c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1)
    end
end

-- keyed by group TABLE, not index: frames must never enter the saved DB, and table identity survives reorders
local barOf   = {}
local allBars = {}
local driver   -- shared-ticker handle, not a frame
local inCombat = false

local function db() return mod.db end

local function barVisible(group)
    if ns:IsMoverEditMode("cooldownmanager") or group.unlocked then return true end
    local gf = group.groupFilter
    if gf and gf ~= "always" then
        if gf == "never" then return false end
        local inRaid  = (IsInRaid and IsInRaid()) or false
        local inGroup = (IsInGroup and IsInGroup()) or inRaid
        if gf == "raid"  and not inRaid then return false end
        if gf == "party" and not (inGroup and not inRaid) then return false end
        if gf == "solo"  and inGroup then return false end
    end
    if group.onlyInCombat and not inCombat then return false end
    if group.hideMounted and IsMounted and IsMounted() then return false end
    if group.onlyInInstance and IsInInstance and not IsInInstance() then return false end
    local hasTarget = UnitExists("target")
    if group.hideNoTarget and not hasTarget then return false end
    if group.hideNoEnemy and not (hasTarget and UnitCanAttack("player", "target")) then return false end
    return true
end

local function defaultGroup(name)
    return {
        name           = name or L["Cooldowns"],
        -- "cooldown" | "aura" | "targetdebuff" | "missing"
        mode           = "cooldown",
        auraStyle      = "glow",
        auraColor      = "yellow",
        tintUnusable   = true,
        tintRange      = false,
        autoTrinkets   = false,
        showTooltips   = false,
        entries        = {},
        iconSize       = 40,
        spacing        = 4,
        perRow         = 12,
        growth         = "RIGHT",
        minDuration    = 1.5,    -- 1.5 = GCD length; 0 = show all
        onlyOnCooldown = false,
        showText       = true,
        showStacks     = true,
        showReagents   = false,
        stackPos       = "BOTTOMRIGHT",
        stackSize      = 13,
        stackColor     = { r = 1, g = 0.95, b = 0.6 },
        desaturate     = true,
        readyFlash     = true,
        iconShape      = "square",
        iconZoom       = 0.08,
        swipeAlpha     = 0.6,
        scale          = 1,
        alpha          = 1,
        textScale      = 0.4,
        textColor      = { r = 1, g = 1, b = 1 },
        textLowColor   = { r = 1, g = 0.4, b = 0.4 },
        lowThreshold   = 3,
        borderSize     = 1,
        borderColor    = { r = 0, g = 0, b = 0 },
        borderClassColor = false,
        barBg          = false,
        barBgColor     = { r = 0, g = 0, b = 0 },
        barBgAlpha     = 0.5,
        readyGlow      = false,
        readyGlowColor = "yellow",
        showInactive   = false,
        showKeybind    = false,
        keybindSize    = 10,
        keybindColor   = { r = 0.9, g = 0.9, b = 0.9 },
        groupFilter    = "always",
        onlyInCombat   = false,
        hideNoTarget   = false,
        hideNoEnemy    = false,
        hideMounted    = false,
        onlyInInstance = false,
        unlocked       = false,
        anchorTo       = nil,
        anchorSide     = "BELOW",
        x              = 0,        -- free: offset from screen centre; anchored: fine-tune offset
        y              = -160,
    }
end

-- stable per-group id so anchors survive renames and reordering
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

-- migrates the pre-groups single-bar config and guarantees one group exists
local function ensureGroups()
    local d = db()
    d.groups = d.groups or {}
    if #d.groups == 0 then
        local g = defaultGroup()
        if type(d.entries) == "table" then g.entries = d.entries end
        for _, k in ipairs({ "iconSize", "spacing", "perRow", "growth",
            "onlyOnCooldown", "showText", "desaturate", "readyFlash", "x", "y" }) do
            if d[k] ~= nil then g[k] = d[k] end
        end
        d.groups[1] = g
        d.entries = nil
    end
    for _, g in ipairs(d.groups) do
        g.mode      = g.mode or "cooldown"
        g.auraStyle = g.auraStyle or "glow"
        g.auraColor = g.auraColor or "yellow"
        if g.showStacks == nil then g.showStacks = true end
        if g.showReagents == nil then g.showReagents = (g.reagentItem or 0) > 0 end
        g.reagentItem = nil
        g.anchorSide = g.anchorSide or "BELOW"
        g.iconShape  = g.iconShape or "square"
        if g.iconZoom   == nil then g.iconZoom   = 0.08 end
        if g.swipeAlpha == nil then g.swipeAlpha = 0.6 end
        g.stackPos   = g.stackPos or "BOTTOMRIGHT"
        if g.minDuration == nil then g.minDuration = 1.5 end
        if g.stackSize  == nil then g.stackSize  = 13 end
        if type(g.stackColor) ~= "table" then g.stackColor = { r = 1, g = 0.95, b = 0.6 } end
        if g.tintUnusable == nil then g.tintUnusable = true end
        -- purge legacy frame buffers off the group table: that table is the saved profile
        g._activeBuf, g._activePrev = nil, nil
    end
    ensureGroupIDs()
    if d.selected < 1 then d.selected = 1 end
    if d.selected > #d.groups then d.selected = #d.groups end
end

local function curGroup()
    local d = db()
    return d.groups[d.selected]
end

-- spellbook scan: 2.5.5's GetSpellInfo(name) often returns no spellID (7th value)
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

local function resolveInput(text, allowRawName)
    if not text or text == "" then return nil end
    local sid = text:match("|Hspell:(%d+)")
    if sid then return "spell", tonumber(sid) end
    local iid = text:match("|Hitem:(%d+)")
    if iid then return "item", tonumber(iid) end

    local num = tonumber(text)
    if num then
        if GetSpellInfo(num) then return "spell", num end
        if GetItemInfo(num) then return "item", num end
        -- 2.5.5 can't resolve proc/aura IDs via GetSpellInfo, but UnitAura still matches them
        return "spell", num
    end

    -- falling back to the NAME works because 2.5.5's GetSpellInfo/GetSpellCooldown accept one
    local sName, _, _, _, _, _, sId = GetSpellInfo(text)
    if sName then
        return "spell", sId or spellIDByName(sName) or sName
    end

    local _, link = GetItemInfo(text)
    if link then
        local id = tonumber(link:match("item:(%d+)"))
        if id then return "item", id end
    end
    -- aura-like groups match by NAME, so foreign buffs are legal input despite not being in the spellbook
    if allowRawName then return "spell", text end
    return nil
end

local function entryInfo(e)
    if e.kind == "spell" then
        local name, _, icon = GetSpellInfo(e.id)
        -- unresolvable proc/aura IDs fall back to what refreshGroup cached when the aura was first seen
        return name or e.savedName or (type(e.id) == "string" and e.id or nil),
               icon or e.savedIcon
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

-- groups live in an account-wide profile, so spells must be filtered per character; matched by NAME so all ranks count
local knownSpells = {}
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

-- NOTE: e.off (parked in the tracked list) is deliberately NOT tested here.
-- entryUsable feeds adoption and options-list visibility -- an off entry that
-- stopped being "usable" fell out of the tracked list entirely and could
-- never be re-enabled (review find). Parking is enforced where things RENDER.
local function entryUsable(e)
    if e.kind ~= "spell" then return true end
    -- An entry stamped for another class is never usable here, whatever its
    -- name resolves to. Two classes can own DIFFERENT spells with the SAME
    -- localized name (zhCN: druid and shaman Rebirth / Nature's Swiftness),
    -- and the spellbook lookup below matches by name -- without this gate the
    -- druid's entries drew on the shaman's bars, unstamped.
    -- (classToken() is declared further down; UnitClass answers the same.)
    if e.cls then
        local myCls = select(2, UnitClass("player"))
        if myCls and e.cls ~= myCls then return false end
    end
    if not next(knownSpells) then rebuildKnownSpells() end
    local name = entryInfo(e)
    return name ~= nil and knownSpells[name:lower()] == true
end

local relayoutGroup, refreshGroup, refreshAll, layoutIcons, positionBar  -- forward declarations
local stopCustomGlow   -- glow engine, defined further down; relayoutGroup calls it

-- Keybind lookup: action slot base -> binding command. Only the always-active
-- bars; stance/page slots are deliberately excluded (their binding follows the
-- page, not the slot).
local SLOT_BINDINGS = {
    [0]  = "ACTIONBUTTON",          -- 1-12 main bar
    [24] = "MULTIACTIONBAR3BUTTON", -- 25-36 right bar
    [36] = "MULTIACTIONBAR4BUTTON", -- 37-48 right bar 2
    [48] = "MULTIACTIONBAR2BUTTON", -- 49-60 bottom right
    [60] = "MULTIACTIONBAR1BUTTON", -- 61-72 bottom left
}
local KEY_ABBREV = {
    { "SHIFT%-", "s" }, { "CTRL%-", "c" }, { "ALT%-", "a" },
    { "MOUSEWHEELUP", "wU" }, { "MOUSEWHEELDOWN", "wD" },
    { "BUTTON", "m" }, { "NUMPAD", "n" },
    { "PAGEUP", "PU" }, { "PAGEDOWN", "PD" }, { "SPACE", "Sp" },
}
local function abbrevKey(key)
    if not key then return nil end
    for _, p in ipairs(KEY_ABBREV) do key = key:gsub(p[1], p[2]) end
    return key
end

-- ranks differ between the tracked entry and the slotted action, so spells are
-- matched by id AND by lowercase name
local kbBySpellName, kbBySpellID, kbByItemID = {}, {}, {}
local kbDirty = true
local function rebuildKeybinds()
    kbDirty = false
    wipe(kbBySpellName); wipe(kbBySpellID); wipe(kbByItemID)
    if not (GetActionInfo and GetBindingKey) then return end
    for base, cmd in pairs(SLOT_BINDINGS) do
        for i = 1, 12 do
            local aType, id = GetActionInfo(base + i)
            if aType == "spell" or aType == "item" then
                local key = abbrevKey(GetBindingKey(cmd .. i))
                if key and key ~= "" then
                    if aType == "spell" and id and id ~= 0 then
                        if not kbBySpellID[id] then kbBySpellID[id] = key end
                        local n = GetSpellInfo(id)
                        if n and not kbBySpellName[n:lower()] then kbBySpellName[n:lower()] = key end
                    elseif aType == "item" and id and not kbByItemID[id] then
                        kbByItemID[id] = key
                    end
                end
            end
        end
    end
end

local function keybindFor(e, ename)
    if kbDirty then rebuildKeybinds() end
    if e.kind == "item" then return kbByItemID[e.id] end
    local k = type(e.id) == "number" and kbBySpellID[e.id] or nil
    if not k and ename then k = kbBySpellName[ename:lower()] end
    return k
end

-- ACTIONBAR_SLOT_CHANGED storms on login (one event per slot); coalesce
local kbQueued = false
local function onBindingsChanged()
    kbDirty = true
    if kbQueued then return end
    kbQueued = true
    C_Timer.After(0.2, function()
        kbQueued = false
        if not mod._enabled then return end
        for _, group in ipairs(db().groups) do
            if group.showKeybind then relayoutGroup(group) end
        end
    end)
end

-- ONE SNAPSHOT PER UNIT AND FILTER, not 40 buffs per icon. UnitAura's spellId
-- is the 10th return on 2.5.5.
--
-- Was two hand-written scans, one for the player's buffs and one for your
-- debuffs on the target. A group can now name its unit, so the scan is keyed by
-- unit AND filter instead: each combination anyone asked for is swept once per
-- refresh, and a combination nobody asked for is not swept at all.
--
-- Tables and record pools are created once per key and reused, so the ticker
-- still allocates nothing after the first sighting of a key.
local scans = {}

local function scanFor(unit, filter)
    local key = unit .. "|" .. filter
    local s = scans[key]
    if not s then s = { byName = {}, byID = {}, pool = {} }; scans[key] = s end
    return s
end

local function runScan(unit, filter)
    local s = scanFor(unit, filter)
    wipe(s.byName); wipe(s.byID)
    if not UnitExists(unit) then return end
    for i = 1, 40 do
        local name, icon, count, _, duration, expiration, caster, _, _, sid = UnitAura(unit, i, filter)
        if not name then break end
        local rec = s.pool[i]
        if not rec then rec = {}; s.pool[i] = rec end
        rec.dur, rec.exp, rec.count, rec.icon, rec.name = duration, expiration, count, icon, name
        rec.mine = (caster == "player" or caster == "pet" or caster == "vehicle")
        -- Same aura from two casters in one loose sweep: the player's own copy
        -- wins the lookup slot, so an own-only entry never misses its aura
        -- because a foreign copy happened to be scanned after it.
        local old = s.byName[name]
        if not old or (rec.mine and not old.mine) then s.byName[name] = rec end
        if sid then
            old = s.byID[sid]
            if not old or (rec.mine and not old.mine) then s.byID[sid] = rec end
        end
    end
end

-- Which unit and filter a group reads. The default keeps every existing group
-- exactly where it was: buffs on you, your own debuffs on the target.
-- ownOnly is stored as nil = "whatever this mode always did", because the two
-- modes disagree: debuffs on the target have always meant YOURS, buffs on you
-- have always meant any. Writing one shared default would silently change one
-- of the two for every group that exists.
local function groupOwnOnly(group)
    if group.auraOwnOnly ~= nil then return group.auraOwnOnly end
    return group.mode == "targetdebuff"
end

-- Per-entry override of the group switch (user request from the Titan report:
-- track a Focus Magic someone casts ON you while the rest of the group stays
-- own-only). nil inherits the group.
local function entryOwnOnly(group, e)
    if e and e.ownOnly ~= nil then return e.ownOnly end
    return groupOwnOnly(group)
end

-- A group scans LOOSE (no |PLAYER) as soon as one entry may count foreign
-- casts; entries that still want their own get that enforced per record at
-- match time (rec.mine). All-own groups keep the cheap filtered sweep.
local function groupNeedsLoose(group)
    if not groupOwnOnly(group) then return true end
    local es = group.entries
    if es then
        for i = 1, #es do
            if es[i].ownOnly == false then return true end
        end
    end
    return false
end

local function groupSource(group)
    local mode = group.mode
    local harmful = (mode == "targetdebuff")
    local unit = group.auraUnit or (harmful and "target" or "player")
    local filter = harmful and "HARMFUL" or "HELPFUL"
    if not groupNeedsLoose(group) then filter = filter .. "|PLAYER" end
    return unit, filter
end

-- kept off the group table: that table is saved to disk and these lists hold frames
local activeBufOf, activePrevOf = {}, {}
local function activeBuffers(group)
    local buf = activeBufOf[group]
    if not buf then buf = {}; activeBufOf[group] = buf end
    wipe(buf)
    return buf
end

-- DYNAMIC ORDER, optional.
--
-- The list arrives in the order the entries were added. Sorting it by what is
-- left puts the icon that needs attention at the front -- which is the whole
-- point of a proc or DoT bar.
--
-- The entry position is the tiebreaker, and it is not optional: two auras with
-- the same remaining time would otherwise swap places on every tick, and a
-- flickering row is worse than an unsorted one. table.sort is not stable, so
-- the tiebreak has to be in the comparator, not left to luck.
local function sortRemainingAsc(a, b)
    local ra = (a._sortRem or math.huge)
    local rb = (b._sortRem or math.huge)
    if ra ~= rb then return ra < rb end
    return (a._sortIdx or 0) < (b._sortIdx or 0)
end

local function sortRemainingDesc(a, b)
    local ra = (a._sortRem or -1)
    local rb = (b._sortRem or -1)
    if ra ~= rb then return ra > rb end
    return (a._sortIdx or 0) < (b._sortIdx or 0)
end

local function sortActive(group, active, now)
    local how = group.sortBy
    if not how or how == "fixed" or #active < 2 then return end
    for i = 1, #active do
        local f = active[i]
        f._sortIdx = i
        local rec = f._rec
        if rec and rec.exp and rec.exp > 0 then
            f._sortRem = rec.exp - now
        elseif f._cdEnd and f._cdEnd > now then
            f._sortRem = f._cdEnd - now       -- cooldown groups sort by what is left of the cooldown
        else
            f._sortRem = nil                  -- no timer: parked at the end either way
        end
    end
    table.sort(active, how == "longest" and sortRemainingDesc or sortRemainingAsc)
end

local function packIfChanged(group, active)
    local prev, same = activePrevOf[group], false
    if prev and #prev == #active then
        same = true
        for j = 1, #active do if prev[j] ~= active[j] then same = false; break end end
    end
    if not same then
        layoutIcons(group, active)
        prev = activePrevOf[group] or {}
        wipe(prev)
        for j = 1, #active do prev[j] = active[j] end
        activePrevOf[group] = prev
    end
end

-- base spell id -> reagent item id; resolved to the localized name at runtime so all ranks match
local SPELL_REAGENT_IDS = {
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
    [1122]  = 5565,  -- Inferno
    [18540] = 18796, -- Ritual of Doom
}
local reagentByName = {}
local function buildReagentMap()
    wipe(reagentByName)
    for spellID, itemID in pairs(SPELL_REAGENT_IDS) do
        local n = GetSpellInfo(spellID)
        if n then reagentByName[n] = itemID end
    end
end

-- corner number: reagent count where the spell consumes one, else the aura stack count
local function applyStack(group, f, rec)
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
    -- target-debuff groups pass their rec in, since they read a different snapshot than the fallback below
    local ps = scanFor("player", "HELPFUL")
    rec = rec or (e and ps.byID[e.id]) or (f.entryName and ps.byName[f.entryName])
    if rec and rec.count and rec.count > 1 then
        f.stack:SetText(rec.count); f.stack:Show()
    else
        f.stack:Hide()
    end
end

-- Class scoping, like the reference: a spell belongs to the class it was added
-- on and is invisible everywhere else. Items stay class-free -- a trinket is
-- usable by everyone, and the auto-trinket sync manages them per character
-- anyway. Stamped at add time; legacy entries without a stamp are adopted by
-- the first class that logs in and actually knows the spell (see adoptEntries).
local myClassToken
local function classToken()
    if not myClassToken then myClassToken = select(2, UnitClass("player")) end
    return myClassToken
end

local function entryVisibleHere(e)
    if e.kind ~= "spell" then return true end
    if e.cls then return e.cls == classToken() end
    return entryUsable(e)   -- legacy entry, not yet adopted by its class
end

-- True/false when the client can answer by ID, nil when it cannot (no API,
-- or the id is a raw name string). IsSpellKnown answers for every LEARNED
-- rank, so the name shortcut below stays only for clients without the APIs.
local function spellKnownByID(id)
    if type(id) ~= "number" then return nil end
    if not (IsPlayerSpell or IsSpellKnown) then return nil end
    local has = IsPlayerSpell and IsPlayerSpell(id)
    if not has and IsSpellKnown then
        has = IsSpellKnown(id) or IsSpellKnown(id, true)
    end
    return has and true or false
end

local function adoptEntries()
    local cls = classToken()
    if not cls then return end
    for _, g in ipairs(db().groups) do
        for _, e in ipairs(g.entries) do
            if e.kind == "spell" and not e.cls then
                -- By ID first: adoption by NAME is exactly how a druid's
                -- entries got stamped SHAMAN on a zhCN client where both
                -- classes own same-named spells.
                local known = spellKnownByID(e.id)
                if known == nil then known = entryUsable(e) end
                if known then e.cls = cls end
            end
        end
    end
end

local function addEntry(group, input)
    if not group then return false end
    local kind, id = resolveInput(input, group.mode ~= "cooldown")
    if not kind then
        ns:Print(L["Cooldown Manager: '%s' is not a known spell or item."], tostring(input))
        return false
    end
    if groupHas(group, kind, id) then
        ns:Print(L["Cooldown Manager: already tracking that."])
        return false
    end
    local e = { kind = kind, id = id }
    if kind == "spell" then e.cls = classToken() end
    group.entries[#group.entries + 1] = e
    relayoutGroup(group)
    local name = entryInfo(e)
    ns:Print(L["Cooldown Manager: added %s."], name or ("#" .. id))
    return true
end

local function makeIcon(bar, i)
    local f = CreateFrame("Frame", nil, bar)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    if f.CreateMaskTexture and f.tex.AddMaskTexture then
        f.mask = f:CreateMaskTexture()
        f.mask:SetAllPoints(f.tex)
        f.tex:AddMaskTexture(f.mask)
    end

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetAllPoints(f)
    f.border:SetColorTexture(0, 0, 0, 1)

    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 5)
    f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 5, -5)
    f.glow:Hide()

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

    -- own frame above the cooldown sweep, else the sweep dims the number
    f.textHost = CreateFrame("Frame", nil, f)
    f.textHost:SetAllPoints(f)
    f.textHost:SetFrameLevel(f.cd:GetFrameLevel() + 5)

    f.text = f.textHost:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(fontPath(), 16, "OUTLINE")
    f.text:SetPoint("CENTER", f.textHost, "CENTER", 0, 0)
    f.text:SetShadowColor(0, 0, 0, 1)
    f.text:SetShadowOffset(1, -1)

    f.stack = f.textHost:CreateFontString(nil, "OVERLAY")
    f.stack:SetFont(fontPath(), 13, "OUTLINE")
    f.stack:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.stack:SetTextColor(1, 0.95, 0.6)
    f.stack:Hide()

    f.keybind = f.textHost:CreateFontString(nil, "OVERLAY")
    f.keybind:SetFont(fontPath(), 10, "OUTLINE")
    f.keybind:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.keybind:Hide()

    f.flash = f.textHost:CreateTexture(nil, "OVERLAY")
    f.flash:SetTexture("Interface\\Cooldown\\star4")
    f.flash:SetBlendMode("ADD")
    f.flash:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.flash:Hide()

    f:EnableMouse(false)
    f:SetScript("OnEnter", function(self)
        local e = self.entry
        -- The body is a spell or item tooltip, which no spec table can express.
        if not e or not ns.UI:OpenTooltip(self, "ANCHOR_RIGHT") then return end
        if e.kind == "item" then
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(e.id)
            else pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. e.id) end
        else
            local sid = tonumber(e.id)
            if sid and GameTooltip.SetSpellByID then
                pcall(GameTooltip.SetSpellByID, GameTooltip, sid)
            else
                GameTooltip:SetText(self.entryName or tostring(e.id))
            end
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
    f:SetScript("OnReceiveDrag", function()
        -- fetched off the bar because the handler is defined later; an upvalue would bind nil here
        local h = bar:GetScript("OnReceiveDrag")
        if h then h(bar) end
    end)
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
    -- sublevel below the icons' own BACKGROUND textures so borders stay on top
    bar.bg = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
    bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -4, 4)
    bar.bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 4, -4)
    bar.bg:Hide()
    bar._icons = {}
    bar._group = group
    bar:SetScript("OnReceiveDrag", function(self) onReceiveDrag(self) end)

    bar.mover = ns:CreateMover(bar, {
        key    = "cdm:" .. tostring(group.id or group.name or "?"),
        label  = group.name,
        db     = group,
        width  = 150,
        height = 34,
        -- a manual drag writes an absolute position, so it detaches the bar from any anchor
        onMove   = function(x, y) group.x, group.y = x, y; group.anchorTo = nil end,
        applyPos = function() positionBar(group) end,
        editPreview = function() refreshAll() end,
        scope    = "cooldownmanager",
    })

    barOf[group] = bar
    allBars[#allBars + 1] = bar
    return bar
end

local ANCHOR_FRAMES
ns.OnLocaleReady(function()
ANCHOR_FRAMES = {
    { frame = "PlayerFrame", label = L["Player Frame"] },
    { frame = "TargetFrame", label = L["Target Frame"] },
    { frame = "FocusFrame",  label = L["Focus Frame"] },
    { frame = "PetFrame",    label = L["Pet Frame"] },
    { frame = "Minimap",     label = L["Minimap"] },
}
end)

local function groupByID(id)
    if not id then return nil end
    for _, g in ipairs(db().groups) do if g.id == id then return g end end
    return nil
end

-- anchorTo: "f:<FrameName>" for a Blizzard frame, numeric id for another group's bar, nil for free
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

positionBar = function(group)
    local bar = barOf[group]
    if not bar then return end
    bar:ClearAllPoints()
    local target = anchorTargetFrame(group)
    local side = ANCHOR_SIDES[group.anchorSide or "BELOW"]
    if target and side then
        bar:SetPoint(side[1], target, side[2], group.x or 0, group.y or 0)
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", group.x or 0, group.y or -160)
    end
end

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
    -- an icon-less bar must not leave a floating background rectangle behind
    if bar.bg then bar.bg:SetShown(group.barBg == true and count > 0) end
end

relayoutGroup = function(group)
    local bar = ensureBar(group)
    -- drop the pack memory, else packIfChanged skips an unchanged set now sitting at stale coordinates
    activePrevOf[group] = nil
    local size = group.iconSize
    local entries = group.entries
    local icons = bar._icons

    bar:SetScale(group.scale or 1)
    do
        -- color only; layoutIcons owns visibility (an empty bar must show no bg)
        local c = group.barBgColor
        bar.bg:SetColorTexture((c and c.r) or 0, (c and c.g) or 0, (c and c.b) or 0,
            group.barBgAlpha or 0.5)
    end
    local inset = group.borderSize
    if inset == nil then inset = 1 end
    local br, bgc, bbc = groupBorderColor(group)

    for i, e in ipairs(entries) do
        local f = icons[i]
        if not f then f = makeIcon(bar, i); icons[i] = f end
        local ename, icon = entryInfo(e)
        f.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local z = group.iconZoom or 0.08
        f.tex:SetTexCoord(z, 1 - z, z, 1 - z)
        f.tex:ClearAllPoints()
        f.tex:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
        f.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
        if f.mask then
            f.mask:SetTexture(shapeMask(group.iconShape), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        -- SetSwipeColor's alpha can be a no-op in 2.5.5, so dim the whole cooldown frame instead
        if f.cd.SetSwipeColor then f.cd:SetSwipeColor(0, 0, 0, 1) end
        f.cd:SetAlpha(group.swipeAlpha or 0.6)
        f.text:SetFont(fontPath(), math.max(8, math.floor(size * (group.textScale or 0.4))), "OUTLINE")
        local si = STACK_INSETS[group.stackPos or "BOTTOMRIGHT"] or STACK_INSETS.BOTTOMRIGHT
        f.stack:ClearAllPoints()
        f.stack:SetPoint(si[1], f, si[1], si[2], si[3])
        f.stack:SetFont(fontPath(), group.stackSize or 13, "OUTLINE")
        local sc = group.stackColor or { r = 1, g = 0.95, b = 0.6 }
        f.stack:SetTextColor(sc.r or 1, sc.g or 0.95, sc.b or 0.6)
        -- cooldown mode only: the toggle lives in that options branch, so an
        -- aura group could otherwise wear a keybind it can no longer turn off
        if group.showKeybind and group.mode == "cooldown" then
            f.keybind:SetFont(fontPath(), group.keybindSize or 10, "OUTLINE")
            local kc = group.keybindColor
            f.keybind:SetTextColor((kc and kc.r) or 0.9, (kc and kc.g) or 0.9, (kc and kc.b) or 0.9)
            f.keybind:SetText(keybindFor(e, ename) or "")
            f.keybind:Show()
        else
            f.keybind:Hide()
        end
        f.entry     = e
        f.entryName = ename
        f._auraIconTex = nil
        f.prevRemain = 0
        f.flashT = nil
        f.border:SetColorTexture(br, bgc, bbc, 1)
        -- at 0 thickness the plate must vanish: circle/rounded masks only cut the
        -- ICON, so the square border plate would peek out at the corners
        f.border:SetShown(borderVisible(group))
        f.glow:Hide()
        if f.proc then
            f.proc:Hide(); f.proc:SetSize(size * 1.4, size * 1.4)
            if f.procAnim and f.procAnim:IsPlaying() then f.procAnim:Stop() end
        end
        f.stack:Hide()
        f.usable = entryUsable(e) and not e.off
        f:EnableMouse(group.showTooltips == true)
        f:SetSize(size, size)
        -- A running glow belongs to whatever this frame showed BEFORE the
        -- relayout: the entry may have shifted, and the button style bakes the
        -- icon size into its ring at start. Stopping here costs one restart on
        -- the next tick and buys correct geometry and ownership.
        if f.customGlow then stopCustomGlow(f) end
        if f.usable then f:Show() else f:Hide() end
    end
    for i = #entries + 1, #icons do icons[i]:Hide() end

    if group.mode == "aura" or group.mode == "targetdebuff" or group.mode == "missing" then
        runScan(groupSource(group))
        refreshGroup(group, GetTime())
    else
        local all = {}
        for i = 1, #entries do
            local f = icons[i]
            if f.usable then all[#all + 1] = f else f:Hide() end
        end
        if #all == 0 then
            bar:SetSize(size, size)
            if bar.bg then bar.bg:Hide() end
        else
            layoutIcons(group, all)
        end
    end

    -- keep the options-page preview strip in step with whatever reshaped the bar
    if mod.RefreshStrip then mod.RefreshStrip(group) end
end

-- ---------------------------------------------------------------------------
-- Custom bar glows (the reference's model, ported 30.07.2026). An entry may
-- carry a LIST e.glows of watchers { name, id, style, mode, combat, colorMode,
-- color }. A watcher looks at YOUR buffs: mode "ACTIVE" glows while the buff
-- is on you, "MISSING" while it is not, and combat gates it to fights. The
-- first watcher whose condition holds paints the icon -- one overlay per icon,
-- list order is the priority. Evaluated on the shared ticker off the same
-- player-aura snapshot the bars already use; the animation only starts or
-- stops on a state flip, never mid-pulse.
--
-- Three styles, the portable subset of the reference's seven: its flipbook
-- styles need a 10.x animation API and its sparkle texture does not exist on
-- this client.

local GLOW_GOLD = { r = 1, g = 0.788, b = 0.137 }   -- the reference's default gold

local GLOW_RING = "Interface\\SpellActivationOverlay\\IconAlert"
local GLOW_ANTS = "Interface\\SpellActivationOverlay\\IconAlertAnts"
-- 5x5 grid of 48px cells on 256px; the last three cells are blank
local ANTS_COLS, ANTS_CELLS, ANTS_CELL = 5, 22, 48 / 256

local function glowColor(g)
    if g.colorMode == "class" then
        local _, cls = UnitClass("player")
        local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        if c then return c.r, c.g, c.b end
    elseif g.colorMode == "custom" and g.color then
        return g.color.r or 1, g.color.g or 1, g.color.b or 1
    end
    return GLOW_GOLD.r, GLOW_GOLD.g, GLOW_GOLD.b
end

local function glowConditionHolds(g)
    if g.combat and not (InCombatLockdown() or UnitAffectingCombat("player")) then
        return false
    end
    local s = scanFor("player", "HELPFUL")
    local present = (g.id and s.byID[g.id]) or (g.name and s.byName[g.name])
    if g.mode == "MISSING" then return not present end
    return present ~= nil
end

local function ensureGlowOverlay(f)
    local o = f.customGlow
    if o then return o end
    o = CreateFrame("Frame", nil, f)
    o:SetAllPoints(f)
    o:SetFrameLevel(f:GetFrameLevel() + 15)   -- the reference's overlay level

    o.edges = ns.MakeEdges(o, "OVERLAY")

    o.ring = o:CreateTexture(nil, "OVERLAY", nil, 1)
    o.ring:SetTexture(GLOW_RING)
    o.ring:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)
    o.ring:SetBlendMode("ADD")
    o.ring:SetPoint("CENTER", o, "CENTER", 0, 0)
    o.ring:Hide()

    o.ants = o:CreateTexture(nil, "OVERLAY", nil, 2)
    o.ants:SetTexture(GLOW_ANTS)
    o.ants:SetDesaturated(true)
    o.ants:SetBlendMode("ADD")
    o.ants:SetPoint("CENTER", o, "CENTER", 0, 0)
    o.ants:Hide()

    o.fill = o:CreateTexture(nil, "OVERLAY", nil, 0)
    o.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    o.fill:SetBlendMode("ADD")
    o.fill:SetAllPoints(f)
    -- the same mask that shapes the icon shapes the fill (the reference's
    -- shape glow); square icons simply have no mask to add
    if f.mask and o.fill.AddMaskTexture then o.fill:AddMaskTexture(f.mask) end
    o.fill:Hide()

    o:Hide()
    f.customGlow = o
    return o
end

-- assignment, not declaration: forward-declared next to relayoutGroup, which
-- stops a glow whenever an icon is re-purposed or re-sized
stopCustomGlow = function(f)
    local o = f.customGlow
    if not (o and o._style) then return end
    o._style = nil
    o:SetScript("OnUpdate", nil)
    o:Hide()
end

local function glowDriver(o, elapsed)
    local t = GetTime()
    if o._style == "pixel" then
        o:SetAlpha(0.55 + 0.35 * math.sin(t * 6))
    elseif o._style == "fill" then
        -- 0.25 +- 0.25, the reference's pulse at its speed
        o:SetAlpha(0.5 + 0.5 * math.sin(t * 10))
    elseif o._style == "button" then
        o._acc = (o._acc or 0) + elapsed
        if o._acc >= 0.017 then                  -- the reference's cell cadence
            o._cell = ((o._cell or 0) + 1) % ANTS_CELLS
            o._acc = 0
            local col = o._cell % ANTS_COLS
            local row = math.floor(o._cell / ANTS_COLS)
            o.ants:SetTexCoord(col * ANTS_CELL, (col + 1) * ANTS_CELL,
                               row * ANTS_CELL, (row + 1) * ANTS_CELL)
        end
    end
end

local function startCustomGlow(f, style, r, g, b)
    local o = ensureGlowOverlay(f)
    if o._style == style and o._r == r and o._g == g and o._b == b then return end
    o._style, o._r, o._g, o._b = style, r, g, b
    o._acc, o._cell = 0, 0

    for _, e in pairs(o.edges) do e:Hide() end
    o.ring:Hide(); o.ants:Hide(); o.fill:Hide()
    o:SetAlpha(1)

    if style == "button" then
        -- the reference's scale chain: ants 1.35x the button, ring 1.3x the ants
        local w, h = f:GetWidth() or 32, f:GetHeight() or 32
        o.ants:SetSize(w * 1.35, h * 1.35)
        o.ants:SetVertexColor(r, g, b)
        o.ants:Show()
        o.ring:SetSize(w * 1.35 * 1.3, h * 1.35 * 1.3)
        o.ring:SetVertexColor(r, g, b)
        o.ring:Show()
    elseif style == "fill" then
        o.fill:SetVertexColor(r, g, b, 0.5)
        o.fill:Show()
    else -- pixel
        ns.LayoutEdges(o.edges, o, 2, r, g, b, 1, 1)
    end

    o:SetScript("OnUpdate", glowDriver)
    o:Show()
end

-- One pass per group per tick, both bar modes. Hidden icons are skipped but
-- keep their glow state: OnUpdate does not run on hidden frames, and the state
-- memory prevents an animation restart when they come back.
local function applyGroupGlows(group)
    local bar = barOf[group]
    local icons = bar and bar._icons
    if not icons then return end
    for i = 1, #group.entries do
        local f = icons[i]
        if f then
            local glows = group.entries[i].glows
            if f:IsShown() and glows and #glows > 0 then
                local win
                for gi = 1, #glows do
                    if glowConditionHolds(glows[gi]) then win = glows[gi]; break end
                end
                if win then
                    startCustomGlow(f, win.style or "pixel", glowColor(win))
                else
                    stopCustomGlow(f)
                end
            elseif f.customGlow then
                stopCustomGlow(f)
            end
        end
    end
end

local function groupHasGlows(group)
    for i = 1, #group.entries do
        local gl = group.entries[i].glows
        if gl and #gl > 0 then return true end
    end
    return false
end

local function updateIcon(group, f, now)
    local e = f.entry
    if not e then return end
    local start, duration, enabled = entryCooldown(e)
    local minDur = group.minDuration or GCD_MAX
    local onCD = enabled ~= 0 and duration and duration > minDur
        and start and (start + duration - now) > 0

    -- Remembered for the optional sort, which runs after every icon is updated
    -- and has no other way back to the cooldown's end.
    f._cdEnd = onCD and (start + duration) or nil

    if onCD then
        local remain = start + duration - now
        f.cd:SetCooldown(start, duration)
        if group.showText then
            -- the visible text only changes when the second (or minute) does;
            -- rebuilding the string ten times a second per icon added up
            local bucket = remain >= 60 and -math.floor(remain / 60 + 0.5) or math.ceil(remain)
            if f._textBucket ~= bucket then
                f._textBucket = bucket
                f.text:SetText(fmtRemain(remain))
            end
            applyTimerColor(group, f.text, remain)
            f.text:Show()
        else
            f._textBucket = nil
            f.text:Hide()
        end
        if group.desaturate then f.tex:SetDesaturated(true); f.tex:SetVertexColor(0.6, 0.6, 0.6)
        else f.tex:SetDesaturated(false); f.tex:SetVertexColor(1, 1, 1) end
        f.glow:Hide()
        f.prevRemain = remain
        if group.onlyOnCooldown then f:Show() end
    else
        f.cd:Clear()
        f._textBucket = nil
        f.text:Hide()
        f.tex:SetDesaturated(false)
        f.tex:SetVertexColor(1, 1, 1)
        if e.kind == "spell" then
            local tinted = false
            if group.tintUnusable ~= false and IsUsableSpell then
                local usable, noMana = IsUsableSpell(e.id)
                if noMana then
                    f.tex:SetVertexColor(0.4, 0.45, 0.9); tinted = true
                elseif not usable then
                    f.tex:SetVertexColor(0.45, 0.45, 0.45); tinted = true
                end
            end
            if not tinted and group.tintRange and IsSpellInRange
               and f.entryName and UnitExists("target") then
                if IsSpellInRange(f.entryName, "target") == 0 then
                    f.tex:SetVertexColor(0.9, 0.3, 0.3)
                end
            end
        end
        if group.readyFlash and (f.prevRemain or 0) > 0 then
            f.flashT = 0
            f.flash:SetAlpha(0.9)
            f.flash:Show()
        end
        if group.readyGlow then
            local usable = true
            if e.kind == "spell" and IsUsableSpell then
                usable = IsUsableSpell(e.id) and true or false
            end
            if usable then
                local c = AURA_COLORS[group.readyGlowColor or "yellow"] or AURA_COLORS.yellow
                f.glow:SetVertexColor(c[1], c[2], c[3], 0.9)
                f.glow:Show()
            else
                f.glow:Hide()
            end
        else
            f.glow:Hide()
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

    applyStack(group, f)
end

local function stopProc(f)
    if f.proc then
        f.proc:Hide()
        if f.procAnim and f.procAnim:IsPlaying() then f.procAnim:Stop() end
    end
end

local function applyAuraStyle(group, f)
    local style = group.auraStyle or "glow"
    local c = AURA_COLORS[group.auraColor or "yellow"] or AURA_COLORS.yellow
    local br, bg, bb = groupBorderColor(group)
    -- the "border" highlight style needs the plate even at 0 thickness; every
    -- other style re-asserts the group's border visibility (the style dropdown
    -- refreshes without a relayout)
    if style == "proc" then
        f.glow:Hide(); f.border:SetColorTexture(br, bg, bb, 1)
        f.border:SetShown(borderVisible(group))
        if f.proc then
            f.proc:SetVertexColor(c[1], c[2], c[3], 1)
            f.proc:Show()
            if f.procAnim and not f.procAnim:IsPlaying() then f.procAnim:Play() end
        end
    elseif style == "glow" then
        stopProc(f)
        f.glow:SetVertexColor(c[1], c[2], c[3], 0.9); f.glow:Show()
        f.border:SetColorTexture(br, bg, bb, 1)
        f.border:SetShown(borderVisible(group))
    elseif style == "border" then
        stopProc(f)
        f.glow:Hide(); f.border:SetColorTexture(c[1], c[2], c[3], 1)
        f.border:Show()
    else
        stopProc(f)
        f.glow:Hide(); f.border:SetColorTexture(br, bg, bb, 1)
        f.border:SetShown(borderVisible(group))
    end
end

-- aura groups with "show inactive": the buff is gone, keep the icon greyed out
local function updateInactiveIcon(group, f)
    f.tex:SetDesaturated(true)
    f.tex:SetVertexColor(0.55, 0.55, 0.55)
    f.cd:Clear()
    f.text:Hide()
    f.stack:Hide()
    stopProc(f)
    f.glow:Hide()
    f.border:SetColorTexture(groupBorderColor(group))
    f.border:SetShown(borderVisible(group))
end

local function updateMissingIcon(group, f)
    f.tex:SetDesaturated(false)
    f.tex:SetVertexColor(1, 1, 1)
    f.cd:Clear()
    f.text:Hide()
    f.stack:Hide()
    applyAuraStyle(group, f)
end

local function updateAuraIcon(group, f, rec, now)
    f.tex:SetDesaturated(false)
    f.tex:SetVertexColor(1, 1, 1)
    applyAuraStyle(group, f)
    if rec.exp and rec.dur and rec.dur > 0 then
        f.cd:SetCooldown(rec.exp - rec.dur, rec.dur)
        local remain = rec.exp - now
        if group.showText and remain > 0 then
            f.text:SetText(fmtRemain(remain))
            applyTimerColor(group, f.text, remain)
            f.text:Show()
        else
            f.text:Hide()
        end
    else
        f.cd:Clear()
        f.text:Hide()
    end
    applyStack(group, f, rec)
end

-- PER-ENTRY CONDITIONS on an aura.
--
-- Two thresholds rather than the operator dropdowns a full trigger editor
-- offers: in practice only two directions are ever used -- "from N stacks
-- upward" and "in the last N seconds" -- and a fixed direction is one less
-- thing to read on a row that already carries a number.
--
-- 0 means the threshold is off, so an entry that predates this passes
-- unchanged. e.cond is the master switch: with it off nothing here is even
-- looked at, which keeps the scan free for everyone who does not use it.
local function entryPasses(e, rec, now)
    if not (e and e.cond and rec) then return true end
    if (e.minStacks or 0) > 0 and (rec.count or 0) < e.minStacks then return false end
    if (e.maxRemaining or 0) > 0 then
        -- An aura without a duration never "runs out", so a remaining-time
        -- condition can never be true for it. Hiding is the honest answer;
        -- treating it as always-about-to-expire would be a lie.
        if not rec.exp or rec.exp <= 0 then return false end
        if (rec.exp - now) > e.maxRemaining then return false end
    end
    return true
end

refreshGroup = function(group, now)
    local bar = barOf[group]
    if not bar then return end
    local icons = bar._icons
    local mode = group.mode

    if mode == "aura" or mode == "targetdebuff" or mode == "missing" then
        local s = scanFor(groupSource(group))
        local byID, byName = s.byID, s.byName
        local invert = (mode == "missing")

        local active = activeBuffers(group)
        for i = 1, #group.entries do
            local f = icons[i]
            if f then
                local e = f.entry
                local rec = (e and byID[e.id]) or (f.entryName and byName[f.entryName])
                -- Per-entry own-only: on a loose sweep a foreign cast is a
                -- record like any other; for an entry that wants only its own
                -- it counts as absent. On a |PLAYER sweep rec.mine is always
                -- true, so this line costs nothing there.
                if rec and not rec.mine and entryOwnOnly(group, e) then rec = nil end
                -- cache name/icon on first sighting; missing mode has rec == nil and would stay "?" otherwise
                if rec and e then
                    if rec.name and not e.savedName then e.savedName = rec.name end
                    if rec.icon and not e.savedIcon then e.savedIcon = rec.icon end
                end
                local show = invert and (rec == nil) or (not invert and rec ~= nil)
                -- Conditions only narrow a PRESENT aura. In "missing" mode there
                -- is no record to measure, so they are skipped rather than
                -- silently inverted.
                if show and not invert and not entryPasses(e, rec, now) then show = false end
                -- "show inactive" keeps expired buffs visible (greyed) so the layout never jumps
                if not show and mode == "aura" and group.showInactive then show = true end
                -- switched off in the tracked list: never shown, in any mode
                -- (after showInactive, which would resurrect it)
                if e and e.off then show = false end
                if show then
                    active[#active + 1] = f
                    f._rec = rec
                    if rec and rec.icon and f._auraIconTex ~= rec.icon then
                        f.tex:SetTexture(rec.icon); f._auraIconTex = rec.icon
                    end
                    f:Show()
                else
                    f.stack:Hide()
                    f:Hide()
                end
            end
        end
        sortActive(group, active, now)
        packIfChanged(group, active)
        for _, f in ipairs(active) do
            if invert then updateMissingIcon(group, f)
            elseif f._rec then updateAuraIcon(group, f, f._rec, now)
            else updateInactiveIcon(group, f) end
        end
        applyGroupGlows(group)
        return
    end

    -- "only on cooldown" shifts the shown set constantly, so re-pack to avoid
    -- holes in the grid. A dynamic order needs the same re-pack for a different
    -- reason -- the icons have to be placed again once they change places --
    -- so it switches packing on as well. Nothing is hidden by that: with
    -- "only on cooldown" off, every usable icon is in the list anyway.
    local pack = group.onlyOnCooldown or (group.sortBy and group.sortBy ~= "fixed")
    local active = pack and activeBuffers(group) or nil
    for i = 1, #group.entries do
        local f = icons[i]
        if f and f.usable and (f:IsShown() or pack) then
            updateIcon(group, f, now)
            if pack and f:IsShown() then active[#active + 1] = f end
        end
    end
    if pack then sortActive(group, active, now); packIfChanged(group, active) end
    applyGroupGlows(group)
end

local visCache = {}
local wantedScans = {}   -- set of "unit|filter" needed this tick; reused, never rebuilt

refreshAll = function()
    if not mod._enabled then return end
    local now = GetTime()
    local groups = db().groups

    -- The two scans below are by far the most expensive thing this module does,
    -- and it runs ten times a second for the whole session. Two conditions were
    -- missing here: a hidden group needs no aura data at all, and neither does a
    -- group with nothing in it. showStacks is on by default, so testing it on its
    -- own made needPlayer true for everyone - a UnitAura sweep every tenth of a
    -- second whether or not a single entry had ever been configured.
    -- barVisible reads only edit mode, filters, combat, mount, instance and
    -- target, never aura state, so deciding it up front changes no behaviour.
    -- Collected as a set of (unit, filter) pairs, so two groups reading the same
    -- unit share one sweep. wanted is reused; the ticker allocates nothing.
    wipe(visCache)
    wipe(wantedScans)
    for i, g in ipairs(groups) do
        local vis = barVisible(g)
        visCache[i] = vis
        local hasWork = (g.entries and #g.entries > 0) or g.autoTrinkets == true
        if vis and hasWork then
            if g.mode == "aura" or g.mode == "missing" or g.mode == "targetdebuff" then
                local unit, filter = groupSource(g)
                wantedScans[unit .. "|" .. filter] = true
            end
            -- the stack number on a cooldown icon reads the player's own
            -- auras, and so do the custom glow watchers
            if g.showStacks or groupHasGlows(g) then
                wantedScans["player|HELPFUL"] = true
            end
        end
    end
    for key in pairs(wantedScans) do
        local unit, filter = key:match("^([^|]+)|(.+)$")
        if unit then runScan(unit, filter) end
    end

    for i, group in ipairs(groups) do
        local bar = barOf[group]
        local vis = visCache[i]
        if bar then
            bar:SetShown(vis)
            -- full opacity while editing, or the bar could be dragged invisibly
            local editing = ns:IsMoverEditMode("cooldownmanager") or group.unlocked
            bar:SetAlpha(editing and 1 or (group.alpha or 1))
        end
        if vis then refreshGroup(group, now) end
    end

    -- cooldowns that start while the options page is open reach the preview
    -- strip here; the function is a cheap no-op while the page is closed
    if mod.UpdateStripCooldowns then mod.UpdateStripCooldowns() end
end

-- C_Timer.After(0) fires next frame, collapsing a burst of events into one refreshAll
local _refreshQueued = false
local function refreshSoon()
    if _refreshQueued then return end
    _refreshQueued = true
    C_Timer.After(0, function()
        _refreshQueued = false
        if mod._enabled then refreshAll() end
    end)
end

local function onUnitAura(_, unit)
    if unit == "player" or unit == "target" then refreshSoon() end
end

local function onCombat()
    -- read live state, not an event arg: ns:RegisterEvent dispatches (event, ...)
    inCombat = not not UnitAffectingCombat("player")
    refreshAll()
end

local function syncAutoTrinkets(group)
    local changed = false
    if not group.autoTrinkets then
        for i = #group.entries, 1, -1 do
            if group.entries[i].auto then table.remove(group.entries, i); changed = true end
        end
        return changed
    end
    local want = {}
    for _, slot in ipairs({ 13, 14 }) do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if id then want[id] = true end
    end
    for i = #group.entries, 1, -1 do
        local e = group.entries[i]
        if e.kind == "item" and want[e.id] then
            want[e.id] = nil
        elseif e.auto then
            table.remove(group.entries, i)
            changed = true
        end
    end
    for id in pairs(want) do
        group.entries[#group.entries + 1] = { kind = "item", id = id, auto = true }
        changed = true
    end
    return changed
end

local function onEquipChanged()
    for _, group in ipairs(db().groups) do
        if group.autoTrinkets and syncAutoTrinkets(group) then
            relayoutGroup(group)
        end
    end
end

local function rebuildBars()
    -- Managing bars from the options page works while the module is off, but
    -- showing them must not: a disabled module's refreshAll is a no-op, so the
    -- bars would stand on screen with frozen icons until the next reload.
    if not mod._enabled then return end
    rebuildKnownSpells()
    -- after the spellbook scan: adoption decides by what this class knows
    adoptEntries()
    buildReagentMap()
    ensureGroupIDs()
    for _, b in ipairs(allBars) do b:Hide() end
    for _, group in ipairs(db().groups) do
        local bar = ensureBar(group)
        bar:Show()
        if bar.mover and bar.mover.label then bar.mover.label:SetText(group.name) end
        syncAutoTrinkets(group)
        relayoutGroup(group)
    end
    -- only after every bar exists can an anchor target any other bar
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

ns:RegisterSlash({ key = "CDEDIT", commands = { "/cdedit" },
    desc = "Unlock the cooldown bars so they can be dragged.",
    module = "cooldownmanager",
})
ns.Slash.CDEDIT = function()
    ns:SetMoversEditMode(not ns:IsMoverEditMode("cooldownmanager"), "cooldownmanager")
    -- the toggle releases a lent preview bar; if the page is open, redraw it so
    -- the preview box explains itself instead of sitting empty
    if mod.RebuildPage then mod.RebuildPage() end
end

function mod:OnEnable()
    ensureGroups()
    -- Each group carries its own saved unlock, which overrides every visibility
    -- filter - including "Never" - and the bar opacity slider. setUnlocked is
    -- the only thing that shows the mover, and it does not run on load.
    for _, group in ipairs(db().groups) do group.unlocked = false end
    -- On the shared ticker. NOT a saving in itself -- the private frame this
    -- replaced was already hidden while the module was off, so it cost nothing
    -- either. What it buys is one driver instead of one frame per module, and
    -- a cancel that is symmetric with the enable.
    if not driver then driver = ns:AddTicker(0.1, refreshAll, nil, "cooldownmanager") end
    inCombat = InCombatLockdown() and true or false
    rebuildBars()
    mod:RegisterEvent("SPELL_UPDATE_COOLDOWN", refreshSoon)
    mod:RegisterEvent("BAG_UPDATE_COOLDOWN",   refreshSoon)
    mod:RegisterEvent("PLAYER_ENTERING_WORLD", refreshAll)
    mod:RegisterEvent("SPELLS_CHANGED",        rebuildBars)
    mod:RegisterEvent("UNIT_AURA",             onUnitAura)
    mod:RegisterEvent("PLAYER_REGEN_DISABLED", onCombat)
    mod:RegisterEvent("PLAYER_REGEN_ENABLED",  onCombat)
    mod:RegisterEvent("PLAYER_TARGET_CHANGED", refreshSoon)
    mod:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", onEquipChanged)
    mod:RegisterEvent("ACTIONBAR_SLOT_CHANGED", onBindingsChanged)
    mod:RegisterEvent("UPDATE_BINDINGS",        onBindingsChanged)
end

function mod:OnDisable()
    if driver then ns:CancelTicker(driver); driver = nil end
    for _, b in ipairs(allBars) do
        if b.mover then b.mover:Hide() end
        b:Hide()
    end
end

local addInput = ""

local function rebuildPage()
    -- Guarded on the current module: the rename/delete dialogs outlive page
    -- navigation, and an unguarded rebuild from their OnAccept would replace
    -- whatever page the user has switched to with this one. The active tab
    -- rides along, else every rebuild would snap back to the first tab.
    if ns.UI and ns.UI.BuildOptionsPage and ns.UI.currentModule == "cooldownmanager" then
        ns.UI:BuildOptionsPage("cooldownmanager", ns.UI.currentTab)
    end
end
-- for callers above this definition in file order (the slash handler)
mod.RebuildPage = rebuildPage

-- ---------------------------------------------------------------------------
-- Live preview region: bar picker on top (centred), under it the entries of
-- the selected bar as they will look.
--
-- This IS the preview, the topmost region of the page, full content width. It
-- never borrows the real bar (an aura bar is legitimately empty out of combat,
-- which made a borrowed preview show nothing) -- it is a second set of frames
-- that always shows every entry, drawn with the bar's own size, shape, zoom
-- and spacing, with the real cooldown swipe on top where there is one. Drag to
-- reorder, right-click to remove.

local STRIP_PAD  = 10
local STRIP_DD_W = 360     -- the centred picker inside the region
local STRIP_DD_H = 26
local STRIP_FOOT = 34      -- room for up to two hint lines under the slots

-- Assigned in the bar-picker section further down; the region only calls them.
local buildPickerValues, reorderGroups

-- The real content width, readable because BuildOptionsPage sizes the scroll
-- child before it asks the module for its items. Fallback for safety only.
local function stripWidth()
    local f = ns.UI and ns.UI.mainFrame
    local w = f and f.scrollChild and f.scrollChild:GetWidth()
    return math.max(300, (w and w > 0 and w or 740) - 28)
end

local function stripLayout(group)
    local size = (group and group.iconSize) or 40
    local gap  = math.max((group and group.spacing) or 4, 2)
    local per  = math.max(1, math.floor((stripWidth() - 2 * STRIP_PAD + gap) / (size + gap)))
    return size, gap, per
end

-- The entry indices this character gets to see, in bar order. Everything the
-- strip draws, measures or drops onto works on this list; the real indices
-- into group.entries ride along so foreign-class entries keep their places.
local function stripVisibleEntries(group)
    local vis = {}
    if group then
        for i, e in ipairs(group.entries) do
            if entryVisibleHere(e) then vis[#vis + 1] = i end
        end
    end
    return vis
end

local function stripHeight(group)
    local n = #stripVisibleEntries(group)
    local size, gap, per = stripLayout(group)
    local rows = math.max(1, math.ceil(math.max(n, 1) / per))
    return STRIP_PAD + STRIP_DD_H + 10 + rows * (size + gap) - gap + STRIP_FOOT
end

local stripFrame

-- Where a drop right now would insert, plus the geometry for the marker line.
-- Mirrors the populate layout instead of hit-testing the slots: an insertion
-- point lives BETWEEN icons, and a strict hit test made a drop into the gap --
-- the natural place to aim at -- do nothing.
-- Returns ins in VISIBLE positions (1..n+1, "insert before visible entry
-- ins"), lineX, lineY (TOPLEFT offsets into the strip), and the icon size for
-- the line's height.
local function stripInsertPoint(f)
    local group = curGroup()
    local n = f._vis and #f._vis or 0
    if n == 0 then return nil end
    local scale = f:GetEffectiveScale()
    local fLeft, fTop = f:GetLeft(), f:GetTop()
    if not (scale and scale > 0 and fLeft and fTop) then return nil end
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale

    local size, gap, per = stripLayout(group)
    local W       = f:GetWidth() or stripWidth()
    local iconTop = STRIP_PAD + STRIP_DD_H + 10
    local rows    = math.ceil(n / per)

    local row = math.floor((fTop - cy - iconTop) / (size + gap))
    if row < 0 then row = 0 elseif row > rows - 1 then row = rows - 1 end

    local rowFirst = row * per + 1
    local inRow    = math.min(n - row * per, per)
    local rowW     = inRow * (size + gap) - gap
    local rowX     = (W - rowW) / 2

    -- nearest boundary between icons, clamped to the row's ends
    local pos = math.floor((cx - fLeft - rowX) / (size + gap) + 0.5)
    if pos < 0 then pos = 0 elseif pos > inRow then pos = inRow end

    local ins   = math.min(rowFirst + pos, n + 1)
    local lineX = rowX + pos * (size + gap) - gap / 2 - 1
    local lineY = iconTop + row * (size + gap)
    return ins, lineX, lineY, size
end

-- Live feedback while a slot is dragged: a ghost of the icon follows the
-- cursor and the marker line stands in the gap the drop would use.
local function stripDragTick(f)
    local ghost = f._ghost
    if ghost then
        local us = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / us, cy / us)
    end
    local ins, lineX, lineY, size = stripInsertPoint(f)
    if ins then
        f._dragLine:ClearAllPoints()
        f._dragLine:SetPoint("TOPLEFT", f, "TOPLEFT", lineX, -lineY)
        f._dragLine:SetSize(2, size)
        f._dragLine:Show()
    else
        f._dragLine:Hide()
    end
end

local function cancelStripDrag(f)
    f:SetScript("OnUpdate", nil)
    f._dragFrom = nil
    if f._dragSlot then f._dragSlot:SetAlpha(1); f._dragSlot = nil end
    if f._ghost then f._ghost:Hide() end
    if f._dragLine then f._dragLine:Hide() end
end

local function ensureStripSlot(f, i)
    local slot = f._slots[i]
    if slot then return slot end
    slot = CreateFrame("Button", nil, f)
    slot:SetSize(40, 40)

    slot._bg = slot:CreateTexture(nil, "BACKGROUND")
    slot._bg:SetAllPoints(slot)
    slot._bg:SetColorTexture(0, 0, 0, 1)

    slot._icon = slot:CreateTexture(nil, "ARTWORK")
    slot._icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
    slot._icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
    slot._icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- same mask mechanism the real icons use, so "Icon shape" previews truthfully
    if slot.CreateMaskTexture and slot._icon.AddMaskTexture then
        slot._mask = slot:CreateMaskTexture()
        slot._mask:SetAllPoints(slot._icon)
        slot._icon:AddMaskTexture(slot._mask)
    end

    -- the real cooldown swipe; populated from the same source as the bar
    slot._cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    slot._cd:SetAllPoints(slot._icon)
    slot._cd:SetDrawEdge(true)
    if slot._cd.SetHideCountdownNumbers then slot._cd:SetHideCountdownNumbers(true) end
    slot._cd.noCooldownCount = true

    -- own frame above the icon, so the hover ring never recolours the resting border
    slot._ring = CreateFrame("Frame", nil, slot)
    slot._ring:SetAllPoints(slot)
    slot._ring:SetFrameLevel(slot._cd:GetFrameLevel() + 2)
    slot._ring._edges = ns.MakeEdges(slot._ring, "OVERLAY")
    slot._ring:Hide()

    slot._count = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.UI.Font(slot._count, 11)
    slot._count:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
    slot._count:SetTextColor(1, 0.95, 0.6)

    slot:SetScript("OnEnter", function(self)
        -- accent read at paint time, never baked: the theme colour is live-mutated
        local a = ns.COLORS.accent
        ns.LayoutEdges(self._ring._edges, self._ring, 2, a.r, a.g, a.b, 1, 0)
        self._ring:Show()
        if self._tip and ns.UI:OpenTooltip(self, "ANCHOR_RIGHT") then
            GameTooltip:SetText(self._tip)
            GameTooltip:AddLine(
                (ns.UI and ns.UI.currentTab == "glows")
                    and L["Click to edit this icon's glow."]
                    or  L["Drag to reorder. Right-click removes it."],
                0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end
    end)
    slot:SetScript("OnLeave", function(self)
        -- the ring doubles as the selection marker on the glows tab
        if not self._selected then self._ring:Hide() end
        ns.UI:HideTooltip()
    end)

    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:SetScript("OnClick", function(self, button)
        local group = curGroup()
        if not (group and self._entryIndex) then return end
        -- On the glows tab any click PICKS the icon whose glow the page edits;
        -- removing stays a tracked-tab action, so a mis-click here cannot
        -- silently shorten the bar. The ENTRY TABLE is stored, not the index:
        -- removals, reorders and the trinket auto-sync shift indices under an
        -- open editor, and an index would silently retarget a different icon
        -- (the same rule the rename/delete dialogs follow).
        if ns.UI and ns.UI.currentTab == "glows" then
            mod._glowSel = group.entries[self._entryIndex]
            rebuildPage()
            return
        end
        if button == "RightButton" then
            local e = group.entries[self._entryIndex]
            -- auto trinkets are re-added by the equipment sync, so removing one
            -- by hand would look like the click did nothing
            if e and e.auto then
                ns:Print(L["That icon is added automatically — switch off auto-tracking to remove it."])
                return
            end
            table.remove(group.entries, self._entryIndex)
            relayoutGroup(group)
            rebuildPage()
        end
    end)

    slot:RegisterForDrag("LeftButton")
    slot:SetScript("OnDragStart", function(self)
        local host = self:GetParent()
        if not self._entryIndex then return end
        host._dragFrom = self._entryIndex
        host._dragSlot = self
        self:SetAlpha(0.35)

        -- ghost of the icon under the cursor, like the reference
        local g = host._ghost
        g:SetSize(self:GetWidth() * 0.8, self:GetHeight() * 0.8)
        g._icon:SetTexture(self._icon:GetTexture())
        g._icon:SetTexCoord(self._icon:GetTexCoord())
        g:Show()

        local a = ns.COLORS.accent
        host._dragLine:SetColorTexture(a.r, a.g, a.b, 0.9)
        host:SetScript("OnUpdate", function(h) stripDragTick(h) end)
    end)
    slot:SetScript("OnDragStop", function(self)
        local host = self:GetParent()
        local from = host._dragFrom
        local ins  = stripInsertPoint(host)
        cancelStripDrag(host)
        local group = curGroup()
        if not (from and ins and group and host._vis) then return end

        -- ins is a VISIBLE position; the move happens on the real entry list,
        -- so foreign-class entries in between keep their places
        local realIns = host._vis[ins] or ((host._vis[#host._vis] or 0) + 1)
        local to = realIns
        if to > from then to = to - 1 end
        if to < 1 then to = 1 end
        if to > #group.entries then to = #group.entries end
        if to == from then return end

        local e = table.remove(group.entries, from)
        table.insert(group.entries, to, e)
        relayoutGroup(group)
        rebuildPage()
    end)

    f._slots[i] = slot
    return slot
end

local function ensureStripFrame(parent)
    if not stripFrame then
        stripFrame = CreateFrame("Frame", nil, parent)
        stripFrame:SetSize(stripWidth(), stripHeight(nil))
        stripFrame._slots = {}

        ns.UI:StyleBackdrop(stripFrame, { bg = { r = 0.05, g = 0.05, b = 0.07, a = 1 } })

        -- drop marker between two icons; coloured at drag start
        stripFrame._dragLine = stripFrame:CreateTexture(nil, "OVERLAY")
        stripFrame._dragLine:Hide()

        -- the dragged icon's stand-in under the cursor; parented to UIParent so
        -- it can leave the region without being clipped
        stripFrame._ghost = CreateFrame("Frame", nil, UIParent)
        stripFrame._ghost:SetFrameStrata("FULLSCREEN_DIALOG")
        stripFrame._ghost:SetFrameLevel(300)
        stripFrame._ghost._icon = stripFrame._ghost:CreateTexture(nil, "ARTWORK")
        stripFrame._ghost._icon:SetAllPoints(stripFrame._ghost)
        stripFrame._ghost:Hide()

        -- page switch or window close mid-drag: OnDragStop never fires then
        stripFrame:SetScript("OnHide", function(self) cancelStripDrag(self) end)

        -- The bar picker, centred at the top of the region. Module-owned, not
        -- pooled: reconfigured per build through its own _vcSetup, exactly what
        -- the options builder would do with it.
        stripFrame._picker = ns.UI:CreateDropdown(stripFrame, {
            width = STRIP_DD_W,
            values = {},
            get = function() return db().selected end,
            set = function(_, v) db().selected = v; mod.RebuildPage() end,
        })

        stripFrame._hint = stripFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        ns.UI.Font(stripFrame._hint, 11)
        stripFrame._hint:SetTextColor(0.62, 0.62, 0.62)
        stripFrame._hint:SetJustifyH("CENTER")
        stripFrame._hint:SetWordWrap(true)
    end
    stripFrame:SetParent(parent)
    stripFrame:Show()
    return stripFrame
end

-- Real cooldown state onto the preview slots, from the same source the bar
-- reads. Called on populate and from refreshAll's ticker while the page shows,
-- so a swipe that starts while the window is open appears without a rebuild.
function mod.UpdateStripCooldowns()
    local f = stripFrame
    if not (f and f:IsVisible()) then return end
    local group = curGroup()
    if not group then return end
    local minDur = group.minDuration or 1.5
    for _, slot in ipairs(f._slots) do
        local idx = slot._entryIndex
        local e = idx and group.entries[idx]
        if e and slot:IsShown() then
            local start, dur = 0, 0
            if group.mode == "cooldown" then
                start, dur = entryCooldown(e)
            end
            -- mirror the bar's GCD filter, or every keypress flashes the strip
            if not (start and dur and dur > minDur and start > 0) then start, dur = 0, 0 end
            if slot._cdStart ~= start or slot._cdDur ~= dur then
                slot._cdStart, slot._cdDur = start, dur
                if dur > 0 then slot._cd:SetCooldown(start, dur) else slot._cd:Clear() end
            end
        end
    end
end

local function buildIconStrip(parent)
    local f = ensureStripFrame(parent)
    cancelStripDrag(f)
    local group = curGroup()
    local vis = stripVisibleEntries(group)
    local size, gap, per = stripLayout(group)
    local zoom = (group and group.iconZoom) or 0.08
    local mask = group and shapeMask(group.iconShape)
    local W = stripWidth()
    f._vis = vis

    -- picker on top, centred; fresh values every build, the list is live data
    local picker = f._picker
    picker._vcSetup(picker, {
        width   = STRIP_DD_W,
        values  = (buildPickerValues and buildPickerValues()) or {},
        reorder = reorderGroups,
        get     = function() return db().selected end,
        set     = function(_, v)
            db().selected = v
            -- an entry index into the OLD bar must not survive the switch
            mod._glowSel = nil
            mod.RebuildPage()
        end,
    })
    picker:ClearAllPoints()
    picker:SetPoint("TOP", f, "TOP", 0, -STRIP_PAD)

    for _, slot in ipairs(f._slots) do
        slot:Hide()
        slot._entryIndex = nil
        -- forget the cooldown memory: the same slot may show a different entry
        -- after a reorder, and a stale pair would suppress the fresh swipe
        slot._cdStart, slot._cdDur = nil, nil
    end

    local n = #vis
    local onGlows = ns.UI and ns.UI.currentTab == "glows"
    local iconTop = STRIP_PAD + STRIP_DD_H + 10
    for k, entryIndex in ipairs(vis) do
        local e = group.entries[entryIndex]
        local slot = ensureStripSlot(f, k)
        local nm, icon = entryInfo(e)
        slot._entryIndex = entryIndex
        slot._tip = nm or ("#" .. tostring(e.id))
        -- persistent ring on the icon whose glow the glows tab is editing;
        -- compared by entry table, which survives reorders
        slot._selected = onGlows and e == mod._glowSel or nil
        if slot._selected then
            local a = ns.COLORS.accent
            ns.LayoutEdges(slot._ring._edges, slot._ring, 2, a.r, a.g, a.b, 1, 0)
            slot._ring:Show()
        else
            slot._ring:Hide()
        end
        slot:SetSize(size, size)
        slot._icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        slot._icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        if slot._mask and mask then
            slot._mask:SetTexture(mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        -- own class but not (or no longer) in the spellbook: shown greyed.
        -- Parked entries (e.off) grey the same way, in every mode.
        slot._icon:SetDesaturated(e.off == true
                                  or (group.mode == "cooldown" and e.kind == "spell"
                                      and not entryUsable(e)) or false)
        slot._count:SetText(e.auto and L["auto"] or "")
        slot:ClearAllPoints()
        -- wraps once a row is full; each row is centred like the picker above
        local col = (k - 1) % per
        local row = math.floor((k - 1) / per)
        local inRow = math.min(n - row * per, per)
        local rowW  = inRow * (size + gap) - gap
        slot:SetPoint("TOPLEFT", f, "TOPLEFT",
            (W - rowW) / 2 + col * (size + gap), -(iconTop + row * (size + gap)))
        slot:Show()
    end

    local rows = math.max(1, math.ceil(math.max(n, 1) / per))
    f._hint:ClearAllPoints()
    f._hint:SetPoint("TOP", f, "TOP", 0, -(iconTop + rows * (size + gap) - gap + 8))
    f._hint:SetWidth(W - 2 * STRIP_PAD)
    if onGlows then
        f._hint:SetText(n > 0
            and L["Click an icon to edit its glow."]
            or  L["Nothing in this bar yet. Add a spell or trinket on the CDM Bars tab first."])
    else
        f._hint:SetText(n > 0
            and L["Drag to reorder. Right-click an icon to remove it."]
            or  L["Nothing in this bar yet. Add a spell or trinket below, or drag one onto the bar."])
    end
    f:SetSize(W, stripHeight(group))
    mod.UpdateStripCooldowns()
    return f
end

-- Sliders that reshape the bar redraw the preview through this; guarded on the
-- page actually showing so a combat-log refresh never rebuilds UI. When the
-- region's height changes (bigger icons, extra row), only a full page rebuild
-- can move the scroll area under it -- the header is sized once per build.
function mod.RefreshStrip(group)
    if not (stripFrame and stripFrame:IsVisible() and group == curGroup()) then return end
    if math.abs(stripHeight(group) - (stripFrame:GetHeight() or 0)) > 0.5 then
        rebuildPage()
    else
        buildIconStrip(stripFrame:GetParent())
    end
end

-- The pinned header above the scroll area (see BuildOptionsPage): the preview
-- region stays in sight at every scroll position. Only on the tabs whose
-- subject the strip actually is; a returned 0 hides the header everywhere else.
--
-- Started as the bar itself plus the glows (30.07.2026, user request), and the
-- layout tab joined them on 01.08.2026 -- icon size, spacing, shape and zoom
-- all read back off the strip while the slider moves, because relayoutGroup
-- ends in RefreshStrip. Growth direction, rows and the bar's scale, opacity
-- and background do NOT show there: the strip is a fixed-width management row
-- for reordering and removing, not a scale model of the bar.
local STRIP_TABS = { tracked = true, glows = true, layout = true, ["default"] = true }
function mod.BuildPageHeader(host, tabId)
    -- The power-bar tab pins its own preview instead of the icon strip; the
    -- capsule below owns the widget, this is just the hand-over.
    if tabId == "powerbar" then
        local pb = ns.modules and ns.modules.powerbar
        if pb and pb.BuildPreview then return pb.BuildPreview(host) end
        return 0
    end
    if tabId ~= nil and not STRIP_TABS[tabId] then return 0 end
    ensureGroups()
    local f = buildIconStrip(host)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 14, 0)
    return stripHeight(curGroup())
end

-- ---------------------------------------------------------------------------
-- Bar picker helpers: rename, delete, add-of-mode, reorder.

local PENCIL_ICON = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\pencil.tga"

local MODE_ORDER = { "cooldown", "aura", "targetdebuff", "missing" }
local MODE_ADD_LABEL, MODE_NEW_NAME
ns.OnLocaleReady(function()
    MODE_ADD_LABEL = {
        cooldown     = L["+  New cooldown bar"],
        aura         = L["+  New buff / proc bar"],
        targetdebuff = L["+  New target debuff bar"],
        missing      = L["+  New missing-buff reminder"],
    }
    MODE_NEW_NAME = {
        cooldown     = L["Cooldowns"],
        aura         = L["Buffs & Procs"],
        targetdebuff = L["Target debuffs"],
        missing      = L["Missing buffs"],
    }
end)

-- The GROUP each popup acts on -- the table, not its index. StaticPopup carries
-- no payload of its own on this client, the dialog outlives the click that
-- opened it, and an index can be reordered out from under an open dialog while
-- the table identity cannot. TWO variables, not one: rename and delete are
-- different popup types, so both dialogs can be open at once, and a shared slot
-- would let the rename opened second retarget the delete opened first.
local pendingRenameGroup, pendingDeleteGroup

local function addGroupOfMode(mode)
    local d = db()
    local g = defaultGroup((MODE_NEW_NAME and MODE_NEW_NAME[mode]) or L["Cooldowns"])
    g.mode = mode
    g.id   = newGroupID()
    d.groups[#d.groups + 1] = g
    d.selected = #d.groups
    rebuildBars(); rebuildPage()
end

-- By table, not index: the caller may hold a group across a reorder or another
-- delete (an open StaticPopup does exactly that).
local function deleteGroup(group)
    local d = db()
    local index
    for i, g in ipairs(d.groups) do
        if g == group then index = i; break end
    end
    if not index then return end
    local bar = barOf[group]
    if bar then bar:Hide(); if bar.mover then bar.mover:Hide() end end
    for _, g in ipairs(d.groups) do
        if g.anchorTo == group.id then g.anchorTo = nil end
    end
    table.remove(d.groups, index)
    if d.selected > #d.groups then d.selected = #d.groups end
    if d.selected < 1 then d.selected = 1 end
    rebuildBars(); rebuildPage()
end

-- Selection is an index into d.groups, so the moved bar has to be followed or
-- the page would silently start editing whichever bar slid into its place.
-- Assignment, not declaration: forward-declared next to the strip, which hands
-- it to the picker.
reorderGroups = function(fromRow, toRow)
    local d = db()
    -- rows are offset by the caption when there is one
    local offset = (#d.groups > 1) and 1 or 0
    local from, to = fromRow - offset, toRow - offset
    if from < 1 or to < 1 or from > #d.groups or to > #d.groups or from == to then return end
    local moved = d.groups[d.selected]
    local g = table.remove(d.groups, from)
    table.insert(d.groups, to, g)
    for i, cand in ipairs(d.groups) do
        if cand == moved then d.selected = i; break end
    end
    rebuildBars(); rebuildPage()
end

-- Does the actual rename; shared by the OK button and the Enter key. The Enter
-- handler must not go through `parent.OnAccept` -- the client keeps OnAccept on
-- the dialog INFO table, never on the frame, so that call is silently nil and
-- the name typed would be thrown away.
local function applyRename(dialog)
    local box  = ns.PopupEditBox(dialog)
    local name = box and box:GetText()
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local group = pendingRenameGroup
    if not group or name == "" then return end
    group.name = name
    rebuildBars(); rebuildPage()
end

ns.OnLocaleReady(function()
    StaticPopupDialogs["VCUI_CDM_BAR_RENAME"] = {
        text         = L["New name for this bar"],
        button1      = ACCEPT or "OK",
        button2      = CANCEL or "Cancel",
        hasEditBox   = true,
        maxLetters   = 32,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(self) applyRename(self) end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            applyRename(parent)
            parent:Hide()
        end,
    }
    StaticPopupDialogs["VCUI_CDM_BAR_DELETE"] = {
        text         = L["Delete this bar and everything on it?"],
        button1      = DELETE or "Delete",
        button2      = CANCEL or "Cancel",
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function() if pendingDeleteGroup then deleteGroup(pendingDeleteGroup) end end,
    }
end)

-- Glow watcher input, same file-level pattern as the add row below. A watcher
-- accepts a spell id (name resolved for the label) or a raw aura name -- on
-- this client UnitAura matches by name, so an unresolvable name still works.
local glowAddInput = ""

-- _glowSel holds the entry TABLE; this resolves it against the current bar and
-- returns nil when the entry has been removed or the bar switched.
local function glowSelectedEntry()
    local group = curGroup()
    if not (group and mod._glowSel) then return nil end
    for _, cand in ipairs(group.entries) do
        if cand == mod._glowSel then return cand end
    end
    return nil
end
mod.GlowSelectedEntry = glowSelectedEntry

local function addGlowWatcher()
    local e = glowSelectedEntry()
    local txt = tostring(glowAddInput or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not e or txt == "" then return end
    local id = tonumber(txt)
    local name
    if id then
        name = GetSpellInfo and GetSpellInfo(id) or nil
        -- an ID this client cannot resolve would make a watcher that never
        -- fires on "active" and always on "missing" -- refuse it out loud
        -- instead of storing a dud
        if not name then
            ns:Print(L["Cooldown Manager: '%s' is not a known spell or item."], txt)
            return
        end
    else
        name = txt
    end
    e.glows = e.glows or {}
    e.glows[#e.glows + 1] = { name = name, id = id, mode = "ACTIVE", style = "pixel" }
    glowAddInput = ""
    refreshAll()
    rebuildPage()
end

-- Lives here rather than inside GetOptions: the strip's add row is built before
-- the per-bar section that used to own it, and a closure rebuilt per page would
-- capture a stale group after every reorder.
local function doAddEntry()
    local group = curGroup()
    local txt = tostring(addInput or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if group and txt ~= "" and addEntry(group, txt) then
        addInput = ""
        rebuildPage()
    end
end

local function promptRename(index)
    local group = db().groups[index]
    if not group then return end
    pendingRenameGroup = group
    local dialog = StaticPopup_Show("VCUI_CDM_BAR_RENAME")
    local box = ns.PopupEditBox(dialog)
    if box then box:SetText(group.name or ""); box:HighlightText() end
end

local function promptDelete(index)
    local d = db()
    local group = d.groups[index]
    if not group then return end
    -- the last bar is the module: deleting it would leave a page with nothing
    -- to edit and ensureGroups would silently make a fresh one anyway
    if #d.groups <= 1 then
        ns:Print(L["That is the last bar — there has to be one."])
        return
    end
    pendingDeleteGroup = group
    StaticPopup_Show("VCUI_CDM_BAR_DELETE")
end

-- The picker's row list. Selection is by ARRAY INDEX, so a reorder has to
-- carry d.selected with it or the page would suddenly be editing a different
-- bar. Assignment: forward-declared next to the strip, which consumes it.
buildPickerValues = function()
    local d = db()
    local groupValues = {}
    if #d.groups > 1 then
        groupValues[#groupValues + 1] = { text = L["Drag to reorder bars"], separator = true }
    end
    for i, g in ipairs(d.groups) do
        groupValues[#groupValues + 1] = {
            value = i, text = g.name,
            draggable = #d.groups > 1,
            buttons = {
                { icon = PENCIL_ICON, tooltip = L["Rename this bar"],
                  onClick = function(idx) promptRename(idx) end },
                { glyph = "\195\151", tooltip = L["Delete this bar"],
                  onClick = function(idx) promptDelete(idx) end },
            },
        }
    end
    for _, m in ipairs(MODE_ORDER) do
        groupValues[#groupValues + 1] = {
            -- same guard addGroupOfMode uses: GetOptions cannot run before
            -- OnLocaleReady in practice, but an error page is a bad way to prove it
            text = (MODE_ADD_LABEL and MODE_ADD_LABEL[m]) or m, action = true,
            onClick = function() addGroupOfMode(m) end,
        }
    end
    return groupValues
end

local function openColorPicker(getCurrent, setNew)
    local c = getCurrent() or { r = 1, g = 1, b = 1 }
    ns:ShowColorPicker({
        r = c.r or 1, g = c.g or 1, b = c.b or 1,
        onChange = function(r, g, b) setNew({ r = r, g = g, b = b }) end,
    })
end

-- Tabs, like the rest of the suite: the pinned preview region stays above all
-- of them; each tab carries one subject. Labels are raw English keys -- the
-- tab renderer translates them.
mod.tabs = {
    { id = "tracked",    label = "CDM Bars" },
    { id = "glows",      label = "Bar Glows" },
    { id = "layout",     label = "Layout" },
    { id = "display",    label = "Icon display" },
    { id = "visibility", label = "Visibility" },
}

function mod:GetOptions(tabId)
    ensureGroups()
    local d = mod.db
    local group = curGroup()
    if tabId == nil or tabId == "default" then tabId = "tracked" end

    -- The power bar tab fronts a real module of its own (merged below in this
    -- file); delegate the way the group containers do -- its enable switch
    -- first, then its page.
    if tabId == "powerbar" then
        local sub = ns.modules and ns.modules.powerbar
        if not sub then return {} end
        local items = {
            { type = "toggle", label = L["Module enabled"],
              get = function() return ns:IsModuleEnabled("powerbar") end,
              set = function(_, v)
                  ns:ToggleModule("powerbar", v)
                  if ns.UI and ns.UI.RefreshSidebarStates then ns.UI:RefreshSidebarStates() end
                  rebuildPage()
              end },
            { type = "spacer", height = 8 },
        }
        if sub.description and sub.description ~= "" then
            items[#items + 1] = { type = "desc", text = L[sub.description] }
            items[#items + 1] = { type = "spacer", height = 6 }
        end
        if sub.GetOptions then
            local ok, subItems = pcall(function() return sub:GetOptions() end)
            if ok and type(subItems) == "table" then
                for _, it in ipairs(subItems) do items[#items + 1] = it end
            else
                items[#items + 1] = { type = "desc", text = L["|cffff5555This tab failed to load.|r"] }
            end
        end
        return items
    end

    -- ------------------------------------------------------------------ glows
    -- The strip above is the interaction surface: a click there stores the
    -- entry index in mod._glowSel and rebuilds this page.
    if tabId == "glows" then
        local items = {
            { type = "desc", text = L["|cffaaaaaaEach icon can glow while a buff of yours is active — or missing. Click an icon in the preview above, then add one or more watchers; the first whose condition holds paints the icon.|r"] },
            { type = "spacer", height = 4 },
        }
        if not group then return items end
        local e = glowSelectedEntry()
        if not (e and entryVisibleHere(e)) then
            mod._glowSel = nil
            items[#items + 1] = { type = "desc", text = L["|cff888888No icon picked yet.|r"] }
            return items
        end

        local ename = entryInfo(e) or ("#" .. tostring(e.id))
        items[#items + 1] = { type = "header", text = string.format(L["Glows: %s"], ename) }

        -- The empty state is where everyone starts; it has to teach. And the
        -- overwhelmingly common watcher is the entry's OWN buff, so that case
        -- is one button instead of a spelling exercise.
        if not (e.glows and e.glows[1]) then
            items[#items + 1] = { type = "desc",
                text = L["|cffaaaaaaNo watcher yet. Most spells put a buff of the same name on you when used — one click below makes this icon glow while that buff is on you. Or type any other buff into the field.|r"] }
            if e.kind == "spell" then
                items[#items + 1] = { type = "button", width = 320, primary = true,
                    label = string.format(L["Glow while '%s' is on me"], ename),
                    onClick = function()
                        e.glows = e.glows or {}
                        e.glows[#e.glows + 1] = { name = ename, id = e.id, mode = "ACTIVE", style = "pixel" }
                        refreshAll(); rebuildPage()
                    end }
                items[#items + 1] = { type = "spacer", height = 4 }
            end
        end

        for gi, g in ipairs(e.glows or {}) do
            local watcher = g.name or (g.id and ("#" .. g.id)) or "?"
            -- noOverride on every value row: the label repeats once per watcher,
            -- and the talent-override capture keys rows by label -- recording
            -- one "Glow style" would replay onto every watcher of the entry
            local glowItems = {
                { type = "dropdown", label = L["Glow when"], width = 260, noOverride = true,
                  values = {
                      { value = "ACTIVE",  text = L["Buff is active"] },
                      { value = "MISSING", text = L["Buff is missing"] },
                  },
                  get = function() return g.mode or "ACTIVE" end,
                  set = function(_, v) g.mode = v; refreshAll() end },
                { type = "toggle", label = L["Only in combat"], noOverride = true,
                  get = function() return g.combat == true end,
                  set = function(_, v) g.combat = v and true or nil; refreshAll() end },
                { type = "dropdown", label = L["Glow style"], width = 260, noOverride = true,
                  values = {
                      { value = "pixel",  text = L["Pixel border"] },
                      { value = "button", text = L["Action button glow"] },
                      { value = "fill",   text = L["Pulsing fill"] },
                  },
                  get = function() return g.style or "pixel" end,
                  set = function(_, v) g.style = v; refreshAll() end },
                { type = "dropdown", label = L["Glow color"], width = 260, noOverride = true,
                  values = {
                      { value = "default", text = L["Gold (default)"] },
                      { value = "class",   text = L["Class color"] },
                      { value = "custom",  text = L["Custom color"] },
                  },
                  get = function() return g.colorMode or "default" end,
                  set = function(_, v) g.colorMode = v; refreshAll(); rebuildPage() end },
            }
            if g.colorMode == "custom" then
                glowItems[#glowItems + 1] = { type = "button", label = L["Pick color..."], width = 160,
                    onClick = function()
                        openColorPicker(function() return g.color end,
                            function(c) g.color = c; refreshAll() end)
                    end }
            end
            glowItems[#glowItems + 1] = { type = "button", label = L["Remove this glow"], width = 180,
                onClick = function()
                    table.remove(e.glows, gi)
                    if #e.glows == 0 then e.glows = nil end
                    refreshAll(); rebuildPage()
                end }
            items[#items + 1] = { type = "section",
                title = string.format(L["Watches: %s"], watcher), items = glowItems }
        end

        items[#items + 1] = { type = "spacer", height = 6 }
        items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
            { type = "editbox", label = L["Add watcher (buff name / ID)"], width = 320, editWidth = 180,
              commitOnFocusLost = true,
              get = function() return glowAddInput end,
              set = function(_, v) glowAddInput = tostring(v or "") end,
              onEnter = function() addGlowWatcher() end },
            { type = "button", label = L["Add"], width = 80, primary = true,
              onClick = function() addGlowWatcher() end },
        } }
        return items
    end

    local items = {}

    if not group then return items end

    -- ---------------------------------------------------------------- tracked
    if tabId == "tracked" then

    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "editbox", label = L["Add (name / ID)"], width = 300, editWidth = 190,
          commitOnFocusLost = true,
          get = function() return addInput end,
          set = function(_, v) addInput = tostring(v or "") end,
          onEnter = function() doAddEntry() end },
        { type = "button", label = L["Add"], width = 80, primary = true,
          onClick = function() doAddEntry() end },
        { type = "button", label = L["Duplicate bar"], width = 130,
          tooltip = L["Copies the selected bar with all entries and layout settings."],
          onClick = function()
              local src = curGroup()
              if not src then return end
              local copy = ns:DeepCopy(src)
              copy.id = newGroupID()
              copy.name = src.name .. " " .. L["(copy)"]
              copy.unlocked = false
              copy.freeMove = nil
              copy.anchorEnabled = nil
              d.groups[#d.groups + 1] = copy
              d.selected = #d.groups
              rebuildBars(); rebuildPage()
          end },
    } }
    items[#items + 1] = { type = "spacer", height = 6 }

    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "editbox", label = L["Name"], width = 260, editWidth = 170,
          get = function() return group.name end,
          set = function(_, v)
              group.name = (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
              if group.name == "" then group.name = L["Cooldowns"] end
              rebuildBars(); rebuildPage()
          end },
        -- Same path as the × in the bar picker: confirm dialog, last-bar guard,
        -- preview release. Two delete paths with different rules is how the
        -- guarded one becomes decorative.
        { type = "button", label = L["Delete group"], width = 130,
          onClick = function() promptDelete(d.selected) end },
    } }
    items[#items + 1] = { type = "dropdown", label = L["Group type"], width = 280,
        values = {
            { value = "cooldown",     text = L["Cooldowns"] },
            { value = "aura",         text = L["Buffs & Procs (only show while active)"] },
            { value = "targetdebuff", text = L["Debuffs on target (yours only)"] },
            { value = "missing",      text = L["Missing buffs (reminder)"] },
        },
        get = function() return group.mode end,
        set = function(_, v) group.mode = v; rebuildBars(); rebuildPage() end }
    local modeDesc
    if group.mode == "aura" then
        modeDesc = L["|cffaaaaaaIcons appear only while their buff/proc is on you; the bar is empty otherwise. Add the BUFF (e.g. Clearcasting) by name or ID.|r"]
    elseif group.mode == "targetdebuff" then
        modeDesc = L["|cffaaaaaaIcons appear while YOUR debuff/DoT is on the target, with its remaining time. Add the debuff by name or ID.|r"]
    elseif group.mode == "missing" then
        modeDesc = L["|cffaaaaaaIcons appear while the buff is MISSING on you - a reminder for weapon oils, blessings, food buffs. Add the buff by name or ID.|r"]
    else
        modeDesc = L["|cffaaaaaaIcons show the cooldown of each spell/trinket.|r"]
    end
    items[#items + 1] = { type = "desc", text = modeDesc }
    items[#items + 1] = { type = "dropdown", label = L["Order"], width = 280,
        tooltip = L["Fixed keeps the order you added them in. The other two reorder live by what is left."],
        values = {
            { value = "fixed",    text = L["As added"] },
            { value = "shortest", text = L["Least time left first"] },
            { value = "longest",  text = L["Most time left first"] },
        },
        get = function() return group.sortBy or "fixed" end,
        set = function(_, v) group.sortBy = (v ~= "fixed") and v or nil; rebuildBars() end }
    if group.mode ~= "cooldown" then
        -- Focus and pet exist on this client; arena and boss units do not, and
        -- a choice that can never resolve is worse than no choice.
        items[#items + 1] = { type = "dropdown", label = L["Watch this unit"], width = 280,
            tooltip = L["Whose auras this group reads. The default is what the group type has always used."],
            values = {
                { value = "player", text = L["You"] },
                { value = "target", text = L["Target"] },
                { value = "focus",  text = L["Focus"] },
                { value = "pet",    text = L["Pet"] },
            },
            get = function()
                local u = groupSource(group)
                return u
            end,
            set = function(_, v) group.auraUnit = v; rebuildBars(); rebuildPage() end }
        items[#items + 1] = { type = "checkbox", label = L["Only what I cast myself"],
            tooltip = L["Off counts the aura no matter who put it there - for a raid debuff that anyone may apply."],
            get = function() return groupOwnOnly(group) end,
            set = function(_, v) group.auraOwnOnly = v and true or false; rebuildBars(); rebuildPage() end }
    end
    items[#items + 1] = { type = "spacer", height = 6 }

    -- Same visibility rule as the preview strip: entries another class created
    -- do not exist here. They stay in the stored list untouched -- their class
    -- sees and manages them.
    local visibleTracked = stripVisibleEntries(group)
    local trackedItems = {}
    if #visibleTracked == 0 then
        trackedItems[1] = { type = "desc", text = L["|cff888888Nothing in this group yet.|r"] }
    else
        -- One PAIRABLE gear row per entry (user request from the Titan report:
        -- two entries per line instead of one). The toggle parks an entry
        -- without deleting it; everything an entry owns -- moving, removing,
        -- conditions, the per-entry own-only override -- lives behind its
        -- gear, so two rows fit where one desc+buttons strip used to sit.
        for pos, i in ipairs(visibleTracked) do
            local e = group.entries[i]
            local entry = e
            local nm, icon = entryInfo(e)
            local label = (icon and ("|T" .. icon .. ":18:18:0:0:64:64:5:59:5:59|t  ") or "")
                .. (nm or ("#" .. tostring(e.id)))
            if e.kind == "item" then label = label .. L["  |cff888888(item)|r"] end
            if e.auto then label = label .. " |cff888888(auto)|r" end
            if group.mode == "cooldown" and e.kind == "spell" and not e.off and not entryUsable(e) then
                label = label .. L["  |cffaa5555(other class)|r"]
            end

            local subs = {}
            if group.mode ~= "cooldown" then
                -- reuses the group switch's label on purpose: same words, same
                -- meaning, one level deeper
                -- noOverride on every per-entry sub-row: they share their
                -- labels with the group-level rows, and the talent-override
                -- replay matches by LABEL -- a recorded group value would
                -- otherwise replay onto every same-named per-entry row and
                -- silently wipe the per-entry choices (review find).
                subs[#subs + 1] = { type = "dropdown", label = L["Only what I cast myself"], width = 220,
                    noOverride = true,
                    tooltip = L["Overrides the group switch for this entry alone - e.g. to track a buff someone else casts on you."],
                    values = {
                        { value = "",     text = L["Group default"] },
                        { value = "mine", text = L["Only mine"] },
                        { value = "any",  text = L["Anyone's"] },
                    },
                    get = function()
                        if entry.ownOnly == true then return "mine" end
                        if entry.ownOnly == false then return "any" end
                        return ""
                    end,
                    set = function(_, v)
                        entry.ownOnly = (v == "mine") and true or ((v == "any") and false or nil)
                        rebuildBars()
                    end }
            end
            if group.mode == "aura" or group.mode == "targetdebuff" then
                subs[#subs + 1] = { type = "toggle", label = L["Use conditions"],
                    noOverride = true,
                    tooltip = L["Narrows this icon to a number of stacks, or to the last seconds before it runs out."],
                    get = function() return entry.cond == true end,
                    set = function(_, v) entry.cond = v and true or nil end }
                subs[#subs + 1] = { type = "slider", label = L["Only from stacks"], min = 0, max = 20, step = 1,
                    noOverride = true,
                    tooltip = L["0 = any number of stacks."],
                    get = function() return entry.minStacks or 0 end,
                    set = function(_, v) entry.minStacks = (v > 0) and v or nil end }
                subs[#subs + 1] = { type = "slider", label = L["Only in the last seconds"], min = 0, max = 30, step = 1,
                    noOverride = true,
                    tooltip = L["0 = at any time. Otherwise the icon appears only this close to running out."],
                    get = function() return entry.maxRemaining or 0 end,
                    set = function(_, v) entry.maxRemaining = (v > 0) and v or nil end }
            end
            -- swap with the neighbouring VISIBLE entry: with a hidden foreign
            -- entry in between, swapping real neighbours would look like the
            -- button did nothing
            local prevIdx = visibleTracked[pos - 1]
            local nextIdx = visibleTracked[pos + 1]
            if prevIdx then
                subs[#subs + 1] = { type = "button", label = L["Move earlier"], width = 180, height = 26,
                    onClick = function()
                        group.entries[i], group.entries[prevIdx] = group.entries[prevIdx], group.entries[i]
                        relayoutGroup(group); rebuildPage()
                    end }
            end
            if nextIdx then
                subs[#subs + 1] = { type = "button", label = L["Move later"], width = 180, height = 26,
                    onClick = function()
                        group.entries[i], group.entries[nextIdx] = group.entries[nextIdx], group.entries[i]
                        relayoutGroup(group); rebuildPage()
                    end }
            end
            -- auto trinkets get no Remove: the sync would re-add them
            if not e.auto then
                subs[#subs + 1] = { type = "button", label = L["Remove"], width = 180, height = 26,
                    onClick = function()
                        table.remove(group.entries, i); relayoutGroup(group); rebuildPage()
                    end }
            end

            trackedItems[#trackedItems + 1] = {
                type = "toggle",
                label = label,
                -- entry parking is user DATA, not a talent-dependent setting;
                -- and the label (a spell name) repeats across groups
                noOverride = true,
                pairable = true,
                -- every entry shows the same controls; without subKey one gear
                -- would open all of them
                subKey = "cdent/" .. tostring(group.id) .. "/" .. i,
                tooltip = L["Unticked parks this entry: it keeps its settings but never shows. The gear holds moving, removing and per-entry settings."],
                get = function() return not entry.off end,
                set = function(_, v)
                    entry.off = (not v) and true or nil
                    rebuildBars()
                end,
                -- a lone auto entry in a cooldown group can end up with no
                -- sub-rows at all; a gear that opens nothing must not exist
                subOptions = (#subs > 0) and subs or nil,
            }
        end
    end
    trackedItems[#trackedItems + 1] = { type = "spacer", height = 4 }
    if group.mode == "cooldown" then
        trackedItems[#trackedItems + 1] = { type = "toggle", label = L["Auto-track equipped trinkets"],
            tooltip = L["Keeps both equipped trinkets in this group automatically - they follow along when you swap trinkets."],
            get = function() return group.autoTrinkets == true end,
            set = function(_, v)
                group.autoTrinkets = v
                syncAutoTrinkets(group)
                relayoutGroup(group)
                rebuildPage()
            end }
    end
    trackedItems[#trackedItems + 1] = { type = "button", label = L["Unlock / Position"], width = 200,
        onClick = function() setUnlocked(group, not group.unlocked) end }
    -- Closed by default (the sanctioned exception in placeSection): the strip
    -- up top already shows, reorders and removes these entries -- this list
    -- only repeats them in longhand, plus the per-entry conditions.
    items[#items + 1] = { type = "section", title = L["Tracked"], items = trackedItems,
        collapsible = true, collapsed = true, key = "tracked" }

    end -- tracked

    -- ------------------------------------------------------------- visibility
    if tabId == "visibility" then

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
                      group.anchorTo = v
                  elseif wouldCycle(group, v) then
                      ns:Print(L["Cooldown Manager: can't anchor there — it would loop."])
                  else
                      group.anchorTo = v
                  end
                  if group.anchorTo and group.anchorTo ~= prev then
                      group.x, group.y = 0, 0
                  end
                  positionBar(group); rebuildPage()
              end },
        }
        if group.anchorTo then
            anchorItems[#anchorItems + 1] = { type = "segmented", label = L["Side"], width = 200,
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
        items[#items + 1] = { type = "section", title = L["Anchor"], items = anchorItems }
    end

    items[#items + 1] = { type = "section", title = L["Visibility"], items = {
        { type = "dropdown", label = L["Show this bar"], width = 260,
          values = {
              { value = "always", text = L["Always"] },
              { value = "party",  text = L["Only in a party (not raid)"] },
              { value = "raid",   text = L["Only in a raid"] },
              { value = "solo",   text = L["Only while solo"] },
              { value = "never",  text = L["Never (temporarily off)"] },
          },
          get = function() return group.groupFilter or "always" end,
          set = function(_, v) group.groupFilter = v; refreshAll() end },
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

    end -- visibility

    -- ----------------------------------------------------------------- layout
    if tabId == "layout" then

    items[#items + 1] = { type = "button", width = 360, primary = true,
        label = ns:IsMoverEditMode("cooldownmanager") and L["Stop editing — lock the cooldown bars"]
                                                       or  L["Edit mode — move the cooldown bars"],
        tooltip = L["Unlocks just the cooldown bars so you can drag them. Arrow keys fine-tune; right-click a purple box for X/Y. (To move ALL VuloUI windows, use 'Unlock Mode' in Global.)"],
        onClick = function()
            ns:SetMoversEditMode(not ns:IsMoverEditMode("cooldownmanager"), "cooldownmanager")
            rebuildPage()
        end }
    items[#items + 1] = { type = "spacer", height = 6 }

    -- Split along one line: what shapes the BAR sits here, what shapes a single
    -- ICON sits in the display section below. Icon size and shape used to live
    -- up here next to "icons per row", which put three different subjects in one
    -- list and made the section the longest on the page by a wide margin.
    items[#items + 1] = { type = "section", title = L["Bar layout"], items = {
        { type = "slider", label = L["Icons per row"], min = 1, max = 20, step = 1,
          get = function() return group.perRow end,
          set = function(_, v) group.perRow = v; relayoutGroup(group) end },
        { type = "segmented", label = L["Growth direction"], width = 220,
          values = {
              { value = "RIGHT", text = L["Right"] }, { value = "LEFT", text = L["Left"] },
              { value = "DOWN",  text = L["Down"]  }, { value = "UP",   text = L["Up"]   },
          },
          get = function() return group.growth end,
          set = function(_, v) group.growth = v; relayoutGroup(group) end },
        { type = "slider", label = L["Spacing"], min = 0, max = 16, step = 1,
          get = function() return group.spacing end,
          set = function(_, v) group.spacing = v; relayoutGroup(group) end },
        { type = "slider", label = L["Bar scale"], min = 0.5, max = 2, step = 0.05,
          get = function() return group.scale or 1 end,
          set = function(_, v) group.scale = v; relayoutGroup(group); positionBar(group) end },
        { type = "slider", label = L["Bar opacity"], min = 0.1, max = 1, step = 0.05,
          get = function() return group.alpha or 1 end,
          set = function(_, v) group.alpha = v; refreshAll() end },
        { type = "toggle", label = L["Bar background"],
          get = function() return group.barBg == true end,
          set = function(_, v) group.barBg = v; relayoutGroup(group) end,
          subOptions = {
              { type = "button", label = L["Background color..."], width = 180,
                onClick = function()
                    openColorPicker(function() return group.barBgColor end,
                        function(c) group.barBgColor = c; relayoutGroup(group) end)
                end },
              { type = "slider", label = L["Background opacity"], min = 0.1, max = 1, step = 0.05,
                get = function() return group.barBgAlpha or 0.5 end,
                set = function(_, v) group.barBgAlpha = v; relayoutGroup(group) end },
          } },
    } }

    items[#items + 1] = { type = "section", title = L["Icon appearance"], items = {
        { type = "slider", label = L["Icon size"], min = 20, max = 64, step = 1,
          get = function() return group.iconSize end,
          set = function(_, v) group.iconSize = v; relayoutGroup(group) end },
        { type = "dropdown", label = L["Icon shape"], width = 220,
          values = {
              { value = "square",  text = L["Square"]  },
              { value = "rounded", text = L["Rounded"] },
              { value = "circle",  text = L["Circle"]  },
          },
          get = function() return group.iconShape or "square" end,
          set = function(_, v) group.iconShape = v; relayoutGroup(group) end },
        -- Was "Icon zoom", read in hundredths (0.08). Same setting, same stored
        -- fraction -- only the label and the unit changed, so that the control
        -- reads the same here and on the nameplate aura rows, which ask the very
        -- same question. No migration: group.iconZoom still holds the fraction.
        { type = "slider", label = L["Icon crop (%)"], min = 0, max = 30, step = 1,
          tooltip = L["How much is cut off each edge of the icon. 0 shows the whole icon including the border baked into its artwork."],
          get = function() return math.floor(((group.iconZoom or 0.08) * 100) + 0.5) end,
          set = function(_, v) group.iconZoom = v / 100; relayoutGroup(group) end },
        { type = "slider", label = L["Cooldown swipe darkness"], min = 0, max = 1, step = 0.05,
          get = function() return group.swipeAlpha or 0.6 end,
          set = function(_, v) group.swipeAlpha = v; relayoutGroup(group) end },
        { type = "slider", label = L["Icon border thickness"], min = 0, max = 3, step = 1,
          get = function()
              local v = group.borderSize
              if v == nil then v = 1 end
              return v
          end,
          set = function(_, v) group.borderSize = v; relayoutGroup(group) end },
        { type = "toggle", label = L["Class-colored border"],
          get = function() return group.borderClassColor == true end,
          set = function(_, v) group.borderClassColor = v; relayoutGroup(group) end,
          subOptions = {
              { type = "button", label = L["Border color..."], width = 180,
                onClick = function()
                    openColorPicker(function() return group.borderColor end,
                        function(c) group.borderColor = c; relayoutGroup(group) end)
                end },
          } },
    } }

    end -- layout

    -- ---------------------------------------------------------------- display
    if tabId == "display" then

    local displayItems = {
        { type = "toggle", label = L["Show countdown text"],
          get = function() return group.showText end,
          set = function(_, v) group.showText = v; refreshAll() end,
          subOptions = {
              { type = "slider", label = L["Countdown text size"], min = 25, max = 60, step = 5,
                tooltip = L["Percent of the icon size."],
                get = function() return math.floor((group.textScale or 0.4) * 100 + 0.5) end,
                set = function(_, v) group.textScale = v / 100; relayoutGroup(group) end },
              { type = "button", label = L["Countdown text color..."], width = 200,
                onClick = function()
                    openColorPicker(function() return group.textColor end,
                        function(c) group.textColor = c; refreshAll() end)
                end },
              { type = "slider", label = L["Warn color under (sec)"], min = 0, max = 10, step = 1,
                tooltip = L["Below this many seconds the countdown switches to the warn color; 0 turns the warn color off."],
                get = function() return group.lowThreshold or 3 end,
                set = function(_, v) group.lowThreshold = v; refreshAll() end },
              { type = "button", label = L["Warn color..."], width = 200,
                onClick = function()
                    openColorPicker(function() return group.textLowColor end,
                        function(c) group.textLowColor = c; refreshAll() end)
                end },
          } },
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
    displayItems[#displayItems + 1] = { type = "toggle", label = L["Show tooltips on hover"],
        tooltip = L["The icons then intercept the mouse - leave this off if the bar sits over clickable UI."],
        get = function() return group.showTooltips == true end,
        set = function(_, v) group.showTooltips = v; relayoutGroup(group) end }
    if group.mode ~= "cooldown" then
        displayItems[#displayItems + 1] = { type = "dropdown", label = L["Highlight"], width = 220,
            values = {
                { value = "proc",   text = L["Proc glow (animated)"] },
                { value = "glow",   text = L["Glow"] },
                { value = "border", text = L["Colored border"] },
                { value = "none",   text = L["None"] },
            },
            get = function() return group.auraStyle end,
            set = function(_, v) group.auraStyle = v; refreshAll() end,
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
        if group.mode == "aura" then
            displayItems[#displayItems + 1] = { type = "toggle", label = L["Keep inactive buffs visible (greyed out)"],
                tooltip = L["Icons stay in place when the buff runs out, just desaturated - the bar never jumps around."],
                get = function() return group.showInactive == true end,
                set = function(_, v) group.showInactive = v; relayoutGroup(group); refreshAll() end }
        end
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
        displayItems[#displayItems + 1] = { type = "toggle", label = L["Glow while ready"],
            tooltip = L["A steady glow while the cooldown is ready - and, for spells, only while it is actually usable (enough mana etc.)."],
            get = function() return group.readyGlow == true end,
            set = function(_, v) group.readyGlow = v; refreshAll() end,
            subOptions = {
                { type = "dropdown", label = L["Glow color"], width = 220,
                  values = {
                      { value = "yellow", text = L["Yellow"] }, { value = "gold",   text = L["Gold"] },
                      { value = "green",  text = L["Green"]  }, { value = "purple", text = L["Purple"] },
                      { value = "red",    text = L["Red"]    }, { value = "blue",   text = L["Blue"] },
                      { value = "white",  text = L["White"]  },
                  },
                  get = function() return group.readyGlowColor or "yellow" end,
                  set = function(_, v) group.readyGlowColor = v; refreshAll() end },
            } }
        displayItems[#displayItems + 1] = { type = "toggle", label = L["Show keybinds"],
            tooltip = L["Shows the key the spell/item is bound to on your action bars. Macros are not matched; stance pages follow the main bar."],
            get = function() return group.showKeybind == true end,
            set = function(_, v) group.showKeybind = v; relayoutGroup(group) end,
            subOptions = {
                { type = "slider", label = L["Keybind text size"], min = 6, max = 16, step = 1,
                  get = function() return group.keybindSize or 10 end,
                  set = function(_, v) group.keybindSize = v; relayoutGroup(group) end },
                { type = "button", label = L["Keybind color..."], width = 200,
                  onClick = function()
                      openColorPicker(function() return group.keybindColor end,
                          function(c) group.keybindColor = c; relayoutGroup(group) end)
                  end },
            } }
        displayItems[#displayItems + 1] = { type = "toggle", label = L["Tint blue when out of mana"],
            get = function() return group.tintUnusable ~= false end,
            set = function(_, v) group.tintUnusable = v; refreshAll() end }
        displayItems[#displayItems + 1] = { type = "toggle", label = L["Tint red when out of range"],
            tooltip = L["Needs a target; uses the spell's own range."],
            get = function() return group.tintRange == true end,
            set = function(_, v) group.tintRange = v; refreshAll() end }
    end
    items[#items + 1] = { type = "section", title = L["Icon display"], items = displayItems }

    end -- display

    return items
end

-- ---------------------------------------------------------------------------
-- Power bar (30.07.2026, user request): merged from Modules/PowerBar.lua as a
-- capsule; the integration capsule below makes it this module's fifth tab.
(function(...)
-- Movable HUD resource bar (mana / rage / energy / focus).
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("powerbar", {
    name        = "Power Bar",
    group       = "HUD",
    description = "A movable resource bar for your character. The power type follows your class automatically (Mana / Rage / Energy) — and for Druids it switches with your form: Bear = Rage, Cat = Energy, otherwise Mana.",
    defaults = {
        enabled    = true,
        width      = 220,
        height     = 20,
        x          = 0,
        y          = -200,
        unlocked   = false,
        texture    = "Atrocity",
        textMode   = "currentmax",
        fontSize   = 12,
        borderSize = 1,
        textAnchor = "CENTER",
        textX      = 0,
        textY      = 0,
        textColor  = { r = 1, g = 1, b = 1 },

        visibility    = "always",
        fadeAlpha     = 20,
        groupVis      = "any",
        onlyInstances = false,
        hideMounted   = false,
        hideNoTarget  = false,
        hideFull      = false,
        fadeOOC       = false,
        oocAlpha      = 40,

        colorMode     = "power",
        customColor   = { r = 0.25, g = 0.45, b = 0.95 },
        gradient      = false,
        gradientColor = { r = 0, g = 0, b = 0 },
        borderColor   = { r = 0, g = 0, b = 0 },
        bgColor       = { r = 0.05, g = 0.05, b = 0.06 },
        bgAlpha       = 0.85,
        smooth        = false,
        strata        = "MEDIUM",
        orient        = "h",     -- "h" | "v" (fills up) | "vd" (fills down)
        fillAlpha     = 1,       -- below 1 the world shows through the FILL

        hashMarks      = "",
        hashPct        = true,
        hashWidth      = 1,
        hashColor      = { r = 0, g = 0, b = 0 },
        thresholdOn    = false,
        threshold      = 20,
        thresholdPct   = true,
        thresholdDir   = "below",
        thresholdColor = { r = 0.9, g = 0.2, b = 0.2 },
        thresholdText  = false,
    },
})

local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local format, floor = string.format, math.floor

-- Keyed by the UnitPowerType token. The table moved to ns.POWER_COLORS so the
-- resource-color settings can rewrite its fields in place; this alias keeps
-- every read below unchanged.
local POWER_COLORS = ns.POWER_COLORS
local DEFAULT_COLOR = POWER_COLORS.MANA

local DEFAULT_TEXTURE = "Atrocity"
local lsmStatusbar   = ns.MediaStatusbar
local textureValues  = ns.MediaStatusbarValues

local function textModeValues()
    return {
        { value = "none",       text = L["No text"] },
        { value = "current",    text = L["Current value"] },
        { value = "currentmax", text = L["Current / Max"] },
        { value = "percent",    text = L["Percent"] },
        { value = "full",       text = L["Current / Max (%)"] },
    }
end

local frame, bar, barText, borderEdges

local function applyFont()
    if not barText then return end
    if ns.UI and ns.UI.Font then
        ns.UI.Font(barText, mod.db.fontSize, "OUTLINE")
    else
        barText:SetFont(STANDARD_TEXT_FONT, mod.db.fontSize, "OUTLINE")
    end
    local c = mod.db.textColor or { r = 1, g = 1, b = 1 }
    barText:SetTextColor(c.r or 1, c.g or 1, c.b or 1)
end

local function currentColor()
    local d = mod.db
    if d.colorMode == "custom" and d.customColor then return d.customColor end
    if d.colorMode == "class" then
        local _, cls = UnitClass("player")
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        if c then return c end
    end
    local _, token = UnitPowerType("player")
    return POWER_COLORS[token] or DEFAULT_COLOR
end

local bgTex

local function applyAppearance()
    if not bar then return end
    local d = mod.db
    local vert = d.orient == "v" or d.orient == "vd"
    bar:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    if bar.SetRotatesTexture then bar:SetRotatesTexture(vert) end
    if bar.SetReverseFill then bar:SetReverseFill(d.orient == "vd") end
    bar:SetStatusBarTexture(lsmStatusbar(d.texture))
    local t = bar:GetStatusBarTexture()
    if t and t.SetHorizTile then t:SetHorizTile(false); t:SetVertTile(false) end
    if t then t:SetAlpha(d.fillAlpha or 1) end
    local c = currentColor()
    bar:SetStatusBarColor(c.r, c.g, c.b)
    if t and t.SetGradient and CreateColor then
        -- The gradient runs along the fill direction. Min side is always the
        -- BOTTOM for vertical bars; with reverse fill the fill's END is the
        -- bottom, so the end colour swaps sides to stay at the fill's end.
        local dir = vert and "VERTICAL" or "HORIZONTAL"
        if d.gradient then
            local g2 = d.gradientColor or { r = 0, g = 0, b = 0 }
            local c1, c2 = CreateColor(1, 1, 1, 1), CreateColor(g2.r, g2.g, g2.b, 1)
            if d.orient == "vd" then c1, c2 = c2, c1 end
            t:SetGradient(dir, c1, c2)
        else
            t:SetGradient(dir, CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
        end
    end
    if bgTex then
        local bc = d.bgColor or { r = 0.05, g = 0.05, b = 0.06 }
        bgTex:SetColorTexture(bc.r, bc.g, bc.b, d.bgAlpha or 0.85)
    end
    applyFont()
end

local function applyBorder()
    if not frame or not borderEdges then return end
    local c = mod.db.borderColor or ns.COLORS.borderDark or { r = 0, g = 0, b = 0 }
    ns.LayoutEdges(borderEdges, frame, mod.db.borderSize or 0, c.r, c.g, c.b, 1, 0)
end

local applyHashes   -- forward declaration: assigned below, captured as an upvalue here

local function applySize()
    if not frame then return end
    frame:SetSize(ns:PixelSnap(mod.db.width, frame), ns:PixelSnap(mod.db.height, frame))
    applyBorder()
    if applyHashes then applyHashes() end
end

local function applyPos()
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        ns:PixelSnap(mod.db.x or 0, frame), ns:PixelSnap(mod.db.y or 0, frame))
end

local function applyText()
    if not barText or not bar then return end
    barText:ClearAllPoints()
    local anchor = mod.db.textAnchor or "CENTER"
    local ox, oy = mod.db.textX or 0, mod.db.textY or 0
    if anchor == "LEFT" then
        barText:SetPoint("LEFT", bar, "LEFT", 4 + ox, oy)
        barText:SetJustifyH("LEFT")
    elseif anchor == "RIGHT" then
        barText:SetPoint("RIGHT", bar, "RIGHT", -4 + ox, oy)
        barText:SetJustifyH("RIGHT")
    else
        barText:SetPoint("CENTER", bar, "CENTER", ox, oy)
        barText:SetJustifyH("CENTER")
    end
end

local hashPool = {}
function applyHashes()
    for _, t in ipairs(hashPool) do t:Hide() end
    if not bar then return end
    local d = mod.db
    local list = d.hashMarks
    if not list or list == "" then return end
    -- Marks sit ACROSS the fill direction: vertical lines along a horizontal
    -- bar, horizontal lines up a vertical one.
    local vert = d.orient == "v" or d.orient == "vd"
    local w = (vert and bar:GetHeight() or bar:GetWidth()) or 0
    if w <= 0 then return end
    local i = 0
    for numStr in tostring(list):gmatch("[%d%.]+") do
        local v = tonumber(numStr)
        local frac
        if v then
            if d.hashPct then
                frac = v / 100
            else
                local mx = UnitPowerMax("player") or 0
                frac = mx > 0 and v / mx or nil
            end
        end
        if frac and frac > 0 and frac < 1 then
            i = i + 1
            local t = hashPool[i]
            if not t then t = bar:CreateTexture(nil, "ARTWORK", nil, 2); hashPool[i] = t end
            local c = d.hashColor or { r = 0, g = 0, b = 0 }
            local hw = d.hashWidth or 1
            t:SetColorTexture(c.r, c.g, c.b, 0.9)
            t:ClearAllPoints()
            if vert then
                -- both dimensions set anew: a pooled mark may have carried the
                -- other orientation a moment ago. Reverse fill runs top-down,
                -- so the mark for value X mirrors to (1 - frac) -- otherwise
                -- mark and fill boundary would only ever meet at 100-X.
                local yy = (d.orient == "vd") and (w * (1 - frac)) or (w * frac)
                t:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  0, yy - hw / 2)
                t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, yy - hw / 2)
                t:SetHeight(hw)
            else
                t:SetPoint("TOPLEFT",    bar, "TOPLEFT",    w * frac - hw / 2, 0)
                t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", w * frac - hw / 2, 0)
                t:SetWidth(hw)
            end
            t:Show()
        end
    end
end

local smoothTicker, smoothTarget
local function ensureSmooth()
    if smoothTicker then return end
    smoothTicker = CreateFrame("Frame"); smoothTicker:Hide()
    smoothTicker:SetScript("OnUpdate", function(self, e)
        if not bar or smoothTarget == nil then self:Hide(); return end
        local cur = bar:GetValue()
        local diff = smoothTarget - cur
        if math.abs(diff) < 0.5 then
            bar:SetValue(smoothTarget); self:Hide(); return
        end
        bar:SetValue(cur + diff * math.min(1, e * 12))
    end)
end

local updateVisibility   -- forward declaration: assigned below, captured as an upvalue here

local function updateValue()
    if not bar then return end
    local d = mod.db
    local cur = UnitPower("player") or 0
    local max = UnitPowerMax("player") or 0
    if max <= 0 then max = 1 end
    bar:SetMinMaxValues(0, max)
    if d.smooth then
        ensureSmooth()
        smoothTarget = cur
        smoothTicker:Show()
    else
        bar:SetValue(cur)
    end

    local c = currentColor()
    local tc = d.textColor or { r = 1, g = 1, b = 1 }
    if d.thresholdOn then
        local ref = d.thresholdPct and (cur / max * 100) or cur
        local hit = (d.thresholdDir == "above") and (ref >= (d.threshold or 20))
            or (d.thresholdDir ~= "above") and (ref <= (d.threshold or 20))
        if hit then
            if d.thresholdText then tc = d.thresholdColor or tc
            else c = d.thresholdColor or c end
        end
    end
    bar:SetStatusBarColor(c.r, c.g, c.b)

    if not barText then return end
    barText:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1)
    local mode = d.textMode
    if mode == "none" then
        barText:SetText("")
    elseif mode == "current" then
        barText:SetText(tostring(cur))
    elseif mode == "percent" then
        barText:SetText(floor(cur / max * 100 + 0.5) .. "%")
    elseif mode == "full" then
        barText:SetText(format("%d / %d  (%d%%)", cur, max, floor(cur / max * 100 + 0.5)))
    else
        barText:SetText(format("%d / %d", cur, max))
    end
    if updateVisibility then updateVisibility() end
end

local function updatePowerType()
    applyAppearance()
    updateValue()
end

function updateVisibility()
    if not frame or not mod.active then return end
    local d = mod.db
    if d.unlocked then frame:Show(); frame:SetAlpha(1); return end
    local show = true
    if d.onlyInstances and not IsInInstance() then show = false end
    if show and d.hideMounted and IsMounted and IsMounted() then show = false end
    if show and d.hideNoTarget and not UnitExists("target") then show = false end
    local grp = d.groupVis
    if show and grp and grp ~= "any" then
        if grp == "group" then show = IsInGroup()
        elseif grp == "raid" then show = IsInRaid()
        elseif grp == "party" then show = IsInGroup() and not IsInRaid()
        elseif grp == "solo" then show = not IsInGroup() end
    end
    if show and d.hideFull and not UnitAffectingCombat("player") then
        local cur, mx = UnitPower("player") or 0, UnitPowerMax("player") or 0
        if mx > 0 and cur >= mx then show = false end
    end
    local m = d.visibility
    if show then
        if m == "combat" then show = UnitAffectingCombat("player")
        elseif m == "noncombat" then show = not UnitAffectingCombat("player") end
    end
    if not show then frame:Hide(); return end
    frame:Show()
    if m == "mouseover" then
        frame:SetAlpha(frame:IsMouseOver(8, -8, -8, 8) and 1 or (d.fadeAlpha or 20) / 100)
    elseif d.fadeOOC and not UnitAffectingCombat("player") then
        frame:SetAlpha((d.oocAlpha or 40) / 100)
    else
        frame:SetAlpha(1)
    end
end

-- Mouseover and mounted state fire no events; a slow ticker polls them instead.
local visTicker
local function updateVisTicker()
    local d = mod.db
    local need = mod.active and (d.visibility == "mouseover" or d.hideMounted)
    if need then
        if not visTicker then
            visTicker = CreateFrame("Frame")
            visTicker._acc = 0
            visTicker:SetScript("OnUpdate", function(self, e)
                self._acc = self._acc + e
                if self._acc < 0.2 then return end
                self._acc = 0
                updateVisibility()
            end)
        end
        visTicker:Show()
    elseif visTicker then
        visTicker:Hide()
    end
end

local function createBorder()
    borderEdges = ns.MakeEdges(frame, "OVERLAY")
end

local function build()
    if frame then return frame end
    frame = CreateFrame("Frame", "VCUIPowerBar", UIParent)
    frame:SetSize(mod.db.width, mod.db.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
    frame:SetFrameStrata(mod.db.strata or "MEDIUM")

    bgTex = frame:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(frame)
    bgTex:SetColorTexture(0.05, 0.05, 0.06, 0.85)

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetAllPoints(frame)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    createBorder()

    barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    applyFont()

    frame.mover = ns:CreateMover(frame, {
        key    = "powerbar",
        label  = L["|cffffffffPOWER BAR|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = mod.db,
        width  = math.max(mod.db.width + 20, 140),
        height = math.max(mod.db.height + 24, 44),
        onMove = function() applyPos() end,
    })

    applyBorder()
    applyText()
    return frame
end

local function setUnlocked(state)
    mod.db.unlocked = state and true or false
    build()
    if mod.db.unlocked then
        frame:Show()
        frame.mover:Show()
        ns:Print(L["Power Bar mover active. |cff9b6cffDrag the purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Move' again to finish."])
    else
        frame.mover:Hide()
        ns:Print(L["Power Bar mover disabled."])
    end
end

local ev
-- OnDisable calls UnregisterAllEvents, so always re-register, never early-return here.
local function registerEvents()
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event)
            if event == "UNIT_DISPLAYPOWER" then
                updatePowerType()
            elseif event == "PLAYER_ENTERING_WORLD" then
                applyAppearance(); updateValue(); applyHashes(); updateVisibility()
            elseif event == "UNIT_MAXPOWER" then
                updateValue(); applyHashes()
            elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED"
                or event == "PLAYER_TARGET_CHANGED" or event == "GROUP_ROSTER_UPDATE"
                or event == "ZONE_CHANGED_NEW_AREA" then
                updateVisibility()
            else
                updateValue()
            end
        end)
    end
    ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    ev:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
end

function mod:OnEnable()
    -- A saved unlock short-circuits every visibility rule and leaves the bar on
    -- screen with no mover to grab, because setUnlocked never runs on load.
    mod.db.unlocked = false
    if not mod.db.texture then mod.db.texture = DEFAULT_TEXTURE end
    build()
    applySize(); applyPos(); applyAppearance(); updateValue(); applyHashes()
    registerEvents()
    frame:Show()
    updateVisibility()
    updateVisTicker()
end

function mod:OnDisable()
    if ev then ev:UnregisterAllEvents() end
    if visTicker then visTicker:Hide() end
    if smoothTicker then smoothTicker:Hide() end
    if frame then frame:Hide() end
end

-- ---------------------------------------------------------------------------
-- Options-page live preview: a separate mock pinned above the scroll area,
-- never the real bar -- the real one obeys its visibility rules and sits
-- wherever the mover put it, usually behind the options window. Styled from
-- the same db keys the real bar reads. The fill is a rolled 30-80% of the
-- REAL power maximum rather than the live value: a full mana bar would hide
-- exactly the background half of what the sliders change.

local pv, pvPct

local function pvStyle()
    if not (pv and pv:IsVisible()) then return end
    local d = mod.db
    local vert = d.orient == "v" or d.orient == "vd"
    local hostW = pv:GetWidth() or 500
    local w, h
    if vert then
        w, h = math.min(d.width or 220, 40), math.min(d.height or 20, 44)
    else
        w, h = math.min(d.width or 220, math.max(120, hostW - 24)), math.min(d.height or 20, 40)
    end
    pv.holder:SetSize(w, h)
    pv.bar:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    if pv.bar.SetRotatesTexture then pv.bar:SetRotatesTexture(vert) end
    if pv.bar.SetReverseFill then pv.bar:SetReverseFill(d.orient == "vd") end
    pv.bar:SetStatusBarTexture(lsmStatusbar(d.texture))
    local t = pv.bar:GetStatusBarTexture()
    if t and t.SetHorizTile then t:SetHorizTile(false); t:SetVertTile(false) end
    if t then t:SetAlpha(d.fillAlpha or 1) end
    local c = currentColor()
    pv.bar:SetStatusBarColor(c.r, c.g, c.b)
    if t and t.SetGradient and CreateColor then
        -- same end-colour mirror as the real bar (see applyAppearance)
        local dir = vert and "VERTICAL" or "HORIZONTAL"
        if d.gradient then
            local g2 = d.gradientColor or { r = 0, g = 0, b = 0 }
            local c1, c2 = CreateColor(1, 1, 1, 1), CreateColor(g2.r, g2.g, g2.b, 1)
            if d.orient == "vd" then c1, c2 = c2, c1 end
            t:SetGradient(dir, c1, c2)
        else
            t:SetGradient(dir, CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
        end
    end
    local bc = d.bgColor or { r = 0.05, g = 0.05, b = 0.06 }
    pv.bg:SetColorTexture(bc.r, bc.g, bc.b, d.bgAlpha or 0.85)
    local ec = d.borderColor or { r = 0, g = 0, b = 0 }
    ns.LayoutEdges(pv.edges, pv.holder, d.borderSize or 0, ec.r, ec.g, ec.b, 1, 0)

    local max = UnitPowerMax("player") or 100
    if max <= 0 then max = 100 end
    local cur = floor(max * (pvPct or 60) / 100 + 0.5)
    pv.bar:SetMinMaxValues(0, max)
    pv.bar:SetValue(cur)
    if ns.UI and ns.UI.Font then ns.UI.Font(pv.text, d.fontSize, "OUTLINE") end
    local tc = d.textColor or { r = 1, g = 1, b = 1 }
    pv.text:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1)
    local mode = d.textMode
    if mode == "none" then pv.text:SetText("")
    elseif mode == "current" then pv.text:SetText(tostring(cur))
    elseif mode == "percent" then pv.text:SetText(floor(cur / max * 100 + 0.5) .. "%")
    elseif mode == "full" then pv.text:SetText(format("%d / %d  (%d%%)", cur, max, floor(cur / max * 100 + 0.5)))
    else pv.text:SetText(format("%d / %d", cur, max)) end
    pv.text:ClearAllPoints()
    local anchor = d.textAnchor or "CENTER"
    local ox, oy = d.textX or 0, d.textY or 0
    if anchor == "LEFT" then
        pv.text:SetPoint("LEFT", pv.bar, "LEFT", 4 + ox, oy)
    elseif anchor == "RIGHT" then
        pv.text:SetPoint("RIGHT", pv.bar, "RIGHT", -4 + ox, oy)
    else
        pv.text:SetPoint("CENTER", pv.bar, "CENTER", ox, oy)
    end
end

-- Exported: the cooldown manager's BuildPageHeader hands its host over while
-- the power-bar tab is open. Returns the pinned height.
function mod.BuildPreview(host)
    if not pv then
        pv = CreateFrame("Frame", nil, host)
        pv.holder = CreateFrame("Frame", nil, pv)
        pv.holder:SetPoint("CENTER", pv, "CENTER", 0, 0)
        pv.bg = pv.holder:CreateTexture(nil, "BACKGROUND")
        pv.bg:SetAllPoints(pv.holder)
        pv.bar = CreateFrame("StatusBar", nil, pv.holder)
        pv.bar:SetAllPoints(pv.holder)
        pv.edges = ns.MakeEdges(pv.holder, "OVERLAY")
        pv.text = pv.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        -- Restyles on a slow tick while visible: every slider write shows
        -- within a quarter second without wiring thirty setters to it.
        pv._acc = 0
        pv:SetScript("OnUpdate", function(self, e)
            self._acc = self._acc + e
            if self._acc < 0.25 then return end
            self._acc = 0
            pvStyle()
        end)
    end
    if not pvPct then pvPct = math.random(30, 80) end
    pv:SetParent(host)
    pv:ClearAllPoints()
    pv:SetPoint("TOPLEFT", host, "TOPLEFT", 14, 0)
    pv:SetPoint("TOPRIGHT", host, "TOPRIGHT", -14, 0)
    pv:SetHeight(56)
    pv:Show()
    pvStyle()
    return 56
end

function mod:GetOptions()
    local SLW = 180
    return {
        { type = "desc",
          text = L["|cffaaaaaaResource bar that follows your class automatically (Mana / Rage / Energy). Druids switch with their form: Bear = Rage, Cat = Energy, otherwise Mana.|r"] },

        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Unlock / Move"], width = 130,
              onClick = function() setUnlocked(not mod.db.unlocked) end },
            { type = "button", label = L["Center Position"], width = 150,
              onClick = function() mod.db.x, mod.db.y = 0, -200; applyPos() end },
        } },

        { type = "section", title = L["Size"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Width"], min = 80, max = 600, step = 2, width = SLW,
                  get = function() return mod.db.width end,
                  set = function(_, v) mod.db.width = v; applySize() end },
                { type = "slider", label = L["Height"], min = 6, max = 60, step = 1, width = SLW,
                  get = function() return mod.db.height end,
                  set = function(_, v) mod.db.height = v; applySize() end },
            } },
            -- For a standing bar swap Width/Height yourself -- the two sliders
            -- keep their meaning (width = horizontal extent), so a saved
            -- horizontal layout survives switching back.
            { type = "segmented", label = L["Orientation"], width = 360,
              values = {
                  { value = "h",  text = L["Horizontal"] },
                  { value = "v",  text = L["Vertical (up)"] },
                  { value = "vd", text = L["Vertical (down)"] },
              },
              get = function() return mod.db.orient or "h" end,
              set = function(_, v) mod.db.orient = v; applyAppearance(); updateValue(); applyHashes() end },
        } },

        { type = "section", title = L["Text"], items = {
            -- "No text" is one of the choices, and then nothing below it means
            -- anything -- so the whole section hangs off this one dropdown.
            { type = "dropdown", label = L["Bar text"], width = 300, values = textModeValues(),
              get = function() return mod.db.textMode end,
              set = function(_, v) mod.db.textMode = v; updateValue() end,
              subOptions = {
                  { type = "segmented", label = L["Text position"], width = 300,
                    values = {
                        { value = "LEFT",   text = L["Left"] },
                        { value = "CENTER", text = L["Center"] },
                        { value = "RIGHT",  text = L["Right"] },
                    },
                    get = function() return mod.db.textAnchor end,
                    set = function(_, v) mod.db.textAnchor = v; applyText() end },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Font size"], min = 8, max = 24, step = 1, width = SLW,
                        get = function() return mod.db.fontSize end,
                        set = function(_, v) mod.db.fontSize = v; applyFont() end },
                      { type = "color", label = L["Text color"], width = 160,
                        get = function() return mod.db.textColor end,
                        set = function(r, g, b) mod.db.textColor = { r = r, g = g, b = b }; applyFont() end },
                  } },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Text offset X"], min = -100, max = 100, step = 1, width = SLW,
                        get = function() return mod.db.textX end,
                        set = function(_, v) mod.db.textX = v; applyText() end },
                      { type = "slider", label = L["Text offset Y"], min = -50, max = 50, step = 1, width = SLW,
                        get = function() return mod.db.textY end,
                        set = function(_, v) mod.db.textY = v; applyText() end },
                  } },
              } },
        } },

        { type = "section", title = L["Appearance"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Border thickness (px)"], min = 0, max = 4, step = 1, width = SLW,
                  get = function() return mod.db.borderSize end,
                  set = function(_, v) mod.db.borderSize = v; applyBorder() end },
                { type = "dropdown", label = L["Bar texture"], width = 300, values = textureValues(),
                  get = function() return mod.db.texture end,
                  set = function(_, v) mod.db.texture = v; applyAppearance() end },
            } },
            { type = "dropdown", label = L["Bar colour"], width = 260,
              values = {
                  { value = "power",  text = L["Power colour (automatic)"] },
                  { value = "class",  text = L["Class colour"] },
                  { value = "custom", text = L["Custom colour"] },
              },
              get = function() return mod.db.colorMode or "power" end,
              set = function(_, v) mod.db.colorMode = v; applyAppearance(); updateValue() end,
              subOptions = {
                  { type = "color", label = L["Custom colour"], width = 200,
                    get = function() return mod.db.customColor end,
                    set = function(r, g, b) mod.db.customColor = { r = r, g = g, b = b }; applyAppearance(); updateValue() end },
              } },
            { type = "checkbox", label = L["Gradient"],
              tooltip = L["The fill fades into a second colour towards its end."],
              get = function() return mod.db.gradient end,
              set = function(_, v) mod.db.gradient = v; applyAppearance() end,
              subOptions = {
                  { type = "color", label = L["Gradient end colour"], width = 200,
                    get = function() return mod.db.gradientColor end,
                    set = function(r, g, b) mod.db.gradientColor = { r = r, g = g, b = b }; applyAppearance() end },
              } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "color", label = L["Border colour"], width = 160,
                  get = function() return mod.db.borderColor end,
                  set = function(r, g, b) mod.db.borderColor = { r = r, g = g, b = b }; applyBorder() end },
                { type = "color", label = L["Background colour"], width = 160,
                  get = function() return mod.db.bgColor end,
                  set = function(r, g, b) mod.db.bgColor = { r = r, g = g, b = b }; applyAppearance() end },
            } },
            { type = "slider", label = L["Background opacity"], min = 0, max = 100, step = 5, width = SLW,
              get = function() return floor((mod.db.bgAlpha or 0.85) * 100 + 0.5) end,
              set = function(_, v) mod.db.bgAlpha = v / 100; applyAppearance() end },
            { type = "slider", label = L["Fill opacity"], min = 10, max = 100, step = 5, width = SLW,
              tooltip = L["Below 100 the world shows through the filled part of the bar."],
              get = function() return floor((mod.db.fillAlpha or 1) * 100 + 0.5) end,
              set = function(_, v) mod.db.fillAlpha = v / 100; applyAppearance() end },
            { type = "dropdown", label = L["Frame strata"], width = 220,
              values = {
                  { value = "BACKGROUND", text = L["Background"] },
                  { value = "LOW",        text = L["Low"] },
                  { value = "MEDIUM",     text = L["Medium"] },
                  { value = "HIGH",       text = L["High"] },
                  { value = "DIALOG",     text = L["Dialog"] },
              },
              get = function() return mod.db.strata or "MEDIUM" end,
              set = function(_, v) mod.db.strata = v; if frame then frame:SetFrameStrata(v) end end },
            { type = "checkbox", label = L["Smooth value changes"],
              get = function() return mod.db.smooth end,
              set = function(_, v) mod.db.smooth = v end },
        } },

        { type = "section", title = L["Visibility"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "dropdown", label = L["Visibility"], width = 220,
                  values = ns.VisibilityValues(),
                  get = function() return mod.db.visibility or "always" end,
                  set = function(_, v) mod.db.visibility = v; updateVisibility(); updateVisTicker() end },
                { type = "dropdown", label = L["Group visibility"], width = 220,
                  values = ns.GroupVisValues(),
                  get = function() return mod.db.groupVis or "any" end,
                  set = function(_, v) mod.db.groupVis = v; updateVisibility() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Only in instances"],
                  get = function() return mod.db.onlyInstances end,
                  set = function(_, v) mod.db.onlyInstances = v; updateVisibility() end },
                { type = "checkbox", label = L["Hide when mounted"],
                  get = function() return mod.db.hideMounted end,
                  set = function(_, v) mod.db.hideMounted = v; updateVisibility(); updateVisTicker() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Hide without target"],
                  get = function() return mod.db.hideNoTarget end,
                  set = function(_, v) mod.db.hideNoTarget = v; updateVisibility() end },
                { type = "checkbox", label = L["Hide while full (out of combat)"],
                  get = function() return mod.db.hideFull end,
                  set = function(_, v) mod.db.hideFull = v; updateVisibility() end },
            } },
            { type = "checkbox", label = L["Fade out of combat"],
              get = function() return mod.db.fadeOOC end,
              set = function(_, v) mod.db.fadeOOC = v; updateVisibility() end,
              subOptions = {
                  { type = "slider", label = L["Out-of-combat opacity"], min = 10, max = 90, step = 5, width = SLW,
                    get = function() return mod.db.oocAlpha or 40 end,
                    set = function(_, v) mod.db.oocAlpha = v; updateVisibility() end },
              } },
            { type = "slider", label = L["Faded opacity"], min = 0, max = 90, step = 5, width = SLW,
              tooltip = L["Mouseover mode: the bar's opacity while the mouse is elsewhere."],
              get = function() return mod.db.fadeAlpha or 20 end,
              set = function(_, v) mod.db.fadeAlpha = v; updateVisibility() end },
        } },

        { type = "section", title = L["Marks & threshold"], items = {
            { type = "editbox", label = L["Hash marks"], width = 260,
              tooltip = L["Comma-separated values, e.g. 30,60 — draws a line at each (great for tick or breakpoint marks)."],
              get = function() return mod.db.hashMarks or "" end,
              set = function(_, v) mod.db.hashMarks = tostring(v or ""); applyHashes() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Values are percent"],
                  get = function() return mod.db.hashPct end,
                  set = function(_, v) mod.db.hashPct = v; applyHashes() end },
                { type = "slider", label = L["Mark width"], min = 1, max = 4, step = 1, width = SLW,
                  get = function() return mod.db.hashWidth or 1 end,
                  set = function(_, v) mod.db.hashWidth = v; applyHashes() end },
            } },
            { type = "color", label = L["Mark colour"], width = 200,
              get = function() return mod.db.hashColor end,
              set = function(r, g, b) mod.db.hashColor = { r = r, g = g, b = b }; applyHashes() end },
            { type = "checkbox", label = L["Threshold colouring"],
              tooltip = L["Recolours the bar (or its text) once the resource crosses the threshold."],
              get = function() return mod.db.thresholdOn end,
              set = function(_, v) mod.db.thresholdOn = v; updateValue() end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "editbox", label = L["Threshold"], width = 120, numeric = true,
                        get = function() return mod.db.threshold or 20 end,
                        set = function(_, v) mod.db.threshold = tonumber(v) or 20; updateValue() end },
                      { type = "checkbox", label = L["Values are percent"],
                        get = function() return mod.db.thresholdPct end,
                        set = function(_, v) mod.db.thresholdPct = v; updateValue() end },
                  } },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "segmented", label = L["Direction"], width = 200,
                        values = {
                            { value = "below", text = L["At or below"] },
                            { value = "above", text = L["At or above"] },
                        },
                        get = function() return mod.db.thresholdDir or "below" end,
                        set = function(_, v) mod.db.thresholdDir = v; updateValue() end },
                      { type = "color", label = L["Threshold colour"], width = 160,
                        get = function() return mod.db.thresholdColor end,
                        set = function(r, g, b) mod.db.thresholdColor = { r = r, g = g, b = b }; updateValue() end },
                  } },
                  { type = "checkbox", label = L["Recolour the text instead of the bar"],
                    get = function() return mod.db.thresholdText end,
                    set = function(_, v) mod.db.thresholdText = v; updateValue() end },
              } },
        } },
    }
end
end)(...);

(function(...)
-- Integration: the power bar page becomes a tab of the cooldown manager and
-- leaves the sidebar (parentTab). Runs after both registrations above.
local _, ns = ...
local cdm = ns.modules and ns.modules.cooldownmanager
local pb  = ns.modules and ns.modules.powerbar
if not (cdm and pb and cdm.tabs) then return end
pb.parentTab = "cooldownmanager"
cdm.tabs[#cdm.tabs + 1] = { id = "powerbar", label = pb.name }
end)(...);
