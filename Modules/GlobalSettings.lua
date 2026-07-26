-- GlobalSettings: sidebar entry with two tabs — General (UI scale, camera, minimap button) and Profile (delegates to the Profiles module).
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("globalsettings", {
    name        = "Global Settings",
    group       = "Global",
    description = "Global UI settings + profile management.",
    defaults    = {
        enabled    = true,
        themeColor = { r = 0.608, g = 0.424, b = 1.000 },   -- house purple
    },
})

mod.tabs = {
    { id = "general", label = "General" },
    { id = "profile", label = "Profile" },
}

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
local THEME_PRESETS
ns.OnLocaleReady(function()
StaticPopupDialogs["VCUI_RELOAD_PROFILING"] = {
    text = L["Script profiling changed. /reload required for the CPU display to update."],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- StaticPopup for language override (requires /reload because module strings are
-- evaluated at file-load time, so a new locale only takes effect on reload)
StaticPopupDialogs["VCUI_RELOAD_LOCALE"] = {
    text = L["Language changed. /reload required to apply the new language to all UI elements."],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- StaticPopup for theme color (already-painted textures keep the old color
-- until the UI reloads)
StaticPopupDialogs["VCUI_RELOAD_THEME"] = {
    text = L["Theme color changed. /reload applies it to everything (elements already drawn keep the old color until then)."],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

THEME_PRESETS = {
    { value = "9b6cff", text = L["Purple (default)"] },
    { value = "4f9bff", text = L["Blue"] },
    { value = "37d67a", text = L["Green"] },
    { value = "ff5c5c", text = L["Red"] },
    { value = "ffd100", text = L["Gold"] },
    { value = "2dd4cf", text = L["Turquoise"] },
    { value = "ff6ec7", text = L["Pink"] },
    { value = "ff8c1a", text = L["Orange"] },
}
end)

local function themeHex()
    local c = mod.db and mod.db.themeColor or {}
    return string.format("%02x%02x%02x",
        math.floor((c.r or 0.608) * 255 + 0.5),
        math.floor((c.g or 0.424) * 255 + 0.5),
        math.floor((c.b or 1.000) * 255 + 0.5))
end

local function setTheme(r, g, b)
    mod.db.themeColor = { r = r, g = g, b = b }
    if ns.ApplyThemeColor then ns:ApplyThemeColor() end
    StaticPopup_Show("VCUI_RELOAD_THEME")
end

local function generalOptions()
    local items = {
        { type = "header", text = L["Language"] },
        { type = "dropdown", label = L["UI Language"],
          tooltip = L["Choose the language for the VuloClassicUI interface. 'Auto' uses your WoW client's language (German clients see German, all others see English).\n\n|cffaaaaaaRequires /reload to apply.|r"],
          values = ns.SUPPORTED_LOCALES,
          get = function() return ns:GetLocaleOverride() end,
          set = function(_, v)
              ns:SetLocaleOverride(v)
              StaticPopup_Show("VCUI_RELOAD_LOCALE")
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Display"] },

        { type = "slider", label = L["UI Scale"],
          min = 0.40, max = 1.15, step = 0.01,
          tooltip = L["Manual UI scaling. 0.65 is smaller, 1.0 is default."],
          get = function() return getCVarNum("uiScale") end,
          set = function(_, v) applyUIScale(v) end },

        { type = "group", layout = "row", gap = 8,
          items = {
              { type = "button", label = L["Pixel Perfect"], width = 130,
                onClick = function()
                    local s = pixelPerfectScale()
                    applyUIScale(s)
                    ns:Print(L["UI Scale = %.4f (pixel perfect)"], s)
                end },
              { type = "button", label = L["1080p Scale"], width = 130,
                onClick = function() applyUIScale(768/1080); ns:Print(L["UI Scale = 0.7111 (1080p)"]) end },
              { type = "button", label = L["1440p Scale"], width = 130,
                onClick = function() applyUIScale(768/1440); ns:Print(L["UI Scale = 0.5333 (1440p)"]) end },
          },
        },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Theme color"] },
        { type = "desc",
          text = L["|cffaaaaaaColors everything that is purple today in the color of your choice - sidebar, borders, highlights, bars. A /reload applies it everywhere.|r"] },
        { type = "dropdown", label = L["Preset"],
          width = 220,
          values = THEME_PRESETS,
          get = function() return themeHex() end,
          set = function(_, v)
              local r = tonumber(v:sub(1, 2), 16) / 255
              local g = tonumber(v:sub(3, 4), 16) / 255
              local b = tonumber(v:sub(5, 6), 16) / 255
              setTheme(r, g, b)
          end },
        { type = "color", label = L["Custom color"],
          get = function() return mod.db.themeColor end,
          set = function(r, g, b) setTheme(r, g, b) end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Camera"] },
        { type = "slider", label = L["Max Camera Distance"],
          min = 1.0, max = 3.4, step = 0.1,
          tooltip = L["Maximum camera distance (CVar cameraDistanceMaxZoomFactor)."],
          get = function() return getCVarNum("cameraDistanceMaxZoomFactor") end,
          set = function(_, v) setCVar("cameraDistanceMaxZoomFactor", v) end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Minimap"] },
        { type = "toggle", label = L["Show Minimap Button"],
          tooltip = L["Toggle the VuloClassicUI button on the minimap."],
          get = function()
              return ns:IsModuleEnabled("minimap")
          end,
          set = function(_, v)
              if ns.ToggleModule then ns:ToggleModule("minimap", v) end
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Performance Display"] },
    }
    -- The client's own always-on profiler needs neither the CVar nor a reload,
    -- so on those clients there is nothing left to switch and the readout is
    -- simply always there. The old switch only appears where it still does work.
    local prof = _G.C_AddOnProfiler
    if prof and prof.GetAddOnMetric and (not prof.IsEnabled or prof.IsEnabled()) then
        items[#items + 1] = { type = "desc",
            text = L["|cffaaaaaaThe header shows how much frame time VuloClassicUI costs. Your client measures this on its own, all the time — no setting and no reload needed.|r"] }
    else
        items[#items + 1] = { type = "toggle", label = L["Show CPU Usage in Header"],
            tooltip = L["Shows total CPU usage of all active addons (plus VuloClassicUI's own share) at the top of the config header.\n\n|cffaaaaaaRequires /reload after toggling.\n\nNote: Enables WoW's scriptProfile CVar, which costs ~3-5% performance — that's the price for WoW collecting this data at all.|r"],
            get = function() return getCVarNum("scriptProfile") == 1 end,
            set = function(_, v)
                setCVar("scriptProfile", v and "1" or "0")
                StaticPopup_Show("VCUI_RELOAD_PROFILING")
            end }
    end
    return items
end

local function profileOptions()
    local p = ns.modules and ns.modules.profiles
    if p and p.GetOptions then
        local ok, items = pcall(p.GetOptions, p)
        if ok and items then return items end
    end
    return {
        { type = "desc",
          text = L["|cffff5555Profile module not loaded.|r"] },
    }
end

function mod:GetOptions(tabId)
    if tabId == "profile" then return profileOptions() end
    return generalOptions()
end
