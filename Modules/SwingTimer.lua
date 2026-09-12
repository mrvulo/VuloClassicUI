-- Swing bars restart on the player's own SWING_DAMAGE/SWING_MISSED combat-log lines, not on attack input.
local _, ns = ...
local L = ns.L

-- Every spec of these swings for a living.
local ALWAYS_MELEE = { WARRIOR = true, ROGUE = true }

-- Hybrids: only these talent trees melee. Tree order on this client is
-- Paladin 1 Holy / 2 Protection / 3 Retribution, Shaman 1 Elemental /
-- 2 Enhancement / 3 Restoration, Druid 1 Balance / 2 Feral / 3 Restoration.
local MELEE_TREES = {
    PALADIN = { [2] = true, [3] = true },
    SHAMAN  = { [2] = true },
    DRUID   = { [2] = true },
}

-- Talent trees are the only spec signal this client offers; the tree holding the
-- most points wins. Returns nil while talents are unreadable (very early login,
-- or a character with no points yet), which callers treat as "don't judge".
local function dominantTree()
    -- Was GetTalentTabInfo, reading return slot 3 as the point count. Right for
    -- the original function; the deprecation shim prepends a spec id, so slot 3
    -- is the ICON FILE ID. Measured on a live client it answers 136048 there --
    -- a number, so nothing complained, and "the tree with the most points"
    -- quietly became "the tree with the largest texture id". For a hybrid this
    -- decided melee versus ranged, which is the whole job of this function.
    return ns:DominantTalentTree()
end

local function isMeleeSpec()
    local _, classFile = UnitClass("player")
    if not classFile then return true end   -- unknown at file load; OnEnable re-checks
    if ALWAYS_MELEE[classFile] then return true end
    local trees = MELEE_TREES[classFile]
    if not trees then return false end      -- no melee spec exists for this class
    local tree = dominantTree()
    if not tree then return true end        -- undecided hybrid: don't lock them out
    return trees[tree] == true
end
ns.SwingTimerIsMeleeSpec = isMeleeSpec

-- group "_hidden": no sidebar entry; options are rendered by PlayerCastbar:GetOptions.
local mod = ns:RegisterModule("swingtimer", {
    name        = "Swing Timer",
    group       = "_hidden",
    description = "Weapon swing timer for your melee auto-attacks (any melee class). Shows a main-hand bar and, while dual-wielding, an off-hand bar.",
    defaults = {
        enabled         = false,
        width           = 200,
        height          = 18,
        gap             = 3,
        x               = 0,
        y               = -140,
        unlocked        = false,
        showOffHand     = true,
        showRanged      = true,
        showAimWindow   = true,
        showText        = true,
        onlyWhileActive = true,
        colorPreset     = "blue",
        texture         = "Atrocity",
        bgTexture       = "Atrocity",
        fillAlpha       = 1.0,
        bgAlpha         = 0.9,
    },
})

local GetTime            = GetTime
local UnitClass          = UnitClass
local GetInventoryItemID = GetInventoryItemID
local format             = string.format

local TEX_FILL  = "Interface\\TargetingFrame\\UI-StatusBar"
local TEX_SPARK = "Interface\\AddOns\\VuloClassicUI\\Media\\Castbar\\CastingBarSpark"

local COLOR_PRESETS = {
    blue   = { r = 0.20, g = 0.52, b = 0.95 },
    violet = { r = 0.608, g = 0.424, b = 1.00 },
    cyan   = { r = 0.22, g = 0.78, b = 0.85 },
    green  = { r = 0.30, g = 0.80, b = 0.40 },
    gold   = { r = 0.95, g = 0.75, b = 0.25 },
    red    = { r = 0.90, g = 0.32, b = 0.32 },
}
-- The picked colour wins; colorPreset stays as the fallback so profiles from
-- before the colour picker keep the colour their preset gave them.
local function barColor()
    local c = mod.db.barColor
    if type(c) == "table" and c.r then return c end
    return COLOR_PRESETS[mod.db.colorPreset] or COLOR_PRESETS.blue
end

local function lsmStatusbar(name) return ns.MediaStatusbar(name, TEX_FILL) end
local function fillTexture() return lsmStatusbar(mod.db.texture) end
local function bgTexture()   return lsmStatusbar(mod.db.bgTexture) end

local DEFAULT_TEXTURE = "Atrocity"
local textureValues   = ns.MediaStatusbarValues

-- Tiling must be disabled on the texture object or narrow LSM textures repeat instead of stretching.
local function applyBarTexture(bar)
    local path = fillTexture()
    bar:SetStatusBarTexture(path)
    local t = bar:GetStatusBarTexture()
    if t then
        if t.SetTexture   then t:SetTexture(path)    end
        if t.SetHorizTile then t:SetHorizTile(false) end
        if t.SetVertTile  then t:SetVertTile(false)  end
    end
    local c = barColor()
    bar:SetStatusBarColor(c.r, c.g, c.b, mod.db.fillAlpha or 1)

    if bar.bg then
        bar.bg:SetTexture(bgTexture())
        if bar.bg.SetHorizTile then bar.bg:SetHorizTile(false) end
        if bar.bg.SetVertTile  then bar.bg:SetVertTile(false)  end
        bar.bg:SetVertexColor(0.10, 0.10, 0.12, mod.db.bgAlpha or 0.9)
    end
end

local frame
local mhBar, ohBar, raBar
local eventFrame
local previewActive, previewExpire = false, 0

-- The ranged bar exists for anyone holding a shooting weapon: a hunter's bow
-- or gun, a caster's wand. Read live (the tracker asks the client), so a
-- weapon swap moves the bar in and out through the inventory event.
local function hasRanged()
    return ns.HasRangedWeapon and ns:HasRangedWeapon() or false
end

-- The enable gate runs at ADDON_LOADED, where the client may not report the
-- ranged weapon's speed yet. A hunter, or anyone with something in the
-- ranged slot, is not judged on that answer -- the talent path has the same
-- "don't judge while unreadable" rule.
local function mayHaveRanged()
    if hasRanged() then return true end
    local _, cls = UnitClass("player")
    if cls == "HUNTER" then return true end
    return GetInventoryItemID("player", 18) ~= nil
end

-- The main-hand bar is for melee specs; a hunter or a wand user sees it only
-- while a melee swing is actually running, not as an empty row above the shot.
local function showMainHand()
    if mod.db.unlocked or ns.SwingTimerIsMeleeSpec() then return true end
    return (select(3, ns:GetSwing("mainhand"))) and true or false
end

-- The real swing clock lives in Core/SwingTracker (shared with the paladin
-- seal-twist helper). Preview and unlock run on their own fake swings so that
-- dragging the bars around in town cannot be mistaken for live data by anything
-- else reading the tracker.
-- Pre-filled with plausible speeds: Edit Mode can turn on without ever going
-- through startPreview, and a zero duration would divide by zero on the first
-- frame it draws.
local previewMH = { start = 0, dur = 2.6, active = true }
local previewOH = { start = 0, dur = 1.8, active = true }
local previewRA = { start = 0, dur = 2.9, active = true }
local liveMH    = { start = 0, dur = 0, active = false }
local liveOH    = { start = 0, dur = 0, active = false }
local liveRA    = { start = 0, dur = 0, active = false }

local function isFake()
    return previewActive or (mod.db and mod.db.unlocked) or ns:IsMoverEditMode()
end

-- Scratch tables, deliberately reused: this runs 50x a second per bar.
local function swingState(hand)
    if isFake() then
        if hand == "ranged" then return previewRA end
        return (hand == "offhand") and previewOH or previewMH
    end
    local out = (hand == "ranged") and liveRA or (hand == "offhand") and liveOH or liveMH
    out.start, out.dur, out.active = ns:GetSwing(hand)
    return out
end

local function anySwingActive()
    if isFake() then return previewMH.active or previewOH.active or previewRA.active end
    return (select(3, ns:GetSwing("mainhand"))) or (select(3, ns:GetSwing("offhand")))
        or (select(3, ns:GetSwing("ranged")))
end

local function addBorder(bar)
    local function edge()
        local t = bar:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 0.9)
        return t
    end
    local top, bottom, left, right = edge(), edge(), edge(), edge()
    top:SetPoint("BOTTOMLEFT",  bar, "TOPLEFT",  -1, 0)
    top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT",  1, 0); top:SetHeight(1)
    bottom:SetPoint("TOPLEFT",  bar, "BOTTOMLEFT",  -1, 0)
    bottom:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT",  1, 0); bottom:SetHeight(1)
    left:SetPoint("TOPRIGHT",    bar, "TOPLEFT",     0,  1)
    left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT",  0, -1); left:SetWidth(1)
    right:SetPoint("TOPLEFT",    bar, "TOPRIGHT",    0,  1)
    right:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 0, -1); right:SetWidth(1)
end

local function createBar(parent, labelText)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(fillTexture())
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetColorTexture(0.04, 0.04, 0.05, 0.92)

    addBorder(bar)

    bar.gloss = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.gloss:SetColorTexture(1, 1, 1, 0.06)

    bar.spark = bar:CreateTexture(nil, "OVERLAY")
    bar.spark:SetTexture(TEX_SPARK)
    bar.spark:SetBlendMode("ADD")
    bar.spark:SetWidth(14)
    bar.spark:Hide()

    -- The aim window at the end of a ranged shot: the stretch where moving or
    -- casting holds the shot back. Only the ranged bar shows it.
    bar.aim = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.aim:SetColorTexture(1, 1, 1, 0.16)
    bar.aim:SetPoint("TOPRIGHT",    bar, "TOPRIGHT",    0, 0)
    bar.aim:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bar.aim:SetWidth(1)
    bar.aim:Hide()

    local font = "Fonts\\FRIZQT__.TTF"
    bar.label = bar:CreateFontString(nil, "OVERLAY")
    bar.label:SetFont(font, 11, "OUTLINE")
    bar.label:SetPoint("LEFT", bar, "LEFT", 5, 0)
    bar.label:SetTextColor(1, 1, 1, 1)
    bar.label:SetText(labelText)

    bar.time = bar:CreateFontString(nil, "OVERLAY")
    bar.time:SetFont(font, 11, "OUTLINE")
    bar.time:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    bar.time:SetJustifyH("RIGHT")
    bar.time:SetTextColor(1, 1, 1, 1)
    bar.time:SetText("")

    return bar
end

local function updateBar(bar, sw, t)
    if not sw.active or sw.dur <= 0 then
        bar:SetValue(0)
        bar._timeBucket = -1
        bar.time:SetText("")
        bar.spark:Hide()
        return
    end
    local elapsed = t - sw.start
    local frac, remaining
    if elapsed >= sw.dur then
        -- Expire the bar if no new swing arrived 2s past due (a missed PLAYER_LEAVE_COMBAT).
        if not mod.db.unlocked and elapsed > sw.dur + 2 then
            sw.active = false
            bar:SetValue(0)
            bar._timeBucket = -1
            bar.time:SetText("")
            bar.spark:Hide()
            return
        end
        frac, remaining = 1, 0
    else
        frac, remaining = elapsed / sw.dur, sw.dur - elapsed
    end
    bar:SetValue(frac)
    -- One decimal on the label, fifty ticks a second on the driver: the string
    -- is only rebuilt when the displayed tenth actually moves.
    local bucket = mod.db.showText and math.floor(remaining * 10) or -1
    if bar._timeBucket ~= bucket then
        bar._timeBucket = bucket
        if bucket >= 0 then
            bar.time:SetFormattedText("%.1f", remaining)
        else
            bar.time:SetText("")
        end
    end
    bar.spark:ClearAllPoints()
    bar.spark:SetPoint("CENTER", bar, "LEFT", bar:GetWidth() * frac, 0)
    bar.spark:Show()
    if bar.isRanged and mod.db.showAimWindow then
        local win = ns.RANGED_AIM_WINDOW or 0.7
        local w = bar:GetWidth() * math.min(1, win / sw.dur)
        if w ~= bar._aimW then
            bar._aimW = w
            bar.aim:SetWidth(math.max(1, w))
        end
        bar.aim:Show()
    elseif bar.isRanged then
        bar.aim:Hide()
    end
end

-- Bars stack top-down in the order main hand, off hand, ranged; a bar that
-- does not apply (no second weapon, nothing to shoot with) leaves no gap.
local function layout()
    if not frame then return end
    local w, h, gap = mod.db.width, mod.db.height, mod.db.gap
    local showMH = showMainHand()
    local showOH = (mod.db.showOffHand and ns:IsDualWielding()) or mod.db.unlocked
    local showRA = (mod.db.showRanged and hasRanged()) or mod.db.unlocked
    if not (showMH or showOH or showRA) then showMH = true end
    local rows = (showMH and 1 or 0) + (showOH and 1 or 0) + (showRA and 1 or 0)
    local totalH = h * rows + gap * (rows - 1)

    frame:SetSize(w, totalH)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)

    -- Stack whatever is shown, top down, with no gap for a hidden bar.
    local above
    for _, pair in ipairs({ { mhBar, showMH }, { ohBar, showOH }, { raBar, showRA } }) do
        local bar, shown = pair[1], pair[2]
        bar:ClearAllPoints()
        if shown then
            if above then
                bar:SetPoint("TOPLEFT",  above, "BOTTOMLEFT",  0, -gap)
                bar:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -gap)
            else
                bar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
                bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            end
            above = bar
        end
        bar:SetHeight(h)
        bar:SetShown(shown)
    end
    raBar._aimW = nil

    applyBarTexture(mhBar)
    applyBarTexture(ohBar)
    applyBarTexture(raBar)
    for _, b in ipairs({ mhBar, ohBar, raBar }) do
        b.spark:SetHeight(h + 6)
        b.gloss:ClearAllPoints()
        b.gloss:SetPoint("TOPLEFT",  b, "TOPLEFT",  0, 0)
        b.gloss:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
        b.gloss:SetHeight(math.max(2, h * 0.45))
        b.time:SetShown(mod.db.showText)
    end
end

local function applyVisibility()
    if not frame then return end
    if mod.db.unlocked or ns:IsMoverEditMode() then frame:Show(); return end
    if previewActive then frame:Show(); return end
    if not mod.db.onlyWhileActive then frame:Show(); return end
    if anySwingActive() then frame:Show() else frame:Hide() end
end

local function startPreview()
    if not frame then return end
    if mod.db.unlocked then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local t = GetTime()
    if previewActive then
        previewExpire = t + 4
        return
    end
    if anySwingActive() then return end
    previewMH.start, previewMH.dur, previewMH.active = t, 2.6, true
    previewOH.start, previewOH.dur, previewOH.active = t, 1.8, true
    previewRA.start, previewRA.dur, previewRA.active = t, 2.9, true
    previewActive = true
    previewExpire = t + 4
    frame:Show()
end

local function applyDisplay()
    layout()
    startPreview()
end

local function create()
    if frame then return frame end

    frame = CreateFrame("Frame", "VCUI_SwingTimer", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(mod.db.width, mod.db.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)
    frame:Hide()

    mhBar = createBar(frame, L["MH"])
    ohBar = createBar(frame, L["OH"])
    raBar = createBar(frame, L["RA"])
    raBar.isRanged = true

    frame.mover = ns:CreateMover(frame, {
        key    = "swingtimer",
        label  = L["|cffffffffSWING TIMER|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = mod.db,
        width  = math.max(mod.db.width + 40, 180),
        height = math.max(90, mod.db.height * 3 + 40),
        onMove = function(x, y)
            ns:Print(format(L["Swing Timer position: x=%.0f, y=%.0f"], x, y))
        end,
        editPreview = function() applyVisibility() end,
    })

    local acc = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + (elapsed or 0)
        if acc < 0.02 then return end
        acc = 0
        local t = GetTime()
        if isFake() then
            if t - previewMH.start >= previewMH.dur then previewMH.start = t end
            if t - previewOH.start >= previewOH.dur then previewOH.start = t end
            if t - previewRA.start >= previewRA.dur then previewRA.start = t end
        end
        if previewActive and t > previewExpire then
            previewActive = false
            applyVisibility()
        end
        if mhBar:IsShown() then updateBar(mhBar, swingState("mainhand"), t) end
        if ohBar:IsShown() then updateBar(ohBar, swingState("offhand"),  t) end
        if raBar:IsShown() then updateBar(raBar, swingState("ranged"),   t) end
        -- Edit Mode has to be exempt here as well, not just in applyVisibility:
        -- that one shows the frame, and a hundredth of a second later this hid
        -- it again. A hidden frame stops running OnUpdate, so nothing ever
        -- brought it back and Edit Mode showed a mover box over empty space.
        if not mod.db.unlocked and not previewActive and mod.db.onlyWhileActive
           and not anySwingActive() and not ns:IsMoverEditMode() then
            self:Hide()
        end
    end)

    return frame
end

local function clearBar(bar)
    if not bar then return end
    bar:SetValue(0)
    bar._timeBucket = -1
    bar.time:SetText("")
    bar.spark:Hide()
    bar.aim:Hide()
end

local function clearBars()
    clearBar(mhBar)
    clearBar(ohBar)
    clearBar(raBar)
end

-- The tracker calls this on every swing reset and on leaving combat; a real
-- swing supersedes the settings preview, which is why previewActive is dropped
-- here rather than inside the tracker (which knows nothing about our preview).
local function onSwing(hand)
    if not mod._enabled then return end
    if previewActive then previewActive = false end
    if not (select(3, ns:GetSwing("mainhand"))) and not (select(3, ns:GetSwing("offhand")))
       and not (select(3, ns:GetSwing("ranged"))) then
        clearBars()
    end
    -- A ranged character's main-hand bar comes and goes with its swing.
    if hand ~= "ranged" and not ns.SwingTimerIsMeleeSpec() then layout() end
    applyVisibility()
end

local function onEvent(_, event, arg1)
    if not mod._enabled then return end
    if event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == nil or arg1 == "player" then
            layout()
            applyVisibility()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        layout()
    end
end

local function registerEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", onEvent)
    end
    -- Swing clock events (combat log, enter/leave combat, attack speed) belong to
    -- Core/SwingTracker now; these two are purely about our own layout.
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
end

local function setUnlocked(state)
    mod.db.unlocked = state
    create()
    if state then
        local t = GetTime()
        previewMH.start, previewMH.dur, previewMH.active = t, 2.6, true
        previewOH.start, previewOH.dur, previewOH.active = t, 1.8, true
        previewRA.start, previewRA.dur, previewRA.active = t, 2.9, true
        layout()
        frame:Show()
        frame.mover:Show()
        ns:Print(L["Swing Timer mover active. |cff9b6cffDrag the purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Test' again to finish."])
    else
        frame.mover:Hide()
        clearBars()
        layout()
        applyVisibility()
        ns:Print(L["Swing Timer mover disabled."])
    end
end

function mod:OnEnable()
    -- An unlock that survives a reload is a trap: setUnlocked is the only thing
    -- that shows the mover and enables the mouse, and it does not run on load.
    -- The bars would sit on screen ignoring every visibility rule, with nothing
    -- to grab and no hint where they came from.
    if mod.db then mod.db.unlocked = false end

    -- Deferred on purpose: disabling a module from inside its own OnEnable
    -- would tear down state the rest of this function is still setting up.
    local function bailOut()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() if ns.SafeDisable then ns:SafeDisable(mod) end end)
        end
    end

    -- Off for everyone until asked for; the first run only records that choice.
    local pref = VuloClassicUICharDB and VuloClassicUICharDB.modEnabled
    if not (pref and pref.swingtimer ~= nil) then
        ns:SetModuleEnabledPref("swingtimer", false)
        bailOut()
        return
    end

    -- A swing timer means nothing without auto-attacks to time: melee swings
    -- for a melee spec, shots for anyone holding a ranged weapon. A caster
    -- with neither stays shut even if an old saved preference says otherwise.
    -- Say so, and record it: switching a module off behind the player's back
    -- while the sidebar keeps showing it as enabled gives them nothing to go
    -- on, and leaving the preference alone repeats the whole thing on every
    -- login.
    if not isMeleeSpec() and not mayHaveRanged() then
        ns:SetModuleEnabledPref("swingtimer", false)
        ns:Print(L["Swing Timer switched off: it only tracks melee auto-attacks and ranged shots, and this character has neither."])
        bailOut()
        return
    end

    -- Migrate texture names that no longer exist in the bundled set.
    -- accepts foreign shared-media choices too; only truly unresolvable names reset
    if not ns.MediaStatusbarValid(mod.db.texture)   then mod.db.texture   = DEFAULT_TEXTURE end
    if not ns.MediaStatusbarValid(mod.db.bgTexture) then mod.db.bgTexture = DEFAULT_TEXTURE end
    create()
    ns:AcquireSwingTracker("swingtimer", onSwing)
    layout()
    registerEvents()
    applyVisibility()
end

function mod:OnDisable()
    ns:ReleaseSwingTracker("swingtimer")
    if eventFrame then eventFrame:UnregisterAllEvents() end
    clearBars()
    if frame then frame:Hide() end
end

function mod:GetOptions()
    local items = {}

    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaShows when your next auto-attack lands: main hand, off hand while dual-wielding, and the ranged shot while a bow, gun or wand is equipped. The bar fills up toward the swing; the number is the time left. The light stretch at the end of the ranged bar is the aim: moving or casting there holds the shot back.|r"] })

    table.insert(items, { type = "toggle", label = L["Enable swing timer"],
        get = function() return ns:IsModuleEnabled("swingtimer") end,
        set = function(_, v) if ns.ToggleModule then ns:ToggleModule("swingtimer", v) end end })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", label = L["Unlock / Test"], width = 130,
              onClick = function() setUnlocked(not mod.db.unlocked) end },
            { type = "button", label = L["Center Position"], width = 150,
              onClick = function()
                  mod.db.x, mod.db.y = 0, -140
                  layout()
              end },
        },
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Display"] })
    table.insert(items, {
        type = "toggle", label = L["Show off-hand bar (while dual-wielding)"],
        get = function() return mod.db.showOffHand end,
        set = function(_, v) mod.db.showOffHand = v; applyDisplay() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show ranged bar"],
        tooltip = L["The auto shot or wand shoot clock, shown while a ranged weapon is equipped."],
        get = function() return mod.db.showRanged end,
        set = function(_, v) mod.db.showRanged = v; applyDisplay() end,
        subOptions = {
            { type = "toggle", label = L["Mark the aim window"],
              tooltip = L["Brightens the last part of the ranged bar: a shot fired from there is delayed by moving or casting."],
              get = function() return mod.db.showAimWindow end,
              set = function(_, v) mod.db.showAimWindow = v; applyDisplay() end },
        },
    })
    table.insert(items, {
        type = "toggle", label = L["Show time remaining"],
        get = function() return mod.db.showText end,
        set = function(_, v) mod.db.showText = v; applyDisplay() end,
    })
    table.insert(items, {
        type = "toggle", label = L["Only show while attacking"],
        tooltip = L["Hides the bars unless you're auto-attacking. Turn off to always show them."],
        get = function() return mod.db.onlyWhileActive end,
        set = function(_, v) mod.db.onlyWhileActive = v; applyVisibility() end,
    })
    table.insert(items, {
        type = "color", label = L["Bar color"], width = 240,
        get = function() return barColor() end,
        set = function(r, g, b)
            mod.db.barColor = { r = r, g = g, b = b }
            applyDisplay()
        end,
    })
    table.insert(items, {
        type = "dropdown", label = L["Foreground texture"],
        width = 240,
        values = textureValues(),
        get = function() return mod.db.texture end,
        set = function(_, v) mod.db.texture = v; applyDisplay() end,
    })
    table.insert(items, {
        type = "slider", label = L["Foreground transparency"],
        min = 0, max = 100, step = 5,
        get = function() return math.floor((mod.db.fillAlpha or 1) * 100 + 0.5) end,
        set = function(_, v) mod.db.fillAlpha = v / 100; applyDisplay() end,
    })
    table.insert(items, {
        type = "dropdown", label = L["Background texture"],
        width = 240,
        values = textureValues(),
        get = function() return mod.db.bgTexture end,
        set = function(_, v) mod.db.bgTexture = v; applyDisplay() end,
    })
    table.insert(items, {
        type = "slider", label = L["Background transparency"],
        min = 0, max = 100, step = 5,
        get = function() return math.floor((mod.db.bgAlpha or 0.9) * 100 + 0.5) end,
        set = function(_, v) mod.db.bgAlpha = v / 100; applyDisplay() end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Size"] })
    table.insert(items, {
        type = "slider", label = L["Width"],
        min = 100, max = 400, step = 5,
        get = function() return mod.db.width end,
        set = function(_, v) mod.db.width = v; applyDisplay() end,
    })
    table.insert(items, {
        type = "slider", label = L["Height"],
        min = 10, max = 36, step = 1,
        get = function() return mod.db.height end,
        set = function(_, v) mod.db.height = v; applyDisplay() end,
    })
    table.insert(items, {
        type = "slider", label = L["Gap between bars"],
        min = 0, max = 12, step = 1,
        get = function() return mod.db.gap end,
        set = function(_, v) mod.db.gap = v; applyDisplay() end,
    })

    return items
end

ns:RegisterSlash({ key = "SWINGTEST", commands = { "/swingtest" },
    desc = "Run a test swing to check the swing timer.",
    module = "swingtimer",
})
ns.Slash.SWINGTEST = function(msg)
    if msg == "debug" then
        local override = (ns.LSM and ns.LSM.GetGlobal) and ns.LSM:GetGlobal("statusbar")
        ns:Print(string.format("SwingTimer fg '%s' -> %s", tostring(mod.db.texture), tostring(fillTexture())))
        ns:Print(string.format("SwingTimer bg '%s' -> %s", tostring(mod.db.bgTexture), tostring(bgTexture())))
        ns:Print(string.format("LSM statusbar global override = %s", tostring(override)))
        return
    end
    setUnlocked(not mod.db.unlocked)
end
