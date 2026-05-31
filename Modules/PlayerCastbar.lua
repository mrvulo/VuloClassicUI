-- =========================================================
-- VuloClassicUI / Modules / PlayerCastbar
-- Two modes:
--   "blizzard" -> Original castbar extended (time remaining text, purple ticks, channel coloring)
--   "custom"   -> Custom castbar in VUI style (icon, spell name below bar, etc.)
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("playercastbar", {
    name        = "Player Castbar",
    group       = "Unit Frames",
    description = "Player castbar with two modes: Original (Blizzard bar extended) or Custom castbar (VUI style).",
    defaults = {
        enabled       = true,
        mode          = "blizzard",        -- "blizzard" or "custom"
        -- Shared defaults
        showTimeText  = true,
        showTicks     = true,
        showSpellName = true,
        showIcon      = true,
        -- Custom mode: size & position
        width         = 240,
        height        = 18,
        iconSize      = 14,
        iconGap       = 3,
        iconX         = 0,     -- additional X offset for the icon
        iconY         = 0,     -- Y offset (positive = up)
        x             = 0,
        y             = -180,
        unlocked      = false,
        -- Colors (for both modes)
        accentColor   = { r = 0.608, g = 0.424, b = 1.000, a = 0.90 },  -- #9b6cff
        castColor     = { r = 1.00,  g = 0.80,  b = 0.20,  a = 1.00 },  -- yellow
        channelColor  = { r = 0.608, g = 0.424, b = 1.000, a = 1.00 },  -- #9b6cff
        successColor  = { r = 0.40, g = 0.85, b = 0.40, a = 1.00 },
        failColor     = { r = 0.90, g = 0.25, b = 0.25, a = 1.00 },
    },
})

local TEX_PATH    = "Interface\\AddOns\\VuloClassicUI\\Media\\Castbar\\"
local TEX_BG      = TEX_PATH .. "CastingBarBackground"
local TEX_FILL    = TEX_PATH .. "CastingBarStandard"     -- yellow tinted -> for normal casts
local TEX_CHANNEL = TEX_PATH .. "CastingBarChannel"      -- separate channel texture
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
-- MODE 1: BLIZZARD (original castbar extended)
-- =========================================================================
-- =========================================================================

local Blizzard = {}

local FALLBACK_W, FALLBACK_H = 260, 18

local function bz_getBar()
    return _G.PlayerCastingBarFrame or _G.CastingBarFrame
end

-- Single walk through the frame tree, collects StatusBars + textures simultaneously
local function bz_walkAndCollect(frame, depth, statusbars, textures)
    if not frame or depth > 5 then return end
    if frame.GetObjectType and frame:GetObjectType() == "StatusBar" then
        table.insert(statusbars, frame)
    end
    if frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "Texture" then
                local cr, cg, cb, ca = 1, 1, 1, 1
                if r.GetVertexColor then cr, cg, cb, ca = r:GetVertexColor() end
                table.insert(textures, { tex = r, origR = cr, origG = cg, origB = cb, origA = ca })
            end
        end
    end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do
            bz_walkAndCollect(c, depth + 1, statusbars, textures)
        end
    end
end

local function bz_ensureStatusBars(bar)
    if bar._vcui_statusbars then return end
    bar._vcui_statusbars = {}
    bar._vcui_textures   = {}
    bz_walkAndCollect(bar, 0, bar._vcui_statusbars, bar._vcui_textures)
    bar._vcui_origColors = {}
    for i, sb in ipairs(bar._vcui_statusbars) do
        local r, g, b, a = 1, 1, 1, 1
        if sb.GetStatusBarColor then r, g, b, a = sb:GetStatusBarColor() end
        bar._vcui_origColors[i] = { r = r, g = g, b = b, a = a }
    end
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

    -- Time remaining text
    o.timeText = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local font, size, flags = o.timeText:GetFont()
    o.timeText:SetFont(font, (size or 10) + 2, flags)
    o.timeText:SetTextColor(1, 1, 1, 1)
    o.timeText:SetPoint("RIGHT", o, "RIGHT", -10, 3)
    o.timeText:SetJustifyH("RIGHT")
    o.timeText:SetText("")

    -- Tick pool
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
            -- On cFrame.bar instead of cFrame: automatically sits on top of the bar StatusBar texture
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

    -- Mover overlay (clearly visible in unlock mode)
    cFrame.mover = ns:CreateMover(cFrame, {
        label  = L["|cffffffffCASTBAR|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = mod.db,
        width  = math.max(mod.db.width + 60, 200),
        height = math.max(60, mod.db.height + 40),
        onMove = function(x, y)
            ns:Print(string.format(L["Castbar position: x=%.0f, y=%.0f"], x, y))
        end,
    })

    -- No mouse events on cFrame itself (would conflict with the mover overlay)
    cFrame:EnableMouse(false)

    cFrame.icon = cFrame:CreateTexture(nil, "BORDER")
    cFrame.icon:SetSize(mod.db.iconSize, mod.db.iconSize)
    cFrame.icon:SetPoint("RIGHT", cFrame, "LEFT",
        -(mod.db.iconGap or 3) + (mod.db.iconX or 0), (mod.db.iconY or 0))
    cFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- 1px border around the icon (4 edges, anchored to the icon -> move automatically with it)
    local function makeIconEdge()
        local t = cFrame:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        return t
    end
    cFrame.iconBorderT = makeIconEdge()
    cFrame.iconBorderT:SetPoint("BOTTOMLEFT",  cFrame.icon, "TOPLEFT",  -1, 0)
    cFrame.iconBorderT:SetPoint("BOTTOMRIGHT", cFrame.icon, "TOPRIGHT",  1, 0)
    cFrame.iconBorderT:SetHeight(1)

    cFrame.iconBorderB = makeIconEdge()
    cFrame.iconBorderB:SetPoint("TOPLEFT",     cFrame.icon, "BOTTOMLEFT",  -1, 0)
    cFrame.iconBorderB:SetPoint("TOPRIGHT",    cFrame.icon, "BOTTOMRIGHT",  1, 0)
    cFrame.iconBorderB:SetHeight(1)

    cFrame.iconBorderL = makeIconEdge()
    cFrame.iconBorderL:SetPoint("TOPRIGHT",    cFrame.icon, "TOPLEFT",     0,  1)
    cFrame.iconBorderL:SetPoint("BOTTOMRIGHT", cFrame.icon, "BOTTOMLEFT",  0, -1)
    cFrame.iconBorderL:SetWidth(1)

    cFrame.iconBorderR = makeIconEdge()
    cFrame.iconBorderR:SetPoint("TOPLEFT",     cFrame.icon, "TOPRIGHT",    0,  1)
    cFrame.iconBorderR:SetPoint("BOTTOMLEFT",  cFrame.icon, "BOTTOMRIGHT", 0, -1)
    cFrame.iconBorderR:SetWidth(1)

    cFrame.setIconShown = function(state)
        cFrame.icon:SetShown(state)
        cFrame.iconBorderT:SetShown(state)
        cFrame.iconBorderB:SetShown(state)
        cFrame.iconBorderL:SetShown(state)
        cFrame.iconBorderR:SetShown(state)
    end

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

    -- Mask for rounded corners (created once initially, re-attached after texture change)
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
    -- Spell name BOTTOM-LEFT
    cFrame.nameText = cFrame:CreateFontString(nil, "OVERLAY")
    cFrame.nameText:SetFont(font, 11, "OUTLINE")
    cFrame.nameText:SetPoint("TOPLEFT", cFrame, "BOTTOMLEFT", 2, -2)
    cFrame.nameText:SetJustifyH("LEFT")
    cFrame.nameText:SetTextColor(1, 1, 1)

    -- Cast timer BOTTOM-RIGHT (same height as name)
    cFrame.timeText = cFrame:CreateFontString(nil, "OVERLAY")
    cFrame.timeText:SetFont(font, 11, "OUTLINE")
    cFrame.timeText:SetPoint("TOPRIGHT", cFrame, "BOTTOMRIGHT", -2, -2)
    cFrame.timeText:SetJustifyH("RIGHT")
    cFrame.timeText:SetTextColor(1, 1, 1)

    cFrame.ticks = {}

    cFrame:SetScript("OnUpdate", function(self, elapsed)
        if not castInfo then
            -- Keep visible in unlock mode, otherwise hide
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
    cFrame.setIconShown(mod.db.showIcon)
    cFrame.nameText:SetText(mod.db.showSpellName and name or "")

    if isChannel then
        -- Channel: green texture, no tint (texture is already green)
        cFrame.bar:SetStatusBarTexture(TEX_CHANNEL)
        if cFrame._applyMask then cFrame._applyMask() end
        c_applyColor({ r = 1, g = 1, b = 1, a = 1 })  -- white = no multiplication
        local count = CHANNEL_TICKS[name]
        if count then c_showTicks(count) else c_hideAllTicks() end
        cFrame.spark:Hide()
    else
        -- Normal cast: yellow texture, no tint
        cFrame.bar:SetStatusBarTexture(TEX_FILL)
        if cFrame._applyMask then cFrame._applyMask() end
        c_applyColor({ r = 1, g = 1, b = 1, a = 1 })  -- white = no multiplication
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
                -- STOP also fires on spell pushback, check if cast is really over
                if castInfo and not castInfo.isChannel and not castInfo.fadeOut then
                    -- Only stop if UnitCastingInfo really returns nothing anymore
                    local stillCasting = UnitCastingInfo("player")
                    if not stillCasting then
                        c_stopCast(true)
                    end
                end
            elseif event == "UNIT_SPELLCAST_FAILED"
                or event == "UNIT_SPELLCAST_FAILED_QUIET" then
                -- FAILED_QUIET often fires on attempts during an ongoing cast.
                -- Only abort if NO cast/channel is running anymore.
                if castInfo and not castInfo.fadeOut then
                    local stillCasting = UnitCastingInfo("player") or UnitChannelInfo("player")
                    if not stillCasting then
                        c_stopCast(false)
                    end
                end
            elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
                -- Real interrupt (e.g. by Kick) -> always stop
                if castInfo then c_stopCast(false) end
            end
        end)
    end

    -- Hide Blizzard bar
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
    cFrame.icon:SetPoint("RIGHT", cFrame, "LEFT",
        -(mod.db.iconGap or 3) + (mod.db.iconX or 0), (mod.db.iconY or 0))
    cFrame.spark:SetHeight(mod.db.height + 8)
end

local function c_setUnlocked(state)
    mod.db.unlocked = state
    c_create()
    if state then
        -- Show the castbar itself with test content
        cFrame:Show()
        cFrame:SetAlpha(1)
        cFrame.bar:SetValue(0.7)
        cFrame.nameText:SetText(L["|cff9b6cffMind Flay|r"])
        cFrame.timeText:SetText("1.5 / 2.0")
        cFrame.icon:SetTexture("Interface\\Icons\\Spell_Nature_Earthbind")
        cFrame.setIconShown(mod.db.showIcon)
        c_applyColor(mod.db.castColor)
        c_showTicks(3)
        -- Show mover overlay on top
        cFrame.mover:Show()
        ns:Print(L["Castbar mover active. |cff9b6cffDrag purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Test' again to finish."])
    else
        cFrame.mover:Hide()
        c_hideAllTicks()
        if not castInfo then cFrame:Hide() end
        ns:Print(L["Castbar mover disabled."])
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
        -- Without a /reload, reactivating the bar's events is not possible
        -- -> warn the user about this.
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
    -- Migration: update old channel color (0.75, 0.35, 1.00) to new #9b6cff.
    -- Only if the user didn't customize the color themselves.
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

    table.insert(items, { type = "header", text = L["Mode"] })
    table.insert(items, {
        type = "dropdown", label = L["Castbar Variant"],
        width = 320,
        tooltip = L["Switch between Original (Blizzard bar extended) and Custom castbar (VUI style with icon, spell name below bar)."],
        values = {
            { value = "blizzard", text = L["Original (Blizzard bar extended)"] },
            { value = "custom",   text = L["Custom Castbar (VUI style)"] },
        },
        get = function() return mod.db.mode end,
        set = function(_, v)
            switchMode(v)
            if v == "blizzard" then
                ns:Print(L["Castbar mode switched to |cff9b6cffOriginal|r. |cffffff00/reload|r recommended so the default bar works normally again."])
            else
                ns:Print(L["Castbar mode switched to |cff9b6cffVUI Style|r."])
            end
        end,
    })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaMode switch: A /reload may be required after switching so the default bar works normally again.|r"] })

    table.insert(items, { type = "spacer", height = 8 })
    table.insert(items, { type = "header", text = L["General"] })

    table.insert(items, {
        type = "toggle", label = L["Show spell name"],
        get = function() return mod.db.showSpellName end,
        set = function(_, v) mod.db.showSpellName = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show cast timer"],
        get = function() return mod.db.showTimeText end,
        set = function(_, v) mod.db.showTimeText = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show channel ticks"],
        tooltip = L["Shows vertical lines at tick points (Mind Flay, Drain Soul, Hellfire, etc.)"],
        get = function() return mod.db.showTicks end,
        set = function(_, v) mod.db.showTicks = v end,
    })

    -- Mode-specific options
    if mod.db.mode == "custom" then
        table.insert(items, { type = "spacer", height = 8 })
        table.insert(items, { type = "header", text = L["VUI Style: Position & Size"] })
        table.insert(items, {
            type = "group", layout = "row", gap = 8,
            items = {
                { type = "button", label = L["Unlock / Test"], width = 130,
                  onClick = function() c_setUnlocked(not mod.db.unlocked) end },
                { type = "button", label = L["Center Position"], width = 170,
                  onClick = function()
                      mod.db.x = 0; mod.db.y = -180
                      c_applyLayout()
                  end },
            },
        })
        table.insert(items, { type = "desc",
            text = L["|cffaaaaaaTip: Hold |cffffffffSHIFT|r and drag the castbar with the left mouse button during a cast to move it. Or use 'Unlock / Test' for a permanent test bar for positioning.|r"] })
        table.insert(items, {
            type = "toggle", label = L["Show icon"],
            get = function() return mod.db.showIcon end,
            set = function(_, v)
                mod.db.showIcon = v
                if cFrame then cFrame.setIconShown(v) end
            end,
        })
        table.insert(items, {
            type = "slider", label = L["Width"],
            min = 120, max = 400, step = 5,
            get = function() return mod.db.width end,
            set = function(_, v) mod.db.width = v; c_applyLayout() end,
        })
        table.insert(items, {
            type = "slider", label = L["Height"],
            min = 12, max = 36, step = 1,
            get = function() return mod.db.height end,
            set = function(_, v) mod.db.height = v; c_applyLayout() end,
        })
        table.insert(items, {
            type = "slider", label = L["Icon Size"],
            min = 16, max = 48, step = 1,
            get = function() return mod.db.iconSize end,
            set = function(_, v) mod.db.iconSize = v; c_applyLayout() end,
        })
        table.insert(items, {
            type = "slider", label = L["Icon X Offset"],
            min = -100, max = 100, step = 1,
            tooltip = L["Moves the icon horizontally. Negative = left, positive = right."],
            get = function() return mod.db.iconX or 0 end,
            set = function(_, v) mod.db.iconX = v; c_applyLayout() end,
        })
        table.insert(items, {
            type = "slider", label = L["Icon Y Offset"],
            min = -50, max = 50, step = 1,
            tooltip = L["Moves the icon vertically. Positive = up, negative = down."],
            get = function() return mod.db.iconY or 0 end,
            set = function(_, v) mod.db.iconY = v; c_applyLayout() end,
        })
    end

    -- Swing Timer lives in its own hidden module; its options are embedded here
    -- so it doesn't get a separate sidebar entry. Works for any melee class.
    local sw = ns.modules and ns.modules.swingtimer
    if sw and sw.GetOptions and sw.db then
        table.insert(items, { type = "spacer", height = 10 })
        table.insert(items, {
            type = "section", title = L["Swing Timer"], collapsed = true,
            items = sw:GetOptions(),
        })
    end

    return items
end

-- =========================================================
-- Slash command for testing
-- =========================================================
SLASH_SCTTEST1 = "/scttest"
SlashCmdList.SCTTEST = function()
    if mod.db.mode == "custom" then
        c_setUnlocked(not mod.db.unlocked)
    else
        ns:Print(L["Test only available in 'Custom Castbar' mode."])
    end
end
