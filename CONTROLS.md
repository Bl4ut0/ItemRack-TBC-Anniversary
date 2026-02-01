# ItemRack Complete Control Scheme Reference

A comprehensive guide to all mouse, keyboard, and command controls available in ItemRack.

---

## 📌 Character Sheet Controls

| Action | Effect |
|--------|--------|
| **Alt+Click** any equipment slot | Creates an on-screen "Quick Access" button for that slot |
| **Alt+Click** the Character Model | Creates a "Set Button" (slot 20) for gear set management |
| **Hover** over an equipment slot | Opens the item selection flyout menu (if enabled) |
| **Shift+Hover** over slot | Opens the flyout menu when "Menu on Shift" option is enabled |

---

## 🎮 Quick Access Slot Button Controls

| Action | Effect |
|--------|--------|
| **Left-Click** | Uses the item (activates on-use trinkets, equippables, etc.) |
| **Right-Click** | Advances to the next item in the queue for that slot |
| **Hover** | Opens the item selection flyout menu |
| **Shift+Left-Click** | Links the equipped item to chat (if chat edit box is open) |
| **Alt+Left-Click** | Toggles Auto-Queue ON/OFF for that slot |
| **Alt+Right-Click** | Opens the Queue configuration panel for that slot |
| **Drag (Left or Right)** | Moves the button (if unlocked); Shift+Drag moves just that button, otherwise the entire docked group moves |

---

## 🔘 Set Button (Slot 20) Controls

| Action | Effect |
|--------|--------|
| **Left-Click** | Equips the current set (or toggles if "Equip Toggle" is ON) |
| **Right-Click** | Opens the Sets tab in Options |
| **Shift+Left-Click** | Unequips the current gear set |
| **Alt+Left-Click** | Toggles ItemRack Events ON/OFF |
| **Alt+Right-Click** | Opens the Sets tab in Options |

---

## 📋 Flyout Menu (Item Selection) Controls

| Action | Effect |
|--------|--------|
| **Left-Click** item | Equips that item to the slot |
| **Right-Click** item | Equips item (if TrinketMenuMode is ON, chooses slot 14; otherwise same as left-click) |
| **Shift+Click** item | Links the item to chat (if chat edit box is open) |
| **Alt+Click** item | Toggles the item as "Hidden" (if AllowHidden is ON) |
| **Left-Click** while bank is open | Pulls item from bank to bags, or pushes to bank if already owned |
| **Right-Click** menu frame | Toggles menu orientation (Vertical ↔ Horizontal) |
| **Drag** menu frame border | Re-docks the menu to a different corner of the button |

---

## 🌐 Minimap / Data Broker Button Controls

| Action | Effect |
|--------|--------|
| **Left-Click** | Opens the gear set selection menu |
| **Right-Click** | Opens the ItemRack Options window |
| **Shift+Click** | Unequips the current gear set |
| **Alt+Left-Click** | Shows hidden sets in the menu |
| **Alt+Right-Click** | Toggles ItemRack Events ON/OFF |

---

## ⌨️ Slash Commands

| Command | Effect |
|---------|--------|
| `/itemrack opt` or `/itemrack options` | Opens the Options window |
| `/itemrack equip <set name>` | Equips the specified set |
| `/itemrack toggle <set name>` | Toggles the specified set on/off |
| `/itemrack toggle <set1>, <set2>` | Toggles between two sets |
| `/itemrack lock` | Locks all buttons in place |
| `/itemrack unlock` | Unlocks buttons for repositioning |
| `/itemrack reset` | Resets all buttons and positions |
| `/itemrack reset everything` | Wipes all ItemRack data and reloads UI |

---

## 🔧 Button Movement & Docking

| Action | Effect |
|--------|--------|
| **Drag** a button | Moves the entire docked button group |
| **Shift+Drag** | Moves only that individual button (breaks from dock chain) |
| Buttons near each other automatically **snap/dock** together when dropped |

---

## ⚙️ Relevant Options

| Option | Effect |
|--------|--------|
| **Disable Alt+Click** | Disables Alt+Click toggling Auto-Queue (useful for self-cast macros) |
| **Menu on Shift** | Requires holding Shift to open flyout menus |
| **Menu on Right-Click** | Opens menus on right-click instead of hover |
| **Allow Hidden** | Enables hiding items from menus via Alt+Click |
| **Lock** | Prevents all button movement |

---

## 🔄 Auto-Queue System

The Auto-Queue system automatically swaps items based on cooldown availability:

1. **Enable Queue**: Alt+Left-Click a slot button, or use the Queue tab in Options
2. **Configure Priority**: In the Queue tab, rank items from highest to lowest priority
3. **How it works**: When an equipped item goes on cooldown, ItemRack swaps to the next ready item
4. **Pause Queue**: Check "Pause Queue" on items to prevent them from being swapped out during use

---

## ⚡ Combat Queue

If you try to swap items while in combat, ItemRack will:
1. Queue the swap for when combat ends
2. Show a small overlay icon on the slot button indicating what's queued
3. Automatically perform the swap when you leave combat

---

## 📝 Notes

- Most actions that modify buttons or swap gear are **blocked during combat** due to Blizzard's secure action restrictions
- The "Set Button" (slot 20) appears when you Alt+Click the character model frame
- Hidden items can still be seen by holding Alt while hovering over menus (if AllowHidden is enabled)
- TrinketMenuMode combines both trinket slots into a single menu for easier management
