# ItemRack v4.24-to-Dev Code Audit and Remediation Plan

> Status: code remediation implemented, automated closure verified, and `v4.45-beta1` published for live-client validation. Stable promotion remains **NO-GO** until the in-client, historical SavedVariables, reporter, and performance gates below are completed.
>
> Audit snapshot: 2026-09-02, branch `dev`, commit `04a6efea4f5c06748acba945103160215566cef2` (`origin/dev` at the time of inspection).
>
> Scope: the original Anniversary v4.24 source baseline, every identifiable public/package checkpoint from v4.25 through v4.42, the historical `v5.0` beta tag that became v4.30, the v4.43 betas/candidate, and current development changes. Source commits, Git tags, GitHub Releases, CurseForge file labels, TOC versions, and extracted `.versions` folders are compared as separate artifacts when their identities differ.
>
> Latest continuation: the candidate boolean ownership guard has been replaced by canonical event frames; equipment mutations now use an observed transaction coordinator; queue selection and migration are versioned and atomic; cooldown state is generation-aware; inherited action-button templates are removed; protected refresh work is coalesced; and set bindings use an empty protected carrier with out-of-combat reconciliation. The full automated suite passes. Remaining work is release evidence, not permission to market unrun in-client cases as fixed.

## Resume here

This file is the durable handoff point for the audit. On resumption:

1. Re-read **Audit controls**, **Executive assessment**, **Confirmed findings**, and **Open hypotheses**.
2. Run `git status --short` and do not overwrite the user's pre-existing changes listed below.
3. Re-run `npm test` before and after any later implementation work.
4. Continue the unchecked items in **Investigation backlog** and the external evidence in **Release-candidate acceptance gate**; do not rebuild already completed architecture without a failing fixture.
5. Preserve migration backups and quarantine records. Never ask users to delete SavedVariables before copying them.

### Pre-existing user work to preserve

At the audit snapshot, these changes were already present and are not audit edits:

- `.gitignore`
- `.tools/check_events_runtime.js`
- `ItemRack/ItemRackEvents.lua`
- `.env.example`
- `compose.yml`

The original `ItemRackEvents.lua` working-tree guard was reviewed as a candidate and deliberately superseded by the canonical event-frame implementation. The user-owned `.env.example` and `compose.yml` remain untouched.

## Implementation checkpoint — 2026-09-03

The remediation is intentionally split into pure state modules and thin WoW-facing adapters:

- `ItemRackTransaction.lua`: one serialized request, exact endpoint observations, explicit terminal/retry outcomes, rollback-aware cursor ownership, full-bag/two-hand preflight, and one finalizer. It does not mutate the global SFX CVar.
- `ItemRackEventState.lua`: ordered event instances with per-slot prior values, buried-layer splicing, shared-set and repeated-set ownership, generation checks, manual release, and deterministic Zone-under-Mounted insertion.
- `ItemRackQueuePolicy.lua` and `ItemRackQueueMigration.lua`: atomic pure context selection plus schema-v2 migration with account-wide legacy metadata recovery, deep backup, quarantine, fail-closed sparse/corrupt boundaries, and future-schema preservation.
- `ItemRackCooldownState.lua`: one generation/base-aware cooldown authority with arena reset tombstones and stale-publication rejection.
- Core adapters: provenance-bearing deferred intent, inventory/UI coalescing, ItemRack-owned button templates, visual-only slot 20, and empty-carrier set bindings reconciled through the set transaction path.

`npm test` passes with 11 Lua 5.1 parse checks, 445 production-Lua assertions, 6 migration-static guards, and 200 structure, secure-template, regression, event, identity, watchdog, and release-flow checks. These are automated closure evidence, not a substitute for protected-action, taint, client-lock, and performance testing in WoW.

### Finding closure ledger

| Findings | Implemented disposition | Automated evidence | Remaining release evidence |
|---|---|---|---|
| F-001, F-010, F-013, F-017 | Historical/package discrepancies retained as audit evidence; Development notes now describe the actual design and identify the superseded beta2 binding behavior. | Release-flow and changelog promotion guards. | Freeze one commit and verify the RC archive/manifest against it. |
| F-002–F-005, F-011/F-012, F-014/F-016, F-025–F-030 | Canonical ordered event frames replace live `.old/.oldset` ownership; every deferred automatic request has provenance/generation; queue policy is separate and pure; manual slot changes release ownership. Legacy state is captured before `LoadEvents`; ambiguous unordered multi-event state is backed up and left unowned rather than guessed. | 159 event-frame, 19 integration, 39 processor, 21 queue-intent, 12 queue-policy, 9 queue-runtime, and 40 cross-cutting regression checks. | Run the supported-client event matrix, including issue #15 and real reload/portal/combat timing. Accept the documented ambiguous-legacy fail-closed behavior. |
| F-006, F-032–F-037 | All mutation entry points converge on serialized observed transactions with exact endpoints, preflight, one active owner, terminal no-space/missing-item failure, cursor/reservation cleanup, and bounded retry. Global SFX mutation is removed. | 25 transaction integration and 30 transaction-engine assertions, plus watchdog/regression guards. | Exercise client-only rejection rules, unique-equipped combinations, long item locks, and full-bag/two-hand moves in each supported client. |
| F-007 | Destructive whitelist pruning stays removed; migrations preserve unknown fields and opaque malformed values through backup/quarantine. | Queue migration and regression fixtures. | Upgrade copies of real historical SavedVariables and inspect all unrelated settings. |
| F-008 | The former static-only gap is substantially closed with a production-Lua harness and pure reducers; static guards remain supplemental. | 445 assertions execute production Lua/pure production reducers. | Build/run in-client protected-action, taint, and timing cases that cannot be truthfully emulated offline. |
| F-009 | Report-backed beta fixes are retained behind focused guards, including displaced-item return, slot-20 visual cleanup, right-click behavior, prompt formatting, rune identity, and binding lifecycle cleanup. | Identity, transaction, secure-template, binding, and regression suites. | Targeted reporter verification on the packaged candidate. |
| F-015/F-018/F-041 | Blizzard action templates were replaced with ItemRack-owned minimal templates across docked, popup, and options surfaces; inherited action state is prohibited. | 55 secure-template and 32 structure checks. | Clean in-client taint log with UI, Masque, combat, options, and popup combinations. |
| F-019, F-021/F-022 | Dead/mixed queue paths were replaced by schema-v2 full traversal; the TOC loads `ItemRackItems`; backups preserve global and per-set data; corrupt and future representations fail closed. | 42 migration assertions and 6 static migration guards. | Upgrade exact SavedVariables fixtures from the named historical releases. |
| F-020 | The latest manual set or explicit toggle-off is captured before readiness/lock/cast returns and wins over a pending associated-spec request; forced same-spec evaluation does not consume it. | 39 processor checks plus early-capture regression guards. | Verify actual dual-spec cast success, cancel, timeout, and deletion paths in client. |
| F-023/F-031 | Normal binding ownership is reconciled without override-table cleanup. The former split `/equipslot [combat]` macro is removed; an empty protected carrier records one set intent and runs it through normal coordination after protection clears. | 37 set-binding assertions, secure-template checks, and regression guards. | Verify key-up delivery and binding upgrades in every client. This intentionally does **not** promise arbitrary in-combat set swaps. |
| F-024/F-040 | Post-combat callbacks and inventory-driven UI work coalesce duplicate work before rebuilding buttons/menus/cooldowns. | 12 inventory-refresh checks and static scheduler guards. | Record a real macro-swap CPU/frame profile and approve an explicit budget. |
| F-038/F-039 | A generation-aware cooldown authority serves all consumers and rejects stale cooldown data after arena reset, including first-open popup state. | 20 cooldown-state and 20 integration assertions. | Reproduce arena entry and crowd-control timing in client. |

Known upgrade limitation: a pre-canonical profile with several simultaneously active legacy events but neither a reliable ordered `EventStack` nor a complete `oldset` chain cannot be reconstructed uniquely. The migrator preserves the evidence, reports the ambiguity, and owns no guessed slots. Slots whose observed login equipment contradicts the recovered target are also released. This can require the user to retrigger an event, but it prevents stale automatic history from overwriting current gear.

### Release branch state

- The audited implementation is committed at `b32c7eb`; beta metadata and final overhaul notes culminate in immutable release commit `c5e208ae1ac2ec25dadfff4600c9088f353a8904`.
- Annotated tag `v4.45-beta1` points to `c5e208a`. The GitHub prerelease is published at https://github.com/Bl4ut0/ItemRack-Anniversary/releases/tag/v4.45-beta1 with archive SHA-256 `982b09689b6c7a4dba7d808f810d67917d9d375bbd03429029dbbe9fa138d38e`.
- The exact tagged staging tree is installed in `_anniversary_`, `_classic_`, `_classic_era_`, and `_classic_era_ptr_`; each installed core file matches staging. SavedVariables were not modified by installation.
- `dev` was restored to `## Version: Dev` after publication. The older untagged 4.43 candidate remains on `master`; it was not tagged or published and must not be mistaken for the tested 4.45 beta.
- A historical annotated `v5.0` tag points to `f12feebb02f03448219550c3de1840ad9d64c657` (`Beta version 5.0`, 2026-03-11). That branch was merged/renumbered as v4.30 at `7bab169`; the tag is lineage evidence, not the current release version, and must never be moved or deleted.
- Local AddOns destinations exist for `_anniversary_`, `_classic_`, `_classic_era_`, and `_classic_era_ptr_`. Installation is intentionally deferred until an exact committed candidate and version are selected; replacing those folders is a destructive deployment step and must use the verified staging installer.

## Audit controls

### Evidence grades

- **Confirmed**: directly demonstrated by code/history, tied to a report and fix, or reproduced by an existing deterministic check.
- **High confidence**: the code path and history support the explanation, but a WoW-runtime reproduction is still required.
- **Plausible**: symptom and code are compatible; alternatives have not been eliminated.
- **Disproved**: tested or traced and found not to cause the reported behavior.

### Evidence sources

1. Current source and Git history, including blame and commit diffs.
2. Extracted packages under `.versions/Legacy` and `.versions/Release`.
3. GitHub tags, releases, issues, and pull requests.
4. All 178 rendered CurseForge comments available on 2026-09-02.
5. Existing JavaScript/static regression checks and Lua syntax checks.

Tags, release notes, and extracted packages are recorded as separate evidence. Some old extracted packages do not contain a source commit/tree manifest, and several Git tags do not have a corresponding GitHub Release entry. A tag name alone is therefore not treated as proof that the CurseForge package was byte-for-byte identical.

### Sources

- CurseForge comments: https://www.curseforge.com/wow/addons/itemrack-anniversary/comments
- Earliest verified public v4.25 file: https://www.curseforge.com/wow/addons/itemrack-anniversary/files/7509739
- Repository: https://github.com/Bl4ut0/ItemRack-Anniversary
- Releases: https://github.com/Bl4ut0/ItemRack-Anniversary/releases
- Issues: https://github.com/Bl4ut0/ItemRack-Anniversary/issues
- Pull requests: https://github.com/Bl4ut0/ItemRack-Anniversary/pulls

## Executive assessment

The broad direction of the Anniversary work was justified: v4.24 inherited a restoration model that could not reliably represent overlapping or nested event ownership, and later reports show real failures in mounted-zone transitions, queue context, combat deferral, inventory locks, UI persistence, keybindings, and rune-specific item identity. Several recent changes are tightly matched to concrete reports and should be retained.

The v4.24 baseline also separates inherited debt from Anniversary regressions. Its event and equipment files are unchanged from the imported 4.23 source, including per-set `old`/`oldset` restore state and unordered single-winner Stance/Zone processing. Conversely, the first Anniversary UI adaptation changed the item-button template to Blizzard's `ActionBarButtonTemplate` while describing it as a custom secure implementation. The repeated action-trait and taint repairs in v4.27 and v4.29 are therefore consequences of an Anniversary design choice, not only upstream legacy behavior.

The largest risk is not that too many fixes were made; it is that event restoration was only half-migrated in v4.30. `ItemRackUser.EventStack` records **logical event names**, while restore snapshots still live in each reusable set's `set.old` and `set.oldset`. Those two structures cannot represent the same situations:

- two events using the same physical set;
- the same set appearing twice at different stack depths;
- `Set A -> Set B -> Set A`;
- removing a buried event without disturbing slots written by a higher layer;
- a manual set selection interleaved with automatic events.

Later fixes added guards, cycle splicing, active flags, manual-override rules, and parent-chain recovery around this mismatch. Many of those changes treat real symptoms, but they also increase the number of partially independent sources of truth. The safest recovery path is to capture the current behavior in deterministic state-machine tests, apply narrowly proven release blockers, then make event-frame ownership and per-layer restore data canonical.

The second architectural risk is that `IsSetEquipped` mixes physical set identity with AutoQueue intent. Event code uses that result to infer manual overrides and whether an event should push or pop. Consequently, a queue setting or a temporarily unready queue snapshot can alter event ownership decisions even when the worn event gear has not changed. A user report that enabling/disabling queue-context checking changed mount restoration is consistent with this coupling.

### Preliminary intent-versus-regression classification

This is deliberately a disposition matrix rather than a percentage. A line-count or commit-count percentage would be misleading because one small ownership error can invalidate a large correct feature, and several package trees still need normalized comparison.

| Classification | Examples established so far | Planning disposition |
|---|---|---|
| Needed and directionally correct | Modern-client API shims; exact-first item/tooltip matching; specialization support as a feature; paired-slot queue availability; displaced-item return and lock cleanup; non-destructive SavedVariable handling; binding lifecycle/key-up delivery; rune-aware identity | Retain and add focused regression/runtime coverage. Key-up delivery does not justify synthetic in-combat set macros. |
| Real problem, incomplete or over-coupled solution | EventStack layered over per-set restore state; action-button detachment around an inherited Blizzard action template; queue-aware `IsSetEquipped`; force-clear swap timeouts; startup event reconstruction from worn gear | Characterize current behavior, apply narrow safety guards, then replace with canonical ownership/transaction boundaries. |
| Confirmed misunderstanding or introduced regression | Describing `ActionBarButtonTemplate` as a custom secure implementation; v4.29.8 removing the legacy queue SavedVariable before migrating it and incompletely converting queue consumers; v4.30 release notes claiming functional `~BaseGear` restoration after that path was removed; v4.30's unreachable queue-aware block; destructive SavedVariable whitelist pruning; restoring taint-prone tooltip/template behavior after earlier fixes | Do not preserve as compatibility behavior. Correct documentation, remove the unsafe mechanism, and lock the failure out with tests. |
| Not yet fully attributable | Exact runtime timing for cooldown-display resets, the share of macro-driven hitching caused by menu/UI fan-out versus client item locks, some unique-gem failures, and reports without an exact addon/client version or pre-reload dump | The responsible risk paths are now identified; reproduce and measure before claiming each user symptom is closed. |

## Release lineage and risk map

| Release | Primary intent observed in history | Audit assessment / hotspot |
|---|---|---|
| v4.24 source / v4.25 first package | TBC Anniversary API adaptation, TOC update, secure-button and icon compatibility | **Original comparison boundary.** Event/equip logic is unchanged from imported v4.23, so `old`/`oldset` and unordered event selection are inherited debt. The package folder labeled 4.25 contains TOC `Version: 4.24` and core Lua matching `0fb45f6`; no separate GitHub v4.24 tag/release exists. The advertised “custom secure button” is actually `ActionBarButtonTemplate`, creating Anniversary-specific shared-action machinery risk. |
| v4.26 | Right-click queue looping; secure set bindings and immediate binding persistence | User-facing goals were legitimate. Core Lua in the extracted 4.26 artifact matches `e528d03`, while both Git tags `v4.25` and `v4.26` point to the earlier `3c19a73`. Artifact identity must not be inferred from either tag. |
| v4.27-v4.27.1 | Adaptive specialization events; set-associated spec switching; button detachment; manual queue cycling; UI persistence | High behavior churn: specialization became a new automatic gear owner, while `ActionButton_OnLoad` was invoked and then partially detached. The event processors retained unordered single-winner behavior. v4.27.1 immediately fixed spec and queue regressions introduced in this line. |
| v4.27.2-v4.27.5 | Dual-wield/spec, combat queue, action highlighting, mount-to-cast transitions, and keybinding fixes | Mostly report-aligned follow-up, but packaging is inconsistent. The `v4.27.5` tag points to `c64618e`; the extracted 4.27.5 core matches the later `7355e74`, which actually contains the advertised fixes. |
| v4.28 | Exact tooltip item-field matching; keybinding panel; cooldown/hotkey display | Primarily UI and item-identity improvements. Extracted core matches `f7c4ca0` and is core-equivalent to the v4.28 tag. Retain exact-first tooltip behavior. |
| v4.29-v4.29.4 | Action-bar taint repair; item-use restoration; spec flicker; zone instance types; `oldset`/helm/cloak follow-up | The v4.29 taint fix directly confirms the template/dispatcher risk introduced at the Anniversary boundary. The `oldset` fallback and restoration changes were reasonable symptoms fixes on a legacy graph that remained structurally ambiguous. Some patch folders are assembled from different source checkpoints. |
| v4.29.5-v4.29.9 | Sound handling; per-set queue metadata/migration; queue-aware set matching branch; keybinding and combat-queue fixes | Large patch-release churn. v4.29.8 removes `ItemRackItems` from the TOC before its migration can load that legacy SavedVariable, losing custom queue metadata; several queue call sites were also incompletely converted to table entries. The `v4.29.8` tag points to the earlier merge commit and omits the artifact's final Events/Queue changes. The queue-aware matching code was developed here but shipped dead in v4.30. |
| `v5.0` beta tag | First beta label for the event-stack/queue/right-click line | Annotated tag `v5.0` points to `f12feeb` on 2026-03-11. It is an ancestor of current dev and was later merged/renumbered as v4.30, not a newer major release than v4.43. Preserve it as a distinct historical checkpoint. |
| v4.30 | Advertised adaptive `EventStack`; AutoQueue-aware `IsSetEquipped`; queue and secure-click fixes | **Root architectural boundary.** Stable code retained per-set restore snapshots and no functional `~BaseGear`, despite release notes saying the old restore system was replaced. The shipped queue-aware block reads `.Queues` from `set.equip`, so it cannot run; the intended event/queue coupling only became live when v4.36 corrected the lookup. |
| v4.31 | Rapid-swap lock guards/timeouts; OnMovement zoning suppression; queue pause; zone re-trigger | Problems were real. The five-second force-clear timeout can recover the addon flag while the WoW client remains locked, so it is a safety net rather than transaction proof. |
| v4.32 | Mounted-zone PR; script compatibility; combat/cast retries; tooltip work | Legitimate compatibility and transition fixes. Mount/zone state became increasingly dependent on timing buffers and `IsSetEquipped`. |
| v4.33 | Cursor cleanup, failed-swap retention, combat queue consistency | Correctly targets transaction failures, but subsequent beta-three history proves displaced-item completion was still incomplete. |
| v4.34 | Per-set queue persistence; event crash and queue matching fixes | Confirmed that PR #10 initially crashed event paths by iterating non-slot set properties. Queue identity/pause behavior was repaired but remained cross-coupled. |
| v4.35 | Queue editor context locking and per-set metadata snapshots | Needed and report-backed. Per-set queue ownership became more complex and needs explicit isolation tests. |
| v4.36 | Six-item queue audit; inheritance; manual vs automatic queue handling | Mostly justified corrections. Sparse tables, implicit current-set lookup, and provenance were proven failure classes. This is also the release where `IsSetEquipped` first correctly looks up per-set queues and therefore where queue policy actually became coupled to event ownership. |
| v4.37-v4.38 | Queue-option UI template hotfixes | Low core-logic risk; demonstrates release-pressure churn in options UI. |
| v4.39 | Empty-slot, pending-swap, and double-pop fixes | High-risk core restoration changes. Must be regression-tested with event layers and bag readiness. |
| v4.39.1 | Cooldown/arena UI and parent/double-pop follow-up | Continued event restoration stabilization; issue #15 persisted. |
| v4.39.2 | Diagnostic framework and restoration fixes | **Major risk boundary.** Events began pushing a logical layer even when the shared physical set was already equipped, and `EquipSet` could create history without a physical swap. This made logical ownership better but exposed shared per-set-history collisions. |
| v4.39.3 | Taint/Masque/icon changes and partial rollback | UI changes were repeatedly revised; core event issue #15 remained open. |
| v4.39.4 | Saved-variable audit fix; mount readiness; package cleanup | Confirmed destructive settings-whitelist regression was fixed by removing pruning. Audit code should never delete unknown user data again. |
| v4.39.5-v4.39.7 | Addon-folder/load-order restructuring, keybind/dump/queue fixes, small UI hotfixes | Large operational churn. Needs package-equivalence and fresh-install/upgrade coverage in addition to source tests. |
| v4.39.8-v4.39.9 | Accessibility, menu-wrap separation, screen clamping | Mostly UI-scoped and lower risk to equipment state. |
| v4.40-v4.40.1 | AutoQueue/combat queue stuck-slot fixes; tooltip taint; menu placement; client support | Queue fixes match reports. `GameTooltip:Show()` was removed for taint, later restored in v4.41, then removed again in beta4: a regression-prone toggle requiring a taint-safe UI test. |
| v4.41 | Forced-dismount recovery; live `oldset` cycle prevention; event spin up/down; in-combat weapons; ghost button fix | Several real fixes, but cycle prevention is evidence that the set-name restore graph cannot model event instances. Spin-down must prove ownership before restoring. |
| v4.42 | Interface/TOC update only | Report changes after v4.42 should not automatically be attributed to its source diff; likely inherited behavior, client behavior, data state, or timing. |
| v4.43-beta1 | Large AutoQueue readiness, cooldown provenance, burn, and lifecycle rewrite | High regression surface. Design is more explicit, but requires executable lifecycle tests; current tests mostly assert source guards/models. |
| v4.43-beta2 | Bags-only paired-slot candidates; count overlay; right-click set menu; secure key-up behavior | Directly report-backed and high confidence to retain. |
| v4.43-beta3 | Displaced-item return, orphan lock cleanup, Druid stance resolution, rune identity | Directly report-backed. The `MoveItem` fix explains the “logout required,” `CUSTOM`, default minimap icon, and frozen `SetsWaiting` symptom chain. |
| beta4/current dev | Keybinding prompt; associated-spec intent; transition holds/watchdogs; event ownership; rune matching; release flow | The audit findings drove a canonical event/transaction/queue/cooldown rewrite with production-Lua coverage. It has not yet had the same public exposure as v4.42 and must not be labeled proven until the remaining client/package gates pass. |

### Release-integrity notes

- No `v4.24` tag or GitHub Release exists. The earliest extracted Anniversary folder is named `ItemRack-bcc-anniversary-4.2.5`, its TOC says `Version: 4.24`, and its five core Lua files exactly match commit `0fb45f6`. The earliest public CurseForge file verified in this audit is labeled 4.25 (`ItemRack-bcc-anniversary-4.2.5.zip`). For audit purposes, v4.24 is the source baseline and v4.25 is the first public-package checkpoint.
- Tags `v4.25` and `v4.26` both point to `3c19a73`. The extracted 4.25/TOC-4.24 core matches the earlier `0fb45f6`; the extracted 4.26 core matches the later `e528d03`. Neither tag uniquely identifies both packages.
- Exact five-core-Lua matches for early stable artifacts include: 4.25/TOC-4.24 → `0fb45f6`, 4.26 → `e528d03`, 4.27 → `4112021`, 4.27.1 → `b3cf63d`, 4.27.5 → `7355e74`, 4.28 → `f7c4ca0`, 4.29 → `fae59b6`, 4.29.1 → `fdb0753`, 4.29.3 → `3b99195`, 4.29.4 → `1fdaf6b`, 4.29.5 → `cb92b1a`, 4.29.8 → `a934e9c`, and 4.29.9 → `147ccae`/`ac3ce88` core-equivalent.
- No single repository commit exactly matches all five core Lua files in the extracted 4.27-beta2, 4.27.3, 4.29.2, or 4.29.6 folders. Focused diffs classify them more narrowly: 4.27-beta2 is closest to `bafcfa1` with locally different Equip/Events files; 4.27.3 is `9f5a5cc`-like with small ItemRack/Events edits; 4.29.2 combines `34b029a`'s `ItemRack.lua` with the other four core files from `fdb0753` (omitting the same commit's button changes); and 4.29.6 is only 13 changed lines away from the later v4.29.7 `485645d` core. These are unmanifested package snapshots, not safe aliases for same-name tags.
- Early tag/package mismatches are behaviorally significant in at least two cases: the `v4.27.5` tag predates the `7355e74` core shipped in the extracted artifact, and the `v4.29.8` tag points to `c7b2ba7` while the extracted artifact includes the later `a934e9c` Events/Queue changes.
- The annotated `v5.0` tag is not evidence of a later post-v4.43 product line. It marks the 2026-03-11 beta commit `f12feeb`; its work was renumbered to v4.30 and merged at `7bab169` later that day.
- Tags exist for v4.35, v4.38, v4.39.8, and v4.40.1 even though they did not appear in the GitHub Release list inspected on 2026-09-02.
- `.versions/Legacy` covers the 4.25-labeled/TOC-4.24 source artifact through v4.39.2; `.versions/Release` covers later releases and betas.
- Snapshot coverage has gaps: no extracted same-name snapshot was found for v4.39.1 or v4.39.3, and some beta folders/ZIPs do not correspond to a published GitHub Release.
- Older snapshots often lack `SOURCE_COMMIT`/`SOURCE_TREE`; v4.43 packaging has a source manifest.
- The initial late-release core-file comparison found package/tag differences in v4.30, v4.32, v4.35, v4.36, v4.39.2, v4.41, and v4.43-beta3. The completed normalized pass below expands that list across the early releases as well. Some mismatches are explainable as a release commit after an early tag; others are mixed or unmanifested builds and must be traced as package artifacts rather than tags.
- A completed line-ending-normalized full-package comparison covers all 47 extracted directories. For the 35 snapshots with a same-name tag, every package had the same 39- or 40-file payload shape as the tag, but only ten were content-identical across every packaged file: v4.39.5 through v4.40, v4.40.1, v4.42, and v4.43-beta1/beta2. Twelve more differed only in release metadata/changelog content. Thirteen had at least one changed core Lua file: v4.25, v4.26, v4.27.5, v4.29.1, v4.29.6, v4.29.8, v4.30, v4.32, v4.35, v4.36, v4.39.2, v4.41, and v4.43-beta3. The no-tag early snapshots were compared to their nearest or exact source commits; v4.27 and v4.27.1/4.29.3/4.29.9 have core-equivalent commits, while both v4.27 betas, v4.27.3, and v4.29.2 remain mixed/unmanifested package checkpoints. The remaining v4.40-beta3 flat package matches its flat release commit, v4.43's 40-file source manifest verifies exactly, v4.43-beta4 matches `271f84b`, and the named v4.43 dev snapshot is core-equivalent to `97d18a1` with expected TOC version changes.
- GitHub asset-digest comparison was stronger for the later ZIPs: every local ZIP with a published digest matched except `ItemRack-anniversary-4.41.zip`. The local v4.41 ZIP has SHA-256 `dd7b3bdd38456407c15150cc8262efc23e64e32cde455a0473c5d5687c692de0`, while GitHub publishes `9346b029a34e4e4ceddaa6eafa149566b78569bbe5cdca70784567d45733ed8e`; its packaged TOC also says `Version: Dev`, and changed core blobs match post-v4.41 development. It is not the official v4.41 package.
- The local v4.43-beta3 ZIP matched GitHub's SHA-256 exactly even though its core blobs differ from the same-name tag. For that version, the published package—not the tag—is the correct user-runtime source.
- Stable transition sizes are unusually large for several patch releases, notably v4.39.1→v4.39.2, v4.39.4→v4.39.5, v4.40.1→v4.41, and v4.42→v4.43-beta1.
- From v4.24 to current dev, core churn is concentrated in `ItemRack.lua`, `ItemRackEvents.lua`, `ItemRackEquip.lua`, `ItemRackQueue.lua`, and the secure/button layer. These need behavioral, not only textual, coverage.

## Confirmed findings

The sections below preserve the evidence and required action as recorded during discovery. Their current implementation disposition is authoritative in the **Finding closure ledger** above; “required action” text is historical unless the ledger still lists code work as open.

### F-001 — v4.30 release notes do not match the shipped restoration design

**Grade: Confirmed. Severity: P0 architectural/documentation risk.**

Commit `a450e05` originally captured a real `~BaseGear` set when the event stack was empty and restored either the next event layer or `~BaseGear` on pop. Commit `f12feeb`, immediately before v4.30, removed that capture/restore behavior and returned `PopEvent` to `UnequipSet`, which uses per-set `.old`/`.oldset`.

The v4.30 notes nevertheless say the old single-variable restore system was replaced, `~BaseGear` is a safe fallback, and stack restoration is combat-safe. Current source only initializes `~BaseGear`; no live path uses it. This is not merely stale wording: it obscures which state is authoritative and likely encouraged later fixes to assume a completed migration.

**Required action:** correct the architecture documentation immediately; do not use the v4.30 release description as a design specification.

### F-002 — event ownership and restore data have incompatible identities

**Grade: Confirmed design mismatch; runtime impact High confidence. Severity: P0.**

- `EventStack` entries identify event names.
- `Event.Active` and `ManualOverride` add separate logical flags.
- `set.old` and `set.oldset` store one mutable restore snapshot per reusable set name.
- `CurrentSet`, `SetSwapping`, `SetsWaiting`, and `CombatQueue` separately describe displayed, in-flight, deferred, and slot-level state.

One event-stack layer cannot be paired unambiguously with one restore snapshot. A stack frame needs its own identity and restore delta/snapshot. Until that exists, guards can prevent known bad pops but cannot make all buried/shared/repeated-set cases correct.

### F-003 — shared-set logical layers were made possible without shared-set restore semantics

**Grade: Confirmed in history and a user runtime dump. Severity: P0.**

In v4.30, `ProcessBuffEvent` generally pushed only when its set was not already equipped. Commit `2a5eb18` (v4.39.2) changed this to push an inactive event even if another event already had the same physical set equipped, explicitly to establish event history. The same commit made `EquipSet` record `.old` in more no-op cases.

That is logically reasonable—Ghostwolf and Mounted really are two owners—but the restore snapshot is still one mutable field on their shared set. Popping either owner can therefore restore or wipe history belonging to the other. GitHub issue #15 contains a dump where the mounted set's `old[14]` is the same item as its own equipped slot 14, making a real restore impossible. The current working-tree `removedLayer`/same-set-top guard addresses an important unsafe pop case, but it does not by itself make the shared history per-layer.

**Required action:** retain the gear-swap feature and fix ownership. Do not solve this by simply removing Mounted swaps or refusing to record the second logical event.

### F-004 — per-set `oldset` parent discovery is nondeterministic and cannot reliably splice a logical stack

**Grade: High confidence. Severity: P0/P1.**

`UnequipSet` searches `pairs(ItemRackUser.Sets)` for a set whose `.oldset` equals the popped set and uses the first match as `parentSet`. Lua table iteration does not define a stable semantic parent. Multiple saved sets can reference the same predecessor, while the active event parent is ordered in `EventStack`.

For a buried event, applying the popped set's saved `.old` also risks touching slots owned by a higher layer unless restoration is represented as per-layer slot deltas.

**Required action:** add a failing deterministic model test for multiple candidate parents and buried removal before changing this code.

### F-005 — queue policy is coupled to physical set identity and event ownership decisions

**Grade: Confirmed coupling; reported failure mechanism High confidence. Severity: P1.**

`IsSetEquipped` calls `GetQueues(setname)`, `GetQueuesEnabled(setname)`, queue readiness checks, cooldown logic, and `AutoQueueItemToEquip`. Event processors also call `IsSetEquipped` to decide whether an event owns gear, whether a manual override occurred, and whether to push/pop.

Therefore a queue context, cooldown, or temporarily unresolved queue snapshot can make an unchanged event set appear unequipped. The CurseForge report where queue-context checking changed mount restoration is consistent with this path. Historical qualification: PR #10 attempted this in the v4.30 line, but the stable implementation read `set.Queues` after assigning `set = ItemRackUser.Sets[setname].equip`, so the queue branch was unreachable. Commit `b74b073` corrected the lookup to `ItemRack.GetQueues(setname)[i]`; v4.36 is the first stable boundary where this coupling is actually live.

**Required action:** split APIs into at least `DoesPhysicalSetMatch(set, mode)` and `DoesQueuePolicyWantAnotherItem(context)`. Event ownership must never be inferred only from queue policy.

### F-006 — the beta-three inventory failure was a real incomplete transaction

**Grade: Confirmed. Severity before fix: P0.**

Before v4.43-beta3, `MoveItem` could place the source item into an occupied destination and leave the displaced item on the cursor instead of returning it to the source. The resulting `AbortSwap=4` path could leave reserved bag positions in `LockList`, stall `SetsWaiting`, mark the current set `CUSTOM`, and reset the minimap icon. This exactly matches the Druid report that only a logout—not `/reload`—recovered the character.

The current displaced-item return and abort cleanup are justified. They still need full-bag, equipment↔bag, equipment↔equipment, and combat-transition runtime tests.

### F-007 — saved-variable audit deleted valid settings until v4.39.4

**Grade: Confirmed. Severity before fix: P1 data loss.**

The audit once pruned every `ItemRackSettings` key absent from a strict default whitelist. Reports included non-persistent `OnMovement`, PvE/PvP exclusions, minimap position, and tooltip settings. Commit `bfb88be` removed the destructive pruning and corrected `AnotherOther` to `AnchorOther`.

**Required action:** preserve unknown keys; migrations must be versioned, narrow, idempotent, and non-destructive. Add an invariant test that arbitrary future keys survive audit.

### F-008 — current automated checks are valuable but are not a WoW state-machine test suite

**Grade: Confirmed. Severity: P1 process risk.**

All current checks pass: Lua syntax, structure, regression guards, event checks, identity, queue/watchdog, and release flow. Much of the suite asserts source substrings or uses small JavaScript models rather than executing the Lua modules against mocked WoW APIs and asynchronous inventory events.

The checks prevent accidental guard removal but cannot prove ordering across `UNIT_INVENTORY_CHANGED`, item locks, combat/cast transitions, zoning, timers, multiple events, or cursor transactions.

**Required action:** keep these tests and add executable Lua/behavioral tests. Do not treat a green static suite as release proof.

### F-009 — several recent fixes are directly attributable and should be retained

**Grade: Confirmed. Severity: regression-protection requirement.**

- v4.43-beta2 bags-only queue candidates fix the paired trinket/ring false-availability report.
- v4.43-beta2 clears the inherited Slot 20 count overlay.
- v4.43-beta2 restores the configured right-click set list.
- v4.43-beta3 completes displaced-item transactions and clears orphan locks.
- beta4/current uses `StaticPopupDialogs.text = "%s"` plus `StaticPopup_Show(..., confirmationText)` to prevent `%` in dynamic binding/set text from being parsed as a format string.
- beta4/current records `PendingSpecSet` so an explicit set associated with a spec is not overwritten by another default set for the same destination spec (GitHub issue #21).

Each needs a focused regression test so a later cleanup does not reintroduce the original report.

### F-010 — public stable exposure and current-dev confidence are different

**Grade: Confirmed. Severity: release-risk control.**

The latest stable GitHub/CurseForge line inspected is v4.42, whose source change is a TOC/interface bump. Many fixes now in the v4.43 betas/current dev have not received equivalent public soak time. A report made “after the latest update” may describe inherited behavior on v4.42, not a source regression introduced by v4.42.

**Required action:** record exact addon version, WoW flavor/build, class, event configuration, queue configuration, and whether SavedVariables were reset for every reproduction.

### F-011 — buried-event restoration clobbers overlapping slots owned by a higher layer

**Grade: Confirmed algorithmic defect. Severity: P0.**

`UnequipSet` copies every numeric entry from the popped set's `.old` snapshot into `~Unequip`. If it finds a live `parentSet`, it changes only `parentSet.oldset`; it does not merge or rewrite `parentSet.old` and does not subtract slots currently owned by the parent/higher event. It then physically equips the complete `~Unequip` snapshot.

Concrete example:

1. Base trinket is `B`.
2. lower event `G` equips `G`; `G.old[13] = B`.
3. higher event `C` equips `C`; `C.old[13] = G` and `C.oldset = G`.
4. lower event ends while `C` remains active.

The correct result is to keep `C` visible and patch `C.old[13]` to `B`, so ending `C` later restores base. Current code equips `G.old[13]` immediately, replacing `C` with `B`. Existing JavaScript event checks validate only the Boolean decision to restore; they do not model per-slot ownership and therefore pass this broken case.

**Required action:** add slot-aware buried-pop tests first. The minimum safe splice must patch higher-layer prior values for overlapping slots and physically restore only unowned slots; canonical per-frame slot deltas are the durable solution.

### F-012 — multiple matching events are resolved through unordered single-winner variables

**Grade: Confirmed. Severity: P1, potentially P0 with overlapping automatic sets.**

`ProcessStanceEvent` and `ProcessSpecializationEvent` iterate enabled events with `pairs()` but retain only one `eventToEquip` and one `eventToUnequip`. With two matching custom events, multiple `.Active` flags can be changed while only the last arbitrary table entry is pushed or popped. Startup reconstruction also iterates `pairs()` and inserts matching Buff/Zone/Stance events into `EventStack` in undefined order based only on physical set matches.

Zone processing has been improved to collect and sort arrays; Buff processing acts inside its loop. Stance, Specialization, and startup do not yet share that deterministic multi-event behavior.

**Required action:** define explicit priority/tie rules, collect all transitions before mutation, sort deterministically, and activate an event only after it owns a successfully created frame.

### F-013 — `.versions` provenance is mixed and one named ZIP is demonstrably not its GitHub release

**Grade: Confirmed. Severity: P1 audit/release integrity.**

The local v4.41 ZIP is not GitHub's v4.41 asset and contains a `Dev` TOC plus later code. Other snapshot/tag differences show that early tags were sometimes placed before the packaged release commit, while later published ZIPs can contain content not represented by the same-name tag. Without a manifest, a folder name is not sufficient provenance.

**Required action:** build the audit comparison matrix around verified GitHub asset digests when available; record source-tree manifests in every future package; recover official historical assets rather than treating the mislabeled v4.41 local ZIP as user-shipped code.

### F-014 — reload purges event order but preserves restoration history, then guesses ownership from gear

**Grade: Confirmed design defect. Severity: P0/P1.**

`InitEvents` clears every runtime `.Active` flag and empties `EventStack`. Despite an adjacent comment saying it wipes all stale `.old/.oldset` data, the implemented cleanup intentionally preserves valid `.old` and `.oldset` so a mount/stance/zone active across reload can restore later. It then reconstructs Buff/Zone/Stance ownership by iterating enabled events with `pairs()` and inserting any event whose set physically matches.

The preserved restore graph is keyed by set name, while the destroyed/rebuilt ownership graph is keyed by event name. Physical gear cannot recover prior event order or prove which of several subset/shared sets created the history. The exact ghost state that later code tries to repair is therefore expected after some reloads, not necessarily corrupt user data.

**Required action:** persist or deterministically rebuild versioned event frames with explicit ownership; never preserve anonymous restore history while discarding its frame identity. Remove the contradictory cleanup comment as part of the same change.

### F-015 — dynamic popup buttons still inherit Blizzard's action-button machinery after the known taint fix was reverted

**Grade: Confirmed code regression; current in-client taint impact High confidence. Severity: P1.**

`CreateMenuButton` still creates `ItemRackMenu*` frames with `ActionButtonTemplate`. Commit `c090660` explicitly removed those buttons from Blizzard's shared action-button dispatcher tables to stop addon taint propagating to protected action bars. Commit `cba6b38` later rolled that work back with other Masque/icon changes, and the dynamic-button cleanup is absent from current source. Docked buttons perform extensive cleanup, but dynamically created popup buttons do not.

This also explains why macro names, counts, flashing, and other inherited action state repeatedly appear on ItemRack controls: the code is fighting a template designed to represent real action slots.

**Required action:** replace `ActionButtonTemplate` with an ItemRack-owned visual/secure template that includes only required regions and behaviors. Treat direct edits to Blizzard dispatcher internals and monkey-patching inherited regions as transitional containment, not the durable design.

### F-016 — issue #15 proves stale duplicate pops and invalid self-restoration history

**Grade: Confirmed runtime evidence. Severity: P0.**

Issue #15's v4.39.4-beta1 trace records:

1. `PushEvent` equips the mount set and captures the correct previous trinket.
2. Stopping movement triggers `PopEvent`; `UnequipSet` restores the previous trinket successfully and empties `EventStack`.
3. On the next event pass, `Active` is already nil but `IsSetEquipped` still reports the mount set true, consistent with temporarily stale inventory identity.
4. The fallback calls `PopEvent` a second time even though that event no longer owns a layer.

Older `PopEvent` then called `UnequipSet` again. The current working-tree `removedLayer` guard is the correct minimal rule for this failure: a stale flag or physical match must not authorize restoration. A separate dump from the same issue shows an already-invalid self snapshot (`pvpm.old[14] == pvpm.equip[14]`), which explains why the mount item can remain after a nominal pop.

The reporter had global queues disabled and reported that v4.29.4 worked after rollback. `/itemrack debug audit` found no current structural errors. The evidence therefore does not support dismissing this family as queue configuration or SavedVariable corruption.

**Required action:** keep the non-owner pop suppression, add the exact two-pass stale-inventory fixture, and prevent creation of a self-restoration snapshot unless it is an explicit no-op ownership adoption with a valid inherited frame.

### F-017 — v4.24 proves the core restoration limitation is inherited, not created by the Anniversary port

**Grade: Confirmed. Severity: P0 architectural provenance.**

The extracted folder labeled 4.25 identifies itself as TOC version 4.24 and its five core Lua files match commit `0fb45f6`. Comparing that source with the imported 4.23 root shows no changes at all in `ItemRackEquip.lua` or `ItemRackEvents.lua`. The baseline already stores restoration in one mutable `set.old`/`set.oldset`, copies the entire `old` table into `~Unequip`, and chooses only one Stance/Zone equip and unequip candidate from `pairs(enabled)` iteration.

This matters for intent review: v4.30's EventStack work was not an unnecessary rewrite of a correct system. It tried to solve a real inherited limitation. The implementation failed because it left the legacy restore store authoritative while adding a second logical ownership structure.

**Required action:** classify per-set restoration and unordered event arbitration as inherited debt, retain the goal of ordered event ownership, and judge post-v4.30 fixes by whether they converge on one canonical frame model rather than by whether they preserve every v4.24 implementation detail.

### F-018 — the first Anniversary “custom secure button” change actually adopted Blizzard's action-bar template

**Grade: Confirmed code/documentation mismatch. Severity: P1 architectural taint/UI risk.**

The imported 4.23 XML used `ActionButtonTemplate,SecureActionButtonTemplate`. Commit `0fb45f6`, represented by the TOC-4.24/first-4.25 artifact, changed that to `ActionBarButtonTemplate`. The v4.25 changelog instead says the incompatible action template was replaced with a “custom secure button implementation.” No ItemRack-owned minimal template was introduced.

The downstream history is internally consistent with that choice causing problems: v4.27 calls `ActionButton_OnLoad`, unregisters events/scripts, and clears action attributes to stop action-bar flashing/keybind traits; v4.29 removes the buttons from shared dispatcher tables to stop taint reaching real action buttons; later revisions repeatedly clear inherited macro/count/glow regions. F-015 shows that dynamic menu buttons still retain related machinery today.

**Required action:** treat the v4.24/v4.25 compatibility goal as valid but the template choice as a design misunderstanding. Replace both docked and dynamic buttons with minimal ItemRack-owned secure/visual templates, then preserve only the interaction and Masque behaviors verified by tests.

### F-019 — v4.30 advertised queue-aware set matching, but the shipped block was unreachable until v4.36

**Grade: Confirmed. Severity: P1 release-note and debugging provenance.**

In v4.30, `IsSetEquipped` assigns `set = ItemRackUser.Sets[setname].equip` and later checks `set.Queues`. Queue data is not stored inside the equipment-slot table, so the advertised queue-aware branch cannot execute. That same block also references `slot` where the loop variable is `i`, but the dead `set.Queues` guard prevents this from surfacing in normal data.

Commit `b74b073` replaces the lookup with `ItemRack.GetQueues(setname)[i]`, uses slot `i`, and checks `GetQueuesEnabled(setname)[i]`; that commit is first contained in v4.36. This narrows regression attribution: queue-aware event identity was an intended v4.30 feature, but reports caused by the live coupling cannot originate from that code path before v4.36.

**Required action:** update release/regression notes to distinguish introduction intent from executable behavior. Add versioned tests that exercise the queue branch directly so a release cannot claim a feature whose only path is dead.

### F-020 — v4.27 conflated an explicitly selected spec-associated set with the destination spec's default event set

**Grade: Confirmed code path and issue #21 fix lineage. Severity: P1.**

v4.27 added two related features: a saved set can request a talent specialization from `EndSetSwap`, and a Specialization event can equip its configured default when `ACTIVE_TALENT_GROUP_CHANGED` fires. Until beta4/current, there was no state connecting those operations. If the player explicitly chose Set A associated with spec 2 while the Secondary Spec event mapped spec 2 to Set B, completion of A initiated the spec change and the event processor then replaced A with B.

The current `PendingSpecSet` path was added specifically to preserve the initiating set through the transition, adopting the destination event only when it maps to that same set. This is not an inherited ItemRack limitation; it is an interaction bug between two Anniversary features introduced at the v4.27 boundary.

**Required action:** retain the `PendingSpecSet` behavior, execute issue #21 as a production-Lua fixture, and cover cancellation, timeout, failed spec casts, same-set adoption, different-default preservation, and manual selection immediately after the transition.

### F-021 — v4.29.8 cannot load the legacy SavedVariable that its queue migration is supposed to preserve

**Grade: Confirmed data-migration defect. Severity: P1 data loss.**

Before v4.29.8, per-item queue behavior (`keep`, `priority`, and `delay`) is stored in the account-wide SavedVariable `ItemRackItems`. The v4.29.8 migration reads `ItemRackItems[baseID]` while converting each queue entry to `{ id, priority, keep, delay }`. However, the same change removes `ItemRackItems` from `## SavedVariables` in `ItemRack.toc` and removes its default global table before startup migration runs.

On a normal upgrade, the current TOC controls which saved globals WoW loads. The legacy table is therefore unavailable to the migration, so every custom setting is replaced by a default and `MigrateQueues` then assigns `ItemRackItems = {}`. The originating commit itself warned that the migration had not been heavily tested and might wipe settings. The direction—making metadata queue/context-specific—was correct; removing the source declaration in the same release made preservation impossible.

There is a second persistent flaw: `isAlreadyMigrated()` examines the first non-empty entry it encounters and returns immediately. A mixed profile can be classified differently based on unordered table iteration; if a table entry is encountered first, remaining legacy scalar entries are not converted, while downstream code assumes every entry has `.id`. The current SavedVariables audit validates queue slot keys but not entry schemas, so it does not repair this state.

**Required action:** replace heuristic discovery with a versioned, idempotent full traversal. For any recovery release, temporarily declare/load the legacy variable before migration, preserve it until every queue validates, and retain a backup/copy rather than clearing it in the same session. Add fixtures for direct upgrades from v4.24/v4.27/v4.29.7, all-legacy, all-new, mixed, interrupted, empty, stop-marker-only, and metadata for items absent from the active queue.

### F-022 — v4.29.8 converted queue storage without converting all consumers

**Grade: Confirmed code regression, fixed in later revisions. Severity at v4.29.8: P1.**

v4.29.8 changes queue entries from strings/numeric stop markers to tables, but `GetNextItemInQueue` still calls `string.match(list[i], ...)` on the table itself. `ManualQueueAdvance` uses `tostring(list[i])`, yielding a table identity rather than an item ID, compares the table itself to numeric `0`, and passes the table instead of `list[i].id` toward equip/queue handling. Plain right-click calls `ManualQueueAdvance`, so the advertised manual queue cycling path cannot identify candidates correctly in that artifact.

v4.30 converts those call sites to `.id` and adds exact-first current-item matching, so the specific regression was short-lived. This history is still important: complaints against v4.29.8 should not be used to discredit the queue feature generally, and schema migrations need an exhaustive consumer inventory before release.

**Required action:** preserve the corrected call sites, add an executable old/new/mixed-schema compatibility test, and make future schema changes fail tests unless every reader and writer uses a single normalization API.

### F-023 — the v4.29.7-v4.42 binding lifecycle mixed standard and override APIs and could destroy unrelated bindings

**Grade: Confirmed code defect and fix lineage. Severity: P1 user configuration loss.**

The original v4.26 adaptation was justified: replacing a protected `/script` macro call with a secure button plus `PostClick` allowed set bindings to work on the Anniversary client. Later cleanup confused two different binding stores:

- v4.29.7 checks `GetBindingAction(key)`, clears that normal binding with `SetBinding(key, nil)`, saves the changed binding set, then installs an unsaved runtime `SetOverrideBindingClick`. A set key colliding with a Blizzard/game action can therefore permanently erase the user's normal assignment.
- Set deletion and unbinding in that line use `ClearOverrideBindings(button)`, which cannot remove bindings created through `SetBindingClick` in earlier/later versions.
- v4.29.9 restores `SetBindingClick`, but its first-pass import checks whether the ItemRack click action already has a key—not whether the saved key is currently owned by another action. The source comment explicitly notes that import overwrites game defaults. Set deletion still uses `ClearOverrideBindings`, so normal saved bindings can survive as orphaned actions through v4.42.
- The callback and secure macro attributes also remain attached to the generated button after deleting the set.

Current beta4 hardening makes the active Blizzard binding table authoritative, refuses to replace an unrelated action during saved-key import, clears all keys for the exact click action, removes the button callback/macro on deletion, and restores prior primary/secondary keys if replacement fails. Those changes are corrective, not unnecessary complexity.

**Required action:** retain the current authority and cleanup rules; add upgrade fixtures from v4.26, v4.29.7, v4.29.9, and v4.42 with conflicting normal actions, two keys, deleted sets, explicit unbinds, and failed `SetBindingClick`. Never use `ClearOverrideBindings` to clean a normal saved binding or save the removal of an unrelated user action without explicit confirmation.

### F-024 — the inherited post-combat callback cleanup removed only alternating entries until v4.36

**Grade: Confirmed inherited bug, fixed. Severity before fix: P2/P1 depending on queued actions.**

From the imported 4.23 source through v4.35, `ProcessCombatQueue` executes `RunAfterCombat` and then clears it with a forward numeric loop calling `table.remove(list, i)`. Each removal shifts the next entry down, so the loop removes the original first, third, fifth, and so on while leaving alternating callbacks to execute again on later combat exits. `ConstructLayout` and `ReflectMainScale` already used this queue; v4.27.5 added `SetSetBindings`, increasing the chance of stale UI/binding work recurring.

Commit `b74b073` replaces the faulty removal loop with `wipe(ItemRack.RunAfterCombat)`, first released in v4.36. This is a justified cleanup of inherited behavior rather than an Anniversary regression, though queued callback de-duplication would still make the intent clearer.

**Required action:** retain the v4.36 full clear, add a small drain-order fixture with multiple callbacks, and coalesce repeated callback names before execution so a combat period cannot accumulate redundant binding/layout work.

### F-025 — the candidate ownership test still authorizes an unsafe buried-layer restore

**Grade: Confirmed candidate-fix acceptance defect. Severity: P0.**

The current working-tree `PopEvent` change contains two useful containment rules: it refuses to restore for an event that did not own an `EventStack` layer, and it keeps the gear when the new top event maps to the same physical set. Those rules directly address the stale second-pop evidence in issue #15 and one adjacent shared-set case.

However, `.tools/check_events_runtime.js` currently expects `restore: true` for `EventStack = { "Ghostwolf", "City" }` when buried `Ghostwolf` is removed and `City` remains on top. That expected result encodes F-011 as correct behavior. In the production path, `UnequipSet("ZoomZoom")` finds `CityGear` through `oldset`, sees that a `CityGear` event remains in `EventStack`, copies every slot in `ZoomZoom.old` into `~Unequip`, and physically equips it. Any overlapping City slot is therefore replaced by the state that existed before Ghostwolf, even though City is still the visible owner.

The correct semantic operation for removing a buried layer is to leave observed gear unchanged and splice that layer's prior slot state into the immediate successor's restoration frame. Removing `X` from `Base → X → Y` should produce `Base → Y`, not temporarily equip `Base` over `Y`. The existing per-set `.old/.oldset` representation cannot reliably perform this splice, especially for `X → Y → X`, because both `X` layers share one mutable `X.old` table.

**Required action:** retain the non-owner guard as a minimal safety fix, but do not accept the current boolean model as proof that event restoration is fixed. Change the buried-different-top expectation to **no physical restore**, add a per-slot state model that verifies visible gear and the successor's inherited prior state, and cover `Base → X → Y`, `Base → X → Y → X`, overlapping/non-overlapping slots, and removal of every layer. The same-set-top suppression is containment only until restoration state is stored per logical layer.

### F-026 — deferred queue-readiness equips can outlive the intent that authorized them

**Grade: Confirmed current-dev design defect. Severity: P0/P1. Introduced in v4.43-beta1; provenance fields added in beta4 but do not validate intent.**

v4.43-beta1 added one global `PendingQueueEquipSet` so `EquipSet` can wait until exact equipped-item/queue state is reliable. The pending record contains a set name and, after beta4, booleans for event/deferred provenance. It does not contain the authorizing event name, an event-frame/request generation, or a predicate that must still be true when the retry runs. `TryEquipPendingQueueSet` checks only that the set still exists, automatic swaps are not globally suspended, and item state is ready; it then calls `EquipSet` unconditionally.

This creates two concrete stale-intent paths:

1. An event pushes its layer and requests set `X` while queue state is unresolved. The event ends before readiness, so `PopEvent` removes the layer and `UnequipSet` finds nothing to restore. Nothing cancels `PendingQueueEquipSet`. When item data resolves, `TryEquipPendingQueueSet` equips `X` even though the event is inactive and no longer owns a layer.
2. The global pending slot is last-writer-wins. A manual set request can be overwritten by a later automatic event request while state is unresolved, despite the waiting-queue/watchdog policy documenting manual intent as authoritative. The inverse ordering also silently discards the automatic request rather than reconciling active intent.

The nearby call order makes the first case more visible: `NotifyQueueStateReady` tries the stale pending set before it calls `RunAllEvents`, so the correct event evaluation happens only after the obsolete equip has already been submitted. `SetsWaiting` has the same broader weakness for lock-deferred event work: it records event/deferred booleans but no identity/generation and cannot cancel an inverse equip/unequip pair when the event condition changes.

**Required action:** represent deferred work as versioned intent, not a set-name callback. Manual intent must have explicit precedence; automatic requests must include event name/frame ID and be revalidated against the current event condition/owned layer immediately before execution. Popping or disabling an event must cancel/coalesce its pending equip. Reorder readiness recovery so current observed conditions are evaluated before any stale automatic request is submitted. Add production-Lua tests for push→defer→pop→ready, manual→automatic while unresolved, automatic→manual, deleted/disabled events, inverse equip/unequip coalescing, and multiple active events sharing a set.

### F-027 — the v4.39 manual-override guard can leave a popped event's items queued for post-combat equip

**Grade: Confirmed cross-path regression. Severity: P0/P1. Introduced at the v4.39 boundary and still present.**

When an event set is requested during combat, `EquipSet` places its desired items into the slot-indexed `CombatQueue`, records only one global `CombatSet`, and returns before making that set current. If the event condition ends before combat does, `PopEvent` removes the event layer and calls `UnequipSet`. Current `UnequipSet` does not treat `CombatSet`/`CombatQueue` or `PendingQueueEquipSet` as pending ownership. Because the event set is neither current nor physically equipped, and may have no parent, `shouldRestore` remains false; the code wipes the set's `.old/.oldset` but does not remove its queued items. `ProcessCombatQueue` later equips those items after combat even though the authorizing event has already popped.

The regression boundary is meaningful. The v4.24 implementation always submitted `~Unequip` when an event popped. During combat, that inverse request wrote the prior items into the same slot-indexed `CombatQueue`, replacing the pending event items. Commit `fe0446f` (contained in v4.39) added the `shouldRestore` manual-override suppression. That protected manual gear in one path, but it separated restoration cleanup from deferred-request cancellation. Commit `2a5eb18` later added `isPendingOrSwapping`, but it checks only `SetSwapping` and `SetsWaiting`; the combat queue remains omitted. A separate Zone helper recognizes `CombatSet`, proving the pending state is known elsewhere but not consistently authoritative.

This queue also cannot safely represent concurrent intent: item entries know their slot and target ID, while `CombatSet` is a single mutable set name. Normal set/event deferrals do not carry the `AutoQueueOwner` metadata used to discard stale AutoQueue entries. A later request can overwrite individual slots and the global owner independently, producing a mixed transaction whose restore lineage belongs to no single request.

**Required action:** do not restore the old behavior blindly, because physically restoring a buried event would reintroduce F-011. Instead, attach request/frame provenance to every combat-deferred slot, cancel slots owned by a popped event, and revalidate remaining automatic intent before submission. Treat an inverse request as cancellation or frame-splice when the original equip was never observed, not as another blind gear swap. Add fixtures for event enter→combat defer→event exit→combat exit, overlapping two-event requests, manual request after event request, partial weapon swaps in combat plus deferred armor, and two requests writing disjoint/overlapping slots.

### F-028 — the v4.32 movement debounce has one global pending owner and strands additional OnMovement events

**Grade: Confirmed deterministic design defect with nondeterministic winner. Severity: P1. Introduced by the v4.32 OnMovement debounce.**

`ProcessBuffEvent` supports `OnMovement` on any enabled Buff event, but delayed stop handling is stored in one scalar `ItemRack.PendingOnMovementUnequip` and one named timer. When movement stops with two qualifying active events, iteration through `pairs(enabled)` lets the first event set the scalar and start the timer. The second sees a non-nil pending value and is skipped. `ProcessOnMovementUnequip` clears the scalar and pops only the recorded event; it does not rescan Buff conditions or schedule the other stopped event. The other event therefore remains `Active` and on `EventStack` until an unrelated movement/aura/recheck happens. Which event wins depends on unordered table iteration.

This also means deletion, exclusion, and forced-dismount cleanup can stop the one global timer when their event owns it without preserving another event that was waiting for the same movement transition. The global speed check prevents some wrong pops after movement resumes, but it does not solve multiple logical owners.

**Required action:** replace the scalar with per-event pending generations or a single debounce generation whose expiry recomputes all OnMovement conditions. Apply transitions in deterministic event-frame order and serialize any resulting gear work; do not enqueue several blind `PopEvent` calls against mutable per-set history. Add two- and three-event fixtures with shared/different sets, reversed insertion order, one event disabled/excluded during the delay, movement resuming before expiry, and a zone transition during the debounce.

### F-029 — per-slot queue inheritance can combine different owners and cross an event's explicit gear boundary

**Grade: Confirmed algorithmic defect. Severity: P1. Introduced by the v4.36 per-slot inheritance line and still present.**

The active-context `GetQueues()` and `GetQueuesEnabled()` proxies resolve their fields independently. Each calls `resolveSlotFromStack(field, slot)`, which scans top-to-bottom for that one field but does not stop when a higher event set explicitly defines `equip[slot]`. This permits two invalid composite contexts:

- a higher event explicitly equips a slot but has no per-set queue data, so the resolver continues to a lower event/global queue and AutoQueue can replace the higher event's owned item;
- one event supplies `Queues[slot]` while another lower layer supplies `QueuesEnabled[slot]`, so list and enabled state come from different logical owners.

`GetActiveQueueOwner` uses different rules: `setOwnsQueueSlot` treats any `Queues`, `QueuesEnabled`, **or** `equip` entry as ownership and returns the first such event set. As a result, `ProcessAutoQueue` can read lower-layer queue data while `AddToCombatQueue` records the higher gear-owning event as the request owner. Later stale-owner checks operate on provenance that never described the policy actually used.

The v4.36 goal was valid: a one-slot mount set should not erase unrelated queues for every other slot. The defect is that inheritance is field-by-field rather than resolving one atomic `(owner, list, enabled)` context, and that an explicit gear slot is not treated consistently as an inheritance boundary. `IsSetEquipped(setname)` uses explicit raw set queue data instead of the active inheritance proxy, so AutoQueue can swap a higher event's item away while the event predicate evaluates under a different queue policy and attempts to reassert it.

**Required action:** replace the three independent lookups with one pure resolver returning owner, queue list, enabled state, and reason from the same layer. Define and test whether an explicit `equip[slot]` blocks lower queue policy (the current `GetActiveQueueOwner` and current-set proxy already imply that it should). Make `ProcessAutoQueue`, combat provenance, UI indicators, and set/event identity consume that same resolved tuple. Add stack fixtures with missing/false fields, explicit slot ownership, manual override CurrentSet, shared sets, reversed stack order, and global fallback.

### F-030 — `IsSetEquipped` can clear the active manual queue choice while inspecting a different set

**Grade: Confirmed state-mutation defect. Severity: P1. Introduced in the v4.39.2 queue/event diagnostic line and still present.**

`IsSetEquipped(setname)` is public and is used as a predicate by event processors, toggle logic, initialization, manual-override detection, and display reconciliation. For queue-enabled slots it calls `AutoQueueItemToEquip(..., setname)`. That function gets the inspected set's explicit queue with `GetQueues(setname)`, but calls `IsManualQueueChoice` without a set name, so manual-hold validation reads the **active** inherited queue context instead. It then compares the worn item against the inspected set's list; if there is no match, it calls `ClearManualQueueChoice(slot)`.

Consequently, evaluating an inactive Event/Set B whose queue does not contain the currently worn manual choice from active Set A can erase A's manual hold. The next periodic AutoQueue pass is then free to rotate the item that the user explicitly selected. This can happen from background event polling or `UpdateCurrentSet`; no user action on Set B is required. The stored manual choice is itself only keyed by slot/item, not by queue owner or intent generation, which makes cross-context validation ambiguous.

**Required action:** make `IsSetEquipped` and its desired-queue calculation pure. Pass one explicit atomic queue context through every helper; never clear manual intent from a predicate. Store manual choice with queue owner/context generation and clear it only on an explicit user choice, an observed incompatible equipment transition in that same context, queue edit/deletion, or a documented context-change rule. Add tests proving repeated identity/UI/event checks of unrelated sets cannot mutate manual hold, burn state, queues, pending work, or SavedVariables.

### F-031 — secure in-combat weapon bindings reconcile after the macro has already changed gear

**Grade: High-confidence ordering/race defect; WoW runtime confirmation required. Severity: P0/P1 for bound weapon sets. Present since secure set bindings were introduced in v4.26.**

Each generated set-binding button runs a secure `/equipslot [combat]` macro for weapon slots and then invokes `RunSetBinding(setname)` from `PostClick`. The normal `EquipSet`/`ToggleSet` path therefore does not own the full transaction: it observes gear after the secure action has been submitted and has no captured pre-click weapon state.

For a weapon-only set, two unsafe outcomes depend on when the client publishes the secure change:

- if the target weapons are visible by `PostClick`, `EquipToggle == "ON"` treats the first press as an unequip, while normal equip mode can snapshot the target weapons into `set.old` as their own restoration state;
- if the old gear remains briefly visible, normal code submits a duplicate swap against client locks and relies on the later secure-keybind mismatch/combat queue path to reconcile it.

For mixed armor/weapon sets, weapons can change securely while protected armor is deferred, so one logical request is split between an untracked secure action and the addon transaction/`CombatQueue`. Exact-instance information is also reduced to base ID plus optional enchant/name in the macro, so identical weapon copies with different gems/runes cannot be assumed deterministic.

This is separate from F-023: beta4 correctly repairs binding-table authority and cleanup, but it does not capture pre-secure-action gear or make the macro and post-click transaction atomic.

**Required action:** build an in-client fixture before choosing the implementation. Capture immutable pre-click slot state with a combat-safe mechanism, give the secure and deferred portions one request ID, and reconcile observed post-click results without calling toggle semantics against already-changed gear. Reject self-restoration snapshots. Test EquipToggle on/off, weapon-only and mixed sets, identical base items with different enhancements/runes, two-hand/offhand transitions, failed secure actions, key-up behavior, and repeated presses while locked.

### F-032 — a full-bag empty-slot abort can leave every game sound effect disabled

**Grade: Confirmed control-flow defect. Severity: P0/P1 global client-setting side effect. Present since the v4.29.5 sound fallback and still present.**

`IterateSwapList` temporarily sets the global `Sound_EnableSFX` CVar to `0` when swap sounds are disabled and the optional LibSoundIndex integration is unavailable or declines the mute. Its restoration timer is created only at the bottom of the function. If the requested set wants an equipment slot empty and `FindSpace()` cannot find a bag slot, the function sets `AbortSwap = 1`, clears the lock list, and returns immediately. That return bypasses cursor cleanup, the abort message, and the CVar restoration timer. All game SFX therefore remain disabled, rather than only being muted for the advertised 1.5 seconds.

The early return is inherited from the original v4.24 equipment loop, but it became a global-settings regression when the CVar fallback was added in the v4.29.5 line. LibSoundIndex is an optional dependency, and the options/login text explicitly promises the CVar fallback when it is absent, so absence of that addon is a supported path rather than an unsupported configuration.

**Required action:** give the operation one cleanup/finalization path that runs for success, abort, Lua error, and every early exit. Restore only state owned by the operation; prefer removing the global-CVar fallback if a safe bounded mute cannot be guaranteed. Do not leave timer/CVar ownership in a local branch. Add an executable fixture with `DisableSwapSound = ON`, no LibSoundIndex, an occupied slot requested empty, zero bag space, and assertions that the original SFX state, cursor, locks, transaction flags, and user-visible abort reason are restored exactly once. Also test user/external CVar changes during the mute window.

### F-033 — beta4 treats a terminal no-space failure as an unlocked transaction and retries forever

**Grade: Confirmed current-dev control-flow regression. Severity: P0/P1. Introduced by the beta4 unlocked-inventory watchdog recovery.**

After F-032's early return, the requested slot remains in `SwapList`. `EquipSet` interprets any non-empty swap list outside combat as a second-pass operation, sets `SetSwapping`, and starts the five-second watchdog. Current beta4 changed that watchdog so an unlocked inventory calls `LockChangedDuringSetSwap()` rather than clearing the stuck transaction. That function calls `IterateSwapList` again; the bags are still full, so the same terminal failure returns with the same entry still in `SwapList`. The post-pass check re-enters `SetSwapping` and restarts the timer. No branch consumes the failure, prints “Not enough room,” or limits the retries.

This behavior differs across the lineage. Before v4.31 the failed operation could wait indefinitely for a lock event that might never arrive. From v4.31 through v4.42 the watchdog eventually discarded the remaining work—also an incomplete outcome, but not an endless poll. Beta4's lost-unlock recovery is useful for a genuinely submitted asynchronous transaction; the misunderstanding is applying it to a synchronous terminal precondition failure with no lock to await. If earlier slots were already submitted before the later empty slot fails, the loop also preserves a partially applied set without a transaction outcome or rollback plan.

**Required action:** classify outcomes explicitly as `submitted/waiting`, `complete`, `retryable`, or `terminal`. A no-space/unique-conflict/precondition failure must stop once, cancel its watchdog, clear only owned reservations/cursor state, preserve an accurate observed-state reconciliation, and report the exact reason. Run a preflight plan before submitting any slot so a predictable later failure cannot leave earlier slots changed. Add tests for failure on the first and later slots, one free slot appearing after failure, manual A→B while the failure is displayed, automatic event requests, two-hand/offhand space, and proof that no timer or `SetSwapping` state survives a terminal abort.

### F-034 — beta3's displaced-item return can classify a failed destination pickup as success

**Grade: High-confidence transaction defect; mocked production-Lua and WoW runtime confirmation required. Severity: P0/P1. Introduced by the beta3 displaced-item completion fix.**

The beta3 `MoveItem` change correctly addressed a real defect: after a successful move into an occupied destination, WoW leaves the displaced destination item on the cursor and ItemRack must return it to the source location. The implementation then uses only `CursorHasItem()` after that return as its success test. This observation is not sufficient to identify the outcome.

For a bag→equipment move, consider a target API call that is rejected after the source pickup despite passing the earlier lock checks. The cursor still holds the original source item. The new generic displaced-item branch calls `PickupContainerItem(fromBag, fromSlot)`, which puts that same item back at its source and empties the cursor. The final test now logs `MoveItem SUCCESS`, the caller removes the slot from `SwapList`, and `EndSetSwap` can set `CurrentSet` to the requested set even though the destination never changed. The exact same ambiguity exists in the other move directions: an empty cursor proves only that something was deposited, not that the requested destination accepted the requested item.

Pre-call lock checks cannot make this proof reliable because the inventory APIs are asynchronous and the comments explicitly intend to handle failures caused by combat timing, animation, internal bag errors, and changing locks. The function captures neither exact source/destination identities nor the identity of the cursor item, and it does not verify observed destination state before declaring success. A stale/empty source can produce a related inverse move: the destination item is picked up and deposited into the presumed source while the function reports success.

**Required action:** make `MoveItem` return a structured submission outcome and retain the transaction step until observed source/destination identities confirm it. At minimum, capture exact pre-move source/destination IDs and cursor identity so a returned original source is distinguishable from a returned displaced destination; ultimately confirm through inventory/lock events. Never remove `SwapList` work or call `EndSetSwap` based only on cursor emptiness. Add deterministic API mocks for successful empty/occupied destinations, rejected target with original item still on cursor, stale empty source, changed destination, exact-copy ambiguity, and delayed lock/inventory events.

### F-035 — missing requested items are omitted from the transaction but the set can still complete

**Grade: Confirmed inherited completion-state defect. Severity: P1, potentially P0 when automatic restoration records a false owner. Present from the v4.24 baseline through current dev.**

While building `SwapList`, `EquipSet` handles a nonzero requested item that `FindItem` cannot locate by appending it to a `Could not find` message. It does not add an unsatisfied transaction step or mark the request partial/failed. The function then snapshots restoration history and continues. If other items are available, they are equipped as a partial set; if no other move remains, `not next(swap)` calls `EndSetSwap` immediately. For a normal set, `EndSetSwap` assigns `ItemRackUser.CurrentSet = setname` even though the missing slot never matched.

The delayed `UpdateCurrentSet` can later relabel the display as `CUSTOM`, but that does not correct the already-recorded request outcome, history, event ownership decisions, callbacks, or intervening queued work. For an automatic event, `set.old` includes the missing slot even though the event never wrote it; a later restore may therefore act as if the event owned that slot. Queue/readiness work reduces false cache misses but does not address a genuinely absent, banked, deleted, or exact-instance-mismatched item.

**Required action:** retain every requested slot in the plan with an explicit state such as `satisfied`, `submitted`, `unavailable`, or `failed`. Define policy separately for manual best-effort sets and automatic event/restoration transactions, but never report full completion or record write ownership for an unavailable slot. Reconcile `CurrentSet` from confirmed observed slots. Add fixtures for all-missing, one-of-many missing, bank-only, exact rune/gem copy missing with a base-ID alternative, item becoming available after the warning, and automatic push/pop around a partial equip.

### F-036 — a locked offhand can leak the single-item swap's global SFX mute

**Grade: Confirmed control-flow defect. Severity: P0/P1 global client-setting side effect. Created by the interaction of the v4.29.5 CVar fallback and the v4.35 offhand-lock guard.**

`EquipItemByID` implements its own sound-mute scope. With swap sounds disabled and LibSoundIndex unavailable or declining the request, it sets the global `Sound_EnableSFX` CVar to `0`. During a two-hand weapon equip, it then checks slot 17 after reserving a free bag location. If the offhand is locked, it adds the request to `CombatQueue` and returns immediately. That return occurs before the fallback restoration timer is created, leaving all game SFX disabled indefinitely.

This is a distinct entry point from F-032's set-swap failure. The broader ownership design is also unsafe: `BuildMenu` and `UpdateCurrentSet` mute the same global CVar around complex unprotected work; `EquipItemByID` uses one shared timer and later writes `1` rather than conditionally restoring an operation-owned generation. Overlapping operations or an external/user CVar change therefore cannot be reconciled reliably even when the normal bottom-of-function path runs.

**Required action:** centralize sound suppression behind one reference-counted or generation-owned API with guaranteed finalization, or remove the global-CVar fallback. The finalizer must run on every return/error, restore only the state this operation changed, and never overwrite a later user/external decision. Cover set swaps, single-item/manual/AutoQueue swaps, menu builds, and current-set updates with the same fault-injection suite.

### F-037 — manual popup and AutoQueue swaps bypass the repaired transaction and can leave displaced gear on the cursor

**Grade: Confirmed transaction-path bypass; exact client event timing still needs runtime coverage. Severity: P0/P1. Inherited from the v4.24 baseline and still present.**

`EquipItemByID`, used by popup/manual swaps and AutoQueue, does not call `MoveItem` or participate in the set transaction. For a normal occupied equipment destination it calls `PickupContainerItem(source)` and then `PickupInventoryItem(destination)`, but it never returns the displaced equipped item to the source, clears or verifies the cursor, retains a pending step, or confirms destination identity. The two-hand path first parks the offhand, then performs the same incomplete bag-to-mainhand operation and can leave the displaced mainhand on the cursor.

The v4.39.3/beta3 displaced-item repair in `MoveItem` is strong historical evidence for the API behavior and reported “logout required” symptom, but that commit only repaired `ItemRackEquip.lua`. It did not route this parallel single-item path through the repaired logic. F-034 also shows that even the repaired path still needs observed confirmation; merely copying its present cursor-empty heuristic would not be sufficient.

**Required action:** eliminate the parallel pickup sequence. Manual popup, AutoQueue, set, combat-deferred, empty-slot, and two-hand operations must submit through one serialized transaction API with exact pre-state, source/destination/cursor identities, displaced-item return, terminal reason, and event-driven observed completion. Add occupied/empty destination, full-bag, offhand, identical-copy, lock, rejection, and rapid manual-plus-AutoQueue fixtures.

### F-038 — arena cooldown reset can immediately re-cache the stale cooldown it is trying to clear

**Grade: High-confidence timing defect; in-client boundary timing required. Severity: P1 display/notification correctness. Introduced in the v4.39.2 cooldown-reset line.**

On first entering an arena, `UpdateArenaVisibilityState` calls `ResetCooldownCaches` immediately and once more after a fixed one-second delay. `ResetCooldownCaches` clears both caches and then immediately calls `UpdateButtonCooldowns` and `UpdateMenuCooldowns`. If Blizzard still reports the pre-arena cooldown during either pass, those update functions repopulate the just-cleared cache. When the authoritative arena-reset `0/0` result arrives later, the crowd-control false-zero guard interprets it as unreliable and preserves the stale cached cooldown until its original expiry.

The second fixed pass reduces the probability but does not establish an ordering guarantee. A reset published after one second, or an asynchronous tooltip/menu refresh between the clear and the authoritative API update, remains unsafe. Clearing `ItemsUsed` at the same point can also suppress or alter readiness notifications independently of what the client has actually confirmed.

**Required action:** make arena entry a cooldown-observation generation with an unsettled/reset state. Do not repopulate from pre-generation values; accept a new active cooldown only after a post-entry authoritative observation rule is satisfied, and distinguish arena reset from CC false-zero suppression. Test reset publication before, at, and after one second, CC during entry, menu open/closed, and notification state.

### F-039 — popup cooldown protection only observes items while that popup is already built

**Grade: High-confidence coverage defect; runtime reproduction required. Severity: P1/P2. Introduced with the v4.39.1 menu cooldown cache.**

`MenuCooldownCache` is populated only inside `UpdateMenuCooldowns`, which iterates the current `ItemRack.Menu`. That update runs when the popup is built or refreshed. If an item begins a cooldown while its popup is closed, no menu-cache entry is recorded. Opening the popup during a crowd-control/line-of-control false-zero window therefore has no prior value to restore, so the menu clears or omits the cooldown even though the docked slot cache may know it.

This contradicts the intended “same cached guard” behavior at the state boundary: button and menu renderers maintain separate partial observations keyed differently, rather than consuming one item-cooldown authority. An item swapped out of a visible slot further widens the gap because neither renderer is guaranteed to keep observing it.

**Required action:** maintain one item/exact-identity cooldown observation store independently of which renderer is visible. Buttons, popups, text, notifications, and AutoQueue readiness should consume a common normalized result while retaining distinct presentation state. Test use-with-menu-closed → CC → open, swapping the used item out, paired slots, duplicate base IDs, arena entry, and reload.

### F-040 — each inventory event can synchronously rebuild every button and the entire open popup

**Grade: Confirmed performance anti-pattern; contribution to individual freeze reports is plausible until profiled. Severity: P1 for rapid multi-slot swaps. Present in the baseline and amplified by later cooldown, rune, queue, Masque, and diagnostic work.**

Every player `UNIT_INVENTORY_CHANGED` immediately calls `UpdateButtons`. That loops all configured buttons, resolves textures/IDs/rune overlays/counts, runs queue-aware `UpdateCurrentSet`, and performs a complete cooldown update. If a popup is visible, the same event immediately calls `BuildMenu`, which clears and rescans all bags (and the bank when open), invokes tooltip-based wearability and soulbound checks for candidates, repositions every dynamic button, removes and re-adds every button across Masque groups, and redraws cooldown/count/rune state. The set-menu branch also sorts the growing menu once per saved set instead of once after collection.

A multi-slot swap can emit several inventory events, so this entire synchronous fan-out repeats while item locks and other aura/macro activity are already hot. This gives the Battle Shout/rapid hotswap hitch report a concrete candidate amplifier, but it does not yet prove how much time is Lua scanning versus Blizzard item-lock/UI work.

**Required action:** instrument production calls and timings first, then coalesce inventory dirtiness per frame/transaction generation. Cache menu eligibility until the relevant bag/equipment/options epoch changes, sort once, batch Masque reconciliation, and separate cheap button texture updates from current-set/cooldown/event reconciliation. The performance gate must record calls and wall/CPU time for menu open/closed, diagnostics on/off, 1-slot and 19-slot swaps, bank state, Masque present/absent, and rapid aura macros.

### F-041 — the options module creates another undetached set of Blizzard action-template buttons

**Grade: Confirmed architectural coverage gap; current in-client taint impact High confidence. Severity: P1. Inherited at the Anniversary boundary and still present.**

F-015 covers runtime popup buttons and F-018 covers the docked quick buttons. The load-on-demand options XML adds a third surface: 20 `ItemRackOptInv*` buttons inherit `ActionButtonTemplate`, and `ItemRackOptSetsCurrentSet` inherits it as well. Their `OnLoad` code hides visual overlays but does not clear action attributes, unregister inherited events, or remove the frames from shared Blizzard action-button dispatchers. Opening options therefore instantiates and then repeatedly mutates 21 more frames carrying the same machinery that prior commits explicitly associated with `ADDON_ACTION_BLOCKED`, inherited macro/count/glow state, and yellow-triangle cleanup.

This also exposes why dispatcher surgery has produced inconsistent results: commit `c090660` cleaned only dynamically created popups, was rolled back by `cba6b38` with an unrelated Masque icon regression, and later cleanup was restored only for docked buttons. The options templates were never converted. The v4.25 changelog's “custom secure button implementation” remains inaccurate across all three visual button families.

**Required action:** replace all visual-only options, popup, and docked action-template inheritance with ItemRack-owned minimal templates. Add secure capability only to the specific controls that perform protected clicks; do not use Blizzard action-bar presentation/mixin state as an icon-layout dependency. Validate options unopened/opened, popup unopened/opened, Masque absent/present, combat entry, action-bar page/visibility changes, macro/count/glow residue, and a clean taint log.

## Report catalogue and triage

Comment numbers below refer to their order in the 178-comment CurseForge page loaded for this audit. This table groups symptoms; it does not assume every report in a row has one root cause.

| Cluster | Evidence examples | Current assessment | Candidate first boundary / fix status |
|---|---|---|---|
| Event gear fails to restore after mount/dismount/zone | CF #21, #36, #64, #81, #110; GitHub #15 | **P0 historical; automated remediation complete.** Strongly connected to split event/restore state, queue-aware identity, transition timing, and oldset cycles. GitHub #15 reports v4.29.4 rollback succeeds. | Canonical per-slot event frames, migration, and transition-generation fixtures pass; targeted client reproduction remains. |
| Ghostwolf + Mounted share a set | User-discovered case and current working-tree patch | **P0 historical; automated remediation complete.** Distinct logical owners now retain distinct frame histories even when they share physical targets. | Shared-set enter/leave, buried pop, same-target splice, and manual release fixtures pass; client verification remains. |
| Wrong set repeatedly re-equips / manual gear overridden | CF #3, #60, #153; GitHub #21 | **P0/P1 historical; automated remediation complete.** Manual intent now has precedence over stale automatic and specialization work. | Generation cancellation and spec/manual race fixtures pass; real cast/client timing remains. |
| Empty or missing gear / “could not find” carried item | CF #1, #22 follow-up, #98 | **P0/P1 historical; automated remediation complete for known code paths.** Missing/no-space outcomes fail before submission; rejected endpoints cannot claim success; every source uses the same transaction. | Transaction fixtures pass. Full-bag and unique-equipped client combinations remain an acceptance gate. |
| Rapid swaps freeze; logout required | CF #4, #116; Druid #10 | **P0 historical; automated remediation complete for addon ownership.** One observed transaction owns the cursor/locks; timeout reconciles or aborts rather than declaring success. | Bounded rapid-request/lost-unlock fixtures pass; long real-client lock stress remains. |
| AutoQueue/trinket queue not advancing or wrong queue applied | CF #2, #5, #29, #88, #101, #105/#122; GitHub #16 | **P1 historical; automated remediation complete.** Proven provenance, paired-slot, sparse lookup, context, migration, cooldown, and transaction paths have explicit owners and tests. | Atomic policy and common transaction suites pass; reporter/client replay remains. |
| Queue settings lost during upgrade | v4.29.7→v4.29.8 source/TOC migration trace | **P1 historical; schema-v2 remediation complete.** The TOC loads the legacy global and the migrator traverses every global/per-set entry. | Deep backup/quarantine/idempotence fixtures pass; exact historical SavedVariables upgrades remain. |
| Queue context affects event restoration | CF #36 and related mount reports | **P1 historical; automated remediation complete.** Queue selection is a pure atomic policy and cannot create event ownership. | Policy, identity-purity, and frame integration fixtures pass; client context toggle remains. |
| Key already bound popup error / bindings fail | CF #9, #127; PR #20 | **P0/P1 historical; code containment complete.** Normal binding ownership is preserved, popup formatting is safe, and the split secure weapon macro was removed. | Empty-carrier set requests reconcile after combat. Client key-up/upgrade testing remains; arbitrary in-combat set swapping is not promised. |
| Set/minimap icon becomes Custom/default | CF #10, #41, #51 | Usually a downstream symptom, not icon root cause. Beta3 linked it to aborted inventory transaction; other SavedVariable cases exist. | Do not “fix” by forcing display state; reconcile actual transaction/event ownership. |
| Options/event/minimap settings do not persist | CF #46, #48 | **Previously confirmed.** Strict audit pruning fixed in v4.39.4. | Add migration preservation tests. |
| Ghost quick-access button | CF #34 | Confirmed v4.41 visibility ownership fix. | Retain with secure-frame tests. |
| UI taint / tooltip / inherited action text | CF #55, #151, #172 | **P1/P2 historical; code containment complete.** All three visual families now use ItemRack-owned templates and the insecure tooltip `Show()` remains removed. | Static/structure guards pass; full macro/count/flashing/taint/Masque client matrix remains. |
| Right-click item/set behavior | CF #19, #175-#178 | Multiple meanings: open set menu, use equipped item, secure attribute behavior. | Set list fixed beta2; `/use` behavior needs explicit UX/config tests. |
| Stance-specific failures | CF #10 | Druid stance index and inventory transaction were both confirmed contributors. | beta3 stance mapping retained; Ghostwolf ownership is covered by canonical shared-set fixtures; client replay remains. |
| Cooldown display resets/wrong dock cooldown | CF #70/#72, #120 | **P1/P2 historical; automated remediation complete.** One generation-aware authority prevents stale arena re-adoption and supplies closed-popup state. | Authority/integration fixtures pass; exact report-to-path client attribution remains. |
| Gear-swap hitch/freezes | CF #4 (Battle Shout macro) | **P1 candidate; structural remediation complete.** Inventory/UI and protected callbacks coalesce repeated dirty work, while transaction ownership addresses the independent lock path. | A production performance trace and approved frame/CPU budget are still required before claiming the reporter symptom is closed. |

## Hypothesis resolution and residual risk

| ID | Hypothesis / risk | Grade | How to prove or disprove |
|---|---|---|---|
| H-001 | Popping a buried event applies its `.old` slots over gear owned by a higher event. | **Confirmed as F-011; remediated offline** | Canonical splice fixtures prove no visible higher slot changes and successor prior values rebase. Run in client. |
| H-002 | `pairs(ItemRackUser.Sets)` selects the wrong `parentSet` when multiple sets reference the same `oldset`. | **Confirmed design flaw; bypassed** | Automatic events no longer use set-graph parent discovery. Retain manual legacy compatibility tests. |
| H-003 | Queue-not-ready makes `IsSetEquipped` false, which can be misclassified as a manual override or cause an unnecessary event push. | **Confirmed risk; remediated offline** | Physical identity, queue policy, and event ownership are separate; readiness intent fixtures pass. Run startup/zone client cases. |
| H-004 | Queue inheritance from `EventStack` creates a feedback loop: event stack chooses queue owner while queue-aware set matching decides event stack behavior. | **Confirmed risk; remediated offline** | Atomic pure queue context cannot mutate the event-frame graph; integration fixtures pass. |
| H-005 | Full bags cause legal equipment↔equipment swaps to be rejected or partially applied when a temporary bag slot is unnecessarily reserved. | Plausible | Test every `MoveItem` direction with zero free slots, unique-equipped gems, and occupied source/destination. |
| H-006 | Force-clearing `SetSwapping` after a timeout permits a new transaction while the client still owns an item lock. | **Confirmed risk; remediated offline** | One active transaction plus observed finalization/bounded retry fixtures prevent overlap. Stress long locks in client. |
| H-007 | Legacy base-ID fallback can select the wrong enchanted/gemmed copy where no exact metadata was saved. | **Accepted compatibility limit** | Exact-first matching is canonical; legacy entries without distinguishing metadata retain wildcard fallback because the lost identity cannot be reconstructed. |
| H-008 | Repeated `RunAllEvents` calls can choose only one transition from unordered enabled-event iteration and miss simultaneous changes. | **Confirmed risk; remediated offline** | Deterministic multi-event processor fixtures pass independently of insertion order. |
| H-009 | One global OnMovement pending owner allows only the first of multiple stopped events to debounce/pop. | **Confirmed as F-028; remediated offline** | Per-event generations and multi-event timer fixtures transition every owner once. |
| H-010 | “Custom icon stuck” after a clean transaction is a separate set matching/persistence problem. | Plausible | Reproduce without abort/lock and compare `CurrentSet`, physical set match, queue policy, and icon update. |
| H-011 | Source-string tests can pass with semantically broken Lua because they do not execute production behavior. | **Confirmed limitation; substantially closed** | Critical behavior now executes as production Lua/pure production modules; static guards are supplemental. In-client behavior remains separate. |
| H-012 | Extracted historical package content differs from same-name Git tags in at least one release. | **Confirmed as F-013; analysis complete** | The normalized 47-snapshot matrix classifies the mismatches; exact-tree manifests are required going forward. |
| H-013 | A terminal full-bag empty-slot failure or locked two-hand offhand path leaks fallback SFX state and retries indefinitely. | **Confirmed as F-032/F-033/F-036; remediated offline** | Terminal/cleanup fixtures pass and global SFX mutation has been removed. Run full-bag/two-hand client cases. |
| H-014 | Cursor emptiness after returning an item to the source proves that the destination accepted the requested item. | **Disproved by F-034; remediated offline** | Exact observed destination/source identities now decide completion; rejection/rollback fixtures pass. |
| H-015 | A `Could not find` warning prevents a set with an unsatisfied nonzero slot from being recorded as complete/current. | **Disproved by F-035; remediated offline** | Preflight reports every missing requested slot and submits no move, so partial sets cannot claim full completion. |
| H-016 | A simple arena cache clear guarantees that a later authoritative `0/0` cooldown reset will be honored. | **Disproved by F-038; remediated offline** | Generation/tombstone fixtures pass on both sides of the prior retry boundary; client timing remains. |
| H-017 | Menu cooldown rendering has the same observation history as docked-button rendering. | **Disproved by F-039; remediated offline** | All consumers now share one authority; closed-menu then CC/first-open fixtures pass. |
| H-018 | Rapid inventory events perform only incremental icon work. | **Disproved by F-040; structural remediation complete** | Dirty work is coalesced. A client profile must quantify the remaining cost and establish the RC budget. |

## Target architecture

The target should make these state boundaries explicit:

1. **Observed state:** equipment/bag item identity, locks, combat/cast/zone/mount/spec state.
2. **Intent:** newest manual request plus active automatic event intentions and queue policy.
3. **Event frames:** ordered instances, each with a unique sequence ID, event name, set name, origin, slots written, and per-slot prior values.
4. **Transaction:** one serialized equip operation with source/destination plan, submitted steps, confirmed steps, locks, timeout reason, and completion/abort outcome.
5. **Display:** derived from confirmed observed state and intent; never used as restoration truth.

A conceptual event frame:

```text
{
  frameId,
  eventName,
  setName,
  sequence,
  slotsWritten = { [slot] = newItem },
  priorSlots   = { [slot] = previousItem },
  status       = "pending" | "active" | "removing"
}
```

When removing a buried frame, restoration should affect only slots whose value is still attributable to that frame; later frames retain ownership. If compatibility requires `.old/.oldset`, treat them as a migration/export view, not the canonical live graph.

## Remediation plan

### Phase 0 — preserve and finish the audit

- [x] Expand baseline from ten releases to v4.30, then to the original TOC-v4.24 Anniversary source and first v4.25 public artifact.
- [x] Inventory tags, releases, snapshots, core churn, issues, PRs, and all CurseForge comments.
- [x] Identify pre-existing dirty work and avoid modifying it.
- [x] Normalize and compare every `.versions` package to its same-name Git tag or, where no tag exists, its manifest/nearest identifiable source commit. Preserve mixed snapshots as independent artifacts rather than inventing equivalence.
- [ ] Complete function-level blame maps for Event, Queue, Equip transaction, SavedVariables, keybindings, and UI secure frames.
- [ ] Add the user's forthcoming reports/logs to the catalogue with exact version/build/configuration.

### Phase 1 — executable characterization before redesign

- [x] Add a Lua-capable test harness that loads production functions with mocked WoW APIs, timers, inventory locks, cursor state, event delivery, and SavedVariables.
- [x] Build deterministic event, transaction, queue, intent, inventory-refresh, and cooldown reducers/models independent of frames/UI.
- [x] Turn each code-reproducible P0/P1 path into a named production-Lua fixture; protected UI and real-client timing cases remain in the acceptance matrix.
- [x] Add invariant/property checks:
  - popping a non-owner changes nothing;
  - popping one of two same-set owners does not restore the shared gear prematurely;
  - popping a buried layer cannot overwrite a later layer's slots;
  - event ordering is deterministic regardless of Lua table insertion order;
  - only one inventory transaction is active;
  - abort clears cursor/reservations without claiming success;
  - `CurrentSet` is derived/reconciled only after observed completion;
  - unknown SavedVariable keys survive audit/migration;
  - queue readiness/policy cannot manufacture event ownership.

### Phase 2 — minimal release-blocker stabilization

- [x] Make buried removal a logical splice: it cannot physically restore through a higher owner, and successor per-slot prior state is rebased.
- [x] Replace same-set boolean suppression with distinct event-frame identities and per-slot ownership.
- [x] Apply canonical ownership consistently to Buff, Zone, Stance, Specialization, spin-down, forced-dismount, Script, and startup paths.
- [x] Give readiness-deferred automatic work authorizing provenance/generation and cancel or revalidate it before execution.
- [x] Release combat-deferred slots when their event owner ends; do not use one mixed `CombatSet` name as slot provenance.
- [x] Separate physical set matching from pure queue-policy evaluation.
- [x] Bypass nondeterministic `parentSet` discovery for live automatic ownership.
- [x] Preserve Mounted gear swaps as normal event frames.
- [x] Keep and test the report-backed beta fixes listed in F-009, except the unsafe split in-combat set macro superseded by binding containment.

### Phase 3 — canonical per-event restoration

- [x] Introduce versioned event frames with per-layer slot deltas/snapshots.
- [x] Migrate live initialization and SavedVariables safely; retain backups and backward compatibility for old sets.
- [x] Replace reliance on per-set mutable `.old/.oldset` for automatic event layers.
- [x] Define manual set requests as explicit intent with precedence and cancellation rules.
- [x] Retire cycle-splicing heuristics as automatic-event authority after equivalent reducer tests; retain legacy/manual compatibility where required.
- [x] Update technical and release documentation to describe actual behavior and migration limits.

### Phase 4 — serialized inventory transactions

- [x] Route set swaps, popup/manual swaps, AutoQueue, combat deferrals, emptying, and two-hand handling through one transaction API; remove parallel cursor sequences.
- [x] Plan all slot moves before touching the cursor; reserve unique physical copies and detect required free bag/offhand space up front.
- [x] Track submitted versus confirmed moves using observed inventory events.
- [x] Capture exact pre/post source, destination, and cursor identities; do not use cursor emptiness as the completion predicate.
- [x] Keep unavailable requested slots in the transaction result; do not give unwritten slots to event ownership or mark a partial set fully current.
- [x] Give success, retryable wait, terminal abort, and exception paths one guaranteed finalizer for cursor, lock reservations, timers, sound ownership, and diagnostics; global SFX CVar ownership is removed entirely.
- [x] Treat missing items and no-space outcomes as terminal preflight failures; rejected client moves fail by observed endpoint rather than entering an infinite lost-unlock retry.
- [x] Coalesce duplicate automatic requests; newest manual request wins after safe abort/completion.
- [x] Replace “timeout means complete” behavior with “timeout means reconcile/abort with diagnostic reason.”
- [ ] Complete the real-client matrix for unique-equipped restrictions, every move direction, full bags, paired weapons, combat/casts, loading screens, and lost unlock events.

### Phase 5 — isolate and harden queues

- [x] Replace first-entry `isAlreadyMigrated()` detection with a versioned, idempotent full queue-schema migration.
- [x] Recover legacy `ItemRackItems` metadata by loading it before migration and preserving both a deep backup and quarantine evidence.
- [x] Give manual, automatic, event, deferred, and secure-binding work explicit provenance.
- [x] Make queue context selection a pure policy query that cannot mutate or define event ownership.
- [x] Resolve queue owner, list, and enabled state atomically; stop inheritance at the explicit-gear boundary and use the same tuple throughout runtime consumers.
- [x] Make `IsSetEquipped` and queue candidate evaluation side-effect-free; scope manual choices to the resolved queue owner/context.
- [x] Define exact-first item compatibility, including enchant/gem/rune identity, legacy base-ID fallback, and paired slots.
- [x] Test per-set/global ownership, explicit boundaries, manual precedence, background changes, sparse/mixed data, and stop sentinels.
- [x] Test priority, pause, delay, burn, cooldown follower, and multiple simultaneous queued slots in the offline runtime suites.

### Phase 6 — UI, persistence, and keybindings

- [x] Add non-destructive versioned queue/event migrations, with deep recovery backups, quarantine, idempotence, and future-schema fail-closed behavior.
- [ ] Run fixture upgrades from every named historical SavedVariables checkpoint and verify minimap/options/event settings and arbitrary unknown keys survive.
- [x] Treat Blizzard's active normal binding table as canonical; never interchange `SetBindingClick` cleanup with `ClearOverrideBindings`.
- [x] Replace split secure in-combat weapon macros and post-click inference with one captured set-level request; reconcile through the normal coordinator after protection clears and never create a self-restoration snapshot.
- [x] Add offline secure-frame guards for inherited count/macro/flashing state, ghost buttons, right-click behavior, and binding lifecycle.
- [x] Replace docked, dynamic popup, and options-panel `ActionButtonTemplate`/`ActionBarButtonTemplate` inheritance with ItemRack-owned minimal templates.
- [x] Resolve the known tooltip taint path without calling `GameTooltip:Show()` from the insecure membership hook.
- [x] Replace renderer-local cooldown caches with one generation-aware item cooldown authority used by buttons, popups, notifications, and queue readiness.
- [x] Coalesce inventory dirty work, popup refreshes, and duplicate protected post-combat callbacks.
- [ ] Run the in-client taint/Masque matrix and profile rapid macro-driven swaps against an agreed CPU/frame budget.

### Phase 7 — staged release and observability

- [x] Produce `v4.45-beta1` from exact commit `c5e208a`, with source manifests and archive SHA-256 traceability.
- [ ] Run fresh install plus upgrades from v4.24/v4.25, v4.27, v4.29.4, v4.30, v4.39.2, v4.42, and latest beta SavedVariables.
- [ ] Beta in rings: automated/internal package installation complete; targeted reporters/classes and public beta soak are active; stable remains gated.
- [x] Include bounded, opt-in diagnostics/support state for event frames, transactions, queue provenance, observed locks, and exact version/build.
- [x] Document migration backups, the ambiguous-legacy limitation, and the rule that SavedVariables must be copied before reset/rollback.

## Release-candidate acceptance gate

**Current stable decision: NO-GO; beta validation is active.** `v4.45-beta1` is the instrumented validation build. Stable promotion is not eligible while a known P0/P1 finding is merely described, guarded only by a source-string test, hidden by a timeout, or untested in its required client scenario. “All reported problems resolved” means every catalogue cluster and confirmed finding has a traceable disposition; it does not mean silently excluding an unreproduced report.

For each finding/report cluster, the release ledger must record: affected versions, reproduction fixture, root cause or disproof evidence, implementation commit, regression test, supported client/flavor runs, SavedVariables/package fixture where applicable, result, and any explicitly accepted limitation. A symptom may close only when its causally relevant fixture passes; a general `npm test` result is not sufficient evidence.

| Gate | Required evidence before RC | Current status |
|---|---|---|
| Event ownership/restoration | Production-Lua state fixtures for shared sets, buried layers, stale readiness/combat intent, simultaneous transitions, reload, and manual precedence; no visible higher-layer slot is overwritten. | **Automated closure complete:** canonical frame/reducer suites pass. **Pending:** issue #15 and full event matrix in supported clients, including reload/portal/combat timing and acceptance of fail-closed ambiguous legacy migration. |
| Inventory transaction safety | Preflight plus serialized observed completion across set, manual, AutoQueue, and deferred paths; unavailable items and terminal failures finalize explicitly; cursor, reservations, timers, `CurrentSet`, and sound handling reconcile under full bags, locks, rejected API moves, paired weapons, and unique conflicts. | **Automated closure complete:** transaction suites pass and global SFX mutation is absent. **Pending:** client-only rejection, long-lock, full-bag, unique-equipped, and weapon transition cases. |
| Queue correctness and migration | Atomic queue owner/list/enabled resolution, pure predicates, explicit provenance, and direct upgrade fixtures that preserve legacy and unknown data. | **Automated closure complete:** pure policy, runtime intent, and schema-v2 migration suites pass. **Pending:** actual SavedVariables upgrades from every historical checkpoint. |
| Secure UI and bindings | In-client taint log is clean with main, popup, and options surfaces exercised; protected set requests preserve one captured intent; no ghost/inherited action state; binding upgrades preserve unrelated actions. | **Code containment complete:** ItemRack-owned templates and the empty-carrier/OOC set-binding design pass offline guards. **Pending:** taint, key-up delivery, Masque, and binding-upgrade client matrix. |
| Cooldown and performance | One generation-aware cooldown authority survives CC and honors arena reset; inventory changes are coalesced and remain within an agreed frame/CPU budget with menus, diagnostics, and Masque combinations. | **Automated cooldown/coalescing closure complete. Pending:** arena/CC timing in client plus measured macro-swap profile and approved budget. |
| Complaint traceability | Every CurseForge/GitHub/user cluster is reproduced, disproved with captured evidence, or listed as a named known limitation with impact and workaround. P0/P1 limitations require explicit maintainer go/no-go approval and cannot be marketed as fixed. | **Open:** cooldown and macro-hitch paths are now identified but not yet reproduced against exact reporter builds; several version-poor reports remain. |
| Client and upgrade matrix | Clean install and SavedVariables upgrades from the phase-7 checkpoints on every supported WoW flavor/build, including class/spec-specific event paths. | **Not run.** |
| Package integrity and rollback | Beta archive is generated from one committed tree; TOC/version/changelog/tag/manifest hashes agree; extracted archive passes tests; rollback remains available. | **Beta gate complete:** tag `v4.45-beta1` resolves to `c5e208a`; the verified archive and checksum are published and the same staging tree is installed locally. Stable will require a new exact-candidate verification. |
| Test quality | Critical tests execute production Lua with mocked WoW APIs and deterministic timers; in-client cases cover protected/secure behavior; static guard checks remain supplemental. | **Offline gate complete:** 445 assertions execute production Lua/pure production reducers. **Pending:** in-client protected/secure and timing evidence. |

### Go/no-go procedure

1. Freeze the RC commit and generate the finding/report closure ledger from this document.
2. Run syntax, production-Lua unit/state-machine, migration, package, and deterministic stress suites from a clean checkout.
3. Run the in-client matrix with taint logging and bounded ItemRack diagnostics; preserve the exact build and support dump for every failure.
4. Re-run targeted reporter cases on the RC archive, not a loose development folder.
5. Compare the extracted archive against the frozen tree and record hashes.
6. Declare **GO** only when every gate above is closed and no unexplained P0/P1 symptom remains. Any code change after sign-off invalidates the affected evidence and requires the relevant gates to run again.

## Required behavioral test matrix

### Events and ownership

- [ ] Ghostwolf and Mounted use the same set: enter/leave in both orders.
- [ ] Ghostwolf and Mounted use different overlapping sets.
- [ ] Remove a buried event beneath a different top set: visible gear does not change, and the successor inherits the removed frame's prior slot state.
- [ ] Mount → zone transition while still mounted.
- [ ] Forced dismount on portal/summon/BG entry.
- [ ] Zone → Mounted → Combat; pop the buried Zone event.
- [ ] `SetA → SetB → SetA`, then pop each layer.
- [ ] Two distinct events map to one set; disabling/deleting either event.
- [ ] Manual set equip while event remains active; event ends later.
- [ ] Manual partial slot change while event remains active.
- [ ] Events disabled/re-enabled during active condition.
- [ ] Simultaneous zone, stance, buff, and spec transition.
- [ ] Two and three active OnMovement Buff events stop together; all transition exactly once regardless of enabled-table insertion order.
- [ ] Startup/reload while each event is active and queue state is unresolved.
- [ ] Event push while queue state is unresolved, then event pop/disable before readiness: the stale set is never equipped.
- [ ] Manual and automatic requests arrive in both orders while queue state is unresolved; explicit manual precedence is preserved.
- [ ] Associated spec set differs from the configured destination-spec default.

### Equipment transactions

- [ ] Bag→empty equipment, bag→occupied equipment, equipment→bag, equipment→equipment, bag→bag.
- [ ] Full bags, one free slot, specialized bags, and unique-equipped gem conflicts.
- [ ] Rapid A→B→C clicks while first transaction is locked.
- [ ] Client lock longer than each watchdog threshold.
- [ ] Lost `ITEM_LOCK_CHANGED`, delayed `UNIT_INVENTORY_CHANGED`, cursor already occupied.
- [ ] Cast begins/ends during a multi-pass swap; combat begins/ends mid-swap.
- [ ] One-slot versus multi-slot set completion.
- [ ] Partial failure does not set `CurrentSet` to the requested set.
- [ ] With swap sounds disabled and LibSoundIndex absent, every success/abort/error path restores the prior SFX state exactly once and never overwrites a later user CVar change.
- [ ] Full bags plus a requested empty equipment slot terminates once with “Not enough room”; it leaves no `SwapList`, `SetSwapping`, watchdog, cursor, reservation, or silent partial-success state.
- [ ] A predictable no-space/unique conflict on a later slot is rejected before any earlier slot is submitted.
- [ ] A rejected destination pickup that returns the original source is not classified as success; `SwapList` remains pending or terminates with an exact reason until observed destination identity agrees.
- [ ] A stale/empty source cannot move the destination item backward and cannot complete the requested set.
- [ ] All-missing and partly missing sets produce explicit unsatisfied/partial outcomes, never full completion; automatic layers own only confirmed written slots.
- [ ] Bound weapon-only and mixed sets in combat with EquipToggle on/off preserve pre-click history and never submit an inverse/duplicate request from `PostClick`.
- [ ] Popup/manual and AutoQueue bag→occupied-slot swaps return displaced gear to its exact source, observe destination success, and never leave a cursor item; repeat for two-hand/offhand transitions.
- [ ] A locked offhand encountered after fallback sound muting defers once and restores the prior SFX state with no orphan timer or overwrite of a later CVar change.

### AutoQueue/combat queue

- [ ] Event enter in combat → deferred equip → event exits before combat ends: no event item equips after combat.
- [ ] Two deferred set/event requests write overlapping and disjoint slots; every slot retains one explicit current owner.
- [ ] Weapon portion swaps during combat while armor is deferred, then the event ends before combat: reconcile both observed and unsubmitted portions.
- [ ] Event-stack queue inheritance never combines `Queues` from one owner with `QueuesEnabled` from another.
- [ ] A higher event's explicit `equip[slot]` applies the documented queue boundary; lower/global policy cannot silently replace that item.
- [ ] Calling `IsSetEquipped` for every saved/event set cannot clear or alter the active context's manual queue choice.

- [ ] Direct SavedVariables upgrades from v4.24/v4.27/v4.29.7 with custom `ItemRackItems` keep/priority/delay values.
- [ ] All-legacy, all-new, mixed, partially migrated, empty, and stop-marker-only queue schemas.
- [ ] Same base trinket/ring in paired slot, with and without another bag copy.
- [ ] Two or more cooldown slots equipped as a set.
- [ ] Start an item cooldown with its popup closed, enter CC/LoC, then open the popup; docked, popup, notification, and queue consumers agree.
- [ ] Enter an arena with a pre-existing cooldown and publish the authoritative reset before/at/after the current one-second retry boundary; stale cache data is never re-adopted.
- [ ] Manual advance during combat with AutoQueue enabled/disabled.
- [ ] Per-set queue context inherited beneath mount/zone layers.
- [ ] Queue context check on/off does not alter event ownership/restoration.
- [ ] Pause, priority, delay, burn-on-use, cooldown follower, and reload persistence.
- [ ] Exact enchant/gem/rune copies plus legacy base-ID entry.
- [ ] Queue state unavailable during loading/zone settlement.

### UI/data/release

- [ ] Upgrade bindings from v4.26/v4.29.7/v4.29.9/v4.42 without overwriting unrelated Blizzard actions or reviving deleted set buttons.
- [ ] Key overwrite prompt with `%` in set/event/binding text and two existing keys.
- [ ] Extended mouse buttons, screenshot key, combat key-up behavior, explicit unbind.
- [ ] Quick button hidden across reload/Masque/action-bar interference.
- [ ] Slot 20 and item buttons contain no inherited count/macro/flashing residue.
- [ ] Dynamically created popup buttons are absent from Blizzard action-button dispatcher tables and do not expose action-slot text/count/glow state.
- [ ] Load and open the options module before and during combat; all 20 slot selectors and the set-icon control are absent from action dispatchers and produce no taint/action-slot residue.
- [ ] Minimap/icon/settings persistence across all migration fixtures.
- [ ] Tooltip set membership with no protected-action taint.
- [ ] Record inventory-event, button-update, set-identity, bag-scan, tooltip-scan, popup-build, cooldown-update, and Masque-call counts/timings for 1-slot and 19-slot swaps with menu/diagnostic/Masque permutations; enforce an agreed budget.
- [ ] Package file tree and manifest match the tagged source.

## Investigation backlog

- [x] Finish normalized full-tree comparisons for every v4.24-v4.29.9 artifact, including the no-single-commit 4.27 betas, 4.27.3, and 4.29.2 folders and the package/tag mismatch in 4.29.6.
- [ ] Build function-level lineage tables from v4.24 for secure buttons/keybindings, specialization ownership, manual queue cycling, and per-set queue migration.
- [x] Inspect `UnequipSet` and `PreventLiveOldsetCycle` across v4.30, v4.39.2, v4.41, and current using explicit X→Y→X and buried-pop traces; automatic ownership now bypasses this graph.
- [x] Trace every call site of `IsSetEquipped` and separate physical identity, queue intent, display identity, and ownership through the new policy/frame boundaries.
- [x] Trace and replace unordered single-winner handling in Buff, Zone, Stance, and Specialization processing with deterministic frame transitions.
- [x] Verify whether more than one OnMovement event can share/cancel the global pending timer. Confirmed as F-028: one unordered winner is popped and additional stopped events remain active/stacked.
- [x] Build production-Lua state fixtures for the code-reproducible paths in F-025 through F-041; protected-template and real timing behavior remains an in-client acceptance gate.
- [x] Reconstruct issue #15's shared-set, stale-pop, buried-owner, and self-prior failure classes in the event reducer and current integration model. Historical-client replay against each named version remains optional attribution evidence; the RC client case remains required.
- [x] Validate issue #21 against current `PendingSpecSet`, including newer manual choice, forced same-spec refresh, expiry, deletion, and failed/unexpected transition fallbacks. Real cast cancel/timeout remains in the client matrix.
- [ ] Reproduce full-bag plus unique PvP gem combinations in client. Offline preflight and transaction fixtures close empty-slot/no-space, duplicate physical source, rejection, and partial-success claims; exact client unique-equipped rules remain open.
- [ ] Profile Battle Shout hotswap hitch and separate Lua CPU, menu rebuild, inventory scan, Masque, logging, and client-lock time. F-040 establishes the uncoalesced fan-out; causal share and performance budget remain open.
- [x] Trace cooldown-display reset reports independently of queue cooldown selection. F-038/F-039 identify the arena reset race and closed-popup observation gap; exact in-client report attribution remains open.
- [x] Audit secure action attributes and inherited regions for comments #151/#172. F-015/F-018/F-041 cover popup, docked, and options action-template surfaces. Right-click behavior in #175-#178 still needs explicit UX/client tests.
- [x] Compare all 47 extracted package trees with tags/manifests/nearest source commits and document deviations under Release-integrity notes.

## Validation snapshot

On 2026-09-03, on branch `dev` with the post-beta working tree based on `8dbc607`, `npm test` passed end to end:

- 11 production files parsed as Lua 5.1.
- Transactions: 25 integration plus 30 engine assertions.
- Events: 177 frame/reducer, 19 integration, and 39 processor assertions.
- Queues: 12 policy, 9 runtime, 21 intent, 42 migration, and 6 migration-static checks.
- Cooldowns: 20 authority plus 20 integration assertions.
- Inventory refresh: 12 coalescing assertions.
- Set bindings: 37 intent/containment/reconciliation assertions.
- Large profiles: 42,128 event checks across 64 sets and 100 activations; 8,749 queue checks across 64 sets/19 slots and a 96-entry stack; 7,509 migration checks across 931 queues/3,724 records; and 2,746 transaction checks across 24 complete sets and 97 generated switches.
- Structure: 32 checks; secure templates: 55; cross-cutting regressions: 40.
- Event compatibility: 18; item identity: 21; queue/watchdog: 16; release flow: 19.

This is 61,595 reported production-Lua checks, 6 migration-static guards, and 201 reported structural/release guards. The suite now executes the previously absent buried per-slot restoration, shared/repeated frames, same-event generation replacement, stale intent cancellation, simultaneous movement events, atomic queue context, large/malformed profile migration, side-effect-free identity, exact endpoint confirmation, terminal missing/no-space behavior, multi-step rollback, cursor ownership, cooldown reset publication, closed-popup cooldown state, coalescing, set-binding containment, and cumulative beta-note generation paths.

Still outside automated proof: Blizzard's protected execution and taint engine, exact client item-lock timing, every unique-equipped rule, real Masque interaction, historical SavedVariables loaded by each supported client, and the CPU/frame budget under macro-driven swaps. Those are the remaining acceptance gates; they must not be inferred from this green suite.

## Decision log

| Date | Decision | Reason |
|---|---|---|
| 2026-09-02 | Initial working boundary set at v4.30, with v4.29.4-v4.29.9 as regression controls. | v4.30 is the EventStack boundary and issue #15 reports v4.29.4 as a working rollback; this boundary was later superseded by the row below. |
| 2026-09-02 | Expand the durable audit baseline to the original internal v4.24 source and first public v4.25 package. | The user requested the full Anniversary lineage. This separates inherited 4.23 behavior from Anniversary-introduced adaptations and regressions. |
| 2026-09-02 | No production fixes are implemented during the evidence-gathering pass. | The request is review and planning first; current uncommitted work must remain independently reviewable. |
| 2026-09-02 | Preserve Mounted gear swaps and solve ownership/restoration. | Removing the feature avoids one collision but does not fix the underlying event identity mismatch. |
| 2026-09-02 | Treat release notes, tags, and packages as separate artifacts. | Several release entries/manifests are missing or inconsistent. |
| 2026-09-02 | Complete normalized comparison across all 47 local snapshots; never substitute a same-name tag for a differing package. | Thirteen same-name tag/package pairs differ in core Lua, several untagged early packages are mixed checkpoints, and later source manifests provide stronger identity where present. |
| 2026-09-02 | Retain existing static/model checks but do not treat them as runtime proof. | They are useful guards and all pass, but they do not execute the real asynchronous Lua/WoW workflow. |
| 2026-09-03 | Make versioned per-event frames and per-slot prior values the canonical live ownership model. | A set-name `.old/.oldset` graph cannot represent shared sets, buried removal, or repeated `X → Y → X` layers. Legacy fields remain migration/compatibility evidence only. |
| 2026-09-03 | Serialize all equipment mutation through an observed endpoint transaction and remove global SFX CVar mutation. | Cursor emptiness and timeout are not success; all mutation sources need one owner, explicit terminal outcomes, and one cleanup boundary. Per-sound suppression is optional through LibSoundIndex. |
| 2026-09-03 | Adopt schema-v2 queue migration and schema-v1 event-state migration with backup, quarantine, idempotence, and future-schema fail-closed behavior. | Direct upgrades must retain recoverable user data; unknown representations must never be guessed or downgraded. |
| 2026-09-03 | Replace synthetic in-combat set macros with an empty protected carrier and out-of-combat set-level reconciliation. | Split weapon execution could not preserve coherent pre-click history or transaction ownership. The safe compatibility contract favors correctness over claiming arbitrary in-combat set swaps. |
| 2026-09-03 | Keep the RC at NO-GO after automated closure. | The implementation is ready for candidate validation, but protected-action/taint behavior, historical profile upgrades, reporter cases, performance, and exact committed-package integrity remain unrun. |
| 2026-09-03 | Publish `v4.45-beta1` as the Primary Reliability Overhaul and keep stable gated. | The exact tagged archive passed automated/package validation and was installed across all four local clients. Live-client and reporter evidence now determines whether corrections or stable promotion follow. |

## Information requested from maintainers/reporters

These questions do not block the audit, but their answers will make reproductions much stronger:

1. Exact addon version and WoW flavor/build for each new complaint.
2. Class/spec and whether Ghostwolf, Mounted, Zone, Stance, or Specialization events share a set.
3. Whether per-set queues and queue-context checking are enabled.
4. A support dump captured before `/reload`, plus SavedVariables copied before any reset.
5. Whether bags were full, an item used a unique-equipped gem, or the requested item was in bank/equipped in the paired slot.
6. Expected precedence when a manually selected set conflicts with an active automatic event: manual until the condition changes, manual until explicitly resumed, or event immediately reasserts.
