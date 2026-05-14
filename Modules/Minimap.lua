-- =========================================================
-- VuloClassicUI / Modules / Minimap
-- Minimap-Button um VuloClassicUI zu öffnen.
-- Linksklick: UI öffnen/schließen
-- Rechtsklick: Module-Liste als Dropdown
-- Shift+Drag: Position auf der Minimap ändern
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("minimap", {
    name        = "Minimap Button",
    group       = "Core",
    description = "Zeigt einen Button auf der Minimap zum schnellen Öffnen von VuloClassicUI. Shift+Ziehen verschiebt den Button.",
    defaults = {
        angle  = 215,       -- Grad auf der Minimap (0 = oben, 90 = rechts, 180 = unten, 270 = links)
        radius = 80,        -- Abstand vom Minimap-Zentrum
        hide   = false,     -- komplett verstecken
    },
})

local button

-- =========================================================
-- Button erstellen
-- =========================================================
local function createButton()
    if button then return button end

    button = CreateFrame("Button", "VuloClassicUIMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)
    button:EnableMouse(true)

    -- Hintergrund-Ring (Standard-Minimap-Button-Look)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetSize(20, 20)
    button.bg:SetPoint("CENTER", 0, 1)
    button.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    -- Icon-Texture
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("CENTER", 0, 1)

    -- Wir liefern vui4.tga lokal mit (VuloClassicUI/Media/Icons/vui4.tga).
    -- Falls jemand stattdessen VuloMedia installiert hat, geht das auch.
    local iconPath
    if IsAddOnLoaded and IsAddOnLoaded("VuloMedia") then
        iconPath = "Interface\\AddOns\\VuloMedia\\Icons\\vui4"
    else
        iconPath = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\vui4"
    end
    button.icon:SetTexture(iconPath)
    button.icon:SetTexCoord(0, 1, 0, 1)

    -- Border (Standard-Ring)
    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetSize(54, 54)
    button.border:SetPoint("TOPLEFT", 0, 0)
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Highlight bei Hover
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- =========================================================
    -- Click-Handler
    -- =========================================================
    button:SetScript("OnClick", function(_, mouseBtn)
        if mouseBtn == "LeftButton" then
            if ns.UI and ns.UI.ToggleMainFrame then
                ns.UI:ToggleMainFrame()
            else
                ns:Print("UI ist noch nicht geladen.")
            end
        elseif mouseBtn == "RightButton" then
            -- Dropdown mit Modul-Liste
            mod:ShowDropdown()
        end
    end)

    -- =========================================================
    -- Drag-Handler (nur mit Shift)
    -- =========================================================
    button:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self.isMoving = true
            self:SetScript("OnUpdate", mod.OnUpdatePosition)
        end
    end)
    button:SetScript("OnDragStop", function(self)
        self.isMoving = false
        self:SetScript("OnUpdate", nil)
    end)

    -- =========================================================
    -- Tooltip
    -- =========================================================
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff9b6cffVuloClassicUI|r")
        GameTooltip:AddLine("|cffffffffLinksklick:|r Optionen öffnen")
        GameTooltip:AddLine("|cffffffffRechtsklick:|r Modul-Schnellauswahl")
        GameTooltip:AddLine("|cffffffffShift+Ziehen:|r Button verschieben")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return button
end

-- =========================================================
-- Position auf der Minimap berechnen
-- =========================================================
local function updatePosition()
    if not button then return end
    local angle  = math.rad(mod.db.angle or 215)
    local radius = mod.db.radius or 80
    local x = radius * math.cos(angle)
    local y = radius * math.sin(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

mod.UpdatePosition = updatePosition

-- OnUpdate während Dragging: Winkel aus Mausposition berechnen
function mod.OnUpdatePosition()
    if not button or not button.isMoving then return end
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local dx, dy = cx - mx, cy - my
    -- Winkel in Grad (0 = rechts, mathematisch)
    local angle = math.deg(math.atan2(dy, dx))
    mod.db.angle = angle
    updatePosition()
end

-- =========================================================
-- Sichtbarkeit
-- =========================================================
local function applyVisibility()
    if not button then return end
    if mod.db.hide then button:Hide() else button:Show() end
end

mod.ApplyVisibility = applyVisibility

-- =========================================================
-- Dropdown mit Modul-Liste (Rechtsklick)
-- =========================================================
local dropdownFrame
function mod:ShowDropdown()
    if not dropdownFrame then
        dropdownFrame = CreateFrame("Frame", "VCUIMinimapDropdown", UIParent, "UIDropDownMenuTemplate")
    end

    local menu = {}
    -- Header
    table.insert(menu, { text = "|cff9b6cffVuloClassicUI|r", isTitle = true, notCheckable = true })
    table.insert(menu, {
        text = "Optionen öffnen", notCheckable = true,
        func = function() if ns.UI then ns.UI:ToggleMainFrame() end end,
    })
    table.insert(menu, { text = "", isTitle = true, notCheckable = true })

    -- Module-Liste mit Toggle
    for _, key in ipairs(ns.moduleOrder) do
        local m = ns.modules[key]
        if m and m.db then
            table.insert(menu, {
                text     = m.name,
                checked  = function() return m.db.enabled end,
                func     = function() ns:ToggleModule(key, not m.db.enabled) end,
                isNotRadio = true,
                keepShownOnClick = true,
            })
        end
    end

    table.insert(menu, { text = "", isTitle = true, notCheckable = true })
    table.insert(menu, {
        text = "Reload UI", notCheckable = true,
        func = function() ReloadUI() end,
    })

    EasyMenu(menu, dropdownFrame, "cursor", 0, 0, "MENU", 2)
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    createButton()
    updatePosition()
    applyVisibility()
end

-- =========================================================
-- Options-Section
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = "Minimap" },
        {
            type = "toggle", label = "Button auf Minimap anzeigen",
            tooltip = "Wenn aus, ist der Button komplett versteckt.",
            get = function() return not mod.db.hide end,
            set = function(_, v) mod.db.hide = not v; applyVisibility() end,
        },
        {
            type = "slider", label = "Abstand vom Zentrum",
            min = 50, max = 120, step = 1,
            get = function() return mod.db.radius end,
            set = function(_, v) mod.db.radius = v; updatePosition() end,
        },
        {
            type = "slider", label = "Winkel (Grad)",
            min = 0, max = 360, step = 1,
            get = function() return mod.db.angle end,
            set = function(_, v) mod.db.angle = v; updatePosition() end,
        },
        { type = "spacer", height = 6 },
        { type = "desc", text = "Tipp: Du kannst den Button auch direkt auf der Minimap verschieben — halte Shift und ziehe ihn an die gewünschte Stelle." },
    }
end
