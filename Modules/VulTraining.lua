-- VulTraining: spell book tab listing trainable class abilities, built from per-class spell tables (Modules/VulTraining/Classes) so no trainer visit is needed.
local _, ns = ...

local mod = ns:RegisterModule("vultraining", {
    name        = "VulTraining",
    group       = "QoL",
    description = "Adds a tab to your spell book that lists the abilities you can still learn from your class trainer, grouped by level. Open the book icon below the spell schools.",
    defaults    = { enabled = true },
})

local format, strlower, strfind, sort = string.format, string.lower, string.find, table.sort
local tinsert, wipe, ipairs, pairs = table.insert, wipe, ipairs, pairs

local L = {
    AVAILABLE     = "Available Now",
    MISSINGREQS   = "Available but Missing Requirements",
    NEXTLEVEL     = "Coming Soon",
    NOTLEVEL      = "Not Yet Available",
    MISSINGTALENT = "Missing Required Talents",
    KNOWN         = "Already Known",
    LEVEL_FORMAT  = "Level %s",
    COST_FORMAT   = "Cost: %s",
    TAB_TEXT      = "What can I train?",
    NO_RESULTS    = "No results found",
    OPTION_DESC   = "|cffaaaaaaAdds a tab to your spell book (the book icon on the side, below the spell schools) listing every ability you can still learn from your class trainer — grouped by status and coloured by level. No need to visit a trainer.|r",
}
local locOverrides = {
    deDE = {
        AVAILABLE     = "Jetzt verfügbar",
        MISSINGREQS   = "Verfügbar, aber fehlende Anforderungen",
        NEXTLEVEL     = "Demnächst",
        NOTLEVEL      = "Noch nicht verfügbar",
        MISSINGTALENT = "Fehlende Talente",
        KNOWN         = "Bereits bekannt",
        LEVEL_FORMAT  = "Level %s",
        COST_FORMAT   = "Kosten: %s",
        TAB_TEXT      = "Was kann ich lernen?",
        NO_RESULTS    = "Keine Ergebnisse gefunden",
        OPTION_DESC   = "|cffaaaaaaFügt deinem Zauberbuch einen Tab hinzu (das Buch-Symbol an der Seite, unter den Zauberschulen), der alle noch beim Klassenlehrer lernbaren Fähigkeiten auflistet — nach Status gruppiert und nach Stufe gefärbt. Kein Lehrerbesuch nötig.|r",
    },
}
do
    local o = locOverrides[GetLocale()]
    if o then for k, v in pairs(o) do L[k] = v end end
end

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
            formattedLevel = format(L.LEVEL_FORMAT, level), formattedFullName = fullName,
            searchText = strlower(fullName), tooltipId = id,
            link = format("|cff71d5ff|Hspell:%d:0|h[%s]|h|r", id, name),
        }
        done(false)
    end

    if Spell and Spell.CreateFromSpellID then
        local si = Spell:CreateFromSpellID(id)
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
    { key = "available",     name = L.AVAILABLE,     color = GREEN_FONT_COLOR_CODE,  hideLevel = true },
    { key = "missingReqs",   name = L.MISSINGREQS,   color = ORANGE_FONT_COLOR_CODE, hideLevel = true },
    { key = "nextLevel",     name = L.NEXTLEVEL,     color = COMINGSOON },
    { key = "notLevel",      name = L.NOTLEVEL,      color = RED_FONT_COLOR_CODE },
    { key = "missingTalent", name = L.MISSINGTALENT, color = "|cffffffff", nameSort = true },
    { key = "known",         name = L.KNOWN,         color = GRAY_FONT_COLOR_CODE, hideLevel = true, nameSort = true },
}
local categoryByKey = {}
for _, cat in ipairs(categories) do
    cat.spells = {}
    cat.isHeader = true
    cat.formattedName = (cat.color or "") .. cat.name .. CLOSE
    categoryByKey[cat.key] = cat
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
        tinsert(mod._data, { isHeader = true, formattedName = L.NO_RESULTS })
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
            if not s or s.isHeader then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if s.tooltipId then GameTooltip:SetSpellByID(s.tooltipId) end
            if s.cost and s.cost > 0 then
                GameTooltip:AddLine(format(L.COST_FORMAT, GetCoinTextureString(s.cost)))
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
        tab.tooltip = L.TAB_TEXT
        tab:Show()
        if SpellBookFrame.selectedSkillLine == SKILL_LINE_TAB then
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

function mod:OnEnable()
    if not mod._built then
        createFrame()
        cacheAllSpells()
        rebuild()
        mod._built = true
    end
    ns:RegisterEvent("PLAYER_LEVEL_UP", onLevelOrLearn)
    ns:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", onLevelOrLearn)
    ns:RegisterEvent("LEARNED_SPELL_IN_TAB", onLevelOrLearn)
    if mod._tab and SpellBookFrame and SpellBookFrame.UpdateSkillLineTabs and SpellBookFrame:IsVisible() then
        SpellBookFrame:UpdateSkillLineTabs()
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_LEVEL_UP", onLevelOrLearn)
    ns:UnregisterEvent("LEARNED_SPELL_IN_SKILL_LINE", onLevelOrLearn)
    ns:UnregisterEvent("LEARNED_SPELL_IN_TAB", onLevelOrLearn)
    if mod._frame then mod._frame:Hide() end
    if mod._tab then mod._tab:Hide() end
end

function mod:GetOptions()
    return {
        { type = "desc", text = L.OPTION_DESC },
    }
end
