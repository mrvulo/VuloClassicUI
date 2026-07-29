-- Paladin seal twist: the bar.
--
-- Everything that is DRAWN lives here -- the frame, the swing bar, the zone
-- shading, the boundary marks, the seal indicators, the rotation row and the
-- per-frame update that moves them. The timing this reads from is in
-- Modules/Classes/Paladin.lua; this file only turns those numbers into pixels.
--
-- See the header of Paladin.lua for why the helper is split at all.
local _, ns = ...
local L = ns.L

local ST = ns.SealTwist
if not ST then return end

local GetTime, UnitAttackSpeed = GetTime, UnitAttackSpeed
local UnitAffectingCombat = UnitAffectingCombat
local min, max, floor = math.min, math.max, math.floor

local BAR_TEX = ST.BAR_TEX

local bar, barBG
local zoneFiller, zoneDanger, zoneTwist
local tickDanger, tickTwist, tickLate, tickJudge
local deadzone, gcdBar
local leftFS, rightFS, actionFS, infoFS, rotLabel
local borderFrame
local driver
local borderEdges = {}
local sealFrame
local sealSlots = {}
local rotIcons  = {}

-- How many indicators were laid out last. The two slots are only re-placed when
-- that count changes, because with the centred option their positions depend on
-- it -- and re-anchoring both of them fifty times a second to compute the same
-- two numbers is exactly the kind of waste that never shows up in a profile.
local sealCountSig

local lastSound, lastLateSound = 0, 0
local wasPrompting, wasLate = false, false

-- Memo for the zone geometry, declared up here because ST.Layout has to be able
-- to drop it: layout shows the zone textures again, and a zone that placeZones
-- had hidden for being zero-width would otherwise come back at its old size and
-- stay there until the weapon speed happened to change.
local tickSig

-- ---------------------------------------------------------------- text sizes

-- The action line has its own size, because it is the one line that is read
-- mid-fight and the one that carries the longest text. 0 means "follow the
-- general size", so a profile that never touches it behaves exactly as before
-- and the two do not have to be kept in step by hand.
function ST.ActionSize(d)
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
function ST.WarnSize(d)
    local s = d.warnFontSize or 0
    return (s > 0) and s or ST.ActionSize(d)
end

-- Shared by both readouts inside the bar. Its fallback is the formula that used
-- to be inline for the attack speed -- four below the general size -- so a
-- profile that never touched it keeps exactly the size it has today.
function ST.SideSize(d)
    local s = d.sideFontSize or 0
    return (s > 0) and s or max(9, d.fontSize - 4)
end

-- Font path, outline flag and colour, resolved together because every caller
-- wants all three and nothing sets one without the others.
function ST.FontFace(d)
    return ns.MediaFont(d.font, ST.FontPath()), d.fontOutline or "OUTLINE"
end

-- The indicator size, which is either its own setting or the bar's height.
-- Everything that measures the pair goes through here, so the two cannot drift.
function ST.SealIconSize(d)
    if d.sealMatchBarHeight then return d.barHeight end
    return d.iconSize
end

function ST.SealTimerSize(d)
    local s = d.sealTimerFontSize or 0
    return (s > 0) and s or max(8, ST.SealIconSize(d) * 0.4)
end

-- What the seal indicators claim to the right of the bar, so the bar keeps its
-- configured width whether they are shown or not. Nothing is reserved on the
-- left any more: both readouts moved INSIDE the bar, which is where a value
-- belonging to the swing belongs and which stops the frame changing width when
-- the left readout is switched off.
local function sideWidths(d)
    -- Detached indicators claim nothing: they are somewhere else on the screen,
    -- and reserving room for them would leave a hole where they used to be.
    if not d.showSeals or d.sealDetached then return 0, 0 end
    local s = ST.SealIconSize(d)
    return 0, s * 2 + d.sealSpacing + 6
end

-- Height the rotation row claims above the bar.
local function rowHeight(d)
    return d.showRotation and (d.rotIconSize + 4) or 0
end

-- ---------------------------------------------------------------- layout

-- Steps are laid out from the middle of the bar, so a sequence that grows or
-- shrinks stays centred instead of walking off one end.
local function placeRotation(d)
    if not rotIcons[1] then return end
    local n = min(#ST.rotSteps, ST.ROT_MAX_STEPS)
    local size, gap = d.rotIconSize, 3
    local span = n * size + (n - 1) * gap
    for i = 1, ST.ROT_MAX_STEPS do
        local ico = rotIcons[i]
        ico:SetSize(size, size)
        ico:ClearAllPoints()
        ico:SetPoint("BOTTOMLEFT", bar, "TOPLEFT",
            (d.barWidth - span) / 2 + (i - 1) * (size + gap), 4)
    end
    rotLabel:ClearAllPoints()
    rotLabel:SetPoint("RIGHT", bar, "TOPLEFT", (d.barWidth - span) / 2 - 6, 4 + size / 2)
    ST.rotDirty = false
end

-- Fill and backing. Tiling is switched off explicitly: a narrow shared-media
-- texture REPEATS across the bar instead of stretching to it, and at 240 px
-- wide that turns a gradient into a row of stripes.
local function applyBarTexture(d)
    bar:SetStatusBarTexture(ns.MediaStatusbar(d.barTexture, BAR_TEX))
    local t = bar:GetStatusBarTexture()
    if t and t.SetHorizTile then t:SetHorizTile(false); t:SetVertTile(false) end
    barBG:SetTexture(ns.MediaStatusbar(d.bgTexture, BAR_TEX))
    barBG:SetVertexColor(ST.Color(d.bgColor, 0.08, 0.08, 0.10))
    barBG:SetAlpha(d.bgAlpha or 0.90)
end

-- Three border modes, and only one of them needs a backdrop.
--
-- Solid is four flat edges, which is the honest way to draw a one-colour
-- outline: a backdrop with no edge file gives a hairline the width setting
-- cannot move. Texture is the case a backdrop is actually for -- a shared-media
-- edge file is an eight-piece atlas, and stretching one across a flat texture
-- would show it corner-first.
local function applyBorder(d)
    local mode = d.borderMode or "none"
    local w = max(1, d.borderWidth or 1)
    local br, bg, bb = ST.Color(d.borderColor, 0, 0, 0)
    local solid = (mode == "solid") and d.showBar

    -- Re-anchored here rather than once at creation, because the corners depend
    -- on the width: the top and bottom edges have to reach OUT past the bar by
    -- the border width, or the four strips leave a notch at each corner.
    for i = 1, 4 do borderEdges[i]:SetShown(solid) end
    if solid then
        for i = 1, 4 do
            local t = borderEdges[i]
            t:SetColorTexture(br, bg, bb, 1)
            t:ClearAllPoints()
        end
        borderEdges[1]:SetPoint("BOTTOMLEFT",  bar, "TOPLEFT",     -w, 0)
        borderEdges[1]:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT",     w, 0)
        borderEdges[1]:SetHeight(w)
        borderEdges[2]:SetPoint("TOPLEFT",     bar, "BOTTOMLEFT",  -w, 0)
        borderEdges[2]:SetPoint("TOPRIGHT",    bar, "BOTTOMRIGHT",  w, 0)
        borderEdges[2]:SetHeight(w)
        borderEdges[3]:SetPoint("TOPRIGHT",    bar, "TOPLEFT",      0, 0)
        borderEdges[3]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT",   0, 0)
        borderEdges[3]:SetWidth(w)
        borderEdges[4]:SetPoint("TOPLEFT",     bar, "TOPRIGHT",     0, 0)
        borderEdges[4]:SetPoint("BOTTOMLEFT",  bar, "BOTTOMRIGHT",  0, 0)
        borderEdges[4]:SetWidth(w)
    end

    if not borderFrame then return end
    local file = (mode == "texture") and d.showBar and ns.MediaBorder(d.borderTexture) or nil
    if file and borderFrame.SetBackdrop then
        borderFrame:ClearAllPoints()
        borderFrame:SetPoint("TOPLEFT",     bar, "TOPLEFT",     -w, w)
        borderFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT",  w, -w)
        borderFrame:SetBackdrop({ edgeFile = file, edgeSize = max(4, w * 4) })
        borderFrame:SetBackdropBorderColor(br, bg, bb, 1)
        borderFrame:Show()
    else
        borderFrame:Hide()
    end
end

function ST.Layout()
    local d = ST.DB()
    local frame = ST.frame
    if not frame or not d then return end

    local fontPath, outline = ST.FontFace(d)
    local fr, fg, fb = ST.Color(d.fontColor, 1, 1, 1)
    local leftW, rightW = sideWidths(d)
    local rowH = rowHeight(d)
    local h = d.barHeight + rowH
    if d.showAction  then h = h + max(ST.ActionSize(d), ST.WarnSize(d)) + 4 end
    if d.showNumbers then h = h + max(9, d.fontSize - 6) + 2 end
    h = h + 6
    -- The EFFECTIVE icon size, not the setting: with the icons matching the bar
    -- height, a large leftover iconSize would reserve height for a size nothing
    -- is drawn at. Detached indicators reserve nothing at all.
    local reserve = (d.showSeals and not d.sealDetached) and ST.SealIconSize(d) or 0
    if reserve > h then h = reserve end

    frame:SetSize(leftW + d.barWidth + rightW, h)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
    frame:SetFrameStrata(d.strata or "MEDIUM")
    frame:SetFrameLevel(d.drawLevel or 10)

    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", leftW, -rowH)
    bar:SetSize(d.barWidth, d.barHeight)
    bar:SetShown(d.showBar)
    applyBarTexture(d)
    applyBorder(d)

    rotLabel:SetFont(fontPath, max(9, d.rotIconSize * 0.5), outline)
    rotLabel:SetShown(d.showRotation)
    for i = 1, ST.ROT_MAX_STEPS do
        if not d.showRotation then rotIcons[i]:Hide() end
    end
    placeRotation(d)

    -- Both readouts sit INSIDE the bar, hard against its two ends. Vertically
    -- centred rather than hung from the top: the bar height is a setting and a
    -- constant offset only centres one value of it.
    local side = ST.SideSize(d)
    leftFS:SetFont(fontPath, side, outline)
    leftFS:SetTextColor(fr, fg, fb)
    leftFS:SetShown(d.showBar and d.leftText ~= "none")
    rightFS:SetFont(fontPath, side, outline)
    rightFS:SetTextColor(fr, fg, fb)
    rightFS:SetShown(d.showBar and d.rightText ~= "none")

    actionFS:SetFont(fontPath, ST.ActionSize(d), outline)
    actionFS._vcSize = ST.ActionSize(d)
    actionFS:SetShown(d.showAction)
    infoFS:SetFont(fontPath, max(9, d.fontSize - 6), outline)
    infoFS:SetShown(d.showNumbers)

    -- The indicator container. Sized for TWO icons whether one is showing or
    -- not: a container that shrinks with the count would drag its own mover box
    -- around, and a detached pair would walk across the screen every time a seal
    -- fell off.
    local isz  = ST.SealIconSize(d)
    local tr, tg, tb = ST.Color(d.sealTimerColor, 1, 1, 1)
    sealFrame:SetSize(isz * 2 + d.sealSpacing, isz)
    sealFrame:ClearAllPoints()
    if d.sealDetached then
        local p = d.sealPos or {}
        sealFrame:SetPoint("CENTER", UIParent, "CENTER", p.x or 0, p.y or -220)
    else
        sealFrame:SetPoint("LEFT", bar, "RIGHT", 6, 0)
    end
    sealFrame:SetShown(d.showSeals)

    for i = 1, 2 do
        local slot = sealSlots[i]
        slot:SetSize(isz, isz)
        slot.time:SetFont(fontPath, ST.SealTimerSize(d), outline)
        slot.time:SetTextColor(tr, tg, tb)
        slot.cd:SetShown(d.sealSwipe)
        -- updateSeals stops touching them when the setting is off, so they have
        -- to be put away here or the last pair stays on screen for good.
        if not d.showSeals then slot:Hide() end
    end
    -- Placement depends on how many are showing, so it is the update's call.
    sealCountSig = nil

    zoneFiller:SetShown(d.showBar and d.showZones)
    zoneDanger:SetShown(d.showBar and d.showZones)
    zoneTwist:SetShown(d.showBar and d.showZones)
    tickDanger:SetShown(d.showBar and d.showTicks)
    tickTwist:SetShown(d.showBar and d.showTicks)
    tickLate:SetShown(d.showBar and d.showTicks)
    -- The judgement mark and the two extra bars are placed per frame, so they
    -- are only put AWAY here -- showing them is the update's call, and doing it
    -- from both ends would flash them for one frame after every settings change.
    if not (d.showBar and d.showJudgeMarker) then tickJudge:Hide() end
    if not (d.showBar and d.showDeadzone)    then deadzone:Hide() end
    if not (d.showBar and d.showGCDBar)      then gcdBar:Hide() end

    local dr, dg, db_ = ST.Color(d.deadzoneColor, 0.72, 0.05, 0.05)
    deadzone:SetTexture(ns.MediaStatusbar(d.deadzoneTexture, BAR_TEX))
    deadzone:SetVertexColor(dr, dg, db_, d.deadzoneAlpha or 0.72)

    gcdBar:SetTexture(ns.MediaStatusbar(d.gcdTexture, BAR_TEX))
    gcdBar:SetVertexColor(ST.Color(d.colGCD, 0.48, 0.48, 0.48))
    gcdBar:SetHeight(min(d.gcdBarHeight, d.barHeight))

    local mt = ns.MediaStatusbar(d.markerTexture, BAR_TEX)
    for _, t in ipairs({ tickDanger, tickTwist, tickLate, tickJudge }) do
        t:SetTexture(mt)
        t:SetWidth(d.markerWidth)
    end
    -- The late mark stays the thin one: it sits inside the twist window rather
    -- than bounding a zone, and at equal weight the two green lines read as one
    -- smeared boundary.
    tickLate:SetWidth(max(1, d.markerWidth - 1))

    -- Everything above can move a boundary; the memo has to go with it.
    tickSig = nil

    -- The guide is a separate frame with its own position and size, but it is
    -- laid out from the same pass: one settings change, one relayout.
    ST.ApplyNextLayout()
end

-- Zones and marks sit at a fraction of the bar measured from the RIGHT, because
-- every boundary is defined as "time left before the swing", not time elapsed.
--
-- Memoised on everything that can move them: this runs once per frame, but the
-- geometry only changes when the weapon speed, haste, latency or a setting does.
local function placeZones(swingDur, dangerStart, windowStart, lateStart, dead)
    local d = ST.DB()
    if not d.showBar or not swingDur or swingDur <= 0 then return end
    local sig = swingDur .. "|" .. dangerStart .. "|" .. windowStart .. "|"
        .. lateStart .. "|" .. dead .. "|" .. d.barWidth
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

    if d.showDeadzone then
        -- Never the whole bar: at a bad enough latency the deadzone arithmetic
        -- swallows the swing, and a bar shaded end to end says nothing at all
        -- where a bar with a sliver of daylight still says "almost none".
        local dw = min((dead / swingDur) * w, w - 1)
        if dw < 1 then deadzone:Hide() else deadzone:SetWidth(dw); deadzone:Show() end
    end
end

-- The judgement mark: where in THIS swing Judgement comes off cooldown.
--
-- Placed per frame rather than with the other marks because it is the one
-- boundary that does not follow from the settings -- it follows from a cooldown
-- that the player restarts whenever they judge. Cheap enough: one division and
-- one SetPoint, and only while the mark is switched on.
local function placeJudge(d, swingDur, remaining)
    if not (d.showBar and d.showJudgeMarker) then return end
    -- A mark for a seal that is not up would point at a judgement that consumes
    -- nothing, which is the one case where following it costs damage.
    if not (ST.hasHeld or ST.hasTwist) or not ST.judgeName then tickJudge:Hide(); return end
    local left = ST.JudgementRemaining()
    -- Nothing to anticipate: either it comes off cooldown after this swing has
    -- already landed, or it is off cooldown NOW -- in which case the mark would
    -- sit on the fill edge and ride along with it, which reads as a moving
    -- boundary rather than as "ready". Whether judgement is available at all is
    -- the next action's job to say, not this mark's.
    if not left or left <= 0 or left >= remaining then tickJudge:Hide(); return end
    local frac = (remaining - left) / swingDur
    if frac >= 1 or frac < 0 then tickJudge:Hide(); return end
    tickJudge:ClearAllPoints()
    tickJudge:SetPoint("TOP",    bar, "TOPRIGHT",    -d.barWidth * frac, 0)
    tickJudge:SetPoint("BOTTOM", bar, "BOTTOMRIGHT", -d.barWidth * frac, 0)
    tickJudge:Show()
end

-- The global cooldown you are sitting on, measured across the swing it eats
-- into: from the start of the swing to the moment the cooldown frees up.
local function placeGCDBar(d, swingDur, remaining)
    if not (d.showBar and d.showGCDBar) then return end
    local left = ST.GCDRemaining()
    if left <= 0 then gcdBar:Hide(); return end
    local ends = (swingDur - remaining) + left
    if ends > swingDur then ends = swingDur end
    local w = (ends / swingDur) * d.barWidth
    if w < 1 then gcdBar:Hide() else gcdBar:SetWidth(w); gcdBar:Show() end
end

-- Where the two indicators sit inside their container, for a given number of
-- them actually showing. Centred puts the group's midpoint on the container's;
-- otherwise the first icon hangs off the container's left edge, which is what
-- an attached pair wants because that edge is the bar.
local function placeSeals(d, n)
    local sig = n .. "|" .. (d.sealCentered and "c" or "l")
    if sig == sealCountSig then return end
    sealCountSig = sig

    local size, gap = ST.SealIconSize(d), d.sealSpacing
    local span = max(n, 1) * size + (max(n, 1) - 1) * gap
    local x0 = d.sealCentered and ((sealFrame:GetWidth() or span) - span) / 2 or 0
    for i = 1, 2 do
        local slot = sealSlots[i]
        slot:ClearAllPoints()
        slot:SetPoint("LEFT", sealFrame, "LEFT", x0 + (i - 1) * (size + gap), 0)
    end
end

-- Which seals are on the player, and for how long. Both show while the twist is
-- in -- that overlap IS the pay-off, and seeing it is how a player confirms the
-- twist landed instead of inferring it from a colour.
local function updateSeals(d, now)
    if not d.showSeals then return end

    -- Placing the pair means seeing it, and out of combat there is nothing to
    -- see. The preview draws the two configured seals from the spellbook so the
    -- container can be dragged to where it belongs.
    local preview = (d.sealPos and d.sealPos.unlocked) or ns:IsMoverEditMode()

    local n = 0
    local function put(icon, expires, duration)
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
        -- Re-armed only when the aura actually changed. SetCooldown restarts the
        -- animation from the top, so calling it every frame freezes the sweep at
        -- its first pixel -- which looks exactly like a sweep that is not
        -- working rather than one being reset.
        if d.sealSwipe and duration and duration > 0 and expires then
            local start = expires - duration
            if slot.cdStart ~= start or slot.cdDur ~= duration then
                slot.cdStart, slot.cdDur = start, duration
                slot.cd:SetCooldown(start, duration)
            end
        elseif slot.cdStart then
            slot.cdStart, slot.cdDur = nil, nil
            slot.cd:Clear()
        end
        slot:Show()
    end

    if preview then
        put(ST.heldTex or ST.heldIcon)
        put(ST.twistTex or ST.twistIcon)
    else
        if ST.hasHeld  then put(ST.heldIcon,  ST.heldExpires,  ST.heldDuration)  end
        if ST.hasTwist then put(ST.twistIcon, ST.twistExpires, ST.twistDuration) end
    end
    placeSeals(d, n)
    for i = n + 1, 2 do sealSlots[i]:Hide() end
end

-- The spell name each step points at, and the tint that says which seal carries
-- the swing on an auto step -- that is the only thing separating the two.
local ATTACK_ICON = "Interface\\ICONS\\INV_Sword_04"
local ROT_TINT = {
    [ST.R_AUTO_T] = { 0.45, 1.00, 0.60 },
    [ST.R_AUTO_H] = { 0.75, 0.60, 1.00 },
}

-- An auto step deliberately does NOT show the seal icon: the twist step already
-- has it, and two identical pictures a colour apart is the sort of row that
-- gets misread in the middle of a fight. The swing gets the attack icon, and
-- the tint says which seal it lands with.
local function stepTexture(step)
    if step == ST.R_CS or step == ST.R_CS_LATE then return ST.csTex end
    if step == ST.R_TWIST then return ST.twistTex end
    return (GetSpellTexture and GetSpellTexture(6603)) or ATTACK_ICON
end

-- The step you are on is the only one at full strength; the rest of the
-- sequence stays visible but drained, so the row reads as "here, then this".
local function updateRotationDisplay(d)
    if not d.showRotation then return end
    if ST.rotDirty then placeRotation(d) end
    rotLabel:SetText(ST.rotKey or L["Twist only"])
    for i = 1, ST.ROT_MAX_STEPS do
        local ico = rotIcons[i]
        local step = ST.rotSteps[i]
        if not step then
            ico:Hide()
        else
            local tex = stepTexture(step)
            if ico.shown ~= tex then
                ico.icon:SetTexture(tex)
                ico.shown = tex
            end
            local current = (i == ST.rotStep)
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

-- One of the two readouts inside the bar.
--
-- Only the attack speed carries a colour of its own, and it earns it: under two
-- global cooldowns per swing the cycle stops fitting -- the twist and the seal
-- going back up need one each -- so the number turning into a warning is the
-- one place the bar can say "this weapon is too fast to twist with". The cap
-- moves with spell haste, which is why it is computed rather than written down
-- as a flat 3.0.
local function updateSideText(d, fs, what, swingDur, remaining, gcd)
    if what == "none" or not fs:IsShown() then return end
    local warn = false
    local text = ""
    if what == "attackSpeed" then
        local speed = swingDur or UnitAttackSpeed("player")
        if speed and speed > 0 then
            text = format("%.1f", speed)
            warn = speed < 2 * gcd
        end
    elseif what == "swingTimer" then
        if remaining then text = format("%.1f", remaining) end
    elseif what == "latency" then
        text = format("%d", floor(ST.LagWorldMs(d) + 0.5))
    elseif what == "gcd" then
        text = format("%.1f", ST.GCDRemaining())
    end
    fs:SetText(text)
    if warn then
        fs:SetTextColor(ST.Color(d.colWarning, 1.00, 0.80, 0.20))
    else
        fs:SetTextColor(ST.Color(d.fontColor, 1, 1, 1))
    end
end

-- ---------------------------------------------------------------- per frame

local function onUpdate()
    local d = ST.DB()
    if not d then return end

    local fake = d.unlocked or ns:IsMoverEditMode()
    local now = GetTime()
    local remaining, swingDur

    if fake then
        -- A fake 2.6 s swing so the bar, the zones and all three marks are
        -- visible while placing the frame out of combat.
        swingDur = 2.6
        remaining = swingDur - (now % swingDur)
    elseif ST.PracticeActive() then
        swingDur, remaining = ST.PracticeSwing()
    else
        local _, dur, active = ns:GetSwing("mainhand")
        if active and dur > 0 then
            swingDur = dur
            remaining = ns:SwingRemaining("mainhand")
        end
    end

    local gcd = ST.CurrentGCD()
    local dangerStart, windowStart, lateStart, windowEnd = ST.Bounds(d, gcd)

    updateSideText(d, leftFS,  d.leftText,  swingDur, remaining, gcd)
    updateSideText(d, rightFS, d.rightText, swingDur, remaining, gcd)

    updateSeals(d, now)

    if d.showRotation then
        ST.UpdateRotation(d, swingDur or UnitAttackSpeed("player") or 0, gcd)
        updateRotationDisplay(d)
    end

    if not remaining then
        -- Shown but not swinging: an empty bar rather than a stale one, so the
        -- frame reads as "waiting" instead of showing a swing that ended.
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetStatusBarColor(ST.Color(d.colDefault, 0.35, 0.35, 0.42))
        actionFS:SetText("")
        if d.showNumbers then infoFS:SetText(L["waiting for a swing"]) end
        -- Everything measured against a swing has nothing to measure against.
        tickJudge:Hide()
        gcdBar:Hide()
        ST.ResetNext()
        -- Leaving these set would swallow the first cue of the next fight.
        wasPrompting, wasLate = false, false
        return
    end

    placeZones(swingDur, dangerStart, windowStart, lateStart, windowEnd)
    placeGCDBar(d, swingDur, remaining)
    placeJudge(d, swingDur, remaining)
    bar:SetMinMaxValues(0, swingDur)
    bar:SetValue(swingDur - remaining)

    local zone = ST.ZoneOf(remaining, dangerStart, windowStart, lateStart, windowEnd)
    local action, actName, actTex
    if fake then
        action, actName, actTex = ST.ACTION_TWIST, ST.twistName, ST.twistTex
    else
        action, actName, actTex = ST.Decide(d, remaining, gcd, dangerStart, windowStart, windowEnd)
    end
    -- The guide draws the same answer as an icon. Fed from here rather than
    -- owning an update of its own: this is where the answer already exists.
    ST.UpdateNext(d, action, actTex)

    -- The twist being IN outranks the zone: there is nothing left to do on this
    -- swing, and a green bar would keep asking for a cast that would overwrite
    -- the seal already carrying it.
    local lost = not fake and ST.TwistLost(remaining, windowEnd)

    -- THE SPECIAL STATES OUTRANK BOTH COLOUR SOURCES. Whether the fill is
    -- painted by zone or by seal, "the twist is already in" and "this swing's
    -- twist is gone" are answers to the question the player is actually asking,
    -- and neither source can express them.
    local cr, cg, cb
    if lost then
        cr, cg, cb = ST.Color(d.colNoTwist, 0.45, 0.16, 0.16)
    elseif ST.hasTwist and not fake and zone ~= ST.Z_FILLER and zone ~= ST.Z_DANGER then
        cr, cg, cb = ST.Color(d.colTwisting, 0.14, 0.45, 0.22)
    elseif d.barColorSource == "seal" then
        cr, cg, cb = ST.SealColor(d)
        if not cr then cr, cg, cb = ST.Color(d.colDefault, 0.35, 0.35, 0.42) end
    elseif action == ST.ACTION_TWIST and zone == ST.Z_DANGER then
        -- The head start puts the prompt in the last sliver of the danger zone
        -- on purpose. Leaving the bar red there would have the two halves of the
        -- display saying opposite things.
        cr, cg, cb = ST.ZoneColor(d, ST.Z_TWIST)
    elseif zone == ST.Z_TWIST or zone == ST.Z_LATE then
        -- No held seal means the window is open on nothing.
        cr, cg, cb = ST.ZoneColor(d, (ST.hasHeld or fake) and zone or ST.Z_MISS)
    else
        cr, cg, cb = ST.ZoneColor(d, zone)
    end
    bar:SetStatusBarColor(cr, cg, cb)

    if d.showAction then
        local label, warn
        local wrap = ST.ACTION_TEXT[action]
        if wrap and action == ST.ACTION_HOLD then
            -- The word, not the spell: "wait" is the instruction, and the spell
            -- being waited FOR is what the icon guide shows.
            label = format(wrap, L["wait"])
        elseif wrap then
            label = format(wrap, actName
                or (action == ST.ACTION_TWIST and L["Twist"])
                or (action == ST.ACTION_HELD and L["Hold seal"])
                or "")
        elseif lost then
            warn = true
            -- Short on purpose: this sits on a bar a few hundred pixels wide and
            -- is read out of the corner of the eye mid-fight. The reason it is
            -- lost (a cooldown landing late) is one of several, and naming that
            -- one made the line too long to take in at a glance.
            --
            -- No colour code in the string any more: the warning colour is a
            -- setting now, and a colour baked into a translated string is one
            -- the player cannot reach and nine locales have to agree on.
            label = L["Twist lost"]
        elseif zone == ST.Z_READY and not fake then
            -- A swing that is due and stays due means auto-attack is off. It is
            -- the classic way to lose a whole rotation without noticing, and
            -- the bar is the only place it shows.
            warn = true
            label = L["Swing ready -- restart your attack"]
        else
            label = ""
        end
        -- The action labels carry their own colour wrappers, so the base colour
        -- only shows through on the warnings. Set either way: a wrapper that
        -- ended leaves the string's own colour behind, and the next warning
        -- would inherit whatever the last action was.
        if warn then
            actionFS:SetTextColor(ST.Color(d.colWarning, 1.00, 0.80, 0.20))
        else
            actionFS:SetTextColor(ST.Color(d.fontColor, 1, 1, 1))
        end
        -- One FontString, two jobs: "press this" and "something is wrong". They
        -- want different sizes -- the warning is a sentence, the action is two
        -- words -- so the font is switched with the text. Only when it actually
        -- differs: this runs on every frame of the bar.
        local want = warn and ST.WarnSize(d) or ST.ActionSize(d)
        if actionFS._vcSize ~= want then
            actionFS._vcSize = want
            local path, outline = ST.FontFace(d)
            actionFS:SetFont(path, want, outline)
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
    local prompt = (action == ST.ACTION_TWIST)
    if not fake then
        if d.sound and prompt and not wasPrompting and now - lastSound > 0.25 then
            lastSound = now
            PlaySoundFile(ST.WINDOW_SOUND, "Master")
        end
        local late = prompt and zone == ST.Z_LATE
        if d.soundLate and late and not wasLate and now - lastLateSound > 0.25 then
            lastLateSound = now
            local id = SOUNDKIT and SOUNDKIT.READY_CHECK
            if id then PlaySound(id, "Master") else PlaySoundFile(ST.WINDOW_SOUND, "Master") end
        end
        wasLate = late
    end
    wasPrompting = prompt
end

-- ---------------------------------------------------------------- build

function ST.Create()
    if ST.frame then return ST.frame end
    local d = ST.DB()

    local frame = CreateFrame("Frame", "VCUI_SealTwist", UIParent)
    ST.frame = frame
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture(BAR_TEX)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    ST.bar = bar

    barBG = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    barBG:SetAllPoints(bar)
    barBG:SetTexture(BAR_TEX)

    -- Four flat edges for the solid border mode. On the FRAME rather than on
    -- the bar, at OVERLAY: an edge parented to the bar and anchored outside it
    -- would be clipped by nothing, but it would also sit under the marks, and a
    -- border under the thing it is framing reads as a rendering fault.
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:Hide()
        borderEdges[i] = t
    end

    -- Only built for the texture mode, but built unconditionally: a frame
    -- created on demand inside a settings handler is a frame created in combat.
    borderFrame = CreateFrame("Frame", nil, frame,
        BackdropTemplateMixin and "BackdropTemplate")
    borderFrame:Hide()

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
    tickJudge  = tickTex(0.90, 0.90, 0.05, 2)   -- judgement comes off cooldown
    tickJudge:Hide()

    -- The deadzone shades the tail of the swing a cast can no longer cross.
    -- ARTWORK, so it sits over the zone shading and under the marks: it is a
    -- statement about the whole tail, and a mark inside it still has to be
    -- readable through it.
    deadzone = bar:CreateTexture(nil, "ARTWORK")
    deadzone:SetPoint("TOPRIGHT",    bar, "TOPRIGHT",    0, 0)
    deadzone:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    deadzone:Hide()

    -- The running global cooldown, drawn along the bottom edge of the bar from
    -- its left. Not a second full-height bar: it answers "how much of this swing
    -- is already spoken for", which is a footnote to the swing rather than a
    -- competing reading of it.
    gcdBar = bar:CreateTexture(nil, "OVERLAY")
    gcdBar:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    gcdBar:SetTexture(BAR_TEX)
    gcdBar:SetVertexColor(0.48, 0.48, 0.48, 0.95)
    gcdBar:Hide()

    leftFS = bar:CreateFontString(nil, "OVERLAY")
    leftFS:SetPoint("LEFT", bar, "LEFT", 4, 0)
    leftFS:SetJustifyH("LEFT")

    rightFS = bar:CreateFontString(nil, "OVERLAY")
    rightFS:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    rightFS:SetJustifyH("RIGHT")

    actionFS = frame:CreateFontString(nil, "OVERLAY")
    actionFS:SetPoint("TOP", bar, "BOTTOM", 0, -4)

    infoFS = frame:CreateFontString(nil, "OVERLAY")
    infoFS:SetPoint("TOP", actionFS, "BOTTOM", 0, -2)
    infoFS:SetTextColor(0.65, 0.65, 0.70)

    rotLabel = frame:CreateFontString(nil, "OVERLAY")
    rotLabel:SetTextColor(0.75, 0.70, 0.85)

    for i = 1, ST.ROT_MAX_STEPS do
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

    -- A container of its own, so the pair can be detached and moved as one. A
    -- CHILD of the main frame even while detached: the indicators say what the
    -- bar is talking about, and a pair still on screen after the bar went away
    -- would be two icons with nothing to belong to.
    sealFrame = CreateFrame("Frame", nil, frame)

    for i = 1, 2 do
        local slot = CreateFrame("Frame", nil, sealFrame)
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints(slot)
        -- Trimmed: the client's own icon border is a fat beige ring that reads
        -- as a different UI at this size.
        slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        slot.cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
        slot.cd:SetAllPoints(slot)
        slot.cd:SetDrawEdge(false)
        slot.cd:SetHideCountdownNumbers(true)

        -- The number lives in its own frame ABOVE the sweep, not in the sweep.
        -- A cooldown frame draws over its parent's regions whatever layer they
        -- claim, so a number parented to the icon spends the last few seconds
        -- behind the wedge counting them down -- and a number parented to the
        -- SWEEP disappears entirely the moment the sweep is switched off.
        slot.textHost = CreateFrame("Frame", nil, slot)
        slot.textHost:SetAllPoints(slot)
        slot.textHost:SetFrameLevel(slot.cd:GetFrameLevel() + 1)
        slot.time = slot.textHost:CreateFontString(nil, "OVERLAY")
        slot.time:SetPoint("BOTTOM", slot, "BOTTOM", 0, 1)
        slot.time:SetTextColor(1, 1, 1)
        slot:Hide()
        sealSlots[i] = slot
    end

    sealFrame.mover = ns:CreateMover(sealFrame, {
        key    = "sealtwisticons",
        label  = L["|cffffffffSEALS|r"],
        db     = d.sealPos,
        fill   = true,
        -- The container's anchor is owned by ST.Layout, which chooses between
        -- the bar edge and the free position. Without this, a global "reset all
        -- positions" would write 0,0 and pin the pair to the middle of the
        -- screen while they are still logically attached to the bar.
        applyPos = function() ST.Layout() end,
        editPreview = function(edit)
            if edit and ST.frame then ST.frame:Show() end
            -- An attached pair has no position of its own, so its box must not
            -- be offered in the global edit pass: dragging it would look like it
            -- worked and be undone by the next layout.
            local db = ST.DB()
            if edit and db and not db.sealDetached then
                ns:SetMoverTempHidden(sealFrame.mover, true)
            end
        end,
    })

    frame.mover = ns:CreateMover(frame, {
        key    = "sealtwist",
        label  = L["|cffffffffSEAL TWIST|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = d,
        width  = max(d.barWidth + 120, 240),
        height = 90,
        onMove = function(x, y)
            ns:Print(format(L["Seal Twist position: x=%.0f, y=%.0f"], x, y))
        end,
        editPreview = function() if ST.frame then ST.frame:Show() end end,
    })

    -- The update driver is its OWN frame, not the bar.
    --
    -- A script on the bar stops the moment the bar is hidden, and the guide has
    -- its own visibility setting: "guide always, bar in combat" would freeze the
    -- icon on whatever it happened to be showing when the fight ended. So the
    -- driver is a bodiless frame that ST.ApplyVisibility switches on whenever
    -- EITHER display wants to be drawn.
    driver = CreateFrame("Frame")
    driver:Hide()
    local acc = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + (elapsed or 0)
        if acc < 0.02 then return end
        acc = 0
        onUpdate()
    end)

    -- The confirmation's glow and text hang off the bar, so they are built once
    -- the bar exists rather than at file load: their own file has no way of
    -- knowing when that happened.
    ST.CreateHitVisuals()
    ST.CreateNextFrame()

    ST.Layout()
    return frame
end

-- Both seals have to exist for the helper to have anything to say -- but the
-- bar is not tied to the swing alone any more. It used to appear only while the
-- tracker held a live swing, which meant it flickered away between pulls, on
-- every target swap, and stayed away entirely on a paladin the seal check had
-- rejected. In combat is the honest condition; the swing decides what the bar
-- shows, not whether it exists.
local function barVisible(d)
    if not (ST.heldName and ST.twistName) then return false end
    -- Practice outranks EVERY condition below, including the master switch. The
    -- trainer is what somebody reaches for before they have turned the helper
    -- on or respecced into it, and a practice run with no bar to time against
    -- is a practice run with nothing in it.
    if ST.PracticeActive() then return true end
    if not d.enabled then return false end
    if d.twoHandSpecOnly and not ST.HasTwoHandSpec() then return false end

    local mode = d.visibility
    if mode == "always" then return true end

    -- A live swing counts as combat. The regen events and the swing tracker do
    -- not agree on the exact frame a pull begins, and the bar going away for two
    -- of them is more noticeable than it staying one frame too long.
    local _, _, active = ns:GetSwing("mainhand")
    local inCombat = active or UnitAffectingCombat("player")
    local sealUp   = ST.hasHeld or ST.hasTwist

    if mode == "seal" then return sealUp end
    if mode == "combatOrSeal" then return inCombat or sealUp end
    return inCombat   -- "combat", and the fallback for an unknown value
end

function ST.ApplyVisibility()
    local d = ST.DB()
    local frame = ST.frame
    if not frame or not d then return end

    -- The unlocked override outranks every condition below it: a frame you
    -- cannot make appear is a frame you cannot place.
    local placing = d.unlocked or ns:IsMoverEditMode()
    local showBar = placing or barVisible(d)
    if showBar then frame:Show() else frame:Hide() end

    -- The driver runs whenever ANYTHING is on screen. Without this the guide
    -- would only be refreshed while the bar happened to be visible, and its own
    -- visibility setting would be a lie whenever the two disagree.
    if driver then
        local wantGuide = placing or (d.naPos and d.naPos.unlocked) or ST.NextVisible()
        if showBar or wantGuide then driver:Show() else driver:Hide() end
        -- The driver is what hides the guide; with it stopped, nothing would.
        if not (showBar or wantGuide) then ST.HideNext() end
    end
end

-- Called when the whole tool is switched off, from a file that must not have to
-- know whether the frame was ever built.
function ST.HideSealMover()
    if sealFrame and sealFrame.mover then sealFrame.mover:Hide() end
end

-- The driver is not a child of anything the teardown hides, so it has to be
-- stopped by name. Left running it would keep asking a disabled tool what to
-- draw, fifty times a second, for the rest of the session.
function ST.StopDriver()
    if driver then driver:Hide() end
end

-- The indicators get their own unlock because they can be somewhere else on the
-- screen entirely. Detaching them is what makes the mover useful, so turning
-- the mover on turns the detachment on with it -- an unlocked box that snaps
-- straight back to the bar edge on release is a control that appears broken.
function ST.SetSealsUnlocked(state)
    local d = ST.DB()
    ST.Create()
    d.sealPos.unlocked = state and true or false
    if d.sealPos.unlocked then
        -- Seed the free position from where the pair is standing RIGHT NOW, so
        -- the first detach does not teleport them to the middle of the screen
        -- and leave the player hunting for the box they just unlocked.
        if not d.sealDetached then
            local x, y = ns:GetCenterOffsets(sealFrame)
            if x and y then d.sealPos.x, d.sealPos.y = x, y end
        end
        d.sealDetached = true
        ST.Layout()
        ST.frame:Show()
        sealFrame.mover:Show()
        ns:Print(L["Seal indicator mover active. |cff9b6cffDrag the purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Test' again to finish."])
    else
        sealFrame.mover:Hide()
        ST.Layout()
        ST.ApplyVisibility()
        ns:Print(L["Seal indicator mover disabled."])
    end
end

function ST.SetUnlocked(state)
    local d = ST.DB()
    d.unlocked = state and true or false
    ST.Create()
    if d.unlocked then
        ST.frame:Show()
        ST.frame.mover:Show()
        ns:Print(L["Seal Twist mover active. |cff9b6cffDrag the purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Test' again to finish."])
    else
        ST.frame.mover:Hide()
        ST.ApplyVisibility()
        ns:Print(L["Seal Twist mover disabled."])
    end
end
