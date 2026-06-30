# ItemRack TBC Anniversary - Release v4.40.1

This release fixes a visual bug where quick-access buttons that had been toggled off (removed) would reappear as empty grey squares on login or character reload. 

---

### 🐛 Bug Fixes
* **Ghost Buttons Visibility Fix**: Fixed a bug where quick-access buttons that had been toggled off (removed) would reappear as empty grey squares on login or character reload. Securely wrapped the button's `Show()` method to prevent external addons (like Masque) or Blizzard's internal Action Bar system from showing buttons that are not currently active in the user's layout.
