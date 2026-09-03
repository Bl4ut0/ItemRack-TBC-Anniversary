const fs = require('fs');
const { runLua } = require('./lib/lua_harness');

const transactionSource = fs.readFileSync('ItemRack/ItemRackTransaction.lua', 'utf8');
const equipSource = fs.readFileSync('ItemRack/ItemRackEquip.lua', 'utf8');

function runCase(name, setup, assertions) {
  runLua(`${setup}\n${transactionSource}\n${assertions}`, `transaction-engine:${name}`);
}

const common = String.raw`
local now = 0
local timers = {}
local clearCursorCalls = 0

function GetTime() return now end
C_Timer = {
  After = function(delay, callback)
    table.insert(timers, { due = now + delay, callback = callback })
  end,
}
function RunTimers(limit)
  local runs = 0
  while #timers > 0 do
    table.sort(timers, function(a, b) return a.due < b.due end)
    local timer = table.remove(timers, 1)
    now = timer.due
    timer.callback()
    runs = runs + 1
    assert(runs < (limit or 200), "timer loop did not settle")
  end
end

INVSLOT_AMMO, INVSLOT_RANGED = 0, 18
C_Container = nil
ItemRackSettings = { DisableSwapSound = "OFF" }
ItemRack = {
  Debug = function() end,
  SameExactID = function(a, b) return a == b end,
  MatchesStoredItemID = function(a, b) return a == b end,
  MuteSwapSounds = function() end,
}
function SpellIsTargeting() return false end
function IsInventoryItemLocked() return false end
function GetContainerItemInfo() return nil, nil, false end
function ClearCursor() clearCursorCalls = clearCursorCalls + 1; cursor = nil end
`;

runCase(
  'accepted and rejected destination observation',
  `${common}
local bags = { [0] = { [1] = 9001 } }
local inventory = { [13] = 8001 }
cursor = nil
local rejectDestination = false
function ItemRack.GetID(bag, slot)
  if slot then return bags[bag] and bags[bag][slot] or 0 end
  return inventory[bag] or 0
end
function CursorHasItem() return cursor ~= nil end
function PickupContainerItem(bag, slot)
  local held = cursor
  cursor = bags[bag][slot]
  bags[bag][slot] = held
end
function PickupInventoryItem(slot)
  if rejectDestination and cursor ~= nil then return end
  local held = cursor
  cursor = inventory[slot]
  inventory[slot] = held
end
`,
  String.raw`
local completed, failed = 0, 0
local result, accepted = ItemRack.StartEquipmentTransaction({
  origin = "manual_popup",
  steps = { ItemRack.NewEquipmentMove(0, 1, 13, nil) },
  onComplete = function() completed = completed + 1 end,
  onFailure = function() failed = failed + 1 end,
})
assert(result == "submitted", "accepted move must first be submitted")
assert(ItemRack.ActiveEquipmentTransaction == accepted, "submitted move must remain observable")
assert(completed == 0, "submission must not synchronously report completion")
RunTimers()
assert(accepted.status == "complete" and completed == 1 and failed == 0, "observed destination must complete once")
assert(inventory[13] == 9001 and bags[0][1] == 8001 and cursor == nil, "accepted swap must exchange exact endpoints")

bags[0][1], inventory[13], rejectDestination = 9001, 8001, true
local rejectedResult, rejected = ItemRack.StartEquipmentTransaction({
  origin = "manual_popup",
  steps = { ItemRack.NewEquipmentMove(0, 1, 13, nil) },
  onComplete = function() completed = completed + 1 end,
  onFailure = function() failed = failed + 1 end,
})
assert(rejectedResult == "submitted", "a no-op API call is still only a submission")
RunTimers()
assert(rejected.status == "failed", "unchanged endpoints must be rejected, never completed")
assert(rejected.reason == "destination_rejected", "rejection must retain a precise terminal reason")
assert(bags[0][1] == 9001 and inventory[13] == 8001, "rejected move must restore its source and preserve destination")
assert(completed == 1 and failed == 1, "each request must finalize exactly once")
assert(clearCursorCalls == 0, "normal accepted/rejected swaps must not need ClearCursor")
`
);

runCase(
  'two-hand second-step rejection rolls back offhand',
  `${common}
local bags = { [0] = { [1] = 9001, [2] = nil } }
local inventory = { [16] = 8001, [17] = 7001 }
cursor = nil
function ItemRack.GetID(bag, slot)
  if slot then return bags[bag] and bags[bag][slot] or 0 end
  return inventory[bag] or 0
end
function CursorHasItem() return cursor ~= nil end
function PickupContainerItem(bag, slot)
  local held = cursor
  cursor = bags[bag][slot]
  bags[bag][slot] = held
end
function PickupInventoryItem(slot)
  if slot == 16 and cursor == 9001 then return end
  local held = cursor
  cursor = inventory[slot]
  inventory[slot] = held
end
`,
  String.raw`
local requestResult, request = ItemRack.StartEquipmentTransaction({
  origin = "manual_popup",
  steps = {
    ItemRack.NewEquipmentMove(17, nil, 0, 2),
    ItemRack.NewEquipmentMove(0, 1, 16, nil),
  },
})
assert(requestResult == "submitted", "two-hand request must submit its first step")
RunTimers()
assert(request.status == "failed_rolled_back", "a rejected second step must explicitly roll back confirmed work")
assert(request.reason == "destination_rejected", "rollback must preserve the initiating failure")
assert(inventory[16] == 8001 and inventory[17] == 7001, "rollback must restore both original weapon slots")
assert(bags[0][1] == 9001 and bags[0][2] == nil and cursor == nil, "rollback must restore both bag sources and cursor")
assert(ItemRack.ActiveEquipmentTransaction == nil, "rolled-back request must leave no active transaction")
`
);

runCase(
  'preexisting cursor is never consumed or cleared',
  `${common}
local bags = { [0] = { [1] = 9001 } }
local inventory = { [13] = 8001 }
cursor = 1234
function ItemRack.GetID(bag, slot)
  if slot then return bags[bag] and bags[bag][slot] or 0 end
  return inventory[bag] or 0
end
function CursorHasItem() return cursor ~= nil end
function PickupContainerItem() error("must not submit with a user cursor") end
function PickupInventoryItem() error("must not submit with a user cursor") end
`,
  String.raw`
local result, request, reason = ItemRack.StartEquipmentTransaction({
  steps = { ItemRack.NewEquipmentMove(0, 1, 13, nil) },
})
assert(result == "blocked" and request == nil and reason == "cursor_occupied", "user cursor must block preflight")
assert(cursor == 1234 and clearCursorCalls == 0, "ItemRack must never clear a cursor it did not create")
assert(ItemRack.ActiveEquipmentTransaction == nil, "blocked preflight must create no transaction")
`
);

runCase(
  'multi-slot set commits only after observation and rolls back later failure',
  String.raw`
local now, timers = 0, {}
local bags = { [0] = { [1] = 9001, [2] = 9002, [3] = nil, [4] = nil } }
local inventory = { [13] = 8001, [14] = 8002 }
local cursor = nil
local rejectSlot14 = false
local prints = 0

INVSLOT_AMMO, INVSLOT_RANGED = 0, 18
C_Container = nil
ItemRackSettings = { DisableSwapSound = "OFF" }
ItemRackUser = {
  EnableQueues = "OFF",
  CurrentSet = "Base",
  Sets = {
    Base = { equip = { [13] = 8001, [14] = 8002 } },
    Test = { equip = { [13] = 9001, [14] = 9002 }, old = { [1] = 1234 }, oldset = "OriginalHistory" },
  },
}
ItemRack = {
  LockList = { [-2] = {}, [-1] = {}, [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {}, [6] = {}, [7] = {}, [8] = {}, [9] = {}, [10] = {}, [11] = {} },
  eqBackOfTheBusOffset = 100,
  Debug = function() end,
  Print = function() prints = prints + 1 end,
  SameExactID = function(a,b) return a == b end,
  MatchesStoredItemID = function(a,b) return a == b end,
  GetEnhancements = function() return 0,0,0,0,0 end,
  GetInfoByID = function(id) return "item"..tostring(id), nil, "INVTYPE_TRINKET" end,
  GetID = function(bag,slot)
    if slot then return bags[bag] and bags[bag][slot] or 0 end
    return inventory[bag] or 0
  end,
  ClearLockList = function()
    for _,list in pairs(ItemRack.LockList) do for key in pairs(list) do list[key] = nil end end
  end,
  FindItem = function(id,lock)
    for bag=0,0 do
      for slot=1,4 do
        if bags[bag][slot] == id and not ItemRack.LockList[bag][slot] then
          if lock then ItemRack.LockList[bag][slot] = 1 end
          return nil,bag,slot
        end
      end
    end
    for slot=0,19 do
      if inventory[slot] == id and not ItemRack.LockList[-2][slot] then
        if lock then ItemRack.LockList[-2][slot] = 1 end
        return slot
      end
    end
  end,
  ValidBag = function(bag) return bag == 0 end,
  IsPlayerReallyDead = function() return false end,
  MuteSwapSounds = function() end,
  ClearBurntQueueItems = function() end,
  UpdateCurrentSet = function() ItemRack.currentSetUpdates = (ItemRack.currentSetUpdates or 0) + 1 end,
  UpdateCombatQueue = function() end,
  AddToCombatQueue = function() error("no combat deferral expected") end,
}
function GetTime() return now end
C_Timer = {
  After = function(delay, callback) table.insert(timers, { due = now + delay, callback = callback }) end,
  NewTimer = function(delay, callback)
    local handle = { canceled = false }
    function handle:Cancel() self.canceled = true end
    table.insert(timers, { due = now + delay, callback = function() if not handle.canceled then callback() end end })
    return handle
  end,
}
function RunTimers()
  local count = 0
  while #timers > 0 do
    table.sort(timers, function(a,b) return a.due < b.due end)
    local timer = table.remove(timers,1)
    now = timer.due
    timer.callback()
    count = count + 1
    assert(count < 300, "set transaction timers failed to settle")
  end
end
function InCombatLockdown() return false end
function CursorHasItem() return cursor ~= nil end
function GetCursorInfo() if cursor then return "item" end end
function ClearCursor() cursor = nil end
function SpellIsTargeting() return false end
function IsInventoryItemLocked() return false end
function GetContainerNumSlots(bag) return bag == 0 and 4 or 0 end
function GetContainerItemInfo() return nil,nil,false end
function GetContainerItemLink(bag,slot) return bags[bag] and bags[bag][slot] end
function GetInventoryItemID(_,slot) return inventory[slot] end
function GetInventoryItemLink(_,slot) return inventory[slot] end
function GetItemInfo() return nil,nil,nil,nil,nil,nil,"Trinkets" end
function PickupContainerItem(bag,slot)
  local held = cursor; cursor = bags[bag][slot]; bags[bag][slot] = held
end
function PickupInventoryItem(slot)
  if rejectSlot14 and slot == 14 and cursor == 9002 then return end
  local held = cursor; cursor = inventory[slot]; inventory[slot] = held
end
function ShowHelm() end
function ShowCloak() end
`,
  `${equipSource}
local initialResult = ItemRack.EquipSet("Test")
assert(ItemRackUser.CurrentSet == "Base", "set submission must not synchronously commit CurrentSet")
assert(ItemRack.ActiveEquipmentTransaction ~= nil and ItemRack.SetSwapping == "Test", "first set step must remain observable")
RunTimers()
assert(ItemRackUser.CurrentSet == "Test", "set must commit only after every destination was observed")
assert(inventory[13] == 9001 and inventory[14] == 9002, "both requested set items must be equipped")
assert(bags[0][1] == 8001 and bags[0][2] == 8002 and cursor == nil, "both displaced items must return to exact sources")
assert(ItemRackUser.Sets.Test.old[13] == 8001 and ItemRackUser.Sets.Test.old[14] == 8002, "successful set must retain pre-transaction history")

-- Reset the world and prove a later rejected step rolls the earlier confirmed
-- step back before metadata is finalized.
bags[0][1], bags[0][2], inventory[13], inventory[14] = 9001,9002,8001,8002
ItemRackUser.CurrentSet = "Base"
ItemRackUser.Sets.Test.old = { [1] = 1234 }
ItemRackUser.Sets.Test.oldset = "OriginalHistory"
rejectSlot14 = true
prints = 0
ItemRack.EquipSet("Test")
RunTimers()
assert(ItemRackUser.CurrentSet == "Base", "failed multi-slot set must leave CurrentSet unchanged")
assert(inventory[13] == 8001 and inventory[14] == 8002, "later failure must roll back earlier confirmed set moves")
assert(bags[0][1] == 9001 and bags[0][2] == 9002 and cursor == nil, "set rollback must restore exact bag endpoints")
assert(ItemRackUser.Sets.Test.old[1] == 1234 and ItemRackUser.Sets.Test.old[13] == nil, "failed set must restore its prior history snapshot")
assert(ItemRackUser.Sets.Test.oldset == "OriginalHistory", "failed set must restore its prior oldset link")
assert(ItemRack.ActiveEquipmentTransaction == nil and ItemRack.SetSwapping == nil and ItemRack.SetSwapTimeout == nil, "failed set must leave no active transaction or watchdog")
assert(prints == 1, "failed set transaction must report exactly once")
`
);

console.log('[TRANSACTION ENGINE LUA] 30 production-Lua assertions passed.');
