-- =========================================================
-- VuloClassicUI / UI / Widgets
-- EUI-inspired widgets: toggle switches, purple sliders, dropdowns,
-- section headers, buttons, editboxes.
-- =========================================================
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local L = ns.L

-- =========================================================
-- Design helpers: shared UI font, gradients, drop shadows
-- =========================================================
local FONT_PATH = "Interface\\AddOns\\VuloClassicUI\\Media\\Fonts\\Expressway.TTF"
UI.FONT_PATH = FONT_PATH

-- Rounded-corner masks (used for the pill toggle switch)
local MASK_ROUNDED = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\csquare_mask.tga"
local MASK_CIRCLE  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\circle_mask.tga"

-- Strip "(...)" hints from option chrome (labels, dropdown values) for a clean,
-- uncluttered look. The full text still lives in the help tooltip.
function UI.StripParens(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("%s*%b()", ""):gsub("%s+$", ""))
end
local clean = UI.StripParens

-- Apply the addon UI font to a FontString (or EditBox)
function UI.Font(fs, size, flags)
    fs:SetFont(FONT_PATH, size or 12, flags or "")
    return fs
end

-- Cross-client gradient on a texture.
-- (r1,g1,b1,a1) = bottom/left color, (r2,g2,b2,a2) = top/right color.
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

-- Soft drop shadow: layered translucent black rings around the frame
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

-- =========================================================
-- Helper: white 1px pixel as background texture
-- =========================================================

local function setColorBG(frame, r, g, b, a, drawLayer)
    local tex = frame:CreateTexture(nil, drawLayer or "BACKGROUND")
    tex:SetAllPoints(frame)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

UI.SetColorBG = setColorBG

-- =========================================================
-- Scrollbar in purple accent style
-- Works on ScrollFrames that use UIPanelScrollFrameTemplate.
-- =========================================================
function UI.StyleScrollbar(scrollFrame)
    if not scrollFrame then return end

    -- Find ScrollBar:
    --   1. Directly as property (Retail style)
    --   2. Via _G with name (if ScrollFrame is named)
    --   3. Via child iteration (if frame has no name)
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

    -- Hide arrow buttons at top/bottom
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

    -- Remove old track textures (yellow tooltip borders)
    for _, region in ipairs({ sb:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetTexture(nil)
        end
    end

    -- Draw new slim track
    if not sb._vcTrack then
        local track = sb:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("TOP",    sb, "TOP",    0, 0)
        track:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
        track:SetWidth(4)
        track:SetColorTexture(0.10, 0.10, 0.13, 1)
        sb._vcTrack = track
    end

    -- Tint thumb (the movable bar) purple
    local thumb = sb:GetThumbTexture()
    if thumb then
        thumb:SetTexture(nil)
        thumb:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        thumb:SetSize(6, 36)
    end

    sb:SetWidth(8)
end

-- =========================================================
-- Tooltip helper
-- Handlers are installed ONCE and read the LIVE config: option widgets
-- are pooled and reconfigured (frames are never garbage-collected), so
-- per-config HookScripts would stack up on every reuse.
-- =========================================================
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

-- =========================================================
-- Build a clean backdrop without tooltip border
-- =========================================================
function UI:StyleBackdrop(frame, opts)
    opts = opts or {}
    local bgColor    = opts.bg     or ns.COLORS.bg
    local borderRGB  = opts.border or ns.COLORS.border

    -- BG
    if not frame._vcBG then
        frame._vcBG = frame:CreateTexture(nil, "BACKGROUND")
        frame._vcBG:SetAllPoints(frame)
    end
    frame._vcBG:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a or 1)

    -- Border: 4 thin lines (top/bottom/left/right)
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

-- =========================================================
-- Header (section heading in EUI style: uppercase, dimmed)
-- =========================================================
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

    -- Small accent tick on the left
    local tick = f:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 3)
    tick:SetSize(3, 12)
    tick:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)

    -- Header label (uppercase, dimmed — section label, like the reference)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("BOTTOMLEFT", tick, "BOTTOMRIGHT", 7, -1)
    UI.Font(fs, 11)
    fs:SetTextColor(0.62, 0.60, 0.70)
    fs:SetJustifyH("LEFT")
    f._label = fs

    -- Optional muted subtitle hint after the label ("one per slot")
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    UI.Font(sub, 10)
    sub:SetTextColor(0.40, 0.40, 0.48)
    sub:Hide()
    f._sub = sub

    -- Thin accent underline spanning the row, fading out to the right
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

-- Description: a wrapper frame around the FontString so the widget can be
-- pooled like every other option widget (regions alone can't be re-pooled
-- cleanly across parents).
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

    -- Width drives the wrap; the frame then adopts the wrapped text height
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

-- Collapsible section header: gear ("more settings") + label + underline.
-- Whole row clickable; the gear lights up (accent) while expanded.
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

    -- Gear icon = "more settings"; tinted accent when the section is open
    local box = b:CreateTexture(nil, "ARTWORK")
    box:SetSize(14, 14)
    box:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 4)
    box:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\gear.tga")
    box:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    b._chevron = box

    -- Label
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 1)
    UI.Font(fs, 12)
    b._label = fs

    -- Accent underline fading out to the right
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

-- =========================================================
-- Toggle Switch (EUI style: switch left/right with purple accent)
-- =========================================================
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

    -- Eye variant: open eye = on (accent), closed eye = off (grey).
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

    -- Width: explicit, else size to content (label + switch). The two-column
    -- page layout overrides this via SetWidth, so a compact default keeps
    -- toggles inside group rows from eating the whole row.
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

    -- Label on the left
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(label, 12)
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    label:SetTextColor(0.95, 0.95, 0.97)

    -- Switch on the right (Button)
    local btn = CreateFrame("Button", nil, container)
    btn:SetSize(TOGGLE_W, TOGGLE_H)
    btn:SetPoint("RIGHT", container, "RIGHT", 0, 0)

    -- Constrain the label so it truncates instead of running under the switch
    label:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    container._switch = btn
    container._label  = label

    if config.style == "eye" then
        -- Eye variant: a single show/hide eye glyph instead of the switch.
        btn:SetSize(22, 16)
        local eye = btn:CreateTexture(nil, "ARTWORK")
        eye:SetPoint("CENTER", btn, "CENTER", 0, 0)
        eye:SetSize(22, 16)
        container._eye = eye
    else
        -- Rectangular track + thin border
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

        -- Square knob with a soft shadow
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

    -- Convenience: entire container is clickable
    container:EnableMouse(true)
    container:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then toggleFlip(self) end
    end)
    attachTooltip(container)

    container._vcType   = "toggle"
    container._vcSetup  = toggleSetup
    container._refresh  = function() toggleRefresh(container) end
    toggleSetup(container, config)
    return container
end

-- Old API compatibility: CreateCheckbox now returns a Toggle
function UI:CreateCheckbox(parent, config)
    return UI:CreateToggle(parent, config)
end

-- =========================================================
-- Slider (purple accent, value display on the right)
-- =========================================================
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

    -- Guard: SetMinMaxValues/SetValue fire OnValueChanged — during a
    -- (re)configure that must not write through config.set().
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

    -- Re-fill once the track has its real width (next frame)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if s:IsShown() then sliderUpdateFill(s, s:GetValue() or s._min) end
        end)
    end
end

function UI:CreateSlider(parent, config)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetObeyStepOnDrag(true)

    if s.Low  then s.Low:SetText("") end  -- hide min text (clean)
    if s.High then s.High:SetText("") end
    if s.Text then
        UI.Font(s.Text, 12)
        s.Text:SetTextColor(0.95, 0.95, 0.97)
    end

    local accent = ns.COLORS.accent

    -- Modern track: dark base bar + accent progress fill, drawn over the
    -- plain Blizzard template track. A slim white thumb sits on top.
    local trackBg = s:CreateTexture(nil, "ARTWORK", nil, 1)
    trackBg:SetHeight(4)
    trackBg:SetPoint("LEFT", s, "LEFT", 2, 0)
    trackBg:SetPoint("RIGHT", s, "RIGHT", -2, 0)
    trackBg:SetColorTexture(0.16, 0.16, 0.20, 1)

    local trackFill = s:CreateTexture(nil, "ARTWORK", nil, 2)
    trackFill:SetHeight(4)
    trackFill:SetPoint("LEFT", trackBg, "LEFT", 0, 0)
    trackFill:SetColorTexture(accent.r, accent.g, accent.b, 0.95)

    s._trackBg, s._trackFill = trackBg, trackFill
    s._updateFill = function(v) sliderUpdateFill(s, v) end

    -- Square accent thumb
    local thumb = s:GetThumbTexture()
    if thumb then
        thumb:SetColorTexture(0.95, 0.95, 1.0, 1)
        thumb:SetSize(14, 14)
    end

    -- Value display + clickable ± buttons (SHIFT = 5x step)
    local function makeStepButton(label, dir)
        local b = CreateFrame("Button", nil, s)
        b:SetSize(16, 16)
        local border = b:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints(b)
        border:SetColorTexture(0.3, 0.3, 0.35, 1)
        local fill = b:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(0.14, 0.14, 0.16, 1)
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
    s._vcType  = "slider"
    s._vcSetup = sliderSetup
    sliderSetup(s, config)
    return s
end

-- =========================================================
-- Dropdown (custom EUI-style widget, not UIDropDownMenu)
-- Layout: black background, purple border, V-arrow on the right, list expands downward
-- =========================================================

-- We share one popup frame across all dropdowns (only one open at a time)
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

    -- Drop shadow + background
    UI:CreateShadow(p)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(p)
    bg:SetColorTexture(0.07, 0.07, 0.09, 0.99)
    p._bg = bg

    -- Border (purple)
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

    -- OnHide: reset owner border
    p:SetScript("OnHide", function(self)
        if self._owner and self._owner._setHovered then
            self._owner._setHovered(false)
        end
        self._owner = nil
    end)

    -- ESC closes the popup
    tinsert(UISpecialFrames, "VCDropdownPopup")

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

    -- Recycle / hide old items
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

        item._text:SetText(clean(L[opt.text]))  -- translate + drop "(...)" hints
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

-- Inline layout: label on the LEFT, the dropdown button on the RIGHT (fixed
-- width). The container is the row -- SetWidth() on it reflows everything, so
-- the OptionsBuilder can drop it straight into a two-column grid.
local function dropdownSetup(container, config)
    container._vcConfig = config
    local btn, label = container._button, container._label
    btn:ClearAllPoints(); label:ClearAllPoints()
    if config.label then
        label:SetText(clean(config.label))
        label:Show()
        label:SetWidth(0)  -- auto-size to text
        label:SetPoint("LEFT", container, "LEFT", 0, 0)
        -- button fills the rest of the row up to the right edge (wide value box)
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

    -- Label on the left (always created; shown only when configured)
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(label, 12)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(0.95, 0.95, 0.97)
    container._label = label

    -- Actual button
    local btn = CreateFrame("Button", nil, container)
    btn:SetHeight(24)
    container._button = btn

    -- BG
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    bg:SetColorTexture(0.06, 0.06, 0.08, 1)

    -- Border (thin, switches to purple on hover/open)
    local borders = {}
    for i = 1, 4 do
        local b = btn:CreateTexture(nil, "BORDER")
        b:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
        borders[i] = b
    end
    borders[1]:SetPoint("TOPLEFT", btn, "TOPLEFT"); borders[1]:SetPoint("TOPRIGHT", btn, "TOPRIGHT"); borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT"); borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", btn, "TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT"); borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", btn, "TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT"); borders[4]:SetWidth(1)

    -- Current value text
    local valueText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(valueText, 12)
    valueText:SetPoint("LEFT",  btn, "LEFT",   8, 0)
    valueText:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    valueText:SetJustifyH("LEFT")
    valueText:SetWordWrap(false)  -- single line, truncate instead of wrapping

    -- V-arrow on the right
    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    arrow:SetTexCoord(0.25, 0.75, 0.30, 0.80)
    arrow:SetVertexColor(0.7, 0.7, 0.75)

    -- Border hover/open effect
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

-- =========================================================
-- EditBox
-- =========================================================
-- Inline: label LEFT, edit field RIGHT (fixed width). SetWidth() on the
-- container reflows it for the two-column grid.
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

    -- Label to the LEFT of the edit field (always created; hidden if unused)
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(label, 12)
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    label:SetTextColor(0.95, 0.95, 0.97)
    container._labelFS = label

    -- Edit field (rectangular, custom style — NO InputBoxTemplate)
    local eb = CreateFrame("EditBox", nil, container)
    eb:SetHeight(22)
    eb:SetAutoFocus(false)
    eb:SetFont(FONT_PATH, 12, "")
    eb:SetTextInsets(8, 8, 0, 0)  -- inner padding left/right
    container._editBox = eb

    -- Background (dark purple tinted)
    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(eb)
    bg:SetColorTexture(0.06, 0.05, 0.10, 0.85)
    eb._bg = bg

    -- Border (1px, accent purple)
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

    -- On focus: brighter purple border
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
        -- Commit the typed value on focus loss too, so clicking an adjacent
        -- button (which steals focus before its OnClick) sees the new value.
        -- Opt-in: setters with heavy rebuild side effects shouldn't fire here.
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
        if cfg.onEnter then cfg.onEnter(v) end   -- e.g. submit/add on Enter
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    attachTooltip(container)
    container._vcType  = "editbox"
    container._vcSetup = editboxSetup
    editboxSetup(container, config)
    return container
end

-- =========================================================
-- Button (clean, with accent hover)
-- =========================================================
local function buttonApplyIdle(b)
    local cfg = b._vcConfig
    if cfg and cfg.primary then
        b._bg:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        b._setBorder(ns.COLORS.accent)
        b._textFS:SetTextColor(1, 1, 1)
    else
        b._bg:SetColorTexture(0.13, 0.13, 0.16, 1)
        b._setBorder(ns.COLORS.border)
        b._textFS:SetTextColor(0.95, 0.95, 0.97)
    end
end

local function buttonSetup(b, config)
    b._vcConfig = config
    b._textFS:SetText(clean(config.label) or "")
    -- grow to fit the label with generous horizontal padding (text never
    -- crowds the border)
    local w = config.width or 120
    local tw = (b._textFS:GetStringWidth() or 0) + 36
    b:SetSize(math.max(w, tw), config.height or 26)
    buttonApplyIdle(b)
end

function UI:CreateButton(parent, config)
    local b = CreateFrame("Button", nil, parent)

    -- BG
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    b._bg = bg

    -- Border (thin)
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

    -- Text
    local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(text, 12)
    text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b._textFS = text

    -- Hover effect (accent border for secondary buttons)
    b:SetScript("OnEnter", function(self)
        local cfg = self._vcConfig
        if cfg and cfg.primary then
            bg:SetColorTexture(ns.COLORS.accent.r * 1.15, ns.COLORS.accent.g * 1.15, ns.COLORS.accent.b * 1.15, 1)
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

    -- Subtle press feedback: nudge the label 1px down
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

-- =========================================================
-- Icon button (texture instead of text label, e.g. arrows)
-- config.icon can be:
--   "up", "down", "left", "right" -> built-in Blizzard arrows
--   "Interface\\..."              -> any texture
-- =========================================================
-- Clean triangle arrows: one "Arrow-Up-Up" texture, flipped/rotated per direction.
-- tc form: {ULx,ULy, LLx,LLy, URx,URy, LRx,LRy} for rotations, or {l,r,t,b} for simple flips.
local BUILTIN_ICONS = {
    up    = { tex = "Interface\\Buttons\\Arrow-Up-Up", tc = {0, 1, 0, 1} },
    down  = { tex = "Interface\\Buttons\\Arrow-Up-Up", tc = {0, 1, 1, 0} },   -- vertical flip
    -- 90° rotations of the up arrow (8-value texcoord form)
    left  = { tex = "Interface\\Buttons\\Arrow-Up-Up", tc = {1,0, 0,0, 1,1, 0,1} },
    right = { tex = "Interface\\Buttons\\Arrow-Up-Up", tc = {0,1, 1,1, 0,0, 1,0} },
}

local function iconButtonSetup(b, config)
    b._vcConfig = config
    b:SetSize(config.width or 24, config.height or 24)
    local icon = b._icon
    local inset = config.iconInset or 10   -- smaller inset = larger glyph
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

    -- Background
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0.15, 0.15, 0.18, 1)

    -- Border (thin)
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

    -- Icon texture (slightly larger, centered)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b._icon = icon

    -- Hover
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

-- =========================================================
-- Power button (small toggle per sidebar entry)
-- =========================================================
function UI:CreatePowerButton(parent, config)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(config.size or 14, config.size or 14)

    -- Power icon (white pixels = visible, black = transparent thanks to alpha channel)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    icon:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\power")
    b._icon = icon

    local function refresh()
        local on = config.get() and true or false
        if on then
            -- Active: purple accent color
            icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        else
            -- Inactive: greyed out (dark grey, ~40% alpha)
            icon:SetVertexColor(0.4, 0.4, 0.4, 0.6)
        end
    end

    b:SetScript("OnClick", function()
        local newState = not (config.get() and true or false)
        config.set(newState)
        refresh()
    end)

    b:SetScript("OnEnter", function()
        -- Hover: brighter white
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
