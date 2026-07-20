-- Shared popup-menu helper; EasyMenu is often nil on Anniversary.
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
        _menuFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
        local bd = (ns.COLORS and ns.COLORS.borderDark) or { r = 0.02, g = 0.02, b = 0.03 }
        _menuFrame:SetBackdropBorderColor(bd.r, bd.g, bd.b, 1)
    end
    if ns.UI and ns.UI.CreateShadow then ns.UI:CreateShadow(_menuFrame) end
    -- ESC closes
    tinsert(UISpecialFrames, "VCUI_SharedPopupMenu")
    return _menuFrame
end

local function getMenuButton(idx)
    local btn = _menuButtons[idx]
    if btn then return btn end
    btn = CreateFrame("Button", nil, _menuFrame)
    btn:SetHeight(20)

    local ac = (ns.COLORS and ns.COLORS.accent) or { r = 0.608, g = 0.424, b = 1 }

    btn.check = btn:CreateTexture(nil, "OVERLAY")
    btn.check:SetSize(6, 6)
    btn.check:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.check:SetColorTexture(ac.r, ac.g, ac.b, 1)
    btn.check:Hide()

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if ns.UI and ns.UI.Font then ns.UI.Font(btn.text, 11) end
    btn.text:SetPoint("LEFT", btn, "LEFT", 22, 0)
    btn.text:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
    btn.text:SetJustifyH("LEFT")

    btn.hl = btn:CreateTexture(nil, "BACKGROUND")
    btn.hl:SetAllPoints(btn)
    btn.hl:SetColorTexture(ac.r, ac.g, ac.b, 0.22)
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
            local ac = (ns.COLORS and ns.COLORS.accent) or { r = 0.608, g = 0.424, b = 1 }
            btn.text:SetTextColor(ac.r, ac.g, ac.b)
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
                local fn        = entry.func
                local keepOpen  = entry.keepOpen
                local checkedFn = entry.checked
                btn:SetScript("OnClick", function()
                    if not keepOpen then menu:Hide() end
                    if fn then fn() end
                    -- keepOpen items must re-evaluate their checkmark in place
                    if keepOpen and checkedFn then
                        local ok, isChecked = pcall(checkedFn)
                        btn.check:SetShown(ok and isChecked)
                    end
                end)
            end
            if entry.checked then
                local ok, isChecked = pcall(entry.checked)
                if ok and isChecked then btn.check:Show() end
            end
        end

        local stringWidth = btn.text:GetStringWidth() or 0
        if stringWidth > maxTextWidth then maxTextWidth = stringWidth end

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  menu, "TOPLEFT",  4, y)
        btn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, y)
        y = y - btn:GetHeight() - 1
    end

    local desiredWidth = math.min(360, math.max(180, maxTextWidth + 40))
    menu:SetWidth(desiredWidth)
    menu:SetHeight(-y + 6)

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

    -- Toggle: clicking the SAME anchor again closes; a different anchor moves it
    if menu:IsShown() and menu._openAnchor == anchor then
        menu:Hide()
        menu._openAnchor = nil
    else
        menu._openAnchor = anchor
        menu:Show()
    end
end

function ns:HidePopupMenu()
    if _menuFrame and _menuFrame:IsShown() then _menuFrame:Hide() end
end
