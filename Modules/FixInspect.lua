-- =========================================================
-- VuloClassicUI / Modules / FixInspect
-- Aggressive fix for Anniversary inspect bugs:
--   1. Empty frame / no items shown
--   2. Shows previous target's data (stuck cache)
--   3. Nothing happens at all
--   4. Only works on second attempt
-- All caused by the same root: Blizzard's inspect server-state gets stuck
-- and ClearInspectPlayer() is never called reliably.
--
-- Strategy:
--   - RAW replacement of NotifyInspect + InspectUnit: ALWAYS clear before request
--   - InspectFrame:OnHide → full reset (clears unit, clears server state)
--   - Watchdog: 5s timeout for stuck pending state
--   - Slash: /inspectreset (force reset), /inspectstate (debug info)
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixinspect", {
    name        = L["Inspect Fix"],
    group       = "Bugfixes",
    description = L["Fixes stuck inspect bugs (no player inspect possible after a faulty close/timeout). Auto-reset after 8s + cleanup when InspectFrame closes + /inspectreset slash command."],
    defaults = {
        enabled         = true,
        aggressiveReset = true,   -- ALWAYS clear server state before NotifyInspect
        autoReset       = true,
        timeoutSec      = 5,      -- shorter than 8s — Anniversary is slow to clear
    },
})

-- =========================================================
-- State
-- =========================================================
local _activeGUID         = nil
local _activeTime         = 0
local _hookedFrame        = false
local _origNotifyInspect  = nil
local _origInspectUnit    = nil
local _watchdog

-- =========================================================
-- Core reset
-- =========================================================
local function fullReset()
    if _G.ClearInspectPlayer then
        pcall(_G.ClearInspectPlayer)
    end
    -- Invalidate UI's cached unit so next inspect doesn't show old data
    local f = _G.InspectFrame
    if f then f.unit = nil end
    _activeGUID = nil
    _activeTime = 0
end

local function onInspectReady()
    -- Server responded — clean our tracking, but don't full-reset (UI uses the data)
    _activeGUID = nil
    _activeTime = 0
end

-- =========================================================
-- RAW wrappers (replace NotifyInspect + InspectUnit directly)
-- This is the only reliable way to clear BEFORE the request is sent.
-- hooksecurefunc would run AFTER and that's too late.
-- =========================================================
local function installNotifyInspectWrapper()
    if _origNotifyInspect or type(_G.NotifyInspect) ~= "function" then return end
    _origNotifyInspect = _G.NotifyInspect
    _G.NotifyInspect = function(unit)
        if mod._enabled and mod.db and mod.db.aggressiveReset then
            fullReset()  -- BEFORE the request → fresh state
        end
        if unit and UnitExists(unit) then
            _activeGUID = UnitGUID(unit)
            _activeTime = GetTime()
        end
        return _origNotifyInspect(unit)
    end
end

local function installInspectUnitWrapper()
    if _origInspectUnit or type(_G.InspectUnit) ~= "function" then return end
    _origInspectUnit = _G.InspectUnit
    _G.InspectUnit = function(unit)
        if mod._enabled and mod.db and mod.db.aggressiveReset then
            fullReset()  -- right-click menu route → also clean
        end
        return _origInspectUnit(unit)
    end
end

local function hookInspectFrame()
    if _hookedFrame then return end
    local f = _G.InspectFrame
    if not f then return end
    -- Aggressive cleanup on close — Blizzard doesn't do this reliably
    f:HookScript("OnHide", function()
        if mod._enabled then fullReset() end
    end)
    _hookedFrame = true
end

-- =========================================================
-- Watchdog: tighter 5s timeout
-- =========================================================
local function watchdogTick()
    if not mod._enabled or not mod.db or not mod.db.autoReset then return end
    if _activeTime == 0 then return end
    local timeout = mod.db.timeoutSec or 5
    if GetTime() - _activeTime > timeout then
        fullReset()
    end
end

-- =========================================================
-- Slash commands
-- =========================================================
_G.SLASH_VCUIINSPECTRESET1 = "/inspectreset"
_G.SlashCmdList["VCUIINSPECTRESET"] = function()
    fullReset()
    if _G.InspectFrame and _G.InspectFrame:IsShown() then
        _G.InspectFrame:Hide()
    end
    if ns and ns.Print then
        ns:Print(L["Inspect state manually reset. Try again now."])
    else
        DEFAULT_CHAT_FRAME:AddMessage(L["|cffffff00[VuloClassicUI]|r Inspect state reset."])
    end
end

_G.SLASH_VCUIINSPECTSTATE1 = "/inspectstate"
_G.SlashCmdList["VCUIINSPECTSTATE"] = function()
    local f = _G.InspectFrame
    local lines = {
        "|cffffff00[VuloClassicUI Inspect State]|r",
        string.format("  NotifyInspect override: %s", _origNotifyInspect and "yes" or "no"),
        string.format("  InspectUnit override:   %s", _origInspectUnit   and "yes" or "no"),
        string.format("  InspectFrame hook:      %s", _hookedFrame      and "yes" or "no"),
        string.format("  Active GUID:            %s", tostring(_activeGUID)),
        string.format("  Active time:            %s", _activeTime > 0 and string.format("%.1fs ago", GetTime() - _activeTime) or "none"),
        string.format("  InspectFrame.unit:      %s", f and tostring(f.unit) or "no frame"),
        string.format("  InspectFrame shown:     %s", (f and f:IsShown()) and "yes" or "no"),
    }
    for _, line in ipairs(lines) do
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
local installFrame

function mod:OnEnable()
    if not mod.db then return end

    -- Install raw wrappers immediately (NotifyInspect + InspectUnit are global)
    installNotifyInspectWrapper()
    installInspectUnitWrapper()
    hookInspectFrame()

    -- ADDON_LOADED for Blizzard_InspectUI (lazy-loaded the first time Inspect is opened)
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

    -- Watchdog ticker (2s tick, 5s timeout by default)
    if not _watchdog and C_Timer and C_Timer.NewTicker then
        _watchdog = C_Timer.NewTicker(2, watchdogTick)
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("INSPECT_READY", onInspectReady)
    if _watchdog then _watchdog:Cancel(); _watchdog = nil end
    -- Note: We don't restore the original NotifyInspect/InspectUnit because
    -- other code may already hold references to our wrapped versions.
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = L["Behavior"] },

        { type = "toggle", label = L["Aggressive reset before each inspect"],
          tooltip = L["Force-clears the inspect state before every NotifyInspect/InspectUnit call. Recommended for Anniversary because Blizzard's UI doesn't reliably clear the previous target's cache. Disable only if you have compatibility issues with another inspect addon."],
          get = function() return mod.db.aggressiveReset ~= false end,
          set = function(_, v) mod.db.aggressiveReset = v end },

        { type = "toggle", label = L["Auto-reset on timeout"],
          tooltip = L["If no response from the server comes after X seconds, the pending inspect state is automatically reset — so the next inspect attempt works again."],
          get = function() return mod.db.autoReset ~= false end,
          set = function(_, v) mod.db.autoReset = v end },

        { type = "slider", label = L["Timeout (seconds)"],
          min = 3, max = 20, step = 1,
          tooltip = L["How long to wait for INSPECT_READY before auto-reset kicks in. 5 seconds is the new default for Anniversary — fast enough to recover quickly."],
          get = function() return mod.db.timeoutSec or 5 end,
          set = function(_, v) mod.db.timeoutSec = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Manual Reset"] },
        { type = "button", label = L["Reset inspect state now"], width = 240,
          onClick = function()
              fullReset()
              if _G.InspectFrame and _G.InspectFrame:IsShown() then
                  _G.InspectFrame:Hide()
              end
              ns:Print(L["Inspect state manually reset."])
          end },
        { type = "desc", text = L["|cffaaaaaaSlash commands: /inspectreset (force-reset), /inspectstate (debug info in chat)|r"] },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Status"] },
        { type = "desc", text = string.format(
            L["NotifyInspect override: %s\nInspectUnit override:   %s\nInspectFrame hook:      %s"],
            _origNotifyInspect and L["|cff66ff66active|r"] or L["|cffff8800waiting|r"],
            _origInspectUnit   and L["|cff66ff66active|r"] or L["|cffff8800waiting|r"],
            _hookedFrame       and L["|cff66ff66active|r"] or L["|cffff8800waiting for Blizzard_InspectUI|r"]) },
        { type = "spacer", height = 4 },
        { type = "desc", text = L["|cffaaaaaaWhat the fix does: replaces NotifyInspect and InspectUnit with wrappers that force-clear server state before each request. Plus full reset when the inspect frame closes or after a 5s timeout.|r"] },
    }
end
