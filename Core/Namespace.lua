-- Shared addon table, used by all files.
local addonName, ns = ...

_G.VuloClassicUI = ns

ns.NAME      = addonName
local _metaGet = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
ns.VERSION   = (_metaGet and _metaGet(addonName, "Version")) or "?"
ns.PREFIX    = "|cff9b6cffVuloClassicUI|r"

-- Flavour detection, two sources.
--
-- WOW_PROJECT_ID is exact where it is defined, but it is a fixed list of
-- constants: a build that reports an id we have no constant for used to leave
-- EVERY flag false, which is worse than a client with no id at all -- that one
-- at least fell back to BCC. The interface number has no such hole. It is a
-- number, it sorts, and a variant of an expansion lands in that expansion's
-- range on its own.
--
-- So: ask the constants first, and where they cannot answer, derive it from
-- the build. 11xxx Era, 2xxxx BCC, 3xxxx Wrath, 4xxxx Cataclysm.
local _proj  = _G.WOW_PROJECT_ID
local _iface = tonumber((select(4, GetBuildInfo()))) or 0
local function _projIs(constant) return _proj ~= nil and constant ~= nil and _proj == constant end
local function _ifaceIn(lo, hi) return _iface >= lo and _iface < hi end

ns.isEra   = _projIs(_G.WOW_PROJECT_CLASSIC)                    -- Classic Era (1.15.x)
ns.isBCC   = _projIs(_G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC)    -- Anniversary (2.5.x)
ns.isWrath = _projIs(_G.WOW_PROJECT_WRATH_CLASSIC)
ns.isCata  = _projIs(_G.WOW_PROJECT_CATACLYSM_CLASSIC)

-- Nothing matched: either no id at all, or one we have no constant for. Let the
-- build number decide instead of leaving every flag false.
if not (ns.isEra or ns.isBCC or ns.isWrath or ns.isCata) then
    if     _ifaceIn(10000, 20000) then ns.isEra   = true
    elseif _ifaceIn(20000, 30000) then ns.isBCC   = true
    elseif _ifaceIn(30000, 40000) then ns.isWrath = true
    elseif _ifaceIn(40000, 50000) then ns.isCata  = true
    else                               ns.isBCC   = true   -- last resort: the build we ship for
    end
end
ns.isClassic = (ns.isEra or ns.isBCC or ns.isWrath or ns.isCata)

-- Era and SoD share TOC 11508 and WOW_PROJECT_CLASSIC; C_Seasons at runtime is the only way to tell them apart, and it is absent on 2.5.x.
local _seasons   = _G.C_Seasons
local _hasSeason  = (_seasons and _seasons.HasActiveSeason and _seasons.HasActiveSeason()) and true or false
ns.SeasonID = (_hasSeason and _seasons.GetActiveSeason and _seasons.GetActiveSeason()) or 0   -- 0 = no season
ns.isSoD    = (ns.isEra and _hasSeason
               and _G.Enum and _G.Enum.SeasonID
               and ns.SeasonID == _G.Enum.SeasonID.SeasonOfDiscovery) and true or false

ns.C = {
    accent = "|cff9b6cff",
    gold   = "|cffffd100",
    silver = "|cffc7c7cf",
    copper = "|cffeda55f",
    pos    = "|cff44ff44",
    neg    = "|cffff4444",
    gray   = "|cffaaaaaa",
    white  = "|cffffffff",
    yellow = "|cffffff00",
    red    = "|cffff5555",
    r      = "|r",
}

ns.COLORS = {
    accent     = { r = 0.608, g = 0.424, b = 1.000 },
    accentDim  = { r = 0.300, g = 0.200, b = 0.500 },
    bg         = { r = 0.06,  g = 0.06,  b = 0.08, a = 0.96 },
    bgLight    = { r = 0.055, g = 0.055, b = 0.07, a = 0.96 },
    bgContent  = { r = 0.08,  g = 0.08,  b = 0.10, a = 0.96 },
    border     = { r = 0.25,  g = 0.25,  b = 0.30, a = 1.00 },
    borderDark = { r = 0.02,  g = 0.02,  b = 0.03, a = 1.00 },
    text       = { r = 1.00,  g = 1.00,  b = 1.00 },
    textDim    = { r = 0.65,  g = 0.65,  b = 0.70 },
    textMuted  = { r = 0.45,  g = 0.45,  b = 0.50 },
    toggleOff  = { r = 0.20,  g = 0.20,  b = 0.23, a = 1.00 },
    sectionHdr = { r = 0.55,  g = 0.50,  b = 0.60 },
}

ns.modules     = {}
ns.moduleOrder = {}

-- Set to true in Init.lua after PLAYER_LOGIN
ns.isInitialised = false
