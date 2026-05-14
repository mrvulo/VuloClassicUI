-- =========================================================
-- VuloClassicUI / Modules / PlayerCastbar
-- Zwei Modi:
--   "blizzard" → Original Castbar erweitert (Restzeit-Text, lila Ticks, Channel-Färbung)
--   "custom"   → Eigene Castbar im VUI-Style (Icon, Spell-Name unter Bar, etc.)
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("playercastbar", {
    name        = "Player Castbar",
    group       = "Unit Frames",
    description = "Spieler-Castbar mit zwei Modi: Original (Blizzard-Bar erweitert) oder Eigene Castbar (VUI-Style).",
    defaults = {
        enabled       = true,
        mode          = "blizzard",        -- "blizzard" oder "custom"
        -- Gemeinsame Defaults
        showTimeText  = true,
        showTicks     = true,
        showSpellName = true,
        showIcon      = true,
        -- Custom-Modus: Größe & Position
        width         = 240,
        height        = 18,
        iconSize      = 14,
        iconGap       = 3,
        x             = 0,
        y             = -180,
        unlocked      = false,
        -- Farben (für beide Modi)
        accentColor   = { r = 0.608, g = 0.424, b = 1.000, a = 0.90 },  -- #9b6cff
        castColor     = { r = 1.00,  g = 0.80,  b = 0.20,  a = 1.00 },  -- gelb
        channelColor  = { r = 0.608, g = 0.424, b = 1.000, a = 1.00 },  -- #9b6cff
        successColor  = { r = 0.40, g = 0.85, b = 0.40, a = 1.00 },
        failColor     = { r = 0.90, g = 0.25, b = 0.25, a = 1.00 },
    },
})

local TEX_PATH    = "Interface\\AddOns\\VuloClassicUI\\Media\\Castbar\\"
local TEX_BG      = TEX_PATH .. "CastingBarBackground"
local TEX_FILL    = TEX_PATH .. "CastingBarStandard"     -- gelb getönt → für normale Casts
local TEX_CHANNEL = TEX_PATH .. "CastingBarChannel"      -- separate Channel-Textur
local TEX_SPARK   = TEX_PATH .. "CastingBarSpark"
local TEX_MASK    = TEX_PATH .. "CastingBarMask"

local CHANNEL_TICKS = {
    ["Mind Flay"]            = 3,
    ["Gedankenschinden"]     = 3,
    ["Mind Sear"]            = 5,
    ["Drain Life"]           = 5,
    ["Lebensentzug"]         = 5,
    ["Drain Mana"]           = 5,
    ["Manaentzug"]           = 5,
    ["Drain Soul"]           = 5,
    ["Seelenentzug"]         = 5,
    ["Health Funnel"]        = 10,
    ["Lebenskanal"]          = 10,
    ["Rain of Fire"]         = 4,
    ["Feuerregen"]           = 4,
    ["Hellfire"]             = 15,
    ["H\195\182llenfeuer"]   = 15,
    ["Arcane Missiles"]      = 5,
    ["Arkangescho\195\159e"] = 5,
    ["Evocation"]            = 4,
    ["Erweckung"]            = 4,
    ["Blizzard"]             = 8,
    ["Schneesturm"]          = 8,
    ["Tranquility"]          = 4,
    ["Seelenruhe"]           = 4,
    ["Hurricane"]            = 10,
    ["Wirbelsturm"]          = 10,
    ["Volley"]               = 6,
    ["Pfeilhagel"]           = 6,
}

-- =========================================================================
-- =========================================================================
-- MODE 1: BLIZZARD (Original-Castbar erweitert)
-- =========================================================================
-- =========================================================================

local Blizzard = {}

local FALLBACK_W, FALLBACK_H = 260, 18

local function bz_collectStatusBars(frame, depth, out)
    if not frame or depth > 5 then return end
    out = out or {}
    if frame.GetObjectType and frame:GetObjectType() == "StatusBar" then
        table.insert(out, frame)
    end
    local kids = { frame:GetChildren() }
    for _, kid in ipairs(kids) do
        bz_collectStatusBars(kid, depth + 1, out)
    end
    return out
end

local function bz_getBar()
    return _G.PlayerCastingBarFrame or _G.CastingBarFrame
end

local function bz_ensureStatusBars(bar)
    if bar._vcui_statusbars then return end
    bar._vcui_statusbars = bz_collectStatusBars(bar, 0, {}) or {}
    bar._vcui_origColors = {}
    for i, sb in ipairs(bar._vcui_statusbars) do
        local r, g, b, a = 1, 1, 1, 1
        if sb.GetStatusBarColor then r, g, b, a = sb:GetStatusBarColor() end
        bar._vcui_origColors[i] = { r = r, g = g, b = b, a = a }
    end
    -- Auch Texturen sammeln für VertexColor-Override
    bar._vcui_textures = {}
    local function walk(f)
        if not f then return end
        if f.GetRegions then
            for _, r in ipairs({ f:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "Texture" then
                    local cr, cg, cb, ca = 1, 1, 1, 1
                    if r.GetVertexColor then cr, cg, cb, ca = r:GetVertexColor() end
                    table.insert(bar._vcui_textures, { tex = r, origR = cr, origG = cg, origB = cb, origA = ca })
                end
            end
        end
        if f.GetChildren then
            for _, c in ipairs({ f:GetChildren() }) do walk(c) end
        end
    end
    walk(bar)
end

local function bz_setChannelColor(bar, isChannel)
    if not bar or not bar._vcui_statusbars then return end
    local c = mod.db.accentColor or { r = 0.75, g = 0.35, b = 1.00, a = 0.90 }

    if isChannel then
        for _, sb in ipairs(bar._vcui_statusbars) do
            if sb.SetStatusBarColor then
                sb:SetStatusBarColor(c.r, c.g, c.b, c.a or 0.9)
            end
        end
        for _, t in ipairs(bar._vcui_textures or {}) do
            if t.tex and t.tex.SetVertexColor then
                t.tex:SetVertexColor(c.r, c.g, c.b, c.a or 0.9)
            end
        end
    else
        for i, sb in ipairs(bar._vcui_statusbars) do
            local orig = bar._vcui_origColors and bar._vcui_origColors[i]
            if sb.SetStatusBarColor and orig then
                sb:SetStatusBarColor(orig.r, orig.g, orig.b, orig.a)
            end
        end
        for _, t in ipairs(bar._vcui_textures or {}) do
            if t.tex and t.tex.SetVertexColor then
                t.tex:SetVertexColor(t.origR or 1, t.origG or 1, t.origB or 1, t.origA or 1)
            end
        end
    end
end

local function bz_ensureOverlay(bar)
    if bar._vcui_overlay then return bar._vcui_overlay end
    local o = CreateFrame("Frame", nil, bar)
    o:SetAllPoints(bar)

    -- Restzeit-Text
    o.timeText = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local font, size, flags = o.timeText:GetFont()
    o.timeText:SetFont(font, (size or 10) + 2, flags)
    o.timeText:SetTextColor(1, 1, 1, 1)
    o.timeText:SetPoint("RIGHT", o, "RIGHT", -10, 3)
    o.timeText:SetJustifyH("RIGHT")
    o.timeText:SetText("")

    -- Tick-Pool
    o.ticks = {}

    bar._vcui_overlay = o
    return o
end

local function bz_hideAllTicks(bar)
    local o = bar and bar._vcui_overlay
    if not o or not o.ticks then return end
    for i = 1, #o.ticks do
        o.ticks[i]:Hide()
        o.ticks[i]:ClearAllPoints()
    end
end

local function bz_showTicks(bar, count)
    local o = bar and bar._vcui_overlay
    if not o or not mod.db.showTicks then return end
    bz_hideAllTicks(bar)
    if not count or count <= 1 then return end

    local linesToDraw = count - 1
    local barW = bar:GetWidth()
    local barH = bar:GetHeight()
    if not barW or barW <= 1 then barW = FALLBACK_W end
    if not barH or barH <= 1 then barH = FALLBACK_H end
    local tickH = math.max(6, barH - 4)

    local c = mod.db.accentColor or { r = 0.75, g = 0.35, b = 1.00 }
    for i = 1, linesToDraw do
        local t = o.ticks[i]
        if not t then
            t = o:CreateTexture(nil, "OVERLAY")
            t:SetWidth(2)
            o.ticks[i] = t
        end
        t:SetColorTexture(c.r, c.g, c.b, 0.85)
        t:SetHeight(tickH)
        t:ClearAllPoints()
        t:SetPoint("CENTER", o, "LEFT", barW * (i / count), 3)
        t:Show()
    end
end

function Blizzard:Enable()
    local bar = bz_getBar()
    if not bar then return end
    bz_ensureStatusBars(bar)
    bz_ensureOverlay(bar)

    if bar._vcui_hookedUpdate then return end
    bar._vcui_hookedUpdate = true
    local acc = 0
    bar:HookScript("OnUpdate", function(self, elapsed)
        if not mod._enabled or mod.db.mode ~= "blizzard" then return end
        acc = acc + (elapsed or 0)
        if acc < 0.03 then return end
        acc = 0

        local o = self._vcui_overlay
        if not o then return end

        if not self:IsShown() then
            o.timeText:SetText("")
            bz_hideAllTicks(self)
            bz_setChannelColor(self, false)
            return
        end

        local cname, _, _, _, cendMS = UnitChannelInfo("player")
        if cname and cendMS then
            local remaining = (cendMS - (GetTime() * 1000)) / 1000
            if remaining < 0 then remaining = 0 end
            if mod.db.showTimeText then
                o.timeText:SetText(string.format("%.1f", remaining))
            else
                o.timeText:SetText("")
            end
            local count = CHANNEL_TICKS[cname]
            if count then bz_showTicks(self, count) else bz_hideAllTicks(self) end
            bz_setChannelColor(self, true)
            return
        end

        local name, _, _, _, endMS = UnitCastingInfo("player")
        if name and endMS then
            local remaining = (endMS - (GetTime() * 1000)) / 1000
            if remaining < 0 then remaining = 0 end
            if mod.db.showTimeText then
                o.timeText:SetText(string.format("%.1f", remaining))
            else
                o.timeText:SetText("")
            end
            bz_hideAllTicks(self)
            bz_setChannelColor(self, false)
            return
        end

        o.timeText:SetText("")
        bz_hideAllTicks(self)
        bz_setChannelColor(self, false)
    end)

    bar:HookScript("OnHide", function(self)
        if self._vcui_overlay then
            self._vcui_overlay.timeText:SetText("")
            bz_hideAllTicks(self)
        end
        bz_setChannelColor(self, false)
    end)

    bar:Show()
end

function Blizzard:Disable()
    local bar = bz_getBar()
    if not bar then return end
    if bar._vcui_overlay then
        bar._vcui_overlay.timeText:SetText("")
        bz_hideAllTicks(bar)
    end
    bz_setChannelColor(bar, false)
end

-- =========================================================================
-- =========================================================================
-- MODE 2: CUSTOM (VUI-Style)
-- =========================================================================
-- =========================================================================

local Custom = {}
local cFrame
local castInfo

local function c_hideAllTicks()
    if not cFrame or not cFrame.ticks then return end
    for i = 1, #cFrame.ticks do
        cFrame.ticks[i]:Hide()
        cFrame.ticks[i]:ClearAllPoints()
    end
end

local function c_showTicks(count)
    if not cFrame or not mod.db.showTicks then return end
    c_hideAllTicks()
    if not count or count <= 1 then return end

    local linesToDraw = count - 1
    local barW = cFrame.bar:GetWidth()
    local barH = cFrame.bar:GetHeight()
    if not barW or barW <= 1 then barW = mod.db.width or 240 end
    if not barH or barH <= 1 then barH = mod.db.height or 18 end
    local tickH = math.max(4, barH + 2)

    for i = 1, linesToDraw do
        local t = cFrame.ticks[i]
        if not t then
            -- Auf cFrame.bar statt cFrame: liegt automatisch über der Bar-Statusbar-Textur
            t = cFrame.bar:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetWidth(2)
            cFrame.ticks[i] = t
        end
        t:SetColorTexture(1, 1, 1, 1)
        t:SetHeight(tickH)
        t:ClearAllPoints()
        t:SetPoint("CENTER", cFrame.bar, "LEFT", barW * (i / count), 0)
        t:Show()
    end
end

local function c_applyColor(color)
    if not cFrame or not color then return end
    cFrame.bar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
end

local function c_create()
    if cFrame then return cFrame end

    cFrame = CreateFrame("Frame", "VCUI_PlayerCastbar", UIParent)
    cFrame:SetSize(mod.db.width, mod.db.height)
    cFrame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)
    cFrame:SetFrameStrata("MEDIUM")
    cFrame:SetMovable(true)
    cFrame:SetClampedToScreen(false)
    cFrame:Hide()

    -- Mover-Overlay (deutlich sichtbar im Unlock-Mode)
    cFrame.mover = CreateFrame("Frame", nil, cFrame)
    cFrame.mover:SetPoint("CENTER", cFrame, "CENTER", 0, 0)
    -- Großer Mover über die Bar hinaus, mindestens 60px hoch damit der Text reinpasst
    cFrame.mover:SetSize(math.max(mod.db.width + 60, 200), math.max(60, mod.db.height + 40))
    cFrame.mover:SetFrameStrata("HIGH")
    cFrame.mover:EnableMouse(true)
    cFrame.mover:Hide()

    cFrame.mover.bg = cFrame.mover:CreateTexture(nil, "BACKGROUND")
    cFrame.mover.bg:SetAllPoints(cFrame.mover)
    cFrame.mover.bg:SetColorTexture(0.6, 0.4, 1.0, 0.4)  -- lila transparent

    cFrame.mover.border = CreateFrame("Frame", nil, cFrame.mover,
        BackdropTemplateMixin and "BackdropTemplate")
    cFrame.mover.border:SetAllPoints(cFrame.mover)
    if cFrame.mover.border.SetBackdrop then
        cFrame.mover.border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })
        cFrame.mover.border:SetBackdropBorderColor(0.75, 0.35, 1, 1)
    end

    cFrame.mover.label = cFrame.mover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cFrame.mover.label:SetPoint("CENTER", cFrame.mover, "CENTER", 0, 0)
    cFrame.mover.label:SetText("|cffffffffCASTBAR|r\n|cffaaaaaaSHIFT+Ziehen|r")
    cFrame.mover.label:SetJustifyH("CENTER")

    cFrame.mover:RegisterForDrag("LeftButton")
    cFrame.mover:SetScript("OnDragStart", function() cFrame:StartMoving() end)
    cFrame.mover:SetScript("OnDragStop", function()
        cFrame:StopMovingOrSizing()
        -- Berechne Center-Offset relativ zu UIParent-Center (anchor-unabhängig)
        local fx, fy = cFrame:GetCenter()
        local px, py = UIParent:GetCenter()
        if fx and fy and px and py then
            local x = fx - px
            local y = fy - py
            cFrame:ClearAllPoints()
            cFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
            mod.db.x = x; mod.db.y = y
            ns:Print(string.format("Castbar Position: x=%.0f, y=%.0f", x, y))
        end
    end)

    -- Keine Mouse-Events auf cFrame selbst (würde mit dem Mover-Overlay konfliktieren)
    cFrame:EnableMouse(false)

    cFrame.icon = cFrame:CreateTexture(nil, "BORDER")
    cFrame.icon:SetSize(mod.db.iconSize, mod.db.iconSize)
    cFrame.icon:SetPoint("RIGHT", cFrame, "LEFT", -mod.db.iconGap, 0)
    cFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    cFrame.bar = CreateFrame("StatusBar", nil, cFrame)
    cFrame.bar:SetAllPoints(cFrame)
    cFrame.bar:SetStatusBarTexture(TEX_FILL)
    cFrame.bar:SetMinMaxValues(0, 1)
    cFrame.bar:SetValue(0)
    c_applyColor(mod.db.castColor)

    cFrame.bg = cFrame.bar:CreateTexture(nil, "BACKGROUND")
    cFrame.bg:SetAllPoints(cFrame.bar)
    cFrame.bg:SetTexture(TEX_BG)
    cFrame.bg:SetVertexColor(0.1, 0.1, 0.1, 0.85)

    -- Mask für runde Ecken (initial einmal anlegen, wird nach Textur-Wechsel re-attached)
    local function applyMask()
        local fillTex = cFrame.bar:GetStatusBarTexture()
        if fillTex and fillTex.AddMaskTexture then
            if not cFrame._mask then
                cFrame._mask = cFrame.bar:CreateMaskTexture()
                cFrame._mask:SetTexture(TEX_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                cFrame._mask:SetAllPoints(cFrame.bar)
            end
            fillTex:AddMaskTexture(cFrame._mask)
            if cFrame.bg.AddMaskTexture then cFrame.bg:AddMaskTexture(cFrame._mask) end
        end
    end
    cFrame._applyMask = applyMask
    applyMask()

    cFrame.spark = cFrame.bar:CreateTexture(nil, "OVERLAY")
    cFrame.spark:SetTexture(TEX_SPARK)
    cFrame.spark:SetBlendMode("ADD")
    cFrame.spark:SetSize(16, mod.db.height + 8)

    local font = "Fonts\\FRIZQT__.TTF"
    -- Spell-Name UNTEN-LINKS
    cFrame.nameText = cFrame:CreateFontString(nil, "OVERLAY")
    cFrame.nameText:SetFont(font, 11, "OUTLINE")
    cFrame.nameText:SetPoint("TOPLEFT", cFrame, "BOTTOMLEFT", 2, -2)
    cFrame.nameText:SetJustifyH("LEFT")
    cFrame.nameText:SetTextColor(1, 1, 1)

    -- Cast-Timer UNTEN-RECHTS (auf gleicher Höhe wie Name)
    cFrame.timeText = cFrame:CreateFontString(nil, "OVERLAY")
    cFrame.timeText:SetFont(font, 11, "OUTLINE")
    cFrame.timeText:SetPoint("TOPRIGHT", cFrame, "BOTTOMRIGHT", -2, -2)
    cFrame.timeText:SetJustifyH("RIGHT")
    cFrame.timeText:SetTextColor(1, 1, 1)

    cFrame.ticks = {}

    cFrame:SetScript("OnUpdate", function(self, elapsed)
        if not castInfo then
            -- Im Unlock-Mode sichtbar lassen, sonst verstecken
            if not mod.db.unlocked then self:Hide() end
            return
        end
        local nowMS = GetTime() * 1000

        if castInfo.fadeOut then
            castInfo.fadeTimer = (castInfo.fadeTimer or 0) - elapsed
            if castInfo.fadeTimer <= 0 then
                castInfo = nil
                if not mod.db.unlocked then self:Hide() end
                return
            end
            self:SetAlpha(castInfo.fadeTimer / 0.5)
            return
        end

        local sMS, eMS = castInfo.startMS, castInfo.endMS
        local duration = (eMS - sMS) / 1000
        if duration <= 0 then duration = 0.01 end

        local progress, remaining
        if castInfo.isChannel then
            remaining = math.max(0, (eMS - nowMS) / 1000)
            progress  = remaining / duration
        else
            local el = math.max(0, (nowMS - sMS) / 1000)
            if el > duration then el = duration end
            progress  = el / duration
            remaining = math.max(0, duration - el)
        end

        self.bar:SetValue(progress)
        self.spark:ClearAllPoints()
        self.spark:SetPoint("CENTER", self.bar, "LEFT", self.bar:GetWidth() * progress, 0)

        if mod.db.showTimeText then
            self.timeText:SetText(string.format("%.1f / %.1f", remaining, duration))
        else
            self.timeText:SetText("")
        end

        if (not castInfo.isChannel and progress >= 1)
        or (castInfo.isChannel and progress <= 0) then
            castInfo.fadeOut = true
            castInfo.fadeTimer = 0.5
        end
    end)

    return cFrame
end

local function c_startCast(isChannel)
    c_create()
    local name, _, icon, sMS, eMS
    if isChannel then
        name, _, icon, sMS, eMS = UnitChannelInfo("player")
    else
        name, _, icon, sMS, eMS = UnitCastingInfo("player")
    end
    if not name or not sMS or not eMS then return end

    castInfo = { name = name, icon = icon, startMS = sMS, endMS = eMS, isChannel = isChannel }
    cFrame:SetAlpha(1)
    cFrame:Show()
    cFrame.icon:SetTexture(icon)
    cFrame.icon:SetShown(mod.db.showIcon)
    cFrame.nameText:SetText(mod.db.showSpellName and name or "")

    if isChannel then
        -- Channel: grüne Textur, keine Tönung (Textur ist schon grün)
        cFrame.bar:SetStatusBarTexture(TEX_CHANNEL)
        if cFrame._applyMask then cFrame._applyMask() end
        c_applyColor({ r = 1, g = 1, b = 1, a = 1 })  -- weiß = keine Multiplikation
        local count = CHANNEL_TICKS[name]
        if count then c_showTicks(count) else c_hideAllTicks() end
        cFrame.spark:Hide()
    else
        -- Normaler Cast: gelbe Textur, keine Tönung
        cFrame.bar:SetStatusBarTexture(TEX_FILL)
        if cFrame._applyMask then cFrame._applyMask() end
        c_applyColor({ r = 1, g = 1, b = 1, a = 1 })  -- weiß = keine Multiplikation
        c_hideAllTicks()
        cFrame.spark:Show()
    end
end

local function c_stopCast(success)
    if not cFrame or not castInfo then return end
    c_applyColor(success and mod.db.successColor or mod.db.failColor)
    c_hideAllTicks()
    cFrame.spark:Hide()
    castInfo.fadeOut = true
    castInfo.fadeTimer = 0.5
end

local c_eventFrame
function Custom:Enable()
    c_create()
    if not c_eventFrame then
        c_eventFrame = CreateFrame("Frame")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START",          "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED",        "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP",           "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",      "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",         "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET",   "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED",    "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START",  "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
        c_eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP",   "player")

        c_eventFrame:SetScript("OnEvent", function(_, event, unit, castGUIDorSpellID, spellID)
            if unit ~= "player" or not mod._enabled or mod.db.mode ~= "custom" then return end

            if event == "UNIT_SPELLCAST_START" then
                c_startCast(false)
            elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
                c_startCast(true)
            elseif event == "UNIT_SPELLCAST_DELAYED" then
                if castInfo and not castInfo.isChannel then
                    local _, _, _, s, e = UnitCastingInfo("player")
                    if s and e then castInfo.startMS = s; castInfo.endMS = e end
                end
            elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
                if castInfo and castInfo.isChannel then
                    local _, _, _, s, e = UnitChannelInfo("player")
                    if s and e then castInfo.startMS = s; castInfo.endMS = e end
                end
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                if castInfo and not castInfo.isChannel then c_stopCast(true) end
            elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
                c_stopCast(true)
            elseif event == "UNIT_SPELLCAST_STOP" then
                -- STOP feuert auch bei Spell-Pushback, prüfen ob Cast wirklich vorbei ist
                if castInfo and not castInfo.isChannel and not castInfo.fadeOut then
                    -- Nur stoppen wenn UnitCastingInfo wirklich nichts mehr zurückgibt
                    local stillCasting = UnitCastingInfo("player")
                    if not stillCasting then
                        c_stopCast(true)
                    end
                end
            elseif event == "UNIT_SPELLCAST_FAILED"
                or event == "UNIT_SPELLCAST_FAILED_QUIET" then
                -- FAILED_QUIET feuert oft bei Versuchen während laufendem Cast.
                -- Nur abbrechen wenn KEIN Cast/Channel mehr läuft.
                if castInfo and not castInfo.fadeOut then
                    local stillCasting = UnitCastingInfo("player") or UnitChannelInfo("player")
                    if not stillCasting then
                        c_stopCast(false)
                    end
                end
            elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
                -- Echter Interrupt (z.B. durch Kick) → immer stoppen
                if castInfo then c_stopCast(false) end
            end
        end)
    end

    -- Blizzard-Bar verstecken
    local b = bz_getBar()
    if b then
        if b.UnregisterAllEvents then b:UnregisterAllEvents() end
        if b.Hide then b:Hide() end
        if not b._vcui_hideHooked then
            b._vcui_hideHooked = true
            b:HookScript("OnShow", function(self)
                if mod._enabled and mod.db.mode == "custom" then self:Hide() end
            end)
        end
    end
end

function Custom:Disable()
    if cFrame then cFrame:Hide() end
    castInfo = nil
end

local function c_applyLayout()
    if not cFrame then return end
    cFrame:SetSize(mod.db.width, mod.db.height)
    cFrame:ClearAllPoints()
    cFrame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)
    cFrame.icon:SetSize(mod.db.iconSize, mod.db.iconSize)
    cFrame.icon:ClearAllPoints()
    cFrame.icon:SetPoint("RIGHT", cFrame, "LEFT", -mod.db.iconGap, 0)
    cFrame.spark:SetHeight(mod.db.height + 8)
end

local function c_setUnlocked(state)
    mod.db.unlocked = state
    c_create()
    if state then
        -- Castbar selbst zeigen mit Test-Inhalt
        cFrame:Show()
        cFrame:SetAlpha(1)
        cFrame.bar:SetValue(0.7)
        cFrame.nameText:SetText("|cff9b6cffMind Flay|r")
        cFrame.timeText:SetText("1.5 / 2.0")
        cFrame.icon:SetTexture("Interface\\Icons\\Spell_Nature_Earthbind")
        cFrame.icon:SetShown(mod.db.showIcon)
        c_applyColor(mod.db.castColor)
        c_showTicks(3)
        -- Mover-Overlay drüber anzeigen
        cFrame.mover:Show()
        ns:Print("Castbar-Mover aktiv. |cff9b6cffLila Box ziehen|r zum Verschieben. Nochmal auf 'Unlock / Test' klicken zum Beenden.")
    else
        cFrame.mover:Hide()
        c_hideAllTicks()
        if not castInfo then cFrame:Hide() end
        ns:Print("Castbar-Mover deaktiviert.")
    end
end

-- =========================================================================
-- =========================================================================
-- MODE-SWITCH
-- =========================================================================
-- =========================================================================

local function switchMode(newMode)
    if newMode ~= "blizzard" and newMode ~= "custom" then return end
    mod.db.mode = newMode

    if newMode == "blizzard" then
        Custom:Disable()
        -- Wenn ein /reload nicht passiert ist, die Events der Bar reaktivieren
        -- ist nicht möglich ohne /reload → User darauf hinweisen.
        Blizzard:Enable()
    else
        Blizzard:Disable()
        Custom:Enable()
    end
end

-- =========================================================================
-- Lifecycle
-- =========================================================================

function mod:OnEnable()
    -- Migration: alte Channel-Farbe (0.75, 0.35, 1.00) auf neue #9b6cff aktualisieren.
    -- Nur wenn der User die Farbe nicht selbst angepasst hatte.
    local function isOldDefault(c)
        return c and math.abs((c.r or 0) - 0.75) < 0.01
                 and math.abs((c.g or 0) - 0.35) < 0.01
                 and math.abs((c.b or 0) - 1.00) < 0.01
    end
    if isOldDefault(mod.db.channelColor) then
        mod.db.channelColor = { r = 0.608, g = 0.424, b = 1.000, a = 1.00 }
    end
    if isOldDefault(mod.db.accentColor) then
        mod.db.accentColor = { r = 0.608, g = 0.424, b = 1.000, a = 0.90 }
    end

    if mod.db.mode == "custom" then
        Custom:Enable()
    else
        Blizzard:Enable()
    end
end

function mod:OnDisable()
    Custom:Disable()
    Blizzard:Disable()
end

-- =========================================================================
-- Options
-- =========================================================================

function mod:GetOptions()
    local items = {}

    table.insert(items, { type = "header", text = "Modus" })
    table.insert(items, {
        type = "dropdown", label = "Castbar-Variante",
        width = 320,
        tooltip = "Wechsel zwischen Original (Blizzard-Bar erweitert) und Eigene Castbar (VUI-Style mit Icon, Spell-Name unter Bar).",
        values = {
            { value = "blizzard", text = "Original (Blizzard-Bar erweitert)" },
            { value = "custom",   text = "Eigene Castbar (VUI-Style)" },
        },
        get = function() return mod.db.mode end,
        set = function(_, v)
            switchMode(v)
            if v == "blizzard" then
                ns:Print("Castbar-Modus auf |cff9b6cffOriginal|r gewechselt. |cffffff00/reload|r empfohlen damit die Standard-Bar wieder normal arbeitet.")
            else
                ns:Print("Castbar-Modus auf |cff9b6cffVUI-Style|r gewechselt.")
            end
        end,
    })
    table.insert(items, { type = "desc",
        text = "|cffaaaaaaModus-Wechsel: Nach dem Umschalten kann ein /reload nötig sein damit die Standard-Bar wieder normal funktioniert.|r" })

    table.insert(items, { type = "spacer", height = 8 })
    table.insert(items, { type = "header", text = "Allgemein" })

    table.insert(items, {
        type = "toggle", label = "Spell-Name anzeigen",
        get = function() return mod.db.showSpellName end,
        set = function(_, v) mod.db.showSpellName = v end,
    })
    table.insert(items, {
        type = "toggle", label = "Cast-Timer anzeigen",
        get = function() return mod.db.showTimeText end,
        set = function(_, v) mod.db.showTimeText = v end,
    })
    table.insert(items, {
        type = "toggle", label = "Channel-Ticks anzeigen",
        tooltip = "Zeigt vertikale Linien an Tick-Zeitpunkten (Mind Flay, Drain Soul, Hellfire, etc.)",
        get = function() return mod.db.showTicks end,
        set = function(_, v) mod.db.showTicks = v end,
    })

    -- Mode-spezifische Optionen
    if mod.db.mode == "custom" then
        table.insert(items, { type = "spacer", height = 8 })
        table.insert(items, { type = "header", text = "VUI-Style: Position & Größe" })
        table.insert(items, {
            type = "group", layout = "row", gap = 8,
            items = {
                { type = "button", label = "Unlock / Test", width = 130,
                  onClick = function() c_setUnlocked(not mod.db.unlocked) end },
                { type = "button", label = "Position zentrieren", width = 170,
                  onClick = function()
                      mod.db.x = 0; mod.db.y = -180
                      c_applyLayout()
                  end },
            },
        })
        table.insert(items, { type = "desc",
            text = "|cffaaaaaaTipp: Halte |cffffffffSHIFT|r und ziehe die Castbar mit der linken Maustaste während eines Casts um sie zu verschieben. Oder nutze 'Unlock / Test' für eine permanente Test-Bar zum Positionieren.|r" })
        table.insert(items, {
            type = "toggle", label = "Icon anzeigen",
            get = function() return mod.db.showIcon end,
            set = function(_, v)
                mod.db.showIcon = v
                if cFrame then cFrame.icon:SetShown(v) end
            end,
        })
        table.insert(items, {
            type = "slider", label = "Breite",
            min = 120, max = 400, step = 5,
            get = function() return mod.db.width end,
            set = function(_, v) mod.db.width = v; c_applyLayout() end,
        })
        table.insert(items, {
            type = "slider", label = "Höhe",
            min = 12, max = 36, step = 1,
            get = function() return mod.db.height end,
            set = function(_, v) mod.db.height = v; c_applyLayout() end,
        })
        table.insert(items, {
            type = "slider", label = "Icon-Größe",
            min = 16, max = 48, step = 1,
            get = function() return mod.db.iconSize end,
            set = function(_, v) mod.db.iconSize = v; c_applyLayout() end,
        })
    end

    return items
end

-- =========================================================
-- Slash für Test
-- =========================================================
SLASH_SCTTEST1 = "/scttest"
SlashCmdList.SCTTEST = function()
    if mod.db.mode == "custom" then
        c_setUnlocked(not mod.db.unlocked)
    else
        ns:Print("Test nur im 'Eigene Castbar'-Modus verfügbar.")
    end
end
