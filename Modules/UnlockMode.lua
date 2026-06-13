-- =========================================================
-- VuloClassicUI / Modules / UnlockMode
-- A "Global" entry that toggles the global edit mode (Core/Mover.lua): every
-- VuloUI window shows a draggable purple box at once. No runtime behaviour of
-- its own — it's just a front door for ns:SetMoversEditMode.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("unlockmode", {
    name        = "Unlock Mode",
    group       = "Global",
    noToggle    = true,   -- it's an action, not an on/off feature
    description = "Activate edit mode to move every VuloUI window at once.",
    defaults    = { enabled = true },
})

local function rebuild()
    if ns.UI and ns.UI.BuildOptionsPage then
        ns.UI:BuildOptionsPage("unlockmode", ns.UI.currentTab)
    end
end

-- Open Blizzard's own Edit Mode (Anniversary client). Our OnShow hook then
-- flips global edit mode on, so every VuloUI window is draggable in it too.
local function openBlizzEdit()
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Can't open Edit Mode in combat."]); return
    end
    if not _G.EditModeManagerFrame then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
        if load then pcall(load, "Blizzard_EditMode") end
    end
    local emf = _G.EditModeManagerFrame
    if not emf then
        ns:Print(L["This client has no Blizzard Edit Mode."]); return
    end
    if _G.VuloClassicUIMainFrame then _G.VuloClassicUIMainFrame:Hide() end  -- clear the canvas
    if emf.EnterEditMode then emf:EnterEditMode()
    elseif _G.ShowUIPanel then ShowUIPanel(emf)
    else emf:Show() end
end

function mod:GetOptions()
    local on = ns:IsMoverEditMode()
    local items = {
        { type = "header", text = L["Unlock Mode"] },
        { type = "desc",
          text = L["|cffaaaaaaActivate edit mode to move every VuloUI window at once — cooldown bars, combat text, trackers, castbar, swing timer and more. It also opens automatically with Blizzard's Edit Mode.|r"] },
        { type = "spacer", height = 6 },
        { type = "button", primary = true, width = 360,
          label = on and L["Stop editing — lock all windows"]
                      or  L["Edit mode — move all VuloUI windows"],
          onClick = function()
              ns:SetMoversEditMode(not ns:IsMoverEditMode())
              rebuild()
          end },
        { type = "spacer", height = 4 },
        { type = "button", width = 360,
          label = L["Open Blizzard's Edit Mode"],
          tooltip = L["Opens Blizzard's own Edit Mode (closes this window first). Our windows show up in it too."],
          onClick = openBlizzEdit },
        { type = "spacer", height = 8 },
        { type = "desc",
          text = L["|cff888888• Drag a purple box to move that window.|n• Hover a box, then use the arrow keys to fine-tune (SHIFT = 5px).|n• Right-click a box for exact X / Y.|n• |cffffffff/cdedit|r toggles this too.|r"] },
    }
    if on then
        items[#items + 1] = { type = "desc",
            text = L["|cff44ff44Edit mode is ON.|r Close this window to reach the boxes, then lock again here or with /cdedit."] }
    end
    return items
end
