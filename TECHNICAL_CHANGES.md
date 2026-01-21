# Technical Changes for TBC Anniversary Edition

This document details all modifications made to port ItemRack Classic to the TBC Anniversary Edition (2.5.4/2.5.5).

## Overview

The TBC Anniversary Edition runs on a modern WoW client engine (similar to Retail), which means many APIs have been moved to new namespaces or deprecated. This port adds compatibility shims and fixes to ensure ItemRack functions correctly.

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
| `ItemRack/ItemRack.toc` | Version 4.24, Interface 20504, updated author |
| `ItemRack/ItemRack.lua` | C_AddOns, C_Container, C_Item shims, AuraUtil shim |
| `ItemRack/ItemRackButtons.lua` | LoadAddOn shim, macro button type |
| `ItemRack/ItemRackButtons.xml` | ActionBarButtonTemplate inheritance |
| `ItemRack/ItemRackEquip.lua` | C_Container shims |
| `ItemRack/ItemRackQueue.lua` | GetItemCooldown shim (C_Container), GetItemSpell/GetItemCount/IsEquippedItem shims |
| `ItemRackOptions/ItemRackOptions.toc` | Version 4.24, Interface 20504 |

---

## Testing Notes

### Verifying API Shims
Use these commands in-game to verify shims are working:

```lua
-- Check if shims are in place
/run print("GetItemCooldown:", GetItemCooldown and "exists" or "missing")
/run print("GetContainerNumSlots:", GetContainerNumSlots and "exists" or "missing")
/run print("LoadAddOn:", LoadAddOn and "exists" or "missing")

-- Test cooldown retrieval (slot 13 = trinket 1)
/run local s,d,e = GetItemCooldown(GetInventoryItemID("player", 13)); print("CD:", s, d, e)
```

### Verifying Button Attributes
```lua
/run local b=ItemRackButton13; print("type:", b:GetAttribute("type"), "macrotext:", b:GetAttribute("macrotext"))
```

Expected output: `type: macro macrotext: /use 13`

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
