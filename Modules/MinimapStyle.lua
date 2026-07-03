-- =========================================================
-- VuloClassicUI / Modules / MinimapStyle — modern minimap
-- Rebuilds the minimap into the clean modern look: a round map with a thin
-- dark ring + accent line + soft shadow (our own generated ring textures —
-- rotation-safe, they are radially symmetric), a slim zone/clock panel,
-- tracking + mail moved onto the map edge, mouse-wheel zoom, and optional
-- skinning/hover-hiding of other addons' minimap buttons.
--
-- Everything is guarded per client (TBC Anniversary 20505 / Era 11508 ship
-- different tracking/battlefield frames). The minimap and its children are
-- NOT protected frames — reparenting/moving them from insecure code is the
-- long-established approach every minimap addon uses.
--
-- All state lives in the single `mm` table (Lua 5.1 locals discipline).
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("minimapstyle", {
    name        = "Minimap",
    group       = "UI Reskin",
    description = "A modern minimap: round with a clean dark ring and accent line, zone text and clock in a slim panel, mouse-wheel zoom, movable and scalable. Optionally hides other addons' buttons until mouseover.",
    defaults = {
        enabled       = true,
        scale         = 1.15,
        x             = 0,        -- CENTER offsets once the user has moved it
        y             = 0,
        moved         = false,    -- false = default top-right corner anchor
        zonePanel     = "top",    -- "top" | "bottom" | "hidden"
        showClock     = true,
        accentRing    = true,     -- thin colored line around the dark ring
        shape         = "round",  -- "round" | "square"
        hideZoom      = true,     -- mouse wheel zooms instead
        showDayNight  = false,    -- the classic sun/moon time button
        skinButtons   = true,     -- restyle other addons' minimap buttons
        buttonsOnHover = false,   -- only show addon buttons while hovering
        showPingChat  = false,    -- print who pinged
        unlocked      = false,
    },
})

local MEDIA = "Interface\\AddOns\\VuloClassicUI\\Media\\Minimap\\"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MAP_SIZE = 140
-- ring texture: map edge sits at r=213 of 256 -> texture must be drawn at
-- mapSize * 256/213 so the ring hugs the map border exactly
local RING_SCALE = 256 / 213

local mm = {}   -- frames, collected buttons, original-state snapshots

local function db() return mod.db end

-- While the base sits on the corner-default anchor, db.x/db.y must still hold
-- the REAL center offsets of that spot (frame-local units, same formula as
-- Core/Mover.lua). Otherwise the first arrow-key nudge / panel edit in edit
-- mode applies from 0,0 and teleports the map to the screen center.
function mm.syncCornerOffsets()
    if db().moved or not mm.base then return end
    local x, y = ns:GetCenterOffsets(mm.base)   -- canonical scale-aware capture
    if x and y then
        db().x, db().y = x, y
    end
end

-- =========================================================
-- Base frame + mover
-- =========================================================
function mm.ensureBase()
    if mm.base then return mm.base end
    local base = CreateFrame("Frame", "VCUI_MinimapFrame", UIParent)
    base:SetSize(MAP_SIZE + 12, MAP_SIZE + 12 + 22)
    if db().moved then
        base:SetPoint("CENTER", UIParent, "CENTER", db().x or 0, db().y or 0)
    else
        -- resolution-independent default: the classic top-right corner
        base:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
    end
    base:SetFrameStrata("LOW")
    mm.base = base

    -- zone/clock panel: a modern dark pill (rounded ends, baked light rim)
    mm.panel = CreateFrame("Frame", "VCUI_MinimapPanel", base)
    mm.panel:SetSize(MAP_SIZE, 18)
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
            -- An EXPLICIT reset (flagged by the reset buttons — a drag can
            -- legitimately snap to 0,0 at the screen centre!) means "back to
            -- default", which for the minimap is the top-right corner, not
            -- dead center (onMove runs after applyPos's SetPoint, so this
            -- override wins).
            if x == 0 and y == 0 and ns._inMoverReset then
                db().moved = false
                mm.base:ClearAllPoints()
                mm.base:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
                mm.syncCornerOffsets()   -- keep db in step for arrow keys / panel
            else
                db().moved = true
            end
            ns:Print(string.format(L["Minimap: x=%.0f, y=%.0f"], x, y))
        end,
    })
    return base
end

-- =========================================================
-- Map adoption + rings
-- =========================================================
function mm.adoptMinimap()
    if mm.adopted then return end
    mm.adopted = true
    -- snapshot for best-effort restore on disable — FIRST adoption only, or a
    -- disable/re-enable cycle would snapshot our own base as the "original"
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

    -- decoration is created ONCE; a re-enable only re-adopts the map (frames
    -- and textures can't be destroyed, recreating them would leak a set per
    -- disable/enable cycle)
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
    -- near-black seam ring at the map edge (baked, flat — deliberately no
    -- bright bevel edges: they read as a second gray ring)
    mm.ring = ringTex("ring_main.tga", 6)
    -- THE ring: the accent band
    mm.accent = ringTex("ring_accent.tga", 7)
    local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
    mm.accent:SetVertexColor(ac.r, ac.g, ac.b, 1)

    -- square variant: 1px frame + soft shadow, no rings
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
    -- addon-button libraries read this to place buttons along the edge
    function GetMinimapShape()
        if mod.active and db().shape == "square" then return "SQUARE" end
        return "ROUND"
    end
end

-- =========================================================
-- Default clutter off. Split in two: the Hide calls are REPEATABLE (a
-- disable/re-enable cycle must re-hide what OnDisable restored), the
-- Show-hooks are one-shot (hooksecurefunc can't be removed).
-- =========================================================
function mm.hideDefaultArt()
    local function gone(f)
        if f and f.Hide then f:Hide() end
    end
    gone(_G.MinimapBorder)
    gone(_G.MinimapBorderTop)
    gone(_G.MinimapToggleButton)
    gone(_G.MiniMapWorldMapButton)
    gone(_G.MinimapNorthTag)
    gone(_G.MinimapCompassTexture)   -- rotate-minimap compass card; our ring is rotation-safe
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
    keepHidden(_G.MinimapCompassTexture)   -- Blizzard shows it when rotate is enabled
    if _G.GameTimeFrame then
        hooksecurefunc(_G.GameTimeFrame, "Show", function(self)
            if mod.active and not db().showDayNight then self:Hide() end
        end)
    end
end

function mm.applyToggles()
    local d = db()
    if _G.MinimapZoomIn and _G.MinimapZoomOut then
        _G.MinimapZoomIn:SetShown(not d.hideZoom)
        _G.MinimapZoomOut:SetShown(not d.hideZoom)
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

-- =========================================================
-- Zone text + clock panel
-- =========================================================
function mm.setupPanel()
    if mm.panelWired then return end
    mm.panelWired = true

    local ztb = _G.MinimapZoneTextButton
    if ztb then
        ztb:SetParent(mm.panel)
        ztb:ClearAllPoints()
        ztb:SetPoint("LEFT", mm.panel, "LEFT", 6, 0)
        ztb:SetHeight(16)
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

    -- clock (lazy Blizzard addon)
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn or _G.UIParentLoadAddOn
    if loader then pcall(loader, "Blizzard_TimeManager") end
    local clock = _G.TimeManagerClockButton
    if clock then
        local regions = { clock:GetRegions() }
        if regions[1] and regions[1].Hide then regions[1]:Hide() end   -- the swirly border art
        clock:SetParent(mm.panel)
        clock:ClearAllPoints()
        clock:SetPoint("RIGHT", mm.panel, "RIGHT", -4, 0)
        clock:SetSize(38, 16)
        local ticker = _G.TimeManagerClockTicker
        if ticker and ns.UI and ns.UI.FONT_PATH then
            ticker:SetFont(ns.UI.FONT_PATH, 11, "")
            ticker:SetTextColor(0.95, 0.95, 1)
        end
    end
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
    if clock then clock:SetShown(showClock) end
    if ztb then
        ztb:Show()
        ztb:ClearAllPoints()
        ztb:SetPoint("LEFT", mm.panel, "LEFT", 6, 0)
        ztb:SetPoint("RIGHT", mm.panel, "RIGHT", showClock and -44 or -6, 0)
    end
end

-- =========================================================
-- Tracking + mail + battlefield onto the map edge
-- =========================================================
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

    -- tracking: TBC ships MiniMapTracking (+Button), Era ships MiniMapTrackingFrame
    local tracking = _G.MiniMapTracking or _G.MiniMapTrackingFrame
    if tracking then
        tracking:SetParent(Minimap)
        tracking:ClearAllPoints()
        tracking:SetPoint("CENTER", Minimap, "TOPLEFT", 20, -20)
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
        -- thin dark ring behind the tracking icon
        local ring = tracking:CreateTexture(nil, "BACKGROUND")
        ring:SetTexture(MEDIA .. "ring_main.tga")
        ring:SetVertexColor(0.07, 0.07, 0.09, 1)
        ring:SetSize(26 * RING_SCALE * 0.85, 26 * RING_SCALE * 0.85)
        ring:SetPoint("CENTER", tracking, "CENTER", 0, 0)
        if ring.SetSnapToPixelGrid then ring:SetSnapToPixelGrid(false); ring:SetTexelSnappingBias(0) end
    end

    -- mail: onto the top-right edge, plain envelope without the gold border
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

    -- battleground queue eye
    local bf = _G.MiniMapBattlefieldFrame or _G.MiniMapLFGFrame
    if bf then
        bf:SetParent(Minimap)
        bf:ClearAllPoints()
        bf:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 20, 20)
    end
    -- Era group-finder eye lives in a load-on-demand Blizzard addon and is
    -- anchored to the stranded old backdrop — re-home it whenever it exists
    -- (called again from the ADDON_LOADED watcher once its addon loads)
    mm.placeLFGEye()

    -- instance difficulty flag (TBC)
    local diff = _G.MiniMapInstanceDifficulty
    if diff then
        diff:SetParent(Minimap)
        diff:ClearAllPoints()
        diff:SetPoint("CENTER", Minimap, "BOTTOMRIGHT", -16, 16)
        diff:SetScale(0.8)
    end
end

-- =========================================================
-- Shift+drag ON THE MAP moves it — the foolproof path that works without any
-- edit mode (Blizzard's own Edit Mode only manages its now-empty cluster).
-- =========================================================
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
        local x, y = ns:GetCenterOffsets(mm.base)   -- canonical scale-aware capture
        if x and y then
            db().x, db().y = x, y
            db().moved = true
            mm.base:ClearAllPoints()
            mm.base:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end
    end)
end

-- =========================================================
-- Zoom: mouse wheel + optional +/- buttons
-- =========================================================
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
    end)
    -- re-home the +/- buttons onto the map edge: on Era they are children of
    -- the old backdrop, which stays glued to the untouched cluster position
    local zin, zout = _G.MinimapZoomIn, _G.MinimapZoomOut
    if zin and zout then
        zin:SetParent(Minimap)
        zin:ClearAllPoints()
        zin:SetPoint("CENTER", Minimap, "BOTTOMRIGHT", -6, 30)
        zin:SetScale(0.7)
        zout:SetParent(Minimap)
        zout:ClearAllPoints()
        zout:SetPoint("CENTER", Minimap, "BOTTOMRIGHT", -22, 8)
        zout:SetScale(0.7)
    end
end

-- =========================================================
-- Other addons' minimap buttons: collect, skin, hover-hide.
-- Collection is name/child based (no library dependency): every unnamed or
-- foreign Button child of the Minimap that carries the classic tracking-
-- border texture layout is treated as an addon button.
-- =========================================================
local BLIZZ_CHILDREN = {
    MinimapZoomIn = true, MinimapZoomOut = true, MiniMapWorldMapButton = true,
    MinimapToggleButton = true, MiniMapTracking = true, MiniMapTrackingFrame = true,
    MiniMapMailFrame = true, MiniMapBattlefieldFrame = true, MiniMapLFGFrame = true,
    LFGMinimapFrame = true,   -- Era group-finder eye — never ring/mask Blizzard's eye
    MiniMapInstanceDifficulty = true, GameTimeFrame = true, TimeManagerClockButton = true,
    MinimapBackdrop = true, MiniMapVoiceChatFrame = true, MinimapZoneTextButton = true,
}

function mm.skinAddonButton(btn)
    if btn._vcuiMapSkin then return end
    btn._vcuiMapSkin = true
    for _, r in ipairs({ btn:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then
            local tex = r:GetTexture()
            if tex == 136430 then       -- MiniMap-TrackingBorder (gold ring)
                r:SetTexture(nil); r:SetAlpha(0)
            elseif tex == 136467 then   -- UI-Minimap-Background
                r:SetTexture(nil); r:SetAlpha(0)
            end
        end
    end
    local icon = btn.icon
    if not icon then
        -- common pattern: the biggest ARTWORK texture is the icon
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
            if w > 20 and w < 44 then   -- classic minimap-button footprint
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

-- Most addon buttons register through the shared LibDBIcon library, which
-- fires a callback for every button it CREATES — catching late registrations
-- the moment they appear (the child scan stays as fallback for the rest).
-- Purely opportunistic: no hard dependency, retried once the lib exists.
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
        if not (mod.active and db().buttonsOnHover) then return end
        acc = acc + elapsed
        if acc < 0.1 then return end
        acc = 0
        local over = self:IsMouseOver(10, -10, -10, 10)
        if over ~= mm.hovered then
            mm.hovered = over
            mm.applyButtonVisibility()
        end
    end)
end

-- =========================================================
-- Ping reporting
-- =========================================================
function mm.onPing(_, unit)
    if not db().showPingChat then return end
    if not unit then return end
    local name = UnitName(unit)
    if name then
        ns:Print(string.format(L["Minimap ping: %s"], name))
    end
end

-- =========================================================
-- Apply / lifecycle
-- =========================================================
function mm.applyAll()
    if not mm.base then return end
    mm.base:SetScale(db().scale or 1)
    mm.syncCornerOffsets()   -- AFTER SetScale: offsets are frame-local units
    mm.applyShape()
    mm.applyPanel()
    mm.applyToggles()
    mm.collectAddonButtons()
    mm.applyButtonVisibility()
end

function mm.onEnteringWorld()
    if not mod.active then return end
    -- GetCenter can be nil (and the UI scale not final) at our early
    -- ADDON_LOADED enable — re-sync here, when layout + scale are settled,
    -- or the first arrow-key nudge still teleports the corner-anchored map
    mm.syncCornerOffsets()
    mm.hookButtonLib()   -- the shared icon lib may have loaded with other addons by now
    mm.collectAddonButtons()
    mm.applyButtonVisibility()
end

function mod:OnEnable()
    mod.active = true
    -- one-time migration: the default scale grew 1.0 -> 1.15 on user request;
    -- bump profiles that still sit on the untouched old default
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
    ns:RegisterEvent("ADDON_LOADED", mm.onAddonLoaded)   -- late-loading group-finder eye
    -- addon buttons often appear a moment after login
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
    -- best-effort restore: give the map back to its original owner; borders,
    -- fonts and moved children come back fully with a /reload
    if mm.adopted then
        mm.adopted = false
        if mm.ring then mm.ring:Hide() end
        if mm.accent then mm.accent:Hide() end
        if mm.shadow then mm.shadow:Hide() end
        if mm.squareFrame then mm.squareFrame:Hide() end
        if mm.panel then mm.panel:Hide() end
        Minimap:SetMaskTexture(ROUND_MASK)   -- never leave a square map inside the round default border
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
        -- addon buttons the hover option may have faded out must come back
        mm.hovered = true
        for _, b in ipairs(mm.addonButtons or {}) do b:SetAlpha(1) end
        if mm.base and mm.base.mover then mm.base.mover:Hide() end
        ns:Print(L["Minimap module disabled — /reload restores the default layout completely."])
    end
end

-- =========================================================
-- Options
-- =========================================================
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

        { type = "spacer", height = 6 },
        { type = "header", text = L["Buttons"] },
        { type = "toggle", label = L["Hide zoom buttons"],
          tooltip = L["The mouse wheel always zooms; the +/- buttons are just clutter."],
          get = function() return d.hideZoom ~= false end,
          set = function(_, v) d.hideZoom = v; mm.applyAll() end },
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
