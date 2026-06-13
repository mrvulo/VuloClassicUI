-- =========================================================
-- VuloClassicUI / Modules / Classes / Priest
-- Priest-specific data for the "Class Specific" module (Priest tab).
-- Registers the Shadow DoT set into the shared DoT-tracker engine.
--
-- NOTE: the Vampiric Touch mana tracker itself stays in the container module
-- (VTManaDisplay.lua) on purpose — it shares the SINGLE combat-log pass with
-- the DoT snapshots, and the combat log is the hottest event in the game.
-- Splitting it into a second handler would destructure every log line twice.
-- Class files contribute DATA; the shared engine is never duplicated.
-- =========================================================
local _, ns = ...

local csMod = ns.modules and ns.modules.vtmanadisplay
if not csMod or not csMod.RegisterDotSet then return end

-- key:    unique across classes (snapshot / row keying)
-- id:     base-rank spell id (name filters every rank)
-- toggle: db.dots flag (defaults live in the container's db schema)
-- school: GetSpellBonusDamage index (6 = Shadow)
csMod:RegisterDotSet("PRIEST", {
    { key = "swp", id = 589,   toggle = "showSWP", label = "Shadow Word: Pain", school = 6, color = { 0.62, 0.40, 0.94 }, base = 1236, coef = 1.10 },
    { key = "vt",  id = 34917, toggle = "showVT",  label = "Vampiric Touch",    school = 6, color = { 0.85, 0.30, 0.85 }, base = 850,  coef = 1.00 },
    { key = "dp",  id = 2944,  toggle = "showDP",  label = "Devouring Plague",  school = 6, color = { 0.40, 0.78, 0.36 }, base = 1216, coef = 1.00 },
})
