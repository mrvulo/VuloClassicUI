-- VuloClassicUI / UI / OptionsBuilder: builds a module page from mod:GetOptions(tabId).
-- Item spec:
--   { type = "header",    text }
--   { type = "desc",      text, width? }
--   { type = "checkbox" / "toggle", label, tooltip, get, set, width? }
--   { type = "slider",    label, tooltip, min, max, step, get, set }
--   { type = "dropdown",  label, tooltip, values, get, set, width? }
--   { type = "editbox",   label, tooltip, get, set, numeric, width? }
--   { type = "button",    label, tooltip, onClick, width?, primary? }
--   { type = "spacer",    height? }
--   { type = "group",     layout = "row" | "columns", items, columns?, gap? }
--   { type = "custom",    build = function(parent) -> frame end, height?, width? }
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local L = ns.L

local CONTENT_PADDING = 14

-- Shared dropdown value lists for the visibility pair several modules offer.
-- Built per call, never at file load: the saved language override is only
-- readable once SavedVariables are in.
function ns.VisibilityValues()
    return {
        { value = "always",    text = L["Always shown"] },
        { value = "mouseover", text = L["Mouseover"] },
        { value = "combat",    text = L["In combat"] },
        { value = "noncombat", text = L["Out of combat"] },
    }
end

-- Anchor points as words. They were built as { value = "CENTER", text = "CENTER" }
-- -- the raw frame token shown to the reader, in every language. The VALUE stays
-- the token because the client needs it; only the text is translated.
function ns.AnchorPointValues()
    return {
        { value = "CENTER",      text = L["Centre"] },
        { value = "TOP",         text = L["Top"] },
        { value = "BOTTOM",      text = L["Bottom"] },
        { value = "LEFT",        text = L["Left"] },
        { value = "RIGHT",       text = L["Right"] },
        { value = "TOPLEFT",     text = L["Top left"] },
        { value = "TOPRIGHT",    text = L["Top right"] },
        { value = "BOTTOMLEFT",  text = L["Bottom left"] },
        { value = "BOTTOMRIGHT", text = L["Bottom right"] },
    }
end

function ns.GroupVisValues()
    return {
        { value = "any",   text = L["Always"] },
        { value = "group", text = L["Only in a group"] },
        { value = "raid",  text = L["Only in a raid"] },
        { value = "party", text = L["Only in a party"] },
        { value = "solo",  text = L["Only solo"] },
    }
end

-- Frames are never garbage-collected: widgets are pooled by type and reconfigured via _vcSetup.
local poolHost = CreateFrame("Frame")
poolHost:Hide()
local pools = {}

local function acquire(vctype, parent)
    local p = pools[vctype]
    local w = p and table.remove(p)
    if w then
        w:SetParent(parent)
        w:Show()
    end
    return w
end

local function release(w)
    local t = w._vcType
    if not t or not w._vcSetup then return false end
    w:Hide()
    w:ClearAllPoints()
    w:SetParent(poolHost)
    pools[t] = pools[t] or {}
    table.insert(pools[t], w)
    return true
end

local function clearChildren(parent)
    local kids = { parent:GetChildren() }
    for _, k in ipairs(kids) do
        if not release(k) then
            if k == UI._dashContainer then
                k:Hide()
            else
                k:Hide()
                k:SetParent(nil)
                k:ClearAllPoints()
            end
        end
    end
    local regions = { parent:GetRegions() }
    for _, r in ipairs(regions) do
        if r.SetText then r:SetText("") end
        r:Hide()
        r:ClearAllPoints()
    end
end
UI.ClearOptionsChildren = clearChildren

local function obtain(vctype, parent, item, factory)
    local w = acquire(vctype, parent)
    if w then
        w:_vcSetup(item)
        return w
    end
    return factory()
end

local function createWidget(parent, item)
    local t = item.type
    if t == "header" then
        local w = obtain("header", parent, item, function()
            return UI:CreateHeader(parent, item.text or "")
        end)
        return w, 26, 480
    elseif t == "desc" then
        local w = obtain("desc", parent, item, function()
            return UI:CreateDescription(parent, item.text or "")
        end)
        w:SetDescWidth(item.width or 480)
        return w, math.max(20, w:GetDescHeight() + 4), item.width or 480
    elseif t == "checkbox" or t == "toggle" then
        -- The eye variant is built differently at construction and cannot be
        -- reconfigured into a switch or back, so the two need separate pools.
        -- Sharing one made an ordinary on/off row come back as an eye glyph
        -- after visiting a page that used the eye style.
        local w = obtain(item.style == "eye" and "toggle_eye" or "toggle", parent, item, function()
            return UI:CreateToggle(parent, item)
        end)
        return w, 26, w:GetWidth() or 260
    elseif t == "slider" then
        local w = obtain("slider", parent, item, function()
            return UI:CreateSlider(parent, item)
        end)
        return w, 24, 280
    elseif t == "dropdown" then
        local w = obtain("dropdown", parent, item, function()
            return UI:CreateDropdown(parent, item)
        end)
        return w, item.label and 30 or 28, item.width or 200
    elseif t == "editbox" then
        local w = obtain("editbox", parent, item, function()
            return UI:CreateEditBox(parent, item)
        end)
        return w, 28, w:GetWidth() or 160
    elseif t == "color" then
        local w = obtain("color", parent, item, function()
            return UI:CreateColorSwatch(parent, item)
        end)
        return w, 26, w:GetWidth() or 200
    elseif t == "button" then
        local w = obtain("button", parent, item, function()
            return UI:CreateButton(parent, item)
        end)
        return w, 30, (w:GetWidth() or item.width or 120)
    elseif t == "iconbutton" then
        local w = obtain("iconbutton", parent, item, function()
            return UI:CreateIconButton(parent, item)
        end)
        return w, 28, item.width or 28
    elseif t == "custom" then
        -- build(parent) must return a module-owned, memoised frame: it survives clearChildren.
        local w = item.build and item.build(parent)
        if not w then return nil, 0, 0 end
        return w, item.height or (w:GetHeight() or 100), item.width or 480
    end
    return nil, 0, 0
end

local function estimateHeight(item)
    local t = item.type
    if t == "checkbox" or t == "toggle" then return 26
    elseif t == "button" or t == "iconbutton" then return 30
    elseif t == "header" then return 26
    elseif t == "desc"   then return 22
    elseif t == "slider" then return 24
    elseif t == "dropdown" then return item.label and 30 or 28
    elseif t == "editbox" then return 28
    elseif t == "color" then return 26
    elseif t == "custom" then return item.height or 100
    end
    return 26
end

UI.sectionCollapsed = UI.sectionCollapsed or {}

-- Consecutive compact controls auto-arrange into a two-column grid; everything
-- else is full width. The slider joined them once it became a one-line row:
-- while its label sat above the track it needed its own taller shape, and that
-- was the reason a page had three different row heights in it.
local COMPACT = { toggle = true, checkbox = true, dropdown = true, editbox = true, color = true, slider = true }
local COL_GAP  = 14
local ROW_H    = 38
local CARD_GAP = 8
local CARD_H   = ROW_H - CARD_GAP
local CARD_VPAD = 11

local function makePanel(parent)
    local p = acquire("panel", parent)
    if p then return p end
    p = CreateFrame("Frame", nil, parent)
    p._vcType  = "panel"
    p._vcSetup = function() end
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints(p)
    -- LIGHTER than the page behind it (bgContent is 0.08). It used to be 0.075,
    -- i.e. a hair DARKER than the page, so a card was nothing but its outline
    -- and the eye had to trace borders to see where one setting ended. Raising
    -- the fill lets the card read as an object and lets the border step back.
    p.bg:SetColorTexture(0.115, 0.115, 0.14, 0.95)
    for _, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = p:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.19, 0.19, 0.24, 1)
        if s == "TOP" or s == "BOTTOM" then
            t:SetPoint(s .. "LEFT"); t:SetPoint(s .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. s); t:SetPoint("BOTTOM" .. s); t:SetWidth(1)
        end
    end
    return p
end

-- Row icons: info shows item.tooltip, gear expands item.subOptions inline.
local ICON_DIR  = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\"
local ICON_INFO = ICON_DIR .. "info.tga"
local ICON_GEAR = ICON_DIR .. "gear.tga"
local ICON_CFG = {
    [ICON_INFO] = { crop = false, desat = false },
    [ICON_GEAR] = { crop = false, desat = false },
}
UI.rowExpanded = UI.rowExpanded or {}

local function makeRowIcon(parent)
    local b = acquire("rowicon", parent)
    if b then return b end
    b = CreateFrame("Button", nil, parent)
    b._vcType  = "rowicon"
    b._vcSetup = function() end
    b:SetSize(16, 16)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        self:SetSize(18, 18)
        if self._tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self._tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.62, 0.62, 0.70)
        self:SetSize(16, 16)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self) if self._onClick then self._onClick() end end)
    return b
end

local function setRowIcon(b, tex, tip, onClick, level)
    local cfg = ICON_CFG[tex] or {}
    b.icon:SetTexture(tex)
    b.icon:SetTexCoord(cfg.crop and 0.10 or 0, cfg.crop and 0.90 or 1,
                       cfg.crop and 0.10 or 0, cfg.crop and 0.90 or 1)
    b.icon:SetDesaturated(cfg.desat and true or false)
    b.icon:SetVertexColor(0.62, 0.62, 0.70)
    b._tip = tip
    b._onClick = onClick
    b:SetFrameLevel(level)
    b:Show()
    return b
end

local placeItem, placeItemList  -- forward decls: mutually recursive via sections

-- One hidden string, reused, to measure label widths before anything is drawn.
-- Creating one per measurement would leak a font string per page build, and
-- frames and their regions are never collected in this client.
local measureFS
local function labelWidth(text)
    if not text or text == "" then return 0 end
    if not measureFS then
        measureFS = poolHost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        UI.Font(measureFS, 12)
    end
    measureFS:SetText(text)
    return measureFS:GetStringWidth() or 0
end

-- The widest label in the run decides where every control in it begins. This is
-- the whole point: the column is MEASURED, not guessed, so a group lines up on
-- one edge without anyone tuning gaps by eye. Capped at 45% of a cell so one
-- long label cannot squeeze every track in the group down to a stub.
local function runLabelColumn(run, cellW)
    local widest = 0
    for _, item in ipairs(run) do
        if item.type == "slider" then
            local w = labelWidth(item.label)
            -- A tooltip puts an info glyph in front of the text, inside the same
            -- column. Measuring only the text made exactly those rows clip --
            -- "Engine-FCT-Skalieru..." was the giveaway.
            if item.tooltip then w = w + 22 end
            if w > widest then widest = w end
        end
    end
    if widest == 0 then return nil end
    -- Slack, not a tight fit: GetStringWidth and the actual glyph run differ by
    -- a hair, and at a tight fit the client answers with an ellipsis rather than
    -- the last letter. Two pixels was not enough -- "Nachrichtenabsta..." lost
    -- three characters to it.
    return math.min(math.ceil(widest) + 10, math.floor(cellW * 0.5))
end

-- How many columns a run of compact rows may use: as many as its labels allow,
-- never more than three. Three columns fit noticeably more on screen, but they
-- leave the label column only about a third of the width -- and a page like the
-- action bars carries labels that simply do not fit there. Rather than picking
-- one number for every page and clipping the pages it does not suit, the run
-- decides for itself and drops to two, or to one.
local MAX_COLS = 3

local function fitColumns(run, availW)
    local widest = 0
    for _, item in ipairs(run) do
        local w = labelWidth(item.label)
        if item.tooltip then w = w + 22 end
        if w > widest then widest = w end
    end
    for cols = MAX_COLS, 2, -1 do
        local cellW = math.floor((availW - (cols - 1) * COL_GAP) / cols)
        -- label plus a control area worth having: below this the row is a label
        -- with a stub of a track next to it.
        if widest + 10 <= cellW * 0.5 and cellW >= 250 then return cols end
    end
    return 2
end

local function placeColumns(parent, run, y)
    local availW = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING
    local cols   = fitColumns(run, availW)
    local colW   = math.floor((availW - (cols - 1) * COL_GAP) / cols)
    local labelCol = runLabelColumn(run, colW)
    local base   = parent:GetFrameLevel()
    local n      = #run
    for idx = 1, n do
        local item  = run[idx]
        local col   = (idx - 1) % cols
        local row   = math.floor((idx - 1) / cols)
        -- last item, alone on its row: it takes the whole width rather than
        -- leaving a ragged gap beside it
        local fullW = (idx == n) and (n % cols == 1)
        local cellX = CONTENT_PADDING + (fullW and 0 or col * (colW + COL_GAP))
        local cellY = y - row * ROW_H
        local cellW = fullW and availW or colW

        local p = makePanel(parent)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", parent, "TOPLEFT", cellX, cellY)
        p:SetSize(cellW, CARD_H)
        p:SetFrameLevel(base + 1)
        p:Show()

        local lead = 0
        if item.tooltip then
            local e = setRowIcon(makeRowIcon(parent), ICON_INFO, item.tooltip, nil, base + 5)
            e:ClearAllPoints()
            e:SetPoint("LEFT", parent, "TOPLEFT", cellX + 10, cellY - CARD_H / 2)
            lead = 22
        end

        local widget = createWidget(parent, item)
        if widget then
            widget:SetWidth(cellW - 20 - lead)
            if labelCol and widget.SetLabelWidth then widget:SetLabelWidth(labelCol) end
            widget:SetFrameLevel(base + 4)
            local wh = widget:GetHeight() or 22
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT",
                cellX + 10 + lead, cellY - math.floor((CARD_H - wh) / 2))
        end
    end
    return y - math.ceil(n / cols) * ROW_H
end

local function placeSection(parent, section, y)
    local title    = section.title or "Section"
    local stateKey = (UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "") .. "/" .. title

    local collapsed = UI.sectionCollapsed[stateKey]
    if collapsed == nil then collapsed = section.collapsed and true or false end

    -- Space ABOVE a section heading, and clearly more than the gap between the
    -- cards inside one. When both gaps are the same the page reads as one long
    -- list and the headings stop grouping anything.
    y = y - 24

    local onClick = function()
        UI.sectionCollapsed[stateKey] = not collapsed
        UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
    end
    local hdr = acquire("collapsible", parent)
    if hdr then
        hdr:_vcSetup(title, not collapsed, onClick)
    else
        hdr = UI:CreateCollapsibleHeader(parent, title, not collapsed, onClick)
    end
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
    y = y - 26

    if not collapsed then
        y = placeItemList(parent, section.items or {}, y)
    end
    return y
end

local CARD_TYPES = { toggle = true, checkbox = true, dropdown = true, editbox = true, slider = true, color = true }

placeItem = function(parent, item, y)
    if item.type == "spacer" then
        return y - (item.height or 8)
    end
    if item.type == "group" then
        return UI:PlaceGroup(parent, item, y)
    end
    if item.type == "section" then
        return placeSection(parent, item, y)
    end
    if item.type == "header" then
        y = y - 12
    end

    local widget, h = createWidget(parent, item)
    if not widget then return y end

    local base   = parent:GetFrameLevel()
    local availW = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING

    if CARD_TYPES[item.type] then
        local p = makePanel(parent)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
        p:SetSize(availW, h)
        p:SetFrameLevel(base + 1)
        p:Show()
        widget:SetFrameLevel(base + 4)

        local key = (UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "")
            .. "/r/" .. tostring(item.label or item.text or item)
        local expanded = UI.rowExpanded[key]

        local iconRight = CONTENT_PADDING + availW - 6
        local nIcons = (item.subOptions and 1 or 0) + (item.tooltip and 1 or 0)
        if item.subOptions then
            local g = setRowIcon(makeRowIcon(parent), ICON_GEAR, L["Extra settings"], function()
                UI.rowExpanded[key] = not expanded
                UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
            end, base + 5)
            g:ClearAllPoints(); g:SetPoint("TOPRIGHT", parent, "TOPLEFT", iconRight, y - 7)
            iconRight = iconRight - 21
        end
        if item.tooltip then
            local e = setRowIcon(makeRowIcon(parent), ICON_INFO, item.tooltip, nil, base + 5)
            e:ClearAllPoints(); e:SetPoint("TOPRIGHT", parent, "TOPLEFT", iconRight, y - 7)
            iconRight = iconRight - 21
        end

        -- A one-line row like every other: no strip reserved to the right of
        -- the track, and no -14 nudge to clear a label that sat above it.
        widget:SetWidth(math.max(120, availW - 20 - nIcons * 21))
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 10, y)

        y = y - h - CARD_GAP
        if expanded and item.subOptions then
            y = placeItemList(parent, item.subOptions, y)
        end
        return y
    end

    if item.type == "button" or item.type == "iconbutton" then
        local wh    = widget:GetHeight() or 24
        local cardH = wh + CARD_VPAD * 2
        local p = makePanel(parent)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
        p:SetSize(availW, cardH)
        p:SetFrameLevel(base + 1)
        p:Show()
        widget:SetFrameLevel(base + 4)
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 10, y - CARD_VPAD)
        return y - cardH - CARD_GAP
    end

    if item.type == "desc" then
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y - 5)
        return y - h - 10
    end

    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
    return y - h
end

placeItemList = function(parent, items, y)
    local i = 1
    while i <= #items do
        local it = items[i]
        if COMPACT[it.type] and not it.subOptions then
            local run = {}
            while items[i] and COMPACT[items[i].type] and not items[i].subOptions do
                run[#run + 1] = items[i]; i = i + 1
            end
            y = placeColumns(parent, run, y)
        else
            y = placeItem(parent, it, y)
            i = i + 1
        end
    end
    return y
end

-- A row whose value is overridden for the ACTIVE talent group gets an accent bar
-- on its left edge. Applied here because every widget type comes through the one
-- funnel above, and cleared on every build rather than only set: widgets are
-- pooled, so a mark left behind would travel to an unrelated row on the next
-- page. Nothing about the row moves -- the bar sits in the padding.
local function applyOverrideMark(w, item)
    if not w or type(w.CreateTexture) ~= "function" then return end

    local on = false
    if item._vcOverrideId and ns.HasOverride and ns.ActiveTalentGroup then
        on = ns:HasOverride(ns:ActiveTalentGroup(), item._vcOverrideId)
    end

    if not on then
        if w._vcOvMark then w._vcOvMark:Hide() end
        return
    end

    local mark = w._vcOvMark
    if not mark then
        mark = w:CreateTexture(nil, "OVERLAY")
        mark:SetPoint("TOPLEFT",    w, "TOPLEFT",    -6, 1)
        mark:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", -6, -1)
        mark:SetWidth(2)
        w._vcOvMark = mark
    end
    local a = ns.COLORS.accent
    mark:SetColorTexture(a.r, a.g, a.b, 0.95)
    mark:Show()
end

-- Rebinding the local: every call site below reads this upvalue, so the mark is
-- applied to all of them without touching the fifteen return points inside.
local rawCreateWidget = createWidget
createWidget = function(parent, item)
    local w, h, wide = rawCreateWidget(parent, item)
    applyOverrideMark(w, item)
    return w, h, wide
end

function UI:PlaceGroup(parent, group, y)
    local layout = group.layout or "row"
    local items  = group.items or {}
    local availW = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING
    local base   = parent:GetFrameLevel()

    local panel = (group.noCard ~= true) and makePanel(parent) or nil
    if panel then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
        panel:SetFrameLevel(base + 1)
        panel:Show()
    end

    if layout == "row" then
        local placed, totalW = {}, 0
        local gap = group.gap or 8
        for i, item in ipairs(items) do
            local widget, h, w = createWidget(parent, item)
            if widget then
                placed[#placed + 1] = { widget = widget, w = w, h = h, item = item }
                totalW = totalW + w + (i > 1 and gap or 0)
            end
        end

        -- centre on ACTUAL widget heights: the createWidget row estimate differs
        local maxWH = 0
        for _, p in ipairs(placed) do
            p.wh = p.widget:GetHeight() or p.h
            if p.wh > maxWH then maxWH = p.wh end
        end
        local PAD   = CARD_VPAD
        local cardH = maxWH + PAD * 2

        local startX = CONTENT_PADDING + 10
        if group.align == "center" then
            startX = CONTENT_PADDING + math.max(10, math.floor((availW - totalW) / 2))
        end

        local cursorX = startX
        for _, p in ipairs(placed) do
            if panel then p.widget:SetFrameLevel(base + 4) end
            local yo = y - PAD - math.floor((maxWH - p.wh) / 2)
            p.widget:SetPoint("TOPLEFT", parent, "TOPLEFT", cursorX, yo)
            cursorX = cursorX + p.w + gap
        end
        if panel then panel:SetSize(availW, cardH) end
        return y - cardH - CARD_GAP

    elseif layout == "columns" then
        local availWidth = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING
        -- Every module declared columns = 2 because two was the only shape on
        -- offer. The measured rule supersedes it: the same fitColumns the
        -- auto-packed runs use, so a page does not mix a two-column group with
        -- a three-column one. A module asking for MORE than the labels allow is
        -- still held to what fits.
        local cols       = fitColumns(items, availWidth)
        local colWidth   = math.floor(availWidth / cols)

        local rowItems = {}
        local rowMaxH  = 0
        local curY     = y

        local function flushRow()
            local cellW = colWidth - 14
            -- One measured label column for the whole row, exactly as in the
            -- two-column path. Without it every slider here fell back to the
            -- 120px default and the second column's label was cut to
            -- "Nachrichte...".
            local labelCol = runLabelColumn(rowItems, cellW)
            for i, ri in ipairs(rowItems) do
                -- clamp to column width: a toggle's right-anchored switch would
                -- otherwise overlap the next column's label
                if ri.width == nil and (ri.type == "toggle" or ri.type == "checkbox") then
                    ri.width = cellW
                end
                local widget = createWidget(parent, ri)
                if widget then
                    -- A slider row sizes itself from its own width. This path
                    -- never set one, so the row kept the width it computed from
                    -- config.width and ran straight into the next column.
                    if ri.type == "slider" then
                        widget:SetWidth(cellW)
                        if labelCol and widget.SetLabelWidth then widget:SetLabelWidth(labelCol) end
                    end
                    if panel then widget:SetFrameLevel(base + 4) end
                    local xo = CONTENT_PADDING + (panel and 6 or 0) + (i - 1) * colWidth
                    local yo = curY - (panel and 4 or 0)
                    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", xo, yo)
                end
            end
            curY = curY - rowMaxH
            rowItems = {}
            rowMaxH  = 0
        end

        for _, item in ipairs(items) do
            table.insert(rowItems, item)
            local eh = estimateHeight(item)
            if eh > rowMaxH then rowMaxH = eh end
            if #rowItems >= cols then flushRow() end
        end
        if #rowItems > 0 then flushRow() end

        if panel then panel:SetSize(availW, (y - curY) + 8); curY = curY - 8 end
        return curY
    end

    if panel then panel:Hide() end
    return y
end

-- True if the module's options are on screen, directly or as its container's active tab.
function UI:IsModuleActive(key)
    if UI.currentModule == key then return true end
    local m = ns.modules[key]
    if not m then return false end
    if m.parentTab and UI.currentModule == m.parentTab and UI.currentTab == key then
        return true
    end
    -- A page member has no page of its own: it is rendered as a section of its
    -- page, which is itself a tab of a container. Without this the answer was
    -- always no, so those modules never redrew their own options and lists that
    -- an Add or Remove button had just changed stayed stale.
    if m._pageKey and (UI.currentTab == m._pageKey or UI.currentModule == m._pageKey) then
        return true
    end
    return false
end

-- Rebuild whatever page is open, without knowing which one that is. Used when
-- something outside the page changes how it must be drawn -- entering or leaving
-- the talent-override editing mode, for one.
function UI:RebuildCurrentPage()
    local key = UI.currentModule
    if not key or key == UI.DASHBOARD_KEY then return end
    UI:BuildOptionsPage(key, UI.currentTab)
end

function UI:BuildOptionsPage(key, tabId)
    local f = UI.mainFrame
    if not f then return end
    -- a sub-module redirects to its container + own tab, so rebuildPage("itskey") keeps working
    local m0 = ns.modules[key]
    if m0 and m0.parentTab then
        tabId = key
        key   = m0.parentTab
    end
    local mod = ns.modules[key]
    if not mod then return end

    local parent = f.scrollChild
    clearChildren(parent)
    parent:SetWidth((f.scroll:GetWidth() or 540) - 8)
    UI._currentBuildKey = key

    local y = -8

    -- mod.description is a raw English key, translated live
    if mod.description and mod.description ~= "" then
        local pw = parent:GetWidth()
        if not pw or pw < 100 then pw = 540 end
        local desc = createWidget(parent, {
            type  = "desc",
            text  = L[mod.description],
            width = pw - 2 * CONTENT_PADDING,
        })
        desc:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
        y = y - math.max(20, desc:GetDescHeight() + 8)
    end

    -- clearChildren() already ran, so an error here would leave a blank page with
    -- no height and no explanation. The other two GetOptions call sites (the tab
    -- container and the settings search index) have always guarded; this one is
    -- the path the user actually walks.
    local items
    if mod.GetOptions then
        local ok, result = pcall(mod.GetOptions, mod, tabId)
        if ok then
            items = result
        else
            ns:Print(L["|cffff5555Options page '%s' failed to build:|r %s"], tostring(mod.key or mod.name), tostring(result))
            items = { { type = "desc", text = L["|cffff5555This page could not be built. /reload, and report it if it persists.|r"] } }
        end
    end
    if type(items) ~= "table" then items = {} end

    -- One interception point for every widget type: the item table is what the
    -- widgets read `set` from, so wrapping it here covers checkbox, slider,
    -- dropdown and editbox at once. The items are freshly built by GetOptions on
    -- every page build, so the wrapper never stacks.
    if ns.NoteOverrideWrite then
        local function wrap(list)
            for _, it in ipairs(list) do
                if type(it) == "table" then
                    if it.items then wrap(it.items) end
                    -- The profile page is excluded outright: which profile is
                    -- active, and the switch that starts the recording itself,
                    -- must never become per-talent-group values. Without this
                    -- the recording switch records itself the moment it is
                    -- turned on, and the talent switch then replays it.
                    if type(it.set) == "function" and type(it.get) == "function"
                       and it.label and it.type ~= "color"
                       and not it.noOverride and key ~= "profiles" then
                        local id     = ns:OverrideId(key, tabId, it.label)
                        local setter = it.set
                        local getter = it.get
                        it._vcOverrideId = id
                        it.set = function(...)
                            setter(...)
                            -- read back rather than read the arguments: what the
                            -- module chose to store is the value that matters
                            ns:NoteOverrideWrite(id, getter)
                        end
                    end
                end
            end
        end
        wrap(items)
    end

    y = placeItemList(parent, items, y)

    local totalHeight = math.max(400, math.abs(y) + 20)
    parent:SetHeight(totalHeight)
end
