# ItemRack Anniversary - Release v4.43-beta3

This release packages the latest development updates:

---

## Changes in this Release
### Bug Fixes & Improvements
- **Occupied Slot Swap Displaced-Item Return (CurseForge: Thoare)**: Fixed a critical bug in `MoveItem` where swapping items into non-empty equipment or bag slots failed to return the displaced item to its source location. This caused swaps into occupied slots to falsely fail with `AbortSwap=4`, orphan reserved bag slots in `LockList`, set `CurrentSet` to `"CUSTOM"`, reset the minimap button to the default gear icon, and freeze set swaps in `SetsWaiting`.
- **Orphaned `LockList` Reservation Cleanup**: `IterateSwapList` now invokes `ClearLockList()` whenever a swap aborts early, preventing failed or interrupted swaps from locking bag slots in ItemRack's search cache.
- **Dynamic Druid Stance Matching**: Enhanced `GetStanceNumber` to resolve Druid stance names (*Bear Form*, *Dire Bear Form*, *Cat Form*, *Aquatic Form*, *Travel Form*, *Moonkin Form*, *Tree of Life*) dynamically against `GetShapeshiftFormInfo`, preventing stance bar index shifts on lower-level Druids (e.g. missing Aquatic Form) from breaking stance event evaluation.
- **SoD Bank-Flyout Rune Icons**: Refreshes engraving data after the bank opens and redraws character-sheet flyout rune markers above Masque and ItemRack's bank-only border, keeping banked rune gear visibly identifiable.
- **SoD Main-Bank Rune Lookup**: Fixed a character-sheet hover error caused by passing WoW's negative main-bank container ID to `C_Engraving.IsInventorySlotEngravable`. Main-bank slots are now translated through `BankButtonIDToInvSlotID` and queried with the equipment-slot engraving API, preserving rune identification instead of dropping it; unsupported negative containers are ignored safely.
- **Rune-Specific Gear Matching**: Saved sets, AutoQueue entries, manual queue choices, combat-queue completion, bank and bag searches, and burn-on-use state now preserve the `:runeid:` identity. When two copies of an item carry different runes, ItemRack selects the saved rune and does not silently fall back to the wrong copy. Existing Era/TBC data and older SoD entries without rune metadata retain the historical base-item fallback.
- **SoD Rune Icon Toggle**: Added a SoD-only **Show SoD rune icons** option that mirrors Blizzard's native `alwaysShowRuneIcons` setting. Rune markers now identify engraved items in ItemRack flyout menus, quick-access buttons, the set editor, and AutoQueue rows; learned-rune icons are cached so saved bank entries remain identifiable when the bank is closed.
- **Rune-Aware AutoQueue Editing**: Opening or rebuilding an AutoQueue no longer removes identical item copies carrying different runes. Rune-aware entries are de-duplicated by their exact item fields and rune, while legacy queue entries retain base-item compatibility.
