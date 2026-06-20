-- =========================================================
-- VuloClassicUI / Modules / VulTraining
-- Adds a tab to the Blizzard spell book that lists the abilities you can still
-- learn from your class trainer, grouped by level.
-- The game only exposes this data at the trainer, so we scan it on TRAINER_SHOW
-- and cache it per class (account-wide).
--
-- The spell-book tab is a normal button on the side; selecting it shows an
-- opaque list panel ON TOP of the spell grid (we never touch the secure spell
-- buttons, so there is no taint). Registered as a QoL sub-module so it has an
-- on/off entry in the Quality of Life tabs.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("vultraining", {
    name        = "VulTraining",
    group       = "QoL",
    description = "Adds a tab to your spell book listing the abilities you can still learn from your class trainer (grouped by level). Open your trainer once to fill / refresh the list.",
    defaults = {
        enabled = true,
        classes = {},   -- classFile -> { { name, rank, level, avail, icon }, ... }
    },
})

local floor = math.floor
local function classKey()
    local _, k = UnitClass("player")
    return k or "UNKNOWN"
end

-- =========================================================
-- Scan the class trainer (current + future abilities)
-- =========================================================
local function scanTrainer()
    if not GetNumTrainerServices then return end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end  -- skip profession trainers

    local getF, setF = GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter
    local fa, fu, fs
    if getF then fa, fu, fs = getF("available"), getF("unavailable"), getF("used") end
    if setF then setF("available", 1); setF("unavailable", 1); setF("used", 0) end

    local list = {}
    for i = 1, (GetNumTrainerServices() or 0) do
        local name, rank, category = GetTrainerServiceInfo(i)
        if name and name ~= "" and category ~= "header" and category ~= "used" then
            list[#list + 1] = {
                name  = name,
                rank  = rank,
                level = (GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)) or 0,
                avail = (category == "available"),
                icon  = (GetTrainerServiceIcon and GetTrainerServiceIcon(i)) or nil,
            }
        end
    end

    if setF then setF("available", fa and 1 or 0); setF("unavailable", fu and 1 or 0); setF("used", fs and 1 or 0) end

    if #list > 0 then
        mod.db.classes = mod.db.classes or {}
        mod.db.classes[classKey()] = list
        if mod._populate and mod._listShown then mod._populate() end
    end
end

-- =========================================================
-- Spell-book tab + list panel
-- =========================================================
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local rows = {}      -- row pool

-- Build the flat row list (headers + entries) from the cached data.
local function buildRows()
    local data = mod.db.classes and mod.db.classes[classKey()]
    local out = {}
    if not data or #data == 0 then
        out[#out + 1] = { header = L["|cffffd200Open your class trainer once to fill this list.|r"] }
        return out
    end
    local lvl = (UnitLevel and UnitLevel("player")) or 0
    local avail, upcoming = {}, {}
    for _, e in ipairs(data) do
        if e.avail or e.level <= lvl then avail[#avail + 1] = e else upcoming[#upcoming + 1] = e end
    end
    table.sort(avail, function(a, b) return (a.name or "") < (b.name or "") end)
    table.sort(upcoming, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return (a.name or "") < (b.name or "")
    end)
    if #avail > 0 then
        out[#out + 1] = { header = "|cff44ff44" .. L["Available now"] .. "|r" }
        for _, e in ipairs(avail) do out[#out + 1] = e end
    end
    if #upcoming > 0 then
        out[#out + 1] = { header = "|cff9b6cff" .. L["Upcoming"] .. "|r", gap = (#avail > 0) }
        local lastLvl
        for _, e in ipairs(upcoming) do
            if e.level ~= lastLvl then
                lastLvl = e.level
                out[#out + 1] = { sub = string.format(L["Level %d"], e.level) }
            end
            out[#out + 1] = e
        end
    end
    return out
end

local function makeRow(parent, i)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(20)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.text:SetJustifyH("LEFT")
    if ns.UI and ns.UI.Font then ns.UI.Font(r.text, 12) end
    rows[i] = r
    return r
end

local function populate()
    local child = mod._scrollChild
    if not child then return end
    local items = buildRows()
    local y = -4
    for i, it in ipairs(items) do
        local r = rows[i] or makeRow(child, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, y)
        r:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, y)
        if it.header then
            r.icon:Hide()
            r.text:ClearAllPoints(); r.text:SetPoint("LEFT", r, "LEFT", 6, 0); r.text:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.text:SetText(it.header)
            y = y - 22
        elseif it.sub then
            r.icon:Hide()
            r.text:ClearAllPoints(); r.text:SetPoint("LEFT", r, "LEFT", 10, 0); r.text:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.text:SetText("|cffbbbbbb" .. it.sub .. "|r")
            y = y - 18
        else
            r.icon:Show(); r.icon:SetTexture(it.icon or QUESTION)
            r.text:ClearAllPoints(); r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.text:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            local rank = (it.rank and it.rank ~= "") and (" |cff888888(" .. it.rank .. ")|r") or ""
            r.text:SetText((it.name or "?") .. rank)
            y = y - 20
        end
        r:Show()
    end
    for i = #items + 1, #rows do rows[i]:Hide() end
    child:SetHeight(math.max(1, -y + 4))
end
mod._populate = populate

local function setListShown(on)
    mod._listShown = on
    if mod._list then mod._list:SetShown(on) end
    if mod._tab then mod._tab:SetChecked(on) end
    if on then
        -- our tab is exclusive: visually deselect the real skill-line tabs
        for i = 1, 8 do local t = _G["SpellBookSkillLineTab" .. i]; if t and t.SetChecked then t:SetChecked(false) end end
        populate()
    end
end

local built = false
local function buildUI()
    if built or not SpellBookFrame then return end
    built = true

    -- opaque list panel over the spell grid (anchored to the grid corners)
    local f = CreateFrame("Frame", "VulTrainingBook", SpellBookFrame)
    f:SetFrameLevel(SpellBookFrame:GetFrameLevel() + 20)   -- above the spell buttons
    f:EnableMouse(true)
    if SpellButton1 and SpellButton12 then
        f:SetPoint("TOPLEFT",     SpellButton1,  "TOPLEFT",     -6, 8)
        f:SetPoint("BOTTOMRIGHT", SpellButton12, "BOTTOMRIGHT",  8, -8)
    else
        f:SetPoint("TOPLEFT",     SpellBookFrame, "TOPLEFT",     22, -78)
        f:SetPoint("BOTTOMRIGHT", SpellBookFrame, "BOTTOMRIGHT", -42, 82)
    end
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.06, 0.08, 0.97)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -6); title:SetText("VulTraining")
    if ns.UI and ns.UI.Font then ns.UI.Font(title, 14) end

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -28)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, d)
        local cur = self:GetVerticalScroll()
        local maxs = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maxs, cur - d * 24)))
    end)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    child:SetWidth(300)
    mod._scrollChild = child
    f:SetScript("OnSizeChanged", function(_, w) if child then child:SetWidth(math.max(1, (w or 320) - 16)) end end)

    f:Hide()
    mod._list = f

    -- side tab button
    local tab = CreateFrame("CheckButton", "VulTrainingTab", SpellBookFrame)
    tab:SetSize(32, 32)
    local icon = tab:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(); icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09"); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    local chk = tab:CreateTexture(nil, "OVERLAY"); chk:SetAllPoints(); chk:SetTexture("Interface\\Buttons\\CheckButtonHilight"); chk:SetBlendMode("ADD")
    tab:SetCheckedTexture(chk)
    tab:SetScript("OnClick", function() setListShown(not mod._listShown) end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("VulTraining"); GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", GameTooltip_Hide)
    mod._tab = tab

    -- clicking any real skill-line tab leaves our view
    for i = 1, 8 do
        local t = _G["SpellBookSkillLineTab" .. i]
        if t and t.HookScript then t:HookScript("OnClick", function() if mod._listShown then setListShown(false) end end) end
    end

    local function refreshTab()
        if not mod._tab then return end
        local n = (GetNumSpellTabs and GetNumSpellTabs()) or 0
        local anchor = n > 0 and _G["SpellBookSkillLineTab" .. n]
        tab:ClearAllPoints()
        if anchor then tab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -22)
        else tab:SetPoint("TOPRIGHT", SpellBookFrame, "TOPRIGHT", -2, -44) end
        local onSpellPage = ((SpellBookFrame.bookType or "spell") == (BOOKTYPE_SPELL or "spell"))
        tab:SetShown(onSpellPage and (mod._enabled ~= false))
        if (not onSpellPage) and mod._listShown then setListShown(false) end
    end
    mod._refreshTab = refreshTab
    if SpellBookFrame_UpdateSkillLineTabs then hooksecurefunc("SpellBookFrame_UpdateSkillLineTabs", refreshTab) end
    if SpellBookFrame_Update then hooksecurefunc("SpellBookFrame_Update", refreshTab) end

    SpellBookFrame:HookScript("OnShow", function() setListShown(false); refreshTab() end)
    SpellBookFrame:HookScript("OnHide", function() setListShown(false) end)
    refreshTab()
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    ns:RegisterEvent("TRAINER_SHOW", scanTrainer)
    buildUI()
    if mod._refreshTab then mod._refreshTab() end
end

function mod:OnDisable()
    ns:UnregisterEvent("TRAINER_SHOW", scanTrainer)
    setListShown(false)
    if mod._tab then mod._tab:Hide() end
end

-- =========================================================
-- Options (just the on/off entry — the list lives in the spell book)
-- =========================================================
function mod:GetOptions()
    return {
        { type = "desc",
          text = L["|cffaaaaaaAdds a tab to your spell book (the book icon on the side, below the spell schools) that lists the abilities you can still learn from your class trainer, grouped by level.|r"] },
        { type = "desc",
          text = L["|cffaaaaaaOpen your class trainer once to fill or refresh the list.|r"] },
    }
end
