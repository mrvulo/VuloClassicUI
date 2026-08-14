-- VuloClassicUI / Modules / ActionRingOptions: the settings page of the action
-- ring. Same split as the nameplates: the runtime half (ActionRing.lua) is the
-- taint-sensitive one and never needs to change when this page does. Reads its
-- shared pieces off mod.optionsBridge; loads after ActionRing.lua per the TOC.
local _, ns = ...
local L   = ns.L
local mod = ns.modules.actionring

local br = mod.optionsBridge
local MAX_MENUS      = br.MAX_MENUS
local MAX_SLOTS      = br.MAX_SLOTS
local BINDING_PREFIX = br.BINDING_PREFIX

-- Which ring the setup section below edits. Page state, not a setting.
local selectedMenu = 1

local function clampSelection()
    if selectedMenu > br.menuCount() then selectedMenu = br.menuCount() end
    if selectedMenu < 1 then selectedMenu = 1 end
end

local function refreshPage()
    if ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
end

-------------------------------------------------------------------------------
--  Key capture -- one overlay shared by the ring keybind and the two db keys.
-------------------------------------------------------------------------------

local IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, UNKNOWN = true, LMETA = true, RMETA = true,
}
local MOUSE_TOKENS = {
    RightButton = "BUTTON2", MiddleButton = "BUTTON3",
    Button4 = "BUTTON4", Button5 = "BUTTON5",
}

local captureFrame

-- onKey(combo) gets the finished combination ("ALT-F5"); onKey(nil) is a
-- cancelled capture. ESCAPE cancels; a plain left-click cancels too, so the
-- overlay can never trap the mouse.
local function startCapture(onKey)
    if not captureFrame then
        captureFrame = CreateFrame("Frame", nil, UIParent)
        captureFrame:SetAllPoints(UIParent)
        captureFrame:SetFrameStrata("TOOLTIP")
        captureFrame:EnableMouse(true)
        captureFrame:EnableKeyboard(true)
        captureFrame.hint = captureFrame:CreateFontString(nil, "OVERLAY")
        ns.UI.Font(captureFrame.hint, 14, "OUTLINE")
        captureFrame.hint:SetPoint("CENTER", 0, 120)
        local bg = captureFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.35)
    end
    captureFrame.hint:SetText(L["Press a key... (ESC to cancel)"])

    local function finish(combo)
        captureFrame:Hide()
        captureFrame:SetScript("OnKeyDown", nil)
        captureFrame:SetScript("OnMouseDown", nil)
        if combo then onKey(combo) end
    end
    local function withModifiers(key)
        local combo = key
        if IsShiftKeyDown()   then combo = "SHIFT-" .. combo end
        if IsControlKeyDown() then combo = "CTRL-" .. combo end
        if IsAltKeyDown()     then combo = "ALT-" .. combo end
        return combo
    end
    captureFrame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then finish(nil) return end
        if IGNORED_KEYS[key] then return end
        finish(withModifiers(key))
    end)
    captureFrame:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then finish(nil) return end
        local token = MOUSE_TOKENS[btn]
        if token then finish(withModifiers(token)) end
    end)
    captureFrame:Show()
end

-- Bind `combo` to ring `index`'s binding action, replacing whatever held the
-- key -- said out loud, never silently. Bindings are per character or per
-- account, whichever set the player runs; SaveBindings keeps the client's own.
local function bindRingKey(index, combo)
    -- SetBinding silently fails during combat lockdown; saying so beats a
    -- no-op announced as done.
    if InCombatLockdown() then
        ns:Print(L["Not in combat - keybinds can't be changed while fighting."])
        return
    end
    local action = BINDING_PREFIX .. index
    local old = GetBindingAction(combo)
    if old and old ~= "" and old ~= action then
        local label = _G["BINDING_NAME_" .. old] or old
        ns:Print(L["Key %s was bound to '%s' - now opens %s."], combo, label, br.menuName(index))
    end
    -- One key per ring keeps the page honest: drop the old key first.
    local k1, k2 = GetBindingKey(action)
    if k1 then SetBinding(k1) end
    if k2 then SetBinding(k2) end
    SetBinding(combo, action)
    if SaveBindings then
        SaveBindings((GetCurrentBindingSet and GetCurrentBindingSet()) or 2)
    end
    br.updateBindings()
    refreshPage()
end

local function unbindRingKey(index)
    if InCombatLockdown() then
        ns:Print(L["Not in combat - keybinds can't be changed while fighting."])
        return
    end
    local k1, k2 = GetBindingKey(BINDING_PREFIX .. index)
    if k1 then SetBinding(k1) end
    if k2 then SetBinding(k2) end
    if SaveBindings then
        SaveBindings((GetCurrentBindingSet and GetCurrentBindingSet()) or 2)
    end
    br.updateBindings()
    refreshPage()
end

local function ringKeyText(index)
    local k1 = GetBindingKey(BINDING_PREFIX .. index)
    return k1 or L["Not bound"]
end

-------------------------------------------------------------------------------
--  Ring templates -- classic-portable presets, offered when adding a ring.
--  Each builder returns a fresh slots array holding what THIS character has
--  right now; a preset that builds empty is not offered.
-------------------------------------------------------------------------------

local GetNumSlotsFn = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetItemIDFn   = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID

local function markerSlots()
    local out = {}
    for i = 1, 8 do out[#out + 1] = { kind = "raidtarget", id = i } end
    out[#out + 1] = { kind = "raidtarget", id = 0 }
    out[#out + 1] = { kind = "clearmarkers" }
    out[#out + 1] = { kind = "cycleraidtarget" }
    return out
end

local function hearthstoneSlots()
    if (GetItemCount(6948) or 0) > 0 then
        return { { kind = "item", id = 6948 } }
    end
    return {}
end

-- Fixed TBC ids filtered by what the character knows; a spell nobody has
-- simply does not appear. Rank chains keep their base rank known, so base
-- ids are the durable handle.
local TELEPORT_SPELLS = {
    3561, 3562, 3563, 3565, 3566, 3567, 32271, 32272, 33690, 35715,   -- Teleport
    10059, 11416, 11418, 11417, 11419, 11420, 32266, 32267, 33691, 35717, -- Portal
}
local function teleportSlots()
    local out = {}
    for _, id in ipairs(TELEPORT_SPELLS) do
        if IsPlayerSpell and IsPlayerSpell(id) and #out < MAX_SLOTS then
            out[#out + 1] = { kind = "spell", id = id }
        end
    end
    return out
end

-- Usable consumables in the bags (potions, elixirs, food with effects).
local function potionSlots()
    local out, seen = {}, {}
    for bag = 0, 4 do
        for s = 1, GetNumSlotsFn(bag) or 0 do
            local id = GetItemIDFn(bag, s)
            if id and not seen[id] and #out < MAX_SLOTS and GetItemSpell(id) then
                local classID = select(6, GetItemInfoInstant(id))
                if classID == 0 then
                    seen[id] = true
                    out[#out + 1] = { kind = "item", id = id }
                end
            end
        end
    end
    return out
end

local FORM_SPELLS = {
    5487,   -- Bear Form
    9634,   -- Dire Bear Form
    768,    -- Cat Form
    5215,   -- Prowl
    783,    -- Travel Form
    1066,   -- Aquatic Form
    33943,  -- Flight Form
    40120,  -- Swift Flight Form
    24858,  -- Moonkin Form
    33891,  -- Tree of Life
}
local function formSlots()
    local out = {}
    for _, id in ipairs(FORM_SPELLS) do
        if IsPlayerSpell and IsPlayerSpell(id) and #out < MAX_SLOTS then
            out[#out + 1] = { kind = "spell", id = id }
        end
    end
    -- Getting OUT is the half no form spell covers; /cancelform is the whole
    -- of it. Only offered once a form has been found.
    if #out > 0 and #out < MAX_SLOTS then
        out[#out + 1] = { kind = "macrotext", text = "/cancelform",
                          name = L["Cancel form"],
                          icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" }
    end
    return out
end

local STANCE_SPELLS = {
    WARRIOR = { 2457, 71, 2458 },   -- Battle, Defensive, Berserker
    PALADIN = { 465, 7294, 19746, 19876, 19888, 19891, 20218, 32223 },  -- the auras
}
local function stanceSlots()
    local out = {}
    for _, id in ipairs(STANCE_SPELLS[select(2, UnitClass("player"))] or {}) do
        if IsPlayerSpell and IsPlayerSpell(id) and #out < MAX_SLOTS then
            out[#out + 1] = { kind = "spell", id = id }
        end
    end
    return out
end

-- Quest items being carried that DO something: an item with no use effect is
-- a quest object, not something an entry can fire.
local function questItemSlots()
    local out, seen = {}, {}
    for bag = 0, 4 do
        for s = 1, GetNumSlotsFn(bag) or 0 do
            local id = GetItemIDFn(bag, s)
            if id and not seen[id] and #out < MAX_SLOTS and GetItemSpell(id) then
                local classID = select(6, GetItemInfoInstant(id))
                if classID == 12 then
                    seen[id] = true
                    out[#out + 1] = { kind = "item", id = id }
                end
            end
        end
    end
    return out
end

local RING_PRESETS = {
    { label = "Target markers", build = markerSlots },
    { label = "Hearthstone",    build = hearthstoneSlots },
    { label = "Teleports",      build = teleportSlots },
    { label = "Potions",        build = potionSlots },
    { label = "Druid forms",    build = formSlots },
    { label = "Stances and auras", build = stanceSlots },
    { label = "Quest items",    build = questItemSlots },
}

-------------------------------------------------------------------------------
--  Entry picker -- one dialog, several sources, click a row to add it.
--  The same dialog doubles as the "empty or template" chooser for a new ring.
-------------------------------------------------------------------------------

local picker
local pickerKind = "spell"
local pickerMode = "entries"   -- "entries" | "newring"
-- Wide enough for the longest tab row across the nine languages.
local PICKER_W, PICKER_H, PROW_H = 380, 420, 26

local refreshPicker

local function addSlot(slot)
    local slots = br.menu(selectedMenu).slots
    if #slots >= MAX_SLOTS then
        ns:Print(L["This ring is full (%d entries)."], MAX_SLOTS)
        return
    end
    slots[#slots + 1] = slot
    br.requestPush()
    refreshPage()
end

-- Create a ring, empty or seeded from a preset's freshly built slots.
local function addRing(presetLabel, slots)
    if br.menuCount() >= MAX_MENUS then
        ns:Print(L["All %d rings are in use."], MAX_MENUS)
        return
    end
    br.closeRing()   -- an open ring must not steer across a renumbering
    mod.db.menuCount = br.menuCount() + 1
    local m = br.menu(mod.db.menuCount)
    m.slots = {}
    m.name = presetLabel and L[presetLabel] or nil
    m.appearance = nil
    for _, s in ipairs(slots or {}) do
        if #m.slots >= MAX_SLOTS then break end
        m.slots[#m.slots + 1] = s
    end
    selectedMenu = mod.db.menuCount
    if picker then picker:Hide() end
    br.updateBindings()
    br.requestPush()
    refreshPage()
end

-- What the current source offers, filtered by the search text. Rebuilt on
-- every refresh: bags and macros change under the dialog.
local function pickerEntries(search)
    local out = {}
    if pickerMode == "newring" then
        out[#out + 1] = { icon = 134400, label = L["Empty ring"],
            onPick = function() addRing(nil) end }
        for _, preset in ipairs(RING_PRESETS) do
            local slots = preset.build()
            if #slots > 0 then
                local icon = br.slotDisplay(slots[1])
                out[#out + 1] = { icon = icon, label = L[preset.label],
                    onPick = function() addRing(preset.label, preset.build()) end }
            end
        end
        -- Falls through to the search filter below rather than returning:
        -- the box is visible in this mode too, so it has to work.
    elseif pickerKind == "spell" then
        local book = BOOKTYPE_SPELL or "spell"
        local i = 1
        while true do
            local name, rank = GetSpellBookItemName(i, book)
            if not name then break end
            local kind, id = GetSpellBookItemInfo(i, book)
            if kind == "SPELL" and id and not IsPassiveSpell(i, book) then
                local label = (rank and rank ~= "") and (name .. " (" .. rank .. ")") or name
                out[#out + 1] = { icon = GetSpellBookItemTexture(i, book), label = label,
                    slot = { kind = "spell", id = id, name = name } }
            end
            i = i + 1
        end
    elseif pickerKind == "item" then
        local seen = {}
        local function offer(id)
            if not id or seen[id] then return end
            -- Only items that DO something on use belong in a ring.
            if not GetItemSpell(id) then return end
            seen[id] = true
            local icon = select(5, GetItemInfoInstant(id))
            out[#out + 1] = { icon = icon, label = GetItemInfo(id) or ("#" .. id),
                slot = { kind = "item", id = id } }
        end
        for bag = 0, 4 do
            for s = 1, GetNumSlotsFn(bag) or 0 do offer(GetItemIDFn(bag, s)) end
        end
        for inv = 13, 14 do offer(GetInventoryItemID("player", inv)) end
        table.sort(out, function(a, b) return a.label < b.label end)
    elseif pickerKind == "macro" then
        local global, char = GetNumMacros()
        for i = 1, (global or 0) do
            local name, icon = GetMacroInfo(i)
            if name then out[#out + 1] = { icon = icon, label = name,
                slot = { kind = "macro", name = name } } end
        end
        for i = 121, 120 + (char or 0) do
            local name, icon = GetMacroInfo(i)
            if name then out[#out + 1] = { icon = icon, label = name,
                slot = { kind = "macro", name = name } } end
        end
    elseif pickerKind == "marker" then
        for i = 1, 8 do
            out[#out + 1] = {
                icon = ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"):format(i),
                label = _G["RAID_TARGET_" .. i] or (L["Raid marker"] .. " " .. i),
                slot = { kind = "raidtarget", id = i },
            }
        end
        out[#out + 1] = { icon = 134400, label = L["Remove marker"],
            slot = { kind = "raidtarget", id = 0 } }
        out[#out + 1] = { icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
            label = L["Cycle raid markers"],
            slot = { kind = "cycleraidtarget" } }
        out[#out + 1] = { icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
            label = L["Clear all markers"],
            slot = { kind = "clearmarkers" } }
    end
    if search and search ~= "" then
        local needle = search:lower()
        local filtered = {}
        for _, e in ipairs(out) do
            if e.label:lower():find(needle, 1, true) then filtered[#filtered + 1] = e end
        end
        return filtered
    end
    return out
end

local function buildPicker()
    if picker then return picker end
    local UI = ns.UI
    local dlg = CreateFrame("Frame", "VuloActionRingPicker", UIParent)
    dlg:SetSize(PICKER_W, PICKER_H)
    dlg:SetPoint("CENTER", 120, 0)
    dlg:SetFrameStrata("FULLSCREEN_DIALOG")
    dlg:EnableMouse(true)
    dlg:SetMovable(true)
    dlg:RegisterForDrag("LeftButton")
    dlg:SetScript("OnDragStart", dlg.StartMoving)
    dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)

    local bg = dlg:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.97)
    local bc = ns.COLORS.border
    local edges = {}
    for i = 1, 4 do
        local t = dlg:CreateTexture(nil, "BORDER")
        t:SetColorTexture(bc.r, bc.g, bc.b, bc.a or 1)
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)

    dlg.strip = dlg:CreateTexture(nil, "ARTWORK")
    dlg.strip:SetPoint("TOPLEFT", 1, -1)
    dlg.strip:SetPoint("TOPRIGHT", -1, -1)
    dlg.strip:SetHeight(2)

    dlg.title = dlg:CreateFontString(nil, "OVERLAY")
    UI.Font(dlg.title, 13)
    dlg.title:SetPoint("TOPLEFT", 12, -12)

    UI:CreateCloseX(dlg, function() dlg:Hide() end)

    -- Source tabs; selection is repainted in refreshPicker, and the whole row
    -- hides in template mode.
    local kinds = {
        { key = "spell",  label = L["Spells"] },
        { key = "item",   label = L["Items"] },
        { key = "macro",  label = L["Macros"] },
        { key = "marker", label = L["Markers"] },
    }
    dlg.tabs = {}
    local x = 10
    for _, k in ipairs(kinds) do
        local b = UI:CreateButton(dlg, { label = k.label, width = 74, onClick = function()
            pickerKind = k.key
            refreshPicker()
        end })
        b:SetHeight(22)
        -- Sized to the TRANSLATED label, not a fixed 74: "Gegenstände" is
        -- half again as wide as "Items" and ran into its neighbour.
        local fs = b:GetFontString()
        local w = math.max(50, math.ceil((fs and fs:GetStringWidth() or 50) + 16))
        b:SetWidth(w)
        b:SetPoint("TOPLEFT", dlg, "TOPLEFT", x, -34)
        b._kind = k.key
        dlg.tabs[#dlg.tabs + 1] = b
        x = x + w + 4
    end

    local eb = CreateFrame("EditBox", nil, dlg)
    eb:SetAutoFocus(false)
    UI.Font(eb, 12)
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetHeight(22)
    eb:SetPoint("TOPLEFT", dlg, "TOPLEFT", 10, -62)
    eb:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -10, -62)
    local ebg = eb:CreateTexture(nil, "BACKGROUND")
    ebg:SetAllPoints(eb)
    ebg:SetColorTexture(0.08, 0.08, 0.1, 0.9)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTextChanged", function() refreshPicker() end)
    dlg.search = eb

    dlg.hint = dlg:CreateFontString(nil, "OVERLAY")
    UI.Font(dlg.hint, 11)
    dlg.hint:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -4)
    dlg.hint:SetTextColor(0.55, 0.55, 0.6)

    local sf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", dlg, "TOPLEFT", 10, -100)
    sf:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -28, 40)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(PICKER_W - 40, 1)
    sf:SetScrollChild(child)
    UI.StyleScrollbar(sf)
    dlg.child = child
    dlg.rows = {}

    -- A macro can do what no list offers; the command entry takes any /text.
    dlg.custom = UI:CreateButton(dlg, { label = L["Custom command..."], width = 150,
        tooltip = L["Add an entry that runs a slash command or macro text."],
        onClick = function()
            ns.UI:ShowStringImportDialog(L["Custom command"], function(text)
                if not text or text == "" then return end
                addSlot({ kind = "macrotext", text = text,
                    name = text:match("^(/%S+)") or L["Custom command"] })
            end)
        end })
    dlg.custom:SetHeight(24)
    dlg.custom:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 10, 8)

    picker = dlg
    return dlg
end

refreshPicker = function()
    if not picker or not picker:IsShown() then return end
    local UI = ns.UI
    local ac = ns.COLORS.accent
    UI.SetGradient(picker.strip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.9, ac.r, ac.g, ac.b, 0.1)

    local isNewRing = pickerMode == "newring"
    picker.title:SetText(isNewRing and L["New ring - empty or template"]
        or (L["Add entry"] .. "  -  " .. br.menuName(selectedMenu)))
    picker.hint:SetText(isNewRing and L["Templates are built from what this character has right now."]
        or L["Click an entry to add it to the ring."])
    picker.custom:SetShown(not isNewRing)
    for _, tab in ipairs(picker.tabs) do
        tab:SetShown(not isNewRing)
        local fs = tab:GetFontString()
        if fs then
            if tab._kind == pickerKind then
                fs:SetTextColor(ac.r, ac.g, ac.b)
            else
                fs:SetTextColor(0.8, 0.8, 0.85)
            end
        end
    end

    local entries = pickerEntries(picker.search:GetText())
    picker.child:SetHeight(math.max(1, #entries * PROW_H))
    for i, e in ipairs(entries) do
        local row = picker.rows[i]
        if not row then
            row = CreateFrame("Button", nil, picker.child)
            row:SetSize(PICKER_W - 42, PROW_H - 2)
            row:SetPoint("TOPLEFT", picker.child, "TOPLEFT", 0, -(i - 1) * PROW_H)
            row.hover = row:CreateTexture(nil, "BACKGROUND")
            row.hover:SetAllPoints()
            row.hover:SetColorTexture(1, 1, 1, 0)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("LEFT", 2, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.name = row:CreateFontString(nil, "OVERLAY")
            UI.Font(row.name, 12)
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetPoint("RIGHT", -4, 0)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
            row:SetScript("OnEnter", function(self) self.hover:SetColorTexture(1, 1, 1, 0.06) end)
            row:SetScript("OnLeave", function(self) self.hover:SetColorTexture(1, 1, 1, 0) end)
            picker.rows[i] = row
        end
        row.icon:SetTexture(e.icon or 134400)
        row.name:SetText(e.label)
        row:SetScript("OnClick", function()
            if e.onPick then e.onPick() else addSlot(e.slot) end
        end)
        row:Show()
    end
    for i = #entries + 1, #picker.rows do picker.rows[i]:Hide() end
end

local function openPicker(mode)
    buildPicker()
    pickerMode = mode or "entries"
    picker.search:SetText("")
    picker:Show()
    refreshPicker()
end

-------------------------------------------------------------------------------
--  The entries panel -- a custom row on the page, rebuilt with it.
-------------------------------------------------------------------------------

local EROW_H, PANEL_H = 26, 240

-- One panel for the module's lifetime: the builder's custom contract wants a
-- memoised frame that survives clearChildren (frames are immortal in this
-- client — a fresh tree per page build would be a leak, one scrollframe per
-- click). The builder also anchors only TOPLEFT and never sets a width, so
-- the panel measures its own from the page — deferred, because at build time
-- the parent may not be laid out yet and GetWidth() answers 0 (truthy, so an
-- `or` fallback would be dead code).
local entriesPanel

-- Forward: the entries panel's row actions (move, remove) redraw themselves
-- without the full page rebuild every other setter goes through, so they
-- poke the preview by hand.
local previewPanel
local function refreshPreview()
    if previewPanel and previewPanel:IsShown() and previewPanel.refresh then
        previewPanel.refresh()
    end
end

local function buildEntriesPanel(parent)
    local UI = ns.UI
    if entriesPanel then
        entriesPanel:SetParent(parent)
        entriesPanel:Show()
        entriesPanel.refresh()
        return entriesPanel
    end
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(480, PANEL_H)

    local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -18, 30)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    UI.StyleScrollbar(sf)

    local empty = panel:CreateFontString(nil, "OVERLAY")
    UI.Font(empty, 11)
    empty:SetPoint("TOP", sf, "TOP", 0, -18)
    empty:SetTextColor(0.45, 0.45, 0.5)
    empty:SetText(L["This ring is empty - add entries below."])

    local addBtn = UI:CreateButton(panel, { label = L["Add entry"], width = 120, primary = true,
        onClick = function() openPicker("entries") end })
    addBtn:SetHeight(24)
    addBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)

    local counter = panel:CreateFontString(nil, "OVERLAY")
    UI.Font(counter, 11)
    counter:SetPoint("LEFT", addBtn, "RIGHT", 10, 0)
    counter:SetTextColor(0.55, 0.55, 0.6)

    local rows = {}
    local function refresh()
        local pp = panel:GetParent()
        local pw = pp and pp:GetWidth() or 0
        if pw > 60 then panel:SetWidth(pw - 24) end
        local slots = br.menu(selectedMenu).slots
        local n = #slots
        empty:SetShown(n == 0)
        counter:SetText(L["%d of %d entries"]:format(n, MAX_SLOTS))
        child:SetSize(math.max(panel:GetWidth() - 20, 100), math.max(1, n * EROW_H))
        for i = 1, n do
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, child)
                row:SetHeight(EROW_H - 2)
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * EROW_H)
                row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(20, 20)
                row.icon:SetPoint("LEFT", 2, 0)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.name = row:CreateFontString(nil, "OVERLAY")
                UI.Font(row.name, 12)
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetPoint("RIGHT", row, "RIGHT", -76, 0)
                row.name:SetJustifyH("LEFT")
                row.name:SetWordWrap(false)
                -- up / down / delete, fixed places on the right edge so the
                -- rows line up like every option row does.
                local function glyphButton(text, xofs, tip, onClick)
                    local b = CreateFrame("Button", nil, row)
                    b:SetSize(20, 20)
                    b:SetPoint("RIGHT", row, "RIGHT", xofs, 0)
                    b.txt = b:CreateFontString(nil, "OVERLAY")
                    UI.Font(b.txt, 12)
                    b.txt:SetPoint("CENTER")
                    b.txt:SetText(text)
                    b:SetScript("OnEnter", function(self)
                        local acc = ns.COLORS.accent
                        self.txt:SetTextColor(acc.r, acc.g, acc.b)
                        if tip then UI:ShowTooltip(self, tip) end
                    end)
                    b:SetScript("OnLeave", function(self)
                        self.txt:SetTextColor(0.7, 0.7, 0.75)
                        UI:HideTooltip()
                    end)
                    b.txt:SetTextColor(0.7, 0.7, 0.75)
                    b:SetScript("OnClick", onClick)
                    return b
                end
                -- Texture arrows, not text: the house font has no arrow
                -- glyphs, they render as boxes. The chat expand arrow points
                -- right; turned on its side it is an up or a down arrow, and
                -- it is white, so the hover tint works on it like on text.
                local function arrowButton(pointsUp, xofs, tip, onClick)
                    local b = CreateFrame("Button", nil, row)
                    b:SetSize(20, 20)
                    b:SetPoint("RIGHT", row, "RIGHT", xofs, 0)
                    b.tex = b:CreateTexture(nil, "ARTWORK")
                    b.tex:SetSize(12, 12)
                    b.tex:SetPoint("CENTER")
                    b.tex:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
                    b.tex:SetRotation(pointsUp and math.rad(90) or math.rad(-90))
                    b.tex:SetVertexColor(0.7, 0.7, 0.75)
                    b:SetScript("OnEnter", function(self)
                        local acc = ns.COLORS.accent
                        self.tex:SetVertexColor(acc.r, acc.g, acc.b)
                        if tip then UI:ShowTooltip(self, tip) end
                    end)
                    b:SetScript("OnLeave", function(self)
                        self.tex:SetVertexColor(0.7, 0.7, 0.75)
                        UI:HideTooltip()
                    end)
                    b:SetScript("OnClick", onClick)
                    return b
                end
                row.up   = arrowButton(true,  -48, L["Move up"], function() row.onUp() end)
                row.down = arrowButton(false, -26, L["Move down"], function() row.onDown() end)
                row.del  = glyphButton("×", -4,  L["Remove"], function() row.onDel() end)
                rows[i] = row
            end
            local slot = slots[i]
            local icon, label = br.slotDisplay(slot)
            row.icon:SetTexture(icon or 134400)
            row.name:SetText(label or "?")
            row.onUp = function()
                if i > 1 then
                    slots[i], slots[i - 1] = slots[i - 1], slots[i]
                    br.requestPush(); refresh(); refreshPreview()
                end
            end
            row.onDown = function()
                if i < #slots then
                    slots[i], slots[i + 1] = slots[i + 1], slots[i]
                    br.requestPush(); refresh(); refreshPreview()
                end
            end
            row.onDel = function()
                table.remove(slots, i)
                br.requestPush(); refresh(); refreshPreview()
            end
            row.up:SetShown(i > 1)
            row.down:SetShown(i < n)
            row:Show()
        end
        for i = n + 1, #rows do rows[i]:Hide() end
    end
    panel.refresh = refresh
    -- One measuring pass after the page has real geometry; re-armed on every
    -- show so a rebuilt page re-measures too.
    panel:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function(s)
            s:SetScript("OnUpdate", nil)
            refresh()
        end)
    end)
    entriesPanel = panel
    refresh()
    return panel
end

-------------------------------------------------------------------------------
--  The preview panel -- the selected ring's entries in their real arrangement,
--  redrawn by every refreshPage(), which the layout setters already call on
--  each slider tick: live update rides the page's own rebuild.
-------------------------------------------------------------------------------

local PREVIEW_H = 210
local WHITE8X8  = "Interface\\Buttons\\WHITE8X8"

-- The panel itself is memoised like entriesPanel, and for the same reasons;
-- its local lives above the entries panel, which pokes it.
local function buildPreviewPanel(parent)
    local UI = ns.UI
    if previewPanel then
        previewPanel:SetParent(parent)
        previewPanel:Show()
        previewPanel.refresh()
        return previewPanel
    end
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(480, PREVIEW_H)

    -- The stage: entries sit in true geometry inside the holder, and the
    -- HOLDER shrinks to fit -- proportions, gaps and sizes stay true to each
    -- other, and a ring that fits is shown at its real size, never enlarged.
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("CENTER")
    holder:SetSize(1, 1)

    -- Tiles in the look of the real ring's slices (ActionRing.lua newSlice):
    -- same backdrop, border, icon inset and trim, so the preview promises the
    -- picture the hold will deliver.
    local tiles = {}
    local function tile(i)
        local t = tiles[i]
        if not t then
            t = CreateFrame("Frame", nil, holder, "BackdropTemplate")
            t:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
            t:SetBackdropColor(0.05, 0.05, 0.06, 0.92)
            t:SetBackdropBorderColor(0.22, 0.22, 0.27, 1)
            t.icon = t:CreateTexture(nil, "ARTWORK")
            t.icon:SetPoint("TOPLEFT", 2, -2)
            t.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            t.label = t:CreateFontString(nil, "OVERLAY")
            t.label:SetFont(UI.FONT_PATH, 10, "OUTLINE")
            t.label:SetPoint("TOP", t, "BOTTOM", 0, -2)
            t.label:SetTextColor(0.8, 0.8, 0.85)
            t:EnableMouse(true)
            t:SetScript("OnEnter", function(self)
                if self.tipText then UI:ShowTooltip(self, self.tipText) end
            end)
            t:SetScript("OnLeave", function() UI:HideTooltip() end)
            tiles[i] = t
        end
        return t
    end

    -- The add button lives INSIDE the holder, placed by the same layout that
    -- placed the entries, so it lands where the next entry would.
    local plus = CreateFrame("Button", nil, holder, "BackdropTemplate")
    plus:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
    plus:SetBackdropColor(0.05, 0.05, 0.06, 0.6)
    plus:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    plus.txt = plus:CreateFontString(nil, "OVERLAY")
    UI.Font(plus.txt, 16)
    plus.txt:SetPoint("CENTER")
    plus.txt:SetText("+")
    plus.txt:SetTextColor(0.7, 0.7, 0.75)
    plus:SetScript("OnEnter", function(self)
        local acc = ns.COLORS.accent
        self.txt:SetTextColor(acc.r, acc.g, acc.b)
        self:SetBackdropBorderColor(acc.r, acc.g, acc.b, 1)
        UI:ShowTooltip(self, L["Add entry"])
    end)
    plus:SetScript("OnLeave", function(self)
        self.txt:SetTextColor(0.7, 0.7, 0.75)
        self:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
        UI:HideTooltip()
    end)
    plus:SetScript("OnClick", function() openPicker("entries") end)

    local function refresh()
        local pp = panel:GetParent()
        local pw = pp and pp:GetWidth() or 0
        if pw > 60 then panel:SetWidth(pw - 24) end

        local lay = br.previewLayout(selectedMenu)
        local half = lay.iconSize * 0.5
        local labelPad = lay.showText and 14 or 0

        -- Half-extents of the drawn picture, add button included; the fit is
        -- computed against the REAL on-screen size (geometry times the ring's
        -- own scale), so the scale slider visibly acts until space runs out.
        local plusHalf = math.max(half * 0.6, 11)
        local maxX = math.abs(lay.plusX) + plusHalf
        local maxY = math.abs(lay.plusY) + plusHalf
        for _, e in ipairs(lay.entries) do
            maxX = math.max(maxX, math.abs(e.x) + half)
            maxY = math.max(maxY, math.abs(e.y) + half + labelPad)
        end
        local availW = math.max(100, (panel:GetWidth() or 480) - 20)
        local availH = PREVIEW_H - 12
        local fit = math.min(1,
            availW * 0.5 / math.max(1, maxX * lay.scale),
            availH * 0.5 / math.max(1, maxY * lay.scale))
        holder:SetScale(lay.scale * fit)

        for i, e in ipairs(lay.entries) do
            local t = tile(i)
            t:SetSize(lay.iconSize, lay.iconSize)
            local icon, label = br.slotDisplay(e.slot)
            t.icon:SetTexture(icon or 134400)
            t.label:SetText(lay.showText and label or "")
            t.tipText = label
            t:ClearAllPoints()
            t:SetPoint("CENTER", holder, "CENTER", e.x, e.y)
            t:Show()
        end
        for i = #lay.entries + 1, #tiles do tiles[i]:Hide() end

        plus:SetSize(plusHalf * 2, plusHalf * 2)
        plus:ClearAllPoints()
        plus:SetPoint("CENTER", holder, "CENTER", lay.plusX, lay.plusY)
        -- A full ring gets no add button -- a grid's "next cell" would sit on
        -- top of an entry, and addSlot would only print the refusal anyway.
        plus:SetShown(lay.total < MAX_SLOTS)
    end
    panel.refresh = refresh
    -- Same deferred measuring pass as the entries panel: at build time the
    -- parent may not have real geometry yet.
    panel:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function(s)
            s:SetScript("OnUpdate", nil)
            refresh()
        end)
    end)
    previewPanel = panel
    refresh()
    return panel
end

-------------------------------------------------------------------------------
--  Ring management
-------------------------------------------------------------------------------

-- Deleting ring i renumbers everything behind it, and the KEYBINDS have to
-- move with their rings: the binding actions are numbered by index, so each
-- following ring's keys are re-bound one action down. Done before the table
-- shrinks, while both old and new owner of every key still exist.
local function deleteRing(index)
    -- The keybind renumbering below runs through SetBinding, which silently
    -- fails in combat -- but the table WOULD shrink, leaving every following
    -- key on the wrong ring for good. The whole operation waits.
    if InCombatLockdown() then
        ns:Print(L["Not in combat - keybinds can't be changed while fighting."])
        return
    end
    br.closeRing()   -- an open ring must not steer across a renumbering
    local count = br.menuCount()
    if count <= 1 then
        -- The last ring is emptied, not removed: zero rings is not a state
        -- the page has any way to show.
        mod.db.menus[1] = { slots = {} }
        br.requestPush()
        refreshPage()
        return
    end
    -- Both key slots move: the page binds one key per ring, but Blizzard's
    -- own keybinding UI can put two on any action, and a delete must not eat
    -- the second one.
    for i = index, count - 1 do
        local n1, n2 = GetBindingKey(BINDING_PREFIX .. (i + 1))
        local h1, h2 = GetBindingKey(BINDING_PREFIX .. i)
        if h1 then SetBinding(h1) end
        if h2 then SetBinding(h2) end
        if n1 then SetBinding(n1, BINDING_PREFIX .. i) end
        if n2 then SetBinding(n2, BINDING_PREFIX .. i) end
    end
    local l1, l2 = GetBindingKey(BINDING_PREFIX .. count)
    if l1 then SetBinding(l1) end
    if l2 then SetBinding(l2) end
    if SaveBindings then
        SaveBindings((GetCurrentBindingSet and GetCurrentBindingSet()) or 2)
    end
    table.remove(mod.db.menus, index)
    mod.db.menuCount = count - 1
    clampSelection()
    br.updateBindings()
    br.requestPush()
    refreshPage()
end

-- "Apply to all rings": the selected ring's effective look becomes the
-- profile, and every ring's own overrides are dropped -- one look everywhere,
-- taken from the ring being edited.
local function applyToAllRings()
    local p = br.pa(selectedMenu)
    for key in pairs(br.APPEARANCE_KEYS) do
        local v = p[key]
        if type(v) == "table" then
            local copy = {}
            for k2, v2 in pairs(v) do copy[k2] = v2 end
            v = copy
        end
        mod.db[key] = v
    end
    for i = 1, br.menuCount() do
        local m = mod.db.menus[i]
        if m then m.appearance = nil end
    end
    br.requestPush()
    refreshPage()
end

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------

-- The layout and display rows exist twice -- once writing the profile, once
-- writing the selected ring's override table -- so they are generated from
-- one accessor pair instead of being written out twice and drifting apart.
local function layoutRows(get, set)
    local items = {}
    local layout = get("layout") or "arc"

    table.insert(items, { type = "dropdown", label = L["Layout"],
        width = 240,
        values = {
            { value = "arc",  text = L["Ring"] },
            { value = "grid", text = L["Grid"] },
            { value = "fan",  text = L["Strip (mouse wheel)"] },
        },
        get = function() return get("layout") or "arc" end,
        set = function(_, v) set("layout", v) end })

    -- Conditional rows instead of gears throughout this builder: every set
    -- rebuilds the page, so a row that would do nothing simply is not there.
    table.insert(items, { type = "dropdown", label = L["Open position"],
        width = 240,
        values = {
            { value = "cursor", text = L["At the cursor"] },
            { value = "screen", text = L["Fixed screen position"] },
        },
        get = function() return get("centerMode") or "cursor" end,
        set = function(_, v) set("centerMode", v) end })
    if get("centerMode") == "screen" then
        table.insert(items, { type = "slider", label = L["Horizontal offset"],
            min = -800, max = 800, step = 5,
            get = function() return get("posX") or 0 end,
            set = function(_, v) set("posX", v) end })
        table.insert(items, { type = "slider", label = L["Vertical offset"],
            min = -500, max = 500, step = 5,
            get = function() return get("posY") or 0 end,
            set = function(_, v) set("posY", v) end })
    end

    if layout == "arc" then
        table.insert(items, { type = "slider", label = L["Arc width"],
            tooltip = L["360 is a full circle; anything less opens a fan of that width."],
            min = 30, max = 360, step = 5,
            get = function() return get("arcSpan") or 360 end,
            set = function(_, v) set("arcSpan", v) end })
        table.insert(items, { type = "slider", label = L["Rotation"],
            min = 0, max = 355, step = 5,
            get = function() return get("arcRotation") or 0 end,
            set = function(_, v) set("arcRotation", v) end })
        table.insert(items, { type = "slider", label = L["Distance from centre"],
            tooltip = L["The ring grows on its own when entries would overlap; this is the smallest size."],
            min = 50, max = 250, step = 5,
            get = function() return get("radius") or 100 end,
            set = function(_, v) set("radius", v) end })
    elseif layout == "grid" then
        -- The columns slider matters when the switch is OFF -- an inverted
        -- dependency, so the pair stays flat rather than gaining a gear.
        table.insert(items, { type = "toggle", label = L["Choose columns automatically"],
            tooltip = L["A near-square grid keeps the worst pointer travel short."],
            get = function() return get("gridAutoColumns") ~= false end,
            set = function(_, v) set("gridAutoColumns", v) end })
        if get("gridAutoColumns") == false then
            table.insert(items, { type = "slider", label = L["Columns"],
                min = 1, max = 8, step = 1,
                get = function() return get("gridColumns") or 4 end,
                set = function(_, v) set("gridColumns", v) end })
        end
    elseif layout == "fan" then
        table.insert(items, { type = "dropdown", label = L["Strip direction"],
            width = 240,
            values = {
                { value = "horizontal", text = L["Horizontal"] },
                { value = "vertical",   text = L["Vertical"] },
            },
            get = function() return get("fanOrientation") or "horizontal" end,
            set = function(_, v) set("fanOrientation", v) end })
        table.insert(items, { type = "slider", label = L["Entries each side"],
            min = 1, max = 6, step = 1,
            get = function() return get("fanVisible") or 2 end,
            set = function(_, v) set("fanVisible", v) end })
        table.insert(items, { type = "toggle", label = L["Invert scroll direction"],
            get = function() return get("fanInvert") == true end,
            set = function(_, v) set("fanInvert", v) end })
        table.insert(items, { type = "toggle", label = L["Select with the mouse"],
            tooltip = L["The release fires the entry under the pointer; with this off, the wheel's entry fires."],
            get = function() return get("fanMouseSelect") ~= false end,
            set = function(_, v) set("fanMouseSelect", v) end })
    end

    table.insert(items, { type = "slider", label = L["Icon size"],
        min = 24, max = 64, step = 2,
        get = function() return get("iconSize") or 40 end,
        set = function(_, v) set("iconSize", v) end })
    table.insert(items, { type = "slider", label = L["Icon spacing"],
        min = 0, max = 24, step = 1,
        get = function() return get("gap") or 6 end,
        set = function(_, v) set("gap", v) end })
    table.insert(items, { type = "slider", label = L["Scale"],
        min = 50, max = 200, step = 5,
        get = function() return math.floor((get("scale") or 1) * 100 + 0.5) end,
        set = function(_, v) set("scale", v / 100) end })
    return items
end

local function displayRows(get, set)
    local items = {}
    table.insert(items, { type = "toggle", label = L["Show cooldowns"],
        get = function() return get("showCooldowns") ~= false end,
        set = function(_, v) set("showCooldowns", v) end })
    table.insert(items, { type = "toggle", label = L["Grey out unusable entries"],
        get = function() return get("showUsability") ~= false end,
        set = function(_, v) set("showUsability", v) end })
    table.insert(items, { type = "toggle", label = L["Hide entries this character cannot use"],
        tooltip = L["Unknown spells and missing macros are left out of the ring entirely. The stored entries stay for characters that can use them."],
        get = function() return get("hideUnusable") == true end,
        set = function(_, v) set("hideUnusable", v) end })
    table.insert(items, { type = "toggle", label = L["Show entry names"],
        get = function() return get("showActionText") == true end,
        set = function(_, v) set("showActionText", v) end })
    table.insert(items, { type = "toggle", label = L["Show ring name in the middle"],
        get = function() return get("showHubText") ~= false end,
        set = function(_, v) set("showHubText", v) end })
    table.insert(items, { type = "toggle", label = L["Show pointer needle"],
        tooltip = L["A dotted line from the centre toward the cursor. Ring layout only."],
        get = function() return get("showNeedle") ~= false end,
        set = function(_, v) set("showNeedle", v) end })
    table.insert(items, { type = "dropdown", label = L["Selection colour"],
        width = 240,
        values = {
            { value = "accent", text = L["Theme colour"] },
            { value = "class",  text = L["Class colour"] },
            { value = "custom", text = L["Custom"] },
        },
        get = function() return get("selectColorMode") or "accent" end,
        set = function(_, v) set("selectColorMode", v) end })
    if get("selectColorMode") == "custom" then
        table.insert(items, { type = "color", label = L["Custom selection colour"], width = 220,
            get = function() return get("selectColor") end,
            set = function(r, g, b) set("selectColor", { r = r, g = g, b = b }) end })
    end
    return items
end

function mod:GetOptions()
    clampSelection()
    local items = {}

    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaHold a keybind to open a ring of actions. Aim at an entry and release the key to use it; release over the middle to cancel. Each ring has its own keybind and its own entries.|r"] })

    table.insert(items, { type = "toggle", label = L["Enable action ring"],
        get = function() return ns:IsModuleEnabled("actionring") end,
        set = function(_, v)
            if ns.ToggleModule then ns:ToggleModule("actionring", v) end
        end })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Ring setup"] })

    do
        local values = {}
        for i = 1, br.menuCount() do
            values[#values + 1] = { value = i, text = br.menuName(i) }
        end
        values[#values + 1] = { action = true, text = L["Add new ring"],
            onClick = function() openPicker("newring") end }
        table.insert(items, { type = "dropdown", label = L["Edit ring"],
            width = 240, values = values,
            get = function() return selectedMenu end,
            set = function(_, v) selectedMenu = v; refreshPage() end })
    end

    table.insert(items, { type = "editbox", label = L["Ring name"],
        -- The buttons right below steal focus before their OnClick; without
        -- this, a typed name is silently discarded on click-away.
        commitOnFocusLost = true,
        tooltip = L["Shown in the middle of the ring and in the keybinding list."],
        get = function()
            local m = mod.db.menus[selectedMenu]
            return (m and m.name) or ""
        end,
        set = function(_, v)
            br.menu(selectedMenu).name = (v ~= "" and v) or nil
            refreshPage()
        end })

    table.insert(items, {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", width = 170,
              label = L["Keybind: %s"]:format(ringKeyText(selectedMenu)),
              tooltip = L["Bind or change the key that opens this ring."],
              onClick = function()
                  startCapture(function(combo) bindRingKey(selectedMenu, combo) end)
              end },
            { type = "button", label = L["Unbind"], width = 90,
              onClick = function() unbindRingKey(selectedMenu) end },
            { type = "button", label = L["Delete ring"], width = 110,
              onClick = function() deleteRing(selectedMenu) end },
            { type = "button", label = L["Preview"], width = 90,
              tooltip = L["Opens this ring without a key press. It closes by itself after a while, or press the button again."],
              onClick = function()
                  if _G.VuloActionRingFrame and _G.VuloActionRingFrame:IsShown() then
                      br.closeRing()
                  else
                      br.openPreview(selectedMenu)
                  end
              end },
        },
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Entries"] })
    table.insert(items, { type = "custom", height = PANEL_H,
        build = buildEntriesPanel })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Preview"] })
    table.insert(items, { type = "custom", height = PREVIEW_H,
        build = buildPreviewPanel })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Layout"] })

    -- Profile accessors: the shared look every ring without overrides uses.
    local function profGet(key) return mod.db[key] end
    local function profSet(key, v)
        mod.db[key] = v
        br.requestPush()
        refreshPage()
    end
    for _, it in ipairs(layoutRows(profGet, profSet)) do
        table.insert(items, it)
    end

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["This ring's own look"] })
    table.insert(items, { type = "toggle", label = L["Override the look for this ring"],
        tooltip = L["This ring keeps its own layout and display settings; every other ring follows the shared ones above."],
        subKey = "override",
        get = function()
            local m = mod.db.menus[selectedMenu]
            return (m and m.appearance) ~= nil
        end,
        set = function(_, v)
            if v then
                br.menuAppearance(selectedMenu, true)
            else
                local m = mod.db.menus[selectedMenu]
                if m then m.appearance = nil end
            end
            br.requestPush()
            refreshPage()
        end,
        subOptions = (function()
            local m = mod.db.menus[selectedMenu]
            if not (m and m.appearance) then
                return {
                    { type = "desc", text = L["|cffaaaaaaTurn the override on to give this ring its own settings.|r"] },
                }
            end
            -- Ring accessors: read through the override view (so untouched
            -- values show the profile's), write into the override table.
            local function ringGet(key) return br.pa(selectedMenu)[key] end
            local function ringSet(key, v)
                br.menuAppearance(selectedMenu, true)[key] = v
                br.requestPush()
                refreshPage()
            end
            local out = layoutRows(ringGet, ringSet)
            for _, it in ipairs(displayRows(ringGet, ringSet)) do
                table.insert(out, it)
            end
            table.insert(out, {
                type = "button", label = L["Apply this look to all rings"], width = 240,
                tooltip = L["The shared settings take this ring's values and every ring's own override is removed."],
                onClick = applyToAllRings,
            })
            return out
        end)() })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Behaviour"] })

    table.insert(items, { type = "toggle", label = L["Keep the ring open"],
        tooltip = L["The ring stays open after the key is released. Aim and press the select key to use an entry; ESCAPE or the ring's key closes it."],
        get = function() return mod.db.toggleMode end,
        set = function(_, v) mod.db.toggleMode = v; br.requestPush(); refreshPage() end,
        subOptions = {
            { type = "button", width = 220,
              label = L["Select key: %s"]:format((mod.db.confirmKey ~= "" and mod.db.confirmKey) or L["Not bound"]),
              tooltip = L["The key that uses the aimed entry while the ring is kept open. Without it the ring falls back to hold-and-release."],
              onClick = function()
                  startCapture(function(combo)
                      mod.db.confirmKey = combo
                      br.requestPush()
                      refreshPage()
                  end)
              end },
            { type = "button", label = L["Clear select key"], width = 150,
              onClick = function()
                  mod.db.confirmKey = ""
                  br.requestPush()
                  refreshPage()
              end },
        } })

    table.insert(items, {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", width = 220,
              label = L["Cancel key: %s"]:format((mod.db.cancelKey ~= "" and mod.db.cancelKey) or L["Not bound"]),
              tooltip = L["An extra key that closes the ring without using anything. ESCAPE always works."],
              onClick = function()
                  startCapture(function(combo)
                      mod.db.cancelKey = combo
                      br.requestPush()
                      refreshPage()
                  end)
              end },
            { type = "button", label = L["Clear cancel key"], width = 150,
              onClick = function()
                  mod.db.cancelKey = ""
                  br.requestPush()
                  refreshPage()
              end },
        },
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Display"] })
    for _, it in ipairs(displayRows(profGet, profSet)) do
        table.insert(items, it)
    end

    return items
end
