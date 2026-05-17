-- =========================================================
-- VuloClassicUI / Modules / MiscQoL ("Allgemein")
-- Sammel-Modul für alle einfachen QoL-Toggles die kein eigenes
-- Modul brauchen: Auto-Aktionen, Hide-Features, Textgrößen.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("miscqol", {
    name        = "Allgemein",
    group       = "QoL",
    description = "Sammlung einfacher Quality-of-Life Toggles: Auto-Akzept (Quest, Res, Summon), Auto-Verkauf, Reparatur, Hide UI-Spam, Textgrößen.",
    defaults    = {
        enabled               = true,
        -- Charakter / Auto-Aktionen
        autoAcceptQuest       = false,
        autoAcceptRes         = true,
        autoAcceptSummon      = false,
        autoReleasePvP        = true,
        -- Anbieter
        autoSellJunk          = true,
        autoRepair            = true,
        -- Sichtbarkeit
        hideErrors            = false,
        hideZoneText          = false,
        hidePortraitNumbers   = false,
        hideKeybindText       = false,
        hideMacroText         = false,
        hideRaidGroupLabels   = false,
        -- Textgrößen
        mailTextSize          = 13,
        questTextSize         = 14,
        bookTextSize          = 14,
    },
})

-- =========================================================
-- API-Compat (Anniversary nutzt C_Container statt globals)
-- =========================================================
local GetContainerNumSlots  = (C_Container and C_Container.GetContainerNumSlots)  or _G.GetContainerNumSlots
local GetContainerItemInfo  = (C_Container and C_Container.GetContainerItemInfo)  or _G.GetContainerItemInfo
local UseContainerItem      = (C_Container and C_Container.UseContainerItem)      or _G.UseContainerItem
local GetContainerItemLink  = (C_Container and C_Container.GetContainerItemLink)  or _G.GetContainerItemLink

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
                    ns:Print("Auto-Verkauft: %d Gegenst\195\164nde, +%s", sold, fmtCopper(earned))
                else
                    ns:Print("Auto-Verkauft: %d Gegenst\195\164nde.", sold)
                end
            end)
        else
            ns:Print("Auto-Verkauft: %d Gegenst\195\164nde.", sold)
        end
    end
end

local function repairAll()
    if not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost = (GetRepairAllCost and GetRepairAllCost()) or 0
    if cost <= 0 then return end
    if (GetMoney() or 0) < cost then
        ns:Print("Reparatur \195\188bersteigt Gold (%d < %d).", GetMoney() or 0, cost)
        return
    end
    RepairAllItems()
    local g = math.floor(cost / 10000)
    local s = math.floor((cost % 10000) / 100)
    ns:Print("Auto-Repariert (%dg %ds).", g, s)
end

-- =========================================================
-- Event-Handler
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

local function onPlayerDead()
    if not mod.db.autoReleasePvP then return end
    if not IsInInstance then return end
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" or instanceType == "arena" then
        if RepopMe then RepopMe() end
    end
end

-- =========================================================
-- Sichtbarkeits-Toggles
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
        if zt then
            zt:RegisterEvent("ZONE_CHANGED")
            zt:RegisterEvent("ZONE_CHANGED_NEW_AREA")
            zt:RegisterEvent("ZONE_CHANGED_INDOORS")
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

local function applyHideRaidGroupLabels()
    for i = 1, 8 do
        local g = _G["CompactRaidGroup" .. i]
        if g and g.title then
            if mod.db.hideRaidGroupLabels then g.title:Hide() else g.title:Show() end
        end
    end
end

-- =========================================================
-- Textgrößen
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
    applyHideRaidGroupLabels()
    applyMailTextSize()
    applyQuestTextSize()
    applyBookTextSize()
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
    ns:RegisterEvent("PLAYER_DEAD",           onPlayerDead)
    ns:RegisterEvent("PLAYER_LOGIN",          onPlayerLogin)

    if ns.isInitialised then
        applyAllVisibility()
    elseif C_Timer and C_Timer.After then
        C_Timer.After(1, applyAllVisibility)
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("MERCHANT_SHOW",         onMerchantShow)
    ns:UnregisterEvent("RESURRECT_REQUEST",     onRezRequest)
    ns:UnregisterEvent("CONFIRM_SUMMON",        onSummonConfirm)
    ns:UnregisterEvent("QUEST_GREETING",        onQuestGreeting)
    ns:UnregisterEvent("QUEST_DETAIL",          onQuestDetail)
    ns:UnregisterEvent("QUEST_ACCEPT_CONFIRM",  onQuestAcceptConfirm)
    ns:UnregisterEvent("PLAYER_DEAD",           onPlayerDead)
    ns:UnregisterEvent("PLAYER_LOGIN",          onPlayerLogin)
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
        { type = "header", text = "Allgemein – Auto-Aktionen" },
        { type = "desc",
          text = "|cffaaaaaaSimple On/Off-Schalter f\195\188r h\195\164ufige QoL-Aktionen. Wirkt sofort, kein /reload n\195\182tig.|r" },

        { type = "header", text = "Charakter" },
        tgl("autoAcceptQuest",   "Quests automatisch annehmen",
            "Akzeptiert Quests beim Anklicken eines NPCs automatisch."),
        tgl("autoAcceptRes",     "Wiederbelebung automatisch annehmen",
            "Klickt 'Akzeptieren' auf Rez-Popups automatisch (nicht im Kampf)."),
        tgl("autoAcceptSummon",  "Beschwörung automatisch annehmen",
            "Klickt 'Akzeptieren' auf Hexenmeister/Stein-Summon-Popups."),
        tgl("autoReleasePvP",    "Geist in PvP/Arena automatisch freilassen",
            "Released sofort beim Tod in BG oder Arena."),

        { type = "spacer", height = 6 },
        { type = "header", text = "Anbieter" },
        tgl("autoSellJunk",      "Junk (grau) automatisch verkaufen",
            "Verkauft alle grauen Items beim Öffnen eines Vendors. Erlös wird im Chat angezeigt."),
        tgl("autoRepair",        "Automatisch reparieren",
            "Repariert komplette Ausrüstung beim Vendor, sofern Gold reicht."),

        { type = "spacer", height = 6 },
        { type = "header", text = "Sichtbarkeit" },
        tgl("hideErrors",        "UI-Fehlermeldungen verstecken",
            "Versteckt die roten Fehlermeldungen in der Bildschirmmitte.",
            applyHideErrors),
        tgl("hideZoneText",      "Gebietstext verstecken",
            "Versteckt den großen Zonen-Namen beim Betreten neuer Gebiete.",
            applyHideZoneText),
        tgl("hidePortraitNumbers", "Level-Zahlen am Portrait verstecken",
            "Versteckt die Level-Anzeige am Player-/Target-/Pet-Portrait.",
            applyHidePortraitNumbers),
        tgl("hideKeybindText",   "Tasten-Belegung an Action-Buttons verstecken",
            "Versteckt die kleinen Tasten-Labels (1, F1, etc.) an den Aktions-Buttons.",
            applyHideKeybindText),
        tgl("hideMacroText",     "Makro-/Spell-Namen an Action-Buttons verstecken",
            "Versteckt die Text-Labels unter den Aktions-Buttons.",
            applyHideMacroText),
        tgl("hideRaidGroupLabels", "Raid-Gruppen-Labels verstecken",
            "Versteckt die 'Gruppe 1'/'Gruppe 2'-Labels über den Compact-Raid-Frames.",
            applyHideRaidGroupLabels),

        { type = "spacer", height = 6 },
        { type = "header", text = "Textgrößen" },
        { type = "slider", label = "Mail-Text Größe",
          min = 8, max = 20, step = 1,
          tooltip = "Schriftgröße im Brief-Inhalt (geöffnete + gesendete Mail).",
          get = function() return mod.db.mailTextSize end,
          set = function(_, v) mod.db.mailTextSize = v; applyMailTextSize() end },
        { type = "slider", label = "Quest-Text Größe",
          min = 8, max = 22, step = 1,
          tooltip = "Schriftgröße in Quest-Beschreibungen + Quest-Log.",
          get = function() return mod.db.questTextSize end,
          set = function(_, v) mod.db.questTextSize = v; applyQuestTextSize() end },
        { type = "slider", label = "Buch-Text Größe",
          min = 8, max = 20, step = 1,
          tooltip = "Schriftgröße in lesbaren Büchern und Briefen aus Item-Texten.",
          get = function() return mod.db.bookTextSize end,
          set = function(_, v) mod.db.bookTextSize = v; applyBookTextSize() end },
    }
end
