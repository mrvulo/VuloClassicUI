-- VuloClassicUI / Modules / NameplatesOptions: the settings page of the nameplates.
--
-- WHY THIS IS ITS OWN FILE
-- Modules/Nameplates.lua had grown to 3066 lines, and 26 % of it was this page:
-- code that only runs while the options window is open, sitting in the same
-- file as the code that redraws every nameplate on every health tick. Three
-- rounds of layout work this cycle touched only this half and reloaded all of
-- it. The runtime half is also the taint-sensitive one -- it hides Blizzard's
-- frames and keeps a side table of plates -- and that is the half a settings
-- change should never be able to reach.
--
-- It was NOT split because of a compiler limit. Measured: 153 of Lua's 200
-- locals per chunk, and the worst function used 23 of its 60 upvalues. There
-- was room. There was just no reason to spend it here.
--
-- Everything past the header below is the original text, moved unchanged. The
-- names it read as file-scope locals of the other file are re-created here from
-- mod.optionsBridge, which is why no line inside GetOptions had to be rewritten
-- -- with one exception, marked where it stands.
local _, ns = ...
local L   = ns.L
local mod = ns.modules.nameplates   -- loads after Nameplates.lua, so this is set

local rt = mod.optionsBridge
local textureValues       = rt.textureValues
local borderTextureValues = rt.borderTextureValues
local buildPreview        = rt.buildPreview
local PREVIEW_CTX         = rt.previewCtx

-- Three tabs; labels are locale KEYS, translated when the tab row renders.
mod.tabs = {
    { id = "display", label = "Display" },
    { id = "colors",  label = "Colours" },
    { id = "general", label = "General" },
}

-- The live preview is a PINNED page header now (user request, 31.07.2026):
-- it used to be the first scrolling item, held in place by a scroll-follow
-- re-anchor. Shown on every tab -- the colour tabs change its look just as
-- much as the display tab does.
function mod.BuildPageHeader(host, tabId)
    -- Display tab only (user request, 31.07.2026) -- the colour and general
    -- tabs get the full scroll height back. A returned 0 hides the header.
    if tabId ~= nil and tabId ~= "default" and tabId ~= "display" then return 0 end
    local f = buildPreview(host)
    f:ClearAllPoints()
    -- Both corners, not a centred fixed width: the box spans the whole
    -- content area (user request, 31.07.2026); the mock plate inside stays
    -- centred by its own anchor.
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 14, -4)
    f:SetPoint("TOPRIGHT", host, "TOPRIGHT", -14, -4)
    -- pinned for real: the scroll-follow re-anchor stands down (see
    -- stickPreview in Modules/Nameplates.lua)
    f._pinned = true
    -- The reserved height, and it has to track the card's own height in
    -- buildPreview (Modules/Nameplates.lua) -- this number is what the scroll
    -- area gives up, that one is what fills it. Both came down together on
    -- 02.08.2026: the card was sized for a fully-loaded mock and stood mostly
    -- empty. 8 more than the card, for the gap above and below.
    return 126
end
local refreshPage         = rt.refreshPage
local applyAndRefresh     = rt.applyAndRefresh
local applyFriendlyCVar   = rt.applyFriendlyCVar
local applyHitbox         = rt.applyHitbox
local updateHoverTicker   = rt.updateHoverTicker
local floor               = math.floor

local function fontValues()
    local vals = { { value = "", text = L["Addon font (default)"] } }
    if ns.LSM then
        for _, name in ipairs(ns.LSM:List("font") or {}) do
            vals[#vals + 1] = { value = name, text = name }
        end
    end
    return vals
end

local function textModeValues()
    return {
        { value = "none",       text = L["No text"] },
        { value = "percent",    text = L["Percent"] },
        { value = "current",    text = L["Current value"] },
        { value = "currentmax", text = L["Current / Max"] },
        { value = "both",       text = L["Value + percent"] },
    }
end

local function reactionPreviewValues()
    return {
        { value = "hostile",  text = L["Hostile"] },
        { value = "neutral",  text = L["Neutral"] },
        { value = "friendly", text = L["Friendly"] },
    }
end

local function friendlyModeValues()
    return {
        { value = "nameonly", text = L["Name only"] },
        { value = "full",     text = L["Full plate"] },
        { value = "hidden",   text = L["Hidden"] },
    }
end

local function markerPosValues()
    return {
        { value = "left",  text = L["Left"] },
        { value = "right", text = L["Right"] },
        { value = "top",   text = L["Above"] },
    }
end

local function borderStyleValues()
    return {
        { value = "lines",   text = L["Thin lines"] },
        { value = "texture", text = L["Texture"] },
    }
end

-- ONE ROW PER SLOT.
--
-- The old model let every aura row pick its own side and growth, which meant
-- two rows could claim the same spot and land on top of each other. Six named
-- slots and one content each makes that impossible by construction -- picking a
-- content for a slot takes it away from whatever slot held it before.
--
-- Storage is unchanged: a slot is just a (side, grow) pair on the row it holds,
-- and the two new sides are the only genuinely new thing. So an existing
-- profile keeps working and needs no migration -- its rows simply show up in
-- whichever slot their current side and growth already describe.
local SLOTS = {
    { key = "top",      label = "Top",       side = "top",    grow = "center" },
    { key = "topleft",  label = "Top left",  side = "top",    grow = "right"  },
    { key = "topright", label = "Top right", side = "top",    grow = "left"   },
    { key = "left",     label = "Left",      side = "left",   grow = "center" },
    { key = "right",    label = "Right",     side = "right",  grow = "center" },
    { key = "bottom",   label = "Bottom",    side = "bottom", grow = "center" },
}

-- row key -> the switch that turns it on, so a slot can hold the whole thing
local SLOT_ROWS = {
    { key = "debuff", label = "Debuffs",           show = "showDebuffs" },
    { key = "buff",   label = "Buffs",             show = "showBuffs"   },
    { key = "cc",     label = "Crowd control",     show = "showCC"      },
    { key = "dot",    label = "Your own debuffs",  show = "showDots"    },
}

local function slotOf(rowKey)
    local cfg  = ns:NameplateRowCfg(rowKey)
    local side = cfg.side or "top"
    local grow = cfg.grow or "center"
    for _, s in ipairs(SLOTS) do
        if s.side == side and (s.side == "left" or s.side == "right" or s.grow == grow) then
            return s.key
        end
    end
    return "top"
end

-- What sits in this slot right now: the first row that is switched ON and
-- points here. Switched-off rows are ignored, so a slot reads as empty when
-- nothing is drawn in it -- which is what the eye expects.
local function contentOf(slotKey)
    for _, r in ipairs(SLOT_ROWS) do
        if mod.db[r.show] and slotOf(r.key) == slotKey then return r.key end
    end
    return "none"
end

-- `quiet` skips the repaint. Only the layout preset passes it: it writes five
-- slots in one click, and without it the page would be torn down and rebuilt
-- five times for one visible change.
local function setSlot(slotKey, rowKey, quiet)
    local slot
    for _, s in ipairs(SLOTS) do if s.key == slotKey then slot = s end end
    if not slot then return end

    -- whatever was here loses its place
    local prev = contentOf(slotKey)
    if prev ~= "none" and prev ~= rowKey then
        for _, r in ipairs(SLOT_ROWS) do
            if r.key == prev then mod.db[r.show] = false end
        end
    end

    if rowKey ~= "none" then
        for _, r in ipairs(SLOT_ROWS) do
            if r.key == rowKey then mod.db[r.show] = true end
        end
        local cfg = ns:NameplateRowCfg(rowKey)
        cfg.side, cfg.grow = slot.side, slot.grow
    end
    if quiet then return end
    applyAndRefresh()
    refreshPage()
end

local function slotValues()
    local vals = { { value = "none", text = L["None"] } }
    for _, r in ipairs(SLOT_ROWS) do
        vals[#vals + 1] = { value = r.key, text = L[r.label] }
    end
    return vals
end

-- slotItems is built further down, once rowPlacementItems exists: it is a plain
-- local, so referring to it from up here would resolve to a nil global.
local slotItems

local function rowFilterValues()
    return {
        { value = "all",    text = L["Everything"] },
        { value = "mine",   text = L["Only mine"] },
        { value = "dispel", text = L["Only removable"] },
    }
end

-- How much of each edge an aura row's icons trim, per row. It sits beside the
-- row's icon size rather than in the slot gear: size and crop are the same
-- question asked twice, and a control that only appears once a slot is filled
-- would be missing exactly while you are looking at the icons.
--
-- Stored as a fraction on the row config, and stored as ABSENT while it matches
-- the 0.08 every plate icon used to hardcode -- the same rule the orientation
-- setting follows, so an untouched profile stays byte-identical.
local function cropSlider(key, SLW)
    local function cfg() return ns:NameplateRowCfg(key) end
    return { type = "slider", label = L["Icon crop (%)"], min = 0, max = 25, step = 1, width = SLW,
        tooltip = L["How much is cut off each edge of the icon. 0 shows the whole icon including the border baked into its artwork."],
        get = function() return math.floor(((cfg().crop or 0.08) * 100) + 0.5) end,
        set = function(_, v)
            if v == 8 then cfg().crop = nil else cfg().crop = v / 100 end
            applyAndRefresh()
        end }
end

-- Placement controls shared by every aura row; `key` selects which row's
-- settings the widgets read and write. withFilter is off for the rows whose
-- contents are already defined by what they collect (crowd control, your DoTs).
-- Side and growth are NOT offered here any more: the slot decides both, and a
-- second control for the same thing could put a row where its own slot says it
-- is not. What is left is the fine tuning that genuinely belongs to the row --
-- offsets, wrapping, filter.
--
-- `stacked` returns the SAME rows one per line instead of in pairs. The paired
-- shape is right on the page, where a row is a full content width; in the slot
-- panel it is not, and the first build proved it -- at half of 250px every
-- label came out as "Ver - t..." and the panel was unreadable (user report,
-- 02.08.2026). Same rows, same order, same setters: only the wrapping differs.
local function rowPlacementItems(key, SLW, applyAndRefresh, withFilter, stacked)
    local function cfg() return ns:NameplateRowCfg(key) end
    local items = {}
    -- A pair on the page, two lines in the panel.
    local function pair(a, b)
        if stacked then
            items[#items + 1] = a
            items[#items + 1] = b
        else
            items[#items + 1] = { type = "group", layout = "row", gap = 8, items = { a, b } }
        end
    end
    -- Stacking axis (user request, 31.07.2026). Automatic is stored as an
    -- ABSENT field, not a value: old profiles stay byte-identical and the
    -- engine's fallback (side slots = column, top/bottom = row) stays the
    -- single source of the default.
    items[#items + 1] = { type = "dropdown", label = L["Orientation"], width = 300,
        tooltip = L["Automatic stacks a side slot as a column and a top or bottom slot as a row."],
        values = {
            { value = "auto", text = L["Automatic"] },
            { value = "h",    text = L["Horizontal"] },
            { value = "v",    text = L["Vertical"] },
        },
        get = function() return cfg().orient or "auto" end,
        set = function(_, v)
            if v == "auto" then cfg().orient = nil else cfg().orient = v end
            applyAndRefresh()
        end }
    pair(
        { type = "slider", label = L["Offset X"], min = -150, max = 150, step = 1, width = SLW,
          get = function() return cfg().x or 0 end,
          set = function(_, v) cfg().x = v; applyAndRefresh() end },
        { type = "slider", label = L["Offset Y"], min = -100, max = 100, step = 1, width = SLW,
          get = function() return cfg().y or 0 end,
          set = function(_, v) cfg().y = v; applyAndRefresh() end })
    pair(
        { type = "slider", label = L["Icon spacing"], min = 0, max = 12, step = 1, width = SLW,
          get = function() return cfg().spacing or 2 end,
          set = function(_, v) cfg().spacing = v; applyAndRefresh() end },
        { type = "slider", label = L["Icons per line"], min = 0, max = 12, step = 1, width = SLW,
          tooltip = L["0 = one line. Otherwise the row wraps after this many icons."],
          get = function() return cfg().perRow or 0 end,
          set = function(_, v) cfg().perRow = v; applyAndRefresh() end })
    if withFilter then
        items[#items + 1] = { type = "dropdown", label = L["Limit to"], width = 300, values = rowFilterValues(),
            tooltip = L["Narrows this row to auras you cast yourself, or to ones that can be removed."],
            get = function() return cfg().filter or "all" end,
            set = function(_, v) cfg().filter = v; applyAndRefresh() end }
    end
    return items
end

-- ---------------------------------------------------------------------------
-- General text: where each text ON an icon or ON the cast bar sits. "None" is
-- the off switch -- the four booleans this replaces were migrated into these
-- positions on first load (see migrateTextPositions in Modules/Nameplates.lua).
local function auraTextPosValues()
    return {
        { value = "none",        text = L["None"] },
        { value = "topleft",     text = L["Top left"] },
        { value = "topright",    text = L["Top right"] },
        { value = "bottomleft",  text = L["Bottom left"] },
        { value = "bottomright", text = L["Bottom right"] },
        { value = "center",      text = L["Centre"] },
    }
end

local function castTextPosValues()
    return {
        { value = "none",   text = L["None"] },
        { value = "left",   text = L["Left"] },
        { value = "right",  text = L["Right"] },
        { value = "center", text = L["Centre"] },
    }
end

-- One aura row's duration text. The position lives on the row config beside its
-- placement, because it IS placement -- just one level down, on the icon.
local function durationRow(rowKey, label)
    local function cfg() return ns:NameplateRowCfg(rowKey) end
    return { type = "dropdown", label = label, width = 260,
        subKey = "durpos/" .. rowKey,
        values = auraTextPosValues(),
        get = function() return cfg().timerPos or "center" end,
        set = function(_, v) cfg().timerPos = v; applyAndRefresh() end,
        inline = {
            { kind = "color", tooltip = L["Timer text colour"],
              get = function() return mod.db.auraTimerColor end,
              set = function(r, g, b)
                  mod.db.auraTimerColor = { r = r, g = g, b = b }; applyAndRefresh()
              end },
            { kind = "popup", tooltip = L["Text settings"],
              popup = { title = label, width = 380, items = {
                  { type = "slider", label = L["Timer text size"], min = 6, max = 20, step = 1, width = 130,
                    get = function() return mod.db.auraTimerSize end,
                    set = function(_, v) mod.db.auraTimerSize = v; applyAndRefresh() end },
                  { type = "checkbox", label = L["Timer decimals below 10 seconds"],
                    tooltip = L["On: 9.9, 3.4 … Off: whole seconds (9, 3)."],
                    get = function() return mod.db.auraTimerDecimals ~= false end,
                    set = function(_, v) mod.db.auraTimerDecimals = v; applyAndRefresh() end },
              } } },
        } }
end

-- ---------------------------------------------------------------------------
-- Text slots: the same model one level down, for the texts ON the plate
-- (user request, 02.08.2026). Four places, two things that can fill them.
--
-- The level is deliberately not a content: it rides at the name's left edge and
-- reads as part of it, which is a relationship "one thing per slot" cannot
-- express -- giving it a slot of its own would let you park it across the bar
-- from the name it belongs to.
local TEXT_SLOTS = {
    { key = "top",    label = "Top text" },
    { key = "left",   label = "Left text" },
    { key = "right",  label = "Right text" },
    { key = "center", label = "Centred text" },
}
local TEXT_ROWS = {
    { key = "name",   label = "Unit name" },
    { key = "health", label = "Health text" },
}

-- Built lazily, never at file scope: L[...] read while this file loads would
-- bake the client language in before the saved override arrives.
local HEALTH_TEXT_MODES, HEALTH_TEXT_SEPARATORS
ns.OnLocaleReady(function()
    HEALTH_TEXT_MODES = {
        { value = "percent",    text = L["Percent"] },
        { value = "current",    text = L["Current health"] },
        { value = "currentmax", text = L["Current and maximum"] },
        { value = "both",       text = L["Current and percent"] },
    }
    -- The value IS the format string the runtime hands to format(); both
    -- placeholders have to survive, which is why these are picked from a list
    -- rather than typed in. Named after the mark, not shown as a sample number:
    -- a sample would have to be translated nine times and would then disagree
    -- with whatever digit grouping the player actually sees.
    HEALTH_TEXT_SEPARATORS = {
        { value = "%s (%s)", text = L["Brackets"] },
        { value = "%s | %s", text = L["Vertical bar"] },
        { value = "%s - %s", text = L["Dash"] },
        -- ONE space, because that is the value the control that used to live in
        -- the removed Text section wrote. Two would match no stored profile,
        -- and a dropdown that finds no match shows its raw value -- the player
        -- would be looking at the literal characters of the format string.
        { value = "%s %s",   text = L["Space"] },
    }
end)

local function textCfg(key) return ns:NameplateTextCfg(key) end

local function textContentOf(slotKey)
    for _, r in ipairs(TEXT_ROWS) do
        if textCfg(r.key).slot == slotKey then return r.key end
    end
    return "none"
end

-- Same exchange rule as the aura slots: giving a slot something takes it away
-- from wherever it was, and evicts whatever was here.
local function setTextSlot(slotKey, rowKey, quiet)
    local prev = textContentOf(slotKey)
    if prev ~= "none" and prev ~= rowKey then textCfg(prev).slot = "none" end
    if rowKey ~= "none" then textCfg(rowKey).slot = slotKey end
    if quiet then return end   -- see setSlot: the preset repaints once at the end
    applyAndRefresh()
    refreshPage()
end

local function textSlotValues()
    local vals = { { value = "none", text = L["None"] } }
    for _, r in ipairs(TEXT_ROWS) do vals[#vals + 1] = { value = r.key, text = L[r.label] } end
    return vals
end

-- What the panel behind a text slot's two arrows holds: where it sits inside
-- the slot, and -- for the health text -- what it says.
local function textSlotPanelItems(rowKey)
    local function cfg() return textCfg(rowKey) end
    local items = {
        { type = "slider", label = L["Offset X"], min = -150, max = 150, step = 1, width = 130,
          get = function() return cfg().x or 0 end,
          set = function(_, v) cfg().x = v; applyAndRefresh() end },
        { type = "slider", label = L["Offset Y"], min = -100, max = 100, step = 1, width = 130,
          get = function() return cfg().y or 0 end,
          set = function(_, v) cfg().y = v; applyAndRefresh() end },
    }
    -- WHAT the health text says used to stay in the "Text" section, so that it
    -- was not controlled from two places at once. That section is gone
    -- (02.08.2026) and took the only home these two had with it: the runtime
    -- still reads both, every profile still carries whatever it had, and
    -- nothing could change them any more. So they come back HERE, which is now
    -- the only place -- not a second one.
    --
    -- The two travel together on purpose. The separator is only ever read in
    -- "current and percent" mode, so on its own it would be a control that does
    -- nothing for every profile in any other mode, which reads as a fault.
    if rowKey == "health" then
        -- NEITHER setter calls refreshPage. These two live inside a popup whose
        -- item list is a snapshot taken when it opened, and rebuilding the page
        -- CLOSES that popup -- a repaint here would shut the panel in the
        -- player's face on every change, which is worse than what it buys.
        --
        -- That is also why the separator is drawn ALWAYS instead of appearing
        -- with the mode that reads it: making it conditional needs exactly the
        -- repaint that closes the panel. Its tooltip carries the dependency.
        items[#items + 1] = { type = "dropdown", label = L["Shows"], width = 200,
            values = HEALTH_TEXT_MODES,
            get = function() return mod.db.healthTextMode or "percent" end,
            set = function(_, v) mod.db.healthTextMode = v; applyAndRefresh() end }
        items[#items + 1] = { type = "dropdown", label = L["Separator"], width = 200,
            tooltip = L["What goes between the two numbers, when the row above is set to current and percent."],
            values = HEALTH_TEXT_SEPARATORS,
            get = function() return mod.db.healthTextFormat or "%s (%s)" end,
            set = function(_, v) mod.db.healthTextFormat = v; applyAndRefresh() end }
    end
    return items
end

local function textSlotItems()
    local items = {}
    for _, s in ipairs(TEXT_SLOTS) do
        local rowKey = textContentOf(s.key)
        items[#items + 1] = {
            type = "dropdown", label = L[s.label], width = 260,
            subKey = "textslot/" .. s.key,
            values = textSlotValues(),
            get = function() return textContentOf(s.key) end,
            set = function(_, v) setTextSlot(s.key, v) end,
            -- NO colour swatch here, unlike the reference row. Our unit name
            -- takes its colour from the class or the reaction (nameByClass,
            -- friendlyNameColor, friendlyNPCColor) and the health text from the
            -- text section -- a flat per-slot override would fight both, and
            -- inventing that fight is not what "put the rows in this order"
            -- asked for. The colours stay where they are, on the Colours tab.
            inline = (rowKey ~= "none") and {
                { kind = "popup", tooltip = L["Fine tuning for this slot"],
                  popup = { title = L[s.label] .. " — " .. L["Slot settings"],
                            width = 380, items = textSlotPanelItems(rowKey) } },
            } or nil,
        }
    end
    return items
end

-- ---------------------------------------------------------------------------
-- Layout preset
--
-- One arrangement the owner asked for by picture (03.08.2026): the name and the
-- health value INSIDE the bar, crowd control to the left of it, incoming
-- debuffs above that, buffs to the right, and a cast bar carrying its icon, its
-- remaining time and its target.
--
-- It sits HERE, below the text slots, because it writes through three different
-- setters and all three have to exist first. Three shapes, because the module
-- stores these three ways: plain keys on the module db, the TEXT slots and the
-- AURA slots. Each goes through the setter that owns it -- the preset must not
-- learn the exchange rules a second time, or the two copies drift apart.
--
-- Applying is reversible. The first click snapshots exactly what it is about to
-- overwrite, a second click re-applies WITHOUT touching that snapshot (or the
-- restore would hand back already-preset values), and the restore drops it.
local PRESET_FLAGS = {
    healthTextMode   = "both",
    healthTextFormat = "%s | %s",
    showCastbar      = true,
    showCastIcon     = true,
    castIconRight    = false,
    castTimer        = true,
    -- castTargetText is NOT the switch any more, the same way nameInBar is not:
    -- a one-shot migration reads it once and every profile that has drawn a
    -- plate is long past that, so writing it would set a key nobody reads.
    -- castTargetSide is what the runtime asks, and "center" is its name for
    -- UNDER the bar -- which is where the picture puts the target.
    --
    -- The name goes left in the same breath, because the two sides are mutually
    -- exclusive: leaving the name on its default centre and putting the target
    -- there too is the one combination the options page blanks on sight.
    castNameSide     = "left",
    castTargetSide   = "center",
}
local PRESET_TEXT_SLOTS = { left = "name", right = "health" }
local PRESET_AURA_SLOTS = { left = "cc",   topleft = "debuff", right = "buff" }

local function applyLayoutPreset()
    local d = mod.db
    if not d then return end

    if not d.layoutBackup then
        local b = { flags = {}, text = {}, aura = {} }
        for k in pairs(PRESET_FLAGS) do b.flags[k] = d[k] end
        -- Every text and aura row is snapshotted, not just the ones the preset
        -- names: placing a row into a slot EVICTS whatever sat there, so rows
        -- the preset never mentions still change under it.
        for _, r in ipairs(TEXT_ROWS) do b.text[r.key] = textCfg(r.key).slot end
        for _, r in ipairs(SLOT_ROWS) do
            local cfg = ns:NameplateRowCfg(r.key)
            b.aura[r.key] = { side = cfg.side, grow = cfg.grow, show = d[r.show] and true or false }
        end
        d.layoutBackup = b
    end

    for k, v in pairs(PRESET_FLAGS) do d[k] = v end
    for slotKey, rowKey in pairs(PRESET_TEXT_SLOTS) do setTextSlot(slotKey, rowKey, true) end
    for slotKey, rowKey in pairs(PRESET_AURA_SLOTS) do setSlot(slotKey, rowKey, true) end

    applyAndRefresh()
    refreshPage()
    ns:Print(L["Nameplate layout applied. The button beside it puts your old one back."])
end

local function restoreLayoutPreset()
    local d = mod.db
    local b = d and d.layoutBackup
    if not b then return end

    for k, v in pairs(b.flags or {}) do d[k] = v end
    for rowKey, slot in pairs(b.text or {}) do textCfg(rowKey).slot = slot end
    for rowKey, saved in pairs(b.aura or {}) do
        local cfg = ns:NameplateRowCfg(rowKey)
        cfg.side, cfg.grow = saved.side, saved.grow
        for _, r in ipairs(SLOT_ROWS) do
            if r.key == rowKey then d[r.show] = saved.show end
        end
    end

    d.layoutBackup = nil
    applyAndRefresh()
    refreshPage()
    ns:Print(L["Nameplate layout restored."])
end

-- The restore button exists only while a snapshot does; both handlers rebuild
-- the page, which is what makes it appear and disappear.
local function presetRow()
    local row = {
        type = "group", layout = "row", gap = 10, align = "center",
        items = {
            { type = "button", label = L["Apply this arrangement"],
              width = 240, primary = true,
              tooltip = L["Puts the unit name and the health value inside the bar, crowd control left of it, incoming debuffs above that and buffs to its right, and gives the cast bar its icon, its remaining time and its target. Your current arrangement is saved first and the button beside this one brings it back."],
              onClick = applyLayoutPreset },
        },
    }
    if mod.db and mod.db.layoutBackup then
        row.items[#row.items + 1] = {
            type = "button", label = L["Restore my arrangement"],
            -- Says the whole truth: the snapshot covers every text and aura row,
            -- not only the ones the preset names, because placing a row EVICTS
            -- whatever sat in that slot. So anything moved by hand after the
            -- apply goes back too -- which is what makes the eviction undoable.
            tooltip = L["Puts every text and aura position back to what it was before the arrangement was applied, and removes the saved copy. Anything you moved by hand since then goes back as well."],
            onClick = restoreLayoutPreset }
    end
    return row
end

-- Declared above, filled here: it needs rowPlacementItems.
-- No slider width any more: every control these rows own lives in the panel,
-- which sizes its own.
slotItems = function(applyAndRefresh)
    local items = {}
    for _, s in ipairs(SLOTS) do
        local rowKey = contentOf(s.key)
        items[#items + 1] = {
            type = "dropdown", label = L[s.label], width = 260,
            subKey = "slot/" .. s.key,
            values = slotValues(),
            get = function() return contentOf(s.key) end,
            set = function(_, v) setSlot(s.key, v) end,
            -- The fine tuning belongs to whatever row sits here right now, and
            -- an empty slot has nothing to tune -- so an empty slot gets no
            -- icon at all.
            --
            -- A PANEL, not the gear (user request, 02.08.2026). The gear unfolds
            -- a sub-column inside the row's own cell, and these rows are half
            -- cells in a two-column grid: six offset sliders would have squeezed
            -- into a 180px stub. The panel opens over the page at a width that
            -- fits them.
            inline = (rowKey ~= "none") and {
                { kind = "popup", tooltip = L["Fine tuning for this slot"],
                  popup = {
                      title = L[s.label] .. " — " .. L["Slot settings"],
                      -- Wide enough for label + track + value block on ONE line.
                      -- Measured, not guessed: the label column is capped at
                      -- half the content width, and "Beschraenken auf" plus its
                      -- info dot needs 127px -- which 320 (cap 125) clipped to
                      -- "Beschraen...". 380 leaves the cap at 155.
                      width = 380,
                      -- stacked: one row per line, see rowPlacementItems
                      items = rowPlacementItems(rowKey, 130, applyAndRefresh,
                                  rowKey == "debuff" or rowKey == "buff", true),
                  } },
            } or nil,
        }
    end
    return items
end

local function outlineValues()
    return {
        { value = "OUTLINE",      text = L["Outline"] },
        { value = "THICKOUTLINE", text = L["Thick outline"] },
        { value = "SHADOW",       text = L["Shadow"] },
        { value = "",             text = L["None"] },
    }
end

function mod:GetOptions(tabId)
    local SLW = 180
    -- The preview is no longer an item here: it is the PINNED page header
    -- (mod.BuildPageHeader below), visible on every tab at every scroll.
    local all = {
        { type = "desc",
          text = L["|cffaaaaaaCustom nameplates for enemies and NPCs. Configure below — the live preview updates as you change each option.|r"] },

        -- Not a section, so the filter at the bottom of this function keeps it
        -- on the Display tab, where the live preview is.
        presetRow(),

        { type = "group", layout = "row", gap = 8, items = {
            { type = "dropdown", label = L["Preview reaction"], width = 300, values = reactionPreviewValues(),
              get = function()
                  if PREVIEW_CTX.reaction >= 5 then return "friendly"
                  elseif PREVIEW_CTX.reaction == 4 then return "neutral" end
                  return "hostile"
              end,
              set = function(_, v)
                  PREVIEW_CTX.reaction = (v == "friendly" and 5) or (v == "neutral" and 4) or 2
                  PREVIEW_CTX.enemy    = (v ~= "friendly")
                  -- The one rewritten line: previewFrame is nil until the page
                  -- is first built, so it has to be read through the bridge.
                  rt.updatePreview()
              end },
        } },

        -- The look of a plate, in three paired rows, before anything else on the
        -- page (user request, 02.08.2026). These rows used to sit inside "Health
        -- Bar" and "Cast Bar" -- which is where they belong by MECHANISM, but
        -- not by the question you arrive with. "What do my plates look like" is
        -- the first thing anyone changes, and it was four sections down.
        --
        -- MOVED, never copied: a setting that answers from two places on one
        -- page is a setting you can no longer trust.
        --
        -- The colour and the fine tuning ride on the row itself as inline icons
        -- rather than behind the right-hand gear. That is a deliberate exception
        -- to the one-expander rule: the gear opens a sub-column, and half a cell
        -- in this grid has no room for one.
        { type = "section", title = L["Style"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "dropdown", label = L["Border"], width = 300, values = borderStyleValues(),
                  get = function() return mod.db.borderStyle end,
                  set = function(_, v) mod.db.borderStyle = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Border colour"],
                        get = function() return mod.db.borderColor end,
                        set = function(r, g, b)
                            mod.db.borderColor = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                      { kind = "gear", tooltip = L["Border settings"],
                        popup = { title = L["Border settings"], width = 250, items = {
                            { type = "dropdown", label = L["Border texture"], width = 220,
                              values = borderTextureValues(),
                              get = function() return mod.db.borderTexture end,
                              set = function(_, v) mod.db.borderTexture = v; applyAndRefresh() end },
                            -- The SAME value the "Cast bar border" thickness
                            -- slider shows, asked as a yes/no. Deliberately in
                            -- both places (user request, 02.08.2026): here you
                            -- are looking at borders in general and only want to
                            -- know whether the cast bar wears one, there you are
                            -- sizing the cast bar itself.
                            --
                            -- Both write castBorderSize, so they cannot drift
                            -- apart: off is 0, on is "absent" -- which the
                            -- slider reads as the health bar's own thickness,
                            -- exactly what this switch meant before it had one.
                            { type = "checkbox", label = L["Border around the cast bar"],
                              tooltip = L["Off leaves the cast bar without its own outline; the health bar keeps one."],
                              get = function()
                                  local v = mod.db.castBorderSize
                                  if v == nil then return mod.db.borderOnCast ~= false end
                                  return v > 0
                              end,
                              set = function(_, v)
                                  mod.db.castBorderSize = v and nil or 0
                                  mod.db.borderOnCast = nil
                                  applyAndRefresh()
                              end },
                        } } },
                  } },
                { type = "slider", label = L["Border size"], min = 0, max = 12, step = 1, width = SLW,
                  get = function() return mod.db.borderSize end,
                  set = function(_, v) mod.db.borderSize = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Background"], min = 0, max = 100, step = 1, width = SLW,
                  tooltip = L["How solid the empty part of the bar is."],
                  get = function() return floor((mod.db.bgAlpha or 0.85) * 100 + 0.5) end,
                  set = function(_, v) mod.db.bgAlpha = v / 100; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Background colour"],
                        -- Dead while the background takes its shade from the bar
                        -- colour: the setting it edits is not the one being drawn.
                        disabled = function() return mod.db.bgTintByBar == true end,
                        get = function() return mod.db.bgColor end,
                        set = function(r, g, b)
                            mod.db.bgColor = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                      -- Sits with the swatch it greys out, which is where it
                      -- explains itself (came from "Health Bar", 02.08.2026).
                      { kind = "gear", tooltip = L["Background settings"],
                        popup = { title = L["Background settings"], width = 380, items = {
                            { type = "checkbox", label = L["Tint background with bar colour"],
                              tooltip = L["The empty part of the bar shows a darkened shade of the bar colour instead of plain dark grey."],
                              get = function() return mod.db.bgTintByBar end,
                              set = function(_, v) mod.db.bgTintByBar = v; applyAndRefresh(); refreshPage() end },
                        } } },
                  } },
                { type = "dropdown", label = L["Absorb style"], width = 300,
                  values = (function()
                      -- "Flat" first: it is what the shield looked like before
                      -- this existed, so an untouched profile finds itself at the top.
                      local vals = { { value = "flat", text = L["Flat colour"] } }
                      for _, v in ipairs(textureValues()) do vals[#vals + 1] = v end
                      return vals
                  end)(),
                  get = function() return mod.db.absorbStyle or "flat" end,
                  set = function(_, v) mod.db.absorbStyle = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Absorb colour"],
                        get = function() return mod.db.colAbsorb end,
                        set = function(r, g, b)
                            mod.db.colAbsorb = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                      { kind = "gear", tooltip = L["Absorb settings"],
                        popup = { title = L["Absorb settings"], width = 250, items = {
                            { type = "slider", label = L["Absorb opacity"], min = 10, max = 100, step = 5,
                              get = function() return floor((mod.db.absorbAlpha or 0.55) * 100 + 0.5) end,
                              set = function(_, v) mod.db.absorbAlpha = v / 100; applyAndRefresh() end },
                        } } },
                      -- The eye IS the on/off switch here, the way the reference
                      -- row reads: a style you cannot see is the same as no shield.
                      { kind = "eye", tooltip = L["Show absorb shield"],
                        get = function() return mod.db.showAbsorb ~= false end,
                        set = function(v) mod.db.showAbsorb = v; applyAndRefresh() end },
                  } },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "dropdown", label = L["Bar texture"], width = 300, values = textureValues(),
                  get = function() return mod.db.healthTexture end,
                  set = function(_, v) mod.db.healthTexture = v; applyAndRefresh() end },
                { type = "dropdown", label = L["Cast bar texture"], width = 300, values = textureValues(),
                  get = function() return mod.db.castTexture end,
                  set = function(_, v) mod.db.castTexture = v; applyAndRefresh() end },
            } },
            -- Came from "Health Bar" (user request, 02.08.2026). On its own row
            -- rather than paired: it is the only row here that is not about a
            -- colour or a texture, and pairing it would suggest it belongs to
            -- whatever ended up beside it.
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Pixel-true plate size"],
                  tooltip = L["Sizes the plates in screen pixels instead of interface units: height 27 is then 27 pixels on any monitor and UI scale."],
                  get = function() return mod.db.pixelPerfect end,
                  set = function(_, v) mod.db.pixelPerfect = v and true or false; applyAndRefresh() end },
                { type = "checkbox", label = L["Rounded bar corners"],
                  tooltip = L["Clips the fill and background to a rounded shape. The line border stays square, so a thin border may show slightly at the corners."],
                  get = function() return mod.db.roundedBars end,
                  set = function(_, v) mod.db.roundedBars = v; applyAndRefresh() end },
            } },
            -- Both say how EVERY plate is measured, so they belong with the
            -- pixel rule above rather than under the health bar (02.08.2026).
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Overall plate scale (%)"], min = 50, max = 200, step = 5, width = SLW,
                  tooltip = L["Scales every plate at once, on top of each individual size."],
                  get = function() return mod.db.globalScale or 100 end,
                  set = function(_, v) mod.db.globalScale = v; applyAndRefresh() end },
                { type = "slider", label = L["Vertical offset"], min = -100, max = 100, step = 1, width = SLW,
                  tooltip = L["Moves every plate up or down relative to its unit."],
                  get = function() return mod.db.plateOffsetY or 0 end,
                  set = function(_, v) mod.db.plateOffsetY = v; applyAndRefresh() end },
            } },
        } },

        -- Second, right under the look (user request, 02.08.2026). Replaces the
        -- four separate "row" sections: placement is asked slot by slot, not row
        -- by row, so two rows can no longer claim one spot.
        { type = "section", title = L["Main positions"], items = (function()
            local items = { { type = "desc",
                text = L["|cffaaaaaaOne thing per slot. Giving a slot something takes it away from the slot that had it.|r"] } }
            for _, it in ipairs(slotItems(applyAndRefresh)) do items[#items + 1] = it end
            return items
        end)() },

        -- Third, straight after the icon slots: same idea, one level down
        -- (user request, 02.08.2026).
        { type = "section", title = L["Main text positions"], items = (function()
            local items = { { type = "desc",
                text = L["|cffaaaaaaOne thing per slot. The level rides at the name's left edge and follows it.|r"] } }
            for _, it in ipairs(textSlotItems()) do items[#items + 1] = it end
            return items
        end)() },

        -- Fourth and fifth, in the reference's own order (user request,
        -- 02.08.2026): the two bars' geometry first, then what colours them.
        -- Every row here MOVED out of "Health Bar" or "Cast Bar"; none is
        -- repeated in its old section.
        { type = "section", title = L["Health and cast bar"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Health bar width"], min = 60, max = 240, step = 2, width = SLW,
                  get = function() return mod.db.healthWidth end,
                  set = function(_, v) mod.db.healthWidth = v; applyAndRefresh() end },
                { type = "slider", label = L["Health bar height"], min = 4, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.healthHeight end,
                  set = function(_, v) mod.db.healthHeight = v; applyAndRefresh() end },
            } },
            -- Back after the "Cast Bar" section was removed (user report,
            -- 02.08.2026: the live preview had no cast bar and nothing on the
            -- page could bring it back). Every other row here shapes the cast
            -- bar; this is the one that decides whether there is one.
            { type = "checkbox", label = L["Show cast bar"],
              get = function() return mod.db.showCastbar end,
              set = function(_, v) mod.db.showCastbar = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Cast bar height"], min = 4, max = 30, step = 1, width = SLW,
                  get = function() return mod.db.castHeight end,
                  set = function(_, v) mod.db.castHeight = v; applyAndRefresh() end },
                { type = "checkbox", label = L["Cast icon"],
                  get = function() return mod.db.showCastIcon end,
                  set = function(_, v) mod.db.showCastIcon = v; applyAndRefresh() end,
                  inline = {
                      { kind = "popup", tooltip = L["Cast icon settings"],
                        popup = { title = L["Cast icon settings"], width = 380, items = {
                            { type = "slider", label = L["Icon scale"], min = 50, max = 200, step = 5, width = 130,
                              get = function() return mod.db.castIconScale or 100 end,
                              set = function(_, v) mod.db.castIconScale = v; applyAndRefresh() end },
                            { type = "slider", label = L["Icon crop (%)"], min = 0, max = 25, step = 1, width = 130,
                              tooltip = L["How much is cut off each edge of the icon. 0 shows the whole icon including the border baked into its artwork."],
                              get = function() return mod.db.castIconCrop or 8 end,
                              set = function(_, v) mod.db.castIconCrop = v; applyAndRefresh() end },
                            { type = "slider", label = L["Icon offset X"], min = -40, max = 40, step = 1, width = 130,
                              get = function() return mod.db.castIconX or 0 end,
                              set = function(_, v) mod.db.castIconX = v; applyAndRefresh() end },
                            { type = "slider", label = L["Icon offset Y"], min = -40, max = 40, step = 1, width = 130,
                              get = function() return mod.db.castIconY or 0 end,
                              set = function(_, v) mod.db.castIconY = v; applyAndRefresh() end },
                            { type = "checkbox", label = L["Icon on the right"],
                              get = function() return mod.db.castIconRight end,
                              set = function(_, v) mod.db.castIconRight = v; applyAndRefresh() end },
                        } } },
                  } },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Cast background"], min = 0, max = 100, step = 5, width = SLW,
                  tooltip = L["0 = uses the global background opacity."],
                  get = function() return floor((mod.db.castBgAlpha or 0) * 100 + 0.5) end,
                  set = function(_, v) mod.db.castBgAlpha = v / 100; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Cast background colour"],
                        get = function() return mod.db.castBgColor end,
                        set = function(r, g, b)
                            mod.db.castBgColor = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                  } },
                -- Its own thickness and colour; absent means "the same as the
                -- health bar's", which is what it always was. 0 = no border.
                { type = "slider", label = L["Cast bar border"], min = 0, max = 12, step = 1, width = SLW,
                  tooltip = L["Thickness of the cast bar's own border. 0 removes it; the health bar keeps its own."],
                  get = function()
                      local v = mod.db.castBorderSize
                      if v == nil and mod.db.borderOnCast == false then return 0 end
                      if v == nil then return mod.db.borderSize or 1 end
                      return v
                  end,
                  set = function(_, v)
                      mod.db.castBorderSize = v
                      -- The switch this replaced has had its say in the getter
                      -- above; leaving it behind would make it look like a
                      -- setting with no control.
                      mod.db.borderOnCast = nil
                      applyAndRefresh()
                  end,
                  inline = {
                      { kind = "color", tooltip = L["Cast bar border colour"],
                        get = function() return mod.db.castBorderColor or mod.db.borderColor end,
                        set = function(r, g, b)
                            mod.db.castBorderColor = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                  } },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Cast timer"],
                  get = function() return mod.db.castTimer end,
                  set = function(_, v) mod.db.castTimer = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Timer colour"],
                        get = function() return mod.db.castTimerColor end,
                        set = function(r, g, b)
                            mod.db.castTimerColor = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                      { kind = "popup", tooltip = L["Cast timer settings"],
                        popup = { title = L["Cast timer settings"], width = 380, items = {
                            { type = "segmented", label = L["Timer side"], width = 200,
                              values = {
                                  { value = "right", text = L["Right"] },
                                  { value = "left",  text = L["Left"] },
                              },
                              get = function() return mod.db.castTimerSide or "right" end,
                              set = function(_, v) mod.db.castTimerSide = v; applyAndRefresh() end },
                            { type = "slider", label = L["Cast timer size"], min = 0, max = 20, step = 1, width = 130,
                              tooltip = L["0 = uses the general text size."],
                              get = function() return mod.db.castTimerSize or 0 end,
                              set = function(_, v) mod.db.castTimerSize = v; applyAndRefresh() end },
                        } } },
                  } },
                { type = "slider", label = L["Cast bar Y offset"], min = -60, max = 60, step = 1, width = SLW,
                  get = function() return mod.db.castOffsetY or 0 end,
                  set = function(_, v) mod.db.castOffsetY = v; applyAndRefresh() end },
            } },
        } },

        { type = "section", title = L["Cast colours and effects"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                -- The reference draws four swatches side by side in one row. We
                -- have no such widget, and inventing one for a single row is a
                -- worse trade than our own idiom: the main colour on the row,
                -- the other three behind its gear. Same four colours, same
                -- place, one click deeper for the rarer ones.
                { type = "checkbox", label = L["Cast colour"],
                  tooltip = L["The bar's colour while a spell is being cast."],
                  get = function() return true end,
                  set = function() end,
                  inline = {
                      { kind = "color", tooltip = L["Cast colour"],
                        get = function() return mod.db.colCast end,
                        set = function(r, g, b)
                            mod.db.colCast = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                      { kind = "gear", tooltip = L["More cast colours"],
                        popup = { title = L["More cast colours"], width = 380, items = {
                            { type = "color", label = L["Non-interruptible"], width = 200,
                              get = function() return mod.db.colCastNoInterrupt end,
                              set = function(r, g, b) mod.db.colCastNoInterrupt = { r = r, g = g, b = b }; applyAndRefresh() end },
                            { type = "color", label = L["Interrupt ready"], width = 200,
                              get = function() return mod.db.colCastKickReady end,
                              set = function(r, g, b) mod.db.colCastKickReady = { r = r, g = g, b = b }; applyAndRefresh() end },
                            { type = "color", label = L["Interrupt flash"], width = 200,
                              get = function() return mod.db.colInterruptFlash end,
                              set = function(r, g, b) mod.db.colInterruptFlash = { r = r, g = g, b = b }; applyAndRefresh() end },
                        } } },
                  } },
                { type = "checkbox", label = L["Interrupt-ready hint"],
                  tooltip = L["Marks the spot on the enemy cast bar where YOUR interrupt comes off cooldown — everything after the tick is kickable."],
                  get = function() return mod.db.castKickTick end,
                  set = function(_, v) mod.db.castKickTick = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Tick colour"],
                        get = function() return mod.db.colKickTick end,
                        set = function(r, g, b)
                            mod.db.colKickTick = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                  } },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                -- Verified against the reference before building: it flashes the
                -- enemy's cast bar and writes "Interrupted" for a moment, with
                -- the swatch greying out while the effect is off. We had all of
                -- that already -- it only moved here and grew the inline swatch.
                { type = "checkbox", label = L["Interrupt flash"],
                  tooltip = L["The enemy's cast bar flashes and reads 'Interrupted' for a moment when their cast is stopped."],
                  get = function() return mod.db.castInterruptFlash end,
                  set = function(_, v) mod.db.castInterruptFlash = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Interrupt flash"],
                        -- dead while the flash is off: nothing would paint it
                        disabled = function() return not mod.db.castInterruptFlash end,
                        get = function() return mod.db.colInterruptFlash end,
                        set = function(r, g, b)
                            mod.db.colInterruptFlash = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                      { kind = "gear", tooltip = L["Interrupt flash settings"],
                        popup = { title = L["Interrupt flash settings"], width = 380, items = {
                            { type = "checkbox", label = L["Show who interrupted"],
                              tooltip = L["The interrupt flash shows the name of whoever landed the interrupt."],
                              get = function() return mod.db.castInterrupter end,
                              set = function(_, v) mod.db.castInterrupter = v; applyAndRefresh() end },
                        } } },
                  } },
                { type = "checkbox", label = L["Show cast bars in front of nameplates"],
                  tooltip = L["Casts draw above every plate, so a cast you care about is never hidden behind another unit's bar."],
                  get = function() return mod.db.castInFront == true end,
                  set = function(_, v) mod.db.castInFront = v; applyAndRefresh() end },
            } },
        } },

        -- Sixth: what marks the plate you are pointing at, aimed at, or hovering
        -- over. Every row MOVED out of "Target & Threat", which keeps the threat
        -- colours it is actually named for.
        { type = "section", title = L["Target, focus and hover effects"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Target effect"],
                  tooltip = L["A coloured edge around the plate you have targeted."],
                  get = function() return mod.db.targetHighlight end,
                  set = function(_, v) mod.db.targetHighlight = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Target highlight colour"],
                        disabled = function() return not mod.db.targetHighlight end,
                        get = function() return mod.db.colTarget end,
                        set = function(r, g, b)
                            mod.db.colTarget = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                      -- The gear that held target scale and non-target opacity
                      -- is gone: both moved to "Target and focus effects" on the
                      -- general tab, where the reference has them. This row is
                      -- the target MARKING; those two are how the plate behaves.
                  } },
                { type = "checkbox", label = L["Target arrows"],
                  tooltip = L["Two arrows pointing in at the target's bar, one on each side."],
                  get = function() return mod.db.targetArrows end,
                  set = function(_, v) mod.db.targetArrows = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Arrow colour"],
                        disabled = function() return not mod.db.targetArrows end,
                        get = function() return mod.db.colTargetArrow end,
                        set = function(r, g, b)
                            mod.db.colTargetArrow = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                      { kind = "popup", tooltip = L["Arrow settings"],
                        popup = { title = L["Arrow settings"], width = 380, items = {
                            { type = "slider", label = L["Arrow size"], min = 6, max = 32, step = 1, width = 130,
                              get = function() return mod.db.targetArrowSize or 14 end,
                              set = function(_, v) mod.db.targetArrowSize = v; applyAndRefresh() end },
                            { type = "slider", label = L["Arrow distance"], min = 0, max = 30, step = 1, width = 130,
                              get = function() return mod.db.targetArrowGap or 4 end,
                              set = function(_, v) mod.db.targetArrowGap = v; applyAndRefresh() end },
                        } } },
                  } },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Target bar colour on"],
                  tooltip = L["Your current target's health bar uses this colour instead of reaction / class / threat colours."],
                  get = function() return mod.db.targetBarColor end,
                  set = function(_, v) mod.db.targetBarColor = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Target bar colour"],
                        disabled = function() return not mod.db.targetBarColor end,
                        get = function() return mod.db.colTargetBar end,
                        set = function(r, g, b)
                            mod.db.colTargetBar = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                  } },
                { type = "checkbox", label = L["Focus bar colour on"],
                  tooltip = L["A coloured edge around the plate you have set as your focus."],
                  get = function() return mod.db.focusHighlight end,
                  set = function(_, v) mod.db.focusHighlight = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Focus highlight colour"],
                        disabled = function() return not mod.db.focusHighlight end,
                        get = function() return mod.db.colFocus end,
                        set = function(r, g, b)
                            mod.db.colFocus = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                  } },
            } },
            { type = "checkbox", label = L["Mouseover effect"],
              tooltip = L["Lightens the health bar of the plate under your mouse cursor."],
              get = function() return mod.db.hoverHighlight end,
              set = function(_, v) mod.db.hoverHighlight = v; updateHoverTicker() end,
              inline = {
                  { kind = "gear", tooltip = L["Mouseover effect settings"],
                    popup = { title = L["Mouseover effect settings"], width = 380, items = {
                        { type = "slider", label = L["Highlight strength"], min = 2, max = 60, step = 2, width = 130,
                          get = function() return mod.db.hoverAlpha or 12 end,
                          set = function(_, v) mod.db.hoverAlpha = v; applyAndRefresh() end },
                    } } },
              } },
        } },

        -- Seventh: where each text on an icon or on the cast bar sits. Every row
        -- is a POSITION, and "None" is what switches that text off -- the four
        -- booleans this replaces were migrated into these positions.
        { type = "section", title = L["General text"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                durationRow("debuff", L["Debuff duration"]),
                durationRow("buff",   L["Buff duration"]),
            } },
            { type = "group", layout = "row", gap = 8, items = {
                durationRow("cc", L["Crowd control duration"]),
                { type = "dropdown", label = L["Aura stacks"], width = 260,
                  values = auraTextPosValues(),
                  get = function() return mod.db.auraStackPos or "bottomright" end,
                  set = function(_, v) mod.db.auraStackPos = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Stack text colour"],
                        get = function() return mod.db.auraStackColor end,
                        set = function(r, g, b)
                            mod.db.auraStackColor = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                      { kind = "popup", tooltip = L["Text settings"],
                        popup = { title = L["Aura stacks"], width = 380, items = {
                            { type = "slider", label = L["Stack text size"], min = 6, max = 20, step = 1, width = 130,
                              get = function() return mod.db.auraStackSize end,
                              set = function(_, v) mod.db.auraStackSize = v; applyAndRefresh() end },
                        } } },
                  } },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "dropdown", label = L["Spell name"], width = 260,
                  values = castTextPosValues(),
                  get = function() return mod.db.castNameSide or "center" end,
                  -- Mutually exclusive with the cast target, the way the
                  -- reference does it: two texts cannot own one side of the bar.
                  set = function(_, v)
                      mod.db.castNameSide = v
                      if v ~= "none" and mod.db.castTargetSide == v then
                          mod.db.castTargetSide = "none"
                      end
                      applyAndRefresh(); refreshPage()
                  end,
                  inline = {
                      { kind = "color", tooltip = L["Cast text colour"],
                        get = function() return mod.db.castTextColor end,
                        set = function(r, g, b)
                            mod.db.castTextColor = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                      { kind = "popup", tooltip = L["Text settings"],
                        popup = { title = L["Spell name"], width = 380, items = {
                            { type = "slider", label = L["Cast text size"], min = 0, max = 20, step = 1, width = 130,
                              tooltip = L["0 = uses the general text size."],
                              get = function() return mod.db.castTextSize or 0 end,
                              set = function(_, v) mod.db.castTextSize = v; applyAndRefresh() end },
                        } } },
                  } },
                { type = "dropdown", label = L["Spell target"], width = 260,
                  tooltip = L["The caster's current target, beside the cast bar. Your own name is coloured."],
                  values = castTextPosValues(),
                  get = function() return mod.db.castTargetSide or "none" end,
                  set = function(_, v)
                      mod.db.castTargetSide = v
                      if v ~= "none" and mod.db.castNameSide == v then
                          mod.db.castNameSide = "none"
                      end
                      applyAndRefresh(); refreshPage()
                  end,
                  inline = {
                      { kind = "popup", tooltip = L["Text settings"],
                        popup = { title = L["Spell target"], width = 380, items = {
                            { type = "slider", label = L["Cast target size"], min = 0, max = 20, step = 1, width = 130,
                              tooltip = L["0 = uses the general text size."],
                              get = function() return mod.db.castTargetSize or 0 end,
                              set = function(_, v) mod.db.castTargetSize = v; applyAndRefresh() end },
                            { type = "slider", label = L["Offset X"], min = -100, max = 100, step = 1, width = 130,
                              get = function() return mod.db.castTargetX or 0 end,
                              set = function(_, v) mod.db.castTargetX = v; applyAndRefresh() end },
                            { type = "slider", label = L["Offset Y"], min = -60, max = 60, step = 1, width = 130,
                              get = function() return mod.db.castTargetY or 0 end,
                              set = function(_, v) mod.db.castTargetY = v; applyAndRefresh() end },
                        } } },
                  } },
            } },
        } },

        -- First on the general tab (user request, 02.08.2026). Placed BEFORE the
        -- preset because the tab filter keeps the order of this table -- a
        -- section is "first on its tab" only by sitting first here.
        --
        -- Same settings as the old "Friendly Plates", recut into two dense rows.
        -- The two name colours ride on the dropdowns they belong to instead of
        -- standing as a separate pair further down.
        { type = "section", title = L["Other nameplates"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Show friendly nameplates"],
                  tooltip = L["Sets Blizzard's friendly-nameplate option (cannot change in combat)."],
                  get = function() return mod.db.friendlyShow end,
                  set = function(_, v) mod.db.friendlyShow = v; applyFriendlyCVar(); applyAndRefresh() end },
                { type = "checkbox", label = L["Show NPC title"],
                  tooltip = L["Shows a friendly NPC's subtitle (e.g. <Innkeeper>) under its name in name-only mode."],
                  get = function() return mod.db.showNPCTitle end,
                  set = function(_, v) mod.db.showNPCTitle = v; applyAndRefresh() end,
                  inline = {
                      { kind = "gear", tooltip = L["NPC title size"],
                        popup = { title = L["Show NPC title"], width = 380, items = {
                            { type = "slider", label = L["NPC title size"], min = 0, max = 20, step = 1, width = 130,
                              tooltip = L["0 = slightly smaller than the name."],
                              get = function() return mod.db.titleSize or 0 end,
                              set = function(_, v) mod.db.titleSize = v; applyAndRefresh() end },
                        } } },
                  } },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "dropdown", label = L["Friendly players"], width = 260, values = friendlyModeValues(),
                  get = function() return mod.db.friendlyPlayers end,
                  set = function(_, v) mod.db.friendlyPlayers = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Friendly player name"],
                        get = function() return mod.db.friendlyNameColor end,
                        set = function(r, g, b)
                            mod.db.friendlyNameColor = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                  } },
                { type = "dropdown", label = L["Friendly NPCs"], width = 260, values = friendlyModeValues(),
                  get = function() return mod.db.friendlyNPCs end,
                  set = function(_, v) mod.db.friendlyNPCs = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Friendly NPC name"],
                        get = function() return mod.db.friendlyNPCColor end,
                        set = function(r, g, b)
                            mod.db.friendlyNPCColor = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                  } },
            } },
            -- Came from "Behaviour": it says which plates exist at all, which is
            -- this section's subject and not a CVar-tuning question.
            { type = "checkbox", label = L["Show plates for enemy pets"],
              get = function() return (GetCVar and GetCVar("nameplateShowEnemyPets")) == "1" end,
              set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateShowEnemyPets", v and "1" or "0") end end },
        } },

        -- Second on the general tab, straight after the plates themselves
        -- (user request, 02.08.2026). All four rows came out of "Behaviour";
        -- they are the game's own CVars except the hitbox, which is ours.
        { type = "section", title = L["Nameplate spacing"], items = {
            { type = "desc",
              text = L["|cffaaaaaaThe game's own settings, changed live and not part of the profile — except the hitbox. Not changeable in combat.|r"] },
            -- STACKING IS `nameplateStackingTypes` ON THIS CLIENT, not
            -- `nameplateMotion`. Established 02.08.2026 after the row showed the
            -- literal text "nil":
            --
            --   * `nameplateMotion` has ZERO occurrences in the client binary,
            --     while nameplateOverlapV and nameplateMaxDistance each have one.
            --     Config.wtf still carries a line for it -- that file accumulates
            --     across client versions, so it proves a CVar once existed, not
            --     that it exists now. The live nil was right, the .wtf was not.
            --   * the binary's own help text for the replacement reads
            --     "Determines which types of nameplates stack to prevent
            --     overlapping each other."
            --
            -- It is a string of type letters, not a 0/1. Measured in game:
            -- GetCVarDefault is "" (nothing stacks) and a working stacked setup
            -- reads "A". So those two are the pair this control offers.
            --
            -- Any OTHER letter combination -- someone tuning it by hand -- reads
            -- back as "Stacking" rather than as raw text, and is overwritten
            -- with "A" if this row is touched. That is the honest trade for a
            -- two-choice control; the alternative was showing "FE" in a menu.
            (function()
                local spacing = { type = "slider", label = L["Stacked spacing"], min = 4, max = 20, step = 1, width = SLW,
                    tooltip = L["Vertical distance between stacked plates (a tenth of the game value)."],
                    get = function() return floor((tonumber(GetCVar and GetCVar("nameplateOverlapV")) or 1.1) * 10 + 0.5) end,
                    set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateOverlapV", v / 10) end end }
                if not (GetCVar and GetCVar("nameplateStackingTypes")) then return spacing end
                return { type = "group", layout = "row", gap = 8, items = {
                    { type = "dropdown", label = L["Stackable nameplates"], width = 260,
                      values = {
                          { value = "",  text = L["Overlapping"] },
                          { value = "A", text = L["Stacking"] },
                      },
                      get = function()
                          local v = GetCVar and GetCVar("nameplateStackingTypes")
                          -- normalised, so a hand-set combination never shows raw
                          return (v and v ~= "") and "A" or ""
                      end,
                      set = function(_, v)
                          if not InCombatLockdown() then
                              pcall(SetCVar, "nameplateStackingTypes", v or "")
                          end
                      end },
                    spacing,
                } }
            end)(),
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Hitbox width (%)"], min = 50, max = 200, step = 5, width = SLW,
                  tooltip = L["Clickable plate area. 100 leaves the game's own size untouched. Stored in the profile."],
                  get = function() return mod.db.hitboxPctW or 100 end,
                  set = function(_, v) mod.db.hitboxPctW = v; applyHitbox() end },
                { type = "slider", label = L["Hitbox height (%)"], min = 50, max = 300, step = 5, width = SLW,
                  get = function() return mod.db.hitboxPctH or 100 end,
                  set = function(_, v) mod.db.hitboxPctH = v; applyHitbox() end },
            } },
            -- The last two rows of "Behaviour", paired under the hitbox (user
            -- request, 02.08.2026). They are the same kind of thing as the rows
            -- above -- the game's own plate CVars -- so the section that already
            -- says so in its description is where they belong. "Behaviour" had
            -- nothing else left and is gone.
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Line-of-sight opacity"], min = 0, max = 100, step = 5, width = SLW,
                  tooltip = L["Opacity of plates whose unit is out of your line of sight."],
                  get = function() return floor((tonumber(GetCVar and GetCVar("nameplateOccludedAlphaMult")) or 0.4) * 100 + 0.5) end,
                  set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateOccludedAlphaMult", v / 100) end end },
                { type = "slider", label = L["Plate view distance"], min = 20, max = 60, step = 1, width = SLW,
                  get = function() return floor(tonumber(GetCVar and GetCVar("nameplateMaxDistance")) or 41) end,
                  set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateMaxDistance", v) end end },
            } },
        } },

        -- Third on the general tab (user request, 02.08.2026). Every row here
        -- was ORPHANED when the old "Auras" section went: the runtime kept
        -- reading these four, but nothing on the page could change them. This
        -- gives them a control again rather than inventing anything.
        { type = "section", title = L["Extra aura options"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Show all debuffs (not just yours)"],
                  tooltip = L["Off: only debuffs you applied. On: every debuff on the unit."],
                  get = function() return mod.db.debuffsAll end,
                  set = function(_, v) mod.db.debuffsAll = v; applyAndRefresh() end },
                { type = "slider", label = L["Max debuffs"], min = 1, max = 8, step = 1, width = SLW,
                  get = function() return mod.db.maxDebuffs end,
                  set = function(_, v) mod.db.maxDebuffs = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Glow stealable / dispellable buffs"],
                  tooltip = L["Glows enemy buffs you can remove (Spellsteal / Purge / Dispel Magic). Only for classes that can."],
                  get = function() return mod.db.showDispelGlow end,
                  set = function(_, v) mod.db.showDispelGlow = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Dispel glow colour"],
                        -- Dead while the glow takes the aura's own school colour
                        -- or while the glow is off entirely.
                        disabled = function()
                            return not mod.db.showDispelGlow or mod.db.dispelGlowBySchool == true
                        end,
                        get = function() return mod.db.colDispel end,
                        set = function(r, g, b)
                            mod.db.colDispel = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                  } },
                { type = "checkbox", label = L["Glow in the aura's own school colour"],
                  tooltip = L["Magic blue, curse purple, disease orange, poison green — instead of one colour for everything."],
                  get = function() return mod.db.dispelGlowBySchool end,
                  set = function(_, v) mod.db.dispelGlowBySchool = v; applyAndRefresh(); refreshPage() end },
            } },
        } },

        -- Fourth on the general tab (user request, 02.08.2026). Not the same
        -- thing as "Target, focus and hover effects" on the display tab: that
        -- one is what MARKS the target, this one is how the plate behaves once
        -- it is the target. The reference splits them the same way.
        --
        -- The execute line came back from the dead here -- it was orphaned when
        -- "Health Bar" went. Target scale and non-target opacity moved OUT of
        -- the display gear so they are not in two places.
        { type = "section", title = L["Target and focus effects"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Execute line"],
                  tooltip = L["A thin marker line on the bar at the chosen health percentage (e.g. 20 for Execute)."],
                  get = function() return mod.db.execLine end,
                  set = function(_, v) mod.db.execLine = v; applyAndRefresh() end,
                  inline = {
                      { kind = "color", tooltip = L["Execute line colour"],
                        disabled = function() return not mod.db.execLine end,
                        get = function() return mod.db.colExec end,
                        set = function(r, g, b)
                            mod.db.colExec = { r = r, g = g, b = b }; applyAndRefresh()
                        end },
                      { kind = "gear", tooltip = L["Execute line"],
                        popup = { title = L["Execute line"], width = 380, items = {
                            { type = "checkbox", label = L["Execute line only on your target"],
                              get = function() return mod.db.execTargetOnly end,
                              set = function(_, v) mod.db.execTargetOnly = v; applyAndRefresh() end },
                        } } },
                  } },
                { type = "slider", label = L["Execute line percent"], min = 5, max = 90, step = 1, width = SLW,
                  get = function() return mod.db.execPct or 20 end,
                  set = function(_, v) mod.db.execPct = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Target plate scale"], min = 100, max = 150, step = 5, width = SLW,
                  tooltip = L["Your target's plate is drawn this much larger (100 = off)."],
                  get = function() return mod.db.targetScale or 100 end,
                  set = function(_, v) mod.db.targetScale = v; applyAndRefresh() end },
                { type = "slider", label = L["Non-target opacity"], min = 20, max = 100, step = 5, width = SLW,
                  get = function() return floor((mod.db.nonTargetAlpha or 1) * 100 + 0.5) end,
                  set = function(_, v) mod.db.nonTargetAlpha = v / 100; applyAndRefresh() end },
            } },
            { type = "checkbox", label = L["Mark on the focus plate"],
              tooltip = L["A short text on your focus target's plate. A ring says this one is special; the mark says which."],
              get = function() return mod.db.focusMark end,
              set = function(_, v) mod.db.focusMark = v; applyAndRefresh() end,
              inline = {
                  { kind = "color", tooltip = L["Mark colour"],
                    disabled = function() return not mod.db.focusMark end,
                    get = function() return mod.db.colFocusMark end,
                    set = function(r, g, b)
                        mod.db.colFocusMark = { r = r, g = g, b = b }; applyAndRefresh()
                    end },
                  { kind = "popup", tooltip = L["Mark on the focus plate"],
                    popup = { title = L["Mark on the focus plate"], width = 380, items = {
                        { type = "editbox", label = L["Mark text"], width = 160,
                          get = function() return mod.db.focusMarkText or "F" end,
                          set = function(_, v) mod.db.focusMarkText = tostring(v or "F"); applyAndRefresh() end },
                        { type = "dropdown", label = L["Mark position"], width = 220,
                          subKey = "focusMarkAnchor",
                          values = ns.AnchorPointValues(),
                          get = function() return mod.db.focusMarkAnchor or "CENTER" end,
                          set = function(_, v) mod.db.focusMarkAnchor = v; applyAndRefresh() end },
                        { type = "slider", label = L["Offset X"], min = -100, max = 100, step = 1, width = 130,
                          get = function() return mod.db.focusMarkX or 0 end,
                          set = function(_, v) mod.db.focusMarkX = v; applyAndRefresh() end },
                        { type = "slider", label = L["Offset Y"], min = -60, max = 60, step = 1, width = 130,
                          get = function() return mod.db.focusMarkY or 0 end,
                          set = function(_, v) mod.db.focusMarkY = v; applyAndRefresh() end },
                        { type = "slider", label = L["Mark size"], min = 0, max = 32, step = 1, width = 130,
                          tooltip = L["0 = uses the name size."],
                          get = function() return mod.db.focusMarkSize or 0 end,
                          set = function(_, v) mod.db.focusMarkSize = v; applyAndRefresh() end },
                    } } },
              } },
        } },

        -- Last on the general tab (user request, 02.08.2026). Both rows were
        -- orphaned when the "Cast Bar" section went -- the runtime kept reading
        -- them, nothing could change them.
        { type = "section", title = L["Extras"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                -- ONE slider where we have a switch plus a percentage, the way
                -- the reference asks it: 100 means "same size as always", which
                -- IS the switch being off. Anything above turns it on and is the
                -- scale in one move.
                { type = "slider", label = L["Plate scale while casting"], min = 100, max = 150, step = 5,
                  width = SLW,
                  tooltip = L["A casting unit's plate grows to this size, so the one that matters stands out. 100 = off."],
                  get = function()
                      if not mod.db.castEmphasis then return 100 end
                      return mod.db.castEmphScale or 110
                  end,
                  set = function(_, v)
                      if v <= 100 then
                          mod.db.castEmphasis = false
                      else
                          mod.db.castEmphasis = true
                          mod.db.castEmphScale = v
                      end
                      applyAndRefresh(); refreshPage()
                  end,
                  inline = {
                      { kind = "gear", tooltip = L["Plate scale while casting"],
                        popup = { title = L["Plate scale while casting"], width = 380, items = {
                            { type = "slider", label = L["Opacity while casting"], min = 20, max = 100, step = 5,
                              width = 130,
                              tooltip = L["A casting unit's plate is at least this opaque, even when something else is targeted."],
                              get = function() return mod.db.castEmphAlpha or 100 end,
                              set = function(_, v) mod.db.castEmphAlpha = v; applyAndRefresh() end },
                        } } },
                  } },
                { type = "checkbox", label = L["Hide name while casting"],
                  tooltip = L["The unit's name gives way to the spell name for as long as the cast runs."],
                  get = function() return mod.db.hideNameWhileCasting end,
                  set = function(_, v) mod.db.hideNameWhileCasting = v; applyAndRefresh() end },
            } },
        } },




        -- First on the colour tab, in the reference's shape (user request,
        -- 02.08.2026): the reaction colours as one row with the rest behind its
        -- gear, not seven rows of equal weight. Same settings throughout --
        -- nothing was added and nothing dropped, it is the same section recut.
        { type = "section", title = L["Enemy colours"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Enemy types"],
                  tooltip = L["The health bar colour a unit takes from its reaction to you."],
                  -- No switch of its own: the row exists to carry its colours.
                  -- A checkbox that answers "yes" forever is the honest shape we
                  -- have for that -- our kit has no label-only row with icons.
                  get = function() return true end,
                  set = function() end,
                  inline = {
                      { kind = "color", tooltip = L["Hostile"],
                        get = function() return mod.db.colHostile end,
                        set = function(r, g, b) mod.db.colHostile = { r = r, g = g, b = b }; applyAndRefresh() end },
                      { kind = "gear", tooltip = L["Enemy types"],
                        popup = { title = L["Enemy types"], width = 380, items = {
                            { type = "color", label = L["Friendly"], width = 200,
                              get = function() return mod.db.colFriendly end,
                              set = function(r, g, b) mod.db.colFriendly = { r = r, g = g, b = b }; applyAndRefresh() end },
                            { type = "color", label = L["Tapped"], width = 200,
                              get = function() return mod.db.colTapped end,
                              set = function(r, g, b) mod.db.colTapped = { r = r, g = g, b = b }; applyAndRefresh() end },
                            { type = "checkbox", label = L["Class colour for enemy players"],
                              get = function() return mod.db.classColorEnemy end,
                              set = function(_, v) mod.db.classColorEnemy = v; applyAndRefresh() end },
                            { type = "checkbox", label = L["Class colour for friendly players"],
                              get = function() return mod.db.classColorFriendly end,
                              set = function(_, v) mod.db.classColorFriendly = v; applyAndRefresh() end },
                        } } },
                  } },
                { type = "checkbox", label = L["Darken enemies out of combat"],
                  tooltip = L["Dims enemies that are not fighting anyone, so the ones that are stand out. Never your own target."],
                  get = function() return mod.db.darkenOOC end,
                  set = function(_, v) mod.db.darkenOOC = v; applyAndRefresh() end,
                  inline = {
                      { kind = "gear", tooltip = L["Darken to (%)"],
                        popup = { title = L["Darken enemies out of combat"], width = 380, items = {
                            { type = "slider", label = L["Darken to (%)"], min = 20, max = 90, step = 5, width = 130,
                              get = function() return mod.db.darkenOOCPct or 45 end,
                              set = function(_, v) mod.db.darkenOOCPct = v; applyAndRefresh() end },
                        } } },
                  } },
            } },
            { type = "checkbox", label = L["Neutral enemies"],
              tooltip = L["Units that are not hostile until you make them so."],
              get = function() return true end,
              set = function() end,
              inline = {
                  { kind = "color", tooltip = L["Neutral"],
                    get = function() return mod.db.colNeutral end,
                    set = function(r, g, b) mod.db.colNeutral = { r = r, g = g, b = b }; applyAndRefresh() end },
              } },
        } },


        { type = "section", title = L["Target & Threat"], items = {
            -- Target effect, arrows, target bar colour, focus highlight and the mouseover
            -- The runtime for this existed all along (execLine/execPct/
            -- colExec/execTargetOnly, painted per plate) -- it just never had
            -- rows on the page. These are the first.
            -- The execute line is "Hinrichten-Linie" in the health bar section -- it was on the page twice under two names.
            -- effect all moved to "Target, focus and hover effects" (02.08.2026).
            -- The focus mark moved to "Target and focus effects" (general tab).
            -- Non-target opacity moved behind the target effect's gear: it says
            -- what every plate that is NOT the target looks like, which is the
            -- target effect's own subject.
            { type = "checkbox", label = L["Colour by threat"],
              tooltip = L["Colour the health bar by your threat on the unit — coloured for your role. Useful in dungeons."],
              get = function() return mod.db.threatEnabled end,
              set = function(_, v) mod.db.threatEnabled = v; applyAndRefresh() end,
              subOptions = {
                  { type = "segmented", label = L["Your role"], width = 300, values = {
                        { value = "dps",  text = L["DPS / Healer"] },
                        { value = "tank", text = L["Tank"] },
                    },
                    get = function() return mod.db.threatRole end,
                    set = function(_, v) mod.db.threatRole = v; applyAndRefresh() end },
                  { type = "color", label = L["Secure (tank has aggro)"], width = 220,
                    get = function() return mod.db.colThreatGood end,
                    set = function(r, g, b) mod.db.colThreatGood = { r = r, g = g, b = b }; applyAndRefresh() end },
                  { type = "color", label = L["Warning (gaining / losing)"], width = 220,
                    get = function() return mod.db.colThreatWarn end,
                    set = function(r, g, b) mod.db.colThreatWarn = { r = r, g = g, b = b }; applyAndRefresh() end },
                  { type = "color", label = L["Danger (pulled / lost)"], width = 220,
                    get = function() return mod.db.colThreatBad end,
                    set = function(r, g, b) mod.db.colThreatBad = { r = r, g = g, b = b }; applyAndRefresh() end },
              } },
        } },


        -- Three sections that were one switch each -- a heading, a lone row, and
        -- an empty right column, three times over (user report, 02.08.2026).
        -- One heading now, paired two per row.
        --
        -- Their gears had to become INLINE gears on the way: a row inside
        -- layout="row" goes through PlaceGroup, which never draws the
        -- right-hand gear. That is the same reason the style rows carry their
        -- settings inline, and it is why these three could not simply be pasted
        -- next to each other.
        { type = "section", title = L["Extra indicators"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Show crowd control (separate row)"],
                  tooltip = L["A separate, prominent row for crowd-control effects (Polymorph, Fear, Sap, …) on the unit, from anyone."],
                  get = function() return mod.db.showCC end,
                  set = function(_, v) mod.db.showCC = v; refreshPage(); applyAndRefresh() end,
                  inline = {
                      { kind = "gear", tooltip = L["Crowd Control"],
                        popup = { title = L["Crowd Control"], width = 380, items = {
                            { type = "slider", label = L["CC icon size"], min = 12, max = 48, step = 1, width = 130,
                              get = function() return mod.db.ccSize end,
                              set = function(_, v) mod.db.ccSize = v; applyAndRefresh() end },
                            { type = "slider", label = L["Max CC"], min = 1, max = 5, step = 1, width = 130,
                              get = function() return mod.db.maxCC end,
                              set = function(_, v) mod.db.maxCC = v; applyAndRefresh() end },
                            { type = "slider", label = L["CC icon width"], min = 0, max = 64, step = 1, width = 130,
                              tooltip = L["0 = square (uses the icon size)."],
                              get = function() return mod.db.ccWidth or 0 end,
                              set = function(_, v) mod.db.ccWidth = v; applyAndRefresh() end },
                            { type = "slider", label = L["CC icon height"], min = 0, max = 64, step = 1, width = 130,
                              tooltip = L["0 = square (uses the icon size)."],
                              get = function() return mod.db.ccHeight or 0 end,
                              set = function(_, v) mod.db.ccHeight = v; applyAndRefresh() end },
                            cropSlider("cc", 130),
                        } } },
                  } },
                { type = "checkbox", label = L["Show target markers"],
                  tooltip = L["Shows the raid target icon (skull, cross, …) that is set on the unit."],
                  get = function() return mod.db.showRaidMarker end,
                  set = function(_, v) mod.db.showRaidMarker = v; applyAndRefresh() end,
                  inline = {
                      { kind = "gear", tooltip = L["Raid Marker"],
                        popup = { title = L["Raid Marker"], width = 380, items = {
                            { type = "dropdown", label = L["Marker position"], width = 220, values = markerPosValues(),
                              get = function() return mod.db.raidMarkerPos end,
                              set = function(_, v) mod.db.raidMarkerPos = v; applyAndRefresh() end },
                            { type = "slider", label = L["Marker size"], min = 8, max = 48, step = 1, width = 130,
                              get = function() return mod.db.raidMarkerSize end,
                              set = function(_, v) mod.db.raidMarkerSize = v; applyAndRefresh() end },
                            { type = "slider", label = L["Marker offset X"], min = -40, max = 40, step = 1, width = 130,
                              get = function() return mod.db.raidMarkerX end,
                              set = function(_, v) mod.db.raidMarkerX = v; applyAndRefresh() end },
                            { type = "slider", label = L["Marker offset Y"], min = -40, max = 40, step = 1, width = 130,
                              get = function() return mod.db.raidMarkerY end,
                              set = function(_, v) mod.db.raidMarkerY = v; applyAndRefresh() end },
                        } } },
                  } },
            } },
            { type = "checkbox", label = L["Show combo points"],
              tooltip = L["Shows your combo points on the target's nameplate (Rogue, or Druid in cat form)."],
              get = function() return mod.db.showClassPower end,
              set = function(_, v) mod.db.showClassPower = v; applyAndRefresh() end,
              inline = {
                  { kind = "gear", tooltip = L["Combo Points"],
                    popup = { title = L["Combo Points"], width = 380, items = {
                        { type = "slider", label = L["Pip size"], min = 4, max = 20, step = 1, width = 130,
                          get = function() return mod.db.cpSize end,
                          set = function(_, v) mod.db.cpSize = v; applyAndRefresh() end },
                        { type = "slider", label = L["Pip spacing"], min = 0, max = 12, step = 1, width = 130,
                          get = function() return mod.db.cpSpacing end,
                          set = function(_, v) mod.db.cpSpacing = v; applyAndRefresh() end },
                        { type = "color", label = L["Point colour"], width = 200,
                          get = function() return mod.db.cpColor end,
                          set = function(r, g, b) mod.db.cpColor = { r = r, g = g, b = b }; applyAndRefresh() end },
                        -- Menu, not a button row: four shapes is already the
                        -- ceiling for a strip, and this list is ours to extend.
                        { type = "dropdown", label = L["Point shape"], width = 220,
                          values = {
                              { value = "square",   text = L["Square"] },
                              { value = "circle",   text = L["Circle"] },
                              { value = "diamond",  text = L["Diamond"] },
                              { value = "triangle", text = L["Triangle"] },
                          },
                          get = function() return mod.db.cpShape or "square" end,
                          set = function(_, v) mod.db.cpShape = v; applyAndRefresh() end },
                        { type = "segmented", label = L["Position"], width = 220,
                          values = {
                              { value = "below", text = L["Below the bar"] },
                              { value = "above", text = L["Above the bar"] },
                          },
                          get = function() return mod.db.cpPos or "below" end,
                          set = function(_, v) mod.db.cpPos = v; applyAndRefresh() end },
                        { type = "slider", label = L["Offset X"], min = -60, max = 60, step = 1, width = 130,
                          get = function() return mod.db.cpOffsetX or 0 end,
                          set = function(_, v) mod.db.cpOffsetX = v; applyAndRefresh() end },
                        { type = "slider", label = L["Offset Y"], min = -40, max = 40, step = 1, width = 130,
                          get = function() return mod.db.cpOffsetY or 0 end,
                          set = function(_, v) mod.db.cpOffsetY = v; applyAndRefresh() end },
                    } } },
              } },
        } },

        { type = "section", title = L["Your Own Debuffs"], items = {
            { type = "desc",
              text = L["|cffaaaaaaA separate row for the harmful auras you cast yourself - your damage-over-time timers, kept away from everything else on the target.|r"] },
            { type = "checkbox", label = L["Show your own debuffs (separate row)"],
              get = function() return mod.db.showDots end,
              set = function(_, v) mod.db.showDots = v; refreshPage(); applyAndRefresh() end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Icon size"], min = 12, max = 48, step = 1, width = SLW,
                        get = function() return mod.db.dotSize end,
                        set = function(_, v) mod.db.dotSize = v; applyAndRefresh() end },
                      { type = "slider", label = L["Max icons"], min = 1, max = 12, step = 1, width = SLW,
                        get = function() return mod.db.maxDots end,
                        set = function(_, v) mod.db.maxDots = v; applyAndRefresh() end },
                  } },
                  cropSlider("dot", SLW),
                  -- placement moved to the slot section above
              } },
        } },




    }

    -- Three tabs (user request, 31.07.2026): every section keeps its code and
    -- its order -- this plan only decides which tab renders which. The loose
    -- head rows (description, preview-reaction picker) live on the first tab.
    local TAB_OF = {
        -- A section missing from this map is DROPPED, not defaulted -- which is
        -- exactly how "Style" shipped invisible on 02.08.2026. Every new section
        -- needs a line here.
        [L["Style"]]            = "display",
        [L["Main text positions"]]      = "display",
        [L["Health and cast bar"]]      = "display",
        [L["Cast colours and effects"]] = "display",
        [L["Target, focus and hover effects"]] = "display",
        [L["General text"]]             = "display",
        -- "Health Bar" is gone (user request, 02.08.2026). Its geometry and
        -- shape rows live in "Style" now; the rest -- smooth changes, edge glow,
        -- low-health glow and the execute line -- currently have NO control at
        -- all. The runtime still reads and draws them, so a profile keeps
        -- whatever it had; they simply cannot be changed until they get a home.
        -- "Text" is gone too (user request, 02.08.2026). showName and
        -- showHealthText went with it and are no longer read at all -- the text
        -- SLOT decides whether those two are drawn now, and "none" is the off.
        -- The rest (font, outline, sizes, the health text's own format, the
        -- level) currently has NO control; the runtime still reads it, so every
        -- profile keeps what it had.
        [L["Enemy colours"]]    = "colors",
        -- "Cast Bar" is gone as well (user request, 02.08.2026). NOTE showCastbar
        -- went with it: that is the cast bar's own on/off, and "Health and cast
        -- bar" has its height, icon, background, border and timer but no switch.
        -- It is the one row out of this section that most likely needs a home.
        [L["Target & Threat"]]  = "colors",
        -- "Auras" is gone too (user request, 02.08.2026). Two things the
        -- setter-counting script cannot see, so they are written down here:
        --   * showDebuffs / showBuffs are NOT orphaned -- setSlot writes them
        --     through mod.db[r.show], so the slot dropdowns still switch those
        --     two rows on and off.
        --   * the debuff and buff CROP sliders went with the section. Crowd
        --     control and your own debuffs keep theirs; those two rows have no
        --     crop control any more.
        [L["Main positions"]]   = "display",
        -- Crowd control, the raid marker and the combo points are one section
        -- now (02.08.2026): three headings for three switches left the right
        -- column empty three times over.
        [L["Extra indicators"]] = "display",
        -- On the general tab like the reference groups it: the extra aura
        -- switches sit with friendly plates, spacing and behaviour rather
        -- than between the visual sections.
        [L["Your Own Debuffs"]] = "general",
        [L["Other nameplates"]] = "general",
        [L["Nameplate spacing"]] = "general",
        [L["Extra aura options"]] = "general",
        [L["Target and focus effects"]] = "general",
        [L["Extras"]]           = "general",
    }
    -- nil = "everything", the way the Arena module answers it too: the
    -- talent-override replay walks GetOptions(mod, nil) and must see every
    -- row -- with a tab filter here, overrides recorded on colour or
    -- behaviour rows (stored with an empty tab before the tabs existed)
    -- would silently stop applying. The UI itself always asks with a tab.
    if tabId == nil then return all end
    if tabId == "default" then tabId = "display" end

    -- Two-column page (user request, 31.07.2026): gear rows only join the
    -- grid when marked pairable, and annotating ~a hundred literals by hand
    -- would drift the first time a row moves -- so the sweep marks every
    -- compact row that carries a gear. Long labels ellipsize in a half cell;
    -- the hover tooltip carries the full text.
    local PAIRABLE_TYPES = {
        toggle = true, checkbox = true, dropdown = true,
        color = true, slider = true, editbox = true,
    }
    local out = {}
    for _, it in ipairs(all) do
        if it.type == "section" then
            if TAB_OF[it.title] == tabId then
                for _, row in ipairs(it.items or {}) do
                    if row.subOptions and PAIRABLE_TYPES[row.type] and row.pairable == nil then
                        row.pairable = true
                    end
                end
                out[#out + 1] = it
            end
        elseif tabId == "display" then
            out[#out + 1] = it
        end
    end
    return out
end
