-- Priest DoT set (class data for the shared DoT tracker in Modules/ClassTools).
local _, ns = ...

local csMod = ns.modules and ns.modules.vtmanadisplay
if not csMod or not csMod.RegisterDotSet then return end

-- id is the base rank; the resolved name filters every rank.
csMod:RegisterDotSet("PRIEST", {
    { key = "swp", id = 589,   toggle = "showSWP", label = "Shadow Word: Pain", school = 6, color = { 0.62, 0.40, 0.94 }, base = 1236, coef = 1.10 },
    { key = "vt",  id = 34917, toggle = "showVT",  label = "Vampiric Touch",    school = 6, color = { 0.85, 0.30, 0.85 }, base = 850,  coef = 1.00 },
    { key = "dp",  id = 2944,  toggle = "showDP",  label = "Devouring Plague",  school = 6, color = { 0.40, 0.78, 0.36 }, base = 1216, coef = 1.00 },
})
