-- Paladin seal twisting helper (class tool).
--
-- Twisting means holding a seal and casting a second one so it lands in the
-- last fraction of a second before the auto-attack: that swing then carries
-- both. The whole trick is timing against the swing clock, so this reads
-- Core/SwingTracker rather than keeping a second one.
--
-- Two facts decide what this may suggest, and both cost a version to learn:
--
--   * Only Seal of Command and Seal of Righteousness can be twisted OUT of --
--     they are the two whose effect still resolves on a swing after the aura
--     was replaced. Everything else is a twist TARGET. Blood and the Martyr
--     are the strongest targets but arrive at 64, so a levelling paladin
--     twists Command into Righteousness. Requiring Blood/Martyr is what kept
--     the whole helper hidden below that level.
--   * The window is server-side. The cast has to REACH the server inside it,
--     so the prompt has to run ahead of the swing by the window plus roughly
--     one trip of the player's latency, and it stops being worth pressing once
--     less than that trip is left.
--
-- THE BAR IS FOUR ZONES, not one countdown. Read as "seconds left before the
-- swing", from the far end towards it:
--
--   filler   a global-cooldown spell still finishes AND leaves the cooldown
--            free before the window opens. The only stretch where casting
--            something else is free.
--   danger   casting anything here means the global cooldown is still running
--            when the window opens, and the twist is gone. This zone is the
--            single most useful thing on the bar, and it is the reason the
--            boundary moves with spell haste instead of sitting at 1.5.
--   twist    cast the second seal.
--   late     the tail of the twist window, wide enough for a judgement in
--            front of the twist -- the double-judge line. Marked separately
--            because it is a deliberate play, not a mistake.
--
-- What it deliberately does NOT do: prompt Judgement. Judging consumes the
-- seal, so a mistimed prompt costs more than no prompt -- that call stays with
-- the player.
local _, ns = ...
local L = ns.L

local csMod = ns.modules and ns.modules.vtmanadisplay
if not csMod or not csMod.RegisterClassTool then return end

local GetTime, GetSpellInfo, GetSpellCooldown = GetTime, GetSpellInfo, GetSpellCooldown
local UnitAttackSpeed, UnitBuff = UnitAttackSpeed, UnitBuff
local GetNetStats, UnitAffectingCombat = GetNetStats, UnitAffectingCombat
local min, max, floor = math.min, math.max, math.floor

local DEFAULTS = {
    -- Off until asked for. Twisting is a Retribution habit, not something every
    -- paladin does, and a bar that appears in the middle of the screen on its
    -- own the first time you enter combat is not a welcome surprise. Off also
    -- means the swing tracker is never held, so nobody pays for a feature they
    -- did not ask for.
    enabled     = false,
    window      = 0.40,   -- seconds before the swing that the twist lands in
    lateWindow  = 0.20,   -- tail of that window: still room for a judgement
    latency     = true,   -- shift the window ahead by the measured lag
    reaction    = 100,    -- ms of head start on the prompt, for the human
    heldSeal    = "",     -- resolved on first run
    twistSeal   = "",
    showBar     = true,
    showZones   = true,
    showTicks   = true,
    showSpeed   = true,   -- attack speed, red under the twisting cap
    showSeals   = true,   -- which seals are on you, and for how long
    showRotation = true,  -- the sequence row above the bar
    rotation    = "auto", -- or one of ROT_ORDER, chosen by hand
    rotIconSize = 24,
    showAction  = true,
    -- Off: the zone colours and the marks are what you read mid-swing, and the
    -- numbers are a diagnostic line. Whoever wants to check the latency the bar
    -- is working with switches it on and leaves it on.
    showNumbers = false,
    showOOC     = false,  -- keep the bar up between fights
    useCS       = true,
    sound       = false,  -- cue when the window opens
    soundLate   = false,  -- cue when the late window opens
    soundHit    = false,  -- cue when the twist actually landed
    hitSound    = "sniper",
    barWidth    = 240,
    barHeight   = 22,
    iconSize    = 26,
    fontSize    = 18,
    actionFontSize = 0,   -- 0 = follow fontSize;  see actionSize()
    warnFontSize   = 0,   -- 0 = follow actionFontSize; see warnSize()
    speedFontSize  = 0,   -- 0 = fontSize - 4;     see speedSize()
    sealTimerFontSize = 0,-- 0 = scales with the icon; see sealTimerSize()
    x           = 0,
    y           = -180,
    unlocked    = false,
}

-- Seals we can name from an ID. The spellbook sweep below picks up anything
-- else the character knows (Season of Discovery runes, later ranks), so a seal
-- missing from this list is found anyway as long as ONE of these resolves.
local SEAL_IDS = {
    20375,   -- Seal of Command
    31892,   -- Seal of Blood        (Horde, 64)
    348700,  -- Seal of the Martyr   (Alliance, 64)
    31801,   -- Seal of Vengeance    (Alliance, 64)
    20154,   -- Seal of Righteousness
    21082,   -- Seal of the Crusader
    20164,   -- Seal of Justice
    20165,   -- Seal of Light
    20166,   -- Seal of Wisdom
}
-- Preference order for the two roles, by base ID.
--
-- HELD is short on purpose: only these two survive being replaced a moment
-- before the swing, so a seal outside this list cannot be the one you hold, no
-- matter how much damage it does.
--
-- TWIST is every seal, best first. Blood and the Martyr are the pay-off at 64;
-- below that Righteousness is the target, which is the twist paladins have run
-- since vanilla. Whatever is picked, it must not be the held seal --
-- pickDefaults skips it rather than trusting the order.
local HELD_PREF  = { 20375, 20154 }
local TWIST_PREF = { 31892, 348700, 31801, 20154, 21082, 20164, 20165, 20166 }

local CRUSADER_STRIKE = 35395
-- Flash of Light rank 1 is a plain 1.5 s cast, so its CURRENT cast time is the
-- current spell GCD: the same haste scales both, and it needs no cooldown to be
-- running to be readable.
local GCD_REFERENCE = 19750
local GCD_MIN, GCD_MAX = 1.0, 1.5

local BAR_TEX  = "Interface\\Buttons\\WHITE8X8"
local FONT     = "Fonts\\FRIZQT__.TTF"
local WINDOW_SOUND = 567458

-- Cues for the hit confirmation. Only sounds this addon already plays
-- elsewhere are listed as built-ins -- an unverified file id fails SILENTLY,
-- which is the worst possible outcome for a setting whose entire job is to make
-- a noise. Anything sharper than these comes from shared media: other addons
-- register their sound packs there, and picking one of those is how you get a
-- crack rather than a chime without this addon shipping audio of its own.
local HIT_SOUNDS = {
    { key = "sniper", label = "Sniper",       media = "Sniper" },
    { key = "rifle",  label = "Rifle",        media = "Rifle"  },
    { key = "chime",  label = "Chime",        file  = WINDOW_SOUND },
    { key = "alarm",  label = "Raid warning", kit   = "RAID_WARNING", fallback = 8959 },
    { key = "ready",  label = "Ready check",  kit   = "READY_CHECK",  fallback = 8960 },
    { key = "menu",   label = "Click",        kit   = "IG_MAINMENU_OPEN" },
}
local LSM_PREFIX = "lsm:"

local function playHitSound(choice)
    if not choice or choice == "" then return end
    local name = choice:match("^" .. LSM_PREFIX .. "(.+)$")
    if name then
        local LSM = ns.LSM
        local hash = LSM and LSM:HashTable("sound")
        local path = hash and hash[name]
        if path and path ~= "" then pcall(PlaySoundFile, path, "Master") end
        return
    end
    for _, s in ipairs(HIT_SOUNDS) do
        if s.key == choice then
            if s.media then
                -- Straight to the file, not through shared media: a global
                -- sound override in another addon would otherwise be able to
                -- swap the cue underneath us.
                local path = ns.MediaSound and ns.MediaSound(s.media)
                if path then pcall(PlaySoundFile, path, "Master") end
            elseif s.file then
                pcall(PlaySoundFile, s.file, "Master")
            else
                local id = (SOUNDKIT and SOUNDKIT[s.kit]) or s.fallback
                if id then pcall(PlaySound, id, "Master") end
            end
            return
        end
    end
end

-- Zones, in the order the swing runs through them.
local Z_FILLER, Z_DANGER, Z_TWIST, Z_LATE, Z_MISS, Z_READY = 1, 2, 3, 4, 5, 6

-- The fill takes the colour of the zone the swing is in, so the bar is readable
-- out of the corner of the eye without reading the marks at all.
local ZONE_COLOR = {
    [Z_FILLER] = { 0.22, 0.52, 0.92 },   -- free to cast something else
    [Z_DANGER] = { 0.85, 0.20, 0.20 },   -- casting now costs the twist
    [Z_TWIST]  = { 0.20, 0.85, 0.35 },   -- cast the second seal
    [Z_LATE]   = { 0.10, 0.62, 0.28 },   -- still in, judgement fits in front
    [Z_MISS]   = { 0.45, 0.16, 0.16 },   -- too late to reach the server
    [Z_READY]  = { 0.25, 0.90, 0.45 },   -- swing due: auto-attack is off
}
local COL_IDLE = { 0.35, 0.35, 0.42 }
local COL_DONE = { 0.14, 0.45, 0.22 }   -- twist already in, swing carries both

local frame, bar, barBG
local zoneFiller, zoneDanger, zoneTwist
local tickDanger, tickTwist, tickLate
local speedFS, actionFS, infoFS, rotLabel
local sealSlots = {}
local rotIcons  = {}

local sealNames        = {}     -- ordered list of seal names this character knows
local heldName, twistName, csName
local armedAt   -- last moment a twist was possible; see refreshSeals
local heldTex, twistTex, csTex
local hasHeld, hasTwist = false, false
local heldIcon, twistIcon
local heldExpires, twistExpires
local lastSound, lastLateSound = 0, 0
local wasPrompting, wasLate = false, false

-- Memo for the zone geometry, declared up here because layout() has to be able
-- to drop it: layout shows the zone textures again, and a zone that placeZones
-- had hidden for being zero-width would otherwise come back at its old size and
-- stay there until the weapon speed happened to change.
local tickSig

local function db() return csMod.db and csMod.db.sealtwist end

local function fontPath()
    if ns.UI and ns.UI.FONT_PATH then return ns.UI.FONT_PATH end
    return FONT
end

-- ---------------------------------------------------------------- spell setup

local function spellKnown(id)
    local name = GetSpellInfo(id)
    if not name then return nil end
    -- GetSpellInfo(name) only resolves for spells actually in the spellbook,
    -- which is what separates "exists in this client" from "this paladin has it".
    if not GetSpellInfo(name) then return nil end
    return name
end

local function collectSeals()
    wipe(sealNames)
    local seen = {}
    local function add(name)
        if not name or name == "" or seen[name] then return end
        seen[name] = true
        sealNames[#sealNames + 1] = name
    end

    for _, id in ipairs(SEAL_IDS) do add(spellKnown(id)) end

    -- Whatever prefix the client uses for seals in this language ("Seal",
    -- "Siegel", "Sceau"): take it from a seal we did resolve, then sweep the
    -- spellbook for siblings we have no ID for.
    local sample = sealNames[1]
    local prefix = sample and sample:match("^(%S+)")
    if prefix and GetNumSpellTabs and GetSpellBookItemName then
        local total = 0
        for i = 1, (GetNumSpellTabs() or 0) do
            local _, _, offset, numSpells = GetSpellTabInfo(i)
            if offset and numSpells then total = max(total, offset + numSpells) end
        end
        for i = 1, total do
            local name = GetSpellBookItemName(i, "spell")
            if name and name:sub(1, #prefix) == prefix then add(name) end
        end
    end
    return sealNames
end

-- True while this name is one of the two seals that can be held. The dropdown
-- offers every seal -- somebody may know a rank we cannot name -- but the
-- warning below tells them when their choice cannot work.
local function canHold(name)
    if not name or name == "" then return false end
    for _, id in ipairs(HELD_PREF) do
        if spellKnown(id) == name then return true end
    end
    return false
end

local function pickDefaults()
    local d = db()
    if not d then return end
    local known = {}
    for _, n in ipairs(sealNames) do known[n] = true end

    if d.heldSeal == "" or not known[d.heldSeal] then
        d.heldSeal = ""
        for _, id in ipairs(HELD_PREF) do
            local n = spellKnown(id)
            -- Never take the seal the other role already has: this also runs
            -- right after the player picked that one by hand, and re-picking it
            -- here would hand their choice straight back to the auto-pick.
            if n and n ~= d.twistSeal then d.heldSeal = n; break end
        end
    end
    -- Also re-pick when the stored twist seal collided with the held one: a
    -- paladin who learns Command after levelling with Righteousness would
    -- otherwise sit on "twist Righteousness into Righteousness" forever.
    if d.twistSeal == "" or not known[d.twistSeal] or d.twistSeal == d.heldSeal then
        d.twistSeal = ""
        for _, id in ipairs(TWIST_PREF) do
            local n = spellKnown(id)
            if n and n ~= d.heldSeal then d.twistSeal = n; break end
        end
    end
    -- "" means "nothing suitable found". Keeping it as an empty string would be
    -- TRUTHY in every "do we have a seal" test below and light the whole helper
    -- up on a paladin who cannot twist at all.
    heldName  = (d.heldSeal  ~= "") and d.heldSeal  or nil
    twistName = (d.twistSeal ~= "") and d.twistSeal or nil
    csName = spellKnown(CRUSADER_STRIKE)

    -- Icons for the rotation row. Taken from the spellbook rather than from the
    -- buff sweep, which only has them while the seal is actually up -- the row
    -- has to draw the step BEFORE you cast it.
    heldTex  = heldName  and select(3, GetSpellInfo(heldName))  or nil
    twistTex = twistName and select(3, GetSpellInfo(twistName)) or nil
    csTex    = csName    and select(3, GetSpellInfo(csName))    or nil
end

-- ---------------------------------------------------------------- live state

-- Seal buffs change on cast, not on a timer, so this runs on UNIT_AURA instead
-- of once per frame. The icon and the expiry come along in the same sweep: the
-- indicators want both, and scanning again for them every frame would be the
-- most expensive thing in the file.
local function refreshSeals(event, unit)
    -- UNIT_AURA fires for every unit in the group; ours is the only one that can
    -- carry our seals, and in a raid the rest is thousands of wasted scans.
    if event == "UNIT_AURA" and unit ~= "player" then return end
    hasHeld, hasTwist = false, false
    heldIcon, twistIcon, heldExpires, twistExpires = nil, nil, nil, nil
    if not (heldName or twistName) then return end
    for i = 1, 40 do
        local n, icon, _, _, _, expires = UnitBuff("player", i)
        if not n then break end
        if n == heldName then
            hasHeld, heldIcon, heldExpires = true, icon, expires
        elseif n == twistName then
            hasTwist, twistIcon, twistExpires = true, icon, expires
        end
    end
    -- "A twist was possible just now." Latched with a timestamp because the hit
    -- confirmation cannot read the live state: casting the second seal REPLACES
    -- the first, and whether UNIT_AURA or UNIT_SPELLCAST_SUCCEEDED arrives first
    -- is not guaranteed anywhere. If the aura update wins the race, hasHeld is
    -- already false and hasTwist already true by the time the cast is confirmed
    -- -- which is exactly why the sound never played.
    if hasHeld and not hasTwist then armedAt = GetTime() end
end

local function currentGCD()
    local castTime = select(4, GetSpellInfo(GCD_REFERENCE))
    if not castTime or castTime <= 0 then return GCD_MAX end
    local g = castTime / 1000
    if g < GCD_MIN then return GCD_MIN end
    if g > GCD_MAX then return GCD_MAX end
    return g
end

-- How far ahead of the swing the window has to be pulled for the cast to land
-- inside it, in seconds.
--
-- The naive answer is half the round trip that GetNetStats reports -- only the
-- outbound leg matters, the reply costs us nothing. Measured against real
-- twists that answer comes out too SMALL: the round trip is not the only delay
-- between deciding and the server acting, and the client adds a fixed slice of
-- its own on top. LAG_SCALE and LAG_FLOOR_MS are that correction, and they are
-- close to one whole round trip in practice rather than half of one.
--
-- Capped because a 600 ms spike would otherwise shove the prompt into the
-- middle of the swing, where pressing is worse than not pressing.
--
-- Polled once every OFFSET_POLL seconds rather than per frame: GetNetStats only
-- refreshes every few seconds anyway, and it is not a free call.
local LAG_SCALE   = 0.98
local LAG_FLOOR_MS = 10
local OFFSET_MAX  = 0.25
local OFFSET_POLL = 3
local offsetValue, offsetAt = 0, 0

local function latencyOffset(d)
    if not d.latency then return 0 end
    local now = GetTime()
    if now - offsetAt >= OFFSET_POLL then
        offsetAt = now
        local world = tonumber(select(4, GetNetStats())) or 0
        local o = (world * LAG_SCALE + LAG_FLOOR_MS) / 1000
        if o < 0 then o = 0 elseif o > OFFSET_MAX then o = OFFSET_MAX end
        offsetValue = o
    end
    return offsetValue
end

-- The zone boundaries, all as "seconds left before the swing", far end first.
local function bounds(d, gcd)
    local off = latencyOffset(d)
    local windowStart = d.window + off
    local lateStart   = min(d.lateWindow + off, windowStart)
    return windowStart + gcd, windowStart, lateStart, off
end

local function zoneOf(r, dangerStart, windowStart, lateStart, windowEnd)
    if r <= 0 then return Z_READY end
    if r > dangerStart then return Z_FILLER end
    if r > windowStart then return Z_DANGER end
    if r > lateStart   then return Z_TWIST end
    if r >= windowEnd  then return Z_LATE end
    return Z_MISS
end

-- Seconds until the global cooldown frees up. Seals have no cooldown of their
-- own, so whatever GetSpellCooldown reports for one IS the GCD.
local function gcdRemaining()
    local probe = twistName or heldName
    if not probe then return 0 end
    local start, dur = GetSpellCooldown(probe)
    if not start or not dur or dur <= 0 then return 0 end
    local left = (start + dur) - GetTime()
    return left > 0 and left or 0
end

local function csReady()
    if not csName then return false end
    local start, dur = GetSpellCooldown(csName)
    if not start or not dur or dur <= 0 then return true end
    -- A GCD-length "cooldown" is just the GCD, not Crusader Strike's own.
    if dur <= GCD_MAX + 0.05 then return true end
    return (start + dur) - GetTime() <= 0
end

-- ACTION_* are what the player should press right now.
local ACTION_NONE, ACTION_HELD, ACTION_TWIST, ACTION_CS = 0, 1, 2, 3

-- This swing's twist is already gone: whatever is on the global cooldown right
-- now frees up later than the moment a cast could still reach the server in
-- time. Worth its own state rather than letting the bar run hopefully into the
-- green -- the answer here is a filler or stopping the attack, not a faster
-- finger. Only interesting while there IS a twist left to lose.
local function twistLost(r, windowEnd)
    if not (hasHeld and not hasTwist) then return false end
    return (r - gcdRemaining()) < windowEnd
end

local function decide(d, r, gcd, dangerStart, windowStart, windowEnd)
    if not r then return ACTION_NONE end
    if gcdRemaining() > 0.05 then return ACTION_NONE end

    -- A head start on the prompt: the window is 0.4 s wide and a human needs
    -- part of that to see the cue and press. The zone colours stay exact -- only
    -- the prompt and the cue move.
    local lead = (d.reaction or 0) / 1000
    if r <= windowStart + lead and r > windowStart then
        if hasHeld and not hasTwist then return ACTION_TWIST end
    end

    if r <= windowStart then
        -- Inside the window: the twist only pays off if the held seal is up to
        -- be replaced, only once, and only while the cast can still get there.
        if r < windowEnd then return ACTION_NONE end
        if hasHeld and not hasTwist then return ACTION_TWIST end
        return ACTION_NONE
    end
    -- Danger zone: the whole point of drawing it is that nothing goes in here.
    if r <= dangerStart then return ACTION_NONE end

    -- Crusader Strike first when there is room for it AND the held seal behind
    -- it, and only while the seal it wants to hit with is up.
    if d.useCS and csName and hasTwist and csReady() and (r - windowStart) >= 2 * gcd then
        return ACTION_CS
    end
    if not hasHeld then return ACTION_HELD end
    return ACTION_NONE
end

-- ---------------------------------------------------------------- rotation
--
-- One twist per swing is only the picture for a slow weapon. As the weapon and
-- the spell haste change, the number of twists that fit between two Crusader
-- Strikes changes with them, and the useful shape becomes a short repeating
-- sequence rather than a single next step. Eight of them cover the range, and
-- which one applies follows from attack speed and the current global cooldown --
-- so the helper picks it rather than asking.
--
-- The names are the ones players use: twists over swings. The last one has no
-- fraction because at that speed there is nothing to divide -- the seal simply
-- stays up and Crusader Strike goes in whenever it is ready.
local R_CS, R_TWIST, R_CS_LATE, R_AUTO_T, R_AUTO_H = 1, 2, 3, 4, 5

local ROT_ORDER = { "1/2", "2/3", "2/2/5", "2/4", "1/3", "2/5", "2/5h", "ride" }
local ROT_STEPS = {
    ["1/2"]   = { R_CS, R_TWIST },
    ["2/3"]   = { R_CS, R_TWIST, R_TWIST },
    ["2/2/5"] = { R_CS, R_TWIST, R_CS_LATE, R_AUTO_T, R_TWIST },
    ["2/4"]   = { R_CS, R_TWIST, R_AUTO_T, R_TWIST },
    ["1/3"]   = { R_CS, R_AUTO_T, R_TWIST },
    ["2/5"]   = { R_CS, R_AUTO_T, R_TWIST, R_AUTO_T, R_TWIST },
    ["2/5h"]  = { R_CS, R_AUTO_H, R_TWIST, R_AUTO_H, R_TWIST },
    ["ride"]  = { R_AUTO_T, R_CS },
}
-- No Crusader Strike, no sequence: every swing is simply a twist, which is the
-- whole rotation for a paladin who has not taken the talent.
local ROT_SIMPLE = { R_TWIST }
local ROT_MAX_STEPS = 5

local rotKey, rotStep = nil, 1
local rotSteps = ROT_SIMPLE
local rotDirty = true

-- The ladder, top to bottom: the first line that fits wins. The thresholds are
-- weapon speeds in seconds, and the ones written against the global cooldown
-- move with spell haste instead of standing still.
local function pickRotation(speed, gcd)
    if not csName then return nil end
    local haste = GCD_MAX - gcd
    if speed > 2.6 then return "1/2" end
    if speed >= max(1.9, 2 * gcd - 0.35) and haste > 0.1 then return "2/3" end
    if speed >= 2.4 or (speed >= 2.3 and haste > 0.05) then return "2/2/5" end
    if speed >= max(1.5, 1.5 * gcd + 0.05) and haste > 0.1 then return "2/4" end
    if speed >= 1.9 then return "1/3" end
    if speed >= gcd + 0.07 then return "2/5" end
    if speed > 1.0 then return "2/5h" end
    return "ride"
end

local function rotAdvance()
    rotStep = rotStep + 1
    if rotStep > #rotSteps then rotStep = 1 end
end

local function updateRotation(d, speed, gcd)
    -- No weapon, no speed, no sequence: the ladder would read a zero as the
    -- fastest case there is and land on the last line.
    if not speed or speed <= 0 then return end
    local key
    if d.rotation ~= "auto" and ROT_STEPS[d.rotation] and csName then
        key = d.rotation
    else
        key = pickRotation(speed, gcd)
    end
    if key == rotKey then return end
    -- A rotation that changes mid-fight (drums, a weapon swap) starts over: the
    -- step counter of the old sequence means nothing in the new one.
    rotKey   = key
    rotSteps = key and ROT_STEPS[key] or ROT_SIMPLE
    rotStep  = 1
    rotDirty = true
end

-- What the player actually did decides where in the sequence they are. Casting
-- is the only honest signal for the two spell steps; the swing tracker is the
-- one for the auto steps.
local function rotOnCast(spellName)
    local cur = rotSteps[rotStep]
    if csName and spellName == csName then
        if cur == R_CS or cur == R_CS_LATE then
            rotAdvance()
        else
            -- Struck out of turn: the sequence always resumes right after its
            -- Crusader Strike, wherever that leaves us.
            rotStep = min(2, #rotSteps)
        end
    elseif twistName and spellName == twistName then
        if cur == R_TWIST then rotAdvance() end
    end
end

local function rotOnSwing(hand)
    if hand ~= "mainhand" then return end
    local cur = rotSteps[rotStep]
    if cur == R_AUTO_T or cur == R_AUTO_H then rotAdvance() end
end

-- The spell name each step points at, and the tint that says which seal carries
-- the swing on an auto step -- that is the only thing separating the two.
local ATTACK_ICON = "Interface\\ICONS\\INV_Sword_04"
local ROT_TINT = {
    [R_AUTO_T] = { 0.45, 1.00, 0.60 },
    [R_AUTO_H] = { 0.75, 0.60, 1.00 },
}

-- An auto step deliberately does NOT show the seal icon: the twist step already
-- has it, and two identical pictures a colour apart is the sort of row that
-- gets misread in the middle of a fight. The swing gets the attack icon, and
-- the tint says which seal it lands with.
local function stepTexture(step)
    if step == R_CS or step == R_CS_LATE then return csTex end
    if step == R_TWIST then return twistTex end
    return (GetSpellTexture and GetSpellTexture(6603)) or ATTACK_ICON
end

local function stepIsAuto(step)
    return step == R_AUTO_T or step == R_AUTO_H
end

-- Reads as a line of spell names, built from what the client already calls
-- them. Only the word for a swing needs translating.
local function rotationText(key)
    local steps = key and ROT_STEPS[key] or ROT_SIMPLE
    local out
    for i = 1, #steps do
        local s = steps[i]
        local word
        if s == R_CS or s == R_CS_LATE then word = csName or "?"
        elseif s == R_TWIST then word = twistName or "?"
        else word = L["auto"] end
        out = out and (out .. " > " .. word) or word
    end
    return out or ""
end

-- ---------------------------------------------------------------- appearance

-- The action line has its own size, because it is the one line that is read
-- mid-fight and the one that carries the longest text. 0 means "follow the
-- general size", so a profile that never touches it behaves exactly as before
-- and the two do not have to be kept in step by hand.
local function actionSize(d)
    local s = d.actionFontSize or 0
    return (s > 0) and s or d.fontSize
end

-- Same shape for the two side texts. Their fallbacks are the formulas that used
-- to be inline: the attack speed sat four below the general size, the seal
-- timer scaled with the icon it is drawn on -- so 0 keeps exactly what an
-- untouched profile has today.
-- The warning line ("twist lost", "swing ready") shares its FontString with the
-- action line but not its job: it is a sentence, not two words, and wants to be
-- smaller. 0 keeps it at the action size, which is how it behaved before.
local function warnSize(d)
    local s = d.warnFontSize or 0
    return (s > 0) and s or actionSize(d)
end

local function speedSize(d)
    local s = d.speedFontSize or 0
    return (s > 0) and s or max(9, d.fontSize - 4)
end

local function sealTimerSize(d)
    local s = d.sealTimerFontSize or 0
    return (s > 0) and s or max(8, d.iconSize * 0.4)
end

-- What the side pieces claim, so the bar keeps its configured width whether
-- they are shown or not.
local function sideWidths(d)
    local leftW  = d.showSpeed and (speedSize(d) * 2.4 + 6) or 0
    local rightW = d.showSeals and (d.iconSize * 2 + 10) or 0
    return leftW, rightW
end

-- Height the rotation row claims above the bar.
local function rowHeight(d)
    return d.showRotation and (d.rotIconSize + 4) or 0
end

-- Steps are laid out from the middle of the bar, so a sequence that grows or
-- shrinks stays centred instead of walking off one end.
local function placeRotation(d)
    if not rotIcons[1] then return end
    local n = min(#rotSteps, ROT_MAX_STEPS)
    local size, gap = d.rotIconSize, 3
    local span = n * size + (n - 1) * gap
    for i = 1, ROT_MAX_STEPS do
        local ico = rotIcons[i]
        ico:SetSize(size, size)
        ico:ClearAllPoints()
        ico:SetPoint("BOTTOMLEFT", bar, "TOPLEFT",
            (d.barWidth - span) / 2 + (i - 1) * (size + gap), 4)
    end
    rotLabel:ClearAllPoints()
    rotLabel:SetPoint("RIGHT", bar, "TOPLEFT", (d.barWidth - span) / 2 - 6, 4 + size / 2)
    rotDirty = false
end

local function layout()
    local d = db()
    if not frame or not d then return end

    local leftW, rightW = sideWidths(d)
    local rowH = rowHeight(d)
    local h = d.barHeight + rowH
    if d.showAction  then h = h + max(actionSize(d), warnSize(d)) + 4 end
    if d.showNumbers then h = h + max(9, d.fontSize - 6) + 2 end
    h = h + 6
    if d.showSeals and d.iconSize > h then h = d.iconSize end

    frame:SetSize(leftW + d.barWidth + rightW, h)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)

    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", leftW, -rowH)
    bar:SetSize(d.barWidth, d.barHeight)
    bar:SetShown(d.showBar)

    rotLabel:SetFont(fontPath(), max(9, d.rotIconSize * 0.5), "OUTLINE")
    rotLabel:SetShown(d.showRotation)
    for i = 1, ROT_MAX_STEPS do
        if not d.showRotation then rotIcons[i]:Hide() end
    end
    placeRotation(d)

    speedFS:SetFont(fontPath(), speedSize(d), "OUTLINE")
    speedFS:SetShown(d.showSpeed)
    actionFS:SetFont(fontPath(), actionSize(d), "OUTLINE")
    actionFS._vcSize = actionSize(d)
    actionFS:SetShown(d.showAction)
    infoFS:SetFont(fontPath(), max(9, d.fontSize - 6), "OUTLINE")
    infoFS:SetShown(d.showNumbers)

    for i = 1, 2 do
        local slot = sealSlots[i]
        slot:SetSize(d.iconSize, d.iconSize)
        slot:ClearAllPoints()
        slot:SetPoint("LEFT", bar, "RIGHT", 6 + (i - 1) * (d.iconSize + 4), 0)
        slot.time:SetFont(fontPath(), sealTimerSize(d), "OUTLINE")
        -- updateSeals stops touching them when the setting is off, so they have
        -- to be put away here or the last pair stays on screen for good.
        if not d.showSeals then slot:Hide() end
    end

    zoneFiller:SetShown(d.showBar and d.showZones)
    zoneDanger:SetShown(d.showBar and d.showZones)
    zoneTwist:SetShown(d.showBar and d.showZones)
    tickDanger:SetShown(d.showBar and d.showTicks)
    tickTwist:SetShown(d.showBar and d.showTicks)
    tickLate:SetShown(d.showBar and d.showTicks)

    -- Everything above can move a boundary; the memo has to go with it.
    tickSig = nil
end

-- Zones and marks sit at a fraction of the bar measured from the RIGHT, because
-- every boundary is defined as "time left before the swing", not time elapsed.
--
-- Memoised on everything that can move them: this runs once per frame, but the
-- geometry only changes when the weapon speed, haste, latency or a setting does.
local function placeZones(swingDur, dangerStart, windowStart, lateStart)
    local d = db()
    if not d.showBar or not swingDur or swingDur <= 0 then return end
    local sig = swingDur .. "|" .. dangerStart .. "|" .. windowStart .. "|"
        .. lateStart .. "|" .. d.barWidth
    if sig == tickSig then return end
    tickSig = sig

    local w = d.barWidth
    local fDanger = min(dangerStart / swingDur, 1)
    local fTwist  = min(windowStart / swingDur, 1)
    local fLate   = min(lateStart   / swingDur, 1)

    -- fromFrac and toFrac are both distances from the RIGHT edge, so a span
    -- runs from the later boundary to the earlier one.
    local function span(tex, fromFrac, toFrac)
        local width = w * (fromFrac - toFrac)
        if width < 1 then tex:Hide(); return end
        tex:Show()
        tex:ClearAllPoints()
        tex:SetPoint("TOPRIGHT",    bar, "TOPRIGHT",    -w * toFrac, 0)
        tex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -w * toFrac, 0)
        tex:SetWidth(width)
    end

    local function mark(tex, frac)
        if frac >= 1 then tex:Hide(); return end
        tex:Show()
        tex:ClearAllPoints()
        tex:SetPoint("TOP",    bar, "TOPRIGHT",    -w * frac, 0)
        tex:SetPoint("BOTTOM", bar, "BOTTOMRIGHT", -w * frac, 0)
    end

    if d.showZones then
        span(zoneTwist,  fTwist,  0)
        span(zoneDanger, fDanger, fTwist)
        span(zoneFiller, 1,       fDanger)
    end

    if d.showTicks then
        mark(tickDanger, fDanger)
        mark(tickTwist,  fTwist)
        -- The late mark would sit under the twist mark when both windows are
        -- set to the same length; hiding it says more than a doubled line.
        if lateStart >= windowStart then tickLate:Hide() else mark(tickLate, fLate) end
    end
end

-- Colour wrappers, not translatable text: the spell name inside them comes from
-- the client and is already localised.
local ACTION_TEXT = {
    [ACTION_HELD]  = "|cffb388ff%s|r",
    [ACTION_TWIST] = "|cff33ff66%s|r",
    [ACTION_CS]    = "|cffffcc33%s|r",
}

-- Which seals are on the player, and for how long. Both show while the twist is
-- in -- that overlap IS the pay-off, and seeing it is how a player confirms the
-- twist landed instead of inferring it from a colour.
local function updateSeals(d, now)
    if not d.showSeals then return end
    local n = 0
    local function put(icon, expires)
        n = n + 1
        local slot = sealSlots[n]
        if not slot then return end
        -- Only on a change: this runs fifty times a second, and re-setting the
        -- same texture path is the kind of small waste that adds up in a raid.
        if slot.shown ~= icon then
            slot.icon:SetTexture(icon)
            slot.shown = icon
        end
        local left = expires and (expires - now) or 0
        if left > 0 then
            slot.time:SetText(format("%d", floor(left + 0.5)))
        else
            slot.time:SetText("")
        end
        slot:Show()
    end
    if hasHeld  then put(heldIcon,  heldExpires) end
    if hasTwist then put(twistIcon, twistExpires) end
    for i = n + 1, 2 do sealSlots[i]:Hide() end
end

-- The step you are on is the only one at full strength; the rest of the
-- sequence stays visible but drained, so the row reads as "here, then this".
local function updateRotationDisplay(d)
    if not d.showRotation then return end
    if rotDirty then placeRotation(d) end
    rotLabel:SetText(rotKey or L["Twist only"])
    for i = 1, ROT_MAX_STEPS do
        local ico = rotIcons[i]
        local step = rotSteps[i]
        if not step then
            ico:Hide()
        else
            local tex = stepTexture(step)
            if ico.shown ~= tex then
                ico.icon:SetTexture(tex)
                ico.shown = tex
            end
            local current = (i == rotStep)
            local tint = ROT_TINT[step]
            if tint then
                ico.icon:SetVertexColor(tint[1], tint[2], tint[3])
            else
                ico.icon:SetVertexColor(1, 1, 1)
            end
            ico.icon:SetAlpha(current and 1 or 0.35)
            ico.edge:SetShown(current)
            ico:Show()
        end
    end
end

local function onUpdate()
    local d = db()
    if not d then return end

    local fake = d.unlocked or ns:IsMoverEditMode()
    local now = GetTime()
    local remaining, swingDur

    if fake then
        -- A fake 2.6 s swing so the bar, the zones and all three marks are
        -- visible while placing the frame out of combat.
        swingDur = 2.6
        remaining = swingDur - (now % swingDur)
    else
        local _, dur, active = ns:GetSwing("mainhand")
        if active and dur > 0 then
            swingDur = dur
            remaining = ns:SwingRemaining("mainhand")
        end
    end

    local gcd = currentGCD()
    local dangerStart, windowStart, lateStart, windowEnd = bounds(d, gcd)

    if d.showSpeed then
        local speed = swingDur or UnitAttackSpeed("player")
        if speed and speed > 0 then
            speedFS:SetText(format("%.1f", speed))
            -- Under two global cooldowns per swing the cycle stops fitting: the
            -- twist and the seal going back up need one each. That is the real
            -- cap, and because it moves with spell haste it is computed rather
            -- than written down as a fixed 3.0.
            if speed < 2 * gcd then
                speedFS:SetTextColor(0.95, 0.30, 0.30)
            else
                speedFS:SetTextColor(0.85, 0.85, 0.90)
            end
        else
            speedFS:SetText("")
        end
    end

    updateSeals(d, now)

    if d.showRotation then
        updateRotation(d, swingDur or UnitAttackSpeed("player") or 0, gcd)
        updateRotationDisplay(d)
    end

    if not remaining then
        -- Shown but not swinging: an empty bar rather than a stale one, so the
        -- frame reads as "waiting" instead of showing a swing that ended.
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetStatusBarColor(COL_IDLE[1], COL_IDLE[2], COL_IDLE[3])
        actionFS:SetText("")
        if d.showNumbers then infoFS:SetText(L["waiting for a swing"]) end
        -- Leaving these set would swallow the first cue of the next fight.
        wasPrompting, wasLate = false, false
        return
    end

    placeZones(swingDur, dangerStart, windowStart, lateStart)
    bar:SetMinMaxValues(0, swingDur)
    bar:SetValue(swingDur - remaining)

    local zone = zoneOf(remaining, dangerStart, windowStart, lateStart, windowEnd)
    local action = fake and ACTION_TWIST
        or decide(d, remaining, gcd, dangerStart, windowStart, windowEnd)

    -- The twist being IN outranks the zone: there is nothing left to do on this
    -- swing, and a green bar would keep asking for a cast that would overwrite
    -- the seal already carrying it.
    local lost = not fake and twistLost(remaining, windowEnd)

    local c
    if lost then
        c = ZONE_COLOR[Z_MISS]
    elseif action == ACTION_TWIST and zone == Z_DANGER then
        -- The head start puts the prompt in the last sliver of the danger zone
        -- on purpose. Leaving the bar red there would have the two halves of the
        -- display saying opposite things.
        c = ZONE_COLOR[Z_TWIST]
    elseif hasTwist and not fake and zone ~= Z_FILLER and zone ~= Z_DANGER then
        c = COL_DONE
    elseif zone == Z_TWIST or zone == Z_LATE then
        -- No held seal means the window is open on nothing.
        c = (hasHeld or fake) and ZONE_COLOR[zone] or ZONE_COLOR[Z_MISS]
    else
        c = ZONE_COLOR[zone] or COL_IDLE
    end
    bar:SetStatusBarColor(c[1], c[2], c[3])

    if d.showAction then
        local label, warn
        if action == ACTION_TWIST then
            label = format(ACTION_TEXT[ACTION_TWIST], twistName or L["Twist"])
        elseif action == ACTION_HELD then
            label = format(ACTION_TEXT[ACTION_HELD], heldName or L["Hold seal"])
        elseif action == ACTION_CS then
            label = format(ACTION_TEXT[ACTION_CS], csName or "")
        elseif lost then
            warn = true
            -- Short on purpose: this sits on a bar a few hundred pixels wide and
            -- is read out of the corner of the eye mid-fight. The reason it is
            -- lost (a cooldown landing late) is one of several, and naming that
            -- one made the line too long to take in at a glance.
            label = L["|cffff5555Twist lost|r"]
        elseif zone == Z_READY and not fake then
            -- A swing that is due and stays due means auto-attack is off. It is
            -- the classic way to lose a whole rotation without noticing, and
            -- the bar is the only place it shows.
            warn = true
            label = L["|cffffcc33Swing ready -- restart your attack|r"]
        else
            label = ""
        end
        -- One FontString, two jobs: "press this" and "something is wrong". They
        -- want different sizes -- the warning is a sentence, the action is two
        -- words -- so the font is switched with the text. Only when it actually
        -- differs: this runs on every frame of the bar.
        local want = warn and warnSize(d) or actionSize(d)
        if actionFS._vcSize ~= want then
            actionFS._vcSize = want
            actionFS:SetFont(fontPath(), want, "OUTLINE")
        end
        actionFS:SetText(label)
    end

    if d.showNumbers then
        -- No bare "|" as a separator: it opens an escape sequence for the font
        -- renderer and eats the character after it.
        local line = format(L["%.2fs left  -  swing %.2fs  -  GCD %.2fs"], remaining, swingDur, gcd)
        if windowEnd > 0 then
            line = line .. format(L["  -  lag %.0fms"], windowEnd * 1000)
        end
        infoFS:SetText(line)
    end

    -- Cues fire on the prompt, not on the zone: the window opens on every swing,
    -- and a beep that sounds while the twist is already in -- or while there is
    -- no held seal to twist out of -- trains the player to ignore it.
    local prompt = (action == ACTION_TWIST)
    if not fake then
        if d.sound and prompt and not wasPrompting and now - lastSound > 0.25 then
            lastSound = now
            PlaySoundFile(WINDOW_SOUND, "Master")
        end
        local late = prompt and zone == Z_LATE
        if d.soundLate and late and not wasLate and now - lastLateSound > 0.25 then
            lastLateSound = now
            local id = SOUNDKIT and SOUNDKIT.READY_CHECK
            if id then PlaySound(id, "Master") else PlaySoundFile(WINDOW_SOUND, "Master") end
        end
        wasLate = late
    end
    wasPrompting = prompt
end

local function create()
    if frame then return frame end
    local d = db()

    frame = CreateFrame("Frame", "VCUI_SealTwist", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture(BAR_TEX)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    barBG = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    barBG:SetAllPoints(bar)
    barBG:SetTexture(BAR_TEX)
    barBG:SetVertexColor(0.08, 0.08, 0.10, 0.9)

    -- Zone shading sits BELOW the fill: the stretch of the swing still to come
    -- shows which zone it runs into, while the stretch already spent is covered
    -- by the fill in the colour of the zone the swing is in right now.
    local function zoneTex(r, g, b)
        local t = bar:CreateTexture(nil, "BACKGROUND", nil, -4)
        t:SetTexture(BAR_TEX)
        t:SetVertexColor(r, g, b, 0.30)
        return t
    end
    zoneFiller = zoneTex(0.22, 0.52, 0.92)
    zoneDanger = zoneTex(0.85, 0.20, 0.20)
    zoneTwist  = zoneTex(0.20, 0.85, 0.35)

    local function tickTex(r, g, b, w)
        local t = bar:CreateTexture(nil, "OVERLAY")
        t:SetTexture(BAR_TEX)
        t:SetVertexColor(r, g, b, 0.95)
        t:SetWidth(w)
        return t
    end
    tickDanger = tickTex(1.00, 0.35, 0.35, 2)   -- filler ends, danger begins
    tickTwist  = tickTex(0.25, 1.00, 0.45, 2)   -- twist window opens
    tickLate   = tickTex(0.60, 1.00, 0.75, 1)   -- late window opens

    speedFS = frame:CreateFontString(nil, "OVERLAY")
    speedFS:SetPoint("RIGHT", bar, "LEFT", -6, 0)
    speedFS:SetTextColor(0.85, 0.85, 0.90)

    actionFS = frame:CreateFontString(nil, "OVERLAY")
    actionFS:SetPoint("TOP", bar, "BOTTOM", 0, -4)

    infoFS = frame:CreateFontString(nil, "OVERLAY")
    infoFS:SetPoint("TOP", actionFS, "BOTTOM", 0, -2)
    infoFS:SetTextColor(0.65, 0.65, 0.70)

    rotLabel = frame:CreateFontString(nil, "OVERLAY")
    rotLabel:SetTextColor(0.75, 0.70, 0.85)

    for i = 1, ROT_MAX_STEPS do
        local ico = CreateFrame("Frame", nil, frame)
        ico.edge = ico:CreateTexture(nil, "BACKGROUND")
        ico.edge:SetPoint("TOPLEFT", ico, "TOPLEFT", -2, 2)
        ico.edge:SetPoint("BOTTOMRIGHT", ico, "BOTTOMRIGHT", 2, -2)
        ico.edge:SetTexture(BAR_TEX)
        ico.edge:SetVertexColor(0.61, 0.42, 1.00, 0.9)
        ico.edge:Hide()
        ico.icon = ico:CreateTexture(nil, "ARTWORK")
        ico.icon:SetAllPoints(ico)
        ico.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ico:Hide()
        rotIcons[i] = ico
    end

    for i = 1, 2 do
        local slot = CreateFrame("Frame", nil, frame)
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints(slot)
        -- Trimmed: the client's own icon border is a fat beige ring that reads
        -- as a different UI at this size.
        slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        slot.time = slot:CreateFontString(nil, "OVERLAY")
        slot.time:SetPoint("BOTTOM", slot, "BOTTOM", 0, 1)
        slot.time:SetTextColor(1, 1, 1)
        slot:Hide()
        sealSlots[i] = slot
    end

    frame.mover = ns:CreateMover(frame, {
        key    = "sealtwist",
        label  = L["|cffffffffSEAL TWIST|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = d,
        width  = max(d.barWidth + 120, 240),
        height = 90,
        onMove = function(x, y)
            ns:Print(format(L["Seal Twist position: x=%.0f, y=%.0f"], x, y))
        end,
        editPreview = function() if frame then frame:Show() end end,
    })

    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + (elapsed or 0)
        if acc < 0.02 then return end
        acc = 0
        onUpdate()
    end)

    layout()
    return frame
end

-- Both seals have to exist for the helper to have anything to say -- but the
-- bar is not tied to the swing alone any more. It used to appear only while the
-- tracker held a live swing, which meant it flickered away between pulls, on
-- every target swap, and stayed away entirely on a paladin the seal check had
-- rejected. In combat is the honest condition; the swing decides what the bar
-- shows, not whether it exists.
local function applyVisibility()
    local d = db()
    if not frame or not d then return end
    if d.unlocked or ns:IsMoverEditMode() then frame:Show(); return end
    if not d.enabled then frame:Hide(); return end
    if not (heldName and twistName) then frame:Hide(); return end
    if d.showOOC then frame:Show(); return end
    local _, _, active = ns:GetSwing("mainhand")
    if active or UnitAffectingCombat("player") then frame:Show() else frame:Hide() end
end

local function setUnlocked(state)
    local d = db()
    d.unlocked = state and true or false
    create()
    if d.unlocked then
        frame:Show()
        frame.mover:Show()
        ns:Print(L["Seal Twist mover active. |cff9b6cffDrag the purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Test' again to finish."])
    else
        frame.mover:Hide()
        applyVisibility()
        ns:Print(L["Seal Twist mover disabled."])
    end
end

-- ---------------------------------------------------------------- module glue

-- Holding the tracker keeps a COMBAT_LOG_EVENT_UNFILTERED listener alive, so a
-- paladin who turned the helper off -- or who has no seal to twist in -- should
-- not be paying for it.
-- One callback for both jobs: the swing decides whether the bar is up at all,
-- and it is also what steps the rotation past an auto.
local function onSwing(hand)
    applyVisibility()
    rotOnSwing(hand)
end

local function syncTracker()
    local d = db()
    if d and d.enabled and heldName and twistName then
        ns:AcquireSwingTracker("sealtwist", onSwing)
    else
        ns:ReleaseSwingTracker("sealtwist")
    end
end

-- Did that cast actually twist? The seal has to have gone out while the swing
-- was inside the window, with the held seal still up to be replaced -- which is
-- the same test the bar draws, asked once at the moment it can be answered.
--
-- The cast is the right moment to ask, not the swing that follows: the server
-- accepted it here, and by the time the swing lands the aura sweep has already
-- overwritten the state this depends on.
-- Did the seal that just went out land INSIDE the window.
--
-- Deliberately does not look at the live aura state -- see the latch in
-- refreshSeals. It asks two things instead: was a twist possible a moment ago,
-- and is the swing inside the window right now.
local ARMED_GRACE = 0.4

local function twistHit(d)
    if not armedAt or (GetTime() - armedAt) > ARMED_GRACE then return false end
    local _, dur, active = ns:GetSwing("mainhand")
    if not active or dur <= 0 then return false end
    local r = ns:SwingRemaining("mainhand")
    if not r then return false end
    local _, windowStart, _, windowEnd = bounds(d, currentGCD())
    return r <= windowStart and r >= windowEnd
end

local function onCastSucceeded(_, unit, _, spellID)
    if unit ~= "player" then return end
    local d = db()
    if not d then return end
    local name = spellID and GetSpellInfo(spellID)
    if not name then return end
    if d.soundHit and twistName and name == twistName and twistHit(d) then
        playHitSound(d.hitSound)
        armedAt = nil   -- one confirmation per twist, not one per aura refresh
    end
    if d.showRotation then rotOnCast(name) end
end

local function onSpellsChanged()
    collectSeals()
    pickDefaults()
    refreshSeals()
    syncTracker()
    applyVisibility()
end

local function onEnable()
    local d = ns:ApplyDefaults(csMod.db.sealtwist, DEFAULTS)
    csMod.db.sealtwist = d
    -- An unlock that survived a reload would leave a mouse-grabbing frame on
    -- screen with nothing to explain it.
    d.unlocked = false

    onSpellsChanged()
    create()

    csMod:RegisterEvent("UNIT_AURA", refreshSeals)
    csMod:RegisterEvent("SPELLS_CHANGED", onSpellsChanged)
    csMod:RegisterEvent("PLAYER_ENTERING_WORLD", onSpellsChanged)
    -- Combat decides visibility now, and combat starts and ends without the
    -- swing tracker having anything to say about it.
    csMod:RegisterEvent("PLAYER_REGEN_DISABLED", applyVisibility)
    csMod:RegisterEvent("PLAYER_REGEN_ENABLED", applyVisibility)
    -- What the player cast is the only honest way to know where in the sequence
    -- they are; guessing from auras would count a seal that fell off as a step.
    csMod:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", onCastSucceeded)
    applyVisibility()
end

local function onDisable()
    ns:ReleaseSwingTracker("sealtwist")
    if frame then
        if frame.mover then frame.mover:Hide() end
        frame:Hide()
    end
end

-- ---------------------------------------------------------------- options

local function sealValues()
    local out = {}
    for _, n in ipairs(sealNames) do out[#out + 1] = { value = n, text = n } end
    if #out == 0 then out[1] = { value = "", text = L["(no seals learned)"] } end
    return out
end

-- The four built-ins first, then whatever sound packs other addons have
-- registered with shared media -- that list is where a sharper cue comes from.
local function hitSoundValues()
    local out = {}
    for _, s in ipairs(HIT_SOUNDS) do
        out[#out + 1] = { value = s.key, text = L[s.label] }
    end
    local LSM = ns.LSM
    if LSM then
        for _, n in ipairs(LSM:List("sound") or {}) do
            if n ~= "None" then out[#out + 1] = { value = LSM_PREFIX .. n, text = n } end
        end
    end
    return out
end

-- Each entry carries its own sequence in the text: the fraction alone means
-- nothing to somebody meeting it for the first time.
local function rotationValues()
    local out = { { value = "auto", text = L["Automatic"] } }
    if not csName then return out end
    for _, key in ipairs(ROT_ORDER) do
        out[#out + 1] = { value = key, text = key .. "  -  " .. rotationText(key) }
    end
    return out
end

local function getOptions()
    local items = {}

    table.insert(items, { type = "header", text = L["Seal Twist"] })
    table.insert(items, { type = "desc", text = L["|cffaaaaaaHold Seal of Command, then cast the second seal in the last fraction of a second before your auto-attack: that swing carries both. Below level 64 the second seal is Righteousness; Blood and the Martyr replace it from there.|r"] })
    table.insert(items, { type = "desc", text = L["|cffaaaaaaThe bar counts down to the swing in zones: |cff5c8aebblue|r is free for a filler, |cffd93636red|r is the stretch where a cast would still be on the global cooldown when the window opens, and |cff33ff66green|r is the twist window. The last mark inside the green is the late twist, which leaves room for a judgement in front of the seal.|r"] })

    if select(2, UnitClass("player")) ~= "PALADIN" then
        table.insert(items, { type = "desc", text = L["|cffff8800Only active while playing a Paladin.|r"] })
        return items
    end

    -- No settings table means the class tool never ran (module switched off).
    -- Falling back to DEFAULTS here would let every setter write into the shared
    -- defaults table and change the starting point for every character.
    local d = db()
    if not d then
        table.insert(items, { type = "desc", text = L["|cffff8800Switch the Class Specific module on to use this.|r"] })
        return items
    end

    if not heldName then
        table.insert(items, { type = "desc", text = L["|cffff8800No seal to twist out of. Only Seal of Command and Seal of Righteousness carry over to a swing after being replaced, so one of the two has to be learned.|r"] })
    elseif not twistName then
        table.insert(items, { type = "desc", text = L["|cffff8800Only one seal learned. A second one is needed to twist into.|r"] })
    elseif not canHold(d.heldSeal) then
        table.insert(items, { type = "desc", text = L["|cffff8800The seal you hold cannot be twisted out of. Only Seal of Command and Seal of Righteousness carry over to the swing that replaces them.|r"] })
    end

    table.insert(items, { type = "toggle", label = L["Enable seal twist helper"],
        get = function() return d.enabled end,
        set = function(_, v) d.enabled = v and true or false; syncTracker(); applyVisibility() end })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", label = L["Unlock / Test"], width = 130,
              onClick = function() setUnlocked(not d.unlocked) end },
            { type = "button", label = L["Center Position"], width = 150,
              onClick = function() d.x, d.y = 0, -180; layout() end },
        },
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Seals"] })
    table.insert(items, { type = "dropdown", label = L["Seal you hold"],
        tooltip = L["Only Seal of Command and Seal of Righteousness work here: they are the two whose effect still lands on the swing that replaces them."],
        values = sealValues(),
        get = function() return d.heldSeal end,
        set = function(_, v)
            d.heldSeal = v
            heldName = (v ~= "") and v or nil
            -- One seal in both roles is a no-op the player cannot see going
            -- wrong, so the other role gives way immediately.
            if v ~= "" and d.twistSeal == v then
                d.twistSeal, twistName = "", nil
                pickDefaults()
            end
            refreshSeals(); syncTracker(); applyVisibility()
        end })
    table.insert(items, { type = "dropdown", label = L["Seal you twist in"],
        values = sealValues(),
        get = function() return d.twistSeal end,
        set = function(_, v)
            d.twistSeal = v
            twistName = (v ~= "") and v or nil
            if v ~= "" and d.heldSeal == v then
                d.heldSeal, heldName = "", nil
                pickDefaults()
            end
            refreshSeals(); syncTracker(); applyVisibility()
        end })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Timing"] })
    table.insert(items, { type = "slider", label = L["Twist window (seconds)"],
        min = 0.20, max = 0.70, step = 0.01, decimals = 2,
        tooltip = L["How far before the swing the second seal has to land. 0.40 is the usual figure; raise it if your latency makes you miss the window."],
        get = function() return d.window end,
        set = function(_, v) d.window = v; layout() end })
    table.insert(items, { type = "slider", label = L["Late twist window (seconds)"],
        min = 0.05, max = 0.40, step = 0.01, decimals = 2,
        tooltip = L["The tail of the twist window, marked separately. Twisting that late still leaves room for a judgement in front of the seal. Set it as long as the twist window to hide the mark."],
        get = function() return d.lateWindow end,
        set = function(_, v) d.lateWindow = v; layout() end })
    table.insert(items, { type = "toggle", label = L["Compensate for latency"],
        tooltip = L["Pulls the window ahead of the swing far enough for the cast to reach the server inside it, and closes it once it no longer can. Measured from your world latency, capped at 250 ms."],
        get = function() return d.latency end,
        set = function(_, v) d.latency = v and true or false; layout() end })
    table.insert(items, { type = "slider", label = L["Head start for the prompt (ms)"],
        min = 0, max = 300, step = 10,
        tooltip = L["Shows the twist prompt and plays its cue this far before the window actually opens, so there is time to see it and press. The colours on the bar stay exact."],
        get = function() return d.reaction end,
        set = function(_, v) d.reaction = v end })
    table.insert(items, { type = "toggle", label = L["Suggest Crusader Strike"],
        tooltip = L["Prompts Crusader Strike when it is ready and there is room for it plus the Command cast before the window opens."],
        get = function() return d.useCS end,
        set = function(_, v) d.useCS = v and true or false end })
    table.insert(items, { type = "toggle", label = L["Sound when the window opens"],
        get = function() return d.sound end,
        set = function(_, v) d.sound = v and true or false end,
        subOptions = {
            { type = "toggle", label = L["Second cue for the late window"],
              tooltip = L["A different sound at the late twist mark, so the two ends of the window can be told apart without looking at the bar."],
              get = function() return d.soundLate end,
              set = function(_, v) d.soundLate = v and true or false end },
        } })
    table.insert(items, { type = "toggle", label = L["Sound when the twist lands"],
        tooltip = L["Fires when the seal actually went out inside the window, not when the window opened. That makes it a hit confirmation you can practise against with your eyes off the bar."],
        get = function() return d.soundHit end,
        set = function(_, v) d.soundHit = v and true or false end,
        subOptions = {
            { type = "dropdown", label = L["Hit sound"], width = 300,
              tooltip = L["The rifle shot is bundled; the rest are the client's own cues. Below them stand any sounds other addons have registered as shared media."],
              values = hitSoundValues(),
              get = function() return d.hitSound end,
              set = function(_, v) d.hitSound = v; playHitSound(v) end },
            { type = "button", label = L["Listen"], width = 130,
              onClick = function() playHitSound(d.hitSound) end },
        } })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Rotation"] })
    table.insert(items, { type = "toggle", label = L["Show the rotation helper"],
        tooltip = L["A row of steps above the bar: which sequence fits your weapon and haste, and where in it you are. It steps forward on what you actually cast and on your swings."],
        get = function() return d.showRotation end,
        set = function(_, v) d.showRotation = v and true or false; layout() end,
        subOptions = {
            { type = "dropdown", label = L["Sequence"], width = 300,
              tooltip = L["Automatic follows your attack speed and spell haste, which is what decides how many twists fit between two strikes. Pick one by hand to drill a single sequence."],
              values = rotationValues(),
              get = function() return d.rotation end,
              set = function(_, v) d.rotation = v; layout() end },
            { type = "slider", label = L["Rotation icon size"], min = 14, max = 48, step = 1,
              get = function() return d.rotIconSize end,
              set = function(_, v) d.rotIconSize = v; layout() end },
        } })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Display"] })
    table.insert(items, { type = "toggle", label = L["Show swing bar"],
        get = function() return d.showBar end,
        set = function(_, v) d.showBar = v and true or false; layout() end,
        subOptions = {
            { type = "toggle", label = L["Shade the zones"],
              tooltip = L["Tints the part of the swing still to come in the colour of the zone it runs into."],
              get = function() return d.showZones end,
              set = function(_, v) d.showZones = v and true or false; layout() end },
            { type = "toggle", label = L["Show the marks"],
              tooltip = L["The three boundary lines: danger zone, twist window, late twist."],
              get = function() return d.showTicks end,
              set = function(_, v) d.showTicks = v and true or false; layout() end },
        } })
    table.insert(items, { type = "toggle", label = L["Show attack speed"],
        tooltip = L["Your current weapon speed, left of the bar. It turns red below two global cooldowns per swing -- under that the twist and the seal going back up no longer both fit, so wait for the cooldown before twisting."],
        get = function() return d.showSpeed end,
        set = function(_, v) d.showSpeed = v and true or false; layout() end })
    table.insert(items, { type = "toggle", label = L["Show seal indicators"],
        tooltip = L["The seals currently on you and how long they last, right of the bar. Both show while the twist is in -- that overlap is the pay-off."],
        get = function() return d.showSeals end,
        set = function(_, v) d.showSeals = v and true or false; layout() end,
        subOptions = {
            { type = "slider", label = L["Seal icon size"], min = 14, max = 48, step = 1,
              get = function() return d.iconSize end,
              set = function(_, v) d.iconSize = v; layout() end },
        } })
    table.insert(items, { type = "toggle", label = L["Show next action"],
        get = function() return d.showAction end,
        set = function(_, v) d.showAction = v and true or false; layout() end })
    table.insert(items, { type = "toggle", label = L["Show numbers"],
        get = function() return d.showNumbers end,
        set = function(_, v) d.showNumbers = v and true or false; layout() end })
    table.insert(items, { type = "toggle", label = L["Show out of combat"],
        tooltip = L["Normally the bar is only up in combat. Switch this on to keep it on screen, which is the easier way to practise the timing on a dummy."],
        get = function() return d.showOOC end,
        set = function(_, v) d.showOOC = v and true or false; applyVisibility() end })
    table.insert(items, { type = "slider", label = L["Bar width"], min = 120, max = 400, step = 10,
        get = function() return d.barWidth end,
        set = function(_, v) d.barWidth = v; layout() end })
    table.insert(items, { type = "slider", label = L["Bar height"], min = 10, max = 40, step = 1,
        get = function() return d.barHeight end,
        set = function(_, v) d.barHeight = v; layout() end })
    table.insert(items, { type = "slider", label = L["Font size"], min = 10, max = 30, step = 1,
        get = function() return d.fontSize end,
        set = function(_, v) d.fontSize = v; layout() end })
    table.insert(items, { type = "slider", label = L["Action text size"], min = 0, max = 40, step = 1,
        tooltip = L["The line that names what to press. 0 follows the general text size."],
        get = function() return d.actionFontSize or 0 end,
        set = function(_, v) d.actionFontSize = v; layout() end })
    table.insert(items, { type = "slider", label = L["Warning text size"], min = 0, max = 40, step = 1,
        tooltip = L["The red and yellow warnings on the bar. 0 follows the action text size."],
        get = function() return d.warnFontSize or 0 end,
        set = function(_, v) d.warnFontSize = v; layout() end })
    table.insert(items, { type = "slider", label = L["Attack speed text size"], min = 0, max = 40, step = 1,
        tooltip = L["The number on the left. 0 follows the general text size."],
        get = function() return d.speedFontSize or 0 end,
        set = function(_, v) d.speedFontSize = v; layout() end })
    table.insert(items, { type = "slider", label = L["Seal timer text size"], min = 0, max = 40, step = 1,
        tooltip = L["The countdown on the seal icons. 0 scales it with the icon."],
        get = function() return d.sealTimerFontSize or 0 end,
        set = function(_, v) d.sealTimerFontSize = v; layout() end })

    return items
end

csMod:RegisterClassTool("PALADIN", {
    onEnable   = onEnable,
    onDisable  = onDisable,
    getOptions = getOptions,
})
