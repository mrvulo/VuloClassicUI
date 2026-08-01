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
        -- Measured, not assumed. Same shaman, talent group 2:
        --   261, "Elementar", "", 136048, nil, nil, 41, "ShamanElementalCombat"
        -- i.e. specId, name, description, icon, role, primaryStat, pointsSpent,
        -- background. Slot 7 is the count, and the deprecated shim is NOT this
        -- function passed through -- it drops description, role and primaryStat,
        -- which is exactly why its icon lands on the slot this one spends on the
        -- description. Two shapes, one name.
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

-- =========================================================================
-- Situations
--
-- The talent group was the only axis. It answers "which build am I", never
-- "where am I" -- and wanting bigger nameplates in a raid has nothing to do
-- with respeccing.
--
-- ONE situation is true at a time, deliberately. Overlapping conditions are
-- where this kind of feature gets expensive: the reference addon layers them
-- and needs ~8000 lines, with a comment in it about a conditional transition
-- that froze the client. A single value cannot contradict itself.
-- =========================================================================

local SITUATIONS = { "raid", "party", "arena", "pvp", "group", "solo" }
ns.OVERRIDE_SITUATIONS = SITUATIONS

function ns:SituationLabel(key)
    if key == "raid"  then return L["Raid instance"] end
    if key == "party" then return L["5-player instance"] end
    if key == "arena" then return L["Arena"] end
    if key == "pvp"   then return L["Battleground"] end
    -- Short on purpose: these are dropdown rows, and the instance kinds above
    -- are already checked first, so "in a group" can only mean "and not in an
    -- instance" by the time it is reached.
    if key == "group" then return L["In a group"] end
    if key == "solo"  then return L["Alone"] end
    return L["Everywhere"]
end

-- Instance type first, because being in a raid instance is also "in a group"
-- and the more specific answer is the useful one.
function ns:CurrentSituation()
    local inside, kind = false, nil
    if IsInInstance then
        local ok, a, b = pcall(IsInInstance)
        if ok then inside, kind = a, b end
    end
    if inside then
        if kind == "arena" then return "arena" end
        if kind == "pvp"   then return "pvp"   end
        if kind == "raid"  then return "raid"  end
        if kind == "party" then return "party" end
    end
    if IsInGroup and IsInGroup() then return "group" end
    if GetNumGroupMembers and (GetNumGroupMembers() or 0) > 0 then return "group" end
    return "solo"
end

function ns:OverrideGroupSituation(id)
    local g = ns:OverrideGroup(id)
    return g and g.situation or nil
end

function ns:SetOverrideGroupSituation(id, key)
    local g = ns:OverrideGroup(id)
    if not g then return false end
    if key == "" or key == nil then
        g.situation = nil
    else
        local ok = false
        for _, k in ipairs(SITUATIONS) do if k == key then ok = true; break end end
        if not ok then return false end
        g.situation = key
    end
    return true
end

-- =========================================================================
-- Group icons
--
-- The eight raid markers: present in every client since forever, distinct at a
-- glance, and the client already holds their names in RAID_TARGET_1..8 in the
-- player's language, so this costs no art and no translation. Two other places
-- in this addon draw them the same way.
-- =========================================================================

function ns:OverrideIconTexture(n)
    n = tonumber(n)
    if not n or n < 1 or n > 8 then return nil end
    return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n
end

function ns:OverrideIconLabel(n)
    n = tonumber(n)
    if not n or n < 1 or n > 8 then return L["No icon"] end
    return _G["RAID_TARGET_" .. n] or ("#" .. n)
end

-- Inline texture escape, for a menu line or a button caption.
function ns:OverrideIconMarkup(n, size)
    local tex = ns:OverrideIconTexture(n)
    if not tex then return "" end
    return "|T" .. tex .. ":" .. (size or 14) .. "|t "
end

function ns:OverrideGroupIcon(id)
    local g = ns:OverrideGroup(id)
    return g and tonumber(g.icon) or nil
end

function ns:SetOverrideGroupIcon(id, n)
    local g = ns:OverrideGroup(id)
    if not g then return false end
    n = tonumber(n)
    g.icon = (n and n >= 1 and n <= 8) and n or nil
    return true
end

-- =========================================================================
-- Which groups apply, and in what order
--
-- A group applies when EVERY filter it declares matches. One that declares
-- nothing never applies on its own -- it can still be edited, it simply has no
-- occasion to switch itself on, and saying so is better than guessing.
--
-- Order is by specificity, fewest filters first, so a group that names both a
-- build and a place lands ON TOP of one that only names the build. That is the
-- rule people already carry around from stylesheets, and it makes the outcome
-- readable instead of dependent on pairs().
-- =========================================================================
function ns:MatchingOverrideGroups(talentGroup, situation)
    talentGroup = talentGroup or ns:ActiveTalentGroup()
    situation   = situation   or ns:CurrentSituation()

    local out = {}
    for id, g in pairs(ns:OverrideGroups()) do
        local filters = 0
        local ok      = true
        local owns    = g.members and next(g.members) ~= nil
        if owns then
            filters = filters + 1
            if not g.members[talentGroup] then ok = false end
        end
        if g.situation then
            filters = filters + 1
            if g.situation ~= situation then ok = false end
        end
        if ok and filters > 0 then
            out[#out + 1] = { id = id, filters = filters }
        end
    end
    table.sort(out, function(a, b)
        if a.filters ~= b.filters then return a.filters < b.filters end
        return a.id < b.id            -- stable, so a re-apply lands the same way
    end)

    local ids = {}
    for i, e in ipairs(out) do ids[i] = e.id end
    return ids
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

-- Used by the options builder to mark a row. While editing, that one group is
-- what is on screen. Otherwise ANY group that currently applies counts -- a row
-- driven by the raid group is just as overridden as one driven by the build,
-- and marking only the build's would leave the other silently unmarked.
function ns:HasOverride(_, id)
    if not id then return false end
    if ns._ovEditing then
        local g = ns:OverrideGroup(ns._ovEditing)
        return (g and g.values and g.values[id] ~= nil) and true or false
    end
    for _, gid in ipairs(ns:MatchingOverrideGroups()) do
        local g = ns:OverrideGroup(gid)
        if g and g.values and g.values[id] ~= nil then return true end
    end
    return false
end

-- =========================================================================
-- Reading the list back
--
-- CountOverrides has always been able to say "12 settings overridden" and
-- nothing could say WHICH twelve. The only way to undo one was to forget all of
-- them, so a single mis-recorded value cost every other value with it.
--
-- The decomposition needed for this already existed: splitId, written for the
-- apply path. Everything below is that same step pointed at the screen instead
-- of at the setters.
-- =========================================================================

-- modKey/tabId/label are the STORED english keys. They are translated here and
-- only here, so what the row shows follows the player's language while the id
-- underneath never moves.
function ns:DescribeOverride(modKey, tabId, label)
    local m = ns.modules and ns.modules[modKey]
    local parts = { L[(m and m.name) or modKey] }
    if tabId and tabId ~= "" and m and m.tabs then
        for _, t in ipairs(m.tabs) do
            if t.id == tabId then
                parts[#parts + 1] = L[t.label]
                break
            end
        end
    end
    parts[#parts + 1] = L[label]
    return table.concat(parts, " > ")
end

function ns:OverrideValueText(v)
    local t = type(v)
    if t == "boolean" then return v and L["on"] or L["off"] end
    if t == "number" then
        -- Sliders store fractions; a raw 0.6499999999 in a list reads as noise.
        if v == math.floor(v) then return tostring(v) end
        return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
    end
    if t == "string" then return v end
    if t == "table" then
        -- The only table we store is a colour. Shown as its own hex digits in
        -- that colour, which needs no legend and no translation.
        local r, g, b = tonumber(v.r), tonumber(v.g), tonumber(v.b)
        if r and g and b then
            local hex = string.format("%02x%02x%02x",
                math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
            return "|cff" .. hex .. hex .. "|r"
        end
    end
    return "?"
end

-- Sorted by the READABLE path, not by the stored id: an id starts with the
-- module KEY ("nameplates") while the row shows the module NAME
-- ("Namensplaketten"). Sorting by one and displaying the other looks like no
-- order at all -- and in a translated client the two orders differ.
function ns:OverrideList(id)
    local g = ns:OverrideGroup(id)
    local out = {}
    if not g or not g.values then return out end
    for oid, value in pairs(g.values) do
        local modKey, tabId, label = splitId(oid)
        if modKey then
            out[#out + 1] = {
                id    = oid,
                value = value,
                text  = ns:DescribeOverride(modKey, tabId, label),
            }
        end
    end
    table.sort(out, function(a, b)
        if a.text == b.text then return a.id < b.id end   -- stable on collisions
        return a.text < b.text
    end)
    return out
end

function ns:RemoveOverride(id, oid)
    local g = ns:OverrideGroup(id)
    if not (g and g.values and oid) then return false end
    if g.values[oid] == nil then return false end
    g.values[oid] = nil
    return true
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
--
-- itemType is passed so the one table shape we accept -- a colour -- can be told
-- apart from a module handing back something we have no business storing.
function ns:NoteOverrideWrite(id, getter, itemType)
    local gid = ns._ovEditing
    if not gid or not id or type(getter) ~= "function" then return end
    local g = ns:OverrideGroup(gid)
    if not g then return end
    local ok, value = pcall(getter)
    if not ok then return end

    local t = type(value)
    if t == "table" then
        -- Colours were excluded entirely until now, which meant changing one
        -- while editing a group did NOTHING and said nothing about it. They are
        -- taken as a COPY of the three numbers, never the getter's table: half
        -- the modules replace that table on every write and the rest mutate it,
        -- so a stored reference would either go stale or track the profile --
        -- and an override that follows the profile is not an override.
        if itemType ~= "color" then return end
        local r, gg, b = tonumber(value.r), tonumber(value.g), tonumber(value.b)
        if not (r and gg and b) then return end
        value = { r = r, g = gg, b = b }
    elseif t ~= "number" and t ~= "string" and t ~= "boolean" then
        return
    end

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
            -- Behind the gear too: the CAPTURE side has descended subOptions
            -- since the Wanderer fix, so overrides on those rows were recorded
            -- and listed -- and then never replayed, because only this walk
            -- resolves them at apply time.
            if it.subOptions then walkItems(it.subOptions, fn) end
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
                    if want ~= nil and type(it.set) == "function" then
                        -- Two setter shapes, one loop: a colour takes (r, g, b)
                        -- and no self, everything else takes (self, value).
                        local ok
                        if it.type == "color" then
                            if type(want) == "table" then
                                ok = pcall(it.set, want.r, want.g, want.b)
                            end
                        else
                            ok = pcall(it.set, nil, want)
                        end
                        if ok then applied = applied + 1 end
                    end
                end)
            end
        end
    end
    return applied
end

-- Every matching group, least specific first, so the specific one has the last
-- word on any setting both of them name.
--
-- The guard is not theoretical. Applying runs module SETTERS, and a setter is
-- free to do anything -- including something that ends up back here. It cannot
-- happen through the controls this file adds (they carry noOverride and are
-- never recorded), but it is one flag against a class of freeze that is very
-- hard to read from a bug report.
function ns:ApplyOverrides(talentGroup, situation)
    if ns._ovApplying then return 0 end
    ns._ovApplying = true
    local n = 0
    local ok, err = pcall(function()
        for _, id in ipairs(ns:MatchingOverrideGroups(talentGroup, situation)) do
            n = n + ns:ApplyOverrideGroup(id)
        end
    end)
    ns._ovApplying = nil
    if not ok then ns:Debug("ApplyOverrides: %s", tostring(err)) end
    return n
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

    -- Which groups are live right now, so "active" means the same thing here as
    -- it does when the settings are applied.
    local live = {}
    for _, gid in ipairs(ns:MatchingOverrideGroups()) do live[gid] = true end

    local any = false
    for id, g in pairs(ns:OverrideGroups()) do
        any = true
        entries[#entries + 1] = {
            -- A raid marker as an inline texture. Plain BULLETS were the problem
            -- here once -- a dot renders as an empty box in the game font -- but
            -- a |T escape draws the real file and is safe.
            text    = ns:OverrideIconMarkup(g.icon)
                      .. g.name
                      .. (live[id] and ("  |cff9b6cff" .. L["active"] .. "|r") or "")
                      .. (g.situation and ("  |cff888888" .. ns:SituationLabel(g.situation) .. "|r") or "")
                      .. string.format("  |cff666666(%d)|r", ns:CountOverrides(id)),
            checked = function() return ns._ovEditing == id end,
            func    = function()
                -- Picking a group used to make it own the current talent group
                -- unconditionally, so that recording could not vanish into
                -- something that never applies. A group tied to a SITUATION
                -- already has its occasion, and forcing a build on top of it
                -- would quietly narrow it to that build.
                if not g.situation and not (g.members and next(g.members)) then
                    ns:AssignTalentGroup(ns:ActiveTalentGroup(), id)
                end
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

-- Situations change far more often than builds do, and the events that announce
-- them fire in bursts: GROUP_ROSTER_UPDATE alone goes off several times for one
-- person joining. So the trigger is the COMPUTED situation changing, not the
-- event -- most of those bursts resolve to the same word and stop here.
local lastSituation

local function applyNow()
    lastSituation = ns:CurrentSituation()
    lastGroup     = ns:ActiveTalentGroup()
    ns:ApplyOverrides(lastGroup, lastSituation)
end

local function onSituationMaybeChanged()
    local now = ns:CurrentSituation()
    if now == lastSituation then return end
    -- Setters reach into modules that own protected frames, so this waits.
    -- Zoning into a raid lands mid-combat often enough to matter.
    if ns:InCombat() then
        ns._ovPendingSituation = true
        return
    end
    lastSituation = now
    ns:ApplyOverrides(nil, now)
end

-- Deliberately only these three. PLAYER_DIFFICULTY_CHANGED would have fitted the
-- story, but it is a later-expansion event and I have no way to verify it exists
-- on this client from here -- and an event that never fires reads like a bug in
-- the feature. Zoning and the roster cover every situation this knows about.
ns:RegisterEvent("PLAYER_ENTERING_WORLD", applyNow)
ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", onSituationMaybeChanged)
ns:RegisterEvent("GROUP_ROSTER_UPDATE",   onSituationMaybeChanged)

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if not ns._ovPendingSituation then return end
    ns._ovPendingSituation = nil
    onSituationMaybeChanged()
end)
