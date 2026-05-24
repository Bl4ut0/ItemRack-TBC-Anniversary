# ItemRack TBC Anniversary - Release v4.39.4

This release addresses a critical settings persistence regression introduced in v4.39.3, along with several diagnostic, logging, and event improvements.

---

### 🐛 Bug Fixes
* **Settings Persistence**: Fixed a major regression where active, dynamically-managed settings (such as the minimap icon position, events database version, show set info in tooltips, and action bar sound suppression settings) were pruned on startup by the SavedVariables auditor, causing them to reset on every logout or reload.

### 🔍 Diagnostic & Logging Improvements
* **Casting & Channeling Debug Traces**: Added detailed debug logging to `OnCastingStart` and `OnCastingStop` to track when swaps are blocked and released by player casting/channeling states.
* **Combat Queue Defer Debugging**: Added debug logging when an `EquipSet` is deferred to the combat queue, indicating the deferral reason (combat, casting, or death) along with the queued slot numbers and item IDs.
* **Expanded Diagnostic Dump**: Updated `/itemrack dump` output to include additional variables (event enabled states, queue configurations, active setting tables, and current casting/channeling blocks) for more comprehensive troubleshooting.
* **Robust Debug Tag Validation**: Restricted toggling to valid debug tags, preventing the system from reporting random names as enabled. Toggling an invalid tag now prints a clean warning and displays all available layers and their status.
* **Enhanced Debug Status Output**: Refactored `/itemrack debug status` to print a complete, color-coded list of all available layers (`Events`, `Equip`, `Queue`, `CombatQueue`, `API`, `UI`, `Combat`) and their exact `ON`/`OFF` states.
* **Diagnostic Dump Reorganization**: Reorganized section output order to match development requests. Added debug states (`DebugAll`, `DebugChat`, and `DebugTags`) and restored the `ItemRackUser.Buttons` layout configuration to the dump. Reorganized options configuration list to match options UI hierarchy.

### ⚙️ Event & Zone Improvements
* **Auto-Dismount Zone Boundaries**: Generalized the mount check in `ProcessZoneEvent` to search the active event stack for any active event with the `Anymount` flag set, allowing custom mount event names like `"pvp mount"` to keep gear equipped correctly when transitioning zones.
* **Syntax Validation**: Resolved code duplication syntax warnings in `ItemRack.lua`. Established an automated Lua validation runner inside scratch spaces.
