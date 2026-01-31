# Changelog - ItemRack TBC Anniversary

All notable changes to the TBC Anniversary port of ItemRack will be documented in this file.

## [4.27] - 2026-01-31
### Core Refinements & Spec Switching
- **Specialization Automation Fix**: Implemented a 0.5s stability timer (`SpecChangeTimer`) for talent switches to prevent gear-swap race conditions.
- **Improved Event Handling**: Added `LastLastSpec` state tracking to prevent spec-based gear swaps from interfering with temporary events like **Drinking**, **Mounting**, or **Stance** changes.
- **Unequip Priority**: Optimized the unequip-then-equip flow during spec transitions to avoid slot conflicts.
- **Redundancy Filter**: Prevents unnecessary equip calls if the target set is already active, cleaning up chat/logs.

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
