-- =========================================================
-- VuloClassicUI / UI / Sidebar
-- VuloUI style: modules are listed under group headers (Core, QoL, Reskin, ...).
-- On the right of each entry: power button to enable/disable.
-- =========================================================
local _, ns = ...
local L = ns.L
ns.UI = ns.UI or {}
local UI = ns.UI

local ROW_HEIGHT     = 28
local GROUP_HEADER_H = 26
local GROUP_GAP      = 8

-- Per-module icons: our own bundled monochrome glyph set (white line art,
-- tinted at runtime — gray idle / accent selected). Rasterized from a freely
-- ISC-licensed icon set; see Media\Icons\modules\LICENSE.txt.
-- Unknown keys fall back to MODULE_ICON_FALLBACK.
local ICON_DIR = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\"
local MODULE_ICONS = {}
for _, key in ipairs({
    "globalsettings", "unlockmode", "qol", "bugfixes", "profiles",
    "minimap", "minimapstyle", "fontbars", "playercastbar", "unitframes",
    "cooldownpulse", "cooldownmanager", "powerbar",
    "arenaframes", "characterpanel", "buttonskin", "darkmode", "friendlist",
    "miscqol", "queuetimer", "tooltipids", "autoitembuy", "goldtracker",
    "goldvendors", "spamfilter", "chat", "bags", "questlog",
    "professionwindow", "disenchantqueue", "vtmanadisplay", "lazyvulo",
    "vulslot", "combattext", "loadouts", "slotpicker", "trinkets",
    "swingtimer", "vulmail", "vulfishing", "vullfg", "vultraining",
    "fixinspect", "fixlfgbrowsenil", "fixguildnews", "fixauctiondropdown",
    "fixbindsocket", "fixcombatglow",
}) do
    MODULE_ICONS[key] = ICON_DIR .. key .. ".tga"
end
local MODULE_ICON_FALLBACK = ICON_DIR .. "_fallback.tga"

-- Expose for the dashboard (and anything else that needs per-module icons)
ns.MODULE_ICONS = MODULE_ICONS
ns.MODULE_ICON_FALLBACK = MODULE_ICON_FALLBACK
function ns:GetModuleIcon(key)
    return MODULE_ICONS[key] or MODULE_ICON_FALLBACK
end

UI.sidebarButtons     = {}
UI.sidebarGroupOrder  = { "Global", "Unit Frames", "HUD", "PvP", "QoL", "UI Reskin", "Bugfixes" }  -- desired order
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

        -- Uniform monochrome icon set: every icon desaturated, tinted by state
        -- (selected = accent, enabled = light gray, disabled = dim gray). One
        -- consistent style instead of mixed full-color spell art.
        local mod = ns.modules[key]
        local enabled
        if mod and mod.toggleGet then enabled = mod.toggleGet()
        else enabled = mod and ns:IsModuleEnabled(key) end
        if btn.icon then
            btn.icon:SetDesaturated(true)
            if selected then
                local a = ns.COLORS.accent
                btn.icon:SetVertexColor(a.r, a.g, a.b)
                btn.icon:SetAlpha(1)
            elseif enabled then
                btn.icon:SetVertexColor(0.76, 0.76, 0.84)
                btn.icon:SetAlpha(0.95)
            else
                btn.icon:SetVertexColor(0.55, 0.55, 0.6)
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

    -- Selected background: accent gradient fading out to the right
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    ns.UI.SetGradient(bg, "HORIZONTAL",
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.26,
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.02)
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
    hover:SetColorTexture(1, 1, 1, 0.04)

    -- Module icon (left) — monochrome treatment, tinted by highlightSelected
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    icon:SetTexture(MODULE_ICONS[key] or MODULE_ICON_FALLBACK)
    -- our glyphs are full-frame white line art — no border crop needed
    icon:SetVertexColor(0.76, 0.76, 0.84, 0.95)
    row.icon = icon

    -- hover: brighten the icon (selection tint wins; restored on leave)
    row:HookScript("OnEnter", function()
        if UI.currentModule ~= key then icon:SetVertexColor(0.95, 0.95, 1) end
    end)
    row:HookScript("OnLeave", function() highlightSelected() end)

    -- Power button on the right (toggle) - unless module marks itself as noToggle
    local power
    if not mod.noToggle then
        power = UI:CreatePowerButton(row, {
            size = 13,
            get = mod.toggleGet or function() return ns:IsModuleEnabled(key) end,
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
    ns.UI.Font(label, 12)
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

    -- Uppercase, slightly smaller — reads as a section label (muted, not accent:
    -- the accent color is reserved for selection/active states)
    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.UI.Font(fs, 10)
    fs:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 8, 4)
    fs:SetText(string.upper(L[groupName]))
    local c = ns.COLORS.sectionHdr
    fs:SetTextColor(c.r, c.g, c.b)
    h._label = fs

    -- Thin separator line under the header, fading out to the right
    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 8, 0)
    line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -8, 0)
    line:SetHeight(1)
    ns.UI.SetGradient(line, "HORIZONTAL",
        0.32, 0.32, 0.38, 0.45,
        0.32, 0.32, 0.38, 0.0)

    return h
end

-- =========================================================
-- Build group buckets
-- =========================================================
local function rebuildBuckets()
    UI.sidebarGroupBuckets = {}
    local origIndex = {}   -- registration order, used as a stable-sort tiebreaker
    for i, key in ipairs(ns.moduleOrder) do
        local mod = ns.modules[key]
        origIndex[key] = i
        if not mod.parentTab then   -- consolidated sub-modules show as tabs, not rows
            local g = mod.group or "Core"
            if not UI.sidebarGroupBuckets[g] then
                UI.sidebarGroupBuckets[g] = {}
            end
            table.insert(UI.sidebarGroupBuckets[g], key)
        end
    end

    -- Stable sort each bucket by optional mod.sidebarOrder (lower = higher up);
    -- ties fall back to registration order so unset modules keep their place.
    for _, bucket in pairs(UI.sidebarGroupBuckets) do
        table.sort(bucket, function(a, b)
            local oa = ns.modules[a].sidebarOrder or 0
            local ob = ns.modules[b].sidebarOrder or 0
            if oa ~= ob then return oa < ob end
            return origIndex[a] < origIndex[b]
        end)
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

    -- Frames are POOLED and reused across opens: WoW frames are never
    -- garbage-collected, so recreating ~40 rows on every open would leak
    -- memory permanently. Hide everything, then re-show what's needed.
    if UI._sidebarChildren then
        for _, c in ipairs(UI._sidebarChildren) do c:Hide() end
    end
    UI._sidebarChildren = {}
    UI._sidebarHeaders  = UI._sidebarHeaders or {}
    UI.sidebarButtons   = UI.sidebarButtons or {}

    rebuildBuckets()

    local y = 0

    -- "Overview" entry at the very top → opens the dashboard (built once)
    do
        local row = UI._dashRow
        if not row then
            row = CreateFrame("Button", nil, parent)
            row:SetHeight(ROW_HEIGHT)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(row)
            ns.UI.SetGradient(bg, "HORIZONTAL",
                ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.26,
                ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.02)
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
            icon:SetTexture(ICON_DIR .. "_dashboard.tga")
            icon:SetVertexColor(0.76, 0.76, 0.84, 0.95)

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            ns.UI.Font(label, 12)
            label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
            row.label = label

            row:SetScript("OnClick", function()
                if UI.ShowDashboard then UI:ShowDashboard() end
            end)
            UI._dashRow = row
        end
        row.label:SetText(L["Overview"])  -- re-set: locale can change live
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
        row:Show()
        table.insert(UI._sidebarChildren, row)
        y = y + ROW_HEIGHT + GROUP_GAP
    end

    for _, groupName in ipairs(UI.sidebarGroupOrder) do
        local moduleKeys = UI.sidebarGroupBuckets[groupName]
        local hidden = UI.sidebarHiddenGroups and UI.sidebarHiddenGroups[groupName]
        if moduleKeys and #moduleKeys > 0 and not hidden then
            -- Group header (pooled per group name)
            local header = UI._sidebarHeaders[groupName]
            if not header then
                header = createGroupHeader(parent, groupName)
                UI._sidebarHeaders[groupName] = header
            end
            if header._label then header._label:SetText(string.upper(L[groupName])) end
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT",  parent, "TOPLEFT",   0, -y)
            header:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  0, -y)
            header:Show()
            table.insert(UI._sidebarChildren, header)
            y = y + GROUP_HEADER_H

            -- Module rows (pooled per module key)
            for _, key in ipairs(moduleKeys) do
                local mod = ns.modules[key]
                local row = UI.sidebarButtons[key]
                if not row then
                    row = createModuleRow(parent, key, mod)
                    UI.sidebarButtons[key] = row
                end
                row.label:SetText(L[mod.name])
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  parent, "TOPLEFT",   0, -y)
                row:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  0, -y)
                row:Show()
                table.insert(UI._sidebarChildren, row)
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
