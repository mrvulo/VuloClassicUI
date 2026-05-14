-- =========================================================
-- VuloClassicUI / Core / Events
-- Zentraler Event-Dispatcher.
-- Module können ns:RegisterEvent("EVENT", function(...) end) machen,
-- statt jedes Mal einen eigenen Frame zu erstellen.
-- =========================================================
local _, ns = ...

local dispatcher = CreateFrame("Frame", "VuloClassicUIEventDispatcher")
ns.eventFrame = dispatcher

local handlers = {}  -- event -> { handler1, handler2, ... }

function ns:RegisterEvent(event, handler)
    if not handlers[event] then
        handlers[event] = {}
        dispatcher:RegisterEvent(event)
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
        dispatcher:UnregisterEvent(event)
    end
end

dispatcher:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, h in ipairs(list) do
        local ok, err = pcall(h, event, ...)
        if not ok then
            ns:Print("|cffff5555Event-Handler-Fehler (%s):|r %s", event, tostring(err))
        end
    end
end)
