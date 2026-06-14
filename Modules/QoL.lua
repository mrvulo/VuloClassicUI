-- =========================================================
-- VuloClassicUI / Modules / QoL (container)
-- Consolidates every "QoL"-group module into ONE tabbed sidebar entry
-- (except the per-class "Class Specific" module, which stays separate).
--
-- How it works:
--   * At file load (this file is listed LAST so every sub-module is already
--     registered) we collect the QoL modules into mod.tabs and stamp each with
--     parentTab = "qol" so the sidebar hides them (UI/Sidebar.lua skips it).
--   * GetOptions(tabId) delegates to the picked sub-module: an enable/disable
--     switch FIRST, then the sub's description + its own options.
--   * The sidebar power button on the "Quality of Life" row is a MASTER switch:
--     it turns every consolidated sub-module on/off at once (remembering the
--     per-module state so turning it back on restores what was on before).
--   * UI:BuildOptionsPage redirects a hidden sub-module's refresh calls to
--     this container + the right tab, so their rebuildPage keeps working.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("qol", {
    name        = "Quality of Life",
    group       = "QoL",
    sidebarOrder = -10,  -- float above "Class Specific" in the QoL group
    description = "",   -- per-tab description is shown instead
    defaults    = { enabled = true },
})

-- Build the tab list now (all sub-modules are registered by this point).
-- "General" first, then the rest in registration order.
mod.tabs    = {}
mod.subKeys = {}   -- flat list of consolidated module keys (for the master switch)
local function addTab(key, sub)
    mod.tabs[#mod.tabs + 1]       = { id = key, label = sub.name }
    mod.subKeys[#mod.subKeys + 1] = key
    sub.parentTab = "qol"
end

local g = ns.modules.miscqol
if g and g.group == "QoL" then addTab("miscqol", g) end

for _, key in ipairs(ns.moduleOrder) do
    local sub = ns.modules[key]
    if sub and sub.group == "QoL"
       and key ~= "qol" and key ~= "vtmanadisplay" and key ~= "miscqol" then
        addTab(key, sub)
    end
end

-- =========================================================
-- Master switch (sidebar power button on the QoL row)
-- =========================================================
-- "On" if at least one sub-module is enabled.
function mod.toggleGet()
    for _, key in ipairs(mod.subKeys) do
        local sub = ns.modules[key]
        if sub and sub.db and sub.db.enabled then return true end
    end
    return false
end

-- Turn every sub-module on/off at once. When switching OFF we remember each
-- module's current state so switching back ON restores exactly that (instead
-- of force-enabling modules that were intentionally off, e.g. Auto Item Buy).
function mod.toggleSet(v)
    mod.db = mod.db or {}
    if v then
        local saved = mod.db._savedStates
        for _, key in ipairs(mod.subKeys) do
            local want = (saved == nil) and true or (saved[key] and true or false)
            ns:ToggleModule(key, want, true)  -- silent: one summary below
        end
        mod.db._savedStates = nil
        ns:Print(L["Quality of Life: modules restored."])
    else
        local saved = {}
        for _, key in ipairs(mod.subKeys) do
            local sub = ns.modules[key]
            saved[key] = (sub and sub.db and sub.db.enabled) and true or false
            ns:ToggleModule(key, false, true)  -- silent: one summary below
        end
        mod.db._savedStates = saved
        ns:Print(L["Quality of Life: all modules off. /reload recommended."])
    end
    -- reflect the new state in the sidebar + the open options page
    if ns.UI then
        if ns.UI.RefreshSidebarStates then ns.UI:RefreshSidebarStates() end
        if ns.UI.currentModule == "qol" and ns.UI.currentTab then
            ns.UI:BuildOptionsPage("qol", ns.UI.currentTab)
        end
    end
end

-- Delegate the picked tab to its sub-module's options.
function mod:GetOptions(tabId)
    local sub = tabId and ns.modules[tabId]
    if not sub or not sub.GetOptions then
        return { { type = "desc", text = L["|cffaaaaaaPick a tab above.|r"] } }
    end

    local items = {}

    -- Enable/disable switch FIRST, so every tab opens with its on/off control.
    items[#items + 1] = {
        type = "toggle", label = L["Module enabled"],
        get = function() return sub.db and sub.db.enabled end,
        set = function(_, v)
            ns:ToggleModule(tabId, v)
            if ns.UI then
                if ns.UI.RefreshSidebarStates then ns.UI:RefreshSidebarStates() end
                ns.UI:BuildOptionsPage("qol", tabId)
            end
        end,
    }
    items[#items + 1] = { type = "spacer", height = 8 }

    if sub.description and sub.description ~= "" then
        items[#items + 1] = { type = "desc", text = L[sub.description] }
        items[#items + 1] = { type = "spacer", height = 6 }
    end

    -- guard: a broken sub-module GetOptions must not take down the whole page
    local ok, subItems = pcall(function() return sub:GetOptions() end)
    if ok and type(subItems) == "table" then
        for _, it in ipairs(subItems) do items[#items + 1] = it end
    else
        items[#items + 1] = { type = "desc", text = L["|cffff5555This tab failed to load.|r"] }
    end
    return items
end
