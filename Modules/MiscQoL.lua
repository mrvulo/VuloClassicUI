-- =========================================================
-- VuloClassicUI / Modules / MiscQoL ("General")
-- Collection module for all simple QoL toggles that don't need their own
-- module: auto actions, hide features, text sizes.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("miscqol", {
    name        = "General",
    group       = "QoL",
    description = "Collection of simple quality-of-life toggles: auto-accept (quest, res, summon), auto-sell, repair, hide UI spam, text sizes.",
    defaults    = {
        enabled               = true,
        -- Character / auto actions
        autoAcceptQuest       = false,
        autoTurnInQuest       = false,
        autoAcceptRes         = true,
        autoAcceptSummon      = false,
        autoReleasePvP        = true,
        -- World
        autoGossip            = false,
        fasterLoot            = true,
        maxCameraZoom         = false,
        -- Vendor
        autoSellJunk          = true,
        autoRepair            = true,
        maxStackButton        = true,
        -- Visibility
        hideErrors            = false,
        hideZoneText          = false,
        hidePortraitNumbers   = false,
        hideKeybindText       = false,
        hideMacroText         = false,
        hideStackCount        = false,
        hideRaidGroupLabels   = false,
        -- Text sizes
        mailTextSize          = 13,
        questTextSize         = 14,
        bookTextSize          = 14,
        -- Flight timer (taxi duration bar)
        flight = {
            enabled    = true,
            chatReport = false,
            barWidth   = 240,
            barHeight  = 18,
            x          = 0,
            y          = 280,
            unlocked   = false,
            times      = {},   -- "source @ destination" -> seconds (learned)
        },
    },
})

-- =========================================================
-- API compat (Anniversary uses C_Container instead of globals)
-- =========================================================
local GetContainerNumSlots  = (C_Container and C_Container.GetContainerNumSlots)  or _G.GetContainerNumSlots
local GetContainerItemInfo  = (C_Container and C_Container.GetContainerItemInfo)  or _G.GetContainerItemInfo
local UseContainerItem      = (C_Container and C_Container.UseContainerItem)      or _G.UseContainerItem
local GetContainerItemLink  = (C_Container and C_Container.GetContainerItemLink)  or _G.GetContainerItemLink
local GetCVarBool           = (C_CVar and C_CVar.GetCVarBool)                     or _G.GetCVarBool

-- =========================================================
-- Helpers
-- =========================================================
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

-- =========================================================
-- StackSplitFrame: MAX button (buy/split entire stack directly)
-- =========================================================
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

    -- Extend frame height once so the MAX button fits at the bottom inside.
    -- Width extension doesn't work because the backdrop in Classic has a
    -- fixed size and doesn't grow with SetWidth -> button would stick out of
    -- the dark panel. Bottom position stays cleanly within the backdrop.
    if not StackSplitFrame._vcuiHeightExtended then
        StackSplitFrame._vcuiHeightExtended = true
        local h = StackSplitFrame:GetHeight() or 50
        StackSplitFrame:SetHeight(h + 28)
    end

    local btn = CreateFrame("Button", "VCUI_StackSplitMaxButton", StackSplitFrame, "UIPanelButtonTemplate")
    btn:SetSize(80, 22)
    btn:SetText(L["MAX"])
    -- Centered at the bottom inside edge of the popup
    btn:ClearAllPoints()
    btn:SetPoint("BOTTOM", StackSplitFrame, "BOTTOM", 0, 8)
    btn:SetFrameLevel(StackSplitFrame:GetFrameLevel() + 2)
    btn:SetScript("OnClick", function()
        local maxStack = StackSplitFrame.maxStack or 1
        if maxStack < 1 then return end

        -- Classic/Anniversary: StackSplitFrame.split is a NUMBER (current value),
        -- the OK handler reads it directly via StackSplitFrame.owner:SplitStack(.split).
        -- Retail: .split is an EditBox with :SetNumber().
        local s = StackSplitFrame.split
        if type(s) == "number" then
            StackSplitFrame.split = maxStack
            if _G.StackSplitText then
                _G.StackSplitText:SetText(maxStack)
            end
        elseif type(s) == "table" and s.SetNumber then
            s:SetNumber(maxStack)
        end

        -- Clicking OK triggers merchant buy or bag split with the set value
        local ok = StackSplitFrame.okayButton or _G.StackSplitOkayButton
        if ok and ok.Click then ok:Click() end
    end)

    -- Show/hide in sync with the popup
    StackSplitFrame:HookScript("OnShow", function()
        btn:SetShown(mod.db.maxStackButton ~= false)
    end)
    StackSplitFrame:HookScript("OnHide", function()
        btn:Hide()
    end)
end

-- =========================================================
-- Event handlers
-- =========================================================
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
    -- When all quest items are turned in -> CompleteQuest triggers QUEST_COMPLETE
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

-- Soulstone / Reincarnation / self-res available? Then never auto-release.
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

-- =========================================================
-- World: gossip automation, faster loot, max camera zoom
-- =========================================================

-- Single-option gossip without quests -> select it (hold SHIFT to skip)
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

-- Faster auto-loot: grab all slots at once instead of Blizzard's
-- one-item-at-a-time crawl. Only acts when auto-loot actually applies
-- (CVar XOR held auto-loot modifier key), so manual looting is untouched.
local _lastFastLoot = 0
local function onLootReady()
    if not mod.db.fasterLoot then return end
    local now = GetTime() or 0
    if (now - _lastFastLoot) < 0.3 then return end  -- LOOT_READY can fire repeatedly
    _lastFastLoot = now
    local cvarAuto  = GetCVarBool and GetCVarBool("autoLootDefault") and true or false
    local modifier  = IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") and true or false
    if cvarAuto == modifier then return end  -- auto-loot not active for this window
    if not GetNumLootItems or not LootSlot then return end
    for i = GetNumLootItems(), 1, -1 do
        LootSlot(i)
    end
end

local CAMERA_CVAR    = "cameraDistanceMaxZoomFactor"
local CAMERA_MAX     = 3.4   -- client clamps if its cap is lower
local CAMERA_DEFAULT = 1.9

local function applyMaxCameraZoom()
    if not SetCVar then return end
    pcall(SetCVar, CAMERA_CVAR, mod.db.maxCameraZoom and CAMERA_MAX or CAMERA_DEFAULT)
end

-- =========================================================
-- Visibility toggles
-- =========================================================
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
        -- Re-register events; do NOT call :Show() directly — FadingFrame OnUpdate
        -- crashes with 'startTime nil' if frame wasn't shown via FadingFrame_Show().
        -- Blizzard will show + fade on the next zone change itself.
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

local function applyHideRaidGroupLabels()
    for i = 1, 8 do
        local g = _G["CompactRaidGroup" .. i]
        if g and g.title then
            if mod.db.hideRaidGroupLabels then g.title:Hide() else g.title:Show() end
        end
    end
end

-- =========================================================
-- Text sizes
-- =========================================================
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
    applyHideKeybindText()
    applyHideMacroText()
    applyHideStackCount()
    applyHideRaidGroupLabels()
    applyMailTextSize()
    applyQuestTextSize()
    applyBookTextSize()
    applyMaxCameraZoom()
end

-- =========================================================
-- Flight timer: progress bar for taxi flights (gryphon & co.)
-- Hooks TakeTaxiNode for source/destination, learns each route's
-- duration and shows a DRAINING countdown bar on known routes.
-- Strictly taxi-only: visibility is tied to UnitOnTaxi, so it can
-- never stick around while you ride your own mount.
-- =========================================================
local FT_FONT = "Fonts\\FRIZQT__.TTF"
local ftBar
local ftFlight            -- { src, dst, key, t0, known } while flying
local ftThrottle = 0

local function ftDB() return mod.db.flight end

local function ftFmt(s)
    s = math.max(0, math.floor(s + 0.5))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function ftRouteKey(src, dst)
    return (src or "?") .. " @ " .. (dst or "?")
end

-- Valid English node names, harvested once from the shipped DB. Lets us
-- recognise the node segment directly on English clients and pick the node
-- (not the zone) out of a multi-part name.
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

-- Resolve a raw client taxi name to (germanNodeName, englishKey).
-- The client formats the CURRENT node as "Zone, Node, Faction" but a
-- DESTINATION as "Node, Zone" -- so taking the part before the first comma
-- grabs the zone for sources. Instead test EVERY comma-separated segment
-- against the German->English map and the English node set (case-insensitive,
-- since client casing varies e.g. "das Dunkle Portal") and pick the segment
-- that is an actual flight node.
local function ftResolve(raw)
    if not raw then return "?", nil end
    local de = ns.FLIGHT_NODE_DE or {}
    local en = ftEnglishNodes()
    local segs = {}
    for s in (raw .. ","):gmatch("%s*(.-)%s*,") do
        if s ~= "" then segs[#segs + 1] = s end
    end
    -- pass 1: exact (German map, then English node set)
    for _, s in ipairs(segs) do
        if de[s] then return s, de[s] end
        if en[s] then return s, en[s] end
    end
    -- pass 2: case-insensitive
    for _, s in ipairs(segs) do
        local l = s:lower()
        for k, v in pairs(de) do if k:lower() == l then return s, v end end
        for k, v in pairs(en) do if k:lower() == l then return s, v end end
    end
    -- nothing matched: keep the first segment for display, no DB key
    return segs[1] or raw, nil
end

-- Short, human-readable node name for display (German node, no zone suffix).
local function ftShort(name)
    return (ftResolve(name))
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

local FT_INSET = 4   -- fill sits inside the tooltip border

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

    -- InFlight-style: tooltip border + dark backdrop, glossy blue fill
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
        label  = L["|cffffffffFLIGHT TIME|r"],
        db     = ftDB(),
        width  = 240,
        height = 30,
        onMove = function(x, y)
            ns:Print(string.format(L["Flight timer: x=%.0f, y=%.0f"], x, y))
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
    -- Only record plausible flights (a cancelled click is shorter than 5s)
    if recordIt and dur > 5 then
        ftDB().times[ftFlight.key] = math.floor(dur + 0.5)
        if ftDB().chatReport then
            ns:Print(L["Flight: %s (%s)"], ftFmt(dur),
                ftShort(ftFlight.src) .. " > " .. ftShort(ftFlight.dst))
        end
    end
    ftFlight = nil
    ftDB().inFlight = nil  -- persisted reload-resume marker
    if ftBar then ftBar:Hide() end
end

local function ftOnUpdate(_, elapsed)
    ftThrottle = ftThrottle + elapsed
    if ftThrottle < 0.1 then return end
    ftThrottle = 0
    if ftDB().unlocked then return end  -- preview owns the bar
    if not ftFlight then return end

    local elapsedT = GetTime() - ftFlight.t0

    -- Hard taxi check: the moment we're not on a taxi anymore (landed,
    -- own mount, whatever) the bar goes away. 3s grace for boarding.
    if elapsedT > 3 and not UnitOnTaxi("player") then
        ftStop(elapsedT > 5)
        return
    end

    if ftFlight.known and ftFlight.known > 0 then
        -- Known route: bar fills towards arrival, "elapsed / total" readout
        ftSetFill(elapsedT / ftFlight.known)
        ftBar.time:SetText(ftFmt(math.min(elapsedT, ftFlight.known)) .. " / " .. ftFmt(ftFlight.known))
    else
        -- Learning flight: no total yet -> empty bar, counting "1:58 / ?"
        ftSetFill(0)
        ftBar.time:SetText(ftFmt(elapsedT) .. " / ?")
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
        -- measured time first, shipped default as fallback
        known = ftDB().times[key] or ftDefaultTime(src, dst),
    }
    -- Persist for /reload mid-flight: epoch-stamped so the elapsed time
    -- keeps running while the UI is away (the flight itself continues).
    ftDB().inFlight = { src = src, dst = dst, key = key, start = time() }

    -- /vcuiflug: dump exactly what the resolver sees (route DB debugging)
    if ftDB().debug then
        local s, se = ftResolve(src)
        local d2, de2 = ftResolve(dst)
        local fac = (UnitFactionGroup and UnitFactionGroup("player")) or "?"
        local hit = se and de2 and ns.FLIGHT_TIMES and ns.FLIGHT_TIMES[fac]
            and ns.FLIGHT_TIMES[fac][se] and ns.FLIGHT_TIMES[fac][se][de2]
        ns:Print("Flugdebug: src='" .. tostring(src) .. "' -> '" .. s .. "' -> '" .. tostring(se)
            .. "' | dst='" .. tostring(dst) .. "' -> '" .. d2 .. "' -> '" .. tostring(de2)
            .. "' | " .. fac .. " | DB=" .. tostring(hit)
            .. " | gelernt=" .. tostring(ftDB().times[key]))
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

    -- The click can fail (no money, combat...): if we never took off,
    -- discard the pending flight again.
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
    -- Resume after /reload mid-flight: restore the bar with the elapsed
    -- time reconstructed from the persisted epoch departure stamp.
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
            -- Landed (or logged out) while the UI was away: the true landing
            -- moment is unknown -> discard instead of recording a wrong time.
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

-- Debug toggle for the route resolver (prints details on each taxi click)
SLASH_VCUIFLUG1 = "/vcuiflug"
SlashCmdList.VCUIFLUG = function()
    local d = mod.db and mod.db.flight
    if not d then return end
    d.debug = not d.debug
    ns:Print("Flugdebug: " .. (d.debug and "AN — nimm einen Flug, dann steht die Auflösung im Chat." or "aus"))
end

local ftTaxiHooked = false
local function ftInit()
    -- The shipped route database lives in a separate file added to the .toc.
    -- /reload does NOT re-read the .toc, so right after an update the file is
    -- absent until the game is fully restarted -> every shipped time shows "?".
    -- Detect that and tell the user once instead of failing silently.
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
        ftTaxiHooked = true  -- hooksecurefunc is permanent; gated on flags
        hooksecurefunc("TakeTaxiNode", ftOnTakeTaxi)
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
local function onPlayerLogin()
    applyAllVisibility()
end

function mod:OnEnable()
    ns:RegisterEvent("MERCHANT_SHOW",         onMerchantShow)
    ns:RegisterEvent("RESURRECT_REQUEST",     onRezRequest)
    ns:RegisterEvent("CONFIRM_SUMMON",        onSummonConfirm)
    ns:RegisterEvent("QUEST_GREETING",        onQuestGreeting)
    ns:RegisterEvent("QUEST_DETAIL",          onQuestDetail)
    ns:RegisterEvent("QUEST_ACCEPT_CONFIRM",  onQuestAcceptConfirm)
    ns:RegisterEvent("QUEST_PROGRESS",        onQuestProgress)
    ns:RegisterEvent("QUEST_COMPLETE",        onQuestComplete)
    ns:RegisterEvent("PLAYER_DEAD",           onPlayerDead)
    ns:RegisterEvent("GOSSIP_SHOW",           onGossipShow)
    ns:RegisterEvent("LOOT_READY",            onLootReady)
    ns:RegisterEvent("PLAYER_LOGIN",          onPlayerLogin)
    ns:RegisterEvent("PLAYER_CONTROL_GAINED", ftOnControlGained)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", ftOnWorldEnter)
    ftInit()

    if ns.isInitialised then
        applyAllVisibility()
    elseif C_Timer and C_Timer.After then
        C_Timer.After(1, applyAllVisibility)
    end

    -- Create StackSplit MAX button (deferred in case frame isn't there yet)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, setupStackSplitMaxButton)
    else
        setupStackSplitMaxButton()
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("MERCHANT_SHOW",         onMerchantShow)
    ns:UnregisterEvent("RESURRECT_REQUEST",     onRezRequest)
    ns:UnregisterEvent("CONFIRM_SUMMON",        onSummonConfirm)
    ns:UnregisterEvent("QUEST_GREETING",        onQuestGreeting)
    ns:UnregisterEvent("QUEST_DETAIL",          onQuestDetail)
    ns:UnregisterEvent("QUEST_ACCEPT_CONFIRM",  onQuestAcceptConfirm)
    ns:UnregisterEvent("QUEST_PROGRESS",        onQuestProgress)
    ns:UnregisterEvent("QUEST_COMPLETE",        onQuestComplete)
    ns:UnregisterEvent("PLAYER_DEAD",           onPlayerDead)
    ns:UnregisterEvent("GOSSIP_SHOW",           onGossipShow)
    ns:UnregisterEvent("LOOT_READY",            onLootReady)
    ns:UnregisterEvent("PLAYER_LOGIN",          onPlayerLogin)
    ns:UnregisterEvent("PLAYER_CONTROL_GAINED", ftOnControlGained)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", ftOnWorldEnter)
    ftFlight = nil
    if ftBar then
        if ftBar.mover then ftBar.mover:Hide() end
        ftBar:Hide()
    end
    -- Module off -> hand the camera distance back to the game default
    if mod.db.maxCameraZoom and SetCVar then
        pcall(SetCVar, CAMERA_CVAR, CAMERA_DEFAULT)
    end
end

-- =========================================================
-- Options
-- =========================================================
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

    return {
        { type = "header", text = L["General - Auto Actions"] },
        { type = "desc",
          text = L["|cffaaaaaaSimple on/off switches for common QoL actions. Take effect immediately, no /reload needed.|r"] },

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
        { type = "header", text = L["Vendor"] },
        tgl("autoSellJunk",      L["Auto-sell junk (grey)"],
            L["Sells all grey items when opening a vendor. Earnings shown in chat."]),
        tgl("autoRepair",        L["Auto-repair"],
            L["Repairs entire equipment at the vendor if gold is sufficient."]),
        tgl("maxStackButton",    L["Stack-split popup: MAX button"],
            L["Adds a 'MAX' button to the quantity popup. Click = buy full stack (at vendor) or split completely (for bag items)."],
            applyMaxStackButton),

        { type = "spacer", height = 6 },
        { type = "section", title = L["Flight Timer"], collapsed = true, items = {
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

        { type = "section", title = L["Visibility"], collapsed = true, items = {
            tgl("hideErrors",        L["Hide UI error messages"],
                L["Hides the red error messages in the screen center."],
                applyHideErrors),
            tgl("hideZoneText",      L["Hide zone text"],
                L["Hides the large zone name when entering new areas."],
                applyHideZoneText),
            tgl("hidePortraitNumbers", L["Hide level numbers on portrait"],
                L["Hides the level display on the Player/Target/Pet portrait."],
                applyHidePortraitNumbers),
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

        { type = "section", title = L["Text Sizes"], collapsed = true, items = {
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
