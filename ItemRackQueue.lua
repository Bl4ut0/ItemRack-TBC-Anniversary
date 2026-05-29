-- ItemRackQueue.lua
local _

-- Compatibility shims for Item APIs (globals may not exist if deprecation fallbacks disabled)
-- GetItemCooldown exists in both C_Container and C_Item - prefer C_Container for consistency
local GetItemCooldown = _G.GetItemCooldown or (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown)
local GetItemSpell = _G.GetItemSpell or (C_Item and C_Item.GetItemSpell)
local GetItemCount = _G.GetItemCount or (C_Item and C_Item.GetItemCount)
local IsEquippedItem = _G.IsEquippedItem or (C_Item and C_Item.IsEquippedItem)

-- Queue debug prints use the global system:
-- Enable:  /script ItemRack.DebugTags.Queue = true
-- Disable: /script ItemRack.DebugTags.Queue = false

function ItemRack.PeriodicQueueCheck()
	if SpellIsTargeting() then
		ItemRack.Debug("Queue","SpellIsTargeting - skipping queue check")
		return
	end
	-- Only process queues if global EnableQueues is ON and at least one slot is enabled
	if ItemRackUser.EnableQueues=="ON" then
		local queuesEnabled = ItemRack.GetQueuesEnabled()
		for i=0,19 do
			if queuesEnabled[i] then
				ItemRack.ProcessAutoQueue(i)
			end
		end
	else
		ItemRack.Debug("Queue","Global queues disabled (EnableQueues ~= ON)")
	end
end

function ItemRack.ClearManualQueueChoice(slot)
	if ItemRack.ManualQueueChoice then
		ItemRack.ManualQueueChoice[slot] = nil
	end
end

function ItemRack.IsManualQueueChoice(slot, exactID, baseID)
	local choice = ItemRack.ManualQueueChoice and ItemRack.ManualQueueChoice[slot]
	if not choice then
		return false
	end
	local choiceBaseID = string.match(tostring(choice), "^(%d+)")
	return ItemRack.SameExactID(choice, exactID) or (baseID and choiceBaseID == tostring(baseID))
end

function ItemRack.SetManualQueueChoice(slot, id, setname)
	if not slot or not id or id == 0 then
		ItemRack.ClearManualQueueChoice(slot)
		return
	end
	local list = ItemRack.GetQueues(setname)[slot]
	if not list then
		ItemRack.ClearManualQueueChoice(slot)
		return
	end
	local baseID = ItemRack.GetIRString(id, true)
	for i=1,#list do
		if list[i].id == 0 then
			break
		end
		local queueBaseID = string.match(tostring(list[i].id), "^(%d+)")
		if ItemRack.SameExactID(list[i].id, id) or (baseID and queueBaseID == tostring(baseID)) then
			ItemRack.ManualQueueChoice = ItemRack.ManualQueueChoice or {}
			ItemRack.ManualQueueChoice[slot] = list[i].id
			return
		end
	end
	ItemRack.ClearManualQueueChoice(slot)
end

function ItemRack.GetQueueBurnKey(id, baseID)
	if id and id ~= 0 then
		return tostring(id):match(ItemRack.iSPatternItemFieldsFromIR) or tostring(id)
	elseif baseID and baseID ~= 0 then
		return tostring(baseID)
	end
end

function ItemRack.IsQueueItemBurnt(slot, id, baseID)
	local burnKey = ItemRack.GetQueueBurnKey(id, baseID)
	return burnKey and ItemRack.BurntQueueItems and ItemRack.BurntQueueItems[slot] and ItemRack.BurntQueueItems[slot][burnKey]
end

function ItemRack.SetQueueItemBurnt(slot, id, baseID)
	local burnKey = ItemRack.GetQueueBurnKey(id, baseID)
	if not slot or not burnKey then
		return
	end
	ItemRack.BurntQueueItems = ItemRack.BurntQueueItems or {}
	ItemRack.BurntQueueItems[slot] = ItemRack.BurntQueueItems[slot] or {}
	ItemRack.BurntQueueItems[slot][burnKey] = true
end

function ItemRack.MarkEquippedQueueItemBurnt(slot, exactID, baseID, list)
	if not slot or not exactID or exactID == 0 then
		return
	end
	list = list or ItemRack.GetQueues()[slot]
	if not list then
		return
	end
	for i=1,#list do
		if list[i].id == 0 then
			break
		end
		if ItemRack.SameExactID(list[i].id, exactID) then
			if list[i].swapOnUse then
				ItemRack.SetQueueItemBurnt(slot, list[i].id, baseID)
			end
			break
		end
	end
end

-- Helper: Find next valid item in queue for a slot
function ItemRack.GetNextItemInQueue(slot)
	if not slot or IsInventoryItemLocked(slot) then return end
	if slot == 17 and ItemRack.IsOffhandBlocked() then return end

	local list = ItemRack.GetQueues()[slot]
	if not list then return end

	local baseID = ItemRack.GetIRString(GetInventoryItemLink("player",slot),true,true)
	if not baseID then return end

	local exactID = ItemRack.GetID(slot)
	
	-- simple loop to find current item in list and return next valid one
	local idx = 0
	-- First pass: Try to find an exact match (respects enchants, gems for multiple identical items)
	for i=1,#(list) do
		if list[i].id ~= 0 and ItemRack.SameExactID(list[i].id, exactID) then
			idx = i
			break
		end
	end
	
	-- Second pass: Fallback to base ID match
	if idx == 0 then
		for i=1,#(list) do
			if list[i].id ~= 0 then
				local listBaseID = string.match(list[i].id,"(%d+)")
				if listBaseID == baseID then
					idx = i
					break
				end
			end
		end
	end

	-- Look forward from current item
	for i=idx+1,#(list) do
		if list[i].id~=0 then -- 0 is stop marker
			local candidate = string.match(list[i].id,"(%d+)")
			local count = candidate and GetItemCount(candidate) or 0
			if candidate and count>0 then
				return list[i].id
			end
		else
			break -- Hit stop marker
		end
	end
	
	-- Wrap around to start if nothing found after current
	for i=1,idx-1 do
		if list[i].id~=0 then
			local candidate = string.match(list[i].id,"(%d+)")
			local count = candidate and GetItemCount(candidate) or 0
			if candidate and count>0 then
				return list[i].id
			end
		end
	end
end

-- Simpler function for manual queue cycling (right-click advance)
-- Finds next item in queue and equips it directly, or queues for after combat
function ItemRack.ManualQueueAdvance(slot)
	if not slot or IsInventoryItemLocked(slot) then
		ItemRack.Debug("Queue", "ManualAdvance: slot locked or invalid")
		return
	end
	if slot == 17 and ItemRack.IsOffhandBlocked() then
		ItemRack.Debug("Queue", "ManualAdvance: offhand slot is blocked by 2H weapon")
		return
	end
	
	local list = ItemRack.GetQueues()[slot]
	if not list or #list == 0 then
		ItemRack.Debug("Queue", "ManualAdvance: no queue for slot", slot)
		return
	end
	
	-- Get currently equipped item's exact ID and base ID
	-- In combat, we might already have an item pending organically. Evaluate from the pending item first.
	local pendingID = ItemRack.CombatQueue[slot]
	local equippedExactID = pendingID or ItemRack.GetID(slot)
	local equippedBaseID = ItemRack.GetIRString(equippedExactID, true)
	ItemRack.Debug("Queue", "ManualAdvance slot", slot, "equipped:", equippedBaseID)
	
	-- Find current item in queue (exact match first)
	local currentIdx = 0
	for i = 1, #list do
		if list[i].id ~= 0 then
			if ItemRack.SameExactID(list[i].id, equippedExactID) then
				currentIdx = i
				break
			end
		end
	end
	
	-- If exact match fails, fallback to base ID match
	if currentIdx == 0 then
		for i = 1, #list do
			if list[i].id ~= 0 then
				local queueBaseID = string.match(tostring(list[i].id), "^(%d+)")
				if queueBaseID == equippedBaseID then
					currentIdx = i
					break
				end
			end
		end
	end
	
	ItemRack.Debug("Queue", "ManualAdvance currentIdx:", currentIdx)
	
	-- Helper to attempt swap
	local function tryEquip(itemID)
		local inv, bag, bagSlot = ItemRack.FindItem(itemID)
		if bag and bagSlot then
			ItemRack.Debug("Queue", "ManualAdvance equipping", itemID, "from bag", bag)
			ItemRack.EquipItemByID(itemID, slot)
			return true
		end
		return false
	end
	
	-- Try items after current index
	for i = currentIdx + 1, #list do
		if list[i].id == 0 then break end -- Stop marker
		local candidate = string.match(list[i].id,"(%d+)")
		if not ItemRack.IsQueueItemBurnt(slot, list[i].id, candidate) then
			if tryEquip(list[i].id) then return true end
		end
	end
	
	-- Wrap around to start of queue
	for i = 1, currentIdx - 1 do
		if list[i].id == 0 then break end
		local candidate = string.match(list[i].id,"(%d+)")
		if not ItemRack.IsQueueItemBurnt(slot, list[i].id, candidate) then
			if tryEquip(list[i].id) then return true end
		end
	end
	
	ItemRack.Debug("Queue", "ManualAdvance: no valid item found in bags")
	return false
end

function ItemRack.ProcessAutoQueue(slot)
	if not slot or IsInventoryItemLocked(slot) then return end
	if slot == 17 and ItemRack.IsOffhandBlocked() then return end

	local start,duration,enable = GetInventoryItemCooldown("player",slot)
	local timeLeft = math.max(start + duration - GetTime(),0)
	local exactID = ItemRack.GetID(slot)
	local baseID = ItemRack.GetIRString(exactID,true)
	local icon = _G["ItemRackButton"..slot.."Queue"]

	if not baseID then return end
	
	local list = ItemRack.GetQueues()[slot]
	local keepValue, delayValue, priorityValue
	
	-- Find the equipped item in the queue to get its priority/keep/delay settings
	if list then
		local matchIdx = 0
		
		-- First pass: Try to find an exact match (respects enchants, gems for multiple identical items)
		for i=1, #list do
			if list[i].id == 0 then
				break -- Stop marker reached before finding our item
			elseif ItemRack.SameExactID(list[i].id, exactID) then
				matchIdx = i
				break
			end
		end
		
		-- Second pass: Fallback to base ID match
		if matchIdx == 0 then
			for i=1, #list do
				if list[i].id == 0 then
					break -- Stop marker reached
				else
					local queueBaseID = string.match(tostring(list[i].id), "^(%d+)")
					if queueBaseID == baseID then
						matchIdx = i
						break
					end
				end
			end
		end
		
		if matchIdx > 0 then
			keepValue = list[matchIdx].keep
			delayValue = tonumber(list[matchIdx].delay)
			priorityValue = list[matchIdx].priority
		end
	end
	
	-- Visual updates logic (keep/delay/buff checks)
	local buff = GetItemSpell(baseID)
	if buff and AuraUtil.FindAuraByName(buff,"player") then
		if icon then icon:SetDesaturated(true) end
		return
	end

	if keepValue then
		if icon then icon:SetVertexColor(1,.5,.5) end
		return
	end
	
	if delayValue and delayValue > 0 then
		if start>0 and (GetTime() - start) <= delayValue then
			if icon then icon:SetDesaturated(true) end
			return
		end
	end

	if icon then
		icon:SetDesaturated(false)
		icon:SetVertexColor(1,1,1)
	end

	-- logic to actually swap
	local equippedCustomTime = nil
	if list then
		local matchIdx = 0
		for i=1,#list do
			if list[i].id == 0 then break end
			if ItemRack.SameExactID(list[i].id, exactID) then
				matchIdx = i
				break
			end
		end
		if matchIdx == 0 then
			for i=1,#list do
				if list[i].id == 0 then break end
				local sqID = string.match(list[i].id,"^(%d+)")
				if sqID == baseID then
					matchIdx = i
					break
				end
			end
		end
		if matchIdx > 0 then
			equippedCustomTime = list[matchIdx].swapInEnabled and list[matchIdx].swapIn or nil
		end
	end
	local ready = ItemRack.ItemNearReady(baseID, slot, equippedCustomTime)
	if ready and ItemRack.CombatQueue[slot] then
		ItemRack.RemoveFromCombatQueue(slot)
	end

	if not list then return end

	ItemRack.BurntQueueItems = ItemRack.BurntQueueItems or {}
	ItemRack.BurntQueueItems[slot] = ItemRack.BurntQueueItems[slot] or {}
	local start, duration = GetItemCooldown(tonumber(baseID))
	if start and start > 0 and duration > 30 then
		ItemRack.MarkEquippedQueueItemBurnt(slot, exactID, baseID, list)
	end

	local nextItem, nextItemID = ItemRack.AutoQueueItemToEquip(slot, baseID, enable, ready)
	if nextItem then
		if GetItemCount(tonumber(nextItem) or nextItem)>0 and not ItemRack.SameExactID(exactID, nextItemID) then
			local _,bag = ItemRack.FindItem(nextItemID)
			if bag and not (ItemRack.CombatQueue[slot]==nextItemID) then
				ItemRack.EquipItemByID(nextItemID,slot,true)
			end
		end
		
	end
end

function ItemRack.AutoQueueItemToEquip(slot, baseID, enable, ready, setname)
	local list = ItemRack.GetQueues(setname)[slot]
	local candidate

	if not list then return nil end

	-- Respect per-item flags (keep, delay) on the currently-equipped item.
	-- These checks mirror what ProcessAutoQueue does at lines 224-234, but must also
	-- live here because IsSetEquipped calls AutoQueueItemToEquip directly.
	-- Without these checks, IsSetEquipped would falsely report the set as "not equipped"
	-- whenever a kept/delayed item is worn, causing movement events to re-equip the set
	-- and the set display to flip to "Custom".
	local exactID = ItemRack.GetID(slot)
	local currentBurnt = ItemRack.IsQueueItemBurnt(slot, exactID, baseID)
	local manualHold = ItemRack.IsManualQueueChoice(slot, exactID, baseID)
	local matchedCurrent = false
	for i=1,#(list) do
		if list[i].id == 0 then
			break
		end
		local matched = false
		if ItemRack.SameExactID(list[i].id, exactID) then
			matched = true
		else
			local queueBaseID = string.match(tostring(list[i].id), "^(%d+)")
			if queueBaseID == baseID then
				matched = true
			end
		end
		if matched then
			matchedCurrent = true
			local buff = GetItemSpell(baseID)
			if buff and AuraUtil.FindAuraByName(buff,"player") then
				return nil
			end
			-- Pause Queue: item is flagged to stay equipped indefinitely
			if list[i].keep then
				return nil
			end
			-- Delay: item should not be swapped until delay seconds after use
			local delayValue = tonumber(list[i].delay)
			if delayValue and delayValue > 0 then
				local start = GetInventoryItemCooldown("player", slot)
				if start and start > 0 and (GetTime() - start) <= delayValue then
					return nil
				end
			end
			break
		end
	end
	if not matchedCurrent and ItemRack.ManualQueueChoice and ItemRack.ManualQueueChoice[slot] then
		ItemRack.ClearManualQueueChoice(slot)
		manualHold = false
	end
	if currentBurnt then
		ready = nil
	end

	-- reuse the loop structure but optimized for auto-queue logic (priority checks etc)
	-- This will return nil if no new item should be equipped.  
	--    - This is either because there is no auto queue or what we have equipped is already what we want.
	for i=1,#(list) do
		candidate = string.match(list[i].id,"(%d+)")
		-- If there is nothing at the top of our queue, return nil.
		if list[i].id==0 then
			return nil
		-- Skip burnt items
		elseif ItemRack.IsQueueItemBurnt(slot, list[i].id, candidate) then
			-- continue
		-- If baseID is near ready but our candidate IS baseID, return nil.
		elseif ready and candidate==baseID then
			return nil
		else
			local canSwap = not ready or enable==0 or list[i].priority
			if manualHold and ready and candidate ~= baseID then
				canSwap = false
			end
			if canSwap then
				local candidateCustomTime = list[i].swapInEnabled and list[i].swapIn or nil
				if ItemRack.ItemNearReady(candidate, slot, candidateCustomTime) then
					return candidate, list[i].id
				end
			end
		end
	end
	
	return nil
end

function ItemRack.ItemNearReady(id, slot, customReadyTime)
	local start,duration = GetItemCooldown(id)
	if not tonumber(start) then return end -- can return nil shortly after loading screen
	if start==0 then return true end

	-- If the total cooldown duration is 30 seconds or less, it's almost certainly an equip cooldown
	-- (or a very short ability CD), so we consider it "ready" to prevent it from swapping out instantly upon equip.
	if duration <= 30 then return true end

	local overlap = 30
	if customReadyTime then
		overlap = customReadyTime
	end

	if math.max(start + duration - GetTime(),0) <= overlap then
		return true
	end
end

function ItemRack.SetQueue(slot,newQueue)
	if not newQueue then
		ItemRack.GetQueuesEnabled()[slot] = nil
	elseif type(newQueue)=="table" then
		-- Always create a fresh table so we never mutate an inherited reference
		-- from a previous set in the event stack (the proxy's __newindex writes
		-- this into currentSet.Queues[slot])
		local fresh = {}
		for i=1,#(newQueue) do
			table.insert(fresh, newQueue[i])
		end
		ItemRack.GetQueues()[slot] = fresh
		if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
			if ItemRackOptSubFrame7:IsVisible() and ItemRackOpt.SelectedSlot==slot then
				ItemRackOpt.SetupQueue(slot)
			else
				ItemRackOpt.UpdateInv()
			end
		end
		ItemRack.GetQueuesEnabled()[slot] = true
	end
	ItemRack.UpdateCombatQueue()
end

function ItemRack.IsOffhandBlocked()
	local mhID = ItemRack.GetID(16)
	if mhID and mhID ~= 0 then
		local _, _, equipSlot = ItemRack.GetInfoByID(mhID)
		if equipSlot == "INVTYPE_2HWEAPON" then
			if ItemRack.HasTitansGrip then
				local mhLink = GetInventoryItemLink("player", 16)
				local subtype = mhLink and select(7, GetItemInfo(mhLink))
				if subtype and ItemRack.NoTitansGrip[subtype] then
					return true
				else
					return false
				end
			else
				return true
			end
		end
	end
	return false
end
