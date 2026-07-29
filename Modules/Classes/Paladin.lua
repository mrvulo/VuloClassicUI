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

local DEFAULTS = {
    -- Off until asked for. Twisting is a Retribution habit, not something every
    -- paladin does, and a bar that appears in the middle of the screen on its
    -- own the first time you enter combat is not a welcome surprise. Off also
    -- means the swing tracker is never held, so nobody pays for a feature they
    -- did not ask for.
    enabled     = false,
    window      = 0.40,   -- seconds before the swing that the twist lands in
    latency     = true,   -- shift the window ahead by one trip of world latency
    heldSeal    = "",     -- resolved on first run
    twistSeal   = "",
    showBar     = true,
    showAction  = true,
    showNumbers = true,
    showOOC     = false,  -- keep the bar up between fights
    useCS       = true,
    sound       = false,
    barWidth    = 240,
    barHeight   = 22,
    fontSize    = 18,
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

local COL_IDLE   = { 0.35, 0.35, 0.42 }
local COL_ARMED  = { 0.38, 0.26, 0.62 }   -- Command is up, waiting for the window
local COL_WINDOW = { 0.20, 0.85, 0.35 }   -- twist now
local COL_DONE   = { 0.14, 0.45, 0.22 }   -- twist landed, swing carries both
local COL_LATE   = { 0.85, 0.20, 0.20 }   -- window open but pressing would not pay: no held
                                          -- seal to replace, or too late to reach the server

local frame, bar, cmdTick, twistTick, twistZone, actionFS, infoFS
local sealNames        = {}     -- ordered list of seal names this character knows
local heldName, twistName, csName
local hasHeld, hasTwist = false, false
local lastSound = 0
local wasPrompting = false

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
            if offset and numSpells then total = math.max(total, offset + numSpells) end
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
end

-- ---------------------------------------------------------------- live state

-- Seal buffs change on cast, not on a timer, so this runs on UNIT_AURA instead
-- of once per frame.
local function refreshSeals(event, unit)
    -- UNIT_AURA fires for every unit in the group; ours is the only one that can
    -- carry our seals, and in a raid the rest is thousands of wasted scans.
    if event == "UNIT_AURA" and unit ~= "player" then return end
    hasHeld, hasTwist = false, false
    if not (heldName or twistName) then return end
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then return end
        if n == heldName  then hasHeld  = true end
        if n == twistName then hasTwist = true end
    end
end

local function currentGCD()
    local castTime = select(4, GetSpellInfo(GCD_REFERENCE))
    if not castTime or castTime <= 0 then return GCD_MAX end
    local g = castTime / 1000
    if g < GCD_MIN then return GCD_MIN end
    if g > GCD_MAX then return GCD_MAX end
    return g
end

-- One trip to the server, in seconds. GetNetStats reports the ROUND trip, and
-- what matters here is only the outbound half: the cast has to arrive inside a
-- window the server keeps, and the reply coming back afterwards costs us
-- nothing. Capped because a 600 ms spike would otherwise shove the prompt into
-- the middle of the swing, where pressing is worse than not pressing.
--
-- Polled once every OFFSET_POLL seconds rather than per frame: GetNetStats only
-- refreshes every few seconds anyway, and it is not a free call.
local OFFSET_MAX  = 0.25
local OFFSET_POLL = 3
local offsetValue, offsetAt = 0, 0

local function latencyOffset(d)
    if not d.latency then return 0 end
    local now = GetTime()
    if now - offsetAt >= OFFSET_POLL then
        offsetAt = now
        local world = select(4, GetNetStats())
        local o = (tonumber(world) or 0) / 2000
        if o < 0 then o = 0 elseif o > OFFSET_MAX then o = OFFSET_MAX end
        offsetValue = o
    end
    return offsetValue
end

-- The two edges of the window, as "seconds left before the swing":
-- press at or below windowStart, and stop pressing below windowEnd, because
-- from there the cast can no longer reach the server in time.
local function twistWindow(d)
    local off = latencyOffset(d)
    return d.window + off, off
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

local function decide(d, remaining, gcd, windowStart, windowEnd)
    if not remaining then return ACTION_NONE end
    if gcdRemaining() > 0.05 then return ACTION_NONE end

    if remaining <= windowStart then
        -- Inside the window: the twist only pays off if the held seal is up to
        -- be replaced, only once, and only while the cast can still get there.
        if remaining < windowEnd then return ACTION_NONE end
        if hasHeld and not hasTwist then return ACTION_TWIST end
        return ACTION_NONE
    end

    local toWindow = remaining - windowStart
    -- Crusader Strike first when there is room for it AND the seal it wants to
    -- hit with is up: doing it later would eat the Command cast.
    if d.useCS and csName and hasTwist and csReady() and toWindow >= 2 * gcd then
        return ACTION_CS
    end
    if not hasHeld and toWindow >= gcd then return ACTION_HELD end
    return ACTION_NONE
end

-- ---------------------------------------------------------------- appearance

local function layout()
    local d = db()
    if not frame or not d then return end
    frame:SetSize(d.barWidth, d.barHeight + d.fontSize + 20)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)

    bar:SetSize(d.barWidth, d.barHeight)
    bar:SetShown(d.showBar)
    actionFS:SetFont(fontPath(), d.fontSize, "OUTLINE")
    actionFS:SetShown(d.showAction)
    infoFS:SetFont(fontPath(), math.max(9, d.fontSize - 6), "OUTLINE")
    infoFS:SetShown(d.showNumbers)
end

-- Ticks sit at a fraction of the bar measured from the RIGHT, because both
-- marks are defined as "time left before the swing", not time elapsed.
--
-- Memoised on everything that can move them: this is called once per frame, but
-- the marks only shift when the weapon speed, haste or the setting changes.
local tickSig
local function placeTicks(swingDur, gcd, windowStart, windowEnd)
    local d = db()
    if not d.showBar or not swingDur or swingDur <= 0 then return end
    local sig = swingDur .. "|" .. gcd .. "|" .. windowStart .. "|" .. windowEnd .. "|" .. d.barWidth
    if sig == tickSig then return end
    tickSig = sig
    local w = d.barWidth

    local twistFrac = windowStart / swingDur
    if twistFrac > 1 then twistFrac = 1 end
    twistTick:ClearAllPoints()
    twistTick:SetPoint("TOP",    bar, "TOPRIGHT",    -w * twistFrac, 0)
    twistTick:SetPoint("BOTTOM", bar, "BOTTOMRIGHT", -w * twistFrac, 0)

    -- The window has width, and with latency compensation its far edge is not
    -- the swing itself: shade what is left of it so the size of the target is
    -- visible, not just where it starts.
    local endFrac = windowEnd / swingDur
    if endFrac > twistFrac then endFrac = twistFrac end
    local zoneW = w * (twistFrac - endFrac)
    if zoneW < 1 then
        twistZone:Hide()
    else
        twistZone:Show()
        twistZone:ClearAllPoints()
        twistZone:SetPoint("TOPRIGHT",    bar, "TOPRIGHT",    -w * endFrac, 0)
        twistZone:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -w * endFrac, 0)
        twistZone:SetWidth(zoneW)
    end

    -- Latest moment a held-seal cast still finishes before the window opens.
    local cmdFrac = (windowStart + gcd) / swingDur
    if cmdFrac > 1 then
        cmdTick:Hide()
    else
        cmdTick:Show()
        cmdTick:ClearAllPoints()
        cmdTick:SetPoint("TOP",    bar, "TOPRIGHT",    -w * cmdFrac, 0)
        cmdTick:SetPoint("BOTTOM", bar, "BOTTOMRIGHT", -w * cmdFrac, 0)
    end
end

-- Colour wrappers, not translatable text: the spell name inside them comes from
-- the client and is already localised.
local ACTION_TEXT = {
    [ACTION_HELD]  = "|cffb388ff%s|r",
    [ACTION_TWIST] = "|cff33ff66%s|r",
    [ACTION_CS]    = "|cffffcc33%s|r",
}

local function onUpdate()
    local d = db()
    if not d then return end

    local fake = d.unlocked or ns:IsMoverEditMode()
    local remaining, swingDur

    if fake then
        -- A fake 2.6 s swing so the bar and both marks are visible while placing
        -- the frame out of combat.
        swingDur = 2.6
        remaining = swingDur - (GetTime() % swingDur)
    else
        local _, dur, active = ns:GetSwing("mainhand")
        if active and dur > 0 then
            swingDur = dur
            remaining = ns:SwingRemaining("mainhand")
        end
    end

    local gcd = currentGCD()
    local windowStart, windowEnd = twistWindow(d)

    if not remaining then
        -- Shown but not swinging: an empty bar rather than a stale one, so the
        -- frame reads as "waiting" instead of showing a swing that ended.
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetStatusBarColor(COL_IDLE[1], COL_IDLE[2], COL_IDLE[3])
        actionFS:SetText("")
        if d.showNumbers then infoFS:SetText(L["waiting for a swing"]) end
        -- Leaving this set would swallow the first beep of the next fight.
        wasPrompting = false
        return
    end

    placeTicks(swingDur, gcd, windowStart, windowEnd)
    bar:SetMinMaxValues(0, swingDur)
    bar:SetValue(swingDur - remaining)

    local inWindow = remaining <= windowStart
    local action = fake and ACTION_TWIST or decide(d, remaining, gcd, windowStart, windowEnd)

    local c
    if inWindow and not fake then
        if hasTwist then
            c = COL_DONE          -- the twist is in; this swing carries both
        elseif not hasHeld then
            c = COL_LATE          -- no held seal to twist out of: nothing to do
        elseif remaining < windowEnd then
            c = COL_LATE          -- too late to reach the server before the swing
        else
            c = COL_WINDOW        -- cast it now
        end
    elseif inWindow then
        c = COL_WINDOW
    elseif hasHeld or fake then
        c = COL_ARMED
    else
        c = COL_IDLE
    end
    bar:SetStatusBarColor(c[1], c[2], c[3])

    if d.showAction then
        local label
        if action == ACTION_TWIST then
            label = format(ACTION_TEXT[ACTION_TWIST], twistName or L["Twist"])
        elseif action == ACTION_HELD then
            label = format(ACTION_TEXT[ACTION_HELD], heldName or L["Hold seal"])
        elseif action == ACTION_CS then
            label = format(ACTION_TEXT[ACTION_CS], csName or "")
        else
            label = ""
        end
        actionFS:SetText(label)
    end

    if d.showNumbers then
        -- No bare "|" as a separator: it opens an escape sequence for the font
        -- renderer and eats the character after it.
        local line = format(L["%.2fs left  -  swing %.2fs  -  GCD %.2fs"], remaining, swingDur, gcd)
        if windowEnd > 0 then
            line = line .. format(L["  -  lag %.0fms"], windowEnd * 2000)
        end
        infoFS:SetText(line)
    end

    -- On the prompt, not on the window: the window opens on every swing, and a
    -- beep that fires while the twist is already up -- or while there is no held
    -- seal to twist out of -- trains the player to ignore it.
    local prompt = (action == ACTION_TWIST)
    if d.sound and prompt and not wasPrompting and not fake then
        local t = GetTime()
        if t - lastSound > 0.25 then
            lastSound = t
            PlaySoundFile(WINDOW_SOUND, "Master")
        end
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
    bar:SetPoint("TOP", frame, "TOP", 0, 0)
    bar:SetStatusBarTexture(BAR_TEX)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture(BAR_TEX)
    bg:SetVertexColor(0.08, 0.08, 0.10, 0.9)

    -- ARTWORK, above the fill but below the two marks: it is a backdrop for the
    -- window, not a line in it.
    twistZone = bar:CreateTexture(nil, "ARTWORK")
    twistZone:SetTexture(BAR_TEX)
    twistZone:SetVertexColor(0.20, 0.85, 0.35, 0.18)

    cmdTick = bar:CreateTexture(nil, "OVERLAY")
    cmdTick:SetTexture(BAR_TEX)
    cmdTick:SetVertexColor(0.70, 0.50, 1.00, 0.95)
    cmdTick:SetWidth(2)

    twistTick = bar:CreateTexture(nil, "OVERLAY")
    twistTick:SetTexture(BAR_TEX)
    twistTick:SetVertexColor(0.25, 1.00, 0.45, 0.95)
    twistTick:SetWidth(2)

    actionFS = frame:CreateFontString(nil, "OVERLAY")
    actionFS:SetPoint("TOP", bar, "BOTTOM", 0, -4)

    infoFS = frame:CreateFontString(nil, "OVERLAY")
    infoFS:SetPoint("TOP", actionFS, "BOTTOM", 0, -2)
    infoFS:SetTextColor(0.65, 0.65, 0.70)

    frame.mover = ns:CreateMover(frame, {
        key    = "sealtwist",
        label  = L["|cffffffffSEAL TWIST|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = d,
        width  = math.max(d.barWidth + 40, 200),
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
local function syncTracker()
    local d = db()
    if d and d.enabled and heldName and twistName then
        ns:AcquireSwingTracker("sealtwist", applyVisibility)
    else
        ns:ReleaseSwingTracker("sealtwist")
    end
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

local function getOptions()
    local items = {}

    table.insert(items, { type = "header", text = L["Seal Twist"] })
    table.insert(items, { type = "desc", text = L["|cffaaaaaaHold Seal of Command, then cast the second seal in the last fraction of a second before your auto-attack: that swing carries both. The bar counts down to the swing, the |cff33ff66green zone|r is the twist window and the |cffb388ffpurple mark|r is the last moment a cast of the held seal still fits in front of it. Below level 64 the second seal is Righteousness; Blood and the Martyr replace it from there.|r"] })

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
        desc = L["Only Seal of Command and Seal of Righteousness work here: they are the two whose effect still lands on the swing that replaces them."],
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
        desc = L["How far before the swing the second seal has to land. 0.40 is the usual figure; raise it if your latency makes you miss the window."],
        get = function() return d.window end,
        set = function(_, v) d.window = v end })
    table.insert(items, { type = "toggle", label = L["Compensate for latency"],
        desc = L["Opens the window earlier by one trip to the server, and closes it once the cast can no longer arrive before the swing. Uses your measured world latency, capped at 250 ms."],
        get = function() return d.latency end,
        set = function(_, v) d.latency = v and true or false end })
    table.insert(items, { type = "toggle", label = L["Suggest Crusader Strike"],
        desc = L["Prompts Crusader Strike when it is ready and there is room for it plus the Command cast before the window opens."],
        get = function() return d.useCS end,
        set = function(_, v) d.useCS = v and true or false end })
    table.insert(items, { type = "toggle", label = L["Sound when the window opens"],
        get = function() return d.sound end,
        set = function(_, v) d.sound = v and true or false end })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Display"] })
    table.insert(items, { type = "toggle", label = L["Show swing bar"],
        get = function() return d.showBar end,
        set = function(_, v) d.showBar = v and true or false; layout() end })
    table.insert(items, { type = "toggle", label = L["Show next action"],
        get = function() return d.showAction end,
        set = function(_, v) d.showAction = v and true or false; layout() end })
    table.insert(items, { type = "toggle", label = L["Show numbers"],
        get = function() return d.showNumbers end,
        set = function(_, v) d.showNumbers = v and true or false; layout() end })
    table.insert(items, { type = "toggle", label = L["Show out of combat"],
        desc = L["Normally the bar is only up in combat. Switch this on to keep it on screen, which is the easier way to practise the timing on a dummy."],
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

    return items
end

csMod:RegisterClassTool("PALADIN", {
    onEnable   = onEnable,
    onDisable  = onDisable,
    getOptions = getOptions,
})
