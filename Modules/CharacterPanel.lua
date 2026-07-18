-- =========================================================
-- VuloClassicUI / Modules / CharacterPanel (merged with _Impl)
-- AUTO-MERGED file. Each former module is wrapped in an isolated
-- IIFE so its file-level locals and any top-level early-return stay
-- self-contained. Modules communicate through the shared ns table.
-- =========================================================

-- ============================================================
-- merged from: CharacterPanel.lua
-- ============================================================
(function(...)
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
        style               = "classic",   -- "classic" (current look) | "modern" (built later)
        showItemLevel       = true,
        showSockets         = true,
        markEmptySockets    = true,
        shortenEnchants     = true,
        ringsEnchantable    = true,
        showAvgItemLevel    = true,
        itemLevelSize       = 11,
        textShadow          = true,
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
        { type = "header", text = L["Style"] },
        { type = "dropdown", label = L["Character panel style"], width = 240,
          tooltip = L["Classic+ is the current look. Modern is a new style we are still building; for now it shows the plain panel."],
          values = {
              { value = "classic", text = L["Classic+ (current)"] },
              { value = "modern",  text = L["Modern (in progress)"] },
          },
          get = function() return mod.db.style or "classic" end,
          set = function(_, v)
              mod.db.style = v
              refreshPanel()
          end },
        { type = "desc", text = L["The options below apply to the Classic+ style."] },

        { type = "spacer", height = 6 },
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
        { type = "checkbox", label = L["Mark empty sockets"],
          tooltip = L["Adds a red ring around item sockets that have no gem."],
          get = function() return mod.db.markEmptySockets end,
          set = function(_, v) mod.db.markEmptySockets = v; refreshPanel() end },
        { type = "checkbox", label = L["Text shadow (instead of outline)"],
          tooltip = L["Cleaner text with a drop shadow instead of a thick outline."],
          get = function() return mod.db.textShadow end,
          set = function(_, v)
              mod.db.textShadow = v
              if mod.restyleAllText then mod.restyleAllText() end
          end },
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

end)(...);

-- ============================================================
-- merged from: CharacterPanel_Impl.lua
-- ============================================================
(function(...)
-- =========================================================
-- VuloClassicUI / Modules / CharacterPanel_Impl
-- Ported from BetterCharacterPanel (TBC ANNIVERSARY).
-- Only works if the "characterpanel" module is enabled.
-- =========================================================
local _, ns = ...
local L = ns.L

-- Runs on BCC/Anniversary and Classic Era: the PaperDoll hooks
-- (PaperDollItemSlotButton_Update / InspectPaperDollItemSlotButton_Update) and the
-- slot frames exist on both. Sockets simply scan empty on Era (no gems in Vanilla),
-- and ring enchants (TBC+) are suppressed below. Other flavors are not supported.
if not (ns.isBCC or ns.isEra) then
    return
end

-- We wait for PLAYER_LOGIN so the module registry and DB are ready.
-- If the module is disabled, we return early.
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local mod = ns.modules and ns.modules.characterpanel
    if not mod or not ns:IsModuleEnabled("characterpanel") then
        return
    end
    -- Module is active -> the rest of this file runs as initialization
    if ns.RunCharacterPanelInit then
        ns:RunCharacterPanelInit()
    end
end)

-- The actual code is wrapped in a function so we can start it lazily.
function ns:RunCharacterPanelInit()
    if ns._characterPanelInitialised then return end
    ns._characterPanelInitialised = true

    -- "addon" is just an event handler collection in the original code.
    -- We rebuild it here locally.
    local addon = {}

    -- Read CharacterPanel module settings (the toggles on its options page).
    local cpMod = ns.modules and ns.modules.characterpanel
    local function cpOpt(key, default)
        local d = cpMod and cpMod.db
        if d and d[key] ~= nil then return d[key] end
        return default
    end
    -- Which look is selected: "classic" (the current Classic+ enhancements) or
    -- "modern" (the new style we build together later). Everything Classic+
    -- draws is gated on this, so picking "modern" leaves a clean slate.
    local function cpStyle() return cpOpt("style", "classic") end

-- =========================================================
-- Constants / Layout
-- =========================================================
local NUM_SOCKET_TEXTURES = 4

local ILVL_FONT_SIZE = 11
local ILVL_Y_OFFSET  = 4

-- Per-slot vertical nudges for the enchant text (positive = up, negative = down)
local WRIST_ENCH_Y   = -8   -- wrist enchant text a bit lower
local WEAPON_ENCH_Y  = 6    -- weapon enchant text a bit higher

local SOCKET_SIZE = 11
local SOCKET_GAP  = 2
local SOCKET_Y_GAP = -1

local buttonLayout = {
	[INVSLOT_HEAD]      = "left",
	[INVSLOT_NECK]      = "left",
	[INVSLOT_SHOULDER]  = "left",
	[INVSLOT_BACK]      = "left",
	[INVSLOT_CHEST]     = "left",
	[INVSLOT_WRIST]     = "left",

	[INVSLOT_HAND]      = "right",
	[INVSLOT_WAIST]     = "right",
	[INVSLOT_LEGS]      = "right",
	[INVSLOT_FEET]      = "right",
	[INVSLOT_FINGER1]   = "right",
	[INVSLOT_FINGER2]   = "right",
	[INVSLOT_TRINKET1]  = "right",
	[INVSLOT_TRINKET2]  = "right",

	[INVSLOT_MAINHAND]  = "center",
	[INVSLOT_OFFHAND]   = "center",
	[INVSLOT_RANGED]    = "center",
}

local ENABLE_AMMO = false
if ENABLE_AMMO and INVSLOT_AMMO then
	buttonLayout[INVSLOT_AMMO] = "right"
end

-- Ring enchanting only exists from TBC onward; on Classic Era never treat rings
-- as enchantable, otherwise every ring would falsely show the red "No Ench".
local RINGS_ENCH = cpOpt("ringsEnchantable", true) and not ns.isEra

local enchantableSlots = {
	[INVSLOT_HEAD] = true,
	[INVSLOT_SHOULDER] = true,
	[INVSLOT_BACK] = true,
	[INVSLOT_CHEST] = true,
	[INVSLOT_WRIST] = true,
	[INVSLOT_HAND] = true,
	[INVSLOT_LEGS] = true,
	[INVSLOT_FEET] = true,
	[INVSLOT_MAINHAND] = true,
	[INVSLOT_OFFHAND] = true,
	[INVSLOT_RANGED] = true,
}

if RINGS_ENCH then
	enchantableSlots[INVSLOT_FINGER1] = true
	enchantableSlots[INVSLOT_FINGER2] = true
end

local enchantReplacementTable = {
	-- English
	["Stamina"] = "Stam",
	["Intellect"] = "Int",
	["Agility"] = "Agi",
	["Strength"] = "Str",
	["Spirit"] = "Spi",

	["Defense"] = "Def",
	["Resilience"] = "Res",

	["Spell Critical Strike Rating"] = "Crit",
	["Spell Critical Strike"] = "Crit",
	["Spell Damage and Healing"] = "Spell",
	["Damage and Healing"] = "Spell",
	["Spell Damage"] = "Spell",
	["Spell Power"] = "Spell",
	["Healing"] = "Heal",

	["Critical Strike Rating"] = "Crit",
	["Critical Strike"] = "Crit",
	["Critical"] = "Crit",
	["Haste"] = "Haste",
	["Hit Rating"] = "Hit",
	["Attack Power"] = "AP",

	-- German
	["Ausdauer"] = "Ausd",
	["Intelligenz"] = "Int",
	["Beweglichkeit"] = "Bew",
	["Stärke"] = "Str",
	["Willenskraft"] = "Will",

	["Verteidigung"] = "Vert",
	["Abhärtung"] = "Abh",

	["Kritische Zaubertrefferwertung"] = "Crit",
	["kritische Zaubertrefferwertung"] = "Crit",
	["Zauberkritische Trefferwertung"] = "Crit",
	["zauberkritische Trefferwertung"] = "Crit",
	["kritische Trefferwertung"] = "Crit",
	["Zauberschaden und Heilung sowie Zaubertrefferwertung"] = "Spell Hit",
	["Zaubermacht und Zaubertrefferwertung"] = "Spell Hit",
	["Zauberschaden und Zaubertrefferwertung"] = "Spell Hit",
	["Zauberschaden und Heilung"] = "Spell",
	["Schaden und Heilung"] = "Spell",
	["Zauberschaden"] = "Spell",
	["Zaubermacht"] = "Spell",
	["Heilung"] = "Heal",

	["Kritische Trefferwertung"] = "Crit",
	["Kritischer Trefferwert"] = "Crit",
	["Kritischer"] = "Crit",
	["Kritische"] = "Crit",
	["Kritisch"] = "Crit",
	["Tempo"] = "Haste",
	["Zaubertrefferwertung"] = "Hit",
	["Trefferwertung"] = "Hit",
	["Angriffskraft"] = "AP",

	["Zauberdurchschlagskraft"] = "Spellpen",
	["Rüstungsdurchschlag"] = "ArP",
	["Waffenschaden"] = "Waff",
	["Schildblockwert"] = "Block",

	["Alle Werte"] = "Stats",
	["Mana alle 5 Sek."] = "MP5",
	["Mana pro 5 Sek."] = "MP5",
	["Manaregeneration"] = "MP5",

	-- Cleanup
	["Rating"] = "",
	[" und "] = " ",
	[" and "] = " ",
	["+"] = "",
}

-- Replacement order, precomputed once (longest key first). The table is static,
-- so there's no need to rebuild + sort it on every ProcessEnchantText call.
local enchantOrder = {}
for k in pairs(enchantReplacementTable) do enchantOrder[#enchantOrder + 1] = k end
table.sort(enchantOrder, function(a, b) return #a > #b end)

local function ProcessEnchantText(enchantText)
	if not enchantText then return enchantText end

	-- Only abbreviate when the "shorten enchant text" toggle is on
	if cpOpt("shortenEnchants", true) then
		for _, seek in ipairs(enchantOrder) do
			enchantText = enchantText:gsub((seek:gsub("(%W)", "%%%1")), enchantReplacementTable[seek])
		end
	end

	enchantText = enchantText:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return enchantText
end

-- =========================================================
-- Tooltip scanner
-- =========================================================
local scanningTooltip = CreateFrame("GameTooltip", "BCPScanningTooltip", nil, "GameTooltipTemplate")
scanningTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local function GetEnchantIdFromLink(itemLink)
	if not itemLink then return nil end

	local itemString = itemLink:match("item[%-?%d:]+")
	if not itemString then return nil end

	local _, _, enchantId = strsplit(":", itemString)

	if enchantId and enchantId ~= "" and enchantId ~= "0" then
		return enchantId
	end

	return nil
end

local function GetEquipLoc(itemLink)
	if not itemLink then return nil end

	if _G.GetItemInfoInstant then
		local _, _, _, equipLoc = GetItemInfoInstant(itemLink)
		return equipLoc
	end

	return select(9, GetItemInfo(itemLink))
end

local function GetItemLevelTBC(itemLink)
	if not itemLink then return nil end
	return select(4, GetItemInfo(itemLink))
end

local function GetWeaponSubClass(itemLink)
	if not itemLink then return nil, nil end
	if _G.GetItemInfoInstant then
		local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemLink)
		return classID, subClassID
	end
	local _, _, _, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfo(itemLink)
	return classID, subClassID
end

local function CanEnchantSlot(unit, slot)
	if not enchantableSlots[slot] then
		return false
	end

	if slot == INVSLOT_OFFHAND then
		local link = GetInventoryItemLink(unit, slot)
		if not link then return false end

		local equipLoc = GetEquipLoc(link)
		if equipLoc == "INVTYPE_HOLDABLE" then
			return false
		end
	end

	if slot == INVSLOT_RANGED then
		local link = GetInventoryItemLink(unit, slot)
		if not link then return false end

		-- Only bows (2), guns (3) and crossbows (18) can take a scope.
		-- Wands (19), thrown (16), relics etc. can't be enchanted, so don't
		-- nag with "No Ench" on them.
		local classID, subClassID = GetWeaponSubClass(link)
		if classID ~= 2 or not (subClassID == 2 or subClassID == 3 or subClassID == 18) then
			return false
		end
	end

	return true
end

local function GetItemEnchantAsText(unit, slot)
	local itemLink = GetInventoryItemLink(unit, slot)
	if not itemLink then return nil, nil end

	if not GetEnchantIdFromLink(itemLink) then
		return nil, nil
	end

	scanningTooltip:ClearLines()
	scanningTooltip:SetInventoryItem(unit, slot)

	for i = 2, scanningTooltip:NumLines() do
		local fs = _G["BCPScanningTooltipTextLeft" .. i]

		if fs and fs.GetText then
			local text = fs:GetText()

			if text and text ~= "" then
				local r, g, b = fs:GetTextColor()
				local isGreen = g and g > 0.9 and r < 0.2 and b < 0.2

				if isGreen
					and not text:find("^Equip:")
					and not text:find("^Benutzen:")
					and not text:find("^Use:")
					and not text:find("Socket Bonus:")
					and not text:find("Sockelbonus:")
					and not text:find("^Requires")
					and not text:find("^Benötigt")
				then
					return nil, ProcessEnchantText(text)
				end
			end
		end
	end

	return nil, nil
end

local function GetSocketTextures(unit, slot)
	scanningTooltip:ClearLines()
	scanningTooltip:SetInventoryItem(unit, slot)

	local textures = {}

	for i = 1, 10 do
		local tex = _G["BCPScanningTooltipTexture" .. i]

		if tex and tex:IsShown() then
			table.insert(textures, tex:GetTexture())
		end
	end

	return textures
end

-- =========================================================
-- Color helpers
-- =========================================================
local function ColorGradient(perc, ...)
	if perc >= 1 then
		local r, g, b = select(select("#", ...) - 2, ...)
		return r, g, b
	elseif perc <= 0 then
		local r, g, b = ...
		return r, g, b
	end

	local num = select("#", ...) / 3
	local segment, relperc = math.modf(perc * (num - 1))
	local r1, g1, b1, r2, g2, b2 = select((segment * 3) + 1, ...)

	return r1 + (r2 - r1) * relperc,
	       g1 + (g2 - g1) * relperc,
	       b1 + (b2 - b1) * relperc
end

local function ColorGradientHP(perc)
	return ColorGradient(perc, 1, 0, 0, 1, 1, 0, 0, 1, 0)
end

-- =========================================================
-- Quality border
-- =========================================================
local function EnsureQualityBorder(button)
	if button.IconBorder then
		return button.IconBorder, true
	end

	if button.BCPQualityBorder then
		return button.BCPQualityBorder, false
	end

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	border:SetBlendMode("ADD")
	border:SetAlpha(0.9)
	border:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
	border:Hide()

	button.BCPQualityBorder = border

	return border, false
end

local function UpdateQualityBorder(button, unit, slot, itemLink)
	local border, isBlizzardBorder = EnsureQualityBorder(button)

	if itemLink then
		local quality = GetInventoryItemQuality(unit, slot)

		if quality then
			local r, g, b = GetItemQualityColor(quality)
			border:SetVertexColor(r, g, b, 1)
			border:Show()

			if isBlizzardBorder and border.SetAlpha then
				border:SetAlpha(1)
			end

			return
		end
	end

	border:Hide()
end

-- =========================================================
-- UI
-- =========================================================
local function AnchorSocketsBelowCentered(ilvlFS, textures)
	local shown = 0

	for i = 1, NUM_SOCKET_TEXTURES do
		if textures[i] and textures[i]:IsShown() then
			shown = shown + 1
		end
	end

	if shown == 0 then return end

	local size = SOCKET_SIZE
	local gap = SOCKET_GAP
	local step = size + gap

	-- Total width of visible sockets + gaps between them
	local totalW = shown * size + (shown - 1) * gap
	-- StartX: left edge of the first socket relative to center, then to socket center
	local startX = -totalW / 2 + size / 2

	local idx = 0

	for i = 1, NUM_SOCKET_TEXTURES do
		local t = textures[i]
		t:ClearAllPoints()

		if t:IsShown() then
			-- Round to whole pixels so no subpixel offsets occur
			local x = math.floor(startX + idx * step + 0.5)
			t:SetPoint("TOP", ilvlFS, "BOTTOM", x, SOCKET_Y_GAP)
			idx = idx + 1
		end
	end
end

-- =========================================================
-- Text style (drop shadow vs. outline) + empty-socket helper
-- =========================================================
local function StyleText(fs, size)
	if not fs then return end
	if cpOpt("textShadow", true) then
		fs:SetFont(STANDARD_TEXT_FONT, size, "")
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
	else
		fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
		fs:SetShadowColor(0, 0, 0, 0)
		fs:SetShadowOffset(0, 0)
	end
end

-- Re-apply the current style to an existing font string, keeping its size.
local function RestyleText(fs)
	if not fs or not fs.GetFont then return end
	local file, size = fs:GetFont()
	if not file then return end
	if cpOpt("textShadow", true) then
		fs:SetFont(file, size, "")
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
	else
		fs:SetFont(file, size, "OUTLINE")
		fs:SetShadowColor(0, 0, 0, 0)
		fs:SetShadowOffset(0, 0)
	end
end

-- Live toggle: walk the slot displays and re-apply the text style.
function cpMod.restyleAllText()
	local pdi = _G.PaperDollItemsFrame
	if pdi and pdi.GetChildren then
		for _, child in ipairs({ pdi:GetChildren() }) do
			if child.ilvlDisplay    then RestyleText(child.ilvlDisplay)    end
			if child.enchantDisplay then RestyleText(child.enchantDisplay) end
		end
	end
end

-- Detect an empty gem socket via the item link's gem fields.
-- This is locale- AND fileID-independent: in 2.5.5 texture:GetTexture()
-- returns a numeric fileID (not a path), so matching the texture path does
-- not work. Socket display index i maps to the i-th gem field of the link
-- (item:itemID:enchant:gem1:gem2:gem3:gem4:...).
local function SocketIsEmpty(itemLink, index)
	if not itemLink or not index then return false end
	local itemString = itemLink:match("item[%-?%d:]+")
	if not itemString then return false end
	local gemID = select(3 + index, strsplit(":", itemString))
	return gemID == nil or gemID == "" or gemID == "0"
end

local function CreateAdditionalDisplayForButton(button)
	local parent = button:GetParent()
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(100)

	f.ilvlDisplay = f:CreateFontString(nil, "OVERLAY")
	StyleText(f.ilvlDisplay, ILVL_FONT_SIZE)
	f.ilvlDisplay:SetJustifyH("CENTER")
	f.ilvlDisplay:SetJustifyV("MIDDLE")

	f.enchantDisplay = f:CreateFontString(nil, "OVERLAY")
	StyleText(f.enchantDisplay, 9)
	f.enchantDisplay:SetTextColor(0, 1, 0, 1)

	f.durabilityDisplay = CreateFrame("StatusBar", nil, f)
	f.durabilityDisplay:SetMinMaxValues(0, 1)
	f.durabilityDisplay:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
	f.durabilityDisplay:GetStatusBarTexture():SetHorizTile(false)
	f.durabilityDisplay:GetStatusBarTexture():SetVertTile(false)
	f.durabilityDisplay:SetHeight(40)
	f.durabilityDisplay:SetWidth(2.3)
	f.durabilityDisplay:SetOrientation("VERTICAL")

	f.socketDisplay = {}
	f.socketRing = {}

	for i = 1, NUM_SOCKET_TEXTURES do
		f.socketDisplay[i] = f:CreateTexture(nil, "OVERLAY")
		f.socketDisplay[i]:SetWidth(SOCKET_SIZE)
		f.socketDisplay[i]:SetHeight(SOCKET_SIZE)

		-- Red glow ring shown around empty (ungemmed) sockets
		f.socketRing[i] = f:CreateTexture(nil, "ARTWORK")
		f.socketRing[i]:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		f.socketRing[i]:SetBlendMode("ADD")
		f.socketRing[i]:SetVertexColor(1, 0.1, 0.1, 1)
		f.socketRing[i]:SetPoint("TOPLEFT", f.socketDisplay[i], "TOPLEFT", -4, 4)
		f.socketRing[i]:SetPoint("BOTTOMRIGHT", f.socketDisplay[i], "BOTTOMRIGHT", 4, -4)
		f.socketRing[i]:Hide()
	end

	return f
end

local function positionLeft(button)
	local f = button.BCPDisplay

	f:SetPoint("TOPLEFT", button, "TOPRIGHT")
	f:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT")

	f.ilvlDisplay:ClearAllPoints()
	f.ilvlDisplay:SetPoint("CENTER", button, "CENTER", 0, ILVL_Y_OFFSET)

	f.enchantDisplay:ClearAllPoints()
	local enchY = -7
	if button:GetID() == INVSLOT_WRIST then
		enchY = enchY + WRIST_ENCH_Y
	end
	f.enchantDisplay:SetPoint("TOPLEFT", f, "TOPLEFT", 10, enchY)

	f.durabilityDisplay:ClearAllPoints()
	f.durabilityDisplay:SetWidth(2.3)
	f.durabilityDisplay:SetHeight(40)
	f.durabilityDisplay:SetOrientation("VERTICAL")
	f.durabilityDisplay:SetPoint("TOPLEFT", button, "TOPLEFT", -6, 0)
	f.durabilityDisplay:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -6, 0)
end

local function positionRight(button)
	local f = button.BCPDisplay

	f:SetPoint("TOPRIGHT", button, "TOPLEFT")
	f:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT")

	f.ilvlDisplay:ClearAllPoints()
	f.ilvlDisplay:SetPoint("CENTER", button, "CENTER", 0, ILVL_Y_OFFSET)

	f.enchantDisplay:ClearAllPoints()
	f.enchantDisplay:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -7)

	f.durabilityDisplay:ClearAllPoints()
	f.durabilityDisplay:SetWidth(1.2)
	f.durabilityDisplay:SetHeight(40)
	f.durabilityDisplay:SetOrientation("VERTICAL")
	f.durabilityDisplay:SetPoint("TOPRIGHT", button, "TOPRIGHT", 4, 0)
	f.durabilityDisplay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, 0)
end

local function positionCenter(button)
	local f = button.BCPDisplay

	f:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -100, 0)
	f:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, -100)

	f.durabilityDisplay:ClearAllPoints()
	f.durabilityDisplay:SetHeight(2)
	f.durabilityDisplay:SetWidth(40)
	f.durabilityDisplay:SetOrientation("HORIZONTAL")
	f.durabilityDisplay:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, -2)
	f.durabilityDisplay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, -2)

	f.ilvlDisplay:ClearAllPoints()
	f.ilvlDisplay:SetPoint("CENTER", button, "CENTER", 0, ILVL_Y_OFFSET)

	f.enchantDisplay:ClearAllPoints()

	if button:GetID() == INVSLOT_MAINHAND then
		f.enchantDisplay:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", -5, WEAPON_ENCH_Y)
	else
		f.enchantDisplay:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 5, WEAPON_ENCH_Y)
	end
end

local function AnchorAdditionalDisplay(button)
	local layout = buttonLayout[button:GetID()]

	if layout == "left" then
		positionLeft(button)
	elseif layout == "right" then
		positionRight(button)
	elseif layout == "center" then
		positionCenter(button)
	end
end

-- =========================================================
-- Update logic
-- =========================================================
local function UpdateAdditionalDisplay(button, unit)
	local f = button.BCPDisplay
	if not f then return end

	local slot = button:GetID()
	local itemLink = GetInventoryItemLink(unit, slot)

	if f.prevItemLink ~= itemLink then
		local itemiLvlText = ""

		if itemLink then
			local ilvl = GetItemLevelTBC(itemLink)

			if ilvl then
				local quality = GetInventoryItemQuality(unit, slot)

				if quality then
					local _, _, _, hex = GetItemQualityColor(quality)
					itemiLvlText = "|c" .. hex .. ilvl .. "|r"
				else
					itemiLvlText = tostring(ilvl)
				end
			else
				C_Timer.After(0.1, function()
					if button and button.BCPDisplay and GetInventoryItemLink(unit, slot) == itemLink then
						UpdateAdditionalDisplay(button, unit)
					end
				end)
			end
		end

		-- "Show item level per slot" toggle
		if not cpOpt("showItemLevel", true) then itemiLvlText = "" end
		f.ilvlDisplay:SetText(itemiLvlText)

		UpdateQualityBorder(button, unit, slot, itemLink)

		local _, enchantText

		if itemLink then
			_, enchantText = GetItemEnchantAsText(unit, slot)
		end

		local canEnchant = CanEnchantSlot(unit, slot)

		if not enchantText then
			f.enchantDisplay:SetText((canEnchant and itemLink) and L["|cffff0000No Ench|r"] or "")
		else
			local maxSize = 18

			if enchantText:find("|c") then
				maxSize = maxSize + 12
			end

			enchantText = string.sub(enchantText, 1, maxSize)
			f.enchantDisplay:SetText(enchantText)
		end

		-- Socket display honours the "Show sockets" toggle
		local textures = (cpOpt("showSockets", true) and itemLink and GetSocketTextures(unit, slot)) or {}

		for i = 1, NUM_SOCKET_TEXTURES do
			local t = f.socketDisplay[i]
			local ring = f.socketRing[i]

			if textures[i] then
				t:SetTexture(textures[i])
				t:SetVertexColor(1, 1, 1)
				t:Show()
				if cpOpt("markEmptySockets", true) and SocketIsEmpty(itemLink, i) then
					ring:Show()
				else
					ring:Hide()
				end
			else
				t:Hide()
				if ring then ring:Hide() end
			end
		end

		AnchorSocketsBelowCentered(f.ilvlDisplay, f.socketDisplay)

		f.prevItemLink = itemLink
	end

	local cur, max = GetInventoryItemDurability(slot)
	local perc = cur and max and max > 0 and cur / max or nil

	if f.prevDurability ~= perc then
		if UnitIsUnit("player", unit) and perc and perc < 1 then
			f.durabilityDisplay:Show()
			f.durabilityDisplay:SetValue(perc)
			f.durabilityDisplay:SetStatusBarColor(ColorGradientHP(perc))
		else
			f.durabilityDisplay:Hide()
		end

		f.prevDurability = perc
	end
end

local function UpdateButton(button, unit)
	if not button or not button.GetID then return end

	local slot = button:GetID()
	if not buttonLayout[slot] then return end

	-- Both styles keep the per-slot item level (the Modern look shows it too);
	-- Modern only adds the stats panel and hides the small average readout.
	if not button.BCPDisplay then
		button.BCPDisplay = CreateAdditionalDisplayForButton(button)
		AnchorAdditionalDisplay(button)
	end

	UpdateAdditionalDisplay(button, unit)
end

hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
	UpdateButton(button, "player")
end)

-- =========================================================
-- Avg iLvL
-- =========================================================
local inspectSlots = {
	INVSLOT_HEAD,
	INVSLOT_NECK,
	INVSLOT_SHOULDER,
	INVSLOT_BACK,
	INVSLOT_CHEST,
	INVSLOT_WRIST,
	INVSLOT_HAND,
	INVSLOT_WAIST,
	INVSLOT_LEGS,
	INVSLOT_FEET,
	INVSLOT_FINGER1,
	INVSLOT_FINGER2,
	INVSLOT_TRINKET1,
	INVSLOT_TRINKET2,
	INVSLOT_MAINHAND,
	INVSLOT_OFFHAND,
	INVSLOT_RANGED,
}

local function GetUnitAverageItemLevelTBC(unit)
	local total, count = 0, 0

	for _, slot in ipairs(inspectSlots) do
		local link = GetInventoryItemLink(unit, slot)

		if link then
			local ilvl = GetItemLevelTBC(link)

			if ilvl then
				total = total + ilvl
				count = count + 1
			end
		end
	end

	if count == 0 then return 0 end

	return math.floor((total / count) + 0.5)
end

local function GetUnitAverageItemQualityTBC(unit)
	local total, count = 0, 0

	for _, slot in ipairs(inspectSlots) do
		local quality = GetInventoryItemQuality(unit, slot)

		if quality then
			total = total + quality
			count = count + 1
		end
	end

	if count == 0 then return 1 end

	return math.floor((total / count) + 0.5)
end

local function CreatePlayerAvgIlvlDisplay()
	if not PaperDollFrame or PaperDollFrame.avgIlvlDisplay then return end

	local anchor = _G.CharacterHandsSlot or CharacterLevelText
	if not anchor then return end

	local fs = PaperDollFrame:CreateFontString(nil, "OVERLAY")
	fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	fs:SetJustifyH("CENTER")
	fs:SetJustifyV("MIDDLE")
	fs:SetText("")

	-- Centered above the hands slot
	fs:SetPoint("BOTTOM", anchor, "TOP", -8, 9)

	PaperDollFrame.avgIlvlDisplay = fs
end

local function UpdatePlayerAvgIlvlDisplay()
	if not CharacterFrame or not CharacterFrame:IsShown() then return end

	CreatePlayerAvgIlvlDisplay()

	if not PaperDollFrame or not PaperDollFrame.avgIlvlDisplay then return end

	-- Modern style suppresses the Classic+ average readout too
	if cpStyle() ~= "classic" then
		PaperDollFrame.avgIlvlDisplay:SetText("")
		return
	end

	-- "Show average item level" toggle — hide the display when off
	if not cpOpt("showAvgItemLevel", true) then
		PaperDollFrame.avgIlvlDisplay:SetText("")
		return
	end

	local ilvl = GetUnitAverageItemLevelTBC("player")
	local avgQuality = GetUnitAverageItemQualityTBC("player")

	local _, _, _, hex = GetItemQualityColor(avgQuality)
	local colorHex = hex or "ffffffff"

	PaperDollFrame.avgIlvlDisplay:SetText(string.format(L["|c%siLvL - %d|r"], colorHex, ilvl))
end

-- =========================================================
-- Inspect
-- =========================================================
local function CreateInspectIlvlDisplay()
	if not InspectPaperDollItemsFrame or InspectPaperDollItemsFrame.ilvlDisplay then return end

	local parent = InspectPaperDollItemsFrame

	parent.ilvlDisplay = parent:CreateFontString(nil, "OVERLAY")
	parent.ilvlDisplay:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	parent.ilvlDisplay:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -20)
	parent.ilvlDisplay:SetPoint("BOTTOMLEFT", parent, "TOPRIGHT", -80, -67)
end

local function UpdateInspectIlvlDisplayTBC(unit)
	if not unit or not UnitExists(unit) then return end
	if not InspectPaperDollItemsFrame or not InspectPaperDollItemsFrame.ilvlDisplay then return end

	local ilvl = GetUnitAverageItemLevelTBC(unit)
	InspectPaperDollItemsFrame.ilvlDisplay:SetText(string.format("|cffffffff%d|r", ilvl))
end

local inspectSlotButtons = {
	"InspectHeadSlot",
	"InspectNeckSlot",
	"InspectShoulderSlot",
	"InspectBackSlot",
	"InspectChestSlot",
	"InspectWristSlot",
	"InspectHandsSlot",
	"InspectWaistSlot",
	"InspectLegsSlot",
	"InspectFeetSlot",
	"InspectFinger0Slot",
	"InspectFinger1Slot",
	"InspectTrinket0Slot",
	"InspectTrinket1Slot",
	"InspectMainHandSlot",
	"InspectSecondaryHandSlot",
	"InspectRangedSlot",
}

local function UpdateAllInspectSlots()
	if not InspectFrame or not InspectFrame.unit then return end

	local unit = InspectFrame.unit

	for _, name in ipairs(inspectSlotButtons) do
		local button = _G[name]

		if button and button.GetID then
			UpdateButton(button, unit)
		end
	end
end

-- =========================================================
-- Player bulk update
-- =========================================================
local characterSlots = {
	"CharacterHeadSlot",
	"CharacterNeckSlot",
	"CharacterShoulderSlot",
	"CharacterChestSlot",
	"CharacterWaistSlot",
	"CharacterLegsSlot",
	"CharacterFeetSlot",
	"CharacterWristSlot",
	"CharacterHandsSlot",
	"CharacterFinger0Slot",
	"CharacterFinger1Slot",
	"CharacterTrinket0Slot",
	"CharacterTrinket1Slot",
	"CharacterBackSlot",
	"CharacterMainHandSlot",
	"CharacterSecondaryHandSlot",
	"CharacterRangedSlot",
}

local function UpdateAllCharacterSlots()
	for _, name in ipairs(characterSlots) do
		local button = _G[name]

		if button and button.GetID then
			UpdateButton(button, "player")
		end
	end
end

-- =========================================================
-- Modern style: a dark stats panel docked to the right of the character
-- frame (big equipped item level + collapsible stat categories). Reads only
-- non-protected player APIs and lives in its own frame parented to
-- CharacterFrame, so nothing here taints the secure paper doll. Retail-only
-- stats (mastery, versatility, tertiary, ratings on Era) are simply not built.
-- =========================================================
local modernPanel

-- safe numeric read: a missing API or bad return never errors the panel
local function num(fn)
	local ok, v = pcall(fn)
	if ok and type(v) == "number" then return v end
	return 0
end

local function maxSpellPower()
	if not GetSpellBonusDamage then return 0 end
	local m = 0
	for s = 2, 7 do local v = GetSpellBonusDamage(s) or 0; if v > m then m = v end end
	return m
end

local function maxSpellCrit()
	if not GetSpellCritChance then return 0 end
	local m = 0
	for s = 2, 7 do local v = GetSpellCritChance(s) or 0; if v > m then m = v end end
	return m
end

-- The stat table, adapted to the running client. TBC (2.5.x) has the combat
-- rating model (haste/hit/spell hit); Classic Era / SoD do not, so those rows
-- are only added on BCC.
-- spell schools 2..7 (Holy/Fire/Nature/Frost/Shadow/Arcane), matching the
-- Blizzard paper doll. Used for the hover breakdowns on Spell Power / Crit.
local SCHOOL_NAMES
local function schoolNames()
	if not SCHOOL_NAMES then
		SCHOOL_NAMES = { [2] = L["Holy"], [3] = L["Fire"], [4] = L["Nature"],
		                 [5] = L["Frost"], [6] = L["Shadow"], [7] = L["Arcane"] }
	end
	return SCHOOL_NAMES
end
local function spellPowerTip(tt)
	if not GetSpellBonusDamage then return end
	local n = schoolNames()
	for i = 2, 7 do
		tt:AddDoubleLine(n[i], tostring(GetSpellBonusDamage(i) or 0), 0.8, 0.8, 0.85, 1, 1, 1)
	end
end
local function spellCritTip(tt)
	if not GetSpellCritChance then return end
	local n = schoolNames()
	for i = 2, 7 do
		tt:AddDoubleLine(n[i], string.format("%.2f%%", GetSpellCritChance(i) or 0), 0.8, 0.8, 0.85, 1, 1, 1)
	end
end

local function buildModernSections()
	local S = {}
	local function sec(key, title) local t = { key = key, title = title, rows = {} }; S[#S+1] = t; return t end
	local function row(t, name, get, fmt, tip) t.rows[#t.rows+1] = { name = name, get = get, fmt = fmt, tip = tip } end

	local attr = sec("attributes", L["Attributes"])
	row(attr, L["Strength"],  function() return select(2, UnitStat("player", 1)) end)
	row(attr, L["Agility"],   function() return select(2, UnitStat("player", 2)) end)
	row(attr, L["Stamina"],   function() return select(2, UnitStat("player", 3)) end)
	row(attr, L["Intellect"], function() return select(2, UnitStat("player", 4)) end)
	row(attr, L["Spirit"],    function() return select(2, UnitStat("player", 5)) end)
	row(attr, L["Health"],    function() return UnitHealthMax("player") end)

	local melee = sec("melee", L["Melee"])
	row(melee, L["Attack Power"], function() local b, p, n = UnitAttackPower("player"); return (b or 0) + (p or 0) + (n or 0) end)
	row(melee, L["Crit"], function() return GetCritChance and GetCritChance() or 0 end, "%.2f%%")
	if ns.isBCC and GetCombatRatingBonus and _G.CR_HASTE_MELEE then
		row(melee, L["Haste"], function() return GetCombatRatingBonus(CR_HASTE_MELEE) end, "%.2f%%")
	end
	if ns.isBCC and GetCombatRating and _G.CR_HIT_MELEE then
		row(melee, L["Hit"], function() return GetCombatRating(CR_HIT_MELEE) end)
	end

	local spell = sec("spell", L["Spell"])
	row(spell, L["Spell Power"], maxSpellPower, nil, spellPowerTip)
	row(spell, L["Healing"], function() return GetSpellBonusHealing and GetSpellBonusHealing() or 0 end)
	row(spell, L["Spell Crit"], maxSpellCrit, "%.2f%%", spellCritTip)
	if ns.isBCC and GetCombatRating and _G.CR_HIT_SPELL then
		row(spell, L["Spell Hit"], function() return GetCombatRating(CR_HIT_SPELL) end)
	end

	local def = sec("defense", L["Defense"])
	row(def, L["Armor"], function() return select(2, UnitArmor("player")) end)
	if UnitDefense then
		row(def, L["Defense"], function() local b, m = UnitDefense("player"); return (b or 0) + (m or 0) end)
	end
	row(def, L["Dodge"], function() return GetDodgeChance and GetDodgeChance() or 0 end, "%.2f%%")
	row(def, L["Parry"], function() return GetParryChance and GetParryChance() or 0 end, "%.2f%%")
	row(def, L["Block"], function() return GetBlockChance and GetBlockChance() or 0 end, "%.2f%%")

	-- Resistances live here on the right now (the Blizzard icons on the paper
	-- doll are hidden under Modern). UnitResistance index: 6 Arcane, 2 Fire,
	-- 3 Nature, 4 Frost, 5 Shadow.
	local res = sec("resistances", L["Resistances"])
	row(res, L["Arcane"], function() return select(2, UnitResistance("player", 6)) end)
	row(res, L["Fire"],   function() return select(2, UnitResistance("player", 2)) end)
	row(res, L["Nature"], function() return select(2, UnitResistance("player", 3)) end)
	row(res, L["Frost"],  function() return select(2, UnitResistance("player", 4)) end)
	row(res, L["Shadow"], function() return select(2, UnitResistance("player", 5)) end)

	return S
end

local function layoutModern()
	local p = modernPanel
	if not (p and p.content) then return end
	local c = p.content
	local collapsed = (cpMod and cpMod.db and cpMod.db.modernCollapsed) or {}
	local y = -4
	for _, s in ipairs(p.secObjs) do
		s.header:ClearAllPoints()
		s.header:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y)
		local isCol = collapsed[s.key]
		s.arrow:SetText(isCol and "+" or "-")
		y = y - 20
		for _, r in ipairs(s.rows) do
			if isCol then
				r.name:Hide(); r.value:Hide(); r.hover:Hide()
			else
				r.name:Show(); r.value:Show(); r.hover:Show()
				r.name:ClearAllPoints();  r.name:SetPoint("TOPLEFT",  c, "TOPLEFT",  10, y)
				r.value:ClearAllPoints(); r.value:SetPoint("TOPRIGHT", c, "TOPRIGHT", -8, y)
				r.hover:ClearAllPoints()
				-- both points on the TOP edge only, so the fixed SetHeight(15)
				-- is honored (a second vertical constraint would override it)
				r.hover:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y + 2)
				r.hover:SetPoint("TOPRIGHT", c, "TOPRIGHT", -4, y + 2)
				y = y - 15
			end
		end
		y = y - 8
	end
	c:SetHeight(math.max(10, -y + 6))
	-- keep the scroll position valid after a collapse shrinks the content
	local range = math.max(0, c:GetHeight() - (p.scroll:GetHeight() or 0))
	if p.scroll:GetVerticalScroll() > range then p.scroll:SetVerticalScroll(range) end
end

local function updateModernValues()
	local p = modernPanel
	if not p then return end
	if p.ilvl then p.ilvl:SetText(tostring(GetUnitAverageItemLevelTBC("player"))) end
	for _, s in ipairs(p.secObjs) do
		for _, r in ipairs(s.rows) do
			local v = num(r.get)
			if r.fmt then
				r.value:SetText(string.format(r.fmt, v))
			else
				r.value:SetText(tostring(math.floor(v + 0.5)))
			end
		end
	end
end

-- =========================================================
-- "One window" chrome: instead of a separate floating panel, we hide the
-- Blizzard tan window art + built-in stats and lay ONE dark rectangle (a
-- texture on CharacterFrame's BACKGROUND, so it sits behind every child:
-- model, slots, name, tabs) that extends to the RIGHT to also back the stats.
-- The stats panel itself is transparent. Everything is reversible so the
-- Classic+ style restores Blizzard's frame live. Offsets are first-pass and
-- meant to be nudged after seeing it in-game.
-- =========================================================
local modernChrome
-- how far the dark rectangle reaches to the right of the frame (holds the stats)
local MODERN_RIGHT_EXT = 172

-- Exposed: how far the Modern style extends the character window to the right,
-- plus its top/bottom edge offsets — so frames docked right of the window (the
-- loadouts sidebar) can shift over and match the Modern chrome's height.
ns.CharacterPanelModernExt = function()
    -- 4th return: is the Modern style active at all (its window edges apply on
    -- EVERY tab). The right extension itself only exists while the paperdoll
    -- tab shows the stats panel.
    if cpMod and cpMod.active and cpStyle() == "modern" then
        local ext = (_G.PaperDollFrame and _G.PaperDollFrame:IsShown()) and MODERN_RIGHT_EXT or 0
        return ext, -6, 72, true
    end
    return 0, 0, 0, false
end

local function ensureModernChrome()
	if modernChrome then return modernChrome.bg end
	if not CharacterFrame then return nil end
	local bgc = ns.COLORS.bg
	local bd  = ns.COLORS.accentDim or ns.COLORS.border
	modernChrome = { hidden = {}, edges = {} }

	local bg = CharacterFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetColorTexture(bgc.r, bgc.g, bgc.b, 0.97)
	bg:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 7, -6)
	bg:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", MODERN_RIGHT_EXT, 72)
	bg:Hide()
	modernChrome.bg = bg

	for i = 1, 4 do
		local t = CharacterFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
		t:SetColorTexture(bd.r, bd.g, bd.b, 0.9)
		t:Hide()
		modernChrome.edges[i] = t
	end
	local e = modernChrome.edges
	e[1]:SetPoint("TOPLEFT", bg, "TOPLEFT");     e[1]:SetPoint("TOPRIGHT", bg, "TOPRIGHT");     e[1]:SetHeight(1)
	e[2]:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT"); e[2]:SetHeight(1)
	e[3]:SetPoint("TOPLEFT", bg, "TOPLEFT");     e[3]:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT");   e[3]:SetWidth(1)
	e[4]:SetPoint("TOPRIGHT", bg, "TOPRIGHT");   e[4]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT"); e[4]:SetWidth(1)

	-- Blizzard chrome to hide under Modern
	local h = modernChrome.hidden
	if _G.CharacterFramePortrait then h[#h + 1] = _G.CharacterFramePortrait end
	if _G.PaperDollFrame then
		-- the tan window backdrop is the 4 BORDER-layer textures on PaperDollFrame
		for _, r in ipairs({ _G.PaperDollFrame:GetRegions() }) do
			if r.IsObjectType and r:IsObjectType("Texture")
			   and r.GetDrawLayer and r:GetDrawLayer() == "BORDER" then
				h[#h + 1] = r
			end
		end
	end
	-- Blizzard's built-in attribute/stat block (our panel replaces it)
	local attr = _G.CharacterAttributesFrame or (_G.PaperDollFrame and _G.PaperDollFrame.Attributes)
	if attr then h[#h + 1] = attr end
	-- the 5 magic-resistance icons are a SEPARATE frame; hide them too (their
	-- values now live in the panel's Resistances category)
	if _G.CharacterResistanceFrame then h[#h + 1] = _G.CharacterResistanceFrame end
	-- the two model-rotate arrows
	if _G.CharacterModelFrameRotateLeftButton  then h[#h + 1] = _G.CharacterModelFrameRotateLeftButton  end
	if _G.CharacterModelFrameRotateRightButton then h[#h + 1] = _G.CharacterModelFrameRotateRightButton end

	return bg
end

local function applyModernChrome(on)
	ensureModernChrome()
	if not modernChrome then return end
	for _, r in ipairs(modernChrome.hidden) do
		if on then if r.Hide then r:Hide() end else if r.Show then r:Show() end end
	end
	if on then
		modernChrome.bg:Show()
		for _, t in ipairs(modernChrome.edges) do t:Show() end
	else
		modernChrome.bg:Hide()
		for _, t in ipairs(modernChrome.edges) do t:Hide() end
	end
end

-- The other character sub-tabs (Reputation / Skills / PvP / Honor) each carry
-- their own tan window chrome. Under Modern we hide that chrome (the BACKGROUND
-- and BORDER direct textures — content lives in child frames / ARTWORK, which
-- we leave alone) and lay a dark panel + accent border on each, parented to the
-- pane so it shows and hides with its tab automatically. Fully reversible.
local modernPanes

local function ensureModernPanes()
	if modernPanes then return modernPanes end
	modernPanes = {}
	local bgc = ns.COLORS.bg
	local bd  = ns.COLORS.accentDim or ns.COLORS.border
	for _, name in ipairs({ "ReputationFrame", "SkillFrame", "PVPFrame" }) do
		local f = _G[name]
		if f and f.CreateTexture and f.GetRegions then
			local rec = { hidden = {}, edges = {} }
			-- collect the existing tan chrome FIRST, before we add our own
			-- textures (so our bg/edges are never swept into the hide list)
			for _, r in ipairs({ f:GetRegions() }) do
				if r.IsObjectType and r:IsObjectType("Texture") and r.GetDrawLayer then
					local dl = r:GetDrawLayer()
					if dl == "BACKGROUND" or dl == "BORDER" then
						rec.hidden[#rec.hidden + 1] = r
					end
				end
			end
			local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
			bg:SetColorTexture(bgc.r, bgc.g, bgc.b, 0.97)
			bg:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -6)
			bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 72)
			bg:Hide()
			rec.bg = bg
			for i = 1, 4 do
				local t = f:CreateTexture(nil, "BACKGROUND", nil, -7)
				t:SetColorTexture(bd.r, bd.g, bd.b, 0.9)
				t:Hide()
				rec.edges[i] = t
			end
			local e = rec.edges
			e[1]:SetPoint("TOPLEFT", bg, "TOPLEFT");       e[1]:SetPoint("TOPRIGHT", bg, "TOPRIGHT");       e[1]:SetHeight(1)
			e[2]:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT"); e[2]:SetHeight(1)
			e[3]:SetPoint("TOPLEFT", bg, "TOPLEFT");       e[3]:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT");   e[3]:SetWidth(1)
			e[4]:SetPoint("TOPRIGHT", bg, "TOPRIGHT");     e[4]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT"); e[4]:SetWidth(1)
			modernPanes[#modernPanes + 1] = rec
		end
	end
	return modernPanes
end

local function applyModernPanes(on)
	if not on and not modernPanes then return end   -- nothing built yet, nothing to restore
	ensureModernPanes()
	for _, rec in ipairs(modernPanes) do
		for _, r in ipairs(rec.hidden) do
			if on then if r.Hide then r:Hide() end else if r.Show then r:Show() end end
		end
		if on then
			rec.bg:Show()
			for _, t in ipairs(rec.edges) do t:Show() end
		else
			rec.bg:Hide()
			for _, t in ipairs(rec.edges) do t:Hide() end
		end
	end
end

-- The bottom tabs (Character / Pet / Reputation / Skills / PvP) carry tan tab
-- art. Under Modern we hide that art (all their Texture regions; the label
-- FontString stays), put a dark strip behind each label and an accent
-- underline on the active tab. Reversible; the original label colors are kept.
local modernTabs

local function tabSelectedId()
	if CharacterFrame and CharacterFrame.selectedTab then return CharacterFrame.selectedTab end
	if PanelTemplates_GetSelectedTab then
		local ok, id = pcall(PanelTemplates_GetSelectedTab, CharacterFrame)
		if ok and id then return id end
	end
	return 1
end

-- re-hide the art (Blizzard re-styles a tab on click) and move the underline
local function layoutModernTabs()
	if not modernTabs or cpStyle() ~= "modern" then return end
	local sel = tabSelectedId()
	for _, rec in ipairs(modernTabs) do
		for _, r in ipairs(rec.hidden) do if r.Hide then r:Hide() end end
		if rec.id == sel then rec.underline:Show() else rec.underline:Hide() end
	end
end

local function ensureModernTabs()
	if modernTabs then return modernTabs end
	modernTabs = {}
	local ac  = ns.COLORS.accent
	local bgc = ns.COLORS.bg
	for i = 1, 5 do
		local tab = _G["CharacterFrameTab" .. i]
		if tab and tab.CreateTexture and tab.GetRegions then
			local rec = { id = i, hidden = {} }
			for _, r in ipairs({ tab:GetRegions() }) do
				if r.IsObjectType and r:IsObjectType("Texture") then
					rec.hidden[#rec.hidden + 1] = r
				end
			end
			local bg = tab:CreateTexture(nil, "BACKGROUND", nil, -2)
			bg:SetColorTexture(bgc.r, bgc.g, bgc.b, 0.95)
			bg:SetPoint("TOPLEFT", tab, "TOPLEFT", 4, -6)
			bg:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -4, 8)
			bg:Hide()
			rec.bg = bg
			local ul = tab:CreateTexture(nil, "ARTWORK")
			ul:SetColorTexture(ac.r, ac.g, ac.b, 0.9)
			ul:SetHeight(2)
			ul:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 2, 1)
			ul:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -2, 1)
			ul:Hide()
			rec.underline = ul
			rec.label = _G["CharacterFrameTab" .. i .. "Text"] or tab.Text
				or (tab.GetFontString and tab:GetFontString())
			if rec.label and rec.label.GetTextColor then
				rec.oR, rec.oG, rec.oB = rec.label:GetTextColor()
			end
			tab:HookScript("OnClick", function() layoutModernTabs() end)
			modernTabs[#modernTabs + 1] = rec
		end
	end
	return modernTabs
end

local function applyModernTabs(on)
	if not on and not modernTabs then return end
	ensureModernTabs()
	for _, rec in ipairs(modernTabs) do
		for _, r in ipairs(rec.hidden) do
			if on then if r.Hide then r:Hide() end else if r.Show then r:Show() end end
		end
		if on then
			rec.bg:Show()
			if rec.label and rec.label.SetTextColor then rec.label:SetTextColor(0.9, 0.9, 0.95) end
		else
			rec.bg:Hide()
			rec.underline:Hide()
			if rec.label and rec.label.SetTextColor then
				rec.label:SetTextColor(rec.oR or 1, rec.oG or 0.82, rec.oB or 0)
			end
		end
	end
	if on then layoutModernTabs() end
end

local function ensureModernPanel()
	if modernPanel then return modernPanel end
	if not CharacterFrame then return nil end
	local bg = ensureModernChrome()
	local UI = ns.UI
	local ac = ns.COLORS.accent
	local function font(fs, size, fallback)
		if UI and UI.FONT_PATH then fs:SetFont(UI.FONT_PATH, size, "") else fs:SetFontObject(fallback) end
	end

	local p = CreateFrame("Frame", "VCUI_ModernCharStats", CharacterFrame)
	p:SetWidth(188)
	-- transparent panel filling the right part of the shared dark rectangle
	if bg then
		p:SetPoint("TOPRIGHT", bg, "TOPRIGHT", -6, -6)
		p:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -6, 6)
	else
		p:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 6, -8)
		p:SetHeight(420)
	end
	p:SetFrameStrata(CharacterFrame:GetFrameStrata())
	p:SetFrameLevel((CharacterFrame:GetFrameLevel() or 0) + 6)

	-- fixed header: caption + big item level (does not scroll)
	local cap = p:CreateFontString(nil, "OVERLAY")
	font(cap, 10, "GameFontNormalSmall")
	cap:SetPoint("TOP", p, "TOP", 0, -8)
	cap:SetText(L["Item Level"])
	cap:SetTextColor(0.6, 0.6, 0.66)

	local il = p:CreateFontString(nil, "OVERLAY")
	font(il, 22, "GameFontNormalHuge")
	il:SetPoint("TOP", cap, "BOTTOM", 0, -1)
	il:SetTextColor(ac.r, ac.g, ac.b)
	p.ilvl = il

	-- scrollable body below the item level
	local scroll = CreateFrame("ScrollFrame", nil, p)
	scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -50)
	scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 6)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = math.max(0, (p.content:GetHeight() or 0) - (self:GetHeight() or 0))
		local nv = math.min(range, math.max(0, self:GetVerticalScroll() - delta * 24))
		self:SetVerticalScroll(nv)
	end)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(184, 400)
	scroll:SetScrollChild(content)
	p.scroll = scroll
	p.content = content

	p.secObjs = {}
	for _, s in ipairs(buildModernSections()) do
		local obj = { key = s.key, rows = {} }
		local header = CreateFrame("Button", nil, content)
		header:SetSize(178, 18)
		local ht = header:CreateFontString(nil, "OVERLAY")
		font(ht, 11, "GameFontNormal")
		ht:SetPoint("LEFT", header, "LEFT", 2, 0)
		ht:SetText(string.upper(s.title or ""))
		ht:SetTextColor(ac.r, ac.g, ac.b)
		local arrow = header:CreateFontString(nil, "OVERLAY")
		font(arrow, 13, "GameFontNormal")
		arrow:SetPoint("RIGHT", header, "RIGHT", -2, 0)
		arrow:SetTextColor(0.6, 0.6, 0.66)
		local div = header:CreateTexture(nil, "ARTWORK")
		div:SetHeight(1)
		div:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
		div:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
		div:SetColorTexture(ac.r, ac.g, ac.b, 0.35)
		header:SetScript("OnClick", function()
			cpMod.db.modernCollapsed = cpMod.db.modernCollapsed or {}
			cpMod.db.modernCollapsed[s.key] = not cpMod.db.modernCollapsed[s.key]
			layoutModern()
		end)
		obj.header = header
		obj.arrow = arrow
		for _, r in ipairs(s.rows) do
			local nameFS = content:CreateFontString(nil, "OVERLAY")
			font(nameFS, 11, "GameFontHighlightSmall")
			nameFS:SetTextColor(0.68, 0.68, 0.72)
			nameFS:SetJustifyH("LEFT")
			nameFS:SetText(r.name)
			local valueFS = content:CreateFontString(nil, "OVERLAY")
			font(valueFS, 11, "GameFontHighlightSmall")
			valueFS:SetTextColor(0.92, 0.92, 0.96)
			valueFS:SetJustifyH("RIGHT")
			-- transparent hover strip for the Blizzard-style detail tooltip
			local hover = CreateFrame("Button", nil, content)
			hover:SetHeight(15)
			hover.def = r
			hover:SetScript("OnEnter", function(self)
				if not GameTooltip then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(self.def.name, 1, 1, 1)
				if self.def.tip then self.def.tip(GameTooltip) end
				GameTooltip:Show()
			end)
			hover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
			obj.rows[#obj.rows + 1] = { name = nameFS, value = valueFS, hover = hover, get = r.get, fmt = r.fmt }
		end
		p.secObjs[#p.secObjs + 1] = obj
	end

	modernPanel = p
	return p
end

-- Called from UpdateCharacterPanel when the Modern style is active and the
-- character frame is open.
function ns:RenderModernCharacterPanel()
	applyModernChrome(true)
	local p = ensureModernPanel()
	if not p then return end
	p:Show()
	updateModernValues()
	layoutModern()
end

local function UpdateCharacterPanel()
	if CharacterFrame and CharacterFrame:IsShown() then
		-- both self-gate on the style; on "modern" they clear the Classic+ overlays
		UpdateAllCharacterSlots()
		UpdatePlayerAvgIlvlDisplay()
		if cpStyle() == "modern" then
			applyModernPanes(true)
			applyModernTabs(true)
			-- the stats panel + right extension belong to the PAPERDOLL tab only;
			-- on skills / reputation / honor tabs they must go away
			if _G.PaperDollFrame and _G.PaperDollFrame:IsShown() then
				ns:RenderModernCharacterPanel()
			else
				if modernPanel then modernPanel:Hide() end
				applyModernChrome(false)
			end
		else
			if modernPanel then modernPanel:Hide() end
			applyModernChrome(false)
			applyModernPanes(false)
			applyModernTabs(false)
		end
		-- frames docked right of the window follow the style's extension
		if ns.ReanchorLoadoutsSidebar then ns.ReanchorLoadoutsSidebar() end
	end
end

-- Exposed so the options toggles can refresh the open panel immediately
ns.RefreshCharacterPanel = UpdateCharacterPanel

-- Tab switches inside the character window toggle the sub-frames without any
-- of our events firing — follow the paperdoll's own show/hide so the Modern
-- stats panel appears and disappears with its tab.
if _G.PaperDollFrame then
	_G.PaperDollFrame:HookScript("OnShow", UpdateCharacterPanel)
	_G.PaperDollFrame:HookScript("OnHide", UpdateCharacterPanel)
end

-- =========================================================
-- Events
-- =========================================================
local eventListener = CreateFrame("Frame")

eventListener:SetScript("OnEvent", function(self, event, ...)
	if addon[event] then
		addon[event](addon, ...)
	end
end)

function addon:ADDON_LOADED(name)
	if name ~= "Blizzard_InspectUI" then return end

	if _G.InspectPaperDollItemSlotButton_Update then
		hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
			if InspectFrame and InspectFrame.unit then
				UpdateButton(button, InspectFrame.unit)
			end
		end)
	end

	if InspectFrame then
		InspectFrame:HookScript("OnShow", function()
			CreateInspectIlvlDisplay()

			C_Timer.After(0.1, function()
				if InspectFrame and InspectFrame.unit then
					UpdateInspectIlvlDisplayTBC(InspectFrame.unit)
					UpdateAllInspectSlots()
				end
			end)
		end)
	end
end

function addon:INSPECT_READY(guid)
	if not InspectFrame or not InspectFrame.unit then return end
	if UnitGUID(InspectFrame.unit) ~= guid then return end

	CreateInspectIlvlDisplay()
	UpdateInspectIlvlDisplayTBC(InspectFrame.unit)
	UpdateAllInspectSlots()
end

function addon:PLAYER_EQUIPMENT_CHANGED()
	UpdateCharacterPanel()
end

function addon:UNIT_INVENTORY_CHANGED(unit)
	if unit ~= "player" then return end
	UpdateCharacterPanel()
end

function addon:UPDATE_INVENTORY_DURABILITY()
	UpdateCharacterPanel()
end

function addon:PLAYER_ENTERING_WORLD()
	C_Timer.After(0.2, function()
		UpdateCharacterPanel()
	end)
end

eventListener:RegisterEvent("ADDON_LOADED")
eventListener:RegisterEvent("INSPECT_READY")
eventListener:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventListener:RegisterEvent("UNIT_INVENTORY_CHANGED")
eventListener:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
eventListener:RegisterEvent("PLAYER_ENTERING_WORLD")

if CharacterFrame then
	CharacterFrame:HookScript("OnShow", function()
		UpdateCharacterPanel()
	end)
end

-- The Modern chrome belongs to the paper-doll (Character) sub-tab only. When
-- the user switches to Reputation/Skills/Honor the character frame stays open
-- but PaperDollFrame hides, so follow it: drop the dark bg + stats panel when
-- the paper doll leaves, restore them when it returns.
if _G.PaperDollFrame then
	_G.PaperDollFrame:HookScript("OnHide", function()
		if modernPanel then modernPanel:Hide() end
		applyModernChrome(false)
	end)
	_G.PaperDollFrame:HookScript("OnShow", function()
		if cpStyle() == "modern" then ns:RenderModernCharacterPanel() end
	end)
end
end  -- ns:RunCharacterPanelInit

end)(...);
