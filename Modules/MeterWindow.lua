-- VuloClassicUI / Modules / MeterWindow: the bar windows for the combat meter.
-- One frame per entry of mod.db.windows, pooled by slot; every frame carries
-- its own mode, segment, sort order and scroll, while bar look, font and the
-- visibility rules are shared. Reads the engine through ns.Meter and never
-- writes into its tables.
local _, ns = ...
local L     = ns.L
local UI    = ns.UI
local mod   = ns.modules.meter
local Meter = ns.Meter

local GetTime             = GetTime
local GetSpellInfo        = GetSpellInfo
local floor               = math.floor
local max                 = math.max
local min                 = math.min
local format              = string.format
local sort                = table.sort
local remove              = table.remove
local wipe                = wipe
local pairs               = pairs
local type                = type
local IsInGroup           = IsInGroup
local IsInRaid            = IsInRaid
local IsInGuild           = IsInGuild
local UnitIsUnit          = UnitIsUnit
local UnitAffectingCombat = UnitAffectingCombat
local CreateFrame         = CreateFrame

local TITLE_H  = 20
local PAD      = 2
local GRAPH_H  = 44   -- the timeline strip above a breakdown
local MODES    = { "damage", "dps", "heal", "hps", "taken", "avoidance", "enemies",
                   "interrupts", "dispels", "deaths", "buffs", "debuffs", "mana" }
-- The threat mode reads the client's threat API, not the log; a client
-- without it simply has eight modes, and a saved "threat" falls to damage.
if Meter.HAS_THREAT then MODES[#MODES + 1] = "threat" end
local MODE_IDX = {}
for i = 1, #MODES do MODE_IDX[MODES[i]] = i end
local PER_SEC  = { dps = true, hps = true }
local COUNT    = { interrupts = true, dispels = true, deaths = true, avoidance = true, buffs = true, debuffs = true }
local HEALING  = { heal = true, hps = true }
local UPTIME   = { buffs = true, debuffs = true }   -- breakdown values are seconds, shown as a share of the fight
-- Which per-spell table of the player entry a mode breaks down into.
local SUB_KEY  = { damage = "spells", dps = "spells", heal = "heals", hps = "heals",
                   taken = "takenBy", interrupts = "kicks", dispels = "purges",
                   buffs = "buffUp", debuffs = "debuffUp", mana = "gains" }
-- Which timeline of the player entry a mode can draw.
local TL_KEY   = { damage = "tlDamage", dps = "tlDamage", heal = "tlHeal", hps = "tlHeal" }
local ICONS    = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\"
local TEX_FLAT = "Interface\\Buttons\\WHITE8X8"
local ICON_FMT = "|T%s:14:14:0:0:64:64:5:59:5:59|t %s"

-- frames[i] = window record: { index, frame, db, mover, rows, order, vals,
-- scroll, mode, segment, lastTitle, lastCount }. db is nil while the slot is
-- unbound (more frames than windows after a close).
local frames = {}
local ticker
local lastCombatEnd  = 0
local hideTimerArmed = false

-- Forward declarations; filled in further down. pageChanged is on the list
-- because the window actions above its definition call it: without the
-- declaration those calls resolved to a nil global, and every mode change
-- from the title menu ended in a silent Lua error after the visible work.
local layoutRows, refresh, applyVisibility, openMenu, rowEnter, syncFrames, dragStart, dragStop
local pageChanged, syncThreatEvents, onRowClick, justDragged

------------------------------------------------------------------------
-- Labels
------------------------------------------------------------------------
local function modeLabel(m)
    if m == "damage"     then return L["Damage"] end
    if m == "dps"        then return L["DPS"] end
    if m == "heal"       then return L["Healing"] end
    if m == "hps"        then return L["HPS"] end
    if m == "taken"      then return L["Damage taken"] end
    if m == "enemies"    then return L["Enemies"] end
    if m == "interrupts" then return L["Interrupts"] end
    if m == "dispels"    then return L["Dispels"] end
    if m == "threat"     then return L["Threat"] end
    if m == "avoidance"  then return L["Avoidance"] end
    if m == "buffs"      then return L["Buff uptime"] end
    if m == "debuffs"    then return L["Debuff uptime"] end
    if m == "mana"       then return L["Mana gained"] end
    return L["Deaths"]
end

-- A finished fight is named by its boss, else by its place in the history
-- (1 = the most recent); the same text serves the menu and the title.
local function fightLabel(seg, idx)
    if seg.title then return seg.title end
    return format(L["Fight %d"], idx or (Meter:HistoryIndex(seg) or 0))
end

local function segmentLabel(w, seg)
    if w.mode == "threat" then
        return (seg and seg.title) or L["No target"]
    end
    if w.segment == "overall" then return L["Overall"] end
    if type(w.segment) == "table" and seg == w.segment then return fightLabel(seg) end
    if seg and seg.title then return seg.title end
    return L["Current fight"]
end

-- The segment a window paints: the threat snapshot in threat mode, else
-- whatever the engine has under the window's choice. A history pick that the
-- engine has trimmed since is dropped back to the saved choice here, so the
-- title and the rows never disagree about what they show.
-- The row set a window paints from its segment: the enemies table in the
-- enemies mode (rows are what the group hit), the players otherwise.
local function rowsOf(seg, mode)
    if not seg then return nil end
    if mode == "enemies" then return seg.enemies or {} end
    return seg.players
end

local function segmentOf(w)
    if w.mode == "threat" then return Meter:ThreatSegment() end
    local seg = Meter:GetSegment(w.segment)
    if type(w.segment) == "table" and seg ~= w.segment then
        w.segment = w.db.segment
        seg = Meter:GetSegment(w.segment)
    end
    return seg
end

------------------------------------------------------------------------
-- Numbers
------------------------------------------------------------------------
-- Integer -> short string, cached: the same totals repeat across ticks and
-- rows, and a raid fight would otherwise mint thousands of strings.
local fmtCache, fmtCount = {}, 0
local function short(n)
    n = floor(n + 0.5)
    if n ~= n then n = 0 end   -- NaN would poison the cache table
    local s = fmtCache[n]
    if s then return s end
    if n >= 1000000 then
        s = format("%.2fm", n / 1000000)
    elseif n >= 1000 then
        s = format("%.1fk", n / 1000)
    else
        s = tostring(n)
    end
    fmtCount = fmtCount + 1
    if fmtCount > 4000 then
        wipe(fmtCache)
        fmtCount = 0
    end
    fmtCache[n] = s
    return s
end

local function clock(sec)
    sec = floor(sec + 0.5)
    return format("%d:%02d", floor(sec / 60), sec % 60)
end

-- The seconds a per-second value divides by: the fight, or the player's own
-- active stretch when the option says so. A lone hit has no stretch yet;
-- one second keeps the number finite and honest ("that hit, per second").
local function basisOf(p, dur)
    if mod.db.dpsBasis == "active" then
        local a = p.active or 0
        if a > dur then a = dur end
        return max(a, 1)
    end
    return dur
end

-- The damage a row counts: everything, or only what went into bosses.
local function damageOf(p)
    if mod.db.bossOnly then return p.bossDamage or 0 end
    return p.damage
end

local function avoided(p)
    local a = p.avoid
    if not a then return 0 end
    return a.dodge + a.parry + a.block + a.miss + a.absorb + a.resist + a.immune
end

local function countKeys(t)
    local n = 0
    if t then for _ in pairs(t) do n = n + 1 end end
    return n
end

-- The aura seconds a player has in a segment: what has ended, plus what is
-- still up when the segment is the running fight. One scratch table, so the
-- ticker never mints one; callers read it before the next call.
local auraScratch = {}
local function auraSeconds(seg, p, guid, key)
    wipe(auraScratch)
    local t = p[key]
    if t then for id, v in pairs(t) do auraScratch[id] = v end end
    if guid and Meter:InCombat() and seg == Meter:GetSegment("current") then
        Meter:OpenAuraSeconds(guid, key, auraScratch)
    end
    return auraScratch
end

local function valueOf(mode, p, dur, seg, guid)
    if mode == "damage"     then return damageOf(p) end
    if mode == "avoidance"  then return avoided(p) end
    if mode == "buffs"      then return countKeys(auraSeconds(seg, p, guid, "buffUp")) end
    if mode == "debuffs"    then return countKeys(auraSeconds(seg, p, guid, "debuffUp")) end
    if mode == "mana"       then return p.mana or 0 end
    if mode == "heal"       then return p.heal - p.overheal end
    if mode == "taken"      then return p.taken      or 0 end
    if mode == "interrupts" then return p.interrupts or 0 end
    if mode == "dispels"    then return p.dispels    or 0 end
    if mode == "deaths"     then return p.deaths     or 0 end
    if mode == "threat"     then return p.threat     or 0 end
    if mode == "enemies"    then return p.damage     or 0 end
    if dur <= 0 then return 0 end
    local basis = basisOf(p, dur)
    if mode == "dps" then return damageOf(p) / basis end
    return (p.heal - p.overheal) / basis
end

-- Ties break on the guid so equal values keep a stable order between ticks.
-- sortVals is set right before each sort; one comparator serves every window.
local sortVals
local function byValue(a, b)
    local va, vb = sortVals[a], sortVals[b]
    if va == vb then return a < b end
    return va > vb
end

-- Amount modes: total (per second); per-second modes swap the two; count
-- modes show the count alone. Percent is appended inside the brackets.
local function rightText(mode, p, v, total, dur)
    local db  = mod.db
    local pct = total > 0 and (v / total * 100) or 0
    -- Threat: the percent is the whole point (share of the tank's threat,
    -- not of the sum), so it ignores the bracket switches.
    if mode == "threat" then return format("%s (%.0f%%)", short(v), p.pct or 0) end
    -- Avoidance: the share is of the attacks that came in, not of the group
    if mode == "avoidance" then
        local att = v + ((p.avoid and p.avoid.hits) or 0)
        return format("%d (%.1f%%)", v, att > 0 and v / att * 100 or 0)
    end
    if COUNT[mode] then
        if db.showPercent then return format("%d (%.1f%%)", v, pct) end
        return format("%d", v)
    end
    local secondary
    if mode == "dps" then
        secondary = damageOf(p)
    elseif mode == "hps" then
        secondary = p.heal - p.overheal
    else
        secondary = dur > 0 and v / basisOf(p, dur) or 0
    end
    local main = short(v)
    if db.showPerSecond and db.showPercent then
        return format("%s (%s, %.1f%%)", main, short(secondary), pct)
    elseif db.showPerSecond then
        return format("%s (%s)", main, short(secondary))
    elseif db.showPercent then
        return format("%s (%.1f%%)", main, pct)
    end
    return main
end

------------------------------------------------------------------------
-- Tooltip: the breakdown block for the window's mode, then the summary.
------------------------------------------------------------------------
-- Spell id -> "|Ticon|t Name", built once per id; the strings live as long
-- as the session, which is what a tooltip that repaints on every re-sort wants.
local spellLeft = {}
local function spellText(id)
    local s = spellLeft[id]
    if s then return s end
    if type(id) == "string" then
        -- environmental kind from the log; the client's own string when it has one
        s = _G["STRING_ENVIRONMENTAL_DAMAGE_" .. id:upper()] or id
        spellLeft[id] = s
        return s
    end
    local name, _, icon = GetSpellInfo(id)
    if name then
        s = icon and format(ICON_FMT, icon, name) or name
    else
        s = "#" .. tostring(id)
    end
    spellLeft[id] = s
    return s
end

local tipLines = {}
local tipColor = {}
local tipSpec  = { title = "", lines = tipLines, anchor = "ANCHOR_RIGHT" }
-- Line tables are pooled: the tooltip is rebuilt on every re-sort under the
-- cursor, and a fresh table per line per tick would be garbage for nothing.
local linePool = {}
local function line(i, left, right)
    local t = linePool[i]
    if not t then
        t = {}
        linePool[i] = t
    end
    t[1], t.right = left, right
    tipLines[#tipLines + 1] = t
    return t
end

local sortIds, sortSrc = {}, {}
local function byCount(a, b)
    local va, vb = sortSrc[a], sortSrc[b]
    -- ids are spell numbers, environmental kinds are strings: tostring keeps
    -- the tie-break comparable
    if va == vb then return tostring(a) < tostring(b) end
    return va > vb
end

local function spellLines(p, key, own, isCount)
    local t = p[key]
    local n = 0
    if t then
        for id, v in pairs(t) do
            if v > 0 then
                n = n + 1
                sortIds[n] = id
            end
        end
    end
    for i = n + 1, #sortIds do sortIds[i] = nil end
    if n == 0 then
        tipLines[#tipLines + 1] = L["No details yet"]
        return
    end
    sortSrc = t
    sort(sortIds, byCount)
    local rows = min(n, mod.db.tooltipRows or 5)
    for i = 1, rows do
        local id = sortIds[i]
        local v  = t[id]
        if isCount then
            line(i, spellText(id), format("%d", v))
        else
            line(i, spellText(id), format("%s (%.1f%%)", short(v), own > 0 and v / own * 100 or 0))
        end
    end
end

-- Who the damage or healing went to. Keys are unit names, so no icon; the
-- line pool is shared with the ability block, hence the offset.
local function targetLines(p, key, own)
    local t = p[key]
    if not t then return end
    local n = 0
    for name, v in pairs(t) do
        if v > 0 then
            n = n + 1
            sortIds[n] = name
        end
    end
    for i = n + 1, #sortIds do sortIds[i] = nil end
    if n == 0 then return end
    sortSrc = t
    sort(sortIds, byCount)
    tipLines[#tipLines + 1] = " "
    tipLines[#tipLines + 1] = L["Targets"]
    local rows = min(n, mod.db.tooltipRows or 5)
    for i = 1, rows do
        local name = sortIds[i]
        local v = t[name]
        line(100 + i, name, format("%s (%.1f%%)", short(v), own > 0 and v / own * 100 or 0))
    end
end

-- The last things that happened before the newest death: seconds before
-- it, what hit (or healed), the amount and the health left afterwards.
-- Damage red, healing green, the killing blow with its overkill.
local function recapLines(rec)
    local recap = rec and rec.recap
    if not recap or #recap == 0 then return end
    tipLines[#tipLines + 1] = " "
    tipLines[#tipLines + 1] = L["Death recap"]
    local n = #recap
    local first = max(1, n - (mod.db.tooltipRows or 5) + 1)
    for i = first, n do
        local d = recap[i]
        local name = d.spell and spellText(d.spell) or (d.heal and L["Healing"] or L["Unknown"])
        local left = format("-%.1fs  %s", d.t or 0, name)
        local right
        if d.heal then
            right = "|cff66dd66+" .. short(d.amount or 0) .. "|r"
        else
            right = "|cffff6666-" .. short(d.amount or 0) .. "|r"
            if i == n and d.overkill then
                right = right .. " |cffff3333(" .. short(d.overkill) .. " " .. L["overkill"] .. ")|r"
            end
        end
        if d.hp and d.hpMax and d.hpMax > 0 then
            right = right .. format(" (%d%%)", floor(d.hp / d.hpMax * 100 + 0.5))
        end
        line(200 + i, left, right)
    end
end

local function deathLines(p)
    local log = p.deathLog
    if not log or #log == 0 then
        tipLines[#tipLines + 1] = L["No details yet"]
        return
    end
    local rows = min(#log, mod.db.tooltipRows or 5)
    for i = 1, rows do
        local d = log[#log - i + 1]
        local left = clock(d.t or 0) .. "  " .. (d.spell and spellText(d.spell) or L["Unknown"])
        local right
        if d.amount and d.src then
            right = short(d.amount) .. " \194\183 " .. d.src
        elseif d.amount then
            right = short(d.amount)      -- environment: no source to name
        else
            right = L["Unknown"]
        end
        line(i, left, right)
    end
    recapLines(log[#log])
end

-- Enemies mode: who did the damage to this enemy.
local sortBy
local function byAmount(a, b)
    local va, vb = sortBy[a], sortBy[b]
    if va == vb then return tostring(a) < tostring(b) end
    return va > vb
end

local function attackerLines(e, seg)
    local by = e.by
    local n = 0
    if by then
        for guid, v in pairs(by) do
            if v > 0 then
                n = n + 1
                sortIds[n] = guid
            end
        end
    end
    for i = n + 1, #sortIds do sortIds[i] = nil end
    if n == 0 then
        tipLines[#tipLines + 1] = L["No details yet"]
        return
    end
    sortBy = by
    sort(sortIds, byAmount)
    tipLines[#tipLines + 1] = L["By attacker"]
    local rows = min(n, mod.db.tooltipRows or 5)
    local own = e.damage or 0
    for i = 1, rows do
        local guid = sortIds[i]
        local p = seg.players[guid]
        local v = by[guid]
        line(i, (p and p.name) or "?", format("%s (%.1f%%)", short(v), own > 0 and v / own * 100 or 0))
    end
end

-- Avoidance: whole attacks by kind with their share of everything that
-- came in, then what was shaved off the hits that landed.
local function avoidLines(p)
    local a = p.avoid
    if not a then
        tipLines[#tipLines + 1] = L["No details yet"]
        return
    end
    local att = avoided(p) + a.hits
    local function kind(i, label, n)
        if n > 0 then line(i, label, format("%d (%.1f%%)", n, att > 0 and n / att * 100 or 0)) end
    end
    kind(1, L["Dodged"],   a.dodge)
    kind(2, L["Parried"],  a.parry)
    kind(3, L["Blocked"],  a.block)
    kind(4, L["Missed"],   a.miss)
    kind(5, L["Absorbed"], a.absorb)
    kind(6, L["Resisted"], a.resist)
    kind(7, L["Immune"],   a.immune)
    line(8, L["Hits taken"], format("%d", a.hits))
    if a.blocked > 0 or a.absorbed > 0 or a.resisted > 0 then
        tipLines[#tipLines + 1] = " "
        tipLines[#tipLines + 1] = L["Taken off landed hits"]
        if a.blocked  > 0 then line(9,  L["Blocked"],  short(a.blocked))  end
        if a.absorbed > 0 then line(10, L["Absorbed"], short(a.absorbed)) end
        if a.resisted > 0 then line(11, L["Resisted"], short(a.resisted)) end
    end
end

-- Aura uptime: seconds per aura against the fight, as a share.
local function uptimeLines(p, key, dur, seg, guid)
    local t = auraSeconds(seg, p, guid, key)
    local n = 0
    if t then
        for id, v in pairs(t) do
            if v > 0 then
                n = n + 1
                sortIds[n] = id
            end
        end
    end
    for i = n + 1, #sortIds do sortIds[i] = nil end
    if n == 0 then
        tipLines[#tipLines + 1] = L["No details yet"]
        return
    end
    sortSrc = t
    sort(sortIds, byCount)
    local rows = min(n, mod.db.tooltipRows or 5)
    for i = 1, rows do
        local id = sortIds[i]
        local v = min(t[id], dur > 0 and dur or t[id])
        line(i, spellText(id), format("%.0f%%", dur > 0 and v / dur * 100 or 0))
    end
end

local function threatStatus(p)
    if p.tanking or (p.status or 0) >= 2 then return L["Tanking"] end
    if p.status == 1 then return L["Above the tank"] end
    return L["Safe"]
end

-- A row of the breakdown: the spell's hit statistics.
local STAT_KEY = { damage = "spellStats", dps = "spellStats", heal = "healStats", hps = "healStats" }
local function spellStatTip(self, w, seg)
    local p    = seg and seg.players[w.detail]
    local key  = STAT_KEY[w.mode]
    local id   = self.spellId
    local e    = p and key and p[key] and p[key][id]
    local name = type(id) == "number" and GetSpellInfo(id) or spellText(id)
    wipe(tipLines)
    if not e or e.n == 0 then
        tipLines[#tipLines + 1] = L["No details yet"]
    else
        line(1, L["Hits"], format("%d", e.n))
        line(2, L["Critical"], format("%d (%.1f%%)", e.c, e.c / e.n * 100))
        -- The stats count raw amounts (a heal before overhealing is taken
        -- off), so the average is theirs and min and max bracket it.
        line(3, L["Average"], short(e.n > 0 and (e.sum or 0) / e.n or 0))
        line(4, L["Minimum"], short(e.min))
        line(5, L["Maximum"], short(e.max))
    end
    tipSpec.title = name or "?"
    local c = p and ns.ClassColor(p.class)
    if c then
        tipColor[1], tipColor[2], tipColor[3] = c.r, c.g, c.b
        tipSpec.color = tipColor
    else
        tipSpec.color = nil
    end
    UI:ShowTooltip(self, tipSpec)
end

rowEnter = function(self)
    local w   = self.win
    local seg = segmentOf(w)
    if w.detail and self.spellId then
        if STAT_KEY[w.mode] then return spellStatTip(self, w, seg) end
        return
    end
    local set = rowsOf(seg, w.mode)
    local p   = set and self.guid and set[self.guid]
    if not p then return end
    local mode  = w.mode
    local vals  = w.vals
    local order = w.order
    local v     = vals[self.guid] or 0
    local total = 0
    for i = 1, #order do total = total + (vals[order[i]] or 0) end

    wipe(tipLines)
    if mode == "threat" then
        tipLines[#tipLines + 1] = format("%s: %s", L["Threat"], short(v))
        tipLines[#tipLines + 1] = format("%s: %.0f%%", L["Percent of tank"], p.pct or 0)
        tipLines[#tipLines + 1] = threatStatus(p)
        tipSpec.title = p.name
        local c = ns.ClassColor(p.class)
        if c then
            tipColor[1], tipColor[2], tipColor[3] = c.r, c.g, c.b
            tipSpec.color = tipColor
        else
            tipSpec.color = nil
        end
        UI:ShowTooltip(self, tipSpec)
        return
    end
    local dur     = Meter:Duration(seg)
    local isCount = COUNT[mode]
    -- the spec first: it is what the icon on the bar just claimed
    if mode ~= "enemies" then
        local tree = Meter.SpecOf and Meter:SpecOf(self.guid)
        local _, specName = tree and Meter:SpecInfo(p.class, tree)
        if specName then tipLines[#tipLines + 1] = format("%s: %s", L["Spec"], specName) end
    end
    if mode == "deaths" then
        deathLines(p)
    elseif mode == "enemies" then
        attackerLines(p, seg)
    elseif mode == "avoidance" then
        avoidLines(p)
    elseif UPTIME[mode] then
        uptimeLines(p, SUB_KEY[mode], dur, seg, self.guid)
    elseif mode == "mana" then
        spellLines(p, "gains", p.mana or 0, false)
    else
        -- shares of ALL the damage: the per-spell and per-target tables hold
        -- everything, whatever the boss filter shows on the bar
        local own = HEALING[mode] and (p.heal - p.overheal)
                 or (mode == "taken" and (p.taken or 0))
                 or p.damage
        spellLines(p, SUB_KEY[mode], own, isCount)
        if HEALING[mode] then
            targetLines(p, "healed", own)
        elseif mode == "damage" or mode == "dps" then
            targetLines(p, "targets", own)
        end
    end
    tipLines[#tipLines + 1] = " "

    if isCount then
        tipLines[#tipLines + 1] = format("%s: %d", L["Total"], v)
    else
        local amount = PER_SEC[mode] and (mode == "dps" and damageOf(p) or (p.heal - p.overheal)) or v
        tipLines[#tipLines + 1] = format("%s: %s", L["Total"], short(amount))
        tipLines[#tipLines + 1] = format("%s: %s", L["Per second"], short(dur > 0 and amount / basisOf(p, dur) or 0))
        if mode ~= "taken" and mode ~= "enemies" then
            local active = Meter:ActiveTime(seg, p)
            tipLines[#tipLines + 1] = format("%s: %s (%.0f%%)", L["Active time"], clock(active),
                dur > 0 and active / dur * 100 or 0)
        end
    end
    tipLines[#tipLines + 1] = format("%s: %.1f%%", L["Share"], total > 0 and v / total * 100 or 0)
    if HEALING[mode] then
        tipLines[#tipLines + 1] = format("%s: %.1f%%", L["Overhealing"], p.heal > 0 and p.overheal / p.heal * 100 or 0)
    end
    tipLines[#tipLines + 1] = format("%s: %s", L["Fight duration"], clock(dur))

    tipSpec.title = p.name
    local c = ns.ClassColor(p.class)
    if c then
        tipColor[1], tipColor[2], tipColor[3] = c.r, c.g, c.b
        tipSpec.color = tipColor
    elseif mode == "enemies" then
        tipColor[1], tipColor[2], tipColor[3] = 0.9, 0.35, 0.35
        tipSpec.color = tipColor
    else
        tipSpec.color = nil
    end
    UI:ShowTooltip(self, tipSpec)
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------
local function rowSlots(w)
    local db = mod.db
    local h = w.db.height - TITLE_H - PAD * 2
    if w.graphShown then h = h - GRAPH_H - 2 end
    return max(1, floor(h / (db.barHeight + db.barGap)))
end

-- Bars glide to their new length: the target is stored, an OnUpdate on the
-- body walks every visible bar towards it and switches itself off once all
-- have arrived. A bar handed to another player snaps, so no length ever
-- slides from one name to the next.
local function animate(w)
    local body = w.frame.body
    if body._anim then return end
    body._anim = true
    body:SetScript("OnUpdate", function(self, dt)
        local rows, active = w.rows, false
        local k = min(1, (dt or 0.016) * 12)
        for i = 1, #rows do
            local r = rows[i]
            local tgt = r._target
            if tgt and r:IsShown() then
                local cur = r._cur or tgt
                local d = tgt - cur
                if d > 0.002 or d < -0.002 then
                    cur = cur + d * k
                    active = true
                else
                    cur = tgt
                end
                r._cur = cur
                r:SetValue(cur)
            end
        end
        if not active then
            self:SetScript("OnUpdate", nil)
            self._anim = nil
        end
    end)
end

local function setBarValue(w, r, v, snap)
    r._target = v
    if snap or not mod.db.smoothBars then
        r._cur = v
        r:SetValue(v)
        return
    end
    if r._cur == nil then
        r._cur = v
        r:SetValue(v)
        return
    end
    animate(w)
end

local function texturePath()
    return ns.MediaStatusbar(mod.db.texture)
end

local function onWheel(w, delta)
    w.scroll = max(0, w.scroll - delta)
    refresh(w)
end

local function showIcons()
    return mod.db.barIcon ~= "off"
end

-- The bar colour: the player's class, or the one colour the option names.
local function barColor(r, class, fallbackR, fallbackG, fallbackB)
    local db = mod.db
    if db.barColorMode == "custom" and type(db.barColor) == "table" then
        local c = db.barColor
        r:SetStatusBarColor(c.r or 0.6, c.g or 0.6, c.b or 0.6, 0.85)
        return
    end
    local c = ns.ClassColor(class)
    if c then
        r:SetStatusBarColor(c.r, c.g, c.b, 0.85)
    else
        r:SetStatusBarColor(fallbackR, fallbackG, fallbackB, 0.85)
    end
end

-- Rows hang from the top of the body, or stand on its bottom when the bars
-- grow upwards; the title bar sits on the same edge the rows start from.
local function placeRow(w, r, i, step, inset)
    local body = w.frame.body
    inset = inset or 0
    r:ClearAllPoints()
    if mod.db.growUp then
        r:SetPoint("BOTTOMLEFT",  body, "BOTTOMLEFT",  inset, (i - 1) * step)
        r:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, (i - 1) * step)
    else
        -- the timeline strip, when shown, takes the top of the body
        local gy = w.graphShown and (GRAPH_H + 2) or 0
        r:SetPoint("TOPLEFT",  body, "TOPLEFT",  inset, -((i - 1) * step) - gy)
        r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -((i - 1) * step) - gy)
    end
end

local function layoutChrome(w)
    local win, title, body = w.frame, w.frame.title, w.frame.body
    title:ClearAllPoints()
    body:ClearAllPoints()
    if mod.db.growUp then
        title:SetPoint("BOTTOMLEFT",  win, "BOTTOMLEFT",  0, 0)
        title:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
        body:SetPoint("TOPLEFT",     win, "TOPLEFT",     PAD, -PAD)
        body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, TITLE_H + PAD)
    else
        title:SetPoint("TOPLEFT",  win, "TOPLEFT",  0, 0)
        title:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
        body:SetPoint("TOPLEFT",     win, "TOPLEFT",     PAD, -(TITLE_H + PAD))
        body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, PAD)
    end
    local db = mod.db
    local c = type(db.bgColor) == "table" and db.bgColor or { r = 0.05, g = 0.05, b = 0.06 }
    local a = (tonumber(db.bgAlpha) or 90) / 100
    win.bg:SetColorTexture(c.r or 0.05, c.g or 0.05, c.b or 0.06, a)
end

local function createRow(w)
    local r = CreateFrame("StatusBar", nil, w.frame.body)
    r.win = w
    r:SetMinMaxValues(0, 1)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints(r)
    r.bg:SetColorTexture(1, 1, 1, 0.05)
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetPoint("LEFT", r, "LEFT", 1, 0)
    -- The icon's own framed square left of the bar (option): the bar starts
    -- after it, the way the big meters draw their rows.
    r.box = CreateFrame("Frame", nil, r, BackdropTemplateMixin and "BackdropTemplate")
    r.box:SetPoint("RIGHT", r, "LEFT", -3, 0)
    if r.box.SetBackdrop then
        r.box:SetBackdrop({ bgFile = TEX_FLAT, edgeFile = TEX_FLAT, edgeSize = 1 })
        r.box:SetBackdropColor(0, 0, 0, 0.6)
        r.box:SetBackdropBorderColor(0, 0, 0, 0.9)
    end
    r.boxIcon = r.box:CreateTexture(nil, "ARTWORK")
    r.boxIcon:SetPoint("TOPLEFT",     r.box, "TOPLEFT",     1, -1)
    r.boxIcon:SetPoint("BOTTOMRIGHT", r.box, "BOTTOMRIGHT", -1, 1)
    r.box:Hide()
    r.left = r:CreateFontString(nil, "OVERLAY")
    r.left:SetJustifyH("LEFT")
    r.left:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY")
    r.right:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.right:SetJustifyH("RIGHT")
    r.left:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
    r.hl = CreateFrame("Frame", nil, r, BackdropTemplateMixin and "BackdropTemplate")
    r.hl:SetAllPoints(r)
    if r.hl.SetBackdrop then
        r.hl:SetBackdrop({ edgeFile = TEX_FLAT, edgeSize = 1 })
        local a = ns.COLORS.accent
        r.hl:SetBackdropBorderColor(a.r, a.g, a.b, 0.9)
    end
    r.hl:Hide()
    r:EnableMouse(true)
    r:EnableMouseWheel(true)
    r:SetScript("OnEnter", rowEnter)
    r:SetScript("OnLeave", function() UI:HideTooltip() end)
    r:SetScript("OnMouseWheel", function(self, delta) onWheel(self.win, delta) end)
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function(self) dragStart(self.win) end)
    r:SetScript("OnDragStop",  function(self) dragStop(self.win) end)
    r:SetScript("OnMouseUp", function(self, btn) onRowClick(self, btn) end)
    return r
end

layoutRows = function(w)
    local db   = mod.db
    local n    = rowSlots(w)
    local tex  = texturePath()
    local step = db.barHeight + db.barGap
    local iconSize = max(1, db.barHeight - 2)
    local icons    = showIcons()
    local box      = icons and db.iconBox
    local textLeft = (icons and not box) and (iconSize + 4) or 4
    local inset    = box and (db.barHeight + 3) or 0
    local rows = w.rows
    for i = 1, n do
        local r = rows[i]
        if not r then
            r = createRow(w)
            rows[i] = r
        end
        r:SetStatusBarTexture(tex)
        local t = r:GetStatusBarTexture()
        if t and t.SetHorizTile then
            t:SetHorizTile(false)
            t:SetVertTile(false)
        end
        r:SetHeight(db.barHeight)
        placeRow(w, r, i, step, inset)
        r.icon:SetSize(iconSize, iconSize)
        r.icon:SetShown(icons and not box)
        r.box:SetSize(db.barHeight, db.barHeight)
        r.box:SetShown(box and true or false)
        r._cur = nil   -- a re-laid row snaps to its next value
        r.left:SetPoint("LEFT", r, "LEFT", textLeft, 0)
        UI.FontFor("meter", r.left,  db.fontSize)
        UI.FontFor("meter", r.right, db.fontSize)
        r.class = nil   -- never equals a class token or false: next paint repaints
        r:Hide()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
end

------------------------------------------------------------------------
-- Refresh: sort once, paint the visible slots, update the title.
------------------------------------------------------------------------
local function setTitle(w, seg, first, lastIdx, n)
    local win = w.frame
    local t
    if w.detail then
        local p = seg and seg.players[w.detail]
        t = ((p and p.name) or "?") .. " \194\183 " .. modeLabel(w.mode)
    else
        t = modeLabel(w.mode) .. " \194\183 " .. segmentLabel(w, seg)
    end
    if t ~= w.lastTitle then
        win.titleText:SetText(t)
        w.lastTitle = t
    end
    local c = ""
    if n > 0 and n > (lastIdx - first + 1) then
        c = format("%d-%d / %d", first, lastIdx, n)
    end
    if c ~= w.lastCount then
        win.count:SetText(c)
        w.lastCount = c
    end
end

-- The icon: the class, or the tree the player has been seen to play; the
-- class stays the fallback while the tree is unknown. r.class caches the
-- pair, so an unchanged row costs one comparison.
local function paintClass(r, p, db, guid)
    if not showIcons() then return end
    local cls  = p.class or false
    local tree = (db.barIcon == "spec" and cls and guid and Meter.SpecOf) and Meter:SpecOf(guid) or nil
    local box  = db.iconBox
    local key  = (box and "b" or "i") .. (tree and (cls .. tree) or tostring(cls))
    if r.class == key then return end
    r.class = key
    local target = box and r.boxIcon or r.icon
    if tree then
        local icon = Meter:SpecInfo(p.class, tree)
        if icon then
            target:SetTexture(icon)
            target:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            target:Show()
            return
        end
    end
    local tex, coords = ns:GetClassIcon(p.class)
    if tex then
        target:SetTexture(tex)
        target:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        target:Show()
    elseif not cls then
        -- an enemy row: the skull marker, so the icon slot is never empty
        target:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
        target:SetTexCoord(0, 1, 0, 1)
        target:Show()
    else
        target:Hide()
    end
end

------------------------------------------------------------------------
-- Timeline strip: the player's damage or healing per five-second bucket
-- of the fight, above the breakdown. Long fights fold several buckets into
-- one bar so the strip never grows past the window.
------------------------------------------------------------------------
local function ensureGraph(w)
    local g = w.frame.graph
    if g then return g end
    local body = w.frame.body
    g = CreateFrame("Frame", nil, body)
    g:SetPoint("TOPLEFT",  body, "TOPLEFT",  0, 0)
    g:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    g:SetHeight(GRAPH_H)
    g.bg = g:CreateTexture(nil, "BACKGROUND")
    g.bg:SetAllPoints(g)
    g.bg:SetColorTexture(1, 1, 1, 0.04)
    g.label = g:CreateFontString(nil, "OVERLAY")
    UI.FontFor("meter", g.label, 9)
    g.label:SetPoint("TOPLEFT", g, "TOPLEFT", 3, -2)
    g.label:SetTextColor(0.6, 0.6, 0.65)
    g.bars = {}
    g:Hide()
    w.frame.graph = g
    return g
end

local function drawGraph(w, seg, p)
    local key = TL_KEY[w.mode]
    local tl  = key and p and p[key]
    local g   = ensureGraph(w)
    -- the overall has no clock; a history fight and the running one do
    if not tl or seg == Meter:GetSegment("overall") then g:Hide(); return false end
    local dur = Meter:Duration(seg)
    if dur <= 0 then g:Hide(); return false end
    local step  = Meter.TL_STEP or 5
    local n     = max(1, math.ceil(dur / step))
    local width = w.frame.body:GetWidth() or 0
    if width < 10 then width = (w.db.width or 220) - 2 * PAD end
    -- at least two pixels per bar: fold buckets when the fight is long
    local k    = max(1, math.ceil(n / floor(width / 2)))
    local bars = math.ceil(n / k)
    local bw   = max(1, floor(width / bars))
    local top, peak = 0, 0
    for b = 1, n do
        local v = tl[b] or 0
        if v > peak then peak = v end
    end
    local c = ns.ClassColor(p.class) or { r = 0.6, g = 0.6, b = 0.6 }
    local inner = GRAPH_H - 14
    for i = 1, bars do
        local v = 0
        for b = (i - 1) * k + 1, min(n, i * k) do v = v + (tl[b] or 0) end
        if v > top then top = v end
    end
    for i = 1, bars do
        local t = g.bars[i]
        if not t then
            t = g:CreateTexture(nil, "ARTWORK")
            g.bars[i] = t
        end
        local v = 0
        for b = (i - 1) * k + 1, min(n, i * k) do v = v + (tl[b] or 0) end
        local h = top > 0 and max(1, floor(inner * v / top)) or 1
        t:SetColorTexture(c.r, c.g, c.b, 0.85)
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", (i - 1) * bw, 1)
        t:SetSize(max(1, bw - 1), h)
        t:Show()
    end
    for i = bars + 1, #g.bars do g.bars[i]:Hide() end
    g.label:SetFormattedText("%s  |cffffffff%s|r / %ds", modeLabel(w.mode), short(peak), step)
    g:Show()
    return true
end

------------------------------------------------------------------------
-- Detail view: a left-click on a bar turns the window into that player's
-- ability list for the current mode (right-click or a click on the title
-- goes back). Window state only, never saved; any mode or segment change
-- and every reset drop it.
------------------------------------------------------------------------
local function refreshDetail(w, seg)
    local db    = mod.db
    local mode  = w.mode
    local order = w.order
    local vals  = w.vals
    local rows  = w.rows
    local p     = seg and seg.players[w.detail]
    local key   = SUB_KEY[mode]
    local t     = p and key and p[key]
    if t and UPTIME[mode] then t = auraSeconds(seg, p, w.detail, key) end
    if not t then
        w.detail = nil
        return false
    end
    w._wasDetail = true
    -- the timeline strip claims the top of the body while it has something to draw
    local wantGraph = drawGraph(w, seg, p)
    if wantGraph ~= (w.graphShown or false) then
        w.graphShown = wantGraph
        layoutRows(w)
    end
    local dur = Meter:Duration(seg)
    local n = 0
    for i = 1, #order do order[i] = nil end
    for id, v in pairs(t) do
        if v > 0 then
            n = n + 1
            order[n] = id
            vals[id] = v
        end
    end
    if n == 0 then
        for i = 1, #rows do rows[i]:Hide() end
        setTitle(w, seg, 0, 0, 0)
        return true
    end
    sortSrc = vals
    sort(order, byCount)
    local slots = rowSlots(w)
    local maxScroll = max(0, n - slots)
    if w.scroll > maxScroll then w.scroll = maxScroll end
    local scroll = w.scroll
    local total = 0
    for i = 1, n do total = total + vals[order[i]] end
    local top = vals[order[1]]
    local isCount = COUNT[mode]
    for i = 1, slots do
        local r   = rows[i]
        local idx = i + scroll
        local id  = order[idx]
        if r and id then
            local v = vals[id]
            local changed = r.spellId ~= id
            setBarValue(w, r, top > 0 and v / top or 0, changed)
            barColor(r, p.class, 0.6, 0.6, 0.6)
            r.icon:Hide()
            r.class = nil
            r.spellId = id
            -- in the framed square the spell's own icon takes the class's place
            if r.box:IsShown() then
                local icon
                if type(id) == "number" then icon = select(3, GetSpellInfo(id)) end
                if icon then
                    r.boxIcon:SetTexture(icon)
                    r.boxIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    r.boxIcon:Show()
                else
                    r.boxIcon:Hide()
                end
            end
            r.left:SetPoint("LEFT", r, "LEFT", 4, 0)
            if db.showRank then
                r.left:SetFormattedText("%d. %s", idx, spellText(id))
            else
                r.left:SetText(spellText(id))
            end
            if UPTIME[mode] then
                r.right:SetFormattedText("%.0f%%", dur > 0 and min(v, dur) / dur * 100 or 0)
            elseif isCount then
                r.right:SetFormattedText("%d", v)
            else
                r.right:SetFormattedText("%s (%.1f%%)", short(v), total > 0 and v / total * 100 or 0)
            end
            r.hl:Hide()
            r.guid = nil
            r:Show()
            -- a re-sort can move another spell under the cursor
            if changed and r:IsMouseOver() then rowEnter(r) end
        elseif r then
            r.guid = nil
            r.spellId = nil
            r:Hide()
        end
    end
    setTitle(w, seg, scroll + 1, min(scroll + slots, n), n)
    return true
end

onRowClick = function(r, btn)
    local w = r.win
    if not w.db or justDragged(w) then return end
    if btn == "RightButton" then
        if w.detail then
            w.detail = nil
            w.scroll = 0
            layoutRows(w)
            refresh(w)
        end
        return
    end
    if btn ~= "LeftButton" or w.detail or not r.guid then return end
    if not SUB_KEY[w.mode] then return end
    w.detail = r.guid
    w.scroll = 0
    UI:HideTooltip()
    refresh(w)
end

refresh = function(w)
    if not w.db then return end
    local db    = mod.db
    local mode  = w.mode
    local order = w.order
    local vals  = w.vals
    local rows  = w.rows
    local seg   = segmentOf(w)
    local n     = 0
    local dur   = 0
    if w.detail and refreshDetail(w, seg) then return end
    if w._wasDetail then
        -- back from the detail list: the rows need their class icon slot again,
        -- and the timeline strip goes with the list it belonged to
        w._wasDetail = nil
        w.graphShown = false
        if w.frame.graph then w.frame.graph:Hide() end
        layoutRows(w)
    end
    local set = rowsOf(seg, mode)
    if set then
        dur = (mode ~= "threat") and Meter:Duration(seg) or 0
        for guid, p in pairs(set) do
            n = n + 1
            order[n] = guid
            vals[guid] = valueOf(mode, p, dur, seg, guid)
        end
    end
    for i = n + 1, #order do order[i] = nil end

    if n == 0 then
        for i = 1, #rows do rows[i]:Hide() end
        setTitle(w, seg, 0, 0, 0)
        return
    end
    sortVals = vals
    sort(order, byValue)
    local slots = rowSlots(w)
    local maxScroll = max(0, n - slots)
    if w.scroll > maxScroll then w.scroll = maxScroll end
    local scroll = w.scroll

    local total = 0
    for i = 1, n do total = total + vals[order[i]] end
    local top = vals[order[1]]
    local me  = Meter:PlayerGUID()

    -- Own bar pinned: scrolled out above, it takes the top slot; scrolled
    -- out below, the bottom slot -- with its real rank, so the window still
    -- says where you stand.
    local pinIdx, pinSlot
    if db.pinSelf and me and mode ~= "enemies" and slots < n then
        for i = 1, n do
            if order[i] == me then pinIdx = i; break end
        end
        if pinIdx then
            if pinIdx <= scroll then pinSlot = 1
            elseif pinIdx > scroll + slots then pinSlot = slots
            else pinIdx = nil end
        end
    end

    for i = 1, slots do
        local r    = rows[i]
        local idx  = i + scroll
        if pinSlot == i then idx = pinIdx end
        local guid = order[idx]
        if r and guid then
            local p = set[guid]
            local v = vals[guid]
            local changed = r.guid ~= guid
            setBarValue(w, r, top > 0 and v / top or 0, changed)
            if mode == "enemies" then
                barColor(r, p.class, 0.75, 0.25, 0.25)
            else
                barColor(r, p.class, 0.6, 0.6, 0.6)
            end
            r.spellId = nil
            paintClass(r, p, db, guid)
            if db.showRank then
                r.left:SetFormattedText("%d. %s", idx, p.name)
            else
                r.left:SetText(p.name)
            end
            r.right:SetText(rightText(mode, p, v, total, dur))
            r.hl:SetShown(db.highlightSelf and guid == me)
            r.guid = guid
            r:Show()
            -- A re-sort can move another player under the cursor; OnEnter does
            -- not fire again, so refresh the tooltip by hand.
            if changed and r:IsMouseOver() then rowEnter(r) end
        elseif r then
            r.guid = nil
            r:Hide()
        end
    end
    setTitle(w, seg, scroll + 1, min(scroll + slots, n), n)
end

local function refreshAll()
    for i = 1, #frames do refresh(frames[i]) end
end

------------------------------------------------------------------------
-- Ticker: only while a fight is open. Dirty -> full repaint; otherwise the
-- per-second windows still move with the clock.
------------------------------------------------------------------------
local function tick()
    local dirty = Meter:IsDirty()
    if dirty then Meter:ClearDirty() end
    for i = 1, #frames do
        local w = frames[i]
        -- threat windows repaint from their own events, never from the log
        if w.mode ~= "threat" and (dirty or PER_SEC[w.mode]) then refresh(w) end
    end
end

local function startTicker()
    if ticker then return end
    ticker = ns:AddTicker(0.5, tick, nil, "meter-window")
end

local function stopTicker()
    if ticker then
        ns:CancelTicker(ticker)
        ticker = nil
    end
end

local function resetScroll()
    for i = 1, #frames do frames[i].scroll = 0 end
end

------------------------------------------------------------------------
-- Threat windows: driven by the threat events, not the fight ticker. The
-- events are registered only while a bound window is in threat mode; a
-- raid fires UNIT_THREAT_LIST_UPDATE constantly and nobody should pay for
-- a mode they are not looking at. Events set a flag, one 0.25 s collector
-- snapshots and repaints; a target change repaints at once.
------------------------------------------------------------------------
local threatArmed   = false
local threatPending = false

local function refreshThreat()
    threatPending = false
    if not mod.active then return end
    Meter:ThreatSnapshot()
    for i = 1, #frames do
        local w = frames[i]
        if w.db and w.mode == "threat" then refresh(w) end
    end
end

local function threatSoon()
    if threatPending then return end
    threatPending = true
    C_Timer.After(0.25, refreshThreat)
end

local function onThreatList(_, unit)
    -- The mob's list changed; only our target's list is on screen. The unit
    -- token is whichever one the client saw the mob under (nameplate, boss,
    -- target itself), so compare identity instead of the token.
    if unit and UnitIsUnit(unit, "target") then threatSoon() end
end

local function onThreatSituation()
    threatSoon()
end

local function onTargetChanged()
    threatPending = false
    refreshThreat()
end

syncThreatEvents = function()
    local want = false
    if Meter.HAS_THREAT and mod.active then
        for i = 1, #frames do
            local w = frames[i]
            if w.db and w.mode == "threat" then want = true; break end
        end
    end
    if want == threatArmed then return end
    threatArmed = want
    if want then
        ns:RegisterEvent("UNIT_THREAT_LIST_UPDATE",      onThreatList)
        ns:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE", onThreatSituation)
        ns:RegisterEvent("PLAYER_TARGET_CHANGED",        onTargetChanged)
        refreshThreat()
    else
        ns:UnregisterEvent("UNIT_THREAT_LIST_UPDATE",      onThreatList)
        ns:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE", onThreatSituation)
        ns:UnregisterEvent("PLAYER_TARGET_CHANGED",        onTargetChanged)
    end
end

local function onEngine(what)
    if what == "start" then
        resetScroll()
        -- A window the fight's end moved to the overall comes back for the pull.
        for i = 1, #frames do
            local w = frames[i]
            if w._autoOverall then
                w._autoOverall = nil
                if w.db then w.segment = w.db.segment end
            end
        end
        -- Option: a window parked on an old fight comes back for the pull.
        if mod.db.autoCurrent then
            for i = 1, #frames do
                local w = frames[i]
                if w.db and type(w.segment) == "table" then
                    w.segment = w.db.segment
                    w.detail  = nil
                end
            end
        end
        -- No immediate paint: the segment is still empty, the first tick fills it.
        startTicker()
        applyVisibility()
    elseif what == "end" then
        stopTicker()
        lastCombatEnd = GetTime()
        -- Option: after the fight the current-fight windows show the overall.
        if mod.db.autoSegment then
            for i = 1, #frames do
                local w = frames[i]
                if w.db and w.segment == "current" then
                    w.segment = "overall"
                    w._autoOverall = true
                    w.scroll = 0
                    w.detail = nil   -- a breakdown of the fight is not one of the overall
                end
            end
        end
        Meter:ClearDirty()
        refreshAll()
        applyVisibility()
        wipe(fmtCache)
        fmtCount = 0
    elseif what == "repaint" then
        -- something outside the log changed a bar (a spec learned out of
        -- combat): repaint without touching scroll or detail state
        Meter:ClearDirty()
        refreshAll()
    else
        resetScroll()
        for i = 1, #frames do frames[i].detail = nil end
        Meter:ClearDirty()
        refreshAll()
    end
end

------------------------------------------------------------------------
-- Windows: the list in mod.db.windows and the frames bound to it
------------------------------------------------------------------------
local function newWindowDB(mode, segment, x, y, width, height, scale, unlocked)
    return { mode = MODE_IDX[mode] and mode or "damage",
             segment = (segment == "overall") and "overall" or "current",
             x = x or 0, y = y or 0, width = width or 220, height = height or 160,
             scale = scale or 1, unlocked = unlocked and true or false,
             locked = true }
end

-- Empty list (fresh profile, or one written by part 1): window 1 inherits
-- the single-window fields part 1 kept on the module, which then go away.
local function ensureWindows()
    local db = mod.db
    if type(db.windows) ~= "table" then db.windows = {} end
    local list = db.windows
    if #list == 0 then
        list[1] = newWindowDB(db.defaultMode, db.defaultSegment, db.x, db.y,
                              db.width, db.height, db.scale, db.unlocked)
        db.x, db.y, db.width, db.height, db.scale, db.unlocked = nil, nil, nil, nil, nil, nil
        db.defaultMode, db.defaultSegment = nil, nil
    end
    for i = 1, #list do
        local e = list[i]
        if type(e) ~= "table" then
            e = newWindowDB()
            list[i] = e
        end
        if not MODE_IDX[e.mode] then e.mode = "damage" end
        if e.segment ~= "overall" then e.segment = "current" end
        e.x, e.y = e.x or 0, e.y or 0
        e.width, e.height = e.width or 220, e.height or 160
        e.scale = e.scale or 1
        if e.locked == nil then e.locked = true end
    end
    return list
end

function mod:AddWindow(mode, fromIndex)
    local list = ensureWindows()
    local src  = list[fromIndex] or list[#list]
    list[#list + 1] = newWindowDB(mode, src.segment, src.x + 30, src.y - 30,
                                  src.width, src.height, src.scale, false)
    if mod.active then syncFrames() end
    pageChanged()
end

-- Mover keys are slot numbers, so closing a window shifts every key above it.
-- Links stored under the old keys (as child or as parent) move with the
-- window; links to the closed window are dropped.
local function remapLinks(removed)
    local p = ns.db and ns.db.profile
    local store = p and p.moverLinks
    if type(store) ~= "table" then return end
    local function shift(key)
        local i = type(key) == "string" and tonumber(key:match("^meter(%d+)$"))
        if not i then return key, false end
        if i == removed then return nil, true end
        if i > removed then return "meter" .. (i - 1), true end
        return key, true
    end
    local moved = {}
    for key, link in pairs(store) do
        local nk, isMeter = shift(key)
        local nt, toMeter = shift(type(link) == "table" and link.to or nil)
        if isMeter or toMeter then
            store[key] = nil
            if nk and nt then
                link.to   = nt
                moved[nk] = link
            end
        end
    end
    for key, link in pairs(moved) do store[key] = link end

    -- Size links (edit mode "width like / height like") use the same keys.
    local sizes = p.moverSizeLinks
    if type(sizes) ~= "table" then return end
    local movedSizes = {}
    for key, e in pairs(sizes) do
        local nk, isMeter = shift(key)
        local nw, wMeter = shift(type(e) == "table" and e.w or nil)
        local nh, hMeter = shift(type(e) == "table" and e.h or nil)
        if isMeter or wMeter or hMeter then
            sizes[key] = nil
            if nk then
                e.w, e.h = nw, nh
                if e.w or e.h then movedSizes[nk] = e end
            end
        end
    end
    for key, e in pairs(movedSizes) do sizes[key] = e end
end

function mod:CloseWindow(index)
    local list = ensureWindows()
    if #list <= 1 or not list[index] then return end
    remove(list, index)
    remapLinks(index)
    if mod.active then
        syncFrames()
        ns:ApplyAllMoverLinks()
    end
    pageChanged()
end

function mod:ToggleLock(index)
    local w = frames[index]
    if not (w and w.db) then return end
    w.db.locked = not w.db.locked
    if w.paintLock then w.paintLock() end
end

-- quiet: called from the options page itself, which must not be rebuilt
-- under the pointer by its own dropdown.
function mod:SetMode(index, m, quiet)
    if not MODE_IDX[m] then return end
    local w = frames[index]
    if not (w and w.db) then return end
    w.db.mode = m
    w.mode    = m
    w.scroll  = 0
    w.detail  = nil
    syncThreatEvents()
    refresh(w)
    if not quiet then pageChanged() end
end

-- s is "current", "overall", or a finished fight's table from the history.
-- A fight pick lives only in the window record: the history does not survive
-- a reload, so the saved choice stays what it was. A plain choice always
-- clears a fight pick, so the options dropdown can leave one again.
function mod:SetSegment(index, s, quiet)
    local w = frames[index]
    if not (w and w.db) then return end
    if type(s) == "table" then
        if not Meter:HistoryIndex(s) then return end
        w.segment = s
    else
        s = (s == "overall") and "overall" or "current"
        w.db.segment = s
        w.segment    = s
    end
    w._autoOverall = nil   -- a chosen segment is not one the fight's end may take back
    w.scroll = 0
    w.detail = nil
    refresh(w)
    if not quiet then pageChanged() end
end

-- Wheel up = previous mode, wheel down = next, wrapping around.
local function onTitleWheel(w, delta)
    local i = MODE_IDX[w.mode] - delta
    if i < 1 then i = #MODES elseif i > #MODES then i = 1 end
    mod:SetMode(w.index, MODES[i])
end

-- Docking uses the framework's mover links, so an anchored window also shows
-- up as linked in edit mode and follows whenever its parent moves.
local SIDES = { "BOTTOM", "TOP", "LEFT", "RIGHT" }
local function sideLabel(side)
    if side == "BOTTOM" then return L["Below"] end
    if side == "TOP"    then return L["Above"] end
    if side == "LEFT"   then return L["Left"] end
    return L["Right"]
end

local function dock(w, parentKey, side)
    local m = w.mover
    if not parentKey then
        ns:SetMoverLink(m, nil)
        return
    end
    -- SetMoverLink measures the current distance; the side call then docks
    -- flush, and the apply/reposition pair moves the window onto its edge
    -- before its own followers are carried along (order matters, see Core).
    if ns:SetMoverLink(m, parentKey, side) and ns:SetMoverLinkSide(m, side, 0) then
        ns:ApplyMoverLink(m)
        ns:OnMoverRepositioned(m)
    elseif ns.FlashMoverReject then
        ns:FlashMoverReject(m, L["Not possible - that would create a loop."])
    end
end

local function anchorEntries(w)
    local key = "meter" .. w.index
    local e = { { text = L["None"],
                  checked = function() return not ns:GetMoverLink(key) end,
                  func = function() dock(w, nil) end } }
    for j = 1, #frames do
        local o = frames[j]
        if o ~= w and o.db then
            local pkey = "meter" .. j
            for i = 1, #SIDES do
                local side = SIDES[i]
                e[#e + 1] = {
                    text = format(L["Combat Meter %d"], j) .. " \194\183 " .. sideLabel(side),
                    checked = function()
                        local l = ns:GetMoverLink(key)
                        return l and l.to == pkey and l.side == side
                    end,
                    func = function() dock(w, pkey, side) end,
                }
            end
        end
    end
    return e
end

------------------------------------------------------------------------
-- Chat report: the window's sorted list, header plus the top N rows, one
-- chat line each. Reads w.order/w.vals as the last refresh left them, so
-- the report says exactly what the window shows.
------------------------------------------------------------------------
local function reportRight(mode, p, v, total, dur)
    if mode == "threat" then return format("%s (%.0f%%)", short(v), p.pct or 0) end
    if COUNT[mode] then return format("%d", v) end
    local pct = total > 0 and (v / total * 100) or 0
    local secondary
    if mode == "dps" then
        secondary = damageOf(p)
    elseif mode == "hps" then
        secondary = p.heal - p.overheal
    else
        secondary = dur > 0 and v / dur or 0
    end
    return format("%s (%s, %.1f%%)", short(v), short(secondary), pct)
end

local function sendReport(w, chatType, target)
    local seg = segmentOf(w)
    if not seg then return end
    if w.mode == "threat" then Meter:ThreatSnapshot() end
    -- the report is always the player list, never an open detail view
    local wasDetail = w.detail
    w.detail = nil
    refresh(w)   -- the list is as fresh as the window; a stale order would lie
    w.detail = wasDetail
    local order, vals = w.order, w.vals
    local n = #order
    if n == 0 then return end
    local mode  = w.mode
    local set   = rowsOf(seg, mode)
    local dur   = (mode ~= "threat") and Meter:Duration(seg) or 0
    local total = 0
    for i = 1, n do total = total + (vals[order[i]] or 0) end
    local head = "VuloClassicUI \194\183 " .. modeLabel(mode) .. " \194\183 " .. segmentLabel(w, seg)
    if mode ~= "threat" then head = head .. " (" .. clock(dur) .. ")" end
    SendChatMessage(head, chatType, nil, target)
    local rows = min(n, tonumber(mod.db.reportRows) or 10)
    for i = 1, rows do
        local guid = order[i]
        local p = set[guid]
        if p then
            SendChatMessage(format("%d. %s  %s", i, p.name, reportRight(mode, p, vals[guid] or 0, total, dur)),
                            chatType, nil, target)
        end
    end
end

-- Whisper asks for a name in a popup; the window index rides on the dialog.
local WHISPER_POPUP = "VCUI_METER_WHISPER"
local function whisperAccept(dialog)
    local box = ns.PopupEditBox(dialog)
    local name = box and box:GetText() or ""
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    local w = dialog.data and frames[dialog.data]
    if name == "" or not (w and w.db) then return end
    sendReport(w, "WHISPER", name)
end

local function promptWhisper(w)
    if not StaticPopupDialogs[WHISPER_POPUP] then
        StaticPopupDialogs[WHISPER_POPUP] = {
            text         = L["Whisper the report to whom?"],
            button1      = ACCEPT or "OK",
            button2      = CANCEL or "Cancel",
            hasEditBox   = true,
            maxLetters   = 48,
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(self) whisperAccept(self) end,
            EditBoxOnEnterPressed = function(self)
                local parent = self:GetParent()
                whisperAccept(parent)
                parent:Hide()
            end,
            EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        }
    end
    local dialog = StaticPopup_Show(WHISPER_POPUP)
    if dialog then dialog.data = w.index end
end

local function reportEntries(w)
    local inGroup = IsInGroup()
    local inRaid  = IsInRaid()
    local inGuild = IsInGuild()
    return {
        { text = L["Say"],   func = function() sendReport(w, "SAY") end },
        { text = L["Party"], disabled = not inGroup, func = function() sendReport(w, "PARTY") end },
        { text = L["Raid"],  disabled = not inRaid,  func = function() sendReport(w, "RAID") end },
        { text = L["Guild"], disabled = not inGuild, func = function() sendReport(w, "GUILD") end },
        { text = L["Officer"], disabled = not inGuild, func = function() sendReport(w, "OFFICER") end },
        { text = L["Whisper to..."], func = function() promptWhisper(w) end },
    }
end

local function menuEntries(w)
    local idx = w.index
    local e = {}
    for i = 1, #MODES do
        local m = MODES[i]
        e[#e + 1] = { text = modeLabel(m),
                      checked = function() return w.mode == m end,
                      func = function() mod:SetMode(idx, m) end }
    end
    e[#e + 1] = { separator = true }
    e[#e + 1] = { text = L["Current fight"],
                  checked = function() return w.segment == "current" end,
                  func = function() mod:SetSegment(idx, "current") end }
    e[#e + 1] = { text = L["Overall"],
                  checked = function() return w.segment == "overall" end,
                  func = function() mod:SetSegment(idx, "overall") end }
    local history = Meter:GetHistory()
    if #history > 0 then
        local fights = {}
        for i = 1, #history do
            local seg = history[i]
            fights[#fights + 1] = {
                text = fightLabel(seg, i) .. "  (" .. clock(seg.duration or 0) .. ")",
                checked = function() return w.segment == seg end,
                func = function() mod:SetSegment(idx, seg) end,
            }
        end
        e[#e + 1] = { text = L["Previous fights"], submenu = fights }
    end
    e[#e + 1] = { separator = true }
    e[#e + 1] = { text = L["Report"], submenu = reportEntries(w) }
    local sub = {}
    for i = 1, #MODES do
        local m = MODES[i]
        sub[#sub + 1] = { text = modeLabel(m), func = function() mod:AddWindow(m, idx) end }
    end
    e[#e + 1] = { text = L["Anchor to"], submenu = anchorEntries(w) }
    e[#e + 1] = { text = L["New window"], submenu = sub }
    if #mod.db.windows > 1 then
        e[#e + 1] = { text = L["Close window"], func = function() mod:CloseWindow(idx) end }
    end
    e[#e + 1] = { separator = true }
    e[#e + 1] = { text = L["Reset"], func = function() Meter:Reset() end }
    return e
end

openMenu = function(w)
    ns:ShowPopupMenu(menuEntries(w), "cursor", w.frame.title)
end

local function openOptions()
    local U = ns.UI
    if not U then return end
    if U.ToggleMainFrame and not (U.mainFrame and U.mainFrame:IsShown()) then
        U:ToggleMainFrame()
    end
    if U.ShowModulePage then U:ShowModulePage("meter") end
end

------------------------------------------------------------------------
-- Visibility (one verdict, applied to every bound frame)
------------------------------------------------------------------------
-- The hotkey hides every window until pressed again. Runtime only: a
-- reload must never leave the player staring at nothing.
local hiddenByKey = false
function mod:ToggleWindows()
    hiddenByKey = not hiddenByKey
    applyVisibility()
end

applyVisibility = function()
    -- mod.active: Core/Modules.lua clears it before OnDisable, so a hide-delay
    -- timer that outlives WindowDisable can no longer re-show the windows.
    if not mod.active then return end
    local db = mod.db
    local show = true
    if (ns.IsEditModeActive and ns:IsEditModeActive())
    or (ns.IsMoverEditMode and ns:IsMoverEditMode()) then
        show = true
    elseif hiddenByKey then
        show = false
    else
        local inCombat = Meter:InCombat() or UnitAffectingCombat("player")
        if db.onlyInGroup and not IsInGroup() then show = false end
        if db.hideInCombat and inCombat then show = false end
        if show and db.hideInPvP and IsInInstance then
            local _, kind = IsInInstance()
            if kind == "arena" or kind == "pvp" then show = false end
        end
        if show and db.hideOutOfCombat and not inCombat then
            local left = (db.hideDelay or 0) - (GetTime() - lastCombatEnd)
            if left > 0 then
                if not hideTimerArmed then
                    hideTimerArmed = true
                    C_Timer.After(left + 0.1, function()
                        hideTimerArmed = false
                        applyVisibility()
                    end)
                end
            else
                show = false
            end
        end
    end
    for i = 1, #frames do
        local w = frames[i]
        w.frame:SetShown(show and w.db ~= nil)
    end
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------
local function iconButton(parent, tex, tipText, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(12, 12)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(b)
    b.tex:SetTexture(ICONS .. tex)
    b.tex:SetVertexColor(0.6, 0.6, 0.65)
    b.tipText = tipText
    b:SetScript("OnEnter", function(self)
        self.tex:SetVertexColor(1, 1, 1)
        UI:ShowTooltip(self, self.tipText)
    end)
    b:SetScript("OnLeave", function(self)
        local c = self.tint
        if c then
            self.tex:SetVertexColor(c.r, c.g, c.b)
        else
            self.tex:SetVertexColor(0.6, 0.6, 0.65)
        end
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Resize path: a docked window's position is derived from its parent, so
-- after a size change it is re-derived (ns:ApplyMover), never re-measured.
local function savePosition(w)
    local x, y = ns:GetCenterOffsets(w.frame)
    if x and y then
        w.db.x, w.db.y = x, y
        ns:ApplyMover(w.mover)
    end
end

-- Left-drag anywhere on an unlocked window moves it; the padlock in the
-- title bar decides. Locked windows still move through the edit-mode box.
dragStart = function(w)
    if not w.db or w.db.locked then return end
    w.dragging = true
    w.frame:StartMoving()
end

dragStop = function(w)
    if not w.dragging then return end
    w.dragging = nil
    w.dragEnd  = GetTime()
    w.frame:StopMovingOrSizing()
    -- Drag path: keep the drop point. MoverSetCenter writes it, re-measures
    -- this window's own link at the new distance and carries its followers;
    -- ns:ApplyMover would snap a docked window straight back onto its edge.
    local x, y = ns:GetCenterOffsets(w.frame)
    if x and y then ns:MoverSetCenter(w.mover, x, y) end
end

-- OnMouseUp follows a drag release in either order with OnDragStop.
-- Forward-declared at the top: the row click above this line reads it.
justDragged = function(w)
    return w.dragging or (w.dragEnd and GetTime() - w.dragEnd < 0.2)
end

local function build(i, wdb)
    local accent = ns.COLORS.accent
    local w = { index = i, db = wdb, rows = {}, order = {}, vals = {}, scroll = 0,
                mode = "damage", segment = "current" }
    frames[i] = w

    local win = CreateFrame("Frame", "VuloClassicUIMeter" .. i, UIParent)
    w.frame = win
    win:SetSize(wdb.width, wdb.height)
    win:SetMovable(true)
    win:SetResizable(true)
    if win.SetResizeBounds then
        win:SetResizeBounds(120, 60)
    elseif win.SetMinResize then
        win:SetMinResize(120, 60)
    end
    win:SetFrameStrata("LOW")
    win:Hide()
    -- Hidden mid-drag (hide-in-combat, group disbands): no OnDragStop comes,
    -- so end the drag here or the title would swallow clicks for good.
    win:HookScript("OnHide", function() if w.dragging then dragStop(w) end end)

    win.bg = win:CreateTexture(nil, "BACKGROUND")
    win.bg:SetAllPoints(win)
    win.bg:SetColorTexture(0.05, 0.05, 0.06, 0.90)
    win.edge = CreateFrame("Frame", nil, win, BackdropTemplateMixin and "BackdropTemplate")
    win.edge:SetAllPoints(win)
    if win.edge.SetBackdrop then
        win.edge:SetBackdrop({ edgeFile = TEX_FLAT, edgeSize = 1 })
        local b = ns.COLORS.border or { r = 0, g = 0, b = 0 }
        win.edge:SetBackdropBorderColor(b.r or 0, b.g or 0, b.b or 0, 0.8)
    end

    -- Title bar: left-click = next mode, right-click = menu, wheel = mode,
    -- left-drag = move while unlocked.
    local title = CreateFrame("Frame", nil, win)
    title:SetPoint("TOPLEFT",  win, "TOPLEFT",  0, 0)
    title:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    title:SetHeight(TITLE_H)
    title.bg = title:CreateTexture(nil, "BACKGROUND")
    title.bg:SetAllPoints(title)
    title.bg:SetColorTexture(1, 1, 1, 0.04)
    title:EnableMouse(true)
    title:EnableMouseWheel(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() dragStart(w) end)
    title:SetScript("OnDragStop", function() dragStop(w) end)
    title:SetScript("OnMouseUp", function(_, button)
        if justDragged(w) then return end
        if w.detail then
            -- any click on the title leaves the detail list
            w.detail = nil
            w.scroll = 0
            refresh(w)
            return
        end
        -- Left: next mode, like the wheel. Right: the menu, which the arrow
        -- button in the title bar also opens.
        if button == "LeftButton" then
            local i = MODE_IDX[w.mode] + 1
            if i > #MODES then i = 1 end
            mod:SetMode(w.index, MODES[i])
        elseif button == "RightButton" then
            openMenu(w)
        end
    end)
    title:SetScript("OnMouseWheel", function(_, delta) onTitleWheel(w, delta) end)
    win.title = title

    win.menuBtn = iconButton(title, "arrow_down.tga", L["Mode, segment and reset"], function() openMenu(w) end)
    win.menuBtn:SetPoint("RIGHT", title, "RIGHT", -5, 0)
    win.resetBtn = iconButton(title, "reset.tga", L["Reset"], function() Meter:Reset() end)
    win.resetBtn:SetPoint("RIGHT", win.menuBtn, "LEFT", -4, 0)
    win.gearBtn = iconButton(title, "gear.tga", L["Settings"], openOptions)
    win.gearBtn:SetPoint("RIGHT", win.resetBtn, "LEFT", -4, 0)
    win.lockBtn = iconButton(title, "lock.tga", "", function() mod:ToggleLock(w.index) end)
    win.lockBtn:SetPoint("RIGHT", win.gearBtn, "LEFT", -4, 0)
    w.paintLock = function()
        local b = win.lockBtn
        if not w.db then return end
        local locked = w.db.locked
        b.tex:SetTexture(ICONS .. (locked and "lock.tga" or "lock_open.tga"))
        b.tipText = locked and L["Unlock position"] or L["Lock position"]
        b.tint = (not locked) and ns.COLORS.accent or nil
        if b:IsMouseOver() then
            -- toggled under the cursor: hover colour and the new tooltip text
            b:GetScript("OnEnter")(b)
        elseif b.tint then
            b.tex:SetVertexColor(b.tint.r, b.tint.g, b.tint.b)
        else
            b.tex:SetVertexColor(0.6, 0.6, 0.65)
        end
    end

    win.count = title:CreateFontString(nil, "OVERLAY")
    UI.FontFor("meter", win.count, 9)
    win.count:SetPoint("RIGHT", win.lockBtn, "LEFT", -6, 0)
    win.count:SetTextColor(0.55, 0.55, 0.6)

    win.titleText = title:CreateFontString(nil, "OVERLAY")
    UI.FontFor("meter", win.titleText, 11)
    win.titleText:SetPoint("LEFT",  title, "LEFT", 6, 0)
    win.titleText:SetPoint("RIGHT", win.count, "LEFT", -4, 0)
    win.titleText:SetJustifyH("LEFT")
    win.titleText:SetWordWrap(false)
    win.titleText:SetTextColor(accent.r, accent.g, accent.b)

    -- Body: the bar rows live here; wheel scrolls. Anchored in layoutChrome,
    -- which also knows which edge the title takes.
    win.body = CreateFrame("Frame", nil, win)
    win.body:EnableMouse(true)
    win.body:EnableMouseWheel(true)
    win.body:SetScript("OnMouseWheel", function(_, delta) onWheel(w, delta) end)
    win.body:RegisterForDrag("LeftButton")
    win.body:SetScript("OnDragStart", function() dragStart(w) end)
    win.body:SetScript("OnDragStop",  function() dragStop(w) end)

    -- Mover box (edit mode); the resize grip is its child, so it shows and
    -- hides with the box and never needs its own edit-mode hook.
    local mover = ns:CreateMover(win, {
        db = wdb, key = "meter" .. i, scalable = true,
        label = format(L["Combat Meter %d"], i), width = 220, height = 40,
    })
    w.mover = mover

    local grip = CreateFrame("Button", nil, mover)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(mover:GetFrameLevel() + 5)
    grip.tex = grip:CreateTexture(nil, "OVERLAY")
    grip.tex:SetAllPoints(grip)
    grip.tex:SetTexture(ICONS .. "expand.tga")
    grip.tex:SetVertexColor(accent.r, accent.g, accent.b, 0.9)
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        win:StopMovingOrSizing()
        if not w.db then return end
        w.db.width  = floor(win:GetWidth()  + 0.5)
        w.db.height = floor(win:GetHeight() + 0.5)
        savePosition(w)
        ns:RefreshMoverGeometry(mover)
        ns:RepositionMoverChildren(mover)
        layoutRows(w)
        refresh(w)
    end)
    win.grip = grip
    return w
end

-- Points slot i at its window table: the mover reads opts.db at use time, so
-- a profile switch or a closed window in front of this one only re-binds.
local function bind(w, wdb)
    -- A fight picked from the history is window state, not saved state; it
    -- survives a re-sync of the same window (every slider on the options page
    -- re-binds) and drops only when the slot changes hands.
    if not (w.db == wdb and type(w.segment) == "table") then
        w.segment = wdb.segment
    end
    w.db      = wdb
    w.mode    = wdb.mode
    w.scroll  = 0
    w.lastTitle, w.lastCount = nil, nil
    w.mover.opts.db = wdb
    w.dragging, w.dragEnd = nil, nil
    if w.paintLock then w.paintLock() end
    w.frame:SetSize(wdb.width, wdb.height)
    ns:ApplyMover(w.mover)
    layoutChrome(w)
    layoutRows(w)
    refresh(w)
end

syncFrames = function()
    local list = ensureWindows()
    for i = 1, #list do
        local w = frames[i] or build(i, list[i])
        bind(w, list[i])
    end
    for i = #list + 1, #frames do
        local w = frames[i]
        w.db = nil
        w.frame:Hide()
    end
    syncThreatEvents()
    applyVisibility()
end

-- The options page lists the windows; a change made from a title menu must
-- reach an open page. Only the window actions call this, never a slider.
pageChanged = function()
    if UI.RebuildCurrentPage and UI.currentModule == "meter" then UI:RebuildCurrentPage() end
end

------------------------------------------------------------------------
-- Mode follows the talents: window 1 opens on healing for a healing tree,
-- on damage for anything else. Tree order on this client is Priest
-- 1 Discipline / 2 Holy, Paladin 1 Holy, Druid 3 Restoration, Shaman
-- 3 Restoration (the same numbering Modules/SwingTimer.lua relies on).
------------------------------------------------------------------------
-- Binding label for the key that toggles the windows (Bindings.xml, action
-- VULO_METER_TOGGLE); lazily, like every other text.
ns.OnLocaleReady(function()
    _G["BINDING_NAME_VULO_METER_TOGGLE"] = L["Toggle combat meter windows"]
end)

local HEAL_TREES = {
    PRIEST  = { [1] = true, [2] = true },
    PALADIN = { [1] = true },
    DRUID   = { [3] = true },
    SHAMAN  = { [3] = true },
}

local function roleMode()
    local _, cls = UnitClass("player")
    local trees = cls and HEAL_TREES[cls]
    if not trees then return "damage" end
    local tree = ns.DominantTalentTree and ns:DominantTalentTree()
    if not tree then return nil end          -- unreadable: do not judge
    return trees[tree] and "heal" or "damage"
end

local function applyRoleMode()
    if not (mod.active and mod.db.followRole) then return end
    local m = roleMode()
    if not m then return end
    local w = frames[1]
    if w and w.db and w.mode ~= m then mod:SetMode(1, m) end
end
mod.ApplyRoleMode = applyRoleMode

------------------------------------------------------------------------
-- Module hooks (called from Modules/Meter.lua and MeterOptions.lua)
------------------------------------------------------------------------
function mod:ApplyWindow()
    if not self.active then return end
    syncFrames()
end

function mod:WindowEnable()
    self:RegisterEvent("PLAYER_REGEN_DISABLED", applyVisibility)
    self:RegisterEvent("PLAYER_REGEN_ENABLED",  applyVisibility)
    self:RegisterEvent("GROUP_ROSTER_UPDATE",   applyVisibility)
    -- arena and battleground are a place, not a state: re-judged on arrival
    self:RegisterEvent("PLAYER_ENTERING_WORLD",  applyVisibility)
    Meter:SetListener(onEngine)
    if not self._editHook and ns.RegisterEditModeHook then
        self._editHook = true
        ns:RegisterEditModeHook(function() applyVisibility() end)
    end
    syncFrames()
    if Meter:InCombat() then startTicker() end
    -- talents are not readable at ADDON_LOADED; the world entry is late enough
    self:RegisterEvent("PLAYER_TALENT_UPDATE",        applyRoleMode)
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", applyRoleMode)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, applyRoleMode) end)
end

function mod:WindowDisable()
    stopTicker()
    -- mod.active is already false here, so this unregisters the threat events.
    syncThreatEvents()
    Meter:SetListener(nil)
    for i = 1, #frames do frames[i].frame:Hide() end
end
