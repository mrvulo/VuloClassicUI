-- =========================================================
-- VuloClassicUI / Modules / VTManaDisplay
-- Trackt wieviel Mana der Spieler mit Vampirberührung an die
-- Gruppe gegeben hat (5% des Shadow-Schadens pro Tick, pro Mana-User).
-- Reset bei Kampfbeginn. Nur aktiv wenn Priester.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("vtmanadisplay", {
    name        = "VT Mana Display",
    group       = "QoL",
    description = "Zeigt live wieviel Mana du mit Vampirberührung an die Gruppe gegeben hast. Reset bei Kampfbeginn. Nur aktiv wenn Priester.",
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

local VT_SPELL_ID_BASE = 34914  -- Vampiric Touch base (TBC)
local SHADOW_SCHOOL    = 32

-- =========================================================
-- Runtime State
-- =========================================================
local playerGUID
local vtSpellName          -- lokalisierter Name, filtert alle Ränge
local vtTargets  = {}      -- destGUID -> true (aktive VTs)
local totalMana  = 0
local lastTick   = 0
local cFrame              -- Display-Frame

-- =========================================================
-- Helpers
-- =========================================================
local function updateFrame()
    if not cFrame or not cFrame.text then return end
    cFrame.text:SetText(string.format("|cff9b6cffVT Mana:|r %d", math.floor(totalMana)))
end

local function resetCombat()
    totalMana = 0
    lastTick  = 0
    updateFrame()
end

local function reportChat()
    if not mod.db.showInChat then return end
    if totalMana <= 0 then return end
    ns:Print("Vampirberührung: %d Mana an Gruppe gegeben.", math.floor(totalMana))
end

local function refreshSpell()
    vtSpellName = GetSpellInfo(VT_SPELL_ID_BASE)
end

-- =========================================================
-- Combat Log Handler
-- Anniversary nutzt modernes Backend — Args via CombatLogGetCurrentEventInfo().
-- Lookup-Table statt mehrerer string-compares pro Event (Hot-Path-Filter).
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
-- Frame + Mover
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
    cFrame.text:SetText("|cff9b6cffVT Mana:|r 0")

    cFrame.mover = ns:CreateMover(cFrame, {
        label  = "|cffffffffVT MANA|r",
        db     = mod.db,
        width  = 200,
        height = 40,
        onMove = function(x, y)
            ns:Print(string.format("VT-Mana-Frame: x=%.0f, y=%.0f", x, y))
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
        ns:Print("VT-Mana-Mover aktiv. |cff9b6cffZiehen|r oder |cff9b6cffPfeiltasten|r (SHIFT = 5px).")
    else
        cFrame.mover:Hide()
        if not mod.db.showFrame then cFrame:Hide() end
        ns:Print("VT-Mana-Mover deaktiviert.")
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    -- Migration: alte Settings unter "vampirictouchmana" übernehmen
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

    -- Nur Priester
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
function mod:GetOptions()
    return {
        { type = "header", text = "VT Mana Display" },
        { type = "desc",
          text = "|cffaaaaaaZeigt live wieviel Mana du mit Vampirberührung an die Gruppe gegeben hast (5% des Shadow-Schadens pro Tick, pro Mana-User).|n"
              .. "|cffffffffReset automatisch bei Kampfbeginn.|r|n"
              .. "Nur aktiv für Priester.|r" },

        { type = "toggle", label = "Frame anzeigen",
          get = function() return mod.db.showFrame end,
          set = function(_, v)
              mod.db.showFrame = v
              if cFrame then if v then cFrame:Show() else cFrame:Hide() end end
          end },

        { type = "toggle", label = "Bei Kampfende in Chat ausgeben",
          tooltip = "Schreibt nach jedem Kampf eine Zusammenfassung in den Chat.",
          get = function() return mod.db.showInChat end,
          set = function(_, v) mod.db.showInChat = v end },

        { type = "slider", label = "Schriftgröße",
          min = 8, max = 32, step = 1,
          get = function() return mod.db.fontSize end,
          set = function(_, v)
              mod.db.fontSize = v
              if cFrame and cFrame.text then
                  cFrame.text:SetFont("Fonts\\FRIZQT__.TTF", v, "OUTLINE")
              end
          end },

        { type = "group", layout = "row", gap = 8,
          items = {
              { type = "button", label = "Unlock / Positionieren", width = 200,
                onClick = function() setUnlocked(not mod.db.unlocked) end },
              { type = "button", label = "Manuell zurücksetzen", width = 200,
                onClick = function()
                    totalMana = 0
                    lastTick  = 0
                    updateFrame()
                    ns:Print("VT-Mana zurückgesetzt.")
                end },
          },
        },
    }
end
