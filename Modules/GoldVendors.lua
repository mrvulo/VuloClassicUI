-- Gold tracker + auto vendor buy; each in its own IIFE so file-level locals and early returns stay isolated.
(function(...)
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("goldtracker", {
    name        = "Gold Tracker",
    group       = "QoL",
    description = "Shows in the backpack gold tooltip how much gold has been gained or spent since the last reset. Per-char persistent.",
    defaults    = {
        enabled = true,
    },
})

local hooked = false

local function data()
    if not (ns.db and ns.db.char) then return nil end
    if not ns.db.char.goldtracker then
        ns.db.char.goldtracker = {
            sessionStart = nil,
            lastMoney    = nil,
            gained       = 0,
            spent        = 0,
        }
    end
    return ns.db.char.goldtracker
end

local GOLD_COLOR   = "|cffffd100"
local SILVER_COLOR = "|cffc7c7cf"
local COPPER_COLOR = "|cffeda55f"
local POS_COLOR    = "|cff44ff44"
local NEG_COLOR    = "|cffff4444"
local ACCENT       = "|cff9b6cff"
local GRAY         = "|cffaaaaaa"

local function formatCopper(copper)
    copper = math.abs(copper or 0)
    if copper == 0 then return "0" .. COPPER_COLOR .. "c|r" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts+1] = g .. GOLD_COLOR   .. "g|r" end
    if s > 0 then parts[#parts+1] = s .. SILVER_COLOR .. "s|r" end
    if c > 0 then parts[#parts+1] = c .. COPPER_COLOR .. "c|r" end
    if #parts == 0 then return "0" .. COPPER_COLOR .. "c|r" end
    return table.concat(parts, " ")
end

-- force=true resets the balance to now; without force only when never initialized.
local function initSession(force)
    local d = data()
    if not d then return end
    if d.sessionStart and not force then return end
    d.sessionStart = GetMoney() or 0
    d.lastMoney    = d.sessionStart
    d.gained       = 0
    d.spent        = 0
end

-- Resyncs lastMoney on login so offline delta (AH/mail/trade) is never counted as gained/spent.
local function syncOnLogin()
    local d = data()
    if not d then return end
    if not d.sessionStart then
        initSession(false)
    else
        d.lastMoney = GetMoney() or d.lastMoney or 0
    end
end

-- Account-wide store: db.global.charGold[realm][charName] = { money, class, faction }.
local function trackCharGold()
    if not (ns.db and ns.db.global) then return end
    local realm, name = GetRealmName(), UnitName("player")
    if not (realm and name) then return end
    ns.db.global.charGold = ns.db.global.charGold or {}
    ns.db.global.charGold[realm] = ns.db.global.charGold[realm] or {}
    ns.db.global.charGold[realm][name] = {
        money   = GetMoney() or 0,
        class   = select(2, UnitClass("player")),
        faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
    }
end

local function onMoney()
    local d = data()
    if not d then return end
    trackCharGold()
    if not d.sessionStart then
        initSession(false)
        return
    end
    local cur   = GetMoney() or 0
    local delta = cur - (d.lastMoney or cur)
    if delta > 0 then
        d.gained = (d.gained or 0) + delta
    elseif delta < 0 then
        d.spent  = (d.spent or 0) + (-delta)
    end
    d.lastMoney = cur
end

function mod.ResetSession()
    initSession(true)
    local d = data()
    if d then
        ns:Print(ns.C.accent .. L["Gold Tracker reset|r. Start = "] .. formatCopper(d.sessionStart))
    end
end

local function showTooltip(self)
    if not mod._enabled then return end
    local d = data()
    if not d then return end
    if not d.sessionStart then initSession(false) end

    if GameTooltip:GetOwner() ~= self then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    else
        GameTooltip:AddLine(" ")
    end

    GameTooltip:AddLine(ns.C.accent .. L["Gold Balance|r"])
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(POS_COLOR .. L["Gained:|r"], formatCopper(d.gained))
    GameTooltip:AddDoubleLine(NEG_COLOR .. L["Spent:|r"],  formatCopper(d.spent))

    local net   = (d.gained or 0) - (d.spent or 0)
    local color = net >= 0 and POS_COLOR or NEG_COLOR
    local sign  = net >= 0 and "+" or "-"
    GameTooltip:AddDoubleLine(L["|cffffffffNet:|r"],
        color .. sign .. " " .. formatCopper(net) .. "|r")

    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(GRAY .. L["Start:|r"], GRAY .. formatCopper(d.sessionStart or 0) .. "|r")
    GameTooltip:AddDoubleLine(GRAY .. L["Now:|r"],   GRAY .. formatCopper(d.lastMoney or 0)    .. "|r")
    GameTooltip:AddLine(GRAY .. L["Reset with /vcui goldreset|r"])

    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

function ns.ShowGoldTooltip(owner)
    local store0 = ns.db and ns.db.global and ns.db.global.charGold
    local realm0 = GetRealmName and GetRealmName()
    if not mod._enabled and not (store0 and realm0 and store0[realm0]) then return end
    if GameTooltip:GetOwner() ~= owner then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    end
    local coin = function(c)
        if GetCoinTextureString then return GetCoinTextureString(c or 0) end
        return formatCopper(c or 0)
    end
    local store = ns.db and ns.db.global and ns.db.global.charGold
    local realm = GetRealmName and GetRealmName()
    local myFaction = UnitFactionGroup and UnitFactionGroup("player") or nil
    if store and realm and store[realm] then
        local rows, total = {}, 0
        for name, info in pairs(store[realm]) do
            if not myFaction or (info.faction or myFaction) == myFaction then
                total = total + (info.money or 0)
                rows[#rows + 1] = { name = name, info = info }
            end
        end
        table.sort(rows, function(a, b) return a.name < b.name end)
        GameTooltip:AddDoubleLine(ns.C.accent .. L["Faction/Server Gold:|r"], coin(total))
        GameTooltip:AddLine(" ")
        for _, r in ipairs(rows) do
            local cls = r.info.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.info.class]
            local colored = r.name
            if cls then
                colored = string.format("|cff%02x%02x%02x%s|r",
                    math.floor((cls.r or 1) * 255 + 0.5), math.floor((cls.g or 1) * 255 + 0.5),
                    math.floor((cls.b or 1) * 255 + 0.5), r.name)
            end
            GameTooltip:AddDoubleLine(colored, coin(r.info.money))
        end
        GameTooltip:AddLine(" ")
        if IsShiftKeyDown and IsShiftKeyDown() then
            local acct = 0
            for _, chars in pairs(store) do
                for _, info in pairs(chars) do acct = acct + (info.money or 0) end
            end
            GameTooltip:AddDoubleLine(GRAY .. L["Account total:|r"], coin(acct))
        else
            GameTooltip:AddLine(GRAY .. L["<Hold Shift to show the account total>|r"])
        end
    end
    showTooltip(owner)
    GameTooltip:Show()
end

local function findMoneyFontString(frame, depth)
    if not frame or depth > 8 then return nil end
    local m = rawget(frame, "Money")
    if m and type(m) == "table" then
        local ok, t = pcall(function() return m.GetObjectType and m:GetObjectType() end)
        if ok and t == "FontString" then return m end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            local found = findMoneyFontString(child, depth + 1)
            if found then return found end
        end
    end
    return nil
end

local function hookOnce(frame, withLeave)
    if not frame or frame._vcui_moneyHooked then return false end
    frame._vcui_moneyHooked = true
    frame:HookScript("OnEnter", showTooltip)
    if withLeave then
        frame:HookScript("OnLeave", hideTooltip)
    end
    return true
end

-- Bag frames may not exist at load; retries every 3s until a money frame is found.
local retryCount = 0
local function tryHook()
    if hooked then return end
    local foundAny = false

    if _G.BaganatorCurrencyWidgetMixin and not mod._baganatorMixinHooked then
        mod._baganatorMixinHooked = true
        hooksecurefunc(_G.BaganatorCurrencyWidgetMixin, "OnLoad", function(widget)
            if widget.Money then hookOnce(widget.Money, false) end
        end)
        foundAny = true
    end

    for name, frame in pairs(_G) do
        if type(name) == "string" and name:find("^Baganator_") and type(frame) == "table" then
            local ok = pcall(function() return frame.GetObjectType end)
            if ok then
                local money = findMoneyFontString(frame, 0)
                if money and hookOnce(money, false) then
                    foundAny = true
                end
            end
        end
    end

    local defaultFrames = {
        "ContainerFrame1MoneyFrame",
        "BackpackTokenFrameMoneyFrame",
        "MainMenuBarBackpackMoneyFrame",
    }
    for _, name in ipairs(defaultFrames) do
        local f = _G[name]
        if f and f.HookScript and hookOnce(f, true) then
            foundAny = true
        end
    end

    if foundAny then
        hooked = true
        return
    end

    retryCount = retryCount + 1
    if retryCount < 20 and C_Timer and C_Timer.After then
        C_Timer.After(3, tryHook)
    end
end

function mod:OnEnable()
    -- Never initSession(true) here: it would wipe the persisted balance on every login.
    ns:RegisterEvent("PLAYER_LOGIN", syncOnLogin)
    ns:RegisterEvent("PLAYER_LOGIN", trackCharGold)
    ns:RegisterEvent("PLAYER_MONEY", onMoney)

    -- Enabled via toggle after PLAYER_LOGIN already fired.
    if ns.isInitialised then syncOnLogin(); trackCharGold() end

    tryHook()
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_LOGIN", syncOnLogin)
    ns:UnregisterEvent("PLAYER_LOGIN", trackCharGold)
    ns:UnregisterEvent("PLAYER_MONEY", onMoney)
    -- HookScript cannot be undone, so showTooltip() gates on mod._enabled instead.
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Gold Tracker"] },
        { type = "desc",
          text = L["|cffaaaaaaShows in the backpack gold tooltip the balance since the last manual reset:|n  - |cff44ff44Gained|r (quests, loot, vendor sales, mail)|n  - |cffff4444Spent|r (repair, vendor buy, mail cost)|n  - |cffffffffNet|r (+/- since reset)|n|nValues are |cffffffffper-char persistent|r across /reload and logout.|nOffline gold (AH mail, trade) is not counted.|n|nReset: button below or |cffffff00/vcui goldreset|r.|r"] },
        { type = "button", label = L["Reset session"], width = 200,
          onClick = function() mod.ResetSession() end },
    }
end

end)(...);

(function(...)
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("autoitembuy", {
    name        = "Auto Item Buy",
    group       = "QoL",
    description = "Automatically buys configured items at configured vendors. Shift when opening the merchant window = emergency stop.",
    defaults = {
        enabled    = false,
        autoClose  = true,
        chatMsg    = true,
        vendors    = {},     -- vendors[vendorName] = { [itemName] = true }
    },
})

local addVendorBuffer  = ""
local selectedVendor   = nil
local addItemBuffer    = ""

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
    if ns.UI and ns.UI.IsModuleActive and ns.UI:IsModuleActive("autoitembuy") then
        ns.UI:BuildOptionsPage("autoitembuy", "default")
    end
end

local eventFrame

local function setupEvents()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("MERCHANT_SHOW")
    eventFrame:SetScript("OnEvent", function(self, event)
        if event ~= "MERCHANT_SHOW" then return end
        if not mod._enabled then return end

        -- Shift held while the merchant opens = emergency stop for this visit.
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

function mod:OnEnable()
    setupEvents()
end

function mod:GetOptions()
    local items = {}

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

    table.insert(items, { type = "header", text = L["Manage Vendors"] })

    local vendorList = getVendorList()
    if #vendorList == 0 then
        table.insert(items, { type = "desc",
            text = L["|cffaaaaaaNo vendors added yet. Add a vendor above, then select it here to configure items.|r"] })
    else
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

end)(...);
