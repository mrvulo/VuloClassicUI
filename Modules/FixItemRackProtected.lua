-- =========================================================
-- VuloClassicUI / Modules / FixItemRackProtected
-- Fixes an Anniversary crash with ItemRack:
--   ItemRack hooks CharacterModelFrame:OnMouseUp and in the old handler calls
--   AutoEquipCursorItem(). In Anniversary that function is protected,
--   meaning it cannot be called from an addon hook ->
--   ADDON_ACTION_BLOCKED.
-- We replace ItemRack's hook with a wrapper: if the cursor is holding an item,
-- we block the call (ClearCursor -> item goes back to inventory,
-- nothing is lost) and report it once in chat.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixitemrack", {
    name        = L["ItemRack Protected Fix"],
    group       = "Bugfixes",
    description = L["Catches the Anniversary ADDON_ACTION_BLOCKED crash when ItemRack tries to auto-equip an item on the character model."],
    defaults = {
        enabled    = true,
        showReport = true,
    },
})

local CursorHasItem = CursorHasItem
local ClearCursor   = ClearCursor

-- =========================================================
-- Installation
-- =========================================================
local wrappedAlready = false

local function installPatch()
    if wrappedAlready then return end
    local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if not IsLoaded or not IsLoaded("ItemRack") then return end

    local frame = _G.CharacterModelFrame
    if not frame then return end

    local oldScript = frame:GetScript("OnMouseUp")
    if not oldScript then return end

    frame:SetScript("OnMouseUp", function(self, button)
        if not mod._enabled then
            return oldScript(self, button)
        end

        if CursorHasItem and CursorHasItem() then
            -- Prevents ItemRack's blocked AutoEquipCursorItem call:
            -- Item returns to inventory (does NOT get lost).
            ClearCursor()
            if mod.db.showReport and not _G.VCUI_ItemRackFix_Reported then
                _G.VCUI_ItemRackFix_Reported = true
                DEFAULT_CHAT_FRAME:AddMessage(
                    L["|cffffff00[VuloClassicUI]|r ItemRack auto-equip on character model blocked (Anniversary protection). Please use drag & drop directly into the equipment slot."])
            end
            return
        end

        -- No cursor item — let ItemRack's hook run normally
        -- (rotation handling, etc.)
        oldScript(self, button)
    end)

    wrappedAlready = true
end

-- =========================================================
-- Lifecycle
-- =========================================================
local installFrame

function mod:OnEnable()
    if not installFrame then
        installFrame = CreateFrame("Frame")
        installFrame:RegisterEvent("ADDON_LOADED")
        installFrame:RegisterEvent("PLAYER_LOGIN")
        installFrame:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "ItemRack" then
                installPatch()
            else
                -- PLAYER_LOGIN or other addon — generic attempt
                installPatch()
            end
        end)
    end

    -- Direct attempt + delayed retries (ItemRack may set its hook later)
    installPatch()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, installPatch)
        C_Timer.After(3, installPatch)
    end
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = L["Behavior"] },
        {
            type = "toggle", label = L["Chat message on first block"],
            tooltip = L["Shows a message once per session when ItemRack's auto-equip was blocked."],
            get = function() return mod.db.showReport end,
            set = function(_, v) mod.db.showReport = v end,
        },
        { type = "spacer", height = 8 },
        { type = "desc", text = L["This fix replaces ItemRack's |cffffffffCharacterModelFrame:OnMouseUp|r hook with a wrapper. When you hold an item on the cursor and click on the character model, ItemRack would call the protected |cffffffffAutoEquipCursorItem()|r — Anniversary blocks that. Instead we clear the cursor (item goes back to inventory) and avoid the crash."] },
        { type = "spacer", height = 4 },
        { type = "desc", text = L["|cffaaaaaaTip: Drag & dropping items directly into the equipment slot still works normally.|r"] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            wrappedAlready and L["|cff66ff66Hook active|r"] or L["waiting for ItemRack"]) },
    }
end
