-- Paladin seal twist: practice mode.
--
-- The place the target dummy goes when there is no target dummy: a self-driven
-- swing clock, keys that stand in for the seals, and a verdict per swing -- so
-- the timing can be drilled without a fight, without a mob and without spending
-- anything.
--
-- Deliberately its own file rather than a corner of the bar. Practice runs the
-- whole display off a SIMULATED swing instead of the tracker, and mixing that
-- switch into the live path is how a helper ends up showing a fake swing in a
-- real fight. The seam is here, and the live code asks one question --
-- ST.PracticeActive -- in the five places where the answer differs.
--
-- WHAT IS SIMULATED, AND WHY IT IS HONEST.
--
-- The seal model is the real one. Casting a seal makes it active and leaves the
-- PREVIOUS seal lingering for FADE_WINDOW; a swing that lands while both are up
-- carried both, and that is a twist. Nothing here grades against a prediction of
-- where the window was -- the simulation knows exactly what it did, which is the
-- one place in this addon where certainty is available and it would be silly not
-- to use it.
--
-- The haste model is the client's: rating is additive and converts at
-- RATING_PER_PERCENT, Bloodlust is a separate multiplicative category, and the
-- global cooldown floors at one second.
--
-- WHAT IS NOT SIMULATED: damage, threat, mana and the target. This is a metronome
-- with a scoreboard, not a rotation simulator, and pretending otherwise would
-- invite people to tune numbers against it.
--
-- See the header of Paladin.lua for why the helper is split at all.
local _, ns = ...
local L = ns.L

local ST = ns.SealTwist
if not ST then return end

local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil

-- How long a replaced seal keeps resolving on the next swing. This is the twist
-- window itself, and it is a server constant rather than a setting: the whole
-- point of practising against it is that it does not move.
local FADE_WINDOW = 0.4

-- Haste. Rating is additive across sources and converts at this many points per
-- one percent; Bloodlust multiplies on top of the result.
local RATING_PER_PERCENT = 15.77
local BUFFS = {
    { key = "bloodlust", label = "Bloodlust",   duration = 40, factor = 1.30 },
    { key = "pot",       label = "Haste potion", duration = 15, rating = 400 },
    { key = "abacus",    label = "Abacus",       duration = 10, rating = 260 },
    { key = "warp",      label = "Time warp",    duration = 10, rating = 325 },
}

-- Simulated cooldowns, in seconds.
local CD = { cs = 6, judge = 10, filler = 8 }

-- The six things a key can be bound to. Order is the order they are offered in.
local ABILITIES = {
    { key = "held",   label = "Cast the held seal" },
    { key = "twist",  label = "Cast the twist seal" },
    { key = "cs",     label = "Crusader Strike" },
    { key = "judge",  label = "Judgement" },
    { key = "filler", label = "Filler" },
    { key = "attack", label = "Start / stop attack" },
}

-- Read by the options tree, which builds one key row per ability.
ST.PRACTICE_ABILITIES = ABILITIES

-- ---------------------------------------------------------------- state

local p = {
    active = false,
    speed  = 3.5,
    gcd    = 1.5,
    swingStart = 0,
    gcdEnd  = 0,
    attacking = false,
    -- name -> the moment it stops resolving on a swing. A permanent seal uses
    -- math.huge; the lingering one carries a real timestamp.
    sealHeld  = 0,   -- 0 = not up
    sealTwist = 0,
    fadingUntil = 0,
    fading = nil,    -- "held" | "twist"
    twistTried = false,
    cd = { cs = 0, judge = 0, filler = 0 },
    buff = { bloodlust = 0, pot = 0, abacus = 0, warp = 0 },
    queued = nil,
    queuedAt = 0,
    fightStart = 0,
    hits = 0,
    swings = 0,
    events = {},     -- { t, tex, result }
}
ST.practice = p

local panel, resultFS, resultLeft, keyCatcher
local infoAcc, drawAcc = 0, 0
local timeline, tlIcons, tlTicks = nil, {}, {}
local buffButtons = {}

function ST.PracticeSwing()
    if not p.attacking then return p.speed, nil end
    local left = (p.swingStart + p.speed) - GetTime()
    if left < 0 then left = 0 end
    return p.speed, left
end

-- Seconds until a simulated spell is ready, by the client-facing spell NAME --
-- which is what ST.Decide asks with, so the guide and the bar work unchanged.
function ST.PracticeCooldown(name)
    -- A spell the paladin has not learned resolves to a nil name, and nil would
    -- MATCH the first other unlearned spell in the chain below -- which
    -- cross-wires two keys onto one simulated cooldown.
    if not name then return 0 end
    local slot
    if name == ST.csName then slot = "cs"
    elseif name == ST.judgeName then slot = "judge"
    elseif name == ST.consName or name == ST.exoName then slot = "filler"
    else return 0 end
    local left = p.cd[slot] - GetTime()
    return left > 0 and left or 0
end

-- ---------------------------------------------------------------- haste

local function recalcSpeed()
    local d = ST.DB()
    local base = (d.practiceSpeed or 0)
    if base <= 0 then base = UnitAttackSpeed("player") or 3.5 end

    local now = GetTime()
    local rating = 0
    for _, b in ipairs(BUFFS) do
        if b.rating and p.buff[b.key] > now then rating = rating + b.rating end
    end
    local mult = 1 + (rating / RATING_PER_PERCENT / 100)

    local speed, gcd = base / mult, 1.5 / mult
    for _, b in ipairs(BUFFS) do
        if b.factor and p.buff[b.key] > now then
            speed, gcd = speed / b.factor, gcd / b.factor
        end
    end
    -- The client floors the spell cooldown at a second however much haste is
    -- stacked; a simulation that does not is a simulation you can beat.
    p.gcd = max(1.0, floor(gcd * 1000 + 0.5) / 1000)
    local newSpeed = max(0.1, floor(speed * 1000 + 0.5) / 1000)

    -- Haste arriving mid-swing keeps the elapsed FRACTION, exactly as the real
    -- swing tracker rescales it. Leaving swingStart alone instead would fire the
    -- swing instantly the moment Bloodlust goes up -- and push it most of a
    -- second late when it drops.
    if p.active and p.speed > 0 then
        local frac = (GetTime() - p.swingStart) / p.speed
        if frac < 1 then p.swingStart = GetTime() - frac * newSpeed end
    end
    p.speed = newSpeed
end

-- ---------------------------------------------------------------- verdict

local function showResult(text, r, g, b)
    local d = ST.DB()
    if not resultFS then return end
    resultFS:SetText(text)
    resultFS:SetTextColor(r, g, b)
    resultLeft = d.practiceResultDuration or 0.8
    resultFS:SetAlpha(1)
end

local function logEvent(tex, result)
    if not p.fightStart or p.fightStart == 0 then return end
    local e = p.events
    e[#e + 1] = { t = GetTime() - p.fightStart, tex = tex, result = result }
    -- Bounded: an hour on a dummy is thousands of icons, and a timeline nobody
    -- scrolls back through does not need to remember all of them.
    if #e > 400 then table.remove(e, 1) end
end

-- Mirrors the pair the rest of the addon reads. The simulation is the source of
-- truth while it runs, so it writes the same two fields the aura sweep would.
local function syncSeals()
    local now = GetTime()
    ST.hasHeld  = p.sealHeld  > now
    ST.hasTwist = p.sealTwist > now
    ST.heldIcon,  ST.heldExpires  = ST.heldTex,  nil
    ST.twistIcon, ST.twistExpires = ST.twistTex, nil
    ST.heldDuration, ST.twistDuration = nil, nil
end

local ATTACK_TEX = "Interface\\ICONS\\INV_Sword_04"

local function onSwing()
    p.swings = p.swings + 1
    local twisted = (ST.hasHeld and ST.hasTwist)

    -- A swing is only graded when a twist was ATTEMPTED on it. Half the steps of
    -- a fast sequence are deliberately plain autos, and painting those red would
    -- make the strip read as a run of failures the player did not commit.
    local result = "plain"
    if p.twistTried then result = twisted and "hit" or "miss" end
    logEvent(ATTACK_TEX, result)

    if p.twistTried then
        local d = ST.DB()
        if twisted then
            p.hits = p.hits + 1
            local c = d.practiceColorHit or {}
            showResult(L["TWIST"], c.r or 0.2, c.g or 1, c.b or 0.35)
            -- The same feedback the live confirmation fires. Here it is not a
            -- guess at all -- the simulation knows both seals were up.
            ST.OnTwistLanded()
        else
            local c = d.practiceColorMiss or {}
            showResult(L["MISS"], c.r or 1, c.g or 0.25, c.b or 0.25)
        end
        p.twistTried = false
    end

    -- The swing consumed the lingering seal, whichever it was.
    if p.fading then
        if p.fading == "held" then p.sealHeld = 0 else p.sealTwist = 0 end
        p.fading, p.fadingUntil = nil, 0
    end

    -- ADVANCED, not reset. Resetting to now throws away the overshoot of the
    -- frame that noticed, and at fifty ticks a second that is a few milliseconds
    -- of drift per swing -- which is a tenth of the twist window inside a
    -- minute. The catch-up clamp is for the other case: a freeze long enough to
    -- owe several swings should cost one, not replay them all.
    local now = GetTime()
    p.swingStart = p.swingStart + p.speed
    if now - p.swingStart > p.speed then p.swingStart = now end
    syncSeals()
end

-- ---------------------------------------------------------------- casting

local function startGCD()
    p.gcdEnd = GetTime() + p.gcd
end

local function castSeal(which)
    local now = GetTime()
    -- The seal being replaced keeps resolving for the window. That linger IS the
    -- twist, and whether it pays off is decided by the swing, not here.
    local other = (which == "held") and "twist" or "held"
    local otherUp = (other == "held") and p.sealHeld or p.sealTwist
    if otherUp > now then
        p.fading = other
        p.fadingUntil = now + FADE_WINDOW
        if other == "held" then p.sealHeld = p.fadingUntil else p.sealTwist = p.fadingUntil end
        p.twistTried = true
    end
    if which == "held" then p.sealHeld = math.huge else p.sealTwist = math.huge end
    startGCD()
    syncSeals()
    logEvent(which == "held" and ST.heldTex or ST.twistTex, "cast")
    if ST.DB().showRotation then
        ST.RotOnCast(which == "held" and ST.heldName or ST.twistName)
    end
end

local function castAbility(slot, name, tex, cd)
    p.cd[slot] = GetTime() + cd
    startGCD()
    logEvent(tex, "cast")
    if slot == "judge" then
        -- Judging consumes the seal, exactly as it does in a fight -- and that
        -- is the whole reason the guide is careful about suggesting it.
        p.sealHeld, p.sealTwist = 0, 0
        p.fading, p.fadingUntil = nil, 0
        syncSeals()
    end
    if slot == "cs" and ST.DB().showRotation then ST.RotOnCast(ST.csName) end
end

-- Returns true when the press was consumed. A press that lands on a running
-- global cooldown is not thrown away: the client holds one for the last
-- SPELL_QUEUE_WINDOW of it, and practising without that is practising a rhythm
-- the game does not ask for.
local function tryCast(key, queued)
    local now = GetTime()
    local d = ST.DB()

    if key == "attack" then
        p.attacking = not p.attacking
        if p.attacking then p.swingStart = now end
        return true
    end

    local left = p.gcdEnd - now
    if left > 0 then
        if queued then return false end
        local window = (d.practiceQueueMs or 400) / 1000
        if left <= window then p.queued, p.queuedAt = key, now end
        return false
    end

    if key == "held"  then castSeal("held");  return true end
    if key == "twist" then castSeal("twist"); return true end

    -- Everything below is a real spell, and a key bound to one the paladin has
    -- not learned does nothing at all: a simulation that lets you press
    -- Crusader Strike at level 20 is teaching a rotation that does not exist.
    local name, tex, cd
    if key == "cs" then name, tex, cd = ST.csName, ST.csTex, CD.cs
    elseif key == "judge" then name, tex, cd = ST.judgeName, ST.judgeTex, CD.judge
    elseif key == "filler" then name, tex, cd = ST.consName, ST.consTex, CD.filler
    else return false end
    if not name then return false end
    if ST.PracticeCooldown(name) > 0 then return false end
    castAbility(key, name, tex, cd)
    return true
end

-- ---------------------------------------------------------------- the tick

local function tick(_, elapsed)
    if not p.active then return end
    -- A real pull ends the session. Two reasons, and either alone is enough: the
    -- keyboard hook this mode installs uses a call the client restricts while
    -- locked down, and a simulated swing bar during an actual fight is the exact
    -- confusion the whole file is arranged to prevent.
    if InCombatLockdown() then ST.StopPractice(); return end
    local now = GetTime()
    local d = ST.DB()

    if resultLeft and resultLeft > 0 then
        resultLeft = resultLeft - elapsed
        local total = d.practiceResultDuration or 0.8
        if resultLeft <= 0 then
            resultFS:SetText("")
        else
            resultFS:SetAlpha(min(1, (resultLeft / total) * 3))
        end
    end

    -- ORDER MATTERS between these two, and it is not fixed.
    --
    -- A swing that was due before the linger ran out carried the twist; one due
    -- after it did not. Both can come up in the same frame at fifty ticks a
    -- second, and handling the fade first unconditionally would grade a landed
    -- twist as too early whenever the two fell in the same 20 ms. So whichever
    -- was due FIRST is settled first.
    local swingDue = p.attacking and (p.swingStart + p.speed) or nil
    local fadeDue  = p.fading and p.fadingUntil or nil

    if swingDue and swingDue <= now and (not fadeDue or swingDue <= fadeDue) then
        onSwing()
        swingDue, fadeDue = nil, (p.fading and p.fadingUntil or nil)
    end

    -- The lingering seal expiring without a swing: the twist was simply too
    -- early, and that is a miss the moment the window closes rather than at the
    -- next swing -- saying so late would teach the wrong correction.
    if fadeDue and now >= fadeDue then
        if p.fading == "held" then p.sealHeld = 0 else p.sealTwist = 0 end
        p.fading, p.fadingUntil = nil, 0
        if p.twistTried then
            p.twistTried = false
            local c = d.practiceColorMiss or {}
            showResult(L["TOO EARLY"], c.r or 1, c.g or 0.25, c.b or 0.25)
            logEvent(ST.twistTex, "miss")
        end
        syncSeals()
    end

    if swingDue and swingDue <= now then onSwing() end

    local hasteChanged = false
    for _, b in ipairs(BUFFS) do
        if p.buff[b.key] > 0 and now >= p.buff[b.key] then
            p.buff[b.key] = 0
            hasteChanged = true
        end
    end
    if hasteChanged then recalcSpeed() end

    if p.queued then
        -- The hold expires with the window it was granted for, so a key pressed
        -- and forgotten cannot fire half a swing later.
        if p.gcdEnd - now <= 0 then
            local k = p.queued
            p.queued = nil
            tryCast(k, true)
        elseif now - p.queuedAt > (d.practiceQueueMs or 400) / 1000 then
            p.queued = nil
        end
    end

    -- The swing clock is the only thing on this tick that wants every frame.
    -- The strip scrolls a couple of pixels in 20 ms and the countdowns change
    -- once a second, so both are stepped down rather than paid for fifty times.
    drawAcc = drawAcc + elapsed
    if drawAcc >= 0.02 then
        drawAcc = 0
        if timeline and timeline:IsShown() then ST.RenderTimeline() end
    end

    infoAcc = infoAcc + elapsed
    if infoAcc >= 0.2 then
        infoAcc = 0
        ST.UpdateBuffButtons()
        if panel then
            panel.info:SetText(format(L["speed %.2fs  -  GCD %.2fs  -  %d of %d"],
                p.speed, p.gcd, p.hits, p.swings))
        end
    end
end

-- ---------------------------------------------------------------- keys

local function keyFor(bind)
    local d = ST.DB()
    for _, a in ipairs(ABILITIES) do
        if (d.practiceKeys and d.practiceKeys[a.key] or ""):upper() == bind then
            return a.key
        end
    end
    return nil
end

local function onKeyDown(self, key)
    if not p.active then return end
    local bind = key
    if IsShiftKeyDown() then bind = "SHIFT-" .. bind end
    if IsControlKeyDown() then bind = "CTRL-" .. bind end
    if IsAltKeyDown() then bind = "ALT-" .. bind end

    local slot = keyFor(bind:upper())
    -- SetPropagateKeyboardInput is one of the calls the client refuses while
    -- locked down. The tick stops the session the moment combat starts, but a
    -- keypress can still land in the same frame as the pull -- so the guard is
    -- here as well as there, and the key simply passes through.
    if InCombatLockdown() then return end
    if not slot then
        -- Not ours: let the key through, or practice mode swallows the whole
        -- keyboard including the one that opens the menu to switch it off.
        self:SetPropagateKeyboardInput(true)
        return
    end
    self:SetPropagateKeyboardInput(false)
    tryCast(slot)
end

-- ---------------------------------------------------------------- timeline

local TL_LANE = 18

local function tlIcon(i)
    if tlIcons[i] then return tlIcons[i] end
    local t = timeline.scroll:CreateTexture(nil, "ARTWORK")
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tlIcons[i] = t
    return t
end

local function tlTick(i)
    if tlTicks[i] then return tlTicks[i] end
    local f = {}
    f.line = timeline.scroll:CreateTexture(nil, "BACKGROUND")
    f.line:SetColorTexture(0.35, 0.35, 0.42, 0.8)
    f.text = timeline.scroll:CreateFontString(nil, "OVERLAY")
    f.text:SetTextColor(0.6, 0.6, 0.68)
    tlTicks[i] = f
    return f
end

-- The ruler is what turns a row of icons into a reading: without it the eye can
-- see THAT two swings were close together but not how close, which is the only
-- number practice is about.
function ST.RenderTimeline()
    local d = ST.DB()
    if not timeline then return end
    local pps = d.practiceTimelinePPS or 80
    local w = d.practiceTimelineWidth or 600
    local span = w / pps
    local nowT = (p.fightStart > 0) and (GetTime() - p.fightStart) or 0
    local from = max(0, nowT - span)

    local fontPath, outline = ST.FontFace(d)

    local n = 0
    for i = 1, #p.events do
        local e = p.events[i]
        if e.t >= from then
            n = n + 1
            local t = tlIcon(n)
            local x = (e.t - from) * pps
            t:SetSize(TL_LANE, TL_LANE)
            t:ClearAllPoints()
            t:SetPoint("LEFT", timeline.scroll, "LEFT", x, e.result == "cast" and TL_LANE / 2 or -TL_LANE / 2)
            t:SetTexture(e.tex)
            if e.result == "hit" then t:SetVertexColor(0.3, 1, 0.45)
            elseif e.result == "miss" then t:SetVertexColor(1, 0.35, 0.35)
            elseif e.result == "plain" then t:SetVertexColor(0.6, 0.6, 0.68)
            else t:SetVertexColor(1, 1, 1) end
            t:Show()
        end
    end
    for i = n + 1, #tlIcons do tlIcons[i]:Hide() end

    local m = 0
    local first = ceil(from)
    for s = first, floor(from + span) do
        m = m + 1
        local tk = tlTick(m)
        local x = (s - from) * pps
        tk.line:ClearAllPoints()
        tk.line:SetPoint("TOP", timeline.scroll, "TOPLEFT", x, 0)
        tk.line:SetSize(1, (s % 5 == 0) and 14 or 7)
        tk.line:Show()
        if s % 5 == 0 then
            tk.text:SetFont(fontPath, 10, outline)
            tk.text:ClearAllPoints()
            tk.text:SetPoint("TOP", tk.line, "BOTTOM", 0, -1)
            tk.text:SetText(format("%d", s))
            tk.text:Show()
        else
            tk.text:Hide()
        end
    end
    for i = m + 1, #tlTicks do tlTicks[i].line:Hide(); tlTicks[i].text:Hide() end
end

-- ---------------------------------------------------------------- frames

function ST.UpdateBuffButtons()
    local now = GetTime()
    for _, b in ipairs(buffButtons) do
        local left = p.buff[b.key] - now
        if left > 0 then
            b.text:SetText(format("%s %d", L[b.label], ceil(left)))
            b.bg:SetColorTexture(0.18, 0.42, 0.22, 0.95)
        else
            b.text:SetText(L[b.label])
            b.bg:SetColorTexture(0.14, 0.14, 0.18, 0.95)
        end
    end
end

local function toggleBuff(key)
    local now = GetTime()
    if p.buff[key] > now then
        p.buff[key] = 0
    else
        for _, b in ipairs(BUFFS) do
            if b.key == key then p.buff[key] = now + b.duration end
        end
    end
    recalcSpeed()
    ST.UpdateBuffButtons()
end

local function makeButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(96, 20)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetColorTexture(0.14, 0.14, 0.18, 0.95)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function buildPanel()
    if panel then return end
    local d = ST.DB()

    panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(220, 150)
    panel:SetFrameStrata("HIGH")
    panel:Hide()
    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints(panel)
    panel.bg:SetColorTexture(0.06, 0.06, 0.08, 0.92)

    panel.title = panel:CreateFontString(nil, "OVERLAY")
    panel.title:SetPoint("TOP", panel, "TOP", 0, -8)

    panel.info = panel:CreateFontString(nil, "OVERLAY")
    panel.info:SetPoint("TOP", panel.title, "BOTTOM", 0, -6)
    panel.info:SetTextColor(0.75, 0.75, 0.82)

    for i, b in ipairs(BUFFS) do
        local key = b.key
        local btn = makeButton(panel, L[b.label], function() toggleBuff(key) end)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT",
            10 + ((i - 1) % 2) * 102, -52 - floor((i - 1) / 2) * 24)
        btn.key = key
        buffButtons[#buffButtons + 1] = btn
    end

    panel.stop = makeButton(panel, L["Stop practice"], function() ST.StopPractice() end)
    panel.stop:SetSize(198, 22)
    panel.stop:SetPoint("BOTTOM", panel, "BOTTOM", 0, 8)

    panel.mover = ns:CreateMover(panel, {
        key    = "sealtwistpractice",
        label  = L["|cffffffffPRACTICE|r"],
        db     = d.practicePanelPos,
        fill   = true,
        applyPos = function() ST.ApplyPracticeLook() end,
    })
end

local function buildResult()
    if resultFS then return end
    local d = ST.DB()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(300, 60)
    f:SetFrameStrata("HIGH")
    resultFS = f:CreateFontString(nil, "OVERLAY")
    resultFS:SetPoint("CENTER")
    f.mover = ns:CreateMover(f, {
        key    = "sealtwistresult",
        label  = L["|cffffffffRESULT|r"],
        db     = d.practiceResultPos,
        fill   = true,
        applyPos = function() ST.ApplyPracticeLook() end,
    })
    resultFS._host = f
end

local function buildTimeline()
    if timeline then return end
    local d = ST.DB()
    timeline = CreateFrame("Frame", nil, UIParent)
    timeline:SetFrameStrata("MEDIUM")
    timeline:Hide()
    timeline.bg = timeline:CreateTexture(nil, "BACKGROUND")
    timeline.bg:SetAllPoints(timeline)
    timeline.bg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
    -- A plain child rather than a ScrollFrame: nothing here is dragged, the
    -- window simply follows the fight clock, and a scroll frame would add a
    -- clipping rectangle to keep in step with the width setting for no gain.
    timeline.scroll = CreateFrame("Frame", nil, timeline)
    timeline.scroll:SetPoint("TOPLEFT", timeline, "TOPLEFT", 0, -20)
    timeline.scroll:SetPoint("BOTTOMRIGHT", timeline, "BOTTOMRIGHT", 0, 0)

    timeline.mover = ns:CreateMover(timeline, {
        key    = "sealtwisttimeline",
        label  = L["|cffffffffTIMELINE|r"],
        db     = d.practiceTimelinePos,
        fill   = true,
        applyPos = function() ST.ApplyPracticeLook() end,
    })
end

function ST.ApplyPracticeLook()
    local d = ST.DB()
    if not panel then return end
    local fontPath, outline = ST.FontFace(d)

    local pp = d.practicePanelPos or {}
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", pp.x or -320, pp.y or 0)
    panel.title:SetFont(fontPath, 14, outline)
    panel.title:SetText(L["|cffffcc33Twist practice|r"])
    panel.info:SetFont(fontPath, 11, outline)
    for _, b in ipairs(buffButtons) do b.text:SetFont(fontPath, 11, outline) end
    panel.stop.text:SetFont(fontPath, 12, outline)

    local rp = d.practiceResultPos or {}
    resultFS._host:ClearAllPoints()
    resultFS._host:SetPoint("CENTER", UIParent, "CENTER", rp.x or 0, rp.y or 120)
    resultFS:SetFont(fontPath, d.practiceResultSize or 28, outline)

    local tp = d.practiceTimelinePos or {}
    timeline:ClearAllPoints()
    timeline:SetPoint("CENTER", UIParent, "CENTER", tp.x or 0, tp.y or -300)
    timeline:SetSize(d.practiceTimelineWidth or 600, TL_LANE * 2 + 26)
end

-- ---------------------------------------------------------------- lifecycle

function ST.StartPractice()
    local d = ST.DB()
    if not d or p.active then return end
    if not (ST.heldName and ST.twistName) then
        ns:Print(L["Practice needs two seals: pick them under Seals first."])
        return
    end
    -- The key catcher and the propagation switch it uses are both restricted
    -- while the client is locked down, and a trainer that starts mid-pull is not
    -- a trainer anyway.
    if InCombatLockdown() then
        ns:Print(L["Not possible in combat."])
        return
    end

    ST.Create()
    buildPanel(); buildResult(); buildTimeline()
    ST.ApplyPracticeLook()

    for k in pairs(p.cd) do p.cd[k] = 0 end
    for k in pairs(p.buff) do p.buff[k] = 0 end
    wipe(p.events)
    p.sealHeld, p.sealTwist = 0, 0
    p.fading, p.fadingUntil, p.twistTried = nil, 0, false
    p.queued, p.gcdEnd = nil, 0
    p.hits, p.swings = 0, 0
    p.attacking = true
    p.fightStart = GetTime()
    p.swingStart = p.fightStart
    p.active = true

    recalcSpeed()
    syncSeals()

    if not keyCatcher then
        keyCatcher = CreateFrame("Frame", nil, UIParent)
        keyCatcher:SetScript("OnKeyDown", onKeyDown)
    end
    keyCatcher:EnableKeyboard(true)
    keyCatcher:SetPropagateKeyboardInput(true)

    panel:Show()
    if d.practiceTimeline then timeline:Show() end
    panel:SetScript("OnUpdate", tick)

    ST.ApplyVisibility()
    ns:Print(L["Practice mode on. Press your bound keys; the swing runs on its own."])
end

function ST.StopPractice()
    if not p.active then return end
    p.active = false
    p.attacking = false
    if keyCatcher then
        keyCatcher:EnableKeyboard(false)
        if not InCombatLockdown() then keyCatcher:SetPropagateKeyboardInput(true) end
    end
    if panel then panel:SetScript("OnUpdate", nil); panel:Hide(); panel.mover:Hide() end
    if timeline then timeline:Hide(); timeline.mover:Hide() end
    if resultFS then resultFS:SetText(""); resultFS._host.mover:Hide() end

    -- Hand the seal pair back to the real world before anything reads it again.
    ST.RefreshSeals()
    ST.ApplyVisibility()
    ns:Print(format(L["Practice mode off. %d of %d swings carried the twist."], p.hits, p.swings))
end

function ST.TogglePractice()
    if p.active then ST.StopPractice() else ST.StartPractice() end
end

-- The timeline switch has to reach a session that is already running: every
-- other toggle on the page applies immediately, and one that waits for the next
-- start reads as a switch that does nothing.
function ST.ApplyTimelineShown()
    if not (timeline and p.active) then return end
    if ST.DB().practiceTimeline then timeline:Show() else timeline:Hide() end
end

