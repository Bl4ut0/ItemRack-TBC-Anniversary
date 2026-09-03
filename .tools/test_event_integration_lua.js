const fs = require('fs');
const { runLua } = require('./lib/lua_harness');

const reducer = fs.readFileSync('ItemRack/ItemRackEventState.lua', 'utf8');
const events = fs.readFileSync('ItemRack/ItemRackEvents.lua', 'utf8');

runLua(String.raw`
function IsMounted() return false end
function UnitOnTaxi() return false end
function GetTime() return 0 end
function InCombatLockdown() return false end
function GetShapeshiftForm() return 0 end
function GetRealZoneText() return "" end
function GetSubZoneText() return "" end
function IsInInstance() return false,nil end
function GetInstanceInfo() return nil,nil,nil,nil,nil,nil,nil,nil end
function UnitClass() return "Shaman","SHAMAN" end
function GetUnitSpeed() return 0 end
C_AddOns, C_Spell, C_Talent = nil,nil,nil

local inventory = { [13]="Base13", [14]="Base14" }
ItemRack = {
  BuildID = "DevTest",
  Debug = function() end,
  Print = function() end,
  PreflightSetSwap = function() return {} end,
  GetID = function(slot) return inventory[slot] or 0 end,
  GetEquippedSlotState = function(slot)
    if inventory[slot] then return "resolved",inventory[slot] end
    return "empty",0
  end,
  IsAutomaticSwapBlocked = function() return true end,
}
ItemRackSettings = { EventsVersion=20 }
ItemRackUser = {
  EnableEvents = "ON",
  Events = {
    Enabled = { Ghostwolf=1, Mounted=1, City=1, LowerX=1, MiddleY=1, UpperX=1 },
    Set = {
      Ghostwolf="Zoom", Mounted="Zoom", City="CitySet",
      LowerX="XSet", MiddleY="YSet", UpperX="XSet",
    },
  },
  Sets = {
    Zoom = { equip={ [13]="Crop" } },
    CitySet = { equip={ [14]="City14" } },
    XSet = { equip={ [13]="X" } },
    YSet = { equip={ [13]="Y" } },
  },
  EventStack = {},
}
ItemRackEvents = {
  Ghostwolf={ Type="Stance", Unequip=1 },
  Mounted={ Type="Buff", Unequip=1 },
  City={ Type="Zone", Unequip=1 },
  LowerX={ Type="Buff", Unequip=1 },
  MiddleY={ Type="Buff", Unequip=1 },
  UpperX={ Type="Buff", Unequip=1 },
}

${reducer}
${events}

ItemRack.EventFrameBatchDepth = 1
local checks = 0
local function check(value,message) assert(value,message); checks = checks + 1 end

local ghost = ItemRack.PushEvent("Ghostwolf")
local mounted = ItemRack.PushEvent("Mounted")
check(ghost.changed and mounted.changed and ghost.frameId ~= mounted.frameId, "shared sets require distinct event frames")
check(#ItemRackUser.EventStack == 2, "EventStack must project both logical owners")
local removeGhost = ItemRack.PopEvent("Ghostwolf")
check(removeGhost.removed and removeGhost.targets[13] == nil, "buried shared owner must not change visible gear")
local mountedFrame = ItemRackUser.EventState.frames[ItemRackUser.EventState.byEvent.Mounted]
check(mountedFrame.slots[13].prior == "Base13", "remaining shared owner must inherit base history")
local stale = ItemRack.PopEvent("Ghostwolf",1)
check(not stale.removed and next(stale.targets) == nil, "stale second pop must be a total no-op")
local removeMounted = ItemRack.PopEvent("Mounted")
check(removeMounted.targets[13] == "Base13", "final shared owner must restore base")

local lower = ItemRack.PushEvent("LowerX")
local middle = ItemRack.PushEvent("MiddleY")
local upper = ItemRack.PushEvent("UpperX")
check(lower.frameId ~= upper.frameId and #ItemRackUser.EventStack == 3, "X-Y-X must retain three independent frames")
local removeMiddle = ItemRack.PopEvent("MiddleY")
check(removeMiddle.targets[13] == nil, "buried Y must not overwrite upper X")
local upperFrame = ItemRackUser.EventState.frames[ItemRackUser.EventState.byEvent.UpperX]
check(upperFrame.slots[13].prior == "X", "upper X must inherit lower X through removed Y")
check(ItemRack.ReleaseEventSlotsForManualChange({ [13]=true }), "manual change must release automatic ownership")
local afterManual = ItemRack.PopEvent("UpperX")
check(afterManual.removed and next(afterManual.targets) == nil, "released manual slot must never be restored by an old event")
check(ItemRackUser.EventState.revision > 0, "integrated operations must advance canonical revision")

-- EnsureEventFrameState owns the SavedVariables boundary: it captures an
-- immutable recovery copy, migrates once, and never derives prior history from
-- the gear merely observed at login.
ItemRackUser = {
  EnableEvents="ON",
  Events={ Enabled={ Mounted=1 }, Set={ Mounted="Zoom" } },
  Sets={ Zoom={ equip={ [13]="Crop" }, old={ [13]="LegacyBase" } } },
  EventStack={ "Mounted" },
}
ItemRackEvents = { Mounted={ Type="Buff", Unequip=1, Active=true } }
inventory[13] = "Crop"
local migrated = ItemRack.EnsureEventFrameState()
local migratedFrame = migrated.frames[migrated.byEvent.Mounted]
check(ItemRackUser.EventStateMigrationVersion == 1 and migratedFrame ~= nil,
  "SavedVariables initialization must version and migrate a legacy event stack")
check(migratedFrame.slots[13].prior == "LegacyBase",
  "legacy set.old must remain the migrated restoration baseline")
check(ItemRackUser.LegacyEventStateBackup.eventStack[1] == "Mounted" and
  ItemRackUser.LegacyEventStateBackup.sets.Zoom.old[13] == "LegacyBase",
  "the recovery backup must preserve both logical order and per-set history")
check(ItemRackUser.EventStateMigrationReport.source == "event_stack",
  "the persisted migration report must identify its evidence source")
local revision = migrated.revision
check(ItemRack.EnsureEventFrameState() == migrated and migrated.revision == revision,
  "the SavedVariables migration boundary must be idempotent")

local futureState = { schema=2, opaque={ keep="unchanged" } }
ItemRackUser = {
  Events={ Enabled={}, Set={} }, Sets={}, EventStack={ "Unknown" }, EventState=futureState,
}
ItemRack.EventStateSchemaUnsupported = nil
local safeRuntimeState = ItemRack.EnsureEventFrameState()
check(ItemRack.EventStateSchemaUnsupported and ItemRackUser.EventState == futureState and
  safeRuntimeState ~= futureState and safeRuntimeState.schema == 1,
  "a future event schema must remain untouched behind a fail-closed runtime state")

ItemRackUser = {
  EnableEvents="ON",
  Events={ Enabled={ Mounted=1 }, Set={ Mounted="Zoom" } },
  Sets={ Zoom={ equip={ [13]="Crop" }, old={ [13]="RecoveredBase" } } },
  EventStack={ "Mounted" },
  LegacyEventStateBackup="damaged earlier backup",
}
ItemRackEvents = { Mounted={ Type="Buff", Unequip=1, Active=true } }
ItemRack.EventStateSchemaUnsupported = nil
local recovered = ItemRack.EnsureEventFrameState()
check(ItemRackUser.UnknownLegacyEventStateBackup == "damaged earlier backup" and
  type(ItemRackUser.LegacyEventStateBackup) == "table" and
  recovered.frames[recovered.byEvent.Mounted].slots[13].prior == "RecoveredBase",
  "a malformed legacy backup must be preserved without blocking a fresh migration snapshot")

print(string.format("[EVENT INTEGRATION LUA] %d production Push/Pop checks passed.",checks))
`, 'event-integration');
