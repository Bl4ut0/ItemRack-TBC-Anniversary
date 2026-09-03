const { extractFunction, runLua } = require('./lib/lua_harness');

const coreFile = 'ItemRack/ItemRack.lua';
const requestRefresh = extractFunction(coreFile, 'ItemRack.RequestInventoryRefresh');
const flushRefresh = extractFunction(coreFile, 'ItemRack.FlushInventoryRefresh');
const transactionFinalized = extractFunction(coreFile, 'ItemRack.OnEquipmentTransactionFinalized');

runLua(String.raw`
local timers = {}
local profile = 0
local buttonUpdates,menuBuilds,optionUpdates = 0,0,0
local menuVisible,optionsVisible = true,true

C_Timer = { After=function(delay,callback) table.insert(timers,callback) end }
function debugprofilestop() profile=profile+0.25; return profile end
function runTimer()
  local callback=table.remove(timers,1)
  assert(callback,"expected a scheduled refresh")
  callback()
end

ItemRackMenuFrame = { IsVisible=function() return menuVisible end }
ItemRackOptFrame = { IsVisible=function() return optionsVisible end }
ItemRackOpt = { Inv={}, UpdateInv=function() optionUpdates=optionUpdates+1 end }
for i=0,19 do ItemRackOpt.Inv[i]={ selected=(i==5) } end

ItemRack = {
  DebugTags={},
  UpdateButtons=function() buttonUpdates=buttonUpdates+1 end,
  BuildMenu=function() menuBuilds=menuBuilds+1 end,
  GetID=function(slot) return "slot:"..tostring(slot) end,
  Debug=function() end,
}

${requestRefresh}
${flushRefresh}
${transactionFinalized}

local checks = 0
local function check(value,message) assert(value,message); checks=checks+1 end

for i=1,19 do ItemRack.RequestInventoryRefresh("event_"..i) end
check(#timers == 1,"same-frame inventory burst must schedule one renderer batch")
runTimer()
check(buttonUpdates == 1 and menuBuilds == 1 and optionUpdates == 1,
  "one batch must update each visible presentation surface once")
check(ItemRack.InventoryRefreshState.lastBatchEvents == 19,
  "metrics must retain the number of coalesced source events")
check(ItemRackOpt.Inv[4].id == "slot:4" and ItemRackOpt.Inv[5].id == nil,
  "options refresh must preserve the actively selected slot")

-- Dirty state remains pending across an active/chained transaction. The final
-- transaction callback is the single point that schedules presentation work.
ItemRack.ActiveEquipmentTransaction={ id=7 }
for i=1,8 do ItemRack.RequestInventoryRefresh("transaction_event") end
check(#timers == 0,"active transaction must defer expensive presentation work")
ItemRack.ActiveEquipmentTransaction=nil
ItemRack.OnEquipmentTransactionFinalized({ status="complete" })
check(#timers == 1,"finalized transaction must release the deferred batch")
runTimer()
check(buttonUpdates == 2 and ItemRack.InventoryRefreshState.lastBatchEvents == 9,
  "transaction events and finalization must collapse into one batch")

-- If a transaction begins after scheduling but before the next frame, the
-- callback keeps the dirty bit and finalization safely reschedules it.
ItemRack.RequestInventoryRefresh("pre_transaction")
ItemRack.ActiveEquipmentTransaction={ id=8 }
runTimer()
check(buttonUpdates == 2 and ItemRack.InventoryRefreshState.dirty,
  "scheduled callback must not paint an in-flight transaction")
ItemRack.ActiveEquipmentTransaction=nil
ItemRack.OnEquipmentTransactionFinalized({ status="failed_rolled_back" })
check(#timers == 1,"deferred dirty state must reschedule after rollback")
runTimer()
check(buttonUpdates == 3,"rollback settlement must produce one final refresh")

menuVisible,optionsVisible = false,false
ItemRack.RequestInventoryRefresh("hidden_surfaces")
runTimer()
check(buttonUpdates == 4 and menuBuilds == 3 and optionUpdates == 3,
  "hidden menu and options surfaces must not be rebuilt")
check(ItemRack.InventoryRefreshState.batches == 4
  and ItemRack.InventoryRefreshState.totalMilliseconds > 0,
  "refresh metrics must record batches and measured execution time")

print(string.format("[INVENTORY REFRESH LUA] %d coalescing and transaction checks passed.",checks))
`, 'inventory-refresh');
