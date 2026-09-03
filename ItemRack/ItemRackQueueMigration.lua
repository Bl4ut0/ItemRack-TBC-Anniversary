-- Versioned, idempotent queue-schema migration.
--
-- v4.29.8 stopped declaring ItemRackItems before its per-item queue settings
-- could be copied into the new per-entry representation. The TOC declares that
-- legacy global again so direct upgrades can recover it. This module never
-- clears ItemRackItems: it remains the account-wide recovery copy for other
-- characters and for rollback inspection.

ItemRack.QueueMigration = ItemRack.QueueMigration or {}
local Migration = ItemRack.QueueMigration

Migration.SchemaVersion = 2

local function DeepCopy(value,seen)
	if type(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local copy = {}
	seen[value] = copy
	for key,entry in pairs(value) do
		copy[DeepCopy(key,seen)] = DeepCopy(entry,seen)
	end
	return copy
end

local function IsListIndex(index)
	return type(index) == "number" and index >= 1 and index == math.floor(index)
end

local function LegacySettingsFor(id,legacyItems,getBaseID)
	if type(legacyItems) ~= "table" or (id ~= nil and tostring(id) == "0") then return nil end
	local baseID
	if type(getBaseID) == "function" then
		local ok,result = pcall(getBaseID,id)
		if ok then baseID = result end
	end
	if baseID == nil then
		baseID = string.match(tostring(id or ""),"^%-?(%d+)")
	end
	if baseID == nil then return nil end
	local settings = legacyItems[baseID] or legacyItems[tostring(baseID)]
		or legacyItems[tonumber(baseID)]
	return type(settings) == "table" and settings or nil
end

local function NormalizeEntry(entry,legacyItems,getBaseID)
	local changed = false
	if type(entry) ~= "table" then
		if type(entry) ~= "number" and type(entry) ~= "string" then
			return nil,false,"invalid_entry_type"
		end
		entry = { id=entry }
		changed = true
	elseif entry.id == nil then
		return nil,false,"missing_id"
	end

	if type(entry.id) ~= "number" and type(entry.id) ~= "string" then
		return nil,false,"invalid_id_type"
	end
	if entry.id == "" then return nil,false,"empty_id" end
	if tostring(entry.id) == "0" and entry.id ~= 0 then
		entry.id = 0
		changed = true
	end

	local legacy = LegacySettingsFor(entry.id,legacyItems,getBaseID) or {}
	for key,value in pairs(legacy) do
		if key ~= "id" and entry[key] == nil then
			if key == "priority" or key == "keep" then
				entry[key] = value and true or false
			elseif key == "delay" then
				entry[key] = tonumber(value) or 0
			else
				entry[key] = DeepCopy(value)
			end
			changed = true
		end
	end
	if entry.priority == nil then
		entry.priority = false
		changed = true
	end
	if entry.keep == nil then
		entry.keep = false
		changed = true
	end
	if entry.delay == nil then
		entry.delay = 0
		changed = true
	elseif tonumber(entry.delay) == nil then
		entry.delay = 0
		changed = true
	end
	return entry,changed
end

local function RecordQuarantine(user,scope,slot,index,value,reason)
	if type(user.QueueMigrationQuarantine) ~= "table" then
		user.QueueMigrationQuarantine = {}
	end
	table.insert(user.QueueMigrationQuarantine,{
		scope=scope,
		slot=slot,
		index=index,
		reason=reason,
		value=DeepCopy(value),
	})
end

local function InsertSafetyBoundary(normalized,report)
	table.insert(normalized,{ id=0, priority=false, keep=false, delay=0 })
	report.boundariesInserted = report.boundariesInserted + 1
end

local function NormalizeQueue(user,queue,scope,slot,legacyItems,getBaseID,report)
	if type(queue) ~= "table" then return end
	local indexed = {}
	for index,entry in pairs(queue) do
		if IsListIndex(index) then
			table.insert(indexed,{ index=index, entry=entry })
		end
	end
	table.sort(indexed,function(left,right) return left.index < right.index end)

	local normalized = {}
	local expectedIndex = 1
	local boundarySeen = false
	for _,record in ipairs(indexed) do
		report.entriesVisited = report.entriesVisited + 1
		local entry,changed,rejection = NormalizeEntry(record.entry,legacyItems,getBaseID)
		if entry then
			local isStop = entry.id == 0
			if record.index > expectedIndex and not boundarySeen and not isStop then
				InsertSafetyBoundary(normalized,report)
				boundarySeen = true
			end
			table.insert(normalized,entry)
			if isStop then boundarySeen = true end
			if changed then report.entriesChanged = report.entriesChanged + 1 end
			if record.index ~= #normalized then report.queuesCompacted = report.queuesCompacted + 1 end
		else
			report.entriesQuarantined = report.entriesQuarantined + 1
			RecordQuarantine(user,scope,slot,record.index,record.entry,rejection)
			if not boundarySeen then
				InsertSafetyBoundary(normalized,report)
				boundarySeen = true
			end
		end
		expectedIndex = record.index + 1
	end

	for index in pairs(queue) do
		if IsListIndex(index) then queue[index] = nil end
	end
	for index,entry in ipairs(normalized) do queue[index] = entry end
	report.queuesVisited = report.queuesVisited + 1
end

local function CanonicalSlotKey(key)
	if type(key) ~= "string" or not string.match(key,"^%d+$") then return nil end
	local slot = tonumber(key)
	if slot and slot >= 0 and slot <= 19 and slot == math.floor(slot) then
		return slot
	end
end

local function NormalizeSlotKeys(user,container,scope,report)
	local moves = {}
	for key,value in pairs(container) do
		local slot = CanonicalSlotKey(key)
		if slot ~= nil then table.insert(moves,{ key=key, slot=slot, value=value }) end
	end
	for _,move in ipairs(moves) do
		if container[move.slot] ~= nil then
			report.slotKeysQuarantined = report.slotKeysQuarantined + 1
			RecordQuarantine(user,scope,move.slot,move.key,move.value,"duplicate_slot_key")
		else
			container[move.slot] = move.value
			report.slotKeysNormalized = report.slotKeysNormalized + 1
		end
		container[move.key] = nil
	end
end

local function NormalizeEnabledValues(user,container,scope,report)
	for slot,value in pairs(container) do
		if type(slot) == "number" then
			report.enabledValuesVisited = report.enabledValuesVisited + 1
			if type(value) ~= "boolean" then
				local normalized
				if value == 1 or value == "1" or value == "ON" or value == "true" then
					normalized = true
				elseif value == 0 or value == "0" or value == "OFF" or value == "false" then
					normalized = false
				end
				if normalized == nil then
					report.enabledValuesQuarantined = report.enabledValuesQuarantined + 1
					RecordQuarantine(user,scope,slot,nil,value,"invalid_enabled_value")
					normalized = false
				else
					report.enabledValuesChanged = report.enabledValuesChanged + 1
				end
				container[slot] = normalized
			end
		end
	end
end

local function NormalizeQueueSlot(user,container,key,scope,slot,legacyItems,getBaseID,report)
	local queue = container[key]
	if type(queue) ~= "table" then
		report.queuesQuarantined = report.queuesQuarantined + 1
		RecordQuarantine(user,scope,slot,nil,queue,"invalid_queue")
		container[key] = {}
		return
	end
	NormalizeQueue(user,queue,scope,slot,legacyItems,getBaseID,report)
end

local function CaptureBackup(user,now)
	if type(user.QueueMigrationBackup) == "table" then return end
	if user.QueueMigrationBackup ~= nil then
		-- A damaged earlier backup must not prevent this migration from taking a
		-- usable recovery snapshot. Preserve the opaque value before replacing it.
		user.UnknownQueueMigrationBackup = DeepCopy(user.QueueMigrationBackup)
	end
	local backup = {
		fromVersion=user.QueueSchemaVersion,
		capturedAt=type(now) == "function" and now() or nil,
		global=DeepCopy(user.Queues),
		globalEnabled=DeepCopy(user.QueuesEnabled),
		sets={},
		setsEnabled={},
	}
	if type(user.Sets) == "table" then
		for setname,set in pairs(user.Sets) do
			if type(set) == "table" and set.Queues ~= nil then
				backup.sets[setname] = DeepCopy(set.Queues)
			end
			if type(set) == "table" and set.QueuesEnabled ~= nil then
				backup.setsEnabled[setname] = DeepCopy(set.QueuesEnabled)
			end
		end
	end
	user.QueueMigrationBackup = backup
end

function Migration.Migrate(user,legacyItems,getBaseID,now)
	assert(type(user) == "table","queue migration requires ItemRackUser")
	local priorVersion = tonumber(user.QueueSchemaVersion) or 0

	local report = {
		fromVersion=priorVersion,
		toVersion=Migration.SchemaVersion,
		queuesVisited=0,
		queuesCompacted=0,
		queuesQuarantined=0,
		boundariesInserted=0,
		slotKeysNormalized=0,
		slotKeysQuarantined=0,
		entriesVisited=0,
		entriesChanged=0,
		entriesQuarantined=0,
		enabledValuesVisited=0,
		enabledValuesChanged=0,
		enabledValuesQuarantined=0,
		legacySettingsAvailable=type(legacyItems) == "table" and next(legacyItems) ~= nil or false,
	}
	if priorVersion > Migration.SchemaVersion then
		report.skipped = "future_schema"
		user.QueueMigrationReport = report
		return report
	end
	if priorVersion < Migration.SchemaVersion then CaptureBackup(user,now) end

	if user.Queues == nil then
		user.Queues = {}
	elseif type(user.Queues) ~= "table" then
		report.queuesQuarantined = report.queuesQuarantined + 1
		RecordQuarantine(user,"global",nil,nil,user.Queues,"invalid_queue_root")
		user.Queues = {}
	end
	NormalizeSlotKeys(user,user.Queues,"global",report)
	for slot,queue in pairs(user.Queues) do
		if type(slot) == "number" then
			NormalizeQueueSlot(user,user.Queues,slot,"global",slot,
				legacyItems,getBaseID,report)
		end
	end
	if user.QueuesEnabled == nil then
		user.QueuesEnabled = {}
	elseif type(user.QueuesEnabled) ~= "table" then
		report.queuesQuarantined = report.queuesQuarantined + 1
		RecordQuarantine(user,"global_enabled",nil,nil,user.QueuesEnabled,"invalid_queue_root")
		user.QueuesEnabled = {}
	end
	NormalizeSlotKeys(user,user.QueuesEnabled,"global_enabled",report)
	NormalizeEnabledValues(user,user.QueuesEnabled,"global_enabled",report)

	if type(user.Sets) == "table" then
		for setname,set in pairs(user.Sets) do
			if type(set) == "table" and set.Queues ~= nil then
				if type(set.Queues) ~= "table" then
					report.queuesQuarantined = report.queuesQuarantined + 1
					RecordQuarantine(user,"set:"..tostring(setname),nil,nil,
						set.Queues,"invalid_queue_root")
					set.Queues = {}
				end
				NormalizeSlotKeys(user,set.Queues,"set:"..tostring(setname),report)
				for slot,queue in pairs(set.Queues) do
					if type(slot) == "number" then
						NormalizeQueueSlot(user,set.Queues,slot,
							"set:"..tostring(setname),slot,legacyItems,getBaseID,report)
					end
				end
			end
			if type(set) == "table" and set.QueuesEnabled ~= nil then
				if type(set.QueuesEnabled) ~= "table" then
					report.queuesQuarantined = report.queuesQuarantined + 1
					RecordQuarantine(user,"set_enabled:"..tostring(setname),nil,nil,
						set.QueuesEnabled,"invalid_queue_root")
					set.QueuesEnabled = {}
				end
				NormalizeSlotKeys(user,set.QueuesEnabled,
					"set_enabled:"..tostring(setname),report)
				NormalizeEnabledValues(user,set.QueuesEnabled,
					"set_enabled:"..tostring(setname),report)
			end
		end
	end

	user.QueueSchemaVersion = Migration.SchemaVersion
	user.QueueMigrationReport = report
	return report
end
