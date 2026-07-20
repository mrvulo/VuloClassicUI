--[[ TrinketsQueue : auto queue system ]]

local _G, type, string, tonumber, table, pairs, select = _G, type, string, tonumber, table, pairs, select

local _vui = _G.VuloClassicUI
local IsClassic = (_vui and _vui.isClassic) or (WOW_PROJECT_ID and WOW_PROJECT_ID >= WOW_PROJECT_CLASSIC) or false

Trinkets.PausedQueue = { }

local TRINKET_KEEP_BUFF_AFTER_SWAP = {
	[19341] = true,
}

function Trinkets.QueueInit()
	TrinketsQueue = TrinketsQueue or {
		Stats = { },
		Sort = { },
		Enabled = { }
	}
	TrinketsQueue.Sort[0] = TrinketsQueue.Sort[0] or { }
	TrinketsQueue.Sort[1] = TrinketsQueue.Sort[1] or { }
	Trinkets_SubQueueFrame:SetBackdropBorderColor(.3, .3, .3,1)
	Trinkets_ProfilesFrame:SetBackdropBorderColor(.3, .3, .3, 1)
	Trinkets_ProfilesListFrame:SetBackdropBorderColor(.3, .3, .3, 1)
	Trinkets_SortPriorityText:SetText("Priority")
	Trinkets_SortPriorityText:SetTextColor(.95, .95, .95)
	Trinkets_SortKeepEquippedText:SetText("Pause Queue")
	Trinkets_SortKeepEquippedText:SetTextColor(.95, .95, .95)
	Trinkets_SortListFrame:SetBackdropBorderColor(.3, .3, .3, 1)
	Trinkets.ReflectQueueEnabled()
	Trinkets.UpdateCombatQueue()
	TrinketsQueue.Profiles = TrinketsQueue.Profiles or { }
	Trinkets.ValidateProfile()
	Trinkets.OpenSort(0)
	Trinkets.OpenSort(1)
end

function Trinkets.ReflectQueueEnabled()
	Trinkets_Trinket0Check:SetChecked(TrinketsQueue.Enabled[0])
	Trinkets_Trinket1Check:SetChecked(TrinketsQueue.Enabled[1])
end

function Trinkets.OpenSort(which)
	Trinkets.CurrentlySorting = which
	Trinkets.PopulateSort(which)
	Trinkets.SortSelected = 0
	Trinkets_SortScrollScrollBar:SetValue(0)
	Trinkets.SortValidate()
	Trinkets.SortScrollFrameUpdate()
end

function Trinkets.GetID(bag, slot)
	local _, id
	if slot then
		_, _, id = string.find(Trinkets.GetContainerItemLink(bag, slot) or "", "item:(%d+)")
	else
		_, _, id = string.find(GetInventoryItemLink("player", bag) or "", "item:(%d+)")
	end
	return id
end

function Trinkets.GetNameByID(id)
	if id == 0 then
		return "-- stop queue here --", "Interface\\Buttons\\UI-GroupLoot-Pass-Up", 1
	else
		local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(id or "")
		return name, texture, quality
	end
end

function Trinkets.AddToSort(which, id)
	if not id then
		return
	end
	local found
	for i = 1, #TrinketsQueue.Sort[which] do
		found = found or TrinketsQueue.Sort[which][i] == id
	end
	if not found then
		table.insert(TrinketsQueue.Sort[which], id)
	end
end

function Trinkets.PopulateSort(which)
	TrinketsQueue.Sort[which] = TrinketsQueue.Sort[which] or { }
	Trinkets.AddToSort(which,Trinkets.GetID(which + 13))
	Trinkets.AddToSort(which,Trinkets.GetID((1 - which) + 13))
	local _, equipLoc, id
	for i = 0, 4 do
		for j = 1, Trinkets.GetContainerNumSlots(i) do
			id = Trinkets.GetID(i, j)
			_, _, _, _, _, _, _, _, equipLoc = GetItemInfo(id or "")
			if equipLoc=="INVTYPE_TRINKET" then
				Trinkets.AddToSort(which, id)
			end
		end
	end
	Trinkets.AddToSort(which, 0) -- item id 0 is the "stop queue here" marker
end

function Trinkets.SortScrollFrameUpdate()
	local offset = FauxScrollFrame_GetOffset(Trinkets_SortScroll)
	local list = TrinketsQueue.Sort[Trinkets.CurrentlySorting]
	FauxScrollFrame_Update(Trinkets_SortScroll, list and #list or 0, 9, 24)
	if list and list[1] then
		local r, g, b, found
		local texture, name, quality, idx
		local item, itemName, itemIcon
		for i = 1, 9 do
			item = _G["Trinkets_Sort"..i]
			itemName = _G["Trinkets_Sort"..i.."Name"]
			itemIcon = _G["Trinkets_Sort"..i.."Icon"]
			idx = offset + i
			if idx <= #list then
				name, texture, quality = Trinkets.GetNameByID(list[idx])
				itemIcon:SetTexture(texture)
				itemName:SetText(name)
				if quality then -- GetItemInfo may not be valid early on after patches
					r, g, b = GetItemQualityColor(quality)
					itemName:SetTextColor(r, g, b)
					itemIcon:SetVertexColor(1, 1, 1)
				end
				item:Show()
				if idx == Trinkets.SortSelected then
					Trinkets.LockHighlight(item)
				else
					Trinkets.UnlockHighlight(item)
				end
			else
				item:Hide()
			end
		end
	end
end

function Trinkets.LockHighlight(frame)
	if type(frame) == "string" then
		frame = _G[frame]
	end
	if not frame then
		return
	end
	frame.lockedHighlight = 1
	_G[frame:GetName().."Highlight"]:Show()
end

function Trinkets.UnlockHighlight(frame)
	if type(frame) == "string" then
		frame = _G[frame]
	end
	if not frame then
		return
	end
	frame.lockedHighlight = nil
	_G[frame:GetName().."Highlight"]:Hide()
end

function Trinkets.SortTooltip(self)
	local idx = FauxScrollFrame_GetOffset(Trinkets_SortScroll) + self:GetID()
	local _
	local name, itemLink = GetItemInfo(TrinketsQueue.Sort[Trinkets.CurrentlySorting][idx] or "")
	_, _, itemLink = string.find(itemLink or "","(item:%d+:%d+:%d+:%d+:%d+:%d+:%d+)")
	if itemLink and TrinketsOptions.ShowTooltips == "ON" then
		Trinkets.AnchorTooltip(self)
		GameTooltip:SetHyperlink(itemLink)
		GameTooltip:Show()
	else
		Trinkets.OnTooltip(self,"Stop Queue Here", "Move this to mark the lowest trinket to auto queue. Sometimes you may want a passive trinket with a click effect to be the end (Burst of Knowledge, Second Wind, etc).")
	end
end

function Trinkets.SortOnClick(self)
	Trinkets_SortDelay:ClearFocus()
	local idx = FauxScrollFrame_GetOffset(Trinkets_SortScroll) + self:GetID()
	if Trinkets.SortSelected == idx then
		Trinkets.SortSelected = 0
	else
		Trinkets.SortSelected = idx
	end
	Trinkets.SortScrollFrameUpdate()
	Trinkets.SortValidate()
end

function Trinkets.SortValidate()
	local selected = Trinkets.SortSelected
	local list = TrinketsQueue.Sort[Trinkets.CurrentlySorting]
	Trinkets_MoveTop:Enable()
	Trinkets_MoveUp:Enable()
	Trinkets_MoveDown:Enable()
	Trinkets_MoveBottom:Enable()
	if selected == 0 or #list < 2 then
		Trinkets_MoveTop:Disable()
		Trinkets_MoveUp:Disable()
		Trinkets_MoveDown:Disable()
		Trinkets_MoveBottom:Disable()
	elseif selected == 1 then
		Trinkets_MoveUp:Disable()
		Trinkets_MoveTop:Disable()
		Trinkets_MoveDown:Enable()
	elseif selected == #list then
		Trinkets_MoveDown:Disable()
		Trinkets_MoveBottom:Disable()
	end
	local idx = FauxScrollFrame_GetOffset(Trinkets_SortScroll)
	if selected > 0 and list[selected] and list[selected] ~= 0 then
		Trinkets_SortDelay:Show()
		Trinkets_SortPriority:Show()
		Trinkets_SortKeepEquipped:Show()
		Trinkets_Delete:Enable()
	else
		Trinkets_SortDelay:Hide()
		Trinkets_SortPriority:Hide()
		Trinkets_SortKeepEquipped:Hide()
		Trinkets_Delete:Disable()
	end
	local stats = TrinketsQueue.Stats[list[Trinkets.SortSelected]]
	Trinkets_SortDelay:SetText(stats and (stats.delay or "0") or "0")
	Trinkets_SortPriority:SetChecked(stats and stats.priority)
	Trinkets_SortKeepEquipped:SetChecked(stats and stats.keep)
	if not IsShiftKeyDown() and selected > 0 then
		local parent = Trinkets_SortScrollScrollBar
		local offset
		if selected <= idx then
			offset = (selected == 1) and 0 or (parent:GetValue() - (parent:GetHeight() / 2))
			parent:SetValue(offset)
			PlaySound(1115)
		elseif selected >= (idx + 10) then
			offset = (selected == #list) and Trinkets_SortScroll:GetVerticalScrollRange() or (parent:GetValue() + (parent:GetHeight() / 2))
			parent:SetValue(offset)
			PlaySound(1115)
		end
	end
end

function Trinkets.SortMove(self)
	Trinkets_SortDelay:ClearFocus()
	local dir = ((self == Trinkets_MoveUp) and - 1) or ((self == Trinkets_MoveTop) and "top") or ((self == Trinkets_MoveDown) and 1) or ((self == Trinkets_MoveBottom) and "bottom")
	local list = TrinketsQueue.Sort[Trinkets.CurrentlySorting]
	local idx1 = Trinkets.SortSelected
	if dir then
		local idx2 = ((dir == "top") and 1) or ((dir == "bottom") and #list) or idx1 + dir
		local temp = list[idx1]
		if tonumber(dir) then
			list[idx1] = list[idx2]
			list[idx2] = temp
		elseif dir == "top" then
			table.remove(list, idx1)
			table.insert(list, 1, temp)
		elseif dir == "bottom" then
			table.remove(list, idx1)
			table.insert(list, temp)
		end
		Trinkets.SortSelected = idx2
	elseif self == Trinkets_Profiles then
		Trinkets.SortSelected = 0
		Trinkets.ShowProfiles(Trinkets_SortListFrame:IsVisible())
	elseif self == Trinkets_Delete then
		table.remove(list, idx1)
		Trinkets.SortSelected = 0
	end
	Trinkets.SortValidate()
	Trinkets.SortScrollFrameUpdate()
end

function Trinkets.SortDelay_OnTextChanged()
	local delay = tonumber(Trinkets_SortDelay:GetText()) or 0
	local id = TrinketsQueue.Sort[Trinkets.CurrentlySorting][Trinkets.SortSelected]
	TrinketsQueue.Stats[id] = TrinketsQueue.Stats[id] or { }
	TrinketsQueue.Stats[id].delay = delay ~= 0 and delay or nil
end

function Trinkets.SortPriority_OnClick(self)
	local check = self:GetChecked()
	local id = TrinketsQueue.Sort[Trinkets.CurrentlySorting][Trinkets.SortSelected]
	TrinketsQueue.Stats[id] = TrinketsQueue.Stats[id] or { }
	TrinketsQueue.Stats[id].priority = check
end

function Trinkets.SortKeepEquipped_OnClick(self)
	local check = self:GetChecked()
	local id = TrinketsQueue.Sort[Trinkets.CurrentlySorting][Trinkets.SortSelected]
	TrinketsQueue.Stats[id] = TrinketsQueue.Stats[id] or { }
	TrinketsQueue.Stats[id].keep = check
end

function Trinkets.TabCheck_OnClick(self)
	TrinketsQueue.Enabled[3 - self:GetID()] = self:GetChecked()
	Trinkets.UpdateCombatQueue()
end

function Trinkets.TrinketNearReady(id)
	local start, duration = Trinkets.GetItemCooldown(id)
	if start == 0 or duration - (GetTime() - start) <= 30 then
		return 1
	end
end

function Trinkets.CanCooldown(inv)
	local _, _, enable = GetInventoryItemCooldown("player", inv)
	return enable == 1
end

function Trinkets.PeriodicQueueCheck()
	if not TrinketsQueue.Enabled[0] and not TrinketsQueue.Enabled[1] then
		Trinkets.StopTimer("QueueUpdate")
		return
	end
	Trinkets.StartTimer("QueueUpdate")
	for i = 0, 1 do
		if TrinketsQueue.Enabled[i] then
			Trinkets.ProcessAutoQueue(i)
		end
	end
end

function Trinkets.ProcessAutoQueue(which)
	local _, _, id = string.find(GetInventoryItemLink("player", 13 + which) or "", "item:(%d+).+%[(.+)%]")
	if not id then
		return
	end
	local start, duration, enable = GetInventoryItemCooldown("player", 13 + which)
	local timeLeft = GetTime() - start
	local icon = _G["Trinkets_Trinket"..which.."Queue"]
	if IsInventoryItemLocked(13 + which) then
		return
	end
	if (IsClassic and (CastingInfo() or ChannelInfo())) or (not IsClassic and (UnitCastingInfo("player") or UnitChannelInfo("player"))) then
		return
	end
	if Trinkets.PausedQueue[which] then
		icon:SetVertexColor(1, .5, .5)
		return
	end
	if TrinketsQueue.Stats[id] then
		if TrinketsQueue.Stats[id].keep then
			icon:SetVertexColor(1, .5, .5)
			return
		end
		if TrinketsQueue.Stats[id].delay then
			if start > 0 and (duration - timeLeft) > 30 and timeLeft < TrinketsQueue.Stats[id].delay then
				icon:SetDesaturated(true)
				return
			end
		else
			local buffName = GetItemSpell(id)
			if buffName then
				if IsClassic then
					if not TRINKET_KEEP_BUFF_AFTER_SWAP[id] then
						local i = 1
						local buff
						while UnitAura("player", i, "HELPFUL") do
							buff = UnitAura("player", i, "HELPFUL")
							if buffName == buff or (start > 0 and (duration - timeLeft) > 30 and timeLeft < 1) then
								icon:SetDesaturated(true)
								return
							end
							i = i + 1
						end
					end
				else
					if AuraUtil.FindAuraByName(buffName, "player", "HELPFUL") or (start > 0 and (duration - timeLeft) > 30 and timeLeft < 1) then
						icon:SetDesaturated(true)
						return
					end
				end
			end
		end
	end
	icon:SetDesaturated(false)
	icon:SetVertexColor(1, 1, 1)
	local name
	local ready = Trinkets.TrinketNearReady(id)
	if ready and Trinkets.CombatQueue[which] then
		Trinkets.CombatQueue[which] = nil
		Trinkets.UpdateCombatQueue()
	end
	local list, rank = TrinketsQueue.Sort[which]
	for i = 1, #list do
		if list[i] == 0 then
			rank = i
			break
		end
		if ready and list[i] == id then
			rank = i
			break
		end
	end
	if rank then
		for i = 1, rank do
			if not ready or enable == 0 or (TrinketsQueue.Stats[list[i]] and TrinketsQueue.Stats[list[i]].priority) then
				if Trinkets.TrinketNearReady(list[i]) then
					if GetItemCount(list[i]) > 0 and not IsEquippedItem(list[i]) then
						local _, bag, slot = Trinkets.FindItem(list[i])
						if bag then
							name = GetItemInfo(list[i])
							if Trinkets.CombatQueue[which] ~= name then
								Trinkets.EquipTrinketByName(name, 13 + which)
							end
							break
						end
					end
				end
			end
		end
	end
end

-- Public macro API: SetQueue(0|1, "ON"|"OFF"|"PAUSE"|"RESUME"|"SORT", trinket names or a profile name...).
function Trinkets.SetQueue(which, ...)
	local errorstub = "|cFFBBBBBBTrinkets:|cFFFFFFFF "
	if not which or not tonumber(which) or which < 0 or which > 1 then
		DEFAULT_CHAT_FRAME:AddMessage(errorstub.."First parameter must be 0 for top trinket or 1 for bottom.")
		return
	end
	if (select("#", ...)) < 1 then
		DEFAULT_CHAT_FRAME:AddMessage(errorstub.."Second parameter is either ON, OFF, PAUSE, RESUME or the beginning of a list of trinkets in a sort order.")
		return
	end
	if Trinkets_OptFrame:IsVisible() then
		Trinkets_OptFrame:Hide()
	end
	local cmd = (select(1, ...))
	if cmd == "ON" then
		TrinketsQueue.Enabled[which] = 1
		Trinkets.PausedQueue[which] = nil
	elseif cmd == "OFF" then
		TrinketsQueue.Enabled[which] = nil
		Trinkets.PausedQueue[which] = nil
	elseif cmd == "PAUSE" then
		Trinkets.PausedQueue[which] = 1
	elseif cmd == "RESUME" then
		Trinkets.PausedQueue[which] = nil
	elseif cmd == "SORT" and (select("#",...)) > 1 then
		local inv, bag, slot
		for i in pairs(TrinketsQueue.Sort[which]) do
			TrinketsQueue.Sort[which][i] = nil
		end
		local profile = Trinkets.GetProfileID((select(2,...)))
		if profile then
			for i = 2, #TrinketsQueue.Profiles[profile] do
				table.insert(TrinketsQueue.Sort[which], TrinketsQueue.Profiles[profile][i])
			end
		else
			for i = 2, (select("#", ...)) do
				inv, bag, slot = Trinkets.FindItem((select(i, ...)), true) -- true = also search equipped slots
				if inv then
					table.insert(TrinketsQueue.Sort[which], Trinkets.GetID(inv))
				elseif bag then
					table.insert(TrinketsQueue.Sort[which], Trinkets.GetID(bag, slot))
				else
					DEFAULT_CHAT_FRAME:AddMessage(errorstub.."Trinket or profile \""..(select(i, ...)).."\" not found.")
				end
			end
			table.insert(TrinketsQueue.Sort[which], 0)
		end
	else
		DEFAULT_CHAT_FRAME:AddMessage(errorstub.." Expected ON, OFF, PAUSE, RESUME or SORT+list")
	end
	Trinkets.ReflectQueueEnabled()
	Trinkets.UpdateCombatQueue()
end

function Trinkets.GetQueue(which)
	if not which or not tonumber(which) or which < 0 or which > 1 then
		DEFAULT_CHAT_FRAME:AddMessage("|cFFBBBBBBTrinkets.GetQueue:|cFFFFFFFF Parameter must be 0 for top trinket or 1 for bottom.")
		return
	end
	local trinketList, name = { }
	for i = 1, #TrinketsQueue.Sort[which] do
		name = Trinkets.GetNameByID(TrinketsQueue.Sort[which][i])
		table.insert(trinketList, name)
	end
	return TrinketsQueue.Enabled[which], trinketList
end

-- add: "add" or "remove" the frame name in UISpecialFrames (Escape-closable).
function Trinkets.Escable(frame, add)
	local found
	for i in pairs(UISpecialFrames) do
		found = found or (UISpecialFrames[i] == frame and i)
	end
	if not found and add == "add" then
		table.insert(UISpecialFrames, frame)
	elseif found and add == "remove" then
		table.remove(UISpecialFrames, found)
	end
end

-- Trinkets_ProfilesFrame's OnHide calls this back with nil, so it must stay re-entrant-safe.
function Trinkets.ShowProfiles(show)
	local normalTexture = Trinkets_Profiles:GetNormalTexture()
	local pushedTexture = Trinkets_Profiles:GetPushedTexture()
	if show then
		Trinkets_SortListFrame:Hide()
		Trinkets_ProfilesFrame:Show()
		normalTexture:SetTexCoord(.875, 1, .25, .375)
		pushedTexture:SetTexCoord(.75, .875, .25, .375)
		Trinkets.Escable("Trinkets_ProfilesFrame", "add")
		Trinkets.Escable("Trinkets_OptFrame", "remove")
	else
		Trinkets_SortListFrame:Show()
		Trinkets_ProfilesFrame:Hide()
		pushedTexture:SetTexCoord(.875, 1, .25, .375)
		normalTexture:SetTexCoord(.75, .875, .25, .375)
		Trinkets.Escable("Trinkets_ProfilesFrame", "remove")
		Trinkets.Escable("Trinkets_OptFrame", "add")
	end
end

function Trinkets.ProfilesFrame_OnHide()
	PlaySound(624)
	Trinkets.ResetProfileSelected()
	Trinkets.ShowProfiles(nil)
end

function Trinkets.ResetProfileSelected()
	Trinkets.ProfileSelected = nil
	Trinkets_ProfileName:SetText("")
	Trinkets.ProfileScrollFrameUpdate()
	Trinkets.ValidateProfile()
end

function Trinkets.ProfileScrollFrameUpdate()
	local offset = FauxScrollFrame_GetOffset(Trinkets_ProfileScroll)
	local list = TrinketsQueue.Profiles
	FauxScrollFrame_Update(Trinkets_ProfileScroll, #(list) or 0, 7, 20)
	local item, idx
	for i = 1, 7 do
		idx = offset + i
		item = _G["Trinkets_Profile"..i]
		if idx <= #list then
			_G["Trinkets_Profile"..i.."Name"]:SetText(list[idx][1])
			item:Show()
			if Trinkets.ProfileSelected == idx then
				item:LockHighlight()
			else
				item:UnlockHighlight()
			end
		else
			item:Hide()
		end
	end
	if #list == 0 then
		Trinkets_Profile1Name:SetText("No profiles saved yet.")
		Trinkets_Profile1:Show()
		Trinkets_Profile1:UnlockHighlight()
	end

end

function Trinkets.ProfileList_OnClick(self)
	if #TrinketsQueue.Profiles > 0 then
		local idx = self:GetID() + FauxScrollFrame_GetOffset(Trinkets_ProfileScroll)
		if Trinkets.ProfileSelected == idx then
			Trinkets.ProfileSelected = nil
			Trinkets_ProfileName:SetText("")
		else
			Trinkets.ProfileSelected = idx
			Trinkets_ProfileName:SetText(TrinketsQueue.Profiles[idx][1])
		end
		Trinkets.ProfileScrollFrameUpdate()
		Trinkets.ValidateProfile()
	end
end

function Trinkets.GetProfileID(name)
	for i = 1, #TrinketsQueue.Profiles do
		if TrinketsQueue.Profiles[i][1] == name then
			return i
		end
	end
end

function Trinkets.ValidateProfile()
	local name = Trinkets_ProfileName:GetText() or ""
	Trinkets_ProfilesDelete:Disable()
	Trinkets_ProfilesLoad:Disable()
	Trinkets_ProfilesSave:Disable()
	if Trinkets.GetProfileID(name) then
		Trinkets_ProfilesDelete:Enable()
		Trinkets_ProfilesLoad:Enable()
	end
	if #name > 0 then
		Trinkets_ProfilesSave:Enable()
	end
end

function Trinkets.ProfileName_OnTextChanged()
	Trinkets.ProfileSelected = Trinkets.GetProfileID(Trinkets_ProfileName:GetText())
	Trinkets.ProfileScrollFrameUpdate()
	Trinkets.ValidateProfile()
end

function Trinkets.ProfilesButton_OnClick(self)
	local idx = Trinkets.ProfileSelected
	local name = Trinkets_ProfileName:GetText() or ""
	if self == Trinkets_ProfilesDelete then
		if idx and TrinketsQueue.Profiles[idx] then
			table.remove(TrinketsQueue.Profiles, idx)
		end
		Trinkets.ResetProfileSelected()
	elseif self == Trinkets_ProfilesSave then
		if idx and TrinketsQueue.Profiles[idx] then
			table.remove(TrinketsQueue.Profiles, idx)
		end
		table.insert(TrinketsQueue.Profiles, 1, {name})
		local list = TrinketsQueue.Sort[Trinkets.CurrentlySorting]
		local save = TrinketsQueue.Profiles[1]
		for i = 1, #list do
			table.insert(save, list[i])
			if list[i] == 0 then
				break
			end
		end
		Trinkets_ProfilesFrame:Hide()
	elseif self == Trinkets_ProfilesLoad then
		Trinkets.LoadProfile(Trinkets.CurrentlySorting, idx)
	elseif self == Trinkets_ProfilesCancel then
		Trinkets_ProfilesFrame:Hide()
	end
end

function Trinkets.ProfileList_OnDoubleClick(self)
	if #TrinketsQueue.Profiles > 0 then
		local idx = self:GetID() + FauxScrollFrame_GetOffset(Trinkets_ProfileScroll)
		if TrinketsQueue.Profiles[idx] then
			Trinkets.LoadProfile(Trinkets.CurrentlySorting, idx)
		end
	end
end

function Trinkets.LoadProfile(which, idx)
	local list = TrinketsQueue.Sort[which]
	local load = TrinketsQueue.Profiles[idx]
	for i in pairs(list) do
		list[i] = nil
	end
	for i = 2, #load do
		table.insert(list, load[i])
	end
	Trinkets_ProfilesFrame:Hide()
	Trinkets.OpenSort(which)
	if TrinketsOptions.HideOnLoad == "ON" then
		Trinkets_OptFrame:Hide()
	end
end
