--[[ TrinketsOpt.lua : Options and sort window for Trinkets ]]

local _G, math, string, table = _G, math, string, table

local IsRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

Trinkets.CheckOptInfo = {
	{"ShowIcon", "ON", "Minimap Button", "Show or hide minimap button."},
	{"SquareMinimap", "OFF", "Square Minimap", "Move minimap button as if around a square minimap.", "ShowIcon"},
	{"CooldownCount", "OFF", "Cooldown Numbers", "Display time remaining on cooldowns ontop of the button."},
	{"CooldownCountBlizzard", "OFF", "Blizzard Cooldowns", "Display time remaining on cooldowns ontop of the button."},
	{"CooldownCountOmniCC", "OFF", "OmniCC Cooldowns", "Display time remaining on cooldowns ontop of the button."},
	{"TooltipFollow", "OFF", "At Mouse", "Display all tooltips near the mouse.", "ShowTooltips"},
	{"KeepOpen", "OFF", "Keep Menu Open", "Keep menu open at all times."},
	{"KeepDocked", "ON", "Keep Menu Docked", "Keep menu docked at all times."},
	{"Notify", "OFF", "Notify When Ready", "Sends an overhead notification when a trinket's cooldown is complete."},
	{"DisableToggle", "OFF", "Disable Toggle", "Disables the minimap button's ability to toggle the trinket frame.", "ShowIcon"},
	{"NotifyChatAlso", "OFF", "Notify Chat Also", "Sends notifications through chat also."},
	{"Locked", "OFF", "Lock Windows", "Prevents the windows from being moved, resized or rotated."},
	{"ShowTooltips", "ON", "Show Tooltips", "Shows tooltips."},
	{"NotifyThirty", "ON", "Notify At 30 sec", "Sends an overhead notification when a trinket has 30 seconds left on cooldown."},
	{"MenuOnShift", "OFF", "Menu On Shift", "Check this to prevent the menu appearing unless Shift is held."},
	{"TinyTooltips", "OFF", "Tiny Tooltips", "Shrink trinket tooltips to only their name, charges and cooldown.", "ShowTooltips"},
	{"SetColumns", "OFF", "Wrap at: ", "Define how many trinkets before the menu will wrap to the next row.\n\nUncheck to let Trinkets choose how to wrap the menu."},
	{"LargeCooldown", "ON", "Large Numbers", "Display the cooldown time in a larger font.", "CooldownCount"},
	{"ShowHotKeys", "ON", "Show Key Bindings", "Display the key bindings over the equipped trinkets."},
	{"StopOnSwap", "OFF", "Stop Queue On Swap", "Swapping a passive trinket stops an auto queue.  Check this to also stop the auto queue when a clickable trinket is manually swapped in via Trinkets.  This will have the most use to those with frequent trinkets marked Priority."},
	{"HideOnLoad", "OFF", "Close On Profile Load", "Check this to dismiss this window when you load a profile."},
	{"RedRange", "OFF", "Red Out of Range", "Check this to red out worn trinkets that are out of range to a valid target.  ie, Gnomish Death Ray and Gnomish Net-O-Matic."},
	{"HidePetBattle", "ON", "Hide in Pet Battles", "Check this auto hide the frame while in a pet battle."},
	{"MenuOnRight", "OFF", "Menu On Right-Click", "Check this to prevent the menu from appearing until either worn trinket is right-clicked.\n\nNOTE: This setting CANNOT be changed while in combat."}
}

Trinkets.TooltipInfo = {
	{"Trinkets_LockButton", "Lock Windows", "Prevents the windows from being moved, resized or rotated."},
	{"Trinkets_Trinket0Check", "Top Trinket Auto Queue", "Check this to enable auto queue for this trinket slot.  You can also Alt+Click the trinket slot to toggle Auto Queue."},
	{"Trinkets_Trinket1Check", "Bottom Trinket Auto Queue", "Check this to enable auto queue for this trinket slot.  You can also Alt+Click the trinket slot to toggle Auto Queue."},
	{"Trinkets_SortPriority", "High Priority", "When checked, this trinket will be swapped in as soon as possible, whether the equipped trinket is on cooldown or not.\n\nWhen unchecked, this trinket will not equip over one already worn that's not on cooldown."},
	{"Trinkets_SortDelay", "Swap Delay", "This is the time (in seconds) before a trinket will be swapped out.  ie, for Earthstrike you want 20 seconds to get the full 20 second effect of the buff."},
	{"Trinkets_SortKeepEquipped", "Pause Queue", "Check this to suspend the auto queue while this trinket is equipped. ie, for Carrot on a Stick if you have a mod to auto-equip it to a slot with Auto Queue active."},
	{"Trinkets_Profiles", "Profiles", "Here you can load or save auto queue profiles."},
	{"Trinkets_Delete", "Delete", "Remove this trinket from the list.  Trinkets further down the list don't affect performance at all.  This option is merely to keep the list managable. Note: Trinkets in your bags will return to end of the list."},
	{"Trinkets_ProfilesDelete", "Delete Profile", "Remove this profile."},
	{"Trinkets_ProfilesLoad", "Load Profile", "Load a queue order for the selected trinket slot.  You can double-click a profile to load it also."},
	{"Trinkets_ProfilesSave", "Save Profile", "Save the queue order from the selected trinket slot.  Either trinket slot can use saved profiles."},
	{"Trinkets_ProfileName", "Profile Name", "Enter a name to call the profile.  When saved, you can load this profile to either trinket slot."}
}

function Trinkets.InitOptions()
	Trinkets.CreateTimer("DragMinimapButton", Trinkets.DragMinimapButton, 0, 1)
	Trinkets.MoveMinimapButton()
	local item
	for i = 1, #Trinkets.CheckOptInfo do
		item = _G["Trinkets_Opt"..Trinkets.CheckOptInfo[i][1].."Text"]
		if item then
			item:SetText(Trinkets.CheckOptInfo[i][3])
			item:SetTextColor(.95, .95, .95)
		end
	end
	Trinkets.Tab_OnClick(1)
	table.insert(UISpecialFrames, "Trinkets_OptFrame")
	Trinkets_Title:SetText("Trinkets "..Trinkets_Version)
	Trinkets_OptFrame:SetBackdropBorderColor(.3, .3, .3, 1)
	Trinkets_SubOptFrame:SetBackdropBorderColor(.3, .3, .3, 1)
	if Trinkets.QueueInit then
		Trinkets.QueueInit()
		Trinkets_Tab1:Show()
		Trinkets_OptFrame:SetHeight(356)
		Trinkets_SubOptFrame:SetPoint("TOPLEFT", Trinkets_OptFrame, "TOPLEFT", 8, - 50)
	else
		Trinkets_OptStopOnSwap:Hide() -- remove StopOnSwap option if queue not loaded
		Trinkets_Tab1:Hide() -- hide options tab if it's only tab
		Trinkets_OptFrame:SetHeight(300)
		Trinkets_SubOptFrame:SetPoint("TOPLEFT", Trinkets_OptFrame, "TOPLEFT", 8, - 24)
	end
	Trinkets_OptColumnsSlider:SetValue(TrinketsOptions.Columns)
	Trinkets_OptColumnsSliderText:SetText(TrinketsOptions.Columns.." trinkets")
	Trinkets_OptMainScaleSlider:SetValue(TrinketsPerOptions.MainScale)
	Trinkets_OptMenuScaleSlider:SetValue(TrinketsPerOptions.MenuScale)
	Trinkets.ReflectLock()
	Trinkets.ReflectCooldownFont()
	Trinkets.KeyBindingsChanged()
end

function Trinkets.ToggleFrame(frame)
	if frame:IsVisible() then
		frame:Hide()
	else
		frame:Show()
	end
end

function Trinkets.OptFrame_OnShow()
	Trinkets.ValidateChecks()
	if Trinkets.CurrentlySorting then
		Trinkets.PopulateSort(Trinkets.CurrentlySorting)
	end
end

function Trinkets.MoveMinimapButton()
	local xpos, ypos
	if TrinketsOptions.SquareMinimap == "ON" then
		xpos = 110 * cos(TrinketsOptions.IconPos or 0)
		ypos = 110 * sin(TrinketsOptions.IconPos or 0)
		xpos = math.max(- 82, math.min(xpos, 84))
		ypos = math.max(- 86, math.min(ypos, 82))
	else
		local radius = IsRetail and 102 or 80
		xpos = radius * cos(TrinketsOptions.IconPos or 0)
		ypos = radius * sin(TrinketsOptions.IconPos or 0)
	end
	if IsRetail then
		Trinkets_IconFrame:SetPoint("TOPLEFT", "Minimap", "TOPLEFT", 82 - xpos, ypos - 84)
	else
		Trinkets_IconFrame:SetPoint("TOPLEFT", "Minimap", "TOPLEFT", 52 - xpos, ypos - 52)
	end
	if TrinketsOptions.ShowIcon == "ON" then
		Trinkets_IconFrame:Show()
	else
		Trinkets_IconFrame:Hide()
	end
end

function Trinkets.DragMinimapButton()
	local xpos, ypos = GetCursorPosition()
	local xmin, ymin = Minimap:GetLeft() or 400, Minimap:GetBottom() or 400
	xpos = xmin - xpos / Minimap:GetEffectiveScale() + 70
	ypos = ypos / Minimap:GetEffectiveScale() - ymin - 70
	TrinketsOptions.IconPos = math.deg(math.atan2(ypos, xpos))
	Trinkets.MoveMinimapButton()
end

function Trinkets.MinimapButton_OnClick(button)
	PlaySound(825)
	if IsShiftKeyDown() then
		TrinketsOptions.Locked = TrinketsOptions.Locked == "ON" and "OFF" or "ON"
		Trinkets.ReflectLock()
	elseif IsAltKeyDown() and Trinkets.QueueInit then
		if button == "LeftButton" then
			TrinketsQueue.Enabled[0] = not TrinketsQueue.Enabled[0] and 1 or nil
		elseif button == "RightButton" then
			TrinketsQueue.Enabled[1] = not TrinketsQueue.Enabled[1] and 1 or nil
		end
		Trinkets.ReflectQueueEnabled()
		Trinkets.UpdateCombatQueue()
	else
		if button == "LeftButton" and TrinketsOptions.DisableToggle == "OFF" then
			Trinkets.ToggleFrame(Trinkets_MainFrame)
		else
			Trinkets.ToggleFrame(Trinkets_OptFrame)
		end
	end
end

function Trinkets.ValidateChecks()
	local check, button
	for i = 1, #Trinkets.CheckOptInfo do
		check = Trinkets.CheckOptInfo[i]
		button = _G["Trinkets_Opt"..check[1]]
		if button then
			button:SetChecked(TrinketsOptions[check[1]] == "ON")
			if check[5] then
				if TrinketsOptions[check[5]] == "ON" then
					button:Enable()
					_G["Trinkets_Opt"..check[1].."Text"]:SetTextColor(.95, .95, .95)
				else
					button:Disable()
					_G["Trinkets_Opt"..check[1].."Text"]:SetTextColor(.5, .5, .5)
				end
			end
		end
	end
	Trinkets_OptColumnsSlider:SetAlpha((TrinketsOptions.SetColumns == "ON") and 1 or .5)
	Trinkets_OptColumnsSlider:EnableMouse((TrinketsOptions.SetColumns == "ON") and 1 or 0)
	Trinkets_OptColumnsSlider:SetValue(TrinketsOptions.Columns)
end

function Trinkets.OptColumnsSlider_OnValueChanged(self, value)
	if not self._onsetting then
		self._onsetting = true
		self:SetValue(self:GetValue())
		value = self:GetValue()
		self._onsetting = false
	else
		return
	end
	if TrinketsOptions then
		TrinketsOptions.Columns = self:GetValue()
		Trinkets_OptColumnsSliderText:SetText(TrinketsOptions.Columns.." trinkets")
		if Trinkets_MenuFrame:IsVisible() then
			Trinkets.BuildMenu()
		end
	end
end

function Trinkets.OptMainScaleSlider_OnValueChanged(self, value)
	if not self._onsetting then
		self._onsetting = true
		self:SetValue(self:GetValue())
		value = self:GetValue()
		self._onsetting = false
	else
		return
	end
	if TrinketsPerOptions then
		TrinketsPerOptions.MainScale = self:GetValue()
		Trinkets_OptMainScaleSliderText:SetText(format("Main Scale: %.2f", TrinketsPerOptions.MainScale))
		Trinkets_MainFrame:SetScale(TrinketsPerOptions.MainScale)
	end
end

function Trinkets.OptMenuScaleSlider_OnValueChanged(self, value)
	if not self._onsetting then
		self._onsetting = true
		self:SetValue(self:GetValue())
		value = self:GetValue()
		self._onsetting = false
	else
		return
	end
	if TrinketsPerOptions then
		TrinketsPerOptions.MenuScale = self:GetValue()
		Trinkets_OptMenuScaleSliderText:SetText(format("Menu Scale: %.2f", TrinketsPerOptions.MenuScale))
		Trinkets_MenuFrame:SetScale(TrinketsPerOptions.MenuScale)
	end
end

function Trinkets.SliderOnMouseWheel(self, delta)
	if delta > 0 then
		self:SetValue(self:GetValue() + self:GetValueStep())
	else
		self:SetValue(self:GetValue() - self:GetValueStep())
	end
end

function Trinkets.CheckButton_OnClick(self)
	local _, _, var = string.find(self:GetName(), "Trinkets_Opt(.+)")
	if TrinketsOptions[var] then
		TrinketsOptions[var] = self:GetChecked() and "ON" or "OFF"
		PlaySound(self:GetChecked() and 856 or 857)
		Trinkets.ValidateChecks()
	end
	if self == Trinkets_OptCooldownCount then
		Trinkets.WriteWornCooldowns()
		Trinkets.WriteMenuCooldowns()
	elseif self == Trinkets_OptCooldownCountBlizzard then
		if Trinkets_Trinket0 and Trinkets_Trinket0.cooldown then
			if TrinketsOptions.CooldownCountBlizzard == "ON" then
				Trinkets_Trinket0.cooldown:SetHideCountdownNumbers(false)
			else
				Trinkets_Trinket0.cooldown:SetHideCountdownNumbers(true)
			end
		end
		if Trinkets_Trinket1 and Trinkets_Trinket1.cooldown then
			if TrinketsOptions.CooldownCountBlizzard == "ON" then
				Trinkets_Trinket1.cooldown:SetHideCountdownNumbers(false)
			else
				Trinkets_Trinket1.cooldown:SetHideCountdownNumbers(true)
			end
		end
		for i = 1, Trinkets.MaxTrinkets do
			local menuButton = _G["Trinkets_Menu"..i]
			if menuButton and menuButton.cooldown then
				if TrinketsOptions.CooldownCountBlizzard == "ON" then
					menuButton.cooldown:SetHideCountdownNumbers(false)
				else
					menuButton.cooldown:SetHideCountdownNumbers(true)
				end
			end
		end
	elseif self == Trinkets_OptCooldownCountOmniCC then
		if Trinkets_Trinket0 and Trinkets_Trinket0.cooldown then
			if TrinketsOptions.CooldownCountOmniCC == "ON" then
				Trinkets_Trinket0.cooldown.noCooldownCount = false
			else
				Trinkets_Trinket0.cooldown.noCooldownCount = true
			end
		end
		if Trinkets_Trinket1 and Trinkets_Trinket1.cooldown then
			if TrinketsOptions.CooldownCountOmniCC == "ON" then
				Trinkets_Trinket1.cooldown.noCooldownCount = false
			else
				Trinkets_Trinket1.cooldown.noCooldownCount = true
			end
		end
		for i = 1, Trinkets.MaxTrinkets do
			local menuButton = _G["Trinkets_Menu"..i]
			if menuButton and menuButton.cooldown then
				if TrinketsOptions.CooldownCountOmniCC == "ON" then
					menuButton.cooldown.noCooldownCount = false
				else
					menuButton.cooldown.noCooldownCount = true
				end
			end
		end
	elseif self == Trinkets_OptLocked then
		Trinkets.DockWindows()
		Trinkets.ReflectLock()
	elseif self == Trinkets_OptKeepOpen or self == Trinkets_OptSetColumns then
		if TrinketsOptions.KeepOpen == "ON" then
			Trinkets.BuildMenu()
		end
	elseif self == Trinkets_OptKeepDocked then
		Trinkets.DockWindows()
	elseif self == Trinkets_OptLargeCooldown then
		Trinkets.ReflectCooldownFont()
	elseif self == Trinkets_OptSquareMinimap then
		Trinkets.MoveMinimapButton()
	elseif self == Trinkets_OptShowHotKeys then
		Trinkets.KeyBindingsChanged()
	elseif self == Trinkets_OptShowIcon then
		Trinkets.MoveMinimapButton()
	--[[elseif self == Trinkets_OptRedRange then
		Trinkets.ReflectRedRange()]]
	elseif self == Trinkets_OptMenuOnRight then
		Trinkets.ReflectMenuOnRight()
	elseif self == Trinkets_OptNotify or self == Trinkets_OptNotifyThirty then
		if Trinkets_OptNotify:GetChecked() or Trinkets_OptNotifyThirty:GetChecked() then
			Trinkets.StartTimer("CooldownUpdate")
		elseif not Trinkets_OptNotify:GetChecked() and not Trinkets_OptNotifyThirty:GetChecked() then
			Trinkets.StopTimer("CooldownUpdate")
		end
	end
end

function Trinkets.ReflectLock()
	local c = TrinketsOptions.Locked == "ON" and 0 or .5
	Trinkets_OptFrame:SetBackdropBorderColor(c, c, c, 1)
	Trinkets_MainFrame:SetBackdropColor(c, c, c, c)
	Trinkets_MainFrame:SetBackdropBorderColor(c, c, c, c * 2)
	Trinkets_MenuFrame:SetBackdropColor(c, c, c, c)
	Trinkets_MenuFrame:SetBackdropBorderColor(c, c, c, c * 2)
	Trinkets_MenuFrame:EnableMouse(c * 2)
	if TrinketsOptions.Locked == "ON" then
		Trinkets_OptLocked:SetChecked(true)
	else
		Trinkets_OptLocked:SetChecked(false)
	end
	local normalTexture = Trinkets_LockButton:GetNormalTexture()
	local pushedTexture = Trinkets_LockButton:GetPushedTexture()
	if c == 0 then
		normalTexture:SetTexCoord(.875, 1, .125, .25)
		pushedTexture:SetTexCoord(.75, .875, .125, .25)
	else
		normalTexture:SetTexCoord(.75, .875, .125, .25)
		pushedTexture:SetTexCoord(.875, 1, .125, .25)
	end
end

function Trinkets.ReflectCooldownFont()
	Trinkets.SetCooldownFont("Trinkets_Trinket0")
	Trinkets.SetCooldownFont("Trinkets_Trinket1")
	for i = 1, 30 do
		Trinkets.SetCooldownFont("Trinkets_Menu"..i)
	end
end

function Trinkets.SetCooldownFont(button)
	local item = _G[button.."Time"]
	if TrinketsOptions.LargeCooldown == "ON" then
		item:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
		item:SetTextColor(1, .82, 0, 1)
		item:ClearAllPoints()
		item:SetPoint("CENTER", button, "CENTER")
	else
		item:SetFont("Fonts\\ARIALN.TTF", 14, "OUTLINE")
		item:SetTextColor(1, 1, 1, 1)
		item:ClearAllPoints()
		item:SetPoint("BOTTOM", button, "BOTTOM")
	end
end

function Trinkets.SmallButton_OnClick(self)
	PlaySound(856)
	if self == Trinkets_CloseButton then
		Trinkets_OptFrame:Hide()
	elseif self == Trinkets_LockButton then
		TrinketsOptions.Locked = (TrinketsOptions.Locked == "ON") and "OFF" or "ON"
		Trinkets.DockWindows()
		Trinkets.ReflectLock()
	end
end

function Trinkets.Tab_OnClick(id)
	PlaySound(825)
	local tab
	if Trinkets_ProfilesFrame then
		Trinkets_ProfilesFrame:Hide()
	end
	for i = 1, 3 do
		tab = _G["Trinkets_Tab"..i]
		if tab then
			tab:UnlockHighlight()
		end
	end
	_G["Trinkets_Tab"..id]:LockHighlight()
	if id == 1 then
		Trinkets_SubOptFrame:Show()
		if Trinkets_SubQueueFrame then
			Trinkets_SubQueueFrame:Hide()
		end
	else
		Trinkets_SubOptFrame:Hide()
		Trinkets_SubQueueFrame:Show()
		Trinkets.OpenSort(3 - id)
	end
end
