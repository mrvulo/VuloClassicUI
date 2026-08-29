-- VuloClassicUI / Modules / Loadouts
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("loadouts", {
    -- Strict grid: lone rows of the one-row sections stretched across the
    -- page (user report, 31.07.2026). On the grid a lone row keeps its half.
    optionsGrid = true,
    name        = "Loadouts",
    group       = "Bags & Items",
    description = "Save and quickly equip gear sets for different specs, content, or roles.",
    defaults = {
        enabled       = true,
        loadouts      = {},
        confirmDelete = true,
        minimap = { hidden = false, angle = 45 },
        autoSwitchEnabled = true,
        formMapping       = {},
        specSwitchEnabled = true,
        specMapping       = {},
        sidebarEnabled      = true,
        sidebarTopOffset    = -8,
        sidebarBottomOffset = 45,
        sidebarPos          = { x = 0, y = 0 },
    },
})

-- Loadouts live per-character in VuloClassicUICharDB; mod.db.loadouts is the legacy account-wide pool.
local function charDB()
    _G.VuloClassicUICharDB = _G.VuloClassicUICharDB or {}
    return _G.VuloClassicUICharDB
end
local function LO()
    local c = charDB(); c.loadouts = c.loadouts or {}; return c.loadouts
end
local function specMap()
    local c = charDB(); c.specMapping = c.specMapping or {}; return c.specMapping
end
local function formMap()
    local c = charDB(); c.formMapping = c.formMapping or {}; return c.formMapping
end

-- API compat: Anniversary moved container APIs into C_Container.
local GetContainerItemID    = (C_Container and C_Container.GetContainerItemID)    or _G.GetContainerItemID
local GetContainerItemLink  = (C_Container and C_Container.GetContainerItemLink)  or _G.GetContainerItemLink
local GetContainerNumSlots  = (C_Container and C_Container.GetContainerNumSlots)  or _G.GetContainerNumSlots
local GetContainerNumFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
local UseContainerItem      = (C_Container and C_Container.UseContainerItem)      or _G.UseContainerItem

-- Skips shirt (4) and tabard (19).
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local SLOT_NAMES
ns.OnLocaleReady(function()
SLOT_NAMES = {
    [1]  = L["Head"],    [2]  = L["Neck"],     [3]  = L["Shoulder"],
    [5]  = L["Chest"],   [6]  = L["Waist"],    [7]  = L["Legs"],
    [8]  = L["Feet"],    [9]  = L["Wrist"],    [10] = L["Hands"],
    [11] = L["Finger 1"], [12] = L["Finger 2"],
    [13] = L["Trinket 1"], [14] = L["Trinket 2"],
    [15] = L["Back"],
    [16] = L["Main Hand"], [17] = L["Off Hand"], [18] = L["Ranged"],
}
end)

local SLOT_GROUPS = {
    all      = EQUIP_SLOTS,
    trinkets = { 13, 14 },
    weapons  = { 16, 17, 18 },
    rings    = { 11, 12 },
    armor    = { 1, 3, 5, 6, 7, 8, 9, 10, 15 },
}

local function getItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function captureCurrentEquipment(slotList)
    slotList = slotList or EQUIP_SLOTS
    local set = {}
    for _, slot in ipairs(slotList) do
        local link = GetInventoryItemLink("player", slot)
        set[slot] = link or false
    end
    return set
end

-- Item id plus SUFFIX, which is what separates the ring "of the Owl" from the
-- one "of the Bear": both carry the same item id, so an id-only search picks
-- whichever lies further left in the bags and calls it a hit.
--
-- Deliberately NOT the enchant or the gems, although the link carries them: those
-- change over an item's life, and a set saved before an enchant would suddenly
-- report its own item as missing. The suffix never changes.
local function itemVariant(link)
    if not link then return nil end
    local s = link:match("item[%-?%d:]+")
    if not s then return nil end
    local f = { strsplit(":", s) }
    return (f[2] or "") .. ":" .. (f[8] or "")
end

-- Includes enchant and gems so two copies of the same item can be told apart
-- when their enhancements differ. The unique id is deliberately excluded for
-- the same reason itemVariant excludes it.
local function itemExact(link)
    if not link then return nil end
    local s = link:match("item[%-?%d:]+")
    if not s then return nil end
    local f = { strsplit(":", s) }
    return (f[2] or "") .. ":" .. (f[3] or "") .. ":" .. (f[4] or "") .. ":"
        .. (f[5] or "") .. ":" .. (f[6] or "") .. ":" .. (f[7] or "") .. ":" .. (f[8] or "")
end

-- The exact match wins; a variant match is kept before the id fallback so two
-- copies can be distinguished without making a changed single copy missing.
local function findItemInBags(targetItemID, wantVariant, wantExact)
    if not GetContainerItemID or not GetContainerNumSlots then return nil end
    local anyBag, anySlot
    local variantBag, variantSlot
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            if GetContainerItemID(bag, slot) == targetItemID then
                if not wantVariant and not wantExact then return bag, slot end
                local l = GetContainerItemLink and GetContainerItemLink(bag, slot)
                if wantExact and itemExact(l) == wantExact then return bag, slot end
                if wantVariant and itemVariant(l) == wantVariant then
                    if not variantBag then variantBag, variantSlot = bag, slot end
                elseif not variantBag and not anyBag then
                    anyBag, anySlot = bag, slot
                end
            end
        end
    end
    if variantBag then return variantBag, variantSlot end
    return anyBag, anySlot
end

-- Bank contents are snapshotted while the bank is open so "in the bank" stays answerable anywhere.
local function bankItems()
    local c = charDB(); c.bankItems = c.bankItems or {}; return c.bankItems
end

local _bankOpen = false
local _snapPending = false

-- The bank's own container plus its bag slots. Built from the globals so a
-- client with a different bank size contributes what it has.
local function bankBagList()
    local bags = { _G.BANK_CONTAINER or -1 }
    for i = 1, (_G.NUM_BANKBAGSLOTS or 6) do
        bags[#bags + 1] = (_G.NUM_BAG_SLOTS or 4) + i
    end
    return bags
end

-- Only answerable while the bank window is open: the bank containers read as
-- empty otherwise, which is why the snapshot below exists for the markers. Gated
-- on the EVENT, not on BankFrame:IsShown() -- the bank module hides Blizzard's
-- window and puts its own up, while the session that makes the containers
-- readable runs from BANKFRAME_OPENED to BANKFRAME_CLOSED either way.
local function findItemInBank(targetItemID, wantVariant, wantExact)
    if not (_bankOpen and GetContainerItemID and GetContainerNumSlots) then return nil end
    local anyBag, anySlot
    local variantBag, variantSlot
    for _, bag in ipairs(bankBagList()) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            if GetContainerItemID(bag, slot) == targetItemID then
                if not wantVariant and not wantExact then return bag, slot end
                local l = GetContainerItemLink and GetContainerItemLink(bag, slot)
                if wantExact and itemExact(l) == wantExact then return bag, slot end
                if wantVariant and itemVariant(l) == wantVariant then
                    if not variantBag then variantBag, variantSlot = bag, slot end
                elseif not variantBag and not anyBag then
                    anyBag, anySlot = bag, slot
                end
            end
        end
    end
    if variantBag then return variantBag, variantSlot end
    return anyBag, anySlot
end

local function snapshotBank()
    local store = bankItems()
    wipe(store)
    for _, bag in ipairs(bankBagList()) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            if id then store[id] = true end
        end
    end
end

local function onBankEvent(event)
    if event == "BANKFRAME_OPENED" then
        _bankOpen = true
        -- item data lags BANKFRAME_OPENED; snapshot a moment later
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function() if _bankOpen then snapshotBank() end end)
        else
            snapshotBank()
        end
    elseif event == "BANKFRAME_CLOSED" then
        _bankOpen = false
    elseif _bankOpen then
        -- coalesce event bursts into one snapshot
        if C_Timer and C_Timer.After then
            if not _snapPending then
                _snapPending = true
                C_Timer.After(0.1, function()
                    _snapPending = false
                    if _bankOpen then snapshotBank() end
                end)
            end
        else
            snapshotBank()
        end
    end
end

-- Returns "equipped" | "bags" | "bank" | nil. Indexed once per frame; a per-item bag scan is too slow here.
local availIndex
local function buildAvailIndex()
    local idx = {}
    for _, s in ipairs(EQUIP_SLOTS) do
        local l = GetInventoryItemLink("player", s)
        local id = l and getItemIDFromLink(l)
        if id then idx[id] = "equipped" end
    end
    if GetContainerItemID and GetContainerNumSlots then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, (GetContainerNumSlots(bag) or 0) do
                local id = GetContainerItemID(bag, slot)
                if id and not idx[id] then idx[id] = "bags" end
            end
        end
    end
    return idx
end

local function itemAvailability(link)
    local itemID = getItemIDFromLink(link)
    if not itemID then return nil end
    if not availIndex then
        availIndex = buildAvailIndex()
        -- valid for this frame only; bags/equipment can change right after
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() availIndex = nil end)
        else
            local idx = availIndex
            availIndex = nil
            local a = idx[itemID]
            if a then return a end
            if bankItems()[itemID] then return "bank" end
            return nil
        end
    end
    local a = availIndex[itemID]
    if a then return a end
    if bankItems()[itemID] then return "bank" end
    return nil
end

-- Liefert fehlende, in der Bank liegende, angelegte und gepruefte Teile.
-- equipped/total tragen den gruenen Marker: nur wenn ALLE Teile getragen
-- werden, gilt das Loadout als angelegt.
local function setStatus(name)
    local lo = LO()[name]
    if not (lo and lo.slots) then return 0, 0, 0, 0 end
    local missing, inBank, equipped, total = 0, 0, 0, 0
    for slot, link in pairs(lo.slots) do
        total = total + 1
        if link == false then
            -- Deliberate empty marker: satisfied while the body slot is bare.
            -- Unsatisfied counts to total only -- the worn piece is surplus,
            -- not missing, so neither the red nor the green marker may fire.
            if not GetInventoryItemLink("player", slot) then
                equipped = equipped + 1
            end
        else
            local a = itemAvailability(link)
            if a == "bank" then inBank = inBank + 1
            elseif a == "equipped" then equipped = equipped + 1
            elseif not a then missing = missing + 1 end
        end
    end
    return missing, inBank, equipped, total
end

-- Reverse index itemID -> set names; rebuilt lazily whenever _setIndexDirty is set by a mutation.
local _setIndexDirty = true
local _setsByItem = {}
local function rebuildSetIndex()
    _setIndexDirty = false
    wipe(_setsByItem)
    for name, lo in pairs(LO() or {}) do
        for _, link in pairs(lo.slots or {}) do
            local id = getItemIDFromLink(link)
            if id then
                local t = _setsByItem[id]
                if not t then t = {}; _setsByItem[id] = t end
                t[#t + 1] = name
            end
        end
    end
    for _, t in pairs(_setsByItem) do table.sort(t) end
end

-- Public: also consumed by the disenchant queue's warning.
function ns.ItemSetMembership(itemID)
    if not itemID or not mod.active then return nil end
    if _setIndexDirty then rebuildSetIndex() end
    local t = _setsByItem[itemID]
    if t and #t > 0 then return table.concat(t, ", ") end
end

-- BOTH mechanisms, deduped -- not whichever one the client appears to have.
-- Picking by "is the table there" is what kept this line off the screen on
-- Anniversary: TooltipDataProcessor EXISTS on that client and its post-call
-- never fires (the same trap General.lua notes for unit tooltips), so the branch
-- that would have worked was never installed and no set line ever appeared.
-- General.lua's own item annotation belts both ways for exactly this reason.
--
-- The dedupe key is the item LINK, not a flag: OnTooltipSetItem fires twice per
-- fill on the older clients, and whichever mechanism gets there second finds the
-- link already annotated. Cleared on OnTooltipCleared, so the same item is
-- annotated again on the next hover.
local _tipHooked = false
local function installSetTooltip()
    if _tipHooked then return end
    _tipHooked = true

    local function annotate(tip)
        if not mod.active or not tip then return end
        if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
        -- Two ways to ask what the tooltip is showing, probed in order: the
        -- method is the classic one, and the newer clients moved it out to
        -- TooltipUtil and dropped it. Only one of them is a special case if we
        -- pick -- and picking is what kept this line off the screen here in the
        -- first place.
        local link
        if tip.GetItem then
            local ok, _, l = pcall(tip.GetItem, tip)
            if ok then link = l end
        end
        if not link and TooltipUtil and TooltipUtil.GetDisplayedItem then
            local ok, _, l = pcall(TooltipUtil.GetDisplayedItem, tip)
            if ok then link = l end
        end
        if not link then return end
        if tip._vcuiSetLink == link then return end
        local sets = ns.ItemSetMembership(getItemIDFromLink(link))
        if not sets then return end
        -- Only ever set where a line actually went in, so an item in no set does
        -- not block the next fill of the same tooltip.
        tip._vcuiSetLink = link
        tip:AddLine(string.format(L["Part of set: %s"], sets),
            ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        tip:Show()
    end

    local function onCleared(tip) tip._vcuiSetLink = nil end

    -- pcall'd per script name: the newer clients dropped OnTooltipSetItem
    -- entirely, and hooking a script a frame does not have is an error, not a
    -- no-op. There the post-call below is the one that carries the line.
    local function hookTip(tip)
        if not (tip and tip.HookScript) then return end
        pcall(tip.HookScript, tip, "OnTooltipSetItem", annotate)
        pcall(tip.HookScript, tip, "OnTooltipCleared", onCleared)
    end
    hookTip(GameTooltip)
    hookTip(ItemRefTooltip)

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
       and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        pcall(TooltipDataProcessor.AddTooltipPostCall,
            Enum.TooltipDataType.Item, annotate)
    end
end

-- UseContainerItem ignores the destination slot; only EquipCursorItem(slot) honours it (rings/trinkets).
local _PickupContainerItem = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem

function ns:EquipBagItemToSlot(bag, bagSlot, equipSlot)
    if InCombatLockdown() then return false, "combat" end
    if not _PickupContainerItem or not _G.EquipCursorItem then return false, "noapi" end

    ClearCursor()
    _PickupContainerItem(bag, bagSlot)
    if CursorHasItem and not CursorHasItem() then
        return false, "pickup"
    end
    local ok = pcall(_G.EquipCursorItem, equipSlot)
    -- Only clear a still-occupied cursor: a pending BoE-confirm popup must keep its item.
    if CursorHasItem and CursorHasItem() then
        ClearCursor()
    end
    return ok
end

-- All empty {bag, slot} pairs in NORMAL bags (family 0). Special bags (quiver,
-- soul bag, profession bags) report free slots but reject armor, so they are
-- skipped entirely rather than tried and failed on.
local function emptyBagSlots()
    local empties = {}
    if not (GetContainerNumFreeSlots and GetContainerNumSlots and GetContainerItemID) then
        return empties
    end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local free, family = GetContainerNumFreeSlots(bag)
        if (free or 0) > 0 and (family or 0) == 0 then
            for slot = 1, (GetContainerNumSlots(bag) or 0) do
                if GetContainerItemID(bag, slot) == nil then
                    table.insert(empties, { bag, slot })
                end
            end
        end
    end
    return empties
end

-- Moves whatever is in `slot` off the character and into a slot claimed from
-- `empties` (built once per set change by emptyBagSlots). Targeted placement
-- instead of PutItemInBackpack, for three reasons measured in the field:
-- PutItemInBackpack on a full backpack raises the red "That bag is full" UI
-- error client-side; free-slot counts go stale across one run because bag data
-- only updates after BAG_UPDATE, so stripping several slots kept aiming every
-- piece at the same already-taken slot; and special bags count as free space
-- while rejecting gear. Claiming a concrete empty slot per piece from a list
-- built up front sidesteps all three.
local function unequipSlotToBags(invSlot, empties)
    if InCombatLockdown() then return false end
    if CursorHasItem and CursorHasItem() then return false end
    -- UseContainerItem cannot place INTO a chosen slot, so only the pickup
    -- route works here; without it, leave the piece where it is.
    if not _PickupContainerItem then return false end
    -- No claimed slot means no free space: leave the piece on the body and do
    -- not touch the cursor, so no red client error ever fires from us.
    local target = table.remove(empties)
    if not target then return false end
    PickupInventoryItem(invSlot)
    if CursorHasItem and not CursorHasItem() then
        table.insert(empties, target)
        return false
    end
    _PickupContainerItem(target[1], target[2])
    if CursorHasItem and CursorHasItem() then
        ClearCursor()
        table.insert(empties, target)
        return false
    end
    return true
end

local function countSlots(loadout)
    local n = 0
    if loadout and loadout.slots then
        for _, v in pairs(loadout.slots) do
            if type(v) == "string" then n = n + 1 end
        end
    end
    return n
end

local function sortedLoadoutNames()
    local names = {}
    if mod.db and LO() then
        local lo = LO()
        for name in pairs(lo) do table.insert(names, name) end
        -- Ohne order ans Ende und dort alphabetisch: Bestaende von vor dem
        -- Umsortier-Feature (alle ohne order) stehen so weiter in ihrer
        -- gewohnten Reihenfolge, der erste Aufbau sieht aus wie immer.
        table.sort(names, function(a, b)
            local oa = lo[a].order or math.huge
            local ob = lo[b].order or math.huge
            if oa ~= ob then return oa < ob end
            return a < b
        end)
        -- Fehlende Nummern einmalig vergeben und Luecken schliessen; die
        -- Vergabe ist idempotent, ein zweiter Aufruf aendert nichts mehr.
        for i, name in ipairs(names) do
            if lo[name].order ~= i then lo[name].order = i end
        end
    end
    return names
end

-- Fuegt das Set an targetIndex der angezeigten Liste ein (1..n) und
-- nummeriert alles neu; targetIndex zaehlt auf der Liste OHNE das gezogene Set.
local function moveLoadout(name, targetIndex)
    local lo = LO()
    if not lo or not lo[name] then return end
    local names = sortedLoadoutNames()
    for i, n in ipairs(names) do
        if n == name then table.remove(names, i) break end
    end
    if targetIndex < 1 then targetIndex = 1 end
    if targetIndex > #names + 1 then targetIndex = #names + 1 end
    table.insert(names, targetIndex, name)
    for i, n in ipairs(names) do lo[n].order = i end
end

local function copySlotList(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

local function saveAs(name, slotList)
    if not name or name == "" then
        ns:Print(L["Please provide a name for the loadout."])
        return
    end
    -- Vorhandenen Eintrag AKTUALISIEREN statt ersetzen. Sonst gehen alle
    -- Felder verloren, die nicht hier stehen - allen voran iconOverride,
    -- also das selbst gewaehlte Symbol.
    local set = LO()[name]
    if not set then
        set = { createdAt = time() }
        -- Erst durchnummerieren lassen: Bestaende von vor dem Umsortier-Feature
        -- haben noch keine Nummer, und ohne diesen Aufruf bekaeme das neue Set
        -- die 1 und stuende VOR ihnen statt hinten.
        sortedLoadoutNames()
        -- ans Ende der angezeigten Liste, nicht alphabetisch einsortiert
        local maxOrder = 0
        for _, other in pairs(LO()) do
            if other.order and other.order > maxOrder then maxOrder = other.order end
        end
        set.order = maxOrder + 1
        LO()[name] = set
    end
    set.slots    = captureCurrentEquipment(slotList)
    set.slotMask = copySlotList(slotList or EQUIP_SLOTS)

    _setIndexDirty = true
    ns:Print(string.format(L["Loadout '%s' saved (%d items)."],
        name, countSlots(set)))
end

-- StaticPopup_Show cannot pass parameters, so the slot list is handed over through this upvalue.
local _pendingSaveSlots = nil

local function promptSaveWithSlots(slotList)
    _pendingSaveSlots = slotList
    StaticPopup_Show("VCUI_LOADOUT_SAVE")
end

-- Must re-capture via slotMask, not loadout.slots: slots only holds what was equipped at save time.
local function overwriteLoadout(name)
    local loadout = LO()[name]
    if not loadout then return end
    local slotList = loadout.slotMask
    if not slotList or #slotList == 0 then
        slotList = {}
        for s in pairs(loadout.slots or {}) do table.insert(slotList, s) end
    end
    if #slotList == 0 then slotList = EQUIP_SLOTS end
    -- Nur Ausruestung und Maske erneuern. Symbol, Erstellungsdatum und
    -- alles weitere bleiben am Eintrag haengen.
    loadout.slots    = captureCurrentEquipment(slotList)
    loadout.slotMask = copySlotList(slotList)
    _setIndexDirty = true
    ns:Print(string.format(L["Loadout '%s' updated with current gear."], name))
end

local function deleteLoadout(name)
    if not LO()[name] then
        ns:Print(string.format(L["Loadout '%s' does not exist."], name))
        return
    end
    LO()[name] = nil
    _setIndexDirty = true
    ns:Print(string.format(L["Loadout '%s' deleted."], name))
end

local function equipLoadout(name)
    if InCombatLockdown() then
        ns:Print(L["Cannot change equipment in combat."])
        return
    end
    local loadout = LO()[name]
    if not loadout then
        ns:Print(string.format(L["Loadout '%s' does not exist."], name))
        return
    end
    if not _PickupContainerItem and not UseContainerItem then
        ns:Print(L["Equipment swap API not available on this client."])
        return
    end

    local swapped, missing, fromBank = 0, 0, 0
    local bagsFull = false
    local failedLinks = {}
    -- Claimed-empty-slot list for stripping, built lazily on the first slot
    -- that actually needs it and shared across the whole run: one snapshot,
    -- each strip consumes one concrete slot from it.
    local empties = nil
    -- Ascending order so paired slots (11/12, 13/14) resolve predictably.
    local sortedSlots = {}
    for slot in pairs(loadout.slots) do table.insert(sortedSlots, slot) end
    table.sort(sortedSlots)

    for _, slot in ipairs(sortedSlots) do
        local link = loadout.slots[slot]
        if link == false then
            local currentLink = GetInventoryItemLink("player", slot)
            if currentLink then
                if not empties then empties = emptyBagSlots() end
                if unequipSlotToBags(slot, empties) then
                    swapped = swapped + 1
                else
                    bagsFull = true
                end
            end
        else
            local currentLink = GetInventoryItemLink("player", slot)
            -- By VARIANT, not by raw link: a stored link carries a unique id that the
            -- same physical item does not keep, so the comparison said "different"
            -- for the very item the set meant and re-equipped it for nothing.
            local want = itemVariant(link)
            local wantExact = itemExact(link)
            local needSwap = itemVariant(currentLink) ~= want
            local exactOnly = false
            if not needSwap and wantExact and itemExact(currentLink) ~= wantExact then
                needSwap, exactOnly = true, true -- right id+suffix on the body, wrong gems/enchant
            end
            if needSwap then
                local itemID = getItemIDFromLink(link)
                if itemID then
                    -- The bags first, then the bank -- and the bank only while it is
                    -- open. A piece lying in the bank was counted as missing until
                    -- now, which meant standing AT the bank and still being told the
                    -- set could not be equipped. The cursor route is the same one a
                    -- drag from the bank onto a paper-doll slot takes -- and that the
                    -- server really allows that out of a BANK slot is measured now
                    -- rather than assumed: tried in the game on 06.08.2026, it
                    -- equips. No detour over the bags is needed, so none is built.
                    local bag, bagSlot = findItemInBags(itemID, want, wantExact)
                    local viaBank = false
                    if not bag then
                        bag, bagSlot = findItemInBank(itemID, want, wantExact)
                        viaBank = bag and true or false
                    end
                    local usable = bag and bagSlot
                    if exactOnly and usable then
                        local foundLink = GetContainerItemLink and GetContainerItemLink(bag, bagSlot)
                        if itemExact(foundLink) ~= wantExact then
                            -- The equipped piece is the set's piece, only regemmed; without an exact copy, leave it alone and report nothing.
                            usable = false
                        end
                    end
                    if usable then
                        local ok = ns:EquipBagItemToSlot(bag, bagSlot, slot)
                        -- The fallback is for BAG slots only. On a bank slot
                        -- UseContainerItem does not equip anything -- it MOVES the
                        -- item into the bags -- so counting it as swapped would
                        -- report an equip that never happened and leave the piece
                        -- lying in a bag.
                        if not ok and not viaBank and UseContainerItem then
                            ok = pcall(UseContainerItem, bag, bagSlot)
                        end
                        if ok then
                            swapped = swapped + 1
                            if viaBank then fromBank = fromBank + 1 end
                        else
                            missing = missing + 1; failedLinks[#failedLinks + 1] = link
                        end
                    elseif not exactOnly then
                        missing = missing + 1
                        failedLinks[#failedLinks + 1] = link
                    end
                end
            end
        end
    end

    -- Anzeige von Helm und Umhang gehoert zum Set: nur angefasst, wenn das
    -- Set einen Wunsch hat, und nur geschrieben, wenn er noch nicht gilt.
    if ShowHelm and loadout.helm then
        local want = (loadout.helm == "show")
        if not ShowingHelm or ShowingHelm() ~= want then ShowHelm(want) end
    end
    if ShowCloak and loadout.cloak then
        local want = (loadout.cloak == "show")
        if not ShowingCloak or ShowingCloak() ~= want then ShowCloak(want) end
    end

    if swapped > 0 then
        if missing > 0 then
            ns:Print(string.format(L["Loadout '%s' equipped (%d swapped, %d missing from bags)."],
                name, swapped, missing))
        else
            ns:Print(string.format(L["Loadout '%s' equipped (%d items swapped)."], name, swapped))
        end
    elseif missing > 0 then
        ns:Print(string.format(L["Loadout '%s': %d items missing from bags, nothing swapped."],
            name, missing))
    else
        ns:Print(string.format(L["Loadout '%s' already equipped."], name))
    end

    -- Its own line rather than a fourth wording of the summary above: the three
    -- there are already translated nine times over, and this one is additional
    -- information, not a different outcome.
    if fromBank > 0 then
        ns:Print(string.format(L["%d of them came out of the bank."], fromBank))
    end

    if bagsFull then
        ns:Print(L["Not enough free bag space to unequip everything."])
    end

    for _, flink in ipairs(failedLinks) do
        local a = itemAvailability(flink)
        local whereTxt
        if a == "bank" then
            -- With the bank open the piece was reachable and the attempt still
            -- failed; with it closed there is something the player can do about
            -- it, so say so instead of only naming the place.
            whereTxt = _bankOpen and L["in the bank"]
                or L["in the bank — open the bank window to equip it"]
        elseif a == "bags" or a == "equipped" then
            whereTxt = L["in bags, equip failed"]
        else
            whereTxt = L["not found"]
        end
        DEFAULT_CHAT_FRAME:AddMessage("    |cffff5555-|r " .. (flink or "?")
            .. "  |cff888888(" .. whereTxt .. ")|r")
    end
end

local function listLoadouts()
    local names = sortedLoadoutNames()
    if #names == 0 then
        ns:Print(L["No loadouts saved yet."])
        return
    end
    ns:Print(L["Saved loadouts:"])
    for _, name in ipairs(names) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  |cffffd100%s|r (%d %s)",
            name, countSlots(LO()[name]), L["items"]))
    end
end

-- Forward declaration: the rename popup below captures it, but the function
-- itself needs sidebarSelected/refreshSidebar, which are declared further down.
local renameLoadout

ns.OnLocaleReady(function()
StaticPopupDialogs["VCUI_LOADOUT_SAVE"] = {
    text = L["Save current equipment as a new loadout. Enter name:"],
    button1 = SAVE or L["Save"],
    button2 = CANCEL or L["Cancel"],
    hasEditBox = true,
    maxLetters = 32,
    OnAccept = function(self)
        -- newer clients expose the box as .EditBox, older as .editBox
        local eb = ns.PopupEditBox(self)
        saveAs(eb and eb:GetText() or "", _pendingSaveSlots)
        _pendingSaveSlots = nil
    end,
    EditBoxOnEnterPressed = function(self)
        saveAs(self:GetText(), _pendingSaveSlots)
        _pendingSaveSlots = nil
        self:GetParent():Hide()
    end,
    OnCancel = function() _pendingSaveSlots = nil end,
    EditBoxOnEscapePressed = function(self)
        _pendingSaveSlots = nil
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["VCUI_LOADOUT_DELETE"] = {
    text = L["Delete loadout '%s'?"],
    button1 = YES or L["Yes"],
    button2 = NO  or L["No"],
    OnAccept = function(_, data) deleteLoadout(data) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- data arrives as the FOURTH StaticPopup_Show argument, not assigned after the
-- fact like the delete popup does it -- OnShow prefills the box and runs
-- inside StaticPopup_Show, before any late assignment would land.
StaticPopupDialogs["VCUI_LOADOUT_RENAME"] = {
    text = L["Rename loadout '%s'. Enter new name:"],
    button1 = SAVE or L["Save"],
    button2 = CANCEL or L["Cancel"],
    hasEditBox = true,
    maxLetters = 32,
    OnShow = function(self)
        local eb = ns.PopupEditBox(self)
        if eb then eb:SetText(self.data or ""); eb:HighlightText() end
    end,
    OnAccept = function(self)
        local eb = ns.PopupEditBox(self)
        renameLoadout(self.data, eb and eb:GetText() or "")
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        renameLoadout(parent.data, self:GetText())
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
end)

ns:RegisterSlash({ key = "LOADOUT", commands = { "/loadout", "/lo" },
    desc = "Gear sets: equip, save, delete, list.",
    module = "loadouts",
})
ns.Slash.LOADOUT = function(msg)
    msg = msg or ""
    local cmd, arg = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "save" then
        saveAs(arg)
    elseif cmd == "equip" or cmd == "" then
        if arg ~= "" then
            equipLoadout(arg)
        else
            ns:Print(L["Usage: /loadout equip <name> | save <name> | delete <name> | list"])
        end
    elseif cmd == "spec" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9b6cff[Loadouts spec debug]|r")
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  talent groups supported = %s", tostring(ns:HasTalentGroups())))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  active talent group     = %s", tostring(ns:ActiveTalentGroup())))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  specSwitchEnabled       = %s", tostring(mod.db.specSwitchEnabled)))
        local anyMap = false
        for name, g in pairs(specMap() or {}) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  mapping: '%s' -> spec %d", name, g))
            anyMap = true
        end
        if not anyMap then
            DEFAULT_CHAT_FRAME:AddMessage("  |cffff8800No spec bindings set — bind a set to a spec in the settings.|r")
        end
        if mod._forceSpecCheck then mod._forceSpecCheck() end
    elseif cmd == "delete" or cmd == "del" or cmd == "remove" or cmd == "rm" then
        if arg == "" then
            ns:Print(L["Usage: /loadout delete <name>"])
        elseif mod.db.confirmDelete then
            local dlg = StaticPopup_Show("VCUI_LOADOUT_DELETE", arg)
            if dlg then dlg.data = arg end
        else
            deleteLoadout(arg)
        end
    elseif cmd == "list" or cmd == "ls" then
        listLoadouts()
    elseif cmd == "import" then
        if mod.ImportLegacy then mod.ImportLegacy() end
    elseif cmd == "debug" then
        if mod._debugSizes then mod._debugSizes() else ns:Print("Sidebar not created yet.") end
    elseif cmd == "tune" then
        local which, valStr = arg:match("^(%S+)%s*(%-?%d*)$")
        local val = tonumber(valStr)
        if which == "top" and val then
            mod.db.sidebarTopOffset = val
            if mod._reanchorSidebar then mod._reanchorSidebar() end
            ns:Print(string.format("Sidebar top offset = %d", val))
        elseif which == "bottom" and val then
            mod.db.sidebarBottomOffset = val
            if mod._reanchorSidebar then mod._reanchorSidebar() end
            ns:Print(string.format("Sidebar bottom offset = %d", val))
        elseif which == "reset" then
            mod.db.sidebarTopOffset = 0
            mod.db.sidebarBottomOffset = 0
            if mod._reanchorSidebar then mod._reanchorSidebar() end
            ns:Print("Sidebar offsets reset to 0.")
        else
            ns:Print("Usage: /loadout tune top <n> | tune bottom <n> | tune reset")
        end
    else
        if LO()[msg] then
            equipLoadout(msg)
        else
            ns:Print(L["Usage: /loadout equip <name> | save <name> | delete <name> | list"])
        end
    end
end

local mmBtn

local function updateMinimapPos()
    if not mmBtn then return end
    local angle = (mod.db.minimap and mod.db.minimap.angle) or -45
    local rad = math.rad(angle)
    local r = 80
    local x = r * math.cos(rad)
    local y = r * math.sin(rad)
    mmBtn:ClearAllPoints()
    mmBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Forward declaration: showLoadoutMenu closes over this before it is defined below.
local openLoadoutsSettings

local function showLoadoutMenu(anchor)
    local entries = {
        { title = true, text = L["Loadouts"] },
    }

    local names = sortedLoadoutNames()
    if #names == 0 then
        table.insert(entries, { text = "  " .. L["No loadouts saved yet."], disabled = true })
    else
        for _, name in ipairs(names) do
            local capturedName = name
            table.insert(entries, {
                text = "  " .. name,
                func = function() equipLoadout(capturedName) end,
            })
        end
    end

    table.insert(entries, { separator = true })
    table.insert(entries, { text = L["Save current as new..."], func = function() promptSaveWithSlots(nil) end })
    table.insert(entries, { text = L["Save trinkets only..."],  func = function() promptSaveWithSlots(SLOT_GROUPS.trinkets) end })
    table.insert(entries, { text = L["Save weapons only..."],   func = function() promptSaveWithSlots(SLOT_GROUPS.weapons)  end })
    table.insert(entries, { separator = true })
    table.insert(entries, { text = L["Settings..."],
        func = function() openLoadoutsSettings() end })

    ns:ShowPopupMenu(entries, anchor)
end

function openLoadoutsSettings()
    if ns.OpenConfig then
        ns:OpenConfig("loadouts")
    elseif ns.UI and ns.UI.ToggleMainFrame then
        ns.UI:ToggleMainFrame()
    end
end

local function createMinimapButton()
    if mmBtn then return end
    if not Minimap then return end

    -- Sizes/offsets below are the standard minimap-button layout; changing them misaligns the border.
    mmBtn = CreateFrame("Button", "VCUI_LoadoutsMinimapButton", Minimap)
    mmBtn:SetFrameStrata("MEDIUM")
    mmBtn:SetFrameLevel(8)
    mmBtn:SetSize(31, 31)
    mmBtn:SetMovable(true)
    mmBtn:RegisterForClicks("AnyUp")
    mmBtn:RegisterForDrag("LeftButton")

    local background = mmBtn:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = mmBtn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Chest_Plate06")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = mmBtn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)

    mmBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    mmBtn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            if not mx then return end
            local sx, sy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale() or 1
            sx, sy = sx / scale, sy / scale
            local angle = math.deg(math.atan2(sy - my, sx - mx))
            mod.db.minimap = mod.db.minimap or {}
            mod.db.minimap.angle = angle
            updateMinimapPos()
        end)
    end)
    mmBtn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    mmBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            showLoadoutMenu(self)
        elseif button == "RightButton" then
            openLoadoutsSettings()
        end
    end)

    ns.UI:AttachTooltip(mmBtn, {
        anchor = "ANCHOR_LEFT",
        title  = (ns.C and ns.C.accent or "|cff9b6cff") .. L["Loadouts"] .. "|r",
        lines  = {
            { L["Left-click: switch set"], 1, 1, 1 },
            { L["Right-click: settings"],  1, 1, 1 },
            { L["Drag: reposition"],     0.6, 0.6, 0.6 },
        },
    })

    updateMinimapPos()

    if mod.db.minimap and mod.db.minimap.hidden then
        mmBtn:Hide()
    end
end

local function applyMinimapVisibility()
    if not mmBtn then return end
    if mod.db.minimap and mod.db.minimap.hidden then
        mmBtn:Hide()
    else
        mmBtn:Show()
    end
end

local _lastForm = -1

local function getCurrentForm()
    if not GetShapeshiftForm then return 0 end
    return GetShapeshiftForm() or 0
end

-- The old code read the name out of GetShapeshiftFormInfo. That tuple is
-- texture, isActive, isCastable on these clients - there is no name in it, so
-- the check never passed and every entry fell through to "Form 1", "Form 2",
-- ... which is useless for picking one. Reminders.lua documents the same tuple.
-- The tooltip is the only place the name exists.
local formTip = CreateFrame("GameTooltip", "VCUILoadoutFormTip", nil, "GameTooltipTemplate")
formTip:SetOwner(UIParent, "ANCHOR_NONE")

local function getFormName(formIdx)
    if formIdx == 0 then return L["No Form"] end
    if formTip.SetShapeshift then
        formTip:ClearLines()
        if pcall(formTip.SetShapeshift, formTip, formIdx) then
            local fs = _G["VCUILoadoutFormTipTextLeft1"]
            local txt = fs and fs:GetText()
            if type(txt) == "string" and txt ~= "" then return txt end
        end
    end
    return string.format(L["Form %d"], formIdx)
end

local function onShapeshiftChange()
    if not mod._enabled or not mod.db then return end
    if not mod.db.autoSwitchEnabled then return end
    if InCombatLockdown() then return end

    local currentForm = getCurrentForm()
    if currentForm == _lastForm then return end
    _lastForm = currentForm

    -- formMapping is keyed by loadout name -> form index, so this is a reverse lookup.
    if not formMap() then return end
    for loadoutName, formIdx in pairs(formMap()) do
        if formIdx == currentForm and LO()[loadoutName] then
            equipLoadout(loadoutName)
            return
        end
    end
end

local _lastSpecGroup = -1

-- These asked the deprecated talent globals directly. C_SpecializationInfo is
-- the supported way to ask now, and it answers first below -- but the old
-- globals are NOT gone on this client, so they stay as a second source rather
-- than being written off.
--
-- Corrected 28.07.2026: an earlier note here claimed GetNumTalentGroups did not
-- exist. `/loadout spec` on a live TBC Anniversary client printed 2, so it
-- exists and answers. Do not delete a fallback on the strength of a source
-- reading when the running client can simply be asked.
local function getActiveSpecGroup()
    return ns:ActiveTalentGroup()
end

-- Both sources (the supported call, then the deprecated global that demonstrably
-- still answers) now live in Core/TalentOverrides.lua, because the talent-group
-- buttons need the same count and two copies drift.
local function getNumSpecGroups()
    return ns:NumTalentGroups()
end

local function getSpecGroupLabel(group)
    -- "Talent group 2 (Shadow)", or just the number while talent data is not
    -- loaded. Same wording the override groups use, so the two features do not
    -- name the same thing two ways.
    return ns:TalentGroupText(group)
end

local function onTalentChange()
    if not mod._enabled or not mod.db then return end
    if not mod.db.specSwitchEnabled then return end
    if InCombatLockdown() then return end

    local currentGroup = getActiveSpecGroup()
    if currentGroup == _lastSpecGroup then return end
    _lastSpecGroup = currentGroup

    if not specMap() then return end
    for loadoutName, groupIdx in pairs(specMap()) do
        if groupIdx == currentGroup and LO()[loadoutName] then
            equipLoadout(loadoutName)
            return
        end
    end
end

mod._forceSpecCheck = function()
    _lastSpecGroup = -1
    onTalentChange()
end

-- Required fallback: some Anniversary builds never fire ACTIVE_TALENT_GROUP_CHANGED.
local _specPoller
local function startSpecPolling()
    if _specPoller or not (C_Timer and C_Timer.NewTicker) then return end
    _specPoller = C_Timer.NewTicker(2, function()
        if not mod._enabled or not mod.db or not mod.db.specSwitchEnabled then return end
        if InCombatLockdown() then return end
        local g = getActiveSpecGroup()
        if g ~= _lastSpecGroup then
            onTalentChange()
        end
    end)
end

local sidebar
local sidebarSetButtons = {}
local sidebarItemRows   = {}
local sidebarSelected
local sidebarExpanded
local refreshSidebar  -- forward declaration; assigned far below, captured by closures above it

-- Rename moves every name-keyed reference along: the entry itself, the talent
-- binding and the form binding (both keyed by the set NAME) and the sidebar
-- selection. The entry table moves untouched, so icon, creation date and
-- slots survive. Declared as a local up at the popup block; defined here
-- because it needs the two sidebar locals above.
renameLoadout = function(oldName, newName)
    newName = (newName or ""):match("^%s*(.-)%s*$")
    if newName == "" then
        ns:Print(L["Please provide a name for the loadout."])
        return
    end
    if newName == oldName then return end
    local set = LO()[oldName]
    if not set then
        ns:Print(string.format(L["Loadout '%s' does not exist."], oldName))
        return
    end
    if LO()[newName] then
        ns:Print(string.format(L["A loadout named '%s' already exists."], newName))
        return
    end
    LO()[newName], LO()[oldName] = set, nil
    local sm = specMap()
    if sm[oldName] ~= nil then sm[newName], sm[oldName] = sm[oldName], nil end
    local fm = formMap()
    if fm[oldName] ~= nil then fm[newName], fm[oldName] = fm[oldName], nil end
    if sidebarSelected == oldName then sidebarSelected = newName end
    _setIndexDirty = true
    if refreshSidebar then refreshSidebar() end
    -- The options page lists the sets by name too; rebuilt only when it is
    -- the page currently on show, else the next open rebuilds anyway.
    if ns.UI and ns.UI.BuildOptionsPage and ns.UI.currentModule == "loadouts" then
        ns.UI:BuildOptionsPage("loadouts", ns.UI.currentTab)
    end
    ns:Print(string.format(L["Loadout '%s' renamed to '%s'."], oldName, newName))
end

local function showSlotReplacePicker(loadoutName, targetSlot, anchor)
    if not ns.ScanBagsForSlot then
        ns:Print(L["SlotPicker module is required for editing item slots."])
        return
    end

    local GetContainerItemLink_ = (C_Container and C_Container.GetContainerItemLink) or _G.GetContainerItemLink

    local candidates = {}
    local seenItemID = {}

    local function addCandidate(link, label)
        if not link then return end
        local itemID = tonumber(link:match("item:(%d+)"))
        if not itemID or seenItemID[itemID] then return end
        seenItemID[itemID] = true
        table.insert(candidates, { link = link, label = label })
    end

    local currentLink = GetInventoryItemLink("player", targetSlot)
    if currentLink then
        local name = currentLink:match("|h%[(.-)%]|h") or currentLink
        addCandidate(currentLink, name .. " |cff66ff66" .. L["(equipped)"] .. "|r")
    end

    local PAIRS = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }
    local pairedSlot = PAIRS[targetSlot]
    if pairedSlot then
        local pairedLink = GetInventoryItemLink("player", pairedSlot)
        if pairedLink then
            local name = pairedLink:match("|h%[(.-)%]|h") or pairedLink
            addCandidate(pairedLink, name .. " |cff8888ffin " .. (SLOT_NAMES[pairedSlot] or "?") .. "|r")
        end
    end

    local bagResults = ns:ScanBagsForSlot(targetSlot)
    for _, entry in ipairs(bagResults) do
        local link = GetContainerItemLink_ and GetContainerItemLink_(entry.bag, entry.slot)
        if link then
            local name = link:match("|h%[(.-)%]|h") or link
            addCandidate(link, name)
        end
    end

    local slotName = SLOT_NAMES[targetSlot] or ("Slot " .. targetSlot)
    local entries  = {
        { title = true, text = string.format(L["Replace: %s"], slotName) },
    }

    if #candidates == 0 then
        table.insert(entries, { text = L["No matching items in your bags."], disabled = true })
    else
        for _, c in ipairs(candidates) do
            local capturedLink = c.link
            table.insert(entries, {
                text = "  " .. c.label,
                func = function()
                    if LO()[loadoutName] then
                        LO()[loadoutName].slots[targetSlot] = capturedLink
                        refreshSidebar()
                        ns:Print(string.format(L["Loadout '%s': slot updated."], loadoutName))
                    end
                end,
            })
        end
    end

    table.insert(entries, { separator = true })
    table.insert(entries, { text = L["Remove from set"], func = function()
        if LO()[loadoutName] then
            LO()[loadoutName].slots[targetSlot] = nil
            refreshSidebar()
        end
    end })

    ns:ShowPopupMenu(entries, anchor)
end

local function getSetIcon(name)
    local loadout = mod.db and LO() and LO()[name]
    if not loadout or not loadout.slots then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    if loadout.iconOverride then return loadout.iconOverride end
    if GetItemInfoInstant then
        for _, link in pairs(loadout.slots) do
            if type(link) == "string" then
                local _, _, _, _, icon = GetItemInfoInstant(link)
                if icon then return icon end
            end
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- =========================================================
-- Window style
--
-- Every window of this module -- the sidebar and the icon picker -- follows the
-- character panel's own style setting (user request, 02.08.2026).
-- =========================================================

-- Which look they wear. File scope on purpose: the layout code below runs long
-- before any of these frames exist and has to read the same answer.
local function sidebarClassic()
    local cp = ns.modules and ns.modules.characterpanel
    return not cp or not cp.db or (cp.db.style or "classic") == "classic"
end

-- Extra padding the style's frame needs on the inside. Blizzard's dialog border
-- is 32 pixels of artwork against a single-pixel edge, so without the surcharge
-- the first column of icons and both header buttons sit ON the frame.
local function sidebarInset()
    return sidebarClassic() and 8 or 0
end

-- Usable width; the frame of the style is added on top of it, never taken out.
local SIDEBAR_WIDTH = 190

-- Only the BORDER of the classic look comes from Blizzard. Its matching
-- background texture is not drawn on this client -- the window stayed
-- see-through -- so the ground is a white texture tinted dark by hand.
--
-- The insets say where that ground STOPS, measured from the frame's own edge,
-- and they have to land on the border's visible inner line. The dialog border is
-- 32 pixels of art, and its ornate line does not sit at the outer pixel: there
-- is roughly a dozen pixels of margin in front of it. At 5 the ground therefore
-- stopped OUTSIDE the line and stood out past the frame on every side (reported
-- with a screenshot, 03.08.2026). 11/12 is the pairing Blizzard itself uses with
-- this exact art at this exact edge size, and it is asymmetric on purpose --
-- the artwork is.
--
-- The number cannot simply be raised further: past the line the ground pulls
-- away from the border and a gap opens that one looks through. It belongs ON
-- the line, not merely inside it.
local WINDOW_BACKDROPS = {
    modern = {
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    },
    classic = {
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    },
}

-- Both looks run through SetBackdrop, so a style switch is a second call on the
-- same frame -- nothing is rebuilt and no /reload is needed.
--
-- Neither look carries a drop shadow any more; see where it used to be created.
local function styleWindow(frame)
    if not frame or not frame.SetBackdrop then return end
    if sidebarClassic() then
        frame:SetBackdrop(WINDOW_BACKDROPS.classic)
        frame:SetBackdropColor(0.05, 0.05, 0.06, 0.95)
        -- the border texture brings its own colour; tinting it greys it out
        frame:SetBackdropBorderColor(1, 1, 1, 1)
    else
        local bg = ns.COLORS.bg
        local bd = ns.COLORS.accentDim or ns.COLORS.border
        frame:SetBackdrop(WINDOW_BACKDROPS.modern)
        frame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
        frame:SetBackdropBorderColor(bd.r, bd.g, bd.b, bd.a or 1)
    end
end

-- Handed out so anything that DOCKS onto these windows wears the same material
-- instead of keeping its own copy of the recipe. The socket strip under the
-- sidebar is the first taker: a copy there would have drifted the first time one
-- of the two numbers above changed. The inset travels with it, because the
-- classic look grows the frame by its border and the content has to move in by
-- the same amount or it sits on the artwork.
ns.StyleLoadoutsWindow = styleWindow
ns.LoadoutsWindowInset = sidebarInset

local _iconPicker
local _iconBtns = {}
local ICON_SIZE = 30
local ICON_COLS = 6
local ICON_ROWS = 8
local ICON_PAD  = 3
local _iconScroll = 0

local GENERIC_ICONS = {
    "Interface\\Icons\\Spell_Holy_PowerWordShield",
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    "Interface\\Icons\\Spell_Holy_HolyBolt",
    "Interface\\Icons\\Spell_Nature_Lightning",
    "Interface\\Icons\\Ability_Warrior_OffensiveStance",
    "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    "Interface\\Icons\\Ability_Rogue_Sprint",
    "Interface\\Icons\\Spell_Frost_FrostBolt02",
    "Interface\\Icons\\Spell_Fire_FlameBolt",
    "Interface\\Icons\\Spell_Nature_HealingTouch",
    "Interface\\Icons\\INV_Sword_27",
    "Interface\\Icons\\INV_Shield_06",
    "Interface\\Icons\\INV_Misc_Gem_Diamond_03",
    "Interface\\Icons\\Achievement_PVP_A_A",
}

local _libraryIcons

-- The client's full macro icon library, built once the way Blizzard's own
-- icon provider does it (loose string paths first, then numeric file ids;
-- both are valid SetTexture arguments and valid table keys for the dedupe).
-- Bare loose filenames carry no folder, so they get the icons path put on.
local function libraryIcons()
    if _libraryIcons then return _libraryIcons end
    if not GetMacroIcons or not GetMacroItemIcons then
        _libraryIcons = {}
        return _libraryIcons
    end

    local t1, t2 = {}, {}
    if GetLooseMacroIcons then GetLooseMacroIcons(t1) end
    GetMacroIcons(t1)
    if GetLooseMacroItemIcons then GetLooseMacroItemIcons(t2) end
    if GetMacroItemIcons then GetMacroItemIcons(t2) end

    local prefix = "Interface\\Icons\\"
    local seen = {}
    _libraryIcons = {}
    for _, source in ipairs({ t1, t2 }) do
        for _, v in ipairs(source) do
            if type(v) == "string" and not v:find("\\", 1, true) then
                v = prefix .. v
            end
            if not seen[v] then
                seen[v] = true
                table.insert(_libraryIcons, v)
            end
        end
    end
    return _libraryIcons
end

local function getIconPickerButton(idx)
    local b = _iconBtns[idx]
    if b then return b end
    b = CreateFrame("Button", nil, _iconPicker)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(b)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(b)
    b.hl:SetColorTexture(0.4, 0.3, 0.6, 0.4)
    b:RegisterForClicks("LeftButtonUp")
    _iconBtns[idx] = b
    return b
end

-- Fixed window of ICON_COLS x ICON_ROWS pooled buttons over the icon list at
-- the current wheel offset -- the library holds thousands of entries, so the
-- pool never grows past one view and scrolling only remaps textures.
local function layoutIconPicker()
    local icons = _iconPicker._icons
    local inset = _iconPicker._inset
    local hover = _iconPicker._hoverColor
    local startY = _iconPicker._startY

    for cell = 1, ICON_COLS * ICON_ROWS do
        local col = (cell - 1) % ICON_COLS
        local visRow = math.floor((cell - 1) / ICON_COLS)
        local srcIndex = (visRow + _iconScroll) * ICON_COLS + col + 1
        local entry = icons[srcIndex]
        local b = getIconPickerButton(cell)
        if entry then
            b.hl:SetColorTexture(hover[1], hover[2], hover[3], hover[4])
            b:Show()
            if entry.isAuto then
                b.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                b.tex:SetVertexColor(0.7, 0.7, 0.7)
                b._iconValue = nil
            else
                b.tex:SetTexture(entry.tex)
                b.tex:SetVertexColor(1, 1, 1)
                b._iconValue = entry.tex
            end
            b:SetScript("OnClick", _iconPicker.onSwatchClick)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", _iconPicker, "TOPLEFT",
                6 + inset + col * (ICON_SIZE + ICON_PAD),
                -(startY + inset + visRow * (ICON_SIZE + ICON_PAD)))
        else
            b:Hide()
        end
    end
end

local function showIconPicker(loadoutName, anchor)
    _iconScroll = 0
    local loadout = LO()[loadoutName]
    if not loadout then return end

    if not _iconPicker then
        _iconPicker = CreateFrame("Frame", "VCUI_LoadoutIconPicker", UIParent,
            BackdropTemplateMixin and "BackdropTemplate")
        _iconPicker:SetFrameStrata("FULLSCREEN_DIALOG")
        _iconPicker:Hide()
        _iconPicker:EnableMouse(true)
        _iconPicker:SetClampedToScreen(true)
        tinsert(UISpecialFrames, "VCUI_LoadoutIconPicker")
        _iconPicker.title = _iconPicker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        _iconPicker.title:SetJustifyH("LEFT")
        _iconPicker.title:SetWordWrap(false)
        _iconPicker.title:SetTextColor(1, 0.82, 0)

        -- Same close control every other window in this addon carries: grey
        -- cross, red field under the pointer. Escape already closed this frame
        -- through UISpecialFrames, but nothing on it said so.
        local closeBtn = CreateFrame("Button", nil, _iconPicker)
        closeBtn:SetSize(20, 18)

        local closeBG = closeBtn:CreateTexture(nil, "BACKGROUND")
        closeBG:SetAllPoints(closeBtn)
        closeBG:SetColorTexture(0.78, 0.16, 0.16, 1)
        closeBG:Hide()

        local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        ns.UI.Font(closeText, 18)
        closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
        closeText:SetText("×")
        closeText:SetTextColor(0.7, 0.7, 0.7)
        closeBtn:SetScript("OnEnter", function()
            closeBG:Show(); closeText:SetTextColor(1, 1, 1)
        end)
        closeBtn:SetScript("OnLeave", function()
            closeBG:Hide(); closeText:SetTextColor(0.7, 0.7, 0.7)
        end)
        closeBtn:SetScript("OnClick", function() _iconPicker:Hide() end)
        _iconPicker.closeBtn = closeBtn

        -- One handler for every swatch, installed once. It used to be a fresh
        -- closure per button on every open, which meant a new function for each
        -- of the twenty-odd icons each time the picker was raised.
        _iconPicker.onSwatchClick = function(self)
            local lo = _iconPicker._loadout
            if lo then lo.iconOverride = self._iconValue end
            _iconPicker:Hide()
            refreshSidebar()
        end

        _iconPicker:EnableMouseWheel(true)
        _iconPicker:SetScript("OnMouseWheel", function(_, delta)
            local icons = _iconPicker._icons or {}
            local maxRow = math.max(0, math.ceil(#icons / ICON_COLS) - ICON_ROWS)
            _iconScroll = _iconScroll - delta * 3
            if _iconScroll < 0 then
                _iconScroll = 0
            elseif _iconScroll > maxRow then
                _iconScroll = maxRow
            end
            layoutIconPicker()
        end)
    end

    -- Which set the swatches write to. One picker, one set at a time.
    _iconPicker._loadout = loadout

    -- Skin and padding hang off the style, so they are set on every open rather
    -- than once at build time -- and through the hook below even while the
    -- window stands open.
    styleWindow(_iconPicker)
    local inset = sidebarInset()
    _iconPicker._restyle = function()
        if _iconPicker:IsShown() then showIconPicker(loadoutName, anchor) end
    end

    _iconPicker.title:ClearAllPoints()
    _iconPicker.title:SetPoint("TOPLEFT", _iconPicker, "TOPLEFT", 8 + inset, -(6 + inset))
    -- Pinned on both sides so a long set name is cut instead of running
    -- under the close control.
    _iconPicker.title:SetPoint("TOPRIGHT", _iconPicker, "TOPRIGHT", -(24 + inset), -(6 + inset))
    _iconPicker.closeBtn:ClearAllPoints()
    _iconPicker.closeBtn:SetPoint("TOPRIGHT", _iconPicker, "TOPRIGHT", -(2 + inset), -(2 + inset))

    _iconPicker.title:SetText(string.format(L["Icon for: %s"], loadoutName))

    local icons = {}
    local seen  = {}
    table.insert(icons, { isAuto = true })
    if GetItemInfoInstant and loadout.slots then
        local slots = {}
        for s in pairs(loadout.slots) do table.insert(slots, s) end
        table.sort(slots)
        for _, s in ipairs(slots) do
            local slotLink = loadout.slots[s]
            if type(slotLink) == "string" then
                local _, _, _, _, ic = GetItemInfoInstant(slotLink)
                if ic and not seen[ic] then
                    seen[ic] = true
                    table.insert(icons, { tex = ic })
                end
            end
        end
    end
    for _, ic in ipairs(GENERIC_ICONS) do
        if not seen[ic] then
            seen[ic] = true
            table.insert(icons, { tex = ic })
        end
    end
    for _, ic in ipairs(libraryIcons()) do
        if not seen[ic] then
            seen[ic] = true
            table.insert(icons, { tex = ic })
        end
    end

    for _, b in ipairs(_iconBtns) do b:Hide() end

    -- Hover backing follows the style for the same reason the selected row does:
    -- on Blizzard's gold frame our purple reads as a second accent.
    local hoverR, hoverG, hoverB, hoverA = 0.4, 0.3, 0.6, 0.4
    if sidebarClassic() then hoverR, hoverG, hoverB, hoverA = 0.42, 0.34, 0.12, 0.40 end

    local startY = 24
    _iconPicker._icons = icons
    _iconPicker._inset = inset
    _iconPicker._hoverColor = { hoverR, hoverG, hoverB, hoverA }
    _iconPicker._startY = startY
    layoutIconPicker()

    -- The window GROWS by the frame it wears instead of losing the room to it:
    -- the six columns have to fit either way.
    local numRows = math.ceil(#icons / ICON_COLS)
    if #icons > ICON_COLS * ICON_ROWS then numRows = ICON_ROWS end
    _iconPicker:SetSize(
        ICON_COLS * (ICON_SIZE + ICON_PAD) + 12 + inset * 2,
        startY + numRows * (ICON_SIZE + ICON_PAD) + 8 + inset * 2)

    _iconPicker:ClearAllPoints()
    if anchor and anchor.GetLeft then
        _iconPicker:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
    else
        _iconPicker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    _iconPicker:Show()
end

-- Repaints the backing of every row that already exists. The rows are pooled in
-- sidebarSetButtons, so a style switch reaches the ones built before it too --
-- without this, only rows created afterwards would change colour.
function mod._repaintSidebarRows()
    for _, b in pairs(sidebarSetButtons) do
        if b._paintSelection then b._paintSelection() end
    end
end

-- Ziehen zum Umsortieren: _dragName ist gesetzt, solange eine Zeile am
-- Mauszeiger haengt. Geist und Linie werden faul gebaut und wiederverwendet.
local _dragName, _dragGhost, _dragLine

local function visibleSetRows()
    local rows = {}
    for _, b in ipairs(sidebarSetButtons) do
        if b:IsShown() then table.insert(rows, b) end
    end
    return rows
end

-- Einfuegeposition aus den Y-Mitten der SET-Zeilen; ausgeklappte Item-Zeilen
-- sind bewusst keine Ziele, die Luecke unter ihnen gehoert zur Zeile darueber.
local function dragInsertIndex()
    local scale = sidebar:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    cy = cy / scale
    local rows = visibleSetRows()
    for i, b in ipairs(rows) do
        local top, bottom = b:GetTop(), b:GetBottom()
        if top and bottom and cy > (top + bottom) / 2 then return i end
    end
    return #rows + 1
end

local function ensureDragGhost()
    if _dragGhost then return _dragGhost end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetSize(150, 28)
    g:SetFrameStrata("TOOLTIP")
    g:SetAlpha(0.6)
    g.icon = g:CreateTexture(nil, "ARTWORK")
    g.icon:SetSize(22, 22)
    g.icon:SetPoint("LEFT", g, "LEFT", 2, 0)
    g.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    g.text = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if ns.UI and ns.UI.Font then ns.UI.Font(g.text, 12) end
    g.text:SetPoint("LEFT", g.icon, "RIGHT", 6, 0)
    g:Hide()
    _dragGhost = g
    return g
end

local function ensureDragLine()
    if _dragLine then return _dragLine end
    local l = sidebar:CreateTexture(nil, "OVERLAY")
    l:SetHeight(2)
    local c = ns.COLORS.accent
    l:SetColorTexture(c.r, c.g, c.b, 0.9)
    l:Hide()
    _dragLine = l
    return l
end

local function updateDragVisual()
    local ghost = ensureDragGhost()
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    ghost:ClearAllPoints()
    ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
        cx / scale + 12, cy / scale - 8)

    local line = ensureDragLine()
    if not sidebar:IsMouseOver() then line:Hide() return end
    local rows = visibleSetRows()
    local idx  = dragInsertIndex()
    line:ClearAllPoints()
    if idx <= #rows then
        -- OBERKANTE der Zielzeile: dort wird eingefuegt
        line:SetPoint("TOPLEFT",  rows[idx], "TOPLEFT",  0, 2)
        line:SetPoint("TOPRIGHT", rows[idx], "TOPRIGHT", 0, 2)
    elseif rows[#rows] then
        -- hinter die letzte Zeile; haengt dort eine Item-Zeile, unter diese
        local anchor = rows[#rows]
        if sidebarExpanded == anchor.setName then
            for _, r in pairs(sidebarItemRows) do
                if r:IsShown() then anchor = r break end
            end
        end
        line:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, -2)
        line:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    end
    line:Show()
end

-- Der Neuaufbau steht NUR im Anwenden-Zweig: der Abbruch-Zweig laesst alles,
-- wie es ist, und darf deshalb auch mitten aus refreshSidebar heraus gerufen
-- werden (Zeilen werden dort versteckt und neu gezeigt), ohne sich im Kreis
-- zu drehen.
local function stopDrag(apply)
    local name = _dragName
    _dragName = nil
    if _dragGhost then _dragGhost:Hide(); _dragGhost:SetScript("OnUpdate", nil) end
    if _dragLine  then _dragLine:Hide() end
    if not name then return end
    if apply and sidebar and sidebar:IsMouseOver() then
        local idx  = dragInsertIndex()
        local rows = visibleSetRows()
        -- idx zaehlt MIT der gezogenen Zeile; fuer moveLoadout zaehlt die
        -- Liste ohne sie, also rueckt hinter ihr alles um eins auf
        for i, b in ipairs(rows) do
            if b.setName == name and i < idx then idx = idx - 1 break end
        end
        moveLoadout(name, idx)
        refreshSidebar()
    end
end

-- Dreistufiger Anzeige-Schalter als Untermenue: Zeigen / Verstecken /
-- Nicht aendern. nil heisst "nicht anfassen" und ist der Standard, damit
-- Sets von vor dem Feature sich exakt wie bisher verhalten.
local function displayToggleEntry(setName, field, label)
    local function option(value, text)
        return {
            text    = text,
            checked = function()
                local lo = LO()[setName]
                return lo and lo[field] == value
            end,
            func = function()
                local lo = LO()[setName]
                if lo then lo[field] = value end
            end,
        }
    end
    return {
        text = label,
        submenu = {
            option("show", L["Show"]),
            option("hide", L["Hide"]),
            option(nil,    L["Don't change"]),
        },
    }
end

local function createSetRow(parent, index)
    local btn = sidebarSetButtons[index]
    if btn then return btn end

    btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(32)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(26, 26)
    btn.icon:SetPoint("LEFT", btn, "LEFT", 4, 0)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.expand = CreateFrame("Button", nil, btn)
    btn.expand:SetSize(18, 18)
    btn.expand:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    -- negative insets enlarge the hit zone; without this near-misses fall through to the row
    btn.expand:SetHitRectInsets(-12, -4, -7, -7)
    btn.expand.icon = btn.expand:CreateTexture(nil, "ARTWORK")
    btn.expand.icon:SetAllPoints(btn.expand)
    btn.expand.icon:SetTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Up")
    btn.expand:SetHighlightTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Highlight")
    btn.expand:SetScript("OnClick", function()
        if sidebarExpanded == btn.setName then
            sidebarExpanded = nil
        else
            sidebarExpanded = btn.setName
        end
        refreshSidebar()
    end)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if ns.UI and ns.UI.Font then ns.UI.Font(btn.text, 12) end
    btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
    btn.text:SetPoint("RIGHT", btn.expand, "LEFT", -4, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetWordWrap(false)

    btn.selection = btn:CreateTexture(nil, "BACKGROUND")
    btn.selection:SetAllPoints(btn)
    btn.selBar = btn:CreateTexture(nil, "ARTWORK")
    btn.selBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    btn.selBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    btn.selBar:SetWidth(3)
    -- Painted through a function rather than baked, so a style switch can
    -- repaint rows that already exist (see RestyleLoadoutsSidebar).
    btn._paintSelection = function()
        -- if/else, NOT `cond and f() or g()`: an and/or expression is truncated
        -- to a SINGLE value, so that form delivered r and left g, b and alpha
        -- nil -- which threw on the first arithmetic further down (error report,
        -- 02.08.2026). A function returning four values may never be called
        -- from inside one.
        local r, g, b2, a
        if mod._sidebarSelectionRGBA then
            r, g, b2, a = mod._sidebarSelectionRGBA()
        else
            -- rows can be built before the sidebar hands its palette over
            local c = ns.COLORS.accent
            r, g, b2, a = c.r, c.g, c.b, 0.30
        end
        if ns.UI and ns.UI.SetGradient then
            ns.UI.SetGradient(btn.selection, "HORIZONTAL",
                r, g, b2, a, r, g, b2, a * 0.13)
        else
            btn.selection:SetColorTexture(r, g, b2, a)
        end
        -- Same hue as the backing, at full strength -- the bar must follow the
        -- style switch too, otherwise the olive Classic+ row keeps a purple edge.
        btn.selBar:SetColorTexture(r, g, b2, 1)
    end
    btn._paintSelection()
    btn.selection:Hide()
    btn.selBar:Hide()

    btn.hl = btn:CreateTexture(nil, "BACKGROUND")
    btn.hl:SetAllPoints(btn)
    btn.hl:SetColorTexture(1, 1, 1, 0.05)
    btn.hl:Hide()

    btn:SetScript("OnEnter", function(self)
        if _dragName then return end
        if not self.isSelected then self.hl:Show() end
        -- Body is a loop over the set's slots, so this opens the tooltip and
        -- fills it by hand -- see UI/Tooltip.lua on why that stays possible.
        ns.UI:OpenTooltip(self, "ANCHOR_LEFT")
        local loadout = LO()[self.setName]
        if loadout then
            GameTooltip:AddLine(self.setName, 1, 0.82, 0)
            GameTooltip:AddLine(string.format("%d %s", countSlots(loadout), L["items"]),
                0.6, 0.6, 0.6)
            local slots = {}
            for s, v in pairs(loadout.slots or {}) do
                if type(v) == "string" then slots[#slots + 1] = s end
            end
            table.sort(slots)
            if #slots > 0 then GameTooltip:AddLine(" ") end
            for _, s in ipairs(slots) do
                local link  = loadout.slots[s]
                local label = SLOT_NAMES[s] or ("Slot " .. s)
                local iname = link and link:match("%[(.-)%]") or "?"
                local a = itemAvailability(link)
                if a == "equipped" or a == "bags" then
                    GameTooltip:AddDoubleLine(label, iname, 0.6, 0.6, 0.6, 0.95, 0.95, 1)
                elseif a == "bank" then
                    GameTooltip:AddDoubleLine(label, iname .. " (" .. L["Bank"] .. ")",
                        0.6, 0.6, 0.6, 1, 0.6, 0.2)
                else
                    GameTooltip:AddDoubleLine(label, iname .. " (" .. L["missing"] .. ")",
                        0.6, 0.6, 0.6, 1, 0.35, 0.35)
                end
            end
            if loadout.helm or loadout.cloak then
                GameTooltip:AddLine(" ")
                if loadout.helm then
                    GameTooltip:AddDoubleLine(L["Helm"],
                        loadout.helm == "show" and L["shown"] or L["hidden"],
                        0.6, 0.6, 0.6, 0.95, 0.95, 1)
                end
                if loadout.cloak then
                    GameTooltip:AddDoubleLine(L["Cloak"],
                        loadout.cloak == "show" and L["shown"] or L["hidden"],
                        0.6, 0.6, 0.6, 0.95, 0.95, 1)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Left-click: select"], 1, 1, 1)
            GameTooltip:AddLine(L["Double-click / Right-click menu: equip"], 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.hl:Hide()
        ns.UI:HideTooltip()
    end)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local setName = self.setName
            local menu = {
                { title = true, text = setName },
                { text = L["Equip"], func = function() equipLoadout(setName) end },
                { text = L["Overwrite"], func = function()
                    overwriteLoadout(setName)
                    refreshSidebar()
                end },
                { text = L["Change icon..."], func = function()
                    showIconPicker(setName, self)
                end },
                { text = L["Rename..."], func = function()
                    -- data as the 4th argument: OnShow prefills from it
                    StaticPopup_Show("VCUI_LOADOUT_RENAME", setName, nil, setName)
                end },
            }

            if ShowHelm and ShowCloak then
                table.insert(menu, displayToggleEntry(setName, "helm",  L["Helm"]))
                table.insert(menu, displayToggleEntry(setName, "cloak", L["Cloak"]))
            end

            if getNumSpecGroups() >= 2 then
                table.insert(menu, { separator = true })
                for g = 1, getNumSpecGroups() do
                    local group = g
                    table.insert(menu, {
                        text    = string.format(L["Bind to %s"], getSpecGroupLabel(group)),
                        checked = function() return specMap() and specMap()[setName] == group end,
                        func    = function()
                            if specMap()[setName] == group then
                                specMap()[setName] = nil
                                ns:Print(string.format(L["'%s' unbound from spec."], setName))
                            else
                                -- bindings are 1:1, so clear any other set on this group
                                for other, gi in pairs(specMap()) do
                                    if gi == group and other ~= setName then specMap()[other] = nil end
                                end
                                specMap()[setName] = group
                                ns:Print(string.format(L["'%s' bound to %s."], setName, getSpecGroupLabel(group)))
                            end
                        end,
                    })
                end
            end

            table.insert(menu, { separator = true })
            table.insert(menu, { text = L["Delete"], func = function()
                if mod.db.confirmDelete then
                    local dlg = StaticPopup_Show("VCUI_LOADOUT_DELETE", setName)
                    if dlg then dlg.data = setName end
                else
                    deleteLoadout(setName)
                    refreshSidebar()
                end
            end })

            ns:ShowPopupMenu(menu, self)
        else
            -- no OnDoubleClick on this button type; detect it by timestamp
            local now = GetTime()
            if self._lastClick and (now - self._lastClick) < 0.35 then
                equipLoadout(self.setName)
                self._lastClick = 0
            else
                sidebarSelected = self.setName
                self._lastClick = now
                refreshSidebar()
            end
        end
    end)

    -- Umsortieren: OnDragStart feuert erst ab Blizzards Zieh-Schwelle, daher
    -- bleiben Klick, Doppelklick und das Rechtsklickmenue davon unberuehrt.
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if not self.setName then return end
        _dragName = self.setName
        ns.UI:HideTooltip()
        local g = ensureDragGhost()
        g.icon:SetTexture(getSetIcon(self.setName))
        g.text:SetText(self.setName)
        g:Show()
        g:SetScript("OnUpdate", updateDragVisual)
        updateDragVisual()
    end)
    btn:SetScript("OnDragStop", function() stopDrag(true) end)

    sidebarSetButtons[index] = btn
    return btn
end

local ITEM_COLS = 6
local ITEM_SIZE = 26
local ITEM_PAD  = 3

local function getItemButton(row, idx)
    local b = row.items[idx]
    if b then return b end
    b = CreateFrame("Button", nil, row)
    b:SetSize(ITEM_SIZE, ITEM_SIZE)
    b.slotBg = b:CreateTexture(nil, "BACKGROUND")
    b.slotBg:SetAllPoints(b)
    b.slotBg:SetColorTexture(0.10, 0.10, 0.13, 0.9)
    b.iconTex = b:CreateTexture(nil, "ARTWORK")
    b.iconTex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.iconTex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.iconBorder = b:CreateTexture(nil, "OVERLAY")
    b.iconBorder:SetAllPoints(b)
    b.iconBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.iconBorder:SetBlendMode("ADD")
    b.iconBorder:Hide()
    b:SetScript("OnEnter", function(self)
        -- One branch pulls an item link into the tooltip, which no spec covers.
        ns.UI:OpenTooltip(self, "ANCHOR_LEFT")
        if self.isAdd then
            GameTooltip:AddLine(L["Add a slot"], 1, 0.82, 0)
            GameTooltip:AddLine(L["Re-adds an ignored slot to this set."], 0.7, 0.7, 0.7)
        elseif self.link then
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
            GameTooltip:AddLine(L["Right-click: remove this slot from the set."], 0.7, 0.7, 0.7)
        else
            local slotName = SLOT_NAMES[self.targetSlot] or ("Slot " .. tostring(self.targetSlot))
            GameTooltip:AddLine(string.format(L["Empty: %s"], slotName), 1, 0.82, 0)
            GameTooltip:AddLine(L["Left-click to pick an item from your bags"], 0.7, 0.7, 0.7)
            GameTooltip:AddLine(L["Right-click: remove this slot from the set."], 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
        self.iconBorder:Show()
    end)
    b:SetScript("OnLeave", function(self)
        ns.UI:HideTooltip()
        self.iconBorder:Hide()
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
        if self.isAdd then
            local lo = self.loadoutName and LO()[self.loadoutName]
            if not lo then return end
            -- union of mask AND stored slots: legacy sets have items but no mask, and
            -- seeding from the mask alone would collapse the set to the one added slot
            local present = {}
            for _, s in ipairs(lo.slotMask or {}) do present[s] = true end
            for s in pairs(lo.slots or {}) do present[s] = true end
            local menu = { { title = true, text = L["Add a slot"] } }
            for _, s in ipairs(EQUIP_SLOTS) do
                if not present[s] then
                    local slotID, loName = s, self.loadoutName
                    table.insert(menu, { text = SLOT_NAMES[s] or ("Slot " .. s), func = function()
                        local lo2 = LO()[loName]
                        if not lo2 then return end
                        if not lo2.slotMask or #lo2.slotMask == 0 then
                            lo2.slotMask = {}
                            for k in pairs(lo2.slots or {}) do
                                table.insert(lo2.slotMask, k)
                            end
                        end
                        table.insert(lo2.slotMask, slotID)
                        table.sort(lo2.slotMask)
                        local cur = GetInventoryItemLink("player", slotID)
                        if cur then lo2.slots[slotID] = cur end
                        _setIndexDirty = true
                        refreshSidebar()
                    end })
                end
            end
            if #menu > 1 then ns:ShowPopupMenu(menu, self) end
            return
        end
        if button == "RightButton" then
            -- must drop the slot from slotMask too, or Overwrite re-captures it
            local lo = self.loadoutName and LO()[self.loadoutName]
            if lo and self.targetSlot then
                lo.slots[self.targetSlot] = nil
                if lo.slotMask then
                    for i = #lo.slotMask, 1, -1 do
                        if lo.slotMask[i] == self.targetSlot then table.remove(lo.slotMask, i) end
                    end
                end
                _setIndexDirty = true
                refreshSidebar()
            end
        else
            if self.loadoutName and self.targetSlot then
                showSlotReplacePicker(self.loadoutName, self.targetSlot, self)
            end
        end
    end)
    row.items[idx] = b
    return b
end

local function getItemRow(parent, index)
    local row = sidebarItemRows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, parent)
    row.items = {}
    sidebarItemRows[index] = row
    return row
end

local EMPTY_SLOT_ICON = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

local function renderItemRow(row, loadoutName)
    local loadout = LO() and LO()[loadoutName]
    if not loadout then
        row:SetHeight(0)
        return
    end

    for _, b in ipairs(row.items) do b:Hide() end

    local displaySlots = loadout.slotMask
    if not displaySlots or #displaySlots == 0 then
        displaySlots = {}
        for slot in pairs(loadout.slots or {}) do
            table.insert(displaySlots, slot)
        end
    end
    local sortedSlots = {}
    for _, s in ipairs(displaySlots) do table.insert(sortedSlots, s) end
    table.sort(sortedSlots)

    for i, slot in ipairs(sortedSlots) do
        local b = getItemButton(row, i)
        local link = loadout.slots and loadout.slots[slot]
        b.loadoutName = loadoutName
        b.targetSlot  = slot
        b.link        = link
        b.isAdd       = nil

        if link then
            local icon
            if GetItemInfoInstant then
                local _, _, _, _, ic = GetItemInfoInstant(link)
                icon = ic
            end
            b.iconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local a = itemAvailability(link)
            if a == "equipped" or a == "bags" then
                b.iconTex:SetVertexColor(1, 1, 1)
                b.iconTex:SetDesaturated(false)
            elseif a == "bank" then
                b.iconTex:SetVertexColor(1, 0.7, 0.35)
                b.iconTex:SetDesaturated(false)
            else
                b.iconTex:SetVertexColor(1, 0.4, 0.4)
                b.iconTex:SetDesaturated(true)
            end
        else
            b.iconTex:SetTexture(EMPTY_SLOT_ICON)
            b.iconTex:SetVertexColor(0.6, 0.6, 0.6)
            b.iconTex:SetDesaturated(false)
        end

        local col = (i - 1) % ITEM_COLS
        local rowIdx = math.floor((i - 1) / ITEM_COLS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", row, "TOPLEFT",
            col * (ITEM_SIZE + ITEM_PAD),
            -(rowIdx * (ITEM_SIZE + ITEM_PAD)))
        b:Show()
    end

    local tiles = #sortedSlots
    if tiles < #EQUIP_SLOTS then
        tiles = tiles + 1
        local b = getItemButton(row, tiles)
        b.loadoutName = loadoutName
        b.targetSlot  = nil
        b.link        = nil
        b.isAdd       = true
        b.iconTex:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
        b.iconTex:SetVertexColor(0.7, 0.7, 0.8)
        b.iconTex:SetDesaturated(false)
        local col = (tiles - 1) % ITEM_COLS
        local rowIdx = math.floor((tiles - 1) / ITEM_COLS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", row, "TOPLEFT",
            col * (ITEM_SIZE + ITEM_PAD),
            -(rowIdx * (ITEM_SIZE + ITEM_PAD)))
        b:Show()
    end

    local rows = math.max(1, math.ceil(tiles / ITEM_COLS))
    row:SetHeight(rows * (ITEM_SIZE + ITEM_PAD) + 2)
end

refreshSidebar = function()
    if not sidebar then return end

    -- Ein Neuaufbau mitten im Ziehen (Taschen-Ereignis waehrend der Maustaste)
    -- versteckt gleich alle Zeilen -- das bricht den Zug clientseitig ab, ohne
    -- dass OnDragStop je feuert. Also hier selbst aufraeumen, sonst blieben
    -- Geist und _dragName haengen und jeder Zeilen-Tooltip waere tot.
    if _dragName then stopDrag(false) end

    if sidebarSelected and not (LO() and LO()[sidebarSelected]) then
        sidebarSelected = nil
    end
    if sidebarExpanded and not (LO() and LO()[sidebarExpanded]) then
        sidebarExpanded = nil
    end

    -- sidebarItemRows is sparse (rows are created lazily), so it must use pairs, not ipairs.
    for _, b in ipairs(sidebarSetButtons) do b:Hide() end
    for _, r in pairs(sidebarItemRows)    do r:Hide() end

    local names = sortedLoadoutNames()
    if not sidebarSelected and #names > 0 then sidebarSelected = names[1] end

    -- Read once per rebuild, not per row: every anchor below has to move in by
    -- the same amount, and the style cannot change halfway through the loop.
    local inset = sidebarInset()
    local y = -(32 + inset)
    for i, name in ipairs(names) do
        local btn = createSetRow(sidebar, i)
        -- Wechselt die Zeile ihr Set (etwa nach dem Umsortieren), verfaellt der
        -- Doppelklick-Zeitstempel -- sonst legte ein schneller Klick danach das
        -- NEUE Set der Zeile an, obwohl der erste Klick dem alten galt.
        if btn.setName ~= name then btn._lastClick = nil end
        btn.setName = name
        -- Marker in absteigender Dringlichkeit: fehlende Teile schlagen
        -- Bankteile, und gruen erscheint nur, wenn wirklich alles getragen
        -- wird - sonst wuerde ein teilweise angelegtes Set als fertig gelten.
        local miss, inBank, equipped, total = setStatus(name)
        local marker = ""
        if miss > 0 then marker = " |cffff5555•|r"
        elseif inBank > 0 then marker = " |cffff9933•|r"
        elseif total > 0 and equipped == total then marker = " |cff33ff55•|r" end
        btn.text:SetText(name .. marker)
        btn.icon:SetTexture(getSetIcon(name))
        btn.isSelected = (name == sidebarSelected)
        if btn.isSelected then
            btn.selection:Show()
            if btn.selBar then btn.selBar:Show() end
            btn.text:SetTextColor(1, 1, 1)
        else
            btn.selection:Hide()
            if btn.selBar then btn.selBar:Hide() end
            btn.text:SetTextColor(0.82, 0.82, 0.88)
        end
        if sidebarExpanded == name then
            btn.expand.icon:SetTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
        else
            btn.expand.icon:SetTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Up")
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  4 + inset, y)
        btn:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -(4 + inset), y)
        btn:Show()
        y = y - 33

        if sidebarExpanded == name then
            local row = getItemRow(sidebar, i)
            renderItemRow(row, name)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  6 + inset, y)
            row:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -(6 + inset), y)
            row:Show()
            y = y - row:GetHeight() - 4
        end
    end

    if #names == 0 then
        if not sidebar.emptyText then
            sidebar.emptyText = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            sidebar.emptyText:SetTextColor(0.6, 0.6, 0.6)
            sidebar.emptyText:SetText(L["No loadouts saved yet."])
        end
        -- Re-anchored on every rebuild, not once at creation: the line has to
        -- drop below the buttons again when the style switches.
        sidebar.emptyText:ClearAllPoints()
        sidebar.emptyText:SetPoint("TOP", sidebar, "TOP", 0, -(48 + inset))
        sidebar.emptyText:Show()
    elseif sidebar.emptyText then
        sidebar.emptyText:Hide()
    end

    if sidebar.equipBtn then
        if sidebarSelected then
            sidebar.equipBtn:Enable()
            sidebar.saveBtn:Enable()
        else
            sidebar.equipBtn:Disable()
            sidebar.saveBtn:Disable()
        end
    end
end

local function createSidebar()
    if sidebar then return sidebar end
    if not CharacterFrame then return end

    sidebar = CreateFrame("Frame", "VCUI_LoadoutsSidebar", CharacterFrame,
        BackdropTemplateMixin and "BackdropTemplate")
    sidebar:SetWidth(SIDEBAR_WIDTH + sidebarInset() * 2)
    sidebar:SetFrameStrata("HIGH")
    sidebar:Hide()

    -- The icon picker hangs off UIParent, not off this frame, so nothing took
    -- it down with the list -- closing the character sheet left the swatches
    -- floating over the game. Hooked here rather than at the six places that
    -- hide the list, so no future one can forget.
    sidebar:HookScript("OnHide", function()
        if _iconPicker then _iconPicker:Hide() end
        -- Schliesst das Charakterfenster mitten im Ziehen (Escape), feuert
        -- OnDragStop nie -- der Geist hinge sonst am Mauszeiger fest und
        -- _dragName wuerde jeden Zeilen-Tooltip dauerhaft unterdruecken.
        stopDrag(false)
    end)

    -- The rune panel opens to the RIGHT of the character sheet -- exactly where
    -- this list docks, so the two stood on top of each other (user report with a
    -- screenshot, 08.08.2026). Verified in game on 08.08.2026 by walking the
    -- parent chain under the mouse: the frame is EngravingFrame, 193 wide, and it
    -- hangs off UIParent -- NOT off the character sheet. So nothing that iterates
    -- the sheet's children will ever see it, and closing the sheet does not take
    -- it down either.
    --
    -- It is created on demand, so the hook cannot be installed once and for all at
    -- load; this waits for the frame and takes the first chance it gets. Both
    -- directions matter: without OnHide the list would stay parked out in the open
    -- after the runes are closed again.
    local engravingHooked = false
    local function hookEngravingFrame()
        if engravingHooked then return end
        local ef = _G.EngravingFrame
        if not (ef and ef.HookScript) then return end
        engravingHooked = true
        local function again() if ns.ReanchorLoadoutsSidebar then ns.ReanchorLoadoutsSidebar() end end
        ef:HookScript("OnShow", again)
        ef:HookScript("OnHide", again)
    end

    -- Both corners anchor to CharacterFrame so the height tracks it live; never snapshot GetHeight().
    local lastX, lastTop, lastBot, lastFlip
    local function anchorToCharacterFrame()
        if not sidebar or not CharacterFrame then return end
        hookEngravingFrame()
        local pos    = mod.db and mod.db.sidebarPos
        local px     = (pos and pos.x) or 0
        local py     = (pos and pos.y) or 0
        local topOff = ((mod.db and mod.db.sidebarTopOffset)    or 0) + py
        local botOff = ((mod.db and mod.db.sidebarBottomOffset) or 0) + py
        -- the Modern style widens the window, so dock past it and ignore the classic art offsets
        local ext, extTop, extBot, modernOn = 0, 0, 0, false
        if ns.CharacterPanelModernExt then ext, extTop, extBot, modernOn = ns.CharacterPanelModernExt() end
        local x = -4 + px + ext + (ext > 0 and 6 or 0)
        if modernOn then
            topOff = extTop + py
            botOff = extBot + py
        end
        -- With the rune panel open its own right edge decides, and the widened
        -- Modern window is then beside the point -- the panel already hangs off it,
        -- so adding the extension on top would push the list a second window's
        -- width into nowhere. The edge is read live rather than assumed from the
        -- panel's width, because that width is not ours to depend on.
        local cr = CharacterFrame.GetRight and CharacterFrame:GetRight()
        local ef = _G.EngravingFrame
        if ef and ef.IsShown and ef:IsShown() and ef.GetRight and cr then
            local er = ef:GetRight()
            if er and er > cr then x = -4 + px + (er - cr) + 6 end
        end

        -- Character sheet plus rune panel plus this list is wider than some
        -- screens, and a list off the right edge cannot be reached. Then it goes
        -- to the LEFT of the sheet -- but only if the left really has room, or the
        -- flip would trade one invisible edge for the other. Same safeguard the
        -- socket picker and the weapon strip already carry.
        local flip = false
        local w  = sidebar.GetWidth and sidebar:GetWidth() or 0
        local cl = CharacterFrame.GetLeft and CharacterFrame:GetLeft()
        local screenR = UIParent and UIParent.GetRight and UIParent:GetRight()
        if cr and cl and screenR and w > 0 then
            flip = (cr + x + w) > screenR and (cl - w - 4) > 0
        end

        -- Nothing to do when nothing moved. This is what lets the tick below call
        -- in four times a second without re-anchoring a frame that is already
        -- where it belongs -- and it keeps the drag on the mover from fighting a
        -- re-anchor mid-pull.
        --
        -- The point count is part of the question, not decoration. Edit Mode's
        -- "Reset this frame" tears the two-point anchor off onto a single CENTER
        -- point and then calls back in here to have it restored -- with the same
        -- offsets as before, so the values alone would say "nothing moved" and the
        -- list would stay collapsed at the centre of the screen.
        local intact = sidebar.GetNumPoints and sidebar:GetNumPoints() == 2
        if intact and x == lastX and topOff == lastTop and botOff == lastBot and flip == lastFlip then return end
        lastX, lastTop, lastBot, lastFlip = x, topOff, botOff, flip

        sidebar:ClearAllPoints()
        if flip then
            sidebar:SetPoint("TOPRIGHT",    CharacterFrame, "TOPLEFT", -4 + px, topOff)
            sidebar:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMLEFT", -4 + px, botOff)
        else
            sidebar:SetPoint("TOPLEFT",    CharacterFrame, "TOPRIGHT", x, topOff)
            sidebar:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMRIGHT", x, botOff)
        end
        -- The shadow is NOT decided here any more; styleWindow owns it. Placing
        -- the same call in two functions meant the later one won, and this one
        -- runs on every re-anchor -- which put the shadow back in Classic+.
    end
    anchorToCharacterFrame()
    sidebar._reanchor = anchorToCharacterFrame
    mod._reanchorSidebar = anchorToCharacterFrame
    ns.ReanchorLoadoutsSidebar = anchorToCharacterFrame   -- character panel style switches call this

    -- The hook above cannot cover the run on which the rune panel is BORN: it is
    -- created on demand, so on the click that first opens it there is no frame to
    -- have hooked, and the list only learned about it at the next re-anchor --
    -- which is why closing and reopening the character sheet appeared to fix it
    -- while opening the runes did not. This tick installs the hook the moment the
    -- frame exists and otherwise costs one comparison: the re-anchor above returns
    -- immediately while nothing has moved. It runs only while the list is visible,
    -- and the list is only visible while the character sheet is open.
    local sinceCheck = 0
    sidebar:HookScript("OnUpdate", function(_, elapsed)
        sinceCheck = sinceCheck + (elapsed or 0)
        if sinceCheck < 0.25 then return end
        sinceCheck = 0
        anchorToCharacterFrame()
    end)

    mod._debugSizes = function()
        local function dump(label, f)
            if not f then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s: |cffff5555nil|r", label))
                return
            end
            local top    = f.GetTop    and f:GetTop()
            local bottom = f.GetBottom and f:GetBottom()
            local height = f.GetHeight and f:GetHeight()
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "  %s: top=%s bottom=%s height=%s",
                label,
                top    and string.format("%.0f", top)    or "?",
                bottom and string.format("%.0f", bottom) or "?",
                height and string.format("%.0f", height) or "?"))
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff9b6cff[Loadouts size debug]|r")
        dump("CharacterFrame",      _G.CharacterFrame)
        dump("CharacterFrameInset", _G.CharacterFrameInset)
        dump("PaperDollFrame",      _G.PaperDollFrame)
        dump("Sidebar",             sidebar)
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  Offsets: top=%d bottom=%d",
            mod.db.sidebarTopOffset or 0, mod.db.sidebarBottomOffset or 0))
    end

    local UIW = ns.UI
    -- No drop shadow, in EITHER look (owner's decision, 03.08.2026). CreateShadow
    -- is not an outline: it is four filled black rectangles standing 1, 3, 5 and
    -- 7 pixels PAST the frame on every side. Behind Blizzard's dialog frame that
    -- read as the background spilling out past the border, and against the flat
    -- panel it was a dark band with nothing to cast it. Not created rather than
    -- created-and-hidden, so there is no switch left to turn it back on.
    local gstrip = sidebar:CreateTexture(nil, "ARTWORK")
    gstrip:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
    gstrip:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    gstrip:SetHeight(2)
    if UIW and UIW.SetGradient then
        local a = ns.COLORS.accent
        UIW.SetGradient(gstrip, "HORIZONTAL", a.r, a.g, a.b, 0.1, a.r, a.g, a.b, 0.9)
    end

    -- Classic+ wears Blizzard's own dialog frame, so the list stands next to the
    -- character window in the same material instead of a flat panel with our
    -- purple edge beside it (user request, 02.08.2026).
    --
    -- The panel goes through the same styleWindow as the icon picker, so both
    -- windows of this module can never drift apart.
    local function styleSidebarChrome()
        styleWindow(sidebar)
        -- the accent strip is the top edge of the flat panel; on Blizzard's
        -- frame it would lie across the artwork
        gstrip:SetShown(not sidebarClassic())
    end
    styleSidebarChrome()

    local bc = ns.COLORS.border or { r = 0.22, g = 0.22, b = 0.27 }
    local fontN, fontH, fontD = ns.UI:PanelButtonFonts("VCUI_LoadoutFont")

    -- The recipe is the one the gear-set addon uses: Classic+ does not paint a
    -- button, it simply lets Blizzard's own artwork stand and turns the label
    -- Blizzard gold. Only the modern style wears our flat skin.
    local GOLD = { r = 1, g = 0.82, b = 0 }
    local skinned = {}
    local function skinBtn(b)
        skinned[b] = true
        if sidebarClassic() then
            ns.UI:UnskinPanelButton(b)
            local fs = b.GetFontString and b:GetFontString()
            if fs then fs:SetTextColor(GOLD.r, GOLD.g, GOLD.b) end
        else
            ns.UI:SkinPanelButton(b, { fonts = { fontN, fontH, fontD }, border = bc })
            local fs = b.GetFontString and b:GetFontString()
            if fs then fs:SetTextColor(1, 1, 1) end
        end
    end

    -- Selected-row backing. Classic+ takes the restrained olive the gear-set
    -- addon uses there: its purple reads as a second accent next to Blizzard's
    -- gold, and the two fight on the same row.
    local function selectionRGBA()
        if sidebarClassic() then return 0.50, 0.39, 0.10, 0.38 end
        local a = ns.COLORS.accent
        return a.r, a.g, a.b, 0.30
    end
    mod._sidebarSelectionRGBA = selectionRGBA

    -- Re-paints what already exists. Registered for the character panel's style
    -- switch below; without it a switch would only reach rows built afterwards.
    --
    -- The padding hangs off the style too, so the list has to be laid out again
    -- as well -- otherwise rows and buttons run onto the Blizzard frame.
    ns.RestyleLoadoutsSidebar = function()
        styleSidebarChrome()
        for b in pairs(skinned) do skinBtn(b) end
        if mod._repaintSidebarRows then mod._repaintSidebarRows() end
        if mod._layoutSidebarButtons then mod._layoutSidebarButtons() end
        if sidebar and sidebar:IsShown() and refreshSidebar then refreshSidebar() end
        -- The picker builds its layout while opening, so a switch while it
        -- stands open only reaches it by opening it again on the same set.
        if _iconPicker and _iconPicker._restyle then _iconPicker._restyle() end
    end

    local equipBtn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    equipBtn:SetHeight(22)
    equipBtn:SetText(L["Equip"])
    equipBtn:SetScript("OnClick", function()
        if sidebarSelected then equipLoadout(sidebarSelected) end
    end)
    skinBtn(equipBtn)
    sidebar.equipBtn = equipBtn

    local saveBtn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    saveBtn:SetHeight(22)
    saveBtn:SetText(L["Save"])
    saveBtn:SetScript("OnClick", function()
        if sidebarSelected then
            overwriteLoadout(sidebarSelected)
            refreshSidebar()
        end
    end)
    skinBtn(saveBtn)
    sidebar.saveBtn = saveBtn

    local newBtn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    newBtn:SetHeight(24)
    newBtn:SetText("+ " .. L["New Set"])
    newBtn:SetScript("OnClick", function() promptSaveWithSlots(nil) end)
    skinBtn(newBtn)
    sidebar.newBtn = newBtn

    -- The three buttons SPAN between the panel's edges instead of carrying a
    -- fixed width (user request, 02.08.2026 -- the gear-set panel this matches
    -- does it the same way). Fixed 86 / 178 held only at exactly one panel
    -- width; any other left the two top buttons in the left half with a gap
    -- beside them.
    --
    -- Recomputed rather than anchored once: it runs again on every style switch,
    -- and both the padding and the width change under it there.
    local function layoutSidebarButtons()
        if not sidebar then return end
        local inset = sidebarInset()
        local pad, gap = 4 + inset, 4

        -- The panel GROWS by the frame it wears instead of losing the room to
        -- it. The icon grid of an expanded set needs its six columns; at a fixed
        -- 190 the wide Blizzard frame left space for five and the last icon of
        -- every line dropped into the next.
        local want = SIDEBAR_WIDTH + inset * 2
        if math.abs((sidebar:GetWidth() or 0) - want) > 0.5 then
            sidebar:SetWidth(want)
        end

        local w = sidebar:GetWidth() or want
        local half = math.max(20, (w - pad * 2 - gap) / 2)

        equipBtn:ClearAllPoints()
        equipBtn:SetWidth(half)
        equipBtn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", pad, -(6 + inset))

        saveBtn:ClearAllPoints()
        saveBtn:SetWidth(half)
        saveBtn:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -pad, -(6 + inset))

        newBtn:ClearAllPoints()
        newBtn:SetPoint("BOTTOMLEFT",  sidebar, "BOTTOMLEFT",  pad, 5 + inset)
        newBtn:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -pad, 5 + inset)
    end
    layoutSidebarButtons()
    mod._layoutSidebarButtons = layoutSidebarButtons
    -- The character panel's style switch already calls the re-anchor; the
    -- buttons have to follow it, or a wider panel keeps half-width buttons.
    sidebar:HookScript("OnSizeChanged", layoutSidebarButtons)

    -- The mover stores an x/y offset only; the frame must stay anchored to CharacterFrame.
    mod.db.sidebarPos = mod.db.sidebarPos or { x = 0, y = 0 }
    sidebar.mover = ns:CreateMover(sidebar, {
        key      = "loadouts.sidebar",
        label    = L["|cffffffffLOADOUTS SIDEBAR|r\n|cffaaaaaaDrag or arrow keys|r"],
        db       = mod.db.sidebarPos,
        width    = 168,
        height   = 44,
        applyPos = anchorToCharacterFrame,
        -- A mover with its own applyPos gets a plain CENTER drop and is then
        -- expected to restore its anchor model from onMove. Without one, Edit
        -- Mode's X/Y boxes and "Reset this frame" tore the sidebar off the
        -- character window onto a single centre point, where its two-point
        -- anchor was gone and it collapsed to height zero.
        onMove   = anchorToCharacterFrame,
    })
    sidebar.mover:SetFrameLevel((sidebar:GetFrameLevel() or 1) + 20)
    do
        -- replaces the default screen-centre drag, which would break the two-point anchor
        local mvr = sidebar.mover
        mvr:SetScript("OnDragStart", function(self)
            local cx, cy = GetCursorPosition()
            self._dragX, self._dragY = cx, cy
            self._origX, self._origY = mod.db.sidebarPos.x or 0, mod.db.sidebarPos.y or 0
            self:SetScript("OnUpdate", function()
                local nx, ny = GetCursorPosition()
                local s = UIParent:GetEffectiveScale()
                if s and s > 0 then
                    mod.db.sidebarPos.x = self._origX + (nx - self._dragX) / s
                    mod.db.sidebarPos.y = self._origY + (ny - self._dragY) / s
                    anchorToCharacterFrame()
                end
            end)
        end)
        mvr:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    end

    -- Die Leiste gehoert zum Reiter "Charakter". Auf Ruf, Fertigkeiten oder
    -- PvP hat sie keinen Bezug, deshalb haengt sie an PaperDollFrame - das
    -- ist genau dieser Reiter - und nicht am Charakterfenster insgesamt.
    local function updateVisibility()
        if not (mod._enabled and mod.db and mod.db.sidebarEnabled ~= false) then
            sidebar:Hide()
            return
        end
        local onGearTab = PaperDollFrame and PaperDollFrame:IsShown()
        if CharacterFrame and CharacterFrame:IsShown() and onGearTab then
            sidebar:Show()
            anchorToCharacterFrame()
            refreshSidebar()
            if sidebar.mover then
                if ns:IsMoverEditMode() then sidebar.mover:Show() else sidebar.mover:Hide() end
            end
        else
            sidebar:Hide()
        end
    end
    mod._updateSidebarVisibility = updateVisibility

    CharacterFrame:HookScript("OnShow", updateVisibility)
    CharacterFrame:HookScript("OnHide", function() sidebar:Hide() end)
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", updateVisibility)
        PaperDollFrame:HookScript("OnHide", function() sidebar:Hide() end)
    end
    updateVisibility()

    if ns:IsMoverEditMode() then sidebar.mover:Show() end
    return sidebar
end

local function applySidebarVisibility()
    if not sidebar then return end
    -- Entscheidet dieselbe Stelle wie die Frame-Hooks, damit der Reiter
    -- nicht an zwei Orten geprueft wird.
    if mod._updateSidebarVisibility then
        mod._updateSidebarVisibility()
    elseif mod.db.sidebarEnabled == false then
        sidebar:Hide()
    end
end

local _origSaveAs    = saveAs
local _origDelete    = deleteLoadout
saveAs = function(name, slotList)
    _origSaveAs(name, slotList)
    if sidebar then
        sidebarSelected = name
        refreshSidebar()
    end
end
deleteLoadout = function(name)
    _origDelete(name)
    if sidebar then
        if sidebarSelected == name then sidebarSelected = nil end
        refreshSidebar()
    end
end

function mod.ImportLegacy()
    local legacy = mod.db and mod.db.loadouts
    if not (legacy and next(legacy)) then
        ns:Print(L["No account-wide loadouts to import."])
        return
    end
    local lo, n = LO(), 0
    for name, data in pairs(legacy) do
        if not lo[name] then
            lo[name] = (CopyTable and CopyTable(data)) or data
            -- repeats the OnEnable slotMask migration; imports arrive after it ran
            local imported = lo[name]
            if not imported.slotMask then
                local mask = {}
                for slot in pairs(imported.slots or {}) do
                    table.insert(mask, slot)
                end
                table.sort(mask)
                imported.slotMask = mask
            end
            n = n + 1
        end
    end
    for name, g in pairs(mod.db.specMapping or {}) do
        if not specMap()[name] then specMap()[name] = g end
    end
    for name, g in pairs(mod.db.formMapping or {}) do
        if not formMap()[name] then formMap()[name] = g end
    end
    ns:Print(string.format(L["Imported %d account-wide loadout(s) onto this character."], n))
    refreshSidebar()
end

function mod:OnEnable()
    if not mod.db then return end
    LO(); formMap(); specMap()
    mod.db.minimap     = mod.db.minimap     or { hidden = false, angle = -45 }

    -- migration: derive slotMask for legacy loadouts saved without one
    for _, loadout in pairs(LO()) do
        if loadout and not loadout.slotMask then
            local mask = {}
            for slot in pairs(loadout.slots or {}) do
                table.insert(mask, slot)
            end
            table.sort(mask)
            loadout.slotMask = mask
        end
    end

    -- one-time migration of the old 0/0 sidebar offset default
    if not mod.db._offsetMigrated then
        if (mod.db.sidebarTopOffset or 0) == 0 and (mod.db.sidebarBottomOffset or 0) == 0 then
            mod.db.sidebarTopOffset    = -14
            mod.db.sidebarBottomOffset = 45
        end
        mod.db._offsetMigrated = true
    end

    if not next(LO()) and not charDB()._importHintShown
       and mod.db.loadouts and next(mod.db.loadouts) then
        charDB()._importHintShown = true
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function()
                if not next(LO()) and mod.db.loadouts and next(mod.db.loadouts) then
                    ns:Print(L["You have account-wide loadouts from an older version. Type /lo import to copy them onto this character."])
                end
            end)
        end
    end

    -- deferred so Minimap exists; applyMinimapVisibility is needed on re-enable (create early-returns)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            createMinimapButton()
            applyMinimapVisibility()
        end)
        C_Timer.After(0.5, createSidebar)
    else
        createMinimapButton()
        applyMinimapVisibility()
        createSidebar()
    end

    -- Statusmarker nachziehen. Das Anlegen laeuft ueber UseContainerItem und
    -- braucht mehrere Frames; der Aufruf direkt nach equipLoadout sieht die
    -- Teile also noch am alten Platz. Erst diese Ereignisse melden den
    -- fertigen Zustand.
    local function refreshMarkers()
        if sidebar and sidebar:IsShown() then refreshSidebar() end
    end
    mod:RegisterEvent("UNIT_INVENTORY_CHANGED", refreshMarkers)
    mod:RegisterEvent("BAG_UPDATE_DELAYED",     refreshMarkers)

    mod:RegisterEvent("UPDATE_SHAPESHIFT_FORM",  onShapeshiftChange)
    mod:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", onShapeshiftChange)
    mod:RegisterEvent("PLAYER_REGEN_ENABLED",    onShapeshiftChange)  -- retry leaving combat

    -- all of these are registered because Anniversary builds vary on which one fires
    mod:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", onTalentChange)
    mod:RegisterEvent("PLAYER_TALENT_UPDATE",        onTalentChange)
    mod:RegisterEvent("CHARACTER_POINTS_CHANGED",    onTalentChange)
    mod:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", onTalentChange)
    mod:RegisterEvent("PLAYER_ENTERING_WORLD",       onTalentChange)
    mod:RegisterEvent("PLAYER_REGEN_ENABLED",        onTalentChange)  -- retry after combat

    mod:RegisterEvent("BANKFRAME_OPENED",         onBankEvent)
    mod:RegisterEvent("BANKFRAME_CLOSED",         onBankEvent)
    mod:RegisterEvent("PLAYERBANKSLOTS_CHANGED",  onBankEvent)
    mod:RegisterEvent("BAG_UPDATE",               onBankEvent)  -- bank BAGS (gated on _bankOpen)

    installSetTooltip()

    _lastForm = getCurrentForm()
    -- deferred: the spec group is not readable immediately on login
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function() _lastSpecGroup = getActiveSpecGroup() end)
    end
    startSpecPolling()
end

function mod:OnDisable()
    if _specPoller then _specPoller:Cancel(); _specPoller = nil end
    if mmBtn then mmBtn:Hide() end
    if sidebar then sidebar:Hide() end
end

local function buildFormDropdownValues()
    local values = { { value = 0, text = L["None"] } }
    local numForms = (GetNumShapeshiftForms and GetNumShapeshiftForms()) or 0
    for i = 1, numForms do
        table.insert(values, { value = i, text = getFormName(i) })
    end
    return values
end

local function buildSpecDropdownValues()
    local values = { { value = 0, text = L["None"] } }
    local numGroups = getNumSpecGroups()
    for g = 1, numGroups do
        table.insert(values, { value = g, text = getSpecGroupLabel(g) })
    end
    return values
end

function mod:GetOptions()
    local spItems = (ns.SlotPickerOptionItems and ns.SlotPickerOptionItems(function()
        local sp = ns.modules and ns.modules.slotpicker
        return sp and sp.db
    end)) or {}
    local items = {
        { type = "header", text = L["Loadouts"] },
        { type = "desc", text = L["Save your current equipment as named gear sets and quickly switch between them. Equipping requires you to be out of combat — items in your bags are auto-equipped via Use."] },

        { type = "spacer", height = 6 },
        { type = "group", layout = "row", gap = 6,
          items = {
              { type = "button", label = L["Save All..."], width = 130,
                onClick = function() promptSaveWithSlots(nil) end },
              { type = "button", label = L["Save Trinkets..."], width = 130,
                onClick = function() promptSaveWithSlots(SLOT_GROUPS.trinkets) end },
              { type = "button", label = L["Save Weapons..."], width = 130,
                onClick = function() promptSaveWithSlots(SLOT_GROUPS.weapons) end },
          },
        },
        { type = "toggle", label = L["Confirm before deleting a loadout"],
          get = function() return mod.db.confirmDelete ~= false end,
          set = function(_, v) mod.db.confirmDelete = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Character Frame Sidebar"] },
        { type = "toggle", label = L["Show sidebar on character frame"],
          tooltip = L["Attach a quick-access sidebar to the right of the character window. Click a set to select, double-click or button to equip, right-click for context menu."],
          get = function() return mod.db.sidebarEnabled ~= false end,
          set = function(_, v)
              mod.db.sidebarEnabled = v
              applySidebarVisibility()
          end },
        { type = "desc", text = L["|cffaaaaaaTip: with the character window open, enable edit mode (Unlock) to drag the sidebar; right-click the purple box to reset its position.|r"] },

        { type = "spacer", height = 6 },
        { type = "section", title = L["Slot Picker"], items = {
            { type = "desc", text = L["|cffaaaaaaRight-click an equipment slot in the character window to see all compatible items from your bags and click one to equip it.|r"] },
            { type = "toggle", label = L["Enable slot picker"],
              get = function() return ns:IsModuleEnabled("slotpicker") end,
              set = function(_, v) if ns.ToggleModule then ns:ToggleModule("slotpicker", v) end end },
            spItems[1], spItems[2],
        } },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Minimap Button"] },
        { type = "toggle", label = L["Show minimap button"],
          tooltip = L["Left-click for a quick set-switcher menu, right-click to open settings, drag to reposition."],
          get = function() return not (mod.db.minimap and mod.db.minimap.hidden) end,
          set = function(_, v)
              mod.db.minimap = mod.db.minimap or {}
              mod.db.minimap.hidden = not v
              applyMinimapVisibility()
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Auto-Switch on Dual Spec"] },
        { type = "toggle", label = L["Enable spec auto-switching"],
          tooltip = L["Automatically equips a loadout when you switch between Spec 1 and Spec 2 (dual spec). Bind each loadout to a spec below. Requires dual spec to be active."],
          get = function() return mod.db.specSwitchEnabled ~= false end,
          set = function(_, v) mod.db.specSwitchEnabled = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Auto-Switch on Stance/Form"] },
        { type = "toggle", label = L["Enable auto-switching"],
          tooltip = L["Automatically equips a loadout when your stance/form changes (warrior stances, druid forms). Out-of-combat only — if a stance change happens in combat, the swap is deferred until combat ends."],
          get = function() return mod.db.autoSwitchEnabled ~= false end,
          set = function(_, v) mod.db.autoSwitchEnabled = v end },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Saved Loadouts"] },
    }

    -- index 3 keeps this directly under the header + desc
    if mod.db.loadouts and next(mod.db.loadouts) then
        table.insert(items, 3, { type = "section", title = L["Import from older version"], items = {
            { type = "desc", text = L["|cffaaaaaaYou have gear sets saved account-wide by an older version. Loadouts are now per-character — import copies them onto THIS character.|r"] },
            { type = "button", label = L["Import account-wide loadouts"], width = 240,
              onClick = function() mod.ImportLegacy() end },
        } })
    end

    local names = sortedLoadoutNames()
    if #names == 0 then
        table.insert(items, { type = "desc", text = L["|cffaaaaaaNo loadouts saved yet. Use the button above to save your current gear.|r"] })
    else
        local formValues = buildFormDropdownValues()
        local hasForms = #formValues > 1
        local specValues = buildSpecDropdownValues()
        local hasSpecs = getNumSpecGroups() >= 2

        for _, name in ipairs(names) do
            local capturedName = name  -- must be a fresh local per iteration for the closures below
            local slotCount = countSlots(LO()[name])

            table.insert(items, { type = "desc",
                text = string.format("|cffffd100%s|r |cff888888(%d %s)|r",
                    name, slotCount, L["items"]) })

            table.insert(items, { type = "group", layout = "row", gap = 6,
                items = {
                    { type = "button", label = L["Equip"], width = 100,
                      onClick = function() equipLoadout(capturedName) end },
                    { type = "button", label = L["Overwrite"], width = 130,
                      onClick = function() overwriteLoadout(capturedName) end },
                    { type = "button", label = L["Rename..."], width = 120,
                      onClick = function()
                          StaticPopup_Show("VCUI_LOADOUT_RENAME", capturedName, nil, capturedName)
                      end },
                    { type = "button", label = L["Delete"], width = 100,
                      onClick = function()
                          if mod.db.confirmDelete then
                              local dlg = StaticPopup_Show("VCUI_LOADOUT_DELETE", capturedName)
                              if dlg then dlg.data = capturedName end
                          else
                              deleteLoadout(capturedName)
                          end
                      end },
                },
            })

            if hasSpecs then
                table.insert(items, { type = "dropdown",
                    label = L["Auto-equip on spec"],
                    tooltip = L["Equip this loadout automatically when you switch to this spec."],
                    values = specValues,
                    get = function() return (specMap() and specMap()[capturedName]) or 0 end,
                    set = function(_, v)
                        -- bindings are 1:1, so clear any other loadout on this spec
                        if v and v ~= 0 then
                            for other, tabIdx in pairs(specMap()) do
                                if tabIdx == v and other ~= capturedName then
                                    specMap()[other] = nil
                                end
                            end
                        end
                        specMap()[capturedName] = (v ~= 0) and v or nil
                    end,
                })
            end

            if hasForms then
                table.insert(items, { type = "dropdown",
                    label = L["Auto-equip on form"],
                    tooltip = L["Equip this loadout automatically when the chosen stance/form is activated."],
                    values = formValues,
                    get = function() return (formMap() and formMap()[capturedName]) or 0 end,
                    set = function(_, v)
                        -- bindings are 1:1, so clear any other loadout on this form
                        if v and v ~= 0 then
                            for other, formIdx in pairs(formMap()) do
                                if formIdx == v and other ~= capturedName then
                                    formMap()[other] = nil
                                end
                            end
                        end
                        formMap()[capturedName] = (v ~= 0) and v or nil
                    end,
                })
            end

            table.insert(items, { type = "spacer", height = 4 })
        end
    end

    table.insert(items, { type = "spacer", height = 8 })
    table.insert(items, { type = "desc", text = L["|cffaaaaaaSlash commands: /loadout save <name>, /loadout equip <name>, /loadout delete <name>, /loadout list. Short alias: /lo|r"] })

    return items
end
