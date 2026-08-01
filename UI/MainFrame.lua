-- VuloClassicUI / UI / MainFrame: the main options window (title bar, sidebar, tabs, content, footer).
local _, ns = ...
local L = ns.L
ns.UI = ns.UI or {}
local UI = ns.UI

local FRAME_WIDTH   = 1050
local FRAME_HEIGHT  = 680
local SIDEBAR_WIDTH = 210
local TITLEBAR_H    = 32
local BOTTOMBAR_H   = 44
local TABBAR_H      = 32

-- 1050x680 is the design size, not a promise. On an interface scale that leaves
-- UIParent smaller than that, the window fills the screen edge to edge -- and
-- because it is clamped to the screen it then cannot be dragged at all: there
-- is nowhere for it to go. Reported as "the menu will not move down"
-- (01.08.2026), where the window stood at 99% of the screen height and had
-- about twenty units of travel left.
--
-- A margin is subtracted rather than fitting exactly, so there is always slack
-- in both directions and the window can still be moved off centre.
local MIN_WIDTH, MIN_HEIGHT, SCREEN_MARGIN = 820, 400, 60

local function fittedSize()
    local w, h = FRAME_WIDTH, FRAME_HEIGHT
    if UIParent and UIParent.GetWidth then
        local aw, ah = UIParent:GetWidth(), UIParent:GetHeight()
        if aw and aw > 0 then w = math.min(w, math.max(MIN_WIDTH,  aw - SCREEN_MARGIN)) end
        if ah and ah > 0 then h = math.min(h, math.max(MIN_HEIGHT, ah - SCREEN_MARGIN)) end
    end
    return w, h
end

-- Re-measured on every open: the interface scale can change while the addon is
-- loaded, and the setting that changes it lives in this very window.
function UI:FitMainFrame()
    local f = UI.mainFrame
    if not f then return end
    local w, h = fittedSize()
    if f:GetWidth() ~= w or f:GetHeight() ~= h then f:SetSize(w, h) end
end

function UI:CreateMainFrame()
    if UI.mainFrame then return UI.mainFrame end

    local f = CreateFrame("Frame", "VuloClassicUIMainFrame", UIParent)
    f:SetSize(fittedSize())
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()

    UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.borderDark or ns.COLORS.border })
    UI:CreateShadow(f)

    local brand = f:CreateTexture(nil, "BORDER", nil, 1)
    brand:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -1)
    brand:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    brand:SetHeight(2)
    UI.SetGradient(brand, "HORIZONTAL",
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1.0,
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.10)

    local pos = (ns.db and ns.db.profile and ns.db.profile.ui and ns.db.profile.ui.mainFramePos)
              or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)

    tinsert(UISpecialFrames, "VuloClassicUIMainFrame")  -- ESC closes

    f:SetScript("OnMouseDown", function()
        if _G.VCDropdownPopup and _G.VCDropdownPopup:IsShown() then
            _G.VCDropdownPopup:Hide()
        end
    end)

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

    local tbBG = UI.SetColorBG(titleBar, 0.04, 0.04, 0.05, 1)
    UI.SetGradient(tbBG, "VERTICAL",
        0.045, 0.045, 0.06, 1,
        0.085, 0.085, 0.11, 1)

    -- the icon supplies the leading "V", the text starts at "uloClassicUI"
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.Font(title, 15)
    title:SetText((ns.C and ns.C.accent or "|cff9b6cff") .. "uloClassicUI|r")
    local _, titleFontSize = title:GetFont()
    local iconSize = (titleFontSize or 14) + 4

    local titleIcon = titleBar:CreateTexture(nil, "OVERLAY")
    titleIcon:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\vui4")
    titleIcon:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleIcon:SetSize(iconSize, iconSize)

    title:SetPoint("LEFT", titleIcon, "RIGHT", 1, 0)

    local version = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    UI.Font(version, 10)
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    version:SetText("v" .. ns.VERSION)
    version:SetTextColor(ns.COLORS.textMuted.r, ns.COLORS.textMuted.g, ns.COLORS.textMuted.b)

    local cpuText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    UI.Font(cpuText, 10)
    cpuText:SetPoint("LEFT", version, "RIGHT", 10, 0)
    cpuText:SetText("")

    -- The client carries its own always-on profiler (used by Blizzard's own addon
    -- list). It needs no CVar and no /reload, and it reports per-frame timings
    -- rather than a cumulative counter we have to difference ourselves. The old
    -- family stays as the fallback for clients without it -- there it still needs
    -- scriptProfile and a reload, which is what the option next to this says.
    local PROF = _G.C_AddOnProfiler
    local METRIC = _G.Enum and _G.Enum.AddOnProfilerMetric

    -- API compat: newer clients moved these into the C_AddOns namespace
    local _UpdateCPU  = (C_AddOns and C_AddOns.UpdateAddOnCPUUsage) or _G.UpdateAddOnCPUUsage
    local _GetCPU     = (C_AddOns and C_AddOns.GetAddOnCPUUsage)    or _G.GetAddOnCPUUsage
    local _GetNum     = (C_AddOns and C_AddOns.GetNumAddOns)        or _G.GetNumAddOns
    local _IsLoaded   = (C_AddOns and C_AddOns.IsAddOnLoaded)       or _G.IsAddOnLoaded

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
    -- GetAddOnCPUUsage is cumulative ms since profiling started; we show the per-tick delta.
    local _lastTotal, _lastOwn, _lastTime = 0, 0, 0

    -- Blizzard's own share formula (Blizzard_AddOnList): NOT own/all-addons, but
    -- own divided by the frame time this addon is actually responsible for --
    -- otherwise the number grows as other addons get cheaper.
    local function sharePercent(metric)
        local app     = PROF.GetApplicationMetric(metric)
        local overall = PROF.GetOverallMetric(metric)
        local own     = PROF.GetAddOnMetric(ns.NAME, metric)
        local rel = app - overall + own
        if rel <= 0 then return 0, own end
        return own / rel * 100, own
    end

    local function updateCPUModern()
        local pct, own = sharePercent(METRIC.RecentAverageTime)
        local peak = PROF.GetAddOnMetric(ns.NAME, METRIC.PeakTime)
        cpuText:SetText(string.format(
            L["|cff888888%.2f ms/frame |cff666666(%.1f%% of ours, peak %.1f ms)|r|r"],
            own, pct, peak))
    end

    local function updateCPULegacy()
        local cv = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("scriptProfile"))
                or (GetCVar and GetCVar("scriptProfile"))
        if cv ~= "1" then
            cpuText:SetText(L["|cff666666CPU: off|r"])
            return
        end
        if _UpdateCPU then _UpdateCPU() end

        local now   = GetTime() or 0
        local own   = (_GetCPU and _GetCPU("VuloClassicUI")) or 0
        local total = getTotalAddonCPU()

        if _lastTime == 0 then
            cpuText:SetText(L["|cff888888CPU: measuring...|r"])
            _lastTotal, _lastOwn, _lastTime = total, own, now
            return
        end

        local dt = now - _lastTime
        if dt < 0.1 then return end

        local totalRate = (total - _lastTotal) / dt
        local ownRate   = (own   - _lastOwn)   / dt

        cpuText:SetText(string.format(
            L["|cff888888CPU: %.2f ms/s |cff666666(VCUI: %.2f)|r|r"],
            totalRate, ownRate))

        _lastTotal, _lastOwn, _lastTime = total, own, now
    end

    -- IsEnabled matters, not just the presence of the functions: Blizzard gates
    -- its own performance UI on it, and with the profiler off every metric
    -- reads 0 -- the header would sit at "0.00 ms/frame" forever without ever
    -- erroring, so nothing would trip the fallback.
    local useModern = PROF and METRIC and PROF.GetAddOnMetric
        and PROF.GetApplicationMetric and PROF.GetOverallMetric
        and METRIC.RecentAverageTime ~= nil and METRIC.PeakTime ~= nil
        and (not PROF.IsEnabled or PROF.IsEnabled())
    local function updateCPU()
        if useModern then
            local ok = pcall(updateCPUModern)
            if ok then return end
            useModern = false   -- fall back for the rest of the session
        end
        updateCPULegacy()
    end

    f:HookScript("OnShow", function()
        UI:FitMainFrame()
        updateCPU()
        if not cpuTicker and C_Timer and C_Timer.NewTicker then
            cpuTicker = C_Timer.NewTicker(2, updateCPU)
        end
    end)
    f:HookScript("OnHide", function()
        if cpuTicker then cpuTicker:Cancel(); cpuTicker = nil end
    end)

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(38, TITLEBAR_H - 3)
    closeBtn:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", -1, -3)

    local closeBG = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBG:SetAllPoints(closeBtn)
    closeBG:SetColorTexture(0.78, 0.16, 0.16, 1)
    closeBG:Hide()

    local searchBox = CreateFrame("EditBox", nil, titleBar)
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetFont(UI.FONT_PATH, 11, "")
    searchBox:SetMaxLetters(60)
    searchBox:SetTextInsets(24, 8, 0, 0)

    local sbBg = searchBox:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints(searchBox)
    sbBg:SetColorTexture(0.04, 0.04, 0.055, 0.95)

    local sbIcon = searchBox:CreateTexture(nil, "OVERLAY")
    sbIcon:SetSize(12, 12)
    sbIcon:SetPoint("LEFT", searchBox, "LEFT", 7, 0)
    sbIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    sbIcon:SetVertexColor(0.55, 0.55, 0.62)

    local sbBorder = CreateFrame("Frame", nil, searchBox, BackdropTemplateMixin and "BackdropTemplate")
    sbBorder:SetAllPoints(searchBox)
    if sbBorder.SetBackdrop then
        sbBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        sbBorder:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    end

    searchBox:HookScript("OnEditFocusGained", function()
        if sbBorder.SetBackdropBorderColor then
            sbBorder:SetBackdropBorderColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        end
        sbIcon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    end)
    searchBox:HookScript("OnEditFocusLost", function()
        if sbBorder.SetBackdropBorderColor then
            sbBorder:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
        end
        sbIcon:SetVertexColor(0.55, 0.55, 0.62)
    end)

    local placeholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    UI.Font(placeholder, 11)
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 24, 0)
    placeholder:SetText(L["Search settings..."])
    placeholder:SetTextColor(0.45, 0.45, 0.52)

    local searchDD = CreateFrame("Frame", nil, f)
    searchDD:SetSize(320, 200)
    searchDD:SetPoint("TOPRIGHT", searchBox, "BOTTOMRIGHT", 0, -2)
    searchDD:SetFrameStrata("FULLSCREEN_DIALOG")
    searchDD:SetFrameLevel(300)
    searchDD:Hide()

    UI:CreateShadow(searchDD)
    local ddBg = searchDD:CreateTexture(nil, "BACKGROUND")
    ddBg:SetAllPoints(searchDD)
    ddBg:SetColorTexture(0.05, 0.05, 0.07, 0.98)
    local ddBorder = CreateFrame("Frame", nil, searchDD, BackdropTemplateMixin and "BackdropTemplate")
    ddBorder:SetAllPoints(searchDD)
    if ddBorder.SetBackdrop then
        ddBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        ddBorder:SetBackdropBorderColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    end

    local function searchOptions(query)
        query = query:lower()
        local results = {}
        for _, key in ipairs(ns.moduleOrder or {}) do
            if #results >= 20 then break end
            local m = ns.modules[key]
            -- page members are indexed once via their page
            if m and m.GetOptions and not m._pageMember then
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
                                -- title: sections. Their headings were plain
                                -- header rows once and searchable via text;
                                -- becoming sections must not unlist them.
                                local raw = item.label or item.text or item.title or ""
                                -- match the translated label AND the English key, so
                                -- searching works in the user's language and in English
                                local shown = raw ~= "" and L[raw] or ""
                                if raw ~= "" and (shown:lower():find(query, 1, true)
                                    or raw:lower():find(query, 1, true)) then
                                    if #results >= 20 then return true end
                                    table.insert(results, {
                                        modName = L[m.name], modKey = key,
                                        tabId = tid, label = shown,
                                    })
                                end
                                if item.items then
                                    if scan(item.items) then return true end
                                end
                                -- and behind a gear: folded away is not gone,
                                -- and a setting you cannot find is the one you
                                -- search for
                                if item.subOptions then
                                    if scan(item.subOptions) then return true end
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
                UI.Font(row.text, 11)
                row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                row.hover = row:CreateTexture(nil, "BACKGROUND")
                row.hover:SetAllPoints(row)
                row.hover:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.25)
                row.hover:Hide()
                row:SetScript("OnEnter", function(self) self.hover:Show() end)
                row:SetScript("OnLeave", function(self) self.hover:Hide() end)
                resultRows[i] = row
            end
            row:SetPoint("TOP", searchDD, "TOP", 0, y)
            row.text:SetText(string.format("%s%s|r  »  %s",
                (ns.C and ns.C.accent) or "|cff9b6cff", res.modName, res.label))
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
    UI.Font(closeText, 20)
    closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeText:SetText("×")
    closeText:SetTextColor(0.7, 0.7, 0.7)
    local font, _, flags = closeText:GetFont()
    if font then closeText:SetFont(font, 20, flags or "") end
    closeBtn:SetScript("OnEnter", function()
        closeBG:Show()
        closeText:SetTextColor(1, 1, 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeBG:Hide()
        closeText:SetTextColor(0.7, 0.7, 0.7)
    end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    sep:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)

    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT",    sep, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", f,   "BOTTOMLEFT", 0, BOTTOMBAR_H)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    UI.SetColorBG(sidebar, ns.COLORS.bgLight.r, ns.COLORS.bgLight.g, ns.COLORS.bgLight.b, 1)

    local sidebarSep = f:CreateTexture(nil, "ARTWORK")
    sidebarSep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    sidebarSep:SetPoint("TOPLEFT",    sidebar, "TOPRIGHT", 0, 0)
    sidebarSep:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarSep:SetWidth(1)

    local sidebarScroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    sidebarScroll:SetPoint("TOPLEFT",     sidebar, "TOPLEFT",     6, -6)
    sidebarScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -14, 6)
    local sidebarContent = CreateFrame("Frame", nil, sidebarScroll)
    sidebarContent:SetSize(SIDEBAR_WIDTH - 22, 10)
    sidebarScroll:SetScrollChild(sidebarContent)
    UI.StyleScrollbar(sidebarScroll)
    UI.EnableScrollWheel(sidebarScroll, sidebarContent)

    -- The dashboard's search prompt hands focus here rather than matching on its
    -- own, so there is only ever one search implementation.
    f.searchBox       = searchBox

    -- Override-group picker, left of the search box. It only appears where the
    -- talent API exists, so a client without it shows no dead control.
    if ns.HasTalentGroups and ns:HasTalentGroups() then
        local ovBtn = CreateFrame("Button", nil, titleBar)
        ovBtn:SetSize(22, 20)
        ovBtn:SetPoint("RIGHT", searchBox, "LEFT", -6, 0)

        -- The player's own class icon: the overrides hang on this character's
        -- talents, so the control that opens them should look like them. Comes
        -- from Blizzard's class sheet, so nothing ships and no restart is needed.
        local glyph = ovBtn:CreateTexture(nil, "ARTWORK")
        glyph:SetSize(15, 15)
        glyph:SetPoint("CENTER")
        local classToken = select(2, UnitClass("player"))
        local tex, coords = ns:GetVuloClassIcon(classToken)
        if tex and coords then
            glyph:SetTexture(tex)
            glyph:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            glyph:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        ovBtn._glyph = glyph

        local hl = ovBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(ovBtn)
        hl:SetColorTexture(1, 1, 1, 0.08)

        ovBtn:SetScript("OnClick", function(self)
            if ns.ShowOverrideMenu then ns:ShowOverrideMenu(self) end
        end)
        ovBtn:SetScript("OnEnter", function(self)
            self._glyph:SetAlpha(1)   -- 90 % idle, full on hover
            local id = ns.EditingOverrideGroup and ns:EditingOverrideGroup()
            local g  = id and ns:OverrideGroup(id)
            -- The group icon rides HERE and not on the button: the button keeps
            -- one identity on purpose (see RefreshOverrideButton below), and the
            -- tooltip is where the group is named anyway.
            local name = g and ((ns.OverrideIconMarkup and ns:OverrideIconMarkup(g.icon) or "") .. g.name)
            -- Same wording as the menu's default entry, from one helper.
            UI:ShowTooltip(self, {
                anchor = "ANCHOR_BOTTOM",
                title  = L["Editing as"],
                lines  = { name and { name, 0.7, 0.7, 0.8 }
                                or { ns:OverrideSelfLabel(), 1, 1, 1 } },
            })
        end)
        ovBtn:SetScript("OnLeave", function(self)
            self._glyph:SetAlpha(0.9)
            UI:HideTooltip()
        end)

        f.overrideBtn = ovBtn

        -- Accent while a group is being recorded into: the whole suite behaves
        -- differently then, and that has to be visible from anywhere in it.
        function UI:RefreshOverrideButton()
            local b = UI.mainFrame and UI.mainFrame.overrideBtn
            if not b then return end
            -- ONE identity: the class icon in its natural colours, whatever the
            -- state. A control that changes its look depending on a mode makes
            -- the reader decode the icon before they can use it -- and the state
            -- is already told twice over, by the tick in the menu and by the
            -- accent bars on the overridden rows.
            b._glyph:SetDesaturated(false)
            b._glyph:SetVertexColor(1, 1, 1)
            b._glyph:SetAlpha(0.9)
        end
        UI:RefreshOverrideButton()
    end

    f.sidebar         = sidebar
    f.sidebarContent  = sidebarContent
    f.sidebarScroll   = sidebarScroll

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
    f.tabSep = tabSep
    f.tabs   = {}

    -- Single-row tab strip. Tabs sit on a rail inside a clipping window; when
    -- they outgrow the bar, two arrow buttons page the rail left and right --
    -- the bar never wraps to a second row.
    local tabStrip = CreateFrame("Frame", nil, tabBar)
    tabStrip:SetClipsChildren(true)
    tabStrip:SetPoint("TOPLEFT",     tabBar, "TOPLEFT",     4, 0)
    tabStrip:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", -4, 0)
    local tabRail = CreateFrame("Frame", nil, tabStrip)
    tabRail:SetPoint("TOPLEFT", tabStrip, "TOPLEFT", 0, -2)
    tabRail:SetSize(10, TABBAR_H - 4)
    f.tabStrip, f.tabRail = tabStrip, tabRail

    local function makeTabArrow(dir)
        local b = CreateFrame("Button", nil, tabBar)
        b:SetSize(18, TABBAR_H - 4)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("CENTER", b, "CENTER", 0, 0)
        icon:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\arrow_"
            .. (dir < 0 and "left" or "right") .. ".tga")
        icon:SetVertexColor(0.7, 0.7, 0.75)
        b._icon = icon
        b:SetScript("OnEnter", function(self) self._icon:SetVertexColor(1, 1, 1) end)
        b:SetScript("OnLeave", function(self) self._icon:SetVertexColor(0.7, 0.7, 0.75) end)
        b:SetScript("OnClick", function() UI:ScrollTabs(dir) end)
        b:Hide()
        return b
    end
    f.tabPrev = makeTabArrow(-1)
    f.tabPrev:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 2, -2)
    f.tabNext = makeTabArrow(1)
    f.tabNext:SetPoint("TOPRIGHT", tabBar, "TOPRIGHT", -2, -2)

    local TABCOL_W = 170
    local tabColumn = CreateFrame("Frame", nil, f)
    tabColumn:SetPoint("TOPLEFT",     sidebar, "TOPRIGHT",    1, 0)
    tabColumn:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 1 + TABCOL_W, 0)
    UI.SetColorBG(tabColumn, ns.COLORS.bgLight.r, ns.COLORS.bgLight.g, ns.COLORS.bgLight.b, 1)
    tabColumn:Hide()

    local tabColSep = f:CreateTexture(nil, "ARTWORK")
    tabColSep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    tabColSep:SetPoint("TOPLEFT",    tabColumn, "TOPRIGHT", 0, 0)
    tabColSep:SetPoint("BOTTOMLEFT", tabColumn, "BOTTOMRIGHT", 0, 0)
    tabColSep:SetWidth(1)

    local tabColScroll = CreateFrame("ScrollFrame", nil, tabColumn, "UIPanelScrollFrameTemplate")
    tabColScroll:SetPoint("TOPLEFT",     tabColumn, "TOPLEFT",     6, -6)
    tabColScroll:SetPoint("BOTTOMRIGHT", tabColumn, "BOTTOMRIGHT", -14, 6)
    local tabColContent = CreateFrame("Frame", nil, tabColScroll)
    tabColContent:SetSize(TABCOL_W - 22, 10)
    tabColScroll:SetScrollChild(tabColContent)
    if UI.StyleScrollbar then UI.StyleScrollbar(tabColScroll) end
    UI.EnableScrollWheel(tabColScroll, tabColContent)

    f.tabColumn     = tabColumn
    f.tabColWidth   = TABCOL_W
    f.tabColContent = tabColContent
    f.tabColScroll  = tabColScroll

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     tabBar,  "BOTTOMLEFT",  0, -1)
    content:SetPoint("BOTTOMRIGHT", f,       "BOTTOMRIGHT", 0, BOTTOMBAR_H)
    UI.SetColorBG(content, ns.COLORS.bgContent.r, ns.COLORS.bgContent.g, ns.COLORS.bgContent.b, 1)

    f.content = content

    -- A module may pin a header here (mod.BuildPageHeader): it sits ABOVE the
    -- scroll area and stays put while the page under it scrolls. Hidden and
    -- zero-cost for every module that does not claim it; the scroll frame's
    -- top anchor switches between the two in BuildOptionsPage.
    local pageHeader = CreateFrame("Frame", nil, content)
    pageHeader:SetPoint("TOPLEFT",  content, "TOPLEFT",  8, -8)
    pageHeader:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, -8)
    pageHeader:SetHeight(10)
    pageHeader:Hide()
    f.pageHeader = pageHeader

    local scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     content, "TOPLEFT",     8,  -8)
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 8)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)
    UI.StyleScrollbar(scroll)
    UI.EnableScrollWheel(scroll, scrollChild)
    f.scroll      = scroll
    f.scrollChild = scrollChild

    local bottomBar = CreateFrame("Frame", nil, f)
    bottomBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    bottomBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    bottomBar:SetHeight(BOTTOMBAR_H)
    local bbBG = UI.SetColorBG(bottomBar, 0.04, 0.04, 0.05, 1)
    UI.SetGradient(bbBG, "VERTICAL",
        0.075, 0.075, 0.095, 1,
        0.045, 0.045, 0.06, 1)

    local bottomSep = f:CreateTexture(nil, "ARTWORK")
    bottomSep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    bottomSep:SetPoint("BOTTOMLEFT",  bottomBar, "TOPLEFT",  0, 0)
    bottomSep:SetPoint("BOTTOMRIGHT", bottomBar, "TOPRIGHT", 0, 0)
    bottomSep:SetHeight(1)

    local resetBtn = UI:CreateButton(bottomBar, {
        label = L["Reset Module"], width = 130, height = 26,
        tooltip = L["Resets all settings of the current module to defaults."],
        onClick = function()
            if not UI.currentModule then return end
            local mod = ns.modules[UI.currentModule]
            if not mod then return end
            for k, v in pairs(mod.defaults or {}) do
                if type(v) == "table" then
                    mod.db[k] = ns:DeepCopy(v)
                else
                    mod.db[k] = v
                end
            end
            -- Keep the tab: rebuilding without it makes GetOptions(nil) return
            -- every section at once, so the page turned into one long list while
            -- the tab column still showed a single tab as selected.
            UI:BuildOptionsPage(UI.currentModule, UI.currentTab)
            UI:RefreshSidebarStates()
            ns:Print(L["Module '%s' reset."], L[mod.name])
        end,
    })
    resetBtn:SetPoint("LEFT", bottomBar, "LEFT", 10, 0)

    local reloadBtn = UI:CreateButton(bottomBar, {
        label = L["Reload UI"], width = 100, height = 26,
        tooltip = L["Reloads the WoW UI completely (/reload)."],
        onClick = function() ReloadUI() end,
    })
    reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)

    local doneBtn = UI:CreateButton(bottomBar, {
        label = L["Done"], width = 90, height = 26, primary = true,
        onClick = function() f:Hide() end,
    })
    doneBtn:SetPoint("RIGHT", bottomBar, "RIGHT", -10, 0)

    -- the client cannot open a browser, so links are shown pre-selected for Ctrl+C
    StaticPopupDialogs["VCUI_COPY_URL"] = StaticPopupDialogs["VCUI_COPY_URL"] or {
        text = L["Copy the link with Ctrl+C:"],
        button1 = CLOSE or "Close",
        hasEditBox = true,
        editBoxWidth = 260,
        OnShow = function(self)
            local eb = ns.PopupEditBox(self)
            if not eb then return end
            eb:SetText(self.data or "")
            eb:HighlightText()
            eb:SetFocus()
        end,
        EditBoxOnTextChanged = function(self, data)
            if self:GetText() ~= (data or "") then
                self:SetText(data or "")
                self:HighlightText()
            end
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        EditBoxOnEnterPressed  = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    local function socialButton(iconFile, label, url, xOff)
        local b = CreateFrame("Button", nil, bottomBar)
        b:SetSize(20, 20)
        b:SetPoint("CENTER", bottomBar, "CENTER", xOff, 0)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints(b)
        t:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\" .. iconFile)
        t:SetVertexColor(0.85, 0.85, 0.85, 0.9)
        b:SetScript("OnEnter", function(self)
            t:SetVertexColor(1, 1, 1, 1)
            UI:ShowTooltip(self, {
                anchor = "ANCHOR_TOP", title = label,
                lines  = { L["Click: copy link"] },
            })
        end)
        b:SetScript("OnLeave", function()
            t:SetVertexColor(0.85, 0.85, 0.85, 0.9)
            UI:HideTooltip()
        end)
        b:SetScript("OnClick", function()
            StaticPopup_Show("VCUI_COPY_URL", nil, nil, url)
        end)
        return b
    end
    socialButton("TwitchV.tga",  "Twitch",  "https://www.twitch.tv/mrvulo", -14)
    socialButton("DiscordV.tga", "Discord", "https://discord.gg/P5dTSB6wC",  14)

    UI.mainFrame = f
    return f
end

-- Optional per-module spec: mod.tabs = { { id = "general", label = "General" }, ... }.
-- Tab buttons are pooled: frames are never garbage-collected.
UI._tabPool = UI._tabPool or {}

function UI:ReleaseTabs()
    local f = UI.mainFrame
    if not f or not f.tabs then return end
    for _, tab in ipairs(f.tabs) do
        tab:Hide()
        tab:ClearAllPoints()
        if tab._icon      then tab._icon:Hide()      end
        if tab._leftbar   then tab._leftbar:Hide()   end
        if tab._underline then tab._underline:Hide() end
        -- the permanent handle, not _activeBG: the top-bar rendering nils that
        if tab._activeBGTex then tab._activeBGTex:Hide() end
        table.insert(UI._tabPool, tab)
    end
    f.tabs = {}
end

local function acquireTab(parentBar)
    local tab = table.remove(UI._tabPool)
    if tab then
        tab:SetParent(parentBar)
        return tab
    end

    tab = CreateFrame("Button", nil, parentBar)
    tab:SetHeight(28)

    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(text, 12)
    text:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab._text = text

    local icon = tab:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", tab, "LEFT", 8, 0)
    icon:Hide()
    tab._icon = icon

    local leftbar = tab:CreateTexture(nil, "OVERLAY")
    leftbar:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    leftbar:SetWidth(3)
    leftbar:SetPoint("TOPLEFT",    tab, "TOPLEFT",    0, 0)
    leftbar:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
    leftbar:Hide()
    tab._leftbar = leftbar

    local activeBG = tab:CreateTexture(nil, "BACKGROUND")
    activeBG:SetAllPoints(tab)
    activeBG:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.08)
    activeBG:Hide()
    tab._activeBG = activeBG
    -- permanent handle: the top-bar rendering nils _activeBG (no fill behind a
    -- text tab), and a pooled frame must not lose the texture over it
    tab._activeBGTex = activeBG

    local underline = tab:CreateTexture(nil, "OVERLAY")
    underline:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT",  tab, "BOTTOMLEFT", 6, 0)
    underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 0)
    underline:Hide()
    tab._underline = underline

    -- scripts installed once on the pooled frame; they read the live self._tabId
    tab:SetScript("OnEnter", function(self)
        if UI.currentTab ~= self._tabId then
            self._text:SetTextColor(1, 1, 1)
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if UI.currentTab ~= self._tabId then
            local c = ns.COLORS.textDim
            self._text:SetTextColor(c.r, c.g, c.b)
        end
    end)
    tab:SetScript("OnClick", function(self)
        UI:ShowTab(self._tabId)
    end)

    return tab
end

function UI:BuildTabsForModule(key)
    local f = UI.mainFrame
    if not f then return end
    local mod = ns.modules[key]

    UI:ReleaseTabs()

    local tabs = (mod and mod.tabs) or { { id = "default", label = L["Settings"] } }
    local hasRealTabs = mod and mod.tabs and #mod.tabs > 1

    if not hasRealTabs then
        f.tabBar:Hide()
        if f.tabSep then f.tabSep:Hide() end
        if f.tabColumn then f.tabColumn:Hide() end
        f.content:ClearAllPoints()
        f.content:SetPoint("TOPLEFT",     f.sidebar, "TOPRIGHT",  1, 0)
        f.content:SetPoint("BOTTOMRIGHT", f,         "BOTTOMRIGHT", 0, BOTTOMBAR_H)
        UI.currentTab = "default"
        UI:BuildOptionsPage(key, "default")
        return
    end

    -- Horizontal tab row along the top of the content area: text tabs with an
    -- accent underline under the active one. This replaced the left tab column
    -- on 30.07.2026 at the user's request. ONE row, always: tabs sit on the
    -- rail at their text width, and when they outgrow the bar (the arena
    -- module), the arrow buttons page the rail -- no second row.
    if f.tabColumn then f.tabColumn:Hide() end
    f.tabBar:Show()
    if f.tabSep then f.tabSep:Show() end

    local rail = f.tabRail
    local ROW_H, PADX, GAPX = TABBAR_H - 4, 14, 2
    local x = 0
    for _, tabDef in ipairs(tabs) do
        local tab = acquireTab(rail)
        tab:SetParent(rail)
        tab._tabId = tabDef.id
        tab:SetHeight(ROW_H)

        if tab._icon then tab._icon:Hide() end
        tab._text:ClearAllPoints()
        tab._text:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tab._text:SetJustifyH("CENTER")
        tab._text:SetText(L[tabDef.label])  -- tabDef.label is a raw English key

        local w = math.max(44, math.ceil(tab._text:GetStringWidth() or 40) + PADX * 2)
        tab:SetWidth(w)
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", rail, "TOPLEFT", x, 0)
        x = x + w + GAPX

        -- underline is the active mark up here; the left bar belongs to the
        -- retired column rendering and must not linger on a pooled frame
        tab._activeMark = tab._underline
        tab._leftbar:Hide()
        if tab._activeBGTex then tab._activeBGTex:Hide() end
        tab._activeBG = nil

        tab:Show()
        table.insert(f.tabs, tab)
    end
    f.tabBar:SetHeight(TABBAR_H)
    rail:SetSize(math.max(x, 10), ROW_H)
    f._tabTotalW = x
    UI._tabOffset = 0
    UI:UpdateTabScroll()

    f.content:ClearAllPoints()
    f.content:SetPoint("TOPLEFT",     f.tabBar, "BOTTOMLEFT",  0, -1)
    f.content:SetPoint("BOTTOMRIGHT", f,        "BOTTOMRIGHT", 0, BOTTOMBAR_H)

    if tabs[1] then UI:ShowTab(tabs[1].id) end
end

-- Applies the clamped rail offset and decides whether the arrows are needed.
function UI:UpdateTabScroll()
    local f = UI.mainFrame
    if not (f and f.tabStrip) then return end
    local barW  = f.tabBar:GetWidth() or 800
    local total = f._tabTotalW or 0
    -- two-pass width: the arrows themselves take room away from the strip
    local overflow = total > barW - 8
    local inset    = overflow and 22 or 4
    f.tabStrip:SetPoint("TOPLEFT",     f.tabBar, "TOPLEFT",     inset, 0)
    f.tabStrip:SetPoint("BOTTOMRIGHT", f.tabBar, "BOTTOMRIGHT", -inset, 0)
    local visible = barW - 2 * inset
    local maxOff  = math.max(0, total - visible)
    local off     = math.min(math.max(UI._tabOffset or 0, 0), maxOff)
    UI._tabOffset = off
    f.tabRail:ClearAllPoints()
    f.tabRail:SetPoint("TOPLEFT", f.tabStrip, "TOPLEFT", -off, -2)
    f.tabPrev:SetShown(overflow)
    f.tabNext:SetShown(overflow)
    -- an arrow with nothing left in its direction dims instead of vanishing,
    -- so the pair keeps its place
    if overflow then
        f.tabPrev:SetAlpha(off > 0      and 1 or 0.35)
        f.tabNext:SetAlpha(off < maxOff and 1 or 0.35)
    end
end

function UI:ScrollTabs(dir)
    UI._tabOffset = (UI._tabOffset or 0) + dir * 160
    UI:UpdateTabScroll()
end

function UI:ShowTab(tabId)
    UI.currentTab = tabId
    local f = UI.mainFrame
    for _, tab in ipairs(f.tabs) do
        local mark = tab._activeMark or tab._underline
        if tab._tabId == tabId then
            if mark then mark:Show() end
            if tab._activeBG then tab._activeBG:Show() end
            tab._text:SetTextColor(1, 1, 1)
        else
            if mark then mark:Hide() end
            if tab._activeBG then tab._activeBG:Hide() end
            local c = ns.COLORS.textDim
            tab._text:SetTextColor(c.r, c.g, c.b)
        end
    end
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
        if UI.ShowDashboard then
            UI:ShowDashboard()
        elseif not UI.currentModule and ns.moduleOrder[1] then
            UI:ShowModulePage(ns.moduleOrder[1])
        end
    end
end
