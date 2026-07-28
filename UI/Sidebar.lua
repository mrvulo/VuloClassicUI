-- VuloClassicUI / UI / Sidebar: module list grouped under headers, each with a power toggle.
local _, ns = ...
local L = ns.L
ns.UI = ns.UI or {}
local UI = ns.UI

local ROW_HEIGHT     = 28
local GROUP_HEADER_H = 26
local GROUP_GAP      = 8

-- Bundled monochrome glyphs, tinted at runtime; see Media\Icons\modules\LICENSE.txt.
local ICON_DIR = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\"
local MODULE_ICONS = {}
for _, key in ipairs({
    -- The four "Tools" containers are not listed here: Modules/Pages.lua points
    -- them at existing glyphs itself, the way the pg_* pages already do.
    "globalsettings", "unlockmode", "bugfixes", "uireskin", "profiles",
    "minimap", "minimapstyle", "fontbars", "playercastbar", "unitframes", "nameplates",
    "cooldownpulse", "cooldownmanager", "powerbar", "actionbars",
    "arenaframes", "characterpanel", "darkskin", "friendlist",
    "miscqol", "queuetimer", "tooltipids", "autoitembuy", "goldtracker",
    "addonskins", "popupskin", "reminders",
    "spamfilter", "chat", "bags", "questlog",
    "professionwindow", "disenchantqueue", "vtmanadisplay", "lazyvulo",
    "vulslot", "combattext", "loadouts", "slotpicker", "trinkets",
    "swingtimer", "vulmail", "vulfishing", "vullfg", "vultraining",
    "fixinspect", "fixlfgbrowsenil", "fixguildnews", "fixauctiondropdown",
    "fixbindsocket", "fixcombatglow",
}) do
    MODULE_ICONS[key] = ICON_DIR .. key .. ".tga"
end
local MODULE_ICON_FALLBACK = ICON_DIR .. "_fallback.tga"

ns.MODULE_ICONS = MODULE_ICONS
ns.MODULE_ICON_FALLBACK = MODULE_ICON_FALLBACK
function ns:GetModuleIcon(key)
    return MODULE_ICONS[key] or MODULE_ICON_FALLBACK
end

UI.sidebarButtons     = {}
-- "Tools" holds the four containers that replaced the single "Quality of Life"
-- row (see Modules/Pages.lua) plus "Class Specific". The four category names
-- themselves never appear as headers: their modules carry parentTab and so are
-- collected into the container rows instead of getting rows of their own.
UI.sidebarGroupOrder  = {
    "Global", "Unit Frames", "HUD", "PvP", "Tools", "UI Reskin", "Bugfixes",
}
UI.sidebarHiddenGroups = { ["_hidden"] = true, ["Account"] = true, ["Core"] = true }
UI.sidebarGroupBuckets = {}

-- Collapsed groups are remembered per profile, and deliberately NOT declared in
-- the defaults: the logout pass in Core/Database.lua only strips keys that
-- appear in the defaults tree, so staying out of it is what keeps the state.
-- Reading must not create the table either, or every profile that never
-- collapsed anything would still save an empty one.
local function collapsedSet(create)
    local ui = ns.db and ns.db.profile and ns.db.profile.ui
    if not ui then return nil end
    if not ui.sidebarCollapsed and create then ui.sidebarCollapsed = {} end
    return ui.sidebarCollapsed
end

local function isCollapsed(groupName)
    local t = collapsedSet(false)
    return (t and t[groupName]) and true or false
end

local function moduleIsOn(key)
    local mod = ns.modules[key]
    if not mod then return false end
    if mod.toggleGet then return mod.toggleGet() and true or false end
    return ns:IsModuleEnabled(key) and true or false
end

-- "3/7": how many of the group are switched on. Without it a collapsed group
-- says nothing about whether anything inside it is running.
local function applyHeaderCount(header, moduleKeys)
    if not header or not header._count then return end
    local on = 0
    for i = 1, #moduleKeys do
        if moduleIsOn(moduleKeys[i]) then on = on + 1 end
    end
    header._count:SetText(on .. "/" .. #moduleKeys)
    local c = (on > 0) and ns.COLORS.accent or ns.COLORS.textMuted
    header._count:SetTextColor(c.r, c.g, c.b)
end

local function highlightSelected()
    if UI._dashRow then
        local onDash = (UI.currentModule == UI.DASHBOARD_KEY)
        if onDash then UI._dashRow.bg:Show(); UI._dashRow.accentBar:Show()
        else UI._dashRow.bg:Hide(); UI._dashRow.accentBar:Hide() end
    end
    if UI._changelogRow then
        local onCL = (UI.currentModule == "changelog")
        if onCL then UI._changelogRow.bg:Show(); UI._changelogRow.accentBar:Show()
        else UI._changelogRow.bg:Hide(); UI._changelogRow.accentBar:Hide() end
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
    hover:SetColorTexture(1, 1, 1, 0.04)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    icon:SetTexture(MODULE_ICONS[key] or MODULE_ICON_FALLBACK)
    icon:SetVertexColor(0.76, 0.76, 0.84, 0.95)
    row.icon = icon

    row:HookScript("OnEnter", function()
        if UI.currentModule ~= key then icon:SetVertexColor(0.95, 0.95, 1) end
    end)
    row:HookScript("OnLeave", function() highlightSelected() end)

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

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.UI.Font(label, 12)
    label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    if power then
        label:SetPoint("RIGHT", power, "LEFT", -6, 0)
    else
        label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    end
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(L[mod.name])  -- mod.name is a raw English key, translated live
    row.label = label

    row:SetScript("OnClick", function()
        UI:ShowModulePage(key)
    end)

    return row
end

local function createGroupHeader(parent, groupName)
    local h = CreateFrame("Button", nil, parent)
    h:SetHeight(GROUP_HEADER_H)

    local hover = h:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(h)
    hover:SetColorTexture(1, 1, 1, 0.03)

    -- Plus/minus rather than a rotated arrow: both textures exist in every
    -- client this addon ships for, so no rotation call and no missing glyph.
    local twist = h:CreateTexture(nil, "ARTWORK")
    twist:SetSize(11, 11)
    twist:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 7, 3)
    h._twist = twist

    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.UI.Font(fs, 10)
    fs:SetPoint("BOTTOMLEFT", twist, "BOTTOMRIGHT", 5, -1)
    fs:SetText(string.upper(L[groupName]))
    local c = ns.COLORS.sectionHdr
    fs:SetTextColor(c.r, c.g, c.b)
    h._label = fs

    local count = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.UI.Font(count, 10)
    count:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -8, 4)
    h._count = count

    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 8, 0)
    line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -8, 0)
    line:SetHeight(1)
    ns.UI.SetGradient(line, "HORIZONTAL",
        0.32, 0.32, 0.38, 0.45,
        0.32, 0.32, 0.38, 0.0)

    h._group = groupName
    h:SetScript("OnClick", function(self)
        local t = collapsedSet(true)
        if not t then return end
        -- nil rather than false when expanding, so an untouched profile stays
        -- empty instead of collecting a false for every group it ever opened.
        t[self._group] = (not t[self._group]) or nil
        UI:PopulateSidebar()
    end)

    return h
end

local function rebuildBuckets()
    UI.sidebarGroupBuckets = {}
    local origIndex = {}   -- registration order: stable-sort tiebreaker
    for i, key in ipairs(ns.moduleOrder) do
        local mod = ns.modules[key]
        origIndex[key] = i
        if not mod.parentTab then   -- sub-modules show as tabs, not rows
            local g = mod.group or "Core"
            if not UI.sidebarGroupBuckets[g] then
                UI.sidebarGroupBuckets[g] = {}
            end
            table.insert(UI.sidebarGroupBuckets[g], key)
        end
    end

    for _, bucket in pairs(UI.sidebarGroupBuckets) do
        table.sort(bucket, function(a, b)
            local oa = ns.modules[a].sidebarOrder or 0
            local ob = ns.modules[b].sidebarOrder or 0
            if oa ~= ob then return oa < ob end
            return origIndex[a] < origIndex[b]
        end)
    end

    local seen = {}
    for _, g in ipairs(UI.sidebarGroupOrder) do seen[g] = true end
    for g in pairs(UI.sidebarGroupBuckets) do
        if not seen[g] and not (UI.sidebarHiddenGroups and UI.sidebarHiddenGroups[g]) then
            table.insert(UI.sidebarGroupOrder, g)
        end
    end
end

function UI:PopulateSidebar()
    local f = UI.mainFrame
    if not f then return end
    local parent = f.sidebarContent

    -- Frames are never garbage-collected: rows are pooled and re-shown, never recreated.
    if UI._sidebarChildren then
        for _, c in ipairs(UI._sidebarChildren) do c:Hide() end
    end
    UI._sidebarChildren = {}
    UI._sidebarHeaders  = UI._sidebarHeaders or {}
    UI.sidebarButtons   = UI.sidebarButtons or {}

    rebuildBuckets()

    local y = 0

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
        row.label:SetText(L["Overview"])  -- re-set on every populate: locale can change live
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
        row:Show()
        table.insert(UI._sidebarChildren, row)
        y = y + ROW_HEIGHT + GROUP_GAP
    end

    if ns.modules and ns.modules.changelog then
        local row = UI._changelogRow
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
            icon:SetTexture(ICON_DIR .. "changelog.tga")
            icon:SetVertexColor(0.76, 0.76, 0.84, 0.95)

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            ns.UI.Font(label, 12)
            label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
            row.label = label

            local dot = row:CreateTexture(nil, "OVERLAY")
            dot:SetSize(13, 13)
            dot:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
            dot:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
            local pulse = dot:CreateAnimationGroup()
            pulse:SetLooping("REPEAT")
            local a1 = pulse:CreateAnimation("Alpha")
            a1:SetFromAlpha(1); a1:SetToAlpha(0.15); a1:SetDuration(0.7); a1:SetOrder(1); a1:SetSmoothing("IN_OUT")
            local a2 = pulse:CreateAnimation("Alpha")
            a2:SetFromAlpha(0.15); a2:SetToAlpha(1); a2:SetDuration(0.7); a2:SetOrder(2); a2:SetSmoothing("IN_OUT")
            row.dot, row.dotPulse = dot, pulse

            row:SetScript("OnClick", function(self)
                if ns.db and ns.db.global then ns.db.global.patchNotesSeen = ns.VERSION end
                if self.dotPulse then self.dotPulse:Stop() end
                if self.dot then self.dot:Hide() end
                if UI.ShowModulePage then UI:ShowModulePage("changelog") end
            end)
            UI._changelogRow = row
        end
        row.label:SetText(L[ns.modules.changelog.name])
        local unread = ns.db and ns.db.global and ns.db.global.patchNotesSeen ~= ns.VERSION
        if unread then
            row.dot:Show()
            if not row.dotPulse:IsPlaying() then row.dotPulse:Play() end
        else
            row.dotPulse:Stop()
            row.dot:Hide()
        end
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
            local header = UI._sidebarHeaders[groupName]
            if not header then
                header = createGroupHeader(parent, groupName)
                UI._sidebarHeaders[groupName] = header
            end
            if header._label then header._label:SetText(string.upper(L[groupName])) end

            -- A collapsed group that holds the page you are on would hide the
            -- selected row, so it opens itself instead of leaving you nowhere.
            local collapsed = isCollapsed(groupName)
            if collapsed then
                for _, key in ipairs(moduleKeys) do
                    if key == UI.currentModule then collapsed = false; break end
                end
            end

            if header._twist then
                header._twist:SetTexture(collapsed
                    and "Interface\\Buttons\\UI-PlusButton-Up"
                    or  "Interface\\Buttons\\UI-MinusButton-Up")
                local c = ns.COLORS.sectionHdr
                header._twist:SetVertexColor(c.r, c.g, c.b, 0.85)
            end
            applyHeaderCount(header, moduleKeys)

            header:ClearAllPoints()
            header:SetPoint("TOPLEFT",  parent, "TOPLEFT",   0, -y)
            header:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  0, -y)
            header:Show()
            table.insert(UI._sidebarChildren, header)
            y = y + GROUP_HEADER_H

            if not collapsed then
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
    -- Switching a module on or off changes its group's "3/7", including for a
    -- collapsed group whose rows are not on screen to tell the story.
    if UI._sidebarHeaders then
        for groupName, header in pairs(UI._sidebarHeaders) do
            local keys = UI.sidebarGroupBuckets and UI.sidebarGroupBuckets[groupName]
            if keys then applyHeaderCount(header, keys) end
        end
    end
    highlightSelected()
end

function UI:ShowModulePage(key)
    -- a parentTab sub-module has no row of its own: open its container, select its tab
    local m = ns.modules[key]
    local subTab
    if m and m.parentTab then
        subTab = key
        key    = m.parentTab
    end
    UI.currentModule = key
    UI.currentTab    = nil
    -- Recorded here rather than at each call site: this is the one door every
    -- page opening goes through, including the search results and the overview.
    if UI.NoteVisitedPage then UI:NoteVisitedPage(key) end
    UI:BuildTabsForModule(key)
    if subTab then UI:ShowTab(subTab) end
    highlightSelected()
end
