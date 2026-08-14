-- Compatibility shim for LoadAddOn (moved to C_AddOns in TBC 2.5.5+)
local LoadAddOn = LoadAddOn or (C_AddOns and C_AddOns.LoadAddOn)

-- Compatibility shim for loadstring (renamed to load in Lua 5.2+)
local loadstring = loadstring or load
local _refreshMountState = 0

-- Compatibility shim for GetSpellInfo (deprecated in 11.0.0, changed in 1.15.0)
local GetSpellInfo = GetSpellInfo or function(spellID)
	if not spellID then return nil end
	local info = C_Spell and C_Spell.GetSpellInfo(spellID)
	if info then
		local subtext = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
		return info.name, subtext, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
	end
end

--[[ Default event definitions

	Events can be one of four types:
		Buff : Triggered by PLAYER_AURAS_CHANGED and delayed .3 sec
		Zone : Triggered by ZONE_CHANGED_NEW_AREA or ZONE_CHANGED_INDOORS and delayed .5 sec
		Stance : Triggered by UPDATE_SHAPESHIFT_FORM and not delayed
		Script : User-defined trigger

		Buff and Stance share an attribute :
		  NotInPVP : nil or 1, whether to ignore this event if pvp flag is set

		Buff, Zone and Stance share an attribute :
		  Unequip : nil or 1, whether to unequip the set when condition ends

		Buff has a special case attribute:
		  Anymount: nil or 1, whether the buff is any mount (IsPlayerMounted())

		Zone has a table:
		  Zones : Indexed by name of zone, lookup table for zones to define this event

		Script has its own attributes:
		  Trigger : Event (ie "UNIT_AURA") that triggers the script
		  Script : Actual script run through RunScript

	The set to equip is defined in ItemRackUser.Events.Set, indexed by event name
	The set to equip is nil if it's a Script event. Script events should use
	EquipEventSet()/UnequipEventSet() so they participate in the event stack.
	Whether an event is enabled is in ItemRackuser.Events.Enabled, indexed by event name
]]

-- increment this value when default events are changed to deploy them to existing events
ItemRack.EventsVersion = 20

ItemRack.LegacySwimmingScript = "local set = \"Name of set\"\nif IsSwimming() and not IsSetEquipped(set) then\n  EquipSet(set)\n  if not SwimmingEvent then\n    function SwimmingEvent()\n      if not IsSwimming() then\n        ItemRack.StopTimer(\"SwimmingEvent\")\n        UnequipSet(set)\n      end\n    end\n    ItemRack.CreateTimer(\"SwimmingEvent\",SwimmingEvent,.5,1)\n  end\n  ItemRack.StartTimer(\"SwimmingEvent\")\nend\n--[[Equips a set when swimming and breath gauge appears and unequips soon after you stop swimming.]]"
ItemRack.StackedSwimmingScript = "local set = \"Name of set\"\nif IsSwimming() and not IsSetEquipped(set) then\n  EquipEventSet(set)\n  if not SwimmingEvent then\n    function SwimmingEvent()\n      if not IsSwimming() then\n        ItemRack.StopTimer(\"SwimmingEvent\")\n        UnequipEventSet()\n      end\n    end\n    ItemRack.CreateTimer(\"SwimmingEvent\",SwimmingEvent,.5,1)\n  end\n  ItemRack.StartTimer(\"SwimmingEvent\")\nend\n--[[Equips a set when swimming and breath gauge appears and unequips soon after you stop swimming.]]"

-- default events, loaded when no events exist or ItemRack.EventsVersion is increased
ItemRack.DefaultEvents = {
	["PVP"] = {
		Type = "Zone",
		Unequip = 1,
		Zones = {
			["Alterac Valley"] = 1,
			["Arathi Basin"] = 1,
			["Warsong Gulch"] = 1,
			["Eye of the Storm"] = 1,
			["Ruins of Lordaeron"] = 1,
			["Blade's Edge Arena"] = 1,
			["Nagrand Arena"] = 1,
		}
	},
	["City"] = {
		Type = "Zone",
		Unequip = 1,
		Zones = {
			["Ironforge"] = 1,
			["Stormwind City"] = 1,
			["Darnassus"] = 1,
			["The Exodar"] = 1,
			["Orgrimmar"] = 1,
			["Thunder Bluff"] = 1,
			["Silvermoon City"] = 1,
			["Undercity"] = 1,
			["Shattrath City"] = 1,
			["Dalaran"] = 1,
		}
	},
	["Mounted"] = { Type = "Buff", Unequip = 1, Anymount = 1 },
	["Drinking"] = { Type = "Buff", Unequip = 1, Buff = "Drink" },

	["Evocation"] = { Class = "MAGE", Type = "Buff", Unequip = 1, Buff = "Evocation" },

	["Warrior Battle"] = { Class = "WARRIOR", Type = "Stance", Stance = 1 },
	["Warrior Defensive"] = { Class = "WARRIOR", Type = "Stance", Stance = 2 },
	["Warrior Berserker"] = { Class = "WARRIOR", Type = "Stance", Stance = 3 },

	["Priest Shadowform"] = { Class = "PRIEST", Type = "Stance", Unequip = 1, Stance = 1 },

	["Druid Humanoid"] = { Class = "DRUID", Type = "Stance", Stance = 0 },
	["Druid Bear"] = { Class = "DRUID", Type = "Stance", Stance = 1 },
	["Druid Aquatic"] = { Class = "DRUID", Type = "Stance", Stance = 2 },
	["Druid Cat"] = { Class = "DRUID", Type = "Stance", Stance = 3 },
	["Druid Travel"] = { Class = "DRUID", Type = "Stance", Stance = 4 },
	["Druid Moonkin"] = { Class = "DRUID", Type = "Stance", Stance = "Moonkin Form" },
	["Druid Tree of Life"] = { Class = "DRUID", Type = "Stance", Stance = "Tree of Life" },

	["Rogue Stealth"] = { Class = "ROGUE", Type = "Stance", Unequip = 1, Stance = 1 },

	["Shaman Ghostwolf"] = { Class = "SHAMAN", Type = "Stance", Unequip = 1, Stance = 1 },
	["Primary Spec"] = { Type = "Specialization", Spec = 1, Unequip = 1 },
	["Secondary Spec"] = { Type = "Specialization", Spec = 2, Unequip = 1 },

	["Swimming"] = {
		["Trigger"] = "MIRROR_TIMER_START",
		["Type"] = "Script",
		["Script"] = ItemRack.StackedSwimmingScript,
	},

	["Buffs Gained"] = {
		Type = "Script",
		Trigger = "UNIT_AURA",
		Script = "if arg1==\"player\" then\n  IRScriptBuffs = IRScriptBuffs or {}\n  local buffs = IRScriptBuffs\n  for i in pairs(buffs) do\n    if not AuraUtil.FindAuraByName(i,\"player\") then\n      buffs[i] = nil\n    end\n  end\n  local i,b = 1,1\n  while b do\n    b = AuraUtil.FindAuraByName(i,\"player\")\n    if b and not buffs[b] then\n      ItemRack.Print(\"Gained buff: \"..b)\n      buffs[b] = 1\n    end\n    i = i+1\n  end\nend\n--[[For script demonstration purposes. Doesn't equip anything just informs when a buff is gained.]]",
	},

	["After Cast"] = {
		Type = "Script",
		Trigger = "UNIT_SPELLCAST_SUCCEEDED",
		Script = "local spell = \"Name of spell\"\nlocal set = \"Name of set\"\nif arg1==\"player\" and arg2==spell then\n  EquipSet(set)\nend\n\n--[[This event will equip \"Name of set\" when \"Name of spell\" has finished casting.  Change the names for your own use.]]",
	},

	["Nefarian's Lair"] = {
		Type = "Zone",
		Unequip = 1,
		Zones = {
			["Nefarian's Lair"] = 1,
		}
	},
}

-- resetDefault to reload/update default events, resetAll to wipe all events and recreate them
function ItemRack.LoadEvents(resetDefault,resetAll)

	local _, playerClass = UnitClass("player")
	local version = tonumber(ItemRackSettings.EventsVersion) or 0

	if ItemRack.EventsVersion > version then
		resetDefault = 1 -- force a load of default events (leaving custom ones intact)
		ItemRackSettings.EventsVersion = ItemRack.EventsVersion
	end

	if not ItemRackUser.Events or resetAll then
		ItemRackUser.Events = {
			Enabled = {}, -- indexed by name of event, whether an event is enabled
			Set = {} -- indexed by name of event, the set defined for the event, if any
		}
	end

	if not ItemRackEvents or resetAll then
		ItemRackEvents = {}
	end

	if resetDefault or resetAll then
		for i in pairs(ItemRack.DefaultEvents) do
			local eventClass = ItemRack.DefaultEvents[i].Class

			if not eventClass or eventClass == playerClass then
				ItemRack.CopyDefaultEvent(i)
			end
		end
	end

	ItemRack.CleanupEvents()
	if ItemRackOpt then
		ItemRackOpt.PopulateEventList() -- if options loaded, recreate event list there
	end
end

function ItemRack.CopyDefaultEvent(eventName)
	ItemRackEvents[eventName] = {}
	local event = ItemRackEvents[eventName]
	local default = ItemRack.DefaultEvents[eventName]

	for i in pairs(default) do
		if type(default[i])~="table" then
			event[i] = default[i]
		else
			-- recursive scares me :P /chicken
			-- this copies a sub-table. if events ever go one more table deep, do a recursive copy
			event[i] = {}
			for j in pairs(default[i]) do
				event[i][j] = default[i][j]
			end
		end
	end
end

-- clear sets of deleted events, clear events with deleted sets
function ItemRack.CleanupEvents()
	local event = ItemRackUser.Events

	-- go through ItemRackUser.Events.Set for deleted events or sets
	for i in pairs(event.Set) do
		if not ItemRackEvents[i] then
			-- this event no longer exists, remove it
			event.Set[i] = nil
			event.Enabled[i] = nil
		end
		if not ItemRackUser.Sets[event.Set[i]] then
			-- this set no longer exists, remove it
			event.Set[i] = nil
			event.Enabled[i] = nil
		end
	end

	-- go through ItemRackUser.Events.Enabled for deleted events
	for i in pairs(event.Enabled) do
		if not ItemRackEvents[i] then
			-- this event no longer exists, remove it
			event.Set[i] = nil
			event.Enabled[i] = nil
		end
		if event.Enabled[i] == false then
			-- this was disabled but not removed
			event.Enabled[i] = nil
		end
	end
end

function ItemRack.MigrateDefaultScriptEvents()
	local swimming = ItemRackEvents and ItemRackEvents["Swimming"]
	if swimming and swimming.Trigger == "MIRROR_TIMER_START" and swimming.Script then
		if swimming.Script == ItemRack.LegacySwimmingScript then
			swimming.Script = ItemRack.StackedSwimmingScript
			return
		end
		local updated = swimming.Script
		updated = string.gsub(updated, "\n  EquipSet%(set%)\n", "\n  EquipEventSet(set)\n", 1)
		updated = string.gsub(updated, "\n        UnequipSet%(set%)\n", "\n        UnequipEventSet()\n", 1)
		if updated ~= swimming.Script then
			swimming.Script = updated
		end
	end
end

function ItemRack.ResetEvents(resetDefault,resetAll)
	if not resetDefault and not resetAll then
		StaticPopupDialogs["ItemRackConfirmResetEvents"] = {
			text = "Do you want to restore just Default events, or wipe All events and restore to default?",
			button1 = "Default", button2 = "Cancel", button3 = "All", timeout = 0, hideOnEscape = 1, whileDead = 1,
			OnAccept = function() ItemRack.ResetEvents(1) end,
			OnAlt = function() ItemRack.ResetEvents(1,1) end,
		}
		StaticPopup_Show("ItemRackConfirmResetEvents")
	else
		ItemRack.LoadEvents(resetDefault,resetAll)
	end
end

function ItemRack.InitEvents()
	ItemRack.LoadEvents()
	ItemRack.MigrateDefaultScriptEvents()

	ItemRack.CreateTimer("EventsBuffTimer",ItemRack.ProcessBuffEvent,.15)
	ItemRack.CreateTimer("EventsZoneTimer",ItemRack.ProcessZoneEvent,.16)
	ItemRack.CreateTimer("CheckForMountedEvents",ItemRack.CheckForMountedEvents,.5,1)
	ItemRack.CreateTimer("SpecChangeTimer",ItemRack.ProcessSpecializationEvent,0.5,1)
	ItemRack.CreateTimer("MovementPollingTimer",ItemRack.PollMovement,.2,1)
	ItemRack.CreateTimer("OnMovementUnequipTimer",ItemRack.ProcessOnMovementUnequip,.5)
	
	-- Initialize Event Stack and BaseGear set if missing
	if not ItemRackUser.EventStack then
		ItemRackUser.EventStack = {}
	end
	ItemRack.ScriptEventSets = {}
	ItemRack.ScriptEventDisableSound = {}
	if not ItemRackUser.Sets["~BaseGear"] then
		ItemRackUser.Sets["~BaseGear"] = {
			equip = {},
			old = {}
		}
	end

	-- ======================================================================
	-- CLEANUP: Clear stale runtime state from SavedVariables
	-- ItemRackEvents is a SavedVariable, so .Active, .LastZoneMatched,
	-- .ManualOverride persist across sessions and must be wiped on init.
	-- ======================================================================
	for eventName, eventData in pairs(ItemRackEvents) do
		eventData.Active = nil
		eventData.LastZoneMatched = nil
		eventData.ManualOverride = nil
		eventData.LastZoneSignature = nil
	end

	-- ======================================================================
	-- CLEANUP: Purge the EventStack.
	-- Events with Unequip=false never pop, so the stack accumulates entries
	-- across sessions. On a fresh login, the stack should always be empty;
	-- events will push onto it naturally as zone/buff/stance conditions match.
	-- ======================================================================
	for i = #ItemRackUser.EventStack, 1, -1 do
		table.remove(ItemRackUser.EventStack, i)
	end

	-- ======================================================================
	-- CLEANUP: Wipe ALL stale old/oldset data on every set.
	-- The .old table stores which items were displaced when the set was
	-- equipped, and .oldset stores which set was active before. This data
	-- is only valid during a single session — on login/reload, no set
	-- should have restoration data. It will be correctly re-populated
	-- when PushEvent/EquipSet actually fires during gameplay.
	-- This prevents ghost set restores, self-referential loops
	-- (Arena.oldset = "Arena"), and stale circular chains
	-- (9% -> 6% 1H -> 6% 2H -> 9%).
	-- ======================================================================
	-- CLEANUP: Clean up self-referential loops or invalid oldset entries on login/reload.
	-- We preserve the rest of .old and .oldset so that events active across reload/login
	-- (e.g. Mounted, Stance, Zone) can correctly restore gear upon dismounting or shifting.
	for setname, setData in pairs(ItemRackUser.Sets) do
		if setData.oldset == setname or (setData.oldset and not ItemRackUser.Sets[setData.oldset]) then
			setData.oldset = nil
		end
	end

	-- Prime all events to prevent redundant swaps on login/reload
	-- Only check enabled events to avoid false-positives on disabled events
	local enabled = ItemRackUser.Events.Enabled
	local getSpec = GetActiveTalentGroup or (C_Talent and C_Talent.GetActiveTalentGroup)
	local currentSpec = getSpec and getSpec()
	local currentStance = GetShapeshiftForm()
	local curZone = GetRealZoneText()
	local curSubZone = GetSubZoneText()
	local isMounted = IsMounted() and not UnitOnTaxi("player")
	local _, instanceType = IsInInstance()

	ItemRack.LastLastSpec = (currentSpec and currentSpec > 0) and currentSpec or nil

	for eventName in pairs(enabled) do
		local eventData = ItemRackEvents[eventName]
		if eventData then
			local shouldBeActive = false
			if eventData.Type == "Specialization" and currentSpec and eventData.Spec == currentSpec then
				shouldBeActive = true
			elseif eventData.Type == "Stance" and ItemRack.GetStanceNumber(eventData.Stance) == currentStance then
				shouldBeActive = true
			elseif eventData.Type == "Zone" and eventData.Zones and (eventData.Zones[curZone] or eventData.Zones[curSubZone] or eventData.Zones[instanceType] or eventData.Zones[instanceType:gsub("^%l", string.upper)]) then
				shouldBeActive = true
			elseif eventData.Type == "Buff" then
				if eventData.Anymount then
					if isMounted then
						if eventData.OnMovement then
							if GetUnitSpeed("player") > 0 then
								shouldBeActive = true
							end
						else
							shouldBeActive = true
						end
					end
				elseif eventData.Buff and AuraUtil.FindAuraByName(eventData.Buff, "player") then
					if eventData.OnMovement then
						if GetUnitSpeed("player") > 0 then
							shouldBeActive = true
						end
					else
						shouldBeActive = true
					end
				end
			end
			
			if shouldBeActive then
				local setname = ItemRackUser.Events.Set[eventName]
				if setname and ItemRack.IsSetEquipped(setname) then
					eventData.Active = true
					-- Re-populate EventStack with active event on startup
					local alreadyStacked = false
					for _, name in ipairs(ItemRackUser.EventStack) do
						if name == eventName then
							alreadyStacked = true
							break
						end
					end
					if not alreadyStacked then
						table.insert(ItemRackUser.EventStack, eventName)
					end
				end
			end
		end
	end

	if ItemRackButton20Queue then
		ItemRackButton20Queue:SetTexture("Interface\\AddOns\\ItemRack\\ItemRackGear")
	else
		-- print("ItemRackButton20Queue doesn't exist?")
	end

	ItemRack.RegisterEvents()
end

function ItemRack.RegisterEvents()
	local frame = ItemRackEventProcessingFrame
	if not frame then return end
	frame:UnregisterAllEvents()
	ItemRack.StopTimer("CheckForMountedEvents")
	ItemRack.ReflectEventsRunning()
	if ItemRackUser.EnableEvents=="OFF" then
		return
	end
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents
	
	local enabledCount = 0
	for _ in pairs(enabled) do enabledCount = enabledCount + 1 end
	local eventType
	for eventName in pairs(enabled) do
		local eventData = events[eventName]
		if eventData then
			eventType = eventData.Type
			if eventType=="Buff" then
				if not frame:IsEventRegistered("UNIT_AURA") then
					frame:RegisterEvent("UNIT_AURA")
				end
				if eventData.OnMovement then
					if not frame:IsEventRegistered("PLAYER_STARTED_MOVING") then
						frame:RegisterEvent("PLAYER_STARTED_MOVING")
						frame:RegisterEvent("PLAYER_STOPPED_MOVING")
					end
				end
			elseif eventType=="Stance" then
				if not frame:IsEventRegistered("UPDATE_SHAPESHIFT_FORM") then
					frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
				end
			elseif eventType=="Zone" then
				if not frame:IsEventRegistered("ZONE_CHANGED_NEW_AREA") then
					frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
				end
				if not frame:IsEventRegistered("ZONE_CHANGED_INDOORS") then
					frame:RegisterEvent("ZONE_CHANGED_INDOORS")
				end
			elseif eventType=="Specialization" then
				if not frame:IsEventRegistered("ACTIVE_TALENT_GROUP_CHANGED") then
					frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
				end
				if not frame:IsEventRegistered("PLAYER_TALENT_UPDATE") then
					frame:RegisterEvent("PLAYER_TALENT_UPDATE")
				end
			elseif eventType=="Script" then
				if not frame:IsEventRegistered(eventData.Trigger) then
					frame:RegisterEvent(eventData.Trigger)
				end
			end
		else
			ItemRack.Debug("Events", "Enabled event missing from ItemRackEvents:", eventName)
		end
	end
	ItemRack.StartTimer("CheckForMountedEvents")

	ItemRack.ProcessStanceEvent()
	ItemRack.ProcessZoneEvent()
	ItemRack.ProcessBuffEvent()
	ItemRack.ProcessSpecializationEvent()
end

function ItemRack.SpinDownEvent(eventName)
	if not eventName then return end
	local eventData = ItemRackEvents and ItemRackEvents[eventName]
	local wasActive = eventData and eventData.Active
	
	ItemRack.Debug("Events", "SpinDownEvent requested for:", eventName)
	
	if eventData then
		eventData.Active = nil
		eventData.LastZoneMatched = nil
		eventData.LastZoneSignature = nil
		eventData.ManualOverride = nil
	end

	local onStack = false
	if ItemRackUser and ItemRackUser.EventStack then
		for i = #ItemRackUser.EventStack, 1, -1 do
			if ItemRackUser.EventStack[i] == eventName then
				onStack = true
				break
			end
		end
	end

	if onStack then
		if eventData and eventData.Unequip then
			ItemRack.PopEvent(eventName)
		else
			local stack = ItemRackUser.EventStack
			if stack then
				for i = #stack, 1, -1 do
					if stack[i] == eventName then
						table.remove(stack, i)
					end
				end
			end
			ItemRack.ClearScriptEventState(eventName)
		end
	elseif wasActive and eventData and eventData.Unequip then
		local setname = ItemRack.GetEventSet(eventName)
		if setname and ItemRackUser.CurrentSet ~= setname and ItemRack.IsSetEquipped(setname) then
			ItemRack.UnequipSet(setname)
		end
	end

	if ItemRack.PendingOnMovementUnequip == eventName then
		ItemRack.PendingOnMovementUnequip = nil
		ItemRack.StopTimer("OnMovementUnequipTimer")
	end

	ItemRack.ScheduleEventRecheck("Event disabled: " .. eventName, 0.1)
end

function ItemRack.SpinUpEvent(eventName)
	if not eventName then return end
	ItemRack.Debug("Events", "SpinUpEvent requested for:", eventName)
	if ItemRackUser.EnableEvents ~= "ON" then return end
	local eventData = ItemRackEvents and ItemRackEvents[eventName]
	ItemRack.RunAllEvents("Event enabled: " .. eventName, eventData and eventData.Type == "Specialization")
end

function ItemRack.SpinDownAllEvents()
	ItemRack.Debug("Events", "SpinDownAllEvents requested")
	local stack = ItemRackUser.EventStack
	if stack then
		for i = #stack, 1, -1 do
			local eventName = stack[i]
			local eventData = ItemRackEvents and ItemRackEvents[eventName]
			if eventData then
				eventData.Active = nil
				eventData.LastZoneMatched = nil
				eventData.LastZoneSignature = nil
				eventData.ManualOverride = nil
				if eventData.Unequip then
					ItemRack.PopEvent(eventName)
				else
					for k = #stack, 1, -1 do
						if stack[k] == eventName then
							table.remove(stack, k)
						end
					end
					ItemRack.ClearScriptEventState(eventName)
				end
			end
		end
	end
	if ItemRackEvents then
		for eventName, eventData in pairs(ItemRackEvents) do
			if eventData.Active then
				eventData.Active = nil
				eventData.LastZoneMatched = nil
				eventData.LastZoneSignature = nil
				eventData.ManualOverride = nil
				if eventData.Unequip then
					local setname = ItemRack.GetEventSet(eventName)
					if setname and ItemRack.IsSetEquipped(setname) then
						ItemRack.UnequipSet(setname)
					end
				end
			end
		end
	end
end

function ItemRack.ToggleEvents(self)
	ItemRackUser.EnableEvents = ItemRackUser.EnableEvents=="ON" and "OFF" or "ON"
	if ItemRackUser.EnableEvents == "OFF" then
		ItemRack.SpinDownAllEvents()
	else
		ItemRack.RunAllEvents("Global events enabled", true)
	end
	if not next(ItemRackUser.Events.Enabled) then
		-- user is turning on events with no events enabled, go to events frame
		LoadAddOn("ItemRackOptions")
		ItemRackOptFrame:Show()
		ItemRackOpt.TabOnClick(self,3)
	else
		if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
			ItemRackOpt.ListScrollFrameUpdate()
		end
	end
	ItemRack.RegisterEvents()
end

--[[ Event Stack Architecture ]]

function ItemRack.GetEventSet(eventName)
	if ItemRack.ScriptEventSets and ItemRack.ScriptEventSets[eventName] then
		return ItemRack.ScriptEventSets[eventName]
	end
	return ItemRackUser.Events.Set[eventName]
end

function ItemRack.GetEventDisableSound(eventName)
	if ItemRack.ScriptEventDisableSound and ItemRack.ScriptEventDisableSound[eventName] ~= nil then
		return ItemRack.ScriptEventDisableSound[eventName]
	end
	return ItemRackEvents[eventName] and ItemRackEvents[eventName].DisableSound
end

function ItemRack.ClearScriptEventState(eventName)
	if ItemRack.ScriptEventSets then
		ItemRack.ScriptEventSets[eventName] = nil
	end
	if ItemRack.ScriptEventDisableSound then
		ItemRack.ScriptEventDisableSound[eventName] = nil
	end
end

function ItemRack.ScriptEventEquip(eventName, setname, disableSound)
	if not eventName then
		return
	end
	if not setname or not ItemRackUser.Sets[setname] then
		ItemRack.Print("Set \""..tostring(setname).."\" doesn't exist.")
		return
	end
	ItemRack.ScriptEventSets = ItemRack.ScriptEventSets or {}
	ItemRack.ScriptEventDisableSound = ItemRack.ScriptEventDisableSound or {}
	local priorSet = ItemRack.ScriptEventSets[eventName]
	local wasActive = false
	if ItemRackUser.EventStack then
		for _, activeEvent in ipairs(ItemRackUser.EventStack) do
			if activeEvent == eventName then
				wasActive = true
				break
			end
		end
	end
	if priorSet and priorSet ~= setname and wasActive then
		ItemRack.PopEvent(eventName)
	end
	ItemRack.ScriptEventSets[eventName] = setname
	ItemRack.ScriptEventDisableSound[eventName] = disableSound
	ItemRack.PushEvent(eventName)
end

function ItemRack.ScriptEventUnequip(eventName, disableSound)
	if not eventName then
		return
	end
	ItemRack.ScriptEventDisableSound = ItemRack.ScriptEventDisableSound or {}
	if disableSound ~= nil then
		ItemRack.ScriptEventDisableSound[eventName] = disableSound
	end
	ItemRack.PopEvent(eventName)
end

function ItemRack.PushEvent(eventName)
	if ItemRackUser.EnableEvents == "OFF" then return end
	ItemRack.Debug("Events", "PushEvent: "..(eventName or "nil"))
	
	-- Remove event if it's already in the stack
	for i = #ItemRackUser.EventStack, 1, -1 do
		if ItemRackUser.EventStack[i] == eventName then
			table.remove(ItemRackUser.EventStack, i)
		end
	end
	
	table.insert(ItemRackUser.EventStack, eventName)
	
	local setname = ItemRack.GetEventSet(eventName)
	if setname then
		local disableSound = ItemRack.GetEventDisableSound(eventName)
		ItemRack.IsEventEquipment = true
		ItemRack.EquipSet(setname, disableSound)
		ItemRack.IsEventEquipment = nil
	end
end

function ItemRack.PopEvent(eventName)
	local poppedSet = ItemRack.GetEventSet(eventName)
	local disableSound = ItemRack.GetEventDisableSound(eventName)
	ItemRack.Debug("Events", "PopEvent: "..(eventName or "nil").." (poppedSet: "..(poppedSet or "nil")..")")

	-- Remove the event from the stack
	for i = #ItemRackUser.EventStack, 1, -1 do
		if ItemRackUser.EventStack[i] == eventName then
			table.remove(ItemRackUser.EventStack, i)
		end
	end
	
	-- Check if any active Zone event has ManualOverride.
	-- If so, and this isn't the zone event itself popping, suppress the restore
	-- IF AND ONLY IF the event popping is buried beneath the user's manual gear choice.
	-- If the event is the Active CurrentSet (e.g. Mount), it must be allowed to unequip natively.
	local suppressRestore = false
	ItemRack.Debug("Events", "PopEvent evaluating suppressRestore. CurrentSet is:", ItemRackUser.CurrentSet)
	if poppedSet and ItemRackUser.CurrentSet ~= poppedSet and ItemRackEvents[eventName] and ItemRackEvents[eventName].Type ~= "Zone" then
		
		ItemRack.Debug("Events", "PopEvent: CurrentSet ~= poppedSet. Checking if pending...")

		-- Check if the set is still actively swapping or waiting to swap.
		-- If so, CurrentSet hasn't updated yet, so do NOT suppress the unequip.
		local isPending = (ItemRack.SetSwapping == poppedSet)
		if not isPending and ItemRack.SetsWaiting then
			for _, q in ipairs(ItemRack.SetsWaiting) do
				if q[1] == poppedSet then
					isPending = true
					break
				end
			end
		end

		if not isPending then
			ItemRack.Debug("Events", "PopEvent: Not pending. Checking Zone Overrides for suppressRestore")
			local enabled = ItemRackUser.Events.Enabled
			for en in pairs(enabled) do
				if ItemRackEvents[en] and ItemRackEvents[en].Type == "Zone" and ItemRackEvents[en].ManualOverride and ItemRackEvents[en].Active then
					suppressRestore = true
					ItemRack.Debug("Events", "PopEvent: suppressing restore for "..(eventName or "nil").." - zone ManualOverride active for "..(en or "nil").." to protect manual gear context")
					break
				end
			end
		else
			ItemRack.Debug("Events", "PopEvent: isPending = true. Skipping suppression.")
		end
	end
	
	-- Unequip the set that we pushed, so it restores its exact swaps
	if poppedSet and not suppressRestore then
		ItemRack.Debug("Events", "PopEvent: Calling UnequipSet for:", poppedSet)
		ItemRack.IsEventEquipment = true
		ItemRack.UnequipSet(poppedSet, disableSound)
		ItemRack.IsEventEquipment = nil
	elseif suppressRestore then
		ItemRack.Debug("Events", "PopEvent: UnequipSet SUPPRESSED for:", poppedSet)
	end
	ItemRack.ClearScriptEventState(eventName)
end

--[[ Event processing ]]

function ItemRack.ProcessingFrameOnEvent(self,event,...)
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		ItemRack.Debug("Events", "Event processing deferred while automatic swaps are suspended:", event)
		return
	end
	local getSlots = C_Container and C_Container.GetContainerNumSlots or _G.GetContainerNumSlots
	local numSlots = getSlots and getSlots(0)
	if not numSlots or numSlots == 0 then
		return
	end

	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents
	local startBuff, startZone, startStance, eventType
	local arg1, arg2 = ...;

	if event == "UNIT_AURA" and arg1 == "player" then
		ItemRack.StartTimer("EventsBuffTimer")
	elseif event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
		ItemRack.StartTimer("EventsBuffTimer")
		if event == "PLAYER_STOPPED_MOVING" and GetUnitSpeed("player") > 0 then
			ItemRack.StartTimer("MovementPollingTimer")
		end
	end

	for eventName in pairs(enabled) do
		local eventData = events[eventName]
		if eventData then
			eventType = eventData.Type
			if event=="UNIT_AURA" and eventType=="Buff" and arg1=="player" then
				startBuff = 1
			elseif event=="UPDATE_SHAPESHIFT_FORM" and eventType=="Stance" then
				startStance = 1
			elseif event=="ZONE_CHANGED_NEW_AREA" and eventType=="Zone" then -- if player move to a new area, toggle set change.
				startZone = 1
				ItemRack.LastZoneChangeTime = GetTime() -- Track zone transitions for OnMovement suppression
			elseif event == "ZONE_CHANGED_INDOORS" and eventType == "Zone" and select(2, IsInInstance()) == "raid" then -- if player change subzone in raid instance, toggle set change, else not.
				startZone = 1
				ItemRack.LastZoneChangeTime = GetTime()
			elseif event == "ACTIVE_TALENT_GROUP_CHANGED" and eventType == "Specialization" then
				ItemRack.StartTimer("SpecChangeTimer")
			elseif eventType=="Script" and eventData.Trigger==event then
				local a1,a2,a3,a4,a5,a6,a7,a8,a9,a10 = ...
				-- Compatibility for UNIT_SPELLCAST_* changes in 1.15.0+ / 10.0+
				-- If arg2 is a castGUID (starts with "Cast-") and arg3 is a spellID, resolve name to arg2
				if event:match("^UNIT_SPELLCAST_") and type(a2)=="string" and a2:match("^Cast%-") then
					local spellID = a3
					if spellID then
						local name, subtext = GetSpellInfo(spellID)
						if name then
							if subtext and subtext ~= "" then
								a2 = name .. "(" .. subtext .. ")"
							else
								a2 = name
							end
						end
					end
				end
				-- Compatibility for COMBAT_LOG_EVENT_UNFILTERED changes in 8.0+ / 1.13+
				if event == "COMBAT_LOG_EVENT_UNFILTERED" then
					a1,a2,a3,a4,a5,a6,a7,a8,a9,a10 = CombatLogGetCurrentEventInfo()
				end
				local method, compileErr = loadstring("local event,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,arg10 = ...;local EquipEventSet = function(setname, disableSound) return ItemRack.ScriptEventEquip(event, setname, disableSound) end;local UnequipEventSet = function(disableSound) return ItemRack.ScriptEventUnequip(event, disableSound) end;local EquipSet = function(setname, disableSound) return EquipEventSet(setname, disableSound) end;local UnequipSet = function(setname, disableSound) local activeSet = ItemRack.GetEventSet(event) if setname and (not activeSet or setname ~= activeSet) then return ItemRack.UnequipSet(setname, disableSound) end return UnequipEventSet(disableSound) end;" .. eventData.Script)
				if not method then
					ItemRack.Debug("Events", "Error compiling script for event '" .. tostring(eventName) .. "': " .. tostring(compileErr))
				else
					local ok, runErr = pcall(method,event,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
					if not ok then
						ItemRack.Debug("Events", "Error running script for event '" .. tostring(eventName) .. "': " .. tostring(runErr))
					end
				end
			end
		end
	end
	if startStance then
		ItemRack.ProcessStanceEvent()
	end
	if startBuff then
		ItemRack.StartTimer("EventsBuffTimer")
	end
	if startZone then
		ItemRack.StartTimer("EventsZoneTimer")
	end
end

--[[ Event processing ]]

local druidStanceNames = {
	[1] = { "Bear Form", "Dire Bear Form" },
	[2] = { "Aquatic Form" },
	[3] = { "Cat Form" },
	[4] = { "Travel Form" },
}

function ItemRack.GetStanceNumber(name)
	local numForms = GetNumShapeshiftForms()
	if not numForms or numForms == 0 then return end

	-- Check exact form name match against current stance bar
	for i = 1, numForms do
		local _, formName = GetShapeshiftFormInfo(i)
		if name == formName then
			return i
		end
	end

	-- Fallback for numeric stance IDs (e.g. default Druid stance events with Stance = 1, 2, 3, 4)
	local stanceNum = tonumber(name)
	if stanceNum then
		local _, playerClass = UnitClass("player")
		if playerClass == "DRUID" and druidStanceNames[stanceNum] then
			for i = 1, numForms do
				local _, formName = GetShapeshiftFormInfo(i)
				for _, targetName in ipairs(druidStanceNames[stanceNum]) do
					if formName == targetName then
						return i
					end
				end
			end
		end
		return stanceNum
	end
end

function ItemRack.ProcessStanceEvent()
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		return
	end
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents

	local currentStance = GetShapeshiftForm()
	local stance, eventToEquip, eventToUnequip, setname

	for eventName in pairs(enabled) do
		local eventData = events[eventName]
		if eventData and eventData.Type=="Stance" then
			local excluded = false
			if eventData.NotInPVP then
				local _,instanceType = IsInInstance()
				if instanceType=="arena" or instanceType=="pvp" then
					excluded = true
				end
			end
			
			if excluded then
				if eventData.Active then
					if eventData.Unequip then
						eventToUnequip = eventName
					end
					eventData.Active = nil
				end
			else
				stance = ItemRack.GetStanceNumber(eventData.Stance)
				setname = ItemRackUser.Events.Set[eventName]
				
				-- Use .Active to track stance state, ensuring cleaner transitions
				if stance==currentStance then
					if not eventData.Active then
						if not ItemRack.IsSetEquipped(setname) then
							eventToEquip = eventName
							eventData.Active = true
						else
							eventData.Active = true
						end
					end
				elseif stance~=currentStance then
					if eventData.Active then
						if eventData.Unequip then
							eventToUnequip = eventName
						end
						eventData.Active = nil
					elseif eventData.Unequip and ItemRack.IsSetEquipped(setname) then
						-- Fallback for consistency: only trigger if the user didn't manually equip this set
						if ItemRackUser.CurrentSet ~= setname then
							eventToUnequip = eventName
						end
					end
				end
			end
		end
	end
	if eventToUnequip then
		ItemRack.PopEvent(eventToUnequip)
	end
	if eventToEquip then
		ItemRack.PushEvent(eventToEquip)
	end
end

local mountZoneRecheckPending
local mountZoneRebasePending

local function scheduleMountZoneRecheck(reason)
	if mountZoneRecheckPending then
		return
	end
	mountZoneRecheckPending = true
	C_Timer.After(0.5, function()
		mountZoneRecheckPending = nil
		if ItemRack.RunAllEvents then
			ItemRack.RunAllEvents(reason or "mount/zone transition retry")
		end
	end)
end

local function removeEventFromStack(eventName)
	local stack = ItemRackUser.EventStack
	if not stack then return end
	for i = #stack, 1, -1 do
		if stack[i] == eventName then
			table.remove(stack, i)
		end
	end
end

local function getActiveMountEvents()
	local activeMountEvents = {}
	local stack = ItemRackUser.EventStack
	if not stack then return activeMountEvents end
	for i = #stack, 1, -1 do
		local eventName = stack[i]
		local eventData = ItemRackEvents[eventName]
		if eventData and eventData.Anymount and eventData.Active then
			table.insert(activeMountEvents, eventName)
		end
	end
	return activeMountEvents
end

local function hasNonRestoringMountLayer(activeMountEvents)
	for _, eventName in ipairs(activeMountEvents) do
		local eventData = ItemRackEvents[eventName]
		if eventData and not eventData.Unequip then
			return true
		end
	end
	return false
end

local function hasNonRestoringMountStackLayer()
	for _, eventName in ipairs(ItemRackUser.EventStack or {}) do
		local eventData = ItemRackEvents[eventName]
		if eventData and eventData.Anymount and not eventData.Unequip then
			return true
		end
	end
	return false
end

local function isSetPendingOrSwapping(setname)
	if not setname then return false end
	if ItemRack.SetSwapping == setname then
		return true
	end
	for _, waiting in ipairs(ItemRack.SetsWaiting or {}) do
		if waiting[1] == setname then
			return true
		end
	end
	if ItemRack.CombatSet == setname and next(ItemRack.CombatQueue) then
		return true
	end
	local combatSet = ItemRackUser.Sets and ItemRackUser.Sets["~CombatQueue"]
	return combatSet and combatSet.oldset == setname and ItemRack.SetSwapping == "~CombatQueue" or false
end

local function mountZoneSwapBusy()
	return InCombatLockdown()
		or ItemRack.NowCasting
		or ItemRack.IsPlayerReallyDead()
		or ItemRack.SetSwapping
		or next(ItemRack.CombatQueue)
		or #ItemRack.SetsWaiting > 0
		or ItemRack.AnythingLocked()
end

-- A forced dismount or destination exclusion must unwind mounted gear before a
-- destination Zone event snapshots its history. Otherwise the Zone set records
-- Mounted as its oldset and the inactive mount entry remains stuck in EventStack.
-- Return true when zone processing must wait for combat/casting/another swap.
local function reconcileInvalidMountEvents(isMounted, instanceType)
	-- A prior unwind may still be moving items. Keep Zone and Buff processing
	-- paused until that single layer has fully restored, then handle the next
	-- layer (if any) on the following pass.
	if ItemRack.MountZoneTransitionDeferred and mountZoneSwapBusy() then
		scheduleMountZoneRecheck("mount/zone unwind in progress")
		return true
	end

	local invalidMountEvents = {}
	local seen = {}
	local stack = ItemRackUser.EventStack or {}

	-- Collect topmost-first so nested custom mount events unwind in stack order.
	for i = #stack, 1, -1 do
		local eventName = stack[i]
		local eventData = ItemRackEvents[eventName]
		if eventData and eventData.Anymount then
			local excluded = (eventData.NotInPVP and (instanceType == "arena" or instanceType == "pvp"))
				or (eventData.NotInPVE and (instanceType == "party" or instanceType == "raid"))
			if not isMounted or excluded then
				table.insert(invalidMountEvents, eventName)
				seen[eventName] = true
			end
		end
	end

	-- Also repair an active mount event that was already lost from EventStack by
	-- an earlier interrupted transition.
	for eventName in pairs(ItemRackUser.Events.Enabled or {}) do
		local eventData = ItemRackEvents[eventName]
		if eventData and eventData.Anymount and eventData.Active and not seen[eventName] then
			local excluded = (eventData.NotInPVP and (instanceType == "arena" or instanceType == "pvp"))
				or (eventData.NotInPVE and (instanceType == "party" or instanceType == "raid"))
			if not isMounted or excluded then
				table.insert(invalidMountEvents, eventName)
				seen[eventName] = true
			end
		end
	end

	if #invalidMountEvents == 0 then
		ItemRack.MountZoneTransitionDeferred = nil
		return false
	end

	if mountZoneSwapBusy() then
		ItemRack.MountZoneTransitionDeferred = true
		ItemRack.Debug("Events", "Deferring forced-dismount reconciliation until swap restrictions clear")
		scheduleMountZoneRecheck("forced dismount before zone")
		return true
	end

	local eventName = invalidMountEvents[1]
	local eventData = ItemRackEvents[eventName]
	if eventData then
		ItemRack.Debug("Events", "Unwinding invalid mount event before zone:", eventName, "mounted:", isMounted, "instance:", instanceType)
		eventData.Active = nil
		if eventData.Unequip then
			ItemRack.PopEvent(eventName)
		else
			-- Unequip=false means keep the physical gear, but the event is no
			-- longer active and must not remain as a restoration-stack layer.
			removeEventFromStack(eventName)
			ItemRack.ClearScriptEventState(eventName)
		end
		if ItemRack.PendingOnMovementUnequip == eventName then
			ItemRack.PendingOnMovementUnequip = nil
			ItemRack.StopTimer("OnMovementUnequipTimer")
		end
	end

	-- Always yield after one layer. UnequipSet may complete asynchronously, and
	-- popping another layer before it finishes can splice or overwrite history.
	ItemRack.MountZoneTransitionDeferred = true
	scheduleMountZoneRecheck("continue forced-dismount unwind")
	return true
end

-- A matching Zone event is logically below a still-active mount event. If the
-- Zone event was not already stacked (for example, the player mounted before
-- entering the zone), insert it directly beneath the mount without equipping it.
local function ensureZoneEventBelowMount(zoneEventName, mountEventName)
	local stack = ItemRackUser.EventStack
	if not stack then return end
	local zoneIndex, mountIndex
	for i, eventName in ipairs(stack) do
		if eventName == zoneEventName then zoneIndex = i end
		if eventName == mountEventName then mountIndex = i end
	end
	if zoneIndex then
		-- Existing stack layers carry oldset/old item history that cannot be
		-- safely reordered by moving the name alone.
		return
	end
	if not mountIndex then
		for i, eventName in ipairs(stack) do
			if eventName == mountEventName then
				mountIndex = i
				break
			end
		end
	end
	table.insert(stack, mountIndex or (#stack + 1), zoneEventName)
end

-- When the player remains mounted but the destination needs a different
-- underlying Zone set, unwind the old mount layer first. Zone and Buff processing
-- then serialize the destination Zone set followed by a fresh mount layer,
-- producing the correct Zone -> Mounted history without an oldset cycle.
local function prepareMountRebase(eventName)
	local eventData = eventName and ItemRackEvents[eventName]
	if eventData then
		eventData.Active = nil
		if eventData.Unequip then
			ItemRack.PopEvent(eventName)
		else
			removeEventFromStack(eventName)
			ItemRack.ClearScriptEventState(eventName)
		end
	end
	_refreshMountState = 4
end

local function getZoneMatch(eventData, currentZone, currentSubZone, instanceType)
	if not eventData or not eventData.Zones then return end
	if eventData.Zones[currentZone] then return currentZone end
	if eventData.Zones[currentSubZone] then return currentSubZone end
	if eventData.Zones[instanceType] then return instanceType end
	if instanceType then
		local displayType = instanceType:gsub("^%l", string.upper)
		if eventData.Zones[displayType] then return displayType end
	end
end

function ItemRack.ProcessZoneEvent(reason)
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		ItemRack.Debug("Events", "ProcessZoneEvent deferred while automatic swaps are suspended:", reason or "")
		return false
	end
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents

	local currentZone = GetRealZoneText()
	local currentSubZone = GetSubZoneText()
	local _, instanceType = IsInInstance()
	local isMounted = IsMounted() and not UnitOnTaxi("player")
	local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()

	-- Resolve forced portal/summon dismounts (and PvP/PvE exclusions) before
	-- any destination Zone set can capture Mounted as its previous set.
	if reconcileInvalidMountEvents(isMounted, instanceType) then
		return false
	end
	local zoneSignature = table.concat({
		tostring(instanceType or "none"),
		tostring(currentZone or ""),
		tostring(currentSubZone or ""),
		tostring(instanceID or "")
	}, "\031")

	-- Determine whether a still-valid mount must be temporarily unwound to
	-- change the underlying Zone layer. Only an actual rebase is blocked by
	-- unrelated inventory activity; an unchanged mounted state remains usable.
	local activeMountEvents = getActiveMountEvents()
	if hasNonRestoringMountStackLayer() then
		-- Unequip=false intentionally leaves that event's physical gear in place.
		-- A destination Zone cannot be inserted beneath it with valid history, so
		-- leave existing Zone state untouched and evaluate it after the mount stack
		-- is removed by a real dismount or exclusion.
		ItemRack.Debug("Events", "Zone processing held behind a non-restoring mount layer")
		return true
	end
	local topMountEvent = activeMountEvents[1]
	local baseMountEvent = activeMountEvents[#activeMountEvents]
	local mountNeedsRebase = false
	local allMountLayersRestore = #activeMountEvents > 0 and not hasNonRestoringMountLayer(activeMountEvents)
	if allMountLayersRestore and baseMountEvent then
		local baseMountSet = ItemRack.GetEventSet(baseMountEvent)
		local mountSetData = baseMountSet and ItemRackUser.Sets[baseMountSet]
		for eventName in pairs(enabled) do
			local zoneData = events[eventName]
			if zoneData and zoneData.Type == "Zone" then
				local setname = ItemRackUser.Events.Set[eventName]
				local matchedZone = getZoneMatch(zoneData, currentZone, currentSubZone, instanceType)
				if matchedZone then
					local signatureChanged = not zoneData.LastZoneSignature or zoneData.LastZoneSignature ~= zoneSignature
					-- An inactive Zone is not established beneath the mount merely
					-- because its items happen to match the visible mounted gear.
					-- It still needs a real history layer before the mount is reapplied.
					local willEquip = (signatureChanged and zoneData.Active) or not zoneData.Active
					if willEquip and (not mountSetData or mountSetData.oldset ~= setname) then
						mountNeedsRebase = true
						break
					end
				elseif zoneData.Active and zoneData.Unequip then
					-- Leaving the underlying Zone while mounted must also unwind the
					-- mount first so the buried Zone event can restore safely.
					mountNeedsRebase = true
					break
				end
			end
		end
	end
	if mountNeedsRebase then
		if mountZoneSwapBusy() then
			ItemRack.MountZoneTransitionDeferred = true
			ItemRack.Debug("Events", "Deferring mounted zone rebase until swap restrictions clear")
			scheduleMountZoneRecheck("mounted zone rebase")
			return false
		end
		ItemRack.MountZoneTransitionDeferred = nil
		-- Custom Anymount events can coexist. Unwind exactly one layer at a time,
		-- topmost-first, and wait for its item swap to finish before reconsidering
		-- the next layer or applying the destination Zone set.
		mountZoneRebasePending = true
		prepareMountRebase(topMountEvent)
		ItemRack.MountZoneTransitionDeferred = true
		scheduleMountZoneRecheck("continue mounted zone rebase")
		return false
	else
		ItemRack.MountZoneTransitionDeferred = nil
	end

	if ItemRack.DebugAll or ItemRack.DebugTags.Events then
		ItemRack.Debug("Events", "ProcessZoneEvent called. Reason:", reason or "timer", "Zone:", currentZone, "SubZone:", currentSubZone, "InstanceType:", instanceType, "InstanceID:", instanceID, "Signature:", zoneSignature)
	end

	local eventsToUnequip = {}
	local eventsToEquip = {}

	for eventName in pairs(enabled) do
		local eventData = events[eventName]
		if eventData and eventData.Type=="Zone" then
			local setname = ItemRackUser.Events.Set[eventName]
			local matchedZone = getZoneMatch(eventData, currentZone, currentSubZone, instanceType)
			
			if matchedZone then
				local currentSignature = eventData.LastZoneSignature
				local signatureChanged = not currentSignature or currentSignature ~= zoneSignature

				if not eventData.Active or signatureChanged then
					if signatureChanged and eventData.Active then
						-- Transitioned to a new zone/instance signature: clear manual override
						eventData.ManualOverride = nil
						
						-- Clear active mount if needed
						local keepMount = false
						local activeMountEvents = getActiveMountEvents()
						local topMountEvent = activeMountEvents[1]
						local baseMountEvent = activeMountEvents[#activeMountEvents]
						if topMountEvent and baseMountEvent and isMounted and events[topMountEvent] and events[topMountEvent].Active then
							local baseMountSet = ItemRack.GetEventSet(baseMountEvent)
							if hasNonRestoringMountLayer(activeMountEvents)
							or not events[baseMountEvent].Unequip
							or (baseMountSet and ItemRackUser.Sets[baseMountSet] and ItemRackUser.Sets[baseMountSet].oldset == setname) then
								keepMount = true
							end
						end

						if keepMount then
							ensureZoneEventBelowMount(eventName, baseMountEvent)
							ItemRack.Debug("Events", "  Zone event transition kept beneath active mount:", eventName)
						else
							table.insert(eventsToEquip, eventName)
							if ItemRack.DebugAll or ItemRack.DebugTags.Events then
								ItemRack.Debug("Events", "  Zone event transition to new signature for:", eventName, "action: equip")
							end
						end
					elseif (mountZoneRebasePending or #getActiveMountEvents() > 0 or not ItemRack.IsSetEquipped(setname)) and not isSetPendingOrSwapping(setname) then
						-- First entry needs either an equip or an explicit history layer
						-- beneath mounted gear, even if the visible items happen to match.
						local keepMount = false
						local activeMountEvents = getActiveMountEvents()
						local topMountEvent = activeMountEvents[1]
						local baseMountEvent = activeMountEvents[#activeMountEvents]
						if topMountEvent and baseMountEvent and isMounted and events[topMountEvent] and events[topMountEvent].Active then
							local baseMountSet = ItemRack.GetEventSet(baseMountEvent)
							if hasNonRestoringMountLayer(activeMountEvents)
							or not events[baseMountEvent].Unequip
							or (baseMountSet and ItemRackUser.Sets[baseMountSet] and ItemRackUser.Sets[baseMountSet].oldset == setname) then
								keepMount = true
							end
						end

						if keepMount then
							ensureZoneEventBelowMount(eventName, baseMountEvent)
							ItemRack.Debug("Events", "  Zone event first entry kept beneath active mount:", eventName)
						else
							table.insert(eventsToEquip, eventName)
							if ItemRack.DebugAll or ItemRack.DebugTags.Events then
								ItemRack.Debug("Events", "  Zone event first entry for:", eventName, "action: equip")
							end
						end
					end
					
					eventData.Active = true
					eventData.LastZoneMatched = matchedZone
					eventData.LastZoneSignature = zoneSignature
				else
					-- Active and same signature
					local zoneCoveredByMount = false
					local activeMountEvents = getActiveMountEvents()
					local topMountEvent = activeMountEvents[1]
					local baseMountEvent = activeMountEvents[#activeMountEvents]
					if topMountEvent and baseMountEvent then
						local topMountSet = ItemRack.GetEventSet(topMountEvent)
						local baseMountSet = ItemRack.GetEventSet(baseMountEvent)
						local mountSetData = baseMountSet and ItemRackUser.Sets[baseMountSet]
						zoneCoveredByMount = (hasNonRestoringMountLayer(activeMountEvents)
							or not events[baseMountEvent].Unequip
							or (mountSetData and mountSetData.oldset == setname))
							and (ItemRackUser.CurrentSet == topMountSet or ItemRack.IsSetEquipped(topMountSet))
					end
					if zoneCoveredByMount then
						-- The Zone set is intentionally hidden beneath mounted gear; this is
						-- not a manual override. Clear stale override state from older builds.
						eventData.ManualOverride = nil
					elseif not ItemRack.IsSetEquipped(setname) and not isSetPendingOrSwapping(setname) then
						-- Same zone, set is not equipped, but event is active: user manually changed gear.
						if not eventData.ManualOverride then
							eventData.ManualOverride = true
							if ItemRack.DebugAll or ItemRack.DebugTags.Events then
								ItemRack.Debug("Events", "  Zone event manual override set for:", eventName, "in signature:", zoneSignature)
							end
						end
					elseif eventData.ManualOverride then
						-- Set IS equipped but ManualOverride was on - user re-equipped the zone set manually.
						eventData.ManualOverride = nil
						if ItemRack.DebugAll or ItemRack.DebugTags.Events then
							ItemRack.Debug("Events", "  Zone event manual override cleared for:", eventName, "set re-equipped")
						end
					end
				end
			else -- not matchedZone
				if eventData.Active then
					if eventData.Unequip then
						table.insert(eventsToUnequip, eventName)
					end
					eventData.Active = nil
					eventData.LastZoneMatched = nil
					eventData.LastZoneSignature = nil
					eventData.ManualOverride = nil
					if ItemRack.DebugAll or ItemRack.DebugTags.Events then
						ItemRack.Debug("Events", "  Zone event left matched zone for:", eventName, "action: unequip")
					end
				elseif eventData.Unequip and ItemRack.IsSetEquipped(setname) then
					-- Fallback for consistency: only trigger if the user didn't manually equip this set
					if ItemRackUser.CurrentSet ~= setname then
						table.insert(eventsToUnequip, eventName)
					end
				end
			end
		end
	end

	-- Deterministic execution of unequips first, then equips
	table.sort(eventsToUnequip)
	table.sort(eventsToEquip)

	for _, en in ipairs(eventsToUnequip) do
		ItemRack.PopEvent(en)
	end
	for _, en in ipairs(eventsToEquip) do
		ItemRack.PushEvent(en)
	end
	mountZoneRebasePending = nil
	return true
end

function ItemRack.ProcessSpecializationEvent(force)
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		return
	end
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents
	
	local getSpec = GetActiveTalentGroup or (C_Talent and C_Talent.GetActiveTalentGroup)
	if not getSpec then return end
	local currentSpec = getSpec()
	
	-- Guard against invalid spec index (can occur during zoning/loading)
	if not currentSpec or currentSpec == 0 then return end
	
	-- Only proceed if the spec index has actually changed
	if not force and ItemRack.LastLastSpec == currentSpec then return end
	ItemRack.LastLastSpec = currentSpec

	local preserveRequestedSet
	local pendingSpecSet = ItemRack.PendingSpecSet
	if pendingSpecSet then
		local expired = pendingSpecSet.expiresAt and GetTime() > pendingSpecSet.expiresAt
		local requestedSetExists = pendingSpecSet.setname and ItemRackUser.Sets[pendingSpecSet.setname]
		if not expired and requestedSetExists and pendingSpecSet.spec == currentSpec and ItemRackUser.CurrentSet == pendingSpecSet.setname then
			preserveRequestedSet = pendingSpecSet.setname
			ItemRack.Debug("Events", "Preserving associated set through spec change:", preserveRequestedSet)
		end
		-- A spec transition consumes the request whether it reached the expected
		-- destination or the player changed course before the cast completed.
		ItemRack.PendingSpecSet = nil
	end
	
	local eventToEquip, eventToUnequip, eventToAdopt, setname
	
	for eventName in pairs(enabled) do
		local eventData = events[eventName]
		if eventData and eventData.Type=="Specialization" and eventData.Spec then
			setname = ItemRackUser.Events.Set[eventName]
			-- Always equip the set for the current spec
			if eventData.Spec == currentSpec then
				if preserveRequestedSet then
					-- If this event already maps to the requested set, adopt it into
					-- the event stack without equipping it a second time. Otherwise
					-- leave the destination event inactive so its default set cannot
					-- replace another explicitly selected set for the same spec.
					if setname == preserveRequestedSet then
						eventToAdopt = eventName
						eventData.Active = true
					else
						eventData.Active = nil
					end
				elseif not eventData.Active then
					eventToEquip = eventName
					eventData.Active = true
				end
			-- Unequip sets for other specs if they're equipped
			elseif eventData.Spec ~= currentSpec then
				if eventData.Active then
					if eventData.Unequip then
						eventToUnequip = eventName
					end
					eventData.Active = nil
				elseif eventData.Unequip and ItemRack.IsSetEquipped(setname) then
					-- Fallback for consistency: only trigger if the user didn't manually equip this set
					if ItemRackUser.CurrentSet ~= setname then
						eventToUnequip = eventName
					end
				end
			end
		end
	end
	
	-- Unequip first, then equip (to avoid conflicts)
	local unequipTriggered = false
	if eventToUnequip and eventToUnequip ~= eventToEquip then
		ItemRack.PopEvent(eventToUnequip)
		unequipTriggered = true
	end
	if preserveRequestedSet then
		-- Remove any stale destination-spec layer before optionally adopting the
		-- event whose mapping already matches the requested set.
		for i = #ItemRackUser.EventStack, 1, -1 do
			local stackedEvent = ItemRackUser.EventStack[i]
			local stackedData = events[stackedEvent]
			if stackedData and stackedData.Type=="Specialization" and stackedData.Spec==currentSpec then
				table.remove(ItemRackUser.EventStack,i)
			end
		end
		if eventToAdopt then
			table.insert(ItemRackUser.EventStack,eventToAdopt)
			ItemRack.Debug("Events", "Adopted requested set into specialization event:", eventToAdopt, preserveRequestedSet)
		else
			ItemRack.Debug("Events", "Suppressed destination specialization default to preserve:", preserveRequestedSet)
		end
		ItemRack.ScheduleDualWieldRetry(preserveRequestedSet)
		ItemRack.UpdateCurrentSet()
		return
	end
	if eventToEquip then
		local setToEquip = ItemRackUser.Events.Set[eventToEquip]
		if not ItemRack.IsSetEquipped(setToEquip) or unequipTriggered then
			ItemRack.Print("Spec changed! Equipping set: "..setToEquip)
			ItemRack.PushEvent(eventToEquip)
			
			-- Dual-Wield Awareness: Schedule a delayed re-check for weapon slots
			ItemRack.ScheduleDualWieldRetry(setToEquip)
		else
			-- If already equipped, still update the UI to ensure the correct set name is shown
			ItemRack.UpdateCurrentSet()
		end
	end
end

-- Dual-Wield Retry: Re-attempt weapon equip after spec change if offhand wasn't equipped
-- Uses EquipItemByID directly instead of temporary sets to avoid queue conflicts
function ItemRack.ScheduleDualWieldRetry(setname)
	if not setname or not ItemRackUser.Sets[setname] then return end
	
	local set = ItemRackUser.Sets[setname].equip
	-- Only proceed if the set has an offhand weapon defined
	if not set or not set[17] or set[17] == 0 then return end
	
	-- Capture the current spec at schedule time for later verification
	local getSpec = GetActiveTalentGroup or (C_Talent and C_Talent.GetActiveTalentGroup)
	local scheduledSpec = getSpec and getSpec() or nil
	
	-- Schedule a delayed check to retry the offhand after dual-wield is recognized
	-- Must wait longer than the 5-second spec change cast to ensure dual-wield is granted
	-- Single attempt only - no retry loop to avoid pestering the user
	C_Timer.After(5.5, function()
		ItemRack.RetryDualWieldWeapons(setname, scheduledSpec)
	end)
end

function ItemRack.RetryDualWieldWeapons(setname, expectedSpec)
	-- Re-validate set still exists (could have been deleted)
	if not setname or not ItemRackUser.Sets[setname] then return end
	
	-- Verify we're still on the expected spec (user might have walked away or switched again)
	local getSpec = GetActiveTalentGroup or (C_Talent and C_Talent.GetActiveTalentGroup)
	local currentSpec = getSpec and getSpec() or nil
	if expectedSpec and currentSpec and currentSpec ~= expectedSpec then
		-- User switched specs again, abort silently
		return
	end
	
	-- Check if the player can now dual-wield
	local canDualWield = CanDualWield and CanDualWield()
	if not canDualWield then 
		-- Spec doesn't support dual-wield, exit gracefully
		return 
	end
	
	local set = ItemRackUser.Sets[setname].equip
	if not set then return end
	
	local currentOffhand = ItemRack.GetID(17)
	local intendedOffhand = set[17]
	
	-- If offhand is defined but not correctly equipped, retry using EquipItemByID
	-- This doesn't use temporary sets, so it won't pollute the SetsWaiting queue
	if intendedOffhand and intendedOffhand ~= 0 and not ItemRack.MatchesStoredItemID(intendedOffhand, currentOffhand) then
		ItemRack.Print("Dual-wield detected, retrying offhand weapon...")
		
		-- Use EquipItemByID which handles combat queue properly
		-- and doesn't create temporary sets
		ItemRack.EquipItemByID(intendedOffhand, 17)
		
		-- Also retry mainhand if needed
		local currentMainhand = ItemRack.GetID(16)
		local intendedMainhand = set[16]
		if intendedMainhand and intendedMainhand ~= 0 and not ItemRack.MatchesStoredItemID(intendedMainhand, currentMainhand) then
			ItemRack.EquipItemByID(intendedMainhand, 16)
		end
	end
end

--here we observe mounted status and raise an event should it change. UNIT_AURA event seems unreliable for this
local _lastStateMounted = IsMounted() and not UnitOnTaxi("player")
local mountStateChangedAt = GetTime()
local mountEquipDelay = 0.75
local mountEquipDelayPending

function ItemRack.ResetMountEventStability()
	_lastStateMounted = IsMounted() and not UnitOnTaxi("player")
	mountStateChangedAt = GetTime()
end

local function scheduleMountEquipCheck()
	if mountEquipDelayPending then return end
	mountEquipDelayPending = true
	local remaining = math.max(mountEquipDelay - (GetTime() - mountStateChangedAt), 0.05)
	C_Timer.After(remaining, function()
		mountEquipDelayPending = nil
		if IsMounted() and not UnitOnTaxi("player") then
			ItemRack.ProcessBuffEvent()
		end
	end)
end

function ItemRack.CheckForMountedEvents()
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		return
	end
	local getSlots = C_Container and C_Container.GetContainerNumSlots or _G.GetContainerNumSlots
	local numSlots = getSlots and getSlots(0)
	if not numSlots or numSlots == 0 then
		return
	end

	if UnitIsDeadOrGhost("player") then
		return
	end

	if ItemRackUser.EnableEvents=="OFF" then
		return
	end

	local isPlayerMounted = IsMounted() and not UnitOnTaxi("player")
	if isPlayerMounted ~= _lastStateMounted or _refreshMountState == 1 then
		_lastStateMounted = isPlayerMounted
		mountStateChangedAt = GetTime()
		_refreshMountState = 0
		if isPlayerMounted then
			-- Let the mount and movement state stabilize before issuing item API
			-- calls. This avoids starting a trinket swap in the same instant that
			-- the player flies through an instance portal after a summon.
			scheduleMountEquipCheck()
		else
			ItemRack.ProcessBuffEvent()
		end
	elseif _refreshMountState > 1 then
		_refreshMountState = _refreshMountState - 1
	end
end

-- Debounced OnMovement unequip callback. Fires 0.5s after the player stops moving.
-- If they started moving again within that window, PendingOnMovementUnequip was cleared
-- and this function does nothing.
function ItemRack.ProcessOnMovementUnequip()
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		ItemRack.PendingOnMovementUnequip = nil
		return
	end
	local eventName = ItemRack.PendingOnMovementUnequip
	ItemRack.PendingOnMovementUnequip = nil
	if not eventName then return end

	local events = ItemRackEvents
	if not events[eventName] then return end

	local speed = GetUnitSpeed("player")
	ItemRack.Debug("Events", "ProcessOnMovementUnequip ("..eventName.."): speed="..tostring(speed).." active="..tostring(events[eventName].Active))

	-- Double-check: only unequip if the player is truly not moving
	if speed > 0 then return end

	if events[eventName].Active then
		ItemRack.PopEvent(eventName)
		events[eventName].Active = nil
	end
end
function ItemRack.ProcessBuffEvent()
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		ItemRack.Debug("Events", "ProcessBuffEvent deferred while automatic swaps are suspended")
		return
	end
	local currentlyMounted = IsMounted() and not UnitOnTaxi("player")
	if currentlyMounted ~= _lastStateMounted then
		_lastStateMounted = currentlyMounted
		mountStateChangedAt = GetTime()
	end
	if currentlyMounted and (GetTime() - mountStateChangedAt) < mountEquipDelay then
		scheduleMountEquipCheck()
		return
	end
	if ItemRack.MountZoneTransitionDeferred then
		ItemRack.Debug("Events", "ProcessBuffEvent paused while mount/zone transition is deferred")
		return
	end
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents

	local buff, setname, isSetEquipped

	-- Zone-transition awareness: suppress OnMovement unequips if a zone change
	-- happened within the last 1 second. Zone boundaries can cause speed blips
	-- or aura flickers that would otherwise trigger a spurious unequip.
	local inZoneTransition = ItemRack.LastZoneChangeTime and (GetTime() - ItemRack.LastZoneChangeTime) < 1

	for eventName in pairs(enabled) do
		local eventData = events[eventName]
		if eventData and eventData.Type=="Buff" then
			local excluded = false
			if eventData.NotInPVP then
				local _,instanceType = IsInInstance()
				if instanceType=="arena" or instanceType=="pvp" then
					excluded = true
				end
			end
			if eventData.NotInPVE then
				local _,instanceType = IsInInstance()
				if instanceType=="party" or instanceType=="raid" then
					excluded = true
				end
			end
			
			if excluded then
				if eventData.Active then
					if eventData.Unequip then
						ItemRack.PopEvent(eventName)
					end
					eventData.Active = nil
					if ItemRack.PendingOnMovementUnequip == eventName then
						ItemRack.PendingOnMovementUnequip = nil
						ItemRack.StopTimer("OnMovementUnequipTimer")
					end
				end
			else
				-- Determine the underlying buff/mount condition (ignoring movement)
				local underlyingBuff
				if eventData.Anymount then
					underlyingBuff = IsMounted() and not UnitOnTaxi("player")
				else
					underlyingBuff = AuraUtil.FindAuraByName(eventData.Buff,"player")
				end

				-- Apply OnMovement check: buff is only true if moving
				buff = underlyingBuff
				if buff and eventData.OnMovement then
					buff = GetUnitSpeed("player") > 0
				end
				setname = ItemRackUser.Events.Set[eventName]
				isSetEquipped = ItemRack.IsSetEquipped(setname)
				
				if eventData.OnMovement then
					ItemRack.Debug("Events", "ProcessBuffEvent checking "..(eventName or "nil")..": moving="..tostring(GetUnitSpeed("player") > 0).." underlyingBuff="..tostring(underlyingBuff).." isSetEquipped="..tostring(isSetEquipped).." active="..tostring(eventData.Active))
				end
				
				-- Use .Active to track if we've already handled this event
				-- This prevents spamming EquipSet if IsSetEquipped returns false (e.g. due to API bugs or manual swaps)
				-- And ensures UnequipSet triggers even if the set is only partially equipped
				if buff then
					-- Player is moving (or buff active for non-movement events).
					if eventData.OnMovement and ItemRack.PendingOnMovementUnequip == eventName then
						ItemRack.PendingOnMovementUnequip = nil
						ItemRack.StopTimer("OnMovementUnequipTimer")
					end
					if not eventData.Active then
						ItemRack.PushEvent(eventName)
						eventData.Active = true
					end
				elseif not buff then
					if eventData.Active then
						if eventData.Unequip then
							-- Zone-transition suppression: if this is an OnMovement event and the
							-- underlying buff is still active but we just crossed a zone boundary,
							-- skip the unequip. The zone transition likely caused a speed blip
							-- or aura flicker — not an intentional stop.
							if eventData.OnMovement and underlyingBuff and inZoneTransition then
								-- Suppress: still mounted, zone boundary artifact. Do nothing.
							elseif eventData.OnMovement and underlyingBuff then
								if eventData.OnMovementDelay == false then
									-- User explicitly disabled the 0.5s stop debounce. Instant unequip.
									ItemRack.PopEvent(eventName)
									eventData.Active = nil
								else
									-- OnMovement debounce: delay the unequip by 0.5s.
									-- If the player starts moving again within that window, the
									-- timer is cancelled above and no swap occurs.
									if not ItemRack.PendingOnMovementUnequip then
										ItemRack.PendingOnMovementUnequip = eventName
										ItemRack.StartTimer("OnMovementUnequipTimer")
									end
								end
							else
								ItemRack.PopEvent(eventName)
								eventData.Active = nil
							end
						else
							eventData.Active = nil
						end
					elseif isSetEquipped and eventData.Unequip then
						-- Fallback: If we didn't track it as active but the set IS equipped, unequip it
						-- Fixed: Skip if the user manually equipped this set right now (CurrentSet check)
						-- Fixed: Skip if the addon is actively swapping out any set (SetSwapping) or if items are locked (AnythingLocked) to prevent double-pops from server lag
						if ItemRackUser.CurrentSet ~= setname and not ItemRack.SetSwapping and not ItemRack.AnythingLocked() then
							ItemRack.PopEvent(eventName)
						end
					end
				end
			end
		end
	end
end

local prevIcon, prevText
function ItemRack.ReflectEventsRunning()
	if ItemRackUser.EnableEvents=="ON" and next(ItemRackUser.Events.Enabled) then
		-- if events enabled and an event is enabled, show gear icons on set and minimap button
		if ItemRackUser.Buttons[20] then
			ItemRackButton20Queue:Show()
		end
		prevIcon = ItemRack.Broker.icon
		prevText = ItemRack.Broker.text
		ItemRack.Broker.icon = [[Interface\AddOns\ItemRack\ItemRackGear]]
		ItemRack.Broker.text = "..."
	else
		if ItemRackUser.Buttons[20] then
			ItemRackButton20Queue:Hide()
		end
		if prevIcon then
			ItemRack.Broker.icon = prevIcon
			ItemRack.Broker.text = prevText
		end
	end
end
