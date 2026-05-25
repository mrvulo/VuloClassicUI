-- =========================================================
-- VuloClassicUI / Core / MediaRegistry
-- Registers all bundled sounds, fonts and statusbars
-- via LibSharedMedia-3.0. Other addons (BigWigs, ElvUI, WeakAuras,
-- DBM, ...) will then automatically detect this media.
--
-- Paths live under Interface\AddOns\VuloClassicUI\Media\
-- =========================================================
local _, ns = ...

local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
if not LSM then
    if ns.Print then
        ns:Print("|cffff5555LibSharedMedia-3.0 not found, Media Registry will be skipped.|r")
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

-- =========================================================
-- Sounds
-- =========================================================
local SOUNDS = BASE .. "Sounds\\"

local namedSounds = {
    Blade        = "Blade.ogg",
    Buffed       = "Buffed.ogg",
    Bullet       = "Bullet.ogg",
    Info         = "Info.ogg",
    Mail         = "Mail.ogg",
    Positive     = "Positive.ogg",
    Thunder      = "Thunder.ogg",
    ["On You"]   = "OnYou.ogg",
}
for name, file in pairs(namedSounds) do
    LSM:Register("sound", name, SOUNDS .. file)
end

-- Numbers 1-10 (with red-tinted label)
for i = 1, 10 do
    local label = string.format("|cFFFF0000%d|r", i)
    -- Original VuloMedia used "FE0000" instead of "FF0000" for 10 — kept as-is
    if i == 10 then label = "|cFFFE000010|r" end
    LSM:Register("sound", label, SOUNDS .. tostring(i) .. ".ogg")
end

-- Raid marker icons 1-8 (with texture icon)
for i = 1, 8 do
    local label = string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:16|t", i)
    LSM:Register("sound", label, SOUNDS .. string.format("0%d.ogg", i))
end

-- Boss calls & generic encounter sounds (red-tinted)
local redSounds = {
    "Add", "Adds", "AoE", "Assist", "Avoid", "Back", "Backup", "Bait", "Beam",
    "Bloodlust", "Blue", "Boss", "Break", "Buff", "CC", "CD", "Center", "Chain",
    "Charge", "Clear", "Collect", "Dance", "Debuff", "Dispell", "Dodge",
    "Dont Move", "Dot", "Drop", "Enter", "Escort", "Exit", "Fixate", "Front",
    "Gate", "Gather", "Green", "Healcd", "Hide", "High Energy", "High Stacks",
    "Immunity", "In", "Interrupt", "Intermission", "Invisibility", "Jump",
    "Knock", "Left", "Linked", "LoS", "Melee", "Move", "Next", "Nuke", "Orange",
    "Orb", "Out", "Overlap", "Phase2", "Phase3", "Pots", "Pull", "Purple",
    "Push", "Range", "Ready", "Red", "Reflect", "Right", "Root", "Seed",
    "Selfcd", "Shield", "Soak", "Soon", "Spawn", "Spellsteal", "Split",
    "Spread", "Stack", "Stop", "Stopcast", "Switch", "Targeted", "Taunt",
    "Totem", "Transition", "Trap", "Turn", "Winds", "Yellow", "Zone",
}
for _, name in ipairs(redSounds) do
    local label = "|cFFFF0000" .. name .. "|r"
    LSM:Register("sound", label, SOUNDS .. name .. ".ogg")
end

-- =========================================================
-- Global convenience pointer for VCUI modules
-- =========================================================
ns.LSM = LSM
