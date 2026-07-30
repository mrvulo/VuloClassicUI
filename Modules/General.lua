-- VuloClassicUI / Modules / General
-- The "General" collection in one file (30.07.2026): the former Extras,
-- Character and Bugfixes members as IIFE capsules, then their collection
-- pages, then the sidebar container. Each capsule keeps its file-level
-- locals and early returns isolated.

(function(...)
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

ns:RegisterSlash({ key = "FLIGHTTIMER", commands = { "/vcuiflug" },
    desc = "Show how long the flight paths you have taken lasted.",
    module = "miscqol",
})
ns.Slash.FLIGHTTIMER = function()
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
end)(...);

(function(...)
-- One-key fishing: one key casts, reels and lures via secure override bindings.
local _, ns = ...

local mod = ns:RegisterModule("vulfishing", {
    name        = "Fishing",
    group       = "Extras",
    -- Two columns, and a row without a partner keeps its half: the third
    -- extra-item slot used to stretch across the page with its box flung to
    -- the far right edge.
    optionsGrid = true,
    description = "One-key fishing: one key casts, reels and applies a lure, and auto-loots your catch.",
    defaults = {
        enabled      = true,
        key          = "",
        lure         = true,
        autoLoot     = true,
        softInteract = true,
        equipPole    = false,
        quietErrors  = true,
        soundBoost   = false,
        soundBG      = false,
        soundLevel   = 100,
        extra        = {},
    },
})

local pairs, ipairs, wipe = pairs, ipairs, wipe

local L = ns.L

local FISHING_POLES = {
    [6256] = true, [6365] = true, [6366] = true, [6367] = true, [12225] = true,
    [19022] = true, [19970] = true, [25978] = true,
}
local FISHING_SPELLS = {
    [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true,
}
-- Ordered best to worst by fishing bonus.
local LURES = { 6533, 6532, 7307, 6811, 6530, 6529 }
local LURE_ENCHANTS = { [263] = true, [264] = true, [265] = true, [266] = true, [3868] = true, [4225] = true }
local FISHING_NAME = PROFESSIONS_FISHING or (GetSpellInfo and GetSpellInfo(7620)) or "Fishing"

local FISH_CVARS = { SoftTargetInteract = "3", SoftTargetInteractRange = "15", SoftTargetInteractRangeIsHard = "0" }
local SOUND_DIM = { Sound_MusicVolume = "0", Sound_AmbienceVolume = "0" }

local owner = CreateFrame("Frame", "VulFishOwner", UIParent)
local macroBtn = CreateFrame("Button", "VulFishMacroButton", UIParent, "SecureActionButtonTemplate")
macroBtn:SetAttribute("type", "macro")
macroBtn:RegisterForClicks("AnyUp", "AnyDown")

local midFishing = false

local function isFishingSpell(spellID)
    if FISHING_SPELLS[spellID] then return true end
    local n = spellID and GetSpellInfo(spellID)
    return n ~= nil and n == FISHING_NAME
end

local function poleEquipped()
    local id = GetInventoryItemID("player", 16)
    return id ~= nil and FISHING_POLES[id] == true
end

local function poleInBags()
    for bag = 0, 4 do
        local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local id = GetContainerItemID and GetContainerItemID(bag, slot)
            if id and FISHING_POLES[id] then
                local name = GetItemInfo(id)
                if name then return name end
            end
        end
    end
end

local function hasLure()
    local has, _, _, enchID = GetWeaponEnchantInfo()
    if not has then return false end
    if enchID == nil then return true end   -- enchant id unreadable on some clients: assume it is a lure
    return LURE_ENCHANTS[enchID] == true
end

local function bestOwnedLure()
    for _, id in ipairs(LURES) do
        if (GetItemCount and GetItemCount(id) or 0) > 0 then
            local name = GetItemInfo(id)
            if name then return name end
        end
    end
end

local cvarCache, cvarsActive = {}, false

-- Soft-target CVars are protected in combat (SetCVar throws ADDON_ACTION_BLOCKED),
-- so apply/restore is deferred to PLAYER_REGEN_ENABLED; wantCVars is the target state.
local cvarDefer = CreateFrame("Frame")
cvarDefer:Hide()
local wantCVars = false

local function applyCVar(k, v)
    local cur = GetCVar(k)
    if cur == nil then return end   -- CVar absent on this client version; never SetCVar an unknown name
    if cvarCache[k] == nil then cvarCache[k] = cur end
    SetCVar(k, v)
end
local function doSetFishCVars()
    if cvarsActive then return end
    cvarsActive = true
    wipe(cvarCache)
    if mod.db.softInteract then for k, v in pairs(FISH_CVARS) do applyCVar(k, v) end end
    if mod.db.autoLoot then applyCVar("autoLootDefault", "1") end
    if mod.db.soundBoost then
        local lvl = math.max(0, math.min(100, mod.db.soundLevel or 100)) / 100
        applyCVar("Sound_MasterVolume", tostring(lvl))
        applyCVar("Sound_SFXVolume", tostring(lvl))
        for k, v in pairs(SOUND_DIM) do applyCVar(k, v) end
    end
    if mod.db.soundBG then applyCVar("Sound_EnableSoundWhenGameIsInBG", "1") end
end
local function doRestoreFishCVars()
    if not cvarsActive then return end
    cvarsActive = false
    for k, v in pairs(cvarCache) do if v ~= nil then SetCVar(k, v) end end
    wipe(cvarCache)
end
cvarDefer:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if wantCVars then doSetFishCVars() else doRestoreFishCVars() end
end)
local function setFishCVars()
    wantCVars = true
    if InCombatLockdown() then cvarDefer:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    doSetFishCVars()
end
local function restoreFishCVars()
    wantCVars = false
    if InCombatLockdown() then cvarDefer:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    doRestoreFishCVars()
end

local NUM_EXTRA = 3
local resolved = {}

local function playerHasBuff(name)
    if not name then return false end
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then return false end
        if n == name then return true end
    end
    return false
end

local function resolveExtra(str)
    if not str or str == "" then return nil end
    str = strtrim(str)
    if str == "" then return nil end
    if str:sub(1, 1) == "/" then
        local r = { kind = "macro", body = str, hasCond = str:find("%[") ~= nil }
        local sp = str:match("/cast%s+([^\n;]+)") or str:match("/use%s+([^\n;]+)")
        if sp then sp = strtrim((sp:gsub("%[.-%]", ""))); if sp == "" then sp = nil end end
        r.spell = sp
        return r
    end
    local itemID = tonumber(str)
    if not itemID and GetItemInfoInstant then itemID = select(1, GetItemInfoInstant(str)) end
    if not itemID then return nil end
    local name = GetItemInfo(itemID) or str
    local spell = GetItemSpell and select(1, GetItemSpell(itemID)) or nil
    return { kind = "item", itemID = itemID, name = name, spell = spell }
end

local function rebuildExtra()
    for i = 1, NUM_EXTRA do
        resolved[i] = resolveExtra(mod.db and mod.db.extra and mod.db.extra[i])
    end
end
mod._rebuildExtra = rebuildExtra

local function macroCondReady(body)
    for cond in body:gmatch("(%[.-%])") do
        if SecureCmdOptionParse(cond) ~= nil then return true end
    end
    return false
end
local function spellReady(name)
    if not name or not GetSpellCooldown then return true end
    local start, dur = GetSpellCooldown(name)
    if start and dur and dur > 1.5 and (start + dur - GetTime()) > 0 then return false end
    if playerHasBuff(name) then return false end
    return true
end
local function extraReady(r)
    if not r then return false end
    if r.kind == "item" then
        if not r.itemID or (GetItemCount(r.itemID) or 0) <= 0 then return false end
        if not IsUsableItem(r.itemID) then return false end
        local start, dur = GetItemCooldown(r.itemID)
        if start and dur and dur > 0 and (start + dur - GetTime()) > 0 then return false end
        if r.spell and playerHasBuff(r.spell) then return false end
        return true
    else
        if not r.hasCond and not r.spell then return false end
        if r.hasCond and not macroCondReady(r.body) then return false end
        if r.spell and not spellReady(r.spell) then return false end
        return true
    end
end
local function bindExtra(k, r)
    if r.kind == "item" then
        macroBtn:SetAttribute("macrotext", "/use " .. (r.name or ("item:" .. r.itemID)))
    else
        macroBtn:SetAttribute("macrotext", r.body)
    end
    SetOverrideBindingClick(owner, true, k, "VulFishMacroButton")
end

local function chosenKey()
    return (mod.db.key ~= "" and mod.db.key) or nil
end

-- Override bindings cannot be changed in combat, hence the lockdown bail-out.
local function actionHandler()
    if InCombatLockdown() then return end
    local k = chosenKey()
    if not k then ClearOverrideBindings(owner); return end
    if IsKeyDown and IsKeyDown(k) then return end   -- rebinding a held key breaks the press; API may be absent
    ClearOverrideBindings(owner)
    if UnitIsDeadOrGhost("player") then return end

    if midFishing then
        if mod.db.softInteract then
            SetOverrideBinding(owner, true, k, "INTERACTMOUSEOVER")
        else
            SetOverrideBindingSpell(owner, true, k, FISHING_NAME)
        end
        return
    end

    if mod.db.equipPole and not poleEquipped() then
        local pole = poleInBags()
        if pole then
            macroBtn:SetAttribute("macrotext", "/equip " .. pole)
            SetOverrideBindingClick(owner, true, k, "VulFishMacroButton")
            return
        end
    end

    if mod.db.lure and not hasLure() then
        local lure = bestOwnedLure()
        if lure then
            macroBtn:SetAttribute("macrotext", "/use " .. lure .. "\n/use 16")
            SetOverrideBindingClick(owner, true, k, "VulFishMacroButton")
            return
        end
    end

    for i = 1, NUM_EXTRA do
        local r = resolved[i]
        if r and extraReady(r) then bindExtra(k, r); return end
    end

    SetOverrideBindingSpell(owner, true, k, FISHING_NAME)
end
mod._apply = actionHandler

local accum = 0
owner:SetScript("OnUpdate", function(_, elapsed)
    if not mod._enabled or not mod.db then return end
    accum = accum + elapsed
    if accum < 0.3 then return end
    accum = 0
    if chosenKey() then actionHandler() end
end)

-- INTERACTMOUSEOVER spams UI_ERROR_MESSAGE while the bobber is not the soft target.
local errQuiet = false
local function setQuiet(on)
    if not UIErrorsFrame then return end
    on = (on and mod.db.quietErrors ~= false) or false
    if on == errQuiet then return end
    errQuiet = on
    if on then UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
    else UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE") end
end

local function onChannelStart(_, unit, _, spellID)
    if unit ~= "player" or not isFishingSpell(spellID) then return end
    midFishing = true
    setQuiet(true)
    setFishCVars()
    actionHandler()
end
local function onChannelStop(_, unit, _, spellID)
    if unit ~= "player" or not isFishingSpell(spellID) then return end
    midFishing = false
    setQuiet(false)
    restoreFishCVars()
    actionHandler()
end
local function onFailed(_, unit, _, spellID)
    if unit ~= "player" or not isFishingSpell(spellID) then return end
    midFishing = false
    setQuiet(false)
    restoreFishCVars()
    actionHandler()
end
local function onRegenEnabled() actionHandler() end
local function onInvChanged() if not midFishing then actionHandler() end end

local capture
local function refreshKey(k)
    capture:Hide()
    if k then
        mod.db.key = k
        ns:Print(L["Fishing key set to: %s"]:format(k))
        actionHandler()
    end
end
local function startCapture()
    if InCombatLockdown() then ns:Print(L["Can't change the fishing key in combat."]); return end
    if not capture then
        capture = CreateFrame("Frame", "VulFishCapture", UIParent)
        capture:SetAllPoints(UIParent)
        capture:SetFrameStrata("FULLSCREEN_DIALOG")
        capture:EnableKeyboard(true); capture:EnableMouse(true); capture:EnableMouseWheel(true)
        local bg = capture:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
        local fs = capture:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        fs:SetPoint("CENTER"); fs:SetText(L["Press the key for fishing  (ESC to cancel)"])
        local SKIP = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, UNKNOWN = 1 }
        capture:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then refreshKey(nil); return end
            if SKIP[key] then return end
            local pre = ""
            if IsControlKeyDown() then pre = pre .. "CTRL-" end
            if IsAltKeyDown() then pre = pre .. "ALT-" end
            if IsShiftKeyDown() then pre = pre .. "SHIFT-" end
            refreshKey(pre .. key)
        end)
        local MB = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
        capture:SetScript("OnMouseDown", function(_, btn) if MB[btn] then refreshKey(MB[btn]) end end)
        capture:SetScript("OnMouseWheel", function(_, d) refreshKey(d > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
    end
    capture:Show()
    capture:SetPropagateKeyboardInput(false)
end

function mod:OnEnable()
    mod:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", onChannelStart)
    mod:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", onChannelStop)
    mod:RegisterEvent("UNIT_SPELLCAST_FAILED", onFailed)
    mod:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET", onFailed)
    mod:RegisterEvent("PLAYER_REGEN_ENABLED", onRegenEnabled)
    mod:RegisterEvent("UNIT_INVENTORY_CHANGED", onInvChanged)
    mod:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", onInvChanged)
    rebuildExtra()
    actionHandler()
end

function mod:OnDisable()
    setQuiet(false)
    restoreFishCVars()
    if not InCombatLockdown() then ClearOverrideBindings(owner) end
end

function mod:GetOptions()
    local keyLabel = (mod.db.key ~= "") and L["Fishing key: %s  —  click to change"]:format(mod.db.key) or L["Set fishing key"]
    local opts = {
        { type = "desc", text = L["|cffaaaaaaOne key does it all: cast, reel in, and apply a lure — then auto-loots. Set a key below, face some water, and press it.|r"] },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = keyLabel, width = 260, onClick = startCapture },
            { type = "button", label = L["Clear key"], width = 120,
              onClick = function() mod.db.key = ""; ns:Print(L["Fishing key cleared."]); actionHandler() end },
        } },
        { type = "toggle", label = L["One-key reel (soft-target interact)"], tooltip = L["While the bobber is out, the same key interacts with it to reel in. Needs soft-target interaction, which is enabled only while fishing and restored afterwards."],
          get = function() return mod.db.softInteract end,
          set = function(_, v) mod.db.softInteract = v; actionHandler() end },
        { type = "toggle", label = L["Auto-apply a lure when the pole has none"],
          get = function() return mod.db.lure end,
          set = function(_, v) mod.db.lure = v; actionHandler() end },
        { type = "toggle", label = L["Auto-loot while fishing"],
          get = function() return mod.db.autoLoot end,
          set = function(_, v) mod.db.autoLoot = v end },
        { type = "toggle", label = L["Auto-equip a fishing pole if none is worn"],
          get = function() return mod.db.equipPole end,
          set = function(_, v) mod.db.equipPole = v; actionHandler() end },
        { type = "toggle", label = L["Hide the reel error spam while fishing"],
          get = function() return mod.db.quietErrors ~= false end,
          set = function(_, v) mod.db.quietErrors = v; if not v then setQuiet(false) end end },
        { type = "toggle", label = L["Boost fishing sound (hear the bite clearly)"], tooltip = L["While the bobber is out, maxes effect + master volume and dims music/ambience so the splash is easy to hear. Restored when you reel in."],
          get = function() return mod.db.soundBoost end,
          set = function(_, v) mod.db.soundBoost = v end },
        { type = "toggle", label = L["Keep sound audible when the game is in the background"],
          get = function() return mod.db.soundBG end,
          set = function(_, v) mod.db.soundBG = v end },
        { type = "slider", label = L["Fishing sound volume"], min = 0, max = 100, step = 5,
          get = function() return mod.db.soundLevel or 100 end,
          set = function(_, v) mod.db.soundLevel = v end },
        { type = "header", text = L["Extra items & macros"] },
        { type = "desc", text = L["|cffaaaaaaItems or macros also used by the key while fishing — only when ready (off cooldown, buff missing, conditions met), then it goes back to casting. Type an item name or ID, shift-click an item into the box, or paste a /macro.|r"] },
    }
    mod.db.extra = mod.db.extra or {}
    for i = 1, NUM_EXTRA do
        opts[#opts + 1] = {
            type = "editbox", label = L["Slot %d"]:format(i), width = 300, editWidth = 200,
            get = function() return mod.db.extra[i] or "" end,
            set = function(_, v)
                mod.db.extra[i] = strtrim(v or "")
                rebuildExtra()
                actionHandler()
            end,
        }
    end
    return opts
end
end)(...);

(function(...)
-- QueueTimer: shows a countdown on the PvP/PvE queue pop dialog.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("queuetimer", {
    name        = "Queue Timer",
    group       = "Extras",
    description = "Shows a countdown on the PvP/PvE queue pop dialog. Optional sound warning at 5 seconds.",
    defaults = {
        queueTimerAudio   = true,
        queueTimerWarning = true,
        hideOtherTimers   = true,
    },
})

local bgId
local updateFrame
local proposalTimeLeft = 40
local queues = {}
local dungeonQueuedTime
local soundPlayed
local isPveQueueActive
local pveQueuePopTime  -- only in memory; old SV pop time is not migrated

local function stopUpdateFrame()
    if updateFrame then
        updateFrame:Hide()
        soundPlayed = false
    end
end

local function createCustomFontStrings(dialog)
    if dialog.queueTimerLabels then return end
    local maxWidth = dialog:GetWidth()

    dialog.customLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.customLabel:SetPoint("TOP", dialog.label or dialog.text, "TOP", 0, 0)
    dialog.customLabel:SetText(L["Queue expires in"])
    local f = dialog.customLabel:GetFont(); dialog.customLabel:SetFont(f, 15, "OUTLINE")
    dialog.customLabel:SetWidth(maxWidth)

    dialog.timerLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.timerLabel:SetPoint("TOP", dialog.customLabel, "BOTTOM", 0, -44)
    f = dialog.timerLabel:GetFont(); dialog.timerLabel:SetFont(f, 24, "OUTLINE")
    dialog.timerLabel:SetWidth(maxWidth)

    dialog.bgLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.bgLabel:SetPoint("TOP", dialog.timerLabel, "BOTTOM", 0, -4)
    f = dialog.bgLabel:GetFont(); dialog.bgLabel:SetFont(f, 15, "OUTLINE")
    dialog.bgLabel:SetWidth(maxWidth)

    dialog.statusTextLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.statusTextLabel:SetPoint("TOP", dialog.bgLabel, "BOTTOM", 0, -3)
    f = dialog.statusTextLabel:GetFont(); dialog.statusTextLabel:SetFont(f, 11, "OUTLINE")
    dialog.statusTextLabel:SetWidth(maxWidth)

    dialog.queueTimerLabels = true
end

local function setExpiresText(timeRemaining, dialog, pvp)
    local secs = timeRemaining > 0 and timeRemaining or 1
    local color = secs > 20 and "20ff20" or secs > 10 and "ffff00" or "ff0000"
    local timerText = format("|cff%s%s|r", color, SecondsToTime(secs))

    -- Battleground / arena name. Reliable in TBC via GetBattlefieldStatus;
    -- the dialog's own instanceInfo.name is empty on the Anniversary client.
    local bgName = ""
    if pvp and bgId and GetBattlefieldStatus then
        local _, mapName = GetBattlefieldStatus(bgId)
        bgName = mapName or ""
    end

    createCustomFontStrings(dialog)
    if dialog.instanceInfo then
        dialog.customLabel:SetPoint("TOP", dialog.label, "TOP", 0, 0)
        dialog.instanceInfo:SetAlpha(0)
        dialog.label:SetText("")
        dialog.timerLabel:SetText(timerText)
        if bgName == "" and dialog.instanceInfo.name and (dialog.instanceInfo:IsShown() or pvp) then
            bgName = dialog.instanceInfo.name:GetText() or ""
        end
        dialog.bgLabel:SetText(bgName)
        -- statusText sub-region isn't present on every dialog variant — guard it
        local st = dialog.instanceInfo.statusText
        dialog.statusTextLabel:SetText((st and st:GetText()) or "")
    else
        dialog.customLabel:SetPoint("TOP", dialog.text, "TOP", 0, 0)
        dialog.text:SetText("")
        dialog.timerLabel:SetText(timerText)
        dialog.bgLabel:SetText(bgName)
        dialog.statusTextLabel:SetText("")
    end
end

local function onUpdate(elapsed)
    if not mod._enabled then
        stopUpdateFrame()
        return
    end
    if bgId then
        updateFrame.timer = updateFrame.timer - elapsed
        if mod.db.queueTimerWarning then
            if GetBattlefieldPortExpiration(bgId) == 6 and not soundPlayed then
                PlaySoundFile(567458, "master")
                C_Timer.After(0.1, function() PlaySoundFile(567458, "master") end)
                C_Timer.After(0.2, function() PlaySoundFile(567458, "master") end)
                soundPlayed = true
            end
        end
        if updateFrame.timer <= 0 then
            if GetBattlefieldStatus(bgId) ~= "confirm" then
                stopUpdateFrame()
                return
            end
            setExpiresText(GetBattlefieldPortExpiration(bgId), PVPReadyDialog, true)
            updateFrame.timer = 1
        end
    elseif proposalTimeLeft and pveQueuePopTime then
        -- derive from the fixed start time instead of decrementing per frame
        proposalTimeLeft = 40 - (GetTime() - pveQueuePopTime)
        if mod.db.queueTimerWarning then
            if proposalTimeLeft <= 6 and not soundPlayed then
                PlaySoundFile(567458, "master")
                C_Timer.After(0.1, function() PlaySoundFile(567458, "master") end)
                C_Timer.After(0.2, function() PlaySoundFile(567458, "master") end)
                soundPlayed = true
            end
        end
        if proposalTimeLeft <= 0 then
            -- window elapsed: restart the display loop from now
            pveQueuePopTime = GetTime()
            proposalTimeLeft = 40
        end
        setExpiresText(proposalTimeLeft, LFGDungeonReadyDialog)
    end
end

local function startUpdateFrame()
    if not updateFrame then
        updateFrame = CreateFrame("Frame")
        updateFrame.timer = 1
        updateFrame:SetScript("OnUpdate", function(_, elapsed) onUpdate(elapsed) end)
    end
    updateFrame:Show()
end

local function printMsg(message)
    DEFAULT_CHAT_FRAME:AddMessage(L["|cff00c0ffQueueTimer:|r "] .. message)
    if mod.db.queueTimerAudio then PlaySoundFile(567458, "master") end
end

local function captureDungeonQueuedTime()
    local hasData, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, queuedTime = GetLFGQueueStats(LE_LFG_CATEGORY_LFD)
    if hasData and queuedTime > 0 then dungeonQueuedTime = queuedTime end
end

local function handleDungeonReadyDialog()
    local proposalExists, _, _, _, _, _, _, hasResponded = GetLFGProposal()
    if proposalExists and not hasResponded then
        -- pveQueuePopTime is the single fixed start time; remaining time is
        -- DERIVED from it (onUpdate reads the same source), so a re-fired
        -- LFG_PROPOSAL_SHOW no longer subtracts the elapsed window a 2nd time.
        local firstShow = not pveQueuePopTime
        if firstShow then pveQueuePopTime = GetTime() end

        proposalTimeLeft = 40 - (GetTime() - pveQueuePopTime)
        if proposalTimeLeft < 0 then proposalTimeLeft = 0 end
        setExpiresText(proposalTimeLeft, LFGDungeonReadyDialog)
        isPveQueueActive = true
        startUpdateFrame()

        if firstShow then
            if dungeonQueuedTime then
                local timeWaited = GetTime() - dungeonQueuedTime
                printMsg(timeWaited < 1 and L["Dungeon queue popped instantly!"] or format(L["Dungeon queue popped after %s"], SecondsToTime(timeWaited)))
            else
                printMsg(L["Dungeon queue popped."])
            end
            dungeonQueuedTime = nil
        end
    end
end

local function updateBattlefieldStatus()
    local isConfirm
    for i = 1, GetMaxBattlefieldID() do
        local status = GetBattlefieldStatus(i)
        if status == "queued" then
            queues[i] = queues[i] or GetTime() - (GetBattlefieldTimeWaited(i) / 1000)
        elseif status == "confirm" then
            if queues[i] then
                local secs = GetTime() - queues[i]
                printMsg(secs < 1 and L["Queue popped instantly!"] or format(L["Queue popped after %s"], SecondsToTime(secs)))
                queues[i] = nil
            end
            isConfirm = true
        else
            queues[i] = nil
        end
    end
    if not isConfirm and not isPveQueueActive then
        bgId = nil
        stopUpdateFrame()
    end
end

local function hideOtherTimers()
    if not mod.db.hideOtherTimers then return end
    if not LFGDungeonReadyPopup then return end
    local children = { LFGDungeonReadyPopup:GetChildren() }
    for _, child in ipairs(children) do
        if child:GetObjectType() == "StatusBar" then child:Hide() end
    end
end

local hooksInstalled = false
local function installHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    if PVPReadyDialog_Display and hooksecurefunc then
        hooksecurefunc("PVPReadyDialog_Display", function(_, i)
            if not mod._enabled then return end
            bgId = i
            startUpdateFrame()
            setExpiresText(GetBattlefieldPortExpiration(bgId), PVPReadyDialog, true)
        end)
    end
end

-- Named handlers registered through the module, so the framework takes all six
-- back out on disable. They used to be anonymous, registered once behind a
-- latch, and left live for the rest of the session with only an _enabled check
-- inside each to keep them quiet.
local function onProposalShow()
    handleDungeonReadyDialog(); hideOtherTimers()
end
local function endProposal()
    isPveQueueActive = false
    stopUpdateFrame()
    hideOtherTimers()
    pveQueuePopTime = nil
    proposalTimeLeft = 40
end
local function onQueueStatusUpdate() captureDungeonQueuedTime() end
local function onBattlefieldStatus() updateBattlefieldStatus() end

function mod:OnEnable()
    installHooks()
    self:RegisterEvent("LFG_PROPOSAL_SHOW",       onProposalShow)
    self:RegisterEvent("LFG_PROPOSAL_SUCCEEDED",  endProposal)
    self:RegisterEvent("LFG_PROPOSAL_FAILED",     endProposal)
    self:RegisterEvent("LFG_PROPOSAL_DONE",       endProposal)
    self:RegisterEvent("LFG_QUEUE_STATUS_UPDATE", onQueueStatusUpdate)
    self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", onBattlefieldStatus)
end

-- The labels live on Blizzard's dialogs and would show stale text on the next
-- queue pop with the module off; instanceInfo was alpha-hidden by us.
-- Known gap: Blizzard's own label text (blanked by setExpiresText) cannot be
-- reconstructed here, so a dialog that is showing RIGHT NOW stays textless
-- until this pop expires; the next pop repaints it.
local function clearCustomLabels(dialog)
    if dialog and dialog.queueTimerLabels then
        dialog.customLabel:SetText("")
        dialog.timerLabel:SetText("")
        dialog.bgLabel:SetText("")
        dialog.statusTextLabel:SetText("")
        if dialog.instanceInfo then dialog.instanceInfo:SetAlpha(1) end
    end
end

function mod:OnDisable()
    bgId = nil
    isPveQueueActive = false
    pveQueuePopTime = nil
    proposalTimeLeft = 40
    stopUpdateFrame()
    clearCustomLabels(PVPReadyDialog)
    clearCustomLabels(LFGDungeonReadyDialog)
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Sound"] },
        {
            type = "checkbox", label = L["Sound on queue pop"],
            tooltip = L["Plays a sound as soon as the queue pops."],
            get = function() return mod.db.queueTimerAudio end,
            set = function(_, v) mod.db.queueTimerAudio = v end,
        },
        {
            type = "checkbox", label = L["5-second warning"],
            tooltip = L["Plays 3 quick sounds when only 5 seconds remain to accept."],
            get = function() return mod.db.queueTimerWarning end,
            set = function(_, v) mod.db.queueTimerWarning = v end,
        },
        { type = "spacer" },
        { type = "header", text = L["Misc"] },
        {
            type = "checkbox", label = L["Hide other timers (e.g. BigWigs)"],
            tooltip = L["Hides foreign StatusBars on the LFG ready popup so only our timer is visible."],
            get = function() return mod.db.hideOtherTimers end,
            set = function(_, v) mod.db.hideOtherTimers = v end,
        },
    }
end
end)(...);

(function(...)
-- VuloClassicUI / Modules / LazyVulo
-- A correct crystal click refreshes the Introspection debuff -> first queue entry is consumed.
-- A wrong click deals Reprisal self-damage -> the consumed entry is restored.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("lazyvulo", {
    name        = "LazyVulo",
    group       = "Extras",
    description = "Apexis Relic memory minigame helper (Ogri'la dailies): record the flashing color sequence, always see what to click next.",
    defaults    = {
        enabled        = true,
        autoShow       = true,
        hotkeysEnabled = true,
        unbindInCombat = true,
        showTooltips   = true,
        scale          = 1.25,
        keys           = { "G", "Y", "B", "R" },
        x              = 0,
        y              = 120,
    },
})

-- Relic game objects; their gossip option starts the game
local RELIC_OBJECTS = { [185890] = true, [185944] = true }
-- "Introspection" debuff ids
local INTROSPECTION = { [40055] = true, [40165] = true, [40166] = true, [40167] = true }
-- "Reprisal" self-damage spell id
local REPRISAL_ID   = 40065
local SELF_FLAGS    = 0x511  -- mine + friendly + player-controlled + player

local RELIC_COLORS = {
    { label = "Green relic",  r = 0.10, g = 0.85, b = 0.15 },
    { label = "Yellow relic", r = 1.00, g = 0.85, b = 0.10 },
    { label = "Blue relic",   r = 0.15, g = 0.45, b = 1.00 },
    { label = "Red relic",    r = 0.95, g = 0.15, b = 0.10 },
}

-- 2x2 grid mirroring the in-game crystal layout, keyed by color index (1=green 2=yellow 3=blue 4=red)
local RECORD_POS = {
    [4] = { 60, 42 },   -- red    -> top-left
    [1] = { 94, 42 },   -- green  -> top-right
    [3] = { 60,  8 },   -- blue   -> bottom-left
    [2] = { 94,  8 },   -- yellow -> bottom-right
}

local MAX_SHOWN = 12
local FRAME_W   = 184
local FRAME_H   = 166

local f
local queue    = {}
local consumed
local lastExpire = 0

local function playClickSound()
    local snd = SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON
    if snd and PlaySound then PlaySound(snd) end
end

local updateQueue  -- forward

local function shiftQueue()
    consumed = queue[1]
    table.remove(queue, 1)
    updateQueue()
end

local function unshiftQueue()
    if not consumed then return end
    table.insert(queue, 1, consumed)
    consumed = nil
    updateQueue()
end

local function recordColor(colorIndex)
    queue[#queue + 1] = colorIndex
    playClickSound()
    updateQueue()
end

local function introspectionExpire()
    for i = 1, 40 do
        local name, _, _, _, _, exp, _, _, _, sid = UnitDebuff("player", i)
        if not name then return nil end
        if sid and INTROSPECTION[sid] then return exp end
    end
    return nil
end

local function unbindKeys()
    if not f then return end
    ClearOverrideBindings(f)
    f._bound = false
end

local function bindKeys()
    if not f then return end
    if InCombatLockdown() then
        f._pendingBind = true
        return
    end
    ClearOverrideBindings(f)
    f._bound = false
    if not f:IsVisible() or not mod.db.hotkeysEnabled then return end
    for i = 1, 4 do
        local key = mod.db.keys[i]
        if key and key ~= "" then
            SetOverrideBindingClick(f, true, key, "VCUI_LazyVuloRecord" .. i)
        end
    end
    f._bound = true
end

local function onRegenDisabled()
    if not f or not f._bound then return end
    if mod.db.unbindInCombat then
        -- fires just before lockdown engages, so unbinding is still allowed
        unbindKeys()
        f._pendingBind = true
    end
end

local function onRegenEnabled()
    if not f then return end
    if f._pendingUnbind then
        f._pendingUnbind = nil
        unbindKeys()
    elseif f._pendingBind then
        f._pendingBind = nil
        if f:IsVisible() then bindKeys() end
    end
end

local function attachHelpTooltip(btn)
    ns.UI:AttachTooltip(btn, function(self)
        if not mod.db.showTooltips or not self.toolHeader then return nil end
        return { title = self.toolHeader,
                 lines = self.toolText and { { self.toolText, nil, nil, nil, true } } or nil }
    end)
end

local function makeIconButton(parent, name, size)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(size, size)
    b.rim = b:CreateTexture(nil, "BACKGROUND")
    b.rim:SetAllPoints(b)
    b.rim:SetColorTexture(0.02, 0.02, 0.03, 1)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.18)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    attachHelpTooltip(b)
    return b
end

local function setButtonColor(b, colorIndex)
    local c = RELIC_COLORS[colorIndex]
    if c then b.tex:SetColorTexture(c.r, c.g, c.b, 1) end
end

local function onQueueClick(self, button)
    local idx = self:GetID()
    if not queue[idx] then return end
    playClickSound()
    if button == "LeftButton" then
        table.remove(queue, idx)
    else
        for i = #queue, idx, -1 do
            queue[i] = nil
        end
    end
    updateQueue()
end

local function buildFrame()
    if f then return f end

    f = CreateFrame("Frame", "VCUI_LazyVulo", UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    -- one-time migration of the legacy point/relPoint anchor save to a CENTER offset
    if mod.db.point then
        f:ClearAllPoints()
        f:SetPoint(mod.db.point, UIParent, mod.db.relPoint or "CENTER", mod.db.x or 0, mod.db.y or 0)
        local fx, fy = f:GetCenter()
        local px, py = UIParent:GetCenter()
        if fx and px then mod.db.x, mod.db.y = fx - px, fy - py end
        mod.db.point, mod.db.relPoint = nil, nil
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
    f:SetScale(mod.db.scale or 1)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:Hide()

    if ns.UI and ns.UI.StyleBackdrop then
        ns.UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.borderDark or ns.COLORS.border })
        if ns.UI.CreateShadow then ns.UI:CreateShadow(f) end
    end

    ns:CreateMover(f, { key = "lazyvulo", label = "|cffffffffLAZYVULO|r", db = mod.db, width = FRAME_W, height = FRAME_H,
        scalable = true, anchorable = true })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if ns.UI and ns.UI.Font then ns.UI.Font(title, 13) end
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    title:SetText((ns.C and ns.C.accent or "|cff9b6cff") .. "LazyVulo|r")

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeText:SetPoint("CENTER", close, "CENTER", 0, 0)
    closeText:SetText("×")
    closeText:SetTextColor(0.7, 0.7, 0.7)
    close:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function() closeText:SetTextColor(0.7, 0.7, 0.7) end)
    close:SetScript("OnClick", function() f:Hide() end)

    f.slots = {}
    for i = 1, MAX_SHOWN do
        local size = (i == 1) and 34 or 22
        local b = makeIconButton(f, nil, size)
        b:SetID(i)
        b:SetScript("OnClick", onQueueClick)
        b.toolText = L["Left click: remove this entry.\nRight click: remove this and all later entries."]
        if i == 1 then
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -26)
        elseif i <= 6 then
            b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 46 + (i - 2) * 26, -60)
        else
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + (i - 7) * 26, -64)
        end
        b:Hide()
        f.slots[i] = b
    end

    f.overflow = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    if ns.UI and ns.UI.Font then ns.UI.Font(f.overflow, 11) end
    f.overflow:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + 6 * 26, -68)
    f.overflow:SetText("")

    for i, c in ipairs(RELIC_COLORS) do
        local b = makeIconButton(f, "VCUI_LazyVuloRecord" .. i, 30)
        local pos = RECORD_POS[i]
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", pos[1], pos[2])
        setButtonColor(b, i)
        b.toolHeader = L[c.label]
        b:SetScript("OnClick", function() recordColor(i) end)
        f["record" .. i] = b
    end

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 0.6)
    sep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 78)
    sep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 78)
    sep:SetHeight(1)

    f:SetScript("OnEvent", function(_, event, unit)
        -- Introspection refreshes announce themselves via the player's aura
        -- event; the old 0.1s poll rescanned all debuff slots while shown.
        if event == "UNIT_AURA" then
            if unit ~= "player" then return end
            local exp = introspectionExpire()
            if exp and exp ~= lastExpire then
                lastExpire = exp
                shiftQueue()
            end
            return
        end
        local _, sub, _, _, _, _, _, _, _, destFlags, _, sid = CombatLogGetCurrentEventInfo()
        if sub == "SPELL_DAMAGE" and sid == REPRISAL_ID
           and destFlags == SELF_FLAGS and consumed then
            unshiftQueue()
        end
    end)

    f:SetScript("OnShow", function(self)
        -- sync to a running Introspection so reopening mid-game doesn't eat a queue entry
        lastExpire = introspectionExpire() or 0
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        if self.RegisterUnitEvent then
            self:RegisterUnitEvent("UNIT_AURA", "player")
        else
            self:RegisterEvent("UNIT_AURA")
        end
        bindKeys()
    end)
    f:SetScript("OnHide", function(self)
        self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:UnregisterEvent("UNIT_AURA")
        if InCombatLockdown() and self._bound then
            self._pendingUnbind = true
        else
            unbindKeys()
        end
    end)

    return f
end

local function updateKeyHints()
    if not f then return end
    for i = 1, 4 do
        local b = f["record" .. i]
        local key = mod.db.hotkeysEnabled and mod.db.keys[i]
        if key and key ~= "" then
            b.toolText = string.format(L["Hotkey: %s"], "|cffffffff" .. key .. "|r")
        else
            b.toolText = L["Click to record this color."]
        end
    end
end

updateQueue = function()
    if not f then return end
    for i = 1, MAX_SHOWN do
        local b, color = f.slots[i], queue[i]
        if color then
            setButtonColor(b, color)
            b.toolHeader = L[RELIC_COLORS[color].label]
            b:Show()
        else
            b:Hide()
        end
    end
    if #queue > MAX_SHOWN then
        f.overflow:SetText(string.format("+%d", #queue - MAX_SHOWN))
    else
        f.overflow:SetText("")
    end
end

local function showWindow()
    buildFrame()
    updateKeyHints()
    f:Show()
    updateQueue()
end

local function toggleWindow()
    buildFrame()
    if f:IsShown() then f:Hide() else showWindow() end
end

local gossipHooked = false

local function onGossipSelect()
    if not mod._enabled or not mod.db.autoShow then return end
    local guid = UnitGUID and UnitGUID("npc")
    local objId = guid and tonumber(guid:match("^GameObject%-.-%-(%d+)%-%x+$"))
    if objId and RELIC_OBJECTS[objId] then
        showWindow()
    end
end

local function installGossipHook()
    if gossipHooked or not C_GossipInfo then return end
    gossipHooked = true
    if C_GossipInfo.SelectOption then
        hooksecurefunc(C_GossipInfo, "SelectOption", onGossipSelect)
    end
    if C_GossipInfo.SelectOptionByIndex then
        hooksecurefunc(C_GossipInfo, "SelectOptionByIndex", onGossipSelect)
    end
end

function mod:OnEnable()
    installGossipHook()
    mod:RegisterEvent("PLAYER_REGEN_DISABLED", onRegenDisabled)
    mod:RegisterEvent("PLAYER_REGEN_ENABLED",  onRegenEnabled)
end

function mod:OnDisable()
    if f then
        if not InCombatLockdown() then unbindKeys() end
        f:Hide()
    end
end

ns:RegisterSlash({ key = "LAZYVULO", commands = { "/lazyvulo", "/lv" },
    desc = "Open the one-button helper.",
    module = "lazyvulo",
})
ns.Slash.LAZYVULO = function()
    if not mod._enabled then
        ns:Print(L["LazyVulo is disabled."])
        return
    end
    toggleWindow()
end

function mod:GetOptions()
    local items = {
        { type = "header", text = L["LazyVulo"] },
        { type = "desc",
          text = L["|cffaaaaaaHelper for the Apexis Relic memory minigame (Ogri'la dailies). Record the flashing sequence with the buttons or hotkeys; the first icon is always your next click. Correct clicks are consumed automatically, wrong clicks are restored.|r"] },
        { type = "desc",
          text = L["|cffaaaaaaOpen manually with /lazyvulo or /lv.|r"] },
        { type = "spacer", height = 4 },

        { type = "toggle", label = L["Auto-show at the Apexis Relic"],
          tooltip = L["Opens the window automatically when you start the relic minigame."],
          get = function() return mod.db.autoShow end,
          set = function(_, v) mod.db.autoShow = v end },

        { type = "toggle", label = L["Enable hotkeys while the window is shown"],
          get = function() return mod.db.hotkeysEnabled end,
          set = function(_, v)
              mod.db.hotkeysEnabled = v
              updateKeyHints()
              if f and f:IsShown() then bindKeys() end
          end },

        { type = "toggle", label = L["Disable hotkeys while in combat"],
          tooltip = L["Hands the keys back to your action bars while you are in combat."],
          get = function() return mod.db.unbindInCombat end,
          set = function(_, v) mod.db.unbindInCombat = v end },

        { type = "toggle", label = L["Show help tooltips"],
          get = function() return mod.db.showTooltips end,
          set = function(_, v) mod.db.showTooltips = v end },

        { type = "slider", label = L["Window scale"],
          min = 0.8, max = 2.0, step = 0.05,
          get = function() return mod.db.scale end,
          set = function(_, v)
              mod.db.scale = v
              if f then f:SetScale(v) end
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Hotkeys"] },
        { type = "desc",
          text = L["|cffaaaaaaOne key per color (e.g. G, Y, B, R or NUMPAD1). Empty = no hotkey.|r"] },
    }

    for i, c in ipairs(RELIC_COLORS) do
        table.insert(items, { type = "editbox", label = L[c.label],
            width = 260, editWidth = 110,
            get = function() return mod.db.keys[i] or "" end,
            set = function(_, v)
                v = tostring(v or ""):gsub("%s", ""):upper()
                mod.db.keys[i] = v
                updateKeyHints()
                if f and f:IsShown() then bindKeys() end
            end })
    end

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "button", label = L["Show window"], width = 160,
        onClick = function() toggleWindow() end })

    return items
end
end)(...);

(function(...)
-- Gold tracker + auto vendor buy; each in its own IIFE so file-level locals and early returns stay isolated.
(function(...)
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("goldtracker", {
    name        = "Gold Tracker",
    group       = "Character",
    description = "Shows in the backpack gold tooltip how much gold has been gained or spent since the last reset. Per-char persistent.",
    defaults    = {
        enabled = true,
    },
})

local hooked = false

local function data()
    if not (ns.db and ns.db.char) then return nil end
    if not ns.db.char.goldtracker then
        ns.db.char.goldtracker = {
            sessionStart = nil,
            lastMoney    = nil,
            gained       = 0,
            spent        = 0,
        }
    end
    return ns.db.char.goldtracker
end

local GOLD_COLOR   = "|cffffd100"
local SILVER_COLOR = "|cffc7c7cf"
local COPPER_COLOR = "|cffeda55f"
local POS_COLOR    = "|cff44ff44"
local NEG_COLOR    = "|cffff4444"
local ACCENT       = "|cff9b6cff"
local GRAY         = "|cffaaaaaa"

local function formatCopper(copper)
    copper = math.abs(copper or 0)
    if copper == 0 then return "0" .. COPPER_COLOR .. "c|r" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts+1] = g .. GOLD_COLOR   .. "g|r" end
    if s > 0 then parts[#parts+1] = s .. SILVER_COLOR .. "s|r" end
    if c > 0 then parts[#parts+1] = c .. COPPER_COLOR .. "c|r" end
    if #parts == 0 then return "0" .. COPPER_COLOR .. "c|r" end
    return table.concat(parts, " ")
end

-- force=true resets the balance to now; without force only when never initialized.
local function initSession(force)
    local d = data()
    if not d then return end
    if d.sessionStart and not force then return end
    d.sessionStart = GetMoney() or 0
    d.lastMoney    = d.sessionStart
    d.gained       = 0
    d.spent        = 0
end

-- Resyncs lastMoney on login so offline delta (AH/mail/trade) is never counted as gained/spent.
local function syncOnLogin()
    local d = data()
    if not d then return end
    if not d.sessionStart then
        initSession(false)
    else
        d.lastMoney = GetMoney() or d.lastMoney or 0
    end
end

-- Account-wide store: db.global.charGold[realm][charName] = { money, class, faction }.
local function trackCharGold()
    if not (ns.db and ns.db.global) then return end
    local realm, name = GetRealmName(), UnitName("player")
    if not (realm and name) then return end
    ns.db.global.charGold = ns.db.global.charGold or {}
    ns.db.global.charGold[realm] = ns.db.global.charGold[realm] or {}
    ns.db.global.charGold[realm][name] = {
        money   = GetMoney() or 0,
        class   = select(2, UnitClass("player")),
        faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
    }
end

local function onMoney()
    local d = data()
    if not d then return end
    trackCharGold()
    if not d.sessionStart then
        initSession(false)
        return
    end
    local cur   = GetMoney() or 0
    local delta = cur - (d.lastMoney or cur)
    if delta > 0 then
        d.gained = (d.gained or 0) + delta
    elseif delta < 0 then
        d.spent  = (d.spent or 0) + (-delta)
    end
    d.lastMoney = cur
end

function mod.ResetSession()
    initSession(true)
    local d = data()
    if d then
        ns:Print(ns.C.accent .. L["Gold Tracker reset|r. Start = "] .. formatCopper(d.sessionStart))
    end
end

local function showTooltip(self)
    if not mod._enabled then return end
    local d = data()
    if not d then return end
    if not d.sessionStart then initSession(false) end

    -- Appends to a tooltip that is already ours instead of replacing it, which
    -- is why this cannot go through ShowTooltip.
    if GameTooltip:GetOwner() ~= self then
        ns.UI:OpenTooltip(self, "ANCHOR_RIGHT")
    else
        GameTooltip:AddLine(" ")
    end

    GameTooltip:AddLine(ns.C.accent .. L["Gold Balance|r"])
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(POS_COLOR .. L["Gained:|r"], formatCopper(d.gained))
    GameTooltip:AddDoubleLine(NEG_COLOR .. L["Spent:|r"],  formatCopper(d.spent))

    local net   = (d.gained or 0) - (d.spent or 0)
    local color = net >= 0 and POS_COLOR or NEG_COLOR
    local sign  = net >= 0 and "+" or "-"
    GameTooltip:AddDoubleLine(L["|cffffffffNet:|r"],
        color .. sign .. " " .. formatCopper(net) .. "|r")

    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(GRAY .. L["Start:|r"], GRAY .. formatCopper(d.sessionStart or 0) .. "|r")
    GameTooltip:AddDoubleLine(GRAY .. L["Now:|r"],   GRAY .. formatCopper(d.lastMoney or 0)    .. "|r")
    GameTooltip:AddLine(GRAY .. L["Reset with /vcui goldreset|r"])

    GameTooltip:Show()
end

local function hideTooltip()
    ns.UI:HideTooltip()
end

function ns.ShowGoldTooltip(owner)
    local store0 = ns.db and ns.db.global and ns.db.global.charGold
    local realm0 = GetRealmName and GetRealmName()
    if not mod._enabled and not (store0 and realm0 and store0[realm0]) then return end
    if GameTooltip:GetOwner() ~= owner then
        ns.UI:OpenTooltip(owner, "ANCHOR_RIGHT")
    end
    local coin = function(c)
        if GetCoinTextureString then return GetCoinTextureString(c or 0) end
        return formatCopper(c or 0)
    end
    local store = ns.db and ns.db.global and ns.db.global.charGold
    local realm = GetRealmName and GetRealmName()
    local myFaction = UnitFactionGroup and UnitFactionGroup("player") or nil
    if store and realm and store[realm] then
        local rows, total = {}, 0
        for name, info in pairs(store[realm]) do
            if not myFaction or (info.faction or myFaction) == myFaction then
                total = total + (info.money or 0)
                rows[#rows + 1] = { name = name, info = info }
            end
        end
        table.sort(rows, function(a, b) return a.name < b.name end)
        GameTooltip:AddDoubleLine(ns.C.accent .. L["Faction/Server Gold:|r"], coin(total))
        GameTooltip:AddLine(" ")
        for _, r in ipairs(rows) do
            local cls = r.info.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.info.class]
            local colored = r.name
            if cls then
                colored = string.format("|cff%02x%02x%02x%s|r",
                    math.floor((cls.r or 1) * 255 + 0.5), math.floor((cls.g or 1) * 255 + 0.5),
                    math.floor((cls.b or 1) * 255 + 0.5), r.name)
            end
            GameTooltip:AddDoubleLine(colored, coin(r.info.money))
        end
        GameTooltip:AddLine(" ")
        if IsShiftKeyDown and IsShiftKeyDown() then
            local acct = 0
            for _, chars in pairs(store) do
                for _, info in pairs(chars) do acct = acct + (info.money or 0) end
            end
            GameTooltip:AddDoubleLine(GRAY .. L["Account total:|r"], coin(acct))
        else
            GameTooltip:AddLine(GRAY .. L["<Hold Shift to show the account total>|r"])
        end
    end
    showTooltip(owner)
    GameTooltip:Show()
end

local function findMoneyFontString(frame, depth)
    if not frame or depth > 8 then return nil end
    local m = rawget(frame, "Money")
    if m and type(m) == "table" then
        local ok, t = pcall(function() return m.GetObjectType and m:GetObjectType() end)
        if ok and t == "FontString" then return m end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            local found = findMoneyFontString(child, depth + 1)
            if found then return found end
        end
    end
    return nil
end

local function hookOnce(frame, withLeave)
    if not frame or frame._vcui_moneyHooked then return false end
    frame._vcui_moneyHooked = true
    frame:HookScript("OnEnter", showTooltip)
    if withLeave then
        frame:HookScript("OnLeave", hideTooltip)
    end
    return true
end

-- Bag frames may not exist at load; retries every 3s until a money frame is found.
local retryCount = 0
local function tryHook()
    if hooked then return end
    local foundAny = false

    if _G.BaganatorCurrencyWidgetMixin and not mod._baganatorMixinHooked then
        mod._baganatorMixinHooked = true
        hooksecurefunc(_G.BaganatorCurrencyWidgetMixin, "OnLoad", function(widget)
            if widget.Money then hookOnce(widget.Money, false) end
        end)
        foundAny = true
    end

    for name, frame in pairs(_G) do
        if type(name) == "string" and name:find("^Baganator_") and type(frame) == "table" then
            local ok = pcall(function() return frame.GetObjectType end)
            if ok then
                local money = findMoneyFontString(frame, 0)
                if money and hookOnce(money, false) then
                    foundAny = true
                end
            end
        end
    end

    local defaultFrames = {
        "ContainerFrame1MoneyFrame",
        "BackpackTokenFrameMoneyFrame",
        "MainMenuBarBackpackMoneyFrame",
    }
    for _, name in ipairs(defaultFrames) do
        local f = _G[name]
        if f and f.HookScript and hookOnce(f, true) then
            foundAny = true
        end
    end

    if foundAny then
        hooked = true
        return
    end

    retryCount = retryCount + 1
    if retryCount < 20 and C_Timer and C_Timer.After then
        C_Timer.After(3, tryHook)
    end
end

function mod:OnEnable()
    -- Never initSession(true) here: it would wipe the persisted balance on every login.
    mod:RegisterEvent("PLAYER_LOGIN", syncOnLogin)
    mod:RegisterEvent("PLAYER_LOGIN", trackCharGold)
    mod:RegisterEvent("PLAYER_MONEY", onMoney)

    -- Enabled via toggle after PLAYER_LOGIN already fired.
    if ns.isInitialised then syncOnLogin(); trackCharGold() end

    tryHook()
end

function mod:OnDisable()
    -- HookScript cannot be undone, so showTooltip() gates on mod._enabled instead.
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Gold Tracker"] },
        { type = "desc",
          text = L["|cffaaaaaaShows in the backpack gold tooltip the balance since the last manual reset:|n  - |cff44ff44Gained|r (quests, loot, vendor sales, mail)|n  - |cffff4444Spent|r (repair, vendor buy, mail cost)|n  - |cffffffffNet|r (+/- since reset)|n|nValues are |cffffffffper-char persistent|r across /reload and logout.|nOffline gold (AH mail, trade) is not counted.|n|nReset: button below or |cffffff00/vcui goldreset|r.|r"] },
        { type = "button", label = L["Reset session"], width = 200,
          onClick = function() mod.ResetSession() end },
    }
end

end)(...);

(function(...)
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("autoitembuy", {
    name        = "Auto Item Buy",
    group       = "Bags & Items",
    description = "Automatically buys configured items at configured vendors. Shift when opening the merchant window = emergency stop.",
    defaults = {
        enabled    = false,
        autoClose  = true,
        chatMsg    = true,
        vendors    = {},     -- vendors[vendorName] = { [itemName] = true }
    },
})

local addVendorBuffer  = ""
local selectedVendor   = nil
local addItemBuffer    = ""

local function p(fmt, ...)
    if not mod.db.chatMsg then return end
    ns:Print(L["|cffffd200[AutoItemBuy]|r "] .. string.format(fmt, ...))
end

local function getVendorList()
    local list = {}
    for name in pairs(mod.db.vendors or {}) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

local function getVendorItems(vendorName)
    local list = {}
    local v = mod.db.vendors and mod.db.vendors[vendorName]
    if not v then return list end
    for itemName in pairs(v) do
        table.insert(list, itemName)
    end
    table.sort(list)
    return list
end

local function refreshUI()
    local UI = ns.UI
    if not (UI and UI.IsModuleActive and UI.BuildOptionsPage) then return end
    if not UI:IsModuleActive("autoitembuy") then return end
    -- Rebuild the page that is actually on screen. This module is rendered as a
    -- section of the "Gold & Vendors" page, so asking for its own page by name
    -- would replace that page with a lone module page.
    UI:BuildOptionsPage(UI._currentBuildKey or "autoitembuy", UI.currentTab)
end

local eventFrame

local function setupEvents()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("MERCHANT_SHOW")
    eventFrame:SetScript("OnEvent", function(self, event)
        if event ~= "MERCHANT_SHOW" then return end
        if not mod._enabled then return end

        -- Shift held while the merchant opens = emergency stop for this visit.
        if IsShiftKeyDown() then return end

        local npcName = UnitName("npc") or UnitName("target")
        if not npcName then return end

        local vendor = mod.db.vendors and mod.db.vendors[npcName]
        if not vendor then return end

        local numItems = GetMerchantNumItems()
        local bought = 0
        for i = 1, numItems do
            local name = GetMerchantItemInfo(i)
            if name and vendor[name] then
                p(L["Buying: "] .. name)
                pcall(function() BuyMerchantItem(i, 1) end)
                bought = bought + 1
            end
        end

        if mod.db.autoClose and bought > 0 then
            local count = 0
            self:SetScript("OnUpdate", function(s)
                count = count + 1
                if count > 10 then
                    CloseMerchant()
                    s:SetScript("OnUpdate", nil)
                end
            end)
        end
    end)
end

function mod:OnEnable()
    setupEvents()
end

function mod:GetOptions()
    local items = {}

    table.insert(items, { type = "header", text = L["General"] })

    table.insert(items, {
        type = "toggle", label = L["Close merchant window after purchase"],
        tooltip = L["Closes the merchant window automatically ~0.2s after purchase."],
        get = function() return mod.db.autoClose end,
        set = function(_, v) mod.db.autoClose = v end,
    })

    table.insert(items, {
        type = "toggle", label = L["Chat message on each purchase"],
        get = function() return mod.db.chatMsg end,
        set = function(_, v) mod.db.chatMsg = v end,
    })

    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaTip: Hold SHIFT when opening the merchant window to skip automatic purchase once.|r"] })

    table.insert(items, { type = "spacer", height = 12 })

    table.insert(items, { type = "header", text = L["Add Vendor"] })

    table.insert(items, {
        type = "group", layout = "row", gap = 6,
        items = {
            {
                type = "editbox", label = L["Vendor Name"],
                width = 260,
                get = function() return addVendorBuffer end,
                set = function(_, v) addVendorBuffer = v end,
            },
            {
                type = "button", label = L["Add"], width = 100,
                onClick = function()
                    local name = (addVendorBuffer or ""):match("^%s*(.-)%s*$")
                    if not name or name == "" then
                        ns:Print(L["|cffff5555Please enter a vendor name.|r"])
                        return
                    end
                    mod.db.vendors = mod.db.vendors or {}
                    if mod.db.vendors[name] then
                        ns:Print(L["|cffff5555Vendor '%s' already exists.|r"], name)
                        return
                    end
                    mod.db.vendors[name] = {}
                    selectedVendor = name
                    addVendorBuffer = ""
                    ns:Print(L["Vendor '%s' added."], name)
                    refreshUI()
                end,
            },
        },
    })

    table.insert(items, { type = "spacer", height = 12 })

    table.insert(items, { type = "header", text = L["Manage Vendors"] })

    local vendorList = getVendorList()
    if #vendorList == 0 then
        table.insert(items, { type = "desc",
            text = L["|cffaaaaaaNo vendors added yet. Add a vendor above, then select it here to configure items.|r"] })
    else
        if not selectedVendor or not mod.db.vendors[selectedVendor] then
            selectedVendor = vendorList[1]
        end

        local vendorValues = {}
        for _, v in ipairs(vendorList) do
            table.insert(vendorValues, { value = v, text = v })
        end

        table.insert(items, {
            type = "dropdown", label = L["Currently selected vendor"],
            width = 280,
            values = vendorValues,
            get = function() return selectedVendor end,
            set = function(_, v)
                selectedVendor = v
                refreshUI()
            end,
        })

        table.insert(items, {
            type = "button", label = L["Delete this vendor"], width = 180,
            onClick = function()
                if not selectedVendor then return end
                local name = selectedVendor
                mod.db.vendors[name] = nil
                ns:Print(L["Vendor '%s' removed."], name)
                selectedVendor = nil
                refreshUI()
            end,
        })

        table.insert(items, { type = "spacer", height = 12 })

        table.insert(items, { type = "header",
            text = string.format(L["Items at '%s'"], selectedVendor) })

        table.insert(items, {
            type = "group", layout = "row", gap = 6,
            items = {
                {
                    type = "editbox", label = L["Item name (exactly as in-game)"],
                    width = 260,
                    get = function() return addItemBuffer end,
                    set = function(_, v) addItemBuffer = v end,
                },
                {
                    type = "button", label = L["Add"], width = 100,
                    onClick = function()
                        local name = (addItemBuffer or ""):match("^%s*(.-)%s*$")
                        if not name or name == "" then
                            ns:Print(L["|cffff5555Please enter an item name.|r"])
                            return
                        end
                        if not selectedVendor or not mod.db.vendors[selectedVendor] then return end
                        mod.db.vendors[selectedVendor][name] = true
                        addItemBuffer = ""
                        ns:Print(L["Item '%s' added at vendor '%s'."], name, selectedVendor)
                        refreshUI()
                    end,
                },
            },
        })

        table.insert(items, { type = "desc",
            text = L["|cffaaaaaaItem names must match the in-game name exactly (including case and special characters).|r"] })

        local itemList = getVendorItems(selectedVendor)
        if #itemList == 0 then
            table.insert(items, { type = "desc",
                text = L["|cffaaaaaaNo items configured. Add items above that should be bought automatically at this vendor.|r"] })
        else
            for _, itemName in ipairs(itemList) do
                table.insert(items, {
                    type = "group", layout = "row", gap = 6,
                    items = {
                        { type = "desc", text = "- " .. itemName, width = 340 },
                        {
                            type = "button", label = L["Remove"], width = 90,
                            onClick = function()
                                if not selectedVendor or not mod.db.vendors[selectedVendor] then return end
                                mod.db.vendors[selectedVendor][itemName] = nil
                                ns:Print(L["Item '%s' removed."], itemName)
                                refreshUI()
                            end,
                        },
                    },
                })
            end
        end
    end

    return items
end

end)(...);
end)(...);

(function(...)
-- Reskins TradeSkillFrame and CraftFrame; both Blizzard UIs are load-on-demand, so setup waits for ADDON_LOADED.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("professionwindow", {
    name        = "Profession Window",
    group       = "Character",
    description = "Enlarges and themes the profession windows (Tradeskill & Craft) to match the quest log: the detail pane sits beside the recipe list, with a Parchment or Dark theme.",
    defaults = {
        enabled   = true,
        larger    = true,
        theme     = "parchment",
        counts    = true,
        bankmats  = true,
        favorites = {},          -- [recipeName] = true
        favFirst  = true,
        bank      = {},          -- [charKey] = { [itemID] = count }
        prices    = true,
        showSource     = true,
        showThresholds = true,
        showSkillup    = true,
    },
})

local PARCHMENT = "Interface\\AddOns\\VuloClassicUI\\Media\\textures\\questlog-parchment"

local TALL = 73

local FRAMES = {
    {
        addon       = "Blizzard_TradeSkillUI",
        frame       = "TradeSkillFrame",
        title       = "TradeSkillFrameTitleText",
        list        = "TradeSkillListScrollFrame",
        detail      = "TradeSkillDetailScrollFrame",
        rowFmt      = "TradeSkillSkill%d",
        rowTemplate = "TradeSkillSkillButtonTemplate",
        displayed   = "TRADE_SKILLS_DISPLAYED",
        scrollBar   = "TradeSkillListScrollFrameScrollBar",
        updateHook  = "TradeSkillFrame_Update",
        info        = function(idx) return GetTradeSkillInfo(idx) end,
        numFn       = function() return GetNumTradeSkills() end,
        selFn       = function() return GetTradeSkillSelectionIndex() end,
        colorTable  = "TradeSkillTypeColor",
        highlight   = "TradeSkillHighlightFrame",
        cancel      = "TradeSkillCancelButton",
        create      = "TradeSkillCreateButton",
        close       = "TradeSkillFrameCloseButton",
        expand      = "TradeSkillExpandTabLeft",
        extraHide   = { "TradeSkillHorizontalBarLeft" },
        detailTex   = { "TradeSkillDetailScrollFrameTop", "TradeSkillDetailScrollFrameBottom" },
        -- Regions 9/10 are the horizontal bars; on the taller frame they cross the recipe text.
        hideRegions = { 4, 5, 8, 9, 10 },
        repos = function(f)
            local inv    = _G.TradeSkillInvSlotDropdown
            local sub    = _G.TradeSkillSubClassDropdown
            local search = _G.TradeSearchInputBox
            local anchor = _G.TradeSkillFrameAvailableFilterCheckButtonText
            if inv then inv:ClearAllPoints(); inv:SetPoint("TOPLEFT", f, "TOPLEFT", 550, -42) end
            if inv and sub then sub:ClearAllPoints(); sub:SetPoint("RIGHT", inv, "LEFT", -10, 0) end
            if search and anchor then search:ClearAllPoints(); search:SetPoint("LEFT", anchor, "RIGHT", 30, 0) end
        end,
    },
    {
        addon       = "Blizzard_CraftUI",
        frame       = "CraftFrame",
        title       = "CraftFrameTitleText",
        list        = "CraftListScrollFrame",
        detail      = "CraftDetailScrollFrame",
        rowFmt      = "Craft%d",
        rowTemplate = "CraftButtonTemplate",
        displayed   = "CRAFTS_DISPLAYED",
        scrollBar   = "CraftListScrollFrameScrollBar",
        updateHook  = "CraftFrame_Update",
        info        = function(idx) local n, _, t, a = GetCraftInfo(idx); return n, t, a end,
        numFn       = function() return GetNumCrafts() end,
        selFn       = function() return GetCraftSelectionIndex() end,
        colorTable  = "CraftTypeColor",
        isCraft     = true,
        highlight   = "CraftHighlightFrame",
        cancel      = "CraftCancelButton",
        create      = "CraftCreateButton",
        close       = "CraftFrameCloseButton",
        expand      = "CraftExpandTabLeft",
        costFmt     = "Craft%dCost",
        detailTex   = { "CraftDetailScrollFrameTop", "CraftDetailScrollFrameBottom" },
        hideRegions = { 4, 5, 9, 10 },
        repos = function(f)
            local dd = f.Dropdown
            if dd then dd:ClearAllPoints(); dd:SetPoint("TOPLEFT", f, "TOPLEFT", 550, -42) end
        end,
    },
}

local states = {}

local function isLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

local function applyTheme(cfg)
    local st = states[cfg.frame]
    if not (st and st.regs) then return end
    local dark = (mod.db.theme == "dark")
    for _, r in ipairs(st.regs) do
        if r.SetDesaturated then r:SetDesaturated(dark) end
        if dark then r:SetVertexColor(0.16, 0.15, 0.14, 1)
        else        r:SetVertexColor(1, 1, 1, 1) end
    end
end

local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

local function enhanceRow(btn, cfg)
    if btn._vcuiStarBtn then return end

    local sb = CreateFrame("Button", nil, btn)
    sb:SetSize(14, 14)
    sb:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
    local tex = sb:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(STAR)
    sb._tex = tex
    btn._vcuiStarBtn = sb

    -- Textureless overlays render as a box around the row text; real icons keep a texture path.
    btn._vcuiBoxes = {}
    for _, r in ipairs({ btn:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then
            local t = r.GetTexture and r:GetTexture()
            -- 130835 is UI-QuestTitleHighlight; the selection stays readable via its bold text.
            if not t or t == 130835 or (type(t) == "string" and t:lower():find("highlight")) then
                btn._vcuiBoxes[#btn._vcuiBoxes + 1] = r
                r:Hide()
            end
        end
    end
    if btn.SetHighlightTexture then btn:SetHighlightTexture("") end

    local function toggle()
        local name, skillType = cfg.info(btn:GetID())
        if name and name ~= "" and skillType ~= "header" then
            mod.db.favorites[name] = (not mod.db.favorites[name]) and true or nil
            if _G[cfg.updateHook] then pcall(_G[cfg.updateHook]) end
        end
    end
    sb:SetScript("OnClick", toggle)
    ns.UI:AttachTooltip(sb, { title = L["Favourite (click to toggle)"] })

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:HookScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then toggle() end
    end)
end

-- Returns nil when there are no favourites, leaving Blizzard's own row order untouched.
local function buildFavOrder(cfg)
    if mod.db.favFirst == false or not next(mod.db.favorites) then return nil end
    local num = cfg.numFn and cfg.numFn() or 0
    if num == 0 then return nil end
    local favs, rest = {}, {}
    for i = 1, num do
        local name, skillType = cfg.info(i)
        if name and skillType ~= "header" and mod.db.favorites[name] then
            favs[#favs + 1] = i
        else
            rest[#rest + 1] = i
        end
    end
    if #favs == 0 then return nil end
    for _, i in ipairs(rest) do favs[#favs + 1] = i end
    return favs
end

-- Repaints rows against a permuted index order and re-SetIDs them; must mirror Blizzard's row recipe exactly.
local function repaintReordered(cfg)
    local order = buildFavOrder(cfg)
    if not order then return end
    local list = _G[cfg.list]
    local offset = (FauxScrollFrame_GetOffset and list) and FauxScrollFrame_GetOffset(list) or 0
    local displayed = _G[cfg.displayed] or 0
    local hl = _G[cfg.highlight]
    local colorT = _G[cfg.colorTable] or {}
    local sel = cfg.selFn and cfg.selFn() or 0
    if hl then hl:Hide() end
    for i = 1, displayed do
        local btn = _G[cfg.rowFmt:format(i)]
        local idx = order[i + offset]
        if btn and btn:IsShown() and idx then
            local rowHl = _G[cfg.rowFmt:format(i) .. "Highlight"]
            if cfg.isCraft then
                local name, subName, ctype, avail, isExpanded, tpCost = GetCraftInfo(idx)
                local color = colorT[ctype]
                local cost = _G[cfg.rowFmt:format(i) .. "Cost"]
                local subT = _G[cfg.rowFmt:format(i) .. "SubText"]
                local txtFS = _G[cfg.rowFmt:format(i) .. "Text"]
                if color then
                    btn:SetNormalFontObject(color.font)
                    if cost then cost:SetTextColor(color.r, color.g, color.b) end
                    if Craft_SetSubTextColor then Craft_SetSubTextColor(btn, color.r, color.g, color.b) end
                end
                -- Text widths are per-entry, so a permuted row must re-run Blizzard's whole width sequence.
                if txtFS and not tpCost then
                    txtFS:SetWidth(list and list:IsVisible() and 290 or 320)
                end
                if ctype == "header" and name then
                    btn:SetID(idx)
                    btn:SetText(name)
                    if subT then subT:SetText("") end
                    if cost then cost:SetText("") end
                    if txtFS then txtFS:SetWidth(0) end
                    btn:SetNormalTexture(isExpanded and "Interface\\Buttons\\UI-MinusButton-Up"
                        or "Interface\\Buttons\\UI-PlusButton-Up")
                    if rowHl then rowHl:SetTexture("Interface\\Buttons\\UI-PlusButton-Hilight") end
                    btn:UnlockHighlight()
                elseif name then
                    btn:SetID(idx)
                    if btn.ClearNormalTexture then btn:ClearNormalTexture() else btn:SetNormalTexture("") end
                    if rowHl then rowHl:SetTexture("") end
                    btn:SetText((avail and avail > 0) and (" " .. name .. " [" .. avail .. "]") or (" " .. name))
                    if subT then
                        if subName and subName ~= "" then
                            subT:SetText(string.format(_G.PARENS_TEMPLATE or "(%s)", subName))
                            if txtFS then txtFS:SetWidth(0) end
                        else
                            subT:SetText("")
                            if txtFS then txtFS:SetWidth(_G.CRAFT_TEXT_WIDTH or 290) end
                        end
                    end
                    if cost then
                        if tpCost and tpCost > 0 then
                            cost:SetText(string.format(_G.TRAINER_LIST_TP or "%d TP", tpCost))
                        else
                            cost:SetText("")
                        end
                    end
                    if sel == idx then
                        if hl then hl:ClearAllPoints(); hl:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0); hl:Show() end
                        btn:LockHighlight()
                        if Craft_SetSubTextColor then Craft_SetSubTextColor(btn, 1, 1, 1) end
                        if cost then cost:SetTextColor(1, 1, 1) end
                    else
                        btn:UnlockHighlight()
                    end
                end
            else
                local name, skillType, avail, isExpanded = GetTradeSkillInfo(idx)
                local color = colorT[skillType]
                if color then btn:SetNormalFontObject(color.font) end
                -- SetID only with valid data, or a nil-name race leaves a row whose ID disagrees with its text.
                if skillType == "header" and name then
                    btn:SetID(idx)
                    btn:SetText(name)
                    btn:SetNormalTexture(isExpanded and "Interface\\Buttons\\UI-MinusButton-Up"
                        or "Interface\\Buttons\\UI-PlusButton-Up")
                    if rowHl then rowHl:SetTexture("Interface\\Buttons\\UI-PlusButton-Hilight") end
                    btn:UnlockHighlight()
                elseif name then
                    btn:SetID(idx)
                    if btn.ClearNormalTexture then btn:ClearNormalTexture() else btn:SetNormalTexture("") end
                    if rowHl then rowHl:SetTexture("") end
                    btn:SetText((avail and avail > 0) and (" " .. name .. " [" .. avail .. "]") or (" " .. name))
                    if sel == idx then
                        if hl then hl:ClearAllPoints(); hl:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0); hl:Show() end
                        btn:LockHighlight()
                    else
                        btn:UnlockHighlight()
                    end
                end
            end
        end
    end
end

local function refreshList(cfg)
    if not mod.active then return end

    -- Divider bars have client-varying region indices and Blizzard re-shows them every update: scan once, re-hide always.
    local st = states[cfg.frame]
    if st then
        if not st.barsScanned then
            st.barsScanned = true
            st.bars = {}
            local f = _G[cfg.frame]
            if f then
                local ftop = f:GetTop()
                for _, r in ipairs({ f:GetRegions() }) do
                    if r.GetObjectType and r:GetObjectType() == "Texture" and r.GetHeight then
                        local h, w = r:GetHeight() or 0, r:GetWidth() or 0
                        local top  = r.GetTop and r:GetTop()
                        -- Thin and wide identifies a divider; skip the parchment borders and the title area.
                        local nearTop = (ftop and top and (ftop - top) < 45)
                        if h > 0 and h <= 20 and w >= 100 and not nearTop then
                            st.bars[#st.bars + 1] = r
                        end
                    end
                end
            end
            local list = _G[cfg.list]
            if list then
                for _, r in ipairs({ list:GetRegions() }) do
                    if r.GetObjectType and r:GetObjectType() == "Texture" then
                        st.bars[#st.bars + 1] = r
                    end
                end
            end
        end
        for _, r in ipairs(st.bars) do r:Hide() end
    end

    -- Must run first: the loop below reads the remapped index off each button's new ID.
    repaintReordered(cfg)

    local displayed = _G[cfg.displayed] or 0
    local sbShown   = cfg.scrollBar and _G[cfg.scrollBar] and _G[cfg.scrollBar]:IsShown()
    local starInset = sbShown and -34 or -16
    for i = 1, displayed do
        local btn = _G[cfg.rowFmt:format(i)]
        if btn and btn:IsShown() then
            enhanceRow(btn, cfg)
            if btn._vcuiStarBtn then
                btn._vcuiStarBtn:ClearAllPoints()
                btn._vcuiStarBtn:SetPoint("RIGHT", btn, "RIGHT", starInset, 0)
            end
            if btn._vcuiBoxes then for _, r in ipairs(btn._vcuiBoxes) do r:Hide() end end
            local name, skillType, numAvailable = cfg.info(btn:GetID())
            local sb = btn._vcuiStarBtn
            if name and skillType and skillType ~= "header" then
                sb:Show()
                if mod.db.favorites[name] then
                    sb._tex:SetDesaturated(false); sb._tex:SetAlpha(1)
                else
                    sb._tex:SetDesaturated(true);  sb._tex:SetAlpha(0.35)
                end
                if mod.db.counts and numAvailable and numAvailable > 0 then
                    local txt = btn:GetText()
                    -- Unanchored check: an early return in Blizzard's update can leave our suffix standing.
                    if txt and not txt:find("%[%d+%]") then
                        btn:SetText(txt .. "  |cffffffff[" .. numAvailable .. "]|r")
                    end
                end
            else
                sb:Hide()
            end
        end
    end
end

local function installListEnhancements(cfg)
    if cfg._listHooked then return end
    if not _G[cfg.updateHook] then return end
    cfg._listHooked = true
    hooksecurefunc(cfg.updateHook, function() refreshList(cfg) end)
    refreshList(cfg)
end

local AUC_ID = "VuloClassicUI"

local function hasAuctionator()
    local a = _G.Auctionator
    return a and a.API and a.API.v1 and a.API.v1.GetAuctionPriceByItemID and true or false
end

local function aucPrice(itemID)
    if not itemID or not hasAuctionator() then return nil end
    local ok, price = pcall(_G.Auctionator.API.v1.GetAuctionPriceByItemID, AUC_ID, itemID)
    if ok and type(price) == "number" then return price end
    return nil
end

local function linkToID(link)
    return link and tonumber(link:match("item:(%d+)")) or nil
end

local function coin(c) return GetCoinTextureString and GetCoinTextureString(c) or (math.floor((c or 0) / 10000) .. "g") end

-- Bags come live from the tradeskill API; bank mats are cached per character so counts work away from the bank.
local function charKey()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

-- Container API moved to C_Container on newer clients; both paths are needed.
local function cSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
local function cItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
    return GetContainerItemID and GetContainerItemID(bag, slot)
end
local function cItemCount(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return (info and info.stackCount) or 0
    end
    if GetContainerItemInfo then local _, c = GetContainerItemInfo(bag, slot); return c or 0 end
    return 0
end

-- TBC bank containers; only readable while the bank window is open, hence the cache.
local BANK_BAGS = { -1, 5, 6, 7, 8, 9, 10, 11 }
local function scanBank()
    if not (mod.active and mod.db) then return end
    local counts = {}
    for _, bag in ipairs(BANK_BAGS) do
        for slot = 1, (cSlots(bag) or 0) do
            local id = cItemID(bag, slot)
            if id then counts[id] = (counts[id] or 0) + cItemCount(bag, slot) end
        end
    end
    mod.db.bank = mod.db.bank or {}
    mod.db.bank[charKey()] = counts
end

local function bankCount(itemID)
    if not (itemID and mod.db and mod.db.bank) then return 0 end
    local c = mod.db.bank[charKey()]
    return (c and c[itemID]) or 0
end

local bankWatcher = CreateFrame("Frame")
local bankOpen = false
bankWatcher:RegisterEvent("BANKFRAME_OPENED")
bankWatcher:RegisterEvent("BANKFRAME_CLOSED")
bankWatcher:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        bankOpen = true; scanBank(); bankWatcher:RegisterEvent("BAG_UPDATE")
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false; scanBank(); bankWatcher:UnregisterEvent("BAG_UPDATE")
    elseif event == "BAG_UPDATE" and bankOpen then
        scanBank()
    end
end)

local function hasCraftLib()
    local c = _G.CraftLib
    return (c and c.GetRecipeByItemId and c.IsReady and c:IsReady()) and true or false
end

-- Enchants produce no item, so they must be looked up by the enchant spell id in the link.
local function craftLibRecipe(dcfg)
    if not hasCraftLib() then return nil end
    local idx = dcfg.sel()
    if not idx or idx < 1 then return nil end
    local link = dcfg.itemLink(idx)
    if not link then return nil end
    local enchantId = tonumber(link:match("enchant:(%d+)"))
    if enchantId and dcfg.profession and _G.CraftLib.GetRecipeBySpellId then
        local ok, r = pcall(_G.CraftLib.GetRecipeBySpellId, _G.CraftLib, dcfg.profession, enchantId)
        if ok and r then return r end
    end
    local itemId = tonumber(link:match("item:(%d+)"))
    if itemId then
        local ok, r = pcall(_G.CraftLib.GetRecipeByItemId, _G.CraftLib, itemId)
        if ok and r then return r end
    end
    return nil
end

local SOURCE_LABELS = {
    trainer = "Trainer", vendor = "Vendor", drop = "Drop", reputation = "Reputation",
    quest = "Quest", starter = "Starter", discovery = "Discovery", world_drop = "World drop",
}
local DIFF_COL = { orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40c040", gray = "|cff909090" }

local function sourceText(recipe)
    local s = recipe and recipe.source
    if not s then return nil end
    local who  = s.npcName or s.zone or s.faction or ""
    local cost = s.trainingCost and (" " .. coin(s.trainingCost)) or ""
    return L["Source"] .. ": |cffffffff" .. L[SOURCE_LABELS[s.type] or "Source"]
        .. (who ~= "" and (" - " .. who) or "") .. cost .. "|r"
end

local function thresholdText(recipe)
    local r = recipe and recipe.skillRange
    if not r then return nil end
    return L["Levels"] .. ": " .. DIFF_COL.orange .. (r.orange or 0) .. "|r " .. DIFF_COL.yellow
        .. (r.yellow or 0) .. "|r " .. DIFF_COL.green .. (r.green or 0) .. "|r " .. DIFF_COL.gray
        .. (r.gray or 0) .. "|r"
end

local function skillupText(recipe, rank)
    if not (recipe and rank and _G.CraftLib and _G.CraftLib.GetRecipeDifficulty) then return nil end
    local diff = _G.CraftLib:GetRecipeDifficulty(recipe, rank)
    return L["Skill-up"] .. ": " .. (DIFF_COL[diff] or "|cffffffff") .. L[diff] .. "|r"
end

local DETAIL_KEYS = { "missing", "craftable", "value", "cost", "profit", "skillup", "thresholds", "source" }

local function buildBlock(dcfg)
    if dcfg._fs then return end
    local f, detail = _G[dcfg.frame], _G[dcfg.detail]
    if not (f and detail) then return end
    local fs = {}
    local function line(prev)
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if prev then t:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, 3)
        else         t:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 16, 22) end
        t:SetJustifyH("LEFT")
        return t
    end
    fs.missing    = line(nil)
    fs.craftable  = line(fs.missing)
    fs.profit     = line(fs.craftable)
    fs.cost       = line(fs.profit)
    fs.value      = line(fs.cost)
    fs.skillup    = line(fs.value)
    fs.thresholds = line(fs.skillup)
    fs.source     = line(fs.thresholds)
    dcfg._fs = fs
end

local function clearBlock(dcfg)
    if not dcfg._fs then return end
    for _, k in ipairs(DETAIL_KEYS) do dcfg._fs[k]:SetText("") end
end

local function updateDetail(dcfg)
    buildBlock(dcfg)
    local fs = dcfg._fs
    if not fs then return end

    local idx = dcfg.sel()
    if not idx or idx < 1 then clearBlock(dcfg); return end

    if mod.db.bankmats then
        local n = dcfg.numReagents(idx) or 0
        if n > 0 then
            local canMake, missing = math.huge, {}
            for r = 1, n do
                local rname, _, needed, haveBags = dcfg.reagentInfo(idx, r)
                needed = needed or 0
                if needed > 0 then
                    local have = (haveBags or 0) + bankCount(linkToID(dcfg.reagentLink(idx, r)))
                    local per  = math.floor(have / needed)
                    if per < canMake then canMake = per end
                    if have < needed then missing[#missing + 1] = (needed - have) .. "x " .. (rname or "?") end
                end
            end
            if canMake == math.huge then canMake = 0 end
            fs.craftable:SetText(L["Craftable"] .. ": |cffffffff" .. canMake .. "|r")
            fs.missing:SetText(#missing > 0 and (L["Missing"] .. ": |cffff7777" .. table.concat(missing, ", ") .. "|r") or "")
        else
            fs.craftable:SetText(""); fs.missing:SetText("")
        end
    else
        fs.craftable:SetText(""); fs.missing:SetText("")
    end

    if dcfg.prices and mod.db.prices and hasAuctionator() then
        local craftedID = linkToID(dcfg.itemLink(idx))
        local minMade = dcfg.numMade(idx) or 1
        if minMade < 1 then minMade = 1 end
        local value = aucPrice(craftedID)
        local cost, known = 0, true
        local n = dcfg.numReagents(idx) or 0
        for r = 1, n do
            local _, _, needed = dcfg.reagentInfo(idx, r)
            local p = aucPrice(linkToID(dcfg.reagentLink(idx, r)))
            if p then cost = cost + p * (needed or 1) else known = false end
        end
        if value then fs.value:SetText(L["AH value"] .. ": " .. coin(value * minMade))
        else          fs.value:SetText(L["AH value"] .. ": |cff888888?|r") end
        if n > 0 and known then fs.cost:SetText(L["Material cost"] .. ": " .. coin(cost))
        else                    fs.cost:SetText(L["Material cost"] .. ": |cff888888?|r") end
        if value and known and n > 0 then
            local profit = value * minMade - cost
            if profit >= 0 then fs.profit:SetText(L["Profit"] .. ": |cff20ff20" .. coin(profit) .. "|r")
            else                fs.profit:SetText(L["Profit"] .. ": |cffff5555-" .. coin(-profit) .. "|r") end
        else
            fs.profit:SetText("")
        end
    else
        fs.value:SetText(""); fs.cost:SetText(""); fs.profit:SetText("")
    end

    local cr = craftLibRecipe(dcfg)
    fs.skillup:SetText((mod.db.showSkillup and skillupText(cr, dcfg.skill())) or "")
    fs.thresholds:SetText((mod.db.showThresholds and thresholdText(cr)) or "")
    fs.source:SetText((mod.db.showSource and sourceText(cr)) or "")
end

local function installDetail(dcfg)
    if not dcfg or dcfg._hooked then return end
    if not _G[dcfg.updateHook] then return end
    dcfg._hooked = true
    hooksecurefunc(dcfg.updateHook, function() updateDetail(dcfg) end)

    if hasCraftLib() and _G[dcfg.list] then
        -- {label, dbKey, gap, width}; gap is measured from the list for the first entry, else from the previous button.
        local defs = {
            { L["Source"],   "showSource",     -8, 108 },
            { L["Levels"],   "showThresholds", 2,  96 },
            { L["Skill-up"], "showSkillup",    0,  96 },
        }
        local prev
        for _, d in ipairs(defs) do
            local key = d[2]
            local b = CreateFrame("Button", nil, _G[dcfg.frame], "UIPanelButtonTemplate")
            b:SetSize(d[4] or 96, 20)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", d[3], 0)
            else b:SetPoint("TOPLEFT", _G[dcfg.list], "BOTTOMLEFT", d[3], -1) end
            b:SetText(d[1])
            local function refresh()
                local on = mod.db[key]
                b:GetFontString():SetTextColor(on and 1 or 0.6, on and 0.82 or 0.6, on and 0 or 0.6)
            end
            b:SetScript("OnClick", function() mod.db[key] = not mod.db[key]; refresh(); updateDetail(dcfg) end)
            refresh()
            prev = b
        end
    end

    updateDetail(dcfg)
end

-- CraftFrame has no sellable item, so prices are off and lookups go through the spell id.
local DETAIL_CFG = {
    TradeSkillFrame = {
        frame = "TradeSkillFrame", detail = "TradeSkillDetailScrollFrame", list = "TradeSkillListScrollFrame",
        updateHook = "TradeSkillFrame_SetSelection", prices = true,
        sel         = function() return GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex() end,
        itemLink    = function(i) return GetTradeSkillItemLink and GetTradeSkillItemLink(i) end,
        numMade     = function(i) return GetTradeSkillNumMade and GetTradeSkillNumMade(i) end,
        numReagents = function(i) return GetTradeSkillNumReagents and GetTradeSkillNumReagents(i) end,
        reagentInfo = function(i, r) return GetTradeSkillReagentInfo(i, r) end,
        reagentLink = function(i, r) return GetTradeSkillReagentItemLink(i, r) end,
        skill       = function() if not GetTradeSkillLine then return nil end local _, rank = GetTradeSkillLine() return rank end,
    },
    CraftFrame = {
        frame = "CraftFrame", detail = "CraftDetailScrollFrame", list = "CraftListScrollFrame",
        updateHook = "CraftFrame_SetSelection", prices = false, profession = "enchanting",
        sel         = function() return GetCraftSelectionIndex and GetCraftSelectionIndex() end,
        itemLink    = function(i) return GetCraftItemLink and GetCraftItemLink(i) end,
        numMade     = function() return 1 end,
        numReagents = function(i) return GetCraftNumReagents and GetCraftNumReagents(i) end,
        reagentInfo = function(i, r) return GetCraftReagentInfo(i, r) end,
        reagentLink = function(i, r) return GetCraftReagentItemLink(i, r) end,
        skill       = function() if not GetCraftDisplaySkillLine then return nil end local _, rank = GetCraftDisplaySkillLine() return rank end,
    },
}

local function refreshAllDetails()
    for _, dcfg in pairs(DETAIL_CFG) do
        local f = _G[dcfg.frame]
        if f and f:IsShown() then updateDetail(dcfg) end
    end
end

local function setupFrame(cfg)
    local st = states[cfg.frame]
    if not st then st = {}; states[cfg.frame] = st end
    if st.done then return end
    local f = _G[cfg.frame]
    if not f then return end
    st.done = true

    if mod.db.larger then
        pcall(function()
            -- never write UIPanelWindows directly: that taints Blizzard's panel
            -- system and locks the character sheet and spellbook in combat
            ns:SetPanelLayout(f, { area = "override", pushable = 1,
                xoffset = -16, yoffset = 12, bottomClampOverride = 152,
                width = 685, height = 487, whileDead = 1 })
            f:SetWidth(714)
            f:SetHeight(487 + TALL)

            local title = _G[cfg.title]
            if title then title:ClearAllPoints(); title:SetPoint("TOP", f, "TOP", 0, -18) end

            local listH = 336 + TALL
            local list = _G[cfg.list]
            if list then
                list:ClearAllPoints()
                list:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -75)
                list:SetSize(295, listH)
            end

            local old = _G[cfg.displayed] or 0
            if cfg.costFmt then
                local c1, b1 = _G[cfg.costFmt:format(1)], _G[cfg.rowFmt:format(1)]
                if c1 and b1 then c1:ClearAllPoints(); c1:SetPoint("RIGHT", b1, "RIGHT", -30, 0) end
            end
            for i = 2, old do
                local b, prev = _G[cfg.rowFmt:format(i)], _G[cfg.rowFmt:format(i - 1)]
                if b and prev then b:ClearAllPoints(); b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1) end
                if cfg.costFmt then
                    local cost = _G[cfg.costFmt:format(i)]
                    if cost and b then cost:ClearAllPoints(); cost:SetPoint("RIGHT", b, "RIGHT", -30, 0) end
                end
            end

            -- Derive the row count from the list height; the client's default no longer fits.
            local rowH = 16
            local b1 = _G[cfg.rowFmt:format(1)]
            if b1 and b1.GetHeight and (b1:GetHeight() or 0) > 0 then rowH = b1:GetHeight() end
            local fitRows = math.max(1, math.floor((listH - 2) / rowH))

            for i = old + 1, fitRows do
                local prev = _G[cfg.rowFmt:format(i - 1)]
                if not _G[cfg.rowFmt:format(i)] and prev then
                    local b = CreateFrame("Button", cfg.rowFmt:format(i), f, cfg.rowTemplate)
                    b:SetID(i); b:Hide(); b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1)
                    if cfg.costFmt then
                        local cost = _G[cfg.costFmt:format(i)]
                        if cost then cost:ClearAllPoints(); cost:SetPoint("RIGHT", b, "RIGHT", -30, 0) end
                    end
                end
            end
            for i = fitRows + 1, old do
                local b = _G[cfg.rowFmt:format(i)]
                if b then b:Hide() end
            end
            _G[cfg.displayed] = fitRows

            -- Blizzard resets the width on every Show, so the hook has to reapply it.
            if cfg.highlight and _G[cfg.highlight] then
                hooksecurefunc(_G[cfg.highlight], "Show", function()
                    _G[cfg.highlight]:SetWidth(290)
                end)
            end

            local detail = _G[cfg.detail]
            if detail then
                detail:ClearAllPoints()
                detail:SetPoint("TOPLEFT", f, "TOPLEFT", 352, -74)
                detail:SetSize(298, 336 + TALL)
            end
            for _, tn in ipairs(cfg.detailTex) do
                local t = _G[tn]; if t and t.SetAlpha then t:SetAlpha(0) end
            end

            local create, cancel, close = _G[cfg.create], _G[cfg.cancel], _G[cfg.close]
            if create and cancel then create:ClearAllPoints(); create:SetPoint("RIGHT", cancel, "LEFT", -1, 0) end
            if cancel then
                cancel:SetSize(80, 22)
                cancel:ClearAllPoints()
                cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -42, 54)
            end
            if close then close:ClearAllPoints(); close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -8) end

            if cfg.expand and _G[cfg.expand] then _G[cfg.expand]:Hide() end
            for _, n in ipairs(cfg.extraHide or {}) do
                local e = _G[n]
                if e then if e.SetSize then e:SetSize(1, 1) end; if e.Hide then e:Hide() end end
            end

            if cfg.repos then cfg.repos(f) end

            -- Two slices of the parchment atlas cover the frame; regions 2/3 are its background textures.
            local regs = { f:GetRegions() }
            local r2, r3 = regs[2], regs[3]
            if r2 and r3 and r2.SetTexture and r3.SetTexture then
                r2:SetTexture(PARCHMENT); r2:SetTexCoord(0.25, 0.75, 0, 0.5); r2:SetSize(512, 512)
                r3:ClearAllPoints(); r3:SetPoint("TOPLEFT", r2, "TOPRIGHT", 0, 0)
                r3:SetTexture(PARCHMENT); r3:SetTexCoord(0.75, 1, 0, 0.5); r3:SetSize(256, 512)
                for _, idx in ipairs(cfg.hideRegions) do
                    local rr = regs[idx]; if rr and rr.Hide then rr:Hide() end
                end
                st.regs = { r2, r3 }
            end
        end)
    else
        -- The theme recolours these two regions, so they have to be recorded
        -- even when the window is not enlarged. Collecting them only inside the
        -- branch above left applyTheme with nothing to work on, which made the
        -- Theme dropdown permanently inert for anyone with "Larger profession
        -- window" off. The quest log fills its own list in both branches for
        -- exactly this reason.
        pcall(function()
            local regs = { f:GetRegions() }
            local r2, r3 = regs[2], regs[3]
            if r2 and r3 and r2.SetVertexColor and r3.SetVertexColor then
                st.regs = { r2, r3 }
            end
        end)
    end

    applyTheme(cfg)
    installListEnhancements(cfg)
    installDetail(DETAIL_CFG[cfg.frame])
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if not mod.active then return end
    for _, cfg in ipairs(FRAMES) do
        if name == cfg.addon then C_Timer.After(0, function() setupFrame(cfg) end) end
    end
end)

function mod:OnEnable()
    for _, cfg in ipairs(FRAMES) do
        if isLoaded(cfg.addon) then setupFrame(cfg) end
    end
end

function mod:OnDisable()
    -- The enlarge isn't cleanly reversible at runtime; a /reload restores it.
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Profession Window"] },
        { type = "desc", text = L["|cffaaaaaaEnlarges the Tradeskill and Craft windows so the detail sits beside the recipe list, with a Parchment or Dark look.|r"] },

        { type = "spacer", height = 6 },
        { type = "toggle", label = L["Larger profession window"],
          tooltip = L["Enlarges the profession windows so more recipes are visible with the detail pane beside the list. /reload to fully apply or revert."],
          get = function() return mod.db.larger end,
          set = function(_, v)
              mod.db.larger = v
              ns:Print(L["Profession window size changed. /reload recommended."])
          end },
        { type = "dropdown", label = L["Theme"], width = 240,
          values = {
              { value = "parchment", text = L["Parchment (default)"] },
              { value = "dark",      text = L["Dark"] },
          },
          get = function() return mod.db.theme end,
          set = function(_, v) mod.db.theme = v; for _, cfg in ipairs(FRAMES) do applyTheme(cfg) end end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Recipes"] },
        { type = "toggle", label = L["Favourites first"],
          tooltip = L["Recipes you marked with the star float to the top of the list."],
          get = function() return mod.db.favFirst ~= false end,
          set = function(_, v)
              mod.db.favFirst = v and true or false
              if _G.TradeSkillFrame and _G.TradeSkillFrame:IsShown() and _G.TradeSkillFrame_Update then pcall(_G.TradeSkillFrame_Update) end
              if _G.CraftFrame and _G.CraftFrame:IsShown() and _G.CraftFrame_Update then pcall(_G.CraftFrame_Update) end
          end },
        { type = "toggle", label = L["Show craftable count"],
          tooltip = L["Shows how many of each recipe you can make right now, like [12]."],
          get = function() return mod.db.counts end,
          set = function(_, v)
              mod.db.counts = v
              if _G.TradeSkillFrame and _G.TradeSkillFrame:IsShown() and _G.TradeSkillFrame_Update then pcall(_G.TradeSkillFrame_Update) end
              if _G.CraftFrame and _G.CraftFrame:IsShown() and _G.CraftFrame_Update then pcall(_G.CraftFrame_Update) end
          end },
        { type = "toggle", label = L["Craftable count incl. bank + missing mats"],
          tooltip = L["On the selected recipe, shows how many you can craft counting your bank mats too, and lists what's still missing. Bank mats are remembered from your last visit to the bank."],
          get = function() return mod.db.bankmats end,
          set = function(_, v) mod.db.bankmats = v; refreshAllDetails() end },
        { type = "desc", text = L["|cff888888Click a recipe's star (or right-click the recipe) to favourite it — the star turns gold.|r"] },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Auction value"] },
        { type = "toggle", label = L["Show auction value & profit"],
          tooltip = L["On the selected recipe, shows the crafted item's auction value, material cost and profit, using Auctionator's price data."],
          get = function() return mod.db.prices end,
          set = function(_, v)
              mod.db.prices = v
              refreshAllDetails()
          end },
        { type = "desc", text = hasAuctionator()
            and L["|cff1eff00Auctionator found — prices from its data.|r"]
            or  L["|cffff5555Auctionator not found. Install Auctionator to get price data.|r"] },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Recipe info (CraftLib)"] },
        { type = "desc", text = L["|cffaaaaaaThree buttons under the recipe list toggle extra info on the selected recipe: source (where to learn/get it), skill levels (orange/yellow/green/grey) and your skill-up chance.|r"] },
        { type = "desc", text = hasCraftLib()
            and L["|cff1eff00CraftLib found — recipe source & levels available.|r"]
            or  L["|cffff5555CraftLib not found. Install CraftLib to show recipe source & levels.|r"] },
    }
end
end)(...);

(function(...)
-- Quest log: levels/IDs in titles, an enlarged frame, Parchment or Dark theme.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("questlog", {
    name        = "Quest Log",
    group       = "Character",
    description = "Enhances the quest log: quest levels (and optional quest IDs) in the titles, a larger frame, and a Parchment or Dark theme.",
    defaults = {
        enabled  = true,
        levels   = true,
        questIDs = false,
        larger   = true,
        theme    = "parchment",
    },
})

-- TBC 2.5.5 has no C_QuestLog.GetInfo; the classic global API is the only one available.
local GetQuestLogTitle      = GetQuestLogTitle
local GetNumQuestLogEntries = GetNumQuestLogEntries
local GetQuestLogSelection  = GetQuestLogSelection
local format                = string.format

-- Atlas whose top half holds the quest-log parchment; sliced by SetTexCoord below.
local PARCHMENT = "Interface\\AddOns\\VuloClassicUI\\Media\\textures\\questlog-parchment"

local hooked   = false
local enlarged = false
local bgDone   = false

local function formatTitle(title, level, questID)
    local prefix = (mod.db.levels and level and level > 0) and format("[%d] ", level) or ""
    local idTag  = (mod.db.questIDs and questID and questID > 0) and format(" |cff808080(%d)|r", questID) or ""
    return prefix .. title .. idTag
end

local function updateListLevels()
    if not mod.active then return end
    if not (mod.db.levels or mod.db.questIDs) then return end
    local numEntries = GetNumQuestLogEntries()
    if not numEntries or numEntries == 0 then return end
    local offset = (_G.FauxScrollFrame_GetOffset and _G.QuestLogListScrollFrame
        and _G.FauxScrollFrame_GetOffset(_G.QuestLogListScrollFrame)) or 0
    for i = 1, (_G.QUESTS_DISPLAYED or 0) do
        local idx = i + offset
        if idx <= numEntries then
            local btn = _G["QuestLogTitle" .. i]
            local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(idx)
            if btn and title and not isHeader and level and level > 0 then
                local txt = "  " .. formatTitle(title, level, questID)
                btn:SetText(txt)
                if _G.QuestLogDummyText then _G.QuestLogDummyText:SetText(txt) end
            end
        end
    end
end

local function lightenDetailText()
    local sc = _G.QuestLogDetailScrollChildFrame
    if not sc then return end
    local function walk(frame)
        if frame.GetRegions then
            for _, r in ipairs({ frame:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "FontString" and r.GetTextColor then
                    local cr, cg, cb = r:GetTextColor()
                    if cr and (cr + cg + cb) < 1.2 then
                        r:SetTextColor(0.92, 0.90, 0.84)
                    end
                end
            end
        end
        if frame.GetChildren then
            for _, c in ipairs({ frame:GetChildren() }) do walk(c) end
        end
    end
    pcall(walk, sc)
end

local function updateDetail()
    if not mod.active then return end
    if mod.db.levels or mod.db.questIDs then
        local q = GetQuestLogSelection and GetQuestLogSelection()
        if q and _G.QuestLogQuestTitle then
            local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(q)
            if title and not isHeader and level and level > 0 then
                _G.QuestLogQuestTitle:SetText(formatTitle(title, level, questID))
            end
        end
    end
    if mod.db.theme == "dark" then lightenDetailText() end
end

local function installHooks()
    if hooked then return end
    hooked = true
    if _G.QuestLog_Update then hooksecurefunc("QuestLog_Update", updateListLevels) end
    if _G.QuestLog_UpdateQuestDetails then hooksecurefunc("QuestLog_UpdateQuestDetails", updateDetail) end
end

-- Regions 3-6 of QuestLogFrame are its parchment textures; retexture them in place.
local function setupBg()
    if bgDone then return end
    local QLF = _G.QuestLogFrame
    if not QLF then return end
    bgDone = true
    pcall(function()
        local regs = { QLF:GetRegions() }
        local q = {}
        for i = 3, 6 do
            local r = regs[i]
            if r and r.GetObjectType and r:GetObjectType() == "Texture" then q[i] = r end
        end

        if enlarged and q[3] and q[4] then
            q[3]:SetTexture(PARCHMENT)
            q[3]:SetTexCoord(0.25, 0.75, 0, 0.5)
            q[3]:SetSize(512, 512)

            q[4]:ClearAllPoints()
            q[4]:SetPoint("TOPLEFT", q[3], "TOPRIGHT", 0, 0)
            q[4]:SetTexture(PARCHMENT)
            q[4]:SetTexCoord(0.75, 1, 0, 0.5)
            q[4]:SetSize(256, 512)

            if q[5] then q[5]:Hide() end
            if q[6] then q[6]:Hide() end
            QLF._vcuiRegs = { q[3], q[4] }
        else
            local list = {}
            for i = 3, 6 do if q[i] then list[#list + 1] = q[i] end end
            QLF._vcuiRegs = list
        end
    end)
end

local function applyTheme()
    local QLF = _G.QuestLogFrame
    if not QLF then return end
    local dark = (mod.db.theme == "dark")
    if QLF._vcuiRegs then
        for _, r in ipairs(QLF._vcuiRegs) do
            if r.SetDesaturated then r:SetDesaturated(dark) end
            if dark then r:SetVertexColor(0.16, 0.15, 0.14, 1)
            else        r:SetVertexColor(1, 1, 1, 1) end
        end
    end
    if dark then lightenDetailText() end
    if _G.QuestLog_Update then pcall(_G.QuestLog_Update) end
end

local function enlarge()
    if enlarged or not mod.db.larger then return end
    local QLF = _G.QuestLogFrame
    if not QLF then return end
    enlarged = true
    pcall(function()
        local tall, extra = 73, 21

        -- never write UIPanelWindows directly: that taints Blizzard's panel
        -- system and locks the character sheet and spellbook in combat
        ns:SetPanelLayout(QLF, { area = "override", pushable = 0,
            xoffset = -16, yoffset = 12, bottomClampOverride = 152,
            width = 685, height = 487, whileDead = 1 })

        QLF:SetWidth(714)
        QLF:SetHeight(487 + tall)

        if _G.QuestLogTitleText then
            _G.QuestLogTitleText:ClearAllPoints()
            _G.QuestLogTitleText:SetPoint("TOP", QLF, "TOP", 0, -18)
        end

        if _G.QuestLogDetailScrollFrame and _G.QuestLogListScrollFrame then
            _G.QuestLogDetailScrollFrame:ClearAllPoints()
            _G.QuestLogDetailScrollFrame:SetPoint("TOPLEFT", _G.QuestLogListScrollFrame, "TOPRIGHT", 31, 1)
            _G.QuestLogDetailScrollFrame:SetHeight(336 + tall)
            _G.QuestLogListScrollFrame:SetHeight(336 + tall)
        end

        local old = _G.QUESTS_DISPLAYED or 0
        _G.QUESTS_DISPLAYED = old + extra
        for i = old + 1, _G.QUESTS_DISPLAYED do
            if not _G["QuestLogTitle" .. i] and _G["QuestLogTitle" .. (i - 1)] then
                local b = CreateFrame("Button", "QuestLogTitle" .. i, QLF, "QuestLogTitleButtonTemplate")
                b:SetID(i)
                b:Hide()
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", _G["QuestLogTitle" .. (i - 1)], "BOTTOMLEFT", 0, 1)
            end
        end

        local function placeBtn(name, w, h, point, rel, relPoint, x, y)
            local b = _G[name]
            if not b then return end
            if w then b:SetSize(w, h) end
            b:ClearAllPoints()
            b:SetPoint(point, rel, relPoint, x, y)
        end
        placeBtn("QuestLogFrameAbandonButton", 110, 21, "BOTTOMLEFT", QLF, "BOTTOMLEFT", 17, 54)
        placeBtn("QuestFramePushQuestButton", 100, 21, "LEFT", _G.QuestLogFrameAbandonButton, "RIGHT", -3, 0)
        placeBtn("QuestFrameExitButton", 80, 22, "BOTTOMRIGHT", QLF, "BOTTOMRIGHT", -42, 54)
    end)
end

local function setup()
    enlarge()
    setupBg()
    applyTheme()
    if _G.QuestLog_Update then pcall(_G.QuestLog_Update) end
end

function mod:OnEnable()
    installHooks()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, setup)
    else
        setup()
    end
end

function mod:OnDisable()
    -- hooksecurefunc cannot be undone; the hooks stay and gate on mod.active.
    -- The enlarged frame and retextured background need a /reload to revert.
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Quest Log"] },
        { type = "desc", text = L["|cffaaaaaaShows quest levels (and optionally IDs) in the quest log, can enlarge it, and lets you pick a Parchment or Dark look.|r"] },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Titles"] },
        { type = "toggle", label = L["Show quest levels"],
          get = function() return mod.db.levels end,
          set = function(_, v) mod.db.levels = v; if _G.QuestLog_Update then pcall(_G.QuestLog_Update) end end },
        { type = "toggle", label = L["Show quest IDs"],
          get = function() return mod.db.questIDs end,
          set = function(_, v) mod.db.questIDs = v; if _G.QuestLog_Update then pcall(_G.QuestLog_Update) end end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Frame"] },
        { type = "toggle", label = L["Larger quest log"],
          tooltip = L["Enlarges the quest log so more quests are visible with the detail pane beside the list. /reload to fully apply or revert."],
          get = function() return mod.db.larger end,
          set = function(_, v)
              mod.db.larger = v
              if v then enlarge(); setupBg(); applyTheme() end
              ns:Print(L["Quest log size changed. /reload recommended."])
          end },
        { type = "dropdown", label = L["Theme"], width = 240,
          values = {
              { value = "parchment", text = L["Parchment (default)"] },
              { value = "dark",      text = L["Dark"] },
          },
          get = function() return mod.db.theme end,
          set = function(_, v) mod.db.theme = v; applyTheme() end },
    }
end
end)(...);

(function(...)
-- Casting on a bag item is protected: one hardware click on a SecureActionButton = one disenchant, and every secure attribute write is guarded by InCombatLockdown().
local _, ns = ...
local L = ns.L

local DISENCHANT_SPELL_ID = 13262

local mod = ns:RegisterModule("disenchantqueue", {
    name        = "Disenchant Queue",
    group       = "Bags & Items",
    description = "For enchanters: a window with one button that disenchants your bag items one click each, auto-advancing through the queue (no casting + picking each item by hand).",
    defaults = {
        enabled    = true,
        minQuality = 2,   -- 2 Uncommon, 3 Rare, 4 Epic
        maxQuality = 3,
        point      = nil,
        ignore     = {},  -- [itemID] = itemLink, persistent
    },
})

local EXCLUDE_EQUIP = { INVTYPE_TABARD = true, INVTYPE_BODY = true }

local sessionIgnore = {}
local win

local function isEnchanter()
    if IsSpellKnown and IsSpellKnown(DISENCHANT_SPELL_ID) then return true end
    if IsPlayerSpell and IsPlayerSpell(DISENCHANT_SPELL_ID) then return true end
    return false
end

local function containerInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local i = C_Container.GetContainerItemInfo(bag, slot)
        if i then return i.itemID, i.quality, i.hyperlink, i.iconFileID, i.isLocked, i.isBound end
        return nil
    elseif _G.GetContainerItemInfo then
        local icon, _, locked, quality, _, _, link, _, _, itemID, isBound = _G.GetContainerItemInfo(bag, slot)
        return itemID, quality, link, icon, locked, isBound
    end
end

local function numSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    return _G.GetContainerNumSlots and _G.GetContainerNumSlots(bag) or 0
end

local function eligible(itemID, quality, locked)
    if not itemID or locked then return false end
    if not quality or quality < mod.db.minQuality or quality > mod.db.maxQuality then return false end
    local _, _, _, equipLoc, _, classID, subClassID = GetItemInfoInstant(itemID)
    if classID ~= 2 and classID ~= 4 then return false end   -- 2 Weapon, 4 Armor
    if EXCLUDE_EQUIP[equipLoc] then return false end          -- tabard / shirt
    if classID == 2 and subClassID == 20 then return false end -- fishing pole
    return true
end

local function findNext()
    for bag = 0, 4 do
        for slot = 1, numSlots(bag) do
            if not sessionIgnore[bag .. "-" .. slot] then
                local itemID, quality, link, icon, locked, isBound = containerInfo(bag, slot)
                if eligible(itemID, quality, locked) and not mod.db.ignore[itemID] then
                    return { bag = bag, slot = slot, itemID = itemID, link = link,
                             icon = icon, bound = isBound and true or false }
                end
            end
        end
    end
end

local function countRemaining()
    local n = 0
    for bag = 0, 4 do
        for slot = 1, numSlots(bag) do
            if not sessionIgnore[bag .. "-" .. slot] then
                local itemID, quality, _, _, locked = containerInfo(bag, slot)
                if eligible(itemID, quality, locked) and not mod.db.ignore[itemID] then n = n + 1 end
            end
        end
    end
    return n
end

local current

local function clearButton()
    local b = win and win.cast
    if not b or InCombatLockdown() then return end
    b:SetAttribute("spell", nil);       b:SetAttribute("*spell1", nil)
    b:SetAttribute("target-bag", nil);  b:SetAttribute("*target-bag1", nil)
    b:SetAttribute("target-slot", nil); b:SetAttribute("*target-slot1", nil)
    b:Disable()
end

local function loadNext()
    if not win or not win:IsShown() then return end
    if InCombatLockdown() then return end  -- retried on PLAYER_REGEN_ENABLED
    local e = findNext()
    current = e
    local b = win.cast
    if e then
        b:SetAttribute("spell", DISENCHANT_SPELL_ID)
        b:SetAttribute("*spell1", DISENCHANT_SPELL_ID)
        b:SetAttribute("target-bag", e.bag)
        b:SetAttribute("*target-bag1", e.bag)
        b:SetAttribute("target-slot", e.slot)
        b:SetAttribute("*target-slot1", e.slot)
        b:Enable()
        win.icon:SetTexture(e.icon)
        win.icon:Show()
        win.itemText:SetText(e.link or "?")
        win.countText:SetText(string.format(L["%d item(s) to disenchant"], countRemaining()))
        if win.ilvl then
            local lvl = e.link and ((GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(e.link))
                or (GetItemInfo and select(4, GetItemInfo(e.link))))
            win.ilvl:SetText((lvl and lvl > 1) and lvl or "")
        end
        if win.bind then
            local tag = ""
            if e.bound then
                tag = "|cff9d9d9dBoP|r"
            elseif e.link and GetItemInfo then
                local bindType = select(14, GetItemInfo(e.link))
                if bindType == 2 then tag = "|cff73bfffBoE|r"
                elseif bindType == 3 then tag = "|cff73bfffBoU|r" end
            end
            win.bind:SetText(tag)
        end
        if win.setWarn then
            local sets = ns.ItemSetMembership and ns.ItemSetMembership(e.itemID)
            if sets then
                win.setWarn:SetText(string.format(L["Part of set: %s"], sets))
                win.setWarn:Show()
            else
                win.setWarn:Hide()
            end
        end
    else
        b:SetAttribute("spell", nil);       b:SetAttribute("*spell1", nil)
        b:SetAttribute("target-bag", nil);  b:SetAttribute("*target-bag1", nil)
        b:SetAttribute("target-slot", nil); b:SetAttribute("*target-slot1", nil)
        b:Disable()
        win.icon:Hide()
        win.itemText:SetText(L["|cff888888Nothing to disenchant.|r"])
        win.countText:SetText("")
        if win.ilvl then win.ilvl:SetText("") end
        if win.bind then win.bind:SetText("") end
        if win.setWarn then win.setWarn:Hide() end
    end
end

local function buildWindow()
    if win then return win end

    local f = CreateFrame("Frame", "VuloClassicUIDisenchantWindow", UIParent, "BackdropTemplate")
    f:SetSize(280, 184)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    f:EnableMouse(true)
    -- one-time migration of the legacy point-anchor save to a CENTER offset
    local p = mod.db.point
    if p then
        f:ClearAllPoints()
        f:SetPoint(p.p or "CENTER", UIParent, p.p or "CENTER", p.x or 0, p.y or 0)
        local fx, fy = f:GetCenter()
        local px, py = UIParent:GetCenter()
        if fx and px then mod.db.x, mod.db.y = fx - px, fy - py end
        mod.db.point = nil
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
    f.mover = ns:CreateMover(f, { key = "disenchantqueue", label = "|cffffffff" .. L["Disenchant Queue"] .. "|r", db = mod.db, width = 280, height = 184,
        scalable = true, anchorable = true })

    -- only the cast button child is protected, so moving the frame itself is legal
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = ns:GetCenterOffsets(self)
        if x and y then
            mod.db.x, mod.db.y = x, y
            if ns.ApplyMover and f.mover then ns:ApplyMover(f.mover) end
        end
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText((ns.C and ns.C.accent or "|cff9b6cff") .. L["Disenchant Queue"] .. "|r")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(32, 32)
    f.icon:SetPoint("TOPLEFT", 12, -34)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.itemText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.itemText:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
    f.itemText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.itemText:SetJustifyH("LEFT")
    f.itemText:SetWordWrap(false)

    f.ilvl = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    f.ilvl:SetPoint("TOPLEFT", f.icon, "TOPLEFT", 1, -1)
    f.ilvl:SetTextColor(1, 1, 1)
    f.bind = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    f.bind:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", -1, 1)
    if ns.UI and ns.UI.FONT_PATH then
        pcall(f.ilvl.SetFont, f.ilvl, ns.UI.FONT_PATH, 10, "OUTLINE")
        pcall(f.bind.SetFont, f.bind, ns.UI.FONT_PATH, 9, "OUTLINE")
    end

    local hover = CreateFrame("Button", nil, f)
    hover:SetPoint("TOPLEFT", f.icon, "TOPLEFT", 0, 0)
    hover:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMLEFT", 0, 0)
    hover:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    hover:SetScript("OnEnter", function(self)
        if current and ns.UI:OpenTooltip(self, "ANCHOR_RIGHT") then
            GameTooltip:SetBagItem(current.bag, current.slot)
            GameTooltip:Show()
        end
    end)
    hover:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
    hover:RegisterForDrag("LeftButton")
    hover:SetScript("OnDragStart", function() local h = f:GetScript("OnDragStart"); if h then h(f) end end)
    hover:SetScript("OnDragStop",  function() local h = f:GetScript("OnDragStop");  if h then h(f) end end)

    f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.countText:SetPoint("TOPLEFT", f.icon, "BOTTOMLEFT", 0, -6)

    f.setWarn = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.setWarn:SetPoint("TOPLEFT", f.countText, "BOTTOMLEFT", 0, -3)
    f.setWarn:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.setWarn:SetJustifyH("LEFT")
    f.setWarn:SetWordWrap(false)
    f.setWarn:SetTextColor(1, 0.55, 0.2)
    f.setWarn:Hide()

    local cast = CreateFrame("Button", "VuloClassicUIDisenchantButton", f,
        "UIPanelButtonTemplate, SecureActionButtonTemplate")
    cast:SetSize(256, 28)
    cast:SetPoint("BOTTOMLEFT", 12, 46)
    cast:SetText(L["Disenchant"])
    -- 2.5.5: the secure cast only fires via the "*" wildcard attributes with AnyUp+AnyDown registration
    cast:RegisterForClicks("AnyUp", "AnyDown")
    cast:SetAttribute("type", "spell")
    cast:SetAttribute("*type1", "spell")
    cast:SetAttribute("unit", "none")
    cast:Disable()
    cast:HookScript("PostClick", function()
        if current then win.countText:SetText(L["Disenchanting…"]) end
    end)
    f.cast = cast

    local function tip(button, textKey)
        ns.UI:AttachTooltip(button, { anchor = "ANCHOR_TOP", title = L[textKey], wrap = true })
    end

    local skip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    skip:SetSize(124, 24)
    skip:SetPoint("BOTTOMLEFT", 12, 12)
    skip:SetText(L["Skip"])
    skip:SetScript("OnClick", function()
        if current then sessionIgnore[current.bag .. "-" .. current.slot] = true end
        loadNext()
    end)
    tip(skip, "Skip this item for now (it comes back next time).")

    local ignore = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    ignore:SetSize(124, 24)
    ignore:SetPoint("BOTTOMRIGHT", -12, 12)
    ignore:SetText(L["Ignore"])
    ignore:SetScript("OnClick", function()
        if current and current.itemID then
            mod.db.ignore[current.itemID] = current.link or true
        end
        loadNext()
    end)
    tip(ignore, "Never disenchant this item (add it to the ignore list).")

    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" or event == "BAG_UPDATE_DELAYED" then
            if f:IsShown() then loadNext() end
        end
    end)

    f:SetScript("OnShow", function() sessionIgnore = {}; loadNext() end)
    f:SetScript("OnHide", function() clearButton() end)

    win = f
    return f
end

function mod:OpenWindow()
    if not isEnchanter() then
        ns:Print(L["You need the Enchanting profession (Disenchant) to use this."])
        return
    end
    buildWindow()
    if win:IsShown() then loadNext() else win:Show() end
end

function mod:ToggleWindow()
    if win and win:IsShown() then win:Hide() else mod:OpenWindow() end
end

function mod:OnEnable()
    ns:RegisterSlash({ key = "DISENCHANT", commands = { "/disenchant", "/entzaubern" },
        desc = "Disenchant the queued items one after another.",
        module = "disenchantqueue",
    })
    ns.Slash.DISENCHANT = function()
        if mod._enabled then mod:ToggleWindow() else ns:Print(L["This module is disabled."]) end
    end
end

function mod:OnDisable()
    if win then win:Hide() end
end

local QUALITY_VALUES = {
    { value = 2, text = "|cff1eff00" .. (_G.ITEM_QUALITY2_DESC or "Uncommon") .. "|r" },
    { value = 3, text = "|cff0070dd" .. (_G.ITEM_QUALITY3_DESC or "Rare") .. "|r" },
    { value = 4, text = "|cffa335ee" .. (_G.ITEM_QUALITY4_DESC or "Epic") .. "|r" },
}

local function refreshOptions()
    local UI = ns.UI
    if UI and UI.BuildOptionsPage and UI.currentModule then
        UI:BuildOptionsPage(UI.currentModule, UI.currentTab or "default")
    end
end

function mod:GetOptions()
    local opts = {
        { type = "header", text = L["Disenchant Queue"] },
        { type = "desc", text = L["|cffaaaaaaA window with one button that disenchants your bag items one click each and auto-advances through the queue. WoW does not allow fully unattended disenchanting, so this is one click per item — but you never have to cast and pick each item by hand again.|r"] },

        { type = "desc", text = isEnchanter()
            and L["|cff1eff00You know Disenchant.|r"]
            or  L["|cffff5555You are not an enchanter — this tool will do nothing.|r"] },

        { type = "spacer", height = 6 },
        { type = "button", label = L["Open disenchant queue"],
          onClick = function() mod:OpenWindow() end },
        { type = "desc", text = L["|cff888888Also: /disenchant or /entzaubern|r"] },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Quality range"] },
        { type = "dropdown", label = L["Lowest quality"], width = 200, values = QUALITY_VALUES,
          get = function() return mod.db.minQuality end,
          set = function(_, v)
              mod.db.minQuality = v
              if v > mod.db.maxQuality then mod.db.maxQuality = v end
              if win and win:IsShown() then loadNext() end
          end },
        { type = "dropdown", label = L["Highest quality"], width = 200, values = QUALITY_VALUES,
          get = function() return mod.db.maxQuality end,
          set = function(_, v)
              mod.db.maxQuality = v
              if v < mod.db.minQuality then mod.db.minQuality = v end
              if win and win:IsShown() then loadNext() end
          end },
        { type = "desc", text = L["|cff888888Only weapons and armour are listed. Each item is shown before you click, so you always see what you are about to disenchant.|r"] },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Ignored items"] },
    }

    local ids = {}
    for id in pairs(mod.db.ignore) do ids[#ids + 1] = id end
    table.sort(ids)

    if #ids == 0 then
        opts[#opts + 1] = { type = "desc", text = L["|cff888888No ignored items yet. Use the Ignore button in the window to protect an item.|r"] }
    else
        opts[#opts + 1] = { type = "desc", text = L["|cff888888Click an entry to remove it from the ignore list.|r"] }
        for _, id in ipairs(ids) do
            local link  = mod.db.ignore[id]
            local label = (type(link) == "string" and link) or ("item:" .. tostring(id))
            opts[#opts + 1] = {
                type = "button", width = 240, label = "|cffff5555x|r  " .. label,
                onClick = function() mod.db.ignore[id] = nil; refreshOptions() end,
            }
        end
        opts[#opts + 1] = { type = "spacer", height = 4 }
        opts[#opts + 1] = { type = "button", width = 160, label = L["Clear ignore list"],
            onClick = function()
                if wipe then wipe(mod.db.ignore) else mod.db.ignore = {} end
                refreshOptions()
            end }
    end

    return opts
end
end)(...);

(function(...)
-- VulTraining: spell book tab listing trainable class abilities, built from per-class spell tables (Modules/VulTraining/Classes) so no trainer visit is needed.
local _, ns = ...

local mod = ns:RegisterModule("vultraining", {
    name        = "VulTraining",
    group       = "Character",
    description = "Adds a tab to your spell book that lists the abilities you can still learn from your class trainer, grouped by level. Open the book icon below the spell schools.",
    defaults    = { enabled = true },
})

local format, strlower, strfind, sort = string.format, string.lower, string.find, table.sort
local tinsert, wipe, ipairs, pairs = table.insert, wipe, ipairs, pairs

local L = ns.L

local MAX_ROWS, ROW_HEIGHT = 22, 14
local SKILL_LINE_TAB = (MAX_SKILLLINE_TABS or 8) - 1
local SPELLBOOK_SPELL = BOOKTYPE_SPELL or "spell"
local PARENS = PARENS_TEMPLATE or "(%s)"
local MEDIA = "Interface\\AddOns\\VuloClassicUI\\Media\\VulTraining\\"
local TEX_LEFT, TEX_RIGHT, TEX_HL = MEDIA .. "page-left", MEDIA .. "page-right", MEDIA .. "row-highlight"
local TAB_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CLOSE = FONT_COLOR_CODE_CLOSE
local COMINGSOON = "|cff82c5ff"

-- Spell info cache: force-loads spell data so name/icon/subtext are present
local spellInfoCache = {}
local function cacheSpell(spell, level, done)
    local id = spell.id
    if spellInfoCache[id] then done(true); return end

    local function finalize(si)
        if spellInfoCache[id] then done(true); return end
        local name = (si and si:GetSpellName()) or GetSpellInfo(id)
        if not name then done(true); return end
        local subText = (si and si.GetSpellSubtext and si:GetSpellSubtext())
            or (GetSpellSubtext and GetSpellSubtext(id)) or ""
        local fSub = (subText and subText ~= "") and format(PARENS, subText) or ""
        local fullName = (fSub ~= "") and (name .. " " .. fSub) or name
        spellInfoCache[id] = {
            id = id, name = name, subText = subText, formattedSubText = fSub,
            icon = select(3, GetSpellInfo(id)), cost = spell.cost, level = level,
            formattedLevel = format(L["Level %d"], level), formattedFullName = fullName,
            searchText = strlower(fullName), tooltipId = id,
            link = format("|cff71d5ff|Hspell:%d:0|h[%s]|h|r", id, name),
        }
        done(false)
    end

    -- ContinueOnSpellLoad HARD-ERRORS on a spell the client does not know
    -- ("Usage: NonEmptySpell:ContinueOnLoad") instead of just calling back, and
    -- Season of Discovery does not carry every id in the trainer lists. One
    -- unknown spell took the whole module down, so ask first and fall back to the
    -- plain lookup, which simply reports no name and skips the entry.
    local si = (Spell and Spell.CreateFromSpellID) and Spell:CreateFromSpellID(id) or nil
    local loadable = false
    if si and si.ContinueOnSpellLoad then
        local ok, empty = pcall(si.IsSpellEmpty, si)
        loadable = ok and not empty
    end
    if loadable then
        si:ContinueOnSpellLoad(function()
            if RunNextFrame then RunNextFrame(function() finalize(si) end) else finalize(si) end
        end)
    else
        finalize(nil)
    end
end

local function isPreviouslyLearned(spellId)
    local map = ns.VTData and ns.VTData.overriddenSpellsMap
    if not map or not map[spellId] then return false end
    local spellIndex, knownIndex = 0, 0
    for i, otherId in ipairs(map[spellId]) do
        if otherId == spellId then spellIndex = i end
        if IsSpellKnown(otherId) or IsPlayerSpell(otherId) then knownIndex = i end
    end
    return spellIndex <= knownIndex
end
local function isAbilityKnown(spellId)
    return IsSpellKnown(spellId) or IsPlayerSpell(spellId) or isPreviouslyLearned(spellId)
end

local categories = {
    { key = "available",     text = "Available now",                      color = GREEN_FONT_COLOR_CODE,  hideLevel = true },
    { key = "missingReqs",   text = "Available but Missing Requirements", color = ORANGE_FONT_COLOR_CODE, hideLevel = true },
    { key = "nextLevel",     text = "Upcoming",                           color = COMINGSOON },
    { key = "notLevel",      text = "Not Yet Available",                  color = RED_FONT_COLOR_CODE },
    { key = "missingTalent", text = "Missing Required Talents",           color = "|cffffffff", nameSort = true },
    { key = "known",         text = "Already Known",                      color = GRAY_FONT_COLOR_CODE, hideLevel = true, nameSort = true },
}
local categoryByKey = {}
for _, cat in ipairs(categories) do
    cat.spells = {}
    cat.isHeader = true
    categoryByKey[cat.key] = cat
end
-- Resolved in OnEnable, not at file load: the saved language override only
-- exists once SavedVariables are in.
local function localizeCategories()
    for _, cat in ipairs(categories) do
        cat.formattedName = (cat.color or "") .. L[cat.text] .. CLOSE
    end
end

local function byLevelThenName(a, b)
    if a.level == b.level then return a.name < b.name end
    return a.level < b.level
end
local function byNameThenLevel(a, b)
    if a.name == b.name then return a.level < b.level end
    return a.name < b.name
end

mod._data = {}
mod._filter = ""
local categoryData = {}

local function buildCategorizedData(playerLevel, isLevelUp)
    for _, cat in ipairs(categories) do wipe(cat.spells) end
    wipe(categoryData)

    local function levelColor(spell)
        local lvl = spell.level
        if isLevelUp then lvl = lvl - 1 end
        return GetQuestDifficultyColor(lvl)
    end

    local sbl = ns.VTData and ns.VTData.SpellsByLevel
    if not sbl then return end
    for level, spells in pairs(sbl) do
        for _, spell in ipairs(spells) do
            local info = spellInfoCache[spell.id]
            if info then
                local key
                if isAbilityKnown(spell.id) then
                    key = "known"
                elseif spell.requiredTalentId and not isAbilityKnown(spell.requiredTalentId) then
                    key = "missingTalent"
                elseif level > playerLevel then
                    key = (level <= playerLevel + 2) and "nextLevel" or "notLevel"
                else
                    local hasReqs = true
                    if spell.requiredIds then
                        for _, r in ipairs(spell.requiredIds) do hasReqs = hasReqs and isAbilityKnown(r) end
                    end
                    key = hasReqs and "available" or "missingReqs"
                end
                local cat = categoryByKey[key]
                if cat then tinsert(cat.spells, info) end
            end
        end
    end

    for _, cat in ipairs(categories) do
        if #cat.spells > 0 then
            sort(cat.spells, cat.nameSort and byNameThenLevel or byLevelThenName)
            for _, s in ipairs(cat.spells) do
                s.levelColor = levelColor(s)
                s.hideLevel = cat.hideLevel
            end
            tinsert(categoryData, cat)
        end
    end
end

local function matchesFilter(text)
    if mod._filter == "" then return true end
    return strfind(text, mod._filter, 1, true) ~= nil
end

local function applyFilter()
    wipe(mod._data)
    for _, cat in ipairs(categoryData) do
        local matched = {}
        for _, s in ipairs(cat.spells) do
            if matchesFilter(s.searchText) then tinsert(matched, s) end
        end
        if #matched > 0 then
            tinsert(mod._data, cat)
            for _, s in ipairs(matched) do tinsert(mod._data, s) end
        end
    end
    if #mod._data == 0 and mod._filter ~= "" then
        tinsert(mod._data, { isHeader = true, formattedName = L["No results found"] })
    end
end

local function rebuild()
    buildCategorizedData(UnitLevel("player"))
    applyFilter()
    if mod._frame and mod._frame:IsVisible() then mod.Update(true) end
end

local function setRowSpell(row, spell)
    if spell == nil then
        row.currentSpell = nil
        row:Hide()
        return
    elseif spell.isHeader then
        row.spell:Hide()
        row.header:Show()
        row.header:SetText(spell.formattedName)
        row:SetID(0)
        row.highlight:SetTexture(nil)
    else
        local rs = row.spell
        row.header:Hide()
        row.highlight:SetTexture(TEX_HL)
        rs:Show()
        rs.label:SetText(spell.name)
        rs.subLabel:SetText(spell.formattedSubText)
        if not spell.hideLevel then
            rs.level:Show()
            rs.level:SetText(spell.formattedLevel)
            local c = spell.levelColor
            if c then rs.level:SetTextColor(c.r, c.g, c.b) end
        else
            rs.level:Hide()
        end
        rs.icon:SetTexture(spell.icon)
    end
    row.currentSpell = spell
    row:Show()
end

local lastOffset = -1
function mod.Update(force)
    local frame = mod._frame
    if not frame then return end
    local offset = FauxScrollFrame_GetOffset(frame.scrollBar)
    if offset == lastOffset and not force then return end
    for i, row in ipairs(frame.rows) do
        setRowSpell(row, mod._data[i + offset])
    end
    FauxScrollFrame_Update(frame.scrollBar, #mod._data, MAX_ROWS, ROW_HEIGHT,
        nil, nil, nil, nil, nil, nil, true)
    lastOffset = offset
end

local function createFrame()
    if mod._frame or not SpellBookFrame then return end

    local frame = CreateFrame("Frame", "VulTrainingFrame", SpellBookFrame)
    frame:SetPoint("TOPLEFT", SpellBookFrame, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", SpellBookFrame, "BOTTOMRIGHT", 0, 0)
    frame:SetFrameStrata("HIGH")

    local left = frame:CreateTexture(nil, "ARTWORK")
    left:SetTexture(TEX_LEFT); left:SetWidth(256); left:SetHeight(512)
    left:SetPoint("TOPLEFT", frame)
    local right = frame:CreateTexture(nil, "ARTWORK")
    right:SetTexture(TEX_RIGHT); right:SetWidth(128); right:SetHeight(512)
    right:SetPoint("TOPRIGHT", frame)

    local search = CreateFrame("EditBox", "$parentSearch", frame, "SearchBoxTemplate")
    search:SetSize(124, 32)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 81, -34)
    search:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        local old = mod._filter
        mod._filter = strlower(self:GetText())
        if mod._filter ~= old then
            applyFilter()
            if frame:IsVisible() then mod.Update(true) end
        end
    end)
    frame:Hide()
    mod._frame = frame

    local scrollBar = CreateFrame("ScrollFrame", "$parentScrollBar", frame, "FauxScrollFrameTemplate")
    scrollBar:SetPoint("TOPLEFT", 0, -75)
    scrollBar:SetPoint("BOTTOMRIGHT", -65, 81)
    scrollBar:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() mod.Update() end)
    end)
    scrollBar:SetScript("OnShow", function()
        if not mod._hasShown then rebuild(); mod._hasShown = true end
        mod.Update(true)
    end)
    frame.scrollBar = scrollBar

    local rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", "$parentRow" .. i, frame)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnEnter", function(self)
            local s = self.currentSpell
            -- Spell tooltip plus a price line: opened by hand, see UI/Tooltip.lua.
            if not s or s.isHeader or not ns.UI:OpenTooltip(self, "ANCHOR_RIGHT") then return end
            if s.tooltipId then GameTooltip:SetSpellByID(s.tooltipId) end
            if s.cost and s.cost > 0 then
                GameTooltip:AddLine(format(L["Cost: %s"], GetCoinTextureString(s.cost)))
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
        row:SetScript("OnClick", function(self, button)
            local s = self.currentSpell
            if button == "LeftButton" and IsShiftKeyDown() and s and s.link then
                local w = ChatEdit_GetActiveWindow()
                if w then w:Insert(s.link) else ChatFrame_OpenChat(s.link) end
            end
        end)

        local highlight = row:CreateTexture("$parentHighlight", "HIGHLIGHT")
        highlight:SetAllPoints()

        local spell = CreateFrame("Frame", "$parentSpell", row)
        spell:SetPoint("LEFT", row, "LEFT")
        spell:SetPoint("TOP", row, "TOP")
        spell:SetPoint("BOTTOM", row, "BOTTOM")

        local icon = spell:CreateTexture(nil, "OVERLAY")
        icon:SetPoint("TOPLEFT", spell)
        icon:SetPoint("BOTTOMLEFT", spell)
        icon:SetWidth(ROW_HEIGHT)

        local label = spell:CreateFontString("$parentLabel", "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", spell, "TOPLEFT", ROW_HEIGHT + 4, 0)
        label:SetPoint("BOTTOM", spell)
        label:SetJustifyV("MIDDLE"); label:SetJustifyH("LEFT")

        local subLabel = spell:CreateFontString("$parentSubLabel", "OVERLAY", "NewSubSpellFont")
        subLabel:SetJustifyH("LEFT")
        subLabel:SetPoint("TOPLEFT", label, "TOPRIGHT", 2, 0)
        subLabel:SetPoint("BOTTOM", label)

        local level = spell:CreateFontString("$parentLevel", "OVERLAY", "GameFontWhite")
        level:SetPoint("TOPRIGHT", spell, -4, 0)
        level:SetPoint("BOTTOM", spell)
        level:SetJustifyH("RIGHT"); level:SetJustifyV("MIDDLE")
        subLabel:SetPoint("RIGHT", level, "LEFT")
        subLabel:SetJustifyV("MIDDLE")

        local header = row:CreateFontString("$parentHeader", "OVERLAY", "GameFontWhite")
        header:SetAllPoints()
        header:SetJustifyV("MIDDLE"); header:SetJustifyH("CENTER")

        spell.label, spell.subLabel, spell.icon, spell.level = label, subLabel, icon, level
        row.highlight, row.header, row.spell = highlight, header, spell

        if rows[i - 1] == nil then
            row:SetPoint("TOPLEFT", frame, 26, -78)
        else
            row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -2)
        end
        row:SetPoint("RIGHT", scrollBar)
        rows[i] = row
    end
    frame.rows = rows

    -- repurpose a spare skill-line tab as our tab
    local tab = _G["SpellBookSkillLineTab" .. SKILL_LINE_TAB]
    mod._tab = tab

    local function onTabs()
        if not tab then return end
        if mod._enabled == false then
            tab:Hide()
            if SpellBookFrame.selectedSkillLine == SKILL_LINE_TAB then frame:Hide() end
            return
        end
        tab:SetNormalTexture(TAB_ICON)
        tab.tooltip = L["What can I train?"]
        tab:Show()
        if SpellBookFrame.selectedSkillLine == SKILL_LINE_TAB then
            -- Seeing our page selected IS the intent, however it got there --
            -- most often by reopening a book that was left on it. Only ever set
            -- true here: the repair path below runs while Blizzard has already
            -- moved the selection away, and reading it there would conclude the
            -- opposite of what the player wants.
            mod._wantOurTab = true
            tab:SetChecked(true)
            frame:Show()
            if ShowAllSpellRanksCheckbox then ShowAllSpellRanksCheckbox:Hide() end
        else
            tab:SetChecked(false)
            frame:Hide()
            local _, class = UnitClass("player")
            if ShowAllSpellRanksCheckbox and class ~= "ROGUE" and class ~= "WARRIOR" then
                ShowAllSpellRanksCheckbox:Show()
            end
        end
    end
    local function onUpdate()
        if SpellBookFrame.bookType ~= SPELLBOOK_SPELL then
            frame:Hide()
        elseif mod._enabled ~= false and SpellBookFrame.selectedSkillLine == SKILL_LINE_TAB then
            frame:Show()
        end
    end
    if SpellBookFrame.UpdateSkillLineTabs then hooksecurefunc(SpellBookFrame, "UpdateSkillLineTabs", onTabs) end
    if SpellBookFrame.Update then hooksecurefunc(SpellBookFrame, "Update", onUpdate) end

    -- Blizzard's spell book throws our page away on SPELLS_CHANGED:
    --     if ( GetNumSpellTabs() < SpellBookFrame.selectedSkillLine ) then
    --         SpellBookFrame.selectedSkillLine = 2;
    -- We deliberately live on a tab slot PAST the real skill lines, so that
    -- test is always true for us and the book jumps to the first class tab --
    -- Fury on a warrior. It only shows up where something fires SPELLS_CHANGED
    -- while the book is open, which the rune system does constantly.
    --
    -- So remember whether the player wants our page, and put the selection back
    -- once Blizzard's own handler has finished with it. The flag is only ever
    -- cleared by picking a DIFFERENT tab -- closing the book must not clear it,
    -- because the book keeps its selection while closed, and reopening it on our
    -- page is by far the most common way to be sitting on it.
    if tab then
        tab:HookScript("OnClick", function() mod._wantOurTab = true end)
    end
    for i = 1, (MAX_SKILLLINE_TABS or 8) do
        local other = _G["SpellBookSkillLineTab" .. i]
        if other and other ~= tab then
            other:HookScript("OnClick", function() mod._wantOurTab = false end)
        end
    end
end

local function cacheAllSpells()
    local sbl = ns.VTData and ns.VTData.SpellsByLevel
    if not sbl then return end
    for level, spells in pairs(sbl) do
        for _, spell in ipairs(spells) do
            cacheSpell(spell, level, function(fromCache)
                if not fromCache and mod._frame then rebuild() end
            end)
        end
    end
end

local function onLevelOrLearn()
    rebuild()
end

-- Put our page back after Blizzard's SPELLS_CHANGED handler has kicked us off
-- it (see the comment in createFrame). File scope on purpose: createFrame runs
-- only once, so a handler declared in there could not be re-registered after
-- the module is switched off and on again.
local function restoreOurTab()
    if not mod._wantOurTab or mod._enabled == false then return end
    local sbf = _G.SpellBookFrame
    if not (sbf and sbf:IsVisible() and sbf.bookType == SPELLBOOK_SPELL) then return end
    if sbf.selectedSkillLine == SKILL_LINE_TAB then return end
    sbf.selectedSkillLine = SKILL_LINE_TAB
    if sbf.Update then sbf:Update() end
end

-- Next frame, not inline: Blizzard's handler for the very same event still has
-- to run, and it is the one doing the damage.
local function onSpellsChanged()
    ns.NextFrame(restoreOurTab)
end

function mod:OnEnable()
    localizeCategories()
    if not mod._built then
        createFrame()
        cacheAllSpells()
        rebuild()
        mod._built = true
    end
    mod:RegisterEvent("PLAYER_LEVEL_UP", onLevelOrLearn)
    mod:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", onLevelOrLearn)
    mod:RegisterEvent("LEARNED_SPELL_IN_TAB", onLevelOrLearn)
    mod:RegisterEvent("SPELLS_CHANGED", onSpellsChanged)
    if mod._tab and SpellBookFrame and SpellBookFrame.UpdateSkillLineTabs and SpellBookFrame:IsVisible() then
        SpellBookFrame:UpdateSkillLineTabs()
    end
end

function mod:OnDisable()
    mod._wantOurTab = false
    if mod._frame then mod._frame:Hide() end
    if mod._tab then mod._tab:Hide() end
end

function mod:GetOptions()
    return {
        { type = "desc", text = L["|cffaaaaaaAdds a tab to your spell book (the book icon on the side, below the spell schools) listing every ability you can still learn from your class trainer — grouped by status and coloured by level. No need to visit a trainer.|r"] },
    }
end
end)(...);

(function(...)
-- VuloClassicUI / Modules / Bugfixes — one IIFE per fix so file-level locals stay isolated.

(function(...)
-- Blizzard (deDE): auction house references an undefined PriceDropdown — provide a stub frame.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixauctiondropdown", {
    name        = "Auction Price Fix",
    group       = "Bugfixes",
    description = "Fixes a nil error in the German auction house UI (PriceDropdown not defined).",
    defaults = {
        enabled = true,
    },
})

local applied = false

local function applyFix()
    if applied then return end
    applied = true

    if GetLocale() == "deDE" and not _G.PriceDropdown then
        local f = CreateFrame("Frame", "PriceDropdown", UIParent)
        f.Text           = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.HideSpacerFrame = CreateFrame("Frame", nil, f)
    end
end

function mod:OnEnable()
    applyFix()
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Info"] },
        { type = "desc", text = L["This fix addresses a known bug in the German WoW localization: the auction house UI references a \"PriceDropdown\" element that was never defined, which causes Lua errors when opening the auction house."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaCurrent locale: %s|r"], GetLocale() or "?") },
        { type = "desc", text = L["|cffaaaaaaThe fix only applies on German clients (deDE). On other languages the module is inactive.|r"] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            applied and (_G.PriceDropdown and L["|cff66ff66applied|r"] or L["skipped (deDE-only)"]) or L["not applied"]) },
    }
end

end)(...);

(function(...)
-- Blizzard: broken guild news entries throw "formatString" errors and kill the panel — xpcall + fallback row.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixguildnews", {
    name        = "Guild News Nil Fix",
    group       = "Bugfixes",
    description = "Catches Lua errors in guild news entries (typically \"formatString\" or \"GuildUtil\") and replaces broken entries with a fallback text instead of letting the whole panel break.",
    defaults = {
        enabled    = true,
        showReport = true,
    },
})

local unpack = unpack or table.unpack

local function safeSetText(obj, text)
    if obj and obj.SetText then obj:SetText(text or "") end
end

local function safeHide(obj)
    if obj and obj.Hide then obj:Hide() end
end

local function safeShow(obj)
    if obj and obj.Show then obj:Show() end
end

local function applyFallbackToButton(button)
    if not button then return end

    safeSetText(button.Name, L["|cffff8080Invalid guild news entry|r"])
    safeSetText(button.Header, "")
    safeSetText(button.Time, "")
    safeSetText(button.Description, "")

    if button.Icon and button.Icon.SetTexture then button.Icon:SetTexture(nil) end
    if button.icon and button.icon.SetTexture then button.icon:SetTexture(nil) end

    safeHide(button.Highlight)
    safeHide(button.NewMarker)
    safeHide(button.newsTypeIcon)

    safeShow(button)
    if button.Enable then button:Enable() end
end

local wrappedAlready = false

local function installPatch()
    if wrappedAlready then return end
    if type(_G.GuildNewsButton_SetNews) ~= "function" then return end

    local Original = _G.GuildNewsButton_SetNews

    _G.GuildNewsButton_SetNews = function(button, newsInfo, ...)
        if not mod._enabled then
            return Original(button, newsInfo, ...)
        end

        local args = { ... }
        local ok, err = xpcall(function()
            return Original(button, newsInfo, unpack(args))
        end, function(e) return e end)

        if ok then return end

        local errText = tostring(err or "")
        if errText:find("formatString") or errText:find("GuildUtil") then
            applyFallbackToButton(button)
            if mod.db.showReport and not _G.VCUI_GuildNewsNilFix_Reported then
                _G.VCUI_GuildNewsNilFix_Reported = true
                DEFAULT_CHAT_FRAME:AddMessage(
                    L["|cffffff00[VuloClassicUI]|r Blizzard guild news error caught (fallback applied)."])
            end
            return
        end

        error(errText, 0)   -- level 0: keep Blizzard's original message/location
    end

    wrappedAlready = true
end

local installFrame

function mod:OnEnable()
    if not installFrame then
        installFrame = CreateFrame("Frame")
        installFrame:RegisterEvent("ADDON_LOADED")
        installFrame:SetScript("OnEvent", function(self, _, addonName)
            if addonName == "Blizzard_Communities" then
                installPatch()
                self:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end

    installPatch()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, installPatch)
    end
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Behavior"] },
        {
            type = "toggle", label = L["Chat message on first error"],
            tooltip = L["Shows a brief message once per session in chat when a guild news error was caught."],
            get = function() return mod.db.showReport end,
            set = function(_, v) mod.db.showReport = v end,
        },
        { type = "spacer", height = 8 },
        { type = "desc", text = L["This fix wraps Blizzard's |cffffffffGuildNewsButton_SetNews|r function in a protected call (xpcall). When an entry throws a known error (\"formatString\" or \"GuildUtil\"), the entry is replaced with a fallback text \"Invalid guild news entry\" — the panel remains usable."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            wrappedAlready and L["|cff66ff66Hook active|r"] or L["waiting for Blizzard_Communities"]) },
    }
end

end)(...);

(function(...)
-- Blizzard: LFGBrowseSearchEntry_Update crashes on stale resultIDs (GetSearchResultInfo nil) — xpcall, next refresh cleans up.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixlfgbrowsenil", {
    name        = "LFG Browse Nil Fix",
    group       = "Bugfixes",
    description = "Catches Lua errors in the Anniversary Group Finder (LFGBrowseSearchEntry_Update with stale resultIDs). Prevents chat spam and broken browse lists.",
    defaults = {
        enabled    = true,
        showReport = true,
    },
})

local unpack = unpack or table.unpack

local wrappedAlready = false

local function installPatch()
    if wrappedAlready then return end
    if type(_G.LFGBrowseSearchEntry_Update) ~= "function" then return end

    local Original = _G.LFGBrowseSearchEntry_Update

    _G.LFGBrowseSearchEntry_Update = function(button, ...)
        if not mod._enabled then
            return Original(button, ...)
        end

        local args = { ... }
        local ok, err = xpcall(function()
            return Original(button, unpack(args))
        end, function(e) return e end)

        if ok then return end

        local errText = tostring(err or "")
        if errText:find("searchResultInfo") or errText:find("attempt to index") then
            if mod.db.showReport and not _G.VCUI_LFGBrowseNilFix_Reported then
                _G.VCUI_LFGBrowseNilFix_Reported = true
                DEFAULT_CHAT_FRAME:AddMessage(
                    L["|cffffff00[VuloClassicUI]|r Blizzard LFG browse error caught (stale entry skipped)."])
            end
            return
        end

        error(errText, 0)   -- level 0: keep Blizzard's original message/location
    end

    wrappedAlready = true
end

local installFrame

function mod:OnEnable()
    if not installFrame then
        installFrame = CreateFrame("Frame")
        installFrame:RegisterEvent("ADDON_LOADED")
        installFrame:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_GroupFinder_VanillaStyle" then
                installPatch()
            end
        end)
    end

    installPatch()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, installPatch)
    end
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Behavior"] },
        {
            type = "toggle", label = L["Chat message on first error"],
            tooltip = L["Shows a brief message once per session in chat when an LFG browse error was caught."],
            get = function() return mod.db.showReport end,
            set = function(_, v) mod.db.showReport = v end,
        },
        { type = "spacer", height = 8 },
        { type = "desc", text = L["This fix wraps Blizzard's |cffffffffLFGBrowseSearchEntry_Update|r function in a protected call (xpcall). When the entry crashes due to a stale resultID (\"searchResultInfo nil\"), the error is swallowed — Blizzard's next refresh automatically cleans up the list entry."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            wrappedAlready and L["|cff66ff66Hook active|r"] or L["waiting for Blizzard_GroupFinder_VanillaStyle"]) },
    }
end

end)(...);

(function(...)
-- Blizzard: inspect server state gets stuck (empty frame / stale target / works only on 2nd try) because ClearInspectPlayer is never reliably called — watchdog + OnHide reset.
-- Taint: NEVER replace the global inspect functions; that taints the secure unit-popup menu and blocks whisper / raid-frame Show. Post-hook only.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixinspect", {
    name        = "Inspect Fix",
    group       = "Bugfixes",
    description = "Fixes stuck inspect bugs (no player inspect possible after a faulty close/timeout). Auto-reset after a timeout, auto-retry when the window stays empty, cleanup when InspectFrame closes + /inspectreset slash command.",
    defaults = {
        enabled    = true,
        autoReset  = true,
        autoRetry  = true,
        timeoutSec = 5,
    },
})

local _activeGUID         = nil
local _activeTime         = 0
local _hookedFrame        = false
local _inspectHooked      = false
local _watchdog
local _lastNotify         = 0
local _retriedGUID        = nil   -- one automatic re-request per inspected target

-- softReset keeps InspectFrame.unit (an open frame still needs it for tooltips); hardReset clears it.
local function softReset()
    if _G.ClearInspectPlayer then
        pcall(_G.ClearInspectPlayer)
    end
    _activeGUID = nil
    _activeTime = 0
end

local function hardReset()
    softReset()
    _retriedGUID = nil
    local f = _G.InspectFrame
    if f then f.unit = nil end
end

-- Blizzard: INSPECT_READY fires before item data has streamed in and the paperdoll paints only once — repaint late, re-request if still empty.
local INSPECT_SLOT_NAMES = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
    "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0",
    "Trinket1", "MainHand", "SecondaryHand", "Ranged",
}

local function repaintInspectSlots()
    local f   = _G.InspectFrame
    local upd = _G.InspectPaperDollItemSlotButton_Update
    if not (f and f:IsShown() and f.unit and upd) then return end
    for _, name in ipairs(INSPECT_SLOT_NAMES) do
        local btn = _G["Inspect" .. name .. "Slot"]
        if btn then pcall(upd, btn) end
    end
end

local function hasAnyInspectItem(unit)
    for slot = 1, 19 do
        if GetInventoryItemLink(unit, slot) then return true end
    end
    return false
end

-- Returns true only if a request was actually sent (a refusal must not re-arm the watchdog).
local function retryInspect(guid)
    local f = _G.InspectFrame
    if not (f and f:IsShown() and f.unit) then return false end
    if UnitGUID(f.unit) ~= guid then return false end
    if _retriedGUID == guid then return false end               -- one shot per target
    if GetTime() - _lastNotify < 1 then return false end        -- server throttle
    if _G.CanInspect and not _G.CanInspect(f.unit) then return false end
    if not _G.NotifyInspect then return false end
    _retriedGUID = guid
    _G.NotifyInspect(f.unit)
    return true
end

local function onInspectReady(_, guid)
    -- clear tracking only; don't reset, the UI still needs the data
    _activeGUID = nil
    _activeTime = 0

    if not (mod._enabled and mod.db and mod.db.autoRetry ~= false) then return end
    local f = _G.InspectFrame
    if not (guid and f and f:IsShown() and f.unit and UnitGUID(f.unit) == guid) then return end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.4, function()
            if not mod._enabled then return end
            local fr = _G.InspectFrame
            if fr and fr:IsShown() and fr.unit and UnitGUID(fr.unit) == guid then
                repaintInspectSlots()
            end
        end)
        -- attempt 2 covers the 1s NotifyInspect throttle eating the first try
        local function emptyCheck(attempt)
            if not mod._enabled then return end
            local fr = _G.InspectFrame
            if not (fr and fr:IsShown() and fr.unit and UnitGUID(fr.unit) == guid) then return end
            repaintInspectSlots()
            if hasAnyInspectItem(fr.unit) then return end
            if not retryInspect(guid) and attempt < 2 and _retriedGUID ~= guid then
                C_Timer.After(1.0, function() emptyCheck(attempt + 1) end)
            end
        end
        C_Timer.After(1.2, function() emptyCheck(1) end)
    end
end

-- Post-hook only: the hook runs after the request, so state can't be cleared up front — the watchdog does it instead.
local function installInspectTracking()
    if _inspectHooked or type(_G.NotifyInspect) ~= "function" then return end
    _inspectHooked = true
    hooksecurefunc("NotifyInspect", function(unit)
        _lastNotify = GetTime()
        if unit and UnitExists(unit) then
            _activeGUID = UnitGUID(unit)
            _activeTime = GetTime()
        end
    end)
end

-- Blizzard: inspect-slot OnEnter shows no tooltip while item data is still streaming and never retries — replaced (tooltip-only, taint-legal); UpdateTooltip re-invokes this until data lands.
local function inspectSlotOnEnter(self)
    if not mod._enabled then
        if self._vcuiOrigEnter then self._vcuiOrigEnter(self) end
        return
    end
    local fr = _G.InspectFrame
    local unit = (fr and fr.unit) or "target"
    ns.UI:OpenTooltip(self, "ANCHOR_RIGHT")
    if GameTooltip:SetInventoryItem(unit, self:GetID()) then
        GameTooltip:Show()
        return
    end
    local slot = self:GetID()
    local link = GetInventoryItemLink and GetInventoryItemLink(unit, slot)
    if link then
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
        return
    end
    local tex = GetInventoryItemTexture and GetInventoryItemTexture(unit, slot)
    if tex then
        -- occupied but uncached: request the data, show a stub until it lands
        local id = GetInventoryItemID and GetInventoryItemID(unit, slot)
        if id and GetItemInfo then GetItemInfo(id) end
        GameTooltip:SetText(_G.RETRIEVING_ITEM_INFO or "...", 1, 0.82, 0)
        GameTooltip:Show()
    else
        ns.UI:HideTooltip()
    end
end

local function hardenInspectTooltips()
    for _, name in ipairs(INSPECT_SLOT_NAMES) do
        local btn = _G["Inspect" .. name .. "Slot"]
        if btn and not btn._vcuiTipFixed then
            btn._vcuiTipFixed = true
            btn._vcuiOrigEnter = btn:GetScript("OnEnter")
            btn:SetScript("OnEnter", inspectSlotOnEnter)
            btn.UpdateTooltip = inspectSlotOnEnter
        end
    end
end

local function hookInspectFrame()
    if _hookedFrame then return end
    local f = _G.InspectFrame
    if not f then return end
    hardenInspectTooltips()
    f:HookScript("OnHide", function()
        if mod._enabled then hardReset() end
    end)
    _hookedFrame = true
end

local function watchdogTick()
    if not mod._enabled or not mod.db or not mod.db.autoReset then return end
    if _activeTime == 0 then return end
    local timeout = mod.db.timeoutSec or 5
    if GetTime() - _activeTime <= timeout then return end

    -- Retry before clearing: ClearInspectPlayer would leave an open frame permanently empty.
    local f = _G.InspectFrame
    local stuckGUID = _activeGUID
    if mod.db.autoRetry ~= false and stuckGUID and _retriedGUID ~= stuckGUID
        and f and f:IsShown() and f.unit and UnitGUID(f.unit) == stuckGUID then
        if retryInspect(stuckGUID) then return end   -- hook re-armed tracking
    end
    softReset()
end

ns:RegisterSlash({ key = "INSPECTRESET", commands = { "/inspectreset" },
    desc = "Unstick inspect after it stops answering.",
})
ns.Slash.INSPECTRESET = function()
    hardReset()
    if _G.InspectFrame and _G.InspectFrame:IsShown() then
        _G.InspectFrame:Hide()
    end
    if ns and ns.Print then
        ns:Print(L["Inspect state manually reset. Try again now."])
    else
        DEFAULT_CHAT_FRAME:AddMessage(L["|cffffff00[VuloClassicUI]|r Inspect state reset."])
    end
end

ns:RegisterSlash({ key = "INSPECTSTATE", commands = { "/inspectstate" },
    desc = "Print what the inspect fix currently thinks.",
    hidden = true,
})
ns.Slash.INSPECTSTATE = function()
    local f = _G.InspectFrame
    local lines = {
        "|cffffff00[VuloClassicUI Inspect State]|r",
        string.format("  NotifyInspect hook:     %s", _inspectHooked and "yes" or "no"),
        string.format("  InspectFrame hook:      %s", _hookedFrame  and "yes" or "no"),
        string.format("  Active GUID:            %s", tostring(_activeGUID)),
        string.format("  Active time:            %s", _activeTime > 0 and string.format("%.1fs ago", GetTime() - _activeTime) or "none"),
        string.format("  InspectFrame.unit:      %s", f and tostring(f.unit) or "no frame"),
        string.format("  InspectFrame shown:     %s", (f and f:IsShown()) and "yes" or "no"),
        string.format("  Last NotifyInspect:     %s", _lastNotify > 0 and string.format("%.1fs ago", GetTime() - _lastNotify) or "none"),
        string.format("  Auto-retry used:        %s", _retriedGUID and "yes (this target)" or "no"),
        string.format("  Slots with data:        %s", (f and f:IsShown() and f.unit) and (hasAnyInspectItem(f.unit) and "yes" or "NONE") or "-"),
    }
    for _, line in ipairs(lines) do
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end
end

local installFrame

function mod:OnEnable()
    if not mod.db then return end

    installInspectTracking()
    hookInspectFrame()

    -- Blizzard_InspectUI is lazy-loaded on first inspect
    if not installFrame then
        installFrame = CreateFrame("Frame")
        installFrame:SetScript("OnEvent", function(self, _, addonName)
            if addonName == "Blizzard_InspectUI" then
                hookInspectFrame()
                self:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end
    if not (IsAddOnLoaded and IsAddOnLoaded("Blizzard_InspectUI")) then
        installFrame:RegisterEvent("ADDON_LOADED")
    end

    mod:RegisterEvent("INSPECT_READY", onInspectReady)

    if not _watchdog and C_Timer and C_Timer.NewTicker then
        _watchdog = C_Timer.NewTicker(2, watchdogTick)
    end
end

function mod:OnDisable()
    if _watchdog then _watchdog:Cancel(); _watchdog = nil end
    -- the NotifyInspect post-hook stays (hooksecurefunc can't be removed); harmless while off
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Behavior"] },

        { type = "toggle", label = L["Auto-reset on timeout"],
          tooltip = L["If no response from the server comes after X seconds, the pending inspect state is automatically reset — so the next inspect attempt works again."],
          get = function() return mod.db.autoReset ~= false end,
          set = function(_, v) mod.db.autoReset = v end },

        { type = "toggle", label = L["Auto-retry empty inspects"],
          tooltip = L["After the server answers, the item slots are repainted again shortly after (data often arrives late). If the window is still completely empty, the inspect is automatically requested one more time."],
          get = function() return mod.db.autoRetry ~= false end,
          set = function(_, v) mod.db.autoRetry = v end },

        { type = "slider", label = L["Timeout (seconds)"],
          min = 3, max = 20, step = 1,
          tooltip = L["How long to wait for INSPECT_READY before auto-reset kicks in. 5 seconds is the new default for Anniversary — fast enough to recover quickly."],
          get = function() return mod.db.timeoutSec or 5 end,
          set = function(_, v) mod.db.timeoutSec = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Manual Reset"] },
        { type = "button", label = L["Reset inspect state now"], width = 240,
          onClick = function()
              hardReset()
              if _G.InspectFrame and _G.InspectFrame:IsShown() then
                  _G.InspectFrame:Hide()
              end
              ns:Print(L["Inspect state manually reset."])
          end },
        { type = "desc", text = L["|cffaaaaaaSlash commands: /inspectreset (force-reset), /inspectstate (debug info in chat)|r"] },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Status"] },
        { type = "desc", text = string.format(
            L["NotifyInspect hook: %s\nInspectFrame hook: %s"],
            _inspectHooked and L["|cff66ff66active|r"] or L["|cffff8800waiting|r"],
            _hookedFrame   and L["|cff66ff66active|r"] or L["|cffff8800waiting for Blizzard_InspectUI|r"]) },
        { type = "spacer", height = 4 },
        { type = "desc", text = L["|cffaaaaaaWhat the fix does: tracks active inspects with a timestamp, repaints late-arriving item data, re-requests an all-empty inspect once, and calls ClearInspectPlayer() on close + on timeout. Prevents a stuck state from blocking all subsequent inspects.|r"] },
    }
end

end)(...);

(function(...)
-- Blizzard (2.5.5): StaticPopup "BIND_SOCKET" is missing, so binding gem socketing errors out — re-add the dialog.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixbindsocket", {
    name        = "Bind-on-Socket Fix",
    group       = "Bugfixes",
    description = "Re-adds the missing BIND_SOCKET confirmation dialog so socketing a gem that binds the item no longer throws a Lua error (Anniversary client).",
    defaults = { enabled = true },
})

local function installFix()
    local dialogs = _G.StaticPopupDialogs
    if not dialogs or dialogs["BIND_SOCKET"] then return end
    dialogs["BIND_SOCKET"] = {
        text         = _G.BIND_SOCKET or L["Socketing this gem will bind the item to you. Continue?"],
        button1      = _G.ACCEPT or "Accept",
        button2      = _G.CANCEL or "Cancel",
        OnAccept     = function() if _G.AcceptSockets then _G.AcceptSockets() end end,
        timeout      = 0,
        whileDead    = 1,
        hideOnEscape = 1,
        showAlert    = 1,
    }
end

function mod:OnEnable()
    installFix()
end

function mod:GetOptions()
    local defined = _G.StaticPopupDialogs and _G.StaticPopupDialogs["BIND_SOCKET"] ~= nil
    return {
        { type = "header", text = L["Bind-on-Socket Fix"] },
        { type = "desc", text = L["The Anniversary client is missing the |cffffffffBIND_SOCKET|r confirmation dialog. Socketing a gem that would bind the item then throws \"Dialog BIND_SOCKET does not exist\" and aborts. This re-adds the dialog so socketing works."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            defined and L["|cff66ff66Dialog defined|r"] or L["not defined yet"]) },
    }
end

end)(...);

(function(...)
-- Blizzard: the player frame no longer flashes red in combat — add our own portrait glow.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixcombatglow", {
    name        = "Combat Indicator",
    group       = "Bugfixes",
    description = "Restores the missing 'in combat' glow on the Player frame (Anniversary default-UI bug). Pulses a red glow around your portrait while you are in combat.",
    defaults = {
        enabled = true,
    },
})

local glow

local function ensureGlow()
    if glow then return glow end
    local pf = _G.PlayerFrame
    if not pf then return nil end

    glow = pf:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\COMMON\\RingBorder")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.18, 0.18, 1)

    local portrait = _G.PlayerPortrait
    if portrait then
        glow:SetPoint("CENTER", portrait, "CENTER", 0, 0)
        local w, h = portrait:GetSize()
        if not w or w == 0 then w, h = 56, 56 end
        glow:SetSize(w * 1.32, h * 1.32)
    else
        glow:SetPoint("CENTER", pf, "TOPLEFT", 40, -25)
        glow:SetSize(74, 74)
    end

    glow.anim = glow:CreateAnimationGroup()
    glow.anim:SetLooping("BOUNCE")
    local a = glow.anim:CreateAnimation("Alpha")
    a:SetFromAlpha(1.0)
    a:SetToAlpha(0.35)
    a:SetDuration(0.7)

    glow:Hide()
    return glow
end

local function update()
    local g = ensureGlow()
    if not g then return end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        g:Show()
        if g.anim then g.anim:Play() end
    else
        if g.anim then g.anim:Stop() end
        g:Hide()
    end
end

function mod:OnEnable()
    ensureGlow()
    mod:RegisterEvent("PLAYER_REGEN_DISABLED", update)
    mod:RegisterEvent("PLAYER_REGEN_ENABLED",  update)
    mod:RegisterEvent("PLAYER_ENTERING_WORLD", update)
    update()
end

function mod:OnDisable()
    if glow then
        if glow.anim then glow.anim:Stop() end
        glow:Hide()
    end
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Combat Indicator"] },
        { type = "desc", text = L["|cffaaaaaaThe default Player frame on Anniversary no longer shows when you are in combat. This restores it: a red glow pulses around your portrait while you are in combat.|r"] },
    }
end

end)(...);

(function(...)
-- Blizzard (2.5.5): nameplate code calls GetSpecializationRole, which this client
-- rejects ("API unsupported") — the error aborts CompactUnitFrame_UpdateAll on
-- every nameplate spawn. Shim the global with a nil-returning Lua function so
-- IsPlayerEffectivelyTank cleanly answers "not a tank".
-- Taint: the shim's return value feeds display-only branches (health border
-- tint); no protected call consumes it. Installed only while the real API
-- throws, so a future Blizzard fix wins automatically.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixnameplaterole", {
    name        = "Nameplate Role Fix",
    group       = "Bugfixes",
    description = "Stops the Lua error that fires every time a nameplate appears (Blizzard's nameplate code calls a specialization API this client does not support).",
    defaults = { enabled = true },
})

local installed = false

local function installFix()
    if installed then return end
    local orig = _G.GetSpecializationRole
    if type(orig) ~= "function" then return end   -- Era: global absent, error path can't occur
    if pcall(orig, 1) then return end             -- API works — nothing to fix
    installed = true
    _G.GetSpecializationRole = function(...)
        if not mod._enabled then return orig(...) end
        return nil   -- no specializations on this client: never a spec role
    end
end

function mod:OnEnable()
    installFix()
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Nameplate Role Fix"] },
        { type = "desc", text = L["Blizzard's own nameplate code asks for your specialization role - an API the Anniversary client rejects. The resulting Lua error fires on every nameplate spawn and aborts part of the nameplate setup. This fix answers the question safely with 'no role'."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            installed and L["|cff66ff66applied|r"] or L["not needed on this client"]) },
    }
end

end)(...);

-- The standalone "Bug Fixes" container is gone (30.07.2026): every Fix*
-- sub-module above is collected by the "General" row instead, together with
-- the former Extras and Character containers. See Modules/General.lua.
end)(...);

(function(...)
-- "Open All" mailbox button: collects every attachment and coin in one click.
local _, ns = ...

local mod = ns:RegisterModule("vulmail", {
    name        = "Mail",
    group       = "Chat & Social",
    description = "Adds an 'Open All' button to your mailbox that collects every attachment and coin in one click.",
    defaults = {
        enabled     = true,
        attachments = true,
        gold        = true,
        keepFree    = 0,
        openSpeed   = 0.15,   -- seconds between mail actions; the server throttles them
        verbose     = true,
        recipients  = true,
    },
})

local format = string.format
local ATTACH_MAX = ATTACHMENTS_MAX_RECEIVE or 16
local NUM_BAGS = NUM_BAG_SLOTS or 4

local L = ns.L

local function countItemsAndMoney()
    local items = 0
    for bag = 0, NUM_BAGS do
        local n = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local _, count = GetContainerItemInfo(bag, slot)
            if count then items = items + count end
        end
    end
    return items, GetMoney()
end

local function freeBagSlots()
    local free = 0
    for bag = 0, NUM_BAGS do
        local f, fam = GetContainerNumFreeSlots(bag)
        if fam == 0 then free = free + (f or 0) end
    end
    return free
end

local function moneyString(c)
    if GetMoneyString then return GetMoneyString(c) end
    return format("%d", math.floor((c or 0) / 10000)) .. "g"
end

local button
local idx, aIdx, waiting, lastItems, lastGold, lastFinal, invFull, running, override, waitTries, waitStart
local startGold, startItems
-- Forward declarations: these four call each other recursively, so all must exist first.
local step, processCurrent, finish, openAll

local pump = CreateFrame("Frame")
pump:Hide()
pump:SetScript("OnUpdate", function(self, e)
    self.t = (self.t or 0) - e
    if self.t <= 0 then self:Hide(); step() end
end)
local function schedule()
    pump.t = mod.db and mod.db.openSpeed or 0.15
    pump:Show()
end

function step()
    if not running then return end
    if idx <= 0 then return finish() end

    if waiting then
        local items, gold = countItemsAndMoney()
        if gold ~= lastGold then
            waiting = false; idx = idx - 1; aIdx = ATTACH_MAX; return step()
        elseif items ~= lastItems then
            waiting = false; aIdx = aIdx - 1
            if lastFinal then lastFinal = false; idx = idx - 1; aIdx = ATTACH_MAX end
            return step()
        else
            -- Watchdog: a take can silently never confirm, so give up after 3s.
            if GetTime() - (waitStart or 0) > 3 then
                waiting = false
                idx = idx - 1; aIdx = ATTACH_MAX
                return schedule()
            end
            return schedule()
        end
    end
    waitTries = 0
    return processCurrent()
end

function processCurrent()
    local _, _, money, cod, _, itemCount, _, _, _, _, isGM = select(3, GetInboxHeaderInfo(idx))
    money = money or 0
    cod = cod or 0

    if cod > 0 or isGM then idx = idx - 1; aIdx = ATTACH_MAX; return step() end

    local takeItems = override or mod.db.attachments
    local takeGold  = override or mod.db.gold

    if not (takeItems and itemCount and itemCount > 0) and not (takeGold and money > 0) then
        idx = idx - 1; aIdx = ATTACH_MAX; return step()
    end

    -- Scan backwards: taking an attachment renumbers the ones after it.
    while aIdx > 0 and not GetInboxItemLink(idx, aIdx) do aIdx = aIdx - 1 end

    if aIdx > 0 and not invFull and (mod.db.keepFree or 0) > 0 then
        if freeBagSlots() <= mod.db.keepFree then invFull = true end
    end

    if aIdx > 0 and takeItems and not invFull then
        lastItems, lastGold = countItemsAndMoney()
        TakeInboxItem(idx, aIdx)
        waiting = true; waitStart = GetTime()
        local a2 = aIdx - 1
        while a2 > 0 and not GetInboxItemLink(idx, a2) do a2 = a2 - 1 end
        if a2 == 0 and not (takeGold and money > 0) then lastFinal = true end
        return schedule()
    elseif takeGold and money > 0 then
        lastItems, lastGold = countItemsAndMoney()
        TakeInboxMoney(idx)
        waiting = true; waitStart = GetTime()
        return schedule()
    else
        idx = idx - 1; aIdx = ATTACH_MAX; return step()
    end
end

function finish()
    pump:Hide()
    local shown, total = GetInboxNumItems()
    -- The inbox only loads 50 mails at a time; refresh and continue, bounded.
    if total and shown and total > shown and not invFull and (mod._continues or 0) < 12 then
        mod._continues = (mod._continues or 0) + 1
        waiting = false
        mod._awaitRefresh = true
        CheckInbox()   -- async; mod._onInbox resumes on MAIL_INBOX_UPDATE
        return
    end
    running = false
    mod._continues = nil
    mod._awaitRefresh = nil
    ns:UnregisterEvent("UI_ERROR_MESSAGE", mod._onError)
    ns:UnregisterEvent("MAIL_INBOX_UPDATE", mod._onInbox)
    if button then button:SetText(L["Open All"]); button:Enable() end
    if InboxFrame_Update then InboxFrame_Update() end

    if mod.db.verbose then
        local gold = GetMoney() - (startGold or GetMoney())
        local items = (select(1, countItemsAndMoney())) - (startItems or 0)
        if gold > 0 or items > 0 then
            local itemStr = items > 0 and format(L[" and %d item(s)"], items) or ""
            ns:Print(format(L["Mail emptied: looted %s%s."], moneyString(gold), itemStr))
        end
    end
    if invFull then ns:Print(L["Bags are full — some items were left in the mail."]) end
end

function openAll(isRecursive)
    if running and not isRecursive then return end
    idx = (GetInboxNumItems()) or 0
    aIdx = ATTACH_MAX
    invFull = false; waiting = false; lastFinal = false; waitStart = nil
    if not isRecursive then
        override = IsShiftKeyDown()
        if idx == 0 then return end
        running = true
        startGold = GetMoney()
        startItems = (select(1, countItemsAndMoney()))
        mod._continues = 0
        if button then button:SetText(L["In Progress"]); button:Disable() end
        -- MAIL_INBOX_UPDATE confirms each take; the pump timer is only a fallback.
        ns:RegisterEvent("UI_ERROR_MESSAGE", mod._onError)
        ns:RegisterEvent("MAIL_INBOX_UPDATE", mod._onInbox)
    end
    step()
end

function mod._onInbox()
    if not running then return end
    if mod._awaitRefresh then
        mod._awaitRefresh = false
        return openAll(true)
    end
    if waiting then step() end
end

function mod._onError(_, arg1, arg2)
    local msg = arg2 or arg1   -- classic sends (message); newer clients send (errorType, message)
    if msg == ERR_INV_FULL then
        invFull = true; waiting = false
    elseif ERR_ITEM_MAX_COUNT and msg == ERR_ITEM_MAX_COUNT then
        aIdx = aIdx - 1; waiting = false
    end
end

local sendButton
local sendHooked

local function mailStore()
    if not VuloClassicUIDB then return nil end
    -- Stored top-level so it survives profile switches and ApplyDefaults.
    VuloClassicUIDB.mailBook = VuloClassicUIDB.mailBook or { alts = {}, recent = {} }
    return VuloClassicUIDB.mailBook
end

local function recordAlt()
    local s = mailStore(); if not s then return end
    local name, realm = UnitName("player"), GetRealmName()
    local faction = UnitFactionGroup("player")
    if not name or not realm then return end
    for _, a in ipairs(s.alts) do
        if a.name == name and a.realm == realm then return end
    end
    s.alts[#s.alts + 1] = { name = name, realm = realm, faction = faction }
    table.sort(s.alts, function(a, b) return a.name < b.name end)
end

local function recordRecent(recipient)
    local s = mailStore(); if not s then return end
    recipient = recipient and strtrim(recipient) or ""
    if recipient == "" then return end
    for i = #s.recent, 1, -1 do if s.recent[i] == recipient then table.remove(s.recent, i) end end
    table.insert(s.recent, 1, recipient)
    for i = #s.recent, 13, -1 do table.remove(s.recent, i) end
end

local function fillRecipient(name)
    if not SendMailNameEditBox then return end
    SendMailNameEditBox:SetText(name)
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetFocus() end
end

local function addNames(entries, titleText, names, cap)
    if #names == 0 then return end
    if #entries > 0 then entries[#entries + 1] = { separator = true } end
    entries[#entries + 1] = { title = true, text = titleText }
    for i = 1, (cap and math.min(#names, cap) or #names) do
        local n = names[i]
        entries[#entries + 1] = { text = n, func = function() fillRecipient(n) end }
    end
end

local function buildRecipientMenu()
    local s = mailStore() or { alts = {}, recent = {} }
    local entries = {}
    local me, myRealm, myFaction = UnitName("player"), GetRealmName(), UnitFactionGroup("player")

    addNames(entries, L["Recently mailed"], s.recent)

    local chars = {}
    for _, a in ipairs(s.alts) do
        if a.name ~= me and a.realm == myRealm and a.faction == myFaction then chars[#chars + 1] = a.name end
    end
    addNames(entries, L["Your characters"], chars, 30)

    local friends = {}
    local nF = (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends())
        or (GetNumFriends and GetNumFriends()) or 0
    for i = 1, nF do
        local info = C_FriendList and C_FriendList.GetFriendInfoByIndex and C_FriendList.GetFriendInfoByIndex(i)
        local fname = (info and info.name) or (GetFriendInfo and GetFriendInfo(i))
        if fname then friends[#friends + 1] = fname end
    end
    addNames(entries, L["Friends"], friends, 30)

    if IsInGuild and IsInGuild() then
        -- Roster fetch is async, so this open uses cached data and the next is fresh.
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
        elseif GuildRoster then GuildRoster() end
        local guild = {}
        local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
        for i = 1, n do
            local gname, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if gname and online then
                gname = gname:match("^[^%-]+") or gname
                if gname ~= me then guild[#guild + 1] = gname end
            end
        end
        table.sort(guild)
        addNames(entries, L["Guild"], guild, 30)
    end

    if #entries == 0 then entries[#entries + 1] = { disabled = true, text = L["No contacts yet"] } end
    return entries
end

local function createSendButton()
    if sendButton or not SendMailFrame or not SendMailNameEditBox then return end
    sendButton = CreateFrame("Button", "VulMailToButton", SendMailFrame)
    sendButton:SetSize(24, 24)
    sendButton:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 0, 1)
    sendButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    sendButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round")
    sendButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    sendButton:SetFrameLevel(sendButton:GetFrameLevel() + 1)
    sendButton:SetScript("OnClick", function(self) ns:ShowPopupMenu(buildRecipientMenu(), self) end)
end

local function applySendButton()
    createSendButton()
    if sendButton then sendButton:SetShown(mod.db.recipients ~= false) end
end

local function createButton()
    if button or not InboxFrame then return end
    button = CreateFrame("Button", "VulMailOpenAll", InboxFrame, "UIPanelButtonTemplate")
    button:SetSize(120, 25)
    if OpenAllMail then
        button:SetAllPoints(OpenAllMail)
    else
        button:SetPoint("CENTER", InboxFrame, "TOP", -36, -399)
    end
    button:SetText(L["Open All"])
    button:SetFrameLevel(button:GetFrameLevel() + 1)
    button:SetScript("OnClick", function() openAll() end)
end

local function onMailShow()
    createButton()
    applySendButton()
    if OpenAllMail then OpenAllMail:Hide() end
    if button then button:Show() end
end
local function onMailClosed()
    running = false
    pump:Hide()
    waiting = false
    ns:UnregisterEvent("UI_ERROR_MESSAGE", mod._onError)
    if button then button:SetText(L["Open All"]); button:Enable() end
end

function mod:OnEnable()
    createButton()
    recordAlt()
    applySendButton()
    if not sendHooked and SendMail then
        hooksecurefunc("SendMail", function(recipient) recordRecent(recipient) end)
        sendHooked = true
    end
    mod:RegisterEvent("MAIL_SHOW", onMailShow)
    mod:RegisterEvent("MAIL_CLOSED", onMailClosed)
    if button then button:Show() end
end

function mod:OnDisable()
    onMailClosed()
    if button then button:Hide() end
    if sendButton then sendButton:Hide() end
    if OpenAllMail then OpenAllMail:Show() end
end

function mod:GetOptions()
    return {
        { type = "desc", text = L["|cffaaaaaaAdds an 'Open All' button to the mailbox. It takes every attachment and coin, skipping CoD and GM mail. Shift-click the button to ignore the filters and take everything.|r"] },
        { type = "toggle", label = L["Take item attachments"],
          get = function() return mod.db.attachments end,
          set = function(_, v) mod.db.attachments = v end },
        { type = "toggle", label = L["Take money"],
          get = function() return mod.db.gold end,
          set = function(_, v) mod.db.gold = v end },
        { type = "toggle", label = L["Print a looted summary"],
          get = function() return mod.db.verbose end,
          set = function(_, v) mod.db.verbose = v end },
        { type = "toggle", label = L["Recipient dropdown on the Send tab"],
          get = function() return mod.db.recipients end,
          set = function(_, v) mod.db.recipients = v; applySendButton() end },
        { type = "slider", label = L["Keep this many bag slots free"], min = 0, max = 12, step = 1,
          get = function() return mod.db.keepFree or 0 end,
          set = function(_, v) mod.db.keepFree = v end },
        { type = "slider", label = L["Speed (seconds between actions)"], min = 0.05, max = 1.0, step = 0.05,
          get = function() return mod.db.openSpeed or 0.15 end,
          set = function(_, v) mod.db.openSpeed = v end },
    }
end
end)(...);

(function(...)
-- Group board: scans chat for group-forming messages and lists them per instance.
local _, ns = ...

local mod = ns:RegisterModule("vullfg", {
    name        = "Group Board",
    group       = "Chat & Social",
    description = "Scans chat for people forming groups and lists them by Classic/TBC instance in a window (/vlfg or the minimap button).",
    defaults = {
        enabled    = true,
        window     = 20,     -- minutes a request stays listed
        minimap    = true,
        mmAngle    = 200,    -- degrees
        scanWorld  = true,
        scanGuild  = true,
        scanSay    = true,
        point      = nil,
    },
})

local floor, format, strlower, strfind = math.floor, string.format, string.lower, string.find
local ipairs, pairs = ipairs, pairs
local GetTime, GetActivity = GetTime, (C_LFGList and C_LFGList.GetActivityInfoTable)
local ACCENT = ns.COLORS and ns.COLORS.accent or { r = 0.608, g = 0.424, b = 1 }

local L = ns.L

-- id = LFG activity id (source of the localized name + level range); abbr = curated chat keywords.
local CAT_ORDER = ns.isEra and { "cd", "cr" } or { "cd", "cr", "bd", "br" }
local CAT_NAME = {}
ns.OnLocaleReady(function()
    CAT_NAME.cd = L["Classic Dungeons"]; CAT_NAME.cr = L["Classic Raids"]
    CAT_NAME.bd = L["Burning Crusade Dungeons"]; CAT_NAME.br = L["Burning Crusade Raids"]
end)

local DUNGEONS = {
    { key="RFC",  id=798, cat="cd", abbr="rfc ragefire chasm" },
    { key="WC",   id=796, cat="cd", abbr="wc wailing caverns" },
    { key="DM",   id=799, cat="cd", abbr="vc deadmines deadmine dm defias" },
    { key="SFK",  id=800, cat="cd", abbr="sfk shadowfang" },
    { key="STK",  id=802, cat="cd", abbr="stockade stockades stocks" },
    { key="BFD",  id=801, cat="cd", abbr="bfd blackfathom fathom" },
    { key="GNO",  id=803, cat="cd", abbr="gno gnomeregan gnome" },
    { key="RFK",  id=804, cat="cd", abbr="rfk razorfen kraul kraul" },
    { key="SM",   id=805, cat="cd", abbr="sm scarlet monastery graveyard library armory cathedral smg sml sma smc", zone=189 },
    { key="RFD",  id=806, cat="cd", abbr="rfd razorfen downs downs" },
    { key="ULD",  id=807, cat="cd", abbr="uld uldaman" },
    { key="ZF",   id=808, cat="cd", abbr="zf zulfarrak farrak" },
    { key="MAR",  id=809, cat="cd", abbr="mar maraudon maru" },
    { key="ST",   id=810, cat="cd", abbr="st sunken temple atalhakkar" },
    { key="BRD",  id=811, cat="cd", abbr="brd blackrock depths depths" },
    { key="DML",  id=813, cat="cd", abbr="dire diremaul dme dmw dmn tribute", zone=429 },
    { key="LBRS", id=812, cat="cd", abbr="lbrs lower spire" },
    { key="UBRS", id=837, cat="cd", abbr="ubrs upper spire" },
    { key="STR",  id=816, cat="cd", abbr="strat stratholme baron ud undead living" },
    { key="SCH",  id=797, cat="cd", abbr="sch scholo scholomance" },
    { key="ZG",   id=836, cat="cr", abbr="zg zulgurub gurub" },
    { key="ONY",  id=838, cat="cr", abbr="ony onyxia" },
    { key="MC",   id=839, cat="cr", abbr="mc molten core" },
    { key="BWL",  id=840, cat="cr", abbr="bwl blackwing lair" },
    { key="AQ20", id=842, cat="cr", abbr="aq20 ruins aqr" },
    { key="AQ40", id=843, cat="cr", abbr="aq40 temple aqt" },
    { key="NAXX", id=841, cat="cr", abbr="naxx naxxramas" },
    { key="RAMPS",id=913, cat="bd", abbr="ramps ramparts hellfire ramp" },
    { key="BF",   id=912, cat="bd", abbr="bf blood furnace bloodfurnace" },
    { key="SP",   id=909, cat="bd", abbr="sp slave pens slave" },
    { key="UB",   id=911, cat="bd", abbr="ub underbog bog" },
    { key="MT",   id=904, cat="bd", abbr="mt mana tombs manatombs" },
    { key="AC",   id=903, cat="bd", abbr="ac crypts crypt auchenai" },
    { key="SETH", id=905, cat="bd", abbr="seth sethekk" },
    { key="SL",   id=906, cat="bd", abbr="sl shadow labyrinth labs labyrinth" },
    { key="SV",   id=910, cat="bd", abbr="sv steamvault steam" },
    { key="MECH", id=916, cat="bd", abbr="mech mechanar" },
    { key="BOT",  id=918, cat="bd", abbr="bot botanica" },
    { key="ARC",  id=915, cat="bd", abbr="arc arcatraz" },
    { key="OHB",  id=908, cat="bd", abbr="ohb hillsbrad durnholde escape" },
    { key="BM",   id=907, cat="bd", abbr="bm morass blackmorass" },
    { key="SH",   id=914, cat="bd", abbr="sh shattered shatteredhalls" },
    { key="MGT",  id=917, cat="bd", abbr="mgt magisters terrace" },
    { key="KARA", id=844, cat="br", abbr="kara karazhan kz" },
    { key="GL",   id=846, cat="br", abbr="gruul gruuls gl" },
    { key="MAG",  id=845, cat="br", abbr="mag magtheridon magth" },
    { key="SSC",  id=848, cat="br", abbr="ssc serpentshrine vashj" },
    { key="EYE",  id=847, cat="br", abbr="tk tempest eye kael" },
    { key="HYJAL",id=849, cat="br", abbr="hyjal mh" },
    { key="BT",   id=850, cat="br", abbr="bt blacktemple illidan" },
    { key="SWP",  id=852, cat="br", abbr="swp sunwell plateau" },
    { key="ZA",   id=851, cat="br", abbr="za zulaman aman" },
}
local byKey = {}
for _, d in ipairs(DUNGEONS) do byKey[d.key] = d end

-- On Classic Era the TBC activity ids don't exist, so drop the bd/br entries.
local ACTIVE = {}
for _, d in ipairs(DUNGEONS) do
    if not (ns.isEra and (d.cat == "bd" or d.cat == "br")) then ACTIVE[#ACTIVE + 1] = d end
end

local SEARCH = "lfg lfm lf lf1m lf2m lf3m lf4m lf5m group grp need lf dps heal heals healer healers tank tanks dd boost run runs wts wtb"
    .. " suche sucht suchen gesucht such gruppe grp brauche heiler dd go"
local HEROIC = { h=true, hc=true, heroic=true, hero=true, ["hero"]=true, hcc=true }

-- word -> list of instance keys, since a word like "dm" can hit more than one
local tagList = {}
local searchWords = {}
local levelText = {}
local nameOf = {}
local built = false

local function addTag(word, key)
    if not word or #word < 2 then return end
    local t = tagList[word]
    if not t then t = {}; tagList[word] = t end
    for _, k in ipairs(t) do if k == key then return end end
    t[#t + 1] = key
end

local function buildTags()
    if built then return end
    for word in (SEARCH):gmatch("%S+") do searchWords[word] = true end
    for _, d in ipairs(ACTIVE) do
        local name, lo, hi
        if d.zone and GetRealZoneText then name = GetRealZoneText(d.zone) end
        if GetActivity then
            local info = GetActivity(d.id)
            if info then
                if not name or name == "" then
                    name = (info.shortName ~= "" and info.shortName) or info.fullName
                    if name then name = name:gsub("%s*%b()%s*$", "") end  -- strip "(Heroic)" etc.
                end
                lo, hi = info.minLevel, info.maxLevel
            end
        end
        name = (name and name ~= "" and name) or d.key
        nameOf[d.key] = name
        if lo and hi and lo > 0 then levelText[d.key] = (lo == hi) and format(" |cff808080(%d)|r", lo) or format(" |cff808080(%d-%d)|r", lo, hi) end
        for word in (d.abbr or ""):gmatch("%S+") do addTag(strlower(word), d.key) end
        for word in strlower(name):gmatch("[%a]+") do
            if #word >= 4 then addTag(word, d.key) end
        end
    end
    built = true
end

local function words(msg)
    local norm = strlower(msg):gsub("[%p%c]", " ")
    local out, seen = {}, {}
    for w in norm:gmatch("%S+") do if not seen[w] then seen[w] = true; out[#out + 1] = w end end
    return out
end

-- requests[key] = { [sender] = { msg, time, channel, heroic } }
local requests = {}

local function handleMessage(msg, sender, fromWorld)
    if not msg or not sender or sender == "" then return end
    if sender == (UnitName and UnitName("player")) then return end
    local hits, hasSearch, hasHeroic
    for _, w in ipairs(words(msg)) do
        if searchWords[w] then hasSearch = true end
        if HEROIC[w] then hasHeroic = true end
        local keys = tagList[w]
        if keys then
            hits = hits or {}
            for _, k in ipairs(keys) do hits[k] = true end
        end
    end
    if not hits then return end
    -- world/LFG channels count as group-forming by themselves; elsewhere require intent words
    if not fromWorld and not hasSearch then return end
    local now = GetTime()
    for k in pairs(hits) do
        requests[k] = requests[k] or {}
        requests[k][sender] = { msg = msg, time = now, channel = fromWorld, heroic = hasHeroic }
    end
    if mod._frame and mod._frame:IsShown() then mod._refreshSoon() end
end

local function prune()
    local cutoff = GetTime() - (mod.db.window or 20) * 60
    for k, byS in pairs(requests) do
        for s, r in pairs(byS) do if r.time < cutoff then byS[s] = nil end end
    end
end

local function timeAgo(t)
    local s = floor(GetTime() - t)
    if s < 60 then return L["now"] end
    return floor(s / 60) .. "m"
end

local rows = {}
local function getRow(parent, i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, parent)
    r:SetHeight(16)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.left:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.left:SetJustifyH("LEFT")
    r.left:SetWordWrap(false)
    if ns.UI and ns.UI.Font then ns.UI.Font(r.left, 12) end
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.right:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.right:SetJustifyH("RIGHT")
    if ns.UI and ns.UI.Font then ns.UI.Font(r.right, 11) end
    r.msg = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.msg:SetPoint("LEFT", r.left, "RIGHT", 8, 0)
    r.msg:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
    r.msg:SetJustifyH("LEFT")
    r.msg:SetWordWrap(false)
    if ns.UI and ns.UI.Font then ns.UI.Font(r.msg, 11) end
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
    r:SetScript("OnClick", function(self, button)
        if not self._sender then return end
        if button == "RightButton" then
            ns:ShowPopupMenu({
                { title = true, text = self._sender:gsub("%-.*", "") },
                { text = L["Whisper"], func = function() ChatFrame_SendTell(self._sender) end },
                { text = L["Invite"],  func = function() if InviteUnit then InviteUnit(self._sender) end end },
                { text = L["Who"],     func = function() if SendWho then SendWho('n-"' .. self._sender:gsub("%-.*", "") .. '"') end end },
            }, self)
        else
            ChatFrame_SendTell(self._sender)
        end
    end)
    ns.UI:AttachTooltip(r, function(self)
        if not self._fullmsg or self._fullmsg == "" then return nil end
        -- No sender means no title line: the message alone becomes the tooltip.
        return {
            title = self._sender and self._sender:gsub("%-.*", "") or nil,
            accent = true,
            lines = { { self._fullmsg, 1, 1, 1, true } },
        }
    end)
    rows[i] = r
    return r
end

local function refresh()
    local f = mod._frame
    if not f or not f:IsShown() then return end
    prune()
    local child = f.child
    local i, y, total = 0, -4, 0

    local function header(text)
        i = i + 1; local r = getRow(child, i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y); r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        r:SetHeight(18); r:Disable(); r._sender = nil; r._fullmsg = nil
        r.left:SetText("|cff" .. format("%02x%02x%02x", ACCENT.r*255, ACCENT.g*255, ACCENT.b*255) .. text .. "|r")
        r.right:SetText(""); r.msg:SetText("")
        r:Show(); y = y - 19
    end

    for _, cat in ipairs(CAT_ORDER) do
        local catPrinted = false
        for _, d in ipairs(ACTIVE) do
            if d.cat == cat and requests[d.key] then
                local list = {}
                for s, rq in pairs(requests[d.key]) do list[#list + 1] = { s = s, rq = rq } end
                if #list > 0 then
                    table.sort(list, function(a, b) return a.rq.time > b.rq.time end)
                    if not catPrinted then header(CAT_NAME[cat] or cat); catPrinted = true end
                    i = i + 1; local h = getRow(child, i)
                    h:ClearAllPoints(); h:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y); h:SetPoint("RIGHT", child, "RIGHT", 0, 0)
                    h:SetHeight(16); h:Disable(); h._sender = nil; h._fullmsg = nil
                    h.left:SetText(format("|cffffd200%s|r%s", nameOf[d.key] or d.key, levelText[d.key] or ""))
                    h.right:SetText("|cff888888" .. #list .. "|r"); h.msg:SetText("")
                    h:Show(); y = y - 16
                    for _, e in ipairs(list) do
                        i = i + 1; local r = getRow(child, i)
                        r:ClearAllPoints(); r:SetPoint("TOPLEFT", child, "TOPLEFT", 18, y); r:SetPoint("RIGHT", child, "RIGHT", -2, 0)
                        r:SetHeight(15); r:Enable(); r._sender = e.s; r._fullmsg = e.rq.msg
                        local nm = e.s:gsub("%-.*", "")
                        r.left:SetText((e.rq.heroic and "|cffff8800[" .. L["H"] .. "]|r " or "") .. nm)
                        r.right:SetText(timeAgo(e.rq.time))
                        r.msg:SetText(e.rq.msg)
                        r:Show(); y = y - 15
                        total = total + 1
                    end
                end
            end
        end
    end

    for j = i + 1, #rows do rows[j]:Hide() end
    if total == 0 then
        i = i + 1; local r = getRow(child, i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", child, "TOPLEFT", 8, -8); r:Disable(); r._sender = nil; r._fullmsg = nil
        r.left:SetText("|cff888888" .. L["No groups forming right now."] .. "|r"); r.right:SetText(""); r.msg:SetText(""); r:Show()
        y = y - 20
    end
    child:SetHeight(math.max(1, -y + 4))
    f.title:SetText(format("%s  |cff888888(%d)|r", L["Group Board"], total))
end

local refreshPending
function mod._refreshSoon()
    if refreshPending then return end
    refreshPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function() refreshPending = false; refresh() end)
    else refreshPending = false; refresh() end
end

local function buildWindow()
    if mod._frame then return end
    local f = CreateFrame("Frame", "VulLFGFrame", UIParent)
    f:SetSize(440, 420)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    -- one-time migration of the legacy point-anchor save to a CENTER offset
    if mod.db.point then
        f:ClearAllPoints()
        f:SetPoint(mod.db.point[1] or "CENTER", UIParent, mod.db.point[2] or "CENTER",
            mod.db.point[3] or 0, mod.db.point[4] or 0)
        local fx, fy = f:GetCenter()
        local px, py = UIParent:GetCenter()
        if fx and px then mod.db.x, mod.db.y = fx - px, fy - py end
        mod.db.point = nil
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
    f:Hide()
    ns:CreateMover(f, { key = "groupboard", label = "|cffffffffGROUP BOARD|r", db = mod.db, width = 440, height = 420,
        scalable = true, anchorable = true })
    ns.UI:StyleBackdrop(f, {
        bg     = { r = 0.06, g = 0.06, b = 0.08, a = 0.97 },
        border = ACCENT,
    })

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -8); f.title:SetText(L["Group Board"])
    if ns.UI and ns.UI.Font then ns.UI.Font(f.title, 14) end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -28)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 8)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, d)
        local cur, maxs = self:GetVerticalScroll(), self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maxs, cur - d * 28)))
    end)
    local child = CreateFrame("Frame", nil, scroll); child:SetSize(1, 1); scroll:SetScrollChild(child)
    child:SetWidth(420)
    f.child = child
    f:SetScript("OnSizeChanged", function(_, w) if child then child:SetWidth(math.max(1, (w or 440) - 20)) end end)
    f:SetScript("OnShow", refresh)
    mod._frame = f
end

function mod:Toggle()
    buildWindow()
    if mod._frame:IsShown() then mod._frame:Hide() else buildTags(); mod._frame:Show() end
end

local function buildMinimap()
    if mod._mm or not Minimap then return end
    local b = CreateFrame("Button", "VulLFGMinimapButton", Minimap)
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    local overlay = b:CreateTexture(nil, "OVERLAY"); overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); overlay:SetPoint("TOPLEFT")
    local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetSize(19, 19); icon:SetPoint("CENTER", -1, 1)
    icon:SetTexture("Interface\\LFGFrame\\BattlenetWorking0")
    icon:SetTexture("Interface\\GossipFrame\\BattleMasterGossipIcon")
    b.icon = icon
    local function place()
        local a = (mod.db.mmAngle or 200)
        local rad = a * math.pi / 180
        b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(rad), 80 * math.sin(rad))
    end
    place()
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function() b:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter(); local px, py = GetCursorPosition(); local s = Minimap:GetEffectiveScale()
        px, py = px / s, py / s
        mod.db.mmAngle = math.deg(math.atan2(py - my, px - mx)); place()
    end) end)
    b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() mod:Toggle() end)
    ns.UI:AttachTooltip(b, {
        anchor = "ANCHOR_LEFT", title = L["Group Board"],
        lines  = { L["/vlfg toggles the group board."] },
    })
    mod._mm = b
end

local function isWorldChannel(cn)
    return strfind(cn, "lookingforgroup") or strfind(cn, "suchenachgruppe")
        or strfind(cn, "world") or strfind(cn, "welt")
        or strfind(cn, "general") or strfind(cn, "allgemein")
        or strfind(cn, "trade") or strfind(cn, "handel")
end

local function onChannel(_, text, sender, _, channel)
    if mod.db.scanWorld == false then return end
    local cn = channel and strlower(channel:gsub("[%s%d]", "")) or ""
    handleMessage(text, sender, isWorldChannel(cn) and true or false)
end
local function onGuild(_, text, sender) if mod.db.scanGuild ~= false then handleMessage(text, sender, false) end end
local function onSay(_, text, sender) if mod.db.scanSay ~= false then handleMessage(text, sender, false) end end

function mod:OnEnable()
    buildTags()
    mod:RegisterEvent("CHAT_MSG_CHANNEL", onChannel)
    mod:RegisterEvent("CHAT_MSG_GUILD", onGuild)
    mod:RegisterEvent("CHAT_MSG_SAY", onSay)
    mod:RegisterEvent("CHAT_MSG_YELL", onSay)
    if mod.db.minimap ~= false then buildMinimap() end
    if mod._mm then mod._mm:SetShown(mod.db.minimap ~= false) end
    if not mod._prune and C_Timer and C_Timer.NewTicker then
        mod._prune = C_Timer.NewTicker(30, function()
            if mod._frame and mod._frame:IsShown() then refresh() end
        end)
    end
end

function mod:OnDisable()
    if mod._mm then mod._mm:Hide() end
    if mod._frame then mod._frame:Hide() end
end

ns:RegisterSlash({ key = "LFGBOARD", commands = { "/vlfg", "/lfgboard" },
    desc = "Open the group finder board.",
    module = "vullfg",
})
ns.Slash.LFGBOARD = function() mod:Toggle() end

function mod:GetOptions()
    return {
        { type = "desc", text = "|cffaaaaaa" .. L["/vlfg toggles the group board."] .. "|r" },
        { type = "slider", label = L["Keep requests for (minutes)"], min = 5, max = 60, step = 5,
          get = function() return mod.db.window or 20 end, set = function(_, v) mod.db.window = v end },
        { type = "toggle", label = L["Show minimap button"],
          get = function() return mod.db.minimap end,
          set = function(_, v) mod.db.minimap = v; if v then buildMinimap() end; if mod._mm then mod._mm:SetShown(v) end end },
        { type = "toggle", label = L["Scan world / trade / LFG channels"], get = function() return mod.db.scanWorld end, set = function(_, v) mod.db.scanWorld = v end },
        { type = "toggle", label = L["Scan guild chat"], get = function() return mod.db.scanGuild end, set = function(_, v) mod.db.scanGuild = v end },
        { type = "toggle", label = L["Scan say / yell"],   get = function() return mod.db.scanSay ~= false end, set = function(_, v) mod.db.scanSay = v end },
    }
end
end)(...);

(function(...)
-- Adds ID lines (SpellID, ItemID, NPC ID, ...) to tooltips.
local _, ns = ...
local L = ns.L

-- Retail moved these into C_Spell/C_Item/C_TradeSkillUI; fall back to the globals on Classic.
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) and C_Spell.GetSpellTexture or GetSpellTexture
local GetItemIconByID = (C_Item and C_Item.GetItemIconByID) and C_Item.GetItemIconByID or GetItemIconByID
local GetItemInfoLocal = (C_Item and C_Item.GetItemInfo) and C_Item.GetItemInfo or GetItemInfo
local GetItemGem = (C_Item and C_Item.GetItemGem) and C_Item.GetItemGem or GetItemGem
local GetItemSpell = (C_Item and C_Item.GetItemSpell) and C_Item.GetItemSpell or GetItemSpell
local GetRecipeReagentItemLink = (C_TradeSkillUI and C_TradeSkillUI.GetRecipeReagentItemLink) and C_TradeSkillUI.GetRecipeReagentItemLink or GetTradeSkillReagentItemLink
local GetItemLinkByGUID = (C_Item and C_Item.GetItemLinkByGUID) and C_Item.GetItemLinkByGUID

local kinds = {
    spell         = "SpellID",
    item          = "ItemID",
    unit          = "NPC ID",
    quest         = "QuestID",
    talent        = "TalentID",
    achievement   = "AchievementID",
    criteria      = "CriteriaID",
    ability       = "AbilityID",
    currency      = "CurrencyID",
    artifactpower = "ArtifactPowerID",
    enchant       = "EnchantID",
    bonus         = "BonusID",
    gem           = "GemID",
    mount         = "MountID",
    companion     = "CompanionID",
    macro         = "MacroID",
    set           = "SetID",
    visual        = "VisualID",
    source        = "SourceID",
    species       = "SpeciesID",
    icon          = "IconID",
    areapoi       = "AreaPoiID",
    vignette      = "VignetteID",
    expansion     = "ExpansionID",
    object        = "ObjectID",
    traitnode     = "TraitNodeID",
    traitentry    = "TraitEntryID",
    traitdef      = "TraitDefinitionID",
}

local kindOrder = {
    "spell", "item", "unit", "quest", "talent",
    "achievement", "criteria", "ability", "currency",
    "enchant", "gem", "icon", "macro", "set",
    "mount", "companion", "species", "object",
    "areapoi", "vignette", "expansion", "visual",
    "source", "artifactpower", "bonus",
    "traitnode", "traitentry", "traitdef",
}

local defaultDisabledKinds = {
    bonus = true, traitnode = true, traitentry = true, traitdef = true,
}

-- TooltipDataProcessor enum value -> kind (Retail only).
local kindsByID = {
    [0]  = "item",        [1]  = "spell",  [2]  = "unit",      [3]  = "unit",
    [4]  = "object",      [5]  = "currency", [6]  = "unit",    [7]  = "spell",
    [8]  = "spell",       [9]  = "unit",   [10] = "mount",     [11] = "spell",
    [12] = "achievement", [13] = "spell",  [14] = "set",       [15] = "",
    [16] = "",            [17] = "spell",  [18] = "spell",     [19] = "item",
    [20] = "",            [21] = "",       [22] = "",          [23] = "quest",
    [24] = "quest",       [25] = "macro",  [26] = "",
}

local moduleDefaults = { enabled = true }
for kind in pairs(kinds) do
    moduleDefaults[kind] = not defaultDisabledKinds[kind]
end
moduleDefaults.showPlayerILvl    = true
moduleDefaults.showPlayerTalents = true

local mod = ns:RegisterModule("tooltipids", {
    name        = "Tooltip IDs",
    group       = "Extras",
    description = "Shows SpellID, ItemID, NPC ID and many other IDs in tooltips (based on idTip by silverwind).",
    defaults    = moduleDefaults,
})

mod.kinds      = kinds
mod.kindOrder  = kindOrder

local function isEnabled(kind)
    if not mod._enabled then return false end
    return mod.db[kind] and true or false
end

local function contains(t, element)
    for _, value in pairs(t) do
        if value == element then return true end
    end
    return false
end

local function hook(table, fn, cb)
    if table and table[fn] then
        hooksecurefunc(table, fn, cb)
    end
end

local function hookScript(table, fn, cb)
    if table and table.HasScript and table:HasScript(fn) then
        table:HookScript(fn, cb)
    end
end

local function getTooltipName(tooltip)
    return tooltip:GetName() or nil
end

local function isSecret(value)
    if not issecretvalue or not issecrettable then return false end
    return issecretvalue(value) or issecrettable(value)
end

local function addLine(tooltip, id, kind)
    if isSecret(id) then return end
    if not id or id == "" or not tooltip or not tooltip.GetName then return end
    if not isEnabled(kind) then return end

    local ok, name = pcall(getTooltipName, tooltip)
    if not ok or not name then return end

    local frame, text
    for i = tooltip:NumLines(), 1, -1 do
        frame = _G[name .. "TextLeft" .. i]
        if frame then text = frame:GetText() end
        if isSecret(text) then return end
        if text and string.find(text, kinds[kind]) then return end
    end

    local multiple = type(id) == "table"
    if multiple and #id == 1 then
        id = id[1]
        multiple = false
    end

    local left  = kinds[kind] .. (multiple and "s" or "")
    local right = multiple and table.concat(id, ",") or id
    local wfc = WHITE_FONT_COLOR or { r = 1, g = 1, b = 1 }
    tooltip:AddDoubleLine(left, right, nil, nil, nil, wfc.r, wfc.g, wfc.b)
    tooltip:Show()
end

local function isStringOrNumber(val)
    local t = type(val)
    return (t == "string") or (t == "number")
end

local function add(tooltip, id, kind)
    addLine(tooltip, id, kind)

    if kind == "spell" and GetSpellTexture and isStringOrNumber(id) then
        local iconId = GetSpellTexture(id)
        if iconId then add(tooltip, iconId, "icon") end
    end

    if kind == "item" and GetItemIconByID and isStringOrNumber(id) then
        local iconId = GetItemIconByID(id)
        if iconId then add(tooltip, iconId, "icon") end
    end

    if kind == "item" and GetItemSpell and isStringOrNumber(id) then
        local spellId = select(2, GetItemSpell(id))
        if spellId then add(tooltip, spellId, "spell") end
    end

    if kind == "macro" then
        if tooltip.GetPrimaryTooltipData then
            local data = tooltip:GetPrimaryTooltipData()
            if data and data.lines and data.lines[1] and data.lines[1].tooltipID then
                add(tooltip, data.lines[1].tooltipID, "spell")
                return
            end
        end
        if tooltip.GetSpell then
            local spellID = select(2, tooltip:GetSpell())
            if spellID then add(tooltip, spellID, "spell"); return end
        end
        if GetMacroSpell and isStringOrNumber(id) then
            local spellID = select(3, GetMacroSpell(id))
            if spellID then add(tooltip, spellID, "spell") end
        end
    end
end

local function addByKind(tooltip, id, kind)
    if not kind or not id then return end
    if kind == "spell" or kind == "enchant" or kind == "trade" then
        add(tooltip, id, "spell")
    elseif kinds[kind] then
        add(tooltip, id, kind)
    end
end

local function addItemInfo(tooltip, link)
    if not link then return end
    local itemString = string.match(link, "item:([%-?%d:]+)")
    if not itemString then return end

    local bonuses = {}
    local itemSplit = {}

    for v in string.gmatch(itemString, "(%d*:?)") do
        if v == ":" then
            itemSplit[#itemSplit + 1] = 0
        else
            itemSplit[#itemSplit + 1] = string.gsub(v, ":", "")
        end
    end

    if itemSplit[13] then
        for index = 1, tonumber(itemSplit[13]) or 0 do
            bonuses[#bonuses + 1] = itemSplit[13 + index]
        end
    end

    local gems = {}
    if GetItemGem then
        for i = 1, 4 do
            local gemLink = select(2, GetItemGem(link, i))
            if gemLink then
                local gemDetail = string.match(gemLink, "item[%-?%d:]+")
                gems[#gems + 1] = string.match(gemDetail, "item:(%d+):")
            end
        end
    end

    local itemId = string.match(link, "item:(%d*)")
    if (itemId == "" or itemId == "0") and TradeSkillFrame and TradeSkillFrame.RecipeList
       and TradeSkillFrame:IsVisible() and GetRecipeReagentItemLink and GetMouseFocus then
        local focus = GetMouseFocus()
        if focus and focus.reagentIndex then
            local selectedRecipe = TradeSkillFrame.RecipeList:GetSelectedRecipeID()
            for i = 1, 8 do
                if focus.reagentIndex == i then
                    local rlink = GetRecipeReagentItemLink(selectedRecipe, i)
                    if rlink then
                        itemId = rlink:match("item:(%d*)") or nil
                    end
                    break
                end
            end
        end
    end

    if itemId then
        add(tooltip, itemId, "item")
        if itemSplit[2] and itemSplit[2] ~= 0 then add(tooltip, itemSplit[2], "enchant") end
        if #bonuses ~= 0 then add(tooltip, bonuses, "bonus") end
        if #gems ~= 0 then add(tooltip, gems, "gem") end

        if GetItemInfoLocal then
            local expansionId = select(15, GetItemInfoLocal(itemId))
            if expansionId and expansionId ~= 254 then
                add(tooltip, expansionId, "expansion")
            end
            local setId = select(16, GetItemInfoLocal(itemId))
            if setId then
                add(tooltip, setId, "set")
            end
        end
    end
end

local function attachItemTooltip(tooltip, id)
    if (tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2)
       and tooltip.info and tooltip.info.tooltipData and tooltip.info.tooltipData.guid
       and GetItemLinkByGUID then
        local link = GetItemLinkByGUID(tooltip.info.tooltipData.guid)
        if link then addItemInfo(tooltip, link) else add(tooltip, id, "item") end
    elseif tooltip.GetItem then
        local link = select(2, tooltip:GetItem())
        if link then addItemInfo(tooltip, link) else add(tooltip, id, "item") end
    else
        add(tooltip, id, "item")
    end
end

-- ANCHOR_NONE plus an explicit point: the tooltip is placed against the
-- achievement row itself, not offset from it, so no anchor rule applies here.
local function achievementOnEnter(btn)
    if not ns.UI:OpenTooltip(btn, "ANCHOR_NONE") then return end
    GameTooltip:SetPoint("TOPLEFT", btn, "TOPRIGHT", 0, 0)
    add(GameTooltip, btn.id, "achievement")
    GameTooltip:Show()
end

local function criteriaOnEnter(enterIndex)
    return function(frame)
        if not GetAchievementCriteriaInfo then return end
        local btn = frame:GetParent() and frame:GetParent():GetParent()
        if not btn or not btn.id then return end
        local achievementId = btn.id
        local index = frame.___index or enterIndex
        if index > GetAchievementNumCriteria(achievementId) then return end
        local criteriaId = select(10, GetAchievementCriteriaInfo(achievementId, index))
        if criteriaId then
            if not GameTooltip:IsVisible() then
                ns.UI:OpenTooltip(btn:GetParent(), "ANCHOR_NONE")
            end
            GameTooltip:SetPoint("TOPLEFT", btn, "TOPRIGHT", 0, 0)
            add(GameTooltip, achievementId, "achievement")
            add(GameTooltip, criteriaId, "criteria")
            GameTooltip:Show()
        end
    end
end

local hookedTooltips = {}

local function onSetItem(tooltip) attachItemTooltip(tooltip, nil) end

local function hookAddonTooltip(tooltip)
    if not tooltip or hookedTooltips[tooltip] then return end
    hookedTooltips[tooltip] = true

    hook(tooltip, "SetSpellBookItem", function(tt, slot, bookType)
        if GetSpellBookItemInfo then
            local spellID = select(2, GetSpellBookItemInfo(slot, bookType))
            if spellID then add(tt, spellID, "spell") end
        end
    end)
    hook(tooltip, "SetSpellByID", function(tt, id) addByKind(tt, id, "spell") end)
    hookScript(tooltip, "OnTooltipSetItem", onSetItem)
    hookScript(tooltip, "OnTooltipSetSpell", function(tip)
        if tip.GetSpell then
            local id = select(2, tip:GetSpell())
            add(tip, id, "spell")
        end
    end)
end

local function scanAddonTooltips()
    local f = EnumerateFrames()
    while f do
        if f.IsObjectType and f:IsObjectType("GameTooltip") and not hookedTooltips[f] then
            hookAddonTooltip(f)
        end
        f = EnumerateFrames(f)
    end
end

local hooksInstalled = false
local function installHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    hookedTooltips[GameTooltip] = true

    if TooltipDataProcessor then
        TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, data)
            if not data or not data.type then return end
            if isSecret(data.type) or isSecret(data.guid) then return end
            local kind = kindsByID[tonumber(data.type)]

            if kind == "unit" and data and data.guid then
                local unitId = tonumber(data.guid:match("-(%d+)-%x+$"), 10)
                if unitId and data.guid:match("%a+") ~= "Player" then
                    add(tooltip, unitId, "unit")
                else
                    add(tooltip, data.id, "unit")
                end
            elseif kind == "item" and data and data.guid and GetItemLinkByGUID then
                local link = GetItemLinkByGUID(data.guid)
                if link then addItemInfo(tooltip, link) else add(tooltip, data.id, kind) end
            elseif kind and kind ~= "" then
                add(tooltip, data.id, kind)
            end
        end)
    end

    if GetActionInfo then
        hook(GameTooltip, "SetAction", function(tooltip, slot)
            local kind, id = GetActionInfo(slot)
            addByKind(tooltip, id, kind)
        end)
    end

    if TalentDisplayMixin then
        hook(TalentDisplayMixin, "SetTooltipInternal", function(btn)
            if not btn then return end
            add(GameTooltip, btn.entryID, "traitentry")
            add(GameTooltip, btn.definitionID, "traitdef")
            if btn.GetNodeInfo then
                local info = btn:GetNodeInfo()
                if info then add(GameTooltip, info.ID, "traitnode") end
            end
        end)
    end

    local function onSetHyperlink(tooltip, link)
        local kind, id = string.match(link, "^(%a+):(%d+)")
        addByKind(tooltip, id, kind)
    end
    hook(ItemRefTooltip, "SetHyperlink", onSetHyperlink)
    hook(GameTooltip,   "SetHyperlink", onSetHyperlink)

    if UnitBuff then
        hook(GameTooltip, "SetUnitBuff", function(tooltip, ...)
            local id = select(10, UnitBuff(...))
            add(tooltip, id, "spell")
        end)
    end

    if UnitDebuff then
        hook(GameTooltip, "SetUnitDebuff", function(tooltip, ...)
            local id = select(10, UnitDebuff(...))
            add(tooltip, id, "spell")
        end)
    end

    if UnitAura then
        hook(GameTooltip, "SetUnitAura", function(tooltip, ...)
            local id = select(10, UnitAura(...))
            add(tooltip, id, "spell")
        end)
    end

    hook(GameTooltip, "SetSpellByID", function(tooltip, id) addByKind(tooltip, id, "spell") end)

    hook(_G, "SetItemRef", function(link)
        local id = tonumber(link:match("spell:(%d+)"))
        add(ItemRefTooltip, id, "spell")
    end)

    hookScript(GameTooltip, "OnTooltipSetSpell", function(tooltip)
        if tooltip.GetSpell then
            local id = select(2, tooltip:GetSpell())
            add(tooltip, id, "spell")
        end
    end)

    if SpellBook_GetSpellBookSlot then
        hook(_G, "SpellButton_OnEnter", function(btn)
            local slot = SpellBook_GetSpellBookSlot(btn)
            if slot and GetSpellBookItemInfo and SpellBookFrame then
                local spellID = select(2, GetSpellBookItemInfo(slot, SpellBookFrame.bookType))
                add(GameTooltip, spellID, "spell")
            end
        end)
    end

    hook(GameTooltip, "SetRecipeResultItem", function(tooltip, id) add(tooltip, id, "spell") end)
    hook(GameTooltip, "SetRecipeRankInfo",   function(tooltip, id) add(tooltip, id, "spell") end)

    if C_ArtifactUI and C_ArtifactUI.GetPowerInfo then
        hook(GameTooltip, "SetArtifactPowerByID", function(tooltip, powerID)
            local powerInfo = C_ArtifactUI.GetPowerInfo(powerID)
            add(tooltip, powerID, "artifactpower")
            if powerInfo then add(tooltip, powerInfo.spellID, "spell") end
        end)
    end

    if GetTalentInfoByID then
        hook(GameTooltip, "SetTalent", function(tooltip, id)
            local ok, result = pcall(GetTalentInfoByID, id)
            if not ok then return end
            local spellID = select(6, result)
            add(tooltip, id, "talent")
            add(tooltip, spellID, "spell")
        end)
    end

    if GetPvpTalentInfoByID then
        hook(GameTooltip, "SetPvpTalent", function(tooltip, id)
            local spellID = select(6, GetPvpTalentInfoByID(id))
            add(tooltip, id, "talent")
            add(tooltip, spellID, "spell")
        end)
    end

    if C_PetJournal and C_PetJournal.GetPetInfoByPetID then
        hook(GameTooltip, "SetCompanionPet", function(_tooltip, petId)
            local speciesId = select(1, C_PetJournal.GetPetInfoByPetID(petId))
            if speciesId then
                local npcId = select(4, C_PetJournal.GetPetInfoBySpeciesID(speciesId))
                add(GameTooltip, speciesId, "species")
                add(GameTooltip, npcId, "unit")
            end
        end)
    end

    hookScript(GameTooltip, "OnTooltipSetUnit", function(tooltip)
        if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return end
        local unit = select(2, tooltip:GetUnit())
        if unit and UnitGUID then
            local guid = UnitGUID(unit) or ""
            local id = tonumber(guid:match("-(%d+)-%x+$"), 10)
            if id and guid:match("%a+") ~= "Player" then
                add(GameTooltip, id, "unit")
            end
        end
    end)

    hook(GameTooltip, "SetToyByItemID",       function(tooltip, id) add(tooltip, id, "item") end)
    hook(GameTooltip, "SetRecipeReagentItem", function(tooltip, id) add(tooltip, id, "item") end)

    hookScript(GameTooltip, "OnTooltipSetItem", onSetItem)

    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListLink then
        hook(GameTooltip, "SetCurrencyToken", function(tooltip, index)
            local link = C_CurrencyInfo.GetCurrencyListLink(index)
            if link then
                local id = tonumber(string.match(link, "currency:(%d+)"))
                add(tooltip, id, "currency")
            end
        end)
    end
    hook(GameTooltip, "SetCurrencyByID",        function(tooltip, id) add(tooltip, id, "currency") end)
    hook(GameTooltip, "SetCurrencyTokenByID",   function(tooltip, id) add(tooltip, id, "currency") end)

    if C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then
        hook(_G, "QuestMapLogTitleButton_OnEnter", function(tooltip)
            if tooltip and tooltip.questLogIndex then
                local id = C_QuestLog.GetQuestIDForLogIndex(tooltip.questLogIndex)
                add(GameTooltip, id, "quest")
            end
        end)
    end

    hook(_G, "TaskPOI_OnEnter", function(tooltip)
        if tooltip and tooltip.questID then add(GameTooltip, tooltip.questID, "quest") end
    end)

    -- Retail-only mixins; nil on TBC, where hook() is a no-op.
    if AreaPOIPinMixin then
        hook(AreaPOIPinMixin, "TryShowTooltip", function(tooltip)
            if tooltip and tooltip.areaPoiID then add(GameTooltip, tooltip.areaPoiID, "areapoi") end
        end)
    end
    if VignettePinMixin then
        hook(VignettePinMixin, "OnMouseEnter", function(tooltip)
            if tooltip and tooltip.vignetteInfo and tooltip.vignetteInfo.vignetteID then
                add(GameTooltip, tooltip.vignetteInfo.vignetteID, "vignette")
            end
        end)
    end

    if C_PetBattles and C_PetBattles.GetActivePet and C_PetBattles.GetAbilityInfo then
        hook(_G, "PetBattleAbilityButton_OnEnter", function(btn)
            local petIndex = C_PetBattles.GetActivePet(LE_BATTLE_PET_ALLY)
            if btn:GetEffectiveAlpha() > 0 then
                local id = select(1, C_PetBattles.GetAbilityInfo(LE_BATTLE_PET_ALLY, petIndex, btn:GetID()))
                if id and PetBattlePrimaryAbilityTooltip then
                    local oldText = PetBattlePrimaryAbilityTooltip.Description:GetText()
                    PetBattlePrimaryAbilityTooltip.Description:SetText(
                        (oldText or "") .. "\r\r" .. kinds.ability .. "|cffffffff " .. id .. "|r"
                    )
                end
            end
        end)
    end
    if C_PetBattles and C_PetBattles.GetAuraInfo then
        hook(_G, "PetBattleAura_OnEnter", function(frame)
            local parent = frame:GetParent()
            if parent then
                local id = select(1, C_PetBattles.GetAuraInfo(parent.petOwner, parent.petIndex, frame.auraIndex))
                if id and PetBattlePrimaryAbilityTooltip then
                    local oldText = PetBattlePrimaryAbilityTooltip.Description:GetText()
                    PetBattlePrimaryAbilityTooltip.Description:SetText(
                        (oldText or "") .. "\r\r" .. kinds.ability .. "|cffffffff " .. id .. "|r"
                    )
                end
            end
        end)
    end
end

local inspectCache = {}                -- guid -> { talents={t1,t2,t3}, ilvl=N, expiry=time }
local inspectFail  = {}                -- guid -> expiry; negative cache, suppresses retry
local INSPECT_CACHE_TIME = 60
local INSPECT_FAIL_TIME  = 30
local INSPECT_THROTTLE   = 1.0
local INSPECT_PARTIAL_TIME = 5
local lastInspectTime    = 0
local pendingInspectGUID = nil
local pendingInspectUnit = nil
local recomputeGUID      = nil
local recomputeUnit      = nil

local function getCachedInspect(guid)
    local d = inspectCache[guid]
    if d and d.expiry > GetTime() then return d end
    return nil
end

local function requestInspect(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    if not CanInspect or not CanInspect(unit) then return end
    if UnitIsVisible and not UnitIsVisible(unit) then return end
    if (GetTime() - lastInspectTime) < INSPECT_THROTTLE then return end
    local guid = UnitGUID(unit)
    if not guid or getCachedInspect(guid) then return end
    if inspectFail[guid] and inspectFail[guid] > GetTime() then return end

    pendingInspectGUID = guid
    pendingInspectUnit = unit
    lastInspectTime    = GetTime()
    -- Pre-mark as failed; INSPECT_READY clears it again.
    inspectFail[guid] = GetTime() + INSPECT_FAIL_TIME
    if NotifyInspect then NotifyInspect(unit) end
end

-- Returns (ilvl, complete); complete is false while an equipped item's level is
-- still uncached, which drags the average low until the data streams in.
local function computeAverageILvl(unit)
    if not GetInventoryItemLink then return 0, true end
    local total, count, missing = 0, 0, 0
    -- Slots 1-18 are equipment; 4 is Shirt and 19 is Tabard, neither has an ilvl.
    for slot = 1, 18 do
        if slot ~= 4 then
            local link = GetInventoryItemLink(unit, slot)
            if link then
                local ilvl
                if C_Item and C_Item.GetDetailedItemLevelInfo then
                    local ok, lvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
                    if ok then ilvl = lvl end
                end
                if not ilvl then
                    local _, _, _, lvl = GetItemInfo(link)  -- queues an async load when uncached
                    ilvl = lvl
                end
                if ilvl and ilvl > 0 then
                    total = total + ilvl
                    count = count + 1
                else
                    missing = missing + 1
                end
            end
        end
    end
    if count == 0 then return 0, missing == 0 end
    return math.floor(total / count + 0.5), missing == 0
end

local function computeTalents(isInspect)
    if not GetNumTalentTabs or not GetTalentInfo or not GetNumTalents then return nil end
    local n = GetNumTalentTabs(isInspect or false) or 3
    local t = {}
    for tab = 1, n do
        local numTalents = GetNumTalents(tab, isInspect or false) or 0
        local spent = 0
        for i = 1, numTalents do
            local _, _, _, _, rank = GetTalentInfo(tab, i, isInspect or false)
            if rank and rank > 0 then spent = spent + rank end
        end
        t[tab] = spent
    end
    return t
end

local function onInspectReady(_, guid)
    -- A stale async result would cache the pending unit's gear under a foreign GUID.
    if guid and pendingInspectGUID and guid ~= pendingInspectGUID then return end
    guid = guid or pendingInspectGUID
    if not guid then return end
    inspectFail[guid] = nil
    local unit = pendingInspectUnit
    pendingInspectGUID = nil
    pendingInspectUnit = nil
    if not unit or not UnitExists(unit) then return end

    local now = GetTime()
    for g, d in pairs(inspectCache) do
        if d.expiry <= now then inspectCache[g] = nil end
    end
    for g, exp in pairs(inspectFail) do
        if exp <= now then inspectFail[g] = nil end
    end

    local talents = computeTalents(true)
    local ilvl, complete = computeAverageILvl(unit)
    inspectCache[guid] = {
        talents = talents, ilvl = ilvl,
        expiry  = GetTime() + (complete and INSPECT_CACHE_TIME or INSPECT_PARTIAL_TIME),
    }
    if complete then
        recomputeGUID, recomputeUnit = nil, nil
    else
        recomputeGUID, recomputeUnit = guid, unit
    end
    -- SetUnit re-fires every tooltip hook, which re-renders our lines.
    if GameTooltip and GameTooltip:IsShown() then
        local _, ttUnit = GameTooltip:GetUnit()
        if ttUnit and UnitGUID(ttUnit) == guid then
            GameTooltip:SetUnit(ttUnit)
        end
    end
end

local function onItemInfoReceived()
    if not recomputeGUID then return end
    local unit = recomputeUnit
    if not unit or not UnitExists(unit) or UnitGUID(unit) ~= recomputeGUID then
        recomputeGUID, recomputeUnit = nil, nil
        return
    end
    local ilvl, complete = computeAverageILvl(unit)
    local d = inspectCache[recomputeGUID]
    if d then
        d.ilvl = ilvl
        if complete then d.expiry = GetTime() + INSPECT_CACHE_TIME end
    end
    if complete then
        local g = recomputeGUID
        recomputeGUID, recomputeUnit = nil, nil
        if GameTooltip and GameTooltip:IsShown() then
            local _, ttUnit = GameTooltip:GetUnit()
            if ttUnit and UnitGUID(ttUnit) == g then GameTooltip:SetUnit(ttUnit) end
        end
    end
end

local function onPlayerTooltipUnit(tooltip)
    if not mod._enabled then return end
    if not (mod.db.showPlayerILvl or mod.db.showPlayerTalents) then return end
    local _, unit = tooltip:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    local data = getCachedInspect(guid)
    if data then
        if mod.db.showPlayerTalents and data.talents and data.talents[1] then
            local s = string.format("%d/%d/%d",
                data.talents[1] or 0, data.talents[2] or 0, data.talents[3] or 0)
            tooltip:AddLine(L["|cff9b6cffTalents:|r "] .. s)
        end
        if mod.db.showPlayerILvl and data.ilvl and data.ilvl > 0 then
            tooltip:AddLine(string.format(L["|cff9b6cffiLvL:|r %d"], data.ilvl))
        end
    else
        requestInspect(unit)
    end
end

function mod:OnEnable()
    installHooks()
    scanAddonTooltips()

    -- On Anniversary only the legacy OnTooltipSetUnit fires, not TooltipDataProcessor.
    -- INSPECT_TALENT_READY does not exist there at all; the registry pcalls both
    -- the register and the unregister, so an unknown event is simply ignored.
    mod:RegisterEvent("INSPECT_READY",         onInspectReady)
    mod:RegisterEvent("INSPECT_TALENT_READY",  onInspectReady)
    mod:RegisterEvent("GET_ITEM_INFO_RECEIVED", onItemInfoReceived)
    -- HookScript appends every call, so a re-enable would double the tooltip lines.
    if GameTooltip and GameTooltip.HookScript and not mod._tooltipHooked then
        mod._tooltipHooked = true
        GameTooltip:HookScript("OnTooltipSetUnit", onPlayerTooltipUnit)
    end

    -- The two below stay on ns:RegisterEvent ON PURPOSE, unlike everything above.
    -- They are fresh closures, so the registry cannot recognise them as
    -- duplicates on a re-enable -- hence the session guard. And a session guard
    -- plus module ownership would be a trap: SafeDisable would take them out and
    -- the guard would refuse to put them back. They only install permanent
    -- Blizzard hooks anyway, and gate their own bodies on mod._enabled.
    if mod._lazyEventsHooked then return end
    mod._lazyEventsHooked = true

    ns:RegisterEvent("ADDON_LOADED", function(_, addonName)
        if not mod._enabled then return end
        scanAddonTooltips()

        if addonName == "Blizzard_AchievementUI" then
            if AchievementTemplateMixin then
                hook(AchievementTemplateMixin, "OnEnter", achievementOnEnter)
                hook(AchievementTemplateMixin, "OnLeave", GameTooltip_Hide)
                local hooked = {}
                local getter = function(pool)
                    return function(self, index)
                        if not self or not self[pool] then return end
                        local frame = self[pool][index]
                        if frame then
                            frame.___index = index
                            if not hooked[frame] then
                                hookScript(frame, "OnEnter", criteriaOnEnter(index))
                                hookScript(frame, "OnLeave", GameTooltip_Hide)
                                hooked[frame] = true
                            end
                        end
                    end
                end
                local objFrame = AchievementTemplateMixin.GetObjectiveFrame and AchievementTemplateMixin:GetObjectiveFrame()
                if objFrame then
                    hook(objFrame, "GetCriteria",        getter("criterias"))
                    hook(objFrame, "GetMiniAchievement", getter("miniAchivements"))
                    hook(objFrame, "GetMeta",            getter("metas"))
                    hook(objFrame, "GetProgressBar",     getter("progressBars"))
                end
            elseif AchievementFrameAchievementsContainer
                   and AchievementFrameAchievementsContainer.buttons then
                for _, button in ipairs(AchievementFrameAchievementsContainer.buttons) do
                    hookScript(button, "OnEnter", achievementOnEnter)
                    hookScript(button, "OnLeave", GameTooltip_Hide)
                end
                local hooked = {}
                hook(_G, "AchievementButton_GetCriteria", function(index, renderOffScreen)
                    local frame = _G["AchievementFrameCriteria" .. (renderOffScreen and "OffScreen" or "") .. index]
                    if frame and not hooked[frame] then
                        hookScript(frame, "OnEnter", criteriaOnEnter(index))
                        hookScript(frame, "OnLeave", GameTooltip_Hide)
                        hooked[frame] = true
                    end
                end)
            end

        elseif addonName == "Blizzard_Collections" then
            if CollectionWardrobeUtil then
                hook(CollectionWardrobeUtil, "SetAppearanceTooltip", function(_frame, sources)
                    local visualIDs, sourceIDs, itemIDs = {}, {}, {}
                    for i = 1, #sources do
                        if sources[i].visualID and not contains(visualIDs, sources[i].visualID) then table.insert(visualIDs, sources[i].visualID) end
                        if sources[i].sourceID and not contains(sourceIDs, sources[i].sourceID) then table.insert(sourceIDs, sources[i].sourceID) end
                        if sources[i].itemID and not contains(itemIDs, sources[i].itemID) then table.insert(itemIDs, sources[i].itemID) end
                    end
                    if #visualIDs == 1 then add(GameTooltip, visualIDs[1], "visual") end
                    if #sourceIDs == 1 then add(GameTooltip, sourceIDs[1], "source") end
                    if #itemIDs == 1 then add(GameTooltip, itemIDs[1], "item") end
                    if #visualIDs > 1 then add(GameTooltip, visualIDs, "visual") end
                    if #sourceIDs > 1 then add(GameTooltip, sourceIDs, "source") end
                    if #itemIDs > 1 then add(GameTooltip, itemIDs, "item") end
                end)
            end
            if PetJournalPetCardPetInfo and C_PetJournal then
                hookScript(PetJournalPetCardPetInfo, "OnEnter", function()
                    if not C_PetBattles or not C_PetBattles.GetPetInfoBySpeciesID then return end
                    if PetJournalPetCard.speciesID then
                        local npcId = select(4, C_PetJournal.GetPetInfoBySpeciesID(PetJournalPetCard.speciesID))
                        add(GameTooltip, PetJournalPetCard.speciesID, "species")
                        add(GameTooltip, npcId, "unit")
                    end
                end)
            end

        elseif addonName == "Blizzard_GarrisonUI" then
            hook(_G, "AddAutoCombatSpellToTooltip", function(tooltip, info)
                if info and info.autoCombatSpellID then
                    add(tooltip, info.autoCombatSpellID, "ability")
                end
            end)
        end
    end)

    ns:RegisterEvent("PLAYER_LOGIN", function()
        if not mod._enabled then return end
        scanAddonTooltips()
    end)
end

local function kindCheckbox(kind)
    return {
        type = "checkbox",
        label = kinds[kind] .. (defaultDisabledKinds[kind] and L["  |cff888888(off by default)|r"] or ""),
        tooltip = string.format(L["Shows %s in tooltips."], kinds[kind]),
        get = function() return mod.db[kind] end,
        set = function(_, v) mod.db[kind] = v end,
    }
end

function mod:GetOptions()
    local items = {
        { type = "header", text = L["General"] },
        { type = "desc",   text = L["Shows additional ID lines in tooltips, e.g. spell, item or NPC IDs."] },
        { type = "spacer" },
        { type = "header", text = L["Quick Select"] },
        {
            type = "group", layout = "row", gap = 6,
            items = {
                { type = "button", label = L["All on"], width = 80, onClick = function()
                    for k in pairs(kinds) do mod.db[k] = true end
                    ns.UI:BuildOptionsPage("tooltipids")
                end },
                { type = "button", label = L["All off"], width = 80, onClick = function()
                    for k in pairs(kinds) do mod.db[k] = false end
                    ns.UI:BuildOptionsPage("tooltipids")
                end },
                { type = "button", label = L["Defaults"], width = 80, onClick = function()
                    for k in pairs(kinds) do
                        mod.db[k] = not defaultDisabledKinds[k]
                    end
                    ns.UI:BuildOptionsPage("tooltipids")
                end },
            },
        },
        { type = "spacer", height = 8 },
        { type = "header", text = L["Player Tooltip (Inspect-based)"] },
        { type = "desc",
          text = L["|cffaaaaaaWhen you hover over a player, their average iLvL + talent distribution (e.g. 14/0/47) is shown in the tooltip. Data is cached 60s per player, inspect throttle 1/s.|r"] },
        { type = "toggle", label = L["Show average iLvL"],
          get = function() return mod.db.showPlayerILvl end,
          set = function(_, v) mod.db.showPlayerILvl = v end },
        { type = "toggle", label = L["Show talent distribution (e.g. 14/0/47)"],
          get = function() return mod.db.showPlayerTalents end,
          set = function(_, v) mod.db.showPlayerTalents = v end },

        { type = "spacer", height = 8 },
        { type = "header", text = L["ID Types"] },
        { type = "desc",   text = L["Which IDs should be shown in tooltips? Some types do not exist on this game version and are ignored (e.g. TraitNodeID, SourceID)."] },
        { type = "spacer", height = 4 },
    }

    local checkboxes = {}
    for _, kind in ipairs(kindOrder) do
        if kinds[kind] then
            table.insert(checkboxes, kindCheckbox(kind))
        end
    end
    table.insert(items, {
        type = "group", layout = "columns",
        items = checkboxes,
    })

    return items
end
end)(...);

(function(...)
-- VuloClassicUI / Modules / SpamFilter
-- Blizzard does not allow add-ons to file spam reports, so we hide messages
-- instead; /ignore is optional (~50 slots, spammers rotate names) and off by default.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("spamfilter", {
    name        = "Spam Filter",
    group       = "Chat & Social",
    description = "Hide (and optionally ignore) chat spammers whose names spell 'casino' & co. with look-alike letters.",
    defaults = {
        enabled       = true,
        hide          = true,   -- swallow their chat messages
        autoIgnore    = false,  -- also add them to the ignore list (~50 slot limit)
        scanMessage   = false,  -- also match against the message text, not just the name
        blockLinks    = false,  -- also hide messages that contain a web link
        extraKeywords = "",     -- comma-separated extra keywords
        whitelist     = "",     -- comma-separated names that are never filtered
    },
})

local CONFUSABLES = {
    -- a
    ["á"]="a",["à"]="a",["â"]="a",["ä"]="a",["ã"]="a",["å"]="a",["ā"]="a",["ă"]="a",["ą"]="a",
    ["Á"]="a",["À"]="a",["Â"]="a",["Ä"]="a",["Ã"]="a",["Å"]="a",["Ā"]="a",["а"]="a",["А"]="a",["α"]="a",
    -- b
    ["в"]="b",["Β"]="b",["ß"]="b",["Ь"]="b",["ḅ"]="b",
    -- c
    ["ç"]="c",["ć"]="c",["č"]="c",["ċ"]="c",["Ç"]="c",["Ć"]="c",["Č"]="c",["с"]="c",["С"]="c",["ϲ"]="c",
    -- e
    ["é"]="e",["è"]="e",["ê"]="e",["ë"]="e",["ē"]="e",["ė"]="e",["ę"]="e",["ě"]="e",
    ["É"]="e",["È"]="e",["Ê"]="e",["Ë"]="e",["е"]="e",["Е"]="e",["ё"]="e",["Ё"]="e",["є"]="e",
    -- g
    ["ğ"]="g",["ǧ"]="g",["ġ"]="g",["ģ"]="g",["Ğ"]="g",
    -- i
    ["í"]="i",["ì"]="i",["î"]="i",["ï"]="i",["ī"]="i",["į"]="i",["ı"]="i",["і"]="i",["Í"]="i",["Ì"]="i",
    ["Î"]="i",["Ï"]="i",["İ"]="i",["І"]="i",["ї"]="i",["ι"]="i",
    -- k
    ["ķ"]="k",["к"]="k",["К"]="k",["κ"]="k",
    -- n
    ["ñ"]="n",["ń"]="n",["ň"]="n",["ņ"]="n",["Ñ"]="n",["Ń"]="n",["п"]="n",["И"]="n",["и"]="n",
    -- o
    ["ó"]="o",["ò"]="o",["ô"]="o",["ö"]="o",["õ"]="o",["ø"]="o",["ō"]="o",["ŏ"]="o",["ő"]="o",
    ["Ó"]="o",["Ò"]="o",["Ô"]="o",["Ö"]="o",["Õ"]="o",["Ø"]="o",["о"]="o",["О"]="o",["ο"]="o",["σ"]="o",
    -- s
    ["ś"]="s",["š"]="s",["ş"]="s",["ș"]="s",["Ś"]="s",["Š"]="s",["Ş"]="s",["ѕ"]="s",["Ѕ"]="s",
    -- u
    ["ú"]="u",["ù"]="u",["û"]="u",["ü"]="u",["ū"]="u",["ů"]="u",["Ú"]="u",["Ù"]="u",["Û"]="u",["Ü"]="u",
    -- t / r / l filler look-alikes
    ["т"]="t",["Т"]="t",["р"]="r",["Р"]="r",["ł"]="l",["Ł"]="l",
}

local DEFAULT_KEYWORDS = { "asino", "casino", "kasino", "gasino" }

local function normalize(s)
    if not s or s == "" then return "" end
    -- CONFUSABLES keys are all multi-byte, so ASCII-only text skips ~110 gsub passes.
    if s:find("[\128-\255]") then
        for from, to in pairs(CONFUSABLES) do
            s = s:gsub(from, to)
        end
    end
    s = s:lower()
    s = s:gsub("[^a-z]", "")
    return s
end

local cachedKeywords
local function buildKeywords()
    local list, seen = {}, {}
    local function add(kw)
        kw = normalize(kw)
        if kw ~= "" and not seen[kw] then seen[kw] = true; list[#list + 1] = kw end
    end
    for _, kw in ipairs(DEFAULT_KEYWORDS) do add(kw) end
    for kw in tostring(mod.db.extraKeywords or ""):gmatch("[^,%s]+") do add(kw) end
    cachedKeywords = list
    return list
end

local function matches(s)
    if not s then return false end
    local n = normalize(s)
    if n == "" then return false end
    for _, kw in ipairs(cachedKeywords or buildKeywords()) do
        if n:find(kw, 1, true) then return true end
    end
    return false
end

local ignoredThisSession = {}

local function maybeIgnore(author)
    if not (mod.db.autoIgnore and author and author ~= "") then return end
    if ignoredThisSession[author] then return end
    ignoredThisSession[author] = true
    local numIgnores = (C_FriendList and C_FriendList.GetNumIgnores and C_FriendList.GetNumIgnores()) or 0
    if numIgnores >= 50 then return end  -- ignore list is full; hiding still works
    if C_FriendList and C_FriendList.AddIgnore then
        pcall(C_FriendList.AddIgnore, author)
    elseif _G.AddIgnore then
        pcall(_G.AddIgnore, author)
    end
end

mod._blocked = 0  -- session counter (shown in options)

local cachedWhitelist
local function buildWhitelist()
    local set = {}
    for n in tostring(mod.db and mod.db.whitelist or ""):gmatch("[^,]+") do
        n = normalize(n)
        if n ~= "" then set[n] = true end
    end
    cachedWhitelist = set
    return set
end
local function isWhitelisted(name)
    local set = cachedWhitelist or buildWhitelist()
    return set[normalize(name)] == true
end

function mod.ToggleWhitelist(name)
    if not (name and name ~= "" and mod.db) then return end
    local key = normalize(name)
    if key == "" then return end
    local kept, removed = {}, false
    for n in tostring(mod.db.whitelist or ""):gmatch("[^,]+") do
        local t = n:gsub("^%s+", ""):gsub("%s+$", "")
        if normalize(t) == key then removed = true else kept[#kept + 1] = t end
    end
    if not removed then kept[#kept + 1] = name end
    mod.db.whitelist = table.concat(kept, ", ")
    buildWhitelist()
    if removed then
        ns:Print(string.format(L["Spam filter: '%s' removed from the whitelist."], name))
    else
        ns:Print(string.format(L["Spam filter: '%s' added to the whitelist (never filtered)."], name))
    end
end

local TLDS = { "com","net","org","io","gg","ru","xyz","info","vip","club","online","shop","site","top","live","biz" }
local function hasLink(s)
    s = (s or ""):lower()
    if s:find("https?://") or s:find("www%.") then return true end
    for _, tld in ipairs(TLDS) do
        if s:find("[%w%-]%." .. tld .. "%f[%A]") then return true end  -- domain.tld at a word boundary
    end
    return false
end

-- Returns true to swallow the message.
local function chatFilter(_, _, msg, author)
    if not (mod._enabled and mod.db) then return false end
    local name = author and author:gsub("%-.*$", "") or ""   -- drop -Realm
    if isWhitelisted(name) then return false end
    local nameHit = matches(name)
    local hit = nameHit
        or (mod.db.scanMessage and matches(msg))
        or (mod.db.blockLinks and hasLink(msg))
    if not hit then return false end
    if nameHit then maybeIgnore(author) end  -- only ignore confirmed spammer names
    mod._blocked = mod._blocked + 1
    if mod.db.hide then return true end
    return false
end

local FILTER_EVENTS = {
    "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",  -- /emote spam
}
local installed = false

function mod:OnEnable()
    buildKeywords()
    buildWhitelist()
    if installed then return end
    installed = true
    if ChatFrame_AddMessageEventFilter then
        for _, ev in ipairs(FILTER_EVENTS) do
            ChatFrame_AddMessageEventFilter(ev, chatFilter)
        end
    end
end

function mod:OnDisable()
    -- Filters stay registered but no-op via the mod._enabled gate, so disabling needs no /reload.
end

function mod:GetOptions()
    local items = {}

    table.insert(items, { type = "header", text = L["Spam Filter"] })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaHides chat from gold/casino spammers whose names use look-alike letters (e.g. Gãsïnô, Casinòbâbe). The name is folded to plain letters, then matched against the keywords below. Applies to whisper, channels, say, yell and emotes — not guild/party/raid.|r"] })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, {
        type = "toggle", label = L["Hide their chat messages"],
        get = function() return mod.db.hide end,
        set = function(_, v) mod.db.hide = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Also add them to your ignore list"],
        tooltip = L["Adds matched senders to /ignore too. The ignore list holds only ~50 names and spammers keep changing names, so hiding is usually enough — leave this off unless you want it."],
        get = function() return mod.db.autoIgnore end,
        set = function(_, v) mod.db.autoIgnore = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Also match the message text"],
        tooltip = L["Also checks the message body for the keywords, not just the sender's name. Catches more spam but can have false positives."],
        get = function() return mod.db.scanMessage end,
        set = function(_, v) mod.db.scanMessage = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Block messages with web links"],
        tooltip = L["Hides any message containing a web link (http://, www., domain.tld) in the filtered channels. Whitelisted names are exempt. Opt-in — can catch the occasional legit link."],
        get = function() return mod.db.blockLinks end,
        set = function(_, v) mod.db.blockLinks = v end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Keywords"] })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaBuilt-in: casino / asino / gasino / kasino. Add your own below, comma-separated (look-alike letters are handled automatically).|r"] })
    table.insert(items, {
        type = "editbox", label = L["Extra keywords"],
        get = function() return mod.db.extraKeywords or "" end,
        set = function(_, v) mod.db.extraKeywords = v or ""; buildKeywords() end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Whitelist"] })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaNames here are never filtered. Comma-separated, or use |r|cff9b6cff/vcui spam <name>|r|cffaaaaaa to toggle one.|r"] })
    table.insert(items, {
        type = "editbox", label = L["Never filter these names"],
        get = function() return mod.db.whitelist or "" end,
        set = function(_, v) mod.db.whitelist = v or ""; buildWhitelist() end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "desc",
        text = string.format(L["|cff9b6cffBlocked this session: %d|r"], mod._blocked or 0) })

    return items
end
end)(...);

(function(...)
-- Collection pages. Registered AFTER the member capsules above, because
-- ns:MakeCollectionPage (exported by Modules/Pages.lua) hides each member at
-- call time. pg_windows and pg_gold moved here from Pages.lua; pg_bugfixes is
-- new and folds all seven client fixes into ONE tab.
local _, ns = ...
local ICONS = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\"

ns:MakeCollectionPage({
    key   = "pg_windows",
    name  = "Windows & Professions",
    group = "Character",
    icon  = ICONS .. "pg_windows.tga",
    desc  = "Quest log, profession windows and the disenchant queue, all in one place.",
    members = { "questlog", "professionwindow", "disenchantqueue" },
})
ns:MakeCollectionPage({
    key   = "pg_gold",
    name  = "Gold & Vendors",
    group = "Character",
    icon  = ICONS .. "pg_gold.tga",
    desc  = "Gold tracking and automatic buying at vendors.",
    members = { "goldtracker", "autoitembuy" },
})
ns:MakeCollectionPage({
    key   = "pg_bugfixes",
    name  = "Bug Fixes",
    group = "Bugfixes",
    icon  = ICONS .. "bugfixes.tga",
    members = { "fixauctiondropdown", "fixguildnews", "fixlfgbrowsenil",
                "fixinspect", "fixbindsocket", "fixcombatglow", "fixnameplaterole" },
})
-- moved from Pages.lua with its members (30.07.2026): spamfilter and
-- tooltipids register in the capsules above, so the page must register here
ns:MakeCollectionPage({
    key   = "pg_chat",
    name  = "Chat & Tooltips",
    group = "Chat & Social",
    icon  = ICONS .. "pg_chat.tga",
    desc  = "Chat spam filter and tooltip IDs.",
    members = { "spamfilter", "tooltipids" },
})
end)(...);

(function(...)
-- The containers, LAST: every one-shot ns.moduleOrder scan must run after all
-- capsules above -- and this file stays the LAST module file in both TOCs,
-- after Pages.lua, whose page factory the pages capsule needs.
--
-- The two Tools rows moved here from Pages.lua (30.07.2026), because members
-- of both their groups (mail, group board, spam filter, tooltip IDs, the
-- disenchant queue) now register inside this file.
local _, ns = ...

local ICONS = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\"
for _, c in ipairs({
    { key = "c_items",  name = "Bags & Items",  memberGroup = "Bags & Items",  order = -40,
      icon = ICONS .. "bags.tga" },
    { key = "c_social", name = "Chat & Social", memberGroup = "Chat & Social", order = -30,
      icon = ICONS .. "chat.tga" },
}) do
    ns:MakeGroupContainer({
        key          = c.key,
        name         = c.name,
        group        = "Tools",
        memberGroup  = c.memberGroup,
        sidebarOrder = c.order,   -- ahead of "Class Specific", which keeps its own row
    })
    if ns.MODULE_ICONS then ns.MODULE_ICONS[c.key] = c.icon end
end

-- The "General" collection row (30.07.2026, user request): ONE sidebar row
-- under Reminders holding, as tabs, the former Extras (Kleinkram), the
-- Character pages and the bug fixes.
ns:MakeGroupContainer({
    key          = "general",
    name         = "General",
    group        = "Global",
    memberGroups = { "Extras", "Character", "Bugfixes" },
    firstKey     = "miscqol",
})

if ns.MODULE_ICONS then
    ns.MODULE_ICONS.general =
        "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\qol.tga"
end
end)(...);
