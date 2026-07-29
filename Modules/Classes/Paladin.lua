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
-- What it long refused to do: prompt Judgement. Judging CONSUMES the seal, so a
-- mistimed prompt costs more than no prompt at all. It is offered now, because
-- a paladin who judges out of the twist has a real question about when -- but it
-- is off by default and it stays the player's call.
--
-- ---------------------------------------------------------------------------
-- SPLIT ACROSS SIX FILES, and the reason is a hard limit rather than taste:
-- Lua 5.1 allows 200 top-level locals per chunk, and this helper is past what
-- one chunk can hold. It is cut along its own seams instead of at an arbitrary
-- line count, and everything shared hangs on ns.SealTwist:
--
--   Modules/Classes/Paladin.lua              this file -- registration, the
--       saved defaults, the seal data, the timing core, the zones, the swing
--       hook and the module glue
--   Modules/Classes/PaladinTwistBar.lua      the frame and everything drawn
--   Modules/Classes/PaladinTwistHit.lua      did the twist land, and the
--       feedback that says so
--   Modules/Classes/PaladinTwistNext.lua     what to press next
--   Modules/Classes/PaladinTwistPractice.lua the practice mode
--   Modules/Classes/PaladinTwistOptions.lua  the options tree
--
-- Load order is TOC order and this file is first, because it is the one that
-- creates ns.SealTwist. Beyond that the order does not matter: the other files
-- only ADD to the table while loading, and every call between them happens at
-- runtime, by which point all six have been read.
local _, ns = ...

local csMod = ns.modules and ns.modules.vtmanadisplay
if not csMod or not csMod.RegisterClassTool then return end

local GetTime, GetSpellInfo, GetSpellCooldown = GetTime, GetSpellInfo, GetSpellCooldown
local UnitBuff = UnitBuff
local GetNetStats = GetNetStats
local min, max = math.min, math.max

-- The shared surface. Fields are the live state the other five files read and
-- write; capitalised entries are functions. Nothing here is a bare global, so
-- no other addon can see or collide with any of it.
local ST = {}
ns.SealTwist = ST
ST.csMod = csMod

ST.DEFAULTS = {
    -- Off until asked for. Twisting is a Retribution habit, not something every
    -- paladin does, and a bar that appears in the middle of the screen on its
    -- own the first time you enter combat is not a welcome surprise. Off also
    -- means the swing tracker is never held, so nobody pays for a feature they
    -- did not ask for.
    enabled     = false,
    window      = 0.40,   -- seconds before the swing that the twist lands in
    lateWindow  = 0.20,   -- tail of that window: still room for a judgement
    reaction    = 100,    -- ms of head start on the prompt, for the human
    heldSeal    = "",     -- resolved on first run
    twistSeal   = "",
    showBar     = true,
    showZones   = true,
    showTicks   = true,
    showSeals   = true,   -- which seals are on you, and for how long
    showRotation = true,  -- the sequence row above the bar
    rotation    = "auto", -- or one of ROT_ORDER, chosen by hand
    rotIconSize = 24,
    showAction  = true,
    -- Off: the zone colours and the marks are what you read mid-swing, and the
    -- numbers are a diagnostic line. Whoever wants to check the latency the bar
    -- is working with switches it on and leaves it on.
    showNumbers = false,
    -- When the bar is on screen at all. "combat" is what the helper always did;
    -- the other three are there because a paladin practising on a dummy and a
    -- paladin raiding want opposite answers. See ST.ApplyVisibility.
    visibility  = "combat",   -- "always" | "combat" | "seal" | "combatOrSeal"
    -- Twisting is a two-hander habit: the whole point is a slow swing with room
    -- for two casts in front of it. Off by default because the talent is not
    -- required to twist, only to make it worth doing.
    twoHandSpecOnly = false,
    useCS       = true,
    -- How long Crusader Strike may be left sitting on a free cooldown before it
    -- outranks everything else. Above this the strike is simply being wasted,
    -- and no arrangement of twists pays for that.
    csMaxDelayMs = 1700,

    -- NEXT ACTION GUIDE. Its own icon frame, off by default: the bar already
    -- names what to press, and a second display saying the same thing is only
    -- worth the screen space to somebody who wants to read the picture instead
    -- of the word.
    naEnabled    = false,
    naPos        = { x = 0, y = -280, unlocked = false },
    naIconSize   = 45,
    naVisibility = "combat",
    -- These three feed the SHARED decision, so the bar's action line answers the
    -- same way the icon does. One question, two renderings.
    naHold       = true,
    -- Off, because prompting a judgement is the one thing this helper spent its
    -- whole life refusing to do -- see the note at the top of the file. It is
    -- offered now, and it is still the player's call whether to trust it.
    naShowJudge  = false,
    naShowFiller = true,
    naManaConsecration = 35,
    naManaExorcism     = 30,

    -- PRACTICE MODE. Nothing here is saved as "on": the mode is started by hand
    -- and stopped by hand, and a practice run that survived a reload would put
    -- a fake swing bar on screen at the character select screen's expense.
    -- 0 for the speed means "whatever is actually equipped".
    practiceSpeed    = 0,
    practiceQueueMs  = 400,
    practiceKeys     = {
        held = "1", twist = "2", cs = "3", judge = "4", filler = "5", attack = "T",
    },
    practicePanelPos = { x = -320, y = 0, unlocked = false },
    practiceResultPos  = { x = 0, y = 120, unlocked = false },
    practiceResultSize = 28,
    practiceResultDuration = 0.8,
    practiceColorHit   = { r = 0.20, g = 1.00, b = 0.35 },
    practiceColorMiss  = { r = 1.00, g = 0.25, b = 0.25 },
    practiceTimeline      = true,
    practiceTimelinePos   = { x = 0, y = -300, unlocked = false },
    practiceTimelineWidth = 600,
    practiceTimelinePPS   = 80,

    -- LATENCY CALIBRATION. The raw round trip is not what the twist has to beat
    -- -- see ST.LagCalibratedMs -- so it is scaled and shifted, and both are
    -- exposed because the correction depends on the route, not on the addon.
    lagMultiplier = 1.4,
    lagOffsetMs   = 15,

    -- DEADZONE: the tail of the swing a cast can no longer cross. Measured from
    -- the RAW world latency, deliberately not the calibrated figure -- this is
    -- the physical trip, not a tuned prediction -- and scaled by hand because
    -- the trip that matters is the one to the realm, not the one to the router.
    showDeadzone    = true,
    deadzoneScale   = 1.0,
    deadzoneTexture = "Matte",
    deadzoneColor   = { r = 0.72, g = 0.05, b = 0.05 },
    deadzoneAlpha   = 0.72,

    -- The GCD sub-bar draws the cooldown you are actually sitting on across the
    -- swing it eats into, which is the one thing the zones cannot show: they say
    -- where the boundaries are, not how much of this swing is already spent.
    showGCDBar   = true,
    gcdBarHeight = 6,
    -- Padding pulls the GCD boundary earlier so a cast that has to travel still
    -- clears it. Dynamic follows the calibrated latency, fixed is a flat number
    -- for whoever prefers one they chose themselves.
    gcdPadding   = "dynamic",  -- "none" | "dynamic" | "fixed"
    gcdPaddingMs = 100,
    -- Same three modes for the twist window itself.
    twistPadding   = "dynamic",
    twistPaddingMs = 0,
    -- Off by default: it is a fourth mark on a bar that already carries three,
    -- and it only means something to a paladin who judges out of the twist.
    showJudgeMarker = false,
    sound       = false,  -- cue when the window opens
    soundLate   = false,  -- cue when the late window opens
    -- TWIST CONFIRMATION. All three are fed by the same combat-log proof and
    -- switch independently, because they suit different ways of practising:
    -- the sound for eyes-off-the-bar, the glow for eyes-on-it, the line for
    -- somebody who wants to see it happen rather than sense it.
    soundHit    = false,
    hitSound    = "sniper",
    hitChannel  = "Master",   -- "Master" | "SFX"
    hitGlow     = false,
    hitGlowColor    = { r = 0.20, g = 1.00, b = 0.35 },
    hitGlowDuration = 0.4,
    hitGlowType     = "pixel",  -- "pixel" | "autocast"
    hitText     = false,
    hitTextFont     = "",
    hitTextSize     = 24,
    hitTextOutline  = "OUTLINE",
    hitTextColor    = { r = 0.20, g = 1.00, b = 0.35 },
    hitTextDuration = 1.5,
    -- Same reason as sealPos: the mover engine reads db.unlocked.
    hitTextPos      = { x = 0, y = 200, unlocked = false },
    barWidth    = 240,
    barHeight   = 22,
    fontSize    = 18,

    -- SEAL INDICATORS. Attached to the right of the bar by default, because
    -- that is where they have always been and because the pair reads as part of
    -- the bar rather than as a second display. Detaching gives them their own
    -- position and their own mover, for a layout where the bar sits under the
    -- character and the seals belong up with the buffs.
    iconSize    = 26,
    sealSpacing = 4,
    -- Off: turning it on rescales the icons to the bar the moment the profile
    -- loads, and an untouched profile should look exactly as it did.
    sealMatchBarHeight = false,
    -- Centred keeps the pair's midpoint still when the second seal appears or
    -- falls off. Left-aligned keeps the FIRST icon still instead, which is what
    -- an attached row wants -- it hangs off the bar's edge.
    sealCentered = false,
    sealDetached = false,
    -- The unlock flag lives INSIDE the position table, not beside it. That table
    -- is what the mover engine is handed as its db, and the engine reads
    -- db.unlocked to decide whether the arrow keys nudge this box and whether it
    -- stays up when edit mode closes. A flag kept one level higher is a flag it
    -- never sees.
    sealPos      = { x = 0, y = -220, unlocked = false },
    -- The client's own sweep. It says the same thing as the number underneath,
    -- but it says it without being read, which is the point mid-fight.
    sealSwipe      = true,
    sealTimerColor = { r = 1, g = 1, b = 1 },
    actionFontSize = 0,   -- 0 = follow fontSize;  see ST.ActionSize
    warnFontSize   = 0,   -- 0 = follow actionFontSize; see ST.WarnSize
    sideFontSize   = 0,   -- 0 = fontSize - 4;     see ST.SideSize
    sealTimerFontSize = 0,-- 0 = scales with the icon; see ST.SealTimerSize
    x           = 0,
    y           = -180,
    unlocked    = false,

    -- TEXTURES. All four go through shared media, so the bar can be made to
    -- match whatever the rest of the interface already uses.
    barTexture    = "Matte",
    gcdTexture    = "Matte",
    bgTexture     = "Matte",
    markerTexture = "Matte",
    markerWidth   = 2,
    bgColor       = { r = 0.08, g = 0.08, b = 0.10 },
    bgAlpha       = 0.90,

    -- BORDER. None is the default because the bar is read at a glance and an
    -- outline around it competes with the marks inside it. Solid draws four
    -- one-colour edges; texture takes an edge file from shared media.
    borderMode    = "none",   -- "none" | "solid" | "texture"
    borderTexture = "",
    borderWidth   = 1,
    borderColor   = { r = 0, g = 0, b = 0 },

    -- Where the frame sits in the stack. MEDIUM and a low level keep it under
    -- menus and tooltips; raise the level to lift it over another addon's bar.
    strata     = "MEDIUM",
    drawLevel  = 10,

    -- FONT. An empty name means "whatever font the rest of the addon uses",
    -- which is what an untouched profile wants -- naming a bundled font here
    -- would quietly override the interface-wide choice.
    font        = "",
    fontOutline = "OUTLINE",  -- "" | "OUTLINE" | "THICKOUTLINE"
    fontColor   = { r = 1, g = 1, b = 1 },

    -- The two readouts inside the bar. Attack speed on the left is what the
    -- helper always showed; the swing timer on the right is the obvious partner.
    leftText  = "attackSpeed",  -- "attackSpeed" | "swingTimer" | "latency" | "gcd" | "none"
    rightText = "swingTimer",

    -- COLOURS.
    --
    -- Two ways to colour the fill, and they answer different questions. Zones
    -- says WHEN -- the colour is the stretch of the swing you are in, which is
    -- what this helper was built around. Seal says WHAT -- the colour is the
    -- seal you are carrying, which is the faster read once the timing is in the
    -- fingers and the thing you still get wrong is the seal.
    barColorSource = "zones",   -- "zones" | "seal"
    sealColors = {
        command       = { r = 0.14, g = 0.66, b = 0.14 },
        righteousness = { r = 0.85, g = 0.72, b = 0.20 },
        blood         = { r = 0.70, g = 0.10, b = 0.10 },
        vengeance     = { r = 0.55, g = 0.20, b = 0.70 },
        crusader      = { r = 0.90, g = 0.55, b = 0.15 },
        justice       = { r = 0.20, g = 0.45, b = 0.85 },
        light         = { r = 0.95, g = 0.95, b = 0.80 },
        wisdom        = { r = 0.30, g = 0.75, b = 0.75 },
    },
    -- The special states, which outrank whichever source is chosen.
    colNoTwist  = { r = 0.45, g = 0.16, b = 0.16 },
    colWarning  = { r = 1.00, g = 0.80, b = 0.20 },
    colTwisting = { r = 0.14, g = 0.45, b = 0.22 },
    colDefault  = { r = 0.35, g = 0.35, b = 0.42 },
    colGCD      = { r = 0.48, g = 0.48, b = 0.48 },
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
-- ST.PickDefaults skips it rather than trusting the order.
local HELD_PREF  = { 20375, 20154 }
local TWIST_PREF = { 31892, 348700, 31801, 20154, 21082, 20164, 20165, 20166 }

ST.CRUSADER_STRIKE = 35395
-- Judgement, for the optional marker that says when it comes off cooldown
-- during this swing.
local JUDGEMENT = 20271
-- The two fillers, for the stretch of the swing where casting something else is
-- free. Exorcism only lands on the undead and demons, so it is offered only when
-- the client agrees the target can take it -- see ST.PickFiller.
local CONSECRATION = 26573
local EXORCISM     = 879
-- Two-Handed Weapon Specialization, rank 1. The talent is matched by NAME
-- against this spell rather than by a hardcoded tree position: the position
-- moves between client builds, and matching an English string would find
-- nothing on eight of our nine locales.
local TWO_HAND_SPEC = 20111
-- Flash of Light rank 1 is a plain 1.5 s cast, so its CURRENT cast time is the
-- current spell GCD: the same haste scales both, and it needs no cooldown to be
-- running to be readable.
local GCD_REFERENCE = 19750
ST.GCD_MIN, ST.GCD_MAX = 1.0, 1.5

ST.BAR_TEX = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"
ST.WINDOW_SOUND = 567458

-- Zones, in the order the swing runs through them.
ST.Z_FILLER, ST.Z_DANGER, ST.Z_TWIST, ST.Z_LATE, ST.Z_MISS, ST.Z_READY = 1, 2, 3, 4, 5, 6

-- The fill takes the colour of the zone the swing is in, so the bar is readable
-- out of the corner of the eye without reading the marks at all.
--
-- The four TRUE zones stay in code. They are not decoration: blue-red-green in
-- that order is what the whole helper teaches, and a profile that recoloured
-- the danger zone green would be a profile that lies. The two entries below
-- them are not zones at all -- they are states that happen to arrive through
-- the same function -- so those come from the settings.
local ZONE_COLOR = {
    [ST.Z_FILLER] = { 0.22, 0.52, 0.92 },   -- free to cast something else
    [ST.Z_DANGER] = { 0.85, 0.20, 0.20 },   -- casting now costs the twist
    [ST.Z_TWIST]  = { 0.20, 0.85, 0.35 },   -- cast the second seal
    [ST.Z_LATE]   = { 0.10, 0.62, 0.28 },   -- still in, judgement fits in front
}

-- Unpacks a saved colour, which is stored as a table of named channels. The
-- fallback is what an option that has never been touched should look like, and
-- it is passed rather than defaulted to white: a missing colour showing up as
-- white on a dark bar reads as a bug, while showing up as the old hardcoded
-- value reads as nothing happening at all -- which is the truth.
function ST.Color(c, fr, fg, fb)
    if type(c) ~= "table" then return fr, fg, fb end
    return c.r or fr, c.g or fg, c.b or fb
end

-- The colour the fill takes for a zone. Z_MISS and Z_READY are settings because
-- they are states, not stretches of the swing; see the note above.
function ST.ZoneColor(d, zone)
    if zone == ST.Z_MISS  then return ST.Color(d.colNoTwist, 0.45, 0.16, 0.16) end
    if zone == ST.Z_READY then return ST.Color(d.colWarning, 1.00, 0.80, 0.20) end
    local c = ZONE_COLOR[zone]
    if not c then return ST.Color(d.colDefault, 0.35, 0.35, 0.42) end
    return c[1], c[2], c[3]
end

-- Which colour setting each seal answers to. Blood and the Martyr share one:
-- they are the same seal on the two factions, and offering two pickers for one
-- decision is how a settings page gets long without getting more useful.
local SEAL_COLOR_KEY = {
    [20375]  = "command",
    [20154]  = "righteousness",
    [31892]  = "blood",
    [348700] = "blood",
    [31801]  = "vengeance",
    [21082]  = "crusader",
    [20164]  = "justice",
    [20165]  = "light",
    [20166]  = "wisdom",
}
-- Filled by ST.PickDefaults: seal NAME in this client's language -> colour key.
ST.sealColorKey = {}

-- Live state, shared with the other five files.
ST.sealNames = {}     -- ordered list of seal names this character knows
ST.heldName, ST.twistName, ST.csName = nil, nil, nil
ST.heldTex, ST.twistTex, ST.csTex = nil, nil, nil
ST.hasHeld, ST.hasTwist = false, false
ST.heldIcon, ST.twistIcon = nil, nil
ST.heldExpires, ST.twistExpires = nil, nil
ST.heldDuration, ST.twistDuration = nil, nil

function ST.DB() return csMod.db and csMod.db.sealtwist end

function ST.FontPath()
    if ns.UI and ns.UI.FONT_PATH then return ns.UI.FONT_PATH end
    return FONT
end

-- ---------------------------------------------------------------- spell setup

function ST.SpellKnown(id)
    local name = GetSpellInfo(id)
    if not name then return nil end
    -- GetSpellInfo(name) only resolves for spells actually in the spellbook,
    -- which is what separates "exists in this client" from "this paladin has it".
    if not GetSpellInfo(name) then return nil end
    return name
end

function ST.CollectSeals()
    local sealNames = ST.sealNames
    wipe(sealNames)
    local seen = {}
    local function add(name)
        if not name or name == "" or seen[name] then return end
        seen[name] = true
        sealNames[#sealNames + 1] = name
    end

    for _, id in ipairs(SEAL_IDS) do add(ST.SpellKnown(id)) end

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
function ST.CanHold(name)
    if not name or name == "" then return false end
    for _, id in ipairs(HELD_PREF) do
        if ST.SpellKnown(id) == name then return true end
    end
    return false
end

function ST.PickDefaults()
    local d = ST.DB()
    if not d then return end
    local known = {}
    for _, n in ipairs(ST.sealNames) do known[n] = true end

    if d.heldSeal == "" or not known[d.heldSeal] then
        d.heldSeal = ""
        for _, id in ipairs(HELD_PREF) do
            local n = ST.SpellKnown(id)
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
            local n = ST.SpellKnown(id)
            if n and n ~= d.heldSeal then d.twistSeal = n; break end
        end
    end
    -- "" means "nothing suitable found". Keeping it as an empty string would be
    -- TRUTHY in every "do we have a seal" test below and light the whole helper
    -- up on a paladin who cannot twist at all.
    ST.heldName  = (d.heldSeal  ~= "") and d.heldSeal  or nil
    ST.twistName = (d.twistSeal ~= "") and d.twistSeal or nil
    ST.csName = ST.SpellKnown(ST.CRUSADER_STRIKE)

    -- Icons for the rotation row. Taken from the spellbook rather than from the
    -- buff sweep, which only has them while the seal is actually up -- the row
    -- has to draw the step BEFORE you cast it.
    ST.heldTex  = ST.heldName  and select(3, GetSpellInfo(ST.heldName))  or nil
    ST.twistTex = ST.twistName and select(3, GetSpellInfo(ST.twistName)) or nil
    ST.csTex    = ST.csName    and select(3, GetSpellInfo(ST.csName))    or nil

    ST.judgeName = ST.SpellKnown(JUDGEMENT)
    ST.consName  = ST.SpellKnown(CONSECRATION)
    ST.exoName   = ST.SpellKnown(EXORCISM)
    ST.judgeTex = ST.judgeName and select(3, GetSpellInfo(ST.judgeName)) or nil
    ST.consTex  = ST.consName  and select(3, GetSpellInfo(ST.consName))  or nil
    ST.exoTex   = ST.exoName   and select(3, GetSpellInfo(ST.exoName))   or nil

    -- Resolved once here rather than per frame: the map is keyed by spell ID,
    -- the bar only ever has a NAME, and GetSpellInfo per ID per frame would be
    -- nine calls fifty times a second for an answer that changes when the
    -- player levels.
    wipe(ST.sealColorKey)
    for id, key in pairs(SEAL_COLOR_KEY) do
        local n = GetSpellInfo(id)
        if n then ST.sealColorKey[n] = key end
    end
end

-- The colour of the seal the swing is carrying, or nil when there is no seal to
-- ask about. The twist seal wins when both are up -- it is the one that just
-- landed, and it is the one the swing is about.
function ST.SealColor(d)
    local name = (ST.hasTwist and ST.twistName) or (ST.hasHeld and ST.heldName) or nil
    if not name then return nil end
    local key = ST.sealColorKey[name]
    local c = key and d.sealColors and d.sealColors[key]
    if not c then return nil end
    return ST.Color(c, 0.35, 0.35, 0.42)
end

-- ---------------------------------------------------------------- talents

-- Two-Handed Weapon Specialization is the talent that makes twisting worth the
-- trouble, so it is offered as a condition for showing the helper at all.
--
-- Cached rather than asked per frame, and refreshed on a delay as well as
-- immediately: the talent API is not reliably updated by the time
-- CHARACTER_POINTS_CHANGED fires, so an immediate read right after spending a
-- point can still answer with the old rank.
local hasTwoHandSpec = false
function ST.HasTwoHandSpec() return hasTwoHandSpec end

local function scanTwoHandSpec()
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return false end
    local want = GetSpellInfo(TWO_HAND_SPEC)
    if not want then return false end
    for tab = 1, (GetNumTalentTabs() or 0) do
        for i = 1, (GetNumTalents(tab) or 0) do
            local name, _, _, _, rank = GetTalentInfo(tab, i)
            if name == want then return (rank or 0) > 0 end
        end
    end
    return false
end

function ST.RefreshTalents()
    hasTwoHandSpec = scanTwoHandSpec()
    ST.ApplyVisibility()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            hasTwoHandSpec = scanTwoHandSpec()
            -- The module can be switched off inside those half seconds, and
            -- ApplyVisibility answers from the settings rather than from whether
            -- anything is still running -- so it would happily put the bar back
            -- on screen for a tool that no longer exists.
            if not csMod.active then return end
            ST.ApplyVisibility()
        end)
    end
end

-- ---------------------------------------------------------------- live state

-- Seal buffs change on cast, not on a timer, so this runs on UNIT_AURA instead
-- of once per frame. The icon and the expiry come along in the same sweep: the
-- indicators want both, and scanning again for them every frame would be the
-- most expensive thing in the file.
function ST.RefreshSeals(event, unit)
    -- UNIT_AURA fires for every unit in the group; ours is the only one that can
    -- carry our seals, and in a raid the rest is thousands of wasted scans.
    if event == "UNIT_AURA" and unit ~= "player" then return end
    -- The simulation owns the seal pair while it runs. Letting a real aura sweep
    -- through would wipe the practised state on every buff tick in the world.
    if ST.PracticeActive() then return end
    ST.hasHeld, ST.hasTwist = false, false
    ST.heldIcon, ST.twistIcon, ST.heldExpires, ST.twistExpires = nil, nil, nil, nil
    ST.heldDuration, ST.twistDuration = nil, nil
    local heldName, twistName = ST.heldName, ST.twistName
    if not (heldName or twistName) then return end
    for i = 1, 40 do
        -- Five and six are duration and expiry. The duration is only needed by
        -- the cooldown sweep, which cannot work backwards from an expiry alone.
        local n, icon, _, _, dur, expires = UnitBuff("player", i)
        if not n then break end
        if n == heldName then
            ST.hasHeld, ST.heldIcon = true, icon
            ST.heldExpires, ST.heldDuration = expires, dur
        elseif n == twistName then
            ST.hasTwist, ST.twistIcon = true, icon
            ST.twistExpires, ST.twistDuration = expires, dur
        end
    end
    -- Two of the four visibility modes are answered by which seals are up, and
    -- this is the only place that ever changes. Cheap enough to call
    -- unconditionally: it is a handful of comparisons and one Show or Hide on
    -- an event that only fires for the player.
    ST.ApplyVisibility()
end

-- True while the practice simulation is driving the display. Every reader of
-- live state asks this rather than the practice file asking every reader to
-- change: the simulation is the exception, and the exception should be the thing
-- that carries the weight.
function ST.PracticeActive()
    local p = ST.practice
    return (p and p.active) and true or false
end

function ST.CurrentGCD()
    if ST.PracticeActive() then return ST.practice.gcd end
    local castTime = select(4, GetSpellInfo(GCD_REFERENCE))
    if not castTime or castTime <= 0 then return ST.GCD_MAX end
    local g = castTime / 1000
    if g < ST.GCD_MIN then return ST.GCD_MIN end
    if g > ST.GCD_MAX then return ST.GCD_MAX end
    return g
end

-- LATENCY, in two flavours, because the bar needs two different answers.
--
-- WORLD is the raw round trip GetNetStats reports. It is a measurement, and it
-- is what the deadzone is built from: the tail of the swing a cast physically
-- cannot cross is a property of the wire, not of anyone's opinion about it.
--
-- CALIBRATED is that measurement corrected. The naive assumption is that half
-- the round trip matters -- only the outbound leg counts, the reply costs us
-- nothing. Measured against real twists that comes out too SMALL: the round
-- trip is not the only delay between deciding and the server acting, and the
-- client adds a slice of its own on top. So the figure the padding works from
-- is (world * multiplier) + offset, and both are settings rather than
-- constants: the correction depends on the route, and a player who keeps
-- missing twists at one end of it can only fix that by moving the numbers.
--
-- Capped because a 3 s spike would otherwise shove every mark off the bar and
-- leave the display worse than useless. High enough that ordinary play, even
-- ordinary bad play, never reaches it.
local LAG_CAP_MS = 500
-- Polled once every LAG_POLL seconds rather than per frame: GetNetStats only
-- refreshes every few seconds anyway, and it is not a free call.
local LAG_POLL = 3
local lagWorld, lagCal, lagAt = 0, 0, 0

local function pollLag(d)
    local now = GetTime()
    if now - lagAt < LAG_POLL then return end
    lagAt = now
    local world = tonumber(select(4, GetNetStats())) or 0
    if world < 0 then world = 0 elseif world > LAG_CAP_MS then world = LAG_CAP_MS end
    lagWorld = world
    local cal = world * (d.lagMultiplier or 1) + (d.lagOffsetMs or 0)
    if cal < 0 then cal = 0 elseif cal > LAG_CAP_MS then cal = LAG_CAP_MS end
    lagCal = cal
end

function ST.LagWorldMs(d) pollLag(d); return lagWorld end
function ST.LagCalibratedMs(d) pollLag(d); return lagCal end

-- Drops the poll timer so the next read recalculates. Only the calibration
-- settings need this: they change the arithmetic rather than the measurement,
-- and without it a slider drag would sit there doing nothing for three seconds.
function ST.ResetLagCache() lagAt = 0 end

-- The share of the calibrated latency each dynamic padding mode takes. They
-- differ because the two boundaries are asking different questions: the GCD one
-- only has to clear a cooldown that is already running, while the twist has to
-- arrive AND resolve, so it wants a little more of the trip in front of it.
local GCD_PAD_SHARE   = 0.65
local TWIST_PAD_SHARE = 0.70

local function padSeconds(d, mode, fixedMs, share)
    if mode == "dynamic" then return ST.LagCalibratedMs(d) * share / 1000 end
    if mode == "fixed"   then return (fixedMs or 0) / 1000 end
    return 0
end

function ST.GCDPadding(d)   return padSeconds(d, d.gcdPadding,   d.gcdPaddingMs,   GCD_PAD_SHARE) end
function ST.TwistPadding(d) return padSeconds(d, d.twistPadding, d.twistPaddingMs, TWIST_PAD_SHARE) end

-- How much of the tail of the swing is out of reach, in seconds. Always
-- computed, whether or not the shading is drawn: this is a timing boundary that
-- the zones, the prompt and the hit confirmation all read, and letting a display
-- switch move it would make the bar lie about when a twist is still possible.
-- Setting the scale to 0 is the way to say "do not compensate at all".
function ST.DeadzoneSeconds(d)
    return (ST.LagWorldMs(d) / 1000) * (d.deadzoneScale or 0)
end

-- The zone boundaries, all as "seconds left before the swing", far end first.
-- The fourth value is where the swing stops being reachable, which every caller
-- knows as windowEnd.
function ST.Bounds(d, gcd)
    local twistPad = ST.TwistPadding(d)
    local windowStart = d.window + twistPad
    local lateStart   = min(d.lateWindow + twistPad, windowStart)
    return windowStart + gcd + ST.GCDPadding(d), windowStart, lateStart, ST.DeadzoneSeconds(d)
end

function ST.ZoneOf(r, dangerStart, windowStart, lateStart, windowEnd)
    if r <= 0 then return ST.Z_READY end
    if r > dangerStart then return ST.Z_FILLER end
    if r > windowStart then return ST.Z_DANGER end
    if r > lateStart   then return ST.Z_TWIST end
    if r >= windowEnd  then return ST.Z_LATE end
    return ST.Z_MISS
end

-- Seconds until the global cooldown frees up. Seals have no cooldown of their
-- own, so whatever GetSpellCooldown reports for one IS the GCD.
function ST.GCDRemaining()
    if ST.PracticeActive() then
        local left = ST.practice.gcdEnd - GetTime()
        return left > 0 and left or 0
    end
    local probe = ST.twistName or ST.heldName
    if not probe then return 0 end
    local start, dur = GetSpellCooldown(probe)
    if not start or not dur or dur <= 0 then return 0 end
    local left = (start + dur) - GetTime()
    return left > 0 and left or 0
end

-- Seconds until Judgement is off cooldown, or nil when the paladin has not
-- learned it. A GCD-length cooldown is the global one, not Judgement's own --
-- the same distinction ST.CSReady draws, and for the same reason.
function ST.JudgementRemaining()
    local name = ST.judgeName
    if not name then return nil end
    local start, dur = GetSpellCooldown(name)
    if not start or not dur or dur <= 0 then return 0 end
    if dur <= ST.GCD_MAX + 0.05 then return 0 end
    local left = (start + dur) - GetTime()
    return left > 0 and left or 0
end

-- This swing's twist is already gone: whatever is on the global cooldown right
-- now frees up later than the moment a cast could still reach the server in
-- time. Worth its own state rather than letting the bar run hopefully into the
-- green -- the answer here is a filler or stopping the attack, not a faster
-- finger. Only interesting while there IS a twist left to lose.
function ST.TwistLost(r, windowEnd)
    if not (ST.hasHeld and not ST.hasTwist) then return false end
    return (r - ST.GCDRemaining()) < windowEnd
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
ST.R_CS, ST.R_TWIST, ST.R_CS_LATE = R_CS, R_TWIST, R_CS_LATE
ST.R_AUTO_T, ST.R_AUTO_H = R_AUTO_T, R_AUTO_H

ST.ROT_ORDER = { "1/2", "2/3", "2/2/5", "2/4", "1/3", "2/5", "2/5h", "ride" }
ST.ROT_STEPS = {
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
ST.ROT_SIMPLE = ROT_SIMPLE
ST.ROT_MAX_STEPS = 5

ST.rotKey, ST.rotStep = nil, 1
ST.rotSteps = ROT_SIMPLE
ST.rotDirty = true

-- The ladder, top to bottom: the first line that fits wins. The thresholds are
-- weapon speeds in seconds, and the ones written against the global cooldown
-- move with spell haste instead of standing still.
local function pickRotation(speed, gcd)
    if not ST.csName then return nil end
    local haste = ST.GCD_MAX - gcd
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
    ST.rotStep = ST.rotStep + 1
    if ST.rotStep > #ST.rotSteps then ST.rotStep = 1 end
end

function ST.UpdateRotation(d, speed, gcd)
    -- No weapon, no speed, no sequence: the ladder would read a zero as the
    -- fastest case there is and land on the last line.
    if not speed or speed <= 0 then return end
    local key
    if d.rotation ~= "auto" and ST.ROT_STEPS[d.rotation] and ST.csName then
        key = d.rotation
    else
        key = pickRotation(speed, gcd)
    end
    if key == ST.rotKey then return end
    -- A rotation that changes mid-fight (drums, a weapon swap) starts over: the
    -- step counter of the old sequence means nothing in the new one.
    ST.rotKey   = key
    ST.rotSteps = key and ST.ROT_STEPS[key] or ROT_SIMPLE
    ST.rotStep  = 1
    ST.rotDirty = true
end

-- What the player actually did decides where in the sequence they are. Casting
-- is the only honest signal for the two spell steps; the swing tracker is the
-- one for the auto steps.
function ST.RotOnCast(spellName)
    local cur = ST.rotSteps[ST.rotStep]
    if ST.csName and spellName == ST.csName then
        if cur == R_CS or cur == R_CS_LATE then
            rotAdvance()
        else
            -- Struck out of turn: the sequence always resumes right after its
            -- Crusader Strike, wherever that leaves us.
            ST.rotStep = min(2, #ST.rotSteps)
        end
    elseif ST.twistName and spellName == ST.twistName then
        if cur == R_TWIST then rotAdvance() end
    end
end

function ST.RotOnSwing(hand)
    if hand ~= "mainhand" then return end
    local cur = ST.rotSteps[ST.rotStep]
    if cur == R_AUTO_T or cur == R_AUTO_H then rotAdvance() end
end

-- Reads as a line of spell names, built from what the client already calls
-- them. Only the word for a swing needs translating.
function ST.RotationText(key)
    local L = ns.L
    local steps = key and ST.ROT_STEPS[key] or ROT_SIMPLE
    local out
    for i = 1, #steps do
        local s = steps[i]
        local word
        if s == R_CS or s == R_CS_LATE then word = ST.csName or "?"
        elseif s == R_TWIST then word = ST.twistName or "?"
        else word = L["auto"] end
        out = out and (out .. " > " .. word) or word
    end
    return out or ""
end

-- ---------------------------------------------------------------- module glue

-- Holding the tracker keeps a COMBAT_LOG_EVENT_UNFILTERED listener alive, so a
-- paladin who turned the helper off -- or who has no seal to twist in -- should
-- not be paying for it.
-- One callback for both jobs: the swing decides whether the bar is up at all,
-- and it is also what steps the rotation past an auto.
local function onSwing(hand)
    ST.ApplyVisibility()
    ST.RotOnSwing(hand)
end

function ST.SyncTracker()
    local d = ST.DB()
    if d and d.enabled and ST.heldName and ST.twistName then
        ns:AcquireSwingTracker("sealtwist", onSwing)
    else
        ns:ReleaseSwingTracker("sealtwist")
    end
    -- The confirmation listener answers to the same conditions plus its own, so
    -- it is re-decided wherever the tracker is. Every option that can change the
    -- answer calls through here rather than reaching for the listener directly.
    ST.SyncHitLog()
end

-- A real pull ends the practice session, and it has to be an EVENT rather than
-- a check inside the simulation's own tick: that tick lives on a frame under
-- UIParent, so hiding the interface stops it -- and a pull taken with the
-- interface hidden would otherwise leave a simulated swing clock driving the bar
-- for the whole fight.
function ST.OnCombatStart()
    if ST.StopPractice then ST.StopPractice() end
    ST.ApplyVisibility()
end

function ST.OnSpellsChanged()
    -- Cheap, and the one place guaranteed to run after PLAYER_ENTERING_WORLD:
    -- a stale or missing GUID makes every combat-log line fail the source test,
    -- and the confirmation would go quiet without anything looking wrong.
    ST.RefreshPlayerGUID()
    ST.CollectSeals()
    ST.PickDefaults()
    ST.RefreshSeals()
    ST.SyncTracker()
    ST.ApplyVisibility()
end

-- Two settings were replaced rather than extended, and ApplyDefaults never
-- removes a key -- so the old ones are still sitting in every saved profile and
-- have to be read once before they are dropped.
--
--   showOOC  a switch with two answers became a dropdown with four
--   latency   one toggle used to do the job of the twist padding AND the
--             deadzone; off meant "compensate for nothing at all", which is now
--             said by a zero scale and a padding mode of none
local function migrate(d)
    if d.showOOC ~= nil then
        d.visibility = d.showOOC and "always" or "combat"
        d.showOOC = nil
    end
    if d.latency ~= nil then
        if not d.latency then
            d.twistPadding  = "none"
            d.deadzoneScale = 0
        end
        d.latency = nil
    end
    -- The attack speed used to be a switch and its own text size, both of them
    -- about the one readout left of the bar. It is now one of five things the
    -- LEFT slot can hold, and the size belongs to the slot rather than to what
    -- happens to be in it.
    if d.showSpeed ~= nil then
        if not d.showSpeed then d.leftText = "none" end
        d.showSpeed = nil
    end
    if d.speedFontSize ~= nil then
        if (d.speedFontSize or 0) > 0 then d.sideFontSize = d.speedFontSize end
        d.speedFontSize = nil
    end
end

local function onEnable()
    local d = ns:ApplyDefaults(csMod.db.sealtwist, ST.DEFAULTS)
    csMod.db.sealtwist = d
    migrate(d)
    -- An unlock that survived a reload would leave a mouse-grabbing frame on
    -- screen with nothing to explain it. Both of them: the indicators have their
    -- own mover now, and it is the easier of the two to leave switched on.
    d.unlocked = false
    d.sealPos.unlocked = false
    d.hitTextPos.unlocked = false
    d.naPos.unlocked = false

    ST.RefreshPlayerGUID()
    ST.OnSpellsChanged()
    ST.RefreshTalents()
    ST.Create()

    csMod:RegisterEvent("UNIT_AURA", ST.RefreshSeals)
    csMod:RegisterEvent("SPELLS_CHANGED", ST.OnSpellsChanged)
    csMod:RegisterEvent("PLAYER_ENTERING_WORLD", ST.OnSpellsChanged)
    -- Combat decides visibility now, and combat starts and ends without the
    -- swing tracker having anything to say about it.
    csMod:RegisterEvent("PLAYER_REGEN_DISABLED", ST.OnCombatStart)
    csMod:RegisterEvent("PLAYER_REGEN_ENABLED", ST.ApplyVisibility)
    -- Only matters while "two-handed specialization only" is on, but registering
    -- it conditionally would mean re-registering whenever that switch moves --
    -- and the handler is two table lookups on an event that fires when a talent
    -- point is spent, which is not a rate anything needs protecting from.
    csMod:RegisterEvent("CHARACTER_POINTS_CHANGED", ST.RefreshTalents)
    csMod:RegisterEvent("PLAYER_TALENT_UPDATE", ST.RefreshTalents)
    -- What the player cast is the only honest way to know where in the sequence
    -- they are; guessing from auras would count a seal that fell off as a step.
    csMod:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", ST.OnCastSucceeded)
    ST.ApplyVisibility()
end

local function onDisable()
    -- Before anything else: it owns the keyboard and a simulated swing clock,
    -- and both have to go back before the frames they drive are taken down.
    if ST.StopPractice then ST.StopPractice() end
    ns:ReleaseSwingTracker("sealtwist")
    -- Clear the three unlocks FIRST. Two of the movers are shown by their own
    -- saved flag rather than by edit mode, and a flag left set keeps a purple
    -- box on screen belonging to a module that no longer exists -- with no
    -- options page left to switch it off from.
    local d = ST.DB()
    if d then
        d.unlocked = false
        if d.sealPos then d.sealPos.unlocked = false end
        if d.hitTextPos then d.hitTextPos.unlocked = false end
        if d.naPos then d.naPos.unlocked = false end
    end
    if ST.frame then
        if ST.frame.mover then ST.frame.mover:Hide() end
        ST.frame:Hide()
    end
    if ST.HideSealMover then ST.HideSealMover() end
    if ST.HideHitText then ST.HideHitText() end
    if ST.HideNext then ST.HideNext() end
    if ST.StopDriver then ST.StopDriver() end
    -- Not SyncHitLog: the module is going away but d.enabled is still true, so
    -- asking it to re-decide would have it decide to keep listening.
    ST.StopHitLog()
end

csMod:RegisterClassTool("PALADIN", {
    onEnable   = onEnable,
    onDisable  = onDisable,
    -- Through the table rather than by value: the options tree lives in its own
    -- file, and whether that file has been read yet is a question of TOC order
    -- this call should not have to know the answer to.
    getOptions = function() return ST.GetOptions() end,
})
