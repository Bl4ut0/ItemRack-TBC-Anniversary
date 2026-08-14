# ItemRack Beta Regression Checklist

Use the packaged build from `.versions/Release/v{Version}`. Reload the UI after installation and test with Lua errors enabled. Capture `/itemrack dump` output whenever a failure occurs.

## 1. Tooltip safety and layout

- Enable **Show set info in tooltips** and place one item in multiple saved sets.
- Hover that item in equipped slots, bags, the bank, and an ItemRack flyout.
- Confirm every expected set name appears, the tooltip backdrop contains the lines, and character-sheet flyouts do not overlap the tooltip.
- Immediately hover and use several Blizzard action-bar buttons. Record any `ADDON_ACTION_BLOCKED`, `SetShown`, `SetAttribute`, or `GameTooltip` error.

## 2. Rune-specific copies (Season of Discovery)

- Prepare two copies of the same base item with different runes and save each in a different set or queue position.
- Equip each set, swap paired ring/trinket slots, and test a main-hand/off-hand shuffle.
- Confirm ItemRack chooses the saved rune, reports the correct set as equipped, colors tooltip rows correctly, and does not silently accept the other rune.
- Test a bound weapon-only set during combat. If the secure macro cannot distinguish the copy, confirm the mismatch remains queued and resolves after combat instead of disappearing.
- Repeat one saved set created before rune metadata existed; it should retain legacy base-item fallback.

## 3. Event ownership and same-spec re-enable

- Manually equip a set that is also assigned to an event, then disable that inactive event. The manually equipped set must remain equipped.
- Activate an event normally, disable it while active, and confirm its stack layer unwinds once.
- Disable and re-enable the specialization event for the current spec without changing specs. Its assigned set should evaluate immediately.
- Disable and re-enable the global event system while remaining in the same spec. Confirm specialization, stance, zone, and buff state are reconciled without duplicate swaps.

## 4. Lock, summon, and transition recovery

- Trigger a one-item and a multi-item set swap while rapidly mounting/dismounting, accepting a summon, or crossing an instance portal.
- Confirm automatic swaps pause through the transition and resume after settlement without an internal bag error or permanent `SetsWaiting` state.
- While an item remains locked, issue multiple automatic requests and finish with one manual set click. Confirm older automatic work is discarded, the latest manual request receives one bounded retry, and persistent failure produces a clear chat message.
- After a forced timeout, confirm the minimap/set display reconciles to the gear actually worn.

## 5. Right-click precedence

- With **Menu on Right-Click** on, confirm right-click opens the flyout.
- With it off and **Use on Right-Click** on, confirm right-click uses the equipped item.
- With both off, confirm right-click advances to the next valid queue item.
- Confirm slot 20 opens the set list only when **Menu on Right-Click** is enabled; Alt+Right-click must always open the Sets options tab.

## 6. Keybindings

- Bind, overwrite, and unbind both a set and a slot. Test a set name containing `%`.
- Confirm rejected overwrites restore both prior bindings, screenshots and extended mouse buttons remain protected, and deleting a set removes its binding.
- Test a bound weapon set both in and out of combat.

## Report data

Include the client branch/build, addon version, reproduction sequence, expected and actual set names, relevant item links/runes, full Lua error text, and `/itemrack dump` output.
