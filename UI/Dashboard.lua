-- =========================================================
-- VuloClassicUI / UI / Dashboard
-- Home screen shown when the config window opens: a card grid of every
-- module with an icon, name and an on/off switch — toggle and overview at
-- a glance. Click a card to jump into that module's settings.
-- =========================================================
local _, ns = ...
local L = ns.L
ns.UI = ns.UI or {}
local UI = ns.UI

local CARD_W      = 232
local CARD_H      = 58
local CARD_GAP_X  = 12
local CARD_GAP_Y  = 12
local PAD         = 14
local COLS        = 2

UI.DASHBOARD_KEY = "__dashboard__"

-- Groups shown on the dashboard, in order (matches the sidebar)
local GROUP_ORDER = { "Global", "Unit Frames", "PvP", "QoL", "UI Reskin", "Bugfixes" }
local HIDDEN_GROUPS = { ["_hidden"] = true, ["Account"] = true, ["Core"] = true }

UI._dashChildren = {}

local function clearDashboard(parent)
    -- Clear ALL children + regions of the scroll child, not just our tracked
    -- cards — the previous module's content frames live here too and would
    -- otherwise overlap the dashboard.
    for _, child in ipairs({ parent:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
        child:ClearAllPoints()
    end
    for _, r in ipairs({ parent:GetRegions() }) do
        if r.SetText then r:SetText("") end
        r:Hide()
        r:ClearAllPoints()
    end
    UI._dashChildren = {}
end

-- =========================================================
-- One module card
-- =========================================================
local function createCard(parent, key, mod)
    local card = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    card:SetSize(CARD_W, CARD_H)

    local UIW = ns.UI
    local borderDark = ns.COLORS.borderDark or ns.COLORS.border

    if card.SetBackdrop then
        card:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        card:SetBackdropColor(0.09, 0.09, 0.115, 0.95)
        card:SetBackdropBorderColor(borderDark.r, borderDark.g, borderDark.b, 1)
    end

    -- Subtle vertical gradient over the card body (lighter towards the top)
    local gloss = card:CreateTexture(nil, "BORDER")
    gloss:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    gloss:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -1, 1)
    UIW.SetGradient(gloss, "VERTICAL",
        0.085, 0.085, 0.105, 1,
        0.125, 0.125, 0.155, 1)

    -- Accent edge on the left while the module is enabled
    local edge = card:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    edge:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
    edge:SetWidth(3)
    edge:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.9)
    card.edge = edge

    -- Hover: accent border + soft highlight
    local hl = card:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(card)
    hl:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.06)
    card:HookScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.9)
        end
    end)
    card:HookScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(borderDark.r, borderDark.g, borderDark.b, 1)
        end
    end)

    -- Icon
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", card, "LEFT", 11, 0)
    icon:SetTexture(ns:GetModuleIcon(key))
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.icon = icon

    -- Name
    local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UIW.Font(name, 12)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    name:SetPoint("RIGHT", card, "RIGHT", -44, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetText(L[mod.name])
    card.nameFS = name

    -- Status: small colored dot + text under the name
    local dot = card:CreateTexture(nil, "OVERLAY")
    dot:SetSize(6, 6)
    dot:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 1, -7)
    card.dot = dot

    local status = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    UIW.Font(status, 10)
    status:SetPoint("LEFT", dot, "RIGHT", 4, 0)
    status:SetPoint("RIGHT", card, "RIGHT", -44, 0)
    status:SetJustifyH("LEFT")
    card.statusFS = status

    -- Power toggle (right)
    local power
    if not mod.noToggle then
        power = UI:CreatePowerButton(card, {
            size = 16,
            get  = mod.toggleGet or function() return mod.db and mod.db.enabled end,
            set  = function(v)
                if mod.toggleSet then mod.toggleSet(v) else ns:ToggleModule(key, v) end
                if card._refresh then card._refresh() end
                UI:RefreshSidebarStates()
            end,
            tooltip = L["Enable/disable module"],
        })
        power:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        card.power = power
    end

    local function refresh()
        local enabled
        if mod.toggleGet then enabled = mod.toggleGet() else enabled = mod.db and mod.db.enabled end
        if enabled then
            icon:SetDesaturated(false); icon:SetAlpha(1)
            name:SetTextColor(1, 1, 1)
            dot:SetColorTexture(0.36, 0.78, 0.36, 1)
            status:SetText(L["Active"])
            status:SetTextColor(0.55, 0.78, 0.55)
            edge:Show()
        else
            icon:SetDesaturated(true); icon:SetAlpha(0.45)
            name:SetTextColor(ns.COLORS.textMuted.r, ns.COLORS.textMuted.g, ns.COLORS.textMuted.b)
            dot:SetColorTexture(0.42, 0.42, 0.48, 1)
            status:SetText(L["Disabled"])
            status:SetTextColor(ns.COLORS.textMuted.r, ns.COLORS.textMuted.g, ns.COLORS.textMuted.b)
            edge:Hide()
        end
        if power and power._refresh then power._refresh() end
    end
    card._refresh = refresh
    refresh()

    -- Click the card body (not the toggle) → open module settings
    card:RegisterForClicks("LeftButtonUp")
    card:SetScript("OnClick", function()
        UI:ShowModulePage(key)
    end)

    return card
end

-- =========================================================
-- Build the dashboard into the content scroll area
-- =========================================================
function UI:ShowDashboard()
    local f = UI.mainFrame
    if not f then return end

    UI.currentModule = UI.DASHBOARD_KEY
    UI.currentTab    = nil

    -- Hide the tab bar; content fills the whole right pane (like a no-tab module)
    if f.tabBar then f.tabBar:Hide() end
    -- Remove any leftover tab buttons
    if f.tabs then
        for _, tab in ipairs(f.tabs) do tab:Hide(); tab:SetParent(nil) end
        f.tabs = {}
    end
    f.content:ClearAllPoints()
    f.content:SetPoint("TOPLEFT",     f.sidebar, "TOPRIGHT",  1, 0)
    f.content:SetPoint("BOTTOMRIGHT", f,         "BOTTOMRIGHT", 0, 44)

    local parent = f.scrollChild
    clearDashboard(parent)
    parent:SetWidth((f.scroll:GetWidth() or 540) - 8)
    if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end

    -- Reflect selection in the sidebar (deselect all module rows)
    if UI.RefreshSidebarStates then UI:RefreshSidebarStates() end

    local y = -10

    -- Title + summary
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.Font(title, 16)
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    title:SetText(L["Overview"])
    title:SetTextColor(0.92, 0.90, 0.96)
    table.insert(UI._dashChildren, title)

    -- Count active modules
    local total, active = 0, 0
    for _, key in ipairs(ns.moduleOrder) do
        local m = ns.modules[key]
        if m and not (HIDDEN_GROUPS[m.group or "Core"]) and not m.noToggle then
            total = total + 1
            if m.db and m.db.enabled then active = active + 1 end
        end
    end

    local summary = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(summary, 11)
    summary:SetPoint("LEFT", title, "RIGHT", 12, -1)
    summary:SetText(string.format(L["%d of %d modules active"], active, total))
    summary:SetTextColor(ns.COLORS.textDim.r, ns.COLORS.textDim.g, ns.COLORS.textDim.b)
    table.insert(UI._dashChildren, summary)

    y = y - 30

    -- Bucket modules by group
    local buckets = {}
    for _, key in ipairs(ns.moduleOrder) do
        local m = ns.modules[key]
        local g = m.group or "Core"
        if not HIDDEN_GROUPS[g] then
            buckets[g] = buckets[g] or {}
            table.insert(buckets[g], key)
        end
    end

    -- Append any groups not in GROUP_ORDER
    local order = {}
    local seen = {}
    for _, g in ipairs(GROUP_ORDER) do
        if buckets[g] then table.insert(order, g); seen[g] = true end
    end
    for g in pairs(buckets) do
        if not seen[g] then table.insert(order, g) end
    end

    -- Render each group: a section label, then a grid of cards
    for _, g in ipairs(order) do
        local keys = buckets[g]
        if keys and #keys > 0 then
            -- Group label (muted — accent is reserved for active states)
            local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            UI.Font(hdr, 10)
            hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
            hdr:SetText(string.upper(L[g]))
            hdr:SetTextColor(ns.COLORS.sectionHdr.r, ns.COLORS.sectionHdr.g, ns.COLORS.sectionHdr.b)
            table.insert(UI._dashChildren, hdr)
            y = y - 20

            -- Cards grid
            for i, key in ipairs(keys) do
                local mod = ns.modules[key]
                local card = createCard(parent, key, mod)
                local col = (i - 1) % COLS
                local row = math.floor((i - 1) / COLS)
                card:SetPoint("TOPLEFT", parent, "TOPLEFT",
                    PAD + col * (CARD_W + CARD_GAP_X),
                    y - row * (CARD_H + CARD_GAP_Y))
                table.insert(UI._dashChildren, card)
            end

            local rows = math.ceil(#keys / COLS)
            y = y - rows * (CARD_H + CARD_GAP_Y) - 8
        end
    end

    parent:SetHeight(math.max(-y + 20, 100))
end
