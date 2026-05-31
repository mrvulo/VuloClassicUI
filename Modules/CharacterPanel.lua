-- =========================================================
-- VuloClassicUI / Modules / CharacterPanel
-- Enhanced character panel (iLvL per slot, sockets, enchant shortening).
-- The actual code lives in CharacterPanel_Impl.lua and reads mod.db.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("characterpanel", {
    name        = "Character Panel",
    group       = "UI Reskin",
    description = "Enhances the character panel: iLvL per slot, socket display, shortened enchant text.",
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
-- Apply iLvL font size to all existing slot displays
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

    -- Path 1: direct slot access (if slot is named and ilvlDisplay is attached directly)
    for _, slot in ipairs(SLOTS) do
        local f = _G["Character" .. slot .. "Slot"]
        if f and f.ilvlDisplay then
            applyFontSize(f.ilvlDisplay, size)
        end
    end

    -- Path 2: Anniversary — ilvlDisplay hangs on anonymous sub-frames of PaperDollItemsFrame
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
    -- Hook on CharacterFrame:OnShow -> iLvL FontStrings are recreated by Impl
    -- with a hard default (11), so reapply after each open with the current slider size
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
    -- Refresh the open character panel so toggles take effect immediately
    local function refreshPanel()
        if ns.RefreshCharacterPanel then ns.RefreshCharacterPanel() end
    end

    return {
        { type = "header", text = L["Display"] },
        { type = "checkbox", label = L["Show item level per slot"],
          get = function() return mod.db.showItemLevel end,
          set = function(_, v) mod.db.showItemLevel = v; refreshPanel() end },
        { type = "checkbox", label = L["Show average item level"],
          get = function() return mod.db.showAvgItemLevel end,
          set = function(_, v) mod.db.showAvgItemLevel = v; refreshPanel() end },
        { type = "checkbox", label = L["Show sockets"],
          get = function() return mod.db.showSockets end,
          set = function(_, v) mod.db.showSockets = v; refreshPanel() end },
        { type = "checkbox", label = L["Shorten enchant text (DE/EN)"],
          tooltip = L["Example: 'Stamina' -> 'Stam', 'Ausdauer' -> 'Ausd'."],
          get = function() return mod.db.shortenEnchants end,
          set = function(_, v) mod.db.shortenEnchants = v; refreshPanel() end },
        { type = "checkbox", label = L["Treat rings as enchantable"],
          tooltip = L["Also shows enchant text on rings (TBC: some professions can enchant rings). /reload required."],
          get = function() return mod.db.ringsEnchantable end,
          set = function(_, v) mod.db.ringsEnchantable = v end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Text Size"] },
        { type = "slider", label = L["Item Level Text Size"],
          min = 8, max = 24, step = 1,
          tooltip = L["Font size of the item level number on each item slot. Takes effect immediately when the character panel is open."],
          get = function() return mod.db.itemLevelSize end,
          set = function(_, v)
              mod.db.itemLevelSize = v
              reapplyItemLevelSize()
          end },

        { type = "spacer" },
        { type = "desc", text = L["Note: Some changes only take full effect after /reload, since the character panel is hooked on load."] },
    }
end
