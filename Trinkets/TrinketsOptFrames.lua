-- VuloClassicUI / Trinkets / OptFrames: TrinketsOpt.xml, in Lua.
--
-- Second of three. Same rules as TrinketsFrames.lua: every global name keeps its
-- spelling, OnLoad is called by hand because CreateFrame does not, and hidden
-- frames are hidden BEFORE an OnHide script can fire.
--
-- WHAT STAYED XML AND WHY
-- This file declared three virtual templates. TrinketsQueue.xml inherits two of
-- them (the tab twice, the check button three times), and a template defined in
-- Lua cannot be inherited by name -- the lesson from the first file, where
-- deleting a shared template produced nine "Couldn't find inherited node". Those
-- two moved to TrinketsTemplates.xml. The third, Trinkets_SmallButtonTemplate,
-- is used only here and is a factory function below.
--
-- WORTH KNOWING BEFORE CHANGING ANYTHING HERE
-- Modules/Trinkets.lua deliberately SUPPRESSES two of the frames this file
-- builds: the minimap button and Trinkets_OptFrame itself, both replaced by our
-- own options page. They are still built, because TrinketsQueue.xml parents its
-- second tab straight into Trinkets_OptFrame and the queue window is reached
-- through frames that live inside it.
local _, ns = ...

local BG = "Interface\\ChatFrame\\ChatFrameBackground"

-- <Gradient orientation="VERTICAL"><MinColor/><MaxColor/></Gradient>
-- Not UI.SetGradient: that helper replaces the texture with a plain white one,
-- and here the gradient tints an actual file.
local function gradient(tex, r1, g1, b1, a1, r2, g2, b2, a2)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("VERTICAL", CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    elseif tex.SetGradientAlpha then
        tex:SetGradientAlpha("VERTICAL", r1, g1, b1, a1, r2, g2, b2, a2)
    end
end

-- The inset background both panels carry: 4px in on every side.
local function insetBackground(parent, r1, g1, b1, a1, r2, g2, b2, a2)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(BG)
    t:SetPoint("TOPLEFT", 4, -4)
    t:SetPoint("BOTTOMRIGHT", -4, 4)
    gradient(t, r1, g1, b1, a1, r2, g2, b2, a2)
    return t
end

-- <Button name="Trinkets_SmallButtonTemplate" virtual="true">
local function makeSmallButton(name, parent)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(16, 16)
    b:SetScript("OnClick", function(self) Trinkets.SmallButton_OnClick(self) end)
    b:SetScript("OnEnter", function(self) Trinkets.OnTooltip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(0.608, 0.424, 1)
    hl:SetAllPoints(b)
    b:SetHighlightTexture(hl)
    return b
end

-- ---------------------------------------------------------------------------
-- <Button name="Trinkets_IconFrame"> -- the minimap button
-- ---------------------------------------------------------------------------
local icon = CreateFrame("Button", "Trinkets_IconFrame", Minimap)
icon:SetSize(32, 32)
icon:SetFrameStrata("MEDIUM")
icon:EnableMouse(true)
icon:SetMovable(true)
icon:SetToplevel(true)
icon:SetPoint("TOPLEFT")
icon:SetNormalTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\trinkets")
local iconPushed = icon:CreateTexture(nil, "ARTWORK")
iconPushed:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\trinkets")
iconPushed:SetVertexColor(0.65, 0.65, 0.65)
icon:SetPushedTexture(iconPushed)
local iconHL = icon:CreateTexture(nil, "HIGHLIGHT")
iconHL:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
iconHL:SetBlendMode("ADD")
iconHL:SetAllPoints(icon)
icon:SetHighlightTexture(iconHL)

icon:SetScript("OnEnter", function(self)
    Trinkets.OnTooltip(self, "Trinkets",
        (TrinketsOptions.DisableToggle == "ON")
            and "Click: toggle options\nDrag: move icon"
            or  "Left click: toggle trinkets\nRight click: toggle options\nDrag: move icon")
end)
icon:SetScript("OnLeave",     function() GameTooltip:Hide() end)
icon:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    Trinkets.StartTimer("DragMinimapButton")
end)
icon:SetScript("OnDragStop",  function(self)
    Trinkets.StopTimer("DragMinimapButton")
    self:UnlockHighlight()
end)
icon:SetScript("OnClick",     function(_, button) Trinkets.MinimapButton_OnClick(button) end)
-- the XML OnLoad
icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
icon:RegisterForDrag("LeftButton")

-- ---------------------------------------------------------------------------
-- <Frame name="Trinkets_OptFrame">
-- ---------------------------------------------------------------------------
local opt = CreateFrame("Frame", "Trinkets_OptFrame", UIParent)
opt:SetSize(300, 356)
opt:SetMovable(true)
opt:SetToplevel(true)
opt:SetClampedToScreen(true)
opt:Hide()
Mixin(opt, TrinketsBackdropTemplateMixin)
opt:SetScript("OnSizeChanged", opt.OnBackdropSizeChanged)
opt.backdropInfo = Trinkets_BACKDROP_16
opt:SetPoint("CENTER")

insetBackground(opt, 0.1, 0.1, 0.1, 0.5, 0.25, 0.25, 0.25, 1)

local title = opt:CreateFontString("Trinkets_Title", "OVERLAY", "GameFontHighlightSmall")
title:SetPoint("TOP", 0, -8)
title:SetTextColor(0.55, 0.55, 0.55)

local close = makeSmallButton("Trinkets_CloseButton", opt)
close:SetPoint("TOPRIGHT", -6, -6)
close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
close:SetDisabledTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Disabled")

local lock = makeSmallButton("Trinkets_LockButton", opt)
lock:SetPoint("TOPRIGHT", close, "TOPLEFT", -2, 0)
lock:SetNormalTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\unlockmode")
local lockPushed = lock:CreateTexture(nil, "ARTWORK")
lockPushed:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\unlockmode")
lockPushed:SetVertexColor(0.65, 0.65, 0.65)
lock:SetPushedTexture(lockPushed)

local tab1 = CreateFrame("Button", "Trinkets_Tab1", opt, "Trinkets_TabTemplate")
tab1:SetID(1)
tab1:SetText("Options")
tab1:SetPoint("TOPRIGHT", -6, -22)

-- ---------------------------------------------------------------------------
-- <Frame name="Trinkets_SubOptFrame"> -- the panel the options sit on
-- ---------------------------------------------------------------------------
local sub = CreateFrame("Frame", "Trinkets_SubOptFrame", opt)
sub:Hide()
Mixin(sub, TrinketsBackdropTemplateMixin)
sub:SetScript("OnSizeChanged", sub.OnBackdropSizeChanged)
sub.backdropInfo = Trinkets_BACKDROP_16
sub:SetPoint("TOPLEFT", 8, -50)
sub:SetPoint("BOTTOMRIGHT", -8, 8)

insetBackground(sub, 0.15, 0.15, 0.15, 1, 0.33, 0.33, 0.33, 1)

-- Every check button is one line below the one before it, with a small indent
-- step. Kept as a list so the chain reads the way it looked in the XML: the
-- x offset is the indent CHANGE, not an absolute column.
local CHECKS = {
    { "Locked",                  8, -8, "PARENT" },
    { "ShowIcon",                0,  4 },
    { "DisableToggle",          16,  4 },
    { "SquareMinimap",           0,  4 },
    { "CooldownCount",         -16,  4 },
    { "LargeCooldown",          16,  4 },
    { "CooldownCountBlizzard", -16,  4 },
    { "CooldownCountOmniCC",     0,  4 },
    { "ShowTooltips",            0,  4 },
    { "TooltipFollow",          16,  4 },
    { "TinyTooltips",            0,  4 },
    { "ShowHotKeys",           -16,  4 },
    { "StopOnSwap",              0,  4 },
    -- Trinkets_OptRedRange sat here and is commented out in the XML. Left out
    -- rather than carried over dead: the option itself still exists in the
    -- settings table, it simply has no row.
    { "HidePetBattle",           0,  4 },
}

local prev
for _, c in ipairs(CHECKS) do
    local name, dx, dy, anchor = "Trinkets_Opt" .. c[1], c[2], c[3], c[4]
    local b = CreateFrame("CheckButton", name, sub, "Trinkets_CheckButtonTemplate")
    if anchor == "PARENT" then
        b:SetPoint("TOPLEFT", dx, dy)
    else
        b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", dx, dy)
    end
    prev = b
end

-- Second column, hung off the panel's TOP rather than its TOPLEFT.
local COLUMN2 = {
    "KeepDocked", "KeepOpen", "MenuOnShift", "MenuOnRight",
    "Notify", "NotifyThirty", "NotifyChatAlso", "SetColumns",
}
prev = nil
for _, key in ipairs(COLUMN2) do
    local b = CreateFrame("CheckButton", "Trinkets_Opt" .. key, sub, "Trinkets_CheckButtonTemplate")
    if prev then
        b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 4)
    else
        b:SetPoint("TOPLEFT", sub, "TOP", 0, -8)
    end
    prev = b
end

-- ---------------------------------------------------------------------------
-- The three sliders.
--
-- EnableMouseWheel is set explicitly. The XML declared an OnMouseWheel handler
-- without the matching attribute, which is the shape a handler takes when it
-- has never actually fired. Turning it on can only add the behaviour the
-- handler was written for.
-- ---------------------------------------------------------------------------
local function makeSlider(name, min, max, step, default, textName, textValue)
    local s = CreateFrame("Slider", name, sub)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(104, 17)
    s:EnableMouse(true)
    s:EnableMouseWheel(true)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetHitRectInsets(0, 0, -5, -5)
    Mixin(s, TrinketsBackdropTemplateMixin)
    s:SetScript("OnSizeChanged", s.OnBackdropSizeChanged)
    s.backdropInfo = Trinkets_SLIDER_BACKDROP

    local thumb = s:CreateTexture(name .. "Thumb", "ARTWORK")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(32, 32)
    s:SetThumbTexture(thumb)

    local fs = s:CreateFontString(textName, "ARTWORK", "GameFontHighlightSmall")
    fs:SetText(textValue)

    s:SetScript("OnMouseWheel", function(self, delta) Trinkets.SliderOnMouseWheel(self, delta) end)
    s:OnBackdropLoaded()
    s:SetValue(default)
    return s, fs
end

local colSlider, colText = makeSlider(
    "Trinkets_OptColumnsSlider", 1, 30, 1, 4,
    "Trinkets_OptColumnsSliderText", "5 trinkets")
colSlider:SetPoint("TOPLEFT", _G.Trinkets_OptSetColumns, "BOTTOMLEFT", 16, 4)
colText:SetPoint("LEFT", _G.Trinkets_OptSetColumnsText, "RIGHT", 0, 0)
colSlider:SetScript("OnValueChanged", function(self, value)
    Trinkets.OptColumnsSlider_OnValueChanged(self, value)
end)

local mainSlider, mainText = makeSlider(
    "Trinkets_OptMainScaleSlider", 0.2, 2.5, 0.01, 1.0,
    "Trinkets_OptMainScaleSliderText", "Main Scale: 1.0")
mainSlider:SetPoint("TOPLEFT", _G.Trinkets_OptSetColumns, "BOTTOMLEFT", 16, -28)
mainText:SetPoint("TOPLEFT", _G.Trinkets_OptSetColumnsText, "BOTTOMLEFT", 0, -24)
mainSlider:SetScript("OnValueChanged", function(self, value)
    Trinkets.OptMainScaleSlider_OnValueChanged(self, value)
end)

local menuSlider, menuText = makeSlider(
    "Trinkets_OptMenuScaleSlider", 0.2, 2.5, 0.01, 1.0,
    "Trinkets_OptMenuScaleSliderText", "Menu Scale: 1.0")
menuSlider:SetPoint("TOPLEFT", mainSlider, "BOTTOMLEFT", 0, -16)
menuText:SetPoint("TOPLEFT", mainText, "BOTTOMLEFT", 0, -22)
menuSlider:SetScript("OnValueChanged", function(self, value)
    Trinkets.OptMenuScaleSlider_OnValueChanged(self, value)
end)

-- ---------------------------------------------------------------------------
-- OnLoad, children before parents, and the window's own scripts last.
-- ---------------------------------------------------------------------------
sub:OnBackdropLoaded()
opt:OnBackdropLoaded()

opt:SetScript("OnMouseDown", function(self) self:StartMoving() end)
opt:SetScript("OnMouseUp",   function(self) self:StopMovingOrSizing() end)
opt:SetScript("OnShow",      function() Trinkets.OptFrame_OnShow() end)
