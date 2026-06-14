-- =========================================================
-- VuloClassicUI / Modules / Bugfixes (container)
-- Consolidates every "Bugfixes"-group module into ONE tabbed sidebar entry.
--
-- All the wiring lives in Core/Container.lua (ns:MakeGroupContainer). This file
-- just folds in the group. Listed LAST in the .toc so every Fix* sub-module is
-- already registered when the factory scans ns.moduleOrder.
-- =========================================================
local _, ns = ...

ns:MakeGroupContainer({
    key   = "bugfixes",
    name  = "Bug Fixes",   -- distinct from the "Bugfixes" group header
    group = "Bugfixes",
})
