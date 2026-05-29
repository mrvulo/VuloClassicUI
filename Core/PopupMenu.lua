-- =========================================================
-- VuloClassicUI / Core / PopupMenu
-- Shared popup-menu helper as a replacement for EasyMenu, which is
-- unreliable in Anniversary (often nil → modules that call it crash).
--
-- Usage:
--   ns:ShowPopupMenu(entries, anchorFrame)
--
-- Entry shape:
--   { title     = true,  text = "Header" }              — section header
--   { separator = true }                                — visual divider
--   { text      = "Item", func = function() ... end }   — clickable
--   { text      = "...",  checked = function() return mod.db.x end,
--     func = function() ... end, keepOpen = true }      — toggle (stays open)
--   { text      = "...",  disabled = true }             — greyed
-- =========================================================
local _, ns = ...

local _menuFrame
local _menuButtons = {}

local function createMenuFrame()
    if _menuFrame then return _menuFrame end
    _menuFrame = CreateFrame("Frame", "VCUI_SharedPopupMenu", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")
    _menuFrame:SetFrameStrata("DIALOG")
    _menuFrame:SetWidth(200)
    _menuFrame:SetHeight(30)
    _menuFrame:Hide()
    _menuFrame:EnableMouse(true)
    _menuFrame:SetClampedToScreen(true)
    if _menuFrame.SetBackdrop then
        _menuFrame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        _menuFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        _menuFrame:SetBackdropBorderColor(0.4, 0.3, 0.6, 1)
    end
    -- ESC closes
    tinsert(UISpecialFrames, "VCUI_SharedPopupMenu")
    return _menuFrame
end

local function getMenuButton(idx)
    local btn = _menuButtons[idx]
    if btn then return btn end
    btn = CreateFrame("Button", nil, _menuFrame)
    btn:SetHeight(20)

    -- Checkmark (left)
    btn.check = btn:CreateTexture(nil, "OVERLAY")
    btn.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    btn.check:SetSize(14, 14)
    btn.check:SetPoint("LEFT", btn, "LEFT", 4, 0)
    btn.check:Hide()

    -- Label
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("LEFT", btn, "LEFT", 22, 0)
    btn.text:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
    btn.text:SetJustifyH("LEFT")

    -- Hover highlight
    btn.hl = btn:CreateTexture(nil, "BACKGROUND")
    btn.hl:SetAllPoints(btn)
    btn.hl:SetColorTexture(0.4, 0.3, 0.6, 0.3)
    btn.hl:Hide()

    btn:SetScript("OnEnter", function(self)
        if self._clickable then self.hl:Show() end
    end)
    btn:SetScript("OnLeave", function(self) self.hl:Hide() end)
    _menuButtons[idx] = btn
    return btn
end

function ns:ShowPopupMenu(entries, anchor)
    if type(entries) ~= "table" then return end
    local menu = createMenuFrame()

    -- Hide leftover buttons from a previous menu
    for _, b in ipairs(_menuButtons) do b:Hide() end

    local y, maxTextWidth = -6, 0

    for i, entry in ipairs(entries) do
        local btn = getMenuButton(i)
        btn:Show()
        btn.check:Hide()
        btn._clickable = false

        if entry.separator then
            btn:SetHeight(6)
            btn.text:SetText("")
            btn:EnableMouse(false)
            btn:SetScript("OnClick", nil)
        elseif entry.title then
            btn:SetHeight(20)
            btn.text:SetText(entry.text or "")
            btn.text:SetTextColor(1, 0.82, 0)
            btn:EnableMouse(false)
            btn:SetScript("OnClick", nil)
        else
            btn:SetHeight(20)
            btn.text:SetText(entry.text or "")
            if entry.disabled then
                btn.text:SetTextColor(0.5, 0.5, 0.5)
                btn:EnableMouse(false)
                btn:SetScript("OnClick", nil)
            else
                btn.text:SetTextColor(1, 1, 1)
                btn:EnableMouse(true)
                btn._clickable = true
                btn:RegisterForClicks("LeftButtonUp")
                local fn       = entry.func
                local keepOpen = entry.keepOpen
                btn:SetScript("OnClick", function()
                    if not keepOpen then menu:Hide() end
                    if fn then fn() end
                end)
            end
            -- Checkmark
            if entry.checked then
                local ok, isChecked = pcall(entry.checked)
                if ok and isChecked then btn.check:Show() end
            end
        end

        -- Compute approximate text width to size the menu
        local stringWidth = btn.text:GetStringWidth() or 0
        if stringWidth > maxTextWidth then maxTextWidth = stringWidth end

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  menu, "TOPLEFT",  4, y)
        btn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, y)
        y = y - btn:GetHeight() - 1
    end

    -- Auto-size width based on widest label (with some padding for checkmark + margins)
    local desiredWidth = math.min(360, math.max(180, maxTextWidth + 40))
    menu:SetWidth(desiredWidth)
    menu:SetHeight(-y + 6)

    -- Position relative to anchor
    menu:ClearAllPoints()
    if anchor and anchor.GetLeft then
        menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", -2, 0)
    elseif anchor == "cursor" then
        local cx, cy = GetCursorPosition()
        local scale  = UIParent:GetEffectiveScale() or 1
        menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    else
        menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- Toggle: clicking same anchor again closes
    if menu:IsShown() then
        menu:Hide()
    else
        menu:Show()
    end
end

-- Convenience: force-close (e.g. when toggling a checkbox should hide elsewhere)
function ns:HidePopupMenu()
    if _menuFrame and _menuFrame:IsShown() then _menuFrame:Hide() end
end
