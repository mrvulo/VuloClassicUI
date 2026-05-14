-- =========================================================
-- VuloClassicUI / Core / MediaRegistry
-- Registriert alle mitgelieferten Sounds, Fonts und StatusBars
-- via LibSharedMedia-3.0. Andere Addons (BigWigs, ElvUI, WeakAuras,
-- DBM, ...) erkennen diese Media dann automatisch.
--
-- Pfade liegen unter Interface\AddOns\VuloClassicUI\Media\
-- =========================================================
local _, ns = ...

local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
if not LSM then
    if ns.Print then
        ns:Print("|cffff5555LibSharedMedia-3.0 nicht gefunden, Media-Registry wird übersprungen.|r")
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

-- Zahlen 1-10 (mit rot-eingefärbtem Label)
for i = 1, 10 do
    local label = string.format("|cFFFF0000%d|r", i)
    -- Die Original-VuloMedia hatte für 10 "FE0000" statt "FF0000" — beibehalten
    if i == 10 then label = "|cFFFE000010|r" end
    LSM:Register("sound", label, SOUNDS .. tostring(i) .. ".ogg")
end

-- Raid-Marker-Icons 1-8 (mit Texture-Icon)
for i = 1, 8 do
    local label = string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:16|t", i)
    LSM:Register("sound", label, SOUNDS .. string.format("0%d.ogg", i))
end

-- Boss-Calls & generische Encounter-Sounds (rot eingefärbt)
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
-- Globale Konvenienz-Pointer für VCUI-Module
-- =========================================================
ns.LSM = LSM
