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

-- reason tells a swing that LANDED from a swing that merely MOVED. Both are news
-- for anything drawing a bar, and only the first is news for anything counting
-- attacks: the seal-twist helper steps its rotation past an auto-attack on this
-- callback, and a parry -- which pulls the swing forward without one landing --
-- stepped it a swing early. Consumers that ignore the second argument keep the
-- old behaviour, which is right for every consumer that only redraws.
--   nil / "swing" -- a swing landed (or the clock was cleared)
--   "shift"       -- the pending swing moved or restarted; nothing landed
--   "start"       -- a fresh swing began (attack started); nothing landed
-- Consumers that count attacks must test for the LANDED values rather than
-- excluding the known others: every reason added later is a non-landing one, so
-- a denylist quietly counts each new arrival as a swing.
local function notify(hand, reason)
    for _, fn in pairs(holders) do
        if type(fn) == "function" then
            local ok, err = pcall(fn, hand, reason)
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
    notify("mainhand", "shift")
end

-- Abilities that spend the main-hand swing instead of an auto-attack. Heroic
-- Strike, Cleave, Maul and Raptor Strike REPLACE the swing: the client logs the
-- ability and NO SWING_DAMAGE line ever arrives, so a clock that only listens
-- for swings hears nothing at all. The bar then stood still through every
-- queued strike and was retired two seconds later by the stale check -- worst
-- exactly for the classes that queue one on every swing. The cast that resets
-- the timer rather than replacing it (Slam) ends in the same place, so it is
-- listed here too.
--
-- Off-hand deliberately absent: all of these are main-hand abilities.
local ON_NEXT_SWING_IDS = {
    78,    -- Heroic Strike
    845,   -- Cleave
    1464,  -- Slam
    6807,  -- Maul
    2973,  -- Raptor Strike
}

-- The other half of the same rule, and the combat log structurally CANNOT see
-- it: these reset the swing without the player dealing damage, so no
-- SPELL_DAMAGE or SPELL_MISSED line is ever written for them. They are heard on
-- the cast instead. Repentance is the one that matters most here -- a
-- retribution paladin twisting seals presses it, and the seal-twist helper
-- reads this same clock, so a swing it did not know had restarted pointed the
-- twist window at a swing that was no longer coming.
-- Matched by ID, not by name, and deliberately so: none of these carry ranks
-- that a name would have to collapse, the cast hands us the id directly, and one
-- of them (the immolation oil) shares its name with a demon's ability -- an
-- exact id cannot be fooled by that, and it saves a lookup on every cast.
local ON_CAST_RESET = {
    [20066] = true,  -- Repentance
    [20549] = true,  -- War Stomp
    [5384]  = true,  -- Feign Death
    -- Healing potions, one id per tier; the tiers do not share a name, so each
    -- has to be listed to be seen.
    [439] = true, [440] = true, [441] = true, [2024] = true,
    [4042] = true, [17534] = true, [28495] = true,
    [41619] = true,  -- Cenarion Healing Salve
    [41620] = true,  -- Bottled Nethergon Vapor
    [11350] = true,  -- Oil of Immolation
}

-- Rank one of each, and the ranks a level seventy actually presses are the ones
-- missing from any hand-written id list. All ranks share their NAME, and the
-- client knows the name behind an id whether or not the player has that rank,
-- so one pass builds an index that covers every rank at once, in the client's
-- own language -- which is the language the combat log speaks. Built on first
-- use rather than at load: spell data is not reliably readable then.
--
-- An empty build is NOT cached: if spell data was unreadable at that moment,
-- caching the empty answer would silence the feature for the rest of the
-- session, and the retry costs one pass over five ids.
local ON_NEXT_SWING_NAMES

local function isOnNextSwing(spellName)
    if not spellName then return false end
    if not ON_NEXT_SWING_NAMES then
        if not GetSpellInfo then return false end
        local set, any = {}, false
        for _, id in ipairs(ON_NEXT_SWING_IDS) do
            local n = GetSpellInfo(id)
            if n then set[n] = true; any = true end
        end
        if not any then return false end
        ON_NEXT_SWING_NAMES = set
    end
    return ON_NEXT_SWING_NAMES[spellName] == true
end

local function isCastReset(spellID)
    return spellID ~= nil and ON_CAST_RESET[spellID] == true
end

-- Extra attacks (Reckoning, Windfury, Sword Specialisation) land as ordinary
-- SWING_DAMAGE lines, and a swing timer that believes them restarts the clock
-- on a hit that never cost a swing -- the bar then points a full weapon speed
-- past the truth. SPELL_EXTRA_ATTACKS announces how many are coming; we swallow
-- exactly that many main-hand lines afterwards.
--
-- The count carries a deadline because the announcement and the attacks are not
-- guaranteed to be adjacent: extra attacks can be STORED and spent after the
-- swing in progress. A stale credit that never got spent would otherwise eat a
-- real swing minutes later.
local EXTRA_WINDOW = 1.5
local extraLeft, extraUntil = 0, 0

-- Frame stamp of the last queued-ability hit, so a cleave hitting two targets
-- is one decision rather than two (see the branch that uses it).
local lastQueuedHit = 0

local function takeExtraCredit()
    if extraLeft <= 0 then return false end
    if GetTime() > extraUntil then extraLeft = 0; return false end
    extraLeft = extraLeft - 1
    return true
end

local function onCombatLog()
    local _, subevent, _, sourceGUID, _, _, _, destGUID = CLGetInfo()
    if sourceGUID ~= playerGUID then
        if destGUID == playerGUID then
            -- Parry haste does not care whether what we parried was a plain
            -- swing or a special: any parried MELEE attack hastens the parrying
            -- unit. Only the payload position of the miss type differs --
            -- SWING_MISSED puts it first, SPELL_MISSED behind the three spell
            -- fields.
            if subevent == "SWING_MISSED" then
                if select(12, CLGetInfo()) == "PARRY" then parryHaste() end
            elseif subevent == "SPELL_MISSED" then
                if select(15, CLGetInfo()) == "PARRY" then parryHaste() end
            end
        end
        return
    end
    if subevent == "SWING_DAMAGE" then
        -- isOffHand is param 21 of SWING_DAMAGE.
        local isOffHand = select(21, CLGetInfo())
        if isOffHand then
            resetOH(); notify("offhand")
        elseif not takeExtraCredit() then
            resetMH(); notify("mainhand")
        end
    elseif subevent == "SWING_MISSED" then
        -- SWING_MISSED puts isOffHand at param 13, or 14 when an amount is present.
        local p13, p14 = select(13, CLGetInfo())
        if (p13 == true) or (p14 == true) then
            resetOH(); notify("offhand")
        elseif not takeExtraCredit() then
            resetMH(); notify("mainhand")
        end
    elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_MISSED" then
        -- spellName is payload field 13 for every SPELL_ prefix. An ability that
        -- spends the swing costs it whether it lands or is dodged, so the miss
        -- line counts exactly like the damage line.
        --
        -- The extra-attack credit is spent HERE as well, and that is not
        -- symmetry for its own sake: an extra attack landing while one of these
        -- is queued is consumed BY the queued ability, so it arrives as the
        -- ability's own line and not as a swing. Skipping the credit here cost
        -- twice over -- the free attacks restarted the clock as though they had
        -- cost a swing, and the credit then sat waiting to swallow the next real
        -- swing instead.
        -- One decision per ability, not per target: a cleave writes one line per
        -- target for a SINGLE swing, and both lines asked the credit separately
        -- -- the first spent it, the second then restarted the clock on what may
        -- have been a free attack. GetTime is constant within a frame and both
        -- lines dispatch in the same one, so the timestamp is the frame's
        -- identity.
        if isOnNextSwing(select(13, CLGetInfo())) then
            local now = GetTime()
            if now ~= lastQueuedHit then
                lastQueuedHit = now
                if not takeExtraCredit() then resetMH(); notify("mainhand") end
            end
        end
    elseif subevent == "SPELL_EXTRA_ATTACKS" then
        -- amount is the last payload field; 12..14 are spellId, name, school.
        local amount = select(15, CLGetInfo())
        amount = tonumber(amount) or 0
        if amount > 0 then
            extraLeft = extraLeft + amount
            extraUntil = GetTime() + EXTRA_WINDOW
        end
    end
end

local function onEvent(_, event, arg1, _, arg3)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        onCombatLog()
    elseif event == "PLAYER_ENTER_COMBAT" then
        recomputeDualWield()
        resetMH()
        if dualWield then resetOH() end
        -- Starting to attack is not an attack landing. Nothing reset the
        -- seal-twist rotation at a combat boundary, so a pull that ended on an
        -- auto-attack step had the NEXT pull's first swing counted before a
        -- single one had landed.
        notify("mainhand", "start")
    elseif event == "PLAYER_LEAVE_COMBAT" then
        mh.active, oh.active = false, false
        extraLeft = 0
        notify(nil)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unit, castGUID, spellID) on this client. Only a swing already running
        -- can be restarted: pressing one of these out of combat must not start a
        -- clock, or the bar would claim a swing nobody threw.
        -- "shift", not a landing: the swing was RESTARTED, nothing was struck.
        -- Tagging it is the whole reason the tag exists -- a helper that counts
        -- auto-attacks would otherwise step forward on a stun or a potion.
        if arg1 == "player" and mh.active and isCastReset(arg3) then
            resetMH(); notify("mainhand", "shift")
        end
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
        frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        frame:RegisterEvent("UNIT_ATTACK_SPEED")
        frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
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

-- UNIT_ATTACK_SPEED is the fast path and stays the primary one, but a swing bar
-- whose whole job is to be right about haste cannot rest on one event firing.
-- So the same question is asked a second way, cheaply: every tenth of a second
-- at most, and only while a swing is actually running, the in-flight duration is
-- compared against what the client reports. Equal means the event did its job
-- and nothing happens; different means it did not, and the rescale that the
-- event would have run happens here instead. The comparison is what deduplicates
-- the two paths -- neither can double-apply.
--
-- The reference for this feature polls the same API four times per FRAME; a
-- tenth of a second is two orders of magnitude cheaper and cannot drift visibly
-- at the speed a bar is read.
local VERIFY_EVERY = 0.1
local lastVerify = 0

local function verifySpeeds()
    if not (mh.active or oh.active) then return end
    local t = GetTime()
    if t - lastVerify < VERIFY_EVERY then return end
    lastVerify = t
    local mainSpeed, offSpeed = UnitAttackSpeed("player")
    local drifted = (mh.active and mainSpeed and mainSpeed > 0 and mh.dur ~= mainSpeed)
                 or (oh.active and offSpeed  and offSpeed  > 0 and oh.dur ~= offSpeed)
    if drifted then rescale() end
end

local function prune(s)
    if s.active and s.dur > 0 and (GetTime() - s.start) > s.dur + STALE_AFTER then
        s.active = false
    end
    return s
end

-- start, duration, active. Callers must treat a false "active" as "no swing
-- known" rather than "swing at time 0".
function ns:GetSwing(hand)
    verifySpeeds()
    local s = prune((hand == "offhand") and oh or mh)
    return s.start, s.dur, s.active
end

-- Seconds until the next swing lands, or nil when there is no live swing.
function ns:SwingRemaining(hand)
    verifySpeeds()
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
