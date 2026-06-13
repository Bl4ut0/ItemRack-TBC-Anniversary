# ItemRack TBC Anniversary - Release v4.39.8

This release introduces options panel sizing accessibility options for visually impaired players, splits the menu wrapping functionality into two independent settings (preventing layout conflicts between vertical quick-access dropdowns and horizontal character-slot hover menus), and resolves a layout bug where floating-point values from the slider API caused wrapping to fail.

---

### 🚀 Features & Accessibility
* **Accessibility Sizing Checkboxes**: Replaced the options scale slider with three discrete checkboxes (**Default size**, **Bigger**, and **Biggest**) to easily change options panel scale (1.0, 1.3, and 1.6 scale respectively). Includes backward-compatible settings migration on login.
* **Separated Wrap Settings**: Split wrapping settings into **Quick menu wrap** and **Char sheet wrap** to support horizontal and vertical menu orientations independently.

### 🐛 Bug Fixes
* **Menu Wrap Layout Bug**: Cast wrap thresholds with `math.floor` and updated comparisons to `>=` to fix the WoW slider float precision bug that stretched menus into single lines and broke the background frame.
