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
    elseif t == "color" then return 26
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
local COMPACT = { toggle = true, checkbox = true, dropdown = true, editbox = true, color = true }
local COL_GAP  = 14
local ROW_H    = 38          -- vertical pitch of a card row
local CARD_GAP = 8           -- empty space between stacked cards
local CARD_H   = ROW_H - CARD_GAP
local CARD_VPAD = 11         -- vertical breathing room inside button/group cards

-- Pooled row panel (rides the widget pool via _vcType / _vcSetup).
-- A raised "card": fill slightly lighter than the content bg + a thin border,
-- so each option row reads as its own panel like the reference design.
local function makePanel(parent)
    local p = acquire("panel", parent)
    if p then return p end
    p = CreateFrame("Frame", nil, parent)
    p._vcType  = "panel"
    p._vcSetup = function() end
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints(p)
    p.bg:SetColorTexture(0.075, 0.075, 0.095, 0.9)   -- subtle, like the mockup row
    for _, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = p:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.15, 0.15, 0.19, 1)       -- thin, low-key border
        if s == "TOP" or s == "BOTTOM" then
            t:SetPoint(s .. "LEFT"); t:SetPoint(s .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. s); t:SetPoint("BOTTOM" .. s); t:SetWidth(1)
        end
    end
    return p
end

-- =========================================================
-- Per-row icons: eye = help/info (shows the option's tooltip), gear = extra
-- settings (toggles an inline expansion of item.subOptions).
-- =========================================================
-- Custom row icons. Drop your TGA files here (see chat instructions); until
-- then WoW shows a placeholder box. They fall back to clean Blizzard textures
-- only if you delete the files. Path = Interface\AddOns\VuloClassicUI\Media\Icons
local ICON_DIR  = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\"
local ICON_INFO = ICON_DIR .. "eye.tga"      -- eye = info/help
local ICON_GEAR = ICON_DIR .. "gear.tga"     -- gear = extra settings
-- custom icons are clean line art: no crop, no desaturate
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
        -- a lone trailing item (odd count) spans the full width
        local fullW = (idx == n) and (n % 2 == 1)
        local cellX = CONTENT_PADDING + (fullW and 0 or col * (colW + COL_GAP))
        local cellY = y - row * ROW_H
        local cellW = fullW and availW or colW

        local p = makePanel(parent)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", parent, "TOPLEFT", cellX, cellY)
        p:SetSize(cellW, CARD_H)
        p:SetFrameLevel(base + 1)
        p:Show()

        -- eye = info: shows the option's help tooltip
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
            widget:SetFrameLevel(base + 4)
            local wh = widget:GetHeight() or 22
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT",
                cellX + 10 + lead, cellY - math.floor((CARD_H - wh) / 2))
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

-- Full-width rows that get a card + (optional) gear/eye icons
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
        y = y - 12  -- breathing room above section labels
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

        -- right-aligned icon cluster: gear (extra settings) then eye (info)
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

        local yOff = y
        if item.type == "slider" then
            yOff = y - 14
        else
            -- fill the row up to the icon cluster so the control right-aligns
            widget:SetWidth(math.max(120, availW - 20 - nIcons * 21))
        end
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 10, yOff)

        y = y - h - CARD_GAP
        if expanded and item.subOptions then
            y = placeItemList(parent, item.subOptions, y)
        end
        return y
    end

    -- standalone buttons sit on their own card too, so nothing floats
    -- frameless next to the carded rows
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

    -- descriptions / tips: breathing room above and below so the text never
    -- hugs the card it follows
    if item.type == "desc" then
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y - 5)
        return y - h - 10
    end

    -- headers: no card
    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
    return y - h
end

-- Gather runs of consecutive compact controls into 2-column rows. Items with
-- extra settings (subOptions) break out to full-width rows (with the gear).
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

function UI:PlaceGroup(parent, group, y)
    local layout = group.layout or "row"
    local items  = group.items or {}
    local availW = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING
    local base   = parent:GetFrameLevel()

    -- Full-width card behind the whole group row
    local panel = (group.noCard ~= true) and makePanel(parent) or nil
    if panel then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
        panel:SetFrameLevel(base + 1)
        panel:Show()
    end

    if layout == "row" then
        -- create + measure all items first, so a button/toggle-only row can be
        -- centred (input/dropdown rows stay left-aligned, which reads better)
        local placed, totalW = {}, 0
        local gap = group.gap or 8
        for i, item in ipairs(items) do
            local widget, h, w = createWidget(parent, item)
            if widget then
                placed[#placed + 1] = { widget = widget, w = w, h = h, item = item }
                totalW = totalW + w + (i > 1 and gap or 0)
            end
        end

        -- card height + true vertical centring use the ACTUAL widget heights
        -- (the createWidget row estimate differs from e.g. a 26px button)
        local maxWH = 0
        for _, p in ipairs(placed) do
            p.wh = p.widget:GetHeight() or p.h
            if p.wh > maxWH then maxWH = p.wh end
        end
        local PAD   = CARD_VPAD
        local cardH = maxWH + PAD * 2

        -- left-aligned by default (grows rightward as items are added);
        -- a group can opt into centering with align = "center"
        local startX = CONTENT_PADDING + 10
        if group.align == "center" then
            startX = CONTENT_PADDING + math.max(10, math.floor((availW - totalW) / 2))
        end

        local cursorX = startX
        for _, p in ipairs(placed) do
            if panel then p.widget:SetFrameLevel(base + 4) end
            local yo = y - PAD - math.floor((maxWH - p.wh) / 2)
            if p.item.type == "slider" then yo = y - 14 end
            p.widget:SetPoint("TOPLEFT", parent, "TOPLEFT", cursorX, yo)
            cursorX = cursorX + p.w + gap
        end
        if panel then panel:SetSize(availW, cardH) end
        return y - cardH - CARD_GAP

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
                    if panel then widget:SetFrameLevel(base + 4) end
                    local xo = CONTENT_PADDING + (panel and 6 or 0) + (i - 1) * colWidth
                    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", xo, curY - (panel and 4 or 0))
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

    if panel then panel:Hide() end  -- unknown layout: no card
    return y
end

-- =========================================================
-- Main function
-- =========================================================
-- True if a module's options are currently on screen — directly, or as the
-- active tab of a container it was consolidated into (parentTab).
function UI:IsModuleActive(key)
    if UI.currentModule == key then return true end
    local m = ns.modules[key]
    return (m and m.parentTab and UI.currentModule == m.parentTab
            and UI.currentTab == key) and true or false
end

function UI:BuildOptionsPage(key, tabId)
    local f = UI.mainFrame
    if not f then return end
    -- A consolidated sub-module redirects to its container + its own tab, so
    -- the sub-module's rebuildPage("itskey") calls keep working.
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
