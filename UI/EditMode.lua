-- Self-driven Edit Mode HUD: Blizzard's own is protected, so opening it from here would taint.
local _, ns = ...
local L  = ns.L
local UI = ns.UI
local accent = ns.COLORS.accent

-- Falls back to a local table when called before the DB exists.
local function gridState()
    local p = ns.db and ns.db.profile
    if p then
        p.editmode      = p.editmode      or {}
        p.editmode.grid = p.editmode.grid or {}
        local g = p.editmode.grid
        if g.show == nil then g.show = false end
        if g.snap == nil then g.snap = true  end
        if g.size == nil then g.size = 32    end
        return g
    end
    ns._editGridFallback = ns._editGridFallback or { show = false, snap = true, size = 32 }
    return ns._editGridFallback
end

function ns:EditSnapXY(x, y, ratio)
    local g = gridState()
    if not g.snap then return x, y end
    local s = g.size or 32
    if s <= 0 then return x, y end
    -- Snap in UIParent units (where the grid is drawn), then convert back to frame-local units.
    ratio = ratio or 1
    if ratio == 0 then ratio = 1 end
    local function snap(v) return (math.floor((v * ratio) / s + 0.5) * s) / ratio end
    return snap(x), snap(y)
end

local dim, toolbar, built
local gridPool = {}

local function refreshGrid()
    local g = gridState()
    for _, t in ipairs(gridPool) do t:Hide() end
    if not dim or not g.show then return end

    local accent = ns.COLORS.accent
    local w, h   = UIParent:GetWidth(), UIParent:GetHeight()
    if not w or not h or w <= 0 then return end
    local cx, cy = w / 2, h / 2
    local size   = g.size or 32
    if size < 4 then size = 4 end

    local idx = 0
    local function lineTex()
        idx = idx + 1
        local t = gridPool[idx]
        if not t then
            t = dim:CreateTexture(nil, "ARTWORK")
            gridPool[idx] = t
        end
        t:ClearAllPoints()
        return t
    end
    local function vline(px, center)
        local t = lineTex()
        if center then t:SetColorTexture(accent.r, accent.g, accent.b, 0.55)
        else           t:SetColorTexture(1, 1, 1, 0.07) end
        t:SetWidth(center and 2 or 1)
        t:SetPoint("TOP",    dim, "TOPLEFT",    px, 0)
        t:SetPoint("BOTTOM", dim, "BOTTOMLEFT", px, 0)
        t:Show()
    end
    local function hline(py, center)
        local t = lineTex()
        if center then t:SetColorTexture(accent.r, accent.g, accent.b, 0.55)
        else           t:SetColorTexture(1, 1, 1, 0.07) end
        t:SetHeight(center and 2 or 1)
        t:SetPoint("LEFT",  dim, "BOTTOMLEFT",  0, py)
        t:SetPoint("RIGHT", dim, "BOTTOMRIGHT", 0, py)
        t:Show()
    end

    vline(cx, true)
    local x = cx + size; while x < w do vline(x, false); x = x + size end
    x = cx - size;       while x > 0 do vline(x, false); x = x - size end

    hline(cy, true)
    local y = cy + size; while y < h do hline(y, false); y = y + size end
    y = cy - size;       while y > 0 do hline(y, false); y = y - size end
end
ns.RefreshEditGrid = refreshGrid

local function build()
    if built then return end
    built = true
    local accent = ns.COLORS.accent

    -- Strata stays below the movers (HIGH) so the boxes remain clickable.
    dim = CreateFrame("Frame", "VCUIEditDim", UIParent)
    dim:SetAllPoints(UIParent)
    dim:SetFrameStrata("MEDIUM")
    dim:EnableMouse(true)
    dim:SetScript("OnMouseDown", function() if ns.DeselectMover then ns:DeselectMover() end end)
    local fill = dim:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(dim)
    fill:SetColorTexture(0, 0, 0, 0.35)
    dim:Hide()

    -- DIALOG keeps the toolbar above the movers (HIGH) so its controls stay clickable.
    toolbar = CreateFrame("Frame", "VCUIEditToolbar", UIParent)
    toolbar:SetSize(960, 64)
    toolbar:SetPoint("TOP", UIParent, "TOP", 0, -140)
    toolbar:SetFrameStrata("DIALOG")
    toolbar:SetClampedToScreen(true)
    toolbar:EnableMouse(true)
    toolbar:SetMovable(true)
    toolbar:RegisterForDrag("LeftButton")
    toolbar:SetScript("OnDragStart", toolbar.StartMoving)
    toolbar:SetScript("OnDragStop",  toolbar.StopMovingOrSizing)
    UI:StyleBackdrop(toolbar, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    UI:CreateShadow(toolbar)

    local strip = toolbar:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT",  toolbar, "TOPLEFT",  0, 0)
    strip:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    UI.SetGradient(strip, "HORIZONTAL", accent.r, accent.g, accent.b, 0.0, accent.r, accent.g, accent.b, 0.9)

    local title = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(title, 13, "")
    title:SetPoint("TOP", toolbar, "TOP", 0, -8)
    title:SetText(L["EDIT MODE"])
    title:SetTextColor(accent.r, accent.g, accent.b)

    local ROWY = -32

    local exitBtn = UI:CreateButton(toolbar, {
        label   = L["Exit"],
        primary = true,
        width   = 96,
        tooltip = L["Close Edit Mode and lock all windows."],
        onClick = function() ns:SetEditMode(false) end,
    })
    exitBtn:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 14, ROWY)

    local gridTog = UI:CreateToggle(toolbar, {
        label   = L["Grid"],
        tooltip = L["Show an alignment grid."],
        get     = function() return gridState().show end,
        set     = function(_, v) gridState().show = v; refreshGrid() end,
    })
    gridTog:SetSize(108, 24)
    gridTog:SetPoint("LEFT", exitBtn, "RIGHT", 18, 0)

    local snapTog = UI:CreateToggle(toolbar, {
        label   = L["Snap"],
        tooltip = L["Snap windows to the grid while dragging."],
        get     = function() return gridState().snap end,
        set     = function(_, v) gridState().snap = v end,
    })
    snapTog:SetSize(140, 24)
    snapTog:SetPoint("LEFT", gridTog, "RIGHT", 14, 0)

    local cap = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(cap, 11)
    cap:SetText(L["Size"])
    cap:SetTextColor(0.65, 0.65, 0.70)
    cap:SetPoint("LEFT", snapTog, "RIGHT", 16, 0)

    local sizeSlider = UI:CreateSlider(toolbar, {
        label = "",
        min   = 8, max = 128, step = 4,
        width = 80,
        get   = function() return gridState().size end,
        set   = function(_, v) gridState().size = v; refreshGrid() end,
    })
    sizeSlider:SetPoint("LEFT", cap, "RIGHT", 8, 0)

    local resetBtn = UI:CreateButton(toolbar, {
        label   = L["Reset"],
        width   = 130,
        tooltip = L["Reset all VuloUI window positions to the screen centre."],
        onClick = function() StaticPopup_Show("VCUI_EDIT_RESET") end,
    })
    resetBtn:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", -16, ROWY)

    local layoutsBtn = UI:CreateButton(toolbar, {
        label   = L["Layouts"],
        width   = 120,
        tooltip = L["Save, load, export and import named window layouts."],
        onClick = function() if ns.ToggleLayouts then ns:ToggleLayouts() end end,
    })
    layoutsBtn:SetPoint("RIGHT", resetBtn, "LEFT", -10, 0)
end

function ns:IsEditModeActive()
    return ns._editActive and true or false
end

-- Lets modules with their own positioner (not a CreateMover box) follow the same toggle.
ns._editHooks = ns._editHooks or {}
function ns:RegisterEditModeHook(fn)
    if type(fn) == "function" then ns._editHooks[#ns._editHooks + 1] = fn end
end

function ns:SetEditMode(state)
    state = state and true or false
    if state and ns:InCombat() then
        ns:Print(L["Not possible in combat."])
        return
    end
    build()
    ns._editActive = state
    if state then
        if ns.PrepareBlizzMovers then ns:PrepareBlizzMovers() end
        dim:Show()
        toolbar:Show()
        refreshGrid()
    else
        -- Abort an in-flight drag (combat auto-exit can fire mid-drag) or the frame sticks to the cursor.
        local d = ns._draggingMover
        if d and d.target and d.target.StopMovingOrSizing then d.target:StopMovingOrSizing() end
        if ns.DeselectMover then ns:DeselectMover() end
        if ns.HideLayouts then ns:HideLayouts() end
        ns._draggingMover = nil
        if ns._hideGuides then ns._hideGuides() end
        dim:Hide()
        toolbar:Hide()
    end
    ns:SetMoversEditMode(state)
    -- Restyle on both edges: leaving must drop free-move boxes back to their quiet look.
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
    for _, fn in ipairs(ns._editHooks) do pcall(fn, state) end
end

StaticPopupDialogs["VCUI_EDIT_RESET"] = {
    text         = L["Reset all VuloUI window positions to the screen centre?"],
    button1      = YES,
    button2      = NO,
    OnAccept     = function() if ns.ResetAllMovers then ns:ResetAllMovers() end end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_DISABLED")
combat:RegisterEvent("PLAYER_REGEN_ENABLED")
combat:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if ns:IsEditModeActive() then
            ns._editResume = true
            ns:SetEditMode(false)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns._editResume then
            ns._editResume = false
            ns:SetEditMode(true)
        end
    end
end)

local disp = CreateFrame("Frame")
disp:RegisterEvent("DISPLAY_SIZE_CHANGED")
disp:RegisterEvent("UI_SCALE_CHANGED")
disp:SetScript("OnEvent", function()
    if ns:IsEditModeActive() then refreshGrid() end
end)

SLASH_VCUIEDIT1 = "/vedit"
SlashCmdList["VCUIEDIT"] = function()
    ns:SetEditMode(not ns:IsEditModeActive())
end

local function snapVal(v, size)
    if not size or size <= 0 then return v end
    return math.floor(v / size + 0.5) * size
end

local function cleanLabel(s)
    s = tostring(s or "Frame")
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- ns._selection holds all selected movers; ns._selectedMover is the primary one the panel edits.
ns._selection = ns._selection or {}

local function selIndex(m)
    for i, x in ipairs(ns._selection) do if x == m then return i end end
end
function ns:IsSelected(m) return selIndex(m) ~= nil end

function ns:RefreshMoverStyles()
    for _, m in ipairs(ns._movers) do
        local sel     = ns:IsSelected(m)
        local primary = (m == ns._selectedMover)
        local sc      = m.opts and m.opts.scope
        local editing = ns._moverEditGlobal or (sc and ns._moverEditScopes and ns._moverEditScopes[sc]) or false
        -- Free-move boxes outside edit mode stay grabbable but go quiet, else they read as a stuck overlay.
        local quiet = m:IsShown() and not editing
            and not (m.opts and m.opts.db and m.opts.db.unlocked)
        if m.bg then
            if quiet then
                m.bg:SetColorTexture(accent.r, accent.g, accent.b, 0.04)
            else
                m.bg:SetColorTexture(accent.r, accent.g, accent.b, sel and 0.5 or 0.18)
            end
        end
        if m.label then m.label:SetShown(not quiet) end
        if m.hint  then m.hint:SetShown(not quiet) end
        if m.border and m.border.SetBackdropBorderColor then
            if quiet then
                m.border:SetBackdropBorderColor(accent.r * 0.6, accent.g * 0.6, accent.b * 0.6, 0.35)
            elseif primary then
                m.border:SetBackdropBorderColor(accent.r, accent.g, accent.b, 1)
            elseif sel then
                m.border:SetBackdropBorderColor(accent.r, accent.g, accent.b, 0.85)
            else
                m.border:SetBackdropBorderColor(accent.r * 0.7, accent.g * 0.7, accent.b * 0.7, 0.8)
            end
        end
    end
end

local panel

local ANCHOR_POINTS = {
    { value = "CENTER",      text = "Center" },
    { value = "TOP",         text = "Top" },
    { value = "BOTTOM",      text = "Bottom" },
    { value = "LEFT",        text = "Left" },
    { value = "RIGHT",       text = "Right" },
    { value = "TOPLEFT",     text = "Top-Left" },
    { value = "TOPRIGHT",    text = "Top-Right" },
    { value = "BOTTOMLEFT",  text = "Bottom-Left" },
    { value = "BOTTOMRIGHT", text = "Bottom-Right" },
}

-- Reads the live target, not the stored db (which only updates on drop), so X/Y track a drag.
local function moverXY(m)
    local x, y = ns:GetCenterOffsets(m and m.target)
    if x and y then return x, y end
    if m and m.opts and m.opts.db then return m.opts.db.x or 0, m.opts.db.y or 0 end
    return 0, 0
end

local function refreshPanel()
    if not panel or not panel:IsShown() then return end
    local m = ns._selectedMover
    if not m or not m.opts then return end
    local name = cleanLabel(m.opts.label)
    local n = #ns._selection
    if n > 1 then
        name = name .. string.format("  %s+%d|r", (ns.C and ns.C.accent) or "|cff9b6cff", n - 1)
    end
    panel.title:SetText(name)
    local x, y = moverXY(m)
    if not panel.xBox._editBox:HasFocus() then
        panel.xBox._editBox:SetText(tostring(math.floor(x + 0.5)))
    end
    if not panel.yBox._editBox:HasFocus() then
        panel.yBox._editBox:SetText(tostring(math.floor(y + 0.5)))
    end
end

local function buildPanel()
    if panel then return end
    panel = CreateFrame("Frame", "VCUIEditPanel", UIParent)
    panel:SetSize(300, 184)
    panel:SetPoint("RIGHT", UIParent, "RIGHT", -48, 60)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
    UI:StyleBackdrop(panel, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    UI:CreateShadow(panel)

    local strip = panel:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, 0)
    strip:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    UI.SetGradient(strip, "HORIZONTAL", accent.r, accent.g, accent.b, 0.0, accent.r, accent.g, accent.b, 0.9)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(panel.title, 14)
    panel.title:SetPoint("TOPLEFT",  panel, "TOPLEFT",  16, -13)
    panel.title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -32, -13)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)
    panel.title:SetTextColor(accent.r, accent.g, accent.b)

    local close = CreateFrame("Button", nil, panel)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -8)
    local cfs = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cfs:SetPoint("CENTER", close, "CENTER", 0, 0)
    cfs:SetText("x")
    cfs:SetTextColor(0.7, 0.7, 0.75)
    close:SetScript("OnEnter", function() cfs:SetTextColor(accent.r, accent.g, accent.b) end)
    close:SetScript("OnLeave", function() cfs:SetTextColor(0.7, 0.7, 0.75) end)
    close:SetScript("OnClick", function() if ns.DeselectMover then ns:DeselectMover() end end)

    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  14, -38)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -38)
    sep:SetHeight(1)
    sep:SetColorTexture(1, 1, 1, 0.07)

    local cap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(cap, 10)
    cap:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -46)
    cap:SetText(L["POSITION"])
    cap:SetTextColor(0.55, 0.55, 0.62)

    panel.xBox = UI:CreateEditBox(panel, {
        label = "X", numeric = true, commitOnFocusLost = true, width = 124, editWidth = 100,
        get = function() local x = moverXY(ns._selectedMover); return math.floor(x + 0.5) end,
        set = function(_, v)
            local m = ns._selectedMover
            if m and v then ns:MoverSetCenter(m, v, m.opts.db.y or 0); refreshPanel() end
        end,
    })
    panel.xBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -62)

    panel.yBox = UI:CreateEditBox(panel, {
        label = "Y", numeric = true, commitOnFocusLost = true, width = 124, editWidth = 100,
        get = function() local _, y = moverXY(ns._selectedMover); return math.floor(y + 0.5) end,
        set = function(_, v)
            local m = ns._selectedMover
            if m and v then ns:MoverSetCenter(m, m.opts.db.x or 0, v); refreshPanel() end
        end,
    })
    panel.yBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -62)

    panel.scaleCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.scaleCap, 10)
    panel.scaleCap:SetText(L["SCALE"])
    panel.scaleCap:SetTextColor(0.55, 0.55, 0.62)
    panel.scaleSlider = UI:CreateSlider(panel, {
        label = "", min = 0.5, max = 2.0, step = 0.05, width = 150,
        get = function() local m = ns._selectedMover; return (m and m.opts.db.scale) or 1 end,
        set = function(_, v) local m = ns._selectedMover; if m then ns:MoverSetScale(m, v) end end,
    })

    panel.anchorCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.anchorCap, 10)
    panel.anchorCap:SetText(L["ANCHOR"])
    panel.anchorCap:SetTextColor(0.55, 0.55, 0.62)

    panel.anchorToggle = UI:CreateToggle(panel, {
        label   = "",
        tooltip = L["Pin this frame to a screen edge/corner so it stays put across resolution changes. Off keeps it centred."],
        get = function() local m = ns._selectedMover; return m and ns:IsMoverAnchorEnabled(m) end,
        set = function(_, v)
            local m = ns._selectedMover
            if m then ns:MoverSetAnchorEnabled(m, v); if ns.OnAnchorToggled then ns:OnAnchorToggled() end end
        end,
    })
    panel.anchorToggle:SetSize(44, 22)

    panel.anchorDrop = UI:CreateDropdown(panel, {
        label = "", width = 150, values = ANCHOR_POINTS,
        tooltip = L["Which screen point the frame is pinned to (keeps it put across resolution changes)."],
        get = function() local m = ns._selectedMover; return (m and m.opts.db.anchor) or "CENTER" end,
        set = function(_, v) local m = ns._selectedMover; if m then ns:MoverSetAnchor(m, v) end end,
    })

    panel.linkCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.linkCap, 10)
    panel.linkCap:SetText(L["FOLLOW WINDOW"])
    panel.linkCap:SetTextColor(0.55, 0.55, 0.62)

    panel.linkDrop = UI:CreateDropdown(panel, {
        label = "", width = 172, values = {},
        tooltip = L["Pins this window to another one - it then moves along whenever that window is moved. Dragging this window keeps the pin and just updates the distance."],
        get = function()
            local m = ns._selectedMover
            local l = m and m.key and ns:GetMoverLink(m.key)
            return (l and l.to) or ""
        end,
        set = function(_, v)
            local m = ns._selectedMover
            if not m then return end
            if not ns:SetMoverLink(m, v ~= "" and v or nil) then
                ns:Print(L["Not possible - that would create a loop."])
            end
            if panel.linkDrop._button and panel.linkDrop._button._refresh then
                panel.linkDrop._button._refresh()
            end
        end,
    })

    panel.freeCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.freeCap, 10)
    panel.freeCap:SetText(L["FREE MOVE"])
    panel.freeCap:SetTextColor(0.55, 0.55, 0.62)

    panel.freeToggle = UI:CreateToggle(panel, {
        label   = "",
        tooltip = L["Leave this window unlocked so you can still drag it after closing Edit Mode. Stays unlocked through /reload."],
        get = function() local m = ns._selectedMover; return m and ns:IsMoverFreeMove(m) end,
        set = function(_, v) local m = ns._selectedMover; if m then ns:SetMoverFreeMove(m, v) end end,
    })
    panel.freeToggle:SetSize(44, 22)

    panel.reset = UI:CreateButton(panel, {
        label   = L["Reset this frame"],
        width   = 264,
        onClick = function()
            local m = ns._selectedMover
            if m then
                ns._inMoverReset = true          -- flags an explicit reset, not a 0,0 drop
                ns:MoverSetCenter(m, 0, 0)
                ns._inMoverReset = false
                refreshPanel()
            end
        end,
    })

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(hint, 11)
    hint:SetPoint("BOTTOMLEFT",  panel, "BOTTOMLEFT",  16, 14)
    hint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 14)
    hint:SetJustifyH("LEFT")
    hint:SetSpacing(2)
    hint:SetTextColor(0.55, 0.55, 0.62)
    hint:SetText(L["Drag a box, or hover it and use the arrow keys (Shift = 5px). Shift+click to select several and drag them together."])

    panel._acc = 0
    panel:SetScript("OnUpdate", function(self, elapsed)
        self._acc = self._acc + elapsed
        if self._acc < 0.05 then return end
        self._acc = 0
        refreshPanel()
    end)
end

local function refreshAnchorEnabled(m)
    if not (panel and panel.anchorDrop) then return end
    local on = m and ns:IsMoverAnchorEnabled(m)
    local a = on and 1 or 0.4
    panel.anchorDrop:SetAlpha(a)
    if panel.anchorDrop.EnableMouse then panel.anchorDrop:EnableMouse(on and true or false) end
    if panel.anchorDrop._button and panel.anchorDrop._button.EnableMouse then
        panel.anchorDrop._button:EnableMouse(on and true or false)
    end
end

local function layoutPanel(m)
    if not panel then return end
    local scalable   = m and m.opts and m.opts.scalable
    local anchorable = m and m.opts and m.opts.anchorable
    local y = -100

    if scalable then
        panel.scaleCap:Show(); panel.scaleSlider:Show()
        panel.scaleCap:ClearAllPoints()
        panel.scaleCap:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y)
        panel.scaleSlider:ClearAllPoints()
        panel.scaleSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y - 20)
        y = y - 48
    else
        panel.scaleCap:Hide(); panel.scaleSlider:Hide()
    end

    if anchorable then
        panel.anchorCap:Show(); panel.anchorToggle:Show(); panel.anchorDrop:Show()
        panel.anchorCap:ClearAllPoints()
        panel.anchorCap:SetPoint("LEFT", panel, "TOPLEFT", 18, y - 13)
        panel.anchorToggle:ClearAllPoints()
        panel.anchorToggle:SetPoint("LEFT", panel.anchorCap, "RIGHT", 10, 0)
        panel.anchorDrop:ClearAllPoints()
        panel.anchorDrop:SetPoint("LEFT", panel.anchorToggle, "RIGHT", 12, 0)
        refreshAnchorEnabled(m)
        y = y - 36
    else
        panel.anchorCap:Hide(); panel.anchorToggle:Hide(); panel.anchorDrop:Hide()
    end

    if m and m.key then
        panel.linkCap:Show(); panel.linkDrop:Show()
        panel.linkCap:ClearAllPoints()
        panel.linkCap:SetPoint("LEFT", panel, "TOPLEFT", 18, y - 13)
        panel.linkDrop:ClearAllPoints()
        panel.linkDrop:SetPoint("LEFT", panel.linkCap, "RIGHT", 10, 0)
        y = y - 36
    else
        panel.linkCap:Hide(); panel.linkDrop:Hide()
    end

    panel.freeCap:Show(); panel.freeToggle:Show()
    panel.freeCap:ClearAllPoints()
    panel.freeCap:SetPoint("LEFT", panel, "TOPLEFT", 18, y - 13)
    panel.freeToggle:ClearAllPoints()
    panel.freeToggle:SetPoint("RIGHT", panel, "TOPRIGHT", -18, y - 13)
    y = y - 34

    panel.reset:ClearAllPoints()
    panel.reset:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y - 8)
    panel:SetHeight(-(y - 8) + 92)
end

-- the candidate list depends on the selected mover (no self, no loops), so it
-- is rebuilt into the live config each time — the popup reads values at click
local function rebuildLinkValues(m)
    if not (panel and panel.linkDrop and panel.linkDrop._vcConfig) then return end
    local vals = { { value = "", text = L["- none -"] } }
    if m and m.key then
        local sorted = {}
        for _, other in ipairs(ns._movers) do
            if other ~= m and other.key
                and not ns:MoverLinkWouldCycle(m.key, other.key) then
                sorted[#sorted + 1] = {
                    value = other.key,
                    text  = (other.opts and other.opts.label) or other.key,
                }
            end
        end
        table.sort(sorted, function(a, b) return tostring(a.text) < tostring(b.text) end)
        for _, v in ipairs(sorted) do vals[#vals + 1] = v end
    end
    panel.linkDrop._vcConfig.values = vals
end

local function refreshCaps(m)
    if m and m.opts and m.opts.scalable and panel.scaleSlider._vcSetup then
        panel.scaleSlider._vcSetup(panel.scaleSlider, panel.scaleSlider._vcConfig)
    end
    if m and m.opts and m.opts.anchorable then
        if panel.anchorDrop._button then panel.anchorDrop._button._refresh() end
        if panel.anchorToggle._refresh then panel.anchorToggle._refresh() end
        refreshAnchorEnabled(m)
    end
    rebuildLinkValues(m)
    if panel.linkDrop and panel.linkDrop._button and panel.linkDrop._button._refresh then
        panel.linkDrop._button._refresh()
    end
    if panel.freeToggle._refresh then panel.freeToggle._refresh() end
end

function ns:OnAnchorToggled()
    refreshAnchorEnabled(ns._selectedMover)
end

-- A plain click on a member of a multi-selection keeps the group and only retargets the primary.
function ns:SelectMover(mover, additive)
    if not mover then return end
    -- Selecting outside edit mode would strand the panel with no dim to deselect against; dragging still works.
    if not ns:IsEditModeActive() then return end

    if additive then
        local i = selIndex(mover)
        if i then
            local wasPrimary = (mover == ns._selectedMover)
            table.remove(ns._selection, i)
            if wasPrimary then ns._selectedMover = ns._selection[#ns._selection] end
        else
            ns._selection[#ns._selection + 1] = mover
            ns._selectedMover = mover
        end
    elseif selIndex(mover) and #ns._selection > 1 then
        ns._selectedMover = mover
    else
        wipe(ns._selection)
        ns._selection[1]  = mover
        ns._selectedMover = mover
    end

    if not ns._selectedMover then
        if panel then panel:Hide() end
        ns:RefreshMoverStyles()
        return
    end

    buildPanel()
    layoutPanel(ns._selectedMover)
    refreshCaps(ns._selectedMover)
    panel:Show()
    ns:RefreshMoverStyles()
    refreshPanel()
end

function ns:DeselectMover()
    wipe(ns._selection)
    ns._selectedMover = nil
    ns._groupDrag = nil
    if panel then panel:Hide() end
    ns:RefreshMoverStyles()
end

-- Only the leader snaps; followers keep their relative offset so the group stays rigid.
function ns:BeginGroupDrag(leader)
    ns._groupDrag = nil
    if #ns._selection <= 1 or not (leader and ns:IsSelected(leader) and leader.target) then return end
    -- Captures are in each owning frame's local space, or a scaled follower teleports on the first tick.
    local followers = {}
    for _, m in ipairs(ns._selection) do
        if m ~= leader and m.target then
            local x, y = ns:GetCenterOffsets(m.target)
            if x and y then
                followers[#followers + 1] = { mover = m, x = x, y = y }
            end
        end
    end
    if #followers == 0 then return end
    local lx, ly = ns:GetCenterOffsets(leader.target)
    if not lx then return end
    ns._groupDrag = { lx = lx, ly = ly, followers = followers }
end

function ns:UpdateGroupDrag()
    local gd = ns._groupDrag
    local leader = ns._draggingMover
    if not (gd and leader and leader.target) then return end
    local lx, ly = ns:GetCenterOffsets(leader.target)
    if not lx then return end
    local dx, dy = lx - gd.lx, ly - gd.ly
    local lscale = leader.target:GetEffectiveScale() or 1
    for _, f in ipairs(gd.followers) do
        local t = f.mover.target
        -- Convert the delta into this follower's space so a scaled frame tracks the leader 1:1 on screen.
        local conv = lscale / (t:GetEffectiveScale() or 1)
        t:ClearAllPoints()
        t:SetPoint("CENTER", UIParent, "CENTER", f.x + dx * conv, f.y + dy * conv)
    end
end

-- sdx/sdy is the snap correction the leader took, reapplied so the group keeps its arrangement.
function ns:EndGroupDrag(sdx, sdy)
    local gd = ns._groupDrag
    ns._groupDrag = nil
    if not gd then return end
    sdx, sdy = sdx or 0, sdy or 0
    for _, f in ipairs(gd.followers) do
        local x, y = ns:GetCenterOffsets(f.mover.target)
        if x and y then
            ns:MoverSetCenter(f.mover, x + sdx, y + sdy)
        end
    end
end

function ns:NudgeGroupFollowers(leader, dx, dy)
    if #ns._selection <= 1 or not ns:IsSelected(leader) then return end
    for _, m in ipairs(ns._selection) do
        if m ~= leader and m.opts and m.opts.db then
            m.opts.db.x = (m.opts.db.x or 0) + dx
            m.opts.db.y = (m.opts.db.y or 0) + dy
            ns:ApplyMover(m)
        end
    end
end

function ns:OnMoverMoved(mover)
    if mover == ns._selectedMover then refreshPanel() end
end

local guideFrame, guidePool = nil, {}
local function ensureGuideFrame()
    if guideFrame then return end
    guideFrame = CreateFrame("Frame", "VCUIEditGuides", UIParent)
    guideFrame:SetAllPoints(UIParent)
    guideFrame:SetFrameStrata("DIALOG")   -- above the mover boxes (HIGH)
    guideFrame:EnableMouse(false)
end
local function hideGuides()
    for _, t in ipairs(guidePool) do t:Hide() end
end
ns._hideGuides = hideGuides
local function drawGuides(gx, gy, persist)
    ensureGuideFrame()
    hideGuides()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local i = 0
    local function gtex()
        i = i + 1
        local t = guidePool[i]
        if not t then t = guideFrame:CreateTexture(nil, "OVERLAY"); guidePool[i] = t end
        t:ClearAllPoints()
        t:SetColorTexture(accent.r, accent.g, accent.b, 0.9)
        return t
    end
    if gx then
        local t = gtex(); t:SetWidth(2)
        local sx = w / 2 + gx
        t:SetPoint("TOP",    guideFrame, "TOPLEFT",    sx, 0)
        t:SetPoint("BOTTOM", guideFrame, "BOTTOMLEFT", sx, 0)
        t:Show()
    end
    if gy then
        local t = gtex(); t:SetHeight(2)
        local sy = h / 2 + gy
        t:SetPoint("LEFT",  guideFrame, "BOTTOMLEFT",  0, sy)
        t:SetPoint("RIGHT", guideFrame, "BOTTOMRIGHT", 0, sy)
        t:Show()
    end
    if not persist and (gx or gy) and C_Timer and C_Timer.After then
        C_Timer.After(0.5, hideGuides)
    end
end

local MAG_THRESH = 12

-- Math runs in UIParent units (where guides are drawn); returned dx/dy convert back to frame-local, lineX/lineY stay UI-space.
local function computeSnap(mover, x, y)
    local target = mover.target
    if not target then return end
    local r = ns.GetScaleRatio and ns:GetScaleRatio(target) or 1
    local xu, yu = x * r, y * r
    local hw = (target:GetWidth()  or 0) / 2 * r
    local hh = (target:GetHeight() or 0) / 2 * r

    local xLines, yLines = { 0 }, { 0 }
    for _, o in ipairs(ns._movers) do
        if o ~= mover and o.target and o:IsShown() then
            local ox, oy = ns:GetCenterOffsets(o.target)
            if ox and oy then
                local orr = ns.GetScaleRatio and ns:GetScaleRatio(o.target) or 1
                local ocx, ocy = ox * orr, oy * orr
                local ohw = (o.target:GetWidth()  or 0) / 2 * orr
                local ohh = (o.target:GetHeight() or 0) / 2 * orr
                xLines[#xLines + 1] = ocx; xLines[#xLines + 1] = ocx - ohw; xLines[#xLines + 1] = ocx + ohw
                yLines[#yLines + 1] = ocy; yLines[#yLines + 1] = ocy - ohh; yLines[#yLines + 1] = ocy + ohh
            end
        end
    end

    local function best(features, lines)
        local bd, bl
        for _, f in ipairs(features) do
            for _, cl in ipairs(lines) do
                local d = cl - f
                if math.abs(d) <= MAG_THRESH and (not bd or math.abs(d) < math.abs(bd)) then
                    bd, bl = d, cl
                end
            end
        end
        return bd, bl
    end

    local dx, lineX = best({ xu - hw, xu, xu + hw }, xLines)
    local dy, lineY = best({ yu - hh, yu, yu + hh }, yLines)
    if dx then dx = dx / r end
    if dy then dy = dy / r end
    return dx, lineX, dy, lineY
end

function ns:EditResolveDrop(mover, x, y)
    local g = gridState()
    local r = (ns.GetScaleRatio and mover.target) and ns:GetScaleRatio(mover.target) or 1
    local dx, lineX, dy, lineY = computeSnap(mover, x, y)
    if dx then x = x + dx elseif g.snap then x = snapVal(x * r, g.size) / r end
    if dy then y = y + dy elseif g.snap then y = snapVal(y * r, g.size) / r end
    drawGuides(dx and lineX or nil, dy and lineY or nil)
    return x, y
end

-- Purely visual preview; the actual snap still happens on drop.
local liveGuideDriver = CreateFrame("Frame")
liveGuideDriver:SetScript("OnUpdate", function()
    local m = ns._draggingMover
    if not (m and m.target and ns:IsEditModeActive()) then return end
    if ns._groupDrag then ns:UpdateGroupDrag() end
    local lx, ly = ns:GetCenterOffsets(m.target)
    if not lx then return end
    local dx, lineX, dy, lineY = computeSnap(m, lx, ly)
    drawGuides(dx and lineX or nil, dy and lineY or nil, true)
end)

local cycleHint, altWasDown
local function ensureCycleHint()
    ensureGuideFrame()
    if cycleHint then return end
    cycleHint = guideFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(cycleHint, 12)
    cycleHint:SetTextColor(accent.r, accent.g, accent.b)
    cycleHint:Hide()
end
local function updateCycle()
    if not ns:IsEditModeActive() then
        if cycleHint then cycleHint:Hide() end
        altWasDown = false
        return
    end
    local list = {}
    for _, m in ipairs(ns._movers) do
        if m:IsShown() and m:IsMouseOver() then list[#list + 1] = m end
    end
    local altDown = IsAltKeyDown() and true or false
    if #list > 1 then
        ensureCycleHint()
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        if cx and s and s > 0 then
            cycleHint:ClearAllPoints()
            cycleHint:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / s + 16, cy / s + 16)
            cycleHint:SetText(string.format(L["%d frames here - hold Alt to cycle"], #list))
            cycleHint:Show()
        end
        if altDown and not altWasDown then
            table.sort(list, function(a, b) return a:GetFrameLevel() < b:GetFrameLevel() end)
            list[1]:Raise()
        end
    elseif cycleHint then
        cycleHint:Hide()
    end
    altWasDown = altDown
end

local cycleDriver = CreateFrame("Frame")
local cycleAcc = 0
cycleDriver:SetScript("OnUpdate", function(_, elapsed)
    cycleAcc = cycleAcc + elapsed
    if cycleAcc < 0.15 then return end
    cycleAcc = 0
    updateCycle()
end)

-- Layouts live in ns.db.global so they are shared across profiles; capture/apply lives in Core/Mover.lua.
local layoutsPanel
local selectedLayout
local layoutValues = {}

local function layoutStore()
    local g = ns.db and ns.db.global
    if g then
        g.editLayouts = g.editLayouts or {}
        return g.editLayouts
    end
    ns._layoutFallback = ns._layoutFallback or {}
    return ns._layoutFallback
end

local function rebuildLayoutList(preferred)
    wipe(layoutValues)
    local store = layoutStore()
    local names = {}
    for name in pairs(store) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        layoutValues[#layoutValues + 1] = { value = name, text = name }
    end
    if preferred and store[preferred] then
        selectedLayout = preferred
    elseif not (selectedLayout and store[selectedLayout]) then
        selectedLayout = names[1]
    end
    if layoutsPanel and layoutsPanel.dropdown and layoutsPanel.dropdown._button then
        layoutsPanel.dropdown._button._refresh()
        if not selectedLayout then
            layoutsPanel.dropdown._button._setText(L["No layouts saved"])
        end
    end
end

local function saveLayout(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
    if not name or name == "" then return end
    layoutStore()[name] = ns:CaptureLayout()
    rebuildLayoutList(name)
    ns:Print(string.format(L["Layout '%s' saved."], name))
end

local function loadSelected()
    local store = layoutStore()
    if not (selectedLayout and store[selectedLayout]) then
        ns:Print(L["No layout selected."]); return
    end
    local n = ns:ApplyLayout(store[selectedLayout])
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
    ns:Print(string.format(L["Applied layout '%s' (%d frames)."], selectedLayout, n))
end

local function importLayout(str)
    local name, snap = ns:DeserializeLayout(str)
    if not name then
        ns:Print(string.format(L["Import failed (%s)."], tostring(snap)))
        return
    end
    if name == "" then name = L["Imported"] end
    -- De-dupe without parentheses; the dropdown strips "(...)" from display.
    local store = layoutStore()
    local base, i, final = name, 2, name
    while store[final] do final = base .. " " .. i; i = i + 1 end
    store[final] = snap
    rebuildLayoutList(final)
    ns:Print(string.format(L["Layout '%s' imported."], final))
end

-- Newer clients expose the popup box as .EditBox, older ones as .editBox.
local function popupBox(self)
    return self.EditBox or self.editBox
        or (self.GetName and _G[(self:GetName() or "") .. "EditBox"])
end

StaticPopupDialogs["VCUI_LAYOUT_SAVE"] = {
    text = L["Name for this layout:"],
    button1 = SAVE or L["Save"], button2 = CANCEL,
    hasEditBox = true, maxLetters = 48,
    OnShow   = function(self) local b = popupBox(self); if b then b:SetText(""); b:SetFocus() end end,
    OnAccept = function(self) local b = popupBox(self); if b then saveLayout(b:GetText()) end end,
    EditBoxOnEnterPressed  = function(self) saveLayout(self:GetText()); self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["VCUI_LAYOUT_IMPORT"] = {
    text = L["Paste a layout string and confirm:"],
    button1 = L["Import"], button2 = CANCEL,
    hasEditBox = true, maxLetters = 0,
    OnShow   = function(self) local b = popupBox(self); if b then b:SetText(""); b:SetFocus() end end,
    OnAccept = function(self) local b = popupBox(self); if b then importLayout(b:GetText()) end end,
    EditBoxOnEnterPressed  = function(self) importLayout(self:GetText()); self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["VCUI_LAYOUT_EXPORT"] = {
    text = L["Copy this string (Ctrl+A, Ctrl+C):"],
    button1 = OKAY or L["Close"],
    hasEditBox = true, maxLetters = 0,
    OnShow = function(self, data)
        local b = popupBox(self)
        if b then b:SetText(data or ""); b:HighlightText(); b:SetFocus() end
    end,
    EditBoxOnEnterPressed  = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["VCUI_LAYOUT_DELETE"] = {
    text = L["Delete layout '%s'?"],
    button1 = YES, button2 = NO,
    OnAccept = function()
        if selectedLayout then layoutStore()[selectedLayout] = nil; rebuildLayoutList() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function buildLayoutsPanel()
    if layoutsPanel then return end
    local p = CreateFrame("Frame", "VCUILayoutsPanel", UIParent)
    layoutsPanel = p
    p:SetSize(260, 252)
    p:SetPoint("LEFT", UIParent, "LEFT", 48, 40)
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop",  p.StopMovingOrSizing)
    UI:StyleBackdrop(p, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    UI:CreateShadow(p)

    local strip = p:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT",  p, "TOPLEFT",  0, 0)
    strip:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    UI.SetGradient(strip, "HORIZONTAL", accent.r, accent.g, accent.b, 0.0, accent.r, accent.g, accent.b, 0.9)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(title, 14)
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -13)
    title:SetText(L["LAYOUTS"])
    title:SetTextColor(accent.r, accent.g, accent.b)

    local close = CreateFrame("Button", nil, p)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -6, -8)
    local cfs = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cfs:SetPoint("CENTER", close, "CENTER", 0, 0)
    cfs:SetText("x"); cfs:SetTextColor(0.7, 0.7, 0.75)
    close:SetScript("OnEnter", function() cfs:SetTextColor(accent.r, accent.g, accent.b) end)
    close:SetScript("OnLeave", function() cfs:SetTextColor(0.7, 0.7, 0.75) end)
    close:SetScript("OnClick", function() p:Hide() end)

    local sep = p:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT",  p, "TOPLEFT",  14, -38)
    sep:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -38)
    sep:SetHeight(1); sep:SetColorTexture(1, 1, 1, 0.07)

    local cap = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(cap, 10)
    cap:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -46)
    cap:SetText(L["SAVED"]); cap:SetTextColor(0.55, 0.55, 0.62)

    p.dropdown = UI:CreateDropdown(p, {
        label = "", width = 228, values = layoutValues,
        tooltip = L["Pick a saved layout to load, delete or export."],
        get = function() return selectedLayout end,
        set = function(_, v) selectedLayout = v end,
    })
    p.dropdown:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -60)

    local loadBtn = UI:CreateButton(p, {
        label = L["Load"], width = 110, primary = true,
        onClick = function() loadSelected() end,
    })
    loadBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -92)

    local delBtn = UI:CreateButton(p, {
        label = L["Delete"], width = 110,
        onClick = function()
            if selectedLayout then StaticPopup_Show("VCUI_LAYOUT_DELETE", selectedLayout)
            else ns:Print(L["No layout selected."]) end
        end,
    })
    delBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -92)

    local saveBtn = UI:CreateButton(p, {
        label = L["Save current as..."], width = 228,
        onClick = function() StaticPopup_Show("VCUI_LAYOUT_SAVE") end,
    })
    saveBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -124)

    local sep2 = p:CreateTexture(nil, "ARTWORK")
    sep2:SetPoint("TOPLEFT",  p, "TOPLEFT",  14, -158)
    sep2:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -158)
    sep2:SetHeight(1); sep2:SetColorTexture(1, 1, 1, 0.07)

    local expBtn = UI:CreateButton(p, {
        label = L["Export"], width = 110,
        onClick = function()
            local store = layoutStore()
            if selectedLayout and store[selectedLayout] then
                StaticPopup_Show("VCUI_LAYOUT_EXPORT", nil, nil,
                    ns:SerializeLayout(selectedLayout, store[selectedLayout]))
            else ns:Print(L["No layout selected."]) end
        end,
    })
    expBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -168)

    local impBtn = UI:CreateButton(p, {
        label = L["Import"], width = 110,
        onClick = function() StaticPopup_Show("VCUI_LAYOUT_IMPORT") end,
    })
    impBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -168)

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(hint, 11)
    hint:SetPoint("BOTTOMLEFT",  p, "BOTTOMLEFT",  16, 14)
    hint:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 14)
    hint:SetJustifyH("LEFT"); hint:SetSpacing(2); hint:SetTextColor(0.55, 0.55, 0.62)
    hint:SetText(L["Save your window arrangement, then load or share it any time."])
end

function ns:ToggleLayouts()
    buildLayoutsPanel()
    if layoutsPanel:IsShown() then
        layoutsPanel:Hide()
    else
        rebuildLayoutList()
        layoutsPanel:Show()
    end
end

function ns:HideLayouts()
    if layoutsPanel then layoutsPanel:Hide() end
end
