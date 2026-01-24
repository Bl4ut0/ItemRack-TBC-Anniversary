-- ItemRackQueue.lua
local _

-- Compatibility shims for Item APIs (globals may not exist if deprecation fallbacks disabled)
-- GetItemCooldown exists in both C_Container and C_Item - prefer C_Container for consistency
local GetItemCooldown = _G.GetItemCooldown or (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown)
local GetItemSpell = _G.GetItemSpell or (C_Item and C_Item.GetItemSpell)
local GetItemCount = _G.GetItemCount or (C_Item and C_Item.GetItemCount)
local IsEquippedItem = _G.IsEquippedItem or (C_Item and C_Item.IsEquippedItem)

-- Debug mode - set to true to enable debug prints
ItemRack.QueueDebug = false

-- Debug print helper
local function DebugPrint(...)
	if ItemRack.QueueDebug then
		print("|cff00ff00[IR-Queue]|r", ...)
	end
end

-- Enable queue debugging with: /script ItemRack.QueueDebug = true
-- Disable with: /script ItemRack.QueueDebug = false

function ItemRack.PeriodicQueueCheck()
	if SpellIsTargeting() then
		DebugPrint("SpellIsTargeting - skipping queue check")
		return
	end
	if ItemRackUser.EnableQueues=="ON" then
		local foundEnabled = false
		for i,v in pairs(ItemRack.GetQueuesEnabled()) do
			if v and v == true then
				foundEnabled = true
				DebugPrint("Processing queue for slot:", i)
				ItemRack.ProcessAutoQueue(i)
			end
		end
		if not foundEnabled then
			DebugPrint("No slot queues enabled")
		end
	else
		DebugPrint("Global queues disabled (EnableQueues ~= ON)")
	end
end

-- Helper: Find next valid item in queue for a slot
function ItemRack.GetNextItemInQueue(slot)
	if not slot or IsInventoryItemLocked(slot) then return end

	local list = ItemRack.GetQueues()[slot]
	if not list then return end

	local baseID = ItemRack.GetIRString(GetInventoryItemLink("player",slot),true,true)
	if not baseID then return end

	-- simple loop to find current item in list and return next valid one
	local idx = 0
	for i=1,#(list) do
		if string.match(list[i],"(%d+)") == baseID then
			idx = i
			break
		end
	end

	-- Look forward from current item
	for i=idx+1,#(list) do
		if list[i]~=0 then -- 0 is stop marker
			local candidate = string.match(list[i],"(%d+)")
			if candidate and GetItemCount(candidate)>0 then
				return list[i]
			end
		else
			break -- Hit stop marker
		end
	end
	
	-- Wrap around to start if nothing found after current
	for i=1,idx-1 do
		if list[i]~=0 then
			local candidate = string.match(list[i],"(%d+)")
			if candidate and GetItemCount(candidate)>0 then
				return list[i]
			end
		end
	end
end

function ItemRack.ProcessAutoQueue(slot)
	local function DebugPrint(...)
		if ItemRack.QueueDebug then
			print("|cff00ff00[IR-Queue]|r", ...)
		end
	end
	
	if not slot or IsInventoryItemLocked(slot) then return end

	local start,duration,enable = GetInventoryItemCooldown("player",slot)
	local timeLeft = math.max(start + duration - GetTime(),0)
	local baseID = ItemRack.GetIRString(GetInventoryItemLink("player",slot),true,true)
	local icon = _G["ItemRackButton"..slot.."Queue"]

	if not baseID then return end
	
	-- Visual updates logic (keep/delay/buff checks)
	local buff = GetItemSpell(baseID)
	if buff and AuraUtil.FindAuraByName(buff,"player") then
		if icon then icon:SetDesaturated(true) end
		return
	end

	if ItemRackItems[baseID] then
		if ItemRackItems[baseID].keep then
			if icon then icon:SetVertexColor(1,.5,.5) end
			return
		end
		if ItemRackItems[baseID].delay then
			if start>0 and timeLeft>30 and timeLeft<=ItemRackItems[baseID].delay then
				if icon then icon:SetDesaturated(true) end
				return
			end
		end
	end
	if icon then
		icon:SetDesaturated(false)
		icon:SetVertexColor(1,1,1)
	end

	-- logic to actually swap
	local ready = ItemRack.ItemNearReady(baseID)
	if ready and ItemRack.CombatQueue[slot] then
		ItemRack.CombatQueue[slot] = nil
		ItemRack.UpdateCombatQueue()
	end

	local list = ItemRack.GetQueues()[slot]
	if not list then return end

	local candidate
    -- reuse the loop structure but optimized for auto-queue logic (priority checks etc)
	for i=1,#(list) do
		candidate = string.match(list[i],"(%d+)")
		if list[i]==0 then
			break
		elseif ready and candidate==baseID then
			break
		else
			local canSwap = not ready or enable==0 or (ItemRackItems[candidate] and ItemRackItems[candidate].priority)
			if canSwap then
				if ItemRack.ItemNearReady(candidate) then
					if GetItemCount(candidate)>0 and not IsEquippedItem(candidate) then
						local _,bag = ItemRack.FindItem(list[i])
						if bag and not (ItemRack.CombatQueue[slot]==list[i]) then
							ItemRack.EquipItemByID(list[i],slot)
							break
						end
					end
				end
			end
		end
	end
end

function ItemRack.ItemNearReady(id)
	local start,duration = GetItemCooldown(id)
	if not tonumber(start) then return end -- can return nil shortly after loading screen
	if start==0 or math.max(start + duration - GetTime(),0)<=30 then
		return true
	end
end

function ItemRack.SetQueue(slot,newQueue)
	if not newQueue then
		ItemRack.GetQueuesEnabled()[slot] = nil
	elseif type(newQueue)=="table" then
		ItemRack.GetQueues()[slot] = ItemRack.GetQueues()[slot] or {}
		for i in pairs(ItemRack.GetQueues()[slot]) do
			ItemRack.GetQueues()[slot][i] = nil
		end
		for i=1,#(newQueue) do
			table.insert(ItemRack.GetQueues()[slot],newQueue[i])
		end
		if ItemRackOptFrame:IsVisible() then
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
