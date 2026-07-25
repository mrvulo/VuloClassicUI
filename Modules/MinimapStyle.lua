-- Minimap reskin. Tracking/battlefield frames differ per client (TBC 20505 vs Era 11508), so every lookup is guarded.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("minimapstyle", {
    name        = "Minimap",
    group       = "UI Reskin",
    description = "A modern minimap: round with a clean dark ring and accent line, zone text and clock in a slim panel, mouse-wheel zoom, movable and scalable. Optionally hides other addons' buttons until mouseover.",
    defaults = {
        enabled       = true,
        scale         = 1.15,
        x             = 0,
        y             = 0,
        moved         = false,
        zonePanel     = "top",    -- "top" | "bottom" | "hidden"
        showClock     = true,
        showDate      = true,
        accentRing    = true,
        ringColorMode = "accent", -- "accent" | "class" | "custom"
        ringColor     = { r = 0.608, g = 0.424, b = 1 },
        shape         = "round",
        zoomButtons   = true,
        showDayNight  = false,
        skinButtons   = true,
        buttonsOnHover = false,
        showPingChat  = false,
        unlocked      = false,
    },
})

local MEDIA = "Interface\\AddOns\\VuloClassicUI\\Media\\Minimap\\"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MAP_SIZE = 140
-- Map edge sits at r=213 of the 256px ring texture.
local RING_SCALE = 256 / 213

local mm = {}

local function db() return mod.db end

-- On the corner-default anchor db.x/y must still hold the real center offsets, or the first arrow-key nudge applies from 0,0.
function mm.syncCornerOffsets()
    if db().moved or not mm.base then return end
    local x, y = ns:GetCenterOffsets(mm.base)
    if x and y then
        db().x, db().y = x, y
    end
end

function mm.ensureBase()
    if mm.base then return mm.base end
    local base = CreateFrame("Frame", "VCUI_MinimapFrame", UIParent)
    base:SetSize(MAP_SIZE + 12, MAP_SIZE + 12 + 22)
    if db().moved then
        base:SetPoint("CENTER", UIParent, "CENTER", db().x or 0, db().y or 0)
    else
        base:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
    end
    base:SetFrameStrata("LOW")
    mm.base = base

    mm.panel = CreateFrame("Frame", "VCUI_MinimapPanel", base)
    mm.panel:SetSize(MAP_SIZE + 22, 18)
    local pbg = mm.panel:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints(mm.panel)
    pbg:SetTexture(MEDIA .. "capsule.tga")
    if pbg.SetSnapToPixelGrid then pbg:SetSnapToPixelGrid(false); pbg:SetTexelSnappingBias(0) end

    base.mover = ns:CreateMover(base, {
        key    = "minimapstyle",
        label  = L["|cffffffffMINIMAP|r"],
        db     = db(),
        width  = MAP_SIZE + 20,
        height = MAP_SIZE + 40,
        onMove = function(x, y)
            -- Only an explicit reset restores the corner anchor; a drag can legitimately land on 0,0.
            if x == 0 and y == 0 and ns._inMoverReset then
                db().moved = false
                mm.base:ClearAllPoints()
                mm.base:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
                mm.syncCornerOffsets()
            else
                db().moved = true
            end
            ns:Print(string.format(L["Minimap: x=%.0f, y=%.0f"], x, y))
        end,
    })
    return base
end

function mm.adoptMinimap()
    if mm.adopted then return end
    mm.adopted = true
    -- Snapshot on first adoption only, else a re-enable would record our own base as the original.
    if not mm.origParent then
        mm.origParent = Minimap:GetParent()
        mm.origPoints = {}
        for i = 1, Minimap:GetNumPoints() do
            mm.origPoints[i] = { Minimap:GetPoint(i) }
        end
    end

    Minimap:SetParent(mm.base)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", mm.base, "CENTER", 0, -11)
    Minimap:SetSize(MAP_SIZE, MAP_SIZE)

    -- Decoration is created once: textures can't be destroyed, so recreating would leak per enable cycle.
    if mm.ring then return end

    local ringSize = MAP_SIZE * RING_SCALE
    local function ringTex(file, sub)
        local t = Minimap:CreateTexture(nil, "ARTWORK", nil, sub)
        t:SetTexture(MEDIA .. file)
        t:SetSize(ringSize, ringSize)
        t:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        return t
    end
    mm.shadow = ringTex("ring_shadow.tga", 5)
    mm.shadow:SetVertexColor(0, 0, 0, 0.65)
    mm.ring = ringTex("ring_main.tga", 6)
    mm.accent = ringTex("ring_accent.tga", 7)
    mm.applyRingColor()

    mm.squareFrame = CreateFrame("Frame", nil, mm.base)
    mm.squareFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1, 1)
    mm.squareFrame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 1, -1)
    mm.squareFrame:SetFrameLevel(math.max(Minimap:GetFrameLevel() - 1, 0))
    local bc = ns.COLORS and (ns.COLORS.borderDark or ns.COLORS.border) or { r = 0.15, g = 0.15, b = 0.18 }
    local sq = {}
    for i = 1, 4 do
        local t = mm.squareFrame:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(bc.r, bc.g, bc.b, 1)
        sq[i] = t
    end
    sq[1]:SetPoint("TOPLEFT"); sq[1]:SetPoint("TOPRIGHT"); sq[1]:SetHeight(1)
    sq[2]:SetPoint("BOTTOMLEFT"); sq[2]:SetPoint("BOTTOMRIGHT"); sq[2]:SetHeight(1)
    sq[3]:SetPoint("TOPLEFT"); sq[3]:SetPoint("BOTTOMLEFT"); sq[3]:SetWidth(1)
    sq[4]:SetPoint("TOPRIGHT"); sq[4]:SetPoint("BOTTOMRIGHT"); sq[4]:SetWidth(1)
    if ns.UI and ns.UI.CreateShadow then ns.UI:CreateShadow(mm.squareFrame) end
    mm.squareFrame:Hide()
end

function mm.applyRingColor()
    if not mm.accent then return end
    local d = db()
    local c
    if d.ringColorMode == "class" then
        local _, token = UnitClass("player")
        c = token and (_G.RAID_CLASS_COLORS or {})[token]
    elseif d.ringColorMode == "custom" then
        c = d.ringColor
    end
    if not (c and c.r) then
        c = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
    end
    mm.accent:SetVertexColor(c.r, c.g, c.b, 1)
end

-- Button libraries read this global to place icons along the minimap edge, so
-- it genuinely has to be global. What it must not do is throw away whoever was
-- there first: the old code redefined it unconditionally on every applyShape
-- call, so any other addon's answer was gone for the session and ours kept
-- claiming "round" even after this module was switched off.
local prevGetMinimapShape = rawget(_G, "GetMinimapShape")
local shapeReporterInstalled = false

local function installShapeReporter()
    if shapeReporterInstalled then return end
    shapeReporterInstalled = true
    GetMinimapShape = function()
        if mod.active then
            return db().shape == "square" and "SQUARE" or "ROUND"
        end
        -- switched off: answer the way the client would have without us
        if prevGetMinimapShape then return prevGetMinimapShape() end
        return "ROUND"
    end
end

function mm.applyShape()
    local square = db().shape == "square"
    if square then
        Minimap:SetMaskTexture("Interface\\Buttons\\WHITE8X8")
        mm.ring:Hide(); mm.accent:Hide(); mm.shadow:Hide()
        mm.squareFrame:Show()
    else
        Minimap:SetMaskTexture(ROUND_MASK)
        mm.squareFrame:Hide()
        mm.shadow:Show()
        mm.ring:Show()
        mm.accent:SetShown(db().accentRing ~= false)
    end
    installShapeReporter()
end

-- Hides are repeatable across enable cycles; the Show-hooks below are one-shot since hooksecurefunc can't be removed.
function mm.hideDefaultArt()
    local function gone(f)
        if f and f.Hide then f:Hide() end
    end
    gone(_G.MinimapBorder)
    gone(_G.MinimapBorderTop)
    gone(_G.MinimapToggleButton)
    gone(_G.MiniMapWorldMapButton)
    gone(_G.MinimapNorthTag)
    gone(_G.MinimapCompassTexture)
    if _G.MinimapCluster and _G.MinimapCluster.BorderTop then _G.MinimapCluster.BorderTop:Hide() end
end

function mm.installDefaultHooks()
    if mm.hooksInstalled then return end
    mm.hooksInstalled = true
    local function keepHidden(f)
        if f and f.Hide then
            hooksecurefunc(f, "Show", function(self)
                if mod.active then self:Hide() end
            end)
        end
    end
    keepHidden(_G.MiniMapWorldMapButton)
    keepHidden(_G.MinimapNorthTag)
    keepHidden(_G.MinimapCompassTexture)   -- Blizzard re-shows it whenever rotate-minimap is enabled
    if _G.GameTimeFrame then
        hooksecurefunc(_G.GameTimeFrame, "Show", function(self)
            if mod.active and not db().showDayNight then self:Hide() end
        end)
    end
end

function mm.applyToggles()
    local d = db()
    if _G.MinimapZoomIn and _G.MinimapZoomOut then
        _G.MinimapZoomIn:Hide()
        _G.MinimapZoomOut:Hide()
    end
    if mm.zoomIn then
        mm.zoomIn:SetShown(d.zoomButtons ~= false)
        mm.zoomOut:SetShown(d.zoomButtons ~= false)
        mm.updateZoomButtons()
    end
    if _G.GameTimeFrame then
        _G.GameTimeFrame:SetShown(d.showDayNight and true or false)
        if d.showDayNight then
            _G.GameTimeFrame:ClearAllPoints()
            _G.GameTimeFrame:SetParent(Minimap)
            _G.GameTimeFrame:SetPoint("CENTER", Minimap, "TOPRIGHT", -14, -14)
            _G.GameTimeFrame:SetScale(0.7)
        end
    end
end

-- Some locales anchor the clock ticker off-center; re-pin it. Returns false until the lazy clock addon exists.
function mm.styleClockTicker()
    local clock = _G.TimeManagerClockButton
    local ticker = _G.TimeManagerClockTicker
    if not (clock and ticker) then return false end
    if ns.UI and ns.UI.FONT_PATH then ticker:SetFont(ns.UI.FONT_PATH, 11, "") end
    ticker:SetTextColor(0.95, 0.95, 1)
    ticker:ClearAllPoints()
    ticker:SetPoint("CENTER", clock, "CENTER", 0, 0)
    return true
end

function mm.setupPanel()
    if mm.panelWired then return end
    mm.panelWired = true

    local ztb = _G.MinimapZoneTextButton
    if ztb then
        ztb:SetParent(mm.panel)
        ztb:ClearAllPoints()
        ztb:SetPoint("LEFT", mm.panel, "LEFT", 6, 0)
        ztb:SetHeight(16)
        ztb:SetScript("OnClick", function()
            if mod.active and ToggleWorldMap then ToggleWorldMap() end
        end)
        local zt = _G.MinimapZoneText
        if zt then
            zt:ClearAllPoints()
            zt:SetPoint("LEFT", ztb, "LEFT", 0, 0)
            zt:SetPoint("RIGHT", ztb, "RIGHT", 0, 0)
            zt:SetJustifyH("LEFT")
            zt:SetWordWrap(false)
            if ns.UI and ns.UI.FONT_PATH then
                zt:SetFont(ns.UI.FONT_PATH, 11, "")
            end
        end
    end

    local loader = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn or _G.UIParentLoadAddOn
    if loader then pcall(loader, "Blizzard_TimeManager") end
    local clock = _G.TimeManagerClockButton
    if clock then
        local regions = { clock:GetRegions() }
        if regions[1] and regions[1].Hide then regions[1]:Hide() end   -- unnamed border art, only reachable by region index
        clock:SetParent(mm.panel)
        clock:ClearAllPoints()
        clock:SetPoint("RIGHT", mm.panel, "RIGHT", -4, 0)
        clock:SetSize(38, 16)
        mm.clockStyled = mm.styleClockTicker()
    end

    if not mm.dateBtn then
        local dateBtn = CreateFrame("Button", "VCUI_MinimapDate", mm.panel)
        dateBtn:SetSize(34, 16)
        local dtxt = dateBtn:CreateFontString(nil, "OVERLAY")
        dtxt:SetAllPoints(dateBtn)
        dtxt:SetJustifyH("CENTER")
        if ns.UI and ns.UI.FONT_PATH then dtxt:SetFont(ns.UI.FONT_PATH, 11, "")
        else dtxt:SetFontObject("GameFontNormalSmall") end
        dtxt:SetTextColor(0.95, 0.95, 1)
        dateBtn.text = dtxt
        local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
        dateBtn:SetScript("OnEnter", function(self)
            self.text:SetTextColor(ac.r, ac.g, ac.b)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                local ok, s = pcall(date, "%A, %d.%m.%Y")
                GameTooltip:SetText(ok and s or "")
                GameTooltip:Show()
            end
        end)
        dateBtn:SetScript("OnLeave", function(self)
            self.text:SetTextColor(0.95, 0.95, 1)
            if GameTooltip then GameTooltip:Hide() end
        end)
        dateBtn:SetScript("OnClick", function()
            if not mod.active then return end
            local loader = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
            if loader then pcall(loader, "Blizzard_Calendar") end
            if _G.ToggleCalendar then pcall(_G.ToggleCalendar) end
        end)
        mm.dateBtn = dateBtn
        mm.updateDate()
        if C_Timer and C_Timer.NewTicker and not mm.dateTicker then
            mm.dateTicker = C_Timer.NewTicker(60, function() mm.updateDate() end)
        end
    end
end

function mm.updateDate()
    if not mm.dateBtn then return end
    local ok, s = pcall(date, "%d.%m")
    mm.dateBtn.text:SetText(ok and s or "")
end

function mm.applyPanel()
    local d = db()
    local pos = d.zonePanel or "top"
    local clock = _G.TimeManagerClockButton
    local ztb = _G.MinimapZoneTextButton

    if pos == "hidden" then
        mm.panel:Hide()
        if clock then clock:Hide() end
        if ztb then ztb:Hide() end
        if mm.dateBtn then mm.dateBtn:Hide() end
        return
    end
    mm.panel:Show()
    mm.panel:ClearAllPoints()
    if pos == "bottom" then
        mm.panel:SetPoint("TOP", Minimap, "BOTTOM", 0, -6)
    else
        mm.panel:SetPoint("BOTTOM", Minimap, "TOP", 0, 6)
    end

    local showClock = d.showClock ~= false and clock ~= nil
    local showDate  = d.showDate ~= false and mm.dateBtn ~= nil
    if clock then clock:SetShown(showClock) end
    if mm.dateBtn then mm.dateBtn:SetShown(showDate) end
    -- Clock addon can load after setupPanel ran, so retry styling until it takes.
    if showClock and not mm.clockStyled then
        mm.clockStyled = mm.styleClockTicker()
    end

    local anchor, point, x = mm.panel, "RIGHT", -4
    if showDate then
        mm.dateBtn:ClearAllPoints()
        mm.dateBtn:SetPoint("RIGHT", mm.panel, "RIGHT", -4, 0)
        anchor, point, x = mm.dateBtn, "LEFT", -4
    end
    if showClock then
        clock:ClearAllPoints()
        clock:SetPoint("RIGHT", anchor, point, x, 0)
        anchor, point, x = clock, "LEFT", -4
    end
    if ztb then
        ztb:Show()
        ztb:ClearAllPoints()
        ztb:SetPoint("LEFT", mm.panel, "LEFT", 6, 0)
        if anchor == mm.panel then
            ztb:SetPoint("RIGHT", mm.panel, "RIGHT", -6, 0)
        else
            ztb:SetPoint("RIGHT", anchor, point, x, 0)
        end
    end
    mm.updateDate()
end

function mm.placeLFGEye()
    local eye = _G.LFGMinimapFrame
    if not eye then return end
    eye:SetParent(Minimap)
    eye:ClearAllPoints()
    eye:SetPoint("CENTER", Minimap, "BOTTOMRIGHT", -10, 16)
end

function mm.onAddonLoaded(_, name)
    if name == "Blizzard_GroupFinder_VanillaStyle" and mod.active then
        mm.placeLFGEye()
    end
end

function mm.setupCorners()
    if mm.cornersWired then return end
    mm.cornersWired = true

    local tracking = _G.MiniMapTracking or _G.MiniMapTrackingFrame
    if tracking then
        tracking:SetParent(Minimap)
        tracking:ClearAllPoints()
        tracking:SetPoint("CENTER", Minimap, "TOPLEFT", 10, -22)
        tracking:SetSize(26, 26)
        local border = _G.MiniMapTrackingButtonBorder or _G.MiniMapTrackingBorder
        if border and border.Hide then
            border:Hide()
            hooksecurefunc(border, "Show", function(self)
                if mod.active then self:Hide() end
            end)
        end
        local iconBG = _G.MiniMapTrackingBackground
        if iconBG and iconBG.Hide then iconBG:Hide() end
        local icon = _G.MiniMapTrackingIcon
        if icon then
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", tracking, "CENTER", 0, 0)
            icon:SetSize(18, 18)
            if not mm.trackingMask and icon.AddMaskTexture then
                mm.trackingMask = tracking:CreateMaskTexture()
                mm.trackingMask:SetTexture(ROUND_MASK)
                mm.trackingMask:SetAllPoints(icon)
                icon:AddMaskTexture(mm.trackingMask)
            end
        end
    end

    local mail = _G.MiniMapMailFrame
    if mail then
        mail:SetParent(Minimap)
        mail:ClearAllPoints()
        mail:SetPoint("CENTER", Minimap, "TOPRIGHT", -20, -20)
        if _G.MiniMapMailBorder then _G.MiniMapMailBorder:Hide() end
        local mi = _G.MiniMapMailIcon
        if mi then
            mi:ClearAllPoints()
            mi:SetPoint("CENTER", mail, "CENTER", 0, 0)
            mi:SetSize(18, 18)
        end
    end

    local bf = _G.MiniMapBattlefieldFrame or _G.MiniMapLFGFrame
    if bf then
        bf:SetParent(Minimap)
        bf:ClearAllPoints()
        bf:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 20, 20)
    end
    -- Era group-finder eye is anchored to the stranded old backdrop; also re-homed from ADDON_LOADED.
    mm.placeLFGEye()

    local diff = _G.MiniMapInstanceDifficulty
    if diff then
        diff:SetParent(Minimap)
        diff:ClearAllPoints()
        diff:SetPoint("CENTER", Minimap, "BOTTOMRIGHT", -16, 16)
        diff:SetScale(0.8)
    end
end

function mm.setupDrag()
    if mm.dragWired then return end
    mm.dragWired = true
    Minimap:RegisterForDrag("LeftButton")
    Minimap:SetScript("OnDragStart", function()
        if mod.active and IsShiftKeyDown() and mm.base then
            mm.base:StartMoving()
            mm.dragging = true
        end
    end)
    Minimap:SetScript("OnDragStop", function()
        if not mm.dragging then return end
        mm.dragging = false
        mm.base:StopMovingOrSizing()
        local x, y = ns:GetCenterOffsets(mm.base)
        if x and y then
            db().x, db().y = x, y
            db().moved = true
            mm.base:ClearAllPoints()
            mm.base:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end
    end)
end

function mm.updateZoomButtons()
    if not mm.zoomIn then return end
    local z, top = Minimap:GetZoom(), Minimap:GetZoomLevels() - 1
    mm.zoomIn:SetAlpha(z >= top and 0.3 or 1)
    mm.zoomOut:SetAlpha(z <= 0 and 0.3 or 1)
end

function mm.setupZoom()
    if mm.zoomWired then return end
    mm.zoomWired = true
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:SetZoom(math.min(self:GetZoom() + 1, self:GetZoomLevels() - 1))
        else
            self:SetZoom(math.max(self:GetZoom() - 1, 0))
        end
        mm.updateZoomButtons()
    end)
    local function makeZoom(glyph, dz, x, y)
        local b = CreateFrame("Button", nil, Minimap)
        b:SetSize(18, 18)
        b:SetPoint("CENTER", Minimap, "TOPRIGHT", x, y)
        b:SetFrameLevel(Minimap:GetFrameLevel() + 3)
        local fs = b:CreateFontString(nil, "OVERLAY")
        local font = (ns.UI and ns.UI.FONT_PATH) or "Fonts\\FRIZQT__.TTF"
        fs:SetFont(font, 19, "OUTLINE")
        fs:SetPoint("CENTER", 0, 0)
        fs:SetText(glyph)
        fs:SetTextColor(1, 1, 1, 0.85)
        b._fs = fs
        b:SetScript("OnEnter", function(self)
            local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
            self._fs:SetTextColor(ac.r, ac.g, ac.b, 1)
        end)
        b:SetScript("OnLeave", function(self) self._fs:SetTextColor(1, 1, 1, 0.85) end)
        b:SetScript("OnClick", function()
            local z = Minimap:GetZoom() + dz
            Minimap:SetZoom(math.max(0, math.min(z, Minimap:GetZoomLevels() - 1)))
            mm.updateZoomButtons()
        end)
        return b
    end
    mm.zoomIn  = makeZoom("+", 1, -4, -7)
    mm.zoomOut = makeZoom("–", -1, 6, -26)
end

-- Blizzard-owned Minimap children; anything else Button-shaped is treated as a third-party icon.
local BLIZZ_CHILDREN = {
    MinimapZoomIn = true, MinimapZoomOut = true, MiniMapWorldMapButton = true,
    MinimapToggleButton = true, MiniMapTracking = true, MiniMapTrackingFrame = true,
    MiniMapMailFrame = true, MiniMapBattlefieldFrame = true, MiniMapLFGFrame = true,
    LFGMinimapFrame = true,
    MiniMapInstanceDifficulty = true, GameTimeFrame = true, TimeManagerClockButton = true,
    MinimapBackdrop = true, MiniMapVoiceChatFrame = true, MinimapZoneTextButton = true,
}

function mm.skinAddonButton(btn)
    if btn._vcuiMapSkin then return end
    btn._vcuiMapSkin = true
    for _, r in ipairs({ btn:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then
            local tex = r:GetTexture()
            if tex == 136430 then       -- MiniMap-TrackingBorder
                r:SetTexture(nil); r:SetAlpha(0)
            elseif tex == 136467 then   -- UI-Minimap-Background
                r:SetTexture(nil); r:SetAlpha(0)
            end
        end
    end
    local icon = btn.icon
    if not icon then
        for _, r in ipairs({ btn:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") and r:GetDrawLayer() == "ARTWORK" then
                icon = r
                break
            end
        end
    end
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        icon:SetSize(19, 19)
        if btn.CreateMaskTexture and icon.AddMaskTexture then
            local mask = btn:CreateMaskTexture()
            mask:SetTexture(ROUND_MASK)
            mask:SetAllPoints(icon)
            icon:AddMaskTexture(mask)
        end
    end
    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(MEDIA .. "ring_main.tga")
    ring:SetVertexColor(0.07, 0.07, 0.09, 1)
    ring:SetSize(19 * RING_SCALE * 1.12, 19 * RING_SCALE * 1.12)
    ring:SetPoint("CENTER", btn, "CENTER", 0, 0)
    if ring.SetSnapToPixelGrid then ring:SetSnapToPixelGrid(false); ring:SetTexelSnappingBias(0) end
end

function mm.collectAddonButtons()
    mm.addonButtons = mm.addonButtons or {}
    if wipe then wipe(mm.addonButtons) else mm.addonButtons = {} end
    for _, child in ipairs({ Minimap:GetChildren() }) do
        local name = child.GetName and child:GetName()
        if child:IsObjectType("Button") and not BLIZZ_CHILDREN[name or ""] then
            local w = child:GetWidth() or 0
            if w > 20 and w < 44 then
                mm.addonButtons[#mm.addonButtons + 1] = child
                if db().skinButtons then mm.skinAddonButton(child) end
            end
        end
    end
end

function mm.applyButtonVisibility()
    local hover = db().buttonsOnHover
    for _, b in ipairs(mm.addonButtons or {}) do
        b:SetAlpha((hover and not mm.hovered) and 0 or 1)
    end
end

-- Optional: catches late icon registrations. No hard dependency, retried once the lib exists.
function mm.hookButtonLib()
    if mm.libHooked then return end
    local ldbi = _G.LibStub and _G.LibStub.GetLibrary
        and _G.LibStub("LibDBIcon-1.0", true)
    if not (ldbi and ldbi.RegisterCallback) then return end
    mm.libHooked = true
    ldbi.RegisterCallback(mm, "LibDBIcon_IconCreated", function()
        if not mod.active then return end
        mm.collectAddonButtons()
        mm.applyButtonVisibility()
    end)
end

function mm.setupHover()
    if mm.hoverWired then return end
    mm.hoverWired = true
    local acc = 0
    mm.base:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.1 then return end
        acc = 0
        if not (mod.active and db().buttonsOnHover) then return end
        local over = self:IsMouseOver(10, -10, -10, 10)
        if over ~= mm.hovered then
            mm.hovered = over
            mm.applyButtonVisibility()
        end
    end)
end

function mm.onPing(_, unit)
    if not db().showPingChat then return end
    if not unit then return end
    local name = UnitName(unit)
    if name then
        ns:Print(string.format(L["Minimap ping: %s"], name))
    end
end

function mm.applyAll()
    -- Option setters call this unconditionally; bail while disabled or we would re-skin the restored map.
    if not mod.active then return end
    if not mm.base then return end
    mm.base:SetScale(db().scale or 1)
    mm.syncCornerOffsets()   -- must follow SetScale: offsets are frame-local units
    mm.applyRingColor()
    mm.applyShape()
    mm.applyPanel()
    mm.applyToggles()
    mm.collectAddonButtons()
    mm.applyButtonVisibility()
end

function mm.onEnteringWorld()
    if not mod.active then return end
    -- GetCenter is nil and UI scale not final at ADDON_LOADED, so re-sync once layout has settled.
    mm.syncCornerOffsets()
    mm.hookButtonLib()
    mm.collectAddonButtons()
    mm.applyButtonVisibility()
end

function mod:OnEnable()
    mod.active = true
    -- setUnlocked is the only thing that shows the mover, and it does not run on
    -- load, so a saved unlock leaves the frame stuck with nothing to grab.
    db().unlocked = false
    if not db()._scaleBumped then
        if (db().scale or 1) == 1.0 then db().scale = 1.15 end
        db()._scaleBumped = true
    end
    mm.ensureBase()
    mm.adoptMinimap()
    mm.hideDefaultArt()
    mm.installDefaultHooks()
    mm.setupPanel()
    mm.setupCorners()
    mm.setupZoom()
    mm.setupDrag()
    mm.setupHover()
    mm.hookButtonLib()
    mm.applyAll()
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", mm.onEnteringWorld)
    ns:RegisterEvent("MINIMAP_PING", mm.onPing)
    ns:RegisterEvent("ADDON_LOADED", mm.onAddonLoaded)
    -- Third-party icons often appear a moment after login.
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
            if mod.active then mm.collectAddonButtons(); mm.applyButtonVisibility() end
        end)
    end
end

function mod:OnDisable()
    mod.active = false
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", mm.onEnteringWorld)
    ns:UnregisterEvent("MINIMAP_PING", mm.onPing)
    ns:UnregisterEvent("ADDON_LOADED", mm.onAddonLoaded)
    -- Best-effort restore; fonts and moved children only come back fully with a /reload.
    if mm.adopted then
        mm.adopted = false
        if mm.ring then mm.ring:Hide() end
        if mm.accent then mm.accent:Hide() end
        if mm.shadow then mm.shadow:Hide() end
        if mm.squareFrame then mm.squareFrame:Hide() end
        if mm.panel then mm.panel:Hide() end
        Minimap:SetMaskTexture(ROUND_MASK)
        Minimap:SetParent(mm.origParent or _G.MinimapCluster or UIParent)
        Minimap:ClearAllPoints()
        if mm.origPoints and mm.origPoints[1] then
            for _, p in ipairs(mm.origPoints) do
                Minimap:SetPoint(p[1], p[2], p[3], p[4], p[5])
            end
        else
            Minimap:SetPoint("CENTER", UIParent, "TOPRIGHT", -100, -120)
        end
        if _G.MinimapBorder then _G.MinimapBorder:Show() end
        if mm.zoomIn then mm.zoomIn:Hide(); mm.zoomOut:Hide() end
        if _G.MinimapZoomIn then _G.MinimapZoomIn:Show(); _G.MinimapZoomOut:Show() end
        mm.hovered = true
        for _, b in ipairs(mm.addonButtons or {}) do b:SetAlpha(1) end
        if mm.base and mm.base.mover then mm.base.mover:Hide() end
        ns:Print(L["Minimap module disabled — /reload restores the default layout completely."])
    end
end

local function setUnlocked(state)
    db().unlocked = state
    if not mm.base then return end
    if state then
        mm.base.mover:Show()
        ns:Print(L["Minimap mover active. |cff9b6cffDrag|r or |cff9b6cffarrow keys|r (SHIFT = 5px)."])
    else
        mm.base.mover:Hide()
    end
end

function mod:GetOptions()
    local d = db()
    return {
        { type = "header", text = L["Minimap"] },
        { type = "desc", text = L["|cffaaaaaaA modern round minimap with a beveled ring, zone text and clock in a slim pill. Zoom with the mouse wheel. |cffffffffShift+drag the map|r to move it — or use Unlock / the addon's own Edit Mode (/vedit). Blizzard's Edit Mode does not manage this map.|r"] },

        { type = "spacer", height = 6 },
        { type = "dropdown", label = L["Shape"],
          values = {
              { value = "round",  text = L["Round"] },
              { value = "square", text = L["Square"] },
          },
          get = function() return d.shape or "round" end,
          set = function(_, v) d.shape = v; mm.applyAll() end },
        { type = "dropdown", label = L["Ring color"],
          values = {
              { value = "accent", text = L["Accent (purple)"] },
              { value = "class",  text = L["Class color"] },
              { value = "custom", text = L["Custom color"] },
          },
          get = function() return d.ringColorMode or "accent" end,
          set = function(_, v) d.ringColorMode = v; mm.applyRingColor() end },
        { type = "color", label = L["Custom ring color"], width = 160,
          get = function() return d.ringColor end,
          set = function(r, g, b)
              d.ringColor = { r = r, g = g, b = b }
              d.ringColorMode = "custom"
              mm.applyRingColor()
          end },
        { type = "toggle", label = L["Accent ring"],
          tooltip = L["A thin colored line around the dark ring (round shape only)."],
          get = function() return d.accentRing ~= false end,
          set = function(_, v) d.accentRing = v; mm.applyAll() end },
        { type = "slider", label = L["Scale"],
          min = 0.7, max = 1.6, step = 0.05,
          get = function() return d.scale or 1 end,
          set = function(_, v) d.scale = v; mm.applyAll() end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Zone panel"] },
        { type = "dropdown", label = L["Zone text and clock"],
          values = {
              { value = "top",    text = L["Above the map"] },
              { value = "bottom", text = L["Below the map"] },
              { value = "hidden", text = L["Hidden"] },
          },
          get = function() return d.zonePanel or "top" end,
          set = function(_, v) d.zonePanel = v; mm.applyAll() end },
        { type = "toggle", label = L["Show clock"],
          get = function() return d.showClock ~= false end,
          set = function(_, v) d.showClock = v; mm.applyAll() end },
        { type = "toggle", label = L["Show date"],
          tooltip = L["Shows the date next to the clock. Click it to open the calendar."],
          get = function() return d.showDate ~= false end,
          set = function(_, v) d.showDate = v; mm.applyAll() end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Buttons"] },
        { type = "toggle", label = L["Zoom buttons (+/-)"],
          tooltip = L["Shows a flat + and - on the right edge of the map. The mouse wheel always zooms too."],
          get = function() return d.zoomButtons ~= false end,
          set = function(_, v) d.zoomButtons = v and true or false; mm.applyAll() end },
        { type = "toggle", label = L["Show day/night button"],
          get = function() return d.showDayNight and true or false end,
          set = function(_, v) d.showDayNight = v and true or false; mm.applyAll() end },
        { type = "toggle", label = L["Restyle addon buttons"],
          tooltip = L["Removes the gold borders from other addons' minimap buttons and gives them a clean round look. Turning this off needs a /reload."],
          get = function() return d.skinButtons ~= false end,
          set = function(_, v) d.skinButtons = v; mm.applyAll() end },
        { type = "toggle", label = L["Addon buttons only on mouseover"],
          tooltip = L["Hides other addons' minimap buttons until the mouse is over the minimap."],
          get = function() return d.buttonsOnHover and true or false end,
          set = function(_, v) d.buttonsOnHover = v and true or false; mm.hovered = false; mm.applyButtonVisibility() end },
        { type = "toggle", label = L["Ping in chat"],
          tooltip = L["Prints who pinged the minimap."],
          get = function() return d.showPingChat and true or false end,
          set = function(_, v) d.showPingChat = v and true or false end },

        { type = "spacer", height = 6 },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Unlock / Position"], width = 200,
              onClick = function() setUnlocked(not d.unlocked) end },
            { type = "button", label = L["Reset position"], width = 200,
              onClick = function()
                  d.x, d.y, d.moved = 0, 0, false
                  if mm.base then
                      mm.base:ClearAllPoints()
                      mm.base:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
                      mm.syncCornerOffsets()
                  end
              end },
        } },
    }
end
