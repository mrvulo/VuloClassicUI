-- =========================================================
-- VuloClassicUI / Modules / FlightTimer
-- Progress bar for taxi flights (gryphon/wyvern/...): hooks
-- TakeTaxiNode to learn source + destination, times the flight and
-- stores the duration per route. Known routes show a countdown bar,
-- unknown ones count up and are learned on landing.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("flighttimer", {
    name        = "Flight Timer",
    group       = "QoL",
    description = "Shows a progress bar with the duration of taxi flights. Unknown routes are learned on the first flight.",
    defaults    = {
        enabled    = true,
        chatReport = false,
        barWidth   = 240,
        barHeight  = 18,
        x          = 0,
        y          = 280,
        unlocked   = false,
        times      = {},   -- "source @ destination" -> seconds (learned)
    },
})

local FONT = "Fonts\\FRIZQT__.TTF"

-- =========================================================
-- State
-- =========================================================
local bar                 -- the timer bar frame
local flight = nil        -- { src, dst, key, t0, known } while flying
local throttle = 0

local function fmtTime(s)
    s = math.max(0, math.floor(s + 0.5))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function routeKey(src, dst)
    return (src or "?") .. " @ " .. (dst or "?")
end

-- Strip the zone prefix for display ("Shattrath, Terokkar" stays readable)
local function shortName(name)
    if not name then return "?" end
    local cut = name:match("^(.-),") or name
    return cut
end

-- =========================================================
-- Bar
-- =========================================================
local function buildBar()
    if bar then return bar end
    local d = mod.db

    bar = CreateFrame("Frame", "VCUI_FlightTimer", UIParent)
    bar:SetSize(d.barWidth, d.barHeight)
    bar:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
    bar:SetFrameStrata("MEDIUM")
    bar:Hide()

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetColorTexture(0.06, 0.06, 0.08, 0.9)

    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
    bar.fill:SetWidth(1)
    bar.fill:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.9)

    -- thin border
    local bc = ns.COLORS.borderDark or { r = 0.02, g = 0.02, b = 0.03 }
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = bar:CreateTexture(nil, "BORDER")
        t:SetColorTexture(bc.r, bc.g, bc.b, 1)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
        end
    end

    bar.label = bar:CreateFontString(nil, "OVERLAY")
    bar.label:SetFont(FONT, 11, "OUTLINE")
    bar.label:SetPoint("LEFT", bar, "LEFT", 5, 0)
    bar.label:SetPoint("RIGHT", bar, "RIGHT", -52, 0)
    bar.label:SetJustifyH("LEFT")
    bar.label:SetWordWrap(false)

    bar.time = bar:CreateFontString(nil, "OVERLAY")
    bar.time:SetFont(FONT, 11, "OUTLINE")
    bar.time:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    bar.time:SetJustifyH("RIGHT")

    bar.mover = ns:CreateMover(bar, {
        label  = L["|cffffffffFLIGHT TIME|r"],
        db     = mod.db,
        width  = 240,
        height = 30,
        onMove = function(x, y)
            ns:Print(string.format(L["Flight timer: x=%.0f, y=%.0f"], x, y))
        end,
    })

    return bar
end

local function applySize()
    if not bar then return end
    bar:SetSize(mod.db.barWidth, mod.db.barHeight)
end

local function setFill(frac)
    frac = math.max(0, math.min(1, frac or 0))
    local w = (mod.db.barWidth - 2) * frac
    bar.fill:SetWidth(math.max(1, w))
end

-- =========================================================
-- Flight tracking
-- =========================================================
local function stopFlight(recordIt)
    if not flight then return end
    local dur = GetTime() - flight.t0
    -- Only record plausible flights (a cancelled click is shorter than 5s)
    if recordIt and dur > 5 then
        mod.db.times[flight.key] = math.floor(dur + 0.5)
        if mod.db.chatReport then
            ns:Print(L["Flight: %s (%s)"], fmtTime(dur),
                shortName(flight.src) .. " > " .. shortName(flight.dst))
        end
    end
    flight = nil
    if bar then bar:Hide() end
end

local function onTakeTaxi(slot)
    if not mod._enabled then return end
    if not slot or not TaxiNodeName then return end
    local dst = TaxiNodeName(slot)
    if not dst or dst == "" then return end
    local src
    for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
        if TaxiNodeGetType(i) == "CURRENT" then
            src = TaxiNodeName(i)
            break
        end
    end

    local key = routeKey(src, dst)
    flight = {
        src   = src,
        dst   = dst,
        key   = key,
        t0    = GetTime(),
        known = mod.db.times[key],
    }

    buildBar()
    bar.label:SetText(shortName(dst))
    bar.time:SetText(flight.known and fmtTime(flight.known) or L["(learning)"])
    setFill(flight.known and 0 or 1)
    bar:Show()

    -- The click can fail (no money, combat...): if we never took off,
    -- discard the pending flight again.
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            if flight and flight.key == key and not UnitOnTaxi("player") then
                stopFlight(false)
            end
        end)
    end
end

local function onUpdate(_, elapsed)
    throttle = throttle + elapsed
    if throttle < 0.1 then return end
    throttle = 0
    if not flight or not bar or not bar:IsShown() then return end
    if mod.db.unlocked then return end  -- preview owns the bar

    local elapsedT = GetTime() - flight.t0
    if flight.known and flight.known > 0 then
        local remaining = flight.known - elapsedT
        if remaining < 0 then remaining = 0 end
        setFill(elapsedT / flight.known)
        bar.time:SetText(fmtTime(remaining))
    else
        setFill(1)
        bar.time:SetText(fmtTime(elapsedT) .. " " .. L["(learning)"])
    end
end

local function onControlGained()
    -- Fires on landing (and on fear end etc. — hence the taxi check)
    if flight and not UnitOnTaxi("player") then
        stopFlight(true)
    end
end

local function onWorldEnter()
    -- Logged in / zoned while not flying but with stale state -> clean up
    if flight and not UnitOnTaxi("player") then
        local dur = GetTime() - flight.t0
        stopFlight(dur > 5)
    end
end

-- =========================================================
-- Mover / preview
-- =========================================================
local function setUnlocked(state)
    mod.db.unlocked = state
    buildBar()
    if state then
        bar.label:SetText(L["Flight Timer"])
        bar.time:SetText("1:23")
        setFill(0.45)
        bar:Show()
        bar.mover:Show()
        ns:Print(L["Flight timer mover active. |cff9b6cffDrag|r or |cff9b6cffarrow keys|r (SHIFT = 5px)."])
    else
        bar.mover:Hide()
        if not (flight and UnitOnTaxi("player")) then bar:Hide() end
        ns:Print(L["Flight timer mover disabled."])
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
local taxiHooked = false

function mod:OnEnable()
    buildBar()
    bar:SetScript("OnUpdate", onUpdate)
    if not taxiHooked and type(TakeTaxiNode) == "function" then
        taxiHooked = true  -- hooksecurefunc is permanent; gate on mod._enabled
        hooksecurefunc("TakeTaxiNode", onTakeTaxi)
    end
    ns:RegisterEvent("PLAYER_CONTROL_GAINED", onControlGained)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", onWorldEnter)
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_CONTROL_GAINED", onControlGained)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", onWorldEnter)
    flight = nil
    if bar then
        bar:SetScript("OnUpdate", nil)
        if bar.mover then bar.mover:Hide() end
        bar:Hide()
    end
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local function learnedCount()
        local n = 0
        for _ in pairs(mod.db.times) do n = n + 1 end
        return n
    end

    return {
        { type = "header", text = L["Flight Timer"] },
        { type = "desc",
          text = L["|cffaaaaaaShows a bar with destination and remaining time while on a taxi. The first flight of a route counts up and is saved; from then on you get a countdown.|r"] },
        { type = "spacer", height = 4 },

        { type = "toggle", label = L["Print flight time to chat"],
          tooltip = L["After landing, prints the measured flight time."],
          get = function() return mod.db.chatReport end,
          set = function(_, v) mod.db.chatReport = v end },

        { type = "slider", label = L["Bar width"],
          min = 140, max = 400, step = 5,
          get = function() return mod.db.barWidth end,
          set = function(_, v) mod.db.barWidth = v; applySize() end },
        { type = "slider", label = L["Bar height"],
          min = 12, max = 30, step = 1,
          get = function() return mod.db.barHeight end,
          set = function(_, v) mod.db.barHeight = v; applySize() end },

        { type = "spacer", height = 6 },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Unlock / Position"], width = 200,
              onClick = function() setUnlocked(not mod.db.unlocked) end },
            { type = "button", label = L["Reset learned times"], width = 200,
              tooltip = L["Deletes all saved route durations."],
              onClick = function()
                  mod.db.times = {}
                  ns:Print(L["Learned flight times reset."])
              end },
        } },
        { type = "desc",
          text = string.format(L["|cffaaaaaaLearned routes: %d|r"], learnedCount()) },
    }
end
