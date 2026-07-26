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
    -- Drop memoised lookups too, or a language change would keep serving the
    -- strings resolved under the previous one.
    if ns.L then wipe(ns.L) end
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

-- Eight languages ship, exactly one is ever read. Handing RegisterLocale a
-- BUILDER instead of a finished table means the other seven never build their
-- ~2500-entry hash table at all -- the builder is simply never called. The
-- table form still works and is applied immediately, so nothing outside this
-- file has to care which shape a locale file uses.
local builders = {}

local function materialize(code)
    local data = ns.localeData[code]
    if data then return data end
    data = {}
    ns.localeData[code] = data          -- set first: a builder must not recurse
    local list = builders[code]
    if list then
        for i = 1, #list do
            local ok, tbl = pcall(list[i])
            if ok and type(tbl) == "table" then
                for k, v in pairs(tbl) do data[k] = v end
            end
        end
    end
    return data
end

-- Resolved lookups are written back into the table itself, so a repeated L[k]
-- is a plain hash hit instead of a metamethod call plus two lookups. Safe
-- because nothing in the addon iterates ns.L (pairs would only see the resolved
-- subset), and RefreshLocale wipes it when the language changes.
ns.L = setmetatable({}, {
    __index = function(t, key)
        local v = materialize(resolveLocale())[key] or key
        rawset(t, key, v)
        return v
    end,
})

function ns:RegisterLocale(code, tblOrBuilder)
    if type(code) ~= "string" then return end
    local kind = type(tblOrBuilder)

    if kind == "function" then
        local list = builders[code]
        if not list then list = {}; builders[code] = list end
        list[#list + 1] = tblOrBuilder
        -- Registered after this language was already read: apply straight away,
        -- otherwise the late entries would never appear.
        local data = ns.localeData[code]
        if data then
            local ok, tbl = pcall(tblOrBuilder)
            if ok and type(tbl) == "table" then
                for k, v in pairs(tbl) do data[k] = v end
            end
        end
        return
    end

    if kind ~= "table" then return end
    ns.localeData[code] = ns.localeData[code] or {}
    for k, v in pairs(tblOrBuilder) do
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
