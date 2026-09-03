const fs = require('fs');
const { extractFunction, runLua } = require('./lib/lua_harness');

const coreFile = 'ItemRack/ItemRack.lua';
const core = fs.readFileSync(coreFile, 'utf8');

const clearBinding = extractFunction(coreFile, 'ItemRack.ClearBindingAction');
const beginBinding = extractFunction(coreFile, 'ItemRack.BeginSetBinding');
const processBinding = extractFunction(coreFile, 'ItemRack.ProcessPendingSetBinding');
const runBinding = extractFunction(coreFile, 'ItemRack.RunSetBinding');
const configureButton = extractFunction(coreFile, 'ItemRack.ConfigureSetBindingButton');
const neutralizeButton = extractFunction(coreFile, 'ItemRack.NeutralizeSetBindingButton');
const queueBindings = extractFunction(coreFile, 'ItemRack.QueueSetBindingsAfterCombat');
const setBindings = extractFunction(coreFile, 'ItemRack.SetSetBindings');

function runCase(name, setup, functions, assertions) {
  runLua(`${setup}\n${functions.join('\n')}\n${assertions}`, `set-binding:${name}`);
}

let checks = 0;

runCase(
  'pre-click intent and logical repeat toggles',
  `
local combat = true
ItemRackUser = { Sets={ Alpha={ equip={ [16]="target" } } } }
ItemRackSettings = { EquipToggle="ON" }
ItemRack = {
  SetBindingRequestSequence=0,
  QueueStateGeneration=7,
  Debug=function() end,
  IsSetEquipped=function() return false end,
}
function InCombatLockdown() return combat end
function GetTime() return 42 end
`,
  [beginBinding],
  `
local first = ItemRack.BeginSetBinding("Alpha")
assert(first.intent == "equip" and first.observedEquipped == false,
  "first toggle press must capture equip against pre-click gear")
assert(first.inCombat and first.queueGeneration == 7 and first.createdAt == 42,
  "request must retain diagnostic combat/generation metadata")
ItemRack.PendingSetBindingRequest = first
local second = ItemRack.BeginSetBinding("Alpha")
assert(second.intent == "unequip", "second unchanged combat press must invert logical pending intent")
ItemRack.PendingSetBindingRequest = second
local third = ItemRack.BeginSetBinding("Alpha")
assert(third.intent == "equip", "third unchanged combat press must invert the newest intent again")
ItemRackSettings.EquipToggle = "OFF"
ItemRack.IsSetEquipped = function() return true end
local fourth = ItemRack.BeginSetBinding("Alpha")
assert(fourth.intent == "equip", "non-toggle bindings must always capture equip")
assert(ItemRack.BeginSetBinding("Missing") == nil, "missing sets must not produce requests")
`
);
checks += 7;

runCase(
  'combat containment and out-of-combat drain',
  `
local combat,equips,unequips = true,0,0
ItemRackUser = { Sets={ Alpha={ equip={} } } }
ItemRackSettings = { EquipToggle="ON" }
ItemRack = {
  Debug=function() end,
  IsPlayerReallyDead=function() return false end,
  EquipSet=function(name) assert(name == "Alpha"); equips=equips+1 end,
  UnequipSet=function() unequips=unequips+1 end,
}
function InCombatLockdown() return combat end
`,
  [beginBinding, processBinding, runBinding],
  `
local request={ kind="secure_set_binding", id=1, setname="Alpha", intent="equip", observedEquipped=false }
local status,reason = ItemRack.RunSetBinding("Alpha",request)
assert(status == "deferred" and reason == "protected", "combat click must be retained, not executed")
assert(ItemRack.PendingSetBindingRequest == request, "combat click must retain the exact explicit request")
assert(equips == 0 and unequips == 0, "combat click must make no insecure equipment call")
combat=false
local processed,intent = ItemRack.ProcessPendingSetBinding("test regen")
assert(processed and intent == "equip", "regen must drain the captured action")
assert(ItemRack.PendingSetBindingRequest == nil, "drained intent must transfer ownership exactly once")
assert(equips == 1 and unequips == 0, "drain must execute only the captured equip action")
assert(ItemRack.ProcessPendingSetBinding() == false and equips == 1,
  "an already drained request must never replay")
`
);
checks += 7;

runCase(
  'newest manual request wins with fixed unequip action',
  `
local combat,trace = true,{}
ItemRackUser = { Sets={ Alpha={equip={}}, Beta={equip={}} } }
ItemRackSettings = { EquipToggle="ON" }
ItemRack = {
  Debug=function() end,
  IsPlayerReallyDead=function() return false end,
  EquipSet=function(name) table.insert(trace,"equip:"..name) end,
  UnequipSet=function(name) table.insert(trace,"unequip:"..name) end,
}
function InCombatLockdown() return combat end
`,
  [beginBinding, processBinding, runBinding],
  `
ItemRack.RunSetBinding("Alpha",{kind="secure_set_binding",id=1,setname="Alpha",intent="equip"})
ItemRack.RunSetBinding("Beta",{kind="secure_set_binding",id=2,setname="Beta",intent="unequip"})
assert(ItemRack.PendingSetBindingRequest.id == 2 and ItemRack.PendingSetBindingRequest.setname == "Beta",
  "newest manual set binding must replace the older pending request")
combat=false
ItemRack.ProcessPendingSetBinding("regen")
assert(#trace == 1 and trace[1] == "unequip:Beta",
  "drain must preserve the newest request's explicit action without re-evaluating toggle state")
`
);
checks += 2;

runCase(
  'invalid request drops and manual precedence cancels automatic readiness work',
  `
local canceled,equipped = nil,0
ItemRackUser = { Sets={ Alpha={equip={}} } }
ItemRack = {
  Debug=function() end,
  IsPlayerReallyDead=function() return false end,
  EquipSet=function() equipped=equipped+1 end,
  UnequipSet=function() error("unexpected unequip") end,
}
function InCombatLockdown() return false end
`,
  [processBinding],
  `
ItemRack.PendingSetBindingRequest={kind="secure_set_binding",id=1,setname="Deleted",intent="equip"}
local ok,reason=ItemRack.ProcessPendingSetBinding("deleted")
assert(not ok and reason == "invalid" and ItemRack.PendingSetBindingRequest == nil,
  "deleted-set request must be discarded deterministically")
local automatic={setname="~EventFrame:2",isAutomatic=true}
ItemRack.PendingQueueEquipSet=automatic
ItemRack.CancelPendingQueueEquipSet=function(value,why)
  assert(value == automatic); canceled=why; ItemRack.PendingQueueEquipSet=nil
end
ItemRack.PendingSetBindingRequest={kind="secure_set_binding",id=2,setname="Alpha",intent="equip"}
assert(ItemRack.ProcessPendingSetBinding("ready"), "valid manual intent must execute")
assert(canceled == "set_binding_manual_precedence", "manual binding must cancel older automatic readiness intent")
assert(equipped == 1, "manual intent must execute after automatic cancellation")
`
);
checks += 4;

runCase(
  'secure button is a no-op carrier',
  `
local combat,equips = false,0
local attributes,scripts = {},{}
local button={
  GetName=function() return "BindingAlpha" end,
  SetAttribute=function(_,name,value) attributes[name]=value end,
  SetScript=function(_,name,value) scripts[name]=value end,
}
ItemRackUser={Sets={Alpha={equip={ [16]="weapon" }}}}
ItemRackSettings={EquipToggle="ON"}
ItemRack={
  SetBindingButtons={}, SetBindingRequestSequence=0,
  Debug=function() end,
  IsSetEquipped=function() return false end,
  IsPlayerReallyDead=function() return false end,
  EquipSet=function() equips=equips+1 end,
  UnequipSet=function() error("unexpected unequip") end,
}
function InCombatLockdown() return combat end
function GetTime() return 1 end
`,
  [beginBinding, processBinding, runBinding, configureButton, neutralizeButton],
  `
assert(ItemRack.ConfigureSetBindingButton(button,"Alpha"), "button must configure out of combat")
assert(attributes.type == "macro" and attributes.macrotext == "" and attributes.useOnKeyDown == false,
  "secure carrier must have an empty macro action on key-up")
assert(type(scripts.PreClick) == "function" and type(scripts.PostClick) == "function",
  "configured carrier must capture and dispatch around its no-op secure phase")
combat=true
scripts.PreClick()
scripts.PostClick()
assert(equips == 0 and ItemRack.PendingSetBindingRequest and ItemRack.PendingSetBindingRequest.setname == "Alpha",
  "PreClick -> secure no-op -> PostClick must only retain intent during combat")
combat=false
ItemRack.ProcessPendingSetBinding("regen")
assert(equips == 1, "retained carrier intent must execute after combat")
assert(ItemRack.NeutralizeSetBindingButton(button), "button must neutralize out of combat")
assert(attributes.macrotext == "" and scripts.PreClick == nil and scripts.PostClick == nil,
  "neutralization must remove both callbacks while retaining an empty secure action")
`
);
checks += 7;

runCase(
  'binding reconciliation imports safely and neutralizes stale frames',
  `
local bindings,keyActions,frames = {},{},{}
local saves = 0
local function NewButton(name)
  local attributes,scripts={},{}
  local button={attributes=attributes,scripts=scripts}
  function button:GetName() return name end
  function button:SetAttribute(key,value) attributes[key]=value end
  function button:SetScript(key,value) scripts[key]=value end
  frames[name]=button
  return button
end
local stale=NewButton("StaleButton")
bindings["CLICK StaleButton:LeftButton"]="CTRL-S"
keyActions["CTRL-S"]="CLICK StaleButton:LeftButton"
bindings["CLICK ButtonDeleted:LeftButton"]="CTRL-D"
keyActions["CTRL-D"]="CLICK ButtonDeleted:LeftButton"
keyActions["CTRL-X"]="JUMP"
ItemRackUser={Sets={Active={equip={},key="CTRL-A"},Conflict={equip={},key="CTRL-X"}}}
ItemRack={
  SetBindingButtons={StaleButton=stale}, RunAfterCombat={},
  Debug=function() end,
  GetSetBindingButtonPrefix=function() return "Button" end,
  GetSetBindingButtonName=function(name) return "Button"..name end,
  SaveCurrentBindings=function() saves=saves+1 end,
}
function InCombatLockdown() return false end
function GetBindingKey(action) return bindings[action] end
function GetBindingAction(key) return keyActions[key] or "" end
function GetNumBindings() return 1 end
function GetBinding(index)
  if index == 1 then return "CLICK ButtonDeleted:LeftButton" end
end
function SetBindingClick(key,buttonName)
  local action="CLICK "..buttonName..":LeftButton"
  bindings[action]=key; keyActions[key]=action; return true
end
function SetBinding(key)
  local action=keyActions[key]
  if action then bindings[action]=nil end
  keyActions[key]=nil
  return true
end
function CreateFrame(_,name) return NewButton(name) end
`,
  [clearBinding, configureButton, neutralizeButton, queueBindings, setBindings],
  `
ItemRack.SetSetBindings()
local active=frames.ButtonActive
assert(active and active.attributes.macrotext == "" and type(active.scripts.PreClick) == "function",
  "saved free key must create a configured no-op carrier")
assert(bindings["CLICK ButtonActive:LeftButton"] == "CTRL-A",
  "free saved key must import into the active Blizzard binding table")
assert(ItemRackUser.Sets.Conflict.key == nil and bindings["CLICK ButtonConflict:LeftButton"] == nil,
  "saved set key must never replace an unrelated active action")
assert(keyActions["CTRL-X"] == "JUMP", "conflicting normal binding must remain untouched")
assert(bindings["CLICK StaleButton:LeftButton"] == nil and keyActions["CTRL-S"] == nil,
  "orphaned registered set action must be cleared")
assert(bindings["CLICK ButtonDeleted:LeftButton"] == nil and keyActions["CTRL-D"] == nil,
  "cross-reload orphan in this character's set namespace must be enumerated and cleared")
assert(stale.scripts.PreClick == nil and stale.scripts.PostClick == nil and stale.attributes.macrotext == "",
  "orphaned frame must be neutralized after its binding is cleared")
assert(saves == 1 and ItemRack.SetBindingsReconciling == nil,
  "all reconciliation mutations must batch into one save and release the guard")
`
);
checks += 8;

runCase(
  'combat reconciliation is coalesced',
  `
ItemRackUser={Sets={}}
ItemRack={RunAfterCombat={},SetBindingButtons={}}
function InCombatLockdown() return true end
function CreateFrame() error("protected frame must not be created in combat") end
`,
  [queueBindings, setBindings],
  `
ItemRack.SetSetBindings()
ItemRack.SetSetBindings()
assert(#ItemRack.RunAfterCombat == 1 and ItemRack.RunAfterCombat[1] == "SetSetBindings",
  "repeated combat reconciliation requests must coalesce")
`
);
checks += 1;

if (core.includes('/equipslot [combat]')) {
  throw new Error('[SET BINDING LUA] Production code still contains a split secure equipslot macro.');
}
checks += 1;

console.log(`[SET BINDING LUA] ${checks} intent, containment, and reconciliation checks passed.`);
