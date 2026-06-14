-- =========================================================
-- VuloClassicUI / Core / Container
-- Factory for "group container" modules: collapse every module in a sidebar
-- group into ONE tabbed sidebar entry. Each tab shows an enable/disable switch
-- first, then that sub-module's own options. The container's sidebar power
-- button is a MASTER switch that toggles every sub-module at once (remembering
-- each module's prior state, so turning it back on restores what was on).
--
-- Used by Modules/QoL.lua and Modules/Bugfixes.lua. A container file MUST be
-- listed in the .toc AFTER every module in its group, so the factory sees them
-- all when it scans ns.moduleOrder.
-- =========================================================
local _, ns = ...
local L = ns.L

-- opts = {
--   key          : container module key            (e.g. "qol")
--   name         : display name / English L key     (e.g. "Quality of Life")
--   group        : sidebar group to consolidate      (e.g. "QoL")
--   sidebarOrder : optional in-group ordering (lower = higher up)
--   firstKey     : optional module key forced to the first tab (e.g. "miscqol")
--   exclude      : optional { [key]=true } of group members to keep separate
-- }
function ns:MakeGroupContainer(opts)
    local mod = ns:RegisterModule(opts.key, {
        name         = opts.name,
        group        = opts.group,
        sidebarOrder = opts.sidebarOrder,
        description  = "",   -- per-tab description is shown instead
        defaults     = { enabled = true },
    })

    -- Build the tab list now (every sub-module is registered by this point).
    mod.tabs    = {}
    mod.subKeys = {}   -- flat list of consolidated keys (for the master switch)
    local exclude = opts.exclude or {}
    local function addTab(key, sub)
        mod.tabs[#mod.tabs + 1]       = { id = key, label = sub.name }
        mod.subKeys[#mod.subKeys + 1] = key
        sub.parentTab = opts.key
    end

    if opts.firstKey then
        local f = ns.modules[opts.firstKey]
        if f and f.group == opts.group then addTab(opts.firstKey, f) end
    end
    for _, key in ipairs(ns.moduleOrder) do
        local sub = ns.modules[key]
        if sub and sub.group == opts.group
           and key ~= opts.key and key ~= opts.firstKey and not exclude[key] then
            addTab(key, sub)
        end
    end

    -- =========================================================
    -- Master switch (sidebar power button on the container row)
    -- =========================================================
    -- "On" if at least one sub-module is enabled.
    function mod.toggleGet()
        for _, key in ipairs(mod.subKeys) do
            if ns:IsModuleEnabled(key) then return true end
        end
        return false
    end

    -- Turn every sub-module on/off at once. When switching OFF we remember each
    -- module's state so switching back ON restores exactly that (instead of
    -- force-enabling modules that were intentionally off).
    function mod.toggleSet(v)
        -- per-character saved-state memory (enable is a per-char preference)
        local store
        if VuloClassicUICharDB then
            VuloClassicUICharDB.containerSaved = VuloClassicUICharDB.containerSaved or {}
            store = VuloClassicUICharDB.containerSaved
        end
        if v then
            local saved = store and store[opts.key]
            for _, key in ipairs(mod.subKeys) do
                local want = (saved == nil) and true or (saved[key] and true or false)
                ns:ToggleModule(key, want, true)   -- silent: one summary below
            end
            if store then store[opts.key] = nil end
            ns:Print(L["%s: modules restored."], L[opts.name])
        else
            local saved = {}
            for _, key in ipairs(mod.subKeys) do
                saved[key] = ns:IsModuleEnabled(key)
                ns:ToggleModule(key, false, true)  -- silent: one summary below
            end
            if store then store[opts.key] = saved end
            ns:Print(L["%s: all modules off. /reload recommended."], L[opts.name])
        end
        -- reflect the new state in the sidebar + the open options page
        if ns.UI then
            if ns.UI.RefreshSidebarStates then ns.UI:RefreshSidebarStates() end
            if ns.UI.currentModule == opts.key and ns.UI.currentTab then
                ns.UI:BuildOptionsPage(opts.key, ns.UI.currentTab)
            end
        end
    end

    -- =========================================================
    -- Per-tab options: enable switch FIRST, then the sub's own options
    -- =========================================================
    function mod:GetOptions(tabId)
        local sub = tabId and ns.modules[tabId]
        if not sub then
            return { { type = "desc", text = L["|cffaaaaaaPick a tab above.|r"] } }
        end

        local items = {}

        -- Enable/disable switch first, so every tab opens with its on/off control.
        items[#items + 1] = {
            type = "toggle", label = L["Module enabled"],
            get = function() return ns:IsModuleEnabled(tabId) end,
            set = function(_, v)
                ns:ToggleModule(tabId, v)
                if ns.UI then
                    if ns.UI.RefreshSidebarStates then ns.UI:RefreshSidebarStates() end
                    ns.UI:BuildOptionsPage(opts.key, tabId)
                end
            end,
        }
        items[#items + 1] = { type = "spacer", height = 8 }

        if sub.description and sub.description ~= "" then
            items[#items + 1] = { type = "desc", text = L[sub.description] }
            items[#items + 1] = { type = "spacer", height = 6 }
        end

        -- guard: a broken sub-module GetOptions must not take down the whole page
        if sub.GetOptions then
            local ok, subItems = pcall(function() return sub:GetOptions() end)
            if ok and type(subItems) == "table" then
                for _, it in ipairs(subItems) do items[#items + 1] = it end
            else
                items[#items + 1] = { type = "desc", text = L["|cffff5555This tab failed to load.|r"] }
            end
        end
        return items
    end

    return mod
end
