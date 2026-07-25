-- Merged file: each section runs in its own IIFE so file-level locals stay isolated.

(function(...)
-- Must load last: every member module referenced below has to be registered already.
local _, ns = ...
local L = ns.L

local function enableToggle(key, m)
    return {
        type  = "toggle",
        label = L["Enabled"],
        get   = function() return ns:IsModuleEnabled(key) end,
        set   = function(_, v) ns:ToggleModule(key, v) end,
    }
end

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
        out[#out + 1] = items[1]
        out[#out + 1] = enableToggle(key, m)
        for i = 2, #items do out[#out + 1] = items[i] end
    else
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

local PAGES = {
    {
        key   = "pg_windows",
        name  = "Windows & Professions",
        icon  = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\pg_windows.tga",
        desc  = "Quest log, profession windows and the disenchant queue, all in one place.",
        members = { "questlog", "professionwindow", "disenchantqueue" },
    },
    {
        key   = "pg_gold",
        name  = "Gold & Vendors",
        icon  = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\pg_gold.tga",
        desc  = "Gold tracking and automatic buying at vendors.",
        members = { "goldtracker", "autoitembuy" },
    },
    {
        key   = "pg_chat",
        name  = "Chat & Tooltips",
        icon  = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules\\pg_chat.tga",
        desc  = "Chat spam filter and tooltip IDs.",
        members = { "spamfilter", "tooltipids" },
    },
}

local function pageToggleGet(members)
    return function()
        for _, k in ipairs(members) do
            if ns:IsModuleEnabled(k) then return true end
        end
        return false
    end
end

-- silent is passed by the group container, which prints one summary line of its
-- own instead of one per member.
local function pageToggleSet(members)
    return function(v, silent)
        for _, k in ipairs(members) do ns:ToggleModule(k, v, silent) end
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
    def.toggleGet = pageToggleGet(page.members)
    def.toggleSet = pageToggleSet(page.members)

    if ns.MODULE_ICONS then ns.MODULE_ICONS[page.key] = page.icon end
    for _, mk in ipairs(page.members) do
        local m = ns.modules[mk]
        if m then
            m.group       = "_hidden"  -- out of the sidebar (still registered/working)
            m._pageMember = true       -- option search lists it once, under the page
            m._pageKey    = page.key   -- lets UI:IsModuleActive find it on screen
        end
    end
end

end)(...);

(function(...)
-- Must be last in the .toc: the factory scans ns.moduleOrder at this point.
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
