-- Locale registry: keys ARE the English text, missing translations fall back to the key.
local _, ns = ...

ns.localeData = ns.localeData or {}

-- Listed in their own language: someone who needs the switch cannot read the
-- language it is currently showing.
ns.SUPPORTED_LOCALES = {
    { value = "auto", text = "Auto (client language)" },
    { value = "enUS", text = "English" },
    { value = "deDE", text = "Deutsch" },
    { value = "esES", text = "Español" },
    { value = "frFR", text = "Français" },
    { value = "itIT", text = "Italiano" },
    { value = "ptBR", text = "Português" },
    { value = "ruRU", text = "Русский" },
    { value = "koKR", text = "한국어" },
}

-- Resolved live per lookup: SavedVariables (holding the override) only exist from ADDON_LOADED, so a load-time snapshot would ignore it.
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

function ns:RefreshLocale()
    _cachedLocale = nil
end

-- File-scope code must never evaluate L[...]: the saved language override only
-- exists from ADDON_LOADED, so a load-time lookup bakes the client language.
-- One-shot blocks that want file-scope style anyway (StaticPopup registrations,
-- label tables) register here; Init.lua runs them right after the override is
-- applied, before any module is enabled.
local pendingLocaleFns = {}
function ns.OnLocaleReady(fn)
    if pendingLocaleFns then
        pendingLocaleFns[#pendingLocaleFns + 1] = fn
    else
        fn()
    end
end

function ns:RunLocaleReadyCallbacks()
    local list = pendingLocaleFns
    pendingLocaleFns = nil
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i])
        if not ok then geterrorhandler()(err) end
    end
end

ns.L = setmetatable({}, {
    __index = function(_, key)
        local data = ns.localeData[resolveLocale()]
        if data and data[key] then return data[key] end
        return key
    end,
})

function ns:RegisterLocale(code, tbl)
    if type(code) ~= "string" or type(tbl) ~= "table" then return end
    ns.localeData[code] = ns.localeData[code] or {}
    for k, v in pairs(tbl) do
        ns.localeData[code][k] = v
    end
end

-- Takes full effect only on /reload: module strings are evaluated at file-load time.
function ns:SetLocaleOverride(code)
    _G.VuloClassicUIDB = _G.VuloClassicUIDB or {}
    if not code or code == "auto" or code == "" then
        _G.VuloClassicUIDB.localeOverride = nil
    else
        _G.VuloClassicUIDB.localeOverride = code
    end
    ns:RefreshLocale()
end

function ns:GetLocaleOverride()
    local svDB = _G.VuloClassicUIDB
    return (svDB and svDB.localeOverride) or "auto"
end
