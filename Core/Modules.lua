-- =========================================================
-- VuloClassicUI / Core / Modules
-- Modul-Registry. Jedes Modul ruft ns:RegisterModule(key, def) auf.
--
-- def = {
--   name        = "Hübscher Anzeigename",
--   description = "Was macht das Modul",
--   defaults    = { enabled = true, ... },          -- merged in db.profile.modules[key]
--   OnEnable    = function(self) ... end,           -- self = module, hat self.db
--   OnDisable   = function(self) ... end,
--   GetOptions  = function(self) return {...} end,  -- liefert Options-Definition (siehe OptionsBuilder)
-- }
-- =========================================================
local _, ns = ...

function ns:RegisterModule(key, def)
    if ns.modules[key] then
        ns:Print("WARN: Modul '%s' bereits registriert.", key)
        return ns.modules[key]
    end

    def.key      = key
    def.name     = def.name or key
    def.group    = def.group or "Core"   -- Sidebar-Gruppe (z.B. "Core", "QoL", "Reskin")
    def.defaults = def.defaults or {}
    -- Jedes Modul kriegt automatisch ein "enabled" Flag im Default
    if def.defaults.enabled == nil then
        def.defaults.enabled = true
    end

    ns.modules[key] = def
    table.insert(ns.moduleOrder, key)

    return def
end

-- =========================================================
-- Wird in Init.lua aufgerufen, nachdem DB initialisiert ist.
-- =========================================================
function ns:EnableModules()
    for _, key in ipairs(ns.moduleOrder) do
        local mod = ns.modules[key]
        if mod.db and mod.db.enabled then
            ns:SafeEnable(mod)
        end
    end
end

function ns:SafeEnable(mod)
    if mod._enabled then return end
    if not mod.OnEnable then
        mod._enabled = true
        return
    end
    local ok, err = pcall(mod.OnEnable, mod)
    if not ok then
        ns:Print("|cffff5555Fehler beim Aktivieren von Modul '%s':|r %s", mod.name, tostring(err))
        return
    end
    mod._enabled = true
    ns:Debug("Modul aktiviert: %s", mod.name)
end

function ns:SafeDisable(mod)
    if not mod._enabled then return end
    if mod.OnDisable then
        local ok, err = pcall(mod.OnDisable, mod)
        if not ok then
            ns:Print("|cffff5555Fehler beim Deaktivieren von '%s':|r %s", mod.name, tostring(err))
        end
    end
    mod._enabled = false
end

function ns:ToggleModule(key, state)
    local mod = ns.modules[key]
    if not mod then return end
    mod.db.enabled = state and true or false
    if mod.db.enabled then
        ns:SafeEnable(mod)
    else
        ns:SafeDisable(mod)
        -- Viele Hooks lassen sich zur Laufzeit nicht entfernen → ReloadUI empfehlen
        ns:Print("Modul '%s' deaktiviert. /reload für vollständige Wirkung empfohlen.", mod.name)
    end
end
