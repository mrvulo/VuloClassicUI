-- =========================================================
-- VuloClassicUI / Modules / BagSort — shared item-sorting engine
-- Used by Modules/Bags.lua + Modules/Bank.lua for
--   * the PHYSICAL sort (actually moving items into order), and
--   * the DISPLAY-ONLY ordering of items inside category sections.
--
-- Design:
--   * Every sort mode is an ordered list of item fields; the first field that
--     differs between two items decides. Descending criteria are expressed as
--     negated ("inverted") fields so the comparator only ever needs "<".
--     Complete ties fall back to a stable per-run index.
--   * Expensive fields (name, item level) are computed lazily via a metatable
--     and cached on the item for the current run. While the client hasn't
--     cached an item's data yet the field returns nil, the run is flagged
--     "incomplete", the data is requested from the server and the driver
--     simply re-runs shortly after — no freeze, no wrong order.
--   * The physical sort is a state machine: every step re-scans the bags
--     fresh, computes target slots (junk at the far end; special bags like
--     herb/soul/ammo bags filled first, preferring the items that fit into
--     the FEWEST special bags) and fires Pickup/Pickup swaps. Locked or
--     still-moving items just mean "try again next tick", so it converges
--     without ever assuming a move succeeded. Only PickupContainerItem +
--     ClearCursor are used — nothing protected, safe from a plain button
--     click, and it bails in combat.
--
-- Lua 5.1 caps a chunk at 200 locals, so (like Modules/Bank.lua) everything
-- lives inside the single `sorting` table below.
-- =========================================================
local _, ns = ...

-- Container API — the bare globals are guaranteed on every flavor we ship for
-- by Core/Compat.lua (GetContainerItemInfo returns the legacy 10-tuple).
local GetContainerNumSlots     = _G.GetContainerNumSlots
local GetContainerItemInfo     = _G.GetContainerItemInfo
local GetContainerNumFreeSlots = _G.GetContainerNumFreeSlots
local PickupContainerItem      = _G.PickupContainerItem
local CI = _G.C_Item or {}

local sorting = {}
ns.SortEngine = sorting

-- =========================================================
-- Small API shims — modern C_Item first, legacy globals second. GetItemInfo
-- (legacy) exists on 20505 + 11508 and doubles as the "request this item's
-- data from the server" trigger on clients without RequestLoadItemDataByID.
-- =========================================================
function sorting.isCached(itemID)
    if CI.IsItemDataCachedByID then return CI.IsItemDataCachedByID(itemID) end
    return GetItemInfo(itemID) ~= nil
end

function sorting.requestLoad(itemID)
    if CI.RequestLoadItemDataByID then CI.RequestLoadItemDataByID(itemID)
    else GetItemInfo(itemID) end
end

function sorting.nameOf(itemID)
    if CI.GetItemNameByID then return CI.GetItemNameByID(itemID) end
    return (GetItemInfo(itemID))
end

function sorting.levelOf(itemLink)
    local f = CI.GetDetailedItemLevelInfo or _G.GetDetailedItemLevelInfo
    if f then
        local ok, lvl = pcall(f, itemLink)
        if ok and lvl then return lvl end
    end
    return (select(4, GetItemInfo(itemLink)))
end

function sorting.invTypeOf(itemID)
    if CI.GetItemInventoryTypeByID then return CI.GetItemInventoryTypeByID(itemID) end
    return nil
end

sorting.getItemFamily = CI.GetItemFamily or _G.GetItemFamily
sorting.instantInfo   = CI.GetItemInfoInstant or _G.GetItemInfoInstant

-- =========================================================
-- Hand-tuned orderings for item class / subclass / equip slot, so "by type"
-- runs consumables -> weapons -> armor -> trade goods -> quest -> misc and
-- weapons/armor read in a sensible gear order. Anything not listed sorts
-- after the listed entries (raw id + 200).
-- =========================================================
sorting.rank = {
    classID = {
        18, -- token
        0,  -- consumable
        5,  -- reagent
        6,  -- projectile
        2,  -- weapon
        4,  -- armor
        11, -- quiver
        3,  -- gem
        8,  -- item enhancement
        16, -- glyph
        1,  -- container
        7,  -- trade goods
        19, -- profession
        9,  -- recipe
        10, -- money
        12, -- quest
        13, -- key
        14, -- permanent
        15, -- misc
        17, -- battle pet
    },
    weaponSub = {
        0,  -- 1h axe
        4,  -- 1h mace
        7,  -- 1h sword
        9,  -- warglaives
        15, -- dagger
        13, -- fist weapon
        11, -- bear claws
        12, -- cat claws
        19, -- wand
        1,  -- 2h axe
        5,  -- 2h mace
        8,  -- 2h sword
        6,  -- polearm
        10, -- staff
        2,  -- bow
        18, -- crossbow
        3,  -- gun
        16, -- thrown
        17, -- spear
        14, -- misc
        20, -- fishing pole
    },
    armorSub = {
        6,  -- shield
        7,  -- libram
        8,  -- idol
        9,  -- totem
        10, -- sigil
        11, -- relic
        4,  -- plate
        3,  -- mail
        2,  -- leather
        1,  -- cloth
        0,  -- generic
        5,  -- cosmetic
    },
    invSlot = {
        17, -- 2h weapon
        13, -- one-hand
        21, -- main hand
        14, -- shield
        23, -- held in off-hand
        26, -- ranged right
        22, -- off hand
        15, -- ranged
        25, -- thrown
        24, -- ammo
        27, -- quiver
        28, -- relic
        1,  -- head
        3,  -- shoulder
        16, -- back
        5,  -- chest
        20, -- robe
        9,  -- wrist
        10, -- hands
        6,  -- waist
        7,  -- legs
        8,  -- feet
        2,  -- neck
        11, -- finger
        12, -- trinket
        4,  -- shirt
        19, -- tabard
        29, -- profession tool
        30, -- profession gear
        18, -- bag
        0,  -- non-equippable
    },
    tradegoodsSub = {
        18, -- optional reagent
        1,  -- parts
        4,  -- jewelcrafting
        7,  -- metal & stone
        6,  -- leather
        5,  -- cloth
        12, -- enchanting
        16, -- inscription
        10, -- elemental
        9,  -- herb
        8,  -- cooking
        11, -- other
        0,  -- trade goods
        2,  -- explosives
        3,  -- devices
        13, -- materials
        14, -- item enchantment
        15, -- weapon enchantment
        17, -- explosives & devices
    },
}

-- fast lookup: rankMap.<key>[id] = position in the hand-tuned list
sorting.rankMap = {}
for key, list in pairs(sorting.rank) do
    local map = {}
    for index, id in ipairs(list) do map[id] = index end
    sorting.rankMap[key] = map
end

-- =========================================================
-- Lazy per-item sort fields. A field that needs uncached item data requests
-- the load and returns nil — the metatable does NOT cache nil, so the next
-- attempt recomputes it, and the comparator flags the run incomplete.
-- classID constants are fixed on every flavor: 2 weapon, 4 armor, 7 trade
-- goods (Enum.ItemClass matches these values where it exists).
-- =========================================================
sorting.fields = {}

sorting.fields.itemLevelRaw = function(item)
    if sorting.isCached(item.itemID) then
        return sorting.levelOf(item.itemLink) or -1
    end
    sorting.requestLoad(item.itemID)
end

sorting.fields.invertedItemLevelRaw = function(item)
    return item.itemLevelRaw and -item.itemLevelRaw
end

-- equipment sorts by its level (descending), everything else is a flat 0 so
-- gear floats to the front in "item level" mode
sorting.fields.invertedItemLevelEquipment = function(item)
    if item.isEquipment then
        return item.itemLevelRaw and -item.itemLevelRaw
    end
    return 0
end

sorting.fields.itemName = function(item)
    if sorting.isCached(item.itemID) then
        return sorting.nameOf(item.itemID) or ""
    end
    sorting.requestLoad(item.itemID)
end

sorting.fields.invertedQuality   = function(item) return -(item.quality or 0) end
sorting.fields.invertedItemID    = function(item) return -item.itemID end
sorting.fields.invertedItemCount = function(item) return -(item.itemCount or 1) end

sorting.fields.sortedClassID = function(item)
    return sorting.rankMap.classID[item.classID] or (item.classID + 200)
end

sorting.fields.sortedSubClassID = function(item)
    if item.classID == 2 then
        return sorting.rankMap.weaponSub[item.subClassID] or (item.subClassID + 200)
    elseif item.classID == 4 then
        return sorting.rankMap.armorSub[item.subClassID] or (item.subClassID + 200)
    elseif item.classID == 7 then
        return sorting.rankMap.tradegoodsSub[item.subClassID] or (item.subClassID + 200)
    end
    return item.subClassID
end

sorting.fields.sortedInvSlotID = function(item)
    return sorting.rankMap.invSlot[item.invSlotID] or (item.invSlotID + 200)
end

sorting.itemMeta = {
    __index = function(item, key)
        local fn = sorting.fields[key]
        if fn then
            local v = fn(item)
            item[key] = v   -- rawset-through; nil stays uncached on purpose
            return v
        end
    end,
}

-- =========================================================
-- Sort modes — ordered field lists (first difference decides)
-- =========================================================
sorting.modes = {
    ["quality"] = {
        "priority", "quality", "sortedClassID", "sortedInvSlotID",
        "sortedSubClassID", "itemLevelRaw", "itemName",
        "invertedItemID", "invertedItemCount", "itemLink",
    },
    ["type"] = {
        "priority", "sortedClassID", "sortedInvSlotID", "sortedSubClassID",
        "invertedItemLevelRaw", "invertedQuality", "itemName",
        "invertedItemID", "invertedItemCount", "itemLink",
    },
    ["name"] = {
        "priority", "sortedClassID", "sortedInvSlotID", "sortedSubClassID",
        "itemName", "invertedItemLevelRaw", "invertedQuality",
        "invertedItemID", "invertedItemCount", "itemLink",
    },
    ["item-level"] = {
        "priority", "invertedItemLevelEquipment", "sortedClassID",
        "sortedInvSlotID", "sortedSubClassID", "invertedQuality",
        "invertedItemLevelRaw", "itemName",
        "invertedItemID", "invertedItemCount", "itemLink",
    },
}

-- =========================================================
-- Key preparation + the comparator itself
-- =========================================================
local HEARTHSTONE = 6948   -- always sorts to the very front

function sorting.AddSortKeys(list)
    for i, item in ipairs(list) do
        if item.itemLink then
            setmetatable(item, sorting.itemMeta)
            item.priority = (item.itemID == HEARTHSTONE) and 1 or 1000
            local classID, subClassID, equipLoc
            if sorting.instantInfo then
                local _, _, _, el, _, c, s = sorting.instantInfo(item.itemID)
                classID, subClassID, equipLoc = c, s, el
            end
            if classID == nil then classID, subClassID = -1, -1 end
            item.classID, item.subClassID = classID, subClassID
            item.invSlotID = sorting.invTypeOf(item.itemID) or -1
            item.isEquipment = (classID == 2 or classID == 4)
                and equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG"
            if item.index == nil then item.index = i end
        end
    end
end

-- Sorts a prepared list (AddSortKeys first!). Returns the sorted list plus an
-- "incomplete" flag when some item data wasn't server-cached yet — callers
-- should re-run shortly after; the missing data has already been requested.
--
-- ORDER-TOTALITY: every key is materialized BEFORE table.sort and the items
-- are frozen (metatable detached), then a missing value consistently sorts
-- AFTER present ones. Skipping missing keys inside the comparator instead
-- (deciding cached pairs by item level but mixed pairs by item id) creates
-- preference cycles, and Lua 5.1's table.sort hard-errors on those
-- ("invalid order function for sorting"). Freezing also stops a value from
-- flipping nil -> real MID-SORT when the server data arrives between two
-- comparisons, which would be just as intransitive.
function sorting.OrderOneListOffline(list, method, reverse)
    local filtered = {}
    for _, item in ipairs(list) do
        if item.itemLink then filtered[#filtered + 1] = item end
    end
    local keys = sorting.modes[method] or sorting.modes["type"]
    local incomplete = false
    for _, item in ipairs(filtered) do
        for _, key in ipairs(keys) do
            if item[key] == nil then incomplete = true end   -- computes + caches
        end
        setmetatable(item, nil)   -- freeze the snapshot for this sort
    end
    table.sort(filtered, function(a, b)
        for _, key in ipairs(keys) do
            local av, bv = a[key], b[key]
            if av == nil or bv == nil then
                -- uncached data: cluster after the fully-known items, in a
                -- FIXED direction so the order stays total; the incomplete
                -- re-run puts them in their real place once the data lands
                if av ~= nil then return true end
                if bv ~= nil then return false end
                -- both missing -> tie on this key, fall through
            elseif av ~= bv then
                if reverse then return av > bv else return av < bv end
            end
        end
        return a.index < b.index
    end)
    return filtered, incomplete
end

-- =========================================================
-- Fresh bag scan -> plain item entries (legacy 10-tuple via Core/Compat.lua:
-- icon, count, locked, quality, readable, lootable, link, filtered, noValue,
-- itemID). Empty slots become {} so slot positions stay addressable.
-- =========================================================
function sorting.scan(bagIDs)
    local bags = {}
    for i, bagID in ipairs(bagIDs) do
        local bag = {}
        for slot = 1, (GetContainerNumSlots(bagID) or 0) do
            local _, count, locked, quality, _, _, link, _, noValue, itemID =
                GetContainerItemInfo(bagID, slot)
            local entry = { locked = locked and true or false }
            if link and itemID then
                entry.itemLink   = link
                entry.itemID     = itemID
                entry.itemCount  = count or 1
                entry.quality    = quality or 1
                entry.hasNoValue = noValue and true or false
            end
            bag[slot] = entry
        end
        bags[i] = bag
    end
    return bags
end

-- Special-bag detection: a nonzero bag family (herb/soul/enchanting/ammo…)
-- gets a contents check so only matching items are assigned to it.
function sorting.bagChecksFor(bagIDs)
    local checks, sortOrder = {}, {}
    for _, bagID in ipairs(bagIDs) do
        local _, family = GetContainerNumFreeSlots(bagID)
        if family and family ~= 0 then
            checks[bagID] = function(item)
                local fam = sorting.getItemFamily and sorting.getItemFamily(item.itemID)
                -- containers/quivers report the family they HOLD, not one they fit into
                return fam and item.classID ~= 1 and item.classID ~= 11
                    and bit.band(fam, family) ~= 0
            end
            sortOrder[bagID] = 5     -- special bags fill before regular ones
        else
            sortOrder[bagID] = 250   -- regular bags last
        end
    end
    return { checks = checks, sortOrder = sortOrder }
end

-- stable per-item identity for comparator ties, so re-running after a batch
-- of moves keeps one consistent target order across steps
function sorting.guidFor(bagID, slot)
    if ItemLocation and CI.GetItemGUID and CI.DoesItemExist then
        local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
        if CI.DoesItemExist(loc) then
            return CI.GetItemGUID(loc) or "-1"
        end
        return "-1"
    end
    return tostring(bagID) .. ":" .. tostring(slot)
end

-- item pickup sounds, muted while a sort step fires its moves
sorting.pickupSounds = {
    567542, 567543, 567544, 567545, 567546, 567547, 567548, 567549, 567550,
    567551, 567552, 567553, 567554, 567555, 567556, 567557, 567558, 567559,
    567560, 567561, 567562, 567563, 567564, 567565, 567566, 567567, 567568,
    567569, 567570, 567571, 567572, 567573, 567574, 567575, 567576, 567577,
}

local function isLockedLive(bagID, slot)
    local _, _, locked = GetContainerItemInfo(bagID, slot)
    return locked and true or false
end

-- =========================================================
-- One physical ordering step. Scans fresh, assigns every item a target slot
-- and fires the moves it can. Returns a status:
--   "complete"  nothing left to do
--   "move"      moves fired — wait for the bag update, then step again
--   "unlock"    some item was locked — retry shortly
--   "itemdata"  sort keys incomplete — retry shortly
-- plus the number of moves queued (for the driver's stuck detection).
-- =========================================================
function sorting.ApplyOrdering(bagIDs, method, reverse)
    if InCombatLockdown() or UnitIsDead("player") then return "complete", 0 end

    local bagChecks = sorting.bagChecksFor(bagIDs)
    local bags = sorting.scan(bagIDs)

    local scanIndexOf = {}
    for i, bagID in ipairs(bagIDs) do scanIndexOf[bagID] = i end

    -- one long list of every occupied slot
    local oneList = {}
    for bagIndex, bagContents in ipairs(bags) do
        for slotIndex, item in ipairs(bagContents) do
            item.from = { bagIndex = bagIndex, slot = slotIndex }
            if item.itemLink then
                oneList[#oneList + 1] = item
            end
        end
    end

    sorting.AddSortKeys(oneList)
    for _, item in ipairs(oneList) do
        item.index = sorting.guidFor(bagIDs[item.from.bagIndex], item.from.slot)
    end

    local sortedItems, incomplete = sorting.OrderOneListOffline(oneList, method, reverse)

    -- bag fill order: special bags first (sortOrder), ties by list position
    -- (inverted list for the junk end)
    local function usableBags(fromEnd)
        local order = {}
        for i = 1, #bagIDs do order[i] = i end
        table.sort(order, function(a, b)
            local ao = bagChecks.sortOrder[bagIDs[a]]
            local bo = bagChecks.sortOrder[bagIDs[b]]
            if ao == bo then
                if fromEnd then return a > b else return a < b end
            end
            return ao < bo
        end)
        local avail = {}
        for _, index in ipairs(order) do
            local bagID = bagIDs[index]
            if (GetContainerNumSlots(bagID) or 0) > 0 then
                avail[#avail + 1] = bagID
            end
        end
        return avail
    end

    local bagIDsAvailable = usableBags(false)
    local bagIDsInverted  = usableBags(true)
    local numBagsAffected = #bagIDsAvailable

    local bagStores = {}
    for _, bagID in ipairs(bagIDsAvailable) do
        bagStores[bagID] = { first = 1, last = GetContainerNumSlots(bagID) or 0 }
    end

    -- how many special bags could hold each item — items that fit the fewest
    -- get first pick of the special-bag space
    for _, item in ipairs(sortedItems) do
        item.specialisedBags = 0
        for _, check in pairs(bagChecks.checks) do
            if check(item) then
                item.specialisedBags = item.specialisedBags + 1
            end
        end
    end

    -- junk (grey with a sell value) goes to the opposite end of the bags
    local groupA, groupB = {}, {}
    for _, item in ipairs(sortedItems) do
        if not item.hasNoValue and item.quality == 0 then
            groupB[#groupB + 1] = item
        else
            groupA[#groupA + 1] = item
        end
    end
    if reverse then
        groupA, groupB = groupB, groupA
    end

    local moveQueue0, moveQueue1 = {}, {}   -- to-empty first, swaps second
    local function queueSwap(item, bagID, slotID)
        local fromBag, fromSlot = bagIDs[item.from.bagIndex], item.from.slot
        if fromBag == bagID and fromSlot == slotID then return end
        local target = bags[scanIndexOf[bagID]][slotID]
        local move = { fromBag = fromBag, fromSlot = fromSlot, toBag = bagID, toSlot = slotID }
        if target and target.itemLink then
            moveQueue1[#moveQueue1 + 1] = move
        else
            moveQueue0[#moveQueue0 + 1] = move
        end
    end

    -- groupB fills bags from the far end backwards
    local function sweepBackwards(group, specialsOnly)
        for _, item in ipairs(group) do
            for bagIndex, bagID in ipairs(bagIDsInverted) do
                local check = bagChecks.checks[bagID]
                if (not specialsOnly and not check) or (check and check(item)) then
                    item.processed = true
                    local slot = bagStores[bagID].last
                    queueSwap(item, bagID, slot)
                    bagStores[bagID].last = slot - 1
                    if bagStores[bagID].first == slot then
                        table.remove(bagIDsInverted, bagIndex)
                    end
                    break
                end
            end
        end
    end

    -- groupA fills bags from the front forwards
    local function sweepForwards(group, specialsOnly)
        for _, item in ipairs(group) do
            for bagIndex, bagID in ipairs(bagIDsAvailable) do
                local check = bagChecks.checks[bagID]
                if (not specialsOnly and not check) or (check and check(item)) then
                    item.processed = true
                    local slot = bagStores[bagID].first
                    queueSwap(item, bagID, slot)
                    bagStores[bagID].first = slot + 1
                    if bagStores[bagID].last == slot then
                        table.remove(bagIDsAvailable, bagIndex)
                    end
                    break
                end
            end
        end
    end

    local function whereSpecialised(group, n)
        local out = {}
        for _, item in ipairs(group) do
            if item.specialisedBags == n then out[#out + 1] = item end
        end
        return out
    end
    local function unprocessed(group)
        local out = {}
        for _, item in ipairs(group) do
            if not item.processed then out[#out + 1] = item end
        end
        return out
    end

    -- special bags first (fewest-fits items get first pick), then the rest
    for i = 1, numBagsAffected do
        sweepBackwards(whereSpecialised(groupB, i), true)
    end
    sweepBackwards(unprocessed(groupB), false)

    -- drop bags the backwards sweep exhausted from the forwards sweep too
    local stillOpen = {}
    for _, bagID in ipairs(bagIDsInverted) do stillOpen[bagID] = true end
    local remaining = {}
    for _, bagID in ipairs(bagIDsAvailable) do
        if stillOpen[bagID] then remaining[#remaining + 1] = bagID end
    end
    bagIDsAvailable = remaining

    for i = 1, numBagsAffected do
        sweepForwards(whereSpecialised(groupA, i), true)
    end
    sweepForwards(unprocessed(groupA), false)

    -- fire the moves; live lock checks serialize chained swaps across steps
    -- (a slot touched by an earlier move in this batch reads as locked)
    local moved, anyLocked = false, false
    if MuteSoundFile then
        for _, id in ipairs(sorting.pickupSounds) do MuteSoundFile(id) end
    end
    for _, move in ipairs(moveQueue0) do
        if not isLockedLive(move.fromBag, move.fromSlot) then
            PickupContainerItem(move.fromBag, move.fromSlot)
            PickupContainerItem(move.toBag, move.toSlot)
            ClearCursor()
            moved = true
        else
            anyLocked = true
        end
    end
    for _, move in ipairs(moveQueue1) do
        if not isLockedLive(move.fromBag, move.fromSlot)
            and not isLockedLive(move.toBag, move.toSlot) then
            PickupContainerItem(move.fromBag, move.fromSlot)
            PickupContainerItem(move.toBag, move.toSlot)
            ClearCursor()
            moved = true
        else
            anyLocked = true
        end
    end
    if UnmuteSoundFile then
        for _, id in ipairs(sorting.pickupSounds) do UnmuteSoundFile(id) end
    end

    local queued = #moveQueue0 + #moveQueue1
    if incomplete then return "itemdata", queued end
    if moved then return "move", queued end
    if anyLocked then return "unlock", queued end
    return "complete", queued
end

-- =========================================================
-- One stack-combining step: for every item with more partial stacks than
-- needed, merge the smallest partial onto the largest (the client combines
-- them natively — no manual splitting required). One merge per item per
-- step; repeats via the driver until nothing is left to merge.
-- =========================================================
function sorting.CombineStacksStep(bagIDs)
    if InCombatLockdown() then return "complete" end
    local bags = sorting.scan(bagIDs)

    local byItem = {}
    for bagIndex, bagContents in ipairs(bags) do
        for slot, entry in ipairs(bagContents) do
            if entry.itemID then
                local t = byItem[entry.itemID]
                if not t then t = {}; byItem[entry.itemID] = t end
                t[#t + 1] = { bagID = bagIDs[bagIndex], slot = slot, entry = entry }
            end
        end
    end

    local moved, anyLocked, waiting = false, false, false
    for itemID, stacks in pairs(byItem) do
        if #stacks > 1 then
            local stackSize = select(8, GetItemInfo(itemID))
            if not stackSize then
                sorting.requestLoad(itemID)
                waiting = true
            elseif stackSize > 1 then
                local total, fullStacks = 0, 0
                for _, s in ipairs(stacks) do
                    total = total + s.entry.itemCount
                    if s.entry.itemCount == stackSize then fullStacks = fullStacks + 1 end
                end
                local targetFull   = math.floor(total / stackSize)
                local targetStacks = math.ceil(total / stackSize)
                if #stacks > targetStacks or fullStacks ~= targetFull then
                    local partials = {}
                    for _, s in ipairs(stacks) do
                        if s.entry.itemCount ~= stackSize then partials[#partials + 1] = s end
                    end
                    table.sort(partials, function(a, b)
                        return a.entry.itemCount < b.entry.itemCount
                    end)
                    local source, target = partials[1], partials[#partials]
                    if source and target and source ~= target then
                        if not source.entry.locked and not target.entry.locked then
                            PickupContainerItem(source.bagID, source.slot)
                            PickupContainerItem(target.bagID, target.slot)
                            ClearCursor()
                            moved = true
                        else
                            anyLocked = true
                        end
                    end
                end
            end
        end
    end

    if moved then return "move" end
    if anyLocked then return "unlock" end
    if waiting then return "itemdata" end
    return "complete"
end

-- =========================================================
-- Driver — repeats combine + ordering steps until everything settles.
--   "move"               wait for the bag-update event (1s fallback timer)
--   "unlock"/"itemdata"  retry shortly
-- onDone(ok) fires EXACTLY once per Run (also on abort/cancel), so callers
-- can safely clear their in-flight flags there.
-- =========================================================
sorting.waiter = CreateFrame("Frame")
sorting.waiter:Hide()
sorting.waiter:SetScript("OnEvent", function()
    local step = sorting.pendingStep
    if step then
        sorting.clearWait()
        step()
    end
end)

function sorting.clearWait()
    sorting.pendingStep = nil
    sorting.waiter:UnregisterAllEvents()
    if sorting.fallbackTimer then
        sorting.fallbackTimer:Cancel()
        sorting.fallbackTimer = nil
    end
end

function sorting.Cancel()
    sorting.clearWait()
    sorting.runToken = (sorting.runToken or 0) + 1   -- invalidate pending steps
    if sorting.active then
        sorting.active = false
        sorting.activeBags = nil
        local cb = sorting.onDone
        sorting.onDone = nil
        if cb then cb(false) end
    end
end

-- cancel only when the running sort covers the given container (e.g. the bank
-- window cancels a BANK sort on close without touching a running bag sort)
function sorting.CancelContaining(bagID)
    if not (sorting.active and sorting.activeBags) then return end
    for _, b in ipairs(sorting.activeBags) do
        if b == bagID then
            sorting.Cancel()
            return
        end
    end
end

function sorting.IsActive()
    return sorting.active and true or false
end

function sorting.Run(bagIDs, method, reverse, onDone)
    if sorting.active then
        if onDone then onDone(false) end
        return
    end
    sorting.active = true
    sorting.activeBags = bagIDs
    sorting.onDone = onDone
    sorting.runToken = (sorting.runToken or 0) + 1
    local myToken  = sorting.runToken
    local phase    = "combine"
    local attempts = 0
    local lastQueued, stuck = -1, 0

    local step
    local function finish(ok)
        sorting.clearWait()
        sorting.active = false
        sorting.activeBags = nil
        local cb = sorting.onDone
        sorting.onDone = nil
        if cb then cb(ok) end
    end
    local function waitForBags()
        sorting.pendingStep = step
        sorting.waiter:RegisterEvent("BAG_UPDATE_DELAYED")
        sorting.waiter:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
        sorting.fallbackTimer = C_Timer.NewTimer(1, function()
            sorting.fallbackTimer = nil
            local s = sorting.pendingStep
            if s then
                sorting.clearWait()
                s()
            end
        end)
    end
    step = function()
        if not sorting.active or sorting.runToken ~= myToken then return end
        if InCombatLockdown() then finish(false); return end
        attempts = attempts + 1
        if attempts > 150 then finish(false); return end

        -- pcall-contained: an escaped error would skip finish() and leave the
        -- caller's in-flight flag stuck true for the whole session
        local ok, status, queued
        if phase == "combine" then
            ok, status = pcall(sorting.CombineStacksStep, bagIDs)
            if ok and status == "complete" then
                phase = "order"
                ok, status, queued = pcall(sorting.ApplyOrdering, bagIDs, method, reverse)
            end
        else
            ok, status, queued = pcall(sorting.ApplyOrdering, bagIDs, method, reverse)
        end
        if not ok then finish(false); return end

        -- stuck detection: the same number of pending moves several steps in
        -- a row means the moves aren't landing (e.g. the bank was closed
        -- mid-sort) — stop instead of ticking until the attempt cap
        if status == "move" and queued ~= nil then
            if queued == lastQueued then
                stuck = stuck + 1
                if stuck >= 4 then finish(false); return end
            else
                stuck = 0
            end
            lastQueued = queued
        end

        if status == "complete" then
            finish(true)
        elseif status == "move" then
            waitForBags()
        else   -- "unlock" / "itemdata"
            C_Timer.After(0.05, step)
        end
    end
    step()
end

-- =========================================================
-- Display-only ordering for one category bucket ({bag, slot} entries from
-- Modules/Bags.lua). Never moves anything; returns re-ordered {bag, slot}
-- pairs + the incomplete flag (caller schedules one repaint when data lands).
-- =========================================================
function sorting.OrderBucket(entries, method, reverse)
    local list = {}
    for i, e in ipairs(entries) do
        local _, count, _, quality, _, _, link, _, noValue, itemID =
            GetContainerItemInfo(e.bag, e.slot)
        list[i] = {
            bag = e.bag, slot = e.slot, index = i,
            itemLink = link, itemID = itemID, itemCount = count or 1,
            quality = quality or 1, hasNoValue = noValue and true or false,
        }
    end
    sorting.AddSortKeys(list)
    local sorted, incomplete = sorting.OrderOneListOffline(list, method, reverse)
    local out = {}
    for _, item in ipairs(sorted) do
        out[#out + 1] = { bag = item.bag, slot = item.slot }
    end
    -- OrderOneListOffline drops link-less entries; keep them (rare race
    -- between the caller's link check and our scan) at the end instead
    if #out < #list then
        for _, item in ipairs(list) do
            if not item.itemLink then
                out[#out + 1] = { bag = item.bag, slot = item.slot }
            end
        end
    end
    return out, incomplete
end
