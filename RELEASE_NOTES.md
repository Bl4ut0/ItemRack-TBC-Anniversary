# ItemRack Anniversary - Release v4.43-beta2

This release packages the latest development updates:

---

### Changes in this Release
### Bug Fixes & Improvements
- **Cross-Slot AutoQueue Availability (CurseForge: Bloodasha)**: AutoQueue now considers only candidates physically available in carried bags. Rings or trinkets already equipped in the paired slot are skipped so the next ready bag item can equip, while an additional matching copy in a bag remains eligible.
- **Set Button Count Overlay (CurseForge: smackadack)**: Permanently cleared the inherited `ItemRackButton20Count` action-button region so Blizzard action counts can no longer cover the current set name.
- **Set Button Right-Click Menu (CurseForge: gizmo22)**: Restored Classic Era behavior by making slot 20 honor the **Menu on right click** setting. With it enabled, right-click toggles the gear-set list; Alt+Right-click continues to open the Sets options tab.
- **In-Combat Set Keybindings (PR #20)**: Set an explicit key-up mode on ItemRack's secure set-binding buttons so bound weapon and gear-set swaps are no longer ignored during combat on Classic Era/Season of Discovery 1.15.9 and TBC Anniversary 2.5.6. Fix contributed by Hamdor.
- **Opt-In AutoQueue Diagnostics**: The runtime AutoQueue flight recorder now allocates entries only while Queue diagnostics or the master debug mode is enabled, and releases its buffer when tracing is disabled to avoid unnecessary allocations during normal play.
- **Reliable Per-Tag Debug Toggles**: Initialized every supported debug tag explicitly and added tracking markers when Queue or master diagnostics are enabled, keeping `/itemrack debug <tag>` behavior and support dumps consistent.
