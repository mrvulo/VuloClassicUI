-- Wraps the embedded engine under Trinkets/*: hides its own options window and minimap icon.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("trinkets", {
    name        = "Trinkets",
    group       = "QoL",
    description = "Two trinket slots on screen with cooldown display, dropdown selection and auto-queue.",
    defaults    = {
        enabled   = true,
        showFrame = true,
    },
})

local function getMainFrame()    return _G.Trinkets_MainFrame end
local function getIconFrame()    return _G.Trinkets_IconFrame end
local function getOptFrame()     return _G.Trinkets_OptFrame  end

local function setShown(state)
    local f = getMainFrame()
    if not f then return end
    -- Secure frame: Show/Hide from insecure code is blocked, so bail in combat and pcall otherwise.
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

-- HookScript keeps them hidden if the engine tries to show them again later.
local function suppressEngineUI()
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

function mod:OnEnable()
    -- Engine initializes on load, so delay the suppress; never call setShown here (secure frame).
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

function mod:GetOptions()
    return {
        { type = "header", text = L["Trinkets"] },
        { type = "desc",
          text = L["|cffaaaaaaTwo trinket slots with cooldown, dropdown selection and auto-queue.|nLeft click = use, right click = dropdown.|r"] },

        { type = "toggle", label = L["Show frame"],
          tooltip = L["Hides or shows the two trinket slots. Auto-queue continues to run while hidden."],
          get = function() return mod.db.showFrame end,
          set = function(_, v)
              mod.db.showFrame = v
              setShown(v)
          end },

        { type = "toggle", label = L["Position locked"],
          tooltip = L["If on, the frame cannot be accidentally moved."],
          get = function()
              return _G.TrinketsOptions and _G.TrinketsOptions.Locked == "ON"
          end,
          set = function(_, v)
              if _G.TrinketsOptions then
                  _G.TrinketsOptions.Locked = v and "ON" or "OFF"
              end
          end },

        { type = "slider", label = L["Size"],
          min = 0.5, max = 2.0, step = 0.05,
          tooltip = L["Scales the trinket slots."],
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
          text = L["|cffaaaaaaTip: Left click on a slot uses the trinket, right click shows the selection list. Auto-queue is configured via right click -> Queue tab.|r"] },
    }
end
