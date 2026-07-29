-- Paladin seal twist: did the twist land, and the feedback that says so.
--
-- The one thing on the whole helper that has to be TRUSTED. A cue that fires
-- when the twist did not land is worse than no cue at all: it trains the wrong
-- timing, and the player has no way of knowing which of the two they are being
-- taught. So the confirmation is kept apart from everything that merely
-- predicts, and it is the only thing in this file that may make a noise.
--
-- WHY THIS IS NOT DONE ON THE CAST.
--
-- It used to be. UNIT_SPELLCAST_SUCCEEDED said the second seal went out, the
-- swing clock said the cast landed inside the window, and the cue fired. Every
-- part of that is true and the conclusion is still a GUESS: "the cast reached
-- the server inside the window" is not the same claim as "the swing carried
-- both seals". The server can disagree -- a swing that resolved a hair earlier
-- than the client drew it, a cast that arrived on the far side of the window, a
-- seal that fell off between the two. The player hears a confirmation and
-- learns a timing that does not work.
--
-- So the answer comes from the combat log, which is the server talking, in two
-- stages:
--
--   1. ATTEMPT. A SWING_DAMAGE or SWING_MISSED from the player, with both seal
--      auras up. That is a swing that COULD have carried the twist.
--   2. LANDED. Within CONFIRM_WINDOW of that swing, a SPELL_DAMAGE from the
--      player whose spell is the held seal. That is the held seal's effect
--      resolving on the swing that replaced it, which is the twist, and it is
--      the only evidence of it that exists.
--
-- Without stage 2 nothing fires. Not a quieter sound, not a different colour --
-- nothing. A confirmation that is right most of the time is a confirmation
-- nobody can practise against.
--
-- AND STAGE 1 COUNTS ITS OWN AURAS, out of the same combat log.
--
-- The obvious thing is to ask the display's aura state -- ST.hasHeld and
-- ST.hasTwist are right there, filled on UNIT_AURA. That is a second event
-- stream, and whether UNIT_AURA for a seal is dispatched before or after the
-- combat-log line for the swing it belongs to is contracted NOWHERE. On the
-- swing where it arrives late, the twist that landed says nothing; on the swing
-- where it arrives early, one that did not land says something. Both are the
-- failure this whole file exists to avoid, and the second one is worse.
--
-- So the seal auras are tracked from SPELL_AURA_APPLIED / _REFRESH / _REMOVED
-- in THIS stream, seeded once when the listener starts. Ordering inside one
-- stream is guaranteed, so the count at the swing line is the count the server
-- had at the swing.
--
-- See the header of Paladin.lua for why the helper is split at all.
local _, ns = ...
local L = ns.L

local ST = ns.SealTwist
if not ST then return end

local GetTime, GetSpellInfo, UnitGUID = GetTime, GetSpellInfo, UnitGUID
local CLGetInfo = CombatLogGetCurrentEventInfo

-- How long after the swing the seal's damage may still arrive. Generous
-- compared to the round trip it is really bounded by: a late confirmation is a
-- cue a fraction of a second behind the swing, while a short window is a twist
-- that landed and said nothing.
local CONFIRM_WINDOW = 0.5

-- The held seal's damage effect carries the seal's own NAME, which is why the
-- name comparison is the primary test: it comes from GetSpellInfo on the seal
-- the player configured, so it is right in every language and at every rank
-- without this file knowing a single ID.
--
-- These are the fallback, for a rank or a client where the damage line does not
-- carry the aura's name. A whitelist, never a substitute: an ID that drifts
-- between builds would silently stop confirming, and the name test is what
-- keeps that from mattering.
local PROC_IDS = {
    [20424] = true,
    [20944] = true, [20945] = true, [20946] = true, [20947] = true,
    [29385] = true,
}

-- Cues for the hit confirmation. Only sounds this addon already plays
-- elsewhere are listed as built-ins -- an unverified file id fails SILENTLY,
-- which is the worst possible outcome for a setting whose entire job is to make
-- a noise. Anything sharper than these comes from shared media: other addons
-- register their sound packs there, and picking one of those is how you get a
-- crack rather than a chime without this addon shipping audio of its own.
ST.HIT_SOUNDS = {
    { key = "sniper", label = "Sniper",       media = "Sniper" },
    { key = "rifle",  label = "Rifle",        media = "Rifle"  },
    { key = "chime",  label = "Chime",        file  = ST.WINDOW_SOUND },
    { key = "alarm",  label = "Raid warning", kit   = "RAID_WARNING", fallback = 8959 },
    { key = "ready",  label = "Ready check",  kit   = "READY_CHECK",  fallback = 8960 },
    { key = "menu",   label = "Click",        kit   = "IG_MAINMENU_OPEN" },
    { key = "levelup", label = "Level up",    kit   = "LEVELUP" },
    { key = "quest",  label = "Quest complete", kit = "IG_QUEST_LIST_COMPLETE" },
    { key = "bonus",  label = "Bonus objective", kit = "UI_SCENARIO_STAGE_END" },
    { key = "map",    label = "Map ping",     kit   = "MAP_PING" },
}
ST.LSM_PREFIX = "lsm:"

-- Master or SFX. Master ignores the sound-effects slider, which is what a
-- confirmation wants -- it is not part of the fight, it is feedback about it.
local function channel(d)
    return (d.hitChannel == "SFX") and "SFX" or "Master"
end

function ST.PlayHitSound(choice, d)
    if not choice or choice == "" then return end
    d = d or ST.DB()
    if not d then return end
    local ch = channel(d)
    local name = choice:match("^" .. ST.LSM_PREFIX .. "(.+)$")
    if name then
        local LSM = ns.LSM
        local hash = LSM and LSM:HashTable("sound")
        local path = hash and hash[name]
        if path and path ~= "" then pcall(PlaySoundFile, path, ch) end
        return
    end
    for _, s in ipairs(ST.HIT_SOUNDS) do
        if s.key == choice then
            if s.media then
                -- Straight to the file, not through shared media: a global
                -- sound override in another addon would otherwise be able to
                -- swap the cue underneath us.
                local path = ns.MediaSound and ns.MediaSound(s.media)
                if path then pcall(PlaySoundFile, path, ch) end
            elseif s.file then
                pcall(PlaySoundFile, s.file, ch)
            else
                local id = (SOUNDKIT and SOUNDKIT[s.kit]) or s.fallback
                if id then pcall(PlaySound, id, ch) end
            end
            return
        end
    end
end

-- ---------------------------------------------------------------- the glow
--
-- Built here rather than pulled in: a glow is four textures and a fade, and
-- bundling a library for it would add a file, a load order and a second copy of
-- something half the addons on the machine already ship.
--
-- Two shapes, because a bar is not a button. The pixel border traces the bar's
-- own outline at any width. The autocast ring is the client's own overlay cut
-- into its four QUADRANTS and pinned to the four corners -- stretching that
-- texture across a 240 px bar in one piece would smear a circle into an
-- ellipse, while four corners at a fixed size read as a ring around the bar
-- however wide it gets.
local AUTOCAST_TEX = "Interface\\Buttons\\UI-AutoCastableOverlay"
local AUTOCAST_QUAD = {
    { 0.0, 0.5, 0.0, 0.5, "TOPLEFT"     },
    { 0.5, 1.0, 0.0, 0.5, "TOPRIGHT"    },
    { 0.0, 0.5, 0.5, 1.0, "BOTTOMLEFT"  },
    { 0.5, 1.0, 0.5, 1.0, "BOTTOMRIGHT" },
}

local glowFrame
local glowEdges, glowCorners = {}, {}
local glowLeft = 0

local function glowUpdate(self, elapsed)
    glowLeft = glowLeft - (elapsed or 0)
    local d = ST.DB()
    local total = (d and d.hitGlowDuration) or 0.4
    if glowLeft <= 0 or total <= 0 then
        self:SetScript("OnUpdate", nil)
        self:Hide()
        return
    end
    -- Fades rather than blinking off. The eye reads a hard cut as a rendering
    -- fault and a fade as an event that happened, and this one is meant to be
    -- caught out of the corner of it.
    self:SetAlpha(glowLeft / total)
end

local function showGlow(d)
    if not glowFrame then return end
    local r, g, b = ST.Color(d.hitGlowColor, 0.2, 1, 0.35)
    local pixel = (d.hitGlowType ~= "autocast")

    for _, t in ipairs(glowEdges) do
        t:SetShown(pixel)
        if pixel then t:SetColorTexture(r, g, b, 1) end
    end
    for _, t in ipairs(glowCorners) do
        t:SetShown(not pixel)
        if not pixel then t:SetVertexColor(r, g, b) end
    end

    if pixel then
        local w = 2
        local bar = ST.bar
        glowEdges[1]:ClearAllPoints()
        glowEdges[1]:SetPoint("BOTTOMLEFT",  bar, "TOPLEFT",     -w, 0)
        glowEdges[1]:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT",     w, 0)
        glowEdges[1]:SetHeight(w)
        glowEdges[2]:ClearAllPoints()
        glowEdges[2]:SetPoint("TOPLEFT",     bar, "BOTTOMLEFT",  -w, 0)
        glowEdges[2]:SetPoint("TOPRIGHT",    bar, "BOTTOMRIGHT",  w, 0)
        glowEdges[2]:SetHeight(w)
        glowEdges[3]:ClearAllPoints()
        glowEdges[3]:SetPoint("TOPRIGHT",    bar, "TOPLEFT",      0, 0)
        glowEdges[3]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT",   0, 0)
        glowEdges[3]:SetWidth(w)
        glowEdges[4]:ClearAllPoints()
        glowEdges[4]:SetPoint("TOPLEFT",     bar, "TOPRIGHT",     0, 0)
        glowEdges[4]:SetPoint("BOTTOMLEFT",  bar, "BOTTOMRIGHT",  0, 0)
        glowEdges[4]:SetWidth(w)
    else
        local size = math.max(12, (d.barHeight or 22))
        for i, t in ipairs(glowCorners) do
            t:SetSize(size, size)
            t:ClearAllPoints()
            local corner = AUTOCAST_QUAD[i][5]
            t:SetPoint(corner, ST.bar, corner, 0, 0)
        end
    end

    glowLeft = d.hitGlowDuration or 0.4
    -- Levelled here, not at creation. The frame's own level is a SETTING, and it
    -- is applied by the layout pass that runs after this frame was built -- a
    -- level computed once at creation leaves the glow underneath the bar it is
    -- supposed to be glowing around.
    glowFrame:SetFrameLevel((ST.frame:GetFrameLevel() or 1) + 8)
    glowFrame:SetAlpha(1)
    glowFrame:Show()
    glowFrame:SetScript("OnUpdate", glowUpdate)
end

-- ---------------------------------------------------------------- the text

local textFrame
local textLeft = 0

local function textUpdate(self, elapsed)
    textLeft = textLeft - (elapsed or 0)
    local d = ST.DB()
    -- Unlocked outranks the timer: the whole point of the mover is to see the
    -- line while placing it, and a line that fades after a second and a half is
    -- one you cannot aim at.
    if d and ((d.hitTextPos and d.hitTextPos.unlocked) or ns:IsMoverEditMode()) then
        self:SetAlpha(1)
        return
    end
    local total = (d and d.hitTextDuration) or 1.5
    if textLeft <= 0 or total <= 0 then
        self:SetScript("OnUpdate", nil)
        self.fs:SetText("")
        return
    end
    -- Solid for the first half, fading through the second. A line that starts
    -- fading immediately reads as already leaving.
    self:SetAlpha(math.min(1, (textLeft / total) * 2))
end

function ST.ApplyHitTextLook()
    local d = ST.DB()
    if not (textFrame and d) then return end
    local path = ns.MediaFont(d.hitTextFont, ST.FontPath())
    textFrame.fs:SetFont(path, d.hitTextSize or 24, d.hitTextOutline or "OUTLINE")
    textFrame.fs:SetTextColor(ST.Color(d.hitTextColor, 0.2, 1, 0.35))
    local p = d.hitTextPos or {}
    textFrame:ClearAllPoints()
    textFrame:SetPoint("CENTER", UIParent, "CENTER", p.x or 0, p.y or 200)
end

local function showText(d)
    if not textFrame then return end
    textFrame.fs:SetText(L["Twist!"])
    textLeft = d.hitTextDuration or 1.5
    textFrame:SetAlpha(1)
    textFrame:SetScript("OnUpdate", textUpdate)
end

-- Called when the whole tool is switched off. The text frame is parented to
-- UIParent, so nothing else takes it down with the bar -- and its mover is shown
-- by a saved flag rather than by edit mode, which means a box left up here has
-- no options page left to switch it off from.
function ST.HideHitText()
    if not textFrame then return end
    textFrame.mover:Hide()
    textFrame:SetScript("OnUpdate", nil)
    textFrame.fs:SetText("")
end

function ST.SetHitTextUnlocked(state)
    local d = ST.DB()
    ST.Create()
    d.hitTextPos.unlocked = state and true or false
    if d.hitTextPos.unlocked then
        ST.ApplyHitTextLook()
        showText(d)
        textFrame.mover:Show()
        ns:Print(L["Twist text mover active. |cff9b6cffDrag the purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Test' again to finish."])
    else
        textFrame.mover:Hide()
        textFrame.fs:SetText("")
        textFrame:SetScript("OnUpdate", nil)
        ns:Print(L["Twist text mover disabled."])
    end
end

-- Built from ST.Create, so this file never has to guess whether the bar exists.
function ST.CreateHitVisuals()
    if glowFrame then return end
    local d = ST.DB()

    glowFrame = CreateFrame("Frame", nil, ST.frame)
    glowFrame:SetAllPoints(ST.bar)
    glowFrame:SetFrameLevel((ST.frame:GetFrameLevel() or 1) + 8)
    glowFrame:Hide()
    for i = 1, 4 do
        glowEdges[i] = glowFrame:CreateTexture(nil, "OVERLAY")
        glowEdges[i]:Hide()
        local q = AUTOCAST_QUAD[i]
        local c = glowFrame:CreateTexture(nil, "OVERLAY")
        c:SetTexture(AUTOCAST_TEX)
        c:SetTexCoord(q[1], q[2], q[3], q[4])
        c:SetBlendMode("ADD")
        c:Hide()
        glowCorners[i] = c
    end

    textFrame = CreateFrame("Frame", nil, UIParent)
    textFrame:SetSize(200, 40)
    textFrame:SetFrameStrata("HIGH")
    textFrame.fs = textFrame:CreateFontString(nil, "OVERLAY")
    textFrame.fs:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    textFrame.mover = ns:CreateMover(textFrame, {
        key    = "sealtwisthit",
        label  = L["|cffffffffTWIST TEXT|r"],
        db     = d.hitTextPos,
        width  = 200,
        height = 44,
        -- The anchor is ours, so a global reset has to come back through it.
        applyPos = function() ST.ApplyHitTextLook() end,
        -- Without a preview the box sits empty in global edit mode: the line is
        -- only ever drawn by an event that has not happened.
        editPreview = function(edit)
            if edit then
                ST.ApplyHitTextLook()
                textFrame.fs:SetText(L["Twist!"])
                textFrame:SetAlpha(1)
                return
            end
            -- Leaving edit mode clears the preview -- unless the row's own
            -- unlock is holding the box up, in which case it is still being
            -- placed and the line is what it is being placed by.
            local cur = ST.DB()
            if not (cur and cur.hitTextPos and cur.hitTextPos.unlocked) then
                textFrame.fs:SetText("")
            end
        end,
    })
    ST.ApplyHitTextLook()
end

-- ---------------------------------------------------------------- confirmation

-- Everything the confirmation fires, in one place, so "did it land" and "what
-- happens then" stay separable -- the practice mode reuses this and must not
-- have to know how a glow is built.
function ST.OnTwistLanded()
    local d = ST.DB()
    if not d then return end
    if d.soundHit then ST.PlayHitSound(d.hitSound, d) end
    if d.hitGlow and ST.bar then showGlow(d) end
    if d.hitText then ST.ApplyHitTextLook(); showText(d) end
end

local logFrame
local playerGUID
local attemptAt
-- The two seal auras as the COMBAT LOG sees them. Deliberately not the same
-- pair the bar draws -- see the header.
local logHeld, logTwist = false, false

local function onCombatLog()
    local _, sub, _, srcGUID = CLGetInfo()
    if srcGUID ~= playerGUID then return end

    if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then
        -- STAGE 1. Both seals up on a swing is the only state a twist can have
        -- been in. Latched with a timestamp rather than a flag, because the
        -- second seal is replacing the first right about now and asking again
        -- when the damage line arrives would answer no.
        if logHeld and logTwist then attemptAt = GetTime() end
        return
    end

    if sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH"
        or sub == "SPELL_AURA_REMOVED" then
        -- Our own seals on ourselves. A seal another paladin put on themselves
        -- passes the source test only for them, but a blessing WE cast on
        -- somebody else would pass it here -- hence the destination check.
        local _, _, _, _, _, _, _, destGUID = CLGetInfo()
        if destGUID ~= playerGUID then return end
        local _, spellName = select(12, CLGetInfo())
        local on = (sub ~= "SPELL_AURA_REMOVED")
        if spellName == ST.heldName then logHeld = on
        elseif spellName == ST.twistName then logTwist = on end
        return
    end

    if sub ~= "SPELL_DAMAGE" then return end
    if not attemptAt or (GetTime() - attemptAt) > CONFIRM_WINDOW then return end

    local spellId, spellName = select(12, CLGetInfo())
    if not ((ST.heldName and spellName == ST.heldName) or PROC_IDS[spellId]) then return end

    -- STAGE 2. One confirmation per attempt: a seal can tick more than once
    -- inside the window, and a cue per tick would turn a confirmation into a
    -- rattle.
    attemptAt = nil
    ST.OnTwistLanded()
end

-- Seeds the combat-log aura pair from a real scan. Needed exactly once per
-- listener start: a seal cast BEFORE the listener existed produced no line for
-- it, and from then on the log is complete because a seal can only arrive or
-- leave through one.
function ST.SeedHitAuras()
    logHeld, logTwist = ST.hasHeld or false, ST.hasTwist or false
end

-- Any feedback at all is enough to need the listener; none of them means the
-- combat log is not parsed. COMBAT_LOG_EVENT_UNFILTERED is the busiest event in
-- the game and a raid fires it thousands of times a fight, so a paladin who
-- wants no confirmation should not be paying to compute one.
function ST.StopHitLog()
    if logFrame then logFrame:UnregisterAllEvents() end
    attemptAt = nil
    logHeld, logTwist = false, false
end

function ST.SyncHitLog()
    local d = ST.DB()
    local want = d and d.enabled and ST.heldName and ST.twistName
        and (d.soundHit or d.hitGlow or d.hitText)

    if not want then ST.StopHitLog(); return end
    if not logFrame then
        logFrame = CreateFrame("Frame")
        logFrame:SetScript("OnEvent", onCombatLog)
    end
    playerGUID = playerGUID or UnitGUID("player")
    -- Re-seeded on every sync, not only on the first: a seal choice can change
    -- under a listener that is already running, and the pair is keyed by name.
    ST.SeedHitAuras()
    logFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

-- The GUID is not known at login time, so it is refreshed on the event that
-- guarantees it -- without it every combat-log line fails the source test and
-- nothing is ever confirmed.
function ST.RefreshPlayerGUID()
    playerGUID = UnitGUID("player")
end

-- The cast is still worth listening to, but only for the rotation: what the
-- player pressed is the honest signal for where in the sequence they are.
-- It no longer decides anything about whether the twist landed.
function ST.OnCastSucceeded(_, unit, _, spellID)
    if unit ~= "player" then return end
    local d = ST.DB()
    if not d then return end
    if not d.showRotation then return end
    local name = spellID and GetSpellInfo(spellID)
    if name then ST.RotOnCast(name) end
end
