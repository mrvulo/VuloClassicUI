-- VuloClassicUI / Core / TalentOverrides
--
-- Named override groups: per-talent-group values for INDIVIDUAL settings inside
-- one profile, so a character who plays two builds does not need a duplicate
-- profile for the sake of a handful of differences.
--
-- MODEL
-- A GROUP is a named set of overrides. A talent group (the dual talent system's
-- 1 or 2) belongs to at most one override group; switching talents applies the
-- owning group's values. "Yourself" means no group is being edited -- the plain
-- profile values are live.
--
-- WHY NOT "SPECIALISATIONS": this client has none. What the talent globals do
-- and do not offer:
--   * GetActiveTalentGroup, GetTalentTabInfo and GetNumTalentTabs exist ONLY
--     inside Blizzard_DeprecatedSpecialization, behind the
--     `loadDeprecationFallbacks` CVar. They can be switched off today and
--     removed tomorrow, so nothing may depend on them ALONE -- but they do
--     answer today, so they are a fine second source behind the real one.
--   * The real API is C_SpecializationInfo. Capability is what we test for,
--     never the client version.
--
-- CORRECTED 28.07.2026: this comment used to claim GetNumTalentGroups did not
-- exist at all, "verified against the unpacked client source". It exists and it
-- answers -- `/loadout spec` printed 2 on a live client. Modules/Loadouts.lua
-- had its fallback removed on the strength of that wrong reading, which would
-- have offered a second talent group to characters who never bought one.
-- LESSON: when a claim about the client can be settled by asking the running
-- game, ask the game. A source reading is evidence, not proof.
--
-- HOW A SETTING IS IDENTIFIED
-- Our options are not paths. A module hands out { get = fn, set = fn } closures
-- and what they write is the module's business, so there is no key to store.
-- What IS stable is the option's place in its page: module, tab and label --
-- the label being an English locale key, not a translation. That triple is the
-- id.
--
-- CAPTURING
-- Every option a page builds passes through UI/OptionsBuilder, which wraps `set`
-- while a group is being edited. The wrapper does not read the written value out
-- of the call: setters take (self, value) but a colour swatch takes three, and
-- guessing there would store nonsense. It calls the ORIGINAL setter first and
-- then reads the value back through the option's own `get`.
--
-- APPLYING
-- On a talent switch the stored ids are grouped by module and tab, GetOptions is
-- called once per pair, and each matching item's `set` is invoked -- the same
-- path a click takes, so every refresh the module does on a change happens too.
local _, ns = ...
local L = ns.L

local SEP = "\031"   -- unit separator: cannot occur in a module key or a label
local SI  = _G.C_SpecializationInfo

-- Far above anything a tree can hold, far below an icon file id. See the note on
-- ns:DominantTalentTree for why a plain "is it a number" test was not enough.
local MAX_TREE_POINTS = 100

-- =========================================================================
-- The axis
-- =========================================================================

function ns:HasTalentGroups()
    return (SI and SI.GetActiveSpecGroup) and true or false
end

function ns:ActiveTalentGroup()
    if SI and SI.GetActiveSpecGroup then
        local ok, g = pcall(SI.GetActiveSpecGroup)
        if ok and type(g) == "number" and g > 0 then return g end
    end
    return 1
end

-- Deliberately NOT falling back to GetTalentTabInfo. Measured on a live client
-- (a shaman, talent group 1), the deprecated shim answers:
--     261, "Elementar", 136048, 0, "ShamanElementalCombat", 0, true
-- against the original classic (name, iconTexture, pointsSpent, background, ...).
-- A spec id is prepended, so every slot moves one to the right -- and slot 3,
-- which the original filled with the point count, now holds the ICON FILE ID.
--
-- That is worse than a wrong label. 136048 is a number, so a type check waves it
-- through, and "the tree with the most points" becomes "the tree with the
-- largest texture id" -- a stable, plausible, entirely wrong answer. Hence the
-- range check below: a point count is small, a file id is not.
--
-- Returns INDEX, NAME of the tree holding the most points in that group, or nil
-- while talent data is not loaded. Two callers want two halves of this: a label
-- wants the name, a module deciding "is this a melee build" wants the index, and
-- both used to walk the trees themselves with their own idea of which return
-- slot holds the point count -- which is the very thing that went wrong.
--
-- The index is the class's tree order, the same 1..3 the talent frame shows.
function ns:DominantTalentTree(group)
    if not (SI and SI.GetSpecializationInfo and UnitClass) then return nil end

    local classID = select(3, UnitClass("player"))
    if not classID or not SI.GetNumSpecializationsForClassID then return nil end
    local okN, numTrees = pcall(SI.GetNumSpecializationsForClassID, classID)
    if not okN or type(numTrees) ~= "number" then return nil end

    local bestIdx, bestName, bestPoints
    for i = 1, numTrees do
        -- returns: specId, name, description, icon, role, primaryStat, pointsSpent, ...
        local ok, _, name, _, _, _, _, points =
            pcall(SI.GetSpecializationInfo, i, false, false, nil, nil, group)
        -- No talent tree in this game holds anything like a hundred points. The
        -- guard is not about this call being wrong -- it is about the next person
        -- reading a neighbouring slot by accident, which has now happened twice.
        -- An icon file id fails it; a point count cannot.
        if type(points) == "number" and (points < 0 or points > MAX_TREE_POINTS) then
            points = nil
        end
        if ok and type(points) == "number" and (not bestPoints or points > bestPoints) then
            bestPoints, bestIdx = points, i
            bestName = (type(name) == "string" and name ~= "") and name or nil
        end
    end
    if bestPoints and bestPoints > 0 then return bestIdx, bestName end
    return nil
end

function ns:TalentGroupLabel(group)
    local _, name = ns:DominantTalentTree(group)
    return name
end

-- "Talent group 2 (Shadow)" where the tree is known, else just the number.
function ns:TalentGroupText(group)
    local label = ns:TalentGroupLabel(group)
    if label then return string.format(L["Talent group %d (%s)"], group, label) end
    return string.format(L["Talent group %d"], group)
end

-- =========================================================================
-- Store
-- =========================================================================

local function cards(create)
    local p = ns.db and ns.db.profile
    if not p then return nil end
    if not p.overrideGroups and create then p.overrideGroups = {} end
    return p.overrideGroups
end

function ns:OverrideGroups()
    return cards(false) or {}
end

function ns:OverrideGroup(id)
    local c = cards(false)
    return c and c[id] or nil
end

-- Ids are strings so they survive the saved-variables round trip unchanged and
-- can never collide with an array index.
function ns:CreateOverrideGroup(name)
    local c = cards(true)
    if not c then return nil end
    local n = 1
    while c["g" .. n] do n = n + 1 end
    local id = "g" .. n
    c[id] = { name = name or ("" .. n), members = {}, values = {} }
    return id
end

function ns:DeleteOverrideGroup(id)
    local c = cards(false)
    if not c or not c[id] then return end
    c[id] = nil
    if ns._ovEditing == id then ns:SetEditingOverrideGroup(nil) end
end

function ns:RenameOverrideGroup(id, name)
    local g = ns:OverrideGroup(id)
    if g and type(name) == "string" and name ~= "" then g.name = name end
end

-- A talent group belongs to at most ONE override group: two owners would make
-- the applied result depend on table order.
function ns:AssignTalentGroup(talentGroup, id)
    local c = cards(true)
    if not c then return end
    for gid, g in pairs(c) do
        if g.members then g.members[talentGroup] = nil end
        if gid == id then g.members = g.members or {}; g.members[talentGroup] = true end
    end
end

function ns:GroupForTalentGroup(talentGroup)
    for id, g in pairs(ns:OverrideGroups()) do
        if g.members and g.members[talentGroup] then return id, g end
    end
    return nil
end

function ns:CountOverrides(id)
    local g = ns:OverrideGroup(id)
    if not g or not g.values then return 0 end
    local n = 0
    for _ in pairs(g.values) do n = n + 1 end
    return n
end

function ns:ClearOverrides(id)
    local g = ns:OverrideGroup(id)
    if g then g.values = {} end
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

-- Used by the options builder to mark a row. Asks about the group that owns the
-- ACTIVE talent group, or the one being edited -- what is on screen right now.
function ns:HasOverride(_, id)
    if not id then return false end
    local editing = ns._ovEditing
    local gid = editing or ns:GroupForTalentGroup(ns:ActiveTalentGroup())
    local g = gid and ns:OverrideGroup(gid)
    return (g and g.values and g.values[id] ~= nil) and true or false
end

-- =========================================================================
-- Editing mode
-- =========================================================================

function ns:EditingOverrideGroup()
    return ns._ovEditing
end

function ns:SetEditingOverrideGroup(id)
    ns._ovEditing = id
    if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
    if ns.UI and ns.UI.RefreshOverrideButton then ns.UI:RefreshOverrideButton() end
end

-- Called by the setter wrapper in UI/OptionsBuilder, after the real setter ran.
function ns:NoteOverrideWrite(id, getter)
    local gid = ns._ovEditing
    if not gid or not id or type(getter) ~= "function" then return end
    local g = ns:OverrideGroup(gid)
    if not g then return end
    local ok, value = pcall(getter)
    if not ok then return end
    -- Tables would be stored by reference and then mutate underneath us.
    local t = type(value)
    if t ~= "number" and t ~= "string" and t ~= "boolean" then return end
    g.values = g.values or {}
    g.values[id] = value
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
function ns:ApplyOverrideGroup(id)
    local g = ns:OverrideGroup(id)
    if not g or not g.values then return 0 end

    local byPage = {}
    for oid, value in pairs(g.values) do
        local modKey, tabId, label = splitId(oid)
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
                        if pcall(it.set, nil, want) then applied = applied + 1 end
                    end
                end)
            end
        end
    end
    return applied
end

function ns:ApplyOverrides(talentGroup)
    local id = ns:GroupForTalentGroup(talentGroup or ns:ActiveTalentGroup())
    if not id then return 0 end
    return ns:ApplyOverrideGroup(id)
end

-- =========================================================================
-- The picker
--
-- Lives here rather than in UI/ because it is one call into the shared popup
-- menu, not a window: "Yourself" plus the saved groups plus a way to add one.
-- Picking a group enters editing mode, so the whole suite is the editor and the
-- real widgets do the editing -- there is no second, lesser copy of the options.
-- =========================================================================

-- Registered inside OnLocaleReady: the dialog carries L[...] strings, and at
-- file scope those resolve before the saved language override is readable and
-- would bake in the client language. StaticPopupDialogs is a table the client
-- always provides -- we add to it, never assign it.
ns.OnLocaleReady(function()
    StaticPopupDialogs["VCUI_OVERRIDE_GROUP_NEW"] = {
        text         = L["Name for the new group"],
        button1      = ACCEPT or "OK",
        button2      = CANCEL or "Cancel",
        hasEditBox   = true,
        maxLetters   = 32,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(self)
            local box  = self.editBox or (self.GetEditBox and self:GetEditBox())
            local name = box and box:GetText()
            if not name or name == "" then return end
            local id = ns:CreateOverrideGroup(name)
            if not id then return end
            -- A new group starts owning the talent group you are on: that is
            -- almost always why it is being created, and it can be moved later.
            ns:AssignTalentGroup(ns:ActiveTalentGroup(), id)
            ns:SetEditingOverrideGroup(id)
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            if parent and parent.OnAccept then parent.OnAccept(parent) end
            parent:Hide()
        end,
    }
end)

-- The default entry is the character themselves, so it says who that is rather
-- than "Yourself": the name in the class colour, the class beside it. Shared
-- with the toolbar button's tooltip so the two can never drift apart.
function ns:OverrideSelfLabel()
    local name = UnitName and UnitName("player")
    if not name then return L["Yourself"] end

    local locClass, token = UnitClass("player")
    local colored = name
    local c = token and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    if c and c.colorStr then
        colored = "|c" .. c.colorStr .. name .. "|r"
    elseif c then
        colored = string.format("|cff%02x%02x%02x%s|r", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255, name)
    end
    if locClass and locClass ~= "" then
        return colored .. "  |cff888888" .. locClass .. "|r"
    end
    return colored
end

function ns:ShowOverrideMenu(anchor)
    if not ns.ShowPopupMenu then return end
    local entries = {}
    local editing = ns._ovEditing
    local active  = ns:ActiveTalentGroup()

    entries[#entries + 1] = { title = true, text = L["Editing as"] }

    entries[#entries + 1] = {
        text    = ns:OverrideSelfLabel(),
        checked = function() return ns._ovEditing == nil end,
        func    = function() ns:SetEditingOverrideGroup(nil) end,
    }

    local any = false
    for id, g in pairs(ns:OverrideGroups()) do
        any = true
        local owns = g.members and g.members[active]
        entries[#entries + 1] = {
            -- Plain words, no symbol: a bullet or a dot renders as an empty box
            -- in the game font, which is exactly what it did here.
            text    = g.name .. (owns and ("  |cff9b6cff" .. L["active"] .. "|r") or "")
                      .. string.format("  |cff666666(%d)|r", ns:CountOverrides(id)),
            checked = function() return ns._ovEditing == id end,
            func    = function()
                -- Picking a group also makes it own the talent group you are on,
                -- otherwise you could record into something that never applies.
                ns:AssignTalentGroup(ns:ActiveTalentGroup(), id)
                ns:SetEditingOverrideGroup(id)
            end,
        }
    end
    if any then entries[#entries + 1] = { separator = true } end

    entries[#entries + 1] = {
        text = L["New group..."],
        func = function() StaticPopup_Show("VCUI_OVERRIDE_GROUP_NEW") end,
    }
    entries[#entries + 1] = {
        text = L["Manage groups..."],
        func = function()
            if ns.UI and ns.UI.ShowModulePage then ns.UI:ShowModulePage("profiles") end
        end,
    }

    ns:ShowPopupMenu(entries, anchor)
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
