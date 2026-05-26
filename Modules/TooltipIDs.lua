-- =========================================================
-- VuloClassicUI / Modules / TooltipIDs
-- Formerly: idTip by silverwind (https://github.com/silverwind/idTip)
-- Adds various IDs to tooltips (SpellID, ItemID, NPC ID, ...).
--
-- Code ported 1:1. SavedVariables settings are in mod.db instead of idTipConfig.
-- =========================================================
local _, ns = ...
local L = ns.L

-- =========================================================
-- API aliases (Retail/Classic compatibility)
-- =========================================================
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) and C_Spell.GetSpellTexture or GetSpellTexture
local GetItemIconByID = (C_Item and C_Item.GetItemIconByID) and C_Item.GetItemIconByID or GetItemIconByID
local GetItemInfoLocal = (C_Item and C_Item.GetItemInfo) and C_Item.GetItemInfo or GetItemInfo
local GetItemGem = (C_Item and C_Item.GetItemGem) and C_Item.GetItemGem or GetItemGem
local GetItemSpell = (C_Item and C_Item.GetItemSpell) and C_Item.GetItemSpell or GetItemSpell
local GetRecipeReagentItemLink = (C_TradeSkillUI and C_TradeSkillUI.GetRecipeReagentItemLink) and C_TradeSkillUI.GetRecipeReagentItemLink or GetTradeSkillReagentItemLink
local GetItemLinkByGUID = (C_Item and C_Item.GetItemLinkByGUID) and C_Item.GetItemLinkByGUID

-- =========================================================
-- Kinds (ID types)
-- =========================================================
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

-- List in stable order for the UI
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

-- TooltipDataProcessor type -> kind mapping (Retail)
local kindsByID = {
    [0]  = "item",        [1]  = "spell",  [2]  = "unit",      [3]  = "unit",
    [4]  = "object",      [5]  = "currency", [6]  = "unit",    [7]  = "spell",
    [8]  = "spell",       [9]  = "unit",   [10] = "mount",     [11] = "spell",
    [12] = "achievement", [13] = "spell",  [14] = "set",       [15] = "",
    [16] = "",            [17] = "spell",  [18] = "spell",     [19] = "item",
    [20] = "",            [21] = "",       [22] = "",          [23] = "quest",
    [24] = "quest",       [25] = "macro",  [26] = "",
}

-- =========================================================
-- Register module with defaults for all ID types
-- =========================================================
local moduleDefaults = { enabled = true }
for kind in pairs(kinds) do
    moduleDefaults[kind] = not defaultDisabledKinds[kind]
end
-- Extra features for player tooltips (iLvL + talent distribution)
moduleDefaults.showPlayerILvl    = true
moduleDefaults.showPlayerTalents = true

local mod = ns:RegisterModule("tooltipids", {
    name        = L["Tooltip IDs"],
    group       = "QoL",
    description = L["Shows SpellID, ItemID, NPC ID and many other IDs in tooltips (based on idTip by silverwind)."],
    defaults    = moduleDefaults,
})

mod.kinds      = kinds
mod.kindOrder  = kindOrder

-- =========================================================
-- Helpers
-- =========================================================
local function isEnabled(kind)
    if not mod._enabled then return false end
    if not mod.db.enabled then return false end
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

-- =========================================================
-- Core functions: addLine / add / addByKind / addItemInfo
-- =========================================================
local function addLine(tooltip, id, kind)
    if isSecret(id) then return end
    if not id or id == "" or not tooltip or not tooltip.GetName then return end
    if not isEnabled(kind) then return end

    local ok, name = pcall(getTooltipName, tooltip)
    if not ok or not name then return end

    -- Check existing lines to avoid duplicate IDs
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

    -- GetMouseFocus for TradeSkill reagents (may differ in TBC Classic, check defensively)
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

-- =========================================================
-- Achievement/Criteria helpers (used in the ADDON_LOADED handler)
-- =========================================================
local function achievementOnEnter(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_NONE")
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
                GameTooltip:SetOwner(btn:GetParent(), "ANCHOR_NONE")
            end
            GameTooltip:SetPoint("TOPLEFT", btn, "TOPRIGHT", 0, 0)
            add(GameTooltip, achievementId, "achievement")
            add(GameTooltip, criteriaId, "criteria")
            GameTooltip:Show()
        end
    end
end

-- =========================================================
-- Scan addon-created tooltips (e.g. ElvUI_SpellBookTooltip)
-- =========================================================
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

-- =========================================================
-- Install all GameTooltip hooks once
-- =========================================================
local hooksInstalled = false
local function installHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    hookedTooltips[GameTooltip] = true

    -- Retail TooltipDataProcessor (for modern clients)
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

    -- Currency hooks
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

    -- Quest hooks
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

    -- AreaPois / Vignettes (Retail-only, the mixins will be nil in TBC -> hook() ignores)
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

    -- PetBattle (Retail-only, nil in TBC -> ignored)
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

-- =========================================================
-- Lifecycle
-- =========================================================
-- =========================================================
-- Player tooltip enhancement: iLvL + talent distribution
-- =========================================================
local inspectCache = {}                -- guid -> { talents={t1,t2,t3}, ilvl=N, expiry=time }
local inspectFail  = {}                -- guid -> expiry: recently failed, don't retry
local INSPECT_CACHE_TIME = 60          -- seconds cache per player
local INSPECT_FAIL_TIME  = 30          -- seconds until retry after failure (out of range)
local INSPECT_THROTTLE   = 1.0
local lastInspectTime    = 0
local pendingInspectGUID = nil
local pendingInspectUnit = nil

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
    -- Negative cache: recently failed out-of-range -> don't retry (no sound spam)
    if inspectFail[guid] and inspectFail[guid] > GetTime() then return end

    pendingInspectGUID = guid
    pendingInspectUnit = unit
    lastInspectTime    = GetTime()
    -- Pre-mark as "failed"; clear again on successful INSPECT_READY.
    inspectFail[guid] = GetTime() + INSPECT_FAIL_TIME
    if NotifyInspect then NotifyInspect(unit) end
end

local function computeAverageILvl(unit)
    if not GetInventoryItemLink then return 0 end
    local total, count = 0, 0
    -- 1-18 = equip slots, skip Shirt (4) and Tabard (19)
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
                    local _, _, _, lvl = GetItemInfo(link)
                    ilvl = lvl
                end
                if ilvl and ilvl > 0 then
                    total = total + ilvl
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return 0 end
    return math.floor(total / count + 0.5)
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
    guid = guid or pendingInspectGUID
    if not guid then return end
    inspectFail[guid] = nil  -- successful -> clear negative cache
    local unit = pendingInspectUnit
    pendingInspectGUID = nil
    pendingInspectUnit = nil
    if not unit or not UnitExists(unit) then return end

    local talents = computeTalents(true)
    local ilvl    = computeAverageILvl(unit)
    inspectCache[guid] = {
        talents = talents, ilvl = ilvl,
        expiry  = GetTime() + INSPECT_CACHE_TIME,
    }
    -- Re-render tooltip immediately (SetUnit triggers all hooks again)
    if GameTooltip and GameTooltip:IsShown() then
        local _, ttUnit = GameTooltip:GetUnit()
        if ttUnit and UnitGUID(ttUnit) == guid then
            GameTooltip:SetUnit(ttUnit)
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

    -- Player tooltip: inspect events + tooltip hook (legacy OnTooltipSetUnit
    -- is the working path in Anniversary — TooltipDataProcessor doesn't fire)
    ns:RegisterEvent("INSPECT_READY",         onInspectReady)
    ns:RegisterEvent("INSPECT_TALENT_READY",  onInspectReady)
    -- Guard flag: HookScript appends on every call -> on toggle off->on
    -- onPlayerTooltipUnit would otherwise register twice + tooltip lines doubled.
    if GameTooltip and GameTooltip.HookScript and not mod._tooltipHooked then
        mod._tooltipHooked = true
        GameTooltip:HookScript("OnTooltipSetUnit", onPlayerTooltipUnit)
    end

    -- Achievement/Collection/Garrison frames are loaded lazily
    ns:RegisterEvent("ADDON_LOADED", function(_, addonName)
        if not mod._enabled then return end
        scanAddonTooltips()

        if addonName == "Blizzard_AchievementUI" then
            if AchievementTemplateMixin then
                -- Modern (Dragonflight+) — not present in TBC, so usually skip
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
                -- Pre-Dragonflight (Classic/TBC) — the normal path
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

    -- Login: rescan in case more tooltips were created in the meantime
    ns:RegisterEvent("PLAYER_LOGIN", function()
        if not mod._enabled then return end
        scanAddonTooltips()
    end)
end

-- =========================================================
-- Options
-- =========================================================

-- Helper to build a checkbox entry per kind (toggle for the UI)
function mod:OnDisable()
    -- pcall: INSPECT_TALENT_READY may not exist in Anniversary,
    -- UnregisterEvent would otherwise throw and abort SafeDisable.
    pcall(ns.UnregisterEvent, ns, "INSPECT_READY",        onInspectReady)
    pcall(ns.UnregisterEvent, ns, "INSPECT_TALENT_READY", onInspectReady)
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
        { type = "desc",   text = L["Which IDs should be shown in tooltips? Some types are only active in Retail and are ignored in TBC (e.g. TraitNodeID, SourceID)."] },
        { type = "spacer", height = 4 },
    }

    -- ID checkboxes in 2 columns
    local checkboxes = {}
    for _, kind in ipairs(kindOrder) do
        if kinds[kind] then
            table.insert(checkboxes, kindCheckbox(kind))
        end
    end
    table.insert(items, {
        type = "group", layout = "columns", columns = 2,
        items = checkboxes,
    })

    return items
end
