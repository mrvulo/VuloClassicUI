-- =========================================================
-- VuloClassicUI / Modules / Pages (merged with QoL container)
-- AUTO-MERGED file. Each former module is wrapped in an isolated
-- IIFE so its file-level locals and any top-level early-return stay
-- self-contained. Modules communicate through the shared ns table.
-- =========================================================

-- ============================================================
-- merged from: Pages.lua
-- ============================================================
(function(...)
-- =========================================================
-- VuloClassicUI / Modules / Pages
-- Sidebar consolidation: related modules are grouped onto a single "page" so
-- the sidebar stays short. A page is just a lightweight pseudo-module whose
-- GetOptions concatenates its members' options (each with its own enable
-- toggle right under its heading). The member modules are taken OUT of the
-- sidebar (group "_hidden") but stay fully registered and functional.
--
-- This needs no changes to the sidebar / options core: a page renders through
-- the exact same path as any other module. Loaded last so every member module
-- it references is already registered.
-- =========================================================
local _, ns = ...
local L = ns.L

-- An "Enabled" toggle bound to a member module's on/off state.
local function enableToggle(key, m)
    return {
        type  = "toggle",
        label = L["Enabled"],
        get   = function() return ns:IsModuleEnabled(key) end,
        set   = function(_, v) ns:ToggleModule(key, v) end,
    }
end

-- Append one member module's block (heading, enable toggle, then its options).
local function memberBlock(out, key)
    local m = ns.modules[key]
    if not m then return end
    out[#out + 1] = { type = "spacer", height = 14 }

    local items
    if m.GetOptions then
        local ok, res = pcall(m.GetOptions, m)
        if ok and type(res) == "table" then items = res end
    end

    if items and items[1] and items[1].type == "header" then
        -- Reuse the module's own heading as the section title.
        out[#out + 1] = items[1]
        out[#out + 1] = enableToggle(key, m)
        for i = 2, #items do out[#out + 1] = items[i] end
    else
        -- No leading heading: synthesize one from the module name.
        out[#out + 1] = { type = "header", text = L[m.name] }
        out[#out + 1] = enableToggle(key, m)
        if items then for _, it in ipairs(items) do out[#out + 1] = it end end
    end
end

local function makeGetOptions(members)
    return function()
        local out = {}
        for _, key in ipairs(members) do memberBlock(out, key) end
        return out
    end
end

-- =========================================================
-- Page definitions
-- =========================================================
local PAGES = {
    {
        key   = "pg_windows",
        name  = "Windows & Professions",
        icon  = "Interface\\Icons\\INV_Misc_Book_09",
        desc  = "Quest log, profession windows and the disenchant queue, all in one place.",
        members = { "questlog", "professionwindow", "disenchantqueue" },
    },
    {
        key   = "pg_gold",
        name  = "Gold & Vendors",
        icon  = "Interface\\Icons\\INV_Misc_Coin_01",
        desc  = "Gold tracking and automatic buying at vendors.",
        members = { "goldtracker", "autoitembuy" },
    },
    {
        key   = "pg_chat",
        name  = "Chat & Tooltips",
        icon  = "Interface\\Icons\\Spell_Holy_Silence",
        desc  = "Chat spam filter and tooltip IDs.",
        members = { "spamfilter", "tooltipids" },
    },
}

-- Master on/off for a page: "on" if any member is enabled; setting toggles all.
local function pageToggleGet(members)
    return function()
        for _, k in ipairs(members) do
            if ns:IsModuleEnabled(k) then return true end
        end
        return false
    end
end

local function pageToggleSet(members)
    return function(v)
        for _, k in ipairs(members) do ns:ToggleModule(k, v) end
        if ns.UI and ns.UI.RefreshSidebarStates then ns.UI:RefreshSidebarStates() end
    end
end

for _, page in ipairs(PAGES) do
    local def = ns:RegisterModule(page.key, {
        name        = page.name,
        group       = "QoL",
        description = page.desc,
        defaults    = { enabled = true },
        GetOptions  = makeGetOptions(page.members),
    })
    -- A master power button that enables/disables all of the page's members.
    def.toggleGet = pageToggleGet(page.members)
    def.toggleSet = pageToggleSet(page.members)

    -- Expose the page icon to the sidebar registry, and hide its members.
    if ns.MODULE_ICONS then ns.MODULE_ICONS[page.key] = page.icon end
    for _, mk in ipairs(page.members) do
        local m = ns.modules[mk]
        if m then
            m.group       = "_hidden"  -- out of the sidebar (still registered/working)
            m._pageMember = true       -- so option search lists it once (under the page)
        end
    end
end

end)(...);

-- ============================================================
-- merged from: QoL.lua
-- ============================================================
(function(...)
-- =========================================================
-- VuloClassicUI / Modules / QoL (container)
-- Consolidates every "QoL"-group module into ONE tabbed sidebar entry
-- (except the per-class "Class Specific" module, which stays separate).
--
-- All the wiring lives in Core/Container.lua (ns:MakeGroupContainer). This file
-- just describes WHICH modules to fold in. Listed LAST in the .toc so every QoL
-- sub-module is already registered when the factory scans ns.moduleOrder.
-- =========================================================
local _, ns = ...

ns:MakeGroupContainer({
    key          = "qol",
    name         = "Quality of Life",
    group        = "QoL",
    sidebarOrder = -10,                    -- float above "Class Specific"
    firstKey     = "miscqol",              -- "General" tab first
    exclude      = { vtmanadisplay = true }, -- Class Specific stays its own row
})

end)(...);
