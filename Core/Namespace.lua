-- =========================================================
-- VuloClassicUI / Core / Namespace
-- Shared addon table, used by all files.
-- =========================================================
local addonName, ns = ...

-- Global reference, in case you want to access it from chat via /run
_G.VuloClassicUI = ns

ns.NAME      = addonName
-- Read version dynamically from TOC (otherwise you'd have to change 2 places on every bump)
local _metaGet = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
ns.VERSION   = (_metaGet and _metaGet(addonName, "Version")) or "?"
ns.PREFIX    = "|cff9b6cffVuloClassicUI|r"

-- Client/version detection. WOW_PROJECT_* may be nil on very old clients, so guard.
local _proj = _G.WOW_PROJECT_ID
ns.isEra       = (_proj ~= nil and _proj == _G.WOW_PROJECT_CLASSIC)                    -- Classic Era / Vanilla (1.15.x)
ns.isBCC       = (_proj ~= nil and _proj == _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC)    -- TBC Classic / Anniversary (2.5.x)
ns.isWrath     = (_proj ~= nil and _proj == _G.WOW_PROJECT_WRATH_CLASSIC)
ns.isCata      = (_proj ~= nil and _proj == _G.WOW_PROJECT_CATACLYSM_CLASSIC)
ns.isClassic   = (ns.isEra or ns.isBCC or ns.isWrath or ns.isCata)                    -- any non-retail flavor
-- If WOW_PROJECT_ID is missing entirely, assume the build we ship for (BCC) so nothing self-disables wrongly.
if _proj == nil then ns.isBCC, ns.isClassic = true, true end

-- Season of Discovery. Era and SoD are indistinguishable by TOC (both Interface
-- 11508) and by WOW_PROJECT_ID (both WOW_PROJECT_CLASSIC) -- the ONLY way to tell
-- them apart is the C_Seasons API at runtime. Every access is guarded because
-- C_Seasons / Enum.SeasonID do NOT exist on the TBC Anniversary (2.5.x) client,
-- so there isSoD ends up false and SeasonID 0 (correct).
local _seasons   = _G.C_Seasons
local _hasSeason  = (_seasons and _seasons.HasActiveSeason and _seasons.HasActiveSeason()) and true or false
ns.SeasonID = (_hasSeason and _seasons.GetActiveSeason and _seasons.GetActiveSeason()) or 0   -- 0 = no season
ns.isSoD    = (ns.isEra and _hasSeason
               and _G.Enum and _G.Enum.SeasonID
               and ns.SeasonID == _G.Enum.SeasonID.SeasonOfDiscovery) and true or false

-- Color escape codes for strings (FontStrings, Tooltip lines, ns:Print)
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

-- Colors for the UI (EUI style: dark backdrops, purple accent)
ns.COLORS = {
    accent     = { r = 0.608, g = 0.424, b = 1.000 },  -- 9b6cff
    accentDim  = { r = 0.300, g = 0.200, b = 0.500 },  -- dimmed variant
    bg         = { r = 0.06,  g = 0.06,  b = 0.08, a = 0.96 },  -- main window BG
    bgLight    = { r = 0.055, g = 0.055, b = 0.07, a = 0.96 },  -- Sidebar BG (darker than content)
    bgContent  = { r = 0.08,  g = 0.08,  b = 0.10, a = 0.96 },  -- Content BG
    border     = { r = 0.25,  g = 0.25,  b = 0.30, a = 1.00 },
    borderDark = { r = 0.02,  g = 0.02,  b = 0.03, a = 1.00 },  -- outer window chrome
    text       = { r = 1.00,  g = 1.00,  b = 1.00 },
    textDim    = { r = 0.65,  g = 0.65,  b = 0.70 },
    textMuted  = { r = 0.45,  g = 0.45,  b = 0.50 },
    toggleOff  = { r = 0.20,  g = 0.20,  b = 0.23, a = 1.00 },
    sectionHdr = { r = 0.55,  g = 0.50,  b = 0.60 },  -- "DISPLAY"-style headers
}

-- Module registry: all modules register themselves here
ns.modules     = {}       -- key -> moduleObject
ns.moduleOrder = {}       -- ordered list for Sidebar

-- Set to true in Init.lua after PLAYER_LOGIN
ns.isInitialised = false
