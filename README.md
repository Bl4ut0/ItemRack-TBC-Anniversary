# ItemRack - TBC Anniversary Edition

A port of the classic ItemRack addon for **World of Warcraft: The Burning Crusade Classic Anniversary Edition (2.5.5)**.

## Credits

This addon is based on the original **ItemRack Classic** maintained by Rottenbeer and Roadblock:

🔗 **Original Addon:** [ItemRack Classic on CurseForge](https://www.curseforge.com/wow/addons/itemrack-classic)

**Original Author:** Gello  
**Classic Port:** Rottenbeer, Roadblock  
**TBC Anniversary Port:** Bl4ut0

## Installation

1. Download the latest release from the [Releases page](https://github.com/Bl4ut0/ItemRack-TBC-Anniversary/releases)
2. Extract the contents to your WoW addons folder:
   ```
   World of Warcraft\_classic_era_\Interface\AddOns\
   ```
3. You should have two folders:
   - `ItemRack/`
   - `ItemRackOptions/`
4. Restart WoW or type `/reload` if already in-game
5. ItemRack should appear as equipment slot buttons on your character panel

## 🎮 Features & Usage

ItemRack allows you to manage your gear with extreme precision through sets, automated queues, and event-based triggers.

### 🚀 Quick Access & Slot Buttons
- **Open Options:** Type `/itemrack opt` or **Right-Click** the minimap button.
- **Slot Buttons:** **Alt-Click** any item slot on your Character Sheet to create an on-screen "Quick Access" button for that slot.
- **Use Item:** **Left-Click** a slot button to use the item (trinkets, on-use effects).
- **Cycle Queue:** **Right-Click** a slot button to immediately swap to the next item in that slot's queue.
- **Open Slot Menu:** Hover over a slot button to open the item selection flyout menu.
- **Open Queue Options:** **Alt+Right-Click** a slot button to open the Queue configuration for that slot.
- **Auto-Queue Toggle:** **Alt+Left-Click** an on-screen slot button to toggle the Auto-Queue system for that specific slot on/off.

### ⚔️ Specialization Automation (Dual Spec)
ItemRack now supports seamless gear-spec integration:
1. Open the **Sets** tab in Options.
2. Select or create a gear set.
3. Check the **Primary Spec** or **Secondary Spec** box to link the set to your talent tree (e.g., "Holy", "Arms").
4. ItemRack will automatically switch your gear when you change specializations.
   - *Note:* A 0.5s stability timer prevents race conditions during the switch.

### 📋 Managing Gear Sets
- **Saving Sets:** Select the items you want, choose an icon, enter a name, and click **Save**.
- **Specialization Text:** Checkboxes now dynamically show your talent tree name if points are spent, making it easy to identify which set belongs to which build.
- **Focus Preservation:** Saving or equipping sets no longer resets your UI scroll position—you stay right where you were editing.

### 🔄 Auto-Queue System
The Auto-Queue system ensures you always have a "ready" item equipped:
1. Click the **Queue** button (lightning bolt) in Options for a specific slot.
2. Rank your items from top to bottom (Priority).
3. When an equipped item goes on cooldown, ItemRack will automatically swap it for the highest priority item that is ready.
4. **Pause Queue:** You can check "Pause Queue" on specific items to prevent them from being swapped out while in use.

### ⚡ Events & Automation
Events allow for complex automation based on game state:
1. Go to the **Config** tab and ensure **Enable Events** is checked.
2. Use the **Events** tab to link specific gear sets to triggers like:
   - **Drinking/Eating:** Swap to spirit gear.
   - **Mounting:** Swap to riding gear.
   - **Zone Changes:** Swap gear when entering a specific raid or city.
   - **Combat State:** Switch weapons or gear sets when entering/leaving combat.
3. **Event Tracking:** Use the "Events" listener button on the config page to monitor which triggers are firing in real-time for debugging.

## TBC Anniversary Compatibility

The TBC Anniversary Edition runs on a modern WoW client engine, which required several API compatibility fixes. See [TECHNICAL_CHANGES.md](TECHNICAL_CHANGES.md) for technical details and [CHANGELOG.md](CHANGELOG.md) for a summary of feature updates.

### Key Changes
- API namespace migrations (`C_Container`, `C_Item`, `C_AddOns`)
- Button template compatibility fixes for secure action handling
- **Visual Fix:** Resolved yellow triangle artifacts in Options Menu via texture cleanup
- Deprecation fallback shims for critical functions

## Support

For issues specific to the TBC Anniversary port, please open an issue on this GitHub repository.

For general ItemRack functionality questions, refer to the [original CurseForge page](https://www.curseforge.com/wow/addons/itemrack-classic).

## License

This addon maintains the same license as the original ItemRack Classic.
