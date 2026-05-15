-- =========================================================
-- VuloClassicUI / Modules / GoldTracker
-- Zeigt im Backpack-Gold-Tooltip die Bilanz seit dem letzten manuellen
-- Reset: Erhalten, Ausgegeben, Netto. Pro Char persistent in
-- ns.db.char.goldtracker (überlebt /reload und Logout).
-- Reset via Options-Button oder /vcui goldreset.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("goldtracker", {
    name        = "Gold Tracker",
    group       = "QoL",
    description = "Zeigt im Backpack-Gold-Tooltip wieviel Gold seit dem letzten Reset dazugekommen oder ausgegeben wurde. Pro Char persistent.",
    defaults    = {
        enabled = true,
    },
})

-- =========================================================
-- Persistent State (pro Char in VuloClassicUICharDB)
-- =========================================================
local hooked = false

local function data()
    if not (ns.db and ns.db.char) then return nil end
    if not ns.db.char.goldtracker then
        ns.db.char.goldtracker = {
            sessionStart = nil,  -- nil = noch nie initialisiert
            lastMoney    = nil,
            gained       = 0,
            spent        = 0,
        }
    end
    return ns.db.char.goldtracker
end

-- =========================================================
-- Farben
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

-- Resettet die Bilanz auf "jetzt". force=true = explizit (Button/Slash),
-- ohne force = nur wenn noch nie initialisiert wurde.
local function initSession(force)
    local d = data()
    if not d then return end
    if d.sessionStart and not force then return end
    d.sessionStart = GetMoney() or 0
    d.lastMoney    = d.sessionStart
    d.gained       = 0
    d.spent        = 0
end

-- Bei Login/Reload: lastMoney auf current syncen OHNE offline-Delta
-- (AH/Mail/Trades zwischen Sessions) in gained/spent einzurechnen.
-- Initialisiert die DB falls noch nie geschehen.
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
-- Public API (für /vcui goldreset und Options-Button)
-- =========================================================
function mod.ResetSession()
    initSession(true)
    local d = data()
    if d then
        ns:Print(ACCENT .. "Gold-Tracker zur\195\188ckgesetzt|r. Start = " .. formatCopper(d.sessionStart))
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

    -- Wenn schon ein Tooltip auf diesem Frame liegt (z.B. Baganators
    -- Realm/Account-Übersicht), Lines anhängen. Sonst eigenen Tooltip.
    if GameTooltip:GetOwner() ~= self then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    else
        GameTooltip:AddLine(" ")
    end

    GameTooltip:AddLine(ACCENT .. "Gold-Bilanz|r")
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(POS_COLOR .. "Erhalten:|r",   formatCopper(d.gained))
    GameTooltip:AddDoubleLine(NEG_COLOR .. "Ausgegeben:|r", formatCopper(d.spent))

    local net   = (d.gained or 0) - (d.spent or 0)
    local color = net >= 0 and POS_COLOR or NEG_COLOR
    local sign  = net >= 0 and "+" or "-"
    GameTooltip:AddDoubleLine("|cffffffffNetto:|r",
        color .. sign .. " " .. formatCopper(net) .. "|r")

    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(GRAY .. "Start:|r", GRAY .. formatCopper(d.sessionStart or 0) .. "|r")
    GameTooltip:AddDoubleLine(GRAY .. "Jetzt:|r", GRAY .. formatCopper(d.lastMoney or 0)    .. "|r")
    GameTooltip:AddLine(GRAY .. "Reset mit /vcui goldreset|r")

    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

-- =========================================================
-- Frame-Hook
-- Unterstützt Baganator (BaganatorCurrencyWidgetMixin) UND default
-- Blizzard MoneyFrame als Fallback. Retry alle 3s bis was gefunden ist.
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

    -- 1. Baganator Mixin — greift bei künftigen CurrencyBar-Instanzen
    if _G.BaganatorCurrencyWidgetMixin and not mod._baganatorMixinHooked then
        mod._baganatorMixinHooked = true
        hooksecurefunc(_G.BaganatorCurrencyWidgetMixin, "OnLoad", function(widget)
            if widget.Money then hookOnce(widget.Money, false) end
        end)
        foundAny = true
    end

    -- 2. Existierende Baganator-Frames durchsuchen
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

    -- 3. Default Blizzard MoneyFrames (Fallback ohne Baganator)
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
    -- WICHTIG: KEIN initSession(true) bei OnEnable! Persistente Werte
    -- müssen erhalten bleiben. syncOnLogin() macht NUR lastMoney sync.
    ns:RegisterEvent("PLAYER_LOGIN", syncOnLogin)
    ns:RegisterEvent("PLAYER_MONEY", onMoney)

    -- Falls Modul später (nach PLAYER_LOGIN) per Toggle aktiviert wird:
    if ns.isInitialised then syncOnLogin() end

    tryHook()
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_LOGIN", syncOnLogin)
    ns:UnregisterEvent("PLAYER_MONEY", onMoney)
    -- HookScripts auf MoneyFrame können nicht entfernt werden,
    -- showTooltip() prüft selbst mod._enabled.
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = "Gold Tracker" },
        { type = "desc",
          text = "|cffaaaaaaZeigt im Backpack-Gold-Tooltip die Bilanz seit dem letzten manuellen Reset:|n"
              .. "  • |cff44ff44Erhalten|r (Quest, Loot, Vendor-Verkauf, Mail)|n"
              .. "  • |cffff4444Ausgegeben|r (Repair, Vendor-Kauf, Mail-Cost)|n"
              .. "  • |cffffffffNetto|r (+/− seit Reset)|n|n"
              .. "Werte sind |cffffffffpro Char persistent|r über /reload und Logout.|n"
              .. "Offline-Gold (AH-Mail, Trade) wird nicht eingerechnet.|n|n"
              .. "Reset: Button unten oder |cffffff00/vcui goldreset|r.|r" },
        { type = "button", label = "Session zurücksetzen", width = 200,
          onClick = function() mod.ResetSession() end },
    }
end
