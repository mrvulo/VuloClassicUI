-- =========================================================
-- VuloClassicUI / UI / OptionsBuilder
-- Builds the content page for a module from mod:GetOptions().
-- Tab-aware: mod:GetOptions(tabId) when the module defines tabs.
--
-- Item types:
--   { type = "header",    text }
--   { type = "desc",      text, width? }
--   { type = "checkbox" / "toggle", label, tooltip, get, set, width? }
--   { type = "slider",    label, tooltip, min, max, step, get, set }
--   { type = "dropdown",  label, tooltip, values, get, set, width? }
--   { type = "editbox",   label, tooltip, get, set, numeric, width? }
--   { type = "button",    label, tooltip, onClick, width?, primary? }
--   { type = "spacer",    height? }
--   { type = "group",     layout = "row" | "columns", items, columns?, gap? }
-- =========================================================
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local L = ns.L

local CONTENT_PADDING = 14
local SECTION_GAP     = 12

-- =========================================================
-- Widget pooling
-- WoW frames are never garbage-collected, so rebuilding a page must not
-- create fresh widgets each time. On clear, widgets go back into
-- type-keyed pools (parked under a hidden host); on build they are
-- reconfigured via their _vcSetup instead of recreated.
-- =========================================================
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

-- Clears a page: pooled widgets are released for reuse; the dashboard's
-- persistent container is only hidden; anything else detaches as before.
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
UI.ClearOptionsChildren = clearChildren  -- shared with the dashboard

-- Acquire a pooled widget of the type or create a fresh one
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
        local w = obtain("toggle", parent, item, function()
            return UI:CreateToggle(parent, item)
        end)
        return w, 26, w:GetWidth() or 260
    elseif t == "slider" then
        local w = obtain("slider", parent, item, function()
            return UI:CreateSlider(parent, item)
        end)
        return w, 38, 280
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
    elseif t == "button" then
        local w = obtain("button", parent, item, function()
            return UI:CreateButton(parent, item)
        end)
        return w, 30, item.width or 120
    elseif t == "iconbutton" then
        local w = obtain("iconbutton", parent, item, function()
            return UI:CreateIconButton(parent, item)
        end)
        return w, 28, item.width or 28
    end
    return nil, 0, 0
end

local function estimateHeight(item)
    local t = item.type
    if t == "checkbox" or t == "toggle" then return 26
    elseif t == "button" or t == "iconbutton" then return 30
    elseif t == "header" then return 26
    elseif t == "desc"   then return 22
    elseif t == "slider" then return 38
    elseif t == "dropdown" then return item.label and 30 or 28
    elseif t == "editbox" then return 28
    end
    return 26
end

-- Collapsible-section state, keyed by "<moduleKey>/<tab>/<title>"
UI.sectionCollapsed = UI.sectionCollapsed or {}

-- =========================================================
-- Layout: consecutive compact controls (toggle/dropdown/editbox) auto-arrange
-- into a two-column grid of subtle "card" rows; headers, sliders, groups,
-- sections and buttons span the full width on their own row.
-- =========================================================
local COMPACT = { toggle = true, checkbox = true, dropdown = true, editbox = true }
local COL_GAP = 12
local ROW_H   = 32

-- Pooled row panel (rides the widget pool via _vcType / _vcSetup)
local function makePanel(parent)
    local p = acquire("panel", parent)
    if p then return p end
    p = CreateFrame("Frame", nil, parent)
    p._vcType  = "panel"
    p._vcSetup = function() end
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints(p)
    p.bg:SetColorTexture(0.105, 0.105, 0.135, 0.55)
    return p
end

local placeItem, placeItemList  -- forward (mutual recursion via sections)

local function placeColumns(parent, run, y)
    local availW = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING
    local colW   = math.floor((availW - COL_GAP) / 2)
    local base   = parent:GetFrameLevel()
    local n      = #run
    for idx = 1, n do
        local item  = run[idx]
        local col   = (idx - 1) % 2
        local row   = math.floor((idx - 1) / 2)
        local cellX = CONTENT_PADDING + col * (colW + COL_GAP)
        local cellY = y - row * ROW_H

        local p = makePanel(parent)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", parent, "TOPLEFT", cellX, cellY)
        p:SetSize(colW, ROW_H - 4)
        p:SetFrameLevel(base + 1)
        p:Show()

        local widget = createWidget(parent, item)
        if widget then
            widget:SetWidth(colW - 16)
            widget:SetFrameLevel(base + 4)
            local wh = widget:GetHeight() or 22
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT",
                cellX + 8, cellY - math.floor(((ROW_H - 4) - wh) / 2))
        end
    end
    return y - math.ceil(n / 2) * ROW_H
end

local function placeSection(parent, section, y)
    local title    = section.title or "Section"
    local stateKey = (UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "") .. "/" .. title

    local collapsed = UI.sectionCollapsed[stateKey]
    if collapsed == nil then collapsed = section.collapsed and true or false end

    y = y - 10  -- breathing room above

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
        y = y - 12  -- breathing room above section labels
    end

    local widget, h = createWidget(parent, item)
    if not widget then return y end

    local xOff = CONTENT_PADDING
    local yOff = y
    if item.type == "slider" then yOff = y - 14 end

    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)
    return y - h
end

-- Gather runs of consecutive compact controls into 2-column rows; everything
-- else is placed full-width. Used at the top level and inside sections.
placeItemList = function(parent, items, y)
    local i = 1
    while i <= #items do
        if COMPACT[items[i].type] then
            local run = {}
            while items[i] and COMPACT[items[i].type] do
                run[#run + 1] = items[i]; i = i + 1
            end
            y = placeColumns(parent, run, y)
        else
            y = placeItem(parent, items[i], y)
            i = i + 1
        end
    end
    return y
end

function UI:PlaceGroup(parent, group, y)
    local layout = group.layout or "row"
    local items  = group.items or {}

    if layout == "row" then
        local cursorX = CONTENT_PADDING
        local maxH = 0
        for _, item in ipairs(items) do
            local widget, h, w = createWidget(parent, item)
            if widget then
                local yo = y
                if item.type == "slider" then yo = y - 14 end
                widget:SetPoint("TOPLEFT", parent, "TOPLEFT", cursorX, yo)
                cursorX = cursorX + w + (group.gap or 8)
                if h > maxH then maxH = h end
            end
        end
        return y - maxH

    elseif layout == "columns" then
        local cols       = group.columns or 2
        local availWidth = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING
        local colWidth   = math.floor(availWidth / cols)

        local rowItems = {}
        local rowMaxH  = 0
        local curY     = y

        local function flushRow()
            for i, ri in ipairs(rowItems) do
                -- Constrain the widget to the column width so a toggle's switch
                -- (right-anchored) stays inside its column instead of overlapping
                -- the next column's label.
                if ri.width == nil and (ri.type == "toggle" or ri.type == "checkbox") then
                    ri.width = colWidth - 14
                end
                local widget = createWidget(parent, ri)
                if widget then
                    local xo = CONTENT_PADDING + (i - 1) * colWidth
                    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", xo, curY)
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

        return curY
    end

    return y
end

-- =========================================================
-- Main function
-- =========================================================
function UI:BuildOptionsPage(key, tabId)
    local f = UI.mainFrame
    if not f then return end
    local mod = ns.modules[key]
    if not mod then return end

    local parent = f.scrollChild
    clearChildren(parent)
    parent:SetWidth((f.scroll:GetWidth() or 540) - 8)
    UI._currentBuildKey = key  -- for collapsible-section state keys

    local y = -8

    -- Module description on top (small, dim) — mod.description is a raw English key
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

    -- Fetch options, optionally with tabId
    local items
    if mod.GetOptions then
        items = mod:GetOptions(tabId)
    end
    items = items or {}

    y = placeItemList(parent, items, y)

    local totalHeight = math.max(400, math.abs(y) + 20)
    parent:SetHeight(totalHeight)
end
