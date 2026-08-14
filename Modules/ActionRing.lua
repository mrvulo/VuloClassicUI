-- VuloClassicUI / Modules / ActionRing: hold a keybind to open a ring of
-- actions; aim at an entry, release the key to cast it. Up to 16 rings, each
-- with its own keybind and its own list of spells, items and macros.
--
-- HOW THE SECURE SIDE WORKS -- read this before touching anything below.
--
-- Which entry a release fires is decided by where the cursor is at that
-- instant, so the decision cannot be made in insecure Lua: writing the chosen
-- action onto a protected button from a PreClick is refused the moment the
-- player is in combat (ADDON_ACTION_BLOCKED on SetAttribute). So the choosing
-- happens INSIDE a secure snippet wrapped around the button's OnClick. Code in
-- the restricted environment is secure, and its SetAttribute calls are not
-- blocked. Everything the snippet needs -- per-entry action triples, the arc
-- geometry, the ring's centre -- is pushed onto the button as ordinary
-- attributes while out of combat; the snippet does no layout maths of its own,
-- which is what stops it drifting away from the insecure hover highlight.
--
-- The route of one press:
--   * Bindings.xml declares VULO_ACTIONRING1..16; UpdateBindings routes each
--     bound key to one secure button via SetOverrideBindingClick. The click
--     arrives as "LeftButton" (the token that call defaults to).
--   * key DOWN: our insecure PreClick opens the visual ring; the snippet's
--     down branch stamps ownership, claims ESCAPE, captures the cursor origin
--     and clears the action type so the press fires nothing.
--   * key UP: the snippet reads the cursor via ui:GetMousePosition() (the
--     sandbox has no GetCursorPosition; measured against UIParent because the
--     handle of an UNprotected frame is refused in combat, and because it
--     returns nil outside the frame's rect), resolves the angle to an entry,
--     writes that entry's action attributes onto the button itself, and the
--     secure template performs the cast. Our PostClick then closes the ring.
--
-- The action attributes are written in the *-wildcard, button-suffixed form
-- ("*type1" for the keybind's LeftButton token, "*type2" for the Select key's
-- RightButton token): plain "type"/"spell" demonstrably does not fire on this
-- client, and the * prefix is what keeps a modifier held during the gesture
-- from changing the lookup. See Core docs on the wildcard rule.
--
-- All angles are DEGREES. The sandbox whitelists WoW's GLOBAL atan2, which
-- answers in degrees -- math.atan2 answers in radians -- so the insecure
-- mirror below converts with math.deg and both sides wrap on an exact 360.
-- sqrt is not whitelisted; ^0.5 is the same thing. GetMousePosition reports a
-- [0,1] fraction of UIParent from its bottom-left, so scaling by UIParent's
-- size gives UIParent units, and dividing by the ring's own scale converts to
-- the units radius and dead zone use.
--
-- STANDALONE NOTE: this file plus ActionRingOptions.lua are the whole module.
-- The framework surface used here is small and sits in the first screen of
-- code: RegisterModule/db, ns.L, ns.UI.FONT_PATH, ns.COLORS, RunOutOfCombatOnce.
local _, ns = ...
local L = ns.L

local MAX_MENUS      = 16
local MAX_SLOTS      = 24
local BINDING_PREFIX = "VULO_ACTIONRING"
local BUTTON_PREFIX  = "VuloActionRingButton"
local DEAD_ZONE      = 24
local OPEN_TIMEOUT   = 120   -- seconds; a ring nobody answers closes itself

-- Mouse-button TOKENS that tell the snippet which binding a click came from:
-- the ring's own keybind always arrives as "LeftButton", so the Select key of
-- a kept-open ring is routed as "RightButton" (suffix 2 -- it may fire) and
-- ESCAPE / the cancel key as "MiddleButton" (suffix 3 -- nothing is ever
-- written under 3, so it can never fire). Real button names on purpose:
-- RegisterForClicks("AnyDown","AnyUp") covers them, and EnableMouse(false)
-- means no real mouse click can ever reach the button anyway.
local CONFIRM_BUTTON = "RightButton"
local CANCEL_BUTTON  = "MiddleButton"

local mod = ns:RegisterModule("actionring", {
    name        = "Action Ring",
    group       = "HUD",
    description = "Hold a keybind to open a ring of actions around the cursor; aim at an entry and release to use it.",
    defaults    = {
        enabled       = true,
        menuCount     = 1,
        -- [i] = { name?, slots = { {kind,id,name,text,cyclePos}, ... }, appearance? }
        menus         = {},
        layout        = "arc",   -- "arc" | "grid" | "fan"
        centerMode    = "cursor",-- "cursor" | "screen"
        posX          = 0,       -- UIParent units from centre (screen mode)
        posY          = 0,
        arcSpan       = 360,     -- degrees; 360 = full circle
        arcRotation   = 0,       -- degrees clockwise from 12 o'clock
        radius        = 100,
        iconSize      = 40,
        gap           = 6,
        scale         = 1,
        gridAutoColumns = true,
        gridColumns   = 4,
        fanOrientation = "horizontal",  -- "horizontal" | "vertical"
        fanVisible    = 2,       -- entries drawn EACH SIDE of the strip's centre
        fanInvert     = false,
        fanMouseSelect = true,   -- exclusive hover channel on the strip
        toggleMode    = false,   -- keep the ring open after the key is released
        confirmKey    = "",      -- key that fires the aimed entry of a kept-open ring
        cancelKey     = "",      -- key that closes without firing (ESCAPE always works)
        showCooldowns = true,
        showUsability = true,
        showActionText = false,  -- entry name under each icon
        hideUnusable  = false,   -- filter entries this character cannot use
        showHubText   = true,
        showNeedle    = true,    -- pointer line from the centre (arc layout)
        selectColorMode = "accent",  -- "accent" | "class" | "custom"
        selectColor   = { r = 1, g = 0.82, b = 0.2 },
    },
})

-- Keybinding UI strings. Inside OnLocaleReady, never at file scope: evaluating
-- L[...] before the saved language override loads would bake the client locale.
ns.OnLocaleReady(function()
    _G["BINDING_HEADER_VULOACTIONRING"] = L["Action Ring"]
    for i = 1, MAX_MENUS do
        _G["BINDING_NAME_" .. BINDING_PREFIX .. i] = L["Action Ring %d"]:format(i)
    end
end)

-- C_Container namespace on newer clients, globals on older ones.
local GetItemCooldownFn = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown

-------------------------------------------------------------------------------
--  Data
-------------------------------------------------------------------------------

local function db() return mod.db end

local function menuCount()
    local c = tonumber(db().menuCount) or 1
    if c < 1 then c = 1 elseif c > MAX_MENUS then c = MAX_MENUS end
    return c
end

local function menu(i)
    local menus = db().menus
    if not menus[i] then menus[i] = { slots = {} } end
    menus[i].slots = menus[i].slots or {}
    return menus[i]
end

local function menuName(i)
    local m = db().menus[i]
    local n = m and m.name
    if n and n ~= "" then return n end
    return L["Action Ring %d"]:format(i)
end

-- Which profile keys a single ring may override. Everything else -- the
-- Select/cancel keys above all -- stays one profile value, so the gesture
-- means the same thing whichever ring is up.
local APPEARANCE_KEYS = {
    layout = true, centerMode = true, posX = true, posY = true, scale = true,
    arcSpan = true, arcRotation = true, radius = true, iconSize = true, gap = true,
    gridAutoColumns = true, gridColumns = true,
    fanOrientation = true, fanVisible = true, fanInvert = true, fanMouseSelect = true,
    showCooldowns = true, showUsability = true, showActionText = true,
    hideUnusable = true, showHubText = true, showNeedle = true,
    selectColorMode = true, selectColor = true,
    toggleMode = true,
}

-- One READ-ONLY view per ring: that ring's overrides in front of the profile.
-- Handing this back as `p` lets every renderer stay written as `p.layout` --
-- the fallback lives in one metatable instead of at sixty call sites. Keyed
-- by the menu TABLE, not the index: deleting a ring shifts the ones above it
-- down, and an override belongs to the ring, not to its position.
local appearanceViews = {}

local function PA(index)
    local m = index and db().menus[index]
    if type(m) ~= "table" then return db() end
    local view = appearanceViews[m]
    if not view then
        view = setmetatable({}, {
            __index = function(_, key)
                if APPEARANCE_KEYS[key] then
                    local v = m.appearance and m.appearance[key]
                    if v ~= nil then return v end
                end
                -- db() rather than a captured profile: the menu table can
                -- outlive a profile switch, the accessor cannot go stale.
                return db()[key]
            end,
            __newindex = function() error("ActionRing appearance view is read-only", 2) end,
        })
        appearanceViews[m] = view
    end
    return view
end

-- The three steering models behind the three layouts.
local function layoutModel(p)
    local l = p.layout
    if l == "grid" then return "POINTER" end
    if l == "fan" then return "SCROLL" end
    return "ANGULAR"
end

-- A cycling entry steps through the eight marker positions, one per press.
local CYCLE_N = 8

local function cycleSteps(kind)
    if kind ~= "cycleraidtarget" then return nil end
    local out = {}
    for i = 1, CYCLE_N do out[i] = "/tm " .. i end
    return out
end

-- The position the NEXT press places -- derived from the stored one, so there
-- is only ever one number to keep in step.
local function cycleNext(slot)
    local last = tonumber(slot and slot.cyclePos) or 0
    if last < 1 or last > CYCLE_N then last = 0 end
    return last % CYCLE_N + 1
end

-- One entry -> the (type, attribute key, value) triple the snippet stamps onto
-- the button. A slot that resolves to nothing either has no secure action
-- type at all (clearmarkers -> fired insecurely from PostClick) or is broken;
-- both cancel in the sandbox as "emptyslot" and PostClick sorts them apart.
local function resolveAction(slot)
    if not slot or not slot.kind then return nil end
    local kind = slot.kind
    if kind == "spell" and slot.id then
        -- By ID: casts exactly the rank that was picked, which matters here.
        return "spell", "spell", slot.id
    elseif kind == "item" and slot.id then
        return "item", "item", "item:" .. slot.id
    elseif kind == "macro" and slot.name then
        return "macro", "macro", slot.name
    elseif kind == "macrotext" and slot.text and slot.text ~= "" then
        return "macro", "macrotext", slot.text
    elseif kind == "raidtarget" and slot.id then
        -- One attribute per entry: the slash command carries the marker index.
        return "macro", "macrotext", "/tm " .. slot.id
    elseif kind == "cycleraidtarget" then
        -- The base value is the fallback; the real step list is pushed as
        -- vrCycV attributes and the snippet advances the position itself.
        return "macro", "macrotext", "/tm " .. cycleNext(slot)
    end
    return nil
end

-- Kinds with no secure action type fire from PostClick with ordinary API.
-- WHICH cell fires is still the snippet's answer ("emptyslot"), never the
-- highlight's -- the two part company on every cancel.
local function fireInsecure(slot)
    if slot and slot.kind == "clearmarkers" and RemoveRaidTargets then
        RemoveRaidTargets()
    end
end

-- Display half of the same entry: icon, label, and the functions the ring's
-- refresh tick uses. Kept next to resolveAction so the two read one slot shape.
local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

local function slotDisplay(slot)
    if not slot or not slot.kind then return nil, nil end
    local kind = slot.kind
    if kind == "spell" and slot.id then
        local name = GetSpellInfo(slot.id)
        return GetSpellTexture(slot.id), name or (slot.name or ("#" .. slot.id))
    elseif kind == "item" and slot.id then
        local icon = select(5, GetItemInfoInstant(slot.id))
        local name = GetItemInfo(slot.id)
        return icon, name or (slot.name or ("#" .. slot.id))
    elseif kind == "macro" and slot.name then
        local idx = GetMacroIndexByName(slot.name) or 0
        if idx > 0 then
            local name, icon = GetMacroInfo(idx)
            return icon, name
        end
        return 134400, slot.name   -- question mark: macro was deleted
    elseif kind == "macrotext" then
        return slot.icon or 134400, slot.name or L["Custom command"]
    elseif kind == "raidtarget" and slot.id then
        if slot.id == 0 then
            return "Interface\\Buttons\\UI-GroupLoot-Pass-Up", L["Remove marker"]
        end
        return RAID_ICON:format(slot.id), _G["RAID_TARGET_" .. slot.id] or L["Raid marker"]
    elseif kind == "cycleraidtarget" then
        -- Drawn as the marker the NEXT press will place.
        return RAID_ICON:format(cycleNext(slot)), L["Cycle raid markers"]
    elseif kind == "clearmarkers" then
        return "Interface\\Buttons\\UI-GroupLoot-Pass-Up", L["Clear all markers"]
    end
    return nil, nil
end

local function slotCooldown(slot)
    if not slot then return end
    if slot.kind == "spell" and slot.id then
        return GetSpellCooldown(slot.id)
    elseif slot.kind == "item" and slot.id and GetItemCooldownFn then
        return GetItemCooldownFn(slot.id)
    elseif slot.kind == "macro" and slot.name then
        local idx = GetMacroIndexByName(slot.name) or 0
        local spell = idx > 0 and GetMacroSpell and GetMacroSpell(idx)
        if spell then return GetSpellCooldown(spell) end
    end
end

local function slotUsable(slot)
    if not slot then return true end
    if slot.kind == "spell" and slot.id then
        local usable, noMana = IsUsableSpell(slot.id)
        return usable or noMana
    elseif slot.kind == "item" and slot.id then
        return (GetItemCount(slot.id) or 0) > 0
    end
    return true
end

local function slotCount(slot)
    if slot and slot.kind == "item" and slot.id then
        local c = GetItemCount(slot.id) or 0
        if c > 1 then return c end
    end
end

-- Can this character do anything with the slot? Only kinds that resolve
-- against one character's own kit are tested; items and markers stay.
local function slotKnown(slot)
    local k = slot and slot.kind
    if k == "spell" and slot.id then
        -- Fail OPEN: with no API to ask, hiding would take entries away on
        -- the strength of nothing.
        if not (IsPlayerSpell or IsSpellKnown) then return true end
        return (IsPlayerSpell and IsPlayerSpell(slot.id))
            or (IsSpellKnown and IsSpellKnown(slot.id)) or false
    elseif k == "macro" then
        return (GetMacroIndexByName(slot.name or "") or 0) > 0
    end
    return true
end

-- The entries of a ring this character can use ("Hide unusable entries").
-- A view, never a mutation: the stored slots keep every entry for the
-- characters that CAN use them. Memoised per menu table so the list pushed
-- to the sandbox and the list the visual draws are pinned to the SAME array
-- between one push and the opens that follow it; requestPush and the
-- spellbook/macro events drop the memo.
local usableMemo = setmetatable({}, { __mode = "k" })

local function usableSlots(m, p)
    local slots = m and m.slots
    if not slots then return {} end
    if not p.hideUnusable then return slots end
    local memo = usableMemo[m]
    if memo then return memo end
    local out
    for i = 1, #slots do
        if not slotKnown(slots[i]) then
            if not out then
                out = {}
                for j = 1, i - 1 do out[j] = slots[j] end
            end
        elseif out then
            out[#out + 1] = slots[i]
        end
    end
    usableMemo[m] = out or slots
    return out or slots
end

local function clearUsableMemo()
    wipe(usableMemo)
end

-------------------------------------------------------------------------------
--  Geometry -- shared by the visual ring, the hover highlight and the push.
-------------------------------------------------------------------------------

-- step, start, full -- all degrees, clockwise from 12 o'clock. A full circle
-- divides evenly; a sector spreads shown entries across the span with the
-- rotation at its middle.
local function arcGeom(p, shown)
    local span = tonumber(p.arcSpan) or 360
    if span < 30 then span = 30 elseif span > 360 then span = 360 end
    local rot = tonumber(p.arcRotation) or 0
    local full = span >= 359.5
    if shown <= 1 then
        return 0, rot, full
    end
    if full then
        return 360 / shown, rot, true
    end
    return span / (shown - 1), rot - span * 0.5, false
end

-- The radius GROWS with the entry count: entries are squares, so the smallest
-- ring that keeps neighbours apart needs chord 2*R*sin(step/2) >= their
-- diagonal separation. The configured radius is a floor, not the answer.
local function ringRadius(p, shown, step)
    local iconSize = tonumber(p.iconSize) or 40
    local r = tonumber(p.radius) or 100
    if shown > 1 and step > 0 and step < 360 then
        local sep = math.max(iconSize + (tonumber(p.gap) or 6), iconSize * 1.4142)
        local sinHalf = math.sin(math.rad(step * 0.5))
        if sinHalf > 0.001 then
            r = math.max(r, sep / (2 * sinHalf))
        end
    end
    return r
end

-- Cell pitch shared by the grid and the strip.
local function pitchOf(p)
    return (tonumber(p.iconSize) or 40) + (tonumber(p.gap) or 6)
end

-- Columns for a grid the user has not pinned: near-square, because a grid's
-- point is to shorten the WORST pointer travel. The remainder check widens by
-- one column when the final row would hold a single entry -- 7 becomes 4 + 3.
local GRID_REACH = 1.0

local function autoGridColumns(shown)
    local cols = math.ceil(math.sqrt(shown))
    if cols < shown and shown % cols == 1 then cols = cols + 1 end
    return math.min(MAX_SLOTS, math.max(1, cols))
end

local function gridDims(p, shown)
    local cols
    if p.gridAutoColumns ~= false then
        cols = autoGridColumns(math.max(1, shown))
    else
        cols = math.min(MAX_SLOTS, math.max(1, math.floor(tonumber(p.gridColumns) or 4)))
    end
    if cols > shown then cols = shown end
    return cols, math.ceil(shown / cols)
end

-- Centre-relative position of slot i; a short final row is centred.
local function gridBase(i, cols, rows, pitch, shown)
    local r = math.floor((i - 1) / cols)
    local c = (i - 1) % cols
    local inRow = math.min(cols, shown - r * cols)
    return (c - (inRow - 1) * 0.5) * pitch, -(r - (rows - 1) * 0.5) * pitch
end

-- The strip: fanVisible entries each side of the centre, culled by the same
-- asymmetric fold the snippet tests (entries land in (-n/2, n/2]).
local FAN_CANCEL_REACH = 2.25

local function fanWindow(p) return math.max(0, math.floor(tonumber(p.fanVisible) or 2)) end
local function fanHoriz(p) return p.fanOrientation ~= "vertical" end
local function fanHalfLength(p)
    return fanWindow(p) * pitchOf(p) + (tonumber(p.iconSize) or 40) * 0.5
end

-- The insecure mirrors of the snippet's steering. Each MUST stay in sync with
-- SNIPPET_PRE below: the highlight they drive is the promise of what the
-- release will fire. dx/dy are ring-local units, centre-relative.
local function hitAngular(dx, dy, shown, step, start, full)
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < DEAD_ZONE then return nil end
    if shown < 1 then return nil end
    if step == 0 then return 1 end
    local theta = math.deg(math.atan2(dx, dy))
    if theta < 0 then theta = theta + 360 end
    if full then
        return (math.floor((theta - start) / step + 0.5) % shown) + 1
    end
    local rel = (theta - start) % 360
    if rel <= (shown - 1) * step + step * 0.5 then
        local idx = math.floor(rel / step + 0.5) + 1
        if idx <= shown then return idx end
    end
    return nil
end

-- Nearest cell by true 2D distance in cell units; past GRID_REACH cells from
-- every entry nothing is selected -- the grid's cancel. No dead zone: the
-- centre of a grid can hold an entry.
local function hitGrid(dx, dy, cells, pitch)
    local best, bestK
    for i = 1, #cells do
        local px = (dx - cells[i].x) / pitch
        local py = (dy - cells[i].y) / pitch
        local k = math.sqrt(px * px + py * py)
        if not bestK or k < bestK then best, bestK = i, k end
    end
    if bestK and bestK > GRID_REACH then return nil end
    return best
end

-- The strip's exclusive hover: which drawn entry's own box the pointer is in,
-- measured from the strip's centre. Returns the FOLD OFFSET d, or nil for the
-- gaps, the space past the window and everything off the strip.
local function fanHoverOffset(p, along, across, shown)
    local pitch = pitchOf(p)
    if pitch <= 0 then return nil end
    if not fanHoriz(p) then along, across = -across, along end
    local band = (tonumber(p.iconSize) or 40) * 0.5
    local win = fanWindow(p)
    local d = math.floor(along / pitch + 0.5)
    if math.abs(across) <= band and math.abs(along - d * pitch) <= band
       and math.abs(d) <= win + 0.5 and d * 2 <= shown and -d * 2 < shown then
        return d
    end
    return nil
end

-- Thrown clear of the strip: past it in ANY direction, a margin across and
-- the drawn length plus that margin along.
local function fanThrownClear(p, along, across)
    if not fanHoriz(p) then along, across = across, along end
    local margin = FAN_CANCEL_REACH * pitchOf(p)
    return math.abs(across) > margin
        or math.abs(along) > fanHalfLength(p) + margin
end

-------------------------------------------------------------------------------
--  The visual ring -- an ordinary insecure frame; free to touch in combat.
-------------------------------------------------------------------------------

local ring          -- the frame; built lazily
local slices = {}   -- pooled entry widgets, indexed by SLOT
local secureButtons = {}
local cancelButton
local catcherFrame  -- full-screen wheel catcher; strip layout only
local secureHeader

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

local function newSlice(i)
    local s = CreateFrame("Frame", nil, ring, "BackdropTemplate")
    s:EnableMouse(false)
    s:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
    s:SetBackdropColor(0.05, 0.05, 0.06, 0.92)

    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 2, -2)
    s.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    s.cd = CreateFrame("Cooldown", nil, s, "CooldownFrameTemplate")
    s.cd:SetAllPoints(s.icon)
    s.cd:SetDrawEdge(false)

    s.count = s:CreateFontString(nil, "OVERLAY")
    s.count:SetFont(ns.UI.FONT_PATH, 11, "OUTLINE")
    s.count:SetPoint("BOTTOMRIGHT", -3, 3)

    s.label = s:CreateFontString(nil, "OVERLAY")
    s.label:SetFont(ns.UI.FONT_PATH, 10, "OUTLINE")
    s.label:SetPoint("TOP", s, "BOTTOM", 0, -2)
    s.label:SetTextColor(0.8, 0.8, 0.85)

    slices[i] = s
    return s
end

-- The selection cue's colour: the theme accent, the class colour, or the
-- ring's own pick. Read at paint time -- the accent is live-mutated.
local function selectionColor(p)
    local mode = p.selectColorMode
    if mode == "class" then
        local _, class = UnitClass("player")
        local c = class and ((ns.CLASS_COLORS and ns.CLASS_COLORS[class])
                             or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
        if c then return c.r, c.g, c.b end
    elseif mode == "custom" and type(p.selectColor) == "table" then
        local c = p.selectColor
        return c.r or 1, c.g or 1, c.b or 1
    end
    local ac = ns.COLORS.accent
    return ac.r, ac.g, ac.b
end

local function paintSelection(s, selected, p)
    if selected then
        s:SetBackdropBorderColor(selectionColor(p))
        s:SetScale(1.12)
    else
        s:SetBackdropBorderColor(0.22, 0.22, 0.27, 1)
        s:SetScale(1)
    end
end

local function ensureRing()
    if ring then return ring end
    ring = CreateFrame("Frame", "VuloActionRingFrame", UIParent)
    ring:SetFrameStrata("DIALOG")
    ring:SetSize(2, 2)
    ring:EnableMouse(false)
    ring:Hide()

    ring.title = ring:CreateFontString(nil, "OVERLAY")
    ring.title:SetFont(ns.UI.FONT_PATH, 13, "OUTLINE")
    ring.title:SetPoint("CENTER", 0, 8)

    ring.info = ring:CreateFontString(nil, "OVERLAY")
    ring.info:SetFont(ns.UI.FONT_PATH, 11, "OUTLINE")
    ring.info:SetPoint("CENTER", 0, -8)
    ring.info:SetTextColor(0.7, 0.7, 0.75)

    -- The pointer needle: a trail of dots from the dead zone toward the
    -- cursor, arc layout only. Dots rather than a rotated line texture --
    -- SetRotation turns a texture's coords, and a solid fill shows nothing of
    -- that; dots need no texture file, so no client restart to see them.
    ring.dots = {}
    for i = 1, 8 do
        local d = ring:CreateTexture(nil, "BACKGROUND")
        d:SetTexture(WHITE8X8)
        d:SetSize(3, 3)
        d:Hide()
        ring.dots[i] = d
    end

    return ring
end

local function hideNeedle()
    for i = 1, #ring.dots do ring.dots[i]:Hide() end
end

local closeRing   -- forward: OnUpdate below needs it

-- Fold offset of slot i on a strip centred on `target`: entries land in
-- (-n/2, n/2], the far side of an even fold staying empty ground -- the same
-- asymmetric rule the snippet's hover test applies.
local function fanFold(i, target, n)
    local d = (i - target) % n
    if d * 2 > n then d = d - n end
    return d
end

-- Lay the strip's window out around `target`. Slices stay indexed by slot;
-- everything the window or the fold culls is hidden.
local function placeFan(p, target)
    local n = ring.shown
    if n < 1 then return end
    local pitch = pitchOf(p)
    local win = fanWindow(p)
    local horiz = fanHoriz(p)
    for i = 1, n do
        local s = slices[i]
        local d = fanFold(i, target, n)
        if math.abs(d) <= win and d * 2 <= n and -d * 2 < n then
            s:ClearAllPoints()
            if horiz then
                s:SetPoint("CENTER", ring, "CENTER", d * pitch, 0)
            else
                s:SetPoint("CENTER", ring, "CENTER", 0, -d * pitch)
            end
            s:Show()
        else
            s:Hide()
        end
    end
    ring.fanTarget = target
end

-- The needle: dots from the dead zone toward the cursor's angle.
local function placeNeedle(p, dx, dy)
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < DEAD_ZONE * 0.5 then hideNeedle() return end
    local nx, ny = dx / dist, dy / dist
    local inner = DEAD_ZONE * 0.7
    local outer = math.max((ring.radius or 100) - (tonumber(p.iconSize) or 40) * 0.7, inner + 12)
    local r, g, b = selectionColor(p)
    local count = #ring.dots
    for i = 1, count do
        local t = (i - 0.5) / count
        local at = inner + (outer - inner) * t
        local d = ring.dots[i]
        d:ClearAllPoints()
        d:SetPoint("CENTER", ring, "CENTER", nx * at, ny * at)
        d:SetVertexColor(r, g, b, 0.15 + 0.5 * t)
        d:Show()
    end
end

-- The steering tick: highlight follows the cursor with the SAME maths the
-- snippet will use at release, cooldowns refresh on a slower beat, and a ring
-- nobody answers times out (out of combat only -- the secure teardown a
-- timeout needs is refused in a fight).
local lastCdTick = 0
local function onRingUpdate()
    local now = GetTime()
    if now - ring.openedAt > OPEN_TIMEOUT and not InCombatLockdown() then
        closeRing(true)
        return
    end

    -- Read, never vivify: the options page can delete or renumber rings while
    -- one is open, and menu() writing a phantom table past menuCount would
    -- persist it into the profile. A ring whose data is gone just closes.
    local ownMenu = db().menus[ring.ownerIndex]
    if not ownMenu or not ownMenu.slots then
        closeRing(true)
        return
    end
    local p = PA(ring.ownerIndex)

    local ui = UIParent
    local cx, cy = GetCursorPosition()
    local es = ui:GetEffectiveScale()
    cx, cy = cx / es, cy / es

    local s = ring.ringScale
    if not ring.moved then
        if math.abs(cx - ring.originX) / s >= 1 or math.abs(cy - ring.originY) / s >= 1 then
            ring.moved = true
        end
    end
    local dx = (cx - ring.centerX) / s
    local dy = (cy - ring.centerY) / s

    local idx
    if ring.model == "SCROLL" then
        -- The strip's index is owned by the secure catcher (the wheel may not
        -- write a button attribute from Lua in combat); reading it back here
        -- is unrestricted. The preview seeds the same attribute insecurely.
        local t = ring.fanTarget or 1
        if catcherFrame and catcherFrame:IsShown() then
            t = tonumber(catcherFrame:GetAttribute("vrFanTarget")) or t
        end
        if ring.shown > 0 then
            local target = ((t - 1) % ring.shown) + 1
            if target ~= ring.fanTarget then placeFan(p, target) end
            if p.fanMouseSelect then
                -- Exclusive hover: the release fires what the pointer is
                -- inside and NOTHING otherwise -- the wheel's entry has no
                -- standing of its own while the channel is on.
                local d = fanHoverOffset(p, dx, dy, ring.shown)
                idx = d and (((target - 1 + d) % ring.shown) + 1) or nil
            else
                idx = target
                -- Thrown clear is measured from the OPEN point, not the
                -- strip's centre -- the two differ in fixed-position mode.
                local tdx = (cx - ring.originX) / s
                local tdy = (cy - ring.originY) / s
                if fanThrownClear(p, tdx, tdy) then idx = nil end
            end
        end
    elseif ring.moved then
        if ring.model == "POINTER" then
            idx = hitGrid(dx, dy, ring.cells, ring.pitch)
        else
            idx = hitAngular(dx, dy, ring.shown, ring.step, ring.start, ring.full)
        end
    end

    if ring.model == "ANGULAR" and p.showNeedle and ring.moved then
        placeNeedle(p, dx, dy)
    end

    if idx ~= ring.selected then
        ring.selected = idx
        for i = 1, ring.shown do
            paintSelection(slices[i], i == idx, p)
        end
        local slot = idx and ring.fireList[idx]
        if slot then
            local _, name = slotDisplay(slot)
            ring.info:SetText(name or "")
        else
            ring.info:SetText(L["Release to cancel"])
        end
    end

    if now - lastCdTick > 0.2 then
        lastCdTick = now
        local slots = ring.fireList
        for i = 1, ring.shown do
            local w, slot = slices[i], slots[i]
            if p.showCooldowns then
                local start, duration = slotCooldown(slot)
                if start and duration and duration > 1.5 then
                    w.cd:SetCooldown(start, duration)
                else
                    w.cd:Clear()
                end
            end
            if p.showUsability then
                local usable = slotUsable(slot)
                w.icon:SetDesaturated(not usable)
                w.icon:SetAlpha(usable and 1 or 0.45)
            end
            local c = slotCount(slot)
            w.count:SetText(c and tostring(c) or "")
        end
    end
end

local releaseSecureState   -- forward

local function openRing(index, isPreview)
    ensureRing()
    local p = PA(index)
    local model = layoutModel(p)
    -- The FILTERED list ("Hide unusable entries"), pinned by the memo to the
    -- same array the last push handed the sandbox: what a cell index fires
    -- and what it draws must come off one list.
    local list = usableSlots(menu(index), p)
    local shown = math.min(#list, MAX_SLOTS)

    local iconSize = tonumber(p.iconSize) or 40
    local scale = tonumber(p.scale) or 1
    if scale <= 0 then scale = 1 end
    ring:SetScale(scale)

    -- Centre in UIParent units; the SetPoint offset is in the ring's own
    -- scaled space, hence the division.
    local ui = UIParent
    local w, h = ui:GetWidth(), ui:GetHeight()
    local cx, cy
    if p.centerMode == "screen" then
        cx = w * 0.5 + (tonumber(p.posX) or 0)
        cy = h * 0.5 + (tonumber(p.posY) or 0)
    else
        local mx, my = GetCursorPosition()
        local es = ui:GetEffectiveScale()
        cx, cy = mx / es, my / es
    end
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", ui, "BOTTOMLEFT", cx / scale, cy / scale)

    ring.model = model
    ring.pitch = pitchOf(p)
    ring.cells = nil
    ring.fanTarget = nil

    local step, start, full, radius
    if model == "ANGULAR" then
        step, start, full = arcGeom(p, shown)
        radius = ringRadius(p, shown, step)
    end

    for i = 1, shown do
        local s = slices[i] or newSlice(i)
        s:SetSize(iconSize, iconSize)
        local icon, label = slotDisplay(list[i])
        s.icon:SetTexture(icon or 134400)
        -- Pooled: the previous ring's usability tint must not survive, and the
        -- tick only repaints it while the option is ON.
        s.icon:SetDesaturated(false)
        s.icon:SetAlpha(1)
        s.cd:Clear()
        s.count:SetText("")
        s.label:SetText(p.showActionText and label or "")
        paintSelection(s, false, p)
        s:ClearAllPoints()
        if model == "ANGULAR" then
            local ang = math.rad(start + (i - 1) * step)
            s:SetPoint("CENTER", ring, "CENTER", math.sin(ang) * radius, math.cos(ang) * radius)
            s:Show()
        end
    end
    for i = shown + 1, #slices do slices[i]:Hide() end

    if model == "POINTER" then
        local cols, rows = gridDims(p, shown)
        local cells = {}
        for i = 1, shown do
            local bx, by = gridBase(i, cols, rows, ring.pitch, shown)
            cells[i] = { x = bx, y = by }
            slices[i]:SetPoint("CENTER", ring, "CENTER", bx, by)
            slices[i]:Show()
        end
        ring.cells = cells
    end

    ring.ownerIndex = index
    ring.shown      = shown
    ring.step       = step
    ring.start      = start
    ring.full       = full
    ring.radius     = radius
    ring.ringScale  = scale
    ring.centerX    = cx
    ring.centerY    = cy
    local ox, oy = GetCursorPosition()
    local es = ui:GetEffectiveScale()
    ring.originX    = ox / es
    ring.originY    = oy / es
    ring.moved      = false
    ring.selected   = nil
    ring.fireList   = list
    ring.openedAt   = GetTime()
    lastCdTick      = 0
    hideNeedle()

    if model == "SCROLL" and shown > 0 then
        placeFan(p, 1)
        -- A real hold's press snippet seeds and shows the catcher; a preview
        -- has no snippet, so it seeds insecurely -- out of combat only, the
        -- catcher is a protected frame.
        if isPreview and catcherFrame and not InCombatLockdown() then
            catcherFrame:SetAttribute("vrFanTarget", 1)
            catcherFrame:SetAttribute("vrShown", shown)
            catcherFrame:SetAttribute("vrInvert", p.fanInvert == true or nil)
            catcherFrame:SetAttribute("vrOpen", 1)
            catcherFrame:Show()
        end
    end

    if p.showHubText then
        ring.title:SetText(menuName(index))
        ring.info:SetText(shown > 0 and L["Release to cancel"] or L["This ring is empty - add entries in the options."])
        ring.title:Show()
        ring.info:Show()
    else
        ring.title:Hide()
        ring.info:Hide()
    end

    ring:SetScript("OnUpdate", onRingUpdate)
    ring:Show()
end

-- Visual close only. The secure half (ownership stamp, claimed keys) is torn
-- down by the release's own snippet; releaseState=true is for the closes that
-- never see a release -- timeout, module disable, an options-driven close.
closeRing = function(releaseState)
    if ring then
        ring:SetScript("OnUpdate", nil)
        ring:Hide()
        ring.ownerIndex = nil
    end
    if releaseState then releaseSecureState() end
end

-------------------------------------------------------------------------------
--  Secure core
-------------------------------------------------------------------------------

-- Everything below the ownership block runs twice per gesture: once with
-- down=true (the press) and once with down=false (the release). The wrapper
-- compiles the body against the fixed parameter list self,button,down --
-- `local button = ...` would be a compile error surfacing only in-game.
--
-- The clears write BOTH suffixed forms ("*type1" the keybind's, "*type2" the
-- Select key's) everywhere the logic clears one, so no stale half can fire.
local SNIPPET_PRE = [==[
    local ui = self:GetFrameRef("ui")
    local cancel = self:GetFrameRef("cancel")

    -- The only thing separating the three clicks that can land here: the
    -- ring's own keybind arrives as "LeftButton", the Select key of a
    -- kept-open ring as "RightButton", ESCAPE/cancel as "MiddleButton".
    local isConfirm = (button == "RightButton")
    local isEscape = (button == "MiddleButton")
    local isMenuKey = isConfirm or isEscape

    -- One ring at a time owns the screen, and the sandbox has to enforce it
    -- for itself: the insecure PreClick that refuses a second key runs before
    -- this and cannot stop the snippet behind it. The stamp lives on the
    -- shared cancel button; the owner's own release clears it (SNIPPET_POST).
    if cancel then
        local owner = cancel:GetAttribute("vrOwner")
        local me = self:GetAttribute("vrMenu")
        if isMenuKey then
            -- Positive ownership for a kept-open ring's own keys too: either
            -- of them reaching a ring that does not hold the screen is a
            -- binding that outlived the ring it was made for.
            if owner ~= me then
                self:SetAttribute("vrWhy", "taken")
                self:SetAttribute("*type1", nil)
                self:SetAttribute("*type2", nil)
                return nil, 1
            end
        elseif down then
            if owner and owner ~= me then
                self:SetAttribute("vrWhy", "taken")
                self:SetAttribute("*type1", nil)
                self:SetAttribute("*type2", nil)
                return nil, 1
            end
            cancel:SetAttribute("vrOwner", me)
        elseif owner ~= me then
            -- Positive ownership, not merely "nobody else": a release whose
            -- press was refused still holds the geometry of an earlier hold.
            self:SetAttribute("vrWhy", "taken")
            self:SetAttribute("*type1", nil)
            self:SetAttribute("*type2", nil)
            return nil, 1
        end
    end

    -- Neither menu key does anything on its press: the acting edge is the
    -- release (useOnKeyDown is pinned false on this button).
    if isMenuKey and down then
        self:SetAttribute("*type1", nil)
        self:SetAttribute("*type2", nil)
        return nil, 1
    end

    -- ESCAPE out of a kept-open ring: closes, fires nothing -- but drops the
    -- keep-open flag first, which is what lets SNIPPET_POST tear down.
    if isEscape then
        self:SetAttribute("vrLatched", nil)
        self:SetAttribute("vrIdx", nil)
        self:SetAttribute("vrWhy", "escaped")
        self:SetAttribute("*type1", nil)
        self:SetAttribute("*type2", nil)
        return nil, 1
    end

    if down then
        -- A kept-open ring whose own key is pressed again is the toggle
        -- shutting it. Only the flag drops here; the teardown waits for this
        -- press's RELEASE, where SNIPPET_POST does every part of it.
        if self:GetAttribute("vrLatched") then
            self:SetAttribute("vrLatched", nil)
            self:SetAttribute("vrWhy", "toggleclose")
            self:SetAttribute("vrIdx", nil)
            self:SetAttribute("*type1", nil)
            self:SetAttribute("*type2", nil)
            return nil, 1
        end
        self:SetAttribute("vrWhy", "pressed")
        self:SetAttribute("vrIdx", nil)
        if cancel then
            cancel:SetAttribute("vrCancel", nil)
            -- Keep-open needs BOTH the switch and a Select key: a ring kept
            -- open with nothing able to answer it would be stuck, so a
            -- half-configured ring keeps the hold-to-fire model instead.
            -- Every claimed key is owned by the cancel button, so one
            -- ClearBindings on close hands them all back together.
            local confirm = self:GetAttribute("vrConfirm")
            local latched
            if confirm and self:GetAttribute("vrToggle") then
                latched = true
                self:SetAttribute("vrLatched", 1)
                cancel:SetBindingClick(true, confirm, self, "RightButton")
                -- ESCAPE onto THIS button: a kept-open ring has no pending
                -- release to read a flag, so its ESCAPE must run the same
                -- teardown every other close runs.
                cancel:SetBindingClick(true, "ESCAPE", self, "MiddleButton")
            else
                cancel:SetBindingClick(true, "ESCAPE", cancel, "LeftButton")
            end
            -- The user's own cancel key, on whichever route this open uses.
            -- Never over the Select key: both on one chord would let the
            -- last binding written decide, and a ring that cancels when the
            -- user meant to fire is the worse reading.
            local cancelKey = self:GetAttribute("vrCancelKey")
            if cancelKey and cancelKey ~= confirm then
                if latched then
                    cancel:SetBindingClick(true, cancelKey, self, "MiddleButton")
                else
                    cancel:SetBindingClick(true, cancelKey, cancel, "LeftButton")
                end
            end
        end
        -- The origin this hold measures "has the cursor moved" against. Kept
        -- on the button, not in a snippet global: every ring shares one
        -- header, and a global would let ring 2's press reset ring 1's origin.
        self:SetAttribute("vrGX", nil)
        self:SetAttribute("vrGY", nil)
        if ui then
            local x, y = ui:GetMousePosition()
            if x then
                self:SetAttribute("vrGX", x * ui:GetWidth())
                self:SetAttribute("vrGY", y * ui:GetHeight())
            end
        end
        -- A strip is steered by the wheel: seed the catcher's accumulator at
        -- the centre entry and put it up to eat wheel ticks. Secure work --
        -- the whole point is that this happens mid-combat.
        if self:GetAttribute("vrMode") == "SCROLL" then
            local catcher = self:GetFrameRef("catcher")
            if catcher then
                catcher:SetAttribute("vrFanTarget", 1)
                catcher:SetAttribute("vrShown", self:GetAttribute("vrShown"))
                catcher:SetAttribute("vrInvert", self:GetAttribute("vrInvert"))
                catcher:SetAttribute("vrOpen", 1)
                catcher:Show()
            end
        end
        self:SetAttribute("*type1", nil)
        self:SetAttribute("*type2", nil)
        return nil, 1
    end

    -- ---- the RELEASE ----
    self:SetAttribute("*type1", nil)
    self:SetAttribute("*type2", nil)

    -- The release of the press that latched the ring open chooses nothing and
    -- tears nothing down: the ring is meant to outlive its key.
    if self:GetAttribute("vrLatched") and not isConfirm then
        self:SetAttribute("vrWhy", "latched")
        return nil, 1
    end
    -- The Select key ends the ring whatever it lands on. Dropped BEFORE the
    -- choosing so every cancel path below still reaches SNIPPET_POST's teardown.
    self:SetAttribute("vrLatched", nil)

    -- The release of the press that toggled a kept-open ring SHUT: its down
    -- edge dropped the flag, so the guard above cannot catch it -- without
    -- this it would resolve an entry and fire it on the way out. Safe to read
    -- vrWhy for this: its only writer is that down edge, one edge earlier.
    if self:GetAttribute("vrWhy") == "toggleclose" then return nil, 1 end

    -- Escaped while the key was still held. Checked before any steering, so
    -- it cannot be undone by moving the pointer back onto the ring.
    if cancel and cancel:GetAttribute("vrCancel") then
        self:SetAttribute("vrWhy", "escaped")
        return nil, 1
    end

    local n = tonumber(self:GetAttribute("vrShown")) or 0
    if n < 1 then self:SetAttribute("vrWhy", "noslots") return nil, 1 end
    if not ui then self:SetAttribute("vrWhy", "nohandle") return nil, 1 end
    local x, y = ui:GetMousePosition()
    local mode = self:GetAttribute("vrMode")
    -- Off-screen cancels only the POINTER-steered layouts: the cursor plays
    -- no part in steering a wheel-only strip, so its release stands -- firing
    -- what the user steered to is the safer of the two failures.
    if not x and mode ~= "SCROLL" then
        self:SetAttribute("vrWhy", "offscreen") return nil, 1
    end
    local w, h = ui:GetWidth(), ui:GetHeight()
    local cx, cy
    if x then cx, cy = x * w, y * h end

    local gx = tonumber(self:GetAttribute("vrGX"))
    local gy = tonumber(self:GetAttribute("vrGY"))
    local s = tonumber(self:GetAttribute("vrScale")) or 1
    if s <= 0 then s = 1 end

    local idx
    if mode == "SCROLL" then
        -- The wheel snippet has been keeping the accumulator; the cursor only
        -- steers this layout through the hover channel and the thrown-clear.
        local catcher = self:GetFrameRef("catcher")
        if not catcher then
            self:SetAttribute("vrWhy", "nocatcher") return nil, 1
        end
        local ft = tonumber(catcher:GetAttribute("vrFanTarget"))
        if not ft then
            -- The press seeds the accumulator, so this can only mean the
            -- press never reached the catcher. Nothing was steered; cancel.
            self:SetAttribute("vrWhy", "unscrolled") return nil, 1
        end
        idx = ((ft - 1) % n) + 1

        if self:GetAttribute("vrFanMouse") then
            -- Exclusive hover: the release fires the entry whose drawn box
            -- the pointer is inside, and NOTHING otherwise -- the wheel's
            -- entry has no standing of its own while the channel is on.
            -- Measured from the strip's own centre: the pinned point in
            -- fixed mode, the open point in cursor mode.
            local hx, hy = gx, gy
            if self:GetAttribute("vrFixed") then
                hx = w * 0.5 + (tonumber(self:GetAttribute("vrPosX")) or 0)
                hy = h * 0.5 + (tonumber(self:GetAttribute("vrPosY")) or 0)
            end
            local hovered
            local pitch = tonumber(self:GetAttribute("vrPitch")) or 0
            if pitch > 0 and hx and cx then
                local along = (cx - hx) / s
                local across = (cy - hy) / s
                -- NEGATED for a vertical strip: it runs downward, so below
                -- the centre is positive d. Mirrors the insecure hover test.
                if not self:GetAttribute("vrFanHoriz") then
                    along, across = -across, along
                end
                local band = tonumber(self:GetAttribute("vrFanBand")) or 0
                local win = tonumber(self:GetAttribute("vrFanWin")) or 0
                local d = floor(along / pitch + 0.5)
                -- Inside the icon's own box on BOTH axes (the gaps fire
                -- nothing), only a DRAWN entry: the window bound plus the
                -- asymmetric fold -- entries land in (-n/2, n/2].
                if abs(across) <= band and abs(along - d * pitch) <= band
                   and abs(d) <= win + 0.5 and d * 2 <= n and -d * 2 < n then
                    hovered = ((ft - 1 + d) % n) + 1
                end
            end
            if not hovered then
                self:SetAttribute("vrIdx", nil)
                self:SetAttribute("vrWhy", "nothover")
                return nil, 1
            end
            idx = hovered
        elseif gx and cx then
            -- Thrown clear of the strip: past it in ANY direction, measured
            -- from where the pointer was when the strip opened. A margin
            -- across, the drawn length plus that margin along.
            local margin = tonumber(self:GetAttribute("vrFanMargin"))
            local half = tonumber(self:GetAttribute("vrFanHalf"))
            if margin and half then
                local along, across = (cx - gx) / s, (cy - gy) / s
                if not self:GetAttribute("vrFanHoriz") then
                    along, across = across, along
                end
                if abs(across) > margin or abs(along) > half + margin then
                    self:SetAttribute("vrIdx", nil)
                    self:SetAttribute("vrWhy", "thrownclear")
                    return nil, 1
                end
            end
        end
    else
        -- Opening under the cursor would otherwise arrive with an entry
        -- already chosen; nothing counts until the pointer has moved a
        -- ring-space unit. Erring toward cancelling rather than firing
        -- something unintended. The wheel layouts are exempt: their steering
        -- is the wheel, not the pointer.
        if gx and abs(cx - gx) / s < 1 and abs(cy - gy) / s < 1 then
            self:SetAttribute("vrWhy", "unmoved")
            return nil, 1
        end

        local ox, oy
        if self:GetAttribute("vrFixed") then
            ox = w * 0.5 + (tonumber(self:GetAttribute("vrPosX")) or 0)
            oy = h * 0.5 + (tonumber(self:GetAttribute("vrPosY")) or 0)
        elseif gx then
            ox, oy = gx, gy
        else
            self:SetAttribute("vrWhy", "noorigin")
            return nil, 1
        end
        local dx, dy = (cx - ox) / s, (cy - oy) / s

        if mode == "POINTER" then
            -- Nearest cell by true 2D distance in cell units; a grid has no
            -- privileged axis. Past vrReach cells from every entry nothing is
            -- selected -- the grid's cancel, and it has no dead zone: the
            -- centre of a grid can hold an entry.
            local pitch = tonumber(self:GetAttribute("vrPitch")) or 1
            if pitch <= 0 then pitch = 1 end
            local bestK
            for i = 1, n do
                local bx = tonumber(self:GetAttribute("vrBX" .. i))
                local by = tonumber(self:GetAttribute("vrBY" .. i))
                if bx then
                    local px, py = (dx - bx) / pitch, (dy - by) / pitch
                    local k = (px * px + py * py) ^ 0.5
                    if not bestK or k < bestK then idx, bestK = i, k end
                end
            end
            if bestK and bestK > (tonumber(self:GetAttribute("vrReach")) or 1) then
                idx = nil
            end
            if not idx then
                self:SetAttribute("vrIdx", nil)
                self:SetAttribute("vrWhy", "outofreach")
                return nil, 1
            end
        else
            local dist = (dx * dx + dy * dy) ^ 0.5
            local theta = atan2(dx, dy)
            if theta < 0 then theta = theta + 360 end

            local dz = tonumber(self:GetAttribute("vrDeadZone")) or 24
            if dist < dz then self:SetAttribute("vrWhy", "deadzone") return nil, 1 end
            local step = tonumber(self:GetAttribute("vrStepDeg")) or 0
            if step == 0 then
                idx = 1
            else
                local rel = theta - (tonumber(self:GetAttribute("vrStartDeg")) or 0)
                if self:GetAttribute("vrFull") then
                    idx = (floor(rel / step + 0.5) % n) + 1
                else
                    rel = rel % 360
                    if rel <= (n - 1) * step + step * 0.5 then
                        idx = floor(rel / step + 0.5) + 1
                        -- Exactly on the sector's outer boundary rounds up
                        -- past the last entry; the range check below repeats
                        -- the guard the insecure mirror makes.
                        if idx > n then idx = nil end
                    end
                end
            end
        end
    end

    self:SetAttribute("vrIdx", idx)
    if not idx or idx < 1 or idx > n then
        self:SetAttribute("vrWhy", "noidx")
        return nil, 1
    end

    local t = self:GetAttribute("vrT" .. idx)
    if not t then self:SetAttribute("vrWhy", "emptyslot") return nil, 1 end

    -- Clear every action key before writing this entry's, so no earlier
    -- entry's value can outlive it: type="macro" reads "macro" before it
    -- falls through to "macrotext", and type="spell" would happily reuse a
    -- stale "spell".
    self:SetAttribute("*spell1", nil)
    self:SetAttribute("*spell2", nil)
    self:SetAttribute("*item1", nil)
    self:SetAttribute("*item2", nil)
    self:SetAttribute("*macro1", nil)
    self:SetAttribute("*macro2", nil)
    self:SetAttribute("*macrotext1", nil)
    self:SetAttribute("*macrotext2", nil)

    -- A cycling entry names a different marker on every press, and the
    -- position advances HERE: an insecure SetAttribute is refused in combat,
    -- which is the whole of when marking matters. The Lua side reads the
    -- position back off the button once the release is over.
    local v = self:GetAttribute("vrV" .. idx)
    local cn = tonumber(self:GetAttribute("vrCycN" .. idx))
    if cn and cn > 0 then
        local pos = (tonumber(self:GetAttribute("vrCycPos" .. idx)) or 0) % cn + 1
        self:SetAttribute("vrCycPos" .. idx, pos)
        v = self:GetAttribute("vrCycV" .. idx .. "_" .. pos) or v
    end
    local k = self:GetAttribute("vrK" .. idx)
    self:SetAttribute("*" .. k .. "1", v)
    self:SetAttribute("*" .. k .. "2", v)
    self:SetAttribute("*type1", t)
    self:SetAttribute("*type2", t)
    self:SetAttribute("vrWhy", "fire")
    return nil, 1
]==]

local SNIPPET_POST = [==[
    if down then return end
    self:SetAttribute("*type1", nil)
    self:SetAttribute("*type2", nil)
    -- A kept-open ring keeps everything standing: the ownership stamp, the
    -- claimed keys. Whatever ends the ring clears the flag first, so the run
    -- that really closes it reaches the teardown below.
    if self:GetAttribute("vrLatched") then return end
    -- Only the ring that owns the screen may put shared state away: a second
    -- key refused its press has nothing of its own to tear down and would
    -- otherwise tear down the hold still in progress.
    local cancel = self:GetFrameRef("cancel")
    if cancel and cancel:GetAttribute("vrOwner") ~= self:GetAttribute("vrMenu") then
        return
    end
    if cancel then
        cancel:SetAttribute("vrOwner", nil)
        -- Hand ESCAPE (and the Select/cancel keys) back to the game.
        cancel:ClearBindings()
    end
    -- Every close funnels through here, including the cancels that returned
    -- early in the pre-snippet, so the catcher stops eating camera zoom on
    -- all of them.
    local catcher = self:GetFrameRef("catcher")
    if catcher then
        catcher:SetAttribute("vrOpen", nil)
        catcher:Hide()
    end
]==]

-- ESCAPE while a ring is held open. It cannot be an insecure key handler: the
-- release that follows is resolved inside the snippet, and only secure code
-- may leave it a flag readable in combat. The button performs no action of
-- its own -- it never gets a type -- so the click exists purely to run this.
-- The catcher goes down now rather than at the release: the key may be held
-- a while yet, and the strip's catcher is still eating camera zoom.
local SNIPPET_CANCEL = [==[
    self:SetAttribute("vrCancel", 1)
    local catcher = self:GetFrameRef("catcher")
    if catcher then
        catcher:SetAttribute("vrOpen", nil)
        catcher:Hide()
    end
]==]

-- One wheel tick. This is the ONLY place a live strip's index advances: an
-- addon may not write these attributes once the player is in combat. The
-- wrapped OnMouseWheel pre-body is compiled as "self,offset" -- `offset` IS
-- the delta (SecureHandlers.lua, CreateSimpleWrapper).
local SNIPPET_WHEEL = [==[
    if not self:GetAttribute("vrOpen") then
        -- Nothing has this open, so it must stop eating camera zoom. The
        -- self-heal for a strip that never saw its key-up -- a zone change
        -- swallowing the release -- at the cost of one notch of zoom.
        self:Hide()
        return false
    end
    local n = tonumber(self:GetAttribute("vrShown")) or 0
    if n < 1 then return false end
    local delta = offset
    if self:GetAttribute("vrInvert") then delta = -delta end
    -- Scrolling up travels toward earlier entries.
    local step = -1
    if delta <= 0 then step = 1 end
    self:SetAttribute("vrFanTarget",
        (tonumber(self:GetAttribute("vrFanTarget")) or 1) + step)
    return false
]==]

local function ensureSecureHeader()
    if secureHeader then return secureHeader end
    secureHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    return secureHeader
end

-- Full-screen, mouse-WHEEL only, never EnableMouse: a mouse-enabled frame
-- would sit between the player and the world and swallow the very clicks the
-- secure activation path depends on. An override binding on MOUSEWHEELUP/DOWN
-- is not an option either -- those are protected and could not be claimed at
-- open time in combat, which is exactly when the strip gets used.
local function ensureCatcher()
    if catcherFrame then return catcherFrame end
    local f = CreateFrame("Frame", "VuloActionRingCatcher", UIParent,
        "SecureHandlerBaseTemplate")
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(1)
    f:EnableMouseWheel(true)
    SecureHandlerWrapScript(f, "OnMouseWheel", ensureSecureHeader(), SNIPPET_WHEEL)
    f:Hide()
    catcherFrame = f
    return f
end

-- Closing the ring on screen is insecure work on an ordinary frame.
local function onCancelPostClick()
    closeRing(false)
end

local function ensureCancelButton()
    if cancelButton then return cancelButton end
    local btn = CreateFrame("Button", "VuloActionRingCancel", UIParent,
        "SecureActionButtonTemplate")
    -- Down only: ESCAPE takes effect the instant it is pressed.
    btn:RegisterForClicks("AnyDown")
    -- Parked: invisible, unclickable by mouse, but SHOWN -- an
    -- override-binding click has to reach a live button.
    btn:EnableMouse(false)
    btn:SetSize(1, 1)
    btn:SetAlpha(0)
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -400, 100)
    btn:Show()
    btn:SetScript("PostClick", onCancelPostClick)
    SecureHandlerSetFrameRef(btn, "catcher", ensureCatcher())
    SecureHandlerWrapScript(btn, "OnClick", ensureSecureHeader(), SNIPPET_CANCEL)
    cancelButton = btn
    return btn
end

local requestPush   -- forward

local pushDirty = false
local function flushPendingPush()
    if not pushDirty then return end
    if InCombatLockdown() then return end   -- RunOutOfCombatOnce below re-runs this
    pushDirty = false
    -- Wiped ONLY when a push actually lands: the memo is what keeps the drawn
    -- ring and the pushed secure attributes reading the SAME list even when
    -- the spellbook shifts between the push and an open mid-fight. Usability
    -- goes stale until the next push rather than ever disagreeing with what a
    -- cell index fires.
    clearUsableMemo()
    for i = 1, menuCount() do
        if secureButtons[i] then mod.PushMenu(i) end
    end
end

local function ownsRing(self)
    return ring and ring.ownerIndex == self._menuIndex and ring:IsShown()
end

local function onPreClick(self, button, down)
    -- A kept-open ring's own two keys open nothing: the ring they answer is
    -- already up. Everything they do happens in the snippet and PostClick.
    if button == CONFIRM_BUTTON or button == CANCEL_BUTTON then return end
    if down then
        -- Pressed again while kept open = toggling shut; the snippet handles it.
        if self:GetAttribute("vrLatched") then return end
        -- Between an edit and the coalescer's timer the ring would DRAW new
        -- contents while the button still fires the old ones. A press is the
        -- moment that stops being tolerable.
        flushPendingPush()
        -- A second ring key pressed while the first is still HELD leaves the
        -- screen to the one already on it; the sandbox refuses it too. A
        -- PREVIEW is the inverse: a visual with no sandbox owner behind it.
        -- The snippet would accept this press and fire with no ring drawn
        -- for it, so the preview yields instead of blocking.
        if ring and ring:IsShown() and not ownsRing(self) then
            local held = cancelButton and cancelButton:GetAttribute("vrOwner")
            if held then return end
            closeRing(true)
        end
        -- The sandbox's ownership stamp outlives the visual on an ESCAPE
        -- during a hold. Without this mirror-check, a second key pressed in
        -- that window would draw a ring the sandbox will never let fire —
        -- steering and promising with nothing behind it.
        local owner = cancelButton and cancelButton:GetAttribute("vrOwner")
        if owner and owner ~= self._menuIndex then return end
        openRing(self._menuIndex)
    end
end

local function onPostClick(self, _, down)
    if down then return end
    if not ownsRing(self) then return end
    local why = self:GetAttribute("vrWhy")
    -- The release that latched the ring open closes nothing; every other
    -- value reaching here ends it. Which entry fired is the SNIPPET's answer,
    -- never the highlight's -- the two part company on every cancel. Only
    -- "fire" and "emptyslot" mean a cell was chosen: "emptyslot" is what a
    -- kind with no secure action type looks like from inside the sandbox.
    if why == "latched" then return end
    if why == "fire" or why == "emptyslot" then
        local idx = tonumber(self:GetAttribute("vrIdx"))
        local slot = idx and ring and ring.fireList and ring.fireList[idx]
        if why == "emptyslot" then
            fireInsecure(slot)
        elseif slot then
            -- The cycle position the snippet advanced, back onto the slot it
            -- belongs to, so the next push and every icon drawn before it
            -- agree with what actually fired. Reading an attribute is
            -- unrestricted, so this works in combat too.
            local pos = tonumber(self:GetAttribute("vrCycPos" .. idx))
            if pos and cycleSteps(slot.kind) then slot.cyclePos = pos end
        end
    end
    closeRing(false)
end

local function getSecureButton(index)
    local btn = secureButtons[index]
    if btn then return btn end
    btn = CreateFrame("Button", BUTTON_PREFIX .. index, UIParent,
        "SecureActionButtonTemplate")
    btn._menuIndex = index
    -- The same number readable from inside the sandbox: the ownership test
    -- needs to know which ring it runs for, and a plain field is invisible
    -- there. Written at build time, which is out of combat by construction.
    btn:SetAttribute("vrMenu", index)
    btn:RegisterForClicks("AnyDown", "AnyUp")
    -- The secure template acts on exactly one edge:
    --   clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)
    -- Left unset it follows the ActionButtonUseKeyDown CVar (on by default),
    -- which would make the DOWN edge -- where we open and clear the type --
    -- the acting one, and the UP edge dead. Pinning keeps the action on UP.
    btn:SetAttribute("useOnKeyDown", false)
    btn:EnableMouse(false)
    btn:SetSize(1, 1)
    btn:SetAlpha(0)
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -300 - index * 4, 100)
    btn:Show()
    btn:SetScript("PreClick", onPreClick)
    btn:SetScript("PostClick", onPostClick)
    SecureHandlerSetFrameRef(btn, "ui", UIParent)
    SecureHandlerSetFrameRef(btn, "cancel", ensureCancelButton())
    SecureHandlerSetFrameRef(btn, "catcher", ensureCatcher())
    -- Wrapped around OnClick, not PreClick: the wrap has to run inside the
    -- very click that goes on to perform the action.
    SecureHandlerWrapScript(btn, "OnClick", ensureSecureHeader(),
        SNIPPET_PRE, SNIPPET_POST)
    secureButtons[index] = btn
    return btn
end

-- Hand the sandbox everything it needs to choose an entry. Out of combat
-- only: these are ordinary insecure writes to a protected frame. A ring
-- edited mid-fight keeps firing its old contents until the fight ends -- the
-- same bargain the override bindings make.
function mod.PushMenu(index)
    if InCombatLockdown() then return end
    local btn = secureButtons[index]
    if not btn then return end
    local p = PA(index)
    local slots = usableSlots(menu(index), p)
    local n = math.min(#slots, MAX_SLOTS)

    for i = 1, MAX_SLOTS do
        local slot = i <= n and slots[i] or nil
        local aType, aKey, aVal
        if slot then aType, aKey, aVal = resolveAction(slot) end
        btn:SetAttribute("vrT" .. i, aType)
        btn:SetAttribute("vrK" .. i, aKey)
        btn:SetAttribute("vrV" .. i, aVal)

        -- A cycling entry's whole run, one step per attribute, plus the
        -- position it is up to. vrCycN is what marks the cell as cycling, so
        -- a cell that has stopped being one loses it -- and the steps under
        -- it, which are read by position and would outlive a shorter run.
        local steps = slot and cycleSteps(slot.kind)
        local had = tonumber(btn:GetAttribute("vrCycN" .. i)) or 0
        for st = 1, math.max(had, steps and #steps or 0) do
            btn:SetAttribute("vrCycV" .. i .. "_" .. st, steps and steps[st] or nil)
        end
        btn:SetAttribute("vrCycN" .. i, steps and #steps or nil)
        btn:SetAttribute("vrCycPos" .. i, steps and (tonumber(slot.cyclePos) or 0) or nil)
    end

    local model = layoutModel(p)
    btn:SetAttribute("vrMode", model)
    btn:SetAttribute("vrShown", n)
    btn:SetAttribute("vrDeadZone", DEAD_ZONE)
    btn:SetAttribute("vrFixed", p.centerMode == "screen" or nil)
    btn:SetAttribute("vrPosX", tonumber(p.posX) or 0)
    btn:SetAttribute("vrPosY", tonumber(p.posY) or 0)
    btn:SetAttribute("vrScale", tonumber(p.scale) or 1)
    btn:SetAttribute("vrToggle", p.toggleMode == true or nil)
    local confirm = db().confirmKey
    btn:SetAttribute("vrConfirm", (type(confirm) == "string" and confirm ~= "") and confirm or nil)
    local cancelKey = db().cancelKey
    btn:SetAttribute("vrCancelKey", (type(cancelKey) == "string" and cancelKey ~= "") and cancelKey or nil)

    -- Angular geometry is pushed for every model (the mode decides what is
    -- read), the cell table only where it means something.
    local step, start, full = arcGeom(p, n)
    btn:SetAttribute("vrStepDeg", step)
    btn:SetAttribute("vrStartDeg", start)
    btn:SetAttribute("vrFull", full or nil)

    local pitch = pitchOf(p)
    btn:SetAttribute("vrPitch", pitch)
    if model == "POINTER" then
        local cols, rows = gridDims(p, n)
        for i = 1, MAX_SLOTS do
            if i <= n then
                local bx, by = gridBase(i, cols, rows, pitch, n)
                btn:SetAttribute("vrBX" .. i, bx)
                btn:SetAttribute("vrBY" .. i, by)
            else
                btn:SetAttribute("vrBX" .. i, nil)
                btn:SetAttribute("vrBY" .. i, nil)
            end
        end
        btn:SetAttribute("vrReach", GRID_REACH)
    end

    btn:SetAttribute("vrInvert", p.fanInvert == true or nil)
    if model == "SCROLL" then
        btn:SetAttribute("vrFanHoriz", fanHoriz(p) or nil)
        btn:SetAttribute("vrFanMargin", FAN_CANCEL_REACH * pitch)
        btn:SetAttribute("vrFanHalf", fanHalfLength(p))
        if p.fanMouseSelect ~= false then
            btn:SetAttribute("vrFanMouse", 1)
            btn:SetAttribute("vrFanBand", (tonumber(p.iconSize) or 40) * 0.5)
            btn:SetAttribute("vrFanWin", fanWindow(p))
        else
            btn:SetAttribute("vrFanMouse", nil)
        end
    end
end

-- Edits arrive in bursts (every slider tick, every list edit), so pushes
-- coalesce: one flag, one timer, and a combat flush deferred to the regen.
requestPush = function()
    if pushDirty then return end
    pushDirty = true
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("actionring-push", flushPendingPush)
    else
        C_Timer.After(0.05, flushPendingPush)
    end
end

-- For the closes that never see a release: timeout, disable, options-driven.
releaseSecureState = function()
    ns:RunOutOfCombatOnce("actionring-release", function()
        if cancelButton then
            ClearOverrideBindings(cancelButton)
            cancelButton:SetAttribute("vrOwner", nil)
            cancelButton:SetAttribute("vrCancel", nil)
        end
        for _, btn in pairs(secureButtons) do
            btn:SetAttribute("vrLatched", nil)
        end
        -- The preview's strip has no release snippet to put this away.
        if catcherFrame then
            catcherFrame:SetAttribute("vrOpen", nil)
            catcherFrame:Hide()
        end
    end)
end

-------------------------------------------------------------------------------
--  Bindings
-------------------------------------------------------------------------------

local bindOwner
local bindingSig

-- Every free modifier combination of a bound key is also routed to the same
-- button, so a modifier pressed DURING the hold still reaches the release --
-- without it, holding SHIFT while aiming would swallow the release entirely.
local MOD_COMBOS = { "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-",
                     "ALT-CTRL-", "ALT-CTRL-SHIFT-" }
local MOD_STRIP  = { "ALT-", "CTRL-", "SHIFT-", "META-" }

local function baseKey(key)
    for i = 1, #MOD_STRIP do
        local m = MOD_STRIP[i]
        if key:sub(1, #m) == m then key = key:sub(#m + 1) end
    end
    return key
end

-- GetBindingAction answers the BASE binding, leaving override bindings out --
-- ours and other addons' alike -- which is what this wants: our own overrides
-- are the thing being decided here. A CLICK binding onto one of our own
-- buttons is answered as free for the case where overrides ARE counted:
-- otherwise a key the player takes back in the panel would keep reading as
-- taken and the override would shadow their new binding until a reload.
local function keyIsFree(key)
    local action = GetBindingAction(key)
    if action == nil or action == "" then return true end
    return action:find("^CLICK " .. BUTTON_PREFIX) ~= nil
end

-- Which combinations of a key are ours to take, as characters of the binding
-- signature: a combination the player later binds to something else has to be
-- handed straight back, and UPDATE_BINDINGS is the only notice of that.
local function modifierSig(key)
    if not key then return "" end
    local base, out = baseKey(key), "|"
    for i = 1, #MOD_COMBOS do
        out = out .. (keyIsFree(MOD_COMBOS[i] .. base) and "1" or "0")
    end
    return out
end

local function bindWithModifiers(name, key, claimed)
    if not key then return end
    local base = baseKey(key)
    -- Only combinations that KEEP everything the player already holds to
    -- press this key are ours: dropping a required modifier is a different
    -- gesture. Without this, a ring on SHIFT-T would also take plain T.
    local mods = key:sub(1, #key - #base)
    -- META is stripped but never re-added; a key bound with it has no
    -- variant that keeps it, so pass 1's own binding is all it gets.
    if mods:find("META-", 1, true) then return end
    local alt   = mods:find("ALT-",   1, true) ~= nil
    local ctrl  = mods:find("CTRL-",  1, true) ~= nil
    local shift = mods:find("SHIFT-", 1, true) ~= nil
    for i = 1, #MOD_COMBOS do
        local combo = MOD_COMBOS[i]
        if (not alt   or combo:find("ALT-",   1, true))
           and (not ctrl  or combo:find("CTRL-",  1, true))
           and (not shift or combo:find("SHIFT-", 1, true)) then
            local k = combo .. base
            if not claimed[k] and keyIsFree(k) then
                SetOverrideBindingClick(bindOwner, false, k, name)
                claimed[k] = true
            end
        end
    end
end

-- The signature guard is required for correctness, not an optimisation:
-- registering an override binding itself fires UPDATE_BINDINGS, which is what
-- brings us here -- an unconditional rewrite feeds itself forever. It also
-- makes the call free for the options page, which reaches it per widget tick.
function mod.UpdateBindings()
    local enabled = ns:IsModuleEnabled("actionring")
    local sig = enabled and "on" or "off"
    local count = menuCount()
    for i = 1, count do
        local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
        sig = sig .. "|" .. (k1 or "") .. "/" .. (k2 or "")
        sig = sig .. modifierSig(k1) .. modifierSig(k2)
    end
    if sig == bindingSig then return end

    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("actionring-bind", mod.UpdateBindings)
        return
    end
    bindingSig = sig

    if bindOwner then ClearOverrideBindings(bindOwner) end
    if not enabled then return end
    if not bindOwner then bindOwner = CreateFrame("Frame") end

    -- Two passes, and the order is what makes them right: every key the
    -- player actually chose is placed first, so a modifier variant one ring
    -- would like can never land on top of a key another ring was GIVEN.
    -- `claimed` is rebuilt per rebind: every SetOverrideBindingClick fires
    -- UPDATE_BINDINGS, which re-enters and turns back at the guard above.
    local built = false
    local claimed = {}
    for i = 1, count do
        local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
        if k1 or k2 then
            built = built or not secureButtons[i]
            local name = getSecureButton(i):GetName()
            if k1 then
                SetOverrideBindingClick(bindOwner, false, k1, name)
                claimed[k1] = true
            end
            if k2 then
                SetOverrideBindingClick(bindOwner, false, k2, name)
                claimed[k2] = true
            end
        end
    end
    for i = 1, count do
        local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
        if k1 or k2 then
            local name = secureButtons[i]:GetName()
            bindWithModifiers(name, k1, claimed)
            bindWithModifiers(name, k2, claimed)
        end
    end

    -- A button built just now holds none of its ring's geometry yet; without
    -- this, the first hold on a freshly bound key would open an empty ring.
    if built then requestPush() end
end

-------------------------------------------------------------------------------
--  Module lifecycle
-------------------------------------------------------------------------------

function mod:OnEnable()
    self:RegisterEvent("UPDATE_BINDINGS", function() mod.UpdateBindings() end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        mod.UpdateBindings()
        clearUsableMemo()
        pushDirty = true
        flushPendingPush()
    end)
    -- The usable filter answers off the spellbook and the macro list; both
    -- can change under a pushed ring.
    self:RegisterEvent("SPELLS_CHANGED", function() requestPush() end)
    self:RegisterEvent("UPDATE_MACROS", function() requestPush() end)
    mod.UpdateBindings()
    pushDirty = true
    if not InCombatLockdown() then flushPendingPush() end
end

function mod:OnDisable()
    closeRing(true)
    -- Signature "off" clears every override binding; the parked secure
    -- buttons stay (frames cannot be destroyed) but nothing routes to them.
    mod.UpdateBindings()
end

-- Centre-relative picture of ring `index` for the options page's preview:
-- where every drawn entry would sit at open, through the SAME geometry
-- helpers the real open uses -- no second copy of the maths to drift apart.
-- The slots come unfiltered: the page previews the list being edited, not
-- the usability of the moment. Also hands back where the page's add button
-- naturally sits: the arc's free middle, the grid's next cell, one pitch
-- past the strip's last drawn entry; an empty ring puts it in the middle.
local function previewLayout(index)
    local p = PA(index)
    local model = layoutModel(p)
    local slots = menu(index).slots or {}
    local shown = math.min(#slots, MAX_SLOTS)
    local out = {
        model    = model,
        total    = shown,   -- the strip culls entries below; this stays the count
        iconSize = tonumber(p.iconSize) or 40,
        scale    = math.max(tonumber(p.scale) or 1, 0.01),
        showText = p.showActionText == true,
        plusX    = 0,
        plusY    = 0,
        entries  = {},
    }
    if shown == 0 then return out end

    if model == "ANGULAR" then
        local step, start = arcGeom(p, shown)
        local radius = ringRadius(p, shown, step)
        for i = 1, shown do
            local ang = math.rad(start + (i - 1) * step)
            out.entries[i] = { slot = slots[i],
                x = math.sin(ang) * radius, y = math.cos(ang) * radius }
        end
    elseif model == "POINTER" then
        local pitch = pitchOf(p)
        local cols, rows = gridDims(p, shown)
        for i = 1, shown do
            local x, y = gridBase(i, cols, rows, pitch, shown)
            out.entries[i] = { slot = slots[i], x = x, y = y }
        end
        -- No "next cell" for the button: adding an entry recentres the last
        -- row (and can reflow the whole grid), so that cell is never where
        -- the preview draws free ground. It parks below the picture instead.
        if shown < MAX_SLOTS then
            out.plusY = -(rows + 1) * 0.5 * pitch - out.iconSize * 0.5
        end
    else -- SCROLL: the strip's opening state, target on slot 1, same cull
        local pitch = pitchOf(p)
        local win = fanWindow(p)
        local horiz = fanHoriz(p)
        local far = 0
        for i = 1, shown do
            local d = fanFold(i, 1, shown)
            if math.abs(d) <= win and d * 2 <= shown and -d * 2 < shown then
                local x, y = d * pitch, 0
                if not horiz then x, y = 0, -d * pitch end
                out.entries[#out.entries + 1] = { slot = slots[i], x = x, y = y }
                if d > far then far = d end
            end
        end
        if horiz then out.plusX = (far + 1) * pitch
        else out.plusY = -(far + 1) * pitch end
    end
    return out
end

-- Everything the options file needs, in one place -- same pattern as the
-- nameplates split. The options half may be loaded or replaced without the
-- runtime half changing shape.
mod.optionsBridge = {
    MAX_MENUS      = MAX_MENUS,
    MAX_SLOTS      = MAX_SLOTS,
    BINDING_PREFIX = BINDING_PREFIX,
    APPEARANCE_KEYS = APPEARANCE_KEYS,
    menuCount      = menuCount,
    menu           = menu,
    menuName       = menuName,
    slotDisplay    = slotDisplay,
    -- Per-ring overrides: the raw table (created on demand) for the page's
    -- setters, the read view for its getters.
    menuAppearance = function(i, create)
        local m = menu(i)
        if create and not m.appearance then m.appearance = {} end
        return m.appearance
    end,
    pa             = PA,
    previewLayout  = previewLayout,
    requestPush    = function() requestPush() end,
    updateBindings = function() mod.UpdateBindings() end,
    openPreview    = function(i) openRing(i, true) end,
    closeRing      = function() closeRing(true) end,
}
