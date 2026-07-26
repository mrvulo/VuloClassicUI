-- VuloClassicUI / Core / MediaRegistry
-- Registers all bundled fonts and statusbars as shared media so any consumer
-- (WeakAuras, boss mods, other UI suites) automatically detects them.
local _, ns = ...
local L = ns.L

local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
if not LSM then
    -- Deferred: at file-load time the saved language choice does not exist yet,
    -- so resolving the text here would print it in the client language AND
    -- poison the locale cache for everything after it.
    ns.OnLocaleReady(function()
        if ns.Print then
            ns:Print(L["|cffff5555LibSharedMedia-3.0 not found, Media Registry will be skipped.|r"])
        end
    end)
end

local BASE = "Interface\\Addons\\VuloClassicUI\\Media\\"

-- StatusBars — only the textures bundled under Media\textures. This list is the
-- single source of truth for every "Bar texture" dropdown; the modules used to
-- carry their own copies and had drifted apart (two of three offered 11 of the
-- 17 registered textures).
local TEX = BASE .. "textures\\"
local STATUSBARS = {
    { "Atrocity",           "atrocity.tga" },
    { "Beautiful",          "beautiful.tga" },
    { "Divide",             "divide.tga" },
    { "Fade",               "fade.tga" },
    { "Fade Right",         "fade-right.tga" },
    { "Glass",              "glass.tga" },
    { "Gradient",           "gradient-lr.tga" },
    { "Gradient (B-T)",     "gradient-bt.tga" },
    { "Gradient (R-L)",     "gradient-rl.tga" },
    { "Gradient (T-B)",     "gradient-tb.tga" },
    { "Matte",              "matte.tga" },
    { "Melli",              "melli.tga" },
    { "Plating",            "plating.tga" },
    { "Sheer",              "sheer.tga" },
    { "Soft Line",          "soft-line.tga" },
    { "Thin Line (Top)",    "thin-line-top.tga" },
    { "Thin Line (Bottom)", "thin-line-bottom.tga" },
}

local BUNDLED_NAMES = {}
for i, e in ipairs(STATUSBARS) do
    BUNDLED_NAMES[i] = e[1]
    if LSM then LSM:Register("statusbar", e[1], TEX .. e[2]) end
end
ns.BUNDLED_STATUSBARS = BUNDLED_NAMES

-- HashTable, not LSM:Fetch: Fetch honours a global texture override and would
-- collapse every choice to one texture.
function ns.MediaStatusbar(name, fallback)
    if LSM and name then
        local hash = LSM:HashTable("statusbar")
        local path = hash and hash[name]
        if path and path ~= "" then return path end
    end
    return fallback or "Interface\\TargetingFrame\\UI-StatusBar"
end

-- True for any texture MediaStatusbar can resolve, bundled or foreign.
function ns.MediaStatusbarValid(name)
    if not (LSM and name) then return false end
    local hash = LSM:HashTable("statusbar")
    return (hash and hash[name] and hash[name] ~= "") and true or false
end

-- Dropdown values: the bundled set first, then statusbars other addons
-- registered with shared media.
function ns.MediaStatusbarValues()
    local v, seen = {}, {}
    for _, n in ipairs(BUNDLED_NAMES) do
        v[#v + 1] = { value = n, text = n }; seen[n] = true
    end
    if LSM then
        for _, n in ipairs(LSM:List("statusbar") or {}) do
            if not seen[n] then v[#v + 1] = { value = n, text = n } end
        end
    end
    return v
end

if LSM then
    LSM:Register("font", "Expressway", BASE .. "Fonts\\Expressway.TTF")
end

-- (Sounds folder removed — VuloClassicUI doesn't use any of its sounds and
--  the 118-file pack was only registered for other addons. QueueTimer uses
--  a built-in Blizzard sound ID, not a bundled file.)

ns.LSM = LSM
