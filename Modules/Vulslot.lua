-- =========================================================
-- VuloClassicUI / Modules / Vulslot
-- Named snapshots of your complete bar setup: all 120 action slots
-- (spells, macros, items), your macros and your keybindings — saved
-- to SavedVariables and restorable with one click. Spells are matched
-- by ID with a name fallback, macros by name, so snapshots survive
-- relogs and macro reshuffles.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("vulslot", {
    name        = "Vulslot",
    group       = "QoL",
    description = "Saves named snapshots of your action bars, macros and keybindings, and restores them with one click.",
    defaults    = {
        enabled         = true,
        restoreMacros   = true,
        restoreBindings = true,
        profiles        = {},   -- name -> snapshot
    },
})

local MAX_SLOTS = 120

local function accountMacroCap()
    return _G.MAX_ACCOUNT_MACROS or 36
end
local function characterMacroCap()
    return _G.MAX_CHARACTER_MACROS or 18
end

-- =========================================================
-- Snapshot (save)
-- =========================================================
local function snapshotActions()
    local out = {}
    for slot = 1, MAX_SLOTS do
        local t, id = GetActionInfo(slot)
        if t == "spell" and id then
            out[slot] = { type = "spell", id = id, name = GetSpellInfo(id) }
        elseif t == "macro" and id then
            local name = GetMacroInfo(id)
            if name then out[slot] = { type = "macro", name = name } end
        elseif t == "item" and id then
            out[slot] = { type = "item", id = id, name = GetItemInfo(id) }
        end
        -- anything else (empty / unsupported type) -> slot stays nil
    end
    return out
end

local function snapshotMacros()
    local out = {}
    local cap = accountMacroCap() + characterMacroCap()
    for i = 1, cap do
        local name, icon, body = GetMacroInfo(i)
        if name then
            out[#out + 1] = {
                name    = name,
                icon    = icon,
                body    = body,
                perchar = i > accountMacroCap(),
            }
        end
    end
    return out
end

local function snapshotBindings()
    local out = {}
    for i = 1, (GetNumBindings and GetNumBindings() or 0) do
        local command = GetBinding(i)
        if command and type(command) == "string" then
            local k1, k2 = GetBindingKey(command)
            if k1 or k2 then
                out[#out + 1] = { command = command, k1 = k1, k2 = k2 }
            end
        end
    end
    return out
end

local function saveProfile(name)
    local _, class = UnitClass("player")
    mod.db.profiles[name] = {
        class    = class,
        actions  = snapshotActions(),
        macros   = snapshotMacros(),
        bindings = snapshotBindings(),
    }
    ns:Print(L["Vulslot profile '%s' saved."], name)
end

-- =========================================================
-- Restore (load)
-- =========================================================
local function restoreMacros(list)
    local edited, created, failed = 0, 0, 0
    ClearCursor()
    for _, m in ipairs(list or {}) do
        local idx = GetMacroIndexByName(m.name) or 0
        if idx > 0 then
            local ok = pcall(EditMacro, idx, m.name, m.icon, m.body)
            if ok then edited = edited + 1 else failed = failed + 1 end
        else
            local ok, newId = pcall(CreateMacro, m.name,
                m.icon or "INV_MISC_QUESTIONMARK", m.body, m.perchar)
            if ok and newId then created = created + 1 else failed = failed + 1 end
        end
    end
    return edited + created, failed
end

local function restoreSlot(slot, saved, counts)
    local curType, curId = GetActionInfo(slot)

    if not saved then
        if curType then
            PickupAction(slot)
            ClearCursor()
            counts.cleared = counts.cleared + 1
        end
        return
    end

    -- Skip when the slot already matches (no flicker, no churn)
    if saved.type == "spell" and curType == "spell" and curId == saved.id then return end
    if saved.type == "item"  and curType == "item"  and curId == saved.id then return end
    if saved.type == "macro" and curType == "macro" and curId then
        local curName = GetMacroInfo(curId)
        if curName == saved.name then return end
    end

    ClearCursor()
    if saved.type == "spell" then
        pcall(PickupSpell, saved.id)
        if not GetCursorInfo() and saved.name then
            pcall(PickupSpell, saved.name)  -- rank/ID changed -> try by name
        end
    elseif saved.type == "macro" then
        local idx = saved.name and (GetMacroIndexByName(saved.name) or 0) or 0
        if idx > 0 then PickupMacro(idx) end
    elseif saved.type == "item" then
        pcall(PickupItem, saved.id)
    end

    if GetCursorInfo() then
        PlaceAction(slot)   -- previous content lands on the cursor
        ClearCursor()
        counts.placed = counts.placed + 1
    else
        -- spell unknown / item not owned / macro missing: keep what's there
        counts.skipped = counts.skipped + 1
    end
end

local function restoreBindings(list)
    local n = 0
    for _, b in ipairs(list or {}) do
        -- exact restore for this command: drop its current keys first
        local c1, c2 = GetBindingKey(b.command)
        if c1 then SetBinding(c1) end
        if c2 then SetBinding(c2) end
        if b.k1 then SetBinding(b.k1, b.command) end
        if b.k2 then SetBinding(b.k2, b.command) end
        n = n + 1
    end
    if SaveBindings then
        SaveBindings((GetCurrentBindingSet and GetCurrentBindingSet()) or 2)
    end
    return n
end

local function loadProfile(name)
    local p = mod.db.profiles[name]
    if not p then return end
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Not in combat — Vulslot can't change bars while fighting."])
        return
    end

    local _, class = UnitClass("player")
    if p.class and p.class ~= class then
        ns:Print(L["Note: profile '%s' was saved on another class (%s)."], name, p.class)
    end

    -- Order matters: macros first so slots can resolve them by name
    if mod.db.restoreMacros and p.macros then
        restoreMacros(p.macros)
    end

    local counts = { placed = 0, cleared = 0, skipped = 0 }
    for slot = 1, MAX_SLOTS do
        restoreSlot(slot, p.actions and p.actions[slot], counts)
    end

    if mod.db.restoreBindings and p.bindings then
        restoreBindings(p.bindings)
    end

    if counts.skipped > 0 then
        ns:Print(L["Vulslot '%s' loaded: %d slots set, %d cleared, |cffff8800%d skipped|r (unknown spell / missing item or macro)."],
            name, counts.placed, counts.cleared, counts.skipped)
    else
        ns:Print(L["Vulslot '%s' loaded: %d slots set, %d cleared."],
            name, counts.placed, counts.cleared)
    end
end

-- =========================================================
-- Lifecycle (pure on-demand module: nothing to wire up)
-- =========================================================
function mod:OnEnable() end
function mod:OnDisable() end

-- =========================================================
-- Options
-- =========================================================
local newName  = ""
local selected = nil

local function sortedProfileNames()
    local names = {}
    for n in pairs(mod.db.profiles) do names[#names + 1] = n end
    table.sort(names)
    return names
end

local function rebuildPage()
    if ns.UI and ns.UI.BuildOptionsPage then
        ns.UI:BuildOptionsPage("vulslot")
    end
end

function mod:GetOptions()
    local names = sortedProfileNames()
    if selected and not mod.db.profiles[selected] then selected = nil end
    if not selected and names[1] then selected = names[1] end

    local values = {}
    for _, n in ipairs(names) do
        local p = mod.db.profiles[n]
        local suffix = (p and p.class) and (" |cff888888(" .. p.class .. ")|r") or ""
        values[#values + 1] = { value = n, text = n .. suffix }
    end

    local function doSave()
        local n = newName:gsub("^%s+", ""):gsub("%s+$", "")
        if n == "" then
            ns:Print(L["Please enter a profile name first."])
            return
        end
        saveProfile(n)
        newName  = ""
        selected = n
        rebuildPage()
    end

    local items = {
        { type = "header", text = L["Vulslot"] },
        { type = "desc",
          text = L["|cffaaaaaaSaves your complete bar setup (all action slots, macros, keybindings) as a named profile and restores it with one click — e.g. PvP and Raid layouts, or to copy a setup to a twink (account-wide storage).|r"] },
        { type = "spacer", height = 6 },

        { type = "header", text = L["Save"] },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "editbox", label = L["Name"], width = 260, editWidth = 180,
              commitOnFocusLost = true,
              get = function() return newName end,
              set = function(_, v) newName = tostring(v or "") end,
              onEnter = function() doSave() end },
            { type = "button", label = L["Save current setup"], width = 180, primary = true,
              onClick = function() doSave() end },
        } },
        { type = "spacer", height = 8 },

        { type = "header", text = L["Load"] },
    }

    if #values == 0 then
        items[#items + 1] = { type = "desc",
            text = L["|cff888888No profiles saved yet.|r"] }
    else
        items[#items + 1] = { type = "dropdown", label = L["Profile"], width = 260,
            values = values,
            get = function() return selected end,
            set = function(_, v) selected = v end }
        items[#items + 1] = { type = "toggle", label = L["Also restore macros"],
            tooltip = L["Rewrites saved macros by name (existing ones are updated, missing ones created)."],
            get = function() return mod.db.restoreMacros end,
            set = function(_, v) mod.db.restoreMacros = v end }
        items[#items + 1] = { type = "toggle", label = L["Also restore keybindings"],
            get = function() return mod.db.restoreBindings end,
            set = function(_, v) mod.db.restoreBindings = v end }
        items[#items + 1] = { type = "spacer", height = 4 }
        items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Load profile"], width = 150, primary = true,
              onClick = function()
                  if selected then loadProfile(selected) end
              end },
            { type = "button", label = L["Overwrite with current setup"], width = 220,
              tooltip = L["Replaces the selected profile with your current bars/macros/bindings."],
              onClick = function()
                  if selected then saveProfile(selected) end
              end },
            { type = "button", label = L["Delete"], width = 110,
              onClick = function()
                  if selected then
                      mod.db.profiles[selected] = nil
                      ns:Print(L["Vulslot profile '%s' deleted."], selected)
                      selected = nil
                      rebuildPage()
                  end
              end },
        } }
    end

    return items
end
