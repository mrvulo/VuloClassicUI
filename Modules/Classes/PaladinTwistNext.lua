-- Paladin seal twist: what to press next.
--
-- The bar says WHEN, this says WHAT. It is deliberately a separate question:
-- the zones are geometry and follow from the swing clock alone, while the next
-- action also depends on the global cooldown, on which seals are actually up,
-- on whether Crusader Strike still fits in front of the window, and on how long
-- the strike has already been sitting there going to waste.
--
-- ONE DECISION, TWO RENDERINGS. ST.Decide is the only place that answers the
-- question. The bar draws the answer as a word under the swing; the guide below
-- draws it as an icon wherever the player put it. Anything else and the two
-- displays start disagreeing in front of somebody who is trying to learn a
-- rotation from them.
--
-- See the header of Paladin.lua for why the helper is split at all.
local _, ns = ...
local L = ns.L

local ST = ns.SealTwist
if not ST then return end

local GetSpellCooldown, GetTime = GetSpellCooldown, GetTime
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitExists, UnitCanAttack = UnitExists, UnitCanAttack
local UnitAffectingCombat = UnitAffectingCombat

-- ACTION_* are what the player should press right now.
ST.ACTION_NONE, ST.ACTION_HELD, ST.ACTION_TWIST, ST.ACTION_CS = 0, 1, 2, 3
-- HOLD is not a spell. It says "the right move is to press nothing, and that is
-- deliberate" -- which is a different statement from an empty display, and the
-- difference matters most in the danger zone where the instinct is to fill.
ST.ACTION_JUDGE, ST.ACTION_FILLER, ST.ACTION_HOLD = 4, 5, 6

-- Colour wrappers, not translatable text: the spell name inside them comes from
-- the client and is already localised.
ST.ACTION_TEXT = {
    [ST.ACTION_HELD]   = "|cffb388ff%s|r",
    [ST.ACTION_TWIST]  = "|cff33ff66%s|r",
    [ST.ACTION_CS]     = "|cffffcc33%s|r",
    [ST.ACTION_JUDGE]  = "|cffff9933%s|r",
    [ST.ACTION_FILLER] = "|cff5c8aeb%s|r",
    [ST.ACTION_HOLD]   = "|cff888888%s|r",
}

-- Seconds until a spell is off cooldown, 0 when it is ready, nil when unknown.
-- A GCD-length cooldown is the global one, not the spell's own.
local function spellRemaining(name)
    if not name then return nil end
    if ST.PracticeActive() then return ST.PracticeCooldown(name) end
    local start, dur = GetSpellCooldown(name)
    if not start or not dur or dur <= 0 then return 0 end
    if dur <= ST.GCD_MAX + 0.05 then return 0 end
    local left = (start + dur) - GetTime()
    return left > 0 and left or 0
end

function ST.CSReady()
    local left = spellRemaining(ST.csName)
    return left ~= nil and left <= 0
end

local function manaPercent()
    local m = UnitPowerMax("player")
    if not m or m <= 0 then return 0 end
    return (UnitPower("player") or 0) / m * 100
end

-- Which filler to offer, or nil.
--
-- Exorcism only lands on the undead and demons, and there is no locale-proof way
-- to ask what a target IS: UnitCreatureType answers in the client's language, so
-- comparing it to an English word is how this check silently stops working on
-- eight of our nine languages.
--
-- So it asks the client whether the spell can be aimed there instead.
-- IsSpellInRange answers 1 for a unit the spell can be cast on and reached, 0
-- for one it can be cast on but not reached, and nil when it cannot be cast on
-- that unit at all. Requiring 1 covers both questions at once.
--
-- This is the best signal available rather than a certainty: if the client is
-- more permissive about target validity than assumed, the worst case is
-- Exorcism suggested where Consecration was meant -- one wasted global cooldown
-- on a filler, in the stretch of the swing that exists for spending exactly one.
function ST.PickFiller(d)
    if not (UnitExists("target") and UnitCanAttack("player", "target")) then return nil end
    local mana = manaPercent()

    if ST.exoName and mana > (d.naManaExorcism or 30) then
        local inRange = IsSpellInRange and IsSpellInRange(ST.exoName, "target")
        if inRange == 1 and (spellRemaining(ST.exoName) or 1) <= 0 then
            return ST.ACTION_FILLER, ST.exoName, ST.exoTex
        end
    end
    if ST.consName and mana > (d.naManaConsecration or 35) then
        if (spellRemaining(ST.consName) or 1) <= 0 then
            return ST.ACTION_FILLER, ST.consName, ST.consTex
        end
    end
    return nil
end

-- HOW LONG Crusader Strike has been sitting ready, which is the one number the
-- cooldown API stops telling you the moment it matters: a ready spell reports a
-- zero cooldown and nothing about when it got there. So the moment is latched
-- the first frame it comes free and cleared the first frame it is spent.
--
-- Latched from ST.Decide, which the driver already calls every frame -- an event
-- for it would have to be SPELL_UPDATE_COOLDOWN, which fires for every spell the
-- player owns and would cost far more than one comparison.
local csReadySince

local function trackCSReady(ready)
    if ready then
        if not csReadySince then csReadySince = GetTime() end
    else
        csReadySince = nil
    end
end

-- Crusader Strike has a delay budget. The strike is worth more than any single
-- twist, so once leaving it any longer would waste it, it stops being a
-- suggestion and becomes the answer.
--
-- Measured from when it BECAME ready to the earliest moment it could actually be
-- pressed -- the current global cooldown plus the player's reaction -- because
-- that whole stretch is delay the player cannot do anything about.
--
-- It still respects `room`. Forcing the strike into a stretch too short to fit
-- the seal behind it trades one wasted strike for a lost twist AND a swing with
-- no seal on it, which is not a trade the budget was ever meant to make.
local function csOverdue(d)
    if not (d.useCS and ST.csName) then return false end
    if not csReadySince then return false end
    local budget = (d.csMaxDelayMs or 1700) / 1000
    if budget <= 0 then return true end
    local soonest = ST.GCDRemaining() + (d.reaction or 0) / 1000
    return ((GetTime() - csReadySince) + soonest) >= budget
end

-- The answer, and with it the spell name and icon to draw for it. Returning all
-- three together is what keeps the bar and the guide from resolving the same
-- action to two different pictures.
function ST.Decide(d, r, gcd, dangerStart, windowStart, windowEnd)
    trackCSReady(ST.csName and ST.CSReady())
    if not r then return ST.ACTION_NONE end

    local held, twist = ST.hasHeld, ST.hasTwist
    local pending = held and not twist
    -- A twist that is already gone is not something to hold FOR. Without this
    -- the guide sits on a patient grey "wait" for a swing the bar has already
    -- painted as lost -- two halves of one display saying opposite things.
    local canHold = d.naHold and pending and not ST.TwistLost(r, windowEnd)

    if ST.GCDRemaining() > 0.05 then
        -- Locked out, but the swing still has a twist in it. Saying so is worth
        -- more than an empty box: it is the difference between "nothing to do"
        -- and "do not fill this, it is spoken for".
        if canHold and r > windowEnd then
            return ST.ACTION_HOLD, ST.twistName, ST.twistTex
        end
        return ST.ACTION_NONE
    end

    -- A head start on the prompt: the window is 0.4 s wide and a human needs
    -- part of that to see the cue and press. The zone colours stay exact -- only
    -- the prompt and the cue move.
    local lead = (d.reaction or 0) / 1000
    if r <= windowStart + lead and r > windowStart then
        if pending then return ST.ACTION_TWIST, ST.twistName, ST.twistTex end
    end

    if r <= windowStart then
        -- Inside the window: the twist only pays off if the held seal is up to
        -- be replaced, only once, and only while the cast can still get there.
        if r < windowEnd then return ST.ACTION_NONE end
        if pending then return ST.ACTION_TWIST, ST.twistName, ST.twistTex end
        return ST.ACTION_NONE
    end

    -- Danger zone: the whole point of drawing it is that nothing goes in here.
    if r <= dangerStart then
        if canHold then return ST.ACTION_HOLD, ST.twistName, ST.twistTex end
        return ST.ACTION_NONE
    end

    -- Free stretch. Room means the cast AND the seal behind it both fit before
    -- the window opens -- one global cooldown each.
    local room = (r - windowStart) >= 2 * gcd

    if room and csOverdue(d) then return ST.ACTION_CS, ST.csName, ST.csTex end

    -- Crusader Strike first when there is room for it AND the held seal behind
    -- it, and only while the seal it wants to hit with is up.
    if d.useCS and ST.csName and twist and ST.CSReady() and room then
        return ST.ACTION_CS, ST.csName, ST.csTex
    end

    -- Judgement consumes the seal, so it only goes in with room to re-seal
    -- afterwards, and only while there IS a seal to spend.
    if d.naShowJudge and ST.judgeName and room and (held or twist)
        and (spellRemaining(ST.judgeName) or 1) <= 0 then
        return ST.ACTION_JUDGE, ST.judgeName, ST.judgeTex
    end

    if not held then return ST.ACTION_HELD, ST.heldName, ST.heldTex end

    if d.naShowFiller and room then
        local a, name, tex = ST.PickFiller(d)
        if a then return a, name, tex end
    end

    if canHold then return ST.ACTION_HOLD, ST.twistName, ST.twistTex end
    return ST.ACTION_NONE
end

-- ---------------------------------------------------------------- the guide

local frame, icon, holdEdge
local lastTex
-- The last CONCRETE recommendation, and it is why the icon does not blink.
--
-- ST.Decide is a momentary answer: in most frames of a swing there is nothing to
-- press, and it says so with ACTION_NONE. Hiding on that made the guide flash for
-- a few tenths per swing and vanish for the rest. The instruction has not changed
-- in those gaps though -- it is simply not due yet -- so the last concrete one
-- stays up, drained and outlined, which is the same thing the hold state already
-- draws. Kept HERE and not in Decide: the decision stays stateless and testable,
-- the remembering is a display concern.
local stickyAction, stickyTex

-- A hold is the same picture as the thing being held for, drained and outlined.
-- Deliberately NOT a different icon: the player is waiting to press exactly this,
-- and swapping the picture for an hourglass would make them look for it again
-- when the wait ends.
local HOLD_ALPHA = 0.35

function ST.ApplyNextLayout()
    local d = ST.DB()
    if not (frame and d) then return end
    local p = d.naPos or {}
    frame:SetSize(d.naIconSize, d.naIconSize)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", p.x or 0, p.y or -280)
    frame:SetFrameStrata(d.strata or "MEDIUM")
end

function ST.NextVisible()
    local d = ST.DB()
    if not d or not d.naEnabled then return false end
    if not (ST.heldName and ST.twistName) then return false end
    -- Practice outranks the master switch and the talent gate, the same way it
    -- does for the bar: the trainer is exactly what a paladin who has neither
    -- turned on nor respecced yet came here for.
    if ST.PracticeActive() then return true end
    if not d.enabled then return false end
    if d.twoHandSpecOnly and not ST.HasTwoHandSpec() then return false end

    local mode = d.naVisibility
    if mode == "always" then return true end
    local _, _, active = ns:GetSwing("mainhand")
    local inCombat = active or UnitAffectingCombat("player")
    local sealUp   = ST.hasHeld or ST.hasTwist
    if mode == "seal" then return sealUp end
    if mode == "combatOrSeal" then return inCombat or sealUp end
    return inCombat
end

-- Driven from the bar's own update rather than owning a second one: the answer
-- it draws is computed there anyway, and two OnUpdate handlers asking the same
-- question fifty times a second is one too many.
function ST.UpdateNext(d, action, tex)
    if not frame then return end
    local placing = (d.naPos and d.naPos.unlocked) or ns:IsMoverEditMode()

    local holding
    if placing then
        -- Something to aim at while positioning the frame.
        action, tex, holding = ST.ACTION_TWIST, ST.twistTex or ST.heldTex, false
    elseif not ST.NextVisible() then
        -- Off screen for good reasons of its own -- out of combat, no seals, the
        -- talent gate. Forget the recommendation with it, or the next fight opens
        -- on a leftover from the last one.
        stickyAction, stickyTex = nil, nil
        frame:Hide()
        return
    elseif action ~= ST.ACTION_NONE and tex then
        stickyAction, stickyTex = action, tex
        holding = (action == ST.ACTION_HOLD)
    elseif d.naHold and stickyTex then
        action, tex, holding = stickyAction, stickyTex, true
    else
        -- Nothing to press and the player asked for a blank rather than a wait.
        frame:Hide()
        return
    end

    if lastTex ~= tex then
        icon:SetTexture(tex)
        lastTex = tex
    end
    icon:SetAlpha(holding and HOLD_ALPHA or 1)
    holdEdge:SetShown(holding)
    frame:Show()
end

-- No live swing means nothing to plan against, so the recommendation is dropped
-- rather than left standing. Without this the icon would keep a stale action up
-- for the whole time between fights on the "always" visibility setting.
function ST.ResetNext()
    stickyAction, stickyTex = nil, nil
    if frame then frame:Hide() end
end

function ST.SetNextUnlocked(state)
    local d = ST.DB()
    ST.Create()
    d.naPos.unlocked = state and true or false
    if d.naPos.unlocked then
        -- The driver is what draws the preview into the box, so it has to be
        -- running before there is anything to aim at.
        ST.ApplyVisibility()
        frame:Show()
        frame.mover:Show()
        ns:Print(L["Next action mover active. |cff9b6cffDrag the purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Test' again to finish."])
    else
        frame.mover:Hide()
        ST.ApplyVisibility()
        ns:Print(L["Next action mover disabled."])
    end
end

function ST.HideNext()
    stickyAction, stickyTex = nil, nil
    if not frame then return end
    frame.mover:Hide()
    frame:Hide()
end

-- Built from ST.Create for the same reason the confirmation's visuals are: this
-- file has no way of knowing when the rest of the helper came up.
function ST.CreateNextFrame()
    if frame then return end
    local d = ST.DB()

    frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    -- Trimmed, like every other icon this helper draws: the client's own border
    -- is a fat beige ring that reads as a different interface at this size.
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    holdEdge = frame:CreateTexture(nil, "BACKGROUND")
    holdEdge:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
    holdEdge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
    holdEdge:SetTexture(ST.BAR_TEX)
    holdEdge:SetVertexColor(0.61, 0.42, 1.00, 0.9)
    holdEdge:Hide()

    frame.mover = ns:CreateMover(frame, {
        key    = "sealtwistnext",
        label  = L["|cffffffffNEXT ACTION|r"],
        db     = d.naPos,
        fill   = true,
        applyPos = function() ST.ApplyNextLayout() end,
        editPreview = function(edit)
            if edit then
                ST.ApplyNextLayout()
                icon:SetTexture(ST.twistTex or ST.heldTex)
                lastTex = nil
                icon:SetAlpha(1)
                frame:Show()
            elseif not ST.NextVisible() then
                frame:Hide()
            end
        end,
    })
    ST.ApplyNextLayout()
end
