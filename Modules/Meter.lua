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
    description = "Lightweight damage and healing meter: who did how much, per fight and overall. Left-click the title for the next mode, right-click for the menu, mouse wheel on the title cycles modes, the padlock frees a window for dragging.",
    defaults    = {
        enabled         = true,
        barHeight       = 18,
        barGap          = 1,
        fontSize        = 11,
        texture         = "Atrocity",
        showRank        = true,
        barIcon         = "class",  -- off | class | spec (showClassIcon before part 5)
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
        pinSelf         = false, -- own bar stays in view when scrolled out
        autoCurrent     = false, -- a window on an old fight returns to the running one on pull
        dpsBasis        = "fight",   -- fight | active: what the per-second values divide by
        barColorMode    = "class",   -- class | custom
        barColor        = { r = 0.60, g = 0.60, b = 0.60 },
        bgColor         = { r = 0.05, g = 0.05, b = 0.06 },
        bgAlpha         = 90,        -- window background opacity in percent
        growUp          = false,     -- title at the bottom, bars stack upwards
        resetOnInstance = "never",   -- never | ask | always: entering a new dungeon or raid
        hideInPvP       = false,     -- arena and battlegrounds
        bossOnly        = false,     -- damage modes count only what went into bosses
        smoothBars      = true,      -- bars glide to their new length
        autoSegment     = false,     -- current -> overall after a fight, back on the pull
        iconBox         = false,     -- icon in its own framed square left of the bar
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

-- Damage and healing events closer together than this count as one stretch
-- of activity; the per-second values can divide by that instead of the fight.
local ACTIVE_GAP = 3

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

local seedSpec   -- forward: the spec store is further down

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
    if seedSpec then seedSpec(guid, e.name, class) end
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
-- enemies[name] = { name, damage, by = { [guid] = amount } }: what the group
-- did to each enemy, for the enemies mode.
local function newSegment()
    return { title = nil, start = 0, duration = 0, players = {}, enemies = {} }
end

-- The last few things that happened to each group member, for the death
-- recap: a ring of RECAP_N records per member, fields overwritten in place
-- so a raid's hit rate mints no tables. A death copies the ring out.
local RECAP_N = 8
local recent = {}          -- guid -> { pos = i, [1..RECAP_N] = rec }
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax

local function recapPush(guid, spell, amount, heal, src, overkill)
    local ring = recent[guid]
    if not ring then
        ring = { pos = 0 }
        for i = 1, RECAP_N do ring[i] = {} end
        recent[guid] = ring
    end
    local pos = ring.pos % RECAP_N + 1
    ring.pos = pos
    local rec = ring[pos]
    rec.t, rec.spell, rec.amount, rec.heal, rec.src, rec.overkill = GetTime(), spell, amount, heal, src, overkill
    local r = roster[guid]
    if r then
        rec.hp, rec.hpMax = UnitHealth(r.unit), UnitHealthMax(r.unit)
    else
        rec.hp, rec.hpMax = nil, nil
    end
end

-- Oldest first, as fresh tables (the ring keeps turning).
local function recapCopy(guid, deathTime)
    local ring = recent[guid]
    if not ring then return nil end
    local out = {}
    for i = 1, RECAP_N do
        local idx = (ring.pos + i - 1) % RECAP_N + 1   -- oldest .. newest
        local rec = ring[idx]
        if rec.t then
            out[#out + 1] = { t = deathTime - rec.t, spell = rec.spell, amount = rec.amount,
                              heal = rec.heal, src = rec.src, overkill = rec.overkill,
                              hp = rec.hp, hpMax = rec.hpMax }
        end
    end
    return out
end

local function recapClear(guid)
    local ring = recent[guid]
    if ring then
        for i = 1, RECAP_N do ring[i].t = nil end
        ring.pos = 0
    end
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
-- Aura uptime hooks; the bodies live with the aura handlers further down.
local creditAuras, seedAuras, resetAuras

local function notify(what)
    if listener then listener(what) end
end

local function newPlayer(name, class)
    return { name = name, class = class,
             damage = 0, heal = 0, overheal = 0,
             taken = 0, interrupts = 0, dispels = 0, deaths = 0,
             active = 0, mana = 0, bossDamage = 0 }
end

-- Timeline: damage and healing per TL_STEP-second bucket of the running
-- fight, for the graph in the breakdown. Only the fight itself keeps one;
-- the overall has no clock to draw against.
local TL_STEP = 5
Meter.TL_STEP = TL_STEP
local function timeline(p, key, seg, now, amount)
    local t = p[key]
    if not t then
        t = {}
        p[key] = t
    end
    local b = math.floor((now - seg.start) / TL_STEP) + 1
    t[b] = (t[b] or 0) + amount
end

-- Bosses: the encounter units the client names, plus whatever carries the
-- running encounter's name. Damage into them is counted twice, once as
-- damage and once as boss damage, so the boss filter is a different column
-- rather than a different fight.
local bossGUIDs = {}
local UnitClassification = UnitClassification
-- A unit the client ranks as a world boss (the skull level) counts too:
-- that is what every raid boss on this client carries, and it needs no
-- encounter units to work.
local function markBossUnit(unit)
    if not UnitExists(unit) then return end
    local g = UnitGUID(unit)
    if g and UnitClassification(unit) == "worldboss" then bossGUIDs[g] = true end
end
local function onEngageUnit()
    wipe(bossGUIDs)
    for i = 1, 5 do
        local g = UnitGUID("boss" .. i)
        if g then bossGUIDs[g] = true end
    end
    markBossUnit("target")
end
local function onTargetChanged()
    markBossUnit("target")
end
local function isBoss(seg, dst, dstName)
    if dst and bossGUIDs[dst] then return true end
    return seg.title ~= nil and dstName == seg.title
end

-- Avoidance and mitigation on the taken side, born on the first hit or
-- miss: whole attacks avoided by kind, the hits that landed, and the amounts
-- shaved off landed hits.
local function avoidRec(p)
    local a = p.avoid
    if not a then
        a = { dodge = 0, parry = 0, block = 0, miss = 0, absorb = 0, resist = 0, immune = 0,
              hits = 0, blocked = 0, absorbed = 0, resisted = 0 }
        p.avoid = a
    end
    return a
end
local MISS_KEY = { DODGE = "dodge", PARRY = "parry", BLOCK = "block", MISS = "miss",
                   ABSORB = "absorb", RESIST = "resist", IMMUNE = "immune", DEFLECT = "miss", EVADE = "miss" }

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

-- Hits, crits, smallest and largest per spell: what the breakdown's tooltip
-- shows. One small table per spell per player, born on its first hit.
local function stat(p, key, id, amount, crit)
    local t = p[key]
    if not t then
        t = {}
        p[key] = t
    end
    local e = t[id]
    if not e then
        e = { n = 0, c = 0, sum = 0, min = amount, max = amount }
        t[id] = e
    end
    e.n   = e.n + 1
    e.sum = e.sum + amount
    if crit then e.c = e.c + 1 end
    if amount < e.min then e.min = amount end
    if amount > e.max then e.max = amount end
end

-- Activity: two of a player's events within ACTIVE_GAP seconds extend their
-- active time by the gap between them. A lone hit adds nothing, a steady
-- rotation adds almost the whole fight.
local function touch(p, now)
    local lt = p.lastT
    if lt and now - lt <= ACTIVE_GAP then
        p.active = (p.active or 0) + (now - lt)
    end
    p.lastT = now
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

-- Seconds the player was active in the segment, for the tooltip and the
-- active-time basis; never above the fight's own length.
function Meter:ActiveTime(seg, p)
    local a = p and p.active or 0
    local d = self:Duration(seg)
    if a > d then a = d end
    return a
end

function Meter:IsDirty()     return dirty end
function Meter:ClearDirty()  dirty = false end
function Meter:InCombat()    return current ~= nil end
function Meter:SetListener(fn) listener = fn end
function Meter:PlayerGUID()  return playerGUID end

function Meter:Reset()
    wipe(overall.players)
    wipe(overall.enemies)
    overall.duration = 0
    if current then
        wipe(current.players)
        wipe(current.enemies)
        current.start = GetTime()
    end
    last = nil
    wipe(history)
    if resetAuras then resetAuras() end
    -- owners stays: summoned pets keep their owner; resolve() already gates on roster.
    rebuildRoster()
    dirty = true
    notify("reset")
end

-- Later parts add their own subevent entries here.
Meter.HANDLERS = {}

------------------------------------------------------------------------
-- Specs: which talent tree a group member plays, for the bar icon.
--
-- Three sources, each stronger than the last: the account-wide store from
-- earlier sessions (0), a talent-exclusive spell seen in the log (1), the
-- talent trees themselves -- own via ns:DominantTalentTree, others through
-- an inspect (2). A stronger source overwrites a weaker one; a weaker one
-- never overwrites. Icons and names come from the client's own class/tree
-- table, so nothing ships.
------------------------------------------------------------------------
local specs = {}          -- guid -> { tree = 1..3, src = 0..2, tried = t }
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
                   SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }

-- Base rank ids of spells that exist in exactly one tree (TBC). Resolved to
-- NAMES at first use through GetSpellInfo, so every rank in the log matches
-- without listing the ranks. A spell the client does not know is skipped.
local SIG_BASE = {
    WARRIOR = { [12294] = 1, [23881] = 2, [23922] = 3, [20243] = 3, [12292] = 2, [12328] = 1 },
    PALADIN = { [20473] = 1, [31842] = 1, [20925] = 2, [31935] = 2, [35395] = 3, [20375] = 3 },
    HUNTER  = { [19574] = 1, [19577] = 1, [19434] = 2, [19506] = 2, [34490] = 2, [19386] = 3, [19306] = 3, [23989] = 3 },
    ROGUE   = { [14177] = 1, [1329] = 1, [14183] = 3, [13877] = 2, [13750] = 2, [16511] = 3, [36554] = 3, [14185] = 3 },
    PRIEST  = { [10060] = 1, [33206] = 1, [14751] = 1, [34861] = 2, [724] = 2, [15473] = 3, [15286] = 3, [15407] = 3, [34914] = 3, [15487] = 3 },
    SHAMAN  = { [16166] = 1, [30706] = 1, [17364] = 2, [30823] = 2, [974] = 3, [16190] = 3, [16188] = 3 },
    MAGE    = { [12042] = 1, [12043] = 1, [31589] = 1, [11366] = 2, [11129] = 2, [11113] = 2, [31661] = 2, [11426] = 3, [12472] = 3, [31687] = 3 },
    WARLOCK = { [30108] = 1, [18220] = 1, [18288] = 1, [18708] = 2, [19028] = 2, [30146] = 2, [18788] = 2, [17877] = 3, [17962] = 3, [30283] = 3 },
    DRUID   = { [24858] = 1, [5570] = 1, [33831] = 1, [33878] = 2, [33876] = 2, [16979] = 2, [18562] = 3, [33891] = 3, [17116] = 3 },
}
local sigByName        -- class -> name -> tree, built once; per class, because
                       -- two classes share a spell name (Nature's Swiftness)

local function sigTable()
    if sigByName then return sigByName end
    sigByName = {}
    local GetSpellInfo = GetSpellInfo
    for class, list in pairs(SIG_BASE) do
        local t = {}
        sigByName[class] = t
        for id, tree in pairs(list) do
            local name = GetSpellInfo(id)
            if name then t[name] = tree end
        end
    end
    return sigByName
end

local function specStore()
    local g = ns.db and ns.db.global
    if not g then return nil end
    if type(g.meterSpecs) ~= "table" then g.meterSpecs = {} end
    return g.meterSpecs
end

-- An entry may exist with no answer yet (an inspect was tried): src -1.
local function setSpec(guid, tree, src)
    local s = specs[guid]
    if s and (s.src or -1) > src then return end
    if s and s.tree == tree and s.src == src then return end
    if not s then
        s = {}
        specs[guid] = s
    end
    s.tree, s.src = tree, src
    local r = roster[guid]
    local store = r and specStore()
    if store and src > 0 then
        store[r.name] = { class = r.class, tree = tree, t = time() }
    end
    dirty = true
    -- Outside a fight no ticker paints; the window repaints on request.
    if not current then notify("repaint") end
end

-- Forward-declared above addUnit: a member joining gets last session's
-- answer at once, and the pull already shows the icon.
seedSpec = function(guid, name, class)
    if specs[guid] then return end
    local store = specStore()
    local e = store and store[name]
    if e and e.class == class and type(e.tree) == "number" then
        specs[guid] = { tree = e.tree, src = 0 }
    end
end

-- A log event from a group member that only one tree can cast.
local function noteSpec(src, spellName)
    if type(spellName) ~= "string" then return end
    local r = roster[src]
    if not r then return end
    local s = specs[src]
    if s and (s.src or -1) >= 1 and s.tree then return end   -- a real source already answered
    local byClass = sigTable()[r.class]
    local tree = byClass and byClass[spellName]
    if tree then setSpec(src, tree, 1) end
end

function Meter:SpecOf(guid)
    local s = specs[guid]
    return s and s.tree or nil
end

-- Icon (file id) and name of a class's tree; cached per pair.
local specInfo = {}
local SI = C_SpecializationInfo
function Meter:SpecInfo(class, tree)
    if not (class and tree) then return nil end
    local key = class .. tree
    local e = specInfo[key]
    if e then return e.icon, e.name end
    local classID = CLASS_ID[class]
    local icon, name
    if classID and SI and SI.GetSpecializationInfoForClassID then
        local ok, _, n, _, ic = pcall(SI.GetSpecializationInfoForClassID, classID, tree)
        if ok then
            if type(n) == "string" and n ~= "" then name = n end
            if type(ic) == "number" or (type(ic) == "string" and ic ~= "") then icon = ic end
        end
    end
    specInfo[key] = { icon = icon or false, name = name or false }
    return icon, name
end

local function readOwnSpec()
    if not (playerGUID and ns.DominantTalentTree) then return end
    local ok, idx = pcall(ns.DominantTalentTree, ns)
    if ok and type(idx) == "number" then setSpec(playerGUID, idx, 2) end
end

-- Inspect queue: one request every two seconds to a member whose spec no
-- talent read has confirmed yet, in range, out of combat, and never while
-- the inspect window is open (its own request would be answered with ours).
local INSPECT_RETRY = 300
local inspectTicker
local pendingGUID, pendingAt
local CanInspect, NotifyInspect, ClearInspectPlayer = CanInspect, NotifyInspect, ClearInspectPlayer

local UnitIsVisible = UnitIsVisible
local function inspectCandidate()
    local now = GetTime()
    for guid, r in pairs(roster) do
        local s = specs[guid]
        if guid ~= playerGUID and (not s or (s.src or -1) < 2)
           and (not s or not s.tried or now - s.tried > INSPECT_RETRY)
           and UnitExists(r.unit) and UnitIsVisible(r.unit) and CanInspect(r.unit) then
            -- Visible and inspectable; a request that still gets no answer
            -- is released by the four-second wait in inspectTick.
            return guid, r.unit
        end
    end
    return nil
end

-- Anyone besides us to ask at all? Solo, the ticker has nothing to do.
local function othersInRoster()
    for guid in pairs(roster) do
        if guid ~= playerGUID then return true end
    end
    return false
end

local function stopInspect()
    if inspectTicker then
        ns:CancelTicker(inspectTicker)
        inspectTicker = nil
    end
end

local function inspectTick()
    if not NotifyInspect then stopInspect(); return end
    if pendingGUID and GetTime() - pendingAt < 4 then return end
    pendingGUID = nil
    if UnitAffectingCombat("player") then return end
    local frame = _G.InspectFrame
    if frame and frame:IsShown() then return end
    local guid, unit = inspectCandidate()
    if not guid then
        -- Nobody in range right now is not "nobody ever": the ticker keeps
        -- looking (a roster scan every two seconds) as long as there is a
        -- group; solo it stops.
        if not othersInRoster() then stopInspect() end
        return
    end
    local s = specs[guid]
    if not s then
        s = { src = -1 }
        specs[guid] = s
    end
    s.tried = GetTime()
    pendingGUID, pendingAt = guid, GetTime()
    NotifyInspect(unit)
end

local function startInspect()
    if inspectTicker or not NotifyInspect then return end
    inspectTicker = ns:AddTicker(2, inspectTick, nil, "meter-inspect")
end

local function onInspectReady(_, guid)
    if not pendingGUID or guid ~= pendingGUID then return end
    pendingGUID = nil
    if not (SI and SI.GetSpecializationInfo) then return end
    local bestIdx, bestPts
    for i = 1, 3 do
        -- inspectTarget nil, as the client's own TBC shim passes it: the
        -- inspected unit is the one NotifyInspect named.
        local ok, _, _, _, _, _, _, points = pcall(SI.GetSpecializationInfo, i, true, false, nil)
        if ok and type(points) == "number" and points >= 0 and points <= 61
           and (not bestPts or points > bestPts) then
            bestPts, bestIdx = points, i
        end
    end
    if bestIdx and bestPts and bestPts > 0 then setSpec(guid, bestIdx, 2) end
    local frame = _G.InspectFrame
    if ClearInspectPlayer and not (frame and frame:IsShown()) then ClearInspectPlayer() end
end

local function pruneSpecStore()
    local store = specStore()
    if not store then return end
    local cutoff = time() - 30 * 86400
    for name, e in pairs(store) do
        if type(e) ~= "table" or (tonumber(e.t) or 0) < cutoff then store[name] = nil end
    end
end

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

-- Auras still up when the fight ends are credited to it and start over for
-- the next one, so a buff that spans two fights shows in both.
local function closeSegment()
    if not current then return end
    stopWait()
    if creditAuras then creditAuras(GetTime()) end
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
    if seedAuras then seedAuras(current.start) end
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
    startInspect()
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

-- Enemies are keyed by name: every trash mob of a kind folds into one row,
-- which is what a reader wants to know ("how much went into the adds").
local function enemyHit(seg, name, owner, amount)
    local e = seg.enemies[name]
    if not e then
        e = { name = name, damage = 0, by = {} }
        seg.enemies[name] = e
    end
    e.damage = e.damage + amount
    e.by[owner] = (e.by[owner] or 0) + amount
end

-- Every counter lands in the running fight AND in the overall; the per-target
-- table (dstName) feeds the tooltip's target block.
local function addDamage(src, amount, spellId, dstName, dst, crit)
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
    if isBoss(current, dst, dstName) then
        p.bossDamage = (p.bossDamage or 0) + amount
        o.bossDamage = (o.bossDamage or 0) + amount
    end
    timeline(p, "tlDamage", current, GetTime(), amount)
    bump(p, "spells", spellId, amount)
    bump(o, "spells", spellId, amount)
    stat(p, "spellStats", spellId, amount, crit)
    stat(o, "spellStats", spellId, amount, crit)
    local now = GetTime()
    touch(p, now)
    touch(o, now)
    if dstName then
        bump(p, "targets", dstName, amount)
        bump(o, "targets", dstName, amount)
        -- the enemy side of the same hit: only for things outside the group
        -- (a friendly-fire hit on a member is the member's damage taken)
        if not roster[dst] and not owners[dst] then
            enemyHit(current, dstName, owner, amount)
            enemyHit(overall, dstName, owner, amount)
        end
    end
    dirty = true
end

-- Damage landing on a group member (players only, never their pets). The
-- last hit stays on the entry so a death can name its killing blow. Taking
-- damage never opens a fight; PLAYER_REGEN_DISABLED already did.
local function addTaken(dst, srcName, amount, spellId, overkill, resisted, blocked, absorbed)
    if not current or not amount or amount <= 0 then return end
    if not roster[dst] then return end
    local p = entry(current, dst)
    local o = entry(overall, dst)
    p.taken = p.taken + amount
    o.taken = o.taken + amount
    bump(p, "takenBy", spellId, amount)
    bump(o, "takenBy", spellId, amount)
    -- Environmental damage (a string kind, no attacker) is not an attack
    -- that could have been avoided: it stays out of the avoidance count.
    if type(spellId) ~= "string" then
        local ap, ao = avoidRec(p), avoidRec(o)
        ap.hits, ao.hits = ap.hits + 1, ao.hits + 1
        if resisted and resisted > 0 then ap.resisted = ap.resisted + resisted; ao.resisted = ao.resisted + resisted end
        if blocked  and blocked  > 0 then ap.blocked  = ap.blocked  + blocked;  ao.blocked  = ao.blocked  + blocked  end
        if absorbed and absorbed > 0 then ap.absorbed = ap.absorbed + absorbed; ao.absorbed = ao.absorbed + absorbed end
    end
    p.lastSpell, p.lastAmount, p.lastSrc = spellId, amount, srcName
    recapPush(dst, spellId, amount, false, srcName, (overkill and overkill > 0) and overkill or nil)
    dirty = true
end

-- SWING_DAMAGE: amount is field 12, overkill 13, critical 18. Spell-prefixed
-- subevents carry spellId, spellName, spellSchool in 12-14, amount in 15,
-- overkill 16, critical 21 (healing: critical 18).
-- Partial mitigation rides on the hit: swing resisted 15, blocked 16,
-- absorbed 17; spell resisted 18, blocked 19, absorbed 20.
HANDLERS.SWING_DAMAGE = function(src, srcName, dst, a12, a15, a16, a13, dstName, a18, _, _, a17)
    addDamage(src, a12, MELEE_ID, dstName, dst, a18)
    addTaken(dst, srcName, a12, MELEE_ID, a13, a15, a16, a17)
end
local function spellDamage(src, srcName, dst, a12, a15, a16, a13, dstName, a18, a21, _, _, a19, a20)
    addDamage(src, a15, a12, dstName, dst, a21)
    addTaken(dst, srcName, a15, a12, a16, a18, a19, a20)
    noteSpec(src, a13)
end
HANDLERS.RANGE_DAMAGE          = spellDamage
HANDLERS.SPELL_DAMAGE          = spellDamage
HANDLERS.SPELL_PERIODIC_DAMAGE = spellDamage
HANDLERS.DAMAGE_SHIELD         = spellDamage
HANDLERS.DAMAGE_SPLIT          = spellDamage

-- Healing never opens a fight (pre-pull heals are not combat); field 16 is
-- overhealing. The per-spell and per-target tables hold effective healing,
-- like the bar.
local function spellHeal(src, srcName, dst, a12, a15, a16, a13, dstName, a18)
    if not current or not a15 then return end
    noteSpec(src, a13)
    -- a heal landing on a member is part of their recap even from outside
    if roster[dst] and a15 > (a16 or 0) then
        recapPush(dst, a12, a15 - (a16 or 0), true, srcName, nil)
    end
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
    stat(p, "healStats", a12, a15, a18)
    stat(o, "healStats", a12, a15, a18)
    local now = GetTime()
    touch(p, now)
    touch(o, now)
    if eff > 0 then timeline(p, "tlHeal", current, now, eff) end
    if dstName then
        bump(p, "healed", dstName, eff)
        bump(o, "healed", dstName, eff)
    end
    dirty = true
end
HANDLERS.SPELL_HEAL          = spellHeal
HANDLERS.SPELL_PERIODIC_HEAL = spellHeal

-- A cast alone names a spec too (a buff, a form, a cooldown): no damage or
-- healing needed before the icon is right.
HANDLERS.SPELL_CAST_SUCCESS = function(src, _, _, _, _, _, a13)
    noteSpec(src, a13)
end

-- A whole attack that never landed on a member: SWING_MISSED carries the
-- kind in 12 and the amount it would have done in 14, SPELL_MISSED in 15
-- and 17. Never opens a fight.
local function missed(dst, kind, amountMissed)
    if not current or not roster[dst] then return end
    local key = MISS_KEY[kind]
    if not key then return end
    local p = entry(current, dst)
    local o = entry(overall, dst)
    local ap, ao = avoidRec(p), avoidRec(o)
    ap[key], ao[key] = ap[key] + 1, ao[key] + 1
    -- The amount a whole avoidance would have done is not added to the
    -- mitigation sums: those are "taken off landed hits", and this one
    -- never landed.
    dirty = true
end
HANDLERS.SWING_MISSED = function(_, _, dst, a12, _, _, _, _, _, _, a14)
    missed(dst, a12, a14)
end
HANDLERS.SPELL_MISSED = function(_, _, dst, _, a15, _, _, _, _, _, _, a17)
    missed(dst, a15, a17)
end
HANDLERS.RANGE_MISSED          = HANDLERS.SPELL_MISSED
HANDLERS.SPELL_PERIODIC_MISSED = HANDLERS.SPELL_MISSED

-- Mana from spells and effects (innervate, judgements, potions, mana tide):
-- SPELL_ENERGIZE amount 15, over-energize 16, power type 17. Only mana; the
-- mode is named for it.
local function energize(dst, a12, a15, a17)
    if not current or not roster[dst] then return end
    if a17 ~= 0 or not a15 or a15 <= 0 then return end
    local p = entry(current, dst)
    local o = entry(overall, dst)
    p.mana = (p.mana or 0) + a15
    o.mana = (o.mana or 0) + a15
    bump(p, "gains", a12, a15)
    bump(o, "gains", a12, a15)
    dirty = true
end
HANDLERS.SPELL_ENERGIZE = function(_, _, dst, a12, a15, _, _, _, _, _, _, a17)
    energize(dst, a12, a15, a17)
end
HANDLERS.SPELL_PERIODIC_ENERGIZE = HANDLERS.SPELL_ENERGIZE

-- Aura uptime. Buffs are counted on the member they sit on, whoever cast
-- them; debuffs on the member who applied them, whatever they sit on. An
-- aura is a start time in auraStart until it ends; then the seconds go to
-- the running fight and the overall. Field 15 says BUFF or DEBUFF.
--
-- Only the fight counts: every record is re-stamped when a fight opens,
-- and one that ends between fights is dropped without credit. Buffs
-- survive a fight's end (a raid buff is up for the night); debuffs do not
-- (their mob is dead, and the client does not always say so).
-- SPELL_AURA_BROKEN(_SPELL) are not hooked: the client sends REMOVED for
-- the same aura, and their source is the breaker, not the applier.
local auraStart = {}
local function auraKey(guid, id, dst) return guid .. ":" .. id .. (dst or "") end

local function creditOne(key, now)
    local rec = auraStart[key]
    if not rec then return end
    local secs = now - rec.t
    -- a member who has left the roster has no entry to credit
    if secs > 0 and current and roster[rec.guid] then
        bump(entry(current, rec.guid), rec.key, rec.id, secs)
        bump(entry(overall, rec.guid), rec.key, rec.id, secs)
    end
    rec.t = now
end

-- Fight end: credit everything, keep the buffs running, drop the debuffs.
creditAuras = function(now)
    for key, rec in pairs(auraStart) do
        creditOne(key, now)
        if rec.key == "debuffUp" then auraStart[key] = nil end
    end
end

-- Fight start: the clock restarts for whatever is still up, and the buffs
-- standing on the roster before the pull (the raid buffs, the flasks) get
-- their record, or the mode would only ever see what was cast mid-fight.
local UnitAura = UnitAura
seedAuras = function(now)
    for _, rec in pairs(auraStart) do rec.t = now end
    if not UnitAura then return end
    for guid, r in pairs(roster) do
        for i = 1, 40 do
            local name, _, _, _, _, _, _, _, _, id = UnitAura(r.unit, i, "HELPFUL")
            if not name then break end
            if id then
                local key = auraKey(guid, id)
                if not auraStart[key] then
                    auraStart[key] = { t = now, guid = guid, id = id, key = "buffUp" }
                end
            end
        end
    end
end

-- A reset: the open auras start over, the debuffs are dropped with their
-- numbers.
resetAuras = function()
    local now = GetTime()
    for key, rec in pairs(auraStart) do
        if rec.key == "debuffUp" then auraStart[key] = nil else rec.t = now end
    end
end

-- Seconds of the auras still up in the running fight, added into `into`
-- by aura id: the window reads a live picture, not only what has ended.
function Meter:OpenAuraSeconds(guid, key, into)
    if not current then return into end
    local now = GetTime()
    for _, rec in pairs(auraStart) do
        if rec.guid == guid and rec.key == key then
            into[rec.id] = (into[rec.id] or 0) + (now - rec.t)
        end
    end
    return into
end

local function auraApplied(src, dst, id, auraType)
    if not current then return end
    if auraType == "BUFF" then
        if not roster[dst] then return end
        local key = auraKey(dst, id)
        if not auraStart[key] then auraStart[key] = { t = GetTime(), guid = dst, id = id, key = "buffUp" } end
    elseif auraType == "DEBUFF" then
        local owner = resolve(src)
        if not owner then return end
        local key = auraKey(owner, id, dst)
        if not auraStart[key] then auraStart[key] = { t = GetTime(), guid = owner, id = id, key = "debuffUp" } end
    end
end

local function auraRemoved(src, dst, id, auraType)
    if not next(auraStart) then return end
    local key
    if auraType == "BUFF" then
        if not roster[dst] then return end
        key = auraKey(dst, id)
    elseif auraType == "DEBUFF" then
        local owner = resolve(src)
        if not owner then return end
        key = auraKey(owner, id, dst)
    else
        return
    end
    if not auraStart[key] then return end
    if current then creditOne(key, GetTime()) end
    auraStart[key] = nil
    dirty = true
end

HANDLERS.SPELL_AURA_APPLIED = function(src, _, dst, a12, a15) auraApplied(src, dst, a12, a15) end
HANDLERS.SPELL_AURA_REMOVED = function(src, _, dst, a12, a15) auraRemoved(src, dst, a12, a15) end

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
    local now = GetTime()
    local rec = { t = now - current.start,
                  spell = p.lastSpell, amount = p.lastAmount, src = p.lastSrc,
                  recap = recapCopy(dst, now) }
    recapClear(dst)
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
    if type(a12) == "string" then addTaken(dst, nil, a13, a12, nil) end
end

local function onCLEU()
    local _, sub, _, src, srcName, _, _, dst, dstName, _, _, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21 = CLGetInfo()
    local h = HANDLERS[sub]
    if h then h(src, srcName, dst, a12, a15, a16, a13, dstName, a18, a21, a14, a17, a19, a20) end
end

------------------------------------------------------------------------
-- Entering a new dungeon or raid: reset the overall, or ask. The instance
-- id is remembered per session; the first world entry only records it, so
-- a reload inside the raid never wipes the numbers.
------------------------------------------------------------------------
local lastInstance
local RESET_POPUP = "VCUI_METER_INSTANCE_RESET"

local function resetSoon()
    if current then pendingReset = true else Meter:Reset() end
end

local function onWorld()
    onRoster()
    local inInst, kindOf = IsInInstance()
    if not inInst or (kindOf ~= "party" and kindOf ~= "raid") then return end
    local id = select(8, GetInstanceInfo())
    if not id then return end
    -- Only instance-to-instance counts: a corpse run back into the same raid
    -- is not a new raid, and the first entry of the session only records.
    local first = (lastInstance == nil)
    local changed = id ~= lastInstance
    lastInstance = id
    if first or not changed then return end
    local mode = mod.db.resetOnInstance
    if mode == "always" then
        resetSoon()
    elseif mode == "ask" and StaticPopup_Show then
        if not StaticPopupDialogs[RESET_POPUP] then
            StaticPopupDialogs[RESET_POPUP] = {
                text = ns.L["Reset the combat meter for this instance?"],
                button1 = YES or "Yes", button2 = NO or "No",
                OnAccept = function() resetSoon() end,
                timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            }
        end
        StaticPopup_Show(RESET_POPUP)
    end
end

function mod:EngineEnable()
    -- Seeded from the saved kind: at ADDON_LOADED on a fresh login the client
    -- does not know the group yet, and "solo -> raid" would wipe the overall.
    local cdb = VuloClassicUICharDB
    kind = (cdb and cdb.meter and cdb.meter.kind) or groupKind()
    self:RegisterEvent("GROUP_ROSTER_UPDATE",         onRoster)
    self:RegisterEvent("PLAYER_ENTERING_WORLD",       onWorld)
    self:RegisterEvent("UNIT_PET",                    onUnitPet)
    self:RegisterEvent("INSPECT_READY",               onInspectReady)
    self:RegisterEvent("PLAYER_TALENT_UPDATE",        readOwnSpec)
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", readOwnSpec)
    -- talents are not readable at ADDON_LOADED; the world entry is late enough
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, readOwnSpec) end)
    pruneSpecStore()
    startInspect()
    self:RegisterEvent("PLAYER_REGEN_DISABLED",       onRegenDisabled)
    self:RegisterEvent("PLAYER_REGEN_ENABLED",        onRegenEnabled)
    self:RegisterEvent("ENCOUNTER_START",             onEncounterStart)
    self:RegisterEvent("ENCOUNTER_END",               onEncounterEnd)
    self:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", onEngageUnit)
    self:RegisterEvent("PLAYER_TARGET_CHANGED",          onTargetChanged)
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
    stopInspect()
    pendingGUID = nil
end

------------------------------------------------------------------------
-- Enable / disable
------------------------------------------------------------------------
function mod:OnEnable()
    playerGUID = UnitGUID("player")
    -- Part 5 folded the class-icon switch into the three-way icon choice; a
    -- saved "off" (the only value the strip keeps) carries over once.
    if self.db.showClassIcon ~= nil then
        self.db.barIcon = self.db.showClassIcon and "class" or "off"
        self.db.showClassIcon = nil
    end
    local cdb = VuloClassicUICharDB
    if cdb then
        cdb.meter = cdb.meter or {}
        local saved = cdb.meter.overall
        if type(saved) ~= "table" then
            saved = newSegment()
            cdb.meter.overall = saved
        end
        saved.players  = saved.players or {}
        saved.enemies  = saved.enemies or {}
        saved.duration = tonumber(saved.duration) or 0
        -- Entries saved by part 1 lack the new counters; fill them once.
        -- lastT is a GetTime stamp: after a reboot the clock starts over and
        -- an old stamp would read as "three seconds ago".
        for _, p in pairs(saved.players) do
            p.taken      = p.taken      or 0
            p.interrupts = p.interrupts or 0
            p.dispels    = p.dispels    or 0
            p.deaths     = p.deaths     or 0
            p.active     = p.active     or 0
            p.lastT      = nil
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
