-- VuloClassicUI / Modules / Bugfixes — one IIFE per fix so file-level locals stay isolated.

(function(...)
-- Blizzard (deDE): auction house references an undefined PriceDropdown — provide a stub frame.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixauctiondropdown", {
    name        = "Auction Price Fix",
    group       = "Bugfixes",
    description = "Fixes a nil error in the German auction house UI (PriceDropdown not defined).",
    defaults = {
        enabled = true,
    },
})

local applied = false

local function applyFix()
    if applied then return end
    applied = true

    if GetLocale() == "deDE" and not _G.PriceDropdown then
        local f = CreateFrame("Frame", "PriceDropdown", UIParent)
        f.Text           = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.HideSpacerFrame = CreateFrame("Frame", nil, f)
    end
end

function mod:OnEnable()
    applyFix()
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Info"] },
        { type = "desc", text = L["This fix addresses a known bug in the German WoW localization: the auction house UI references a \"PriceDropdown\" element that was never defined, which causes Lua errors when opening the auction house."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaCurrent locale: %s|r"], GetLocale() or "?") },
        { type = "desc", text = L["|cffaaaaaaThe fix only applies on German clients (deDE). On other languages the module is inactive.|r"] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            applied and (_G.PriceDropdown and L["|cff66ff66applied|r"] or L["skipped (deDE-only)"]) or L["not applied"]) },
    }
end

end)(...);

(function(...)
-- Blizzard: broken guild news entries throw "formatString" errors and kill the panel — xpcall + fallback row.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixguildnews", {
    name        = "Guild News Nil Fix",
    group       = "Bugfixes",
    description = "Catches Lua errors in guild news entries (typically \"formatString\" or \"GuildUtil\") and replaces broken entries with a fallback text instead of letting the whole panel break.",
    defaults = {
        enabled    = true,
        showReport = true,
    },
})

local unpack = unpack or table.unpack

local function safeSetText(obj, text)
    if obj and obj.SetText then obj:SetText(text or "") end
end

local function safeHide(obj)
    if obj and obj.Hide then obj:Hide() end
end

local function safeShow(obj)
    if obj and obj.Show then obj:Show() end
end

local function applyFallbackToButton(button)
    if not button then return end

    safeSetText(button.Name, L["|cffff8080Invalid guild news entry|r"])
    safeSetText(button.Header, "")
    safeSetText(button.Time, "")
    safeSetText(button.Description, "")

    if button.Icon and button.Icon.SetTexture then button.Icon:SetTexture(nil) end
    if button.icon and button.icon.SetTexture then button.icon:SetTexture(nil) end

    safeHide(button.Highlight)
    safeHide(button.NewMarker)
    safeHide(button.newsTypeIcon)

    safeShow(button)
    if button.Enable then button:Enable() end
end

local wrappedAlready = false

local function installPatch()
    if wrappedAlready then return end
    if type(_G.GuildNewsButton_SetNews) ~= "function" then return end

    local Original = _G.GuildNewsButton_SetNews

    _G.GuildNewsButton_SetNews = function(button, newsInfo, ...)
        if not mod._enabled then
            return Original(button, newsInfo, ...)
        end

        local args = { ... }
        local ok, err = xpcall(function()
            return Original(button, newsInfo, unpack(args))
        end, function(e) return e end)

        if ok then return end

        local errText = tostring(err or "")
        if errText:find("formatString") or errText:find("GuildUtil") then
            applyFallbackToButton(button)
            if mod.db.showReport and not _G.VCUI_GuildNewsNilFix_Reported then
                _G.VCUI_GuildNewsNilFix_Reported = true
                DEFAULT_CHAT_FRAME:AddMessage(
                    L["|cffffff00[VuloClassicUI]|r Blizzard guild news error caught (fallback applied)."])
            end
            return
        end

        error(errText, 0)   -- level 0: keep Blizzard's original message/location
    end

    wrappedAlready = true
end

local installFrame

function mod:OnEnable()
    if not installFrame then
        installFrame = CreateFrame("Frame")
        installFrame:RegisterEvent("ADDON_LOADED")
        installFrame:SetScript("OnEvent", function(self, _, addonName)
            if addonName == "Blizzard_Communities" then
                installPatch()
                self:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end

    installPatch()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, installPatch)
    end
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Behavior"] },
        {
            type = "toggle", label = L["Chat message on first error"],
            tooltip = L["Shows a brief message once per session in chat when a guild news error was caught."],
            get = function() return mod.db.showReport end,
            set = function(_, v) mod.db.showReport = v end,
        },
        { type = "spacer", height = 8 },
        { type = "desc", text = L["This fix wraps Blizzard's |cffffffffGuildNewsButton_SetNews|r function in a protected call (xpcall). When an entry throws a known error (\"formatString\" or \"GuildUtil\"), the entry is replaced with a fallback text \"Invalid guild news entry\" — the panel remains usable."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            wrappedAlready and L["|cff66ff66Hook active|r"] or L["waiting for Blizzard_Communities"]) },
    }
end

end)(...);

(function(...)
-- Blizzard: LFGBrowseSearchEntry_Update crashes on stale resultIDs (GetSearchResultInfo nil) — xpcall, next refresh cleans up.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixlfgbrowsenil", {
    name        = "LFG Browse Nil Fix",
    group       = "Bugfixes",
    description = "Catches Lua errors in the Anniversary Group Finder (LFGBrowseSearchEntry_Update with stale resultIDs). Prevents chat spam and broken browse lists.",
    defaults = {
        enabled    = true,
        showReport = true,
    },
})

local unpack = unpack or table.unpack

local wrappedAlready = false

local function installPatch()
    if wrappedAlready then return end
    if type(_G.LFGBrowseSearchEntry_Update) ~= "function" then return end

    local Original = _G.LFGBrowseSearchEntry_Update

    _G.LFGBrowseSearchEntry_Update = function(button, ...)
        if not mod._enabled then
            return Original(button, ...)
        end

        local args = { ... }
        local ok, err = xpcall(function()
            return Original(button, unpack(args))
        end, function(e) return e end)

        if ok then return end

        local errText = tostring(err or "")
        if errText:find("searchResultInfo") or errText:find("attempt to index") then
            if mod.db.showReport and not _G.VCUI_LFGBrowseNilFix_Reported then
                _G.VCUI_LFGBrowseNilFix_Reported = true
                DEFAULT_CHAT_FRAME:AddMessage(
                    L["|cffffff00[VuloClassicUI]|r Blizzard LFG browse error caught (stale entry skipped)."])
            end
            return
        end

        error(errText, 0)   -- level 0: keep Blizzard's original message/location
    end

    wrappedAlready = true
end

local installFrame

function mod:OnEnable()
    if not installFrame then
        installFrame = CreateFrame("Frame")
        installFrame:RegisterEvent("ADDON_LOADED")
        installFrame:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_GroupFinder_VanillaStyle" then
                installPatch()
            end
        end)
    end

    installPatch()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, installPatch)
    end
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Behavior"] },
        {
            type = "toggle", label = L["Chat message on first error"],
            tooltip = L["Shows a brief message once per session in chat when an LFG browse error was caught."],
            get = function() return mod.db.showReport end,
            set = function(_, v) mod.db.showReport = v end,
        },
        { type = "spacer", height = 8 },
        { type = "desc", text = L["This fix wraps Blizzard's |cffffffffLFGBrowseSearchEntry_Update|r function in a protected call (xpcall). When the entry crashes due to a stale resultID (\"searchResultInfo nil\"), the error is swallowed — Blizzard's next refresh automatically cleans up the list entry."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            wrappedAlready and L["|cff66ff66Hook active|r"] or L["waiting for Blizzard_GroupFinder_VanillaStyle"]) },
    }
end

end)(...);

(function(...)
-- Blizzard: inspect server state gets stuck (empty frame / stale target / works only on 2nd try) because ClearInspectPlayer is never reliably called — watchdog + OnHide reset.
-- Taint: NEVER replace the global inspect functions; that taints the secure unit-popup menu and blocks whisper / raid-frame Show. Post-hook only.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixinspect", {
    name        = "Inspect Fix",
    group       = "Bugfixes",
    description = "Fixes stuck inspect bugs (no player inspect possible after a faulty close/timeout). Auto-reset after a timeout, auto-retry when the window stays empty, cleanup when InspectFrame closes + /inspectreset slash command.",
    defaults = {
        enabled    = true,
        autoReset  = true,
        autoRetry  = true,
        timeoutSec = 5,
    },
})

local _activeGUID         = nil
local _activeTime         = 0
local _hookedFrame        = false
local _inspectHooked      = false
local _watchdog
local _lastNotify         = 0
local _retriedGUID        = nil   -- one automatic re-request per inspected target

-- softReset keeps InspectFrame.unit (an open frame still needs it for tooltips); hardReset clears it.
local function softReset()
    if _G.ClearInspectPlayer then
        pcall(_G.ClearInspectPlayer)
    end
    _activeGUID = nil
    _activeTime = 0
end

local function hardReset()
    softReset()
    _retriedGUID = nil
    local f = _G.InspectFrame
    if f then f.unit = nil end
end

-- Blizzard: INSPECT_READY fires before item data has streamed in and the paperdoll paints only once — repaint late, re-request if still empty.
local INSPECT_SLOT_NAMES = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
    "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0",
    "Trinket1", "MainHand", "SecondaryHand", "Ranged",
}

local function repaintInspectSlots()
    local f   = _G.InspectFrame
    local upd = _G.InspectPaperDollItemSlotButton_Update
    if not (f and f:IsShown() and f.unit and upd) then return end
    for _, name in ipairs(INSPECT_SLOT_NAMES) do
        local btn = _G["Inspect" .. name .. "Slot"]
        if btn then pcall(upd, btn) end
    end
end

local function hasAnyInspectItem(unit)
    for slot = 1, 19 do
        if GetInventoryItemLink(unit, slot) then return true end
    end
    return false
end

-- Returns true only if a request was actually sent (a refusal must not re-arm the watchdog).
local function retryInspect(guid)
    local f = _G.InspectFrame
    if not (f and f:IsShown() and f.unit) then return false end
    if UnitGUID(f.unit) ~= guid then return false end
    if _retriedGUID == guid then return false end               -- one shot per target
    if GetTime() - _lastNotify < 1 then return false end        -- server throttle
    if _G.CanInspect and not _G.CanInspect(f.unit) then return false end
    if not _G.NotifyInspect then return false end
    _retriedGUID = guid
    _G.NotifyInspect(f.unit)
    return true
end

local function onInspectReady(_, guid)
    -- clear tracking only; don't reset, the UI still needs the data
    _activeGUID = nil
    _activeTime = 0

    if not (mod._enabled and mod.db and mod.db.autoRetry ~= false) then return end
    local f = _G.InspectFrame
    if not (guid and f and f:IsShown() and f.unit and UnitGUID(f.unit) == guid) then return end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.4, function()
            if not mod._enabled then return end
            local fr = _G.InspectFrame
            if fr and fr:IsShown() and fr.unit and UnitGUID(fr.unit) == guid then
                repaintInspectSlots()
            end
        end)
        -- attempt 2 covers the 1s NotifyInspect throttle eating the first try
        local function emptyCheck(attempt)
            if not mod._enabled then return end
            local fr = _G.InspectFrame
            if not (fr and fr:IsShown() and fr.unit and UnitGUID(fr.unit) == guid) then return end
            repaintInspectSlots()
            if hasAnyInspectItem(fr.unit) then return end
            if not retryInspect(guid) and attempt < 2 and _retriedGUID ~= guid then
                C_Timer.After(1.0, function() emptyCheck(attempt + 1) end)
            end
        end
        C_Timer.After(1.2, function() emptyCheck(1) end)
    end
end

-- Post-hook only: the hook runs after the request, so state can't be cleared up front — the watchdog does it instead.
local function installInspectTracking()
    if _inspectHooked or type(_G.NotifyInspect) ~= "function" then return end
    _inspectHooked = true
    hooksecurefunc("NotifyInspect", function(unit)
        _lastNotify = GetTime()
        if unit and UnitExists(unit) then
            _activeGUID = UnitGUID(unit)
            _activeTime = GetTime()
        end
    end)
end

-- Blizzard: inspect-slot OnEnter shows no tooltip while item data is still streaming and never retries — replaced (tooltip-only, taint-legal); UpdateTooltip re-invokes this until data lands.
local function inspectSlotOnEnter(self)
    if not mod._enabled then
        if self._vcuiOrigEnter then self._vcuiOrigEnter(self) end
        return
    end
    local fr = _G.InspectFrame
    local unit = (fr and fr.unit) or "target"
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip:SetInventoryItem(unit, self:GetID()) then
        GameTooltip:Show()
        return
    end
    local slot = self:GetID()
    local link = GetInventoryItemLink and GetInventoryItemLink(unit, slot)
    if link then
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
        return
    end
    local tex = GetInventoryItemTexture and GetInventoryItemTexture(unit, slot)
    if tex then
        -- occupied but uncached: request the data, show a stub until it lands
        local id = GetInventoryItemID and GetInventoryItemID(unit, slot)
        if id and GetItemInfo then GetItemInfo(id) end
        GameTooltip:SetText(_G.RETRIEVING_ITEM_INFO or "...", 1, 0.82, 0)
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

local function hardenInspectTooltips()
    for _, name in ipairs(INSPECT_SLOT_NAMES) do
        local btn = _G["Inspect" .. name .. "Slot"]
        if btn and not btn._vcuiTipFixed then
            btn._vcuiTipFixed = true
            btn._vcuiOrigEnter = btn:GetScript("OnEnter")
            btn:SetScript("OnEnter", inspectSlotOnEnter)
            btn.UpdateTooltip = inspectSlotOnEnter
        end
    end
end

local function hookInspectFrame()
    if _hookedFrame then return end
    local f = _G.InspectFrame
    if not f then return end
    hardenInspectTooltips()
    f:HookScript("OnHide", function()
        if mod._enabled then hardReset() end
    end)
    _hookedFrame = true
end

local function watchdogTick()
    if not mod._enabled or not mod.db or not mod.db.autoReset then return end
    if _activeTime == 0 then return end
    local timeout = mod.db.timeoutSec or 5
    if GetTime() - _activeTime <= timeout then return end

    -- Retry before clearing: ClearInspectPlayer would leave an open frame permanently empty.
    local f = _G.InspectFrame
    local stuckGUID = _activeGUID
    if mod.db.autoRetry ~= false and stuckGUID and _retriedGUID ~= stuckGUID
        and f and f:IsShown() and f.unit and UnitGUID(f.unit) == stuckGUID then
        if retryInspect(stuckGUID) then return end   -- hook re-armed tracking
    end
    softReset()
end

_G.SLASH_VCUIINSPECTRESET1 = "/inspectreset"
_G.SlashCmdList["VCUIINSPECTRESET"] = function()
    hardReset()
    if _G.InspectFrame and _G.InspectFrame:IsShown() then
        _G.InspectFrame:Hide()
    end
    if ns and ns.Print then
        ns:Print(L["Inspect state manually reset. Try again now."])
    else
        DEFAULT_CHAT_FRAME:AddMessage(L["|cffffff00[VuloClassicUI]|r Inspect state reset."])
    end
end

_G.SLASH_VCUIINSPECTSTATE1 = "/inspectstate"
_G.SlashCmdList["VCUIINSPECTSTATE"] = function()
    local f = _G.InspectFrame
    local lines = {
        "|cffffff00[VuloClassicUI Inspect State]|r",
        string.format("  NotifyInspect hook:     %s", _inspectHooked and "yes" or "no"),
        string.format("  InspectFrame hook:      %s", _hookedFrame  and "yes" or "no"),
        string.format("  Active GUID:            %s", tostring(_activeGUID)),
        string.format("  Active time:            %s", _activeTime > 0 and string.format("%.1fs ago", GetTime() - _activeTime) or "none"),
        string.format("  InspectFrame.unit:      %s", f and tostring(f.unit) or "no frame"),
        string.format("  InspectFrame shown:     %s", (f and f:IsShown()) and "yes" or "no"),
        string.format("  Last NotifyInspect:     %s", _lastNotify > 0 and string.format("%.1fs ago", GetTime() - _lastNotify) or "none"),
        string.format("  Auto-retry used:        %s", _retriedGUID and "yes (this target)" or "no"),
        string.format("  Slots with data:        %s", (f and f:IsShown() and f.unit) and (hasAnyInspectItem(f.unit) and "yes" or "NONE") or "-"),
    }
    for _, line in ipairs(lines) do
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end
end

local installFrame

function mod:OnEnable()
    if not mod.db then return end

    installInspectTracking()
    hookInspectFrame()

    -- Blizzard_InspectUI is lazy-loaded on first inspect
    if not installFrame then
        installFrame = CreateFrame("Frame")
        installFrame:SetScript("OnEvent", function(self, _, addonName)
            if addonName == "Blizzard_InspectUI" then
                hookInspectFrame()
                self:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end
    if not (IsAddOnLoaded and IsAddOnLoaded("Blizzard_InspectUI")) then
        installFrame:RegisterEvent("ADDON_LOADED")
    end

    ns:RegisterEvent("INSPECT_READY", onInspectReady)

    if not _watchdog and C_Timer and C_Timer.NewTicker then
        _watchdog = C_Timer.NewTicker(2, watchdogTick)
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("INSPECT_READY", onInspectReady)
    if _watchdog then _watchdog:Cancel(); _watchdog = nil end
    -- the NotifyInspect post-hook stays (hooksecurefunc can't be removed); harmless while off
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Behavior"] },

        { type = "toggle", label = L["Auto-reset on timeout"],
          tooltip = L["If no response from the server comes after X seconds, the pending inspect state is automatically reset — so the next inspect attempt works again."],
          get = function() return mod.db.autoReset ~= false end,
          set = function(_, v) mod.db.autoReset = v end },

        { type = "toggle", label = L["Auto-retry empty inspects"],
          tooltip = L["After the server answers, the item slots are repainted again shortly after (data often arrives late). If the window is still completely empty, the inspect is automatically requested one more time."],
          get = function() return mod.db.autoRetry ~= false end,
          set = function(_, v) mod.db.autoRetry = v end },

        { type = "slider", label = L["Timeout (seconds)"],
          min = 3, max = 20, step = 1,
          tooltip = L["How long to wait for INSPECT_READY before auto-reset kicks in. 5 seconds is the new default for Anniversary — fast enough to recover quickly."],
          get = function() return mod.db.timeoutSec or 5 end,
          set = function(_, v) mod.db.timeoutSec = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Manual Reset"] },
        { type = "button", label = L["Reset inspect state now"], width = 240,
          onClick = function()
              hardReset()
              if _G.InspectFrame and _G.InspectFrame:IsShown() then
                  _G.InspectFrame:Hide()
              end
              ns:Print(L["Inspect state manually reset."])
          end },
        { type = "desc", text = L["|cffaaaaaaSlash commands: /inspectreset (force-reset), /inspectstate (debug info in chat)|r"] },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Status"] },
        { type = "desc", text = string.format(
            L["NotifyInspect hook: %s\nInspectFrame hook: %s"],
            _inspectHooked and L["|cff66ff66active|r"] or L["|cffff8800waiting|r"],
            _hookedFrame   and L["|cff66ff66active|r"] or L["|cffff8800waiting for Blizzard_InspectUI|r"]) },
        { type = "spacer", height = 4 },
        { type = "desc", text = L["|cffaaaaaaWhat the fix does: tracks active inspects with a timestamp, repaints late-arriving item data, re-requests an all-empty inspect once, and calls ClearInspectPlayer() on close + on timeout. Prevents a stuck state from blocking all subsequent inspects.|r"] },
    }
end

end)(...);

(function(...)
-- Blizzard (2.5.5): StaticPopup "BIND_SOCKET" is missing, so binding gem socketing errors out — re-add the dialog.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixbindsocket", {
    name        = "Bind-on-Socket Fix",
    group       = "Bugfixes",
    description = "Re-adds the missing BIND_SOCKET confirmation dialog so socketing a gem that binds the item no longer throws a Lua error (Anniversary client).",
    defaults = { enabled = true },
})

local function installFix()
    local dialogs = _G.StaticPopupDialogs
    if not dialogs or dialogs["BIND_SOCKET"] then return end
    dialogs["BIND_SOCKET"] = {
        text         = _G.BIND_SOCKET or L["Socketing this gem will bind the item to you. Continue?"],
        button1      = _G.ACCEPT or "Accept",
        button2      = _G.CANCEL or "Cancel",
        OnAccept     = function() if _G.AcceptSockets then _G.AcceptSockets() end end,
        timeout      = 0,
        whileDead    = 1,
        hideOnEscape = 1,
        showAlert    = 1,
    }
end

function mod:OnEnable()
    installFix()
end

function mod:GetOptions()
    local defined = _G.StaticPopupDialogs and _G.StaticPopupDialogs["BIND_SOCKET"] ~= nil
    return {
        { type = "header", text = L["Bind-on-Socket Fix"] },
        { type = "desc", text = L["The Anniversary client is missing the |cffffffffBIND_SOCKET|r confirmation dialog. Socketing a gem that would bind the item then throws \"Dialog BIND_SOCKET does not exist\" and aborts. This re-adds the dialog so socketing works."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            defined and L["|cff66ff66Dialog defined|r"] or L["not defined yet"]) },
    }
end

end)(...);

(function(...)
-- Blizzard: the player frame no longer flashes red in combat — add our own portrait glow.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixcombatglow", {
    name        = "Combat Indicator",
    group       = "Bugfixes",
    description = "Restores the missing 'in combat' glow on the Player frame (Anniversary default-UI bug). Pulses a red glow around your portrait while you are in combat.",
    defaults = {
        enabled = true,
    },
})

local glow

local function ensureGlow()
    if glow then return glow end
    local pf = _G.PlayerFrame
    if not pf then return nil end

    glow = pf:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\COMMON\\RingBorder")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.18, 0.18, 1)

    local portrait = _G.PlayerPortrait
    if portrait then
        glow:SetPoint("CENTER", portrait, "CENTER", 0, 0)
        local w, h = portrait:GetSize()
        if not w or w == 0 then w, h = 56, 56 end
        glow:SetSize(w * 1.32, h * 1.32)
    else
        glow:SetPoint("CENTER", pf, "TOPLEFT", 40, -25)
        glow:SetSize(74, 74)
    end

    glow.anim = glow:CreateAnimationGroup()
    glow.anim:SetLooping("BOUNCE")
    local a = glow.anim:CreateAnimation("Alpha")
    a:SetFromAlpha(1.0)
    a:SetToAlpha(0.35)
    a:SetDuration(0.7)

    glow:Hide()
    return glow
end

local function update()
    local g = ensureGlow()
    if not g then return end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        g:Show()
        if g.anim then g.anim:Play() end
    else
        if g.anim then g.anim:Stop() end
        g:Hide()
    end
end

function mod:OnEnable()
    ensureGlow()
    ns:RegisterEvent("PLAYER_REGEN_DISABLED", update)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",  update)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", update)
    update()
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED", update)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",  update)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", update)
    if glow then
        if glow.anim then glow.anim:Stop() end
        glow:Hide()
    end
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Combat Indicator"] },
        { type = "desc", text = L["|cffaaaaaaThe default Player frame on Anniversary no longer shows when you are in combat. This restores it: a red glow pulses around your portrait while you are in combat.|r"] },
    }
end

end)(...);

(function(...)
-- Blizzard (2.5.5): nameplate code calls GetSpecializationRole, which this client
-- rejects ("API unsupported") — the error aborts CompactUnitFrame_UpdateAll on
-- every nameplate spawn. Shim the global with a nil-returning Lua function so
-- IsPlayerEffectivelyTank cleanly answers "not a tank".
-- Taint: the shim's return value feeds display-only branches (health border
-- tint); no protected call consumes it. Installed only while the real API
-- throws, so a future Blizzard fix wins automatically.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixnameplaterole", {
    name        = "Nameplate Role Fix",
    group       = "Bugfixes",
    description = "Stops the Lua error that fires every time a nameplate appears (Blizzard's nameplate code calls a specialization API this client does not support).",
    defaults = { enabled = true },
})

local installed = false

local function installFix()
    if installed then return end
    local orig = _G.GetSpecializationRole
    if type(orig) ~= "function" then return end   -- Era: global absent, error path can't occur
    if pcall(orig, 1) then return end             -- API works — nothing to fix
    installed = true
    _G.GetSpecializationRole = function(...)
        if not mod._enabled then return orig(...) end
        return nil   -- no specializations on this client: never a spec role
    end
end

function mod:OnEnable()
    installFix()
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Nameplate Role Fix"] },
        { type = "desc", text = L["Blizzard's own nameplate code asks for your specialization role - an API the Anniversary client rejects. The resulting Lua error fires on every nameplate spawn and aborts part of the nameplate setup. This fix answers the question safely with 'no role'."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            installed and L["|cff66ff66applied|r"] or L["not needed on this client"]) },
    }
end

end)(...);

(function(...)
-- Container: must come LAST so every Fix* sub-module is registered before the factory scans ns.moduleOrder.
local _, ns = ...

ns:MakeGroupContainer({
    key   = "bugfixes",
    name  = "Bug Fixes",
    group = "Bugfixes",
})

end)(...);
