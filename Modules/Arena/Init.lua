-- =========================================================
-- VuloClassicUI / Modules / Arena / Init
-- Registriert das ArenaFrames Modul und stellt gemeinsame Helpers bereit.
-- Submodule (Core, Layout, ClassColor, Trinket, DR, Castbar) erweitern mod.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("arenaframes", {
    name        = "Arena Frames",
    group       = "PvP",
    description = "Erweitert die Arena-Enemy-Frames: verschieben/skalieren, Klassen-Farben, Class-Icons, PvP-Trinket-CD, DR-Tracking, Castbar, drag&drop Layout.",
    defaults = {
        -- Core (Position/Scale/Fonts)
        pos        = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
        scale      = 1.0,
        healthSize = 10,
        powerSize  = 10,

        -- Layout (drag&drop)
        slotOrder        = { 1, 2, 3, 4, 5 },  -- default reihenfolge
        slotSpacing      = 6,                  -- pixel zwischen frames
        growDirection    = "down",             -- "up" | "down"
        slotOffsets      = {},                 -- pro slot { x, y } für freies positionieren

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

        -- DR (kommt später)
        drEnabled   = false,
        drSize      = 24,

        -- Castbar (kommt später)
        castbarEnabled = false,
        castbarWidth   = 120,
        castbarHeight  = 14,
    },
})

ns.ArenaModule = mod

-- =========================================================
-- Gemeinsame Helpers für Submodule
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

-- Speichert pro Submodul eine Liste von "OnArenaFrameReady" Handlern
mod._readyHandlers = {}
function mod:OnArenaFramesReady(handler)
    table.insert(self._readyHandlers, handler)
end

function mod:_triggerReady()
    H.ForEach(function(frame, i)
        for _, handler in ipairs(self._readyHandlers) do
            local ok, err = pcall(handler, frame, i)
            if not ok then
                ns:Print("|cffff5555ArenaFrames-Submodul Fehler:|r %s", tostring(err))
            end
        end
    end)
end

-- Wird von Core.lua aufgerufen sobald die Frames sicher existieren
function mod:RefreshAll()
    -- Stellt sicher dass Blizzard_ArenaUI geladen ist
    if UIParentLoadAddOn and IsAddOnLoaded and not IsAddOnLoaded("Blizzard_ArenaUI") then
        UIParentLoadAddOn("Blizzard_ArenaUI")
    end
    if not H.GetOwner() then return false end
    self:_triggerReady()
    return true
end

-- =========================================================
-- Lifecycle: jedes Submodul kann sich für OnEnable registrieren
-- =========================================================
mod._onEnableHandlers = {}
function mod:RegisterOnEnable(handler)
    table.insert(self._onEnableHandlers, handler)
end

function mod:OnEnable()
    -- Core's OnEnable (Position/Scale/Fonts + Frame-Hooks)
    if self.OnEnableCore then self:OnEnableCore() end
    -- Submodule
    for _, h in ipairs(self._onEnableHandlers) do
        local ok, err = pcall(h, self)
        if not ok then
            ns:Print("|cffff5555Arena-Submodul OnEnable Fehler:|r %s", tostring(err))
        end
    end
end

-- =========================================================
-- Options-Aggregation: jedes Submodul liefert seine Optionen-Section,
-- jede Section wird ein eigener Tab.
-- =========================================================
mod._optionsBuilders = {}

-- name → Tab-Label-Mapping
local SECTION_LABELS = {
    core       = "General",
    layout     = "Layout",
    classcolor = "Class Color",
    trinket    = "PvP Trinket",
    dr         = "DR Tracker",
    castbar    = "Castbar",
}

function mod:AddOptionsSection(name, builder)
    table.insert(self._optionsBuilders, { name = name, fn = builder })
end

-- Wird nach Datei-Load aufgerufen damit Tabs in der richtigen Reihenfolge stehen
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

-- mod.tabs muss erst nach allen AddOptionsSection-Aufrufen befüllt werden.
-- Daher Lazy-Eval beim Öffnen der Page (siehe MainFrame BuildTabsForModule).
-- Wir setzen mod.tabs einmalig bei PLAYER_LOGIN nachdem alle Submodul-Dateien geladen sind.
local tabsInitFrame = CreateFrame("Frame")
tabsInitFrame:RegisterEvent("PLAYER_LOGIN")
tabsInitFrame:SetScript("OnEvent", function()
    mod.tabs = buildTabsArray()
end)

function mod:GetOptions(tabId)
    -- Wenn ein Tab angefragt ist: nur Items dieser einen Section
    if tabId and tabId ~= "default" then
        for _, sec in ipairs(self._optionsBuilders) do
            if sec.name == tabId then
                return sec.fn(self) or {}
            end
        end
        return {}
    end

    -- Fallback (kein Tab definiert): alle hintereinander
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
