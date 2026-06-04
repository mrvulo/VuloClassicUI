-- =========================================================
-- VuloClassicUI / Modules / FixCombatGlow
-- Restores the missing "in combat" indicator on the default Player frame.
-- Confirmed TBC Anniversary default-UI bug: the player frame no longer flashes
-- red in combat. We add our own red glow around the player portrait, toggled by
-- PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED. Pure cosmetic, no taint.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixcombatglow", {
    name        = "Combat Indicator",
    group       = "Bugfixes",
    description = "Restores the missing 'in combat' glow on the Player frame (Anniversary default-UI bug). Pulses a red glow around your portrait while you are in combat.",
    defaults = {
        enabled = true,
    },
})

local glow

local function ensureGlow()
    if glow then return glow end
    local pf = _G.PlayerFrame
    if not pf then return nil end

    glow = pf:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.15, 0.15, 1)

    local portrait = _G.PlayerPortrait
    if portrait then
        glow:SetPoint("CENTER", portrait, "CENTER", 0, 0)
        local w, h = portrait:GetSize()
        if not w or w == 0 then w, h = 60, 60 end
        glow:SetSize(w * 1.9, h * 1.9)
    else
        -- Fallback: roughly over the portrait area of the player frame
        glow:SetPoint("CENTER", pf, "TOPLEFT", 40, -25)
        glow:SetSize(110, 110)
    end

    -- Subtle pulse so the combat state is noticeable
    glow.anim = glow:CreateAnimationGroup()
    glow.anim:SetLooping("BOUNCE")
    local a = glow.anim:CreateAnimation("Alpha")
    a:SetFromAlpha(1.0)
    a:SetToAlpha(0.35)
    a:SetDuration(0.7)

    glow:Hide()
    return glow
end

local function update()
    local g = ensureGlow()
    if not g then return end
    if mod._enabled and UnitAffectingCombat and UnitAffectingCombat("player") then
        g:Show()
        if g.anim then g.anim:Play() end
    else
        if g.anim then g.anim:Stop() end
        g:Hide()
    end
end

function mod:OnEnable()
    ensureGlow()
    ns:RegisterEvent("PLAYER_REGEN_DISABLED", update)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",  update)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", update)
    update()
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED", update)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",  update)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", update)
    if glow then
        if glow.anim then glow.anim:Stop() end
        glow:Hide()
    end
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Combat Indicator"] },
        { type = "desc", text = L["|cffaaaaaaThe default Player frame on Anniversary no longer shows when you are in combat. This restores it: a red glow pulses around your portrait while you are in combat.|r"] },
    }
end
