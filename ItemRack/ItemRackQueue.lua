-- ItemRackQueue.lua
local _

-- Compatibility shims for Item APIs (globals may not exist if deprecation fallbacks disabled)
-- GetItemCooldown exists in both C_Container and C_Item - prefer C_Container for consistency
local GetItemCooldown = _G.GetItemCooldown or (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown)
local GetItemSpell = _G.GetItemSpell or (C_Item and C_Item.GetItemSpell)
local IsEquippedItem = _G.IsEquippedItem or (C_Item and C_Item.IsEquippedItem)

-- Compatibility shim for GetSpellInfo (deprecated in 11.0.0, changed in 1.15.0)
local GetSpellInfo = GetSpellInfo or function(spellID)
	if not spellID then return nil end
	local info = C_Spell and C_Spell.GetSpellInfo(spellID)
	if info then
		local subtext = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
		return info.name, subtext, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
	end
end

-- Queue debug prints use the global system:
-- Enable:  /script ItemRack.DebugTags.Queue = true
-- Disable: /script ItemRack.DebugTags.Queue = false

function ItemRack.PeriodicQueueCheck()
	if ItemRack.QueueStateReady ~= true then
		return
	end
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		if ItemRack.QueueDiagnostic then ItemRack.QueueDiagnostic("autoqueue_skipped", { reason = "automatic_swap_suspended" }) end
		return
	end
	if ItemRack.SetSwapping or (ItemRack.AnythingLocked and ItemRack.AnythingLocked()) then
		if ItemRack.QueueDiagnostic then ItemRack.QueueDiagnostic("autoqueue_skipped", { reason = ItemRack.SetSwapping and "set_swap_in_progress" or "inventory_locked" }) end
		return
	end
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

-- A legacy queue entry has no rune suffix and therefore resolves any carried
-- copy with the same base ID. That fallback remains necessary for profiles
-- created before rune-aware IDs existed, but it becomes ambiguous once the
-- active part of the same queue contains an explicit rune entry for that item.
function ItemRack.QueueHasExplicitRuneEntry(list,baseID)
	if not list or not baseID or baseID == 0 then return false end
	baseID = tostring(baseID)
	for i=1,#list do
		local entryID = list[i].id
		if entryID == 0 then break end
		if ItemRack.HasRuneID(entryID)
		and tostring(ItemRack.GetIRString(entryID,true)) == baseID then
			return true
		end
	end
	return false
end

function ItemRack.IsQueueEntryUnambiguous(list,index)
	local entry = list and list[index]
	if not entry or not entry.id or entry.id == 0 then return false end
	if ItemRack.HasRuneID(entry.id) then return true end
	local baseID = ItemRack.GetIRString(entry.id,true)
	return not ItemRack.QueueHasExplicitRuneEntry(list,baseID)
end

-- Resolve exact rune/item identity before considering a legacy base-ID
-- wildcard, regardless of the entries' order in the queue. Never use an
-- ambiguous wildcard when this queue has explicit rune identities available.
function ItemRack.FindQueueEntryIndex(list,currentID)
	if not list or not currentID or currentID == 0 then return nil end
	local legacyFallback
	for i=1,#list do
		local entryID = list[i].id
		if entryID == 0 then break end
		if ItemRack.SameExactID(entryID,currentID) then
			return i
		elseif not legacyFallback and not ItemRack.HasRuneID(entryID)
		and ItemRack.IsQueueEntryUnambiguous(list,i)
		and ItemRack.SameID(entryID,currentID) then
			legacyFallback = i
		end
	end
	return legacyFallback
end

function ItemRack.IsManualQueueChoice(slot, exactID, baseID)
	local choice = ItemRack.ManualQueueChoice and ItemRack.ManualQueueChoice[slot]
	if not choice then
		return false
	end
	local list = ItemRack.GetQueues()[slot]
	local choiceIndex = ItemRack.FindQueueEntryIndex(list,choice)
	if not choiceIndex or not ItemRack.IsQueueEntryUnambiguous(list,choiceIndex) then
		return false
	end
	return ItemRack.MatchesStoredItemID(choice, exactID)
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
	local matchIndex = ItemRack.FindQueueEntryIndex(list,id)
	if matchIndex then
		ItemRack.ManualQueueChoice = ItemRack.ManualQueueChoice or {}
		ItemRack.ManualQueueChoice[slot] = list[matchIndex].id
		return
	end
	ItemRack.ClearManualQueueChoice(slot)
end

function ItemRack.GetQueueBurnKey(id, baseID)
	if id and id ~= 0 then
		local idText = tostring(id)
		local burnKey = idText:match(ItemRack.iSPatternItemFieldsFromIR) or idText
		local runeSuffix = idText:match("(:runeid:%d+)$")
		return runeSuffix and (burnKey..runeSuffix) or burnKey
	elseif baseID and baseID ~= 0 then
		return tostring(baseID)
	end
end

function ItemRack.IsQueueItemBurnt(slot, id, baseID)
	local burnKey = ItemRack.GetQueueBurnKey(id, baseID)
	if not burnKey or not slot then return false end
	local function HasBurnKey(key)
		if ItemRackUser and ItemRackUser.BurntQueueItems and ItemRackUser.BurntQueueItems[slot] and ItemRackUser.BurntQueueItems[slot][key] then
			return true
		end
		return ItemRack.BurntQueueItems and ItemRack.BurntQueueItems[slot] and ItemRack.BurntQueueItems[slot][key]
	end
	if HasBurnKey(burnKey) then return true end
	-- Burn state written before rune-aware keys applied to all copies of the
	-- item. Continue honoring that legacy key until the queue state is cleared.
	if ItemRack.HasRuneID(id) then
		local legacyKey = tostring(id):match(ItemRack.iSPatternItemFieldsFromIR)
		if legacyKey and legacyKey ~= burnKey and HasBurnKey(legacyKey) then
			return true
		end
	end
	return false
end

function ItemRack.SetQueueItemBurnt(slot, id, baseID)
	local burnKey = ItemRack.GetQueueBurnKey(id, baseID)
	if not slot or not burnKey then
		return
	end
	ItemRackUser = ItemRackUser or {}
	ItemRackUser.BurntQueueItems = ItemRackUser.BurntQueueItems or {}
	ItemRackUser.BurntQueueItems[slot] = ItemRackUser.BurntQueueItems[slot] or {}
	ItemRackUser.BurntQueueItems[slot][burnKey] = true

	ItemRack.BurntQueueItems = ItemRackUser.BurntQueueItems
end

function ItemRack.MarkEquippedQueueItemBurnt(slot, exactID, baseID, list)
	if not slot or not exactID or exactID == 0 then
		return
	end
	list = list or ItemRack.GetQueues()[slot]
	if not list then
		return
	end
	local matchIndex = ItemRack.FindQueueEntryIndex(list,exactID)
	if matchIndex and list[matchIndex].swapOnUse then
		ItemRack.SetQueueItemBurnt(slot,list[matchIndex].id,baseID)
		if ItemRack.QueueDiagnostic then
			ItemRack.QueueDiagnostic("queue_item_burnt", { baseID = baseID, slot = slot })
		end
	end
end

-- Helper: Find next valid item in queue for a slot
function ItemRack.GetNextItemInQueue(slot)
	if not slot or IsInventoryItemLocked(slot) then return end
	if not ItemRack.IsEquippedSlotStateReady(slot) then return end
	if slot == 17 and ItemRack.IsOffhandBlocked() then return end

	local list = ItemRack.GetQueues()[slot]
	if not list then return end

	local baseID = ItemRack.GetIRString(GetInventoryItemLink("player",slot),true,true)
	if not baseID then return end

	local exactID = ItemRack.GetID(slot)
	
	-- Locate the exact rune identity first. A legacy base-ID entry is used only
	-- when this queue has no explicit rune entry for the same item.
	local idx = ItemRack.FindQueueEntryIndex(list,exactID) or 0

	-- Look forward from current item
	for i=idx+1,#(list) do
		if list[i].id~=0 then -- 0 is stop marker
			local candidate = string.match(tostring(list[i].id),"(%d+)")
			if candidate and ItemRack.IsQueueEntryUnambiguous(list,i)
			and ItemRack.FindItemInBags(list[i].id) then
				return list[i].id
			end
		else
			break -- Hit stop marker
		end
	end
	
	-- Wrap around to start if nothing found after current
	for i=1,idx-1 do
		if list[i].id~=0 then
			local candidate = string.match(tostring(list[i].id),"(%d+)")
			if candidate and ItemRack.IsQueueEntryUnambiguous(list,i)
			and ItemRack.FindItemInBags(list[i].id) then
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
	local equippedExactID
	if pendingID then
		equippedExactID = pendingID
	else
		if not ItemRack.IsEquippedSlotStateReady(slot) then
			ItemRack.Debug("Queue", "ManualAdvance: equipped item data is unresolved")
			return
		end
		equippedExactID = ItemRack.EquippedSnapshot[slot]
	end
	local equippedBaseID = ItemRack.GetIRString(equippedExactID, true)
	ItemRack.Debug("Queue", "ManualAdvance slot", slot, "equipped:", equippedBaseID)
	
	-- Find current item in queue (exact rune identity first, with a legacy
	-- fallback only when no explicit rune entry makes that fallback ambiguous).
	local currentIdx = ItemRack.FindQueueEntryIndex(list,equippedExactID) or 0
	
	ItemRack.Debug("Queue", "ManualAdvance currentIdx:", currentIdx)
	
	-- Helper to attempt swap
	local function tryEquip(index)
		if not ItemRack.IsQueueEntryUnambiguous(list,index) then
			ItemRack.Debug("Queue", "ManualAdvance: skipping ambiguous legacy entry", index)
			return false
		end
		local itemID = list[index].id
		local bag, bagSlot = ItemRack.FindItemInBags(itemID)
		if bag and bagSlot then
			ItemRack.Debug("Queue", "ManualAdvance equipping", itemID, "from bag", bag)
			ItemRack.EquipItemByID(itemID, slot, false, bag, bagSlot)
			return true
		end
		return false
	end
	
	-- Try items after current index
	for i = currentIdx + 1, #list do
		if list[i].id == 0 then break end -- Stop marker
		local candidate = string.match(tostring(list[i].id),"(%d+)")
		if not ItemRack.IsQueueItemBurnt(slot, list[i].id, candidate) then
			if tryEquip(i) then return true end
		end
	end
	
	-- Wrap around to start of queue
	for i = 1, currentIdx - 1 do
		if list[i].id == 0 then break end
		local candidate = string.match(tostring(list[i].id),"(%d+)")
		if not ItemRack.IsQueueItemBurnt(slot, list[i].id, candidate) then
			if tryEquip(i) then return true end
		end
	end
	
	ItemRack.Debug("Queue", "ManualAdvance: no valid item found in bags")
	return false
end

-- Slot-aware default swap-in threshold helper:
-- Default overlap is 30 seconds for trinket slots (13, 14), and 0 seconds for all other equipment slots.
function ItemRack.GetDefaultSwapIn(slot)
	if slot == 13 or slot == 14 then
		return 30
	end
	return 0
end

function ItemRack.ClearBurntQueueItems(slot)
	ItemRackUser = ItemRackUser or {}
	ItemRackUser.BurntQueueItems = ItemRackUser.BurntQueueItems or {}
	if slot then
		ItemRackUser.BurntQueueItems[slot] = nil
	else
		ItemRackUser.BurntQueueItems = {}
	end
	ItemRack.BurntQueueItems = ItemRackUser.BurntQueueItems
	if ItemRack.QueueDiagnostic then
		ItemRack.QueueDiagnostic("burnt_items_cleared", { slot = slot or "all" })
	end
end

function ItemRack.RecordEquipTime(slot, exactID, transitionTime, attempt)
	if not slot or not exactID or exactID == 0 then return end
	ItemRackUser = ItemRackUser or {}
	ItemRackUser.EquipTimers = ItemRackUser.EquipTimers or {}
	local previousTimerRecord = ItemRack.EquipTimers and ItemRack.EquipTimers[slot]
	local start, duration = GetInventoryItemCooldown("player", slot)
	start = tonumber(start)
	duration = tonumber(duration)
	local now = GetTime()
	local referenceTime = tonumber(transitionTime) or now
	attempt = tonumber(attempt) or 0
	local pendingUse = ItemRack.PendingReflectItemUse
	and ItemRack.PendingReflectItemUse[slot]
	local exactBaseID = tonumber(ItemRack.GetIRString(exactID, true))
	local pendingUseMatches = pendingUse and (
		(pendingUse.exactID and ItemRack.SameExactID(pendingUse.exactID, exactID))
		or (not pendingUse.exactID and pendingUse.baseID and pendingUse.baseID == exactBaseID)
	)
	local useCheckPending = pendingUseMatches
	and type(pendingUse.deadline) == "number" and now <= pendingUse.deadline
	and duration and duration >= 29 and duration <= 31

	-- Blizzard can publish UNIT_INVENTORY_CHANGED before the new inventory
	-- cooldown is visible. Keep this transition protected while the cooldown
	-- settles; treating 0/nil as "no penalty" here can make AutoQueue undo a
	-- valid equip before its 30-second penalty appears. If an item-use hook is
	-- simultaneously resolving the same ambiguous 30-second cooldown, let the
	-- hook compare its start against the transition before classifying it.
	if (not start or not duration or (start == 0 and duration == 0) or useCheckPending)
	and attempt < 12 then
		local pendingRecord = {
			id = exactID,
			time = referenceTime,
			transitionTime = referenceTime,
			hasPenalty = nil,
			pending = true,
			used = false
		}
		ItemRackUser.EquipTimers[slot] = pendingRecord
		ItemRack.EquipTimers = ItemRackUser.EquipTimers
		if ItemRack.AdvanceRecentRuneOnlyEquipTransitionRecord then
			ItemRack.AdvanceRecentRuneOnlyEquipTransitionRecord(slot,previousTimerRecord,pendingRecord,exactID)
		end
		if ItemRack.QueueDiagnostic then
			ItemRack.QueueDiagnostic("equip_timer_pending", { attempt = attempt, slot = slot })
		end

		local generation = ItemRack.QueueStateGeneration
		local deadline = now + 0.75
		local retry
		retry = function()
			if generation ~= ItemRack.QueueStateGeneration
			or not ItemRack.EquipTimers
			or ItemRack.EquipTimers[slot] ~= pendingRecord
			or not pendingRecord.pending
			or pendingRecord.used then
				return
			end

			local state, currentExactID = ItemRack.GetEquippedSlotState(slot)
			if state == "resolved" then
				if ItemRack.SameExactID(currentExactID, exactID) then
					ItemRack.RecordEquipTime(slot, exactID, referenceTime, attempt + 1)
				else
					ItemRack.ClearEquipTimer(slot)
				end
			elseif state == "empty" then
				ItemRack.ClearEquipTimer(slot)
			elseif GetTime() < deadline then
				C_Timer.After(0.05, retry)
			elseif ItemRack.ScheduleEquippedStateRetry then
				-- Leave the protective pending record in place. Reconciliation
				-- will restart classification once the exact slot resolves.
				ItemRack.ScheduleEquippedStateRetry()
			end
		end
		C_Timer.After(0.05, retry)
		return
	end

	local hasPenalty = false
	local cooldownOffset = start and start > 0 and math.abs(referenceTime - start)
	if cooldownOffset and cooldownOffset <= 1
	and duration and duration >= 29 and duration <= 31 then
		hasPenalty = true
	end
	ItemRackUser.EquipTimers[slot] = {
		id = exactID,
		time = hasPenalty and start or now,
		hasPenalty = hasPenalty,
		used = not hasPenalty -- Items without an equip penalty are unheld immediately
	}
	ItemRack.EquipTimers = ItemRackUser.EquipTimers
	if ItemRack.AdvanceRecentRuneOnlyEquipTransitionRecord then
		ItemRack.AdvanceRecentRuneOnlyEquipTransitionRecord(slot,previousTimerRecord,ItemRack.EquipTimers[slot],exactID)
	end
	if ItemRack.QueueDiagnostic then
		ItemRack.QueueDiagnostic("equip_timer_recorded", {
			hasPenalty = hasPenalty,
			slot = slot,
			used = ItemRackUser.EquipTimers[slot].used and true or false
		})
	end
end

function ItemRack.MarkEquippedItemUsed(slot)
	if not slot then return end
	ItemRackUser = ItemRackUser or {}
	ItemRackUser.EquipTimers = ItemRackUser.EquipTimers or {}
	if ItemRackUser.EquipTimers[slot] then
		ItemRackUser.EquipTimers[slot].used = true
		ItemRackUser.EquipTimers[slot].pending = nil
	end
	ItemRack.EquipTimers = ItemRackUser.EquipTimers
	if ItemRack.QueueDiagnostic then
		ItemRack.QueueDiagnostic("equipped_item_marked_used", { slot = slot })
	end
end

function ItemRack.IsRecentEquip(slot, exactID)
	if not slot or not exactID then return false end
	local record = ItemRack.EquipTimers and ItemRack.EquipTimers[slot]
	if not record then return false end
	if record.used then return false end -- Released immediately if used or if no equip penalty exists
	if ItemRack.SameExactID(record.id, exactID) then
		local baseID = ItemRack.GetIRString(exactID, true)
		if not ItemRack.IsQueueItemBurnt(slot, exactID, baseID) then
			return (GetTime() - record.time) < 30
		end
	end
	return false
end

local function ResolveProxy(itemID)
	local numericID = tonumber(ItemRack.GetIRString(itemID,true))
	return numericID and ItemRack.CooldownProxies[numericID]
end

-- Raw cooldown of the gating item, for display. Returns nil when itemID has no
-- proxy, so callers fall through to the item's own (absent) cooldown.
local function GetProxyCooldown(itemID)
	if not GetItemCooldown then return nil end
	local proxy = ResolveProxy(itemID)
	if not proxy then return nil end
	return GetItemCooldown(proxy.id)
end

-- Substitutes the gating item's cooldown into a display triple, for the slot
-- buttons and flyout menu. Passes the original values through untouched when
-- itemID has no proxy.
function ItemRack.ApplyProxyCooldown(itemID, start, duration, enable)
	local proxyStart, proxyDuration, proxyEnable = GetProxyCooldown(itemID)
	if proxyStart then
		return proxyStart, proxyDuration, proxyEnable
	end
	return start, duration, enable
end

-- Stands in for GetItemSpell on proxied items so the existing buff-hold check
-- keeps them equipped for as long as the aura actually runs. Returns a localized
-- name to match what GetItemSpell yields; a literal name string is accepted
-- too. Callers prefer this over GetItemSpell: a CooldownProxies entry is an
-- authored declaration of what gates the item, so it wins over any on-use
-- spell the item also carries.
function ItemRack.GetProxyBuff(itemID)
	local proxy = ResolveProxy(itemID)
	if not proxy or not proxy.buff then return nil end
	if type(proxy.buff) == "number" then
		return (GetSpellInfo(proxy.buff))
	end
	return proxy.buff
end

-- Remaining seconds on the gating item, for readiness. Distinct from
-- GetProxyCooldown above, which returns the raw triple for display. Returns 0
-- when the gating item is ready, and nil when itemID has no proxy, so the
-- caller can tell "ready" from "not proxied".
local function GetProxyCooldownLeft(itemID)
	if not GetItemCooldown then return nil end
	local proxy = ResolveProxy(itemID)
	if not proxy then return nil end
	local start, duration = GetItemCooldown(proxy.id)
	start = tonumber(start)
	duration = tonumber(duration)
	if not start or not duration then return nil end
	if start == 0 or duration == 0 then return 0 end
	return math.max(start + duration - GetTime(), 0)
end

function ItemRack.GetItemCooldownLeft(itemID)
	if not itemID or itemID == 0 or not GetItemCooldown then return nil end
	local numericID = tonumber(itemID) or tonumber(string.match(tostring(itemID), "^(%d+)"))
	if not numericID then return nil end
	local proxied = GetProxyCooldownLeft(numericID)
	if proxied then return proxied end
	local start, duration = GetItemCooldown(numericID)
	start = tonumber(start)
	duration = tonumber(duration)
	if not start or not duration then return nil end -- nil-safe
	if start == 0 or duration == 0 then return 0 end
	return math.max(start + duration - GetTime(), 0)
end

function ItemRack.IsCandidateReady(slot, candidateID, customReadyTime)
	local threshold = tonumber(customReadyTime)
	if threshold == nil then threshold = ItemRack.GetDefaultSwapIn(slot) end
	local timeLeft = ItemRack.GetItemCooldownLeft(candidateID)
	if timeLeft == nil then return false end -- nil-safe: unknown cooldown state -> retry later (not ready)
	return timeLeft <= threshold
end

function ItemRack.ShouldHoldEquippedItem(slot, exactID, baseID, customReadyTime)
	if ItemRack.IsQueueItemBurnt(slot, exactID, baseID) then
		if ItemRack.QueueDiagnostic then ItemRack.QueueDiagnostic("hold_decision", { hold = false, reason = "burnt", slot = slot }) end
		return false
	end
	if ItemRack.IsRecentEquip(slot, exactID) then
		if ItemRack.QueueDiagnostic then ItemRack.QueueDiagnostic("hold_decision", { hold = true, reason = "equip_penalty", slot = slot }) end
		return true
	end
	local threshold = tonumber(customReadyTime)
	if threshold == nil then threshold = ItemRack.GetDefaultSwapIn(slot) end
	local timeLeft = ItemRack.GetItemCooldownLeft(exactID or baseID)
	if timeLeft == nil then
		if ItemRack.QueueDiagnostic then ItemRack.QueueDiagnostic("hold_decision", { hold = true, reason = "unknown_cooldown", slot = slot }) end
		return true
	end -- nil-safe: unknown cooldown state -> hold current gear safely
	local hold = timeLeft <= threshold
	if ItemRack.QueueDiagnostic then
		-- Report the gating item when one stands in, so a dump explains a
		-- remaining time that belongs to no cooldown on the equipped item.
		local proxy = ResolveProxy(exactID or baseID)
		ItemRack.QueueDiagnostic("hold_decision", { hold = hold, proxy = proxy and proxy.id or nil, remaining = string.format("%.2f", timeLeft), slot = slot, threshold = threshold })
	end
	return hold
end

function ItemRack.ProcessAutoQueue(slot)
	if ItemRack.QueueStateReady ~= true then
		if ItemRack.QueueDiagnostic then ItemRack.QueueDiagnostic("autoqueue_skipped", { reason = "state_not_ready", slot = slot }) end
		return
	end
	if not slot then return end
	if not ItemRack.IsEquippedSlotStateReady(slot) then
		if ItemRack.QueueDiagnostic then ItemRack.QueueDiagnostic("autoqueue_skipped", { reason = "slot_unresolved", slot = slot }) end
		return
	end
	if IsInventoryItemLocked(slot) then return end
	if slot == 17 and ItemRack.IsOffhandBlocked() then return end

	local start,duration,enable = GetInventoryItemCooldown("player",slot)
	start = tonumber(start)
	duration = tonumber(duration)
	if not start or not duration then return end -- Top-level nil guard
	local timeLeft = math.max(start + duration - GetTime(),0)
	local exactID = ItemRack.GetID(slot)
	local baseID = ItemRack.GetIRString(exactID,true)
	local icon = _G["ItemRackButton"..slot.."Queue"]

	if not baseID then return end
	
	local list = ItemRack.GetQueues()[slot]
	local keepValue, delayValue, priorityValue
	
	-- Find the equipped item in the queue to get its priority/keep/delay settings
	if list then
		local matchIdx = ItemRack.FindQueueEntryIndex(list,exactID) or 0
		
		if matchIdx > 0 then
			keepValue = list[matchIdx].keep
			delayValue = tonumber(list[matchIdx].delay)
			priorityValue = list[matchIdx].priority
		end
	end
	
	-- Visual updates logic (keep/delay/buff checks)
	local buff = ItemRack.GetProxyBuff(baseID) or GetItemSpell(baseID)
	if buff and AuraUtil.FindAuraByName(buff,"player") then
		if icon then icon:SetDesaturated(true) end
		return
	end

	if keepValue then
		if icon then icon:SetVertexColor(1,.5,.5) end
		return
	end
	
	if delayValue and delayValue > 0 then
		if start > 0 and (GetTime() - start) <= delayValue then
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
		local matchIdx = ItemRack.FindQueueEntryIndex(list,exactID) or 0
		if matchIdx > 0 then
			equippedCustomTime = list[matchIdx].swapInEnabled and list[matchIdx].swapIn or nil
		end
	end
	local ready = ItemRack.ShouldHoldEquippedItem(slot, exactID, baseID, equippedCustomTime)
	if ready and ItemRack.CombatQueue[slot] and ItemRack.AutoQueueFlag and ItemRack.AutoQueueFlag[slot] then
		ItemRack.RemoveFromCombatQueue(slot)
	end

	if not list then return end

	-- NOTE: Legacy duration > 30 auto-burn inference REMOVED completely.
	-- Burn-on-use is 100% event-driven via ReflectItemUse() upon actual player activation.

	local nextItem, nextItemID = ItemRack.AutoQueueItemToEquip(slot, baseID, enable, ready)
	if nextItem then
		if ItemRack.QueueDiagnostic then ItemRack.QueueDiagnostic("autoqueue_candidate", { current = baseID, next = nextItemID, ready = ready and true or false, slot = slot }) end
		if not ItemRack.MatchesStoredItemID(nextItemID, exactID) then
			local bag,bagSlot = ItemRack.FindItemInBags(nextItemID)
			if bag and not (ItemRack.CombatQueue[slot]==nextItemID) then
				if ItemRack.QueueDiagnostic then ItemRack.QueueDiagnostic("autoqueue_equip_requested", { item = nextItemID, slot = slot }) end
				ItemRack.EquipItemByID(nextItemID,slot,true,bag,bagSlot)
			end
		end
		
	end
end

function ItemRack.AutoQueueItemToEquip(slot, baseID, enable, ready, setname)
	if ItemRack.QueueStateReady ~= true then
		return nil
	end
	if not ItemRack.IsEquippedSlotStateReady(slot) then
		return nil
	end
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
	local currentMatchIndex = ItemRack.FindQueueEntryIndex(list,exactID)
	local matchedCurrent = currentMatchIndex ~= nil
	if currentMatchIndex then
		local currentEntry = list[currentMatchIndex]
		local buff = ItemRack.GetProxyBuff(baseID) or GetItemSpell(baseID)
		if buff and AuraUtil.FindAuraByName(buff,"player") then
			return nil
		end
		-- Pause Queue: item is flagged to stay equipped indefinitely
		if currentEntry.keep then
			return nil
		end
		-- Delay: item should not be swapped until delay seconds after use
		local delayValue = tonumber(currentEntry.delay)
		if delayValue and delayValue > 0 then
			local start = GetInventoryItemCooldown("player", slot)
			if start and start > 0 and (GetTime() - start) <= delayValue then
				return nil
			end
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
		local entryID = list[i].id
		candidate = string.match(tostring(entryID),"(%d+)")
		-- If there is nothing at the top of our queue, return nil.
		if entryID==0 then
			return nil
		-- A legacy entry can ask FindItemInBags for an arbitrary same-base copy.
		-- Once this queue has rune-specific entries for that item, only those exact
		-- entries are eligible candidates.
		elseif not ItemRack.IsQueueEntryUnambiguous(list,i) then
			if ItemRack.QueueDiagnostic then
				ItemRack.QueueDiagnostic("autoqueue_candidate_skipped", { item = entryID, reason = "ambiguous_legacy_identity", slot = slot })
			end
		-- Skip burnt items
		elseif ItemRack.IsQueueItemBurnt(slot, entryID, candidate) then
			-- continue
		-- If baseID is near ready but our candidate IS baseID, return nil.
		elseif ready and i == currentMatchIndex then
			return nil
		else
			local canSwap = not ready or enable==0 or list[i].priority
			if manualHold and ready and i ~= currentMatchIndex then
				canSwap = false
			end
			if canSwap then
				local candidateCustomTime = list[i].swapInEnabled and list[i].swapIn or nil
				if ItemRack.IsCandidateReady(slot, entryID, candidateCustomTime) then
					-- Queue candidates must be carried in bags. An item equipped in the
					-- other ring/trinket slot cannot satisfy this slot or block later items.
					if ItemRack.FindItemInBags(entryID) then
						return candidate, entryID
					elseif ItemRack.QueueDiagnostic then
						ItemRack.QueueDiagnostic("autoqueue_candidate_skipped", { item = entryID, reason = "not_in_bags", slot = slot })
					end
				end
			end
		end
	end
	
	return nil
end

function ItemRack.ItemNearReady(id, slot, customReadyTime)
	if not id or id == 0 then return true end
	if not ItemRack.IsEquippedSlotStateReady(slot) then return true end
	local exactID = ItemRack.EquippedSnapshot[slot]
	local baseID = ItemRack.GetIRString(id, true)
	if exactID and ItemRack.MatchesStoredItemID(id, exactID) then
		return ItemRack.ShouldHoldEquippedItem(slot, exactID, baseID, customReadyTime)
	else
		return ItemRack.IsCandidateReady(slot, id, customReadyTime)
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
