-- =========================================================
-- VuloClassicUI / Modules / GoldTracker
-- Shows in the backpack gold tooltip the balance since the last manual
-- reset: gained, spent, net. Per-char persistent in
-- ns.db.char.goldtracker (survives /reload and logout).
-- Reset via options button or /vcui goldreset.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("goldtracker", {
    name        = "Gold Tracker",
    group       = "QoL",
    description = "Shows in the backpack gold tooltip how much gold has been gained or spent since the last reset. Per-char persistent.",
    defaults    = {
        enabled = true,
    },
})

-- =========================================================
-- Persistent state (per char in VuloClassicUICharDB)
-- =========================================================
local hooked = false

local function data()
    if not (ns.db and ns.db.char) then return nil end
    if not ns.db.char.goldtracker then
        ns.db.char.goldtracker = {
            sessionStart = nil,  -- nil = never initialized
            lastMoney    = nil,
            gained       = 0,
            spent        = 0,
        }
    end
    return ns.db.char.goldtracker
end

-- =========================================================
-- Colors
-- =========================================================
local GOLD_COLOR   = "|cffffd100"
local SILVER_COLOR = "|cffc7c7cf"
local COPPER_COLOR = "|cffeda55f"
local POS_COLOR    = "|cff44ff44"
local NEG_COLOR    = "|cffff4444"
local ACCENT       = "|cff9b6cff"
local GRAY         = "|cffaaaaaa"

-- =========================================================
-- Helpers
-- =========================================================
local function formatCopper(copper)
    copper = math.abs(copper or 0)
    if copper == 0 then return "0" .. COPPER_COLOR .. "c|r" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts+1] = g .. GOLD_COLOR   .. "g|r" end
    if s > 0 then parts[#parts+1] = s .. SILVER_COLOR .. "s|r" end
    if c > 0 then parts[#parts+1] = c .. COPPER_COLOR .. "c|r" end
    if #parts == 0 then return "0" .. COPPER_COLOR .. "c|r" end
    return table.concat(parts, " ")
end

-- Resets the balance to "now". force=true = explicit (button/slash),
-- without force = only if never initialized.
local function initSession(force)
    local d = data()
    if not d then return end
    if d.sessionStart and not force then return end
    d.sessionStart = GetMoney() or 0
    d.lastMoney    = d.sessionStart
    d.gained       = 0
    d.spent        = 0
end

-- On login/reload: sync lastMoney to current WITHOUT including offline delta
-- (AH/mail/trades between sessions) in gained/spent.
-- Initializes the DB if never done.
local function syncOnLogin()
    local d = data()
    if not d then return end
    if not d.sessionStart then
        initSession(false)
    else
        d.lastMoney = GetMoney() or d.lastMoney or 0
    end
end

local function onMoney()
    local d = data()
    if not d then return end
    if not d.sessionStart then
        initSession(false)
        return
    end
    local cur   = GetMoney() or 0
    local delta = cur - (d.lastMoney or cur)
    if delta > 0 then
        d.gained = (d.gained or 0) + delta
    elseif delta < 0 then
        d.spent  = (d.spent or 0) + (-delta)
    end
    d.lastMoney = cur
end

-- =========================================================
-- Public API (for /vcui goldreset and options button)
-- =========================================================
function mod.ResetSession()
    initSession(true)
    local d = data()
    if d then
        ns:Print(ACCENT .. "Gold Tracker reset|r. Start = " .. formatCopper(d.sessionStart))
    end
end

-- =========================================================
-- Tooltip
-- =========================================================
local function showTooltip(self)
    if not mod._enabled then return end
    local d = data()
    if not d then return end
    if not d.sessionStart then initSession(false) end

    -- If a tooltip is already on this frame (e.g. Baganator's
    -- realm/account overview), append lines. Otherwise own tooltip.
    if GameTooltip:GetOwner() ~= self then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    else
        GameTooltip:AddLine(" ")
    end

    GameTooltip:AddLine(ACCENT .. "Gold Balance|r")
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(POS_COLOR .. "Gained:|r", formatCopper(d.gained))
    GameTooltip:AddDoubleLine(NEG_COLOR .. "Spent:|r",  formatCopper(d.spent))

    local net   = (d.gained or 0) - (d.spent or 0)
    local color = net >= 0 and POS_COLOR or NEG_COLOR
    local sign  = net >= 0 and "+" or "-"
    GameTooltip:AddDoubleLine("|cffffffffNet:|r",
        color .. sign .. " " .. formatCopper(net) .. "|r")

    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(GRAY .. "Start:|r", GRAY .. formatCopper(d.sessionStart or 0) .. "|r")
    GameTooltip:AddDoubleLine(GRAY .. "Now:|r",   GRAY .. formatCopper(d.lastMoney or 0)    .. "|r")
    GameTooltip:AddLine(GRAY .. "Reset with /vcui goldreset|r")

    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

-- =========================================================
-- Frame hook
-- Supports Baganator (BaganatorCurrencyWidgetMixin) AND default
-- Blizzard MoneyFrame as fallback. Retries every 3s until found.
-- =========================================================
local function findMoneyFontString(frame, depth)
    if not frame or depth > 8 then return nil end
    local m = rawget(frame, "Money")
    if m and type(m) == "table" then
        local ok, t = pcall(function() return m.GetObjectType and m:GetObjectType() end)
        if ok and t == "FontString" then return m end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            local found = findMoneyFontString(child, depth + 1)
            if found then return found end
        end
    end
    return nil
end

local function hookOnce(frame, withLeave)
    if not frame or frame._vcui_moneyHooked then return false end
    frame._vcui_moneyHooked = true
    frame:HookScript("OnEnter", showTooltip)
    if withLeave then
        frame:HookScript("OnLeave", hideTooltip)
    end
    return true
end

local retryCount = 0
local function tryHook()
    if hooked then return end
    local foundAny = false

    -- 1. Baganator mixin — catches future CurrencyBar instances
    if _G.BaganatorCurrencyWidgetMixin and not mod._baganatorMixinHooked then
        mod._baganatorMixinHooked = true
        hooksecurefunc(_G.BaganatorCurrencyWidgetMixin, "OnLoad", function(widget)
            if widget.Money then hookOnce(widget.Money, false) end
        end)
        foundAny = true
    end

    -- 2. Scan existing Baganator frames
    for name, frame in pairs(_G) do
        if type(name) == "string" and name:find("^Baganator_") and type(frame) == "table" then
            local ok = pcall(function() return frame.GetObjectType end)
            if ok then
                local money = findMoneyFontString(frame, 0)
                if money and hookOnce(money, false) then
                    foundAny = true
                end
            end
        end
    end

    -- 3. Default Blizzard MoneyFrames (fallback without Baganator)
    local defaultFrames = {
        "ContainerFrame1MoneyFrame",
        "BackpackTokenFrameMoneyFrame",
        "MainMenuBarBackpackMoneyFrame",
    }
    for _, name in ipairs(defaultFrames) do
        local f = _G[name]
        if f and f.HookScript and hookOnce(f, true) then
            foundAny = true
        end
    end

    if foundAny then
        hooked = true
        return
    end

    retryCount = retryCount + 1
    if retryCount < 20 and C_Timer and C_Timer.After then
        C_Timer.After(3, tryHook)
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    -- IMPORTANT: NO initSession(true) in OnEnable! Persistent values
    -- must be preserved. syncOnLogin() only syncs lastMoney.
    ns:RegisterEvent("PLAYER_LOGIN", syncOnLogin)
    ns:RegisterEvent("PLAYER_MONEY", onMoney)

    -- If module is enabled later (after PLAYER_LOGIN) via toggle:
    if ns.isInitialised then syncOnLogin() end

    tryHook()
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_LOGIN", syncOnLogin)
    ns:UnregisterEvent("PLAYER_MONEY", onMoney)
    -- HookScripts on MoneyFrame can't be removed,
    -- showTooltip() checks mod._enabled itself.
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = "Gold Tracker" },
        { type = "desc",
          text = "|cffaaaaaaShows in the backpack gold tooltip the balance since the last manual reset:|n"
              .. "  - |cff44ff44Gained|r (quests, loot, vendor sales, mail)|n"
              .. "  - |cffff4444Spent|r (repair, vendor buy, mail cost)|n"
              .. "  - |cffffffffNet|r (+/- since reset)|n|n"
              .. "Values are |cffffffffper-char persistent|r across /reload and logout.|n"
              .. "Offline gold (AH mail, trade) is not counted.|n|n"
              .. "Reset: button below or |cffffff00/vcui goldreset|r.|r" },
        { type = "button", label = "Reset session", width = 200,
          onClick = function() mod.ResetSession() end },
    }
end
