-- Module registry. def.defaults is merged into db.profile.modules[key]; OnEnable/OnDisable/GetOptions take the module as self.
local _, ns = ...
local L = ns.L

function ns:RegisterModule(key, def)
    if ns.modules[key] then
        ns:Print(L["WARN: Module '%s' already registered."], key)
        return ns.modules[key]
    end

    def.key      = key
    def.name     = def.name or key
    def.group    = def.group or "Core"
    def.defaults = def.defaults or {}
    if def.defaults.enabled == nil then
        def.defaults.enabled = true
    end

    ns.modules[key] = def
    table.insert(ns.moduleOrder, key)

    return def
end

-- Enable state is PER CHARACTER (CharDB.modEnabled[key]), falling back to the shared profile default.
function ns:IsModuleEnabled(key)
    local mod = ns.modules[key]
    if not mod then return false end
    local ov = VuloClassicUICharDB and VuloClassicUICharDB.modEnabled
    if ov and ov[key] ~= nil then return ov[key] end
    return (mod.db and mod.db.enabled) and true or false
end

function ns:SetModuleEnabledPref(key, state)
    if not VuloClassicUICharDB then return end
    VuloClassicUICharDB.modEnabled = VuloClassicUICharDB.modEnabled or {}
    VuloClassicUICharDB.modEnabled[key] = state and true or false
end

function ns:EnableModules()
    for _, key in ipairs(ns.moduleOrder) do
        local mod = ns.modules[key]
        if mod and ns:IsModuleEnabled(key) then
            ns:SafeEnable(mod)
        end
    end
end

-- Both flags mean "this module is on" and must always agree. They used to be
-- set at different moments - active before OnEnable, _enabled only after it
-- returned - so anything checked during OnEnable read false and skipped its
-- work. That cost five features across four modules before anyone noticed, and
-- every one of them looked like an unrelated bug. Setting both up front also
-- makes the guard above a real re-entrancy guard for the duration of OnEnable.
function ns:SafeEnable(mod)
    if mod._enabled then return end
    mod.active   = true
    mod._enabled = true
    if not mod.OnEnable then return end
    local ok, err = pcall(mod.OnEnable, mod)
    if not ok then
        mod.active, mod._enabled = false, false
        ns:Print(L["|cffff5555Error enabling module '%s':|r %s"], mod.name, tostring(err))
        return
    end
    ns:Debug("Module enabled: %s", mod.name)
end

function ns:SafeDisable(mod)
    if not mod._enabled then return end
    mod.active = false
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
    state = state and true or false
    ns:SetModuleEnabledPref(key, state)
    if state then
        ns:SafeEnable(mod)
    else
        ns:SafeDisable(mod)
        -- Many hooks can't be removed at runtime -> recommend ReloadUI.
        if not silent then
            ns:Print(L["Module '%s' disabled. /reload recommended for full effect."], mod.name)
        end
    end
end
