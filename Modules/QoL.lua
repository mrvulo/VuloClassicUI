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
