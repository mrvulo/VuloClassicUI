-- VuloClassicUI / Core / Init
-- Loaded LAST. Waits for ADDON_LOADED, initializes DB,
-- enables modules, registers slash commands.
local _, ns = ...
local L = ns.L

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")

initFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= ns.NAME then return end
        ns:InitDB()
        -- Any file-scope L[...] lookup before this point cached the CLIENT
        -- language, because the saved language override only exists now.
        -- Without this reset the override silently never applied.
        if ns.RefreshLocale then ns:RefreshLocale() end
        if ns.RunLocaleReadyCallbacks then ns:RunLocaleReadyCallbacks() end
        ns:EnableModules()

    elseif event == "PLAYER_LOGIN" then
        ns.isInitialised = true
        if ns.RestoreFreeMovers then ns:RestoreFreeMovers() end
        ns:Print(L["v%s loaded. /vcui to open."], ns.VERSION)
        -- Migrations run at ADDON_LOADED, where anything printed can scroll away
        -- before the player is even in the world. They leave their report here.
        for _, n in ipairs(ns.migrationNotes or {}) do
            ns:Print(unpack(n))
        end
        ns.migrationNotes = nil
    end
end)

-- Slash commands
-- Only the WORDS that follow /vcui live here -- those are this file's business
-- and no registry can know them. The standalone commands come from
-- ns:PrintSlashHelp, which reads the table every command writes itself into.
--
-- They used to be listed here by hand as well, and the list had quietly drifted
-- to missing fourteen of the twenty: /vcuiprof, /vedit, /vkb, /cdedit,
-- /lazyvulo, /vlfg, /disenchant, /friendstate and the aliases -- and /vcui help
-- itself. A list that has to be maintained beside the thing it describes ends up
-- describing something else.
local function printVcuiHelp()
    local A = (ns.C and ns.C.accent) or "|cff9b6cff"
    ns:Print(L["VuloClassicUI — commands:"])
    ns:Print(A .. "/vcui <module>|r — " .. L["jump to that module's page"])
    ns:Print(A .. "/vcui modules|r — " .. L["list all modules with on/off state"])
    ns:Print(A .. "/vcui spam <name>|r — " .. L["toggle a name on/off the spam-filter whitelist"])
    ns:Print(A .. "/vcui goldreset|r — " .. L["reset the gold tracker session"])
    ns:Print(A .. "/vcui debug|r, " .. A .. "/vcui reset|r")
    if ns.PrintSlashHelp then ns:PrintSlashHelp() end
end

-- /vcui reset wipes every setting of every character on the account. A typo
-- while trying slash commands must not be able to do that silently, so it asks
-- first - the same way deleting a single profile already does.
ns.OnLocaleReady(function()
StaticPopupDialogs["VCUI_DB_RESET"] = {
    text = L["Reset ALL VuloClassicUI settings for every character on this account? This cannot be undone."],
    button1 = L["Reset"],
    button2 = CANCEL,
    OnAccept = function()
        if ns:InCombat() then ns:Print(L["Not possible in combat."]); return end
        -- The graphics-optimize backup dies with the DB, but the CVars it
        -- covers live in the client's config and would stay optimized with no
        -- way back. "Reset ALL settings" returns those too.
        local gfx = VuloClassicUIDB and VuloClassicUIDB.global
                and VuloClassicUIDB.global.gfxBackup
        if gfx then
            for cvar, v in pairs(gfx) do pcall(SetCVar, cvar, v) end
        end
        VuloClassicUIDB     = nil
        VuloClassicUICharDB = nil
        ns:Print(L["DB reset. UI reloading."])
        ReloadUI()
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    showAlert = 1,
}
end)

ns:RegisterSlash({ key = "OPTIONS", commands = { "/vcui", "/vulo" },
    desc = "Open the settings window. Add a word for more: help, modules, debug, reset.",
})
ns.Slash.OPTIONS = function(msg)
    local raw = (msg or ""):match("^%s*(.-)%s*$")
    msg = raw:lower()

    -- Answered BEFORE the UI check below. If the interface failed to load, the
    -- list of commands is the one thing that still helps, and printing it needs
    -- no interface.
    if msg == "help" or msg == "?" or msg == "commands" then
        printVcuiHelp()
        return
    end

    if not ns.UI or not ns.UI.ToggleMainFrame then
        ns:Print(L["UI not loaded. Likely a Lua error during init. Enable /console scriptErrors 1 and /reload."])
        return
    end

    local ok, err = pcall(function()
        if msg == "" or msg == "config" or msg == "options" then
            ns.UI:ToggleMainFrame()

        elseif msg == "reset" then
            if ns:InCombat() then ns:Print(L["Not possible in combat."]); return end
            StaticPopup_Show("VCUI_DB_RESET")

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

ns:RegisterSlash({ key = "IDTIP", commands = { "/idtip" },
    desc = "Open the tooltip ID settings.",
})
-- Straight to the handler, not through SlashCmdList: the key is namespaced now,
-- and a shortcut that reaches its target by global name breaks silently the day
-- the name changes -- which is exactly what happened here.
ns.Slash.IDTIP = function() ns.Slash.OPTIONS("tooltipids") end

ns:RegisterSlash({ key = "RELOAD", commands = { "/rl", "/reloadui" },
    desc = "Reload the interface. Refused while in combat.",
    note = "Replaces the game's own /reloadui so it cannot be run mid-fight.",
})
ns.Slash.RELOAD = function()
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Not possible in combat."])
        return
    end
    ReloadUI()
end
