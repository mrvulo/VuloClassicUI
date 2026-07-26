-- VuloClassicUI / Core / Events
-- Central event dispatcher: ns:RegisterEvent("EVENT", handler) instead of a
-- frame per module.
local _, ns = ...
local L = ns.L

local dispatcher = CreateFrame("Frame", "VuloClassicUIEventDispatcher")
ns.eventFrame = dispatcher

local handlers = {}  -- event -> { handler1, handler2, ... }

function ns:RegisterEvent(event, handler)
    if not handlers[event] then
        -- pcall: not all events exist in every WoW version
        -- (e.g. INSPECT_TALENT_READY does not exist in Anniversary). Silently ignore.
        local ok = pcall(dispatcher.RegisterEvent, dispatcher, event)
        if not ok then return end
        handlers[event] = {}
    end
    table.insert(handlers[event], handler)
end

function ns:UnregisterEvent(event, handler)
    if not handlers[event] then return end
    for i = #handlers[event], 1, -1 do
        if handlers[event][i] == handler then
            table.remove(handlers[event], i)
        end
    end
    if #handlers[event] == 0 then
        handlers[event] = nil
        pcall(dispatcher.UnregisterEvent, dispatcher, event)
    end
end

-- The combat-heavy events fire thousands of times per second in a raid with
-- several listeners each; a pcall per handler per firing is the hottest shared
-- code in the addon. These dispatch unprotected: an error surfaces through
-- Blizzard's error handler (louder, which such a bug deserves) and skips the
-- remaining handlers for that one firing only. Everything else keeps the
-- isolated per-handler pcall with the friendly chat message.
local HOT = {
    COMBAT_LOG_EVENT_UNFILTERED = true,
    UNIT_AURA = true,
    UNIT_HEALTH = true,
    UNIT_HEALTH_FREQUENT = true,
    UNIT_POWER_UPDATE = true,
    UNIT_POWER_FREQUENT = true,
}

dispatcher:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    if HOT[event] then
        for i = 1, #list do
            list[i](event, ...)
        end
        return
    end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then
            ns:Print(L["|cffff5555Event handler error (%s):|r %s"], event, tostring(err))
        end
    end
end)
