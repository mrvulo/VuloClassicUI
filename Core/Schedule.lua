-- VuloClassicUI / Core / Schedule
-- Two shared schedulers every module needs and nearly every module used to
-- hand-roll: a throttled ticker registry and a combat-deferral queue.
local _, ns = ...

-- ---------------------------------------------------------------------------
-- Shared ticker
--
-- A dozen modules each carried the same three lines: own frame, own OnUpdate,
-- own accumulator, early-return until the interval is up. Every one of them is
-- a separate C-to-Lua call on EVERY rendered frame, even while the module is
-- idle -- an empty OnUpdate still pays the call, which is the whole cost.
--
-- One driver takes that down to a single call per frame plus a cheap in-VM walk,
-- and -- the part that actually matters -- it HIDES itself when the last
-- subscriber leaves. A hidden frame runs no OnUpdate at all, so an idle UI costs
-- exactly nothing. Blizzard parks its own state-driver manager the same way.

local driver = CreateFrame("Frame")
driver:Hide()

local subs, count = {}, 0

local function tick(_, elapsed)
    local i = 1
    while i <= count do
        local s = subs[i]
        s.acc = s.acc + elapsed
        if s.acc >= s.interval then
            s.acc = 0
            s.fn(s.arg)
        end
        -- A callback may cancel itself (or a neighbour). Removal swaps the last
        -- entry into this slot, so only advance when the slot is untouched --
        -- otherwise the entry that moved here would be skipped for this tick.
        if subs[i] == s then i = i + 1 end
    end
end
driver:SetScript("OnUpdate", tick)

-- interval in seconds, fn(arg). Returns a handle for ns:CancelTicker.
-- The first call is one full interval away, exactly like the hand-rolled form.
function ns:AddTicker(interval, fn, arg)
    if type(fn) ~= "function" then return nil end
    local s = { interval = interval or 0.1, fn = fn, arg = arg, acc = 0 }
    count = count + 1
    subs[count] = s
    s.slot = count
    if count == 1 then driver:Show() end
    return s
end

function ns:CancelTicker(handle)
    if not handle then return false end
    local slot = handle.slot
    if not slot or subs[slot] ~= handle then return false end   -- already gone
    local last = subs[count]
    subs[slot] = last
    last.slot = slot
    subs[count] = nil
    count = count - 1
    handle.slot = nil
    if count == 0 then driver:Hide() end
    return true
end

-- Debug aid: how much is actually running right now.
function ns:TickerCount() return count end

-- ---------------------------------------------------------------------------
-- Combat deferral
--
-- Nine call sites carried the same guard by hand, each with its own pending
-- flag and its own drain. The guard half is genuinely identical everywhere;
-- the drains are not, so this only takes over the "do it once it is safe" case.

local pending = {}
local regen = CreateFrame("Frame")

local function drain()
    -- The event firing is not proof lockdown has lifted (rapid re-entry, and it
    -- also fires around loading screens), so ask the live API.
    if InCombatLockdown() then return end
    if #pending == 0 then return end
    -- Swap BEFORE draining: a job that queues another job must land in a fresh
    -- list, not in the one being walked.
    local jobs = pending
    pending = {}
    for i = 1, #jobs do
        local j = jobs[i]
        local ok, err = pcall(j.fn, j[1], j[2], j[3], j[4])
        if not ok then geterrorhandler()(err) end
    end
end

regen:RegisterEvent("PLAYER_REGEN_ENABLED")
regen:SetScript("OnEvent", drain)

-- Runs fn(...) now when out of combat, otherwise once combat ends.
-- Up to four arguments are carried; more than that wants a closure anyway.
function ns:RunOutOfCombat(fn, ...)
    if type(fn) ~= "function" then return end
    if not InCombatLockdown() then
        fn(...)
        return
    end
    pending[#pending + 1] = { fn = fn, ... }
end

-- Same, but at most one queued job per key: a layout that gets requested forty
-- times during a fight must not run forty times when it ends.
local keyed = {}
function ns:RunOutOfCombatOnce(key, fn, ...)
    if type(fn) ~= "function" then return end
    if not InCombatLockdown() then
        keyed[key] = nil
        fn(...)
        return
    end
    if keyed[key] then return end
    keyed[key] = true
    ns:RunOutOfCombat(function(...)
        keyed[key] = nil
        fn(...)
    end, ...)
end
