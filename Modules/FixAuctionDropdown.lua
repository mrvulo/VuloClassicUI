-- =========================================================
-- VuloClassicUI / Modules / FixAuctionPriceDropdown
-- Fixes a bug in the German client where the PriceDropdown in the
-- auction house throws nil errors. Provides an empty PriceDropdown
-- so the UI doesn't crash.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixauctiondropdown", {
    name        = L["Auction Price Fix"],
    group       = "Bugfixes",
    description = L["Fixes a nil error in the German auction house UI (PriceDropdown not defined)."],
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
        { type = "header", text = L["Info"] },
        { type = "desc", text = L["This fix addresses a known bug in the German WoW localization: the auction house UI references a \"PriceDropdown\" element that was never defined, which causes Lua errors when opening the auction house."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaCurrent locale: %s|r"], GetLocale() or "?") },
        { type = "desc", text = L["|cffaaaaaaThe fix only applies on German clients (deDE). On other languages the module is inactive.|r"] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            applied and (_G.PriceDropdown and L["|cff66ff66applied|r"] or L["skipped (deDE-only)"]) or L["not applied"]) },
    }
end
