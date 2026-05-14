-- =========================================================
-- VuloClassicUI / Modules / FixAuctionPriceDropdown
-- Behebt einen Bug im deutschen Client wo das PriceDropdown im
-- Auktionshaus nil-Fehler wirft. Stellt einen leeren PriceDropdown
-- bereit damit die UI nicht crasht.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("fixauctiondropdown", {
    name        = "Auction Price Fix",
    group       = "Bugfixes",
    description = "Behebt einen nil-Fehler im deutschen Auktionshaus-UI (PriceDropdown nicht definiert).",
    defaults = {
        enabled = true,
    },
})

local applied = false

local function applyFix()
    if applied then return end
    applied = true

    if GetLocale() == "deDE" and not _G.PriceDropdown then
        local f = CreateFrame("Frame", "PriceDropdown", UIParent)
        f.Text           = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.HideSpacerFrame = CreateFrame("Frame", nil, f)
    end
end

function mod:OnEnable()
    applyFix()
end

function mod:GetOptions()
    return {
        { type = "header", text = "Info" },
        { type = "desc", text = "Dieser Fix behebt einen bekannten Bug in der deutschen WoW-Lokalisierung: das Auktionshaus-UI referenziert ein \"PriceDropdown\"-Element, das nie definiert wurde, was zu Lua-Fehlern beim Öffnen des Auktionshauses führt." },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format("|cffaaaaaaAktuelle Sprache: %s|r", GetLocale() or "?") },
        { type = "desc", text = "|cffaaaaaaDer Fix greift nur auf deutschen Clients (deDE). Auf anderen Sprachen ist das Modul inaktiv.|r" },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format("|cffaaaaaaStatus: %s|r",
            applied and (_G.PriceDropdown and "|cff66ff66angewendet|r" or "übersprungen (deDE-only)") or "nicht angewendet") },
    }
end
