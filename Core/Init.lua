-- =========================================================
-- VuloClassicUI / Core / Init
-- Loaded LAST. Waits for ADDON_LOADED, initializes DB,
-- enables modules, registers slash commands.
-- =========================================================
local _, ns = ...

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")

initFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= ns.NAME then return end
        ns:InitDB()
        ns:EnableModules()

    elseif event == "PLAYER_LOGIN" then
        ns.isInitialised = true
        ns:Print("v%s loaded. /vcui to open.", ns.VERSION)
    end
end)

-- =========================================================
-- Slash commands
-- =========================================================
SLASH_VULOCLASSICUI1 = "/vcui"
SLASH_VULOCLASSICUI2 = "/vulo"
SlashCmdList["VULOCLASSICUI"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    -- Defensive: if UI is not loaded yet, show a clear message
    if not ns.UI or not ns.UI.ToggleMainFrame then
        ns:Print("UI not loaded. Likely a Lua error during init. Enable /console scriptErrors 1 and /reload.")
        return
    end

    local ok, err = pcall(function()
        if msg == "" or msg == "config" or msg == "options" then
            ns.UI:ToggleMainFrame()

        elseif msg == "reset" then
            if ns:InCombat() then ns:Print("Not possible in combat."); return end
            VuloClassicUIDB     = nil
            VuloClassicUICharDB = nil
            ns:Print("DB reset. UI reloading.")
            ReloadUI()

        elseif msg == "debug" then
            ns.db.global.debug = not ns.db.global.debug
            ns:Print("Debug = %s", tostring(ns.db.global.debug))

        elseif msg == "modules" then
            ns:Print("Registered modules:")
            for _, key in ipairs(ns.moduleOrder) do
                local m = ns.modules[key]
                ns:Print("  - %s (%s) [%s]", m.name, key, (m.db and m.db.enabled) and "ON" or "off")
            end

        elseif msg == "goldreset" then
            local gt = ns.modules.goldtracker
            if gt and gt.ResetSession then
                gt.ResetSession()
            else
                ns:Print("Gold Tracker not active.")
            end

        elseif ns.modules[msg] then
            if not ns.UI.mainFrame or not ns.UI.mainFrame:IsShown() then
                ns.UI:ToggleMainFrame()
            end
            ns.UI:ShowModulePage(msg)

        else
            ns:Print("Commands: /vcui (options) | /vcui <module> | /vcui modules | /vcui goldreset | /vcui debug | /vcui reset")
        end
    end)

    if not ok then
        ns:Print("|cffff5555Error while executing:|r %s", tostring(err))
    end
end

-- Convenience aliases for modules
SLASH_VCUI_IDTIP1 = "/idtip"
SlashCmdList["VCUI_IDTIP"] = function() SlashCmdList["VULOCLASSICUI"]("tooltipids") end

-- Quick reload
SLASH_VCUI_RELOAD1 = "/rl"
SLASH_VCUI_RELOAD2 = "/reloadui"
SlashCmdList["VCUI_RELOAD"] = function()
    if InCombatLockdown and InCombatLockdown() then
        ns:Print("Not possible in combat.")
        return
    end
    ReloadUI()
end
