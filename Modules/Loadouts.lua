-- =========================================================
-- VuloClassicUI / Modules / Loadouts
-- ItemRack-style equipment set manager.
-- Save current gear as a named "loadout" and quickly swap between sets.
--
-- Equipping in Anniversary is restricted (AutoEquipCursorItem is protected),
-- so we use UseContainerItem(bag, slot) which acts as a normal "use" on
-- equipable items → swap works out-of-combat for items located in bags.
--
-- Slash: /loadout (or /lo) save <name> | equip <name> | delete <name> | list
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("loadouts", {
    name        = L["Loadouts"],
    group       = "QoL",
    description = L["Save and quickly equip gear sets for different specs, content, or roles."],
    defaults = {
        enabled       = true,
        loadouts      = {},   -- { [name] = { slots = { [slotID] = itemLink, ... }, createdAt = epoch, formIdx = nil } }
        confirmDelete = true,
        -- Minimap button
        minimap = { hidden = false, angle = -45 },
        -- Auto-switch on stance/form change: [formIndex] = "loadoutName"
        autoSwitchEnabled = true,
        formMapping       = {},
    },
})

-- =========================================================
-- API compat (Anniversary uses C_Container namespace)
-- =========================================================
local GetContainerItemID    = (C_Container and C_Container.GetContainerItemID)    or _G.GetContainerItemID
local GetContainerNumSlots  = (C_Container and C_Container.GetContainerNumSlots)  or _G.GetContainerNumSlots
local UseContainerItem      = (C_Container and C_Container.UseContainerItem)      or _G.UseContainerItem

-- Equipment slots we capture (skip shirt=4 and tabard=19)
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- Slot display names (for UI / pickers)
local SLOT_NAMES = {
    [1]  = L["Head"],    [2]  = L["Neck"],     [3]  = L["Shoulder"],
    [5]  = L["Chest"],   [6]  = L["Waist"],    [7]  = L["Legs"],
    [8]  = L["Feet"],    [9]  = L["Wrist"],    [10] = L["Hands"],
    [11] = L["Finger 1"], [12] = L["Finger 2"],
    [13] = L["Trinket 1"], [14] = L["Trinket 2"],
    [15] = L["Back"],
    [16] = L["Main Hand"], [17] = L["Off Hand"], [18] = L["Ranged"],
}

-- Pre-defined slot groups for quick-save
local SLOT_GROUPS = {
    all      = EQUIP_SLOTS,
    trinkets = { 13, 14 },
    weapons  = { 16, 17, 18 },
    rings    = { 11, 12 },
    armor    = { 1, 3, 5, 6, 7, 8, 9, 10, 15 },
}

-- =========================================================
-- Helpers
-- =========================================================
local function getItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function captureCurrentEquipment(slotList)
    slotList = slotList or EQUIP_SLOTS
    local set = {}
    for _, slot in ipairs(slotList) do
        local link = GetInventoryItemLink("player", slot)
        if link then set[slot] = link end
    end
    return set
end

local function findItemInBags(targetItemID)
    if not GetContainerItemID or not GetContainerNumSlots then return nil end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            if GetContainerItemID(bag, slot) == targetItemID then
                return bag, slot
            end
        end
    end
    return nil
end

local function countSlots(loadout)
    local n = 0
    if loadout and loadout.slots then
        for _ in pairs(loadout.slots) do n = n + 1 end
    end
    return n
end

local function sortedLoadoutNames()
    local names = {}
    if mod.db and mod.db.loadouts then
        for name in pairs(mod.db.loadouts) do
            table.insert(names, name)
        end
        table.sort(names)
    end
    return names
end

-- =========================================================
-- Core operations
-- =========================================================
local function saveAs(name, slotList)
    if not name or name == "" then
        ns:Print(L["Please provide a name for the loadout."])
        return
    end
    mod.db.loadouts[name] = {
        slots     = captureCurrentEquipment(slotList),
        createdAt = time(),
    }
    ns:Print(string.format(L["Loadout '%s' saved (%d items)."],
        name, countSlots(mod.db.loadouts[name])))
end

-- Pending slot list for the StaticPopup (popups have no parameter passing on Show)
local _pendingSaveSlots = nil

local function promptSaveWithSlots(slotList)
    _pendingSaveSlots = slotList
    StaticPopup_Show("VCUI_LOADOUT_SAVE")
end

local function deleteLoadout(name)
    if not mod.db.loadouts[name] then
        ns:Print(string.format(L["Loadout '%s' does not exist."], name))
        return
    end
    mod.db.loadouts[name] = nil
    ns:Print(string.format(L["Loadout '%s' deleted."], name))
end

local function equipLoadout(name)
    if InCombatLockdown() then
        ns:Print(L["Cannot change equipment in combat."])
        return
    end
    local loadout = mod.db.loadouts[name]
    if not loadout then
        ns:Print(string.format(L["Loadout '%s' does not exist."], name))
        return
    end
    if not UseContainerItem then
        ns:Print(L["Equipment swap API not available on this client."])
        return
    end

    local swapped, missing = 0, 0
    for slot, link in pairs(loadout.slots) do
        local currentLink = GetInventoryItemLink("player", slot)
        if currentLink ~= link then
            local itemID = getItemIDFromLink(link)
            if itemID then
                local bag, bagSlot = findItemInBags(itemID)
                if bag and bagSlot then
                    pcall(UseContainerItem, bag, bagSlot)
                    swapped = swapped + 1
                else
                    missing = missing + 1
                end
            end
        end
    end

    if swapped > 0 then
        if missing > 0 then
            ns:Print(string.format(L["Loadout '%s' equipped (%d swapped, %d missing from bags)."],
                name, swapped, missing))
        else
            ns:Print(string.format(L["Loadout '%s' equipped (%d items swapped)."], name, swapped))
        end
    elseif missing > 0 then
        ns:Print(string.format(L["Loadout '%s': %d items missing from bags, nothing swapped."],
            name, missing))
    else
        ns:Print(string.format(L["Loadout '%s' already equipped."], name))
    end
end

local function listLoadouts()
    local names = sortedLoadoutNames()
    if #names == 0 then
        ns:Print(L["No loadouts saved yet."])
        return
    end
    ns:Print(L["Saved loadouts:"])
    for _, name in ipairs(names) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  |cffffd100%s|r (%d %s)",
            name, countSlots(mod.db.loadouts[name]), L["items"]))
    end
end

-- =========================================================
-- StaticPopups
-- =========================================================
StaticPopupDialogs["VCUI_LOADOUT_SAVE"] = {
    text = L["Save current equipment as a new loadout. Enter name:"],
    button1 = SAVE or L["Save"],
    button2 = CANCEL or L["Cancel"],
    hasEditBox = true,
    maxLetters = 32,
    OnAccept = function(self)
        saveAs(self.editBox:GetText(), _pendingSaveSlots)
        _pendingSaveSlots = nil
    end,
    EditBoxOnEnterPressed = function(self)
        saveAs(self:GetText(), _pendingSaveSlots)
        _pendingSaveSlots = nil
        self:GetParent():Hide()
    end,
    OnCancel = function() _pendingSaveSlots = nil end,
    EditBoxOnEscapePressed = function(self)
        _pendingSaveSlots = nil
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["VCUI_LOADOUT_DELETE"] = {
    text = L["Delete loadout '%s'?"],
    button1 = YES or L["Yes"],
    button2 = NO  or L["No"],
    OnAccept = function(_, data) deleteLoadout(data) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- =========================================================
-- Slash commands
-- =========================================================
_G.SLASH_VCUILOADOUT1 = "/loadout"
_G.SLASH_VCUILOADOUT2 = "/lo"
_G.SlashCmdList["VCUILOADOUT"] = function(msg)
    msg = msg or ""
    local cmd, arg = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "save" then
        saveAs(arg)
    elseif cmd == "equip" or cmd == "" then
        if arg ~= "" then
            equipLoadout(arg)
        else
            ns:Print(L["Usage: /loadout equip <name> | save <name> | delete <name> | list"])
        end
    elseif cmd == "delete" or cmd == "del" or cmd == "remove" or cmd == "rm" then
        if arg == "" then
            ns:Print(L["Usage: /loadout delete <name>"])
        elseif mod.db.confirmDelete then
            local dlg = StaticPopup_Show("VCUI_LOADOUT_DELETE", arg)
            if dlg then dlg.data = arg end
        else
            deleteLoadout(arg)
        end
    elseif cmd == "list" or cmd == "ls" then
        listLoadouts()
    else
        -- Treat unknown first word as a loadout name to equip
        if mod.db.loadouts[msg] then
            equipLoadout(msg)
        else
            ns:Print(L["Usage: /loadout equip <name> | save <name> | delete <name> | list"])
        end
    end
end

-- =========================================================
-- Minimap button
-- =========================================================
local mmBtn

local function updateMinimapPos()
    if not mmBtn then return end
    local angle = (mod.db.minimap and mod.db.minimap.angle) or -45
    local rad = math.rad(angle)
    local r = 80  -- distance from minimap center
    local x = r * math.cos(rad)
    local y = r * math.sin(rad)
    mmBtn:ClearAllPoints()
    mmBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Loadouts dropdown — uses ns:ShowPopupMenu (shared helper, EasyMenu replacement)
local function showLoadoutMenu(anchor)
    local entries = {
        { title = true, text = L["Loadouts"] },
    }

    local names = sortedLoadoutNames()
    if #names == 0 then
        table.insert(entries, { text = "  " .. L["No loadouts saved yet."], disabled = true })
    else
        for _, name in ipairs(names) do
            local capturedName = name
            table.insert(entries, {
                text = "  " .. name,
                func = function() equipLoadout(capturedName) end,
            })
        end
    end

    table.insert(entries, { separator = true })
    table.insert(entries, { text = L["Save current as new..."], func = function() promptSaveWithSlots(nil) end })
    table.insert(entries, { text = L["Save trinkets only..."],  func = function() promptSaveWithSlots(SLOT_GROUPS.trinkets) end })
    table.insert(entries, { text = L["Save weapons only..."],   func = function() promptSaveWithSlots(SLOT_GROUPS.weapons)  end })
    table.insert(entries, { separator = true })
    table.insert(entries, { text = L["Settings..."],
        func = function() if ns.OpenConfig then ns:OpenConfig("loadouts") end end })

    ns:ShowPopupMenu(entries, anchor)
end

local function createMinimapButton()
    if mmBtn then return end
    if not Minimap then return end

    mmBtn = CreateFrame("Button", "VCUI_LoadoutsMinimapButton", Minimap)
    mmBtn:SetSize(31, 31)
    mmBtn:SetFrameStrata("MEDIUM")
    mmBtn:SetFrameLevel(8)

    -- Icon (equipment armor icon) — circular crop for round-button look
    local icon = mmBtn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Chest_Plate06")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", mmBtn, "CENTER", 0, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- crop default border

    -- Round border (Blizzard minimap-tracking style)
    -- Standard LibDBIcon-style offset: TOPLEFT, 54x54, anchor (-11, 12) for proper centering
    local border = mmBtn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", mmBtn, "TOPLEFT", -11, 12)

    mmBtn:SetMovable(true)
    mmBtn:RegisterForClicks("AnyUp")
    mmBtn:RegisterForDrag("LeftButton")

    -- Drag to reposition around minimap (saved as angle)
    mmBtn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local sx, sy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale() or 1
            sx, sy = sx / scale, sy / scale
            local angle = math.deg(math.atan2(sy - my, sx - mx))
            mod.db.minimap = mod.db.minimap or {}
            mod.db.minimap.angle = angle
            updateMinimapPos()
        end)
    end)
    mmBtn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    mmBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            showLoadoutMenu(self)
        elseif button == "RightButton" then
            if ns.OpenConfig then ns:OpenConfig("loadouts") end
        end
    end)

    mmBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff9b6cffLoadouts|r")
        GameTooltip:AddLine(L["Left-click: switch set"], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: settings"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag: reposition"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updateMinimapPos()

    if mod.db.minimap and mod.db.minimap.hidden then
        mmBtn:Hide()
    end
end

local function applyMinimapVisibility()
    if not mmBtn then return end
    if mod.db.minimap and mod.db.minimap.hidden then
        mmBtn:Hide()
    else
        mmBtn:Show()
    end
end

-- =========================================================
-- Stance/Form auto-switching
-- =========================================================
local _lastForm = -1

local function getCurrentForm()
    if not GetShapeshiftForm then return 0 end
    return GetShapeshiftForm() or 0
end

local function getFormName(formIdx)
    if formIdx == 0 then return L["No Form"] end
    if GetShapeshiftFormInfo then
        local _, name = pcall(GetShapeshiftFormInfo, formIdx)
        if type(name) == "string" and name ~= "" then return name end
    end
    return string.format(L["Form %d"], formIdx)
end

local function onShapeshiftChange()
    if not mod._enabled or not mod.db then return end
    if not mod.db.autoSwitchEnabled then return end
    if InCombatLockdown() then return end

    local currentForm = getCurrentForm()
    if currentForm == _lastForm then return end
    _lastForm = currentForm

    -- formMapping is keyed by loadout name → form index (1:1).
    -- Reverse-look up to find which loadout is bound to the current form.
    if not mod.db.formMapping then return end
    for loadoutName, formIdx in pairs(mod.db.formMapping) do
        if formIdx == currentForm and mod.db.loadouts[loadoutName] then
            equipLoadout(loadoutName)
            return
        end
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    if not mod.db then return end
    -- Defensive: ensure tables exist even if profile is fresh
    mod.db.loadouts    = mod.db.loadouts    or {}
    mod.db.formMapping = mod.db.formMapping or {}
    mod.db.minimap     = mod.db.minimap     or { hidden = false, angle = -45 }

    -- Create minimap button (deferred so Minimap definitely exists)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, createMinimapButton)
    else
        createMinimapButton()
    end

    -- Hook stance/form events
    ns:RegisterEvent("UPDATE_SHAPESHIFT_FORM",  onShapeshiftChange)
    ns:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", onShapeshiftChange)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",    onShapeshiftChange)  -- retry leaving combat

    _lastForm = getCurrentForm()
end

function mod:OnDisable()
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORM",  onShapeshiftChange)
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS", onShapeshiftChange)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",    onShapeshiftChange)
    if mmBtn then mmBtn:Hide() end
end

-- =========================================================
-- Options UI
-- =========================================================
-- Build a list of available form indices for dropdown values
local function buildFormDropdownValues()
    local values = { { value = 0, text = L["None"] } }
    -- Add all known shapeshift forms (max 6 in Anniversary classes)
    local numForms = (GetNumShapeshiftForms and GetNumShapeshiftForms()) or 0
    for i = 1, numForms do
        table.insert(values, { value = i, text = getFormName(i) })
    end
    return values
end

function mod:GetOptions()
    local items = {
        { type = "header", text = L["Loadouts"] },
        { type = "desc", text = L["Save your current equipment as named gear sets and quickly switch between them. Equipping requires you to be out of combat — items in your bags are auto-equipped via Use."] },

        { type = "spacer", height = 6 },
        { type = "group", layout = "row", gap = 6,
          items = {
              { type = "button", label = L["Save All..."], width = 130,
                onClick = function() promptSaveWithSlots(nil) end },
              { type = "button", label = L["Save Trinkets..."], width = 130,
                onClick = function() promptSaveWithSlots(SLOT_GROUPS.trinkets) end },
              { type = "button", label = L["Save Weapons..."], width = 130,
                onClick = function() promptSaveWithSlots(SLOT_GROUPS.weapons) end },
          },
        },
        { type = "toggle", label = L["Confirm before deleting a loadout"],
          get = function() return mod.db.confirmDelete ~= false end,
          set = function(_, v) mod.db.confirmDelete = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Minimap Button"] },
        { type = "toggle", label = L["Show minimap button"],
          tooltip = L["Left-click for a quick set-switcher menu, right-click to open settings, drag to reposition."],
          get = function() return not (mod.db.minimap and mod.db.minimap.hidden) end,
          set = function(_, v)
              mod.db.minimap = mod.db.minimap or {}
              mod.db.minimap.hidden = not v
              applyMinimapVisibility()
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Auto-Switch on Stance/Form"] },
        { type = "toggle", label = L["Enable auto-switching"],
          tooltip = L["Automatically equips a loadout when your stance/form changes (warrior stances, druid forms). Out-of-combat only — if a stance change happens in combat, the swap is deferred until combat ends."],
          get = function() return mod.db.autoSwitchEnabled ~= false end,
          set = function(_, v) mod.db.autoSwitchEnabled = v end },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Saved Loadouts"] },
    }

    local names = sortedLoadoutNames()
    if #names == 0 then
        table.insert(items, { type = "desc", text = L["|cffaaaaaaNo loadouts saved yet. Use the button above to save your current gear.|r"] })
    else
        local formValues = buildFormDropdownValues()
        local hasForms = #formValues > 1  -- 1 = only "None" → no stance class

        for _, name in ipairs(names) do
            local capturedName = name  -- closure capture
            local slotCount = countSlots(mod.db.loadouts[name])
            -- Row 1: name + Equip/Overwrite/Delete
            table.insert(items, { type = "group", layout = "row", gap = 6,
                items = {
                    { type = "desc", text = string.format("|cffffd100%s|r |cff888888(%d %s)|r",
                        name, slotCount, L["items"]) },
                    { type = "button", label = L["Equip"], width = 80,
                      onClick = function() equipLoadout(capturedName) end },
                    { type = "button", label = L["Overwrite"], width = 100,
                      onClick = function()
                          -- Preserve the original slot mask when overwriting
                          local oldSlots = mod.db.loadouts[capturedName].slots or {}
                          local slotList = {}
                          for s in pairs(oldSlots) do table.insert(slotList, s) end
                          mod.db.loadouts[capturedName] = {
                              slots     = captureCurrentEquipment(#slotList > 0 and slotList or nil),
                              createdAt = time(),
                          }
                          ns:Print(string.format(L["Loadout '%s' updated with current gear."], capturedName))
                      end },
                    { type = "button", label = L["Delete"], width = 80,
                      onClick = function()
                          if mod.db.confirmDelete then
                              local dlg = StaticPopup_Show("VCUI_LOADOUT_DELETE", capturedName)
                              if dlg then dlg.data = capturedName end
                          else
                              deleteLoadout(capturedName)
                          end
                      end },
                },
            })

            -- Row 2: Auto-equip on form dropdown (only show if class has forms)
            if hasForms then
                table.insert(items, { type = "dropdown",
                    label = L["Auto-equip on form"],
                    tooltip = L["Equip this loadout automatically when the chosen stance/form is activated."],
                    values = formValues,
                    get = function() return (mod.db.formMapping and mod.db.formMapping[capturedName]) or 0 end,
                    set = function(_, v)
                        mod.db.formMapping = mod.db.formMapping or {}
                        -- Clear any other loadout currently mapped to this form (1:1 mapping)
                        if v and v ~= 0 then
                            for other, formIdx in pairs(mod.db.formMapping) do
                                if formIdx == v and other ~= capturedName then
                                    mod.db.formMapping[other] = nil
                                end
                            end
                        end
                        mod.db.formMapping[capturedName] = (v ~= 0) and v or nil
                    end,
                })
            end
        end
    end

    table.insert(items, { type = "spacer", height = 8 })
    table.insert(items, { type = "desc", text = L["|cffaaaaaaSlash commands: /loadout save <name>, /loadout equip <name>, /loadout delete <name>, /loadout list. Short alias: /lo|r"] })

    return items
end
