-- =========================================================
-- VuloClassicUI / Core / Mover
-- Generic mover helper + a global EDIT MODE that shows every registered mover
-- at once (and mirrors Blizzard's Edit Mode where the client has one, e.g.
-- the Anniversary client).
--
--   - drag a purple box to move its frame
--   - arrow keys fine-tune (1px / SHIFT = 5px) while editing
--   - RIGHT-CLICK a box -> a small settings popup (X / Y / reset)
--
-- Usage:
--   local mover = ns:CreateMover(target, {
--       label  = "|cffffffffMY FRAME|r",
--       db     = mod.db,                 -- needs x, y (and optionally unlocked)
--       width  = 200, height = 40,
--       onMove   = function(x, y) end,   -- after a drag/key (optional)
--       applyPos = function() end,       -- custom reposition (optional; else CENTER)
--       editPreview = function(show) end,-- show/hide a preview while editing (optional)
--   })
-- =========================================================
local _, ns = ...

ns._movers    = ns._movers or {}      -- every mover created via ns:CreateMover
ns._moverEdit = ns._moverEdit or false

-- ---------------------------------------------------------
-- Positioning. Modules with their own anchoring pass opts.applyPos; everything
-- else stores a CENTER offset from the screen centre.
-- ---------------------------------------------------------
local function applyPos(mover)
    local opts = mover.opts
    if opts.applyPos then opts.applyPos(); return end
    local target, db = mover.target, opts.db
    target:ClearAllPoints()
    target:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 0)
    if opts.onMove then opts.onMove(db.x or 0, db.y or 0) end
end

-- ---------------------------------------------------------
-- Shared settings popup (re-pointed to the right-clicked mover)
-- ---------------------------------------------------------
local popup
local function cleanLabel(s)
    s = tostring(s or "Mover")
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function ensurePopup()
    if popup then return popup end
    popup = CreateFrame("Frame", "VCUIMoverPopup", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")
    popup:SetSize(210, 124)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:EnableMouse(true)
    if popup.SetBackdrop then
        popup:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        })
        popup:SetBackdropColor(0.06, 0.05, 0.10, 0.97)
        local c = (ns.COLORS and ns.COLORS.accent) or { r = 0.5, g = 0.3, b = 0.9 }
        popup:SetBackdropBorderColor(c.r, c.g, c.b, 1)
    end

    popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popup.title:SetPoint("TOP", popup, "TOP", 0, -8)

    local close = CreateFrame("Button", nil, popup)
    close:SetSize(20, 20); close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, -2)
    local ct = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ct:SetPoint("CENTER", close, "CENTER", 0, 0); ct:SetText("x")
    close:SetScript("OnClick", function() popup:Hide() end)

    local function mkField(labelText, yOff)
        local lbl = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", popup, "TOPLEFT", 16, yOff)
        lbl:SetText(labelText)
        local bg = CreateFrame("Frame", nil, popup, BackdropTemplateMixin and "BackdropTemplate")
        bg:SetSize(96, 22); bg:SetPoint("RIGHT", popup, "TOPRIGHT", -16, yOff)
        if bg.SetBackdrop then
            bg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            bg:SetBackdropColor(0.10, 0.09, 0.14, 1)
            bg:SetBackdropBorderColor(0.30, 0.30, 0.36, 1)
        end
        local eb = CreateFrame("EditBox", nil, bg)
        eb:SetPoint("LEFT", bg, "LEFT", 6, 0)
        eb:SetPoint("RIGHT", bg, "RIGHT", -6, 0)
        eb:SetHeight(20)
        eb:SetAutoFocus(false)
        eb:SetFontObject("GameFontHighlightSmall")
        eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        return eb
    end
    popup.xEdit = mkField("X", -36)
    popup.yEdit = mkField("Y", -62)

    popup.reset = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    popup.reset:SetSize(92, 22)
    popup.reset:SetPoint("BOTTOM", popup, "BOTTOM", 0, 12)
    popup.reset:SetText((ns.L and ns.L["Reset position"]) or "Reset")

    popup:Hide()
    return popup
end

local function commitField(mover, edit, axis)
    local v = tonumber(edit:GetText())
    if not v then return end
    mover.opts.db[axis] = v
    applyPos(mover)
end

local function showMoverPopup(mover)
    local p = ensurePopup()
    local db = mover.opts.db
    p.title:SetText(cleanLabel(mover.opts.label))
    p.xEdit:SetText(tostring(math.floor((db.x or 0) + 0.5)))
    p.yEdit:SetText(tostring(math.floor((db.y or 0) + 0.5)))
    p.xEdit:SetScript("OnEnterPressed", function(s) commitField(mover, s, "x"); s:ClearFocus() end)
    p.yEdit:SetScript("OnEnterPressed", function(s) commitField(mover, s, "y"); s:ClearFocus() end)
    p.reset:SetScript("OnClick", function()
        db.x, db.y = 0, 0; applyPos(mover)
        p.xEdit:SetText("0"); p.yEdit:SetText("0")
    end)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", mover, "BOTTOMLEFT", 0, -4)
    p:Show()
end

-- ---------------------------------------------------------
-- Mover factory
-- ---------------------------------------------------------
function ns:CreateMover(target, opts)
    opts = opts or {}
    local db = opts.db
    assert(db, "ns:CreateMover needs opts.db")
    assert(target, "ns:CreateMover needs target")

    target:SetMovable(true)
    target:SetClampedToScreen(false)

    local mover = CreateFrame("Frame", nil, target)
    mover.target = target
    mover.opts   = opts
    mover:SetPoint("CENTER", target, "CENTER", 0, 0)
    mover:SetSize(opts.width or 200, opts.height or 40)
    mover:SetFrameStrata("HIGH")
    mover:EnableMouse(true)
    mover:Hide()

    mover.bg = mover:CreateTexture(nil, "BACKGROUND")
    mover.bg:SetAllPoints(mover)
    mover.bg:SetColorTexture(0.6, 0.4, 1.0, 0.4)

    mover.border = CreateFrame("Frame", nil, mover,
        BackdropTemplateMixin and "BackdropTemplate")
    mover.border:SetAllPoints(mover)
    if mover.border.SetBackdrop then
        mover.border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })
        mover.border:SetBackdropBorderColor(0.75, 0.35, 1, 1)
    end

    if opts.label then
        mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        mover.label:SetPoint("CENTER", mover, "CENTER", 0, 6)
        mover.label:SetJustifyH("CENTER")
        mover.label:SetText(opts.label)
        mover.hint = mover:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        mover.hint:SetPoint("CENTER", mover, "CENTER", 0, -9)
        mover.hint:SetText((ns.L and ns.L["right-click: settings"]) or "right-click: settings")
    end

    -- Drag — moves target, writes x/y (a CENTER offset) into db
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function() target:StartMoving() end)
    mover:SetScript("OnDragStop", function()
        target:StopMovingOrSizing()
        local fx, fy = target:GetCenter()
        local px, py = UIParent:GetCenter()
        if fx and fy and px and py then
            local x, y = fx - px, fy - py
            target:ClearAllPoints()
            target:SetPoint("CENTER", UIParent, "CENTER", x, y)
            db.x, db.y = x, y
            if opts.onMove then opts.onMove(x, y) end
        end
    end)

    -- Right-click — open the settings popup for this mover
    mover:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then showMoverPopup(self) end
    end)

    -- Hovering a box makes it the ACTIVE one — arrow keys then nudge only it
    -- (several movers are visible at once in edit mode, so we must single one out).
    mover:SetScript("OnEnter", function(self) ns._activeMover = self end)

    -- Keyboard — arrow keys 1px, SHIFT 5px (while editing OR individually unlocked)
    mover:EnableKeyboard(true)
    mover:SetPropagateKeyboardInput(true)
    mover:SetScript("OnKeyDown", function(self, key)
        -- only the last-hovered ("active") box reacts, so arrow keys nudge one
        if not (ns._moverEdit or db.unlocked) or ns._activeMover ~= self then
            self:SetPropagateKeyboardInput(true)
            return
        end
        local step = IsShiftKeyDown() and 5 or 1
        local dx, dy = 0, 0
        if     key == "UP"    then dy =  step
        elseif key == "DOWN"  then dy = -step
        elseif key == "LEFT"  then dx = -step
        elseif key == "RIGHT" then dx =  step
        else
            self:SetPropagateKeyboardInput(true)
            return
        end
        self:SetPropagateKeyboardInput(false)
        db.x = (db.x or 0) + dx
        db.y = (db.y or 0) + dy
        applyPos(self)
        if popup and popup:IsShown() and popup._mover == self then
            popup.xEdit:SetText(tostring(math.floor((db.x or 0) + 0.5)))
            popup.yEdit:SetText(tostring(math.floor((db.y or 0) + 0.5)))
        end
    end)
    -- so the popup can update its fields while THIS mover is being nudged
    mover:HookScript("OnMouseDown", function(self) if popup then popup._mover = self end end)

    ns._movers[#ns._movers + 1] = mover
    return mover
end

-- ---------------------------------------------------------
-- Global edit mode: show / hide EVERY registered mover at once
-- ---------------------------------------------------------
function ns:SetMoversEditMode(state)
    state = state and true or false
    if ns._moverEdit == state then return end
    ns._moverEdit = state
    for _, mover in ipairs(ns._movers) do
        local opts = mover.opts
        if opts.editPreview then pcall(opts.editPreview, state) end
        if state then
            mover:Show()
        elseif not (opts.db and opts.db.unlocked) then
            mover:Hide()
        end
    end
    if not state and popup then popup:Hide() end
end

function ns:IsMoverEditMode() return ns._moverEdit end

-- Hook Blizzard's Edit Mode (Anniversary) so it toggles ours too.
function ns:HookBlizzardEditMode()
    local emf = _G.EditModeManagerFrame
    if not emf or emf._vcMoverHooked then return emf ~= nil end
    emf._vcMoverHooked = true
    emf:HookScript("OnShow", function() ns:SetMoversEditMode(true)  end)
    emf:HookScript("OnHide", function() ns:SetMoversEditMode(false) end)
    return true
end

-- Try the hook now and again when Blizzard_EditMode loads on demand.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, evt, name)
    if evt == "ADDON_LOADED" and name ~= "Blizzard_EditMode" then return end
    ns:HookBlizzardEditMode()
end)
