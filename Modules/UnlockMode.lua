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
