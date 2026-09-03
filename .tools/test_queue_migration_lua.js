const assert = require('assert');
const fs = require('fs');
const { runLua } = require('./lib/lua_harness');

const migration = fs.readFileSync('ItemRack/ItemRackQueueMigration.lua', 'utf8');
const toc = fs.readFileSync('ItemRack/ItemRack.toc', 'utf8');
const core = fs.readFileSync('ItemRack/ItemRack.lua', 'utf8');
const options = fs.readFileSync('ItemRackOptions/ItemRackOptions.lua', 'utf8');

runLua(String.raw`
ItemRack = {}
${migration}

local checks = 0
local function check(value,message) assert(value,message); checks = checks + 1 end
local function baseID(id)
  return string.match(tostring(id or ""),"^%-?(%d+)")
end
local function countReason(records,reason)
  local count = 0
  for _,record in ipairs(records or {}) do
    if record.reason == reason then count = count + 1 end
  end
  return count
end

-- Direct pre-v4.29.8 upgrade: legacy scalar entries receive the account-wide
-- defaults that were formerly stored only in ItemRackItems.
do
  local legacy = {
    ["111"]={ priority=1, delay=7, swapOnUse=1, extra={ source="legacy" } },
    ["222"]={ keep=1 },
  }
  local user = {
    Queues={ [13]={ 111, 0, "222:5" } },
    Sets={},
  }
  local report = ItemRack.QueueMigration.Migrate(user,legacy,baseID,function() return 1234 end)
  check(user.QueueSchemaVersion == 2, "direct upgrades must record schema v2")
  check(report.fromVersion == 0 and report.toVersion == 2,
    "migration report must record its version boundary")
  check(report.entriesVisited == 3 and report.entriesChanged == 3,
    "every legacy scalar entry, including the stop sentinel, must be visited")
  check(user.Queues[13][1].id == 111 and user.Queues[13][1].priority == true and
    user.Queues[13][1].keep == false and user.Queues[13][1].delay == 7,
    "legacy priority and delay metadata must be recovered")
  check(user.Queues[13][1].swapOnUse == 1 and
    user.Queues[13][1].extra.source == "legacy" and
    user.Queues[13][1].extra ~= legacy["111"].extra,
    "unknown legacy queue metadata must transfer without sharing mutable tables")
  check(user.Queues[13][2].id == 0 and user.Queues[13][2].priority == false and
    user.Queues[13][2].keep == false and user.Queues[13][2].delay == 0,
    "the queue stop sentinel must be normalized without item metadata")
  check(user.Queues[13][3].id == "222:5" and user.Queues[13][3].keep == true,
    "extended item strings must look up metadata by base item ID")
  check(user.QueueMigrationBackup.capturedAt == 1234 and
    user.QueueMigrationBackup.global[13][1] == 111,
    "the original scalar queue must be recoverable from a pre-mutation backup")
  check(legacy["111"].priority == 1 and legacy["222"].keep == 1,
    "migration must leave account-wide ItemRackItems recovery data untouched")
end

-- The failed first-entry heuristic could leave a profile half converted. Audit
-- every entry even when schema v2 is already recorded, while preserving fields
-- explicitly chosen by the user and extension fields unknown to the migrator.
do
  local first = { id="333", priority=false, custom="preserve" }
  local user = {
    QueueSchemaVersion=2,
    Queues={
      [13]={ first, "444" },
    },
    QueuesEnabled={ ["13"]="ON" },
    Sets={
      Travel={
        Queues={ [14]={ [1]={ id="555", keep=false, delay=2 }, [4]=666 } },
        QueuesEnabled={ ["14"]="OFF" },
      },
    },
  }
  local legacy = {
    ["333"]={ priority=1, keep=1, delay=9 },
    ["444"]={ priority=1 },
    ["555"]={ keep=1 },
    ["666"]={ delay=4 },
  }
  local report = ItemRack.QueueMigration.Migrate(user,legacy,baseID)
  check(report.queuesVisited == 2 and report.entriesVisited == 4,
    "mixed global and per-set queues must be fully traversed")
  check(user.Queues[13][1] == first and first.priority == false and
    first.keep == true and first.delay == 9 and first.custom == "preserve",
    "explicit fields and unknown fields must survive while missing fields are filled")
  check(user.Queues[13][2].id == "444" and user.Queues[13][2].priority == true,
    "a scalar after a table entry must still migrate")
  check(user.Sets.Travel.Queues[14][1].id == "555" and
    user.Sets.Travel.Queues[14][1].keep == false,
    "explicit false values in per-set queues must not inherit legacy truthy values")
  check(user.Sets.Travel.Queues[14][2].id == 0 and
    user.Sets.Travel.Queues[14][3].id == 666 and
    user.Sets.Travel.Queues[14][3].delay == 4,
    "sparse per-set suffixes must remain behind an inserted stop boundary")
  check(report.queuesCompacted == 1,
    "sparse queue compaction must be visible in the migration report")
  check(report.boundariesInserted == 1,
    "repair must disclose the safety boundary inserted at a sparse gap")
  check(user.QueuesEnabled[13] == true and user.QueuesEnabled["13"] == nil and
    user.Sets.Travel.QueuesEnabled[14] == false,
    "numeric-string enabled keys and legacy boolean spellings must canonicalize")
  check(user.QueueMigrationBackup == nil,
    "already-versioned mixed-schema repair must not invent an inaccurate pre-v2 backup")
end

-- Corrupt entries are retained in quarantine instead of being silently lost;
-- corrupt queue containers are replaced with safe empty tables.
do
  local user = {
    Queues={
      [13]={ [1]=111, [3]=false, [5]={ note="missing id" }, [7]="777", label="keep" },
      [14]=false,
      note="keep-root-property",
    },
    Sets={ Broken={ Queues="not-a-table" } },
  }
  local report = ItemRack.QueueMigration.Migrate(user,{},baseID)
  check(#user.Queues[13] == 3 and user.Queues[13][1].id == 111 and
    user.Queues[13][2].id == 0 and user.Queues[13][3].id == "777",
    "valid suffix entries must survive behind a fail-closed stop boundary")
  check(user.Queues[13].label == "keep" and user.Queues.note == "keep-root-property",
    "non-list extension properties must not be destroyed")
  check(type(user.Queues[14]) == "table" and next(user.Queues[14]) == nil and
    type(user.Sets.Broken.Queues) == "table" and next(user.Sets.Broken.Queues) == nil,
    "invalid global and per-set queue containers must become safe empty tables")
  check(report.entriesQuarantined == 2 and report.queuesQuarantined == 2,
    "entry and container quarantine totals must be reported separately")
  check(report.boundariesInserted == 1,
    "the first corrupt active-prefix entry must insert exactly one safety boundary")
  check(#user.QueueMigrationQuarantine == 4 and
    countReason(user.QueueMigrationQuarantine,"invalid_entry_type") == 1 and
    countReason(user.QueueMigrationQuarantine,"missing_id") == 1 and
    countReason(user.QueueMigrationQuarantine,"invalid_queue") == 1 and
    countReason(user.QueueMigrationQuarantine,"invalid_queue_root") == 1,
    "every rejected value must retain a reasoned quarantine record")
  check(user.QueueMigrationBackup.global[14] == false and
    user.QueueMigrationBackup.sets.Broken == "not-a-table",
    "the backup must precede all container repair")

  local backup = user.QueueMigrationBackup
  local quarantineCount = #user.QueueMigrationQuarantine
  local first = user.Queues[13][1]
  local rerun = ItemRack.QueueMigration.Migrate(user,{},baseID)
  check(rerun.entriesChanged == 0 and rerun.entriesQuarantined == 0 and
    rerun.queuesQuarantined == 0,
    "a second pass over canonical data must be idempotent")
  check(user.QueueMigrationBackup == backup and
    #user.QueueMigrationQuarantine == quarantineCount and user.Queues[13][1] == first,
    "idempotence must preserve the first backup, quarantine, and entry identities")

  user.Queues[13][4] = "888"
  local repair = ItemRack.QueueMigration.Migrate(user,{},baseID)
  check(repair.entriesChanged == 1 and user.Queues[13][4].id == "888",
    "schema-v2 profiles must still repair scalar entries introduced by partial upgrades")
  check(user.QueueMigrationBackup == backup,
    "later mixed-schema repair must not overwrite the original backup")
end

do
  local user = {
    Queues={
      ["13"]={ "from-string-key" },
      [14]={ "canonical-wins" },
      ["14"]={ "duplicate-must-not-merge" },
    },
    QueuesEnabled={ ["13"]="1", [14]=true, ["14"]="0", [15]={ bad=true } },
    Sets={ BrokenEnabled={ QueuesEnabled="not-a-table" } },
  }
  local report = ItemRack.QueueMigration.Migrate(user,{},baseID)
  check(user.Queues[13][1].id == "from-string-key" and user.Queues["13"] == nil,
    "an unambiguous numeric-string queue slot must move to its numeric key")
  check(user.Queues[14][1].id == "canonical-wins" and user.Queues["14"] == nil,
    "a numeric queue slot must win over its duplicate string key")
  check(user.QueuesEnabled[13] == true and user.QueuesEnabled[14] == true and
    user.QueuesEnabled[15] == false,
    "enabled values must canonicalize, with malformed values failing closed")
  check(type(user.Sets.BrokenEnabled.QueuesEnabled) == "table" and
    next(user.Sets.BrokenEnabled.QueuesEnabled) == nil,
    "a malformed per-set enabled root must become a safe empty table")
  check(report.slotKeysNormalized == 2 and report.slotKeysQuarantined == 2 and
    report.enabledValuesQuarantined == 1 and report.queuesQuarantined == 1,
    "slot-key collisions and enabled-state repairs must be fully reported")
  check(countReason(user.QueueMigrationQuarantine,"duplicate_slot_key") == 2 and
    countReason(user.QueueMigrationQuarantine,"invalid_enabled_value") == 1,
    "collided and malformed enabled data must remain inspectable in quarantine")
  check(user.QueueMigrationBackup.global["13"][1] == "from-string-key" and
    user.QueueMigrationBackup.globalEnabled[15].bad == true and
    user.QueueMigrationBackup.setsEnabled.BrokenEnabled == "not-a-table",
    "queue and enabled-state backups must preserve every pre-repair shape")
end

do
  local user = { Queues={ [13]={ "999" } }, Sets={} }
  local report = ItemRack.QueueMigration.Migrate(user,"malformed legacy root",baseID)
  check(report.legacySettingsAvailable == false and user.Queues[13][1].id == "999",
    "a malformed legacy metadata root must not abort scalar conversion")
  user = { Queues={ [13]={ "999" } }, Sets={} }
  ItemRack.QueueMigration.Migrate(user,{ ["999"]="malformed item metadata" },baseID)
  check(user.Queues[13][1].priority == false and user.Queues[13][1].delay == 0,
    "a malformed legacy metadata value must safely fall back to defaults")
end

do
  local user = { Queues=false, Sets={} }
  local report = ItemRack.QueueMigration.Migrate(user,{},baseID)
  check(type(user.Queues) == "table" and report.queuesQuarantined == 1 and
    user.QueueMigrationQuarantine[1].reason == "invalid_queue_root",
    "a corrupt global queue root must be backed up, quarantined, and made safe")
end

do
  local user = {
    QueueMigrationBackup="damaged earlier backup",
    Queues={ [13]={ "1010" } },
    Sets={},
  }
  ItemRack.QueueMigration.Migrate(user,{},baseID,function() return 5678 end)
  check(user.UnknownQueueMigrationBackup == "damaged earlier backup" and
    type(user.QueueMigrationBackup) == "table" and
    user.QueueMigrationBackup.capturedAt == 5678 and
    user.QueueMigrationBackup.global[13][1] == "1010",
    "a malformed earlier backup must be preserved while a usable snapshot is captured")
end

do
  local user = { Sets={} }
  local report = ItemRack.QueueMigration.Migrate(user,{},baseID)
  check(type(user.Queues) == "table" and report.queuesQuarantined == 0 and
    user.QueueMigrationQuarantine == nil,
    "a fresh profile with no queues must initialize without a false corruption record")
end

do
  local original = { "future-entry" }
  local user = { QueueSchemaVersion=99, Queues={ [13]=original }, Sets={} }
  local report = ItemRack.QueueMigration.Migrate(user,{},baseID)
  check(report.skipped == "future_schema" and user.QueueSchemaVersion == 99 and
    user.Queues[13] == original and user.QueueMigrationBackup == nil,
    "unknown future schemas must never be downgraded or rewritten")
end

print(string.format("[QUEUE MIGRATION LUA] %d upgrade, recovery, and idempotence checks passed.",checks))
`, 'queue-migration');

let staticChecks = 0;
function check(condition, message) {
  assert.ok(condition, message);
  staticChecks += 1;
}

check(
  /^## SavedVariables:.*\bItemRackItems\b/m.test(toc),
  'The TOC must load account-wide ItemRackItems for direct legacy upgrades.'
);
check(
  toc.includes('ItemRackQueueMigration.lua'),
  'The migration module must be loaded by the addon.'
);
check(
  core.includes('ItemRack.MigrateQueues()') &&
    core.includes('pcall(ItemRack.QueueMigration.Migrate,ItemRackUser,ItemRackItems'),
  'Core initialization must always invoke the versioned migrator with legacy metadata.'
);
check(
  !core.includes('isAlreadyMigrated') && !core.includes('ItemRackItems = {}'),
  'The first-entry heuristic and destructive account-wide cleanup must stay retired.'
);
check(
  options.includes('if selectedEntry.id ~= 0 then') &&
    !options.includes('list[selected].id ~= "0"'),
  'Queue option controls must recognize the canonical numeric stop marker.'
);
check(
  core.includes('if ItemRack.QueueSchemaUnsupported then') &&
    core.includes('return true, "unsupported queue schema"') &&
    core.includes('reason="unsupported_schema"'),
  'Unknown or failed queue schemas must fail closed without reading their representation.'
);

console.log(`[QUEUE MIGRATION STATIC] ${staticChecks} release guards passed.`);
