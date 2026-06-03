-- =========================================================
-- VuloClassicUI / Modules / ProfessionWindow
-- Enlarges and themes the profession windows to match the quest log:
--   * TradeSkillFrame  (most professions + secondary skills)
--   * CraftFrame       (Enchanting / Beast Training)
-- Each gets a wider frame with the detail pane beside the recipe list and a
-- Parchment or Dark theme, using the same bundled parchment image as the quest
-- log. Both Blizzard UIs are load-on-demand, so we wait for ADDON_LOADED.
-- Everything is guarded; a /reload fully restores the frames.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("professionwindow", {
    name        = "Profession Window",
    group       = "QoL",
    description = "Enlarges and themes the profession windows (Tradeskill & Craft) to match the quest log: the detail pane sits beside the recipe list, with a Parchment or Dark theme.",
    defaults = {
        enabled   = true,
        larger    = true,        -- enlarge the frames (detail beside the list)
        theme     = "parchment", -- "parchment" | "dark"
        counts    = true,        -- show "[N] craftable" after each recipe
        favorites = {},          -- [recipeName] = true (right-click a recipe)
        prices    = true,        -- show AH value / cost / profit (needs Auctionator)
        showSource     = true,   -- CraftLib: where the recipe comes from
        showThresholds = true,   -- CraftLib: orange/yellow/green/grey skill levels
        showSkillup    = true,   -- CraftLib: skill-up chance colour at your skill
    },
})

-- Same bundled parchment the quest log uses (atlas: top half is the parchment).
local PARCHMENT = "Interface\\AddOns\\VuloClassicUI\\Media\\textures\\questlog-parchment"

local TALL = 73

-- Per-frame configuration. The two profession frames share one structure but
-- use different element names; this table captures the differences.
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
        info        = function(idx) return GetTradeSkillInfo(idx) end,  -- name, type, numAvailable
        priceCapable = true,   -- recipes produce a sellable item -> show value/profit
        highlight   = "TradeSkillHighlightFrame",
        cancel      = "TradeSkillCancelButton",
        create      = "TradeSkillCreateButton",
        close       = "TradeSkillFrameCloseButton",
        expand      = "TradeSkillExpandTabLeft",
        extraHide   = { "TradeSkillHorizontalBarLeft" },
        detailTex   = { "TradeSkillDetailScrollFrameTop", "TradeSkillDetailScrollFrameBottom" },
        -- regions 9/10 are the horizontal bars (barLeft/barRight); on the taller
        -- frame they sit across the recipe text, so hide them too.
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
        highlight   = "CraftHighlightFrame",
        cancel      = "CraftCancelButton",
        create      = "CraftCreateButton",
        close       = "CraftFrameCloseButton",
        expand      = "CraftExpandTabLeft",
        costFmt     = "Craft%dCost",   -- craft rows carry a cost sub-element
        detailTex   = { "CraftDetailScrollFrameTop", "CraftDetailScrollFrameBottom" },
        hideRegions = { 4, 5, 9, 10 },
        repos = function(f)
            local dd = f.Dropdown
            if dd then dd:ClearAllPoints(); dd:SetPoint("TOPLEFT", f, "TOPLEFT", 550, -42) end
        end,
    },
}

local states = {}  -- [frameName] = { done = bool, regs = { tex, tex } }

local function isLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

-- =========================================================
-- Theme (tint the bundled parchment, or desaturate + darken it)
-- =========================================================
local function applyTheme(cfg)
    local st = states[cfg.frame]
    if not (st and st.regs) then return end
    local dark = (mod.db.theme == "dark")
    for _, r in ipairs(st.regs) do
        -- Parchment shows the image as-is; dark desaturates + tints it dark.
        if r.SetDesaturated then r:SetDesaturated(dark) end
        if dark then r:SetVertexColor(0.16, 0.15, 0.14, 1)
        else        r:SetVertexColor(1, 1, 1, 1) end
    end
end

-- =========================================================
-- Recipe list: craftable count "[N]" + right-click favourite star
-- =========================================================
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"  -- the single yellow star

local function enhanceRow(btn, cfg)
    if btn._vcuiStarBtn then return end

    -- An always-visible star on each recipe row: dim when not a favourite, gold
    -- when it is. Click the star (or right-click the row) to toggle.
    local sb = CreateFrame("Button", nil, btn)
    sb:SetSize(14, 14)
    sb:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
    local tex = sb:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(STAR)   -- full single-icon file, no cropping
    sb._tex = tex
    btn._vcuiStarBtn = sb

    -- Some rows carry textureless, solid overlay textures that render as a box
    -- around the text (e.g. from a movable-frame addon). Hide those; real icon
    -- textures keep a texture path, so they're left alone.
    btn._vcuiBoxes = {}
    for _, r in ipairs({ btn:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then
            local t = r.GetTexture and r:GetTexture()
            -- textureless overlays, OR the rounded highlight/selection box
            -- (UI-QuestTitleHighlight, fileID 130835 on this client). The
            -- selected recipe stays visible via its bold/white text.
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
    sb:SetScript("OnEnter", function()
        GameTooltip:SetOwner(sb, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Favourite (click to toggle)"], 1, 1, 1)
        GameTooltip:Show()
    end)
    sb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Right-click anywhere on the row also toggles (left-click still selects).
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:HookScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then toggle() end
    end)
end

local function refreshList(cfg)
    if not mod._enabled then return end

    -- Hide leftover thin horizontal divider bars that sit across the recipe text
    -- on the enlarged frame. The region index varies by client and Blizzard
    -- re-shows them on every update, so scan once then re-hide each refresh.
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
                        -- thin + wide = a horizontal divider bar; skip the tall
                        -- parchment/vertical borders and the title area at the top
                        local nearTop = (ftop and top and (ftop - top) < 45)
                        if h > 0 and h <= 20 and w >= 100 and not nearTop then
                            st.bars[#st.bars + 1] = r
                        end
                    end
                end
            end
            -- The recipe list scroll frame carries border textures (fileID
            -- 130969) that draw a frame/box around the list. Hide them too.
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

    local displayed = _G[cfg.displayed] or 0
    -- Pull the favourite stars further in when a scrollbar is showing, so they
    -- don't sit crammed at the far right edge (e.g. First Aid's long list).
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
                -- Star on every recipe row: faint when not a favourite, gold when it is.
                sb:Show()
                if mod.db.favorites[name] then
                    sb._tex:SetDesaturated(false); sb._tex:SetAlpha(1)
                else
                    sb._tex:SetDesaturated(true);  sb._tex:SetAlpha(0.35)
                end
                if mod.db.counts and numAvailable and numAvailable > 0 then
                    local txt = btn:GetText()
                    -- Blizzard re-sets the plain name each update, so append once.
                    if txt and not txt:find("%[%d+%]%s*$") then
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

-- =========================================================
-- Auction value + profit (TradeSkill only; needs Auctionator for prices)
-- =========================================================
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

local priceFS, priceHooked

local function coin(c) return GetCoinTextureString and GetCoinTextureString(c) or (math.floor((c or 0) / 10000) .. "g") end

-- =========================================================
-- CraftLib (optional): recipe source, skill thresholds, skill-up colour.
-- =========================================================
local function hasCraftLib()
    local c = _G.CraftLib
    return (c and c.GetRecipeByItemId and c.IsReady and c:IsReady()) and true or false
end

local function selectedCraftRecipe()
    if not hasCraftLib() then return nil end
    local idx = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex()
    if not idx or idx < 1 then return nil end
    local id = linkToID(GetTradeSkillItemLink and GetTradeSkillItemLink(idx))
    if not id then return nil end
    local ok, recipe = pcall(_G.CraftLib.GetRecipeByItemId, _G.CraftLib, id)
    return ok and recipe or nil
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

local function skillupText(recipe)
    if not (recipe and GetTradeSkillLine) then return nil end
    -- NOTE: must NOT write `GetTradeSkillLine and GetTradeSkillLine()` — the
    -- `and` collapses the multi-return to one value, so rank would be nil.
    local _, rank = GetTradeSkillLine()
    if not rank then return nil end
    local diff = _G.CraftLib:GetRecipeDifficulty(recipe, rank)
    return L["Skill-up"] .. ": " .. (DIFF_COL[diff] or "|cffffffff") .. L[diff] .. "|r"
end

-- =========================================================
-- Detail info block (auction value/profit + CraftLib lines), bottom of detail
-- =========================================================
local DETAIL_KEYS = { "value", "cost", "profit", "skillup", "thresholds", "source" }

local function buildPriceBlock()
    if priceFS then return end
    local f, detail = _G.TradeSkillFrame, _G.TradeSkillDetailScrollFrame
    if not (f and detail) then return end
    priceFS = {}
    local function line(prev)
        -- GameFontNormal = the gold label font Auctionator's crafting info uses.
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if prev then fs:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, 3)
        else         fs:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 16, 22) end
        fs:SetJustifyH("LEFT")
        return fs
    end
    -- stacked bottom-up; empty lines collapse so hidden rows take no space
    priceFS.profit     = line(nil)
    priceFS.cost       = line(priceFS.profit)
    priceFS.value      = line(priceFS.cost)
    priceFS.skillup    = line(priceFS.value)
    priceFS.thresholds = line(priceFS.skillup)
    priceFS.source     = line(priceFS.thresholds)
end

local function clearPrices()
    if not priceFS then return end
    for _, k in ipairs(DETAIL_KEYS) do priceFS[k]:SetText("") end
end

local function updateDetailInfo()
    buildPriceBlock()
    if not priceFS then return end

    -- Labels keep GameFontNormal's gold colour (Auctionator style); values carry
    -- their own embedded colour codes.
    local idx = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex()
    if not idx or idx < 1 then clearPrices(); return end

    -- Auction value / material cost / profit (needs Auctionator)
    if mod.db.prices and hasAuctionator() then
        local craftedID = linkToID(GetTradeSkillItemLink and GetTradeSkillItemLink(idx))
        local minMade = 1
        if GetTradeSkillNumMade then local a = GetTradeSkillNumMade(idx); if a and a > 0 then minMade = a end end
        local value = aucPrice(craftedID)
        local cost, known = 0, true
        local n = (GetTradeSkillNumReagents and GetTradeSkillNumReagents(idx)) or 0
        for r = 1, n do
            local _, _, needed = GetTradeSkillReagentInfo(idx, r)
            local p = aucPrice(linkToID(GetTradeSkillReagentItemLink(idx, r)))
            if p then cost = cost + p * (needed or 1) else known = false end
        end
        if value then priceFS.value:SetText(L["AH value"] .. ": " .. coin(value * minMade))
        else          priceFS.value:SetText(L["AH value"] .. ": |cff888888?|r") end
        if n > 0 and known then priceFS.cost:SetText(L["Material cost"] .. ": " .. coin(cost))
        else                    priceFS.cost:SetText(L["Material cost"] .. ": |cff888888?|r") end
        if value and known and n > 0 then
            local profit = value * minMade - cost
            if profit >= 0 then priceFS.profit:SetText(L["Profit"] .. ": |cff20ff20" .. coin(profit) .. "|r")
            else                priceFS.profit:SetText(L["Profit"] .. ": |cffff5555-" .. coin(-profit) .. "|r") end
        else
            priceFS.profit:SetText("")
        end
    else
        priceFS.value:SetText(""); priceFS.cost:SetText(""); priceFS.profit:SetText("")
    end

    -- CraftLib lines (need CraftLib); toggled by the bottom buttons
    local cr = selectedCraftRecipe()
    priceFS.skillup:SetText((mod.db.showSkillup and skillupText(cr)) or "")
    priceFS.thresholds:SetText((mod.db.showThresholds and thresholdText(cr)) or "")
    priceFS.source:SetText((mod.db.showSource and sourceText(cr)) or "")
end

local function installDetailInfo()
    if priceHooked then return end
    if not _G.TradeSkillFrame_SetSelection then return end
    priceHooked = true
    hooksecurefunc("TradeSkillFrame_SetSelection", updateDetailInfo)

    -- CraftLib toggle buttons just under the list (only if CraftLib is present)
    if hasCraftLib() and _G.TradeSkillListScrollFrame then
        -- {label, dbKey, gap, width}: gap = x from the list (1st) or from the
        -- prev button. Smaller gaps pull a button further left.
        local defs = {
            { L["Source"],   "showSource",     -8, 108 },
            { L["Levels"],   "showThresholds", 2,  96 },
            { L["Skill-up"], "showSkillup",    0,  96 },
        }
        local prev
        for _, d in ipairs(defs) do
            local key = d[2]
            local b = CreateFrame("Button", nil, _G.TradeSkillFrame, "UIPanelButtonTemplate")
            b:SetSize(d[4] or 96, 20)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", d[3], 0)
            else b:SetPoint("TOPLEFT", _G.TradeSkillListScrollFrame, "BOTTOMLEFT", d[3], -1) end
            b:SetText(d[1])
            local function refresh()
                local on = mod.db[key]
                b:GetFontString():SetTextColor(on and 1 or 0.6, on and 0.82 or 0.6, on and 0 or 0.6)
            end
            b:SetScript("OnClick", function() mod.db[key] = not mod.db[key]; refresh(); updateDetailInfo() end)
            refresh()
            prev = b
        end
    end

    updateDetailInfo()
end

-- =========================================================
-- Enlarge + parchment background (runs once per frame)
-- =========================================================
local function setupFrame(cfg)
    local st = states[cfg.frame]
    if not st then st = {}; states[cfg.frame] = st end
    if st.done then return end
    local f = _G[cfg.frame]
    if not f then return end
    st.done = true

    if mod.db.larger then
        pcall(function()
            -- Double-wide override + size
            if _G.UIPanelWindows and _G.UIPanelWindows[cfg.frame] then
                _G.UIPanelWindows[cfg.frame] = { area = "override", pushable = 1,
                    xoffset = -16, yoffset = 12, bottomClampOverride = 152, width = 685, height = 487, whileDead = 1 }
            end
            f:SetWidth(714)
            f:SetHeight(487 + TALL)

            local title = _G[cfg.title]
            if title then title:ClearAllPoints(); title:SetPoint("TOP", f, "TOP", 0, -18) end

            -- Recipe list: a touch shorter than the frame so the last row keeps
            -- a clear margin above the bottom buttons.
            local listH = 336 + TALL
            local list = _G[cfg.list]
            if list then
                list:ClearAllPoints()
                list:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -75)
                list:SetSize(295, listH)
            end

            -- Reposition the client's original rows (+ their cost column, if any)
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

            -- Fit the displayed row count to the list height so rows never spill
            -- into the button row (independent of the client's default count).
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
            -- Hide any default rows beyond the fit (if the client showed more).
            for i = fitRows + 1, old do
                local b = _G[cfg.rowFmt:format(i)]
                if b then b:Hide() end
            end
            _G[cfg.displayed] = fitRows

            -- Highlight bar spans the wider list
            if cfg.highlight and _G[cfg.highlight] then
                hooksecurefunc(_G[cfg.highlight], "Show", function()
                    _G[cfg.highlight]:SetWidth(290)
                end)
            end

            -- Detail pane to the right, full height; hide its own edge textures
            local detail = _G[cfg.detail]
            if detail then
                detail:ClearAllPoints()
                detail:SetPoint("TOPLEFT", f, "TOPLEFT", 352, -74)
                detail:SetSize(298, 336 + TALL)
            end
            for _, tn in ipairs(cfg.detailTex) do
                local t = _G[tn]; if t and t.SetAlpha then t:SetAlpha(0) end
            end

            -- Bottom buttons
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

            -- Reposition the filter dropdowns / search box for the wider frame
            if cfg.repos then cfg.repos(f) end

            -- Parchment background: two slices of the bundled image fill the
            -- whole frame at ~1:1 (left = list, right = detail).
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
    end

    applyTheme(cfg)
    installListEnhancements(cfg)   -- count + favourites work with or without enlarge
    if cfg.priceCapable then installDetailInfo() end
end

-- =========================================================
-- Lifecycle
-- =========================================================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if not mod._enabled then return end
    for _, cfg in ipairs(FRAMES) do
        if name == cfg.addon then C_Timer.After(0, function() setupFrame(cfg) end) end
    end
end)

function mod:OnEnable()
    -- Frames already loaded this session (professions opened before login reload)
    for _, cfg in ipairs(FRAMES) do
        if isLoaded(cfg.addon) then setupFrame(cfg) end
    end
end

function mod:OnDisable()
    -- The enlarge isn't cleanly reversible at runtime; a /reload restores it.
end

-- =========================================================
-- Options
-- =========================================================
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
        { type = "toggle", label = L["Show craftable count"],
          tooltip = L["Shows how many of each recipe you can make right now, like [12]."],
          get = function() return mod.db.counts end,
          set = function(_, v)
              mod.db.counts = v
              if _G.TradeSkillFrame and _G.TradeSkillFrame:IsShown() and _G.TradeSkillFrame_Update then pcall(_G.TradeSkillFrame_Update) end
              if _G.CraftFrame and _G.CraftFrame:IsShown() and _G.CraftFrame_Update then pcall(_G.CraftFrame_Update) end
          end },
        { type = "desc", text = L["|cff888888Click a recipe's star (or right-click the recipe) to favourite it — the star turns gold.|r"] },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Auction value"] },
        { type = "toggle", label = L["Show auction value & profit"],
          tooltip = L["On the selected recipe, shows the crafted item's auction value, material cost and profit, using Auctionator's price data."],
          get = function() return mod.db.prices end,
          set = function(_, v)
              mod.db.prices = v
              if _G.TradeSkillFrame and _G.TradeSkillFrame:IsShown() and updateDetailInfo then updateDetailInfo() end
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
