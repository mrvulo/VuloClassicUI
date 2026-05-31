-- =========================================================
-- VuloClassicUI / Modules / VTManaDisplay (Class Specific)
-- Container module for class-specific tools, organized by class tabs.
-- Currently: Priest → Shadow → Vampiric Touch mana tracker
--   (tracks 5% of shadow damage per tick given back to the group as mana).
-- Built to be extended: add a class to CLASS_TABS to give it its own tab.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("vtmanadisplay", {
    name        = "Class Specific",
    group       = "QoL",
    description = "Class-specific tools, grouped by class. Currently includes the Priest Vampiric Touch mana tracker (Shadow).",
    defaults    = {
        enabled    = true,
        showFrame  = true,
        showInChat = false,
        x          = 0,
        y          = -220,
        fontSize   = 14,
        unlocked   = false,
    },
})

-- Class tabs: only classes that actually have tools get a tab.
-- Tab id is the lowercase class token; label is a raw English key (translated live).
mod.tabs = {
    { id = "priest", label = "Priest" },
}

local VT_SPELL_ID_BASE = 34914  -- Vampiric Touch base (TBC)
local SHADOW_SCHOOL    = 32

-- =========================================================
-- Runtime state
-- =========================================================
local playerGUID
local vtSpellName          -- localized name, filters all ranks
local vtTargets  = {}      -- destGUID -> true (active VTs)
local totalMana  = 0
local lastTick   = 0
local cFrame              -- display frame

-- =========================================================
-- Helpers
-- =========================================================
local function updateFrame()
    if not cFrame or not cFrame.text then return end
    cFrame.text:SetText(string.format(L["|cff9b6cffVT Mana:|r %d"], math.floor(totalMana)))
end

local function resetCombat()
    totalMana = 0
    lastTick  = 0
    updateFrame()
end

local function reportChat()
    if not mod.db.showInChat then return end
    if totalMana <= 0 then return end
    ns:Print(L["Vampiric Touch: %d mana given to the group."], math.floor(totalMana))
end

local function refreshSpell()
    vtSpellName = GetSpellInfo(VT_SPELL_ID_BASE)
end

-- =========================================================
-- Combat log handler
-- Anniversary uses the modern backend — args via CombatLogGetCurrentEventInfo().
-- Lookup table instead of multiple string compares per event (hot-path filter).
-- =========================================================
local TRACKED_EVENTS = {
    SPELL_AURA_APPLIED    = "apply",
    SPELL_AURA_REMOVED    = "remove",
    SPELL_DAMAGE          = "damage",
    SPELL_PERIODIC_DAMAGE = "damage",
}

local function onCLEU()
    if not vtSpellName then return end
    if not playerGUID then
        playerGUID = UnitGUID("player")
        if not playerGUID then return end
    end

    local _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _,
          _, spellName, _, amount, _, school = CombatLogGetCurrentEventInfo()

    if sourceGUID ~= playerGUID then return end
    local kind = TRACKED_EVENTS[subEvent]
    if not kind then return end

    if kind == "apply" then
        if spellName == vtSpellName then
            vtTargets[destGUID] = true
            lastTick = 0
        end
    elseif kind == "remove" then
        if spellName == vtSpellName then
            vtTargets[destGUID] = nil
            totalMana = totalMana + lastTick
            updateFrame()
        end
    else -- "damage"
        if vtTargets[destGUID] and amount and amount > 0 and school == SHADOW_SCHOOL then
            local mana = amount * 0.05
            totalMana = totalMana + mana
            lastTick  = mana
            updateFrame()
        end
    end
end

-- =========================================================
-- Frame + mover
-- =========================================================
local function createFrame()
    if cFrame then return cFrame end

    cFrame = CreateFrame("Frame", "VCUI_VTManaFrame", UIParent)
    cFrame:SetSize(180, 22)
    cFrame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x, mod.db.y)
    cFrame:SetFrameStrata("LOW")
    cFrame:SetMovable(true)
    cFrame:SetClampedToScreen(false)

    cFrame.text = cFrame:CreateFontString(nil, "OVERLAY")
    cFrame.text:SetFont("Fonts\\FRIZQT__.TTF", mod.db.fontSize, "OUTLINE")
    cFrame.text:SetPoint("CENTER", cFrame, "CENTER", 0, 0)
    cFrame.text:SetTextColor(1, 1, 1, 1)
    cFrame.text:SetText(L["|cff9b6cffVT Mana:|r 0"])

    cFrame.mover = ns:CreateMover(cFrame, {
        label  = L["|cffffffffVT MANA|r"],
        db     = mod.db,
        width  = 200,
        height = 40,
        onMove = function(x, y)
            ns:Print(string.format(L["VT mana frame: x=%.0f, y=%.0f"], x, y))
        end,
    })

    return cFrame
end

local function setUnlocked(state)
    mod.db.unlocked = state
    if not cFrame then createFrame() end
    if state then
        cFrame:Show()
        cFrame.mover:Show()
        ns:Print(L["VT mana mover active. |cff9b6cffDrag|r or |cff9b6cffarrow keys|r (SHIFT = 5px)."])
    else
        cFrame.mover:Hide()
        if not mod.db.showFrame then cFrame:Hide() end
        ns:Print(L["VT mana mover disabled."])
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    -- Migration: take over old settings under "vampirictouchmana"
    if ns.db and ns.db.profile and ns.db.profile.modules then
        local old = ns.db.profile.modules.vampirictouchmana
        if old then
            for k, v in pairs(old) do
                if mod.db[k] == nil or k == "x" or k == "y" then
                    mod.db[k] = v
                end
            end
            ns.db.profile.modules.vampirictouchmana = nil
        end
    end

    -- Priests only
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return end

    playerGUID  = UnitGUID("player")
    vtSpellName = GetSpellInfo(VT_SPELL_ID_BASE)

    createFrame()
    if mod.db.showFrame then cFrame:Show() else cFrame:Hide() end

    ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    ns:RegisterEvent("PLAYER_REGEN_DISABLED",       resetCombat)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",        reportChat)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD",       resetCombat)
    ns:RegisterEvent("SPELLS_CHANGED",              refreshSpell)
end

function mod:OnDisable()
    ns:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED",       resetCombat)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",        reportChat)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD",       resetCombat)
    ns:UnregisterEvent("SPELLS_CHANGED",              refreshSpell)
    if cFrame then cFrame:Hide() end
end

-- =========================================================
-- Options
-- =========================================================
-- Priest tab: Shadow → Vampiric Touch mana tracker
local function priestOptions()
    local isPriest = select(2, UnitClass("player")) == "PRIEST"
    local items = {
        { type = "header", text = L["Shadow"] },
        { type = "desc",
          text = L["|cffaaaaaaVampiric Touch mana tracker — shows live how much mana you've given to the group (5% of shadow damage per tick, per mana user).|n|cffffffffReset automatically on combat start.|r|r"] },
    }

    if not isPriest then
        table.insert(items, { type = "spacer", height = 6 })
        table.insert(items, { type = "desc",
            text = L["|cffff8800These tools are only active while playing a Priest.|r"] })
    end

    table.insert(items, { type = "spacer", height = 4 })
    table.insert(items, { type = "toggle", label = L["Show frame"],
        get = function() return mod.db.showFrame end,
        set = function(_, v)
            mod.db.showFrame = v
            if cFrame then if v then cFrame:Show() else cFrame:Hide() end end
        end })

    table.insert(items, { type = "toggle", label = L["Print to chat at combat end"],
        tooltip = L["Writes a summary in chat after each fight."],
        get = function() return mod.db.showInChat end,
        set = function(_, v) mod.db.showInChat = v end })

    table.insert(items, { type = "slider", label = L["Font size"],
        min = 8, max = 32, step = 1,
        get = function() return mod.db.fontSize end,
        set = function(_, v)
            mod.db.fontSize = v
            if cFrame and cFrame.text then
                cFrame.text:SetFont("Fonts\\FRIZQT__.TTF", v, "OUTLINE")
            end
        end })

    table.insert(items, { type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", label = L["Unlock / Position"], width = 200,
              onClick = function() setUnlocked(not mod.db.unlocked) end },
            { type = "button", label = L["Reset manually"], width = 200,
              onClick = function()
                  totalMana = 0
                  lastTick  = 0
                  updateFrame()
                  ns:Print(L["VT mana reset."])
              end },
        },
    })

    return items
end

function mod:GetOptions(tabId)
    if tabId == "priest" or tabId == nil then
        return priestOptions()
    end
    return {
        { type = "desc", text = L["|cffaaaaaaNo tools for this class yet.|r"] },
    }
end
