-- Compatibility shim for LoadAddOn (moved to C_AddOns in TBC 2.5.5+)
local LoadAddOn = LoadAddOn or (C_AddOns and C_AddOns.LoadAddOn)

-- Compatibility shim for loadstring (renamed to load in Lua 5.2+)
local loadstring = loadstring or load
local _refreshMountState = 0
local CaptureLegacyEventState

-- Script events execute arbitrary Lua and ItemRackEvents is a shared global
-- SavedVariable that any addon can modify. Keep the active approval snapshot
-- private to this file and compare the exact event name, trigger, and source at
-- every registration/dispatch boundary. This is a consent and persistence
-- guard, not an addon sandbox: all WoW addons still share one Lua environment.
local scriptEventPrelude = "local event,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,arg10 = ...;local EquipEventSet = function(setname, disableSound) return ItemRack.ScriptEventEquip(event, setname, disableSound) end;local UnequipEventSet = function(disableSound) return ItemRack.ScriptEventUnequip(event, disableSound) end;local EquipSet = function(setname, disableSound) return EquipEventSet(setname, disableSound) end;local UnequipSet = function(setname, disableSound) local activeSet = ItemRack.GetEventSet(event) if setname and (not activeSet or setname ~= activeSet) then return ItemRack.UnequipSet(setname, disableSound) end return UnequipEventSet(disableSound) end;"
local maxScriptEventLength = 4096
local maxScriptTriggerLength = 128
local approvedScriptEvents = {}
local lastApprovedScriptEvents = {}
local scriptApprovalsInitialized = false
local pendingScriptApproval
local bundledScriptEvents = {}

local function ScriptApprovalRecord(eventName,eventData,approvedBy)
	return {
		Event = eventName,
		Type = "Script",
		Trigger = eventData.Trigger,
		Script = eventData.Script,
		ApprovedBy = approvedBy,
	}
end

local function ScriptApprovalMatches(record,eventName,eventData)
	return type(record) == "table"
		and type(eventData) == "table"
		and record.Event == eventName
		and record.Trigger == eventData.Trigger
		and record.Script == eventData.Script
end

local function ValidateScriptEvent(eventName,eventData)
	if type(eventName) ~= "string" or eventName == "" then
		return false,"invalid event name"
	end
	if type(eventData) ~= "table" or eventData.Type ~= "Script" then
		return false,"not a script event"
	end
	if type(eventData.Trigger) ~= "string" or eventData.Trigger == ""
		or #eventData.Trigger > maxScriptTriggerLength
		or not eventData.Trigger:match("^[A-Z][A-Z0-9_]*$") then
		return false,"invalid game-event trigger"
	end
	if type(eventData.Script) ~= "string" or eventData.Script == "" then
		return false,"missing script text"
	end
	if #eventData.Script > maxScriptEventLength then
		return false,"script exceeds the 4096-character editor limit"
	end
	if eventData.Script:find("%z") then
		return false,"script contains an invalid null byte"
	end
	return true
end

local function IsBundledScriptEvent(eventName,eventData)
	local default = bundledScriptEvents[eventName]
	return type(default) == "table" and default.Type == "Script"
		and default.Trigger == eventData.Trigger
		and default.Script == eventData.Script
end

local function EnsureScriptApprovalStore()
	local userEvents = ItemRackUser and ItemRackUser.Events
	if type(userEvents) ~= "table" then return nil end
	if type(userEvents.ScriptApprovals) ~= "table" then
		userEvents.ScriptApprovals = {}
	end
	return userEvents.ScriptApprovals
end

local function InitializeScriptEventApprovals()
	approvedScriptEvents = {}
	lastApprovedScriptEvents = {}
	scriptApprovalsInitialized = true
	local stored = EnsureScriptApprovalStore()
	if not stored then return end
	for eventName,record in pairs(stored) do
		local approvedData = type(record) == "table" and {
			Type = "Script",
			Trigger = record.Trigger,
			Script = record.Script,
		}
		local valid = type(record) == "table"
			and (record.ApprovedBy == "interface" or record.ApprovedBy == "prompt")
			and record.Event == eventName and ValidateScriptEvent(eventName,approvedData)
		if valid then
			lastApprovedScriptEvents[eventName] = ScriptApprovalRecord(eventName,approvedData,record.ApprovedBy)
		else
			stored[eventName] = nil
		end
	end
	for eventName,eventData in pairs(ItemRackEvents or {}) do
		local valid = ValidateScriptEvent(eventName,eventData)
		if valid and IsBundledScriptEvent(eventName,eventData) then
			approvedScriptEvents[eventName] = ScriptApprovalRecord(eventName,eventData,"bundled")
		elseif valid and ScriptApprovalMatches(lastApprovedScriptEvents[eventName],eventName,eventData) then
			approvedScriptEvents[eventName] = ScriptApprovalRecord(
				eventName,eventData,lastApprovedScriptEvents[eventName].ApprovedBy)
		end
	end
end

local function IsScriptEventApproved(eventName,eventData)
	if not scriptApprovalsInitialized then InitializeScriptEventApprovals() end
	eventData = eventData or (ItemRackEvents and ItemRackEvents[eventName])
	local valid,reason = ValidateScriptEvent(eventName,eventData)
	if not valid then return false,reason end
	if IsBundledScriptEvent(eventName,eventData) then return true,"bundled" end
	if ScriptApprovalMatches(approvedScriptEvents[eventName],eventName,eventData) then
		return true,approvedScriptEvents[eventName].ApprovedBy
	end
	local stored = ItemRackUser and ItemRackUser.Events
		and ItemRackUser.Events.ScriptApprovals
		and ItemRackUser.Events.ScriptApprovals[eventName]
	if stored then return false,"script changed after approval" end
	return false,"player approval required"
end

local function ForgetScriptEventApproval(eventName)
	if eventName == nil then return end
	approvedScriptEvents[eventName] = nil
	lastApprovedScriptEvents[eventName] = nil
	local stored = ItemRackUser and ItemRackUser.Events and ItemRackUser.Events.ScriptApprovals
	if type(stored) == "table" then stored[eventName] = nil end
end

local function SafeScriptEventLabel(value)
	value = tostring(value or ""):gsub("[%c]"," "):gsub("|","||")
	if #value > 80 then value = value:sub(1,77).."..." end
	return value
end

local function BlockScriptEvent(eventName,reason,quiet)
	local enabled = ItemRackUser and ItemRackUser.Events and ItemRackUser.Events.Enabled
	if type(enabled) == "table" and eventName ~= nil then enabled[eventName] = nil end
	ItemRack.BlockedScriptEvents = ItemRack.BlockedScriptEvents or {}
	local blockedKey = eventName == nil and "<nil>" or eventName
	local firstNotice = not ItemRack.BlockedScriptEvents[blockedKey]
	ItemRack.BlockedScriptEvents[blockedKey] = reason or "player approval required"
	if not quiet and firstNotice then
		ItemRack.Print("Blocked script event \""..SafeScriptEventLabel(eventName).."\": "..tostring(reason)..". Review and enable it in ItemRack Events to approve it.")
	end
end

local function QuarantineUnapprovedScriptEvents(quiet)
	local enabled = ItemRackUser and ItemRackUser.Events and ItemRackUser.Events.Enabled
	if type(enabled) ~= "table" then return 0 end
	local blocked = 0
	for eventName in pairs(enabled) do
		local eventData = ItemRackEvents and ItemRackEvents[eventName]
		if type(eventData) == "table" and eventData.Type == "Script" then
			local approved,reason = IsScriptEventApproved(eventName,eventData)
			if not approved then
				BlockScriptEvent(eventName,reason,quiet)
				blocked = blocked + 1
			end
		end
	end
	return blocked
end

local function CompileScriptEvent(eventData)
	return loadstring(scriptEventPrelude..eventData.Script)
end

local function ApproveScriptEvent(eventName,eventData,approvedBy,enableAfterApproval)
	local valid,reason = ValidateScriptEvent(eventName,eventData)
	if not valid then return false,reason end
	local method,compileErr = CompileScriptEvent(eventData)
	if not method then
		ItemRack.Debug("Events", "Approval refused for invalid script '"..tostring(eventName).."': "..tostring(compileErr))
		return false,"script has a syntax error"
	end
	local store = EnsureScriptApprovalStore()
	if not store then return false,"approval storage is unavailable" end
	local record = ScriptApprovalRecord(eventName,eventData,approvedBy)
	store[eventName] = ScriptApprovalRecord(eventName,eventData,approvedBy)
	lastApprovedScriptEvents[eventName] = ScriptApprovalRecord(eventName,eventData,approvedBy)
	approvedScriptEvents[eventName] = record
	ItemRack.BlockedScriptEvents = ItemRack.BlockedScriptEvents or {}
	ItemRack.BlockedScriptEvents[eventName] = nil
	if enableAfterApproval then
		ItemRackUser.Events.Enabled[eventName] = true
		ItemRackUser.EnableEvents = "ON"
	end
	return true,approvedBy
end

local function DiscardUnapprovedScriptEvent(eventName,reason,quiet)
	local enabled = ItemRackUser and ItemRackUser.Events and ItemRackUser.Events.Enabled
	if type(enabled) == "table" and eventName ~= nil then enabled[eventName] = nil end
	local fallback = lastApprovedScriptEvents[eventName] or bundledScriptEvents[eventName]
	if fallback and ValidateScriptEvent(eventName,fallback) then
		ItemRackEvents[eventName] = {
			Type = "Script",
			Trigger = fallback.Trigger,
			Script = fallback.Script,
		}
		local approvedBy = fallback.ApprovedBy or "bundled"
		approvedScriptEvents[eventName] = ScriptApprovalRecord(eventName,ItemRackEvents[eventName],approvedBy)
		if approvedBy ~= "bundled" then
			local store = EnsureScriptApprovalStore()
			if store then store[eventName] = ScriptApprovalRecord(eventName,ItemRackEvents[eventName],approvedBy) end
		end
		if not quiet then
			ItemRack.Print("Rejected unapproved changes to script event \""..SafeScriptEventLabel(eventName).."\" and restored its last approved version disabled.")
		end
		return "restored"
	end
	if ItemRackEvents and eventName ~= nil then ItemRackEvents[eventName] = nil end
	if eventName ~= nil and ItemRackUser and ItemRackUser.Events and ItemRackUser.Events.Set then
		ItemRackUser.Events.Set[eventName] = nil
	end
	ForgetScriptEventApproval(eventName)
	if not quiet then
		ItemRack.Print("Rejected and removed script event \""..SafeScriptEventLabel(eventName).."\": "..tostring(reason)..".")
	end
	return "removed"
end

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

-- Capture packaged Script definitions in a private table while this file is
-- loading. A later write to the public ItemRack.DefaultEvents table must not be
-- able to manufacture bundled trust for injected code.
for eventName,eventData in pairs(ItemRack.DefaultEvents) do
	if eventData.Type == "Script" then
		bundledScriptEvents[eventName] = {
			Type = "Script",
			Trigger = eventData.Trigger,
			Script = eventData.Script,
		}
	end
end

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
	-- Capture legacy Active flags and restore trails before LoadEvents refreshes
	-- default definitions and can overwrite their transient SavedVariable fields.
	if ItemRackUser.EventStateMigrationVersion == nil and CaptureLegacyEventState then
		CaptureLegacyEventState()
	end
	ItemRack.LoadEvents()
	ItemRack.MigrateDefaultScriptEvents()
	InitializeScriptEventApprovals()
	local blockedScripts = QuarantineUnapprovedScriptEvents(true)
	if blockedScripts > 0 then
		ItemRack.Print("Blocked "..blockedScripts.." unapproved script event(s). Review and enable them in ItemRack Events before they can run.")
	end
	-- Deferred Script triggers are runtime-only. Never carry a one-shot game
	-- event across a reload or a fresh event-system initialization.
	ItemRack.DeferredScriptEvents = {}

	ItemRack.CreateTimer("EventsBuffTimer",ItemRack.ProcessBuffEvent,.15)
	ItemRack.CreateTimer("EventsZoneTimer",ItemRack.ProcessZoneEvent,.16)
	ItemRack.CreateTimer("CheckForMountedEvents",ItemRack.CheckForMountedEvents,.5,1)
	ItemRack.CreateTimer("SpecChangeTimer",ItemRack.ProcessSpecializationEvent,0.5,1)
	ItemRack.CreateTimer("MovementPollingTimer",ItemRack.PollMovement,.2,1)
	
	-- EventState is persistent logical ownership. EventStack remains a derived
	-- compatibility projection for older UI/debug consumers.
	local eventState = ItemRack.EnsureEventFrameState()
	ItemRack.ScriptEventSets = {}
	ItemRack.ScriptEventDisableSound = {}
	ItemRack.ScriptEventGenerations = {}
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

	ItemRack.RefreshEventStackProjection()

	-- Legacy manual-set history may still be useful after a reload, so preserve it.
	-- Only remove references that can never be valid; automatic event ownership is
	-- restored exclusively from EventState above, never inferred from old/oldset.
	for setname, setData in pairs(ItemRackUser.Sets) do
		if setData.oldset == setname or (setData.oldset and not ItemRackUser.Sets[setData.oldset]) then
			setData.oldset = nil
		end
	end

	-- Rehydrate Active as a compatibility/UI projection from canonical frames.
	-- Never reconstruct ownership merely because currently worn gear matches a
	-- configured set; that gear may have been selected manually.
	local enabled = ItemRackUser.Events.Enabled
	local getSpec = GetActiveTalentGroup or (C_Talent and C_Talent.GetActiveTalentGroup)
	local currentSpec = getSpec and getSpec()
	ItemRack.LastLastSpec = (currentSpec and currentSpec > 0) and currentSpec or nil
	local orphaned = {}
	for _,frameId in ipairs(eventState.order) do
		local frame = eventState.frames[frameId]
		local eventData = frame and ItemRackEvents[frame.eventName]
		if eventData and enabled[frame.eventName] and eventData.Type ~= "Script" then
			eventData.Active = true
			ItemRack.EventGenerations = ItemRack.EventGenerations or {}
			ItemRack.EventGenerations[frame.eventName] = frame.eventGeneration or 0
		else
			table.insert(orphaned,{ name=frame and frame.eventName, generation=frame and frame.eventGeneration })
		end
	end
	for _,orphan in ipairs(orphaned) do
		if orphan.name then
			local result = ItemRack.EventFrames.Pop(eventState,orphan.name,orphan.generation)
			ItemRack.QueueEventFrameTargets(result)
		end
	end
	ItemRack.RefreshEventStackProjection()

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
	QuarantineUnapprovedScriptEvents(false)
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
				local approved = IsScriptEventApproved(eventName,eventData)
				if approved and not frame:IsEventRegistered(eventData.Trigger) then
					local ok,registerErr = pcall(frame.RegisterEvent,frame,eventData.Trigger)
					if not ok then
						BlockScriptEvent(eventName,"invalid or unavailable game-event trigger",false)
						ItemRack.Debug("Events", "Failed to register Script trigger:", eventName, registerErr)
					end
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

-- Public helpers bridge the load-on-demand options UI to the private runtime
-- approval snapshot. Registration and execution still perform their own exact
-- content checks immediately before accepting a Script event.
function ItemRack.IsScriptEventApproved(eventName)
	return IsScriptEventApproved(eventName)
end

function ItemRack.ForgetScriptEventApproval(eventName)
	ForgetScriptEventApproval(eventName)
end

function ItemRack.ReconcileScriptEventApprovals()
	return QuarantineUnapprovedScriptEvents(false)
end

function ItemRack.ApproveScriptEventFromInterface(eventName)
	local eventData = ItemRackEvents and ItemRackEvents[eventName]
	local approved,reason = ApproveScriptEvent(eventName,eventData,"interface",true)
	if not approved then
		DiscardUnapprovedScriptEvent(eventName,reason,false)
		return false,reason
	end
	return true,"interface"
end

function ItemRack.RemoveUnapprovedScriptEvents()
	local candidates = {}
	for eventName,eventData in pairs(ItemRackEvents or {}) do
		if type(eventData) == "table" and eventData.Type == "Script"
		and not IsScriptEventApproved(eventName,eventData) then
			table.insert(candidates,eventName)
		end
	end
	for _,eventName in ipairs(candidates) do
		DiscardUnapprovedScriptEvent(eventName,"no player approval was recorded",true)
	end
	local stored = ItemRackUser and ItemRackUser.Events and ItemRackUser.Events.ScriptApprovals
	if type(stored) == "table" then
		for eventName in pairs(stored) do
			local eventData = ItemRackEvents and ItemRackEvents[eventName]
			if type(eventData) ~= "table" or eventData.Type ~= "Script" then
				ForgetScriptEventApproval(eventName)
			end
		end
	end
	return #candidates
end

function ItemRack.RequestScriptEventApproval(eventName,enableAfterApproval)
	local eventData = ItemRackEvents and ItemRackEvents[eventName]
	local valid,reason = ValidateScriptEvent(eventName,eventData)
	if not valid then
		DiscardUnapprovedScriptEvent(eventName,reason,false)
		return false,reason
	end
	local approved,approvalSource = IsScriptEventApproved(eventName,eventData)
	if approved then
		if enableAfterApproval then
			ItemRackUser.Events.Enabled[eventName] = true
			ItemRackUser.EnableEvents = "ON"
			ItemRack.RegisterEvents()
			if ItemRackOpt and ItemRackOpt.PopulateEventList then ItemRackOpt.PopulateEventList() end
		end
		return true,approvalSource
	end
	if pendingScriptApproval then
		return false,"another script approval is already pending"
	end

	local pending = ScriptApprovalRecord(eventName,eventData,"prompt")
	local method,compileErr = CompileScriptEvent(eventData)
	if not method then
		DiscardUnapprovedScriptEvent(eventName,"script has a syntax error",false)
		ItemRack.Debug("Events", "Approval refused for invalid script '"..tostring(eventName).."': "..tostring(compileErr))
		return false,"script has a syntax error"
	end
	pendingScriptApproval = pending

	StaticPopupDialogs["ITEMRACK_APPROVE_SCRIPT_EVENT"] = {
		text = "%s",
		button1 = enableAfterApproval and "Approve & Enable" or "Approve",
		button2 = "Reject",
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
		OnAccept = function()
			if pendingScriptApproval ~= pending then return end
			pendingScriptApproval = nil
			local current = ItemRackEvents and ItemRackEvents[eventName]
			if not ScriptApprovalMatches(pending,eventName,current) then
				DiscardUnapprovedScriptEvent(eventName,"script changed while approval was open",false)
				return
			end
			local accepted,acceptReason = ApproveScriptEvent(eventName,current,"prompt",enableAfterApproval)
			if not accepted then
				DiscardUnapprovedScriptEvent(eventName,acceptReason,false)
				return
			end
			ItemRack.Print("Approved script event \""..SafeScriptEventLabel(eventName).."\" through the confirmation prompt.")
			ItemRack.RegisterEvents()
			if ItemRackOpt and ItemRackOpt.PopulateEventList then ItemRackOpt.PopulateEventList() end
		end,
		OnCancel = function()
			if pendingScriptApproval ~= pending then return end
			pendingScriptApproval = nil
			DiscardUnapprovedScriptEvent(eventName,"player rejected the approval prompt",false)
			if ItemRackOpt and ItemRackOpt.PopulateEventList then ItemRackOpt.PopulateEventList() end
		end,
	}
	local prompt = "ItemRack script events execute arbitrary Lua with addon-level access. Only approve code you wrote or reviewed.\n\nEvent: "
		..SafeScriptEventLabel(eventName).."\nTrigger: "..SafeScriptEventLabel(eventData.Trigger)
		.."\n\nApprove this exact trigger and script? Any later change will disable it again. Rejecting removes a new event or restores its last approved version."
	local popup = StaticPopup_Show("ITEMRACK_APPROVE_SCRIPT_EVENT",prompt)
	if not popup then
		pendingScriptApproval = nil
		DiscardUnapprovedScriptEvent(eventName,"approval prompt could not be shown",false)
		return false,"approval prompt could not be shown"
	end
	return false,"approval pending"
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

	local state = ItemRack.EnsureEventFrameState()
	if state.byEvent[eventName] then
		ItemRack.PopEvent(eventName)
	elseif wasActive then
		ItemRack.Debug("Events", "SpinDownEvent found no owned frame; no restore is permitted:", eventName)
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
	-- Script triggers describe a moment in time. If the user disables events
	-- while automatic swaps are suspended, do not replay those moments when
	-- the event system is enabled again later.
	ItemRack.DeferredScriptEvents = {}
	local stack = {}
	for _,eventName in ipairs(ItemRack.RefreshEventStackProjection()) do
		table.insert(stack,eventName)
	end
	ItemRack.BeginEventFrameBatch()
	for i=#stack,1,-1 do
		local eventName = stack[i]
		local eventData = ItemRackEvents and ItemRackEvents[eventName]
		if eventData then
			eventData.Active = nil
			eventData.LastZoneMatched = nil
			eventData.LastZoneSignature = nil
			eventData.ManualOverride = nil
		end
		ItemRack.PopEvent(eventName)
	end
	ItemRack.EndEventFrameBatch()
	if ItemRackEvents then
		for eventName, eventData in pairs(ItemRackEvents) do
			if eventData.Active then
				eventData.Active = nil
				eventData.LastZoneMatched = nil
				eventData.LastZoneSignature = nil
				eventData.ManualOverride = nil
				-- No frame means no ownership and therefore no permitted restore.
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

local function CopyTable(value,seen)
	if type(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local copy = {}
	seen[value] = copy
	for key,item in pairs(value) do
		if type(item) == "table" then
			copy[key] = CopyTable(item,seen)
		else
			copy[key] = item
		end
	end
	return copy
end

local EVENT_STATE_MIGRATION_VERSION = 1

CaptureLegacyEventState = function()
	local backup = ItemRackUser.LegacyEventStateBackup
	if type(backup) ~= "table" then
		if backup ~= nil then
			-- Keep an opaque damaged backup recoverable, but do not let it block a
			-- new structured snapshot of the legacy event evidence.
			ItemRackUser.UnknownLegacyEventStateBackup = CopyTable(backup)
		end
		backup = {}
	end
	if backup.eventStack == nil then backup.eventStack = CopyTable(ItemRackUser.EventStack or {}) end
	if type(backup.eventStack) ~= "table" then
		backup.invalidEventStack = CopyTable(backup.eventStack)
		backup.eventStack = {}
	end
	if backup.capturedFrom == nil then backup.capturedFrom = ItemRack.BuildID end
	if backup.activeEvents == nil then
		backup.activeEvents = {}
		for eventName,eventData in pairs(ItemRackEvents or {}) do
			if type(eventData) == "table" and eventData.Active then
				backup.activeEvents[eventName] = true
			end
		end
	end
	if type(backup.activeEvents) ~= "table" then
		backup.invalidActiveEvents = CopyTable(backup.activeEvents)
		backup.activeEvents = {}
	end
	if backup.eventSets == nil then
		backup.eventSets = CopyTable(ItemRackUser.Events and ItemRackUser.Events.Set or {})
	end
	if type(backup.eventSets) ~= "table" then
		backup.invalidEventSets = CopyTable(backup.eventSets)
		backup.eventSets = {}
	end
	if backup.events == nil then
		backup.events = {}
		for eventName,eventData in pairs(ItemRackEvents or {}) do
			if type(eventData) == "table" then
				backup.events[eventName] = {
					Type=eventData.Type,
					Unequip=eventData.Unequip,
				}
			end
		end
	end
	if type(backup.events) ~= "table" then
		backup.invalidEvents = CopyTable(backup.events)
		backup.events = {}
	end
	if backup.sets == nil then
		backup.sets = {}
		local referenced = {}
		for _,eventName in pairs(backup.eventStack or {}) do
			local setName = backup.eventSets[eventName]
			if setName then referenced[setName] = true end
		end
		for eventName in pairs(backup.activeEvents or {}) do
			local setName = backup.eventSets[eventName]
			if setName then referenced[setName] = true end
		end
		local added = true
		while added do
			added = false
			for setName in pairs(referenced) do
				local set = ItemRackUser.Sets and ItemRackUser.Sets[setName]
				if type(set) == "table" and set.oldset and not referenced[set.oldset] then
					referenced[set.oldset] = true
					added = true
				end
			end
		end
		for setName in pairs(referenced) do
			local set = ItemRackUser.Sets and ItemRackUser.Sets[setName]
			if type(set) == "table" then
				backup.sets[setName] = {
					equip=CopyTable(set.equip or {}),
					old=CopyTable(set.old or {}),
					oldset=set.oldset,
				}
			end
		end
	end
	if type(backup.sets) ~= "table" then
		backup.invalidSets = CopyTable(backup.sets)
		backup.sets = {}
	end
	ItemRackUser.LegacyEventStateBackup = backup
	return backup
end

local function CaptureReliableEquipment()
	local observed = {}
	if not ItemRack.GetEquippedSlotState then return observed end
	for slot=0,19 do
		local ok,state,id = pcall(ItemRack.GetEquippedSlotState,slot)
		if ok and state == "resolved" then
			observed[slot] = id
		elseif ok and state == "empty" then
			observed[slot] = 0
		end
	end
	return observed
end

function ItemRack.EnsureEventFrameState()
	if ItemRack.EventFrames.IsState(ItemRackUser.EventState)
	and ItemRackUser.EventStateMigrationVersion == EVENT_STATE_MIGRATION_VERSION then
		ItemRackUser.EventStack = ItemRack.EventFrames.ProjectStack(ItemRackUser.EventState)
		return ItemRackUser.EventState
	end
	if type(ItemRackUser.EventState) == "table"
	and type(ItemRackUser.EventState.schema) == "number"
	and ItemRackUser.EventState.schema > 1 then
		ItemRackUser.UnknownEventStateBackup = CopyTable(ItemRackUser.EventState)
		ItemRack.EventStateSchemaUnsupported = true
		ItemRack.UnsupportedEventState = ItemRack.UnsupportedEventState
			or ItemRack.EventFrames.NewState()
		ItemRackUser.EventStack = {}
		return ItemRack.UnsupportedEventState
	end

	local existingState = ItemRackUser.EventState
	local backup = CaptureLegacyEventState()
	if ItemRack.EventFrames.IsState(existingState) and #existingState.order > 0 then
		-- Canonical frames created by an earlier development build are already
		-- more authoritative than legacy set history; adopt them without replay.
		ItemRackUser.EventStateMigrationVersion = EVENT_STATE_MIGRATION_VERSION
		ItemRackUser.EventStateMigrationReport = { source="existing_canonical" }
		ItemRackUser.EventStack = ItemRack.EventFrames.ProjectStack(existingState)
		return existingState
	elseif existingState ~= nil and not ItemRack.EventFrames.IsState(existingState) then
		ItemRackUser.UnknownEventStateBackup = CopyTable(ItemRackUser.EventState)
	end

	local state,report = ItemRack.EventFrames.MigrateLegacy({
		eventStack=backup.eventStack,
		activeEvents=backup.activeEvents,
		eventSets=backup.eventSets,
		events=backup.events,
		enabled=ItemRackUser.Events and ItemRackUser.Events.Enabled,
		sets=backup.sets,
		observed=CaptureReliableEquipment(),
		matches=function(target,current)
			if ItemRack.MatchesStoredItemID then
				return ItemRack.MatchesStoredItemID(target,current)
			end
			return target == current
		end,
	})
	ItemRackUser.EventState = state
	ItemRackUser.EventStateMigrationVersion = EVENT_STATE_MIGRATION_VERSION
	ItemRackUser.EventStateMigrationReport = report
	ItemRackUser.EventStack = ItemRack.EventFrames.ProjectStack(state)
	ItemRack.Debug("Events", "Legacy event-state migration:", report.source,
		report.framesMigrated, "frames", report.slotsMigrated, "slots",
		report.slotsReleasedForMismatch, "mismatched slots released")
	return ItemRackUser.EventState
end

function ItemRack.RefreshEventStackProjection()
	local state = ItemRack.EnsureEventFrameState()
	ItemRackUser.EventStack = ItemRack.EventFrames.ProjectStack(state)
	return ItemRackUser.EventStack
end

function ItemRack.GetTopEventFrame()
	local state = ItemRack.EnsureEventFrameState()
	local frameId = state.order[#state.order]
	return frameId and state.frames[frameId]
end

function ItemRack.ReleaseEventSlotsForManualChange(slots)
	local state = ItemRack.EnsureEventFrameState()
	if not ItemRack.EventFrames.ReleaseSlots(state,slots) then return false end
	for slot in pairs(slots or {}) do
		if ItemRack.EventFramePendingTargets then
			ItemRack.EventFramePendingTargets[slot] = nil
		end
	end
	ItemRack.RefreshEventStackProjection()
	ItemRack.Debug("Events", "Manual equipment intent released automatic slot ownership at revision:", state.revision)
	return true
end

function ItemRack.QueueEventFrameTargets(result, disableSound)
	if not result or type(result.targets) ~= "table" then return end
	local state = ItemRack.EnsureEventFrameState()
	local pendingSet = ItemRack.PendingQueueEquipSet
	if pendingSet and pendingSet.eventFrameRevision
	and pendingSet.eventFrameRevision ~= state.revision
	and ItemRack.CancelPendingQueueEquipSet then
		ItemRack.CancelPendingQueueEquipSet(pendingSet,"event_frame_revision_changed")
	end
	ItemRack.EventFramePendingTargets = ItemRack.EventFramePendingTargets or {}
	for slot,target in pairs(result.targets) do
		ItemRack.EventFramePendingTargets[slot] = target
	end
	ItemRack.EventFramePendingRevision = state.revision
	if disableSound ~= nil then ItemRack.EventFramePendingDisableSound = disableSound end
	if not ItemRack.EventFrameBatchDepth or ItemRack.EventFrameBatchDepth == 0 then
		ItemRack.TryReconcileEventFrames()
	end
end

function ItemRack.BeginEventFrameBatch()
	ItemRack.EventFrameBatchDepth = (ItemRack.EventFrameBatchDepth or 0) + 1
end

function ItemRack.EndEventFrameBatch()
	ItemRack.EventFrameBatchDepth = math.max((ItemRack.EventFrameBatchDepth or 1) - 1,0)
	if ItemRack.EventFrameBatchDepth == 0 then ItemRack.TryReconcileEventFrames() end
end

function ItemRack.EventFramePlanFinished(setname, succeeded, reason)
	local plan = ItemRack.EventFramePlans and ItemRack.EventFramePlans[setname]
	if not plan then return end
	ItemRack.EventFramePlans[setname] = nil
	ItemRackUser.Sets[setname] = nil
	ItemRack.EventFramePlanActive = nil
	local state = ItemRack.EnsureEventFrameState()
	if not succeeded and plan.revision == state.revision then
		-- Retain the latest desired targets for a later inventory/readiness event;
		-- do not spin on a terminal missing/full-bag condition.
		ItemRack.EventFramePendingTargets = ItemRack.EventFramePendingTargets or {}
		for slot,target in pairs(plan.targets) do
			ItemRack.EventFramePendingTargets[slot] = target
		end
		ItemRack.EventFramePlanBlockedReason = reason or "plan_failed"
	else
		ItemRack.EventFramePlanBlockedReason = nil
	end
	local top = ItemRack.GetTopEventFrame()
	if succeeded then
		ItemRackUser.CurrentSet = top and top.setName or nil
	end
	ItemRack.RefreshEventStackProjection()
	if next(ItemRack.EventFramePendingTargets or {}) and (succeeded or plan.revision ~= state.revision) then
		C_Timer.After(0,function() ItemRack.TryReconcileEventFrames(true) end)
	elseif ItemRack.UpdateCurrentSet then
		C_Timer.After(0,ItemRack.UpdateCurrentSet)
	end
end

function ItemRack.TryReconcileEventFrames(force)
	local pending = ItemRack.EventFramePendingTargets
	if not pending or not next(pending) or ItemRack.EventFramePlanActive then return false end
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then return false end
	if ItemRack.NowCasting or InCombatLockdown() or ItemRack.IsPlayerReallyDead()
	or ItemRack.SetSwapping or ItemRack.HasActiveEquipmentTransaction() or ItemRack.AnythingLocked() then
		return false
	end
	if ItemRack.EventFramePlanBlockedReason and not force then return false end

	local state = ItemRack.EnsureEventFrameState()
	local revision = state.revision
	local setname = "~EventFrame:"..tostring(revision)
	local targets = CopyTable(pending)
	ItemRack.EventFramePendingTargets = {}
	ItemRack.EventFramePendingRevision = nil
	ItemRack.EventFramePlans = ItemRack.EventFramePlans or {}
	ItemRack.EventFramePlans[setname] = { revision=revision, targets=targets }
	ItemRack.EventFramePlanActive = setname
	ItemRackUser.Sets[setname] = { equip=CopyTable(targets) }
	local previousEventEquipment = ItemRack.IsEventEquipment
	ItemRack.IsEventEquipment = true
	ItemRack.EquipSet(setname,ItemRack.EventFramePendingDisableSound)
	ItemRack.IsEventEquipment = previousEventEquipment
	return true
end

function ItemRack.RetryBlockedEventFrames()
	local blocked = ItemRack.EventFrameBlockedActivations or {}
	local names = {}
	for eventName in pairs(blocked) do table.insert(names,eventName) end
	table.sort(names)
	local retried = false
	ItemRack.BeginEventFrameBatch()
	for _,eventName in ipairs(names) do
		local pending = blocked[eventName]
		local state = ItemRack.EnsureEventFrameState()
		local frameId = state.byEvent[eventName]
		local frame = frameId and state.frames[frameId]
		if not frame or frame.eventGeneration ~= pending.generation then
			blocked[eventName] = nil
		elseif ItemRackEvents[eventName] and ItemRackEvents[eventName].Active
		and ItemRackUser.Sets[pending.setname] then
			local ready = ItemRack.PreflightSetSwap(pending.setname)
			if ready then
				ItemRack.PopEvent(eventName,pending.generation)
				blocked[eventName] = nil
				ItemRack.PushEvent(eventName)
				retried = true
			end
		end
	end
	ItemRack.EndEventFrameBatch()
	if ItemRack.EventFramePlanBlockedReason then
		ItemRack.EventFramePlanBlockedReason = nil
		ItemRack.TryReconcileEventFrames(true)
	end
	return retried
end

function ItemRack.ClearScriptEventState(eventName, generation)
	local currentGeneration = ItemRack.ScriptEventGenerations and ItemRack.ScriptEventGenerations[eventName]
	if generation ~= nil and currentGeneration ~= nil and generation ~= currentGeneration then
		return false
	end
	if ItemRack.ScriptEventSets then
		ItemRack.ScriptEventSets[eventName] = nil
	end
	if ItemRack.ScriptEventDisableSound then
		ItemRack.ScriptEventDisableSound[eventName] = nil
	end
	if ItemRack.ScriptEventGenerations then
		ItemRack.ScriptEventGenerations[eventName] = nil
	end
	return true
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
	local result = ItemRack.PushEvent(eventName)
	if result and result.frameId then
		local frame = ItemRackUser.EventState.frames[result.frameId]
		ItemRack.ScriptEventGenerations = ItemRack.ScriptEventGenerations or {}
		ItemRack.ScriptEventGenerations[eventName] = frame and frame.eventGeneration
		return frame and frame.eventGeneration
	end
end

function ItemRack.ScriptEventUnequip(eventName, disableSound, expectedGeneration)
	if not eventName then
		return
	end
	ItemRack.ScriptEventDisableSound = ItemRack.ScriptEventDisableSound or {}
	if disableSound ~= nil then
		ItemRack.ScriptEventDisableSound[eventName] = disableSound
	end
	return ItemRack.PopEvent(eventName,expectedGeneration)
end

function ItemRack.PushEvent(eventName, belowEventName)
	if ItemRackUser.EnableEvents == "OFF" then return end
	ItemRack.Debug("Events", "PushEvent: "..(eventName or "nil"))
	if not eventName then return end
	local state = ItemRack.EnsureEventFrameState()
	local setname = ItemRack.GetEventSet(eventName)
	local existingId = state.byEvent[eventName]
	local existing = existingId and state.frames[existingId]
	if existing and existing.setName == setname then
		ItemRack.RefreshEventStackProjection()
		return { changed=false, frameId=existingId, targets={} }
	end
	if existing then
		local removed = ItemRack.EventFrames.Pop(state,eventName,existing.eventGeneration)
		ItemRack.QueueEventFrameTargets(removed,ItemRack.GetEventDisableSound(eventName))
	end

	ItemRack.EventGenerations = ItemRack.EventGenerations or {}
	local generation = math.max(ItemRack.EventGenerations[eventName] or 0,
		existing and existing.eventGeneration or 0) + 1
	ItemRack.EventGenerations[eventName] = generation
	local slots, observed = {}, {}
	local blockedReason
	if setname and ItemRackUser.Sets[setname] then
		local ready, reason = ItemRack.PreflightSetSwap(setname)
		if ready then
			slots = ItemRack.EventFrames.SnapshotSet(ItemRackUser.Sets[setname])
			for slot in pairs(slots) do observed[slot] = ItemRack.GetID(slot) end
		else
			blockedReason = reason
			ItemRack.EventFrameBlockedActivations = ItemRack.EventFrameBlockedActivations or {}
			ItemRack.EventFrameBlockedActivations[eventName] = {
				generation=generation, setname=setname, reason=reason,
			}
			ItemRack.Debug("Events", "Event frame activation deferred by preflight:", eventName, reason)
		end
	end
	local eventData = ItemRackEvents and ItemRackEvents[eventName]
	local beforeFrameId = belowEventName and state.byEvent[belowEventName]
	local result = ItemRack.EventFrames.Activate(state,{
		eventName=eventName,
		eventGeneration=generation,
		setName=setname,
		origin=eventData and eventData.Type,
		restoreOnExit=eventData and eventData.Unequip and true or false,
		beforeFrameId=beforeFrameId,
		slots=slots,
		observed=observed,
	})
	if blockedReason and result.frameId and state.frames[result.frameId] then
		state.frames[result.frameId].status = "blocked"
		state.frames[result.frameId].blockedReason = blockedReason
	end
	ItemRack.RefreshEventStackProjection()
	ItemRack.QueueEventFrameTargets(result,ItemRack.GetEventDisableSound(eventName))
	return result
end

function ItemRack.PopEvent(eventName, expectedGeneration)
	local disableSound = ItemRack.GetEventDisableSound(eventName)
	ItemRack.Debug("Events", "PopEvent: "..tostring(eventName))
	if not eventName then return { removed=false, targets={} } end
	local state = ItemRack.EnsureEventFrameState()
	local frameId = state.byEvent[eventName]
	local frame = frameId and state.frames[frameId]
	local nonRestoringSlots = {}
	if frame and frame.restoreOnExit == false then
		for slot,owned in pairs(frame.slots or {}) do
			nonRestoringSlots[slot] = owned.target
		end
	end
	local generation = expectedGeneration
	if generation == nil and frame then generation = frame.eventGeneration end
	local result = ItemRack.EventFrames.Pop(state,eventName,generation)
	if not result.removed then
		ItemRack.Debug("Events", "PopEvent ignored unowned or stale event:", eventName, result.reason or "")
		return result
	end
	if ItemRack.EventFrameBlockedActivations then
		ItemRack.EventFrameBlockedActivations[eventName] = nil
	end
	-- Unequip=false retains already-observed gear, but an activation that has
	-- not been submitted yet must not survive its owner. Replace only that
	-- owner's still-pending target with the remaining effective owner (if any).
	for slot,target in pairs(nonRestoringSlots) do
		if ItemRack.EventFramePendingTargets
		and ItemRack.EventFramePendingTargets[slot] == target then
			local effective = ItemRack.EventFrames.EffectiveTarget(state,slot)
			ItemRack.EventFramePendingTargets[slot] = effective
		end
	end
	ItemRack.RefreshEventStackProjection()
	ItemRack.QueueEventFrameTargets(result,disableSound)
	ItemRack.ClearScriptEventState(eventName,generation)
	return result
end

--[[ Event processing ]]

local deferredScriptEventLimit = 64

local function HasEnabledScriptTrigger(event)
	if not event or not ItemRackUser or ItemRackUser.EnableEvents == "OFF" then
		return false
	end
	local enabled = ItemRackUser.Events and ItemRackUser.Events.Enabled
	if not enabled then
		return false
	end
	for eventName in pairs(enabled) do
		local eventData = ItemRackEvents and ItemRackEvents[eventName]
		if eventData and eventData.Type == "Script" and eventData.Trigger == event then
			local approved,reason = IsScriptEventApproved(eventName,eventData)
			if approved then return true end
			BlockScriptEvent(eventName,reason,false)
		end
	end
	return false
end

local function CaptureScriptEventArguments(event,...)
	local a1,a2,a3,a4,a5,a6,a7,a8,a9,a10 = ...
	-- Compatibility for UNIT_SPELLCAST_* changes in 1.15.0+ / 10.0+.
	-- Resolve this while the event is being received so a deferred replay keeps
	-- the original cast rather than observing some later game state.
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
	-- COMBAT_LOG_EVENT_UNFILTERED has no useful callback arguments on modern
	-- clients. Capture its payload now: CombatLogGetCurrentEventInfo() would
	-- refer to a different combat-log record by the time a hold is released.
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		a1,a2,a3,a4,a5,a6,a7,a8,a9,a10 = CombatLogGetCurrentEventInfo()
	end
	return {
		[1]=a1, [2]=a2, [3]=a3, [4]=a4, [5]=a5,
		[6]=a6, [7]=a7, [8]=a8, [9]=a9, [10]=a10,
	}
end

local function ProcessScriptTriggers(event,args)
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents
	local a1,a2,a3,a4,a5 = args[1],args[2],args[3],args[4],args[5]
	local a6,a7,a8,a9,a10 = args[6],args[7],args[8],args[9],args[10]
	for eventName in pairs(enabled) do
		local eventData = events[eventName]
		if eventData and eventData.Type=="Script" and eventData.Trigger==event then
			local approved,reason = IsScriptEventApproved(eventName,eventData)
			if not approved then
				BlockScriptEvent(eventName,reason,false)
			else
				local method, compileErr = loadstring(scriptEventPrelude .. eventData.Script)
				if not method then
					BlockScriptEvent(eventName,"script has a syntax error",false)
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
end

local function QueueDeferredScriptEvent(event,...)
	if not HasEnabledScriptTrigger(event) then
		return false
	end
	local queue = ItemRack.DeferredScriptEvents
	if not queue then
		queue = {}
		ItemRack.DeferredScriptEvents = queue
	end
	if #queue >= deferredScriptEventLimit then
		table.remove(queue,1)
		ItemRack.Debug("Events", "Deferred Script event queue full; discarded oldest trigger")
	end
	table.insert(queue,{
		event = event,
		args = CaptureScriptEventArguments(event,...),
	})
	ItemRack.Debug("Events", "Queued Script trigger until automatic swaps resume:", event)
	return true
end

-- Called by RunAllEvents after transition/readiness holds have cleared. This
-- deliberately invokes only user Script triggers; Buff/Zone/Stance/Spec state
-- is already reevaluated by RunAllEvents and must not be processed twice.
function ItemRack.ReplayDeferredScriptEvents()
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		return 0
	end
	local queue = ItemRack.DeferredScriptEvents
	if not queue or #queue == 0 then
		return 0
	end
	ItemRack.DeferredScriptEvents = {}
	for i = 1, #queue do
		local pending = queue[i]
		ProcessScriptTriggers(pending.event,pending.args)
	end
	ItemRack.Debug("Events", "Replayed deferred Script triggers:", #queue)
	return #queue
end

function ItemRack.ProcessingFrameOnEvent(self,event,...)
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		QueueDeferredScriptEvent(event,...)
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
			end
		end
	end
	if HasEnabledScriptTrigger(event) then
		ProcessScriptTriggers(event,CaptureScriptEventArguments(event,...))
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
	if currentStance == nil then return end
	local state = ItemRack.EnsureEventFrameState()
	local names = {}
	for eventName in pairs(enabled) do
		local eventData = events[eventName]
		if eventData and eventData.Type=="Stance" then
			table.insert(names,eventName)
		end
	end
	table.sort(names)
	local _,instanceType = IsInInstance()
	local exits,entries = {},{}
	for _,eventName in ipairs(names) do
		local eventData = events[eventName]
		local excluded = eventData.NotInPVP and (instanceType=="arena" or instanceType=="pvp")
		local stance = not excluded and ItemRack.GetStanceNumber(eventData.Stance)
		local desired = stance ~= nil and stance == currentStance
		local ownsFrame = state.byEvent[eventName] ~= nil
		if desired and not ownsFrame then
			table.insert(entries,eventName)
			eventData.Active = nil
		elseif desired then
			eventData.Active = true
		elseif ownsFrame then
			table.insert(exits,eventName)
			eventData.Active = nil
		else
			eventData.Active = nil
		end
	end
	ItemRack.BeginEventFrameBatch()
	for _,eventName in ipairs(exits) do ItemRack.PopEvent(eventName) end
	for _,eventName in ipairs(entries) do
		ItemRack.PushEvent(eventName)
		events[eventName].Active = state.byEvent[eventName] and true or nil
	end
	ItemRack.EndEventFrameBatch()
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
	ItemRack.PopEvent(eventName)
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
	local state = ItemRack.EnsureEventFrameState()
	if state.byEvent[zoneEventName] then return end
	ItemRack.PushEvent(zoneEventName,mountEventName)
end

-- When the player remains mounted but the destination needs a different
-- underlying Zone set, unwind the old mount layer first. Zone and Buff processing
-- then serialize the destination Zone set followed by a fresh mount layer,
-- producing the correct Zone -> Mounted history without an oldset cycle.
local function prepareMountRebase(eventName)
	local eventData = eventName and ItemRackEvents[eventName]
	if eventData then
		eventData.Active = nil
		ItemRack.PopEvent(eventName)
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

local function ProcessZoneEventLegacy(reason)
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

-- Canonical Zone reducer. Logical frames make mount/zone rebasing a pure
-- insertion operation, so no visible mount set needs to be unequipped and
-- re-equipped merely to change an underlying Zone owner.
function ItemRack.ProcessZoneEvent(reason)
	if ItemRack.IsAutomaticSwapBlocked and ItemRack.IsAutomaticSwapBlocked() then
		ItemRack.Debug("Events", "ProcessZoneEvent deferred while automatic swaps are suspended:", reason or "")
		return false
	end
	local currentZone = GetRealZoneText()
	local currentSubZone = GetSubZoneText()
	local _,instanceType = IsInInstance()
	local _,_,_,_,_,_,_,instanceID = GetInstanceInfo()
	local signature = table.concat({
		tostring(instanceType or "none"), tostring(currentZone or ""),
		tostring(currentSubZone or ""), tostring(instanceID or ""),
	},"\031")
	local state = ItemRack.EnsureEventFrameState()
	local activeMountEvents = getActiveMountEvents()
	local baseMountEvent = activeMountEvents[#activeMountEvents]
	local names = {}
	for eventName in pairs(ItemRackUser.Events.Enabled) do
		local eventData = ItemRackEvents[eventName]
		if eventData and eventData.Type == "Zone" then table.insert(names,eventName) end
	end
	table.sort(names)

	local exits,entries = {},{}
	for _,eventName in ipairs(names) do
		local eventData = ItemRackEvents[eventName]
		local matched = getZoneMatch(eventData,currentZone,currentSubZone,instanceType)
		local ownsFrame = state.byEvent[eventName] ~= nil
		if matched then
			if not ownsFrame then table.insert(entries,eventName) end
			eventData.Active = true
			eventData.LastZoneMatched = matched
			if eventData.LastZoneSignature ~= signature then
				eventData.ManualOverride = nil
			end
			eventData.LastZoneSignature = signature
		elseif ownsFrame then
			table.insert(exits,eventName)
			eventData.Active = nil
			eventData.LastZoneMatched = nil
			eventData.LastZoneSignature = nil
			eventData.ManualOverride = nil
		else
			eventData.Active = nil
		end
	end

	-- Apply all logical removals before additions; the pending physical plan is
	-- coalesced by slot and therefore never exposes an intermediate mount unwind.
	ItemRack.BeginEventFrameBatch()
	for _,eventName in ipairs(exits) do ItemRack.PopEvent(eventName) end
	for _,eventName in ipairs(entries) do
		if baseMountEvent and ItemRackUser.EventState.byEvent[baseMountEvent] then
			ItemRack.PushEvent(eventName,baseMountEvent)
		else
			ItemRack.PushEvent(eventName)
		end
	end
	ItemRack.EndEventFrameBatch()
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
	
	-- Only proceed if the spec index has actually changed. A forced same-spec
	-- refresh may rebuild event ownership, but it must not consume an associated
	-- set request whose specialization cast is still in progress.
	local previousSpec = ItemRack.LastLastSpec
	if not force and previousSpec == currentSpec then return end
	local specChanged = previousSpec ~= currentSpec
	ItemRack.LastLastSpec = currentSpec

	local preserveRequestedSet
	local suppressDestinationDefaults
	local pendingSpecSet = ItemRack.PendingSpecSet
	if pendingSpecSet then
		local expired = pendingSpecSet.expiresAt and GetTime() > pendingSpecSet.expiresAt
		if specChanged and not expired and pendingSpecSet.spec == currentSpec
		and pendingSpecSet.cancelledByManualUnequip then
			suppressDestinationDefaults = true
			ItemRack.Debug("Events", "Suppressing specialization defaults after newer manual unequip")
		else
			local requestedSet = pendingSpecSet.latestManualSet or pendingSpecSet.setname
			local requestedSetExists = requestedSet and ItemRackUser.Sets[requestedSet]
			local requestStillCurrent = pendingSpecSet.latestManualSet ~= nil
				or ItemRackUser.CurrentSet == pendingSpecSet.setname
			if specChanged and not expired and requestedSetExists
			and pendingSpecSet.spec == currentSpec and requestStillCurrent then
				preserveRequestedSet = requestedSet
				ItemRack.Debug("Events", "Preserving associated set through spec change:", preserveRequestedSet)
			end
		end
		-- An actual spec transition consumes the request whether it reached the
		-- expected destination or the player changed course. Expiry is also final;
		-- a forced refresh at the unchanged source spec leaves the request intact.
		if expired or specChanged then ItemRack.PendingSpecSet = nil end
	end
	
	local state = ItemRack.EnsureEventFrameState()
	local names = {}
	for eventName in pairs(enabled) do
		local eventData = events[eventName]
		if eventData and eventData.Type=="Specialization" and eventData.Spec then
			table.insert(names,eventName)
		end
	end
	table.sort(names)
	local exits,entries = {},{}
	for _,eventName in ipairs(names) do
		local eventData = events[eventName]
		local setname = ItemRackUser.Events.Set[eventName]
		local matchesSpec = eventData.Spec == currentSpec
		local desired = matchesSpec and not suppressDestinationDefaults
			and (not preserveRequestedSet or setname == preserveRequestedSet)
		local ownsFrame = state.byEvent[eventName] ~= nil
		if desired and not ownsFrame then
			table.insert(entries,eventName)
			eventData.Active = nil
		elseif desired then
			eventData.Active = true
		elseif ownsFrame then
			table.insert(exits,eventName)
			eventData.Active = nil
		else
			eventData.Active = nil
		end
	end

	local retrySets = {}
	ItemRack.BeginEventFrameBatch()
	for _,eventName in ipairs(exits) do ItemRack.PopEvent(eventName) end
	for _,eventName in ipairs(entries) do
		local setname = ItemRackUser.Events.Set[eventName]
		if setname and ItemRackUser.Sets[setname] then
			ItemRack.PushEvent(eventName)
			events[eventName].Active = state.byEvent[eventName] and true or nil
			if events[eventName].Active then retrySets[setname] = true end
		else
			events[eventName].Active = nil
			ItemRack.Debug("Events", "Specialization event has no valid set mapping:", eventName, setname or "nil")
		end
	end
	ItemRack.EndEventFrameBatch()

	if preserveRequestedSet then
		local adopted = false
		for _,eventName in ipairs(names) do
			if events[eventName].Active and ItemRackUser.Events.Set[eventName] == preserveRequestedSet then
				adopted = true
				break
			end
		end
		ItemRack.Debug("Events", adopted and "Adopted requested set into specialization event:"
			or "Suppressed destination specialization defaults to preserve:", preserveRequestedSet)
		retrySets[preserveRequestedSet] = true
		if ItemRack.UpdateCurrentSet then ItemRack.UpdateCurrentSet() end
	end
	for setname in pairs(retrySets) do ItemRack.ScheduleDualWieldRetry(setname) end
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
		ItemRack.EquipItemByID(intendedOffhand, 17, false, nil, nil, "dual_wield_retry")
		
		-- Also retry mainhand if needed
		local currentMainhand = ItemRack.GetID(16)
		local intendedMainhand = set[16]
		if intendedMainhand and intendedMainhand ~= 0 and not ItemRack.MatchesStoredItemID(intendedMainhand, currentMainhand) then
			ItemRack.EquipItemByID(intendedMainhand, 16, false, nil, nil, "dual_wield_retry")
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

-- A single generation-bound debounce recomputes every OnMovement event. A
-- callback from an older movement epoch is a total no-op, so simultaneous
-- events cannot strand one another or pop after movement resumes.
local function ScheduleOnMovementRecheck(generation)
	if ItemRack.PendingOnMovementGeneration == generation then return end
	ItemRack.PendingOnMovementGeneration = generation
	C_Timer.After(0.5,function() ItemRack.ProcessOnMovementUnequip(generation) end)
end

function ItemRack.ProcessOnMovementUnequip(expectedGeneration)
	local pending = ItemRack.PendingOnMovementGeneration
	expectedGeneration = expectedGeneration or pending
	if not expectedGeneration or pending ~= expectedGeneration
	or ItemRack.OnMovementGeneration ~= expectedGeneration then return end
	if GetUnitSpeed("player") > 0 then
		ItemRack.PendingOnMovementGeneration = nil
		return
	end
	local zoneAge = ItemRack.LastZoneChangeTime and (GetTime() - ItemRack.LastZoneChangeTime)
	if zoneAge and zoneAge < 1 then
		C_Timer.After(math.max(1-zoneAge,0.05),function()
			ItemRack.ProcessOnMovementUnequip(expectedGeneration)
		end)
		return
	end
	ItemRack.PendingOnMovementGeneration = nil
	ItemRack.OnMovementDelayElapsedGeneration = expectedGeneration
	ItemRack.Debug("Events", "OnMovement debounce elapsed; reconciling generation:", expectedGeneration)
	ItemRack.ProcessBuffEvent()
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
	local mountReady = not currentlyMounted or (GetTime() - mountStateChangedAt) >= mountEquipDelay
	if currentlyMounted and not mountReady then
		scheduleMountEquipCheck()
	end
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents
	local state = ItemRack.EnsureEventFrameState()
	local speed = GetUnitSpeed("player") or 0
	local moving = speed > 0
	if ItemRack.LastOnMovementState == nil or ItemRack.LastOnMovementState ~= moving then
		ItemRack.LastOnMovementState = moving
		ItemRack.OnMovementGeneration = (ItemRack.OnMovementGeneration or 0) + 1
		ItemRack.OnMovementDelayElapsedGeneration = nil
		if moving then ItemRack.PendingOnMovementGeneration = nil end
	end
	local movementGeneration = ItemRack.OnMovementGeneration or 0
	local movementDelayElapsed = ItemRack.OnMovementDelayElapsedGeneration == movementGeneration
	local _,instanceType = IsInInstance()
	local names = {}
	for eventName in pairs(enabled) do
		local eventData = events[eventName]
		if eventData and eventData.Type=="Buff" then table.insert(names,eventName) end
	end
	table.sort(names)

	local exits,entries = {},{}
	local needsMovementDebounce = false
	for _,eventName in ipairs(names) do
		local eventData = events[eventName]
		local excluded = (eventData.NotInPVP and (instanceType=="arena" or instanceType=="pvp"))
			or (eventData.NotInPVE and (instanceType=="party" or instanceType=="raid"))
		local underlyingBuff
		if not excluded then
			if eventData.Anymount then
				underlyingBuff = currentlyMounted
			else
				underlyingBuff = eventData.Buff and AuraUtil.FindAuraByName(eventData.Buff,"player") and true or false
			end
		end
		local ownsFrame = state.byEvent[eventName] ~= nil
		local desired = underlyingBuff and true or false
		if desired and eventData.Anymount and not mountReady then
			-- Preserve an existing mount frame during stabilization, but do not
			-- create one until the client reports a stable mount state.
			desired = ownsFrame
		elseif desired and eventData.OnMovement then
			if moving then
				desired = true
			elseif eventData.OnMovementDelay == false or movementDelayElapsed then
				desired = false
			else
				desired = ownsFrame
				if ownsFrame then needsMovementDebounce = true end
			end
		end
		if eventData.OnMovement then
			ItemRack.Debug("Events", "ProcessBuffEvent checking", eventName,
				"moving:", moving, "underlying:", underlyingBuff and true or false,
				"owned:", ownsFrame, "desired:", desired)
		end
		if desired and not ownsFrame then
			table.insert(entries,eventName)
			eventData.Active = nil
		elseif desired then
			eventData.Active = true
		elseif ownsFrame then
			table.insert(exits,eventName)
			eventData.Active = nil
		else
			eventData.Active = nil
		end
	end

	ItemRack.BeginEventFrameBatch()
	for _,eventName in ipairs(exits) do ItemRack.PopEvent(eventName) end
	for _,eventName in ipairs(entries) do
		ItemRack.PushEvent(eventName)
		events[eventName].Active = state.byEvent[eventName] and true or nil
	end
	ItemRack.EndEventFrameBatch()
	if needsMovementDebounce then
		ScheduleOnMovementRecheck(movementGeneration)
	elseif ItemRack.PendingOnMovementGeneration == movementGeneration then
		ItemRack.PendingOnMovementGeneration = nil
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
