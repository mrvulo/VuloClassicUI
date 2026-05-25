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
local function getMainFrame()    return _G.Trinkets_MainFrame end
local function getIconFrame()    return _G.Trinkets_IconFrame end
local function getOptFrame()     return _G.Trinkets_OptFrame  end

local function setShown(state)
    local f = getMainFrame()
    if not f then return end
    -- Secure-Frame: Show/Hide aus insecure Addon-Code wird vom WoW-Security
    -- geblockt. Skip im Combat, pcall um sonstige action-blocked-Pings abzufangen.
    if InCombatLockdown and InCombatLockdown() then return end
    if state and f:IsShown() then return end
    if not state and not f:IsShown() then return end
    pcall(function()
        if state then f:Show() else f:Hide() end
    end)
end

local function rescaleMain()
    local f = getMainFrame()
    if f and TrinketsPerOptions and TrinketsPerOptions.MainScale then
        f:SetScale(TrinketsPerOptions.MainScale)
    end
end

-- Versteckt Minimap-Icon + Options-Fenster der Engine permanent.
-- Mit HookScript: falls Engine sie später wieder zeigen will, sofort wieder hide.
local function suppressEngineUI()
    -- SavedVar-Flag (falls Engine sich darauf verlässt)
    if _G.TrinketsOptions then
        _G.TrinketsOptions.ShowIcon = "OFF"
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
    -- Engine initialisiert sich beim Load — wir warten kurz mit dem Suppress.
    -- KEIN setShown beim Init (Trinkets_MainFrame ist secure → Show()
    -- aus insecure Code wird vom WoW-Security geblockt). Engine zeigt selbst.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, suppressEngineUI)
        C_Timer.After(2,   suppressEngineUI)
    else
        suppressEngineUI()
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
              return _G.TrinketsOptions and _G.TrinketsOptions.Locked == "ON"
          end,
          set = function(_, v)
              if _G.TrinketsOptions then
                  _G.TrinketsOptions.Locked = v and "ON" or "OFF"
              end
          end },

        { type = "slider", label = "Größe",
          min = 0.5, max = 2.0, step = 0.05,
          tooltip = "Skaliert die Trinket-Slots.",
          get = function()
              return (_G.TrinketsPerOptions and _G.TrinketsPerOptions.MainScale) or 1.0
          end,
          set = function(_, v)
              if _G.TrinketsPerOptions then
                  _G.TrinketsPerOptions.MainScale = v
              end
              rescaleMain()
          end },

        { type = "spacer", height = 4 },
        { type = "desc",
          text = "|cffaaaaaaTipp: Linksklick auf einen Slot nutzt das Trinket, Rechtsklick zeigt die Auswahl-Liste. Auto-Queue konfigurierst du per Rechtsklick → Queue-Tab.|r" },
    }
end
