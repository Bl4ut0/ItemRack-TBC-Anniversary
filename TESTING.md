# Automated Testing

Run the complete release gate from the repository root:

```powershell
npm test
```

Run only the deterministic many-set workloads:

```powershell
node tests/test_large_profiles_lua.js
```

The focused script-event trust test can be run independently with:

```powershell
node .tools/test_script_event_approval_lua.js
```

It executes the production event dispatcher and verifies interface approval,
exact prompted approval, first-use blocking, mutation rollback,
time-of-check/time-of-use rejection, logout persistence cleanup,
packaged-script matching, and malformed or oversized input removal.

The many-set suite executes the production Lua reducers and transaction engine
through Fengari. It does not replace the focused regression files under
`.tools`; it adds long-lived profile shapes and operation sequences that are
hard to reproduce manually on a character with only a few saved sets.

## Large-profile coverage

| Workload | Generated profile | Code-level use cases and invariants |
|---|---:|---|
| Event ownership | 64 physical sets, 100 activations, 80 seeded removals | Overlapping slots, distinct events sharing a set, repeated sets at different depths, Zone-style insertion below a visible owner, stale generations, arbitrary buried removal, manual slot release, and same-event generation replacement. Every operation verifies frame/order indexes, effective physical gear, and final restoration to the original base. |
| Queue policy | 64 sets × 19 slots, 96 event-stack entries | Current-set boundaries, duplicate event-set inheritance, global fallback, missing explicit sets, per-set queues disabled, context inheritance disabled, false enabled values, atomic owner/list/enabled provenance, and no mutation of manual choice, event order, or unknown set fields. |
| SavedVariables migration | 48 sets plus global queues; 931 queues and 3,724 legacy records | Numeric-string slot keys, scalar and canonical entries, sparse gaps, corrupt entries, fail-closed stop markers, legacy priority/keep/delay recovery, nested unknown metadata, quarantine, deep backup, idempotent rerun, and unknown-future-schema refusal. |
| Equipment transactions | 24 complete saved sets across 96 generated switches plus contention cases | Bag↔equipment and equipment↔equipment planning, occupied destinations, exact endpoint observation, serial execution, seven later-step destination failures with full rollback, locked-source resume, rapid-click collision, user cursor ownership, spell targeting, one terminal callback, and zero cursor/transaction residue. |

The event workload uses seed `44501`. Keep that seed stable for the release
gate. If broader fuzzing is added later, report the failing seed and convert
the smallest failure into a named deterministic fixture.

## Test boundary

These tests prove ItemRack's Lua state and its reactions to modeled WoW API
outcomes. They cannot emulate Blizzard's protected-action and taint engine,
real client item-lock timing, unique-equipped restrictions, Masque behavior,
rendering, or frame-time cost. Those remain client acceptance cases in
[`BETA_TEST_CHECKLIST.md`](BETA_TEST_CHECKLIST.md); a green `npm test` must not
be used as evidence that those client-only gates were run.

When adding a reported failure, keep both layers when relevant:

1. Add the smallest focused regression near the owning module under `.tools`.
2. Add or extend a many-set sequence when depth, repetition, migration size,
   or transaction ordering contributed to the failure.
3. Assert the terminal state, not only that an API call was submitted.
4. Preserve unknown SavedVariables fields and verify reruns are idempotent.
