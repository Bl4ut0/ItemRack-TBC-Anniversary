# ItemRack TBC Anniversary - Release v4.40

This release introduces official support for the Burning Crusade Classic 2.5.6 PTR, fixes the character sheet left-side popout menus rendering off-screen (Issue #17) - with a fix provided by github user `physixtential`, and includes several key fixes for auto-queue swaps, manual combat queue entries, and GameTooltip taint errors.

---

### 🐛 Bug Fixes & Improvements
* **TBC PTR 2.5.6 Support**: Added interface version `20506` to `ItemRack.toc` to ensure compatibility with the Burning Crusade Classic 2.5.6 PTR client.
* **Left-side Menus Off-screen Fix (Issue #17)**: Fixed character sheet left-side popout menus rendering off-screen by default in the default WoW UI. Defaulted `LeftSlotsGoRight` to `"ON"` and added a one-time profile migration to update existing configurations. (Fix provided by `physixtential`)
* **GameTooltip Taint Fix**: Fixed `ADDON_ACTION_BLOCKED` taint errors on Blizzard action buttons (`SetAttribute`) caused by calling `tooltip:Show()` inside `ListSetsHavingItem` under insecure hooks. Removed the redundant `Show()` call.
* **Auto-Queue Stuck Slots Fix**: Resolved a bug where equipping an item set containing multiple items already on cooldown (with Auto-Queue enabled) only swapped the first slot. Subsequent slots were deferred to the combat queue and got stuck outside of combat. `ItemRack.LocksChanged()` now sequentially processes deferred combat queue swaps and waiting sets.
* **Manual Swaps Combat Queue Fix**: Fixed a bug where manual item swaps or manual set swaps queued during combat were deleted from the combat queue if the currently equipped item in that slot was ready (had no active cooldown). `ProcessAutoQueue` now respects `ItemRack.AutoQueueFlag[slot]` and only removes auto-queued swaps.
