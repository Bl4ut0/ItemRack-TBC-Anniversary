-- ItemRackCooldownState.lua
--
-- One renderer-independent authority for item cooldown observations. Records
-- are keyed by exact stored identity and indexed by base item ID so a popup
-- opened later can consume a cooldown first observed on an equipped button.

ItemRack.CooldownState = ItemRack.CooldownState or {}
local CooldownState = ItemRack.CooldownState

local function Text(value)
	if value == nil or value == 0 then return nil end
	return tostring(value)
end

local function Remaining(record,now)
	return record and math.max(record.start + record.duration - now,0) or 0
end

local function IsCurrentGeneration(state,record)
	return record and record.generation == state.generation
end

local function ArenaConfirmationKeys(exactID,baseID)
	local exactKey = Text(exactID)
	local baseKey = Text(baseID)
	-- The game cooldown API is base-item scoped. When a base ID is known, all
	-- enchanted/rune/exact variants must share one arena phase or a tombstone
	-- left by one variant can incorrectly hide a new cooldown from another.
	if baseKey then return nil,"base:"..baseKey end
	return exactKey and ("exact:"..exactKey),nil
end

local function IsArenaIdentityConfirmed(state,exactID,baseID)
	if not state.arena then return false end
	local exactKey,baseKey = ArenaConfirmationKeys(exactID,baseID)
	return (exactKey and state.arena.confirmed[exactKey])
		or (baseKey and state.arena.confirmed[baseKey]) or false
end

local function ConfirmArenaIdentity(state,exactID,baseID)
	if not state.arena then return end
	local exactKey,baseKey = ArenaConfirmationKeys(exactID,baseID)
	if exactKey then state.arena.confirmed[exactKey] = true end
	if baseKey then state.arena.confirmed[baseKey] = true end
end

local function IsArenaIdentityReset(state,exactID,baseID)
	if not state.arena then return false end
	local exactKey,baseKey = ArenaConfirmationKeys(exactID,baseID)
	return (exactKey and state.arena.reset[exactKey])
		or (baseKey and state.arena.reset[baseKey]) or false
end

local function MarkArenaIdentityReset(state,exactID,baseID,value)
	if not state.arena then return end
	local exactKey,baseKey = ArenaConfirmationKeys(exactID,baseID)
	if exactKey then state.arena.reset[exactKey] = value or nil end
	if baseKey then state.arena.reset[baseKey] = value or nil end
end

local function RemoveRecord(state,key)
	local record = key and state.records[key]
	if not record then return end
	state.records[key] = nil
	local members = record.baseKey and state.byBase[record.baseKey]
	if members then
		members[key] = nil
		if not next(members) then state.byBase[record.baseKey] = nil end
	end
end

local function ClearIdentity(state,exactID,baseID)
	local exactKey = Text(exactID)
	local baseKey = Text(baseID)
	if exactKey then RemoveRecord(state,exactKey) end
	if baseKey and state.byBase[baseKey] then
		local keys = {}
		for key in pairs(state.byBase[baseKey]) do table.insert(keys,key) end
		for _,key in ipairs(keys) do RemoveRecord(state,key) end
	end
end

function CooldownState.New()
	return { schema=1, generation=0, records={}, byBase={} }
end

function CooldownState.IsState(value)
	return type(value) == "table" and value.schema == 1
		and type(value.records) == "table" and type(value.byBase) == "table"
end

function CooldownState.Reset(state)
	state.generation = (state.generation or 0) + 1
	state.records = {}
	state.byBase = {}
	state.arena = nil
	return state.generation
end

function CooldownState.BeginArena(state,now)
	state.generation = (state.generation or 0) + 1
	state.arena = {
		generation=state.generation, enteredAt=now, confirmed={}, reset={},
	}
	return state.generation
end

function CooldownState.EndArena(state)
	state.arena = nil
end

function CooldownState.Get(state,exactID,baseID,now)
	if not CooldownState.IsState(state) then return nil end
	local exactKey = Text(exactID)
	local baseKey = Text(baseID)
	local record = exactKey and state.records[exactKey]
	if record and IsCurrentGeneration(state,record) and Remaining(record,now) > 0.1 then
		return record
	end
	local newest
	for key in pairs(baseKey and state.byBase[baseKey] or {}) do
		local candidate = state.records[key]
		if candidate and IsCurrentGeneration(state,candidate) and Remaining(candidate,now) > 0.1
		and (not newest or candidate.observedAt > newest.observedAt) then
			newest = candidate
		end
	end
	return newest
end

function CooldownState.Observe(state,observation)
	if not CooldownState.IsState(state) or type(observation) ~= "table" then
		return { active=false, known=false, status="invalid_observation" }
	end
	local now = tonumber(observation.now) or 0
	local start = tonumber(observation.start)
	local duration = tonumber(observation.duration)
	local enable = tonumber(observation.enable)
	local exactKey = Text(observation.exactID)
	local baseKey = Text(observation.baseID)
	local active = enable == 1 and start and start > 0 and duration and duration > 1.5

	if active then
		if state.arena and start < state.arena.enteredAt - 0.1 then
			local current = CooldownState.Get(state,observation.exactID,
				observation.baseID,now)
			if current then
				return { active=true, known=true, start=current.start,
					duration=current.duration, enable=1,
					status="arena_stale_guarded", record=current }
			end
			return { active=false, known=false, start=0, duration=0, enable=1,
				status="arena_stale_sample", generation=state.arena.generation }
		end
		local key = exactKey or (baseKey and ("base:"..baseKey))
		if not key then
			return { active=false, known=false, status="missing_identity" }
		end
		ConfirmArenaIdentity(state,observation.exactID,observation.baseID)
		MarkArenaIdentityReset(state,observation.exactID,observation.baseID,false)
		RemoveRecord(state,key)
		local record = {
			key=key, exactKey=exactKey, baseKey=baseKey,
			start=start, duration=duration, enable=1,
			generation=state.generation, observedAt=now, source=observation.source,
		}
		state.records[key] = record
		if baseKey then
			state.byBase[baseKey] = state.byBase[baseKey] or {}
			state.byBase[baseKey][key] = true
		end
		return { active=true, known=true, start=start, duration=duration,
			enable=1, status="active", record=record }
	end

	if state.arena and IsArenaIdentityReset(state,
		observation.exactID,observation.baseID) then
		-- Reset is a durable fact for this generation, not a one-consumer event.
		-- Button/menu observation order therefore cannot make notifications infer
		-- a false ready transition. A genuine post-entry active sample clears it.
		return { active=false, known=true, start=0, duration=0,
			enable=enable or 1, status="arena_reset",
			generation=state.arena.generation }
	end

	if state.arena and not IsArenaIdentityConfirmed(state,
		observation.exactID,observation.baseID) then
		-- Arena entry is an explicit cooldown reset boundary. A zero/disabled
		-- first post-entry sample confirms reset for this identity; after that,
		-- false zero/disabled samples use the normal unexpired-record guard.
		-- A stale active pre-entry sample was rejected above and can never
		-- repopulate the current generation.
		ClearIdentity(state,observation.exactID,observation.baseID)
		ConfirmArenaIdentity(state,observation.exactID,observation.baseID)
		MarkArenaIdentityReset(state,observation.exactID,observation.baseID,true)
		return { active=false, known=true, start=0, duration=0,
			enable=enable or 1, status="arena_reset", generation=state.arena.generation }
	end

	local cached = CooldownState.Get(state,observation.exactID,observation.baseID,now)
	if cached then
		return { active=true, known=true, start=cached.start, duration=cached.duration,
			enable=1, status="guarded", record=cached }
	end
	ClearIdentity(state,observation.exactID,observation.baseID)
	return { active=false, known=start ~= nil and duration ~= nil,
		start=start or 0, duration=duration or 0, enable=enable,
		status=(start == nil or duration == nil) and "unknown" or "clear" }
end

function ItemRack.EnsureCooldownState()
	if not CooldownState.IsState(ItemRack.CooldownObservations) then
		ItemRack.CooldownObservations = CooldownState.New()
	end
	return ItemRack.CooldownObservations
end

function ItemRack.ObserveItemCooldown(exactID,baseID,start,duration,enable,source)
	return CooldownState.Observe(ItemRack.EnsureCooldownState(),{
		exactID=exactID, baseID=baseID, start=start, duration=duration,
		enable=enable, source=source, now=GetTime(),
	})
end

function ItemRack.GetObservedItemCooldown(exactID,baseID)
	return CooldownState.Get(ItemRack.EnsureCooldownState(),exactID,baseID,GetTime())
end
