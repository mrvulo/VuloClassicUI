-- =========================================================
-- VuloClassicUI / Modules / ButtonSkin
-- Lightweight Masque_Shadow-style skin for Blizzard action buttons — the
-- look people install Masque + Masque_Shadow for, without the framework:
--   - icons cropped so the ugly default border is gone
--   - chunky NormalTexture border removed
--   - rounded icon shape (mask) + a soft black drop-shadow that bleeds out
--     past the button edge (the Masque "Shadow" look)
--   - several styles: shadow / rounded / square / accent / circle / minimal
-- WeakAuras icons go through Masque automatically — point its "WeakAuras"
-- group at "Masque: Shadow 1" for the matching look.
-- No external library, no secure-frame writes (only textures/regions are
-- touched), fully toggleable.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("buttonskin", {
    name        = "Button Skin",
    group       = "UI Reskin",
    description = "Masque_Shadow-style skin for action buttons: black, rounded, soft drop-shadow. Lightweight Masque alternative with several styles.",
    defaults = {
        enabled       = true,
        style         = "shadow",  -- shadow | rounded | square | accent | circle | minimal
        skinPetStance = true,      -- also skin pet + stance buttons
        skinWeakAuras = true,      -- also add the shadow to WeakAuras icons (no Masque)
    },
})

-- Action button name prefixes × 12 ids
local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton", "BonusActionButton",
}
local EXTRA_PREFIXES = { "PetActionButton", "StanceButton" }

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

-- Bundled textures (rounded-square / circular masks + the soft shadow glow).
-- Shipped under Media\Masks\ so they load reliably in the Classic client.
local MASK_ROUNDED = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\csquare_mask.tga"  -- rounded square
local MASK_CIRCLE  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\circle_mask.tga"
local SHADOW_GLOW  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\shadow_glow.tga"      -- Masque "Shadow" hollow ring
local SHADOW_BACK  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\shadow_backdrop.tga"  -- Masque "Shadow" filled rounded backdrop

-- How far the soft shadow bleeds out past the button edge (px)
local SHADOW_INSET = 4

-- The Masque "Shadow 1" look = a FILLED dark rounded backdrop bleeding out
-- behind the icon (verified: Backdrop.tga centre alpha 255, corners 0) + a
-- HOLLOW dark rounded ring laid OVER the icon edge (Normal.tga centre 0, edge
-- ~165-221). Together they give the dark rim + depth of the real skin.
-- `outset` is how far the backdrop bleeds past the icon edge (px).
local function attachShadow(frame, anchor, store, outset)
    if not frame or not anchor then return end
    store = store or frame
    outset = outset or 4

    -- Filled dark rounded backdrop behind the icon (depth + dark rim)
    if not store._vcuiBack then
        local back = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        back:SetPoint("TOPLEFT",     anchor, "TOPLEFT",     -outset,  outset)
        back:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT",  outset, -outset)
        back:SetTexture(SHADOW_BACK)
        back:SetVertexColor(0.03, 0.03, 0.04, 1)   -- near-black, slightly cool
        store._vcuiBack = back
    end

    -- Hollow dark rounded ring over the icon edge — drawn twice for a crisper,
    -- stronger edge (the texture maxes at ~87% alpha, so one pass is soft).
    if not store._vcuiRing then
        local r1 = frame:CreateTexture(nil, "OVERLAY", nil, 6)
        r1:SetPoint("TOPLEFT",     anchor, "TOPLEFT",     -2,  2)
        r1:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT",  2, -2)
        r1:SetTexture(SHADOW_GLOW)
        r1:SetVertexColor(0, 0, 0, 1)
        store._vcuiRing = r1

        local r2 = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        r2:SetAllPoints(r1)
        r2:SetTexture(SHADOW_GLOW)
        r2:SetVertexColor(0, 0, 0, 1)
        store._vcuiRing2 = r2
    end
end

-- Style table: how each style draws a button
--   border = "black" | "accent" | nil (none)
--   bg     = dark backdrop behind the icon
--   mask   = mask texture (rounds the icon + backdrop) or nil
--   shadow = soft black drop-shadow glow behind the button (Masque_Shadow look)
local STYLES = {
    -- Default: the real Masque_Shadow look. Square cropped icon + a soft black
    -- rounded shadow bleeding out past the edge (its rounded corners make the
    -- square button read as gently rounded). No icon mask = rock-solid.
    shadow   = { border = nil,      bg = true,  mask = nil,          shadow = true  },  -- Masque_Shadow (square + soft shadow)
    rounded  = { border = nil,      bg = true,  mask = MASK_ROUNDED, shadow = true  },  -- icon corners actually masked round
    square   = { border = "black",  bg = true,  mask = nil,          shadow = false },  -- crisp square, black 1px edge
    accent   = { border = "accent", bg = true,  mask = nil,          shadow = false },  -- square, purple edge
    circle   = { border = nil,      bg = true,  mask = MASK_CIRCLE,  shadow = true  },  -- circular + shadow
    minimal  = { border = nil,      bg = false, mask = nil,          shadow = false },  -- cropped icon only
}

local function currentStyle()
    return STYLES[mod.db and mod.db.style] or STYLES.shadow
end

-- =========================================================
-- Skin a single button
-- =========================================================
local function getRegion(button, suffix, fallback)
    local name = button:GetName()
    return (name and _G[name .. suffix]) or fallback
end

local function hideNormalTexture(button)
    -- Action buttons expose the chunky border as NormalTexture
    local nt = (button.GetNormalTexture and button:GetNormalTexture())
            or getRegion(button, "NormalTexture", button.NormalTexture)
    if nt then
        nt:SetTexture(nil)
        nt:SetAlpha(0)
    end
end

-- Lazily create the button's reusable mask texture (anchored to the icon)
local function ensureMask(button, icon)
    if not button._vcuiMask and button.CreateMaskTexture then
        local m = button:CreateMaskTexture()
        m:SetAllPoints(icon)
        button._vcuiMask = m
    end
    return button._vcuiMask
end

-- Turn the rounded/circular mask on or off for both the icon and its backdrop,
-- so the whole button silhouette gets the shape (not just the icon art).
local function setMasked(button, icon, on, maskTex)
    if on then
        local m = ensureMask(button, icon)
        if not m then return end
        m:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:Show()
        if not button._vcuiMaskOn then
            if icon.AddMaskTexture then pcall(icon.AddMaskTexture, icon, m) end
            if button._vcuiBg and button._vcuiBg.AddMaskTexture then
                pcall(button._vcuiBg.AddMaskTexture, button._vcuiBg, m)
            end
            button._vcuiMaskOn = true
        end
    elseif button._vcuiMaskOn and button._vcuiMask then
        local m = button._vcuiMask
        if icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, m) end
        if button._vcuiBg and button._vcuiBg.RemoveMaskTexture then
            pcall(button._vcuiBg.RemoveMaskTexture, button._vcuiBg, m)
        end
        m:Hide()
        button._vcuiMaskOn = false
    end
end

-- Apply the current style's look to an already-prepared button
local function applyStyle(button)
    local st   = currentStyle()
    local icon = getRegion(button, "Icon", button.icon or button.Icon)

    -- Always crop away the icon's built-in border ring
    if icon and icon.SetTexCoord then icon:SetTexCoord(unpack(ICON_CROP)) end

    -- Eckiger Fallback-Backdrop nur ohne Shadow-Style
    if button._vcuiBg then
        button._vcuiBg:SetShown((st.bg and not st.shadow) and true or false)
    end

    -- Masque "Shadow": filled rounded backdrop + dark ring over the icon edge
    local showShadow = st.shadow and true or false
    if button._vcuiBack  then button._vcuiBack:SetShown(showShadow) end
    if button._vcuiRing  then button._vcuiRing:SetShown(showShadow) end
    if button._vcuiRing2 then button._vcuiRing2:SetShown(showShadow) end

    -- Shape mask (rounded / circle) on icon + backdrop
    if icon then
        setMasked(button, icon, st.mask ~= nil, st.mask)
    end

    -- Border
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
end

local function skinButton(button)
    if not button then return end
    if not button._vcuiSkinned then
        button._vcuiSkinned = true

        -- Masque "Shadow" look: a soft black rounded ring laid over the icon's
        -- outer edge. Anchored to the icon so it lines up with what you see.
        local icon0 = getRegion(button, "Icon", button.icon or button.Icon)
        attachShadow(button, icon0 or button, button)

        -- Dark backdrop behind the icon (created once; shown/hidden per style)
        local bg = button:CreateTexture(nil, "BACKGROUND", nil, -2)
        bg:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        bg:SetColorTexture(0.04, 0.04, 0.05, 0.9)
        button._vcuiBg = bg

        -- Thin 1px border frame (created once; colored/shown per style)
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

    hideNormalTexture(button)
    applyStyle(button)
end

-- =========================================================
-- Skin all buttons
-- =========================================================
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
    if not mod._enabled or not mod.db then return end
    forEachButton(skinButton)
end

-- Re-apply the active style without re-creating frames
local function refreshAll()
    if not mod._enabled or not mod.db then return end
    forEachButton(function(b)
        if b._vcuiSkinned then
            hideNormalTexture(b)
            applyStyle(b)
        end
    end)
end

-- =========================================================
-- WeakAuras icon skinning (always — works with or without Masque).
-- The shadow sits behind the outer `region` frame, which is the icon's
-- bounding box in both Masque and non-Masque modes, so it lines up either way.
-- =========================================================
local function skinWAIcon(region)
    if not region or region.regionType ~= "icon" then return end
    if region._vcuiRing then return end
    local icon = region.icon
    if not icon then return end
    -- Anchor to the icon itself (it spans the visible area in both Masque and
    -- non-Masque modes), so the ring lines up with what you actually see.
    attachShadow(region, icon, region)
end

local function skinWAById(id)
    if not (WeakAuras and WeakAuras.GetRegion) then return end
    local ok, region = pcall(WeakAuras.GetRegion, id)
    if ok and region then skinWAIcon(region) end
end

-- Scan all currently-existing icon regions (lazy: only auras that exist now)
local function skinAllWAIcons()
    if not mod._enabled or not mod.db or not mod.db.skinWeakAuras then return end
    if not (WeakAuras and WeakAuras.GetRegion) then return end
    local saved = _G.WeakAurasSaved
    if not (saved and saved.displays) then return end
    for id, data in pairs(saved.displays) do
        if type(data) == "table" and data.regionType == "icon" then
            skinWAById(id)
        end
    end
end

-- Hook WeakAuras.Add so future / edited / re-loaded icon auras get skinned too.
-- (Private is not reachable externally; Add is the public per-aura entry point.)
local waHooked = false
local function hookWeakAuras()
    if waHooked or not (WeakAuras and WeakAuras.Add) then return end
    waHooked = true
    hooksecurefunc(WeakAuras, "Add", function(data)
        if not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
        if type(data) ~= "table" or data.regionType ~= "icon" or not data.id then return end
        local id = data.id
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function() skinWAById(id) end)  -- let the region build
        else
            skinWAById(id)
        end
    end)
end

-- =========================================================
-- Lifecycle
-- =========================================================
local hookInstalled = false

local function skinEverything()
    skinAll()
    skinAllWAIcons()
end

function mod:OnEnable()
    if not mod.db then return end

    -- Skin our own way (no Masque dependency). Deferred so all frames exist.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, skinEverything)
        C_Timer.After(2.0, skinEverything)
        C_Timer.After(5.0, skinAllWAIcons)   -- WeakAuras often loads late
    else
        skinEverything()
    end

    -- Catch future / edited / lazily-built WeakAuras icons
    hookWeakAuras()

    -- Blizzard rebuilds NormalTexture on button updates — re-hide it after.
    if not hookInstalled then
        hookInstalled = true
        if _G.ActionButton_Update then
            hooksecurefunc("ActionButton_Update", function(button)
                if mod._enabled and button and button._vcuiSkinned then
                    hideNormalTexture(button)
                end
            end)
        end
    end

    -- Re-skin when bars / auras show or refresh
    ns:RegisterEvent("PLAYER_ENTERING_WORLD",     skinEverything)
    ns:RegisterEvent("UPDATE_SHAPESHIFT_FORMS",   skinAll)
    ns:RegisterEvent("PET_BAR_UPDATE",            skinAll)
    ns:RegisterEvent("PLAYER_REGEN_DISABLED",     skinAllWAIcons)  -- procs appearing in combat
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",      skinAllWAIcons)
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD",   skinEverything)
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS", skinAll)
    ns:UnregisterEvent("PET_BAR_UPDATE",          skinAll)
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED",   skinAllWAIcons)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",    skinAllWAIcons)
    -- Note: existing skins stay until /reload (we don't tear down the borders
    -- to avoid touching buttons in combat). A /reload fully removes them.
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local STYLE_VALUES = {
        { value = "shadow",  text = L["Shadow (Masque-style: square + soft shadow)"] },
        { value = "rounded", text = L["Rounded icon (masked corners)"] },
        { value = "square",  text = L["Square (black edge)"] },
        { value = "accent",  text = L["Square (accent edge)"] },
        { value = "circle",  text = L["Circle"] },
        { value = "minimal", text = L["Minimal (icon only)"] },
    }

    local waText = L["|cffaaaaaaWeakAuras icons get the same soft shadow. If Masque also skins them you may see a double edge — disable Masque's WeakAuras group then.|r"]

    return {
        { type = "header", text = L["Button Skin"] },
        { type = "desc", text = L["|cffaaaaaaShadow-1 look for the action bars — no Masque required. Cropped icons with a soft black drop-shadow.|r"] },

        { type = "dropdown", label = L["Style"],
          tooltip = L["Pick how the action buttons look. Rounded/Circle use an icon mask; Minimal is just the cropped icon."],
          width = 260,
          values = STYLE_VALUES,
          get = function() return mod.db.style or "shadow" end,
          set = function(_, v) mod.db.style = v; refreshAll() end },

        { type = "toggle", label = L["Also skin pet & stance buttons"],
          get = function() return mod.db.skinPetStance end,
          set = function(_, v) mod.db.skinPetStance = v; skinAll() end },

        { type = "toggle", label = L["Also skin WeakAuras icons"],
          get = function() return mod.db.skinWeakAuras end,
          set = function(_, v) mod.db.skinWeakAuras = v; skinAllWAIcons() end },

        { type = "spacer", height = 6 },
        { type = "desc", text = waText },
        { type = "spacer", height = 4 },
        { type = "desc", text = L["|cffaaaaaaNote: turning the skin off fully reverts after a /reload.|r"] },
    }
end
