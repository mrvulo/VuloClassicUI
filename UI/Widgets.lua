-- =========================================================
-- VuloClassicUI / UI / Widgets
-- EUI-inspired widgets: toggle switches, purple sliders, dropdowns,
-- section headers, buttons, editboxes.
-- =========================================================
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

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
-- =========================================================
local function attachTooltip(frame, text)
    if not text then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
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
function UI:CreateHeader(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(480, 22)

    -- Small accent tick on the left
    local tick = f:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 3)
    tick:SetSize(3, 12)
    tick:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)

    -- Header label (uppercase, bright)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("BOTTOMLEFT", tick, "BOTTOMRIGHT", 7, -1)
    fs:SetText(string.upper(text or ""))
    fs:SetTextColor(0.92, 0.90, 0.96)
    fs:SetJustifyH("LEFT")
    f._label = fs

    -- Thin accent underline spanning the row, fading to the right
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 0)
    line:SetHeight(1)
    line:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.22)

    return f
end

function UI:CreateDescription(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetText(text or "")
    local c = ns.COLORS.textDim
    fs:SetTextColor(c.r, c.g, c.b)
    fs:SetJustifyH("LEFT")
    return fs
end

-- =========================================================
-- Toggle Switch (EUI style: switch left/right with purple accent)
-- =========================================================
function UI:CreateToggle(parent, config)
    local container = CreateFrame("Frame", nil, parent)

    -- Label on the left
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetText(config.label or "")
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    label:SetTextColor(1, 1, 1)

    -- Switch on the right (Button)
    local switchW, switchH = 36, 18
    local btn = CreateFrame("Button", nil, container)
    btn:SetSize(switchW, switchH)
    btn:SetPoint("RIGHT", container, "RIGHT", 0, 0)

    -- Constrain the label so it truncates instead of running under the switch
    label:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    -- Container width: explicitly set, or fixed at 360 so switches end up in one column
    -- (labels of different lengths would otherwise shift the switch X position)
    local explicitW = config.width
    if explicitW then
        container:SetSize(explicitW, 22)
    else
        local labelW = label:GetStringWidth() or 0
        local needed = labelW + 16 + switchW
        container:SetSize(math.max(needed, 360), 22)
    end

    -- BG track
    local track = btn:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(btn)
    track:SetColorTexture(ns.COLORS.toggleOff.r, ns.COLORS.toggleOff.g, ns.COLORS.toggleOff.b, 1)

    -- Knob
    local knob = btn:CreateTexture(nil, "ARTWORK")
    knob:SetSize(switchH - 4, switchH - 4)
    knob:SetColorTexture(1, 1, 1, 1)

    -- Border (very thin)
    local borderColor = ns.COLORS.border
    local borders = {}
    for i = 1, 4 do
        local b = btn:CreateTexture(nil, "BORDER")
        b:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
        borders[i] = b
    end
    borders[1]:SetPoint("TOPLEFT", btn, "TOPLEFT"); borders[1]:SetPoint("TOPRIGHT", btn, "TOPRIGHT"); borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT"); borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", btn, "TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT"); borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", btn, "TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT"); borders[4]:SetWidth(1)

    local function refresh()
        local state = config.get(btn) and true or false
        if state then
            track:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
            knob:ClearAllPoints()
            knob:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        else
            track:SetColorTexture(ns.COLORS.toggleOff.r, ns.COLORS.toggleOff.g, ns.COLORS.toggleOff.b, 1)
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", btn, "LEFT", 2, 0)
        end
    end

    btn:SetScript("OnClick", function()
        local newState = not (config.get(btn) and true or false)
        config.set(btn, newState)
        refresh()
    end)

    -- Convenience: entire container is clickable
    container:EnableMouse(true)
    container:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            local newState = not (config.get(btn) and true or false)
            config.set(btn, newState)
            refresh()
        end
    end)

    refresh()

    attachTooltip(container, config.tooltip)
    container._vcType   = "toggle"
    container._vcConfig = config
    container._switch   = btn
    container._label    = label
    container._refresh  = refresh
    return container
end

-- Old API compatibility: CreateCheckbox now returns a Toggle
function UI:CreateCheckbox(parent, config)
    return UI:CreateToggle(parent, config)
end

-- =========================================================
-- Slider (purple accent, value display on the right)
-- =========================================================
function UI:CreateSlider(parent, config)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetWidth(config.width or 200)
    s:SetMinMaxValues(config.min or 0, config.max or 100)
    s:SetValueStep(config.step or 1)
    s:SetObeyStepOnDrag(true)
    s:SetValue(config.get(s) or config.min or 0)

    if s.Low  then s.Low:SetText("") end  -- hide min text (clean)
    if s.High then s.High:SetText("") end
    if s.Text then
        s.Text:SetText(config.label or "")
        local c = ns.COLORS.text
        s.Text:SetTextColor(c.r, c.g, c.b)
    end

    local accent = ns.COLORS.accent
    local sMin = config.min or 0
    local sMax = config.max or 100

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

    local function updateFill(v)
        local frac = 0
        if sMax > sMin then frac = (v - sMin) / (sMax - sMin) end
        frac = math.max(0, math.min(1, frac))
        local w = (trackBg:GetWidth() or (config.width or 200)) * frac
        trackFill:SetWidth(math.max(0.001, w))
    end
    s._updateFill = updateFill

    -- Slimmer accent thumb
    local thumb = s:GetThumbTexture()
    if thumb then
        thumb:SetColorTexture(0.95, 0.95, 1.0, 1)
        thumb:SetSize(8, 16)
    end

    -- Value display + clickable ± buttons (SHIFT = 5x step)
    local stepSize = config.step or 1

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
        txt:SetPoint("CENTER", b, "CENTER", 0, 1)
        txt:SetText(label)
        b:SetScript("OnEnter", function() border:SetColorTexture(accent.r, accent.g, accent.b, 1) end)
        b:SetScript("OnLeave", function() border:SetColorTexture(0.3, 0.3, 0.35, 1) end)
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function()
            local mult = IsShiftKeyDown() and 5 or 1
            s:SetValue(s:GetValue() + dir * stepSize * mult)
        end)
        return b
    end

    local minusBtn = makeStepButton("-", -1)
    minusBtn:SetPoint("LEFT", s, "RIGHT", 8, 0)

    local valueText = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", minusBtn, "RIGHT", 4, 0)
    valueText:SetWidth(36)
    valueText:SetJustifyH("CENTER")
    local current = config.get(s) or 0
    valueText:SetText(string.format("%g", current))

    local plusBtn = makeStepButton("+", 1)
    plusBtn:SetPoint("LEFT", valueText, "RIGHT", 4, 0)

    s:SetScript("OnValueChanged", function(self, v)
        if config.step and config.step >= 1 then
            v = math.floor(v + 0.5)
        end
        valueText:SetText(string.format("%g", v))
        updateFill(v)
        config.set(self, v)
    end)

    -- Initial fill (defer one frame so the track has its real width)
    updateFill(config.get(s) or sMin)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() updateFill(s:GetValue() or sMin) end)
    end

    attachTooltip(s, config.tooltip)
    s._vcType   = "slider"
    s._vcConfig = config
    s._valueText = valueText
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

    -- Background
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(p)
    bg:SetColorTexture(0.08, 0.08, 0.10, 0.98)
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

        item._text:SetText(opt.text)
        if opt.value == config.get(button) then
            item._check:Show()
            item._text:SetTextColor(1, 1, 1)
        else
            item._check:Hide()
            item._text:SetTextColor(0.85, 0.85, 0.85)
        end

        item:SetScript("OnClick", function()
            config.set(button, opt.value)
            if button._setText then button._setText(opt.text) end
            closeActivePopup()
        end)

        item:Show()
    end

    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:Show()
end

function UI:CreateDropdown(parent, config)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(config.width or 160, config.label and 46 or 26)

    -- Optional label on top
    if config.label then
        local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        label:SetText(config.label)
        local c = ns.COLORS.text
        label:SetTextColor(c.r, c.g, c.b)
        container._label = label
    end

    -- Actual button
    local btn = CreateFrame("Button", nil, container)
    btn:SetHeight(26)
    if config.label then
        btn:SetPoint("BOTTOMLEFT",  container, "BOTTOMLEFT",  0, 0)
        btn:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    else
        btn:SetAllPoints(container)
    end

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
    valueText:SetPoint("LEFT",  btn, "LEFT",   8, 0)
    valueText:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    valueText:SetJustifyH("LEFT")

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

    local function setText(text) valueText:SetText(text or "") end
    btn._setText = setText

    local function refresh()
        local current = config.get(btn)
        for _, opt in ipairs(config.values or {}) do
            if opt.value == current then
                setText(opt.text)
                return
            end
        end
        setText(tostring(current or ""))
    end
    btn._refresh = refresh
    refresh()

    btn:SetScript("OnEnter", function() setHovered(true) end)
    btn:SetScript("OnLeave", function()
        if not (activePopup and activePopup:IsShown() and activePopup._owner == btn) then
            setHovered(false)
        end
    end)

    btn:SetScript("OnClick", function(self)
        if activePopup and activePopup:IsShown() and activePopup._owner == self then
            closeActivePopup()
        else
            closeActivePopup()
            openPopup(self, config)
            setHovered(true)
        end
    end)

    attachTooltip(btn, config.tooltip)
    container._vcType   = "dropdown"
    container._vcConfig = config
    container._button   = btn
    return container
end

-- =========================================================
-- EditBox
-- =========================================================
function UI:CreateEditBox(parent, config)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(26)

    -- Label to the LEFT of the edit field (instead of above)
    local label, eb
    if config.label and config.label ~= "" then
        label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", container, "LEFT", 0, 0)
        label:SetText(config.label)
        local c = ns.COLORS.text
        label:SetTextColor(c.r, c.g, c.b)
    end

    -- Edit field (rectangular, custom style — NO InputBoxTemplate)
    eb = CreateFrame("EditBox", nil, container)
    eb:SetHeight(22)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetTextInsets(8, 8, 0, 0)  -- inner padding left/right
    eb:SetText(tostring(config.get(eb) or ""))

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
    end)

    if label then
        -- config.width = desired TOTAL width (label + gap + editbox)
        local labelW = label:GetStringWidth() or 0
        local totalW = config.width or (labelW + 12 + 140)
        local editW  = config.editWidth or (totalW - labelW - 12)
        if editW < 40 then editW = 40 end

        container:SetWidth(labelW + 12 + editW)
        eb:SetPoint("LEFT", label, "RIGHT", 12, 0)
        eb:SetWidth(editW)
    else
        -- No label: edit field fills the container
        container:SetWidth(config.width or 160)
        eb:SetPoint("LEFT",  container, "LEFT",  0, 0)
        eb:SetWidth(config.width or 160)
    end

    eb:SetScript("OnEnterPressed", function(self)
        local v = self:GetText()
        if config.numeric then v = tonumber(v) end
        config.set(self, v)
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    attachTooltip(container, config.tooltip)
    container._vcType   = "editbox"
    container._vcConfig = config
    container._editBox  = eb
    return container
end

-- =========================================================
-- Button (clean, with accent hover)
-- =========================================================
function UI:CreateButton(parent, config)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(config.width or 120, config.height or 24)

    -- BG
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

    -- Text
    local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", b, "CENTER", 0, 0)
    text:SetText(config.label or "")
    local tc = ns.COLORS.text
    text:SetTextColor(tc.r, tc.g, tc.b)

    -- Accent variant (primary button)
    if config.primary then
        bg:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    end

    -- Hover effect
    b:SetScript("OnEnter", function()
        if config.primary then
            bg:SetColorTexture(ns.COLORS.accent.r * 1.15, ns.COLORS.accent.g * 1.15, ns.COLORS.accent.b * 1.15, 1)
        else
            bg:SetColorTexture(0.22, 0.22, 0.26, 1)
        end
        if config.tooltip then
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(config.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        if config.primary then
            bg:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        else
            bg:SetColorTexture(0.15, 0.15, 0.18, 1)
        end
        GameTooltip:Hide()
    end)

    b:SetScript("OnClick", function(self)
        if config.onClick then config.onClick(self) end
    end)

    b._vcType   = "button"
    b._vcConfig = config
    b._textFS   = text
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
}

function UI:CreateIconButton(parent, config)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(config.width or 24, config.height or 24)

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
    icon:SetSize((config.width or 24) - 10, (config.height or 24) - 10)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)

    local iconKey = config.icon
    local builtin = iconKey and BUILTIN_ICONS[iconKey]
    if builtin then
        icon:SetTexture(builtin.tex)
        icon:SetTexCoord(unpack(builtin.tc))
    elseif iconKey then
        icon:SetTexture(iconKey)
    end

    -- Hover
    b:SetScript("OnEnter", function()
        bg:SetColorTexture(0.22, 0.22, 0.26, 1)
        icon:SetVertexColor(1, 1, 1)
        if config.tooltip then
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(config.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(0.15, 0.15, 0.18, 1)
        icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
        if config.onClick then config.onClick(self) end
    end)

    b._vcType = "iconbutton"
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
