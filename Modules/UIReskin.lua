-- =========================================================
-- VuloClassicUI / Modules / UIReskin (container)
-- Consolidates every "UI Reskin"-group module into ONE tabbed sidebar entry
-- (Addon Skins, Character Panel, Dark Skin, Chat, Friends List, Minimap) — the
-- same pattern QoL and Bugfixes already use.
--
-- All the wiring lives in Core/Container.lua (ns:MakeGroupContainer). This file
-- just names the group to fold in. Listed LAST in the .toc (with the other
-- containers) so every UI Reskin sub-module is already registered when the
-- factory scans ns.moduleOrder.
-- =========================================================
local _, ns = ...

ns:MakeGroupContainer({
    key   = "uireskin",
    name  = "Interface Skins",   -- distinct from the "UI Reskin" group header
    group = "UI Reskin",
})
