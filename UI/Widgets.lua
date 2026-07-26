-- VuloClassicUI / UI / Widgets: toggle switches, sliders, dropdowns, headers, buttons, editboxes.
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local L = ns.L

local FONT_PATH = "Interface\\AddOns\\VuloClassicUI\\Media\\Fonts\\Expressway.TTF"
UI.FONT_PATH = FONT_PATH

local MASK_ROUNDED = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\csquare_mask.tga"
local MASK_CIRCLE  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\circle_mask.tga"

-- Strips "(...)" hints from labels and dropdown values; the full text stays in the tooltip.
function UI.StripParens(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("%s*%b()", ""):gsub("%s+$", ""))
end
local clean = UI.StripParens

function UI.Font(fs, size, flags)
    fs:SetFont(FONT_PATH, size or 12, flags or "")
    return fs
end

-- SetGradient(tex, orient, ...): first color is bottom/left, second is top/right.
function UI.SetGradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    if tex.SetGradient and CreateColor then
        tex:SetGradient(orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    elseif tex.SetGradientAlpha then
        tex:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2)
    else
        tex:SetColorTexture((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, ((a1 or 1) + (a2 or 1)) / 2)
    end
end

-- The dark "x" close button in a window's top-right corner (bags, bank, guild bank).
function UI:CreateCloseX(f, onClick)
    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -7)
    local cx = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cx:SetPoint("CENTER"); cx:SetText("x"); cx:SetTextColor(0.7, 0.7, 0.75)
    close:SetScript("OnEnter", function() cx:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b) end)
    close:SetScript("OnLeave", function() cx:SetTextColor(0.7, 0.7, 0.75) end)
    close:SetScript("OnClick", onClick)
    return close
end

-- Dark search box with magnifier icon and accent border while focused.
-- opts: width (default 120), onText(self). Caller anchors the box.
function UI:CreateSearchBox(parent, opts)
    opts = opts or {}
    local sb = CreateFrame("EditBox", nil, parent)
    sb:SetAutoFocus(false)
    sb:SetSize(opts.width or 120, 18)
    sb:SetFont(FONT_PATH, 11, "")
    sb:SetMaxLetters(40)
    sb:SetTextInsets(22, 8, 0, 0)
    sb:SetTextColor(0.9, 0.9, 0.95)
    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sb); bg:SetColorTexture(0.04, 0.04, 0.055, 0.95)
    local icon = sb:CreateTexture(nil, "OVERLAY")
    icon:SetSize(11, 11)
    icon:SetPoint("LEFT", sb, "LEFT", 6, 0)
    icon:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\fixinspect.tga")
    icon:SetVertexColor(0.55, 0.55, 0.62)
    local border = CreateFrame("Frame", nil, sb, BackdropTemplateMixin and "BackdropTemplate")
    border:SetAllPoints(sb)
    if border.SetBackdrop then
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        border:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    end
    sb:SetScript("OnEditFocusGained", function()
        if border.SetBackdropBorderColor then border:SetBackdropBorderColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1) end
    end)
    sb:SetScript("OnEditFocusLost", function()
        if border.SetBackdropBorderColor then border:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1) end
    end)
    sb:SetScript("OnTextChanged", opts.onText)
    sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    sb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    return sb
end

function UI:CreateShadow(frame)
    if frame._vcShadow then return end
    frame._vcShadow = {}
    local layers = { { 1, 0.45 }, { 3, 0.28 }, { 5, 0.15 }, { 7, 0.07 } }
    for i, l in ipairs(layers) do
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8 + (i - 1))
        t:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -l[1],  l[1])
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  l[1], -l[1])
        t:SetColorTexture(0, 0, 0, l[2])
        frame._vcShadow[i] = t
    end
end

local function setColorBG(frame, r, g, b, a, drawLayer)
    local tex = frame:CreateTexture(nil, drawLayer or "BACKGROUND")
    tex:SetAllPoints(frame)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

UI.SetColorBG = setColorBG

-- Restyles a ScrollFrame built from UIPanelScrollFrameTemplate.
function UI.StyleScrollbar(scrollFrame)
    if not scrollFrame then return end

    -- API compat: the scrollbar is a property, a global by name, or an unnamed child
    local sb = scrollFrame.ScrollBar
    if not sb then
        local sfName = scrollFrame.GetName and scrollFrame:GetName()
        if sfName then sb = _G[sfName .. "ScrollBar"] end
    end
    if not sb then
        for _, child in ipairs({ scrollFrame:GetChildren() }) do
            if child.SetThumbTexture then sb = child; break end
        end
    end
    if not sb then return end

    local function findChild(parent, suffix)
        local pName = parent.GetName and parent:GetName()
        if pName then
            local g = _G[pName .. suffix]
            if g then return g end
        end
        return nil
    end
    local upBtn   = sb.ScrollUpButton   or findChild(sb, "ScrollUpButton")
    local downBtn = sb.ScrollDownButton or findChild(sb, "ScrollDownButton")
    if upBtn   then upBtn:Hide();   upBtn:SetHeight(0.001)   end
    if downBtn then downBtn:Hide(); downBtn:SetHeight(0.001) end

    for _, region in ipairs({ sb:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetTexture(nil)
        end
    end

    if not sb._vcTrack then
        local track = sb:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("TOP",    sb, "TOP",    0, 0)
        track:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
        track:SetWidth(4)
        track:SetColorTexture(0.10, 0.10, 0.13, 1)
        sb._vcTrack = track
    end

    local thumb = sb:GetThumbTexture()
    if thumb then
        thumb:SetTexture(nil)
        thumb:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        thumb:SetSize(6, 36)
    end

    sb:SetWidth(8)
end

-- Installed once and reading the live _vcConfig: pooled widgets would otherwise stack hooks.
local function tooltipShow(self)
    local cfg = self._vcConfig
    local text = cfg and cfg.tooltip
    if not text then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end
local function tooltipHide() GameTooltip:Hide() end

local function attachTooltip(frame)
    frame:SetScript("OnEnter", tooltipShow)
    frame:SetScript("OnLeave", tooltipHide)
end

function UI:StyleBackdrop(frame, opts)
    opts = opts or {}
    local bgColor    = opts.bg     or ns.COLORS.bg
    local borderRGB  = opts.border or ns.COLORS.border

    if not frame._vcBG then
        frame._vcBG = frame:CreateTexture(nil, "BACKGROUND")
        frame._vcBG:SetAllPoints(frame)
    end
    frame._vcBG:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a or 1)

    if not frame._vcBorders then
        frame._vcBorders = {}
        for i = 1, 4 do
            local b = frame:CreateTexture(nil, "BORDER")
            b:SetColorTexture(borderRGB.r, borderRGB.g, borderRGB.b, borderRGB.a or 1)
            frame._vcBorders[i] = b
        end
        local t, b, l, r = unpack(frame._vcBorders)
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        t:SetHeight(1)
        b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        b:SetHeight(1)
        l:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        l:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        l:SetWidth(1)
        r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        r:SetWidth(1)
    end
    for _, b in ipairs(frame._vcBorders) do
        b:SetColorTexture(borderRGB.r, borderRGB.g, borderRGB.b, borderRGB.a or 1)
    end
end

-- Header item: { text, subtitle? }
local function headerSetup(f, item)
    f._label:SetText(string.upper(clean(item.text) or ""))
    if item.subtitle and item.subtitle ~= "" then
        f._sub:SetText(item.subtitle)
        f._sub:Show()
    else
        f._sub:SetText("")
        f._sub:Hide()
    end
end

function UI:CreateHeader(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(480, 22)

    local tick = f:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 3)
    tick:SetSize(3, 12)
    tick:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)

    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("BOTTOMLEFT", tick, "BOTTOMRIGHT", 7, -1)
    UI.Font(fs, 11)
    fs:SetTextColor(0.62, 0.60, 0.70)
    fs:SetJustifyH("LEFT")
    f._label = fs

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    UI.Font(sub, 10)
    sub:SetTextColor(0.40, 0.40, 0.48)
    sub:Hide()
    f._sub = sub

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 0)
    line:SetHeight(1)
    UI.SetGradient(line, "HORIZONTAL",
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.40,
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.0)

    f._vcType  = "header"
    f._vcSetup = headerSetup
    headerSetup(f, { text = text })
    return f
end

-- Desc item: { text }. Wrapped in a frame because bare regions cannot be pooled across parents.
local function descSetup(f, item)
    f._fs:SetText(item.text or "")
end

function UI:CreateDescription(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(480, 20)

    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(fs, 11)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    local c = ns.COLORS.textDim
    fs:SetTextColor(c.r, c.g, c.b)
    fs:SetJustifyH("LEFT")
    f._fs = fs

    -- width drives the wrap; the frame then adopts the wrapped text height
    function f:SetDescWidth(w)
        self._fs:SetWidth(w)
        local _, h = self._fs:GetSize()
        self:SetSize(w, math.max(18, (h or 18)))
    end
    function f:GetDescHeight()
        local _, h = self._fs:GetSize()
        return h or 18
    end

    f._vcType  = "desc"
    f._vcSetup = descSetup
    descSetup(f, { text = text })
    return f
end

-- Collapsible header: CreateCollapsibleHeader(parent, text, expanded, onClick)
local function collapsibleSetup(b, title, expanded, onClick)
    b._label:SetText(string.upper(title or ""))
    b._label:SetTextColor(0.92, 0.90, 0.96)
    if expanded then
        b._chevron:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    else
        b._chevron:SetVertexColor(0.6, 0.6, 0.68)
    end
    b._vcOnClick = onClick
end

function UI:CreateCollapsibleHeader(parent, text, expanded, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(480, 24)

    local box = b:CreateTexture(nil, "ARTWORK")
    box:SetSize(14, 14)
    box:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 4)
    box:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\gear.tga")
    box:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    b._chevron = box

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 1)
    UI.Font(fs, 12)
    b._label = fs

    local line = b:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -10, 0)
    line:SetHeight(1)
    UI.SetGradient(line, "HORIZONTAL",
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.40,
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.0)

    b:SetScript("OnClick", function(self) if self._vcOnClick then self._vcOnClick() end end)
    b:SetScript("OnEnter", function(self) self._label:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function(self) self._label:SetTextColor(0.92, 0.90, 0.96) end)

    b._vcType  = "collapsible"
    b._vcSetup = collapsibleSetup
    collapsibleSetup(b, text, expanded, onClick)
    return b
end

-- Toggle config: { label, tooltip?, get, set, width?, style = "eye"? }
local TOGGLE_W, TOGGLE_H = 36, 18
local EYE_ON  = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\eye.tga"
local EYE_OFF = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\eye_off.tga"

local function setTrackColor(container, r, g, b)
    for _, t in ipairs(container._trackParts) do t:SetColorTexture(r, g, b, 1) end
end

local function toggleRefresh(container)
    local cfg, btn = container._vcConfig, container._switch
    if not cfg then return end
    local state = cfg.get(btn) and true or false

    if container._eye then
        container._eye:SetTexture(state and EYE_ON or EYE_OFF)
        if state then
            container._eye:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        else
            container._eye:SetVertexColor(0.45, 0.45, 0.50, 1)
        end
        return
    end

    local knob = container._knob
    if state then
        setTrackColor(container, ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        knob:SetColorTexture(1, 1, 1, 1)
        knob:ClearAllPoints()
        knob:SetPoint("RIGHT", btn, "RIGHT", -3, 0)
    else
        setTrackColor(container, ns.COLORS.toggleOff.r, ns.COLORS.toggleOff.g, ns.COLORS.toggleOff.b)
        knob:SetColorTexture(0.72, 0.72, 0.78, 1)
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", btn, "LEFT", 3, 0)
    end
end

local function toggleFlip(container)
    local cfg = container._vcConfig
    if not cfg then return end
    local newState = not (cfg.get(container._switch) and true or false)
    cfg.set(container._switch, newState)
    toggleRefresh(container)
end

local function toggleSetup(container, config)
    container._vcConfig = config
    local label = container._label
    label:SetText(clean(config.label) or "")

    if config.width then
        container:SetSize(config.width, 22)
    else
        local labelW = label:GetStringWidth() or 0
        container:SetSize(math.max(labelW + 12 + TOGGLE_W, 90), 22)
    end
    toggleRefresh(container)
end

function UI:CreateToggle(parent, config)
    local container = CreateFrame("Frame", nil, parent)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(label, 12)
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    label:SetTextColor(0.95, 0.95, 0.97)

    local btn = CreateFrame("Button", nil, container)
    btn:SetSize(TOGGLE_W, TOGGLE_H)
    btn:SetPoint("RIGHT", container, "RIGHT", 0, 0)

    label:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    container._switch = btn
    container._label  = label

    if config.style == "eye" then
        btn:SetSize(22, 16)
        local eye = btn:CreateTexture(nil, "ARTWORK")
        eye:SetPoint("CENTER", btn, "CENTER", 0, 0)
        eye:SetSize(22, 16)
        container._eye = eye
    else
        local track = btn:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints(btn)
        track:SetColorTexture(ns.COLORS.toggleOff.r, ns.COLORS.toggleOff.g, ns.COLORS.toggleOff.b, 1)
        container._trackParts = { track }

        local borderColor = ns.COLORS.borderDark or ns.COLORS.border
        for _, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local bd = btn:CreateTexture(nil, "BORDER")
            bd:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
            if s == "TOP" or s == "BOTTOM" then
                bd:SetPoint(s .. "LEFT"); bd:SetPoint(s .. "RIGHT"); bd:SetHeight(1)
            else
                bd:SetPoint("TOP" .. s); bd:SetPoint("BOTTOM" .. s); bd:SetWidth(1)
            end
        end

        local knobShadow = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        knobShadow:SetSize(TOGGLE_H - 4, TOGGLE_H - 4)
        knobShadow:SetColorTexture(0, 0, 0, 0.30)

        local knob = btn:CreateTexture(nil, "ARTWORK", nil, 2)
        knob:SetSize(TOGGLE_H - 6, TOGGLE_H - 6)
        knob:SetColorTexture(1, 1, 1, 1)
        knobShadow:SetPoint("CENTER", knob, "CENTER", 0, 0)

        container._knob = knob
    end

    btn:SetScript("OnClick", function(self) toggleFlip(self:GetParent()) end)

    container:EnableMouse(true)
    container:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then toggleFlip(self) end
    end)
    attachTooltip(container)

    -- Separate pool key per style: the eye variant is built at construction and
    -- cannot be turned back into a switch, so the two must never be interchanged.
    container._vcType   = (config.style == "eye") and "toggle_eye" or "toggle"
    container._vcSetup  = toggleSetup
    container._refresh  = function() toggleRefresh(container) end
    toggleSetup(container, config)
    return container
end

-- Slider config: { label, tooltip?, min, max, step, get, set, width? }
-- Rounds a flat colour texture with one of the bundled masks. Turning texel
-- snapping off matters as much as the mask: with it on, small rounded art is
-- snapped hard onto the pixel grid and the curve comes out visibly stepped.
local function roundTexture(owner, tex, maskFile)
    if not (owner and tex and owner.CreateMaskTexture and tex.AddMaskTexture) then return end
    local m = owner:CreateMaskTexture()
    m:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(tex)          -- tracks the fill as it grows
    tex:AddMaskTexture(m)
    if tex.SetSnapToPixelGrid   then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    return m
end

local function sliderUpdateFill(s, v)
    local sMin, sMax = s._min or 0, s._max or 100
    local frac = 0
    if sMax > sMin then frac = (v - sMin) / (sMax - sMin) end
    frac = math.max(0, math.min(1, frac))
    local w = (s._trackBg:GetWidth() or s:GetWidth() or 200) * frac
    s._trackFill:SetWidth(math.max(0.001, w))
end

local function sliderSetup(s, config)
    s._vcConfig = config
    s._min  = config.min or 0
    s._max  = config.max or 100
    s._step = config.step or 1

    -- SetMinMaxValues/SetValue fire OnValueChanged; a reconfigure must not call config.set()
    s._configuring = true
    s:SetWidth(config.width or 200)
    s:SetMinMaxValues(s._min, s._max)
    s:SetValueStep(s._step)
    if s.Text then s.Text:SetText(clean(config.label) or "") end
    local v = config.get(s) or s._min
    s:SetValue(v)
    s._valueText:SetText(string.format("%g", v))
    sliderUpdateFill(s, v)
    s._configuring = false

    -- re-fill next frame, once the track has its real width
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if s:IsShown() then sliderUpdateFill(s, s:GetValue() or s._min) end
        end)
    end
end

function UI:CreateSlider(parent, config)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetObeyStepOnDrag(true)

    if s.Low  then s.Low:SetText("") end
    if s.High then s.High:SetText("") end
    if s.Text then
        UI.Font(s.Text, 12)
        s.Text:SetTextColor(0.95, 0.95, 0.97)
    end

    local accent = ns.COLORS.accent
    local thumb  = s:GetThumbTexture()

    -- The template ships its own groove art, which sits under our flat track and
    -- reads as a second, misaligned bar. Drop it before we draw anything.
    for _, r in ipairs({ s:GetRegions() }) do
        if r ~= thumb and r.GetObjectType and r:GetObjectType() == "Texture" then
            r:SetTexture(nil)
        end
    end

    -- A 6px bar is only the drawing; the frame stays the grab target, and a few
    -- px of slack on top of that is the difference between precise and fiddly.
    s:SetHitRectInsets(0, 0, -3, -3)

    -- White at low alpha rather than a fixed grey: it stays hue-neutral, so the
    -- track keeps the same relationship to any panel colour behind it.
    local TRACK_IDLE, TRACK_HOVER = 0.16, 0.24
    local trackBg = s:CreateTexture(nil, "ARTWORK", nil, 1)
    trackBg:SetHeight(6)
    trackBg:SetPoint("LEFT", s, "LEFT", 2, 0)
    trackBg:SetPoint("RIGHT", s, "RIGHT", -2, 0)
    trackBg:SetColorTexture(1, 1, 1, TRACK_IDLE)
    roundTexture(s, trackBg, MASK_ROUNDED)

    -- Inner shadow along the top lip: reads as carved into the panel instead of
    -- laid on top of it. Two pixels is enough; more looks like a smudge.
    local trackShade = s:CreateTexture(nil, "ARTWORK", nil, 2)
    trackShade:SetPoint("TOPLEFT",  trackBg, "TOPLEFT",  0, 0)
    trackShade:SetPoint("TOPRIGHT", trackBg, "TOPRIGHT", 0, 0)
    trackShade:SetHeight(2)
    UI.SetGradient(trackShade, "VERTICAL", 0, 0, 0, 0, 0, 0, 0, 0.45)
    roundTexture(s, trackShade, MASK_ROUNDED)

    local trackFill = s:CreateTexture(nil, "ARTWORK", nil, 3)
    trackFill:SetHeight(6)
    trackFill:SetPoint("LEFT", trackBg, "LEFT", 0, 0)
    trackFill:SetColorTexture(accent.r, accent.g, accent.b, 0.95)
    roundTexture(s, trackFill, MASK_ROUNDED)

    -- One-pixel gloss on the fill's top edge; the classic glass cue. Inset by a
    -- pixel so it cannot poke out of the fill's rounded corners.
    local fillGloss = s:CreateTexture(nil, "ARTWORK", nil, 4)
    fillGloss:SetPoint("TOPLEFT",  trackFill, "TOPLEFT",   1, 0)
    fillGloss:SetPoint("TOPRIGHT", trackFill, "TOPRIGHT", -1, 0)
    fillGloss:SetHeight(1)
    fillGloss:SetColorTexture(1, 1, 1, 0.12)

    s._trackBg, s._trackFill = trackBg, trackFill
    s._updateFill = function(v) sliderUpdateFill(s, v) end

    -- Accent halo behind the knob, so it reads as a control rather than a blob.
    -- ~1.3x the knob; at 2x it stops looking deliberate and starts looking broken.
    local thumbGlow = s:CreateTexture(nil, "ARTWORK", nil, 5)
    thumbGlow:SetSize(20, 20)
    thumbGlow:SetColorTexture(accent.r, accent.g, accent.b, 0.5)
    roundTexture(s, thumbGlow, MASK_CIRCLE)
    thumbGlow:Hide()

    if thumb then
        -- Desaturated knob over a saturated fill separates on two channels at
        -- once, which holds up far better than brightness alone.
        thumb:SetColorTexture(0.97, 0.97, 1.0, 1)
        thumb:SetSize(15, 15)
        thumb:SetDrawLayer("OVERLAY")     -- keep it above the halo
        roundTexture(s, thumb, MASK_CIRCLE)
        thumbGlow:SetPoint("CENTER", thumb, "CENTER", 0, 0)
        thumbGlow:Show()
    end

    -- Eased hover, instant press. Current values live in upvalues so an
    -- interrupted fade continues from where it actually is rather than snapping
    -- back to a base value first.
    local GLOW_IDLE, GLOW_HOVER, GLOW_PRESS = 0.55, 0.9, 1.0
    local glowNow,  glowGoal  = GLOW_IDLE, GLOW_IDLE
    local trackNow, trackGoal = TRACK_IDLE, TRACK_IDLE
    local function paintState()
        thumbGlow:SetAlpha(glowNow)
        trackBg:SetColorTexture(1, 1, 1, trackNow)
    end
    local function fadeTick(self, elapsed)
        local k = math.min(1, (elapsed or 0) / 0.18 * 3)
        local settled = true
        if math.abs(glowGoal - glowNow) > 0.004 then
            glowNow = glowNow + (glowGoal - glowNow) * k; settled = false
        else glowNow = glowGoal end
        if math.abs(trackGoal - trackNow) > 0.003 then
            trackNow = trackNow + (trackGoal - trackNow) * k; settled = false
        else trackNow = trackGoal end
        paintState()
        if settled then self:SetScript("OnUpdate", nil) end
    end
    s._setSliderState = function(hovered, pressed)
        glowGoal  = pressed and GLOW_PRESS or (hovered and GLOW_HOVER or GLOW_IDLE)
        trackGoal = (hovered or pressed) and TRACK_HOVER or TRACK_IDLE
        if pressed then
            -- ease OUT of a press, never into it: a fading press feels laggy
            glowNow, trackNow = glowGoal, trackGoal
            s:SetScript("OnUpdate", nil)
            paintState()
        else
            s:SetScript("OnUpdate", fadeTick)
        end
    end
    paintState()
    s._thumbGlow = thumbGlow

    local function makeStepButton(label, dir)
        local b = CreateFrame("Button", nil, s)
        b:SetSize(16, 16)
        local border = b:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints(b)
        border:SetColorTexture(0.3, 0.3, 0.35, 1)
        roundTexture(b, border, MASK_ROUNDED)
        local fill = b:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(0.14, 0.14, 0.16, 1)
        roundTexture(b, fill, MASK_ROUNDED)
        local txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        UI.Font(txt, 12)
        txt:SetPoint("CENTER", b, "CENTER", 0, 1)
        txt:SetText(label)
        b:SetScript("OnEnter", function() border:SetColorTexture(accent.r, accent.g, accent.b, 1) end)
        b:SetScript("OnLeave", function() border:SetColorTexture(0.3, 0.3, 0.35, 1) end)
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function()
            local mult = IsShiftKeyDown() and 5 or 1
            s:SetValue(s:GetValue() + dir * (s._step or 1) * mult)
        end)
        return b
    end

    local minusBtn = makeStepButton("-", -1)
    minusBtn:SetPoint("LEFT", s, "RIGHT", 8, 0)

    local valueText = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(valueText, 11)
    valueText:SetPoint("LEFT", minusBtn, "RIGHT", 4, 0)
    valueText:SetWidth(36)
    valueText:SetJustifyH("CENTER")
    s._valueText = valueText

    local plusBtn = makeStepButton("+", 1)
    plusBtn:SetPoint("LEFT", valueText, "RIGHT", 4, 0)

    s:SetScript("OnValueChanged", function(self, v)
        local cfg = self._vcConfig
        if not cfg then return end
        if cfg.step and cfg.step >= 1 then
            v = math.floor(v + 0.5)
        end
        self._valueText:SetText(string.format("%g", v))
        sliderUpdateFill(self, v)
        if self._configuring then return end
        cfg.set(self, v)
    end)

    attachTooltip(s)
    -- hooked after attachTooltip so its own handlers can't displace these
    s:HookScript("OnEnter", function(self)
        if self._setSliderState then self._setSliderState(true, self._pressed) end
    end)
    s:HookScript("OnLeave", function(self)
        if self._setSliderState then self._setSliderState(false, self._pressed) end
    end)
    s:HookScript("OnMouseDown", function(self)
        self._pressed = true
        if self._setSliderState then self._setSliderState(true, true) end
    end)
    -- IsMouseOver decides the target, or letting go off-frame strands it bright
    s:HookScript("OnMouseUp", function(self)
        self._pressed = nil
        if self._setSliderState then self._setSliderState(self:IsMouseOver(), false) end
    end)

    s._vcType  = "slider"
    s._vcSetup = sliderSetup
    sliderSetup(s, config)
    return s
end

-- Dropdown config: { label?, tooltip?, values = { { text, value }, ... }, get, set, width? }
-- One popup frame is shared by all dropdowns; only one can be open at a time.
local activePopup

local function closeActivePopup()
    if activePopup and activePopup:IsShown() then
        activePopup:Hide()
        if activePopup._owner and activePopup._owner._setHovered then
            activePopup._owner._setHovered(false)
        end
        activePopup._owner = nil
    end
end

local function ensurePopupFrame()
    if activePopup then return activePopup end
    local p = CreateFrame("Frame", "VCDropdownPopup", UIParent)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetFrameLevel(200)
    p:EnableMouse(true)
    p:Hide()

    UI:CreateShadow(p)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(p)
    bg:SetColorTexture(0.07, 0.07, 0.09, 0.99)
    p._bg = bg

    local borders = {}
    for i = 1, 4 do
        local b = p:CreateTexture(nil, "BORDER")
        b:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        borders[i] = b
    end
    borders[1]:SetPoint("TOPLEFT", p, "TOPLEFT"); borders[1]:SetPoint("TOPRIGHT", p, "TOPRIGHT"); borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT"); borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", p, "TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT"); borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", p, "TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT"); borders[4]:SetWidth(1)

    p._items = {}

    p:SetScript("OnHide", function(self)
        if self._owner and self._owner._setHovered then
            self._owner._setHovered(false)
        end
        self._owner = nil
    end)

    tinsert(UISpecialFrames, "VCDropdownPopup")  -- ESC closes

    activePopup = p
    return p
end

local function openPopup(button, config)
    local p = ensurePopupFrame()
    p._owner = button

    local values = config.values or {}
    local itemHeight = 24
    local width  = button:GetWidth()
    local height = #values * itemHeight + 4

    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    p:SetSize(width, height)

    for _, item in ipairs(p._items) do item:Hide() end

    for i, opt in ipairs(values) do
        local item = p._items[i]
        if not item then
            item = CreateFrame("Button", nil, p)
            item:SetHeight(itemHeight)

            local hover = item:CreateTexture(nil, "BACKGROUND")
            hover:SetAllPoints(item)
            hover:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.25)
            hover:Hide()
            item._hover = hover

            local check = item:CreateTexture(nil, "OVERLAY")
            check:SetSize(6, 6)
            check:SetPoint("LEFT", item, "LEFT", 6, 0)
            check:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
            check:Hide()
            item._check = check

            local fs = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            UI.Font(fs, 12)
            fs:SetPoint("LEFT", item, "LEFT", 18, 0)
            fs:SetPoint("RIGHT", item, "RIGHT", -8, 0)
            fs:SetJustifyH("LEFT")
            item._text = fs

            item:SetScript("OnEnter", function(self) self._hover:Show() end)
            item:SetScript("OnLeave", function(self) self._hover:Hide() end)
            p._items[i] = item
        end

        item:ClearAllPoints()
        item:SetPoint("TOPLEFT",  p, "TOPLEFT",   2, -((i - 1) * itemHeight + 2))
        item:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -((i - 1) * itemHeight + 2))

        item._text:SetText(clean(L[opt.text]))
        if opt.value == config.get(button) then
            item._check:Show()
            item._text:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        else
            item._check:Hide()
            item._text:SetTextColor(0.88, 0.88, 0.90)
        end

        item:SetScript("OnClick", function()
            config.set(button, opt.value)
            if button._setText then button._setText(L[opt.text]) end
            closeActivePopup()
        end)

        item:Show()
    end

    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:Show()
end

-- The container is the row: SetWidth() on it reflows label and button.
local function dropdownSetup(container, config)
    container._vcConfig = config
    local btn, label = container._button, container._label
    btn:ClearAllPoints(); label:ClearAllPoints()
    if config.label then
        label:SetText(clean(config.label))
        label:Show()
        label:SetWidth(0)
        label:SetPoint("LEFT", container, "LEFT", 0, 0)
        btn:SetHeight(24)
        btn:SetPoint("LEFT", label, "RIGHT", 10, 0)
        btn:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        container:SetSize(config.width or 240, 28)
    else
        label:Hide()
        btn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        btn:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
        container:SetSize(config.width or 160, 26)
    end
    btn._refresh()
end

function UI:CreateDropdown(parent, config)
    local container = CreateFrame("Frame", nil, parent)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(label, 12)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(0.95, 0.95, 0.97)
    container._label = label

    local btn = CreateFrame("Button", nil, container)
    btn:SetHeight(24)
    container._button = btn

    -- same geometry StyleBackdrop draws; it keeps the four edges on the frame as
    -- _vcBorders, which is what the hover recolour below uses
    UI:StyleBackdrop(btn, { bg = { r = 0.06, g = 0.06, b = 0.08, a = 1 } })
    local borders = btn._vcBorders

    local valueText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(valueText, 12)
    valueText:SetPoint("LEFT",  btn, "LEFT",   8, 0)
    valueText:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    valueText:SetJustifyH("LEFT")
    valueText:SetWordWrap(false)

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    arrow:SetTexCoord(0.25, 0.75, 0.30, 0.80)
    arrow:SetVertexColor(0.7, 0.7, 0.75)

    local function setHovered(state)
        local c = state and ns.COLORS.accent or ns.COLORS.border
        for _, b in ipairs(borders) do
            b:SetColorTexture(c.r, c.g, c.b, 1)
        end
        if state then
            arrow:SetVertexColor(1, 1, 1)
        else
            arrow:SetVertexColor(0.7, 0.7, 0.75)
        end
    end
    btn._setHovered = setHovered

    local function setText(text) valueText:SetText(clean(text) or "") end
    btn._setText = setText

    local function refresh()
        local cfg = container._vcConfig
        if not cfg then return end
        local current = cfg.get(btn)
        for _, opt in ipairs(cfg.values or {}) do
            if opt.value == current then
                setText(L[opt.text])
                return
            end
        end
        setText(tostring(current or ""))
    end
    btn._refresh = refresh

    btn:SetScript("OnEnter", function(self)
        setHovered(true)
        local cfg = container._vcConfig
        if cfg and cfg.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(cfg.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if not (activePopup and activePopup:IsShown() and activePopup._owner == btn) then
            setHovered(false)
        end
    end)

    btn:SetScript("OnClick", function(self)
        if activePopup and activePopup:IsShown() and activePopup._owner == self then
            closeActivePopup()
        else
            closeActivePopup()
            openPopup(self, container._vcConfig or {})
            setHovered(true)
        end
    end)

    container._vcType  = "dropdown"
    container._vcSetup = dropdownSetup
    dropdownSetup(container, config)
    return container
end

-- EditBox config: { label?, tooltip?, get, set, numeric?, width?, editWidth?, commitOnFocusLost?, onEnter? }
local function editboxSetup(container, config)
    container._vcConfig = config
    local label, eb = container._labelFS, container._editBox
    eb:ClearAllPoints(); label:ClearAllPoints()
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)

    if config.label and config.label ~= "" then
        label:SetText(clean(config.label))
        label:Show()
        label:SetPoint("LEFT", container, "LEFT", 0, 0)
        local editW = config.editWidth or 130
        eb:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        eb:SetWidth(editW)
        label:SetPoint("RIGHT", eb, "LEFT", -10, 0)
        local labelW = label:GetStringWidth() or 80
        container:SetWidth(config.width or (labelW + 14 + editW))
    else
        label:Hide()
        eb:SetPoint("LEFT", container, "LEFT", 0, 0)
        eb:SetWidth(config.width or 160)
        container:SetWidth(config.width or 160)
    end

    eb:ClearFocus()
    eb:SetText(tostring(config.get(eb) or ""))
end

function UI:CreateEditBox(parent, config)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(26)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(label, 12)
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    label:SetTextColor(0.95, 0.95, 0.97)
    container._labelFS = label

    local eb = CreateFrame("EditBox", nil, container)
    eb:SetHeight(22)
    eb:SetAutoFocus(false)
    eb:SetFont(FONT_PATH, 12, "")
    eb:SetTextInsets(8, 8, 0, 0)
    container._editBox = eb

    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(eb)
    bg:SetColorTexture(0.06, 0.05, 0.10, 0.85)
    eb._bg = bg

    local borderColor = ns.COLORS.border or { r = 0.35, g = 0.25, b = 0.55, a = 1 }
    local borderFrame = CreateFrame("Frame", nil, eb,
        BackdropTemplateMixin and "BackdropTemplate")
    borderFrame:SetAllPoints(eb)
    if borderFrame.SetBackdrop then
        borderFrame:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        borderFrame:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a or 1)
    end
    eb._borderFrame = borderFrame

    eb:SetScript("OnEditFocusGained", function(self)
        if self._borderFrame and self._borderFrame.SetBackdropBorderColor then
            local c = ns.COLORS.accent
            self._borderFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        end
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        if self._borderFrame and self._borderFrame.SetBackdropBorderColor then
            self._borderFrame:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a or 1)
        end
        -- opt-in: an adjacent button steals focus before its OnClick, so commit here too
        local cfg = container._vcConfig
        if cfg and cfg.commitOnFocusLost then
            local v = self:GetText()
            if cfg.numeric then v = tonumber(v) end
            cfg.set(self, v)
        end
    end)

    eb:SetScript("OnEnterPressed", function(self)
        local cfg = container._vcConfig
        if not cfg then self:ClearFocus(); return end
        local v = self:GetText()
        if cfg.numeric then v = tonumber(v) end
        cfg.set(self, v)
        self:ClearFocus()
        if cfg.onEnter then cfg.onEnter(v) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    attachTooltip(container)
    container._vcType  = "editbox"
    container._vcSetup = editboxSetup
    editboxSetup(container, config)
    return container
end

-- Button config: { label, tooltip?, onClick, width?, height?, primary? }
local function buttonApplyIdle(b)
    local cfg = b._vcConfig
    if cfg and cfg.primary then
        local a = ns.COLORS.accent
        b._bg:SetColorTexture(0.13, 0.13, 0.16, 1)
        b._setBorder(a, 0.70)
        b._textFS:SetTextColor(a.r, a.g, a.b, 0.95)
    else
        b._bg:SetColorTexture(0.13, 0.13, 0.16, 1)
        b._setBorder(ns.COLORS.border)
        b._textFS:SetTextColor(0.95, 0.95, 0.97)
    end
end

local function buttonSetup(b, config)
    b._vcConfig = config
    b._textFS:SetText(clean(config.label) or "")
    local w = config.width or 120
    local tw = (b._textFS:GetStringWidth() or 0) + 36
    b:SetSize(math.max(w, tw), config.height or 26)
    buttonApplyIdle(b)
end

function UI:CreateButton(parent, config)
    local b = CreateFrame("Button", nil, parent)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    b._bg = bg

    local borderColor = ns.COLORS.border
    local borders = {}
    for i = 1, 4 do
        local bt = b:CreateTexture(nil, "BORDER")
        bt:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
        borders[i] = bt
    end
    borders[1]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[4]:SetWidth(1)

    b._setBorder = function(c, a)
        for _, bt in ipairs(borders) do bt:SetColorTexture(c.r, c.g, c.b, a or 1) end
    end

    local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(text, 12)
    text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b._textFS = text

    b:SetScript("OnEnter", function(self)
        local cfg = self._vcConfig
        if cfg and cfg.primary then
            local a = ns.COLORS.accent
            bg:SetColorTexture(a.r * 0.16, a.g * 0.16, a.b * 0.16, 1)
            self._setBorder(a, 1)
            self._textFS:SetTextColor(a.r, a.g, a.b, 1)
        else
            bg:SetColorTexture(0.19, 0.19, 0.23, 1)
            self._setBorder(ns.COLORS.accent, 0.8)
        end
        if cfg and cfg.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(cfg.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        buttonApplyIdle(self)
        GameTooltip:Hide()
    end)

    b:SetScript("OnMouseDown", function(self)
        self._textFS:SetPoint("CENTER", self, "CENTER", 0, -1)
    end)
    b:SetScript("OnMouseUp", function(self)
        self._textFS:SetPoint("CENTER", self, "CENTER", 0, 0)
    end)

    b:SetScript("OnClick", function(self)
        local cfg = self._vcConfig
        if cfg and cfg.onClick then cfg.onClick(self) end
    end)

    b._vcType  = "button"
    b._vcSetup = buttonSetup
    buttonSetup(b, config)
    return b
end

-- IconButton config: { icon = "up"/"down"/"left"/"right" or a texture path, tooltip?, onClick, width?, height?, iconInset? }
local ARROW_DIR = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\"
local BUILTIN_ICONS = {
    up    = { tex = ARROW_DIR .. "arrow_up.tga",    tc = {0, 1, 0, 1} },
    down  = { tex = ARROW_DIR .. "arrow_down.tga",  tc = {0, 1, 0, 1} },
    left  = { tex = ARROW_DIR .. "arrow_left.tga",  tc = {0, 1, 0, 1} },
    right = { tex = ARROW_DIR .. "arrow_right.tga", tc = {0, 1, 0, 1} },
}

local function iconButtonSetup(b, config)
    b._vcConfig = config
    b:SetSize(config.width or 24, config.height or 24)
    local icon = b._icon
    local inset = config.iconInset or 10
    icon:SetSize((config.width or 24) - inset, (config.height or 24) - inset)
    icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)

    local iconKey = config.icon
    local builtin = iconKey and BUILTIN_ICONS[iconKey]
    if builtin then
        icon:SetTexture(builtin.tex)
        icon:SetTexCoord(unpack(builtin.tc))
    else
        icon:SetTexCoord(0, 1, 0, 1)
        if iconKey then icon:SetTexture(iconKey) end
    end
end

function UI:CreateIconButton(parent, config)
    local b = CreateFrame("Button", nil, parent)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0.15, 0.15, 0.18, 1)

    local borderColor = ns.COLORS.border
    local borders = {}
    for i = 1, 4 do
        local bt = b:CreateTexture(nil, "BORDER")
        bt:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
        borders[i] = bt
    end
    borders[1]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[4]:SetWidth(1)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b._icon = icon

    b:SetScript("OnEnter", function(self)
        bg:SetColorTexture(0.22, 0.22, 0.26, 1)
        icon:SetVertexColor(1, 1, 1)
        local cfg = self._vcConfig
        if cfg and cfg.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(cfg.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(0.15, 0.15, 0.18, 1)
        icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
        local cfg = self._vcConfig
        if cfg and cfg.onClick then cfg.onClick(self) end
    end)

    b._vcType  = "iconbutton"
    b._vcSetup = iconButtonSetup
    iconButtonSetup(b, config)
    return b
end

-- PowerButton config: { size?, tooltip?, get() -> bool, set(bool) }
function UI:CreatePowerButton(parent, config)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(config.size or 14, config.size or 14)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    icon:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\power")
    b._icon = icon

    local function refresh()
        local on = config.get() and true or false
        if on then
            icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        else
            icon:SetVertexColor(0.4, 0.4, 0.4, 0.6)
        end
    end

    b:SetScript("OnClick", function()
        local newState = not (config.get() and true or false)
        config.set(newState)
        refresh()
    end)

    b:SetScript("OnEnter", function()
        icon:SetVertexColor(1, 1, 1, 1)
        if config.tooltip then
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(config.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        refresh()
        GameTooltip:Hide()
    end)

    refresh()
    b._refresh = refresh
    return b
end

-- ColorSwatch config: { label, get() -> {r,g,b} or {r=,g=,b=}, set(r,g,b), width? }
function UI:CreateColorSwatch(parent, config)
    local b = CreateFrame("Button", nil, parent)

    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(label, 12); label:SetTextColor(0.95, 0.95, 0.97)
    label:SetPoint("LEFT", b, "LEFT", 0, 0)
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)
    b._label = label

    local sw = CreateFrame("Button", nil, b)
    sw:SetSize(18, 18)
    sw:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    local border = sw:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); border:SetColorTexture(0, 0, 0, 0.8)
    local fill = sw:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
    b._fill = fill
    label:SetPoint("RIGHT", sw, "LEFT", -8, 0)

    local function curRGB()
        local cfg = b._vcConfig
        local c = cfg and cfg.get and cfg.get()
        if not c then return 1, 1, 1 end
        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1
    end
    local function refresh()
        local r, g, bl = curRGB(); fill:SetColorTexture(r, g, bl, 1)
    end
    local function open()
        local r, g, bl = curRGB()
        ns:ShowColorPicker({ r = r, g = g, b = bl, onChange = function(nr, ng, nb)
            local cfg = b._vcConfig
            if cfg and cfg.set then cfg.set(nr, ng, nb) end
            fill:SetColorTexture(nr, ng, nb, 1)
        end })
    end
    b:SetScript("OnClick", open)
    sw:SetScript("OnClick", open)
    sw:SetScript("OnEnter", function() border:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1) end)
    sw:SetScript("OnLeave", function() border:SetColorTexture(0, 0, 0, 0.8) end)

    b._refresh = refresh
    b._vcType  = "color"
    b._vcSetup = function(self, cfg)
        self._vcConfig = cfg
        self._label:SetText(clean(cfg.label) or "")
        if cfg.width then
            self:SetSize(cfg.width, 22)
        else
            self:SetSize(math.max((self._label:GetStringWidth() or 0) + 12 + 18, 120), 22)
        end
        refresh()
    end
    b._vcSetup(b, config)
    return b
end
