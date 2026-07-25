-- Player castbar in two modes: "blizzard" extends the default bar, "custom" draws our own.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("playercastbar", {
    name        = "Player Castbar",
    group       = "Unit Frames",
    description = "Player castbar with two modes: Original (Blizzard bar extended) or Custom castbar (VUI style).",
    defaults = {
        enabled       = true,
        mode          = "blizzard",
        showTimeText  = true,
        timeTextMode  = "both",
        showTicks     = true,
        showClipMarker = true,
        showPushback  = true,
        mergeCrafts   = true,
        showSpellName = true,
        showIcon      = true,
        fillMode      = "texture",
        width         = 240,
        height        = 18,
        iconSize      = 14,
        iconGap       = 3,
        iconX         = 0,
        iconY         = 0,
        x             = 0,
        y             = -180,
        unlocked      = false,
        accentColor   = { r = 0.608, g = 0.424, b = 1.000, a = 0.90 },
        castColor     = { r = 1.00,  g = 0.80,  b = 0.20,  a = 1.00 },
        channelColor  = { r = 0.608, g = 0.424, b = 1.000, a = 1.00 },
        successColor  = { r = 0.40, g = 0.85, b = 0.40, a = 1.00 },
        failColor     = { r = 0.90, g = 0.25, b = 0.25, a = 1.00 },
    },
})

local TEX_PATH    = "Interface\\AddOns\\VuloClassicUI\\Media\\Castbar\\"
local TEX_BG      = TEX_PATH .. "CastingBarBackground"
local TEX_FILL    = TEX_PATH .. "CastingBarStandard"
local TEX_CHANNEL = TEX_PATH .. "CastingBarChannel"
local TEX_SPARK   = TEX_PATH .. "CastingBarSpark"
local TEX_MASK    = TEX_PATH .. "CastingBarMask"

-- Keyed by real localized client spell names; a miss silently falls back to ~1 tick/second.
local CHANNEL_TICKS = {
    ["Mind Flay"]            = 3,
    ["Gedankenschinden"]     = 3,
    ["Mind Sear"]            = 5,
    ["Drain Life"]           = 5,
    ["Blutsauger"]           = 5,
    ["Drain Mana"]           = 5,
    ["Manasauger"]           = 5,
    ["Drain Soul"]           = 5,
    ["Seelendieb"]           = 5,
    ["Health Funnel"]        = 10,
    ["Gesundheitskanal"]     = 10,
    ["Rain of Fire"]         = 4,
    ["Feuerregen"]           = 4,
    ["Hellfire"]             = 15,
    ["H\195\182llenfeuer"]   = 15,
    ["Arcane Missiles"]      = 5,
    ["Arkane Geschosse"]     = 5,
    ["Evocation"]            = 4,
    ["Hervorrufung"]         = 4,
    ["Blizzard"]             = 8,
    ["Tranquility"]          = 4,
    ["Gelassenheit"]         = 4,
    ["Hurricane"]            = 10,
    ["Orkan"]                = 10,
    ["Volley"]               = 6,
    ["Salve"]                = 6,
}

-- Non-tick channels: excluded so the ~1/s fallback doesn't turn them into a barcode.
local NO_TICKS = {
    ["Fishing"] = true,             ["Angeln"] = true,
    ["First Aid"] = true,           ["Erste Hilfe"] = true,
    ["Disenchant"] = true,          ["Entzaubern"] = true,
    ["Hearthstone"] = true,         ["Ruhestein"] = true,
    ["Astral Recall"] = true,       ["Astralruf"] = true,
    ["Ritual of Summoning"] = true, ["Ritual der Beschw\195\182rung"] = true,
    ["Summoning Stone"] = true,     ["Beschw\195\182rungsstein"] = true,
}

-- The 1.5-15s window keeps the fallback off long utility channels; every real tick spell above 15s is in the table.
local function tickCountFor(name, duration, isTradeSkill)
    if name and NO_TICKS[name] then return nil end
    local c = name and CHANNEL_TICKS[name]
    if c then return c end
    if isTradeSkill then return nil end
    if duration and duration >= 1.5 and duration <= 15 then
        return math.floor(duration + 0.5)
    end
    return nil
end

-- Casts use the spell-queue CVar (not latency); channels use world latency.
local function clipSeconds(forCast)
    if forCast and GetCVar then
        local q = tonumber(GetCVar("SpellQueueWindow") or "")
        if q and q > 0 then return q / 1000 end
    end
    return (select(4, GetNetStats()) or 0) / 1000
end

local function fmtTime(remaining, duration)
    local m = mod.db.timeTextMode or "both"
    if m == "seconds" then
        return tostring(math.ceil(remaining))
    elseif m == "both" and duration and duration > 0 then
        return string.format("%.1f / %.1f", remaining, duration)
    end
    return string.format("%.1f", remaining)
end

local craftSeries   -- { name, total, done, stamp }; armed by the craft hooks, counted by the tracker below

local function seriesLabel(castName)
    if mod.db.mergeCrafts == false or not craftSeries or not castName then return nil end
    if craftSeries.name ~= castName or (craftSeries.total or 1) <= 1 then return nil end
    local done = craftSeries.done or 0
    if done < 1 then done = 1 end
    if done > craftSeries.total then done = craftSeries.total end
    return string.format("%s %d/%d", castName, done, craftSeries.total)
end

local function armCraftHooks()
    if mod._craftHooked then return end
    mod._craftHooked = true
    if type(_G.DoTradeSkill) == "function" and type(_G.GetTradeSkillInfo) == "function" then
        hooksecurefunc("DoTradeSkill", function(index, num)
            local name = GetTradeSkillInfo(index)
            if type(name) == "string" then
                craftSeries = { name = name, total = tonumber(num) or 1, done = 0, stamp = GetTime() }
            end
        end)
    end
    -- Craft API is always single-cast; hooked anyway so a different craft clears a stale series.
    if type(_G.DoCraft) == "function" and type(_G.GetCraftInfo) == "function" then
        hooksecurefunc("DoCraft", function(index)
            local name = GetCraftInfo(index)
            if type(name) == "string" then
                craftSeries = { name = name, total = 1, done = 0, stamp = GetTime() }
            end
        end)
    end
end

local Blizzard = {}

local FALLBACK_W, FALLBACK_H = 260, 18

local function bz_getBar()
    return _G.PlayerCastingBarFrame or _G.CastingBarFrame
end

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

    o.timeText = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local font, size, flags = o.timeText:GetFont()
    o.timeText:SetFont(font, (size or 10) + 2, flags)
    o.timeText:SetTextColor(1, 1, 1, 1)
    o.timeText:SetPoint("RIGHT", o, "RIGHT", -10, 3)
    o.timeText:SetJustifyH("RIGHT")
    o.timeText:SetText("")

    o.pushText = o:CreateFontString(nil, "OVERLAY")
    o.pushText:SetFont(font, (size or 10) + 2, "OUTLINE")
    o.pushText:SetPoint("BOTTOM", o, "TOP", 0, 4)
    o.pushText:SetTextColor(1, 0.25, 0.25, 1)
    o.pushText:Hide()

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
    if o.clip then o.clip:Hide() end
end

-- Marks the completion end: channels drain leftward, casts fill rightward.
local function bz_showClip(bar, duration, atRight)
    local o = bar and bar._vcui_overlay
    if not o then return end
    if not (mod.db.showClipMarker and duration and duration > 0) then
        if o.clip then o.clip:Hide() end
        return
    end
    if not o.clip then
        o.clip = o:CreateTexture(nil, "ARTWORK", nil, 1)
        o.clip:SetColorTexture(1, 0.82, 0.20, 0.30)
    end
    local barW = bar:GetWidth(); if not barW or barW <= 1 then barW = FALLBACK_W end
    local barH = bar:GetHeight(); if not barH or barH <= 1 then barH = FALLBACK_H end
    local frac = clipSeconds(atRight) / duration
    if frac < 0.05 then frac = 0.05 elseif frac > 0.5 then frac = 0.5 end
    o.clip:ClearAllPoints()
    if atRight then
        o.clip:SetPoint("RIGHT", o, "RIGHT", 0, 3)
    else
        o.clip:SetPoint("LEFT", o, "LEFT", 0, 3)
    end
    o.clip:SetSize(barW * frac, barH)
    o.clip:Show()
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
    local tickH = barH

    for i = 1, linesToDraw do
        local t = o.ticks[i]
        if not t then
            t = o:CreateTexture(nil, "OVERLAY")
            t:SetWidth(2)
            o.ticks[i] = t
        end
        t:SetColorTexture(1, 1, 1, 0.9)
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

        if o._pushUntil then
            local rem = o._pushUntil - GetTime()
            if rem <= 0 then
                o._pushUntil = nil
                o.pushText:Hide()
            else
                o.pushText:SetAlpha(rem > 0.4 and 1 or (rem / 0.4))
            end
        end

        if not self:IsShown() then
            o.timeText:SetText("")
            bz_hideAllTicks(self)
            bz_setChannelColor(self, false)
            return
        end

        local cname, _, _, cstartMS, cendMS, cTrade = UnitChannelInfo("player")
        if cname and cendMS then
            local remaining = (cendMS - (GetTime() * 1000)) / 1000
            if remaining < 0 then remaining = 0 end
            local dur = cstartMS and (cendMS - cstartMS) / 1000
            if mod.db.showTimeText then
                o.timeText:SetText(fmtTime(remaining, dur))
            else
                o.timeText:SetText("")
            end
            local count = tickCountFor(cname, dur, cTrade)
            if count then
                bz_showTicks(self, count)
                bz_showClip(self, dur, false)
            else
                bz_hideAllTicks(self)
            end
            bz_setChannelColor(self, true)
            return
        end

        local name, _, _, startMS, endMS = UnitCastingInfo("player")
        if name and endMS then
            local remaining = (endMS - (GetTime() * 1000)) / 1000
            if remaining < 0 then remaining = 0 end
            local dur = startMS and (endMS - startMS) / 1000
            if mod.db.showTimeText then
                o.timeText:SetText(fmtTime(remaining, dur))
            else
                o.timeText:SetText("")
            end
            bz_hideAllTicks(self)
            bz_showClip(self, dur, true)
            local lbl = seriesLabel(name)
            if lbl and self.Text and self.Text.SetText then
                self.Text:SetText(lbl)
            end
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

local Custom = {}
local cFrame
local castInfo
local c_showTestContent   -- forward declaration: the mover's editPreview closes over this

local function c_hideAllTicks()
    if not cFrame or not cFrame.ticks then return end
    for i = 1, #cFrame.ticks do
        cFrame.ticks[i]:Hide()
        cFrame.ticks[i]:ClearAllPoints()
    end
    if cFrame.clip then cFrame.clip:Hide() end
end

local function c_showClip(duration, atRight)
    if not (cFrame and cFrame.bar) then return end
    if not (mod.db.showClipMarker and duration and duration > 0) then
        if cFrame.clip then cFrame.clip:Hide() end
        return
    end
    if not cFrame.clip then
        cFrame.clip = cFrame.bar:CreateTexture(nil, "OVERLAY", nil, 6)
        cFrame.clip:SetColorTexture(1, 0.82, 0.20, 0.25)
        -- Needs the fill's rounded-corner mask or the square block overhangs the end cap.
        if cFrame._mask and cFrame.clip.AddMaskTexture then
            cFrame.clip:AddMaskTexture(cFrame._mask)
        end
    end
    local barW = cFrame.bar:GetWidth(); if not barW or barW <= 1 then barW = mod.db.width or 240 end
    local barH = cFrame.bar:GetHeight(); if not barH or barH <= 1 then barH = mod.db.height or 18 end
    local frac = clipSeconds(atRight) / duration
    if frac < 0.05 then frac = 0.05 elseif frac > 0.5 then frac = 0.5 end
    cFrame.clip:ClearAllPoints()
    if atRight then
        cFrame.clip:SetPoint("RIGHT", cFrame.bar, "RIGHT", 0, 0)
    else
        cFrame.clip:SetPoint("LEFT", cFrame.bar, "LEFT", 0, 0)
    end
    cFrame.clip:SetSize(barW * frac, barH)
    cFrame.clip:Show()
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
    local tickH = barH

    for i = 1, linesToDraw do
        local t = cFrame.ticks[i]
        if not t then
            -- Parented to the bar, not cFrame, so it draws above the StatusBar texture.
            t = cFrame.bar:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetWidth(2)
            cFrame.ticks[i] = t
        end
        t:SetColorTexture(1, 1, 1, 0.7)
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

-- Near-white base for the tintable fill modes; the yellow/green art muddies any color multiplied onto it.
local TEX_NEUTRAL = "Interface\\AddOns\\VuloClassicUI\\Media\\textures\\matte"

local function c_applyFill(isChannel)
    if not (cFrame and cFrame.bar) then return end
    local fm = mod.db.fillMode or "texture"
    if fm == "texture" then
        cFrame.bar:SetStatusBarTexture(isChannel and TEX_CHANNEL or TEX_FILL)
        if cFrame._applyMask then cFrame._applyMask() end
        c_applyColor({ r = 1, g = 1, b = 1, a = 1 })
        return
    end
    cFrame.bar:SetStatusBarTexture(TEX_NEUTRAL)
    local t = cFrame.bar:GetStatusBarTexture()
    if t then
        if t.SetHorizTile then t:SetHorizTile(false) end
        if t.SetVertTile  then t:SetVertTile(false)  end
    end
    if cFrame._applyMask then cFrame._applyMask() end
    local c
    if fm == "class" then
        local _, token = UnitClass("player")
        c = token and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    end
    c = c or mod.db.accentColor or { r = 0.608, g = 0.424, b = 1.000 }
    c_applyColor({ r = c.r, g = c.g, b = c.b, a = 1 })
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

    cFrame.mover = ns:CreateMover(cFrame, {
        key    = "castbar",
        label  = L["|cffffffffCASTBAR|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = mod.db,
        width  = math.max(mod.db.width + 60, 200),
        height = math.max(60, mod.db.height + 40),
        onMove = function(x, y)
            ns:Print(string.format(L["Castbar position: x=%.0f, y=%.0f"], x, y))
        end,
        editPreview = function(show)
            if show then c_showTestContent()
            elseif not castInfo and not mod.db.unlocked then cFrame:Hide() end
        end,
    })

    -- Mouse stays off cFrame itself; it would conflict with the mover overlay.
    cFrame:EnableMouse(false)

    cFrame.icon = cFrame:CreateTexture(nil, "BORDER")
    cFrame.icon:SetSize(mod.db.iconSize, mod.db.iconSize)
    cFrame.icon:SetPoint("RIGHT", cFrame, "LEFT",
        -(mod.db.iconGap or 3) + (mod.db.iconX or 0), (mod.db.iconY or 0))
    cFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

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

    local function applyMask()
        local fillTex = cFrame.bar:GetStatusBarTexture()
        if fillTex and fillTex.AddMaskTexture then
            if not cFrame._mask then
                cFrame._mask = cFrame.bar:CreateMaskTexture()
                cFrame._mask:SetTexture(TEX_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                cFrame._mask:SetAllPoints(cFrame.bar)
                if cFrame.bg.AddMaskTexture then cFrame.bg:AddMaskTexture(cFrame._mask) end
            end
            -- The StatusBar reuses its texture object across SetStatusBarTexture, so mask once per object.
            if not fillTex._vcui_masked then
                fillTex:AddMaskTexture(cFrame._mask)
                fillTex._vcui_masked = true
            end
        end
    end
    cFrame._applyMask = applyMask
    applyMask()

    cFrame.spark = cFrame.bar:CreateTexture(nil, "OVERLAY")
    cFrame.spark:SetTexture(TEX_SPARK)
    cFrame.spark:SetBlendMode("ADD")
    cFrame.spark:SetSize(16, mod.db.height + 8)

    local font = "Fonts\\FRIZQT__.TTF"
    cFrame.nameText = cFrame:CreateFontString(nil, "OVERLAY")
    cFrame.nameText:SetFont(font, 11, "OUTLINE")
    cFrame.nameText:SetPoint("TOPLEFT", cFrame, "BOTTOMLEFT", 2, -2)
    cFrame.nameText:SetJustifyH("LEFT")
    cFrame.nameText:SetTextColor(1, 1, 1)

    cFrame.timeText = cFrame:CreateFontString(nil, "OVERLAY")
    cFrame.timeText:SetFont(font, 11, "OUTLINE")
    cFrame.timeText:SetPoint("TOPRIGHT", cFrame, "BOTTOMRIGHT", -2, -2)
    cFrame.timeText:SetJustifyH("RIGHT")
    cFrame.timeText:SetTextColor(1, 1, 1)

    cFrame.pushText = cFrame:CreateFontString(nil, "OVERLAY")
    cFrame.pushText:SetFont(font, 12, "OUTLINE")
    cFrame.pushText:SetPoint("BOTTOM", cFrame, "TOP", 0, 3)
    cFrame.pushText:SetTextColor(1, 0.25, 0.25)
    cFrame.pushText:Hide()

    cFrame.pushFlash = cFrame.bar:CreateTexture(nil, "OVERLAY", nil, 5)
    cFrame.pushFlash:SetAllPoints(cFrame.bar)
    cFrame.pushFlash:SetColorTexture(1, 0.2, 0.2, 0.35)
    if cFrame._mask and cFrame.pushFlash.AddMaskTexture then
        cFrame.pushFlash:AddMaskTexture(cFrame._mask)
    end
    cFrame.pushFlash:Hide()

    cFrame.ticks = {}

    cFrame:SetScript("OnUpdate", function(self, elapsed)
        if self._pushUntil then
            local rem = self._pushUntil - GetTime()
            if rem <= 0 then
                self._pushUntil = nil
                self.pushText:Hide()
                self.pushFlash:Hide()
            else
                local a = rem > 0.4 and 1 or (rem / 0.4)
                self.pushText:SetAlpha(a)
                self.pushFlash:SetAlpha(a * 0.35)
            end
        end

        if not castInfo then
            if not (mod.db.unlocked or ns:IsMoverEditMode()) then self:Hide() end
            return
        end
        local nowMS = GetTime() * 1000

        if castInfo.fadeOut then
            castInfo.fadeTimer = (castInfo.fadeTimer or 0) - elapsed
            if castInfo.fadeTimer <= 0 then
                castInfo = nil
                if not (mod.db.unlocked or ns:IsMoverEditMode()) then self:Hide() end
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

        -- Glide at bounded speed so pushback/clipping jumps don't snap.
        local disp = castInfo.disp
        if disp == nil then
            disp = progress
        else
            local diff = progress - disp
            local maxStep = (elapsed or 0) * math.max(4, 2 / duration)
            if diff > maxStep then disp = disp + maxStep
            elseif diff < -maxStep then disp = disp - maxStep
            else disp = progress end
        end
        castInfo.disp = disp

        self.bar:SetValue(disp)
        self.spark:ClearAllPoints()
        self.spark:SetPoint("CENTER", self.bar, "LEFT", self.bar:GetWidth() * disp, 0)

        self._textAcc = (self._textAcc or 0) + elapsed
        if self._textAcc >= 0.05 then
            self._textAcc = 0
            local str = mod.db.showTimeText and fmtTime(remaining, duration) or ""
            if str ~= self._lastTimeText then
                self._lastTimeText = str
                self.timeText:SetText(str)
            end
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
    local name, _, icon, sMS, eMS, cTrade
    if isChannel then
        name, _, icon, sMS, eMS, cTrade = UnitChannelInfo("player")
    else
        name, _, icon, sMS, eMS = UnitCastingInfo("player")
    end
    if not name or not sMS or not eMS then return end

    castInfo = { name = name, icon = icon, startMS = sMS, endMS = eMS, isChannel = isChannel }
    cFrame._textAcc, cFrame._lastTimeText = 1, nil
    cFrame:SetAlpha(1)
    cFrame:Show()
    cFrame.icon:SetTexture(icon)
    cFrame.setIconShown(mod.db.showIcon)
    cFrame.nameText:SetText(mod.db.showSpellName and (seriesLabel(name) or name) or "")

    c_applyFill(isChannel)
    if isChannel then
        local cdur  = sMS and eMS and (eMS - sMS) / 1000
        local count = tickCountFor(name, cdur, cTrade)
        if count then
            c_showTicks(count)
            c_showClip(cdur, false)
        else
            c_hideAllTicks()
        end
        cFrame.spark:Hide()
    else
        local dur = sMS and eMS and (eMS - sMS) / 1000
        c_hideAllTicks()
        c_showClip(dur, true)
        cFrame.spark:Show()
    end
end

local function c_stopCast(success)
    if not cFrame or not castInfo then return end
    -- A late event inside the 0.5s fade window must not restart or recolor it.
    if castInfo.fadeOut then return end
    c_applyColor(success and mod.db.successColor or mod.db.failColor)
    c_hideAllTicks()
    cFrame.spark:Hide()
    -- Snap to the completed state so the fade doesn't start from a mid-frame value.
    if success then cFrame.bar:SetValue(castInfo.isChannel and 0 or 1) end
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
                -- STOP also fires on pushback, so confirm the cast is really over.
                if castInfo and not castInfo.isChannel and not castInfo.fadeOut then
                    local stillCasting = UnitCastingInfo("player")
                    if not stillCasting then
                        c_stopCast(true)
                    end
                end
            elseif event == "UNIT_SPELLCAST_FAILED"
                or event == "UNIT_SPELLCAST_FAILED_QUIET" then
                -- FAILED_QUIET often fires for attempts during an ongoing cast; only abort if nothing is running.
                if castInfo and not castInfo.fadeOut then
                    local stillCasting = UnitCastingInfo("player") or UnitChannelInfo("player")
                    if not stillCasting then
                        c_stopCast(false)
                    end
                end
            elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
                if castInfo then c_stopCast(false) end
            end
        end)
    end

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

c_showTestContent = function()
    cFrame:Show()
    cFrame:SetAlpha(1)
    cFrame.bar:SetValue(0.7)
    cFrame.nameText:SetText(L["|cff9b6cffMind Flay|r"])
    cFrame.timeText:SetText("1.5 / 2.0")
    cFrame.icon:SetTexture("Interface\\Icons\\Spell_Nature_Earthbind")
    cFrame.setIconShown(mod.db.showIcon)
    c_applyFill(true)
    c_showTicks(3)
    c_showClip(3, false)
end

local function c_setUnlocked(state)
    mod.db.unlocked = state
    c_create()
    if state then
        c_showTestContent()
        cFrame.mover:Show()
        ns:Print(L["Castbar mover active. |cff9b6cffDrag purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Test' again to finish."])
    else
        cFrame.mover:Hide()
        c_hideAllTicks()
        if not castInfo then cFrame:Hide() end
        ns:Print(L["Castbar mover disabled."])
    end
end

-- Keeps its own end-time snapshots: event order between this and the mode handlers is undefined.
local function showPushback(txt)
    if mod.db.showPushback == false then return end
    if mod.db.mode == "custom" then
        if cFrame and cFrame.pushText and cFrame:IsShown() then
            cFrame.pushText:SetText(txt)
            cFrame.pushText:SetAlpha(1)
            cFrame.pushText:Show()
            cFrame.pushFlash:SetAlpha(0.35)
            cFrame.pushFlash:Show()
            cFrame._pushUntil = GetTime() + 0.9
        end
    else
        local bar = bz_getBar()
        local o = bar and bar._vcui_overlay
        if o and o.pushText and bar:IsShown() then
            o.pushText:SetText(txt)
            o.pushText:SetAlpha(1)
            o.pushText:Show()
            o._pushUntil = GetTime() + 0.9
        end
    end
end

local tracker
local function ensureTracker()
    if tracker then return end
    tracker = CreateFrame("Frame")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_START",          "player")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_STOP",           "player")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED",        "player")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START",  "player")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    tracker:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP",   "player")
    tracker:SetScript("OnEvent", function(self, event)
        if not mod._enabled then return end

        if event == "UNIT_SPELLCAST_STOP" then
            self.castEnd = nil     -- a stale snapshot would fake a pushback
            return
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            self.chanEnd = nil
            return
        end

        if event == "UNIT_SPELLCAST_START" then
            local name, _, _, _, endMS = UnitCastingInfo("player")
            self.castEnd = endMS
            if craftSeries and name then
                if name == craftSeries.name and (GetTime() - craftSeries.stamp) < 30 then
                    craftSeries.done  = (craftSeries.done or 0) + 1
                    craftSeries.stamp = GetTime()
                else
                    craftSeries = nil
                end
                -- The custom bar may have painted its label before this handler ran, so repaint it.
                if mod.db.mode == "custom" and cFrame and castInfo
                   and not castInfo.isChannel and mod.db.showSpellName then
                    cFrame.nameText:SetText(seriesLabel(name) or name)
                end
            end

        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            self.chanEnd = select(5, UnitChannelInfo("player"))

        elseif event == "UNIT_SPELLCAST_DELAYED" then
            local _, _, _, _, endMS = UnitCastingInfo("player")
            if endMS and self.castEnd and endMS > self.castEnd + 10 then
                showPushback(string.format("+%.1fs", (endMS - self.castEnd) / 1000))
            end
            if endMS then self.castEnd = endMS end

        elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            local endMS = select(5, UnitChannelInfo("player"))
            if endMS and self.chanEnd and endMS < self.chanEnd - 10 then
                showPushback(string.format("-%.1fs", (self.chanEnd - endMS) / 1000))
            end
            if endMS then self.chanEnd = endMS end
        end
    end)
end

local function switchMode(newMode)
    if newMode ~= "blizzard" and newMode ~= "custom" then return end
    mod.db.mode = newMode

    if newMode == "blizzard" then
        Custom:Disable()
        -- The default bar's events cannot be re-registered without a /reload.
        Blizzard:Enable()
    else
        Blizzard:Disable()
        Custom:Enable()
    end
end

function mod:OnEnable()
    -- A saved unlock keeps the castbar visible when nothing is being cast, and
    -- setUnlocked - the only thing that shows the mover - never runs on load.
    if mod.db then mod.db.unlocked = false end
    ensureTracker()
    armCraftHooks()
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
        type = "dropdown", label = L["Timer format"],
        width = 280,
        values = {
            { value = "both",      text = L["Remaining / total (1.5 / 2.0)"] },
            { value = "remaining", text = L["Remaining only (1.5)"] },
            { value = "seconds",   text = L["Whole seconds (2)"] },
        },
        get = function() return mod.db.timeTextMode or "both" end,
        set = function(_, v) mod.db.timeTextMode = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show channel ticks"],
        tooltip = L["Shows vertical lines at tick points (Mind Flay, Drain Soul, Hellfire, etc.)"],
        get = function() return mod.db.showTicks end,
        set = function(_, v) mod.db.showTicks = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show clip window"],
        tooltip = L["Shades your latency at the end of the bar: on channels the moment to recast without losing the last tick, on casts the spell-queue window where the next cast can already be pressed."],
        get = function() return mod.db.showClipMarker end,
        set = function(_, v) mod.db.showClipMarker = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Show pushback"],
        tooltip = L["Briefly shows the time lost to spell pushback in red above the bar."],
        get = function() return mod.db.showPushback ~= false end,
        set = function(_, v) mod.db.showPushback = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Merge crafting casts"],
        tooltip = L["When crafting several items in a row the bar shows a counter like 3/20 instead of single casts."],
        get = function() return mod.db.mergeCrafts ~= false end,
        set = function(_, v) mod.db.mergeCrafts = v end,
    })

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
            type = "dropdown", label = L["Fill color"],
            width = 280,
            tooltip = L["Bar textures = the classic yellow/green art. Accent or class color tint a neutral bar instead."],
            values = {
                { value = "texture", text = L["Bar textures (yellow/green)"] },
                { value = "accent",  text = L["Accent color"] },
                { value = "class",   text = L["Class color"] },
            },
            get = function() return mod.db.fillMode or "texture" end,
            set = function(_, v)
                mod.db.fillMode = v
                if cFrame and cFrame:IsShown() then
                    if castInfo then c_applyFill(castInfo.isChannel)
                    elseif mod.db.unlocked then c_showTestContent() end
                end
            end,
        })
        table.insert(items, { type = "section", title = L["Size & offsets"], collapsed = true, items = {
            { type = "slider", label = L["Width"],
              min = 120, max = 400, step = 5,
              get = function() return mod.db.width end,
              set = function(_, v) mod.db.width = v; c_applyLayout() end },
            { type = "slider", label = L["Height"],
              min = 12, max = 36, step = 1,
              get = function() return mod.db.height end,
              set = function(_, v) mod.db.height = v; c_applyLayout() end },
            { type = "slider", label = L["Icon Size"],
              min = 16, max = 48, step = 1,
              get = function() return mod.db.iconSize end,
              set = function(_, v) mod.db.iconSize = v; c_applyLayout() end },
            { type = "slider", label = L["Icon X Offset"],
              min = -100, max = 100, step = 1,
              tooltip = L["Moves the icon horizontally. Negative = left, positive = right."],
              get = function() return mod.db.iconX or 0 end,
              set = function(_, v) mod.db.iconX = v; c_applyLayout() end },
            { type = "slider", label = L["Icon Y Offset"],
              min = -50, max = 50, step = 1,
              tooltip = L["Moves the icon vertically. Positive = up, negative = down."],
              get = function() return mod.db.iconY or 0 end,
              set = function(_, v) mod.db.iconY = v; c_applyLayout() end },
        } })
    end

    -- Swing timer is a hidden module; embedding its options here avoids a second sidebar entry.
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

SLASH_SCTTEST1 = "/scttest"
SlashCmdList.SCTTEST = function()
    if mod.db.mode == "custom" then
        c_setUnlocked(not mod.db.unlocked)
    else
        ns:Print(L["Test only available in 'Custom Castbar' mode."])
    end
end
