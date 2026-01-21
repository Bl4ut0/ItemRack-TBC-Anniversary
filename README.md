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

## Features

- **Equipment slot buttons** - Quick access to swap gear
- **Gear sets** - Save and equip complete equipment configurations
- **Auto-queue system** - Automatically swap trinkets and other items based on cooldowns
- **Event-based swapping** - Swap gear based on in-game events
- **Masque support** - Compatible with button skinning addons

## TBC Anniversary Compatibility

The TBC Anniversary Edition runs on a modern WoW client engine, which required several API compatibility fixes. See [TECHNICAL_CHANGES.md](TECHNICAL_CHANGES.md) for detailed documentation of all modifications.

### Key Changes
- API namespace migrations (`C_Container`, `C_Item`, `C_AddOns`)
- Button template compatibility fixes for secure action handling
- Deprecation fallback shims for critical functions

## Support

For issues specific to the TBC Anniversary port, please open an issue on this GitHub repository.

For general ItemRack functionality questions, refer to the [original CurseForge page](https://www.curseforge.com/wow/addons/itemrack-classic).

## License

This addon maintains the same license as the original ItemRack Classic.
