-- =========================================================
-- VuloClassicUI / Modules / ArenaFrames
-- Formerly: ArenaEnemyEdit
-- Moves + scales the Blizzard ArenaEnemyFrames, plus font sizing.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("arenaframes", {
    name        = "Arena Frames",
    description = "Moves/scales the ArenaEnemyFrames and changes the font size of the bars.",
    defaults = {
        pos        = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
        scale      = 1.0,
        healthSize = 10,
        powerSize  = 10,
    },
})

local mover
local unlocked      = false
local pendingApply  = false
local isDragging    = false
local hookedManage  = false

-- =========================================================
-- Helpers
-- =========================================================
local function forceLoadArenaUI()
    if UIParentLoadAddOn and IsAddOnLoaded and not IsAddOnLoaded("Blizzard_ArenaUI") then
        UIParentLoadAddOn("Blizzard_ArenaUI")
    end
end

local function getOwner() return _G["ArenaEnemyFrames"] end

local function getArenaBars(frame)
    local health = frame.healthbar or frame.HealthBar or _G[frame:GetName() .. "HealthBar"]
    local power  = frame.manabar  or frame.ManaBar  or frame.powerbar or frame.PowerBar
                 or _G[frame:GetName() .. "ManaBar"] or _G[frame:GetName() .. "PowerBar"]
    return health, power
end

local function forEachArenaFrame(fn)
    for i = 1, 5 do
        local f = _G["ArenaEnemyFrame" .. i]
        if f then fn(f, i) end
    end
end

local function applyArenaFonts()
    local hSize = mod.db.healthSize
    local pSize = mod.db.powerSize
    forEachArenaFrame(function(frame)
        local health, power = getArenaBars(frame)
        if health then
            ns:SetBarTextFontSize(health, hSize)
            if TextStatusBar_UpdateTextString then TextStatusBar_UpdateTextString(health) end
        end
        if power then
            ns:SetBarTextFontSize(power, pSize)
            if TextStatusBar_UpdateTextString then TextStatusBar_UpdateTextString(power) end
        end
    end)
end

local function unmanageOwner()
    if UIPARENT_MANAGED_FRAME_POSITIONS and UIPARENT_MANAGED_FRAME_POSITIONS["ArenaEnemyFrames"] then
        UIPARENT_MANAGED_FRAME_POSITIONS["ArenaEnemyFrames"] = nil
    end
end

local function applyToOwner()
    local owner = getOwner()
    if not owner then return end
    if ns:InCombat() then pendingApply = true; return end

    local p = mod.db.pos
    unmanageOwner()
    owner:ClearAllPoints()
    owner:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    owner:SetScale(mod.db.scale or 1.0)
    applyArenaFonts()
end

mod.applyToOwner = applyToOwner

local function savePosFromMover()
    if not mover then return end
    local point, _, relPoint, x, y = mover:GetPoint(1)
    mod.db.pos.point    = point or "CENTER"
    mod.db.pos.relPoint = relPoint or "CENTER"
    mod.db.pos.x        = x or 0
    mod.db.pos.y        = y or 0
end

local function applyMoverPos()
    if not mover then return end
    local p = mod.db.pos
    mover:ClearAllPoints()
    mover:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
end

local function createMover()
    if mover then return end
    mover = CreateFrame("Button", "VCUIArenaFramesMover", UIParent, "BackdropTemplate")
    mover:SetFrameStrata("HIGH")
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetClampedToScreen(true)
    mover:EnableMouseWheel(true)
    mover:SetSize(300, 44)
    mover:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    mover:SetBackdropColor(0, 0.6, 1, 0.22)

    mover.text = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mover.text:SetPoint("CENTER")
    mover.text:SetText("ArenaEnemyFrames: drag | Scale: 1.00 (mouse wheel)")

    mover:SetScript("OnDragStart", function(self)
        if ns:InCombat() then ns:Print("Not possible in combat."); return end
        isDragging = true
        self:StartMoving()
    end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        isDragging = false
        if ns:InCombat() then return end
        savePosFromMover()
        applyToOwner()
    end)
    mover:SetScript("OnMouseWheel", function(_, delta)
        if ns:InCombat() then ns:Print("Not possible in combat."); return end
        local s = ns:Clamp((mod.db.scale or 1.0) + (delta > 0 and 0.05 or -0.05), 0.5, 2.0)
        mod.db.scale = s
        mover.text:SetText(string.format("ArenaEnemyFrames: drag | Scale: %.2f (mouse wheel)", s))
        applyToOwner()
    end)
    mover:Hide()
end

local function hookManageFramePositions()
    if hookedManage or not hooksecurefunc then return end
    if not _G["UIParent_ManageFramePositions"] then return end
    hookedManage = true
    hooksecurefunc("UIParent_ManageFramePositions", function()
        if not mod._enabled then return end
        if unlocked and not ns:InCombat() and not isDragging then
            applyToOwner()
        elseif not ns:InCombat() then
            applyToOwner()
        end
    end)
end

local function tryApply()
    forceLoadArenaUI()
    createMover()
    hookManageFramePositions()
    unmanageOwner()
    applyMoverPos()
    applyToOwner()

    if C_Timer and C_Timer.After then
        C_Timer.After(0, applyArenaFonts)
        C_Timer.After(1, applyArenaFonts)
    end
end

local function setUnlocked(state)
    unlocked = state
    tryApply()
    if state then
        if ns:InCombat() then ns:Print("Not possible in combat."); unlocked = false; return end
        mover:Show()
        mover.text:SetText(string.format("ArenaEnemyFrames: drag | Scale: %.2f (mouse wheel)", mod.db.scale or 1.0))
        ns:Print("Arena Frames unlocked: drag + mouse wheel to scale.")
    else
        if mover and not ns:InCombat() then
            savePosFromMover()
            applyToOwner()
        end
        if mover then mover:Hide() end
        ns:Print("Arena Frames locked.")
    end
end

mod.setUnlocked = setUnlocked

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    ns:RegisterEvent("PLAYER_LOGIN",          function() tryApply() end)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() tryApply() end)
    ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() tryApply() end)
    ns:RegisterEvent("ADDON_LOADED",          function(_, name)
        if name == "Blizzard_ArenaUI" then tryApply() end
    end)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",  function()
        if pendingApply then pendingApply = false; tryApply() end
    end)

    tryApply()
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = "Position & Size" },
        {
            type = "button", label = "Unlock (move/scale)",
            tooltip = "Shows a mover. Drag to move, mouse wheel to scale.",
            onClick = function() setUnlocked(not unlocked) end,
        },
        {
            type = "slider", label = "Scale",
            min = 0.5, max = 2.0, step = 0.05,
            get = function() return mod.db.scale end,
            set = function(_, v) mod.db.scale = v; applyToOwner() end,
        },
        { type = "spacer" },
        { type = "header", text = "Font Sizes" },
        {
            type = "slider", label = "Health Bar Text",
            min = 6, max = 20, step = 1,
            get = function() return mod.db.healthSize end,
            set = function(_, v) mod.db.healthSize = v; applyArenaFonts() end,
        },
        {
            type = "slider", label = "Power Bar Text",
            min = 6, max = 20, step = 1,
            get = function() return mod.db.powerSize end,
            set = function(_, v) mod.db.powerSize = v; applyArenaFonts() end,
        },
        { type = "spacer" },
        {
            type = "button", label = "Reset Position",
            onClick = function()
                mod.db.pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
                applyMoverPos()
                applyToOwner()
                ns:Print("Arena Frames position reset.")
            end,
        },
    }
end
