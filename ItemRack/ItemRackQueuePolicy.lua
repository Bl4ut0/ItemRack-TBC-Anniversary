-- ItemRackQueuePolicy.lua
--
-- Pure, atomic queue-context resolution. A slot's owner, list, and enabled
-- state always come from one layer. An explicit equipment slot is a policy
-- boundary even when that set has no queue, preventing a lower event/global
-- queue from replacing gear owned by the higher layer.

ItemRack.QueuePolicy = ItemRack.QueuePolicy or {}
local QueuePolicy = ItemRack.QueuePolicy

local function HasBoundary(setData,slot)
	return setData and (
		(setData.Queues and setData.Queues[slot] ~= nil) or
		(setData.QueuesEnabled and setData.QueuesEnabled[slot] ~= nil) or
		(setData.equip and setData.equip[slot] ~= nil)
	)
end

local function FromSet(setName,setData,slot,reason)
	local list = setData.Queues and setData.Queues[slot]
	local enabled = setData.QueuesEnabled and setData.QueuesEnabled[slot]
	return {
		owner = setName,
		list = list,
		enabled = enabled,
		reason = reason,
	}
end

local function FromGlobal(user,slot,reason)
	local list = user.Queues and user.Queues[slot]
	local enabled = user.QueuesEnabled and user.QueuesEnabled[slot]
	return {
		owner = false,
		list = list,
		enabled = enabled,
		reason = reason,
	}
end

function QueuePolicy.Resolve(user,getEventSet,slot,explicitSetName)
	if type(user) ~= "table" or type(slot) ~= "number" then
		return { owner=false, reason="invalid_context" }
	end
	if user.EnablePerSetQueues ~= "ON" then
		return FromGlobal(user,slot,"per_set_disabled")
	end

	local targetSetName = explicitSetName or user.CurrentSet
	local targetSet = targetSetName and user.Sets and user.Sets[targetSetName]
	if explicitSetName then
		if targetSet then
			local context = FromSet(targetSetName,targetSet,slot,"explicit_set")
			if not HasBoundary(targetSet,slot) then context.owner = false end
			return context
		end
		return FromGlobal(user,slot,"missing_explicit_set")
	end

	if targetSet then
		if HasBoundary(targetSet,slot) then
			return FromSet(targetSetName,targetSet,slot,"current_set")
		end
		if user.EnableQueueContextCheck ~= "ON" then
			local context = FromSet(targetSetName,targetSet,slot,"context_inheritance_disabled")
			context.owner = false
			return context
		end
	elseif user.EnableQueueContextCheck ~= "ON" then
		return FromGlobal(user,slot,"no_current_set")
	end

	local seen = {}
	if targetSetName then seen[targetSetName] = true end
	local stack = user.EventStack
	for index=#(stack or {}),1,-1 do
		local eventName = stack[index]
		local eventSetName
		if getEventSet then eventSetName = getEventSet(eventName) end
		if not eventSetName and user.Events and user.Events.Set then
			eventSetName = user.Events.Set[eventName]
		end
		if eventSetName and not seen[eventSetName] then
			seen[eventSetName] = true
			local eventSet = user.Sets and user.Sets[eventSetName]
			if HasBoundary(eventSet,slot) then
				return FromSet(eventSetName,eventSet,slot,"event_stack")
			end
		end
	end

	return FromGlobal(user,slot,"global_fallback")
end
