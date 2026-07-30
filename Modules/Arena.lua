-- VuloClassicUI / Modules / Arena

-- Each merged submodule runs in its own IIFE so file-level locals and top-level early-returns stay isolated.
(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L

local mod = ns:RegisterModule("arenaframes", {
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
    },
})

ns.ArenaModule = mod

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

function mod:OnEnable()
    -- before OnEnableCore, so the handlers it wires on a first enable are not
    -- also caught by the re-install loop and registered twice
    reinstallEvents()
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
}
end)

function mod:AddOptionsSection(name, builder)
    table.insert(self._optionsBuilders, { name = name, fn = builder })
end

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

-- mod.tabs can only be built after every AddOptionsSection call, i.e. at PLAYER_LOGIN.
local tabsInitFrame = CreateFrame("Frame")
tabsInitFrame:RegisterEvent("PLAYER_LOGIN")
tabsInitFrame:SetScript("OnEvent", function()
    mod.tabs = buildTabsArray()
end)

function mod:GetOptions(tabId)
    if tabId and tabId ~= "default" then
        for _, sec in ipairs(self._optionsBuilders) do
            if sec.name == tabId then
                return sec.fn(self) or {}
            end
        end
        return {}
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
            if not (UnitExists and UnitExists("arena" .. i)) and not ns:InCombat() then
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
            if not (UnitExists and UnitExists("arena" .. i)) then frame:Hide() end
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

-- Size of the whole stack, for the drag overlay. nil until the frames have a
-- measurable height, which is the first tick after the arena UI loads.
local stackW, stackH
function mod.GetStackSize()
    return stackW, stackH
end

local reportedLayoutError = false

local function anchorSlots(owner, slots, spacing, grow)
    local previous = nil
    for _, slotIndex in ipairs(slots) do
        local frame = _G["ArenaEnemyFrame" .. slotIndex]
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
    local totalH, maxW, counted = 0, 0, 0
    for _, slotIndex in ipairs(slots) do
        local frame = _G["ArenaEnemyFrame" .. slotIndex]
        if frame then
            local h, w = frame:GetHeight() or 0, frame:GetWidth() or 0
            if h > 0 then totalH = totalH + h; counted = counted + 1 end
            if w > maxW then maxW = w end
        end
    end
    if counted > 0 then
        stackH = totalH + spacing * (counted - 1)
        stackW = maxW
    else
        stackH, stackW = nil, nil
    end

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
local function watchFrameAnchors()
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

    -- runs on every call: frames created after the last one still need watching
    watchFrameAnchors()
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
        local frame = _G["ArenaEnemyFrame" .. i]
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
    local arenaFrame = _G["ArenaEnemyFrame" .. i]
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
        local unit = "arena" .. i
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
    local arenaFrame = _G["ArenaEnemyFrame" .. i]
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
        local unit = "arena" .. i
        if UnitExists(unit) then refreshTrinketFromAPI(unit) end
    end
end

local function onCombatLog()
    local _, subevent, _, sourceGUID, _, _, _, _, _, _, _, spellId =
        CombatLogGetCurrentEventInfo()

    if subevent ~= "SPELL_CAST_SUCCESS" then return end
    if not TRINKET_SPELLS[spellId] then return end

    for i = 1, 5 do
        local unit = "arena" .. i
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

local function ev_PLAYER_ENTERING_WORLD()
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

-- spellId -> DR category; rank variants mostly map to the final rank only
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

local function updateDRDisplay(unit)
    if not mod.db.drEnabled then return end
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local arenaFrame = _G["ArenaEnemyFrame" .. i]
    if not arenaFrame then return end

    local container = ensureDRContainer(arenaFrame, i)
    mod.LayoutSideIcons(arenaFrame, i)

    local state = drState[unit] or {}
    local visible = {}
    for cat, data in pairs(state) do
        if data.expires > GetTime() then
            table.insert(visible, { cat = cat, data = data })
        end
    end
    table.sort(visible, function(a, b) return a.cat < b.cat end)

    for _, icon in pairs(container.icons) do icon:Hide() end

    -- On the left edge the row has to grow away from the frame, or a second
    -- icon would be laid straight across the health bar.
    local leftSide = not mod.IsSideStripRight()

    local x = 0
    for _, entry in ipairs(visible) do
        local icon = container.icons[entry.cat]
        if not icon then
            icon = createDRIcon(container, entry.cat)
            container.icons[entry.cat] = icon
        end
        icon:SetSize(mod.db.drSize, mod.db.drSize)
        icon:ClearAllPoints()
        if leftSide then
            icon:SetPoint("RIGHT", container, "RIGHT", -x, 0)
        else
            icon:SetPoint("LEFT", container, "LEFT", x, 0)
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
        icon.border:SetColorTexture(getDRColor(level))

        icon.cd:SetCooldown(entry.data.appliedTime, DR_RESET_TIME)
        icon:Show()

        x = x + mod.db.drSize + 2
    end
end

-- Moving a slider outside an arena has no live state to redraw, so the frames
-- that already exist are re-anchored directly.
function mod.RefreshDR()
    mod.RefreshSideIcons()
    for unit in pairs(drState) do updateDRDisplay(unit) end
end

local function onAuraApplied(destUnit, spellId)
    local cat = DR_SPELLS[spellId]
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

local function ev_PLAYER_ENTERING_WORLD_2()
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
            set = function(_, v) mod.db.castbarHeight = v; refreshCastbars() end,
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
    local unit = "arena" .. i
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
    local arenaFrame = i and _G["ArenaEnemyFrame" .. i]
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
    local unit = "arena" .. i
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
    local arenaFrame = i and _G["ArenaEnemyFrame" .. i]
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
    local arenaFrame = i and _G["ArenaEnemyFrame" .. i]
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
        local unit = "arena" .. i
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
local function styleCooldown(cd)
    if not cd or cd._vcStyled or not mod.db.cdTextEnabled then return end
    if haveCooldownAddon() then return end
    cd._vcStyled = true
    cd:SetHideCountdownNumbers(true)
    local fs = cd:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if ns.UI and ns.UI.Font then ns.UI.Font(fs, 13, "OUTLINE") end
    fs:SetPoint("CENTER", cd, "CENTER", 0, 0)
    cd._vcText = fs
    local acc = 0
    cd:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.05 then return end
        acc = 0
        local start, dur = self:GetCooldownTimes()
        if not start or start == 0 or not dur or dur == 0 then fs:SetText(""); return end
        local left = (start + dur) / 1000 - GetTime()
        if left <= 0 then
            fs:SetText("")
        elseif left < 6 then
            fs:SetFormattedText("%.1f", left)
            fs:SetTextColor(1, 0.4, 0.3)
        elseif left < 60 then
            fs:SetFormattedText("%d", left)
            fs:SetTextColor(1, 1, 1)
        else
            fs:SetFormattedText("%d:%02d", left / 60, left % 60)
            fs:SetTextColor(1, 1, 1)
        end
    end)
end
mod.StyleCooldown = styleCooldown

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
        local unit = "arena" .. i
        if UnitExists(unit) and UnitGUID(unit) == sourceGUID then
            if isRacial then mod.RacialUsed(unit, spellId) end
            if isDispel then mod.DispelUsed(unit, spellId) end
            return
        end
    end
end

local pvpCleuOn = false
local function setPvPCombatLog(on)
    if on == pvpCleuOn then return end
    pvpCleuOn = on
    if on then
        ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onPvPCombatLog)
    else
        ns:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onPvPCombatLog)
    end
end

local function ev_PLAYER_ENTERING_WORLD_3()
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
