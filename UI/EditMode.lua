-- =========================================================
-- VuloClassicUI / UI / EditMode
-- A global Edit Mode HUD in our EUI style, built ON TOP of the existing mover
-- engine (Core/Mover.lua). Entering Edit Mode shows every registered mover box
-- at once, plus:
--   - a dimmed fullscreen overlay so the movers pop,
--   - an optional alignment grid (purple centre cross + faint lines),
--   - a draggable toolbar (Exit / Grid / Snap / grid size / Reset positions).
--
-- Grid snapping is wired back into the mover drag via ns:EditSnapXY (called from
-- Core/Mover.lua's OnDragStop). Settings live in ns.db.profile.editmode.grid.
--
-- NOTE: addons may not open Blizzard's own Edit Mode (protected -> taint), so
-- this HUD is fully self-driven. Where the client HAS Blizzard Edit Mode
-- (Anniversary), Core/Mover.lua mirrors its open/close into ns:SetEditMode.
-- =========================================================
local _, ns = ...
local L  = ns.L
local UI = ns.UI
local accent = ns.COLORS.accent

-- ---------------------------------------------------------
-- Grid settings (persisted per profile; safe fallback before the DB is ready)
-- ---------------------------------------------------------
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

-- ---------------------------------------------------------
-- Grid snap, called from Core/Mover.lua OnDragStop. x/y are CENTER offsets from
-- the screen centre (same coordinate model the mover already uses), so we snap
-- them to multiples of the grid size -> frame centres line up with grid lines.
-- ---------------------------------------------------------
function ns:EditSnapXY(x, y)
    local g = gridState()
    if not g.snap then return x, y end
    local s = g.size or 32
    if s <= 0 then return x, y end
    local function snap(v) return math.floor(v / s + 0.5) * s end
    return snap(x), snap(y)
end

-- ---------------------------------------------------------
-- Lazy-built chrome
-- ---------------------------------------------------------
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
    -- vertical line at screen x = px
    local function vline(px, center)
        local t = lineTex()
        if center then t:SetColorTexture(accent.r, accent.g, accent.b, 0.55)
        else           t:SetColorTexture(1, 1, 1, 0.07) end
        t:SetWidth(center and 2 or 1)
        t:SetPoint("TOP",    dim, "TOPLEFT",    px, 0)
        t:SetPoint("BOTTOM", dim, "BOTTOMLEFT", px, 0)
        t:Show()
    end
    -- horizontal line at screen y = py (measured from the bottom)
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

-- ---------------------------------------------------------
-- Build (once)
-- ---------------------------------------------------------
local function build()
    if built then return end
    built = true
    local accent = ns.COLORS.accent

    -- Dim overlay: below the movers (HIGH) so the purple boxes stay on top and
    -- clickable; mouse-enabled so stray clicks hit it instead of the world.
    dim = CreateFrame("Frame", "VCUIEditDim", UIParent)
    dim:SetAllPoints(UIParent)
    dim:SetFrameStrata("MEDIUM")
    dim:EnableMouse(true)
    -- click empty space to deselect the current frame
    dim:SetScript("OnMouseDown", function() if ns.DeselectMover then ns:DeselectMover() end end)
    local fill = dim:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(dim)
    fill:SetColorTexture(0, 0, 0, 0.35)
    dim:Hide()

    -- Toolbar: above the movers (DIALOG > HIGH) so its controls are clickable.
    toolbar = CreateFrame("Frame", "VCUIEditToolbar", UIParent)
    -- wide enough that the grid-size slider's value + / - steppers clear the
    -- right-hand Layouts / Reset buttons (left cluster anchors left, right cluster
    -- anchors right, so the extra width separates them)
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

    -- Accent strip + title
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

    -- Exit (primary accent)
    local exitBtn = UI:CreateButton(toolbar, {
        label   = L["Exit"],
        primary = true,
        width   = 96,
        tooltip = L["Close Edit Mode and lock all windows."],
        onClick = function() ns:SetEditMode(false) end,
    })
    exitBtn:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 14, ROWY)

    -- Grid toggle
    local gridTog = UI:CreateToggle(toolbar, {
        label   = L["Grid"],
        tooltip = L["Show an alignment grid."],
        get     = function() return gridState().show end,
        set     = function(_, v) gridState().show = v; refreshGrid() end,
    })
    gridTog:SetSize(108, 24)
    gridTog:SetPoint("LEFT", exitBtn, "RIGHT", 18, 0)

    -- Snap toggle
    local snapTog = UI:CreateToggle(toolbar, {
        label   = L["Snap"],
        tooltip = L["Snap windows to the grid while dragging."],
        get     = function() return gridState().snap end,
        set     = function(_, v) gridState().snap = v end,
    })
    snapTog:SetSize(140, 24)
    snapTog:SetPoint("LEFT", gridTog, "RIGHT", 14, 0)

    -- Grid-size caption + slider
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

    -- Reset positions (right-aligned)
    local resetBtn = UI:CreateButton(toolbar, {
        label   = L["Reset"],
        width   = 130,
        tooltip = L["Reset all VuloUI window positions to the screen centre."],
        onClick = function() StaticPopup_Show("VCUI_EDIT_RESET") end,
    })
    resetBtn:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", -16, ROWY)

    -- Layouts (save / load / export named arrangements) — opens its own panel
    local layoutsBtn = UI:CreateButton(toolbar, {
        label   = L["Layouts"],
        width   = 120,
        tooltip = L["Save, load, export and import named window layouts."],
        onClick = function() if ns.ToggleLayouts then ns:ToggleLayouts() end end,
    })
    layoutsBtn:SetPoint("RIGHT", resetBtn, "LEFT", -10, 0)
end

-- ---------------------------------------------------------
-- Public: enter / exit
-- ---------------------------------------------------------
function ns:IsEditModeActive()
    return ns._editActive and true or false
end

-- Hooks fired whenever Edit Mode toggles, so a module with its OWN positioner
-- (not a ns:CreateMover box) can follow the same on/off — e.g. Arena's overlay.
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
        -- Park/link Blizzard frame anchors before the boxes are shown.
        if ns.PrepareBlizzMovers then ns:PrepareBlizzMovers() end
        dim:Show()
        toolbar:Show()
        refreshGrid()
    else
        -- abort any in-flight drag cleanly so the grabbed frame isn't left stuck
        -- to the cursor (e.g. combat auto-exit fires mid-drag)
        local d = ns._draggingMover
        if d and d.target and d.target.StopMovingOrSizing then d.target:StopMovingOrSizing() end
        if ns.DeselectMover then ns:DeselectMover() end   -- also clears ns._groupDrag
        if ns.HideLayouts then ns:HideLayouts() end
        ns._draggingMover = nil
        if ns._hideGuides then ns._hideGuides() end
        dim:Hide()
        toolbar:Hide()
    end
    -- Drive the existing mover engine (shows/hides every registered box).
    ns:SetMoversEditMode(state)
    -- Style the freshly-shown boxes (selected vs unselected look).
    if state and ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
    -- let bespoke positioners (Arena) follow the same toggle
    for _, fn in ipairs(ns._editHooks) do pcall(fn, state) end
end

-- ---------------------------------------------------------
-- Reset confirmation
-- ---------------------------------------------------------
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

-- ---------------------------------------------------------
-- Combat safety: auto-exit on entering combat, restore afterwards.
-- ---------------------------------------------------------
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

-- Keep the grid correct across resolution / UI-scale changes.
local disp = CreateFrame("Frame")
disp:RegisterEvent("DISPLAY_SIZE_CHANGED")
disp:RegisterEvent("UI_SCALE_CHANGED")
disp:SetScript("OnEvent", function()
    if ns:IsEditModeActive() then refreshGrid() end
end)

-- ---------------------------------------------------------
-- Slash command
-- ---------------------------------------------------------
SLASH_VCUIEDIT1 = "/vedit"
SlashCmdList["VCUIEDIT"] = function()
    ns:SetEditMode(not ns:IsEditModeActive())
end

-- =========================================================
-- Phase 2: selection + floating per-frame panel, edge/centre magnetism with
-- alignment guides, and Alt-cycle through stacked frames.
-- =========================================================
local function snapVal(v, size)
    if not size or size <= 0 then return v end
    return math.floor(v / size + 0.5) * size
end

local function cleanLabel(s)
    s = tostring(s or "Frame")
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- ---------------------------------------------------------
-- Selection set (multi-select). ns._selection is the list of selected movers;
-- ns._selectedMover is the PRIMARY (the one the floating panel edits). A group
-- drag moves every selected box; the panel still edits only the primary.
-- ---------------------------------------------------------
ns._selection = ns._selection or {}

local function selIndex(m)
    for i, x in ipairs(ns._selection) do if x == m then return i end end
end
function ns:IsSelected(m) return selIndex(m) ~= nil end

-- ---------------------------------------------------------
-- Selection visuals: brighten selected boxes, dim the rest. The primary
-- (panel target) gets the strongest border so you can tell which one X/Y edits.
-- ---------------------------------------------------------
function ns:RefreshMoverStyles()
    for _, m in ipairs(ns._movers) do
        local sel     = ns:IsSelected(m)
        local primary = (m == ns._selectedMover)
        if m.bg then
            m.bg:SetColorTexture(accent.r, accent.g, accent.b, sel and 0.5 or 0.18)
        end
        if m.border and m.border.SetBackdropBorderColor then
            if primary then
                m.border:SetBackdropBorderColor(accent.r, accent.g, accent.b, 1)
            elseif sel then
                m.border:SetBackdropBorderColor(accent.r, accent.g, accent.b, 0.85)
            else
                m.border:SetBackdropBorderColor(accent.r * 0.7, accent.g * 0.7, accent.b * 0.7, 0.8)
            end
        end
    end
end

-- ---------------------------------------------------------
-- Floating per-frame settings panel (EUI styled, built from our widgets).
-- ---------------------------------------------------------
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

-- Live CENTER offset of the selected mover's target. Reading the target every
-- frame (rather than the stored db, which only updates on drop) is what lets the
-- panel's X / Y track a drag or an arrow-key nudge in real time.
local function moverXY(m)
    local t = m and m.target
    if t and t.GetCenter then
        local fx, fy = t:GetCenter()
        local px, py = UIParent:GetCenter()
        if fx and fy and px and py then return fx - px, fy - py end
    end
    if m and m.opts and m.opts.db then return m.opts.db.x or 0, m.opts.db.y or 0 end
    return 0, 0
end

local function refreshPanel()
    if not panel or not panel:IsShown() then return end
    local m = ns._selectedMover
    if not m or not m.opts then return end
    local name = cleanLabel(m.opts.label)
    local n = #ns._selection
    if n > 1 then name = name .. string.format("  |cff9b6cff+%d|r", n - 1) end
    panel.title:SetText(name)
    local x, y = moverXY(m)
    -- don't stomp on the field the user is currently typing in
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
    panel:SetSize(264, 184)
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

    -- title (frame name) — bigger, with room before the close button
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(panel.title, 14)
    panel.title:SetPoint("TOPLEFT",  panel, "TOPLEFT",  16, -13)
    panel.title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -32, -13)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)
    panel.title:SetTextColor(accent.r, accent.g, accent.b)

    -- lightweight close (×) — deselects
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

    -- separator under the title
    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  14, -38)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -38)
    sep:SetHeight(1)
    sep:SetColorTexture(1, 1, 1, 0.07)

    -- "POSITION" caption
    local cap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(cap, 10)
    cap:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -46)
    cap:SetText(L["POSITION"])
    cap:SetTextColor(0.55, 0.55, 0.62)

    -- X / Y side by side, each a wide value box so big numbers stay readable
    panel.xBox = UI:CreateEditBox(panel, {
        label = "X", numeric = true, commitOnFocusLost = true, width = 110, editWidth = 86,
        get = function() local x = moverXY(ns._selectedMover); return math.floor(x + 0.5) end,
        set = function(_, v)
            local m = ns._selectedMover
            if m and v then ns:MoverSetCenter(m, v, m.opts.db.y or 0); refreshPanel() end
        end,
    })
    panel.xBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -62)

    panel.yBox = UI:CreateEditBox(panel, {
        label = "Y", numeric = true, commitOnFocusLost = true, width = 110, editWidth = 86,
        get = function() local _, y = moverXY(ns._selectedMover); return math.floor(y + 0.5) end,
        set = function(_, v)
            local m = ns._selectedMover
            if m and v then ns:MoverSetCenter(m, m.opts.db.x or 0, v); refreshPanel() end
        end,
    })
    panel.yBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -62)

    -- SCALE row (shown only for movers that opt in; positioned by layoutPanel)
    panel.scaleCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.scaleCap, 10)
    panel.scaleCap:SetText(L["SCALE"])
    panel.scaleCap:SetTextColor(0.55, 0.55, 0.62)
    panel.scaleSlider = UI:CreateSlider(panel, {
        label = "", min = 0.5, max = 2.0, step = 0.05, width = 80,
        get = function() local m = ns._selectedMover; return (m and m.opts.db.scale) or 1 end,
        set = function(_, v) local m = ns._selectedMover; if m then ns:MoverSetScale(m, v) end end,
    })

    -- ANCHOR-point row (shown only for movers that opt in)
    panel.anchorCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.anchorCap, 10)
    panel.anchorCap:SetText(L["ANCHOR"])
    panel.anchorCap:SetTextColor(0.55, 0.55, 0.62)
    panel.anchorDrop = UI:CreateDropdown(panel, {
        label = "", width = 150, values = ANCHOR_POINTS,
        tooltip = L["Which screen point the frame is pinned to (keeps it put across resolution changes)."],
        get = function() local m = ns._selectedMover; return (m and m.opts.db.anchor) or "CENTER" end,
        set = function(_, v) local m = ns._selectedMover; if m then ns:MoverSetAnchor(m, v) end end,
    })

    panel.reset = UI:CreateButton(panel, {
        label   = L["Reset this frame"],
        width   = 228,
        onClick = function()
            local m = ns._selectedMover
            if m then ns:MoverSetCenter(m, 0, 0); refreshPanel() end
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

    -- Live values: keep X / Y in step with a drag or an arrow-key nudge.
    panel._acc = 0
    panel:SetScript("OnUpdate", function(self, elapsed)
        self._acc = self._acc + elapsed
        if self._acc < 0.05 then return end
        self._acc = 0
        refreshPanel()
    end)
end

-- Show / position the optional Scale + Anchor rows for the selected mover and
-- size the panel to fit (capabilities are per-mover, declared in ns:CreateMover).
local function layoutPanel(m)
    if not panel then return end
    local scalable   = m and m.opts and m.opts.scalable
    local anchorable = m and m.opts and m.opts.anchorable
    local y = -94

    if scalable then
        panel.scaleCap:Show(); panel.scaleSlider:Show()
        panel.scaleCap:ClearAllPoints()
        panel.scaleCap:SetPoint("LEFT", panel, "TOPLEFT", 18, y)
        panel.scaleSlider:ClearAllPoints()
        panel.scaleSlider:SetPoint("LEFT", panel.scaleCap, "RIGHT", 14, 0)
        y = y - 30
    else
        panel.scaleCap:Hide(); panel.scaleSlider:Hide()
    end

    if anchorable then
        panel.anchorCap:Show(); panel.anchorDrop:Show()
        panel.anchorCap:ClearAllPoints()
        panel.anchorCap:SetPoint("LEFT", panel, "TOPLEFT", 18, y - 13)
        panel.anchorDrop:ClearAllPoints()
        panel.anchorDrop:SetPoint("LEFT", panel.anchorCap, "RIGHT", 12, 0)
        y = y - 34
    else
        panel.anchorCap:Hide(); panel.anchorDrop:Hide()
    end

    panel.reset:ClearAllPoints()
    panel.reset:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y - 6)
    panel:SetHeight(-(y - 6) + 78)
end

-- Reflect the selected mover's current scale / anchor in the panel controls.
local function refreshCaps(m)
    if m and m.opts and m.opts.scalable and panel.scaleSlider._vcSetup then
        panel.scaleSlider._vcSetup(panel.scaleSlider, panel.scaleSlider._vcConfig)
    end
    if m and m.opts and m.opts.anchorable and panel.anchorDrop._button then
        panel.anchorDrop._button._refresh()
    end
end

-- additive (Shift+click): toggle this mover in/out of the selection set.
-- non-additive (plain click): select just this one — UNLESS it is already part
-- of a multi-selection, in which case keep the group (so a plain click/grab on a
-- group member can drag the whole group) and only move the primary to it.
function ns:SelectMover(mover, additive)
    if not mover then return end

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
        ns._selectedMover = mover            -- keep the group, just retarget the panel
    else
        wipe(ns._selection)
        ns._selection[1]  = mover
        ns._selectedMover = mover
    end

    if not ns._selectedMover then            -- toggled the last box off
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

-- ---------------------------------------------------------
-- Group drag: when the dragged ("leader") box is part of a multi-selection,
-- every other selected box follows it by the same delta. Only the leader snaps
-- (magnetism); followers keep their relative offset so the group stays rigid.
-- ---------------------------------------------------------
function ns:BeginGroupDrag(leader)
    ns._groupDrag = nil
    if #ns._selection <= 1 or not (leader and ns:IsSelected(leader) and leader.target) then return end
    local px, py = UIParent:GetCenter()
    if not px then return end
    local followers = {}
    for _, m in ipairs(ns._selection) do
        if m ~= leader and m.target and m.target.GetCenter then
            local fx, fy = m.target:GetCenter()
            if fx and fy then
                followers[#followers + 1] = { mover = m, x = fx - px, y = fy - py }
            end
        end
    end
    if #followers == 0 then return end
    local lfx, lfy = leader.target:GetCenter()
    if not lfx then return end
    ns._groupDrag = { lx = lfx - px, ly = lfy - py, followers = followers }
end

-- Called each frame while dragging (from liveGuideDriver): translate followers
-- by the leader's live movement so they track the cursor with it.
function ns:UpdateGroupDrag()
    local gd = ns._groupDrag
    local leader = ns._draggingMover
    if not (gd and leader and leader.target) then return end
    local px, py = UIParent:GetCenter()
    local lfx, lfy = leader.target:GetCenter()
    if not (px and lfx) then return end
    -- leader's movement, measured in its own coordinate space
    local dx, dy = (lfx - px) - gd.lx, (lfy - py) - gd.ly
    local lscale = leader.target:GetEffectiveScale() or 1
    for _, f in ipairs(gd.followers) do
        local t = f.mover.target
        -- convert the delta into THIS follower's space so a scaled frame tracks
        -- the leader 1:1 on screen (conv == 1 when both are at the same scale)
        local conv = lscale / (t:GetEffectiveScale() or 1)
        t:ClearAllPoints()
        t:SetPoint("CENTER", UIParent, "CENTER", f.x + dx * conv, f.y + dy * conv)
    end
end

-- Called on drop. sdx/sdy = the snap correction the leader took, applied on top
-- of each follower's live position so the whole group keeps its arrangement;
-- then each follower is committed through its own model (scale/anchor/custom).
function ns:EndGroupDrag(sdx, sdy)
    local gd = ns._groupDrag
    ns._groupDrag = nil
    if not gd then return end
    sdx, sdy = sdx or 0, sdy or 0
    local px, py = UIParent:GetCenter()
    if not px then return end
    for _, f in ipairs(gd.followers) do
        local t = f.mover.target
        local fx, fy = t:GetCenter()
        if fx and fy then
            ns:MoverSetCenter(f.mover, (fx - px) + sdx, (fy - py) + sdy)
        end
    end
end

-- Arrow-key nudge: move the rest of the selection by the same step as the leader.
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

-- ---------------------------------------------------------
-- Alignment guides (flashed when a magnet snap engages on drop).
-- ---------------------------------------------------------
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

-- Find the nearest snap lines for `mover` at CENTER offset (x,y): every other
-- mover's edges/centre + the screen centre cross. Returns dx,lineX,dy,lineY --
-- the per-axis snap delta and the line it snaps to (or nil if nothing in range).
local function computeSnap(mover, x, y)
    local target = mover.target
    local px, py = UIParent:GetCenter()
    if not (px and target) then return end
    local hw = (target:GetWidth()  or 0) / 2
    local hh = (target:GetHeight() or 0) / 2

    local xLines, yLines = { 0 }, { 0 }   -- 0 == screen centre line
    for _, o in ipairs(ns._movers) do
        if o ~= mover and o.target and o:IsShown() then
            local ofx, ofy = o.target:GetCenter()
            if ofx and ofy then
                local ocx, ocy = ofx - px, ofy - py
                local ohw = (o.target:GetWidth()  or 0) / 2
                local ohh = (o.target:GetHeight() or 0) / 2
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

    local dx, lineX = best({ x - hw, x, x + hw }, xLines)
    local dy, lineY = best({ y - hh, y, y + hh }, yLines)
    return dx, lineX, dy, lineY
end

-- ---------------------------------------------------------
-- Magnetism on DROP: snap the dropped frame to the nearest lines (grid-snap is
-- the per-axis fallback) and flash the guides.
-- ---------------------------------------------------------
function ns:EditResolveDrop(mover, x, y)
    local g = gridState()
    local dx, lineX, dy, lineY = computeSnap(mover, x, y)
    if dx then x = x + dx elseif g.snap then x = snapVal(x, g.size) end
    if dy then y = y + dy elseif g.snap then y = snapVal(y, g.size) end
    drawGuides(dx and lineX or nil, dy and lineY or nil)   -- flash on drop
    return x, y
end

-- ---------------------------------------------------------
-- LIVE guides: while a box is being dragged, show the alignment lines it is
-- about to snap to. Purely visual -- the actual snap still happens on drop.
-- ---------------------------------------------------------
local liveGuideDriver = CreateFrame("Frame")
liveGuideDriver:SetScript("OnUpdate", function()
    local m = ns._draggingMover
    if not (m and m.target and ns:IsEditModeActive()) then return end
    if ns._groupDrag then ns:UpdateGroupDrag() end   -- drag the rest of the group along
    local px, py = UIParent:GetCenter()
    local fx, fy = m.target:GetCenter()
    if not (px and fx) then return end
    local dx, lineX, dy, lineY = computeSnap(m, fx - px, fy - py)
    drawGuides(dx and lineX or nil, dy and lineY or nil, true)   -- persistent while dragging
end)

-- ---------------------------------------------------------
-- Alt-cycle: when several boxes overlap under the cursor, show a hint and let
-- Alt raise the buried one so it can be grabbed.
-- ---------------------------------------------------------
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

-- =========================================================
-- Named layouts: save / load / delete the current arrangement + a copy-paste
-- export / import string. Stored account-wide in ns.db.global.editLayouts so
-- they're shared across profiles and characters. The capture / apply / (de)
-- serialize logic lives in Core/Mover.lua.
-- =========================================================
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

-- Rebuild the dropdown list from the store and keep / repair the selection.
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
    -- de-dupe without parentheses (the dropdown strips "(...)" from display)
    local store = layoutStore()
    local base, i, final = name, 2, name
    while store[final] do final = base .. " " .. i; i = i + 1 end
    store[final] = snap
    rebuildLayoutList(final)
    ns:Print(string.format(L["Layout '%s' imported."], final))
end

-- ---------------------------------------------------------
-- Popups (name input, import paste, export copy, delete confirm)
-- ---------------------------------------------------------
local function popupBox(self)
    return self.editBox or (self.GetName and _G[(self:GetName() or "") .. "EditBox"])
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

-- ---------------------------------------------------------
-- The Layouts panel (EUI styled, mirrors the per-frame panel chrome)
-- ---------------------------------------------------------
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
