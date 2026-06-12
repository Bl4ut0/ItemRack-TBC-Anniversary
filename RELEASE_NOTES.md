# ItemRack TBC Anniversary - Release v4.39.6

This hotfix release resolves an inconsistency in tooltip anchoring for right-side character sheet equipment slots, restoring the correct default popout direction to the left and aligning `AnchorTooltip` to prevent positioning conflicts.

---

### 🐛 Bug Fixes
* **Tooltip Anchoring Inconsistency**: Restored the tooltip default popout direction for right-side slots to the left (matching the behavior prior to version 4.39.4). Aligned the `AnchorTooltip` logic to match the slot-enter layout, resolving positioning conflicts and flickering during active cooldown updates.
