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
    -- Strict grid: without it, the last checkbox of each run sat alone on the
    -- page's full width with its switch far right of its label (user report,
    -- 31.07.2026 -- three such rows on this one page). On the grid a lone row
    -- keeps its half and leaves the other empty.
    optionsGrid = true,
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

        -- One source of truth with the unified edit mode: the mover applies
        -- db.scale on its own (scalable), the slider writes the same key.
        scale     = 1.0,
        opacity   = 1.0,
        strata    = "MEDIUM",
        glow      = "none",   -- "none" | "pulse" | "solid"

        -- Per-rule switches UNDER the category switches: absent/true = on,
        -- false = off. A table default deep-merges, so saved falses survive
        -- ApplyDefaults and the profile strip keeps them (non-default values).
        rules     = {},

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

        -- Group scan: class buffs YOU could cast, checked on party/raid
        -- members. Off by default -- it reads every member's auras.
        othersMissing  = false,
        -- Context thresholds in MINUTES; 0 falls back to expireSoon. Raid
        -- groups count anywhere, dungeon groups only inside the instance.
        raidSoonMin    = 0,
        dungeonSoonMin = 0,
        -- What a click on the food/flask/weapon reminder uses: "auto" picks
        -- the highest-level matching consumable in the bags, a number is a
        -- pinned item id.
        preferred_food   = "auto",
        preferred_flask  = "auto",
        preferred_weapon = "auto",
        -- Small display-only copies of the current reminders at the mouse.
        cursorAttach   = false,
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

local auraNames, auraIcons, auraExpiry, auraDuration = {}, {}, {}, {}
local function scanPlayerAuras()
    wipe(auraNames); wipe(auraIcons); wipe(auraExpiry); wipe(auraDuration)
    for i = 1, 40 do
        -- name, icon, count, debuffType, duration, expirationTime
        local name, icon, _, _, dur, expires = UnitBuff("player", i)
        if not name then break end
        auraNames[name] = true
        auraIcons[name] = icon
        auraExpiry[name] = expires or 0
        auraDuration[name] = dur or 0
    end
end

local function haveAnyAura(set)
    if not set then return false end
    for n in pairs(set) do
        if auraNames[n] then return true, auraExpiry[n], auraDuration[n] end
    end
    return false
end

-- The "running out" threshold for RIGHT NOW: raid groups get their own
-- minutes anywhere, dungeon groups theirs inside the instance, everything
-- else the global seconds. 0 in a context slider means "no override here".
local function effectiveSoon()
    local d = mod.db
    local m
    if IsInRaid and IsInRaid() then
        m = d.raidSoonMin
    elseif IsInGroup and IsInGroup() and select(2, IsInInstance()) == "party" then
        m = d.dungeonSoonMin
    end
    if m and m > 0 then return m * 60 end
    return d.expireSoon or 0
end

-- Is a buff missing, or close enough to gone to be worth saying so?
local function lacking(set)
    local have, exp, dur = haveAnyAura(set)
    if not have then return true end
    local soon = effectiveSoon()
    if soon <= 0 or not exp or exp == 0 then return false end
    -- A buff whose FULL duration is not LONGER than the threshold would nag
    -- from the moment it lands (Battle Shout is two minutes; a 5-minute
    -- threshold never stopped warning about it). <=, not <: at exactly equal
    -- the warning would also be permanent by construction.
    if dur and dur > 0 and dur <= soon then return false end
    return (exp - GetTime()) < soon
end

-- GetSpellInfo(name) answers "is this in my spellbook" in one call. Walking the
-- book instead cost ~200 pcalls per rule per refresh for the same answer.
local function knowsSpell(baseName)
    if not baseName then return false end
    local ok, res = pcall(GetSpellInfo, baseName)
    return ok and res ~= nil
end

-- --- group scan ------------------------------------------------------------
-- Someone in the group lacks a buff the player could cast. Read per member,
-- so it runs only behind the othersMissing switch; the player is skipped --
-- the own-aura check above already owns that case.

local function unitLacksSet(unit, set)
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then return true end
        if set[name] then return false end
    end
    return true
end

local function someoneMissing(b)
    if not b._set then return nil end
    local prefix, n
    if IsInRaid() then
        prefix, n = "raid", GetNumGroupMembers() or 0
    else
        prefix, n = "party", (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
    end
    for i = 1, n do
        local u = prefix .. i
        if UnitExists(u) and not UnitIsUnit(u, "player")
           and not UnitIsDeadOrGhost(u) and UnitIsConnected(u)
           and UnitIsVisible(u)
           and not (b.manaOnly and UnitPowerType(u) ~= 0)
           and unitLacksSet(u, b._set) then
            return u, UnitName(u)
        end
    end
    return nil
end

-- --- bag consumables -------------------------------------------------------
-- What a click on the food/flask/weapon reminder uses. Classified by the
-- item data's consumable subclasses (2 elixir, 3 flask, 5 food and drink,
-- 6 weapon enhancement), which this client's modern item database carries.

local GetCSlots  = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetCItemID = C_Container and C_Container.GetContainerItemID  or GetContainerItemID

local PREF_SUBS = { food = { 5 }, flask = { 2, 3 }, weapon = { 6 } }

local function scanConsumables(kind)
    local subs, out = PREF_SUBS[kind], {}
    if not (subs and GetItemInfoInstant and GetCSlots and GetCItemID) then return out end
    for bag = 0, 4 do
        for slot = 1, GetCSlots(bag) or 0 do
            local id = GetCItemID(bag, slot)
            if id and not out[id] then
                local _, _, _, _, _, classID, subID = GetItemInfoInstant(id)
                if classID == 0 and (subID == subs[1] or subID == subs[2]) then
                    out[id] = true
                    out[#out + 1] = id
                end
            end
        end
    end
    return out
end

-- "auto" = the highest-level matching consumable carried right now; a pinned
-- id only counts while it is actually in the bags.
local function preferredItem(kind)
    local pref = mod.db["preferred_" .. kind]
    if type(pref) == "number" and (GetItemCount(pref) or 0) > 0 then return pref end
    local best, bestLvl
    for _, id in ipairs(scanConsumables(kind)) do
        local _, _, _, ilvl = GetItemInfo(id)
        ilvl = ilvl or 0
        if not best or ilvl > bestLvl then best, bestLvl = id, ilvl end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Rules. A rule is data: key, category, priority, an optional class gate, a
-- test that reports whether something is missing, and what to show for it.

local RULES = {}
local function rule(t) RULES[#RULES + 1] = t end

-- `ids` lists one representative id per variant that satisfies the need, so the
-- greater version counts too: casting Prayer of Fortitude must not leave a
-- "you forgot Fortitude" reminder standing.
-- `others` marks the buffs worth scanning the GROUP for (whole-group blessings;
-- Thorns is a picked target and Battle Shout lands on the warrior too, so the
-- own-aura check covers it). `manaOnly` skips members the buff does nothing
-- for -- rage and energy users need no Intellect.
local CLASS_BUFFS = {
    { key = "fortitude", class = "PRIEST",  cast = 1243,  ids = { 1243, 21562 }, others = true },
    { key = "spirit",    class = "PRIEST",  cast = 14752, ids = { 14752, 27681 }, others = true, manaOnly = true },
    { key = "intellect", class = "MAGE",    cast = 1459,  ids = { 1459, 23028 }, others = true, manaOnly = true },
    { key = "wild",      class = "DRUID",   cast = 1126,  ids = { 1126, 21849 }, others = true },
    { key = "thorns",    class = "DRUID",   cast = 467,   ids = { 467 } },
    { key = "shout",     class = "WARRIOR", cast = 6673,  ids = { 6673 } },
}

for _, b in ipairs(CLASS_BUFFS) do
    rule({
        key = "buff_" .. b.key,
        cat = "catBuffs",
        priority = 70,
        class = b.class,
        -- optLabel/optClass feed the per-rule checkbox behind the category's
        -- gear and the options-page preview. A FUNCTION, not a value: rules
        -- are declared at file load, long before spell data and the saved
        -- locale are readable.
        optClass = b.class,
        optLabel = function() return spellName(b.cast) or b.key end,
        test = function()
            local base = spellName(b.cast)
            if not (base and knowsSpell(base)) then return false end
            b._set = b._set or nameSet(b.ids)
            b._otherUnit, b._other = nil, nil
            if lacking(b._set) then return true end
            if b.others and mod.db.othersMissing and IsInGroup and IsInGroup() then
                b._otherUnit, b._other = someoneMissing(b)
                return b._otherUnit ~= nil
            end
            return false
        end,
        emit = function()
            local base = spellName(b.cast)
            local e = {
                icon = select(3, GetSpellInfo(b.cast)),
                label = base, tip = L["Missing: %s"], tipArg = base,
                castName = base,
            }
            -- The unit rides into the secure unit attribute. "player" in the
            -- own case, NOT default targeting: with a friendly player
            -- targeted the click would buff the target and the reminder
            -- would stay lit.
            e.castUnit = "player"
            if b._otherUnit then
                -- Pre-formatted: the tip/tipArg channel carries one value and
                -- this one needs member AND spell.
                e.tip, e.tipArg = string.format(L["Missing on %s: %s"], b._other or "?", base), nil
                e.castUnit = b._otherUnit
            end
            return e
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

-- Largest remaining enchant time seen per hand, as a duration estimate;
-- reset when the hand has no enchant so a fresh application re-learns.
local weaponMaxLeft = { main = 0, off = 0 }

for _, hand in ipairs({ "main", "off" }) do
    rule({
        key = "weapon_" .. hand,
        cat = "catWeapon",
        priority = 60,
        optGate  = WEAPON_CLASSES,
        optLabel = function() return (hand == "off") and L["Off hand"] or L["Main hand"] end,
        optShow  = function()
            if hand == "off" then return offHandIsWeapon() end
            return slotWeaponKind(16) ~= nil
        end,
        test = function(ctx)
            if not WEAPON_CLASSES[ctx.class] then return false end
            if hand == "off" then
                if not offHandIsWeapon() then return false end
            elseif not slotWeaponKind(16) then
                return false
            end
            local has, left = weaponEnchant(hand)
            if not has then weaponMaxLeft[hand] = 0; return true end
            if left and left > weaponMaxLeft[hand] then weaponMaxLeft[hand] = left end
            local soon = effectiveSoon()
            if soon <= 0 or not left then return false end
            -- The API gives no full duration, only remaining time; the
            -- largest remainder seen per hand since the last application is
            -- the estimate. Without it a context threshold >= the enchant's
            -- duration (30-minute imbue, 30-minute raid slider) nags from
            -- the moment the enchant lands. After a reload mid-enchant the
            -- estimate is low and costs that one cycle's early warning --
            -- the miss still warns, and that beats the permanent nag.
            if weaponMaxLeft[hand] > 0 and weaponMaxLeft[hand] <= soon then return false end
            return left < soon
        end,
        emit = function()
            local has = weaponEnchant(hand)
            local which = (hand == "off") and L["Off hand"] or L["Main hand"]
            return {
                icon = GetInventoryItemTexture("player", hand == "off" and 17 or 16),
                label = which,
                tip = has and L["Weapon enchant running out: %s"] or L["No weapon enchant: %s"],
                tipArg = which,
                -- a click uses the preferred oil/stone ON the weapon slot
                useItem = preferredItem("weapon"),
                targetSlot = (hand == "off") and 17 or 16,
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
    optClass = "WARRIOR",
    optLabel = function() return L["Stance"] end,
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
    optClass = "PALADIN",
    optLabel = function() return L["Aura"] end,
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
    optGate  = PET_CLASSES,
    optLabel = function() return L["No pet out"] end,
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
    optGate  = PET_CLASSES,
    optLabel = function() return L["Pet is set to passive"] end,
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
        if auraIcons[name] == FOOD_ICON_ID then
            return true, auraExpiry[name], auraDuration[name]
        end
    end
    return false
end

rule({
    key = "food",
    cat = "catFood",
    priority = 30,
    optLabel = function() return L["Food"] end,
    test = function()
        local have, exp, dur = wellFedExpiry()
        if not have then return true end
        local soon = effectiveSoon()
        if soon <= 0 or not exp or exp == 0 then return false end
        -- <= like lacking(): 30-minute food vs a 30-minute raid threshold
        -- must not warn while WELL FED is up
        if dur and dur > 0 and dur <= soon then return false end
        return (exp - GetTime()) < soon
    end,
    emit = function()
        return { icon = "Interface\\Icons\\Spell_Misc_Food", label = L["Food"], tip = L["Not well fed"],
                 useItem = preferredItem("food") }
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
    optLabel = function() return L["Flask"] end,
    test = function()
        mod._flaskSet = mod._flaskSet or nameSet(FLASK_IDS)
        return lacking(mod._flaskSet)
    end,
    emit = function()
        return { icon = "Interface\\Icons\\INV_Potion_97", label = L["Flask"], tip = L["No flask or elixir"],
                 useItem = preferredItem("flask") }
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
    optLabel = function() return L["Ammo"] end,
    optShow  = function()
        local loc = slotWeaponKind(18)
        return (loc and AMMO_LOC[loc]) and true or false
    end,
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
    optLabel = function() return L["Durability"] end,
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
    -- Bound to its OWN db key, not the rules table: the flag predates the
    -- per-rule switches and keeps every existing profile's choice.
    optDb    = "ruleEmptySlots",
    optLabel = function() return L["Also warn about empty equipment slots"] end,
    optTip   = function() return L["Off by default: a ring, trinket or cloak is often legitimately empty while levelling."] end,
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
    optLabel = function() return L["Talent points"] end,
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

-- Rules the player middle-clicked away. Session state, wiped on the next
-- loading screen -- the same lifetime the tooltip promises.
local dismissed = {}

-- Strata and opacity live on the anchor so every icon inherits both; the
-- mover applies db.scale on the same frame (scalable), so all three follow
-- one target.
local function applyAnchorLook()
    if not anchor then return end
    anchor:SetFrameStrata(mod.db.strata or "MEDIUM")
    anchor:SetAlpha(mod.db.opacity or 1)
    anchor:SetScale(mod.db.scale or 1)
end
mod.ApplyAnchorLook = applyAnchorLook

local function ensureAnchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", "VCUIReminders", UIParent)
    anchor:SetSize(1, 1)
    anchor:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 200)
    applyAnchorLook()
    if ns.CreateMover then
        ns:CreateMover(anchor, {
            key = "reminders", label = L["Reminders"], db = mod.db,
            width = 180, height = 44, scalable = true,
        })
    end
    return anchor
end

-- Accent ring behind the black border: 2px of colour all around, on the layer
-- below the border so the icon keeps its dark edge. Colour is read at paint
-- time -- the accent is live-mutated by the theme.
local function ensureGlow(f)
    if f.glow then return f.glow end
    local g = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    g:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
    g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    f.glow = g
    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.9)
    a:SetToAlpha(0.2)
    a:SetDuration(0.7)
    f.glowAnim = ag
    return g
end

local function applyGlow(f)
    local mode = mod.db.glow or "none"
    if mode == "none" then
        if f.glow then f.glowAnim:Stop(); f.glow:Hide() end
        return
    end
    local g = ensureGlow(f)
    local ac = ns.COLORS.accent
    g:SetColorTexture(ac.r, ac.g, ac.b, 1)
    g:Show()
    if mode == "pulse" then
        f.glowAnim:Play()
    else
        f.glowAnim:Stop()
        g:SetAlpha(0.85)
    end
end

-- --- cursor copies ----------------------------------------------------------
-- Small DISPLAY-ONLY duplicates of the current reminders trailing the mouse.
-- Plain frames, never secure: they need no clicks, and insecure frames may
-- show, hide and follow the cursor even in combat.
local cursorRow
local CURSOR_MAX, CURSOR_SIZE = 4, 18

local function ensureCursorRow()
    if cursorRow then return cursorRow end
    cursorRow = CreateFrame("Frame", nil, UIParent)
    cursorRow:SetFrameStrata("TOOLTIP")
    cursorRow:SetSize(1, 1)
    cursorRow.icons = {}
    cursorRow:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s - 26)
    end)
    return cursorRow
end

local function updateCursorRow(list)
    if not mod.db.cursorAttach or not list or #list == 0 then
        if cursorRow then cursorRow:Hide() end
        return
    end
    local row = ensureCursorRow()
    local n = math.min(#list, CURSOR_MAX)
    local total = n * CURSOR_SIZE + (n - 1) * 3
    for i = 1, n do
        local f = row.icons[i]
        if not f then
            f = CreateFrame("Frame", nil, row)
            f.icon = f:CreateTexture(nil, "ARTWORK")
            f.icon:SetAllPoints(f)
            f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            f.border = f:CreateTexture(nil, "BACKGROUND")
            f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
            f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
            f.border:SetColorTexture(0, 0, 0, 0.85)
            row.icons[i] = f
        end
        f:SetSize(CURSOR_SIZE, CURSOR_SIZE)
        f:ClearAllPoints()
        f:SetPoint("LEFT", row, "CENTER", -total / 2 + (i - 1) * (CURSOR_SIZE + 3), 0)
        f.icon:SetTexture(list[i].icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        f:Show()
    end
    for i = n + 1, #row.icons do row.icons[i]:Hide() end
    row:Show()
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
    -- The wildcard recipe this client needs (see the secure-handler notes):
    -- the action itself hangs on *type1/*spell1, so ONLY button 1 casts --
    -- the middle button reaches PostClick and nothing else. HookScript, never
    -- SetScript, on a secure button.
    f:RegisterForClicks("AnyUp", "AnyDown")
    f:HookScript("PostClick", function(self, btn)
        if btn == "MiddleButton" and self._ruleKey then
            dismissed[self._ruleKey] = true
            if mod.RequestRefresh then mod.RequestRefresh() end
        end
    end)
    -- The icons are clickable but say nothing about what they want without this.
    ns.UI:AttachTooltip(f, function(self)
        if not self or not self._tipText then return nil end
        local lines = {}
        if self._tipHint then lines[#lines + 1] = { self._tipHint, 0.7, 0.7, 0.75, true } end
        lines[#lines + 1] = { L["Middle-click: hide until the next loading screen."], 0.55, 0.55, 0.6, true }
        return { title = self._tipText, color = { 1, 0.82, 0.25 }, wrap = true, lines = lines }
    end)
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
    -- Before the combat gate: the cursor copies are insecure and may go
    -- regardless of lockdown.
    if cursorRow then cursorRow:Hide() end
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
        -- Capped at the cell the icon owns, ellipsis instead of running into
        -- the neighbour's label ("Mal der Wildnis" is three icons wide).
        f.label:SetWidth(sz + gap + 2)
        f.label:SetWordWrap(false)
        f.label:SetShown(d.showLabel ~= false)
        f:ClearAllPoints()
        f:SetPoint("LEFT", anchor, "CENTER", -total / 2 + (i - 1) * (sz + gap), 0)
        f.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        f.label:SetText(e.label or "")
        f._tipText = e.tipText
        f._tipHint = (e.castName and L["Click to cast."])
            or (e.useItem and L["Click to use."]) or nil
        f._ruleKey = e._ruleKey
        -- Three exclusive click shapes; every branch clears what the other
        -- two set, or a reused slot casts yesterday's action.
        if e.castName then
            f:SetAttribute("*type1", "spell")
            f:SetAttribute("*spell1", e.castName)
            f:SetAttribute("*unit1", e.castUnit)
            f:SetAttribute("*item1", nil)
            f:SetAttribute("*target-slot1", nil)
        elseif e.useItem then
            f:SetAttribute("*type1", "item")
            f:SetAttribute("*item1", "item:" .. e.useItem)
            f:SetAttribute("*target-slot1", e.targetSlot)
            f:SetAttribute("*spell1", nil)
            f:SetAttribute("*unit1", nil)
        else
            f:SetAttribute("*type1", nil)
            f:SetAttribute("*spell1", nil)
            f:SetAttribute("*unit1", nil)
            f:SetAttribute("*item1", nil)
            f:SetAttribute("*target-slot1", nil)
        end
        applyGlow(f)
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
    -- While the module's own options page is open the pinned preview shows the
    -- row instead; two copies of the same icons on screen read as a bug.
    if mod._optionsOpen then return true end
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
    -- The options-page preview rides the same refresh path, BEFORE any of the
    -- early returns: it must follow setting changes even while the module is
    -- off or the real row is suppressed.
    if mod.RefreshPreview then mod.RefreshPreview() end
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
        -- Category switch first, then the per-rule switch under it; a rule
        -- middle-clicked away stays quiet until the next loading screen.
        local on = mod.db[r.cat] ~= false and mod.db.rules[r.key] ~= false
            and not dismissed[r.key]
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
                    e._ruleKey = r.key
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
    updateCursorRow(shown)
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
-- Group members' auras matter only while the group scan is on; the debounce
-- in requestRefresh coalesces a raid's UNIT_AURA bursts.
local function onUnitAura(_, unit)
    if unit == "player" then requestRefresh(); return end
    if mod.db.othersMissing and type(unit) == "string"
       and (unit:find("^party%d+$") or unit:find("^raid%d+$")) then
        requestRefresh()
    end
end
local function onSpellsChanged()
    wipe(nameCache)          -- ranks and names can change on learning a spell
    mod._auraSet, mod._flaskSet, mod._eatSet = nil, nil, nil
    for _, b in ipairs(CLASS_BUFFS) do b._set = nil end
    requestRefresh()
end
local function onRegenEnabled() if dirty then requestRefresh() end; ensurePool(); requestRefresh() end

-- A loading screen ends every middle-click dismissal -- the lifetime the
-- tooltip promises.
local function onEnteringWorld()
    wipe(dismissed)
    requestRefresh()
end

local EVENTS = {
    PLAYER_ENTERING_WORLD    = onEnteringWorld,
    PLAYER_REGEN_ENABLED     = onRegenEnabled,
    UNIT_AURA                = onUnitAura,
    UNIT_INVENTORY_CHANGED   = onPlayerUnit,
    GROUP_ROSTER_UPDATE      = requestRefresh,
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
    applyAnchorLook()
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
-- Options-page live preview: the pinned header above the scroll area shows the
-- row as it is CONFIGURED -- every rule that applies to this character and is
-- switched on, whether or not it currently fires -- so a size, glow or label
-- change is visible while dragging the slider. A separate, insecure renderer,
-- never the real frame: the real row is a pool of secure cast buttons, and the
-- preview must be clickable-for-navigation, not clickable-for-casting. While
-- the preview is on screen the real row hides (see suppressed) -- the same
-- icons twice reads as a bug.

local preview

local function previewEntries()
    local class = select(2, UnitClass("player"))
    local ctx = { class = class }
    local out = {}
    for _, r in ipairs(RULES) do
        local show = mod.db[r.cat] ~= false
        if show then
            if r.optDb then show = mod.db[r.optDb] and true or false
            else show = mod.db.rules[r.key] ~= false end
        end
        if show and r.class and r.class ~= class then show = false end
        if show and r.optGate and not r.optGate[class] then show = false end
        if show and r.optShow then
            local ok, res = pcall(r.optShow)
            show = (ok and res) and true or false
        end
        if show then
            local ok, e = pcall(r.emit, ctx)
            if ok and e then
                e._rule = r
                e.tipText = e.tipArg ~= nil and string.format(e.tip or "%s", e.tipArg) or (e.tip or "")
                out[#out + 1] = e
            end
        end
    end
    return out
end

local function previewIcon(i)
    local f = preview.icons[i]
    if f then return f end
    f = CreateFrame("Button", nil, preview)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(0, 0, 0, 0.85)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -1)
    ns.UI:AttachTooltip(f, function(self)
        if not self._tipText then return nil end
        return { title = self._tipText, color = { 1, 0.82, 0.25 }, wrap = true,
                 lines = { { L["Click an icon to jump to its settings."], 0.7, 0.7, 0.75, true } } }
    end)
    f:SetScript("OnClick", function(self)
        local r = self._rule
        if not r then return end
        ns.UI:ExpandRow("cat/" .. r.cat)
        ns.UI:RebuildCurrentPage()
        ns.UI:ScrollToSection(L["What to watch"])
    end)
    preview.icons[i] = f
    return f
end

-- The scale slider multiplies the icon size here rather than SetScale on the
-- container: the height this page pins for the header must be plain pixels,
-- and labels stay readable at every scale.
local function previewIconSize()
    return floor((mod.db.iconSize or 36) * (mod.db.scale or 1) + 0.5)
end

local function previewHeight()
    local d = mod.db
    local h = previewIconSize() + 6
    if d.showLabel ~= false then h = h + (d.fontSize or 11) + 4 end
    return h + 16
end

local function refreshPreview()
    local d = mod.db
    local list = previewEntries()
    local sz   = previewIconSize()
    local gap  = d.spacing or 6
    local n    = #list
    local total = n * sz + math.max(0, n - 1) * gap
    for i, e in ipairs(list) do
        local f = previewIcon(i)
        f:SetSize(sz, sz)
        if ns.UI.Font then ns.UI.Font(f.label, d.fontSize or 11, "OUTLINE") end
        -- Same cap as the real row: the cell's width, then ellipsis.
        f.label:SetWidth(sz + gap + 2)
        f.label:SetWordWrap(false)
        f.label:SetShown(d.showLabel ~= false)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", preview, "TOP", -total / 2 + (i - 1) * (sz + gap), 0)
        f.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        f.label:SetText(e.label or "")
        f._tipText = e.tipText
        f._rule = e._rule
        f:SetAlpha(d.opacity or 1)
        applyGlow(f)
        f:Show()
    end
    for i = n + 1, #preview.icons do preview.icons[i]:Hide() end
    preview.hint:ClearAllPoints()
    preview.hint:SetPoint("BOTTOM", preview, "BOTTOM", 0, 2)
    preview.hint:SetText(n > 0 and L["Click an icon to jump to its settings."]
        or L["Nothing to preview: every reminder is switched off."])
    local h = previewHeight()
    preview._h = h
    preview:SetHeight(h)
    return h
end

function mod.BuildPageHeader(host)
    if not preview then
        preview = CreateFrame("Frame", nil, host)
        preview.icons = {}
        preview.hint = preview:CreateFontString(nil, "OVERLAY")
        if ns.UI.Font then ns.UI.Font(preview.hint, 10) end
        preview.hint:SetTextColor(0.55, 0.55, 0.62)
        -- The shared header host hides every child on a page switch and the
        -- whole window closes over it; both must hand the screen back to the
        -- real row.
        preview:SetScript("OnShow", function() mod._optionsOpen = true; requestRefresh() end)
        preview:SetScript("OnHide", function() mod._optionsOpen = false; requestRefresh() end)
    end
    preview:SetParent(host)
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", host, "TOPLEFT", 14, -4)
    preview:SetPoint("TOPRIGHT", host, "TOPRIGHT", -14, -4)
    preview:Show()
    -- Directly, not only via OnShow: on the FIRST build the frame is created
    -- already visible when the shared host is (arriving from another page
    -- that pins a header), so the OnShow edge never fires and the real row
    -- would keep painting behind the window.
    mod._optionsOpen = true
    requestRefresh()
    return refreshPreview() + 8
end

-- Ridden by evaluate() on every refresh: cheap repaint while the height holds,
-- full page rebuild when a slider changed it (the scroll area sits below the
-- pinned header and only a rebuild can move it). Same split the cooldown
-- manager's strip uses.
function mod.RefreshPreview()
    if not (preview and preview:IsVisible()) then return end
    if math.abs(previewHeight() - (preview._h or 0)) > 0.5 then
        ns.UI:RebuildCurrentPage()
    else
        refreshPreview()
    end
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
    -- Value lists per call, never at file load: the saved language override is
    -- only readable once SavedVariables are in.
    local GLOW_VALUES = {
        { value = "none",  text = L["None"] },
        { value = "pulse", text = L["Pulse"] },
        { value = "solid", text = L["Steady"] },
    }
    local STRATA_VALUES = {
        { value = "BACKGROUND", text = L["Background"] },
        { value = "LOW",        text = L["Low"] },
        { value = "MEDIUM",     text = L["Medium"] },
        { value = "HIGH",       text = L["High"] },
        { value = "DIALOG",     text = L["Dialog"] },
    }

    -- One pairable gear row per category, the per-rule switches behind the
    -- gear (they only matter while the category is on -- the suboptions
    -- criterion). Class-gated rules carry their class colour, the way a raid
    -- roster does, so the eye finds "mine" without reading.
    local byCat = {}
    for _, r in ipairs(RULES) do
        byCat[r.cat] = byCat[r.cat] or {}
        table.insert(byCat[r.cat], r)
    end

    local watch = {}
    for _, c in ipairs(CATEGORY_ORDER) do
        local catKey = c[1]
        local subs = {}
        for _, r in ipairs(byCat[catKey] or {}) do
            local label = (r.optLabel and r.optLabel()) or r.key
            if r.optClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.optClass] then
                local col = RAID_CLASS_COLORS[r.optClass]
                label = string.format("|cff%02x%02x%02x%s|r",
                    col.r * 255, col.g * 255, col.b * 255, label)
            end
            local ruleKey = r.key
            if r.optDb then
                local dbKey = r.optDb
                subs[#subs + 1] = { type = "checkbox", label = label,
                    tooltip = r.optTip and r.optTip() or nil,
                    get = function() return mod.db[dbKey] end,
                    set = function(_, v) mod.db[dbKey] = v; requestRefresh() end }
            else
                subs[#subs + 1] = { type = "checkbox", label = label,
                    -- ON is stored as ABSENT, so a profile only carries the
                    -- rules somebody switched off. An if, not and-or: with
                    -- false as the middle operand `x and false or nil` is nil
                    -- on BOTH branches.
                    get = function() return mod.db.rules[ruleKey] ~= false end,
                    set = function(_, v)
                        if v then mod.db.rules[ruleKey] = nil
                        else mod.db.rules[ruleKey] = false end
                        requestRefresh()
                    end }
            end
            -- A threshold sits directly under the rule it tunes.
            if ruleKey == "durability" then
                subs[#subs + 1] = { type = "slider", label = L["Durability below (%)"], min = 5, max = 90, step = 5,
                    get = function() return mod.db.durabilityPct end,
                    set = function(_, v) mod.db.durabilityPct = v; requestRefresh() end }
            elseif ruleKey == "ammo" then
                subs[#subs + 1] = { type = "slider", label = L["Ammo below"], min = 0, max = 1000, step = 50,
                    get = function() return mod.db.ammoLow end,
                    set = function(_, v) mod.db.ammoLow = v; requestRefresh() end }
            end
        end
        -- What a click on this category's reminder uses; the value list is
        -- read from the bags at page-build time.
        local function preferredRow(label, kind)
            local vals = { { value = "auto", text = L["Automatic (best in bags)"] } }
            for _, id in ipairs(scanConsumables(kind)) do
                local name = GetItemInfo(id)
                vals[#vals + 1] = { value = id, text = name or ("item:" .. id) }
            end
            return { type = "dropdown", label = label, values = vals,
                get = function() return mod.db["preferred_" .. kind] or "auto" end,
                set = function(_, v) mod.db["preferred_" .. kind] = v; requestRefresh() end }
        end
        if catKey == "catBuffs" then
            subs[#subs + 1] = { type = "toggle", label = L["Show effects missing on others"],
                tooltip = L["Scans your party or raid for class buffs you could cast and reminds you when someone lacks one."],
                get = function() return mod.db.othersMissing end,
                set = function(_, v) mod.db.othersMissing = v; requestRefresh() end }
        elseif catKey == "catFood" then
            subs[#subs + 1] = preferredRow(L["Preferred food"], "food")
            subs[#subs + 1] = preferredRow(L["Preferred flask or elixir"], "flask")
        elseif catKey == "catWeapon" then
            subs[#subs + 1] = preferredRow(L["Preferred weapon enhancement"], "weapon")
        end
        watch[#watch + 1] = { type = "toggle", label = L[c[2]],
            subKey = "cat/" .. catKey, pairable = true,
            get = function() return mod.db[catKey] ~= false end,
            set = function(_, v) mod.db[catKey] = v; requestRefresh() end,
            subOptions = subs }
    end

    return {
        { type = "desc", text = L["|cffaaaaaaShows a short row of icons for what you are missing right now. Out of combat a click casts or uses the fix; hovering explains what it wants. The row holds still during combat.|r"] },

        { type = "section", title = L["Core"], items = {
            { type = "slider", label = L["Scale"], min = 0.5, max = 2.0, step = 0.05,
              -- The same db.scale the unified edit mode scales the row by;
              -- the slider is just a second hand on the one clock.
              get = function() return mod.db.scale or 1 end,
              set = function(_, v) mod.db.scale = v; applyAnchorLook(); requestRefresh() end },
            { type = "slider", label = L["Most icons at once"], min = 1, max = 8, step = 1,
              tooltip = L["Anything past this is bundled into a single counter instead of adding another icon."],
              get = function() return mod.db.maxIcons end,
              set = function(_, v) mod.db.maxIcons = v; requestRefresh() end },
            { type = "slider", label = L["Fade-in time"], min = 0, max = 1, step = 0.05,
              tooltip = L["How long an icon takes to appear. 0 makes it show instantly."],
              get = function() return mod.db.fadeTime or 0.15 end,
              set = function(_, v) mod.db.fadeTime = v end },
        } },

        { type = "section", title = L["Appearance"], items = {
            { type = "slider", label = L["Icon size"], min = 20, max = 64, step = 1,
              get = function() return mod.db.iconSize end,
              set = function(_, v) mod.db.iconSize = v; requestRefresh() end },
            { type = "slider", label = L["Icon spacing"], min = 0, max = 20, step = 1,
              get = function() return mod.db.spacing end,
              set = function(_, v) mod.db.spacing = v; requestRefresh() end },
            { type = "slider", label = L["Opacity"], min = 0.2, max = 1.0, step = 0.05,
              get = function() return mod.db.opacity or 1 end,
              set = function(_, v) mod.db.opacity = v; applyAnchorLook(); requestRefresh() end },
            { type = "toggle", label = L["Show labels"],
              get = function() return mod.db.showLabel ~= false end,
              set = function(_, v) mod.db.showLabel = v; requestRefresh() end,
              subOptions = {
                  { type = "slider", label = L["Font size"], min = 8, max = 18, step = 1,
                    get = function() return mod.db.fontSize or 11 end,
                    set = function(_, v) mod.db.fontSize = v; requestRefresh() end },
              } },
            { type = "dropdown", label = L["Glow style"], values = GLOW_VALUES,
              get = function() return mod.db.glow or "none" end,
              set = function(_, v) mod.db.glow = v; requestRefresh() end },
            { type = "dropdown", label = L["Frame strata"], values = STRATA_VALUES,
              get = function() return mod.db.strata or "MEDIUM" end,
              set = function(_, v) mod.db.strata = v; applyAnchorLook() end },
            { type = "toggle", label = L["Attach reminders to the cursor"],
              tooltip = L["Shows small copies of the current reminders next to the mouse cursor."],
              get = function() return mod.db.cursorAttach end,
              set = function(_, v) mod.db.cursorAttach = v; requestRefresh() end },
        } },

        { type = "section", title = L["What to watch"], items = watch },

        { type = "section", title = L["Behaviour"], items = {
            { type = "slider", label = L["Settle time (seconds)"], min = 0, max = 10, step = 0.5,
              tooltip = L["How long something must stay missing before an icon appears. Stops it flickering between casts."],
              get = function() return mod.db.settle end,
              set = function(_, v) mod.db.settle = v end },
            { type = "slider", label = L["Warn when under (seconds)"], min = 0, max = 1800, step = 30,
              tooltip = L["Also warn while a buff or weapon enchant is about to run out. 0 = only warn when it is gone."],
              get = function() return mod.db.expireSoon end,
              set = function(_, v) mod.db.expireSoon = v; requestRefresh() end,
              subOptions = {
                  { type = "slider", label = L["In raids (minutes)"], min = 0, max = 30, step = 1,
                    tooltip = L["0 uses the global warn threshold."],
                    get = function() return mod.db.raidSoonMin or 0 end,
                    set = function(_, v) mod.db.raidSoonMin = v; requestRefresh() end },
                  { type = "slider", label = L["In dungeons (minutes)"], min = 0, max = 60, step = 1,
                    tooltip = L["0 uses the global warn threshold."],
                    get = function() return mod.db.dungeonSoonMin or 0 end,
                    set = function(_, v) mod.db.dungeonSoonMin = v; requestRefresh() end },
              } },
            { type = "checkbox", label = L["Quiet while resting"],
              tooltip = L["No reminders in a city or inn."],
              get = function() return mod.db.quietResting ~= false end,
              set = function(_, v) mod.db.quietResting = v; requestRefresh() end },
            { type = "checkbox", label = L["Quiet while eating or drinking"],
              get = function() return mod.db.quietEating ~= false end,
              set = function(_, v) mod.db.quietEating = v; requestRefresh() end },
            { type = "checkbox", label = L["Only in a group"],
              get = function() return mod.db.onlyInGroup end,
              set = function(_, v) mod.db.onlyInGroup = v; requestRefresh() end },
        } },
    }
end
