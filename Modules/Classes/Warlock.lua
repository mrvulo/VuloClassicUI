-- =========================================================
-- VuloClassicUI / Modules / Classes / Warlock
-- Warlock-specific data for the "Class Specific" module (Warlock tab).
-- Registers the Affliction / Destruction DoT set into the shared DoT-tracker
-- engine — the container builds the Warlock tab's options generically from it.
-- Class files contribute DATA only; the engine is shared, never duplicated.
-- =========================================================
local _, ns = ...
local L = ns.L

local csMod = ns.modules and ns.modules.vtmanadisplay
if not csMod or not csMod.RegisterDotSet then return end

-- key:    unique across classes (snapshot / row keying)
-- id:     base-rank spell id (name filters every rank)
-- toggle: db.dots flag (defaults live in the container's db schema)
-- school: GetSpellBonusDamage index (6 = Shadow, 3 = Fire)
csMod:RegisterDotSet("WARLOCK", {
    { key = "corr",   id = 172,   toggle = "showCorruption", label = "Corruption",          school = 6, color = { 0.55, 0.35, 0.85 }, base = 900,  coef = 0.94 },
    { key = "coa",    id = 980,   toggle = "showCoA",        label = "Curse of Agony",      school = 6, color = { 0.45, 0.30, 0.70 }, base = 1356, coef = 1.20 },
    { key = "ua",     id = 30108, toggle = "showUA",         label = "Unstable Affliction", school = 6, color = { 0.72, 0.42, 0.96 }, base = 1050, coef = 1.20 },
    { key = "siphon", id = 18265, toggle = "showSiphon",     label = "Siphon Life",         school = 6, color = { 0.40, 0.66, 0.42 }, base = 630,  coef = 1.00 },
    { key = "immo",   id = 348,   toggle = "showImmolate",   label = "Immolate",            school = 3, color = { 0.92, 0.46, 0.20 }, base = 615,  coef = 0.65 },
    { key = "codoom", id = 603,   toggle = "showCoDoom",     label = "Curse of Doom",       school = 6, color = { 0.72, 0.22, 0.22 }, base = 4200, coef = 2.00 },
}, {
    desc = L["|cffaaaaaaTracks your Warlock DoTs (Corruption, Curse of Agony, Unstable Affliction, Siphon Life, Immolate, Curse of Doom) on the target, with the same recast-snapshot readout as the Priest tracker.|r"],
})
