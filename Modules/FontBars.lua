-- =========================================================
-- VuloClassicUI / Modules / FontBars
-- Ehemals: VuloFontBars
-- Kleinere Schriftgrößen auf Player/Target/Pet Health & Mana Bars,
-- plus dauerhaftes Verstecken des TargetFrameBackground.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("fontbars", {
    name        = "Font Bars",
    group       = "Unit Frames",
    description = "Kleinere Schriftgrößen für Player/Target/Pet Health & Mana Bars, optional TargetFrameBackground verstecken.",
    defaults = {
        healthSize       = 11,
        powerSize        = 11,
        petFeedbackSize  = 11,
        onlyTheseBars    = true,
        hideTargetBackground = true,
    },
})

-- =========================================================
-- Helpers
-- =========================================================
local function isOurBar(bar)
    if not mod.db.onlyTheseBars then return true end
    return bar == PlayerFrameHealthBar
        or bar == PlayerFrameManaBar
        or bar == TargetFrameHealthBar
        or bar == TargetFrameManaBar
        or bar == PetFrameHealthBar
        or bar == PetFrameManaBar
end

local function applyPetFeedbackFont()
    local size = tonumber(mod.db.petFeedbackSize) or 11
    local fs = PetFrameFeedbackText
        or (PetFrame and (PetFrame.FeedbackText or PetFrame.feedbackText))
        or _G["PetFrameFeedbackText"]
    if not fs or not fs.GetFont or not fs.SetFont then return end
    local font, _, flags = fs:GetFont()
    if not font then return end
    fs:SetFont(font, size, flags)
end

local function applyAll()
    if not mod._enabled then return end
    local hs = mod.db.healthSize
    local ps = mod.db.powerSize

    if PlayerFrameHealthBar then ns:SetBarTextFontSize(PlayerFrameHealthBar, hs) end
    if PlayerFrameManaBar   then ns:SetBarTextFontSize(PlayerFrameManaBar,   ps) end
    if TargetFrameHealthBar then ns:SetBarTextFontSize(TargetFrameHealthBar, hs) end
    if TargetFrameManaBar   then ns:SetBarTextFontSize(TargetFrameManaBar,   ps) end
    if PetFrameHealthBar    then ns:SetBarTextFontSize(PetFrameHealthBar,    hs) end
    if PetFrameManaBar      then ns:SetBarTextFontSize(PetFrameManaBar,      ps) end

    if TextStatusBar_UpdateTextString then
        if PlayerFrameHealthBar then TextStatusBar_UpdateTextString(PlayerFrameHealthBar) end
        if PlayerFrameManaBar   then TextStatusBar_UpdateTextString(PlayerFrameManaBar)   end
        if TargetFrameHealthBar then TextStatusBar_UpdateTextString(TargetFrameHealthBar) end
        if TargetFrameManaBar   then TextStatusBar_UpdateTextString(TargetFrameManaBar)   end
        if PetFrameHealthBar    then TextStatusBar_UpdateTextString(PetFrameHealthBar)    end
        if PetFrameManaBar      then TextStatusBar_UpdateTextString(PetFrameManaBar)      end
    end

    applyPetFeedbackFont()
end

local function hideTargetBackground()
    if not mod._enabled then return end
    if not mod.db.hideTargetBackground then return end
    if TargetFrameBackground then TargetFrameBackground:Hide() end
end

mod.applyAll = applyAll  -- nach außen für Slider-Live-Updates

-- =========================================================
-- Hooks (einmalig setzen, nicht jedes Mal bei Enable)
-- =========================================================
local hooksInstalled = false
local function installHooks()
    if hooksInstalled or not hooksecurefunc then return end
    hooksInstalled = true

    if TextStatusBar_UpdateTextString then
        hooksecurefunc("TextStatusBar_UpdateTextString", function(bar)
            if not mod._enabled then return end
            if not bar or not isOurBar(bar) then return end
            if bar == PlayerFrameHealthBar or bar == TargetFrameHealthBar or bar == PetFrameHealthBar then
                ns:SetBarTextFontSize(bar, mod.db.healthSize)
            elseif bar == PlayerFrameManaBar or bar == TargetFrameManaBar or bar == PetFrameManaBar then
                ns:SetBarTextFontSize(bar, mod.db.powerSize)
            end
        end)
    end

    if PetFrame_Update then
        hooksecurefunc("PetFrame_Update", function() applyPetFeedbackFont() end)
    end
    if PetFrame_UpdateStatus then
        hooksecurefunc("PetFrame_UpdateStatus", function() applyPetFeedbackFont() end)
    end
    if TargetFrame_CheckDead then
        hooksecurefunc("TargetFrame_CheckDead", function() hideTargetBackground() end)
    end
    if TargetFrame_Update then
        hooksecurefunc("TargetFrame_Update", function() hideTargetBackground() end)
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    installHooks()

    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        applyAll()
        hideTargetBackground()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() applyAll(); hideTargetBackground() end)
            C_Timer.After(1, function() applyAll(); hideTargetBackground() end)
        end
    end)
    ns:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        applyAll(); hideTargetBackground()
    end)
    ns:RegisterEvent("UNIT_PET", function() applyAll() end)

    applyAll()
    hideTargetBackground()
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = "Schriftgrößen" },
        {
            type = "slider", label = "Health-Bar Text",
            min = 6, max = 24, step = 1,
            tooltip = "Schriftgröße auf Health-Bars (Player/Target/Pet).",
            get = function() return mod.db.healthSize end,
            set = function(_, v) mod.db.healthSize = v; applyAll() end,
        },
        {
            type = "slider", label = "Power-Bar Text",
            min = 6, max = 24, step = 1,
            tooltip = "Schriftgröße auf Mana/Power-Bars.",
            get = function() return mod.db.powerSize end,
            set = function(_, v) mod.db.powerSize = v; applyAll() end,
        },
        {
            type = "slider", label = "Pet Combat Feedback Text",
            min = 6, max = 24, step = 1,
            tooltip = "Schriftgröße für 'Damage', 'Dodge', 'Miss' beim Pet.",
            get = function() return mod.db.petFeedbackSize end,
            set = function(_, v) mod.db.petFeedbackSize = v; applyAll() end,
        },
        { type = "spacer" },
        { type = "header", text = "Verhalten" },
        {
            type = "checkbox", label = "Nur Player/Target/Pet Bars beeinflussen",
            tooltip = "Wenn aus: alle TextStatusBars im UI werden mit den Größen oben überschrieben (kann andere Addons stören).",
            get = function() return mod.db.onlyTheseBars end,
            set = function(_, v) mod.db.onlyTheseBars = v; applyAll() end,
        },
        {
            type = "checkbox", label = "TargetFrame-Background verstecken",
            tooltip = "Versteckt das dunkle Hintergrund-Element des TargetFrames dauerhaft.",
            get = function() return mod.db.hideTargetBackground end,
            set = function(_, v)
                mod.db.hideTargetBackground = v
                if v then hideTargetBackground()
                elseif TargetFrameBackground then TargetFrameBackground:Show() end
            end,
        },
    }
end
