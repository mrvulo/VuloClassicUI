-- VuloClassicUI / Modules / Meter: combat meter engine. Counts damage and
-- healing per group member (pets credited to their owner) in two live
-- segments -- the running fight and the overall total -- and hands the window
-- a read-only view through ns.Meter. Knows nothing about bars; those live in
-- Modules/MeterWindow.lua and attach through mod:WindowEnable().
-- No L here on purpose: the engine has no text of its own.
local _, ns = ...

local mod = ns:RegisterModule("meter", {
    name        = "Combat Meter",
    group       = "HUD",
    description = "Lightweight damage and healing meter: who did how much, per fight and overall. Left-click the title for mode and segment, mouse wheel on the title cycles modes, right-drag the title to move.",
    defaults    = {
        enabled         = true,
        width           = 220,
        height          = 160,
        barHeight       = 18,
        barGap          = 1,
        fontSize        = 11,
        texture         = "Atrocity",
        scale           = 1.0,
        showRank        = true,
        showPerSecond   = true,
        showPercent     = true,
        highlightSelf   = true,
        onlyInGroup     = false,
        hideInCombat    = false,
        hideOutOfCombat = false,
        hideDelay       = 10,
        defaultMode     = "damage",      -- damage | dps | heal | hps
        defaultSegment  = "current",     -- current | overall
        resetOnNewGroup = true,
        x = 0, y = 0, unlocked = false,
    },
})

local GetTime             = GetTime
local UnitGUID            = UnitGUID
local UnitName            = UnitName
local UnitClass           = UnitClass
local UnitAffectingCombat = UnitAffectingCombat
local IsInRaid            = IsInRaid
local IsInGroup           = IsInGroup
local GetNumGroupMembers  = GetNumGroupMembers
local wipe                = wipe
local pairs               = pairs
local type, tonumber      = type, tonumber

local Meter = {}
ns.Meter = Meter

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
local dirty = false
local listener              -- window callback: fn("start" | "end" | "reset")

local function notify(what)
    if listener then listener(what) end
end

-- Only called after resolve() confirmed roster[guid] exists.
local function entry(seg, guid)
    local p = seg.players[guid]
    if not p then
        local r = roster[guid]
        p = { name = r.name, class = r.class, damage = 0, heal = 0, overheal = 0 }
        seg.players[guid] = p
    end
    return p
end

-- Source GUID -> the roster GUID it counts for, or nil when nobody we track.
local function resolve(guid)
    if roster[guid] then return guid end
    local o = owners[guid]
    if o and roster[o] then return o end
    return nil
end

local function fold(dst, src)
    for guid, p in pairs(src.players) do
        local d = dst.players[guid]
        if not d then
            d = { name = p.name, class = p.class, damage = 0, heal = 0, overheal = 0 }
            dst.players[guid] = d
        end
        d.damage   = d.damage   + p.damage
        d.heal     = d.heal     + p.heal
        d.overheal = d.overheal + p.overheal
    end
    dst.duration = dst.duration + src.duration
end

------------------------------------------------------------------------
-- Public read interface (the window reads through this and never writes)
------------------------------------------------------------------------
function Meter:GetSegment(which)
    if which == "overall" then return overall end
    return current or last
end

function Meter:Duration(seg)
    if not seg then return 0 end
    if seg == current then return GetTime() - seg.start end
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
    -- owners stays: summoned pets keep their owner; resolve() already gates on roster.
    rebuildRoster()
    dirty = true
    notify("reset")
end

-- Parts 2 and 3 add their own subevent entries here.
Meter.HANDLERS = {}

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
    fold(overall, current)
    last, current = current, nil
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

local function addDamage(src, amount)
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
    p.damage = p.damage + amount
    dirty = true
end

-- SWING_DAMAGE: amount is field 12. Spell-prefixed subevents carry spellId,
-- spellName, spellSchool in 12-14 and amount in 15.
HANDLERS.SWING_DAMAGE = function(src, _, a12) addDamage(src, a12) end
local function spellDamage(src, _, _, a15) addDamage(src, a15) end
HANDLERS.RANGE_DAMAGE          = spellDamage
HANDLERS.SPELL_DAMAGE          = spellDamage
HANDLERS.SPELL_PERIODIC_DAMAGE = spellDamage
HANDLERS.DAMAGE_SHIELD         = spellDamage
HANDLERS.DAMAGE_SPLIT          = spellDamage

-- Healing never opens a fight (pre-pull heals are not combat); field 16 is
-- overhealing.
local function spellHeal(src, _, _, a15, a16)
    if not current or not a15 then return end
    local owner = resolve(src)
    if not owner then return end
    local p = entry(current, owner)
    p.heal     = p.heal + a15
    p.overheal = p.overheal + (a16 or 0)
    dirty = true
end
HANDLERS.SPELL_HEAL          = spellHeal
HANDLERS.SPELL_PERIODIC_HEAL = spellHeal

HANDLERS.SPELL_SUMMON = function(src, dst)
    if dst and roster[src] then owners[dst] = src end
end

local function onCLEU()
    local _, sub, _, src, _, _, _, dst, _, _, _, a12, _, _, a15, a16 = CLGetInfo()
    local h = HANDLERS[sub]
    if h then h(src, dst, a12, a15, a16) end
end

function mod:EngineEnable()
    kind = groupKind()
    self:RegisterEvent("GROUP_ROSTER_UPDATE",         onRoster)
    self:RegisterEvent("PLAYER_ENTERING_WORLD",       onRoster)
    self:RegisterEvent("UNIT_PET",                    onUnitPet)
    self:RegisterEvent("PLAYER_REGEN_DISABLED",       onRegenDisabled)
    self:RegisterEvent("PLAYER_REGEN_ENABLED",        onRegenEnabled)
    self:RegisterEvent("ENCOUNTER_START",             onEncounterStart)
    self:RegisterEvent("ENCOUNTER_END",               onEncounterEnd)
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
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
