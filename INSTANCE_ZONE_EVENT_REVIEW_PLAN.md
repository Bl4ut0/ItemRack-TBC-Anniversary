# Instance Zone Event Review and Dev Plan

## Scope

This review focuses on reports where gear swaps do not happen when entering or moving between instances. The highest-risk code paths are:

- `ItemRack/ItemRack.lua`: world, zone, combat, casting event dispatch.
- `ItemRack/ItemRackEvents.lua`: event registration, zone matching, event stack push/pop, buff and stance exclusions.
- `ItemRack/ItemRackEquip.lua`: set equip/unequip, lock deferral, restoration history.

The supplied beta1 dump also shows one configuration issue: the `PVP` zone event exists, but it is not enabled in `ItemRackUser.Events.Enabled`. In that specific dump, the `pvp` set should not be expected to equip from the Zone event system. The code findings below still apply to instance swaps in general.

## Code Review Findings

### P1 - Instance loads do not force a settled zone-event recheck

`ItemRackFrame` registers `PLAYER_ENTERING_WORLD` in `ItemRack/ItemRack.lua`, but `ItemRack.OnEnterWorld()` only updates arena visibility, buttons, bindings, and current-set display. It does not call or schedule `ItemRack.ProcessZoneEvent()`.

Relevant code:

- `ItemRack/ItemRack.lua:393`: `PLAYER_ENTERING_WORLD` is routed to `ItemRack.OnEnterWorld`.
- `ItemRack/ItemRack.lua:632-647`: `OnEnterWorld()` does not re-evaluate event sets.
- `ItemRack/ItemRackEvents.lua:426-432`: the event-processing frame registers `ZONE_CHANGED_NEW_AREA` and `ZONE_CHANGED_INDOORS` for Zone events, but not `PLAYER_ENTERING_WORLD`.

Why this matters:

Instance transitions commonly involve a loading-screen world entry. If `ZONE_CHANGED_NEW_AREA` fires too early, does not fire in the expected order, or runs before `IsInInstance()` / zone text is stable, there is no later guaranteed Zone re-evaluation.

Expected behavior:

After `PLAYER_ENTERING_WORLD`, schedule one or more delayed event rechecks after the client has stable world and instance state.

### P1 - Zone transitions inside an already-active Zone event can suppress re-equip

`ProcessZoneEvent()` treats an active Zone event whose set is not currently equipped as a manual override, even when `LastZoneMatched` changed.

Relevant code:

- `ItemRack/ItemRackEvents.lua:777-840`

Current behavior:

```lua
if not events[eventName].Active or events[eventName].LastZoneMatched ~= matchedZone then
  if not ItemRack.IsSetEquipped(setname) then
    if events[eventName].Active then
      events[eventName].ManualOverride = true
    else
      eventToEquip = eventName
    end
  end
end
```

Why this matters:

This preserves manual override inside the same zone, but it also blocks a new instance/subzone transition from reasserting the event gear. The changelog says zone gear should re-equip on every valid zone transition, but this branch only equips on first entry when `.Active` is false.

Expected behavior:

Manual override should be scoped to the same zone/instance state. A real transition should clear the override and reassert the zone set.

### P1 - Instance-type matches are too coarse for transition tracking

Zone matching supports instance keywords such as `party`, `raid`, `pvp`, and `arena`.

Relevant code:

- `ItemRack/ItemRackEvents.lua:761-774`

Current behavior:

If a Zone event matches by instance type, `matchedZone` becomes only the coarse type string, such as `party` or `raid`.

Why this matters:

Moving from one dungeon to another can keep `matchedZone == "party"`. Moving from one raid to another can keep `matchedZone == "raid"`. That means `LastZoneMatched` may not change even though the player changed instances. Manual override can therefore leak across different instances of the same type, and re-equip may not be attempted.

Expected behavior:

Track a separate zone-state signature, not just the matched rule. The signature should include at least real zone text, subzone text, and instance type. If available in the target client, an instance map ID or instance ID would make this stronger.

### P2 - Active mount preservation looks up a set by event name

The beta1 custom mount fix searches the active event stack for any event with `Anymount`, which is the right direction. However, one branch still treats the event name as the set name.

Relevant code:

- `ItemRack/ItemRackEvents.lua:790-803`

Current behavior:

```lua
if ItemRackUser.Sets[activeMountEvent] and ItemRackUser.Sets[activeMountEvent].oldset == setname then
```

For a user event named `pvp mount` with set `pvpm`, `ItemRackUser.Sets["pvp mount"]` normally does not exist. This causes the branch to miss the actual mount set history.

Expected behavior:

Resolve the mount set through `ItemRack.GetEventSet(activeMountEvent)` or `ItemRackUser.Events.Set[activeMountEvent]`, then inspect `ItemRackUser.Sets[activeMountSet]`.

### P2 - Excluded active buff or stance events are skipped instead of unwound

`ProcessBuffEvent()` and `ProcessStanceEvent()` set `skip` for exclusions like `NotInPVP` or `NotInPVE`, then skip the whole event body.

Relevant code:

- `ItemRack/ItemRackEvents.lua:710-719`
- `ItemRack/ItemRackEvents.lua:1050-1065`

Why this matters:

If an event is already active before entering an excluded instance type, the skip path can avoid calling `PopEvent()` and avoid clearing `.Active`. This is not the main generic instance-entry issue from the supplied dump, but it can become a contributing event-stack bug for mounted, buff, or stance sets.

Expected behavior:

If an event is active and its exclusion becomes true, the event should be treated as no longer matching: pop it when `Unequip` is enabled, clear `.Active`, and clear any pending movement unequip state for that event.

### P2 - Combat/casting release comments promise all event types but only buffs recheck

`OnLeavingCombatOrDeath()` and `OnCastingStop()` both comment that event-based sets are re-evaluated after restrictions are lifted. They only call `ProcessBuffEvent()`.

Relevant code:

- `ItemRack/ItemRack.lua:737-740`
- `ItemRack/ItemRack.lua:822-826`

Why this matters:

If an instance transition happens while a swap is blocked by combat, casting, death, or locks, the system should re-run Zone/Stance/Spec decisions after restrictions clear. Currently Zone events rely on whatever was queued earlier, or on a later zone event that may never arrive.

Expected behavior:

Use a shared event recheck helper that can re-run Zone, Buff, Stance, and Spec processors safely when the client state changes or restrictions lift.

### P3 - Zone event loop stores only one pending equip and one pending unequip

`ProcessZoneEvent()` uses scalar `eventToEquip` and `eventToUnequip`.

Relevant code:

- `ItemRack/ItemRackEvents.lua:763`
- `ItemRack/ItemRackEvents.lua:859-864`

Why this matters:

If more than one Zone event changes state in the same scan, the last event encountered wins. `pairs()` order is not deterministic, so overlapping zone events can behave inconsistently.

Expected behavior:

Collect pending unequips and equips into ordered lists. Pop all ended events first, then push chosen/active matching events in deterministic priority.

### P3 - Enabled event entries are not consistently nil-guarded

Several loops assume every enabled event has a matching `ItemRackEvents[eventName]`.

Relevant code:

- `ItemRack/ItemRackEvents.lua:410-412`
- `ItemRack/ItemRackEvents.lua:633-635`
- `ItemRack/ItemRackEvents.lua:767-768`
- `ItemRack/ItemRackEvents.lua:1050-1051`

Why this matters:

SavedVariables repair should usually prevent this, but a stale enabled key can still turn into a Lua error and stop all event processing.

Expected behavior:

Guard `events[eventName]` before reading `.Type`; log or prune bad entries through the auditor path.

## Proposed Solution Strategy

### Phase 1 - Add a centralized event recheck scheduler

Create a small helper in `ItemRackEvents.lua` or `ItemRack.lua`:

```lua
function ItemRack.ScheduleEventRecheck(reason, delays)
  -- Coalesce by timer name or reason.
  -- Run ProcessZoneEvent, ProcessBuffEvent, ProcessStanceEvent, and ProcessSpecializationEvent when available.
end
```

Recommended first use:

- On `PLAYER_ENTERING_WORLD`: schedule checks at about `0.5s` and `1.5s`.
- On `ZONE_CHANGED_NEW_AREA` and relevant `ZONE_CHANGED_INDOORS`: keep the existing short Zone timer, and optionally schedule the settled recheck.
- On casting/combat/death release: run the same helper instead of only `ProcessBuffEvent()`.

Design goal:

Make instance transition handling reliable without relying on one event firing in exactly the right order.

### Phase 2 - Separate matched rule from actual zone-state signature

Keep `matchedZone` as the rule that matched, but add a transition signature:

```lua
local zoneSignature = table.concat({
  tostring(instanceType or "none"),
  tostring(currentZone or ""),
  tostring(currentSubZone or "")
}, "\031")
```

If a stable map or instance ID API is available in this client, include it in the signature.

Store:

- `events[eventName].LastZoneMatched = matchedZone`
- `events[eventName].LastZoneSignature = zoneSignature`

Use `LastZoneSignature` to decide whether the player has entered a meaningfully different place.

### Phase 3 - Fix manual override scoping

Update `ProcessZoneEvent()` semantics:

- If matched and inactive: equip normally.
- If matched, active, same signature, and set is not equipped: treat as manual override.
- If matched, active, different signature: clear manual override and re-equip/reassert the zone set.
- If not matched and active: pop/clear normally.

This keeps the 4.38 manual override protection inside the same zone while restoring the 4.31/4.29.8 re-equip behavior on actual transitions.

### Phase 4 - Fix active mount set resolution

Replace event-name set lookup with event-set resolution:

```lua
local activeMountSet = ItemRack.GetEventSet(activeMountEvent)
local activeMountSetData = activeMountSet and ItemRackUser.Sets[activeMountSet]
```

Then compare:

```lua
activeMountSetData.oldset == setname
```

Also add debug output for `activeMountEvent`, `activeMountSet`, `oldset`, `targetZoneSet`, and `instanceType`.

### Phase 5 - Treat exclusion as a state transition, not a skip

For Buff and Stance processors:

- Compute `excluded`.
- If `excluded` and event is active, pop/clear the event.
- If `excluded` and event is inactive, continue.
- Only process normal buff/stance matching when not excluded.

For OnMovement events, also clear `ItemRack.PendingOnMovementUnequip` if it references the excluded event.

### Phase 6 - Make pending zone transitions deterministic

Change `ProcessZoneEvent()` from scalar `eventToEquip` / `eventToUnequip` to tables:

- `eventsToUnequip = {}`
- `eventsToEquip = {}`

Process all unequips before equips. If multiple Zone events match at once, define a deterministic priority. A conservative first pass is to keep current behavior but deterministic by sorted event name. A better later pass is explicit event priority.

### Phase 7 - Add safer guards and diagnostics

Add nil guards around enabled event loops:

```lua
local eventData = events[eventName]
if eventData then
  ...
else
  ItemRack.Debug("Events", "Enabled event missing from ItemRackEvents:", eventName)
end
```

Add a focused debug trace in `ProcessZoneEvent()`:

- reason/source if passed in
- current zone
- subzone
- instance type
- matched rule
- zone signature
- old signature
- active flag
- manual override flag
- chosen action: equip, reassert, suppress, pop, none

## Dev Test Plan

### Basic instance entry

1. Create a Zone event matching `party`, bound to a test set.
2. Start outside an instance in a non-test set.
3. Enter a dungeon.
4. Expected: after `PLAYER_ENTERING_WORLD`, logs show a settled recheck and the `party` set equips.

Repeat for `raid`, `pvp`, and `arena` where available.

### Specific instance names

1. Create a Zone event with a specific instance zone name.
2. Enter that instance from the open world.
3. Expected: the event equips after load even if `ZONE_CHANGED_NEW_AREA` was missed or early.

### Same-type instance transition

1. Create a Zone event matching `party`.
2. Enter dungeon A and confirm the set equips.
3. Manually equip another set inside dungeon A.
4. Move to dungeon B without relying on a long open-world stay, if testable.
5. Expected: new zone signature clears manual override and reasserts the party set.

### Same zone manual override protection

1. Enter a matched Zone event.
2. Manually equip another set.
3. Trigger a same-zone event refresh.
4. Expected: the zone set does not fight the user in the same zone signature.

### Leaving an instance

1. Enter a matched instance and equip the zone set.
2. Leave the instance.
3. Expected: Zone event pops and restores previous gear, respecting the event stack.

### Mounted transition with custom event name

1. Create a custom mount event name, such as `pvp mount`, bound to a set whose name is different, such as `pvpm`.
2. Mount and move so the event is active.
3. Enter a matched zone/instance event.
4. Expected: debug logs show event name and set name separately; mount preservation uses the set name and does not misread `ItemRackUser.Sets[eventName]`.

### Exclusion unwind

1. Create a Buff or Stance event with `NotInPVE`.
2. Activate it outside an instance.
3. Enter a dungeon or raid.
4. Expected: the event pops/clears when it becomes excluded.

Repeat with `NotInPVP` for battleground or arena.

### Combat/casting/death deferral

1. Trigger a zone event while swaps are blocked by combat, casting, death, or item locks where practical.
2. Expected: the event recheck runs when restrictions clear, pending swaps process, and `CurrentSet` converges to the expected set.

### Stale SavedVariables guard

1. Inject an enabled event key that has no matching `ItemRackEvents[eventName]`.
2. Reload.
3. Expected: no Lua error; debug/audit identifies the stale event.

## Acceptance Criteria

- Entering an instance reliably re-evaluates Zone events after `PLAYER_ENTERING_WORLD`.
- A manual override is respected within the same zone/instance signature.
- A new instance or zone signature clears stale manual override and can reassert the Zone set.
- Instance keyword events (`party`, `raid`, `pvp`, `arena`) do not leak override state across distinct instances.
- Custom mount event names work when the event name differs from the set name.
- Buff/Stance exclusions unwind active events instead of leaving stale stack entries.
- Combat/casting/death release rechecks all relevant event types, not only Buff events.
- Debug logs clearly explain why a zone set did or did not equip.

## Suggested Branch Work Order

1. Add debug instrumentation and `ScheduleEventRecheck()` first.
2. Wire `PLAYER_ENTERING_WORLD`, combat release, and casting release into the scheduler.
3. Add zone signatures and manual-override scoping.
4. Fix mount event set resolution.
5. Fix exclusion unwind.
6. Convert scalar zone pending actions to deterministic lists if tests show overlapping zone events are still unstable.
7. Add nil guards and auditor cleanup for stale enabled events.
8. Run the dev test matrix and compare `/itemrack dump` before and after each scenario.

## Risk Notes

- The manual override fix is the riskiest behavior change. It must preserve "do not fight the user in the same zone" while reasserting on true transitions.
- The settled recheck scheduler should coalesce repeated calls to avoid spamming swaps during load screens.
- Zone signatures should be stored as runtime state only. Do not persist them as durable SavedVariables beyond the active session.
- Avoid changing `EquipSet()` and `UnequipSet()` restoration semantics in the first pass unless the event-layer fixes still leave reproducible failures.
