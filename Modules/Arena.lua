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
        scale      = 1.0,
        healthSize = 10,
        powerSize  = 10,

        slotOrder        = { 1, 2, 3, 4, 5 },
        slotSpacing      = 6,
        growDirection    = "down",
        slotOffsets      = {},

        classColorHealth  = true,
        classColorName    = true,
        classIconPortrait = true,

        trinketEnabled   = true,
        trinketSize      = 28,
        trinketAnchor    = "LEFT",
        trinketOffsetX   = -6,
        trinketOffsetY   = 0,

        drEnabled   = false,
        drSize      = 24,

        castbarEnabled = false,
        castbarWidth   = 120,
        castbarHeight  = 14,
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

function mod:OnEnable()
    if self.OnEnableCore then self:OnEnableCore() end
    for _, h in ipairs(self._onEnableHandlers) do
        local ok, err = pcall(h, self)
        if not ok then
            ns:Print(L["|cffff5555Arena submodule OnEnable error:|r %s"], tostring(err))
        end
    end
end

mod._optionsBuilders = {}

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

local function applyToOwner()
    local owner = H.GetOwner()
    if not owner then return end
    if ns:InCombat() then pendingApply = true; return end

    local p = mod.db.pos
    unmanageOwner()
    owner:ClearAllPoints()
    owner:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    owner:SetScale(mod.db.scale or 1.0)

    if dragOverlay and dragOverlay:IsShown() and mod.UpdateDragOverlay then
        mod:UpdateDragOverlay()
    end
end

mod.ApplyOwnerPosition = applyToOwner

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

-- Proxy overlay is dragged instead of the secure container (StartMoving on it would taint); both are kept at identical scale + CENTER offset.
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

function mod:OnEnableCore()
    installFontHooks()
    hookManageFramePositions()
    ensureDragOverlay()

    self:OnArenaFramesReady(function(frame, i)
        applyArenaFonts(frame)
    end)

    ns:RegisterEvent("PLAYER_LOGIN",          function() mod:Refresh() end)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() mod:Refresh() end)
    ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() mod:Refresh() end)
    ns:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_ArenaUI" then mod:Refresh() end
    end)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if pendingApply then pendingApply = false; mod:Refresh() end
        applyBGUnitWatch()
    end)

    self:Refresh()
end

function mod:Refresh()
    unmanageOwner()
    applyToOwner()
    if self:RefreshAll() then
        applyAllFonts()
    end

    if not unlocked and not ns:InCombat() then
        H.ForEach(function(frame, i)
            if not (UnitExists and UnitExists("arena" .. i)) then frame:Hide() end
        end)
    end

    applyBGUnitWatch()

    -- frames can arrive a tick or two late
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() applyToOwner() end)
        C_Timer.After(1, function() applyToOwner(); self:RefreshAll(); applyBGUnitWatch() end)
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

(function(...)
local _, ns = ...
if ns.isEra then return end
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

local function applyLayout()
    local owner = H.GetOwner()
    if not owner then return end
    -- secure frames: moving them in combat is blocked and taints; re-applied on PLAYER_REGEN_ENABLED
    if InCombatLockdown() then return end

    local order   = mod.db.slotOrder   or { 1, 2, 3, 4, 5 }
    local spacing = mod.db.slotSpacing or 6
    local grow    = mod.db.growDirection or "down"

    local previous = nil
    for visualIndex, slotIndex in ipairs(order) do
        local frame = _G["ArenaEnemyFrame" .. slotIndex]
        if frame then
            frame:ClearAllPoints()
            local offsets = mod.db.slotOffsets and mod.db.slotOffsets[slotIndex] or { x = 0, y = 0 }

            if not previous then
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

local layoutHooked = false
local function hookLayout()
    if layoutHooked or not hooksecurefunc then return end
    layoutHooked = true

    if _G.ArenaEnemyFrames_UpdatePlayer then
        hooksecurefunc("ArenaEnemyFrames_UpdatePlayer", function()
            if not mod._enabled then return end
            applyLayout()
        end)
    end
    if _G.ArenaEnemyFrames_Update then
        hooksecurefunc("ArenaEnemyFrames_Update", function()
            if not mod._enabled then return end
            applyLayout()
        end)
    end

    -- catches updates the in-combat guard above skipped
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if mod._enabled then applyLayout() end
    end)
end

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
    -- layout is applied for all slots at once, nothing per frame
end)

local layoutInitFrame = CreateFrame("Frame")
layoutInitFrame:RegisterEvent("ADDON_LOADED")
layoutInitFrame:RegisterEvent("PLAYER_LOGIN")
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

    if C_Timer and C_Timer.After then
        C_Timer.After(duration + 0.1, function()
            if activeCDs[unit] and activeCDs[unit].start + activeCDs[unit].duration <= GetTime() then
                tf.icon:SetDesaturated(false)
                activeCDs[unit] = nil
            end
        end)
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

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    local inArena = false
    if IsInInstance then
        local _, instanceType = IsInInstance()
        inArena = (instanceType == "arena")
    end
    if not inArena then resetAllCDs() end
    setCombatLog(inArena)
end)
ns:RegisterEvent("ARENA_OPPONENT_UPDATE", function(_, _, eventType)
    if eventType == "seen" then resetAllCDs() end
end)

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

    local container = drFrames[i]
    if not container then
        container = createDRContainer(arenaFrame, i)
        drFrames[i] = container
        container:ClearAllPoints()
        container:SetPoint("LEFT", arenaFrame, "RIGHT", 8, 0)
    end

    local state = drState[unit] or {}
    local visible = {}
    for cat, data in pairs(state) do
        if data.expires > GetTime() then
            table.insert(visible, { cat = cat, data = data })
        end
    end
    table.sort(visible, function(a, b) return a.cat < b.cat end)

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

local function resetAll()
    drState = {}
    for _, container in pairs(drFrames) do
        for _, icon in pairs(container.icons) do icon:Hide() end
    end
end

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

    local remaining = self.endTime - now
    if remaining < 0 then remaining = 0 end
    self.timer:SetText(string.format("%.1f", remaining))

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
            C_Timer.After(0.7, function() if cb._hideToken == token then cb:Hide() end end)
        else
            cb:Hide()
        end
    else
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
