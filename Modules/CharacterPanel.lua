-- =========================================================
-- VuloClassicUI / Modules / CharacterPanel
-- Ehemals: BetterCharacterPanel (TBC Anniversary)
--
-- WICHTIG: Dieser Stub bindet nur die Settings ein. Der eigentliche
-- Code (iLvL-Anzeige, Sockets, Enchant-Text-Kürzung) ist sehr lang
-- (~880 Zeilen) und nicht trivial zu modularisieren ohne Funktionsverlust.
--
-- Empfohlene Vorgehensweise:
--   1. Erstelle Modules/CharacterPanel_Original.lua
--   2. Kopiere den Inhalt deiner BetterCharacterPanel.lua dort rein
--   3. Ersetze ganz oben die isTBC-Guard durch:
--        local _, ns = ...
--        local mod = ns.modules.characterpanel
--        if not mod or not mod.db or not mod.db.enabled then return end
--   4. Trage CharacterPanel_Original.lua zusätzlich in die .toc ein
--      (nach Modules/CharacterPanel.lua)
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
    },
})

function mod:OnEnable()
    -- Der Original-Code in CharacterPanel_Original.lua liest mod.db
    -- und macht den Rest. Hier ist nichts zu tun außer das Flag setzen,
    -- das die andere Datei beim Laden prüft.
    --
    -- Falls du den Original-Code noch nicht reinkopiert hast, sieht der User
    -- einfach keine Anzeigen — kein Fehler.
end

function mod:GetOptions()
    return {
        { type = "header", text = "Anzeigen" },
        {
            type = "checkbox", label = "Item-Level pro Slot anzeigen",
            get = function() return mod.db.showItemLevel end,
            set = function(_, v) mod.db.showItemLevel = v end,
        },
        {
            type = "checkbox", label = "Durchschnittliches Item-Level anzeigen",
            get = function() return mod.db.showAvgItemLevel end,
            set = function(_, v) mod.db.showAvgItemLevel = v end,
        },
        {
            type = "checkbox", label = "Sockel anzeigen",
            get = function() return mod.db.showSockets end,
            set = function(_, v) mod.db.showSockets = v end,
        },
        {
            type = "checkbox", label = "Verzauberungstexte kürzen (DE/EN)",
            tooltip = "Beispiel: 'Stamina' -> 'Stam', 'Ausdauer' -> 'Ausd'.",
            get = function() return mod.db.shortenEnchants end,
            set = function(_, v) mod.db.shortenEnchants = v end,
        },
        {
            type = "checkbox", label = "Ringe als verzauberbar behandeln",
            tooltip = "Zeigt auch auf Ringen den Verzauberungstext (TBC: einige Berufe können Ringe verzaubern).",
            get = function() return mod.db.ringsEnchantable end,
            set = function(_, v) mod.db.ringsEnchantable = v end,
        },
        { type = "spacer" },
        { type = "desc", text = "Hinweis: Änderungen greifen erst nach /reload vollständig, da das Charakter-Panel beim Laden gehookt wird." },
    }
end
