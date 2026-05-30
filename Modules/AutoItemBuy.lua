-- =========================================================
-- VuloClassicUI / Modules / AutoItemBuy
-- Automatically buys certain items at certain vendors.
-- Hold Shift when opening the merchant window = emergency stop.
--
-- Configurable in the UI: vendor names and item names.
-- Default: off.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("autoitembuy", {
    name        = "Auto Item Buy",
    group       = "QoL",
    description = "Automatically buys configured items at configured vendors. Shift when opening the merchant window = emergency stop.",
    defaults = {
        enabled    = false,  -- OFF by default
        autoClose  = true,   -- close merchant window after purchase
        chatMsg    = true,   -- print on each purchase
        vendors    = {},     -- vendors[vendorName] = { itemName1 = true, itemName2 = true, ... }
    },
})

-- =========================================================
-- Buffers for UI input (not in the DB)
-- =========================================================
local addVendorBuffer  = ""
local selectedVendor   = nil  -- currently selected vendor in the UI
local addItemBuffer    = ""

-- =========================================================
-- Helper
-- =========================================================
local function p(fmt, ...)
    if not mod.db.chatMsg then return end
    ns:Print(L["|cffffd200[AutoItemBuy]|r "] .. string.format(fmt, ...))
end

local function getVendorList()
    local list = {}
    for name in pairs(mod.db.vendors or {}) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

local function getVendorItems(vendorName)
    local list = {}
    local v = mod.db.vendors and mod.db.vendors[vendorName]
    if not v then return list end
    for itemName in pairs(v) do
        table.insert(list, itemName)
    end
    table.sort(list)
    return list
end

local function refreshUI()
    if ns.UI and ns.UI.currentModule == "autoitembuy" then
        ns.UI:BuildOptionsPage("autoitembuy", "default")
    end
end

-- =========================================================
-- Event handling (MERCHANT_SHOW)
-- =========================================================
local eventFrame

local function setupEvents()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("MERCHANT_SHOW")
    eventFrame:SetScript("OnEvent", function(self, event)
        if event ~= "MERCHANT_SHOW" then return end
        if not mod._enabled then return end

        -- Hold SHIFT = emergency stop
        if IsShiftKeyDown() then return end

        local npcName = UnitName("npc") or UnitName("target")
        if not npcName then return end

        local vendor = mod.db.vendors and mod.db.vendors[npcName]
        if not vendor then return end

        local numItems = GetMerchantNumItems()
        local bought = 0
        for i = 1, numItems do
            local name = GetMerchantItemInfo(i)
            if name and vendor[name] then
                p(L["Buying: "] .. name)
                pcall(function() BuyMerchantItem(i, 1) end)
                bought = bought + 1
            end
        end

        -- Optional: close merchant window automatically
        if mod.db.autoClose and bought > 0 then
            local count = 0
            self:SetScript("OnUpdate", function(s)
                count = count + 1
                if count > 10 then
                    CloseMerchant()
                    s:SetScript("OnUpdate", nil)
                end
            end)
        end
    end)
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    setupEvents()
end

-- =========================================================
-- Options page
-- =========================================================
function mod:GetOptions()
    local items = {}

    -- =========================================================
    -- General settings
    -- =========================================================
    table.insert(items, { type = "header", text = L["General"] })

    table.insert(items, {
        type = "toggle", label = L["Close merchant window after purchase"],
        tooltip = L["Closes the merchant window automatically ~0.2s after purchase."],
        get = function() return mod.db.autoClose end,
        set = function(_, v) mod.db.autoClose = v end,
    })

    table.insert(items, {
        type = "toggle", label = L["Chat message on each purchase"],
        get = function() return mod.db.chatMsg end,
        set = function(_, v) mod.db.chatMsg = v end,
    })

    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaTip: Hold SHIFT when opening the merchant window to skip automatic purchase once.|r"] })

    table.insert(items, { type = "spacer", height = 12 })

    -- =========================================================
    -- Add vendor
    -- =========================================================
    table.insert(items, { type = "header", text = L["Add Vendor"] })

    table.insert(items, {
        type = "group", layout = "row", gap = 6,
        items = {
            {
                type = "editbox", label = L["Vendor Name"],
                width = 260,
                get = function() return addVendorBuffer end,
                set = function(_, v) addVendorBuffer = v end,
            },
            {
                type = "button", label = L["Add"], width = 100,
                onClick = function()
                    local name = (addVendorBuffer or ""):match("^%s*(.-)%s*$")
                    if not name or name == "" then
                        ns:Print(L["|cffff5555Please enter a vendor name.|r"])
                        return
                    end
                    mod.db.vendors = mod.db.vendors or {}
                    if mod.db.vendors[name] then
                        ns:Print(L["|cffff5555Vendor '%s' already exists.|r"], name)
                        return
                    end
                    mod.db.vendors[name] = {}
                    selectedVendor = name
                    addVendorBuffer = ""
                    ns:Print(L["Vendor '%s' added."], name)
                    refreshUI()
                end,
            },
        },
    })

    table.insert(items, { type = "spacer", height = 12 })

    -- =========================================================
    -- Vendor selection & management
    -- =========================================================
    table.insert(items, { type = "header", text = L["Manage Vendors"] })

    local vendorList = getVendorList()
    if #vendorList == 0 then
        table.insert(items, { type = "desc",
            text = L["|cffaaaaaaNo vendors added yet. Add a vendor above, then select it here to configure items.|r"] })
    else
        -- Auto-select if none chosen yet
        if not selectedVendor or not mod.db.vendors[selectedVendor] then
            selectedVendor = vendorList[1]
        end

        local vendorValues = {}
        for _, v in ipairs(vendorList) do
            table.insert(vendorValues, { value = v, text = v })
        end

        table.insert(items, {
            type = "dropdown", label = L["Currently selected vendor"],
            width = 280,
            values = vendorValues,
            get = function() return selectedVendor end,
            set = function(_, v)
                selectedVendor = v
                refreshUI()
            end,
        })

        table.insert(items, {
            type = "button", label = L["Delete this vendor"], width = 180,
            onClick = function()
                if not selectedVendor then return end
                local name = selectedVendor
                mod.db.vendors[name] = nil
                ns:Print(L["Vendor '%s' removed."], name)
                selectedVendor = nil
                refreshUI()
            end,
        })

        table.insert(items, { type = "spacer", height = 12 })

        -- =========================================================
        -- Items for selected vendor
        -- =========================================================
        table.insert(items, { type = "header",
            text = string.format(L["Items at '%s'"], selectedVendor) })

        table.insert(items, {
            type = "group", layout = "row", gap = 6,
            items = {
                {
                    type = "editbox", label = L["Item name (exactly as in-game)"],
                    width = 260,
                    get = function() return addItemBuffer end,
                    set = function(_, v) addItemBuffer = v end,
                },
                {
                    type = "button", label = L["Add"], width = 100,
                    onClick = function()
                        local name = (addItemBuffer or ""):match("^%s*(.-)%s*$")
                        if not name or name == "" then
                            ns:Print(L["|cffff5555Please enter an item name.|r"])
                            return
                        end
                        if not selectedVendor or not mod.db.vendors[selectedVendor] then return end
                        mod.db.vendors[selectedVendor][name] = true
                        addItemBuffer = ""
                        ns:Print(L["Item '%s' added at vendor '%s'."], name, selectedVendor)
                        refreshUI()
                    end,
                },
            },
        })

        table.insert(items, { type = "desc",
            text = L["|cffaaaaaaItem names must match the in-game name exactly (including case and special characters).|r"] })

        local itemList = getVendorItems(selectedVendor)
        if #itemList == 0 then
            table.insert(items, { type = "desc",
                text = L["|cffaaaaaaNo items configured. Add items above that should be bought automatically at this vendor.|r"] })
        else
            for _, itemName in ipairs(itemList) do
                table.insert(items, {
                    type = "group", layout = "row", gap = 6,
                    items = {
                        { type = "desc", text = "- " .. itemName, width = 340 },
                        {
                            type = "button", label = L["Remove"], width = 90,
                            onClick = function()
                                if not selectedVendor or not mod.db.vendors[selectedVendor] then return end
                                mod.db.vendors[selectedVendor][itemName] = nil
                                ns:Print(L["Item '%s' removed."], itemName)
                                refreshUI()
                            end,
                        },
                    },
                })
            end
        end
    end

    return items
end
