-- =========================================================
-- VuloClassicUI / Modules / GlobalSettings
-- Single sidebar entry with two tabs:
--   General — UI scale, camera distance, minimap button
--   Profile — pointer to the Profiles module
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("globalsettings", {
    name        = "Global Settings",
    group       = "Global",
    description = "Global UI settings + profile management.",
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
    -- useUiScale must be "1" for uiScale to take effect
    setCVar("useUiScale", "1")
    setCVar("uiScale", scale)
    if UIParent and UIParent.SetScale then
        pcall(UIParent.SetScale, UIParent, scale)
    end
end

local function pixelPerfectScale()
    -- 768 / vertical physical resolution
    if GetPhysicalScreenSize then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then return 768 / h end
    end
    return 0.65
end

-- StaticPopup for profiling toggle (requires /reload for the CVar to take effect)
StaticPopupDialogs["VCUI_RELOAD_PROFILING"] = {
    text = "Script profiling changed. /reload required for the CPU display to update.",
    button1 = "Reload now",
    button2 = "Later",
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
          tooltip = "Manual UI scaling. 0.65 is smaller, 1.0 is default.",
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
        { type = "header", text = "Camera" },
        { type = "slider", label = "Max Camera Distance",
          min = 1.0, max = 3.4, step = 0.1,
          tooltip = "Maximum camera distance (CVar cameraDistanceMaxZoomFactor).",
          get = function() return getCVarNum("cameraDistanceMaxZoomFactor") end,
          set = function(_, v) setCVar("cameraDistanceMaxZoomFactor", v) end },

        { type = "spacer", height = 6 },
        { type = "header", text = "Minimap" },
        { type = "toggle", label = "Show Minimap Button",
          tooltip = "Toggle the VuloClassicUI button on the minimap.",
          get = function()
              local m = ns.modules and ns.modules.minimap
              return m and m.db and m.db.enabled
          end,
          set = function(_, v)
              if ns.ToggleModule then ns:ToggleModule("minimap", v) end
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = "Performance Display" },
        { type = "toggle", label = "Show CPU Usage in Header",
          tooltip = "Shows total CPU usage of all active addons (plus VuloClassicUI's own share) at the top of the config header.\n\n|cffaaaaaaRequires /reload after toggling.\n\nNote: Enables WoW's scriptProfile CVar, which costs ~3-5% performance — that's the price for WoW collecting this data at all.|r",
          get = function() return getCVarNum("scriptProfile") == 1 end,
          set = function(_, v)
              setCVar("scriptProfile", v and "1" or "0")
              StaticPopup_Show("VCUI_RELOAD_PROFILING")
          end },
    }
end

-- =========================================================
-- Tab: Profile (delegates to the Profiles module)
-- =========================================================
local function profileOptions()
    local p = ns.modules and ns.modules.profiles
    if p and p.GetOptions then
        local ok, items = pcall(p.GetOptions, p)
        if ok and items then return items end
    end
    return {
        { type = "desc",
          text = "|cffff5555Profile module not loaded.|r" },
    }
end

-- =========================================================
-- Options dispatcher
-- =========================================================
function mod:GetOptions(tabId)
    if tabId == "profile" then return profileOptions() end
    return generalOptions()
end
