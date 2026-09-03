const assert = require('assert');
const fs = require('fs');

const events = fs.readFileSync('ItemRack/ItemRackEvents.lua', 'utf8').replace(/\r\n/g, '\n');
const eventState = fs.readFileSync('ItemRack/ItemRackEventState.lua', 'utf8').replace(/\r\n/g, '\n');

function between(source, start, end) {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notStrictEqual(startIndex, -1, `Missing start marker: ${start}`);
  assert.notStrictEqual(endIndex, -1, `Missing end marker: ${end}`);
  return source.slice(startIndex, endIndex);
}

let checks = 0;
function check(condition, message) {
  assert.ok(condition, message);
  checks += 1;
}

const deferredScripts = between(
  events,
  'local deferredScriptEventLimit',
  'function ItemRack.ProcessingFrameOnEvent'
);
const processingFrame = between(
  events,
  'function ItemRack.ProcessingFrameOnEvent',
  '--[[ Event processing ]]'
);

const startupOwnership = between(
  events,
  '-- Rehydrate Active as a compatibility/UI projection from canonical frames.',
  'if ItemRackButton20Queue then'
);

check(
  deferredScripts.includes('local deferredScriptEventLimit = 64') &&
    deferredScripts.includes('if #queue >= deferredScriptEventLimit then') &&
    deferredScripts.includes('table.remove(queue,1)'),
  'Deferred Script triggers must use a bounded FIFO queue.'
);
check(
  processingFrame.includes('QueueDeferredScriptEvent(event,...)'),
  'Blocked game events must preserve enabled Script triggers and their arguments.'
);
check(
  deferredScripts.includes('a1,a2,a3,a4,a5,a6,a7,a8,a9,a10 = CombatLogGetCurrentEventInfo()'),
  'Combat-log arguments must be captured at receipt time rather than replay time.'
);
check(
  deferredScripts.includes('ItemRack.DeferredScriptEvents = {}') &&
    deferredScripts.includes('ProcessScriptTriggers(pending.event,pending.args)') &&
    !deferredScripts.includes('ProcessingFrameOnEvent('),
  'Replay must drain a snapshot and invoke only Script triggers, not built-in state processing.'
);

const specialization = between(
  events,
  'function ItemRack.ProcessSpecializationEvent(force)',
  '-- Dual-Wield Retry:'
);
check(
  specialization.includes('table.sort(names)') &&
    specialization.includes('local exits,entries = {},{}') &&
    specialization.includes('for _,eventName in ipairs(exits) do ItemRack.PopEvent(eventName) end') &&
    specialization.includes('for _,eventName in ipairs(entries) do'),
  'Specialization transitions must collect, sort, and batch every matching event.'
);
check(
  specialization.includes('local ownsFrame = state.byEvent[eventName] ~= nil') &&
    specialization.includes('events[eventName].Active = state.byEvent[eventName] and true or nil') &&
    !specialization.includes('ItemRack.IsSetEquipped(setname)'),
  'Specialization Active state must follow canonical ownership rather than physical set matching.'
);
check(
  specialization.includes('not preserveRequestedSet or setname == preserveRequestedSet') &&
    specialization.includes('retrySets[preserveRequestedSet] = true'),
  'Explicit associated-set intent must suppress different destination specialization defaults.'
);
check(
  startupOwnership.includes('eventState.frames[frameId]') &&
    startupOwnership.includes('eventData.Active = true') &&
    !startupOwnership.includes('ItemRack.IsSetEquipped'),
  'Startup must project persisted frame ownership and never reconstruct it from matching gear.'
);

const popEvent = between(
  events,
  'function ItemRack.PopEvent(eventName, expectedGeneration)',
  '--[[ Event processing ]]'
);
check(
  popEvent.includes('ItemRack.EventFrames.Pop(state,eventName,generation)') &&
    popEvent.includes('if not result.removed then') &&
    !popEvent.includes('ItemRack.UnequipSet'),
  'PopEvent must use canonical generation-bound frame ownership and never legacy set restoration.'
);
check(
  eventState.includes('higherSlot.prior = removedSlot.prior') &&
    eventState.includes('targets[slot] = restore'),
  'Buried frame removal must transfer history to a higher slot owner and restore only uncovered slots.'
);
check(
  popEvent.includes('ItemRack.QueueEventFrameTargets(result,disableSound)') &&
    popEvent.includes('ItemRack.ClearScriptEventState(eventName,generation)'),
  'A successful pop must coalesce its physical plan and clear only matching script generation state.'
);
check(eventState.includes('nextFrameId = 1'), 'Every activation must receive a unique frame identity.');
check(eventState.includes('frame.eventGeneration ~= eventGeneration'), 'Stale generations must be total no-ops.');
check(eventState.includes('table.insert(state.order,insertIndex,frameId)'), 'Underlying Zone frames must support logical insertion below mount owners.');
check(eventState.includes('function EventFrames.ReleaseSlots'), 'Manual equipment intent must be able to relinquish automatic slot ownership.');

const stance = between(
  events,
  'function ItemRack.ProcessStanceEvent()',
  'local mountZoneRecheckPending'
);
check(
  stance.includes('table.sort(names)') &&
    stance.includes('local exits,entries = {},{}') &&
    stance.includes('ItemRack.BeginEventFrameBatch()'),
  'Stance processing must deterministically batch all matching transitions.'
);

const buff = between(
  events,
  'local function ScheduleOnMovementRecheck',
  'local prevIcon, prevText'
);
check(
  buff.includes('ItemRack.PendingOnMovementGeneration') &&
    buff.includes('ItemRack.OnMovementGeneration ~= expectedGeneration') &&
    !buff.includes('PendingOnMovementUnequip'),
  'OnMovement debounce must use one generation-bound full re-evaluation, not one event-name slot.'
);
check(
  buff.includes('table.sort(names)') &&
    buff.includes('for _,eventName in ipairs(exits) do ItemRack.PopEvent(eventName) end') &&
    buff.includes('for _,eventName in ipairs(entries) do'),
  'Buff processing must collect and batch every transition in deterministic order.'
);

console.log(`[EVENT REGRESSION] ${checks} script, specialization, and event ownership guards passed.`);
