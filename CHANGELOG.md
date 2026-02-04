# Changelog - ItemRack TBC Anniversary

All notable changes to the TBC Anniversary port of ItemRack will be documented in this file.

## [4.27.4] - 2026-02-03
### 🚀 New in v4.27.4

#### ⚡ Event System Overhaul
- **Buff Event State Tracking**: Fixed an issue where temporary events (Mounting, Drinking) could get "stuck" or spam gear swaps. Added distinct `.Active` state tracking to ensure events properly unequip their gear when ending.
- **Nested Event Handling**: Implemented "stack splicing" logic to handle complex event transitions (e.g., Drinking ending while Mounted). The system now correctly restores the original gear state instead of reverting to an intermediate temporary set.
- **Stance Reliability**: Extended the `.Active` state tracking to Stance events (Shapesifting, Ghost Wolf), ensuring they cleanly revert gear even if the equipment API reports mismatches.

#### 🎨 UI & Visual Fixes
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
