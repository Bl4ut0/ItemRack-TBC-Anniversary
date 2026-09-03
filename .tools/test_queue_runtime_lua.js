const { extractFunction, runLua } = require('./lib/lua_harness');

const queueFile = 'ItemRack/ItemRackQueue.lua';
const equipFile = 'ItemRack/ItemRackEquip.lua';
const clearManual = extractFunction(queueFile, 'ItemRack.ClearManualQueueChoice');
const findQueueEntry = extractFunction(queueFile, 'ItemRack.FindQueueEntryIndex');
const isManual = extractFunction(queueFile, 'ItemRack.IsManualQueueChoice');
const setManual = extractFunction(queueFile, 'ItemRack.SetManualQueueChoice');
const autoQueue = extractFunction(queueFile, 'ItemRack.AutoQueueItemToEquip');
const isSetEquipped = extractFunction(equipFile, 'ItemRack.IsSetEquipped');

runLua(String.raw`
local activeList = { { id="100" } }
local inspectedList = { { id="200" } }
local contexts = {
  Active = { owner="Active", list=activeList, enabled=true },
  Other = { owner="Other", list=inspectedList, enabled=true },
}

ItemRackUser = {
  EnableQueues="ON",
  Sets={ Other={ equip={ [13]="200" } } },
}
ItemRack = {
  QueueStateReady=true,
  ManualQueueChoice={ [13]="100" },
  ManualQueueChoiceOwner={ [13]="Active" },
  GetQueueContext=function(_,setname) return contexts[setname or "Active"] end,
  IsEquippedSlotStateReady=function() return true end,
  SameExactID=function(a,b) return tostring(a)==tostring(b) end,
  SameID=function(a,b) return tostring(a)==tostring(b) end,
  MatchesStoredItemID=function(a,b) return tostring(a)==tostring(b) end,
  HasRuneID=function() return false end,
  IsQueueEntryUnambiguous=function() return true end,
  IsQueueItemBurnt=function() return false end,
  GetID=function() return "999" end,
  GetIRString=function(value) return tostring(value) end,
  ShouldHoldEquippedItem=function() return false end,
  ItemNearReady=function() return false end,
  IsCandidateReady=function() return false end,
  FindItemInBags=function() return nil end,
  Debug=function() end,
}
function GetInventoryItemCooldown() return 0,0,1 end
function GetItemSpell() return nil end
function GetTime() return 100 end
AuraUtil = { FindAuraByName=function() return nil end }

${clearManual}
${findQueueEntry}
${isManual}
${setManual}
${autoQueue}
${isSetEquipped}

local checks = 0
local function check(value,message) assert(value,message); checks = checks + 1 end

check(ItemRack.IsManualQueueChoice(13,"100","100",nil,activeList,"Active"),
  "manual hold must validate against its atomic active context")
check(not ItemRack.IsManualQueueChoice(13,"100","100","Other",inspectedList,"Other"),
  "manual hold must not cross into a different queue owner")

local matched = ItemRack.IsSetEquipped("Other")
check(not matched, "fixture must inspect a physically different set")
check(ItemRack.ManualQueueChoice[13] == "100" and ItemRack.ManualQueueChoiceOwner[13] == "Active",
  "IsSetEquipped must not mutate a manual choice while inspecting another set")

-- Candidate selection is a query. Even a stale hold is cleaned only by the
-- explicit ProcessAutoQueue mutation path, never by this reusable predicate.
ItemRack.ManualQueueChoice[13] = "Missing"
ItemRack.ManualQueueChoiceOwner[13] = "Active"
ItemRack.AutoQueueItemToEquip(13,"999",1,false,nil,contexts.Active)
check(ItemRack.ManualQueueChoice[13] == "Missing" and ItemRack.ManualQueueChoiceOwner[13] == "Active",
  "AutoQueueItemToEquip must remain side-effect free for manual choices")

ItemRack.SetManualQueueChoice(13,"100")
check(ItemRack.ManualQueueChoice[13] == "100" and ItemRack.ManualQueueChoiceOwner[13] == "Active",
  "manual choices must record the same owner that supplied their list")
ItemRack.ClearManualQueueChoice(13)
check(ItemRack.ManualQueueChoice[13] == nil and ItemRack.ManualQueueChoiceOwner[13] == nil,
  "manual choice cleanup must clear identity and provenance together")

local cooldownList = { { id="200" }, { id="999" } }
local cooldownContext = { owner="Cooldown", list=cooldownList, enabled=true }
ItemRack.FindItemInBags=function() return 0,1 end
ItemRack.IsCandidateReady=function() return true end
ItemRack.GetObservedItemCooldown=function() return nil end
local candidate = ItemRack.AutoQueueItemToEquip(13,"999",0,true,"Cooldown",cooldownContext)
check(candidate == nil,
  "raw enable=0 must not override normalized hold/readiness state")

cooldownList[2].delay = 10
ItemRack.GetObservedItemCooldown=function() return { start=95, duration=60 } end
candidate = ItemRack.AutoQueueItemToEquip(13,"999",1,false,"Cooldown",cooldownContext)
check(candidate == nil,
  "false-zero raw slot sample must not bypass delay from shared authority")

print(string.format("[QUEUE RUNTIME LUA] %d purity and provenance checks passed.",checks))
`, 'queue-runtime');
