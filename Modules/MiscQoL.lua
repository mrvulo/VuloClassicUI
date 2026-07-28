-- General QoL toggles.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("miscqol", {
    name        = "General",
    group       = "Extras",
    description = "Collection of simple quality-of-life toggles: auto-accept (quest, res, summon), auto-sell, repair, hide UI spam, text sizes.",
    defaults    = {
        enabled               = true,
        autoAcceptQuest       = false,
        autoTurnInQuest       = false,
        autoAcceptRes         = true,
        autoAcceptSummon      = false,
        autoReleasePvP        = true,
        blockStrangerInvites  = false,
        blockStrangerTrades   = false,
        autoGossip            = false,
        fasterLoot            = true,
        maxCameraZoom         = false,
        autoSellJunk          = true,
        autoRepair            = true,
        maxStackButton        = true,
        skinStackSplit        = true,
        skinGameMenu          = true,
        gameMenuButton        = true,
        hideErrors            = false,
        hideZoneText          = false,
        hidePortraitNumbers   = false,
        crispHitNumbers       = true,
        hitNumberSize         = 22,
        hideKeybindText       = false,
        hideMacroText         = false,
        hideStackCount        = false,
        hideRaidGroupLabels   = false,
        mailTextSize          = 13,
        questTextSize         = 14,
        bookTextSize          = 14,
        flight = {
            enabled    = true,
            chatReport = false,
            barWidth   = 240,
            barHeight  = 18,
            x          = 0,
            y          = 280,
            unlocked   = false,
            times      = {},
        },
    },
})

-- API compat (Anniversary uses C_Container instead of globals)
local GetContainerNumSlots  = (C_Container and C_Container.GetContainerNumSlots)  or _G.GetContainerNumSlots
local GetContainerItemInfo  = (C_Container and C_Container.GetContainerItemInfo)  or _G.GetContainerItemInfo
local UseContainerItem      = (C_Container and C_Container.UseContainerItem)      or _G.UseContainerItem
local GetContainerItemLink  = (C_Container and C_Container.GetContainerItemLink)  or _G.GetContainerItemLink
local GetCVarBool           = (C_CVar and C_CVar.GetCVarBool)                     or _G.GetCVarBool

local function isJunkLegacy(bag, slot)
    local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
    if not link then return false end
    local _, _, q = GetItemInfo(link)
    return q == 0
end

local function fmtCopper(c)
    c = math.abs(c or 0)
    local g  = math.floor(c / 10000)
    local s  = math.floor((c % 10000) / 100)
    local cu = c % 100
    local gold   = (ns.C and ns.C.gold)   or "|cffffd100"
    local silver = (ns.C and ns.C.silver) or "|cffc7c7cf"
    local copper = (ns.C and ns.C.copper) or "|cffeda55f"
    local r      = (ns.C and ns.C.r)      or "|r"
    if g > 0 then
        return string.format("%d%sg%s %d%ss%s %d%sc%s", g, gold, r, s, silver, r, cu, copper, r)
    elseif s > 0 then
        return string.format("%d%ss%s %d%sc%s", s, silver, r, cu, copper, r)
    end
    return string.format("%d%sc%s", cu, copper, r)
end

local function sellAllJunk()
    if not GetContainerNumSlots or not UseContainerItem then return end
    local sold = 0
    local moneyBefore = GetMoney() or 0

    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local junk = false
            if GetContainerItemInfo then
                local info = GetContainerItemInfo(bag, slot)
                if type(info) == "table" then
                    junk = (info.quality == 0)
                end
            end
            if not junk then
                junk = isJunkLegacy(bag, slot)
            end
            if junk then
                UseContainerItem(bag, slot)
                sold = sold + 1
            end
        end
    end

    if sold > 0 then
        local repairExpected = 0
        if mod.db.autoRepair and CanMerchantRepair and CanMerchantRepair() and GetRepairAllCost then
            repairExpected = GetRepairAllCost() or 0
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.6, function()
                local earned = (GetMoney() or 0) - moneyBefore + repairExpected
                if earned > 0 then
                    ns:Print(L["Auto-sold: %d items, +%s"], sold, fmtCopper(earned))
                else
                    ns:Print(L["Auto-sold: %d items."], sold)
                end
            end)
        else
            ns:Print(L["Auto-sold: %d items."], sold)
        end
    end
end

local function repairAll()
    if not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost = (GetRepairAllCost and GetRepairAllCost()) or 0
    if cost <= 0 then return end
    if (GetMoney() or 0) < cost then
        ns:Print(L["Repair exceeds gold (%d < %d)."], GetMoney() or 0, cost)
        return
    end
    RepairAllItems()
    local g = math.floor(cost / 10000)
    local s = math.floor((cost % 10000) / 100)
    ns:Print(L["Auto-repaired (%dg %ds)."], g, s)
end

local _stackSplitHooked = false

local function applyMaxStackButton()
    if not StackSplitFrame then return end
    local btn = _G.VCUI_StackSplitMaxButton
    if not btn then return end
    btn:SetShown(mod.db.maxStackButton ~= false and StackSplitFrame:IsShown())
end

local function setupStackSplitMaxButton()
    if _stackSplitHooked then return end
    if not StackSplitFrame then return end

    local okBtn  = StackSplitFrame.okayButton  or _G.StackSplitOkayButton
    local cancel = StackSplitFrame.cancelButton or _G.StackSplitCancelButton
    if not okBtn or not cancel then return end

    _stackSplitHooked = true

    -- Height only: the Classic backdrop has a fixed size and does not grow with SetWidth.
    if not StackSplitFrame._vcuiHeightExtended then
        StackSplitFrame._vcuiHeightExtended = true
        local h = StackSplitFrame:GetHeight() or 50
        StackSplitFrame:SetHeight(h + 28)
    end

    local btn = CreateFrame("Button", "VCUI_StackSplitMaxButton", StackSplitFrame, "UIPanelButtonTemplate")
    btn:SetSize(80, 22)
    btn:SetText(L["MAX"])
    btn:ClearAllPoints()
    btn:SetPoint("BOTTOM", StackSplitFrame, "BOTTOM", 0, 8)
    btn:SetFrameLevel(StackSplitFrame:GetFrameLevel() + 2)
    btn:SetScript("OnClick", function()
        local maxStack = StackSplitFrame.maxStack or 1
        if maxStack < 1 then return end

        -- Classic/Anniversary: .split is a NUMBER read by the OK handler; Retail: an EditBox.
        local s = StackSplitFrame.split
        if type(s) == "number" then
            StackSplitFrame.split = maxStack
            if _G.StackSplitText then
                _G.StackSplitText:SetText(maxStack)
            end
        elseif type(s) == "table" and s.SetNumber then
            s:SetNumber(maxStack)
        end

        local ok = StackSplitFrame.okayButton or _G.StackSplitOkayButton
        if ok and ok.Click then ok:Click() end
    end)

    StackSplitFrame:HookScript("OnShow", function()
        btn:SetShown(mod.db.maxStackButton ~= false)
    end)
    StackSplitFrame:HookScript("OnHide", function()
        btn:Hide()
    end)
end

-- StackSplitFrame skin: pure restyle; turning the option off needs a /reload.
local _stackSplitSkinned = false

local function setupStackSplitSkin()
    if _stackSplitSkinned then return end
    if mod.db.skinStackSplit == false then return end
    local f  = StackSplitFrame
    local UI = ns.UI
    if not (f and UI and UI.StyleBackdrop) then return end
    _stackSplitSkinned = true

    local ac = (ns.COLORS and ns.COLORS.accent) or { r = 0.608, g = 0.424, b = 1 }
    local bc = (ns.COLORS and ns.COLORS.border) or { r = 0.22, g = 0.22, b = 0.27 }

    local fontN, fontH, fontD = ns.UI:PanelButtonFonts("VCUI_SplitFont")

    local function stripTextures(region)
        for _, r in ipairs({ region:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then
                r:SetTexture(nil)
                r:SetAlpha(0)
            end
        end
    end

    local function addEdges(owner, holder)
        local edges = {}
        for i = 1, 4 do
            local t = owner:CreateTexture(nil, "BORDER")
            t:SetColorTexture(bc.r, bc.g, bc.b, 1)
            edges[i] = t
        end
        edges[1]:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0);       edges[1]:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0);       edges[1]:SetHeight(1)
        edges[2]:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0); edges[2]:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0); edges[2]:SetHeight(1)
        edges[3]:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0);       edges[3]:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0);   edges[3]:SetWidth(1)
        edges[4]:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0);     edges[4]:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0); edges[4]:SetWidth(1)
        return function(c, a)
            for _, t in ipairs(edges) do t:SetColorTexture(c.r, c.g, c.b, a or 1) end
        end
    end

    local function skinPanelButton(b)
        if not b or b._vcuiSkin then return end
        b._vcuiSkin = true
        stripTextures(b)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(b)
        bg:SetColorTexture(0.13, 0.13, 0.16, 1)
        local setEdges = addEdges(b, b)
        b:SetNormalFontObject(fontN)
        b:SetHighlightFontObject(fontH)
        b:SetDisabledFontObject(fontD)
        b:HookScript("OnEnter", function()
            bg:SetColorTexture(0.19, 0.19, 0.23, 1)
            setEdges(ac, 0.9)
        end)
        b:HookScript("OnLeave", function()
            bg:SetColorTexture(0.13, 0.13, 0.16, 1)
            setEdges(bc, 1)
        end)
    end

    local function skinArrow(b, dir)
        if not b or b._vcuiSkin then return end
        b._vcuiSkin = true
        stripTextures(b)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER", b, "CENTER", 0, 0)
        icon:SetSize(14, 14)
        icon:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\arrow_" .. dir .. ".tga")
        local function tint()
            if b:IsEnabled() then
                icon:SetVertexColor(ac.r, ac.g, ac.b, 1)
            else
                icon:SetVertexColor(0.4, 0.4, 0.45, 1)
            end
        end
        tint()
        b:HookScript("OnEnter",   function() if b:IsEnabled() then icon:SetVertexColor(1, 1, 1, 1) end end)
        b:HookScript("OnLeave",   tint)
        b:HookScript("OnDisable", tint)
        b:HookScript("OnEnable",  tint)
    end

    stripTextures(f)
    if f.NineSlice and f.NineSlice.SetAlpha then f.NineSlice:SetAlpha(0) end
    if f.Border and f.Border.SetAlpha then f.Border:SetAlpha(0) end
    UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border })
    if UI.CreateShadow then UI:CreateShadow(f) end
    local strip = f:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    if UI.SetGradient then
        UI.SetGradient(strip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)
    end
    f:SetSize(214, 88)

    local box = CreateFrame("Frame", nil, f)
    box:SetSize(104, 28)
    box:SetPoint("TOP", f, "TOP", 0, -14)
    local bbg = box:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints(box)
    bbg:SetColorTexture(0.05, 0.05, 0.07, 1)
    addEdges(box, box)

    local txt = _G.StackSplitText
    if txt then
        -- the text is a BACKGROUND region of f; adopt it into the box on OVERLAY so the number is not covered
        txt:SetParent(box)
        txt:SetDrawLayer("OVERLAY")
        txt:ClearAllPoints()
        txt:SetPoint("CENTER", box, "CENTER", 0, 0)
        if UI.Font then UI.Font(txt, 15) end
        txt:SetTextColor(1, 1, 1)
    end

    local left  = f.leftButton or f.LeftButton
        or _G.StackSplitLeftButton or _G.StackSplitFrameLeftButton
    local right = f.rightButton or f.RightButton
        or _G.StackSplitRightButton or _G.StackSplitFrameRightButton
    if left then
        skinArrow(left, "left")
        left:ClearAllPoints()
        left:SetPoint("RIGHT", box, "LEFT", -6, 0)
        left:SetSize(22, 22)
    end
    if right then
        skinArrow(right, "right")
        right:ClearAllPoints()
        right:SetPoint("LEFT", box, "RIGHT", 6, 0)
        right:SetSize(22, 22)
    end

    local okBtn  = StackSplitFrame.okayButton  or _G.StackSplitOkayButton
    local cancel = StackSplitFrame.cancelButton or _G.StackSplitCancelButton
    local maxBtn = _G.VCUI_StackSplitMaxButton
    if okBtn then
        skinPanelButton(okBtn)
        okBtn:ClearAllPoints()
        okBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
        okBtn:SetSize(62, 22)
    end
    if cancel then
        skinPanelButton(cancel)
        cancel:ClearAllPoints()
        cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
        cancel:SetSize(62, 22)
    end
    if maxBtn then
        skinPanelButton(maxBtn)
        maxBtn:ClearAllPoints()
        maxBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
        maxBtn:SetSize(62, 22)
    end
end

local function onMerchantShow()
    if mod.db.autoSellJunk then sellAllJunk() end
    if mod.db.autoRepair   then repairAll()   end
end

local function onRezRequest()
    if not mod.db.autoAcceptRes then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if AcceptResurrect then AcceptResurrect() end
    if StaticPopup_Hide then
        StaticPopup_Hide("RESURRECT_NO_SICKNESS")
        StaticPopup_Hide("RESURRECT_NO_TIMER")
    end
end

local function onSummonConfirm()
    if not mod.db.autoAcceptSummon then return end
    if ConfirmSummon then ConfirmSummon() end
    if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_SUMMON") end
end

local function onQuestGreeting()
    if not mod.db.autoAcceptQuest then return end
    local n = (GetNumAvailableQuests and GetNumAvailableQuests()) or 0
    for i = 1, n do
        if SelectAvailableQuest then SelectAvailableQuest(i) end
    end
end

local function onQuestDetail()
    if not mod.db.autoAcceptQuest then return end
    if AcceptQuest then AcceptQuest() end
end

local function onQuestAcceptConfirm()
    if not mod.db.autoAcceptQuest then return end
    if AcceptQuest then AcceptQuest() end
end

local function onQuestProgress()
    if not mod.db.autoTurnInQuest then return end
    if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then
        CompleteQuest()
    end
end

local function onQuestComplete()
    if not mod.db.autoTurnInQuest then return end
    if not GetNumQuestChoices or not GetQuestReward then return end
    local choices = GetNumQuestChoices() or 0
    -- 0 = no choice reward (auto-pick), 1 = only one reward, >1 = user must choose
    if choices <= 1 then
        GetQuestReward(choices)
    end
end

local function hasSelfRes()
    if C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions then
        local ok, t = pcall(C_DeathInfo.GetSelfResurrectOptions)
        if ok and type(t) == "table" then return #t > 0 end
    end
    if HasSoulstone then return HasSoulstone() ~= nil end
    return false
end

local function onPlayerDead()
    if not mod.db.autoReleasePvP then return end
    if not IsInInstance then return end
    if hasSelfRes() then return end
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" or instanceType == "arena" then
        if RepopMe then RepopMe() end
    end
end

local function onGossipShow()
    if not mod.db.autoGossip then return end
    if IsShiftKeyDown and IsShiftKeyDown() then return end
    if not C_GossipInfo or not C_GossipInfo.GetOptions then return end
    local active    = (C_GossipInfo.GetNumActiveQuests and C_GossipInfo.GetNumActiveQuests()) or 0
    local available = (C_GossipInfo.GetNumAvailableQuests and C_GossipInfo.GetNumAvailableQuests()) or 0
    if active > 0 or available > 0 then return end
    local opts = C_GossipInfo.GetOptions()
    if type(opts) ~= "table" or #opts ~= 1 then return end
    local opt = opts[1]
    -- Modern API selects by gossipOptionID; older builds by list index
    if type(opt) == "table" and opt.gossipOptionID and C_GossipInfo.SelectOption then
        C_GossipInfo.SelectOption(opt.gossipOptionID)
    elseif C_GossipInfo.SelectOptionByIndex then
        C_GossipInfo.SelectOptionByIndex(1)
    elseif C_GossipInfo.SelectOption then
        C_GossipInfo.SelectOption(1)
    end
end

-- Faster auto-loot: only acts when auto-loot applies (CVar XOR modifier key), so manual looting is untouched.
local _lastFastLoot = 0
local function onLootReady()
    if not mod.db.fasterLoot then return end
    local now = GetTime() or 0
    if (now - _lastFastLoot) < 0.3 then return end  -- LOOT_READY can fire repeatedly
    _lastFastLoot = now
    local cvarAuto  = GetCVarBool and GetCVarBool("autoLootDefault") and true or false
    local modifier  = IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") and true or false
    if cvarAuto == modifier then return end
    if not GetNumLootItems or not LootSlot then return end
    for i = GetNumLootItems(), 1, -1 do
        LootSlot(i)
    end
end

local CAMERA_CVAR    = "cameraDistanceMaxZoomFactor"
local CAMERA_MAX     = 3.4
local CAMERA_DEFAULT = 1.9

-- Only ever write while the option is on, and hand the player's own value back
-- when it goes off. The else branch used to write 1.9, so merely leaving the
-- toggle alone reset a distance the player had deliberately raised - and it
-- fought the Max Camera Distance slider under General, which drives this very
-- CVar and lost the argument on every login.
local function applyMaxCameraZoom()
    if not SetCVar then return end
    if mod.db.maxCameraZoom then
        if mod.db.cameraZoomPrev == nil then
            local cur = tonumber(GetCVar and GetCVar(CAMERA_CVAR))
            -- Anyone upgrading had the option on already, so the CVar is sitting
            -- at our own maximum. Storing that as "theirs" would make it theirs
            -- forever; fall back to the client default instead.
            if cur and cur ~= CAMERA_MAX then mod.db.cameraZoomPrev = cur end
        end
        pcall(SetCVar, CAMERA_CVAR, CAMERA_MAX)
    elseif mod.db.cameraZoomPrev ~= nil then
        pcall(SetCVar, CAMERA_CVAR, mod.db.cameraZoomPrev)
        mod.db.cameraZoomPrev = nil
    end
end

local function applyHideErrors()
    if not UIErrorsFrame then return end
    if mod.db.hideErrors then
        UIErrorsFrame:UnregisterAllEvents()
        UIErrorsFrame:Hide()
    else
        UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
        UIErrorsFrame:RegisterEvent("UI_INFO_MESSAGE")
        UIErrorsFrame:Show()
    end
end

local function applyHideZoneText()
    local zt = _G.ZoneTextFrame
    local szt = _G.SubZoneTextFrame
    if mod.db.hideZoneText then
        if zt  then zt:UnregisterAllEvents();  zt:Hide()  end
        if szt then szt:UnregisterAllEvents(); szt:Hide() end
    else
        -- Never :Show() directly - FadingFrame OnUpdate errors with nil startTime unless shown via FadingFrame_Show().
        if zt then
            zt:RegisterEvent("ZONE_CHANGED")
            zt:RegisterEvent("ZONE_CHANGED_NEW_AREA")
            zt:RegisterEvent("ZONE_CHANGED_INDOORS")
        end
        if szt then
            szt:RegisterEvent("ZONE_CHANGED")
            szt:RegisterEvent("ZONE_CHANGED_INDOORS")
        end
    end
end

local function applyHidePortraitNumbers()
    local frames = { _G.PlayerLevelText, _G.TargetFrameTextureFrameLevelText, _G.PetLevelText }
    for _, f in ipairs(frames) do
        if f then
            if mod.db.hidePortraitNumbers then f:Hide() else f:Show() end
        end
    end
end

-- Blizzard's combat-feedback animation rescales the font (blurry); freeze SetFont/SetTextHeight at a fixed size.
local function applyHitNumberFont(fs, on, size)
    if not fs then return end
    if on then
        if not fs._vcOrigSetFont then
            fs._vcOrigSetFont       = fs.SetFont
            fs._vcOrigSetTextHeight = fs.SetTextHeight
        end
        pcall(fs._vcOrigSetFont, fs, "Fonts\\FRIZQT__.TTF", size, "THICKOUTLINE")
        fs.SetFont       = function() end
        fs.SetTextHeight = function() end
    elseif fs._vcOrigSetFont then
        fs.SetFont       = fs._vcOrigSetFont
        fs.SetTextHeight = fs._vcOrigSetTextHeight
    end
end

local function applyCrispHitNumbers()
    local on   = mod.db.crispHitNumbers
    local size = mod.db.hitNumberSize or 22
    applyHitNumberFont(_G.PlayerHitIndicator, on, size)
    applyHitNumberFont(_G.PetHitIndicator,    on, size)
end

local BUTTON_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton", "BonusActionButton",
    "PetActionButton", "StanceButton",
}

local function forEachActionButton(fn)
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b then fn(b) end
        end
    end
end

local function applyHideKeybindText()
    forEachActionButton(function(b)
        if b.HotKey then
            if mod.db.hideKeybindText then b.HotKey:Hide() else b.HotKey:Show() end
        end
    end)
end

local function applyHideMacroText()
    forEachActionButton(function(b)
        if b.Name then
            if mod.db.hideMacroText then b.Name:Hide() else b.Name:Show() end
        end
    end)
end

local function applyHideStackCount()
    forEachActionButton(function(b)
        if b.Count then
            if mod.db.hideStackCount then b.Count:Hide() else b.Count:Show() end
        end
    end)
end

-- CompactRaidGroup* are secure: Hide/Show taints the compact-frame layout, so use SetAlpha and never touch them in combat.
local function applyHideRaidGroupLabels()
    if InCombatLockdown() then return end
    local hide = mod.db.hideRaidGroupLabels and true or false
    for i = 1, 8 do
        local g = _G["CompactRaidGroup" .. i]
        local title = g and g.title
        if title then
            if hide then
                title:SetAlpha(0)
                g._vcuiLabelHidden = true
            elseif g._vcuiLabelHidden then
                title:SetAlpha(1)
                g._vcuiLabelHidden = nil
            end
        end
    end
end

local function setFontSize(fontObject, size)
    if not fontObject or not fontObject.GetFont then return end
    if not size or size <= 0 then return end
    local ok, file, _, flags = pcall(fontObject.GetFont, fontObject)
    if not ok or not file then return end
    pcall(fontObject.SetFont, fontObject, file, size, flags or "")
end

local function applyMailTextSize()
    setFontSize(_G.OpenMailBodyText,    mod.db.mailTextSize)
    setFontSize(_G.SendMailBodyEditBox, mod.db.mailTextSize)
end

local function applyQuestTextSize()
    setFontSize(_G.QuestFont,            mod.db.questTextSize)
    setFontSize(_G.QuestFontNormalSmall, mod.db.questTextSize - 2)
    setFontSize(_G.QuestTitleFont,       mod.db.questTextSize + 2)
end

local function applyBookTextSize()
    setFontSize(_G.ItemTextFontNormal, mod.db.bookTextSize)
end

local function applyAllVisibility()
    applyHideErrors()
    applyHideZoneText()
    applyHidePortraitNumbers()
    applyCrispHitNumbers()
    applyHideKeybindText()
    applyHideMacroText()
    applyHideStackCount()
    applyHideRaidGroupLabels()
    applyMailTextSize()
    applyQuestTextSize()
    applyBookTextSize()
    applyMaxCameraZoom()
end

-- Flight timer: taxi duration bar; visibility is tied to UnitOnTaxi.
local FT_FONT = "Fonts\\FRIZQT__.TTF"
local ftBar
local ftFlight
local ftThrottle = 0

local function ftDB() return mod.db.flight end

local function ftFmt(s)
    s = math.max(0, math.floor(s + 0.5))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function ftRouteKey(src, dst)
    return (src or "?") .. " @ " .. (dst or "?")
end

-- English node names harvested from the shipped DB, to pick the node (not the zone) out of a multi-part name.
local ftNodeSet
local function ftEnglishNodes()
    if ftNodeSet then return ftNodeSet end
    ftNodeSet = {}
    local db = ns.FLIGHT_TIMES
    if db then
        for _, routes in pairs(db) do
            for src, dsts in pairs(routes) do
                ftNodeSet[src] = src
                for dst in pairs(dsts) do ftNodeSet[dst] = dst end
            end
        end
    end
    return ftNodeSet
end

-- Resolve a raw taxi name: the client formats the current node as "Zone, Node, Faction" but a destination as "Node, Zone", so every segment is tested.
local function ftResolve(raw)
    if not raw then return "?", nil end
    local de = ns.FLIGHT_NODE_DE or {}
    local en = ftEnglishNodes()
    local segs = {}
    for s in (raw .. ","):gmatch("%s*(.-)%s*,") do
        if s ~= "" then segs[#segs + 1] = s end
    end
    for _, s in ipairs(segs) do
        if de[s] then return s, de[s] end
        if en[s] then return s, en[s] end
    end
    for _, s in ipairs(segs) do
        local l = s:lower()
        for k, v in pairs(de) do if k:lower() == l then return s, v end end
        for k, v in pairs(en) do if k:lower() == l then return s, v end end
    end
    return segs[1] or raw, nil
end

local function ftShort(name)
    local s = (ftResolve(name))
    if s and s ~= "" then s = (s:gsub("^%a", string.upper)) end
    return s
end

-- Default duration from the shipped route database (FlightTimesDB.lua).
local function ftDefaultTime(src, dst)
    local db = ns.FLIGHT_TIMES
    if not db then return nil end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local routes = faction and db[faction]
    if not routes then return nil end
    local _, s = ftResolve(src)
    local _, d = ftResolve(dst)
    return s and d and routes[s] and routes[s][d] or nil
end

local FT_INSET = 4

local function ftSetFill(frac)
    frac = math.max(0, math.min(1, frac or 0))
    local w = (ftDB().barWidth - FT_INSET * 2) * frac
    if w < 1 then
        ftBar.fill:Hide()
        ftBar.spark:Hide()
    else
        ftBar.fill:SetWidth(w)
        ftBar.fill:Show()
        if frac > 0.02 and frac < 0.98 then
            ftBar.spark:Show()
        else
            ftBar.spark:Hide()
        end
    end
end

local function ftBuildBar()
    if ftBar then return ftBar end
    local d = ftDB()

    ftBar = CreateFrame("Frame", "VCUI_FlightTimer", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")
    ftBar:SetSize(d.barWidth, d.barHeight)
    ftBar:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
    ftBar:SetFrameStrata("MEDIUM")
    ftBar:Hide()

    if ftBar.SetBackdrop then
        ftBar:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        ftBar:SetBackdropColor(0.04, 0.04, 0.10, 0.85)
        ftBar:SetBackdropBorderColor(0.85, 0.85, 0.90, 1)
    end

    ftBar.fill = ftBar:CreateTexture(nil, "ARTWORK")
    ftBar.fill:SetPoint("TOPLEFT", ftBar, "TOPLEFT", FT_INSET, -FT_INSET)
    ftBar.fill:SetPoint("BOTTOMLEFT", ftBar, "BOTTOMLEFT", FT_INSET, FT_INSET)
    ftBar.fill:SetTexture("Interface\\AddOns\\VuloClassicUI\\Media\\textures\\glass.tga")
    ftBar.fill:SetVertexColor(0.35, 0.50, 0.80, 0.95)
    ftBar.fill:Hide()

    ftBar.spark = ftBar:CreateTexture(nil, "OVERLAY")
    ftBar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    ftBar.spark:SetBlendMode("ADD")
    ftBar.spark:SetSize(14, d.barHeight + 8)
    ftBar.spark:SetPoint("CENTER", ftBar.fill, "RIGHT", 0, 0)
    ftBar.spark:Hide()

    ftBar.label = ftBar:CreateFontString(nil, "OVERLAY")
    ftBar.label:SetFont(FT_FONT, 12, "OUTLINE")
    ftBar.label:SetPoint("LEFT", ftBar, "LEFT", 7, 0)
    ftBar.label:SetPoint("RIGHT", ftBar, "RIGHT", -84, 0)
    ftBar.label:SetJustifyH("LEFT")
    ftBar.label:SetWordWrap(false)

    ftBar.time = ftBar:CreateFontString(nil, "OVERLAY")
    ftBar.time:SetFont(FT_FONT, 12, "OUTLINE")
    ftBar.time:SetPoint("RIGHT", ftBar, "RIGHT", -7, 0)
    ftBar.time:SetJustifyH("RIGHT")

    ftBar.mover = ns:CreateMover(ftBar, {
        key    = "flighttime",
        label  = L["|cffffffffFLIGHT TIME|r"],
        db     = ftDB(),
        width  = 240,
        height = 30,
        onMove = function(x, y)
            ns:Print(string.format(L["Flight timer: x=%.0f, y=%.0f"], x, y))
        end,
        editPreview = function(show)
            if show then ftBar:Show() elseif not ftFlight then ftBar:Hide() end
        end,
    })

    return ftBar
end

local function ftApplySize()
    if not ftBar then return end
    ftBar:SetSize(ftDB().barWidth, ftDB().barHeight)
    ftBar.spark:SetSize(14, ftDB().barHeight + 8)
end

local function ftStop(recordIt)
    if not ftFlight then return end
    local dur = GetTime() - ftFlight.t0
    if recordIt and dur > 5 then
        ftDB().times[ftFlight.key] = math.floor(dur + 0.5)
        if ftDB().chatReport then
            ns:Print(L["Flight: %s (%s)"], ftFmt(dur),
                ftShort(ftFlight.src) .. " > " .. ftShort(ftFlight.dst))
        end
    end
    ftFlight = nil
    ftDB().inFlight = nil
    if ftBar then ftBar:Hide() end
end

local function ftOnUpdate(_, elapsed)
    ftThrottle = ftThrottle + elapsed
    if ftThrottle < 0.1 then return end
    ftThrottle = 0
    if ftDB().unlocked then return end
    if not ftFlight then return end

    local elapsedT = GetTime() - ftFlight.t0

    -- 3s grace for boarding, then leaving the taxi always hides the bar
    if elapsedT > 3 and not UnitOnTaxi("player") then
        ftStop(elapsedT > 5)
        return
    end

    -- the text changes once per second; the 10 Hz tick only moves the fill
    local sec = math.floor(elapsedT)
    if ftFlight.known and ftFlight.known > 0 then
        ftSetFill(elapsedT / ftFlight.known)
        if ftFlight._textSec ~= sec then
            ftFlight._textSec = sec
            ftBar.time:SetText(ftFmt(math.min(elapsedT, ftFlight.known)) .. " / " .. ftFmt(ftFlight.known))
        end
    else
        ftSetFill(0)
        if ftFlight._textSec ~= sec then
            ftFlight._textSec = sec
            ftBar.time:SetText(ftFmt(elapsedT) .. " / ?")
        end
    end
end

local function ftOnTakeTaxi(slot)
    if not mod._enabled or not ftDB().enabled then return end
    if not slot or not TaxiNodeName then return end
    local dst = TaxiNodeName(slot)
    if not dst or dst == "" then return end
    local src
    for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
        if TaxiNodeGetType(i) == "CURRENT" then
            src = TaxiNodeName(i)
            break
        end
    end

    local key = ftRouteKey(src, dst)
    ftFlight = {
        src   = src,
        dst   = dst,
        key   = key,
        t0    = GetTime(),
        known = ftDB().times[key] or ftDefaultTime(src, dst),
    }
    -- persist for /reload mid-flight (epoch-stamped so elapsed keeps running)
    ftDB().inFlight = { src = src, dst = dst, key = key, start = time() }

    if ftDB().debug then
        local s, se = ftResolve(src)
        local d2, de2 = ftResolve(dst)
        local fac = (UnitFactionGroup and UnitFactionGroup("player")) or "?"
        local hit = se and de2 and ns.FLIGHT_TIMES and ns.FLIGHT_TIMES[fac]
            and ns.FLIGHT_TIMES[fac][se] and ns.FLIGHT_TIMES[fac][se][de2]
        ns:Print("Flight debug: src='" .. tostring(src) .. "' -> '" .. s .. "' -> '" .. tostring(se)
            .. "' | dst='" .. tostring(dst) .. "' -> '" .. d2 .. "' -> '" .. tostring(de2)
            .. "' | " .. fac .. " | dbLoaded=" .. tostring(ns.FLIGHT_TIMES ~= nil)
            .. " | db=" .. tostring(hit)
            .. " | learned=" .. tostring(ftDB().times[key]))
    end

    ftBuildBar()
    ftBar.label:SetText(ftShort(dst))
    if ftFlight.known then
        ftBar.time:SetText("0:00 / " .. ftFmt(ftFlight.known))
    else
        ftBar.time:SetText("0:00 / ?")
    end
    ftSetFill(0)
    ftBar:Show()

    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            if ftFlight and ftFlight.key == key and not UnitOnTaxi("player") then
                ftStop(false)
            end
        end)
    end
end

local function ftOnControlGained()
    if ftFlight and not UnitOnTaxi("player") then
        ftStop(true)
    end
end

local function ftOnWorldEnter()
    local saved = ftDB().inFlight
    if not ftFlight and saved then
        if UnitOnTaxi("player") then
            local elapsed = math.max(0, time() - (saved.start or time()))
            ftFlight = {
                src   = saved.src,
                dst   = saved.dst,
                key   = saved.key,
                t0    = GetTime() - elapsed,
                known = ftDB().times[saved.key] or ftDefaultTime(saved.src, saved.dst),
            }
            ftBuildBar()
            ftBar.label:SetText(ftShort(saved.dst))
            ftBar:Show()
        else
            ftDB().inFlight = nil
        end
    end

    if ftFlight and not UnitOnTaxi("player") then
        local dur = GetTime() - ftFlight.t0
        ftStop(dur > 5)
    end
end

local function ftSetUnlocked(state)
    ftDB().unlocked = state
    ftBuildBar()
    if state then
        ftBar.label:SetText(L["Flight Timer"])
        ftBar.time:SetText("1:58 / 5:05")
        ftSetFill(0.4)
        ftBar:Show()
        ftBar.mover:Show()
        ns:Print(L["Flight timer mover active. |cff9b6cffDrag|r or |cff9b6cffarrow keys|r (SHIFT = 5px)."])
    else
        ftBar.mover:Hide()
        if not (ftFlight and UnitOnTaxi("player")) then ftBar:Hide() end
        ns:Print(L["Flight timer mover disabled."])
    end
end

SLASH_VCUIFLUG1 = "/vcuiflug"
SlashCmdList.VCUIFLUG = function()
    local d = mod.db and mod.db.flight
    if not d then return end
    d.debug = not d.debug
    ns:Print(d.debug and L["Flight debug on — take a flight, the resolution appears in the chat."]
        or L["Flight debug off."])
end

local ftTaxiHooked = false
local function ftInit()
    -- /reload does not re-read the .toc, so after an update the route DB file is absent until a full restart.
    if not ns.FLIGHT_TIMES and not ns._flightDBWarned then
        ns._flightDBWarned = true
        ns:Print(L["|cffff8800Flight route database not loaded.|r Fully restart WoW (a /reload is not enough after an update) so the flight times work."])
    end

    -- Migration: the standalone "flighttimer" module was folded into General
    if ns.db and ns.db.profile and ns.db.profile.modules then
        local old = ns.db.profile.modules.flighttimer
        if old then
            local fl = ftDB()
            for k, v in pairs(old) do
                if k ~= "enabled" and fl[k] ~= nil then fl[k] = v end
            end
            ns.db.profile.modules.flighttimer = nil
        end
    end

    ftBuildBar()
    ftBar:SetScript("OnUpdate", ftOnUpdate)
    if not ftTaxiHooked and type(TakeTaxiNode) == "function" then
        ftTaxiHooked = true
        hooksecurefunc("TakeTaxiNode", ftOnTakeTaxi)
    end
end

local function normName(name)
    if not name or name == "" then return nil end
    name = name:match("^([^-]+)") or name
    return name:lower()
end

local trustedNames = {}
local guildRosterLoaded = false
local function rebuildTrusted()
    wipe(trustedNames)
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, (C_FriendList.GetNumFriends() or 0) do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            local nm = info and normName(info.name)
            if nm then trustedNames[nm] = true end
        end
    end
    if IsInGuild and IsInGuild() and GetGuildRosterInfo then
        for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
            local nm = normName(GetGuildRosterInfo(i))
            if nm then trustedNames[nm] = true end
        end
    end
end
-- only scan while the feature is on (GUILD_ROSTER_UPDATE fires a lot)
local function maybeRebuild()
    if mod.db.blockStrangerInvites or mod.db.blockStrangerTrades then rebuildTrusted() end
end
local function onGuildRoster()
    guildRosterLoaded = true
    maybeRebuild()
end

local function isStranger(name)
    local nm = normName(name)
    if not nm then return false end
    -- roster not loaded yet -> fail open so a real guildmate is never declined
    if IsInGuild and IsInGuild() and not guildRosterLoaded then
        if GuildRoster then GuildRoster() end
        return false
    end
    return not trustedNames[nm]
end

local function onPartyInvite(_, name)
    if not mod.db.blockStrangerInvites or not name or name == "" then return end
    if isStranger(name) then
        if DeclineGroup then DeclineGroup() end
        if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
        ns:Print(L["|cffffd200[QoL]|r Blocked group invite from %s (not guild/friend)."], name)
    end
end

-- Trades have no accept popup; the InitiateTrade hook flags player-started trades so they are skipped.
local userInitiatedTrade = false
local function checkTrade()
    if not mod.db.blockStrangerTrades then return end
    if userInitiatedTrade then userInitiatedTrade = false; return end
    local partner = TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText()
    if partner and partner ~= "" and isStranger(partner) then
        if CancelTrade then CancelTrade() end
        ns:Print(L["|cffffd200[QoL]|r Blocked trade from %s (not guild/friend)."], partner)
    end
end
local function onTradeShow()
    if not mod.db.blockStrangerTrades then return end
    ns.NextFrame(checkTrade)
end
local function onTradeClosed() userInitiatedTrade = false end

-- Game menu (Escape): skin + options button. The menu rebuilds its buttons from a pool on every open.
local gameMenuDone = false

local function skinMenuButton(b, bc)
    if not b or b._vcuiSkin then return end
    b._vcuiSkin = true
    b:SetHeight((b:GetHeight() or 26) + 4)
    local fs = b.GetFontString and b:GetFontString()
    for i = 1, select("#", b:GetRegions()) do
        local r = select(i, b:GetRegions())
        if r and r:IsObjectType("Texture") and r ~= fs then r:SetAlpha(0) end
    end
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        local tex = b[key]
        if tex and tex.SetAlpha then
            tex:SetAlpha(0)
            hooksecurefunc(tex, "SetAlpha", function(self, a)
                if a > 0 then self:SetAlpha(0) end
            end)
        end
    end
    local inset = CreateFrame("Frame", nil, b)
    inset:SetPoint("TOPLEFT", 2, -2)
    inset:SetPoint("BOTTOMRIGHT", -2, 2)
    inset:SetFrameLevel(b:GetFrameLevel())
    local bg = inset:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.13, 0.9)
    for i = 1, 4 do
        local t = inset:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(bc.r, bc.g, bc.b, 1)
        if i == 1 then t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(1)
        elseif i == 2 then t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(1)
        elseif i == 3 then t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(1)
        else t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(1) end
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(inset)
    hl:SetColorTexture(1, 1, 1, 0.08)
    if fs and ns.UI and ns.UI.FONT_PATH then
        local _, size, flags = fs:GetFont()
        fs:SetFont(ns.UI.FONT_PATH, (size or 14) - 2, flags or "")
    end
end

local function setupGameMenu()
    if gameMenuDone or not GameMenuFrame then return end
    if not (mod.db.skinGameMenu or mod.db.gameMenuButton) then return end
    gameMenuDone = true

    local UIW = ns.UI
    local ac = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }
    local bc = ns.COLORS and (ns.COLORS.borderDark or ns.COLORS.border) or { r = 0.15, g = 0.15, b = 0.18 }

    if mod.db.skinGameMenu then
        for i = 1, select("#", GameMenuFrame:GetRegions()) do
            local r = select(i, GameMenuFrame:GetRegions())
            if r and r:IsObjectType("Texture") then r:SetAlpha(0) end
        end
        if GameMenuFrame.NineSlice then GameMenuFrame.NineSlice:SetAlpha(0) end
        if GameMenuFrame.Border then GameMenuFrame.Border:SetAlpha(0) end
        local header = GameMenuFrame.Header
        if header then
            for i = 1, select("#", header:GetRegions()) do
                local r = select(i, header:GetRegions())
                if r and r:IsObjectType("Texture") then r:SetAlpha(0) end
            end
            local ht = header.Text or (header.GetRegions and select(1, header:GetRegions()))
            if ht and ht.SetTextColor then
                ht:SetTextColor(ac.r, ac.g, ac.b, 1)
                if UIW and UIW.Font then UIW.Font(ht, 14) end
            end
            header:ClearAllPoints()
            header:SetPoint("TOP", GameMenuFrame, "TOP", 0, -10)
            if header.EnableMouse then header:EnableMouse(false) end
        end
        if UIW and UIW.StyleBackdrop then
            UIW:StyleBackdrop(GameMenuFrame, { bg = ns.COLORS and ns.COLORS.bg, border = bc })
        end
        if UIW and UIW.CreateShadow then UIW:CreateShadow(GameMenuFrame) end
        local strip = GameMenuFrame:CreateTexture(nil, "ARTWORK")
        strip:SetPoint("TOPLEFT", GameMenuFrame, "TOPLEFT", 0, 0)
        strip:SetPoint("TOPRIGHT", GameMenuFrame, "TOPRIGHT", 0, 0)
        strip:SetHeight(2)
        if UIW and UIW.SetGradient then
            UIW.SetGradient(strip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)
        end
        if GameMenuFrame.InitButtons then
            hooksecurefunc(GameMenuFrame, "InitButtons", function(menu)
                if not menu.buttonPool then return end
                for menuBtn in menu.buttonPool:EnumerateActive() do
                    skinMenuButton(menuBtn, bc)
                end
            end)
        end
    end

    if mod.db.gameMenuButton and GameMenuFrame.Layout then
        local btn = CreateFrame("Button", "VCUI_GameMenuButton", GameMenuFrame, "MainMenuFrameButtonTemplate")
        btn:SetSize(200, 35)
        btn:SetScript("OnClick", function()
            if InCombatLockdown() then
                ns:Print(L["Not possible in combat."])
                return
            end
            HideUIPanel(GameMenuFrame)
            if ns.UI and ns.UI.ToggleMainFrame then ns.UI:ToggleMainFrame() end
        end)
        if mod.db.skinGameMenu then skinMenuButton(btn, bc) end

        local baseHeight
        hooksecurefunc(GameMenuFrame, "Layout", function()
            if InCombatLockdown() then btn:Hide(); return end
            if not (mod.active and mod.db.gameMenuButton) then btn:Hide(); return end
            if not GameMenuFrame.buttonPool then btn:Hide(); return end

            local anchor
            for menuBtn in GameMenuFrame.buttonPool:EnumerateActive() do
                local text = menuBtn:GetText()
                if text == BLIZZARD_STORE then anchor = menuBtn; break
                elseif text == GAMEMENU_OPTIONS then anchor = menuBtn end
            end
            if not anchor then btn:Hide(); return end

            local w, h = anchor:GetWidth(), anchor:GetHeight()
            if w and w > 0 then btn:SetSize(w, h or 35) end
            btn:Show()
            local hex = string.format("|cff%02x%02x%02x", ac.r * 255, ac.g * 255, ac.b * 255)
            btn:SetText(hex .. "Vulo|r|cffffffffClassicUI|r")
            if ns.UI and ns.UI.FONT_PATH then
                local fs = btn:GetFontString()
                if fs then fs:SetFont(ns.UI.FONT_PATH, 13, "") end
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOP", anchor, "BOTTOM", 0, -12)

            local extraH = 40
            local anchorBottom = anchor:GetBottom()
            if anchorBottom then
                for menuBtn in GameMenuFrame.buttonPool:EnumerateActive() do
                    local top = menuBtn:GetTop()
                    if top and top < anchorBottom + 2 then
                        local p, rel, rp, x, y = menuBtn:GetPoint(1)
                        if p then
                            menuBtn:ClearAllPoints()
                            menuBtn:SetPoint(p, rel, rp, x, (y or 0) - extraH)
                        end
                    end
                end
            end
            if not baseHeight then baseHeight = GameMenuFrame:GetHeight() end
            GameMenuFrame:SetHeight(baseHeight + extraH)
        end)
    end
end

local function onPlayerLogin()
    applyAllVisibility()
    setupGameMenu()
end

function mod:OnEnable()
    -- The flight timer keeps its own unlock flag. setUnlocked is the only thing
    -- that shows the mover and it does not run on load, so a saved unlock would
    -- pin the frame on screen with no way to get hold of it.
    if mod.db and mod.db.flight then mod.db.flight.unlocked = false end
    mod:RegisterEvent("MERCHANT_SHOW",         onMerchantShow)
    mod:RegisterEvent("RESURRECT_REQUEST",     onRezRequest)
    mod:RegisterEvent("CONFIRM_SUMMON",        onSummonConfirm)
    mod:RegisterEvent("QUEST_GREETING",        onQuestGreeting)
    mod:RegisterEvent("QUEST_DETAIL",          onQuestDetail)
    mod:RegisterEvent("QUEST_ACCEPT_CONFIRM",  onQuestAcceptConfirm)
    mod:RegisterEvent("QUEST_PROGRESS",        onQuestProgress)
    mod:RegisterEvent("QUEST_COMPLETE",        onQuestComplete)
    mod:RegisterEvent("PLAYER_DEAD",           onPlayerDead)
    mod:RegisterEvent("GOSSIP_SHOW",           onGossipShow)
    mod:RegisterEvent("LOOT_READY",            onLootReady)
    mod:RegisterEvent("PLAYER_LOGIN",          onPlayerLogin)
    mod:RegisterEvent("PLAYER_CONTROL_GAINED", ftOnControlGained)
    mod:RegisterEvent("PLAYER_ENTERING_WORLD", ftOnWorldEnter)
    mod:RegisterEvent("PARTY_INVITE_REQUEST",  onPartyInvite)
    mod:RegisterEvent("TRADE_SHOW",            onTradeShow)
    mod:RegisterEvent("TRADE_CLOSED",          onTradeClosed)
    mod:RegisterEvent("FRIENDLIST_UPDATE",     maybeRebuild)
    mod:RegisterEvent("GUILD_ROSTER_UPDATE",   onGuildRoster)
    if InitiateTrade and not mod._tradeHooked then
        mod._tradeHooked = true
        hooksecurefunc("InitiateTrade", function() userInitiatedTrade = true end)
    end
    if GuildRoster then GuildRoster() end
    rebuildTrusted()
    ftInit()

    if ns.isInitialised then
        applyAllVisibility()
        setupGameMenu()
    elseif C_Timer and C_Timer.After then
        C_Timer.After(1, applyAllVisibility)
    end

    -- deferred in case the frame is not there yet; skin AFTER the button so it is dressed and re-anchored too
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            setupStackSplitMaxButton()
            setupStackSplitSkin()
        end)
    else
        setupStackSplitMaxButton()
        setupStackSplitSkin()
    end
end

function mod:OnDisable()
    ftFlight = nil
    if ftBar then
        if ftBar.mover then ftBar.mover:Hide() end
        ftBar:Hide()
    end
    if mod.db.maxCameraZoom and SetCVar then
        -- give back what we took, not what we guess the default is
        pcall(SetCVar, CAMERA_CVAR, mod.db.cameraZoomPrev or CAMERA_DEFAULT)
        mod.db.cameraZoomPrev = nil
    end
end

-- Macro Factory: builds per-character macros; potion IDs are best tier first.
local POTION_IDS = { 22829, 13446, 3928, 1710, 929, 118 }
local function potionBody()
    for _, id in ipairs(POTION_IDS) do
        if (GetItemCount and GetItemCount(id) or 0) > 0 then
            local n = GetItemInfo(id)
            if n then return "#showtooltip\n/use " .. n end
        end
    end
    return nil
end

local MACRO_DEFS
ns.OnLocaleReady(function()
MACRO_DEFS = {
    { name = "VCUI Trinket1", icon = "Interface\\Icons\\INV_Jewelry_Necklace_07",
      label = L["Trinket 1"], body = "#showtooltip 13\n/use 13" },
    { name = "VCUI Trinket2", icon = "Interface\\Icons\\INV_Jewelry_Necklace_11",
      label = L["Trinket 2"], body = "#showtooltip 14\n/use 14" },
    { name = "VCUI Trinkets", icon = "Interface\\Icons\\INV_Jewelry_Necklace_24",
      label = L["Both trinkets"], body = "#showtooltip 13\n/use 13\n/use 14" },
    { name = "VCUI Focus", icon = "Interface\\Icons\\Ability_Hunter_MasterMarksman",
      label = L["Set focus"], body = "/focus" },
    { name = "VCUI Potion", icon = "Interface\\Icons\\INV_Potion_54",
      label = L["Healing potion"], body = potionBody },
}
end)

local function makeMacro(def)
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Macro Factory: can't create macros in combat."]); return
    end
    local body = (type(def.body) == "function") and def.body() or def.body
    if not body or body == "" then
        ns:Print(L["Macro Factory: nothing to build (e.g. no healing potion in your bags)."]); return
    end
    local existing = GetMacroIndexByName and GetMacroIndexByName(def.name) or 0
    if existing and existing > 0 then
        EditMacro(existing, def.name, def.icon, body)
        ns:Print(L["Macro '%s' updated — drag it from |cffffffff/macro|r onto your action bar."], def.name)
    elseif CreateMacro then
        local ok = pcall(CreateMacro, def.name, def.icon, body, true)
        if ok then
            ns:Print(L["Macro '%s' created — open |cffffffff/macro|r and drag it onto your action bar."], def.name)
        else
            ns:Print(L["Macro Factory: couldn't create it (character macro slots full?)."])
        end
    end
end

function mod:GetOptions()
    local function tgl(key, label, tooltip, applyFn)
        return {
            type = "toggle", label = label, tooltip = tooltip,
            get = function() return mod.db[key] end,
            set = function(_, v)
                mod.db[key] = v
                if applyFn then applyFn() end
            end,
        }
    end

    local macroItems = {
        { type = "desc",
          text = L["|cffaaaaaaOne click builds a ready-made macro (per character). Then open |cffffffff/macro|r and drag it onto your action bar. Works on any client — uses item slots / IDs, no English needed.|r"] },
    }
    do
        local row = {}
        for i, def in ipairs(MACRO_DEFS) do
            row[#row + 1] = { type = "button", label = def.label, width = 130,
                onClick = function() makeMacro(def) end }
            if #row == 3 or i == #MACRO_DEFS then
                macroItems[#macroItems + 1] = { type = "group", layout = "row", gap = 6, items = row }
                row = {}
            end
        end
    end

    return {
        { type = "header", text = L["General - Auto Actions"] },
        { type = "desc",
          text = L["|cffaaaaaaSimple on/off switches for common QoL actions. Take effect immediately, no /reload needed.|r"] },

        { type = "spacer", height = 6 },
        { type = "section", title = L["Macro Factory"], items = macroItems },

        { type = "header", text = L["Character"] },
        tgl("autoAcceptQuest",   L["Auto-accept quests"],
            L["Automatically accepts quests when clicking an NPC."]),
        tgl("autoTurnInQuest",   L["Auto-turn in quests"],
            L["Automatically completes finished quests. Waits for user choice on multi-reward quests (no auto-pick)."]),
        tgl("autoAcceptRes",     L["Auto-accept resurrect"],
            L["Automatically clicks 'Accept' on resurrect popups (not in combat)."]),
        tgl("autoAcceptSummon",  L["Auto-accept summon"],
            L["Automatically clicks 'Accept' on warlock/stone summon popups."]),
        tgl("autoReleasePvP",    L["Auto-release spirit in PvP/Arena"],
            L["Releases instantly on death in BG or arena."]),

        { type = "spacer", height = 6 },
        { type = "header", text = L["World"] },
        tgl("autoGossip",        L["Auto-select single gossip option"],
            L["Skips NPC dialog windows that only have a single option. Hold SHIFT to temporarily bypass."]),
        tgl("fasterLoot",        L["Faster auto-loot"],
            L["Loots all items at once when auto-loot applies, instead of one by one."]),
        tgl("maxCameraZoom",     L["Max camera zoom"],
            L["Raises the maximum camera zoom-out distance far beyond the default."],
            applyMaxCameraZoom),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Protection"] },
        tgl("blockStrangerInvites", L["Block group invites from strangers"],
            L["Auto-declines party/raid invites from players who are not in your guild or on your friends list."],
            maybeRebuild),
        tgl("blockStrangerTrades",  L["Block trades from strangers"],
            L["Auto-closes trade windows opened by players who are not in your guild or on your friends list. Trades you start yourself are not affected."],
            maybeRebuild),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Vendor"] },
        tgl("autoSellJunk",      L["Auto-sell junk (grey)"],
            L["Sells all grey items when opening a vendor. Earnings shown in chat."]),
        tgl("autoRepair",        L["Auto-repair"],
            L["Repairs entire equipment at the vendor if gold is sufficient."]),
        tgl("maxStackButton",    L["Stack-split popup: MAX button"],
            L["Adds a 'MAX' button to the quantity popup. Click = buy full stack (at vendor) or split completely (for bag items)."],
            applyMaxStackButton),
        tgl("skinStackSplit",    L["Stack-split popup: VuloUI look"],
            L["Restyles the quantity popup (stack buying/splitting) to match the addon look: dark panel, clean buttons and arrows. Turning this off needs a /reload."],
            function()
                if mod.db.skinStackSplit ~= false then setupStackSplitSkin() end
            end),

        { type = "header", text = L["Game Menu"] },
        tgl("skinGameMenu",      L["Game menu: VuloUI look"],
            L["Restyles the Escape menu to match the addon look: dark panel, flat buttons, accent title. Changing this needs a /reload."],
            setupGameMenu),
        tgl("gameMenuButton",    L["Game menu: VuloClassicUI button"],
            L["Adds a VuloClassicUI button to the Escape menu that opens the options window. Turning this off needs a /reload."],
            setupGameMenu),

        { type = "spacer", height = 6 },
        { type = "section", title = L["Flight Timer"], items = {
            { type = "toggle", label = L["Show flight time bar"],
              tooltip = L["Shows destination and remaining time while on a taxi. The first flight of a route is learned, then you get a draining countdown."],
              get = function() return mod.db.flight.enabled end,
              set = function(_, v)
                  mod.db.flight.enabled = v
                  if not v then ftStop(false) end
              end },
            { type = "toggle", label = L["Print flight time to chat"],
              tooltip = L["After landing, prints the measured flight time."],
              get = function() return mod.db.flight.chatReport end,
              set = function(_, v) mod.db.flight.chatReport = v end },
            { type = "slider", label = L["Bar width"],
              min = 140, max = 400, step = 5,
              get = function() return mod.db.flight.barWidth end,
              set = function(_, v) mod.db.flight.barWidth = v; ftApplySize() end },
            { type = "slider", label = L["Bar height"],
              min = 12, max = 30, step = 1,
              get = function() return mod.db.flight.barHeight end,
              set = function(_, v) mod.db.flight.barHeight = v; ftApplySize() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "button", label = L["Unlock / Position"], width = 200,
                  onClick = function() ftSetUnlocked(not mod.db.flight.unlocked) end },
                { type = "button", label = L["Reset learned times"], width = 200,
                  tooltip = L["Deletes all saved route durations."],
                  onClick = function()
                      mod.db.flight.times = {}
                      ns:Print(L["Learned flight times reset."])
                  end },
            } },
        } },

        { type = "section", title = L["Visibility"], items = {
            tgl("hideErrors",        L["Hide UI error messages"],
                L["Hides the red error messages in the screen center."],
                applyHideErrors),
            tgl("hideZoneText",      L["Hide zone text"],
                L["Hides the large zone name when entering new areas."],
                applyHideZoneText),
            tgl("hidePortraitNumbers", L["Hide level numbers on portrait"],
                L["Hides the level display on the Player/Target/Pet portrait."],
                applyHidePortraitNumbers),
            tgl("crispHitNumbers", L["Crisp portrait hit numbers"],
                L["Renders the damage/heal numbers that flash on the Player/Pet portrait with a fixed, sharp font instead of Blizzard's blurry growing animation."],
                applyCrispHitNumbers),
            { type = "slider", label = L["Hit number size"],
              min = 14, max = 36, step = 1,
              tooltip = L["Font size of the portrait hit numbers (when 'Crisp' is on)."],
              get = function() return mod.db.hitNumberSize end,
              set = function(_, v) mod.db.hitNumberSize = v; applyCrispHitNumbers() end },
            tgl("hideKeybindText",   L["Hide keybind text on action buttons"],
                L["Hides the small key labels (1, F1, etc.) on the action buttons."],
                applyHideKeybindText),
            tgl("hideMacroText",     L["Hide macro/spell names on action buttons"],
                L["Hides the text labels under the action buttons."],
                applyHideMacroText),
            tgl("hideStackCount",    L["Hide stack/charge numbers on action buttons"],
                L["Hides the small boxes with numbers at the top right (item stacks, charges, cooldown seconds for long CDs)."],
                applyHideStackCount),
            tgl("hideRaidGroupLabels", L["Hide raid group labels"],
                L["Hides the 'Group 1'/'Group 2' labels above the compact raid frames."],
                applyHideRaidGroupLabels),
        } },

        { type = "section", title = L["Text Sizes"], items = {
            { type = "slider", label = L["Mail Text Size"],
              min = 8, max = 20, step = 1,
              tooltip = L["Font size in mail body (opened + sent mail)."],
              get = function() return mod.db.mailTextSize end,
              set = function(_, v) mod.db.mailTextSize = v; applyMailTextSize() end },
            { type = "slider", label = L["Quest Text Size"],
              min = 8, max = 22, step = 1,
              tooltip = L["Font size in quest descriptions + quest log."],
              get = function() return mod.db.questTextSize end,
              set = function(_, v) mod.db.questTextSize = v; applyQuestTextSize() end },
            { type = "slider", label = L["Book Text Size"],
              min = 8, max = 20, step = 1,
              tooltip = L["Font size in readable books and letters from item text."],
              get = function() return mod.db.bookTextSize end,
              set = function(_, v) mod.db.bookTextSize = v; applyBookTextSize() end },
        } },
    }
end
