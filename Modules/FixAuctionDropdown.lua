-- =========================================================
-- VuloClassicUI / Modules / FixAuctionPriceDropdown
-- Fixes a bug in the German client where the PriceDropdown in the
-- auction house throws nil errors. Provides an empty PriceDropdown
-- so the UI doesn't crash.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("fixauctiondropdown", {
    name        = "Auction Price Fix",
    group       = "Bugfixes",
    description = "Fixes a nil error in the German auction house UI (PriceDropdown not defined).",
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
        { type = "desc", text = "This fix addresses a known bug in the German WoW localization: the auction house UI references a \"PriceDropdown\" element that was never defined, which causes Lua errors when opening the auction house." },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format("|cffaaaaaaCurrent locale: %s|r", GetLocale() or "?") },
        { type = "desc", text = "|cffaaaaaaThe fix only applies on German clients (deDE). On other languages the module is inactive.|r" },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format("|cffaaaaaaStatus: %s|r",
            applied and (_G.PriceDropdown and "|cff66ff66applied|r" or "skipped (deDE-only)") or "not applied") },
    }
end
