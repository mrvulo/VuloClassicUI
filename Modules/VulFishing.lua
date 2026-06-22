-- =========================================================
-- VuloClassicUI / Modules / VulFishing
-- One-key fishing. A single chosen key dynamically casts Fishing, reels in the
-- bobber (soft-target interact), and applies a lure when one is missing — all
-- via override bindings on a secure button, so it stays taint-safe. While the
-- bobber is out it temporarily enables soft-target interaction + auto-loot.
-- Registered as a QoL sub-module.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("vulfishing", {
    name        = "Fishing",
    group       = "QoL",
    description = "One-key fishing: one key casts, reels and applies a lure, and auto-loots your catch.",
    defaults = {
        enabled      = true,
        key          = "",     -- chosen key token, e.g. "BUTTON4" or "SHIFT-F"
        lure         = true,   -- auto-apply a lure when missing
        autoLoot     = true,   -- temp auto-loot while the bobber is out
        softInteract = true,   -- one-key reel via soft-target interact
        equipPole    = false,  -- auto-equip a fishing pole from bags
        quietErrors  = true,   -- hide the reel's "unknown unit / out of range" spam
        soundBoost   = false,  -- boost effect/master volume while fishing so the bite is clear
        soundBG      = false,  -- also keep sound playing while the game is in the background
        soundLevel   = 100,    -- 0-100 % volume to boost to while fishing
        extra        = {},     -- up to 3 extra item/macro strings used mid-cycle
    },
})

local pairs, ipairs, wipe = pairs, ipairs, wipe

-- ---------------------------------------------------------
-- Localization
-- ---------------------------------------------------------
local L = {
    DESC        = "|cffaaaaaaOne key does it all: cast, reel in, and apply a lure — then auto-loots. Set a key below, face some water, and press it.|r",
    SET_KEY     = "Set fishing key",
    KEY_IS      = "Fishing key: %s  —  click to change",
    CLEAR_KEY   = "Clear key",
    LURE        = "Auto-apply a lure when the pole has none",
    AUTOLOOT    = "Auto-loot while fishing",
    SOFT        = "One-key reel (soft-target interact)",
    SOFT_TT     = "While the bobber is out, the same key interacts with it to reel in. Needs soft-target interaction, which is enabled only while fishing and restored afterwards.",
    EQUIP       = "Auto-equip a fishing pole if none is worn",
    QUIET       = "Hide the reel error spam while fishing",
    SOUND       = "Boost fishing sound (hear the bite clearly)",
    SOUND_TT    = "While the bobber is out, maxes effect + master volume and dims music/ambience so the splash is easy to hear. Restored when you reel in.",
    SOUND_BG    = "Keep sound audible when the game is in the background",
    SOUND_LEVEL = "Fishing sound volume",
    EXTRA_HEADER = "Extra items & macros",
    EXTRA_TT    = "|cffaaaaaaItems or macros also used by the key while fishing — only when ready (off cooldown, buff missing, conditions met), then it goes back to casting. Type an item name or ID, shift-click an item into the box, or paste a /macro.|r",
    EXTRA_SLOT  = "Slot %d",
    PRESS       = "Press the key for fishing  (ESC to cancel)",
    KEY_SET     = "Fishing key set to: %s",
    KEY_CLEARED = "Fishing key cleared.",
    IN_COMBAT   = "Can't change the fishing key in combat.",
}
if GetLocale() == "deDE" then
    L.DESC      = "|cffaaaaaaEine Taste macht alles: auswerfen, einholen und Köder anlegen — danach Auto-Plündern. Unten eine Taste festlegen, aufs Wasser schauen, drücken.|r"
    L.SET_KEY   = "Angel-Taste festlegen"
    L.KEY_IS    = "Angel-Taste: %s  —  zum Ändern klicken"
    L.CLEAR_KEY = "Taste löschen"
    L.LURE      = "Köder automatisch anlegen, wenn die Angel keinen hat"
    L.AUTOLOOT  = "Auto-Plündern während des Angelns"
    L.SOFT      = "Ein-Tasten-Einholen (Soft-Target)"
    L.SOFT_TT   = "Während der Bobber draußen ist, holt dieselbe Taste ihn ein. Braucht Soft-Target-Interaktion — wird nur beim Angeln aktiviert und danach wiederhergestellt."
    L.EQUIP     = "Angel automatisch anlegen, wenn keine ausgerüstet ist"
    L.QUIET     = "Reel-Fehlermeldungen beim Angeln ausblenden"
    L.SOUND     = "Angel-Sound verstärken (Biss klar hören)"
    L.SOUND_TT  = "Während der Bobber draußen ist, werden Effekt- + Master-Lautstärke maximiert und Musik/Ambiente abgesenkt, damit das Platschen gut hörbar ist. Wird beim Einholen wiederhergestellt."
    L.SOUND_BG  = "Sound auch hörbar, wenn das Spiel im Hintergrund läuft"
    L.SOUND_LEVEL = "Angel-Sound-Lautstärke"
    L.EXTRA_HEADER = "Extra-Items & Makros"
    L.EXTRA_TT  = "|cffaaaaaaItems oder Makros, die die Taste beim Angeln mitbenutzt — nur wenn bereit (kein Cooldown, Buff fehlt, Bedingungen erfüllt), danach wird wieder ausgeworfen. Item-Name oder -ID eintippen, ein Item per Shift-Klick einfügen, oder ein /Makro einfügen.|r"
    L.EXTRA_SLOT = "Slot %d"
    L.PRESS     = "Drücke die Taste fürs Angeln  (ESC = abbrechen)"
    L.KEY_SET   = "Angel-Taste gesetzt auf: %s"
    L.KEY_CLEARED = "Angel-Taste gelöscht."
    L.IN_COMBAT = "Angel-Taste kann im Kampf nicht geändert werden."
end

-- ---------------------------------------------------------
-- Data
-- ---------------------------------------------------------
local FISHING_POLES = {
    [6256] = true, [6365] = true, [6366] = true, [6367] = true, [12225] = true,
    [19022] = true, [19970] = true, [25978] = true,
}
local FISHING_SPELLS = {
    [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true,
}
-- best -> worst, by fishing bonus
local LURES = { 6533, 6532, 7307, 6811, 6530, 6529 }
local LURE_ENCHANTS = { [263] = true, [264] = true, [265] = true, [266] = true, [3868] = true, [4225] = true }
local FISHING_NAME = PROFESSIONS_FISHING or (GetSpellInfo and GetSpellInfo(7620)) or "Fishing"

local FISH_CVARS = { SoftTargetInteract = "3", SoftTargetInteractRange = "15", SoftTargetInteractRangeIsHard = "0" }
-- while fishing: raise effect + master volume (to soundLevel%) and dim music/ambience so the bite stands out
local SOUND_DIM = { Sound_MusicVolume = "0", Sound_AmbienceVolume = "0" }

-- ---------------------------------------------------------
-- Secure binding owner + macro button
-- ---------------------------------------------------------
local owner = CreateFrame("Frame", "VulFishOwner", UIParent)
local macroBtn = CreateFrame("Button", "VulFishMacroButton", UIParent, "SecureActionButtonTemplate")
macroBtn:SetAttribute("type", "macro")
macroBtn:RegisterForClicks("AnyUp", "AnyDown")

local midFishing = false

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------
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
    if enchID == nil then return true end         -- can't read id: assume the pole enchant is a lure
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

-- ---------------------------------------------------------
-- Temp CVars (soft-target interact + auto-loot while fishing)
-- ---------------------------------------------------------
local cvarCache, cvarsActive = {}, false
local function applyCVar(k, v)
    if cvarCache[k] == nil then cvarCache[k] = GetCVar(k) end
    SetCVar(k, v)
end
local function setFishCVars()
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
local function restoreFishCVars()
    if not cvarsActive then return end
    cvarsActive = false
    for k, v in pairs(cvarCache) do if v ~= nil then SetCVar(k, v) end end
    wipe(cvarCache)
end

-- ---------------------------------------------------------
-- Extra items / macros: used mid-cycle only when "ready", so they never
-- permanently block casting. Items gate on cooldown + their granted buff;
-- macros gate on their [conditions] and/or the spell they cast.
-- ---------------------------------------------------------
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

-- ---------------------------------------------------------
-- Action handler: pick what the key does right now
-- ---------------------------------------------------------
local function chosenKey()
    return (mod.db.key ~= "" and mod.db.key) or nil
end

local function actionHandler()
    if InCombatLockdown() then return end
    local k = chosenKey()
    if not k then ClearOverrideBindings(owner); return end
    if IsKeyDown and IsKeyDown(k) then return end  -- never rebind while held (guarded: API may be absent)
    ClearOverrideBindings(owner)
    if UnitIsDeadOrGhost("player") then return end

    -- reel in while a bobber is out
    if midFishing then
        if mod.db.softInteract then
            SetOverrideBinding(owner, true, k, "INTERACTMOUSEOVER")
        else
            SetOverrideBindingSpell(owner, true, k, FISHING_NAME)
        end
        return
    end

    -- equip a pole if asked and none is worn
    if mod.db.equipPole and not poleEquipped() then
        local pole = poleInBags()
        if pole then
            macroBtn:SetAttribute("macrotext", "/equip " .. pole)
            SetOverrideBindingClick(owner, true, k, "VulFishMacroButton")
            return
        end
    end

    -- apply a lure if missing
    if mod.db.lure and not hasLure() then
        local lure = bestOwnedLure()
        if lure then
            macroBtn:SetAttribute("macrotext", "/use " .. lure .. "\n/use 16")
            SetOverrideBindingClick(owner, true, k, "VulFishMacroButton")
            return
        end
    end

    -- extra items / macros, only while they are ready (never blocks casting)
    for i = 1, NUM_EXTRA do
        local r = resolved[i]
        if r and extraReady(r) then bindExtra(k, r); return end
    end

    -- default: cast
    SetOverrideBindingSpell(owner, true, k, FISHING_NAME)
end
mod._apply = actionHandler

-- ---------------------------------------------------------
-- Throttled re-evaluation (reacts to lure applied, pole swapped, etc.)
-- ---------------------------------------------------------
local accum = 0
owner:SetScript("OnUpdate", function(_, elapsed)
    if not mod._enabled or not mod.db then return end
    accum = accum + elapsed
    if accum < 0.3 then return end
    accum = 0
    if chosenKey() then actionHandler() end
end)

-- ---------------------------------------------------------
-- Events
-- ---------------------------------------------------------
-- Mute the cast/interact error spam ("Unknown unit" / "Out of range") that the
-- one-key reel (INTERACTMOUSEOVER) throws when the bobber isn't the soft target.
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

-- ---------------------------------------------------------
-- Key capture
-- ---------------------------------------------------------
local capture
local function refreshKey(k)
    capture:Hide()
    if k then
        mod.db.key = k
        ns:Print(L.KEY_SET:format(k))
        actionHandler()
    end
end
local function startCapture()
    if InCombatLockdown() then ns:Print(L.IN_COMBAT); return end
    if not capture then
        capture = CreateFrame("Frame", "VulFishCapture", UIParent)
        capture:SetAllPoints(UIParent)
        capture:SetFrameStrata("FULLSCREEN_DIALOG")
        capture:EnableKeyboard(true); capture:EnableMouse(true); capture:EnableMouseWheel(true)
        local bg = capture:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
        local fs = capture:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        fs:SetPoint("CENTER"); fs:SetText(L.PRESS)
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

-- ---------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------
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
    local keyLabel = (mod.db.key ~= "") and L.KEY_IS:format(mod.db.key) or L.SET_KEY
    local opts = {
        { type = "desc", text = L.DESC },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = keyLabel, width = 260, onClick = startCapture },
            { type = "button", label = L.CLEAR_KEY, width = 120,
              onClick = function() mod.db.key = ""; ns:Print(L.KEY_CLEARED); actionHandler() end },
        } },
        { type = "toggle", label = L.SOFT, tooltip = L.SOFT_TT,
          get = function() return mod.db.softInteract end,
          set = function(_, v) mod.db.softInteract = v; actionHandler() end },
        { type = "toggle", label = L.LURE,
          get = function() return mod.db.lure end,
          set = function(_, v) mod.db.lure = v; actionHandler() end },
        { type = "toggle", label = L.AUTOLOOT,
          get = function() return mod.db.autoLoot end,
          set = function(_, v) mod.db.autoLoot = v end },
        { type = "toggle", label = L.EQUIP,
          get = function() return mod.db.equipPole end,
          set = function(_, v) mod.db.equipPole = v; actionHandler() end },
        { type = "toggle", label = L.QUIET,
          get = function() return mod.db.quietErrors ~= false end,
          set = function(_, v) mod.db.quietErrors = v; if not v then setQuiet(false) end end },
        { type = "toggle", label = L.SOUND, tooltip = L.SOUND_TT,
          get = function() return mod.db.soundBoost end,
          set = function(_, v) mod.db.soundBoost = v end },
        { type = "toggle", label = L.SOUND_BG,
          get = function() return mod.db.soundBG end,
          set = function(_, v) mod.db.soundBG = v end },
        { type = "slider", label = L.SOUND_LEVEL, min = 0, max = 100, step = 5,
          get = function() return mod.db.soundLevel or 100 end,
          set = function(_, v) mod.db.soundLevel = v end },
        { type = "header", text = L.EXTRA_HEADER },
        { type = "desc", text = L.EXTRA_TT },
    }
    mod.db.extra = mod.db.extra or {}
    for i = 1, NUM_EXTRA do
        opts[#opts + 1] = {
            type = "editbox", label = L.EXTRA_SLOT:format(i), width = 300, editWidth = 200,
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
