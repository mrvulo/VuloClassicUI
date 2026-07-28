-- FontBars: smaller font sizes on Player/Target/Pet Health & Mana bars, plus permanently hiding the TargetFrameBackground.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fontbars", {
    name        = "Font Bars",
    group       = "Unit Frames",
    description = "Smaller font sizes for Player/Target/Pet Health & Mana bars, optionally hide TargetFrameBackground.",
    defaults = {
        healthSize       = 11,
        powerSize        = 11,
        petFeedbackSize  = 11,
        onlyTheseBars    = true,
        hideTargetBackground = true,
    },
})

local function isOurBar(bar)
    if not mod.db.onlyTheseBars then return true end
    return bar == PlayerFrameHealthBar
        or bar == PlayerFrameManaBar
        or bar == TargetFrameHealthBar
        or bar == TargetFrameManaBar
        or bar == PetFrameHealthBar
        or bar == PetFrameManaBar
end

-- Original sizes per FontString, captured before the first change so
-- OnDisable can put them back (the hooks themselves cannot be removed).
local origSizes = {}
local function remember(fs)
    if fs and origSizes[fs] == nil and fs.GetFont then
        local _, size = fs:GetFont()
        origSizes[fs] = size or false
    end
end
local function setBarSize(bar, size)
    if not bar then return end
    remember(bar.TextString or ns:SafeGetFontString(bar, "Text"))
    remember(bar.LeftText   or ns:SafeGetFontString(bar, "TextLeft"))
    remember(bar.RightText  or ns:SafeGetFontString(bar, "TextRight"))
    ns:SetBarTextFontSize(bar, size)
end

local function applyPetFeedbackFont()
    if not mod.active then return end
    local size = tonumber(mod.db.petFeedbackSize) or 11
    local fs = PetFrameFeedbackText
        or (PetFrame and (PetFrame.FeedbackText or PetFrame.feedbackText))
        or _G["PetFrameFeedbackText"]
    if not fs or not fs.GetFont or not fs.SetFont then return end
    local font, _, flags = fs:GetFont()
    if not font then return end
    remember(fs)
    fs:SetFont(font, size, flags)
end

local function applyAll()
    if not mod.active then return end
    local hs = mod.db.healthSize
    local ps = mod.db.powerSize

    setBarSize(PlayerFrameHealthBar, hs)
    setBarSize(PlayerFrameManaBar,   ps)
    setBarSize(TargetFrameHealthBar, hs)
    setBarSize(TargetFrameManaBar,   ps)
    setBarSize(PetFrameHealthBar,    hs)
    setBarSize(PetFrameManaBar,      ps)

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
    if not mod.active then return end
    if not mod.db.hideTargetBackground then return end
    if TargetFrameBackground then TargetFrameBackground:Hide() end
end

mod.applyAll = applyAll  -- exposed for slider live updates

local hooksInstalled = false
local function installHooks()
    if hooksInstalled or not hooksecurefunc then return end
    hooksInstalled = true

    if TextStatusBar_UpdateTextString then
        hooksecurefunc("TextStatusBar_UpdateTextString", function(bar)
            if not mod.active then return end
            if not bar or not isOurBar(bar) then return end
            if bar == PlayerFrameHealthBar or bar == TargetFrameHealthBar or bar == PetFrameHealthBar then
                setBarSize(bar, mod.db.healthSize)
            elseif bar == PlayerFrameManaBar or bar == TargetFrameManaBar or bar == PetFrameManaBar then
                setBarSize(bar, mod.db.powerSize)
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

-- named handlers so OnDisable can unregister them, and re-enable doesn't stack
-- duplicate anonymous closures (ns:RegisterEvent doesn't dedupe)
local function fbOnPEW()
    applyAll()
    hideTargetBackground()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() applyAll(); hideTargetBackground() end)
        C_Timer.After(1, function() applyAll(); hideTargetBackground() end)
    end
end
local function fbOnTarget() applyAll(); hideTargetBackground() end
local function fbOnPet() applyAll() end

function mod:OnEnable()
    installHooks()
    mod:RegisterEvent("PLAYER_ENTERING_WORLD", fbOnPEW)
    mod:RegisterEvent("PLAYER_TARGET_CHANGED", fbOnTarget)
    mod:RegisterEvent("UNIT_PET", fbOnPet)
    applyAll()
    hideTargetBackground()
end

function mod:OnDisable()
    for fs, size in pairs(origSizes) do
        if size and fs.GetFont then
            local font, _, flags = fs:GetFont()
            if font then fs:SetFont(font, size, flags) end
        end
    end
    if TargetFrameBackground then TargetFrameBackground:Show() end
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Font Sizes"] },
        {
            type = "slider", label = L["Health Bar Text"],
            min = 6, max = 24, step = 1,
            tooltip = L["Font size on health bars (Player/Target/Pet)."],
            get = function() return mod.db.healthSize end,
            set = function(_, v) mod.db.healthSize = v; applyAll() end,
        },
        {
            type = "slider", label = L["Power Bar Text"],
            min = 6, max = 24, step = 1,
            tooltip = L["Font size on mana/power bars."],
            get = function() return mod.db.powerSize end,
            set = function(_, v) mod.db.powerSize = v; applyAll() end,
        },
        {
            type = "slider", label = L["Pet Combat Feedback Text"],
            min = 6, max = 24, step = 1,
            tooltip = L["Font size for 'Damage', 'Dodge', 'Miss' on the pet."],
            get = function() return mod.db.petFeedbackSize end,
            set = function(_, v) mod.db.petFeedbackSize = v; applyAll() end,
        },
        { type = "spacer" },
        { type = "header", text = L["Behavior"] },
        {
            type = "checkbox", label = L["Only affect Player/Target/Pet bars"],
            tooltip = L["If off: all TextStatusBars in the UI are overridden with the sizes above (may interfere with other addons)."],
            get = function() return mod.db.onlyTheseBars end,
            set = function(_, v) mod.db.onlyTheseBars = v; applyAll() end,
        },
        {
            type = "checkbox", label = L["Hide TargetFrame background"],
            tooltip = L["Permanently hides the dark background element of the TargetFrame."],
            get = function() return mod.db.hideTargetBackground end,
            set = function(_, v)
                mod.db.hideTargetBackground = v
                if v then hideTargetBackground()
                elseif TargetFrameBackground then TargetFrameBackground:Show() end
            end,
        },
    }
end
