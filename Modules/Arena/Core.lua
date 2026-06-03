-- =========================================================
-- VuloClassicUI / Modules / Arena / Core
-- Position, scale, fonts, mover overlay, Ctrl+Shift+click to move.
-- =========================================================
local _, ns = ...
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

local pendingApply = false
local unlocked = false
local hookedManage = false
local moverOverlay  -- hint overlay at top of screen
local dragOverlay   -- drag overlay above the arena frames

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

local function ensureDragOverlay()
    if dragOverlay then return dragOverlay end

    dragOverlay = CreateFrame("Frame", "VCUIArenaDragOverlay", UIParent)
    dragOverlay:SetSize(MOVER_WIDTH, MOVER_HEIGHT)
    dragOverlay:SetFrameStrata("HIGH")
    dragOverlay:SetFrameLevel(100)
    dragOverlay:EnableMouse(true)
    dragOverlay:SetMovable(true)
    dragOverlay:RegisterForDrag("LeftButton")
    dragOverlay:EnableMouseWheel(true)
    dragOverlay:SetClampedToScreen(true)
    dragOverlay:Hide()

    -- Background (semi-transparent purple)
    local bg = dragOverlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(dragOverlay)
    bg:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.30)

    -- Border (thicker purple edge)
    local borders = {}
    for i = 1, 4 do
        local b = dragOverlay:CreateTexture(nil, "BORDER")
        b:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        borders[i] = b
    end
    borders[1]:SetPoint("TOPLEFT", dragOverlay, "TOPLEFT"); borders[1]:SetPoint("TOPRIGHT", dragOverlay, "TOPRIGHT"); borders[1]:SetHeight(2)
    borders[2]:SetPoint("BOTTOMLEFT", dragOverlay, "BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT", dragOverlay, "BOTTOMRIGHT"); borders[2]:SetHeight(2)
    borders[3]:SetPoint("TOPLEFT", dragOverlay, "TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT", dragOverlay, "BOTTOMLEFT"); borders[3]:SetWidth(2)
    borders[4]:SetPoint("TOPRIGHT", dragOverlay, "TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT", dragOverlay, "BOTTOMRIGHT"); borders[4]:SetWidth(2)

    -- Label on top
    local title = dragOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", dragOverlay, "TOP", 0, -12)
    title:SetText(L["|cffffffffArena Frames|r"])
    title:SetJustifyH("CENTER")

    local subtitle = dragOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -6)
    subtitle:SetText(L["|cffaaaaaaClick + drag\nMouse wheel = scale|r"])
    subtitle:SetJustifyH("CENTER")
    dragOverlay.subtitle = subtitle

    -- Drag: moves the mover itself, we apply the position at the end
    dragOverlay:SetScript("OnDragStart", function(self)
        if ns:InCombat() then ns:Print(L["Not possible in combat."]); return end
        self:StartMoving()
        self._vcMoving = true
    end)

    dragOverlay:SetScript("OnDragStop", function(self)
        if not self._vcMoving then return end
        self:StopMovingOrSizing()
        self._vcMoving = false

        -- Apply mover position -> save in mod.db.pos
        local point, _, relPoint, x, y = self:GetPoint(1)
        mod.db.pos.point    = point    or "CENTER"
        mod.db.pos.relPoint = relPoint or "CENTER"
        mod.db.pos.x        = x or 0
        mod.db.pos.y        = y or 0

        -- Move container to the new position
        applyToOwner()
        ns:Print(L["Arena Frames position saved."])
    end)

    -- Mouse wheel to scale
    dragOverlay:SetScript("OnMouseWheel", function(_, delta)
        if ns:InCombat() then return end
        local s = ns:Clamp((mod.db.scale or 1.0) + (delta > 0 and 0.05 or -0.05), 0.5, 2.0)
        mod.db.scale = s
        applyToOwner()
        dragOverlay:SetScale(s)   -- keep the mover in the owner's coordinate scale
        if moverOverlay and moverOverlay.title then
            moverOverlay.title:SetText(string.format(L["|cff9b6cffArenaFrames Unlock|r  |cffaaaaaa(Scale: %.2f)|r"], s))
        end
        if subtitle then
            subtitle:SetText(string.format(L["|cffaaaaaaClick + drag\nMouse wheel = scale\nCurrent: %.2f|r"], s))
        end
    end)

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

-- =========================================================
-- Hint overlay at top of screen (shows scale, hint text)
-- =========================================================
local function createMoverOverlay()
    if moverOverlay then return end
    moverOverlay = CreateFrame("Frame", "VCUIArenaMoverHint", UIParent, "BackdropTemplate")
    moverOverlay:SetSize(320, 60)
    moverOverlay:SetPoint("TOP", UIParent, "TOP", 0, -120)
    moverOverlay:SetFrameStrata("HIGH")
    moverOverlay:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    moverOverlay:SetBackdropColor(0, 0.6, 1, 0.25)

    moverOverlay.title = moverOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moverOverlay.title:SetPoint("TOP", moverOverlay, "TOP", 0, -8)
    moverOverlay.title:SetText(L["|cff9b6cffArenaFrames Unlock|r"])

    moverOverlay.hint = moverOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moverOverlay.hint:SetPoint("TOP", moverOverlay.title, "BOTTOM", 0, -4)
    moverOverlay.hint:SetText(L["Drag the purple overlay above the frames to move.\nMouse wheel on overlay = scale. /vcui arenaframes to finish."])
    moverOverlay.hint:SetJustifyH("CENTER")

    moverOverlay:Hide()
end

local function setUnlocked(state)
    unlocked = state
    if state then
        if ns:InCombat() then
            ns:Print(L["Not possible in combat."])
            unlocked = false
            return
        end
        createMoverOverlay()
        moverOverlay:Show()

        -- Ensure Blizzard_ArenaUI (for the real frames in arena combat)
        if not H.GetOwner() then
            if UIParentLoadAddOn and IsAddOnLoaded and not IsAddOnLoaded("Blizzard_ArenaUI") then
                UIParentLoadAddOn("Blizzard_ArenaUI")
            end
        end
        mod:ShowTestFrames(true)

        -- Show drag overlay — it's its own mover, independent of frame visibility
        ensureDragOverlay()
        mod:UpdateDragOverlay()
        dragOverlay:Show()

        ns:Print(L["Unlock active. Click + drag the purple overlay to move."])
    else
        if moverOverlay then moverOverlay:Hide() end
        if dragOverlay  then dragOverlay:Hide() end
        mod:ShowTestFrames(false)
        ns:Print(L["Unlock disabled."])
    end
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
-- Lifecycle (called from init)
-- =========================================================
function mod:OnEnableCore()
    installFontHooks()
    hookManageFramePositions()

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
    -- Sometimes the frames arrive delayed
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() applyToOwner() end)
        C_Timer.After(1, function() applyToOwner(); self:RefreshAll() end)
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
                { type = "button", label = L["Unlock"], width = 80,
                  onClick = function() setUnlocked(not unlocked) end },
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
