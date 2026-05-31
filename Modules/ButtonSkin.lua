-- =========================================================
-- VuloClassicUI / Modules / ButtonSkin
-- Lightweight "Shadow"-style skin for Blizzard action buttons — the look
-- people install Masque + Masque_Shadow for, without the framework:
--   - icons cropped so the ugly default border is gone
--   - chunky NormalTexture border removed, replaced by a clean 1px edge
--   - dark backdrop behind each icon
-- No external library, no secure-frame writes (only textures/regions are
-- touched), fully toggleable.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("buttonskin", {
    name        = "Button Skin",
    group       = "UI Reskin",
    description = "Clean Shadow-style skin for action buttons: cropped icons, thin border, dark backdrop. A lightweight Masque_Shadow alternative.",
    defaults = {
        enabled       = true,
        style         = "shadow",  -- shadow | accent | rounded | circle | minimal
        skinPetStance = true,      -- also skin pet + stance buttons
    },
})

-- Action button name prefixes × 12 ids
local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton", "BonusActionButton",
}
local EXTRA_PREFIXES = { "PetActionButton", "StanceButton" }

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

-- Bundled mask textures (rounded-square / circular icon shapes).
-- Shipped under Media\Masks\ so they load reliably in the Classic client.
local MASK_ROUNDED = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\csquare_mask.tga"  -- rounded square
local MASK_CIRCLE  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\circle_mask.tga"

-- Style table: how each style draws an icon
--   border   = "black" | "accent" | nil (none)
--   bg       = show dark backdrop behind icon
--   mask     = mask texture (rounds the icon) or nil
local STYLES = {
    shadow  = { border = "black",  bg = true,  mask = nil          },  -- square, black edge
    accent  = { border = "accent", bg = true,  mask = nil          },  -- square, purple edge
    rounded = { border = nil,      bg = true,  mask = MASK_ROUNDED },  -- rounded silhouette
    circle  = { border = nil,      bg = true,  mask = MASK_CIRCLE  },  -- circular silhouette
    minimal = { border = nil,      bg = false, mask = nil          },  -- cropped icon only
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

    -- Dark backdrop behind the icon
    if button._vcuiBg then
        button._vcuiBg:SetShown(st.bg and true or false)
    end

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

        -- Dark backdrop behind the icon (created once; shown/hidden per style)
        local bg = button:CreateTexture(nil, "BACKGROUND")
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
-- Lifecycle
-- =========================================================
local hookInstalled = false

function mod:OnEnable()
    if not mod.db then return end

    -- Initial skin (deferred so all bar frames exist)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, skinAll)
        C_Timer.After(2.0, skinAll)
    else
        skinAll()
    end

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

    -- Re-skin when bars show/refresh
    ns:RegisterEvent("PLAYER_ENTERING_WORLD",     skinAll)
    ns:RegisterEvent("UPDATE_SHAPESHIFT_FORMS",   skinAll)
    ns:RegisterEvent("PET_BAR_UPDATE",            skinAll)
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD",   skinAll)
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS", skinAll)
    ns:UnregisterEvent("PET_BAR_UPDATE",          skinAll)
    -- Note: existing skins stay until /reload (we don't tear down the borders
    -- to avoid touching buttons in combat). A /reload fully removes them.
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local STYLE_VALUES = {
        { value = "shadow",  text = L["Shadow (square, black edge)"] },
        { value = "accent",  text = L["Accent (square, purple edge)"] },
        { value = "rounded", text = L["Rounded corners"] },
        { value = "circle",  text = L["Circle"] },
        { value = "minimal", text = L["Minimal (icon only)"] },
    }

    return {
        { type = "header", text = L["Button Skin"] },
        { type = "desc", text = L["|cffaaaaaaA clean skin for the action buttons — cropped icons, a thin border and a dark backdrop. Lightweight alternative to Masque + Masque_Shadow.|r"] },

        { type = "dropdown", label = L["Style"],
          tooltip = L["Pick how the action buttons look. Rounded/Circle use an icon mask; Minimal is just the cropped icon."],
          width = 260,
          values = STYLE_VALUES,
          get = function() return mod.db.style or "shadow" end,
          set = function(_, v) mod.db.style = v; refreshAll() end },

        { type = "toggle", label = L["Also skin pet & stance buttons"],
          get = function() return mod.db.skinPetStance end,
          set = function(_, v) mod.db.skinPetStance = v; skinAll() end },

        { type = "spacer", height = 6 },
        { type = "desc", text = L["|cffaaaaaaNote: turning the skin off fully reverts after a /reload. Works on Blizzard's default bars; if you use another action-bar addon, let it handle skinning instead.|r"] },
    }
end
