-- =========================================================
-- VuloClassicUI / Modules / VulTraining
-- "What's training": lists the abilities you can still learn from your class
-- trainer, grouped by level. The game only exposes this data at the trainer,
-- so we scan it once on TRAINER_SHOW and cache it per class (account-wide).
-- Shows up as a tab inside the Quality of Life container.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("vultraining", {
    name        = "VulTraining",
    group       = "QoL",
    description = "Lists the abilities you can still learn from your class trainer, grouped by level. Open your trainer once to fill / refresh the list.",
    defaults = {
        enabled = true,
        classes = {},   -- classFile -> { { name, rank, level, avail }, ... }
    },
})

local function classKey()
    local _, k = UnitClass("player")
    return k or "UNKNOWN"
end

-- =========================================================
-- Scan the class trainer (current + future abilities)
-- =========================================================
local function scanTrainer()
    if not GetNumTrainerServices then return end
    -- Only class trainers — profession trainers also fire TRAINER_SHOW but list
    -- recipes, not levelled class abilities.
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end

    -- Temporarily show every category so we also capture not-yet-available
    -- (future) abilities, then restore the player's own filter choices.
    local getF, setF = GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter
    local fa, fu, fs
    if getF then fa, fu, fs = getF("available"), getF("unavailable"), getF("used") end
    if setF then
        setF("available", 1); setF("unavailable", 1); setF("used", 0)
    end

    local list = {}
    for i = 1, (GetNumTrainerServices() or 0) do
        local name, rank, category = GetTrainerServiceInfo(i)
        if name and name ~= "" and category ~= "header" and category ~= "used" then
            local lvl = (GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)) or 0
            list[#list + 1] = {
                name  = name,
                rank  = rank,
                level = lvl or 0,
                avail = (category == "available"),
            }
        end
    end

    if setF then
        setF("available", fa and 1 or 0); setF("unavailable", fu and 1 or 0); setF("used", fs and 1 or 0)
    end

    if #list > 0 then
        mod.db.classes = mod.db.classes or {}
        mod.db.classes[classKey()] = list
        if ns.UI and ns.UI.IsModuleActive and ns.UI:IsModuleActive("vultraining") then
            ns.UI:BuildOptionsPage("vultraining", ns.UI.currentTab)
        end
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    ns:RegisterEvent("TRAINER_SHOW", scanTrainer)
end

function mod:OnDisable()
    ns:UnregisterEvent("TRAINER_SHOW", scanTrainer)
end

-- =========================================================
-- Options (the tab content)
-- =========================================================
local function fmtEntry(e)
    local r = (e.rank and e.rank ~= "") and (" |cff888888(" .. e.rank .. ")|r") or ""
    return "• " .. (e.name or "?") .. r
end

function mod:GetOptions()
    local items = {
        { type = "desc",
          text = L["|cffaaaaaaAbilities you can still learn from your class trainer. Open your trainer once to fill or refresh this list.|r"] },
    }

    local data = mod.db.classes and mod.db.classes[classKey()]
    if not data or #data == 0 then
        items[#items + 1] = { type = "desc",
            text = L["|cffffd200No data yet — open your class trainer once.|r"] }
        return items
    end

    local lvl = (UnitLevel and UnitLevel("player")) or 0
    local available, upcoming = {}, {}
    for _, e in ipairs(data) do
        if e.avail or e.level <= lvl then available[#available + 1] = e else upcoming[#upcoming + 1] = e end
    end
    table.sort(available, function(a, b) return (a.name or "") < (b.name or "") end)
    table.sort(upcoming, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return (a.name or "") < (b.name or "")
    end)

    if #available > 0 then
        items[#items + 1] = { type = "header", text = L["Available now"] }
        for _, e in ipairs(available) do
            items[#items + 1] = { type = "desc", text = "|cff44ff44" .. fmtEntry(e) .. "|r" }
        end
    end

    if #upcoming > 0 then
        items[#items + 1] = { type = "spacer", height = 6 }
        items[#items + 1] = { type = "header", text = L["Upcoming"] }
        local lastLvl
        for _, e in ipairs(upcoming) do
            if e.level ~= lastLvl then
                lastLvl = e.level
                items[#items + 1] = { type = "desc", text = string.format(L["|cff9b6cffLevel %d|r"], e.level) }
            end
            items[#items + 1] = { type = "desc", text = "|cffcccccc" .. fmtEntry(e) .. "|r" }
        end
    end

    return items
end
