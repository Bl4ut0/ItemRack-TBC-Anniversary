# ItemRack TBC Anniversary - Release v4.39.5

This release includes major updates to the Event Swapping and Instance Transition frameworks to resolve instances where gear sets failed to load when entering or transitioning between dungeons, raids, and PvP environments, as well as fixing Masque quick slot button skinning and solid white backdrop textures.

---

### ⚙️ Event Swapping & Instance Transitions
* **Centralized Event Recheck Scheduler**: Added `ItemRack.ScheduleEventRecheck` and `ItemRack.RunAllEvents` to safely schedule and run event-based evaluations. Schedules automatic settled checks at `0.5s` and `1.5s` upon entering the world/instances (`PLAYER_ENTERING_WORLD`), and on zone changes (`ZONE_CHANGED_NEW_AREA`).
* **Unified Event Release Triggers**: Refactored combat and casting stop events (`OnLeavingCombatOrDeath` and `OnCastingStop`) to run rechecks on all event categories (stances, spec, zones, buffs) instead of only buffs.
* **Signature-Aware Zone Transitions**: Implemented multi-field zone signatures (incorporating instance type, zone text, subzone text, and unique instance ID) to cleanly differentiate between distinct dungeons of the same type.
* **Improved Manual Override Protection**: Refactored override scoping in `ProcessZoneEvent`. Manual gear swaps are strictly protected within the same zone signature but automatically cleared upon zoning into a different zone/instance signature, allowing zone set auto-equip to resume.
* **Exclusion Unwinding**: Rewrote buff and stance exclusion checks (`NotInPVP`/`NotInPVE`). When an event is active but its exclusion becomes true, the event is immediately unwound/popped from the stack rather than skipped, preventing zombie sets from sticking on the event stack.
* **Deterministic Zone Swaps**: Replaced scalar pending zone actions with alphabetical sorting lists (`eventsToUnequip` and `eventsToEquip`), ensuring all unequips finish before equips are processed in a stable, deterministic order.
* **Mount Set Resolution Fix**: Corrected set lookup in `ProcessZoneEvent` for mount events by resolving the set name through the active event data structure instead of using the raw event name.
* **Defensive Programming Nil-Guards**: Added nil guards around enabled event lookups across all event processors to avoid Lua errors with corrupt profile data.

### 🐛 Bug Fixes
* **Masque Quick Slot Skinning**: Fixed Masque skinning for Quick Access buttons by passing explicit button regions (`Icon`, `Cooldown`, `Count`, `HotKey`) to `AddButton`.
* **White Background Texture Fix**: Fixed a bug where the swap menu frame (`ItemRackMenuFrame`) background was rendered as a solid white texture in recent client patches. Re-anchored `bgFile` to `DialogBox-Background`.
* **Blank Diagnostic Dump Fix**: Fixed a bug where the diagnostic log and state dump window (`/itemrack dump`) appeared entirely blank due to the multiline edit box collapsing to 0 height. Added an `OnTextChanged` height recalculator script.
* **SavedVariables Auditor 'Custom' Set Guard**: Excluded the special `"Custom"` set string from database checks. Previously, running `/itemrack debug audit` or logging in while in a `"Custom"` gear state (such as being mounted with unsaved gear) would flag and clear the valid `"Custom"` history path, breaking dismount gear restoration.
