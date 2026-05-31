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

-- Bundled textures (rounded-square / circular masks + the soft shadow glow).
-- Shipped under Media\Masks\ so they load reliably in the Classic client.
local MASK_ROUNDED = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\csquare_mask.tga"  -- rounded square
local MASK_CIRCLE  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\circle_mask.tga"
local SHADOW_GLOW  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\shadow_glow.tga"   -- Masque "Shadow" glow

-- How far the soft shadow bleeds out past the button edge (px)
local SHADOW_INSET = 4

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

    -- Dark backdrop behind the icon
    if button._vcuiBg then
        button._vcuiBg:SetShown(st.bg and true or false)
    end

    -- Soft black drop-shadow (Masque_Shadow look)
    if button._vcuiShadow then
        button._vcuiShadow:SetShown(st.shadow and true or false)
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

        -- Soft black drop-shadow behind everything (the Masque "Shadow" glow).
        -- Bleeds out past the button edge; not masked (it already is the shape).
        local shadow = button:CreateTexture(nil, "BACKGROUND", nil, -8)
        shadow:SetPoint("TOPLEFT",     button, "TOPLEFT",     -SHADOW_INSET,  SHADOW_INSET)
        shadow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT",  SHADOW_INSET, -SHADOW_INSET)
        shadow:SetTexture(SHADOW_GLOW)
        shadow:SetVertexColor(0, 0, 0, 1)     -- tint the grey glow pure black
        shadow:Hide()
        button._vcuiShadow = shadow

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
-- Masque integration (preferred when Masque is installed)
-- When Masque is present we register Blizzard's action buttons with it and
-- let Masque skin them with a real skin (e.g. "Masque: Shadow 1"), exactly
-- like WeakAuras already does for its icons. This gives both the same look.
-- =========================================================
-- Resolve Masque lazily — it's a separate addon and may load after us.
local MSQ
local msqChecked = false
local function ensureMSQ()
    if not msqChecked then
        msqChecked = true
        MSQ = (LibStub and LibStub("Masque", true)) or nil
        mod.hasMasque = MSQ ~= nil
    end
    return MSQ
end

local MASQUE_SKIN = "Masque: Shadow 1"
local msqBars, msqExtra   -- Masque group objects

local function getBarGroup()
    if not msqBars then msqBars = MSQ:Group("VuloClassicUI", "Action Bars") end
    return msqBars
end
local function getExtraGroup()
    if not msqExtra then msqExtra = MSQ:Group("VuloClassicUI", "Pet & Stance") end
    return msqExtra
end

-- Push a skin onto our groups (used once for the default, or from the button)
local function applyMasqueSkin(skinID)
    if not MSQ then return end
    local g1 = getBarGroup()
    if g1 and g1.__Set then pcall(g1.__Set, g1, "SkinID", skinID) end
    if msqExtra and msqExtra.__Set then pcall(msqExtra.__Set, msqExtra, "SkinID", skinID) end
end

local function addPrefixToGroup(group, prefix)
    for i = 1, 12 do
        local b = _G[prefix .. i]
        if b and not b._vcuiMSQ then
            b._vcuiMSQ = true
            pcall(group.AddButton, group, b, nil, "Action")
        end
    end
end

local function registerMasque()
    if not ensureMSQ() or not mod._enabled or not mod.db then return end

    local bars = getBarGroup()
    for _, prefix in ipairs(BAR_PREFIXES) do
        addPrefixToGroup(bars, prefix)
    end

    if mod.db.skinPetStance then
        local extra = getExtraGroup()
        for _, prefix in ipairs(EXTRA_PREFIXES) do
            addPrefixToGroup(extra, prefix)
        end
    end

    -- One-time: default our groups to Shadow 1 so the look shows up instantly.
    -- After this the user can freely pick any skin in Masque; we never re-force it.
    if not mod.db.masqueSkinApplied then
        mod.db.masqueSkinApplied = true
        applyMasqueSkin(MASQUE_SKIN)
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
local hookInstalled = false

function mod:OnEnable()
    if not mod.db then return end

    -- ---- Masque path: hand the buttons to Masque, it does the skinning ----
    if ensureMSQ() then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, registerMasque)
            C_Timer.After(2.0, registerMasque)
        else
            registerMasque()
        end
        ns:RegisterEvent("PLAYER_ENTERING_WORLD",   registerMasque)
        ns:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", registerMasque)
        ns:RegisterEvent("PET_BAR_UPDATE",          registerMasque)
        return
    end

    -- ---- Fallback path: our own lightweight skin (no Masque installed) ----
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
    if ensureMSQ() then
        ns:UnregisterEvent("PLAYER_ENTERING_WORLD",   registerMasque)
        ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS", registerMasque)
        ns:UnregisterEvent("PET_BAR_UPDATE",          registerMasque)
        -- Masque keeps managing the buttons until /reload (avoids enable/disable
        -- state churn); Masque's own group toggle can hard-disable if wanted.
        return
    end

    ns:UnregisterEvent("PLAYER_ENTERING_WORLD",   skinAll)
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS", skinAll)
    ns:UnregisterEvent("PET_BAR_UPDATE",          skinAll)
    -- Note: existing skins stay until /reload (we don't tear down the borders
    -- to avoid touching buttons in combat). A /reload fully removes them.
end

-- =========================================================
-- Options
-- =========================================================
local function openMasque()
    if SlashCmdList and SlashCmdList["MASQUE"] then
        SlashCmdList["MASQUE"]("")
    elseif _G.Masque and _G.Masque.ToggleOptions then
        pcall(_G.Masque.ToggleOptions)
    end
end

function mod:GetOptions()
    -- ---- Masque present: drive the real Masque_Shadow skin ----
    if ensureMSQ() then
        return {
            { type = "header", text = L["Button Skin"] },
            { type = "desc", text = L["|cffaaaaaaMasque detected. Your action bars are registered with Masque and skinned with \"Masque: Shadow 1\" — the same texture WeakAuras uses, so both match.|r"] },

            { type = "button", label = L["Open Masque"], primary = true,
              tooltip = L["Open Masque to pick a different skin or tweak the groups (VuloClassicUI / Action Bars & Pet & Stance)."],
              onClick = openMasque },

            { type = "button", label = L["Reset bars to Shadow 1"],
              tooltip = L["Force the action-bar groups back to the \"Masque: Shadow 1\" skin."],
              onClick = function() applyMasqueSkin(MASQUE_SKIN) end },

            { type = "toggle", label = L["Also skin pet & stance buttons"],
              get = function() return mod.db.skinPetStance end,
              set = function(_, v) mod.db.skinPetStance = v; registerMasque() end },

            { type = "spacer", height = 6 },
            { type = "desc", text = L["|cffaaaaaaWeakAuras icons: open Masque, set the \"WeakAuras\" group to \"Masque: Shadow 1\" for the exact same look.|r"] },
        }
    end

    -- ---- No Masque: our own lightweight skin with style presets ----
    local STYLE_VALUES = {
        { value = "shadow",  text = L["Shadow (Masque-style: square + soft shadow)"] },
        { value = "rounded", text = L["Rounded icon (masked corners)"] },
        { value = "square",  text = L["Square (black edge)"] },
        { value = "accent",  text = L["Square (accent edge)"] },
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
        { type = "desc", text = L["|cffaaaaaaInstall Masque + Masque_Shadow for the full textured look on bars and WeakAuras.|r"] },
        { type = "spacer", height = 4 },
        { type = "desc", text = L["|cffaaaaaaNote: turning the skin off fully reverts after a /reload. Works on Blizzard's default bars; if you use another action-bar addon, let it handle skinning instead.|r"] },
    }
end
