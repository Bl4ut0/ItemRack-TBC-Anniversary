-- Compatibility shim for LoadAddOn (moved to C_AddOns in TBC 2.5.5+)
local LoadAddOn = LoadAddOn or (C_AddOns and C_AddOns.LoadAddOn)
-- Compatibility shim for GetItemCount (moved to C_Item, may not have global if deprecation fallbacks off)
local GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount)

ItemRack.Docking = {} -- temporary table for current docking potential

ItemRack.BracketInfo = { ["TOP"] = {36,12,.25,.75,0,.25}, -- bracket construction info
					["BOTTOM"] = {36,12,.25,.75,.75,1}, -- cx,cy,left,right,top,bottom
					["LEFT"] = {12,36,0,.25,.25,.75},
					["RIGHT"] = {12,36,.75,1,.25,.75},
					["TOPLEFT"] = {12,12,0,.25,0,.25},
					["TOPRIGHT"] = {12,12,.75,1,0,.25},
					["BOTTOMLEFT"] = {12,12,0,.25,.75,1},
					["BOTTOMRIGHT"] = {12,12,.75,1,.75,1}
				  }

ItemRack.ReflectClicked = {} -- buttons clicked (checked)
ItemRack.LockedButtons = {} -- buttons locked (desaturated)

ItemRack.NewAnchor = nil

local function IRRoundTenths(value)
	if not value then
		return 0
	end
	return math.floor(value * 10 + 0.5) / 10
end

-- Cooldown debug can fire extremely often because Blizzard refreshes item cooldowns
-- for many UI/state changes. Only print when the slot's visible cooldown state changes.
local function IRDebugCooldownState(slot, stateKey, message)
	if not (ItemRack.DebugAll or ItemRack.DebugTags.Cooldown) then
		return
	end
	ItemRack.CooldownDebugLast = ItemRack.CooldownDebugLast or {}
	if ItemRack.CooldownDebugLast[slot] == stateKey then
		return
	end
	ItemRack.CooldownDebugLast[slot] = stateKey
	ItemRack.Debug("Cooldown", message)
end

function ItemRack.ButtonOnLoad(self)
	local name = self:GetName()
	self.OriginalSetChecked = self.SetChecked
	self.icon = _G[name.."ItemRackIcon"]
	self.Icon = self.icon
	self.Count = _G[name.."Count"]
	self.HotKey = _G[name.."HotKey"]
	self.Name = _G[name.."Name"]
	self.Cooldown = _G[name.."Cooldown"]

	for _,fontString in ipairs({self.Count,self.HotKey,self.Name}) do
		if fontString then
			fontString:SetText("")
			fontString:Hide()
		end
	end
	if self.Cooldown and self.Cooldown.SetHideCountdownNumbers and not _G.OmniCC then
		self.Cooldown:SetHideCountdownNumbers(true)
	end
end

function ItemRack.InitButtons()
	ItemRackUser.Buttons = ItemRackUser.Buttons or {}

	ItemRack.oldPaperDollItemSlotButton_OnModifiedClick = PaperDollItemSlotButton_OnModifiedClick
	PaperDollItemSlotButton_OnModifiedClick = ItemRack.newPaperDollItemSlotButton_OnModifiedClick

	if CharacterAmmoSlot then
		ItemRack.oldCharacterAmmoSlot_OnClick = CharacterAmmoSlot:GetScript("OnClick")
		CharacterAmmoSlot:SetScript("OnClick",ItemRack.newCharacterAmmoSlot_OnClick)
	end

	local characterModel = CharacterModelFrame or CharacterModelScene
	if characterModel then
		ItemRack.oldCharacterModelFrame_OnMouseUp = characterModel:GetScript("OnMouseUp")
		characterModel:SetScript("OnMouseUp",ItemRack.newCharacterModelFrame_OnMouseUp)
	end


	local button
	for i=0,20 do
		button = _G["ItemRackButton"..i]
		if i<20 then
			-- Only inventory slots are protected. CLICK bindings use key-up
			-- consistently regardless of ActionButtonUseKeyDown, and modifier
			-- actions that ItemRack handles in Lua must not also use the item.
			button:SetAttribute("useOnKeyDown",false)
			button:SetAttribute("type1","item")
			button:SetAttribute("slot",i)
			button:SetAttribute("item",tostring(i))
			button:SetAttribute("shift-type1",ATTRIBUTE_NOOP)
			button:SetAttribute("alt-type2",ATTRIBUTE_NOOP)
		end
		button:RegisterForDrag("LeftButton","RightButton")
		button:RegisterForClicks("LeftButtonUp","RightButtonUp")
		button:SetScript("PreClick", ItemRack.ButtonPreClick)
		ItemRack.MenuMouseoverFrames["ItemRackButton"..i]=1

		if ItemRack.MasqueGroups and ItemRack.MasqueGroups[1] then
			local name = button:GetName()
			ItemRack.MasqueGroups[1]:AddButton(button, {
				Icon = _G[name.."ItemRackIcon"],
				Cooldown = _G[name.."Cooldown"],
				Count = _G[name.."Count"],
				HotKey = _G[name.."HotKey"],
			})
		end
	end

	ItemRack.CreateTimer("ButtonsDocking",ItemRack.ButtonsDocking,.2,1) -- (repeat) on while buttons docking
	ItemRack.CreateTimer("MenuDocking",ItemRack.MenuDocking,.2,1) -- (repeat) on while menu docking

	ItemRackMenuFrame:SetScript("OnMouseDown",ItemRack.MenuFrameOnMouseDown)
	ItemRackMenuFrame:SetScript("OnMouseUp",ItemRack.MenuFrameOnMouseUp)
	ItemRackMenuFrame:EnableMouse(true)

	ItemRack.CreateTimer("ReflectClickedUpdate",ItemRack.ReflectClickedUpdate,.2,1)		

	ItemRackFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
	ItemRackFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
	ItemRackFrame:RegisterEvent("ITEM_LOCK_CHANGED")
	ItemRackFrame:RegisterEvent("UPDATE_BINDINGS")
	ItemRack.ReflectMainScale()
	ItemRack.ReflectRightClickUse()
	ItemRack.ConstructLayout()
	ItemRack.UpdateButtonCooldowns()
	ItemRack.ReflectHideOOC()
	ItemRack.ReflectHidePetBattle()
	if ItemRack.UpdateArenaVisibilityState then
		ItemRack.UpdateArenaVisibilityState()
	end
	ItemRack.ReflectCooldownFont()
	ItemRack.UpdateCombatQueue()
	ItemRack.KeyBindingsChanged()
	ItemRack.UpdateDisableAltClick()
end

local function queueAfterCombatOnce(functionName)
	for i=1,#ItemRack.RunAfterCombat do
		if ItemRack.RunAfterCombat[i] == functionName then
			return
		end
	end
	table.insert(ItemRack.RunAfterCombat,functionName)
end

function ItemRack.UpdateDisableAltClick()
	if InCombatLockdown() then
		queueAfterCombatOnce("UpdateDisableAltClick")
		return
	end
	for i=0,19 do
		_G["ItemRackButton"..i]:SetAttribute("alt-type1",
			ItemRackSettings.DisableAltClick=="OFF" and ATTRIBUTE_NOOP or nil)
	end
end

function ItemRack.newPaperDollItemSlotButton_OnModifiedClick(self, button)
	if IsAltKeyDown() then
		ItemRack.ToggleButton(self:GetID())
	else
		ItemRack.oldPaperDollItemSlotButton_OnModifiedClick(self, button)
	end
end

function ItemRack.newCharacterAmmoSlot_OnClick(self, button)
	if IsAltKeyDown() then
		ItemRack.newPaperDollItemSlotButton_OnModifiedClick(self, button)
	elseif button=="LeftButton" then
		-- only call old function if LeftButton. We never UseInventoryItem(0) (in theory)
		ItemRack.oldCharacterAmmoSlot_OnClick(self, button)
	end
end

function ItemRack.newCharacterModelFrame_OnMouseUp(self, button)
	if IsAltKeyDown() then
		ItemRack.ToggleButton(20)
	end
	ItemRack.oldCharacterModelFrame_OnMouseUp(self, button)
end

function ItemRack.AddButton(id)
	ItemRackUser.Buttons[id] = {}
	local button = _G["ItemRackButton"..id]
	button:ClearAllPoints()
	if ItemRack.NewAnchor and ItemRackUser.Buttons[ItemRack.NewAnchor] then
		ItemRackUser.Buttons[id].Side = "LEFT"
		ItemRackUser.Buttons[id].DockTo = ItemRack.NewAnchor
		local dockinfo = ItemRack.DockInfo[ItemRackUser.Buttons[id].Side]
		button:SetPoint("LEFT","ItemRackButton"..ItemRack.NewAnchor,"RIGHT",dockinfo.xoff*(ItemRackUser.ButtonSpacing or 4),dockinfo.yoff*(ItemRackUser.ButtonSpacing or 4))
	else
		button:SetPoint("CENTER",UIParent,"CENTER")
	end
	ItemRack.NewAnchor = id
	_G["ItemRackButton"..id.."ItemRackIcon"]:SetTexture(ItemRack.GetTextureBySlot(id))
	ItemRack.SetRuneIconOverlay(button,id<20 and ItemRack.GetID(id) or nil,nil,nil,"BOTTOMLEFT")
	button:Show()
	ItemRack.UpdateButtonCooldowns()
	if ItemRack.RefreshButtonVisibility then
		ItemRack.RefreshButtonVisibility()
	end
	if id==20 then
		ItemRack.UpdateCurrentSet()
		if ItemRack.ReflectEventsRunning then
			ItemRack.ReflectEventsRunning()
		end
	end
end

function ItemRack.RemoveButton(id)
	if InCombatLockdown() then
		ItemRack.Print("Sorry, you can't add or remove buttons during combat.")
		return
	end
	local child,xpos,ypos
	local dockedTo = ItemRackUser.Buttons[id].DockedTo
	for i in pairs(ItemRackUser.Buttons) do
		if ItemRackUser.Buttons[i].DockTo == id then
			ItemRackUser.Buttons[i].DockTo = nil
			ItemRackUser.Buttons[i].Side = nil
			child = _G["ItemRackButton"..i]
			xpos,ypos = child:GetLeft(),child:GetTop()
			child:ClearAllPoints()
			child:SetPoint("TOPLEFT","UIParent","BOTTOMLEFT",xpos,ypos)
			ItemRackUser.Buttons[i].Left = xpos
			ItemRackUser.Buttons[i].Top = ypos
		end
	end
	ItemRack.NewAnchor = nil
	ItemRackUser.Buttons[id] = nil
	_G["ItemRackButton"..id]:Hide()
end

function ItemRack.ToggleButton(id)
	if InCombatLockdown() then
		ItemRack.Print("Sorry, you can't add or remove buttons during combat.")
	elseif ItemRackUser.Buttons[id] then
		ItemRack.RemoveButton(id)
	else
		ItemRack.AddButton(id)
	end
end

--[[ Button Movement ]]

function ItemRack.Near(v1,v2)
	if v1 and v2 and math.abs(v1-v2)<12 then
		return 1
	end
end

-- which: Main/Menu, side="LEFT"/"TOPRIGHT"/etc, relativeTo=button, corner="TOPLEFT"/"TOPRIGHT"/etc
-- shapes ItemRackMainBracket or ItemRackMenuBracket to a side and draws it there
function ItemRack.MoveBracket(which,side,relativeTo,corner)
	local bracket = _G["ItemRack"..which.."Bracket"]
	if bracket then
		local texture = _G["ItemRack"..which.."BracketTexture"]
		local info = ItemRack.BracketInfo[side]
		bracket:SetWidth(info[1])
		bracket:SetHeight(info[2])
		texture:SetTexCoord(info[3],info[4],info[5],info[6])
		bracket:ClearAllPoints()
		bracket:SetPoint(corner,relativeTo,corner)
		bracket:SetParent(relativeTo)
		bracket:SetAlpha(1)
		bracket:Show()
	end
end

function ItemRack.HideBrackets()
	ItemRackMainBracket:Hide()
	ItemRackMenuBracket:Hide()
	ItemRack.Docking.Side = nil
	ItemRack.Docking.From = nil
	ItemRack.Docking.To = nil
end

-- returns true if candidate is not already docked to button in a docking chain
function ItemRack.LegalDock(button,candidate)
	while ItemRackUser.Buttons[candidate].DockTo do
		if ItemRackUser.Buttons[candidate].DockTo==button then
			return nil -- candidate is already docked somehow to this button
		end
		candidate = ItemRackUser.Buttons[candidate].DockTo
	end
	return 1
end

-- return button if it's not docked, or the original button of dock chain if docked
function ItemRack.FindParent(button)
	while ItemRackUser.Buttons[button] and ItemRackUser.Buttons[button].DockTo do
		button = ItemRackUser.Buttons[button].DockTo
	end
	return button
end

-- while buttons drag, this function periodically lights up docking possibilities
function ItemRack.ButtonsDocking()

	local button = ItemRack.ButtonMoving
	local dock = nil
	local buttonID = button:GetID()
	local near = ItemRack.Near
	if not button then
		ItemRack.StopTimer("ButtonsDocking")
		return
	end

	ItemRack.HideBrackets()

	for i in pairs(ItemRackUser.Buttons) do
		dock = _G["ItemRackButton"..i]
		if near(button:GetLeft(),dock:GetRight()) and (near(button:GetTop(),dock:GetTop()) or near(button:GetBottom(),dock:GetBottom())) and ItemRack.LegalDock(buttonID,i) then
			ItemRack.MoveBracket("Main","LEFT",button,"TOPLEFT")
			ItemRack.MoveBracket("Menu","RIGHT",dock,"TOPRIGHT")
			ItemRack.Docking.Side = "LEFT"
		elseif near(button:GetRight(),dock:GetLeft()) and (near(button:GetTop(),dock:GetTop()) or near(button:GetBottom(),dock:GetBottom())) and ItemRack.LegalDock(buttonID,i) then
			ItemRack.MoveBracket("Main","LEFT",dock,"TOPLEFT")
			ItemRack.MoveBracket("Menu","RIGHT",button,"TOPRIGHT")
			ItemRack.Docking.Side = "RIGHT"
		elseif near(button:GetTop(),dock:GetBottom()) and (near(button:GetLeft(),dock:GetLeft()) or near(button:GetRight(),dock:GetRight())) and ItemRack.LegalDock(buttonID,i) then
			ItemRack.MoveBracket("Main","TOP",button,"TOPLEFT")
			ItemRack.MoveBracket("Menu","BOTTOM",dock,"BOTTOMLEFT")
			ItemRack.Docking.Side = "TOP"
		elseif near(button:GetBottom(),dock:GetTop()) and (near(button:GetLeft(),dock:GetLeft()) or near(button:GetRight(),dock:GetRight())) and ItemRack.LegalDock(buttonID,i) then
			ItemRack.MoveBracket("Main","TOP",dock,"TOPLEFT")
			ItemRack.MoveBracket("Menu","BOTTOM",button,"BOTTOMLEFT")
			ItemRack.Docking.Side = "BOTTOM"
		end

		if ItemRack.Docking.Side then
			ItemRack.Docking.From = buttonID
			ItemRack.Docking.To = i
			break
		end
	end
end

function ItemRack.StartMovingButton(self)
	if ItemRackUser.Locked=="ON" or InCombatLockdown() then return end
	if IsShiftKeyDown() then
		ItemRack.ButtonMoving = self
	else
		ItemRack.ButtonMoving = _G["ItemRackButton"..ItemRack.FindParent(self:GetID())]
	end
	for i in pairs(ItemRackUser.Buttons) do -- highlight parent buttons
		if not ItemRackUser.Buttons[i].DockTo then
			_G["ItemRackButton"..i]:LockHighlight()
		end
	end
	ItemRack.ButtonMoving:StartMoving()
	ItemRack.StartTimer("ButtonsDocking")
end

function ItemRack.StopMovingButton(self)
	if ItemRackUser.Locked=="ON" or not ItemRack.ButtonMoving then return end
	ItemRack.StopTimer("ButtonsDocking")
	ItemRack.ButtonMoving:StopMovingOrSizing()
	ItemRack.NewAnchor = nil
	local buttonID = ItemRack.ButtonMoving:GetID()
	if ItemRack.Docking.Side then
		ItemRack.ButtonMoving:ClearAllPoints()
		local dockinfo = ItemRack.DockInfo[ItemRack.Docking.Side]
		ItemRack.ButtonMoving:SetPoint(ItemRack.Docking.Side,"ItemRackButton"..ItemRack.Docking.To,ItemRack.OppositeSide[ItemRack.Docking.Side],dockinfo.xoff*(ItemRackUser.ButtonSpacing or 4),dockinfo.yoff*(ItemRackUser.ButtonSpacing or 4))
		ItemRackUser.Buttons[buttonID].DockTo=ItemRack.Docking.To
		ItemRackUser.Buttons[buttonID].Side=ItemRack.Docking.Side
		ItemRackUser.Buttons[buttonID].Left = nil
		ItemRackUser.Buttons[buttonID].Top = nil
	else
		ItemRackUser.Buttons[buttonID].DockTo=nil
		ItemRackUser.Buttons[buttonID].Side=nil
		ItemRackUser.Buttons[buttonID].Left = ItemRack.ButtonMoving:GetLeft()
		ItemRackUser.Buttons[buttonID].Top = ItemRack.ButtonMoving:GetTop()
	end
	for i in pairs(ItemRackUser.Buttons) do
		_G["ItemRackButton"..i]:UnlockHighlight()
	end
	ItemRack.HideBrackets()
end

function ItemRack.ConstructLayout()

	if InCombatLockdown() then
		queueAfterCombatOnce("ConstructLayout")
		return
	end
	local button,dockinfo

	-- flag all buttons to be drawn
	for i in pairs(ItemRackUser.Buttons) do
		ItemRackUser.Buttons[i].needsDrawn = 1
	end

	-- draw undocked buttons first (or buttons docked to a non-existent parent)
	for i in pairs(ItemRackUser.Buttons) do
		local dockTo = ItemRackUser.Buttons[i].DockTo
		if ItemRackUser.Buttons[i].needsDrawn and (not dockTo or not ItemRackUser.Buttons[dockTo]) then
--			button = ItemRack.CreateButton(ItemRackUser.Buttons[i].name,i,ItemRackUser.Buttons[i].type)
			button = _G["ItemRackButton"..i]
			ItemRackUser.Buttons[i].needsDrawn = nil
			button:ClearAllPoints()
			if ItemRackUser.Buttons[i].Left then
				button:SetPoint("TOPLEFT","UIParent","BOTTOMLEFT",ItemRackUser.Buttons[i].Left,ItemRackUser.Buttons[i].Top)
			else
				button:SetPoint("CENTER","UIParent","CENTER")
			end
			button:Show()
		end
	end
	local done
	-- iterate over docked buttons in the order they're docked
	while not done do
		done = 1
		for i in pairs(ItemRackUser.Buttons) do
			local dockTo = ItemRackUser.Buttons[i].DockTo
			-- if this button still needs drawing, and its parent is fully drawn (needsDrawn is nil/false)
			if ItemRackUser.Buttons[i].needsDrawn and dockTo and ItemRackUser.Buttons[dockTo] and not ItemRackUser.Buttons[dockTo].needsDrawn then 
--				button = ItemRack.CreateButton(ItemRackUser.Buttons[i].name,i,ItemRackUser.Buttons[i].type)
				button = _G["ItemRackButton"..i]
				ItemRackUser.Buttons[i].needsDrawn = nil
				button:ClearAllPoints()
				dockinfo = ItemRack.DockInfo[ItemRackUser.Buttons[i].Side]
				button:SetPoint(ItemRackUser.Buttons[i].Side,"ItemRackButton"..dockTo,ItemRack.OppositeSide[ItemRackUser.Buttons[i].Side],dockinfo.xoff*(ItemRackUser.ButtonSpacing or 4),dockinfo.yoff*(ItemRackUser.ButtonSpacing or 4))
				button:Show()
				done = nil
			end
		end
	end
	ItemRack.UpdateButtons()
	if ItemRack.RefreshButtonVisibility then
		ItemRack.RefreshButtonVisibility()
	end
end

-- updates icons for equipment slots by grabbing the texture directly from the player's worn items
function ItemRack.UpdateButtons()
	for i in pairs(ItemRackUser.Buttons) do
		if i<20 then
			_G["ItemRackButton"..i.."ItemRackIcon"]:SetTexture(ItemRack.GetTextureBySlot(i))
			ItemRack.SetRuneIconOverlay(_G["ItemRackButton"..i],ItemRack.GetID(i),nil,nil,"BOTTOMLEFT")
			
			-- Update Stack/Charge Count (Hide if <= 1, Show if > 1)
			local count = GetInventoryItemCount("player", i)
			local countFrame = _G["ItemRackButton"..i.."Count"]
			if countFrame then
				if count and count > 1 then
					countFrame:SetText(count)
					countFrame:Show()
				else
					countFrame:SetText("")
					countFrame:Hide()
				end
			end
		end
		--ranged ammo is now infinite, so the below ammo count updater has been commented out
		if i==0 then --ranged "ammo" slot
			local baseID = ItemRack.GetIRString(ItemRack.GetID(0),true) --get the ItemRack-style ID for the ammo item in inventory slot 0 (ranged ammo) and convert it to just its baseID
			if baseID~=0 then -- verify that we properly have the ammo item's baseID
				local ammoCount = GetItemCount(baseID)
				ItemRackButton0Count:SetText(ammoCount > 0 and ammoCount or "") -- hide the 0 if out of ammo
			else
				ItemRackButton0Count:SetText("") -- clear the ammo count since there is no ammo in the slot
			end
		end
	end
	ItemRack.UpdateCurrentSet()
	ItemRack.UpdateButtonCooldowns()
end

--[[ Menu ]]

function ItemRack.DockMenuToButton(button)
	if (button==13 or button==14) and ItemRackSettings.TrinketMenuMode=="ON" and ItemRackUser.Buttons[13] and ItemRackUser.Buttons[14] then
		button = 13 + (ItemRackSettings.AnchorOther=="ON" and 1 or 0)
	end

	local parent = ItemRack.FindParent(button)
	-- get docking and orientation from parent of this button group, use defaults if none defined
	local menuDock = (ItemRackUser.Buttons[parent] and ItemRackUser.Buttons[parent].MenuDock) or "BOTTOMLEFT"
	local mainDock = (ItemRackUser.Buttons[parent] and ItemRackUser.Buttons[parent].MainDock) or "TOPLEFT"
	local menuOrient = (ItemRackUser.Buttons[parent] and ItemRackUser.Buttons[parent].MenuOrient) or "VERTICAL"
	ItemRack.DockWindows(menuDock,_G["ItemRackButton"..button],mainDock,menuOrient,button)
end

function ItemRack.OnEnterButton(self)
	ItemRack.InventoryTooltip(self)
	if ItemRack.IsTimerActive("ButtonsDocking") or (not IsShiftKeyDown() and ItemRackSettings.MenuOnShift=="ON") or ItemRackSettings.MenuOnRight=="ON" then
		return -- don't show menu while buttons docking
	end
	local button = self:GetID()
	ItemRack.DockMenuToButton(button)
	ItemRack.BuildMenu(button, nil, 2)
end

--[[ Menu Docking ]]

function ItemRack.MenuFrameOnMouseDown(self,button)
	if button=="LeftButton" then
		ItemRack.MenuDockingTo = ItemRack.menuMovable
		if ItemRack.MenuDockingTo then
			for i in pairs(ItemRackUser.Buttons) do
				if i~=ItemRack.MenuDockingTo then
					_G["ItemRackButton"..i]:SetAlpha(ItemRackUser.Alpha/3)
				end
			end
			ItemRackMenuFrame:StartMoving()
			ItemRack.StartTimer("MenuDocking")
		end
	end
end

function ItemRack.MenuFrameOnMouseUp(self,button)
	if button=="LeftButton" and ItemRack.MenuDockingTo then
		ItemRack.StopTimer("MenuDocking")
		for i in pairs(ItemRackUser.Buttons) do
			_G["ItemRackButton"..i]:SetAlpha(ItemRackUser.Alpha)
		end
		local parent = ItemRack.FindParent(ItemRack.MenuDockingTo)
		ItemRackUser.Buttons[parent].MenuDock = ItemRack.menuDock
		ItemRackUser.Buttons[parent].MainDock = ItemRack.mainDock
		ItemRack.DockMenuToButton(ItemRack.MenuDockingTo)
		ItemRack.BuildMenu()
		ItemRack.MenuDockingTo = nil
		ItemRackMenuFrame:StopMovingOrSizing()
		ItemRack.HideBrackets()
	elseif button=="RightButton" then
		if ItemRack.menuMovable then
			local parent = ItemRack.FindParent(ItemRack.menuMovable)
			local button = ItemRackUser.Buttons[parent]
			button.MenuOrient = (button.MenuOrient=="VERTICAL") and "HORIZONTAL" or "VERTICAL"
			ItemRack.DockMenuToButton(ItemRack.menuMovable)
			ItemRack.BuildMenu()
		end
	end
end

function ItemRack.MenuDocking()

	local main = _G["ItemRackButton"..ItemRack.MenuDockingTo]
	local menu = ItemRackMenuFrame
	local mainscale = main:GetEffectiveScale()
	local menuscale = menu:GetEffectiveScale()
	local near = ItemRack.Near

	if near(main:GetRight()*mainscale,menu:GetLeft()*menuscale) then
		if near(main:GetTop()*mainscale,menu:GetTop()*menuscale) then
			ItemRack.mainDock = "TOPRIGHT"
			ItemRack.menuDock = "TOPLEFT"
		elseif near(main:GetBottom()*mainscale,menu:GetBottom()*menuscale) then
			ItemRack.mainDock = "BOTTOMRIGHT"
			ItemRack.menuDock = "BOTTOMLEFT"
		end
	elseif near(main:GetLeft()*mainscale,menu:GetRight()*menuscale) then
		if near(main:GetTop()*mainscale,menu:GetTop()*menuscale) then
			ItemRack.mainDock = "TOPLEFT"
			ItemRack.menuDock = "TOPRIGHT"
		elseif near(main:GetBottom()*mainscale,menu:GetBottom()*menuscale) then
			ItemRack.mainDock = "BOTTOMLEFT"
			ItemRack.menuDock = "BOTTOMRIGHT"
		end
	elseif near(main:GetRight()*mainscale,menu:GetRight()*menuscale) then
		if near(main:GetTop()*mainscale,menu:GetBottom()*menuscale) then
			ItemRack.mainDock = "TOPRIGHT"
			ItemRack.menuDock = "BOTTOMRIGHT"
		elseif near(main:GetBottom()*mainscale,menu:GetTop()*menuscale) then
			ItemRack.mainDock = "BOTTOMRIGHT"
			ItemRack.menuDock = "TOPRIGHT"
		end
	elseif near(main:GetLeft()*mainscale,menu:GetLeft()*menuscale) then
		if near(main:GetTop()*mainscale,menu:GetBottom()*menuscale) then
			ItemRack.mainDock = "TOPLEFT"
			ItemRack.menuDock = "BOTTOMLEFT"
		elseif near(main:GetBottom()*mainscale,menu:GetTop()*menuscale) then
			ItemRack.mainDock = "BOTTOMLEFT"
			ItemRack.menuDock = "TOPLEFT"
		end
	end
	ItemRack.MoveBracket("Main",ItemRack.mainDock,main,ItemRack.mainDock)
	ItemRack.MoveBracket("Menu",ItemRack.menuDock,menu,ItemRack.menuDock)
end

--[[ Using buttons ]]

function ItemRack.ButtonPreClick(self,button)
	local id = self:GetID()
	if button=="LeftButton" and IsAltKeyDown() then
		if id<20 and ItemRackSettings.DisableAltClick=="OFF" then
			if not ItemRack.GetQueues()[id] then
				LoadAddOn("ItemRackOptions")
				if ItemRackOpt and ItemRackOpt.SetupQueue then
					local wasOpen = ItemRackOptFrame and ItemRackOptFrame:IsVisible()
					if wasOpen then
						ItemRackOpt.TabOnClick(self,4)
					end
					
					ItemRackOpt.SetupQueue(id)
					
					if not wasOpen and ItemRackOptFrame then
						ItemRackOptFrame:Hide()
					end
				end
			end
			-- Ensure per-set table exists before writing
			if ItemRackUser.EnablePerSetQueues == "ON" then
				local currentSet = ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet]
				if currentSet and not currentSet.QueuesEnabled then
					currentSet.QueuesEnabled = {}
				end
			end
			ItemRack.GetQueuesEnabled()[id] = not ItemRack.GetQueuesEnabled()[id]
			if ItemRackOptSubFrame7 and ItemRackOptSubFrame7:IsVisible() and ItemRackOpt.SelectedSlot==id then
				ItemRackOpt.UpdateQueueEnable()
			end
			ItemRack.UpdateCombatQueue()
		elseif id==20 then
			ItemRack.ToggleEvents(self)
		end
	end
end

function ItemRack.ButtonPostClick(self,button)
	if self.OriginalSetChecked then self:OriginalSetChecked(false) end
	local id = self:GetID()
	if button=="RightButton" then
		local handled = nil
		
		-- Alt+Right-click opens the Queue Options panel for this slot
		if IsAltKeyDown() then
			if id<20 then
				LoadAddOn("ItemRackOptions")
				ItemRackOptFrame:Show()
				ItemRackOpt.TabOnClick(self,4)
				ItemRackOpt.SetupQueue(id)
			else
				-- For slot 20 (set button), open Sets tab instead
				LoadAddOn("ItemRackOptions")
				ItemRackOptFrame:Show()
				ItemRackOpt.TabOnClick(self,3)
			end
			return
		end
		
		
		-- Slot 20 must honor the same Menu-on-right-click setting as Classic Era.
		-- Alt+Right-click above remains the shortcut to the Sets options tab.
		if id==20 then
			if ItemRackSettings.MenuOnRight=="ON" then
				if ItemRackMenuFrame:IsVisible() and ItemRack.menuOpen==id then
					ItemRackMenuFrame:Hide()
				else
					ItemRack.DockMenuToButton(id)
					ItemRack.BuildMenu(id, nil, 2)
				end
			else
				ItemRack.ToggleOptions(self)
			end
			return
		end
		
		-- Plain right-click advances the queue OR opens the menu based on MenuOnRight setting
		if ItemRackSettings.MenuOnRight=="ON" then
			if ItemRackMenuFrame:IsVisible() and ItemRack.menuOpen==id then
				ItemRackMenuFrame:Hide()
			else
				ItemRack.DockMenuToButton(id)
				ItemRack.BuildMenu(id, nil, 2)
			end
		elseif ItemRackSettings.RightClickUse=="ON" then
			-- Right-click uses the item instead of advancing the auto queue
			ItemRack.ReflectItemUse(id)
		else
			-- Plain right-click advances the queue (handles combat queue internally)
			if ItemRack.ManualQueueAdvance and ItemRack.ManualQueueAdvance(id) then
				handled = 1
			end
		end
	elseif IsShiftKeyDown() then
		if id<20 then
			if ChatFrame1EditBox:IsVisible() then
				ChatFrame1EditBox:Insert(GetInventoryItemLink("player",id))
			end
		elseif ItemRackUser.CurrentSet then
			ItemRack.UnequipSet(ItemRackUser.CurrentSet)
		end
	elseif IsAltKeyDown() then
		-- Alt-LeftClick handled in PreClick to avoid SecureActionButton interference
	elseif id<20 then
		ItemRack.ReflectItemUse(id)
	elseif id==20 then
		if button=="LeftButton" and ItemRackUser.CurrentSet then
			if ItemRackSettings.EquipToggle=="ON" then
				ItemRack.ToggleSet(ItemRackUser.CurrentSet)
			else
				ItemRack.EquipSet(ItemRackUser.CurrentSet)
			end
		else
			ItemRack.ToggleOptions(self,2) -- summon set options
		end
	end
end

function ItemRack.ReflectClickedUpdate()
	local reflect = ItemRack.ReflectClicked
	local found
	for i in pairs(reflect) do
		reflect[i] = reflect[i] - .2
		if reflect[i]<0 then
			local btn = _G["ItemRackButton"..i]
			if btn and btn.OriginalSetChecked then btn:OriginalSetChecked(false) end
			reflect[i] = nil
		end
		found = 1
	end
	if not found then
		ItemRack.StopTimer("ReflectClickedUpdate")
	end
end

-- Renderer projection of real item cooldowns, keyed by slot id.
-- Each entry: { start = <number>, duration = <number>, itemID = <number> }
-- CooldownState is the authority; this table exists for UI/debug compatibility only.
ItemRack.CooldownCache = ItemRack.CooldownCache or {}

function ItemRack.UpdateButtonCooldowns()
	ItemRack.InCooldownUpdate = true
	for i in pairs(ItemRackUser.Buttons) do
		if i<20 then
			local cdFrame = _G["ItemRackButton"..i.."Cooldown"]
			local start, duration, enable = GetInventoryItemCooldown("player",i)
			local currentItemID = GetInventoryItemID("player", i)
			local exactID = ItemRack.GetID(i)
			local observed = ItemRack.ObserveItemCooldown(exactID,currentItemID,
				start,duration,enable,"button")

			-- Suppress Blizzard's built-in countdown numbers; ItemRack draws its own
			if cdFrame and cdFrame.SetHideCountdownNumbers and not _G["OmniCC"] then
				cdFrame:SetHideCountdownNumbers(true)
			end

			if observed.active then
				ItemRack.CooldownCache[i] = {
					start=observed.start, duration=observed.duration,
					itemID=currentItemID, exactID=exactID,
				}
				CooldownFrame_Set(cdFrame,observed.start,observed.duration,1)
				IRDebugCooldownState(i,
					string.format("%s:%s:%.1f:%.1f",observed.status,tostring(currentItemID),
						IRRoundTenths(observed.start),IRRoundTenths(observed.duration)),
					string.format("slot %d %s start=%.1f dur=%.1f",i,observed.status,
						observed.start,observed.duration))
			else
				ItemRack.CooldownCache[i] = nil
				if observed.status ~= "arena_stale_sample"
				and observed.status ~= "arena_reset"
				and enable == 1 and start and start > 0
				and duration and duration > 0 and duration <= 1.5 then
					CooldownFrame_Set(cdFrame,start,duration,enable)
				else
					CooldownFrame_Clear(cdFrame)
				end
				IRDebugCooldownState(i,observed.status..":"..tostring(currentItemID),
					string.format("slot %d %s (api start=%.1f dur=%.1f enable=%s)",
						i,observed.status,start or 0,duration or 0,tostring(enable)))
			end
		end
	end
	ItemRack.WriteButtonCooldowns()
	ItemRack.InCooldownUpdate = false
end

function ItemRack.WriteButtonCooldowns()
	if ItemRackSettings.CooldownCount=="ON" then
		for i in pairs(ItemRackUser.Buttons) do
			local exactID = ItemRack.GetID(i)
			local baseID = GetInventoryItemID("player",i)
			local observed = ItemRack.GetObservedItemCooldown(exactID,baseID)
			if observed then
				ItemRack.WriteCooldown(_G["ItemRackButton"..i.."Time"],
					observed.start,observed.duration)
			else
				_G["ItemRackButton"..i.."Time"]:SetText("")
			end
		end
	end
end
function ItemRack.UpdateButtonLocks()
	local isLocked, alreadyLocked
	for i in pairs(ItemRackUser.Buttons) do
		if i<20 then
			isLocked = IsInventoryItemLocked(i)
			alreadyLocked = ItemRack.LockedButtons[i]
			if isLocked and not alreadyLocked then
				_G["ItemRackButton"..i.."ItemRackIcon"]:SetDesaturated(true)
				ItemRack.LockedButtons[i] = 1
			elseif not isLocked and alreadyLocked then
				_G["ItemRackButton"..i.."ItemRackIcon"]:SetDesaturated(false)
				ItemRack.LockedButtons[i] = nil
			end
		end
	end
end

--[[ Button menu ]]

function ItemRack.ButtonMenuOnClick(self)

	if self==ItemRackButtonMenuClose then
		ItemRack.RemoveButton(ItemRack.menuOpen)
	elseif self==ItemRackButtonMenuOptions then
		ItemRack.ToggleOptions(self)
	elseif self==ItemRackButtonMenuLock then
		ItemRackUser.Locked = ItemRackUser.Locked=="ON" and "OFF" or "ON"
		ItemRack.ReflectLock()
	elseif self==ItemRackButtonMenuQueue then
		if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
			ItemRackOptFrame:Hide()
		else
			LoadAddOn("ItemRackOptions")
			ItemRackOptFrame:Show()
			if ItemRack.menuOpen<20 then
				ItemRackOpt.TabOnClick(self,4)
				ItemRackOpt.SetupQueue(ItemRack.menuOpen)
			else
				ItemRackOpt.TabOnClick(self,3)
			end
		end
	end
end

function ItemRack.ReflectMainScale(changing)
	if InCombatLockdown() then
		queueAfterCombatOnce("ReflectMainScale")
		return
	end
	local scale = ItemRackUser.MainScale or 1
	local button
	for i=0,20 do
		button = ItemRackUser.Buttons[i]
		if not changing or not button or not button.Left then
			_G["ItemRackButton"..i]:SetScale(scale)
		else
			local frame = _G["ItemRackButton"..i]
			local oldscale = frame:GetScale() or 1
			local framex = frame:GetLeft()*oldscale
			local framey = frame:GetTop()*oldscale
			frame:SetScale(scale)
			frame:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",framex/scale,framey/scale)
			ItemRackUser.Buttons[i].Left = framex/scale -- frame:GetLeft()
			ItemRackUser.Buttons[i].Top = framey/scale -- frame:GetTop()
		end
	end
end

function ItemRack.ReflectRightClickUse()
	if InCombatLockdown() then
		queueAfterCombatOnce("ReflectRightClickUse")
		return
	end
	local secureUse = ItemRackSettings.RightClickUse == "ON"
		and ItemRackSettings.MenuOnRight ~= "ON"
	for i=0,19 do
		local button = _G["ItemRackButton"..i]
		button:SetAttribute("type2",secureUse and "item" or nil)
		button:SetAttribute("item2",secureUse and tostring(i) or nil)
		-- Alt-right-click is always ItemRack configuration, never an item use.
		button:SetAttribute("alt-type2",ATTRIBUTE_NOOP)
	end
end

function ItemRack.ReflectMenuOnRight()
	ItemRack.ReflectRightClickUse()
end

function ItemRack.ShouldHideButtons()
	return (ItemRackSettings.HideOOC=="ON" and not ItemRack.inCombat)
		or (ItemRackSettings.HidePetBattle=="ON" and ItemRack.inPetBattle)
		or (ItemRackSettings.HideArena=="ON" and ItemRack.inArena)
end

function ItemRack.RefreshButtonVisibility()
	if InCombatLockdown() then
		queueAfterCombatOnce("RefreshButtonVisibility")
		return
	end
	local shouldHide = ItemRack.ShouldHideButtons()
	if shouldHide then
		if ItemRackMenuFrame and ItemRackMenuFrame:IsVisible() then
			ItemRackMenuFrame:Hide()
		end
		if GameTooltip then
			GameTooltip:Hide()
		end
		if ItemRack.HideBrackets then
			ItemRack.HideBrackets()
		end
	end
	for i in pairs(ItemRackUser.Buttons) do
		local button = _G["ItemRackButton"..i]
		if shouldHide then
			button:Hide()
		else
			button:Show()
		end
	end
end

function ItemRack.ReflectHideOOC()
	ItemRack.RefreshButtonVisibility()
end

function ItemRack.ReflectHidePetBattle()
	ItemRack.RefreshButtonVisibility()
end

function ItemRack.ReflectHideArena()
	ItemRack.RefreshButtonVisibility()
end

--[[ Cooldowns ]]

function ItemRack.WriteCooldown(where,start,duration)
	if not start or not duration or start==0 or ItemRackSettings.CooldownCount=="OFF" then
		where:SetText("")
		return
	end
	local cooldown = duration - (GetTime()-start)
	if cooldown<3 and not where:GetText() then
		-- this is a global cooldown. don't display it. not accurate but at least not annoying
	else
		local roundedCooldown = math.floor(cooldown + 0.5)  -- round to nearest second
		if ItemRackSettings.LargeNumbers=="ON" then
			-- Blizzard-style format: mm:ss or h:mm or just seconds
			local text
			if roundedCooldown >= 3600 then
				local h = math.floor(roundedCooldown / 3600)
				local m = math.floor((roundedCooldown - h * 3600) / 60)
				text = string.format("%d:%02d", h, m)
			elseif (ItemRackSettings.Cooldown90=="ON" and roundedCooldown > 90) or (ItemRackSettings.Cooldown90=="OFF" and roundedCooldown > 60) then
				local m = math.floor(roundedCooldown / 60)
				local s = math.floor(roundedCooldown - m * 60)
				text = string.format("%d:%02d", m, s)
			else
				text = tostring(roundedCooldown)
			end
			where:SetText(text)
			-- Dynamic coloring like Blizzard: white > 60s, yellow < 60s, red < 5s
			if roundedCooldown < 5 then
				where:SetTextColor(1, 0.1, 0.1, 1)
			elseif roundedCooldown <= 60 then
				where:SetTextColor(1, 0.82, 0, 1)
			else
				where:SetTextColor(1, 1, 1, 1)
			end
		else
			-- Original small numbers format: "30 s", "2 m", "1 h"
			where:SetText((roundedCooldown<=(ItemRackSettings.Cooldown90=="ON" and 90 or 60) and roundedCooldown.." s") or (roundedCooldown<3600 and math.ceil(roundedCooldown/60).." m") or math.ceil(roundedCooldown/3600).." h")
			where:SetTextColor(1, 1, 1, 1)
		end
	end
end

--[[ Key binding display ]]

function ItemRack.KeyBindingsChanged()
	local key
	for i in pairs(ItemRackUser.Buttons) do
		local hotkey = _G["ItemRackButton"..i.."HotKey"]
		if hotkey then
			if ItemRackSettings.ShowHotKeys=="ON" then
				key = GetBindingKey("CLICK ItemRackButton"..i..":LeftButton")
				if key then
					hotkey:SetText(GetBindingText(key,nil,1))
					hotkey:SetTextColor(0.6, 0.6, 0.6, 1)
					hotkey:Show()
				else
					hotkey:SetText("")
					hotkey:Hide()
				end
			else
				hotkey:SetText("")
				hotkey:Hide()
			end
		end
	end

	-- Sync set keybindings if initiated
	if ItemRack.BindingsInitialized then
		for i in pairs(ItemRackUser.Sets) do
			local buttonName = "ItemRack"..UnitName("player")..GetRealmName()..i
			if _G[buttonName] then
				local boundKey = GetBindingKey("CLICK "..buttonName..":LeftButton")
				if boundKey and boundKey ~= "" then
					ItemRackUser.Sets[i].key = boundKey
				elseif not boundKey then
					-- If unbound via game UI, clear natively
					ItemRackUser.Sets[i].key = nil
				end
			end
		end
	end
end

function ItemRack.ResetButtons()
	for i in pairs(ItemRackUser.Buttons) do
		ItemRack.RemoveButton(i)
	end
	ItemRackUser.Alpha = 1
	ItemRackUser.Locked = "OFF"
	ItemRackUser.MainScale = 1
	ItemRackUser.MenuScale = .85
	ItemRackUser.OptScale = 1
	ItemRackUser.OptSizeDefault = "ON"
	ItemRackUser.OptSizeBigger = "OFF"
	ItemRackUser.OptSizeBiggest = "OFF"
	ItemRackUser.CharMenuWrap = "OFF"
	ItemRackUser.CharMenuWrapValue = 3
	if ItemRackOpt then
		ItemRackOpt.UpdateSlider("Alpha")
		ItemRackOpt.UpdateSlider("MenuScale")
		ItemRackOpt.UpdateSlider("MainScale")
		ItemRackOpt.UpdateSlider("CharMenuWrapValue")
		ItemRackOpt.ReflectOptScale()
		ItemRackOpt.ListScrollFrameUpdate()
	end
end
