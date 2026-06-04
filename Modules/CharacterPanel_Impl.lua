-- =========================================================
-- VuloClassicUI / Modules / CharacterPanel_Impl
-- Ported from BetterCharacterPanel (TBC ANNIVERSARY).
-- Only works if the "characterpanel" module is enabled.
-- =========================================================
local _, ns = ...
local L = ns.L

local isTBC = (WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
if not isTBC then
    return
end

-- We wait for PLAYER_LOGIN so the module registry and DB are ready.
-- If the module is disabled, we return early.
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local mod = ns.modules and ns.modules.characterpanel
    if not mod or not mod.db or not mod.db.enabled then
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

-- =========================================================
-- Constants / Layout
-- =========================================================
local NUM_SOCKET_TEXTURES = 4

local ILVL_FONT_SIZE = 11
local ILVL_Y_OFFSET  = 4

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

local RINGS_ENCH = cpOpt("ringsEnchantable", true)

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

	["Spell Damage"] = "SpDmg",
	["Healing"] = "Heal",

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

	["Zauberschaden und Heilung sowie Zaubertrefferwertung"] = "Zaub & Zaubt",
	["Zauberschaden"] = "Zaub",
	["Zaubermacht"] = "Zaub",
	["Schaden und Heilung"] = "Z/H",
	["Zaubermacht und Zaubertrefferwertung"] = "Zaub & Zaubt",
	["Zauberschaden und Zaubertrefferwertung"] = "Zaub & Zaubt",
	["Heilung"] = "Heal",

	["Kritische Trefferwertung"] = "Crit",
	["Kritischer Trefferwert"] = "Crit",
	["Kritisch"] = "Crit",
	["Tempo"] = "Tempo",
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
	[" und "] = " ",
	[" and "] = " ",
	["+"] = "",
}

local function pairsByKeys(t, f)
	local a = {}

	for n in pairs(t) do
		table.insert(a, n)
	end

	table.sort(a, function(a, b)
		return #a > #b
	end)

	local i = 0

	return function()
		i = i + 1
		if a[i] == nil then return nil end
		return a[i], t[a[i]]
	end
end

local function ProcessEnchantText(enchantText)
	if not enchantText then return enchantText end

	-- Only abbreviate when the "shorten enchant text" toggle is on
	if cpOpt("shortenEnchants", true) then
		for seek, replacement in pairsByKeys(enchantReplacementTable) do
			enchantText = enchantText:gsub(seek, replacement)
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

local function CreateAdditionalDisplayForButton(button)
	local parent = button:GetParent()
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(100)

	f.ilvlDisplay = f:CreateFontString(nil, "OVERLAY")
	f.ilvlDisplay:SetFont(STANDARD_TEXT_FONT, ILVL_FONT_SIZE, "OUTLINE")
	f.ilvlDisplay:SetJustifyH("CENTER")
	f.ilvlDisplay:SetJustifyV("MIDDLE")

	f.enchantDisplay = f:CreateFontString(nil, "OVERLAY")
	f.enchantDisplay:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
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

	for i = 1, NUM_SOCKET_TEXTURES do
		f.socketDisplay[i] = f:CreateTexture(nil, "OVERLAY")
		f.socketDisplay[i]:SetWidth(SOCKET_SIZE)
		f.socketDisplay[i]:SetHeight(SOCKET_SIZE)
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
	f.enchantDisplay:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -7)

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
		f.enchantDisplay:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", -5, 0)
	else
		f.enchantDisplay:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 5, 0)
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

			if textures[i] then
				t:SetTexture(textures[i])
				t:SetVertexColor(1, 1, 1)
				t:Show()
			else
				t:Hide()
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

local function UpdateCharacterPanel()
	if CharacterFrame and CharacterFrame:IsShown() then
		UpdateAllCharacterSlots()
		UpdatePlayerAvgIlvlDisplay()
	end
end

-- Exposed so the options toggles can refresh the open panel immediately
ns.RefreshCharacterPanel = UpdateCharacterPanel

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
end  -- ns:RunCharacterPanelInit
