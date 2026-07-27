-- Dark button skin plus an opt-in re-tint of Blizzard's default UI artwork.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("darkskin", {
    name        = "Dark Skin",
    group       = "UI Reskin",
    description = "The dark look of the UI in one place: a built-in dark skin for action buttons and WeakAuras icons, plus an optional Dark Mode that darkens Blizzard's default frames, minimap and bars.",
    defaults = {
        enabled       = true,
        style         = "shadow",  -- shadow | rounded | square | accent | circle | minimal | minimaldark
        waStyle       = "shadow",
        skinPetStance = true,
        skinBars      = true,
        barIconSize   = 88,        -- shadow style: icon fills this % of the button (rest = rim)
        skinWeakAuras = true,
        hideWABorder  = true,
        darkMode        = false,
        dmDesaturate    = true,
        dmColor         = { r = 0.40, g = 0.40, b = 0.40 },
        dmUnitframes    = true,
        dmMinimap       = true,
        dmActionbars    = true,
        dmActionButtons = false,
        dmBags          = false,
    },
})

local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton", "BonusActionButton",
    "VuloActionButton", "VuloAB_bottomleftB", "VuloAB_bottomrightB",
    "VuloAB_rightB", "VuloAB_leftB", "VuloAB_extraB", "VuloAB_stanceB",
}
local EXTRA_PREFIXES = { "PetActionButton", "StanceButton" }

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

-- Bundled masks under Media\Masks\; file paths load more reliably than fileIDs in Classic.
local MASK_ROUNDED = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\csquare_mask.tga"
local MASK_CIRCLE  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\circle_mask.tga"
local MASK_SQUARE  = "Interface\\Buttons\\WHITE8X8"
local TEX_BACKDROP = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\Backdrop.tga"
local TEX_BORDER   = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\Normal.tga"

-- The rim comes from insetting the icon's MASK by a fraction of icon size, so it
-- scales with the icon; RIM_OUTSET is a fixed bleed for the soft shadow.
local RIM_OUTSET  = 3

local function attachShadow(frame, store, outset)
    if not frame then return end
    store = store or frame
    outset = outset or RIM_OUTSET

    if not store._vcuiBack then
        local back = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        back:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -outset,  outset)
        back:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  outset, -outset)
        back:SetTexture(TEX_BACKDROP)
        back:SetVertexColor(0.03, 0.03, 0.04, 1)
        store._vcuiBack = back

        local ring = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        ring:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -outset,  outset)
        ring:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  outset, -outset)
        ring:SetTexture(TEX_BORDER)
        ring:SetVertexColor(0, 0, 0, 1)
        store._vcuiRing = ring
    end
end

local STYLES = {
    shadow   = { border = nil,      bg = true,  mask = nil,          shadow = true  },
    rounded  = { border = nil,      bg = true,  mask = MASK_ROUNDED, shadow = false },
    square   = { border = "black",  bg = true,  mask = nil,          shadow = false },
    accent   = { border = "accent", bg = true,  mask = nil,          shadow = false },
    circle   = { border = nil,      bg = true,  mask = MASK_CIRCLE,  shadow = false },
    minimal  = { border = nil,      bg = false, mask = nil,          shadow = false },
    minimaldark = { border = nil,   bg = false, mask = nil,          shadow = false, darkenNormal = true },
}

local DARK_TINT = 0.12

-- Gates the NormalTexture re-hide hooks; flipped by setBarsSkinned().
local barsSkinned = false

local function currentStyle(forWA)
    local key = mod.db and (forWA and mod.db.waStyle or mod.db.style)
    return STYLES[key] or STYLES.shadow
end

-- Measured: painting the WeakAuras icons cost a 28 ms hitch on EVERY combat
-- edge, because the sweep walked every aura ever saved -- most of them not even
-- on screen -- and re-applied a look that had not changed.
--
-- A region now remembers what it was last painted with. This is a FINGERPRINT
-- of the settings, not a counter that someone has to remember to bump: a
-- profile switch rewrites the settings without going through any of our option
-- setters, and a counter silently missed that -- every icon kept the old
-- profile's look until /reload.
local function waSignature()
    local db = mod.db
    if not db then return "?" end
    return (db.waStyle or "shadow") .. (db.hideWABorder and "|B" or "|b")
end

local function getRegion(button, suffix, fallback)
    local name = button:GetName()
    return (name and _G[name .. suffix]) or fallback
end

local function hideNormalTexture(button)
    local nt = (button.GetNormalTexture and button:GetNormalTexture())
            or getRegion(button, "NormalTexture", button.NormalTexture)
    if nt then
        nt:SetTexture(nil)
        nt:SetAlpha(0)
    end
    local slot = getRegion(button, "SlotBackground", button.SlotBackground)
    if slot then slot:SetAlpha(0) end
end

local function applyNormalTexture(button)
    if not currentStyle().darkenNormal then
        hideNormalTexture(button)
        return
    end
    local nt = (button.GetNormalTexture and button:GetNormalTexture())
            or getRegion(button, "NormalTexture", button.NormalTexture)
    if nt then
        if button._vcuiNTOrig then nt:SetTexture(button._vcuiNTOrig) end
        nt:SetAlpha(1)
        if nt.SetDesaturated then nt:SetDesaturated(true) end
        nt:SetVertexColor(DARK_TINT, DARK_TINT, DARK_TINT, 1)
    end
    local slot = getRegion(button, "SlotBackground", button.SlotBackground)
    if slot then slot:SetAlpha(0) end
end

-- This client has no reliable global ActionButton_Update, so hook each button's setter.
local function lockNormalTexture(button)
    if button._vcuiNTHook or not button.SetNormalTexture then return end
    button._vcuiNTHook = true
    hooksecurefunc(button, "SetNormalTexture", function(self)
        if mod._enabled and barsSkinned and self._vcuiSkinned then
            applyNormalTexture(self)
        end
    end)
end

local function ensureMask(button)
    if not button._vcuiMask and button.CreateMaskTexture then
        button._vcuiMask = button:CreateMaskTexture()
    end
    return button._vcuiMask
end

-- `pct` insets the mask by that fraction of icon size, revealing the backdrop as a rim.
local function setMasked(button, icon, on, maskTex, pct)
    if on then
        local m = ensureMask(button)
        if not m then return end
        m:ClearAllPoints()
        pct = pct or 0
        if pct > 0 then
            local w = icon:GetWidth() or 0
            if w < 1 then w = (button.GetWidth and button:GetWidth()) or 32 end
            local inset = math.max(1, w * pct)
            m:SetPoint("TOPLEFT",     icon, "TOPLEFT",      inset, -inset)
            m:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset,  inset)
        else
            m:SetAllPoints(icon)
        end
        m:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:Show()
        if not button._vcuiMaskOn then
            if icon.AddMaskTexture then pcall(icon.AddMaskTexture, icon, m) end
            button._vcuiMaskOn = true
        end
    elseif button._vcuiMaskOn and button._vcuiMask then
        local m = button._vcuiMask
        if icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, m) end
        m:Hide()
        button._vcuiMaskOn = false
    end
end

local function applyStyle(button)
    local st   = currentStyle()
    local icon = getRegion(button, "Icon", button.icon or button.Icon)

    if icon and icon.SetTexCoord then icon:SetTexCoord(unpack(ICON_CROP)) end

    if button._vcuiBg then
        button._vcuiBg:SetShown((st.bg and not st.shadow) and true or false)
    end

    local showShadow = st.shadow and true or false
    if button._vcuiBack then button._vcuiBack:SetShown(showShadow) end
    if button._vcuiRing then button._vcuiRing:SetShown(showShadow) end

    if icon then
        local maskTex = st.mask or (st.shadow and MASK_SQUARE) or nil
        local size = tonumber(mod.db.barIconSize) or 90
        local pct  = st.shadow and ((100 - size) / 200) or 0
        setMasked(button, icon, maskTex ~= nil, maskTex, pct)
    end

    if button._vcuiBorder then
        if st.border then
            button._vcuiBorder:Show()
            if st.border == "accent" then
                local a = ns.COLORS.accent
                button._vcuiBorder:SetBackdropBorderColor(a.r, a.g, a.b, 1)
            else
                button._vcuiBorder:SetBackdropBorderColor(0, 0, 0, 1)
            end
        else
            button._vcuiBorder:Hide()
        end
    end

    applyNormalTexture(button)
end

local function skinButton(button)
    if not button then return end
    if not button._vcuiSkinned then
        button._vcuiSkinned = true

        local nt0 = button.GetNormalTexture and button:GetNormalTexture()
        if nt0 and nt0.GetTexture then button._vcuiNTOrig = nt0:GetTexture() end

        attachShadow(button, button)
        lockNormalTexture(button)

        local bg = button:CreateTexture(nil, "BACKGROUND", nil, -2)
        bg:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        bg:SetColorTexture(0.04, 0.04, 0.05, 0.9)
        button._vcuiBg = bg

        local border = CreateFrame("Frame", nil, button,
            BackdropTemplateMixin and "BackdropTemplate")
        border:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
        if border.SetBackdrop then
            border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        end
        local lvl = button:GetFrameLevel() or 1
        border:SetFrameLevel(math.max(0, lvl - 1))
        button._vcuiBorder = border
    end

    applyStyle(button)
end

local function forEachButton(fn)
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b then fn(b) end
        end
    end
    if mod.db.skinPetStance then
        for _, prefix in ipairs(EXTRA_PREFIXES) do
            for i = 1, 12 do
                local b = _G[prefix .. i]
                if b then fn(b) end
            end
        end
    end
end

local function skinAll()
    if not mod._enabled or not mod.db or not mod.db.skinBars then return end
    forEachButton(skinButton)
end

local function refreshAll()
    if not mod._enabled or not mod.db then return end
    forEachButton(function(b)
        if b._vcuiSkinned then
            applyStyle(b)
        end
    end)
end

-- Touches only textures/regions, never secure attributes, so it is combat-safe.
local function unstyleButton(button)
    if not button or not button._vcuiSkinned then return end
    if button._vcuiBg     then button._vcuiBg:Hide()     end
    if button._vcuiBack   then button._vcuiBack:Hide()   end
    if button._vcuiRing   then button._vcuiRing:Hide()   end
    if button._vcuiBorder then button._vcuiBorder:Hide() end

    local icon = getRegion(button, "Icon", button.icon or button.Icon)
    if icon then
        setMasked(button, icon, false)
        if icon.SetTexCoord then icon:SetTexCoord(0, 1, 0, 1) end
    end

    local nt = (button.GetNormalTexture and button:GetNormalTexture())
            or getRegion(button, "NormalTexture", button.NormalTexture)
    if nt then
        if button._vcuiNTOrig then nt:SetTexture(button._vcuiNTOrig) end
        nt:SetAlpha(1)
        if nt.SetDesaturated then nt:SetDesaturated(false) end
        nt:SetVertexColor(1, 1, 1)
    end
    local slot = getRegion(button, "SlotBackground", button.SlotBackground)
    if slot then slot:SetAlpha(1) end
end

local function setBarsSkinned(on)
    barsSkinned = on and true or false
    if on then
        if mod._enabled then forEachButton(skinButton) end
    else
        forEachButton(unstyleButton)
    end
end

local function insetCooldown(region, icon, pct)
    local cd = region.cooldown
    if not (cd and cd.ClearAllPoints) then return end
    cd:ClearAllPoints()
    if pct and pct > 0 then
        local w = (icon and icon:GetWidth()) or 0
        if w < 1 then w = (region.GetWidth and region:GetWidth()) or 32 end
        local inset = math.max(1, w * pct)
        cd:SetPoint("TOPLEFT",     icon, "TOPLEFT",      inset, -inset)
        cd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset,  inset)
    else
        cd:SetAllPoints(icon)
    end
end

local function styleWAIcon(region)
    if not region or region.regionType ~= "icon" then return end
    local icon = region.icon
    if not icon then return end
    local w = icon:GetWidth() or 0
    if w < 1 then w = (region.GetWidth and region:GetWidth()) or 32 end

    -- Hiding WeakAuras' own border must happen on EVERY pass, never memoised:
    -- WeakAuras releases and re-creates all of a region's sub-parts on any edit,
    -- and hands out recycled region tables when an aura gains a stack -- both
    -- give us a fresh, VISIBLE border on a table that still carries our stamp.
    -- It is a handful of table entries, so it is cheap enough to always do.
    if mod.db and mod.db.hideWABorder and region.subRegions then
        for _, sub in ipairs(region.subRegions) do
            if type(sub) == "table" and sub.SetBorderColor and sub.Hide then
                sub:Hide()
            end
        end
    end

    -- The rest is geometry and masks: idempotent for the same settings and the
    -- same size, so it is the part worth skipping. Width is in the test because
    -- every offset is derived from it -- resize an aura and the rim must follow.
    local sig = waSignature()
    if region._vcuiWASig == sig and region._vcuiWAWidth == w then return end
    region._vcuiWASig, region._vcuiWAWidth = sig, w

    attachShadow(region, region, 1)
    local st = currentStyle(true)
    local showShadow = st.shadow and true or false

    local WA_SHRINK = 0.08
    local WA_RIM    = 0.12
    local out = w * WA_RIM

    for _, t in ipairs({ region._vcuiBack, region._vcuiRing }) do
        if t then
            t:SetShown(showShadow)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT",     region, "TOPLEFT",     -out,  out)
            t:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT",  out, -out)
        end
    end
    if region._vcuiBack then region._vcuiBack:SetVertexColor(0.02, 0.02, 0.03, 1) end

    local maskTex = st.mask or (st.shadow and MASK_SQUARE) or nil
    local pct     = st.shadow and WA_SHRINK or 0
    setMasked(region, icon, maskTex ~= nil, maskTex, pct)

    local function fixCD(cd)
        insetCooldown(region, icon, pct)
        if cd.SetSwipeColor then pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0) end
    end
    if region.cooldown then
        fixCD(region.cooldown)
        if not region.cooldown._vcuiCDHook then
            region.cooldown._vcuiCDHook = true
            hooksecurefunc(region.cooldown, "SetCooldown", function(self)
                if mod._enabled and mod.db and mod.db.skinWeakAuras then fixCD(self) end
            end)
        end
    end

end

local function styleWAAuraBarIcon(region)
    local icon  = region and region.icon
    local frame = region and region.iconFrame
    if not (icon and frame) then return end

    local w = (icon.GetWidth and icon:GetWidth()) or 0
    if w < 1 then w = (frame.GetWidth and frame:GetWidth()) or 20 end

    -- Same reasoning as the icon variant: settings fingerprint plus size. The
    -- aurabar painter never touched WeakAuras' own border, so there is nothing
    -- to pull out in front of the check here.
    local sig = waSignature()
    if region._vcuiWASig == sig and region._vcuiWAWidth == w then return end
    region._vcuiWASig, region._vcuiWAWidth = sig, w

    attachShadow(frame, region, 1)
    local st = currentStyle(true)
    local showShadow = st.shadow and true or false

    local out = w * 0.12

    for _, t in ipairs({ region._vcuiBack, region._vcuiRing }) do
        if t then
            t:SetShown(showShadow)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -out,  out)
            t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  out, -out)
        end
    end
    if region._vcuiBack then region._vcuiBack:SetVertexColor(0.02, 0.02, 0.03, 1) end

    local maskTex = st.mask or (st.shadow and MASK_SQUARE) or nil
    local pct     = st.shadow and 0.08 or 0
    setMasked(frame, icon, maskTex ~= nil, maskTex, pct)
end

local function skinWARegion(region)
    if type(region) ~= "table" then return end
    local rt = region.regionType
    if rt == "icon" then
        styleWAIcon(region)
    elseif rt == "aurabar" then
        styleWAAuraBarIcon(region)
    end
end

local function skinWAById(id)
    if not (WeakAuras and WeakAuras.GetRegion) then return end
    local ok, region = pcall(WeakAuras.GetRegion, id)
    if ok then skinWARegion(region) end
end

local function skinFrameTree(frame, depth)
    if not frame or depth > 10 then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    local rt = frame.regionType
    if rt == "icon" or rt == "aurabar" then pcall(skinWARegion, frame) end
    if not frame.GetChildren then return end
    local packed = { pcall(frame.GetChildren, frame) }
    if packed[1] then
        for i = 2, #packed do skinFrameTree(packed[i], depth + 1) end
    end
end

local function skinAllWAIcons()
    if not mod._enabled or not mod.db or not mod.db.skinWeakAuras then return end
    if WeakAuras and WeakAuras.GetRegion then
        local saved = _G.WeakAurasSaved
        if saved and saved.displays then
            for id, data in pairs(saved.displays) do
                if type(data) == "table"
                   and (data.regionType == "icon" or data.regionType == "aurabar") then
                    skinWAById(id)
                end
            end
        end
    end
    skinFrameTree(UIParent, 0)
end

local function onNamePlateAdded(_, unit)
    if not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
    if not (unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            if plate then skinFrameTree(plate, 0) end
        end)
    end
end
local function onTargetChangedWA()
    if not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function() skinFrameTree(_G.TargetFrame, 0) end)
    end
end

local _waSoonPending = false
local function skinWAFrameOnly()
    if not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
    skinFrameTree(_G.WeakAurasFrame, 0)
end
local function skinWASoon()
    if _waSoonPending or not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
    if not (C_Timer and C_Timer.After) then return end
    _waSoonPending = true
    C_Timer.After(0.25, function()
        _waSoonPending = false
        skinWAFrameOnly()
    end)
end

local waHooked = false
local function hookWeakAuras()
    if waHooked or not (WeakAuras and WeakAuras.Add) then return end
    waHooked = true
    hooksecurefunc(WeakAuras, "Add", function(data)
        if not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
        if type(data) ~= "table" or data.regionType ~= "icon" or not data.id then return end
        local id = data.id
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function() skinWAById(id) end)
        else
            skinWAById(id)
        end
    end)
end

local function skinEverything()
    skinAll()
    skinAllWAIcons()
end

local _skinAllPending, _skinEvtPending
local function skinAllSoon()
    if not (C_Timer and C_Timer.After) then return skinAll() end
    if _skinAllPending then return end
    _skinAllPending = true
    C_Timer.After(0.1, function() _skinAllPending = false; if mod._enabled then skinAll() end end)
end

-- Entry point for other modules to re-skin freshly created action buttons.
ns.ReskinActionButtons = skinAllSoon
local function skinEverythingSoon()
    if not (C_Timer and C_Timer.After) then return skinEverything() end
    if _skinEvtPending then return end
    _skinEvtPending = true
    C_Timer.After(0.2, function() _skinEvtPending = false; if mod._enabled then skinEverything() end end)
end

-- Cannot gate on mod._enabled: the core sets it true only AFTER OnEnable returns.
local active = false

local function dmColorRGB()
    local c = mod.db and mod.db.dmColor
    if not c then return 0.4, 0.4, 0.4 end
    return c.r or 0.4, c.g or 0.4, c.b or 0.4
end

local function paint(tex, on)
    if not tex or not tex.SetVertexColor then return end
    if on then
        if tex.SetDesaturated then pcall(tex.SetDesaturated, tex, mod.db.dmDesaturate and true or false) end
        tex:SetVertexColor(dmColorRGB())
    else
        if tex.SetDesaturated then pcall(tex.SetDesaturated, tex, false) end
        tex:SetVertexColor(1, 1, 1)
    end
end

local function paintGlobals(names, on)
    for _, n in ipairs(names) do paint(_G[n], on) end
end

local function paintNormal(btnName, on)
    local b = _G[btnName]
    if not b or not b.GetNormalTexture then return end
    paint(b:GetNormalTexture(), on)
end

local UNIT_BORDERS = {
    "PlayerFrameTexture",
    "TargetFrameTextureFrameTexture",
    "FocusFrameTextureFrameTexture",
    "PetFrameTexture",
    "PartyMemberFrame1Texture", "PartyMemberFrame2Texture",
    "PartyMemberFrame3Texture", "PartyMemberFrame4Texture",
    "TargetFrameToTTextureFrameTexture",
    "FocusFrameToTTextureFrameTexture",
}
local MINIMAP_REGIONS = {
    "MinimapBorder", "MinimapBorderTop", "MinimapCompassTexture", "MinimapNorthTag",
    "MiniMapTrackingButtonBorder", "MiniMapTrackingBorder",
    "MiniMapMailBorder", "MiniMapBattlefieldBorder",
    "MiniMapWorldBorder", "MiniMapLFGBorder",
}
local MINIMAP_BUTTONS = { "MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton" }
local ACTIONBAR_ART = {
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
    "MainMenuBarTexture0", "MainMenuBarTexture1",
    "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuBarTextureExtender",
}
local ACTION_BUTTON_BARS = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton",
}
local BAG_BUTTONS = {
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "KeyRingButton",
}

-- The button skin hides the same NormalTexture, so the tint must stand down.
local function buttonSkinOwnsBars()
    return (mod.db.skinBars and barsSkinned) and true or false
end

local function applyUnitframes(on) paintGlobals(UNIT_BORDERS, on) end
local function applyMinimap(on)
    paintGlobals(MINIMAP_REGIONS, on)
    for _, n in ipairs(MINIMAP_BUTTONS) do paintNormal(n, on) end
end
local function applyActionbars(on) paintGlobals(ACTIONBAR_ART, on) end
local function applyActionButtons(on)
    if on and buttonSkinOwnsBars() then return end
    for _, bar in ipairs(ACTION_BUTTON_BARS) do
        for i = 1, 12 do paintNormal(bar .. i, on) end
    end
end
local function applyBags(on)
    for _, n in ipairs(BAG_BUTTONS) do paintNormal(n, on) end
end

local function isDMOn(area)
    return (active and mod.db.darkMode and mod.db[area]) and true or false
end

local function applyAllDM()
    applyUnitframes(isDMOn("dmUnitframes"))
    applyMinimap(isDMOn("dmMinimap"))
    applyActionbars(isDMOn("dmActionbars"))
    applyActionButtons(isDMOn("dmActionButtons"))
    applyBags(isDMOn("dmBags"))
end

local function restoreAllDM()
    applyUnitframes(false)
    applyMinimap(false)
    applyActionbars(false)
    applyActionButtons(false)
    applyBags(false)
end

-- Blizzard resets these textures on redraw, so the tint has to be re-applied.
local dmHooked = false
local function installDMHooks()
    if dmHooked then return end
    dmHooked = true

    if _G.TargetFrame_CheckClassification then
        hooksecurefunc("TargetFrame_CheckClassification", function(self)
            if not isDMOn("dmUnitframes") then return end
            local n = self and self.GetName and self:GetName()
            if n then paint(_G[n .. "TextureFrameTexture"], true) end
        end)
    end

    if _G.ActionButton_Update then
        hooksecurefunc("ActionButton_Update", function(btn)
            if not isDMOn("dmActionButtons") or buttonSkinOwnsBars() then return end
            if btn and btn.GetNormalTexture then paint(btn:GetNormalTexture(), true) end
        end)
    end
end

local hookInstalled = false

-- Named handlers registered through the module: they used to be anonymous and
-- latched, so they stayed live for the session once the dark mode had been on
-- even once, and only the isDMOn check kept them from painting.
local PARTY_TEXTURES = { "PartyMemberFrame1Texture", "PartyMemberFrame2Texture",
                         "PartyMemberFrame3Texture", "PartyMemberFrame4Texture" }

local function onFocusChangedDM()
    if isDMOn("dmUnitframes") then paint(_G.FocusFrameTextureFrameTexture, true) end
end
local function onUnitPetDM()
    if isDMOn("dmUnitframes") then paint(_G.PetFrameTexture, true) end
end
local function onRosterUpdateDM()
    if isDMOn("dmUnitframes") then paintGlobals(PARTY_TEXTURES, true) end
end

local function wireDMEvents()
    mod:RegisterEvent("PLAYER_FOCUS_CHANGED", onFocusChangedDM)
    mod:RegisterEvent("UNIT_PET",             onUnitPetDM)
    mod:RegisterEvent("GROUP_ROSTER_UPDATE",  onRosterUpdateDM)
end

local function onWorldEnter()
    skinEverythingSoon()
    if mod.db.darkMode then applyAllDM() end
end
local function onTargetChanged()
    onTargetChangedWA()
    if isDMOn("dmUnitframes") then paint(_G.TargetFrameTextureFrameTexture, true) end
end

function mod:OnEnable()
    if not mod.db then return end
    active = true
    barsSkinned = mod.db.skinBars and true or false

    -- Deferred so all frames exist; the late pass catches slow-loading aura icons.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, skinEverything)
        C_Timer.After(2.0, skinEverything)
        C_Timer.After(5.0, skinAllWAIcons)
    else
        skinEverything()
    end

    hookWeakAuras()
    installDMHooks()
    wireDMEvents()

    -- Blizzard rebuilds NormalTexture on button updates, so re-hide it after.
    if not hookInstalled then
        hookInstalled = true
        if _G.ActionButton_Update then
            hooksecurefunc("ActionButton_Update", function(button)
                if mod._enabled and barsSkinned and button and button._vcuiSkinned then
                    applyNormalTexture(button)
                end
            end)
        end
    end

    -- Through the module, not ns: directly -- that is what puts the time on
    -- "darkskin" in the measurement instead of on a bare event name. These were
    -- the entries that showed up anonymous, and the 28 ms hitch hid in them.
    -- It also hands the teardown to the framework.
    mod:RegisterEvent("PLAYER_ENTERING_WORLD",     onWorldEnter)
    mod:RegisterEvent("UPDATE_SHAPESHIFT_FORMS",   skinAllSoon)
    mod:RegisterEvent("PET_BAR_UPDATE",            skinAllSoon)
    mod:RegisterEvent("PLAYER_REGEN_DISABLED",     skinAllWAIcons)
    mod:RegisterEvent("PLAYER_REGEN_ENABLED",      skinAllWAIcons)
    mod:RegisterEvent("PLAYER_TARGET_CHANGED",     onTargetChanged)
    mod:RegisterEvent("NAME_PLATE_UNIT_ADDED",     onNamePlateAdded)
    -- registration follows the option: UNIT_AURA fires for every unit
    -- everywhere, and with the skin off the handler would only ever bail
    if mod.db.skinWeakAuras then
        mod:RegisterEvent("UNIT_AURA", skinWASoon)
    end

    applyAllDM()
end

function mod:OnDisable()
    active = false
    -- The events registered through the module are taken back out by the
    -- framework right after this returns; the three dark-mode ones go the same
    -- way. Nothing left to mirror by hand here.
    restoreAllDM()
    -- Button skins and hooks stay until /reload; tearing them down could touch
    -- buttons in combat. Remaining hooks are gated by `active` / mod._enabled.
end

function mod:GetOptions()
    local STYLE_VALUES = {
        { value = "shadow",  text = L["Shadow (dark rounded rim)"] },
        { value = "rounded", text = L["Rounded icon (masked corners)"] },
        { value = "square",  text = L["Square (black edge)"] },
        { value = "accent",  text = L["Square (accent edge)"] },
        { value = "circle",  text = L["Circle"] },
        { value = "minimal", text = L["Minimal (icon only)"] },
        { value = "minimaldark", text = L["Minimal Dark (darkened Blizzard border)"] },
    }

    local function dmApply() applyAllDM() end
    local function dmAreaToggle(key, label, tooltip)
        return {
            type = "toggle", label = label, tooltip = tooltip,
            get = function() return mod.db[key] end,
            set = function(_, v) mod.db[key] = v; dmApply() end,
        }
    end

    return {
        { type = "header", text = L["Dark Skin"] },
        { type = "desc", text = L["|cffaaaaaaThe dark look of the UI in one place: a built-in skin for action buttons and WeakAuras icons, plus an optional Dark Mode that re-tints Blizzard's default frames.|r"] },

        { type = "header", text = L["Action Bars"] },
        { type = "toggle", label = L["Skin the action bars"],
          tooltip = L["The dark action-bar button skin."],
          get = function() return mod.db.skinBars end,
          set = function(_, v) mod.db.skinBars = v; setBarsSkinned(v) end },
        { type = "dropdown", label = L["Bar style"],
          tooltip = L["Pick how the action buttons look. Rounded/Circle use an icon mask; Minimal is just the cropped icon."],
          width = 260,
          values = STYLE_VALUES,
          get = function() return mod.db.style or "shadow" end,
          set = function(_, v) mod.db.style = v; refreshAll() end },
        { type = "slider", label = L["Bar icon size"],
          tooltip = L["How much of the button the icon fills in Shadow style. Higher = bigger icons with a thinner rim."],
          min = 76, max = 100, step = 2,
          get = function() return mod.db.barIconSize or 90 end,
          set = function(_, v) mod.db.barIconSize = v; refreshAll() end },
        { type = "toggle", label = L["Also skin pet & stance buttons"],
          get = function() return mod.db.skinPetStance end,
          set = function(_, v) mod.db.skinPetStance = v; skinAll() end },

        { type = "spacer", height = 8 },

        { type = "header", text = L["WeakAuras Icons"] },
        { type = "toggle", label = L["Skin WeakAuras icons"],
          get = function() return mod.db.skinWeakAuras end,
          set = function(_, v)
              local was = mod.db.skinWeakAuras
              mod.db.skinWeakAuras = v
              -- Through the module, like the registration in OnEnable, so the
              -- framework's teardown owns this one too. The registry refuses a
              -- duplicate, so the flip check is belt and braces.
              if mod._enabled and v and not was then
                  mod:RegisterEvent("UNIT_AURA", skinWASoon)
              elseif was and not v then
                  ns:UnregisterEvent("UNIT_AURA", skinWASoon)
              end
              if v then skinAllWAIcons() end
          end },
        { type = "dropdown", label = L["WeakAuras style"],
          tooltip = L["Style for WeakAuras icons, independent of the action bars."],
          width = 260,
          values = STYLE_VALUES,
          get = function() return mod.db.waStyle or "shadow" end,
          set = function(_, v) mod.db.waStyle = v; skinAllWAIcons() end },
        { type = "toggle", label = L["Hide WeakAuras' own border"],
          tooltip = L["Hides the light border WeakAuras draws on icons, so only our dark rim shows. /reload to fully restore it."],
          get = function() return mod.db.hideWABorder end,
          set = function(_, v) mod.db.hideWABorder = v; skinAllWAIcons() end },

        { type = "spacer", height = 8 },

        { type = "header", text = L["Dark Mode"] },
        { type = "desc", text = L["|cffaaaaaaOptional: darkens and desaturates Blizzard's default artwork — unit frames, minimap and action bars — to a neutral dark tone. Reversible: turn it off and the gold look returns.|r"] },
        { type = "toggle", label = L["Enable Dark Mode"],
          tooltip = L["Re-tints Blizzard's default frames, minimap and action-bar artwork to a dark tone. Off by default."],
          get = function() return mod.db.darkMode end,
          set = function(_, v) mod.db.darkMode = v; applyAllDM() end },
        { type = "toggle", label = L["Desaturate (greyscale)"],
          tooltip = L["Strips the colour out of the artwork before tinting, for a true greyscale look. Off keeps a hint of the original hue."],
          get = function() return mod.db.dmDesaturate end,
          set = function(_, v) mod.db.dmDesaturate = v; dmApply() end },
        { type = "color", label = L["Tint colour"], width = 160,
          get = function() return mod.db.dmColor end,
          set = function(r, g, b) mod.db.dmColor = { r = r, g = g, b = b }; dmApply() end },

        dmAreaToggle("dmUnitframes", L["Unit frames"],
            L["Player, target, focus, pet and party frame borders."]),
        dmAreaToggle("dmMinimap", L["Minimap"],
            L["Minimap border, compass, zoom and tracking buttons."]),
        dmAreaToggle("dmActionbars", L["Action bar artwork"],
            L["The gryphons and the metal action-bar background."]),
        dmAreaToggle("dmActionButtons", L["Action button borders"],
            L["Also tints the border ring around every action button. Optional — leave off if it looks too flat."]),
        dmAreaToggle("dmBags", L["Bag slots"],
            L["Tints the backpack, bag and keyring button borders."]),

        { type = "spacer", height = 6 },
        { type = "desc", text = L["|cffaaaaaaNote: if the Player & Target Frame module's |cffffffffThreat glow|r is on, threat colouring takes over the target/focus border while you have aggro — that's intended.|r"] },
    }
end

SLASH_VCUIWA1 = "/vcuiwa"
SlashCmdList.VCUIWA = function()
    local shown, skinned = 0, 0
    local unskinned = {}
    local function chain(f)
        local parts, n = {}, 0
        while f and n < 7 do
            parts[#parts + 1] = (f.GetName and f:GetName())
                or ("{" .. tostring(f.regionType or (f.GetObjectType and f:GetObjectType())) .. "}")
            f = f.GetParent and f:GetParent()
            n = n + 1
        end
        return table.concat(parts, " < ")
    end
    local types = {}
    local function walk(f, d)
        if not f or d > 12 then return end
        if f.IsForbidden and f:IsForbidden() then return end
        local rt = f.regionType
        if (rt == "icon" or rt == "aurabar") and f.icon and f.IsShown and f:IsShown() then
            types[rt] = (types[rt] or 0) + 1
            shown = shown + 1
            if f._vcuiRing then
                skinned = skinned + 1
            else
                local ok, err = pcall(skinWARegion, f)
                unskinned[#unskinned + 1] = rt .. " @ " .. chain(f)
                    .. (ok and "" or (" |cffff5555ERR " .. tostring(err) .. "|r"))
            end
        end
        if not f.GetChildren then return end
        local packed = { pcall(f.GetChildren, f) }
        if packed[1] then
            for i = 2, #packed do walk(packed[i], d + 1) end
        end
    end
    walk(UIParent, 0)
    ns:Print(string.format("WeakAuras regions: shown=%d skinned=%d unskinned=%d (icon=%d aurabar=%d) enabled=%s skinWA=%s",
        shown, skinned, #unskinned, types.icon or 0, types.aurabar or 0,
        tostring(mod._enabled), tostring(mod.db and mod.db.skinWeakAuras)))
    for i = 1, math.min(#unskinned, 12) do
        ns:Print("  " .. unskinned[i])
    end
    if #unskinned == 0 and shown > 0 then ns:Print("All shown WeakAuras icon/aurabar regions are skinned.") end
end
