-- VuloClassicUI / Modules / Reminders
-- What is missing right now, as a short row of icons you can click to fix.
--
-- Written for this client rather than ported: spell ranks, greater/lesser buff
-- pairs, ammo, durability and unspent talent points do not exist on modern
-- clients and are exactly the things that bite here.
--
-- Combat rule: the icons are SecureActionButtons so a click can cast the fix,
-- and those may not be created, moved, shown or hidden while locked down. So
-- the whole display is frozen in combat and catches up on leaving it. That
-- costs nothing real - every reminder here is something you fix before a pull.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("reminders", {
    name        = "Reminders",
    group       = "Global",
    description = "Shows what you are missing - class buffs, weapon enchants, food, stance, pet, ammo, durability, empty gear slots and unspent talent points.",
    defaults = {
        -- Off until asked for. This is the fallback ns:IsModuleEnabled reads
        -- when a character has no explicit preference yet; stating it beats
        -- relying on the key being absent.
        enabled   = false,

        iconSize  = 36,
        spacing   = 6,
        maxIcons  = 4,
        x         = 0,
        y         = 200,
        showLabel = true,
        fontSize  = 11,
        settle    = 2.0,      -- seconds a problem must persist before it shows
        fadeTime  = 0.15,

        catBuffs  = true,
        catWeapon = true,
        catStance = true,
        catPet    = true,
        catFood   = true,
        catGear   = true,
        -- Off by default: a levelling character legitimately has an empty ring,
        -- trinket or cloak, and a permanently lit icon trains you to ignore the
        -- whole row.
        ruleEmptySlots = false,

        expireSoon    = 300,  -- seconds; 0 disables "running out" warnings
        durabilityPct = 25,
        ammoLow       = 200,

        quietResting  = true,
        quietEating   = true,
        onlyInGroup   = false,
    },
})

local GetTime, UnitBuff = GetTime, UnitBuff
local floor = math.floor

-- ---------------------------------------------------------------------------
-- Detection helpers
--
-- Everything matches on the LOCALISED BASE NAME resolved from a representative
-- spell id. On this client every rank shares one base name, so a single lookup
-- covers "Rank 1" through "Rank 7" without listing an id per rank, and it stays
-- correct in every game language.

local nameCache = {}
local function spellName(id)
    if not id then return nil end
    local n = nameCache[id]
    if n ~= nil then return n or nil end
    local ok, res = pcall(GetSpellInfo, id)
    n = (ok and res) or false
    nameCache[id] = n
    return n or nil
end

-- Sets are rebuilt whenever they come back empty, because the first refresh can
-- land before the spell data is queryable and a permanently empty set would
-- report "missing" for the rest of the session.
local function nameSet(ids)
    local set, n = {}, 0
    for _, id in ipairs(ids) do
        local nm = spellName(id)
        if nm then set[nm] = true; n = n + 1 end
    end
    return (n > 0) and set or nil
end

local auraNames, auraIcons, auraExpiry = {}, {}, {}
local function scanPlayerAuras()
    wipe(auraNames); wipe(auraIcons); wipe(auraExpiry)
    for i = 1, 40 do
        -- name, icon, count, debuffType, duration, expirationTime
        local name, icon, _, _, _, expires = UnitBuff("player", i)
        if not name then break end
        auraNames[name] = true
        auraIcons[name] = icon
        auraExpiry[name] = expires or 0
    end
end

local function haveAnyAura(set)
    if not set then return false end
    for n in pairs(set) do
        if auraNames[n] then return true, auraExpiry[n] end
    end
    return false
end

-- Is a buff missing, or close enough to gone to be worth saying so?
local function lacking(set)
    local have, exp = haveAnyAura(set)
    if not have then return true end
    local soon = mod.db.expireSoon or 0
    if soon <= 0 or not exp or exp == 0 then return false end
    return (exp - GetTime()) < soon
end

-- GetSpellInfo(name) answers "is this in my spellbook" in one call. Walking the
-- book instead cost ~200 pcalls per rule per refresh for the same answer.
local function knowsSpell(baseName)
    if not baseName then return false end
    local ok, res = pcall(GetSpellInfo, baseName)
    return ok and res ~= nil
end

-- ---------------------------------------------------------------------------
-- Rules. A rule is data: key, category, priority, an optional class gate, a
-- test that reports whether something is missing, and what to show for it.

local RULES = {}
local function rule(t) RULES[#RULES + 1] = t end

-- `ids` lists one representative id per variant that satisfies the need, so the
-- greater version counts too: casting Prayer of Fortitude must not leave a
-- "you forgot Fortitude" reminder standing.
local CLASS_BUFFS = {
    { key = "fortitude", class = "PRIEST",  cast = 1243,  ids = { 1243, 21562 } },
    { key = "spirit",    class = "PRIEST",  cast = 14752, ids = { 14752, 27681 } },
    { key = "intellect", class = "MAGE",    cast = 1459,  ids = { 1459, 23028 } },
    { key = "wild",      class = "DRUID",   cast = 1126,  ids = { 1126, 21849 } },
    { key = "thorns",    class = "DRUID",   cast = 467,   ids = { 467 } },
    { key = "shout",     class = "WARRIOR", cast = 6673,  ids = { 6673 } },
}

for _, b in ipairs(CLASS_BUFFS) do
    rule({
        key = "buff_" .. b.key,
        cat = "catBuffs",
        priority = 70,
        class = b.class,
        test = function()
            local base = spellName(b.cast)
            if not (base and knowsSpell(base)) then return false end
            b._set = b._set or nameSet(b.ids)
            return lacking(b._set)
        end,
        emit = function()
            local base = spellName(b.cast)
            return {
                icon = select(3, GetSpellInfo(b.cast)),
                label = base, tip = L["Missing: %s"], tipArg = base,
                castName = base,
            }
        end,
    })
end

-- --- weapon enchant --------------------------------------------------------
local function slotWeaponKind(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if not link then return nil end
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    return equipLoc
end

local function offHandIsWeapon()
    local loc = slotWeaponKind(17)
    return loc ~= nil and loc ~= "INVTYPE_SHIELD" and loc ~= "INVTYPE_HOLDABLE"
end

-- Only the has/expiry returns are read. The enchant id is deliberately ignored:
-- the reminder does not care WHICH enchant is on there, only whether one is.
local function weaponEnchant(hand)
    if not GetWeaponEnchantInfo then return true, nil end
    local hasMH, mhLeft, _, _, hasOH, ohLeft = GetWeaponEnchantInfo()
    if hand == "off" then
        return hasOH and true or false, ohLeft and (ohLeft / 1000) or nil
    end
    return hasMH and true or false, mhLeft and (mhLeft / 1000) or nil
end

local WEAPON_CLASSES = { ROGUE = true, SHAMAN = true }

for _, hand in ipairs({ "main", "off" }) do
    rule({
        key = "weapon_" .. hand,
        cat = "catWeapon",
        priority = 60,
        test = function(ctx)
            if not WEAPON_CLASSES[ctx.class] then return false end
            if hand == "off" then
                if not offHandIsWeapon() then return false end
            elseif not slotWeaponKind(16) then
                return false
            end
            local has, left = weaponEnchant(hand)
            if not has then return true end
            local soon = mod.db.expireSoon or 0
            return soon > 0 and left ~= nil and left < soon
        end,
        emit = function()
            local has = weaponEnchant(hand)
            local which = (hand == "off") and L["Off hand"] or L["Main hand"]
            return {
                icon = GetInventoryItemTexture("player", hand == "off" and 17 or 16),
                label = which,
                tip = has and L["Weapon enchant running out: %s"] or L["No weapon enchant: %s"],
                tipArg = which,
            }
        end,
    })
end

-- --- stance / aura ---------------------------------------------------------
-- GetShapeshiftFormInfo returns icon, isActive, isCastable on this client -
-- there is no name in the tuple, and reading slot 3 as "active" silently gets
-- isCastable, which is true for every stance you know.
local function anyFormActive()
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    if n == 0 then return true end
    for i = 1, n do
        local _, isActive = GetShapeshiftFormInfo(i)
        if isActive then return true end
    end
    return false
end

rule({
    key = "stance",
    cat = "catStance",
    priority = 80,
    class = "WARRIOR",
    test = function() return not anyFormActive() end,
    emit = function()
        return { icon = select(1, GetShapeshiftFormInfo(1)), label = L["Stance"], tip = L["No stance active"] }
    end,
})

local PALADIN_AURAS = { 465, 7294, 19746, 19891, 19888, 19876, 32223 }
rule({
    key = "aura",
    cat = "catStance",
    priority = 75,
    class = "PALADIN",
    test = function()
        mod._auraSet = mod._auraSet or nameSet(PALADIN_AURAS)
        return not haveAnyAura(mod._auraSet)
    end,
    emit = function()
        return { icon = select(3, GetSpellInfo(465)), label = L["Aura"], tip = L["No aura active"] }
    end,
})

-- --- pet -------------------------------------------------------------------
local PET_CLASSES = { HUNTER = true, WARLOCK = true }

rule({
    key = "pet_missing",
    cat = "catPet",
    priority = 85,
    test = function(ctx)
        if not PET_CLASSES[ctx.class] then return false end
        return not (UnitExists("pet") and not UnitIsDead("pet"))
    end,
    emit = function()
        return { icon = "Interface\\Icons\\Ability_Hunter_BeastCall", label = L["Pet"], tip = L["No pet out"] }
    end,
})

rule({
    key = "pet_passive",
    cat = "catPet",
    priority = 50,
    test = function(ctx)
        if not PET_CLASSES[ctx.class] then return false end
        if not UnitExists("pet") or UnitIsDead("pet") then return false end
        if IsMounted and IsMounted() then return false end   -- mounting forces passive
        if not GetPetActionInfo then return false end
        for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
            -- name, texture, isToken, isActive, ...  -- isActive is the 4th
            local name, _, _, isActive = GetPetActionInfo(i)
            if name == "PET_MODE_PASSIVE" and isActive then return true end
        end
        return false
    end,
    emit = function()
        return { icon = "Interface\\Icons\\Ability_Hunter_Pet_Bear", label = L["Passive"], tip = L["Pet is set to passive"] }
    end,
})

-- --- food / flask ----------------------------------------------------------
-- Every food in the game grants the same Well Fed icon, so one file id covers
-- all of them and keeps working in any language. UnitBuff hands back a file id
-- here, not a path, which is why this is a number compare.
local FOOD_ICON_ID = 136000

local function wellFedExpiry()
    for name in pairs(auraNames) do
        if auraIcons[name] == FOOD_ICON_ID then return true, auraExpiry[name] end
    end
    return false
end

rule({
    key = "food",
    cat = "catFood",
    priority = 30,
    test = function()
        local have, exp = wellFedExpiry()
        if not have then return true end
        local soon = mod.db.expireSoon or 0
        if soon <= 0 or not exp or exp == 0 then return false end
        return (exp - GetTime()) < soon
    end,
    emit = function()
        return { icon = "Interface\\Icons\\Spell_Misc_Food", label = L["Food"], tip = L["Not well fed"] }
    end,
})

local FLASK_IDS = {
    17626, 17627, 17628, 17629, 17630, 17631,
    28518, 28519, 28520, 28521, 28540,
    28497, 28501, 28502, 28503, 28509,
}
rule({
    key = "flask",
    cat = "catFood",
    priority = 28,
    test = function()
        mod._flaskSet = mod._flaskSet or nameSet(FLASK_IDS)
        return lacking(mod._flaskSet)
    end,
    emit = function()
        return { icon = "Interface\\Icons\\INV_Potion_97", label = L["Flask"], tip = L["No flask or elixir"] }
    end,
})

-- --- gear ------------------------------------------------------------------
-- Thrown weapons ARE the projectile and leave the ammo slot empty, so gating on
-- "has something in the ranged slot" alone would nag every Rogue forever.
local AMMO_LOC = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }

rule({
    key = "ammo",
    cat = "catGear",
    priority = 90,
    test = function()
        local loc = slotWeaponKind(18)
        if not (loc and AMMO_LOC[loc]) then return false end
        local n = GetInventoryItemCount and GetInventoryItemCount("player", 0) or 0
        return n < (mod.db.ammoLow or 200)
    end,
    emit = function()
        local n = GetInventoryItemCount and GetInventoryItemCount("player", 0) or 0
        return {
            icon = GetInventoryItemTexture("player", 0) or "Interface\\Icons\\INV_Ammo_Arrow_02",
            label = tostring(n), tip = L["Low ammo: %d left"], tipArg = n,
        }
    end,
})

local DURABILITY_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
local function worstDurability()
    if not GetInventoryItemDurability then return nil end
    local worst, slot
    for _, s in ipairs(DURABILITY_SLOTS) do
        local cur, max = GetInventoryItemDurability(s)
        if cur and max and max > 0 then
            local f = cur / max
            if not worst or f < worst then worst, slot = f, s end
        end
    end
    return worst, slot
end

rule({
    key = "durability",
    cat = "catGear",
    priority = 65,
    test = function()
        local worst = worstDurability()
        return worst ~= nil and worst < ((mod.db.durabilityPct or 25) / 100)
    end,
    emit = function()
        local worst, slot = worstDurability()
        local pct = floor((worst or 0) * 100)
        return {
            icon = (slot and GetInventoryItemTexture("player", slot)) or "Interface\\Icons\\Ability_Repair",
            label = pct .. "%", tip = L["Equipment damaged: %d%% left"], tipArg = pct,
        }
    end,
})

-- Only slots that are never legitimately empty on a played character. Rings,
-- trinkets, neck and cloak are deliberately absent: they are routinely open
-- while levelling and would keep this permanently lit.
local EQUIP_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16 }
local function emptySlotCount()
    local n = 0
    for _, s in ipairs(EQUIP_SLOTS) do
        if not GetInventoryItemID("player", s) then n = n + 1 end
    end
    return n
end

rule({
    key = "empty_slot",
    cat = "catGear",
    priority = 55,
    test = function()
        if not mod.db.ruleEmptySlots then return false end
        return emptySlotCount() > 0
    end,
    emit = function()
        local n = emptySlotCount()
        return {
            icon = "Interface\\Icons\\INV_Misc_Bag_08", label = tostring(n),
            tip = L["Empty equipment slots: %d"], tipArg = n,
        }
    end,
})

rule({
    key = "talent_points",
    cat = "catGear",
    priority = 95,
    test = function()
        return (UnitCharacterPoints and UnitCharacterPoints("player") or 0) > 0
    end,
    emit = function()
        local p = UnitCharacterPoints("player") or 0
        return {
            icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", label = tostring(p),
            tip = L["Unspent talent points: %d"], tipArg = p,
        }
    end,
})

-- ---------------------------------------------------------------------------
-- Display

local anchor, icons, overflow = nil, {}, nil
local POOL_SIZE = 8

local function ensureAnchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", "VCUIReminders", UIParent)
    anchor:SetSize(1, 1)
    anchor:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 200)
    if ns.CreateMover then
        ns:CreateMover(anchor, {
            key = "reminders", label = L["Reminders"], db = mod.db,
            width = 180, height = 44, scalable = true,
        })
    end
    return anchor
end

local function makeIcon(i)
    local f = CreateFrame("Button", "VCUIReminder" .. i, ensureAnchor(), "SecureActionButtonTemplate")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(0, 0, 0, 0.85)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -1)
    f:EnableMouse(true)
    -- The icons are clickable but say nothing about what they want without this.
    f:SetScript("OnEnter", function(self)
        if not self._tipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self._tipText, 1, 0.82, 0.25, 1, true)
        if self._tipHint then GameTooltip:AddLine(self._tipHint, 0.7, 0.7, 0.75, true) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    icons[i] = f
    return f
end

-- The whole pool is built up front, out of combat, so no secure button is ever
-- created while locked down.
local function ensurePool()
    if InCombatLockdown() then return end
    for i = 1, POOL_SIZE do
        if not icons[i] then makeIcon(i) end
    end
end

local function ensureOverflow()
    if overflow then return overflow end
    overflow = ensureAnchor():CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overflow:Hide()
    return overflow
end

-- Every caller checked for combat before getting here except module shutdown,
-- which is the one case where nothing is left running to catch up afterwards:
-- the ticker is cancelled and the events are unregistered one statement earlier,
-- so a blocked Hide() would leave the row on screen until /reload. The guard
-- lives here so it covers every caller, and it leaves one handler behind to
-- finish the job the moment combat ends.
local hideWhenSafe

local function hideAll()
    if InCombatLockdown() then
        ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", hideWhenSafe)
        return
    end
    for _, f in ipairs(icons) do f:Hide() end
    if overflow then overflow:Hide() end
end

function hideWhenSafe()
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED", hideWhenSafe)
    hideAll()
end

local function layout(list, extra)
    local d = mod.db
    local sz = d.iconSize or 36
    local gap = d.spacing or 6
    local n = #list
    local total = n * sz + (n - 1) * gap
    for i, e in ipairs(list) do
        local f = icons[i]
        if not f then break end
        local wasShown = f:IsShown()
        f:SetSize(sz, sz)
        if ns.UI and ns.UI.Font then ns.UI.Font(f.label, d.fontSize or 11, "OUTLINE") end
        f.label:SetShown(d.showLabel ~= false)
        f:ClearAllPoints()
        f:SetPoint("LEFT", anchor, "CENTER", -total / 2 + (i - 1) * (sz + gap), 0)
        f.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        f.label:SetText(e.label or "")
        f._tipText = e.tipText
        f._tipHint = e.castName and L["Click to cast."] or nil
        if e.castName then
            f:SetAttribute("type", "spell")
            f:SetAttribute("spell", e.castName)
        else
            f:SetAttribute("type", nil)
            f:SetAttribute("spell", nil)
        end
        f:Show()
        -- fade only on the way in; re-fading something already on screen every
        -- refresh is what makes a reminder row look broken
        if not wasShown and UIFrameFadeIn then
            UIFrameFadeIn(f, d.fadeTime or 0.15, 0, 1)
        else
            f:SetAlpha(1)
        end
    end
    for i = n + 1, #icons do icons[i]:Hide() end

    if extra > 0 and n > 0 then
        local o = ensureOverflow()
        if ns.UI and ns.UI.Font then ns.UI.Font(o, (d.fontSize or 11) + 2, "OUTLINE") end
        o:ClearAllPoints()
        o:SetPoint("LEFT", icons[n], "RIGHT", gap, 0)
        o:SetFormattedText("+%d", extra)
        o:SetTextColor(1, 0.82, 0.25)
        o:Show()
    elseif overflow then
        overflow:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Evaluation

local pending, dirty = {}, false
local EAT_DRINK_IDS = { 433, 430 }   -- the Food and Drink channel auras

local function suppressed()
    local d = mod.db
    if UnitIsDeadOrGhost("player") then return true end
    if d.quietResting and IsResting and IsResting() then return true end
    if d.onlyInGroup and GetNumGroupMembers and (GetNumGroupMembers() or 0) == 0 then return true end
    if d.quietEating then
        mod._eatSet = mod._eatSet or nameSet(EAT_DRINK_IDS)
        -- already fixing it; piling a reminder on top is just noise
        if haveAnyAura(mod._eatSet) then return true end
    end
    return false
end

local function evaluate()
    if not mod._enabled then hideAll(); return end
    -- Secure buttons cannot be moved, shown or hidden while locked down, so the
    -- row simply holds still and catches up on leaving combat.
    if InCombatLockdown() then dirty = true; return end
    dirty = false
    ensurePool()

    scanPlayerAuras()
    if suppressed() then hideAll(); return end

    local ctx = { class = select(2, UnitClass("player")) }
    local now, hits = GetTime(), {}

    for _, r in ipairs(RULES) do
        local on = mod.db[r.cat] ~= false
        local classOk = (not r.class) or r.class == ctx.class
        local bad = false
        if on and classOk then
            local ok, res = pcall(r.test, ctx)
            bad = (ok and res) and true or false
        end
        if bad then
            -- a problem must persist before it earns a slot, so nothing flickers
            -- in the gap between two casts
            pending[r.key] = pending[r.key] or now
            if now - pending[r.key] >= (mod.db.settle or 0) then
                local ok, e = pcall(r.emit, ctx)
                if ok and e then
                    e.priority = r.priority or 0
                    e.tipText = e.tipArg ~= nil and string.format(e.tip or "%s", e.tipArg) or (e.tip or "")
                    hits[#hits + 1] = e
                end
            end
        else
            pending[r.key] = nil
        end
    end

    if #hits == 0 then hideAll(); return end
    table.sort(hits, function(a, b) return a.priority > b.priority end)

    local cap = math.min(mod.db.maxIcons or 4, POOL_SIZE)
    local shown, extra = hits, 0
    if #hits > cap then
        shown = {}
        for i = 1, cap do shown[i] = hits[i] end
        extra = #hits - cap
    end
    layout(shown, extra)
end

local queued = false
local function requestRefresh()
    if queued then return end
    queued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function() queued = false; evaluate() end)
    else
        queued = false
        evaluate()
    end
end
mod.RequestRefresh = requestRefresh

-- Named handlers, so OnDisable can actually take them off again; anonymous
-- closures would pile up one set per enable.
local function onPlayerUnit(_, unit) if unit == "player" then requestRefresh() end end
local function onSpellsChanged()
    wipe(nameCache)          -- ranks and names can change on learning a spell
    mod._auraSet, mod._flaskSet, mod._eatSet = nil, nil, nil
    for _, b in ipairs(CLASS_BUFFS) do b._set = nil end
    requestRefresh()
end
local function onRegenEnabled() if dirty then requestRefresh() end; ensurePool(); requestRefresh() end

local EVENTS = {
    PLAYER_ENTERING_WORLD    = requestRefresh,
    PLAYER_REGEN_ENABLED     = onRegenEnabled,
    UNIT_AURA                = onPlayerUnit,
    UNIT_INVENTORY_CHANGED   = onPlayerUnit,
    UNIT_PET                 = requestRefresh,
    PET_BAR_UPDATE           = requestRefresh,
    SPELLS_CHANGED           = onSpellsChanged,
    CHARACTER_POINTS_CHANGED = requestRefresh,
    BAG_UPDATE_DELAYED       = requestRefresh,
    UPDATE_INVENTORY_DURABILITY = requestRefresh,
}

-- Weapon enchants have no event on this client, so the only way to notice one
-- running out is to look.
local ticker

function mod:OnEnable()
    ensureAnchor()
    ensurePool()
    for ev, fn in pairs(EVENTS) do ns:RegisterEvent(ev, fn) end
    if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(2, requestRefresh) end
    requestRefresh()
end

function mod:OnDisable()
    if ticker then ticker:Cancel(); ticker = nil end
    for ev, fn in pairs(EVENTS) do ns:UnregisterEvent(ev, fn) end
    hideAll()
end

-- ---------------------------------------------------------------------------
-- Options

local CATEGORY_ORDER = {
    { "catBuffs",  "Class buffs" },
    { "catWeapon", "Weapon enchants" },
    { "catStance", "Stance and aura" },
    { "catPet",    "Pet" },
    { "catFood",   "Food and flask" },
    { "catGear",   "Ammo, durability, gear, talents" },
}

function mod:GetOptions()
    local items = {
        { type = "desc", text = L["|cffaaaaaaShows a short row of icons for what you are missing right now. Out of combat a click casts or uses the fix; hovering explains what it wants. The row holds still during combat.|r"] },
        { type = "header", text = L["What to watch"] },
    }
    for _, c in ipairs(CATEGORY_ORDER) do
        local key = c[1]
        items[#items + 1] = { type = "checkbox", label = L[c[2]],
            get = function() return mod.db[key] ~= false end,
            set = function(_, v) mod.db[key] = v; requestRefresh() end }
    end
    items[#items + 1] = { type = "checkbox", label = L["Also warn about empty equipment slots"],
        tooltip = L["Off by default: a ring, trinket or cloak is often legitimately empty while levelling."],
        get = function() return mod.db.ruleEmptySlots end,
        set = function(_, v) mod.db.ruleEmptySlots = v; requestRefresh() end }

    items[#items + 1] = { type = "header", text = L["Appearance"] }
    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "slider", label = L["Icon size"], min = 20, max = 64, step = 1,
          get = function() return mod.db.iconSize end,
          set = function(_, v) mod.db.iconSize = v; requestRefresh() end },
        { type = "slider", label = L["Icon spacing"], min = 0, max = 20, step = 1,
          get = function() return mod.db.spacing end,
          set = function(_, v) mod.db.spacing = v; requestRefresh() end },
    } }
    items[#items + 1] = { type = "slider", label = L["Fade-in time"], min = 0, max = 1, step = 0.05,
        tooltip = L["How long an icon takes to appear. 0 makes it show instantly."],
        get = function() return mod.db.fadeTime or 0.15 end,
        set = function(_, v) mod.db.fadeTime = v end }
    items[#items + 1] = { type = "slider", label = L["Most icons at once"], min = 1, max = 8, step = 1,
        tooltip = L["Anything past this is bundled into a single counter instead of adding another icon."],
        get = function() return mod.db.maxIcons end,
        set = function(_, v) mod.db.maxIcons = v; requestRefresh() end }
    items[#items + 1] = { type = "checkbox", label = L["Show labels"],
        get = function() return mod.db.showLabel ~= false end,
        set = function(_, v) mod.db.showLabel = v; requestRefresh() end }

    items[#items + 1] = { type = "header", text = L["Behaviour"] }
    items[#items + 1] = { type = "slider", label = L["Settle time (seconds)"], min = 0, max = 10, step = 0.5,
        tooltip = L["How long something must stay missing before an icon appears. Stops it flickering between casts."],
        get = function() return mod.db.settle end,
        set = function(_, v) mod.db.settle = v end }
    items[#items + 1] = { type = "slider", label = L["Warn when under (seconds)"], min = 0, max = 1800, step = 30,
        tooltip = L["Also warn while a buff or weapon enchant is about to run out. 0 = only warn when it is gone."],
        get = function() return mod.db.expireSoon end,
        set = function(_, v) mod.db.expireSoon = v; requestRefresh() end }
    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "slider", label = L["Durability below (%)"], min = 5, max = 90, step = 5,
          get = function() return mod.db.durabilityPct end,
          set = function(_, v) mod.db.durabilityPct = v; requestRefresh() end },
        { type = "slider", label = L["Ammo below"], min = 0, max = 1000, step = 50,
          get = function() return mod.db.ammoLow end,
          set = function(_, v) mod.db.ammoLow = v; requestRefresh() end },
    } }
    items[#items + 1] = { type = "checkbox", label = L["Quiet while resting"],
        tooltip = L["No reminders in a city or inn."],
        get = function() return mod.db.quietResting ~= false end,
        set = function(_, v) mod.db.quietResting = v; requestRefresh() end }
    items[#items + 1] = { type = "checkbox", label = L["Quiet while eating or drinking"],
        get = function() return mod.db.quietEating ~= false end,
        set = function(_, v) mod.db.quietEating = v; requestRefresh() end }
    items[#items + 1] = { type = "checkbox", label = L["Only in a group"],
        get = function() return mod.db.onlyInGroup end,
        set = function(_, v) mod.db.onlyInGroup = v; requestRefresh() end }

    return items
end
