const assert = require('assert');
const fs = require('fs');

const events = fs.readFileSync('ItemRack/ItemRackEvents.lua', 'utf8').replace(/\r\n/g, '\n');

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
  '-- Prime all events to prevent redundant swaps on login/reload',
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
  'local function EventOwnsStackLayer',
  '-- Dual-Wield Retry:'
);
const pushIndex = specialization.indexOf('ItemRack.PushEvent(eventToEquip)');
const activateIndex = specialization.indexOf(
  'events[eventToEquip].Active = EventOwnsStackLayer(eventToEquip) and true or nil'
);
check(
  pushIndex !== -1 && activateIndex > pushIndex,
  'A specialization event may become active only after PushEvent creates its stack layer.'
);
check(
  specialization.includes('if eventData.Unequip and ownsStackLayer then') &&
    specialization.includes('events[eventToEquip].Active = nil\n\t\t\tItemRack.UpdateCurrentSet()') &&
    !specialization.includes('ItemRack.IsSetEquipped(setname)'),
  'A manually equipped matching specialization set must remain inactive and must not be popped later.'
);
check(
  specialization.includes('table.insert(ItemRackUser.EventStack,eventToAdopt)') &&
    specialization.indexOf('events[eventToAdopt].Active = true') >
      specialization.indexOf('table.insert(ItemRackUser.EventStack,eventToAdopt)'),
  'Explicit specialization adoption must establish stack ownership before activation.'
);
check(
  startupOwnership.includes('if eventData.Type == "Specialization" then') &&
    startupOwnership.includes('eventData.Active = nil') &&
    startupOwnership.indexOf('if eventData.Type == "Specialization" then') <
      startupOwnership.indexOf('table.insert(ItemRackUser.EventStack, eventName)'),
  'Startup must not reconstruct specialization ownership solely from matching equipped gear.'
);

console.log(`[EVENT REGRESSION] ${checks} deferred-script and specialization ownership guards passed.`);
