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
    e.unit, e.name, e.class = unit, UnitName(unit), class
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
    wipe(owners)
    rebuildRoster()
    dirty = true
    notify("reset")
end

-- Parts 2 and 3 add their own subevent entries here.
Meter.HANDLERS = {}

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
