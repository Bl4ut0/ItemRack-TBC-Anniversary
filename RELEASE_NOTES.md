# ItemRack TBC Anniversary - Release v4.41

This release includes major stability improvements, real-time event spin-down/spin-up capabilities, in-combat weapon swapping, live set restoration cycle prevention, forced dismount recovery, and ghost button visibility fixes.

---

### 🚀 Features & Improvements
* **Event Enable/Disable Spin-Down & Spin-Up**: Unchecking or deleting an event in the Events Options menu (or toggling events globally) now immediately unwinds/spins down the event if it is currently active, popping it off the event stack and restoring base gear. Checking an event immediately evaluates whether the event condition currently applies and spins it up.
* **In-Combat Weapon Swapping**: Weapon slot swaps (Mainhand, Offhand, Ranged) now execute immediately during combat when not spellcasting, while non-weapon armor slots continue to defer safely to `CombatQueue`. If a weapon swap is requested while spellcasting, it executes immediately as soon as the cast finishes (`OnCastingStop`).

### 🐛 Bug Fixes
* **Live Set Restoration Cycle Prevention**: Implemented real-time cycle detection (`PreventLiveOldsetCycle`) to automatically detect and splice circular set loops (`SetA -> SetB -> SetA`) during live set swaps, preventing UI locks and infinite restoration loops without breaking gear restoration chains.
* **Forced-Dismount Event Stack Recovery**: Fixed summon, portal, and instance transitions that forcibly dismount the player while a mount set is active. Mounted events now unwind before destination Zone sets apply, preventing inactive mount entries and corrupted restoration chains.
* **Ghost Buttons Visibility Fix**: Fixed a bug where quick-access buttons that had been toggled off (removed) would reappear as empty grey squares on login or reload. Securely wrapped the button's `Show()` method to prevent external addons or Blizzard's Action Bar system from showing inactive buttons.
* **Tooltip Set Info Containment Fix**: Fixed a bug where appended set lines fell outside the bottom boundary of the tooltip window. Restored `tooltip:Show()` inside `ListSetsHavingItem` after set lines are added so `GameTooltip` recalculates its height and contains set names within the backdrop.

