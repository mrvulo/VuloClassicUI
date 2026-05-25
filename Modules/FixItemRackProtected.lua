-- =========================================================
-- VuloClassicUI / Modules / FixItemRackProtected
-- Behebt einen Anniversary-Crash bei ItemRack:
--   ItemRack hookt CharacterModelFrame:OnMouseUp und ruft im alten Handler
--   AutoEquipCursorItem() auf. In Anniversary ist die Funktion protected,
--   darf also nicht aus einem Addon-Hook heraus aufgerufen werden →
--   ADDON_ACTION_BLOCKED.
-- Wir ersetzen ItemRack's Hook durch einen Wrapper: wenn der Cursor ein Item
-- trägt, blocken wir den Call (ClearCursor → Item geht ins Inventory zurück,
-- nichts geht verloren) und melden es einmalig im Chat.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("fixitemrack", {
    name        = "ItemRack Protected Fix",
    group       = "Bugfixes",
    description = "F\195\164ngt den Anniversary ADDON_ACTION_BLOCKED-Crash ab, wenn ItemRack versucht ein Item am Charaktermodell automatisch zu equippen.",
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
            -- Verhindert ItemRack's geblockten AutoEquipCursorItem-Call:
            -- Item zur\195\188ck ins Inventar (geht NICHT verloren).
            ClearCursor()
            if mod.db.showReport and not _G.VCUI_ItemRackFix_Reported then
                _G.VCUI_ItemRackFix_Reported = true
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffffff00[VuloClassicUI]|r ItemRack Auto-Equip am Charaktermodell blockiert (Anniversary-Schutz). " ..
                    "Bitte Drag&Drop direkt in den Equipment-Slot verwenden.")
            end
            return
        end

        -- Kein Cursor-Item — ItemRack's Hook normal durchlaufen lassen
        -- (Rotations-Handling etc.)
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
                -- PLAYER_LOGIN oder anderes addon — generischer Versuch
                installPatch()
            end
        end)
    end

    -- Direkter Versuch + delayed Retries (ItemRack k\195\182nnte Hook erst sp\195\164t setzen)
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
        { type = "header", text = "Verhalten" },
        {
            type = "toggle", label = "Chat-Nachricht beim ersten Block",
            tooltip = "Zeigt einmalig pro Session eine Nachricht wenn ItemRack's Auto-Equip blockiert wurde.",
            get = function() return mod.db.showReport end,
            set = function(_, v) mod.db.showReport = v end,
        },
        { type = "spacer", height = 8 },
        { type = "desc", text = "Dieser Fix ersetzt ItemRack's |cffffffffCharacterModelFrame:OnMouseUp|r-Hook durch einen Wrapper. Wenn du ein Item am Cursor h\195\164ltst und auf das Charaktermodell klickst, w\195\188rde ItemRack die geschtzte |cffffffffAutoEquipCursorItem()|r aufrufen — Anniversary blockt das. Wir clearen stattdessen den Cursor (Item geht zur\195\188ck ins Inventar) und vermeiden so den Crash." },
        { type = "spacer", height = 4 },
        { type = "desc", text = "|cffaaaaaaTipp: Items per Drag&Drop direkt in den Equipment-Slot ziehen funktioniert weiterhin normal.|r" },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format("|cffaaaaaaStatus: %s|r",
            wrappedAlready and "|cff66ff66Hook aktiv|r" or "wartet auf ItemRack") },
    }
end
