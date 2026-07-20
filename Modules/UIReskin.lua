-- UIReskin (container): folds every "UI Reskin"-group module into one tabbed sidebar entry.
-- Wiring lives in Core/Container.lua (ns:MakeGroupContainer); this file just names the group.
-- Must stay listed LAST in the .toc (with the other containers) so every UI Reskin
-- sub-module is already registered when the factory scans ns.moduleOrder.
local _, ns = ...

ns:MakeGroupContainer({
    key   = "uireskin",
    name  = "Interface Skins",   -- distinct from the "UI Reskin" group header
    group = "UI Reskin",
})
