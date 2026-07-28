-- VuloClassicUI / Core / TalentOverrides
--
-- Per-talent-group values for INDIVIDUAL settings inside one profile, so a
-- character who raids as one build and does something else as the other does
-- not need a duplicate profile for the sake of a handful of differences.
--
-- Why not "specialisations": this client has none. The axis that actually
-- switches at runtime is the talent group of the dual talent system, so that is
-- what an override hangs on; the dominant talent tree only supplies its label.
--
-- HOW A SETTING IS IDENTIFIED
-- Our options are not paths. A module hands out { get = fn, set = fn } closures
-- and what they write is the module's business, so there is no key to store.
-- What IS stable is the option's place in its page: module, tab and label -- the
-- label being an English locale key, not a translation. That triple is the id.
--
-- CAPTURING
-- Every option a page builds passes through UI/OptionsBuilder, which wraps `set`
-- while an override group is being edited. The wrapper does not try to read the
-- written value out of the call: setters take (self, value) but a colour swatch
-- takes three, and guessing there would store nonsense. It calls the ORIGINAL
-- setter first and then reads the value back through the option's own `get`.
-- Whatever the module decided to store is what gets captured, by definition.
--
-- APPLYING
-- On a talent switch the stored ids are grouped by module and tab, GetOptions is
-- called once per pair, and each matching item's `set` is invoked -- the same
-- path a click takes, so every refresh the module does on a change happens too.
local _, ns = ...

local SEP = "\031"   -- unit separator: cannot occur in a module key or a label

-- =========================================================================
-- The axis
-- =========================================================================

function ns:ActiveTalentGroup()
    if GetActiveTalentGroup then
        local ok, g = pcall(GetActiveTalentGroup)
        if ok and type(g) == "number" then return g end
    end
    return 1
end

function ns:NumTalentGroups()
    if GetNumTalentGroups then
        local ok, n = pcall(GetNumTalentGroups)
        if ok and type(n) == "number" and n > 0 then return n end
    end
    return 1
end

-- Name of the tree with the most points in that group -- "Shadow", "Holy".
-- Nil while the talent data is not loaded yet; callers fall back to a number.
function ns:TalentGroupLabel(group)
    if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
    local best, bestPoints
    for tab = 1, (GetNumTalentTabs() or 0) do
        local ok, name, _, points = pcall(GetTalentTabInfo, tab, false, false, group)
        if ok and type(points) == "number" and (not bestPoints or points > bestPoints) then
            bestPoints = points
            best = (type(name) == "string" and name ~= "") and name or nil
        end
    end
    if bestPoints and bestPoints > 0 then return best end
    return nil
end

-- =========================================================================
-- Store
-- =========================================================================

local function store(create)
    local p = ns.db and ns.db.profile
    if not p then return nil end
    if not p.talentOverrides and create then p.talentOverrides = {} end
    return p.talentOverrides
end

local function groupStore(group, create)
    local s = store(create)
    if not s then return nil end
    if not s[group] and create then s[group] = {} end
    return s[group]
end

function ns:OverrideId(modKey, tabId, label)
    if not modKey or not label then return nil end
    return modKey .. SEP .. (tabId or "") .. SEP .. label
end

local function splitId(id)
    local a, b, c = id:match("^(.-)" .. SEP .. "(.-)" .. SEP .. "(.+)$")
    if not a then return nil end
    return a, (b ~= "" and b or nil), c
end

function ns:CountOverrides(group)
    local g = groupStore(group, false)
    if not g then return 0 end
    local n = 0
    for _ in pairs(g) do n = n + 1 end
    return n
end

function ns:ClearOverrides(group)
    local s = store(false)
    if s then s[group] = nil end
end

function ns:HasOverride(group, id)
    local g = groupStore(group, false)
    return (g and id and g[id] ~= nil) and true or false
end

-- =========================================================================
-- Editing mode
-- =========================================================================

-- ns._ovEditing is the group currently being recorded into, or nil.
function ns:EditingOverrideGroup()
    return ns._ovEditing
end

function ns:SetEditingOverrideGroup(group)
    ns._ovEditing = group
    if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
end

-- Called by the setter wrapper in UI/OptionsBuilder, after the real setter ran.
function ns:NoteOverrideWrite(id, getter)
    local group = ns._ovEditing
    if not group or not id or type(getter) ~= "function" then return end
    local ok, value = pcall(getter)
    if not ok then return end
    -- Tables would be stored by reference and then mutate underneath us.
    local t = type(value)
    if t ~= "number" and t ~= "string" and t ~= "boolean" then return end
    local g = groupStore(group, true)
    if g then g[id] = value end
end

-- =========================================================================
-- Applying
-- =========================================================================

local function walkItems(items, fn)
    for _, it in ipairs(items or {}) do
        if type(it) == "table" then
            if it.items then walkItems(it.items, fn) end
            fn(it)
        end
    end
end

-- Grouped by module+tab so GetOptions runs once per page, not once per setting.
function ns:ApplyOverrides(group)
    local g = groupStore(group, false)
    if not g then return 0 end

    local byPage = {}
    for id, value in pairs(g) do
        local modKey, tabId, label = splitId(id)
        if modKey and ns.modules[modKey] then
            local pageKey = modKey .. SEP .. (tabId or "")
            local page = byPage[pageKey]
            if not page then
                page = { modKey = modKey, tabId = tabId, items = {} }
                byPage[pageKey] = page
            end
            page.items[label] = value
        end
    end

    local applied = 0
    for _, page in pairs(byPage) do
        local mod = ns.modules[page.modKey]
        if mod and mod.GetOptions then
            local ok, items = pcall(mod.GetOptions, mod, page.tabId)
            if ok and type(items) == "table" then
                walkItems(items, function(it)
                    local want = it.label and page.items[it.label]
                    -- nil means "not overridden"; false is a real stored value.
                    if want ~= nil and type(it.set) == "function" and it.type ~= "color" then
                        -- Every options widget calls set(self, value); the odd
                        -- one-argument setter belongs to the sidebar power
                        -- button, which is not built from an options item.
                        if pcall(it.set, nil, want) then applied = applied + 1 end
                    end
                end)
            end
        end
    end
    return applied
end

-- =========================================================================
-- Lifecycle
-- =========================================================================

local lastGroup

local function onTalentSwitch()
    local now = ns:ActiveTalentGroup()
    if now == lastGroup then return end
    lastGroup = now
    -- Leaving edit mode on a switch: what is being recorded belongs to the group
    -- that was active when recording started, and that is no longer this one.
    if ns._ovEditing then ns:SetEditingOverrideGroup(nil) end
    ns:ApplyOverrides(now)
end

ns:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", onTalentSwitch)
ns:RegisterEvent("PLAYER_TALENT_UPDATE", onTalentSwitch)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    lastGroup = ns:ActiveTalentGroup()
    ns:ApplyOverrides(lastGroup)
end)
