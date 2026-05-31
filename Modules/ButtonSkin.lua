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

-- How many px the icon shrinks so the dark backdrop shows as a rim all around
-- it (the real Masque "Shadow" look — icon smaller than the frame).
local ICON_INSET = 3

-- Shrink (or restore) the icon inside its frame so the backdrop forms a rim.
local function setIconInset(frame, icon, px)
    if not (icon and icon.ClearAllPoints and frame) then return end
    icon:ClearAllPoints()
    if px and px > 0 then
        icon:SetPoint("TOPLEFT",     frame, "TOPLEFT",      px, -px)
        icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px,  px)
    else
        icon:SetAllPoints(frame)
    end
end

-- The Masque "Shadow 1" look = a FILLED dark rounded backdrop (verified:
-- Backdrop.tga centre alpha 255, corners 0) at the full FRAME size, with the
-- icon shrunk inside it (see setIconInset) so the backdrop shows as a clean
-- dark rounded rim all around the icon. `outset` is a small bleed past the
-- frame edge for soft depth.
local function attachShadow(frame, store, outset)
    if not frame then return end
    store = store or frame
    outset = outset or 2

    if not store._vcuiBack then
        local back = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        back:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -outset,  outset)
        back:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  outset, -outset)
        back:SetTexture(SHADOW_BACK)
        back:SetVertexColor(0.03, 0.03, 0.04, 1)   -- near-black
        store._vcuiBack = back
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
    shadow   = { border = nil,      bg = true,  mask = nil,          shadow = true  },  -- Masque_Shadow: square icon + dark rim
    rounded  = { border = nil,      bg = true,  mask = MASK_ROUNDED, shadow = false },  -- icon corners masked round
    square   = { border = "black",  bg = true,  mask = nil,          shadow = false },  -- crisp square, black 1px edge
    accent   = { border = "accent", bg = true,  mask = nil,          shadow = false },  -- square, purple edge
    circle   = { border = nil,      bg = true,  mask = MASK_CIRCLE,  shadow = false },  -- circular
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
    -- Action buttons expose the chunky gold border as NormalTexture
    local nt = (button.GetNormalTexture and button:GetNormalTexture())
            or getRegion(button, "NormalTexture", button.NormalTexture)
    if nt then
        nt:SetTexture(nil)
        nt:SetAlpha(0)
    end
    -- Empty-slot grid border (shown when "always show buttons" is on)
    local slot = getRegion(button, "SlotBackground", button.SlotBackground)
    if slot then slot:SetAlpha(0) end
end

-- Blizzard re-applies the NormalTexture on state changes and this client has
-- no reliable global ActionButton_Update, so hook each button's setter once.
local function lockNormalTexture(button)
    if button._vcuiNTHook or not button.SetNormalTexture then return end
    button._vcuiNTHook = true
    hooksecurefunc(button, "SetNormalTexture", function(self)
        if mod._enabled and self._vcuiSkinned then
            local n = self.GetNormalTexture and self:GetNormalTexture()
            if n and n.GetAlpha and n:GetAlpha() ~= 0 then
                n:SetTexture(nil); n:SetAlpha(0)
            end
        end
    end)
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

    -- Shrink the icon for the Shadow style so the backdrop forms a rim around it
    if icon then setIconInset(button, icon, st.shadow and ICON_INSET or 0) end

    -- Eckiger Fallback-Backdrop nur ohne Shadow-Style
    if button._vcuiBg then
        button._vcuiBg:SetShown((st.bg and not st.shadow) and true or false)
    end

    -- Masque "Shadow": filled dark rounded backdrop bleeding out as a rim
    if button._vcuiBack then button._vcuiBack:SetShown(st.shadow and true or false) end

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

        -- Masque "Shadow": filled dark rounded backdrop at button size; the icon
        -- is shrunk inside it (applyStyle) so the backdrop forms the rim.
        attachShadow(button, button)

        -- Keep Blizzard's gold border from coming back
        lockNormalTexture(button)

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
-- WeakAuras icon skinning (always — works with or without Masque). Uses the
-- SAME style as the bars (shadow / rounded / square / circle / minimal), so the
-- style dropdown drives both. The shadow/mask anchor to region.icon, which
-- spans the visible area in both Masque and non-Masque modes.
-- =========================================================
local function styleWAIcon(region)
    if not region or region.regionType ~= "icon" then return end
    local icon = region.icon
    if not icon then return end

    attachShadow(region, region)                -- create backdrop once
    local st = currentStyle()

    if region._vcuiBack then region._vcuiBack:SetShown(st.shadow and true or false) end

    -- Shrink the icon for the Shadow style so the backdrop forms a rim
    setIconInset(region, icon, st.shadow and ICON_INSET or 0)

    -- rounded / circle icon mask (idempotent)
    setMasked(region, icon, st.mask ~= nil, st.mask)
end

local function skinWAById(id)
    if not (WeakAuras and WeakAuras.GetRegion) then return end
    local ok, region = pcall(WeakAuras.GetRegion, id)
    if ok and region then styleWAIcon(region) end
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
          set = function(_, v) mod.db.style = v; refreshAll(); skinAllWAIcons() end },

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
