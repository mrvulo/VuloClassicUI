-- =========================================================
-- VuloClassicUI / Core / Locale
-- Simple locale registry with English-fallback via metatable.
--
-- Pattern (matches WeakAuras / ElvUI style):
--   - Keys ARE the English text — no abstract identifiers
--   - L["Some text"] returns the translation for the current client locale
--   - If no translation exists, returns the key itself (= English default)
--   - Locales are registered via ns:RegisterLocale("deDE", { ... })
--
-- Usage in modules:
--   local L = ns.L
--   { type = "header", text = L["Behavior"] }
-- =========================================================
local _, ns = ...

-- Internal storage: { ["deDE"] = { ["English key"] = "Deutsche Übersetzung", ... }, ... }
ns.localeData = ns.localeData or {}

-- Supported locales — used by the GlobalSettings dropdown
ns.SUPPORTED_LOCALES = {
    { value = "auto", text = "Auto (client language)" },
    { value = "enUS", text = "English" },
    { value = "deDE", text = "Deutsch" },
}

-- Resolve the active locale LIVE on every lookup. This is critical because
-- SavedVariables (where the override lives) are NOT available when Core/Locale.lua
-- runs at file-load time — they only become available at ADDON_LOADED. A snapshot
-- taken at file-load would always be the client locale, ignoring the override.
-- A small cache avoids recomputing constantly; ns:RefreshLocale() clears it
-- (called from InitDB once SavedVariables are loaded, and on override change).
local _cachedLocale = nil

local function resolveLocale()
    if _cachedLocale then return _cachedLocale end
    local svDB = _G.VuloClassicUIDB
    if svDB and svDB.localeOverride
       and svDB.localeOverride ~= "auto"
       and svDB.localeOverride ~= "" then
        _cachedLocale = svDB.localeOverride
    else
        _cachedLocale = (GetLocale and GetLocale()) or "enUS"
    end
    return _cachedLocale
end

-- Clears the locale cache so the next lookup re-resolves (after SV load / change)
function ns:RefreshLocale()
    _cachedLocale = nil
end

-- The L table: fallback returns the key itself if no translation exists.
-- Lookup resolves the locale live, so translations are correct as soon as
-- the SavedVariables (and thus the override) are available.
ns.L = setmetatable({}, {
    __index = function(_, key)
        local data = ns.localeData[resolveLocale()]
        if data and data[key] then return data[key] end
        -- English fallback: return the key as-is (English IS the default)
        return key
    end,
})

-- Locale registration entry-point used by Locales/<code>.lua files
function ns:RegisterLocale(code, tbl)
    if type(code) ~= "string" or type(tbl) ~= "table" then return end
    ns.localeData[code] = ns.localeData[code] or {}
    for k, v in pairs(tbl) do
        ns.localeData[code][k] = v
    end
end

-- Returns the active client locale code (e.g. "enUS", "deDE")
function ns:GetActiveLocale()
    return resolveLocale()
end

-- Returns true if a translation exists for the current locale + key
function ns:HasTranslation(key)
    local data = ns.localeData[resolveLocale()]
    return data and data[key] ~= nil
end

-- Public API for the language override dropdown
-- Saves to SavedVariables so it survives /reload. The new locale takes effect
-- on next /reload because module strings are evaluated at file-load time.
function ns:SetLocaleOverride(code)
    _G.VuloClassicUIDB = _G.VuloClassicUIDB or {}
    if not code or code == "auto" or code == "" then
        _G.VuloClassicUIDB.localeOverride = nil
    else
        _G.VuloClassicUIDB.localeOverride = code
    end
    ns:RefreshLocale()  -- so a re-render picks up the change without /reload
end

function ns:GetLocaleOverride()
    local svDB = _G.VuloClassicUIDB
    return (svDB and svDB.localeOverride) or "auto"
end
