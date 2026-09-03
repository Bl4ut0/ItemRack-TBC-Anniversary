const fs = require('fs');
const { runLua } = require('./lib/lua_harness');

const policy = fs.readFileSync('ItemRack/ItemRackQueuePolicy.lua', 'utf8');

runLua(String.raw`
ItemRack = {}
${policy}

local checks = 0
local function check(value,message) assert(value,message); checks = checks + 1 end
local function resolve(user,slot,setname)
  return ItemRack.QueuePolicy.Resolve(user,function(eventName)
    return user.Events and user.Events.Set and user.Events.Set[eventName]
  end,slot,setname)
end
local function baseUser()
  return {
    EnablePerSetQueues="ON",
    EnableQueueContextCheck="ON",
    CurrentSet="Current",
    Queues={ [13]={ { id="Global" } } },
    QueuesEnabled={ [13]=true },
    Events={ Set={ Lower="LowerSet", Upper="UpperSet" } },
    EventStack={ "Lower", "Upper" },
    Sets={ Current={ equip={} }, LowerSet={ equip={} }, UpperSet={ equip={} } },
  }
end

do
  local user = baseUser()
  user.EnablePerSetQueues = "OFF"
  local context = resolve(user,13)
  check(context.owner == false and context.list[1].id == "Global" and context.enabled == true,
    "disabled per-set queues must return one global tuple")
end

do
  local user = baseUser()
  user.Sets.Current.Queues = { [13]={ { id="Current" } } }
  user.Sets.Current.QueuesEnabled = { [13]=false }
  local context = resolve(user,13)
  check(context.owner == "Current" and context.list[1].id == "Current",
    "current boundary must own its whole tuple")
  check(context.enabled == false, "explicit false enabled state must not fall through")
end

do
  local user = baseUser()
  user.Sets.Current.Queues = { [13]={ { id="Current" } } }
  user.Sets.LowerSet.QueuesEnabled = { [13]=true }
  local context = resolve(user,13)
  check(context.owner == "Current" and context.list[1].id == "Current" and context.enabled == nil,
    "a list-only layer must not borrow enabled state from another owner")
end

do
  local user = baseUser()
  user.Sets.Current.QueuesEnabled = { [13]=true }
  user.Sets.UpperSet.Queues = { [13]={ { id="Upper" } } }
  local context = resolve(user,13)
  check(context.owner == "Current" and context.list == nil and context.enabled == true,
    "an enabled-only layer must not borrow a list from another owner")
end

do
  local user = baseUser()
  user.Sets.Current.equip[13] = "OwnedGear"
  user.Sets.UpperSet.Queues = { [13]={ { id="Upper" } } }
  user.Sets.UpperSet.QueuesEnabled = { [13]=true }
  local context = resolve(user,13)
  check(context.owner == "Current" and context.list == nil and context.enabled == nil,
    "explicit equipped gear must block every lower queue policy")
end

do
  local user = baseUser()
  user.Sets.LowerSet.Queues = { [13]={ { id="Lower" } } }
  user.Sets.LowerSet.QueuesEnabled = { [13]=true }
  user.Sets.UpperSet.Queues = { [13]={ { id="Upper" } } }
  local context = resolve(user,13)
  check(context.owner == "UpperSet" and context.list[1].id == "Upper" and context.enabled == nil,
    "top event boundary must supply the entire tuple without lower-field mixing")
end

do
  local user = baseUser()
  user.CurrentSet = nil
  user.Sets.UpperSet.Queues = { [13]={ { id="Upper" } } }
  user.Sets.UpperSet.QueuesEnabled = { [13]=true }
  local context = resolve(user,13)
  check(context.owner == "UpperSet" and context.reason == "event_stack",
    "event policy must remain visible when CurrentSet is temporarily unknown")
end

do
  local user = baseUser()
  local context = resolve(user,13,"LowerSet")
  check(context.owner == false and context.list == nil and context.enabled == nil,
    "explicit set inspection must be raw and must not inherit active/global fields")
  user.Sets.LowerSet.equip[13] = "Boundary"
  context = resolve(user,13,"LowerSet")
  check(context.owner == "LowerSet" and context.list == nil and context.enabled == nil,
    "explicit gear boundary must be attributed to the inspected set")
end

do
  local user = baseUser()
  local context = resolve(user,13)
  check(context.owner == false and context.list[1].id == "Global" and context.enabled == true,
    "no per-set boundary must fall back to one global tuple")
end

do
  local user = baseUser()
  user.EnableQueueContextCheck = "OFF"
  local context = resolve(user,13)
  check(context.owner == false and context.list == nil and context.enabled == nil,
    "disabled context inheritance must expose raw current-set fields, not global fields")
end

print(string.format("[QUEUE POLICY LUA] %d atomic resolution checks passed.",checks))
`, 'queue-policy');
