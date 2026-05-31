-- =========================================================
-- VuloClassicUI / Core / MediaRegistry
-- Registers all bundled sounds, fonts and statusbars
-- via LibSharedMedia-3.0. Other addons (BigWigs, ElvUI, WeakAuras,
-- DBM, ...) will then automatically detect this media.
--
-- Paths live under Interface\AddOns\VuloClassicUI\Media\
-- =========================================================
local _, ns = ...
local L = ns.L

local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
if not LSM then
    if ns.Print then
        ns:Print(L["|cffff5555LibSharedMedia-3.0 not found, Media Registry will be skipped.|r"])
    end
    return
end

local BASE = "Interface\\Addons\\VuloClassicUI\\Media\\"

-- =========================================================
-- StatusBars
-- =========================================================
LSM:Register("statusbar", "Atrocity", BASE .. "StatusBars\\Atrocity")
LSM:Register("statusbar", "Kait",     BASE .. "StatusBars\\Kait.tga")

-- =========================================================
-- Fonts
-- =========================================================
LSM:Register("font", "Expressway", BASE .. "Fonts\\Expressway.TTF")

-- (Sounds folder removed — VuloClassicUI doesn't use any of its sounds and
--  the 118-file pack was only registered for other addons. QueueTimer uses
--  a built-in Blizzard sound ID, not a bundled file.)

-- =========================================================
-- Global convenience pointer for VCUI modules
-- =========================================================
ns.LSM = LSM
