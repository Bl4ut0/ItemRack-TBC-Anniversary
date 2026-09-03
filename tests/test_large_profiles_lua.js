const fs = require('fs');
const { runLua } = require('../.tools/lib/lua_harness');

const eventState = fs.readFileSync('ItemRack/ItemRackEventState.lua', 'utf8');
const queuePolicy = fs.readFileSync('ItemRack/ItemRackQueuePolicy.lua', 'utf8');
const queueMigration = fs.readFileSync('ItemRack/ItemRackQueueMigration.lua', 'utf8');
const transaction = fs.readFileSync('ItemRack/ItemRackTransaction.lua', 'utf8');

// These scenarios deliberately look more like a long-lived SavedVariables
// profile than a focused unit fixture.  Every pseudo-random choice is seeded
// so a failure can be reproduced exactly.
runLua(String.raw`
ItemRack = {}
${eventState}

local API = ItemRack.EventFrames
local checks = 0
local seed = 44501

local function check(value,message)
  assert(value,message)
  checks = checks + 1
end

local function countEntries(value)
  local count = 0
  for _ in pairs(value or {}) do count = count + 1 end
  return count
end

local function nextRandom(limit)
  seed = (seed * 48271) % 2147483647
  return (seed % limit) + 1
end

local function copySlots(value)
  local result = {}
  for slot,item in pairs(value or {}) do result[slot] = item end
  return result
end

local function applyTargets(physical,targets)
  for slot,target in pairs(targets or {}) do physical[slot] = target end
end

local function validateState(state,physical,base,label)
  check(#state.order == countEntries(state.frames),label..": frame/order count diverged")
  check(#state.order == countEntries(state.byEvent),label..": event/order count diverged")
  local seen = {}
  for index,frameId in ipairs(state.order) do
    local frame = state.frames[frameId]
    check(frame ~= nil,label..": order references a missing frame")
    check(not seen[frameId],label..": order contains a duplicate frame")
    check(state.byEvent[frame.eventName] == frameId,label..": reverse event index diverged")
    check(frame.id == frameId and frame.sequence == frameId,label..": frame identity changed")
    seen[frameId] = index
  end
  for eventName,frameId in pairs(state.byEvent) do
    check(seen[frameId] ~= nil,label..": event index references an unordered frame")
    check(state.frames[frameId].eventName == eventName,label..": event name/index mismatch")
  end
  for slot=1,19 do
    local target = API.EffectiveTarget(state,slot)
    check(physical[slot] == (target or base[slot]),
      label..": physical/effective mismatch in slot "..tostring(slot))
  end
end

local sets = {}
for setIndex=1,64 do
  local setName = "ProfileSet"..tostring(setIndex)
  local equip = {}
  for offset=0,5 do
    local slot = ((setIndex * 3 + offset * 5) % 19) + 1
    equip[slot] = setName.."/slot"..tostring(slot)
  end
  sets[setName] = equip
end

local base,physical = {},{}
for slot=1,19 do
  base[slot] = "Base/slot"..tostring(slot)
  physical[slot] = base[slot]
end

local state = API.NewState()
local generations = {}
for eventIndex=1,80 do
  local eventName = "ProfileEvent"..tostring(eventIndex)
  local setName = "ProfileSet"..tostring(((eventIndex - 1) % 64) + 1)
  local activation = {
    eventName=eventName,
    eventGeneration=1000 + eventIndex,
    setName=setName,
    slots=sets[setName],
    observed=copySlots(physical),
    origin=(eventIndex % 3 == 0) and "Zone" or "Buff",
  }
  if eventIndex % 9 == 0 and #state.order > 0 then
    activation.beforeFrameId = state.order[#state.order]
  end
  local result = API.Activate(state,activation)
  check(result.changed and type(result.frameId) == "number",
    "generated activation must create an independently owned frame")
  applyTargets(physical,result.targets)
  generations[eventName] = activation.eventGeneration

  local revision = state.revision
  local stale = API.Pop(state,eventName,activation.eventGeneration - 1)
  check(stale.removed == false and stale.reason == "stale_generation",
    "stale generation must not remove a generated event")
  check(state.revision == revision and next(stale.targets) == nil,
    "stale generation must be a total no-op")
  validateState(state,physical,base,"activate "..tostring(eventIndex))
end

check(#state.order == 80,"all generated logical owners must coexist")
check(state.frames[state.byEvent.ProfileEvent1].setName ==
      state.frames[state.byEvent.ProfileEvent65].setName,
  "different events must be able to share one physical set")

local removalOrder = {}
for index=1,80 do removalOrder[index] = "ProfileEvent"..tostring(index) end
local removalCount = 0
while #removalOrder > 0 do
  local index = nextRandom(#removalOrder)
  local eventName = table.remove(removalOrder,index)
  local result = API.Pop(state,eventName,generations[eventName])
  check(result.removed == true,"every generated owner must pop exactly once")
  applyTargets(physical,result.targets)
  removalCount = removalCount + 1
  validateState(state,physical,base,"pop "..tostring(removalCount))
end
check(#state.order == 0 and next(state.frames) == nil and next(state.byEvent) == nil,
  "random buried-pop drain must leave no ownership residue")
for slot=1,19 do
  check(physical[slot] == base[slot],"final generated pop must restore every base slot")
end

-- A new generation replaces the same logical event. Removed slots restore,
-- retained slots take the new target, and unchanged retained targets do not
-- momentarily restore their base value.
do
  local replacementState = API.NewState()
  local replacementPhysical = copySlots(base)
  local first = API.Activate(replacementState,{
    eventName="Reusable", eventGeneration=1, setName="OldSet",
    slots={ [13]="Old13", [14]="Same14" }, observed=copySlots(replacementPhysical),
  })
  applyTargets(replacementPhysical,first.targets)
  local second = API.Activate(replacementState,{
    eventName="Reusable", eventGeneration=2, setName="NewSet",
    slots={ [13]="New13", [14]="Same14" }, observed=copySlots(replacementPhysical),
  })
  applyTargets(replacementPhysical,second.targets)
  check(#replacementState.order == 1 and
      replacementState.frames[replacementState.byEvent.Reusable].eventGeneration == 2,
    "generation replacement must leave exactly one current frame")
  check(replacementPhysical[13] == "New13" and replacementPhysical[14] == "Same14",
    "generation replacement must apply the final visible targets")
  local third = API.Activate(replacementState,{
    eventName="Reusable", eventGeneration=3, setName="NarrowSet",
    slots={ [13]="Newest13" }, observed=copySlots(replacementPhysical),
  })
  applyTargets(replacementPhysical,third.targets)
  check(replacementPhysical[14] == base[14],
    "a replacement generation must restore slots it no longer owns")
  applyTargets(replacementPhysical,API.Pop(replacementState,"Reusable",3).targets)
  check(replacementPhysical[13] == base[13] and replacementPhysical[14] == base[14],
    "replacement history must still drain to the original base")

  local unresolved = API.NewState()
  API.Activate(unresolved,{
    eventName="UnresolvedReplacement", eventGeneration=1, setName="Old",
    slots={ [13]="Old13" }, observed={ [13]=base[13] },
  })
  local unresolvedResult = API.Activate(unresolved,{
    eventName="UnresolvedReplacement", eventGeneration=2, setName="BaseAgain",
    slots={ [13]=base[13] }, observed={},
  })
  check(unresolvedResult.targets[13] == base[13],
    "replacement must coalesce correctly when the new physical observation is unresolved")
end

-- Manual gear selection releases that slot from every automatic layer while
-- unrelated slots continue to unwind normally.
do
  local releaseState = API.NewState()
  local releasePhysical = copySlots(base)
  for index=1,20 do
    local name = "ReleaseEvent"..tostring(index)
    local setName = "ProfileSet"..tostring(index)
    local result = API.Activate(releaseState,{
      eventName=name, eventGeneration=index, setName=setName,
      slots=sets[setName], observed=copySlots(releasePhysical),
    })
    applyTargets(releasePhysical,result.targets)
  end
  releasePhysical[13] = "Manual/slot13"
  local revision = releaseState.revision
  check(API.ReleaseSlots(releaseState,{ [13]=true }),
    "manual ownership must release an occupied automatic slot")
  check(releaseState.revision == revision + 1 and API.EffectiveTarget(releaseState,13) == nil,
    "manual release must invalidate stale plans and all slot owners")
  for index=20,1,-1 do
    applyTargets(releasePhysical,API.Pop(releaseState,"ReleaseEvent"..tostring(index),index).targets)
  end
  check(releasePhysical[13] == "Manual/slot13",
    "automatic unwind must not overwrite a manually released slot")
  for slot=1,19 do
    if slot ~= 13 then
      check(releasePhysical[slot] == base[slot],
        "unreleased generated slots must still unwind to base")
    end
  end
end

print(string.format(
  "[LARGE PROFILE EVENTS] %d checks; 64 sets, 100 activations, 80 randomized buried removals (seed 44501).",
  checks))
`, 'large-profile-events');

runLua(String.raw`
ItemRack = {}
${queuePolicy}

local Policy = ItemRack.QueuePolicy
local checks = 0
local function check(value,message) assert(value,message); checks = checks + 1 end

local user = {
  EnablePerSetQueues="ON",
  EnableQueueContextCheck="ON",
  CurrentSet="Set1",
  Queues={}, QueuesEnabled={}, Sets={}, EventStack={}, Events={ Set={} },
  manualChoice={ owner="player", value="must-survive" },
}
for slot=1,19 do
  user.Queues[slot] = { { id="Global/"..tostring(slot) } }
  user.QueuesEnabled[slot] = slot % 2 == 0
end
for setIndex=1,64 do
  local name = "Set"..tostring(setIndex)
  local set = { equip={}, Queues={}, QueuesEnabled={}, marker="marker/"..name }
  for slot=1,19 do
    if (setIndex + slot) % 5 == 0 then
      set.equip[slot] = "Gear/"..name.."/"..tostring(slot)
    end
    if (setIndex * 3 + slot) % 7 == 0 then
      set.Queues[slot] = { { id="Queue/"..name.."/"..tostring(slot) } }
    end
    if (setIndex * 11 + slot) % 9 == 0 then
      set.QueuesEnabled[slot] = (slot % 2 == 1)
    end
  end
  user.Sets[name] = set
end
for eventIndex=1,96 do
  local eventName = "Event"..tostring(eventIndex)
  local setName = "Set"..tostring(((eventIndex * 7 - 1) % 64) + 1)
  user.EventStack[eventIndex] = eventName
  user.Events.Set[eventName] = setName
end

local function boundary(set,slot)
  return set.Queues[slot] ~= nil or set.QueuesEnabled[slot] ~= nil or set.equip[slot] ~= nil
end

local function resolve(slot,explicit)
  return Policy.Resolve(user,function(eventName) return user.Events.Set[eventName] end,slot,explicit)
end

local function checkAtomic(context,slot,label)
  if context.owner then
    local owner = user.Sets[context.owner]
    check(context.list == owner.Queues[slot],label..": queue list came from another owner")
    check(context.enabled == owner.QueuesEnabled[slot],label..": enabled state came from another owner")
  elseif context.reason == "global_fallback" or context.reason == "per_set_disabled"
      or context.reason == "missing_explicit_set" or context.reason == "no_current_set" then
    check(context.list == user.Queues[slot],label..": global list identity changed")
    check(context.enabled == user.QueuesEnabled[slot],label..": global enabled identity changed")
  end
end

for setIndex=1,64 do
  local name = "Set"..tostring(setIndex)
  local set = user.Sets[name]
  for slot=1,19 do
    local context = resolve(slot,name)
    check(context.reason == "explicit_set", "explicit set must remain the policy boundary")
    check(context.owner == (boundary(set,slot) and name or false),
      "explicit owner must follow that set's boundary only")
    check(context.list == set.Queues[slot] and context.enabled == set.QueuesEnabled[slot],
      "explicit list/enabled tuple must be atomic even without ownership")
  end
end

for currentIndex=1,64 do
  local currentName = "Set"..tostring(currentIndex)
  user.CurrentSet = currentName
  for slot=1,19 do
    local expectedName
    if boundary(user.Sets[currentName],slot) then
      expectedName = currentName
    else
      local seen = { [currentName]=true }
      for index=#user.EventStack,1,-1 do
        local candidate = user.Events.Set[user.EventStack[index]]
        if candidate and not seen[candidate] then
          seen[candidate] = true
          if boundary(user.Sets[candidate],slot) then expectedName = candidate; break end
        end
      end
    end
    local context = resolve(slot)
    check(context.owner == (expectedName or false),
      "current/event/global precedence selected the wrong owner")
    check(context.reason == (expectedName == currentName and "current_set"
      or expectedName and "event_stack" or "global_fallback"),
      "queue context reported the wrong precedence reason")
    checkAtomic(context,slot,"current "..currentName.." slot "..tostring(slot))
  end
end

for slot=1,19 do
  local context = resolve(slot,"MissingSet")
  check(context.reason == "missing_explicit_set" and context.owner == false,
    "missing explicit sets must fail safely to the global tuple")
  checkAtomic(context,slot,"missing explicit")
end

user.EnablePerSetQueues = "OFF"
for slot=1,19 do
  local context = resolve(slot,"Set32")
  check(context.reason == "per_set_disabled" and context.owner == false,
    "disabled per-set queues must always select global policy")
  checkAtomic(context,slot,"per-set disabled")
end
user.EnablePerSetQueues = "ON"
user.EnableQueueContextCheck = "OFF"
user.CurrentSet = "Set17"
for slot=1,19 do
  local context = resolve(slot)
  check(context.reason == (boundary(user.Sets.Set17,slot) and "current_set"
      or "context_inheritance_disabled"),
    "disabled inheritance must stop before event/global search")
  check(context.owner == (boundary(user.Sets.Set17,slot) and "Set17" or false),
    "disabled inheritance must not borrow another owner")
  check(context.list == user.Sets.Set17.Queues[slot] and
      context.enabled == user.Sets.Set17.QueuesEnabled[slot],
    "disabled inheritance must retain one atomic current-set tuple")
end

check(user.manualChoice.owner == "player" and user.manualChoice.value == "must-survive",
  "queue resolution must not mutate a manual choice")
check(#user.EventStack == 96 and user.EventStack[1] == "Event1" and
    user.EventStack[96] == "Event96", "queue resolution must not mutate the event stack")
for setIndex=1,64 do
  local name = "Set"..tostring(setIndex)
  check(user.Sets[name].marker == "marker/"..name,
    "queue resolution must not mutate saved-set extensions")
end

print(string.format(
  "[LARGE PROFILE QUEUES] %d checks; 64 sets x 19 slots with a 96-event inheritance stack.",
  checks))
`, 'large-profile-queues');

runLua(String.raw`
ItemRack = {}
${queueMigration}

local Migration = ItemRack.QueueMigration
local checks = 0
local function check(value,message) assert(value,message); checks = checks + 1 end
local function count(value)
  local result = 0
  for _ in pairs(value or {}) do result = result + 1 end
  return result
end

local legacy = {}
local user = {
  QueueSchemaVersion=0,
  Queues={}, QueuesEnabled={}, Sets={},
  futureRoot={ keep=true, nested={ value="root-extension" } },
}

local nextID = 100000
local function buildQueue(label)
  nextID = nextID + 10
  local first,second,suffix = nextID + 1,nextID + 2,nextID + 6
  legacy[tostring(first)] = {
    priority=true, keep="truthy", delay="2.5",
    plugin={ source=label, nested={ retained=true } },
  }
  return {
    [1]=first,
    [2]={ id=second, priority=false, custom={ label=label } },
    [4]={ missing="id" },
    [6]=suffix,
    label=label,
  },first,second,suffix
end

local globalFirst = {}
for slot=1,19 do
  local queue,first = buildQueue("global/"..tostring(slot))
  local key = slot % 2 == 0 and tostring(slot) or slot
  user.Queues[key] = queue
  user.QueuesEnabled[key] = slot % 3 == 0 and "ON" or "0"
  globalFirst[slot] = first
end

local setFirst = {}
for setIndex=1,48 do
  local name = "MigratedSet"..tostring(setIndex)
  local set = { Queues={}, QueuesEnabled={}, extension={ setIndex=setIndex } }
  setFirst[name] = {}
  for slot=1,19 do
    local queue,first = buildQueue(name.."/"..tostring(slot))
    local key = (setIndex + slot) % 2 == 0 and tostring(slot) or slot
    set.Queues[key] = queue
    set.QueuesEnabled[key] = (setIndex + slot) % 4 == 0 and "true" or 0
    setFirst[name][slot] = first
  end
  user.Sets[name] = set
end

local originalGlobal = user.Queues
local report = Migration.Migrate(user,legacy,function(id) return tostring(id) end,
  function() return 4450001 end)
check(user.QueueSchemaVersion == 2 and report.fromVersion == 0 and report.toVersion == 2,
  "large legacy profile must reach schema v2")
check(type(user.QueueMigrationBackup) == "table" and
    user.QueueMigrationBackup.capturedAt == 4450001,
  "large migration must capture one timestamped recovery snapshot")
check(user.QueueMigrationBackup.global == nil or user.QueueMigrationBackup.global ~= originalGlobal,
  "migration backup must be a deep copy, never the live queue root")
check(user.futureRoot.nested.value == "root-extension",
  "migration must preserve unknown root fields")

local expectedQueues = 49 * 19
check(report.queuesVisited == expectedQueues,
  "migration must visit every global and per-set queue")
check(report.entriesVisited == expectedQueues * 4,
  "migration must visit every sparse list record")
check(report.entriesQuarantined == expectedQueues and
    report.boundariesInserted == expectedQueues,
  "each corrupt sparse queue must quarantine once and gain one stop boundary")
check(report.slotKeysNormalized > 0 and report.enabledValuesChanged > 0,
  "large profile must exercise key and enabled-value normalization")
check(#user.QueueMigrationQuarantine == expectedQueues,
  "every rejected entry must remain inspectable")

local function validateQueue(queue,first,label)
  check(type(queue) == "table" and #queue == 4,label..": normalized queue length is wrong")
  check(queue[1].id == first and queue[1].priority == true and
      queue[1].keep == true and queue[1].delay == 2.5,
    label..": legacy item metadata was not recovered")
  check(queue[1].plugin.source == label and queue[1].plugin.nested.retained == true,
    label..": unknown nested metadata was lost")
  check(type(queue[2]) == "table" and queue[2].custom.label == label,
    label..": canonical entry extensions were lost")
  check(queue[3].id == 0 and queue[3].priority == false and
      queue[3].keep == false and queue[3].delay == 0,
    label..": unsafe suffix must be isolated behind a canonical stop marker")
  check(type(queue[4]) == "table" and queue[4].id ~= nil,
    label..": valid suffix entry must remain recoverable")
  check(queue.label == label,label..": non-list queue extension was destroyed")
end

for slot=1,19 do
  validateQueue(user.Queues[slot],globalFirst[slot],"global/"..tostring(slot))
  check(type(user.QueuesEnabled[slot]) == "boolean",
    "global enabled values must normalize to booleans")
end
for setIndex=1,48 do
  local name = "MigratedSet"..tostring(setIndex)
  local set = user.Sets[name]
  check(set.extension.setIndex == setIndex,"per-set extension must survive migration")
  for slot=1,19 do
    validateQueue(set.Queues[slot],setFirst[name][slot],name.."/"..tostring(slot))
    check(type(set.QueuesEnabled[slot]) == "boolean",
      "per-set enabled values must normalize to booleans")
  end
end

local backup = user.QueueMigrationBackup
local quarantine = user.QueueMigrationQuarantine
local firstEntry = user.Sets.MigratedSet1.Queues[1][1]
user.Sets.MigratedSet1.Queues[1][1].plugin.nested.retained = "changed-live-value"
check(user.QueueMigrationBackup.sets.MigratedSet1["1"][1] == setFirst.MigratedSet1[1],
  "mutating canonical data must not alter the pre-migration backup")
local rerun = Migration.Migrate(user,legacy,function(id) return tostring(id) end)
check(rerun.entriesChanged == 0 and rerun.entriesQuarantined == 0 and
    rerun.boundariesInserted == 0,
  "a second large-profile pass must be idempotent")
check(user.QueueMigrationBackup == backup and user.QueueMigrationQuarantine == quarantine and
    user.Sets.MigratedSet1.Queues[1][1] == firstEntry,
  "idempotence must preserve backup, quarantine, and canonical entry identities")

local futureQueue = { "opaque-future-entry" }
local future = { QueueSchemaVersion=99, Queues={ [13]=futureQueue }, Sets={} }
local futureReport = Migration.Migrate(future,legacy,function(id) return tostring(id) end)
check(futureReport.skipped == "future_schema" and future.QueueSchemaVersion == 99 and
    future.Queues[13] == futureQueue and future.QueueMigrationBackup == nil,
  "unknown future profiles must remain byte-shape compatible and untouched")

print(string.format(
  "[LARGE PROFILE MIGRATION] %d checks; %d queues and %d legacy records migrated twice.",
  checks, expectedQueues, expectedQueues * 4))
`, 'large-profile-migration');

runLua(String.raw`
local now,timers = 0,{}
local bags,inventory,cursor = {},{},nil
local bagCount,bagSize = 5,40
local locked = {}
local spellTargeting = false
local rejection = nil
local checks = 0
local completed,failed = 0,0

local function check(value,message) assert(value,message); checks = checks + 1 end
local function locationKey(bag,slot)
  return slot and ("b:"..tostring(bag)..":"..tostring(slot)) or ("i:"..tostring(bag))
end
local function getValue(bag,slot)
  if slot then return bags[bag][slot] or 0 end
  return inventory[bag] or 0
end
local function setValue(bag,slot,value)
  if value == 0 then value = nil end
  if slot then bags[bag][slot] = value else inventory[bag] = value end
end
local function swapLocation(bag,slot)
  local held = cursor
  cursor = getValue(bag,slot)
  setValue(bag,slot,held or 0)
end

for bag=0,bagCount-1 do bags[bag] = {} end
for slot=1,19 do inventory[slot] = 50000 + slot end

INVSLOT_AMMO,INVSLOT_RANGED = 0,18
C_Container = nil
ItemRackSettings = { DisableSwapSound="OFF" }
ItemRack = {
  Debug=function() end,
  SameExactID=function(left,right) return left == right end,
  MatchesStoredItemID=function(left,right) return left == right end,
  MuteSwapSounds=function() end,
}
function GetTime() return now end
C_Timer = {
  After=function(delay,callback)
    table.insert(timers,{ due=now + delay, callback=callback })
  end,
}
function RunTimers(limit)
  local runs = 0
  while #timers > 0 do
    table.sort(timers,function(left,right) return left.due < right.due end)
    local timer = table.remove(timers,1)
    now = timer.due
    timer.callback()
    runs = runs + 1
    assert(runs < (limit or 500),"transaction timers did not settle")
  end
end
function ItemRack.GetID(bag,slot) return getValue(bag,slot) end
function CursorHasItem() return cursor ~= nil end
function SpellIsTargeting() return spellTargeting end
function ClearCursor() cursor = nil end
function GetContainerItemInfo(bag,slot)
  return nil,nil,locked[locationKey(bag,slot)] and true or false
end
function IsInventoryItemLocked(slot)
  return locked[locationKey(slot,nil)] and true or false
end
function PickupContainerItem(bag,slot) swapLocation(bag,slot) end
function PickupInventoryItem(slot)
  if rejection and not rejection.used and cursor == rejection.item and slot == rejection.slot then
    rejection.used = true
    return
  end
  swapLocation(slot,nil)
end

${transaction}

local equipSlots = { 1,3,5,7,13,14,16,17 }
local profiles = {}
local cell = 0
for profileIndex=1,24 do
  local profile = {}
  for _,slot in ipairs(equipSlots) do
    local id = 1000000 + profileIndex * 100 + slot
    profile[slot] = id
    cell = cell + 1
    local bag = math.floor((cell - 1) / bagSize)
    local bagSlot = ((cell - 1) % bagSize) + 1
    bags[bag][bagSlot] = id
  end
  profiles[profileIndex] = profile
end

local function allLocations()
  local result = {}
  for slot=1,19 do
    table.insert(result,{ bag=slot, slot=nil })
  end
  for bag=0,bagCount-1 do
    for slot=1,bagSize do table.insert(result,{ bag=bag, slot=slot }) end
  end
  return result
end
local locations = allLocations()

local function snapshot()
  local result = {}
  for _,location in ipairs(locations) do
    result[locationKey(location.bag,location.slot)] = getValue(location.bag,location.slot)
  end
  return result
end
local function assertSnapshot(expected,label)
  for _,location in ipairs(locations) do
    local key = locationKey(location.bag,location.slot)
    check(getValue(location.bag,location.slot) == expected[key],label..": endpoint "..key.." changed")
  end
  check(cursor == nil,label..": cursor item leaked")
end

local function buildPlan(profile)
  local values,byKey = {},{}
  for _,location in ipairs(locations) do
    local key = locationKey(location.bag,location.slot)
    values[key] = getValue(location.bag,location.slot)
    byKey[key] = location
  end
  local steps = {}
  for _,destinationSlot in ipairs(equipSlots) do
    local desired = profile[destinationSlot]
    local destinationKey = locationKey(destinationSlot,nil)
    if values[destinationKey] ~= desired then
      local sourceKey
      for key,value in pairs(values) do
        if value == desired then sourceKey = key; break end
      end
      assert(sourceKey,"desired profile item is missing: "..tostring(desired))
      local source = byKey[sourceKey]
      table.insert(steps,ItemRack.NewEquipmentMove(
        source.bag,source.slot,destinationSlot,nil))
      values[sourceKey],values[destinationKey] = values[destinationKey],values[sourceKey]
    end
  end
  return steps
end

local function startProfile(profileIndex,injectFailure)
  local steps = buildPlan(profiles[profileIndex])
  check(#steps > 0,"profile switch must contain at least one physical move")
  local before = snapshot()
  if injectFailure then
    check(#steps >= 3,"failure profile must have enough confirmed-prefix coverage")
    local destination = steps[3].to.bag
    rejection = { slot=destination, item=profiles[profileIndex][destination], used=false }
  else
    rejection = nil
  end
  local result,request = ItemRack.StartEquipmentTransaction({
    kind="large_profile", origin="generated_set_"..tostring(profileIndex), steps=steps,
    onComplete=function() completed = completed + 1 end,
    onFailure=function() failed = failed + 1 end,
  })
  check(result == "submitted" and request ~= nil,
    "generated profile must enter observed transaction state")
  RunTimers()
  check(ItemRack.ActiveEquipmentTransaction == nil,
    "generated profile must leave no active transaction")
  if injectFailure then
    check(rejection.used,"injected destination rejection was not exercised")
    check(request.status == "failed_rolled_back" and request.reason == "destination_rejected",
      "later generated failure must report exact rollback status")
    assertSnapshot(before,"rolled-back profile "..tostring(profileIndex))
  else
    check(request.status == "complete","generated profile transaction must complete")
    for _,slot in ipairs(equipSlots) do
      check(inventory[slot] == profiles[profileIndex][slot],
        "completed generated profile has the wrong equipped item")
    end
    check(cursor == nil,"completed generated profile must leave an empty cursor")
  end
end

local successfulRequests,rolledBackRequests = 0,0
for requestIndex=1,96 do
  local profileIndex = ((requestIndex * 11 - 1) % 24) + 1
  local injectFailure = requestIndex % 13 == 0
  startProfile(profileIndex,injectFailure)
  if injectFailure then rolledBackRequests = rolledBackRequests + 1
  else successfulRequests = successfulRequests + 1 end
end
check(completed == successfulRequests and failed == rolledBackRequests,
  "each generated request must invoke exactly one terminal callback")

-- Hold the first endpoint lock so a second request collides with an active
-- transaction, then release the lock and prove the original request resumes.
do
  local profileIndex = 2
  local steps = buildPlan(profiles[profileIndex])
  local first = steps[1]
  locked[locationKey(first.from.bag,first.from.slot)] = true
  local result,request = ItemRack.StartEquipmentTransaction({ steps=steps })
  check(result == "submitted" and request.status == "blocked",
    "locked source must retain one resumable transaction")
  local blocked,other,reason = ItemRack.StartEquipmentTransaction({
    steps={ ItemRack.NewEquipmentMove(0,1,1,nil) },
  })
  check(blocked == "blocked" and other == nil and reason == "transaction_active",
    "rapid set clicks must not interleave transactions")
  locked[locationKey(first.from.bag,first.from.slot)] = nil
  RunTimers()
  check(request.status == "complete" and ItemRack.ActiveEquipmentTransaction == nil,
    "released lock must let the original transaction finish")
end

do
  cursor = 777777
  local result,request,reason = ItemRack.StartEquipmentTransaction({
    steps={ ItemRack.NewEquipmentMove(0,1,1,nil) },
  })
  check(result == "blocked" and request == nil and reason == "cursor_occupied",
    "a user-owned cursor must block a large-profile request")
  check(cursor == 777777,"blocked preflight must preserve the user's cursor item")
  cursor = nil
  spellTargeting = true
  result,request,reason = ItemRack.StartEquipmentTransaction({
    steps={ ItemRack.NewEquipmentMove(0,1,1,nil) },
  })
  check(result == "blocked" and request == nil and reason == "spell_targeting",
    "spell targeting must block transaction ownership")
  spellTargeting = false
end

print(string.format(
  "[LARGE PROFILE TRANSACTIONS] %d checks; 24 saved sets, %d successful and %d rolled-back switches.",
  checks, successfulRequests + 1, rolledBackRequests))
`, 'large-profile-transactions');

console.log('[LARGE PROFILE LUA] Deterministic many-set use-case suite passed.');
