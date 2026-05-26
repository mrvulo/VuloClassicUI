-- =========================================================
-- VuloClassicUI / Core / Events
-- Central event dispatcher.
-- Modules can call ns:RegisterEvent("EVENT", function(...) end)
-- instead of creating their own frame each time.
-- =========================================================
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

dispatcher:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, h in ipairs(list) do
        local ok, err = pcall(h, event, ...)
        if not ok then
            ns:Print(L["|cffff5555Event handler error (%s):|r %s"], event, tostring(err))
        end
    end
end)
