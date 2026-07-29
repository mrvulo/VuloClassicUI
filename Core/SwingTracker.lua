-- Shared weapon-swing state.
--
-- Two features want to know when the next auto-attack lands: the swing bars and
-- the paladin seal-twist helper. Both used to be free to parse
-- COMBAT_LOG_EVENT_UNFILTERED themselves, which meant paying for the same busy
-- event twice and -- worse -- letting two copies of the same clock disagree by a
-- frame. This owns the state; consumers read it.
--
-- The tracker only listens while somebody holds it, so a character with neither
-- feature on registers nothing at all.
local _, ns = ...

local CLGetInfo = CombatLogGetCurrentEventInfo
local GetTime, UnitAttackSpeed, UnitGUID = GetTime, UnitAttackSpeed, UnitGUID
local GetInventoryItemID = GetInventoryItemID

local mh = { start = 0, dur = 0, active = false }
local oh = { start = 0, dur = 0, active = false }
local dualWield = false
local playerGUID
local mhItem, ohItem

local holders    = {}   -- tag -> listener function or true
local holderCount = 0
local frame

local function notify(hand)
    for _, fn in pairs(holders) do
        if type(fn) == "function" then
            local ok, err = pcall(fn, hand)
            if not ok then geterrorhandler()(err) end
        end
    end
end

local function recomputeDualWield()
    local _, offSpeed = UnitAttackSpeed("player")
    dualWield = (offSpeed ~= nil and offSpeed > 0)
end

-- Seed the weapon snapshot so the first inventory event after login is not read
-- as a weapon swap.
local function snapshotWeapons()
    mhItem, ohItem = GetInventoryItemID("player", 16), GetInventoryItemID("player", 17)
end

local function resetMH()
    local mainSpeed = UnitAttackSpeed("player")
    if not mainSpeed or mainSpeed <= 0 then return end
    mh.start, mh.dur, mh.active = GetTime(), mainSpeed, true
end

local function resetOH()
    local _, offSpeed = UnitAttackSpeed("player")
    if not offSpeed or offSpeed <= 0 then return end
    oh.start, oh.dur, oh.active = GetTime(), offSpeed, true
end

-- A haste change mid-swing keeps the elapsed fraction; it does not restart the
-- swing. Scaling the remainder is what the game itself does.
local function rescale()
    local mainSpeed, offSpeed = UnitAttackSpeed("player")
    local t = GetTime()
    if mh.active and mainSpeed and mainSpeed > 0 and mh.dur > 0 then
        local frac = (t - mh.start) / mh.dur
        if frac < 1 then mh.dur = mainSpeed; mh.start = t - frac * mh.dur end
    end
    if oh.active and offSpeed and offSpeed > 0 and oh.dur > 0 then
        local frac = (t - oh.start) / oh.dur
        if frac < 1 then oh.dur = offSpeed; oh.start = t - frac * oh.dur end
    end
end

-- Parry haste. A unit that PARRIES gets its own next swing pulled forward by
-- 40% of its weapon speed, floored at 20% of that speed still to go -- so this
-- is about attacks coming AT us, not the ones we land. It is the one thing that
-- moves the swing without an event of its own, and for a seal twist it moves
-- the whole window: a bar that ignores it points at a swing that already
-- happened.
--
-- Main hand only: the reduction is a property of the swing timer the client
-- hastens, and every consumer we have reads the main hand.
local function parryHaste()
    if not mh.active or mh.dur <= 0 then return end
    local now = GetTime()
    local left = (mh.start + mh.dur) - now
    if left <= 0 then return end
    local newLeft = left - mh.dur * 0.4
    local floorLeft = mh.dur * 0.2
    if newLeft < floorLeft then newLeft = floorLeft end
    if newLeft >= left then return end
    mh.start = now + newLeft - mh.dur
    notify("mainhand")
end

local function onCombatLog()
    local _, subevent, _, sourceGUID, _, _, _, destGUID = CLGetInfo()
    if sourceGUID ~= playerGUID then
        if destGUID == playerGUID and subevent == "SWING_MISSED"
            and select(12, CLGetInfo()) == "PARRY" then
            parryHaste()
        end
        return
    end
    if subevent == "SWING_DAMAGE" then
        -- isOffHand is param 21 of SWING_DAMAGE.
        local isOffHand = select(21, CLGetInfo())
        if isOffHand then resetOH(); notify("offhand") else resetMH(); notify("mainhand") end
    elseif subevent == "SWING_MISSED" then
        -- SWING_MISSED puts isOffHand at param 13, or 14 when an amount is present.
        local p13, p14 = select(13, CLGetInfo())
        if (p13 == true) or (p14 == true) then resetOH(); notify("offhand") else resetMH(); notify("mainhand") end
    end
end

local function onEvent(_, event, arg1)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        onCombatLog()
    elseif event == "PLAYER_ENTER_COMBAT" then
        recomputeDualWield()
        resetMH()
        if dualWield then resetOH() end
        notify("mainhand")
    elseif event == "PLAYER_LEAVE_COMBAT" then
        mh.active, oh.active = false, false
        notify(nil)
    elseif event == "UNIT_ATTACK_SPEED" then
        rescale()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == nil or arg1 == "player" then
            recomputeDualWield()
            -- The event also fires for trinkets, bags and every enchant tick;
            -- only an actual weapon change restarts the swing, so compare the
            -- items rather than resetting on all of them.
            local newMH, newOH = GetInventoryItemID("player", 16), GetInventoryItemID("player", 17)
            local swapped = (newMH ~= mhItem) or (newOH ~= ohItem)
            mhItem, ohItem = newMH, newOH
            if swapped then
                if mh.active then resetMH() end
                if oh.active and dualWield then resetOH() end
            end
            notify(nil)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        playerGUID = UnitGUID("player")
        recomputeDualWield()
        snapshotWeapons()
    end
end

local function startListening()
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
    end
    playerGUID = playerGUID or UnitGUID("player")
    recomputeDualWield()
    snapshotWeapons()
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("PLAYER_ENTER_COMBAT")
    frame:RegisterEvent("PLAYER_LEAVE_COMBAT")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    if frame.RegisterUnitEvent then
        frame:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
    else
        frame:RegisterEvent("UNIT_ATTACK_SPEED")
    end
end

-- tag identifies the consumer, so a double Acquire from the same feature (module
-- re-enabled without a matching disable) cannot inflate the count and pin the
-- combat-log listener on forever.
function ns:AcquireSwingTracker(tag, onSwing)
    if not tag then return end
    if holders[tag] == nil then holderCount = holderCount + 1 end
    holders[tag] = onSwing or true
    -- Unconditional: RegisterEvent is idempotent, and a release down to zero
    -- unregisters on a frame that still exists, so "frame is created" is not the
    -- same question as "frame is listening".
    startListening()
end

function ns:ReleaseSwingTracker(tag)
    if not tag or holders[tag] == nil then return end
    holders[tag] = nil
    holderCount = holderCount - 1
    if holderCount <= 0 then
        holderCount = 0
        if frame then frame:UnregisterAllEvents() end
        mh.active, oh.active = false, false
    end
end

-- A swing this far past due means we lost the event that should have restarted
-- it -- a dropped combat-log line, or a PLAYER_LEAVE_COMBAT that never arrived.
-- Without this a bar sits pinned at full forever, so the check belongs here
-- rather than in each consumer: a consumer reading through an accessor cannot
-- retire the swing itself.
local STALE_AFTER = 2

local function prune(s)
    if s.active and s.dur > 0 and (GetTime() - s.start) > s.dur + STALE_AFTER then
        s.active = false
    end
    return s
end

-- start, duration, active. Callers must treat a false "active" as "no swing
-- known" rather than "swing at time 0".
function ns:GetSwing(hand)
    local s = prune((hand == "offhand") and oh or mh)
    return s.start, s.dur, s.active
end

-- Seconds until the next swing lands, or nil when there is no live swing.
function ns:SwingRemaining(hand)
    local s = prune((hand == "offhand") and oh or mh)
    if not s.active or s.dur <= 0 then return nil end
    local left = (s.start + s.dur) - GetTime()
    if left < 0 then return 0 end
    return left
end

-- Read fresh rather than from the cached field: consumers call this from their
-- own layout code, which can run before or after our UNIT_INVENTORY_CHANGED
-- handler in the same frame, and the answer must not depend on that order.
function ns:IsDualWielding()
    local _, offSpeed = UnitAttackSpeed("player")
    return (offSpeed ~= nil and offSpeed > 0)
end
