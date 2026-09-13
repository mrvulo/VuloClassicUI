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
    local v = {
        { value = "damage",     text = L["Damage"] },
        { value = "dps",        text = L["DPS"] },
        { value = "heal",       text = L["Healing"] },
        { value = "hps",        text = L["HPS"] },
        { value = "taken",      text = L["Damage taken"] },
        { value = "enemies",    text = L["Enemies"] },
        { value = "interrupts", text = L["Interrupts"] },
        { value = "dispels",    text = L["Dispels"] },
        { value = "deaths",     text = L["Deaths"] },
    }
    if ns.Meter and ns.Meter.HAS_THREAT then
        v[#v + 1] = { value = "threat", text = L["Threat"] }
    end
    return v
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

-- One row per window: mode, segment, and a close button once there is more
-- than one window to close. The window file re-syncs the frames on apply.
-- noOverride: the rows share their labels ("Segment" on every window) and the
-- list itself grows and shrinks, so a talent override could neither name one
-- window reliably nor survive a closed one.
-- While the module runs, the window actions do the work (they also clear a
-- fight picked from the title menu and arm the threat events); a re-sync of
-- every frame would keep such a pick and swallow the dropdown's choice.
local function setMode(i, w, v)
    w.mode = v
    if mod.active and mod.SetMode then mod:SetMode(i, v, true) else apply() end
end

local function setSegment(i, w, v)
    w.segment = v
    if mod.active and mod.SetSegment then mod:SetSegment(i, v, true) else apply() end
end

local function windowRow(i, w, closable)
    local items = {
        { type = "dropdown", label = string.format(L["Window %d"], i), width = 150,
          values = modeValues(), noOverride = true,
          get = function() return w.mode end,
          set = function(_, v) setMode(i, w, v) end },
        { type = "dropdown", label = L["Segment"], width = 150,
          values = segmentValues(), noOverride = true,
          get = function() return w.segment end,
          set = function(_, v) setSegment(i, w, v) end },
        -- Per window, through the mover's own scale: the edit-mode box and
        -- this slider write the same field.
        { type = "slider", label = L["Scale"], min = 0.5, max = 1.5, step = 0.05, noOverride = true,
          get = function() return w.scale or 1 end,
          set = function(_, v) w.scale = v; apply() end },
    }
    if closable then
        items[#items + 1] = { type = "button", width = 110, label = L["Close"],
            onClick = function()
                if mod.CloseWindow then mod:CloseWindow(i) end
            end }
    end
    return { type = "group", layout = "row", gap = 8, items = items }
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
    items[#items + 1] = { type = "slider", label = L["Abilities in tooltip"], min = 3, max = 10, step = 1,
        get = function() return mod.db.tooltipRows end,
        set = function(_, v) mod.db.tooltipRows = v end }
    items[#items + 1] = { type = "slider", label = L["Bar spacing"], min = 0, max = 6, step = 1,
        get = function() return mod.db.barGap end,
        set = function(_, v) mod.db.barGap = v; apply() end }
    items[#items + 1] = toggle(L["Show rank"], "showRank")
    items[#items + 1] = { type = "dropdown", label = L["Bar icon"], width = 200,
        tooltip = L["The spec is the tree a player has been seen to play: your own talents, a talent-only spell in the log, or an inspect in range. Until it is known the class icon stands in."],
        values = {
            { value = "off",   text = L["Off"] },
            { value = "class", text = L["Class"] },
            { value = "spec",  text = L["Spec"] },
        },
        get = function() return mod.db.barIcon end,
        set = function(_, v) mod.db.barIcon = v; apply() end }
    items[#items + 1] = { type = "dropdown", label = L["Bar colour"], width = 200,
        values = {
            { value = "class",  text = L["Class colour"] },
            { value = "custom", text = L["Custom colour"] },
        },
        get = function() return mod.db.barColorMode end,
        set = function(_, v) mod.db.barColorMode = v; apply() end,
        subOptions = {
            { type = "color", label = L["Custom colour"],
              get = function() return mod.db.barColor end,
              set = function(r, g, b) mod.db.barColor = { r = r, g = g, b = b }; apply() end },
        } }
    items[#items + 1] = { type = "color", label = L["Window background"],
        get = function() return mod.db.bgColor end,
        set = function(r, g, b) mod.db.bgColor = { r = r, g = g, b = b }; apply() end,
        subOptions = {
            { type = "slider", label = L["Background opacity"], min = 0, max = 100, step = 5,
              get = function() return mod.db.bgAlpha end,
              set = function(_, v) mod.db.bgAlpha = v; apply() end },
        } }
    items[#items + 1] = toggle(L["Bars grow upwards"], "growUp",
        L["The title bar moves to the bottom edge and the bars stack up from it."])
    items[#items + 1] = { type = "dropdown", label = L["Per-second basis"], width = 200,
        tooltip = L["Fight time divides by the whole fight. Active time divides by the seconds in which the player kept casting or hitting, so a late joiner or a paused healer is judged on their own time."],
        values = {
            { value = "fight",  text = L["Fight time"] },
            { value = "active", text = L["Active time"] },
        },
        get = function() return mod.db.dpsBasis end,
        set = function(_, v) mod.db.dpsBasis = v; apply() end }
    items[#items + 1] = toggle(L["Show value in brackets"], "showPerSecond",
        L["Per-second value next to the total. In the per-second modes the brackets show the total instead."])
    items[#items + 1] = toggle(L["Show percent"], "showPercent")
    items[#items + 1] = toggle(L["Highlight your own bar"], "highlightSelf")
    items[#items + 1] = toggle(L["Keep your own bar in view"], "pinSelf",
        L["When your own bar scrolls out of view it stays pinned at the top or bottom edge with its real rank."])

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Visibility"] }
    items[#items + 1] = toggle(L["Only in group"], "onlyInGroup")
    items[#items + 1] = toggle(L["Hide in arena and battlegrounds"], "hideInPvP")
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
    items[#items + 1] = { type = "header", text = L["Windows"] }
    local list = mod.db.windows or {}
    for i = 1, #list do
        items[#items + 1] = windowRow(i, list[i], #list > 1)
    end
    items[#items + 1] = {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", width = 180, label = L["New window"],
              onClick = function()
                  if mod.AddWindow then mod:AddWindow("damage", #list) end
              end },
        },
    }
    items[#items + 1] = toggle(L["Reset overall when joining a new group"], "resetOnNewGroup")
    items[#items + 1] = { type = "dropdown", label = L["Reset when entering an instance"], width = 200,
        tooltip = L["A new dungeon or raid resets the overall total: at once, after a question, or never. A reload inside the same instance never counts as entering it."],
        values = {
            { value = "never",  text = L["Never"] },
            { value = "ask",    text = L["Ask"] },
            { value = "always", text = L["Always"] },
        },
        get = function() return mod.db.resetOnInstance end,
        set = function(_, v) mod.db.resetOnInstance = v end }
    items[#items + 1] = toggle(L["Back to the current fight on pull"], "autoCurrent",
        L["A window showing a previous fight returns to the running fight when the next one starts."])
    items[#items + 1] = { type = "toggle", label = L["Mode follows your talents"],
        tooltip = L["The first window opens on healing while your talents make you a healer and on damage otherwise; it switches with your spec."],
        get = function() return mod.db.followRole end,
        set = function(_, v)
            mod.db.followRole = v
            if v and mod.ApplyRoleMode then mod.ApplyRoleMode() end
        end }
    items[#items + 1] = { type = "slider", label = L["Fights to keep"], min = 0, max = 30, step = 1,
        tooltip = L["Finished fights the title menu offers under Previous fights. They live until a reload; the overall total is what survives one."],
        get = function() return mod.db.historySize end,
        set = function(_, v) mod.db.historySize = v end }

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Report"] }
    items[#items + 1] = { type = "slider", label = L["Rows in report"], min = 3, max = 25, step = 1,
        tooltip = L["Lines below the header when a window is reported to a chat channel from its title menu."],
        get = function() return mod.db.reportRows end,
        set = function(_, v) mod.db.reportRows = v end }

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Position"] }
    items[#items + 1] = {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", width = 180,
              label = ns:IsMoverEditMode() and L["Stop moving"] or L["Unlock / Move"],
              onClick = function()
                  ns:SetMoversEditMode(not ns:IsMoverEditMode())
                  apply()
                  refreshPage()
              end },
            { type = "button", width = 150, label = L["Reset position"],
              onClick = function()
                  for i = 1, #list do
                      list[i].x, list[i].y = (i - 1) * 30, -(i - 1) * 30
                  end
                  apply()
              end },
        },
    }

    return items
end
