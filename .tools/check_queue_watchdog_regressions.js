const assert = require('assert');
const fs = require('fs');

const queue = fs.readFileSync('ItemRack/ItemRackQueue.lua', 'utf8');
const equip = fs.readFileSync('ItemRack/ItemRackEquip.lua', 'utf8');

let checks = 0;
function check(condition, message) {
  assert.ok(condition, message);
  checks += 1;
}

function between(source, start, end) {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notStrictEqual(startIndex, -1, `Missing start marker: ${start}`);
  assert.notStrictEqual(endIndex, -1, `Missing end marker: ${end}`);
  return source.slice(startIndex, endIndex);
}

const queueMatcher = between(
  queue,
  'function ItemRack.FindQueueEntryIndex',
  'function ItemRack.IsManualQueueChoice'
);
check(
  queueMatcher.indexOf('ItemRack.SameExactID') < queueMatcher.lastIndexOf('return legacyFallback'),
  'Queue matching must check exact identity before returning a legacy fallback.'
);
check(
  queueMatcher.includes('ItemRack.IsQueueEntryUnambiguous(list,i)'),
  'Legacy queue matching must reject an ambiguous same-base wildcard.'
);

const autoQueue = between(
  queue,
  'function ItemRack.AutoQueueItemToEquip',
  'function ItemRack.ItemNearReady'
);
check(
  autoQueue.indexOf('ItemRack.IsQueueEntryUnambiguous(list,i)') < autoQueue.indexOf('ItemRack.FindItemInBags(entryID)'),
  'AutoQueue must reject an ambiguous legacy entry before looking in bags.'
);

const manualAdvance = between(
  queue,
  'function ItemRack.ManualQueueAdvance',
  'function ItemRack.GetDefaultSwapIn'
);
check(
  manualAdvance.includes('ItemRack.FindQueueEntryIndex(list,equippedExactID)') &&
    manualAdvance.indexOf('ItemRack.IsQueueEntryUnambiguous(list,index)') < manualAdvance.indexOf('ItemRack.FindItemInBags(itemID)'),
  'Manual queue cycling must start from exact identity and skip ambiguous legacy candidates.'
);

const setEquipped = between(
  equip,
  'function ItemRack.IsSetEquipped',
  'function ItemRack.UnequipSet'
);
check(
  setEquipped.includes('ItemRack.FindQueueEntryIndex(slotQueue,id)') &&
    !setEquipped.includes('matchesStored(slotQueue[q].id, id)'),
  'Queue-aware set detection must not revive an ambiguous legacy rune wildcard.'
);

const waitingWatchdog = between(
  equip,
  'function ItemRack.StartSetsWaitingWatchdog',
  'function ItemRack.PauseAutomaticSwapForWorldTransition'
);
check(
  waitingWatchdog.includes('local ordinarySwapBlocked = ItemRack.SetSwapping or ItemRack.NowCasting') &&
    waitingWatchdog.includes('not ordinarySwapBlocked and hardLocked'),
  'SetsWaiting timeout must require a real lock after casting/set-swap blockers clear.'
);

const waitingDedupe = between(
  equip,
  'function ItemRack.AddSetToSetsWaiting',
  'function ItemRack.OrderSwaps'
);
check(
  /if not incomingAutomatic then[\s\S]*request\[5\] = nil[\s\S]*request\[6\] = nil[\s\S]*request\[7\] = nil/.test(waitingDedupe),
  'A duplicate manual request must replace automatic/deferred/watchdog provenance.'
);
check(
  /table\.remove\(wait,i\)[\s\S]*table\.insert\(wait,request\)/.test(waitingDedupe),
  'A fresh manual duplicate must become the newest waiting request.'
);

// Deterministic behavior model for the migration boundary. These cases state
// the compatibility contract independently of queue order or bag scan order.
const legacy = (base) => ({ base, rune: null });
const rune = (base, runeID) => ({ base, rune: runeID });
const exact = (left, right) => left.base === right.base && left.rune === right.rune;

function hasExplicitRune(entries, base) {
  return entries.some((entry) => entry && entry.rune !== null && entry.base === base);
}

function unambiguous(entries, index) {
  const entry = entries[index];
  return entry && (entry.rune !== null || !hasExplicitRune(entries, entry.base));
}

function findCurrent(entries, current) {
  const exactIndex = entries.findIndex((entry) => entry && exact(entry, current));
  if (exactIndex !== -1) return exactIndex;
  return entries.findIndex((entry, index) =>
    entry && entry.rune === null && unambiguous(entries, index) && entry.base === current.base
  );
}

function firstCarriedCandidate(entries, carried) {
  return entries.findIndex((entry, index) =>
    entry && unambiguous(entries, index) && carried.some((item) =>
      exact(entry, item) || (entry.rune === null && entry.base === item.base)
    )
  );
}

const mixed = [legacy(100), rune(100, 7), rune(100, 9)];
check(findCurrent(mixed, rune(100, 9)) === 2, 'An exact rune match must win after an earlier wildcard.');
check(findCurrent(mixed, rune(100, 11)) === -1, 'An unlisted rune must not match a wildcard beside rune entries.');
check(firstCarriedCandidate(mixed, [rune(100, 9), rune(100, 7)]) === 1, 'Candidate choice must follow explicit queue order, not bag order.');
check(findCurrent([legacy(100)], rune(100, 9)) === 0, 'A legacy-only profile must retain base-ID compatibility.');
check(firstCarriedCandidate([legacy(100)], [rune(100, 9)]) === 0, 'A legacy-only candidate must retain base-ID bag lookup.');

function timeoutEligible({ automaticBlock, setSwapping, casting, hardLock, elapsed, limit }) {
  return !automaticBlock && !setSwapping && !casting && hardLock && elapsed >= limit;
}
check(!timeoutEligible({ automaticBlock: false, setSwapping: false, casting: true, hardLock: false, elapsed: 60, limit: 10 }), 'Casting alone must never expire SetsWaiting.');
check(!timeoutEligible({ automaticBlock: false, setSwapping: true, casting: false, hardLock: true, elapsed: 60, limit: 10 }), 'An ordinary set swap must suspend the SetsWaiting lock budget.');
check(timeoutEligible({ automaticBlock: false, setSwapping: false, casting: false, hardLock: true, elapsed: 10, limit: 10 }), 'A persistent real lock must remain bounded.');

console.log(`[QUEUE/WATCHDOG] ${checks} deterministic guards passed.`);
