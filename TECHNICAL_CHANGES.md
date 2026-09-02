# Technical Changes for TBC Anniversary Edition

This document details all modifications made to port ItemRack Classic to the TBC Anniversary Edition (2.5.4/2.5.5).

## Overview

The TBC Anniversary Edition runs on a modern WoW client engine (similar to Retail), which means many APIs have been moved to new namespaces or deprecated. This port adds compatibility shims and fixes to ensure ItemRack functions correctly.

## Tooltip Post-Hook Taint Containment
**File:** `ItemRack/ItemRack.lua` — `ItemRack.ListSetsHavingItem`

### Problem
`ListSetsHavingItem` runs from insecure post-hooks on Blizzard tooltip methods. Calling `tooltip:Show()` from those hooks can propagate taint into protected action-button update paths and produce `ADDON_ACTION_BLOCKED` errors after an otherwise harmless item hover.

### Correct boundary
The hook may append ItemRack's set-name lines with `AddDoubleLine`, but Blizzard retains ownership of the tooltip's `Show` lifecycle. Avoiding direct assignments to `GameTooltip.SetOwner` fixes a separate taint source; it does **not** make an insecure `Show()` call safe. Earlier versions of this document incorrectly combined those two issues.

### Solution
`ListSetsHavingItem` now only appends and clears its lines. It never calls `Show()` or replaces a secure tooltip method. Character-sheet positioning is applied after Blizzard's handler completes. Backdrop sizing should be verified in-game on each supported client; any future sizing adjustment must preserve this protected-method boundary.

---

## Auto-Queue Stuck Slots Fix
**File:** [ItemRack.lua](file:///c:/Dev%20Projects/ItemRack/ItemRack/ItemRack.lua) — `ItemRack.LocksChanged`

### Problem
When equipping an item set containing multiple items that are already on cooldown with Auto-Queue enabled for those slots, only the first slot would get auto-swapped. The subsequent slots would get stuck and never swap.

### Root Cause
During the set swap or subsequent periodic queue check, the first slot swap locks that slot.
When processing the next auto-queued slot, `EquipItemByID` checks `AnythingLocked()`. Since the first slot is locked, `EquipItemByID` defers the second slot's swap by adding it to `ItemRack.CombatQueue`.
When the first slot's swap finishes, `ITEM_LOCK_CHANGED` triggers `LocksChanged()`. However, `LocksChanged()` originally had no checks to process the `CombatQueue` when OOC. The combat queue would remain unprocessed indefinitely outside of combat, keeping the slots stuck.

### Solution
Modified `LocksChanged()` to process `CombatQueue` and `SetsWaiting` sequentially inside the `else` block:
- If there are items in `CombatQueue`, no items are locked, player is not casting, and player is not in combat, we trigger `ProcessCombatQueue()`.
- If `ProcessCombatQueue()` initiates a swap, `AnythingLocked()` becomes true, preventing `ProcessSetsWaiting()` from executing in the same frame.
- If `ProcessCombatQueue()` does not swap anything (or is empty), `AnythingLocked()` remains false and we proceed to evaluate and process `SetsWaiting` immediately.

---

## GameTooltip Taint Fix (ADDON_ACTION_BLOCKED)
**File:** `ItemRack.lua` — `PaperDollItemSlotButton_OnEnter` override

### Problem
After hovering over a character sheet equipment slot (while an ItemRack popout menu was visible), Blizzard action bar buttons would start throwing `ADDON_ACTION_BLOCKED` errors on `MultiBar5Button1:SetShown()`. The error persisted until `/reload`.

The call chain in the error was:
```
OnEnter → UpdateAction → UpdateShownButtons → SetShown (BLOCKED)
```

### Root Cause
To prevent tooltip overlap with ItemRack's popout menus, the `PaperDollItemSlotButton_OnEnter` override temporarily **replaced** `GameTooltip.SetOwner` with an addon closure:

```lua
-- BEFORE (taint-causing)
oldSetOwner = GameTooltip.SetOwner
GameTooltip.SetOwner = function(tooltip, owner, _anchor, ...)
    oldSetOwner(tooltip, ownerHook, anchorHook, ...)
end
-- ... call original handler ...
GameTooltip.SetOwner = oldSetOwner  -- restore
```

Even though the original function was restored immediately, **WoW's taint system permanently flags the table key** once addon code writes to it. The `GameTooltip` table was now considered tainted. Later, when Blizzard's action bar `OnEnter` handler called `GameTooltip:SetOwner()`, it read from the tainted table, propagating taint through the entire execution chain until `SetShown()` (a protected function) was blocked.

### Solution — Tooltip Repositioning
Instead of intercepting `GameTooltip.SetOwner`, we now:
1. **Hide** the tooltip with `SetAlpha(0)` before calling the original handler (prevents a visible "snap")
2. Call the original Blizzard handler **completely untouched** (secure, no taint)
3. **After** it finishes, reposition using `ClearAllPoints()`/`SetPoint()` — these are method calls, not table key assignments, so they don't cause taint
4. **Reveal** the tooltip at the correct position with `SetAlpha(1)`
5. Store the desired anchor in `ItemRack.pendingTooltipAnchor` so it can be **re-applied** after asynchronous native tooltip refreshes that restore Blizzard's default anchor
6. If the repositioned tooltip is **too wide** and overlaps the menu, fall back to below the menu frame

```lua
-- Hide during setup to prevent visible snap
GameTooltip:SetAlpha(0)
ItemRack.oldPaperDollItemSlotButton_OnEnter(self)  -- secure, untouched

-- Reposition and reveal
ItemRack.ApplyTooltipAnchor()  -- ClearAllPoints + SetPoint to desired position
GameTooltip:SetAlpha(1)
```

### Key Takeaways
1. **Never directly assign to secure table keys** (e.g. `GameTooltip.SetOwner = ...`), even temporarily. WoW's taint tracking flags the key permanently.
2. Use `hooksecurefunc()` for pre/post hooks, or reposition frames after the secure handler completes.

---

## Recent Feature Refinements (Spec Switching & UI Persistence)

### Specialization & Gear Synchronization
**File:** `ItemRackEvents.lua`, `ItemRackEquip.lua`
In the TBC engine, talent switching often fires events before the client is ready to swap gear, leading to race conditions.
- **Stability Timer:** Implemented a `0.5s` stability timer (`SpecChangeTimer`) to allow the client state to settle after a spec switch before triggering gear automation.
- **State Tracking:** Added `ItemRack.LastLastSpec` to track the active talent group index. This prevents "spec change" gear sets from fighting with temporary event sets (like "Drinking" or "Mounted") by ensuring a swap only triggers when the talent group actually transitions.
- **Redundancy Filter:** Added checks to avoid redundant `EquipSet` calls if the correct gear is already worn.

### Options UI Persistence
**File:** `ItemRackOptions.lua`, `ItemRackEquip.lua`
- **Editing Stability:** Added logic to prevent the Options UI from automatically "jumping" back to the currently equipped set while the user is mid-edit. The UI now respects the `ItemRackOptSetsSaveButton` state.
- **Spec Checkbox Management:** Introduced a `SpecDirty` flag to properly manage the state of Primary/Secondary spec checkboxes, ensuring they save correctly without being reset by background UI updates.

### Visual & Layout Polish
**File:** `ItemRackButtons.lua`, `ItemRackOptions.lua`, `ItemRack.lua`
- **Item Count Display:** Fixed logic to correctly show/hide item counts. Stacks and charges are now visible, but "1" counts for gear are hidden. Specifically addressed the **Ranged/Ammo slot** to correctly hide the "0" count when empty.
- **Dual Spec UI Layout:** Optimized the spacing of spec-related checkboxes in the Sets tab (4px overlap) to ensure all elements (Spec 1, Spec 2, Hide) fit within the frame.

---

## Event Stack & Restoration Fixes
**File:** `ItemRackEvents.lua`

### Problem
When the player logged in or reloaded their UI, the state of active events and their stance/gear restoration memory (`.old` and `oldset`) was wiped out. Consequently, if a player was mounted when logging out, dismounting after logging back in would fail to restore their previous gear set.

### Solution
1. **Preservation of Restoration Memory**: We modified `ItemRackEvents.lua` to prevent wiping the `.old` and `oldset` tables during initial event setup.
2. **Re-populating the EventStack**: On initialization, the code now scans for active events and automatically re-populates the character's `ItemRackUser.EventStack`, ensuring the gear restoration chain remains perfectly intact across logins and reloads.

---

## Two-Handed Weapon & Offhand Queue Handlers
**File:** `ItemRackEquip.lua`, `ItemRackQueue.lua`

### Problem
1. **Cursor Lock on 2H swap**: Equipping a two-handed weapon while holding a one-handed weapon and a shield would sometimes cause the offhand item to get stuck on the cursor and lock the UI because the WoW client's item-picking API was triggered concurrently for slot 16 and slot 17.
2. **Infinite Queue Loops**: The auto-queue system would continue trying to process the offhand slot (17) even when a two-handed weapon was active in the main hand slot (16), causing queue stalls.

### Solution
1. **Swap Re-ordering**: Modified `ItemRackEquip.lua` to prioritize equipping the two-handed weapon in slot 16 first. This forces the client to automatically unequip and place the offhand weapon/shield into the bags before any slot 17 operations occur, eliminating cursor conflicts.
2. **Cursor Safety Fallback**: Added a post-equip cursor check. If an item is still stuck on the cursor after a swap, it is safely deposited into the first available container slot.
3. **Offhand Block Guard**: Implemented `ItemRack.IsOffhandBlocked()` check inside the queue processor to suspend offhand auto-queues and block manual queue advances for slot 17 when a 2H weapon is held.

---

## SavedVariables Auditor & Setting Sync
**File:** `ItemRack.lua`

### Problem
Over time, database schemas can become corrupt or filled with obsolete keys. Specifically:
- Sets could form circular restoration paths (`A -> B -> A`), causing infinite gear-swapping loops.
- Obsolete settings from old addon versions (e.g. `CharacterSheetMenusLeft`) remained in the user's SavedVariables file forever.
- Disabled or missing events would linger in `ItemRackUser.EventStack`.

### Solution
1. **Auto-Repair Auditor**: Created `/itemrack debug audit` which checks for:
   - Self-referential and orphaned `oldset` references.
   - Circular set loops (breaks the loop chain).
   - Duplicate or missing events in the active `EventStack`.
   - Out-of-bounds/invalid slot IDs in `Queues`, `QueuesEnabled`, and `Buttons`.
2. **Auto-Sync Settings**: Clones the default `ItemRackSettings` table at load-time and matches the player's saved settings against it. Any missing settings are automatically restored, and any obsolete keys are pruned.
3. **Diagnostics & Reporting**: Runs silently on startup, printing a one-line warning to the user if any corruption was auto-fixed, and saves the full diagnostic run report to `ItemRackUser.LastAudit`.
4. **Compile Safety**: The auditor and event loop compile custom scripts using `loadstring` within a safe sandbox. Syntax or runtime script errors are captured and logged to the `Events` debug tag rather than throwing Lua errors.

---

## API Namespace Migrations

### C_AddOns Namespace
**File:** `ItemRack.lua`, `ItemRackButtons.lua`

The addon management APIs have moved to the `C_AddOns` namespace.

```lua
-- Shim for LoadAddOn
if not LoadAddOn and C_AddOns and C_AddOns.LoadAddOn then
    LoadAddOn = C_AddOns.LoadAddOn
end

-- Shim for GetAddOnMetadata
if not GetAddOnMetadata and C_AddOns and C_AddOns.GetAddOnMetadata then
    GetAddOnMetadata = C_AddOns.GetAddOnMetadata
end
```

**Functions affected:**
- `LoadAddOn` → `C_AddOns.LoadAddOn`
- `GetAddOnMetadata` → `C_AddOns.GetAddOnMetadata`
- `EnableAddOn` → `C_AddOns.EnableAddOn`
- `DisableAddOn` → `C_AddOns.DisableAddOn`

---

### C_Container Namespace
**File:** `ItemRack.lua`, `ItemRackEquip.lua`, `ItemRackQueue.lua`

Container-related APIs have moved to `C_Container`.

```lua
-- Shim for GetContainerNumSlots
if not GetContainerNumSlots then
    GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots
end

-- Shim for GetContainerItemLink
if not GetContainerItemLink then
    GetContainerItemLink = C_Container and C_Container.GetContainerItemLink
end
```

**Functions affected:**
- `GetContainerNumSlots` → `C_Container.GetContainerNumSlots`
- `GetContainerItemLink` → `C_Container.GetContainerItemLink`
- `GetContainerItemInfo` → `C_Container.GetContainerItemInfo`
- `PickupContainerItem` → `C_Container.PickupContainerItem`
- `UseContainerItem` → `C_Container.UseContainerItem`

---

### C_Item Namespace
**File:** `ItemRack.lua`, `ItemRackButtons.lua`

Item information APIs have moved to `C_Item`.

```lua
-- Shim for GetItemInfo
if not GetItemInfo and C_Item and C_Item.GetItemInfo then
    GetItemInfo = function(itemInfo)
        return C_Item.GetItemInfo(itemInfo)
    end
end

-- Shim for GetItemCount
if not GetItemCount and C_Item and C_Item.GetItemCount then
    GetItemCount = function(itemInfo)
        return C_Item.GetItemCount(itemInfo)
    end
end
```

**Functions affected:**
- `GetItemInfo` → `C_Item.GetItemInfo`
- `GetItemCount` → `C_Item.GetItemCount`
- `GetItemSpell` → `C_Item.GetItemSpell`
- `IsEquippedItem` → `C_Item.IsEquippedItem`

---

### GetItemCooldown Fix
**File:** `ItemRackQueue.lua`

**Important:** The cooldown API is located in `C_Container`, NOT `C_Item`.

```lua
-- GetItemCooldown is in C_Container namespace, not C_Item
if not GetItemCooldown then
    if C_Container and C_Container.GetItemCooldown then
        GetItemCooldown = function(itemID)
            return C_Container.GetItemCooldown(itemID)
        end
    end
end
```

This was a critical fix - the Blizzard deprecation fallback incorrectly maps to `C_Item.GetItemCooldown`, but the actual function is `C_Container.GetItemCooldown`.

---

## Button Template Fix and Icon Layer Strategy
**File:** `ItemRackButtons.xml`, `ItemRackButtons.lua`, `ItemRack.lua`

### Problem
The original template inherited from `ActionButtonTemplate,SecureActionButtonTemplate`. In TBC Anniversary (Retail engine), `ActionButtonTemplate` includes a Mixin (`BaseActionButtonMixin`) that interferes with `SecureActionButtonTemplate`'s click handling when used by an addon, causing "Action Blocked" errors.

Switching to `ActionBarButtonTemplate` fixed the click blocking issue (allowing secure actions) but introduced a new problem: its associated Mixin aggressively manages the button's icon, clearing it because it sees no valid "Action" assigned to the button.

### Solution
We implemented a hybrid approach:
1. **Template:** Use `ActionBarButtonTemplate` to leverage its working secure click handling.
2. **Custom Icon Layer:** Defined a new texture layer `$parentItemRackIcon` in the XML, separate from the standard `$parentIcon` that the Mixin controls (and clears).
3. **Lua Updates:** Updated all ItemRack code to target `ItemRackIcon` instead of `Icon` for visual updates.
4. **Queue Indicator:** Restored the queue indicator as an explicit layer `$parentQueue` to ensure visibility.

This allows the button to function securely as an item button while ItemRack maintains full control over its visual appearance, bypassing the template's internal logic.

```xml
	<CheckButton name="ItemRackButtonsTemplate" inherits="ActionBarButtonTemplate" ...>
		<Layers>
			<!-- Custom layer to avoid Mixin interference -->
			<Layer level="BORDER">
				<Texture name="$parentItemRackIcon"/>
			</Layer>
            ...
		</Layers>
```

---

## AuraUtil Compatibility
**File:** `ItemRack.lua`

Added shim for `AuraUtil.FindAuraByName` which may not exist in all client versions:

```lua
if not AuraUtil or not AuraUtil.FindAuraByName then
    AuraUtil = AuraUtil or {}
    AuraUtil.FindAuraByName = function(auraName, unit, filter)
        -- Manual iteration through unit auras
        for i = 1, 40 do
            local name = UnitAura(unit, i, filter)
            if not name then break end
            if name == auraName then
                return UnitAura(unit, i, filter)
            end
        end
    end
end
```

---

## Files Modified

| File | Changes |
|------|---------|
| `ItemRack/ItemRack.toc` | Version 4.27, Interface 20505, updated author |
| `ItemRack/ItemRack.lua` | C_AddOns, C_Container, C_Item shims, AuraUtil shim, Menu item count logic, Options scale settings/sync/audit, Menu wrap float bugfix |
| `ItemRack/ItemRackButtons.lua` | LoadAddOn shim, Item count/Ammo slot display logic, Reset options scale settings |
| `ItemRack/ItemRackButtons.xml` | ActionBarButtonTemplate inheritance |
| `ItemRack/ItemRackEquip.lua` | C_Container shims, Spec-to-Gear logic, UI persistence checks |
| `ItemRack/ItemRackQueue.lua` | GetItemCooldown shim (C_Container), GetItemSpell/GetItemCount/IsEquippedItem shims |
| `ItemRack/ItemRackEvents.lua` | Spec stability timer, redundancy filters |
| `ItemRackOptions/ItemRackOptions.toc` | Version 4.27, Interface 20505 |
| `ItemRackOptions/ItemRackOptions.lua` | Dual Spec UI spacing, SpecDirty tracking, Save Set consistency, Sizing accessibility checkboxes |

---

## Options Menu Texture Cleanup
**File:** `ItemRackOptions/ItemRackOptions.xml`

### Problem
The buttons in the **ItemRack Options** menu (`ItemRackOptInvTemplate`, used for slot selection) inherited from `ActionButtonTemplate`. In the TBC Anniversary client, this template introduces several anonymous texture overlays (likely using missing Atlases) which render as a large **Yellow Triangle** when the button is interacted with (clicked/selected).

Standard texture overrides were insufficient because the artifacts were rendering as additional "anonymous" textures layered on top of the button.

### Solution
We implemented a robust programmatic cleanup in the `OnLoad` script of `ItemRackOptInvTemplate`:
1.  **Iterate all regions** of the button.
2.  **Identify standard textures** (`NormalTexture`, `PushedTexture`, `HighlightTexture`, `CheckedTexture`, and the named `Icon`).
3.  **Hide everything else** (specifically anonymous textures that do not match the standard set).

Additionally, we overrode the standard interaction textures (`PushedTexture`, `HighlightTexture`, `CheckedTexture`) with valid Classic interface files (e.g., `Interface\Buttons\UI-Quickslot2`) to ensure consistent visuals without reliance on potentially broken template defaults.

```xml
<OnLoad>
    -- ...
    -- Programmatically hide specific anonymous textures (Triangle Hunting)
    for _, region in ipairs({self:GetRegions()}) do
        if region:GetObjectType() == "Texture" then
            -- Logic to identify and preserve standard textures
            -- Hide unknown anonymous textures
        end
    end
</OnLoad>
```

---

## Options Sizing and Menu Wrap Improvements
**Files:** `ItemRack.lua`, `ItemRackButtons.lua`, `ItemRackOptions.lua`, `ItemRackOptions.xml`

### Sizing Accessibility Checkboxes
- Replaced the options scale slider/editbox with three mutual-exclusive checkboxes: **Default size** (1.0), **Bigger** (1.3), and **Biggest** (1.6) for visual accessibility.
- Added backward-compatible profile migration inside `ItemRack.AuditSavedVariables()` to automatically translate any existing slider-based numeric scale values to the closest checkbox state.
- Integrated checkbox states into the `"Reset Buttons"` routine.

### Menu Wrap Float Bugfix
- Fixed a layout bug in `ItemRack.BuildMenu()` where popout menus (such as the sets list menu) failed to wrap when `SetMenuWrap` was enabled. 
- Because WoW's `Slider:GetValue()` API returns floating-point values, `col == max_cols` (e.g. `3 == 3.0000001`) would fail to match, causing the row to extend indefinitely in a single line while leaving the backdrop frame broken.
- Resolved this by casting `ItemRackUser.SetMenuWrapValue` using `math.floor` and changing the comparison check to `col >= max_cols`.

### Separated Quick Menu and Character Menu Wrapping
- Split the menu wrapping functionality into two distinct user settings to avoid layout conflicts:
  - **Quick Menu Wrap** (`SetMenuWrap` / `SetMenuWrapValue`): Applied to quick access buttons and sets popout menus, which extend vertically (wrapping horizontally).
  - **Character Sheet Menu Wrap** (`CharMenuWrap` / `CharMenuWrapValue`): Applied to character pane slot hover menus, which extend horizontally (wrapping vertically).
- Updated the defaults, self-healing/saved variables auditing, button reset functions, and options window widgets to register and control both sets of settings independently.

---

## Options Window Screen Clamping
**Files:** `ItemRackOptions/ItemRackOptions.lua`, `ItemRackOptions/ItemRackOptions.xml`

### Problem
When the Options panel scale is increased using the new accessibility checkboxes (**Bigger** at 130% or **Biggest** at 160%), the frame can easily clip or open completely off-screen, particularly on lower resolutions or if the panel was previously dragged near a screen edge.

### Solution
- Added `clampedToScreen="true"` attributes to both `ItemRackOptFrame` and `ItemRackFloatingEditor` in the XML definitions.
- Added programmatical enforcement via `self:SetClampedToScreen(true)` in `ItemRackOpt.OnLoad()`.
- Updated `ItemRackOpt.ReflectOptScale()` to toggle the clamping state (`SetClampedToScreen(false)` followed by `SetClampedToScreen(true)`) whenever the scale is updated. Toggling the clamp state forces WoW's layout engine to immediately recalculate the frame boundaries and snap it back within the visible screen area.

---

## Manual Swaps Combat Queue Fix
**File:** `ItemRack/ItemRackQueue.lua`

### Problem
When the player is in combat and triggers a manual item or set swap, the swap is queued in `ItemRack.CombatQueue`. However, if the currently equipped item in that slot has no active cooldown (meaning `ready` is true), the periodic auto-queue processor `ItemRack.ProcessAutoQueue()` would immediately identify the equipped item as ready and call `ItemRack.RemoveFromCombatQueue(slot)`. This silently deleted the user's manual swap from the combat queue before combat ended, resulting in ignored swaps.

### Solution
- Updated the queue removal condition in `ItemRack.ProcessAutoQueue()` to verify the swap's origin.
- Guarded the cleanup check with `ItemRack.AutoQueueFlag` and `ItemRack.AutoQueueFlag[slot]`.
- This ensures that only auto-queued swaps (which have `AutoQueueFlag[slot] = true`) are removed from the queue when the equipped item is ready, while manual item/set swaps are safely preserved.

---

## Forced-Dismount & Mounted Zone Transition Recovery
**File:** `ItemRack/ItemRackEvents.lua`, `ItemRack/ItemRack.lua`

### Problem
When teleported via portal, summoned, or entering instances while mounted, the client forcibly dismounts the player before or during the zone load. Previously, destination `Zone` events executed before the mount set was popped, causing the new `Zone` set to record `Mounted` as its `oldset` (previous gear history). This resulted in inactive mount entries trapped on `ItemRackUser.EventStack` and circular `Zone -> Mounted -> Zone` gear restoration loops.

### Solution
1. **Unwinding Invalid Mount Events:** Implemented `reconcileInvalidMountEvents(isMounted, instanceType)` which scans `EventStack` topmost-first and unwinds any invalid/excluded mount layers *before* any destination Zone event is evaluated.
2. **Mounted Zone Re-Basing:** Implemented `prepareMountRebase(eventName)`: When moving between zones while remaining mounted, old mount layers unwind one step first so the destination Zone set records clean base gear history before the mount layer is re-applied.
3. **Zone Placement Under Mount:** Implemented `ensureZoneEventBelowMount(zoneEventName, mountEventName)` to place matching Zone events underneath active mount layers without forcing redundant item swaps.
4. **Transition Deferral Guards:** Added `mountZoneSwapBusy()` checks (combat, casting, death, active locks) and `scheduleMountZoneRecheck(...)` to safely defer transition processing when restrictions exist. `ProcessBuffEvent()` is paused while `ItemRack.MountZoneTransitionDeferred` is set.

---

## Live Set Restoration Cycle Prevention
**File:** `ItemRack/ItemRackEquip.lua`

### Problem
If a user manually or automatically toggles back and forth between two sets during gameplay (e.g. `SetA` -> `SetB` -> `SetA`), `SetA.oldset` was recorded as `SetB` while `SetB.oldset` remained `SetA`. This created a live circular restoration loop (`SetA <-> SetB`) in the database during gameplay, causing `UnequipSet` to bounce infinitely between sets, freeze UI swaps, and require a UI reload or addon restart.

### Solution
Implemented `ItemRack.PreventLiveOldsetCycle(targetSet, proposedOldSet)` in `ItemRackEquip.lua`:
- Executed before `set.oldset = ItemRackUser.CurrentSet` in `EquipSet`.
- Traverses `proposedOldSet`'s `oldset` chain. If `targetSet` is already present anywhere in `proposedOldSet`'s chain, a cycle is detected.
- Splices `targetSet` out of its previous position in the chain by updating `targetSet`'s ancestor to point to `targetSet`'s current `oldset`, and then places `targetSet` cleanly at the top of the linear chain.
- Guarantees that the `oldset` chain remains strictly linear (`Base -> SetB -> SetA`) regardless of how many times the user toggles between sets back and forth.

---

## In-Combat Weapon Swapping
**Files:** `ItemRack/ItemRackEquip.lua`, `ItemRack/ItemRack.lua`

### Problem
While WoW blocks armor slot swaps (slots 0–15, 19) in combat, weapon slot swaps (slots 16 Mainhand, 17 Offhand, 18 Ranged) are permitted by the game engine. Previously, `EquipSet` and `ProcessCombatQueue` deferred all item slots (including weapons) to `CombatQueue` until out of combat (`InCombatLockdown() == false`).

### Solution
- Updated `EquipSet` in `ItemRackEquip.lua`: When in combat, `canSwapWeaponInCombat` checks if a slot is a weapon slot (16, 17, 18). If the player is not spellcasting (`NowCasting`) and not dead, weapon slots bypass the `CombatQueue` deferral and execute **immediately in combat** via `IterateSwapList`. Non-weapon armor slots continue to defer safely to `CombatQueue`.
- Updated `ProcessCombatQueue` in `ItemRack/ItemRack.lua`: Weapon slots (16, 17, 18) in `CombatQueue` evaluate `canSwap = (not inCombat) or (isWeaponSlot and not ItemRack.NowCasting and not ItemRack.IsPlayerReallyDead())`. If a weapon swap was queued while mid-cast, as soon as the spellcast finishes (`OnCastingStop`), `ProcessCombatQueue` executes the weapon swap mid-combat without waiting for combat to end.

---

## Event Enable/Disable Spin-Down & Spin-Up
**Files:** `ItemRack/ItemRackEvents.lua`, `ItemRackOptions/ItemRackOptions.lua`

### Problem
Previously, unchecking (disabling) an event in the Events Options menu or deleting an active event left its set equipped on the player if the event was currently active (`eventData.Active == true` or present on `ItemRackUser.EventStack`). The user had to manually unequip the set or re-log to revert back to their base gear. Conversely, enabling an event did not evaluate whether the event condition was currently true until the next game event (e.g. movement or stance change) fired.

### Solution
1. **Event Spin-Down (`ItemRack.SpinDownEvent`):**
   - Implemented `ItemRack.SpinDownEvent(eventName)` in `ItemRackEvents.lua`.
   - When an event is unchecked, deleted, or disabled in `ItemRackOptions.lua`, `SpinDownEvent` clears `eventData.Active`, `ManualOverride`, and zone signatures.
   - If the event is on `ItemRackUser.EventStack` or currently equipped, it pops the event via `PopEvent(eventName)` or unequips the set, restoring the underlying gear layer.
2. **Event Spin-Up (`ItemRack.SpinUpEvent`):**
   - Implemented `ItemRack.SpinUpEvent(eventName)` in `ItemRackEvents.lua`.
   - When an event is checked (enabled) or assigned a set, `SpinUpEvent` invokes `RunAllEvents`, immediately checking whether the event condition currently applies (e.g. player is mounted, in stance, or in zone) and equipping the set.
3. **Global Toggle Spin-Down (`ItemRack.SpinDownAllEvents`):**
   - Toggling events OFF globally via `ItemRack.ToggleEvents` invokes `SpinDownAllEvents()`, unwinding all active event stack layers and returning the player to their base gear.

---

## Cooldown Proxy Trinkets
**Files:** `ItemRack/ItemRack.lua`, `ItemRack/ItemRackQueue.lua`, `ItemRack/ItemRackButtons.lua`

### Problem
Some trinkets have no cooldown of their own because their effect is driven by a separate item. Serpent-Coil Braid (30720) keys off mana gems. `GetItemCooldown` therefore reports the braid as permanently ready, and AutoQueue would swap it in while its gem was still on cooldown and the trinket was doing nothing.

### Solution
`ItemRack.CooldownProxies` in `ItemRack.lua` maps such an item to the item that gates it:

```lua
ItemRack.CooldownProxies = {
	[30720] = { id = 22044, buff = 37445 }, -- Serpent-Coil Braid <- mana gems (Mana Surge)
}
```

1. **Readiness:** `ItemRack.GetItemCooldownLeft` resolves through the proxy, so `IsCandidateReady` and `ShouldHoldEquippedItem` see the gating item's remaining cooldown. `hold_decision` diagnostics record the gating item's ID when one stands in, so a dump explains a remaining time that belongs to no cooldown on the equipped item.
2. **Buff hold:** the queue's existing "hold while this item's buff runs" check keys on `GetItemSpell`, which cannot see an equip effect, so `buff` names the aura instead. `ItemRack.GetProxyBuff` supplies the name instead, and takes precedence over `GetItemSpell` because a `CooldownProxies` entry is an explicit declaration of what gates the item. Give it as a spell ID so the name resolves in the client's own locale; a literal name is also accepted.
3. **Display:** `ItemRack.ApplyProxyCooldown` substitutes the gating item's cooldown into the slot button and flyout menu swirls and countdown text.
