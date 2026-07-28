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
