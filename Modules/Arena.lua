-- VuloClassicUI / Modules / Arena

-- Each merged submodule runs in its own IIFE so file-level locals and top-level early-returns stay isolated.
(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L

local mod = ns:RegisterModule("arenaframes", {
    -- Strict grid: lone last rows of a run stretched across the page (user
    -- report, 31.07.2026). On the grid a lone row keeps its half.
    optionsGrid = true,
    name        = "Arena Frames",
    group       = "PvP",
    description = "Enhances the Arena enemy frames: move/scale, class colors, class icons, PvP trinket CD, DR tracking, castbar, drag&drop layout.",
    defaults = {
        pos        = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
        -- x/y drive pos, not the other way round, so they have to be defaults
        -- too - otherwise "Reset Module" put pos back and left the real position
        -- untouched.
        x          = 0,
        y          = 0,
        scale      = 1.0,
        healthSize = 10,
        powerSize  = 10,

        slotOrder        = { 1, 2, 3, 4, 5 },
        -- Gap below each frame. 6 left no room for the opponent's pet bar, which
        -- hangs off the bottom of the arena frame and then reached into the next
        -- one; 28 clears it and still reads as one block.
        slotSpacing      = 28,
        growDirection    = "down",
        slotOffsets      = {},

        -- Shared side strip: racial, PvP trinket and the DR row all live on the
        -- same edge and are laid out in one pass, in that order, outwards from
        -- the frame. See RegisterSideIcon.
        iconSide     = "RIGHT",
        iconOffsetX  = 8,
        iconOffsetY  = 0,
        iconGap      = 4,

        classColorHealth  = true,
        classColorName    = true,
        classIconPortrait = true,

        trinketEnabled   = true,
        trinketSize      = 24,

        drEnabled   = false,
        drSize      = 24,

        castbarEnabled = false,
        castbarWidth   = 120,
        castbarHeight  = 14,

        trinketSound = true,
        trinketGlow  = true,

        racialEnabled = true,
        racialSize    = 22,

        shadowsightEnabled = true,

        auraIconEnabled = true,
        auraOnlyCC      = false,

        dispelEnabled = false,
        dispelSize    = 22,

        rangeEnabled = true,
        rangeAlpha   = 0.45,

        cdTextEnabled = true,

        -- Loss of control lives in its own table because the mover writes x/y
        -- into whatever db it is handed, and the two above already belong to
        -- the arena frames.
        loss = {
            enabled        = true,
            visibility     = "always",
            unlocked       = false,
            x              = 0,
            y              = 0,
            scale          = 1,
            alpha          = 1,
            iconSize       = 40,
            nameSize       = 18,
            timeSize       = 16,
            -- Empty name means "whatever the global font setting says": that is
            -- what MediaFont falls back to, so the row follows the rest of the
            -- interface until the player picks something for this display alone.
            font           = "",
            outline        = "THICKOUTLINE",
            nameColor      = { r = 1, g = 0.925, b = 0 },
            timeColor      = { r = 1, g = 1, b = 1 },
            showBackground = true,
            -- Off by default: the second icon is for players who want to see
            -- what follows the effect that is holding them, and it is easy to
            -- read as a duplicate of the first when it appears unannounced.
            showNext       = false,
        },

        -- Own table for the same reason as above: the mover writes x/y into
        -- whatever it is handed.
        interrupts = {
            enabled     = true,
            visibility  = "pvp",
            unlocked    = false,
            x           = 0,
            y           = 140,
            iconSize    = 32,
            spacing     = 4,
            perRow      = 8,
            growth      = "RIGHT",
            showUnused  = false,
            showTimer   = true,
            showSwipe   = true,
            timerSize   = 13,
            -- Empty font name means the global setting, same as the loss
            -- display: the bar follows the rest of the interface until told
            -- otherwise.
            font        = "",
            outline     = "OUTLINE",
            timerColor  = { r = 1, g = 0.9, b = 0.4 },
        },
    },
})

ns.ArenaModule = mod

mod.helpers = {}
local H = mod.helpers

function H.GetOwner() return _G["ArenaEnemyFrames"] end

-- The five unit tokens and the five frame names, spelled once. Both were built
-- with a concatenation at every use, and the combat log handlers do it five
-- times per event -- in a raid that is thousands of throwaway strings a second
-- for two lists that can never change.
ns.ARENA_UNITS = { "arena1", "arena2", "arena3", "arena4", "arena5" }
local FRAME_NAMES = {
    "ArenaEnemyFrame1", "ArenaEnemyFrame2", "ArenaEnemyFrame3",
    "ArenaEnemyFrame4", "ArenaEnemyFrame5",
}

-- Looked up rather than cached: Blizzard_ArenaUI loads on demand, so a nil
-- answer here must not become the permanent one.
function H.Frame(i)
    local name = FRAME_NAMES[i]
    return name and _G[name] or nil
end

function H.ForEach(fn)
    for i = 1, 5 do
        local f = _G[FRAME_NAMES[i]]
        if f then fn(f, i) end
    end
end

function H.GetUnit(i)
    return ns.ARENA_UNITS[i]
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

-- ---------------------------------------------------------------------------
-- Side strip.
--
-- Racial, PvP trinket and the DR row share one edge of the arena frame. Each
-- used to carry its own edge and its own X/Y offsets, hand-tuned around the
-- others: the defaults read "26 clears the racial at 22", and every size slider
-- was a fresh chance for two icons to land on the same spot. They are laid out
-- in a single pass instead - fixed order, each one placed after the previous.
--
-- A slot is reserved by the SETTING, not by what is visible right now. An icon
-- that is momentarily hidden (racial before the opponent's race is known, an
-- expired DR) keeps its gap instead of shifting the rest along. In an arena an
-- icon that moves is an icon you have to find twice.
mod._sideIcons = {}

-- order: lower sits closer to the frame. Getter returns (frame, width), or nil
-- when the feature is switched off and its slot should collapse.
function mod.RegisterSideIcon(order, getter)
    local list = mod._sideIcons
    list[#list + 1] = { order = order, get = getter }
    table.sort(list, function(a, b) return a.order < b.order end)
end

function mod.IsSideStripRight()
    return (mod.db.iconSide or "RIGHT") ~= "LEFT"
end

function mod.LayoutSideIcons(arenaFrame, i)
    if not arenaFrame then return end
    local d     = mod.db
    local right = mod.IsSideStripRight()
    local gap   = d.iconGap or 4
    local y     = d.iconOffsetY or 0
    local x     = d.iconOffsetX or 8

    for _, entry in ipairs(mod._sideIcons) do
        local ok, f, width = pcall(entry.get, arenaFrame, i)
        -- A getter that throws leaves its icon unanchored for good, so it has to
        -- say so. Once per getter: this runs from the combat log, and a repeating
        -- fault would otherwise fill the chat frame during a fight.
        if not ok and not entry.reported then
            entry.reported = true
            ns:Print(L["|cffff5555Arena icon strip error:|r %s"], tostring(f))
        end
        if ok and f then
            f:ClearAllPoints()
            if right then
                f:SetPoint("LEFT", arenaFrame, "RIGHT", x, y)
            else
                f:SetPoint("RIGHT", arenaFrame, "LEFT", -x, y)
            end
            x = x + (width or f:GetWidth() or 0) + gap
        end
    end
end

function mod.RefreshSideIcons()
    H.ForEach(mod.LayoutSideIcons)
    -- Every slider that moves the strip already comes through here, so the
    -- options-page stand-in follows without a second wiring. No-op until the
    -- preview exists and is on screen.
    if mod.RefreshSidePreview then mod.RefreshSidePreview() end
end

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

function mod:RefreshAll()
    if UIParentLoadAddOn and IsAddOnLoaded and not IsAddOnLoaded("Blizzard_ArenaUI") then
        UIParentLoadAddOn("Blizzard_ArenaUI")
    end
    if not H.GetOwner() then return false end
    self:_triggerReady()
    return true
end

mod._onEnableHandlers = {}
function mod:RegisterOnEnable(handler)
    table.insert(self._onEnableHandlers, handler)
end

-- ns:RegisterEvent appends and unregisters by function identity, so a handler
-- passed as an anonymous function can never be taken back out again - which is
-- why this module had no OnDisable at all. Every handler in this file is named
-- and recorded here instead. The five installed from OnEnableCore had a second
-- problem on top: nothing de-duplicates, so each enable added another copy of
-- all five, for the rest of the session.
mod._events = {}
mod._eventsLive = true

function mod.RegEvent(event, fn)
    mod._events[#mod._events + 1] = { event, fn }
    ns:RegisterEvent(event, fn)
end

local function reinstallEvents()
    if mod._eventsLive then return end
    for i = 1, #mod._events do
        ns:RegisterEvent(mod._events[i][1], mod._events[i][2])
    end
    mod._eventsLive = true
end

local function removeEvents()
    if not mod._eventsLive then return end
    for i = 1, #mod._events do
        ns:UnregisterEvent(mod._events[i][1], mod._events[i][2])
    end
    mod._eventsLive = false
end

-- ---------------------------------------------------------------------------
-- Zone-gated subscriptions.
--
-- The combat log is the hottest event in the game, so three submodules take it
-- only for as long as the player is inside an arena. They used to do that with
-- a direct ns:RegisterEvent and a private flag, which put those handlers in NO
-- registry at all: not in mod._events, and not in the per-module list that
-- ns:ModUnregisterAllEvents walks. Switching the module off inside an arena
-- therefore left all three subscribed for the rest of the session -- and the
-- one handler that would have taken them out on the way through the gate had
-- just been unregistered along with everything else.
--
-- Two rules, and both matter: OnDisable takes the live ones out while keeping
-- what each submodule WANTS, and OnEnable restores exactly those again rather
-- than every subscription that was ever asked for.
local dynList, dynWant, dynLive = {}, {}, {}

local function syncDynEvents()
    for i = 1, #dynList do
        local d = dynList[i]
        local want = mod._eventsLive and dynWant[d.fn] or false
        if want ~= (dynLive[d.fn] or false) then
            dynLive[d.fn] = want
            if want then
                ns:RegisterEvent(d.event, d.fn)
            else
                ns:UnregisterEvent(d.event, d.fn)
            end
        end
    end
end

function mod.SetDynEvent(event, fn, on)
    if dynWant[fn] == nil then
        dynList[#dynList + 1] = { event = event, fn = fn }
    end
    dynWant[fn] = on and true or false
    syncDynEvents()
end

function mod:OnEnable()
    -- before OnEnableCore, so the handlers it wires on a first enable are not
    -- also caught by the re-install loop and registered twice
    reinstallEvents()
    syncDynEvents()
    if self.OnEnableCore then self:OnEnableCore() end
    for _, h in ipairs(self._onEnableHandlers) do
        local ok, err = pcall(h, self)
        if not ok then
            ns:Print(L["|cffff5555Arena submodule OnEnable error:|r %s"], tostring(err))
        end
    end
end

mod._onDisableHandlers = {}
function mod:RegisterOnDisable(handler)
    table.insert(self._onDisableHandlers, handler)
end

function mod:OnDisable()
    removeEvents()
    syncDynEvents()
    for _, h in ipairs(self._onDisableHandlers) do
        local ok, err = pcall(h, self)
        if not ok then
            ns:Print(L["|cffff5555Arena submodule OnDisable error:|r %s"], tostring(err))
        end
    end
end

mod._optionsBuilders = {}

local SECTION_LABELS
ns.OnLocaleReady(function()
SECTION_LABELS = {
    core       = L["General"],
    layout     = L["Layout"],
    classcolor = L["Class Color"],
    trinket    = L["PvP Trinket"],
    dr         = L["DR Tracker"],
    castbar    = L["Castbar"],
    racial     = L["Racials"],
    shadowsight = L["Shadow Sight"],
    auraicon   = L["Auras"],
    dispel     = L["Dispels"],
    range      = L["Range"],
    loss       = L["Loss of Control"],
    interrupt  = L["Interrupts"],
}
end)

function mod:AddOptionsSection(name, builder)
    table.insert(self._optionsBuilders, { name = name, fn = builder })
end

-- TWO tabs instead of eleven (user request, 31.07.2026): "General" carries
-- position/scale/fonts plus the layout section, "PvP Settings" everything
-- else -- class colours, trinket, DR, castbar, racials, shadow sight, auras,
-- dispels and range. The section capsules stay untouched; only the tab plan
-- decides what renders where.
local TAB_SECTIONS = {
    core = { core = true, layout = true },
    pvp  = { classcolor = true, trinket = true, dr = true, castbar = true,
             racial = true, shadowsight = true, auraicon = true, dispel = true,
             range = true },
    loss      = { loss = true },
    interrupt = { interrupt = true },
}

local function buildTabsArray()
    local tabs = {
        { id = "core", label = SECTION_LABELS.core or "General" },
        { id = "pvp",  label = L["PvP Settings"] },
    }
    -- Only where the client has the namespace behind it. The submodule sets the
    -- flag at load; a tab whose page could offer nothing is better absent than
    -- empty.
    if mod.HasLossOfControl then
        tabs[#tabs + 1] = { id = "loss", label = SECTION_LABELS.loss or "Loss of Control" }
    end
    tabs[#tabs + 1] = { id = "interrupt", label = SECTION_LABELS.interrupt or "Interrupts" }
    return tabs
end

-- mod.tabs can only be built after every AddOptionsSection call, i.e. at PLAYER_LOGIN.
local tabsInitFrame = CreateFrame("Frame")
tabsInitFrame:RegisterEvent("PLAYER_LOGIN")
tabsInitFrame:SetScript("OnEvent", function()
    mod.tabs = buildTabsArray()
end)

function mod:GetOptions(tabId)
    if tabId and tabId ~= "default" then
        -- Collect every section the tab plan assigns to this tab, in
        -- registration order; each section brings its own headers, a spacer
        -- keeps them readable as groups.
        local want = TAB_SECTIONS[tabId]
        if not want then return {} end
        local items = {}
        for _, sec in ipairs(self._optionsBuilders) do
            if want[sec.name] then
                for _, it in ipairs(sec.fn(self) or {}) do
                    table.insert(items, it)
                end
                table.insert(items, { type = "spacer", height = 8 })
            end
        end
        return items
    end

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

(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

local pendingApply = false
local unlocked = false
local hookedManage = false
local dragOverlay

local function unmanageOwner()
    if UIPARENT_MANAGED_FRAME_POSITIONS and UIPARENT_MANAGED_FRAME_POSITIONS["ArenaEnemyFrames"] then
        UIPARENT_MANAGED_FRAME_POSITIONS["ArenaEnemyFrames"] = nil
    end
end

local applyingOwner = false

local function applyToOwner()
    local owner = H.GetOwner()
    if not owner then return end
    if ns:InCombat() then pendingApply = true; return end
    if applyingOwner then return end

    -- pcall with the flag cleared outside it: an error in here would otherwise
    -- leave applyingOwner true and every later correction would take the
    -- "already running" exit, permanently and without a word.
    local p = mod.db.pos or {}
    unmanageOwner()
    applyingOwner = true
    pcall(function()
        owner:ClearAllPoints()
        owner:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
        owner:SetScale(mod.db.scale or 1.0)
    end)
    applyingOwner = false

    if dragOverlay and dragOverlay:IsShown() and mod.UpdateDragOverlay then
        mod:UpdateDragOverlay()
    end
end

mod.ApplyOwnerPosition = applyToOwner

-- Whatever moves the container reports it here, hook on UIParent_ManageFramePositions
-- or not: a post-hook on its own anchor methods catches the re-manage, the layout
-- pass Blizzard runs when an opponent appears, and anything a third addon does.
-- In combat the frame is protected and cannot be moved back, so the correction is
-- deferred to PLAYER_REGEN_ENABLED through pendingApply, exactly as applyToOwner
-- already does.
local ownerWatched = false
local function watchOwnerAnchors()
    if ownerWatched or not hooksecurefunc then return end
    local owner = H.GetOwner()
    if not owner then return end
    ownerWatched = true
    local function onOwnerMoved()
        if not mod._enabled or applyingOwner then return end
        applyToOwner()
    end
    hooksecurefunc(owner, "SetPoint", onOwnerMoved)
    hooksecurefunc(owner, "ClearAllPoints", onOwnerMoved)
end

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

-- Blizzard rewrites bar text fonts in TextStatusBar_UpdateTextString; re-apply ours after it.
local fontHooksInstalled = false
local function installFontHooks()
    if fontHooksInstalled or not hooksecurefunc or not TextStatusBar_UpdateTextString then return end
    fontHooksInstalled = true
    hooksecurefunc("TextStatusBar_UpdateTextString", function(bar)
        if not mod._enabled or not bar then return end
        for i = 1, 5 do
            local f = H.Frame(i)
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

-- UIParent_ManageFramePositions would snap the container back to Blizzard's slot.
local function hookManageFramePositions()
    if hookedManage or not hooksecurefunc then return end
    if not _G["UIParent_ManageFramePositions"] then return end
    hookedManage = true
    hooksecurefunc("UIParent_ManageFramePositions", function()
        if not mod._enabled or ns:InCombat() then return end
        applyToOwner()
    end)
end

local MOVER_WIDTH  = 220
local MOVER_HEIGHT = 280

-- The overlay is what the player grabs, so it has to cover what it claims to.
-- The constants above only ever matched the stack at the old 6px spacing; at a
-- wider setting the bottom frames hung outside the box and could not be grabbed
-- at all. The layout pass measures the real stack, and the overlay follows it.
local function sizeDragOverlay()
    if not dragOverlay then return end
    local w, h = MOVER_WIDTH, MOVER_HEIGHT
    if mod.GetStackSize then
        local sw, sh = mod.GetStackSize()
        if sw and sw > 0 then w = sw end
        if sh and sh > 0 then h = sh end
    end
    dragOverlay:SetSize(w, h)
    if mod._mover and mod._mover.SetSize then mod._mover:SetSize(w, h) end
end

-- Proxy overlay is dragged instead of the secure container (StartMoving on it would taint); both are kept at identical scale + CENTER offset.
local function arenaApplyPos()
    if not dragOverlay then return end
    dragOverlay:SetScale(mod.db.scale or 1.0)
    sizeDragOverlay()
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

    -- migrate legacy pos table into the mover engine's CENTER-offset model (mod.db.x/y)
    if mod.db.x == nil then
        mod.db.x = (mod.db.pos and mod.db.pos.x) or 0
        mod.db.y = (mod.db.pos and mod.db.pos.y) or 0
    end

    dragOverlay = CreateFrame("Frame", "VCUIArenaDragOverlay", UIParent)
    dragOverlay:SetSize(MOVER_WIDTH, MOVER_HEIGHT)
    dragOverlay:SetFrameStrata("HIGH")
    dragOverlay:SetFrameLevel(100)
    dragOverlay:SetClampedToScreen(true)
    dragOverlay:Hide()

    mod._mover = ns:CreateMover(dragOverlay, {
        key      = "arenaframes",
        label    = L["|cffffffffARENA FRAMES|r"],
        db       = mod.db,
        width    = MOVER_WIDTH, height = MOVER_HEIGHT,
        scalable = true,
        applyPos = arenaApplyPos,
        onMove   = arenaOnMove,
        editPreview = function(show) if mod.SetUnlocked then mod.SetUnlocked(show) end end,
    })
    return dragOverlay
end

function mod:UpdateDragOverlay()
    if not dragOverlay then return end

    local p = mod.db.pos or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    sizeDragOverlay()
    dragOverlay:ClearAllPoints()
    dragOverlay:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    -- must match the owner's scale, else dragging does not map 1:1
    dragOverlay:SetScale(mod.db.scale or 1.0)
end

local function setUnlocked(state)
    unlocked = state and true or false
    if unlocked then
        if ns:InCombat() then
            ns:Print(L["Not possible in combat."])
            unlocked = false
            return
        end
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
    -- unlocking releases the BG unit watch so all test frames show; defined later, so reached via mod
    if mod.ApplyBGUnitWatch then mod.ApplyBGUnitWatch() end
end

mod.SetUnlocked = setUnlocked
mod.IsUnlocked  = function() return unlocked end

local function showTestArenaFrames(show)
    H.ForEach(function(frame, i)
        if show then
            frame:Show()
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
            -- only kill phantom frames without a unit; real ones stay Blizzard-managed
            if not (UnitExists and UnitExists(ns.ARENA_UNITS[i])) and not ns:InCombat() then
                frame:Hide()
            end
        end
    end)
    if not show then
        local owner = H.GetOwner()
        if owner and ArenaEnemyFrames_Update then
            pcall(ArenaEnemyFrames_Update)
        end
    end
end

mod.ShowTestFrames = showTestArenaFrames

-- BG-only: RegisterUnitWatch is Blizzard's secure show/hide driver, so it works in combat without tainting.
local bgWatchActive = false
local function applyBGUnitWatch()
    -- (un)registering a unit watch is blocked in combat
    if InCombatLockdown and InCombatLockdown() then return end

    local inBG = false
    if IsInInstance then
        local _, instanceType = IsInInstance()
        inBG = (instanceType == "pvp")
    end

    local want = inBG and not unlocked
    if want == bgWatchActive then return end
    bgWatchActive = want

    H.ForEach(function(frame)
        if want then
            -- never SetAttribute here; Blizzard already set "unit" and writing it would taint the frame
            if RegisterUnitWatch and frame:GetAttribute("unit") then
                pcall(RegisterUnitWatch, frame)
            end
        elseif UnregisterUnitWatch then
            pcall(UnregisterUnitWatch, frame)
        end
    end)
end
mod.ApplyBGUnitWatch = applyBGUnitWatch

local function ev_core_refresh()
    mod:Refresh()
end

local function ev_core_ADDON_LOADED(_, name)
    if name == "Blizzard_ArenaUI" then mod:Refresh() end
end

local function ev_core_PLAYER_REGEN_ENABLED()
    if pendingApply then pendingApply = false; mod:Refresh() end
    applyBGUnitWatch()
end

local coreEventsWired = false

function mod:OnEnableCore()
    installFontHooks()
    hookManageFramePositions()
    ensureDragOverlay()

    self:OnArenaFramesReady(function(frame, i)
        applyArenaFonts(frame)
    end)

    -- Once per session: OnEnable re-installs the recorded set on a later enable,
    -- and wiring these again here would add a second copy of each.
    if not coreEventsWired then
        coreEventsWired = true
        mod.RegEvent("PLAYER_LOGIN",          ev_core_refresh)
        mod.RegEvent("PLAYER_ENTERING_WORLD", ev_core_refresh)
        mod.RegEvent("ZONE_CHANGED_NEW_AREA", ev_core_refresh)
        mod.RegEvent("ADDON_LOADED",          ev_core_ADDON_LOADED)
        mod.RegEvent("PLAYER_REGEN_ENABLED",  ev_core_PLAYER_REGEN_ENABLED)
    end

    self:Refresh()
end

function mod:Refresh()
    unmanageOwner()
    watchOwnerAnchors()
    applyToOwner()
    if self:RefreshAll() then
        applyAllFonts()
    end
    -- The arena UI is loaded on demand, so this is the first point in a session
    -- where the frames exist at all; the layout block installs its hooks here.
    if self.HookLayout then self.HookLayout() end
    if self.ApplyLayout then self.ApplyLayout() end

    if not unlocked and not ns:InCombat() then
        H.ForEach(function(frame, i)
            if not (UnitExists and UnitExists(ns.ARENA_UNITS[i])) then frame:Hide() end
        end)
    end

    applyBGUnitWatch()

    -- frames can arrive a tick or two late
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            watchOwnerAnchors(); applyToOwner()
            if self.HookLayout then self.HookLayout() end
            if self.ApplyLayout then self.ApplyLayout() end
        end)
        C_Timer.After(1, function()
            watchOwnerAnchors(); applyToOwner()
            self:RefreshAll(); applyBGUnitWatch()
            if self.HookLayout then self.HookLayout() end
            if self.ApplyLayout then self.ApplyLayout() end
        end)
    end
end

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
                      -- x/y are the authoritative pair: arenaApplyPos rewrites
                      -- pos from them. Clearing only pos looked right until the
                      -- next nudge or scale change, which put the old position
                      -- straight back and saved it again.
                      mod.db.x, mod.db.y = 0, 0
                      mod.db.pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
                      arenaApplyPos()
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

(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

-- Set while we are anchoring, so the watchdog below does not answer our own
-- SetPoint calls.
local applying  = false
local scheduled = false

-- The slot order is player data and arrives from imported profile strings too,
-- which are not validated on the way in. A repeated slot would make us anchor a
-- frame to itself (SetPoint raises on the cycle) and a slotOffsets entry that is
-- not a table would raise on the first field read - both inside the anchoring
-- loop, where an error leaves the whole module wedged. Sanitised up front
-- instead, so the loop below cannot throw on bad stored data.
local SLOT_SEQ = {}
local function orderedSlots()
    for i = #SLOT_SEQ, 1, -1 do SLOT_SEQ[i] = nil end
    local seen = {}
    local order = mod.db.slotOrder
    if type(order) == "table" then
        for _, slotIndex in ipairs(order) do
            slotIndex = tonumber(slotIndex)
            if slotIndex and slotIndex >= 1 and slotIndex <= 5 and not seen[slotIndex] then
                seen[slotIndex] = true
                SLOT_SEQ[#SLOT_SEQ + 1] = slotIndex
            end
        end
    end
    -- a slot dropped by the pass above still has to be laid out somewhere
    for slotIndex = 1, 5 do
        if not seen[slotIndex] then SLOT_SEQ[#SLOT_SEQ + 1] = slotIndex end
    end
    return SLOT_SEQ
end

local function slotOffset(slotIndex)
    local all = mod.db.slotOffsets
    local o = type(all) == "table" and all[slotIndex]
    if type(o) ~= "table" then return 0, 0 end
    return tonumber(o.x) or 0, tonumber(o.y) or 0
end

-- The five opponent frames are protected: they carry unit attributes and can be
-- clicked in combat, so the client guards their position. Anchoring one of them
-- from our code is allowed outside a fight, but it marks the frame, and the next
-- time the default interface repositions it during a round its own SetPoint is
-- refused and the block is reported against us:
--
--   [ADDON_ACTION_BLOCKED] ... 'UNKNOWN()' / [C]: in function 'SetPoint'
--
-- There is no way to anchor a protected frame without leaving that mark, so the
-- frames are only touched when the player actually asked for a different
-- arrangement. An untouched setup keeps the default stacking and stays clean;
-- moving a slot, the spacing slider or the grow direction takes it over from
-- there, and the message becomes the price of a feature that was asked for
-- rather than something every arena hands out for free.
local DEFAULT_SPACING = 28

local function layoutIsDefault()
    if (mod.db.growDirection or "down") ~= "down" then return false end
    if (tonumber(mod.db.slotSpacing) or DEFAULT_SPACING) ~= DEFAULT_SPACING then return false end

    local order = mod.db.slotOrder
    if type(order) == "table" then
        for i = 1, 5 do
            if tonumber(order[i]) ~= i then return false end
        end
    end

    local offsets = mod.db.slotOffsets
    if type(offsets) == "table" then
        for _, o in pairs(offsets) do
            if type(o) == "table" and ((tonumber(o.x) or 0) ~= 0 or (tonumber(o.y) or 0) ~= 0) then
                return false
            end
        end
    end

    return true
end

-- Size of the whole stack, for the drag overlay. nil until the frames have a
-- measurable height, which is the first tick after the arena UI loads.
local stackW, stackH
function mod.GetStackSize()
    return stackW, stackH
end

local reportedLayoutError = false

-- Installed on demand from applyLayout, so a default arrangement never writes
-- anything into the protected frames at all.
local watchFrameAnchors

local function anchorSlots(owner, slots, spacing, grow)
    local previous = nil
    for _, slotIndex in ipairs(slots) do
        local frame = H.Frame(slotIndex)
        if frame then
            local ox, oy = slotOffset(slotIndex)
            frame:ClearAllPoints()

            if not previous then
                local edge = (grow == "down") and "TOP" or "BOTTOM"
                if stackH then
                    local half = (grow == "down") and (stackH / 2) or -(stackH / 2)
                    frame:SetPoint(edge, owner, "CENTER", ox, oy + half)
                else
                    frame:SetPoint(edge, owner, edge, ox, oy)
                end
            else
                local thisAnchor = (grow == "down") and "TOP"    or "BOTTOM"
                local prevAnchor = (grow == "down") and "BOTTOM" or "TOP"
                local yDelta     = (grow == "down") and -spacing or  spacing
                frame:SetPoint(thisAnchor, previous, prevAnchor, ox, oy + yDelta)
            end
            previous = frame
        end
    end
end

local function applyLayout()
    local owner = H.GetOwner()
    if not owner then return end
    -- secure frames: moving them in combat is blocked and taints; re-applied on PLAYER_REGEN_ENABLED
    if InCombatLockdown() then return end
    if applying then return end

    local slots   = orderedSlots()
    local spacing = mod.db.slotSpacing or 28
    local grow    = mod.db.growDirection or "down"

    -- Measured first, because the stack is centred on the container: without it
    -- the frames would hang off the container's top edge and the drag overlay,
    -- which the mover engine keeps centred on the same point, could only ever
    -- cover them at one particular spacing.
    -- Two measurements: the height our own spacing would produce, and the height
    -- the frames actually occupy right now. The first is the right answer while
    -- we are anchoring - the frames have not moved yet at that point - and the
    -- second is the only honest one when we leave the stacking alone, because
    -- then the gap is not ours to predict. Top and bottom need no scale
    -- conversion: all five share the container's scale, so they are already in
    -- the same units as GetHeight.
    local totalH, maxW, counted = 0, 0, 0
    local top, bottom
    for _, slotIndex in ipairs(slots) do
        local frame = H.Frame(slotIndex)
        if frame then
            local h, w = frame:GetHeight() or 0, frame:GetWidth() or 0
            if h > 0 then totalH = totalH + h; counted = counted + 1 end
            if w > maxW then maxW = w end
            local t, b = frame:GetTop(), frame:GetBottom()
            if t and b then
                if not top    or t > top    then top    = t end
                if not bottom or b < bottom then bottom = b end
            end
        end
    end
    if counted > 0 then
        stackH = totalH + spacing * (counted - 1)
        stackW = maxW
    else
        stackH, stackW = nil, nil
    end

    -- Measuring above is harmless - it only reads. Anchoring is what marks the
    -- protected frames, so a default arrangement stops here and leaves them to
    -- the default interface. The overlay is still updated: it is our own frame
    -- and the player can still drag the whole stack around.
    if layoutIsDefault() then
        if counted > 0 and top and bottom and top > bottom then
            stackH = top - bottom
        end
        if mod.UpdateDragOverlay then mod:UpdateDragOverlay() end
        return
    end

    -- Only from here on is the layout ours, so this is where the frames start
    -- being watched for moves made behind our back.
    watchFrameAnchors()

    -- pcall, and the flag cleared outside it: an error thrown between setting
    -- and clearing would leave `applying` true for the rest of the session, and
    -- every later re-apply - including the one that repairs the frames after a
    -- fight - would take the "already running" exit and do nothing, silently.
    applying = true
    local ok, err = pcall(anchorSlots, owner, slots, spacing, grow)
    applying = false
    if not ok and not reportedLayoutError then
        reportedLayoutError = true
        ns:Print(L["|cffff5555Arena layout failed:|r %s"], tostring(err))
    end

    if mod.UpdateDragOverlay then mod:UpdateDragOverlay() end
end

mod.ApplyLayout = applyLayout

-- One re-apply per frame update, however many anchor calls triggered it: a single
-- Blizzard pass touches all five frames and would otherwise run the whole layout
-- five times over.
local function requestLayout()
    if applying or scheduled or not mod._enabled then return end
    -- nothing to defer: PLAYER_REGEN_ENABLED re-applies unconditionally
    if InCombatLockdown() then return end
    if not (C_Timer and C_Timer.After) then applyLayout(); return end
    scheduled = true
    C_Timer.After(0, function()
        scheduled = false
        applyLayout()
    end)
end

local function ev_layout_PLAYER_REGEN_ENABLED()
    -- Anything that moved a frame while it was protected is repaired here, and
    -- unconditionally: a move made through a path we do not watch would leave no
    -- flag behind, so there is nothing worth remembering during the fight.
    if mod._enabled then applyLayout() end
end

local function ev_layout_refresh()
    requestLayout()
end

-- Frames are re-anchored by more than one path - a new opponent being seen, the
-- container being re-managed - and there is no one event that covers all of
-- them, so the frames report their own moves instead.
--
-- The limit is combat: these are protected frames, so a move made during a round
-- cannot be undone until it ends. A late opponent walking into view mid-fight
-- therefore keeps Blizzard's stacking until PLAYER_REGEN_ENABLED repairs it.
local anchorWatched = {}
function watchFrameAnchors()
    if not hooksecurefunc then return end
    H.ForEach(function(frame)
        if anchorWatched[frame] then return end
        anchorWatched[frame] = true
        hooksecurefunc(frame, "SetPoint", requestLayout)
        hooksecurefunc(frame, "ClearAllPoints", requestLayout)
    end)
end

local layoutHooked = false
local function hookLayout()
    if not hooksecurefunc then return end

    -- Blizzard_ArenaUI loads on demand, so at PLAYER_LOGIN these globals do not
    -- exist yet. The flag used to be set before they were checked, which meant
    -- the hooks were never installed at all and the whole layout - order, spacing,
    -- grow direction - silently did nothing for the rest of the session.
    if not layoutHooked and _G.ArenaEnemyFrames_Update and _G.ArenaEnemyFrames_UpdatePlayer then
        layoutHooked = true
        hooksecurefunc("ArenaEnemyFrames_UpdatePlayer", requestLayout)
        hooksecurefunc("ArenaEnemyFrames_Update", requestLayout)
    end
end

mod.HookLayout = hookLayout

-- Registered here rather than inside hookLayout: the post-combat repair must not
-- depend on the arena UI having been loaded when the hooks were tried.
mod.RegEvent("PLAYER_REGEN_ENABLED",  ev_layout_PLAYER_REGEN_ENABLED)
mod.RegEvent("ARENA_OPPONENT_UPDATE", ev_layout_refresh)

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
    ns.UI:BuildOptionsPage("arenaframes")
end

mod:OnArenaFramesReady(function(frame, i)
    -- Layout is applied for all slots at once, nothing per frame - but this is
    -- where frames are known to exist, so it is where they get watched.
    hookLayout()
    requestLayout()
end)

local layoutInitFrame = CreateFrame("Frame")
layoutInitFrame:RegisterEvent("ADDON_LOADED")
layoutInitFrame:RegisterEvent("PLAYER_LOGIN")
layoutInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
layoutInitFrame:SetScript("OnEvent", function(_, _, addonName)
    hookLayout()
    if mod._enabled then applyLayout() end
end)

mod:AddOptionsSection("layout", function()
    local items = {
        { type = "header", text = L["Layout (Order)"] },
        { type = "desc",   text = L["Order of the arena frames. Use up/down to move slots 1-5."] },
        { type = "spacer", height = 4 },
    }

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
        tooltip = L["Gap below each frame. The opponent's pet bar hangs off the bottom of the frame, so a small gap lets it reach into the next one."],
        min = 0, max = 120, step = 1,
        get = function() return mod.db.slotSpacing end,
        set = function(_, v) mod.db.slotSpacing = v; applyLayout() end,
    })
    table.insert(items, {
        type = "segmented", label = L["Grow direction"],
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

    table.insert(items, { type = "spacer", height = 8 })
    table.insert(items, { type = "header", text = L["Icon Strip"] })
    table.insert(items, { type = "desc",
        text = L["Racial, PvP trinket and the DR row sit on the same edge of the frame and are placed one after the other, in that order, outwards from the frame."] })
    table.insert(items, {
        type = "dropdown", label = L["Side"],
        values = {
            { value = "RIGHT", text = L["Right of frame"] },
            { value = "LEFT",  text = L["Left of frame"] },
        },
        get = function() return mod.db.iconSide end,
        -- RefreshDR, not just RefreshSideIcons: the side also decides which way
        -- the DR icons grow INSIDE their container, and that is redrawn in
        -- updateDRDisplay. Moving the container alone would leave a live row
        -- growing back across the arena frame until the next expiry tick.
        set = function(_, v) mod.db.iconSide = v; mod.RefreshSideIcons(); mod.RefreshDR() end,
    })
    table.insert(items, {
        type = "slider", label = L["Distance from frame"],
        min = 0, max = 80, step = 1,
        get = function() return mod.db.iconOffsetX end,
        set = function(_, v) mod.db.iconOffsetX = v; mod.RefreshSideIcons() end,
    })
    table.insert(items, {
        type = "slider", label = L["Spacing between icons"],
        min = 0, max = 30, step = 1,
        get = function() return mod.db.iconGap end,
        set = function(_, v) mod.db.iconGap = v; mod.RefreshSideIcons() end,
    })
    table.insert(items, {
        type = "slider", label = L["Offset Y"],
        min = -60, max = 60, step = 1,
        get = function() return mod.db.iconOffsetY end,
        set = function(_, v) mod.db.iconOffsetY = v; mod.RefreshSideIcons() end,
    })

    return items
end)

end)(...);

(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

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

-- CLASS_ICON_TCOORDS is cut for exactly this atlas; other class-icon textures use a different grid.
local CLASS_ICON_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

local function classColor(class)
    if not class then return nil end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local applyClassToFrame

local function applyToFrame(frame, i)
    local unit = H.GetUnit(i)
    if not UnitExists(unit) then
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

applyClassToFrame = function(frame, class)  -- fills the forward declaration above (used by applyToFrame)
    if not class then return end
    local r, g, b = classColor(class)

    if mod.db.classColorHealth then
        local health = H.GetArenaBars(frame)
        if health then
            health:SetStatusBarColor(r, g, b)
            if health.SetForceStatusColor then health:SetForceStatusColor(r, g, b) end
        end
    end

    if mod.db.classColorName then
        local nameText = H.GetNameText(frame)
        if nameText then nameText:SetTextColor(r, g, b) end
    end

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

local function restoreFrame(frame, i)
    local unit = H.GetUnit(i)
    local health = H.GetArenaBars(frame)
    if health then
        health:SetStatusBarColor(0, 1, 0)
    end
    local nameText = H.GetNameText(frame)
    if nameText then nameText:SetTextColor(1, 0.82, 0) end

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

mod:OnArenaFramesReady(function(frame, i)
    applyToFrame(frame, i)
end)

-- Blizzard rewrites the bar color on every player update, so re-apply after it.
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
        -- deliberately not hooked: _UpdatePlayer covers it
    end
end

local function ev_UNIT_PORTRAIT_UPDATE(_, unit)
    if not mod._enabled then return end
    if unit and unit:match("^arena[1-5]$") then
        local i = tonumber(unit:match("arena(%d)"))
        local frame = H.Frame(i)
        if frame then applyToFrame(frame, i) end
    end
end
mod.RegEvent("UNIT_PORTRAIT_UPDATE", ev_UNIT_PORTRAIT_UPDATE)

local function ev_ARENA_OPPONENT_UPDATE()
    if not mod._enabled then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, applyAll)
    else
        applyAll()
    end
end
mod.RegEvent("ARENA_OPPONENT_UPDATE", ev_ARENA_OPPONENT_UPDATE)

mod:RegisterOnEnable(function()
    installHooks()
end)

mod:AddOptionsSection("classcolor", function()
    return {
        { type = "header", text = L["Class Visuals"] },
        {
            type = "checkbox", label = L["Class-colored health bars"],
            tooltip = L["Colors the health bar in the player's class color."],
            get = function() return mod.db.classColorHealth end,
            set = function(_, v)
                mod.db.classColorHealth = v
                -- restore-then-reapply so turning one toggle off keeps the others intact
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
                if v then applyAll() else restoreAll(); applyAll() end
            end,
        },
    }
end)

end)(...);

(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

-- spellId -> shared PvP trinket CD. Stoneform (20594) is excluded: it does not share this cooldown.
local TRINKET_SPELLS = {
    [42292] = 120,  -- PvP Trinket
    [7744]  = 120,  -- Will of the Forsaken
    [59752] = 120,  -- Every Man for Himself
}

-- texture path, not atlas: atlases are unreliable on this client
local TRINKET_TEXTURE = "Interface\\Icons\\INV_Jewelry_TrinketPVP_02"

local trinketFrames = {}

local function createTrinketFrame(parent, slotIndex)
    local f = CreateFrame("Frame", "VCUIArenaTrinket" .. slotIndex, parent)
    f:SetSize(mod.db.trinketSize or 28, mod.db.trinketSize or 28)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexture(TRINKET_TEXTURE)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(0, 0, 0, 0.8)
    f.border:SetDrawLayer("BACKGROUND")

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(true)
    f.cd:SetHideCountdownNumbers(false)
    if mod.StyleCooldown then mod.StyleCooldown(f.cd) end

    f:EnableMouse(false)

    f:Hide()
    return f
end

local function ensureTrinketFrame(arenaFrame, i)
    if trinketFrames[i] then return trinketFrames[i] end
    local tf = createTrinketFrame(arenaFrame, i)
    trinketFrames[i] = tf
    return tf
end

-- Second in the side strip: right next to the racial, one step further out.
mod.RegisterSideIcon(20, function(arenaFrame, i)
    if not mod.db.trinketEnabled then return nil end
    local tf = ensureTrinketFrame(arenaFrame, i)
    tf:SetSize(mod.db.trinketSize, mod.db.trinketSize)
    return tf, mod.db.trinketSize
end)

local function applyToFrame(arenaFrame, i)
    local tf = ensureTrinketFrame(arenaFrame, i)
    mod.LayoutSideIcons(arenaFrame, i)
    if mod.db.trinketEnabled then
        tf:Show()
        if mod:IsUnlocked() then
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

local activeCDs = {}

-- Audible + visible confirmation that a trinket just went. Deliberately short:
-- an alert you have to look at defeats the point of having one.
function mod.OnTrinketUsed(tf, unit)
    if mod.db.trinketSound then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
    if not (mod.db.trinketGlow and tf) then return end
    if not tf.glow then
        local g = tf:CreateTexture(nil, "OVERLAY", nil, 2)
        g:SetPoint("TOPLEFT", tf, "TOPLEFT", -4, 4)
        g:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", 4, -4)
        g:SetTexture("Interface\\Buttons\\WHITE8X8")
        g:SetBlendMode("ADD")
        g:Hide()
        tf.glow = g
    end
    tf.glow:SetVertexColor(1, 0.9, 0.4, 0.75)
    tf.glow:Show()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() if tf.glow then tf.glow:Hide() end end)
    end
end

local function startCooldown(unit, duration)
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local arenaFrame = H.Frame(i)
    if not arenaFrame then return end
    local tf = ensureTrinketFrame(arenaFrame, i)
    mod.LayoutSideIcons(arenaFrame, i)

    -- Only a genuinely new use gets the alert; the API refresh re-arms the same
    -- cooldown repeatedly and would otherwise beep every few seconds.
    local prev = activeCDs[unit]
    local fresh = not (prev and prev.start + prev.duration > GetTime())

    tf.cd:SetCooldown(GetTime(), duration)
    tf.icon:SetDesaturated(true)
    if mod.db.trinketEnabled then tf:Show() end

    activeCDs[unit] = { start = GetTime(), duration = duration }
    if fresh then mod.OnTrinketUsed(tf, unit) end

    if C_Timer and C_Timer.After then
        C_Timer.After(duration + 0.1, function()
            if activeCDs[unit] and activeCDs[unit].start + activeCDs[unit].duration <= GetTime() then
                tf.icon:SetDesaturated(false)
                activeCDs[unit] = nil
            end
        end)
    end
end

-- The client knows the real remaining cooldown, including uses you never saw
-- (out of range, behind a pillar, or before you loaded in). The combat log stays
-- as a fallback for when the API has nothing yet.
local function apiTrinketAvailable()
    return C_PvP and C_PvP.GetArenaCrowdControlInfo and C_PvP.RequestCrowdControlSpell
end

local function requestTrinketInfo()
    if not apiTrinketAvailable() then return end
    for i = 1, 5 do
        local unit = ns.ARENA_UNITS[i]
        if UnitExists(unit) then pcall(C_PvP.RequestCrowdControlSpell, unit) end
    end
end

-- Returns startTime/duration in seconds, or nil when the client has nothing.
local function apiTrinketCooldown(unit)
    if not apiTrinketAvailable() then return nil end
    local ok, spellID, _, startMs, durMs = pcall(C_PvP.GetArenaCrowdControlInfo, unit)
    if not ok or not spellID then return nil end
    -- 0/0 means "the client has no cooldown payload yet", NOT "the trinket is
    -- up". Treating it as up wipes a cooldown we already tracked from the
    -- combat log the moment any other opponent triggers a refresh.
    if not (startMs and durMs) or startMs == 0 or durMs == 0 then return nil end
    return startMs / 1000, durMs / 1000
end

local function refreshTrinketFromAPI(unit)
    if not mod.db.trinketEnabled then return end
    local i = tonumber(unit and unit:match("^arena(%d)$") or "")
    if not i then return end
    local start, dur = apiTrinketCooldown(unit)
    if not start then return end
    local arenaFrame = H.Frame(i)
    if not arenaFrame then return end
    local tf = ensureTrinketFrame(arenaFrame, i)
    mod.LayoutSideIcons(arenaFrame, i)
    -- the API re-reports the same cooldown on every refresh; only a start time
    -- we have not tracked yet counts as an actual use
    local prev = activeCDs[unit]
    local fresh = not (prev and math.abs((prev.start or 0) - start) < 1)
    tf.cd:SetCooldown(start, dur)
    tf.icon:SetDesaturated(true)
    activeCDs[unit] = { start = start, duration = dur }
    if fresh and (GetTime() - start) < 3 then mod.OnTrinketUsed(tf, unit) end
    -- without this the swipe finishes but the icon stays grey until some later
    -- event happens to fire, so a trinket that is back up still reads as down
    local left = (start + dur) - GetTime()
    if left > 0 and C_Timer and C_Timer.After then
        C_Timer.After(left + 0.1, function()
            local cur = activeCDs[unit]
            if not cur or cur.start + cur.duration <= GetTime() then
                tf.icon:SetDesaturated(false)
                activeCDs[unit] = nil
            end
        end)
    end
    tf:Show()
end

local function refreshAllTrinketsFromAPI()
    for i = 1, 5 do
        local unit = ns.ARENA_UNITS[i]
        if UnitExists(unit) then refreshTrinketFromAPI(unit) end
    end
end

local function onCombatLog()
    local _, subevent, _, sourceGUID, _, _, _, _, _, _, _, spellId =
        CombatLogGetCurrentEventInfo()

    if subevent ~= "SPELL_CAST_SUCCESS" then return end
    if not TRINKET_SPELLS[spellId] then return end

    for i = 1, 5 do
        local unit = ns.ARENA_UNITS[i]
        if UnitExists(unit) and UnitGUID(unit) == sourceGUID then
            startCooldown(unit, TRINKET_SPELLS[spellId])
            return
        end
    end
end

local function resetAllCDs()
    activeCDs = {}
    for i, tf in pairs(trinketFrames) do
        if tf and tf.cd then
            tf.cd:Clear()
            tf.icon:SetDesaturated(false)
        end
    end
end

mod:OnArenaFramesReady(function(frame, i)
    applyToFrame(frame, i)
end)

-- named handler so the very hot combat log stays registered only inside arenas
local function onCLEU()
    if not mod._enabled or not mod.db.trinketEnabled then return end
    onCombatLog()
end

local function setCombatLog(active)
    mod.SetDynEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU, active)
end

local function ev_PLAYER_ENTERING_WORLD()
    -- The handlers of this file are registered at LOAD, so a module that was
    -- never enabled still gets them. Without this guard a switched-off module
    -- subscribes to the combat log on entering an arena.
    if not mod._enabled then return end
    local inArena = false
    if IsInInstance then
        local _, instanceType = IsInInstance()
        inArena = (instanceType == "arena")
    end
    if not inArena then resetAllCDs() end
    setCombatLog(inArena)
    if inArena and C_Timer and C_Timer.After then
        -- opponents are not visible in the TBC prep room; ask again once the
        -- gates are open and the units actually exist
        C_Timer.After(2, requestTrinketInfo)
        C_Timer.After(6, function() requestTrinketInfo(); refreshAllTrinketsFromAPI() end)
    end
end
mod.RegEvent("PLAYER_ENTERING_WORLD", ev_PLAYER_ENTERING_WORLD)
-- Enabling counts as arriving: the zone decision lived in the loading screen
-- alone, so a module switched on INSIDE an arena took no combat log until the
-- next one. It also re-decides after a disable, which is what keeps a stale
-- "wanted" subscription from being restored in the wrong zone.
mod:RegisterOnEnable(ev_PLAYER_ENTERING_WORLD)
local function ev_ARENA_OPPONENT_UPDATE_2(_, unit, eventType)
    if eventType == "seen" then
        -- Ask the client what it knows; one opponent walking into view must not
        -- wipe the cooldowns we are already tracking for the others.
        if apiTrinketAvailable() then
            requestTrinketInfo()
            if unit then refreshTrinketFromAPI(unit) end
        end
    end
end
mod.RegEvent("ARENA_OPPONENT_UPDATE", ev_ARENA_OPPONENT_UPDATE_2)

-- On this client ARENA_COOLDOWNS_UPDATE fires with no unit at all, so the
-- refresh has to cover every opponent rather than keying off the argument.
local function ev_ARENA_COOLDOWNS_UPDATE(_, unit)
    if not mod.db.trinketEnabled then return end
    if unit then refreshTrinketFromAPI(unit) else refreshAllTrinketsFromAPI() end
end
mod.RegEvent("ARENA_COOLDOWNS_UPDATE", ev_ARENA_COOLDOWNS_UPDATE)

local function ev_ARENA_CROWD_CONTROL_SPELL_UPDATE(_, unit)
    if unit then refreshTrinketFromAPI(unit) end
end
mod.RegEvent("ARENA_CROWD_CONTROL_SPELL_UPDATE", ev_ARENA_CROWD_CONTROL_SPELL_UPDATE)

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
        { type = "desc", text = L["Where it sits is set once for all three trackers under Layout, Icon Strip."] },
        {
            type = "checkbox", label = L["Sound"],
            tooltip = L["Plays a raid warning sound the moment an opponent uses their PvP trinket."],
            get = function() return mod.db.trinketSound end,
            set = function(_, v) mod.db.trinketSound = v end,
        },
        {
            type = "checkbox", label = L["Glow"],
            tooltip = L["Flashes the icon briefly when an opponent uses their PvP trinket."],
            get = function() return mod.db.trinketGlow end,
            set = function(_, v) mod.db.trinketGlow = v end,
        },
    }
end)

end)(...);

(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule

local DR_RESET_TIME = 18

-- spellId -> DR category. ONE id per spell is enough and most of these are the
-- rank-one id: the ranks are picked up by name at the gate (see drCategory), so
-- nothing here has to be kept complete by hand.
local DR_SPELLS = {
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

    [2094]  = "disorient",     -- Blind

    [5782]  = "fear",          -- Fear (Warlock)
    [6358]  = "fear",          -- Seduction (Succubus)
    [5484]  = "fear",          -- Howl of Terror
    [8122]  = "fear",          -- Psychic Scream
    [5246]  = "fear",          -- Intimidating Shout
    [10326] = "fear",          -- Turn Evil

    [15487] = "silence",       -- Silence (Priest)
    [18498] = "silence",       -- Silenced (Warrior Shield Bash effect)
    [24259] = "silence",       -- Spell Lock
    [25046] = "silence",       -- Arcane Torrent (Blood Elf racial)

    [122]   = "root",          -- Frost Nova
    [339]   = "root",          -- Entangling Roots
    [19185] = "root",          -- Entrapment
    [13099] = "root",          -- Net-o-Matic

    [33786] = "cyclone",       -- Cyclone
}

-- drState[unit][category] = { applied, expires, appliedTime }
local drState = {}

local drFrames = {}

-- Widest the row can get: one icon per DR category we track, plus the 2px gap
-- updateDRDisplay leaves between them. Derived rather than a fixed 120, so the
-- strip reserves what the size slider actually asks for.
local DR_MAX_ICONS = 6
local function drRowWidth()
    local size = mod.db.drSize or 24
    return DR_MAX_ICONS * size + (DR_MAX_ICONS - 1) * 2
end

local function createDRContainer(parent, slotIndex)
    local container = CreateFrame("Frame", "VCUIArenaDR" .. slotIndex, parent)
    container:SetSize(drRowWidth(), mod.db.drSize or 24)
    container.icons = {}
    return container
end

local function ensureDRContainer(arenaFrame, i)
    local container = drFrames[i]
    if not container then
        container = createDRContainer(arenaFrame, i)
        drFrames[i] = container
    end
    return container
end

-- Last in the side strip: the row is the widest of the three and grows as more
-- categories come up, so it goes furthest from the frame.
mod.RegisterSideIcon(30, function(arenaFrame, i)
    if not mod.db.drEnabled then return nil end
    local container = ensureDRContainer(arenaFrame, i)
    local w = drRowWidth()
    container:SetSize(w, mod.db.drSize or 24)
    return container, w
end)

local function createDRIcon(parent, category)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(mod.db.drSize or 24, mod.db.drSize or 24)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    f.border:SetColorTexture(0, 1, 0, 1)
    f.border:SetDrawLayer("BACKGROUND")

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(true)

    f.category = category
    f:Hide()
    return f
end

-- level: 1 = full, 2 = half, 3 = quarter, 4 = immune
local function getDRColor(level)
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

-- Hoisted, and the list is refilled rather than rebuilt: this runs twice a
-- second for every tracked opponent, so a comparator closure and a fresh table
-- per pass are rubbish the player pays for in an arena.
local function byCategory(a, b) return a.cat < b.cat end
local visible = {}

local function updateDRDisplay(unit)
    if not mod.db.drEnabled then return end
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local arenaFrame = mod.helpers.Frame(i)
    if not arenaFrame then return end

    local container = ensureDRContainer(arenaFrame, i)

    local state = drState[unit] or {}
    local now = GetTime()
    local n = 0
    for cat, data in pairs(state) do
        if data.expires > now then
            n = n + 1
            local slot = visible[n]
            if slot then
                slot.cat, slot.data = cat, data
            else
                visible[n] = { cat = cat, data = data }
            end
        end
    end
    for k = n + 1, #visible do visible[k] = nil end
    table.sort(visible, byCategory)

    -- Placed once, not on every tick. The row reserves the width of a FULL set
    -- of categories (drRowWidth), so its position cannot move as icons come and
    -- go -- and every setting that could move it goes through RefreshSideIcons
    -- already. This used to run three getters, three pcalls and an anchor pass
    -- per opponent, twice a second, to arrive at the same spot every time.
    if not container._placed then
        container._placed = true
        mod.LayoutSideIcons(arenaFrame, i)
    end

    for _, icon in pairs(container.icons) do icon:Hide() end

    -- On the left edge the row has to grow away from the frame, or a second
    -- icon would be laid straight across the health bar.
    local leftSide = not mod.IsSideStripRight()

    local size = mod.db.drSize or 24
    local x = 0
    for vi = 1, #visible do
        local entry = visible[vi]
        local icon = container.icons[entry.cat]
        if not icon then
            icon = createDRIcon(container, entry.cat)
            container.icons[entry.cat] = icon
        end
        -- Anchors only when they actually differ: two of these three values are
        -- the same on every tick of a running row.
        if icon._size ~= size or icon._x ~= x or icon._left ~= leftSide then
            icon._size, icon._x, icon._left = size, x, leftSide
            icon:SetSize(size, size)
            icon:ClearAllPoints()
            if leftSide then
                icon:SetPoint("RIGHT", container, "RIGHT", -x, 0)
            else
                icon:SetPoint("LEFT", container, "LEFT", x, 0)
            end
        end

        -- resolved once per icon; the 0.5s ticker must not rescan DR_SPELLS
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
        if icon._level ~= level then
            icon._level = level
            icon.border:SetColorTexture(getDRColor(level))
        end

        -- The swipe is re-armed only when the effect was actually re-applied.
        -- Setting the same cooldown twice a second makes it stutter -- the same
        -- fault the interrupt bar carries a guard against, one capsule down.
        local appliedAt = entry.data.appliedTime
        if icon._cdStart ~= appliedAt then
            icon._cdStart = appliedAt
            icon.cd:SetCooldown(appliedAt, DR_RESET_TIME)
        end
        icon:Show()

        x = x + size + 2
    end
end

-- Moving a slider outside an arena has no live state to redraw, so the frames
-- that already exist are re-anchored directly.
function mod.RefreshDR()
    mod.RefreshSideIcons()
    for unit in pairs(drState) do updateDRDisplay(unit) end
end

-- Rank two and up used to be invisible to the tracker.
--
-- DR_SPELLS is a list of ids, and every rank of a spell has its OWN id: the table
-- carries Polymorph 118 and Sap 6770, which are the RANK ONE ids, so the ranks a
-- level 70 actually casts fell straight through the gate and no icon ever
-- appeared. (The comment above the table claimed the opposite.) Writing the
-- missing ids in by hand would be guessing at numbers I cannot verify here, and
-- the list would go stale again with the next spell anyway.
--
-- So the CLIENT supplies them. Every rank of a spell shares its NAME, and
-- GetSpellInfo answers the name for an id the client knows -- so one pass over
-- the ids we already have yields a name table that covers every rank at once,
-- in the client's own language, which is also the language the combat log speaks.
-- Built on first use, not at load: spell data is not reliably readable then.
local DR_BY_NAME
local function drCategory(spellId, spellName)
    local cat = DR_SPELLS[spellId]
    if cat then return cat end
    if not spellName or not GetSpellInfo then return nil end
    if not DR_BY_NAME then
        DR_BY_NAME = {}
        for id, c in pairs(DR_SPELLS) do
            local n = GetSpellInfo(id)
            -- First id wins for a name. Two categories under one name would be a
            -- table bug, not a rank -- and silently picking the later one would
            -- hide it.
            if n and DR_BY_NAME[n] == nil then DR_BY_NAME[n] = c end
        end
    end
    return DR_BY_NAME[spellName]
end

local function onAuraApplied(destUnit, spellId, spellName)
    local cat = drCategory(spellId, spellName)
    if not cat then return end

    drState[destUnit] = drState[destUnit] or {}
    local entry = drState[destUnit][cat]
    if not entry then
        entry = { applied = 0, expires = 0, appliedTime = 0 }
        drState[destUnit][cat] = entry
    end

    if entry.expires < GetTime() then
        entry.applied = 0
    end

    entry.applied = math.min(entry.applied + 1, 4)
    entry.appliedTime = GetTime()
    entry.expires = GetTime() + DR_RESET_TIME

    updateDRDisplay(destUnit)
end

local function onCombatLog()
    local _, subevent, _, _, _, _, _, destGUID, _, _, _, spellId, spellName =
        CombatLogGetCurrentEventInfo()

    if subevent ~= "SPELL_AURA_APPLIED" and subevent ~= "SPELL_AURA_REFRESH" then return end
    -- The same gate the handler uses, so a rank that only the NAME knows is not
    -- dropped here before it ever gets there.
    if not drCategory(spellId, spellName) then return end

    for i = 1, 5 do
        local unit = ns.ARENA_UNITS[i]
        if UnitExists(unit) and UnitGUID(unit) == destGUID then
            onAuraApplied(unit, spellId, spellName)
            return
        end
    end
end

-- Expiry sweep for the diminishing-returns icons, on the shared ticker. The
-- private frame this replaced was already hidden outside arenas, so this is not
-- a per-frame saving -- it is one driver instead of one frame per module, and a
-- cancel that the module's own disable path can reach.
local updaterTicker
local function drTick()
    if not mod.db.drEnabled or not mod._enabled then return end
    for unit in pairs(drState) do
        updateDRDisplay(unit)
    end
end
local function ensureUpdater()
    if updaterTicker then return end
    updaterTicker = ns:AddTicker(0.5, drTick, nil, "arena-dr")
end

local function resetAll()
    drState = {}
    if updaterTicker then
        ns:CancelTicker(updaterTicker)
        updaterTicker = nil
    end
    for _, container in pairs(drFrames) do
        for _, icon in pairs(container.icons) do icon:Hide() end
    end
end

-- Switching the module off inside an arena used to leave the ticker subscribed:
-- the zone change that would have cleared it arrives through an event this
-- module just unregistered. One orphan is enough to keep the SHARED driver
-- shown for the rest of the session, so this is the one cancel that must not
-- depend on the player walking out.
mod:RegisterOnDisable(resetAll)

-- named handler so the very hot combat log stays registered only inside arenas
local function onCLEU()
    if not mod._enabled or not mod.db.drEnabled then return end
    onCombatLog()
end

local function setCombatLog(active)
    mod.SetDynEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU, active)
end

local function ev_PLAYER_ENTERING_WORLD_2()
    -- see the trinket capsule: file-scope registration means a module that is
    -- off still receives this, and it would start a ticker and take the combat
    -- log for a feature nobody switched on
    if not mod._enabled then return end
    resetAll()
    local inArena = false
    if IsInInstance then
        local _, instanceType = IsInInstance()
        inArena = (instanceType == "arena")
    end
    if inArena then ensureUpdater() end
    setCombatLog(inArena)
end
mod.RegEvent("PLAYER_ENTERING_WORLD", ev_PLAYER_ENTERING_WORLD_2)
-- Same as the trinket capsule: enabling inside an arena has to arm the expiry
-- ticker and the combat log, not wait for the next loading screen.
mod:RegisterOnEnable(ev_PLAYER_ENTERING_WORLD_2)

mod:AddOptionsSection("dr", function()
    return {
        { type = "header", text = L["Diminishing Returns Tracker"] },
        { type = "desc",   text = L["Shows icons next to each arena frame for active DR categories (Stun, Fear, Polymorph etc.) with color indicator: |cff00ff00green|r = full, |cffffff00yellow|r = 1/2, |cffff8000orange|r = 1/4, |cffff0000red|r = immune."] },
        {
            type = "checkbox", label = L["Enable DR tracking"],
            get = function() return mod.db.drEnabled end,
            set = function(_, v)
                mod.db.drEnabled = v
                if not v then
                    resetAll()
                elseif IsInInstance and select(2, IsInInstance()) == "arena" then
                    -- resetAll hid the expiry ticker; toggle-on mid-arena must revive it
                    ensureUpdater()
                end
            end,
        },
        {
            type = "slider", label = L["Icon size"],
            min = 16, max = 40, step = 1,
            get = function() return mod.db.drSize end,
            set = function(_, v) mod.db.drSize = v; mod.RefreshDR() end,
        },
        { type = "desc", text = L["Where it sits is set once for all three trackers under Layout, Icon Strip."] },
    }
end)

end)(...);

(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

local castbars = {}

local function createCastbar(parent, slotIndex)
    local f = CreateFrame("StatusBar", "VCUIArenaCastbar" .. slotIndex, parent, "BackdropTemplate")
    f:SetSize(mod.db.castbarWidth, mod.db.castbarHeight)
    f:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f:SetStatusBarColor(1.0, 0.7, 0.0)
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetColorTexture(0, 0, 0, 0.7)

    f:SetBackdrop({
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetSize(mod.db.castbarHeight, mod.db.castbarHeight)
    f.icon:SetPoint("RIGHT", f, "LEFT", -2, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("LEFT",  f, "LEFT",   4, 0)
    f.text:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    f.text:SetJustifyH("LEFT")

    f.timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.timer:SetPoint("RIGHT", f, "RIGHT", -4, 0)

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

local function castbarOnUpdate(self, elapsed)
    if not self.casting and not self.channeling then
        self:Hide()
        return
    end
    local now = GetTime()
    local total = self.endTime - self.startTime
    if total <= 0 then total = 0.01 end  -- instant casts report startTime == endTime
    local progress
    if self.channeling then
        progress = (self.endTime - now) / total
    else
        progress = (now - self.startTime) / total
    end
    progress = math.max(0, math.min(1, progress))
    self:SetValue(progress)

    -- text at 10 Hz is plenty; the bar fill above stays per-frame smooth.
    -- SetFormattedText formats C-side, so no Lua string per update either.
    self._textAcc = (self._textAcc or 0.1) + elapsed
    if self._textAcc >= 0.1 then
        self._textAcc = 0
        local remaining = self.endTime - now
        if remaining < 0 then remaining = 0 end
        self.timer:SetFormattedText("%.1f", remaining)
    end

    if now >= self.endTime then
        self.casting = false
        self.channeling = false
        self:Hide()
    end
end

local function startCast(unit, channeling)
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local arenaFrame = H.Frame(i)
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

    cb._hideToken = (cb._hideToken or 0) + 1   -- invalidates any pending interrupt-hide timer
    cb._interruptHold = nil
    cb._textAcc = 0.1                          -- paint the timer text on the first tick
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
        -- Freeze the bar: with casting/channeling false the OnUpdate would
        -- hide it on the very next frame, so the 0.7s display never showed.
        cb:SetScript("OnUpdate", nil)
        cb:SetStatusBarColor(1, 0, 0)
        cb.text:SetText(L["INTERRUPTED"])
        cb.timer:SetText("")
        cb._hideToken = (cb._hideToken or 0) + 1
        local token = cb._hideToken
        if C_Timer and C_Timer.After then
            -- The client fires UNIT_SPELLCAST_STOP right after INTERRUPTED;
            -- the hold keeps that stop from wiping the display early.
            cb._interruptHold = GetTime() + 0.7
            C_Timer.After(0.7, function() if cb._hideToken == token then cb:Hide() end end)
        else
            cb:Hide()
        end
    else
        if cb._interruptHold and GetTime() < cb._interruptHold then return end
        cb:Hide()
    end
end

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

local function isArenaUnit(unit)
    return unit and unit:match("^arena[1-5]$") ~= nil
end

mod:OnArenaFramesReady(function(frame, i)
    ensureCastbar(frame, i)
end)

local function ev_UNIT_SPELLCAST_START(_, unit)
    if not mod._enabled or not mod.db.castbarEnabled or not isArenaUnit(unit) then return end
    startCast(unit, false)
end
mod.RegEvent("UNIT_SPELLCAST_START", ev_UNIT_SPELLCAST_START)
local function ev_UNIT_SPELLCAST_CHANNEL_START(_, unit)
    if not mod._enabled or not mod.db.castbarEnabled or not isArenaUnit(unit) then return end
    startCast(unit, true)
end
mod.RegEvent("UNIT_SPELLCAST_CHANNEL_START", ev_UNIT_SPELLCAST_CHANNEL_START)
local function ev_UNIT_SPELLCAST_STOP(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, false)
end
mod.RegEvent("UNIT_SPELLCAST_STOP", ev_UNIT_SPELLCAST_STOP)
local function ev_UNIT_SPELLCAST_CHANNEL_STOP(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, false)
end
mod.RegEvent("UNIT_SPELLCAST_CHANNEL_STOP", ev_UNIT_SPELLCAST_CHANNEL_STOP)
local function ev_UNIT_SPELLCAST_INTERRUPTED(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, true)
end
mod.RegEvent("UNIT_SPELLCAST_INTERRUPTED", ev_UNIT_SPELLCAST_INTERRUPTED)
local function ev_UNIT_SPELLCAST_FAILED(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, false)
end
mod.RegEvent("UNIT_SPELLCAST_FAILED", ev_UNIT_SPELLCAST_FAILED)

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
            -- The dispel icon is anchored below the castbar and reads this same
            -- height, so it has to follow -- otherwise it sits on the bar until
            -- something else happens to re-place it.
            set = function(_, v)
                mod.db.castbarHeight = v
                refreshCastbars()
                if mod.RefreshDispels then mod.RefreshDispels() end
            end,
        },
    }
end)

end)(...);

-- =========================================================================
-- Racial cooldowns.
-- The cooldowns below are this expansion's values, which differ from later
-- ones: Perception is the Human racial (Will to Survive came later) and
-- Shadowmeld is a 10s crouch rather than a 2 minute cooldown. There is
-- deliberately NO shared cooldown with the PvP trinket -- that link did not
-- exist yet, and faking it would grey out a trinket the enemy can still use.
-- =========================================================================
(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule

local H = mod.helpers

local RACIAL_CD = {
    [20549] = 120,  -- War Stomp
    [7744]  = 120,  -- Will of the Forsaken
    [20554] = 180,  -- Berserking
    [26296] = 180,
    [26297] = 180,
    [20572] = 120,  -- Blood Fury (attack power)
    [33697] = 120,  -- Blood Fury (hybrid)
    [33702] = 120,  -- Blood Fury (spell power)
    [20589] = 105,  -- Escape Artist
    [20594] = 180,  -- Stoneform
    [20600] = 180,  -- Perception
    [20580] = 10,   -- Shadowmeld
    [28730] = 120,  -- Arcane Torrent (mana)
    [25046] = 120,  -- Arcane Torrent (energy)
    [28880] = 180,  -- Gift of the Naaru
}

-- One representative spell per race for the resting icon, shown before the
-- opponent has pressed anything.
local RACE_SPELL = {
    Tauren   = 20549, Scourge = 7744,  Troll = 26297, Orc      = 20572,
    Gnome    = 20589, Dwarf   = 20594, Human = 20600, NightElf = 20580,
    BloodElf = 28730, Draenei = 28880,
}

local racialFrames = {}

local function ensureRacialFrame(arenaFrame, i)
    local f = racialFrames[i]
    if f then return f end
    f = CreateFrame("Frame", "VCUIArenaRacial" .. i, arenaFrame)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(0, 0, 0, 0.8)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(true)
    if mod.StyleCooldown then mod.StyleCooldown(f.cd) end
    f:EnableMouse(false)
    f:Hide()
    racialFrames[i] = f
    return f
end

-- First in the side strip: closest to the frame, with the trinket right beside it.
mod.RegisterSideIcon(10, function(arenaFrame, i)
    if not mod.db.racialEnabled then return nil end
    local f = ensureRacialFrame(arenaFrame, i)
    f:SetSize(mod.db.racialSize, mod.db.racialSize)
    return f, mod.db.racialSize
end)

local function updateRacial(arenaFrame, i)
    local d = mod.db
    if not mod._enabled then return end
    local f = ensureRacialFrame(arenaFrame, i)
    mod.LayoutSideIcons(arenaFrame, i)
    if not d.racialEnabled then f:Hide(); return end
    local unit = ns.ARENA_UNITS[i]
    local race = UnitExists(unit) and select(2, UnitRace(unit)) or nil
    local spell = race and RACE_SPELL[race]
    if not spell then f:Hide(); return end
    local tex = GetSpellTexture and GetSpellTexture(spell)
    f.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    f:Show()
end

mod.RefreshRacials = function() H.ForEach(updateRacial) end
mod:OnArenaFramesReady(updateRacial)

function mod.RacialUsed(unit, spellId)
    local dur = RACIAL_CD[spellId]
    if not dur or not mod.db.racialEnabled then return end
    local i = tonumber(unit:match("^arena(%d)$") or "")
    local arenaFrame = i and H.Frame(i)
    if not arenaFrame then return end
    local f = ensureRacialFrame(arenaFrame, i)
    mod.LayoutSideIcons(arenaFrame, i)
    local tex = GetSpellTexture and GetSpellTexture(spellId)
    if tex then f.icon:SetTexture(tex) end
    f.cd:SetCooldown(GetTime(), dur)
    f.icon:SetDesaturated(true)
    f:Show()
    local token = (f._token or 0) + 1
    f._token = token
    if C_Timer and C_Timer.After then
        C_Timer.After(dur + 0.1, function()
            if f._token == token and f.icon then f.icon:SetDesaturated(false) end
        end)
    end
end

function mod.ResetRacials()
    for _, f in pairs(racialFrames) do
        f._token = (f._token or 0) + 1     -- invalidates any pending restore
        if f.cd then f.cd:Clear() end
        if f.icon then f.icon:SetDesaturated(false) end
    end
end

mod.RACIAL_CD = RACIAL_CD

mod:AddOptionsSection("racial", function()
    return {
        { type = "header", text = L["Racial Cooldowns"] },
        { type = "desc",   text = L["Shows the opponent's racial ability and its cooldown once they use it. These are this expansion's cooldowns, and no racial shares one with the PvP trinket yet."] },
        { type = "checkbox", label = L["Show racial cooldown"],
          get = function() return mod.db.racialEnabled end,
          set = function(_, v) mod.db.racialEnabled = v; mod.RefreshRacials() end },
        { type = "slider", label = L["Icon size"], min = 16, max = 48, step = 1,
          get = function() return mod.db.racialSize end,
          set = function(_, v) mod.db.racialSize = v; mod.RefreshRacials() end },
        { type = "desc", text = L["Where it sits is set once for all three trackers under Layout, Icon Strip."] },
    }
end)

end)(...);

-- =========================================================================
-- Shadow Sight timer. A mechanic of this expansion only: the two arena orbs
-- appear 95s after the gates open and each returns 122s after it is taken.
-- =========================================================================
(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule

local FIRST_SPAWN    = 95
local RESPAWN        = 122
local SHADOWSIGHT_ID = 34709

local orbs, holder, fs, ticker = { 0, 0 }, nil, nil, nil

local function ensureHolder()
    if holder then return holder end
    holder = CreateFrame("Frame", "VCUIArenaShadowsight", UIParent)
    holder:SetSize(260, 20)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -120)
    fs = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if ns.UI and ns.UI.Font then ns.UI.Font(fs, 14, "OUTLINE") end
    fs:SetPoint("CENTER", holder, "CENTER", 0, 0)
    fs:SetTextColor(0.75, 0.55, 1)
    holder:Hide()
    return holder
end

local function stopTimers()
    if ticker then ticker:Cancel(); ticker = nil end
    if holder then holder:Hide() end
end

local function tick()
    if not mod.db.shadowsightEnabled then stopTimers(); return end
    local now = GetTime()
    local ready, soonest = 0, nil
    for _, t in ipairs(orbs) do
        if t <= now then
            ready = ready + 1
        elseif not soonest or t < soonest then
            soonest = t
        end
    end
    if ready > 0 and soonest then
        fs:SetFormattedText(L["Shadow Sight up - next in %d s"], soonest - now)
    elseif ready > 0 then
        fs:SetText(L["Shadow Sight up"])
    elseif soonest then
        fs:SetFormattedText(L["Shadow Sight in %d s"], soonest - now)
    else
        fs:SetText("")
    end
    holder:Show()
end

local function startTimers()
    if not mod.db.shadowsightEnabled then return end
    ensureHolder()
    local first = GetTime() + FIRST_SPAWN
    orbs[1], orbs[2] = first, first
    if ticker then ticker:Cancel() end
    if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(0.2, tick) end
    tick()
end

-- One orb was taken: push whichever was already up, so the two run
-- independently exactly as the orbs themselves do.
local function orbTaken()
    local now = GetTime()
    for i, t in ipairs(orbs) do
        if t <= now then
            orbs[i] = now + RESPAWN
            return
        end
    end
end

mod.ShadowsightID    = SHADOWSIGHT_ID
mod.ShadowsightTaken = orbTaken
mod.StartShadowsight = startTimers
mod.StopShadowsight  = stopTimers

mod:AddOptionsSection("shadowsight", function()
    return {
        { type = "header", text = L["Shadow Sight"] },
        { type = "desc",   text = L["Counts down the arena orbs: the first pair appears 95 seconds after the gates open, and each one returns 122 seconds after it is taken."] },
        { type = "checkbox", label = L["Show Shadow Sight timer"],
          get = function() return mod.db.shadowsightEnabled end,
          set = function(_, v)
              mod.db.shadowsightEnabled = v
              if not v then stopTimers() end
          end },
    }
end)

end)(...);

-- =========================================================================
-- The single most relevant aura on the class icon: an immunity outranks crowd
-- control, which outranks a defensive, which outranks an offensive cooldown.
-- Showing every aura would only be a second, worse aura bar.
-- =========================================================================
(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule

local H = mod.helpers

local AURA_PRIO = {}
local function put(prio, cat, ...)
    for i = 1, select("#", ...) do
        AURA_PRIO[select(i, ...)] = { prio, cat }
    end
end

-- immunities and effects that make a cast pointless
put(10, "important", 23920, 45438, 642, 1022, 5599, 10278, 31224, 19263, 498, 1020)
-- crowd control
put(9, "cc", 118, 12824, 12825, 12826, 28271, 28272)
put(9, "cc", 5782, 6213, 6215, 5484, 5246, 8122, 8124, 10888, 10890)
put(9, "cc", 2094, 1833, 408, 1776, 6770, 2070, 11297, 6768)
put(9, "cc", 853, 5588, 5589, 10308, 20066)
put(9, "cc", 3355, 14308, 14309, 19503, 19410, 12809, 20253)
put(9, "cc", 339, 1062, 5195, 5196, 9852, 9853, 33786, 22570, 16979)
put(9, "cc", 6358, 6789, 17928, 30283, 31117, 24259)
-- silences and lockouts
put(6, "cc", 15487, 18469, 1330, 28730, 25046)
-- defensive cooldowns
put(5, "defensive", 871, 12975, 5277, 22812, 33206, 31821, 498, 1038)
-- drinking: a free opener
put(4, "important", 43183, 430, 431, 432, 1133, 1135, 1137)
-- offensive cooldowns
put(2, "offensive", 1719, 12472, 2825, 32182, 13750, 12292, 11129, 12042, 3045, 34471, 12328)

local CAT_COLOR = {
    cc        = { 0.85, 0.35, 1.00 },
    important = { 1.00, 0.85, 0.25 },
    defensive = { 0.35, 0.75, 1.00 },
    offensive = { 1.00, 0.45, 0.25 },
}

local auraFrames = {}

local function ensureAuraFrame(arenaFrame, i)
    local f = auraFrames[i]
    if f then return f end
    local portrait = H.GetPortrait(arenaFrame)
    f = CreateFrame("Frame", nil, arenaFrame)
    if portrait then
        f:SetAllPoints(portrait)
    else
        f:SetSize(28, 28)
        f:SetPoint("LEFT", arenaFrame, "LEFT", 4, 0)
    end
    f:SetFrameLevel(arenaFrame:GetFrameLevel() + 6)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- four edges, not a filled quad: a full-cover ADD texture washes the icon
    -- out instead of outlining it; colour is painted per aura in updateAuraIcon
    f.ring = ns.MakeEdges(f, "OVERLAY")
    ns.LayoutEdges(f.ring, f, 2, 0, 0, 0, 0.9, 2)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(false)
    if mod.StyleCooldown then mod.StyleCooldown(f.cd) end
    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -1)
    f:EnableMouse(false)
    f:Hide()
    auraFrames[i] = f
    return f
end

-- Highest priority wins; a tie goes to whichever lasts longer, so the icon does
-- not flicker between two auras of the same rank.
-- The filter list and the result table are hoisted: this runs per UNIT_AURA
-- and the consumer reads the result immediately, so one shared table suffices.
local AURA_FILTERS = { "HELPFUL", "HARMFUL" }
local _bestAura = {}
local function bestAura(unit)
    local found, bestPrio, bestLeft = false, nil, nil
    for fi = 1, #AURA_FILTERS do
        local filter = AURA_FILTERS[fi]
        for i = 1, 40 do
            local name, icon, count, _, duration, expires, _, _, _, spellId =
                UnitAura(unit, i, filter)
            if not name then break end
            local e = spellId and AURA_PRIO[spellId]
            if e and (not mod.db.auraOnlyCC or e[2] == "cc") then
                local left = (expires or 0) > 0 and (expires - GetTime()) or 9999
                if (not found) or e[1] > bestPrio or (e[1] == bestPrio and left > bestLeft) then
                    found = true
                    _bestAura.icon, _bestAura.count = icon, count or 0
                    _bestAura.duration, _bestAura.expires = duration or 0, expires or 0
                    _bestAura.cat = e[2]
                    bestPrio, bestLeft = e[1], left
                end
            end
        end
    end
    return found and _bestAura or nil
end

local function updateAuraIcon(arenaFrame, i)
    if not mod._enabled then return end
    local f = ensureAuraFrame(arenaFrame, i)
    if not mod.db.auraIconEnabled then f:Hide(); return end
    local unit = ns.ARENA_UNITS[i]
    if not UnitExists(unit) then f:Hide(); return end
    local a = bestAura(unit)
    if not a then f:Hide(); return end
    f.icon:SetTexture(a.icon)
    local c = CAT_COLOR[a.cat] or CAT_COLOR.important
    for _, t in pairs(f.ring) do t:SetColorTexture(c[1], c[2], c[3], 0.9) end
    if a.duration > 0 and a.expires > 0 then
        f.cd:SetCooldown(a.expires - a.duration, a.duration)
        f.cd:Show()
    else
        f.cd:Hide()
    end
    f.count:SetText(a.count > 1 and a.count or "")
    f:Show()
end

mod.RefreshAuraIcons = function() H.ForEach(updateAuraIcon) end
mod:OnArenaFramesReady(updateAuraIcon)

function mod.AuraIconUpdate(unit)
    local i = tonumber(unit and unit:match("^arena(%d)$") or "")
    local arenaFrame = i and H.Frame(i)
    if arenaFrame then updateAuraIcon(arenaFrame, i) end
end

mod:AddOptionsSection("auraicon", function()
    return {
        { type = "header", text = L["Aura on the class icon"] },
        { type = "desc",   text = L["Puts the single most relevant aura on the opponent's class icon: an immunity outranks crowd control, which outranks a defensive, which outranks an offensive cooldown."] },
        { type = "checkbox", label = L["Show aura on the class icon"],
          get = function() return mod.db.auraIconEnabled end,
          set = function(_, v) mod.db.auraIconEnabled = v; mod.RefreshAuraIcons() end },
        { type = "checkbox", label = L["Crowd control only"],
          get = function() return mod.db.auraOnlyCC end,
          set = function(_, v) mod.db.auraOnlyCC = v; mod.RefreshAuraIcons() end },
    }
end)

end)(...);

-- =========================================================================
-- Dispel cooldowns.
-- Almost nothing to track in this expansion: Dispel Magic, Cleanse, Purify,
-- Remove Curse and Abolish Poison all have NO cooldown. Only Mass Dispel and
-- the felhunter's Devour Magic do, so this row stays quiet most of the time --
-- which is why it ships off by default rather than looking broken.
-- =========================================================================
(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule

local H = mod.helpers

local DISPEL_CD = {
    [32375] = 15,   -- Mass Dispel
    [19505] = 8,    -- Devour Magic (pet), ranks below
    [19731] = 8,
    [19734] = 8,
    [19736] = 8,
    [27276] = 8,
    [27277] = 8,
}

local dispelFrames = {}

local function ensureDispelFrame(arenaFrame, i)
    local f = dispelFrames[i]
    if f then return f end
    f = CreateFrame("Frame", nil, arenaFrame)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(0, 0, 0, 0.8)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(true)
    if mod.StyleCooldown then mod.StyleCooldown(f.cd) end
    f:EnableMouse(false)
    f:Hide()
    dispelFrames[i] = f
    return f
end

local function layoutDispel(f, arenaFrame)
    local d = mod.db
    f:SetSize(d.dispelSize, d.dispelSize)
    f:ClearAllPoints()
    -- below the castbar slot, which also sits under the frame
    f:SetPoint("TOP", arenaFrame, "BOTTOM", 0, -(mod.db.castbarHeight or 14) - 6)
end

local function updateDispel(arenaFrame, i)
    if not mod._enabled then return end
    local f = ensureDispelFrame(arenaFrame, i)
    layoutDispel(f, arenaFrame)
    if not mod.db.dispelEnabled then f:Hide() end
end

mod.RefreshDispels = function() H.ForEach(updateDispel) end
mod:OnArenaFramesReady(updateDispel)

function mod.DispelUsed(unit, spellId)
    local dur = DISPEL_CD[spellId]
    if not dur or not mod.db.dispelEnabled then return end
    local i = tonumber(unit:match("^arena(%d)$") or "")
    local arenaFrame = i and H.Frame(i)
    if not arenaFrame then return end
    local f = ensureDispelFrame(arenaFrame, i)
    layoutDispel(f, arenaFrame)
    local tex = GetSpellTexture and GetSpellTexture(spellId)
    f.icon:SetTexture(tex or "Interface\\Icons\\Spell_Holy_DispelMagic")
    f.cd:SetCooldown(GetTime(), dur)
    f:Show()
    local token = (f._token or 0) + 1
    f._token = token
    if C_Timer and C_Timer.After then
        C_Timer.After(dur + 0.1, function()
            if f._token == token then f:Hide() end
        end)
    end
end

function mod.ResetDispels()
    for _, f in pairs(dispelFrames) do
        f._token = (f._token or 0) + 1
        if f.cd then f.cd:Clear() end
        f:Hide()
    end
end

mod.DISPEL_CD = DISPEL_CD

mod:AddOptionsSection("dispel", function()
    return {
        { type = "header", text = L["Dispel Cooldowns"] },
        { type = "desc",   text = L["|cffaaaaaaMost dispels have no cooldown in this expansion, so only Mass Dispel and the felhunter's Devour Magic can ever show up here.|r"] },
        { type = "checkbox", label = L["Show dispel cooldown"],
          get = function() return mod.db.dispelEnabled end,
          set = function(_, v) mod.db.dispelEnabled = v; mod.RefreshDispels() end },
        { type = "slider", label = L["Icon size"], min = 14, max = 40, step = 1,
          get = function() return mod.db.dispelSize end,
          set = function(_, v) mod.db.dispelSize = v; mod.RefreshDispels() end },
    }
end)

end)(...);

-- =========================================================================
-- Range indicator: the frame fades when the opponent is out of reach of a
-- spell your class actually has. Checked against a real spell rather than a
-- hardcoded yardage, so the answer matches what the server will allow.
-- =========================================================================
(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule

local H = mod.helpers

-- One reliable, always-known spell per class, chosen for a useful range.
local RANGE_SPELL_ID = {
    -- Deliberately no Charge or Auto Shot: both have a MINIMUM range, so they
    -- report out-of-range while you are stood in melee, i.e. exactly backwards.
    WARRIOR = 772,   -- Rend, melee
    ROGUE   = 2094,  -- Blind, 10y
    HUNTER  = 2973,  -- Raptor Strike, melee
    MAGE    = 133,   -- Fireball, 35y
    PRIEST  = 585,   -- Smite, 30y
    WARLOCK = 686,   -- Shadow Bolt, 30y
    DRUID   = 5176,  -- Wrath, 30y
    SHAMAN  = 403,   -- Lightning Bolt, 30y
    PALADIN = 20271, -- Judgement, 10y
}

local rangeSpellName
local function resolveRangeSpell()
    local _, class = UnitClass("player")
    local id = class and RANGE_SPELL_ID[class]
    rangeSpellName = id and GetSpellInfo and GetSpellInfo(id) or nil
end

local function inRange(unit)
    if not rangeSpellName or not IsSpellInRange then return true end
    local r = IsSpellInRange(rangeSpellName, unit)
    if r == nil then return true end          -- spell cannot answer for this unit
    return r == 1
end

local ticker

local function applyRange()
    if not (mod._enabled and mod.db.rangeEnabled) then return end
    H.ForEach(function(frame, i)
        local unit = ns.ARENA_UNITS[i]
        if not UnitExists(unit) then return end
        frame:SetAlpha(inRange(unit) and 1 or (mod.db.rangeAlpha or 0.45))
    end)
end

local function startRange()
    if ticker or not mod.db.rangeEnabled then return end
    resolveRangeSpell()
    if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(0.2, applyRange) end
end

local function stopRange()
    if ticker then ticker:Cancel(); ticker = nil end
    H.ForEach(function(frame) frame:SetAlpha(1) end)
end

mod.StartRangeCheck = startRange
mod.StopRangeCheck  = stopRange

ns:RegisterEvent("SPELLS_CHANGED", resolveRangeSpell)

mod:AddOptionsSection("range", function()
    return {
        { type = "header", text = L["Range"] },
        { type = "desc",   text = L["Fades the frame while the opponent is out of reach, measured with a spell your class knows rather than a fixed distance."] },
        { type = "checkbox", label = L["Fade out-of-range opponents"],
          get = function() return mod.db.rangeEnabled end,
          set = function(_, v)
              mod.db.rangeEnabled = v
              if v then startRange() else stopRange() end
          end },
        { type = "slider", label = L["Faded opacity"], min = 10, max = 90, step = 5,
          get = function() return math.floor((mod.db.rangeAlpha or 0.45) * 100) end,
          set = function(_, v) mod.db.rangeAlpha = v / 100; applyRange() end },
    }
end)

end)(...);

-- =========================================================================
-- Event wiring for the sections above, plus precise cooldown numbers.
-- =========================================================================
(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule

local H = mod.helpers

-- A dedicated cooldown-text addon does this better and would fight us for the
-- same font string, so stand down when one is loaded.
local function haveCooldownAddon()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if not loaded then return false end
    for _, name in ipairs({ "OmniCC", "tullaCC", "CooldownCount" }) do
        local ok, isLoaded = pcall(loaded, name)
        if ok and isLoaded then return true end
    end
    return false
end

-- cdTextEnabled has deliberately no option. The styling is one-shot per cooldown
-- frame (_vcStyled), so a control would only affect frames styled after the
-- change and read as a switch that does nothing. It exists to avoid doubled
-- numbers when a cooldown-count addon is present, and haveCooldownAddon below
-- already handles that case on its own.
-- ONE driver for every cooldown text in this module, not an OnUpdate per frame.
-- Twenty icons -- trinket, racial, dispel and aura across five opponents --
-- meant twenty handlers at 20 Hz, each asking the client for its cooldown
-- times. The shared ticker runs at 10 Hz, which is all a tenth-of-a-second
-- readout can show, and skips whatever is not on screen.
local styledCDs = {}
local cdTicker

local function paintCooldownText(cd)
    local fs = cd._vcText
    if not fs then return end
    local start, dur = cd:GetCooldownTimes()
    if not start or start == 0 or not dur or dur == 0 then
        if cd._vcLast ~= "" then cd._vcLast = ""; fs:SetText("") end
        return
    end
    local left = (start + dur) / 1000 - GetTime()
    if left <= 0 then
        if cd._vcLast ~= "" then cd._vcLast = ""; fs:SetText("") end
    elseif left < 6 then
        fs:SetFormattedText("%.1f", left)
        if cd._vcLast ~= "hot" then cd._vcLast = "hot"; fs:SetTextColor(1, 0.4, 0.3) end
    elseif left < 60 then
        fs:SetFormattedText("%d", left)
        if cd._vcLast ~= "warm" then cd._vcLast = "warm"; fs:SetTextColor(1, 1, 1) end
    else
        fs:SetFormattedText("%d:%02d", left / 60, left % 60)
        if cd._vcLast ~= "warm" then cd._vcLast = "warm"; fs:SetTextColor(1, 1, 1) end
    end
end

local function cdTick()
    for i = 1, #styledCDs do
        local cd = styledCDs[i]
        if cd:IsVisible() then paintCooldownText(cd) end
    end
end

local function styleCooldown(cd)
    if not cd or cd._vcStyled or not mod.db.cdTextEnabled then return end
    if haveCooldownAddon() then return end
    cd._vcStyled = true
    cd:SetHideCountdownNumbers(true)
    local fs = cd:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if ns.UI and ns.UI.Font then ns.UI.Font(fs, 13, "OUTLINE") end
    fs:SetPoint("CENTER", cd, "CENTER", 0, 0)
    cd._vcText = fs
    styledCDs[#styledCDs + 1] = cd
    if not cdTicker then cdTicker = ns:AddTicker(0.1, cdTick, nil, "arena-cdtext") end
end
mod.StyleCooldown = styleCooldown

-- The driver is shared, so an orphan would keep ticking for the rest of the
-- session; the module's own disable path is the one place that can stop it.
mod:RegisterOnDisable(function()
    if cdTicker then ns:CancelTicker(cdTicker); cdTicker = nil end
end)
mod:RegisterOnEnable(function()
    if not cdTicker and #styledCDs > 0 then
        cdTicker = ns:AddTicker(0.1, cdTick, nil, "arena-cdtext")
    end
end)

-- Racials, dispels and Shadow Sight all come from the combat log; one handler
-- keeps the hot event registered exactly once.
local function onPvPCombatLog()
    if not mod._enabled then return end
    local _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId =
        CombatLogGetCurrentEventInfo()

    if spellId == mod.ShadowsightID and mod.db.shadowsightEnabled
        and (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_CAST_SUCCESS") then
        mod.ShadowsightTaken()
        return
    end

    if subevent ~= "SPELL_CAST_SUCCESS" and subevent ~= "SPELL_AURA_APPLIED"
        and subevent ~= "SPELL_DISPEL" then
        return
    end
    if not sourceGUID then return end

    local isRacial = mod.RACIAL_CD and mod.RACIAL_CD[spellId]
    local isDispel = mod.DISPEL_CD and mod.DISPEL_CD[spellId]
    if not (isRacial or isDispel) then return end

    for i = 1, 5 do
        local unit = ns.ARENA_UNITS[i]
        if UnitExists(unit) and UnitGUID(unit) == sourceGUID then
            if isRacial then mod.RacialUsed(unit, spellId) end
            if isDispel then mod.DispelUsed(unit, spellId) end
            return
        end
    end
end

local function setPvPCombatLog(on)
    mod.SetDynEvent("COMBAT_LOG_EVENT_UNFILTERED", onPvPCombatLog, on)
end

local function ev_PLAYER_ENTERING_WORLD_3()
    -- see the trinket capsule: a switched-off module must not take the combat
    -- log, and must not start the range ticker either
    if not mod._enabled then return end
    local inArena = false
    if IsInInstance then
        local _, instanceType = IsInInstance()
        inArena = (instanceType == "arena")
    end
    setPvPCombatLog(inArena)
    if inArena then
        if mod.ResetRacials then mod.ResetRacials() end
        if mod.ResetDispels then mod.ResetDispels() end
        if mod.StartRangeCheck then mod.StartRangeCheck() end
    else
        if mod.StopShadowsight then mod.StopShadowsight() end
        if mod.StopRangeCheck then mod.StopRangeCheck() end
        if mod.ResetRacials then mod.ResetRacials() end
        if mod.ResetDispels then mod.ResetDispels() end
    end
end
mod.RegEvent("PLAYER_ENTERING_WORLD", ev_PLAYER_ENTERING_WORLD_3)
mod:RegisterOnEnable(ev_PLAYER_ENTERING_WORLD_3)

-- Gates opening is what starts the orb clock; the first opponent becoming
-- visible is the closest reliable signal for it on this client.
local gatesOpen = false
local function ev_ARENA_OPPONENT_UPDATE_3(_, unit, eventType)
    if eventType ~= "seen" then return end
    if not gatesOpen then
        gatesOpen = true
        if mod.StartShadowsight then mod.StartShadowsight() end
    end
    if mod.RefreshRacials then mod.RefreshRacials() end
    if unit and mod.AuraIconUpdate then mod.AuraIconUpdate(unit) end
end
mod.RegEvent("ARENA_OPPONENT_UPDATE", ev_ARENA_OPPONENT_UPDATE_3)

local function ev_UNIT_AURA(_, unit)
    if not mod._enabled then return end
    -- fires for every unit everywhere; only arena1-5 matter here
    if not unit or string.sub(unit, 1, 5) ~= "arena" then return end
    if mod.AuraIconUpdate then mod.AuraIconUpdate(unit) end
end
mod.RegEvent("UNIT_AURA", ev_UNIT_AURA)

local function ev_PLAYER_LEAVING_WORLD()
    gatesOpen = false
end
mod.RegEvent("PLAYER_LEAVING_WORLD", ev_PLAYER_LEAVING_WORLD)

end)(...);

-- =========================================================================
-- Loss of control: what is holding you right now and how much longer.
--
-- Stun, fear, root, silence, disarm and school lockouts all arrive through one
-- client namespace, already ranked by the same priority the default interface
-- uses. Two effects can run at once, so the display shows the one that matters
-- (highest priority, and among those the one that lasts longest) and optionally
-- the next one below it -- but only when that one outlasts the first, because
-- an effect ending earlier tells you nothing you are not already reading.
-- =========================================================================
(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule

-- The whole submodule hangs on one client namespace. Where it is missing the
-- tab never appears, so no page can offer settings that drive nothing.
local LOC = _G.C_LossOfControl
local HAS_LOC = LOC and LOC.GetActiveLossOfControlDataCount and LOC.GetActiveLossOfControlData
mod.HasLossOfControl = HAS_LOC and true or false
if not HAS_LOC then return end

local GetTime, format, floor = GetTime, string.format, math.floor

local frame, primary, secondary, mover
local previewUntil = 0
local current, runnerUp

local function db() return mod.db.loss end

-- ---------------------------------------------------------------------------
-- Reading the client
-- ---------------------------------------------------------------------------

-- A school lockout has no useful display text of its own -- every school
-- reports the same sentence -- so it is named after the school it locked.
local function effectName(d)
    if d.locType == "SCHOOL_INTERRUPT" and d.lockoutSchool and d.lockoutSchool ~= 0
       and _G.GetSchoolString then
        return format(L["%s Locked"], _G.GetSchoolString(d.lockoutSchool))
    end
    return d.displayText
end

-- Both passes want "higher priority wins, and among equals the one that runs
-- longest". The second pass starts from the winner's expiry and caps the
-- priority, so it can only return something lower-ranked that outlasts it.
local function pick(count, minExpiry, maxPriority)
    local bestPrio, bestExpiry, best = -1, minExpiry, nil
    for i = 1, count do
        local d = LOC.GetActiveLossOfControlData(i)
        if d then
            local expiry = GetTime() + (d.timeRemaining or 0)
            local prio   = d.priority or 0
            if prio >= bestPrio and expiry > bestExpiry
               and (not maxPriority or prio < maxPriority) then
                bestPrio, bestExpiry = prio, expiry
                best = { name = effectName(d), icon = d.iconTexture,
                         duration = d.duration, expiry = expiry, priority = prio }
            end
        end
    end
    return best
end

local function zoneAllows()
    local v = db().visibility
    if v == "always" then return true end
    if not IsInInstance then return false end
    local _, kind = IsInInstance()
    if v == "arena" then return kind == "arena" end
    return kind == "arena" or kind == "pvp"
end

-- ---------------------------------------------------------------------------
-- Building the display
-- ---------------------------------------------------------------------------

local function sizeSlot(slot, size)
    slot:SetSize(size, size)
    slot.tex:SetSize(size, size)
    slot.cd:SetSize(size, size)
end

local function newSlot(parent)
    local slot = CreateFrame("Frame", nil, parent)

    local tex = slot:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("CENTER")
    -- 30 percent crop: the icon's own baked-in border reads as mush at this
    -- size and carries nothing the drawn border below does not carry better.
    tex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    slot.tex = tex

    local border = CreateFrame("Frame", nil, slot,
        BackdropTemplateMixin and "BackdropTemplate")
    border:SetPoint("TOPLEFT", tex, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 1, -1)
    if border.SetBackdrop then
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        border:SetBackdropBorderColor(0, 0, 0, 1)
    end

    -- Reverse swipe: the shade grows back as the effect runs out, so a nearly
    -- clear icon means nearly free again.
    local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cd:SetPoint("CENTER")
    cd:SetReverse(true)
    cd:SetDrawEdge(true)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    slot.cd = cd

    return slot
end

local function build()
    if frame then return frame end

    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(200, 54)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Cooldown\\LoC-ShadowBG")
    bg:SetPoint("CENTER")
    bg:SetSize(200, 54)
    bg:SetVertexColor(0, 0, 0, 0.5)
    bg:SetDesaturated(true)
    -- 180 degrees is both axes flipped, so the shadow's heavy edge sits below.
    bg:SetTexCoord(1, 0, 1, 0)
    frame.bg = bg

    local function redLine(flip, y)
        local t = frame:CreateTexture(nil, "ARTWORK")
        t:SetTexture("Interface\\Cooldown\\Loc-RedLine")
        t:SetBlendMode("ADD")
        t:SetPoint("CENTER", frame, "CENTER", 0, y)
        t:SetSize(200, 30)
        t:SetVertexColor(1, 0, 0.008, 1)
        if flip then t:SetTexCoord(1, 0, 1, 0) end
        return t
    end
    frame.lineTop    = redLine(false, 42)
    frame.lineBottom = redLine(true, -42)

    primary = newSlot(frame)
    primary:SetPoint("CENTER", frame, "CENTER", -60, 0)

    primary.name = frame:CreateFontString(nil, "OVERLAY")
    primary.name:SetPoint("LEFT", primary, "RIGHT", 3, 7)
    primary.name:SetTextColor(1, 0.925, 0, 1)
    primary.name:SetJustifyH("LEFT")

    primary.time = frame:CreateFontString(nil, "OVERLAY")
    primary.time:SetPoint("LEFT", primary, "RIGHT", 3, -11)
    primary.time:SetTextColor(1, 1, 1, 1)
    primary.time:SetJustifyH("LEFT")

    -- The runner-up hangs off the main icon's bottom right and carries no text:
    -- it is an "and then this" hint, not a second readout.
    secondary = newSlot(frame)
    secondary:SetPoint("CENTER", primary, "BOTTOMRIGHT", 4, -2)

    mover = ns:CreateMover(frame, {
        key    = "arenaloss",
        label  = L["|cffffffffLOSS OF CONTROL|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = db(),
        width  = 220,
        height = 70,
        onMove = function() mod.LossApplyPos() end,
    })

    mod.LossApplyPos()
    mod.LossApplyLook()
    return frame
end

function mod.LossApplyPos()
    if not frame then return end
    local d = db()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", d.x or 0, d.y or 0)
end

function mod.LossApplyLook()
    if not frame then return end
    local d = db()
    frame:SetScale(d.scale or 1)
    frame:SetAlpha(d.alpha or 1)

    sizeSlot(primary, d.iconSize or 40)
    sizeSlot(secondary, floor((d.iconSize or 40) * 0.5 + 0.5))

    -- Set straight rather than through UI.Font: that helper always uses the
    -- global face, and this display carries its own choice.
    local path  = ns.MediaFont(d.font)
    local flags = d.outline or ""
    primary.name:SetFont(path, d.nameSize or 18, flags)
    primary.time:SetFont(path, d.timeSize or 16, flags)

    local nc = d.nameColor or {}
    primary.name:SetTextColor(nc.r or 1, nc.g or 0.925, nc.b or 0)
    local tc = d.timeColor or {}
    primary.time:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1)

    local decor = d.showBackground and true or false
    frame.bg:SetShown(decor)
    frame.lineTop:SetShown(decor)
    frame.lineBottom:SetShown(decor)
end

-- ---------------------------------------------------------------------------
-- Driving it
-- ---------------------------------------------------------------------------

-- The options window sits on HIGH as well, and being built later it wins the
-- draw order -- a preview started from the page would hide behind the page
-- that switched it on. So the display is lifted for exactly as long as the
-- player is looking at it on purpose (preview running, or the box unlocked for
-- dragging) and drops back to HIGH afterwards, which is where it belongs while
-- something is actually controlling the player.
local function applyStrata()
    if not frame then return end
    local lifted = db().unlocked or GetTime() < previewUntil
    frame:SetFrameStrata(lifted and "FULLSCREEN_DIALOG" or "HIGH")
end

local ticker = CreateFrame("Frame")
ticker:Hide()

local function showEntry(slot, entry)
    slot.tex:SetTexture(entry.icon)
    if entry.duration and entry.duration > 0 then
        slot.cd:SetCooldown(entry.expiry - entry.duration, entry.duration)
    else
        slot.cd:Clear()
    end
    slot:Show()
end

-- Same rule as the interrupt bar: an unlocked box and a running preview are
-- the player looking at the thing on purpose, so neither the zone filter nor
-- the enable switch may take it away from under them.
local function shouldShow()
    local d = db()
    if d.unlocked or GetTime() < previewUntil then return true end
    return d.enabled and zoneAllows()
end

local function refresh()
    local d = db()
    if not shouldShow() then
        if frame then frame:Hide() end
        ticker:Hide()
        return
    end

    build()
    if GetTime() < previewUntil then return end
    applyStrata()

    local count = LOC.GetActiveLossOfControlDataCount() or 0
    current  = count > 0 and pick(count, 0, nil) or nil
    runnerUp = nil
    if current and d.showNext then
        runnerUp = pick(count, current.expiry, current.priority)
    end

    if not current then
        frame:Hide()
        ticker:Hide()
        return
    end

    showEntry(primary, current)
    primary.name:SetText(current.name or "")
    if runnerUp then showEntry(secondary, runnerUp) else secondary:Hide() end
    frame:Show()
    ticker:Show()
end

-- The countdown is the only thing that has to run per frame; everything else
-- moves on an event. Once the number would go negative the scan decides
-- whether a second effect is still holding, so the display never blanks out
-- while something is in fact still on the player.
ticker:SetScript("OnUpdate", function()
    if not current then ticker:Hide(); return end
    local left = current.expiry - GetTime()
    if left <= 0 then
        if GetTime() >= previewUntil then refresh() end
        return
    end
    primary.time:SetText(format(L["%.1f seconds"], left))
end)

local function ev_loss()
    refresh()
end
mod.RegEvent("LOSS_OF_CONTROL_UPDATE", ev_loss)
mod.RegEvent("LOSS_OF_CONTROL_ADDED", ev_loss)
mod.RegEvent("PLAYER_ENTERING_WORLD", ev_loss)

mod:RegisterOnEnable(function()
    build()
    mod.LossApplyLook()
    refresh()
end)

mod:RegisterOnDisable(function()
    if frame then frame:Hide() end
    ticker:Hide()
end)

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

local function setUnlocked(state)
    build()
    db().unlocked = state and true or false
    applyStrata()
    if db().unlocked then
        frame:Show()
        mover:Show()
        ns:Print(L["Loss of control mover active. |cff9b6cffDrag the purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Press the button again to finish."])
    else
        mover:Hide()
        refresh()
    end
end

-- Positioning something you cannot see is guesswork, and a real stun is a poor
-- moment to judge a layout, so the page can put a stand-in on screen.
local function preview()
    build()
    previewUntil = GetTime() + 8
    current = { name = L["Preview"], icon = 136071, duration = 8,
                expiry = previewUntil, priority = 0 }
    showEntry(primary, current)
    primary.name:SetText(current.name)
    -- No stand-in for the runner-up: with only one placeholder icon to hand it
    -- would be the same picture twice, which reads as a fault rather than as a
    -- second effect. In a real fight the small icon carries a different spell.
    secondary:Hide()
    applyStrata()
    frame:Show()
    ticker:Show()
end

-- Built fresh on every page build: another addon may have registered further
-- faces with shared media since the last time this page was open.
local function lossFontValues()
    local v = { { value = "", text = L["Use the global font"] } }
    for _, entry in ipairs(ns.MediaFontValues() or {}) do
        v[#v + 1] = entry
    end
    return v
end

mod:AddOptionsSection("loss", function()
    local d = db()
    return {
        { type = "header", text = L["Loss of Control"] },
        { type = "desc",   text = L["Shows what is controlling you right now -- stun, fear, root, silence, disarm or a school lockout -- with the effect icon, its name and the time left. Where two effects run at once the one that matters is shown large, and the next one as a small icon beside it."] },

        { type = "checkbox", label = L["Show loss of control alert"],
          get = function() return d.enabled end,
          set = function(_, v) d.enabled = v; refresh() end },

        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Unlock / Move"], width = 130,
              onClick = function() setUnlocked(not db().unlocked) end },
            { type = "button", label = L["Preview"], width = 130,
              onClick = function() preview() end },
        } },

        { type = "dropdown", label = L["Show in"], width = 220,
          values = {
              { value = "always", text = L["Everywhere"] },
              { value = "pvp",    text = L["Arena and battlegrounds"] },
              { value = "arena",  text = L["Arena only"] },
          },
          get = function() return d.visibility end,
          set = function(_, v) d.visibility = v; refresh() end },

        { type = "slider", label = L["Icon size"], min = 20, max = 80, step = 1,
          get = function() return d.iconSize end,
          set = function(_, v) d.iconSize = v; mod.LossApplyLook() end },
        { type = "slider", label = L["Scale"], min = 0.5, max = 2, step = 0.05,
          get = function() return d.scale end,
          set = function(_, v) d.scale = v; mod.LossApplyLook() end },
        { type = "slider", label = L["Opacity"], min = 0.1, max = 1, step = 0.05,
          get = function() return d.alpha end,
          set = function(_, v) d.alpha = v; mod.LossApplyLook() end },

        { type = "slider", label = L["Name font size"], min = 8, max = 32, step = 1,
          get = function() return d.nameSize end,
          set = function(_, v) d.nameSize = v; mod.LossApplyLook() end },
        { type = "slider", label = L["Timer font size"], min = 8, max = 32, step = 1,
          get = function() return d.timeSize end,
          set = function(_, v) d.timeSize = v; mod.LossApplyLook() end },

        { type = "dropdown", label = L["Font"], width = 240, values = lossFontValues(),
          get = function() return d.font or "" end,
          set = function(_, v) d.font = v; mod.LossApplyLook() end },
        { type = "dropdown", label = L["Outline"], width = 240,
          values = {
              { value = "THICKOUTLINE", text = L["Thick outline"] },
              { value = "OUTLINE",      text = L["Outline"] },
              { value = "SHADOW",       text = L["Shadow"] },
              { value = "",             text = L["None"] },
          },
          get = function() return d.outline or "" end,
          set = function(_, v) d.outline = v; mod.LossApplyLook() end },

        { type = "color", label = L["Name color"], width = 160,
          get = function() return d.nameColor end,
          set = function(r, g, b) d.nameColor = { r = r, g = g, b = b }; mod.LossApplyLook() end },
        { type = "color", label = L["Timer color"], width = 160,
          get = function() return d.timeColor end,
          set = function(r, g, b) d.timeColor = { r = r, g = g, b = b }; mod.LossApplyLook() end },

        { type = "checkbox", label = L["Background and red lines"],
          get = function() return d.showBackground end,
          set = function(_, v) d.showBackground = v; mod.LossApplyLook() end },
        { type = "checkbox", label = L["Show the next effect"],
          get = function() return d.showNext end,
          set = function(_, v) d.showNext = v; refresh() end },
    }
end)

end)(...);

-- =========================================================================
-- Interrupt tracker: whose kick is down, and for how long.
--
-- The combat log is the only source here. A cast lands, the spell is one this
-- table knows, the caster is a hostile player -- then an icon starts running
-- its cooldown. Tracking is per CASTER, not per spell, so two enemy rogues get
-- an icon each; in arena that difference is the whole point.
--
-- Spell ids carry their ranks. The combat log reports the rank that was
-- actually cast, so every rank of the same ability has to resolve back to one
-- entry, and the highest cooldown of the ability is the one worth showing.
-- =========================================================================
(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule

local GetTime, floor, format, unpack = GetTime, math.floor, string.format, unpack

-- id = { cooldown in seconds, class token, ability key }
-- The ability key groups ranks: every rank of one kick shares it, so the display
-- never shows the same enemy ability twice. The id lists below do NOT have to be
-- rank-complete -- see spellDef further down, which picks up the ranks nobody
-- wrote in by name.
local SPELLS  = {}   -- every id that triggers the ability
local ABILITY = {}   -- one entry per ability, carrying the id to draw
local function put(cd, class, key, pet, ...)
    -- The first id is the canonical one: it decides which icon the bar shows,
    -- so a frost shock spent on a snare still draws the shaman's shock rather
    -- than whichever rank happened to arrive.
    ABILITY[key] = { id = (select(1, ...)), cd = cd, class = class, key = key }
    for i = 1, select("#", ...) do
        SPELLS[select(i, ...)] = { cd = cd, class = class, key = key, pet = pet }
    end
end

put(10, "WARRIOR", "pummel",       false, 6552, 6554)
put(12, "WARRIOR", "shieldbash",   false, 72, 1671, 1672)
put(10, "ROGUE",   "kick",         false, 1766, 1767, 1768, 1769)
put(24, "MAGE",    "counterspell", false, 2139)
put(45, "PRIEST",  "silence",      false, 15487)
put(20, "HUNTER",  "silencingshot", false, 34490)
put(15, "DRUID",   "feralcharge",  false, 16979)
-- The felhunter casts this one, not the warlock, so it arrives from a source
-- that carries no player flag. See the source filter below.
put(24, "WARLOCK", "spelllock",    true,  19244, 19647)

-- Every shock shares one cooldown, so a frost shock spent on a snare is a kick
-- the shaman no longer has. Tracking only Earth Shock would leave the bar
-- claiming an interrupt is ready while it is not. Five seconds on Burning
-- Crusade, six on Wrath.
local SHOCKS = { 8042, 8044, 8045, 8046, 10412, 10413, 10414, 25454,
                 8050, 8052, 8053, 10447, 10448, 29228, 25457,
                 8056, 8058, 10472, 10473, 25464 }
put(ns.isWrath and 6 or 5, "SHAMAN", "shock", false, unpack(SHOCKS))

-- Wrath additions. Gated so a Burning Crusade client never lists an ability it
-- has no spell for.
if ns.isWrath then
    put(6,   "SHAMAN",      "windshear",   false, 57994)
    put(10,  "DEATHKNIGHT", "mindfreeze",  false, 47528)
    put(120, "DEATHKNIGHT", "strangulate", false, 47476)
end

-- Which abilities a class can bring, for the greyed-out preview of enemies who
-- have not used theirs yet.
local BY_CLASS = {}
for _, ab in pairs(ABILITY) do
    BY_CLASS[ab.class] = BY_CLASS[ab.class] or {}
    table.insert(BY_CLASS[ab.class], ab)
end

local frame, mover
local icons  = {}      -- pooled buttons
local active = {}      -- [guid .. "/" .. key] = { expiry, cd, id, class, name }
local previewUntil = 0

local function db() return mod.db.interrupts end

-- ---------------------------------------------------------------------------
-- The bar
-- ---------------------------------------------------------------------------

local function newIcon()
    local f = CreateFrame("Frame", nil, frame)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(f)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.tex = tex

    local border = CreateFrame("Frame", nil, f,
        BackdropTemplateMixin and "BackdropTemplate")
    border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    if border.SetBackdrop then
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    end
    f.border = border

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(f)
    cd:SetDrawEdge(true)
    -- The client's own numbers stay off: they cannot be styled, and this bar
    -- carries its own text so the settings below actually reach it.
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    f.cd = cd

    -- Above the swipe, so the shade never eats the number.
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.text = text

    return f
end

-- Coarse at the top, exact at the bottom: a two-minute lockout does not need a
-- tenth of a second, and the last few seconds are the ones actually worth
-- reading.
local function timerText(left)
    if left >= 60 then return format("%dm", floor(left / 60 + 0.5)) end
    if left >= 10 then return format("%d", floor(left + 0.5)) end
    return format("%.1f", left)
end

-- Font and colour are set here rather than in the refresh pass: that pass runs
-- five times a second, and the text look only changes when a setting does.
function mod.InterruptApplyLook()
    local d = db()
    local path  = ns.MediaFont(d.font)
    local flags = d.outline or ""
    local c = d.timerColor or {}
    local swipe = d.showSwipe ~= false
    for _, f in ipairs(icons) do
        f.text:SetFont(path, d.timerSize or 12, flags)
        f.text:SetTextColor(c.r or 1, c.g or 0.9, c.b or 0.4)
        -- Where the client offers it the swipe is switched off on the cooldown
        -- itself, so the frame keeps running and only stops painting; older
        -- clients get the whole cooldown hidden, which looks the same. Either
        -- way the timer text is untouched -- it sits on the icon, not on the
        -- cooldown.
        if f.cd.SetDrawSwipe then
            f.cd:SetDrawSwipe(swipe)
            if f.cd.SetDrawEdge then f.cd:SetDrawEdge(swipe) end
            f.cd:Show()
        else
            f.cd:SetShown(swipe)
        end
    end
end

local function ensureIcon(i)
    if not icons[i] then
        icons[i] = newIcon()
        mod.InterruptApplyLook()   -- the fresh one still has no font
    end
    return icons[i]
end

local function build()
    if frame then return frame end

    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(200, 32)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    mover = ns:CreateMover(frame, {
        key    = "arenainterrupts",
        label  = L["|cffffffffINTERRUPTS|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = db(),
        width  = 220,
        height = 60,
        onMove = function() mod.InterruptApplyPos() end,
    })

    mod.InterruptApplyPos()
    return frame
end

function mod.InterruptApplyPos()
    if not frame then return end
    local d = db()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", d.x or 0, d.y or 0)
end

-- Same growth vocabulary the cooldown bars already use, so a player who has set
-- one of those up does not have to learn a second one.
local function layout(shown)
    local d = db()
    local size, pad = d.iconSize or 32, d.spacing or 4
    local perRow = math.max(1, d.perRow or 8)
    local horiz  = (d.growth == "RIGHT" or d.growth == "LEFT")
    local count  = #shown
    local posN   = math.min(math.max(count, 1), perRow)
    local lineN  = math.max(1, math.ceil(math.max(count, 1) / perRow))
    local cols   = horiz and posN or lineN
    local rows   = horiz and lineN or posN
    local step   = size + pad

    for i = 1, count do
        local idx  = i - 1
        local line = floor(idx / perRow)
        local pos  = idx % perRow
        local col  = horiz and pos or line
        local row  = horiz and line or pos
        if d.growth == "LEFT" then col = (cols - 1) - col end
        if d.growth == "UP"   then row = (rows - 1) - row end
        local f = shown[i]
        f:SetSize(size, size)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", frame, "TOPLEFT", col * step, -row * step)
    end
    frame:SetSize(math.max(cols * size + (cols - 1) * pad, 1),
                  math.max(rows * size + (rows - 1) * pad, 1))
end

-- ---------------------------------------------------------------------------
-- What to show
-- ---------------------------------------------------------------------------

local function zoneAllows()
    local v = db().visibility
    if v == "always" then return true end
    if not IsInInstance then return false end
    local _, kind = IsInInstance()
    if v == "arena" then return kind == "arena" end
    return kind == "arena" or kind == "pvp"
end

local function classColor(class)
    local c = class and ns.COLORS and ns.COLORS.class and ns.COLORS.class[class]
    if c then return c.r, c.g, c.b end
    local raw = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    if raw then return raw.r, raw.g, raw.b end
    return 0.6, 0.6, 0.6
end

-- Enemies whose interrupt has not been seen yet, so the bar reads as "these are
-- the kicks in this match" from the opening gate rather than filling up as they
-- are spent. Arena only: outside it there is no reliable enemy roster.
local function unusedEntries(out)
    if not db().showUnused then return end
    if not (IsInInstance and select(2, IsInInstance()) == "arena") then return end
    for i = 1, 5 do
        local unit = ns.ARENA_UNITS[i]
        if UnitExists and UnitExists(unit) then
            local _, class = UnitClass(unit)
            local guid = UnitGUID and UnitGUID(unit)
            -- `or {}` here was a fresh empty table per opponent per pass
            local abilities = BY_CLASS[class]
            if abilities then
                for ai = 1, #abilities do
                    local ab = abilities[ai]
                    if not (guid and active[guid .. "/" .. ab.key]) then
                        out[#out + 1] = { id = ab.id, class = class, ready = true }
                    end
                end
            end
        end
    end
end

-- Positioning happens wherever the player is standing, which is almost never
-- an arena -- so an unlocked box and a running preview both override the zone
-- filter and the enable switch. Without this the ticker wiped the bar off the
-- screen a fifth of a second after the unlock button put it there.
local function shouldShow()
    local d = db()
    if d.unlocked or GetTime() < previewUntil then return true end
    -- The whole module being off has to take the bar with it. Its handlers are
    -- registered at file scope, so a module that was never enabled still hears
    -- the combat log -- and without this the bar appeared, filled up, and never
    -- cleared, because the ticker that expires its icons only runs from OnEnable.
    if not mod._enabled then return false end
    return d.enabled and zoneAllows()
end

-- One ticker for the whole bar: an icon whose cooldown has run out has to
-- leave, and nothing else tells us when that moment is. It is shown only while
-- something can actually expire -- see the end of refresh.
local ticker = CreateFrame("Frame")
ticker:Hide()

-- Hoisted out of refresh: that pass runs five times a second, and a comparator
-- written inside it is a fresh closure on every one of them.
local function byExpiry(a, b) return a.expiry < b.expiry end

-- Two scratch lists, refilled and trimmed instead of rebuilt, for the same
-- reason -- Lua 5.1 has no generational collector, so a table per pass is
-- rubbish the player pays for as a stutter.
local list, shown = {}, {}

local function refresh()
    if not shouldShow() then
        if frame then frame:Hide() end
        ticker:Hide()
        return
    end
    build()
    local d = db()

    local now = GetTime()
    local n = 0
    for key, e in pairs(active) do
        if e.expiry <= now then
            active[key] = nil
        else
            n = n + 1
            list[n] = e
        end
    end
    for i = n + 1, #list do list[i] = nil end
    -- Only a running cooldown can expire; the ready icons below never do, so
    -- they must not keep the ticker alive.
    local live = n

    -- Soonest ready first: the one you are waiting on sits at the front.
    table.sort(list, byExpiry)
    unusedEntries(list)

    local count = 0
    for i = 1, #list do
        local e = list[i]
        local f = ensureIcon(i)

        -- Everything below is compared before it is written. This pass runs
        -- five times a second and used to re-set texture, border, saturation,
        -- alpha and text unconditionally on every icon each time.
        local tex = (GetSpellTexture and GetSpellTexture(e.id)) or 134400
        if f._tex ~= tex then f.tex:SetTexture(tex); f._tex = tex end
        if f._class ~= e.class then
            f._class = e.class
            if f.border.SetBackdropBorderColor then
                f.border:SetBackdropBorderColor(classColor(e.class))
            end
        end

        if e.ready then
            if f._ready ~= true then
                f._ready = true
                f.cd:Clear()
                f._cdStart, f._cdDur = nil, nil
                f.tex:SetDesaturated(true)
                f.tex:SetAlpha(0.45)
                f.text:SetText("")
                f._timer = ""
            end
        else
            if f._ready ~= false then
                f._ready = false
                f.tex:SetDesaturated(false)
                f.tex:SetAlpha(1)
            end
            -- Only when it actually changed: re-arming an unchanged swipe makes
            -- it stutter.
            local start = e.expiry - e.cd
            if f._cdStart ~= start or f._cdDur ~= e.cd then
                f.cd:SetCooldown(start, e.cd)
                f._cdStart, f._cdDur = start, e.cd
            end
            local txt = d.showTimer and timerText(e.expiry - now) or ""
            if f._timer ~= txt then f.text:SetText(txt); f._timer = txt end
        end

        f:Show()
        count = count + 1
        shown[count] = f
    end
    for i = count + 1, #shown do shown[i] = nil end
    for i = count + 1, #icons do icons[i]:Hide() end

    ticker:SetShown(live > 0)

    if count == 0 and not db().unlocked then
        frame:Hide()
        return
    end
    layout(shown)
    frame:Show()
end

-- ---------------------------------------------------------------------------
-- Reading the combat log
-- ---------------------------------------------------------------------------

local HOSTILE = _G.COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local PLAYER  = _G.COMBATLOG_OBJECT_TYPE_PLAYER      or 0x00000400

-- The ranks the lists above do not carry, resolved by NAME.
--
-- Every rank of a spell has its own id and shares its name, so a hand-written id
-- list is only ever as complete as the day it was written: the top ranks of the
-- rogue kick and the shield bash -- the ones a level 70 actually presses -- were
-- missing, and those interrupts started no bar at all. Writing the numbers in by
-- hand would be guessing at ids that cannot be verified from here, and the list
-- would go stale with the next rank anyway.
--
-- GetSpellInfo answers the name for every id we DO carry, so one pass builds an
-- index that covers all ranks at once, in the client's own language -- which is
-- the language the combat log speaks. Built on first use, not at load: spell data
-- is not reliably readable then. The ability key groups ranks already, so a hit
-- by name lands on the same entry and the bar still draws the canonical icon.
local BY_NAME
local function spellDef(spellID, spellName)
    local def = spellID and SPELLS[spellID]
    if def then return def end
    if not spellName or not GetSpellInfo then return nil end
    if not BY_NAME then
        BY_NAME = {}
        for id, d in pairs(SPELLS) do
            local n = GetSpellInfo(id)
            -- First id wins for a name: within one ability every rank carries the
            -- same cooldown, class and key, so which rank answered does not
            -- matter -- and two ABILITIES under one name would be a list bug that
            -- silently picking the later one would hide.
            if n and BY_NAME[n] == nil then BY_NAME[n] = d end
        end
    end
    return BY_NAME[spellName]
end

local function onCombatLog()
    if not mod._enabled or not db().enabled then return end
    local info = CombatLogGetCurrentEventInfo
    if not info then return end
    local _, sub, _, sourceGUID, sourceName, sourceFlags, _, _, _, _, _, spellID, spellName = info()
    if sub ~= "SPELL_CAST_SUCCESS" then return end

    local def = spellDef(spellID, spellName)
    if not def or not sourceGUID then return end

    -- Hostile only: a friendly kick is not what this bar is for.
    local flags = sourceFlags or 0
    if bit.band(flags, HOSTILE) == 0 then return end
    -- Players, plus the pets that carry an interrupt of their own. Demanding
    -- the player flag for everything would drop every felhunter lock, which is
    -- the one interrupt in the list nobody casts personally.
    if not def.pet and bit.band(flags, PLAYER) == 0 then return end

    active[sourceGUID .. "/" .. def.key] = {
        id     = ABILITY[def.key].id,
        cd     = def.cd,
        class  = def.class,
        name   = sourceName,
        expiry = GetTime() + def.cd,
    }
    refresh()
end

local nextSweep = 0
ticker:SetScript("OnUpdate", function()
    local now = GetTime()
    if now < nextSweep then return end
    nextSweep = now + 0.2
    refresh()
end)

-- The combat log is taken only where the bar could ever show something. The
-- three older capsules gate it to arenas; this one was registered at file scope
-- and never let go, so every combat log line in the world -- thousands a second
-- in a raid -- was decoded for a bar whose own default is "arena and
-- battlegrounds". The zone filter it already carries decides.
local function syncCombatLog()
    mod.SetDynEvent("COMBAT_LOG_EVENT_UNFILTERED", onCombatLog,
        mod._enabled and db().enabled and zoneAllows())
end
mod.SyncInterruptCombatLog = syncCombatLog

local function ev_zone()
    syncCombatLog()
    refresh()
end

mod.RegEvent("PLAYER_ENTERING_WORLD", ev_zone)
mod.RegEvent("ARENA_OPPONENT_UPDATE", ev_zone)

mod:RegisterOnEnable(function()
    build()
    syncCombatLog()
    refresh()
end)

mod:RegisterOnDisable(function()
    if frame then frame:Hide() end
    ticker:Hide()
end)

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

local function setUnlocked(state)
    build()
    db().unlocked = state and true or false
    if db().unlocked then
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:Show()
        mover:Show()
        ns:Print(L["Interrupt bar mover active. |cff9b6cffDrag the purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Press the button again to finish."])
    else
        frame:SetFrameStrata("MEDIUM")
        mover:Hide()
        refresh()
    end
end

-- A stand-in run so the bar can be placed and sized without waiting for an
-- enemy to actually spend a kick.
local function preview()
    build()
    local demo = { "kick", "counterspell", "pummel", "spelllock" }
    local pick = { 1766, 2139, 6552, 19244 }
    local cls  = { "ROGUE", "MAGE", "WARRIOR", "WARLOCK" }
    local longest = 0
    for i = 1, #demo do
        local left = 6 + i * 2
        if left > longest then longest = left end
        active["preview" .. i .. "/" .. demo[i]] = {
            id = pick[i], cd = 10 + i * 4, class = cls[i],
            name = "?", expiry = GetTime() + left,
        }
    end
    previewUntil = GetTime() + longest
    refresh()
end

-- Rebuilt per page build, so a font another addon registered since the last
-- visit shows up. Same first entry as the loss display: an empty name means
-- MediaFont falls through to the global setting.
local function interruptFontValues()
    local v = { { value = "", text = L["Use the global font"] } }
    for _, entry in ipairs(ns.MediaFontValues() or {}) do
        v[#v + 1] = entry
    end
    return v
end

mod:AddOptionsSection("interrupt", function()
    local d = db()
    return {
        { type = "header", text = L["Interrupts"] },
        { type = "desc",   text = L["Watches the combat log for enemy interrupts and starts a cooldown for each one, tracked per caster -- two enemies of the same class get an icon each. The border carries the caster's class colour."] },

        -- Both setters re-decide the combat log subscription, not just the
        -- display: switching the bar off in an arena has to hand the event back.
        { type = "checkbox", label = L["Show interrupt bar"],
          get = function() return d.enabled end,
          set = function(_, v) d.enabled = v; syncCombatLog(); refresh() end },

        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Unlock / Move"], width = 130,
              onClick = function() setUnlocked(not db().unlocked) end },
            { type = "button", label = L["Preview"], width = 130,
              onClick = function() preview() end },
        } },

        { type = "dropdown", label = L["Show in"], width = 220,
          values = {
              { value = "always", text = L["Everywhere"] },
              { value = "pvp",    text = L["Arena and battlegrounds"] },
              { value = "arena",  text = L["Arena only"] },
          },
          get = function() return d.visibility end,
          set = function(_, v) d.visibility = v; syncCombatLog(); refresh() end },

        { type = "dropdown", label = L["Growth direction"], width = 220,
          values = {
              { value = "RIGHT", text = L["Right"] }, { value = "LEFT", text = L["Left"] },
              { value = "DOWN",  text = L["Down"]  }, { value = "UP",   text = L["Up"]   },
          },
          get = function() return d.growth end,
          set = function(_, v) d.growth = v; refresh() end },

        { type = "slider", label = L["Icon size"], min = 16, max = 64, step = 1,
          get = function() return d.iconSize end,
          set = function(_, v) d.iconSize = v; refresh() end },
        { type = "slider", label = L["Spacing"], min = 0, max = 16, step = 1,
          get = function() return d.spacing end,
          set = function(_, v) d.spacing = v; refresh() end },
        { type = "slider", label = L["Icons per row"], min = 1, max = 12, step = 1,
          get = function() return d.perRow end,
          set = function(_, v) d.perRow = v; refresh() end },

        { type = "checkbox", label = L["Show interrupts that are still ready"],
          get = function() return d.showUnused end,
          set = function(_, v) d.showUnused = v; refresh() end },

        -- Its own row rather than a sub-option: the swipe and the text are
        -- independent, either one is a complete readout on its own.
        { type = "checkbox", label = L["Cooldown swipe on the icons"],
          get = function() return d.showSwipe end,
          set = function(_, v) d.showSwipe = v; mod.InterruptApplyLook() end },

        { type = "checkbox", label = L["Timer text on the icons"],
          get = function() return d.showTimer end,
          set = function(_, v) d.showTimer = v; refresh() end,
          subOptions = {
              { type = "slider", label = L["Timer font size"], min = 8, max = 32, step = 1,
                get = function() return d.timerSize end,
                set = function(_, v) d.timerSize = v; mod.InterruptApplyLook() end },
              { type = "dropdown", label = L["Font"], width = 240,
                values = interruptFontValues(),
                get = function() return d.font or "" end,
                set = function(_, v) d.font = v; mod.InterruptApplyLook() end },
              { type = "dropdown", label = L["Outline"], width = 240,
                values = {
                    { value = "OUTLINE",      text = L["Outline"] },
                    { value = "THICKOUTLINE", text = L["Thick outline"] },
                    { value = "",             text = L["None"] },
                },
                get = function() return d.outline or "" end,
                set = function(_, v) d.outline = v; mod.InterruptApplyLook() end },
              { type = "color", label = L["Timer color"], width = 160,
                get = function() return d.timerColor end,
                set = function(r, g, b)
                    d.timerColor = { r = r, g = g, b = b }; mod.InterruptApplyLook()
                end },
          } },
    }
end)

end)(...);

-- =========================================================================
-- Live preview of the side strip.
--
-- The strip sits next to the arena enemy frames, and those exist only inside
-- an arena -- so every slider below it adjusts something the player cannot
-- see while adjusting it. This draws a stand-in instead: a mock enemy frame
-- with the same three icons, placed by exactly the arithmetic LayoutSideIcons
-- uses, so what moves here is what will move in there.
--
-- Insecure throughout, and deliberately so. Forcing the real arena frames on
-- screen out of an arena would mean touching protected frames from Lua, and
-- this addon has paid for that once already.
-- =========================================================================
(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule

local preview

local BOX_W, BOX_H = 128, 38

-- Same order the real strip is registered in: racial (10), PvP trinket (20),
-- then the diminishing-returns row (30).
local DEMO = {
    { tex = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
      size = function() return mod.db.racialSize or 22 end,
      on   = function() return mod.db.racialEnabled end },
    { tex = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01",
      size = function() return mod.db.trinketSize or 24 end,
      on   = function() return mod.db.trinketEnabled end },
    -- The real row holds one icon per tracked category and grows with them;
    -- three slots stand in for it, which is what a normal match shows.
    { tex = "Interface\\Icons\\Spell_Nature_Polymorph",
      size = function() return mod.db.drSize or 24 end,
      on   = function() return mod.db.drEnabled end,
      slots = 3 },
}

local function build(host)
    if preview then
        preview:SetParent(host)
        preview:ClearAllPoints()
        preview:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        return preview
    end

    preview = CreateFrame("Frame", nil, host)
    preview:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    preview:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    preview:SetHeight(96)

    -- The mock enemy frame. Not a copy of Blizzard's art, just a body of the
    -- right size: the strip anchors to the frame's edge, and only that edge
    -- matters for what the sliders do.
    local box = CreateFrame("Frame", nil, preview)
    box:SetSize(BOX_W, BOX_H)
    box:SetPoint("CENTER", preview, "CENTER", 0, 4)
    ns.UI.SetColorBG(box, 0.10, 0.10, 0.13, 1)
    preview.box = box

    local border = CreateFrame("Frame", nil, box,
        BackdropTemplateMixin and "BackdropTemplate")
    border:SetAllPoints(box)
    if border.SetBackdrop then
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        border:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    end

    local name = box:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(name, 10)
    name:SetPoint("TOPLEFT", box, "TOPLEFT", 5, -4)
    name:SetText("|cffff7c0aGegner|r")

    local hp = box:CreateTexture(nil, "ARTWORK")
    hp:SetPoint("TOPLEFT", box, "TOPLEFT", 5, -18)
    hp:SetSize(BOX_W - 10, 8)
    hp:SetColorTexture(0.15, 0.62, 0.25, 1)

    local mp = box:CreateTexture(nil, "ARTWORK")
    mp:SetPoint("TOPLEFT", box, "TOPLEFT", 5, -28)
    mp:SetSize(BOX_W - 10, 5)
    mp:SetColorTexture(0.20, 0.40, 0.85, 1)

    preview.icons = {}

    local hint = preview:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(hint, 10)
    hint:SetPoint("BOTTOM", preview, "BOTTOM", 0, 2)
    hint:SetTextColor(0.6, 0.6, 0.66)
    hint:SetText(L["Stand-in for an enemy frame: the side strip is placed by the settings below."])

    return preview
end

local function slot(i)
    local f = preview.icons[i]
    if f then return f end
    f = CreateFrame("Frame", nil, preview)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local b = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate")
    b:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    if b.SetBackdrop then
        b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        b:SetBackdropBorderColor(0, 0, 0, 1)
    end
    preview.icons[i] = f
    return f
end

-- The arithmetic below is LayoutSideIcons, copied on purpose rather than
-- shared: that one walks the registered getters and anchors real frames to a
-- real arena frame. Keeping them apart means the preview cannot reach into
-- anything protected. If the placement rule there changes, it changes here.
function mod.RefreshSidePreview()
    if not preview or not preview:IsShown() then return end
    local d     = mod.db
    local right = mod.IsSideStripRight()
    local gap   = d.iconGap or 4
    local y     = d.iconOffsetY or 0
    local x     = d.iconOffsetX or 8

    local n = 0
    for _, def in ipairs(DEMO) do
        if def.on() then
            local size = def.size()
            for s = 1, (def.slots or 1) do
                n = n + 1
                local f = slot(n)
                f.tex:SetTexture(def.tex)
                f:SetSize(size, size)
                f:ClearAllPoints()
                if right then
                    f:SetPoint("LEFT", preview.box, "RIGHT", x, y)
                else
                    f:SetPoint("RIGHT", preview.box, "LEFT", -x, y)
                end
                f:Show()
                -- Inside the row the slots sit shoulder to shoulder; only the
                -- row as a whole takes the gap, exactly as the real one does.
                x = x + size + ((s == (def.slots or 1)) and gap or 1)
            end
        end
    end
    for i = n + 1, #preview.icons do preview.icons[i]:Hide() end
end

-- Only the tab that carries the layout section; a returned 0 hides the header
-- everywhere else.
function mod.BuildPageHeader(host, tabId)
    if tabId ~= nil and tabId ~= "core" and tabId ~= "default" then return 0 end
    build(host)
    preview:Show()
    mod.RefreshSidePreview()
    return 96
end

end)(...);
