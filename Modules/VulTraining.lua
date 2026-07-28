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
