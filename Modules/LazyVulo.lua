-- VuloClassicUI / Modules / LazyVulo
-- A correct crystal click refreshes the Introspection debuff -> first queue entry is consumed.
-- A wrong click deals Reprisal self-damage -> the consumed entry is restored.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("lazyvulo", {
    name        = "LazyVulo",
    group       = "Extras",
    description = "Apexis Relic memory minigame helper (Ogri'la dailies): record the flashing color sequence, always see what to click next.",
    defaults    = {
        enabled        = true,
        autoShow       = true,
        hotkeysEnabled = true,
        unbindInCombat = true,
        showTooltips   = true,
        scale          = 1.25,
        keys           = { "G", "Y", "B", "R" },
        x              = 0,
        y              = 120,
    },
})

-- Relic game objects; their gossip option starts the game
local RELIC_OBJECTS = { [185890] = true, [185944] = true }
-- "Introspection" debuff ids
local INTROSPECTION = { [40055] = true, [40165] = true, [40166] = true, [40167] = true }
-- "Reprisal" self-damage spell id
local REPRISAL_ID   = 40065
local SELF_FLAGS    = 0x511  -- mine + friendly + player-controlled + player

local RELIC_COLORS = {
    { label = "Green relic",  r = 0.10, g = 0.85, b = 0.15 },
    { label = "Yellow relic", r = 1.00, g = 0.85, b = 0.10 },
    { label = "Blue relic",   r = 0.15, g = 0.45, b = 1.00 },
    { label = "Red relic",    r = 0.95, g = 0.15, b = 0.10 },
}

-- 2x2 grid mirroring the in-game crystal layout, keyed by color index (1=green 2=yellow 3=blue 4=red)
local RECORD_POS = {
    [4] = { 60, 42 },   -- red    -> top-left
    [1] = { 94, 42 },   -- green  -> top-right
    [3] = { 60,  8 },   -- blue   -> bottom-left
    [2] = { 94,  8 },   -- yellow -> bottom-right
}

local MAX_SHOWN = 12
local FRAME_W   = 184
local FRAME_H   = 166

local f
local queue    = {}
local consumed
local lastExpire = 0

local function playClickSound()
    local snd = SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON
    if snd and PlaySound then PlaySound(snd) end
end

local updateQueue  -- forward

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

local function introspectionExpire()
    for i = 1, 40 do
        local name, _, _, _, _, exp, _, _, _, sid = UnitDebuff("player", i)
        if not name then return nil end
        if sid and INTROSPECTION[sid] then return exp end
    end
    return nil
end

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
        -- fires just before lockdown engages, so unbinding is still allowed
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
    b.rim = b:CreateTexture(nil, "BACKGROUND")
    b.rim:SetAllPoints(b)
    b.rim:SetColorTexture(0.02, 0.02, 0.03, 1)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.18)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    attachHelpTooltip(b)
    return b
end

local function setButtonColor(b, colorIndex)
    local c = RELIC_COLORS[colorIndex]
    if c then b.tex:SetColorTexture(c.r, c.g, c.b, 1) end
end

local function onQueueClick(self, button)
    local idx = self:GetID()
    if not queue[idx] then return end
    playClickSound()
    if button == "LeftButton" then
        table.remove(queue, idx)
    else
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
    -- one-time migration of the legacy point/relPoint anchor save to a CENTER offset
    if mod.db.point then
        f:ClearAllPoints()
        f:SetPoint(mod.db.point, UIParent, mod.db.relPoint or "CENTER", mod.db.x or 0, mod.db.y or 0)
        local fx, fy = f:GetCenter()
        local px, py = UIParent:GetCenter()
        if fx and px then mod.db.x, mod.db.y = fx - px, fy - py end
        mod.db.point, mod.db.relPoint = nil, nil
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
    f:SetScale(mod.db.scale or 1)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:Hide()

    if ns.UI and ns.UI.StyleBackdrop then
        ns.UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.borderDark or ns.COLORS.border })
        if ns.UI.CreateShadow then ns.UI:CreateShadow(f) end
    end

    ns:CreateMover(f, { key = "lazyvulo", label = "|cffffffffLAZYVULO|r", db = mod.db, width = FRAME_W, height = FRAME_H,
        scalable = true, anchorable = true })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if ns.UI and ns.UI.Font then ns.UI.Font(title, 13) end
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    title:SetText((ns.C and ns.C.accent or "|cff9b6cff") .. "LazyVulo|r")

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

    f.overflow = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    if ns.UI and ns.UI.Font then ns.UI.Font(f.overflow, 11) end
    f.overflow:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + 6 * 26, -68)
    f.overflow:SetText("")

    for i, c in ipairs(RELIC_COLORS) do
        local b = makeIconButton(f, "VCUI_LazyVuloRecord" .. i, 30)
        local pos = RECORD_POS[i]
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", pos[1], pos[2])
        setButtonColor(b, i)
        b.toolHeader = L[c.label]
        b:SetScript("OnClick", function() recordColor(i) end)
        f["record" .. i] = b
    end

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 0.6)
    sep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 78)
    sep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 78)
    sep:SetHeight(1)

    f:SetScript("OnEvent", function(_, event, unit)
        -- Introspection refreshes announce themselves via the player's aura
        -- event; the old 0.1s poll rescanned all debuff slots while shown.
        if event == "UNIT_AURA" then
            if unit ~= "player" then return end
            local exp = introspectionExpire()
            if exp and exp ~= lastExpire then
                lastExpire = exp
                shiftQueue()
            end
            return
        end
        local _, sub, _, _, _, _, _, _, _, destFlags, _, sid = CombatLogGetCurrentEventInfo()
        if sub == "SPELL_DAMAGE" and sid == REPRISAL_ID
           and destFlags == SELF_FLAGS and consumed then
            unshiftQueue()
        end
    end)

    f:SetScript("OnShow", function(self)
        -- sync to a running Introspection so reopening mid-game doesn't eat a queue entry
        lastExpire = introspectionExpire() or 0
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        if self.RegisterUnitEvent then
            self:RegisterUnitEvent("UNIT_AURA", "player")
        else
            self:RegisterEvent("UNIT_AURA")
        end
        bindKeys()
    end)
    f:SetScript("OnHide", function(self)
        self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:UnregisterEvent("UNIT_AURA")
        if InCombatLockdown() and self._bound then
            self._pendingUnbind = true
        else
            unbindKeys()
        end
    end)

    return f
end

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
            setButtonColor(b, color)
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

function mod:OnEnable()
    installGossipHook()
    mod:RegisterEvent("PLAYER_REGEN_DISABLED", onRegenDisabled)
    mod:RegisterEvent("PLAYER_REGEN_ENABLED",  onRegenEnabled)
end

function mod:OnDisable()
    if f then
        if not InCombatLockdown() then unbindKeys() end
        f:Hide()
    end
end

ns:RegisterSlash({ key = "LAZYVULO", commands = { "/lazyvulo", "/lv" },
    desc = "Open the one-button helper.",
    module = "lazyvulo",
})
ns.Slash.LAZYVULO = function()
    if not mod._enabled then
        ns:Print(L["LazyVulo is disabled."])
        return
    end
    toggleWindow()
end

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
