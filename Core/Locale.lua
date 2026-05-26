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

-- Detect current client locale (defaults to enUS if unavailable)
local currentLocale = (GetLocale and GetLocale()) or "enUS"

-- The L table: fallback returns the key itself if no translation exists
ns.L = setmetatable({}, {
    __index = function(_, key)
        local data = ns.localeData[currentLocale]
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
    return currentLocale
end

-- Returns true if a translation exists for the current locale + key
function ns:HasTranslation(key)
    local data = ns.localeData[currentLocale]
    return data and data[key] ~= nil
end
