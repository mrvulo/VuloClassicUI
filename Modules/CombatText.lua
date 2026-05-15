-- =========================================================
-- VuloClassicUI / Modules / CombatText
-- Wrapper für Blizzards eingebauten Floating Combat Text:
-- Master + pro-Event Toggles, plus freier Mover für den Anchor.
-- =========================================================
local _, ns = ...

-- API-Compat: Anniversary nutzt modernes Backend → C_AddOns statt Globals
local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
local LoadAddOn     = (C_AddOns and C_AddOns.LoadAddOn)     or _G.LoadAddOn

local mod = ns:RegisterModule("combattext", {
    name        = "Combat Text",
    group       = "QoL",
    description = "Blizzards Floating Combat Text mit konfigurierbaren Event-Filtern und frei positionierbarem Anchor.",
    defaults    = {
        enabled        = true,
        master         = true,
        combatState    = true,   -- +Combat / -Combat
        spellMechanics = true,   -- Interrupted / Reflected
        dispels        = true,   -- Dispelled (Purged fällt auch hier rein)
        auras          = true,   -- You gave / gave you
        reactives      = true,   -- Reflected, Counterattack-Procs
        dodgeParryMiss = true,   -- Parried / Dodged / Missed
        repairs        = true,   -- Reparaturkosten
        x              = 0,      -- Offset relativ zu PlayerFrameHealthBar.TOP
        y              = 0,
        unlocked       = false,
        sharpFonts     = true,   -- Skurri-Bitmap → Friz Quadrata TTF + OUTLINE
        worldTextScale = 1.0,    -- Engine-FCT (über Mob/Pet) Skalierung — 1.0 = Standard
    },
})

-- =========================================================
-- CVar Mapping
-- =========================================================
local CVARS = {
    master          = "enableCombatText",
    combatState     = "floatingCombatTextCombatState",
    spellMechanics  = "floatingCombatTextSpellMechanics",
    dispels         = "floatingCombatTextDispels",
    auras           = "floatingCombatTextAuras",
    reactives       = "floatingCombatTextReactives",
    dodgeParryMiss  = "floatingCombatTextDodgeParryMiss",
    repairs         = "floatingCombatTextRepairs",
}

-- =========================================================
-- Helpers
-- =========================================================
local function applyWorldTextScale()
    local v = tostring(mod.db.worldTextScale or 1.0)
    -- Mehrere mögliche CVar-Namen je nach WoW-Version probieren
    pcall(SetCVar, "WorldTextScale",  v)
    pcall(SetCVar, "damageTextScale", v)
end

local function applyCVars()
    for key, cvar in pairs(CVARS) do
        pcall(SetCVar, cvar, mod.db[key] and "1" or "0")
    end
    applyWorldTextScale()
    -- Legacy globale Flag (in alten Builds verwendet)
    if SHOW_COMBAT_TEXT ~= nil then
        SHOW_COMBAT_TEXT = mod.db.master and "1" or "0"
    end
    -- Blizzard CombatText nachladen wenn nötig
    if mod.db.master then
        if IsAddOnLoaded and not IsAddOnLoaded("Blizzard_CombatText") and LoadAddOn then
            pcall(LoadAddOn, "Blizzard_CombatText")
        end
        if CombatText_UpdateDisplayedMessages then
            pcall(CombatText_UpdateDisplayedMessages)
        end
    end
end

local function getAnchor()
    return _G.PlayerFrameHealthBar or _G.PlayerFrame
end

-- =========================================================
-- Skurri-Bitmap durch Friz Quadrata TTF ersetzen.
-- Blizzards CombatText nutzt die NumberFont_Outline_* Templates für
-- die großen Damage-Zahlen — bei nicht-nativen UI-Scales wird die
-- Bitmap-Font Skurri unscharf. TTF + OUTLINE bleibt bei jeder Scale scharf.
-- =========================================================
local FONTS_TO_SHARPEN = {
    "NumberFont_Outline_Huge",
    "NumberFont_Outline_Large",
    "NumberFont_Outline_Med",
    "NumberFontNormalHuge",
    "CombatTextFont",
    -- Hit-Indikatoren auf UnitFrames (Schaden über Pet/Player-Portrait)
    "PetHitIndicator",
    "PlayerHitIndicator",
}

local function applySharpFonts()
    if not mod.db.sharpFonts then return end
    local font = "Fonts\\FRIZQT__.TTF"
    for _, name in ipairs(FONTS_TO_SHARPEN) do
        local f = _G[name]
        if f and f.SetFont and f.GetFont then
            local _, size, flags = f:GetFont()
            size  = size or 16
            flags = flags or "OUTLINE"
            -- Wenn schon OUTLINE drin: behalten. Sonst OUTLINE hinzufügen.
            if not flags:find("OUTLINE") then
                flags = flags .. (flags ~= "" and "," or "") .. "OUTLINE"
            end
            pcall(f.SetFont, f, font, size, flags)
        end
    end
end

local function reAnchorCombatText()
    local ct = _G.CombatText
    local anchor = getAnchor()
    if not ct or not anchor then return end
    ct:ClearAllPoints()
    ct:SetPoint("BOTTOM", anchor, "TOP", mod.db.x or 0, 25 + (mod.db.y or 0))
end

-- =========================================================
-- Mover-Frame
-- =========================================================
local moverFrame

local function applyMoverPosition()
    if moverFrame then
        local anchor = getAnchor()
        if anchor then
            moverFrame:ClearAllPoints()
            moverFrame:SetPoint("BOTTOM", anchor, "TOP",
                mod.db.x or 0, 25 + (mod.db.y or 0))
        end
    end
    reAnchorCombatText()
end

local function createMover()
    if moverFrame then return moverFrame end

    moverFrame = CreateFrame("Frame", "VCUI_CombatTextMover", UIParent)
    moverFrame:SetSize(200, 60)
    moverFrame:SetFrameStrata("HIGH")
    moverFrame:EnableMouse(true)
    moverFrame:SetMovable(true)
    moverFrame:Hide()

    local anchor = getAnchor()
    if anchor then
        moverFrame:SetPoint("BOTTOM", anchor, "TOP",
            mod.db.x or 0, 25 + (mod.db.y or 0))
    else
        moverFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    moverFrame.bg = moverFrame:CreateTexture(nil, "BACKGROUND")
    moverFrame.bg:SetAllPoints(moverFrame)
    moverFrame.bg:SetColorTexture(0.6, 0.4, 1.0, 0.4)

    moverFrame.border = CreateFrame("Frame", nil, moverFrame,
        BackdropTemplateMixin and "BackdropTemplate")
    moverFrame.border:SetAllPoints(moverFrame)
    if moverFrame.border.SetBackdrop then
        moverFrame.border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })
        moverFrame.border:SetBackdropBorderColor(0.75, 0.35, 1, 1)
    end

    moverFrame.label = moverFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    moverFrame.label:SetPoint("CENTER", moverFrame, "CENTER", 0, 0)
    moverFrame.label:SetText("|cffffffffCOMBAT TEXT|r")

    moverFrame:RegisterForDrag("LeftButton")
    moverFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    moverFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Offset zur PlayerFrame anchor berechnen
        local a = getAnchor()
        if not a then return end
        local mx, my = self:GetCenter()
        local ax, ay = a:GetCenter()
        local _, ah  = a:GetSize()
        local _, mh  = self:GetSize()
        -- Wir wollen: mover BOTTOM = anchor.TOP + 25 + db.y
        -- → mover.center_y = anchor.center_y + ah/2 + 25 + db.y + mh/2
        -- → db.y = mover.center_y - anchor.center_y - ah/2 - 25 - mh/2
        local dy = my - ay - ah/2 - 25 - mh/2
        local dx = mx - ax
        mod.db.x = dx
        mod.db.y = dy
        applyMoverPosition()
        ns:Print(string.format("Combat-Text-Anchor: x=%.0f, y=%.0f", dx, dy))
    end)

    -- Keyboard für Fein-Justierung (1px, SHIFT = 5px)
    moverFrame:EnableKeyboard(true)
    moverFrame:SetPropagateKeyboardInput(true)
    moverFrame:SetScript("OnKeyDown", function(self, key)
        if not mod.db.unlocked then
            self:SetPropagateKeyboardInput(true)
            return
        end
        local step = IsShiftKeyDown() and 5 or 1
        local dx, dy = 0, 0
        if     key == "UP"    then dy =  step
        elseif key == "DOWN"  then dy = -step
        elseif key == "LEFT"  then dx = -step
        elseif key == "RIGHT" then dx =  step
        else
            self:SetPropagateKeyboardInput(true)
            return
        end
        self:SetPropagateKeyboardInput(false)
        mod.db.x = (mod.db.x or 0) + dx
        mod.db.y = (mod.db.y or 0) + dy
        applyMoverPosition()
    end)

    return moverFrame
end

local function setUnlocked(state)
    mod.db.unlocked = state
    createMover()
    applyMoverPosition()
    if state then
        moverFrame:Show()
        ns:Print("Combat-Text-Mover aktiv. |cff9b6cffZiehen|r oder |cff9b6cffPfeiltasten|r (SHIFT = 5px).")
    else
        moverFrame:Hide()
        ns:Print("Combat-Text-Mover deaktiviert.")
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    applyCVars()
    applySharpFonts()
    -- Blizzard CombatText positioniert sich beim Load — daher delayed Re-Anchor
    -- + nochmal sharpFonts da Blizzard die Templates beim ersten Load resetten könnte
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            reAnchorCombatText()
            applySharpFonts()
        end)
    else
        reAnchorCombatText()
    end
end

function mod:OnDisable()
    pcall(SetCVar, "enableCombatText", "0")
    if SHOW_COMBAT_TEXT ~= nil then SHOW_COMBAT_TEXT = "0" end
    if moverFrame then moverFrame:Hide() end
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local function makeToggle(key, label, tooltip)
        return {
            type = "toggle", label = label, tooltip = tooltip,
            get = function() return mod.db[key] end,
            set = function(_, v)
                mod.db[key] = v
                applyCVars()
            end,
        }
    end

    return {
        { type = "header", text = "Combat Text" },
        { type = "desc",
          text = "|cffaaaaaaBlizzards eingebauter Floating Combat Text. Master-Schalter steuert das ganze System, jeder Event-Typ ist einzeln an/aus schaltbar.|r" },

        makeToggle("master", "Combat Text aktivieren (Master)",
            "Schaltet das gesamte Floating-Combat-Text-System ein oder aus."),

        { type = "spacer", height = 8 },
        { type = "header", text = "Events" },

        makeToggle("combatState",    "+Combat / -Combat",
            "Zeigt 'Entering Combat' und 'Leaving Combat'."),
        makeToggle("spellMechanics", "Interrupted / Reflected (Spell-Mechaniken)",
            "Zeigt unterbrochene oder reflektierte Zauber."),
        makeToggle("dispels",        "Dispelled / Purged",
            "Zeigt eigene Dispels und Purges (Buff-Entfernungen)."),
        makeToggle("auras",          "You gave / gave you (Auras)",
            "Zeigt verteilte und erhaltene Buffs/Debuffs."),
        makeToggle("reactives",      "Reaktive Procs",
            "Zeigt reaktive Spells (z.B. Counterattack-Proc, Reflected)."),
        makeToggle("dodgeParryMiss", "Parried / Dodged / Missed",
            "Zeigt geblockte/pariert/ausgewichene Treffer."),
        makeToggle("repairs",        "Reparaturkosten",
            "Zeigt Reparaturkosten beim NPC."),

        { type = "spacer", height = 8 },
        { type = "header", text = "Darstellung" },
        { type = "toggle", label = "Schärfere Schrift (Friz Quadrata TTF + OUTLINE)",
          tooltip = "Ersetzt die Skurri-Bitmap-Schrift durch Friz Quadrata mit Outline. Bleibt bei jeder UI-Scale scharf statt verschwommen.",
          get = function() return mod.db.sharpFonts end,
          set = function(_, v)
              mod.db.sharpFonts = v
              if v then
                  applySharpFonts()
                  ns:Print("Damage-Text-Schrift gesch\195\164rft. |cffffff00/reload|r falls die Standard-Font noch \195\188brig ist.")
              else
                  ns:Print("Damage-Text-Schrift zur\195\188ckgesetzt — |cffffff00/reload|r erforderlich um Skurri wieder zu laden.")
              end
          end },
        { type = "slider", label = "Engine-FCT Skalierung (über Mob/Pet)",
          min = 1.0, max = 2.5, step = 0.1,
          tooltip = "Skaliert die Schadenszahlen die im 3D-World über Mobs und Pets erscheinen. Bei niedriger UI-Scale (z.B. 65%) hochsetzen — gibt der Bitmap-Font mehr Pixel, wird schärfer.",
          get = function() return mod.db.worldTextScale or 1.0 end,
          set = function(_, v)
              mod.db.worldTextScale = v
              applyWorldTextScale()
          end },
        { type = "desc",
          text = "|cffaaaaaa\195\156ber-Mob/Pet-Zahlen sind |cffffffffEngine-gerendert|r |cffaaaaaa(nicht Lua), nur via Scale beeinflussbar. Pixel-perfect UI-Scale w\195\244re |cffffffff768/Bildschirmh\195\182he|r |cffaaaaaa(z.B. 0.71 bei 1080p, 0.53 bei 1440p).|r" },

        { type = "spacer", height = 8 },
        { type = "header", text = "Position" },
        { type = "desc",
          text = "|cffaaaaaaCombat Text erscheint Standard \195\188ber dem Spieler-Frame. Unlock zeigt einen Mover — mit Drag oder Pfeiltasten verschieben (SHIFT = 5px).|r" },
        { type = "group", layout = "row", gap = 8,
          items = {
              { type = "button", label = "Unlock / Positionieren", width = 200,
                onClick = function() setUnlocked(not mod.db.unlocked) end },
              { type = "button", label = "Position zurücksetzen", width = 180,
                onClick = function()
                    mod.db.x = 0
                    mod.db.y = 0
                    applyMoverPosition()
                    ns:Print("Combat-Text-Position zur\195\188ckgesetzt.")
                end },
          },
        },
    }
end
