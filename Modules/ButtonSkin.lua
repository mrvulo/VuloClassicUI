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
        enabled         = true,
        useAccentBorder = false,  -- false = black edge (classic Shadow), true = purple accent
        skinPetStance   = true,   -- also skin pet + stance buttons
    },
})

-- Action button name prefixes × 12 ids
local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton", "BonusActionButton",
}
local EXTRA_PREFIXES = { "PetActionButton", "StanceButton" }

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

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

local function skinButton(button)
    if not button then return end
    if not button._vcuiSkinned then
        button._vcuiSkinned = true

        -- Crop the icon (removes the built-in dark border ring)
        local icon = getRegion(button, "Icon", button.icon or button.Icon)
        if icon and icon.SetTexCoord then
            icon:SetTexCoord(unpack(ICON_CROP))
        end

        -- Dark backdrop behind the icon (fills the 1px gap to the edge)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        bg:SetColorTexture(0.04, 0.04, 0.05, 0.9)
        button._vcuiBg = bg

        -- Thin 1px border frame around the button
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

    -- Border color follows the setting
    if button._vcuiBorder and button._vcuiBorder.SetBackdropBorderColor then
        if mod.db.useAccentBorder then
            local a = ns.COLORS.accent
            button._vcuiBorder:SetBackdropBorderColor(a.r, a.g, a.b, 1)
        else
            button._vcuiBorder:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end
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

-- Re-apply border color / re-hide normal textures without re-creating frames
local function refreshAll()
    if not mod._enabled or not mod.db then return end
    forEachButton(function(b)
        if b._vcuiSkinned then
            hideNormalTexture(b)
            if b._vcuiBorder and b._vcuiBorder.SetBackdropBorderColor then
                if mod.db.useAccentBorder then
                    local a = ns.COLORS.accent
                    b._vcuiBorder:SetBackdropBorderColor(a.r, a.g, a.b, 1)
                else
                    b._vcuiBorder:SetBackdropBorderColor(0, 0, 0, 1)
                end
            end
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
    return {
        { type = "header", text = L["Button Skin"] },
        { type = "desc", text = L["|cffaaaaaaA clean Shadow-style skin for the action buttons — cropped icons, a thin border and a dark backdrop. Lightweight alternative to Masque + Masque_Shadow.|r"] },

        { type = "toggle", label = L["Accent-colored border"],
          tooltip = L["Off = black edge (classic Shadow look). On = purple accent border matching the UI."],
          get = function() return mod.db.useAccentBorder end,
          set = function(_, v) mod.db.useAccentBorder = v; refreshAll() end },

        { type = "toggle", label = L["Also skin pet & stance buttons"],
          get = function() return mod.db.skinPetStance end,
          set = function(_, v) mod.db.skinPetStance = v; skinAll() end },

        { type = "spacer", height = 6 },
        { type = "desc", text = L["|cffaaaaaaNote: turning the skin off fully reverts after a /reload. Works on Blizzard's default bars; if you use another action-bar addon, let it handle skinning instead.|r"] },
    }
end
