-- =========================================================
-- VuloClassicUI / Modules / Arena (merged from Modules/Arena/*)
-- AUTO-MERGED file. Each former module is wrapped in an isolated
-- IIFE so its file-level locals and any top-level early-return stay
-- self-contained. Modules communicate through the shared ns table.
-- =========================================================

-- ============================================================
-- merged from: Arena/Init.lua
-- ============================================================
(function(...)
-- =========================================================
-- VuloClassicUI / Modules / Arena / Init
-- Registers the ArenaFrames module and provides shared helpers.
-- Submodules (Core, Layout, ClassColor, Trinket, DR, Castbar) extend mod.
-- =========================================================
local _, ns = ...
if ns.isEra then return end  -- Classic Era has no arenas; skip the whole module
local L = ns.L

local mod = ns:RegisterModule("arenaframes", {
    name        = "Arena Frames",
    group       = "PvP",
    description = "Enhances the Arena enemy frames: move/scale, class colors, class icons, PvP trinket CD, DR tracking, castbar, drag&drop layout.",
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

end)(...);

-- ============================================================
-- merged from: Arena/Core.lua
-- ============================================================
(function(...)
-- =========================================================
-- VuloClassicUI / Modules / Arena / Core
-- Position, scale, fonts, mover overlay, Ctrl+Shift+click to move.
-- =========================================================
local _, ns = ...
if ns.isEra then return end  -- Classic Era has no arenas; skip the whole module
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

local pendingApply = false
local unlocked = false
local hookedManage = false
local dragOverlay   -- invisible proxy frame; the unified mover box is its child

-- =========================================================
-- Unmanage + apply position/scale
-- =========================================================
local function unmanageOwner()
    if UIPARENT_MANAGED_FRAME_POSITIONS and UIPARENT_MANAGED_FRAME_POSITIONS["ArenaEnemyFrames"] then
        UIPARENT_MANAGED_FRAME_POSITIONS["ArenaEnemyFrames"] = nil
    end
end

local function applyToOwner()
    local owner = H.GetOwner()
    if not owner then return end
    if ns:InCombat() then pendingApply = true; return end

    local p = mod.db.pos
    unmanageOwner()
    owner:ClearAllPoints()
    owner:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    owner:SetScale(mod.db.scale or 1.0)

    -- If the drag overlay is visible, follow the new owner layout
    if dragOverlay and dragOverlay:IsShown() and mod.UpdateDragOverlay then
        mod:UpdateDragOverlay()
    end
end

mod.ApplyOwnerPosition = applyToOwner

-- =========================================================
-- Fonts
-- =========================================================
local function applyArenaFonts(frame)
    local health, power = H.GetArenaBars(frame)
    if health then
        ns:SetBarTextFontSize(health, mod.db.healthSize)
        if TextStatusBar_UpdateTextString then TextStatusBar_UpdateTextString(health) end
    end
    if power then
        ns:SetBarTextFontSize(power, mod.db.powerSize)
        if TextStatusBar_UpdateTextString then TextStatusBar_UpdateTextString(power) end
    end
end

local function applyAllFonts()
    H.ForEach(applyArenaFonts)
end

mod.ApplyFonts = applyAllFonts

-- =========================================================
-- Hook into TextStatusBar_UpdateTextString so our sizes don't get overwritten
-- =========================================================
local fontHooksInstalled = false
local function installFontHooks()
    if fontHooksInstalled or not hooksecurefunc or not TextStatusBar_UpdateTextString then return end
    fontHooksInstalled = true
    hooksecurefunc("TextStatusBar_UpdateTextString", function(bar)
        if not mod._enabled or not bar then return end
        for i = 1, 5 do
            local f = _G["ArenaEnemyFrame" .. i]
            if f then
                local hb, pb = H.GetArenaBars(f)
                if bar == hb then
                    ns:SetBarTextFontSize(bar, mod.db.healthSize)
                    return
                elseif bar == pb then
                    ns:SetBarTextFontSize(bar, mod.db.powerSize)
                    return
                end
            end
        end
    end)
end

-- =========================================================
-- Hook UIParent_ManageFramePositions so Blizzard doesn't snap back
-- =========================================================
local function hookManageFramePositions()
    if hookedManage or not hooksecurefunc then return end
    if not _G["UIParent_ManageFramePositions"] then return end
    hookedManage = true
    hooksecurefunc("UIParent_ManageFramePositions", function()
        if not mod._enabled or ns:InCombat() then return end
        applyToOwner()
    end)
end

-- =========================================================
-- Drag overlay (only visible in unlock mode)
-- Sits above the arena frames, catches mouse input and moves the container.
-- =========================================================
-- Drag overlay as a standalone mover.
-- The mover is its own frame with fixed size, sitting at the position of
-- the ArenaEnemyFrames. When dragging, we move the container along.
-- Also works when the test frames aren't fully positioned yet.
-- =========================================================
local MOVER_WIDTH  = 220
local MOVER_HEIGHT = 280

-- Custom positioner for the unified mover. The proxy overlay and the SECURE
-- ArenaEnemyFrames container are kept in lockstep (identical scale + identical
-- CENTER offset) so the real frames land exactly where the box is dropped — and
-- we never StartMoving the protected frames themselves (taint-free).
local function arenaApplyPos()
    if not dragOverlay then return end
    dragOverlay:SetScale(mod.db.scale or 1.0)
    dragOverlay:ClearAllPoints()
    dragOverlay:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
    mod.db.pos = mod.db.pos or {}
    mod.db.pos.point, mod.db.pos.relPoint = "CENTER", "CENTER"
    mod.db.pos.x, mod.db.pos.y = mod.db.x or 0, mod.db.y or 0
    applyToOwner()
end

local function arenaOnMove(x, y)
    mod.db.x, mod.db.y = x or 0, y or 0
    mod.db.pos = mod.db.pos or {}
    mod.db.pos.point, mod.db.pos.relPoint = "CENTER", "CENTER"
    mod.db.pos.x, mod.db.pos.y = mod.db.x, mod.db.y
    applyToOwner()
end

local function ensureDragOverlay()
    if dragOverlay then return dragOverlay end

    -- one-time migration of the legacy {point,relPoint,x,y} position into the
    -- engine's CENTER-offset model (x/y at the top level of mod.db)
    if mod.db.x == nil then
        mod.db.x = (mod.db.pos and mod.db.pos.x) or 0
        mod.db.y = (mod.db.pos and mod.db.pos.y) or 0
    end

    -- Invisible proxy frame. The unified mover box (created below) supplies the
    -- purple look, drag, left/right-click -> per-frame panel, arrow-key nudge,
    -- magnetism and the scale slider — consistent with every other window.
    dragOverlay = CreateFrame("Frame", "VCUIArenaDragOverlay", UIParent)
    dragOverlay:SetSize(MOVER_WIDTH, MOVER_HEIGHT)
    dragOverlay:SetFrameStrata("HIGH")
    dragOverlay:SetFrameLevel(100)
    dragOverlay:SetClampedToScreen(true)
    dragOverlay:Hide()

    mod._mover = ns:CreateMover(dragOverlay, {
        key      = "arenaframes",
        label    = L["|cffffffffARENA FRAMES|r"],
        db       = mod.db,                  -- x/y (migrated) + scale
        width    = MOVER_WIDTH, height = MOVER_HEIGHT,
        scalable = true,                    -- scale via the panel slider (0.5-2.0)
        applyPos = arenaApplyPos,
        onMove   = arenaOnMove,
        editPreview = function(show) if mod.SetUnlocked then mod.SetUnlocked(show) end end,
    })
    return dragOverlay
end

-- Set mover to the position of the ArenaEnemyFrames container (on show)
function mod:UpdateDragOverlay()
    if not dragOverlay then return end

    local p = mod.db.pos or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    dragOverlay:ClearAllPoints()
    dragOverlay:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    -- Match the owner's scale so dragging maps 1:1 (otherwise the frames land
    -- offset from where you dropped the mover).
    dragOverlay:SetScale(mod.db.scale or 1.0)
end

-- Driven by the unified Edit Mode via the mover's editPreview (/vedit). Shows
-- the test frames + the proxy overlay (whose child IS the purple mover box), and
-- toggles the BG unit watch so all slots are visible while configuring.
local function setUnlocked(state)
    unlocked = state and true or false
    if unlocked then
        if ns:InCombat() then
            ns:Print(L["Not possible in combat."])
            unlocked = false
            return
        end
        -- Ensure Blizzard_ArenaUI exists so there are frames to position
        if not H.GetOwner() then
            if UIParentLoadAddOn and IsAddOnLoaded and not IsAddOnLoaded("Blizzard_ArenaUI") then
                UIParentLoadAddOn("Blizzard_ArenaUI")
            end
        end
        mod:ShowTestFrames(true)

        ensureDragOverlay()
        mod:UpdateDragOverlay()
        dragOverlay:Show()
    else
        if dragOverlay then dragOverlay:Hide() end
        mod:ShowTestFrames(false)
    end
    -- Unlocking must release the BG unit watch (so all test frames show);
    -- locking re-applies it. Defined later -> reach it through mod.
    if mod.ApplyBGUnitWatch then mod.ApplyBGUnitWatch() end
end

mod.SetUnlocked = setUnlocked
mod.IsUnlocked  = function() return unlocked end

-- =========================================================
-- Show test frames (for configuration without arena)
-- Blizzard's ArenaEnemyFrame_SetMaxArenaPlayers + Show
-- =========================================================
local function showTestArenaFrames(show)
    H.ForEach(function(frame, i)
        if show then
            frame:Show()
            -- Without real unit data the frames show nothing. Set a dummy.
            if frame.healthbar then
                frame.healthbar:SetMinMaxValues(0, 100)
                frame.healthbar:SetValue(75)
            end
            if frame.manabar then
                frame.manabar:SetMinMaxValues(0, 100)
                frame.manabar:SetValue(50)
            end
            local nameText = H.GetNameText(frame)
            if nameText then nameText:SetText(L["ArenaPlayer"] .. i) end
        else
            -- Hide phantom test frames that have no real arena unit (e.g. in a
            -- battleground, or after closing the config outside an arena). Real
            -- arena frames (with a unit) are left for Blizzard to manage.
            if not (UnitExists and UnitExists("arena" .. i)) and not ns:InCombat() then
                frame:Hide()
            end
        end
    end)
    if not show then
        local owner = H.GetOwner()
        if owner and ArenaEnemyFrames_Update then
            -- Let Blizzard manage the frames normally again
            pcall(ArenaEnemyFrames_Update)
        end
    end
end

mod.ShowTestFrames = showTestArenaFrames

-- =========================================================
-- Battleground: show only frames that have a real enemy unit
-- (e.g. flag carriers); empty slots auto-hide. RegisterUnitWatch is
-- Blizzard's own secure show/hide-by-unit driver, so it works during
-- combat and doesn't taint the frame. Scoped to battlegrounds; arenas
-- keep Blizzard's default behaviour. Skipped while unlocked (config).
-- =========================================================
local bgWatchActive = false
local function applyBGUnitWatch()
    -- (Un)registering a unit watch is blocked while in combat.
    if InCombatLockdown and InCombatLockdown() then return end

    local inBG = false
    if IsInInstance then
        local _, instanceType = IsInInstance()
        inBG = (instanceType == "pvp")  -- "pvp" = battleground
    end

    local want = inBG and not unlocked
    if want == bgWatchActive then return end
    bgWatchActive = want

    H.ForEach(function(frame)
        if want then
            -- Blizzard already sets the secure "unit" attribute; only attach the
            -- watch. Never SetAttribute here -> that would taint the frame.
            if RegisterUnitWatch and frame:GetAttribute("unit") then
                pcall(RegisterUnitWatch, frame)
            end
        elseif UnregisterUnitWatch then
            pcall(UnregisterUnitWatch, frame)
        end
    end)
end
mod.ApplyBGUnitWatch = applyBGUnitWatch

-- =========================================================
-- Lifecycle (called from init)
-- =========================================================
function mod:OnEnableCore()
    installFontHooks()
    hookManageFramePositions()
    ensureDragOverlay()   -- register the unified mover so /vedit can drive it

    -- Notify submodules when frames are ready
    self:OnArenaFramesReady(function(frame, i)
        applyArenaFonts(frame)
    end)

    -- Events
    ns:RegisterEvent("PLAYER_LOGIN",          function() mod:Refresh() end)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() mod:Refresh() end)
    ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() mod:Refresh() end)
    ns:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_ArenaUI" then mod:Refresh() end
    end)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if pendingApply then pendingApply = false; mod:Refresh() end
        applyBGUnitWatch()  -- (re)apply now that combat ended (blocked in combat)
    end)

    self:Refresh()
end

function mod:Refresh()
    unmanageOwner()
    applyToOwner()
    if self:RefreshAll() then
        applyAllFonts()
    end

    -- Safety net: when not configuring (unlocked), never leave a frame showing
    -- without a real arena unit -> kills lingering test/phantom frames in BGs.
    if not unlocked and not ns:InCombat() then
        H.ForEach(function(frame, i)
            if not (UnitExists and UnitExists("arena" .. i)) then frame:Hide() end
        end)
    end

    -- Battlegrounds: only keep frames with a real enemy (e.g. flag carriers).
    applyBGUnitWatch()

    -- Sometimes the frames arrive delayed
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() applyToOwner() end)
        C_Timer.After(1, function() applyToOwner(); self:RefreshAll(); applyBGUnitWatch() end)
    end
end

-- =========================================================
-- Options section: position, scale, fonts
-- =========================================================
mod:AddOptionsSection("core", function()
    return {
        { type = "header", text = L["Position & Size"] },
        {
            type = "group", layout = "row", gap = 8,
            items = {
                { type = "button", label = L["Open Edit Mode"], width = 140,
                  onClick = function()
                      if ns.SetEditMode then ns:SetEditMode(not ns:IsEditModeActive())
                      else setUnlocked(not unlocked) end
                  end },
                { type = "button", label = L["Reset position"], width = 160,
                  onClick = function()
                      mod.db.pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
                      applyToOwner()
                      ns:Print(L["Position reset."])
                  end },
            },
        },
        { type = "desc", text = L["In unlock mode a purple overlay appears above the frames. Click + drag to move, mouse wheel to scale."] },
        {
            type = "slider", label = L["Scale"],
            min = 0.5, max = 2.0, step = 0.05,
            get = function() return mod.db.scale end,
            set = function(_, v) mod.db.scale = v; applyToOwner() end,
        },
        { type = "spacer", height = 6 },
        { type = "header", text = L["Font Sizes"] },
        {
            type = "slider", label = L["Health Bar Text"],
            min = 6, max = 20, step = 1,
            get = function() return mod.db.healthSize end,
            set = function(_, v) mod.db.healthSize = v; applyAllFonts() end,
        },
        {
            type = "slider", label = L["Power Bar Text"],
            min = 6, max = 20, step = 1,
            get = function() return mod.db.powerSize end,
            set = function(_, v) mod.db.powerSize = v; applyAllFonts() end,
        },
    }
end)

end)(...);

-- ============================================================
-- merged from: Arena/Layout.lua
-- ============================================================
(function(...)
-- =========================================================
-- VuloClassicUI / Modules / Arena / Layout
-- Drag & drop for the order of the arena frames.
-- Blizzard arranges them 1-5 stacked by default.
-- We override that with mod.db.slotOrder and mod.db.slotSpacing.
-- =========================================================
local _, ns = ...
if ns.isEra then return end  -- Classic Era has no arenas; skip the whole module
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

-- =========================================================
-- Apply layout
-- =========================================================
local function applyLayout()
    local owner = H.GetOwner()
    if not owner then return end
    -- ArenaEnemyFrames are secure frames; moving them in combat is blocked
    -- and taints them. Skip now and re-apply on PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then return end

    local order   = mod.db.slotOrder   or { 1, 2, 3, 4, 5 }
    local spacing = mod.db.slotSpacing or 6
    local grow    = mod.db.growDirection or "down"

    -- First frame relative to the container, all others relative to the previous
    local previous = nil
    for visualIndex, slotIndex in ipairs(order) do
        local frame = _G["ArenaEnemyFrame" .. slotIndex]
        if frame then
            frame:ClearAllPoints()
            local offsets = mod.db.slotOffsets and mod.db.slotOffsets[slotIndex] or { x = 0, y = 0 }

            if not previous then
                -- First visible frame on container
                local anchorPoint = (grow == "down") and "TOP" or "BOTTOM"
                frame:SetPoint(anchorPoint, owner, anchorPoint, offsets.x or 0, offsets.y or 0)
            else
                local thisAnchor   = (grow == "down") and "TOP"    or "BOTTOM"
                local prevAnchor   = (grow == "down") and "BOTTOM" or "TOP"
                local yDelta       = (grow == "down") and -spacing or  spacing
                frame:SetPoint(thisAnchor, previous, prevAnchor, offsets.x or 0, (offsets.y or 0) + yDelta)
            end
            previous = frame
        end
    end
end

mod.ApplyLayout = applyLayout

-- =========================================================
-- Hook into Blizzard's update so our layout takes effect after each refresh
-- =========================================================
local layoutHooked = false
local function hookLayout()
    if layoutHooked or not hooksecurefunc then return end
    layoutHooked = true

    -- ArenaEnemyFrames_UpdatePlayer is called per slot
    if _G.ArenaEnemyFrames_UpdatePlayer then
        hooksecurefunc("ArenaEnemyFrames_UpdatePlayer", function()
            if not mod._enabled then return end
            applyLayout()
        end)
    end
    -- General update
    if _G.ArenaEnemyFrames_Update then
        hooksecurefunc("ArenaEnemyFrames_Update", function()
            if not mod._enabled then return end
            applyLayout()
        end)
    end

    -- Re-apply once combat ends: frames that updated mid-combat were skipped
    -- by the InCombatLockdown guard in applyLayout.
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if mod._enabled then applyLayout() end
    end)
end

-- =========================================================
-- Layout editor: shows buttons in VCUI with up/down arrows to move single slots
-- =========================================================
local function moveSlot(slotIndex, direction)
    local order = mod.db.slotOrder
    local pos = nil
    for i, v in ipairs(order) do
        if v == slotIndex then pos = i; break end
    end
    if not pos then return end
    local newPos = pos + direction
    if newPos < 1 or newPos > #order then return end
    order[pos], order[newPos] = order[newPos], order[pos]
    applyLayout()
    -- Re-render page to show new order
    ns.UI:BuildOptionsPage("arenaframes")
end

-- =========================================================
-- Lifecycle
-- =========================================================
mod:OnArenaFramesReady(function(frame, i)
    -- Nothing to do per frame, we set layout for all at once
end)

-- Install hook (happens after init, when Blizzard_ArenaUI is loaded)
local layoutInitFrame = CreateFrame("Frame")
layoutInitFrame:RegisterEvent("ADDON_LOADED")
layoutInitFrame:RegisterEvent("PLAYER_LOGIN")
layoutInitFrame:SetScript("OnEvent", function(_, _, addonName)
    hookLayout()
    if mod._enabled then applyLayout() end
end)

-- =========================================================
-- Options section
-- =========================================================
mod:AddOptionsSection("layout", function()
    local items = {
        { type = "header", text = L["Layout (Order)"] },
        { type = "desc",   text = L["Order of the arena frames. Use up/down to move slots 1-5."] },
        { type = "spacer", height = 4 },
    }

    -- One row per slot: [Slot N] [up] [down]
    for visualIndex, slotIndex in ipairs(mod.db.slotOrder) do
        table.insert(items, {
            type = "group", layout = "row", gap = 4,
            items = {
                { type = "desc", text = string.format(L["|cff9b6cff%d.|r  Arena Slot %d"], visualIndex, slotIndex), width = 140 },
                { type = "iconbutton", icon = "up",   width = 28, height = 24,
                  tooltip = L["Move up"],
                  onClick = function() moveSlot(slotIndex, -1) end },
                { type = "iconbutton", icon = "down", width = 28, height = 24,
                  tooltip = L["Move down"],
                  onClick = function() moveSlot(slotIndex,  1) end },
            },
        })
    end

    table.insert(items, { type = "spacer", height = 4 })
    table.insert(items, {
        type = "slider", label = L["Spacing between frames"],
        min = 0, max = 40, step = 1,
        get = function() return mod.db.slotSpacing end,
        set = function(_, v) mod.db.slotSpacing = v; applyLayout() end,
    })
    table.insert(items, {
        type = "dropdown", label = L["Grow direction"],
        values = {
            { value = "down", text = L["Downward"] },
            { value = "up",   text = L["Upward"] },
        },
        get = function() return mod.db.growDirection end,
        set = function(_, v) mod.db.growDirection = v; applyLayout() end,
    })
    table.insert(items, {
        type = "button", label = L["Reset order"], width = 180,
        onClick = function()
            mod.db.slotOrder = { 1, 2, 3, 4, 5 }
            applyLayout()
            ns.UI:BuildOptionsPage("arenaframes")
        end,
    })

    return items
end)

end)(...);

-- ============================================================
-- merged from: Arena/ClassColor.lua
-- ============================================================
(function(...)
-- =========================================================
-- VuloClassicUI / Modules / Arena / ClassColor
-- Class-colored health bar, class icon instead of portrait, name in class color.
-- =========================================================
local _, ns = ...
if ns.isEra then return end  -- Classic Era has no arenas; skip the whole module
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

-- =========================================================
-- Class icon texture coords (Blizzard's UI-Charactercreate-Classes)
-- =========================================================
local CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS or {
    ["WARRIOR"]     = { 0,    0.25, 0,    0.25 },
    ["MAGE"]        = { 0.25, 0.49, 0,    0.25 },
    ["ROGUE"]       = { 0.49, 0.73, 0,    0.25 },
    ["DRUID"]       = { 0.73, 0.97, 0,    0.25 },
    ["HUNTER"]      = { 0,    0.25, 0.25, 0.5 },
    ["SHAMAN"]      = { 0.25, 0.49, 0.25, 0.5 },
    ["PRIEST"]      = { 0.49, 0.73, 0.25, 0.5 },
    ["WARLOCK"]     = { 0.73, 0.97, 0.25, 0.5 },
    ["PALADIN"]     = { 0,    0.25, 0.5,  0.75 },
    ["DEATHKNIGHT"] = { 0.25, 0.49, 0.5,  0.75 },
    ["MONK"]        = { 0.49, 0.73, 0.5,  0.75 },
    ["DEMONHUNTER"] = { 0.73, 0.97, 0.5,  0.75 },
}

-- This atlas is the one CLASS_ICON_TCOORDS is cut for (the WorldStateFrame
-- texture uses a different grid, which offset every class symbol).
local CLASS_ICON_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

-- =========================================================
-- Get class color
-- =========================================================
local function classColor(class)
    if not class then return nil end
    -- RAID_CLASS_COLORS is available in TBC 2.5.5
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- =========================================================
-- Apply per frame
-- =========================================================
local applyClassToFrame  -- forward declaration

local function applyToFrame(frame, i)
    local unit = H.GetUnit(i)
    if not UnitExists(unit) then
        -- Test mode: use any class as demo, otherwise nothing
        if mod:IsUnlocked() then
            local demoClasses = { "WARRIOR", "MAGE", "ROGUE", "DRUID", "PRIEST" }
            local demo = demoClasses[i] or "WARRIOR"
            applyClassToFrame(frame, demo)
        end
        return
    end

    local _, class = UnitClass(unit)
    applyClassToFrame(frame, class)
end

applyClassToFrame = function(frame, class)  -- the forward-declared local
    if not class then return end
    local r, g, b = classColor(class)

    -- Color health bar
    if mod.db.classColorHealth then
        local health = H.GetArenaBars(frame)
        if health then
            health:SetStatusBarColor(r, g, b)
            -- Prevent Blizzard from re-coloring
            if health.SetForceStatusColor then health:SetForceStatusColor(r, g, b) end
        end
    end

    -- Color name
    if mod.db.classColorName then
        local nameText = H.GetNameText(frame)
        if nameText then nameText:SetTextColor(r, g, b) end
    end

    -- Class icon instead of portrait
    if mod.db.classIconPortrait then
        local portrait = H.GetPortrait(frame)
        if portrait then
            portrait:SetTexture(CLASS_ICON_TEXTURE)
            local coords = CLASS_ICON_TCOORDS[class]
            if coords then
                portrait:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
            if portrait.SetVertexColor then portrait:SetVertexColor(1, 1, 1) end
        end
    end
end

-- When settings are turned off -> restore original values
local function restoreFrame(frame, i)
    local unit = H.GetUnit(i)
    local health = H.GetArenaBars(frame)
    if health then
        -- Standard power type color (for health: generic green, Blizzard's default)
        health:SetStatusBarColor(0, 1, 0)
    end
    local nameText = H.GetNameText(frame)
    if nameText then nameText:SetTextColor(1, 0.82, 0) end

    -- Portrait: if unit exists, let Blizzard regenerate it
    local portrait = H.GetPortrait(frame)
    if portrait and UnitExists(unit) and SetPortraitTexture then
        portrait:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(portrait, unit)
    end
end

local function applyAll()
    H.ForEach(applyToFrame)
end

local function restoreAll()
    H.ForEach(restoreFrame)
end

mod.ApplyClassColors   = applyAll
mod.RestoreClassColors = restoreAll

-- =========================================================
-- Hooks + events
-- =========================================================
mod:OnArenaFramesReady(function(frame, i)
    applyToFrame(frame, i)
end)

-- Blizzard rewrites bar color in TextStatusBar_UpdateTextString and Update.
-- We hook the most important update paths.
local classColorHooked = false
local function installHooks()
    if classColorHooked or not hooksecurefunc then return end
    classColorHooked = true

    if _G.ArenaEnemyFrames_UpdatePlayer then
        hooksecurefunc("ArenaEnemyFrames_UpdatePlayer", function()
            if not mod._enabled then return end
            applyAll()
        end)
    end
    if _G.UnitFrame_OnEvent then
        -- Risky hook; not needed if _UpdatePlayer is enough
    end
end

-- UNIT_PORTRAIT_UPDATE / PORTRAITS_UPDATED fire when Blizzard redraws the portrait
ns:RegisterEvent("UNIT_PORTRAIT_UPDATE", function(_, unit)
    if not mod._enabled then return end
    if unit and unit:match("^arena[1-5]$") then
        local i = tonumber(unit:match("arena(%d)"))
        local frame = _G["ArenaEnemyFrame" .. i]
        if frame then applyToFrame(frame, i) end
    end
end)

ns:RegisterEvent("ARENA_OPPONENT_UPDATE", function()
    if not mod._enabled then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, applyAll)
    else
        applyAll()
    end
end)

-- Install hooks on module activate
mod:RegisterOnEnable(function()
    installHooks()
end)

-- =========================================================
-- Options section
-- =========================================================
mod:AddOptionsSection("classcolor", function()
    return {
        { type = "header", text = L["Class Visuals"] },
        {
            type = "checkbox", label = L["Class-colored health bars"],
            tooltip = L["Colors the health bar in the player's class color."],
            get = function() return mod.db.classColorHealth end,
            set = function(_, v)
                mod.db.classColorHealth = v
                -- blanket-restore then re-apply still-enabled features, so
                -- turning one toggle off no longer clobbers the others
                if v then applyAll() else restoreAll(); applyAll() end
            end,
        },
        {
            type = "checkbox", label = L["Class-colored name"],
            get = function() return mod.db.classColorName end,
            set = function(_, v) mod.db.classColorName = v; applyAll() end,
        },
        {
            type = "checkbox", label = L["Class icon instead of portrait"],
            tooltip = L["Replaces the 3D portrait with a class symbol."],
            get = function() return mod.db.classIconPortrait end,
            set = function(_, v)
                mod.db.classIconPortrait = v
                -- blanket-restore then re-apply still-enabled features, so
                -- turning one toggle off no longer clobbers the others
                if v then applyAll() else restoreAll(); applyAll() end
            end,
        },
    }
end)

end)(...);

-- ============================================================
-- merged from: Arena/Trinket.lua
-- ============================================================
(function(...)
-- =========================================================
-- VuloClassicUI / Modules / Arena / Trinket
-- PvP trinket cooldown tracker per arena opponent.
-- Detects the cast via COMBAT_LOG_EVENT_UNFILTERED and shows icon + timer.
-- =========================================================
local _, ns = ...
if ns.isEra then return end  -- Classic Era has no arenas; skip the whole module
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

-- =========================================================
-- TBC PvP trinket spells and their cooldowns
-- =========================================================
local TRINKET_SPELLS = {
    -- PvP trinket item spells (all same effect, all 2 min CD in TBC)
    [42292] = 120,  -- PvP Trinket (Gladiator/Arena/Honor)
    [7744]  = 120,  -- Will of the Forsaken (Undead)
    [59752] = 120,  -- Will to Survive / Every Man for Himself (Human, retail)
    -- NOTE: Stoneform (20594) is a Dwarf racial that does NOT share the PvP
    -- trinket cooldown, so it must not be tracked here (false trinket display).
}

-- Icons for the trinkets (atlas doesn't work everywhere in TBC, so TexturePath)
local TRINKET_TEXTURE = "Interface\\Icons\\INV_Jewelry_TrinketPVP_02"

-- One trinket frame per slot
local trinketFrames = {}

-- =========================================================
-- Create trinket frame
-- =========================================================
local function createTrinketFrame(parent, slotIndex)
    local f = CreateFrame("Frame", "VCUIArenaTrinket" .. slotIndex, parent)
    f:SetSize(mod.db.trinketSize or 28, mod.db.trinketSize or 28)

    -- Icon
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexture(TRINKET_TEXTURE)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Border
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(0, 0, 0, 0.8)
    f.border:SetDrawLayer("BACKGROUND")

    -- Cooldown spiral
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(true)
    f.cd:SetHideCountdownNumbers(false)

    -- Tooltip
    f:EnableMouse(false)  -- not clickable, otherwise combat issues

    f:Hide()
    return f
end

local function ensureTrinketFrame(arenaFrame, i)
    if trinketFrames[i] then return trinketFrames[i] end
    local tf = createTrinketFrame(arenaFrame, i)
    trinketFrames[i] = tf
    return tf
end

-- =========================================================
-- Anchor + display
-- =========================================================
local function anchorTrinketFrame(tf, arenaFrame)
    if not tf or not arenaFrame then return end
    tf:ClearAllPoints()
    tf:SetSize(mod.db.trinketSize, mod.db.trinketSize)
    if mod.db.trinketAnchor == "LEFT" then
        tf:SetPoint("RIGHT", arenaFrame, "LEFT",  mod.db.trinketOffsetX,  mod.db.trinketOffsetY)
    else
        tf:SetPoint("LEFT",  arenaFrame, "RIGHT", -mod.db.trinketOffsetX, mod.db.trinketOffsetY)
    end
end

local function applyToFrame(arenaFrame, i)
    local tf = ensureTrinketFrame(arenaFrame, i)
    anchorTrinketFrame(tf, arenaFrame)
    if mod.db.trinketEnabled then
        tf:Show()
        if mod:IsUnlocked() then
            -- Test: show icon without cooldown
            tf.cd:Hide()
            tf.icon:SetDesaturated(false)
        end
    else
        tf:Hide()
    end
end

mod.RefreshTrinkets = function()
    H.ForEach(applyToFrame)
end

-- =========================================================
-- Trigger cooldown
-- =========================================================
local activeCDs = {}  -- arenaUnit -> { startTime, duration }

local function startCooldown(unit, duration)
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local arenaFrame = _G["ArenaEnemyFrame" .. i]
    if not arenaFrame then return end
    local tf = ensureTrinketFrame(arenaFrame, i)
    anchorTrinketFrame(tf, arenaFrame)

    tf.cd:SetCooldown(GetTime(), duration)
    tf.icon:SetDesaturated(true)
    if mod.db.trinketEnabled then tf:Show() end

    activeCDs[unit] = { start = GetTime(), duration = duration }

    -- Brighten again after expiry
    if C_Timer and C_Timer.After then
        C_Timer.After(duration + 0.1, function()
            if activeCDs[unit] and activeCDs[unit].start + activeCDs[unit].duration <= GetTime() then
                tf.icon:SetDesaturated(false)
                activeCDs[unit] = nil
            end
        end)
    end
end

-- =========================================================
-- Combat log: detect trinket cast
-- =========================================================
local function onCombatLog()
    local _, subevent, _, sourceGUID, _, _, _, _, _, _, _, spellId =
        CombatLogGetCurrentEventInfo()

    if subevent ~= "SPELL_CAST_SUCCESS" then return end
    if not TRINKET_SPELLS[spellId] then return end

    -- Which arena slot is it?
    for i = 1, 5 do
        local unit = "arena" .. i
        if UnitExists(unit) and UnitGUID(unit) == sourceGUID then
            startCooldown(unit, TRINKET_SPELLS[spellId])
            return
        end
    end
end

-- =========================================================
-- On arena start: reset all CDs
-- =========================================================
local function resetAllCDs()
    activeCDs = {}
    for i, tf in pairs(trinketFrames) do
        if tf and tf.cd then
            tf.cd:Clear()
            tf.icon:SetDesaturated(false)
        end
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
mod:OnArenaFramesReady(function(frame, i)
    applyToFrame(frame, i)
end)

-- Named handler so the (very hot) combat log can be registered only while
-- inside an arena. Otherwise it would fire a pcall for every combat-log line
-- in raids / dungeons / the open world, even though this only shows in arenas.
local function onCLEU()
    if not mod._enabled or not mod.db.trinketEnabled then return end
    onCombatLog()
end

local cleuActive = false
local function setCombatLog(active)
    if active == cleuActive then return end
    cleuActive = active
    if active then
        ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    else
        ns:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    end
end

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    local inArena = false
    if IsInInstance then
        local _, instanceType = IsInInstance()
        inArena = (instanceType == "arena")
    end
    if not inArena then resetAllCDs() end  -- left the arena -> clear
    setCombatLog(inArena)
end)
ns:RegisterEvent("ARENA_OPPONENT_UPDATE", function(_, _, eventType)
    -- "seen" = new opponents; reset on match start
    if eventType == "seen" then resetAllCDs() end
end)

-- =========================================================
-- Options section
-- =========================================================
mod:AddOptionsSection("trinket", function()
    return {
        { type = "header", text = L["PvP Trinket Tracker"] },
        {
            type = "checkbox", label = L["Show PvP trinket cooldown"],
            tooltip = L["Shows an icon with cooldown spiral next to the arena frame when the opponent used their PvP trinket."],
            get = function() return mod.db.trinketEnabled end,
            set = function(_, v) mod.db.trinketEnabled = v; mod.RefreshTrinkets() end,
        },
        {
            type = "slider", label = L["Icon size"],
            min = 16, max = 48, step = 1,
            get = function() return mod.db.trinketSize end,
            set = function(_, v) mod.db.trinketSize = v; mod.RefreshTrinkets() end,
        },
        {
            type = "dropdown", label = L["Position"],
            values = {
                { value = "LEFT",  text = L["Left of frame"] },
                { value = "RIGHT", text = L["Right of frame"] },
            },
            get = function() return mod.db.trinketAnchor end,
            set = function(_, v) mod.db.trinketAnchor = v; mod.RefreshTrinkets() end,
        },
        {
            type = "slider", label = L["Offset X"],
            min = -50, max = 50, step = 1,
            get = function() return mod.db.trinketOffsetX end,
            set = function(_, v) mod.db.trinketOffsetX = v; mod.RefreshTrinkets() end,
        },
        {
            type = "slider", label = L["Offset Y"],
            min = -50, max = 50, step = 1,
            get = function() return mod.db.trinketOffsetY end,
            set = function(_, v) mod.db.trinketOffsetY = v; mod.RefreshTrinkets() end,
        },
    }
end)

end)(...);

-- ============================================================
-- merged from: Arena/DR.lua
-- ============================================================
(function(...)
-- =========================================================
-- VuloClassicUI / Modules / Arena / DR (Diminishing Returns)
-- Tracks DR categories per arena opponent and shows icon + timer.
--
-- TBC DR system: Full -> 1/2 -> 1/4 -> Immune
-- Reset after ~15-18 seconds without a new cast of the same category.
-- =========================================================
local _, ns = ...
if ns.isEra then return end  -- Classic Era has no arenas; skip the whole module
local L = ns.L
local mod = ns.ArenaModule

local DR_RESET_TIME = 18  -- TBC

-- =========================================================
-- DR categories (order determines ID mapping in DR_SPELLS)
-- Source: warcraft.wiki.gg/wiki/Diminishing_returns (TBC entry)
-- =========================================================

-- Spell -> category. Intentionally trimmed to the most important TBC spells.
-- You can extend the list. For spells with rank variants, usually
-- only the final rank ID is here; add more if needed.
local DR_SPELLS = {
    -- Stuns
    [408]   = "stun",          -- Kidney Shot
    [1833]  = "stun",          -- Cheap Shot
    [5211]  = "stun",          -- Bash (Druid)
    [12809] = "stun",          -- Concussion Blow
    [20549] = "stun",          -- War Stomp (Tauren racial)
    [22703] = "stun",          -- Inferno Effect (Warlock Pet)
    [25274] = "stun",          -- Intercept
    [30283] = "stun",          -- Shadowfury (TBC)
    [12355] = "stun",          -- Impact (Mage stun proc)
    [19577] = "stun",          -- Intimidation (Hunter Pet)

    -- Incapacitate (Polymorph, Sap, Repentance, Freezing Trap, etc.)
    [118]   = "incapacitate",  -- Polymorph
    [12826] = "incapacitate",  -- Polymorph (Rank 4)
    [28272] = "incapacitate",  -- Polymorph: Pig
    [28271] = "incapacitate",  -- Polymorph: Turtle
    [6770]  = "incapacitate",  -- Sap
    [11297] = "incapacitate",  -- Sap (Rank 2)
    [3355]  = "incapacitate",  -- Freezing Trap Effect
    [9484]  = "incapacitate",  -- Shackle Undead
    [20066] = "incapacitate",  -- Repentance
    [2637]  = "incapacitate",  -- Hibernate

    -- Disorient
    [2094]  = "disorient",     -- Blind

    -- Fear
    [5782]  = "fear",          -- Fear (Warlock)
    [6358]  = "fear",          -- Seduction (Succubus)
    [5484]  = "fear",          -- Howl of Terror
    [8122]  = "fear",          -- Psychic Scream
    [5246]  = "fear",          -- Intimidating Shout
    [10326] = "fear",          -- Turn Evil

    -- Silence
    [15487] = "silence",       -- Silence (Priest)
    [18498] = "silence",       -- Silenced (Warrior Shield Bash effect)
    [24259] = "silence",       -- Spell Lock
    [25046] = "silence",       -- Arcane Torrent (Blood Elf racial)

    -- Root
    [122]   = "root",          -- Frost Nova
    [339]   = "root",          -- Entangling Roots
    [19185] = "root",          -- Entrapment
    [13099] = "root",          -- Net-o-Matic

    -- Cyclone (own category in TBC)
    [33786] = "cyclone",
}

-- =========================================================
-- DR state per unit
-- =========================================================
-- drState[unit][category] = { applied = number, expires = number }
local drState = {}

-- One row of DR icons per slot
-- drFrames[slot] = { container = Frame, icons = { [category] = icon } }
local drFrames = {}

-- =========================================================
-- Create DR icon frame
-- =========================================================
local function createDRContainer(parent, slotIndex)
    local container = CreateFrame("Frame", "VCUIArenaDR" .. slotIndex, parent)
    container:SetSize(120, mod.db.drSize or 24)
    container.icons = {}
    return container
end

local function createDRIcon(parent, category)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(mod.db.drSize or 24, mod.db.drSize or 24)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Border (shows DR level: yellow = 1/2, orange = 1/4, red = immune)
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    f.border:SetColorTexture(0, 1, 0, 1)  -- start: full
    f.border:SetDrawLayer("BACKGROUND")

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(true)

    f.category = category
    f:Hide()
    return f
end

-- =========================================================
-- Update DR display
-- =========================================================
local function getDRColor(level)
    -- level: 1 = full, 2 = half, 3 = quarter, 4 = immune
    if level == 1 then return 0, 1, 0 end
    if level == 2 then return 1, 1, 0 end
    if level == 3 then return 1, 0.5, 0 end
    return 1, 0, 0
end

local function getDRLevel(applied)
    if applied <= 1 then return 1 end
    if applied == 2 then return 2 end
    if applied == 3 then return 3 end
    return 4
end

local function updateDRDisplay(unit)
    if not mod.db.drEnabled then return end
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local arenaFrame = _G["ArenaEnemyFrame" .. i]
    if not arenaFrame then return end

    local container = drFrames[i]
    if not container then
        container = createDRContainer(arenaFrame, i)
        drFrames[i] = container
        container:ClearAllPoints()
        container:SetPoint("LEFT", arenaFrame, "RIGHT", 8, 0)
    end

    -- Arrange visible icons in a row
    local state = drState[unit] or {}
    local visible = {}
    for cat, data in pairs(state) do
        if data.expires > GetTime() then
            table.insert(visible, { cat = cat, data = data })
        end
    end
    -- Stable sort (alphabetical)
    table.sort(visible, function(a, b) return a.cat < b.cat end)

    -- Hide all
    for _, icon in pairs(container.icons) do icon:Hide() end

    local x = 0
    for _, entry in ipairs(visible) do
        local icon = container.icons[entry.cat]
        if not icon then
            icon = createDRIcon(container, entry.cat)
            container.icons[entry.cat] = icon
        end
        icon:SetSize(mod.db.drSize, mod.db.drSize)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", container, "LEFT", x, 0)

        -- Texture: resolved once per icon from a cached category->spell map,
        -- instead of rescanning DR_SPELLS + GetSpellInfo every 0.5s tick
        if not icon._texSet then
            mod._drCatFirst = mod._drCatFirst or (function()
                local t = {}
                for sid, c in pairs(DR_SPELLS) do if not t[c] then t[c] = sid end end
                return t
            end)()
            local sid = mod._drCatFirst[entry.cat]
            if sid then
                local _, _, iconTex = GetSpellInfo(sid)
                if iconTex then icon.icon:SetTexture(iconTex); icon._texSet = true end
            end
        end

        local level = getDRLevel(entry.data.applied)
        icon.border:SetColorTexture(getDRColor(level))

        icon.cd:SetCooldown(entry.data.appliedTime, DR_RESET_TIME)
        icon:Show()

        x = x + mod.db.drSize + 2
    end
end

-- =========================================================
-- Process DR event
-- =========================================================
local function onAuraApplied(destUnit, spellId)
    local cat = DR_SPELLS[spellId]
    if not cat then return end

    drState[destUnit] = drState[destUnit] or {}
    local entry = drState[destUnit][cat]
    if not entry then
        entry = { applied = 0, expires = 0, appliedTime = 0 }
        drState[destUnit][cat] = entry
    end

    -- If the previous entry has expired, reset
    if entry.expires < GetTime() then
        entry.applied = 0
    end

    entry.applied = math.min(entry.applied + 1, 4)
    entry.appliedTime = GetTime()
    entry.expires = GetTime() + DR_RESET_TIME

    updateDRDisplay(destUnit)
end

-- =========================================================
-- Combat log
-- =========================================================
local function onCombatLog()
    local _, subevent, _, _, _, _, _, destGUID, _, _, _, spellId =
        CombatLogGetCurrentEventInfo()

    if subevent ~= "SPELL_AURA_APPLIED" and subevent ~= "SPELL_AURA_REFRESH" then return end
    if not DR_SPELLS[spellId] then return end

    for i = 1, 5 do
        local unit = "arena" .. i
        if UnitExists(unit) and UnitGUID(unit) == destGUID then
            onAuraApplied(unit, spellId)
            return
        end
    end
end

-- =========================================================
-- Periodic update (for expiration)
-- =========================================================
local updaterFrame
local function ensureUpdater()
    if updaterFrame then return end
    updaterFrame = CreateFrame("Frame")
    updaterFrame.timer = 0
    updaterFrame:SetScript("OnUpdate", function(self, elapsed)
        self.timer = self.timer + elapsed
        if self.timer < 0.5 then return end
        self.timer = 0
        if not mod.db.drEnabled or not mod._enabled then return end
        for unit in pairs(drState) do
            updateDRDisplay(unit)
        end
    end)
end

-- =========================================================
-- Reset
-- =========================================================
local function resetAll()
    drState = {}
    for _, container in pairs(drFrames) do
        for _, icon in pairs(container.icons) do icon:Hide() end
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
-- Named handler so the (very hot) combat log can be registered only while
-- inside an arena. Otherwise it would fire a pcall for every combat-log line
-- in raids / dungeons / the open world, even though DR only shows in arenas.
local function onCLEU()
    if not mod._enabled or not mod.db.drEnabled then return end
    onCombatLog()
end

local cleuActive = false
local function setCombatLog(active)
    if active == cleuActive then return end
    cleuActive = active
    if active then
        ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    else
        ns:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    end
end

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    resetAll()
    local inArena = false
    if IsInInstance then
        local _, instanceType = IsInInstance()
        inArena = (instanceType == "arena")
    end
    if inArena then ensureUpdater() end
    setCombatLog(inArena)
end)

-- =========================================================
-- Options
-- =========================================================
mod:AddOptionsSection("dr", function()
    return {
        { type = "header", text = L["Diminishing Returns Tracker"] },
        { type = "desc",   text = L["Shows icons to the right of each arena frame for active DR categories (Stun, Fear, Polymorph etc.) with color indicator: |cff00ff00green|r = full, |cffffff00yellow|r = 1/2, |cffff8000orange|r = 1/4, |cffff0000red|r = immune."] },
        {
            type = "checkbox", label = L["Enable DR tracking"],
            get = function() return mod.db.drEnabled end,
            set = function(_, v)
                mod.db.drEnabled = v
                if not v then resetAll() end
            end,
        },
        {
            type = "slider", label = L["Icon size"],
            min = 16, max = 40, step = 1,
            get = function() return mod.db.drSize end,
            set = function(_, v) mod.db.drSize = v end,
        },
    }
end)

end)(...);

-- ============================================================
-- merged from: Arena/Castbar.lua
-- ============================================================
(function(...)
-- =========================================================
-- VuloClassicUI / Modules / Arena / Castbar
-- Custom castbar per arena opponent.
-- =========================================================
local _, ns = ...
if ns.isEra then return end  -- Classic Era has no arenas; skip the whole module
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

local castbars = {}  -- slot -> frame

-- =========================================================
-- Build castbar
-- =========================================================
local function createCastbar(parent, slotIndex)
    local f = CreateFrame("StatusBar", "VCUIArenaCastbar" .. slotIndex, parent, "BackdropTemplate")
    f:SetSize(mod.db.castbarWidth, mod.db.castbarHeight)
    f:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f:SetStatusBarColor(1.0, 0.7, 0.0)
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)

    -- Background
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetColorTexture(0, 0, 0, 0.7)

    -- Border
    f:SetBackdrop({
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    -- Icon on the left
    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetSize(mod.db.castbarHeight, mod.db.castbarHeight)
    f.icon:SetPoint("RIGHT", f, "LEFT", -2, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Spell name
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("LEFT",  f, "LEFT",   4, 0)
    f.text:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    f.text:SetJustifyH("LEFT")

    -- Timer on the right
    f.timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.timer:SetPoint("RIGHT", f, "RIGHT", -4, 0)

    -- State
    f.casting   = false
    f.channeling = false
    f.startTime = 0
    f.endTime   = 0

    f:Hide()
    return f
end

local function ensureCastbar(arenaFrame, i)
    if castbars[i] then return castbars[i] end
    local cb = createCastbar(arenaFrame, i)
    castbars[i] = cb
    cb:ClearAllPoints()
    cb:SetPoint("TOP", arenaFrame, "BOTTOM", 0, -2)
    return cb
end

-- =========================================================
-- OnUpdate for running casts
-- =========================================================
local function castbarOnUpdate(self, elapsed)
    if not self.casting and not self.channeling then
        self:Hide()
        return
    end
    local now = GetTime()
    local total = self.endTime - self.startTime
    if total <= 0 then total = 0.01 end  -- guard: instant casts give startTime == endTime
    local progress
    if self.channeling then
        progress = (self.endTime - now) / total
    else
        progress = (now - self.startTime) / total
    end
    progress = math.max(0, math.min(1, progress))
    self:SetValue(progress)

    local remaining = self.endTime - now
    if remaining < 0 then remaining = 0 end
    self.timer:SetText(string.format("%.1f", remaining))

    if now >= self.endTime then
        self.casting = false
        self.channeling = false
        self:Hide()
    end
end

-- =========================================================
-- Start cast
-- =========================================================
local function startCast(unit, channeling)
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local arenaFrame = _G["ArenaEnemyFrame" .. i]
    if not arenaFrame then return end
    local cb = ensureCastbar(arenaFrame, i)
    cb:SetSize(mod.db.castbarWidth, mod.db.castbarHeight)

    local name, _, texture, startTime, endTime
    if channeling then
        name, _, texture, startTime, endTime = UnitChannelInfo(unit)
    else
        name, _, texture, startTime, endTime = UnitCastingInfo(unit)
    end

    if not name or not startTime or not endTime then cb:Hide(); return end

    cb.startTime = startTime / 1000
    cb.endTime   = endTime   / 1000
    cb.casting    = not channeling
    cb.channeling = channeling

    cb.text:SetText(name)
    cb.icon:SetTexture(texture)
    if channeling then
        cb:SetStatusBarColor(0.2, 0.7, 1.0)
    else
        cb:SetStatusBarColor(1.0, 0.7, 0.0)
    end

    cb._hideToken = (cb._hideToken or 0) + 1   -- invalidate any pending interrupt-hide
    cb:Show()
    cb:SetScript("OnUpdate", castbarOnUpdate)
end

local function stopCast(unit, interrupted)
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local cb = castbars[i]
    if not cb then return end
    cb.casting   = false
    cb.channeling = false
    if interrupted then
        cb:SetStatusBarColor(1, 0, 0)
        cb.text:SetText(L["INTERRUPTED"])
        cb._hideToken = (cb._hideToken or 0) + 1
        local token = cb._hideToken
        if C_Timer and C_Timer.After then
            -- only hide if no new cast started in the meantime (token still ours)
            C_Timer.After(0.7, function() if cb._hideToken == token then cb:Hide() end end)
        else
            cb:Hide()
        end
    else
        cb:Hide()
    end
end

-- =========================================================
-- Re-anchor castbar (on layout change)
-- =========================================================
local function refreshCastbars()
    H.ForEach(function(frame, i)
        local cb = ensureCastbar(frame, i)
        cb:SetSize(mod.db.castbarWidth, mod.db.castbarHeight)
        cb.icon:SetSize(mod.db.castbarHeight, mod.db.castbarHeight)
        cb:ClearAllPoints()
        cb:SetPoint("TOP", frame, "BOTTOM", 0, -2)
        if not mod.db.castbarEnabled then cb:Hide() end
    end)
end

mod.RefreshCastbars = refreshCastbars

-- =========================================================
-- Events
-- =========================================================
local function isArenaUnit(unit)
    return unit and unit:match("^arena[1-5]$") ~= nil
end

mod:OnArenaFramesReady(function(frame, i)
    ensureCastbar(frame, i)
end)

ns:RegisterEvent("UNIT_SPELLCAST_START", function(_, unit)
    if not mod._enabled or not mod.db.castbarEnabled or not isArenaUnit(unit) then return end
    startCast(unit, false)
end)
ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", function(_, unit)
    if not mod._enabled or not mod.db.castbarEnabled or not isArenaUnit(unit) then return end
    startCast(unit, true)
end)
ns:RegisterEvent("UNIT_SPELLCAST_STOP", function(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, false)
end)
ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, false)
end)
ns:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", function(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, true)
end)
ns:RegisterEvent("UNIT_SPELLCAST_FAILED", function(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, false)
end)

-- =========================================================
-- Options
-- =========================================================
mod:AddOptionsSection("castbar", function()
    return {
        { type = "header", text = L["Castbar"] },
        {
            type = "checkbox", label = L["Castbar for arena opponents"],
            tooltip = L["Shows a castbar below the frame when the opponent casts or channels."],
            get = function() return mod.db.castbarEnabled end,
            set = function(_, v) mod.db.castbarEnabled = v; refreshCastbars() end,
        },
        {
            type = "slider", label = L["Width"],
            min = 60, max = 250, step = 1,
            get = function() return mod.db.castbarWidth end,
            set = function(_, v) mod.db.castbarWidth = v; refreshCastbars() end,
        },
        {
            type = "slider", label = L["Height"],
            min = 8, max = 30, step = 1,
            get = function() return mod.db.castbarHeight end,
            set = function(_, v) mod.db.castbarHeight = v; refreshCastbars() end,
        },
    }
end)

end)(...);
