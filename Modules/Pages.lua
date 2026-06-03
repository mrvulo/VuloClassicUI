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
        get   = function() return m.db and m.db.enabled end,
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

for _, page in ipairs(PAGES) do
    ns:RegisterModule(page.key, {
        name        = page.name,
        group       = "QoL",
        noToggle    = true,        -- enabling/disabling happens per member inside
        description = page.desc,
        defaults    = { enabled = true },
        GetOptions  = makeGetOptions(page.members),
    })
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
