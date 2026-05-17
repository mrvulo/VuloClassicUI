-- =========================================================
-- VuloClassicUI / Modules / Trinkets
-- Zwei Trinket-Slots mit Cooldown, Dropdown und Queue.
-- Eingebettete Engine unter Trinkets/* (Code unverändert).
-- Dieses Modul:
--   • versteckt das eigene Options-Fenster + Minimap-Icon der Engine
--   • bringt alle relevanten Einstellungen direkt in die VCUI-Modulseite
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("trinkets", {
    name        = "Trinkets",
    group       = "QoL",
    description = "Zwei Trinket-Slots auf dem Bildschirm mit Cooldown-Anzeige, Dropdown-Auswahl und Auto-Queue.",
    defaults    = {
        enabled   = true,
        showFrame = true,
    },
})

-- =========================================================
-- Helpers
-- =========================================================
local function getMainFrame()    return _G.TrinketMenu_MainFrame end
local function getIconFrame()    return _G.TrinketMenu_IconFrame end
local function getOptFrame()     return _G.TrinketMenu_OptFrame  end

local function setShown(state)
    local f = getMainFrame()
    if not f then return end
    if state then f:Show() else f:Hide() end
end

local function rescaleMain()
    local f = getMainFrame()
    if f and TrinketMenuPerOptions and TrinketMenuPerOptions.MainScale then
        f:SetScale(TrinketMenuPerOptions.MainScale)
    end
end

-- Versteckt Minimap-Icon + Options-Fenster der Engine permanent.
-- Mit HookScript: falls Engine sie später wieder zeigen will, sofort wieder hide.
local function suppressEngineUI()
    -- SavedVar-Flag (falls Engine sich darauf verlässt)
    if _G.TrinketMenuOptions then
        _G.TrinketMenuOptions.ShowIcon = "OFF"
    end

    local mm = getIconFrame()
    if mm then
        mm:Hide()
        mm:EnableMouse(false)
        if not mm._vcui_suppressHooked then
            mm._vcui_suppressHooked = true
            mm:HookScript("OnShow", function(self) self:Hide() end)
        end
    end

    local opt = getOptFrame()
    if opt then
        opt:Hide()
        if not opt._vcui_suppressHooked then
            opt._vcui_suppressHooked = true
            opt:HookScript("OnShow", function(self) self:Hide() end)
        end
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    -- Engine initialisiert sich beim Load — wir warten kurz und übernehmen
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            suppressEngineUI()
            setShown(mod.db.showFrame)
        end)
        -- Sicherheitsnetz: nach 2s nochmal (falls Engine später shown will)
        C_Timer.After(2, suppressEngineUI)
    else
        suppressEngineUI()
        setShown(mod.db.showFrame)
    end
end

function mod:OnDisable()
    setShown(false)
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = "Trinkets" },
        { type = "desc",
          text = "|cffaaaaaaZwei Trinket-Slots mit Cooldown, Dropdown-Auswahl und Auto-Queue.|n"
              .. "Linksklick = nutzen, Rechtsklick = Dropdown.|r" },

        { type = "toggle", label = "Frame anzeigen",
          tooltip = "Versteckt oder zeigt die zwei Trinket-Slots. Auto-Queue läuft auch im versteckten Zustand weiter.",
          get = function() return mod.db.showFrame end,
          set = function(_, v)
              mod.db.showFrame = v
              setShown(v)
          end },

        { type = "toggle", label = "Position gesperrt",
          tooltip = "Wenn an, kann das Frame nicht versehentlich verschoben werden.",
          get = function()
              return _G.TrinketMenuOptions and _G.TrinketMenuOptions.Locked == "ON"
          end,
          set = function(_, v)
              if _G.TrinketMenuOptions then
                  _G.TrinketMenuOptions.Locked = v and "ON" or "OFF"
              end
          end },

        { type = "slider", label = "Größe",
          min = 0.5, max = 2.0, step = 0.05,
          tooltip = "Skaliert die Trinket-Slots.",
          get = function()
              return (_G.TrinketMenuPerOptions and _G.TrinketMenuPerOptions.MainScale) or 1.0
          end,
          set = function(_, v)
              if _G.TrinketMenuPerOptions then
                  _G.TrinketMenuPerOptions.MainScale = v
              end
              rescaleMain()
          end },

        { type = "spacer", height = 4 },
        { type = "desc",
          text = "|cffaaaaaaTipp: Linksklick auf einen Slot nutzt das Trinket, Rechtsklick zeigt die Auswahl-Liste. Auto-Queue konfigurierst du per Rechtsklick → Queue-Tab.|r" },
    }
end
