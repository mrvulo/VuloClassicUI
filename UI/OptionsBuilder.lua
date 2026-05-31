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

local function clearChildren(parent)
    local kids = { parent:GetChildren() }
    for _, k in ipairs(kids) do
        k:Hide()
        k:SetParent(nil)
        k:ClearAllPoints()
    end
    local regions = { parent:GetRegions() }
    for _, r in ipairs(regions) do
        if r.SetText then r:SetText("") end
        r:Hide()
        r:ClearAllPoints()
    end
end

local function createWidget(parent, item)
    local t = item.type
    if t == "header" then
        return UI:CreateHeader(parent, item.text or ""), 26, 480
    elseif t == "desc" then
        local fs = UI:CreateDescription(parent, item.text or "")
        fs:SetWidth(item.width or 480)
        local _, h = fs:GetSize()
        return fs, math.max(20, (h or 18) + 4), item.width or 480
    elseif t == "checkbox" or t == "toggle" then
        local w = UI:CreateToggle(parent, item)
        return w, 26, w:GetWidth() or 260
    elseif t == "slider" then
        return UI:CreateSlider(parent, item), 38, 280
    elseif t == "dropdown" then
        return UI:CreateDropdown(parent, item), item.label and 50 or 32, item.width or 200
    elseif t == "editbox" then
        local w = UI:CreateEditBox(parent, item)
        return w, 28, w:GetWidth() or 160
    elseif t == "button" then
        return UI:CreateButton(parent, item), 30, item.width or 120
    elseif t == "iconbutton" then
        return UI:CreateIconButton(parent, item), 28, item.width or 28
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
    elseif t == "dropdown" then return item.label and 50 or 32
    elseif t == "editbox" then return 28
    end
    return 26
end

-- Collapsible-section state, keyed by "<moduleKey>/<tab>/<title>"
UI.sectionCollapsed = UI.sectionCollapsed or {}

local placeItem  -- forward declaration (placeSection calls back into it)

local function placeSection(parent, section, y)
    local title    = section.title or "Section"
    local stateKey = (UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "") .. "/" .. title

    -- Resolve collapsed state: runtime override, else the section's default
    local collapsed = UI.sectionCollapsed[stateKey]
    if collapsed == nil then collapsed = section.collapsed and true or false end

    y = y - 10  -- breathing room above

    local hdr = UI:CreateCollapsibleHeader(parent, title, not collapsed, function()
        UI.sectionCollapsed[stateKey] = not collapsed
        UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
    end)
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
    y = y - 26

    if not collapsed then
        for _, sub in ipairs(section.items or {}) do
            y = placeItem(parent, sub, y)
        end
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
        -- Header gets extra breathing room above for clear section separation
        y = y - 10
    end

    local widget, h = createWidget(parent, item)
    if not widget then return y end

    local xOff = CONTENT_PADDING
    local yOff = y
    if item.type == "slider" then yOff = y - 14 end

    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)
    return y - h
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
        local desc = UI:CreateDescription(parent, L[mod.description])
        desc:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
        local pw = parent:GetWidth()
        if not pw or pw < 100 then pw = 540 end
        desc:SetWidth(pw - 2 * CONTENT_PADDING)
        local _, descH = desc:GetSize()
        y = y - math.max(20, (descH or 18) + 8)
    end

    -- Fetch options, optionally with tabId
    local items
    if mod.GetOptions then
        items = mod:GetOptions(tabId)
    end
    items = items or {}

    for _, item in ipairs(items) do
        y = placeItem(parent, item, y)
    end

    local totalHeight = math.max(400, math.abs(y) + 20)
    parent:SetHeight(totalHeight)
end
