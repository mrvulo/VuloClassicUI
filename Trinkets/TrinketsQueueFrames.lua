-- VuloClassicUI / Trinkets / QueueFrames: TrinketsQueue.xml, in Lua.
--
-- Third and last, 869 lines of XML. With this one the folder holds no XML at
-- all and TrinketsTemplates.xml -- the shim that carried shared templates
-- across the conversion -- is gone with it.
--
-- Same rules as the first two: names keep their spelling because the vendored
-- code reads them as globals, OnLoad is called by hand, hidden frames are
-- hidden before an OnHide script exists to fire.
--
-- TWO THINGS THIS FILE DOES THAT THE OTHERS DID NOT
--
-- It reaches INTO Trinkets_OptFrame. Four of its frames -- two tabs and their
-- check boxes -- are children of a frame built in TrinketsOptFrames.lua, and
-- Trinkets_SubQueueFrame is too. That is why the load order in the TOC matters
-- and why this file comes last.
--
-- Trinkets_SortDelay was declared virtual="true" in the XML while the code uses
-- it as a real frame (SetText, Show, ClearFocus on it by name). WoW evidently
-- ignores the attribute for an element sitting inside <Frames>. In Lua there is
-- no ambiguity to reproduce: it is created as what the code needs.
local _, ns = ...

local BG        = "Interface\\ChatFrame\\ChatFrameBackground"
local QUEST_HL  = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local EDGE      = "Interface\\ClassTrainerFrame\\UI-ClassTrainer-FilterBorder"
local MEDIA     = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\"

local function gradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    if tex.SetGradient and CreateColor then
        tex:SetGradient(orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    elseif tex.SetGradientAlpha then
        tex:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2)
    end
end

local function insetBackground(parent, r1, g1, b1, a1, r2, g2, b2, a2)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(BG)
    t:SetPoint("TOPLEFT", 4, -4)
    t:SetPoint("BOTTOMRIGHT", -4, 4)
    gradient(t, "VERTICAL", r1, g1, b1, a1, r2, g2, b2, a2)
    return t
end

-- A panel with the backdrop mixin, its inset background and its own OnLoad --
-- three of these in this file, identical apart from the shade.
local function makePanel(name, parent, r1, g1, b1, r2, g2, b2)
    local f = CreateFrame("Frame", name, parent)
    Mixin(f, TrinketsBackdropTemplateMixin)
    f:SetScript("OnSizeChanged", f.OnBackdropSizeChanged)
    f.backdropInfo = Trinkets_BACKDROP_16
    insetBackground(f, r1, g1, b1, 1, r2, g2, b2, 1)
    return f
end

-- The three-slice border both edit boxes wear.
local function editBoxBorder(box, name, leftX, leftY, rightX, rightY)
    local l = box:CreateTexture(name .. "Left", "BACKGROUND")
    l:SetTexture(EDGE); l:SetSize(12, 29)
    l:SetPoint("TOPLEFT", leftX, leftY)
    l:SetTexCoord(0, 0.09375, 0, 1)

    local r = box:CreateTexture(name .. "Right", "BACKGROUND")
    r:SetTexture(EDGE); r:SetSize(12, 29)
    r:SetPoint("TOPRIGHT", rightX, rightY)
    r:SetTexCoord(0.90625, 1, 0, 1)

    local mid = box:CreateTexture(nil, "BACKGROUND")
    mid:SetTexture(EDGE)
    mid:SetPoint("TOPLEFT", l, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    mid:SetTexCoord(0.09375, 0.90625, 0, 1)
    return l, r
end

-- ---------------------------------------------------------------------------
-- The five templates this file declared, as factories.
-- ---------------------------------------------------------------------------

-- <Button name="Trinkets_ProfilesListTemplate">
local function makeProfileRow(name, parent)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(174, 20)
    b:RegisterForClicks("LeftButtonUp")
    local fs = b:CreateFontString(name .. "Name", "BACKGROUND", "GameFontHighlight")
    fs:SetText("Profile name")
    fs:SetPoint("LEFT", 8, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(QUEST_HL); hl:SetBlendMode("ADD"); hl:SetAllPoints(b)
    b:SetHighlightTexture(hl)
    b:SetScript("OnClick",       function(self) Trinkets.ProfileList_OnClick(self) end)
    b:SetScript("OnDoubleClick", function(self) Trinkets.ProfileList_OnDoubleClick(self) end)
    return b
end

-- <Button name="Trinkets_ProfilesButtonTemplate" inherits="UIPanelButtonGrayTemplate">
local function makeProfileButton(name, parent, text)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonGrayTemplate")
    b:SetSize(54, 24)
    b:SetText(text)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetScript("OnEnter", function(self) Trinkets.OnTooltip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) Trinkets.ProfilesButton_OnClick(self) end)
    return b
end

-- <CheckButton name="Trinkets_TabCheckTemplate" inherits="UICheckButtonTemplate">
-- The XML OnLoad reads its own id to find the tab it sits on, so the tab has to
-- exist first -- which is why each pair below is built tab, then check.
local function makeTabCheck(name, parent, id)
    local b = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    b:SetSize(24, 24)
    b:SetID(id)
    b:SetScript("OnEnter", function(self) Trinkets.OnTooltip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) Trinkets.TabCheck_OnClick(self) end)
    local tab = _G["Trinkets_Tab" .. id]
    if tab then b:SetFrameLevel(tab:GetFrameLevel() + 2) end
    return b
end

-- <Button name="Trinkets_SortTemplate">
local function makeSortRow(name, parent, id)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(210, 24)
    b:SetID(id)

    local icon = b:CreateTexture(name .. "Icon", "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("TOPLEFT", 4, -1)

    local fs = b:CreateFontString(name .. "Name", "ARTWORK", "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetSize(170, 22)
    fs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    fs:SetPoint("RIGHT")

    local hl = b:CreateTexture(name .. "Highlight", "BACKGROUND")
    hl:SetTexture(QUEST_HL); hl:SetBlendMode("ADD")
    hl:SetSize(210, 24)
    hl:SetPoint("TOPLEFT")
    hl:Hide()

    b:SetScript("OnEnter", function(self)
        _G[self:GetName() .. "Highlight"]:Show()
        Trinkets.SortTooltip(self)
    end)
    b:SetScript("OnLeave", function(self)
        if not self.lockedHighlight then
            _G[self:GetName() .. "Highlight"]:Hide()
        end
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self) Trinkets.SortOnClick(self) end)
    return b
end

-- <Button name="Trinkets_MoveButtonTemplate">
local function makeMoveButton(name, parent, normal, tint)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(24, 24)
    b:SetScript("OnEnter", function(self) Trinkets.OnTooltip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) Trinkets.SortMove(self) end)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(0.608, 0.424, 1)
    hl:SetAllPoints(b)
    b:SetHighlightTexture(hl)

    -- Same art for all three states, told apart by shade -- the folder the
    -- original atlas lived in was never shipped with this addon, see 662bfe8.
    local n = b:CreateTexture(nil, "ARTWORK")
    n:SetTexture(normal)
    if tint then n:SetVertexColor(unpack(tint)) end
    b:SetNormalTexture(n)

    local p = b:CreateTexture(nil, "ARTWORK")
    p:SetTexture(normal); p:SetVertexColor(0.65, 0.65, 0.65)
    b:SetPushedTexture(p)

    local d = b:CreateTexture(nil, "ARTWORK")
    d:SetTexture(normal); d:SetVertexColor(0.35, 0.35, 0.35)
    b:SetDisabledTexture(d)
    return b
end

local ACCENT = { 0.608, 0.424, 1 }

-- ---------------------------------------------------------------------------
-- Two more tabs on the options window, each with its check box.
-- ---------------------------------------------------------------------------
local optFrame = _G.Trinkets_OptFrame

local tab2 = Trinkets.NewTabButton("Trinkets_Tab2", optFrame, 2, "Bottom")
tab2:SetPoint("TOPRIGHT", _G.Trinkets_Tab1, "TOPLEFT")
local check1 = makeTabCheck("Trinkets_Trinket1Check", optFrame, 2)
check1:SetPoint("RIGHT", tab2, "RIGHT", -4, 0)

local tab3 = Trinkets.NewTabButton("Trinkets_Tab3", optFrame, 3, "Top")
tab3:SetPoint("TOPRIGHT", tab2, "TOPLEFT")
local check0 = makeTabCheck("Trinkets_Trinket0Check", optFrame, 3)
check0:SetPoint("RIGHT", tab3, "RIGHT", -4, 0)

-- ---------------------------------------------------------------------------
-- <Frame name="Trinkets_SubQueueFrame"> -- the queue panel
-- ---------------------------------------------------------------------------
local subq = makePanel("Trinkets_SubQueueFrame", optFrame, 0.15, 0.15, 0.15, 0.33, 0.33, 0.33)
subq:Hide()
subq:SetPoint("TOPLEFT", 8, -50)
subq:SetPoint("BOTTOMRIGHT", -8, 8)

local moveTop = makeMoveButton("Trinkets_MoveTop", subq, MEDIA .. "arrow_up", ACCENT)
moveTop:SetPoint("TOPLEFT", 8, -50)
local moveUp = makeMoveButton("Trinkets_MoveUp", subq, MEDIA .. "arrow_up")
moveUp:SetPoint("TOPLEFT", moveTop, "BOTTOMLEFT", 0, -8)
local moveDown = makeMoveButton("Trinkets_MoveDown", subq, MEDIA .. "arrow_down")
moveDown:SetPoint("TOPLEFT", moveUp, "BOTTOMLEFT", 0, -8)
local moveBottom = makeMoveButton("Trinkets_MoveBottom", subq, MEDIA .. "arrow_down", ACCENT)
moveBottom:SetPoint("TOPLEFT", moveDown, "BOTTOMLEFT", 0, -8)

local profilesBtn = makeMoveButton("Trinkets_Profiles", subq, MEDIA .. "modules\\profiles")
profilesBtn:SetPoint("BOTTOMLEFT", moveTop, "TOPLEFT", 0, 12)
local deleteBtn = makeMoveButton("Trinkets_Delete", subq, MEDIA .. "broom")
deleteBtn:SetPoint("TOPLEFT", moveBottom, "BOTTOMLEFT", 0, -12)

-- <EditBox name="Trinkets_SortDelay">
local delay = CreateFrame("EditBox", "Trinkets_SortDelay", subq)
delay:SetSize(28, 20)
delay:SetPoint("BOTTOMLEFT", 54, 8)
delay:SetNumeric(true)
delay:SetAutoFocus(false)
delay:SetMaxLetters(3)
delay:EnableMouse(true)
delay:SetFontObject("GameFontHighlight")
delay:SetJustifyH("RIGHT")
editBoxBorder(delay, "Trinkets_SortDelay", -7, 2, 10, 2)

local delayCap = delay:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
delayCap:SetJustifyH("RIGHT"); delayCap:SetText("Delay")
delayCap:SetPoint("RIGHT", delay, "LEFT", -10, 0)
local delaySec = delay:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
delaySec:SetJustifyH("LEFT"); delaySec:SetText("sec")
delaySec:SetPoint("LEFT", delay, "RIGHT", 12, 0)

delay:SetScript("OnEnter",         function(self) Trinkets.OnTooltip(self) end)
delay:SetScript("OnLeave",         function() GameTooltip:Hide() end)
delay:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
delay:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
delay:SetScript("OnTextChanged",   function() Trinkets.SortDelay_OnTextChanged() end)

local sortPrio = Trinkets.NewOptCheck("Trinkets_SortPriority", subq)
sortPrio:SetPoint("TOPLEFT", delay, "TOPRIGHT", 40, 2)
sortPrio:SetScript("OnClick", function(self) Trinkets.SortPriority_OnClick(self) end)

local sortKeep = Trinkets.NewOptCheck("Trinkets_SortKeepEquipped", subq)
sortKeep:SetPoint("TOPLEFT", sortPrio, "TOPRIGHT", 40, 0)
sortKeep:SetScript("OnClick", function(self) Trinkets.SortKeepEquipped_OnClick(self) end)

-- ---------------------------------------------------------------------------
-- <Frame name="Trinkets_SortListFrame"> -- nine rows and a scroll bar
-- ---------------------------------------------------------------------------
local sortList = makePanel("Trinkets_SortListFrame", subq, 0.075, 0.075, 0.075, 0.165, 0.165, 0.165)
sortList:SetPoint("TOPLEFT", 32, -8)
sortList:SetPoint("BOTTOMRIGHT", -8, 28)

local prevSort
for i = 1, 9 do
    local row = makeSortRow("Trinkets_Sort" .. i, sortList, i)
    if prevSort then
        row:SetPoint("TOPLEFT", prevSort, "BOTTOMLEFT")
    else
        row:SetPoint("TOPLEFT", 6, -6)
    end
    prevSort = row
end

local sortScroll = CreateFrame("ScrollFrame", "Trinkets_SortScroll", sortList, "FauxScrollFrameTemplate")
sortScroll:SetPoint("TOPLEFT",     _G.Trinkets_Sort1, "TOPLEFT")
sortScroll:SetPoint("BOTTOMRIGHT", _G.Trinkets_Sort9, "BOTTOMRIGHT")
local sortScrollBG = sortScroll:CreateTexture(nil, "BACKGROUND")
sortScrollBG:SetTexture(BG)
sortScrollBG:SetPoint("TOPLEFT",     sortScroll, "TOPRIGHT",     0,  2)
sortScrollBG:SetPoint("BOTTOMRIGHT", sortScroll, "BOTTOMRIGHT", 25, -2)
gradient(sortScrollBG, "HORIZONTAL", 0, 0, 0, 0, 0, 0, 0, 1)
sortScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, 24, Trinkets.SortScrollFrameUpdate)
end)
sortScroll:SetScript("OnShow", function() Trinkets.SortScrollFrameUpdate() end)

sortList:OnBackdropLoaded()

-- ---------------------------------------------------------------------------
-- <Frame name="Trinkets_ProfilesFrame">
-- ---------------------------------------------------------------------------
local profFrame = makePanel("Trinkets_ProfilesFrame", subq, 0.15, 0.15, 0.15, 0.33, 0.33, 0.33)
profFrame:Hide()
profFrame:SetPoint("TOPLEFT", 32, -8)
profFrame:SetPoint("BOTTOMRIGHT", -8, 28)

local profName = CreateFrame("EditBox", "Trinkets_ProfileName", profFrame)
profName:SetSize(160, 20)
profName:SetPoint("TOP", 20, -10)
profName:SetAutoFocus(false)
profName:SetMaxLetters(256)
profName:EnableMouse(true)
profName:SetFontObject("GameFontHighlight")
local profLeft = editBoxBorder(profName, "Trinkets_ProfileName", -11, 2, 4, 2)

local profCap = profName:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
profCap:SetText("Profile")
profCap:SetPoint("RIGHT", profLeft, "LEFT", -4, 2)

profName:SetScript("OnEnter",         function(self) Trinkets.OnTooltip(self) end)
profName:SetScript("OnLeave",         function() GameTooltip:Hide() end)
profName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
profName:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
profName:SetScript("OnTextChanged",   function() Trinkets.ProfileName_OnTextChanged() end)

local pDel = makeProfileButton("Trinkets_ProfilesDelete", profFrame, "Delete")
pDel:SetPoint("BOTTOMLEFT", 8, 12)
local pLoad = makeProfileButton("Trinkets_ProfilesLoad", profFrame, "Load")
pLoad:SetPoint("LEFT", pDel, "RIGHT", 4, 0)
local pSave = makeProfileButton("Trinkets_ProfilesSave", profFrame, "Save")
pSave:SetPoint("LEFT", pLoad, "RIGHT", 4, 0)
local pCancel = makeProfileButton("Trinkets_ProfilesCancel", profFrame, "Cancel")
pCancel:SetPoint("LEFT", pSave, "RIGHT", 4, 0)

local profList = makePanel("Trinkets_ProfilesListFrame", profFrame, 0.075, 0.075, 0.075, 0.165, 0.165, 0.165)
profList:SetPoint("TOPLEFT", 16, -34)
profList:SetPoint("BOTTOMRIGHT", -16, 40)

local prevProf
for i = 1, 7 do
    local row = makeProfileRow("Trinkets_Profile" .. i, profList)
    row:SetID(i)
    if prevProf then
        row:SetPoint("TOPLEFT", prevProf, "BOTTOMLEFT")
    else
        row:SetPoint("TOPLEFT", 8, -8)
    end
    prevProf = row
end

local profScroll = CreateFrame("ScrollFrame", "Trinkets_ProfileScroll", profList, "FauxScrollFrameTemplate")
profScroll:SetPoint("TOPLEFT",     _G.Trinkets_Profile1, "TOPLEFT")
profScroll:SetPoint("BOTTOMRIGHT", _G.Trinkets_Profile7, "BOTTOMRIGHT")
local profScrollBG = profScroll:CreateTexture(nil, "BACKGROUND")
profScrollBG:SetTexture(BG)
profScrollBG:SetPoint("TOPLEFT",     profScroll, "TOPRIGHT",     0,  2)
profScrollBG:SetPoint("BOTTOMRIGHT", profScroll, "BOTTOMRIGHT", 25, -2)
gradient(profScrollBG, "HORIZONTAL", 0, 0, 0, 0, 0, 0, 0, 1)
profScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, 20, Trinkets.ProfileScrollFrameUpdate)
end)
profScroll:SetScript("OnShow", function() Trinkets.ProfileScrollFrameUpdate() end)

profList:OnBackdropLoaded()

local hideOnLoad = Trinkets.NewOptCheck("Trinkets_OptHideOnLoad", profFrame)
hideOnLoad:SetPoint("TOPLEFT", profFrame, "BOTTOMLEFT", 50, 2)

-- OnLoad and the window scripts last, as XML would have reached them.
profFrame:OnBackdropLoaded()
profFrame:SetScript("OnHide", function() Trinkets.ProfilesFrame_OnHide() end)
profFrame:SetScript("OnShow", function() PlaySound(624) end)

subq:OnBackdropLoaded()
