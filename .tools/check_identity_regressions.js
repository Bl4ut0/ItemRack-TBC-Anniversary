const assert = require('assert');
const fs = require('fs');

const core = fs.readFileSync('ItemRack/ItemRack.lua', 'utf8');
const queue = fs.readFileSync('ItemRack/ItemRackQueue.lua', 'utf8');

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

const tooltipMembership = between(
  core,
  'function ItemRack.ListSetsHavingItem',
  'function ItemRack.InitCore'
);
check(
  tooltipMembership.includes('MatchesStoredItemFields') &&
    !tooltipMembership.includes('MatchesStoredItemID'),
  'Tooltip membership must preserve item fields instead of using a base-ID wildcard.'
);

const storedFields = between(
  core,
  'function ItemRack.MatchesStoredItemFields',
  'function ItemRack.IsRuneOnlyIdentityChange'
);
check(
  storedFields.includes('ItemRack.SameItemFields(expectedID,currentID)') &&
    storedFields.includes('ItemRack.GetRuneID(expectedID) == ItemRack.GetRuneID(currentID)'),
  'Displayed identity must preserve enchant/gem fields and exact saved rune identity.'
);

const runeUpdate = between(
  core,
  'function ItemRack.OnRuneUpdated',
  '-- takes two ItemRack-style IDs'
);
check(
  runeUpdate.includes('tonumber(runeInfo.equipmentSlot)') &&
    runeUpdate.includes('ItemRack.RefreshEquippedRuneIdentity(equipmentSlot,expectedRuneID,refreshDeadline)') &&
    !runeUpdate.includes('PendingRuneIdentityRefreshUntil'),
  'RUNE_UPDATED attribution must be scoped to Blizzard\'s affected equipment slot.'
);

const reconcile = between(
  core,
  'function ItemRack.ReconcileEquippedSnapshot',
  'function ItemRack.ScheduleEquippedStateRetry'
);
check(
  reconcile.includes('local priorRuneEquipTimer = runeIdentityChanged') &&
    reconcile.indexOf('ItemRack.RecordEquipTime(i, currentID, transitionTime)') <
      reconcile.indexOf('ItemRack.RememberRuneOnlyEquipTransition(i,previousID,currentID,priorRuneEquipTimer)') &&
    !reconcile.includes('IsRuneIdentityRefreshPending'),
  'A rune-only item-string delta must record a physical transition before it can be rolled back by the matching event.'
);
check(
  reconcile.includes('if not previousID or previousID == 0 or not ItemRack.SameExactID(previousID, currentID) then') &&
    reconcile.includes('ItemRack.RecordEquipTime(i, currentID, transitionTime)'),
  'Physical rune-copy swaps must continue through the normal equip-transition path.'
);
check(
  reconcile.includes('ItemRack.GetRecentRuneOnlyEquipTransition(i,currentID)') &&
    reconcile.includes('ItemRack.RecentRuneOnlyEquipTransitions[i] = nil'),
  'Subsequent different or empty slot transitions must invalidate recent rune rollback state.'
);

const recentTransition = between(
  core,
  'function ItemRack.RememberRuneOnlyEquipTransition',
  'function ItemRack.AdoptEquippedRuneIdentity'
);
check(
  recentTransition.includes('previousRecord = previousRecord') &&
    recentTransition.includes('recordedRecord = ItemRack.EquipTimers and ItemRack.EquipTimers[slot]') &&
    recentTransition.includes('ItemRackUser.EquipTimers[slot] = recent.previousRecord'),
  'Event-order rollback must restore the exact pre-transition equip timer.'
);
check(
  recentTransition.includes('if currentID and not ItemRack.SameExactID(recent.currentID,currentID) then') &&
    recentTransition.includes('ItemRack.RecentRuneOnlyEquipTransitions[slot] = nil'),
  'An intervening slot identity must invalidate a recent rollback record.'
);
check(
  recentTransition.includes('function ItemRack.AdvanceRecentRuneOnlyEquipTransitionRecord') &&
    (queue.match(/AdvanceRecentRuneOnlyEquipTransitionRecord/g) || []).length >= 2,
  'Async equip-timer classification must carry the exact rollback pointer forward.'
);

const runeRefresh = between(
  core,
  'function ItemRack.RefreshEquippedRuneIdentity',
  'function ItemRack.MatchesStoredItemID'
);
check(
  runeRefresh.includes('local firstSlot = equipmentSlot or 0') &&
    runeRefresh.includes('local lastSlot = equipmentSlot or 19') &&
    runeRefresh.includes('if #candidates == 1 then'),
  'A known rune event must inspect only its slot; a missing payload must require exactly one candidate.'
);
check(
  runeRefresh.indexOf('ItemRack.RollbackRuneOnlyEquipTransition') <
    runeRefresh.indexOf('ItemRack.AdoptEquippedRuneIdentity'),
  'The prior equip hold must be restored before its rune identity is adopted.'
);
check(
  runeRefresh.includes('currentRuneID == expectedRuneID') &&
    runeRefresh.includes('equipmentSlot ~= nil and unresolved and deadline and GetTime() < deadline') &&
    runeRefresh.includes('C_Timer.After(0.05'),
  'Rune refresh must verify the expected rune and retry only an unresolved known target slot.'
);
check(
  runeRefresh.includes('local fallbackIsRemoval = equipmentSlot ~= nil or expectedRuneID ~= nil') &&
    runeRefresh.includes('or currentRuneID == 0 or currentRuneID == nil'),
  'A nil event payload may infer only one unambiguous rune-removal delta.'
);
check(
  runeRefresh.includes('candidate.recent and not candidate.liveDelta and not rollbackSucceeded'),
  'A recent-only event-order recovery must not adopt when its exact timer rollback failed.'
);

const adoptRune = between(
  core,
  'function ItemRack.AdoptEquippedRuneIdentity',
  'function ItemRack.RefreshEquippedRuneIdentity'
);
check(
  adoptRune.includes('activeRecord and activeRecord.pending and ItemRack.RecordEquipTime') &&
    adoptRune.includes('ItemRack.RecordEquipTime(slot,currentID,activeRecord.transitionTime or activeRecord.time)'),
  'Adopting a rune must re-arm a legitimate pending equip hold under the new exact identity.'
);

// Deterministic model of the identity-display contract. Legacy IDs may omit
// rune metadata, but they may not omit the distinguishing item fields.
function matchesStoredFields(expected, current) {
  if (expected.fields !== current.fields) return false;
  if (expected.rune !== null) return expected.rune === current.rune;
  return true;
}

check(
  matchesStoredFields({ fields: '100:5:0:0:0:0:0:0', rune: null }, { fields: '100:5:0:0:0:0:0:0', rune: 7 }),
  'A legacy entry must tolerate missing rune metadata when every item field matches.'
);
check(
  !matchesStoredFields({ fields: '100:5:0:0:0:0:0:0', rune: null }, { fields: '100:6:0:0:0:0:0:0', rune: 7 }),
  'A different enchant must not appear as the same tooltip/set item.'
);
check(
  !matchesStoredFields({ fields: '100:5:0:0:0:0:0:0', rune: 7 }, { fields: '100:5:0:0:0:0:0:0', rune: 9 }),
  'A rune-aware saved entry must reject another rune on the same item fields.'
);
function classifyRuneDelta({ eventSlot, deltaSlot, candidateCount, expectedRune, currentRune }) {
  const scoped = eventSlot === null || eventSlot === deltaSlot;
  const unambiguous = eventSlot !== null || candidateCount === 1;
  const runeMatches = expectedRune === null || expectedRune === currentRune;
  return scoped && unambiguous && runeMatches;
}

check(
  !classifyRuneDelta({ eventSlot: 5, deltaSlot: 10, candidateCount: 1, expectedRune: 7, currentRune: 7 }),
  'A rune event for one slot must not suppress a physical copy swap in another slot.'
);
check(
  !classifyRuneDelta({ eventSlot: null, deltaSlot: 10, candidateCount: 2, expectedRune: null, currentRune: 7 }),
  'A nil rune payload must not guess between multiple simultaneous deltas.'
);
check(
  classifyRuneDelta({ eventSlot: 10, deltaSlot: 10, candidateCount: 1, expectedRune: 7, currentRune: 7 }),
  'A matching slot and rune may roll back the synthetic transition regardless of event order.'
);

console.log(`[IDENTITY REGRESSION] ${checks} item-identity guards passed.`);
