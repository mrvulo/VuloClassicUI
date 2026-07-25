-- One-key fishing: one key casts, reels and lures via secure override bindings.
local _, ns = ...

local mod = ns:RegisterModule("vulfishing", {
    name        = "Fishing",
    group       = "QoL",
    description = "One-key fishing: one key casts, reels and applies a lure, and auto-loots your catch.",
    defaults = {
        enabled      = true,
        key          = "",
        lure         = true,
        autoLoot     = true,
        softInteract = true,
        equipPole    = false,
        quietErrors  = true,
        soundBoost   = false,
        soundBG      = false,
        soundLevel   = 100,
        extra        = {},
    },
})

local pairs, ipairs, wipe = pairs, ipairs, wipe

local L = ns.L

local FISHING_POLES = {
    [6256] = true, [6365] = true, [6366] = true, [6367] = true, [12225] = true,
    [19022] = true, [19970] = true, [25978] = true,
}
local FISHING_SPELLS = {
    [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true,
}
-- Ordered best to worst by fishing bonus.
local LURES = { 6533, 6532, 7307, 6811, 6530, 6529 }
local LURE_ENCHANTS = { [263] = true, [264] = true, [265] = true, [266] = true, [3868] = true, [4225] = true }
local FISHING_NAME = PROFESSIONS_FISHING or (GetSpellInfo and GetSpellInfo(7620)) or "Fishing"

local FISH_CVARS = { SoftTargetInteract = "3", SoftTargetInteractRange = "15", SoftTargetInteractRangeIsHard = "0" }
local SOUND_DIM = { Sound_MusicVolume = "0", Sound_AmbienceVolume = "0" }

local owner = CreateFrame("Frame", "VulFishOwner", UIParent)
local macroBtn = CreateFrame("Button", "VulFishMacroButton", UIParent, "SecureActionButtonTemplate")
macroBtn:SetAttribute("type", "macro")
macroBtn:RegisterForClicks("AnyUp", "AnyDown")

local midFishing = false

local function isFishingSpell(spellID)
    if FISHING_SPELLS[spellID] then return true end
    local n = spellID and GetSpellInfo(spellID)
    return n ~= nil and n == FISHING_NAME
end

local function poleEquipped()
    local id = GetInventoryItemID("player", 16)
    return id ~= nil and FISHING_POLES[id] == true
end

local function poleInBags()
    for bag = 0, 4 do
        local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local id = GetContainerItemID and GetContainerItemID(bag, slot)
            if id and FISHING_POLES[id] then
                local name = GetItemInfo(id)
                if name then return name end
            end
        end
    end
end

local function hasLure()
    local has, _, _, enchID = GetWeaponEnchantInfo()
    if not has then return false end
    if enchID == nil then return true end   -- enchant id unreadable on some clients: assume it is a lure
    return LURE_ENCHANTS[enchID] == true
end

local function bestOwnedLure()
    for _, id in ipairs(LURES) do
        if (GetItemCount and GetItemCount(id) or 0) > 0 then
            local name = GetItemInfo(id)
            if name then return name end
        end
    end
end

local cvarCache, cvarsActive = {}, false

-- Soft-target CVars are protected in combat (SetCVar throws ADDON_ACTION_BLOCKED),
-- so apply/restore is deferred to PLAYER_REGEN_ENABLED; wantCVars is the target state.
local cvarDefer = CreateFrame("Frame")
cvarDefer:Hide()
local wantCVars = false

local function applyCVar(k, v)
    local cur = GetCVar(k)
    if cur == nil then return end   -- CVar absent on this client version; never SetCVar an unknown name
    if cvarCache[k] == nil then cvarCache[k] = cur end
    SetCVar(k, v)
end
local function doSetFishCVars()
    if cvarsActive then return end
    cvarsActive = true
    wipe(cvarCache)
    if mod.db.softInteract then for k, v in pairs(FISH_CVARS) do applyCVar(k, v) end end
    if mod.db.autoLoot then applyCVar("autoLootDefault", "1") end
    if mod.db.soundBoost then
        local lvl = math.max(0, math.min(100, mod.db.soundLevel or 100)) / 100
        applyCVar("Sound_MasterVolume", tostring(lvl))
        applyCVar("Sound_SFXVolume", tostring(lvl))
        for k, v in pairs(SOUND_DIM) do applyCVar(k, v) end
    end
    if mod.db.soundBG then applyCVar("Sound_EnableSoundWhenGameIsInBG", "1") end
end
local function doRestoreFishCVars()
    if not cvarsActive then return end
    cvarsActive = false
    for k, v in pairs(cvarCache) do if v ~= nil then SetCVar(k, v) end end
    wipe(cvarCache)
end
cvarDefer:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if wantCVars then doSetFishCVars() else doRestoreFishCVars() end
end)
local function setFishCVars()
    wantCVars = true
    if InCombatLockdown() then cvarDefer:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    doSetFishCVars()
end
local function restoreFishCVars()
    wantCVars = false
    if InCombatLockdown() then cvarDefer:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    doRestoreFishCVars()
end

local NUM_EXTRA = 3
local resolved = {}

local function playerHasBuff(name)
    if not name then return false end
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then return false end
        if n == name then return true end
    end
    return false
end

local function resolveExtra(str)
    if not str or str == "" then return nil end
    str = strtrim(str)
    if str == "" then return nil end
    if str:sub(1, 1) == "/" then
        local r = { kind = "macro", body = str, hasCond = str:find("%[") ~= nil }
        local sp = str:match("/cast%s+([^\n;]+)") or str:match("/use%s+([^\n;]+)")
        if sp then sp = strtrim((sp:gsub("%[.-%]", ""))); if sp == "" then sp = nil end end
        r.spell = sp
        return r
    end
    local itemID = tonumber(str)
    if not itemID and GetItemInfoInstant then itemID = select(1, GetItemInfoInstant(str)) end
    if not itemID then return nil end
    local name = GetItemInfo(itemID) or str
    local spell = GetItemSpell and select(1, GetItemSpell(itemID)) or nil
    return { kind = "item", itemID = itemID, name = name, spell = spell }
end

local function rebuildExtra()
    for i = 1, NUM_EXTRA do
        resolved[i] = resolveExtra(mod.db and mod.db.extra and mod.db.extra[i])
    end
end
mod._rebuildExtra = rebuildExtra

local function macroCondReady(body)
    for cond in body:gmatch("(%[.-%])") do
        if SecureCmdOptionParse(cond) ~= nil then return true end
    end
    return false
end
local function spellReady(name)
    if not name or not GetSpellCooldown then return true end
    local start, dur = GetSpellCooldown(name)
    if start and dur and dur > 1.5 and (start + dur - GetTime()) > 0 then return false end
    if playerHasBuff(name) then return false end
    return true
end
local function extraReady(r)
    if not r then return false end
    if r.kind == "item" then
        if not r.itemID or (GetItemCount(r.itemID) or 0) <= 0 then return false end
        if not IsUsableItem(r.itemID) then return false end
        local start, dur = GetItemCooldown(r.itemID)
        if start and dur and dur > 0 and (start + dur - GetTime()) > 0 then return false end
        if r.spell and playerHasBuff(r.spell) then return false end
        return true
    else
        if not r.hasCond and not r.spell then return false end
        if r.hasCond and not macroCondReady(r.body) then return false end
        if r.spell and not spellReady(r.spell) then return false end
        return true
    end
end
local function bindExtra(k, r)
    if r.kind == "item" then
        macroBtn:SetAttribute("macrotext", "/use " .. (r.name or ("item:" .. r.itemID)))
    else
        macroBtn:SetAttribute("macrotext", r.body)
    end
    SetOverrideBindingClick(owner, true, k, "VulFishMacroButton")
end

local function chosenKey()
    return (mod.db.key ~= "" and mod.db.key) or nil
end

-- Override bindings cannot be changed in combat, hence the lockdown bail-out.
local function actionHandler()
    if InCombatLockdown() then return end
    local k = chosenKey()
    if not k then ClearOverrideBindings(owner); return end
    if IsKeyDown and IsKeyDown(k) then return end   -- rebinding a held key breaks the press; API may be absent
    ClearOverrideBindings(owner)
    if UnitIsDeadOrGhost("player") then return end

    if midFishing then
        if mod.db.softInteract then
            SetOverrideBinding(owner, true, k, "INTERACTMOUSEOVER")
        else
            SetOverrideBindingSpell(owner, true, k, FISHING_NAME)
        end
        return
    end

    if mod.db.equipPole and not poleEquipped() then
        local pole = poleInBags()
        if pole then
            macroBtn:SetAttribute("macrotext", "/equip " .. pole)
            SetOverrideBindingClick(owner, true, k, "VulFishMacroButton")
            return
        end
    end

    if mod.db.lure and not hasLure() then
        local lure = bestOwnedLure()
        if lure then
            macroBtn:SetAttribute("macrotext", "/use " .. lure .. "\n/use 16")
            SetOverrideBindingClick(owner, true, k, "VulFishMacroButton")
            return
        end
    end

    for i = 1, NUM_EXTRA do
        local r = resolved[i]
        if r and extraReady(r) then bindExtra(k, r); return end
    end

    SetOverrideBindingSpell(owner, true, k, FISHING_NAME)
end
mod._apply = actionHandler

local accum = 0
owner:SetScript("OnUpdate", function(_, elapsed)
    if not mod._enabled or not mod.db then return end
    accum = accum + elapsed
    if accum < 0.3 then return end
    accum = 0
    if chosenKey() then actionHandler() end
end)

-- INTERACTMOUSEOVER spams UI_ERROR_MESSAGE while the bobber is not the soft target.
local errQuiet = false
local function setQuiet(on)
    if not UIErrorsFrame then return end
    on = (on and mod.db.quietErrors ~= false) or false
    if on == errQuiet then return end
    errQuiet = on
    if on then UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
    else UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE") end
end

local function onChannelStart(_, unit, _, spellID)
    if unit ~= "player" or not isFishingSpell(spellID) then return end
    midFishing = true
    setQuiet(true)
    setFishCVars()
    actionHandler()
end
local function onChannelStop(_, unit, _, spellID)
    if unit ~= "player" or not isFishingSpell(spellID) then return end
    midFishing = false
    setQuiet(false)
    restoreFishCVars()
    actionHandler()
end
local function onFailed(_, unit, _, spellID)
    if unit ~= "player" or not isFishingSpell(spellID) then return end
    midFishing = false
    setQuiet(false)
    restoreFishCVars()
    actionHandler()
end
local function onRegenEnabled() actionHandler() end
local function onInvChanged() if not midFishing then actionHandler() end end

local capture
local function refreshKey(k)
    capture:Hide()
    if k then
        mod.db.key = k
        ns:Print(L["Fishing key set to: %s"]:format(k))
        actionHandler()
    end
end
local function startCapture()
    if InCombatLockdown() then ns:Print(L["Can't change the fishing key in combat."]); return end
    if not capture then
        capture = CreateFrame("Frame", "VulFishCapture", UIParent)
        capture:SetAllPoints(UIParent)
        capture:SetFrameStrata("FULLSCREEN_DIALOG")
        capture:EnableKeyboard(true); capture:EnableMouse(true); capture:EnableMouseWheel(true)
        local bg = capture:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
        local fs = capture:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        fs:SetPoint("CENTER"); fs:SetText(L["Press the key for fishing  (ESC to cancel)"])
        local SKIP = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, UNKNOWN = 1 }
        capture:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then refreshKey(nil); return end
            if SKIP[key] then return end
            local pre = ""
            if IsControlKeyDown() then pre = pre .. "CTRL-" end
            if IsAltKeyDown() then pre = pre .. "ALT-" end
            if IsShiftKeyDown() then pre = pre .. "SHIFT-" end
            refreshKey(pre .. key)
        end)
        local MB = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
        capture:SetScript("OnMouseDown", function(_, btn) if MB[btn] then refreshKey(MB[btn]) end end)
        capture:SetScript("OnMouseWheel", function(_, d) refreshKey(d > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
    end
    capture:Show()
    capture:SetPropagateKeyboardInput(false)
end

function mod:OnEnable()
    ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", onChannelStart)
    ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", onChannelStop)
    ns:RegisterEvent("UNIT_SPELLCAST_FAILED", onFailed)
    ns:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET", onFailed)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", onRegenEnabled)
    ns:RegisterEvent("UNIT_INVENTORY_CHANGED", onInvChanged)
    ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", onInvChanged)
    rebuildExtra()
    actionHandler()
end

function mod:OnDisable()
    ns:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START", onChannelStart)
    ns:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", onChannelStop)
    ns:UnregisterEvent("UNIT_SPELLCAST_FAILED", onFailed)
    ns:UnregisterEvent("UNIT_SPELLCAST_FAILED_QUIET", onFailed)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED", onRegenEnabled)
    ns:UnregisterEvent("UNIT_INVENTORY_CHANGED", onInvChanged)
    ns:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED", onInvChanged)
    setQuiet(false)
    restoreFishCVars()
    if not InCombatLockdown() then ClearOverrideBindings(owner) end
end

function mod:GetOptions()
    local keyLabel = (mod.db.key ~= "") and L["Fishing key: %s  —  click to change"]:format(mod.db.key) or L["Set fishing key"]
    local opts = {
        { type = "desc", text = L["|cffaaaaaaOne key does it all: cast, reel in, and apply a lure — then auto-loots. Set a key below, face some water, and press it.|r"] },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = keyLabel, width = 260, onClick = startCapture },
            { type = "button", label = L["Clear key"], width = 120,
              onClick = function() mod.db.key = ""; ns:Print(L["Fishing key cleared."]); actionHandler() end },
        } },
        { type = "toggle", label = L["One-key reel (soft-target interact)"], tooltip = L["While the bobber is out, the same key interacts with it to reel in. Needs soft-target interaction, which is enabled only while fishing and restored afterwards."],
          get = function() return mod.db.softInteract end,
          set = function(_, v) mod.db.softInteract = v; actionHandler() end },
        { type = "toggle", label = L["Auto-apply a lure when the pole has none"],
          get = function() return mod.db.lure end,
          set = function(_, v) mod.db.lure = v; actionHandler() end },
        { type = "toggle", label = L["Auto-loot while fishing"],
          get = function() return mod.db.autoLoot end,
          set = function(_, v) mod.db.autoLoot = v end },
        { type = "toggle", label = L["Auto-equip a fishing pole if none is worn"],
          get = function() return mod.db.equipPole end,
          set = function(_, v) mod.db.equipPole = v; actionHandler() end },
        { type = "toggle", label = L["Hide the reel error spam while fishing"],
          get = function() return mod.db.quietErrors ~= false end,
          set = function(_, v) mod.db.quietErrors = v; if not v then setQuiet(false) end end },
        { type = "toggle", label = L["Boost fishing sound (hear the bite clearly)"], tooltip = L["While the bobber is out, maxes effect + master volume and dims music/ambience so the splash is easy to hear. Restored when you reel in."],
          get = function() return mod.db.soundBoost end,
          set = function(_, v) mod.db.soundBoost = v end },
        { type = "toggle", label = L["Keep sound audible when the game is in the background"],
          get = function() return mod.db.soundBG end,
          set = function(_, v) mod.db.soundBG = v end },
        { type = "slider", label = L["Fishing sound volume"], min = 0, max = 100, step = 5,
          get = function() return mod.db.soundLevel or 100 end,
          set = function(_, v) mod.db.soundLevel = v end },
        { type = "header", text = L["Extra items & macros"] },
        { type = "desc", text = L["|cffaaaaaaItems or macros also used by the key while fishing — only when ready (off cooldown, buff missing, conditions met), then it goes back to casting. Type an item name or ID, shift-click an item into the box, or paste a /macro.|r"] },
    }
    mod.db.extra = mod.db.extra or {}
    for i = 1, NUM_EXTRA do
        opts[#opts + 1] = {
            type = "editbox", label = L["Slot %d"]:format(i), width = 300, editWidth = 200,
            get = function() return mod.db.extra[i] or "" end,
            set = function(_, v)
                mod.db.extra[i] = strtrim(v or "")
                rebuildExtra()
                actionHandler()
            end,
        }
    end
    return opts
end
