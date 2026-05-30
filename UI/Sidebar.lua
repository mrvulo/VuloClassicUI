-- =========================================================
-- VuloClassicUI / UI / Sidebar
-- EUI style: modules are listed under group headers (Core, QoL, Reskin, ...).
-- On the right of each entry: power button to enable/disable.
-- =========================================================
local _, ns = ...
local L = ns.L
ns.UI = ns.UI or {}
local UI = ns.UI

local ROW_HEIGHT     = 26
local GROUP_HEADER_H = 28
local GROUP_GAP      = 6

UI.sidebarButtons     = {}
UI.sidebarGroupOrder  = { "Global", "Unit Frames", "PvP", "QoL", "UI Reskin", "Bugfixes" }  -- desired order
UI.sidebarHiddenGroups = { ["_hidden"] = true, ["Account"] = true, ["Core"] = true }  -- not shown in sidebar
UI.sidebarGroupBuckets = {}

local function highlightSelected()
    for key, btn in pairs(UI.sidebarButtons) do
        if key == UI.currentModule then
            btn.bg:Show()
            btn.label:SetTextColor(1, 1, 1)
        else
            btn.bg:Hide()
            local c = ns.COLORS.textDim
            btn.label:SetTextColor(c.r, c.g, c.b)
        end
    end
end

local function createModuleRow(parent, key, mod)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    -- Selected background (transparent when not selected)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.18)
    bg:Hide()
    row.bg = bg

    -- Hover
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(row)
    hover:SetColorTexture(1, 1, 1, 0.05)

    -- Label
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", row, "LEFT", 10, 0)
    label:SetText(L[mod.name])  -- mod.name is a raw English key; translate live
    row.label = label

    -- Power button on the right (toggle) - unless module marks itself as noToggle
    if not mod.noToggle then
        local power = UI:CreatePowerButton(row, {
            get = function() return mod.db and mod.db.enabled end,
            set = function(v)
                ns:ToggleModule(key, v)
                UI:RefreshSidebarStates()
            end,
            tooltip = L["Enable/disable module"],
        })
        power:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.power = power
    end

    row:SetScript("OnClick", function()
        UI:ShowModulePage(key)
    end)

    return row
end

local function createGroupHeader(parent, groupName)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(GROUP_HEADER_H)

    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", h, "LEFT", 6, -2)
    fs:SetText(L[groupName])
    local c = ns.COLORS.accent
    fs:SetTextColor(c.r, c.g, c.b)

    return h
end

-- =========================================================
-- Build group buckets
-- =========================================================
local function rebuildBuckets()
    UI.sidebarGroupBuckets = {}
    for _, key in ipairs(ns.moduleOrder) do
        local mod = ns.modules[key]
        local g = mod.group or "Core"
        if not UI.sidebarGroupBuckets[g] then
            UI.sidebarGroupBuckets[g] = {}
        end
        table.insert(UI.sidebarGroupBuckets[g], key)
    end

    -- Groups not in the order list get appended at the end
    -- (unless explicitly hidden)
    local seen = {}
    for _, g in ipairs(UI.sidebarGroupOrder) do seen[g] = true end
    for g in pairs(UI.sidebarGroupBuckets) do
        if not seen[g] and not (UI.sidebarHiddenGroups and UI.sidebarHiddenGroups[g]) then
            table.insert(UI.sidebarGroupOrder, g)
        end
    end
end

-- =========================================================
-- Populate sidebar
-- =========================================================
function UI:PopulateSidebar()
    local f = UI.mainFrame
    if not f then return end
    local parent = f.sidebarContent

    -- Clean up old children
    if UI._sidebarChildren then
        for _, c in ipairs(UI._sidebarChildren) do
            c:Hide()
            c:SetParent(nil)
        end
    end
    UI._sidebarChildren = {}
    UI.sidebarButtons   = {}

    rebuildBuckets()

    local y = 0
    for _, groupName in ipairs(UI.sidebarGroupOrder) do
        local moduleKeys = UI.sidebarGroupBuckets[groupName]
        local hidden = UI.sidebarHiddenGroups and UI.sidebarHiddenGroups[groupName]
        if moduleKeys and #moduleKeys > 0 and not hidden then
            -- Group header
            local header = createGroupHeader(parent, groupName)
            header:SetPoint("TOPLEFT",  parent, "TOPLEFT",   0, -y)
            header:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  0, -y)
            table.insert(UI._sidebarChildren, header)
            y = y + GROUP_HEADER_H

            -- Module rows
            for _, key in ipairs(moduleKeys) do
                local mod = ns.modules[key]
                local row = createModuleRow(parent, key, mod)
                row:SetPoint("TOPLEFT",  parent, "TOPLEFT",   0, -y)
                row:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  0, -y)
                table.insert(UI._sidebarChildren, row)
                UI.sidebarButtons[key] = row
                y = y + ROW_HEIGHT
            end

            y = y + GROUP_GAP
        end
    end

    parent:SetHeight(math.max(y + 10, 100))

    highlightSelected()
end

function UI:RefreshSidebarStates()
    for key, row in pairs(UI.sidebarButtons) do
        if row.power and row.power._refresh then
            row.power._refresh()
        end
    end
    highlightSelected()
end

function UI:ShowModulePage(key)
    UI.currentModule = key
    UI.currentTab    = nil
    UI:BuildTabsForModule(key)
    -- BuildTabsForModule eventually calls ShowTab(firstTabId), which triggers BuildOptionsPage
    highlightSelected()
end
