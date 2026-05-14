-- =========================================================
-- VuloClassicUI / Modules / Arena / Core
-- Position, Scale, Fonts, Mover-Overlay, Ctrl+Shift+Click zum Verschieben.
-- =========================================================
local _, ns = ...
local mod = ns.ArenaModule
local H = mod.helpers

local pendingApply = false
local unlocked = false
local hookedManage = false
local moverOverlay  -- Hint-Overlay oben am Bildschirm
local dragOverlay   -- Drag-Overlay über den Arena-Frames

-- =========================================================
-- Unmanage + Apply Position/Scale
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

    -- Wenn das Drag-Overlay sichtbar ist, dem neuen Owner-Layout folgen
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
-- Hook in TextStatusBar_UpdateTextString, damit unsere Sizes nicht überschrieben werden
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
-- Hook UIParent_ManageFramePositions, damit Blizzard nicht zurücksnappt
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
-- Drag-Overlay (nur sichtbar im Unlock-Mode)
-- Liegt über den Arena-Frames, fängt Maus-Input ab und verschiebt den Container.
-- =========================================================
-- Drag-Overlay als Standalone-Mover.
-- Der Mover ist ein eigener Frame mit fester Größe, der an der Position des
-- ArenaEnemyFrames sitzt. Beim Ziehen verschieben wir den Container mit.
-- Funktioniert auch wenn die Test-Frames noch nicht voll positioniert sind.
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

    -- Hintergrund (halbtransparent lila)
    local bg = dragOverlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(dragOverlay)
    bg:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.30)

    -- Border (dickerer lila Rand)
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

    -- Label oben
    local title = dragOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", dragOverlay, "TOP", 0, -12)
    title:SetText("|cffffffffArena-Frames|r")
    title:SetJustifyH("CENTER")

    local subtitle = dragOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -6)
    subtitle:SetText("|cffaaaaaaKlick + Ziehen\nMausrad = Scale|r")
    subtitle:SetJustifyH("CENTER")
    dragOverlay.subtitle = subtitle

    -- Drag: bewegt den Mover selbst, am Ende übernehmen wir die Position
    dragOverlay:SetScript("OnDragStart", function(self)
        if ns:InCombat() then ns:Print("Im Kampf nicht möglich."); return end
        self:StartMoving()
        self._vcMoving = true
    end)

    dragOverlay:SetScript("OnDragStop", function(self)
        if not self._vcMoving then return end
        self:StopMovingOrSizing()
        self._vcMoving = false

        -- Position des Movers übernehmen → in mod.db.pos speichern
        local point, _, relPoint, x, y = self:GetPoint(1)
        mod.db.pos.point    = point    or "CENTER"
        mod.db.pos.relPoint = relPoint or "CENTER"
        mod.db.pos.x        = x or 0
        mod.db.pos.y        = y or 0

        -- Container an die neue Position
        applyToOwner()
        ns:Print("Arena-Frames Position gespeichert.")
    end)

    -- Mausrad zum Skalieren
    dragOverlay:SetScript("OnMouseWheel", function(_, delta)
        if ns:InCombat() then return end
        local s = ns:Clamp((mod.db.scale or 1.0) + (delta > 0 and 0.05 or -0.05), 0.5, 2.0)
        mod.db.scale = s
        applyToOwner()
        if moverOverlay and moverOverlay.title then
            moverOverlay.title:SetText(string.format("|cff9b6cffArenaFrames Unlock|r  |cffaaaaaa(Scale: %.2f)|r", s))
        end
        if subtitle then
            subtitle:SetText(string.format("|cffaaaaaaKlick + Ziehen\nMausrad = Scale\nAktuell: %.2f|r", s))
        end
    end)

    return dragOverlay
end

-- Mover an die Position des ArenaEnemyFrames-Containers setzen (bei Show)
function mod:UpdateDragOverlay()
    if not dragOverlay then return end

    local p = mod.db.pos or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    dragOverlay:ClearAllPoints()
    dragOverlay:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
end

-- =========================================================
-- Hint-Overlay oben am Bildschirm (zeigt Scale, Hinweis-Text)
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
    moverOverlay.title:SetText("|cff9b6cffArenaFrames Unlock|r")

    moverOverlay.hint = moverOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moverOverlay.hint:SetPoint("TOP", moverOverlay.title, "BOTTOM", 0, -4)
    moverOverlay.hint:SetText("Lila Overlay über den Frames ziehen zum Verschieben.\nMausrad auf Overlay = Scale. /vcui arenaframes zum Beenden.")
    moverOverlay.hint:SetJustifyH("CENTER")

    moverOverlay:Hide()
end

local function setUnlocked(state)
    unlocked = state
    if state then
        if ns:InCombat() then
            ns:Print("Im Kampf nicht möglich.")
            unlocked = false
            return
        end
        createMoverOverlay()
        moverOverlay:Show()

        -- Blizzard_ArenaUI sicherstellen (für die echten Frames im Arena-Kampf)
        if not H.GetOwner() then
            if UIParentLoadAddOn and IsAddOnLoaded and not IsAddOnLoaded("Blizzard_ArenaUI") then
                UIParentLoadAddOn("Blizzard_ArenaUI")
            end
        end
        mod:ShowTestFrames(true)

        -- Drag-Overlay zeigen — ist ein eigener Mover, unabhängig von Frame-Sichtbarkeit
        ensureDragOverlay()
        mod:UpdateDragOverlay()
        dragOverlay:Show()

        ns:Print("Unlock aktiv. Klick + Ziehen auf das lila Overlay zum Verschieben.")
    else
        if moverOverlay then moverOverlay:Hide() end
        if dragOverlay  then dragOverlay:Hide() end
        mod:ShowTestFrames(false)
        ns:Print("Unlock deaktiviert.")
    end
end

mod.SetUnlocked = setUnlocked
mod.IsUnlocked  = function() return unlocked end

-- =========================================================
-- Test-Frames anzeigen (für Konfiguration ohne Arena)
-- Blizzards ArenaEnemyFrame_SetMaxArenaPlayers + Show
-- =========================================================
local function showTestArenaFrames(show)
    H.ForEach(function(frame, i)
        if show then
            frame:Show()
            -- Ohne echte Unit-Daten zeigen die Frames nichts. Setze ein Dummy.
            if frame.healthbar then
                frame.healthbar:SetMinMaxValues(0, 100)
                frame.healthbar:SetValue(75)
            end
            if frame.manabar then
                frame.manabar:SetMinMaxValues(0, 100)
                frame.manabar:SetValue(50)
            end
            local nameText = H.GetNameText(frame)
            if nameText then nameText:SetText("ArenaPlayer" .. i) end
        else
            -- Bei Frame "verstecken" nicht :Hide() machen, sonst registriert er sich neu
            -- Stattdessen den Owner refreshen
        end
    end)
    if not show then
        local owner = H.GetOwner()
        if owner and ArenaEnemyFrames_Update then
            -- Lass Blizzard die Frames wieder normal verwalten
            pcall(ArenaEnemyFrames_Update)
        end
    end
end

mod.ShowTestFrames = showTestArenaFrames

-- =========================================================
-- Lifecycle (vom Init aufgerufen)
-- =========================================================
function mod:OnEnableCore()
    installFontHooks()
    hookManageFramePositions()

    -- Submodule informieren wenn die Frames bereit sind
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
    -- Manchmal kommen die Frames verzögert
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() applyToOwner() end)
        C_Timer.After(1, function() applyToOwner(); self:RefreshAll() end)
    end
end

-- =========================================================
-- Options-Section: Position, Scale, Fonts
-- =========================================================
mod:AddOptionsSection("core", function()
    return {
        { type = "header", text = "Position & Größe" },
        {
            type = "group", layout = "row", gap = 8,
            items = {
                { type = "button", label = "Unlock", width = 80,
                  onClick = function() setUnlocked(not unlocked) end },
                { type = "button", label = "Position zurücksetzen", width = 160,
                  onClick = function()
                      mod.db.pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
                      applyToOwner()
                      ns:Print("Position zurückgesetzt.")
                  end },
            },
        },
        { type = "desc", text = "Im Unlock-Mode erscheint ein lila Overlay über den Frames. Klick + Ziehen zum Verschieben, Mausrad zum Skalieren." },
        {
            type = "slider", label = "Scale",
            min = 0.5, max = 2.0, step = 0.05,
            get = function() return mod.db.scale end,
            set = function(_, v) mod.db.scale = v; applyToOwner() end,
        },
        { type = "spacer", height = 6 },
        { type = "header", text = "Schriftgrößen" },
        {
            type = "slider", label = "Health-Bar Text",
            min = 6, max = 20, step = 1,
            get = function() return mod.db.healthSize end,
            set = function(_, v) mod.db.healthSize = v; applyAllFonts() end,
        },
        {
            type = "slider", label = "Power-Bar Text",
            min = 6, max = 20, step = 1,
            get = function() return mod.db.powerSize end,
            set = function(_, v) mod.db.powerSize = v; applyAllFonts() end,
        },
    }
end)
