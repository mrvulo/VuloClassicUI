-- Casting on a bag item is protected: one hardware click on a SecureActionButton = one disenchant, and every secure attribute write is guarded by InCombatLockdown().
local _, ns = ...
local L = ns.L

local DISENCHANT_SPELL_ID = 13262

local mod = ns:RegisterModule("disenchantqueue", {
    name        = "Disenchant Queue",
    group       = "QoL",
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
        if current and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetBagItem(current.bag, current.slot)
            GameTooltip:Show()
        end
    end)
    hover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
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
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L[textKey], 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    _G.SLASH_VCUIDISENCHANT1 = "/disenchant"
    _G.SLASH_VCUIDISENCHANT2 = "/entzaubern"
    _G.SlashCmdList["VCUIDISENCHANT"] = function()
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
