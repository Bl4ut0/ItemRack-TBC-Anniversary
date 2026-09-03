const { extractFunction, runLua } = require('./lib/lua_harness');

const coreFile = 'ItemRack/ItemRack.lua';
const equipFile = 'ItemRack/ItemRackEquip.lua';
const eventsFile = 'ItemRack/ItemRackEvents.lua';

const cancelPending = extractFunction(coreFile, 'ItemRack.CancelPendingQueueEquipSet');
const pendingCurrent = extractFunction(coreFile, 'ItemRack.IsPendingQueueEquipSetCurrent');
const tryPending = extractFunction(coreFile, 'ItemRack.TryEquipPendingQueueSet');
const notifyReady = extractFunction(coreFile, 'ItemRack.NotifyQueueStateReady');
const equipSet = extractFunction(equipFile, 'ItemRack.EquipSet');
const queueFrameTargets = extractFunction(eventsFile, 'ItemRack.QueueEventFrameTargets');

function runCase(name, setup, functions, assertions) {
  runLua(`${setup}\n${functions.join('\n')}\n${assertions}`, `queue-intent:${name}`);
}

let checks = 0;

runCase(
  'stale event revision cannot replay',
  `
local equipCalls, finished = 0,nil
local pending = { setname="~EventFrame:1", isEventEquipment=true, isAutomatic=true, eventFrameRevision=1 }
ItemRackUser = {
  EnableQueues="OFF",
  EventState={ revision=2 },
  Sets={ ["~EventFrame:1"]={ equip={ [13]="Old" } } },
}
ItemRack = {
  PendingQueueEquipSet=pending,
  EventFramePlanActive="~EventFrame:1",
  EventFramePlans={ ["~EventFrame:1"]={ revision=1 } },
  Debug=function() end,
  EquipSet=function() equipCalls=equipCalls+1 end,
  EventFramePlanFinished=function(setname,succeeded,reason)
    finished={ setname=setname, succeeded=succeeded, reason=reason }
  end,
}
`,
  [cancelPending, pendingCurrent, tryPending],
  `
assert(not ItemRack.TryEquipPendingQueueSet(), "stale pending event plan must not execute")
assert(equipCalls == 0, "stale pending event plan must make zero EquipSet calls")
assert(ItemRack.PendingQueueEquipSet == nil, "stale pending event plan must be removed")
assert(finished and finished.setname == "~EventFrame:1" and finished.reason == "stale_event_frame_revision",
  "stale event plan must finish through its canonical cleanup path")
`
);
checks += 4;

runCase(
  'queue readiness evaluates events before replay',
  `
local trace,equipCalls = {},0
local pending = { setname="~EventFrame:4", isEventEquipment=true, isAutomatic=true, eventFrameRevision=4 }
ItemRackUser = {
  EnableQueues="OFF",
  EventState={ revision=4 },
  Sets={ ["~EventFrame:4"]={ equip={} } },
}
ItemRack = {
  QueueStateReady=true,
  QueueStateGeneration=9,
  PendingQueueEquipSet=pending,
  EventFramePlanActive="~EventFrame:4",
  EventFramePlans={ ["~EventFrame:4"]={ revision=4 } },
  Debug=function() end,
  EquipSet=function() equipCalls=equipCalls+1; table.insert(trace,"equip") end,
  EventFramePlanFinished=function() table.insert(trace,"cancel") end,
  RunAllEvents=function()
    table.insert(trace,"events")
    ItemRackUser.EventState.revision=5
  end,
}
C_Timer={ After=function(_,callback) callback() end }
`,
  [cancelPending, pendingCurrent, tryPending, notifyReady],
  `
ItemRack.NotifyQueueStateReady()
assert(trace[1] == "events" and trace[2] == "cancel", "event truth must be evaluated before pending replay")
assert(equipCalls == 0 and ItemRack.PendingQueueEquipSet == nil,
  "event invalidation during readiness must cancel without equipping")
`
);
checks += 2;

runCase(
  'manual pending intent has precedence',
  `
local finished
ItemRackUser = {
  EnableQueues="ON",
  Sets={ Manual={ equip={ [13]="Manual" } }, ["~EventFrame:8"]={ equip={ [13]="Automatic" } } },
}
ItemRack = {
  QueueStateReady=false,
  PendingQueueEquipSet={ id=1, setname="Manual", isAutomatic=nil },
  PendingQueueRequestSequence=1,
  IsEventEquipment=true,
  EventFramePlans={ ["~EventFrame:8"]={ revision=8 } },
  Debug=function() end,
  EventFramePlanFinished=function(setname,succeeded,reason)
    finished={ setname=setname, succeeded=succeeded, reason=reason }
  end,
}
`,
  [equipSet],
  `
local result = ItemRack.EquipSet("~EventFrame:8")
assert(result == "superseded", "automatic readiness-deferred intent must yield to pending manual intent")
assert(ItemRack.PendingQueueEquipSet.setname == "Manual" and not ItemRack.PendingQueueEquipSet.isAutomatic,
  "manual pending intent must remain untouched")
assert(finished and finished.setname == "~EventFrame:8" and finished.reason == "manual_pending_precedence",
  "yielding event plan must use its normal cleanup/future-reconcile path")
`
);
checks += 3;

runCase(
  'new manual intent supersedes automatic pending intent',
  `
local canceled
local old = { id=1, setname="~EventFrame:3", isAutomatic=true, isEventEquipment=true, eventFrameRevision=3 }
ItemRackUser = {
  EnableQueues="ON",
  Sets={ Manual={ equip={ [13]="Manual" } }, ["~EventFrame:3"]={ equip={ [13]="Old" } } },
}
ItemRack = {
  QueueStateReady=false,
  PendingQueueEquipSet=old,
  PendingQueueRequestSequence=1,
  Debug=function() end,
  ScheduleQueueStateRetry=function() end,
  EventFramePlanFinished=function(setname,succeeded,reason)
    canceled={ setname=setname, succeeded=succeeded, reason=reason }
  end,
}
`,
  [cancelPending, equipSet],
  `
local result = ItemRack.EquipSet("Manual")
assert(result == "deferred", "manual request must remain pending while queue state is unresolved")
assert(ItemRack.PendingQueueEquipSet ~= old and ItemRack.PendingQueueEquipSet.setname == "Manual",
  "newest manual request must replace automatic pending work")
assert(not ItemRack.PendingQueueEquipSet.isAutomatic and not ItemRack.PendingQueueEquipSet.eventFrameRevision,
  "replacement manual request must carry no automatic provenance")
assert(canceled and canceled.reason == "newer_manual_intent",
  "superseded automatic event plan must finalize exactly once")
`
);
checks += 4;

runCase(
  'frame mutation cancels deferred plan immediately',
  `
local canceled,tries = 0,0
local state={ revision=12 }
ItemRackUser={ EventState=state }
ItemRack={
  PendingQueueEquipSet={ setname="~EventFrame:11", eventFrameRevision=11 },
  EventFrameBatchDepth=1,
  EnsureEventFrameState=function() return state end,
  CancelPendingQueueEquipSet=function(pending,reason)
    canceled=canceled+1
    assert(reason == "event_frame_revision_changed")
    ItemRack.PendingQueueEquipSet=nil
  end,
  TryReconcileEventFrames=function() tries=tries+1 end,
}
`,
  [queueFrameTargets],
  `
ItemRack.QueueEventFrameTargets({ targets={ [13]="Current" } })
assert(canceled == 1, "frame revision change must immediately cancel its readiness-deferred predecessor")
assert(ItemRack.EventFramePendingTargets[13] == "Current" and ItemRack.EventFramePendingRevision == 12,
  "latest frame targets must replace canceled work")
assert(tries == 0, "an enclosing batch must delay physical reconciliation")
`
);
checks += 3;

runCase(
  'event plan combat race never enters legacy combat queue',
  `
local lockdownChecks,finished = 0,nil
ItemRackUser = {
  EnableQueues="OFF",
  Sets={ ["~EventFrame:20"]={ equip={ [13]="Automatic" } } },
}
ItemRack = {
  IsEventEquipment=true,
  EventFramePlans={ ["~EventFrame:20"]={ revision=20 } },
  SwapList={},
  ManualQueueChoice=nil,
  Debug=function() end,
  HasActiveEquipmentTransaction=function() return false end,
  AnythingLocked=function() return false end,
  PreflightSetSwap=function() return { [13]="Automatic" } end,
  IsPlayerReallyDead=function() return false end,
  EventFramePlanFinished=function(setname,succeeded,reason)
    finished={ setname=setname, succeeded=succeeded, reason=reason }
  end,
  AddToCombatQueue=function() error("event frame must never enter anonymous CombatQueue") end,
}
function InCombatLockdown()
  lockdownChecks=lockdownChecks+1
  return lockdownChecks >= 2
end
`,
  [equipSet],
  `
local result = ItemRack.EquipSet("~EventFrame:20")
assert(result == "deferred", "combat race must defer the canonical frame plan")
assert(finished and finished.reason == "event_plan_combat", "combat race must retain a retry reason")
assert(next(ItemRack.SwapList) == nil, "deferred event plan must clear its transient swap list")
`
);
checks += 3;

runCase(
  'event plan lock race never enters legacy waiting queue',
  `
local finished
ItemRackUser = { EnableQueues="OFF", Sets={ ["~EventFrame:21"]={ equip={ [13]="Automatic" } } } }
ItemRack = {
  IsEventEquipment=true,
  EventFramePlans={ ["~EventFrame:21"]={ revision=21 } },
  Debug=function() end,
  HasActiveEquipmentTransaction=function() return false end,
  AnythingLocked=function() return true end,
  GetLockedReason=function() return "bag 0 slot 1" end,
  EventFramePlanFinished=function(setname,succeeded,reason)
    finished={ setname=setname, succeeded=succeeded, reason=reason }
  end,
  AddSetToSetsWaiting=function() error("event frame must never enter unversioned SetsWaiting") end,
}
function InCombatLockdown() return false end
`,
  [equipSet],
  `
local result = ItemRack.EquipSet("~EventFrame:21")
assert(result == "deferred", "inventory race must defer the canonical frame plan")
assert(finished and finished.reason == "event_plan_inventory_busy",
  "inventory race must retain a retry reason through frame cleanup")
`
);
checks += 2;

console.log(`[QUEUE INTENT LUA] ${checks} generation and precedence checks passed.`);
