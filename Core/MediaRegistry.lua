-- =========================================================
-- VuloClassicUI / Core / MediaRegistry
-- Registers all bundled sounds, fonts and statusbars
-- via LibSharedMedia-3.0. Any addon that consumes shared media (WeakAuras,
-- boss mods, other UI suites) will then automatically detect it.
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
-- StatusBars — only the textures bundled under Media\textures.
-- These show up in any statusbar texture picker (Swing Timer, other addons, ...).
-- =========================================================
local TEX = BASE .. "textures\\"
LSM:Register("statusbar", "Atrocity",           TEX .. "atrocity.tga")
LSM:Register("statusbar", "Beautiful",          TEX .. "beautiful.tga")
LSM:Register("statusbar", "Divide",             TEX .. "divide.tga")
LSM:Register("statusbar", "Fade",               TEX .. "fade.tga")
LSM:Register("statusbar", "Fade Right",         TEX .. "fade-right.tga")
LSM:Register("statusbar", "Glass",              TEX .. "glass.tga")
LSM:Register("statusbar", "Gradient",           TEX .. "gradient-lr.tga")
LSM:Register("statusbar", "Gradient (B-T)",     TEX .. "gradient-bt.tga")
LSM:Register("statusbar", "Gradient (R-L)",     TEX .. "gradient-rl.tga")
LSM:Register("statusbar", "Gradient (T-B)",     TEX .. "gradient-tb.tga")
LSM:Register("statusbar", "Matte",              TEX .. "matte.tga")
LSM:Register("statusbar", "Melli",              TEX .. "melli.tga")
LSM:Register("statusbar", "Plating",            TEX .. "plating.tga")
LSM:Register("statusbar", "Sheer",              TEX .. "sheer.tga")
LSM:Register("statusbar", "Soft Line",          TEX .. "soft-line.tga")
LSM:Register("statusbar", "Thin Line (Top)",    TEX .. "thin-line-top.tga")
LSM:Register("statusbar", "Thin Line (Bottom)", TEX .. "thin-line-bottom.tga")

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
