-- ItemRackEquip.lua : ItemRack.EquipSet and its supporting functions.
local GetContainerNumSlots, GetContainerItemLink, GetContainerItemCooldown, GetContainerItemInfo, GetItemCooldown, PickupContainerItem, ContainerIDToInventoryID
if C_Container then
	GetContainerNumSlots = C_Container.GetContainerNumSlots
	GetContainerItemLink = C_Container.GetContainerItemLink
	GetContainerItemCooldown = C_Container.GetContainerItemCooldown
	GetItemCooldown = C_Container.GetItemCooldown
	PickupContainerItem = C_Container.PickupContainerItem
	ContainerIDToInventoryID = C_Container.ContainerIDToInventoryID
	GetContainerItemInfo = function(bag, slot)
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info then
			return info.iconFileID, info.stackCount, info.isLocked, info.quality, info.isReadable, info.hasLoot, info.hyperlink, info.isFiltered, info.hasNoValue, info.itemID, info.isBound
		else
			return
		end
	end
else
	GetContainerNumSlots, GetContainerItemLink, GetContainerItemCooldown, GetContainerItemInfo, GetItemCooldown, PickupContainerItem, ContainerIDToInventoryID =
	_G.GetContainerNumSlots, _G.GetContainerItemLink, _G.GetContainerItemCooldown, _G.GetContainerItemInfo, _G.GetItemCooldown, _G.PickupContainerItem, _G.ContainerIDToInventoryID
end

ItemRack.SwapList = {} -- table of item ids that want to swap in, indexed by slot
ItemRack.AbortSwap = nil -- reasons: 1=not enough room, 2=item on cursor, 3=in spell targeting mode, 4=item lock
ItemRack.AbortReasons = {"Not enough room.","Something is on the cursor.","In spell targeting mode.","Another swap is in progress."}

ItemRack.SetsWaiting = {} -- numerically indexed table of {"setname",func} ie {"pvp",ItemRack.EquipSet}
ItemRack.SetsWaitingTimeout = 10

function ItemRack.StopSetsWaitingWatchdog()
	ItemRack.SetsWaitingWatchGeneration = (ItemRack.SetsWaitingWatchGeneration or 0) + 1
	ItemRack.SetsWaitingStartedAt = nil
end

-- ITEM_LOCK_CHANGED can be lost when an item transaction overlaps a loading
-- screen. Poll the lock state as a fallback, then abandon only ItemRack's
-- pending callbacks if the client continues reporting the same hard lock.
-- This cannot clear a server/client item lock, but it prevents every later set
-- request from accumulating behind it and appearing as a permanent queue.
function ItemRack.StartSetsWaitingWatchdog()
	if ItemRack.SetsWaitingStartedAt then return end
	ItemRack.SetsWaitingStartedAt = GetTime()
	ItemRack.SetsWaitingWatchGeneration = (ItemRack.SetsWaitingWatchGeneration or 0) + 1
	local generation = ItemRack.SetsWaitingWatchGeneration

	local function PollSetsWaiting()
		if generation ~= ItemRack.SetsWaitingWatchGeneration then return end
		if #ItemRack.SetsWaiting == 0 then
			ItemRack.StopSetsWaitingWatchdog()
			return
		end

		local automaticSwapBlocked = ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked()
		local ordinarySwapBlocked = ItemRack.SetSwapping or ItemRack.NowCasting
		local hardLocked
		if not automaticSwapBlocked and not ordinarySwapBlocked then
			hardLocked = ItemRack.AnythingLocked()
		end
		if automaticSwapBlocked or ordinarySwapBlocked then
			-- Loading screens, summon confirmation, casting, and an ordinary
			-- multi-pass set swap do not prove an inventory lock is stuck. Give a
			-- real lock its full recovery window after those blockers finish.
			ItemRack.SetsWaitingStartedAt = GetTime()
		end
		if not automaticSwapBlocked and not ordinarySwapBlocked and not hardLocked then
			ItemRack.Debug("API", "SetsWaiting watchdog observed unlocked inventory; resuming without ITEM_LOCK_CHANGED")
			ItemRack.ProcessSetsWaiting()
			if #ItemRack.SetsWaiting == 0 then
				ItemRack.StopSetsWaitingWatchdog()
				return
			end
		elseif not automaticSwapBlocked and not ordinarySwapBlocked and hardLocked
		and (GetTime() - ItemRack.SetsWaitingStartedAt) >= ItemRack.SetsWaitingTimeout then
			local count = #ItemRack.SetsWaiting
			local reason = ItemRack.GetLockedReason()
			local retryRequest
			for i = count, 1, -1 do
				local request = ItemRack.SetsWaiting[i]
				if not request[5] and not request[6] and not request[7] then
					retryRequest = request
					break
				end
			end
			for i = count, 1, -1 do
				table.remove(ItemRack.SetsWaiting, i)
			end
			ItemRack.ClearLockList()
			if retryRequest then
				retryRequest[7] = true
				table.insert(ItemRack.SetsWaiting, retryRequest)
				ItemRack.SetsWaitingStartedAt = GetTime()
				ItemRack.Debug("API", "SetsWaiting watchdog retained the newest manual request and canceled", count - 1, "stale/automatic request(s):", reason)
				ItemRack.Print("WoW still reports "..reason.." locked. Retrying your most recent manual set once; older automatic requests were canceled.")
			else
				ItemRack.Debug("API", "SetsWaiting watchdog canceled", count, "request(s) after persistent lock:", reason)
				ItemRack.Print("Canceled "..count.." pending set swap(s): WoW still reports "..reason.." locked.")
				ItemRack.StopSetsWaitingWatchdog()
				return
			end
		end

		C_Timer.After(0.25, PollSetsWaiting)
	end

	C_Timer.After(0.25, PollSetsWaiting)
end

function ItemRack.PauseAutomaticSwapForWorldTransition(reason)
	local waitingAutomaticRequests = 0
	for _, queued in ipairs(ItemRack.SetsWaiting) do
		if queued[5] or queued[6] then
			waitingAutomaticRequests = waitingAutomaticRequests + 1
		end
	end
	if waitingAutomaticRequests > 0 then
		ItemRack.Debug("API", "Pausing", waitingAutomaticRequests, "automatic waiting set request(s):", reason or "automatic swap suspended")
	end
	if ItemRack.PendingQueueEquipSet
	and (ItemRack.PendingQueueEquipSet.isEventEquipment or ItemRack.PendingQueueEquipSet.isDeferredEquipment) then
		ItemRack.Debug("Equip", "Pausing event-driven pending queue-state set:", ItemRack.PendingQueueEquipSet.setname)
	end
	if ItemRack.SetSwapping and ItemRack.SetSwappingIsAutomatic then
		-- Preserve the remaining swap plan but do not issue another item API call
		-- until the destination is settled. This also lets a canceled summon
		-- continue the original event swap instead of leaving it half-equipped.
		ItemRack.Debug("Equip", "Pausing automatic multi-pass swap for world transition:", ItemRack.SetSwapping, reason or "")
	end
end

-- Legion artifact items that act as two items
ItemRack.PhantomItem = {
	[128293] = true, -- Blades of the Fallen Prince (frost death knight)
	[127830] = true, -- Twinblades of the Deceiver (havoc demon hunter)
	[128831] = true, -- Aldrachi Warblades (vengeance demon hunter)
	[128859] = true, -- Fangs of Ashamane (feral druid)
	[128822] = true, -- Claws of Ursoc (guardian druid)
	[133959] = true, -- Heart of the Phoenix (fire mage)
	[133948] = true, -- Fists of the Heavens (windwalker monk)
	[128867] = true, -- Oathseeker (prot pally)
	[133958] = true, -- Secrets of the Void (shadow priest)
	[128869] = true, -- The Kingslayers (assassin rogue)
	[134552] = true, -- The Dreadblades (outlaw rogue)
	[128479] = true, -- Fangs of the Devourer (subtlety rogue)
	[128936] = true, -- The Highkeeper's Ward (ele shaman)
	[128873] = true, -- Fury of the Stonemother (enh shaman)
	[128934] = true, -- Shield of the Sea Queen (resto shaman)
	[128943] = true, -- Skull of the Man'ari (demo lock)
	[134553] = true, -- Warswords of the Valarjar (fury warrior)
	[128289] = true, -- Scale of the Earth-Warder (prot warrior)
}

ItemRack.UniqueGems = {
	-- Wrath JC gems
	[36766] = 3, --bright-dragons-eye
	[36767] = 3, --solid-dragons-eye
	[42142] = 3, --bold-dragons-eye
	[42143] = 3, --delicate-dragons-eye
	[42144] = 3, --runed-dragons-eye
	[42145] = 3, --sparkling-dragons-eye
	[42146] = 3, --lustrous-dragons-eye
	[42148] = 3, --brilliant-dragons-eye
	[42149] = 3, --smooth-dragons-eye
	[42150] = 3, --quick-dragons-eye
	[42151] = 3, --subtle-dragons-eye
	[42152] = 3, --flashing-dragons-eye
	[42153] = 3, --fractured-dragons-eye
	[42154] = 3, --precise-dragons-eye
	[42155] = 3, --stormy-dragons-eye
	[42156] = 3, --rigid-dragons-eye
	[42157] = 3, --thick-dragons-eye
	[42158] = 3, --mystic-dragons-eye
	[49110] = 3, --nightmare-tear
	-- Other
	[27679] = 1, --sublime-mystic-dawnstone
	[27777] = 1, --stark-blood-garnet
	[27785] = 1, --notched-deep-peridot
	[27786] = 1, --barbed-deep-peridot
	[27809] = 1, --barbed-deep-peridot
	[27812] = 1, --stark-blood-garnet
	[27820] = 1, --notched-deep-peridot
	[28360] = 1, --mighty-blood-garnet
	[28361] = 1, --mighty-blood-garnet
	[28556] = 1, --swift-windfire-diamond
	[28557] = 1, --swift-starfire-diamond
	[30571] = 1, --don-rodrigos-heart
	[30598] = 1, --don-amancios-heart
	[32634] = 1, --unstable-amethyst
	[32635] = 1, --unstable-peridot
	[32636] = 1, --unstable-sapphire
	[32637] = 1, --unstable-citrine
	[32638] = 1, --unstable-topaz
	[32639] = 1, --unstable-talasite
	[32735] = 1, --radiant-spencerite
	[33131] = 1, --crimson-sun
	[33132] = 1, --delicate-fire-ruby
	[33133] = 1, --don-julios-heart
	[33134] = 1, --kailees-rose
	[33135] = 1, --falling-star
	[33137] = 1, --sparkling-falling-star
	[33138] = 1, --mystic-bladestone
	[33139] = 1, --brilliant-bladestone
	[33140] = 1, --blood-of-amber
	[33141] = 1, --great-bladestone
	[33142] = 1, --rigid-bladestone
	[33143] = 1, --stone-of-blades
	[33144] = 1, --facet-of-eternity
	[34256] = 1, --charmed-amani-jewel
	[34831] = 1, --eye-of-the-sea
	[42701] = 1, --enchanted-pearl
	[42702] = 1, --enchanted-tear
	[44066] = 1, --kharmaas-grace
	-- TBC PvP Ornate gems (unique-equipped, purchased with Honor points)
	[28362] = 1, --bold-ornate-ruby
	[28118] = 1, --runed-ornate-ruby
	[28363] = 1, --inscribed-ornate-topaz
	[28123] = 1, --potent-ornate-topaz
	[28119] = 1, --smooth-ornate-dawnstone
	[28120] = 1, --gleaming-ornate-dawnstone
	--[41492] = 1, --perfect-inscribed-citrine DEBUG
}
ItemRack.eqBackOfTheBusOffset = 100

function ItemRack.ProcessSetsWaiting()
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		if #ItemRack.SetsWaiting > 0 then
			ItemRack.StartSetsWaitingWatchdog()
		end
		return
	end
	local queued = ItemRack.SetsWaiting[1]
	if not queued then
		ItemRack.StopSetsWaitingWatchdog()
		return
	end
	local setwaiting = queued[1]
	local whichequip = queued[2]
	local disableSound = queued[3]
	local isSecureKeybind = queued[4]
	local isEventEquipment = queued[5]
	local isDeferredEquipment = queued[6]
	local isWatchdogRetry = queued[7]
	table.remove(ItemRack.SetsWaiting,1)
	-- Each dequeued request gives the next request its own recovery window
	-- instead of inheriting the first request's timeout budget.
	ItemRack.SetsWaitingStartedAt = GetTime()
	
	-- Safety: Skip sets that no longer exist (prevents getting stuck)
	if not ItemRackUser.Sets[setwaiting] then
		ItemRack.Debug("API", "ProcessSetsWaiting aborted: set no longer exists ->", setwaiting)
		-- Set was deleted, skip it and try the next one
		if #ItemRack.SetsWaiting > 0 then
			ItemRack.ProcessSetsWaiting()
		else
			ItemRack.StopSetsWaitingWatchdog()
		end
		return
	end
	
	ItemRack.Debug("API", "ProcessSetsWaiting executing callback for:", setwaiting)
	local previousEventEquipment = ItemRack.IsEventEquipment
	local previousDeferredEquipment = ItemRack.IsDeferredEquipment
	local previousWatchdogRetry = ItemRack.IsWatchdogRetry
	if isEventEquipment then
		ItemRack.IsEventEquipment = true
	end
	if isDeferredEquipment then
		ItemRack.IsDeferredEquipment = true
	end
	if isWatchdogRetry then
		ItemRack.IsWatchdogRetry = true
	end
	whichequip(setwaiting, disableSound, isSecureKeybind)
	ItemRack.IsEventEquipment = previousEventEquipment
	ItemRack.IsDeferredEquipment = previousDeferredEquipment
	ItemRack.IsWatchdogRetry = previousWatchdogRetry
	if #ItemRack.SetsWaiting == 0 then
		ItemRack.StopSetsWaitingWatchdog()
	else
		ItemRack.StartSetsWaitingWatchdog()
	end
end

function ItemRack.AddSetToSetsWaiting(setwaiting,whichequip,disableSound,isSecureKeybind)
	local wait = ItemRack.SetsWaiting
	local incomingEvent = ItemRack.IsEventEquipment and true or nil
	local incomingDeferred = ItemRack.IsDeferredEquipment and true or nil
	local incomingAutomatic = incomingEvent or incomingDeferred
	for i,request in ipairs(wait) do
		if request[1]==setwaiting and request[2]==whichequip then
			local existingAutomatic = request[5] or request[6]
			if not incomingAutomatic then
				-- Manual intent is authoritative. Replace automatic provenance and
				-- move this request to the tail so "newest manual request" remains
				-- true even when de-duplication collapses an older queue entry.
				request[3] = disableSound
				request[4] = isSecureKeybind
				request[5] = nil
				request[6] = nil
				request[7] = nil
				table.remove(wait,i)
				table.insert(wait,request)
				if ItemRack.SetsWaitingStartedAt then
					ItemRack.SetsWaitingStartedAt = GetTime()
				end
			elseif existingAutomatic then
				-- Automatic duplicates may merge provenance, but they must never
				-- downgrade an already queued manual request.
				request[3] = disableSound
				request[4] = isSecureKeybind
				request[5] = request[5] or incomingEvent
				request[6] = request[6] or incomingDeferred
				if ItemRack.IsWatchdogRetry then
					request[7] = true
				end
			end
			ItemRack.Debug("API", "AddSetToSetsWaiting merged duplicate for:", setwaiting, incomingAutomatic and "automatic" or "manual")
			ItemRack.StartSetsWaitingWatchdog()
			return
		end
	end
	ItemRack.Debug("API", "AddSetToSetsWaiting added set to API lock queue:", setwaiting)
	table.insert(wait,{setwaiting,whichequip,disableSound,isSecureKeybind,incomingEvent,incomingDeferred,ItemRack.IsWatchdogRetry and true or nil})
	ItemRack.StartSetsWaitingWatchdog()
end

function ItemRack.OrderSwaps(swap)
	for k,v in pairs(swap) do
		if swap[k] and swap[k] ~= 0 then
			local itemID, enchantID, gem1, gem2, gem3 = ItemRack.GetEnhancements(swap[k])
			if (ItemRack.UniqueGems[gem1] or ItemRack.UniqueGems[gem2] or ItemRack.UniqueGems[gem3])
			and k < ItemRack.eqBackOfTheBusOffset then
				swap[k+ItemRack.eqBackOfTheBusOffset] = v
				
				local wornID = ItemRack.GetID(k)
				local wornHasUniqueGem = false
				if wornID and wornID ~= 0 then
					local _, _, wGem1, wGem2, wGem3 = ItemRack.GetEnhancements(wornID)
					if ItemRack.UniqueGems[wGem1] or ItemRack.UniqueGems[wGem2] or ItemRack.UniqueGems[wGem3] then
						wornHasUniqueGem = true
					end
				end
				
				if wornHasUniqueGem then
					swap[k] = 0 -- unequip worn item with unique gem early
				else
					swap[k] = nil
				end
			end
		end
	end
end

function ItemRack.IsWeaponOnlySet(setname)
	local set = setname and ItemRackUser.Sets[setname]
	if not set or not set.equip then return false end
	local hasWeapons = false
	for slot, item in pairs(set.equip) do
		if type(slot) == "number" then
			if slot < 16 or slot > 18 then
				return false
			end
			if item and item ~= 0 then
				hasWeapons = true
			end
		end
	end
	return hasWeapons
end

function ItemRack.PreventLiveOldsetCycle(targetSet, proposedOldSet)
	if not targetSet or not proposedOldSet or targetSet == proposedOldSet then
		return
	end
	if not ItemRackUser or not ItemRackUser.Sets then
		return
	end

	-- Search proposedOldSet's oldset chain to see if targetSet is already present.
	-- If proposedOldSet (or an ancestor in its chain) points to targetSet,
	-- setting targetSet.oldset = proposedOldSet would create a live circular loop (e.g. SetA -> SetB -> SetA).
	local current = proposedOldSet
	local parentPointingToTarget = nil
	local visited = { [targetSet] = true }

	while current do
		if visited[current] then
			break
		end
		visited[current] = true

		local nextOld = ItemRackUser.Sets[current] and ItemRackUser.Sets[current].oldset
		if nextOld == targetSet then
			parentPointingToTarget = current
			break
		end
		current = nextOld
	end

	if parentPointingToTarget and ItemRackUser.Sets[parentPointingToTarget] then
		-- Splice targetSet out of the chain: point parentPointingToTarget to targetSet's current oldset
		local targetOldSet = ItemRackUser.Sets[targetSet] and ItemRackUser.Sets[targetSet].oldset
		if targetOldSet == parentPointingToTarget then
			targetOldSet = nil
		end
		ItemRackUser.Sets[parentPointingToTarget].oldset = targetOldSet
		ItemRack.Debug("Equip", "Live cycle prevented: spliced '" .. tostring(targetSet) .. "' out of '" .. tostring(parentPointingToTarget) .. "' oldset chain.")
	elseif proposedOldSet == targetSet then
		ItemRackUser.Sets[proposedOldSet].oldset = nil
	end
end

function ItemRack.EquipSet(setname, disableSound, isSecureKeybind)
	ItemRack.Debug("Equip", "EquipSet invoked for set:", setname or "nil")
	if not setname or not ItemRackUser.Sets[setname] then
		ItemRack.Print("Set \""..tostring(setname).."\" doesn't exist.")
		return
	end
	local unresolvedSetSlot
	if ItemRackUser.EnableQueues == "ON" and ItemRack.QueueStateReady == true then
		for slot in pairs(ItemRackUser.Sets[setname].equip) do
			if type(slot) == "number" and not ItemRack.IsEquippedSlotStateReady(slot) then
				unresolvedSetSlot = slot
				break
			end
		end
	end
	if (ItemRackUser.EnableQueues == "ON" and ItemRack.QueueStateReady ~= true) or unresolvedSetSlot then
		ItemRack.PendingQueueEquipSet = {
			setname = setname,
			disableSound = disableSound,
			isSecureKeybind = isSecureKeybind,
			isEventEquipment = ItemRack.IsEventEquipment and true or nil,
			isDeferredEquipment = ItemRack.IsDeferredEquipment and true or nil
		}
		ItemRack.PendingQueueStateEventReason = "Deferred EquipSet"
		if ItemRack.ScheduleQueueStateRetry then
			ItemRack.ScheduleQueueStateRetry()
		end
		if unresolvedSetSlot and ItemRack.ScheduleEquippedStateRetry then
			ItemRack.ScheduleEquippedStateRetry()
		end
		ItemRack.Debug("Equip", "EquipSet deferred until exact equipped state is ready:", setname, unresolvedSetSlot or "")
		return
	end
	ItemRack.PendingQueueEquipSet = nil
	if ItemRack.SetSwapping or ItemRack.AnythingLocked() then
		local blockReason = ItemRack.SetSwapping and ("SetSwapping("..tostring(ItemRack.SetSwapping)..")") or ItemRack.GetLockedReason()
		ItemRack.Debug("Equip", "EquipSet deferred set:", setname, "- locked item:", blockReason)
		-- a swap is in progress, add this set to the wait list and leave
		ItemRack.AddSetToSetsWaiting(setname,ItemRack.EquipSet, disableSound, isSecureKeybind)
		return
	end
	local set = ItemRackUser.Sets[setname]
	local swap = ItemRack.SwapList
	for i in pairs(swap) do
		swap[i] = nil
	end
	local inv,bag,slot
	local couldntFind
	local inCombat = InCombatLockdown()
	local isInternalSet = setname and string.sub(setname, 1, 1) == "~" -- Internal sets like ~Unequip, ~CombatQueue, ~DualWieldRetry
	
	if ItemRack.ManualQueueChoice then
		for i in pairs(set.equip) do
			if type(i) == "number" then
				ItemRack.ManualQueueChoice[i] = nil
			end
		end
	end
	if not isInternalSet then
		for i in pairs(set.equip) do
			if type(i) == "number" and ItemRack.ClearBurntQueueItems then
				ItemRack.ClearBurntQueueItems(i)
			end
		end
	end
	
	for i in pairs(set.equip) do
		if type(i) == "number" then
			if ItemRack.GetID(i)~=set.equip[i] then -- if intended item is not worn (exact match)
				inv,bag,slot = ItemRack.FindItem(set.equip[i])
				if not inv and not bag then
					-- if not found at all, then start/add to list of items not found
					-- Suppress these messages during combat or for internal sets (they're noise)
					if set.equip[i] == 0 then
						swap[i] = 0
					elseif not inCombat and not isInternalSet then
						couldntFind = couldntFind or "Could not find: "
						couldntFind = couldntFind.."["..tostring(ItemRack.GetInfoByID(set.equip[i])).."] "
					end
				elseif inv~=i then -- and finding intended item doesn't point to worn
					swap[i] = set.equip[i] -- then note this item for a swap
				end
			end
		end
	end
	ItemRack.Print(couldntFind) -- if couldntFind is nil then nothing will print
 
	-- Snapshot current gear BEFORE checking if set is already equipped.
	-- Even when no swaps are needed (set already worn), we must record what was
	-- previously equipped so that UnequipSet can restore it later.
	-- Without this, events like "stop moving" or "leave zone" find an empty
	-- set.old table and silently fail to restore any gear.
	if not isInternalSet then
		set.old = set.old or {}
		if ItemRackUser.CurrentSet == setname and next(set.old) then
			-- Set is already actively tracking History. Do not overwrite.
			ItemRack.Debug("Equip", "Skipping set.old snapshot. Set is already CurrentSet and has history.")
		else
			for i in pairs(set.old) do
				set.old[i] = nil -- wipe old items
			end
			local proposedOldSet = ItemRackUser.CurrentSet
			if proposedOldSet and proposedOldSet ~= setname then
				ItemRack.PreventLiveOldsetCycle(setname, proposedOldSet)
			end
			set.oldset = proposedOldSet
			-- Pre-populate old with current gear for every slot this set defines.
			for i in pairs(set.equip) do
				if type(i) == "number" then
					set.old[i] = ItemRack.GetID(i)
				end
			end
		end
	end
 
	-- at this point, ItemRack.SwapList has only what needs to be swapped, indexed by slot
	if not next(swap) then
		ItemRack.Debug("Equip", "Set", setname, "already perfectly equipped. swap table is empty.")
		ItemRack.EndSetSwap(setname) -- end swap if set already equipped
		return
	end
	
	local swapStr = ""
	for k,v in pairs(swap) do swapStr = swapStr .. k..":"..v.." " end
	ItemRack.Debug("Equip", "EquipSet swap list generated:", swapStr)
 
	-- if in combat, dead, or casting, queue non-weapon items for later
	-- PickupInventoryItem is blocked by the game during InCombatLockdown() for armor, but weapons (16, 17, 18) can swap in combat if not casting/dead
	if InCombatLockdown() or ItemRack.IsPlayerReallyDead() or ItemRack.NowCasting then
		local reason = InCombatLockdown() and "combat" or (ItemRack.NowCasting and "casting" or "dead")
		ItemRack.Debug("Equip", "EquipSet checking swap deferrals: set=" .. tostring(setname) .. " reason=" .. reason .. " slots queued:")
		local isWeaponOnly = InCombatLockdown() and ItemRack.IsWeaponOnlySet(setname)
		for i in pairs(swap) do
			local isWeaponSlot = (i >= 16 and i <= 18)
			local canSwapWeaponInCombat = InCombatLockdown() and isWeaponSlot and not ItemRack.NowCasting and not ItemRack.IsPlayerReallyDead()
			local secureMacroMismatch = isWeaponOnly and isSecureKeybind
			if canSwapWeaponInCombat and not secureMacroMismatch then
				ItemRack.Debug("Equip", "  slot " .. tostring(i) .. " -> weapon swap allowed in combat")
			else
				local detail = secureMacroMismatch and "secure macro left an item-identity mismatch" or reason
				ItemRack.Debug("Equip", "  slot " .. tostring(i) .. " -> " .. tostring(swap[i]) .. " DEFERRED to CombatQueue (" .. detail .. ")")
				ItemRack.AddToCombatQueue(i,swap[i])
				swap[i] = nil
				if set.old then
					set.old[i] = ItemRack.GetID(i)
					ItemRack.CombatSet = setname
				elseif set.oldset then
					ItemRack.CombatSet = set.oldset
				end
			end
		end
	end
	if not next(swap) then
		return
	end

	if ItemRackUser.Sets[setname].ShowHelm ~= nil then
		if ItemRackUser.Sets[setname].ShowHelm == 1 then
			ShowHelm(true)
		else
			ShowHelm(false)
		end
	end
	
	if ItemRackUser.Sets[setname].ShowCloak ~= nil then
		if ItemRackUser.Sets[setname].ShowCloak == 1 then
			ShowCloak(true)
		else
			ShowCloak(false)
		end
	end

	ItemRack.OrderSwaps(swap) -- bump items with unique gems to the end of the line

	ItemRack.IterateSwapList(setname, disableSound) -- run SwapList swaps
	if not next(swap) then
		if not ItemRack.AnythingLocked() then
			ItemRack.EndSetSwap(setname)
		else
			-- Pickup APIs are asynchronous. A one-item set can have no remaining
			-- SwapList entries while its equipment/bag transaction is still locked.
			-- Keep it tracked until the client confirms the unlock instead of
			-- declaring completion and allowing another event swap to stack on it.
			ItemRack.SetSwapping = setname
			ItemRack.SetSwappingDisableSound = disableSound
			ItemRack.SetSwappingIsAutomatic = (ItemRack.IsEventEquipment or ItemRack.IsDeferredEquipment) and true or nil
			ItemRack.Debug("Equip", "First-pass moves submitted; waiting for client unlock before completing set:", setname, ItemRack.GetLockedReason())
			ItemRack.StartSetSwapTimeout()
		end
		return
	end

	-- If we're in combat and weapon swaps failed (e.g. cursor issue), move remaining
	-- items to CombatQueue instead of entering SetSwapping wait state, which can get
	-- stuck. The CombatQueue will process them cleanly when combat ends.
	if InCombatLockdown() then
		for i in pairs(swap) do
			ItemRack.AddToCombatQueue(i, swap[i])
			if set.old then
				set.old[i] = ItemRack.GetID(i)
				ItemRack.CombatSet = setname
			end
			swap[i] = nil
		end
		return
	end

	-- a second pass is needed. ItemRack.SwapList (swap) has the list of remaining items to swap.
	-- With ItemRack.SetSwapping defined, ITEM_LOCK_CHANGED will call LockChangedDuringSetSwap()
	-- to determine when to run a second pass.
	ItemRack.SetSwapping = setname
	ItemRack.SetSwappingDisableSound = disableSound
	ItemRack.SetSwappingIsAutomatic = (ItemRack.IsEventEquipment or ItemRack.IsDeferredEquipment) and true or nil

	-- Safety timeout: if SetSwapping is never cleared (e.g. locks never fire for a failed swap),
	-- force-clear after 5s to prevent the permanent "stuck until logout" state.
	ItemRack.StartSetSwapTimeout()
end

-- Starts (or restarts) a 5-second safety timer that force-clears SetSwapping if it
-- hasn't been resolved by then. Prevents the addon from getting permanently stuck.
function ItemRack.StartSetSwapTimeout()
	if ItemRack.SetSwapTimeout then
		ItemRack.SetSwapTimeout:Cancel()
	end
	ItemRack.SetSwapTimeout = C_Timer.NewTimer(5, function()
		if ItemRack.SetSwapping then
			if ItemRack.SetSwappingIsAutomatic
			and ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
				ItemRack.SetSwapTimeout = nil
				ItemRack.StartSetSwapTimeout()
				return
			end
			if not ItemRack.AnythingLocked() then
				ItemRack.SetSwapTimeout = nil
				ItemRack.Debug("Equip", "SetSwapping watchdog observed unlocked inventory; resuming without ITEM_LOCK_CHANGED")
				ItemRack.LockChangedDuringSetSwap()
				return
			end
			local timedOutSet = ItemRack.SetSwapping
			local lockReason = ItemRack.GetLockedReason()
			ItemRack.Debug("Equip", "SetSwapping safety timeout - force clearing stuck state for:", timedOutSet)
			ItemRack.SetSwapping = nil
			ItemRack.SetSwappingDisableSound = nil
			ItemRack.SetSwappingIsAutomatic = nil
			ItemRack.SetSwapTimeout = nil
			-- Clear any remaining swap list entries that can't complete
			for i in pairs(ItemRack.SwapList) do
				ItemRack.SwapList[i] = nil
			end
			ItemRack.ClearLockList()
			ItemRack.UpdateCurrentSet()
			ItemRack.Print("Set swap timed out for \""..tostring(timedOutSet).."\": WoW still reports "..tostring(lockReason).." locked. ItemRack reconciled the displayed set state.")
			-- Try to process any sets that were waiting
			if #ItemRack.SetsWaiting > 0 and not ItemRack.AnythingLocked() and not ItemRack.NowCasting
			and not (ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked()) then
				ItemRack.ProcessSetsWaiting()
			end
		end
	end)
end

function ItemRack.AnythingLocked()
	-- Guard: if the cursor is holding an item (e.g. from a failed swap), treat as locked
	if CursorHasItem() then
		return 1
	end
	for i=1,19 do
		if IsInventoryItemLocked(i) then
			return 1
		end
	end
	for i=0,4 do
		for j=1,GetContainerNumSlots(i) do
			if select(3,GetContainerItemInfo(i,j)) then
				return 1
			end
		end
	end
end

function ItemRack.GetLockedReason()
	if CursorHasItem() then
		return "CursorHasItem"
	end
	for i=1,19 do
		if IsInventoryItemLocked(i) then
			return "InventorySlot("..i..")"
		end
	end
	for i=0,4 do
		for j=1,GetContainerNumSlots(i) do
			if select(3,GetContainerItemInfo(i,j)) then
				return "ContainerSlot("..i..","..j..")"
			end
		end
	end
	return "None"
end

function ItemRack.LockChangedDuringSetSwap()
	if not ItemRack.AnythingLocked() then
		local setname = ItemRack.SetSwapping
		local disableSound = ItemRack.SetSwappingDisableSound
		local isAutomatic = ItemRack.SetSwappingIsAutomatic
		ItemRack.Debug("API", "Locks cleared. Resuming interrupted swap list for:", setname)
		ItemRack.SetSwapping = nil
		ItemRack.SetSwappingDisableSound = nil
		ItemRack.SetSwappingIsAutomatic = nil
		ItemRack.IterateSwapList(setname, disableSound)

		-- Re-check: if the second pass locked new items or left work undone,
		-- re-enter swap-waiting mode instead of immediately starting the next swap.
		if next(ItemRack.SwapList) or ItemRack.AnythingLocked() then
			ItemRack.Debug("API", "Secondary locks detected. Pausing swap again for:", setname)
			ItemRack.SetSwapping = setname
			ItemRack.SetSwappingDisableSound = disableSound
			ItemRack.SetSwappingIsAutomatic = isAutomatic
			-- Restart the safety timeout for this new waiting period
			ItemRack.StartSetSwapTimeout()
			return
		end

		ItemRack.EndSetSwap(setname)

		if next(ItemRack.CombatQueue) and not ItemRack.NowCasting and not InCombatLockdown() then
			ItemRack.ProcessCombatQueue()
			if ItemRack.AnythingLocked() then
				return
			end
		end

		if #ItemRack.SetsWaiting > 0 and not ItemRack.NowCasting then
			-- Defer to next frame to let lock state fully settle before starting
			-- the next swap. This prevents the "Internal bag error" from rapid swaps.
			C_Timer.After(0, function()
				if not ItemRack.AnythingLocked() and not ItemRack.NowCasting and #ItemRack.SetsWaiting > 0 then
					ItemRack.ProcessSetsWaiting()
				end
			end)
		end
	end
end

function ItemRack.IterateSwapList(setname, disableSound)
	ItemRack.Debug("Equip", "IterateSwapList running for set:", setname)
	local set = ItemRackUser.Sets[setname]
	local swap = ItemRack.SwapList

	local useSound = GetCVar("Sound_EnableSFX")
	local overrideSound = false
	local usedSurgicalMute = false
	if (disableSound or ItemRackSettings.DisableSwapSound == "ON") and useSound == "1" then
		-- Try surgical muting via LibSoundIndex (mutes equip and UI sounds)
		if ItemRack.MuteSwapSounds(1.5) then
			usedSurgicalMute = true
		else
			-- Fallback: blunt CVar mute (silences ALL SFX)
			SetCVar("Sound_EnableSFX", "0")
			overrideSound = true
		end
	end

	ItemRack.AbortSwap = nil
	ItemRack.ClearLockList()

	local treatAs2H = nil
	local skip, inv, bag, slot
	for k=0,19+ItemRack.eqBackOfTheBusOffset do
		local i = k
		if k >= ItemRack.eqBackOfTheBusOffset then
			i = k-ItemRack.eqBackOfTheBusOffset
		end
		if skip or ItemRack.AbortSwap then
			skip = nil
		elseif swap[k] then
			if swap[k]==0 then -- if intended to be empty
				bag,slot = ItemRack.FindSpace()
				if bag then
					if set.old then
						if set.old[i] == nil then set.old[i] = ItemRack.GetID(i) end
					end
					ItemRack.Debug("Equip", "IterateSwapList emptying slot", i, "to bag", bag, "slot", slot)
					ItemRack.MoveItem(i,nil,bag,slot) -- empty slot
					if not ItemRack.AbortSwap then
						swap[k] = nil
					end
				else
					ItemRack.Debug("Equip", "IterateSwapList aborted: No space to empty slot", i)
					ItemRack.AbortSwap = 1
					ItemRack.ClearLockList()
					return
				end
			else
				inv,bag,slot = ItemRack.FindItem(swap[k],1)
				ItemRack.Debug("Equip", "IterateSwapList FindItem returned: inv=", inv, "bag=", bag, "slot=", slot, "for intended ID:", swap[k])
				if bag then
					if i==16 and ItemRack.HasTitansGrip then
						local subtype = select(7,GetItemInfo(GetContainerItemLink(bag,slot)))
						if subtype and ItemRack.NoTitansGrip[subtype] then
							treatAs2H = 1
						end
					end
					-- TODO: Polarms, Fishing Poles and Staves (7th GetItemInfo) cannot
					-- be equipped alongside Two-Handed Axes, Two-Handed Maces and Two-Handed Swords
					if (not ItemRack.HasTitansGrip or treatAs2H) and select(3,ItemRack.GetInfoByID(swap[k]))=="INVTYPE_2HWEAPON" then
						ItemRack.Debug("Equip", "IterateSwapList determined 2H Weapon logic for:", swap[k])
						-- this is a 2H weapon. swap both slots at once if offhand equipped
						if set.old then
							if set.old[i] == nil then set.old[i] = ItemRack.GetID(i) end
							if set.old[i+1] == nil then set.old[i+1] = ItemRack.GetID(i+1) end
						end
						if GetInventoryItemLink("player",17) then
							local freeBag,freeSlot = ItemRack.FindSpace()
							if freeBag then
								ItemRack.Debug("Equip", "IterateSwapList emptying offhand to bag", freeBag, "slot", freeSlot)
								ItemRack.MoveItem(17,nil,freeBag,freeSlot)
							else
								ItemRack.Debug("Equip", "IterateSwapList aborted: No space for offhand removal.")
								ItemRack.AbortSwap=1
							end
						end
						if not ItemRack.AbortSwap then
							ItemRack.Debug("Equip", "IterateSwapList swapping 2H weapon from bag", bag, "slot", slot, "to slot 16")
							ItemRack.MoveItem(bag,slot,16,nil)
							if not ItemRack.AbortSwap and CursorHasItem() then
								ItemRack.Debug("Equip", "IterateSwapList putting displaced 1H weapon on cursor into bag", bag, "slot", slot)
								PickupContainerItem(bag, slot)
							end
						end
						if not ItemRack.AbortSwap then
							swap[k] = nil
							swap[k+1] = nil -- fix by Romracer
						end
						skip = 1
					else
						if set.old then
							if set.old[i] == nil then set.old[i] = ItemRack.GetID(i) end
						end
						ItemRack.Debug("Equip", "IterateSwapList executing normal move from bag", bag, "slot", slot, "--> slot", i)
						ItemRack.MoveItem(bag,slot,i,nil)
						if not ItemRack.AbortSwap then
							swap[k] = nil
						end
					end
				elseif inv==(i+1) and ItemRack.MatchesStoredItemID(swap[k+1],ItemRack.GetID(i)) then
					-- item is in other slot and other slot wants to go to this one
					ItemRack.Debug("Equip", "IterateSwapList executing localized inner-slot shuffle from slot", i, "to", i+1)
					if set.old then
						if set.old[i] == nil then set.old[i] = ItemRack.GetID(i) end
						if set.old[i+1] == nil then set.old[i+1] = ItemRack.GetID(i+1) end
					end
					ItemRack.MoveItem(i,nil,i+1,nil)
					if not ItemRack.AbortSwap then
						swap[k] = nil
						swap[k+1] = nil
					end
					skip = 1
				end
			end
		end
	end
	-- Only print abort message if there are no remaining items to retry.
	-- During multi-pass swaps, AbortSwap=4 (locked items) is expected and will
	-- be retried via SetSwapping — printing "Another swap is in progress" here is misleading.
	if ItemRack.AbortSwap and not InCombatLockdown() and not next(swap) then
		ItemRack.Print("Swap stopped. "..(ItemRack.AbortReasons[ItemRack.AbortSwap] or ""))
	end
	if ItemRack.AbortSwap then
		ItemRack.ClearLockList()
	end
	-- Safety: if cursor still has an item from a partial swap, clear it so it doesn't
	-- block subsequent swaps. ClearCursor() returns the item to its original location.
	if CursorHasItem() then
		ClearCursor()
	end
	-- CVar fallback restore
	if overrideSound then
		if ItemRack.CVarMuteTimer then
			ItemRack.CVarMuteTimer:Cancel()
		end
		ItemRack.CVarMuteTimer = C_Timer.NewTimer(1.5, function()
			SetCVar("Sound_EnableSFX", "1")
			ItemRack.CVarMuteTimer = nil
		end)
	end
end

function ItemRack.EndSetSwap(setname)
	ItemRack.Debug("Equip", "EndSetSwap called for set:", setname or "nil")
	ItemRack.SetSwapping = nil
	ItemRack.SetSwappingDisableSound = nil
	ItemRack.SetSwappingIsAutomatic = nil
	-- Cancel safety timeout since swap completed normally
	if ItemRack.SetSwapTimeout then
		ItemRack.SetSwapTimeout:Cancel()
		ItemRack.SetSwapTimeout = nil
	end
	if setname then
		if not string.match(setname,"^~") then --do not list internal sets, prefixed with ~
			ItemRackUser.CurrentSet = setname
			C_Timer.After(0.5, ItemRack.UpdateCurrentSet)
			
			-- Dual Spec Support: Auto-Swap Spec if Set is bound
			local set = ItemRackUser.Sets[setname]
			if set.AssociatedSpec then
				if GetActiveTalentGroup and GetNumTalentGroups then
					local currentSpec = GetActiveTalentGroup()
					local numGroups = GetNumTalentGroups()
					local neededSpec = set.AssociatedSpec
					
					if numGroups > 1 and currentSpec ~= neededSpec then
						ItemRack.Print("Set "..setname.." requires Spec "..neededSpec.." (Current: "..currentSpec.."). Switching...")
						if SetActiveTalentGroup then
							-- Preserve the exact set that initiated this spec switch. The
							-- destination Specialization event may point at a different set
							-- that shares the same spec and must not overwrite this choice.
							local request = {
								setname = setname,
								spec = neededSpec,
								expiresAt = GetTime() + 15,
							}
							ItemRack.PendingSpecSet = request
							ItemRack.Debug("Events", "Associated set requested spec switch:", setname, "->", neededSpec)
							C_Timer.After(15,function()
								if ItemRack.PendingSpecSet == request then
									ItemRack.Debug("Events", "Associated spec-set request expired:", setname)
									ItemRack.PendingSpecSet = nil
								end
							end)
							SetActiveTalentGroup(neededSpec)
						end
					else
						-- Diagnostic for when it doesn't switch
						-- ItemRack.Print("Spec Check: No switch needed. neededSpec="..tostring(neededSpec).." current="..tostring(currentSpec).." numGroups="..tostring(numGroups))
					end
				end
			end
		elseif ItemRackUser.Sets[setname].oldset then
			-- Internal set (e.g. ~Unequip, ~CombatQueue) finished restoring gear.
			-- Set CurrentSet back to the set name stored in oldset.
			ItemRackUser.CurrentSet = ItemRackUser.Sets[setname].oldset
			ItemRackUser.Sets[setname].oldset = nil
			C_Timer.After(0.5, ItemRack.UpdateCurrentSet)
		end
		if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
			-- Only jump to the equipped set if the user isn't currently editing one
			if not ItemRackOptSetsSaveButton:IsEnabled() then
				ItemRackOpt.ChangeEditingSet()
			end
		end
		
		ItemRack.UpdateCombatQueue() -- update button gear icon if per set queues is active
	end
--	ItemRack.Print("End of set swap. CurrentSet: "..tostring(ItemRackUser.CurrentSet))
end

-- moves an item from bag,slot to bag,slot (slot is nil for bag=inv)
function ItemRack.MoveItem(fromBag,fromSlot,toBag,toSlot)
	local destSlot = toSlot and "bag" or toBag -- for debug: which inv slot is the target
	local abort
	if CursorHasItem() then
		abort = 2
		ItemRack.Debug("CombatQueue", "MoveItem ABORT=2 (CursorHasItem) dest="..tostring(destSlot))
	elseif SpellIsTargeting() then
		abort = 3
		ItemRack.Debug("CombatQueue", "MoveItem ABORT=3 (SpellIsTargeting) dest="..tostring(destSlot))
	elseif not fromSlot and ItemRack.PhantomItem[GetInventoryItemID("player",fromBag) or 1] then
		ItemRack.Debug("CombatQueue", "MoveItem SKIP (PhantomItem) dest="..tostring(destSlot))
		return  -- oscarucb: ignore swap requests on slots containing "phantom" artifact items
	elseif (not fromSlot and IsInventoryItemLocked(fromBag)) or (not toSlot and IsInventoryItemLocked(toBag)) then
		abort = 4
		ItemRack.Debug("CombatQueue", "MoveItem ABORT=4 (InventoryItemLocked) dest="..tostring(destSlot).." fromLocked="..tostring(not fromSlot and IsInventoryItemLocked(fromBag)).." toLocked="..tostring(not toSlot and IsInventoryItemLocked(toBag)))
	elseif (fromSlot and select(3,GetContainerItemInfo(fromBag,fromSlot))) or (toSlot and select(3,GetContainerItemInfo(toBag,toSlot))) then
		abort = 4
		ItemRack.Debug("CombatQueue", "MoveItem ABORT=4 (ContainerItemLocked) dest="..tostring(destSlot))
	end
	if abort then
		ItemRack.AbortSwap = abort
		return
	else
		ItemRack.Debug("CombatQueue", "MoveItem ATTEMPT from=("..tostring(fromBag)..","..tostring(fromSlot)..") to=("..tostring(toBag)..","..tostring(toSlot)..") combat="..tostring(InCombatLockdown()))
		if fromSlot then
			PickupContainerItem(fromBag,fromSlot)
		else
			PickupInventoryItem(fromBag)
		end
		if toSlot then
			PickupContainerItem(toBag,toSlot)
		else
			if toBag == INVSLOT_AMMO then -- workaround for classic ammo slot weirdness
				toBag = INVSLOT_RANGED
			end
			PickupInventoryItem(toBag)
		end

		-- Return displaced items to source locations to complete swaps:
		if fromSlot and not toSlot and CursorHasItem() then
			-- Moving from container to inventory: place displaced item into source container slot
			PickupContainerItem(fromBag, fromSlot)
		elseif not fromSlot and toSlot and CursorHasItem() then
			-- Moving from inventory to container: place displaced item into source inventory slot
			PickupInventoryItem(fromBag)
		elseif not fromSlot and not toSlot and CursorHasItem() then
			-- Inner-slot shuffle (inventory to inventory): place displaced item into source inventory slot
			PickupInventoryItem(fromBag)
		elseif fromSlot and toSlot and CursorHasItem() then
			-- Container to container: place displaced item into source container slot
			PickupContainerItem(fromBag, fromSlot)
		end

		-- Post-swap safety: if cursor still has an item after return pickup, the swap
		-- was blocked (e.g. by combat timing, GCD, animation, full bag). Clear the cursor
		-- to return whatever is held back to its origin and mark as aborted.
		if CursorHasItem() then
			ItemRack.Debug("CombatQueue", "MoveItem POST-SWAP FAIL: cursor still has item after swap to dest="..tostring(destSlot)..". ClearCursor called.")
			ClearCursor()
			ItemRack.AbortSwap = 4
		else
			ItemRack.Debug("CombatQueue", "MoveItem SUCCESS dest="..tostring(destSlot))
		end
	end
end

function ItemRack.IsSetEquipped(setname,exact)
	if setname and ItemRackUser.Sets[setname] then
		local set = ItemRackUser.Sets[setname].equip
		local id
		local matchesStored = ItemRack.MatchesStoredItemID
		
		-- Special handling for Trinkets and Rings to allow swapped slots
		local check11_12 = (set[11] and set[12])
		local check13_14 = (set[13] and set[14])
		
		local anyChecked = false
		for i in pairs(set) do
			if type(i) == "number" then
				if ItemRackUser.EnableQueues == "ON"
				and (ItemRack.QueueStateReady ~= true or not ItemRack.IsEquippedSlotStateReady(i)) then
					return false
				end
				anyChecked = true
				id = ItemRack.GetID(i)
				local match = false
				
				if (exact and set[i]==id) or (not exact and matchesStored(set[i],id)) then
					match = true
				elseif not exact then
					-- Try cross-slot check for Rings (11/12)
					if (i==11 or i==12) and check11_12 then
						local otherID = ItemRack.GetID(i==11 and 12 or 11)
						if matchesStored(set[i], otherID) then match = true end
					-- Try cross-slot check for Trinkets (13/14)
					elseif (i==13 or i==14) and check13_14 then
						local otherID = ItemRack.GetID(i==13 and 14 or 13)
						if matchesStored(set[i], otherID) then match = true end
					end
				end
				
				-- If auto-queues are globally enabled and this slot has an active
				-- queue, accept whichever queued item is intentionally active for
				-- this set context. Dormant queue settings must not make an unchanged
				-- equipment set appear as "Custom".
				local slotQueue = ItemRack.GetQueues(setname)[i]
				if ItemRackUser.EnableQueues == "ON" and slotQueue and #slotQueue > 0 and ItemRack.GetQueuesEnabled(setname)[i] then
					local currentBaseID = ItemRack.GetIRString(id,true)
					local currentCustomTime
					local currentInQueue = false
					if currentBaseID and currentBaseID ~= 0 then
						-- Use the queue's exact-first migration boundary here too. A
						-- legacy wildcard beside rune-specific entries cannot establish
						-- that an unlisted rune copy is intentionally active for the set.
						local currentQueueIndex = ItemRack.FindQueueEntryIndex(slotQueue,id)
						if currentQueueIndex then
							local currentEntry = slotQueue[currentQueueIndex]
							currentInQueue = true
							currentCustomTime = currentEntry.swapInEnabled and currentEntry.swapIn or nil
						end
						local start,duration,enable = GetInventoryItemCooldown("player",i)
						local ready = ItemRack.ShouldHoldEquippedItem and ItemRack.ShouldHoldEquippedItem(i, id, currentBaseID, currentCustomTime) or ItemRack.ItemNearReady(currentBaseID, i, currentCustomTime)
						local _, active = ItemRack.AutoQueueItemToEquip(i, currentBaseID, enable, ready, setname)
						if currentInQueue then
							match = not active or matchesStored(active, id)
						elseif match and active and not matchesStored(active, id) then
							match = false
						end
					elseif match then
						match = false
					end
				end
				
				if not match then
					ItemRack.Debug("Equip", "IsSetEquipped mismatch: set="..tostring(setname).." slot="..tostring(i).." expected="..tostring(set[i]).." equipped="..tostring(id).." queues="..tostring(ItemRackUser.EnableQueues))
					return false
				end
			end
		end
		
		return anyChecked
	end
end

function ItemRack.UnequipSet(setname, disableSound)
	-- Unequips a set. If 'parentSet' is found, it patches the stack.
	-- Otherwise, it restores the set's 'old' to 'ItemRackUser.CurrentSet' via '~Unequip'.
	if setname and ItemRackUser.Sets[setname] then
		ItemRack.Debug("Equip", "UnequipSet called for:", setname, "- CurrentSet is:", ItemRackUser.CurrentSet)
		if ItemRack.SetSwapping or ItemRack.AnythingLocked() then
			local blockReason = ItemRack.SetSwapping and ("SetSwapping("..tostring(ItemRack.SetSwapping)..")") or ItemRack.GetLockedReason()
			ItemRack.Debug("Equip", "UnequipSet deferred set:", setname, "- locked item:", blockReason)
			ItemRack.AddSetToSetsWaiting(setname,ItemRack.UnequipSet, disableSound)
			return
		end
		
		-- Stack Splicing Logic:
		-- Check if another set (e.g. "Zoomies") is currently holding this set (e.g. "Drank") as its 'oldset'.
		-- If so, we are unequipping a set that is "buried" in the stack (Drinking stopped while Mounted).
		-- We must splice it out: update parent's oldset, restore items, but DO NOT update CurrentSet.
		local parentSet = nil
		for sName, sData in pairs(ItemRackUser.Sets) do
			if not string.match(sName, "^~") and sData.oldset == setname and sName ~= setname then -- ensure not self-referential
				parentSet = sName
				break 
			end
		end

		local old = ItemRackUser.Sets[setname].old
		local unequip = ItemRackUser.Sets["~Unequip"].equip
		for i in pairs(unequip) do
			unequip[i] = nil
		end
		if old then
			for i in pairs(old) do
				if type(i) == "number" then
					unequip[i] = old[i]
				end
			end
		end
		
		local shouldRestore = false
		local isPendingOrSwapping = false
		if ItemRack.SetSwapping == setname then
			isPendingOrSwapping = true
		elseif ItemRack.SetsWaiting then
			for _, q in ipairs(ItemRack.SetsWaiting) do
				if q[1] == setname then
					isPendingOrSwapping = true
					break
				end
			end
		end

		if ItemRackUser.CurrentSet == setname then
			ItemRack.Debug("Equip", "Top of stack normal unequip. shouldRestore = true")
			shouldRestore = true
			ItemRackUser.Sets["~Unequip"].oldset = ItemRackUser.Sets[setname].oldset
			ItemRackUser.Sets["~Unequip"].ShowHelm = nil
			ItemRackUser.Sets["~Unequip"].ShowCloak = nil
			if ItemRackUser.Sets[ItemRackUser.Sets["~Unequip"].oldset] then
				ItemRackUser.Sets["~Unequip"].ShowHelm = ItemRackUser.Sets[ItemRackUser.Sets["~Unequip"].oldset].ShowHelm
				ItemRackUser.Sets["~Unequip"].ShowCloak = ItemRackUser.Sets[ItemRackUser.Sets["~Unequip"].oldset].ShowCloak
			end
		elseif isPendingOrSwapping then
			ItemRack.Debug("Equip", "Pending API locks detected for top stack. shouldRestore = true")
			shouldRestore = true
			ItemRackUser.Sets["~Unequip"].oldset = ItemRackUser.Sets[setname].oldset
			ItemRackUser.Sets["~Unequip"].ShowHelm = nil
			ItemRackUser.Sets["~Unequip"].ShowCloak = nil
			if ItemRackUser.Sets[ItemRackUser.Sets["~Unequip"].oldset] then
				ItemRackUser.Sets["~Unequip"].ShowHelm = ItemRackUser.Sets[ItemRackUser.Sets["~Unequip"].oldset].ShowHelm
				ItemRackUser.Sets["~Unequip"].ShowCloak = ItemRackUser.Sets[ItemRackUser.Sets["~Unequip"].oldset].ShowCloak
			end
		elseif ItemRack.IsSetEquipped(setname) and (not ItemRackUser.CurrentSet or not ItemRackUser.Sets[ItemRackUser.CurrentSet] or not ItemRack.IsSetEquipped(ItemRackUser.CurrentSet)) then
			ItemRack.Debug("Equip", "Physical gear still matches set and CurrentSet drifted stale. shouldRestore = true")
			shouldRestore = true
			ItemRackUser.Sets["~Unequip"].oldset = ItemRackUser.Sets[setname].oldset
			ItemRackUser.Sets["~Unequip"].ShowHelm = nil
			ItemRackUser.Sets["~Unequip"].ShowCloak = nil
			if ItemRackUser.Sets[ItemRackUser.Sets["~Unequip"].oldset] then
				ItemRackUser.Sets["~Unequip"].ShowHelm = ItemRackUser.Sets[ItemRackUser.Sets["~Unequip"].oldset].ShowHelm
				ItemRackUser.Sets["~Unequip"].ShowCloak = ItemRackUser.Sets[ItemRackUser.Sets["~Unequip"].oldset].ShowCloak
			end
		elseif parentSet then
			ItemRack.Debug("Equip", "parentSet found:", parentSet, "- Stack splicing.")
			ItemRackUser.Sets[parentSet].oldset = ItemRackUser.Sets[setname].oldset
			
			if ItemRackUser.EventStack then
				for _, eName in ipairs(ItemRackUser.EventStack) do
					if ItemRack.GetEventSet and ItemRack.GetEventSet(eName) == parentSet then
						shouldRestore = true
						break
					end
				end
			end
			ItemRack.Debug("Equip", "parentSet shouldRestore evaluated to:", shouldRestore)
			ItemRackUser.Sets["~Unequip"].oldset = nil
			ItemRackUser.Sets["~Unequip"].ShowHelm = nil
			ItemRackUser.Sets["~Unequip"].ShowCloak = nil
		end
		
		if shouldRestore then
			local dbgStr = ""
			for k,v in pairs(ItemRackUser.Sets["~Unequip"].equip) do
				dbgStr = dbgStr .. tostring(k)..":"..tostring(v).." "
			end
			ItemRack.Debug("Equip", "DIAGNOSTIC - ~Unequip contains:", (dbgStr == "" and "EMPTY" or dbgStr))
			ItemRack.Debug("Equip", "Equipping ~Unequip to restore items.")
			ItemRack.EquipSet("~Unequip", disableSound)
		else
			ItemRack.Debug("Equip", "shouldRestore is FALSE (CurrentSet doesn't match and not buried). Wiping .old data for setname:", setname)
			-- Restore was suppressed (manual override). Clean up stale old/oldset
			-- on the popped set so it doesn't linger in SavedVariables.
			if old then
				for k in pairs(old) do
					old[k] = nil
				end
			end
			ItemRackUser.Sets[setname].oldset = nil
		end
	end
end

function ItemRack.ToggleSet(setname,exact,disableSound,isSecureKeybind)
	if ItemRack.IsSetEquipped(setname,exact) then
--		print("remove "..setname)
		ItemRack.UnequipSet(setname,disableSound)
	else
--		print("equip "..setname)
		ItemRack.EquipSet(setname,disableSound,isSecureKeybind)
	end
end
