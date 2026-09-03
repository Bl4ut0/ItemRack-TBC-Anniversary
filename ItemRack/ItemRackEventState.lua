-- ItemRackEventState.lua
--
-- Pure logical ownership for automatic equipment events.  Each activation has
-- its own frame and per-slot history; physical set names are labels, never
-- ownership keys.  The reducer emits a coalesced slot plan but performs no WoW
-- API calls, which keeps buried removals deterministic and testable.

ItemRack.EventFrames = ItemRack.EventFrames or {}
local EventFrames = ItemRack.EventFrames

local function SameValue(left, right)
	return left == right
end

local function CopySlots(slots)
	local copy = {}
	for slot,value in pairs(slots or {}) do
		if type(slot) == "number" then copy[slot] = value end
	end
	return copy
end

local function CopyValue(value,seen)
	if type(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local copy = {}
	seen[value] = copy
	for key,item in pairs(value) do
		copy[CopyValue(key,seen)] = CopyValue(item,seen)
	end
	return copy
end

local function FindOrderIndex(state, frameId)
	for index,id in ipairs(state.order) do
		if id == frameId then return index end
	end
end

local function EffectiveBelow(state, orderIndex, slot)
	for index=orderIndex-1,1,-1 do
		local frame = state.frames[state.order[index]]
		local owned = frame and frame.slots[slot]
		if owned then return owned.target end
	end
end

local function EffectiveTarget(state, slot)
	for index=#state.order,1,-1 do
		local frame = state.frames[state.order[index]]
		local owned = frame and frame.slots[slot]
		if owned then return owned.target,frame end
	end
end

function EventFrames.NewState()
	return {
		schema = 1,
		revision = 0,
		nextFrameId = 1,
		order = {},
		byEvent = {},
		frames = {},
	}
end

function EventFrames.IsState(value)
	return type(value) == "table" and value.schema == 1
		and type(value.order) == "table"
		and type(value.byEvent) == "table"
		and type(value.frames) == "table"
end

function EventFrames.EffectiveTarget(state, slot)
	return EffectiveTarget(state,slot)
end

function EventFrames.ValidateOwner(state, owner, slot, target)
	if not EventFrames.IsState(state) or type(owner) ~= "table"
	or owner.kind ~= "event" or owner.revision ~= state.revision then
		return false
	end
	local frame = state.frames[owner.frameId]
	local owned = frame and frame.slots[slot]
	if not owned or frame.eventName ~= owner.eventName then return false end
	local effective,effectiveFrame = EffectiveTarget(state,slot)
	return effectiveFrame == frame and SameValue(effective,target)
end

function EventFrames.Activate(state, activation)
	if not EventFrames.IsState(state) then
		return { changed=false, targets={}, reason="invalid_state" }
	end
	if type(activation) ~= "table" or type(activation.eventName) ~= "string"
	or type(activation.slots) ~= "table" then
		return { changed=false, targets={}, reason="invalid_activation" }
	end

	local existingId = state.byEvent[activation.eventName]
	local replacementTargets = {}
	local replacementVisible = {}
	local replacing = false
	if existingId then
		local existing = state.frames[existingId]
		if existing and existing.eventGeneration == activation.eventGeneration then
			return { changed=false, frameId=existingId, targets={} }
		end
		-- A newer generation for the same logical event replaces the old frame.
		-- Reuse Pop so its prior ownership is spliced correctly first, retaining
		-- the restoration plan for slots the replacement no longer owns.
		replacing = true
		for slot in pairs(activation.slots) do
			if type(slot) == "number" then
				replacementVisible[slot] = EffectiveTarget(state,slot)
			end
		end
		local removed = EventFrames.Pop(state,activation.eventName,
			existing and existing.eventGeneration)
		for slot,target in pairs(removed.targets or {}) do
			replacementTargets[slot] = target
		end
	end

	local frameId = state.nextFrameId
	state.nextFrameId = frameId + 1
	local insertIndex = #state.order + 1
	if activation.beforeFrameId then
		insertIndex = FindOrderIndex(state,activation.beforeFrameId) or insertIndex
	end
	local frame = {
		id = frameId,
		eventName = activation.eventName,
		eventGeneration = activation.eventGeneration,
		setName = activation.setName,
		sequence = frameId,
		origin = activation.origin,
		restoreOnExit = activation.restoreOnExit ~= false,
		status = "active",
		slots = {},
	}
	local targets = replacementTargets
	for slot,target in pairs(CopySlots(activation.slots)) do
		local higherSlot
		if insertIndex <= #state.order then
			for index=insertIndex,#state.order do
				local higherFrame = state.frames[state.order[index]]
				if higherFrame and higherFrame.slots[slot] then
					higherSlot = higherFrame.slots[slot]
					break
				end
			end
		end
		local prior
		if insertIndex <= #state.order then
			prior = EffectiveBelow(state,insertIndex,slot)
		else
			prior = EffectiveTarget(state,slot)
		end
		if prior == nil and higherSlot then prior = higherSlot.prior end
		if prior == nil and replacing and replacementTargets[slot] ~= nil then
			-- The removed top frame's Pop target is the logical layer below it.
			-- Use that for future restoration even though the old item remains
			-- physically visible until this coalesced replacement plan is applied.
			prior = replacementTargets[slot]
		end
		if prior == nil then prior = activation.observed and activation.observed[slot] end
		-- nil means the first physical observation is not reliable yet.  Such a
		-- slot is deliberately not owned; empty equipment is represented by 0.
		if prior ~= nil then
			frame.slots[slot] = { target=target, prior=prior, state="planned" }
			if higherSlot then
				higherSlot.prior = target
				if replacing then targets[slot] = nil end
			elseif replacing then
				-- Pop and Activate are one logical replacement. Coalesce their
				-- physical plans against what is still visible, so an unchanged
				-- retained target does not briefly restore while an old-only slot
				-- still receives Pop's restoration target.
				local visible = activation.observed and activation.observed[slot]
				if visible == nil then visible = replacementVisible[slot] end
				if visible ~= nil then
					if SameValue(target,visible) then
						targets[slot] = nil
					else
						targets[slot] = target
					end
				elseif not SameValue(target,prior) then
					targets[slot] = target
				end
			elseif not SameValue(target,prior) then
				targets[slot] = target
			end
		end
	end

	state.frames[frameId] = frame
	state.byEvent[activation.eventName] = frameId
	table.insert(state.order,insertIndex,frameId)
	state.revision = state.revision + 1
	return { changed=true, frameId=frameId, targets=targets, revision=state.revision }
end

function EventFrames.Pop(state, eventName, eventGeneration)
	local empty = { removed=false, targets={} }
	if not EventFrames.IsState(state) then
		empty.reason = "invalid_state"
		return empty
	end
	local frameId = state.byEvent[eventName]
	local frame = frameId and state.frames[frameId]
	if not frame then return empty end
	if eventGeneration ~= nil and frame.eventGeneration ~= eventGeneration then
		empty.reason = "stale_generation"
		return empty
	end
	local removedIndex = FindOrderIndex(state,frameId)
	if not removedIndex then return empty end

	local targets = {}
	for slot,removedSlot in pairs(frame.slots) do
		local higherSlot
		for index=removedIndex+1,#state.order do
			local higherFrame = state.frames[state.order[index]]
			if higherFrame and higherFrame.slots[slot] then
				higherSlot = higherFrame.slots[slot]
				break
			end
		end
		if higherSlot then
			-- The visible higher owner stays untouched, but it inherits the removed
			-- layer's prior so its eventual exit reaches the correct lower state.
			higherSlot.prior = removedSlot.prior
		elseif frame.restoreOnExit then
			local lower = EffectiveBelow(state,removedIndex,slot)
			local restore = removedSlot.prior
			if lower ~= nil and not SameValue(lower,restore) then
				-- Prior is normally already the effective lower plan.  Prefer the
				-- current lower owner if a migrated/repaired state disagrees.
				restore = lower
			end
			if not SameValue(removedSlot.target,restore) then
				targets[slot] = restore
			end
		end
	end

	table.remove(state.order,removedIndex)
	state.frames[frameId] = nil
	state.byEvent[eventName] = nil
	state.revision = state.revision + 1
	return { removed=true, frameId=frameId, targets=targets, revision=state.revision }
end

function EventFrames.SnapshotSet(set)
	return CopySlots(set and set.equip)
end

function EventFrames.ReleaseSlots(state, slots)
	if not EventFrames.IsState(state) then return false end
	local changed = false
	for slot in pairs(slots or {}) do
		if type(slot) == "number" then
			for _,frameId in ipairs(state.order) do
				local frame = state.frames[frameId]
				if frame and frame.slots[slot] then
					frame.slots[slot] = nil
					changed = true
				end
			end
		end
	end
	if changed then state.revision = state.revision + 1 end
	return changed
end

local function SortedListRecords(list)
	local records = {}
	for index,value in pairs(type(list) == "table" and list or {}) do
		if type(index) == "number" and index >= 1 and index == math.floor(index) then
			table.insert(records,{ index=index, value=value })
		end
	end
	table.sort(records,function(left,right) return left.index < right.index end)
	return records
end

local function RecordMigrationIssue(report,reason,eventName,value)
	report.issues = report.issues or {}
	table.insert(report.issues,{
		reason=reason,
		eventName=eventName,
		value=CopyValue(value),
	})
end

local function ValidateLegacyCandidate(input,eventName,report)
	if type(eventName) ~= "string" or eventName == "" then
		RecordMigrationIssue(report,"invalid_event_name",nil,eventName)
		return nil
	end
	local eventData = type(input.events) == "table" and input.events[eventName]
	if type(eventData) ~= "table" then
		RecordMigrationIssue(report,"missing_event",eventName)
		return nil
	end
	if type(input.enabled) == "table" and not input.enabled[eventName] then
		RecordMigrationIssue(report,"disabled_event",eventName)
		return nil
	end
	if eventData.Type == "Script" then
		RecordMigrationIssue(report,"transient_script_event",eventName)
		return nil
	end
	local setName = type(input.eventSets) == "table" and input.eventSets[eventName]
	local set = setName and type(input.sets) == "table" and input.sets[setName]
	if type(set) ~= "table" or type(set.equip) ~= "table" then
		RecordMigrationIssue(report,"missing_event_set",eventName,setName)
		return nil
	end
	return { eventName=eventName, eventData=eventData, setName=setName, set=set }
end

local function CandidatesCommute(candidates)
	local targets = {}
	for _,candidate in ipairs(candidates) do
		for slot,target in pairs(candidate.set.equip) do
			if type(slot) == "number" then
				if targets[slot] ~= nil and not SameValue(targets[slot],target) then
					return false
				end
				targets[slot] = target
			end
		end
	end
	return true
end

local function OrderCandidatesByOldset(candidates)
	local bySet = {}
	for _,candidate in ipairs(candidates) do
		if bySet[candidate.setName] then return nil end
		bySet[candidate.setName] = candidate
	end
	local ordered,used = {},{}
	while #ordered < #candidates do
		local nextCandidate
		for _,candidate in ipairs(candidates) do
			if not used[candidate.eventName] then
				local parent = candidate.set.oldset
				if not bySet[parent] or used[bySet[parent].eventName] then
					if nextCandidate then return nil end
					nextCandidate = candidate
				end
			end
		end
		if not nextCandidate then return nil end
		used[nextCandidate.eventName] = true
		table.insert(ordered,nextCandidate)
	end
	return ordered
end

-- Convert recoverable pre-frame ownership into canonical per-event frames.
-- The migration never emits equipment targets: it describes gear that legacy
-- state says is already active, and retains only slots with a usable prior.
function EventFrames.MigrateLegacy(input)
	input = type(input) == "table" and input or {}
	local state = EventFrames.NewState()
	local report = {
		source="none",
		candidates=0,
		framesMigrated=0,
		slotsMigrated=0,
		slotsWithoutPrior=0,
		slotsReleasedForMismatch=0,
		issues={},
	}
	local candidates,seen = {},{}
	local stackRecords = SortedListRecords(input.eventStack)
	local lastIndex = {}
	for _,record in ipairs(stackRecords) do
		if type(record.value) == "string" then lastIndex[record.value] = record.index end
	end
	for _,record in ipairs(stackRecords) do
		local eventName = record.value
		if type(eventName) == "string" and lastIndex[eventName] ~= record.index then
			RecordMigrationIssue(report,"duplicate_event",eventName,record.index)
		else
			local candidate = ValidateLegacyCandidate(input,eventName,report)
			if candidate and not seen[eventName] then
				seen[eventName] = true
				table.insert(candidates,candidate)
			end
		end
	end
	if #candidates > 0 then
		report.source = "event_stack"
	else
		local activeNames = {}
		for eventName,active in pairs(type(input.activeEvents) == "table" and input.activeEvents or {}) do
			if active and type(eventName) == "string" then
				table.insert(activeNames,eventName)
			elseif active then
				RecordMigrationIssue(report,"invalid_event_name",nil,eventName)
			end
		end
		table.sort(activeNames)
		for _,eventName in ipairs(activeNames) do
			local candidate = ValidateLegacyCandidate(input,eventName,report)
			if candidate then table.insert(candidates,candidate) end
		end
		if #candidates == 1 then
			report.source = "single_active_flag"
		elseif #candidates > 1 and CandidatesCommute(candidates) then
			report.source = "commutative_active_flags"
		elseif #candidates > 1 then
			local ordered = OrderCandidatesByOldset(candidates)
			if ordered then
				candidates = ordered
				report.source = "oldset_chain"
			else
				RecordMigrationIssue(report,"ambiguous_active_order",nil,activeNames)
				candidates = {}
				report.source = "ambiguous_active_flags"
			end
		end
	end

	report.candidates = #candidates
	local generation = 0
	for _,candidate in ipairs(candidates) do
		generation = generation + 1
		local slots = CopySlots(candidate.set.equip)
		local observed = {}
		local restoreOnExit = candidate.eventData.Unequip and true or false
		for slot,target in pairs(slots) do
			local prior = type(candidate.set.old) == "table" and candidate.set.old[slot]
			if prior == nil and candidate.set.oldset and type(input.sets) == "table" then
				local priorSet = input.sets[candidate.set.oldset]
				prior = priorSet and type(priorSet.equip) == "table" and priorSet.equip[slot]
			end
			if prior == nil and not restoreOnExit then prior = target end
			if prior ~= nil then
				observed[slot] = prior
			end
		end
		local result = EventFrames.Activate(state,{
			eventName=candidate.eventName,
			eventGeneration=generation,
			setName=candidate.setName,
			origin=candidate.eventData.Type,
			restoreOnExit=restoreOnExit,
			slots=slots,
			observed=observed,
		})
		local frame = result.frameId and state.frames[result.frameId]
		if frame then
			frame.status = "migrated"
			report.framesMigrated = report.framesMigrated + 1
			for _ in pairs(frame.slots) do
				report.slotsMigrated = report.slotsMigrated + 1
			end
			for slot in pairs(slots) do
				if not frame.slots[slot] then
					report.slotsWithoutPrior = report.slotsWithoutPrior + 1
				end
			end
		end
	end

	-- If reliable current equipment disagrees with the effective legacy target,
	-- treat that slot as a manual/newer owner. Dropping all frame ownership for
	-- the slot is safer than later restoring stale history over visible gear.
	local mismatched = {}
	for slot,current in pairs(type(input.observed) == "table" and input.observed or {}) do
		local target = EffectiveTarget(state,slot)
		if target ~= nil then
			local matches = type(input.matches) == "function"
				and input.matches(target,current) or SameValue(target,current)
			if not matches then
				mismatched[slot] = true
				report.slotsReleasedForMismatch = report.slotsReleasedForMismatch + 1
				RecordMigrationIssue(report,"observed_target_mismatch",nil,
					{ slot=slot, expected=target, observed=current })
			end
		end
	end
	if next(mismatched) then EventFrames.ReleaseSlots(state,mismatched) end
	return state,report
end

function EventFrames.ProjectStack(state)
	local stack = {}
	if not EventFrames.IsState(state) then return stack end
	for _,frameId in ipairs(state.order) do
		local frame = state.frames[frameId]
		if frame then table.insert(stack,frame.eventName) end
	end
	return stack
end
