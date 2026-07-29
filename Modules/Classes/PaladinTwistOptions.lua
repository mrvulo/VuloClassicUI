-- Paladin seal twist: the options tree.
--
-- Kept apart from the feature for the ordinary reason -- it is by far the
-- longest part and it does no work at runtime -- and for one specific to this
-- client: Lua 5.1 allows 200 top-level locals per chunk, and an options tree
-- that grows a local per dropdown source is what eats that budget first.
--
-- See the header of Paladin.lua for why the helper is split at all.
local _, ns = ...
local L = ns.L

local ST = ns.SealTwist
if not ST then return end

local function sealValues()
    local out = {}
    for _, n in ipairs(ST.sealNames) do out[#out + 1] = { value = n, text = n } end
    if #out == 0 then out[1] = { value = "", text = L["(no seals learned)"] } end
    return out
end

-- The built-ins first, then whatever sound packs other addons have registered
-- with shared media -- that list is where a sharper cue comes from.
local function hitSoundValues()
    local out = {}
    for _, s in ipairs(ST.HIT_SOUNDS) do
        out[#out + 1] = { value = s.key, text = L[s.label] }
    end
    local LSM = ns.LSM
    if LSM then
        for _, n in ipairs(LSM:List("sound") or {}) do
            if n ~= "None" then out[#out + 1] = { value = ST.LSM_PREFIX .. n, text = n } end
        end
    end
    return out
end

-- Shared by both padding rows: the two boundaries differ in how much of the
-- latency they take, not in what the choice means.
local function paddingValues()
    return {
        { value = "none",    text = L["None"] },
        { value = "dynamic", text = L["Dynamic (follows latency)"] },
        { value = "fixed",   text = L["Fixed"] },
    }
end

local function visibilityValues()
    return {
        { value = "always",       text = L["Always"] },
        { value = "combat",       text = L["In combat"] },
        { value = "seal",         text = L["Seal active"] },
        { value = "combatOrSeal", text = L["In combat or seal active"] },
    }
end

local function channelValues()
    return {
        { value = "Master", text = L["Master"] },
        { value = "SFX",    text = L["Sound effects"] },
    }
end

local function glowTypeValues()
    return {
        { value = "pixel",    text = L["Pixel border"] },
        { value = "autocast", text = L["Autocast ring"] },
    }
end

local function outlineValues()
    return {
        { value = "",             text = L["None"] },
        { value = "OUTLINE",      text = L["Outline"] },
        { value = "THICKOUTLINE", text = L["Thick outline"] },
    }
end

local function borderModeValues()
    return {
        { value = "none",    text = L["None"] },
        { value = "solid",   text = L["Solid"] },
        { value = "texture", text = L["Texture"] },
    }
end

-- The client's own names, not translated: a strata is an identifier the player
-- meets in every addon that has this setting, and localising it would make two
-- addons disagree about what the same layer is called.
local function strataValues()
    local out = {}
    for _, s in ipairs({ "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }) do
        out[#out + 1] = { value = s, text = s }
    end
    return out
end

local function sideTextValues()
    return {
        { value = "attackSpeed", text = L["Attack speed"] },
        { value = "swingTimer",  text = L["Swing timer"] },
        { value = "latency",     text = L["Latency (ms)"] },
        { value = "gcd",         text = L["Global cooldown left"] },
        { value = "none",        text = L["Nothing"] },
    }
end

local function colorSourceValues()
    return {
        { value = "zones", text = L["The zone the swing is in"] },
        { value = "seal",  text = L["The seal you are carrying"] },
    }
end

-- One row per seal colour, built from a list so the eight stay in one shape.
-- Blood and the Martyr share an entry: same seal, two factions.
local SEAL_COLOR_ROWS = {
    { key = "command",       label = "Seal of Command" },
    { key = "righteousness", label = "Seal of Righteousness" },
    { key = "blood",         label = "Seal of Blood / the Martyr" },
    { key = "vengeance",     label = "Seal of Vengeance" },
    { key = "crusader",      label = "Seal of the Crusader" },
    { key = "justice",       label = "Seal of Justice" },
    { key = "light",         label = "Seal of Light" },
    { key = "wisdom",        label = "Seal of Wisdom" },
}

-- Each entry carries its own sequence in the text: the fraction alone means
-- nothing to somebody meeting it for the first time.
local function rotationValues()
    local out = { { value = "auto", text = L["Automatic"] } }
    if not ST.csName then return out end
    for _, key in ipairs(ST.ROT_ORDER) do
        out[#out + 1] = { value = key, text = key .. "  -  " .. ST.RotationText(key) }
    end
    return out
end

function ST.GetOptions()
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
    local d = ST.DB()
    if not d then
        table.insert(items, { type = "desc", text = L["|cffff8800Switch the Class Specific module on to use this.|r"] })
        return items
    end

    if not ST.heldName then
        table.insert(items, { type = "desc", text = L["|cffff8800No seal to twist out of. Only Seal of Command and Seal of Righteousness carry over to a swing after being replaced, so one of the two has to be learned.|r"] })
    elseif not ST.twistName then
        table.insert(items, { type = "desc", text = L["|cffff8800Only one seal learned. A second one is needed to twist into.|r"] })
    elseif not ST.CanHold(d.heldSeal) then
        table.insert(items, { type = "desc", text = L["|cffff8800The seal you hold cannot be twisted out of. Only Seal of Command and Seal of Righteousness carry over to the swing that replaces them.|r"] })
    end

    table.insert(items, { type = "toggle", label = L["Enable seal twist helper"],
        get = function() return d.enabled end,
        set = function(_, v) d.enabled = v and true or false; ST.SyncTracker(); ST.ApplyVisibility() end })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", label = L["Unlock / Test"], width = 130,
              onClick = function() ST.SetUnlocked(not d.unlocked) end },
            { type = "button", label = L["Center Position"], width = 150,
              onClick = function() d.x, d.y = 0, -180; ST.Layout() end },
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
            ST.heldName = (v ~= "") and v or nil
            -- One seal in both roles is a no-op the player cannot see going
            -- wrong, so the other role gives way immediately.
            if v ~= "" and d.twistSeal == v then
                d.twistSeal, ST.twistName = "", nil
            end
            -- Unconditional. PickDefaults is also what re-resolves the ICONS,
            -- and the rotation row memoises on the texture it was handed -- a
            -- seal changed without it keeps drawing the old seal's picture until
            -- the next SPELLS_CHANGED.
            ST.PickDefaults()
            ST.RefreshSeals(); ST.SyncTracker(); ST.ApplyVisibility()
        end })
    table.insert(items, { type = "dropdown", label = L["Seal you twist in"], fullWidth = true,
        values = sealValues(),
        get = function() return d.twistSeal end,
        set = function(_, v)
            d.twistSeal = v
            ST.twistName = (v ~= "") and v or nil
            if v ~= "" and d.heldSeal == v then
                d.heldSeal, ST.heldName = "", nil
            end
            -- Unconditional, for the icons -- see the held-seal setter above.
            ST.PickDefaults()
            ST.RefreshSeals(); ST.SyncTracker(); ST.ApplyVisibility()
        end })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Timing"] })
    table.insert(items, { type = "slider", label = L["Twist window (seconds)"],
        min = 0.20, max = 0.70, step = 0.01, decimals = 2,
        tooltip = L["How far before the swing the second seal has to land. 0.40 is the usual figure; raise it if your latency makes you miss the window."],
        get = function() return d.window end,
        set = function(_, v) d.window = v; ST.Layout() end })
    table.insert(items, { type = "slider", label = L["Late twist window (seconds)"],
        min = 0.05, max = 0.40, step = 0.01, decimals = 2,
        tooltip = L["The tail of the twist window, marked separately. Twisting that late still leaves room for a judgement in front of the seal. Set it as long as the twist window to hide the mark."],
        get = function() return d.lateWindow end,
        set = function(_, v) d.lateWindow = v; ST.Layout() end })
    table.insert(items, { type = "dropdown", label = L["Twist window padding"], fullWidth = true,
        tooltip = L["Pulls the twist window earlier so the cast still reaches the server inside it. Dynamic follows your calibrated latency; fixed is a number you choose yourself."],
        values = paddingValues(),
        get = function() return d.twistPadding end,
        set = function(_, v) d.twistPadding = v; ST.Layout() end,
        subOptions = {
            { type = "slider", label = L["Fixed twist padding (ms)"], min = 0, max = 300, step = 5,
              tooltip = L["Only used while the padding mode is set to fixed."],
              get = function() return d.twistPaddingMs end,
              set = function(_, v) d.twistPaddingMs = v; ST.Layout() end },
        } })
    table.insert(items, { type = "slider", label = L["Head start for the prompt (ms)"],
        min = 0, max = 300, step = 10,
        tooltip = L["Shows the twist prompt and plays its cue this far before the window actually opens, so there is time to see it and press. The colours on the bar stay exact."],
        get = function() return d.reaction end,
        set = function(_, v) d.reaction = v end })
    table.insert(items, { type = "toggle", label = L["Suggest Crusader Strike"],
        tooltip = L["Prompts Crusader Strike when it is ready and there is room for it plus the Command cast before the window opens."],
        get = function() return d.useCS end,
        set = function(_, v) d.useCS = v and true or false end,
        subOptions = {
            { type = "slider", label = L["Longest Crusader Strike delay (ms)"],
              min = 0, max = 4000, step = 100,
              tooltip = L["Once leaving the strike any longer than this would waste it, it stops being a suggestion and becomes the answer. Measured against the earliest moment you could actually cast it, not against now."],
              get = function() return d.csMaxDelayMs end,
              set = function(_, v) d.csMaxDelayMs = v end },
        } })
    table.insert(items, { type = "toggle", label = L["Sound when the window opens"],
        get = function() return d.sound end,
        set = function(_, v) d.sound = v and true or false end,
        subOptions = {
            { type = "toggle", label = L["Second cue for the late window"],
              tooltip = L["A different sound at the late twist mark, so the two ends of the window can be told apart without looking at the bar."],
              get = function() return d.soundLate end,
              set = function(_, v) d.soundLate = v and true or false end },
        } })
    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Twist landed"] })
    table.insert(items, { type = "desc", text = L["|cffaaaaaaAll three cues below wait for PROOF, not for a prediction. A swing has to land with both seals up, and the held seal's own damage has to follow it in the combat log. Nothing fires without that second line -- a confirmation that is right most of the time is one you cannot practise against.|r"] })
    table.insert(items, { type = "toggle", label = L["Sound when the twist lands"],
        get = function() return d.soundHit end,
        set = function(_, v) d.soundHit = v and true or false; ST.SyncTracker() end,
        subOptions = {
            { type = "dropdown", label = L["Hit sound"], width = 300,
              tooltip = L["The sniper and rifle cracks are bundled; the rest are the client's own cues. Below them stand any sounds other addons have registered as shared media."],
              values = hitSoundValues(),
              get = function() return d.hitSound end,
              set = function(_, v) d.hitSound = v; ST.PlayHitSound(v, d) end },
            { type = "dropdown", label = L["Sound channel"], width = 240,
              tooltip = L["Master ignores the sound effects slider, which is what a confirmation wants: it is feedback about the fight rather than part of it."],
              values = channelValues(),
              get = function() return d.hitChannel end,
              set = function(_, v) d.hitChannel = v; ST.PlayHitSound(d.hitSound, d) end },
            { type = "button", label = L["Listen"], width = 130,
              onClick = function() ST.PlayHitSound(d.hitSound, d) end },
        } })
    table.insert(items, { type = "toggle", label = L["Glow on the bar when the twist lands"],
        get = function() return d.hitGlow end,
        set = function(_, v) d.hitGlow = v and true or false; ST.SyncTracker() end,
        subOptions = {
            { type = "dropdown", label = L["Glow style"], width = 240,
              tooltip = L["Pixel border traces the bar's own outline at any width. Autocast pins the client's own ring to the four corners, so it stays a ring however wide the bar gets."],
              values = glowTypeValues(),
              get = function() return d.hitGlowType end,
              set = function(_, v) d.hitGlowType = v end },
            { type = "color", label = L["Glow colour"], width = 180,
              get = function() return d.hitGlowColor end,
              set = function(r, g, b) d.hitGlowColor = { r = r, g = g, b = b } end },
            { type = "slider", label = L["Glow duration (seconds)"],
              min = 0.1, max = 3, step = 0.1, decimals = 1,
              get = function() return d.hitGlowDuration end,
              set = function(_, v) d.hitGlowDuration = v end },
        } })
    table.insert(items, { type = "toggle", label = L["Text when the twist lands"],
        tooltip = L["A line somewhere on screen, with its own position. Useful where the bar is in the corner of the eye and the confirmation should be in the middle of it."],
        get = function() return d.hitText end,
        set = function(_, v) d.hitText = v and true or false; ST.SyncTracker() end,
        subOptions = {
            { type = "dropdown", label = L["Text font"], width = 240,
              values = ns.MediaFontValues(),
              get = function() return d.hitTextFont end,
              set = function(_, v) d.hitTextFont = v; ST.ApplyHitTextLook() end },
            { type = "dropdown", label = L["Text outline"], width = 240,
              values = outlineValues(),
              get = function() return d.hitTextOutline end,
              set = function(_, v) d.hitTextOutline = v; ST.ApplyHitTextLook() end },
            { type = "slider", label = L["Text size"], min = 10, max = 60, step = 1,
              get = function() return d.hitTextSize end,
              set = function(_, v) d.hitTextSize = v; ST.ApplyHitTextLook() end },
            { type = "color", label = L["Text colour"], width = 180,
              get = function() return d.hitTextColor end,
              set = function(r, g, b) d.hitTextColor = { r = r, g = g, b = b }; ST.ApplyHitTextLook() end },
            { type = "slider", label = L["Text duration (seconds)"],
              min = 0.2, max = 5, step = 0.1, decimals = 1,
              get = function() return d.hitTextDuration end,
              set = function(_, v) d.hitTextDuration = v end },
            { type = "button", label = L["Unlock / Test"], width = 130,
              onClick = function() ST.SetHitTextUnlocked(not d.hitTextPos.unlocked) end },
        } })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Latency"] })
    table.insert(items, { type = "desc", text = L["|cffaaaaaaThe round trip your client reports is not the delay a twist has to beat: the client adds a slice of its own, so the figure everything below works from is (world latency x multiplier) + offset. Raise the multiplier if you keep missing twists that looked in time.|r"] })
    table.insert(items, { type = "slider", label = L["Latency multiplier"],
        min = 0.5, max = 3, step = 0.05, decimals = 2,
        get = function() return d.lagMultiplier end,
        set = function(_, v) d.lagMultiplier = v; ST.ResetLagCache() end })
    table.insert(items, { type = "slider", label = L["Latency offset (ms)"], min = 0, max = 200, step = 5,
        get = function() return d.lagOffsetMs end,
        set = function(_, v) d.lagOffsetMs = v; ST.ResetLagCache() end })
    table.insert(items, { type = "toggle", label = L["Shade the deadzone"],
        tooltip = L["The tail of the swing a cast can no longer cross, shaded at the end of the bar. Its size follows your raw world latency rather than the calibrated figure, because this one is the wire and not a prediction. This switch only draws it -- the timing itself always accounts for it, so set the scale to 0 if you want no compensation at all."],
        get = function() return d.showDeadzone end,
        set = function(_, v) d.showDeadzone = v and true or false; ST.Layout() end,
        subOptions = {
            { type = "slider", label = L["Deadzone scale"], min = 0, max = 3, step = 0.05, decimals = 2,
              tooltip = L["Multiplies your world latency. Raise it if you cannot twist just outside the shaded stretch, lower it if you still can inside it. 0 switches the compensation off entirely."],
              get = function() return d.deadzoneScale end,
              set = function(_, v) d.deadzoneScale = v; ST.Layout() end },
            { type = "dropdown", label = L["Deadzone texture"], width = 240,
              values = ns.MediaStatusbarValues(),
              get = function() return d.deadzoneTexture end,
              set = function(_, v) d.deadzoneTexture = v; ST.Layout() end },
            -- The colour is NOT repeated here. It lives once, with the other
            -- special colours, because a setting that exists in two places is a
            -- setting people change in the wrong one.
            { type = "slider", label = L["Deadzone transparency"], min = 0, max = 1, step = 0.05, decimals = 2,
              get = function() return d.deadzoneAlpha end,
              set = function(_, v) d.deadzoneAlpha = v; ST.Layout() end },
        } })
    table.insert(items, { type = "dropdown", label = L["Global cooldown padding"], fullWidth = true,
        tooltip = L["Pulls the global cooldown boundary earlier by part of your latency, so a cast started right at the mark still clears the cooldown in time."],
        values = paddingValues(),
        get = function() return d.gcdPadding end,
        set = function(_, v) d.gcdPadding = v; ST.Layout() end,
        subOptions = {
            { type = "slider", label = L["Fixed global cooldown padding (ms)"], min = 0, max = 400, step = 5,
              tooltip = L["Only used while the padding mode is set to fixed."],
              get = function() return d.gcdPaddingMs end,
              set = function(_, v) d.gcdPaddingMs = v; ST.Layout() end },
        } })

    -- ------------------------------------------------------------ next action

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Next action"] })
    table.insert(items, { type = "desc", text = L["|cffaaaaaaAn icon of the one thing to press, wherever you want it. It answers the same question as the line under the bar -- the three switches below feed both, so the word and the picture can never disagree.|r"] })
    table.insert(items, { type = "toggle", label = L["Show the next action guide"],
        get = function() return d.naEnabled end,
        set = function(_, v) d.naEnabled = v and true or false; ST.ApplyVisibility() end,
        subOptions = {
            -- Full width on purpose. Paired with the icon-size slider this row
            -- gets half a cell, and the shared label column is capped at half of
            -- THAT -- which truncates the label in most languages ("Wann sie
            -- e..." in German). Shortening nine translations to fit a column is
            -- the wrong end to fix it from.
            { type = "dropdown", label = L["When to show it"], fullWidth = true,
              values = visibilityValues(),
              get = function() return d.naVisibility end,
              set = function(_, v) d.naVisibility = v; ST.ApplyVisibility() end },
            { type = "slider", label = L["Icon size"], min = 20, max = 90, step = 1,
              get = function() return d.naIconSize end,
              set = function(_, v) d.naIconSize = v; ST.ApplyNextLayout() end },
            { type = "button", label = L["Unlock / Test"], width = 130,
              onClick = function() ST.SetNextUnlocked(not d.naPos.unlocked) end },
        } })
    table.insert(items, { type = "toggle", label = L["Show a hold instead of nothing"],
        tooltip = L["While the right move is to press nothing on purpose -- the twist is coming and anything else would cost it -- the guide keeps showing the seal, drained and outlined. An empty box says the same thing much less clearly."],
        get = function() return d.naHold end,
        set = function(_, v) d.naHold = v and true or false end })
    table.insert(items, { type = "toggle", label = L["Suggest Judgement"],
        tooltip = L["Judging consumes the seal, so it is only ever offered with room to re-seal afterwards. Off by default: a mistimed judgement costs more than no suggestion at all."],
        get = function() return d.naShowJudge end,
        set = function(_, v) d.naShowJudge = v and true or false end })
    table.insert(items, { type = "toggle", label = L["Suggest a filler"],
        tooltip = L["Consecration, or Exorcism where the target can take it, in the stretch of the swing that is free for it. Exorcism is offered by asking the client whether the spell can be aimed at your target, which is right in every language."],
        get = function() return d.naShowFiller end,
        set = function(_, v) d.naShowFiller = v and true or false end,
        subOptions = {
            { type = "slider", label = L["Consecration mana floor (%)"], min = 0, max = 100, step = 5,
              tooltip = L["Below this share of your mana the filler is not worth it."],
              get = function() return d.naManaConsecration end,
              set = function(_, v) d.naManaConsecration = v end },
            { type = "slider", label = L["Exorcism mana floor (%)"], min = 0, max = 100, step = 5,
              get = function() return d.naManaExorcism end,
              set = function(_, v) d.naManaExorcism = v end },
        } })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Rotation"] })
    table.insert(items, { type = "toggle", label = L["Show the rotation helper"],
        tooltip = L["A row of steps above the bar: which sequence fits your weapon and haste, and where in it you are. It steps forward on what you actually cast and on your swings."],
        get = function() return d.showRotation end,
        set = function(_, v) d.showRotation = v and true or false; ST.Layout() end,
        subOptions = {
            { type = "dropdown", label = L["Sequence"], width = 300,
              tooltip = L["Automatic follows your attack speed and spell haste, which is what decides how many twists fit between two strikes. Pick one by hand to drill a single sequence."],
              values = rotationValues(),
              get = function() return d.rotation end,
              set = function(_, v) d.rotation = v; ST.Layout() end },
            { type = "slider", label = L["Rotation icon size"], min = 14, max = 48, step = 1,
              get = function() return d.rotIconSize end,
              set = function(_, v) d.rotIconSize = v; ST.Layout() end },
        } })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Display"] })
    table.insert(items, { type = "toggle", label = L["Show swing bar"],
        get = function() return d.showBar end,
        set = function(_, v) d.showBar = v and true or false; ST.Layout() end,
        subOptions = {
            { type = "toggle", label = L["Shade the zones"],
              tooltip = L["Tints the part of the swing still to come in the colour of the zone it runs into."],
              get = function() return d.showZones end,
              set = function(_, v) d.showZones = v and true or false; ST.Layout() end },
            { type = "toggle", label = L["Show the marks"],
              tooltip = L["The three boundary lines: danger zone, twist window, late twist."],
              get = function() return d.showTicks end,
              set = function(_, v) d.showTicks = v and true or false; ST.Layout() end },
            { type = "toggle", label = L["Show the judgement mark"],
              tooltip = L["A fourth line where Judgement comes off cooldown during this swing, so a judgement can be put in front of the twist instead of on top of it. Only drawn while a seal is up."],
              get = function() return d.showJudgeMarker end,
              set = function(_, v) d.showJudgeMarker = v and true or false; ST.Layout() end },
        } })
    table.insert(items, { type = "toggle", label = L["Show the global cooldown bar"],
        tooltip = L["A strip along the bottom of the bar reaching to the moment the global cooldown frees up, so you can see how much of this swing is already spoken for."],
        get = function() return d.showGCDBar end,
        set = function(_, v) d.showGCDBar = v and true or false; ST.Layout() end,
        subOptions = {
            { type = "slider", label = L["Global cooldown bar height"], min = 2, max = 20, step = 1,
              get = function() return d.gcdBarHeight end,
              set = function(_, v) d.gcdBarHeight = v; ST.Layout() end },
        } })
    table.insert(items, { type = "dropdown", label = L["Left readout"], width = 240,
        tooltip = L["What the left end of the bar shows. Attack speed turns into the warning colour below two global cooldowns per swing -- under that the twist and the seal going back up no longer both fit, so wait for the cooldown before twisting."],
        values = sideTextValues(),
        get = function() return d.leftText end,
        set = function(_, v) d.leftText = v; ST.Layout() end })
    table.insert(items, { type = "dropdown", label = L["Right readout"], width = 240,
        values = sideTextValues(),
        get = function() return d.rightText end,
        set = function(_, v) d.rightText = v; ST.Layout() end })
    table.insert(items, { type = "toggle", label = L["Show seal indicators"],
        tooltip = L["The seals currently on you and how long they last, right of the bar. Both show while the twist is in -- that overlap is the pay-off."],
        get = function() return d.showSeals end,
        set = function(_, v) d.showSeals = v and true or false; ST.Layout() end,
        subOptions = {
            { type = "toggle", label = L["Match the bar height"],
              tooltip = L["Sizes the icons to the bar instead of to their own setting, so the pair keeps lining up with it when the bar height changes."],
              get = function() return d.sealMatchBarHeight end,
              set = function(_, v) d.sealMatchBarHeight = v and true or false; ST.Layout() end },
            { type = "slider", label = L["Seal icon size"], min = 14, max = 48, step = 1,
              tooltip = L["Ignored while the icons match the bar height."],
              get = function() return d.iconSize end,
              set = function(_, v) d.iconSize = v; ST.Layout() end },
            { type = "slider", label = L["Seal icon spacing"], min = 0, max = 20, step = 1,
              get = function() return d.sealSpacing end,
              set = function(_, v) d.sealSpacing = v; ST.Layout() end },
            { type = "toggle", label = L["Centre the icons"],
              tooltip = L["Keeps the midpoint of the pair still when the second seal appears or falls off. Left-aligned keeps the first icon still instead, which is what an attached pair wants -- that edge is the bar."],
              get = function() return d.sealCentered end,
              set = function(_, v) d.sealCentered = v and true or false; ST.Layout() end },
            { type = "toggle", label = L["Show the cooldown sweep"],
              tooltip = L["The client's own sweep across the icon. It says the same thing as the number under it, but it says it without being read."],
              get = function() return d.sealSwipe end,
              set = function(_, v) d.sealSwipe = v and true or false; ST.Layout() end },
            { type = "color", label = L["Seal timer colour"], width = 180,
              get = function() return d.sealTimerColor end,
              set = function(r, g, b) d.sealTimerColor = { r = r, g = g, b = b }; ST.Layout() end },
            { type = "toggle", label = L["Detach from the bar"],
              tooltip = L["Gives the pair its own position anywhere on screen. They stay tied to the bar in every other way: when it is hidden, they are too."],
              get = function() return d.sealDetached end,
              set = function(_, v) d.sealDetached = v and true or false; ST.Layout() end },
            { type = "button", label = L["Unlock / Test"], width = 130,
              onClick = function() ST.SetSealsUnlocked(not d.sealPos.unlocked) end },
        } })
    table.insert(items, { type = "toggle", label = L["Show next action"],
        get = function() return d.showAction end,
        set = function(_, v) d.showAction = v and true or false; ST.Layout() end })
    table.insert(items, { type = "toggle", label = L["Show numbers"],
        get = function() return d.showNumbers end,
        set = function(_, v) d.showNumbers = v and true or false; ST.Layout() end })
    -- Same reason as the guide's visibility row: long label, and the info glyph
    -- takes another 22 px out of the shared column on top.
    table.insert(items, { type = "dropdown", label = L["When to show the bar"], fullWidth = true,
        tooltip = L["Always keeps it on screen, which is the easier way to practise the timing on a dummy. Seal active shows it whenever you are carrying a seal, in or out of a fight."],
        values = visibilityValues(),
        get = function() return d.visibility end,
        set = function(_, v) d.visibility = v; ST.ApplyVisibility() end })
    table.insert(items, { type = "toggle", label = L["Only with Two-Handed Weapon Specialization"],
        tooltip = L["Hides the helper unless you have a point in the talent. Twisting works without it, but the slow swing it is built around is what makes the whole habit pay."],
        get = function() return d.twoHandSpecOnly end,
        set = function(_, v) d.twoHandSpecOnly = v and true or false; ST.RefreshTalents() end })
    table.insert(items, { type = "slider", label = L["Bar width"], min = 120, max = 400, step = 10,
        get = function() return d.barWidth end,
        set = function(_, v) d.barWidth = v; ST.Layout() end })
    table.insert(items, { type = "slider", label = L["Bar height"], min = 10, max = 40, step = 1,
        get = function() return d.barHeight end,
        set = function(_, v) d.barHeight = v; ST.Layout() end })
    table.insert(items, { type = "slider", label = L["Font size"], min = 10, max = 30, step = 1,
        get = function() return d.fontSize end,
        set = function(_, v) d.fontSize = v; ST.Layout() end })
    table.insert(items, { type = "slider", label = L["Action text size"], min = 0, max = 40, step = 1,
        tooltip = L["The line that names what to press. 0 follows the general text size."],
        get = function() return d.actionFontSize or 0 end,
        set = function(_, v) d.actionFontSize = v; ST.Layout() end })
    table.insert(items, { type = "slider", label = L["Warning text size"], min = 0, max = 40, step = 1,
        tooltip = L["The red and yellow warnings on the bar. 0 follows the action text size."],
        get = function() return d.warnFontSize or 0 end,
        set = function(_, v) d.warnFontSize = v; ST.Layout() end })
    table.insert(items, { type = "slider", label = L["Readout text size"], min = 0, max = 40, step = 1,
        tooltip = L["The two numbers inside the bar. 0 follows the general text size."],
        get = function() return d.sideFontSize or 0 end,
        set = function(_, v) d.sideFontSize = v; ST.Layout() end })
    table.insert(items, { type = "slider", label = L["Seal timer text size"], min = 0, max = 40, step = 1,
        tooltip = L["The countdown on the seal icons. 0 scales it with the icon."],
        get = function() return d.sealTimerFontSize or 0 end,
        set = function(_, v) d.sealTimerFontSize = v; ST.Layout() end })

    -- ------------------------------------------------------------ practice

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Practice"] })
    table.insert(items, { type = "desc", text = L["|cffaaaaaaA swing clock that runs on its own, with no target and nothing spent. Press your bound keys against it and every swing is graded: the twist landed, it was too early, or nothing was attempted. The seal model is the real one -- a replaced seal keeps resolving for 0.4 seconds -- so the timing you learn here is the timing that works.|r"] })
    table.insert(items, { type = "button", label = L["Start / stop practice"], width = 200, primary = true,
        onClick = function() ST.TogglePractice() end })
    table.insert(items, { type = "slider", label = L["Simulated weapon speed"],
        min = 0, max = 5, step = 0.1, decimals = 1,
        tooltip = L["0 uses whatever you have equipped. Any other value drills a speed you do not own yet, which is how you find out that the weapon you are saving for needs a different sequence."],
        get = function() return d.practiceSpeed end,
        set = function(_, v) d.practiceSpeed = v end })
    table.insert(items, { type = "slider", label = L["Spell queue window (ms)"], min = 0, max = 800, step = 50,
        tooltip = L["A key pressed this far before the global cooldown ends is held and fires the moment it does, exactly as the client does it. Practising without it teaches a rhythm the game never asks for."],
        get = function() return d.practiceQueueMs end,
        set = function(_, v) d.practiceQueueMs = v end })

    for _, a in ipairs(ST.PRACTICE_ABILITIES) do
        local slot = a.key
        table.insert(items, { type = "editbox", label = L[a.label],
            width = 260, editWidth = 90, commitOnFocusLost = true,
            get = function() return (d.practiceKeys and d.practiceKeys[slot]) or "" end,
            set = function(_, v)
                d.practiceKeys = d.practiceKeys or {}
                -- Stored uppercase because that is what the key handler compares
                -- against; a lowercase binding would simply never match.
                d.practiceKeys[slot] = (v or ""):upper()
            end })
    end

    table.insert(items, { type = "slider", label = L["Result text size"], min = 12, max = 72, step = 1,
        get = function() return d.practiceResultSize end,
        set = function(_, v) d.practiceResultSize = v; ST.ApplyPracticeLook() end })
    table.insert(items, { type = "slider", label = L["Result text duration (seconds)"],
        min = 0.2, max = 3, step = 0.1, decimals = 1,
        get = function() return d.practiceResultDuration end,
        set = function(_, v) d.practiceResultDuration = v end })
    table.insert(items, { type = "color", label = L["Landed colour"], width = 200,
        get = function() return d.practiceColorHit end,
        set = function(r, g, b) d.practiceColorHit = { r = r, g = g, b = b } end })
    table.insert(items, { type = "color", label = L["Missed colour"], width = 200,
        get = function() return d.practiceColorMiss end,
        set = function(r, g, b) d.practiceColorMiss = { r = r, g = g, b = b } end })
    table.insert(items, { type = "toggle", label = L["Show the fight timeline"],
        tooltip = L["Every swing and every cast on one strip against a ruler. The ruler is the point: without it you can see that two swings were close together but not how close, which is the only number practice is about."],
        get = function() return d.practiceTimeline end,
        set = function(_, v) d.practiceTimeline = v and true or false; ST.ApplyTimelineShown() end,
        subOptions = {
            { type = "slider", label = L["Timeline width"], min = 200, max = 1200, step = 20,
              get = function() return d.practiceTimelineWidth end,
              set = function(_, v) d.practiceTimelineWidth = v; ST.ApplyPracticeLook() end },
            { type = "slider", label = L["Timeline pixels per second"], min = 20, max = 200, step = 5,
              get = function() return d.practiceTimelinePPS end,
              set = function(_, v) d.practiceTimelinePPS = v end },
        } })

    -- ------------------------------------------------------------ appearance

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Appearance"] })
    table.insert(items, { type = "dropdown", label = L["Bar texture"], width = 240,
        values = ns.MediaStatusbarValues(),
        get = function() return d.barTexture end,
        set = function(_, v) d.barTexture = v; ST.Layout() end })
    table.insert(items, { type = "dropdown", label = L["Global cooldown bar texture"], fullWidth = true,
        values = ns.MediaStatusbarValues(),
        get = function() return d.gcdTexture end,
        set = function(_, v) d.gcdTexture = v; ST.Layout() end })
    table.insert(items, { type = "dropdown", label = L["Background texture"], width = 240,
        values = ns.MediaStatusbarValues(),
        get = function() return d.bgTexture end,
        set = function(_, v) d.bgTexture = v; ST.Layout() end,
        subOptions = {
            { type = "color", label = L["Background colour"], width = 180,
              get = function() return d.bgColor end,
              set = function(r, g, b) d.bgColor = { r = r, g = g, b = b }; ST.Layout() end },
            { type = "slider", label = L["Background transparency"], min = 0, max = 1, step = 0.05, decimals = 2,
              get = function() return d.bgAlpha end,
              set = function(_, v) d.bgAlpha = v; ST.Layout() end },
        } })
    table.insert(items, { type = "dropdown", label = L["Border"], width = 240,
        tooltip = L["Solid draws four flat edges in the colour below. Texture takes an edge file from shared media, which is what a border from another interface pack looks like."],
        values = borderModeValues(),
        get = function() return d.borderMode end,
        set = function(_, v) d.borderMode = v; ST.Layout() end,
        subOptions = {
            { type = "dropdown", label = L["Border texture"], width = 240,
              tooltip = L["Only used while the border is set to texture."],
              values = ns.MediaBorderValues(),
              get = function() return d.borderTexture end,
              set = function(_, v) d.borderTexture = v; ST.Layout() end },
            { type = "slider", label = L["Border width"], min = 1, max = 8, step = 1,
              get = function() return d.borderWidth end,
              set = function(_, v) d.borderWidth = v; ST.Layout() end },
            { type = "color", label = L["Border colour"], width = 180,
              get = function() return d.borderColor end,
              set = function(r, g, b) d.borderColor = { r = r, g = g, b = b }; ST.Layout() end },
        } })
    table.insert(items, { type = "dropdown", label = L["Marker texture"], width = 240,
        values = ns.MediaStatusbarValues(),
        get = function() return d.markerTexture end,
        set = function(_, v) d.markerTexture = v; ST.Layout() end,
        subOptions = {
            { type = "slider", label = L["Marker width"], min = 1, max = 8, step = 1,
              get = function() return d.markerWidth end,
              set = function(_, v) d.markerWidth = v; ST.Layout() end },
        } })
    table.insert(items, { type = "dropdown", label = L["Font"], width = 240,
        values = ns.MediaFontValues(),
        get = function() return d.font end,
        set = function(_, v) d.font = v; ST.Layout() end,
        subOptions = {
            { type = "dropdown", label = L["Font outline"], width = 240,
              values = outlineValues(),
              get = function() return d.fontOutline end,
              set = function(_, v) d.fontOutline = v; ST.Layout() end },
            { type = "color", label = L["Font colour"], width = 180,
              get = function() return d.fontColor end,
              set = function(r, g, b) d.fontColor = { r = r, g = g, b = b }; ST.Layout() end },
        } })
    table.insert(items, { type = "dropdown", label = L["Frame strata"], width = 240,
        tooltip = L["Which layer of the interface the helper sits in. Raise it to lift the bar over another addon that draws in the same place."],
        values = strataValues(),
        get = function() return d.strata end,
        set = function(_, v) d.strata = v; ST.Layout() end,
        subOptions = {
            { type = "slider", label = L["Draw level"], min = 1, max = 100, step = 1,
              tooltip = L["The order inside the chosen layer. Higher draws on top."],
              get = function() return d.drawLevel end,
              set = function(_, v) d.drawLevel = v; ST.Layout() end },
        } })

    -- ------------------------------------------------------------ colours

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Colours"] })
    -- Full width, and it fixes two things at once. Its German label is long
    -- enough to risk truncation in a half cell, AND leaving it in the run made
    -- the run fifteen rows -- an odd count, so placeColumns stretched the last
    -- colour across the page and put its swatch 42 px left of every other one.
    -- Out of the run the colours are 8 seals + 6 states = 14, an exact grid.
    table.insert(items, { type = "dropdown", label = L["Colour the bar by"], fullWidth = true,
        tooltip = L["Zones colour the fill by the stretch of the swing you are in, which is what this helper is built around. Seal colours it by what you are carrying, which is the faster read once the timing is in your fingers. Either way the special colours below outrank the choice."],
        values = colorSourceValues(),
        get = function() return d.barColorSource end,
        set = function(_, v) d.barColorSource = v end })
    for _, row in ipairs(SEAL_COLOR_ROWS) do
        local key = row.key
        table.insert(items, { type = "color", label = L[row.label], width = 220,
            get = function() return d.sealColors and d.sealColors[key] end,
            set = function(r, g, b)
                d.sealColors = d.sealColors or {}
                d.sealColors[key] = { r = r, g = g, b = b }
            end })
    end
    table.insert(items, { type = "color", label = L["No twist possible"], width = 220,
        tooltip = L["The fill while this swing's twist is already gone, and the tail of the swing a cast can no longer reach."],
        get = function() return d.colNoTwist end,
        set = function(r, g, b) d.colNoTwist = { r = r, g = g, b = b } end })
    table.insert(items, { type = "color", label = L["Warning"], width = 220,
        tooltip = L["The warnings on the bar, and the attack speed once the weapon is too fast to twist with."],
        get = function() return d.colWarning end,
        set = function(r, g, b) d.colWarning = { r = r, g = g, b = b } end })
    table.insert(items, { type = "color", label = L["Twisting"], width = 220,
        tooltip = L["The fill while both seals are up: the twist is in and this swing carries it."],
        get = function() return d.colTwisting end,
        set = function(r, g, b) d.colTwisting = { r = r, g = g, b = b } end })
    table.insert(items, { type = "color", label = L["Default"], width = 220,
        tooltip = L["The fill with no seal up and between swings."],
        get = function() return d.colDefault end,
        set = function(r, g, b) d.colDefault = { r = r, g = g, b = b } end })
    table.insert(items, { type = "color", label = L["Global cooldown"], width = 220,
        get = function() return d.colGCD end,
        set = function(r, g, b) d.colGCD = { r = r, g = g, b = b }; ST.Layout() end })
    table.insert(items, { type = "color", label = L["Deadzone"], width = 220,
        get = function() return d.deadzoneColor end,
        set = function(r, g, b) d.deadzoneColor = { r = r, g = g, b = b }; ST.Layout() end })

    return items
end
