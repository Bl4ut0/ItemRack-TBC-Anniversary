const fs = require('fs');
const { extractFunction, runLua } = require('./lib/lua_harness');

const equipFile = 'ItemRack/ItemRackEquip.lua';
const coreFile = 'ItemRack/ItemRack.lua';
const iterateSwapList = extractFunction(equipFile, 'ItemRack.IterateSwapList');
const moveItem = extractFunction(equipFile, 'ItemRack.MoveItem');
const equipItemByID = extractFunction(coreFile, 'ItemRack.EquipItemByID');
const transactionModule = fs.readFileSync('ItemRack/ItemRackTransaction.lua', 'utf8');
const failSetSwap = extractFunction(equipFile, 'ItemRack.FailSetSwap');
const preflightSetSwap = extractFunction(equipFile, 'ItemRack.PreflightSetSwap');
const addToCombatQueue = extractFunction(coreFile, 'ItemRack.AddToCombatQueue');

function runCase(name, setup, functions, assertions) {
  runLua(`${setup}\n${functions.join('\n')}\n${assertions}`, `transaction:${name}`);
}

runCase(
  'full-bag empty-slot sound safety',
  `
ItemRack = {
  SwapList = { [16] = 0 }, AbortReasons = { "Not enough room." },
  eqBackOfTheBusOffset = 100, Debug = function() end,
  MuteSwapSounds = function() return nil end, ClearLockList = function() end,
  FindSpace = function() return nil end,
  Print = function() ItemRack.printCount = (ItemRack.printCount or 0) + 1 end,
}
ItemRackUser = { Sets = { Test = { equip = {}, old = {} } } }
ItemRackSettings = { DisableSwapSound = "ON" }
local sfx, writes = "1", {}
function GetCVar() return sfx end
function SetCVar(_, value) sfx = value; table.insert(writes, value) end
function InCombatLockdown() return false end
function CursorHasItem() return false end
function ClearCursor() end
function GetInventoryItemLink() return nil end
C_Timer = { NewTimer = function() error("terminal preflight must not create a mute timer") end }
`,
  [failSetSwap, iterateSwapList],
  `
ItemRack.IterateSwapList("Test", false)
assert(ItemRack.AbortSwap == 1, "no-space must remain an explicit terminal reason")
assert(next(ItemRack.SwapList) == nil, "terminal no-space must clear all pending swap work")
assert(ItemRack.SetSwapping == nil and ItemRack.SetSwapTimeout == nil, "terminal no-space must create no watchdog state")
assert(ItemRack.printCount == 1, "terminal no-space must report exactly once")
assert(sfx == "1", "no-space must never leave global SFX muted")
assert(#writes == 0, "safe sound suppression must not modify global SFX")
`
);

runCase(
  'locked offhand sound safety',
  `
ItemRack = {
  CombatQueue = {}, Debug = function() end, ClearManualQueueChoice = function() end,
  SetManualQueueChoice = function() end, IsPlayerReallyDead = function() return false end,
  MatchesStoredItemID = function(a,b) return a == b end,
  GetID = function(bag, slot)
    if slot then return 9001 end
    if bag == 16 then return 8001 end
    if bag == 17 then return 7001 end
    return 0
  end,
  MuteSwapSounds = function() return nil end,
  GetInfoByID = function() return "Two-hander", nil, "INVTYPE_2HWEAPON" end,
  FindSpace = function() return 0, 2 end,
  AnythingLocked = function() return false end,
  HasActiveEquipmentTransaction = function() return false end,
  AddToCombatQueue = function(slot, id) ItemRack.CombatQueue[slot] = id end,
}
ItemRackSettings = { DisableSwapSound = "ON" }
local sfx, writes = "1", {}
function GetCVar() return sfx end
function SetCVar(_, value) sfx = value; table.insert(writes, value) end
function InCombatLockdown() return false end
function GetCursorInfo() return nil end
function SpellIsTargeting() return false end
function GetContainerItemInfo() return nil, nil, false end
function IsInventoryItemLocked(slot) return slot == 17 end
function GetInventoryItemLink(_, slot) if slot == 17 then return "offhand" end end
function GetContainerItemLink() return "twohand" end
function GetItemInfo() return nil,nil,nil,nil,nil,nil,"Two-Handed Swords" end
function PickupContainerItem() error("locked offhand must defer before pickup") end
function PickupInventoryItem() error("locked offhand must defer before pickup") end
C_Timer = { NewTimer = function() error("deferred preflight must not create a mute timer") end }
`,
  [equipItemByID],
  `
ItemRack.EquipItemByID(9001, 16, true, 0, 1)
assert(ItemRack.CombatQueue[16] == 9001, "locked offhand request must be deferred")
assert(sfx == "1", "locked offhand deferral must not leave global SFX muted")
assert(#writes == 0, "safe sound suppression must not modify global SFX")
`
);

runCase(
  'manual occupied destination completes cursor transaction',
  `
local bags = { [0] = { [1] = 9001 } }
local inventory = { [13] = 8001 }
local cursor = nil
local now, timers = 0, {}
ItemRack = {
  CombatQueue = {}, PhantomItem = {}, AbortSwap = nil, Debug = function() end,
  ClearManualQueueChoice = function() end, SetManualQueueChoice = function() end,
  IsPlayerReallyDead = function() return false end,
  MatchesStoredItemID = function(a,b) return a == b end,
  SameExactID = function(a,b) return a == b end,
  GetID = function(bag, slot)
    if slot then return bags[bag] and bags[bag][slot] or 0 end
    return inventory[bag] or 0
  end,
  GetInfoByID = function() return "Trinket", nil, "INVTYPE_TRINKET" end,
  MuteSwapSounds = function() return nil end, FindSpace = function() return 0, 2 end,
  AddToCombatQueue = function(slot, id) ItemRack.CombatQueue[slot] = id end,
  AnythingLocked = function() return false end,
}
ItemRackSettings = { DisableSwapSound = "OFF" }
INVSLOT_AMMO, INVSLOT_RANGED = 0, 18
function InCombatLockdown() return false end
function GetCursorInfo() if cursor then return "item" end end
function CursorHasItem() return cursor ~= nil end
function ClearCursor() cursor = nil end
function SpellIsTargeting() return false end
function GetContainerItemInfo(bag, slot)
  return nil,nil,false,nil,nil,nil,nil,nil,nil,bags[bag] and bags[bag][slot]
end
function IsInventoryItemLocked() return false end
function GetInventoryItemID(_, slot) return inventory[slot] end
function GetInventoryItemLink(_, slot) return inventory[slot] and tostring(inventory[slot]) or nil end
function GetContainerItemLink(bag, slot) return bags[bag][slot] and tostring(bags[bag][slot]) or nil end
function GetItemInfo() return nil,nil,nil,nil,nil,nil,"Trinkets" end
function PickupContainerItem(bag, slot)
  local held = cursor; cursor = bags[bag][slot]; bags[bag][slot] = held
end
function PickupInventoryItem(slot)
  local held = cursor; cursor = inventory[slot]; inventory[slot] = held
end
function GetCVar() return "1" end
function SetCVar() error("sound is disabled for this case") end
function GetTime() return now end
C_Timer = {
  After = function(delay, callback) table.insert(timers, { due = now + delay, callback = callback }) end,
  NewTimer = function() error("no mute timer expected") end,
}
function RunTimers()
  local count = 0
  while #timers > 0 do
    table.sort(timers, function(a,b) return a.due < b.due end)
    local timer = table.remove(timers, 1)
    now = timer.due
    timer.callback()
    count = count + 1
    assert(count < 100, "transaction timers failed to settle")
  end
end
`,
  [transactionModule, moveItem, equipItemByID],
  `
local result = ItemRack.EquipItemByID(9001, 13, false, 0, 1)
assert(result == "submitted", "manual move must remain submitted until observed")
RunTimers()
assert(inventory[13] == 9001, "requested item must reach equipment destination")
assert(bags[0][1] == 8001, "displaced item must return to exact source")
assert(cursor == nil, "completed manual swap must leave cursor empty")
assert(ItemRack.ActiveEquipmentTransaction == nil, "observed manual swap must finalize its transaction")
assert(ItemRack.AbortSwap == nil, "successful manual swap must not abort")
`
);

runCase(
  'set preflight is atomic for missing duplicate and no-space targets',
  `
local bags = { [0] = { [1] = 9001, [2] = 6001 } }
local inventory = { [13] = 8001, [14] = 8002 }
local pickupCalls = 0
ItemRackUser = {
  CurrentSet = "Base",
  Sets = {
    Mixed = { equip = { [13] = 9001, [14] = 9999 }, old = { [13] = 7777 }, oldset = "Older" },
    Duplicate = { equip = { [13] = 9001, [14] = 9001 } },
    Empty = { equip = { [13] = 0 } },
  },
}
ItemRack = {
  LockList = { [-2] = {}, [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} },
  HasTitansGrip = false, NoTitansGrip = {},
  MatchesStoredItemID = function(a,b) return a == b end,
  GetID = function(bag,slot)
    if slot then return bags[bag] and bags[bag][slot] or 0 end
    return inventory[bag] or 0
  end,
  ClearLockList = function()
    for _,list in pairs(ItemRack.LockList) do for key in pairs(list) do list[key] = nil end end
  end,
  FindItem = function(id,lock)
    for bag=0,0 do
      for slot=1,2 do
        if bags[bag][slot] == id and not ItemRack.LockList[bag][slot] then
          if lock then ItemRack.LockList[bag][slot] = 1 end
          return nil,bag,slot
        end
      end
    end
  end,
  ValidBag = function(bag) return bag == 0 end,
  GetInfoByID = function(id) return "item"..tostring(id), nil, "INVTYPE_TRINKET" end,
}
function GetContainerNumSlots(bag) return bag == 0 and 2 or 0 end
function GetContainerItemLink(bag,slot) return bags[bag] and bags[bag][slot] end
function GetInventoryItemLink(_,slot) return inventory[slot] end
function PickupContainerItem() pickupCalls = pickupCalls + 1 end
function PickupInventoryItem() pickupCalls = pickupCalls + 1 end
function GetItemInfo() return nil,nil,nil,nil,nil,nil,"Trinkets" end
`,
  [preflightSetSwap],
  `
local mixed, mixedReason, missing = ItemRack.PreflightSetSwap("Mixed")
assert(mixed == nil and string.match(mixedReason,"^missing_items"), "one absent set item must fail the whole preflight")
assert(#missing == 1 and missing[1].slot == 14, "preflight must enumerate the unsatisfied slot")
assert(ItemRackUser.Sets.Mixed.old[13] == 7777 and ItemRackUser.Sets.Mixed.oldset == "Older", "failed preflight must not mutate history")
assert(ItemRackUser.CurrentSet == "Base" and pickupCalls == 0, "failed preflight must not mutate gear or CurrentSet")

local duplicate, duplicateReason = ItemRack.PreflightSetSwap("Duplicate")
assert(duplicate == nil and string.match(duplicateReason,"^missing_items"), "one physical copy cannot satisfy two requested slots")

local empty, emptyReason = ItemRack.PreflightSetSwap("Empty")
assert(empty == nil and string.match(emptyReason,"^no_space"), "full bags plus an empty target must fail before submission")
assert(pickupCalls == 0, "all terminal preflight failures must make zero pickup calls")
`
);

runCase(
  'already-worn intent cancels stale combat queue entry',
  `
ItemRack = {
  CombatQueue = { [13] = 8001 },
  AutoQueueFlag = { [13] = true },
  AutoQueueOwner = { [13] = "OldEvent" },
  GetEquippedSlotState = function() return "resolved", 9001 end,
  MatchesStoredItemID = function(a,b) return a == b end,
  ClearCombatQueueMetadata = function(slot)
    ItemRack.AutoQueueFlag[slot] = nil
    ItemRack.AutoQueueOwner[slot] = nil
  end,
  UpdateCombatQueue = function() ItemRack.updateCount = (ItemRack.updateCount or 0) + 1 end,
  GetActiveQueueOwner = function() return "NewEvent" end,
  GetInfoByID = function(id) return tostring(id) end,
  Debug = function() end,
}
`,
  [addToCombatQueue],
  `
ItemRack.AddToCombatQueue(13,9001,true)
assert(ItemRack.CombatQueue[13] == nil, "already-worn intent must cancel an older conflicting queued item")
assert(ItemRack.AutoQueueFlag[13] == nil and ItemRack.AutoQueueOwner[13] == nil, "stale queue provenance must be cleared")
assert(ItemRack.updateCount == 1, "queue overlay must refresh exactly once")
`
);

console.log('[LUA TRANSACTION] 25 production-Lua transaction assertions passed.');
