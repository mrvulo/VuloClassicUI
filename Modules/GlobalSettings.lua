-- =========================================================
-- VuloClassicUI / Modules / GlobalSettings
-- Einziger Sidebar-Eintrag mit zwei Tabs:
--   General — UI-Scale, Kamera-Distanz, Minimap-Button
--   Profile — Pointer auf das Profiles-Modul
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("globalsettings", {
    name        = "Global Settings",
    group       = "Global",
    description = "Globale UI-Einstellungen + Profile-Verwaltung.",
    defaults    = { enabled = true },
})

mod.tabs = {
    { id = "general", label = "General" },
    { id = "profile", label = "Profile" },
}

-- =========================================================
-- Helpers
-- =========================================================
local function setCVar(cvar, val)
    pcall(SetCVar, cvar, tostring(val))
end

local function getCVarNum(cvar)
    local v = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(cvar))
           or (GetCVar and GetCVar(cvar))
    return tonumber(v) or 0
end

local function applyUIScale(scale)
    if not scale or scale <= 0 then return end
    -- useUiScale muss "1" sein damit uiScale greift
    setCVar("useUiScale", "1")
    setCVar("uiScale", scale)
    if UIParent and UIParent.SetScale then
        pcall(UIParent.SetScale, UIParent, scale)
    end
end

local function pixelPerfectScale()
    -- 768 / vertikale physische Auflösung
    if GetPhysicalScreenSize then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then return 768 / h end
    end
    return 0.65
end

-- StaticPopup für Profiling-Toggle (benötigt /reload damit der CVar greift)
StaticPopupDialogs["VCUI_RELOAD_PROFILING"] = {
    text = "Script-Profiling ge\195\164ndert. /reload erforderlich damit die CPU-Anzeige aktualisiert wird.",
    button1 = "Jetzt reloaden",
    button2 = "Sp\195\164ter",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- =========================================================
-- Tab: General
-- =========================================================
local function generalOptions()
    return {
        { type = "header", text = "Display" },

        { type = "slider", label = "UI Scale",
          min = 0.40, max = 1.15, step = 0.01,
          tooltip = "Manuelle UI-Skalierung. 0.65 ist kleiner, 1.0 ist Standard.",
          get = function() return getCVarNum("uiScale") end,
          set = function(_, v) applyUIScale(v) end },

        { type = "group", layout = "row", gap = 8,
          items = {
              { type = "button", label = "Pixel Perfect", width = 130,
                onClick = function()
                    local s = pixelPerfectScale()
                    applyUIScale(s)
                    ns:Print("UI Scale = %.4f (pixel perfect)", s)
                end },
              { type = "button", label = "1080p Scale", width = 130,
                onClick = function() applyUIScale(768/1080); ns:Print("UI Scale = 0.7111 (1080p)") end },
              { type = "button", label = "1440p Scale", width = 130,
                onClick = function() applyUIScale(768/1440); ns:Print("UI Scale = 0.5333 (1440p)") end },
          },
        },

        { type = "spacer", height = 6 },
        { type = "header", text = "Kamera" },
        { type = "slider", label = "Max Camera Distance",
          min = 1.0, max = 3.4, step = 0.1,
          tooltip = "Maximale Kamera-Entfernung (CVar cameraDistanceMaxZoomFactor).",
          get = function() return getCVarNum("cameraDistanceMaxZoomFactor") end,
          set = function(_, v) setCVar("cameraDistanceMaxZoomFactor", v) end },

        { type = "spacer", height = 6 },
        { type = "header", text = "Minimap" },
        { type = "toggle", label = "Minimap-Button anzeigen",
          tooltip = "VuloClassicUI-Button auf der Minimap an/aus.",
          get = function()
              local m = ns.modules and ns.modules.minimap
              return m and m.db and m.db.enabled
          end,
          set = function(_, v)
              if ns.ToggleModule then ns:ToggleModule("minimap", v) end
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = "Debug" },
        { type = "toggle", label = "Script-Profiling aktivieren (CPU-Anzeige)",
          tooltip = "Aktiviert WoWs scriptProfile CVar damit die CPU-Anzeige im Config-Header funktioniert.\n\n|cffff8800ACHTUNG:|r Profiling kostet ~3-5% Performance. Nur zum Debuggen empfohlen.\n\n|cffaaaaaaErfordert /reload damit die \195\132nderung greift.|r",
          get = function() return getCVarNum("scriptProfile") == 1 end,
          set = function(_, v)
              setCVar("scriptProfile", v and "1" or "0")
              StaticPopup_Show("VCUI_RELOAD_PROFILING")
          end },
    }
end

-- =========================================================
-- Tab: Profile (delegiert ans Profiles-Modul)
-- =========================================================
local function profileOptions()
    local p = ns.modules and ns.modules.profiles
    if p and p.GetOptions then
        local ok, items = pcall(p.GetOptions, p)
        if ok and items then return items end
    end
    return {
        { type = "desc",
          text = "|cffff5555Profile-Modul nicht geladen.|r" },
    }
end

-- =========================================================
-- Options Dispatcher
-- =========================================================
function mod:GetOptions(tabId)
    if tabId == "profile" then return profileOptions() end
    return generalOptions()
end
