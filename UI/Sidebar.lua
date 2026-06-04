-- =========================================================
-- VuloClassicUI / UI / Sidebar
-- EUI style: modules are listed under group headers (Core, QoL, Reskin, ...).
-- On the right of each entry: power button to enable/disable.
-- =========================================================
local _, ns = ...
local L = ns.L
ns.UI = ns.UI or {}
local UI = ns.UI

local ROW_HEIGHT     = 28
local GROUP_HEADER_H = 26
local GROUP_GAP      = 8

-- Per-module icons (Blizzard textures available in TBC Classic).
-- Unknown keys fall back to MODULE_ICON_FALLBACK.
local MODULE_ICONS = {
    globalsettings     = "Interface\\Icons\\Trade_Engineering",
    profiles           = "Interface\\Icons\\INV_Misc_Note_03",
    minimap            = "Interface\\Icons\\INV_Misc_Map_01",
    fontbars           = "Interface\\Icons\\INV_Misc_Note_01",
    playercastbar      = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    cooldownpulse      = "Interface\\Icons\\Spell_Nature_TimeStop",
    arenaframes        = "Interface\\Icons\\Achievement_Arena_2v2_1",
    characterpanel     = "Interface\\Icons\\INV_Chest_Plate06",
    buttonskin         = "Interface\\Icons\\INV_Misc_EngGizmos_27",
    miscqol            = "Interface\\Icons\\Trade_BlackSmithing",
    queuetimer         = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    tooltipids         = "Interface\\Icons\\INV_Misc_QuestionMark",
    autoitembuy        = "Interface\\Icons\\INV_Misc_Coin_01",
    goldtracker        = "Interface\\Icons\\INV_Misc_Coin_05",
    spamfilter         = "Interface\\Icons\\Spell_Holy_Silence",
    questlog           = "Interface\\Icons\\INV_Misc_Book_09",
    professionwindow   = "Interface\\Icons\\Trade_Tailoring",
    disenchantqueue    = "Interface\\Icons\\INV_Enchant_Disenchant",
    vtmanadisplay      = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    combattext         = "Interface\\Icons\\Ability_Warrior_BattleShout",
    loadouts           = "Interface\\Icons\\INV_Chest_Chain",
    slotpicker         = "Interface\\Icons\\INV_Misc_Bag_08",
    trinkets           = "Interface\\Icons\\INV_Misc_Gem_Variety_01",
    fixinspect         = "Interface\\Icons\\INV_Misc_Spyglass_02",
    fixlfgbrowsenil    = "Interface\\Icons\\INV_Misc_GroupLooking",
    fixguildnews       = "Interface\\Icons\\INV_Scroll_03",
    fixauctiondropdown = "Interface\\Icons\\INV_Misc_Coin_02",
    fixbindsocket      = "Interface\\Icons\\INV_Misc_Gem_Diamond_02",
    fixcombatglow      = "Interface\\Icons\\Ability_Warrior_Challange",
}
local MODULE_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_Gear_01"

-- Expose for the dashboard (and anything else that needs per-module icons)
ns.MODULE_ICONS = MODULE_ICONS
ns.MODULE_ICON_FALLBACK = MODULE_ICON_FALLBACK
function ns:GetModuleIcon(key)
    return MODULE_ICONS[key] or MODULE_ICON_FALLBACK
end

UI.sidebarButtons     = {}
UI.sidebarGroupOrder  = { "Global", "Unit Frames", "PvP", "QoL", "UI Reskin", "Bugfixes" }  -- desired order
UI.sidebarHiddenGroups = { ["_hidden"] = true, ["Account"] = true, ["Core"] = true }  -- not shown in sidebar
UI.sidebarGroupBuckets = {}

local function highlightSelected()
    -- Dashboard row (separate from module rows)
    if UI._dashRow then
        local onDash = (UI.currentModule == UI.DASHBOARD_KEY)
        if onDash then UI._dashRow.bg:Show(); UI._dashRow.accentBar:Show()
        else UI._dashRow.bg:Hide(); UI._dashRow.accentBar:Hide() end
    end

    for key, btn in pairs(UI.sidebarButtons) do
        local selected = (key == UI.currentModule)
        if selected then
            btn.bg:Show()
            if btn.accentBar then btn.accentBar:Show() end
            btn.label:SetTextColor(1, 1, 1)
        else
            btn.bg:Hide()
            if btn.accentBar then btn.accentBar:Hide() end
            local c = ns.COLORS.textDim
            btn.label:SetTextColor(c.r, c.g, c.b)
        end

        -- Dim the icon + label of disabled modules so on/off is readable at a glance
        local mod = ns.modules[key]
        local enabled
        if mod and mod.toggleGet then enabled = mod.toggleGet()
        else enabled = mod and mod.db and mod.db.enabled end
        if btn.icon then
            if enabled then
                btn.icon:SetDesaturated(false)
                btn.icon:SetAlpha(1)
            else
                btn.icon:SetDesaturated(true)
                btn.icon:SetAlpha(0.4)
            end
        end
        if not selected and not enabled then
            btn.label:SetTextColor(ns.COLORS.textMuted.r, ns.COLORS.textMuted.g, ns.COLORS.textMuted.b)
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

    -- Accent bar on the left edge (shown when selected)
    local accentBar = row:CreateTexture(nil, "ARTWORK")
    accentBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    accentBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    accentBar:SetWidth(3)
    accentBar:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    accentBar:Hide()
    row.accentBar = accentBar

    -- Hover
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(row)
    hover:SetColorTexture(1, 1, 1, 0.05)

    -- Module icon (left)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    icon:SetTexture(MODULE_ICONS[key] or MODULE_ICON_FALLBACK)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- crop default border
    row.icon = icon

    -- Power button on the right (toggle) - unless module marks itself as noToggle
    local power
    if not mod.noToggle then
        power = UI:CreatePowerButton(row, {
            size = 13,
            get = mod.toggleGet or function() return mod.db and mod.db.enabled end,
            set = mod.toggleSet or function(v)
                ns:ToggleModule(key, v)
                UI:RefreshSidebarStates()
            end,
            tooltip = L["Enable/disable module"],
        })
        power:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.power = power
    end

    -- Label (between icon and power button) — truncates instead of overlapping
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    if power then
        label:SetPoint("RIGHT", power, "LEFT", -6, 0)
    else
        label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    end
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)  -- single line, truncates with "..." if too long
    label:SetText(L[mod.name])  -- mod.name is a raw English key; translate live
    row.label = label

    row:SetScript("OnClick", function()
        UI:ShowModulePage(key)
    end)

    return row
end

local function createGroupHeader(parent, groupName)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(GROUP_HEADER_H)

    -- Uppercase, slightly smaller — reads as a section label
    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 8, 4)
    fs:SetText(string.upper(L[groupName]))
    local c = ns.COLORS.accent
    fs:SetTextColor(c.r, c.g, c.b)

    -- Thin separator line under the header
    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 8, 0)
    line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -8, 0)
    line:SetHeight(1)
    line:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.25)

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

    -- "Overview" entry at the very top → opens the dashboard
    do
        local row = CreateFrame("Button", nil, parent)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.18)
        bg:Hide()
        row.bg = bg

        local accentBar = row:CreateTexture(nil, "ARTWORK")
        accentBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        accentBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        accentBar:SetWidth(3)
        accentBar:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        accentBar:Hide()
        row.accentBar = accentBar

        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(row)
        hover:SetColorTexture(1, 1, 1, 0.05)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", row, "LEFT", 8, 0)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Book_03")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
        label:SetText(L["Overview"])

        row:SetScript("OnClick", function()
            if UI.ShowDashboard then UI:ShowDashboard() end
        end)

        UI._sidebarChildren = UI._sidebarChildren or {}
        table.insert(UI._sidebarChildren, row)
        UI._dashRow = row
        y = y + ROW_HEIGHT + GROUP_GAP
    end

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
