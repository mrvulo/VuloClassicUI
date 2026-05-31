-- =========================================================
-- VuloClassicUI / Modules / SwingTimer
-- Weapon swing timer bars (main hand / off hand) for melee auto-attacks.
--
-- How it works:
--   * UnitAttackSpeed("player") gives the current MH/OH swing durations.
--   * The combat log (SWING_DAMAGE / SWING_MISSED from the player) tells us
--     exactly when a hand swings -> we restart that hand's bar.
--   * PLAYER_ENTER_COMBAT / PLAYER_LEAVE_COMBAT mark auto-attack start/stop.
--   * UNIT_ATTACK_SPEED rescales an in-progress swing on haste changes.
--
-- The off-hand bar only appears while dual-wielding, so it's most relevant
-- for Rogue / Warrior (hence the "Class" group).
-- =========================================================
local _, ns = ...
local L = ns.L

-- group "_hidden": no own sidebar entry. The options live as a section inside
-- the Player Castbar module (see PlayerCastbar:GetOptions). The timer itself
-- runs for every class (the off-hand bar simply only shows while dual-wielding).
local mod = ns:RegisterModule("swingtimer", {
    name        = "Swing Timer",
    group       = "_hidden",
    description = "Weapon swing timer for your melee auto-attacks (any melee class). Shows a main-hand bar and, while dual-wielding, an off-hand bar.",
    defaults = {
        enabled         = true,
        width           = 200,
        height          = 18,
        gap             = 3,
        x               = 0,
        y               = -140,
        unlocked        = false,
        showOffHand     = true,      -- show OH bar while dual-wielding
        showText        = true,      -- show the remaining-time number
        onlyWhileActive = true,      -- hide the frame unless you're swinging
        colorPreset     = "blue",    -- matches the reference screenshot
        texture         = "Atrocity",-- foreground (fill) statusbar texture
        bgTexture       = "Atrocity",-- background statusbar texture
        fillAlpha       = 1.0,       -- foreground transparency (0..1)
        bgAlpha         = 0.9,       -- background transparency (0..1)
    },
})

-- =========================================================
-- Constants / locals
-- =========================================================
local GetTime         = GetTime
local UnitAttackSpeed = UnitAttackSpeed
local UnitGUID        = UnitGUID
local CLGetInfo       = CombatLogGetCurrentEventInfo
local format          = string.format

local TEX_FILL  = "Interface\\TargetingFrame\\UI-StatusBar"  -- neutral white -> tints cleanly
local TEX_SPARK = "Interface\\AddOns\\VuloClassicUI\\Media\\Castbar\\CastingBarSpark"

local COLOR_PRESETS = {
    blue   = { r = 0.20, g = 0.52, b = 0.95 },
    violet = { r = 0.608, g = 0.424, b = 1.00 },
    cyan   = { r = 0.22, g = 0.78, b = 0.85 },
    green  = { r = 0.30, g = 0.80, b = 0.40 },
    gold   = { r = 0.95, g = 0.75, b = 0.25 },
    red    = { r = 0.90, g = 0.32, b = 0.32 },
}
local function barColor()
    return COLOR_PRESETS[mod.db.colorPreset] or COLOR_PRESETS.blue
end

-- Resolve a statusbar texture by LibSharedMedia name. IMPORTANT: we read from
-- the HashTable directly instead of LSM:Fetch — Fetch honours a global texture
-- override (set by some skin addons), which would make every choice resolve to
-- the same texture. HashTable always returns exactly the chosen one.
local function lsmStatusbar(name)
    if ns.LSM and name then
        local hash = ns.LSM:HashTable("statusbar")
        local path = hash and hash[name]
        if path and path ~= "" then return path end
    end
    return TEX_FILL
end
local function fillTexture() return lsmStatusbar(mod.db.texture) end
local function bgTexture()   return lsmStatusbar(mod.db.bgTexture) end

-- The bundled bar textures (Media\textures), registered in Core/MediaRegistry.
-- The picker is limited to these on purpose — no Blizzard default, no other
-- addons' textures.
local BUNDLED_TEXTURES = {
    "Atrocity", "Beautiful", "Divide", "Fade", "Fade Right", "Glass",
    "Gradient", "Gradient (B-T)", "Gradient (R-L)", "Gradient (T-B)",
    "Matte", "Melli", "Plating", "Sheer", "Soft Line",
    "Thin Line (Top)", "Thin Line (Bottom)",
}
local DEFAULT_TEXTURE = "Atrocity"

local function isBundledTexture(name)
    for _, n in ipairs(BUNDLED_TEXTURES) do
        if n == name then return true end
    end
    return false
end

-- Dropdown values: only the bundled Media\textures bars.
local function textureValues()
    local vals = {}
    for _, name in ipairs(BUNDLED_TEXTURES) do
        vals[#vals + 1] = { value = name, text = name }
    end
    return vals
end

-- Apply the foreground (fill) + background textures, colours and transparency
-- to a bar. Robust: re-set on the texture object and disable tiling so narrow
-- LSM textures don't repeat.
local function applyBarTexture(bar)
    -- Foreground (fill)
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

    -- Background
    if bar.bg then
        bar.bg:SetTexture(bgTexture())
        if bar.bg.SetHorizTile then bar.bg:SetHorizTile(false) end
        if bar.bg.SetVertTile  then bar.bg:SetVertTile(false)  end
        bar.bg:SetVertexColor(0.10, 0.10, 0.12, mod.db.bgAlpha or 0.9)
    end
end

local playerGUID
local dualWield = false

-- swing state for each hand
local mh = { start = 0, dur = 0, active = false }
local oh = { start = 0, dur = 0, active = false }

local frame          -- container (movable)
local mhBar, ohBar   -- the two StatusBars
local eventFrame
local previewActive, previewExpire = false, 0  -- short demo when settings change

-- =========================================================
-- Swing math
-- =========================================================
local function recomputeDualWield()
    local _, offSpeed = UnitAttackSpeed("player")
    dualWield = (offSpeed ~= nil and offSpeed > 0)
end

local function resetMH()
    local mainSpeed = UnitAttackSpeed("player")
    if not mainSpeed or mainSpeed <= 0 then return end
    previewActive = false  -- real swing supersedes a settings preview
    mh.start, mh.dur, mh.active = GetTime(), mainSpeed, true
end

local function resetOH()
    local _, offSpeed = UnitAttackSpeed("player")
    if not offSpeed or offSpeed <= 0 then return end
    previewActive = false
    oh.start, oh.dur, oh.active = GetTime(), offSpeed, true
end

-- Haste changed mid-swing: keep the same elapsed fraction with the new speed.
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

-- =========================================================
-- Visuals
-- =========================================================
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

    -- subtle top gloss for a glossy look
    bar.gloss = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.gloss:SetColorTexture(1, 1, 1, 0.06)

    bar.spark = bar:CreateTexture(nil, "OVERLAY")
    bar.spark:SetTexture(TEX_SPARK)
    bar.spark:SetBlendMode("ADD")
    bar.spark:SetWidth(14)
    bar.spark:Hide()

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
        bar.time:SetText("")
        bar.spark:Hide()
        return
    end
    local elapsed = t - sw.start
    local frac, remaining
    if elapsed >= sw.dur then
        -- Safety net: if no new swing arrived well past the expected time
        -- (e.g. PLAYER_LEAVE_COMBAT was missed), let the bar expire.
        if not mod.db.unlocked and elapsed > sw.dur + 2 then
            sw.active = false
            bar:SetValue(0)
            bar.time:SetText("")
            bar.spark:Hide()
            return
        end
        frac, remaining = 1, 0
    else
        frac, remaining = elapsed / sw.dur, sw.dur - elapsed
    end
    bar:SetValue(frac)
    bar.time:SetText(mod.db.showText and format("%.1f", remaining) or "")
    bar.spark:ClearAllPoints()
    bar.spark:SetPoint("CENTER", bar, "LEFT", bar:GetWidth() * frac, 0)
    bar.spark:Show()
end

local function layout()
    if not frame then return end
    local w, h, gap = mod.db.width, mod.db.height, mod.db.gap
    local showOH = (mod.db.showOffHand and dualWield) or mod.db.unlocked
    local totalH = showOH and (h * 2 + gap) or h

    frame:SetSize(w, totalH)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)

    mhBar:ClearAllPoints()
    mhBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    mhBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    mhBar:SetHeight(h)

    ohBar:ClearAllPoints()
    ohBar:SetPoint("TOPLEFT",  mhBar, "BOTTOMLEFT",  0, -gap)
    ohBar:SetPoint("TOPRIGHT", mhBar, "BOTTOMRIGHT", 0, -gap)
    ohBar:SetHeight(h)
    ohBar:SetShown(showOH)

    applyBarTexture(mhBar)
    applyBarTexture(ohBar)
    for _, b in ipairs({ mhBar, ohBar }) do
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
    if mod.db.unlocked then frame:Show(); return end
    if previewActive then frame:Show(); return end
    if not mod.db.onlyWhileActive then frame:Show(); return end
    if mh.active or oh.active then frame:Show() else frame:Hide() end
end

-- Briefly show animated demo bars so a settings change is visible even when
-- you're not currently attacking. Skipped in combat (the real bars show then)
-- and when the test/unlock mover is active (those bars are already visible).
local function startPreview()
    if not frame then return end
    if mod.db.unlocked then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local t = GetTime()
    if previewActive then
        previewExpire = t + 4  -- keep extending while the user tweaks settings
        return
    end
    if mh.active or oh.active then return end  -- real bars already showing (attacking)
    mh.start, mh.dur, mh.active = t, 2.6, true
    oh.start, oh.dur, oh.active = t, 1.8, true
    previewActive = true
    previewExpire = t + 4
    frame:Show()
end

-- Apply a display change (layout) and show a short preview if hidden.
local function applyDisplay()
    layout()
    startPreview()
end

-- =========================================================
-- Build (once)
-- =========================================================
local function create()
    if frame then return frame end

    frame = CreateFrame("Frame", "VCUI_SwingTimer", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(mod.db.width, mod.db.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)
    frame:Hide()

    mhBar = createBar(frame, L["MH"])
    ohBar = createBar(frame, L["OH"])

    frame.mover = ns:CreateMover(frame, {
        label  = L["|cffffffffSWING TIMER|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = mod.db,
        width  = math.max(mod.db.width + 40, 180),
        height = math.max(70, mod.db.height * 2 + 40),
        onMove = function(x, y)
            ns:Print(format(L["Swing Timer position: x=%.0f, y=%.0f"], x, y))
        end,
    })

    frame:SetScript("OnUpdate", function(self)
        local t = GetTime()
        if mod.db.unlocked or previewActive then
            -- demo loop so the bars animate (positioning / settings preview)
            if t - mh.start >= mh.dur then mh.start = t end
            if t - oh.start >= oh.dur then oh.start = t end
        end
        if previewActive and t > previewExpire then
            previewActive = false
            mh.active, oh.active = false, false
            applyVisibility()
        end
        updateBar(mhBar, mh, t)
        if ohBar:IsShown() then updateBar(ohBar, oh, t) end
        -- Auto-hide once both hands have expired (covers a missed leave-combat)
        if not mod.db.unlocked and not previewActive and mod.db.onlyWhileActive
           and not mh.active and not oh.active then
            self:Hide()
        end
    end)

    return frame
end

-- =========================================================
-- Events
-- =========================================================
local function onCombatLog()
    local _, subevent, _, sourceGUID = CLGetInfo()
    if sourceGUID ~= playerGUID then return end
    if subevent == "SWING_DAMAGE" then
        local isOffHand = select(21, CLGetInfo())
        if isOffHand then resetOH() else resetMH() end
        applyVisibility()
    elseif subevent == "SWING_MISSED" then
        -- isOffHand is param 13 (or 14 when an amount is present); check both.
        local p13, p14 = select(13, CLGetInfo())
        if (p13 == true) or (p14 == true) then resetOH() else resetMH() end
        applyVisibility()
    end
end

local function clearBars()
    mh.active, oh.active = false, false
    if mhBar then mhBar:SetValue(0); mhBar.time:SetText(""); mhBar.spark:Hide() end
    if ohBar then ohBar:SetValue(0); ohBar.time:SetText(""); ohBar.spark:Hide() end
end

local function onEvent(_, event, arg1)
    if not mod._enabled then return end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        onCombatLog()
    elseif event == "PLAYER_ENTER_COMBAT" then
        recomputeDualWield()
        resetMH()
        if dualWield then resetOH() end
        applyVisibility()
    elseif event == "PLAYER_LEAVE_COMBAT" then
        clearBars()
        applyVisibility()
    elseif event == "UNIT_ATTACK_SPEED" then
        rescale()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == nil or arg1 == "player" then
            recomputeDualWield()
            layout()
            applyVisibility()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        playerGUID = UnitGUID("player")
        recomputeDualWield()
        layout()
    end
end

local function registerEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", onEvent)
    end
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("PLAYER_ENTER_COMBAT")
    eventFrame:RegisterEvent("PLAYER_LEAVE_COMBAT")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    if eventFrame.RegisterUnitEvent then
        eventFrame:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
    else
        eventFrame:RegisterEvent("UNIT_ATTACK_SPEED")
    end
end

-- =========================================================
-- Unlock / test
-- =========================================================
local function setUnlocked(state)
    mod.db.unlocked = state
    create()
    if state then
        local t = GetTime()
        mh.start, mh.dur, mh.active = t, 2.6, true
        oh.start, oh.dur, oh.active = t, 1.8, true
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

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    playerGUID = UnitGUID("player")
    -- Migrate old/removed texture choices (e.g. "Blizzard") to a bundled one
    if not isBundledTexture(mod.db.texture)   then mod.db.texture   = DEFAULT_TEXTURE end
    if not isBundledTexture(mod.db.bgTexture) then mod.db.bgTexture = DEFAULT_TEXTURE end
    create()
    recomputeDualWield()
    layout()
    registerEvents()
    applyVisibility()
end

function mod:OnDisable()
    if eventFrame then eventFrame:UnregisterAllEvents() end
    clearBars()
    if frame then frame:Hide() end
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local items = {}

    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaShows when your next melee auto-attack lands (any melee class). The off-hand bar only appears while dual-wielding. The bar fills up toward the swing; the number is the time left.|r"] })

    table.insert(items, { type = "toggle", label = L["Enable swing timer"],
        get = function() return mod.db.enabled end,
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
        type = "dropdown", label = L["Bar color"],
        width = 240,
        values = {
            { value = "blue",   text = L["Blue"] },
            { value = "violet", text = L["Violet"] },
            { value = "cyan",   text = L["Cyan"] },
            { value = "green",  text = L["Green"] },
            { value = "gold",   text = L["Gold"] },
            { value = "red",    text = L["Red"] },
        },
        get = function() return mod.db.colorPreset end,
        set = function(_, v) mod.db.colorPreset = v; applyDisplay() end,
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

-- =========================================================
-- Slash test
-- =========================================================
SLASH_VCUISWING1 = "/swingtest"
SlashCmdList.VCUISWING = function(msg)
    if msg == "debug" then
        local override = (ns.LSM and ns.LSM.GetGlobal) and ns.LSM:GetGlobal("statusbar")
        ns:Print(string.format("SwingTimer fg '%s' -> %s", tostring(mod.db.texture), tostring(fillTexture())))
        ns:Print(string.format("SwingTimer bg '%s' -> %s", tostring(mod.db.bgTexture), tostring(bgTexture())))
        ns:Print(string.format("LSM statusbar global override = %s", tostring(override)))
        return
    end
    setUnlocked(not mod.db.unlocked)
end
