-- VuloClassicUI / Modules / Meter: combat meter engine. Counts damage,
-- healing, damage taken, interrupts, dispels and deaths per group member
-- (pets credited to their owner) in two live segments -- the running fight
-- and the overall total -- and hands the window a read-only view through
-- ns.Meter. Knows nothing about bars; those live in Modules/MeterWindow.lua
-- and attach through mod:WindowEnable().
-- No L here on purpose: the engine has no text of its own.
local _, ns = ...

local mod = ns:RegisterModule("meter", {
    name        = "Combat Meter",
    group       = "HUD",
    description = "Lightweight damage and healing meter: who did how much, per fight and overall. Left-click the title for mode and segment, mouse wheel on the title cycles modes, the padlock frees a window for dragging.",
    defaults    = {
        enabled         = true,
        barHeight       = 18,
        barGap          = 1,
        fontSize        = 11,
        texture         = "Atrocity",
        showRank        = true,
        showClassIcon   = true,
        showPerSecond   = true,
        showPercent     = false,
        highlightSelf   = true,
        tooltipRows     = 5,
        onlyInGroup     = false,
        hideInCombat    = false,
        hideOutOfCombat = false,
        hideDelay       = 10,
        resetOnNewGroup = true,
        historySize     = 10,   -- finished fights kept for the window menu; 0 = none
        reportRows      = 10,   -- lines a chat report carries below its header
        followRole      = false, -- window 1 opens on healing for a healing spec, damage otherwise
        -- One entry per window: { mode, segment, x, y, width, height, scale,
        -- unlocked }. Filled by the window file; empty means "one window".
        windows         = {},
    },
})

local GetTime             = GetTime
local UnitGUID            = UnitGUID
local UnitName            = UnitName
local UnitClass           = UnitClass
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsFeignDeath    = UnitIsFeignDeath
local UnitExists          = UnitExists
local UnitCanAttack       = UnitCanAttack
local IsInRaid            = IsInRaid
local IsInGroup           = IsInGroup
local GetNumGroupMembers  = GetNumGroupMembers
local wipe                = wipe
local pairs               = pairs
local type, tonumber      = type, tonumber

local Meter = {}
ns.Meter = Meter

-- Melee swings carry no spell id; the auto-attack spell gives them a name
-- and an icon from the game itself.
local MELEE_ID   = 6603
Meter.MELEE_ID   = MELEE_ID
local MAX_DEATHS = 20

------------------------------------------------------------------------
-- Group roster and pet owners
------------------------------------------------------------------------
-- roster[guid] = { unit, name, class }; only these (and their pets) count.
local roster = {}
-- owners[petGUID] = ownerGUID; filled from the group's pet units and from
-- SPELL_SUMMON, so totems, elementals and guardians credit their owner.
local owners = {}
local playerGUID

local PET_UNIT = { player = "pet" }
for i = 1, 4  do PET_UNIT["party" .. i] = "partypet" .. i end
for i = 1, 40 do PET_UNIT["raid"  .. i] = "raidpet"  .. i end

local function addUnit(unit)
    local guid = UnitGUID(unit)
    if not guid then return end
    local _, class = UnitClass(unit)
    local e = roster[guid]
    if not e then e = {}; roster[guid] = e end
    e.unit, e.name, e.class = unit, UnitName(unit) or "?", class
    local petUnit = PET_UNIT[unit]
    if petUnit then
        local petGUID = UnitGUID(petUnit)
        if petGUID then owners[petGUID] = guid end
    end
end

-- Rebuilt whole on every roster change. Segment entries copy name and class,
-- so a member who leaves mid-fight keeps their bar; only new events stop.
local function rebuildRoster()
    wipe(roster)
    addUnit("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do addUnit("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do addUnit("party" .. i) end
    end
end

local function groupKind()
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return "solo"
end

------------------------------------------------------------------------
-- Segments
------------------------------------------------------------------------
local function newSegment()
    return { title = nil, start = 0, duration = 0, players = {} }
end

local current               -- the running fight, nil outside combat
local last                  -- the last finished fight, shown until the next starts
local overall = newSegment() -- swapped for the saved table in OnEnable
-- Finished fights, newest first, capped by db.historySize. Session only: the
-- overall total is what survives a reload, the fight list is not worth the
-- saved-variable weight (per-spell tables for every member of every fight).
local history = {}
local dirty = false
local listener              -- window callback: fn("start" | "end" | "reset")

local function notify(what)
    if listener then listener(what) end
end

local function newPlayer(name, class)
    return { name = name, class = class,
             damage = 0, heal = 0, overheal = 0,
             taken = 0, interrupts = 0, dispels = 0, deaths = 0 }
end

-- Only called after resolve() confirmed roster[guid] exists.
local function entry(seg, guid)
    local p = seg.players[guid]
    if not p then
        local r = roster[guid]
        p = newPlayer(r.name, r.class)
        seg.players[guid] = p
    end
    return p
end

-- The per-spell tables are born on the first event of their kind for a
-- player, never per event: p.spells, p.heals, p.takenBy, p.kicks, p.purges.
local function bump(p, key, id, n)
    local t = p[key]
    if not t then
        t = {}
        p[key] = t
    end
    t[id] = (t[id] or 0) + n
end

-- Source GUID -> the roster GUID it counts for, or nil when nobody we track.
local function resolve(guid)
    if roster[guid] then return guid end
    local o = owners[guid]
    if o and roster[o] then return o end
    return nil
end

-- The overall total is written on the hot path together with the running
-- fight (two entries per event instead of a fold at the fight's end), so an
-- overall window moves during the fight and a crash mid-fight loses nothing.
local function pushDeath(p, rec)
    local log = p.deathLog
    if not log then
        log = {}
        p.deathLog = log
    end
    log[#log + 1] = rec
    if #log > MAX_DEATHS then table.remove(log, 1) end
end

------------------------------------------------------------------------
-- Public read interface (the window reads through this and never writes)
------------------------------------------------------------------------
-- "overall", a finished fight from the history (its table), or anything
-- else for the running fight. A history table that has since been trimmed
-- falls through to the running fight, so a window pinned to it degrades
-- instead of going blank.
function Meter:GetSegment(which)
    if which == "overall" then return overall end
    if type(which) == "table" then
        for i = 1, #history do
            if history[i] == which then return which end
        end
    end
    return current or last
end

function Meter:GetHistory() return history end

function Meter:HistoryIndex(seg)
    for i = 1, #history do
        if history[i] == seg then return i end
    end
    return nil
end

function Meter:Duration(seg)
    if not seg then return 0 end
    if seg == current then return GetTime() - seg.start end
    if seg == overall and current then
        -- the running fight is already counted in the overall's totals
        return (seg.duration or 0) + (GetTime() - current.start)
    end
    return seg.duration or 0
end

function Meter:IsDirty()     return dirty end
function Meter:ClearDirty()  dirty = false end
function Meter:InCombat()    return current ~= nil end
function Meter:SetListener(fn) listener = fn end
function Meter:PlayerGUID()  return playerGUID end

function Meter:Reset()
    wipe(overall.players)
    overall.duration = 0
    if current then
        wipe(current.players)
        current.start = GetTime()
    end
    last = nil
    wipe(history)
    -- owners stays: summoned pets keep their owner; resolve() already gates on roster.
    rebuildRoster()
    dirty = true
    notify("reset")
end

-- Later parts add their own subevent entries here.
Meter.HANDLERS = {}

------------------------------------------------------------------------
-- Threat: a live snapshot of the target's threat list, not a segment. The
-- window asks for it on threat events; the table is reused between calls.
------------------------------------------------------------------------
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
Meter.HAS_THREAT = UnitDetailedThreatSituation ~= nil

local threatSeg  = { title = nil, start = 0, duration = 0, players = {} }
local threatPool = {}   -- guid -> row table, so a raid does not mint 40 tables per tick

local function threatRow(guid, name, class)
    local p = threatPool[guid]
    if not p then
        p = { threat = 0, pct = 0, status = 0, tanking = false }
        threatPool[guid] = p
    end
    p.name, p.class = name, class
    return p
end

-- One row per group member and per pet that holds threat on the target;
-- pets wear their owner's class colour. threat is the raw value in whole
-- points (the API hands back hundredths), pct the share of the tank's.
local function threatUnit(unit, guid, name, class)
    local tanking, status, _, pct, value = UnitDetailedThreatSituation(unit, "target")
    if not value then return end
    local p = threatRow(guid, name, class)
    p.threat  = value / 100
    p.pct     = pct or 0
    p.status  = status or 0
    p.tanking = tanking and true or false
    threatSeg.players[guid] = p
end

function Meter:ThreatSnapshot()
    local players = threatSeg.players
    wipe(players)
    -- A friend or a corpse has no threat list; the title says "no target"
    -- rather than naming someone with an empty window under it.
    if not UnitDetailedThreatSituation or not UnitExists("target")
    or not UnitCanAttack("player", "target") then
        threatSeg.title = nil
        return threatSeg
    end
    threatSeg.title = UnitName("target")
    for guid, r in pairs(roster) do
        threatUnit(r.unit, guid, r.name, r.class)
        local petUnit = PET_UNIT[r.unit]
        if petUnit and UnitExists(petUnit) then
            local petGUID = UnitGUID(petUnit)
            if petGUID then
                threatUnit(petUnit, petGUID, UnitName(petUnit) or "?", r.class)
            end
        end
    end
    return threatSeg
end

function Meter:ThreatSegment() return threatSeg end

------------------------------------------------------------------------
-- Segment boundaries
------------------------------------------------------------------------
local CLGetInfo = CombatLogGetCurrentEventInfo
local waitTicker, clearChecks
local pendingReset = false
local kind                     -- "solo" | "party" | "raid", for resetOnNewGroup

local function stopWait()
    if waitTicker then
        ns:CancelTicker(waitTicker)
        waitTicker = nil
    end
end

local function closeSegment()
    if not current then return end
    stopWait()
    current.duration = GetTime() - current.start
    overall.duration = overall.duration + current.duration
    last, current = current, nil
    -- Into the history, newest first; the cap is read live so a lowered
    -- slider (0 included) trims on the next fight end without a reload. A
    -- fight nobody scored in (aggro that never connected) is not worth a
    -- menu line.
    local cap = tonumber(mod.db.historySize) or 0
    if cap > 0 and next(last.players) then table.insert(history, 1, last) end
    while #history > cap do table.remove(history) end
    if pendingReset then
        pendingReset = false
        Meter:Reset()
    end
    dirty = true
    notify("end")
end

-- Pets count too: a pet-only pull keeps the fight open, and a segment the log
-- opened for a pet does not churn open/close every second.
local function anyoneInCombat()
    for _, r in pairs(roster) do
        if UnitAffectingCombat(r.unit) then return true end
        local petUnit = PET_UNIT[r.unit]
        if petUnit and UnitAffectingCombat(petUnit) then return true end
    end
    return false
end

-- Runs only between our own PLAYER_REGEN_ENABLED and the group's last exit
-- from combat. Two clear checks in a row (about one second) close the fight.
local function waitTick()
    if anyoneInCombat() then
        clearChecks = 0
        return
    end
    clearChecks = clearChecks + 1
    if clearChecks >= 2 then closeSegment() end
end

local function beginWait()
    if not current or waitTicker then return end
    clearChecks = 0
    waitTicker = ns:AddTicker(0.5, waitTick, nil, "meter-wait")
end

local function openSegment(title)
    if current then return end
    current = newSegment()
    current.start = GetTime()
    current.title = title
    dirty = true
    notify("start")
    -- Opened by the log while we stand outside combat (a healer at the pull):
    -- no PLAYER_REGEN_ENABLED will ever come for us, so the wait starts now.
    if not UnitAffectingCombat("player") then beginWait() end
end

local function onRegenDisabled()
    stopWait()
    openSegment(nil)
end

local function onRegenEnabled()
    beginWait()
end

-- ENCOUNTER_START(encounterID, encounterName, difficultyID, groupSize)
local function onEncounterStart(_, _, name)
    closeSegment()
    openSegment(name)
end

local function onEncounterEnd()
    closeSegment()
end

local function onRoster()
    rebuildRoster()
    local k = groupKind()
    if k ~= kind then
        -- Solo -> group and party -> raid start a fresh overall; a member
        -- joining or leaving, or a raid shrinking to a party, does not.
        -- Mid-fight the reset waits for the end.
        local upgrade = (kind == "solo" and k ~= "solo") or (kind == "party" and k == "raid")
        if kind and upgrade and mod.db.resetOnNewGroup then
            if current then pendingReset = true else Meter:Reset() end
        end
        kind = k
        local cdb = VuloClassicUICharDB
        if cdb and cdb.meter then cdb.meter.kind = k end
    end
end

-- UNIT_PET(unit): the pet of a group unit changed.
local function onUnitPet(_, unit)
    local petUnit = PET_UNIT[unit]
    if not petUnit then return end
    local guid = UnitGUID(unit)
    if not (guid and roster[guid]) then return end
    local petGUID = UnitGUID(petUnit)
    if petGUID then owners[petGUID] = guid end
end

------------------------------------------------------------------------
-- Combat log reader: one CombatLogGetCurrentEventInfo per firing, one table
-- lookup per subevent, no allocation on the hot path.
------------------------------------------------------------------------
local HANDLERS = Meter.HANDLERS

-- Every counter lands in the running fight AND in the overall; the per-target
-- table (dstName) feeds the tooltip's target block.
local function addDamage(src, amount, spellId, dstName)
    if not amount or amount <= 0 then return end
    local owner = resolve(src)
    if not owner then return end
    if not current then
        -- Residual ticks after a fight closed (a DoT on a dead boss) must not
        -- open a fresh segment: the log opens a fight only while someone fights.
        if not anyoneInCombat() then return end
        openSegment(nil)
    end
    local p = entry(current, owner)
    local o = entry(overall, owner)
    p.damage = p.damage + amount
    o.damage = o.damage + amount
    bump(p, "spells", spellId, amount)
    bump(o, "spells", spellId, amount)
    if dstName then
        bump(p, "targets", dstName, amount)
        bump(o, "targets", dstName, amount)
    end
    dirty = true
end

-- Damage landing on a group member (players only, never their pets). The
-- last hit stays on the entry so a death can name its killing blow. Taking
-- damage never opens a fight; PLAYER_REGEN_DISABLED already did.
local function addTaken(dst, srcName, amount, spellId)
    if not current or not amount or amount <= 0 then return end
    if not roster[dst] then return end
    local p = entry(current, dst)
    local o = entry(overall, dst)
    p.taken = p.taken + amount
    o.taken = o.taken + amount
    bump(p, "takenBy", spellId, amount)
    bump(o, "takenBy", spellId, amount)
    p.lastSpell, p.lastAmount, p.lastSrc = spellId, amount, srcName
    dirty = true
end

-- SWING_DAMAGE: amount is field 12. Spell-prefixed subevents carry spellId,
-- spellName, spellSchool in 12-14 and amount in 15.
HANDLERS.SWING_DAMAGE = function(src, srcName, dst, a12, _, _, _, dstName)
    addDamage(src, a12, MELEE_ID, dstName)
    addTaken(dst, srcName, a12, MELEE_ID)
end
local function spellDamage(src, srcName, dst, a12, a15, _, _, dstName)
    addDamage(src, a15, a12, dstName)
    addTaken(dst, srcName, a15, a12)
end
HANDLERS.RANGE_DAMAGE          = spellDamage
HANDLERS.SPELL_DAMAGE          = spellDamage
HANDLERS.SPELL_PERIODIC_DAMAGE = spellDamage
HANDLERS.DAMAGE_SHIELD         = spellDamage
HANDLERS.DAMAGE_SPLIT          = spellDamage

-- Healing never opens a fight (pre-pull heals are not combat); field 16 is
-- overhealing. The per-spell and per-target tables hold effective healing,
-- like the bar.
local function spellHeal(src, _, _, a12, a15, a16, _, dstName)
    if not current or not a15 then return end
    local owner = resolve(src)
    if not owner then return end
    local p = entry(current, owner)
    local o = entry(overall, owner)
    a16 = a16 or 0
    local eff = a15 - a16
    p.heal     = p.heal + a15
    o.heal     = o.heal + a15
    p.overheal = p.overheal + a16
    o.overheal = o.overheal + a16
    bump(p, "heals", a12, eff)
    bump(o, "heals", a12, eff)
    if dstName then
        bump(p, "healed", dstName, eff)
        bump(o, "healed", dstName, eff)
    end
    dirty = true
end
HANDLERS.SPELL_HEAL          = spellHeal
HANDLERS.SPELL_PERIODIC_HEAL = spellHeal

-- SPELL_INTERRUPT / SPELL_DISPEL / SPELL_STOLEN: 12-14 is our spell, 15-17
-- the spell we stopped or the aura we removed.
local function countFor(src, key, counter, a15)
    if not current then return end
    local owner = resolve(src)
    if not owner then return end
    local p = entry(current, owner)
    local o = entry(overall, owner)
    p[counter] = p[counter] + 1
    o[counter] = o[counter] + 1
    bump(p, key, a15 or 0, 1)
    bump(o, key, a15 or 0, 1)
    dirty = true
end
HANDLERS.SPELL_INTERRUPT = function(src, _, _, _, a15) countFor(src, "kicks",  "interrupts", a15) end
HANDLERS.SPELL_DISPEL    = function(src, _, _, _, a15) countFor(src, "purges", "dispels",    a15) end
HANDLERS.SPELL_STOLEN    = HANDLERS.SPELL_DISPEL

-- UNIT_DIED: the dead unit is the destination. A hunter feigning death fires
-- the same subevent, and the unit flag tells the two apart.
HANDLERS.UNIT_DIED = function(_, _, dst)
    if not current then return end
    local r = roster[dst]
    if not r or UnitIsFeignDeath(r.unit) then return end
    local p = entry(current, dst)
    local o = entry(overall, dst)
    p.deaths = p.deaths + 1
    o.deaths = o.deaths + 1
    local rec = { t = GetTime() - current.start,
                  spell = p.lastSpell, amount = p.lastAmount, src = p.lastSrc }
    pushDeath(p, rec)
    pushDeath(o, rec)
    dirty = true
end

HANDLERS.SPELL_SUMMON = function(src, _, dst)
    if dst and roster[src] then owners[dst] = src end
end

-- ENVIRONMENTAL_DAMAGE: no source, field 12 is the kind ("Falling", "Lava"...),
-- field 13 the amount. Counted as damage taken under the kind itself, so a
-- fall shows up in the breakdown and can be the killing blow.
HANDLERS.ENVIRONMENTAL_DAMAGE = function(_, _, dst, a12, _, _, a13)
    if type(a12) == "string" then addTaken(dst, nil, a13, a12) end
end

local function onCLEU()
    local _, sub, _, src, srcName, _, _, dst, dstName, _, _, a12, a13, _, a15, a16 = CLGetInfo()
    local h = HANDLERS[sub]
    if h then h(src, srcName, dst, a12, a15, a16, a13, dstName) end
end

function mod:EngineEnable()
    -- Seeded from the saved kind: at ADDON_LOADED on a fresh login the client
    -- does not know the group yet, and "solo -> raid" would wipe the overall.
    local cdb = VuloClassicUICharDB
    kind = (cdb and cdb.meter and cdb.meter.kind) or groupKind()
    self:RegisterEvent("GROUP_ROSTER_UPDATE",         onRoster)
    self:RegisterEvent("PLAYER_ENTERING_WORLD",       onRoster)
    self:RegisterEvent("UNIT_PET",                    onUnitPet)
    self:RegisterEvent("PLAYER_REGEN_DISABLED",       onRegenDisabled)
    self:RegisterEvent("PLAYER_REGEN_ENABLED",        onRegenEnabled)
    self:RegisterEvent("ENCOUNTER_START",             onEncounterStart)
    self:RegisterEvent("ENCOUNTER_END",               onEncounterEnd)
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    -- A reload or logout mid-fight: the counters are already in the overall,
    -- the fight's duration is not until it closes. Close it here, or the saved
    -- overall carries the damage of that fight with none of its seconds and
    -- overstates every per-second value after the reload.
    self:RegisterEvent("PLAYER_LOGOUT", closeSegment)
end

function mod:EngineDisable()
    closeSegment()
    stopWait()
end

------------------------------------------------------------------------
-- Enable / disable
------------------------------------------------------------------------
function mod:OnEnable()
    playerGUID = UnitGUID("player")
    local cdb = VuloClassicUICharDB
    if cdb then
        cdb.meter = cdb.meter or {}
        local saved = cdb.meter.overall
        if type(saved) ~= "table" then
            saved = newSegment()
            cdb.meter.overall = saved
        end
        saved.players  = saved.players or {}
        saved.duration = tonumber(saved.duration) or 0
        -- Entries saved by part 1 lack the new counters; fill them once.
        for _, p in pairs(saved.players) do
            p.taken      = p.taken      or 0
            p.interrupts = p.interrupts or 0
            p.dispels    = p.dispels    or 0
            p.deaths     = p.deaths     or 0
        end
        overall = saved
    end
    rebuildRoster()
    if self.EngineEnable then self:EngineEnable() end
    if self.WindowEnable then self:WindowEnable() end
end

function mod:OnDisable()
    if self.EngineDisable then self:EngineDisable() end
    if self.WindowDisable then self:WindowDisable() end
end
