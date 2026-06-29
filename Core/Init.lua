-- =========================================================
-- VuloClassicUI / Core / Init
-- Loaded LAST. Waits for ADDON_LOADED, initializes DB,
-- enables modules, registers slash commands.
-- =========================================================
local _, ns = ...
local L = ns.L

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
        -- re-show the box of any window left in per-frame "free move", so it
        -- stays draggable across sessions without re-opening Edit Mode
        if ns.RestoreFreeMovers then ns:RestoreFreeMovers() end
        ns:Print(L["v%s loaded. /vcui to open."], ns.VERSION)
    end
end)

-- =========================================================
-- Slash commands
-- =========================================================
local function printVcuiHelp()
    local A = "|cff9b6cff"
    ns:Print(L["VuloClassicUI — commands:"])
    ns:Print(A .. "/vcui|r, /vulo — " .. L["open the options window"])
    ns:Print(A .. "/vcui <module>|r — " .. L["jump to that module's page"])
    ns:Print(A .. "/vcui modules|r — " .. L["list all modules with on/off state"])
    ns:Print(A .. "/vcui spam <name>|r — " .. L["toggle a name on/off the spam-filter whitelist"])
    ns:Print(A .. "/vcui goldreset|r — " .. L["reset the gold tracker session"])
    ns:Print(A .. "/vcui debug|r, " .. A .. "/vcui reset|r")
    ns:Print(A .. "/rl|r, /reloadui — " .. L["reload the UI"])
    ns:Print(A .. "/lo|r, /loadout — " .. L["gear loadouts"])
    ns:Print(A .. "/idtip|r — " .. L["tooltip IDs page"])
    ns:Print(A .. "/dcp|r — " .. L["cooldown pulse page"])
    ns:Print(A .. "/scttest|r — " .. L["castbar test"])
    ns:Print(A .. "/swingtest|r — " .. L["swing timer test/mover"])
    ns:Print(A .. "/vcuiwa|r — " .. L["WeakAuras skin diagnostics"])
    ns:Print(A .. "/inspectreset|r — " .. L["fix a stuck inspect"])
    ns:Print(A .. "/trinket|r — " .. L["trinket panel"])
end

SLASH_VULOCLASSICUI1 = "/vcui"
SLASH_VULOCLASSICUI2 = "/vulo"
SlashCmdList["VULOCLASSICUI"] = function(msg)
    local raw = (msg or ""):match("^%s*(.-)%s*$")
    msg = raw:lower()

    -- Defensive: if UI is not loaded yet, show a clear message
    if not ns.UI or not ns.UI.ToggleMainFrame then
        ns:Print(L["UI not loaded. Likely a Lua error during init. Enable /console scriptErrors 1 and /reload."])
        return
    end

    local ok, err = pcall(function()
        if msg == "" or msg == "config" or msg == "options" then
            ns.UI:ToggleMainFrame()

        elseif msg == "reset" then
            if ns:InCombat() then ns:Print(L["Not possible in combat."]); return end
            VuloClassicUIDB     = nil
            VuloClassicUICharDB = nil
            ns:Print(L["DB reset. UI reloading."])
            ReloadUI()

        elseif msg == "debug" then
            ns.db.global.debug = not ns.db.global.debug
            ns:Print(L["Debug = %s"], tostring(ns.db.global.debug))

        elseif msg == "modules" then
            ns:Print(L["Registered modules:"])
            for _, key in ipairs(ns.moduleOrder) do
                local m = ns.modules[key]
                ns:Print("  - %s (%s) [%s]", m.name, key, ns:IsModuleEnabled(key) and L["ON"] or L["off"])
            end

        elseif msg == "goldreset" then
            local gt = ns.modules.goldtracker
            if gt and gt.ResetSession then
                gt.ResetSession()
            else
                ns:Print(L["Gold Tracker not active."])
            end

        elseif msg == "help" or msg == "?" then
            printVcuiHelp()

        elseif msg == "spam" or msg:match("^spam%s") then
            local arg = raw:match("^%S+%s+(.-)$")
            local sf = ns.modules and ns.modules.spamfilter
            if not (sf and sf.ToggleWhitelist) then
                ns:Print(L["Spam filter not available."])
            elseif not arg or arg == "" then
                ns:Print(L["Usage: /vcui spam <name> — toggle a name on/off the spam-filter whitelist."])
            else
                sf.ToggleWhitelist(arg)
            end

        elseif ns.modules[msg] then
            if not ns.UI.mainFrame or not ns.UI.mainFrame:IsShown() then
                ns.UI:ToggleMainFrame()
            end
            ns.UI:ShowModulePage(msg)

        else
            ns:Print(L["Type |cff9b6cff/vcui help|r for the full command list."])
        end
    end)

    if not ok then
        ns:Print(L["|cffff5555Error while executing:|r %s"], tostring(err))
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
        ns:Print(L["Not possible in combat."])
        return
    end
    ReloadUI()
end
