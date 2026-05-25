-- =========================================================
-- VuloClassicUI / Modules / FixInspect
-- Behebt h\195\164ufige Inspect-Bugs in Anniversary:
--   1. Blizzard ruft ClearInspectPlayer() nicht zuverl\195\164ssig wenn InspectFrame
--      geschlossen wird → Server denkt Inspect l\195\164uft noch → n\195\164chster Inspect
--      eines anderen Spielers schl\195\164gt fehl.
--   2. Stuck-State: INSPECT_READY kommt nie zur\195\188ck (Spieler out of range,
--      Disconnect, oder Server-Timeout) → permanenter pending-State.
--   Wir trackt aktive Inspects mit Timestamp und resette automatisch wenn
--   nach 8s nichts zur\195\188ckkam, plus Cleanup beim InspectFrame:OnHide.
-- Slash: /inspectreset — manueller Force-Reset wenn UI komplett stuck ist.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("fixinspect", {
    name        = "Inspect Fix",
    group       = "Bugfixes",
    description = "Behebt stuck-Inspect-Bugs (kein Spieler-Inspect mehr m\195\182glich nach fehlerhaftem Close/Timeout). Auto-Reset nach 8s + Cleanup beim InspectFrame schlie\195\159en + /inspectreset Slash-Command.",
    defaults = {
        enabled    = true,
        autoReset  = true,
        timeoutSec = 8,
    },
})

-- =========================================================
-- State
-- =========================================================
local _activeGUID  = nil
local _activeTime  = 0
local _hookedFrame = false
local _hookedNotify = false
local _watchdog

-- =========================================================
-- Helpers
-- =========================================================
local function resetInspect()
    if _G.ClearInspectPlayer then
        pcall(_G.ClearInspectPlayer)
    end
    _activeGUID = nil
    _activeTime = 0
end

local function onInspectReady()
    -- Server hat geantwortet — tracking-state aufr\195\164umen
    _activeGUID = nil
    _activeTime = 0
end

-- Wird gehookt: NotifyInspect → wir markieren den pending-State
local function trackNotifyInspect(unit)
    if not unit or not UnitExists(unit) then return end
    _activeGUID = UnitGUID(unit)
    _activeTime = GetTime()
end

local function hookNotifyInspect()
    if _hookedNotify then return end
    if type(_G.NotifyInspect) ~= "function" then return end
    -- hooksecurefunc l\195\164uft NACH dem Original-Call, taintet nichts
    hooksecurefunc("NotifyInspect", trackNotifyInspect)
    _hookedNotify = true
end

local function hookInspectFrame()
    if _hookedFrame then return end
    local f = _G.InspectFrame
    if not f then return end
    -- Auto-cleanup beim Schlie\195\159en — Blizzard macht das nicht zuverl\195\164ssig
    f:HookScript("OnHide", function()
        if mod._enabled then resetInspect() end
    end)
    _hookedFrame = true
end

-- Watchdog: pr\195\188ft alle 2s ob pending-Inspect zu alt ist → reset
local function watchdogTick()
    if not mod._enabled or not mod.db or not mod.db.autoReset then return end
    if _activeTime == 0 then return end
    local timeout = mod.db.timeoutSec or 8
    if GetTime() - _activeTime > timeout then
        resetInspect()
    end
end

-- =========================================================
-- Slash-Command f\195\188r manuellen Reset
-- =========================================================
_G.SLASH_VCUIINSPECTRESET1 = "/inspectreset"
_G.SlashCmdList["VCUIINSPECTRESET"] = function()
    resetInspect()
    if ns and ns.Print then
        ns:Print("Inspect-State manuell zur\195\188ckgesetzt. Versuche jetzt erneut.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[VuloClassicUI]|r Inspect-State zur\195\188ckgesetzt.")
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
local installFrame

function mod:OnEnable()
    if not mod.db then return end

    -- Sofort versuchen (NotifyInspect ist global verf\195\188gbar)
    hookNotifyInspect()
    hookInspectFrame()

    -- ADDON_LOADED f\195\188r Blizzard_InspectUI (wird lazy geladen)
    if not installFrame then
        installFrame = CreateFrame("Frame")
        installFrame:RegisterEvent("ADDON_LOADED")
        installFrame:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_InspectUI" then
                hookInspectFrame()
            end
        end)
    end

    -- INSPECT_READY clearing
    ns:RegisterEvent("INSPECT_READY", onInspectReady)

    -- Watchdog-Ticker (2s)
    if not _watchdog and C_Timer and C_Timer.NewTicker then
        _watchdog = C_Timer.NewTicker(2, watchdogTick)
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("INSPECT_READY", onInspectReady)
    if _watchdog then _watchdog:Cancel(); _watchdog = nil end
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = "Verhalten" },

        { type = "toggle", label = "Auto-Reset bei Timeout",
          tooltip = "Wenn nach X Sekunden keine Antwort vom Server kommt, wird der pending Inspect-State automatisch zur\195\188ckgesetzt — damit der n\195\164chste Inspect-Versuch wieder funktioniert.",
          get = function() return mod.db.autoReset ~= false end,
          set = function(_, v) mod.db.autoReset = v end },

        { type = "slider", label = "Timeout (Sekunden)",
          min = 3, max = 20, step = 1,
          tooltip = "Wie lange auf INSPECT_READY warten bevor Auto-Reset greift. 8 Sekunden ist ein guter Default — schnell genug f\195\188r out-of-range, langsam genug um normale Server-Lag nicht abzubrechen.",
          get = function() return mod.db.timeoutSec or 8 end,
          set = function(_, v) mod.db.timeoutSec = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = "Manueller Reset" },
        { type = "button", label = "Inspect-State jetzt zur\195\188cksetzen", width = 240,
          onClick = function()
              resetInspect()
              ns:Print("Inspect-State manuell zur\195\188ckgesetzt.")
          end },
        { type = "desc", text = "|cffaaaaaaSlash-Command: /inspectreset|r" },

        { type = "spacer", height = 8 },
        { type = "header", text = "Status" },
        { type = "desc", text = string.format(
            "NotifyInspect Hook: %s\nInspectFrame Hook: %s",
            _hookedNotify and "|cff66ff66aktiv|r" or "|cffff8800wartet|r",
            _hookedFrame  and "|cff66ff66aktiv|r" or "|cffff8800wartet auf Blizzard_InspectUI|r") },
        { type = "spacer", height = 4 },
        { type = "desc", text = "|cffaaaaaaWas der Fix macht: trackt aktive Inspects mit Timestamp, ruft ClearInspectPlayer() beim Schlie\195\159en + bei Timeout auf. Verhindert dass ein stuck-State alle nachfolgenden Inspects blockiert.|r" },
    }
end
