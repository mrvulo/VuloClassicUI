-- =========================================================
-- VuloClassicUI / Modules / Arena / Castbar
-- Custom castbar per arena opponent.
-- =========================================================
local _, ns = ...
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

local castbars = {}  -- slot -> frame

-- =========================================================
-- Build castbar
-- =========================================================
local function createCastbar(parent, slotIndex)
    local f = CreateFrame("StatusBar", "VCUIArenaCastbar" .. slotIndex, parent, "BackdropTemplate")
    f:SetSize(mod.db.castbarWidth, mod.db.castbarHeight)
    f:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f:SetStatusBarColor(1.0, 0.7, 0.0)
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)

    -- Background
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetColorTexture(0, 0, 0, 0.7)

    -- Border
    f:SetBackdrop({
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    -- Icon on the left
    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetSize(mod.db.castbarHeight, mod.db.castbarHeight)
    f.icon:SetPoint("RIGHT", f, "LEFT", -2, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Spell name
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("LEFT",  f, "LEFT",   4, 0)
    f.text:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    f.text:SetJustifyH("LEFT")

    -- Timer on the right
    f.timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.timer:SetPoint("RIGHT", f, "RIGHT", -4, 0)

    -- State
    f.casting   = false
    f.channeling = false
    f.startTime = 0
    f.endTime   = 0

    f:Hide()
    return f
end

local function ensureCastbar(arenaFrame, i)
    if castbars[i] then return castbars[i] end
    local cb = createCastbar(arenaFrame, i)
    castbars[i] = cb
    cb:ClearAllPoints()
    cb:SetPoint("TOP", arenaFrame, "BOTTOM", 0, -2)
    return cb
end

-- =========================================================
-- OnUpdate for running casts
-- =========================================================
local function castbarOnUpdate(self, elapsed)
    if not self.casting and not self.channeling then
        self:Hide()
        return
    end
    local now = GetTime()
    local total = self.endTime - self.startTime
    if total <= 0 then total = 0.01 end  -- guard: instant casts give startTime == endTime
    local progress
    if self.channeling then
        progress = (self.endTime - now) / total
    else
        progress = (now - self.startTime) / total
    end
    progress = math.max(0, math.min(1, progress))
    self:SetValue(progress)

    local remaining = self.endTime - now
    if remaining < 0 then remaining = 0 end
    self.timer:SetText(string.format("%.1f", remaining))

    if now >= self.endTime then
        self.casting = false
        self.channeling = false
        self:Hide()
    end
end

-- =========================================================
-- Start cast
-- =========================================================
local function startCast(unit, channeling)
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local arenaFrame = _G["ArenaEnemyFrame" .. i]
    if not arenaFrame then return end
    local cb = ensureCastbar(arenaFrame, i)
    cb:SetSize(mod.db.castbarWidth, mod.db.castbarHeight)

    local name, _, texture, startTime, endTime
    if channeling then
        name, _, texture, startTime, endTime = UnitChannelInfo(unit)
    else
        name, _, texture, startTime, endTime = UnitCastingInfo(unit)
    end

    if not name or not startTime or not endTime then cb:Hide(); return end

    cb.startTime = startTime / 1000
    cb.endTime   = endTime   / 1000
    cb.casting    = not channeling
    cb.channeling = channeling

    cb.text:SetText(name)
    cb.icon:SetTexture(texture)
    if channeling then
        cb:SetStatusBarColor(0.2, 0.7, 1.0)
    else
        cb:SetStatusBarColor(1.0, 0.7, 0.0)
    end

    cb:Show()
    cb:SetScript("OnUpdate", castbarOnUpdate)
end

local function stopCast(unit, interrupted)
    local i = tonumber(unit:match("^arena(%d)$"))
    if not i then return end
    local cb = castbars[i]
    if not cb then return end
    cb.casting   = false
    cb.channeling = false
    if interrupted then
        cb:SetStatusBarColor(1, 0, 0)
        cb.text:SetText(L["INTERRUPTED"])
        if C_Timer and C_Timer.After then
            C_Timer.After(0.7, function() cb:Hide() end)
        else
            cb:Hide()
        end
    else
        cb:Hide()
    end
end

-- =========================================================
-- Re-anchor castbar (on layout change)
-- =========================================================
local function refreshCastbars()
    H.ForEach(function(frame, i)
        local cb = ensureCastbar(frame, i)
        cb:SetSize(mod.db.castbarWidth, mod.db.castbarHeight)
        cb.icon:SetSize(mod.db.castbarHeight, mod.db.castbarHeight)
        cb:ClearAllPoints()
        cb:SetPoint("TOP", frame, "BOTTOM", 0, -2)
        if not mod.db.castbarEnabled then cb:Hide() end
    end)
end

mod.RefreshCastbars = refreshCastbars

-- =========================================================
-- Events
-- =========================================================
local function isArenaUnit(unit)
    return unit and unit:match("^arena[1-5]$") ~= nil
end

mod:OnArenaFramesReady(function(frame, i)
    ensureCastbar(frame, i)
end)

ns:RegisterEvent("UNIT_SPELLCAST_START", function(_, unit)
    if not mod._enabled or not mod.db.castbarEnabled or not isArenaUnit(unit) then return end
    startCast(unit, false)
end)
ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", function(_, unit)
    if not mod._enabled or not mod.db.castbarEnabled or not isArenaUnit(unit) then return end
    startCast(unit, true)
end)
ns:RegisterEvent("UNIT_SPELLCAST_STOP", function(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, false)
end)
ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, false)
end)
ns:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", function(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, true)
end)
ns:RegisterEvent("UNIT_SPELLCAST_FAILED", function(_, unit)
    if not mod._enabled or not isArenaUnit(unit) then return end
    stopCast(unit, false)
end)

-- =========================================================
-- Options
-- =========================================================
mod:AddOptionsSection("castbar", function()
    return {
        { type = "header", text = L["Castbar"] },
        {
            type = "checkbox", label = L["Castbar for arena opponents"],
            tooltip = L["Shows a castbar below the frame when the opponent casts or channels."],
            get = function() return mod.db.castbarEnabled end,
            set = function(_, v) mod.db.castbarEnabled = v; refreshCastbars() end,
        },
        {
            type = "slider", label = L["Width"],
            min = 60, max = 250, step = 1,
            get = function() return mod.db.castbarWidth end,
            set = function(_, v) mod.db.castbarWidth = v; refreshCastbars() end,
        },
        {
            type = "slider", label = L["Height"],
            min = 8, max = 30, step = 1,
            get = function() return mod.db.castbarHeight end,
            set = function(_, v) mod.db.castbarHeight = v; refreshCastbars() end,
        },
    }
end)
