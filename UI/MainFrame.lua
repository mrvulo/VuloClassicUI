-- =========================================================
-- VuloClassicUI / UI / MainFrame
-- EUI-inspired main window:
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

    -- Clean backdrop without tooltip look
    UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.border })

    -- Position from DB (with full nil-chain guard)
    local pos = (ns.db and ns.db.profile and ns.db.profile.ui and ns.db.profile.ui.mainFramePos)
              or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)

    -- ESC closes
    tinsert(UISpecialFrames, "VuloClassicUIMainFrame")

    -- Click anywhere on the frame closes open dropdown popups
    f:SetScript("OnMouseDown", function()
        if _G.VCDropdownPopup and _G.VCDropdownPopup:IsShown() then
            _G.VCDropdownPopup:Hide()
        end
    end)

    -- =========================================================
    -- Title bar (draggable)
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

    -- Title background (slightly darker)
    UI.SetColorBG(titleBar, 0.04, 0.04, 0.05, 1)

    -- Title: icon (V from logo) + "uloClassicUI" text + version + CPU
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetText("|cff9b6cffuloClassicUI|r")
    local _, titleFontSize = title:GetFont()
    local iconSize = (titleFontSize or 14) + 4

    local titleIcon = titleBar:CreateTexture(nil, "OVERLAY")
    titleIcon:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\vui4")
    titleIcon:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleIcon:SetSize(iconSize, iconSize)

    title:SetPoint("LEFT", titleIcon, "RIGHT", 1, 0)

    local version = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    version:SetText("v" .. ns.VERSION)

    -- CPU usage (refresh every 2s while frame is visible)
    local cpuText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cpuText:SetPoint("LEFT", version, "RIGHT", 10, 0)
    cpuText:SetText("")

    -- API compat (Anniversary uses the C_AddOns namespace in some cases)
    local _UpdateCPU  = (C_AddOns and C_AddOns.UpdateAddOnCPUUsage) or _G.UpdateAddOnCPUUsage
    local _GetCPU     = (C_AddOns and C_AddOns.GetAddOnCPUUsage)    or _G.GetAddOnCPUUsage
    local _GetNum     = (C_AddOns and C_AddOns.GetNumAddOns)        or _G.GetNumAddOns
    local _IsLoaded   = (C_AddOns and C_AddOns.IsAddOnLoaded)       or _G.IsAddOnLoaded

    -- Sums CPU ms of all currently loaded addons
    local function getTotalAddonCPU()
        if not _GetCPU or not _GetNum then return 0 end
        local total = 0
        for i = 1, _GetNum() do
            if not _IsLoaded or _IsLoaded(i) then
                total = total + (_GetCPU(i) or 0)
            end
        end
        return total
    end

    local cpuTicker
    -- WoW's GetAddOnCPUUsage returns CUMULATIVE ms since profiling started.
    -- But we want "ms per second" (= current load) — so use the delta to the last tick.
    local _lastTotal, _lastOwn, _lastTime = 0, 0, 0

    local function updateCPU()
        local cv = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("scriptProfile"))
                or (GetCVar and GetCVar("scriptProfile"))
        if cv ~= "1" then
            cpuText:SetText("|cff666666CPU: off|r")
            return
        end
        if _UpdateCPU then _UpdateCPU() end

        local now   = GetTime() or 0
        local own   = (_GetCPU and _GetCPU("VuloClassicUI")) or 0
        local total = getTotalAddonCPU()

        if _lastTime == 0 then
            -- First tick — no delta available yet
            cpuText:SetText("|cff888888CPU: measuring...|r")
            _lastTotal, _lastOwn, _lastTime = total, own, now
            return
        end

        local dt = now - _lastTime
        if dt < 0.1 then return end  -- delta too small, skip

        local totalRate = (total - _lastTotal) / dt   -- ms spent per second
        local ownRate   = (own   - _lastOwn)   / dt

        cpuText:SetText(string.format(
            "|cff888888CPU: %.2f ms/s |cff666666(VCUI: %.2f)|r|r",
            totalRate, ownRate))

        _lastTotal, _lastOwn, _lastTime = total, own, now
    end

    f:HookScript("OnShow", function()
        updateCPU()
        if not cpuTicker and C_Timer and C_Timer.NewTicker then
            cpuTicker = C_Timer.NewTicker(2, updateCPU)
        end
    end)
    f:HookScript("OnHide", function()
        if cpuTicker then cpuTicker:Cancel(); cpuTicker = nil end
    end)

    -- Close button (right)
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -8, 0)

    -- =========================================================
    -- Search box (between CPU text and close button)
    -- =========================================================
    local searchBox = CreateFrame("EditBox", nil, titleBar)
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetMaxLetters(60)
    searchBox:SetTextInsets(8, 8, 0, 0)

    local sbBg = searchBox:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints(searchBox)
    sbBg:SetColorTexture(0.05, 0.05, 0.07, 0.95)

    local sbBorder = CreateFrame("Frame", nil, searchBox, BackdropTemplateMixin and "BackdropTemplate")
    sbBorder:SetAllPoints(searchBox)
    if sbBorder.SetBackdrop then
        sbBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        sbBorder:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    end

    local placeholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
    placeholder:SetText("Search settings...")

    -- Result dropdown below the search box
    local searchDD = CreateFrame("Frame", nil, f)
    searchDD:SetSize(320, 200)
    searchDD:SetPoint("TOPRIGHT", searchBox, "BOTTOMRIGHT", 0, -2)
    searchDD:SetFrameStrata("FULLSCREEN_DIALOG")
    searchDD:SetFrameLevel(300)
    searchDD:Hide()

    local ddBg = searchDD:CreateTexture(nil, "BACKGROUND")
    ddBg:SetAllPoints(searchDD)
    ddBg:SetColorTexture(0.05, 0.05, 0.07, 0.98)
    local ddBorder = CreateFrame("Frame", nil, searchDD, BackdropTemplateMixin and "BackdropTemplate")
    ddBorder:SetAllPoints(searchDD)
    if ddBorder.SetBackdrop then
        ddBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        ddBorder:SetBackdropBorderColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    end

    -- Search logic: iterates all modules + tabs + items, matches by label substring
    local function searchOptions(query)
        query = query:lower()
        local results = {}
        for _, key in ipairs(ns.moduleOrder or {}) do
            local m = ns.modules[key]
            if m and m.GetOptions then
                local tabIds = {}
                if m.tabs then
                    for _, t in ipairs(m.tabs) do table.insert(tabIds, t.id) end
                else
                    table.insert(tabIds, "default")
                end
                for _, tid in ipairs(tabIds) do
                    local ok, items = pcall(m.GetOptions, m, tid)
                    if ok and type(items) == "table" then
                        local function scan(list)
                            for _, item in ipairs(list) do
                                local label = (item.label or item.text or ""):lower()
                                if label ~= "" and label:find(query, 1, true) then
                                    table.insert(results, {
                                        modName = m.name, modKey = key,
                                        tabId = tid, label = item.label or item.text,
                                    })
                                    if #results >= 20 then return true end
                                end
                                if item.items then
                                    if scan(item.items) then return true end
                                end
                            end
                        end
                        if scan(items) then break end
                    end
                end
            end
        end
        return results
    end

    -- Result rows (reused pool)
    local resultRows = {}
    local function renderResults(results)
        for _, row in ipairs(resultRows) do row:Hide() end
        if #results == 0 then searchDD:Hide(); return end
        local y = -4
        for i, res in ipairs(results) do
            local row = resultRows[i]
            if not row then
                row = CreateFrame("Button", nil, searchDD)
                row:SetHeight(20)
                row:SetPoint("LEFT", searchDD, "LEFT", 4, 0)
                row:SetPoint("RIGHT", searchDD, "RIGHT", -4, 0)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                row.text:SetJustifyH("LEFT")
                row.hover = row:CreateTexture(nil, "BACKGROUND")
                row.hover:SetAllPoints(row)
                row.hover:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.25)
                row.hover:Hide()
                row:SetScript("OnEnter", function(self) self.hover:Show() end)
                row:SetScript("OnLeave", function(self) self.hover:Hide() end)
                resultRows[i] = row
            end
            row:SetPoint("TOP", searchDD, "TOP", 0, y)
            row.text:SetText(string.format("|cff9b6cff%s|r  »  %s", res.modName, res.label))
            row._modKey = res.modKey
            row._tabId  = res.tabId
            row:SetScript("OnClick", function(self)
                searchBox:ClearFocus()
                searchBox:SetText("")
                placeholder:Show()
                searchDD:Hide()
                if UI.ShowModulePage then UI:ShowModulePage(self._modKey) end
                if self._tabId and self._tabId ~= "default" and UI.ShowTab then
                    UI:ShowTab(self._tabId)
                end
            end)
            row:Show()
            y = y - 22
        end
        searchDD:SetHeight(math.min(440, 8 + #results * 22))
        searchDD:Show()
    end

    searchBox:HookScript("OnTextChanged", function(self)
        local q = self:GetText() or ""
        if q == "" then placeholder:Show() else placeholder:Hide() end
        if #q < 2 then searchDD:Hide(); return end
        renderResults(searchOptions(q))
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText(""); self:ClearFocus(); searchDD:Hide(); placeholder:Show()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeText:SetText("×")
    closeText:SetTextColor(0.7, 0.7, 0.7)
    -- Set font size explicitly (GameFontNormalLarge is ~16, we want 24)
    local font, _, flags = closeText:GetFont()
    if font then closeText:SetFont(font, 24, flags or "") end
    closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.3, 0.3) end)
    closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(0.7, 0.7, 0.7) end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Separator line below title
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    sep:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)

    -- =========================================================
    -- Sidebar (left)
    -- =========================================================
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT",    sep, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", f,   "BOTTOMLEFT", 0, BOTTOMBAR_H)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    UI.SetColorBG(sidebar, ns.COLORS.bgLight.r, ns.COLORS.bgLight.g, ns.COLORS.bgLight.b, 1)

    -- Sidebar separator line on the right
    local sidebarSep = f:CreateTexture(nil, "ARTWORK")
    sidebarSep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    sidebarSep:SetPoint("TOPLEFT",    sidebar, "TOPRIGHT", 0, 0)
    sidebarSep:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarSep:SetWidth(1)

    -- Sidebar ScrollFrame (for long module lists)
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
    -- Tab bar (top right, above content)
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
    -- Content (right side, below tabs)
    -- =========================================================
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     tabBar,  "BOTTOMLEFT",  0, -1)
    content:SetPoint("BOTTOMRIGHT", f,       "BOTTOMRIGHT", 0, BOTTOMBAR_H)
    UI.SetColorBG(content, ns.COLORS.bgContent.r, ns.COLORS.bgContent.g, ns.COLORS.bgContent.b, 1)

    f.content = content

    -- Scroll inside content
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
    -- Bottom bar
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

    -- Reset (left)
    local resetBtn = UI:CreateButton(bottomBar, {
        label = "Reset Module", width = 130, height = 26,
        tooltip = "Resets all settings of the current module to defaults.",
        onClick = function()
            if not UI.currentModule then return end
            local mod = ns.modules[UI.currentModule]
            if not mod then return end
            -- Recursively copy module defaults
            for k, v in pairs(mod.defaults or {}) do
                if type(v) == "table" then
                    mod.db[k] = ns:DeepCopy(v)
                else
                    mod.db[k] = v
                end
            end
            UI:BuildOptionsPage(UI.currentModule)
            UI:RefreshSidebarStates()
            ns:Print("Module '%s' reset.", mod.name)
        end,
    })
    resetBtn:SetPoint("LEFT", bottomBar, "LEFT", 10, 0)

    -- Reload UI
    local reloadBtn = UI:CreateButton(bottomBar, {
        label = "Reload UI", width = 100, height = 26,
        tooltip = "Reloads the WoW UI completely (/reload).",
        onClick = function() ReloadUI() end,
    })
    reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)

    -- Done (right, primary)
    local doneBtn = UI:CreateButton(bottomBar, {
        label = "Done", width = 90, height = 26, primary = true,
        onClick = function() f:Hide() end,
    })
    doneBtn:SetPoint("RIGHT", bottomBar, "RIGHT", -10, 0)

    UI.mainFrame = f
    return f
end

-- =========================================================
-- Tab system
-- =========================================================
-- Tabs are built for the current module. Default: a single tab "Settings".
-- Modules can define mod.tabs = { {id="general", label="General"}, ... }.
function UI:BuildTabsForModule(key)
    local f = UI.mainFrame
    if not f then return end
    local mod = ns.modules[key]

    -- Remove old tabs
    for _, tab in ipairs(f.tabs) do
        tab:Hide()
        tab:SetParent(nil)
    end
    f.tabs = {}

    -- Resolve tab definitions
    local tabs = (mod and mod.tabs) or { { id = "default", label = "Settings" } }
    local hasRealTabs = mod and mod.tabs and #mod.tabs > 1

    -- If only the default tab: hide tab bar, pull content up
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
    -- Render content for this tab
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
