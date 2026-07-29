-- Movable HUD resource bar (mana / rage / energy / focus).
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("powerbar", {
    name        = "Power Bar",
    group       = "HUD",
    description = "A movable resource bar for your character. The power type follows your class automatically (Mana / Rage / Energy) — and for Druids it switches with your form: Bear = Rage, Cat = Energy, otherwise Mana.",
    defaults = {
        enabled    = true,
        width      = 220,
        height     = 20,
        x          = 0,
        y          = -200,
        unlocked   = false,
        texture    = "Atrocity",
        textMode   = "currentmax",
        fontSize   = 12,
        borderSize = 1,
        textAnchor = "CENTER",
        textX      = 0,
        textY      = 0,
        textColor  = { r = 1, g = 1, b = 1 },

        visibility    = "always",
        fadeAlpha     = 20,
        groupVis      = "any",
        onlyInstances = false,
        hideMounted   = false,
        hideNoTarget  = false,
        hideFull      = false,
        fadeOOC       = false,
        oocAlpha      = 40,

        colorMode     = "power",
        customColor   = { r = 0.25, g = 0.45, b = 0.95 },
        gradient      = false,
        gradientColor = { r = 0, g = 0, b = 0 },
        borderColor   = { r = 0, g = 0, b = 0 },
        bgColor       = { r = 0.05, g = 0.05, b = 0.06 },
        bgAlpha       = 0.85,
        smooth        = false,

        hashMarks      = "",
        hashPct        = true,
        hashWidth      = 1,
        hashColor      = { r = 0, g = 0, b = 0 },
        thresholdOn    = false,
        threshold      = 20,
        thresholdPct   = true,
        thresholdDir   = "below",
        thresholdColor = { r = 0.9, g = 0.2, b = 0.2 },
        thresholdText  = false,
    },
})

local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local format, floor = string.format, math.floor

-- Keyed by the UnitPowerType token.
local POWER_COLORS = {
    MANA        = { r = 0.25, g = 0.45, b = 0.95 },
    RAGE        = { r = 0.85, g = 0.22, b = 0.22 },
    ENERGY      = { r = 0.95, g = 0.85, b = 0.25 },
    FOCUS       = { r = 0.95, g = 0.55, b = 0.25 },
    RUNIC_POWER = { r = 0.30, g = 0.70, b = 0.90 },
}
local DEFAULT_COLOR = POWER_COLORS.MANA

local DEFAULT_TEXTURE = "Atrocity"
local lsmStatusbar   = ns.MediaStatusbar
local textureValues  = ns.MediaStatusbarValues

local function textModeValues()
    return {
        { value = "none",       text = L["No text"] },
        { value = "current",    text = L["Current value"] },
        { value = "currentmax", text = L["Current / Max"] },
        { value = "percent",    text = L["Percent"] },
        { value = "full",       text = L["Current / Max (%)"] },
    }
end

local frame, bar, barText, borderEdges

local function applyFont()
    if not barText then return end
    if ns.UI and ns.UI.Font then
        ns.UI.Font(barText, mod.db.fontSize, "OUTLINE")
    else
        barText:SetFont(STANDARD_TEXT_FONT, mod.db.fontSize, "OUTLINE")
    end
    local c = mod.db.textColor or { r = 1, g = 1, b = 1 }
    barText:SetTextColor(c.r or 1, c.g or 1, c.b or 1)
end

local function currentColor()
    local d = mod.db
    if d.colorMode == "custom" and d.customColor then return d.customColor end
    if d.colorMode == "class" then
        local _, cls = UnitClass("player")
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        if c then return c end
    end
    local _, token = UnitPowerType("player")
    return POWER_COLORS[token] or DEFAULT_COLOR
end

local bgTex

local function applyAppearance()
    if not bar then return end
    local d = mod.db
    bar:SetStatusBarTexture(lsmStatusbar(d.texture))
    local t = bar:GetStatusBarTexture()
    if t and t.SetHorizTile then t:SetHorizTile(false); t:SetVertTile(false) end
    local c = currentColor()
    bar:SetStatusBarColor(c.r, c.g, c.b)
    if t and t.SetGradient and CreateColor then
        if d.gradient then
            local g2 = d.gradientColor or { r = 0, g = 0, b = 0 }
            t:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(g2.r, g2.g, g2.b, 1))
        else
            t:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
        end
    end
    if bgTex then
        local bc = d.bgColor or { r = 0.05, g = 0.05, b = 0.06 }
        bgTex:SetColorTexture(bc.r, bc.g, bc.b, d.bgAlpha or 0.85)
    end
    applyFont()
end

local function applyBorder()
    if not frame or not borderEdges then return end
    local c = mod.db.borderColor or ns.COLORS.borderDark or { r = 0, g = 0, b = 0 }
    ns.LayoutEdges(borderEdges, frame, mod.db.borderSize or 0, c.r, c.g, c.b, 1, 0)
end

local applyHashes   -- forward declaration: assigned below, captured as an upvalue here

local function applySize()
    if not frame then return end
    frame:SetSize(ns:PixelSnap(mod.db.width, frame), ns:PixelSnap(mod.db.height, frame))
    applyBorder()
    if applyHashes then applyHashes() end
end

local function applyPos()
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        ns:PixelSnap(mod.db.x or 0, frame), ns:PixelSnap(mod.db.y or 0, frame))
end

local function applyText()
    if not barText or not bar then return end
    barText:ClearAllPoints()
    local anchor = mod.db.textAnchor or "CENTER"
    local ox, oy = mod.db.textX or 0, mod.db.textY or 0
    if anchor == "LEFT" then
        barText:SetPoint("LEFT", bar, "LEFT", 4 + ox, oy)
        barText:SetJustifyH("LEFT")
    elseif anchor == "RIGHT" then
        barText:SetPoint("RIGHT", bar, "RIGHT", -4 + ox, oy)
        barText:SetJustifyH("RIGHT")
    else
        barText:SetPoint("CENTER", bar, "CENTER", ox, oy)
        barText:SetJustifyH("CENTER")
    end
end

local hashPool = {}
function applyHashes()
    for _, t in ipairs(hashPool) do t:Hide() end
    if not bar then return end
    local d = mod.db
    local list = d.hashMarks
    if not list or list == "" then return end
    local w = bar:GetWidth() or 0
    if w <= 0 then return end
    local i = 0
    for numStr in tostring(list):gmatch("[%d%.]+") do
        local v = tonumber(numStr)
        local frac
        if v then
            if d.hashPct then
                frac = v / 100
            else
                local mx = UnitPowerMax("player") or 0
                frac = mx > 0 and v / mx or nil
            end
        end
        if frac and frac > 0 and frac < 1 then
            i = i + 1
            local t = hashPool[i]
            if not t then t = bar:CreateTexture(nil, "ARTWORK", nil, 2); hashPool[i] = t end
            local c = d.hashColor or { r = 0, g = 0, b = 0 }
            local hw = d.hashWidth or 1
            t:SetColorTexture(c.r, c.g, c.b, 0.9)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", bar, "TOPLEFT", w * frac - hw / 2, 0)
            t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", w * frac - hw / 2, 0)
            t:SetWidth(hw)
            t:Show()
        end
    end
end

local smoothTicker, smoothTarget
local function ensureSmooth()
    if smoothTicker then return end
    smoothTicker = CreateFrame("Frame"); smoothTicker:Hide()
    smoothTicker:SetScript("OnUpdate", function(self, e)
        if not bar or smoothTarget == nil then self:Hide(); return end
        local cur = bar:GetValue()
        local diff = smoothTarget - cur
        if math.abs(diff) < 0.5 then
            bar:SetValue(smoothTarget); self:Hide(); return
        end
        bar:SetValue(cur + diff * math.min(1, e * 12))
    end)
end

local updateVisibility   -- forward declaration: assigned below, captured as an upvalue here

local function updateValue()
    if not bar then return end
    local d = mod.db
    local cur = UnitPower("player") or 0
    local max = UnitPowerMax("player") or 0
    if max <= 0 then max = 1 end
    bar:SetMinMaxValues(0, max)
    if d.smooth then
        ensureSmooth()
        smoothTarget = cur
        smoothTicker:Show()
    else
        bar:SetValue(cur)
    end

    local c = currentColor()
    local tc = d.textColor or { r = 1, g = 1, b = 1 }
    if d.thresholdOn then
        local ref = d.thresholdPct and (cur / max * 100) or cur
        local hit = (d.thresholdDir == "above") and (ref >= (d.threshold or 20))
            or (d.thresholdDir ~= "above") and (ref <= (d.threshold or 20))
        if hit then
            if d.thresholdText then tc = d.thresholdColor or tc
            else c = d.thresholdColor or c end
        end
    end
    bar:SetStatusBarColor(c.r, c.g, c.b)

    if not barText then return end
    barText:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1)
    local mode = d.textMode
    if mode == "none" then
        barText:SetText("")
    elseif mode == "current" then
        barText:SetText(tostring(cur))
    elseif mode == "percent" then
        barText:SetText(floor(cur / max * 100 + 0.5) .. "%")
    elseif mode == "full" then
        barText:SetText(format("%d / %d  (%d%%)", cur, max, floor(cur / max * 100 + 0.5)))
    else
        barText:SetText(format("%d / %d", cur, max))
    end
    if updateVisibility then updateVisibility() end
end

local function updatePowerType()
    applyAppearance()
    updateValue()
end

function updateVisibility()
    if not frame or not mod.active then return end
    local d = mod.db
    if d.unlocked then frame:Show(); frame:SetAlpha(1); return end
    local show = true
    if d.onlyInstances and not IsInInstance() then show = false end
    if show and d.hideMounted and IsMounted and IsMounted() then show = false end
    if show and d.hideNoTarget and not UnitExists("target") then show = false end
    local grp = d.groupVis
    if show and grp and grp ~= "any" then
        if grp == "group" then show = IsInGroup()
        elseif grp == "raid" then show = IsInRaid()
        elseif grp == "party" then show = IsInGroup() and not IsInRaid()
        elseif grp == "solo" then show = not IsInGroup() end
    end
    if show and d.hideFull and not UnitAffectingCombat("player") then
        local cur, mx = UnitPower("player") or 0, UnitPowerMax("player") or 0
        if mx > 0 and cur >= mx then show = false end
    end
    local m = d.visibility
    if show then
        if m == "combat" then show = UnitAffectingCombat("player")
        elseif m == "noncombat" then show = not UnitAffectingCombat("player") end
    end
    if not show then frame:Hide(); return end
    frame:Show()
    if m == "mouseover" then
        frame:SetAlpha(frame:IsMouseOver(8, -8, -8, 8) and 1 or (d.fadeAlpha or 20) / 100)
    elseif d.fadeOOC and not UnitAffectingCombat("player") then
        frame:SetAlpha((d.oocAlpha or 40) / 100)
    else
        frame:SetAlpha(1)
    end
end

-- Mouseover and mounted state fire no events; a slow ticker polls them instead.
local visTicker
local function updateVisTicker()
    local d = mod.db
    local need = mod.active and (d.visibility == "mouseover" or d.hideMounted)
    if need then
        if not visTicker then
            visTicker = CreateFrame("Frame")
            visTicker._acc = 0
            visTicker:SetScript("OnUpdate", function(self, e)
                self._acc = self._acc + e
                if self._acc < 0.2 then return end
                self._acc = 0
                updateVisibility()
            end)
        end
        visTicker:Show()
    elseif visTicker then
        visTicker:Hide()
    end
end

local function createBorder()
    borderEdges = ns.MakeEdges(frame, "OVERLAY")
end

local function build()
    if frame then return frame end
    frame = CreateFrame("Frame", "VCUIPowerBar", UIParent)
    frame:SetSize(mod.db.width, mod.db.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
    frame:SetFrameStrata("MEDIUM")

    bgTex = frame:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(frame)
    bgTex:SetColorTexture(0.05, 0.05, 0.06, 0.85)

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetAllPoints(frame)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    createBorder()

    barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    applyFont()

    frame.mover = ns:CreateMover(frame, {
        key    = "powerbar",
        label  = L["|cffffffffPOWER BAR|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = mod.db,
        width  = math.max(mod.db.width + 20, 140),
        height = math.max(mod.db.height + 24, 44),
        onMove = function() applyPos() end,
    })

    applyBorder()
    applyText()
    return frame
end

local function setUnlocked(state)
    mod.db.unlocked = state and true or false
    build()
    if mod.db.unlocked then
        frame:Show()
        frame.mover:Show()
        ns:Print(L["Power Bar mover active. |cff9b6cffDrag the purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Move' again to finish."])
    else
        frame.mover:Hide()
        ns:Print(L["Power Bar mover disabled."])
    end
end

local ev
-- OnDisable calls UnregisterAllEvents, so always re-register, never early-return here.
local function registerEvents()
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event)
            if event == "UNIT_DISPLAYPOWER" then
                updatePowerType()
            elseif event == "PLAYER_ENTERING_WORLD" then
                applyAppearance(); updateValue(); applyHashes(); updateVisibility()
            elseif event == "UNIT_MAXPOWER" then
                updateValue(); applyHashes()
            elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED"
                or event == "PLAYER_TARGET_CHANGED" or event == "GROUP_ROSTER_UPDATE"
                or event == "ZONE_CHANGED_NEW_AREA" then
                updateVisibility()
            else
                updateValue()
            end
        end)
    end
    ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    ev:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
end

function mod:OnEnable()
    -- A saved unlock short-circuits every visibility rule and leaves the bar on
    -- screen with no mover to grab, because setUnlocked never runs on load.
    mod.db.unlocked = false
    if not mod.db.texture then mod.db.texture = DEFAULT_TEXTURE end
    build()
    applySize(); applyPos(); applyAppearance(); updateValue(); applyHashes()
    registerEvents()
    frame:Show()
    updateVisibility()
    updateVisTicker()
end

function mod:OnDisable()
    if ev then ev:UnregisterAllEvents() end
    if visTicker then visTicker:Hide() end
    if smoothTicker then smoothTicker:Hide() end
    if frame then frame:Hide() end
end

function mod:GetOptions()
    local SLW = 180
    return {
        { type = "desc",
          text = L["|cffaaaaaaResource bar that follows your class automatically (Mana / Rage / Energy). Druids switch with their form: Bear = Rage, Cat = Energy, otherwise Mana.|r"] },

        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Unlock / Move"], width = 130,
              onClick = function() setUnlocked(not mod.db.unlocked) end },
            { type = "button", label = L["Center Position"], width = 150,
              onClick = function() mod.db.x, mod.db.y = 0, -200; applyPos() end },
        } },

        { type = "section", title = L["Size"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Width"], min = 80, max = 600, step = 2, width = SLW,
                  get = function() return mod.db.width end,
                  set = function(_, v) mod.db.width = v; applySize() end },
                { type = "slider", label = L["Height"], min = 6, max = 60, step = 1, width = SLW,
                  get = function() return mod.db.height end,
                  set = function(_, v) mod.db.height = v; applySize() end },
            } },
        } },

        { type = "section", title = L["Text"], items = {
            -- "No text" is one of the choices, and then nothing below it means
            -- anything -- so the whole section hangs off this one dropdown.
            { type = "dropdown", label = L["Bar text"], width = 300, values = textModeValues(),
              get = function() return mod.db.textMode end,
              set = function(_, v) mod.db.textMode = v; updateValue() end,
              subOptions = {
                  { type = "segmented", label = L["Text position"], width = 300,
                    values = {
                        { value = "LEFT",   text = L["Left"] },
                        { value = "CENTER", text = L["Center"] },
                        { value = "RIGHT",  text = L["Right"] },
                    },
                    get = function() return mod.db.textAnchor end,
                    set = function(_, v) mod.db.textAnchor = v; applyText() end },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Font size"], min = 8, max = 24, step = 1, width = SLW,
                        get = function() return mod.db.fontSize end,
                        set = function(_, v) mod.db.fontSize = v; applyFont() end },
                      { type = "color", label = L["Text color"], width = 160,
                        get = function() return mod.db.textColor end,
                        set = function(r, g, b) mod.db.textColor = { r = r, g = g, b = b }; applyFont() end },
                  } },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Text offset X"], min = -100, max = 100, step = 1, width = SLW,
                        get = function() return mod.db.textX end,
                        set = function(_, v) mod.db.textX = v; applyText() end },
                      { type = "slider", label = L["Text offset Y"], min = -50, max = 50, step = 1, width = SLW,
                        get = function() return mod.db.textY end,
                        set = function(_, v) mod.db.textY = v; applyText() end },
                  } },
              } },
        } },

        { type = "section", title = L["Appearance"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Border thickness (px)"], min = 0, max = 4, step = 1, width = SLW,
                  get = function() return mod.db.borderSize end,
                  set = function(_, v) mod.db.borderSize = v; applyBorder() end },
                { type = "dropdown", label = L["Bar texture"], width = 300, values = textureValues(),
                  get = function() return mod.db.texture end,
                  set = function(_, v) mod.db.texture = v; applyAppearance() end },
            } },
            { type = "dropdown", label = L["Bar colour"], width = 260,
              values = {
                  { value = "power",  text = L["Power colour (automatic)"] },
                  { value = "class",  text = L["Class colour"] },
                  { value = "custom", text = L["Custom colour"] },
              },
              get = function() return mod.db.colorMode or "power" end,
              set = function(_, v) mod.db.colorMode = v; applyAppearance(); updateValue() end,
              subOptions = {
                  { type = "color", label = L["Custom colour"], width = 200,
                    get = function() return mod.db.customColor end,
                    set = function(r, g, b) mod.db.customColor = { r = r, g = g, b = b }; applyAppearance(); updateValue() end },
              } },
            { type = "checkbox", label = L["Gradient"],
              tooltip = L["The fill fades into a second colour towards the right."],
              get = function() return mod.db.gradient end,
              set = function(_, v) mod.db.gradient = v; applyAppearance() end,
              subOptions = {
                  { type = "color", label = L["Gradient end colour"], width = 200,
                    get = function() return mod.db.gradientColor end,
                    set = function(r, g, b) mod.db.gradientColor = { r = r, g = g, b = b }; applyAppearance() end },
              } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "color", label = L["Border colour"], width = 160,
                  get = function() return mod.db.borderColor end,
                  set = function(r, g, b) mod.db.borderColor = { r = r, g = g, b = b }; applyBorder() end },
                { type = "color", label = L["Background colour"], width = 160,
                  get = function() return mod.db.bgColor end,
                  set = function(r, g, b) mod.db.bgColor = { r = r, g = g, b = b }; applyAppearance() end },
            } },
            { type = "slider", label = L["Background opacity"], min = 0, max = 100, step = 5, width = SLW,
              get = function() return floor((mod.db.bgAlpha or 0.85) * 100 + 0.5) end,
              set = function(_, v) mod.db.bgAlpha = v / 100; applyAppearance() end },
            { type = "checkbox", label = L["Smooth value changes"],
              get = function() return mod.db.smooth end,
              set = function(_, v) mod.db.smooth = v end },
        } },

        { type = "section", title = L["Visibility"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "dropdown", label = L["Visibility"], width = 220,
                  values = ns.VisibilityValues(),
                  get = function() return mod.db.visibility or "always" end,
                  set = function(_, v) mod.db.visibility = v; updateVisibility(); updateVisTicker() end },
                { type = "dropdown", label = L["Group visibility"], width = 220,
                  values = ns.GroupVisValues(),
                  get = function() return mod.db.groupVis or "any" end,
                  set = function(_, v) mod.db.groupVis = v; updateVisibility() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Only in instances"],
                  get = function() return mod.db.onlyInstances end,
                  set = function(_, v) mod.db.onlyInstances = v; updateVisibility() end },
                { type = "checkbox", label = L["Hide when mounted"],
                  get = function() return mod.db.hideMounted end,
                  set = function(_, v) mod.db.hideMounted = v; updateVisibility(); updateVisTicker() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Hide without target"],
                  get = function() return mod.db.hideNoTarget end,
                  set = function(_, v) mod.db.hideNoTarget = v; updateVisibility() end },
                { type = "checkbox", label = L["Hide while full (out of combat)"],
                  get = function() return mod.db.hideFull end,
                  set = function(_, v) mod.db.hideFull = v; updateVisibility() end },
            } },
            { type = "checkbox", label = L["Fade out of combat"],
              get = function() return mod.db.fadeOOC end,
              set = function(_, v) mod.db.fadeOOC = v; updateVisibility() end,
              subOptions = {
                  { type = "slider", label = L["Out-of-combat opacity"], min = 10, max = 90, step = 5, width = SLW,
                    get = function() return mod.db.oocAlpha or 40 end,
                    set = function(_, v) mod.db.oocAlpha = v; updateVisibility() end },
              } },
            { type = "slider", label = L["Faded opacity"], min = 0, max = 90, step = 5, width = SLW,
              tooltip = L["Mouseover mode: the bar's opacity while the mouse is elsewhere."],
              get = function() return mod.db.fadeAlpha or 20 end,
              set = function(_, v) mod.db.fadeAlpha = v; updateVisibility() end },
        } },

        { type = "section", title = L["Marks & threshold"], items = {
            { type = "editbox", label = L["Hash marks"], width = 260,
              tooltip = L["Comma-separated values, e.g. 30,60 — draws a line at each (great for tick or breakpoint marks)."],
              get = function() return mod.db.hashMarks or "" end,
              set = function(_, v) mod.db.hashMarks = tostring(v or ""); applyHashes() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Values are percent"],
                  get = function() return mod.db.hashPct end,
                  set = function(_, v) mod.db.hashPct = v; applyHashes() end },
                { type = "slider", label = L["Mark width"], min = 1, max = 4, step = 1, width = SLW,
                  get = function() return mod.db.hashWidth or 1 end,
                  set = function(_, v) mod.db.hashWidth = v; applyHashes() end },
            } },
            { type = "color", label = L["Mark colour"], width = 200,
              get = function() return mod.db.hashColor end,
              set = function(r, g, b) mod.db.hashColor = { r = r, g = g, b = b }; applyHashes() end },
            { type = "checkbox", label = L["Threshold colouring"],
              tooltip = L["Recolours the bar (or its text) once the resource crosses the threshold."],
              get = function() return mod.db.thresholdOn end,
              set = function(_, v) mod.db.thresholdOn = v; updateValue() end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "editbox", label = L["Threshold"], width = 120, numeric = true,
                        get = function() return mod.db.threshold or 20 end,
                        set = function(_, v) mod.db.threshold = tonumber(v) or 20; updateValue() end },
                      { type = "checkbox", label = L["Values are percent"],
                        get = function() return mod.db.thresholdPct end,
                        set = function(_, v) mod.db.thresholdPct = v; updateValue() end },
                  } },
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "segmented", label = L["Direction"], width = 200,
                        values = {
                            { value = "below", text = L["At or below"] },
                            { value = "above", text = L["At or above"] },
                        },
                        get = function() return mod.db.thresholdDir or "below" end,
                        set = function(_, v) mod.db.thresholdDir = v; updateValue() end },
                      { type = "color", label = L["Threshold colour"], width = 160,
                        get = function() return mod.db.thresholdColor end,
                        set = function(r, g, b) mod.db.thresholdColor = { r = r, g = g, b = b }; updateValue() end },
                  } },
                  { type = "checkbox", label = L["Recolour the text instead of the bar"],
                    get = function() return mod.db.thresholdText end,
                    set = function(_, v) mod.db.thresholdText = v; updateValue() end },
              } },
        } },
    }
end
