# ItemRack TBC Anniversary - Release v4.39.3

This release consolidates significant diagnostic/auditing tools, stability fixes for two-handed weapon swapping, event state recovery across login/reloads, and various event and queue improvements.

---

### 🔍 Diagnostic & Auditor Improvements
* **SavedVariables Auditor & Auto-Repairer**: Added a database scanner (`/itemrack debug audit`) to detect and fix corruptions in gear sets (circular `oldset` paths, orphaned references), event stacks (duplicates, missing event names), and queues.
* **Obsolete Settings Pruning**: The auditor automatically merges missing defaults and prunes obsolete keys in `ItemRackSettings` using a load-time clone of the default settings table.
* **Audit Persistence**: Auto-fixed startup issues are notified via a one-line chat alert, with detailed reports saved to `ItemRackUser.LastAudit` in the WTF database.
* **Enhanced Debug Subcommands**: Extended the `/itemrack debug` command to support `/itemrack debug help`, `/itemrack debug status`, `/itemrack debug clear`, `/itemrack debug audit`, and tag-specific toggles (`events`, `equip`, `queue`, `combatqueue`, `api`, `ui`, `combat`).
* **Dynamic Event Compile Error Safety**: Custom scripted event compilations are now wrapped securely. Compilation and runtime errors no longer crash the main event thread and are logged to the `Events` debug tag.
* **Expanded Combat Taint Tracing**: Upgraded the internal diagnostic framework to troubleshoot "Action Blocked" combat errors.
  * Added `Combat` and `UI` trace layers to track `InCombatLockdown()` state during combat transitions and when opening/clicking ItemRack's dynamic popout menus.
  * Increased internal log buffer from 500 to 5,000 lines.
  * **Silent Tracing**: `/itemrack debug` now activates trace layers silently. Real-time chat output can be toggled via `/itemrack debug chat`.
  * Expanded `/itemrack dump` output to include runtime combat state, active menu visibility, combat queue contents, and current quick-access button configurations.

### 🐛 Bug Fixes
* **Ghost Overrides for Events**: Fixed an edge case in `ItemRackEvents.lua` where transient or disabled Zone events could leave their `ManualOverride` flag stuck on. This "ghost override" previously suppressed gear restorations (like dismounting or dropping a stance) permanently, even when the player was not actively using a zone set (PR #14).
* **Event Stance and Restoration Persistence**: Fixed a bug where stance and gear restoration data (`.old` and `oldset`) was wiped on startup, breaking stance restoration on login or reload. It now re-populates the event restoration stack automatically from active events on load.
* **Two-Handed Weapon Equipping & Cursor Lock**: Placed 2H weapon swapping at the top of the swap order so the client automatically bags the displaced offhand/shield. Added a cursor cleanup safety check to ensure any leftover item on the cursor is deposited into an empty container slot.
* **Offhand Queue Guarding**: Guarded auto-queues and manual queue advances to prevent offhand slot processing or locking if a two-handed weapon is equipped.
* **UnequipSet Nil Table Guard**: Guarded the `.old` table iteration inside `UnequipSet` to prevent a Lua error when unequipping a set that has a nil/empty history table (which can happen after database auditing cleans up empty tables).

### ✨ Improvements
* **Missing Ornate Gem IDs**: Added six missing TBC PvP Honor gems to the unique-gem tracking list:
  * Bold Ornate Ruby (28362)
  * Runed Ornate Ruby (28118)
  * Inscribed Ornate Topaz (28363)
  * Potent Ornate Topaz (28123)
  * Smooth Ornate Dawnstone (28119)
  * Gleaming Ornate Dawnstone (28120)
  These gems are now correctly detected when ordering set swaps, ensuring items socketed with them are unequipped first to avoid unique-gem conflicts.
