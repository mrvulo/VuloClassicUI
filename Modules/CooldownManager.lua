-- =========================================================
-- VuloClassicUI / Modules / CooldownManager
-- Retail-style cooldown bars for Classic, organised into GROUPS:
-- make one bar for procs/buffs, one for defensive CDs, one for
-- offensive CDs... each group is its own movable bar with its own
-- spell list and layout. Add entries by typing a name/ID, shift-
-- clicking a spell into the box, or dragging onto an unlocked bar.
-- Icons only DISPLAY cooldowns (no casting) -> no secure/taint issues.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("cooldownmanager", {
    name        = "Cooldown Manager",
    group       = "HUD",
    description = "Movable cooldown bars grouped however you like (procs, defensives, offensives ...) — like the retail cooldown manager.",
    defaults    = {
        enabled  = true,
        groups   = {},   -- array of group tables (see defaultGroup)
        selected = 1,    -- group index currently shown in the options
    },
})

-- =========================================================
-- API compat (2.5.5 has no C_Spell / global GetItemCooldown reliably)
-- =========================================================
local GetSpellCooldown = _G.GetSpellCooldown or (C_Spell and C_Spell.GetSpellCooldown)
local GetSpellInfo     = _G.GetSpellInfo
local GetItemIcon      = _G.GetItemIcon or (C_Item and C_Item.GetItemIconByID)

local function getItemCooldown(itemID)
    if not itemID then return 0, 0, 0 end
    if _G.GetItemCooldown then return GetItemCooldown(itemID) end
    if C_Item and C_Item.GetItemCooldown then
        local s, d, e = C_Item.GetItemCooldown(itemID)
        return s, d, (e == true and 1) or (e == false and 0) or e
    end
    if C_Container and C_Container.GetItemCooldown then
        return C_Container.GetItemCooldown(itemID)
    end
    return 0, 0, 0
end

local function spellCooldown(id)
    if not GetSpellCooldown then return 0, 0, 1 end
    local a, b, c = GetSpellCooldown(id)
    if type(a) == "table" then
        return a.startTime or 0, a.duration or 0, a.isEnabled ~= false and 1 or 0
    end
    return a or 0, b or 0, c or 1
end

local GCD_MAX = 1.5
local FONT = "Fonts\\FRIZQT__.TTF"

-- =========================================================
-- State
-- =========================================================
-- barOf maps a group TABLE to its runtime bar frame (NOT stored in the DB,
-- which can't hold frames). Group tables keep their identity across reorders,
-- so a bar stays bound to its group even when indices shift.
local barOf   = {}
local allBars = {}   -- every bar ever created (for blanket hide on rebuild)
local throttle = 0
local driver

local function db() return mod.db end

-- =========================================================
-- Groups
-- =========================================================
local function defaultGroup(name)
    return {
        name           = name or L["Cooldowns"],
        mode           = "cooldown",   -- "cooldown" | "aura" (buffs/procs)
        entries        = {},
        iconSize       = 40,
        spacing        = 4,
        perRow         = 12,
        growth         = "RIGHT",
        onlyOnCooldown = false,
        showText       = true,
        desaturate     = true,
        readyFlash     = true,
        unlocked       = false,
        x              = 0,
        y              = -160,
    }
end

-- Migration from the old single-bar layout + ensure one group always exists.
local function ensureGroups()
    local d = db()
    d.groups = d.groups or {}
    if #d.groups == 0 then
        local g = defaultGroup()
        -- carry over the pre-groups flat config, if present
        if type(d.entries) == "table" then g.entries = d.entries end
        for _, k in ipairs({ "iconSize", "spacing", "perRow", "growth",
            "onlyOnCooldown", "showText", "desaturate", "readyFlash", "x", "y" }) do
            if d[k] ~= nil then g[k] = d[k] end
        end
        d.groups[1] = g
        d.entries = nil
    end
    for _, g in ipairs(d.groups) do
        g.mode = g.mode or "cooldown"   -- older groups predate aura mode
    end
    if d.selected < 1 then d.selected = 1 end
    if d.selected > #d.groups then d.selected = #d.groups end
end

local function curGroup()
    local d = db()
    return d.groups[d.selected]
end

-- =========================================================
-- Entry resolution
-- =========================================================
local function resolveInput(text)
    if not text or text == "" then return nil end
    local sid = text:match("|Hspell:(%d+)")
    if sid then return "spell", tonumber(sid) end
    local iid = text:match("|Hitem:(%d+)")
    if iid then return "item", tonumber(iid) end

    local num = tonumber(text)
    if num then
        if GetSpellInfo(num) then return "spell", num end
        if GetItemInfo(num) then return "item", num end
        return nil
    end
    if GetSpellInfo(text) then
        local id = select(7, GetSpellInfo(text))
        if id then return "spell", id end
    end
    local _, link = GetItemInfo(text)
    if link then
        local id = tonumber(link:match("item:(%d+)"))
        if id then return "item", id end
    end
    return nil
end

local function entryInfo(e)
    if e.kind == "spell" then
        local name, _, icon = GetSpellInfo(e.id)
        return name, icon
    else
        local name = GetItemInfo(e.id)
        return name, (GetItemIcon and GetItemIcon(e.id))
    end
end

local function entryCooldown(e)
    if e.kind == "spell" then return spellCooldown(e.id) end
    return getItemCooldown(e.id)
end

local function groupHas(group, kind, id)
    for _, e in ipairs(group.entries) do
        if e.kind == kind and e.id == id then return true end
    end
    return false
end

local relayoutGroup, refreshGroup, refreshAll, layoutIcons  -- forward

-- Player buff snapshot, rebuilt once per refresh (name + spellID keyed) so
-- aura groups don't scan 40 buffs per icon. UnitAura spellId is the 10th
-- return in 2.5.5 (same as VTManaDisplay relies on).
local auraByName, auraByID = {}, {}
local function scanPlayerAuras()
    wipe(auraByName); wipe(auraByID)
    for i = 1, 40 do
        local name, _, count, _, duration, expiration, _, _, _, sid = UnitAura("player", i, "HELPFUL")
        if not name then break end
        local rec = { dur = duration, exp = expiration, count = count }
        auraByName[name] = rec
        if sid then auraByID[sid] = rec end
    end
end

local function addEntry(group, input)
    if not group then return false end
    local kind, id = resolveInput(input)
    if not kind then
        ns:Print(L["Cooldown Manager: '%s' is not a known spell or item."], tostring(input))
        return false
    end
    if groupHas(group, kind, id) then
        ns:Print(L["Cooldown Manager: already tracking that."])
        return false
    end
    group.entries[#group.entries + 1] = { kind = kind, id = id }
    relayoutGroup(group)
    local name = entryInfo(group.entries[#group.entries])
    ns:Print(L["Cooldown Manager: added %s."], name or ("#" .. id))
    return true
end

-- =========================================================
-- Icons + bar
-- =========================================================
local function makeIcon(bar, i)
    local f = CreateFrame("Frame", nil, bar)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetAllPoints(f)
    f.border:SetColorTexture(0, 0, 0, 1)

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.tex)
    f.cd:SetDrawEdge(true)
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    f.cd.noCooldownCount = true

    -- number on its own frame ABOVE the cooldown sweep so it stays crisp
    f.textHost = CreateFrame("Frame", nil, f)
    f.textHost:SetAllPoints(f)
    f.textHost:SetFrameLevel(f.cd:GetFrameLevel() + 5)

    f.text = f.textHost:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(FONT, 16, "OUTLINE")
    f.text:SetPoint("CENTER", f.textHost, "CENTER", 0, 0)
    f.text:SetShadowColor(0, 0, 0, 1)
    f.text:SetShadowOffset(1, -1)

    -- stack count (aura mode) in the bottom-right corner
    f.stack = f.textHost:CreateFontString(nil, "OVERLAY")
    f.stack:SetFont(FONT, 13, "OUTLINE")
    f.stack:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.stack:SetTextColor(1, 0.95, 0.6)
    f.stack:Hide()

    f.flash = f.textHost:CreateTexture(nil, "OVERLAY")
    f.flash:SetTexture("Interface\\Cooldown\\star4")
    f.flash:SetBlendMode("ADD")
    f.flash:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.flash:Hide()
    return f
end

local function onReceiveDrag(bar)
    if not mod._enabled or not bar._group then return end
    local ctype, a, b = GetCursorInfo()
    if ctype == "spell" then
        local id = select(4, GetCursorInfo())
        if not id and b and GetSpellBookItemInfo then
            id = select(2, GetSpellBookItemInfo(a, b))
        end
        if id then addEntry(bar._group, tostring(id)) end
    elseif ctype == "item" and a then
        addEntry(bar._group, tostring(a))
    end
    ClearCursor()
end

local function ensureBar(group)
    local bar = barOf[group]
    if bar then bar._group = group; return bar end

    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetSize(group.iconSize, group.iconSize)
    bar:SetPoint("CENTER", UIParent, "CENTER", group.x or 0, group.y or -160)
    bar:SetFrameStrata("MEDIUM")
    bar._icons = {}
    bar._group = group
    bar:SetScript("OnReceiveDrag", function(self) onReceiveDrag(self) end)

    bar.mover = ns:CreateMover(bar, {
        label  = group.name,
        db     = group,   -- per-group x/y/unlocked live here
        width  = 150,
        height = 34,
        onMove = function(x, y) group.x, group.y = x, y end,
    })

    barOf[group] = bar
    allBars[#allBars + 1] = bar
    return bar
end

-- Position an ordered list of icon frames in the group's grid (positive
-- bounding box, cell order flipped for LEFT/UP growth).
layoutIcons = function(group, list)
    local bar = ensureBar(group)
    local size, pad = group.iconSize, group.spacing
    local count  = #list
    local perRow = math.max(1, group.perRow)
    local horiz  = (group.growth == "RIGHT" or group.growth == "LEFT")
    local posN   = math.min(math.max(count, 1), perRow)
    local lineN  = math.max(1, math.ceil(math.max(count, 1) / perRow))
    local totalCols = horiz and posN or lineN
    local totalRows = horiz and lineN or posN
    local step = size + pad
    for i = 1, count do
        local idx  = i - 1
        local line = math.floor(idx / perRow)
        local pos  = idx % perRow
        local col  = horiz and pos or line
        local rowi = horiz and line or pos
        if group.growth == "LEFT" then col  = (totalCols - 1) - col end
        if group.growth == "UP"   then rowi = (totalRows - 1) - rowi end
        local f = list[i]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", bar, "TOPLEFT", col * step, -rowi * step)
    end
    bar:SetSize(totalCols * size + (totalCols - 1) * pad,
                totalRows * size + (totalRows - 1) * pad)
end

relayoutGroup = function(group)
    local bar = ensureBar(group)
    local size = group.iconSize
    local entries = group.entries
    local icons = bar._icons

    for i, e in ipairs(entries) do
        local f = icons[i]
        if not f then f = makeIcon(bar, i); icons[i] = f end
        local ename, icon = entryInfo(e)
        f.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        f.text:SetFont(FONT, math.max(8, math.floor(size * 0.4)), "OUTLINE")
        f.entry     = e
        f.entryName = ename
        f.prevRemain = 0
        f.flashT = nil
        f:SetSize(size, size)
        f:Show()
    end
    for i = #entries + 1, #icons do icons[i]:Hide() end

    if group.mode == "aura" then
        -- visibility + packing happen per refresh (only active procs show)
        refreshGroup(group, GetTime())
    else
        local all = {}
        for i = 1, #entries do all[i] = icons[i] end
        if #all == 0 then bar:SetSize(size, size) else layoutIcons(group, all) end
    end
end

local function updateIcon(group, f, now)
    local e = f.entry
    if not e then return end
    local start, duration, enabled = entryCooldown(e)
    local onCD = enabled ~= 0 and duration and duration > GCD_MAX
        and start and (start + duration - now) > 0

    if onCD then
        local remain = start + duration - now
        f.cd:SetCooldown(start, duration)
        if group.showText then
            if remain >= 60 then
                f.text:SetText(math.floor(remain / 60 + 0.5) .. "m")
            elseif remain >= 10 then
                f.text:SetText(string.format("%d", remain))
            else
                f.text:SetText(string.format("%.1f", remain))
            end
            if remain <= 3 then f.text:SetTextColor(1, 0.4, 0.4)
            else f.text:SetTextColor(1, 1, 1) end
            f.text:Show()
        else
            f.text:Hide()
        end
        if group.desaturate then f.tex:SetDesaturated(true); f.tex:SetVertexColor(0.6, 0.6, 0.6)
        else f.tex:SetDesaturated(false); f.tex:SetVertexColor(1, 1, 1) end
        f.prevRemain = remain
        if group.onlyOnCooldown then f:Show() end
    else
        f.cd:Clear()
        f.text:Hide()
        f.tex:SetDesaturated(false)
        f.tex:SetVertexColor(1, 1, 1)
        if group.readyFlash and (f.prevRemain or 0) > 0 then
            f.flashT = 0
            f.flash:SetAlpha(0.9)
            f.flash:Show()
        end
        f.prevRemain = 0
        if group.onlyOnCooldown then f:Hide() end
    end

    if f.flashT then
        f.flashT = f.flashT + 0.1
        local p = f.flashT / 0.45
        if p >= 1 then f.flash:Hide(); f.flashT = nil
        else
            local s = f:GetWidth() * (1.6 + p * 0.6)
            f.flash:SetSize(s, s)
            f.flash:SetAlpha(0.9 * (1 - p))
        end
    end
end

-- Aura mode: the icon is only ever shown while the buff/proc is active.
-- Draw a draining sweep for the remaining time + stacks.
local function updateAuraIcon(group, f, rec, now)
    f.tex:SetDesaturated(false)
    f.tex:SetVertexColor(1, 1, 1)
    if rec.exp and rec.dur and rec.dur > 0 then
        f.cd:SetCooldown(rec.exp - rec.dur, rec.dur)
        local remain = rec.exp - now
        if group.showText and remain > 0 then
            if remain >= 60 then
                f.text:SetText(math.floor(remain / 60 + 0.5) .. "m")
            elseif remain >= 10 then
                f.text:SetText(string.format("%d", remain))
            else
                f.text:SetText(string.format("%.1f", remain))
            end
            f.text:SetTextColor(remain <= 3 and 1 or 1, remain <= 3 and 0.4 or 1, remain <= 3 and 0.4 or 1)
            f.text:Show()
        else
            f.text:Hide()
        end
    else
        f.cd:Clear()       -- permanent / no timed duration
        f.text:Hide()
    end
    if rec.count and rec.count > 1 then
        f.stack:SetText(rec.count); f.stack:Show()
    else
        f.stack:Hide()
    end
end

refreshGroup = function(group, now)
    local bar = barOf[group]
    if not bar then return end
    local icons = bar._icons

    if group.mode == "aura" then
        scanPlayerAuras()
        local active = {}
        for i = 1, #group.entries do
            local f = icons[i]
            if f then
                local e = f.entry
                local rec = (e and auraByID[e.id]) or (f.entryName and auraByName[f.entryName])
                if rec then
                    active[#active + 1] = f
                    f._rec = rec
                    f:Show()
                else
                    f.stack:Hide()
                    f:Hide()
                end
            end
        end
        layoutIcons(group, active)          -- pack only the active procs
        for _, f in ipairs(active) do updateAuraIcon(group, f, f._rec, now) end
        return
    end

    -- cooldown mode
    for i = 1, #group.entries do
        local f = icons[i]
        if f and (f:IsShown() or group.onlyOnCooldown) then
            updateIcon(group, f, now)
        end
    end
end

refreshAll = function()
    if not mod._enabled then return end
    local now = GetTime()
    for _, group in ipairs(db().groups) do
        refreshGroup(group, now)
    end
end

local function onUnitAura(_, unit)
    if unit == "player" then refreshAll() end
end

-- Rebuild every bar: hide all, then (re)lay-out each current group.
local function rebuildBars()
    for _, b in ipairs(allBars) do b:Hide() end
    for _, group in ipairs(db().groups) do
        local bar = ensureBar(group)
        bar:Show()
        if bar.mover and bar.mover.label then bar.mover.label:SetText(group.name) end
        relayoutGroup(group)
    end
    refreshAll()
end

local function setUnlocked(group, state)
    if not group then return end
    group.unlocked = state
    local bar = ensureBar(group)
    bar:EnableMouse(state)
    if state then
        bar.mover:Show()
        ns:Print(L["Cooldown group '%s' unlocked. Drag spells/items onto it; |cff9b6cffdrag|r to move."], group.name)
    else
        bar.mover:Hide()
        ns:Print(L["Cooldown group '%s' locked."], group.name)
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    ensureGroups()
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", function(_, elapsed)
            throttle = throttle + elapsed
            if throttle < 0.1 then return end
            throttle = 0
            refreshAll()
        end)
    end
    driver:Show()
    rebuildBars()
    ns:RegisterEvent("SPELL_UPDATE_COOLDOWN", refreshAll)
    ns:RegisterEvent("BAG_UPDATE_COOLDOWN",   refreshAll)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", refreshAll)
    ns:RegisterEvent("SPELLS_CHANGED",        rebuildBars)
    ns:RegisterEvent("UNIT_AURA",             onUnitAura)  -- snappy proc show/hide
end

function mod:OnDisable()
    ns:UnregisterEvent("SPELL_UPDATE_COOLDOWN", refreshAll)
    ns:UnregisterEvent("BAG_UPDATE_COOLDOWN",   refreshAll)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", refreshAll)
    ns:UnregisterEvent("SPELLS_CHANGED",        rebuildBars)
    ns:UnregisterEvent("UNIT_AURA",             onUnitAura)
    if driver then driver:Hide() end
    for _, b in ipairs(allBars) do
        if b.mover then b.mover:Hide() end
        b:Hide()
    end
end

-- =========================================================
-- Options
-- =========================================================
local addInput = ""

local function rebuildPage()
    if ns.UI and ns.UI.BuildOptionsPage then ns.UI:BuildOptionsPage("cooldownmanager") end
end

function mod:GetOptions()
    ensureGroups()
    local d = mod.db
    local group = curGroup()

    -- Group selector
    local groupValues = {}
    for i, g in ipairs(d.groups) do
        groupValues[#groupValues + 1] = { value = i, text = g.name }
    end

    local items = {
        { type = "header", text = L["Cooldown Manager"] },
        { type = "desc",
          text = L["|cffaaaaaaMovable cooldown bars grouped however you like — e.g. one for procs/buffs, one for defensive cooldowns, one for offensives. Pick or create a group below, then add spells/trinkets to it.|r"] },
        { type = "spacer", height = 6 },

        { type = "header", text = L["Groups"] },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "dropdown", label = L["Edit group"], width = 240,
              values = groupValues,
              get = function() return d.selected end,
              set = function(_, v) d.selected = v; rebuildPage() end },
            { type = "button", label = L["New group"], width = 120, primary = true,
              onClick = function()
                  d.groups[#d.groups + 1] = defaultGroup(string.format(L["Group %d"], #d.groups + 1))
                  d.selected = #d.groups
                  rebuildBars(); rebuildPage()
              end },
        } },
    }

    if not group then return items end

    -- Selected group: name + delete
    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "editbox", label = L["Name"], width = 260, editWidth = 170,
          get = function() return group.name end,
          set = function(_, v)
              group.name = (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
              if group.name == "" then group.name = L["Cooldowns"] end
              rebuildBars(); rebuildPage()
          end },
        { type = "button", label = L["Delete group"], width = 130,
          onClick = function()
              local bar = barOf[group]
              if bar then bar:Hide(); if bar.mover then bar.mover:Hide() end end
              table.remove(d.groups, d.selected)
              if d.selected > #d.groups then d.selected = #d.groups end
              rebuildBars(); rebuildPage()
          end },
    } }
    items[#items + 1] = { type = "dropdown", label = L["Group type"], width = 280,
        values = {
            { value = "cooldown", text = L["Cooldowns"] },
            { value = "aura",     text = L["Buffs & Procs (only show while active)"] },
        },
        get = function() return group.mode end,
        set = function(_, v) group.mode = v; rebuildBars(); rebuildPage() end }
    items[#items + 1] = { type = "desc",
        text = (group.mode == "aura")
            and L["|cffaaaaaaIcons appear only while their buff/proc is on you; the bar is empty otherwise. Add the BUFF (e.g. Clearcasting) by name or ID.|r"]
            or  L["|cffaaaaaaIcons show the cooldown of each spell/trinket.|r"] }
    items[#items + 1] = { type = "spacer", height = 6 }

    -- Add entry
    items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
        { type = "editbox", label = L["Add (name / ID)"], width = 280, editWidth = 190,
          get = function() return addInput end,
          set = function(_, v) addInput = tostring(v or "") end },
        { type = "button", label = L["Add"], width = 80, primary = true,
          onClick = function()
              local txt = addInput:gsub("^%s+", ""):gsub("%s+$", "")
              if txt ~= "" and addEntry(group, txt) then addInput = ""; rebuildPage() end
          end },
    } }
    items[#items + 1] = { type = "spacer", height = 4 }

    -- Tracked list
    items[#items + 1] = { type = "header", text = L["Tracked"] }
    if #group.entries == 0 then
        items[#items + 1] = { type = "desc", text = L["|cff888888Nothing in this group yet.|r"] }
    else
        for i, e in ipairs(group.entries) do
            local name = (entryInfo(e)) or ("#" .. e.id)
            local kindTag = e.kind == "item" and L["  |cff888888(item)|r"] or ""
            items[#items + 1] = { type = "group", layout = "row", gap = 6, items = {
                { type = "button", label = "X", width = 28,
                  onClick = function() table.remove(group.entries, i); relayoutGroup(group); rebuildPage() end },
                { type = "button", label = L["Up"], width = 44,
                  onClick = function()
                      if i > 1 then
                          group.entries[i], group.entries[i-1] = group.entries[i-1], group.entries[i]
                          relayoutGroup(group); rebuildPage()
                      end
                  end },
                { type = "desc", text = name .. kindTag, width = 220 },
            } }
        end
    end

    -- Layout
    items[#items + 1] = { type = "spacer", height = 8 }
    items[#items + 1] = { type = "header", text = L["Layout"] }
    items[#items + 1] = { type = "slider", label = L["Icon size"], min = 20, max = 64, step = 1,
        get = function() return group.iconSize end,
        set = function(_, v) group.iconSize = v; relayoutGroup(group) end }
    items[#items + 1] = { type = "slider", label = L["Spacing"], min = 0, max = 16, step = 1,
        get = function() return group.spacing end,
        set = function(_, v) group.spacing = v; relayoutGroup(group) end }
    items[#items + 1] = { type = "slider", label = L["Icons per row"], min = 1, max = 20, step = 1,
        get = function() return group.perRow end,
        set = function(_, v) group.perRow = v; relayoutGroup(group) end }
    items[#items + 1] = { type = "dropdown", label = L["Growth direction"], width = 220,
        values = {
            { value = "RIGHT", text = L["Right"] }, { value = "LEFT", text = L["Left"] },
            { value = "DOWN",  text = L["Down"]  }, { value = "UP",   text = L["Up"]   },
        },
        get = function() return group.growth end,
        set = function(_, v) group.growth = v; relayoutGroup(group) end }

    -- Display
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Display"] }
    items[#items + 1] = { type = "toggle", label = L["Show countdown text"],
        get = function() return group.showText end,
        set = function(_, v) group.showText = v; refreshAll() end }
    if group.mode ~= "aura" then
        items[#items + 1] = { type = "toggle", label = L["Only show while on cooldown"],
            tooltip = L["Hides ready icons; they reappear when on cooldown."],
            get = function() return group.onlyOnCooldown end,
            set = function(_, v) group.onlyOnCooldown = v; relayoutGroup(group); refreshAll() end }
        items[#items + 1] = { type = "toggle", label = L["Dim icon while on cooldown"],
            get = function() return group.desaturate end,
            set = function(_, v) group.desaturate = v; refreshAll() end }
        items[#items + 1] = { type = "toggle", label = L["Flash when ready"],
            get = function() return group.readyFlash end,
            set = function(_, v) group.readyFlash = v end }
    end

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "button", label = L["Unlock / Position"], width = 200,
        onClick = function() setUnlocked(group, not group.unlocked) end }

    return items
end
