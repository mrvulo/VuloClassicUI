-- =========================================================
-- VuloClassicUI / Modules / FixLFGBrowseNil
-- Behebt einen Bug im Anniversary GroupFinder (Vanilla-Style) wo
-- LFGBrowseSearchEntry_Update mit veralteten resultIDs aufgerufen wird:
--   C_LFGList.GetSearchResultInfo(resultID) gibt nil zurück, weil das
--   Result vom Server inzwischen entfernt wurde — Blizzards Update-Funktion
--   indiziert dann auf nil und crasht (Blizzard_LFGVanilla_Browse.lua:267).
-- Wrappt LFGBrowseSearchEntry_Update in xpcall — defekte Einträge bleiben
-- mit ihrem alten Zustand sichtbar bis Blizzards Refresh sie neu zeichnet.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("fixlfgbrowsenil", {
    name        = "LFG Browse Nil Fix",
    group       = "Bugfixes",
    description = "F\195\164ngt Lua-Fehler im Anniversary Group-Finder ab (LFGBrowseSearchEntry_Update mit veralteten resultIDs). Verhindert Chat-Spam und kaputte Browse-Listen.",
    defaults = {
        enabled    = true,
        showReport = true,  -- einmalig pro Session melden
    },
})

local unpack = unpack or table.unpack

-- =========================================================
-- Installation
-- =========================================================
local wrappedAlready = false

local function installPatch()
    if wrappedAlready then return end
    if type(_G.LFGBrowseSearchEntry_Update) ~= "function" then return end

    local Original = _G.LFGBrowseSearchEntry_Update

    _G.LFGBrowseSearchEntry_Update = function(button, ...)
        if not mod._enabled then
            return Original(button, ...)
        end

        local args = { ... }
        local ok, err = xpcall(function()
            return Original(button, unpack(args))
        end, function(e) return e end)

        if ok then return end

        local errText = tostring(err or "")
        -- Bekannter Anniversary-Bug: searchResultInfo wird nil weil Server-Result
        -- veraltet ist. Silent return — Blizzards n\195\164chster Refresh r\195\164umt auf.
        if errText:find("searchResultInfo") or errText:find("attempt to index") then
            if mod.db.showReport and not _G.VCUI_LFGBrowseNilFix_Reported then
                _G.VCUI_LFGBrowseNilFix_Reported = true
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffffff00[VuloClassicUI]|r Blizzard LFG-Browse Fehler abgefangen (veralteter Eintrag \195\188bersprungen).")
            end
            return
        end

        -- Andere Fehler durchreichen damit BugSack & Co was sehen
        error(errText)
    end

    wrappedAlready = true
end

-- =========================================================
-- Lifecycle
-- =========================================================
local installFrame

function mod:OnEnable()
    if not installFrame then
        installFrame = CreateFrame("Frame")
        installFrame:RegisterEvent("ADDON_LOADED")
        installFrame:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_GroupFinder_VanillaStyle" then
                installPatch()
            end
        end)
    end

    -- Direkt versuchen (falls Addon schon geladen ist)
    installPatch()
    -- Plus ein delayed retry f\195\188r Edge-Cases
    if C_Timer and C_Timer.After then
        C_Timer.After(1, installPatch)
    end
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = "Verhalten" },
        {
            type = "toggle", label = "Chat-Nachricht beim ersten Fehler",
            tooltip = "Zeigt einmalig pro Session eine kurze Nachricht im Chat wenn ein LFG-Browse-Fehler abgefangen wurde.",
            get = function() return mod.db.showReport end,
            set = function(_, v) mod.db.showReport = v end,
        },
        { type = "spacer", height = 8 },
        { type = "desc", text = "Dieser Fix wickelt Blizzards |cffffffffLFGBrowseSearchEntry_Update|r-Funktion in einen gesch\195\188tzten Aufruf (xpcall) ein. Wenn der Eintrag wegen einer veralteten resultID crasht (\"searchResultInfo nil\"), wird der Fehler verschluckt — Blizzards n\195\164chster Refresh r\195\164umt den Listen-Eintrag automatisch auf." },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format("|cffaaaaaaStatus: %s|r",
            wrappedAlready and "|cff66ff66Hook aktiv|r" or "wartet auf Blizzard_GroupFinder_VanillaStyle") },
    }
end
