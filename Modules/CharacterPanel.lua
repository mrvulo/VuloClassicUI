-- =========================================================
-- VuloClassicUI / Modules / CharacterPanel
-- Verbessertes Charakter-Panel (iLvL pro Slot, Sockets, Enchant-Kürzung).
-- Der eigentliche Code liegt in CharacterPanel_Impl.lua und liest mod.db.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("characterpanel", {
    name        = "Character Panel",
    group       = "UI Reskin",
    description = "Verbessert das Charakter-Panel: iLvL pro Slot, Sockel-Anzeige, gekürzte Enchant-Texte.",
    defaults = {
        showItemLevel       = true,
        showSockets         = true,
        shortenEnchants     = true,
        ringsEnchantable    = true,
        showAvgItemLevel    = true,
        itemLevelSize       = 11,
    },
})

-- =========================================================
-- iLvL Font-Size auf alle existing slot displays anwenden
-- =========================================================
local SLOTS = {
    "Head","Neck","Shoulder","Back","Chest","Wrist","Hands","Waist",
    "Legs","Feet","Finger0","Finger1","Trinket0","Trinket1",
    "MainHand","SecondaryHand","Ranged",
}

local function applyFontSize(fs, size)
    if not fs or not fs.SetFont or not fs.GetFont then return false end
    local ok, file, _, flags = pcall(fs.GetFont, fs)
    if ok and type(file) == "string" then
        pcall(fs.SetFont, fs, file, size, flags or "OUTLINE")
        return true
    end
    return false
end

local function reapplyItemLevelSize()
    local size = mod.db.itemLevelSize or 11

    -- Pfad 1: direkter Slot-Zugriff (falls Slot named ist und ilvlDisplay direkt anhängt)
    for _, slot in ipairs(SLOTS) do
        local f = _G["Character" .. slot .. "Slot"]
        if f and f.ilvlDisplay then
            applyFontSize(f.ilvlDisplay, size)
        end
    end

    -- Pfad 2: Anniversary — ilvlDisplay hängt an anonymen Sub-Frames von PaperDollItemsFrame
    local pdi = _G.PaperDollItemsFrame
    if pdi and pdi.GetChildren then
        for _, child in ipairs({ pdi:GetChildren() }) do
            if child.ilvlDisplay then
                applyFontSize(child.ilvlDisplay, size)
            end
        end
    end
end
mod.reapplyItemLevelSize = reapplyItemLevelSize

function mod:OnEnable()
    -- Hook auf CharacterFrame:OnShow → iLvL-FontStrings werden vom Impl neu erstellt
    -- mit hartem default (11), daher reapply nach jedem Open mit aktueller Slider-Größe
    if _G.CharacterFrame and not _G.CharacterFrame._vcui_ilvlHook then
        _G.CharacterFrame._vcui_ilvlHook = true
        _G.CharacterFrame:HookScript("OnShow", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, reapplyItemLevelSize)
            else
                reapplyItemLevelSize()
            end
        end)
    end
end

function mod:GetOptions()
    return {
        { type = "header", text = "Anzeigen" },
        { type = "checkbox", label = "Item-Level pro Slot anzeigen",
          get = function() return mod.db.showItemLevel end,
          set = function(_, v) mod.db.showItemLevel = v end },
        { type = "checkbox", label = "Durchschnittliches Item-Level anzeigen",
          get = function() return mod.db.showAvgItemLevel end,
          set = function(_, v) mod.db.showAvgItemLevel = v end },
        { type = "checkbox", label = "Sockel anzeigen",
          get = function() return mod.db.showSockets end,
          set = function(_, v) mod.db.showSockets = v end },
        { type = "checkbox", label = "Verzauberungstexte kürzen (DE/EN)",
          tooltip = "Beispiel: 'Stamina' -> 'Stam', 'Ausdauer' -> 'Ausd'.",
          get = function() return mod.db.shortenEnchants end,
          set = function(_, v) mod.db.shortenEnchants = v end },
        { type = "checkbox", label = "Ringe als verzauberbar behandeln",
          tooltip = "Zeigt auch auf Ringen den Verzauberungstext (TBC: einige Berufe können Ringe verzaubern).",
          get = function() return mod.db.ringsEnchantable end,
          set = function(_, v) mod.db.ringsEnchantable = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = "Textgröße" },
        { type = "slider", label = "Item-Level Text Größe",
          min = 8, max = 24, step = 1,
          tooltip = "Schriftgröße der Item-Level-Zahl auf jedem Item-Slot. Wirkt sofort wenn das Charakter-Panel offen ist.",
          get = function() return mod.db.itemLevelSize end,
          set = function(_, v)
              mod.db.itemLevelSize = v
              reapplyItemLevelSize()
          end },

        { type = "spacer" },
        { type = "desc", text = "Hinweis: Einige Änderungen greifen erst nach /reload vollständig, da das Charakter-Panel beim Laden gehookt wird." },
    }
end
