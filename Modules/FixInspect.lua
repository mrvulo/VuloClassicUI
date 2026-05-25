-- =========================================================
-- VuloClassicUI / Modules / FixInspect
-- Fixes common inspect bugs in Anniversary:
--   1. Blizzard doesn't reliably call ClearInspectPlayer() when InspectFrame
--      is closed -> server thinks inspect is still running -> next inspect
--      of another player fails.
--   2. Stuck state: INSPECT_READY never comes back (player out of range,
--      disconnect, or server timeout) -> permanent pending state.
--   We track active inspects with a timestamp and reset automatically when
--   nothing came back after 8s, plus cleanup on InspectFrame:OnHide.
-- Slash: /inspectreset — manual force-reset when the UI is completely stuck.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("fixinspect", {
    name        = "Inspect Fix",
    group       = "Bugfixes",
    description = "Fixes stuck inspect bugs (no player inspect possible after a faulty close/timeout). Auto-reset after 8s + cleanup when InspectFrame closes + /inspectreset slash command.",
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
    -- Server has responded — clean up tracking state
    _activeGUID = nil
    _activeTime = 0
end

-- Hooked: NotifyInspect -> we mark the pending state
local function trackNotifyInspect(unit)
    if not unit or not UnitExists(unit) then return end
    _activeGUID = UnitGUID(unit)
    _activeTime = GetTime()
end

local function hookNotifyInspect()
    if _hookedNotify then return end
    if type(_G.NotifyInspect) ~= "function" then return end
    -- hooksecurefunc runs AFTER the original call, doesn't taint anything
    hooksecurefunc("NotifyInspect", trackNotifyInspect)
    _hookedNotify = true
end

local function hookInspectFrame()
    if _hookedFrame then return end
    local f = _G.InspectFrame
    if not f then return end
    -- Auto-cleanup on close — Blizzard doesn't do this reliably
    f:HookScript("OnHide", function()
        if mod._enabled then resetInspect() end
    end)
    _hookedFrame = true
end

-- Watchdog: checks every 2s whether the pending inspect is too old -> reset
local function watchdogTick()
    if not mod._enabled or not mod.db or not mod.db.autoReset then return end
    if _activeTime == 0 then return end
    local timeout = mod.db.timeoutSec or 8
    if GetTime() - _activeTime > timeout then
        resetInspect()
    end
end

-- =========================================================
-- Slash command for manual reset
-- =========================================================
_G.SLASH_VCUIINSPECTRESET1 = "/inspectreset"
_G.SlashCmdList["VCUIINSPECTRESET"] = function()
    resetInspect()
    if ns and ns.Print then
        ns:Print("Inspect state manually reset. Try again now.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[VuloClassicUI]|r Inspect state reset.")
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
local installFrame

function mod:OnEnable()
    if not mod.db then return end

    -- Try immediately (NotifyInspect is available globally)
    hookNotifyInspect()
    hookInspectFrame()

    -- ADDON_LOADED for Blizzard_InspectUI (loaded lazily)
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

    -- Watchdog ticker (2s)
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
        { type = "header", text = "Behavior" },

        { type = "toggle", label = "Auto-reset on timeout",
          tooltip = "If no response from the server comes after X seconds, the pending inspect state is automatically reset — so the next inspect attempt works again.",
          get = function() return mod.db.autoReset ~= false end,
          set = function(_, v) mod.db.autoReset = v end },

        { type = "slider", label = "Timeout (seconds)",
          min = 3, max = 20, step = 1,
          tooltip = "How long to wait for INSPECT_READY before auto-reset kicks in. 8 seconds is a good default — fast enough for out-of-range, slow enough not to abort normal server lag.",
          get = function() return mod.db.timeoutSec or 8 end,
          set = function(_, v) mod.db.timeoutSec = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = "Manual Reset" },
        { type = "button", label = "Reset inspect state now", width = 240,
          onClick = function()
              resetInspect()
              ns:Print("Inspect state manually reset.")
          end },
        { type = "desc", text = "|cffaaaaaaSlash command: /inspectreset|r" },

        { type = "spacer", height = 8 },
        { type = "header", text = "Status" },
        { type = "desc", text = string.format(
            "NotifyInspect hook: %s\nInspectFrame hook: %s",
            _hookedNotify and "|cff66ff66active|r" or "|cffff8800waiting|r",
            _hookedFrame  and "|cff66ff66active|r" or "|cffff8800waiting for Blizzard_InspectUI|r") },
        { type = "spacer", height = 4 },
        { type = "desc", text = "|cffaaaaaaWhat the fix does: tracks active inspects with a timestamp, calls ClearInspectPlayer() on close + on timeout. Prevents a stuck state from blocking all subsequent inspects.|r" },
    }
end
