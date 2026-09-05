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
local UnitAffectingCombat = UnitAffectingCombat
local CreateFrame         = CreateFrame

local TITLE_H  = 20
local PAD      = 2
local MODES    = { "damage", "dps", "heal", "hps", "taken", "interrupts", "dispels", "deaths" }
local MODE_IDX = {}
for i = 1, #MODES do MODE_IDX[MODES[i]] = i end
local PER_SEC  = { dps = true, hps = true }
local COUNT    = { interrupts = true, dispels = true, deaths = true }
local HEALING  = { heal = true, hps = true }
-- Which per-spell table of the player entry a mode breaks down into.
local SUB_KEY  = { damage = "spells", dps = "spells", heal = "heals", hps = "heals",
                   taken = "takenBy", interrupts = "kicks", dispels = "purges" }
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

-- Forward declarations; filled in further down.
local layoutRows, refresh, applyVisibility, openMenu, rowEnter, syncFrames, dragStart, dragStop

------------------------------------------------------------------------
-- Labels
------------------------------------------------------------------------
local function modeLabel(m)
    if m == "damage"     then return L["Damage"] end
    if m == "dps"        then return L["DPS"] end
    if m == "heal"       then return L["Healing"] end
    if m == "hps"        then return L["HPS"] end
    if m == "taken"      then return L["Damage taken"] end
    if m == "interrupts" then return L["Interrupts"] end
    if m == "dispels"    then return L["Dispels"] end
    return L["Deaths"]
end

local function segmentLabel(w, seg)
    if w.segment == "overall" then return L["Overall"] end
    if seg and seg.title then return seg.title end
    return L["Current fight"]
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

local function valueOf(mode, p, dur)
    if mode == "damage"     then return p.damage end
    if mode == "heal"       then return p.heal - p.overheal end
    if mode == "taken"      then return p.taken      or 0 end
    if mode == "interrupts" then return p.interrupts or 0 end
    if mode == "dispels"    then return p.dispels    or 0 end
    if mode == "deaths"     then return p.deaths     or 0 end
    if dur <= 0 then return 0 end
    if mode == "dps" then return p.damage / dur end
    return (p.heal - p.overheal) / dur
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
    if COUNT[mode] then
        if db.showPercent then return format("%d (%.1f%%)", v, pct) end
        return format("%d", v)
    end
    local secondary
    if mode == "dps" then
        secondary = p.damage
    elseif mode == "hps" then
        secondary = p.heal - p.overheal
    else
        secondary = dur > 0 and v / dur or 0
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
    if va == vb then return a < b end
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
        if d.amount then
            right = short(d.amount) .. " \194\183 " .. (d.src or "?")
        else
            right = L["Unknown"]
        end
        line(i, left, right)
    end
end

rowEnter = function(self)
    local w   = self.win
    local seg = Meter:GetSegment(w.segment)
    local p   = seg and self.guid and seg.players[self.guid]
    if not p then return end
    local mode  = w.mode
    local vals  = w.vals
    local order = w.order
    local dur   = Meter:Duration(seg)
    local v     = vals[self.guid] or 0
    local total = 0
    for i = 1, #order do total = total + (vals[order[i]] or 0) end

    wipe(tipLines)
    local isCount = COUNT[mode]
    if mode == "deaths" then
        deathLines(p)
    else
        local own = HEALING[mode] and (p.heal - p.overheal)
                 or (mode == "taken" and (p.taken or 0))
                 or p.damage
        spellLines(p, SUB_KEY[mode], own, isCount)
    end
    tipLines[#tipLines + 1] = " "

    if isCount then
        tipLines[#tipLines + 1] = format("%s: %d", L["Total"], v)
    else
        local amount = PER_SEC[mode] and (mode == "dps" and p.damage or (p.heal - p.overheal)) or v
        tipLines[#tipLines + 1] = format("%s: %s", L["Total"], short(amount))
        tipLines[#tipLines + 1] = format("%s: %s", L["Per second"], short(dur > 0 and amount / dur or 0))
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
    return max(1, floor((w.db.height - TITLE_H - PAD * 2) / (db.barHeight + db.barGap)))
end

local function texturePath()
    return ns.MediaStatusbar(mod.db.texture)
end

local function onWheel(w, delta)
    w.scroll = max(0, w.scroll - delta)
    refresh(w)
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
    return r
end

layoutRows = function(w)
    local db   = mod.db
    local n    = rowSlots(w)
    local tex  = texturePath()
    local step = db.barHeight + db.barGap
    local iconSize = max(1, db.barHeight - 2)
    local textLeft = db.showClassIcon and (iconSize + 4) or 4
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
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",  w.frame.body, "TOPLEFT",  0, -((i - 1) * step))
        r:SetPoint("TOPRIGHT", w.frame.body, "TOPRIGHT", 0, -((i - 1) * step))
        r.icon:SetSize(iconSize, iconSize)
        r.icon:SetShown(db.showClassIcon and true or false)
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
    local t = modeLabel(w.mode) .. " \194\183 " .. segmentLabel(w, seg)
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

local function paintClass(r, p, db)
    if not db.showClassIcon then return end
    local cls = p.class or false
    if r.class == cls then return end
    r.class = cls
    local tex, coords = ns:GetClassIcon(p.class)
    if tex then
        r.icon:SetTexture(tex)
        r.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        r.icon:Show()
    else
        r.icon:Hide()
    end
end

refresh = function(w)
    if not w.db then return end
    local db    = mod.db
    local win   = w.frame
    local mode  = w.mode
    local order = w.order
    local vals  = w.vals
    local rows  = w.rows
    local seg   = Meter:GetSegment(w.segment)
    local n     = 0
    local dur   = 0
    if seg then
        dur = Meter:Duration(seg)
        for guid, p in pairs(seg.players) do
            n = n + 1
            order[n] = guid
            vals[guid] = valueOf(mode, p, dur)
        end
    end
    for i = n + 1, #order do order[i] = nil end

    if n == 0 then
        for i = 1, #rows do rows[i]:Hide() end
        win.empty:Show()
        setTitle(w, seg, 0, 0, 0)
        return
    end
    win.empty:Hide()

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

    for i = 1, slots do
        local r    = rows[i]
        local idx  = i + scroll
        local guid = order[idx]
        if r and guid then
            local p = seg.players[guid]
            local v = vals[guid]
            r:SetValue(top > 0 and v / top or 0)
            local c = ns.ClassColor(p.class)
            if c then
                r:SetStatusBarColor(c.r, c.g, c.b, 0.85)
            else
                r:SetStatusBarColor(0.6, 0.6, 0.6, 0.85)
            end
            paintClass(r, p, db)
            if db.showRank then
                r.left:SetFormattedText("%d. %s", idx, p.name)
            else
                r.left:SetText(p.name)
            end
            r.right:SetText(rightText(mode, p, v, total, dur))
            r.hl:SetShown(db.highlightSelf and guid == me)
            local changed = r.guid ~= guid
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
        if dirty or PER_SEC[w.mode] then refresh(w) end
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

local function onEngine(what)
    if what == "start" then
        resetScroll()
        -- No immediate paint: the segment is still empty, the first tick fills it.
        startTicker()
        applyVisibility()
    elseif what == "end" then
        stopTicker()
        lastCombatEnd = GetTime()
        Meter:ClearDirty()
        refreshAll()
        applyVisibility()
        wipe(fmtCache)
        fmtCount = 0
    else
        resetScroll()
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

function mod:SetMode(index, m)
    if not MODE_IDX[m] then return end
    local w = frames[index]
    if not (w and w.db) then return end
    w.db.mode = m
    w.mode    = m
    w.scroll  = 0
    refresh(w)
    pageChanged()
end

function mod:SetSegment(index, s)
    local w = frames[index]
    if not (w and w.db) then return end
    s = (s == "overall") and "overall" or "current"
    w.db.segment = s
    w.segment    = s
    w.scroll     = 0
    refresh(w)
    pageChanged()
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
    e[#e + 1] = { separator = true }
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
applyVisibility = function()
    -- mod.active: Core/Modules.lua clears it before OnDisable, so a hide-delay
    -- timer that outlives WindowDisable can no longer re-show the windows.
    if not mod.active then return end
    local db = mod.db
    local show = true
    if (ns.IsEditModeActive and ns:IsEditModeActive())
    or (ns.IsMoverEditMode and ns:IsMoverEditMode()) then
        show = true
    else
        local inCombat = Meter:InCombat() or UnitAffectingCombat("player")
        if db.onlyInGroup and not IsInGroup() then show = false end
        if db.hideInCombat and inCombat then show = false end
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

local function savePosition(w)
    local x, y = ns:GetCenterOffsets(w.frame)
    if x and y then
        w.db.x, w.db.y = x, y
        ns:ApplyMover(w.mover)
        -- Re-measures this window's own link and carries anything docked to it.
        ns:OnMoverRepositioned(w.mover)
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
    savePosition(w)
end

-- OnMouseUp follows a drag release in either order with OnDragStop.
local function justDragged(w)
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

    -- Title bar: left-click = menu, wheel = mode, right-drag = move.
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
        if button == "LeftButton" and not justDragged(w) then openMenu(w) end
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
        if b.tint then
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

    -- Body: the bar rows live here; wheel scrolls.
    win.body = CreateFrame("Frame", nil, win)
    win.body:SetPoint("TOPLEFT",     win, "TOPLEFT",     PAD, -(TITLE_H + PAD))
    win.body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, PAD)
    win.body:EnableMouse(true)
    win.body:EnableMouseWheel(true)
    win.body:SetScript("OnMouseWheel", function(_, delta) onWheel(w, delta) end)
    win.body:RegisterForDrag("LeftButton")
    win.body:SetScript("OnDragStart", function() dragStart(w) end)
    win.body:SetScript("OnDragStop",  function() dragStop(w) end)

    win.empty = win.body:CreateFontString(nil, "OVERLAY")
    UI.FontFor("meter", win.empty, 11)
    win.empty:SetPoint("TOP", win.body, "TOP", 0, -8)
    win.empty:SetTextColor(0.5, 0.5, 0.55)
    win.empty:SetText(L["No combat data"])

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
    w.db      = wdb
    w.mode    = wdb.mode
    w.segment = wdb.segment
    w.scroll  = 0
    w.lastTitle, w.lastCount = nil, nil
    w.mover.opts.db = wdb
    w.dragging, w.dragEnd = nil, nil
    if w.paintLock then w.paintLock() end
    w.frame:SetSize(wdb.width, wdb.height)
    ns:ApplyMover(w.mover)
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
    applyVisibility()
end

-- The options page lists the windows; a change made from a title menu must
-- reach an open page. Only the window actions call this, never a slider.
local function pageChanged()
    if UI.RebuildCurrentPage and UI.currentModule == "meter" then UI:RebuildCurrentPage() end
end

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
    Meter:SetListener(onEngine)
    if not self._editHook and ns.RegisterEditModeHook then
        self._editHook = true
        ns:RegisterEditModeHook(function() applyVisibility() end)
    end
    syncFrames()
    if Meter:InCombat() then startTicker() end
end

function mod:WindowDisable()
    stopTicker()
    Meter:SetListener(nil)
    for i = 1, #frames do frames[i].frame:Hide() end
end
