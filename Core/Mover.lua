-- =========================================================
-- VuloClassicUI / Core / Mover
-- Generic mover helper. Creates a purple drag overlay
-- with arrow-key fine adjustment (1px / SHIFT = 5px).
--
-- Usage:
--   local mover = ns:CreateMover(target, {
--       label  = "|cffffffffMY FRAME|r",
--       db     = mod.db,              -- needs x, y, unlocked
--       width  = 200, height = 40,    -- mover size (optional)
--       onMove = function(x, y) end,  -- callback after drag/key (optional)
--   })
--   mover:Show()  -- shows the mover (target is moved via StartMoving)
-- =========================================================
local _, ns = ...

function ns:CreateMover(target, opts)
    opts = opts or {}
    local db = opts.db
    assert(db, "ns:CreateMover needs opts.db")
    assert(target, "ns:CreateMover needs target")

    target:SetMovable(true)
    target:SetClampedToScreen(false)

    local mover = CreateFrame("Frame", nil, target)
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
        mover.label:SetPoint("CENTER", mover, "CENTER", 0, 0)
        mover.label:SetJustifyH("CENTER")
        mover.label:SetText(opts.label)
    end

    -- Drag — moves target, writes x/y into db (relative to UIParent center)
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

    -- Keyboard — arrow keys 1px, SHIFT 5px
    mover:EnableKeyboard(true)
    mover:SetPropagateKeyboardInput(true)
    mover:SetScript("OnKeyDown", function(self, key)
        if not db.unlocked then
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
        target:ClearAllPoints()
        target:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        if opts.onMove then opts.onMove(db.x, db.y) end
    end)

    return mover
end
