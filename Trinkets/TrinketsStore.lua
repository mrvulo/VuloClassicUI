-- VuloClassicUI / Trinkets / Store: the three foreign SavedVariables, moved into ours.
--
-- WHAT THIS REPLACES
-- The vendored trinket window shipped with its own storage, declared in both
-- TOCs: TrinketsOptions (account) and TrinketsPerOptions + TrinketsQueue (per
-- character). Three more names in the global table and three more blocks in the
-- saved file that nothing of ours could see, back up, export or reset.
--
-- WHY THE ~260 ACCESS SITES ARE NOT TOUCHED
-- Measured first: every read and write of those three names happens INSIDE a
-- function, never at file scope. So the names do not have to go -- only what
-- they point AT. Bind them to tables in our own database before any of that
-- code runs and all 263 sites keep working, unchanged and unreviewed. Rewriting
-- them would have been 263 chances to introduce a typo into working code, for
-- no gain a player could see.
--
-- SCOPE IS DELIBERATELY UNCHANGED
-- Account stays account (ns.db.global), per character stays per character
-- (ns.db.char). Moving the options into the PROFILE would have been the more
-- ambitious answer -- they would join export, switching and per-class
-- assignment -- but it also changes where a setting lives for everyone who
-- already has one, and it needs a re-bind on every profile switch. That is a
-- second decision and it does not belong in the same step as moving the data.
--
-- THE TOC KEEPS DECLARING THEM, ON PURPOSE
-- A SavedVariable the TOC no longer lists is not loaded, so removing the three
-- names in the same version that migrates them would drop the very data the
-- migration reads. They stay declared for this release, which also leaves the
-- old blocks in the file as a backup. Removing them is a later, separate step.
local _, ns = ...

local ACCOUNT_KEY = "TrinketsOptions"
local CHAR_KEYS   = { perOptions = "TrinketsPerOptions", queue = "TrinketsQueue" }

-- Copy, never adopt: the table the client loaded belongs to the old
-- SavedVariable and is written back to it. Sharing it would tie the two
-- together and make the migration impossible to tell apart from a no-op.
local function copyInto(dst, src)
    if type(src) ~= "table" then return dst end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = copyInto({}, v)
        else
            dst[k] = v
        end
    end
    return dst
end

local function isEmpty(t)
    return type(t) ~= "table" or next(t) == nil
end

-- Runs from ns:InitDB, after ns.db.global and ns.db.char exist and before any
-- module is enabled -- which is the whole window there is: the trinket code
-- reads these names from OnEnable onwards.
function ns:BindTrinketStore()
    local g, c = ns.db and ns.db.global, ns.db and ns.db.char
    if not (g and c) then return end

    g.trinkets = g.trinkets or {}
    c.trinkets = c.trinkets or {}

    -- Account side. Guarded by its own flag rather than the schema counter: the
    -- flag says "this data has been taken over", which is the question, and it
    -- stays true for a player who later logs in on a second machine with an
    -- older file.
    if not g.trinketsMigrated then
        g.trinkets.options = copyInto(g.trinkets.options or {}, _G[ACCOUNT_KEY])
        g.trinketsMigrated = true
        if not isEmpty(g.trinkets.options) then
            ns.migrationNotes = ns.migrationNotes or {}
            ns.migrationNotes[#ns.migrationNotes + 1] =
                { ns.L["Trinket window settings now live in this addon's own database."] }
        end
    end
    g.trinkets.options = g.trinkets.options or {}

    -- Per character, with a per-character flag: the account schema counter runs
    -- once for the whole account, so the second character would never migrate.
    -- Same shape as MigrateDarkSkinPerChar.
    if not c.trinketsMigrated then
        for field, globalName in pairs(CHAR_KEYS) do
            c.trinkets[field] = copyInto(c.trinkets[field] or {}, _G[globalName])
        end
        c.trinketsMigrated = true
    end
    for field in pairs(CHAR_KEYS) do
        c.trinkets[field] = c.trinkets[field] or {}
    end

    -- The point of the exercise. From here the vendored code reads and writes
    -- our tables while still spelling them the way it always has.
    _G[ACCOUNT_KEY] = g.trinkets.options
    for field, globalName in pairs(CHAR_KEYS) do
        _G[globalName] = c.trinkets[field]
    end
end

-- Called by the window's own "reset to defaults", which used to nil the three
-- globals. That stopped working the moment they were bound: it would unbind the
-- names and leave our tables untouched, so everything came back on reload.
function ns:ResetTrinketStore()
    local g, c = ns.db and ns.db.global, ns.db and ns.db.char
    if g then g.trinkets = {} end
    if c then c.trinkets = {} end
    -- The migrated flags STAY SET. Clearing them would make the next login copy
    -- the old SavedVariable block straight back in -- it is still declared in
    -- the TOC for this release -- and the reset would quietly undo itself.
    _G[ACCOUNT_KEY] = nil
    for _, globalName in pairs(CHAR_KEYS) do _G[globalName] = nil end
end
