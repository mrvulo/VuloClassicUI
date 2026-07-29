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

local function setSlot(slotKey, rowKey)
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

-- Placement controls shared by every aura row; `key` selects which row's
-- settings the widgets read and write. withFilter is off for the rows whose
-- contents are already defined by what they collect (crowd control, your DoTs).
-- Side and growth are NOT offered here any more: the slot decides both, and a
-- second control for the same thing could put a row where its own slot says it
-- is not. What is left is the fine tuning that genuinely belongs to the row --
-- offsets, wrapping, filter.
local function rowPlacementItems(key, SLW, applyAndRefresh, withFilter)
    local function cfg() return ns:NameplateRowCfg(key) end
    local items = {}
    local rest = {
        { type = "group", layout = "row", gap = 8, items = {
            { type = "slider", label = L["Offset X"], min = -150, max = 150, step = 1, width = SLW,
              get = function() return cfg().x or 0 end,
              set = function(_, v) cfg().x = v; applyAndRefresh() end },
            { type = "slider", label = L["Offset Y"], min = -100, max = 100, step = 1, width = SLW,
              get = function() return cfg().y or 0 end,
              set = function(_, v) cfg().y = v; applyAndRefresh() end },
        } },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "slider", label = L["Icon spacing"], min = 0, max = 12, step = 1, width = SLW,
              get = function() return cfg().spacing or 2 end,
              set = function(_, v) cfg().spacing = v; applyAndRefresh() end },
            { type = "slider", label = L["Icons per line"], min = 0, max = 12, step = 1, width = SLW,
              tooltip = L["0 = one line. Otherwise the row wraps after this many icons."],
              get = function() return cfg().perRow or 0 end,
              set = function(_, v) cfg().perRow = v; applyAndRefresh() end },
        } },
    }
    for _, it in ipairs(rest) do items[#items + 1] = it end
    if withFilter then
        items[#items + 1] = { type = "dropdown", label = L["Limit to"], width = 300, values = rowFilterValues(),
            tooltip = L["Narrows this row to auras you cast yourself, or to ones that can be removed."],
            get = function() return cfg().filter or "all" end,
            set = function(_, v) cfg().filter = v; applyAndRefresh() end }
    end
    return items
end

-- Declared above, filled here: it needs rowPlacementItems.
slotItems = function(SLW, applyAndRefresh)
    local items = {}
    for _, s in ipairs(SLOTS) do
        local rowKey = contentOf(s.key)
        items[#items + 1] = {
            type = "dropdown", label = L[s.label], width = 260,
            subKey = "slot/" .. s.key,
            values = slotValues(),
            get = function() return contentOf(s.key) end,
            set = function(_, v) setSlot(s.key, v) end,
            -- The fine tuning hangs off the slot's gear and belongs to whatever
            -- row sits here right now. An empty slot has nothing to tune, so it
            -- gets no gear at all.
            subOptions = (rowKey ~= "none")
                and rowPlacementItems(rowKey, SLW, applyAndRefresh,
                        rowKey == "debuff" or rowKey == "buff")
                or nil,
        }
    end
    return items
end

-- A preset: one click that writes a whole look into the CURRENT profile.
--
-- The values were read out of a working setup rather than invented, and two
-- unit traps had to be undone on the way in -- both verified against the source
-- they came from, not guessed:
--
--   * the bar width was stored as an OFFSET onto a base of 150. Taken at face
--     value the plates would have come out 70 wide instead of 220.
--   * that setup stores only what differs from its own defaults, and it does
--     that per LEAF -- so a colour can arrive with one component missing. A
--     missing component is not zero, it is "unchanged", and four colours
--     (among them the threat warning) would have been read as a different
--     colour entirely.
--
-- Only settings we actually have are listed. Anything that needs a placement
-- model we do not have -- one aura row per anchor slot -- is deliberately
-- absent rather than approximated.
local PRESET = {
    -- health bar
    healthWidth          = 220,
    healthHeight         = 27,
    bgAlpha              = 0.8,
    borderColor          = { r = 0, g = 0, b = 0 },
    absorbAlpha          = 0.8,
    -- cast bar
    castHeight           = 20,
    colCast              = { r = 0.624, g = 0.749, b = 1 },
    colCastNoInterrupt   = { r = 0.486, g = 0.486, b = 0.486 },
    colCastKickReady     = { r = 0.78, g = 0.78, b = 0.78 },
    castBgAlpha          = 0.8,
    castBgColor          = { r = 0.031, g = 0.031, b = 0.031 },
    castTextSize         = 13,
    castTimerSize        = 13,
    showCastShield       = false,
    castInterruptFlash   = false,
    colInterruptFlash    = { r = 0.475, g = 0.84, b = 0.475 },
    -- reaction and threat
    colHostile           = { r = 0.635, g = 0.22, b = 0.22 },
    colNeutral           = { r = 0.851, g = 0.816, b = 0.588 },
    colThreatWarn        = { r = 1, g = 0.773, b = 0.427 },
    colThreatBad         = { r = 1, g = 0.655, b = 0.2 },
    -- target
    colTarget            = { r = 0.451, g = 0.506, b = 1 },
    nonTargetAlpha       = 0.7,
    -- text
    nameSize             = 13,
    fontSize             = 13,
    healthTextSize       = 13,
    healthTextMode       = "both",
    -- auras
    debuffSize           = 27,
    buffSize             = 28,
    ccSize               = 27,
    auraSpacing          = 1,
    auraTimerSize        = 14,
    showDispelGlow       = true,
    dispelGlowBySchool   = true,   -- dort: dispelGlowUseTypeColor
    lowHpGlow            = true,
    -- the raid marker sits above the plate there
    raidMarkerPos        = "top",
    raidMarkerSize       = 22,
}

-- Row spacing is NOT in the table above. mod.db.auraSpacing is only the
-- fallback (Modules/Nameplates.lua: `cfg.spacing or d.auraSpacing`), and every
-- row already carries its own value -- so writing the fallback alone would
-- change nothing visible.
local PRESET_ROW_SPACING = 1

local function applyPreset()
    for k, v in pairs(PRESET) do
        if type(v) == "table" then
            mod.db[k] = { r = v.r, g = v.g, b = v.b }   -- copy: the preset is shared
        else
            mod.db[k] = v
        end
    end
    for _, key in ipairs({ "debuff", "buff", "cc", "dot" }) do
        local cfg = ns.NameplateRowCfg and ns:NameplateRowCfg(key)
        if cfg then cfg.spacing = PRESET_ROW_SPACING end
    end
    applyAndRefresh()
    refreshPage()
    ns:Print(L["Nameplate settings replaced. Switch profile to get the old ones back."])
end

ns.OnLocaleReady(function()
StaticPopupDialogs["VCUI_NAMEPLATES_PRESET"] = {
    text = L["Overwrites this profile's nameplate settings with a wide, flat, dark look. Other profiles are untouched."],
    button1 = _G.ACCEPT or "Accept", button2 = _G.CANCEL or "Cancel",
    OnAccept = function() applyPreset() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
end)

local function outlineValues()
    return {
        { value = "OUTLINE",      text = L["Outline"] },
        { value = "THICKOUTLINE", text = L["Thick outline"] },
        { value = "SHADOW",       text = L["Shadow"] },
        { value = "",             text = L["None"] },
    }
end

function mod:GetOptions()
    local SLW = 180
    return {
        { type = "desc",
          text = L["|cffaaaaaaCustom nameplates for enemies and NPCs. Configure below — the live preview updates as you change each option.|r"] },

        { type = "custom", height = 214, build = function(parent) return buildPreview(parent) end },
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

        { type = "section", title = L["Preset"], items = {
            { type = "desc",
              text = L["|cffaaaaaaOverwrites this profile's nameplate settings with a wide, flat, dark look. Other profiles are untouched.|r"] },
            { type = "button", label = L["Apply the wide, flat look"], width = 260,
              onClick = function() StaticPopup_Show("VCUI_NAMEPLATES_PRESET") end },
        } },

        { type = "section", title = L["Health Bar"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Width"], min = 60, max = 240, step = 2, width = SLW,
                  get = function() return mod.db.healthWidth end,
                  set = function(_, v) mod.db.healthWidth = v; applyAndRefresh() end },
                { type = "slider", label = L["Height"], min = 4, max = 40, step = 1, width = SLW,
                  get = function() return mod.db.healthHeight end,
                  set = function(_, v) mod.db.healthHeight = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Smooth health changes"],
                  tooltip = L["The bar glides to the new value; a bright trail marks health draining away."],
                  get = function() return mod.db.healthSmooth end,
                  set = function(_, v) mod.db.healthSmooth = v; applyAndRefresh() end },
                { type = "checkbox", label = L["Tint background with bar colour"],
                  tooltip = L["The empty part of the bar shows a darkened shade of the bar colour instead of plain dark grey."],
                  get = function() return mod.db.bgTintByBar end,
                  set = function(_, v) mod.db.bgTintByBar = v; applyAndRefresh() end },
            } },
            -- Out of its pair row on purpose: an item inside layout="row" goes
            -- through PlaceGroup, which never draws a gear, so a parent has to
            -- stand on its own. "Rounded bar corners" pairs up again by itself.
            { type = "checkbox", label = L["Glow at the bar edge"],
              tooltip = L["A soft glow rides the end of the fill, tinted in the bar's own colour. Also applies to the cast bar."],
              get = function() return mod.db.showSpark end,
              set = function(_, v) mod.db.showSpark = v; applyAndRefresh() end,
              subOptions = {
                  { type = "slider", label = L["Edge glow width"], min = 2, max = 40, step = 1, width = SLW,
                    get = function() return mod.db.sparkWidth end,
                    set = function(_, v) mod.db.sparkWidth = v; applyAndRefresh() end },
              } },
            { type = "checkbox", label = L["Rounded bar corners"],
              tooltip = L["Clips the fill and background to a rounded shape. The line border stays square, so a thin border may show slightly at the corners."],
              get = function() return mod.db.roundedBars end,
              set = function(_, v) mod.db.roundedBars = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Bar texture"], width = 300, values = textureValues(),
              get = function() return mod.db.healthTexture end,
              set = function(_, v) mod.db.healthTexture = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Border style"], width = 300, values = borderStyleValues(),
              get = function() return mod.db.borderStyle end,
              set = function(_, v) mod.db.borderStyle = v; applyAndRefresh() end,
              subOptions = {
                  { type = "dropdown", label = L["Border texture"], width = 300, values = borderTextureValues(),
                    get = function() return mod.db.borderTexture end,
                    set = function(_, v) mod.db.borderTexture = v; applyAndRefresh() end },
                  { type = "color", label = L["Border colour"], width = 200,
                    get = function() return mod.db.borderColor end,
                    set = function(r, g, b) mod.db.borderColor = { r = r, g = g, b = b }; applyAndRefresh() end },
                  { type = "slider", label = L["Border thickness (px)"], min = 0, max = 12, step = 1,
                    get = function() return mod.db.borderSize end,
                    set = function(_, v) mod.db.borderSize = v; applyAndRefresh() end },
              } },
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
            { type = "checkbox", label = L["Show absorb shield"],
              tooltip = L["Overlays damage-absorption shields (e.g. Power Word: Shield) on the health bar."],
              get = function() return mod.db.showAbsorb end,
              set = function(_, v) mod.db.showAbsorb = v; applyAndRefresh() end,
              subOptions = {
                  -- "Flat" first: it is what the shield looked like before this
                  -- existed, so an untouched profile finds itself at the top.
                  { type = "dropdown", label = L["Absorb style"], width = 300,
                    values = (function()
                        local vals = { { value = "flat", text = L["Flat colour"] } }
                        for _, v in ipairs(textureValues()) do vals[#vals + 1] = v end
                        return vals
                    end)(),
                    get = function() return mod.db.absorbStyle or "flat" end,
                    set = function(_, v) mod.db.absorbStyle = v; applyAndRefresh() end },
                  { type = "color", label = L["Absorb colour"], width = 200,
                    get = function() return mod.db.colAbsorb end,
                    set = function(r, g, b) mod.db.colAbsorb = { r = r, g = g, b = b }; applyAndRefresh() end },
                  { type = "slider", label = L["Absorb opacity"], min = 10, max = 100, step = 5,
                    get = function() return floor((mod.db.absorbAlpha or 0.55) * 100 + 0.5) end,
                    set = function(_, v) mod.db.absorbAlpha = v / 100; applyAndRefresh() end },
              } },
            { type = "checkbox", label = L["Glow when low on health"],
              tooltip = L["A coloured ring around the bar once the unit drops below the mark."],
              get = function() return mod.db.lowHpGlow end,
              set = function(_, v) mod.db.lowHpGlow = v; applyAndRefresh() end,
              subOptions = {
                  { type = "slider", label = L["Glow below (%)"], min = 5, max = 90, step = 5, width = SLW,
                    get = function() return mod.db.lowHpPct or 35 end,
                    set = function(_, v) mod.db.lowHpPct = v; applyAndRefresh() end },
                  { type = "color", label = L["Low health colour"], width = 200,
                    get = function() return mod.db.colLowHp end,
                    set = function(r, g, b) mod.db.colLowHp = { r = r, g = g, b = b }; applyAndRefresh() end },
              } },
            { type = "checkbox", label = L["Execute line"],
              tooltip = L["A thin marker line on the bar at the chosen health percentage (e.g. 20 for Execute)."],
              get = function() return mod.db.execLine end,
              set = function(_, v) mod.db.execLine = v; applyAndRefresh() end,
              subOptions = {
                  { type = "checkbox", label = L["Execute line only on your target"],
                    get = function() return mod.db.execTargetOnly end,
                    set = function(_, v) mod.db.execTargetOnly = v; applyAndRefresh() end },
                  { type = "color", label = L["Execute line colour"], width = 200,
                    get = function() return mod.db.colExec end,
                    set = function(r, g, b) mod.db.colExec = { r = r, g = g, b = b }; applyAndRefresh() end },
                  { type = "slider", label = L["Execute line percent"], min = 5, max = 90, step = 1,
                    get = function() return mod.db.execPct or 20 end,
                    set = function(_, v) mod.db.execPct = v; applyAndRefresh() end },
              } },
        } },

        { type = "section", title = L["Text"], items = {
            { type = "dropdown", label = L["Font"], width = 300, values = fontValues(),
              tooltip = L["The typeface for every text on the plates (name, health, cast, auras)."],
              get = function() return mod.db.fontFace or "" end,
              set = function(_, v) mod.db.fontFace = v; applyAndRefresh() end },
            { type = "dropdown", label = L["Font outline"], width = 300, values = outlineValues(),
              tooltip = L["How plate text is lifted off the background."],
              get = function() return mod.db.fontOutline or "OUTLINE" end,
              set = function(_, v) mod.db.fontOutline = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Show name"],
              get = function() return mod.db.showName end,
              set = function(_, v) mod.db.showName = v; refreshPage(); applyAndRefresh() end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Name offset X"], min = -100, max = 100, step = 1, width = SLW,
                        get = function() return mod.db.nameOffsetX or 0 end,
                        set = function(_, v) mod.db.nameOffsetX = v; applyAndRefresh() end },
                      { type = "slider", label = L["Name offset Y"], min = -40, max = 40, step = 1, width = SLW,
                        get = function() return mod.db.nameOffsetY or 0 end,
                        set = function(_, v) mod.db.nameOffsetY = v; applyAndRefresh() end },
                  } },
              } },
            { type = "checkbox", label = L["Show level"],
              tooltip = L["Shows the unit level to the left of the name; ?? means the level is far above yours."],
              get = function() return mod.db.showLevel end,
              set = function(_, v) mod.db.showLevel = v; applyAndRefresh() end,
              subOptions = {
                  { type = "checkbox", label = L["Mark rare and elite"],
                    tooltip = L["Appends a rank to the level and turns it gold: + elite, R rare, R+ rare elite, B world boss."],
                    get = function() return mod.db.showLevelMod ~= false end,
                    set = function(_, v) mod.db.showLevelMod = v; applyAndRefresh() end },
                  { type = "slider", label = L["Level size"], min = 0, max = 20, step = 1, width = SLW,
                    tooltip = L["0 = uses the name size."],
                    get = function() return mod.db.levelSize or 0 end,
                    set = function(_, v) mod.db.levelSize = v; applyAndRefresh() end },
              } },
            { type = "checkbox", label = L["Show health text"],
              get = function() return mod.db.showHealthText end,
              set = function(_, v) mod.db.showHealthText = v; refreshPage(); applyAndRefresh() end,
              subOptions = {
                  { type = "dropdown", label = L["Health text"], width = 300, values = textModeValues(),
                    get = function() return mod.db.healthTextMode end,
                    set = function(_, v) mod.db.healthTextMode = v; applyAndRefresh() end },
                  { type = "dropdown", label = L["Value + percent layout"], width = 300,
                    values = {
                        { value = "%s (%s)", text = "12.3k (45%)" },
                        { value = "%s | %s", text = "12.3k | 45%" },
                        { value = "%s - %s", text = "12.3k - 45%" },
                        { value = "%s %s",   text = "12.3k 45%" },
                    },
                    get = function() return mod.db.healthTextFormat or "%s (%s)" end,
                    set = function(_, v) mod.db.healthTextFormat = v; applyAndRefresh() end },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "checkbox", label = L["Short values (12.3k)"],
                        get = function() return mod.db.healthTextShort end,
                        set = function(_, v) mod.db.healthTextShort = v; applyAndRefresh() end },
                      { type = "checkbox", label = L["Show percent sign"],
                        get = function() return mod.db.healthTextPercentSign ~= false end,
                        set = function(_, v) mod.db.healthTextPercentSign = v; applyAndRefresh() end },
                  } },
                  { type = "slider", label = L["Health text size"], min = 0, max = 20, step = 1, width = SLW,
                    tooltip = L["0 = uses the general text size."],
                    get = function() return mod.db.healthTextSize or 0 end,
                    set = function(_, v) mod.db.healthTextSize = v; applyAndRefresh() end },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Health text offset X"], min = -100, max = 100, step = 1, width = SLW,
                        get = function() return mod.db.healthTextOffsetX or 0 end,
                        set = function(_, v) mod.db.healthTextOffsetX = v; applyAndRefresh() end },
                      { type = "slider", label = L["Health text offset Y"], min = -40, max = 40, step = 1, width = SLW,
                        get = function() return mod.db.healthTextOffsetY or 0 end,
                        set = function(_, v) mod.db.healthTextOffsetY = v; applyAndRefresh() end },
                  } },
              } },
            -- Stays out here: these two are the general type sizes, not the name's
            -- and not the health text's -- the aura and cast rows read them too.
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Name size"], min = 6, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.nameSize end,
                  set = function(_, v) mod.db.nameSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Text size"], min = 6, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.fontSize end,
                  set = function(_, v) mod.db.fontSize = v; applyAndRefresh() end },
            } },
        } },

        { type = "section", title = L["Colours"], items = {
            { type = "checkbox", label = L["Class colour for enemy players"],
              get = function() return mod.db.classColorEnemy end,
              set = function(_, v) mod.db.classColorEnemy = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Class colour for friendly players"],
              get = function() return mod.db.classColorFriendly end,
              set = function(_, v) mod.db.classColorFriendly = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "color", label = L["Hostile"], width = 160,
                  get = function() return mod.db.colHostile end,
                  set = function(r, g, b) mod.db.colHostile = { r = r, g = g, b = b }; applyAndRefresh() end },
                { type = "color", label = L["Neutral"], width = 160,
                  get = function() return mod.db.colNeutral end,
                  set = function(r, g, b) mod.db.colNeutral = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "color", label = L["Friendly"], width = 160,
                  get = function() return mod.db.colFriendly end,
                  set = function(r, g, b) mod.db.colFriendly = { r = r, g = g, b = b }; applyAndRefresh() end },
                { type = "color", label = L["Tapped"], width = 160,
                  get = function() return mod.db.colTapped end,
                  set = function(r, g, b) mod.db.colTapped = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
        } },

        { type = "section", title = L["Cast Bar"], items = {
            { type = "checkbox", label = L["Show cast bar"],
              get = function() return mod.db.showCastbar end,
              set = function(_, v) mod.db.showCastbar = v; refreshPage(); applyAndRefresh() end },
            { type = "checkbox", label = L["Show cast icon"],
              get = function() return mod.db.showCastIcon end,
              set = function(_, v) mod.db.showCastIcon = v; applyAndRefresh() end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Icon scale"], min = 50, max = 200, step = 5, width = SLW,
                        get = function() return mod.db.castIconScale or 100 end,
                        set = function(_, v) mod.db.castIconScale = v; applyAndRefresh() end },
                      { type = "checkbox", label = L["Icon on the right"],
                        get = function() return mod.db.castIconRight end,
                        set = function(_, v) mod.db.castIconRight = v; applyAndRefresh() end },
                  } },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Icon offset X"], min = -40, max = 40, step = 1, width = SLW,
                        get = function() return mod.db.castIconX or 0 end,
                        set = function(_, v) mod.db.castIconX = v; applyAndRefresh() end },
                      { type = "slider", label = L["Icon offset Y"], min = -40, max = 40, step = 1, width = SLW,
                        get = function() return mod.db.castIconY or 0 end,
                        set = function(_, v) mod.db.castIconY = v; applyAndRefresh() end },
                  } },
              } },
            { type = "checkbox", label = L["Show cast text"],
              get = function() return mod.db.showCastText end,
              set = function(_, v) mod.db.showCastText = v; applyAndRefresh() end,
              subOptions = {
                  { type = "color", label = L["Cast text colour"], width = 200,
                    get = function() return mod.db.castTextColor end,
                    set = function(r, g, b) mod.db.castTextColor = { r = r, g = g, b = b }; applyAndRefresh() end },
              } },
            { type = "dropdown", label = L["Cast bar texture"], width = 300, values = textureValues(),
              get = function() return mod.db.castTexture end,
              set = function(_, v) mod.db.castTexture = v; applyAndRefresh() end },
            { type = "color", label = L["Cast colour"], width = 200,
              get = function() return mod.db.colCast end,
              set = function(r, g, b) mod.db.colCast = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "color", label = L["Non-interruptible"], width = 200,
              get = function() return mod.db.colCastNoInterrupt end,
              set = function(r, g, b) mod.db.colCastNoInterrupt = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "checkbox", label = L["Show remaining cast time"],
              get = function() return mod.db.castTimer end,
              set = function(_, v) mod.db.castTimer = v; applyAndRefresh() end,
              subOptions = {
                  { type = "segmented", label = L["Timer side"], width = 220,
                    values = {
                        { value = "right", text = L["Right"] },
                        { value = "left",  text = L["Left"] },
                    },
                    get = function() return mod.db.castTimerSide or "right" end,
                    set = function(_, v) mod.db.castTimerSide = v; applyAndRefresh() end },
                  { type = "color", label = L["Timer colour"], width = 200,
                    get = function() return mod.db.castTimerColor end,
                    set = function(r, g, b) mod.db.castTimerColor = { r = r, g = g, b = b }; applyAndRefresh() end },
              } },
            { type = "checkbox", label = L["Own colour while your interrupt is on cooldown"],
              tooltip = L["Interruptible casts paint differently while YOUR interrupt ability is still on cooldown — you see at a glance whether kicking is even possible."],
              get = function() return mod.db.kickColorOn end,
              set = function(_, v) mod.db.kickColorOn = v; applyAndRefresh() end,
              subOptions = {
                  { type = "color", label = L["Interrupt-on-cooldown colour"], width = 220,
                    get = function() return mod.db.colCastKickCd end,
                    set = function(r, g, b) mod.db.colCastKickCd = { r = r, g = g, b = b }; applyAndRefresh() end },
              } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Own colour while your interrupt is ready"],
                  tooltip = L["Interruptible casts paint in this colour while your interrupt is off cooldown — kick at will."],
                  get = function() return mod.db.kickReadyColorOn end,
                  set = function(_, v) mod.db.kickReadyColorOn = v; applyAndRefresh() end },
                { type = "color", label = L["Interrupt-ready colour"], width = 160,
                  get = function() return mod.db.colCastKickReady end,
                  set = function(r, g, b) mod.db.colCastKickReady = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Own colour while channelling"],
                  get = function() return mod.db.castChannelColor end,
                  set = function(_, v) mod.db.castChannelColor = v; applyAndRefresh() end },
                { type = "color", label = L["Channel colour"], width = 160,
                  get = function() return mod.db.colCastChannel end,
                  set = function(r, g, b) mod.db.colCastChannel = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Own colour when the cast targets YOU"],
                  tooltip = L["The bar turns this colour while the caster's target is you."],
                  get = function() return mod.db.castYouColorOn end,
                  set = function(_, v) mod.db.castYouColorOn = v; applyAndRefresh() end },
                { type = "color", label = L["Targets-you colour"], width = 160,
                  get = function() return mod.db.colCastYou end,
                  set = function(r, g, b) mod.db.colCastYou = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Cast bar height"], min = 4, max = 30, step = 1, width = SLW,
                  get = function() return mod.db.castHeight end,
                  set = function(_, v) mod.db.castHeight = v; applyAndRefresh() end },
                { type = "slider", label = L["Cast bar width"], min = 0, max = 250, step = 2, width = SLW,
                  tooltip = L["0 = match the health bar width."],
                  get = function() return mod.db.castWidth or 0 end,
                  set = function(_, v) mod.db.castWidth = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Cast text size"], min = 0, max = 20, step = 1, width = SLW,
                  tooltip = L["0 = uses the general text size."],
                  get = function() return mod.db.castTextSize or 0 end,
                  set = function(_, v) mod.db.castTextSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Cast timer size"], min = 0, max = 20, step = 1, width = SLW,
                  tooltip = L["0 = uses the general text size."],
                  get = function() return mod.db.castTimerSize or 0 end,
                  set = function(_, v) mod.db.castTimerSize = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Offset X"], min = -100, max = 100, step = 1, width = SLW,
                  get = function() return mod.db.castOffsetX or 0 end,
                  set = function(_, v) mod.db.castOffsetX = v; applyAndRefresh() end },
                { type = "slider", label = L["Offset Y"], min = -60, max = 60, step = 1, width = SLW,
                  get = function() return mod.db.castOffsetY or 0 end,
                  set = function(_, v) mod.db.castOffsetY = v; applyAndRefresh() end },
            } },
            { type = "color", label = L["Cast background colour"], width = 220,
              get = function() return mod.db.castBgColor end,
              set = function(r, g, b) mod.db.castBgColor = { r = r, g = g, b = b }; applyAndRefresh() end },
            { type = "slider", label = L["Cast background opacity"], min = 0, max = 100, step = 5, width = SLW,
              tooltip = L["0 = uses the global background opacity."],
              get = function() return floor((mod.db.castBgAlpha or 0) * 100 + 0.5) end,
              set = function(_, v) mod.db.castBgAlpha = v / 100; applyAndRefresh() end },
            { type = "checkbox", label = L["Shield on uninterruptible casts"],
              get = function() return mod.db.showCastShield end,
              set = function(_, v) mod.db.showCastShield = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Tick where your interrupt becomes ready"],
              tooltip = L["Marks the spot on the enemy cast bar where YOUR interrupt comes off cooldown — everything after the tick is kickable."],
              get = function() return mod.db.castKickTick end,
              set = function(_, v) mod.db.castKickTick = v; applyAndRefresh() end,
              subOptions = {
                  { type = "color", label = L["Tick colour"], width = 200,
                    get = function() return mod.db.colKickTick end,
                    set = function(r, g, b) mod.db.colKickTick = { r = r, g = g, b = b }; applyAndRefresh() end },
              } },
            -- "Show who interrupted" moved in here from further down: its own
            -- tooltip says the name rides ON the interrupt flash, so with the
            -- flash off it has nothing to write to.
            { type = "checkbox", label = L["Flash when a cast is interrupted"],
              get = function() return mod.db.castInterruptFlash end,
              set = function(_, v) mod.db.castInterruptFlash = v; applyAndRefresh() end,
              subOptions = {
                  { type = "color", label = L["Flash colour"], width = 200,
                    get = function() return mod.db.colInterruptFlash end,
                    set = function(r, g, b) mod.db.colInterruptFlash = { r = r, g = g, b = b }; applyAndRefresh() end },
                  { type = "checkbox", label = L["Show who interrupted"],
                    tooltip = L["The interrupt flash shows the name of whoever landed the interrupt."],
                    get = function() return mod.db.castInterrupter end,
                    set = function(_, v) mod.db.castInterrupter = v; applyAndRefresh() end },
              } },
            { type = "checkbox", label = L["Hide name while casting"],
              get = function() return mod.db.hideNameWhileCasting end,
              set = function(_, v) mod.db.hideNameWhileCasting = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Emphasise casting units"],
              tooltip = L["While a unit casts, its plate grows a little and stays readable even when something else is targeted."],
              get = function() return mod.db.castEmphasis end,
              set = function(_, v) mod.db.castEmphasis = v; applyAndRefresh() end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Casting scale (%)"], min = 100, max = 160, step = 5, width = SLW,
                        get = function() return mod.db.castEmphScale or 110 end,
                        set = function(_, v) mod.db.castEmphScale = v; applyAndRefresh() end },
                      { type = "slider", label = L["Casting opacity (%)"], min = 10, max = 100, step = 5, width = SLW,
                        get = function() return mod.db.castEmphAlpha or 100 end,
                        set = function(_, v) mod.db.castEmphAlpha = v; applyAndRefresh() end },
                  } },
              } },
        } },

        { type = "section", title = L["Target & Threat"], items = {
            { type = "checkbox", label = L["Highlight your target"],
              get = function() return mod.db.targetHighlight end,
              set = function(_, v) mod.db.targetHighlight = v; applyAndRefresh() end,
              subOptions = {
                  { type = "color", label = L["Target highlight colour"], width = 220,
                    get = function() return mod.db.colTarget end,
                    set = function(r, g, b) mod.db.colTarget = { r = r, g = g, b = b }; applyAndRefresh() end },
              } },
            { type = "checkbox", label = L["Own bar colour on your target"],
              tooltip = L["Your current target's health bar uses this colour instead of reaction / class / threat colours."],
              get = function() return mod.db.targetBarColor end,
              set = function(_, v) mod.db.targetBarColor = v; applyAndRefresh() end,
              subOptions = {
                  { type = "color", label = L["Target bar colour"], width = 220,
                    get = function() return mod.db.colTargetBar end,
                    set = function(r, g, b) mod.db.colTargetBar = { r = r, g = g, b = b }; applyAndRefresh() end },
              } },
            { type = "checkbox", label = L["Mouseover highlight"],
              tooltip = L["Lightens the health bar of the plate under your mouse cursor."],
              get = function() return mod.db.hoverHighlight end,
              set = function(_, v) mod.db.hoverHighlight = v; updateHoverTicker() end },
            { type = "slider", label = L["Target plate scale"], min = 100, max = 150, step = 5,
              tooltip = L["Your target's plate is drawn this much larger (100 = off)."],
              get = function() return mod.db.targetScale or 100 end,
              set = function(_, v) mod.db.targetScale = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Highlight your focus"],
              tooltip = L["A second, distinct glow ring on your focus target's nameplate."],
              get = function() return mod.db.focusHighlight end,
              set = function(_, v) mod.db.focusHighlight = v; applyAndRefresh() end,
              subOptions = {
                  { type = "color", label = L["Focus highlight colour"], width = 220,
                    get = function() return mod.db.colFocus end,
                    set = function(r, g, b) mod.db.colFocus = { r = r, g = g, b = b }; applyAndRefresh() end },
              } },
            { type = "slider", label = L["Non-target opacity"], min = 20, max = 100, step = 5, width = SLW,
              get = function() return floor((mod.db.nonTargetAlpha or 1) * 100 + 0.5) end,
              set = function(_, v) mod.db.nonTargetAlpha = v / 100; applyAndRefresh() end },
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

        { type = "section", title = L["Auras"], items = {
            { type = "checkbox", label = L["Show debuffs"],
              get = function() return mod.db.showDebuffs end,
              set = function(_, v) mod.db.showDebuffs = v; refreshPage(); applyAndRefresh() end,
              subOptions = {
                  { type = "checkbox", label = L["Show all debuffs (not just yours)"],
                    tooltip = L["Off: only debuffs you applied. On: every debuff on the unit."],
                    get = function() return mod.db.debuffsAll end,
                    set = function(_, v) mod.db.debuffsAll = v; applyAndRefresh() end },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Debuff icon size"], min = 12, max = 40, step = 1, width = SLW,
                        get = function() return mod.db.debuffSize end,
                        set = function(_, v) mod.db.debuffSize = v; applyAndRefresh() end },
                      { type = "slider", label = L["Max debuffs"], min = 1, max = 8, step = 1, width = SLW,
                        get = function() return mod.db.maxDebuffs end,
                        set = function(_, v) mod.db.maxDebuffs = v; applyAndRefresh() end },
                  } },
              } },
            { type = "checkbox", label = L["Show buffs"],
              get = function() return mod.db.showBuffs end,
              set = function(_, v) mod.db.showBuffs = v; refreshPage(); applyAndRefresh() end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Buff icon size"], min = 12, max = 40, step = 1, width = SLW,
                        get = function() return mod.db.buffSize end,
                        set = function(_, v) mod.db.buffSize = v; applyAndRefresh() end },
                      { type = "slider", label = L["Max buffs"], min = 1, max = 8, step = 1, width = SLW,
                        get = function() return mod.db.maxBuffs end,
                        set = function(_, v) mod.db.maxBuffs = v; applyAndRefresh() end },
                  } },
              } },
            -- Spacing moved into each row's own section; a global control here
            -- would be dead, since every row now carries its own value.
            { type = "checkbox", label = L["Cooldown swipe"],
              get = function() return mod.db.auraSwipe end,
              set = function(_, v) mod.db.auraSwipe = v; applyAndRefresh() end },
            -- "Dispel glow colour" moved up out of the flat run: it was four rows
            -- away from the switch that is the only thing that draws it.
            { type = "checkbox", label = L["Glow stealable / dispellable buffs"],
              tooltip = L["Glows enemy buffs you can remove (Spellsteal / Purge / Dispel Magic). Only for classes that can."],
              get = function() return mod.db.showDispelGlow end,
              set = function(_, v) mod.db.showDispelGlow = v; applyAndRefresh() end,
              subOptions = {
                  { type = "checkbox", label = L["Glow in the aura's own school colour"],
                    tooltip = L["Magic blue, curse purple, disease orange, poison green — instead of one colour for everything."],
                    get = function() return mod.db.dispelGlowBySchool end,
                    set = function(_, v) mod.db.dispelGlowBySchool = v; applyAndRefresh() end },
                  { type = "color", label = L["Dispel glow colour"], width = 220,
                    get = function() return mod.db.colDispel end,
                    set = function(r, g, b) mod.db.colDispel = { r = r, g = g, b = b }; applyAndRefresh() end },
              } },
            { type = "checkbox", label = L["Colour border by school"],
              tooltip = L["Aura borders take the colour of their school: magic blue, curse purple, disease orange, poison green."],
              get = function() return mod.db.auraTypeBorder ~= false end,
              set = function(_, v) mod.db.auraTypeBorder = v; applyAndRefresh() end },
            { type = "checkbox", label = L["Flash before running out"],
              tooltip = L["The icon pulses over the last part of its duration, so you can see when to refresh."],
              get = function() return mod.db.auraExpireFlash ~= false end,
              set = function(_, v) mod.db.auraExpireFlash = v; applyAndRefresh() end,
              subOptions = {
                  { type = "slider", label = L["Flash below (%)"], min = 5, max = 60, step = 5, width = SLW,
                    tooltip = L["Share of the remaining duration at which the pulse starts."],
                    get = function() return mod.db.auraExpirePct or 30 end,
                    set = function(_, v) mod.db.auraExpirePct = v; applyAndRefresh() end },
              } },
            { type = "checkbox", label = L["Show timer text"],
              get = function() return mod.db.showAuraTimer end,
              set = function(_, v) mod.db.showAuraTimer = v; applyAndRefresh() end,
              subOptions = {
                  { type = "checkbox", label = L["Timer decimals below 10 seconds"],
                    tooltip = L["On: 9.9, 3.4 … Off: whole seconds (9, 3)."],
                    get = function() return mod.db.auraTimerDecimals ~= false end,
                    set = function(_, v) mod.db.auraTimerDecimals = v; applyAndRefresh() end },
              } },
            { type = "checkbox", label = L["Show stacks"],
              get = function() return mod.db.showAuraStacks end,
              set = function(_, v) mod.db.showAuraStacks = v; applyAndRefresh() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Timer text size"], min = 6, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.auraTimerSize end,
                  set = function(_, v) mod.db.auraTimerSize = v; applyAndRefresh() end },
                { type = "slider", label = L["Stack text size"], min = 6, max = 20, step = 1, width = SLW,
                  get = function() return mod.db.auraStackSize end,
                  set = function(_, v) mod.db.auraStackSize = v; applyAndRefresh() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Aura offset X"], min = -100, max = 100, step = 1, width = SLW,
                  tooltip = L["Nudges every aura row at once, on top of each row's own offset."],
                  get = function() return mod.db.auraOffsetX or 0 end,
                  set = function(_, v) mod.db.auraOffsetX = v; applyAndRefresh() end },
                { type = "slider", label = L["Aura offset Y"], min = -40, max = 60, step = 1, width = SLW,
                  tooltip = L["Nudges every aura row at once, on top of each row's own offset."],
                  get = function() return mod.db.auraOffsetY or 0 end,
                  set = function(_, v) mod.db.auraOffsetY = v; applyAndRefresh() end },
            } },
        } },

        -- Replaces the four separate "row" sections. Placement is asked slot by
        -- slot now, not row by row, so two rows can no longer claim one spot.
        { type = "section", title = L["Main positions"], items = (function()
            local items = { { type = "desc",
                text = L["|cffaaaaaaOne thing per slot. Giving a slot something takes it away from the slot that had it.|r"] } }
            for _, it in ipairs(slotItems(SLW, applyAndRefresh)) do items[#items + 1] = it end
            return items
        end)() },

        { type = "section", title = L["Crowd Control"], items = {
            -- The whole section hangs off this one switch, placement rows and
            -- all, so it becomes a single row with a gear. unpack has to stay
            -- last inside the table it expands into, exactly as before.
            { type = "checkbox", label = L["Show crowd control (separate row)"],
              tooltip = L["A separate, prominent row for crowd-control effects (Polymorph, Fear, Sap, …) on the unit, from anyone."],
              get = function() return mod.db.showCC end,
              set = function(_, v) mod.db.showCC = v; refreshPage(); applyAndRefresh() end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["CC icon size"], min = 12, max = 48, step = 1, width = SLW,
                        get = function() return mod.db.ccSize end,
                        set = function(_, v) mod.db.ccSize = v; applyAndRefresh() end },
                      { type = "slider", label = L["Max CC"], min = 1, max = 5, step = 1, width = SLW,
                        get = function() return mod.db.maxCC end,
                        set = function(_, v) mod.db.maxCC = v; applyAndRefresh() end },
                  } },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["CC icon width"], min = 0, max = 64, step = 1, width = SLW,
                        tooltip = L["0 = square (uses the icon size)."],
                        get = function() return mod.db.ccWidth or 0 end,
                        set = function(_, v) mod.db.ccWidth = v; applyAndRefresh() end },
                      { type = "slider", label = L["CC icon height"], min = 0, max = 64, step = 1, width = SLW,
                        tooltip = L["0 = square (uses the icon size)."],
                        get = function() return mod.db.ccHeight or 0 end,
                        set = function(_, v) mod.db.ccHeight = v; applyAndRefresh() end },
                  } },
                  -- placement moved to the slot section above
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
                  -- placement moved to the slot section above
              } },
        } },

        { type = "section", title = L["Friendly Plates"], items = {
            { type = "checkbox", label = L["Show friendly nameplates"],
              tooltip = L["Sets Blizzard's friendly-nameplate option (cannot change in combat)."],
              get = function() return mod.db.friendlyShow end,
              set = function(_, v) mod.db.friendlyShow = v; applyFriendlyCVar(); applyAndRefresh() end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "dropdown", label = L["Friendly players"], width = 300, values = friendlyModeValues(),
                        get = function() return mod.db.friendlyPlayers end,
                        set = function(_, v) mod.db.friendlyPlayers = v; applyAndRefresh() end },
                      { type = "dropdown", label = L["Friendly NPCs"], width = 300, values = friendlyModeValues(),
                        get = function() return mod.db.friendlyNPCs end,
                        set = function(_, v) mod.db.friendlyNPCs = v; applyAndRefresh() end },
                  } },
              } },
            -- The size used to sit ABOVE the switch that turns the title on at
            -- all; nesting it puts the two in the right order as a side effect.
            { type = "checkbox", label = L["Show NPC title"],
              tooltip = L["Shows a friendly NPC's subtitle (e.g. <Innkeeper>) under its name in name-only mode."],
              get = function() return mod.db.showNPCTitle end,
              set = function(_, v) mod.db.showNPCTitle = v; applyAndRefresh() end,
              subOptions = {
                  { type = "slider", label = L["NPC title size"], min = 0, max = 20, step = 1, width = SLW,
                    tooltip = L["0 = slightly smaller than the name."],
                    get = function() return mod.db.titleSize or 0 end,
                    set = function(_, v) mod.db.titleSize = v; applyAndRefresh() end },
              } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "color", label = L["Friendly player name"], width = 220,
                  get = function() return mod.db.friendlyNameColor end,
                  set = function(r, g, b) mod.db.friendlyNameColor = { r = r, g = g, b = b }; applyAndRefresh() end },
                { type = "color", label = L["Friendly NPC name"], width = 220,
                  get = function() return mod.db.friendlyNPCColor end,
                  set = function(r, g, b) mod.db.friendlyNPCColor = { r = r, g = g, b = b }; applyAndRefresh() end },
            } },
        } },

        { type = "section", title = L["Raid Marker"], items = {
            { type = "checkbox", label = L["Show target markers"],
              tooltip = L["Shows the raid target icon (skull, cross, …) that is set on the unit."],
              get = function() return mod.db.showRaidMarker end,
              set = function(_, v) mod.db.showRaidMarker = v; applyAndRefresh() end,
              subOptions = {
                  { type = "dropdown", label = L["Marker position"], width = 300, values = markerPosValues(),
                    get = function() return mod.db.raidMarkerPos end,
                    set = function(_, v) mod.db.raidMarkerPos = v; applyAndRefresh() end },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Marker size"], min = 8, max = 48, step = 1, width = SLW,
                        get = function() return mod.db.raidMarkerSize end,
                        set = function(_, v) mod.db.raidMarkerSize = v; applyAndRefresh() end },
                      { type = "slider", label = L["Marker offset X"], min = -40, max = 40, step = 1, width = SLW,
                        get = function() return mod.db.raidMarkerX end,
                        set = function(_, v) mod.db.raidMarkerX = v; applyAndRefresh() end },
                  } },
                  { type = "slider", label = L["Marker offset Y"], min = -40, max = 40, step = 1, width = SLW,
                    get = function() return mod.db.raidMarkerY end,
                    set = function(_, v) mod.db.raidMarkerY = v; applyAndRefresh() end },
              } },
        } },

        { type = "section", title = L["Combo Points"], items = {
            { type = "checkbox", label = L["Show combo points"],
              tooltip = L["Shows your combo points on the target's nameplate (Rogue, or Druid in cat form)."],
              get = function() return mod.db.showClassPower end,
              set = function(_, v) mod.db.showClassPower = v; applyAndRefresh() end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Pip size"], min = 4, max = 20, step = 1, width = SLW,
                        get = function() return mod.db.cpSize end,
                        set = function(_, v) mod.db.cpSize = v; applyAndRefresh() end },
                      { type = "slider", label = L["Pip spacing"], min = 0, max = 12, step = 1, width = SLW,
                        get = function() return mod.db.cpSpacing end,
                        set = function(_, v) mod.db.cpSpacing = v; applyAndRefresh() end },
                  } },
                  { type = "color", label = L["Point colour"], width = 200,
                    get = function() return mod.db.cpColor end,
                    set = function(r, g, b) mod.db.cpColor = { r = r, g = g, b = b }; applyAndRefresh() end },
                  -- Menu, not a button row: four shapes is already the ceiling
                  -- for a strip, and this list is ours to extend -- a star or a
                  -- hexagon would break it. Same call as the two bar styles.
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
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Offset X"], min = -60, max = 60, step = 1, width = SLW,
                        get = function() return mod.db.cpOffsetX or 0 end,
                        set = function(_, v) mod.db.cpOffsetX = v; applyAndRefresh() end },
                      { type = "slider", label = L["Offset Y"], min = -40, max = 40, step = 1, width = SLW,
                        get = function() return mod.db.cpOffsetY or 0 end,
                        set = function(_, v) mod.db.cpOffsetY = v; applyAndRefresh() end },
                  } },
              } },
        } },

        { type = "section", title = L["Behaviour"], items = {
            { type = "desc",
              text = L["|cffaaaaaaThese are the game's own nameplate settings, changed live (not part of the profile). Not changeable in combat.|r"] },
            { type = "segmented", label = L["Plate motion"], width = 260,
              values = {
                  { value = "0", text = L["Overlapping"] },
                  { value = "1", text = L["Stacking"] },
              },
              get = function() return GetCVar and tostring(GetCVar("nameplateMotion")) or "0" end,
              set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateMotion", v) end end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Stacked spacing"], min = 4, max = 20, step = 1, width = SLW,
                  tooltip = L["Vertical distance between stacked plates (a tenth of the game value)."],
                  get = function() return floor((tonumber(GetCVar and GetCVar("nameplateOverlapV")) or 1.1) * 10 + 0.5) end,
                  set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateOverlapV", v / 10) end end },
                { type = "slider", label = L["Line-of-sight opacity"], min = 0, max = 100, step = 5, width = SLW,
                  tooltip = L["Opacity of plates whose unit is out of your line of sight."],
                  get = function() return floor((tonumber(GetCVar and GetCVar("nameplateOccludedAlphaMult")) or 0.4) * 100 + 0.5) end,
                  set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateOccludedAlphaMult", v / 100) end end },
            } },
            { type = "slider", label = L["Plate view distance"], min = 20, max = 60, step = 1,
              get = function() return floor(tonumber(GetCVar and GetCVar("nameplateMaxDistance")) or 41) end,
              set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "nameplateMaxDistance", v) end end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Hitbox width"], min = 0, max = 200, step = 5, width = SLW,
                  tooltip = L["Clickable plate area (0 = the game's default). Stored in the profile."],
                  get = function() return mod.db.hitboxW or 0 end,
                  set = function(_, v) mod.db.hitboxW = v; applyHitbox() end },
                { type = "slider", label = L["Hitbox height"], min = 0, max = 100, step = 5, width = SLW,
                  get = function() return mod.db.hitboxH or 0 end,
                  set = function(_, v) mod.db.hitboxH = v; applyHitbox() end },
            } },
        } },
    }
end
