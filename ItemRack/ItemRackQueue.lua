-- ItemRackQueue.lua
local _

-- Compatibility shim for GetItemCooldown (may be in C_Container or global, depending on WoW version)
local GetItemCooldown = _G.GetItemCooldown or (C_Container and C_Container.GetItemCooldown)

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

function ItemRack.ProcessAutoQueue(slot)
	local function DebugPrint(...)
		if ItemRack.QueueDebug then
			print("|cff00ff00[IR-Queue]|r", ...)
		end
	end
	
	if not slot then
		DebugPrint("Slot is nil")
		return
	end
	if IsInventoryItemLocked(slot) then
		DebugPrint("Slot", slot, "is locked")
		return
	end

	local start,duration,enable = GetInventoryItemCooldown("player",slot)
	local timeLeft = math.max(start + duration - GetTime(),0)
	local baseID = ItemRack.GetIRString(GetInventoryItemLink("player",slot),true,true)
	local icon = _G["ItemRackButton"..slot.."Queue"]

	if not baseID then
		DebugPrint("No baseID for slot", slot)
		return
	end
	
	DebugPrint("Slot:", slot, "BaseID:", baseID, "CD Start:", start, "Duration:", duration, "TimeLeft:", math.floor(timeLeft))

	local buff = GetItemSpell(baseID)
	if buff then
		if AuraUtil.FindAuraByName(buff,"player") then
			if icon then icon:SetDesaturated(true) end
			DebugPrint("Item buff active, skipping")
			return
		end
	end

	if ItemRackItems[baseID] then
		if ItemRackItems[baseID].keep then
			if icon then icon:SetVertexColor(1,.5,.5) end
			DebugPrint("Item has .keep flag, skipping")
			return -- leave if .keep flag set on this item
		end
		if ItemRackItems[baseID].delay then
			-- Leave item equipped if remaining cd for the item is less than its delay
			if start>0 and timeLeft>30 and timeLeft<=ItemRackItems[baseID].delay then
				if icon then icon:SetDesaturated(true) end
				DebugPrint("Item in delay window, skipping")
				return
			end
		end
	end
	if icon then
		icon:SetDesaturated(false)
		icon:SetVertexColor(1,1,1)
	end

	local ready = ItemRack.ItemNearReady(baseID)
	DebugPrint("Current item ready:", ready and "YES" or "NO")
	
	if ready and ItemRack.CombatQueue[slot] then
		ItemRack.CombatQueue[slot] = nil
		ItemRack.UpdateCombatQueue()
	end

	local list = ItemRack.GetQueues()[slot]
	
	if not list then
		DebugPrint("No queue list for slot", slot)
		return
	end
	
	DebugPrint("Queue has", #list, "items")

	local candidate,bag
	for i=1,#(list) do
		candidate = string.match(list[i],"(%d+)") --FIXME: not sure what list[i] is; it might simply be cleaning up some sort of slot number to make sure it is numeric, OR it might actually be an itemID... if it is the latter then this (conversion to baseID) should be handled by either ItemRack.GetIRString(list[i],true) if list[i] is an ItemRack-style ID or ItemRack.GetIRString(list[i],true,true) if list[i] is a regular ItemLink/ItemString, MOST things point to it being an ItemRack-style ID, but I do not want to mess anything up if this is in fact just a regular number, so I'll leave the line as it is
		DebugPrint("Checking queue item", i, "list[i]:", tostring(list[i]), "candidate:", tostring(candidate))
		if list[i]==0 then
			DebugPrint("Hit stop marker (list[i]==0)")
			break
		elseif ready and candidate==baseID then
			DebugPrint("Current item is ready and matches candidate, stopping")
			break
		else
			local canSwap = not ready or enable==0 or (ItemRackItems[candidate] and ItemRackItems[candidate].priority)
			DebugPrint("Can swap check: ready=", ready, "enable=", enable, "priority=", ItemRackItems[candidate] and ItemRackItems[candidate].priority, "=> canSwap=", canSwap)
			if canSwap then
				local candidateReady = ItemRack.ItemNearReady(candidate)
				DebugPrint("Candidate ready:", candidateReady and "YES" or "NO")
				if candidateReady then
					local itemCount = GetItemCount(candidate)
					local isEquipped = IsEquippedItem(candidate)
					DebugPrint("ItemCount:", itemCount, "IsEquipped:", isEquipped and "YES" or "NO")
					if itemCount>0 and not isEquipped then
						_,bag = ItemRack.FindItem(list[i])
						DebugPrint("FindItem result - bag:", tostring(bag))
						if bag then
							local inCombatQueue = ItemRack.CombatQueue[slot]==list[i]
							DebugPrint("Already in combat queue:", inCombatQueue and "YES" or "NO")
							if not inCombatQueue then
								DebugPrint("SWAPPING to item:", list[i])
								ItemRack.EquipItemByID(list[i],slot)
							end
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
