# Changelog - ItemRack TBC Anniversary

All notable changes to the TBC Anniversary port of ItemRack will be documented in this file.

## [Development]

### Improvements
- **Classic Era 1.15.9 Support**: Updated interface version from 11508 to 11509 in TOC files for Classic Era 1.15.9 (build 68808) compatibility, while maintaining support for TBC Anniversary 2.5.5 and 2.5.6.

## [4.41] - 2026-07-25

### Bug Fixes & Improvements
- **Ghost Buttons Visibility Fix**: Fixed a bug where quick-access buttons that had been toggled off (removed) would reappear as empty grey squares on login or character reload. Securely wrapped the button's `Show()` method to prevent external addons (like Masque) or Blizzard's internal Action Bar system from showing buttons that are not currently active in the user's layout.
- **Tooltip Set Info Containment Fix**: Fixed a bug where enabling "Show set info in tooltips" caused appended set lines to fall outside the bottom boundary of the tooltip window. Restored `tooltip:Show()` inside `ListSetsHavingItem` after set lines are added so that `GameTooltip` recalculates its height and correctly contains the set names within the tooltip backdrop.
- **Forced-Dismount Event Stack Recovery**: Fixed summon, portal, and instance transitions that dismount the player while a mount set is active. Mounted events are now unwound before destination Zone sets are applied, preventing inactive mount entries and `Zone -> Mounted` restoration chains. Still-mounted transitions preserve the mount layer above the matching Zone event, while combat/casting and in-progress swaps defer reconciliation safely.
- **Live `oldset` Cycle Prevention**: Implemented `ItemRack.PreventLiveOldsetCycle` to detect and splice circular set restoration chains (`SetA -> SetB -> SetA`) in real-time when users manually or automatically toggle between gear sets during live gameplay, preventing UI locks and infinite set restoration loops.
- **In-Combat Weapon Swapping**: Updated `EquipSet` and `ProcessCombatQueue` to permit weapon slot swaps (slots 16 Mainhand, 17 Offhand, 18 Ranged) to execute immediately during combat when not spellcasting, while non-weapon armor slots continue to defer safely to `CombatQueue`.
- **Event Enable/Disable Spin-Down & Spin-Up**: Added `ItemRack.SpinDownEvent` and `ItemRack.SpinUpEvent`. Unchecking or deleting an event in the Events Options menu now immediately unwinds/spins down the event if it is currently active, popping it off the event stack and restoring base gear. Checking an event immediately evaluates whether the event condition currently applies and spins it up.

## [4.40] - 2026-06-29
### Bug Fixes & Improvements
- **TBC PTR 2.5.6 Support**: Added interface version `20506` to `ItemRack.toc` to ensure compatibility with the Burning Crusade Classic 2.5.6 PTR client.
- **Left-side Menus Off-screen Fix (Issue #17)**: Fixed character sheet left-side popout menus rendering off-screen by default in the default WoW UI. Defaulted `LeftSlotsGoRight` to `"ON"` and added a one-time profile migration to update existing configurations. (Fix provided by `physixtential`)
- **GameTooltip Taint Fix**: Fixed `ADDON_ACTION_BLOCKED` taint errors on Blizzard action buttons (`SetAttribute`) caused by calling `tooltip:Show()` inside `ListSetsHavingItem` under insecure hooks. Removed the redundant `Show()` call.
- **Auto-Queue Stuck Slots Fix**: Resolved a bug where equipping an item set containing multiple items already on cooldown (with Auto-Queue enabled) only swapped the first slot. Subsequent slots were deferred to the combat queue and got stuck outside of combat. `ItemRack.LocksChanged()` now sequentially processes deferred combat queue swaps and waiting sets.
- **Manual Swaps Combat Queue Fix**: Fixed a bug where manual item swaps or manual set swaps queued during combat were deleted from the combat queue if the currently equipped item in that slot was ready (had no active cooldown). `ProcessAutoQueue` now respects `ItemRack.AutoQueueFlag[slot]` and only removes auto-queued swaps.

## [4.40-beta2] - 2026-06-15
### Bug Fixes & Improvements
- **Auto-Queue Stuck Slots Fix**: Resolved a bug where equipping an item set containing multiple items already on cooldown (with Auto-Queue enabled) only swapped the first slot. Subsequent slots were deferred to the combat queue and got stuck outside of combat. `ItemRack.LocksChanged()` now sequentially processes deferred combat queue swaps and waiting sets.
- **Manual Swaps Combat Queue Fix**: Fixed a bug where manual item swaps or manual set swaps queued during combat were deleted from the combat queue if the currently equipped item in that slot was ready (had no active cooldown). `ProcessAutoQueue` now respects `ItemRack.AutoQueueFlag[slot]` and only removes auto-queued swaps.

## [4.40-beta1] - 2026-06-14
### Bug Fixes & Improvements
- **Manual Swaps Combat Queue Fix**: Fixed a bug where manual item swaps or manual set swaps queued during combat were deleted from the combat queue if the currently equipped item in that slot was ready (had no active cooldown). `ProcessAutoQueue` now respects `ItemRack.AutoQueueFlag[slot]` and only removes auto-queued swaps.

## [4.39.9] - 2026-06-14
### Bug Fixes & Improvements
- **Options Screen Clamping**: Enabled `clampedToScreen` and added runtime clamping updates for `ItemRackOptFrame` and `ItemRackFloatingEditor`. This prevents the options page and script editor from clipping off-screen when the frame scale is increased.

## [4.39.8] - 2026-06-13
### Accessibility & Layout Improvements
- **Accessibility Options Sizing**: Replaced the options scale slider/editbox with three mutual-exclusive checkboxes (**Default size**, **Bigger**, and **Biggest**) to easily size the options frame for visually impaired players. Profile migration auto-maps existing custom slider scales onto the checkboxes on login.
- **Separated Wrap Settings**: Split menu wrapping into two independent settings: **Quick menu wrap** (for quick-access and set-list dropdowns, wrapping horizontally) and **Char sheet wrap** (for character pane hover lists, wrapping vertically). This prevents layout conflicts arising from different default orientations.
- **Set Menu Wrap Layout Bugfix**: Fixed a layout bug where floating-point numbers returned from WoW's slider API (e.g. `3.0000001` instead of `3`) caused wrapping logic (`col == max_cols`) to fail. Added `math.floor` cast and `>=` comparison to ensure correct wrapping on popout menus (like the sets menu).

## [4.39.7] - 2026-06-12
### Bug Fixes
- **Tooltip Anchoring Overlap**: Fixed a bug where right-side character sheet slots (Gloves through Rings) would have their tooltips anchor to the left and overlap the popout menus due to a timing race condition with coordinate-based layout evaluations. Replaced coordinate lookups with a deterministic settings-based evaluation.

## [4.39.6] - 2026-06-12
### Bug Fixes
- **Tooltip Anchoring Inconsistency**: Restored the tooltip default popout direction for right-side slots to the left (matching the behavior prior to version 4.39.4). Aligned the `AnchorTooltip` logic to match the slot-enter layout, resolving positioning conflicts and flickering during active cooldown updates.

## [4.39.5] - 2026-06-12
### Event Swapping & Instance Transitions
- **Centralized Event Recheck Scheduler**: Added `ItemRack.ScheduleEventRecheck` and `ItemRack.RunAllEvents` to safely schedule and run event-based evaluations. Schedules automatic settled checks at `0.5s` and `1.5s` upon entering the world/instances (`PLAYER_ENTERING_WORLD`), and on zone changes (`ZONE_CHANGED_NEW_AREA`).
- **Unified Event Release Triggers**: Refactored combat and casting stop events (`OnLeavingCombatOrDeath` and `OnCastingStop`) to run rechecks on all event categories (stances, spec, zones, buffs) instead of only buffs.
- **Signature-Aware Zone Transitions**: Implemented multi-field zone signatures (incorporating instance type, zone text, subzone text, and unique instance ID) to cleanly differentiate between distinct dungeons of the same type.
- **Improved Manual Override Protection**: Refactored override scoping in `ProcessZoneEvent`. Manual gear swaps are strictly protected within the same zone signature but automatically cleared upon zoning into a different zone/instance signature, allowing zone set auto-equip to resume.
- **Exclusion Unwinding**: Rewrote buff and stance exclusion checks (`NotInPVP`/`NotInPVE`). When an event is active but its exclusion becomes true, the event is immediately unwound/popped from the stack rather than skipped, preventing zombie sets from sticking on the event stack.
- **Deterministic Zone Swaps**: Replaced scalar pending zone actions with alphabetical sorting lists (`eventsToUnequip` and `eventsToEquip`), ensuring all unequips finish before equips are processed in a stable, deterministic order.
- **Mount Set Resolution Fix**: Corrected set lookup in `ProcessZoneEvent` for mount events by resolving the set name through the active event data structure instead of using the raw event name.
- **Defensive Programming Nil-Guards**: Added nil guards around enabled event lookups across all event processors to avoid Lua errors with corrupt profile data.

### Bug Fixes
- **Masque Quick Slot Skinning**: Fixed Masque skinning for Quick Access buttons by passing explicit button regions (`Icon`, `Cooldown`, `Count`, `HotKey`) to `AddButton`.
- **White Background Texture Fix**: Fixed a bug where the swap menu frame (`ItemRackMenuFrame`) background was rendered as a solid white texture in recent client patches. Re-anchored `bgFile` to `DialogBox-Background`.
- **Blank Diagnostic Dump Fix**: Fixed a bug where the diagnostic log and state dump window (`/itemrack dump`) appeared entirely blank due to the multiline edit box collapsing to 0 height. Added an `OnTextChanged` height recalculator script.
- **SavedVariables Auditor 'Custom' Set Guard**: Excluded the special `"Custom"` set string from database checks. Previously, running `/itemrack debug audit` or logging in while in a `"Custom"` gear state (such as being mounted with unsaved gear) would flag and clear the valid `"Custom"` history path, breaking dismount gear restoration.

## [4.39.4] - 2026-05-24
### Bug Fixes
- **Settings Persistence**: Fixed a major regression where active, dynamically-managed settings (such as the minimap icon position, events database version, show set info in tooltips, and action bar sound suppression settings) were pruned on startup by the SavedVariables auditor, causing them to reset on every logout or reload.
### Diagnostic & Logging Improvements
- **Casting & Channeling Debug Traces**: Added detailed debug logging to `OnCastingStart` and `OnCastingStop` to track when swaps are blocked and released by player casting/channeling states.
- **Combat Queue Defer Debugging**: Added debug logging when an `EquipSet` is deferred to the combat queue, indicating the deferral reason (combat, casting, or death) along with the queued slot numbers and item IDs.
- **Expanded Diagnostic Dump**: Updated `/itemrack dump` output to include additional variables (event enabled states, queue configurations, active setting tables, and current casting/channeling blocks) for more comprehensive troubleshooting.
- **Robust Debug Tag Validation**: Restricted toggling to valid debug tags, preventing the system from reporting random names as enabled. Toggling an invalid tag now prints a clean warning and displays all available layers and their status.
- **Enhanced Debug Status Output**: Refactored `/itemrack debug status` to print a complete, color-coded list of all available layers (`Events`, `Equip`, `Queue`, `CombatQueue`, `API`, `UI`, `Combat`) and their exact `ON`/`OFF` states.
- **Diagnostic Dump Reorganization**: Reorganized section output order to match development requests. Added debug states (`DebugAll`, `DebugChat`, and `DebugTags`) and restored the `ItemRackUser.Buttons` layout configuration to the dump. Reorganized options configuration list to match options UI hierarchy.
- **Auto-Dismount Zone Boundaries**: Generalized the mount check in `ProcessZoneEvent` to search the active event stack for any active event with the `Anymount` flag set, allowing custom mount event names like `"pvp mount"` to keep gear equipped correctly when transitioning zones.
- **Syntax Validation**: Resolved code duplication syntax warnings in `ItemRack.lua`. Established an automated Lua validation runner inside scratch spaces.

## [4.39.3] - 2026-05-23
### Diagnostic & Auditor Improvements
- **SavedVariables Auditor & Auto-Repairer**: Added a comprehensive database scanner (`/itemrack debug audit`) to detect and fix corruptions in sets (circular `oldset` paths, orphaned references), event stacks (duplicates, missing event names), and queues.
- **Obsolete Settings Pruning**: The auditor automatically merges missing defaults and prunes obsolete keys in `ItemRackSettings` using a load-time clone of the default settings table.
- **Audit Persistence**: Auto-fixed startup issues are notified to the user via a one-line chat alert and detailed reports are saved to `ItemRackUser.LastAudit` in the WTF database.
- **Enhanced Debug Subcommands**: Extended the `/itemrack debug` command to support `/itemrack debug help`, `/itemrack debug status`, `/itemrack debug clear`, `/itemrack debug audit`, and tag-specific toggles (`events`, `equip`, `queue`, `combatqueue`, `api`, `ui`, `combat`).
- **Dynamic Event Compile Error Safety**: Custom scripted event compilations are now wrapped securely. Compilation and runtime errors no longer crash the main event thread and are logged to the `Events` debug tag.
- **Expanded Combat Taint Tracing**: Significantly upgraded the internal diagnostic framework to help users troubleshoot "Action Blocked" combat errors.
  - Added new `Combat` and `UI` trace layers to track `InCombatLockdown()` state precisely during combat transitions and when opening/clicking ItemRack's dynamic popout menus.
  - Increased the internal `ItemRack.LogBuffer` capacity from 500 to 5,000 lines to ensure combat traces aren't lost during long arena matches or battlegrounds.
  - **Silent Tracing**: Typing `/itemrack debug` now activates all trace layers silently in the background without spamming the chat window. If you wish to view traces in real-time, use the new `/itemrack debug chat` command.
  - Expanded `/itemrack dump` output to include runtime combat state, active menu visibility, combat queue contents, and current quick-access button configurations.

### Bug Fixes
- **Ghost Overrides for Events**: Fixed an edge case in `ItemRackEvents.lua` where transient or disabled Zone events could leave their `ManualOverride` flag stuck on. This "ghost override" previously suppressed gear restorations (like dismounting or dropping a stance) permanently, even when the player was not actively using a zone set. (PR #14)
- **Event Stance and Restoration Persistence**: Fixed a bug in `ItemRackEvents.lua` where stance and gear restoration data (`.old` and `oldset`) was wiped on startup, breaking stance restoration on login or reload. Re-populates the event restoration stack automatically from active events on load.
- **Two-Handed Weapon Equipping & Cursor Lock**: Placed 2H weapon swapping at the top of the swap order so the client automatically bags the displaced offhand/shield. Added a cursor cleanup safety check to ensure any leftover item on the cursor is placed into an empty container slot.
- **Offhand Queue Guarding**: Guarded auto-queues and manual queue advances to prevent offhand slot processing or locking if a two-handed weapon is equipped.
- **UnequipSet Nil Table Guard**: Guarded the `.old` table iteration inside `UnequipSet` to prevent a Lua error when unequipping a set that has a nil/empty history table (which can happen after database auditing cleans up empty tables).

### Improvements
- **Missing Ornate Gem IDs**: Added six missing TBC PvP Honor gems to the unique-gem tracking list: Bold Ornate Ruby (28362), Runed Ornate Ruby (28118), Inscribed Ornate Topaz (28363), Potent Ornate Topaz (28123), Smooth Ornate Dawnstone (28119), and Gleaming Ornate Dawnstone (28120). These gems are now correctly detected when ordering set swaps, ensuring items socketed with them are unequipped first to avoid unique-gem conflicts.

## [4.39.2] - 2026-04-20
### Bug Fixes
- **OmniCC Compatibility**: Fixed an issue where the native cooldown overlay provided by OmniCC would fail to display on ItemRack buttons. The addon now dynamically routes its CC-guard bypasses through the engine's metatable so that OmniCC can securely receive `OnSetCooldown` events.
- **Trinket Cooldown Desync**: Enhanced the precision of the CC-guard cache evaluation (using a 0.1s epsilon) to prevent a brief jarring flash-to-ready state when an item ends its cooldown.
- **Popout Menu Alt+Click Hiding**: Fixed a regression where using Alt+Click on items within a popout menu would try to toggle the Quick Access Queue instead of letting you hide the item (e.g. mining picks or fishing poles).
- **Arena Cooldown Reset**: Quick Access and popup-menu cooldown displays now clear their cached item cooldown state when entering a fresh arena, with a delayed second pass on arena entry to match Blizzard's full item-reset timing for fresh matches.
- **Stale Combat Queue Context**: Auto-queued combat swaps now remember which set/queue context created them and are discarded if that context changes before combat ends. This fixes cases where leaving combat after mount or event transitions could still apply a trinket or queued item chosen for an older set context.
- **Parachute Burn-on-Use**: Burn-on-use queue items are now marked from the actual item-use event, fixing short post-buff cooldown cases like parachute cloaks where the item became "ready enough" before the queue ever rotated it out.
- **Detailed Burn State Matching**: Burn-on-use queue state is now tracked by the exact queued item fields instead of just the base item ID, so duplicate same-base items no longer burn each other and per-item swap-in timing resolves against the precise equipped variant.
- **Per-Set Queue Save Completeness**: Saving a set now preserves all queue metadata, including Burn on Use and Custom Swap In settings. Previously, re-saving a set could silently drop those newer per-item queue options and cause later queue behavior to drift from what the user configured.
- **Event Event History Corruption**: `EquipSet` is now guarded from cannibalizing valid historical data (`set.old`) into itself during successive mounts/event triggers while already equipped.
- **Event Restoration Stack Splicing**: Corrected a severe regression in `UnequipSet` where historical ghost pointers on previously equipped sets would trick the unequip engine into thinking the currently active set was buried in the stack, aborting the gear restoration entirely. Top-of-stack manual set evaluations now rightfully take absolute precedence over event stack tracking.
- **Queued Item Set Detection**: `IsSetEquipped` now treats the currently active queued item as valid for the owning set and evaluates queue intent in the correct set context, fixing minimap/current-set display drift and reducing false event desyncs when queues swap items.

### Improvements
- **Diagnostic Debugging Framework**: Introduced a fully native, copyable diagnostic UI that captures server API locks and ItemRack physics swapping engine states `(/itemrack dump)`. Users can export 500-line activity logs alongside active `SavedVariables` arrays instantly.
- **Script Event Stack Helpers**: Script events now support `EquipEventSet("setname")` and `UnequipEventSet()` so custom scripted swaps participate in the same event stack, nested restore, and manual-override logic as built-in events.
- **Script Event Backward Compatibility**: Existing simple script events that use bare `EquipSet(...)` and `UnequipSet(...)` inside the script editor continue to work without user edits. These names are now shimmed onto the new stack-aware helper path at runtime.
- **Swimming Script Migration**: The default Swimming script now uses the stack-aware helper API, and legacy saved copies are migrated automatically on load.

### Documentation
- **Script Event Migration Guide**: Added documentation for updating older script events from `EquipSet("setname")` / `UnequipSet("setname")` to `EquipEventSet("setname")` / `UnequipEventSet()`. Existing simple scripts do not need to be changed immediately, but the helper names are now the recommended pattern going forward.

## [4.39.1] - 2026-04-14
### Bug Fixes
- **Robust Loss-of-Control Cooldown Guard**: Quick Access buttons now preserve real item cooldown swirls when Blizzard reports false `start=0` / `dur=0` states or clears the cooldown frame during stuns and other loss-of-control effects. Popup menu cooldowns now use the same cached-cooldown guard.
- **Cooldown Debug Spam**: `IR-Cooldown` now logs only when a slot's cooldown state actually changes, preventing heavy chat spam from repeated cooldown refresh events.

### Improvements
- **Arena Quick Access Hiding**: Added a `Hide in arenas` option for the docked Quick Access buttons. When enabled, the on-screen quick access bar and its menu automatically hide inside arena instances and restore when you leave.

## [4.39] - 2026-04-13
### 🐛 Bug Fixes
- **Hostile Event Fallback (Fixed FC Gear Bug)**: Fixed a major bug where manually equipping an event set (e.g., your FC gear) when its event condition wasn't active (e.g., you didn't have the flag buff yet) would cause ItemRack to instantly unequip the gear and revert to your previous setup. The fallback logic that caused this has been fixed to strictly respect your manual gear selections (by verifying the `CurrentSet` context) while preserving its ability to clean up genuinely desynced gear states (like dropping a mount state while reloading the UI).
- **Cooldown Visibility (Partial)**: Improved Quick Access button and popup menu cooldown swirls during some stun and loss-of-control states by forcing `enable=1` when the API still reported an active cooldown duration. The stronger cached CC-guard for false `0/0` returns was added in `4.39.1`.
- **Manual Gear Override Protection**: Fixed a persisting issue where manual gear swaps could still be incorrectly overwritten when buried/nested events ended out-of-order. The `UnequipSet` logic fundamentally relies on the active `CurrentSet` context and now refuses to execute background gear restorations if you have actively manually overridden the set.
- **OnMovement Unequip Failures in Overridden Zones**: Fixed a bug where OnMovement gear (like Riding Crops or Swim Speed items) would fail to unequip when you stopped moving if you were inside a Zone Event that you had manually overridden (such as wearing PvE gear inside WSG). The zone's override suppression was blindly halting all event restorations, trapping you in movement gear permanently. It has been strictly compatibilized to only suppress buried background events, seamlessly allowing the natural active gear context (like your mount set) to unequip properly.
- **Bank Item Tooltip Crash**: Fixed a bug where hovering over bank items from a popout menu would fail to display the tooltip or cause UI lag. The modern WoW API strictly returns `nil` for bank container cooldowns, which bypassed the zero-cooldown check and forced the tooltip engine into an infinite redraw loop at 60 FPS.
- **Popout Menu Tooltip Anchoring (Large Grid Flicker)**: Fixed the GameTooltip positioning for popout menus, correcting a major visibility bug reported on large multi-column grids (like 3x3 setups). The anchoring logic was dropping its vertical alignment flags, allowing `GameTooltip` to default to the upper-left or upper-right of the menu box. On outer columns, this caused the tooltip's invisible boundary to overlap the mouse cursor, immediately firing an `OnLeave`/`OnEnter` strobe effect that prevented the tooltip from rendering. The anchor state is now properly tracked with an added 5-pixel horizontal safe zone margin to guarantee the tooltip renders cleanly away from the grid boundary.
- **Empty Slot Equipment Bug**: Fixed a bug where configuring a slot as "Empty Slot" (0) in a gear set was silently ignored by the `isSetEquipped` detection logic, and bypassed entirely by the `IterateSwapList` engine. Event-based sets that relied on un-equipping items (like dropping a PVP trinket to an empty slot for a Mount set) will now seamlessly evaluate and remove the item.
- **Pending Swap Wipe Race**: Added strict `isPendingOrSwapping` logic to `UnequipSet`. Previously, if a set was still actively transacting in the WoW API queues when a user dismounted or stopped moving, the strict mismatch checks aggressively destroyed your old gear memory before restoring. The queue now actively recognizes if the gear is still caught in a `SetSwapping` or `SetsWaiting` delay, gracefully restoring the memory context instead of destructing it.
- **Server Lag Double-Pop Prevention**: Fixed a highly specific but severely destructive race condition caused by server latency. When rapidly transitioning states (like stopping while mounted), the addon could poll the WoW API before the 1-pass gear reversion swapped items. The engine previously interpreted this server lag as a "stuck" gear state and would spam a secondary phantom `PopEvent` that violently wiped the set's restoration data. The queue validation logic now tightly bounds against `AnythingLocked()` and `SetsWaiting` to completely silence any phantom events until the API resolves the swap.

## [4.38] - 2026-04-08
### 🐛 Bug Fixes
- **Options Load Crash**: Added a nil guard to the `CheckButtonLabels` loop in the Options window to prevent "attempt to index" errors if expected UI buttons are missing from the XML context.
- **Zone Event Overriding Manual Swaps**: Fixed a critical bug where zone-based events (like Warsong Gulch auto-equip) would aggressively force the zone set back onto the player within seconds of manually changing gear. The event system now detects when a user has manually overridden the zone set and respects that choice for the remainder of the zone stay. The override clears automatically when leaving the zone, restoring pre-zone gear as expected.
- **Stale SavedVariable Cleanup on Init**: Added comprehensive cleanup on every login/reload that wipes all transient runtime state from SavedVariables:
  - **EventStack**: Purged on init — events with `Unequip=false` never popped, causing the stack to accumulate across sessions with stale restoration data.
  - **old/oldset on ALL sets**: Wiped on init — these fields only have meaning during a single session. Stale chains (e.g., `Cloud.oldset = "Arena"`, `9% → 6% 1H → 6% 2H → 9%`) caused ghost set restores and infinite loops.
  - **Runtime event flags**: `.Active`, `.LastZoneMatched`, `.ManualOverride` cleared from the account-wide `ItemRackEvents` SavedVariable to prevent stale zone-exit logic firing on login.
- **Disabled Events Primed on Init**: Fixed the event priming logic iterating over ALL events (including disabled ones), which could mark disabled events as Active. Priming now only processes enabled events.

## [4.37] - 2026-04-06
### ✨ New Features
- **Burn on Use**: Added a per-item "Burn on Use" check-box for the queue editor. When enabled, using an item (and putting it on cooldown) flags it as "burnt." The auto-queue system gracefully skips burnt items on subsequent rotations until you naturally re-equip the set or manually jog the queue, allowing true single-use queue logic.
- **Custom Swap-In Cooldowns**: Added a custom "Swap In" parameter. You can now define exactly how many seconds remaining on an item's cooldown it should be forcibly swapped back into the equipped slot (overwriting the default global 30-second overlap timer). 

### 🐛 Bug Fixes
- **UI Editing Context Desync**: Fixed a UI issue where the Queue Editing tab failed to bind strictly to the "Equip in options" checkbox configuration, inadvertently forcing the context to only the global equipped state.
- **Queue Cooldown Crashing**: Fixed a critical `bad argument #1` `GetItemCooldown` Lua failure during queue processing where it erroneously tried to validate ItemRack's pseudo-string format instead of reducing it back to the pure numeric integer ID required by the C engine.
- **Visual Alignments**: Polished the Options window layout to correctly anchor the new custom Queue Editor settings.

## [4.36] - 2026-04-02
### 🐛 Bug Fixes
- **Pause Queue Bypassed on Movement**: Fixed a critical bug where marking a trinket as "Pause Queue" (`keep=true`) would only hold while standing still — as soon as you started walking, the auto-queue would swap it away to the next item. The root cause was `AutoQueueItemToEquip()` never checking the `keep` or `delay` flags on the currently-equipped item. While `ProcessAutoQueue` had its own guards, `AutoQueueItemToEquip` was also called from `IsSetEquipped()` in the event system (triggered by `PLAYER_STARTED_MOVING`), which would falsely report the set as "not equipped" and trigger a re-equip that overrode the paused trinket.
- **Set Stuck on "Custom" After Queue Advance**: Fixed a related issue where manually advancing the queue (which temporarily puts you in "Custom" state) would prevent re-equipping your set from the ItemRack menu — the set would stay on "Custom" even though all items were equipped. This was caused by the same `IsSetEquipped` false-negative from the missing `keep` check in `AutoQueueItemToEquip`.
- **Delay Flag Bypassed by Event System**: Fixed the per-item `delay` setting (which prevents swapping an item until X seconds after use) being ignored when evaluated through the event system's `IsSetEquipped` path, matching the same structural fix as the `keep` flag.
- **Short Cooldown Auto-Queue**: Fixed the auto-swap logic for items with short cooldowns (like the Parachute Cloak) by improving cooldown and delay evaluation.
- **Redundant Zone Events**: Prevented redundant zone-based event triggers in cities and PvP zones by implementing a state-aware zone transition check.
- **Queue Initialization Popup**: Suppressed an unintended behavior where Alt+LeftClicking an empty/uninitialized queue slot's quick-access button would abruptly pop open the ItemRack Options menu across the center of your screen. The addon will now silently auto-populate and toggle the new queue in the background, keeping your screen clear (you can still manually open the Queue menu for a slot using Alt+RightClick).

### ✨ Improvements
- **Per-Slot Queue Inheritance for Event Sets**: When an event set (like a mount set) only defines a few slots, equipping it no longer wipes the auto-queue state of every other slot. `GetQueues()` and `GetQueuesEnabled()` now use per-slot inheritance: the active set's data takes priority, missing slots inherit from the previous set in the event stack, and the global queue is the final fallback. This means your bottom trinket's auto-queue keeps running normally when the mount event only swaps the top trinket.

### 🔧 Queue System Audit
- **Manual Queue Discarded in Combat**: Fixed a critical bug where manual queue advances (right-click cycle) for any slot were silently discarded when leaving combat if auto-queue was disabled for that slot. The combat queue filter was too aggressive — it now correctly distinguishes between manual advances (which should always be honored) and auto-queued entries (which should be filtered when auto-queue is disabled). This was the root cause of the reported slot 14 (lower trinket) manual queue not working.
- **Missing `UpdateQueueEnable` Function**: Defined the `ItemRackOpt.UpdateQueueEnable()` function which was called from two locations (Alt-click queue toggle in the Quick Access Menu and Quick Access Button) but never implemented. Previously, Alt-clicking to toggle auto-queue while the Queue Options panel was open for that slot would throw a Lua error instead of updating the checkbox state.
- **`IsSetEquipped` Queue-Awareness Dead Code**: Fixed the auto-queue awareness check in `IsSetEquipped` which was rendered inactive by using `#set.Queues` on a sparse table (always returns 0 in Lua). The check now correctly queries the specific slot's queue list via `GetQueues(setname)[i]` and only activates when auto-queue is enabled for that slot via `GetQueuesEnabled()`. This reactivates the intended behavior: zone/buff events won't see a set as "already equipped" when the auto-queue has a pending swap.
- **`RunAfterCombat` Cleanup Skipping Entries**: Fixed a classic Lua iteration bug where calling `table.remove(t, i)` during a forward `for` loop would shift indices and skip every other entry. If multiple deferred functions (like `ConstructLayout` and `ReflectMainScale`) were queued during combat, some would never be cleared and would re-run on every subsequent combat exit. Replaced with `wipe()`.
- **`SetQueue` Crash When Options Not Loaded**: Added a nil guard for `ItemRackOptFrame:IsVisible()` in the `SetQueue` function. Since `ItemRackOptions` is a LoadOnDemand addon, calling `SetQueue()` from a user's custom event script before the Options panel had ever been opened would crash with a nil index error.
- **`SaveSet` Per-Set Queue Context Desync**: Fixed `SaveSet` calling `GetQueuesEnabled()` and `GetQueues()` without passing the set name, causing them to resolve against `CurrentSet` instead of the set being saved. If an event (zone/buff/spec change) updated `CurrentSet` while the Options panel was open, clicking Save would snapshot the wrong set's queue configuration, silently overwriting the user's in-place queue edits with data from an unrelated set.

## [4.35] - 2026-03-28
### ✨ Improvements
- **Per-Set Queue Snapshotting**: When `Enable per-set queues` is active, clicking "Save" on a Set now deeply copies all active AutoQueue metadata (including enabled slot states, item priority orders, explicit delay timers, and pause markers). Previously, saving a new set omitted this metadata, forcing users to manually rebuild their queues for each set.
- **On Movement Debounce Toggle**: Added a "Stop Delay" check button to the Events option panel for the "On Movement" unequip hook. Users can now bypass the 0.5s debounce timer, initiating instantaneous gear swaps (e.g., unequipping your Riding Crop) the exact millisecond you press your movement key.
- **Queue Context Display**: The Queue Options tab now explicitly displays the name and icon of the exact Set whose auto-queue you are actively editing, preventing confusion about which Set's queue is being modified.

### 🐛 Bug Fixes
- **Queue Editor Race Condition**: Fixed a critical isolation bug where editing auto-queues while the Options menu was open could silently corrupt unrelated sets. If an event (like Mounting or entering Combat) caused a gear swap in the background, subsequent edits (moving items, changing delays, toggling auto-queue) would instantly bind to the *newly equipped* set instead of the one you originally selected. The Queue editor now securely snapshots and locks context to the specific set being edited regardless of background gear changes.
- **Queue Menu Empty Table Pollution**: Fixed an issue where simply opening the Queue UI would rapidly spam the `SavedVariables` table with empty `Queues` objects across every single gear set you owned, bloating file sizes and triggering accidental per-set override defaults. 
- **Bank Item Tooltips**: Sanitized the internal `IRStringToItemString` generator to safely truncate custom trailing attributes. This prevents the WoW client's `GameTooltip:SetHyperlink()` function from crashing and rendering an empty UI when inspecting saved item sets located inside your Bank while the bank frame is closed.
- **Main Bank Empty Tooltips**: Fixed a core engine bug where inspecting items residing natively in the 28-slot main Bank (`bag == -1`) returned stripped or broken tooltips (making other addons like VendorPrice append to an empty record). ItemRack now bypasses the failing `GameTooltip:SetBagItem` on this specific container, natively translating the slot into a player inventory ID using `BankButtonIDToInvSlotID` directly matching the Blizzard UI implementation.

## [4.34] - 2026-03-23
### ✨ Improvements
- **Per-Set Queue Persistence**: Auto-queue settings are now contextually saved and loaded per-set. Creating or updating a gear set will actively capture your current queue state (including toggles and lists) for each slot. Switching between sets will seamlessly restore your configured queue layouts!

### 🐛 Bug Fixes
- **Event Set Swapping Broken**: Fixed a fatal Lua error in `IsSetEquipped` arising from PR #10 (Auto-Queue awareness). The queue loop was incorrectly iterating over non-numeric set properties (like the `Queues` table itself), causing the WoW API (`GetInventoryItemLink`) to crash when it received a string instead of a slot number. This silent crash was halting execution of all event scripts (Mount, Zone, etc) and breaking manual set swaps.
- **Auto-Queue Freezing Swaps**: Fixed an issue where Auto-Queue would infinitely spam `EquipItemByID` if it tried to queue an item ID that the WoW API's `IsEquippedItem` function couldn't parse properly from a string. This spam locked the trinket slot permanently, causing all Event-based set swaps to abort into the `SetsWaiting` queue forever. The queue verify now uses `ItemRack.SameExactID` instead of WoW API.
- **Character Sheet Tooltips**: Fixed violent visual jumping and menu overlap caused by third-party addons resetting `GameTooltip` anchors during asynchronous data renders (such as fetching server info or modifying lines). ItemRack now securely hooks the native `GameTooltip:Show()` execution, actively clamping its own safe-zone offsets securely over the C-engine's defaults before the graphical layout updates, guaranteeing no frame-1 rendering flickers.
- **Auto-Queue Pause/Delay Ignored**: Fixed an issue where the "Pause Queue", "Priority", and "Delay" settings were ignored during auto queueing. The auto queue system was checking the saved string IDs against the equipped base item ID using strict equality, which failed if the queued item string contained enchants or gems. It now uses a reliable two-pass lookup: first trying to match the exact item ID (to support identical base items with different enchants/gems having separate queue settings), and then falling back to matching the base item ID if needed.

## [4.33] - 2026-03-20
### Bug Fixes
- **Weapons Stuck on Cursor in Combat**: `MoveItem` now verifies cursor state after each swap attempt. If the game blocks `PickupInventoryItem` (e.g. during combat lockdown), the item is immediately returned via `ClearCursor()` instead of being left stuck on the cursor. Prevents the "Swap stopped. Something is on the cursor." spam.
- **Failed Swaps Losing Items**: `IterateSwapList` no longer removes items from the swap list when `MoveItem` fails. Failed items now stay in the swap list and properly fall through to the CombatQueue fallback instead of being silently dropped.
- **Stale Pending Swap Indicator**: Fixed the pending swap overlay icon persisting after gear had already been swapped:
  - `AddToCombatQueue` now checks `SameID` against the currently equipped item, preventing items that are already equipped from being queued.
  - `UpdateCombatQueue` sweeps stale entries (where queued item matches equipped) before rendering overlays.
  - `ProcessCombatQueue` now always refreshes overlay indicators at the end, even when the queue was already processed by a different path.
  - `OnUnitInventoryChanged` sweeps the CombatQueue after every gear change, clearing entries where the queued item matches what's actually equipped.
- **Combat API Race Condition**: `EquipSet` and `EquipItemByID` used `UnitAffectingCombat()` to decide whether to queue swaps, but `ProcessCombatQueue` used `InCombatLockdown()` to decide when to process them. Both now consistently use `InCombatLockdown()`.
- **Partial Swap Cursor Cleanup**: `IterateSwapList` now calls `ClearCursor()` after the swap loop if an item is stuck on the cursor from a partial swap. Additionally, if swaps fail during combat, remaining items are moved to CombatQueue instead of entering the `SetSwapping` wait state.

### Improvements
- **CombatQueue Debug Tag**: Added `CombatQueue` to the debug tag system for diagnosing swap queue issues. Enable with `/script ItemRack.DebugTags.CombatQueue = true`.

## [4.32] - 2026-03-16
### Bug Fixes
- **Tooltip Ultrawide Overlap**: Fixed a bug where tooltips would overlap popout menus on ultrawide monitors or at low UI scales. Tooltips for popout menu items now anchor to the entire menu frame (instead of individual buttons) and intelligently deploy to the left or right side based on physical screen space availability rather than naive center-screen heuristics.
- **Custom Script Compatibility**: Fixed an issue where custom "Script" type events would fail because `arg1`, `arg2`, etc., were not explicitly defined in the script's scope. All custom scripts now have local access to `event` and `arg1` through `arg10`.
- **Legacy Event Argument Resolution**: Added a compatibility layer for `UNIT_SPELLCAST_*` and `COMBAT_LOG_EVENT_UNFILTERED` events. Modern WoW passes a cast GUID in `arg2` and requires `CombatLogGetCurrentEventInfo()` for combat data; ItemRack now automatically resolves these back to the legacy formats (`Name(Rank)` for spells and flat arguments for combat logs) so that older user-defined scripts continue to function without modification.
- **Persistence of Default Events**: Deleting a default event (e.g. "After Cast") now restores its original definition in an unbound state rather than removing it entirely from the list.
- **Popout Tooltip Awareness**: Improved tooltip placement for character sheet popout menus. Tooltips now account for UI scaling and effectively align vertically with the specific item being moused over, resolving issues where tooltips would appear with large gaps or on the wrong side of the screen on ultrawide monitors.
- **Improved Combat Weapon Swaps**: Reduced delays and added cast-tracking to ensure weapon swaps trigger reliably during rapid spellcasting. Fixed an issue where weapon swaps queued during combat or casting would fail to trigger for players spamming spells. Added `castID` tracking to prevent race conditions during rapid casting and enabled immediate weapon processing on cast completion. Weapons (slots 16, 17, 18) now bypass standard combat restrictions and are held persistently across multiple casts until a GCD or casting window opens.
- **OnMovement Rapid Toggle**: Fixed an issue where rapidly starting and stopping while mounted with an "On Movement" event active could cause gear swaps to get stuck. Added a 0.5-second debounce for OnMovement unequips — if the player starts moving again within that window, the pending unequip is cancelled, preventing gear from flip-flopping.
- **Bank Item Tooltips**: Fixed a typo in `FindInBank` where a missing `not` caused the item lock check to fail when searching the bank, and updated `IDTooltip` to use `SetBagItem` instead of `SetHyperlink` for bank items. Tooltips for banked items now reliably show full item information and set memberships instead of displaying "unknown" values.
- **Delayed Gear Swaps After Combat/Casting**: Fixed an issue where event-based gear swaps (e.g. "On Movement" riding sets) would stay "pending" after combat or casting ended, requiring the player to jog the queue by moving or triggering another event. `OnLeavingCombatOrDeath` and `OnCastingStop` now immediately re-evaluate active event sets and run a 0.1s delayed timer to process any queued swaps once restrictions are fully lifted.
- **Mounted Zone Transitions (PR #13)**: Fixed an issue where crossing into a new zone while mounted would incorrectly strip your mount gear set and swap to the zone gear, even though you were still on a mount. Zone events now check for an active mount set first, and if the mount set's underlying zone gear already matches the target, the mount gear stays on until you dismount. Includes a frame-based `_refreshMountState` buffer to prevent gear flickering during the transition, and properly handles PvP/PvE instance-type exclusions for mounted events. (Thanks to [UDrew](https://github.com/UDrew) for [PR #13](https://github.com/Bl4ut0/ItemRack-Anniversary/pull/13)!)

## [4.31] - 2026-03-13
### Bug Fixes
- **Internal Bag Error on Rapid Set Swaps**: Hardened the set swap pipeline against the WoW client "Internal bag error" that could occur when swapping sets rapidly (2–3 quick swaps). Added a `CursorHasItem()` guard to `AnythingLocked()`, a lock re-check after multi-step swap passes, frame-deferred `SetsWaiting` processing, and a 5-second safety timeout (`StartSetSwapTimeout()`) that force-clears a stuck `SetSwapping` state — preventing the permanent "need to logout" lockup.
- **OnMovement Zone-Crossing Stutter**: Fixed an issue where crossing a zone boundary (e.g. running out of a town) while mounted with an "On Movement" event active would briefly unequip and re-equip the movement gear set. Zone transitions can cause momentary speed blips or aura flickers that the event system misinterpreted as "player stopped." Added zone-transition awareness: `ProcessBuffEvent` now suppresses OnMovement unequips for 1 second after a `ZONE_CHANGED_NEW_AREA` event, as long as the underlying buff (e.g. mount) is still active. Intentional stops and dismounts still trigger an immediate unequip with zero delay.
- **Auto-Queue Pause Ignored**: Fixed a critical bug where pausing a trinket slot's auto-queue (via Alt+Click) while in combat would fail to cancel pending gear swaps. The system now correctly respects the paused state for auto-queued swaps when combat ends, while still permitting manual and Event-driven set swaps to process through the combat queue cleanly.
- **Zone Event Re-triggering (Issue #5)**: Fixed an issue where moving between two subzones/zones that are *both* part of the same active Zone Event (e.g., from Elwynn Forest to Stormwind City) wouldn't re-equip your event gear if you had temporarily changed it. The addon now consistently re-asserts the zone gear upon every valid zone transition.

## [4.30] - 2026-03-11
### 🏗️ New: Adaptive Event Stack (Multi-Level State Recovery)
- **Event Stack Architecture**: Replaced the old `set.old` single-variable restore system with a fully ordered `ItemRackUser.EventStack`. The addon now remembers a hierarchy of overlapping events (e.g. walking into a City → entering an Arena → entering Combat). When an event ends, it seamlessly restores the gear from the *previous* active event layer instead of blindly reverting to whatever was worn before. This fixes the long-standing issue where overlapping events (Mount + Zone + Combat) would trample each other's gear on unequip.
- **`PushEvent` / `PopEvent` System**: All four event handlers (Stance, Zone, Specialization, Buff) now use a centralized stack-based equip/unequip flow. `PushEvent(eventName)` adds an event to the stack and equips its set; `PopEvent(eventName)` removes it and restores the previous layer's gear.
- **`~BaseGear` Internal Set**: A new internal set is automatically initialized on load as the fallback base layer, ensuring there is always a safe gear state to restore to.
- **Combat-Safe Stack Restoration**: Fixed a major bug where events ending while in combat (e.g. dropping Mount form) failed to restore the previous gear set and permanently lost track of the active set label. The stack now correctly routes through the combat queue system.

### New: Auto-Queue Aware Set Detection (PR #10)
- **`IsSetEquipped` Auto-Queue Awareness**: `IsSetEquipped` now checks whether the auto-queue system would swap to a *different* item in any slot before confirming a set is "equipped". This fixes a scenario where two sets using the **same items** but with **different auto-queue configurations** in the same slot were indistinguishable. (Thanks to [UDrew](https://github.com/UDrew) for [PR #10](https://github.com/Bl4ut0/ItemRack-Anniversary/pull/10)!)
- **`AutoQueueItemToEquip` Extraction**: Refactored `ProcessAutoQueue` to extract a reusable `AutoQueueItemToEquip(slot, baseID, enable, ready)` function. This function returns the item the auto-queue *would* equip next, allowing other systems (like `IsSetEquipped`) to query queue intent without triggering actual swaps.

### Bug Fixes
- **Event Stack Restoration**: Fixed events popping out-of-order failing to splice hidden gear correctly. The stack now handles arbitrary removal (not just top-of-stack pops).
- **Quick Access Queue Toggle**: Re-implemented the queue toggle logic for the Quick Access Menu. Holding Alt and Left-Clicking an item in the menu now correctly toggles the auto-queue for that specific slot on/off, and prevents native action bar dragging issues.
- **Right-Click Queue Advance**: Fixed the Right-Click manual queue cycle. Right-clicking a Quick Access button now correctly advances to the next item in the auto-queue without throwing silent table-to-string coercion errors.
- **Right-Click Item Use**: Fixed the "Use on Right Click" setting. In modern WoW, ItemRack failed to assign the required `type2` attribute to the SecureActionButtons. Checking this setting now natively tells the engine to trigger item usage on right-click, taking effect immediately.
- **Menu Cooldown Refresh**: Added safety safeguards to `ItemRack.WriteCooldown` to prevent Lua arithmetic crashes when attempting to draw cooldown rings on empty or invalid quick access menu slots.
- **Settings Menu**: Moved the "Disable Alt+Click" option from "Interface & Misc" to "Global Settings" to increase visibility and prevent user confusion regarding the Quick Access Menu alt-click features.

## [4.29.9] - 2026-03-09
### Bug Fixes
- **Keybind Persistence & UI Overrides**: Reverted the core set keybinding logic to use `SetBindingClick` instead of `SetOverrideBindingClick`. This fixes an issue where standard WoW keybindings were fighting ItemRack and being improperly deleted during overlap resolution, while also ensuring that users' saved keybinds correctly restore on login. Both the native game UI and ItemRack Options can now freely edit, delete, and persist set hotkeys synchronously.

## [4.29.8] - 2026-03-08
### New Features
- **Per-Queue Queue Settings (PR #7)**: Integrated community pull request #7 which migrates Queue settings (Priority, Keep, Delay) from a global per-item list into the actual Queue data structure. This means you can now have an item set to "Keep" in one queue/slot, but not in another, allowing much greater flexibility!

### Bug Fixes
- **Queue Variable Typo**: Fixed a variable naming bug introduced in the PR #7 migration (`equippedBaseID` used instead of `baseID`) which prevented the Priority, Keep, and Delay functions from reading correctly in the auto-queue.
- **Zone Event Re-equipping (Issue #5)**: Fixed a bug where transitioning between two subzones/zones that are *both* part of the same Zone Event (e.g. from Elwynn Forest to Stormwind City) wouldn't re-equip your event gear if you had temporarily changed gear. The addon will now correctly attempt to re-equip your zone gear on every valid zone transition.

## [4.29.7] - 2026-03-07
### Bug Fixes
- **Keybind Conflicts Not Resolved**: Fixed set and slot keybinds failing to override existing bindings. When confirming a keybind conflict, the old binding was never cleared from the Blizzard binding system, and the non-priority override was always shadowed. Now properly calls `SetBinding(key, nil)` + `SaveBindings()` before setting the override.
- **Keybind Variable Bug**: Fixed `BindSet()` and `BindSlot()` referencing an undefined `buttonName` variable instead of `ItemRackOpt.Binding.buttonName`, which could cause keybind assignment silently fails.
- **Startup Keybind Conflicts**: Fixed saved set keybinds not working after login/reload if the key was also claimed by a standard Blizzard binding. `SetSetBindings()` now clears conflicting standard bindings before applying overrides.

## [4.29.6] - 2026-03-06
### UI Cleanup
- **Removed Per-Event "Disable swap sounds" Checkboxes**: Removed the redundant "Disable swap sounds" checkbox from the Buff, Stance, Zone, and Specialization event editor panels. Per-event sound muting is already accessible from the Sound Settings submenu in Options.

### Bug Fixes
- **Tooltip Circular Anchor Crash**: Fixed `SetPoint would result in anchor family connection` errors that occurred when hovering over item slots in the Options panel or when other addons (e.g. Questie) owned GameTooltip. The `ShrinkTooltip` function was re-anchoring the tooltip to an owner it was already attached to. Now uses `GameTooltip:SetText()` to clear content without re-anchoring.
- **Character Sheet Tooltip Scoping**: Fixed `Tiny Tooltips on Quick Access Only` incorrectly applying tiny tooltips to character sheet popout menus. The detection used `GetID() < 20` which matched popup menu item IDs. Now uses frame names (`ItemRackMenu` vs `ItemRackButton`) and `menuDockedTo` to properly distinguish quick access menus from character sheet menus.

### New Features
- **Quick Access Sub Menus Only**: New checkbox nested under "Tiny Tooltips on Quick Access Only". When enabled, only the popup sub-menu items (the list of trinkets/items you can swap to) get tiny tooltips — the main docked slot button retains its full-size tooltip.
- **Disable Tooltips in Combat**: New checkbox in Tooltip Settings that suppresses item tooltips on ItemRack menus and buttons while you are in combat. UI tooltips (options panel, etc.) are unaffected.

## [4.29.5] - 2026-03-04
### Bug Fixes
- **Tooltip Frame Error (`GetName` on bad self)**: Fixed an error that could occur when mousing over certain restricted or spoofed game UI frames (like the new `SecureTransferDialog`), which caused the addon's popout menus (`ItemRack.MenuMouseover`) to crash when calling frame methods. Safely wrapped `GetName` and `IsVisible` lookups with `pcall`.
- **Gear Swap Stalls**: Fixed a major bug where swapping Specializations back and forth would permanently lock the `SetsWaiting` queue, requiring players to cast a spell or enter combat to jog the queue. The queue now correctly processes back-to-back swaps when the inventory lock clears.
- **Jumping / Momentum Stalls**: Fixed an issue where jumping or falling while relying on an "On Movement" event would abruptly trigger a "stopped moving" event and un-equip gear while you were still in the air. ItemRack now uses a `MovementPollingTimer` to correctly wait until your speed reaches 0 before triggering off-movement swaps.

### Improvements
- **Tooltips System Overhaul**:
  - **Global Toggle**: Added a `Show tooltips` option to completely disable ItemRack's custom tooltips.
  - **Selective Tiny Tooltips**: Added `Tiny Tooltips on Quick Access Only`. When enabled, the main Set button retains its large informative tooltip, but individual gear slot buttons use tiny tooltips, reducing screen clutter.
  - **Comparison Overlap Fix**: Fixed an issue where holding Shift to view a popout menu would trigger multiple overlapping "item comparison tooltips" from the default WoW UI. These are now explicitly suppressed.
- **Audio System Enhancements**:
  - **Test Environment**: Added a "Test" options panel when `LibSoundIndex` is active, allowing users to manually toggle/test specific audio categories like `BAGS` and `ALL_EQUIP`.
  - **Get Addon Integration**: If `LibSoundIndex` is missing, the Audio Framework pane now displays a "Get Addon" button with a direct copyable CurseForge link.
  - **One-Time Warning**: ItemRack now throws a one-time popup warning if you try to enable "Disable swap sounds" without the required library.
  - **CVar Fallback Tuning**: Increased the fallback CVar audio mute length from 0.5s to 1.5s to completely capture the longer Foley sounds during large swaps.
- **Shift-Click Equip via Bank**: Holding Shift while clicking an item in an ItemRack popout menu while the bank window is open will now successfully equip the item, overriding the default transfer-to-bank behavior.
- **Menu Settings Mutual Exclusivity**: The `Menu on Shift` and `Menu on right click` settings are now mutually exclusive, automatically toggling the other off to prevent control conflicts.
- **Disable Swap Sounds**: Added a robust audio toggling system:
  1. **Global Setting**: A new "Disable swap sounds" checkbox in the main options menu will silence all automated and manual gear swaps.
  2. **Per-Event Toggles**: Enabled events are dynamically listed in the Sound Settings submenu, allowing you to mute specific automated events individually without affecting manual clicks.
  3. **LibSoundIndex Integration**: The addon now natively supports `LibSoundIndex-1.0` to perform "surgical muting". When installed, only the sound of the equipment swapping and UI bag drops are muted. If not installed, ItemRack falls back to briefly muting the game's Master SFX CVar during swaps.

## [4.29.4] - 2026-03-01
### Improvements
- **"On Movement" Event Toggle**: Added a new checkbox to the Event Edit panel for "Buff" events (like Mounting). When "On Movement" is checked together with "Any mount" or a specific buff constraint, the event will *only* keep your gear swapped while you are actively moving. This prevents your mount speed gear from staying on when you stop to gather a node or attack a mob. (Suggested by [xeropresence](https://github.com/Bl4ut0/ItemRack-Anniversary/issues/4))

### Bug Fixes
- **"Custom" Set Indicator**: Fixed a bug where the UI would refuse to update the set name to "Custom" when manually changing a piece of gear, getting "stuck" on the previous set's name. This occurred because Active Events (such as Mounting or Drinking) were forcefully suppressing the gear mismatch logic. Events will now properly unhook their gear UI lock if they detect you've actively swapped out any of the underlying event items.
- **Helm & Cloak Unequip**: Fixed an issue where the Show/Hide Helm and Cloak settings were being forgotten when unequipping a set to restore the previous gear. The fallback set (`~Unequip`) now correctly inherits the visibility settings of the previous set. (Thanks to [UDrew](https://github.com/UDrew/ItemRack-Anniversary/pull/3) for the fix!)

---

## [4.29.3] - 2026-02-28
### Bug Fixes
- **Macro Text Overlay on Buttons**: Fixed an issue where macro/action name text from Blizzard's action bar could appear overlaid on ItemRack quick access buttons. Since ItemRack buttons inherit `ActionBarButtonTemplate`, the template's `Name` FontString would display macro names from matching action bar slot IDs (e.g., a macro in slot 1 showing its name on the Head slot button). The `Name` FontString is now cleared, hidden, and permanently blocked from future writes on slots 0-19. Slot 20 (Set Button) is unaffected and continues to display the gear set name.

### Changed
- Added support for tracking instance types in Zone events (`ItemRackEvents.lua`). You can now just enter `arena`, `pvp`, `party`, or `raid` in the Zone event textbook and it properly works across all localized clients. (Thanks to [UDrew](https://github.com/UDrew/ItemRack-Anniversary/commit/a226d36ad1b1903c29e8fb357b41033320af415e) for the fork and foundation!)

---

## [4.29.2] - 2026-02-25
### Bug Fixes
- **Bottom Row Popout**: Reverted the popout rule for bottom-row character sheet items (Main Hand, Off Hand, Ranged, Ammo) that was unintentionally changed. They now correctly dock vertically by default as they used to.
- **Bottom Row Tooltip Overlap**: Fixed an issue where the new tooltip overlap-protection logic would drop tooltips directly onto vertical Weapon/Ammo menus. Tooltips now intelligently push to the left or right side of the menu based on screen position.
- **Orange Highlight Unequipped**: Fixed the logic for the `TooltipColorUnEquipped` setting. It now successfully detects simple un-enchanted item IDs across characters and correctly highlights items that are in your bags (but not in the active set) in orange on the Set Tooltip.

---

## [4.29.1] - 2026-02-25
### Bug Fixes
- **Specialization Re-equip Flicker**: Fixed an issue where zoning or reloading would cause ItemRack to aggressively re-equip spec-tied gear sets, overwriting manual gear changes (like equipping a shield).
  1. **Spec Priming**: ItemRack now primes its state on startup, recognizing the current specialization, stance, and zone to prevent redundant "new" swaps.
  2. **Zoning Guard**: Added protection against invalid spec indices (0) that occasionally flicker during loading screens.
  3. **State Tracking**: Converted Specialization and Zone events to use `.Active` flag tracking. This ensures that once a set is equipped for a spec/zone, ItemRack won't "fight" manual gear overrides until the player actually changes state.

### Improvements
- **Optimized Popout Menus**: Redesigned the popout menu (`BuildMenu`) logic to handle high item counts (like multiple necklaces/rings).
  - **Dynamic Wrapping**: Menus now automatically wrap into multiple columns when item counts are high (4/8/12/24 items), keeping the menu compact.
  - **Always to the Side**: Handled the "Always go to either side" rule for character sheet popouts on the left and right sides of the window. Weapon and Ammo slots deliberately remain untouched and continue to dock vertically.
  - **Screen Space Awareness**: Menus now calculate their height against the screen resolution, automatically adjusting column counts to ensure the entire menu remains visible and accessible.
- **Enhanced Tooltip Anchoring**: Improved `ApplyTooltipAnchor` to protect all ItemRack toolbar buttons. Tooltips now intelligently anchor away from screen edges and Blizzard's default UI elements to prevent overlap.

---

## [4.29] - 2026-02-25
### Bug Fixes
- **Action Bar Taint (ADDON_ACTION_BLOCKED)**: Fixed a critical taint propagation issue that caused Blizzard action bar buttons (e.g. `MultiBar5Button1:SetShown()`) to break after opening the character sheet. Two root causes were addressed:
  1. **GameTooltip taint**: Temporarily replacing `GameTooltip.SetOwner` with an addon closure permanently flagged the table key as tainted, propagating through `OnEnter` → `UpdateShownButtons` → `SetShown`. Tooltip repositioning now occurs *after* the secure handler, using `ClearAllPoints`/`SetPoint` with alpha-hide to prevent visual snap.
  2. **Action bar dispatcher taint**: ItemRack buttons inheriting `ActionBarButtonTemplate` were registered with Blizzard's shared event dispatcher tables. Addon code touching these buttons propagated taint to all real action buttons. `ButtonOnLoad` now unregisters from `ActionBarButtonEventsFrame`, `ActionBarActionEventsFrame`, and related dispatchers.
- **Button Nil Errors**: Fixed `attempt to index field '?' (a nil value)` scaling errors that occasionally occurred on clients carrying over older profile data (e.g. Season of Discovery / Classic Era) when mousing over buttons or dragging them.

### Changed
- Improved macro functionality: `ItemRack.CreateMacro()` now uses a more flexible regex `string.find(text, "#showtooltip")` to detect proper macro prefixes and preserves spacing before tooltips, fixing issues with `#showtooltip` breaking.

### Improvements
- **Tooltip Highlight Unequipped**: Added a new setting "Highlight unequipped in tooltip" to the Options pane. When viewing a set's minimap or on-screen tooltip, items that are taking up inventory space but are not currently equipped are drawn in **Orange**, making it easy to see what items aren't on your character.
- **Improved Tooltip Placement**: Tooltips for popout menus on character-sheet slots now dynamically anchor to ensure they don't cover the buttons or the screen edges. Tooltips for right-side slots (Hands, Belt, etc) now fall down below the ItemRack menu to keep the buttons usable.

---

## [4.28] - 2026-02-14
### Bug Fixes
- **Tooltip Set Info ("Show set info in tooltips")**: Fixed an issue where hovering over items in your bags or character panel would inconsistently show or miss the "ItemRack Set:" label. The root cause was a strict full-string comparison that broke when the TBC Anniversary launch added extra fields to item strings. Replaced with a new `SameExactID` comparison that matches the first 8 item-identifying fields (itemID, enchant, gems, suffix, unique) while ignoring trailing context fields (level, spec). This correctly differentiates items with different enchants or gems, and is immune to item string format changes. Internal sets (`~Unequip`, `~CombatQueue`) are now also filtered from tooltips.

### Improvements
- **Blizzard Keybinding Integration**: All 20 equipment slots (0–19) are now registered in the Blizzard Keybindings panel under **AddOns > ItemRack**. Each slot has a descriptive label (e.g., "Head (Slot 1)", "Off Hand / Shield / Held In Off-hand (Slot 17)"). Added `Bindings.xml` for keybinding registration.
- **Improved Cooldown Display (Large Numbers)**: When "Large Numbers" is enabled in settings, cooldown text now uses a compact `mm:ss` / `h:mm` format with dynamic coloring: **white** (>60s), **yellow** (<60s), and **red** (<5s). Small numbers mode retains the original `30 s` / `2 m` / `1 h` format.
- **Native Countdown Suppression**: Suppressed WoW's built-in `CooldownFrame` countdown numbers on ItemRack buttons. The game's settings only allow disabling this for spells (not items), so ItemRack now explicitly calls `SetHideCountdownNumbers(true)` to prevent duplicate countdown text when using its own cooldown system.
- **Hotkey Display**: Improved keybinding text rendering on slot buttons — keys now display in a subtle gray (`0.6, 0.6, 0.6`) and are properly hidden when no key is bound. Added nil-safety checks for the hotkey font string.

## [4.27.5] - 2026-02-09
### Bug Fixes
- **Action Bar Interaction**: Fixed an issue where casting spells from the main action bar (slots 1-12) would inadvertently highlight/check corresponding ItemRack slots. This was caused by the underlying button template responding to action bar events; these event handlers have now been explicitly disabled for ItemRack buttons, including hiding the CheckedTexture and SpellActivationAlert elements.
- **Mounted-to-Casting Transitions**: Fixed an issue where gear set swaps would get stuck when transitioning from mounted to casting. The `SetsWaiting` queue was not being processed after casting ended, causing pending set changes to never execute. Re-enabled processing of waiting sets after both spell completion and the delayed combat queue.
- **Keybind Saving in Combat**: Improved combat handling for keybind saving. If a reload happens during combat, the keybind save operation is now queued to run automatically after combat ends, instead of failing silently.
- **Ammo Slot Nil Check**: Fixed a "bad argument #1" Lua error that occurred when `GetInventoryItemID` returned nil for empty slots (particularly the ammo slot). The error would trigger during buff event processing (e.g., mounting, drinking) when the addon scanned inventory slots. Added proper nil check before calling `GetItemInfo`.
- **Combat Queue UI Timing**: Fixed an issue where the set icon would briefly show "Custom" after combat ends, even though the correct set was equipped. This was caused by `UpdateCurrentSet()` being called immediately after combat queue items were equipped, before the item swap animation completed. Added a 0.5s delay to match the timing used for normal set swaps.

---

## [4.27.4] - 2026-02-03
### Event System Overhaul
- **Buff Event State Tracking**: Fixed an issue where temporary events (Mounting, Drinking) could get "stuck" or spam gear swaps. Added distinct `.Active` state tracking to ensure events properly unequip their gear when ending.
- **Nested Event Handling**: Implemented "stack splicing" logic to handle complex event transitions (e.g., Drinking ending while Mounted). The system now correctly restores the original gear state instead of reverting to an intermediate temporary set.
- **Stance Reliability**: Extended the `.Active` state tracking to Stance events (Shapesifting, Ghost Wolf), ensuring they cleanly revert gear even if the equipment API reports mismatches.
- **UI Label Stability**: The current set label/icon now correctly persists during active events (like "Zoomies") instead of reverting to "Custom" when `IsSetEquipped` fails falsely due to API inconsistencies.

## [4.27.3] - 2026-02-02
### Dual-Wield Timing Fix
- **Extended Retry Delay**: Increased the dual-wield weapon retry delay from 0.75 seconds to 5.5 seconds. The previous delay was too short to account for the 5-second spec change cast, causing the offhand weapon retry to trigger before dual-wield capability was granted.

### UI Options
- **Menu Docking Control**: Added two new options under "Character sheet menus" for controlling popout menu direction:
  - **Left slots: menu on right** — Flips left-side slots (Head, Neck, Shoulder, Back, Chest, Shirt, Tabard, Wrist) to show menus on the RIGHT
  - **Right slots: menu on left** — Flips right-side slots (Hands, Waist, Legs, Feet, Rings, Trinkets) to show menus on the LEFT
  - Bottom weapon slots (MainHand, OffHand, Ranged) always dock vertically and are unaffected

---

## [4.27.2] - 2026-02-01
### Dual-Wield Spec Awareness
- **Offhand Weapon Retry**: Added logic to detect when a spec change grants dual-wield capability (e.g., Enhancement Shaman, Fury Warrior). If the offhand weapon fails to equip during the initial set swap, ItemRack will automatically retry the weapon slots after a short delay.
- **Safe Implementation**: Uses `EquipItemByID` directly instead of temporary sets, avoiding queue conflicts that could break the addon.

### Stability Fixes
- **SetsWaiting Safety**: Added protection against deleted sets in the waiting queue. If a set in the queue no longer exists, it is now safely skipped instead of breaking subsequent swaps.
- **Simplified Combat Detection**: Streamlined the combat state check in `EquipSet` to avoid potential timing issues.

### Combat Queue Consistency
- **Manual Queue Cycling**: Right-clicking a slot button to cycle through the queue now properly uses the combat queue if you're in combat. Previously, this action would silently fail during combat.
- **Unified Combat Handling**: All gear-switching systems now consistently use `AddToCombatQueue()` when the player is in combat, dead, or casting. Items queued this way will automatically equip when combat ends.
- **Event Restoration During Combat**: Suppressed noisy "Could not find" error messages when events like Drinking end during combat. These messages were not actionable while fighting and cluttered the chat.

---

## [4.27.1] - 
### Queue System Fixes
- **Queue Duplicates**: Fixed an issue where items would duplicate in the queue list due to minor string ID mismatching. Now uses robust base-ID matching.
- **Stop Marker Fix**: Resolved a bug that caused multiple "Stop Queue Here" (red circle) markers to appear in the list.
- **Auto-Cleanup**: Opening the queue menu now automatically detects and removes any existing duplicates or extra markers from saved data.

### UI & Layout Improvements
- **Smart Menu Docking**: Character sheet flyout menus for left-side slots (Head, Neck, Back, Chest, Shirt, Tabard, Wrist, Shoulder) now spawn to the **left** instead of the right, preventing overlap with tooltips or the character model.
- **Minimap Tooltip Anchor**: Repositioned the minimap button tooltip to the bottom-left of the button to ensure it doesn't obstruct the dropdown menu interactions.
- **Documentation**: Added a complete [CONTROLS.md](CONTROLS.md) reference guide accessible from the README.

## [4.27] - Dual Spec Support
### Core Refinements & Spec Switching
- **Specialization Automation Fix**: Implemented a 0.5s stability timer (`SpecChangeTimer`) for talent switches to prevent gear-swap race conditions.
- **Improved Event Handling**: Added `LastLastSpec` state tracking to prevent spec-based gear swaps from interfering with temporary events like **Drinking**, **Mounting**, or **Stance** changes.
- **Unequip Priority**: Optimized the unequip-then-equip flow during spec transitions to avoid slot conflicts.
- **Redundancy Filter**: Prevents unnecessary equip calls if the target set is already active, cleaning up chat/logs.

### Keybind Improvements
- **Right-Click Queue Cycling**: Fixed and improved manual queue cycling. Right-clicking a slot button now correctly swaps to the next item in that slot's queue using a simplified bag-search approach that bypasses ID matching issues.
- **Alt+Right-Click Queue Options**: Alt+Right-clicking a slot button now opens the Queue configuration panel for that slot.
- **Left-Click Item Use**: Left-clicking a slot button uses the equipped item (trinkets, on-use effects).
- **Alt+Left-Click Queue Toggle**: Alt+Left-clicking toggles the Auto-Queue system on/off for that slot.

### UI & Options Stability
- **Focus Preservation**: Fixed a bug where saving a set or equipping gear would cause the Options window to jump to the currently equipped set. The UI now maintains the user's current editing context.
- **Spec Checkbox Persistence**: Introduced `SpecDirty` tracking to ensure Primary/Secondary spec associations are saved reliably and loaded correctly in the Sets list. Spec checkboxes are now dynamically labeled with your talent tree name (e.g., "Holy", "Arms").
- **UI Spacing**: Adjusted dual-spec checkbox layout with a 4px overlap to ensure all functional buttons fit within the interface frame.

### Visual & Display Fixes
- **Item Count Logic**: Refined the display of item counts on buttons and flyout menus.
    - Stacks and charges are now always visible.
    - Standard gear (count: 1) correctly hides the count text.
    - **Ammo Slot**: Fixed a specific issue where the Ranged/Ammo slot would display a "0" when empty.
- **Flyout Menus**: Enabled item counts for all slots in popout menus to improve visibility for consumables and charged items.

---

## [4.26] - Previous Port Release
### TBC Anniversary Compatibility
- **API Namespace Migrations**: Migrated all critical APIs to modern namespaces (`C_Container`, `C_Item`, `C_AddOns`).
- **Secure Action Handling**: Switched to `ActionBarButtonTemplate` to resolve click-blocking issues in the modern engine.
- **Icon Layer Strategy**: Implemented `$parentItemRackIcon` to bypass modern Mixin icon-clearing logic.
- **Yellow Triangle Fix**: Programmatic texture cleanup for the Options menu buttons to remove legacy artifact overlays.
- **AuraUtil Shim**: Added compatibility for modern aura searching.
