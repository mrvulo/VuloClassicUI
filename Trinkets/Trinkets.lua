--[[ Trinkets 11.1.8 ]]--

Trinkets = { }

local _G, math, tonumber, string, type, pairs, ipairs, table, select = _G, math, tonumber, string, type, pairs, ipairs, table, select
local Masque = LibStub("Masque", true)

local IsClassic = WOW_PROJECT_ID >= WOW_PROJECT_CLASSIC
local IsVanillaClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local IsRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

-- localized strings required to support engineering bags
Trinkets.BAG = "Bag" -- 7th return of GetItemInfo on a normal bag
Trinkets.ENGINEERING_BAG = "Engineering Bag" -- 7th return of GetItemInfo on an engineering bag
Trinkets.TRADE_GOODS = "Trade Goods" -- 6th return of GetItemInfo on most engineered trinkets
Trinkets.DEVICES = "Devices" -- 7th return of GetItemInfo on most engineered trinkets
Trinkets.REQUIRES_ENGINEERING = "Requires Engineering" -- from tooltip when GetItemInfo ambiguous

function Trinkets.LoadDefaults()
	TrinketsOptions = TrinketsOptions or {
		IconPos = - 100,				-- angle of initial minimap icon position
		ShowIcon = "ON",				-- whether to show the minimap button
		SquareMinimap = "OFF",			-- whether the minimap is square instead of circular
		CooldownCount = "OFF",			-- whether to display numerical cooldown counters
		CooldownCountBlizzard = "ON",	-- whether to display numerical blizzard cooldown counters
		CooldownCountOmniCC = "ON",		-- whether to display numerical omnicc cooldown counters
		LargeCooldown = "ON",			-- whether cooldown numbers are large or small
		TooltipFollow = "OFF",			-- whether tooltips follow the mouse
		KeepOpen = "OFF",				-- whether menu hides after use
		KeepDocked = "ON",				-- whether to keep menu docked at all times
		Notify = "OFF",					-- whether a message appears when a trinket is ready
		DisableToggle = "OFF",			-- whether minimap button toggles trinkets
		NotifyUsedOnly = "OFF",			-- whether notify happens only on trinkets used
		NotifyChatAlso = "OFF",			-- whether to send notify to chat also
		Locked = "OFF",					-- whether windows can be moved/scaled/rotated
		ShowTooltips = "ON",			-- whether to display tooltips at all
		NotifyThirty = "OFF",			-- whether to notify cooldowns at 30 seconds instead of 0
		MenuOnShift = "OFF",			-- whether menu requires Shift to display
		TinyTooltips = "OFF",			-- whether tooltips display only name and cooldown
		SetColumns = "OFF",				-- whether number of columns in menu is chosen automatically
		Columns = 4,					-- if SetColumns "ON", number of columns before menu wraps
		ShowHotKeys = "OFF",			-- whether hotkeys show on trinkets
		StopOnSwap = "OFF",				-- whether to stop auto queue on all manual swaps
		RedRange = "OFF",				-- whether to monitor and red out out of range trinkets
		HidePetBattle = "ON",			-- whether to hide the trinkets while in a pet battle
		MenuOnRight = "OFF"				-- whether to open menu with right-click
	}
	TrinketsPerOptions = TrinketsPerOptions or {
		MainDock = "BOTTOMRIGHT",		-- corner of main window docked to
		MenuDock = "BOTTOMLEFT",		-- corner menu window is docked from
		MainOrient = "HORIZONTAL",		-- direction of main window
		MenuOrient = "VERTICAL",		-- direction of menu window
		XPos = 400,						-- left edge of main window
		YPos = 400,						-- top edge of main window
		MainScale = 1,					-- scaling of main window
		MenuScale = 1,					-- scaling of menu window
		Visible = "ON",					-- whether to display the trinkets
		FirstUse = true,				-- whether this is the first time this user has used the mod
		ItemsUsed = { },				-- table of trinkets used and their cooldown status
		Alpha = 1,						-- alpha of both windows
		Hidden = { }					-- table of trinkets hidden
	}
end

--[[ Misc Variables ]]--

-- VCUI-Patch: war GetAddOnMetadata("Trinkets",...) → nil weil als VuloClassicUI eingebettet
Trinkets_Version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("VuloClassicUI", "Version")) or "embedded"
BINDING_HEADER_VULOCLASSICUI_TRINKETS = "VuloClassicUI – Trinkets"
setglobal("BINDING_NAME_CLICK Trinkets_Trinket0:LeftButton", "Trinket-Slot oben")
setglobal("BINDING_NAME_CLICK Trinkets_Trinket1:LeftButton", "Trinket-Slot unten")

Trinkets.MaxTrinkets = 30 -- add more to Trinkets_MenuFrame if this changes
Trinkets.BaggedTrinkets = { } -- indexed by number, 1-30 of trinkets in the menu
Trinkets.NumberOfTrinkets = 0 -- number of trinkets in the menu
Trinkets.CombatQueue = { } -- [0] or [1] = name of trinket queued for slot 0 or 1
Trinkets.Corners = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}

--[[ Local functions ]]--

-- dock-dependant offset and directions: MainDock..MenuDock
-- x/yoff   = offset MenuFrame is positioned to MainFrame
-- x/ydir   = direction trinkets are added to menu
-- x/ystart = starting offset when building a menu, relativePoint MenuDock
if IsRetail then
	Trinkets.DockStats = {
		["TOPRIGHTTOPLEFT"] =			{ xoff = -7, yoff = 0, xdir = 1, ydir = - 1, xstart = 4, ystart = -4 },
		["BOTTOMRIGHTBOTTOMLEFT"] = 	{ xoff = -7, yoff = 0, xdir = 1, ydir = 1, xstart = 4, ystart = 48 },
		["TOPLEFTTOPRIGHT"] =			{ xoff = 7, yoff = 0, xdir = - 1, ydir = -1, xstart = -48, ystart = -4 },
		["BOTTOMLEFTBOTTOMRIGHT"] =		{ xoff = 7, yoff = 0, xdir = - 1, ydir = 1, xstart = -48, ystart = 48 },
		["TOPRIGHTBOTTOMRIGHT"] =		{ xoff = 0, yoff = -7, xdir = -1, ydir = 1, xstart = -48, ystart = 48 },
		["BOTTOMRIGHTTOPRIGHT"] =		{ xoff = 0, yoff = 7, xdir = - 1, ydir = -1, xstart = -48, ystart = -4 },
		["TOPLEFTBOTTOMLEFT"] =			{ xoff = 0, yoff = -7, xdir = 1, ydir = 1, xstart = 4, ystart = 48 },
		["BOTTOMLEFTTOPLEFT"] =			{ xoff = 0, yoff = 7, xdir = 1, ydir = - 1, xstart = 4, ystart = -4 }
	}
else
	Trinkets.DockStats = {
		["TOPRIGHTTOPLEFT"] =			{ xoff = -12, yoff = 0, xdir = 1, ydir = - 1, xstart = 8, ystart = -8 },
		["BOTTOMRIGHTBOTTOMLEFT"] = 	{ xoff = -12, yoff = 0, xdir = 1, ydir = 1, xstart = 8, ystart = 44 },
		["TOPLEFTTOPRIGHT"] =			{ xoff = 12, yoff = 0, xdir = -1, ydir = -1, xstart = -44, ystart = -8 },
		["BOTTOMLEFTBOTTOMRIGHT"] =		{ xoff = 12, yoff = 0, xdir = -1, ydir = 1, xstart = -44, ystart = 44 },
		["TOPRIGHTBOTTOMRIGHT"] =		{ xoff = 0, yoff = -12, xdir = -1, ydir = 1, xstart = -44, ystart = 44 },
		["BOTTOMRIGHTTOPRIGHT"] =		{ xoff = 0, yoff = 12, xdir = -1, ydir = -1, xstart = -44, ystart = -8 },
		["TOPLEFTBOTTOMLEFT"] =			{ xoff = 0, yoff = -12, xdir = 1, ydir = 1, xstart = 8, ystart = 44 },
		["BOTTOMLEFTTOPLEFT"] =			{ xoff = 0, yoff = 12, xdir = 1, ydir = - 1, xstart = 8, ystart = -8 }
	}
end

-- returns offset and direction depending on current docking. ie: Trinkets.DockInfo("xoff")
function Trinkets.DockInfo(arg1)
	local anchor = TrinketsPerOptions.MainDock..TrinketsPerOptions.MenuDock
	if Trinkets.DockStats[anchor] and arg1 and Trinkets.DockStats[anchor][arg1] then
		return Trinkets.DockStats[anchor][arg1]
	else
		return 0
	end
end

-- hide the docking markers
function Trinkets.ClearDocking()
	for i = 1, 4 do
		_G["Trinkets_MainDock_"..Trinkets.Corners[i]]:Hide()
		_G["Trinkets_MenuDock_"..Trinkets.Corners[i]]:Hide()
	end
end

-- returns true if the two values are close to each other
function Trinkets.Near(arg1, arg2)
	return (math.max(arg1, arg2) - math.min(arg1, arg2)) < 15
end

-- moves the MenuFrame to the dock position against MainFrame
function Trinkets.DockWindows()
	Trinkets.ClearDocking()
	if TrinketsOptions.KeepDocked == "ON" then
		Trinkets_MenuFrame:ClearAllPoints()
		if TrinketsOptions.Locked == "OFF" then
			Trinkets_MenuFrame:SetPoint(TrinketsPerOptions.MenuDock, "Trinkets_MainFrame", TrinketsPerOptions.MainDock, Trinkets.DockInfo("xoff"), Trinkets.DockInfo("yoff"))
		else
			Trinkets_MenuFrame:SetPoint(TrinketsPerOptions.MenuDock, "Trinkets_MainFrame", TrinketsPerOptions.MainDock, Trinkets.DockInfo("xoff"), Trinkets.DockInfo("yoff"))
		end
	end
	if Trinkets_MenuFrame:IsVisible() then
		Trinkets.BuildMenu()
	end
end

-- displays windows vertically or horizontally
function Trinkets.OrientWindows()
	if TrinketsPerOptions.MainOrient == "HORIZONTAL" then
		if IsRetail then
			Trinkets_MainFrame:SetWidth(97)
			Trinkets_MainFrame:SetHeight(52)
		else
			Trinkets_MainFrame:SetWidth(92)
			Trinkets_MainFrame:SetHeight(52)
		end
	else
		if IsRetail then
			Trinkets_MainFrame:SetWidth(52)
			Trinkets_MainFrame:SetHeight(97)
		else
			Trinkets_MainFrame:SetWidth(52)
			Trinkets_MainFrame:SetHeight(92)
		end
	end
end

function Trinkets.ScaleFrame(scale)
	Trinkets.FrameToScale:SetScale(scale)
end

function Trinkets.GetContainerNumSlots(bagID)
	return C_Container.GetContainerNumSlots(bagID)
end

function Trinkets.GetContainerItemCooldown(bagID, slotIndex)
	return C_Container.GetContainerItemCooldown(bagID, slotIndex)
end

function Trinkets.GetContainerItemInfo(bagID, slotIndex)
	return C_Container.GetContainerItemInfo(bagID, slotIndex)
end

function Trinkets.GetContainerItemLink(bagID, slotIndex)
	return C_Container.GetContainerItemLink(bagID, slotIndex)
end

function Trinkets.PickupContainerItem(bagID, slotIndex)
	return C_Container.PickupContainerItem(bagID, slotIndex)
end

function Trinkets.GetItemCooldown(itemID)
	return C_Container.GetItemCooldown(itemID)
end

-- scan inventory and build MenuFrame
function Trinkets.BuildMenu()
	if not IsShiftKeyDown() and TrinketsOptions.MenuOnShift == "ON" then
		return
	end
	local idx = 1
	local _, itemLink, itemID, itemName, equipSlot, itemTexture
	-- go through bags and gather trinkets into .BaggedTrinkets
	for i = 0, 4 do
		for j = 1, Trinkets.GetContainerNumSlots(i) do
			itemLink = Trinkets.GetContainerItemLink(i, j)
			if itemLink then
				_, _, itemID, itemName = string.find(Trinkets.GetContainerItemLink(i, j) or "", "item:(%d+).+%[(.+)%]")
				_, _, _, _, _, _, _, _, equipSlot, itemTexture = GetItemInfo(itemID or "")
				if equipSlot == "INVTYPE_TRINKET" and (IsAltKeyDown() or not TrinketsPerOptions.Hidden[itemID]) then
					if not Trinkets.BaggedTrinkets[idx] then
						Trinkets.BaggedTrinkets[idx] = { }
					end
					Trinkets.BaggedTrinkets[idx].id = itemID
					Trinkets.BaggedTrinkets[idx].bag = i
					Trinkets.BaggedTrinkets[idx].slot = j
					Trinkets.BaggedTrinkets[idx].name = itemName
					Trinkets.BaggedTrinkets[idx].texture = itemTexture
					idx = idx + 1
				end
			end
		end
	end
	Trinkets.NumberOfTrinkets = math.min(idx - 1, Trinkets.MaxTrinkets)
	if Trinkets.NumberOfTrinkets < 1 then
		-- user has no bagged trinkets :(
		Trinkets_MenuFrame:Hide()
	else
		-- display trinkets outward from docking point
		local col, row, xpos, ypos = 0, 0, Trinkets.DockInfo("xstart"), Trinkets.DockInfo("ystart")
		local max_cols = 1
		if Trinkets.NumberOfTrinkets > 24 then
			max_cols = 5
		elseif Trinkets.NumberOfTrinkets > 18 then
			max_cols = 4
		elseif Trinkets.NumberOfTrinkets > 12 then
			max_cols = 3
		elseif Trinkets.NumberOfTrinkets > 4 then
			max_cols = 2
		end
		if TrinketsOptions.SetColumns == "ON" and TrinketsOptions.Columns then
			max_cols = TrinketsOptions.Columns
		end
		local item, icon
		for i = 1, Trinkets.NumberOfTrinkets do
			item = _G["Trinkets_Menu"..i]
			icon = _G["Trinkets_Menu"..i.."Icon"]
			icon:SetTexture(Trinkets.BaggedTrinkets[i].texture)
			if TrinketsPerOptions.Hidden[Trinkets.BaggedTrinkets[i].id] then
				icon:SetDesaturated(true)
			else
				icon:SetDesaturated(false)
			end
			item:SetPoint("TOPLEFT", "Trinkets_MenuFrame", TrinketsPerOptions.MenuDock, xpos, ypos)
			if TrinketsPerOptions.MenuOrient == "VERTICAL" then
				xpos = xpos + Trinkets.DockInfo("xdir") * (IsRetail and 45 or 40)
				col = col + 1
				if col == max_cols then
					xpos = Trinkets.DockInfo("xstart")
					col = 0
					ypos = ypos + Trinkets.DockInfo("ydir") * (IsRetail and 45 or 40)
					row = row + 1
				end
				item:Show()
			else
				ypos = ypos + Trinkets.DockInfo("ydir") * (IsRetail and 45 or 40)
				col = col + 1
				if col == max_cols then
					ypos = Trinkets.DockInfo("ystart")
					col = 0
					xpos = xpos + Trinkets.DockInfo("xdir") * (IsRetail and 45 or 40)
					row = row + 1
				end
				item:Show()
			end
		end
		for i = (Trinkets.NumberOfTrinkets + 1), Trinkets.MaxTrinkets do
			_G["Trinkets_Menu"..i]:Hide()
		end
		if col == 0 then
			row = row - 1
		end
		if TrinketsPerOptions.MenuOrient == "VERTICAL" then
			Trinkets_MenuFrame:SetWidth((IsRetail and 7 or 12) + (max_cols * (IsRetail and 45 or 40)))
			Trinkets_MenuFrame:SetHeight((IsRetail and 7 or 12) + ((row + 1) * (IsRetail and 45 or 40)))
		else
			Trinkets_MenuFrame:SetWidth((IsRetail and 7 or 12) + ((row + 1) * (IsRetail and 45 or 40)))
			Trinkets_MenuFrame:SetHeight((IsRetail and 7 or 12) + (max_cols * (IsRetail and 45 or 40)))
		end
		Trinkets.UpdateMenuCooldowns()
		Trinkets_MenuFrame:Show()
		Trinkets.StartTimer("MenuMouseover")
	end
end

function Trinkets.Initialize()
	local options = TrinketsOptions
	-- Set Trinkets Skin
	if (Masque and not Trinkets.MasqueGroup) then
		local group = Masque:Group("Trinkets")
		Trinkets.MasqueGroup = group
		group:AddButton(Trinkets_Trinket0)
		group:AddButton(Trinkets_Trinket1)
		for i = 1, 30 do
			_G["Trinkets_Menu"..i]:SetFrameLevel(2)
			group:AddButton(_G["Trinkets_Menu"..i])
		end
	end
	options.KeepDocked = options.KeepDocked or "ON" -- new option for 2.1
	options.Notify = options.Notify or "OFF" -- 2.1
	options.DisableToggle = options.DisableToggle or "OFF" -- new option for 2.2
	options.NotifyUsedOnly = options.NotifyUsedOnly or "OFF" -- 2.2
	options.NotifyChatAlso = options.NotifyChatAlso or "OFF" -- 2.2
	options.ShowTooltips = options.ShowTooltips or "ON" -- 2.3
	options.NotifyThirty = options.NotifyThirty or "OFF" -- 2.5
	options.SquareMinimap = options.SquareMinimap or "OFF" -- 2.6
	options.MenuOnShift = options.MenuOnShift or "OFF" -- 2.6
	options.TinyTooltips = options.TinyTooltips or "OFF" -- 3.0
	options.SetColumns = options.SetColumns or "OFF" -- 3.0
	options.Columns = options.Columns or 4 -- 3.0
	options.CooldownCount = options.CooldownCount or "OFF" -- 3.0
	options.LargeCooldown = options.LargeCooldown or "OFF" -- 3.0
	options.ShowHotKeys = options.ShowHotKeys or "OFF" -- 3.0
	TrinketsPerOptions.ItemsUsed = TrinketsPerOptions.ItemsUsed or { } -- 3.0
	options.StopOnSwap = options.StopOnSwap or "OFF" -- 3.2
	options.HideOnLoad = options.HideOnLoad or "OFF" -- 3.4
	options.RedRange = options.RedRange or "OFF" -- 3.54
	options.HidePetBattle = options.HidePetBattle or "ON" -- 6.0.3
	options.CooldownCountBlizzard = options.CooldownCountBlizzard or "ON" -- 11.1.6
	options.CooldownCountOmniCC = options.CooldownCountOmniCC or "ON" -- 11.1.6
	TrinketsPerOptions.Alpha = TrinketsPerOptions.Alpha or 1 -- 3.5
	TrinketsPerOptions.Hidden = TrinketsPerOptions.Hidden or { }
	options.MenuOnRight = options.MenuOnRight or "OFF" -- 3.61
	if TrinketsPerOptions.XPos and TrinketsPerOptions.YPos then
		Trinkets_MainFrame:ClearAllPoints()
		Trinkets_MainFrame:SetPoint("TOPLEFT", "UIParent", "BOTTOMLEFT", TrinketsPerOptions.XPos, TrinketsPerOptions.YPos)
	end
	if TrinketsPerOptions.MainScale then
		Trinkets_MainFrame:SetScale(TrinketsPerOptions.MainScale)
	end
	if TrinketsPerOptions.MenuScale then
		Trinkets_MenuFrame:SetScale(TrinketsPerOptions.MenuScale)
	end
	Trinkets.ReflectAlpha()
	Trinkets_Trinket0:SetAttribute("type", "item")
	Trinkets_Trinket1:SetAttribute("type", "item")
	Trinkets_Trinket0:SetAttribute("slot", 13)
	Trinkets_Trinket1:SetAttribute("slot", 14)
	if Trinkets.QueueInit then
		-- alt has a special purpose if queue installed
		Trinkets_Trinket0:SetAttribute("alt-slot*", ATTRIBUTE_NOOP)
		Trinkets_Trinket1:SetAttribute("alt-slot*", ATTRIBUTE_NOOP)
	end
	Trinkets_Trinket0:SetAttribute("shift-slot*", ATTRIBUTE_NOOP)
	Trinkets_Trinket1:SetAttribute("shift-slot*", ATTRIBUTE_NOOP)
	Trinkets.ReflectMenuOnRight()
	Trinkets.InitTimers()
	Trinkets.CreateTimer("UpdateWornTrinkets", Trinkets.UpdateWornTrinkets, .75)
	Trinkets.CreateTimer("DockingMenu", Trinkets.DockingMenu, .2, 1)
	Trinkets.CreateTimer("MenuMouseover", Trinkets.MenuMouseover, .25, 1)
	Trinkets.CreateTimer("TooltipUpdate", Trinkets.TooltipUpdate, 1, 1)
	Trinkets.CreateTimer("CooldownUpdate", Trinkets.CooldownUpdate, 1, 1)
	Trinkets.CreateTimer("QueueUpdate", Trinkets.QueueUpdate, 1, 1)
	--Trinkets.CreateTimer("RedRange", Trinkets.RedRangeUpdate, .33, 1)
	hooksecurefunc("UseInventoryItem", Trinkets.newUseInventoryItem)
	hooksecurefunc("UseAction", Trinkets.newUseAction)
	Trinkets.InitOptions()
	Trinkets.UpdateWornTrinkets()
	Trinkets.DockWindows()
	Trinkets.OrientWindows()
	if options.CooldownCount == "ON" or options.NotifyThirty == "ON" or options.Notify == "ON" then
		Trinkets.StartTimer("CooldownUpdate")
	end
	if Trinkets_Trinket0 and Trinkets_Trinket0.cooldown then
		if options.CooldownCountBlizzard == "ON" then
			Trinkets_Trinket0.cooldown:SetHideCountdownNumbers(false)
		else
			Trinkets_Trinket0.cooldown:SetHideCountdownNumbers(true)
		end
		if options.CooldownCountOmniCC == "ON" then
			Trinkets_Trinket0.cooldown.noCooldownCount = false
		else
			Trinkets_Trinket0.cooldown.noCooldownCount = true

		end
	end
	if Trinkets_Trinket1 and Trinkets_Trinket1.cooldown then
		if options.CooldownCountBlizzard == "ON" then
			Trinkets_Trinket1.cooldown:SetHideCountdownNumbers(false)
		else
			Trinkets_Trinket1.cooldown:SetHideCountdownNumbers(true)
		end
		if options.CooldownCountOmniCC == "ON" then
			Trinkets_Trinket1.cooldown.noCooldownCount = false
		else
			Trinkets_Trinket1.cooldown.noCooldownCount = true
		end
	end
	for i = 1, Trinkets.MaxTrinkets do
		local menuButton = _G["Trinkets_Menu"..i]
		if menuButton and menuButton.cooldown then
			if options.CooldownCountBlizzard == "ON" then
				menuButton.cooldown:SetHideCountdownNumbers(false)
			else
				menuButton.cooldown:SetHideCountdownNumbers(true)
			end
			if options.CooldownCountOmniCC == "ON" then
				menuButton.cooldown.noCooldownCount = false
			else
				menuButton.cooldown.noCooldownCount = true
			end
		end
	end
	if Trinkets.PeriodicQueueCheck then
		Trinkets.PeriodicQueueCheck()
	end
	--Trinkets.StartTimer("QueueUpdate")
	--Trinkets.ReflectRedRange()
	if TrinketsPerOptions.Visible == "ON" and (GetInventoryItemLink("player", 13) or GetInventoryItemLink("player", 14)) then
		Trinkets_MainFrame:Show()
	end
	-- fix for OmniCC
	Trinkets_MainFrame:SetFrameLevel(1)
	Trinkets_MenuFrame:SetFrameLevel(1)
	Trinkets_Trinket0:SetFrameLevel(2)
	Trinkets_Trinket1:SetFrameLevel(2)
	for i = 1, Trinkets.MaxTrinkets do
		_G["Trinkets_Menu"..i]:SetFrameLevel(2)
	end

end

function Trinkets.ReflectMenuOnRight()
	Trinkets_Trinket0:SetAttribute("slot2", TrinketsOptions.MenuOnRight == "ON" and ATTRIBUTE_NOOP or nil)
	Trinkets_Trinket1:SetAttribute("slot2", TrinketsOptions.MenuOnRight == "ON" and ATTRIBUTE_NOOP or nil)
end

-- returns true if the player is really dead or ghost, not merely FD
function Trinkets.IsPlayerReallyDead()
	if IsVanillaClassic then
		return UnitIsDeadOrGhost("player") and not UnitIsFeignDeath("player")
	else
		return UnitIsDeadOrGhost("player")
	end
end

function Trinkets.ItemInfo(slot)
	local _
	local link, id, name, equipLoc, texture = GetInventoryItemLink("player", slot)
	if link then
		local _, _, id = string.find(link, "item:(%d+)")
		name, _, _, _, _, _, _, _, equipLoc, texture = GetItemInfo(id)
	else
		_, texture = GetInventorySlotInfo("Trinket"..(slot - 13).."Slot")
	end
	return texture, name, equipLoc
end

function Trinkets.FindItem(item, includeInventory)
	if includeInventory then
		for i = 13, 14 do
			local itemLink = GetInventoryItemLink("player", i) or ""
			local inventoryItemID = strmatch(itemLink, "item:(%d+)")
			local itemName = GetItemInfo(itemLink)
			if item == itemName or item == inventoryItemID then
				return i
			end
		end
	end
	for i = 0, 4 do
		for j = 1, Trinkets.GetContainerNumSlots(i) do
			local containerItemLink = Trinkets.GetContainerItemLink(i, j) or ""
			local containerItemID = strmatch(containerItemLink, "item:(%d+)")
			local containerItemName = GetItemInfo(containerItemLink)
			if item == containerItemName or item == containerItemID then
				return nil, i, j
			end
		end
	end
end

--[[ Frame Scripts ]]--

function Trinkets.OnLoad(self)
	self:OnBackdropLoaded()
	self:SetBackdropColor(0.0, 0.0, 0.0)
	self:SetBackdropBorderColor(0.0, 0.0, 0.0)
	SlashCmdList["TrinketsCOMMAND"] = Trinkets.SlashHandler
	SLASH_TrinketsCOMMAND1 = "/Trinkets"
	SLASH_TrinketsCOMMAND2 = "/trinket"
	self:RegisterEvent("PLAYER_LOGIN")
end

function Trinkets.OnEvent(self, event, ...)
	if event == "UNIT_INVENTORY_CHANGED" then
		local unitID = ...
		if unitID == "player" then
			Trinkets.UpdateWornTrinkets()
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		Trinkets.UpdateWornTrinkets()
	elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
		Trinkets.UpdateWornCooldowns(1)
	elseif event == "PET_BATTLE_OPENING_START" then
		if TrinketsOptions.HidePetBattle == "ON" then
			Trinkets_MainFrame.WasShown = Trinkets_MainFrame:IsShown()
			if Trinkets_MainFrame.WasShown then
				Trinkets_MainFrame:Hide()
			end
			Trinkets_MenuFrame.WasShown = Trinkets_MenuFrame:IsShown()
			if Trinkets_MenuFrame.WasShown then
				Trinkets_MenuFrame:Hide()
			end
		end
	elseif event == "PET_BATTLE_CLOSE" then
		if TrinketsOptions.HidePetBattle == "ON" then
			if Trinkets_MainFrame.WasShown then
				Trinkets_MainFrame:Show()
			end
			if Trinkets_MenuFrame.WasShown then
				Trinkets_MenuFrame:Show()
			end
		end
	elseif (event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE") and not Trinkets.IsPlayerReallyDead() then
		if Trinkets.CombatQueue[0] or Trinkets.CombatQueue[1] then
			Trinkets.EquipTrinketByName(Trinkets.CombatQueue[0], 13)
			Trinkets.EquipTrinketByName(Trinkets.CombatQueue[1], 14)
			Trinkets.CombatQueue[0] = nil
			Trinkets.CombatQueue[1] = nil
			Trinkets.UpdateCombatQueue()
		end
		Trinkets_OptMenuOnRight:Enable()
	elseif event == "UPDATE_BINDINGS" then
		Trinkets.KeyBindingsChanged()
	elseif event == "PLAYER_REGEN_DISABLED" then
		Trinkets_OptMenuOnRight:Disable()
	elseif event == "PLAYER_LOGIN" then
		Trinkets.LoadDefaults()
		Trinkets.Initialize()
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("PLAYER_REGEN_DISABLED")
		self:RegisterEvent("PLAYER_UNGHOST")
		self:RegisterEvent("PLAYER_ALIVE")
		self:RegisterEvent("UNIT_INVENTORY_CHANGED")
		self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		self:RegisterEvent("UPDATE_BINDINGS")
		self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
		if not IsClassic then
			self:RegisterEvent("PET_BATTLE_OPENING_START")
			self:RegisterEvent("PET_BATTLE_CLOSE")
		end
	end
end

function Trinkets.UpdateWornTrinkets()
	local texture, name = Trinkets.ItemInfo(13)
	Trinkets_Trinket0Icon:SetTexture(texture)
	texture, name = Trinkets.ItemInfo(14)
	Trinkets_Trinket1Icon:SetTexture(texture)
	Trinkets_Trinket0Icon:SetDesaturated(false)
	Trinkets_Trinket0:SetChecked(false)
	Trinkets_Trinket1Icon:SetDesaturated(false)
	Trinkets_Trinket1:SetChecked(false)
	Trinkets.UpdateWornCooldowns()
	if Trinkets_MenuFrame:IsVisible() then
		Trinkets.BuildMenu()
	end
end

function Trinkets.SlashHandler(msg)
	local _, _, which, profile = string.find(msg, "load (.+) (.+)")
	if profile and Trinkets.SetQueue then
		which = string.lower(which)
		if which == "top" or which == "0" then
			which = 0
		elseif which == "bottom" or which == "1" then
			which = 1
		end
		if type(which) == "number" then
			Trinkets.SetQueue(which, "SORT", profile)
			return
		end
	end
	msg = string.lower(msg)
	if not msg or msg == "" then
		Trinkets.ToggleFrame(Trinkets_MainFrame)
	elseif string.find(msg, "^opt") or string.find(msg, "^config") then
		Trinkets.ToggleFrame(Trinkets_OptFrame)
	elseif msg == "lock" then
		TrinketsOptions.Locked = "ON"
		Trinkets.DockWindows()
		Trinkets.ReflectLock()
	elseif msg == "unlock" then
		TrinketsOptions.Locked = "OFF"
		Trinkets.DockWindows()
		Trinkets.ReflectLock()
	elseif msg == "reset" then
		Trinkets.ResetSettings()
	elseif msg == "clear" then
		wipe(TrinketsPerOptions.Hidden)
		DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Trinkets: Cleared all ignored/hidden trinkets.")
	elseif string.find(msg, "alpha") then
		local _, _, alpha = string.find(msg, "alpha (.+)")
		alpha = tonumber(alpha)
		if alpha and alpha > 0 and alpha <= 1.0 then
			TrinketsPerOptions.Alpha = alpha
		else
			DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Trinkets alpha:")
			DEFAULT_CHAT_FRAME:AddMessage("trinket alpha (number) : set alpha from 0.1 to 1.0")
		end
		Trinkets.ReflectAlpha()
	elseif string.find(msg, "scale") then
		local _, _, menuscale = string.find(msg, "scale menu (.+)")
		if tonumber(menuscale) then
			Trinkets.FrameToScale = Trinkets_MenuFrame
			Trinkets.ScaleFrame(menuscale)
		end
		local _, _, mainscale = string.find(msg, "scale main (.+)")
		if tonumber(mainscale) then
			Trinkets.FrameToScale = Trinkets_MainFrame
			Trinkets.ScaleFrame(mainscale)
		end
		if not tonumber(menuscale) and not tonumber(mainscale) then
			DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Trinkets scale:")
			DEFAULT_CHAT_FRAME:AddMessage("/trinket scale main (number) : set exact main scale")
			DEFAULT_CHAT_FRAME:AddMessage("/trinket scale menu (number) : set exact menu scale")
			DEFAULT_CHAT_FRAME:AddMessage("ie, /trinket scale menu 0.85")
			DEFAULT_CHAT_FRAME:AddMessage("Note: You can drag the lower-right corner of either window to scale.  This slash command is for those who want to set an exact scale.")
		end
		Trinkets.FrameToScale = nil
		TrinketsPerOptions.MainScale = Trinkets_MainFrame:GetScale()
		TrinketsPerOptions.MenuScale = Trinkets_MenuFrame:GetScale()
	elseif string.find(msg, "load") then
		DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Trinkets load:")
		DEFAULT_CHAT_FRAME:AddMessage("/trinket load (top|bottom) profilename\nie: /trinket load bottom PvP")
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Trinkets useage:")
		DEFAULT_CHAT_FRAME:AddMessage("/trinket or /Trinkets : toggle the window")
		DEFAULT_CHAT_FRAME:AddMessage("/trinket reset : reset all settings")
		DEFAULT_CHAT_FRAME:AddMessage("/trinket clear : clear all ignored/hidden trinkets")
		DEFAULT_CHAT_FRAME:AddMessage("/trinket opt : summon options window")
		DEFAULT_CHAT_FRAME:AddMessage("/trinket lock|unlock : toggles window lock")
		DEFAULT_CHAT_FRAME:AddMessage("/trinket scale main|menu (number) : sets an exact scale")
		DEFAULT_CHAT_FRAME:AddMessage("/trinket load top|bottom profilename : loads a profile to top or bottom trinket")
	end
end

function Trinkets.ResetSettings()
	StaticPopupDialogs["TrinketsRESET"] = {
		text = "Are you sure you want to reset Trinkets to default state and reload the UI?",
		button1 = "Yes", button2 = "No", showAlert = 1, timeout = 0, whileDead = 1,
		OnAccept = function()
			TrinketsOptions = nil
			TrinketsPerOptions = nil
			TrinketsQueue = nil
			ReloadUI()
		end
	}
	StaticPopup_Show("TrinketsRESET")
end

--[[ Window Movement ]]--

function Trinkets.MainFrame_OnMouseUp(self)
	local arg1 = GetMouseButtonClicked()
	if arg1 == "LeftButton" then
		pcall(self.StopMovingOrSizing, self)
		TrinketsPerOptions.XPos = Trinkets_MainFrame:GetLeft()
		TrinketsPerOptions.YPos = Trinkets_MainFrame:GetTop()
	elseif TrinketsOptions.Locked == "OFF" then
		if TrinketsPerOptions.MainOrient == "VERTICAL" then
			TrinketsPerOptions.MainOrient = "HORIZONTAL"
		else
			TrinketsPerOptions.MainOrient = "VERTICAL"
		end
		Trinkets.OrientWindows()
	end
end

function Trinkets.MainFrame_OnMouseDown(self)
	if GetMouseButtonClicked() == "LeftButton" and TrinketsOptions.Locked == "OFF" then
		-- Secure-Frame: StartMoving wird vom WoW-Security geblockt (UseItem-Buttons).
		-- pcall um den action-blocked-Ping zu schlucken; Drag funktioniert dann nicht,
		-- aber Frame ist via Locked-Toggle eh ge-locked oder über Options positionierbar.
		pcall(self.StartMoving, self)
	end
end

--[[ Timers ]]

function Trinkets.InitTimers()
	Trinkets.TimerPool = { }
	Trinkets.Timers = { }
end

function Trinkets.CreateTimer(name, func, delay, rep)
	Trinkets.TimerPool[name] = {func = func, delay = delay, rep = rep, elapsed = delay}
end

function Trinkets.IsTimerActive(name)
	for i, j in ipairs(Trinkets.Timers) do
		if j == name then
			return i
		end
	end
	return nil
end

function Trinkets.StartTimer(name, delay)
	Trinkets.TimerPool[name].elapsed = delay or Trinkets.TimerPool[name].delay
	if not Trinkets.IsTimerActive(name) then
		table.insert(Trinkets.Timers, name)
		Trinkets_TimersFrame:Show()
	end
end

function Trinkets.StopTimer(name)
	local idx = Trinkets.IsTimerActive(name)
	if idx then
		table.remove(Trinkets.Timers, idx)
		if #Trinkets.Timers < 1 then
			Trinkets_TimersFrame:Hide()
		end
	end
end

function Trinkets.TimersFrame_OnUpdate(elapsed)
	local timerPool
	for _, name in ipairs(Trinkets.Timers) do
		timerPool = Trinkets.TimerPool[name]
		timerPool.elapsed = timerPool.elapsed - elapsed
		if timerPool.elapsed < 0 then
			timerPool.func()
			if timerPool.rep then
				timerPool.elapsed = timerPool.delay
			else
				Trinkets.StopTimer(name)
			end
		end
	end
	if Trinkets.PeriodicQueueCheck then
		Trinkets.PeriodicQueueCheck()
	end -- Check for auto queue
end

function Trinkets.TimerDebug()
	local on = "|cFF00FF00On"
	local off = "|cFFFF0000Off"
	DEFAULT_CHAT_FRAME:AddMessage("|cFF44AAFFTrinkets_TimersFrame is "..(Trinkets_TimersFrame:IsVisible() and on or off))
	for i in pairs(Trinkets.TimerPool) do
		DEFAULT_CHAT_FRAME:AddMessage(i.." is "..(Trinkets.IsTimerActive(i) and on or off))
	end
end

--[[ OnClicks ]]

function Trinkets.MainTrinket_OnClick(self, button, down)
	self:SetChecked(false)
	if button == "RightButton" and TrinketsOptions.MenuOnRight == "ON" then
		if Trinkets_MenuFrame:IsVisible() then
			Trinkets_MenuFrame:Hide()
		else
			Trinkets.BuildMenu()
		end
	elseif IsShiftKeyDown() and down then
		if ChatFrame1EditBox:IsVisible() then
			ChatFrame1EditBox:Insert(GetInventoryItemLink("player", self:GetID()))
		end
	elseif IsAltKeyDown() and not down and Trinkets.QueueInit then
		local which = self:GetID() - 13
		if TrinketsQueue.Enabled[which] then
			Trinkets.CombatQueue[self:GetID() - 13] = nil
			TrinketsQueue.Enabled[which] = nil
		else
			TrinketsQueue.Enabled[which] = 1
		end
		Trinkets.ReflectQueueEnabled()
		-- toggle queue
		Trinkets.UpdateCombatQueue()
	else
		Trinkets.ReflectTrinketUse(self:GetID())
	end
end

function Trinkets.MenuTrinket_OnClick(self, button, down)
	self:SetChecked(false)
	if IsShiftKeyDown() and ChatFrame1EditBox:IsVisible() then
		ChatFrame1EditBox:Insert(Trinkets.GetContainerItemLink(Trinkets.BaggedTrinkets[self:GetID()].bag, Trinkets.BaggedTrinkets[self:GetID()].slot))
	elseif IsAltKeyDown() then
		local _, _, itemID = string.find(Trinkets.GetContainerItemLink(Trinkets.BaggedTrinkets[self:GetID()].bag, Trinkets.BaggedTrinkets[self:GetID()].slot) or "", "item:(%d+)")
		if TrinketsPerOptions.Hidden[itemID] then
			TrinketsPerOptions.Hidden[itemID] = nil
		else
			TrinketsPerOptions.Hidden[itemID] = 1
		end
		Trinkets.BuildMenu()
	else
		local slot = (button == "LeftButton") and 13 or 14
		if Trinkets.QueueInit then
			local _, _, canCooldown = Trinkets.GetContainerItemCooldown(Trinkets.BaggedTrinkets[self:GetID()].bag, Trinkets.BaggedTrinkets[self:GetID()].slot)
			if canCooldown == 0 or TrinketsOptions.StopOnSwap == "ON" then -- if incoming trinket can't go on cooldown
				TrinketsQueue.Enabled[slot - 13] = nil -- turn off autoqueue
				Trinkets.ReflectQueueEnabled()
			end
		end
		Trinkets.EquipTrinketByName(Trinkets.BaggedTrinkets[self:GetID()].name, slot)
		if not IsShiftKeyDown() and TrinketsOptions.KeepOpen == "OFF" then
			Trinkets_MenuFrame:Hide()
		end
	end
end

--[[ Docking ]]

function Trinkets.MenuFrame_OnMouseDown(button)
	if button == "LeftButton" and TrinketsOptions.Locked == "OFF" then
		pcall(Trinkets_MenuFrame.StartMoving, Trinkets_MenuFrame)
		if TrinketsOptions.KeepDocked == "ON" then
			Trinkets.StartTimer("DockingMenu")
		end
	end
end

function Trinkets.MenuFrame_OnMouseUp(button)
	if button == "LeftButton" then
		Trinkets.StopTimer("DockingMenu")
		pcall(Trinkets_MenuFrame.StopMovingOrSizing, Trinkets_MenuFrame)
		if TrinketsOptions.KeepDocked == "ON" then
			Trinkets.DockWindows()
		end
	elseif TrinketsOptions.Locked == "OFF" then
		if TrinketsPerOptions.MenuOrient == "VERTICAL" then
			TrinketsPerOptions.MenuOrient = "HORIZONTAL"
		else
			TrinketsPerOptions.MenuOrient = "VERTICAL"
		end
		Trinkets.BuildMenu()
	end
end

function Trinkets.DockingMenu()
	local main = Trinkets_MainFrame
	local menu = Trinkets_MenuFrame
	local mainscale = Trinkets_MainFrame:GetScale()
	local menuscale = Trinkets_MenuFrame:GetScale()
	local near = Trinkets.Near
	if near(main:GetRight() * mainscale,menu:GetLeft() * menuscale) then
		if near(main:GetTop() * mainscale,menu:GetTop() * menuscale) then
			TrinketsPerOptions.MainDock = "TOPRIGHT"
			TrinketsPerOptions.MenuDock = "TOPLEFT"
		elseif near(main:GetBottom() * mainscale,menu:GetBottom() * menuscale) then
			TrinketsPerOptions.MainDock = "BOTTOMRIGHT"
			TrinketsPerOptions.MenuDock = "BOTTOMLEFT"
		end
	elseif near(main:GetLeft() * mainscale,menu:GetRight() * menuscale) then
		if near(main:GetTop() * mainscale,menu:GetTop() * menuscale) then
			TrinketsPerOptions.MainDock = "TOPLEFT"
			TrinketsPerOptions.MenuDock = "TOPRIGHT"
		elseif near(main:GetBottom() * mainscale,menu:GetBottom() * menuscale) then
			TrinketsPerOptions.MainDock = "BOTTOMLEFT"
			TrinketsPerOptions.MenuDock = "BOTTOMRIGHT"
		end
	elseif near(main:GetRight() * mainscale,menu:GetRight() * menuscale) then
		if near(main:GetTop() * mainscale,menu:GetBottom() * menuscale) then
			TrinketsPerOptions.MainDock = "TOPRIGHT"
			TrinketsPerOptions.MenuDock = "BOTTOMRIGHT"
		elseif near(main:GetBottom() * mainscale,menu:GetTop() * menuscale) then
			TrinketsPerOptions.MainDock = "BOTTOMRIGHT"
			TrinketsPerOptions.MenuDock = "TOPRIGHT"
		end
	elseif near(main:GetLeft() * mainscale,menu:GetLeft() * menuscale) then
		if near(main:GetTop() * mainscale,menu:GetBottom() * menuscale) then
			TrinketsPerOptions.MainDock = "TOPLEFT"
			TrinketsPerOptions.MenuDock = "BOTTOMLEFT"
		elseif near(main:GetBottom() * mainscale,menu:GetTop() * menuscale) then
			TrinketsPerOptions.MainDock = "BOTTOMLEFT"
			TrinketsPerOptions.MenuDock = "TOPLEFT"
		end
	end
	Trinkets.ClearDocking()
	_G["Trinkets_MainDock_"..TrinketsPerOptions.MainDock]:Show()
	_G["Trinkets_MenuDock_"..TrinketsPerOptions.MenuDock]:Show()
end

function Trinkets.MenuMouseover()
	if (not MouseIsOver(Trinkets_MainFrame)) and (not MouseIsOver(Trinkets_MenuFrame)) and not IsShiftKeyDown() and (TrinketsOptions.KeepOpen == "OFF") then
		Trinkets.StopTimer("MenuMouseover")
		Trinkets_MenuFrame:Hide()
	end
end

--[[ Cooldowns ]]

function Trinkets.UpdateWornCooldowns(maybeGlobal)
	local start, duration, enable = GetInventoryItemCooldown("player", 13)
	CooldownFrame_Set(Trinkets_Trinket0Cooldown, start, duration, enable)
	start, duration, enable = GetInventoryItemCooldown("player", 14)
	CooldownFrame_Set(Trinkets_Trinket1Cooldown, start, duration, enable)
	if not maybeGlobal then
		Trinkets.WriteWornCooldowns()
	end
end

function Trinkets.UpdateMenuCooldowns()
	local start, duration, enable
	for i = 1, Trinkets.NumberOfTrinkets do
		start,duration,enable = Trinkets.GetContainerItemCooldown(Trinkets.BaggedTrinkets[i].bag, Trinkets.BaggedTrinkets[i].slot)
		CooldownFrame_Set(_G["Trinkets_Menu"..i.."Cooldown"], start, duration, enable)
	end
	Trinkets.WriteMenuCooldowns()
end

--[[ Item use ]]

function Trinkets.ReflectTrinketUse(slot)
	_G["Trinkets_Trinket"..(slot - 13)]:SetChecked(true)
	Trinkets.StartTimer("UpdateWornTrinkets")
	local _, _, id = string.find(GetInventoryItemLink("player", slot) or "", "item:(%d+)")
	if id then
		TrinketsPerOptions.ItemsUsed[id] = 0 -- 0 is an indeterminate state, cooldown will figure if it's worth watching
	end
end

function Trinkets.newUseInventoryItem(slot)
	if slot == 13 or slot == 14 and not MerchantFrame:IsVisible() then
		Trinkets.ReflectTrinketUse(slot)
	end
end

function Trinkets.newUseAction(slot)
	if IsEquippedAction(slot) then
		Trinkets_TooltipScan:SetOwner(WorldFrame, "ANCHOR_NONE")
		Trinkets_TooltipScan:SetAction(slot)
		local _, trinket0 = Trinkets.ItemInfo(13)
		local _, trinket1 = Trinkets.ItemInfo(14)
		if GameTooltipTextLeft1:GetText() == trinket0 then
			Trinkets.ReflectTrinketUse(13)
		elseif GameTooltipTextLeft1:GetText() == trinket1 then
			Trinkets.ReflectTrinketUse(14)
		end
	end
end

--[[ Tooltips ]]

function Trinkets.WornTrinketTooltip(self)
	if TrinketsOptions.ShowTooltips == "OFF" then
		return
	end
	local id = self:GetID()
	Trinkets.TooltipOwner = self
	Trinkets.TooltipType = "INVENTORY"
	Trinkets.TooltipSlot = id
	Trinkets.TooltipBag = Trinkets.CombatQueue[id - 13]
	Trinkets.StartTimer("TooltipUpdate", 0)
end

function Trinkets.MenuTrinketTooltip(self)
	if TrinketsOptions.ShowTooltips == "OFF" then
		return
	end
	local id = self:GetID()
	Trinkets.TooltipOwner = self
	Trinkets.TooltipType = "BAG"
	Trinkets.TooltipBag = Trinkets.BaggedTrinkets[id].bag
	Trinkets.TooltipSlot = Trinkets.BaggedTrinkets[id].slot
	Trinkets.StartTimer("TooltipUpdate", 0)
end

function Trinkets.ClearTooltip()
	GameTooltip:Hide()
	Trinkets.StopTimer("TooltipUpdate")
	Trinkets.TooltipType = nil
end

function Trinkets.AnchorTooltip(self)
	if TrinketsOptions.TooltipFollow == "ON" then
		if self.GetLeft and self:GetLeft() and self:GetLeft() < 400 then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		else
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		end
	else
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
	end
end

-- updates the tooltip created in the functions above
function Trinkets.TooltipUpdate()
	if Trinkets.TooltipType then
		local cooldown
		Trinkets.AnchorTooltip(Trinkets.TooltipOwner)
		if Trinkets.TooltipType == "BAG" then
			GameTooltip:SetBagItem(Trinkets.TooltipBag, Trinkets.TooltipSlot)
			cooldown = Trinkets.GetContainerItemCooldown(Trinkets.TooltipBag, Trinkets.TooltipSlot)
		else
			GameTooltip:SetInventoryItem("player", Trinkets.TooltipSlot)
			cooldown = GetInventoryItemCooldown("player", Trinkets.TooltipSlot)
		end
		Trinkets.ShrinkTooltip(Trinkets.TooltipOwner) -- if TinyTooltips on, shrink it
		if Trinkets.TooltipType == "INVENTORY" and Trinkets.TooltipBag then
			GameTooltip:AddLine("Queued: "..Trinkets.TooltipBag)
		end
		GameTooltip:Show()
		if cooldown == 0 then
			-- stop updates if this trinket has no cooldown
			Trinkets.TooltipType = nil
			Trinkets.StopTimer("TooltipUpdate")
		end
	end

end

-- normal tooltip for options
function Trinkets.OnTooltip(self, line1, line2)
	if TrinketsOptions.ShowTooltips == "ON" then
		Trinkets.AnchorTooltip(self)
		if line1 then
			GameTooltip:AddLine(line1)
			GameTooltip:AddLine(line2, .8, .8, .8, 1)
			GameTooltip:Show()
		else
			local name = self:GetName() or ""
			for i = 1, #Trinkets.CheckOptInfo do
				if name == "Trinkets_Opt"..Trinkets.CheckOptInfo[i][1] and Trinkets.CheckOptInfo[i][3] then
					Trinkets.OnTooltip(self, Trinkets.CheckOptInfo[i][3], Trinkets.CheckOptInfo[i][4])
				end
			end
			for i = 1, #Trinkets.TooltipInfo do
				if Trinkets.TooltipInfo[i][1] == name and Trinkets.TooltipInfo[i][2] then
					Trinkets.OnTooltip(self, Trinkets.TooltipInfo[i][2], Trinkets.TooltipInfo[i][3])
				end
			end
		end
	end
end

-- strip format reordering in global strings
Trinkets.ITEM_SPELL_CHARGES = string.gsub(ITEM_SPELL_CHARGES, "%%%d%$d", "%%d")

function Trinkets.ShrinkTooltip(owner)
	if TrinketsOptions.TinyTooltips == "ON" then
		local r, g, b = GameTooltipTextLeft1:GetTextColor()
		local name = GameTooltipTextLeft1:GetText()
		local line, cooldown, charge
		for i = 2, GameTooltip:NumLines() do
			line = _G["GameTooltipTextLeft"..i]
			if line:IsVisible() then
				line = line:GetText() or ""
				if string.find(line, COOLDOWN_REMAINING) then
					cooldown = line
				end
				if string.find(line, Trinkets.ITEM_SPELL_CHARGES) then
					charge = line
				end
			end
		end
		Trinkets.AnchorTooltip(owner)
		GameTooltip:AddLine(name, r, g, b)
		GameTooltip:AddLine(charge, 1, 1, 1)
		GameTooltip:AddLine(cooldown, 1, 1, 1)
	end
end

-- returns 1 if the item at bag(,slot) is an engineered trinket
function Trinkets.IsEngineered(bag, slot)
	local item = slot and Trinkets.GetContainerItemLink(bag, slot) or GetInventoryItemLink("player", bag)
	if item then
		local _, _, _, _, _, itemType, itemSubtype, _, itemLoc = GetItemInfo(item)
		if itemType == Trinkets.TRADE_GOODS and itemSubtype == Trinkets.DEVICES and itemLoc == "INVTYPE_TRINKET" then
			return 1
		end
		Trinkets_TooltipScan:SetOwner(WorldFrame, "ANCHOR_NONE")
		Trinkets_TooltipScan:SetHyperlink(item)
		for i = 1, Trinkets_TooltipScan:NumLines() do
			if string.match(_G["Trinkets_TooltipScanTextLeft"..i]:GetText() or "", Trinkets.REQUIRES_ENGINEERING) then
				return 1
			end
		end
	end
end

-- returns bag,slot of a free bag space, if one found.  engineering true if only looking for an engineering bag
function Trinkets.FindSpace(engineering)
	local bagType
	for i = 4, 0, -1 do
		bagType = (select(7, GetItemInfo(GetInventoryItemLink("player", 19 + i) or "")))
		if (engineering and bagType == Trinkets.ENGINEERING_BAG) or (not engineering and bagType == Trinkets.BAG) then
			for j = 1, Trinkets.GetContainerNumSlots(i) do
				if not Trinkets.GetContainerItemLink(i, j) then
					return i, j
				end
			end
		end
	end
end

--[[ Combat Queue ]]

function Trinkets.EquipTrinketByName(name, slot)
	if not name then
		return
	end
	if UnitAffectingCombat("player") or Trinkets.IsPlayerReallyDead() or (IsRetail and C_PetBattles.IsInBattle() or false) then
		-- queue trinket
		local queue = Trinkets.CombatQueue
		local which = slot - 13 -- 0 or 1
		if queue[which] == name then
			queue[which] = nil
		elseif queue[1 - which] == name then
			queue[1 - which] = nil
			queue[which] = name
		else
			queue[which] = name
		end
	elseif not CursorHasItem() and not SpellIsTargeting() then
		local _, b, s = Trinkets.FindItem(name)
		if b then
			if not Trinkets.GetContainerItemInfo(b, s).isLocked and not IsInventoryItemLocked(slot) then
				-- neither container item nor inventory item locked, perform swap
				local directSwap = true -- assume a direct swap will happen
				if (select(7, GetItemInfo(GetInventoryItemLink("player", 19 + b) or ""))) == Trinkets.ENGINEERING_BAG then
					-- incoming trinket is in an engineering bag
					if not Trinkets.IsEngineered(slot) then
						-- outgoing trinket can't go inside it
						local freeBag,freeSlot = Trinkets.FindSpace()
						if freeBag then
							PickupInventoryItem(slot)
							Trinkets.PickupContainerItem(freeBag, freeSlot)
							Trinkets.PickupContainerItem(b, s)
							EquipCursorItem(slot)
							directSwap = nil
						end
					end
				elseif Trinkets.IsEngineered(slot) and not Trinkets.IsEngineered(b, s) then
					-- outgoing trinket is engineered, incoming trinket is not
					local freeBag, freeSlot = Trinkets.FindSpace(1)
					if freeBag then
						-- move outgoing trinket to engineering bag, equip incoming trinket
						PickupInventoryItem(slot)
						Trinkets.PickupContainerItem(freeBag, freeSlot)
						Trinkets.PickupContainerItem(b, s)
						EquipCursorItem(slot)
						directSwap = nil
					end
				end
				if directSwap then
					Trinkets.PickupContainerItem(b, s)
					PickupInventoryItem(slot)
				end
				_G["Trinkets_Trinket"..(slot - 13).."Icon"]:SetDesaturated(true)
				Trinkets.StartTimer("UpdateWornTrinkets") -- in case it's not equipped (stunned, etc)
			end
		end
	end
	Trinkets.UpdateCombatQueue()
end

function Trinkets.UpdateCombatQueue()
	local _, bag, slot
	for which = 0, 1 do
		local trinket = Trinkets.CombatQueue[which]
		local icon = _G["Trinkets_Trinket"..which.."Queue"]
		icon:Hide()
		if trinket then
			_, bag, slot = Trinkets.FindItem(trinket)
			if bag then
				icon:SetTexture(Trinkets.GetContainerItemInfo(bag, slot).iconFileID)
				icon:Show()
			end
		elseif Trinkets.QueueInit and TrinketsQueue and TrinketsQueue.Enabled[which] then
			icon:SetTexture("Interface\\AddOns\\Trinkets\\Textures\\Trinkets-Gear")
			icon:Show()
		end
	end
end

--[[ Notify ]]

function Trinkets.Notify(msg)
	PlaySound(4146)
	if MikSBT then -- send via MSBT if it exists
		MikSBT.DisplayMessage(msg, "Notification", true, 255, 0, 0, nil, nil, nil, nil)
	elseif SCT_Display then -- send via SCT if it exists
		SCT_Display(msg, {r = .2, g = .7, b = .9})
	elseif Parrot then -- send via Parrot if it exists
		Parrot:ShowMessage(msg, "Notification", true, 255, 0, 0, nil, nil, nil, nil)
	elseif xCT then -- send via xCT if it exists
		ct.frames[3]:AddMessage(msg, 255, 0, 0)
	elseif xCT_Plus then -- send via xCT+ if it exists
		xCT_Plus:AddMessage("general", msg, {1, 0, 0})
	elseif SHOW_COMBAT_TEXT == "1" and CombatText_AddMessage then -- or default UI's SCT
		CombatText_AddMessage(msg, CombatText_StandardScroll, .2, .7, .9)
	else
		-- send vis UIErrorsFrame if neither SCT exists
		UIErrorsFrame:AddMessage(msg, .2, .7, .9, 1, UIERRORS_HOLD_TIME)
	end
	if TrinketsOptions.NotifyChatAlso == "ON" then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33b2e5"..msg)
	end
end

function Trinkets.CooldownUpdate()
	local inv, bag, slot, start, duration, name, remain
	for i in pairs(TrinketsPerOptions.ItemsUsed) do
		start, duration = Trinkets.GetItemCooldown(i)
		if start and TrinketsPerOptions.ItemsUsed[i] < 3 then
			TrinketsPerOptions.ItemsUsed[i] = TrinketsPerOptions.ItemsUsed[i] + 1 -- count for 3 seconds before seeing if this is a real cooldown
		elseif start then
			if start > 0 then
				remain = duration - (GetTime() - start)
				if TrinketsPerOptions.ItemsUsed[i] < 5 then
					if remain > 29 then
						TrinketsPerOptions.ItemsUsed[i] = 30 -- first actual cooldown greater than 30 seconds, tag it for 30+0 notify
					elseif remain > 5 then
						TrinketsPerOptions.ItemsUsed[i] = 5 -- first actual cooldown less than 30 but greater than 5, tag for 0 notify
					end
				end
			end
			if TrinketsPerOptions.ItemsUsed[i] == 30 and start > 0 and remain < 30 then
				if TrinketsOptions.NotifyThirty == "ON" then
					name = GetItemInfo(i)
					if name then
						Trinkets.Notify(name.." ready soon!")
					end
				end
				TrinketsPerOptions.ItemsUsed[i] = 5 -- tag for just 0 notify now
			elseif TrinketsPerOptions.ItemsUsed[i] == 5 and start == 0 then
				if TrinketsOptions.Notify == "ON" then
					name = GetItemInfo(i)
					if name then
						Trinkets.Notify(name.." ready!")
					end
				end
			end
			if start == 0 then
				TrinketsPerOptions.ItemsUsed[i] = nil
			end
		end
	end
	-- update cooldown numbers
	if TrinketsOptions.CooldownCount == "ON" then
		if Trinkets_MainFrame:IsVisible() then
			Trinkets.WriteWornCooldowns()
		end
		if Trinkets_MenuFrame:IsVisible() then
			Trinkets.WriteMenuCooldowns()
		end
	end
end

function Trinkets.QueueUpdate()
	if Trinkets.PeriodicQueueCheck then
		Trinkets.PeriodicQueueCheck()
	end
end

function Trinkets.WriteWornCooldowns()
	local start, duration
	start, duration = GetInventoryItemCooldown("player", 13)
	Trinkets.WriteCooldown(Trinkets_Trinket0Time, start, duration)
	start, duration = GetInventoryItemCooldown("player", 14)
	Trinkets.WriteCooldown(Trinkets_Trinket1Time, start, duration)
end

function Trinkets.WriteMenuCooldowns()
	local start, duration
	for i = 1, Trinkets.NumberOfTrinkets do
		start, duration = Trinkets.GetContainerItemCooldown(Trinkets.BaggedTrinkets[i].bag, Trinkets.BaggedTrinkets[i].slot)
		Trinkets.WriteCooldown(_G["Trinkets_Menu"..i.."Time"], start, duration)
	end
end

function Trinkets.WriteCooldown(where, start, duration)
	local cooldown = duration - (GetTime() - start)
	if start == 0 or TrinketsOptions.CooldownCount == "OFF" then
		where:SetText("")
	elseif cooldown < 3 and not where:GetText() then
		-- this is a global cooldown. don't display it. not accurate but at least not annoying
	else
		where:SetText((cooldown < 60 and math.floor(cooldown + .5).." s") or (cooldown < 3600 and math.ceil(cooldown / 60).." m") or math.ceil(cooldown / 3600).." h")
	end
end

function Trinkets.OnShow()
	TrinketsPerOptions.Visible = "ON"
	if TrinketsOptions.KeepOpen == "ON" then
		Trinkets.BuildMenu()
	end
end

function Trinkets.OnHide()
	Trinkets_MenuFrame:Hide()
	TrinketsPerOptions.Visible = "OFF"
end

function Trinkets.ReflectAlpha()
	Trinkets_MainFrame:SetAlpha(TrinketsPerOptions.Alpha)
	Trinkets_MenuFrame:SetAlpha(TrinketsPerOptions.Alpha)
end

--[[ Key bindings ]]

function Trinkets.KeyBindingsChanged()
	if TrinketsOptions.ShowHotKeys == "ON" then
		local key
		for i = 0, 1 do
			key = GetBindingKey("CLICK Trinkets_Trinket"..i..":LeftButton")
			_G["Trinkets_Trinket"..i.."HotKey"]:SetText(GetBindingText(key or "", nil, 1))
		end
	else
		Trinkets_Trinket0HotKey:SetText("")
		Trinkets_Trinket1HotKey:SetText("")
	end
end

--[[ Monitor Range ]]

--[[function Trinkets.ReflectRedRange()
	if TrinketsOptions.RedRange == "ON" then
		Trinkets.StartTimer("RedRange")
	else
		Trinkets.StopTimer("RedRange")
		Trinkets_Trinket0Icon:SetVertexColor(1, 1, 1)
		Trinkets_Trinket1Icon:SetVertexColor(1, 1, 1)
	end
end

function Trinkets.RedRangeUpdate()
	local item
	for i = 13, 14 do
		item = GetInventoryItemLink("player", i)
		if item and C_Item.IsItemInRange(item, "target") == 0 then
			_G["Trinkets_Trinket"..(i - 13).."Icon"]:SetVertexColor(1, .3, .3)
		else
			_G["Trinkets_Trinket"..(i - 13).."Icon"]:SetVertexColor(1, 1, 1)
		end
	end
end]]
