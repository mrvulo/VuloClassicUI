-- VuloClassicUI / Modules / TrackbarsOptions: the settings page of the data
-- bars. Same split as the action ring: the engine (Trackbars.lua) exposes what
-- this page may touch on mod.optionsBridge and never needs to change when the
-- page does. Loads after Trackbars.lua and TrackbarsBlocks.lua per the TOC.
local _, ns = ...
local L   = ns.L
local mod = ns.modules.trackbars

local br = mod.optionsBridge

-- Page state, not settings: which bar the sections below edit, the text in the
-- rename box, and which bar's Delete button is on its second (confirming) step.
local selectedBarId
local renameBuffer  = ""
local deleteArmedFor

local function refreshPage()
    if ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
end

-- Clamp like ActionRingOptions does: a deleted or never-chosen selection falls
-- back to the first bar instead of leaving the page editing nothing.
local function selectedBar()
    local cfg = selectedBarId and br.BarCfg(selectedBarId)
    if not cfg then
        cfg = mod.db.bars[1]
        selectedBarId = cfg and cfg.id or nil
    end
    return cfg
end

local function blockLabel(typeKey)
    for _, bt in ipairs(br.BLOCK_TYPES) do
        if bt.key == typeKey then return bt.label() end
    end
    return tostring(typeKey)
end

local function pickTemplate(anchor)
    local entries = {}
    for _, tpl in ipairs(br.TEMPLATES) do
        entries[#entries + 1] = { text = tpl.label(), func = function()
            local cfg = br.CreateBar(tpl.key)
            if cfg then selectedBarId = cfg.id end
            refreshPage()
        end }
    end
    ns:ShowPopupMenu(entries, anchor)
end

-------------------------------------------------------------------------------
--  Per-block section
-------------------------------------------------------------------------------

-- The micro menu's nine switches, in the order the strip draws them. Raw locale
-- keys; the toggles translate them when the row is built.
local MM_TOGGLES = {
    { key = "character", label = "Character" },
    { key = "spellbook", label = "Spellbook" },
    { key = "talents",   label = "Talents" },
    { key = "quests",    label = "Quest Log" },
    { key = "social",    label = "Social" },
    { key = "lfg",       label = "LFG" },
    { key = "map",       label = "World Map" },
    { key = "menu",      label = "Game Menu" },
    { key = "help",      label = "Help" },
}

-- Widgets every block type shares: side, gap, scale, text color, accent.
local function addCommonBlockItems(items, cfg, b)
    items[#items + 1] = {
        type = "dropdown", label = L["Side"], width = 240,
        values = {
            { value = "left",   text = "Left" },
            { value = "center", text = "Centered" },
            { value = "right",  text = "Right" },
        },
        get = function() return b.side or "left" end,
        set = function(_, v) b.side = v; br.RequestLayout(cfg.id) end,
    }
    items[#items + 1] = {
        type = "slider", label = L["Gap"], min = 0, max = 40, step = 1,
        get = function() return b.gap or 10 end,
        set = function(_, v) b.gap = v; br.RequestLayout(cfg.id) end,
    }
    items[#items + 1] = {
        type = "slider", label = L["Scale"], min = 50, max = 200, step = 5,
        get = function() return b.scale or 100 end,
        set = function(_, v) b.scale = v; br.ApplyBar(cfg.id) end,
    }
    items[#items + 1] = {
        type = "color", label = L["Text color"],
        get = function() return b.color or { r = 1, g = 1, b = 1 } end,
        set = function(r, g, bl)
            b.color = { r = r, g = g, b = bl }
            br.ApplyBar(cfg.id)
        end,
    }
    items[#items + 1] = {
        type = "toggle", label = L["Use accent color"],
        tooltip = L["Paints this block in the interface accent color instead of the color above."],
        get = function() return b.useAccent end,
        set = function(_, v) b.useAccent = v; br.ApplyBar(cfg.id) end,
    }
end

-- The settings widgets one block type has and another does not. Keys mirror
-- BLOCK_DEFAULTS exactly; types without settings (fps, durability, bags) add
-- nothing here.
local function addTypeBlockItems(items, cfg, b)
    local s = b.settings or {}
    local t = b.type
    if t == "clock" then
        items[#items + 1] = {
            type = "toggle", label = L["24-hour clock"],
            get = function() return s.hour24 end,
            set = function(_, v) s.hour24 = v; br.ApplyBar(cfg.id) end,
        }
        items[#items + 1] = {
            type = "dropdown", label = L["Source"], width = 240,
            values = {
                { value = "local",  text = "Local time" },
                { value = "server", text = "Server time" },
            },
            get = function() return s.source or "local" end,
            set = function(_, v) s.source = v; br.ApplyBar(cfg.id) end,
        }
    elseif t == "ms" then
        items[#items + 1] = {
            type = "toggle", label = L["Show world latency"],
            get = function() return s.world end,
            set = function(_, v) s.world = v; br.ApplyBar(cfg.id) end,
        }
    elseif t == "gold" then
        items[#items + 1] = {
            type = "toggle", label = L["Show free bag slots"],
            get = function() return s.showBagSlots end,
            set = function(_, v) s.showBagSlots = v; br.ApplyBar(cfg.id) end,
        }
        items[#items + 1] = {
            type = "toggle", label = L["Short format (gold only)"],
            get = function() return s.shorten end,
            set = function(_, v) s.shorten = v; br.ApplyBar(cfg.id) end,
        }
    elseif t == "zone" then
        items[#items + 1] = {
            type = "toggle", label = L["Show coordinates"],
            get = function() return s.showCoords end,
            set = function(_, v) s.showCoords = v; br.ApplyBar(cfg.id) end,
        }
    elseif t == "xprep" then
        items[#items + 1] = {
            type = "dropdown", label = L["Mode"], width = 240,
            values = {
                { value = "auto", text = "Automatic" },
                { value = "xp",   text = "XP" },
                { value = "rep",  text = "Reputation" },
            },
            get = function() return s.mode or "auto" end,
            set = function(_, v) s.mode = v; br.ApplyBar(cfg.id) end,
        }
    elseif t == "spacer" then
        items[#items + 1] = {
            type = "slider", label = L["Width"], min = 4, max = 200, step = 1,
            get = function() return s.width or 20 end,
            set = function(_, v) s.width = v; br.RequestLayout(cfg.id) end,
        }
    elseif t == "micromenu" then
        for row = 0, 2 do
            local group = { type = "group", layout = "row", gap = 8, items = {} }
            for col = 1, 3 do
                local def = MM_TOGGLES[row * 3 + col]
                if def then
                    group.items[#group.items + 1] = {
                        type = "toggle", label = L[def.label],
                        get = function() return s[def.key] end,
                        set = function(_, v) s[def.key] = v; br.ApplyBar(cfg.id) end,
                    }
                end
            end
            items[#items + 1] = group
        end
        items[#items + 1] = {
            type = "slider", label = L["Spacing"], min = 0, max = 10, step = 1,
            get = function() return s.spacing or 2 end,
            set = function(_, v) s.spacing = v; br.ApplyBar(cfg.id) end,
        }
    end
end

local function addBlockSection(items, cfg, b, index, count)
    items[#items + 1] = { type = "spacer", height = 4 }
    items[#items + 1] = { type = "header",
        text = string.format("%d. %s", index, blockLabel(b.type)) }
    items[#items + 1] = {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "iconbutton", icon = "up", tooltip = L["Move up"],
              onClick = function()
                  if index <= 1 then return end
                  br.MoveBlock(cfg.id, b.id, -1)
                  refreshPage()
              end },
            { type = "iconbutton", icon = "down", tooltip = L["Move down"],
              onClick = function()
                  if index >= count then return end
                  br.MoveBlock(cfg.id, b.id, 1)
                  refreshPage()
              end },
            { type = "button", label = L["Remove"], width = 110, danger = true,
              onClick = function()
                  br.RemoveBlock(cfg.id, b.id)
                  refreshPage()
              end },
        },
    }
    addCommonBlockItems(items, cfg, b)
    addTypeBlockItems(items, cfg, b)
end

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------

function mod:GetOptions()
    local items = {}

    items[#items + 1] = { type = "desc",
        text = L["|cffaaaaaaBuild your own info bars from blocks: clock, gold, XP, latency, micro menu and more. Create a bar from a template, then stack and order its blocks below.|r"] }
    items[#items + 1] = { type = "toggle", label = L["Enable Trackbars"],
        get = function() return ns:IsModuleEnabled("trackbars") end,
        set = function(_, v)
            if ns.ToggleModule then ns:ToggleModule("trackbars", v) end
            refreshPage()
        end }
    items[#items + 1] = { type = "spacer", height = 6 }

    -- No bars yet: the template picker IS the page. One button per template,
    -- its description in the hover tooltip.
    if #mod.db.bars == 0 then
        items[#items + 1] = { type = "header", text = L["Create your first bar"] }
        items[#items + 1] = { type = "desc",
            text = L["|cffaaaaaaPick a template to start with. Every bar stays fully editable afterwards.|r"] }
        for _, tpl in ipairs(br.TEMPLATES) do
            items[#items + 1] = {
                type = "button", label = tpl.label(), width = 260,
                tooltip = tpl.desc and tpl.desc() or nil,
                onClick = function()
                    local cfg = br.CreateBar(tpl.key)
                    if cfg then selectedBarId = cfg.id end
                    refreshPage()
                end,
            }
        end
        return items
    end

    local cfg = selectedBar()
    if not cfg then return items end

    -- ------------------------------------------------------------ bar picker
    local barValues = {}
    for _, c in ipairs(mod.db.bars) do
        barValues[#barValues + 1] = { value = c.id, text = c.name or tostring(c.id) }
    end
    items[#items + 1] = {
        type = "dropdown", label = L["Bar"], width = 280, values = barValues,
        get = function()
            local c = selectedBar()
            return c and c.id
        end,
        set = function(_, v)
            selectedBarId = v
            deleteArmedFor = nil
            renameBuffer = ""
            refreshPage()
        end,
    }
    items[#items + 1] = {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", label = L["New bar..."], width = 150,
              onClick = function(btn) pickTemplate(btn) end },
            -- Delete confirms in place: the first click arms the button and
            -- swaps its label, the second click deletes. No dialog needed.
            { type = "button", width = 150, danger = true,
              label = (deleteArmedFor == cfg.id) and L["Click again to delete"] or L["Delete..."],
              tooltip = L["Removes the selected bar and all of its blocks."],
              onClick = function()
                  if deleteArmedFor == cfg.id then
                      deleteArmedFor = nil
                      br.DeleteBar(cfg.id)
                      selectedBarId = nil
                  else
                      deleteArmedFor = cfg.id
                  end
                  refreshPage()
              end },
        },
    }
    items[#items + 1] = {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "editbox", label = L["Rename to"], width = 200,
              get = function() return renameBuffer end,
              set = function(_, v) renameBuffer = v end },
            { type = "button", label = L["Rename"], width = 110,
              onClick = function()
                  local name = (renameBuffer or ""):match("^%s*(.-)%s*$")
                  if not name or name == "" then return end
                  br.RenameBar(cfg.id, name)
                  renameBuffer = ""
                  refreshPage()
              end },
        },
    }

    -- ----------------------------------------------------------- bar settings
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Bar Settings"] }
    items[#items + 1] = {
        type = "dropdown", label = L["Length"], width = 240,
        values = {
            { value = "full",   text = "Full width" },
            { value = "custom", text = "Custom length" },
        },
        get = function() return cfg.lengthMode or "custom" end,
        set = function(_, v)
            cfg.lengthMode = v
            br.ApplyBar(cfg.id)
            refreshPage()   -- the rows below differ per mode
        end,
    }
    if cfg.lengthMode == "full" then
        items[#items + 1] = {
            type = "dropdown", label = L["Edge"], width = 240,
            values = {
                { value = "bottom", text = "Bottom" },
                { value = "top",    text = "Top" },
            },
            get = function() return cfg.edge or "bottom" end,
            set = function(_, v) cfg.edge = v; br.ApplyBar(cfg.id) end,
        }
        items[#items + 1] = {
            type = "slider", label = L["Edge offset"], min = 0, max = 500, step = 5,
            get = function() return cfg.edgeOffset or 0 end,
            set = function(_, v) cfg.edgeOffset = v; br.ApplyBar(cfg.id) end,
        }
    else
        items[#items + 1] = {
            type = "slider", label = L["Width"], min = 100, max = 2000, step = 10,
            get = function() return cfg.length or 400 end,
            set = function(_, v) cfg.length = v; br.ApplyBar(cfg.id) end,
        }
        items[#items + 1] = {
            type = "group", layout = "row", gap = 8,
            items = {
                { type = "button", width = 180,
                  label = ns:IsMoverEditMode() and L["Stop moving"] or L["Unlock / Move"],
                  tooltip = L["Shows the movers so free-standing bars can be dragged into place."],
                  onClick = function()
                      ns:SetMoversEditMode(not ns:IsMoverEditMode())
                      refreshPage()
                  end },
            },
        }
    end
    items[#items + 1] = {
        type = "slider", label = L["Height"], min = 16, max = 48, step = 1,
        get = function() return cfg.thickness or 26 end,
        set = function(_, v) cfg.thickness = v; br.RebuildBar(cfg.id) end,
    }
    items[#items + 1] = {
        type = "dropdown", label = L["Distribution"], width = 240,
        tooltip = L["Auto sizes each block by its content; even split gives every block the same share of the bar."],
        values = {
            { value = "auto", text = "Automatic" },
            { value = "even", text = "Even split" },
        },
        get = function() return cfg.sizingMode or "auto" end,
        set = function(_, v) cfg.sizingMode = v; br.RequestLayout(cfg.id) end,
    }
    items[#items + 1] = {
        type = "slider", label = L["Font scale"], min = 50, max = 150, step = 5,
        get = function() return cfg.fontScale or 100 end,
        set = function(_, v) cfg.fontScale = v; br.RebuildBar(cfg.id) end,
    }
    items[#items + 1] = {
        type = "toggle", label = L["Only on mouseover"],
        get = function() return cfg.mouseoverOnly end,
        set = function(_, v) cfg.mouseoverOnly = v; br.ApplyBar(cfg.id) end,
    }
    items[#items + 1] = {
        type = "color", label = L["Background"],
        get = function() return cfg.bg or { r = 0.05, g = 0.05, b = 0.06 } end,
        set = function(r, g, b)
            cfg.bg = cfg.bg or { a = 0.90 }
            cfg.bg.r, cfg.bg.g, cfg.bg.b = r, g, b
            br.ApplyBar(cfg.id)
        end,
    }
    -- The house color swatch is RGB only; the alpha channel gets its own
    -- slider. Same mapping the swing timer uses for this label: the value IS
    -- the alpha percentage (90 = solid-ish, 0 = invisible).
    items[#items + 1] = {
        type = "slider", label = L["Background transparency"], min = 0, max = 100, step = 5,
        get = function() return math.floor(((cfg.bg and cfg.bg.a) or 0.90) * 100 + 0.5) end,
        set = function(_, v)
            cfg.bg = cfg.bg or { r = 0.05, g = 0.05, b = 0.06 }
            cfg.bg.a = v / 100
            br.ApplyBar(cfg.id)
        end,
    }
    items[#items + 1] = {
        type = "toggle", label = L["Hide border"],
        get = function() return cfg.hideBorder end,
        set = function(_, v) cfg.hideBorder = v; br.ApplyBar(cfg.id) end,
    }

    -- ---------------------------------------------------------------- blocks
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Blocks"] }
    if #cfg.blocks == 0 then
        items[#items + 1] = { type = "desc",
            text = L["|cffaaaaaaThis bar has no blocks yet -- add one below.|r"] }
    end
    for i, b in ipairs(cfg.blocks) do
        addBlockSection(items, cfg, b, i, #cfg.blocks)
    end

    items[#items + 1] = { type = "spacer", height = 4 }
    items[#items + 1] = {
        type = "button", label = L["Add block..."], width = 200, primary = true,
        onClick = function(btn)
            local entries = {}
            for _, bt in ipairs(br.BLOCK_TYPES) do
                entries[#entries + 1] = { text = bt.label(), func = function()
                    br.AddBlock(cfg.id, bt.key)
                    refreshPage()
                end }
            end
            ns:ShowPopupMenu(entries, btn)
        end,
    }

    return items
end
