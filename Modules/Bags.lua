-- =========================================================
-- VuloClassicUI / Modules / Bags  (Phase 1 — core unified bag)
-- One custom window that shows every backpack/bag item in a single grid.
-- We do NOT reskin Blizzard's ContainerFrames; we draw our own frame and drive
-- open/close off the normal bag key, suppressing the default bag windows.
--
-- TAINT DISCIPLINE (functional, in-combat-safe item buttons):
--   * each slot is a SECURE button inheriting Blizzard's own
--     "ContainerFrameItemButtonTemplate" (needs a global name on Classic) — all
--     use/equip/pickup/split/tooltip is Blizzard-driven; we NEVER SetScript its
--     OnClick/OnDragStart (only HookScript) and NEVER call the protected
--     UseContainerItem/PickupContainerItem ourselves.
--   * bag id lives on the button's PARENT (SetID), slot id on the button (SetID)
--     — exactly what Blizzard's handler reads.
--   * buttons are created only OUT of combat (pre-allocated on enable); in combat
--     we only refresh visuals + reposition existing buttons, and rebuild fully on
--     PLAYER_REGEN_ENABLED. Creating a brand-new button in combat can taint.
--   * open/close hooks use hooksecurefunc only — no Blizzard global is replaced.
-- =========================================================
local _, ns = ...
local L  = ns.L
local UI = ns.UI

-- Container API — the bare globals are guaranteed on every flavor we ship for by
-- Core/Compat.lua (it recreates them from C_Container on Era). GetContainerItemInfo
-- returns the legacy tuple there too.
local GetContainerNumSlots     = _G.GetContainerNumSlots
local GetContainerItemInfo     = _G.GetContainerItemInfo
local GetContainerItemCooldown = _G.GetContainerItemCooldown
local GetContainerNumFreeSlots = _G.GetContainerNumFreeSlots
local GetContainerItemLink     = _G.GetContainerItemLink   -- Compat guarantees this on Era

-- Native bag sort exists on retail + some Classic builds only; fall back to our
-- own Lua sort when absent (see doSort). Never assume it's there.
local nativeSort   = (_G.C_Container and _G.C_Container.SortBags) or _G.SortBags
local nativeSetDir = (_G.C_Container and _G.C_Container.SetSortBagsRightToLeft) or _G.SetSortBagsRightToLeft

local BAGS = { 0, 1, 2, 3, 4 }          -- backpack + 4 bags (keyring/bank: later phases)

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
        sortMode      = "blizzard",   -- "blizzard" | "quality" | "type" | "name"
        useCategories = true,         -- categorized sections vs one flat grid
        hideEmpty     = true,         -- hide category headers with zero items
        viewMode      = "all",        -- "all" | "onebag" | "multibag"
        sidebarCollapsed = true,      -- sidebar starts collapsed (arrow only)
        -- Phase 3c — user categories + manual item assignment (all profile-scoped)
        customCats      = {},         -- array of { key, name, icon }
        itemAssignments = {},         -- [itemID] = categoryKey
        disabledCats    = {},         -- [builtinKey] = true
        catOrder        = nil,        -- array of keys; nil = auto order
        -- Phase 3c STAGE-2 — pinned/recent pseudo-categories
        pinnedItems     = {},         -- [itemID] = true (profile-scoped, persistent)
        showRecent      = true,       -- master toggle for the Recent pseudo-category
        recentCap       = 20,         -- max distinct itemIDs kept in Recent (0 = unlimited)
        -- Phase 3c STAGE-3 — user-defined collapsible category groups
        groups          = {},         -- ordered array of { id, name, collapsed, cats = { catKey, ... } }
        -- Phase 4 STAGE-2 — per-bag visibility + keyring + quick-drop
        hiddenBags      = {},         -- [bagID] = true -> bag not rendered
        showKeyring     = false,      -- include the keyring (-2) in the grid
        showItemLevel   = true,       -- ilvl text on weapons/armor
        bagBarShown     = false,      -- the bag-icons strip above the window
        -- Phase 4 STAGE-1 — bank window (Modules/Bank.lua reads this sub-table;
        -- SEPARATE keys so the bank mover never collides with the bag window's).
        bank = { enabled = true, x = -280, y = 0, scale = 1.0, columns = 14, hiddenBags = {} },
    },
})

mod.active = false

-- =========================================================
-- Layout constants
-- =========================================================
local BTN, GAP, PAD = 37, 4, 12
local HEADER_H, FOOTER_H = 32, 26
local HEADER_ROW = 18   -- vertical space a category section header occupies
-- STAGE-3: collapsible category groups
local GROUP_HEADER_ROW = 20   -- vertical space a group header row occupies
local GROUP_INDENT     = 10   -- x-indent for category sections inside an expanded group
local SIDEBAR_INDENT   = 14   -- x-indent for member category rows in the sidebar
-- Sidebar (Phase 3b) — plain-frame left panel; never holds secure item buttons.
local SIDEBAR_W_EXPANDED  = 160
local SIDEBAR_W_COLLAPSED = 32
local SIDEBAR_BTN_H       = 24
local SIDEBAR_BTN_GAP     = 2
local SIDEBAR_ICON        = 16
local SIDEBAR_HDR_H       = 22
-- STAGE-2: content scrolls (instead of the window growing without bound) once it
-- exceeds this fraction of the screen height.
local CONTENT_MAX_FRAC = 0.60   -- viewport caps at 60% of UIParent height
local WHEEL_STEP       = BTN + GAP

-- =========================================================
-- Categories (Phase 3a). Keys are internal + stable; display names localized.
-- ORDER drives top-to-bottom section stacking. Everything keys off numeric
-- Enum.ItemClass IDs (locale-independent) + equip slot + quality, so the same
-- rules work on 20505 and 11508; classes absent on a client never match.
-- =========================================================
local CATEGORY_ORDER = {
    "pinned", "recent",   -- STAGE-2 pseudo-categories, always at the top
    "quest", "consumable", "weapon", "armor", "trinket", "container",
    "tradegoods", "recipe", "projectile", "quiver", "key", "junk", "misc",
}

-- Phase 3c state (mirrors of the profile-linked mod.db) + forward declarations.
-- Declared BEFORE catName/categoryIcon/categoryFor and the CRUD/menu functions
-- that reference them, so every reference binds the same upvalue.
local customCats      = {}     -- array of { key, name, icon } (mirror)
local itemAssignments = {}     -- [itemID] = categoryKey (mirror)
local disabledCats    = {}     -- [builtinKey] = true (mirror)
local customCatByKey  = {}     -- [key] = customCats entry (rebuilt on change)
local nextCustomSeq   = 0      -- unique key counter ("cust1", "cust2", ...)
-- declared up here (not in the State block below) because the CRUD functions
-- reference it before that block; a later `local` would bind a stale global.
local selectedCategory = "all" -- "all" | a category key (only meaningful in "all" view)
local DEFAULT_CUSTOM_ICON = "Interface\\Icons\\INV_Misc_Note_02"
-- Phase 3c STAGE-2 pseudo-category state. pinnedItems mirrors mod.db.pinnedItems
-- (profile). recentItems/recentOrder are RUNTIME ONLY (rebuilt on BAG_UPDATE_DELAYED
-- from a per-char baseline diff). All THREE must be declared here -- textually before
-- categoryExists (below) and categoryFor -- so those closures bind the upvalue, not a nil global.
local pinnedItems = {}          -- [itemID] = true (mirror of mod.db.pinnedItems)
local recentItems = {}          -- [itemID] = true (runtime; items acquired this session)
local recentOrder = {}          -- array of itemIDs, newest first (for cap + stable order)
local recentBaseline = {}       -- [itemID] = last-seen total count (runtime; re-seeded each session)
local recentPrimed = false      -- true once the baseline has been seeded this session
-- Phase 3c STAGE-3 group state. `groups` is a LIVE reference to mod.db.groups
-- (set in OnEnable); groupById/groupOfCat are rebuilt lookups. Declared here --
-- textually before makeSidebarRow/layoutCategorized/showCategoryMenu -- so every
-- closure binds these upvalues, never a nil global.
local groups       = {}   -- ordered array of { id, name, collapsed, cats = {catKey,...} } (mirror)
local groupById    = {}   -- [id] = group entry (rebuilt on change)
local groupOfCat   = {}   -- [catKey] = group entry (rebuilt on change; max ONE group per cat)
local nextGroupSeq = 0    -- unique id counter ("grp1", "grp2", ...)
local rebuildCustomLookup, categoryExists, orderedCategoryKeys, categoriesChanged
local createCustomCategory, renameCategory, deleteOrDisableCategory, reenableCategory, moveCategory
local showCategoryMenu, promptNewCategory
local updateRecentItems, clearRecentItems    -- STAGE-2 recent helpers (defined below)
-- STAGE-3 groups: declared ONCE here (with the Phase-3c block), defined below via
-- bare `function name()` assignment. NEVER redeclare with `local` at the definition.
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

-- Category / view-mode icons (base-UI textures present on 20505 + 11508).
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

-- ---- Phase 3c: custom-category registry + CRUD -----------------------------
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

-- Is a category key a valid, visible destination right now?
function categoryExists(key)
    if not key then return false end
    if key == "pinned" then return next(pinnedItems) ~= nil end       -- pseudo-cat: valid only when something is pinned
    if key == "recent" then                                          -- pseudo-cat: gated on toggle + non-empty
        return (mod.db and mod.db.showRecent ~= false) and next(recentItems) ~= nil
    end
    if customCatByKey[key] then return true end     -- live custom category
    if disabledCats[key] then return false end      -- disabled built-in
    for _, k in ipairs(CATEGORY_ORDER) do if k == key then return true end end
    return false
end

-- Effective ordered category-key list: built-ins (minus disabled) + customs,
-- reordered by mod.db.catOrder when present; unknown/gone keys dropped.
function orderedCategoryKeys()
    local out, seen = {}, {}
    local function push(key)
        if key and not seen[key] and categoryExists(key) then out[#out + 1] = key; seen[key] = true end
    end
    -- STAGE-2: pinned/recent pseudo-categories are ALWAYS pinned to the very top,
    -- regardless of any user catOrder (they are never written into catOrder).
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

-- deletes a custom category, OR disables a built-in (built-ins can't be deleted)
function deleteOrDisableCategory(key)
    if key == "pinned" or key == "recent" then return end   -- STAGE-2 pseudo-cats: never disable
    local c = customCatByKey[key]
    if c then
        for i = 1, #customCats do
            if customCats[i] and customCats[i].key == key then table.remove(customCats, i); break end
        end
        -- STAGE-3: a deleted custom category leaves its group; a DISABLED built-in
        -- keeps its membership (skipped while disabled, restored on re-enable).
        -- MUST run before customCatByKey[key] is nilled: assignCatToGroup's
        -- groupableKey() check consults customCatByKey and would no-op after it.
        if groupOfCat[key] and assignCatToGroup then assignCatToGroup(key, nil) end
        customCatByKey[key] = nil
        for itemID, ck in pairs(itemAssignments) do
            if ck == key then itemAssignments[itemID] = nil end   -- purge dead assignments
        end
        if mod.db.catOrder then
            for i = #mod.db.catOrder, 1, -1 do
                if mod.db.catOrder[i] == key then table.remove(mod.db.catOrder, i) end
            end
        end
    else
        disabledCats[key] = true   -- built-in: hide + reroute auto items to misc
    end
    if selectedCategory == key then selectedCategory = "all" end
    if categoriesChanged then categoriesChanged() end
end

function reenableCategory(key)
    disabledCats[key] = nil
    if categoriesChanged then categoriesChanged() end
end

-- move a category one step within the effective order (materialises catOrder)
function moveCategory(key, delta)
    if key == "pinned" or key == "recent" then return end   -- STAGE-2 pseudo-cats: fixed at the top
    local eff = orderedCategoryKeys()
    mod.db.catOrder = mod.db.catOrder or {}
    -- materialise from the effective order but NEVER bake the pseudo-categories into
    -- the persistent order (they are positioned by CATEGORY_ORDER + categoryExists).
    if #mod.db.catOrder == 0 then
        for _, k in ipairs(eff) do
            if k ~= "pinned" and k ~= "recent" then mod.db.catOrder[#mod.db.catOrder + 1] = k end
        end
    end
    local order = mod.db.catOrder
    local idx
    for i, k in ipairs(order) do if k == key then idx = i; break end end
    if not idx then return end
    -- STAGE-3: grouped keys don't render in the ungrouped block, so swapping with one
    -- would be an invisible no-op click -- skip past them to the next visible neighbor.
    local swap = idx + delta
    while order[swap] and groupOfCat[order[swap]] do swap = swap + delta end
    if swap < 1 or swap > #order then return end
    order[idx], order[swap] = order[swap], order[idx]
    if categoriesChanged then categoriesChanged() end
end

-- ---- Phase 3c STAGE-3: collapsible category groups --------------------------
-- Groups are a pure PRESENTATION layer: categoryFor()/collectByCategory() still
-- bucket by category key only; groups just regroup the non-pseudo keys for the
-- grid + sidebar. All state lives in mod.db.groups (profile-scoped).

-- Can this key ever live in a group? (pseudo-cats + unknown keys: never)
local function groupableKey(key)
    if not key or key == "pinned" or key == "recent" or key == "__unassign" then return false end
    if customCatByKey[key] then return true end
    for _, k in ipairs(CATEGORY_ORDER) do if k == key then return true end end
    return false
end

-- Rebuild groupById/groupOfCat + nextGroupSeq from the groups array; sanitizes
-- persisted data (drops malformed entries, pseudo-cats, duplicates across groups,
-- dead custom keys). Call AFTER rebuildCustomLookup() so customCatByKey is fresh.
function rebuildGroupLookup()
    wipe(groupById); wipe(groupOfCat)
    nextGroupSeq = 0
    for i = #groups, 1, -1 do
        local g = groups[i]
        -- strict type checks: a corrupt SavedVariables entry (numeric id, string
        -- cats, ...) must be dropped/repaired here, not error out OnEnable.
        if not (type(g) == "table" and type(g.id) == "string") then
            table.remove(groups, i)   -- malformed (hand-edited SavedVariables): drop
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
                table.remove(g.cats, j)   -- pseudo/dead/duplicate: can never be grouped
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
    if categoriesChanged then categoriesChanged() end   -- coalesced relayout + sidebar
end

-- THE render order. Returns an array of entries:
--   { kind = "cat",   key = catKey }
--   { kind = "group", group = g, cats = { existing member keys, in g.cats order } }
-- Order: pinned, recent (pseudo, always top) -> groups in mod.db.groups order
-- (members in the group's own order) -> ungrouped cats in orderedCategoryKeys()
-- order. With zero groups this is exactly orderedCategoryKeys() -> no behavior change.
function groupedDisplay()
    local base, out, inBase = orderedCategoryKeys(), {}, {}
    for _, key in ipairs(base) do inBase[key] = true end
    if inBase.pinned then out[#out + 1] = { kind = "cat", key = "pinned" } end
    if inBase.recent then out[#out + 1] = { kind = "cat", key = "recent" } end
    for _, g in ipairs(groups) do
        local cats = {}
        for _, key in ipairs(g.cats) do
            if inBase[key] then cats[#cats + 1] = key end   -- disabled/gone keys skipped
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

-- Deleting a group NEVER deletes categories: its members simply become ungrouped
-- (groupOfCat is rebuilt from the remaining groups).
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

-- groupId = nil -> remove from its current group ("ungroup").
function assignCatToGroup(catKey, groupId)
    if not groupableKey(catKey) then return end          -- pinned/recent/__unassign/dead: never
    local target = groupId and groupById[groupId] or nil
    if groupId and not target then return end            -- unknown group: no-op
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
    -- disabled built-ins stay members but don't render -- skip them when picking
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

-- =========================================================
-- State
-- =========================================================
local bagFrame                      -- the main window (built lazily, out of combat)
local buttons     = {}              -- pooled item buttons, indexed by visual position
local indexFrames = {}              -- [bag] = plain Frame carrying SetID(bag)
local btnCounter  = 0               -- global-name counter
local pendingRelayout = false       -- set when a rebuild was blocked by combat
local searchText  = ""              -- lowercased live query ("" = no filter)
local sortReverse = false           -- runtime mirror of mod.db.sortReverse
local sortMode    = "blizzard"      -- runtime mirror of mod.db.sortMode
local sortInFlight = false          -- true while a custom-sort move batch drains
local useCategories = true          -- runtime mirror of mod.db.useCategories
local hideEmpty     = true          -- runtime mirror of mod.db.hideEmpty
local viewMode         = "all"      -- "all" | "onebag" | "multibag" (mirror of mod.db.viewMode)
local sidebarExpanded  = false      -- true = panel open (mirror of NOT mod.db.sidebarCollapsed)
-- selectedCategory is declared earlier (near the custom-category state) so the
-- CRUD functions above can reference it; do NOT redeclare it here.
local sidebarWidth     = SIDEBAR_W_COLLAPSED  -- live width; finishSize() reads this

-- Forward declarations (real definitions further down). Declared ONCE here, before
-- ANY of them is defined or referenced, so every closure/dispatcher binds the same
-- upvalue (defining `local function layout` later would shadow these -> nil calls).
local layout, layoutOneBag, layoutMultiBag
local buildSidebar, rebuildSidebar, applySidebarWidth

-- =========================================================
-- Helpers
-- =========================================================
-- Phase 4 STAGE-2: the DISPLAYED bag list — bags 0..4 minus the user-hidden
-- ones, plus the keyring (-2) when enabled. Everything that RENDERS iterates
-- this; sorting + the Recent baseline stay on the physical bags 0..4.
local KEYRING = _G.KEYRING_CONTAINER or -2
local function visibleBags()
    local out, hidden = {}, (mod.db and mod.db.hiddenBags) or {}
    for _, bag in ipairs(BAGS) do
        if not hidden[bag] then out[#out + 1] = bag end
    end
    if mod.db and mod.db.showKeyring and not hidden[KEYRING] then out[#out + 1] = KEYRING end
    return out
end

-- Localized display name for a container (backpack / equipped bag / keyring).
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
        if bag ~= KEYRING then   -- keyring is dynamic; its "free" count is noise
            local f = GetContainerNumFreeSlots(bag)
            free = free + (f or 0)
        end
    end
    return free
end

-- First empty slot across the visible regular bags (for the quick-drop slot).
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

-- STAGE-2: snapshot current bag contents as itemID -> total count (used by the Recent diff).
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

-- STAGE-2: mark everything currently in bags as "seen" and clear the Recent set. Called
-- when the bag window closes, so "recent" means "acquired since you last closed the bag".
local function markRecentSeen()
    recentBaseline = snapshotTotals()
    recentPrimed = true
    if wipe then wipe(recentItems); wipe(recentOrder) else recentItems, recentOrder = {}, {} end
end

local function updateMoney()
    if bagFrame and bagFrame.money and GetCoinTextureString then
        bagFrame.money:SetText(GetCoinTextureString(GetMoney() or 0))
    end
end

local function updateFree()
    if bagFrame and bagFrame.free then
        bagFrame.free:SetText(string.format(L["%d free"], freeSlots()))
    end
end

-- Search match. Returns true (match), false (no match) or nil (data not ready ->
-- keep the slot shown and retry on the next refresh). Cache-safe: never forces
-- the async GetItemInfo; the display name lives inside the item link, and
-- GetItemInfoInstant is local-only (no network).
local function itemMatchesSearch(bag, slot, query)
    local searchText = query or searchText   -- Phase 4: the bank passes its own query
    if searchText == "" then return true end
    local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
    if not link then return false end                     -- empty slot vs a non-empty query
    if link:lower():find(searchText, 1, true) then return true end  -- name is inside the link
    if GetItemInfoInstant then
        -- returns: itemID, itemType(str), itemSubType(str), equipLoc(str), icon, classID(num), subClassID(num)
        local _, itemType, itemSubType, equipLoc = GetItemInfoInstant(link)
        for _, field in ipairs({ itemType, itemSubType, equipLoc }) do
            if type(field) == "string" and field ~= "" and field:lower():find(searchText, 1, true) then
                return true
            end
        end
    end
    return false
end

-- =========================================================
-- Category classifier. Numeric Enum.ItemClass IDs (locale-independent).
-- =========================================================
local CLASS_CONSUMABLE, CLASS_CONTAINER, CLASS_WEAPON, CLASS_GEM = 0, 1, 2, 3
local CLASS_ARMOR, CLASS_REAGENT, CLASS_PROJECTILE, CLASS_TRADEGOODS = 4, 5, 6, 7
local CLASS_RECIPE, CLASS_QUIVER, CLASS_QUEST, CLASS_KEY, CLASS_MISC = 9, 11, 12, 13, 15

local GetQuestInfo = _G.C_Container and _G.C_Container.GetContainerItemQuestInfo
local categoryCache = {}   -- [itemID] = class-derived categoryKey (class is intrinsic)

-- class/equip-slot only (never quest/junk -- those are decided per-slot below), so
-- this result is safe to cache by itemID.
local function classifyLink(link)
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

-- categoryKey for a slot:
--   manual assignment (if the target still exists) > quest flag > junk > cached class.
-- The class cache holds ONLY classifyLink() output, so assignments never poison it
-- and wiping it never loses an assignment (assignments live in itemAssignments).
local function categoryFor(bag, slot)
    local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
    if not link then return nil end
    local _, _, _, quality, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)
    if itemID then
        if pinnedItems[itemID] then return "pinned" end               -- STAGE-2: pin wins over everything
        local assigned = itemAssignments[itemID]
        if assigned and categoryExists(assigned) then return assigned end
        if mod.db and mod.db.showRecent ~= false and recentItems[itemID] then return "recent" end  -- STAGE-2
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

-- Refresh one button's visuals from its own bag/slot (never touches interactivity).
local function updateButton(btn)
    local bag  = btn:GetParent():GetID()
    local slot = btn:GetID()
    local icon, count, locked, quality, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)

    SetItemButtonTexture(btn, icon)
    SetItemButtonCount(btn, count)
    SetItemButtonDesaturated(btn, locked)

    -- keep the "new item" / battlepay glow suppressed (cheap insurance in case
    -- anything re-shows it; the heavy strip happens once in acquireButton)
    local ng = btn.NewItemTexture or _G[btn:GetName() .. "NewItemTexture"]
    if ng and ng:IsShown() then ng:Hide() end
    local bp = btn.BattlepayItemTexture or _G[btn:GetName() .. "BattlepayItemTexture"]
    if bp and bp:IsShown() then bp:Hide() end

    -- quality border: our own crisp 1px edge in the item's quality colour —
    -- clearly visible, unlike the template's soft IconBorder glow. Poor/common
    -- items get none (visual noise).
    local qf = btn._qborder
    if qf then
        if mod.db.qualityBorders ~= false and quality and quality >= 2 and GetItemQualityColor then
            local r, g, b = GetItemQualityColor(quality)
            qf:SetColorTexture(r, g, b, 1)
            qf:Show()
        else
            qf:Hide()
        end
    end

    -- item level on equipment (weapons/armor), quality-coloured, top-left.
    -- GetItemInfo can miss on uncached items -> hidden now, filled by the next
    -- refresh (BAG_UPDATE bursts re-run updateButton anyway).
    local fs = btn._ilvl
    if fs then
        local lvl
        if mod.db.showItemLevel ~= false and link and GetItemInfoInstant then
            local _, _, _, equipLoc, _, classID = GetItemInfoInstant(link)
            if (classID == 2 or classID == 4) and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" then
                lvl = (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link))
                    or (GetItemInfo and select(4, GetItemInfo(link)))
            end
        end
        if lvl and lvl > 1 then
            -- same font/size as the stack-count numbers (follows the option live)
            if UI and UI.FONT_PATH then
                pcall(fs.SetFont, fs, UI.FONT_PATH, mod.db.countFontSize or 12, "OUTLINE")
            end
            fs:SetText(lvl)   -- plain white (set at creation)
            fs:Show()
        else
            fs:Hide()
        end
    end

    -- count font = our font at the configured size
    local cnt = _G[btn:GetName() .. "Count"]
    if cnt and UI and UI.FONT_PATH then
        pcall(cnt.SetFont, cnt, UI.FONT_PATH, mod.db.countFontSize or 12, "OUTLINE")
    end

    -- cooldown swirl
    local cd = _G[btn:GetName() .. "Cooldown"]
    if cd then
        local start, dur, enable = GetContainerItemCooldown(bag, slot)
        if start and dur and dur > 0 then
            CooldownFrame_Set(cd, start, dur, enable)
        elseif cd.Hide then
            cd:Hide()
        end
    end

    -- search dimming: matched = full alpha, non-match = dimmed (but still fully
    -- interactive -- we only touch alpha, never Enable/Hide, so the secure click
    -- handler is untouched). nil (item not cached yet) keeps it visible + retried.
    if searchText == "" then
        btn:SetAlpha(1)
    else
        btn:SetAlpha(itemMatchesSearch(bag, slot) ~= false and 1 or 0.25)
    end
end

-- Get (or lazily create, OUT of combat) the plain frame that carries a bag id.
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

-- Get (or lazily create, OUT of combat) the pooled secure button at position n.
local function acquireButton(n)
    local btn = buttons[n]
    if btn then return btn end
    if InCombatLockdown() then return nil end
    btnCounter = btnCounter + 1
    btn = CreateFrame("Button", "VuloClassicUIBagItem" .. btnCounter, bagFrame.content,
        "ContainerFrameItemButtonTemplate")
    btn:SetSize(BTN, BTN)
    -- STAGE-2: middle-click toggles a "pin". Passing an explicit list REPLACES the
    -- template's click registration, so we re-list Left/Right to keep Blizzard's secure
    -- use/equip/pickup path intact. Registered ONCE here, always out of combat
    -- (acquireButton bails in combat above), so no protected-in-combat taint.
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    -- Additive post-hook only (never SetScript): runs AFTER the secure handler, so
    -- left/right use/equip already fired; the middle branch does nothing secure
    -- (reads item info, flips a plain Lua table, relayouts) -> cannot taint the action.
    btn:HookScript("OnClick", function(self, mouseButton)
        if mouseButton ~= "MiddleButton" then return end
        local bg = self:GetParent() and self:GetParent():GetID()
        local sl = self:GetID()
        if not (bg and sl) then return end
        local _, _, _, _, _, _, _, _, _, itemID = GetContainerItemInfo(bg, sl)
        if not itemID then return end
        if pinnedItems[itemID] then pinnedItems[itemID] = nil
        else pinnedItems[itemID] = true end
        if categoriesChanged then categoriesChanged() end   -- re-bucket + relayout + sidebar
    end)
    -- Clean dark slots. The modern item-button template shows a "new item" glow
    -- (atlas bags-glow-*) + a battlepay overlay on EVERY slot here -- suppressing
    -- the default bags means the game's "new item" flags never get cleared, so
    -- every slot glows. Hide those overlays (and stop their glow animations), plus
    -- Blizzard's blue empty-slot NormalTexture.
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
    -- belt-and-suspenders: hide any remaining glow-atlas texture on the button
    for r = 1, select("#", btn:GetRegions()) do
        local reg = select(r, btn:GetRegions())
        if reg and reg.GetObjectType and reg:GetObjectType() == "Texture" and reg.GetAtlas then
            local a = reg:GetAtlas()
            if type(a) == "string" and a:find("glow", 1, true) then reg:Hide() end
        end
    end
    -- dark empty-slot backing (shows through empty slots; icon covers it when full)
    local sb = btn:CreateTexture(nil, "BACKGROUND")
    sb:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    sb:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    sb:SetColorTexture(0.10, 0.10, 0.13, 0.55)
    btn._slotbg = sb
    -- quality border: a full-button colour layer BEHIND the 1px-inset icon.
    -- A filled ring can never drop a side (no hairline sub-pixel rasterization)
    -- and stays evenly thin at every resolution/scale — the reference look.
    local qb = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    qb:SetAllPoints(btn)
    -- disable pixel snapping on BOTH ring and icon: with snapping, each edge
    -- independently rounds to the pixel grid and the ring rasterizes 1px on one
    -- side, 2px on another. Anti-aliased edges render the ring evenly thick on
    -- every side at any position/scale (and a filled ring can never vanish).
    if qb.SetSnapToPixelGrid then qb:SetSnapToPixelGrid(false); qb:SetTexelSnappingBias(0) end
    qb:Hide()
    btn._qborder = qb
    local iconTex = _G[bname .. "IconTexture"] or btn.icon
    if iconTex then
        iconTex:ClearAllPoints()
        iconTex:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        iconTex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- crop the icon's own dark bevel
        if iconTex.SetSnapToPixelGrid then iconTex:SetSnapToPixelGrid(false); iconTex:SetTexelSnappingBias(0) end
    end
    -- item level text: plain white, standard number font (equipment only)
    local il = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    il:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    il:SetTextColor(1, 1, 1)
    il:Hide()
    btn._ilvl = il
    btn:Hide()   -- layout() shows the ones it uses; keeps pre-allocated buttons invisible
    buttons[n] = btn
    return btn
end

-- Pooled category-section header FontStrings (plain text -> no taint).
local sectionHeaders = {}
local function acquireHeader(n)
    local h = sectionHeaders[n]
    if h then return h end
    if not bagFrame then return nil end
    h = bagFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if UI and UI.Font then UI.Font(h, 12) end
    h:SetJustifyH("LEFT")
    h:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    h:Hide()
    sectionHeaders[n] = h
    return h
end

-- STAGE-3: pooled group-section headers. Plain Buttons (label + v/> glyph on a
-- faint accent bar) -> zero taint; they never host or overlap secure item buttons
-- (layout reserves their rows). Left-click toggles collapse, right-click opens
-- the group menu. Safe to create in combat (insecure frames).
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
    label:SetTextColor(1, 1, 1)   -- white on accent bar = distinct from accent category headers
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

-- =========================================================
-- Layout. Two modes: one flat grid, or category sections. A dispatcher named
-- layout() (kept, since refresh/Open/options/events call it) picks based on the
-- useCategories setting. Both preserve the secure button/index-frame wiring and
-- only change WHERE a button is placed.
-- =========================================================
local function finishSize(cols, contentH, blocked, extraW)
    if blocked then pendingRelayout = true end
    local contentW = cols * (BTN + GAP) - GAP + (extraW or 0)   -- STAGE-3: group indent
    contentH = math.max(contentH, BTN)

    -- scroll CHILD = true content size (may exceed the viewport -> scrolls)
    bagFrame.content:SetSize(contentW, contentH)

    -- viewport height capped to a fraction of the screen; width = content width
    local cap = math.floor(UIParent:GetHeight() * CONTENT_MAX_FRAC)
    local vpH = math.min(contentH, cap)
    local vp  = bagFrame.contentVP
    if vp then vp:SetSize(contentW, vpH) end

    -- scrollbar range + visibility from overflow
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

    -- window = padding + sidebar + GAP + content + (scrollbar gutter) + padding.
    -- Height uses the CAPPED viewport height, so the window never exceeds the screen.
    local barGutter = (sbar and sbar:IsShown()) and 10 or 0
    bagFrame:SetSize(PAD + sidebarWidth + GAP + contentW + barGutter + PAD,
                     HEADER_H + vpH + FOOTER_H + PAD)
    updateMoney()
    updateFree()
end

-- Phase 4 STAGE-2: park the quick-drop slot on its own row at the very bottom
-- of the content (directly under the last section); returns its height so the
-- caller can grow contentH. It lives in the scroll child, so it scrolls along.
local function placeDropSlot(y, blocked)
    local d = bagFrame and bagFrame.dropSlot
    if not d then return 0 end
    -- a combat-blocked layout can abort MID-SECTION: buttons of the partial
    -- section are already shown at/below y, so parking the drop there would
    -- stack it onto them (and under-report contentH). Hide until the
    -- pendingRelayout pass after combat.
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
    for _, bag in ipairs(visibleBags()) do
        local slots = GetContainerNumSlots(bag) or 0
        local idx = ensureIndexFrame(bag)
        if not idx then blocked = true; break end
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
                col * (BTN + GAP), -row * (BTN + GAP))
            btn:Show()
            updateButton(btn)
        end
        if blocked then break end
    end
    for i = n + 1, #buttons do buttons[i]:Hide() end
    for i = 1, #sectionHeaders do sectionHeaders[i]:Hide() end   -- no headers in flat mode
    for i = 1, #groupHeaders do groupHeaders[i]:Hide() end       -- STAGE-3: no group chrome either
    local rows = math.max(1, math.ceil(math.max(n, 1) / cols))
    local h = rows * (BTN + GAP) - GAP
    h = h + GAP + placeDropSlot(h + GAP)   -- quick-drop row under the grid
    finishSize(cols, h, blocked)
end

-- occupied slots bucketed by category, preserving slot order (so sort carries in)
local function collectByCategory()
    local buckets = {}
    for _, bag in ipairs(visibleBags()) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            if GetContainerItemLink and GetContainerItemLink(bag, slot) then
                local key = categoryFor(bag, slot) or "misc"
                if disabledCats[key] then key = "misc" end   -- disabled built-in -> catch-all
                local b = buckets[key]; if not b then b = {}; buckets[key] = b end
                b[#b + 1] = { bag = bag, slot = slot }
            end
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

    -- One category section at x-offset `indent`. Returns false when combat-blocked.
    -- Same show rule as before: a picked filter shows ONLY that category (even
    -- empty, so the window isn't blank); otherwise the hide-empty rule applies.
    local function renderCategory(key, indent)
        local items = buckets[key]
        local count = items and #items or 0
        local show = (not filtered and (count > 0 or not hideEmpty))
                  or (filtered and key == selectedCategory)
        if not show then return true end
        hdrN = hdrN + 1
        local h = acquireHeader(hdrN)
        if h then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT", 1 + indent, -y)
            h:SetText(string.format("%s  |cff808080(%d)|r", catName(key), count))
            h:Show()
        end
        y = y + HEADER_ROW
        for i = 1, count do
            local it  = items[i]
            -- bail BEFORE consuming a button index: a consumed-but-unplaced index
            -- would be skipped by the trailing hide loop, leaving that pooled secure
            -- button SHOWN at its stale previous-layout position (misclick hazard).
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
            -- STAGE-3: an active filter renders the selected category FLAT, with no
            -- group chrome -- the group is effectively forced expanded for this view
            -- (its persisted collapsed flag is untouched).
            for _, key in ipairs(entry.cats) do
                if key == selectedCategory then renderCategory(key, 0); break end
            end
        else
            local g = entry.group
            local total = 0
            for _, key in ipairs(entry.cats) do
                total = total + (buckets[key] and #buckets[key] or 0)
            end
            -- same visibility rule as a category: hide an all-empty group when
            -- hideEmpty is on (a freshly created empty group is managed via the
            -- sidebar, which always lists it)
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
                    y = y + GAP   -- collapsed: skip every member section entirely
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
    -- y already carries the trailing section GAP -> the drop slot lands exactly
    -- one GAP below the last category, then grows the content by its height
    local dropH = placeDropSlot(y)
    finishSize(cols, y + dropH, blocked, (ghN > 0) and GROUP_INDENT or 0)
end

-- OneBag: every OCCUPIED slot from bags 0-4 in one flat grid, one header.
layoutOneBag = function()
    if not (bagFrame and mod.active) then return end
    local cols = mod.db.columns or 12
    if cols < 1 then cols = 1 end

    local items = {}
    for _, bag in ipairs(visibleBags()) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            if GetContainerItemLink and GetContainerItemLink(bag, slot) then
                items[#items + 1] = { bag = bag, slot = slot }
            end
        end
    end

    local btnN, blocked = 0, false
    local y = 0
    local h = acquireHeader(1)
    if h then
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT", 1, -y)
        h:SetText(string.format("%s  |cff808080(%d)|r", L["All Bags"], #items))
        h:Show()
    end
    y = y + HEADER_ROW

    for i = 1, #items do
        local it  = items[i]
        -- bail BEFORE consuming a button index (see layoutCategorized note)
        local idx = ensureIndexFrame(it.bag)
        if not idx then blocked = true; break end
        btnN = btnN + 1
        local btn = acquireButton(btnN)
        if not btn then blocked = true; break end
        btn:SetParent(idx)
        btn:SetID(it.slot)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT",
            col * (BTN + GAP), -(y + row * (BTN + GAP)))
        btn:Show()
        updateButton(btn)
    end
    if #items > 0 then y = y + math.ceil(#items / cols) * (BTN + GAP) else y = y + BTN end

    for i = btnN + 1, #buttons do buttons[i]:Hide() end
    for i = 2, #sectionHeaders do sectionHeaders[i]:Hide() end
    for i = 1, #groupHeaders do groupHeaders[i]:Hide() end   -- STAGE-3
    local dropH = placeDropSlot(y)
    finishSize(cols, y + dropH, blocked)
end

-- MultiBag: one section per bag 0-4 (all slots in slot order), skips empty bags.
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
            local h = acquireHeader(hdrN)
            if h then
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT", 1, -y)
                h:SetText(string.format("%s  |cff808080(%d)|r", bagName, slots))
                h:Show()
            end
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
    for i = 1, #groupHeaders do groupHeaders[i]:Hide() end   -- STAGE-3
    local dropH = placeDropSlot(y)
    finishSize(cols, math.max(y + dropH, BTN), blocked)
end

-- Dispatcher (assigned to the forward-declared upvalue). Routes by viewMode.
local lastLayoutSig   -- identity of the last laid-out view (mode|filter|sort|categorized)
function layout()
    if not (bagFrame and mod.active) then return end
    -- STAGE-2: when the view IDENTITY changes (view mode / category filter / sort /
    -- categorized toggle) the retained pixel scroll offset points at a different set of
    -- rows, so reset it to the top. A plain content refresh (same identity) keeps its
    -- scroll position -- looting while scrolled down doesn't snap you back up.
    local sig = tostring(viewMode) .. "|" .. tostring(selectedCategory) .. "|"
        .. tostring(sortMode) .. "|" .. tostring(sortReverse) .. "|" .. tostring(useCategories)
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

-- coalesce a burst of BAG_UPDATE etc. into one relayout next frame
local refreshScheduled = false
local function refresh()
    if not (mod.active and bagFrame and bagFrame:IsShown()) then return end
    if refreshScheduled then return end
    refreshScheduled = true
    local function run()
        refreshScheduled = false
        -- if the filtered category emptied out, fall back to All (no stranded blank)
        if selectedCategory ~= "all" then
            local b = collectByCategory()[selectedCategory]
            if not (b and #b > 0) then selectedCategory = "all" end
        end
        if sidebarExpanded and rebuildSidebar then rebuildSidebar() end
        if bagFrame.bagBar and bagFrame.bagBar:IsShown() and bagFrame.updateBagBar then
            bagFrame.updateBagBar()   -- bag swaps change the strip's icons
        end
        layout()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

-- Phase 3c: an assignment/category change never touches categoryCache (class-only);
-- it just needs a re-bucket + relayout + sidebar rebuild, which refresh() does.
function categoriesChanged() refresh() end

-- =========================================================
-- Sort. Native SortBags() is unreliable on Classic (it's only a global when an
-- external sort addon is present; C_Container.SortBags is retail-only), so we
-- PREFER the native call when it genuinely exists and otherwise fall back to our
-- own Lua sort. Both are taint-safe from a plain button (only PickupContainerItem
-- + ClearCursor, no protected item API) and both bail in combat.
-- =========================================================
local SORT_BAGS = { 0, 1, 2, 3, 4 }
local sortBagsActive = SORT_BAGS   -- Phase 4: doSort() may point this at the bank's bag list

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

-- strict weak ordering; primary key depends on sortMode, rest are stable tie-breaks
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
    else -- "quality" (also the custom fallback used when a client lacks native sort)
        if qa ~= qb then if sortReverse then return qa < qb else return qa > qb end end
        if ta ~= tb then return ta < tb end
        if sa ~= sb then return sa < sb end
        if na ~= nb then if sortReverse then return na > nb else return na < nb end end
        return false
    end
end

-- Fallback sort (only runs when the client has NO native SortBags). Selection
-- sort: for each target position, bring the "smallest" remaining item into it
-- with a proper 3-pickup swap. Converges in <= N swaps (one swap per frame so
-- item locks settle); never swaps two identical stacks (so nothing merges); a
-- 3-pickup swap is a clean exchange, so an item is never stranded on the cursor.
local _sortStep = 0
local sortPos   = 1

-- should x be placed before y? non-empty before empty; among items, by sortLess.
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
            sortPos = sortPos + 1                       -- right item already here
        else
            local a, b = slots[sortPos], slots[best]
            if slotLocked(a.bag, a.slot) or slotLocked(b.bag, b.slot) then
                if C_Timer and C_Timer.After then C_Timer.After(0, customSortStep) else sortInFlight = false end
                return                                  -- locked: retry this position next frame
            end
            -- proper 3-pickup swap (clean whether the other slot is empty or full)
            PickupContainerItem(a.bag, a.slot)
            PickupContainerItem(b.bag, b.slot)
            PickupContainerItem(a.bag, a.slot)
            ClearCursor()
            sortPos = sortPos + 1
            if C_Timer and C_Timer.After then C_Timer.After(0, customSortStep) else customSortStep() end
            return                                      -- one swap per frame
        end
    end
    sortInFlight = false
    refresh()
end

-- Phase 4: doSort optionally takes a bag list + native sorter so the bank
-- window can reuse the whole machinery (its own containers, its own native fn).
local function doSort(bagList, nativeFn)
    if sortInFlight then return end
    if InCombatLockdown() or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        if UIErrorsFrame then UIErrorsFrame:AddMessage(L["Can't sort bags in combat."], 1, 0.2, 0.2) end
        return
    end
    local native = bagList and nativeFn or (not bagList and nativeSort) or nil
    -- "blizzard" mode uses Blizzard's native category sort when the client has it
    -- (stacks merge, combat-safe); quality/type/name always use our own sort.
    if sortMode == "blizzard" and native then
        if nativeSetDir then pcall(nativeSetDir, sortReverse and true or false) end
        pcall(native)                -- Blizzard handles the moves + combat + stacks
        refresh()                    -- BAG_UPDATE will also fire; belt-and-suspenders
        return
    end
    sortBagsActive = bagList or SORT_BAGS
    sortInFlight = true
    _sortStep = 0
    sortPos = 1
    customSortStep()
end

-- Published for Modules/Bank.lua: shared search matcher + sort driver. The sort
-- respects the shared "Sort order" / "Reverse" settings; concurrent sorts are
-- already serialized by sortInFlight.
ns.BagItemMatchesSearch = itemMatchesSearch
ns.RunBagSort = doSort

-- =========================================================
-- Sidebar (Phase 3b) — plain frames only. It SELECTS what layout() draws; it
-- never creates or moves secure item buttons, so every click/hover/scroll/resize
-- is taint-free and legal in combat.
-- =========================================================
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

    -- Phase 3c: drop/hold an item on a category row to assign it; right-click for
    -- the category menu. GetCursorInfo/ClearCursor are unprotected on 20505/11508
    -- (read the cursor, drop it back) -> taint-free from this plain button.
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
        if key == "recent" then return false end          -- STAGE-2: recent is not an assignment target
        if key == "pinned" then                           -- STAGE-2: dropping on Pinned pins the item
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
            if self._groupId and showGroupMenu then                       -- STAGE-3 group row
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
        -- collapsed shows a right ("expand") arrow, expanded a left ("collapse") one
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
        if not sidebarExpanded then selectedCategory = "all" end  -- don't strand a filter
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

-- Populate/refresh sidebar rows: VIEW modes, then (in "all" view) a CATEGORIES list.
function rebuildSidebar()
    if not (bagFrame and bagFrame.sidebarChild and sidebarExpanded) then return end
    local child, pool = bagFrame.sidebarChild, bagFrame.sbRows
    local n, y = 0, 0

    local function sectionLabel(text)
        n = n + 1
        local row = makeSidebarRow(child, pool, n)
        row.icon:Hide(); row.sel:Hide(); row.bg:SetAlpha(0); row._selected = false
        row._onClick = nil; row._catKey = nil; row._groupId = nil   -- inert header (constructor dispatches on these)
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
        row.icon:SetPoint("LEFT", row, "LEFT", 6 + (indent or 0), 0)   -- STAGE-3 indent
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
        row._onClick = onClick     -- constructor OnClick dispatches here
        row._catKey  = catKey      -- nil = plain row; a key = drop/menu target
        row._groupId = nil         -- STAGE-3: pooled row may have been a group row
        row:Show()
        y = y + SIDEBAR_BTN_H + SIDEBAR_BTN_GAP
    end

    -- STAGE-3: a group row -- accent label with v/> glyph + summed count. Click
    -- toggles collapse; right-click opens the group menu (via _groupId in the
    -- constructor). NOT a drop/assign target (_catKey = nil).
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
            if GetCursorInfo and GetCursorInfo() == "item" then return end  -- don't toggle while dragging
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
        -- All Items row: click = clear filter; drop an item here = un-assign it (__unassign)
        itemRow(categoryIcon("misc"), L["All Items"], nil, selectedCategory == "all", function()
            if selectedCategory == "all" then return end
            selectedCategory = "all"; rebuildSidebar()
            if mod:IsOpen() then layout() end
        end, "__unassign")
        -- STAGE-3: same visibility rule as before per category (has items OR is a
        -- custom drop target); groups are ALWAYS listed (management surface).
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
                    catRow(selectedCategory, SIDEBAR_INDENT)   -- never hide the active filter row
                end
            end
        end
        -- [+] create a new custom category / a new group
        itemRow("Interface\\Buttons\\UI-PlusButton-Up", L["New category..."], nil, false,
            function() if promptNewCategory then promptNewCategory() end end, nil)
        itemRow("Interface\\Buttons\\UI-PlusButton-Up", L["New group..."], nil, false,
            function() if promptNewGroup then promptNewGroup() end end, nil)
    end

    for i = n + 1, #pool do pool[i]:Hide() end
    child:SetHeight(math.max(y, 10))
    -- STAGE-3: collapsing a group can shrink the child below the current scroll
    -- offset -- clamp so the sidebar is never stuck scrolled into blank space.
    local s = bagFrame.sidebarScroll
    if s then
        local maxs = math.max(0, child:GetHeight() - s:GetHeight())
        if (s:GetVerticalScroll() or 0) > maxs then s:SetVerticalScroll(maxs) end
    end
end

-- =========================================================
-- Frame construction (out of combat)
-- =========================================================
local function buildFrame()
    if bagFrame or InCombatLockdown() then return bagFrame end
    local f = CreateFrame("Frame", "VuloClassicUIBagFrame", UIParent)
    bagFrame = f
    f:SetFrameStrata("HIGH")
    f:SetSize(400, 300)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:Hide()
    -- STAGE-2: closing the window marks the current contents as "seen" (Recent then only
    -- shows items gained since). OnHide fires only on a real shown->hidden transition, so
    -- repeated CloseAllBags while already closed won't wipe freshly-acquired recents.
    f:HookScript("OnHide", function() markRecentSeen() end)
    if UI and UI.StyleBackdrop then UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border }) end
    if UI and UI.CreateShadow then UI:CreateShadow(f) end
    if _G.tinsert and _G.UISpecialFrames then tinsert(UISpecialFrames, "VuloClassicUIBagFrame") end

    -- accent strip along the top
    local strip = f:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    if UI and UI.SetGradient then
        local a = ns.COLORS.accent
        UI.SetGradient(strip, "HORIZONTAL", a.r, a.g, a.b, 0.1, a.r, a.g, a.b, 0.9)
    end

    -- header: title + close
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if UI and UI.Font then UI.Font(f.title, 14) end
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -9)
    f.title:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    f.title:SetText(L["Inventory"])

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -7)
    local cx = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cx:SetPoint("CENTER"); cx:SetText("x"); cx:SetTextColor(0.7, 0.7, 0.75)
    close:SetScript("OnEnter", function() cx:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b) end)
    close:SetScript("OnLeave", function() cx:SetTextColor(0.7, 0.7, 0.75) end)
    close:SetScript("OnClick", function() mod:Close() end)

    -- header search box (right side of the header, left of the close button)
    local sb = CreateFrame("EditBox", nil, f)
    f.search = sb
    sb:SetAutoFocus(false)
    sb:SetSize(150, 18)
    sb:SetPoint("RIGHT", close, "LEFT", -8, 0)
    sb:SetFont(UI.FONT_PATH, 11, "")
    sb:SetMaxLetters(40)
    sb:SetTextInsets(22, 8, 0, 0)
    sb:SetTextColor(0.9, 0.9, 0.95)
    local sbBg = sb:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints(sb); sbBg:SetColorTexture(0.04, 0.04, 0.055, 0.95)
    local sbIcon = sb:CreateTexture(nil, "OVERLAY")
    sbIcon:SetSize(11, 11)
    sbIcon:SetPoint("LEFT", sb, "LEFT", 6, 0)
    sbIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    sbIcon:SetVertexColor(0.55, 0.55, 0.62)
    local sbBorder = CreateFrame("Frame", nil, sb, BackdropTemplateMixin and "BackdropTemplate")
    sbBorder:SetAllPoints(sb)
    if sbBorder.SetBackdrop then
        sbBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        sbBorder:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    end
    sb:SetScript("OnEditFocusGained", function()
        if sbBorder.SetBackdropBorderColor then sbBorder:SetBackdropBorderColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1) end
    end)
    sb:SetScript("OnEditFocusLost", function()
        if sbBorder.SetBackdropBorderColor then sbBorder:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1) end
    end)
    sb:SetScript("OnTextChanged", function(self)
        searchText = (self:GetText() or ""):lower()
        refresh()
    end)
    sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    sb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    if not mod.db.showSearch then sb:Hide() end

    -- header sort button (icon; left of the search box). Right-click toggles order.
    local sortBtn = CreateFrame("Button", nil, f)
    f.sortBtn = sortBtn
    sortBtn:SetSize(18, 18)
    sortBtn:SetPoint("RIGHT", sb, "LEFT", -8, 0)
    local si = sortBtn:CreateTexture(nil, "ARTWORK")
    si:SetAllPoints(); si:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
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

    -- Phase 4 STAGE-2: bag-filter button (left of sort) — a menu with one
    -- checkable entry per bag + the keyring toggle. Plain frames + a table
    -- write per toggle -> zero taint; keepOpen lets the user flip several.
    local bagsBtn = CreateFrame("Button", nil, f)
    f.bagsBtn = bagsBtn
    bagsBtn:SetSize(18, 18)
    bagsBtn:SetPoint("RIGHT", sortBtn, "LEFT", -8, 0)
    local bi = bagsBtn:CreateTexture(nil, "ARTWORK")
    bi:SetAllPoints(); bi:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
    bi:SetTexCoord(0.07, 0.93, 0.07, 0.93)
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

    -- Phase 4 STAGE-2: visual bag bar — a strip of the real bag icons floating
    -- above the window (backpack, bags 1-4, keyring). Clicking an icon toggles
    -- that bag's visibility in the grid (hidden = desaturated + dim). Plain
    -- buttons flipping db flags -> zero taint. The header button toggles the bar.
    local ICON_N = #BAGS + 1                    -- bags + keyring
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

    -- content grid area
    -- sidebar (plain-frame left panel: view modes + category filter)
    buildSidebar(f)
    -- content grid area — a ScrollFrame viewport whose scroll CHILD holds the grid.
    -- The child keeps the name f.content, so every layout function that anchors to
    -- bagFrame.content (index frames + secure buttons + section headers) is untouched;
    -- only the viewport clips + scrolls it. Secure wiring is therefore unchanged.
    local vp = CreateFrame("ScrollFrame", nil, f)
    f.contentVP = vp
    vp:SetPoint("TOPLEFT", f.sidebar, "TOPRIGHT", GAP, 0)   -- top-left fixed; size set in finishSize()
    vp:EnableMouseWheel(true)

    f.content = CreateFrame("Frame", nil, vp)   -- scroll CHILD; the grid lives here
    vp:SetScrollChild(f.content)
    f.content:SetPoint("TOPLEFT", vp, "TOPLEFT", 0, 0)

    -- slim custom scrollbar (purple thumb) on the viewport's right edge; shown only when
    -- content overflows (see finishSize). A plain Slider avoids the template's chrome.
    -- Parented to the WINDOW (not the viewport) so it is never clipped and always draws
    -- above the grid; still anchored to the viewport's right edge so it tracks it.
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
        sbar:SetValue(off)   -- keep the thumb in sync (OnValueChanged re-applies the scroll harmlessly)
    end)

    -- Phase 4 STAGE-2: quick-drop slot — drop or click an item onto it to stash
    -- it into the FIRST free bag slot. Item-button-sized and parented to the
    -- CONTENT (scroll child): each layout places it on its own row directly
    -- under the last section, so it scrolls with the grid. Plain button;
    -- PickupContainerItem with an item on the cursor is an unprotected place-
    -- into-slot (same call our custom sort uses), so this is taint-free.
    local drop = CreateFrame("Button", nil, f.content)
    f.dropSlot = drop
    drop:SetSize(BTN, BTN)
    drop:Hide()   -- layout() positions + shows it
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
        PickupContainerItem(bag, slot)   -- cursor holds an item -> places it there
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

    -- footer: free slots (left) + money (right)
    f.free = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.free:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 8)
    f.money = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 8)
    -- invisible hover region over the money text -> account gold tooltip
    local moneyBtn = CreateFrame("Button", nil, f)
    moneyBtn:SetPoint("TOPLEFT", f.money, "TOPLEFT", -4, 2)
    moneyBtn:SetPoint("BOTTOMRIGHT", f.money, "BOTTOMRIGHT", 4, -2)
    moneyBtn:SetScript("OnEnter", function(self)
        if ns.ShowGoldTooltip then ns.ShowGoldTooltip(self) end
    end)
    moneyBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- movable + scalable via our mover (Edit Mode); CENTER offset in db.x/db.y
    if ns.CreateMover then
        mod.mover = ns:CreateMover(f, {
            db = mod.db, scalable = true, anchorable = true,
            label = "|cffffffffBAGS|r",
            width = 160, height = 40,
        })
        if ns.ApplyMover then ns:ApplyMover(mod.mover) end
    end

    -- Direct drag anywhere not covered by an item button (header/edges/footer) —
    -- writes the SAME CENTER-offset model the mover uses, so both stay in sync.
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local fx, fy = self:GetCenter()
        local px, py = UIParent:GetCenter()
        if fx and fy and px and py then
            mod.db.x, mod.db.y = fx - px, fy - py
            if ns.ApplyMover and mod.mover then ns:ApplyMover(mod.mover) end
        end
    end)
    return f
end

-- pre-allocate enough buttons now (out of combat) so opening in combat is safe
local function preallocate()
    if InCombatLockdown() then return end
    if not bagFrame then buildFrame() end
    if not bagFrame then return end
    -- STAGE-3: create every per-bag index frame now (out of combat), so a layout
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

-- =========================================================
-- Open / close  (our window; state is our own, not Blizzard's)
-- =========================================================
function mod:IsOpen() return bagFrame and bagFrame:IsShown() end

function mod:Open()
    if not mod.active then return end
    if not bagFrame then
        if InCombatLockdown() then return end
        buildFrame()
    end
    if not bagFrame then return end
    bagFrame:Show()
    if applySidebarWidth then applySidebarWidth() end   -- sync width + arrow to saved state
    if rebuildSidebar then rebuildSidebar() end          -- populate (no-op if collapsed)
    -- bag swaps while the window was closed don't fire our refresh -> re-read
    -- the strip's icons on every open
    if bagFrame.bagBar and bagFrame.bagBar:IsShown() and bagFrame.updateBagBar then
        bagFrame.updateBagBar()
    end
    layout()
end

function mod:Close()
    if bagFrame then
        -- clear the query so we don't reopen with half the bag dimmed
        -- (SetText fires OnTextChanged -> searchText = "" -> refresh)
        if bagFrame.search then bagFrame.search:SetText("") end
        bagFrame:Hide()
    end
end

function mod:Toggle()
    if mod:IsOpen() then mod:Close() else mod:Open() end
end

-- option-driven visibility of the header widgets
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

-- =========================================================
-- Hooks: drive our window from the bag key / merchant / etc., and hide the
-- default bag windows. hooksecurefunc only — no global is replaced.
-- Toggle functions call Open/CloseAllBags internally, so hooking both would
-- double-fire; we record the DESIRED state and apply the last one next frame
-- (the Toggle*'s own hook fires last and computes from our real state).
-- =========================================================
local _hooked = false
local wantOpen, wantScheduled = false, false
local function applyWant() wantScheduled = false; if wantOpen then mod:Open() else mod:Close() end end
local function want(state)
    wantOpen = state
    if wantScheduled then return end
    wantScheduled = true
    if C_Timer and C_Timer.After then C_Timer.After(0, applyWant) else applyWant() end
end

-- Suppress the default bag windows by REPARENTING them to a permanently-hidden
-- frame. This beats hooking their OnShow to :Hide(): it's flicker-free and it
-- never calls Hide() on a protected ContainerFrame in combat (which would be
-- blocked). Only the regular bag frames 1..6 are touched; bank frames (7..13)
-- are left to Blizzard until the bank phase. Reparenting a protected frame is
-- only legal OUT of combat, so if we're enabled mid-combat we defer to
-- PLAYER_REGEN_ENABLED. Restored on disable.
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

-- =========================================================
-- Events
-- =========================================================
local _eventsWired = false
-- STAGE-2: recompute the Recent set from a per-itemID count diff vs the runtime baseline,
-- then snapshot the new totals. Recent is session-scoped (re-seeded every login/reload via
-- OnEnable), so the baseline is a runtime table -- nothing to persist. Capped to
-- mod.db.recentCap newest itemIDs. Called on BAG_UPDATE_DELAYED only (BAG_UPDATE counts
-- are unreliable mid-event).
function updateRecentItems()
    local baseline = recentBaseline
    local totals = snapshotTotals()

    -- 1) prune recent entries whose item is no longer in bags (consumed/sold/mailed),
    --    so Recent never lists a phantom that isn't actually present anymore.
    for i = #recentOrder, 1, -1 do
        local id = recentOrder[i]
        if not totals[id] then
            table.remove(recentOrder, i)
            recentItems[id] = nil
        end
    end

    -- 2) first scan of the session: seed the baseline, flag nothing as new
    if not recentPrimed then
        recentBaseline = totals
        recentPrimed = true
        return
    end

    -- 3) flag only item TYPES that were NOT present as of the last "seen" snapshot (login
    --    or last bag-close). Buying/looting MORE of something you already had does NOT
    --    re-flag it -- only brand-new item types show under Recent. Newest first.
    for itemID in pairs(totals) do
        if (baseline[itemID] or 0) == 0 then
            if recentItems[itemID] then
                for i = #recentOrder, 1, -1 do
                    if recentOrder[i] == itemID then table.remove(recentOrder, i); break end
                end
            else
                recentItems[itemID] = true
            end
            table.insert(recentOrder, 1, itemID)   -- (re)insert at front
        end
    end

    -- 4) enforce the cap (0 = unlimited)
    local cap = mod.db and mod.db.recentCap or 20
    if cap and cap > 0 then
        while #recentOrder > cap do
            local drop = table.remove(recentOrder)   -- oldest
            recentItems[drop] = nil
        end
    end
    -- NB: recentBaseline is intentionally NOT advanced here. It only moves forward on
    -- bag-close (markRecentSeen) or login-prime, so "recent" = "since you last closed".
end

-- STAGE-2: user-facing "clear recent" -- wipes the runtime set but keeps the baseline
-- so items already in bags do NOT re-flag as new.
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
        -- (disabling the module mid-combat skips restoreBlizzardBags)
        if mod.active then hideBlizzardBags()
        elseif _bagsSuppressed then restoreBlizzardBags() end
        if pendingRelayout then
            pendingRelayout = false
            preallocate()
            if mod:IsOpen() then layout() end
        end
    else
        -- class is intrinsic so the category cache rarely needs clearing, but a
        -- cheap wipe on the delayed event keeps it honest across itemID reuse.
        if event == "BAG_UPDATE_DELAYED" then
            if wipe then wipe(categoryCache) end
            if mod.db.showRecent ~= false then updateRecentItems() end   -- STAGE-2 recent diff
        end
        refresh()   -- BAG_UPDATE(_DELAYED), ITEM_LOCK_CHANGED, BAG_UPDATE_COOLDOWN
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    mod.active = true
    sortReverse = mod.db.sortReverse and true or false
    sortMode = mod.db.sortMode or "blizzard"
    useCategories = (mod.db.useCategories ~= false)
    hideEmpty = (mod.db.hideEmpty ~= false)
    viewMode = mod.db.viewMode or "all"
    if viewMode ~= "all" and viewMode ~= "onebag" and viewMode ~= "multibag" then viewMode = "all" end
    sidebarExpanded = (mod.db.sidebarCollapsed == false)
    sidebarWidth = sidebarExpanded and SIDEBAR_W_EXPANDED or SIDEBAR_W_COLLAPSED
    selectedCategory = "all"
    -- Phase 3c: mirror the (profile-linked) custom-category state; these are live
    -- references, so writes through them persist automatically.
    mod.db.customCats      = mod.db.customCats      or {}
    mod.db.itemAssignments = mod.db.itemAssignments or {}
    mod.db.disabledCats    = mod.db.disabledCats    or {}
    customCats      = mod.db.customCats
    itemAssignments = mod.db.itemAssignments
    disabledCats    = mod.db.disabledCats
    -- STAGE-2: pinned is profile-scoped (live reference like the others).
    mod.db.pinnedItems = mod.db.pinnedItems or {}
    pinnedItems = mod.db.pinnedItems
    -- STAGE-3: groups are profile-scoped; live reference so writes persist.
    mod.db.groups = mod.db.groups or {}
    groups = mod.db.groups
    if mod.db.showRecent == nil then mod.db.showRecent = true end
    if mod.db.recentCap  == nil then mod.db.recentCap  = 20 end
    -- STAGE-2: recent is session-scoped. Clear the runtime set + baseline and force a
    -- re-prime on the next BAG_UPDATE_DELAYED, so whatever is already in bags at login
    -- is treated as "already seen", not new.
    if wipe then wipe(recentItems); wipe(recentOrder); wipe(recentBaseline)
    else recentItems, recentOrder, recentBaseline = {}, {}, {} end
    recentPrimed = false
    lastLayoutSig = nil   -- force a scroll-reset on the first layout of this session
    rebuildCustomLookup()
    rebuildGroupLookup()   -- STAGE-3: AFTER rebuildCustomLookup (sanitizer needs customCatByKey)
    installHooks()
    if not _eventsWired then
        _eventsWired = true
        for _, ev in ipairs({
            "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
            "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY", "PLAYER_REGEN_ENABLED",
        }) do
            ns:RegisterEvent(ev, onEvent)
        end
    end
    preallocate()
    hideBlizzardBags()   -- out-of-combat now; deferred to PLAYER_REGEN_ENABLED if in combat
    if ns.BankOnEnable then ns.BankOnEnable() end   -- Phase 4: re-suppress default bank on live re-enable
end

function mod:OnDisable()
    mod.active = false
    if bagFrame then bagFrame:Hide() end
    restoreBlizzardBags()   -- give Blizzard's default bags back
    if ns.BankOnDisable then ns.BankOnDisable() end   -- Phase 4: hide bank window + restore default bank
    -- open/close hooks stay installed but no-op via the active gate; no global
    -- was ever replaced, so the default bags work again after this.
end

-- =========================================================
-- Phase 3c: name-entry popups + right-click category menu (Classic-safe).
-- StaticPopup is core FrameXML on 20505 + 11508; ns:ShowPopupMenu is our own
-- menu helper (Core/PopupMenu.lua) -- no MenuUtil/EasyMenu dependency.
-- =========================================================
StaticPopupDialogs["VCUI_BAGS_NEW_CATEGORY"] = {
    text = L["New category name:"],
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = 32,
    OnShow = function(self)
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
        if eb then eb:SetText(""); eb:SetFocus() end
    end,
    OnAccept = function(self)
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
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
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
        if eb then eb:SetText((data and data.current) or ""); eb:HighlightText(); eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
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
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
        if eb then eb:SetText(""); eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
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
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
        if eb then eb:SetText((data and data.current) or ""); eb:HighlightText(); eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
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

function promptNewCategory()
    StaticPopup_Show("VCUI_BAGS_NEW_CATEGORY")
end

-- catKey is optional: when set, the freshly created group immediately adopts it
-- (used by the "New group..." entry in the assign-to-group menu).
function promptNewGroup(catKey)
    StaticPopup_Show("VCUI_BAGS_NEW_GROUP", nil, nil, catKey and { catKey = catKey } or nil)
end

function showCategoryMenu(anchorRow, key)
    if not key or key == "__unassign" then return end
    if key == "pinned" or key == "recent" then return end   -- STAGE-2 pseudo-cats: no rename/move/delete
    local isCustom = customCatByKey[key] ~= nil
    local grouped  = groupOfCat[key] ~= nil                 -- STAGE-3
    local entries = {
        { title = true, text = catName(key) },
        { text = L["Rename"], func = function()
            StaticPopup_Show("VCUI_BAGS_RENAME_CATEGORY", nil, nil, { key = key, current = catName(key) })
        end },
        -- STAGE-3: inside a group, up/down moves within the group's own cats order
        { text = L["Move up"],   func = function()
            if groupOfCat[key] then moveCatWithinGroup(key, -1) else moveCategory(key, -1) end
        end },
        { text = L["Move down"], func = function()
            if groupOfCat[key] then moveCatWithinGroup(key,  1) else moveCategory(key,  1) end
        end },
        { separator = true },
        -- STAGE-3: chained menu (our popup menu is a flat list; the first menu hides
        -- itself on click, then the second opens on the same anchor)
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

-- STAGE-3: second-stage menu listing every group (checkmark = current), plus
-- "New group..." and, when grouped, "Remove from group".
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

-- STAGE-3: right-click menu for a group header (grid) or group row (sidebar).
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

-- =========================================================
-- Options
-- =========================================================
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
    -- STAGE-3: groups (per-group management is right-click-only; options stay light)
    table.insert(items, {
        type = "button", label = L["New group..."], width = 200,
        onClick = function() if promptNewGroup then promptNewGroup() end end,
    })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaTip: right-click a category to add it to a group; click a group header to collapse or expand it; right-click a group header to rename, move or delete it.|r"] })
    -- STAGE-2: pinned/recent pseudo-category controls
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
    -- one toggle per built-in category to show/hide it (hidden ones reroute to Misc).
    -- pinned/recent are pseudo-categories with their own controls -> skip them here.
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
        type = "toggle", label = L["Show sidebar"],
        tooltip = L["A collapsible left panel for view modes and category filtering."],
        get = function() return not mod.db.sidebarCollapsed end,
        set = function(_, v)
            mod.db.sidebarCollapsed = not v
            sidebarExpanded = v and true or false
            if not v then selectedCategory = "all" end  -- don't strand a filter when hiding the sidebar
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
            if ns.BankRefresh then ns.BankRefresh() end   -- shared flag: repaint an open bank too
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
        end,
    })
    table.insert(items, {
        type = "slider", label = L["Item count text size"], min = 8, max = 16, step = 1,
        get = function() return mod.db.countFontSize end,
        set = function(_, v)
            mod.db.countFontSize = v
            if mod:IsOpen() then layout() end
            if ns.BankRefresh then ns.BankRefresh() end
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
            { value = "blizzard", text = L["Blizzard (category)"] },
            { value = "quality",  text = L["Quality"] },
            { value = "type",     text = L["Item type"] },
            { value = "name",     text = L["Name"] },
        },
        get = function() return mod.db.sortMode end,
        set = function(_, v) mod.db.sortMode = v; sortMode = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Reverse sort order"],
        tooltip = L["Sort in the opposite direction."],
        get = function() return mod.db.sortReverse end,
        set = function(_, v) mod.db.sortReverse = v; sortReverse = v and true or false end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, {
        type = "button", label = L["Reset bag position"], width = 200,
        onClick = function()
            if mod.mover and ns.MoverSetCenter then ns:MoverSetCenter(mod.mover, 0, 0) end
        end,
    })
    -- Phase 4: the bank window (Modules/Bank.lua) publishes its own option
    -- items; splice them in so bag + bank settings share one page.
    if ns.BankOptions then
        for _, it in ipairs(ns.BankOptions()) do table.insert(items, it) end
    end
    return items
end
