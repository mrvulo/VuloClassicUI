-- =========================================================
-- VuloClassicUI / Modules / DisenchantQueue
-- A "click once per item" disenchant helper for enchanters.
--
-- WoW does NOT allow unattended automation here: UseContainerItem / casting a
-- spell on a bag item is a protected action. The only legal way is a
-- SecureActionButton the player clicks; one hardware click = one disenchant.
-- The technique (confirmed working on Classic/TBC/Anniversary, e.g. by
-- DisenchanterPlus) is a secure button with:
--     type        = "spell"
--     spell       = 13262           (Disenchant)
--     target-bag  / target-slot     (the item to disenchant)
-- After each disenchant we load the next eligible bag item onto the same button
-- (out of combat), so the player just keeps clicking one button to work through
-- the whole queue instead of casting + picking each item by hand.
--
-- Everything that touches secure attributes is guarded by InCombatLockdown().
-- =========================================================
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
        point      = nil, -- saved window position { p, x, y }
    },
})

-- Armor slots that are never disenchantable
local EXCLUDE_EQUIP = { INVTYPE_TABARD = true, INVTYPE_BODY = true }

local sessionIgnore = {}  -- [bag.."-"..slot] = true (skipped this session)
local win                 -- the window frame (built lazily)

-- =========================================================
-- Helpers
-- =========================================================
local function isEnchanter()
    if IsSpellKnown and IsSpellKnown(DISENCHANT_SPELL_ID) then return true end
    if IsPlayerSpell and IsPlayerSpell(DISENCHANT_SPELL_ID) then return true end
    return false
end

-- Container info across the C_Container / legacy split (2.5.5 has C_Container,
-- but we stay defensive).
local function containerInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local i = C_Container.GetContainerItemInfo(bag, slot)
        if i then return i.itemID, i.quality, i.hyperlink, i.iconFileID, i.isLocked end
        return nil
    elseif _G.GetContainerItemInfo then
        local icon, _, locked, quality, _, _, link, _, _, itemID = _G.GetContainerItemInfo(bag, slot)
        return itemID, quality, link, icon, locked
    end
end

local function numSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    return _G.GetContainerNumSlots and _G.GetContainerNumSlots(bag) or 0
end

-- Is the item a disenchant candidate? (weapon/armour of the chosen quality)
local function eligible(itemID, quality, locked)
    if not itemID or locked then return false end
    if not quality or quality < mod.db.minQuality or quality > mod.db.maxQuality then return false end
    local _, _, _, equipLoc, _, classID, subClassID = GetItemInfoInstant(itemID)
    if classID ~= 2 and classID ~= 4 then return false end   -- 2 Weapon, 4 Armor
    if EXCLUDE_EQUIP[equipLoc] then return false end          -- tabard / shirt
    if classID == 2 and subClassID == 20 then return false end -- fishing pole
    return true
end

-- Find the first eligible item in bags (0-4). Returns a table or nil.
local function findNext()
    for bag = 0, 4 do
        for slot = 1, numSlots(bag) do
            if not sessionIgnore[bag .. "-" .. slot] then
                local itemID, quality, link, icon, locked = containerInfo(bag, slot)
                if eligible(itemID, quality, locked) then
                    return { bag = bag, slot = slot, itemID = itemID, link = link, icon = icon }
                end
            end
        end
    end
end

-- Count remaining eligible items (for the progress text)
local function countRemaining()
    local n = 0
    for bag = 0, 4 do
        for slot = 1, numSlots(bag) do
            if not sessionIgnore[bag .. "-" .. slot] then
                local itemID, quality, _, _, locked = containerInfo(bag, slot)
                if eligible(itemID, quality, locked) then n = n + 1 end
            end
        end
    end
    return n
end

-- =========================================================
-- Window: current item + a secure "Disenchant" button + skip / close
-- =========================================================
local current  -- the entry currently loaded on the secure button

local function clearButton()
    local b = win and win.cast
    if not b or InCombatLockdown() then return end
    b:SetAttribute("spell", nil)
    b:SetAttribute("target-bag", nil)
    b:SetAttribute("target-slot", nil)
    b:Disable()
end

-- Load the next eligible item onto the secure button (out of combat only).
local function loadNext()
    if not win or not win:IsShown() then return end
    if InCombatLockdown() then return end  -- retried on PLAYER_REGEN_ENABLED
    local e = findNext()
    current = e
    local b = win.cast
    if e then
        b:SetAttribute("spell", DISENCHANT_SPELL_ID)
        b:SetAttribute("target-bag", e.bag)
        b:SetAttribute("target-slot", e.slot)
        b:Enable()
        win.icon:SetTexture(e.icon)
        win.icon:Show()
        win.itemText:SetText(e.link or "?")
        win.countText:SetText(string.format(L["%d item(s) to disenchant"], countRemaining()))
    else
        b:SetAttribute("spell", nil); b:SetAttribute("target-bag", nil); b:SetAttribute("target-slot", nil)
        b:Disable()
        win.icon:Hide()
        win.itemText:SetText(L["|cff888888Nothing to disenchant.|r"])
        win.countText:SetText("")
    end
end

local function buildWindow()
    if win then return win end

    local f = CreateFrame("Frame", "VuloClassicUIDisenchantWindow", UIParent, "BackdropTemplate")
    f:SetSize(280, 150)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- restore / save position
    local p = mod.db.point
    if p then f:SetPoint(p.p or "CENTER", UIParent, p.p or "CENTER", p.x or 0, p.y or 0)
    else f:SetPoint("CENTER") end

    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        mod.db.point = { p = point, x = x, y = y }
    end)

    -- title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("|cff9b6cff" .. L["Disenchant Queue"] .. "|r")

    -- close (X)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- current item icon + name
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(32, 32)
    f.icon:SetPoint("TOPLEFT", 12, -34)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.itemText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.itemText:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
    f.itemText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.itemText:SetJustifyH("LEFT")
    f.itemText:SetWordWrap(false)

    f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.countText:SetPoint("TOPLEFT", f.icon, "BOTTOMLEFT", 0, -6)

    -- the secure cast button (visible main action)
    local cast = CreateFrame("Button", "VuloClassicUIDisenchantButton", f,
        "UIPanelButtonTemplate, SecureActionButtonTemplate")
    cast:SetSize(150, 26)
    cast:SetPoint("BOTTOMLEFT", 12, 12)
    cast:SetText(L["Disenchant"])
    cast:RegisterForClicks("LeftButtonUp")
    cast:SetAttribute("type", "spell")
    cast:SetAttribute("unit", "none")
    cast:Disable()
    -- After the secure cast fires, the item gets consumed and BAG_UPDATE_DELAYED
    -- advances the queue; here we just give immediate feedback.
    cast:HookScript("PostClick", function()
        if current then win.countText:SetText(L["Disenchanting…"]) end
    end)
    f.cast = cast

    -- skip current (insecure; just ignores this slot for the session)
    local skip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    skip:SetSize(96, 26)
    skip:SetPoint("LEFT", cast, "RIGHT", 6, 0)
    skip:SetText(L["Skip"])
    skip:SetScript("OnClick", function()
        if current then sessionIgnore[current.bag .. "-" .. current.slot] = true end
        loadNext()
    end)

    -- events: advance the queue when bags change, retry after combat
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

-- =========================================================
-- Public open/toggle
-- =========================================================
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

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    -- slash commands
    _G.SLASH_VCUIDISENCHANT1 = "/disenchant"
    _G.SLASH_VCUIDISENCHANT2 = "/entzaubern"
    _G.SlashCmdList["VCUIDISENCHANT"] = function()
        if mod._enabled then mod:ToggleWindow() else ns:Print(L["This module is disabled."]) end
    end
end

function mod:OnDisable()
    if win then win:Hide() end
end

-- =========================================================
-- Options
-- =========================================================
local QUALITY_VALUES = {
    { value = 2, text = "|cff1eff00" .. (_G.ITEM_QUALITY2_DESC or "Uncommon") .. "|r" },
    { value = 3, text = "|cff0070dd" .. (_G.ITEM_QUALITY3_DESC or "Rare") .. "|r" },
    { value = 4, text = "|cffa335ee" .. (_G.ITEM_QUALITY4_DESC or "Epic") .. "|r" },
}

function mod:GetOptions()
    return {
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
    }
end
