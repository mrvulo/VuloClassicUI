-- =========================================================
-- VuloClassicUI / Modules / LazyVulo
-- Helper for the Apexis Relic memory minigame (Ogri'la dailies,
-- Blade's Edge): record the flashing color sequence with buttons or
-- hotkeys; the queue always shows what to click next.
--   - A correct crystal click refreshes the Introspection debuff on
--     you -> the first queue entry is consumed automatically.
--   - A wrong click zaps you with Reprisal self-damage -> the entry
--     is restored (it was not actually consumed).
-- Auto-opens when you start the minigame at the relic (gossip hook).
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("lazyvulo", {
    name        = "LazyVulo",
    group       = "QoL",
    description = "Apexis Relic memory minigame helper (Ogri'la dailies): record the flashing color sequence, always see what to click next.",
    defaults    = {
        enabled        = true,
        autoShow       = true,
        hotkeysEnabled = true,
        unbindInCombat = true,
        showTooltips   = true,
        scale          = 1.25,
        keys           = { "G", "Y", "B", "R" },
        point          = "CENTER",
        relPoint       = "CENTER",
        x              = 0,
        y              = 120,
    },
})

-- =========================================================
-- Game data (Apexis Relic minigame, TBC)
-- =========================================================
-- The two relic game objects; selecting their gossip option starts the game
local RELIC_OBJECTS = { [185890] = true, [185944] = true }
-- "Introspection": refreshed on every crystal click -> consume a queue entry
local INTROSPECTION = { [40055] = true, [40165] = true, [40166] = true, [40167] = true }
-- "Reprisal": self-damage on a wrong click -> restore the consumed entry
local REPRISAL_ID   = 40065
local SELF_FLAGS    = 0x511  -- mine + friendly + player-controlled + player

local RELIC_COLORS = {
    { label = "Green relic",  icon = "Interface\\Icons\\Spell_Shadow_AntiMagicShell" },
    { label = "Yellow relic", icon = "Interface\\Icons\\Spell_Holy_Retribution"     },
    { label = "Blue relic",   icon = "Interface\\Icons\\Spell_Fire_BlueFlameRing"   },
    { label = "Red relic",    icon = "Interface\\Icons\\Spell_Fire_Burnout"         },
}

local MAX_SHOWN = 12   -- queue icons drawn (overflow shows "+N")
local FRAME_W   = 184
local FRAME_H   = 138

-- =========================================================
-- State
-- =========================================================
local f                   -- main window
local queue    = {}       -- recorded color indices, [1] = next click
local consumed            -- last consumed color (restored on Reprisal)
local lastExpire = 0      -- Introspection expiration we already handled

local function playClickSound()
    local snd = SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON
    if snd and PlaySound then PlaySound(snd) end
end

-- =========================================================
-- Queue handling
-- =========================================================
local updateQueue  -- forward (defined after the frame builder)

local function shiftQueue()
    consumed = queue[1]
    table.remove(queue, 1)
    updateQueue()
end

local function unshiftQueue()
    if not consumed then return end
    table.insert(queue, 1, consumed)
    consumed = nil
    updateQueue()
end

local function recordColor(colorIndex)
    queue[#queue + 1] = colorIndex
    playClickSound()
    updateQueue()
end

-- Current Introspection expiration time on the player (nil if absent)
local function introspectionExpire()
    for i = 1, 40 do
        local name, _, _, _, _, exp, _, _, _, sid = UnitDebuff("player", i)
        if not name then return nil end
        if sid and INTROSPECTION[sid] then return exp end
    end
    return nil
end

-- =========================================================
-- Hotkeys (override bindings while the window is shown)
-- =========================================================
local function unbindKeys()
    if not f then return end
    ClearOverrideBindings(f)
    f._bound = false
end

local function bindKeys()
    if not f then return end
    if InCombatLockdown() then
        f._pendingBind = true
        return
    end
    ClearOverrideBindings(f)
    f._bound = false
    if not f:IsVisible() or not mod.db.hotkeysEnabled then return end
    for i = 1, 4 do
        local key = mod.db.keys[i]
        if key and key ~= "" then
            SetOverrideBindingClick(f, true, key, "VCUI_LazyVuloRecord" .. i)
        end
    end
    f._bound = true
end

local function onRegenDisabled()
    if not f or not f._bound then return end
    if mod.db.unbindInCombat then
        -- PLAYER_REGEN_DISABLED fires just before lockdown engages
        unbindKeys()
        f._pendingBind = true
    end
end

local function onRegenEnabled()
    if not f then return end
    if f._pendingUnbind then
        f._pendingUnbind = nil
        unbindKeys()
    elseif f._pendingBind then
        f._pendingBind = nil
        if f:IsVisible() then bindKeys() end
    end
end

-- =========================================================
-- Window
-- =========================================================
local function attachHelpTooltip(btn)
    btn:SetScript("OnEnter", function(self)
        if not mod.db.showTooltips then return end
        if not self.toolHeader then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.toolHeader, 1, 1, 1)
        if self.toolText then
            GameTooltip:AddLine(self.toolText, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function makeIconButton(parent, name, size)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(size, size)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(b)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    attachHelpTooltip(b)
    return b
end

local function onQueueClick(self, button)
    local idx = self:GetID()
    if not queue[idx] then return end
    playClickSound()
    if button == "LeftButton" then
        table.remove(queue, idx)
    else -- remove this entry and everything after it
        for i = #queue, idx, -1 do
            queue[i] = nil
        end
    end
    updateQueue()
end

local function buildFrame()
    if f then return f end

    f = CreateFrame("Frame", "VCUI_LazyVulo", UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint(mod.db.point or "CENTER", UIParent, mod.db.relPoint or "CENTER",
        mod.db.x or 0, mod.db.y or 0)
    f:SetScale(mod.db.scale or 1)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()

    if ns.UI and ns.UI.StyleBackdrop then
        ns.UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.borderDark or ns.COLORS.border })
        if ns.UI.CreateShadow then ns.UI:CreateShadow(f) end
    end

    -- Drag anywhere on the panel body
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        mod.db.point, mod.db.relPoint, mod.db.x, mod.db.y = p, rp, x, y
    end)

    -- Title + close
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if ns.UI and ns.UI.Font then ns.UI.Font(title, 13) end
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    title:SetText("|cff9b6cffLazyVulo|r")

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeText:SetPoint("CENTER", close, "CENTER", 0, 0)
    closeText:SetText("×")
    closeText:SetTextColor(0.7, 0.7, 0.7)
    close:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function() closeText:SetTextColor(0.7, 0.7, 0.7) end)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Queue slots: big "next" icon, then two rows of small ones
    f.slots = {}
    for i = 1, MAX_SHOWN do
        local size = (i == 1) and 34 or 22
        local b = makeIconButton(f, nil, size)
        b:SetID(i)
        b:SetScript("OnClick", onQueueClick)
        b.toolText = L["Left click: remove this entry.\nRight click: remove this and all later entries."]
        if i == 1 then
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -26)
        elseif i <= 6 then
            b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 46 + (i - 2) * 26, -60)
        else
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + (i - 7) * 26, -64)
        end
        b:Hide()
        f.slots[i] = b
    end

    -- Overflow counter ("+N" when the sequence is longer than the slots)
    f.overflow = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    if ns.UI and ns.UI.Font then ns.UI.Font(f.overflow, 11) end
    f.overflow:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + 6 * 26, -68)
    f.overflow:SetText("")

    -- Record buttons (the four relic colors)
    for i, c in ipairs(RELIC_COLORS) do
        local b = makeIconButton(f, "VCUI_LazyVuloRecord" .. i, 30)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 23 + (i - 1) * 36, 8)
        b.tex:SetTexture(c.icon)
        b.toolHeader = L[c.label]
        b:SetScript("OnClick", function() recordColor(i) end)
        f["record" .. i] = b
    end

    -- Separator above the record row
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 0.6)
    sep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 44)
    sep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 44)
    sep:SetHeight(1)

    -- Watch Introspection refreshes while shown (0.1s poll, like a HOT tick)
    local throttle = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        throttle = throttle + elapsed
        if throttle < 0.1 then return end
        throttle = 0
        local exp = introspectionExpire()
        if exp and exp ~= lastExpire then
            lastExpire = exp
            shiftQueue()
        end
    end)

    -- Reprisal self-damage (wrong click) -> restore the consumed entry
    f:SetScript("OnEvent", function()
        local _, sub, _, _, _, _, _, _, _, destFlags, _, sid = CombatLogGetCurrentEventInfo()
        if sub == "SPELL_DAMAGE" and sid == REPRISAL_ID
           and destFlags == SELF_FLAGS and consumed then
            unshiftQueue()
        end
    end)

    f:SetScript("OnShow", function(self)
        -- Sync to a possibly running Introspection so reopening the window
        -- mid-game doesn't immediately eat a queue entry.
        lastExpire = introspectionExpire() or 0
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        bindKeys()
    end)
    f:SetScript("OnHide", function(self)
        self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        if InCombatLockdown() and self._bound then
            self._pendingUnbind = true  -- cleared on PLAYER_REGEN_ENABLED
        else
            unbindKeys()
        end
    end)

    return f
end

-- Hotkey hints on the record buttons
local function updateKeyHints()
    if not f then return end
    for i = 1, 4 do
        local b = f["record" .. i]
        local key = mod.db.hotkeysEnabled and mod.db.keys[i]
        if key and key ~= "" then
            b.toolText = string.format(L["Hotkey: %s"], "|cffffffff" .. key .. "|r")
        else
            b.toolText = L["Click to record this color."]
        end
    end
end

updateQueue = function()
    if not f then return end
    for i = 1, MAX_SHOWN do
        local b, color = f.slots[i], queue[i]
        if color then
            b.tex:SetTexture(RELIC_COLORS[color].icon)
            b.toolHeader = L[RELIC_COLORS[color].label]
            b:Show()
        else
            b:Hide()
        end
    end
    if #queue > MAX_SHOWN then
        f.overflow:SetText(string.format("+%d", #queue - MAX_SHOWN))
    else
        f.overflow:SetText("")
    end
end

local function showWindow()
    buildFrame()
    updateKeyHints()
    f:Show()
    updateQueue()
end

local function toggleWindow()
    buildFrame()
    if f:IsShown() then f:Hide() else showWindow() end
end

-- =========================================================
-- Auto-show: selecting the relic's gossip option starts the game
-- =========================================================
local gossipHooked = false

local function onGossipSelect()
    if not mod._enabled or not mod.db.autoShow then return end
    local guid = UnitGUID and UnitGUID("npc")
    local objId = guid and tonumber(guid:match("^GameObject%-.-%-(%d+)%-%x+$"))
    if objId and RELIC_OBJECTS[objId] then
        showWindow()
    end
end

local function installGossipHook()
    if gossipHooked or not C_GossipInfo then return end
    gossipHooked = true
    if C_GossipInfo.SelectOption then
        hooksecurefunc(C_GossipInfo, "SelectOption", onGossipSelect)
    end
    if C_GossipInfo.SelectOptionByIndex then
        hooksecurefunc(C_GossipInfo, "SelectOptionByIndex", onGossipSelect)
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    installGossipHook()
    ns:RegisterEvent("PLAYER_REGEN_DISABLED", onRegenDisabled)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",  onRegenEnabled)
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED", onRegenDisabled)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",  onRegenEnabled)
    if f then
        if not InCombatLockdown() then unbindKeys() end
        f:Hide()
    end
end

-- Slash command: toggle the window
SLASH_VCUILAZYVULO1 = "/lazyvulo"
SLASH_VCUILAZYVULO2 = "/lv"
SlashCmdList.VCUILAZYVULO = function()
    if not mod._enabled then
        ns:Print(L["LazyVulo is disabled."])
        return
    end
    toggleWindow()
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local items = {
        { type = "header", text = L["LazyVulo"] },
        { type = "desc",
          text = L["|cffaaaaaaHelper for the Apexis Relic memory minigame (Ogri'la dailies). Record the flashing sequence with the buttons or hotkeys; the first icon is always your next click. Correct clicks are consumed automatically, wrong clicks are restored.|r"] },
        { type = "desc",
          text = L["|cffaaaaaaOpen manually with /lazyvulo or /lv.|r"] },
        { type = "spacer", height = 4 },

        { type = "toggle", label = L["Auto-show at the Apexis Relic"],
          tooltip = L["Opens the window automatically when you start the relic minigame."],
          get = function() return mod.db.autoShow end,
          set = function(_, v) mod.db.autoShow = v end },

        { type = "toggle", label = L["Enable hotkeys while the window is shown"],
          get = function() return mod.db.hotkeysEnabled end,
          set = function(_, v)
              mod.db.hotkeysEnabled = v
              updateKeyHints()
              if f and f:IsShown() then bindKeys() end
          end },

        { type = "toggle", label = L["Disable hotkeys while in combat"],
          tooltip = L["Hands the keys back to your action bars while you are in combat."],
          get = function() return mod.db.unbindInCombat end,
          set = function(_, v) mod.db.unbindInCombat = v end },

        { type = "toggle", label = L["Show help tooltips"],
          get = function() return mod.db.showTooltips end,
          set = function(_, v) mod.db.showTooltips = v end },

        { type = "slider", label = L["Window scale"],
          min = 0.8, max = 2.0, step = 0.05,
          get = function() return mod.db.scale end,
          set = function(_, v)
              mod.db.scale = v
              if f then f:SetScale(v) end
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Hotkeys"] },
        { type = "desc",
          text = L["|cffaaaaaaOne key per color (e.g. G, Y, B, R or NUMPAD1). Empty = no hotkey.|r"] },
    }

    for i, c in ipairs(RELIC_COLORS) do
        table.insert(items, { type = "editbox", label = L[c.label],
            width = 260, editWidth = 110,
            get = function() return mod.db.keys[i] or "" end,
            set = function(_, v)
                v = tostring(v or ""):gsub("%s", ""):upper()
                mod.db.keys[i] = v
                updateKeyHints()
                if f and f:IsShown() then bindKeys() end
            end })
    end

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "button", label = L["Show window"], width = 160,
        onClick = function() toggleWindow() end })

    return items
end
