-- =========================================================
-- VuloClassicUI / UI / MainFrame
-- EUI-inspiriertes Hauptfenster:
--   ┌─────────────────────────────────────────────────────┐
--   │ Title                                             X │
--   ├──────────┬──────────────────────────────────────────┤
--   │ Sidebar  │  Tabs: General | Profiles | Fonts ...   │
--   │          ├──────────────────────────────────────────┤
--   │          │  Scrollable Content                      │
--   │          │                                          │
--   ├──────────┴──────────────────────────────────────────┤
--   │ [Reset]  [Reload]                          [Done]   │
--   └─────────────────────────────────────────────────────┘
-- =========================================================
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

local FRAME_WIDTH   = 820
local FRAME_HEIGHT  = 540
local SIDEBAR_WIDTH = 200
local TITLEBAR_H    = 32
local BOTTOMBAR_H   = 44
local TABBAR_H      = 32

function UI:CreateMainFrame()
    if UI.mainFrame then return UI.mainFrame end

    local f = CreateFrame("Frame", "VuloClassicUIMainFrame", UIParent)
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()

    -- Saubere Backdrop ohne Tooltip-Look
    UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.border })

    -- Position aus DB
    local pos = (ns.db and ns.db.profile.ui.mainFramePos) or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)

    -- ESC schließt
    tinsert(UISpecialFrames, "VuloClassicUIMainFrame")

    -- Klick irgendwo aufs Fenster schließt offene Dropdown-Popups
    f:SetScript("OnMouseDown", function()
        if _G.VCDropdownPopup and _G.VCDropdownPopup:IsShown() then
            _G.VCDropdownPopup:Hide()
        end
    end)

    -- =========================================================
    -- Title-Bar (draggable)
    -- =========================================================
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(TITLEBAR_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint(1)
        if ns.db and ns.db.profile and ns.db.profile.ui then
            ns.db.profile.ui.mainFramePos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    -- Title-Hintergrund (etwas dunkler)
    UI.SetColorBG(titleBar, 0.04, 0.04, 0.05, 1)

    -- Title-Text
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    title:SetText("|cff9b6cffVuloClassicUI|r")

    local version = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 6, -1)
    version:SetText("v" .. ns.VERSION)

    -- Close-Button (rechts)
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -8, 0)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeText:SetText("×")
    closeText:SetTextColor(0.7, 0.7, 0.7)
    -- Font-Größe explizit setzen (GameFontNormalLarge ist ~16, wir wollen 24)
    local font, _, flags = closeText:GetFont()
    if font then closeText:SetFont(font, 24, flags or "") end
    closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.3, 0.3) end)
    closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(0.7, 0.7, 0.7) end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Trenn-Linie unter Titel
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    sep:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)

    -- =========================================================
    -- Sidebar (links)
    -- =========================================================
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT",    sep, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", f,   "BOTTOMLEFT", 0, BOTTOMBAR_H)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    UI.SetColorBG(sidebar, ns.COLORS.bgLight.r, ns.COLORS.bgLight.g, ns.COLORS.bgLight.b, 1)

    -- Sidebar-Trenn-Linie rechts
    local sidebarSep = f:CreateTexture(nil, "ARTWORK")
    sidebarSep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    sidebarSep:SetPoint("TOPLEFT",    sidebar, "TOPRIGHT", 0, 0)
    sidebarSep:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarSep:SetWidth(1)

    -- Sidebar-ScrollFrame (für lange Modul-Listen)
    local sidebarScroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    sidebarScroll:SetPoint("TOPLEFT",     sidebar, "TOPLEFT",     6, -6)
    sidebarScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -14, 6)
    local sidebarContent = CreateFrame("Frame", nil, sidebarScroll)
    sidebarContent:SetSize(SIDEBAR_WIDTH - 22, 10)
    sidebarScroll:SetScrollChild(sidebarContent)
    UI.StyleScrollbar(sidebarScroll)

    f.sidebar         = sidebar
    f.sidebarContent  = sidebarContent
    f.sidebarScroll   = sidebarScroll

    -- =========================================================
    -- Tab-Bar (oben rechts, über Content)
    -- =========================================================
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT",  sidebar,  "TOPRIGHT", 1, 0)
    tabBar:SetPoint("TOPRIGHT", f,        "TOPRIGHT", 0, -TITLEBAR_H - 1)
    tabBar:SetHeight(TABBAR_H)
    UI.SetColorBG(tabBar, ns.COLORS.bgContent.r, ns.COLORS.bgContent.g, ns.COLORS.bgContent.b, 1)

    local tabSep = f:CreateTexture(nil, "ARTWORK")
    tabSep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    tabSep:SetPoint("TOPLEFT",  tabBar, "BOTTOMLEFT",  0, 0)
    tabSep:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    tabSep:SetHeight(1)

    f.tabBar = tabBar
    f.tabs   = {}

    -- =========================================================
    -- Content (rechts unter Tabs)
    -- =========================================================
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     tabBar,  "BOTTOMLEFT",  0, -1)
    content:SetPoint("BOTTOMRIGHT", f,       "BOTTOMRIGHT", 0, BOTTOMBAR_H)
    UI.SetColorBG(content, ns.COLORS.bgContent.r, ns.COLORS.bgContent.g, ns.COLORS.bgContent.b, 1)

    f.content = content

    -- Scroll innerhalb Content
    local scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     content, "TOPLEFT",     8,  -8)
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 8)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)
    UI.StyleScrollbar(scroll)
    f.scroll      = scroll
    f.scrollChild = scrollChild

    -- =========================================================
    -- Bottom-Bar
    -- =========================================================
    local bottomBar = CreateFrame("Frame", nil, f)
    bottomBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    bottomBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    bottomBar:SetHeight(BOTTOMBAR_H)
    UI.SetColorBG(bottomBar, 0.04, 0.04, 0.05, 1)

    local bottomSep = f:CreateTexture(nil, "ARTWORK")
    bottomSep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    bottomSep:SetPoint("BOTTOMLEFT",  bottomBar, "TOPLEFT",  0, 0)
    bottomSep:SetPoint("BOTTOMRIGHT", bottomBar, "TOPRIGHT", 0, 0)
    bottomSep:SetHeight(1)

    -- Reset (links)
    local resetBtn = UI:CreateButton(bottomBar, {
        label = "Reset Module", width = 130, height = 26,
        tooltip = "Setzt alle Einstellungen des aktuellen Moduls auf Defaults zurück.",
        onClick = function()
            if not UI.currentModule then return end
            local mod = ns.modules[UI.currentModule]
            if not mod then return end
            -- Modul-Defaults rekursiv kopieren
            for k, v in pairs(mod.defaults or {}) do
                if type(v) == "table" then
                    mod.db[k] = ns:DeepCopy(v)
                else
                    mod.db[k] = v
                end
            end
            UI:BuildOptionsPage(UI.currentModule)
            UI:RefreshSidebarStates()
            ns:Print("Modul '%s' zurückgesetzt.", mod.name)
        end,
    })
    resetBtn:SetPoint("LEFT", bottomBar, "LEFT", 10, 0)

    -- Reload UI
    local reloadBtn = UI:CreateButton(bottomBar, {
        label = "Reload UI", width = 100, height = 26,
        tooltip = "Lädt die WoW-UI komplett neu (/reload).",
        onClick = function() ReloadUI() end,
    })
    reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)

    -- Done (rechts, primary)
    local doneBtn = UI:CreateButton(bottomBar, {
        label = "Done", width = 90, height = 26, primary = true,
        onClick = function() f:Hide() end,
    })
    doneBtn:SetPoint("RIGHT", bottomBar, "RIGHT", -10, 0)

    UI.mainFrame = f
    return f
end

-- =========================================================
-- Tab-System
-- =========================================================
-- Tabs werden für das aktuelle Modul gebaut. Default: ein einziger Tab "Settings".
-- Module können in mod.tabs = { {id="general", label="General"}, ... } definieren.
function UI:BuildTabsForModule(key)
    local f = UI.mainFrame
    if not f then return end
    local mod = ns.modules[key]

    -- Alte Tabs entfernen
    for _, tab in ipairs(f.tabs) do
        tab:Hide()
        tab:SetParent(nil)
    end
    f.tabs = {}

    -- Tab-Definitionen ermitteln
    local tabs = (mod and mod.tabs) or { { id = "default", label = "Settings" } }
    local hasRealTabs = mod and mod.tabs and #mod.tabs > 1

    -- Wenn nur Default-Tab: Tab-Bar ausblenden, Content nach oben ziehen
    if not hasRealTabs then
        f.tabBar:Hide()
        f.content:ClearAllPoints()
        f.content:SetPoint("TOPLEFT",     f.sidebar, "TOPRIGHT",  1, 0)
        f.content:SetPoint("BOTTOMRIGHT", f,         "BOTTOMRIGHT", 0, 44)  -- bottombar height
        UI.currentTab = "default"
        UI:BuildOptionsPage(key, "default")
        return
    end

    f.tabBar:Show()
    f.content:ClearAllPoints()
    f.content:SetPoint("TOPLEFT",     f.tabBar, "BOTTOMLEFT",  0, -1)
    f.content:SetPoint("BOTTOMRIGHT", f,        "BOTTOMRIGHT", 0, 44)

    local x = 12
    for i, tabDef in ipairs(tabs) do
        local tab = CreateFrame("Button", nil, f.tabBar)
        tab:SetSize(0, 28)

        local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER", tab, "CENTER", 0, 0)
        text:SetText(tabDef.label)

        local fontW = text:GetStringWidth() + 24
        tab:SetWidth(math.max(60, fontW))
        tab:SetPoint("BOTTOMLEFT", f.tabBar, "BOTTOMLEFT", x, 0)
        x = x + tab:GetWidth() + 4

        local underline = tab:CreateTexture(nil, "OVERLAY")
        underline:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        underline:SetHeight(2)
        underline:SetPoint("BOTTOMLEFT",  tab, "BOTTOMLEFT", 6, 0)
        underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 0)
        underline:Hide()

        tab._underline = underline
        tab._text      = text
        tab._tabId     = tabDef.id

        tab:SetScript("OnEnter", function()
            if UI.currentTab ~= tabDef.id then
                text:SetTextColor(1, 1, 1)
            end
        end)
        tab:SetScript("OnLeave", function()
            if UI.currentTab ~= tabDef.id then
                local c = ns.COLORS.textDim
                text:SetTextColor(c.r, c.g, c.b)
            end
        end)
        tab:SetScript("OnClick", function()
            UI:ShowTab(tabDef.id)
        end)

        table.insert(f.tabs, tab)
    end

    if tabs[1] then UI:ShowTab(tabs[1].id) end
end

function UI:ShowTab(tabId)
    UI.currentTab = tabId
    local f = UI.mainFrame
    for _, tab in ipairs(f.tabs) do
        if tab._tabId == tabId then
            tab._underline:Show()
            tab._text:SetTextColor(1, 1, 1)
        else
            tab._underline:Hide()
            local c = ns.COLORS.textDim
            tab._text:SetTextColor(c.r, c.g, c.b)
        end
    end
    -- Content für diesen Tab rendern
    if UI.currentModule then
        UI:BuildOptionsPage(UI.currentModule, tabId)
    end
end

function UI:ToggleMainFrame()
    local f = UI:CreateMainFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        UI:PopulateSidebar()
        if not UI.currentModule and ns.moduleOrder[1] then
            UI:ShowModulePage(ns.moduleOrder[1])
        end
    end
end
