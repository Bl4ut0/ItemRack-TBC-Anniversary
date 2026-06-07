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
	local setwaiting = ItemRack.SetsWaiting[1][1]
	local whichequip = ItemRack.SetsWaiting[1][2]
	local disableSound = ItemRack.SetsWaiting[1][3]
	local isSecureKeybind = ItemRack.SetsWaiting[1][4]
	table.remove(ItemRack.SetsWaiting,1)
	
	-- Safety: Skip sets that no longer exist (prevents getting stuck)
	if not ItemRackUser.Sets[setwaiting] then
		ItemRack.Debug("API", "ProcessSetsWaiting aborted: set no longer exists ->", setwaiting)
		-- Set was deleted, skip it and try the next one
		if #ItemRack.SetsWaiting > 0 then
			ItemRack.ProcessSetsWaiting()
		end
		return
	end
	
	ItemRack.Debug("API", "ProcessSetsWaiting executing callback for:", setwaiting)
	whichequip(setwaiting, disableSound, isSecureKeybind)
end

function ItemRack.AddSetToSetsWaiting(setwaiting,whichequip,disableSound,isSecureKeybind)
	local wait = ItemRack.SetsWaiting
	for i in pairs(wait) do
		if wait[i][1]==setwaiting and wait[i][2]==whichequip then
			ItemRack.Debug("API", "AddSetToSetsWaiting ignored duplicate for:", setwaiting)
			return
		end
	end
	ItemRack.Debug("API", "AddSetToSetsWaiting added set to API lock queue:", setwaiting)
	table.insert(wait,{setwaiting,whichequip,disableSound,isSecureKeybind})
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

function ItemRack.EquipSet(setname, disableSound, isSecureKeybind)
	ItemRack.Debug("Equip", "EquipSet invoked for set:", setname or "nil")
	if not setname or not ItemRackUser.Sets[setname] then
		ItemRack.Print("Set \""..tostring(setname).."\" doesn't exist.")
		return
	end
	if ItemRack.AnythingLocked() then
		ItemRack.Debug("Equip", "EquipSet deferred set:", setname, "- locked item:", ItemRack.GetLockedReason())
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
	if ItemRack.BurntQueueItems and not isInternalSet then
		for i in pairs(set.equip) do
			if type(i) == "number" then
				ItemRack.BurntQueueItems[i] = nil
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
			set.oldset = ItemRackUser.CurrentSet
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
 
	-- if in combat, dead, or casting, queue items for later
	-- PickupInventoryItem is blocked by the game during InCombatLockdown()
	-- Exception: when triggered via secure keybind in combat, if the ACTUAL swap
	-- only involves weapon slots (16-18), the SecureActionButton's /equipslot [combat]
	-- macro already handled them — skip the queue. This works whether the set is
	-- weapon-only or a full gear set that only needs weapons changed right now.
	if InCombatLockdown() or ItemRack.IsPlayerReallyDead() or ItemRack.NowCasting then
		local reason = InCombatLockdown() and "combat" or (ItemRack.NowCasting and "casting" or "dead")
		-- Check if the actual swap is weapon-only at runtime
		local swapIsWeaponOnly = isSecureKeybind and InCombatLockdown()
		if swapIsWeaponOnly then
			for i in pairs(swap) do
				if i < 16 or i > 18 then
					swapIsWeaponOnly = false
					break
				end
			end
		end
		ItemRack.Debug("Equip", "EquipSet DEFERRED: set=" .. tostring(setname) .. " reason=" .. reason .. " swapIsWeaponOnly=" .. tostring(swapIsWeaponOnly))
		if swapIsWeaponOnly then
			-- Secure macro already handled all weapon slots — just clear the swap
			for i in pairs(swap) do
				ItemRack.Debug("Equip", "  slot " .. tostring(i) .. " SKIPPED (secure macro handled weapon swap in combat)")
				swap[i] = nil
			end
		else
			-- Non-weapon slots need changing — queue everything for after combat
			for i in pairs(swap) do
				ItemRack.Debug("Equip", "  slot " .. tostring(i) .. " -> " .. tostring(swap[i]))
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
		ItemRack.EndSetSwap(setname)
		return -- leave if swap completed on first pass
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
			ItemRack.Debug("Equip", "SetSwapping safety timeout — force clearing stuck state for:", ItemRack.SetSwapping)
			ItemRack.SetSwapping = nil
			ItemRack.SetSwappingDisableSound = nil
			ItemRack.SetSwapTimeout = nil
			-- Clear any remaining swap list entries that can't complete
			for i in pairs(ItemRack.SwapList) do
				ItemRack.SwapList[i] = nil
			end
			-- Try to process any sets that were waiting
			if #ItemRack.SetsWaiting > 0 and not ItemRack.AnythingLocked() and not ItemRack.NowCasting then
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
		ItemRack.Debug("API", "Locks cleared. Resuming interrupted swap list for:", setname)
		ItemRack.SetSwapping = nil
		ItemRack.SetSwappingDisableSound = nil
		ItemRack.IterateSwapList(setname, disableSound)

		-- Re-check: if the second pass locked new items or left work undone,
		-- re-enter swap-waiting mode instead of immediately starting the next swap.
		if next(ItemRack.SwapList) or ItemRack.AnythingLocked() then
			ItemRack.Debug("API", "Secondary locks detected. Pausing swap again for:", setname)
			ItemRack.SetSwapping = setname
			ItemRack.SetSwappingDisableSound = disableSound
			-- Restart the safety timeout for this new waiting period
			ItemRack.StartSetSwapTimeout()
			return
		end

		ItemRack.EndSetSwap(setname)

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
				elseif inv==(i+1) and ItemRack.SameID(swap[k+1],ItemRack.GetID(i)) then
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
		-- Post-swap safety: if cursor still has an item, the target pickup was
		-- blocked (e.g. by combat timing, GCD, animation). Return the item to
		-- its source immediately so nothing gets stuck on the cursor.
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
		local same = ItemRack.SameID
		
		-- Special handling for Trinkets and Rings to allow swapped slots
		local check11_12 = (set[11] and set[12])
		local check13_14 = (set[13] and set[14])
		
		local anyChecked = false
		for i in pairs(set) do
			if type(i) == "number" then
				anyChecked = true
				id = ItemRack.GetID(i)
				local match = false
				
				if (exact and set[i]==id) or (not exact and same(set[i],id)) then
					match = true
				elseif not exact then
					-- Try cross-slot check for Rings (11/12)
					if (i==11 or i==12) and check11_12 then
						local otherID = ItemRack.GetID(i==11 and 12 or 11)
						if same(set[i], otherID) then match = true end
					-- Try cross-slot check for Trinkets (13/14)
					elseif (i==13 or i==14) and check13_14 then
						local otherID = ItemRack.GetID(i==13 and 14 or 13)
						if same(set[i], otherID) then match = true end
					end
				end
				
				-- If the slot has an active auto-queue, accept whichever queued item
				-- is intentionally active for this set context, and reject only when
				-- the queue would still swap to something else.
				local slotQueue = ItemRack.GetQueues(setname)[i]
				if slotQueue and #slotQueue > 0 and ItemRack.GetQueuesEnabled(setname)[i] then
					local currentBaseID = ItemRack.GetIRString(id,true)
					local currentCustomTime
					local currentInQueue = false
					if currentBaseID and currentBaseID ~= 0 then
						for q=1,#slotQueue do
							if slotQueue[q].id == 0 then
								break
							end
							local queueBaseID = ItemRack.GetIRString(slotQueue[q].id,true)
							if ItemRack.SameExactID(slotQueue[q].id, id) or queueBaseID == currentBaseID then
								currentInQueue = true
								currentCustomTime = slotQueue[q].swapInEnabled and slotQueue[q].swapIn or nil
								break
							end
						end
						local start,duration,enable = GetInventoryItemCooldown("player",i)
						local ready = ItemRack.ItemNearReady(currentBaseID, i, currentCustomTime)
						local active = ItemRack.AutoQueueItemToEquip(i, currentBaseID, enable, ready, setname)
						if currentInQueue then
							match = not active or same(active, id)
						elseif match and active and not same(active, id) then
							match = false
						end
					elseif match then
						match = false
					end
				end
				
				if not match then return false end
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
		if ItemRack.AnythingLocked() then
			ItemRack.Debug("Equip", "UnequipSet deferred set:", setname, "- locked item:", ItemRack.GetLockedReason())
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
