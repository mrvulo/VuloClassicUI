-- =========================================================
-- VuloClassicUI / VulTraining / data shim
-- The per-class spell tables (Modules/VulTraining/Classes/*.lua) are factual
-- WoW spell-id data. They expect a small namespace with currentClass +
-- Race/Faction filters + an overridden-rank helper, and they assign
-- SpellsByLevel onto it. This file provides that namespace as ns.VTData so the
-- data files load unchanged (only their header line was repointed here).
-- =========================================================
local _, ns = ...

local tinsert, ipairs, pairs = table.insert, ipairs, pairs

local D = {}
ns.VTData = D

D.currentClass = select(2, UnitClass("player"))

local function filterByLevel(spellsByLevel, pred)
    local out = {}
    for level, spells in pairs(spellsByLevel) do
        out[level] = {}
        for _, spell in ipairs(spells) do
            if pred(spell) == true then tinsert(out[level], spell) end
        end
    end
    return out
end

local playerFaction = UnitFactionGroup("player")
function D.FactionFilter(spellsByLevel)
    return filterByLevel(spellsByLevel, function(spell)
        return spell.faction == nil or spell.faction == playerFaction
    end)
end

local playerRace = select(3, UnitRace("player"))
function D.RaceFilter(spellsByLevel)
    return filterByLevel(spellsByLevel, function(spell)
        if spell.race == nil and spell.races == nil then return true end
        if spell.races == nil then return spell.race == playerRace end
        return spell.races[1] == playerRace or spell.races[2] == playerRace
    end)
end

-- varargs: each arg is a list of spell ids where a later id fully overrides an
-- earlier rank (warrior/rogue style). Used to detect "previously learned".
function D:AddOverriddenSpells(...)
    local map = {}
    for _, ids in ipairs({ ... }) do
        for _, id in ipairs(ids) do map[id] = ids end
    end
    self.overriddenSpellsMap = map
end
