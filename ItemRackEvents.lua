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

function ItemRack.ToggleEvents(self)
	ItemRackUser.EnableEvents = ItemRackUser.EnableEvents=="ON" and "OFF" or "ON"
	if not next(ItemRackUser.Events.Enabled) then
		-- user is turning on events with no events enabled, go to events frame
		if ItemRackOptFrame then
			ItemRackOptFrame:Show()
			ItemRackOpt.TabOnClick(self,3)
		else
			ItemRack.Print("Options panel not loaded.")
		end
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

function ItemRack.GetStanceNumber(name)
	if tonumber(name) then
		return name
	end
	for i=1,GetNumShapeshiftForms() do
		if name==select(2,GetShapeshiftFormInfo(i)) then
			return i
		end
	end
end

function ItemRack.ProcessStanceEvent()
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

function ItemRack.ProcessZoneEvent(reason)
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents

	local currentZone = GetRealZoneText()
	local currentSubZone = GetSubZoneText()
	local _, instanceType = IsInInstance()
	local isMounted = IsMounted() and not UnitOnTaxi("player")
	local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()

	local zoneSignature = table.concat({
		tostring(instanceType or "none"),
		tostring(currentZone or ""),
		tostring(currentSubZone or ""),
		tostring(instanceID or "")
	}, "\031")

	if ItemRack.DebugAll or ItemRack.DebugTags.Events then
		ItemRack.Debug("Events", "ProcessZoneEvent called. Reason:", reason or "timer", "Zone:", currentZone, "SubZone:", currentSubZone, "InstanceType:", instanceType, "InstanceID:", instanceID, "Signature:", zoneSignature)
	end

	local eventsToUnequip = {}
	local eventsToEquip = {}

	for eventName in pairs(enabled) do
		local eventData = events[eventName]
		if eventData and eventData.Type=="Zone" then
			local setname = ItemRackUser.Events.Set[eventName]
			local matchedZone = nil
			if eventData.Zones then
				if eventData.Zones[currentZone] then matchedZone = currentZone
				elseif eventData.Zones[currentSubZone] then matchedZone = currentSubZone
				elseif eventData.Zones[instanceType] then matchedZone = instanceType
				elseif eventData.Zones[instanceType:gsub("^%l", string.upper)] then matchedZone = instanceType:gsub("^%l", string.upper)
				end
			end
			
			if matchedZone then
				local currentSignature = eventData.LastZoneSignature
				local signatureChanged = not currentSignature or currentSignature ~= zoneSignature

				if not eventData.Active or signatureChanged then
					if signatureChanged and eventData.Active then
						-- Transitioned to a new zone/instance signature: clear manual override
						eventData.ManualOverride = nil
						
						-- Clear active mount if needed
						local keepMount = true
						local activeMountEvent = nil
						for _, activeEventName in ipairs(ItemRackUser.EventStack) do
							local mEventData = events[activeEventName]
							if mEventData and mEventData.Anymount then
								activeMountEvent = activeEventName
								break
							end
						end
						if activeMountEvent and isMounted and events[activeMountEvent] and events[activeMountEvent].Active then
							local activeMountSet = ItemRack.GetEventSet(activeMountEvent)
							if activeMountSet and ItemRackUser.Sets[activeMountSet] and ItemRackUser.Sets[activeMountSet].oldset == setname then
								if events[activeMountEvent].NotInPVP and (instanceType=="arena" or instanceType=="pvp") then
									keepMount = false
									if events[activeMountEvent].Unequip then
										ItemRack.PopEvent(activeMountEvent)
									end
								elseif events[activeMountEvent].NotInPVE and (instanceType=="party" or instanceType=="raid") then
									keepMount = false
									if events[activeMountEvent].Unequip then
										ItemRack.PopEvent(activeMountEvent)
									end
								end
							else
								keepMount = false
							end
						else
							keepMount = false
						end

						if not keepMount and activeMountEvent and events[activeMountEvent] then
							events[activeMountEvent].Active = false
							_refreshMountState = 4
						end

						-- Equip set
						table.insert(eventsToEquip, eventName)
						if ItemRack.DebugAll or ItemRack.DebugTags.Events then
							ItemRack.Debug("Events", "  Zone event transition to new signature for:", eventName, "action: equip")
						end
					elseif not ItemRack.IsSetEquipped(setname) then
						-- First entry into the zone (not active yet) and set is not equipped
						local keepMount = true
						local activeMountEvent = nil
						for _, activeEventName in ipairs(ItemRackUser.EventStack) do
							local mEventData = events[activeEventName]
							if mEventData and mEventData.Anymount then
								activeMountEvent = activeEventName
								break
							end
						end
						if activeMountEvent and isMounted and events[activeMountEvent] and events[activeMountEvent].Active then
							local activeMountSet = ItemRack.GetEventSet(activeMountEvent)
							if activeMountSet and ItemRackUser.Sets[activeMountSet] and ItemRackUser.Sets[activeMountSet].oldset == setname then
								if events[activeMountEvent].NotInPVP and (instanceType=="arena" or instanceType=="pvp") then
									keepMount = false
									if events[activeMountEvent].Unequip then
										ItemRack.PopEvent(activeMountEvent)
									end
								elseif events[activeMountEvent].NotInPVE and (instanceType=="party" or instanceType=="raid") then
									keepMount = false
									if events[activeMountEvent].Unequip then
										ItemRack.PopEvent(activeMountEvent)
									end
								end
							else
								keepMount = false
							end
						else
							keepMount = false
						end

						if not keepMount and activeMountEvent and events[activeMountEvent] then
							events[activeMountEvent].Active = false
							_refreshMountState = 4
						end

						table.insert(eventsToEquip, eventName)
						if ItemRack.DebugAll or ItemRack.DebugTags.Events then
							ItemRack.Debug("Events", "  Zone event first entry for:", eventName, "action: equip")
						end
					end
					
					eventData.Active = true
					eventData.LastZoneMatched = matchedZone
					eventData.LastZoneSignature = zoneSignature
				else
					-- Active and same signature
					if not ItemRack.IsSetEquipped(setname) then
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
end

function ItemRack.ProcessSpecializationEvent()
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents
	
	local getSpec = GetActiveTalentGroup or (C_Talent and C_Talent.GetActiveTalentGroup)
	if not getSpec then return end
	local currentSpec = getSpec()
	
	-- Guard against invalid spec index (can occur during zoning/loading)
	if not currentSpec or currentSpec == 0 then return end
	
	-- Only proceed if the spec index has actually changed
	if ItemRack.LastLastSpec == currentSpec then return end
	ItemRack.LastLastSpec = currentSpec
	
	local eventToEquip, eventToUnequip, setname
	
	for eventName in pairs(enabled) do
		if events[eventName].Type=="Specialization" and events[eventName].Spec then
			setname = ItemRackUser.Events.Set[eventName]
			-- Always equip the set for the current spec
			if events[eventName].Spec == currentSpec then
				if not events[eventName].Active then
					eventToEquip = eventName
					events[eventName].Active = true
				end
			-- Unequip sets for other specs if they're equipped
			elseif events[eventName].Spec ~= currentSpec then
				if events[eventName].Active then
					if events[eventName].Unequip then
						eventToUnequip = eventName
					end
					events[eventName].Active = nil
				elseif events[eventName].Unequip and ItemRack.IsSetEquipped(setname) then
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
	if intendedOffhand and intendedOffhand ~= 0 and not ItemRack.SameID(currentOffhand, intendedOffhand) then
		ItemRack.Print("Dual-wield detected, retrying offhand weapon...")
		
		-- Use EquipItemByID which handles combat queue properly
		-- and doesn't create temporary sets
		ItemRack.EquipItemByID(intendedOffhand, 17)
		
		-- Also retry mainhand if needed
		local currentMainhand = ItemRack.GetID(16)
		local intendedMainhand = set[16]
		if intendedMainhand and intendedMainhand ~= 0 and not ItemRack.SameID(currentMainhand, intendedMainhand) then
			ItemRack.EquipItemByID(intendedMainhand, 16)
		end
	end
end

--here we observe mounted status and raise an event should it change. UNIT_AURA event seems unreliable for this
local _lastStateMounted = IsMounted() and not UnitOnTaxi("player")
function ItemRack.CheckForMountedEvents()
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
		_refreshMountState = 0
		ItemRack.ProcessBuffEvent()
	elseif _refreshMountState > 1 then
		_refreshMountState = _refreshMountState - 1
	end
end

-- Debounced OnMovement unequip callback. Fires 0.5s after the player stops moving.
-- If they started moving again within that window, PendingOnMovementUnequip was cleared
-- and this function does nothing.
function ItemRack.ProcessOnMovementUnequip()
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
