-- VuloClassicUI / Modules / ClassTools: the "Class Specific" page.
--
-- This file is the HOST, not a class file -- that is why it sits in Modules/
-- and not in Modules/Classes/. It has to load before them: every file in
-- Modules/Classes/ reaches for ns.modules.vtmanadisplay and registers into one
-- of the two tables below, and a class file that loaded first would find
-- nothing and silently return.
--
--   RegisterClassTool(class, {onEnable, onDisable, getOptions})
--       a full feature owning its own frames -- Shaman totem bar, Paladin seal
--       twist. See Modules/Classes/Shaman.lua for the shape.
--   RegisterDotSet(class, dots, meta)
--       data only; the generic DoT tracker does the work. See
--       Modules/Classes/Priest.lua and Warlock.lua.
--
-- The host owns registration, tabs, saved settings and options dispatch, and
-- nothing else. The two on-screen trackers -- the Vampiric Touch mana counter
-- and the DoT tracker, which share one combat log handler -- live in
-- Modules/ClassTrackers.lua and hang themselves on mod.trackers.
--
-- The module key stays "vtmanadisplay" although the file no longer is: the key
-- is written into saved profiles and referenced from UI/Sidebar.lua and
-- UI/Pages.lua, so renaming it would need a settings migration for no gain.
--
-- The wrapping IIFE is not decoration -- it gives the file its own 200-local
-- budget under Lua 5.1.
(function(...)
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("vtmanadisplay", {
    name        = "Class Specific",
    -- Its own row, not a tab of the Character container: this module already
    -- uses the tab column for its nine class tabs, and a container tab cannot
    -- carry tabs of its own.
    group       = "Tools",
    description = "Class-specific tools, grouped by class: the Priest Vampiric Touch mana tracker, DoT trackers, the Shaman totem bar and the Paladin seal twist helper.",
    defaults    = {
        enabled    = true,
        showFrame  = true,
        showInChat = false,
        x          = 0,
        y          = -220,
        fontSize   = 14,
        unlocked   = false,
        dots = {
            layout      = "bars",   -- "bars" | "icons"
            showSWP     = true,
            showVT      = true,
            showDP      = false,
            showCorruption = true,
            showCoA        = true,
            showUA         = true,
            showSiphon     = true,
            showImmolate   = true,
            showCoDoom     = false,
            warnSeconds = 3,
            colorText   = true,
            showGain    = true,
            barWidth    = 150,
            barHeight   = 18,
            iconSize    = 32,
            spacing     = 3,
            fontSize    = 12,
            x           = 250,
            y           = 0,
            unlocked    = false,
        },
    },
})

-- ONLY the played class gets a tab (user request, 31.07.2026): the other
-- classes' settings were editable but wrote into THIS character's profile,
-- where the foreign class never reads them -- misleading rather than useful.
-- Filtering the tab list also keeps the foreign rows out of the settings
-- search, which indexes exactly these tabs.
local _, PLAYER_CLASS = UnitClass("player")

-- Real class icon rather than a fallback cog. It comes from Blizzard's own
-- atlas, so nothing ships and no client restart is needed.
mod.tabs = {}
for _, t in ipairs({
    { id = "priest",  label = "Priest"  },
    { id = "druid",   label = "Druid"   },
    { id = "hunter",  label = "Hunter"  },
    { id = "mage",    label = "Mage"    },
    { id = "paladin", label = "Paladin" },
    { id = "rogue",   label = "Rogue"   },
    { id = "shaman",  label = "Shaman"  },
    { id = "warlock", label = "Warlock" },
    { id = "warrior", label = "Warrior" },
}) do
    if t.id:upper() == PLAYER_CLASS then
        local tex, coords = ns:GetClassIcon(t.id)
        if tex then t.icon, t.iconCoords = tex, coords end
        mod.tabs[#mod.tabs + 1] = t
    end
end

-- classToken -> { onEnable, onDisable, getOptions }, registered by class files.
mod.classTools = {}
function mod:RegisterClassTool(classToken, def)
    self.classTools[classToken] = def
end

-- Both registries are fields on mod rather than file locals: the tracker file
-- reads mod.dotSets, and it cannot see a local in here.
mod.dotSets    = {}   -- classToken -> { dot defs }
mod.dotSetMeta = {}

function mod:RegisterDotSet(classToken, dots, meta)
    self.dotSets[classToken] = dots
    if meta then self.dotSetMeta[classToken] = meta end
end

function mod:OnEnable()
    -- Both frames have their own saved unlock, and neither setUnlocked runs on
    -- load - so a leftover flag pins the frame on screen with no mover to grab.
    if mod.db then
        mod.db.unlocked = false
        if mod.db.dots then mod.db.dots.unlocked = false end
    end

    -- Migration from the old "vampirictouchmana" module
    if ns.db and ns.db.profile and ns.db.profile.modules then
        local old = ns.db.profile.modules.vampirictouchmana
        if old then
            for k, v in pairs(old) do
                if mod.db[k] == nil or k == "x" or k == "y" then
                    mod.db[k] = v
                end
            end
            ns.db.profile.modules.vampirictouchmana = nil
        end
    end

    local _, class = UnitClass("player")
    local tool = mod.classTools and mod.classTools[class]
    if tool and tool.onEnable then
        local ok, err = pcall(tool.onEnable)
        if not ok then ns:Print(L["|cffff5555Class tool error:|r %s"], tostring(err)) end
    end

    mod.trackers.Enable(class)
end

function mod:OnDisable()
    mod.trackers.Disable()

    local _, class = UnitClass("player")
    local tool = mod.classTools and mod.classTools[class]
    if tool and tool.onDisable then pcall(tool.onDisable) end
end

local TAB_LABEL = {}
for _, t in ipairs(mod.tabs) do TAB_LABEL[t.id] = t.label end

function mod:GetOptions(tabId)
    -- EVERY request resolves to the played class -- nil/default from a fresh
    -- page open, and stale tab ids saved while playing another character.
    -- With the tab list above this is what makes foreign class settings
    -- unreachable rather than merely hidden.
    tabId = PLAYER_CLASS:lower()

    if tabId == "priest" then
        return mod.trackers.PriestOptions()
    end

    local classToken = tabId:upper()

    local tool = self.classTools and self.classTools[classToken]
    if tool and tool.getOptions then
        return tool.getOptions()
    end

    if self.dotSets[classToken] then
        local label = TAB_LABEL[tabId] or classToken
        local items = { { type = "header", text = L[label] or label } }
        local meta = self.dotSetMeta[classToken]
        if meta and meta.desc then
            -- meta.desc is the ENGLISH text, i.e. the locale key -- translated
            -- here rather than by the registering file. A class file that wrote
            -- L[...] at its own file scope would resolve before the saved
            -- language override is read and bake in the client language.
            table.insert(items, { type = "desc", text = L[meta.desc] })
        end
        mod.trackers.AppendDotOptions(items, classToken)
        return items
    end

    return {
        { type = "header", text = L["No tools yet"] },
        { type = "desc", text = L["|cffaaaaaaNo class-specific tools for this class yet. Got an idea? Let me know!|r"] },
    }
end

end)(...);
