const fs = require('fs');
const { extractFunction, runLua } = require('./lib/lua_harness');

const reducer = fs.readFileSync('ItemRack/ItemRackEventState.lua', 'utf8');
const events = fs.readFileSync('ItemRack/ItemRackEvents.lua', 'utf8');
const equipSet = extractFunction('ItemRack/ItemRackEquip.lua', 'ItemRack.EquipSet');
const unequipSet = extractFunction('ItemRack/ItemRackEquip.lua', 'ItemRack.UnequipSet');

runLua(String.raw`
local now = 100
local movingSpeed = 0
local currentStance = 0
local currentSpec = 1
local mounted = false
local instanceType = nil
local auras = {}
local inventory = { [13]="Base13", [14]="Base14", [15]="Base15" }
local scheduled = {}

function IsMounted() return mounted end
function UnitOnTaxi() return false end
function GetTime() return now end
function InCombatLockdown() return false end
function GetShapeshiftForm() return currentStance end
function GetNumShapeshiftForms() return 2 end
function GetShapeshiftFormInfo(index)
  if index == 1 then return nil,"Form One" end
  if index == 2 then return nil,"Form Two" end
end
function GetActiveTalentGroup() return currentSpec end
function GetRealZoneText() return "" end
function GetSubZoneText() return "" end
function IsInInstance() return instanceType ~= nil,instanceType end
function GetInstanceInfo() return nil,nil,nil,nil,nil,nil,nil,nil end
function UnitClass() return "Shaman","SHAMAN" end
function GetUnitSpeed() return movingSpeed end
function CanDualWield() return false end
C_AddOns, C_Spell, C_Talent = nil,nil,nil
C_Timer = {
  After = function(delay, callback)
    table.insert(scheduled,{ delay=delay, callback=callback })
  end,
}
AuraUtil = {
  FindAuraByName = function(name)
    return auras[name] and name or nil
  end,
}

ItemRack = {
  BuildID = "ProcessorTest",
  Debug = function() end,
  Print = function() end,
  PreflightSetSwap = function() return true end,
  GetID = function(slot) return inventory[slot] or 0 end,
  IsAutomaticSwapBlocked = function() return false end,
  UpdateCurrentSet = function() end,
}
ItemRackSettings = { EventsVersion=20 }
ItemRackUser = { EnableEvents="ON", Events={ Enabled={}, Set={} }, Sets={}, EventStack={} }
ItemRackEvents = {}

${reducer}
${events}
${equipSet}
${unequipSet}

local checks = 0
local function check(value,message) assert(value,message); checks = checks + 1 end
local function count(tbl)
  local result = 0
  for _ in pairs(tbl or {}) do result = result + 1 end
  return result
end
local function runScheduled(index)
  local pending = table.remove(scheduled,index or 1)
  assert(pending,"expected a scheduled callback")
  pending.callback()
  return pending.delay
end
local function reset()
  ItemRackUser = {
    EnableEvents="ON",
    Events={ Enabled={}, Set={} },
    Sets={},
    EventStack={},
    EventState=ItemRack.EventFrames.NewState(),
  }
  ItemRackEvents = {}
  ItemRack.EventFramePendingTargets = {}
  ItemRack.EventFramePendingRevision = nil
  ItemRack.EventFramePendingDisableSound = nil
  ItemRack.EventFrameBatchDepth = 1
  ItemRack.EventFramePlanActive = nil
  ItemRack.EventFramePlanBlockedReason = nil
  ItemRack.EventFrameBlockedActivations = {}
  ItemRack.EventGenerations = {}
  ItemRack.LastLastSpec = nil
  ItemRack.PendingSpecSet = nil
  ItemRack.LastOnMovementState = nil
  ItemRack.OnMovementGeneration = nil
  ItemRack.OnMovementDelayElapsedGeneration = nil
  ItemRack.PendingOnMovementGeneration = nil
  ItemRack.LastZoneChangeTime = nil
  scheduled = {}
  auras = {}
  movingSpeed = 0
  currentStance = 0
  currentSpec = 1
  mounted = false
  instanceType = nil
  inventory = { [13]="Base13", [14]="Base14", [15]="Base15" }
end
local function addEvent(name,data,setname,equip)
  ItemRackEvents[name] = data
  ItemRackUser.Events.Enabled[name] = 1
  ItemRackUser.Events.Set[name] = setname
  ItemRackUser.Sets[setname] = { equip=equip }
end

-- Stance transitions collect every match and impose name order, independent of
-- insertion/pairs order. Leaving removes logical ownership even for Keep gear.
reset()
addEvent("ZuluStance",{ Type="Stance", Stance=1, Unequip=1 },"ZuluSet",{ [14]="Zulu14" })
addEvent("AlphaStance",{ Type="Stance", Stance=1 },"AlphaSet",{ [13]="Alpha13" })
currentStance = 1
ItemRack.ProcessStanceEvent()
check(#ItemRackUser.EventStack == 2, "all matching stance events must activate")
check(ItemRackUser.EventStack[1] == "AlphaStance" and ItemRackUser.EventStack[2] == "ZuluStance",
  "stance frame order must be deterministic")
check(ItemRackEvents.AlphaStance.Active and ItemRackEvents.ZuluStance.Active,
  "stance Active flags must project owned frames")
currentStance = 2
ItemRack.ProcessStanceEvent()
check(#ItemRackUser.EventStack == 0, "all ended stance frames must be removed")
check(ItemRack.EventFramePendingTargets[13] == nil,
  "an unsubmitted Unequip=false stance target must be cancelled when it ends")
check(ItemRack.EventFramePendingTargets[14] == "Base14",
  "an Unequip=true stance target must restore its observed base")

-- Multiple Buff+OnMovement owners share one generation-bound expiry. One
-- callback retires all of them in sorted order rather than one pairs() winner.
reset()
addEvent("ZuluMove",{ Type="Buff", Buff="Move Z", OnMovement=1, Unequip=1 },"ZuluMoveSet",{ [14]="Move14" })
addEvent("AlphaMove",{ Type="Buff", Buff="Move A", OnMovement=1, Unequip=1 },"AlphaMoveSet",{ [13]="Move13" })
auras["Move A"],auras["Move Z"] = true,true
movingSpeed = 7
ItemRack.ProcessBuffEvent()
check(ItemRackUser.EventStack[1] == "AlphaMove" and ItemRackUser.EventStack[2] == "ZuluMove",
  "Buff activation order must be deterministic")
ItemRack.EventFramePendingTargets = {}
movingSpeed = 0
ItemRack.ProcessBuffEvent()
check(#ItemRackUser.EventStack == 2 and #scheduled == 1,
  "stopping must retain all movement owners and schedule one shared debounce")
runScheduled()
check(#ItemRackUser.EventStack == 0, "one movement expiry must retire every stopped event")
check(ItemRack.EventFramePendingTargets[13] == "Base13"
  and ItemRack.EventFramePendingTargets[14] == "Base14",
  "movement expiry must coalesce every restoration slot")

-- A callback from the stopped epoch cannot pop frames after movement resumes.
reset()
addEvent("Move",{ Type="Buff", Buff="Move", OnMovement=1, Unequip=1 },"MoveSet",{ [13]="Move13" })
auras.Move = true
movingSpeed = 4
ItemRack.ProcessBuffEvent()
ItemRack.EventFramePendingTargets = {}
movingSpeed = 0
ItemRack.ProcessBuffEvent()
local staleGeneration = ItemRack.OnMovementGeneration
check(#scheduled == 1, "stop epoch must schedule its debounce")
movingSpeed = 4
ItemRack.ProcessBuffEvent()
runScheduled()
check(ItemRackUser.EventState.byEvent.Move ~= nil and ItemRackEvents.Move.Active,
  "stale stop callback must not pop after movement resumes")
check(ItemRack.OnMovementGeneration ~= staleGeneration,
  "movement resume must advance the callback generation")

-- A never-submitted non-restoring Buff activation is cancellation, not stale
-- future intent. This is the Unequip=false counterpart to observed keep-gear.
reset()
addEvent("KeepMove",{ Type="Buff", Buff="Keep", OnMovement=1, OnMovementDelay=false },"KeepSet",{ [13]="Keep13" })
auras.Keep = true
movingSpeed = 3
ItemRack.ProcessBuffEvent()
check(ItemRack.EventFramePendingTargets[13] == "Keep13", "keep event must initially request its target")
movingSpeed = 0
ItemRack.ProcessBuffEvent()
check(ItemRackUser.EventState.byEvent.KeepMove == nil, "instant stopped keep event must release its frame")
check(ItemRack.EventFramePendingTargets[13] == nil, "released keep event must cancel its unsubmitted target")

-- Specialization processing activates and retires every matching event in a
-- deterministic batch, rather than retaining one arbitrary eventToEquip value.
reset()
addEvent("ZuluSpec",{ Type="Specialization", Spec=1, Unequip=1 },"ZuluSpecSet",{ [14]="Spec14" })
addEvent("AlphaSpec",{ Type="Specialization", Spec=1, Unequip=1 },"AlphaSpecSet",{ [13]="Spec13" })
addEvent("SecondSpec",{ Type="Specialization", Spec=2, Unequip=1 },"SecondSpecSet",{ [15]="Spec15" })
currentSpec = 1
ItemRack.ProcessSpecializationEvent()
check(ItemRackUser.EventStack[1] == "AlphaSpec" and ItemRackUser.EventStack[2] == "ZuluSpec",
  "all current-spec events must activate in deterministic order")
currentSpec = 2
ItemRack.ProcessSpecializationEvent()
check(#ItemRackUser.EventStack == 1 and ItemRackUser.EventStack[1] == "SecondSpec",
  "spec transition must remove all old owners before adding the destination owners")
check(not ItemRackEvents.AlphaSpec.Active and not ItemRackEvents.ZuluSpec.Active
  and ItemRackEvents.SecondSpec.Active, "specialization Active flags must match frame ownership")

-- GitHub #21: an explicitly selected associated set wins over a different
-- destination-spec default; the request is consumed exactly once.
reset()
addEvent("Primary",{ Type="Specialization", Spec=1, Unequip=1 },"PrimarySet",{ [13]="Primary13" })
addEvent("Secondary",{ Type="Specialization", Spec=2, Unequip=1 },"DefaultSecondary",{ [13]="Default13" })
ItemRackUser.Sets.ManualSecondary = { equip={ [13]="Manual13" } }
currentSpec = 1
ItemRack.ProcessSpecializationEvent()
ItemRack.ReleaseEventSlotsForManualChange({ [13]=true })
ItemRack.EventFramePendingTargets = {}
ItemRackUser.CurrentSet = "ManualSecondary"
ItemRack.PendingSpecSet = { setname="ManualSecondary", spec=2, expiresAt=now+15 }
currentSpec = 2
ItemRack.ProcessSpecializationEvent()
check(ItemRack.PendingSpecSet == nil, "associated-set request must be consumed by the transition")
check(ItemRackUser.CurrentSet == "ManualSecondary", "destination default must not replace explicit set intent")
check(ItemRackUser.EventState.byEvent.Secondary == nil,
  "different destination default must not acquire ownership during preservation")
check(ItemRack.EventFramePendingTargets[13] == nil,
  "suppressed destination default must submit no gear target")

-- If the destination event maps to the selected set, it may adopt a logical
-- frame without generating a redundant physical move.
reset()
addEvent("SecondaryManual",{ Type="Specialization", Spec=2, Unequip=1 },"ManualSecondary",{ [13]="Manual13" })
inventory[13] = "Manual13"
ItemRackUser.CurrentSet = "ManualSecondary"
ItemRack.PendingSpecSet = { setname="ManualSecondary", spec=2, expiresAt=now+15 }
ItemRack.LastLastSpec = 1
currentSpec = 2
ItemRack.ProcessSpecializationEvent()
check(ItemRackUser.EventState.byEvent.SecondaryManual ~= nil and ItemRackEvents.SecondaryManual.Active,
  "matching destination event must adopt a frame")
check(ItemRack.EventFramePendingTargets[13] == nil,
  "same-set adoption must not submit a redundant equipment move")

-- Every explicit set-equip entry converges on EquipSet. It must record manual
-- intent before a readiness/casting return; automatic and internal calls must
-- not replace that intent, and the newest manual request wins.
reset()
ItemRackUser.Sets.Initiator = { equip={} }
ItemRackUser.Sets.ManualB = { equip={} }
ItemRackUser.Sets.ManualC = { equip={} }
ItemRackUser.Sets.Automatic = { equip={} }
ItemRackUser.Sets["~Internal"] = { equip={} }
ItemRackUser.EnableQueues = "ON"
ItemRack.QueueStateReady = false
ItemRack.ScheduleQueueStateRetry = function() end
ItemRack.PendingSpecSet = { setname="Initiator", spec=2, expiresAt=now+15 }
check(ItemRack.EquipSet("ManualB") == "deferred" and
  ItemRack.PendingSpecSet.latestManualSet == "ManualB",
  "manual intent must be captured before queue readiness defers EquipSet")
ItemRack.IsEventEquipment = true
ItemRack.EquipSet("Automatic")
ItemRack.IsEventEquipment = nil
check(ItemRack.PendingSpecSet.latestManualSet == "ManualB",
  "event equipment must not supersede a pending manual specialization intent")
ItemRack.PendingQueueEquipSet = nil
ItemRack.IsDeferredEquipment = true
ItemRack.EquipSet("Automatic")
ItemRack.IsDeferredEquipment = nil
check(ItemRack.PendingSpecSet.latestManualSet == "ManualB",
  "deferred automatic equipment must not supersede manual intent")
ItemRack.PendingQueueEquipSet = nil
ItemRack.EquipSet("~Internal")
check(ItemRack.PendingSpecSet.latestManualSet == "ManualB",
  "internal restoration sets must not supersede manual intent")
ItemRack.PendingQueueEquipSet = nil
ItemRack.EquipSet("ManualC")
check(ItemRack.PendingSpecSet.latestManualSet == "ManualC",
  "multiple manual selections must use last-write-wins precedence")

-- Toggling the initiating set off is a newer manual decision too. Capture it
-- before a lock defers the restore and suppress the destination default once.
reset()
addEvent("DestinationDefault",{ Type="Specialization", Spec=2, Unequip=1 },
  "DefaultSet",{ [13]="Default13" })
ItemRackUser.Sets.Initiator = { equip={ [13]="Initial13" }, old={} }
ItemRackUser.CurrentSet = "Initiator"
ItemRack.PendingSpecSet = { setname="Initiator", spec=2, expiresAt=now+15 }
ItemRack.LastLastSpec = 1
ItemRack.SetSwapping = "Other"
ItemRack.AddSetToSetsWaiting = function() end
ItemRack.UnequipSet("Initiator")
ItemRack.SetSwapping = nil
check(ItemRack.PendingSpecSet.cancelledByManualUnequip and
  ItemRack.PendingSpecSet.latestManualSet == nil,
  "manual toggle-off must supersede a pending associated-set intent before lock deferral")
currentSpec = 2
ItemRack.ProcessSpecializationEvent()
check(ItemRack.PendingSpecSet == nil and
  ItemRackUser.EventState.byEvent.DestinationDefault == nil and
  ItemRack.EventFramePendingTargets[13] == nil,
  "the expected spec transition must not immediately undo the newer manual unequip")

-- A newer manual set remains authoritative even while CurrentSet still names
-- the associated set that initiated the cast.
reset()
addEvent("Primary",{ Type="Specialization", Spec=1, Unequip=1 },"PrimarySet",{ [13]="Primary13" })
addEvent("DestinationDefault",{ Type="Specialization", Spec=2, Unequip=1 },"DefaultSet",{ [13]="Default13" })
ItemRackUser.Sets.ManualB = { equip={ [13]="ManualB13" } }
currentSpec = 1
ItemRack.ProcessSpecializationEvent()
ItemRackUser.CurrentSet = "PrimarySet"
ItemRack.PendingSpecSet = {
  setname="PrimarySet", latestManualSet="ManualB", spec=2, expiresAt=now+15,
}
ItemRack.ReleaseEventSlotsForManualChange(ItemRackUser.Sets.ManualB.equip)
ItemRack.EventFramePendingTargets = {}
currentSpec = 2
ItemRack.ProcessSpecializationEvent()
check(ItemRack.PendingSpecSet == nil and
  ItemRackUser.EventState.byEvent.DestinationDefault == nil,
  "a newer queued manual set must suppress a different destination default")
check(ItemRack.EventFramePendingTargets[13] == nil,
  "suppressed destination defaults must not submit physical gear")

-- If the destination event maps to that newer manual set, it may adopt the
-- logical frame even before CurrentSet catches up.
reset()
addEvent("ManualDestination",{ Type="Specialization", Spec=2, Unequip=1 },"ManualB",{ [13]="ManualB13" })
ItemRackUser.Sets.Initiator = { equip={ [13]="Initial13" } }
inventory[13] = "ManualB13"
ItemRackUser.CurrentSet = "Initiator"
ItemRack.PendingSpecSet = {
  setname="Initiator", latestManualSet="ManualB", spec=2, expiresAt=now+15,
}
ItemRack.LastLastSpec = 1
currentSpec = 2
ItemRack.ProcessSpecializationEvent()
check(ItemRackUser.EventState.byEvent.ManualDestination ~= nil and
  ItemRackEvents.ManualDestination.Active,
  "a matching destination event must adopt the newer manual set")
check(ItemRack.EventFramePendingTargets[13] == nil,
  "newer same-set adoption must avoid a redundant physical target")

-- Forced same-spec reconciliation is not proof that the in-flight cast
-- completed. Leave the request for the real transition (or its timeout).
reset()
addEvent("Primary",{ Type="Specialization", Spec=1, Unequip=1 },"PrimarySet",{ [13]="Primary13" })
ItemRackUser.PendingMarker = true
ItemRack.PendingSpecSet = { setname="PrimarySet", spec=2, expiresAt=now+15 }
ItemRack.LastLastSpec = 1
currentSpec = 1
ItemRack.ProcessSpecializationEvent(true)
check(ItemRack.PendingSpecSet ~= nil,
  "forced same-spec processing must not consume an in-flight associated-set request")

-- Expired/deleted overrides are not allowed to suppress a valid destination.
reset()
addEvent("Destination",{ Type="Specialization", Spec=2, Unequip=1 },"DefaultSet",{ [13]="Default13" })
ItemRackUser.Sets.Initiator = { equip={} }
ItemRackUser.CurrentSet = "Initiator"
ItemRack.PendingSpecSet = {
  setname="Initiator", latestManualSet="DeletedSet", spec=2, expiresAt=now-1,
}
ItemRack.LastLastSpec = 1
currentSpec = 2
ItemRack.ProcessSpecializationEvent()
check(ItemRack.PendingSpecSet == nil and ItemRackEvents.Destination.Active,
  "an expired or deleted manual override must fall back to the destination default")

-- Changing course to a different specialization consumes the stale request
-- and evaluates that specialization normally.
reset()
ItemRackUser.Sets.Initiator = { equip={} }
ItemRackUser.CurrentSet = "Initiator"
ItemRack.PendingSpecSet = { setname="Initiator", spec=2, expiresAt=now+15 }
ItemRack.LastLastSpec = 1
currentSpec = 3
ItemRack.ProcessSpecializationEvent()
check(ItemRack.PendingSpecSet == nil,
  "a transition to an unexpected specialization must consume the stale request")

print(string.format("[EVENT PROCESSORS LUA] %d deterministic processor checks passed.",checks))
`, 'event-processors');
