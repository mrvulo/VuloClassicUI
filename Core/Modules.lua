-- =========================================================
-- VuloClassicUI / Core / Modules
-- Module registry. Each module calls ns:RegisterModule(key, def).
--
-- def = {
--   name        = "Nice display name",
--   description = "What the module does",
--   defaults    = { enabled = true, ... },          -- merged into db.profile.modules[key]
--   OnEnable    = function(self) ... end,           -- self = module, has self.db
--   OnDisable   = function(self) ... end,
--   GetOptions  = function(self) return {...} end,  -- returns options definition (see OptionsBuilder)
-- }
-- =========================================================
local _, ns = ...
local L = ns.L

function ns:RegisterModule(key, def)
    if ns.modules[key] then
        ns:Print(L["WARN: Module '%s' already registered."], key)
        return ns.modules[key]
    end

    def.key      = key
    def.name     = def.name or key
    def.group    = def.group or "Core"   -- Sidebar group (e.g. "Core", "QoL", "Reskin")
    def.defaults = def.defaults or {}
    -- Every module automatically gets an "enabled" flag in the defaults
    if def.defaults.enabled == nil then
        def.defaults.enabled = true
    end

    ns.modules[key] = def
    table.insert(ns.moduleOrder, key)

    return def
end

-- =========================================================
-- Called in Init.lua after DB is initialized.
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
        ns:Print(L["|cffff5555Error enabling module '%s':|r %s"], mod.name, tostring(err))
        return
    end
    mod._enabled = true
    ns:Debug("Module enabled: %s", mod.name)
end

function ns:SafeDisable(mod)
    if not mod._enabled then return end
    if mod.OnDisable then
        local ok, err = pcall(mod.OnDisable, mod)
        if not ok then
            ns:Print(L["|cffff5555Error disabling '%s':|r %s"], mod.name, tostring(err))
        end
    end
    mod._enabled = false
end

function ns:ToggleModule(key, state, silent)
    local mod = ns.modules[key]
    if not mod then return end
    mod.db.enabled = state and true or false
    if mod.db.enabled then
        ns:SafeEnable(mod)
    else
        ns:SafeDisable(mod)
        -- Many hooks can't be removed at runtime -> recommend ReloadUI.
        -- silent: bulk callers (e.g. the QoL master switch) print one summary.
        if not silent then
            ns:Print(L["Module '%s' disabled. /reload recommended for full effect."], mod.name)
        end
    end
end
