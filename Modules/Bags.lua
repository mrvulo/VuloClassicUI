-- VuloClassicUI / Modules / Bags
local _, ns = ...
local L  = ns.L
local UI = ns.UI

-- Container globals come from Core/Compat.lua on Era (legacy GetContainerItemInfo tuple).
local GetContainerNumSlots     = _G.GetContainerNumSlots
local GetContainerItemInfo     = _G.GetContainerItemInfo
local GetContainerItemCooldown = _G.GetContainerItemCooldown
local GetContainerNumFreeSlots = _G.GetContainerNumFreeSlots
local GetContainerItemLink     = _G.GetContainerItemLink

-- Native bag sort is absent on many Classic builds; nativeSort/nativeSetDir may be nil.
local nativeSort   = (_G.C_Container and _G.C_Container.SortBags) or _G.SortBags
local nativeSetDir = (_G.C_Container and _G.C_Container.SetSortBagsRightToLeft) or _G.SetSortBagsRightToLeft

local BAGS = { 0, 1, 2, 3, 4 }

local mod = ns:RegisterModule("bags", {
    name        = "Bags",
    group       = "QoL",
    description = "A single unified inventory window: all bags in one grid, with quality borders, counts, cooldowns, money and free slots. Movable and scalable.",
    defaults = {
        enabled       = true,
        x             = 0,
        y             = 0,
        scale         = 1.0,
        columns       = 12,
        qualityBorders = true,
        countFontSize = 12,
        showSearch    = true,
        showSortButton = true,
        sortReverse   = false,
        sortMode      = "type",       -- "type" | "quality" | "name" | "item-level" | "blizzard"
        catSortMode   = "type",       -- "type" | "quality" | "name" | "item-level" | "off"
        showFreeSlots = true,
        onebagFixedSlots = true,
        junkMarker    = true,
        bindMarker    = true,
        questMarker   = true,
        useCategories = true,
        hideEmpty     = true,
        viewMode      = "all",        -- "all" | "onebag" | "multibag"
        sidebarCollapsed = true,
        customCats      = {},
        itemAssignments = {},
        disabledCats    = {},
        catOrder        = nil,
        pinnedItems     = {},
        showRecent      = true,
        recentCap       = 20,
        groups          = {},
        hiddenBags      = {},
        showKeyring     = false,
        showItemLevel   = true,
        itemLevelQualityColor = true,
        collapsedCats   = {},
        bagBarShown     = false,
        -- bank sub-table: SEPARATE keys so the bank mover never collides with the bag window
        bank = { enabled = true, x = -280, y = 0, scale = 1.0, columns = 14, hiddenBags = {} },
    },
})

mod.active = false

local BTN, GAP, PAD = 37, 4, 12
local HEADER_H, FOOTER_H = 32, 26
local HEADER_ROW = 18
local GROUP_HEADER_ROW = 20
local GROUP_INDENT     = 10
local SIDEBAR_INDENT   = 14
local SIDEBAR_W_EXPANDED  = 160
local SIDEBAR_W_COLLAPSED = 32
local SIDEBAR_BTN_H       = 24
local SIDEBAR_BTN_GAP     = 2
local SIDEBAR_ICON        = 16
local SIDEBAR_HDR_H       = 22
local CONTENT_MAX_FRAC = 0.60   -- viewport caps at 60% of UIParent height
local WHEEL_STEP       = BTN + GAP

-- Categories. Keys are internal + stable; display names localized.
local CATEGORY_ORDER = {
    "pinned", "recent",   -- pseudo-categories, always at the top
    "quest", "consumable", "weapon", "armor", "trinket", "container",
    "tradegoods", "recipe", "projectile", "quiver", "key", "junk", "misc",
}

-- Declared before every function that references them, so closures bind these upvalues.
local customCats      = {}
local itemAssignments = {}
local disabledCats    = {}
local customCatByKey  = {}
local nextCustomSeq   = 0
local selectedCategory = "all"
local DEFAULT_CUSTOM_ICON = "Interface\\Icons\\INV_Misc_Note_02"
-- pinnedItems mirrors the profile; recentItems/recentOrder/recentBaseline are runtime only.
local pinnedItems = {}
local recentItems = {}
local recentOrder = {}
local recentBaseline = {}
local recentPrimed = false
-- groups is a LIVE reference to mod.db.groups (set in OnEnable).
local groups       = {}
local groupById    = {}
local groupOfCat   = {}
local nextGroupSeq = 0
local rebuildCustomLookup, categoryExists, orderedCategoryKeys, categoriesChanged
local createCustomCategory, renameCategory, deleteOrDisableCategory, reenableCategory, moveCategory
local showCategoryMenu, promptNewCategory
local updateRecentItems, clearRecentItems
-- Defined below via bare "function name()" -- never redeclare with local at the definition.
local rebuildGroupLookup, groupsChanged, groupedDisplay
local createGroup, renameGroup, deleteGroup, moveGroup
local assignCatToGroup, moveCatWithinGroup, toggleGroupCollapsed
local showGroupMenu, showAssignToGroupMenu, promptNewGroup

local function catName(key)
    local c = customCatByKey[key]
    if c then return c.name or key end
    if mod.db and mod.db.catRenames and mod.db.catRenames[key] then return mod.db.catRenames[key] end
    local map = {
        pinned = L["Pinned Items"], recent = L["Recent Items"],
        quest = L["Quest"], consumable = L["Consumables"], weapon = L["Weapons"],
        armor = L["Armor"], trinket = L["Trinkets"], container = L["Bags"],
        tradegoods = L["Trade Goods"], recipe = L["Recipes"], projectile = L["Ammo"],
        quiver = L["Quivers"], key = L["Keys"], junk = L["Junk"], misc = L["Miscellaneous"],
    }
    return map[key] or key
end

local CATEGORY_ICON = {
    pinned = "Interface\\Icons\\INV_Misc_Note_02",
    recent = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    quest = "Interface\\Icons\\INV_Scroll_04", consumable = "Interface\\Icons\\INV_Potion_Healing01",
    weapon = "Interface\\Icons\\INV_Sword_04", armor = "Interface\\Icons\\INV_Chest_Plate04",
    trinket = "Interface\\Icons\\INV_Jewelry_Talisman_09", container = "Interface\\Icons\\INV_Misc_Bag_08",
    tradegoods = "Interface\\Icons\\INV_Ore_Copper_02", recipe = "Interface\\Icons\\INV_Scroll_03",
    projectile = "Interface\\Icons\\INV_Ammo_Arrow_01", quiver = "Interface\\Icons\\INV_Misc_Quiver_02",
    key = "Interface\\Icons\\INV_Misc_Key_03", junk = "Interface\\Icons\\INV_Misc_Coin_10",
    misc = "Interface\\Icons\\INV_Misc_QuestionMark",
}
local function categoryIcon(key)
    local c = customCatByKey[key]
    if c then return c.icon or DEFAULT_CUSTOM_ICON end
    return CATEGORY_ICON[key] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local VIEWMODE_ICON = {
    all = "Interface\\Icons\\INV_Misc_Bag_10", onebag = "Interface\\Icons\\INV_Misc_Bag_08",
    multibag = "Interface\\Icons\\INV_Misc_Bag_09",
}
local function viewModeIcon(mode) return VIEWMODE_ICON[mode] or VIEWMODE_ICON.all end
local function viewModeName(mode)
    if mode == "onebag" then return L["OneBag"] end
    if mode == "multibag" then return L["MultiBag"] end
    return L["All Items"]
end

function rebuildCustomLookup()
    wipe(customCatByKey)
    nextCustomSeq = 0
    for i = 1, #customCats do
        local c = customCats[i]
        if c and c.key then
            customCatByKey[c.key] = c
            local num = tonumber(c.key:match("^cust(%d+)$"))
            if num and num > nextCustomSeq then nextCustomSeq = num end
        end
    end
end

function categoryExists(key)
    if not key then return false end
    if key == "pinned" then return next(pinnedItems) ~= nil end
    if key == "recent" then
        return (mod.db and mod.db.showRecent ~= false) and next(recentItems) ~= nil
    end
    if customCatByKey[key] then return true end
    if disabledCats[key] then return false end
    for _, k in ipairs(CATEGORY_ORDER) do if k == key then return true end end
    return false
end

function orderedCategoryKeys()
    local out, seen = {}, {}
    local function push(key)
        if key and not seen[key] and categoryExists(key) then out[#out + 1] = key; seen[key] = true end
    end
    -- pseudo-categories are always top and are never written into catOrder
    push("pinned"); push("recent")
    if mod.db and mod.db.catOrder then for _, key in ipairs(mod.db.catOrder) do push(key) end end
    for _, key in ipairs(CATEGORY_ORDER) do push(key) end
    for i = 1, #customCats do local c = customCats[i]; if c then push(c.key) end end
    return out
end

function createCustomCategory(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then return end
    nextCustomSeq = nextCustomSeq + 1
    local key = "cust" .. nextCustomSeq
    customCats[#customCats + 1] = { key = key, name = name, icon = DEFAULT_CUSTOM_ICON }
    customCatByKey[key] = customCats[#customCats]
    if mod.db.catOrder then mod.db.catOrder[#mod.db.catOrder + 1] = key end
    if categoriesChanged then categoriesChanged() end
end

function renameCategory(key, newName)
    newName = newName and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if newName == "" then return end
    local c = customCatByKey[key]
    if c then
        c.name = newName
    else
        mod.db.catRenames = mod.db.catRenames or {}
        mod.db.catRenames[key] = newName
    end
    if categoriesChanged then categoriesChanged() end
end

function deleteOrDisableCategory(key)
    if key == "pinned" or key == "recent" then return end
    local c = customCatByKey[key]
    if c then
        for i = 1, #customCats do
            if customCats[i] and customCats[i].key == key then table.remove(customCats, i); break end
        end
        -- MUST run before customCatByKey[key] is nilled (groupableKey consults it)
        if groupOfCat[key] and assignCatToGroup then assignCatToGroup(key, nil) end
        customCatByKey[key] = nil
        for itemID, ck in pairs(itemAssignments) do
            if ck == key then itemAssignments[itemID] = nil end
        end
        if mod.db.catOrder then
            for i = #mod.db.catOrder, 1, -1 do
                if mod.db.catOrder[i] == key then table.remove(mod.db.catOrder, i) end
            end
        end
    else
        disabledCats[key] = true
    end
    if selectedCategory == key then selectedCategory = "all" end
    if categoriesChanged then categoriesChanged() end
end

function reenableCategory(key)
    disabledCats[key] = nil
    if categoriesChanged then categoriesChanged() end
end

function moveCategory(key, delta)
    if key == "pinned" or key == "recent" then return end
    local eff = orderedCategoryKeys()
    mod.db.catOrder = mod.db.catOrder or {}
    if #mod.db.catOrder == 0 then
        for _, k in ipairs(eff) do
            if k ~= "pinned" and k ~= "recent" then mod.db.catOrder[#mod.db.catOrder + 1] = k end
        end
    end
    local order = mod.db.catOrder
    local idx
    for i, k in ipairs(order) do if k == key then idx = i; break end end
    if not idx then return end
    -- grouped keys do not render here; skip them or the click is an invisible no-op
    local swap = idx + delta
    while order[swap] and groupOfCat[order[swap]] do swap = swap + delta end
    if swap < 1 or swap > #order then return end
    order[idx], order[swap] = order[swap], order[idx]
    if categoriesChanged then categoriesChanged() end
end

local function groupableKey(key)
    if not key or key == "pinned" or key == "recent" or key == "__unassign" then return false end
    if customCatByKey[key] then return true end
    for _, k in ipairs(CATEGORY_ORDER) do if k == key then return true end end
    return false
end

-- Call AFTER rebuildCustomLookup() so customCatByKey is fresh.
function rebuildGroupLookup()
    wipe(groupById); wipe(groupOfCat)
    nextGroupSeq = 0
    for i = #groups, 1, -1 do
        local g = groups[i]
        -- corrupt SavedVariables must be repaired here, not error out OnEnable
        if not (type(g) == "table" and type(g.id) == "string") then
            table.remove(groups, i)
        elseif type(g.cats) ~= "table" then
            g.cats = {}
        end
    end
    for i = 1, #groups do
        local g = groups[i]
        groupById[g.id] = g
        for j = #g.cats, 1, -1 do
            local key = g.cats[j]
            if not groupableKey(key) or groupOfCat[key] then
                table.remove(g.cats, j)
            else
                groupOfCat[key] = g
            end
        end
        local num = tonumber(g.id:match("^grp(%d+)$"))
        if num and num > nextGroupSeq then nextGroupSeq = num end
    end
end

function groupsChanged()
    rebuildGroupLookup()
    if categoriesChanged then categoriesChanged() end
end

-- THE render order. Returns an array of entries:
function groupedDisplay()
    local base, out, inBase = orderedCategoryKeys(), {}, {}
    for _, key in ipairs(base) do inBase[key] = true end
    if inBase.pinned then out[#out + 1] = { kind = "cat", key = "pinned" } end
    if inBase.recent then out[#out + 1] = { kind = "cat", key = "recent" } end
    for _, g in ipairs(groups) do
        local cats = {}
        for _, key in ipairs(g.cats) do
            if inBase[key] then cats[#cats + 1] = key end
        end
        out[#out + 1] = { kind = "group", group = g, cats = cats }
    end
    for _, key in ipairs(base) do
        if key ~= "pinned" and key ~= "recent" and not groupOfCat[key] then
            out[#out + 1] = { kind = "cat", key = key }
        end
    end
    return out
end

function createGroup(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then return nil end
    nextGroupSeq = nextGroupSeq + 1
    local id = "grp" .. nextGroupSeq
    groups[#groups + 1] = { id = id, name = name, collapsed = false, cats = {} }
    groupsChanged()
    return id
end

function renameGroup(id, newName)
    newName = newName and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
    local g = groupById[id]
    if not g or newName == "" then return end
    g.name = newName
    groupsChanged()
end

function deleteGroup(id)
    for i = #groups, 1, -1 do
        if groups[i] and groups[i].id == id then table.remove(groups, i); break end
    end
    groupsChanged()
end

function moveGroup(id, delta)
    local idx
    for i, g in ipairs(groups) do if g.id == id then idx = i; break end end
    if not idx then return end
    local swap = idx + delta
    if swap < 1 or swap > #groups then return end
    groups[idx], groups[swap] = groups[swap], groups[idx]
    groupsChanged()
end

function assignCatToGroup(catKey, groupId)
    if not groupableKey(catKey) then return end
    local target = groupId and groupById[groupId] or nil
    if groupId and not target then return end
    local cur = groupOfCat[catKey]
    if cur == target then return end
    if cur then
        for i = #cur.cats, 1, -1 do
            if cur.cats[i] == catKey then table.remove(cur.cats, i) end
        end
    end
    if target then target.cats[#target.cats + 1] = catKey end
    groupsChanged()
end

function moveCatWithinGroup(catKey, delta)
    local g = groupOfCat[catKey]
    if not g then return end
    local idx
    for i, k in ipairs(g.cats) do if k == catKey then idx = i; break end end
    if not idx then return end
    -- skip disabled built-ins when picking the swap neighbor (they never render)
    -- the swap neighbor, else the click looks like a dead no-op (same rule as
    -- moveCategory's grouped-key skip).
    local swap = idx + delta
    while g.cats[swap] and not categoryExists(g.cats[swap]) do swap = swap + delta end
    if swap < 1 or swap > #g.cats then return end
    g.cats[idx], g.cats[swap] = g.cats[swap], g.cats[idx]
    groupsChanged()
end

function toggleGroupCollapsed(id)
    local g = groupById[id]
    if not g then return end
    g.collapsed = not g.collapsed   -- persisted (g lives inside mod.db.groups)
    groupsChanged()
end

local function catCollapsed(key)
    return mod.db and mod.db.collapsedCats and mod.db.collapsedCats[key] == true
end

local function toggleCatCollapsed(key)
    if not (mod.db and key) then return end
    mod.db.collapsedCats = mod.db.collapsedCats or {}
    mod.db.collapsedCats[key] = (not mod.db.collapsedCats[key]) or nil
    if categoriesChanged then categoriesChanged() end
end

local bagFrame
local buttons     = {}
local indexFrames = {}
local btnCounter  = 0
local pendingRelayout = false
local searchText  = ""
local sortReverse = false
local sortMode    = "blizzard"
local catSortMode = "type"
local sortInFlight = false
local useCategories = true
local hideEmpty     = true
local viewMode         = "all"
local sidebarExpanded  = false
local sidebarWidth     = SIDEBAR_W_COLLAPSED

-- Forward declarations -- never redeclare these with local at the definition site.
local layout, layoutOneBag, layoutMultiBag
local buildSidebar, rebuildSidebar, applySidebarWidth

-- Everything that RENDERS iterates visibleBags(); sorting + the Recent baseline use BAGS.
local KEYRING = _G.KEYRING_CONTAINER or -2
local function visibleBags()
    local out, hidden = {}, (mod.db and mod.db.hiddenBags) or {}
    for _, bag in ipairs(BAGS) do
        if not hidden[bag] then out[#out + 1] = bag end
    end
    if mod.db and mod.db.showKeyring and not hidden[KEYRING] then out[#out + 1] = KEYRING end
    return out
end

local function bagDisplayName(bag)
    if bag == 0 then return L["Backpack"] end
    if bag == KEYRING then return _G.KEYRING or L["Keyring"] end
    if _G.C_Container and _G.C_Container.ContainerIDToInventoryID and GetInventoryItemLink then
        local invID  = C_Container.ContainerIDToInventoryID(bag)
        local invLnk = invID and GetInventoryItemLink("player", invID)
        local name   = invLnk and invLnk:match("%[(.-)%]")
        if name then return name end
    end
    return string.format(L["Bag %d"], bag)
end

local function totalSlots()
    local n = 0
    for _, bag in ipairs(visibleBags()) do n = n + (GetContainerNumSlots(bag) or 0) end
    return n
end

local function freeSlots()
    local free = 0
    for _, bag in ipairs(visibleBags()) do
        if bag ~= KEYRING then
            local f = GetContainerNumFreeSlots(bag)
            free = free + (f or 0)
        end
    end
    return free
end

local function firstFreeSlot()
    for _, bag in ipairs(visibleBags()) do
        if bag ~= KEYRING then
            for slot = 1, (GetContainerNumSlots(bag) or 0) do
                if not (GetContainerItemLink and GetContainerItemLink(bag, slot)) then
                    return bag, slot
                end
            end
        end
    end
    return nil
end

local function snapshotTotals()
    local totals = {}
    for _, bag in ipairs(BAGS) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local _, count, _, _, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)
            if itemID then totals[itemID] = (totals[itemID] or 0) + (count or 1) end
        end
    end
    return totals
end

-- Marks current contents seen, so "recent" means acquired since you last closed the bag.
local function markRecentSeen()
    recentBaseline = snapshotTotals()
    recentPrimed = true
    if wipe then wipe(recentItems); wipe(recentOrder) else recentItems, recentOrder = {}, {} end
end

local function updateMoney()
    if bagFrame and bagFrame.money and GetCoinTextureString then
        -- second arg = coin icon size, so the icons grow with the 13px font
        bagFrame.money:SetText(GetCoinTextureString(GetMoney() or 0, 13))
    end
end

local function updateFree()
    if not bagFrame then return end
    if bagFrame.free then
        bagFrame.free:SetText(string.format(L["%d free"], freeSlots()))
    end
    if bagFrame.title then
        local total, freeAll = 0, 0
        for _, bag in ipairs(visibleBags()) do
            if bag ~= KEYRING then
                total = total + (GetContainerNumSlots(bag) or 0)
                freeAll = freeAll + (GetContainerNumFreeSlots(bag) or 0)
            end
        end
        bagFrame.title:SetText(string.format("%s  |cff808080%d / %d %s|r",
            L["Inventory"], total - freeAll, total, L["Items"]))
    end
end

-- Returns true/false/nil (nil = data not ready, keep the slot shown). Never forces async GetItemInfo.
local function itemMatchesSearch(bag, slot, query)
    local searchText = query or searchText
    if searchText == "" then return true end
    local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
    if not link then return false end
    if ns.ItemSearchMatch then
        local quality = select(4, GetContainerItemInfo(bag, slot))
        return ns.ItemSearchMatch(link, quality, searchText)
    end
    return link:lower():find(searchText, 1, true) and true or false
end

local GetQuestInfo = _G.C_Container and _G.C_Container.GetContainerItemQuestInfo
local categoryCache = {}

-- The item-class numbers are only ever read by classifyLink, so they live in a
-- do-block: the function keeps them as upvalues, but their slots are released
-- at the `end`. Lua 5.1 allows 200 locals per chunk and this file is the
-- closest to that ceiling -- past it the file stops COMPILING, so headroom here
-- is worth more than the tidiness of a flat list.
local classifyLink
do
    local CLASS_CONSUMABLE, CLASS_CONTAINER, CLASS_WEAPON, CLASS_GEM = 0, 1, 2, 3
    local CLASS_ARMOR, CLASS_REAGENT, CLASS_PROJECTILE, CLASS_TRADEGOODS = 4, 5, 6, 7
    local CLASS_RECIPE, CLASS_QUIVER, CLASS_QUEST, CLASS_KEY = 9, 11, 12, 13

    -- class/equip-slot only (quest/junk are per-slot), so the result is cacheable by itemID
    function classifyLink(link)
        if not (link and GetItemInfoInstant) then return "misc" end
        local _, _, _, equipLoc, _, classID = GetItemInfoInstant(link)
        if classID == CLASS_QUEST then return "quest" end
        if classID == CLASS_CONSUMABLE then return "consumable" end
        if classID == CLASS_WEAPON then return "weapon" end
        if classID == CLASS_ARMOR then
            if equipLoc == "INVTYPE_TRINKET" then return "trinket" end
            return "armor"
        end
        if classID == CLASS_CONTAINER then return "container" end
        if classID == CLASS_TRADEGOODS or classID == CLASS_REAGENT or classID == CLASS_GEM then return "tradegoods" end
        if classID == CLASS_RECIPE then return "recipe" end
        if classID == CLASS_PROJECTILE then return "projectile" end
        if classID == CLASS_QUIVER then return "quiver" end
        if classID == CLASS_KEY then return "key" end
        return "misc"
    end
end

-- priority: pin > manual assignment > recent > quest flag > junk > cached class
local function categoryFor(bag, slot)
    local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
    if not link then return nil end
    local _, _, _, quality, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)
    if itemID then
        if pinnedItems[itemID] then return "pinned" end
        local assigned = itemAssignments[itemID]
        if assigned and categoryExists(assigned) then return assigned end
        if mod.db and mod.db.showRecent ~= false and recentItems[itemID] then return "recent" end
    end
    if GetQuestInfo then
        local ok, info = pcall(GetQuestInfo, bag, slot)
        if ok and info and (info.isQuestItem or info.questID) then return "quest" end
    end
    if quality == 0 then return "junk" end
    if itemID and categoryCache[itemID] then return categoryCache[itemID] end
    local key = classifyLink(link)
    if itemID then categoryCache[itemID] = key end
    return key
end

local bindTypeCache = {}

-- One recipe for the dark item button, shared by the bag window, the bank and
-- the guild bank. All three carried their own hand-copied version and drifted
-- apart: the item level colour rule below had been added to the bag window only,
-- so "Color item levels by quality" silently did nothing at a banker. Bank.lua
-- and GuildBank.lua load after this file and take both halves from here.
function ns.BagsSkinItemButton(btn)
    local bname = btn:GetName()

    local sb = btn:CreateTexture(nil, "BACKGROUND")
    sb:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    sb:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    sb:SetColorTexture(0.10, 0.10, 0.13, 0.55)
    btn._slotbg = sb

    local qb = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    qb:SetAllPoints(btn)
    -- pixel snapping off on ring + icon, else the border rasterizes unevenly
    if qb.SetSnapToPixelGrid then qb:SetSnapToPixelGrid(false); qb:SetTexelSnappingBias(0) end
    qb:Hide()
    btn._qborder = qb

    local iconTex = (bname and _G[bname .. "IconTexture"]) or btn.icon
    if iconTex then
        iconTex:ClearAllPoints()
        iconTex:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        iconTex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- crop the icon's own dark bevel
        if iconTex.SetSnapToPixelGrid then iconTex:SetSnapToPixelGrid(false); iconTex:SetTexelSnappingBias(0) end
    end

    local il = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    il:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    il:SetTextColor(1, 1, 1)
    il:Hide()
    btn._ilvl = il

    local bm = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    bm:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    bm:SetTextColor(0.45, 0.75, 1)
    bm:Hide()
    btn._bind = bm

    return btn
end

-- The quality ring and the item level number. Reads the bag module's settings,
-- which is what all three windows are configured by.
function ns.BagsPaintQuality(btn, quality, link)
    local d = mod.db

    local qf = btn._qborder
    if qf then
        if d.qualityBorders ~= false and quality and quality >= 2 and GetItemQualityColor then
            local r, g, b = GetItemQualityColor(quality)
            qf:SetColorTexture(r, g, b, 1)
            qf:Show()
        else
            qf:Hide()
        end
    end

    -- ilvl can be nil on uncached items; the next refresh fills it in
    local fs = btn._ilvl
    if not fs then return end
    local lvl
    if d.showItemLevel ~= false and link and GetItemInfoInstant then
        local _, _, _, equipLoc, _, classID = GetItemInfoInstant(link)
        if (classID == 2 or classID == 4) and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" then
            lvl = (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link))
                or (GetItemInfo and select(4, GetItemInfo(link)))
        end
    end
    if lvl and lvl > 1 then
        local fontPath = ns.UI and ns.UI.FONT_PATH
        if fontPath then
            pcall(fs.SetFont, fs, fontPath, d.countFontSize or 12, "OUTLINE")
        end
        fs:SetText(lvl)
        if d.itemLevelQualityColor ~= false and quality and quality >= 2 and GetItemQualityColor then
            local r, g, b = GetItemQualityColor(quality)
            fs:SetTextColor(r, g, b)
        else
            fs:SetTextColor(1, 1, 1)
        end
        fs:Show()
    else
        fs:Hide()
    end
end

-- The next four helpers are the parts of the per-item paint that bags, bank
-- and guild bank had each copied by hand; the copies had already drifted once
-- (quality colouring). db decides countFontSize/bindMarker per window; the
-- bind cache is per window too.
function ns.BagsApplyCountFont(btn, db)
    local cnt = _G[btn:GetName() .. "Count"]
    if cnt and ns.UI and ns.UI.FONT_PATH then
        pcall(cnt.SetFont, cnt, ns.UI.FONT_PATH, db.countFontSize or 12, "OUTLINE")
    end
end

-- BoE/BoU only while not yet soulbound (bindType 2 = on equip, 3 = on use)
function ns.BagsPaintBindTag(btn, link, itemID, isBound, db, cache)
    local bm = btn._bind
    if not bm then return end
    local tag
    if db.bindMarker ~= false and link and not isBound and itemID and GetItemInfo then
        -- nil name = item not server-cached yet, retry next paint
        local bindType = cache[itemID]
        if bindType == nil then
            local iname = GetItemInfo(link)
            if iname then
                bindType = select(14, GetItemInfo(link)) or 0
                cache[itemID] = bindType
            end
        end
        if bindType == 2 or bindType == 3 then
            local _, _, _, equipLoc, _, classID = GetItemInfoInstant(link)
            if (classID == 2 or classID == 4) and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" then
                tag = (bindType == 2) and "BoE" or "BoU"
            end
        end
    end
    if tag then
        if ns.UI and ns.UI.FONT_PATH then
            pcall(bm.SetFont, bm, ns.UI.FONT_PATH,
                math.max(8, (db.countFontSize or 12) - 2), "OUTLINE")
        end
        bm:SetText(tag)
        bm:Show()
    else
        bm:Hide()
    end
end

-- Everything a container-backed item button (bags, bank) paints identically.
-- Returns what only the callers' own extras need.
function ns.BagsPaintContainerButton(btn, bag, slot, db, cache)
    local icon, count, locked, quality, _, _, link, _, noValue, itemID, isBound = GetContainerItemInfo(bag, slot)

    SetItemButtonTexture(btn, icon)
    SetItemButtonCount(btn, count)
    SetItemButtonDesaturated(btn, locked)

    local ng = btn.NewItemTexture or _G[btn:GetName() .. "NewItemTexture"]
    if ng and ng:IsShown() then ng:Hide() end
    local bp = btn.BattlepayItemTexture or _G[btn:GetName() .. "BattlepayItemTexture"]
    if bp and bp:IsShown() then bp:Hide() end

    ns.BagsPaintQuality(btn, quality, link)
    ns.BagsApplyCountFont(btn, db)
    ns.BagsPaintBindTag(btn, link, itemID, isBound, db, cache)

    -- Exclamation mark on items that start a quest you have not accepted yet
    -- (questID without isActive - active-quest objectives stay unmarked)
    local showBang = false
    if icon and GetQuestInfo and db.questMarker ~= false then
        local okQ, qinfo = pcall(GetQuestInfo, bag, slot)
        showBang = okQ and qinfo and qinfo.questID and not qinfo.isActive and true or false
    end
    local qb = btn._questBang
    if showBang then
        if not qb then
            qb = btn:CreateTexture(nil, "OVERLAY", nil, 2)
            qb:SetTexture(TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang")
            qb:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
            qb:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
            btn._questBang = qb
        end
        qb:Show()
    elseif qb then
        qb:Hide()
    end

    local cd = _G[btn:GetName() .. "Cooldown"]
    if cd then
        local start, dur, enable = GetContainerItemCooldown(bag, slot)
        if start and dur and dur > 0 then
            CooldownFrame_Set(cd, start, dur, enable)
        elseif cd.Hide then
            cd:Hide()
        end
    end

    return icon, quality, noValue
end

-- Suppressing the default bags means "new item" flags never clear — strip the
-- glow overlays once at button creation. Guards cover both button templates.
function ns.BagsStripButtonGlow(btn)
    local bname = btn:GetName()
    if btn.SetNormalTexture then pcall(btn.SetNormalTexture, btn, nil) end
    local nt = _G[bname .. "NormalTexture"]; if nt then nt:SetTexture(nil); nt:Hide() end
    if btn.GetNormalTexture then local g = btn:GetNormalTexture(); if g then g:SetTexture(nil); g:Hide() end end
    if btn.flashAnim and btn.flashAnim.Stop then btn.flashAnim:Stop() end
    if btn.newitemglowAnim and btn.newitemglowAnim.Stop then btn.newitemglowAnim:Stop() end
    local newTex = btn.NewItemTexture or _G[bname .. "NewItemTexture"]
    if newTex then newTex:Hide() end
    local bpTex = btn.BattlepayItemTexture or _G[bname .. "BattlepayItemTexture"]
    if bpTex then bpTex:Hide() end
    for r = 1, select("#", btn:GetRegions()) do
        local reg = select(r, btn:GetRegions())
        if reg and reg.GetObjectType and reg:GetObjectType() == "Texture" and reg.GetAtlas then
            local a = reg:GetAtlas()
            if type(a) == "string" and a:find("glow", 1, true) then reg:Hide() end
        end
    end
end

local function updateButton(btn)
    local bag  = btn:GetParent():GetID()
    local slot = btn:GetID()
    local icon, quality, noValue = ns.BagsPaintContainerButton(btn, bag, slot, mod.db, bindTypeCache)

    if btn._slotbg then
        if bag == KEYRING then
            btn._slotbg:SetColorTexture(0.16, 0.12, 0.24, 0.7)
        else
            btn._slotbg:SetColorTexture(0.10, 0.10, 0.13, 0.55)
        end
    end

    -- junk = grey WITH sell value (same rule as the sort engine)
    local jt = btn._junk
    if jt then
        if mod.db.junkMarker ~= false and quality == 0 and not noValue and icon then
            if UI and UI.FONT_PATH then
                pcall(jt.SetFont, jt, UI.FONT_PATH,
                    math.max(9, (mod.db.countFontSize or 12) - 1), "OUTLINE")
            end
            jt:Show()
        else
            jt:Hide()
        end
    end

    -- dim via alpha only -- never Enable/Hide, that would break the secure click path
    if searchText == "" then
        btn:SetAlpha(1)
    else
        btn:SetAlpha(itemMatchesSearch(bag, slot) ~= false and 1 or 0.25)
    end
end

local function ensureIndexFrame(bag)
    local f = indexFrames[bag]
    if not f then
        if InCombatLockdown() then return nil end
        f = CreateFrame("Frame", nil, bagFrame.content)
        f:SetAllPoints(bagFrame.content)
        indexFrames[bag] = f
    end
    f:SetID(bag)
    return f
end

local function acquireButton(n)
    local btn = buttons[n]
    if btn then return btn end
    if InCombatLockdown() then return nil end
    btnCounter = btnCounter + 1
    btn = CreateFrame("Button", "VuloClassicUIBagItem" .. btnCounter, bagFrame.content,
        "ContainerFrameItemButtonTemplate")
    btn:SetSize(BTN, BTN)
    -- an explicit click list REPLACES the template registration; re-list Left/Right to keep the secure path
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    -- HookScript only (never SetScript): runs after the secure handler, so it cannot taint it
    btn:HookScript("OnClick", function(self, mouseButton)
        if mouseButton ~= "MiddleButton" then return end
        local bg = self:GetParent() and self:GetParent():GetID()
        local sl = self:GetID()
        if not (bg and sl) then return end
        local _, _, _, _, _, _, _, _, _, itemID = GetContainerItemInfo(bg, sl)
        if not itemID then return end
        if pinnedItems[itemID] then pinnedItems[itemID] = nil
        else pinnedItems[itemID] = true end
        if categoriesChanged then categoriesChanged() end
    end)
    ns.BagsStripButtonGlow(btn)
    ns.BagsSkinItemButton(btn)

    local jk = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    local jac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
    jk:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 2)
    jk:SetText("C")
    jk:SetTextColor(jac.r, jac.g, jac.b)
    jk:Hide()
    btn._junk = jk   -- bag window only: the bank has nothing to sell
    btn:Hide()
    buttons[n] = btn
    return btn
end

local sectionHeaders = {}
local function acquireHeader(n)
    local h = sectionHeaders[n]
    if h then return h end
    if not bagFrame then return nil end
    -- insecure Button; layout reserves its row so it never overlaps a secure item button
    h = CreateFrame("Button", nil, bagFrame.content)
    h:SetHeight(HEADER_ROW)
    local label = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if UI and UI.Font then UI.Font(label, 12) end
    label:SetJustifyH("LEFT")
    label:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    label:SetPoint("LEFT", h, "LEFT", 0, 0)
    h.label = label

    local hint = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    if UI and UI.Font then UI.Font(hint, 10) end
    hint:SetJustifyH("RIGHT")
    hint:SetPoint("RIGHT", h, "RIGHT", -1, 0)
    hint:SetTextColor(0.5, 0.5, 0.55)
    hint:Hide()
    h.hint = hint

    local div = h:CreateTexture(nil, "ARTWORK")
    div:SetPoint("LEFT", label, "RIGHT", 8, 0)
    div:SetPoint("RIGHT", hint, "LEFT", -8, 0)
    div:SetHeight(1)
    div:SetColorTexture(1, 1, 1, 0.06)
    h.divider = div

    h:RegisterForClicks("LeftButtonUp")
    h:SetScript("OnClick", function(self)
        if self._catKey and toggleCatCollapsed then toggleCatCollapsed(self._catKey) end
    end)
    h:SetScript("OnEnter", function(self)
        if self._catKey then
            self.label:SetTextColor(1, 1, 1)
            self.hint:SetTextColor(0.75, 0.7, 0.85)
        end
    end)
    h:SetScript("OnLeave", function(self)
        self.label:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        self.hint:SetTextColor(0.5, 0.5, 0.55)
    end)
    h:Hide()
    sectionHeaders[n] = h
    return h
end

-- catKey non-nil makes the header collapsible; nil = plain label.
local function placeHeader(h, x, y, text, widthCols, catKey)
    if not h then return end
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT", x, -y)
    h:SetWidth(math.max(1, widthCols * (BTN + GAP) - GAP - x + 1))
    h.label:SetText(text)
    if catKey then
        local collapsed = catCollapsed(catKey)
        h._catKey = catKey
        h._collapsed = collapsed
        h:EnableMouse(true)
        h.divider:Show()
        h.hint:SetText(collapsed and L["Show"] or L["Hide"])
        h.hint:SetTextColor(0.5, 0.5, 0.55)
        h.hint:Show()
    else
        h._catKey = nil
        h._collapsed = nil
        h:EnableMouse(false)
        h.hint:SetText("")
        h.hint:Hide()
        h.divider:Show()
    end
    h:Show()
end

local groupHeaders = {}
local function acquireGroupHeader(n)
    local gh = groupHeaders[n]
    if gh then return gh end
    if not bagFrame then return nil end
    gh = CreateFrame("Button", nil, bagFrame.content)
    gh:SetHeight(GROUP_HEADER_ROW)
    local bg = gh:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(gh)
    bg:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.10)
    gh.bg = bg
    local label = gh:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if UI and UI.Font then UI.Font(label, 12) end
    label:SetPoint("LEFT", gh, "LEFT", 3, 0)
    label:SetPoint("RIGHT", gh, "RIGHT", -3, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(1, 1, 1)
    gh.label = label
    gh:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    gh:SetScript("OnClick", function(self, mouseButton)
        if not self._groupId then return end
        if mouseButton == "RightButton" then
            if showGroupMenu then showGroupMenu(self, self._groupId) end
        else
            if toggleGroupCollapsed then toggleGroupCollapsed(self._groupId) end
        end
    end)
    gh:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.22)
    end)
    gh:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.10)
    end)
    gh:Hide()
    groupHeaders[n] = gh
    return gh
end

local function finishSize(cols, contentH, blocked, extraW)
    if blocked then pendingRelayout = true end
    local contentW = cols * (BTN + GAP) - GAP + (extraW or 0)
    contentH = math.max(contentH, BTN)

    bagFrame.content:SetSize(contentW, contentH)

    local cap = math.floor(UIParent:GetHeight() * CONTENT_MAX_FRAC)
    local vpH = math.min(contentH, cap)
    local vp  = bagFrame.contentVP
    if vp then vp:SetSize(contentW, vpH) end

    local overflow = contentH - vpH
    local sbar = bagFrame.contentBar
    if sbar and vp then
        if overflow > 0 then
            sbar:SetMinMaxValues(0, overflow)
            local cur = math.min(vp:GetVerticalScroll() or 0, overflow)
            vp:SetVerticalScroll(cur)
            sbar:SetValue(cur)
            local thumb = sbar:GetThumbTexture()
            if thumb then thumb:SetHeight(math.max(20, vpH * (vpH / contentH))) end
            sbar:Show()
        else
            vp:SetVerticalScroll(0)
            sbar:SetValue(0)
            sbar:Hide()
        end
    end

    -- height uses the CAPPED viewport height, so the window never exceeds the screen
    local barGutter = (sbar and sbar:IsShown()) and 10 or 0
    bagFrame:SetSize(PAD + sidebarWidth + GAP + contentW + barGutter + PAD,
                     HEADER_H + vpH + FOOTER_H + PAD)
    updateMoney()
    updateFree()
end

local function placeDropSlot(y, blocked)
    local d = bagFrame and bagFrame.dropSlot
    if not d then return 0 end
    -- a combat-blocked layout can abort mid-section; hide until the post-combat pass
    if blocked then d:Hide(); return 0 end
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT", 0, -y)
    d:Show()
    return BTN
end

local function layoutFlat()
    if not (bagFrame and mod.active) then return end
    local cols = mod.db.columns or 12
    if cols < 1 then cols = 1 end

    local n, blocked = 0, false
    local yExtra, keyHeader = 0, 0
    for _, bag in ipairs(visibleBags()) do
        local slots = GetContainerNumSlots(bag) or 0
        local idx = ensureIndexFrame(bag)
        if not idx then blocked = true; break end
        if bag == KEYRING and slots > 0 and n > 0 then
            n = math.ceil(n / cols) * cols
            placeHeader(acquireHeader(1), 1,
                math.floor(n / cols) * (BTN + GAP) + yExtra,
                _G.KEYRING or L["Keyring"], cols, nil)
            keyHeader = 1
            yExtra = yExtra + HEADER_ROW
        end
        for slot = 1, slots do
            n = n + 1
            local btn = acquireButton(n)
            if not btn then blocked = true; break end
            btn:SetParent(idx)
            btn:SetID(slot)
            local col = (n - 1) % cols
            local row = math.floor((n - 1) / cols)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT",
                col * (BTN + GAP), -(row * (BTN + GAP) + yExtra))
            btn:Show()
            updateButton(btn)
        end
        if blocked then break end
    end
    for i = n + 1, #buttons do buttons[i]:Hide() end
    for i = keyHeader + 1, #sectionHeaders do sectionHeaders[i]:Hide() end
    for i = 1, #groupHeaders do groupHeaders[i]:Hide() end
    local rows = math.max(1, math.ceil(math.max(n, 1) / cols))
    local h = rows * (BTN + GAP) - GAP + yExtra
    h = h + GAP + placeDropSlot(h + GAP, blocked)
    finishSize(cols, h, blocked)
end

local function collectByCategory()
    local buckets = {}
    for _, bag in ipairs(visibleBags()) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            if GetContainerItemLink and GetContainerItemLink(bag, slot) then
                local key = categoryFor(bag, slot) or "misc"
                if disabledCats[key] then key = "misc" end
                local b = buckets[key]; if not b then b = {}; buckets[key] = b end
                b[#b + 1] = { bag = bag, slot = slot }
            end
        end
    end
    if catSortMode ~= "off" and ns.SortEngine then
        local needRetry = false
        for key, b in pairs(buckets) do
            -- pcall: a display-order failure must never take down layout()
            local ok, sorted, incomplete = pcall(ns.SortEngine.OrderBucket, b, catSortMode, sortReverse)
            if ok and sorted then
                buckets[key] = sorted
                if incomplete then needRetry = true end
            end
        end
        -- some item data was not server-cached yet: repaint shortly after
        if needRetry and not mod._catSortRetry and C_Timer and C_Timer.After then
            mod._catSortRetry = true
            C_Timer.After(0.5, function()
                mod._catSortRetry = nil
                if categoriesChanged then categoriesChanged() end
            end)
        end
    end
    return buckets
end

local function layoutCategorized()
    if not (bagFrame and mod.active) then return end
    local cols = mod.db.columns or 12
    if cols < 1 then cols = 1 end

    local buckets = collectByCategory()
    local btnN, hdrN, ghN, blocked = 0, 0, 0, false
    local y = 0   -- distance from content TOPLEFT (positive downward)
    local filtered = (selectedCategory ~= "all")

    local function renderCategory(key, indent)
        local items = buckets[key]
        local count = items and #items or 0
        local show = (not filtered and (count > 0 or not hideEmpty))
                  or (filtered and key == selectedCategory)
        if not show then return true end
        hdrN = hdrN + 1
        local collapsed = (not filtered) and catCollapsed(key)
        placeHeader(acquireHeader(hdrN), 1 + indent, y,
            string.format("%s  |cff808080(%d)|r", catName(key), count),
            cols, (not filtered) and key or nil)
        y = y + HEADER_ROW
        if collapsed then
            y = y + GAP
            return true
        end
        for i = 1, count do
            local it  = items[i]
            -- bail BEFORE consuming a button index, else that pooled button stays shown at a stale position
            local idx = ensureIndexFrame(it.bag)
            if not idx then blocked = true; return false end
            btnN = btnN + 1
            local btn = acquireButton(btnN)
            if not btn then blocked = true; return false end
            btn:SetParent(idx)
            btn:SetID(it.slot)
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT",
                indent + col * (BTN + GAP), -(y + row * (BTN + GAP)))
            btn:Show()
            updateButton(btn)
        end
        if count > 0 then y = y + math.ceil(count / cols) * (BTN + GAP) end
        y = y + GAP
        return true
    end

    for _, entry in ipairs(groupedDisplay()) do
        if entry.kind == "cat" then
            if not renderCategory(entry.key, 0) then break end
        elseif filtered then
            for _, key in ipairs(entry.cats) do
                if key == selectedCategory then renderCategory(key, 0); break end
            end
        else
            local g = entry.group
            local total = 0
            for _, key in ipairs(entry.cats) do
                total = total + (buckets[key] and #buckets[key] or 0)
            end
            if total > 0 or not hideEmpty then
                ghN = ghN + 1
                local gh = acquireGroupHeader(ghN)
                if gh then
                    gh._groupId = g.id
                    gh:ClearAllPoints()
                    gh:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT", 0, -y)
                    gh:SetWidth(cols * (BTN + GAP) - GAP + GROUP_INDENT)
                    gh.label:SetText(string.format("%s  %s  |cff808080(%d)|r",
                        g.collapsed and ">" or "v", g.name or g.id, total))
                    gh:Show()
                end
                y = y + GROUP_HEADER_ROW
                if g.collapsed then
                    y = y + GAP
                else
                    for _, key in ipairs(entry.cats) do
                        if not renderCategory(key, GROUP_INDENT) then break end
                    end
                end
            end
        end
        if blocked then break end
    end

    for i = btnN + 1, #buttons do buttons[i]:Hide() end
    for i = hdrN + 1, #sectionHeaders do sectionHeaders[i]:Hide() end
    for i = ghN + 1, #groupHeaders do groupHeaders[i]:Hide() end
    local dropH = placeDropSlot(y, blocked)
    finishSize(cols, y + dropH, blocked, (ghN > 0) and GROUP_INDENT or 0)
end

layoutOneBag = function()
    if not (bagFrame and mod.active) then return end
    local cols = mod.db.columns or 12
    if cols < 1 then cols = 1 end

    local natural = mod.db.showFreeSlots ~= false and mod.db.onebagFixedSlots ~= false
    local items, itemCount = {}, 0
    for _, bag in ipairs(visibleBags()) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local occupied = GetContainerItemLink and GetContainerItemLink(bag, slot)
            if occupied then itemCount = itemCount + 1 end
            if occupied or natural then
                items[#items + 1] = { bag = bag, slot = slot }
            end
        end
    end
    if not natural and mod.db.showFreeSlots ~= false then
        for _, bag in ipairs(visibleBags()) do
            for slot = 1, (GetContainerNumSlots(bag) or 0) do
                if not (GetContainerItemLink and GetContainerItemLink(bag, slot)) then
                    items[#items + 1] = { bag = bag, slot = slot }
                end
            end
        end
    end

    local btnN, blocked = 0, false
    local y = 0
    placeHeader(acquireHeader(1), 1, y,
        string.format("%s  |cff808080(%d)|r", L["All Bags"], itemCount), cols, nil)
    y = y + HEADER_ROW

    local pos, keyHeaderN = 0, 1
    for i = 1, #items do
        local it  = items[i]

        local idx = ensureIndexFrame(it.bag)
        if not idx then blocked = true; break end
        if it.bag == KEYRING and keyHeaderN == 1 then
            keyHeaderN = 2
            if pos > 0 then pos = math.ceil(pos / cols) * cols end
            placeHeader(acquireHeader(2), 1,
                y + math.floor(pos / cols) * (BTN + GAP),
                _G.KEYRING or L["Keyring"], cols, nil)
            y = y + HEADER_ROW
        end
        btnN = btnN + 1
        local btn = acquireButton(btnN)
        if not btn then blocked = true; break end
        btn:SetParent(idx)
        btn:SetID(it.slot)
        local col = pos % cols
        local row = math.floor(pos / cols)
        pos = pos + 1
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT",
            col * (BTN + GAP), -(y + row * (BTN + GAP)))
        btn:Show()
        updateButton(btn)
    end
    if pos > 0 then y = y + math.ceil(pos / cols) * (BTN + GAP) else y = y + BTN end

    for i = btnN + 1, #buttons do buttons[i]:Hide() end
    for i = keyHeaderN + 1, #sectionHeaders do sectionHeaders[i]:Hide() end
    for i = 1, #groupHeaders do groupHeaders[i]:Hide() end
    local dropH = placeDropSlot(y, blocked)
    finishSize(cols, y + dropH, blocked)
end

layoutMultiBag = function()
    if not (bagFrame and mod.active) then return end
    local cols = mod.db.columns or 12
    if cols < 1 then cols = 1 end

    local btnN, hdrN, blocked = 0, 0, false
    local y = 0

    for _, bag in ipairs(visibleBags()) do
        local slots = GetContainerNumSlots(bag) or 0
        if slots > 0 or not hideEmpty then
            local bagName = bagDisplayName(bag)

            hdrN = hdrN + 1
            placeHeader(acquireHeader(hdrN), 1, y,
                string.format("%s  |cff808080(%d)|r", bagName, slots), cols, nil)
            y = y + HEADER_ROW

            local idx = ensureIndexFrame(bag)
            if not idx then blocked = true; break end
            for slot = 1, slots do
                btnN = btnN + 1
                local btn = acquireButton(btnN)
                if not btn then blocked = true; break end
                btn:SetParent(idx)
                btn:SetID(slot)
                local col = (slot - 1) % cols
                local row = math.floor((slot - 1) / cols)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT",
                    col * (BTN + GAP), -(y + row * (BTN + GAP)))
                btn:Show()
                updateButton(btn)
            end
            if blocked then break end
            if slots > 0 then y = y + math.ceil(slots / cols) * (BTN + GAP) end
            y = y + GAP
        end
    end

    for i = btnN + 1, #buttons do buttons[i]:Hide() end
    for i = hdrN + 1, #sectionHeaders do sectionHeaders[i]:Hide() end
    for i = 1, #groupHeaders do groupHeaders[i]:Hide() end
    local dropH = placeDropSlot(y, blocked)
    finishSize(cols, math.max(y + dropH, BTN), blocked)
end

local lastLayoutSig   -- identity of the last laid-out view (mode|filter|sort|categorized)
function layout()
    if not (bagFrame and mod.active) then return end
    -- reset scroll only when the view IDENTITY changes; a plain refresh keeps its offset
    local sig = tostring(viewMode) .. "|" .. tostring(selectedCategory) .. "|"
        .. tostring(sortMode) .. "|" .. tostring(sortReverse) .. "|" .. tostring(useCategories)
        .. "|" .. tostring(catSortMode)
        .. "|" .. (viewMode == "onebag"
            and (tostring(mod.db.showFreeSlots) .. tostring(mod.db.onebagFixedSlots)) or "")
    if sig ~= lastLayoutSig then
        lastLayoutSig = sig
        if bagFrame.contentVP then bagFrame.contentVP:SetVerticalScroll(0) end
        if bagFrame.contentBar then bagFrame.contentBar:SetValue(0) end
    end
    if     viewMode == "onebag"   then layoutOneBag()
    elseif viewMode == "multibag" then layoutMultiBag()
    elseif useCategories          then layoutCategorized()
    else                               layoutFlat() end
end

local refreshScheduled = false
local function refresh()
    if not (mod.active and bagFrame and bagFrame:IsShown()) then return end
    if refreshScheduled then return end
    refreshScheduled = true
    local function run()
        refreshScheduled = false

        if selectedCategory ~= "all" then
            local b = collectByCategory()[selectedCategory]
            if not (b and #b > 0) then selectedCategory = "all" end
        end
        if sidebarExpanded and rebuildSidebar then rebuildSidebar() end
        if bagFrame.bagBar and bagFrame.bagBar:IsShown() and bagFrame.updateBagBar then
            bagFrame.updateBagBar()
        end
        layout()
    end
    ns.NextFrame(run)
end

function categoriesChanged() refresh() end

-- Prefer native SortBags only when it genuinely exists, else our own Lua sort. Both bail in combat.
local SORT_BAGS = { 0, 1, 2, 3, 4 }
local sortBagsActive = SORT_BAGS

local function sortKey(link)
    local q, t, s, name = 0, "", "", ""
    if link then
        name = link:match("%[(.-)%]") or ""
        if GetItemInfoInstant then
            local _, _, qq, _, _, tt, ss = GetItemInfoInstant(link)
            q, t, s = qq or 0, tt or "", ss or ""
        end
    end
    return q, t, s, name
end

local function sortLess(la, lb)
    local qa, ta, sa, na = sortKey(la)
    local qb, tb, sb, nb = sortKey(lb)
    if sortMode == "name" then
        if na ~= nb then if sortReverse then return na > nb else return na < nb end end
        if qa ~= qb then return qa > qb end
        return false
    elseif sortMode == "type" then
        if ta ~= tb then if sortReverse then return ta > tb else return ta < tb end end
        if sa ~= sb then return sa < sb end
        if qa ~= qb then return qa > qb end
        if na ~= nb then return na < nb end
        return false
    else
        if qa ~= qb then if sortReverse then return qa < qb else return qa > qb end end
        if ta ~= tb then return ta < tb end
        if sa ~= sb then return sa < sb end
        if na ~= nb then if sortReverse then return na > nb else return na < nb end end
        return false
    end
end

-- Fallback selection sort: one 3-pickup swap per frame; never swaps two identical stacks.
local _sortStep = 0
local sortPos   = 1

local function betterSlot(x, y)
    if x.link and not y.link then return true  end
    if y.link and not x.link then return false end
    if not x.link and not y.link then return false end
    return sortLess(x.link, y.link)
end

local function slotLocked(bag, slot)
    local _, _, locked = GetContainerItemInfo(bag, slot)
    return locked
end

local function customSortStep()
    if InCombatLockdown() then sortInFlight = false; return end
    _sortStep = _sortStep + 1
    if _sortStep > 400 then sortInFlight = false; refresh(); return end

    local slots = {}
    for _, bag in ipairs(sortBagsActive) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            slots[#slots + 1] = { bag = bag, slot = slot, link = GetContainerItemLink(bag, slot) }
        end
    end

    while sortPos <= #slots do
        local best = sortPos
        for j = sortPos + 1, #slots do
            if betterSlot(slots[j], slots[best]) then best = j end
        end
        if best == sortPos then
            sortPos = sortPos + 1
        else
            local a, b = slots[sortPos], slots[best]
            if slotLocked(a.bag, a.slot) or slotLocked(b.bag, b.slot) then
                if C_Timer and C_Timer.After then C_Timer.After(0, customSortStep) else sortInFlight = false end
                return
            end
            -- proper 3-pickup swap (clean whether the other slot is empty or full)
            PickupContainerItem(a.bag, a.slot)
            PickupContainerItem(b.bag, b.slot)
            PickupContainerItem(a.bag, a.slot)
            ClearCursor()
            sortPos = sortPos + 1
            ns.NextFrame(customSortStep)
            return
        end
    end
    sortInFlight = false
    refresh()
end

local function doSort(bagList, nativeFn)
    if sortInFlight then return end
    if ns.SortEngine and ns.SortEngine.IsActive() then return end
    if InCombatLockdown() or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        if UIErrorsFrame then UIErrorsFrame:AddMessage(L["Can't sort bags in combat."], 1, 0.2, 0.2) end
        return
    end
    local native = bagList and nativeFn or (not bagList and nativeSort) or nil
    if sortMode == "blizzard" and native then
        if nativeSetDir then pcall(nativeSetDir, sortReverse and true or false) end
        pcall(native)
        refresh()
        return
    end
    sortBagsActive = bagList or SORT_BAGS
    -- the engine callback fires exactly once, also on abort, so sortInFlight always clears
    if ns.SortEngine then
        sortInFlight = true
        local isBank = bagList ~= nil
        ns.SortEngine.Run(sortBagsActive,
            (sortMode == "blizzard") and "type" or sortMode,
            sortReverse and true or false,
            function()
                sortInFlight = false
                refresh()
                if isBank and ns.BankRefresh then ns.BankRefresh() end
            end)
        return
    end
    sortInFlight = true
    _sortStep = 0
    sortPos = 1
    customSortStep()
end

ns.BagItemMatchesSearch = itemMatchesSearch
ns.RunBagSort = doSort

local function makeSidebarRow(parent, pool, n)
    local row = pool[n]
    if row then return row end
    row = CreateFrame("Button", nil, parent)
    row:SetHeight(SIDEBAR_BTN_H)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0)
    row.bg = bg
    local sel = row:CreateTexture(nil, "ARTWORK")
    sel:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    sel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    sel:SetWidth(2)
    sel:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    sel:Hide()
    row.sel = sel
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(SIDEBAR_ICON, SIDEBAR_ICON)
    icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if UI and UI.Font then UI.Font(label, 11) end
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label
    row:SetScript("OnEnter", function(self) if not self._selected then self.bg:SetAlpha(0.18) end end)
    row:SetScript("OnLeave", function(self) if not self._selected then self.bg:SetAlpha(0) end end)

    -- GetCursorInfo/ClearCursor are unprotected, so drop-to-assign is taint-free here
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:RegisterForDrag("LeftButton")
    local function tryAssignFromCursor(self)
        local key = self._catKey
        if not key or not (GetCursorInfo and ClearCursor) then return false end
        local ctype, a1, a2 = GetCursorInfo()
        if ctype ~= "item" then return false end
        local itemID = tonumber(a1)
        if not itemID and type(a2) == "string" then itemID = tonumber(a2:match("item:(%d+)")) end
        if not itemID and type(a1) == "string" then itemID = tonumber(a1:match("item:(%d+)")) end
        if not itemID then return false end
        if key == "recent" then return false end
        if key == "pinned" then
            pinnedItems[itemID] = true
        elseif key == "__unassign" then itemAssignments[itemID] = nil
        else itemAssignments[itemID] = key end
        ClearCursor()
        if categoriesChanged then categoriesChanged() end
        return true
    end
    row:SetScript("OnReceiveDrag", function(self) tryAssignFromCursor(self) end)
    row:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if self._groupId and showGroupMenu then
                showGroupMenu(self, self._groupId)
            elseif self._catKey and self._catKey ~= "__unassign" and showCategoryMenu then
                showCategoryMenu(self, self._catKey)
            end
            return
        end
        if GetCursorInfo and GetCursorInfo() == "item" and tryAssignFromCursor(self) then return end
        if self._onClick then self._onClick(self) end
    end)

    pool[n] = row
    return row
end

local function setSidebarRowSelected(row, on)
    row._selected = on and true or false
    if on then
        row.sel:Show(); row.bg:SetAlpha(0.12)
        row.label:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    else
        row.sel:Hide(); row.bg:SetAlpha(0)
        row.label:SetTextColor(0.78, 0.78, 0.82)
    end
end

function applySidebarWidth()
    if not bagFrame then return end
    sidebarWidth = sidebarExpanded and SIDEBAR_W_EXPANDED or SIDEBAR_W_COLLAPSED
    bagFrame.sidebar:SetWidth(sidebarWidth)
    if bagFrame.sidebarScroll then bagFrame.sidebarScroll:SetShown(sidebarExpanded) end
    if bagFrame.sidebarArrow then
        bagFrame.sidebarArrow:SetTexture(sidebarExpanded
            and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
            or  "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    end
end

function buildSidebar(f)
    local sb = CreateFrame("Frame", nil, f)
    f.sidebar = sb
    sb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -HEADER_H)
    sb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, FOOTER_H)
    sb:SetWidth(sidebarExpanded and SIDEBAR_W_EXPANDED or SIDEBAR_W_COLLAPSED)
    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sb); bg:SetColorTexture(0, 0, 0, 0.25)
    local div = sb:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
    div:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
    div:SetWidth(1)
    div:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 0.6)

    local tog = CreateFrame("Button", nil, sb)
    f.sidebarToggle = tog
    tog:SetSize(20, 20)
    tog:SetPoint("TOPLEFT", sb, "TOPLEFT", 6, -6)
    local arrow = tog:CreateTexture(nil, "ARTWORK")
    f.sidebarArrow = arrow
    arrow:SetAllPoints(tog)
    arrow:SetTexture(sidebarExpanded
        and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
        or  "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    arrow:SetVertexColor(0.7, 0.7, 0.75)
    tog:SetScript("OnEnter", function()
        arrow:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        if GameTooltip then
            GameTooltip:SetOwner(tog, "ANCHOR_RIGHT")
            GameTooltip:SetText(sidebarExpanded and L["Collapse sidebar"] or L["Expand sidebar"])
            GameTooltip:Show()
        end
    end)
    tog:SetScript("OnLeave", function() arrow:SetVertexColor(0.7, 0.7, 0.75); if GameTooltip then GameTooltip:Hide() end end)
    tog:SetScript("OnClick", function()
        sidebarExpanded = not sidebarExpanded
        mod.db.sidebarCollapsed = not sidebarExpanded
        if not sidebarExpanded then selectedCategory = "all" end
        applySidebarWidth()
        if sidebarExpanded and rebuildSidebar then rebuildSidebar() end
        if mod:IsOpen() then layout() end
    end)

    local scroll = CreateFrame("ScrollFrame", nil, sb)
    f.sidebarScroll = scroll
    scroll:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, -30)
    scroll:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", -1, 2)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxs = math.max(0, (self.child and self.child:GetHeight() or 0) - self:GetHeight())
        self:SetVerticalScroll(math.min(maxs, math.max(0, cur - delta * (SIDEBAR_BTN_H + SIDEBAR_BTN_GAP))))
    end)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(SIDEBAR_W_EXPANDED - 2, 10)
    scroll:SetScrollChild(child)
    scroll.child = child
    f.sidebarChild = child
    scroll:SetShown(sidebarExpanded)
    f.sbRows = {}
end

function rebuildSidebar()
    if not (bagFrame and bagFrame.sidebarChild and sidebarExpanded) then return end
    local child, pool = bagFrame.sidebarChild, bagFrame.sbRows
    local n, y = 0, 0

    local function sectionLabel(text)
        n = n + 1
        local row = makeSidebarRow(child, pool, n)
        row.icon:Hide(); row.sel:Hide(); row.bg:SetAlpha(0); row._selected = false
        row._onClick = nil; row._catKey = nil; row._groupId = nil
        row:EnableMouse(false)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.label:SetText(text); row.label:SetTextColor(0.5, 0.5, 0.55)
        row:SetHeight(SIDEBAR_HDR_H)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
        row:Show()
        y = y + SIDEBAR_HDR_H + SIDEBAR_BTN_GAP
    end

    local function itemRow(icon, text, count, selected, onClick, catKey, indent)
        n = n + 1
        local row = makeSidebarRow(child, pool, n)
        row:EnableMouse(true); row:SetHeight(SIDEBAR_BTN_H)
        row.icon:Show(); row.icon:SetTexture(icon)
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", row, "LEFT", 6 + (indent or 0), 0)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        if count ~= nil then
            row.label:SetText(string.format("%s  |cff808080(%d)|r", text, count))
        else
            row.label:SetText(text)
        end
        setSidebarRowSelected(row, selected)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
        row._onClick = onClick
        row._catKey  = catKey
        row._groupId = nil
        row:Show()
        y = y + SIDEBAR_BTN_H + SIDEBAR_BTN_GAP
    end

    -- a group row -- accent label with v/> glyph + summed count. Click
    local function groupRow(g, total)
        n = n + 1
        local row = makeSidebarRow(child, pool, n)
        row:EnableMouse(true); row:SetHeight(SIDEBAR_BTN_H)
        row.icon:Hide()
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.label:SetText(string.format("%s  %s  |cff808080(%d)|r",
            g.collapsed and ">" or "v", g.name or g.id, total))
        setSidebarRowSelected(row, false)
        row.label:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
        row._catKey  = nil
        row._groupId = g.id
        row._onClick = function()
            if GetCursorInfo and GetCursorInfo() == "item" then return end
            if toggleGroupCollapsed then toggleGroupCollapsed(g.id) end
        end
        row:Show()
        y = y + SIDEBAR_BTN_H + SIDEBAR_BTN_GAP
    end

    sectionLabel(L["View"])
    for _, mode in ipairs({ "all", "onebag", "multibag" }) do
        itemRow(viewModeIcon(mode), viewModeName(mode), nil, viewMode == mode, function()
            if viewMode == mode then return end
            viewMode = mode; mod.db.viewMode = mode; selectedCategory = "all"
            rebuildSidebar()
            if mod:IsOpen() then layout() end
        end)
    end

    if viewMode == "all" then
        y = y + 4
        sectionLabel(L["Categories"])
        local buckets = collectByCategory()
        itemRow(categoryIcon("misc"), L["All Items"], nil, selectedCategory == "all", function()
            if selectedCategory == "all" then return end
            selectedCategory = "all"; rebuildSidebar()
            if mod:IsOpen() then layout() end
        end, "__unassign")
        local function catRow(key, indent)
            local items = buckets[key]
            local count = items and #items or 0
            if count > 0 or customCatByKey[key] then
                itemRow(categoryIcon(key), catName(key), count, selectedCategory == key, function()
                    if selectedCategory == key then return end
                    selectedCategory = key; rebuildSidebar()
                    if mod:IsOpen() then layout() end
                end, key, indent)
            end
        end

        for _, entry in ipairs(groupedDisplay()) do
            if entry.kind == "cat" then
                catRow(entry.key, 0)
            else
                local g = entry.group
                local total = 0
                for _, key in ipairs(entry.cats) do
                    total = total + (buckets[key] and #buckets[key] or 0)
                end
                groupRow(g, total)
                if not g.collapsed then
                    for _, key in ipairs(entry.cats) do catRow(key, SIDEBAR_INDENT) end
                elseif groupOfCat[selectedCategory] == g then
                    catRow(selectedCategory, SIDEBAR_INDENT)
                end
            end
        end
        itemRow("Interface\\Buttons\\UI-PlusButton-Up", L["New category..."], nil, false,
            function() if promptNewCategory then promptNewCategory() end end, nil)
        itemRow("Interface\\Buttons\\UI-PlusButton-Up", L["New group..."], nil, false,
            function() if promptNewGroup then promptNewGroup() end end, nil)
    end

    for i = n + 1, #pool do pool[i]:Hide() end
    child:SetHeight(math.max(y, 10))
    -- clamp: collapsing a group can shrink the child below the current scroll offset
    local s = bagFrame.sidebarScroll
    if s then
        local maxs = math.max(0, child:GetHeight() - s:GetHeight())
        if (s:GetVerticalScroll() or 0) > maxs then s:SetVerticalScroll(maxs) end
    end
end

local function buildFrame()
    if bagFrame or InCombatLockdown() then return bagFrame end
    local f = CreateFrame("Frame", "VuloClassicUIBagFrame", UIParent)
    bagFrame = f
    f:SetFrameStrata("HIGH")
    f:SetSize(400, 300)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:Hide()
    -- OnHide fires only on a real shown->hidden transition, so a repeated CloseAllBags is safe
    f:HookScript("OnHide", function() markRecentSeen() end)
    if UI and UI.StyleBackdrop then UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border }) end
    if UI and UI.CreateShadow then UI:CreateShadow(f) end
    if _G.tinsert and _G.UISpecialFrames then tinsert(UISpecialFrames, "VuloClassicUIBagFrame") end

    local strip = f:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    if UI and UI.SetGradient then
        local a = ns.COLORS.accent
        UI.SetGradient(strip, "HORIZONTAL", a.r, a.g, a.b, 0.1, a.r, a.g, a.b, 0.9)
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if UI and UI.Font then UI.Font(f.title, 14) end
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -9)
    f.title:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    f.title:SetText(L["Inventory"])

    local close = UI:CreateCloseX(f, function() mod:Close() end)

    local sb = UI:CreateSearchBox(f, {
        width = 150,
        onText = function(self)
            searchText = (self:GetText() or ""):lower()
            refresh()
            if ns.BankMirrorSearch then ns.BankMirrorSearch(self:GetText() or "") end
            if ns.GuildBankMirrorSearch then ns.GuildBankMirrorSearch(self:GetText() or "") end
        end,
    })
    f.search = sb
    sb:SetPoint("RIGHT", close, "LEFT", -8, 0)
    sb:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Search"])
        GameTooltip:AddLine(L["Keywords: q:epic, typ:weapon, ilvl>30 (combinable). Also filters the open bank and guild bank."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    sb:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if not mod.db.showSearch then sb:Hide() end

    local sortBtn = CreateFrame("Button", nil, f)
    f.sortBtn = sortBtn
    sortBtn:SetSize(18, 18)
    sortBtn:SetPoint("RIGHT", sb, "LEFT", -8, 0)
    local si = sortBtn:CreateTexture(nil, "ARTWORK")
    si:SetAllPoints(); si:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\broom.tga")
    si:SetVertexColor(0.7, 0.7, 0.75)
    sortBtn:SetScript("OnEnter", function()
        si:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        if GameTooltip then
            GameTooltip:SetOwner(sortBtn, "ANCHOR_TOP")
            GameTooltip:SetText(L["Sort bags"])
            GameTooltip:AddLine(L["Right-click to toggle sort order."], 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    sortBtn:SetScript("OnLeave", function() si:SetVertexColor(0.7, 0.7, 0.75); if GameTooltip then GameTooltip:Hide() end end)
    sortBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sortBtn:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            sortReverse = not sortReverse
            mod.db.sortReverse = sortReverse
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(sortReverse and L["Sort order: reversed"] or L["Sort order: normal"], 0.6, 0.8, 1)
            end
        else
            doSort()
        end
    end)
    if not mod.db.showSortButton then sortBtn:Hide() end

    local bagsBtn = CreateFrame("Button", nil, f)
    f.bagsBtn = bagsBtn
    bagsBtn:SetSize(18, 18)
    bagsBtn:SetPoint("RIGHT", sortBtn, "LEFT", -8, 0)
    local bi = bagsBtn:CreateTexture(nil, "ARTWORK")
    bi:SetAllPoints(); bi:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\bags.tga")
    bi:SetVertexColor(0.7, 0.7, 0.75)
    bagsBtn:SetScript("OnEnter", function()
        bi:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        if GameTooltip then
            GameTooltip:SetOwner(bagsBtn, "ANCHOR_TOP")
            GameTooltip:SetText(L["Show or hide bags"])
            GameTooltip:Show()
        end
    end)
    bagsBtn:SetScript("OnLeave", function() bi:SetVertexColor(0.7, 0.7, 0.75); if GameTooltip then GameTooltip:Hide() end end)

    local bankBtn = CreateFrame("Button", nil, f)
    f.bankBtn = bankBtn
    bankBtn:SetSize(18, 18)
    bankBtn:SetPoint("RIGHT", bagsBtn, "LEFT", -8, 0)
    local ki = bankBtn:CreateTexture(nil, "ARTWORK")
    ki:SetAllPoints(); ki:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\landmark.tga")
    ki:SetVertexColor(0.7, 0.7, 0.75)
    bankBtn:SetScript("OnEnter", function()
        ki:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        if GameTooltip then
            GameTooltip:SetOwner(bankBtn, "ANCHOR_TOP")
            GameTooltip:SetText(L["Bank contents"])
            GameTooltip:AddLine(L["Shows what your bank holds - from the last bank visit, viewable anywhere."], 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end
    end)
    bankBtn:SetScript("OnLeave", function() ki:SetVertexColor(0.7, 0.7, 0.75); if GameTooltip then GameTooltip:Hide() end end)
    bankBtn:SetScript("OnClick", function()
        if ns.ToggleBankMirror then ns.ToggleBankMirror() end
    end)

    f.title:SetPoint("RIGHT", bankBtn, "LEFT", -8, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)

    local ICON_N = #BAGS + 1
    local bar = CreateFrame("Frame", nil, f)
    f.bagBar = bar
    bar:SetSize(ICON_N * (26 + GAP) - GAP + 12, 34)
    bar:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
    if UI and UI.StyleBackdrop then UI:StyleBackdrop(bar, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border }) end
    bar:Hide()
    bar._icons = {}
    local function barIconFor(bag)
        if bag == 0 then return "Interface\\Buttons\\Button-Backpack-Up" end
        if bag == KEYRING then return "Interface\\Icons\\INV_Misc_Key_03" end
        if _G.C_Container and _G.C_Container.ContainerIDToInventoryID and GetInventoryItemTexture then
            local invID = C_Container.ContainerIDToInventoryID(bag)
            local tex = invID and GetInventoryItemTexture("player", invID)
            if tex then return tex end
        end
        return "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
    end
    local function barBagShown(bag)
        if bag == KEYRING then return mod.db.showKeyring and true or false end
        return not (mod.db.hiddenBags and mod.db.hiddenBags[bag])
    end
    f.updateBagBar = function()
        for _, ic in ipairs(bar._icons) do
            local on = barBagShown(ic._bag)
            ic._tex:SetTexture(barIconFor(ic._bag))
            ic._tex:SetDesaturated(not on)
            ic._tex:SetVertexColor(1, 1, 1, on and 1 or 0.35)
        end
    end
    local barBags = {}
    for _, b in ipairs(BAGS) do barBags[#barBags + 1] = b end
    barBags[#barBags + 1] = KEYRING
    for i, bag in ipairs(barBags) do
        local b = bag
        local ic = CreateFrame("Button", nil, bar)
        ic:SetSize(26, 26)
        ic:SetPoint("LEFT", bar, "LEFT", 6 + (i - 1) * (26 + GAP), 0)
        local bg2 = ic:CreateTexture(nil, "BACKGROUND")
        bg2:SetAllPoints(ic); bg2:SetColorTexture(0.10, 0.10, 0.13, 0.55)
        ic._tex = ic:CreateTexture(nil, "ARTWORK")
        ic._tex:SetPoint("TOPLEFT", 1, -1); ic._tex:SetPoint("BOTTOMRIGHT", -1, 1)
        ic._tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ic._bag = b
        ic:SetScript("OnClick", function()
            if b == KEYRING then
                mod.db.showKeyring = not mod.db.showKeyring
            else
                mod.db.hiddenBags = mod.db.hiddenBags or {}
                mod.db.hiddenBags[b] = not mod.db.hiddenBags[b] or nil
            end
            f.updateBagBar()
            refresh()
        end)
        ic:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(bagDisplayName(b))
                GameTooltip:AddLine(L["Click to show or hide this bag."], 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end
        end)
        ic:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        bar._icons[#bar._icons + 1] = ic
    end
    bagsBtn:SetScript("OnClick", function()
        local show = not bar:IsShown()
        bar:SetShown(show)
        mod.db.bagBarShown = show
        if show then f.updateBagBar() end
    end)
    if mod.db.bagBarShown then bar:Show(); f.updateBagBar() end

    buildSidebar(f)
    -- the scroll CHILD keeps the name f.content, so every layout anchor stays unchanged
    local vp = CreateFrame("ScrollFrame", nil, f)
    f.contentVP = vp
    vp:SetPoint("TOPLEFT", f.sidebar, "TOPRIGHT", GAP, 0)
    vp:EnableMouseWheel(true)

    f.content = CreateFrame("Frame", nil, vp)
    vp:SetScrollChild(f.content)
    f.content:SetPoint("TOPLEFT", vp, "TOPLEFT", 0, 0)

    -- parented to the WINDOW (not the viewport) so it is never clipped
    local sbar = CreateFrame("Slider", nil, f)
    f.contentBar = sbar
    sbar:SetFrameLevel((vp:GetFrameLevel() or 0) + 10)
    sbar:SetOrientation("VERTICAL")
    sbar:SetWidth(6)
    sbar:SetPoint("TOPLEFT", vp, "TOPRIGHT", 2, 0)
    sbar:SetPoint("BOTTOMLEFT", vp, "BOTTOMRIGHT", 2, 0)
    sbar:SetMinMaxValues(0, 0)
    sbar:SetValue(0)
    local sthumb = sbar:CreateTexture(nil, "ARTWORK")
    sthumb:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.7)
    sthumb:SetWidth(6)
    sbar:SetThumbTexture(sthumb)
    sbar:SetScript("OnValueChanged", function(self, value)
        vp:SetVerticalScroll(value)
    end)
    sbar:Hide()

    vp:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        local maxs  = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
        local off   = math.min(maxs, math.max(0, (self:GetVerticalScroll() or 0) - delta * WHEEL_STEP))
        self:SetVerticalScroll(off)
        sbar:SetValue(off)
    end)

    -- quick-drop: PickupContainerItem with an item on the cursor is unprotected -> taint-free
    local drop = CreateFrame("Button", nil, f.content)
    f.dropSlot = drop
    drop:SetSize(BTN, BTN)
    drop:Hide()
    local dbg = drop:CreateTexture(nil, "BACKGROUND")
    dbg:SetAllPoints(drop); dbg:SetColorTexture(0.10, 0.10, 0.13, 0.75)
    local dborder = CreateFrame("Frame", nil, drop, BackdropTemplateMixin and "BackdropTemplate")
    dborder:SetAllPoints(drop)
    if dborder.SetBackdrop then
        dborder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        dborder:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    end
    local dplus = drop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if UI and UI.Font then UI.Font(dplus, 14) end
    dplus:SetPoint("CENTER", drop, "CENTER", 0, 0)
    dplus:SetText("+"); dplus:SetTextColor(0.5, 0.5, 0.55)
    local function dropCursorItem()
        if not (CursorHasItem and CursorHasItem()) then return false end
        local bag, slot = firstFreeSlot()
        if not bag then
            if UIErrorsFrame then UIErrorsFrame:AddMessage(L["No free bag slots."], 1, 0.2, 0.2) end
            return true
        end
        PickupContainerItem(bag, slot)
        return true
    end
    drop:SetScript("OnReceiveDrag", dropCursorItem)
    drop:SetScript("OnClick", dropCursorItem)
    drop:SetScript("OnEnter", function(self)
        if dborder.SetBackdropBorderColor then dborder:SetBackdropBorderColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1) end
        dplus:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Drop an item here to put it into the first free slot."])
            GameTooltip:Show()
        end
    end)
    drop:SetScript("OnLeave", function()
        if dborder.SetBackdropBorderColor then dborder:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1) end
        dplus:SetTextColor(0.5, 0.5, 0.55)
        if GameTooltip then GameTooltip:Hide() end
    end)

    f.free = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.free:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 8)
    f.money = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if UI and UI.Font then UI.Font(f.money, 13) end
    f.money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 7)
    local moneyBtn = CreateFrame("Button", nil, f)
    moneyBtn:SetPoint("TOPLEFT", f.money, "TOPLEFT", -4, 2)
    moneyBtn:SetPoint("BOTTOMRIGHT", f.money, "BOTTOMRIGHT", 4, -2)
    moneyBtn:SetScript("OnEnter", function(self)
        if ns.ShowGoldTooltip then ns.ShowGoldTooltip(self) end
    end)
    moneyBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- movable + scalable via our mover; CENTER offset in db.x/db.y
    if ns.CreateMover then
        mod.mover = ns:CreateMover(f, {
            db = mod.db, scalable = true, anchorable = true,
            label = "|cffffffffBAGS|r",
            width = 160, height = 40,
        })
        if ns.ApplyMover then ns:ApplyMover(mod.mover) end
    end

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = ns:GetCenterOffsets(self)
        if x and y then
            mod.db.x, mod.db.y = x, y
            if ns.ApplyMover and mod.mover then ns:ApplyMover(mod.mover) end
        end
    end)
    return f
end

-- pre-allocate buttons out of combat so opening in combat is safe
local function preallocate()
    if InCombatLockdown() then return end
    if not bagFrame then buildFrame() end
    if not bagFrame then return end
    -- create every index frame now, so a mid-combat layout never hits the blocked path
    -- that first touches a bag mid-combat (e.g. expanding a collapsed group) can
    -- never hit the blocked path for a missing index frame. Includes the keyring
    -- so toggling it on mid-combat also has its frame ready.
    for _, bag in ipairs(BAGS) do ensureIndexFrame(bag) end
    ensureIndexFrame(KEYRING)
    local need = totalSlots() + 8
    for i = #buttons + 1, need do
        if not acquireButton(i) then break end
    end
end

function mod:IsOpen() return bagFrame and bagFrame:IsShown() end

function mod:Open()
    if not mod.active then return end
    if not bagFrame then
        if InCombatLockdown() then return end
        buildFrame()
    end
    if not bagFrame then return end
    bagFrame:Show()
    if applySidebarWidth then applySidebarWidth() end
    if rebuildSidebar then rebuildSidebar() end
    if bagFrame.bagBar and bagFrame.bagBar:IsShown() and bagFrame.updateBagBar then
        bagFrame.updateBagBar()
    end
    layout()
end

function mod:Close()
    if bagFrame then
        if bagFrame.search then bagFrame.search:SetText("") end
        bagFrame:Hide()
    end
end

function mod:Toggle()
    if mod:IsOpen() then mod:Close() else mod:Open() end
end

local function applySearchVisibility()
    if bagFrame and bagFrame.search then
        bagFrame.search:SetShown(mod.db.showSearch and true or false)
        if not mod.db.showSearch then bagFrame.search:SetText("") end
    end
end
local function applySortVisibility()
    if bagFrame and bagFrame.sortBtn then
        bagFrame.sortBtn:SetShown(mod.db.showSortButton and true or false)
    end
end

-- hooksecurefunc only. Toggle* calls Open/CloseAllBags internally, so record the desired state and apply it next frame.
local _hooked = false
local wantOpen, wantScheduled = false, false
local function applyWant() wantScheduled = false; if wantOpen then mod:Open() else mod:Close() end end
local function want(state)
    wantOpen = state
    if wantScheduled then return end
    wantScheduled = true
    ns.NextFrame(applyWant)
end

-- Suppress default bags by REPARENTING to a hidden frame (never Hide() a protected frame); only legal out of combat, else deferred to PLAYER_REGEN_ENABLED.
local hiddenBagHost = CreateFrame("Frame")
hiddenBagHost:Hide()
local _origBagParent  = {}
local _bagsSuppressed = false

local function hideBlizzardBags()
    if _bagsSuppressed or InCombatLockdown() then return end
    _bagsSuppressed = true
    for i = 1, 6 do
        local cf = _G["ContainerFrame" .. i]
        if cf then
            _origBagParent[i] = _origBagParent[i] or cf:GetParent()
            cf:SetParent(hiddenBagHost)
        end
    end
end

local function restoreBlizzardBags()
    if not _bagsSuppressed or InCombatLockdown() then return end
    _bagsSuppressed = false
    for i = 1, 6 do
        local cf = _G["ContainerFrame" .. i]
        if cf then cf:SetParent(_origBagParent[i] or UIParent) end
    end
end

local function installHooks()
    if _hooked then return end
    _hooked = true

    local function hookOpen(fn)  if type(_G[fn]) == "function" then hooksecurefunc(fn, function() if mod.active then want(true)  end end) end end
    local function hookClose(fn) if type(_G[fn]) == "function" then hooksecurefunc(fn, function() if mod.active then want(false) end end) end end
    local function hookTog(fn)   if type(_G[fn]) == "function" then hooksecurefunc(fn, function() if mod.active then want(not mod:IsOpen()) end end) end end

    hookOpen("OpenAllBags");   hookClose("CloseAllBags");   hookTog("ToggleAllBags")
    hookOpen("OpenBackpack");  hookClose("CloseBackpack");  hookTog("ToggleBackpack")
    hookOpen("OpenBag");       hookClose("CloseBag");       hookTog("ToggleBag")
end

-- Named so the one-shot in OnDisable can be taken back out by identity, and
-- declared here so both OnEnable and OnDisable can see it.
local function restoreBagsWhenSafe()
    restoreBlizzardBags()
end

local BAG_EVENTS = {
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
    "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY", "PLAYER_REGEN_ENABLED",
}
-- Recent = per-itemID count diff vs a runtime baseline; session-scoped, capped to recentCap, BAG_UPDATE_DELAYED only.
function updateRecentItems()
    local baseline = recentBaseline
    local totals = snapshotTotals()

    for i = #recentOrder, 1, -1 do
        local id = recentOrder[i]
        if not totals[id] then
            table.remove(recentOrder, i)
            recentItems[id] = nil
        end
    end

    if not recentPrimed then
        recentBaseline = totals
        recentPrimed = true
        return
    end

    for itemID in pairs(totals) do
        if (baseline[itemID] or 0) == 0 then
            if recentItems[itemID] then
                for i = #recentOrder, 1, -1 do
                    if recentOrder[i] == itemID then table.remove(recentOrder, i); break end
                end
            else
                recentItems[itemID] = true
            end
            table.insert(recentOrder, 1, itemID)
        end
    end

    local cap = mod.db and mod.db.recentCap or 20
    if cap and cap > 0 then
        while #recentOrder > cap do
            local drop = table.remove(recentOrder)
            recentItems[drop] = nil
        end
    end
    -- recentBaseline is intentionally NOT advanced here; only markRecentSeen/login move it
end

function clearRecentItems()
    if wipe then wipe(recentItems); wipe(recentOrder)
    else recentItems, recentOrder = {}, {} end
    if categoriesChanged then categoriesChanged() end
end

local function onEvent(event, arg1)
    if event == "PLAYER_MONEY" then
        updateMoney()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- suppression/restore may have been combat-deferred in either direction
        if mod.active then hideBlizzardBags()
        elseif _bagsSuppressed then restoreBlizzardBags() end
        if pendingRelayout then
            pendingRelayout = false
            preallocate()
            if mod:IsOpen() then layout() end
        end
    else
        if event == "BAG_UPDATE_DELAYED" then
            if wipe then wipe(categoryCache) end
            if mod.db.showRecent ~= false then updateRecentItems() end
        end
        refresh()
    end
end

function mod:OnEnable()
    mod.active = true
    if not mod.db.sortModeUpgraded then
        mod.db.sortModeUpgraded = true
        if mod.db.sortMode == "blizzard" then mod.db.sortMode = "type" end
    end
    sortReverse = mod.db.sortReverse and true or false
    sortMode = mod.db.sortMode or "type"
    catSortMode = mod.db.catSortMode or "type"
    useCategories = (mod.db.useCategories ~= false)
    hideEmpty = (mod.db.hideEmpty ~= false)
    viewMode = mod.db.viewMode or "all"
    if viewMode ~= "all" and viewMode ~= "onebag" and viewMode ~= "multibag" then viewMode = "all" end
    sidebarExpanded = (mod.db.sidebarCollapsed == false)
    sidebarWidth = sidebarExpanded and SIDEBAR_W_EXPANDED or SIDEBAR_W_COLLAPSED
    selectedCategory = "all"
    -- live references into the profile: writes through these persist automatically
    mod.db.customCats      = mod.db.customCats      or {}
    mod.db.itemAssignments = mod.db.itemAssignments or {}
    mod.db.disabledCats    = mod.db.disabledCats    or {}
    customCats      = mod.db.customCats
    itemAssignments = mod.db.itemAssignments
    disabledCats    = mod.db.disabledCats
    mod.db.pinnedItems = mod.db.pinnedItems or {}
    pinnedItems = mod.db.pinnedItems
    mod.db.groups = mod.db.groups or {}
    groups = mod.db.groups
    if mod.db.showRecent == nil then mod.db.showRecent = true end
    if mod.db.recentCap  == nil then mod.db.recentCap  = 20 end
    if wipe then wipe(recentItems); wipe(recentOrder); wipe(recentBaseline)
    else recentItems, recentOrder, recentBaseline = {}, {}, {} end
    recentPrimed = false
    lastLayoutSig = nil
    rebuildCustomLookup()
    rebuildGroupLookup()   -- AFTER rebuildCustomLookup (sanitizer needs customCatByKey)
    installHooks()
    -- Registered through the module, so all six come back out on disable. The
    -- latch that used to guard this is gone: the registry refuses a duplicate.
    for _, ev in ipairs(BAG_EVENTS) do
        self:RegisterEvent(ev, onEvent)
    end
    -- Re-enabled before a deferred restore could run: drop it, the module owns
    -- the bags again and the one-shot would hand them back mid-session.
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED", restoreBagsWhenSafe)
    preallocate()
    hideBlizzardBags()
    if ns.BankOnEnable then ns.BankOnEnable() end
    if ns.GuildBankOnEnable then ns.GuildBankOnEnable() end
end

function mod:OnDisable()
    mod.active = false
    if ns.SortEngine then ns.SortEngine.Cancel() end
    if bagFrame then bagFrame:Hide() end
    restoreBlizzardBags()
    -- restoreBlizzardBags refuses to reparent in combat, and the module's own
    -- events are about to be unregistered -- without this the player would be
    -- left with NO bags at all until /reload. Registered outside the module's
    -- ownership on purpose: it has to outlive the module being switched off.
    if _bagsSuppressed then
        ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", restoreBagsWhenSafe)
    end
    if ns.BankOnDisable then ns.BankOnDisable() end
    if ns.GuildBankOnDisable then ns.GuildBankOnDisable() end
end

ns.OnLocaleReady(function()
StaticPopupDialogs["VCUI_BAGS_NEW_CATEGORY"] = {
    text = L["New category name:"],
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = 32,
    OnShow = function(self)
        local eb = ns.PopupEditBox(self)
        if eb then eb:SetText(""); eb:SetFocus() end
    end,
    OnAccept = function(self)
        local eb = ns.PopupEditBox(self)
        createCustomCategory(eb and eb:GetText() or "")
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        local eb = p.editBox or self
        createCustomCategory(eb:GetText() or "")
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["VCUI_BAGS_RENAME_CATEGORY"] = {
    text = L["Rename category:"],
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = 32,
    OnShow = function(self, data)
        local eb = ns.PopupEditBox(self)
        if eb then eb:SetText((data and data.current) or ""); eb:HighlightText(); eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = ns.PopupEditBox(self)
        if data then renameCategory(data.key, eb and eb:GetText() or "") end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        local eb = p.editBox or self
        if p.data then renameCategory(p.data.key, eb:GetText() or "") end
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["VCUI_BAGS_NEW_GROUP"] = {
    text = L["New group name:"],
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = 32,
    OnShow = function(self)
        local eb = ns.PopupEditBox(self)
        if eb then eb:SetText(""); eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = ns.PopupEditBox(self)
        local id = createGroup(eb and eb:GetText() or "")
        if id and data and data.catKey then assignCatToGroup(data.catKey, id) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        local eb = p.editBox or self
        local id = createGroup(eb:GetText() or "")
        if id and p.data and p.data.catKey then assignCatToGroup(p.data.catKey, id) end
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["VCUI_BAGS_RENAME_GROUP"] = {
    text = L["Rename group:"],
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = 32,
    OnShow = function(self, data)
        local eb = ns.PopupEditBox(self)
        if eb then eb:SetText((data and data.current) or ""); eb:HighlightText(); eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = ns.PopupEditBox(self)
        if data then renameGroup(data.id, eb and eb:GetText() or "") end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        local eb = p.editBox or self
        if p.data then renameGroup(p.data.id, eb:GetText() or "") end
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
end)

function promptNewCategory()
    StaticPopup_Show("VCUI_BAGS_NEW_CATEGORY")
end

function promptNewGroup(catKey)
    StaticPopup_Show("VCUI_BAGS_NEW_GROUP", nil, nil, catKey and { catKey = catKey } or nil)
end

function showCategoryMenu(anchorRow, key)
    if not key or key == "__unassign" then return end
    if key == "pinned" or key == "recent" then return end
    local isCustom = customCatByKey[key] ~= nil
    local grouped  = groupOfCat[key] ~= nil
    local entries = {
        { title = true, text = catName(key) },
        { text = L["Rename"], func = function()
            StaticPopup_Show("VCUI_BAGS_RENAME_CATEGORY", nil, nil, { key = key, current = catName(key) })
        end },
        { text = L["Move up"],   func = function()
            if groupOfCat[key] then moveCatWithinGroup(key, -1) else moveCategory(key, -1) end
        end },
        { text = L["Move down"], func = function()
            if groupOfCat[key] then moveCatWithinGroup(key,  1) else moveCategory(key,  1) end
        end },
        { separator = true },
        { text = L["Add to group..."], func = function() showAssignToGroupMenu(anchorRow, key) end },
    }
    if grouped then
        entries[#entries + 1] = { text = L["Remove from group"],
            func = function() assignCatToGroup(key, nil) end }
    end
    entries[#entries + 1] = { separator = true }
    entries[#entries + 1] = { text = isCustom and L["Delete category"] or L["Disable category"],
        func = function() deleteOrDisableCategory(key) end }
    if ns.ShowPopupMenu then ns:ShowPopupMenu(entries, anchorRow) end
end

function showAssignToGroupMenu(anchor, catKey)
    if not catKey or catKey == "pinned" or catKey == "recent" or catKey == "__unassign" then return end
    local entries = { { title = true, text = catName(catKey) } }
    for _, g in ipairs(groups) do
        local gid = g.id
        entries[#entries + 1] = {
            text = g.name or gid,
            checked = function() return groupOfCat[catKey] == groupById[gid] end,
            func = function() assignCatToGroup(catKey, gid) end,
        }
    end
    entries[#entries + 1] = { text = L["New group..."], func = function() promptNewGroup(catKey) end }
    if groupOfCat[catKey] then
        entries[#entries + 1] = { separator = true }
        entries[#entries + 1] = { text = L["Remove from group"],
            func = function() assignCatToGroup(catKey, nil) end }
    end
    if ns.ShowPopupMenu then ns:ShowPopupMenu(entries, anchor) end
end

function showGroupMenu(anchor, id)
    local g = groupById[id]
    if not g then return end
    local entries = {
        { title = true, text = g.name or id },
        { text = g.collapsed and L["Expand"] or L["Collapse"],
          func = function() toggleGroupCollapsed(id) end },
        { text = L["Rename"], func = function()
            StaticPopup_Show("VCUI_BAGS_RENAME_GROUP", nil, nil, { id = id, current = g.name or "" })
        end },
        { text = L["Move up"],   func = function() moveGroup(id, -1) end },
        { text = L["Move down"], func = function() moveGroup(id,  1) end },
        { separator = true },
        { text = L["Delete group"], func = function() deleteGroup(id) end },
    }
    if ns.ShowPopupMenu then ns:ShowPopupMenu(entries, anchor) end
end

function mod:GetOptions()
    local items = {}
    table.insert(items, { type = "header", text = L["Bags"] })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaOne window for all your bags. Press your bag key (default B) to open it. Type in the search box to find items; click the sort button to tidy up. At a banker, your bank opens in a matching window.|r"] })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Layout"] })
    table.insert(items, {
        type = "slider", label = L["Window scale"], min = 50, max = 150, step = 5,
        get = function() return (mod.db.scale or 1) * 100 end,
        set = function(_, v)
            mod.db.scale = v / 100
            if mod.mover and ns.MoverSetScale then ns:MoverSetScale(mod.mover, mod.db.scale)
            elseif bagFrame then bagFrame:SetScale(mod.db.scale) end
        end,
    })
    table.insert(items, {
        type = "slider", label = L["Grid columns"], min = 6, max = 20, step = 1,
        get = function() return mod.db.columns end,
        set = function(_, v) mod.db.columns = v; if mod:IsOpen() then layout() end end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Categories"] })
    table.insert(items, {
        type = "toggle", label = L["Group items into categories"],
        tooltip = L["Show items in labelled sections (Quest, Consumables, Armor...). Off = one flat grid."],
        get = function() return mod.db.useCategories ~= false end,
        set = function(_, v)
            mod.db.useCategories = v; useCategories = v and true or false
            if mod:IsOpen() then layout() end
        end,
    })
    table.insert(items, {
        type = "toggle", label = L["Hide empty categories"],
        tooltip = L["Don't show a section header for a category that has no items."],
        get = function() return mod.db.hideEmpty ~= false end,
        set = function(_, v)
            mod.db.hideEmpty = v; hideEmpty = v and true or false
            if mod:IsOpen() then layout() end
        end,
    })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaTip: drag an item onto a category in the sidebar to keep it there; right-click a category to rename, move or delete it.|r"] })
    table.insert(items, {
        type = "button", label = L["New category..."], width = 200,
        onClick = function() promptNewCategory() end,
    })
    table.insert(items, {
        type = "button", label = L["New group..."], width = 200,
        onClick = function() if promptNewGroup then promptNewGroup() end end,
    })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaTip: right-click a category to add it to a group; click a group header to collapse or expand it; right-click a group header to rename, move or delete it.|r"] })
    table.insert(items, { type = "spacer", height = 4 })
    table.insert(items, {
        type = "toggle", label = L["Show Recent Items"],
        tooltip = L["Show a 'Recent Items' section for new item types you gain; it clears when you close the bag."],
        get = function() return mod.db.showRecent ~= false end,
        set = function(_, v)
            mod.db.showRecent = v and true or false
            if not v then
                if wipe then wipe(recentItems); wipe(recentOrder) else recentItems, recentOrder = {}, {} end
            end
            if categoriesChanged then categoriesChanged() end
        end,
    })
    table.insert(items, {
        type = "slider", label = L["Recent items kept"], min = 0, max = 50, step = 1,
        tooltip = L["Maximum number of distinct recent items to remember (0 = no limit)."],
        get = function() return mod.db.recentCap or 20 end,
        set = function(_, v) mod.db.recentCap = v; if categoriesChanged then categoriesChanged() end end,
    })
    table.insert(items, {
        type = "button", label = L["Clear recent"], width = 200,
        onClick = function() if clearRecentItems then clearRecentItems() end end,
    })
    table.insert(items, {
        type = "button", label = L["Unpin all items"], width = 200,
        onClick = function()
            if wipe and pinnedItems then wipe(pinnedItems) end
            if categoriesChanged then categoriesChanged() end
        end,
    })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaTip: middle-click an item to pin it to the top; middle-click again to unpin.|r"] })
    for _, key in ipairs(CATEGORY_ORDER) do
        if key ~= "pinned" and key ~= "recent" then
            table.insert(items, {
                type = "toggle", label = string.format(L["Show category: %s"], catName(key)),
                get = function() return not disabledCats[key] end,
                set = function(_, v) if v then reenableCategory(key) else deleteOrDisableCategory(key) end end,
            })
        end
    end
    table.insert(items, {
        type = "button", label = L["Reset category order"], width = 200,
        onClick = function() mod.db.catOrder = nil; if categoriesChanged then categoriesChanged() end end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["View"] })
    table.insert(items, {
        type = "dropdown", label = L["View mode"], width = 200,
        tooltip = L["All = categorized sections. OneBag = one flat grid. MultiBag = a section per bag."],
        values = {
            { value = "all",      text = L["All Items"] },
            { value = "onebag",   text = L["OneBag"] },
            { value = "multibag", text = L["MultiBag"] },
        },
        get = function() return mod.db.viewMode or "all" end,
        set = function(_, v)
            mod.db.viewMode = v; viewMode = v; selectedCategory = "all"
            if sidebarExpanded and rebuildSidebar then rebuildSidebar() end
            if mod:IsOpen() then layout() end
        end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show free slots (OneBag)"],
        tooltip = L["OneBag view: show the empty bag slots after the items, so you can drop things onto them directly."],
        get = function() return mod.db.showFreeSlots ~= false end,
        set = function(_, v)
            mod.db.showFreeSlots = v and true or false
            if mod:IsOpen() then layout() end
        end,
    })
    table.insert(items, {
        type = "toggle", label = L["Fixed slot order (OneBag)"],
        tooltip = L["Shows every slot in its natural bag order with the empty slots inline — items stay visually where you drop them, like one big real bag. Needs the free-slots option above."],
        get = function() return mod.db.onebagFixedSlots ~= false end,
        set = function(_, v)
            mod.db.onebagFixedSlots = v and true or false
            if mod:IsOpen() then layout() end
        end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show sidebar"],
        tooltip = L["A collapsible left panel for view modes and category filtering."],
        get = function() return not mod.db.sidebarCollapsed end,
        set = function(_, v)
            mod.db.sidebarCollapsed = not v
            sidebarExpanded = v and true or false
            if not v then selectedCategory = "all" end
            if applySidebarWidth then applySidebarWidth() end
            if v and rebuildSidebar then rebuildSidebar() end
            if mod:IsOpen() then layout() end
        end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Appearance"] })
    table.insert(items, {
        type = "toggle", label = L["Quality borders"],
        tooltip = L["Colour each item's border by its rarity."],
        get = function() return mod.db.qualityBorders end,
        set = function(_, v)
            mod.db.qualityBorders = v
            if mod:IsOpen() then layout() end
            if ns.BankRefresh then ns.BankRefresh() end
            if ns.GuildBankRefresh then ns.GuildBankRefresh() end
        end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show item levels"],
        tooltip = L["Shows the item level on weapons and armor."],
        get = function() return mod.db.showItemLevel ~= false end,
        set = function(_, v)
            mod.db.showItemLevel = v and true or false
            if mod:IsOpen() then layout() end
            if ns.BankRefresh then ns.BankRefresh() end
            if ns.GuildBankRefresh then ns.GuildBankRefresh() end
        end,
    })
    table.insert(items, {
        type = "toggle", label = L["Color item levels by quality"],
        tooltip = L["Tints the item level number in the item's quality color instead of plain white."],
        get = function() return mod.db.itemLevelQualityColor ~= false end,
        set = function(_, v)
            mod.db.itemLevelQualityColor = v and true or false
            if mod:IsOpen() then layout() end
            if ns.BankRefresh then ns.BankRefresh() end
            if ns.GuildBankRefresh then ns.GuildBankRefresh() end
        end,
    })
    table.insert(items, {
        type = "toggle", label = L["Junk marker (C)"],
        tooltip = L["Marks vendor trash with a purple C in the icon corner - grey items a merchant pays gold for."],
        get = function() return mod.db.junkMarker ~= false end,
        set = function(_, v)
            mod.db.junkMarker = v and true or false
            if mod:IsOpen() then layout() end
        end,
    })
    table.insert(items, {
        type = "toggle", label = L["Quest starter marker (!)"],
        tooltip = L["Overlays a yellow exclamation mark on items that start a quest you have not accepted yet."],
        get = function() return mod.db.questMarker ~= false end,
        set = function(_, v)
            mod.db.questMarker = v and true or false
            if mod:IsOpen() then layout() end
            if ns.BankRefresh then ns.BankRefresh() end
        end,
    })
    table.insert(items, {
        type = "toggle", label = L["BoE/BoU markers"],
        tooltip = L["Tags equipment that is still tradeable (binds on equip or use, not yet soulbound) - handy for banking and the auction house."],
        get = function() return mod.db.bindMarker ~= false end,
        set = function(_, v)
            mod.db.bindMarker = v and true or false
            if mod:IsOpen() then layout() end
            if ns.BankRefresh then ns.BankRefresh() end
            if ns.GuildBankRefresh then ns.GuildBankRefresh() end
        end,
    })
    table.insert(items, {
        type = "slider", label = L["Item count text size"], min = 8, max = 16, step = 1,
        get = function() return mod.db.countFontSize end,
        set = function(_, v)
            mod.db.countFontSize = v
            if mod:IsOpen() then layout() end
            if ns.BankRefresh then ns.BankRefresh() end
            if ns.GuildBankRefresh then ns.GuildBankRefresh() end
        end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Search & sorting"] })
    table.insert(items, {
        type = "toggle", label = L["Show search box"],
        tooltip = L["A search field in the window header. Dims items that don't match."],
        get = function() return mod.db.showSearch end,
        set = function(_, v) mod.db.showSearch = v; applySearchVisibility() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show sort button"],
        tooltip = L["A sort button in the window header. Right-click it to reverse the order."],
        get = function() return mod.db.showSortButton end,
        set = function(_, v) mod.db.showSortButton = v; applySortVisibility() end,
    })
    table.insert(items, {
        type = "dropdown", label = L["Sort order"], width = 200,
        tooltip = L["How the sort button arranges items. 'Blizzard' groups by category like the default UI; the others are a flat order."],
        values = {
            { value = "blizzard",   text = L["Blizzard (category)"] },
            { value = "quality",    text = L["Quality"] },
            { value = "type",       text = L["Item type"] },
            { value = "name",       text = L["Name"] },
            { value = "item-level", text = L["Item level"] },
        },
        get = function() return mod.db.sortMode end,
        set = function(_, v) mod.db.sortMode = v; sortMode = v end,
    })
    table.insert(items, {
        type = "dropdown", label = L["Sort categories by"], width = 200,
        tooltip = L["Display-only ordering of the items inside each category section. Never moves anything in your bags."],
        values = {
            { value = "off",        text = L["Off"] },
            { value = "quality",    text = L["Quality"] },
            { value = "type",       text = L["Item type"] },
            { value = "name",       text = L["Name"] },
            { value = "item-level", text = L["Item level"] },
        },
        get = function() return mod.db.catSortMode end,
        set = function(_, v)
            mod.db.catSortMode = v
            catSortMode = v
            if mod:IsOpen() then layout() end
        end,
    })
    table.insert(items, {
        type = "toggle", label = L["Reverse sort order"],
        tooltip = L["Sort in the opposite direction."],
        get = function() return mod.db.sortReverse end,
        set = function(_, v)
            mod.db.sortReverse = v
            sortReverse = v and true or false
            if mod:IsOpen() then layout() end
        end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, {
        type = "button", label = L["Reset bag position"], width = 200,
        onClick = function()
            if mod.mover and ns.MoverSetCenter then ns:MoverSetCenter(mod.mover, 0, 0) end
        end,
    })
    if ns.BankOptions then
        for _, it in ipairs(ns.BankOptions()) do table.insert(items, it) end
    end
    if ns.GuildBankOptions then
        for _, it in ipairs(ns.GuildBankOptions()) do table.insert(items, it) end
    end
    return items
end
