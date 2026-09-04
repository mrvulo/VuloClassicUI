-- VuloClassicUI / Modules / MeterOptions: options page for the combat meter.
-- The module description (rendered by the options builder) already carries
-- the usage hints, so the page starts with the enable switch.
local _, ns = ...
local L   = ns.L
local mod = ns.modules.meter

local function apply()
    if mod.ApplyWindow then mod:ApplyWindow() end
end

local function refreshPage()
    if ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
end

local function modeValues()
    return {
        { value = "damage", text = L["Damage"] },
        { value = "dps",    text = L["DPS"] },
        { value = "heal",   text = L["Healing"] },
        { value = "hps",    text = L["HPS"] },
    }
end

local function segmentValues()
    return {
        { value = "current", text = L["Current fight"] },
        { value = "overall", text = L["Overall"] },
    }
end

local function toggle(label, key, tooltip)
    return {
        type = "toggle", label = label, tooltip = tooltip,
        get = function() return mod.db[key] end,
        set = function(_, v) mod.db[key] = v; apply() end,
    }
end

function mod:GetOptions()
    local items = {}

    items[#items + 1] = { type = "toggle", label = L["Enable combat meter"],
        get = function() return ns:IsModuleEnabled("meter") end,
        set = function(_, v) ns:ToggleModule("meter", v) end }

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Display"] }
    items[#items + 1] = { type = "slider", label = L["Bar height"], min = 12, max = 30, step = 1,
        get = function() return mod.db.barHeight end,
        set = function(_, v) mod.db.barHeight = v; apply() end }
    items[#items + 1] = { type = "slider", label = L["Font size"], min = 8, max = 16, step = 1,
        get = function() return mod.db.fontSize end,
        set = function(_, v) mod.db.fontSize = v; apply() end }
    items[#items + 1] = { type = "dropdown", label = L["Texture"], width = 240,
        values = ns.MediaStatusbarValues(),
        get = function() return mod.db.texture end,
        set = function(_, v) mod.db.texture = v; apply() end }
    items[#items + 1] = { type = "slider", label = L["Scale"], min = 50, max = 200, step = 5,
        get = function() return math.floor((mod.db.scale or 1) * 100 + 0.5) end,
        set = function(_, v) mod.db.scale = v / 100; apply() end }
    items[#items + 1] = toggle(L["Show rank"], "showRank")
    items[#items + 1] = toggle(L["Show value in brackets"], "showPerSecond",
        L["Per-second value next to the total. In the per-second modes the brackets show the total instead."])
    items[#items + 1] = toggle(L["Show percent"], "showPercent")
    items[#items + 1] = toggle(L["Highlight your own bar"], "highlightSelf")

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Visibility"] }
    items[#items + 1] = toggle(L["Only in group"], "onlyInGroup")
    items[#items + 1] = toggle(L["Hide in combat"], "hideInCombat")
    items[#items + 1] = {
        type = "toggle", label = L["Hide out of combat"],
        get = function() return mod.db.hideOutOfCombat end,
        set = function(_, v) mod.db.hideOutOfCombat = v; apply() end,
        subOptions = {
            { type = "slider", label = L["Hide delay (seconds)"], min = 0, max = 60, step = 1,
              get = function() return mod.db.hideDelay end,
              set = function(_, v) mod.db.hideDelay = v; apply() end },
        },
    }

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Behavior"] }
    items[#items + 1] = { type = "dropdown", label = L["Default mode"], width = 200,
        values = modeValues(),
        get = function() return mod.db.defaultMode end,
        set = function(_, v) mod.db.defaultMode = v end }
    items[#items + 1] = { type = "dropdown", label = L["Default segment"], width = 200,
        values = segmentValues(),
        get = function() return mod.db.defaultSegment end,
        set = function(_, v) mod.db.defaultSegment = v end }
    items[#items + 1] = toggle(L["Reset overall when joining a new group"], "resetOnNewGroup")

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Position"] }
    items[#items + 1] = {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", width = 180,
              label = ns:IsMoverEditMode() and L["Stop moving"] or L["Unlock / Move"],
              onClick = function()
                  ns:SetMoversEditMode(not ns:IsMoverEditMode())
                  refreshPage()
              end },
            { type = "button", width = 150, label = L["Reset position"],
              onClick = function()
                  mod.db.x, mod.db.y = 0, 0
                  apply()
              end },
        },
    }

    return items
end
