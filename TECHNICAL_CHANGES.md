# Technical Changes for TBC Anniversary Edition

This document details all modifications made to port ItemRack Classic to the TBC Anniversary Edition (2.5.4/2.5.5).

## Overview

The TBC Anniversary Edition runs on a modern WoW client engine (similar to Retail), which means many APIs have been moved to new namespaces or deprecated. This port adds compatibility shims and fixes to ensure ItemRack functions correctly.

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
5. Store the desired anchor in `ItemRack.pendingTooltipAnchor` so it can be **re-applied** after `tooltip:Show()` calls from hooks (e.g. `ListSetsHavingItem`) which would otherwise re-snap the tooltip
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
