-- =========================================================
-- VuloClassicUI / Modules / AutoItemBuy
-- Kauft automatisch bestimmte Items bei bestimmten Händlern.
-- Shift halten beim Öffnen des Händlerfensters = Not-Aus.
--
-- Konfigurierbar im UI: Händler-Namen und Item-Namen.
-- Default: aus.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("autoitembuy", {
    name        = "Auto Item Buy",
    group       = "QoL",
    description = "Kauft automatisch festgelegte Items bei festgelegten Händlern. Shift beim Öffnen des Händlerfensters = Not-Aus.",
    defaults = {
        enabled    = false,  -- standardmäßig AUS
        autoClose  = true,   -- Händlerfenster nach Kauf schließen
        chatMsg    = true,   -- Print bei jedem Kauf
        vendors    = {},     -- vendors[händlerName] = { itemName1 = true, itemName2 = true, ... }
    },
})

-- =========================================================
-- Buffer für UI-Eingaben (nicht in der DB)
-- =========================================================
local addVendorBuffer  = ""
local selectedVendor   = nil  -- aktuell ausgewählter Händler in der UI
local addItemBuffer    = ""

-- =========================================================
-- Helper
-- =========================================================
local function p(fmt, ...)
    if not mod.db.chatMsg then return end
    ns:Print("|cffffd200[AutoItemBuy]|r " .. string.format(fmt, ...))
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
-- Event-Handling (MERCHANT_SHOW)
-- =========================================================
local eventFrame

local function setupEvents()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("MERCHANT_SHOW")
    eventFrame:SetScript("OnEvent", function(self, event)
        if event ~= "MERCHANT_SHOW" then return end
        if not mod._enabled then return end

        -- SHIFT halten = Not-Aus
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
                p("Kaufe: " .. name)
                pcall(function() BuyMerchantItem(i, 1) end)
                bought = bought + 1
            end
        end

        -- Optional: Händlerfenster automatisch schließen
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
-- Options-Page
-- =========================================================
function mod:GetOptions()
    local items = {}

    -- =========================================================
    -- Allgemeine Settings
    -- =========================================================
    table.insert(items, { type = "header", text = "Allgemein" })

    table.insert(items, {
        type = "toggle", label = "Händlerfenster nach Kauf schließen",
        tooltip = "Schließt das Händlerfenster automatisch ~0.2s nach dem Kauf.",
        get = function() return mod.db.autoClose end,
        set = function(_, v) mod.db.autoClose = v end,
    })

    table.insert(items, {
        type = "toggle", label = "Chat-Nachricht bei jedem Kauf",
        get = function() return mod.db.chatMsg end,
        set = function(_, v) mod.db.chatMsg = v end,
    })

    table.insert(items, { type = "desc",
        text = "|cffaaaaaaTipp: Halte SHIFT beim Öffnen des Händlerfensters, um automatischen Kauf einmalig zu überspringen.|r" })

    table.insert(items, { type = "spacer", height = 12 })

    -- =========================================================
    -- Händler hinzufügen
    -- =========================================================
    table.insert(items, { type = "header", text = "Händler hinzufügen" })

    table.insert(items, {
        type = "group", layout = "row", gap = 6,
        items = {
            {
                type = "editbox", label = "Händler-Name",
                width = 260,
                get = function() return addVendorBuffer end,
                set = function(_, v) addVendorBuffer = v end,
            },
            {
                type = "button", label = "Hinzufügen", width = 100,
                onClick = function()
                    local name = (addVendorBuffer or ""):match("^%s*(.-)%s*$")
                    if not name or name == "" then
                        ns:Print("|cffff5555Bitte einen Händler-Namen eingeben.|r")
                        return
                    end
                    mod.db.vendors = mod.db.vendors or {}
                    if mod.db.vendors[name] then
                        ns:Print("|cffff5555Händler '%s' existiert bereits.|r", name)
                        return
                    end
                    mod.db.vendors[name] = {}
                    selectedVendor = name
                    addVendorBuffer = ""
                    ns:Print("Händler '%s' hinzugefügt.", name)
                    refreshUI()
                end,
            },
        },
    })

    table.insert(items, { type = "spacer", height = 12 })

    -- =========================================================
    -- Händler-Auswahl & Verwaltung
    -- =========================================================
    table.insert(items, { type = "header", text = "Händler verwalten" })

    local vendorList = getVendorList()
    if #vendorList == 0 then
        table.insert(items, { type = "desc",
            text = "|cffaaaaaaNoch keine Händler hinzugefügt. Füge oben einen Händler hinzu, dann wähle ihn hier aus, um Items zu konfigurieren.|r" })
    else
        -- Auto-select wenn noch keiner gewählt
        if not selectedVendor or not mod.db.vendors[selectedVendor] then
            selectedVendor = vendorList[1]
        end

        local vendorValues = {}
        for _, v in ipairs(vendorList) do
            table.insert(vendorValues, { value = v, text = v })
        end

        table.insert(items, {
            type = "dropdown", label = "Aktuell ausgewählter Händler",
            width = 280,
            values = vendorValues,
            get = function() return selectedVendor end,
            set = function(_, v)
                selectedVendor = v
                refreshUI()
            end,
        })

        table.insert(items, {
            type = "button", label = "Diesen Händler löschen", width = 180,
            onClick = function()
                if not selectedVendor then return end
                local name = selectedVendor
                mod.db.vendors[name] = nil
                ns:Print("Händler '%s' entfernt.", name)
                selectedVendor = nil
                refreshUI()
            end,
        })

        table.insert(items, { type = "spacer", height = 12 })

        -- =========================================================
        -- Items für ausgewählten Händler
        -- =========================================================
        table.insert(items, { type = "header",
            text = string.format("Items bei '%s'", selectedVendor) })

        table.insert(items, {
            type = "group", layout = "row", gap = 6,
            items = {
                {
                    type = "editbox", label = "Item-Name (exakt wie im Spiel)",
                    width = 260,
                    get = function() return addItemBuffer end,
                    set = function(_, v) addItemBuffer = v end,
                },
                {
                    type = "button", label = "Hinzufügen", width = 100,
                    onClick = function()
                        local name = (addItemBuffer or ""):match("^%s*(.-)%s*$")
                        if not name or name == "" then
                            ns:Print("|cffff5555Bitte einen Item-Namen eingeben.|r")
                            return
                        end
                        if not selectedVendor or not mod.db.vendors[selectedVendor] then return end
                        mod.db.vendors[selectedVendor][name] = true
                        addItemBuffer = ""
                        ns:Print("Item '%s' bei Händler '%s' hinzugefügt.", name, selectedVendor)
                        refreshUI()
                    end,
                },
            },
        })

        table.insert(items, { type = "desc",
            text = "|cffaaaaaaItem-Namen müssen exakt mit dem In-Game-Namen übereinstimmen (inkl. Groß-/Kleinschreibung und Sonderzeichen).|r" })

        local itemList = getVendorItems(selectedVendor)
        if #itemList == 0 then
            table.insert(items, { type = "desc",
                text = "|cffaaaaaaKeine Items konfiguriert. Füge oben Items hinzu, die bei diesem Händler automatisch gekauft werden sollen.|r" })
        else
            for _, itemName in ipairs(itemList) do
                table.insert(items, {
                    type = "group", layout = "row", gap = 6,
                    items = {
                        { type = "desc", text = "• " .. itemName, width = 340 },
                        {
                            type = "button", label = "Entfernen", width = 90,
                            onClick = function()
                                if not selectedVendor or not mod.db.vendors[selectedVendor] then return end
                                mod.db.vendors[selectedVendor][itemName] = nil
                                ns:Print("Item '%s' entfernt.", itemName)
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
