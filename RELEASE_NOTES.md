# ItemRack TBC Anniversary - Release v4.39.7

This hotfix release resolves a bug where right-side character sheet equipment slots (Gloves through Rings) had their tooltips anchor incorrectly to the left, causing them to overlap and obscure popout menus. It replaces coordinate-based layout evaluations with a settings-based logical check to prevent timing and race condition bugs.

---

### 🐛 Bug Fixes
* **Tooltip Anchoring Overlap**: Fixed a bug where right-side character sheet slots (Gloves through Rings) would have their tooltips anchor to the left and overlap the popout menus due to a timing race condition with coordinate-based layout evaluations. Replaced coordinate lookups with a deterministic settings-based evaluation.
