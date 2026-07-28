-- VuloClassicUI / Trinkets / Frames: Trinkets.xml, in Lua.
--
-- A line-for-line translation of the 378-line XML, not a redesign. Every global
-- name it produced is produced here with the same spelling, because the vendored
-- Lua reads them as globals: Trinkets_Trinket0Time, Trinkets_Menu17Time,
-- Trinkets_Trinket1Queue, Trinkets_MainDock_TOPLEFT and so on. A single renamed
-- frame is a silent nil somewhere in 1300 lines.
--
-- THREE THINGS THE XML DID THAT LUA DOES NOT DO BY ITSELF
--
-- 1. OnLoad. XML runs a frame's OnLoad the moment it is built; CreateFrame never
--    does. Each one is therefore CALLED here, at the point the XML would have
--    reached it -- children first, then the parent, which is the order XML uses.
--
-- 2. Script inheritance. A frame that inherits a template AND declares its own
--    OnLoad REPLACES the template's. That is not a guess: both frames using
--    TrinketsBackdropTemplate call self:OnBackdropLoaded() by hand in their own
--    OnLoad, which is exactly what you write when you know it was overridden.
--    So the template body runs only where the XML let it run.
--
-- 3. hidden="true" creates a frame hidden WITHOUT firing OnHide. CreateFrame
--    makes it shown, so Hide() has to come BEFORE the OnHide script is attached,
--    or every one of these would fire a spurious OnHide at load.
--
-- Templates become factory functions. They have to: CreateFrame's template
-- argument only accepts templates the XML system knows about, so a virtual
-- frame defined in Lua cannot be inherited by name. The two Blizzard templates
-- in use here -- ActionButtonTemplate, SecureActionButtonTemplate -- are still
-- XML and are still passed as strings.
local _, ns = ...

local BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"

-- ---------------------------------------------------------------------------
-- <Frame name="TrinketsBackdropTemplate" mixin="TrinketsBackdropTemplateMixin">
-- ---------------------------------------------------------------------------
local function applyBackdropTemplate(f)
    Mixin(f, TrinketsBackdropTemplateMixin)
    f:SetScript("OnSizeChanged", f.OnBackdropSizeChanged)
    -- The template's OnLoad is deliberately NOT run: see note 2 above.
end

-- ---------------------------------------------------------------------------
-- <Frame name="TrinketsTimeTemplate"> -- 36x12 at BOTTOMRIGHT, $parentTime
-- ---------------------------------------------------------------------------
local function makeTimeFrame(parent, fsName)
    local f = CreateFrame("Frame", nil, parent)
    f:EnableMouse(false)
    f:SetSize(36, 12)
    f:SetPoint("BOTTOMRIGHT")
    local fs = f:CreateFontString(fsName, "OVERLAY", "NumberFontNormal")
    fs:SetJustifyH("CENTER")
    -- The XML gives this FontString no anchors, which fills its parent. Stated
    -- rather than implied, since the whole 36x12 box is the cooldown readout.
    fs:SetAllPoints(f)
    return f, fs
end

-- ---------------------------------------------------------------------------
-- <Frame name="TrinketsQueueTemplate"> -- 18x18 at TOPLEFT -2,2, $parentQueue
-- ---------------------------------------------------------------------------
local function makeQueueFrame(parent, texName)
    local f = CreateFrame("Frame", nil, parent)
    f:EnableMouse(false)
    f:SetSize(18, 18)
    f:SetPoint("TOPLEFT", -2, 2)
    local tex = f:CreateTexture(texName, "OVERLAY")
    tex:SetAllPoints(f)
    return f, tex
end

-- ---------------------------------------------------------------------------
-- The four corner textures both frames carry, identical apart from the corner
-- and the slice of the border file each one shows.
-- ---------------------------------------------------------------------------
local DOCKS = {
    { point = "TOPRIGHT",    left = 0.625, right = 0.75  },
    { point = "TOPLEFT",     left = 0.5,   right = 0.625 },
    { point = "BOTTOMLEFT",  left = 0.75,  right = 0.875 },
    { point = "BOTTOMRIGHT", left = 0.875, right = 1     },
}

local function makeDocks(parent, prefix)
    for _, d in ipairs(DOCKS) do
        local t = parent:CreateTexture(prefix .. d.point, "OVERLAY")
        t:SetTexture(BORDER)
        t:SetBlendMode("ADD")        -- alphaMode = "ADD"
        t:SetSize(16, 16)
        t:SetPoint(d.point)
        t:SetTexCoord(d.left, d.right, 0, 1)
        t:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- The two trinket-button templates. Everything except OnLoad is shared; OnLoad
-- differs because the worn buttons override it (note 2) and the menu buttons
-- do not.
-- ---------------------------------------------------------------------------
local function attachTrinketScripts(b, onClick, onEnter)
    b:SetScript("OnShow", function(self)
        if self.Arrow then self.Arrow:SetShown(false) end
    end)
    b:SetScript("PostClick", function(self, button, down)
        onClick(self, button, down)
    end)
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", function() Trinkets.ClearTooltip() end)
end

local function styleActionButton(b)
    if b.cooldown then b.cooldown:SetSwipeColor(0, 0, 0, 0.8) end
    if b.icon then b.icon:SetAllPoints() end
end

-- <CheckButton name="TrinketsMainTrinketTemplate" inherits="ActionButtonTemplate,SecureActionButtonTemplate">
local function makeWornTrinket(name, parent, id, point, retailX, retailY, classicX, classicY)
    local b = CreateFrame("CheckButton", name, parent,
        "ActionButtonTemplate,SecureActionButtonTemplate")
    b:SetID(id)
    attachTrinketScripts(b, Trinkets.MainTrinket_OnClick, function(self)
        if TrinketsOptions.MenuOnRight == "OFF" then Trinkets.BuildMenu() end
        Trinkets.WornTrinketTooltip(self)
    end)

    -- The per-button OnLoad from the XML, which replaced the template's. Note it
    -- registers THREE click types where the template registered two, and never
    -- blanks TogglePopup -- both differences are the XML's, kept as they are.
    if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        b:SetPoint(point, retailX, retailY)
    else
        b:SetPoint(point, classicX, classicY)
    end
    b:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp")
    styleActionButton(b)
    return b
end

-- <CheckButton name="TrinketsMenuTrinketTemplate" inherits="ActionButtonTemplate">
local function makeMenuTrinket(name, parent, id)
    local b = CreateFrame("CheckButton", name, parent, "ActionButtonTemplate")
    b:SetID(id)
    attachTrinketScripts(b, Trinkets.MenuTrinket_OnClick, function(self)
        Trinkets.MenuTrinketTooltip(self)
    end)
    -- The template's own OnLoad, which here is the only one.
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if b.TogglePopup then b.TogglePopup = function() end end
    styleActionButton(b)
    return b
end

-- ---------------------------------------------------------------------------
-- <Frame name="Trinkets_MainFrame"> -- the equipped trinkets
-- ---------------------------------------------------------------------------
local main = CreateFrame("Frame", "Trinkets_MainFrame", UIParent)
main:SetSize(92, 52)
main:SetToplevel(true)
main:SetFrameStrata("BACKGROUND")
main:EnableMouse(true)
main:SetMovable(true)
main:Hide()                                   -- before any OnHide is attached
applyBackdropTemplate(main)
-- <KeyValue key="backdropInfo" ... type="global"/>, and it has to be in place
-- before Trinkets.OnLoad calls OnBackdropLoaded below.
main.backdropInfo = Trinkets_BACKDROP_16_16_4444
main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 400, 400)

makeDocks(main, "Trinkets_MainDock_")

local trinket0 = makeWornTrinket("Trinkets_Trinket0", main, 13, "TOPLEFT", 4, -4, 8, -8)
makeTimeFrame(trinket0,  "Trinkets_Trinket0Time")
makeQueueFrame(trinket0, "Trinkets_Trinket0Queue")

local trinket1 = makeWornTrinket("Trinkets_Trinket1", main, 14, "BOTTOMRIGHT", -3, 3, -8, 8)
makeTimeFrame(trinket1,  "Trinkets_Trinket1Time")
makeQueueFrame(trinket1, "Trinkets_Trinket1Queue")

main:SetScript("OnEvent",     function(self, event, ...) Trinkets.OnEvent(self, event, ...) end)
main:SetScript("OnMouseDown", function(self) Trinkets.MainFrame_OnMouseDown(self) end)
main:SetScript("OnMouseUp",   function(self) Trinkets.MainFrame_OnMouseUp(self) end)
main:SetScript("OnShow",      function() Trinkets.OnShow() end)
main:SetScript("OnHide",      function() Trinkets.OnHide() end)

-- ---------------------------------------------------------------------------
-- <Frame name="Trinkets_MenuFrame"> -- the bagged trinkets
-- ---------------------------------------------------------------------------
local menu = CreateFrame("Frame", "Trinkets_MenuFrame", UIParent)
menu:SetSize(52, 92)
menu:SetToplevel(true)
menu:SetFrameStrata("MEDIUM")
menu:EnableMouse(true)
menu:SetMovable(true)
menu:SetClampedToScreen(true)
menu:Hide()
applyBackdropTemplate(menu)
menu.backdropInfo = Trinkets_BACKDROP_16_16_4444
menu:SetPoint("BOTTOMLEFT", main, "BOTTOMRIGHT")

makeDocks(menu, "Trinkets_MenuDock_")

-- 30 buttons, then 30 time frames -- the XML builds them in that order and the
-- menu's own layout code walks them by name, so the order is kept.
for i = 1, 30 do
    makeMenuTrinket("Trinkets_Menu" .. i, menu, i)
end
for i = 1, 30 do
    makeTimeFrame(_G["Trinkets_Menu" .. i], "Trinkets_Menu" .. i .. "Time")
end

menu:SetScript("OnMouseDown", function(_, button) Trinkets.MenuFrame_OnMouseDown(button) end)
menu:SetScript("OnMouseUp",   function(_, button) Trinkets.MenuFrame_OnMouseUp(button) end)

-- ---------------------------------------------------------------------------
-- <Frame name="Trinkets_TimersFrame"> -- drives every timer
-- ---------------------------------------------------------------------------
local timers = CreateFrame("Frame", "Trinkets_TimersFrame", UIParent)
timers:Hide()
timers:SetScript("OnUpdate", function(_, elapsed) Trinkets.TimersFrame_OnUpdate(elapsed) end)

-- ---------------------------------------------------------------------------
-- <GameTooltip name="Trinkets_TooltipScan"> -- read-only, never shown
-- ---------------------------------------------------------------------------
local scan = CreateFrame("GameTooltip", "Trinkets_TooltipScan", UIParent, "GameTooltipTemplate")
scan:Hide()
scan:SetOwner(WorldFrame, "ANCHOR_NONE")      -- the XML's OnLoad

-- ---------------------------------------------------------------------------
-- OnLoad, last and in XML order: the children above are built, so the parent's
-- OnLoad finds everything it expects.
--
-- MenuFrame's OnLoad body first, then MainFrame's -- MainFrame's registers the
-- slash command and PLAYER_LOGIN, which is the point the whole addon starts
-- from, and it should not start before the menu exists.
-- ---------------------------------------------------------------------------
menu:OnBackdropLoaded()
menu:SetBackdropColor(0, 0, 0)
menu:SetBackdropBorderColor(0, 0, 0)

Trinkets.OnLoad(main)
