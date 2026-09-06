# ItemRack - Anniversary Edition

A maintained port of the classic ItemRack addon for **WoW Classic Era/Hardcore/Season of Discovery (1.15.9)** and **The Burning Crusade Classic Anniversary (2.5.5/2.5.6)**.

## Credits

This addon is based on the original **ItemRack Classic** maintained by Rottenbeer and Roadblock:

🔗 **Original Addon:** [ItemRack Classic on CurseForge](https://www.curseforge.com/wow/addons/itemrack-classic)

**Original Author:** Gello  
**Classic Port:** Rottenbeer, Roadblock  
**TBC Anniversary Port:** Bl4ut0

## Installation

1. Download the latest release from the [Releases page](https://github.com/Bl4ut0/ItemRack-Anniversary/releases)
2. Extract the contents to the `Interface\AddOns` folder for the client you use, for example:
   ```
   World of Warcraft\_classic_era_\Interface\AddOns\
   World of Warcraft\_anniversary_\Interface\AddOns\
   ```
3. You should have two folders:
   - `ItemRack/`
   - `ItemRackOptions/`
4. **(Optional)** Install [LibSoundIndex](https://www.curseforge.com/wow/addons/libsoundindex) to mute individual gear-swap sounds without affecting combat alerts or UI. ItemRack never changes the game's global SFX setting when the library is absent.
5. Restart WoW or type `/reload` if already in-game
6. ItemRack should appear as equipment slot buttons on your character panel

## 🎮 Features & Usage

ItemRack allows you to manage your gear with extreme precision through sets, automated queues, and event-based triggers.

**[📖 View Complete Control Reference](CONTROLS.md)** - Detailed guide to all mouse clicks, keybinds, and commands.

### 🚀 Quick Access & Slot Buttons
- **Open Options:** Type `/itemrack opt` or **Right-Click** the minimap button.
- **Slot Buttons:** **Alt-Click** any item slot on your Character Sheet to create an on-screen "Quick Access" button for that slot.
- **Use Item:** **Left-Click** a slot button to use the item (trinkets, on-use effects).
- **Right-Click:** Opens the slot menu when **Menu on right click** is enabled; otherwise uses the item when **Use on right click** is enabled; with both disabled, advances to the next valid queue item.
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
5. **Per-Set Queues:** Gear Sets automatically save and recall which slot queues are currently enabled when you equip them.
6. **Burn on Use:** Burned queue items are now tracked by the exact queued item variant, so duplicate same-base items with different enchants, gems, or suffixes no longer burn each other.

### ⚡ Events & Automation
Events allow for complex automation based on game state:
1. Go to the **Config** tab and ensure **Enable Events** is checked.
2. Use the **Events** tab to link specific gear sets to triggers like:
   - **Drinking/Eating:** Swap to spirit gear.
   - **Mounting:** Swap to riding gear.
   - **Zone Changes:** Swap gear when entering a specific raid or city.
   - **Combat State:** Switch weapons or gear sets when entering/leaving combat.
3. **Manual Overrides:** Manually picking a set actively overrides and suppresses background events that attempt to combat your choice. 
4. **Event Tracking:** Use the **`/itemrack debug`** command to monitor which triggers are firing in real-time. This prints all background event logic and gear restorations directly to your chat window. (See the Diagnostic Debugging section below for more details).

#### Script Event Compatibility
Script events now have a stack-aware helper API:
- `EquipEventSet("Set Name")`
- `UnequipEventSet()`

Existing simple script events do **not** need to be rewritten if they use bare `EquipSet(...)` and `UnequipSet(...)` inside the script event editor. Those names are now shimmed onto the stack-aware event path automatically.

Recommended migration for older scripts:

Before:
```lua
EquipSet("My Set")
UnequipSet("My Set")
```

After:
```lua
EquipEventSet("My Set")
UnequipEventSet()
```

Use the new helper names when editing or creating script events going forward. If a script intentionally calls `ItemRack.EquipSet(...)` or `ItemRack.UnequipSet(...)`, that remains the low-level escape hatch and is not automatically stack-managed.

#### Script Event Safety

Script events execute Lua with addon-level access, so ItemRack treats their code as an explicit trust decision:

- Saving a valid custom Script event through ItemRack's editor counts as explicit approval and enables that exact source without an extra prompt.
- A Script event introduced or changed outside the editor is disabled. Deliberately enabling it opens an **Approve & Enable** prompt.
- Approval covers the exact event name, game-event trigger, and script text. Changing any of them disables the event and requires prompt approval or an ItemRack editor save.
- Unchanged scripts shipped with ItemRack are trusted as part of the installed addon. Modifying one removes that bundled trust.
- Rejected, malformed, oversized, or syntactically invalid new events are removed. Rejected changes to a previously approved event restore its last approved source, disabled.
- ItemRack removes or rolls back every remaining unapproved Script event before SavedVariables are written at logout. Registration and dispatch also recheck approval before compiling code.

WoW addons share one Lua environment, so no addon can sandbox another hostile addon or WeakAura. This guard prevents unreviewed code from using ItemRack's saved script-event engine as an execution or persistence path; users should still delete any untrusted aura or addon that supplied the code.

### 🛠️ Diagnostic Debugging Tools (New!)
ItemRack now includes an incredibly powerful, native diagnostic system built directly into the UI. No more trying to find or zip `WTF` folders—if you experience a bug, you can instantly export exactly what is wrong.

1. Turn on debugging: `/itemrack debug`
2. Perform the action that breaks (e.g., mounting, entering combat).
3. Type `/itemrack dump` to summon a native pop-up window containing the last 500 actions, queue states, and any stuck API locks.
4. Hit `CTRL+C` in the text box to instantly copy the exact, anonymized diagnostic code and active `SavedVariables` state for easy sharing when reporting a bug.

> [!IMPORTANT]
> **Data Privacy Notice:** The `/itemrack dump` command retrieves technical data for debugging, which includes your gear set names, queue configurations, and recently equipped items. It does **not** collect passwords or sensitive account information. Please review the output before sharing if you wish to keep specific set names private.

## TBC Anniversary Compatibility

The TBC Anniversary Edition runs on a modern WoW client engine, which required several API compatibility fixes. See [TECHNICAL_CHANGES.md](TECHNICAL_CHANGES.md) for technical details and [CHANGELOG.md](CHANGELOG.md) for a summary of feature updates.

### Key Changes
- API namespace migrations (`C_Container`, `C_Item`, `C_AddOns`)
- Button template compatibility fixes for secure action handling
- **Visual Fix:** Resolved yellow triangle artifacts in Options Menu via texture cleanup
- Deprecation fallback shims for critical functions

## Development and testing

Run `npm test` for the complete code-level release gate. The suite includes
deterministic large-profile workloads with dozens of overlapping saved sets,
deep event stacks, legacy queue migrations, and serialized equipment failures.
See [TESTING.md](TESTING.md) for the scenario matrix, reproduction seed, and the
client behaviors that still require in-game beta testing.

## Support

For issues specific to the TBC Anniversary port, please open an issue on this GitHub repository.

For general ItemRack functionality questions, refer to the [original CurseForge page](https://www.curseforge.com/wow/addons/itemrack-classic).

## License

This addon maintains the same license as the original ItemRack Classic.
