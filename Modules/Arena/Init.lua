-- =========================================================
-- VuloClassicUI / Modules / Arena / Init
-- Registers the ArenaFrames module and provides shared helpers.
-- Submodules (Core, Layout, ClassColor, Trinket, DR, Castbar) extend mod.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("arenaframes", {
    name        = L["Arena Frames"],
    group       = "PvP",
    description = L["Enhances the Arena enemy frames: move/scale, class colors, class icons, PvP trinket CD, DR tracking, castbar, drag&drop layout."],
    defaults = {
        -- Core (Position/Scale/Fonts)
        pos        = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
        scale      = 1.0,
        healthSize = 10,
        powerSize  = 10,

        -- Layout (drag&drop)
        slotOrder        = { 1, 2, 3, 4, 5 },  -- default order
        slotSpacing      = 6,                  -- pixels between frames
        growDirection    = "down",             -- "up" | "down"
        slotOffsets      = {},                 -- per slot { x, y } for free positioning

        -- ClassColor
        classColorHealth  = true,
        classColorName    = true,
        classIconPortrait = true,

        -- Trinket
        trinketEnabled   = true,
        trinketSize      = 28,
        trinketAnchor    = "LEFT",   -- LEFT | RIGHT
        trinketOffsetX   = -6,
        trinketOffsetY   = 0,

        -- DR (coming later)
        drEnabled   = false,
        drSize      = 24,

        -- Castbar (coming later)
        castbarEnabled = false,
        castbarWidth   = 120,
        castbarHeight  = 14,
    },
})

ns.ArenaModule = mod

-- =========================================================
-- Shared helpers for submodules
-- =========================================================
mod.helpers = {}
local H = mod.helpers

function H.GetOwner() return _G["ArenaEnemyFrames"] end

function H.ForEach(fn)
    for i = 1, 5 do
        local f = _G["ArenaEnemyFrame" .. i]
        if f then fn(f, i) end
    end
end

function H.GetUnit(i)
    return "arena" .. i
end

function H.GetArenaBars(frame)
    local health = frame.healthbar or frame.HealthBar or _G[frame:GetName() .. "HealthBar"]
    local power  = frame.manabar   or frame.ManaBar   or frame.powerbar or frame.PowerBar
                or _G[frame:GetName() .. "ManaBar"]   or _G[frame:GetName() .. "PowerBar"]
    return health, power
end

function H.GetPortrait(frame)
    return frame.portrait or _G[frame:GetName() .. "Portrait"]
end

function H.GetNameText(frame)
    return frame.name or _G[frame:GetName() .. "Name"]
end

-- Stores a list of "OnArenaFrameReady" handlers per submodule
mod._readyHandlers = {}
function mod:OnArenaFramesReady(handler)
    table.insert(self._readyHandlers, handler)
end

function mod:_triggerReady()
    H.ForEach(function(frame, i)
        for _, handler in ipairs(self._readyHandlers) do
            local ok, err = pcall(handler, frame, i)
            if not ok then
                ns:Print(L["|cffff5555ArenaFrames submodule error:|r %s"], tostring(err))
            end
        end
    end)
end

-- Called by Core.lua once the frames are guaranteed to exist
function mod:RefreshAll()
    -- Ensure Blizzard_ArenaUI is loaded
    if UIParentLoadAddOn and IsAddOnLoaded and not IsAddOnLoaded("Blizzard_ArenaUI") then
        UIParentLoadAddOn("Blizzard_ArenaUI")
    end
    if not H.GetOwner() then return false end
    self:_triggerReady()
    return true
end

-- =========================================================
-- Lifecycle: each submodule can register for OnEnable
-- =========================================================
mod._onEnableHandlers = {}
function mod:RegisterOnEnable(handler)
    table.insert(self._onEnableHandlers, handler)
end

function mod:OnEnable()
    -- Core's OnEnable (Position/Scale/Fonts + frame hooks)
    if self.OnEnableCore then self:OnEnableCore() end
    -- Submodules
    for _, h in ipairs(self._onEnableHandlers) do
        local ok, err = pcall(h, self)
        if not ok then
            ns:Print(L["|cffff5555Arena submodule OnEnable error:|r %s"], tostring(err))
        end
    end
end

-- =========================================================
-- Options aggregation: each submodule provides its options section,
-- each section becomes its own tab.
-- =========================================================
mod._optionsBuilders = {}

-- name -> tab label mapping
local SECTION_LABELS = {
    core       = L["General"],
    layout     = L["Layout"],
    classcolor = L["Class Color"],
    trinket    = L["PvP Trinket"],
    dr         = L["DR Tracker"],
    castbar    = L["Castbar"],
}

function mod:AddOptionsSection(name, builder)
    table.insert(self._optionsBuilders, { name = name, fn = builder })
end

-- Called after file load so tabs end up in the correct order
local function buildTabsArray()
    local tabs = {}
    for _, sec in ipairs(mod._optionsBuilders) do
        table.insert(tabs, {
            id    = sec.name,
            label = SECTION_LABELS[sec.name] or sec.name,
        })
    end
    return tabs
end

-- mod.tabs can only be populated after all AddOptionsSection calls.
-- Hence lazy eval when opening the page (see MainFrame BuildTabsForModule).
-- We set mod.tabs once at PLAYER_LOGIN after all submodule files are loaded.
local tabsInitFrame = CreateFrame("Frame")
tabsInitFrame:RegisterEvent("PLAYER_LOGIN")
tabsInitFrame:SetScript("OnEvent", function()
    mod.tabs = buildTabsArray()
end)

function mod:GetOptions(tabId)
    -- If a tab is requested: only items from that one section
    if tabId and tabId ~= "default" then
        for _, sec in ipairs(self._optionsBuilders) do
            if sec.name == tabId then
                return sec.fn(self) or {}
            end
        end
        return {}
    end

    -- Fallback (no tabs defined): all in sequence
    local items = {}
    for _, sec in ipairs(self._optionsBuilders) do
        local subItems = sec.fn(self)
        if subItems then
            for _, it in ipairs(subItems) do
                table.insert(items, it)
            end
            table.insert(items, { type = "spacer", height = 8 })
        end
    end
    return items
end
