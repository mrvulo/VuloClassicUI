-- =========================================================
-- VuloClassicUI / Modules / QoL (container)
-- Consolidates every "QoL"-group module into ONE tabbed sidebar entry
-- (except the per-class "Class Specific" module, which stays separate).
--
-- How it works:
--   * At file load (this file is listed LAST so every sub-module is already
--     registered) we collect the QoL modules into mod.tabs and stamp each with
--     parentTab = "qol" so the sidebar hides them (UI/Sidebar.lua skips it).
--   * GetOptions(tabId) delegates to the picked sub-module (prepending its
--     description). Each tab carries its own power button (UI:BuildTabsForModule),
--     so per-module enable/disable lives on the tab itself.
--   * UI:BuildOptionsPage redirects a hidden sub-module's refresh calls to
--     this container + the right tab, so their rebuildPage keeps working.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("qol", {
    name        = "Quality of Life",
    group       = "QoL",
    noToggle    = true,
    description = "",   -- per-tab description is shown instead
    defaults    = { enabled = true },
})

-- Build the tab list now (all sub-modules are registered by this point).
-- "General" first, then the rest in registration order.
mod.tabs = {}
local function addTab(key, sub)
    mod.tabs[#mod.tabs + 1] = { id = key, label = sub.name }
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

-- Delegate the picked tab to its sub-module's options.
function mod:GetOptions(tabId)
    local sub = tabId and ns.modules[tabId]
    if not sub or not sub.GetOptions then
        return { { type = "desc", text = L["|cffaaaaaaPick a tab above.|r"] } }
    end

    local items = {}
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
