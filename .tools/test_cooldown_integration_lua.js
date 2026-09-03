const fs = require('fs');
const { extractFunction, runLua } = require('./lib/lua_harness');

const coreFile = 'ItemRack/ItemRack.lua';
const buttonsFile = 'ItemRack/ItemRackButtons.lua';
const queueFile = 'ItemRack/ItemRackQueue.lua';
const cooldownState = fs.readFileSync('ItemRack/ItemRackCooldownState.lua', 'utf8');
const resetCaches = extractFunction(coreFile, 'ItemRack.ResetCooldownCaches');
const updateArena = extractFunction(coreFile, 'ItemRack.UpdateArenaVisibilityState');
const updateMenu = extractFunction(coreFile, 'ItemRack.UpdateMenuCooldowns');
const writeMenu = extractFunction(coreFile, 'ItemRack.WriteMenuCooldowns');
const cooldownUpdate = extractFunction(coreFile, 'ItemRack.CooldownUpdate');
const updateButtons = extractFunction(buttonsFile, 'ItemRack.UpdateButtonCooldowns');
const writeButtons = extractFunction(buttonsFile, 'ItemRack.WriteButtonCooldowns');
const cooldownLeft = extractFunction(queueFile, 'ItemRack.GetItemCooldownLeft');

runLua(String.raw`
local now = 100
local instanceType
local slotExact = "100:exact"
local slotBase = 100
local slotCooldown = { 95, 60, 1 }
local itemCooldowns = { [100]={ 0, 0, 0 } }
local notifications = {}

local function NewFrame()
  return {
    SetHideCountdownNumbers=function(self,value) self.hideNumbers=value end,
    Hide=function(self) self.hidden=true end,
  }
end
local function NewText()
  return { SetText=function(self,value) self.text=value end }
end

function GetTime() return now end
function IsInInstance() return instanceType ~= nil,instanceType end
function GetInventoryItemID(_,slot) if slot == 13 then return slotBase end end
function GetInventoryItemCooldown(_,slot)
  if slot ~= 13 then return 0,0,1 end
  return slotCooldown[1],slotCooldown[2],slotCooldown[3]
end
function GetItemCooldown(id)
  local value = itemCooldowns[tonumber(id)]
  if not value then return nil,nil,nil end
  return value[1],value[2],value[3]
end
function GetItemInfo(id) return "Item"..tostring(id) end
function CooldownFrame_Set(frame,start,duration,enable)
  frame.last={ kind="set", start=start, duration=duration, enable=enable }
end
function CooldownFrame_Clear(frame) frame.last={ kind="clear" } end
function IRRoundTenths(value) return value or 0 end
function IRDebugCooldownState() end

ItemRackSettings = {
  CooldownCount="ON", Notify="ON", NotifyThirty="ON",
}
ItemRackUser = { Buttons={ [13]=1 }, ItemsUsed={} }
ItemRack = {
  Menu={ "100:exact" }, menuOpen=13,
  CooldownCache={}, MenuCooldownCache={}, CooldownDebugLast={},
  DebugTags={},
  GetID=function(slot) if slot == 13 then return slotExact end return 0 end,
  GetIRString=function(value)
    return string.match(tostring(value or ""),"^(%d+)") or 0
  end,
  WriteCooldown=function(where,start,duration)
    where.textStart=start
    where.textDuration=duration
  end,
  Notify=function(message) table.insert(notifications,message) end,
  RefreshButtonVisibility=function() ItemRack.visibilityRefreshes=(ItemRack.visibilityRefreshes or 0)+1 end,
  PeriodicQueueCheck=function() ItemRack.queueChecks=(ItemRack.queueChecks or 0)+1 end,
}

ItemRackMenuFrame = { IsVisible=function() return true end }
_G.ItemRackButton13Cooldown = NewFrame()
_G.ItemRackButton13Time = NewText()
_G.ItemRackMenu1Cooldown = NewFrame()
_G.ItemRackMenu1Time = NewText()

${cooldownState}
${writeButtons}
${updateButtons}
${writeMenu}
${updateMenu}
${resetCaches}
${updateArena}
${cooldownLeft}
${cooldownUpdate}

local checks = 0
local function check(value,message) assert(value,message); checks = checks + 1 end

-- Button publication is renderer-independent. A popup opened later while the
-- item API is disabled must consume that same observation.
ItemRack.UpdateButtonCooldowns()
check(_G.ItemRackButton13Cooldown.last.start == 95,
  "button must render the normalized active cooldown")
check(ItemRack.GetObservedItemCooldown("100:exact",100) ~= nil,
  "button must publish into the shared identity authority")

slotExact,slotBase,slotCooldown = "200:exact",200,{ 0,0,1 }
ItemRack.UpdateButtonCooldowns()
check(_G.ItemRackButton13Cooldown.last.kind == "clear",
  "swapped slot must clear its presentation")
check(ItemRack.GetObservedItemCooldown("100:exact",100) ~= nil,
  "swapping an item out must not erase its active identity cooldown")

ItemRack.UpdateMenuCooldowns()
check(_G.ItemRackMenu1Cooldown.last.kind == "set"
  and _G.ItemRackMenu1Cooldown.last.start == 95,
  "first popup open during CC must reuse the earlier button observation")
check(_G.ItemRackMenu1Time.textStart == 95,
  "popup countdown text must read the same authority as its cooldown frame")

-- Arena entry is an ordering barrier, not a timed cache clear. Both renderers
-- initially see a late pre-entry sample and must reject it.
now = 300
slotExact,slotBase,slotCooldown = "300:exact",300,{ 290,120,1 }
ItemRack.Menu = { "300:exact" }
itemCooldowns[300] = { 290,120,1 }
ItemRackUser.ItemsUsed[300] = 5
instanceType = "arena"
ItemRack.UpdateArenaVisibilityState()
check(ItemRack.CooldownObservations.arena ~= nil,
  "arena entry must open a generation barrier")
check(_G.ItemRackButton13Cooldown.last.kind == "clear"
  and _G.ItemRackMenu1Cooldown.last.kind == "clear",
  "pre-entry samples must not be painted after arena entry")
check(ItemRack.GetObservedItemCooldown("300:exact",300) == nil,
  "pre-entry samples must not repopulate the arena generation")
check(ItemRackUser.ItemsUsed[300] == 5,
  "arena transition itself must not race notification state")

ItemRack.CooldownUpdate()
check(ItemRackUser.ItemsUsed[300] == nil and #notifications == 0,
  "stale arena publication must retire notifications silently")

-- Once the boundary is confirmed, a genuine post-entry use is authoritative;
-- later disabled/LoC samples cannot erase it.
now = 302
slotCooldown = { 0,0,1 }
ItemRack.UpdateButtonCooldowns()

-- Reset classification is durable across producer order: a renderer consuming
-- the first zero cannot make the notification loop emit a false ready message.
ItemRack.ObserveItemCooldown("310:exact",310,0,0,1,"button")
ItemRackUser.ItemsUsed[310] = 5
ItemRack.ItemsUsedCooldownGeneration[310] = ItemRack.CooldownObservations.generation
itemCooldowns[310] = { 0,0,1 }
ItemRack.CooldownUpdate()
check(ItemRackUser.ItemsUsed[310] == nil and #notifications == 0,
  "renderer-first arena reset must retire notification tracking silently")

now = 304
ItemRack.ObserveItemCooldown("300:exact",300,304,90,1,"verified-use")
slotCooldown = { 290,120,1 }
ItemRack.UpdateButtonCooldowns()
check(_G.ItemRackButton13Cooldown.last.start == 304,
  "late pre-entry active sample must preserve the post-entry authority")
slotCooldown = { 304.1,4,0 }
ItemRack.UpdateButtonCooldowns()
check(_G.ItemRackButton13Cooldown.last.start == 304
  and _G.ItemRackButton13Cooldown.last.duration == 90,
  "post-entry cooldown must survive a disabled control-loss sample")

now = 305
itemCooldowns[300] = { 304.1,4,0 }
local remaining = ItemRack.GetItemCooldownLeft("300:exact")
check(remaining and math.abs(remaining-89) < 0.01,
  "queue readiness must consume the guarded shared cooldown")
itemCooldowns[400] = { 305,4,0 }
check(ItemRack.GetItemCooldownLeft("400:exact") == nil,
  "queue must hold on an uncorroborated positive disabled sample")
itemCooldowns[401] = { 0,0,0 }
check(ItemRack.GetItemCooldownLeft("401:exact") == 0,
  "passive zero/disabled item must remain a known-ready candidate")

instanceType = nil
ItemRack.UpdateArenaVisibilityState()
check(ItemRack.CooldownObservations.arena == nil
  and ItemRack.GetObservedItemCooldown("300:exact",300) ~= nil,
  "leaving arena must retain genuine current-generation cooldowns")

-- False zeros cannot announce ready. Expiration plus a readable zero can.
now = 400
ItemRack.ObserveItemCooldown(500,500,395,10,1,"verified-use")
ItemRackUser.ItemsUsed[500] = 5
ItemRack.ItemsUsedCooldownGeneration[500] = ItemRack.CooldownObservations.generation
itemCooldowns[500] = { 0,0,1 }
ItemRack.CooldownUpdate()
check(ItemRackUser.ItemsUsed[500] == 5 and #notifications == 0,
  "guarded false zero must not announce readiness")
now = 406
ItemRack.CooldownUpdate()
check(ItemRackUser.ItemsUsed[500] == nil and #notifications == 1
  and notifications[1] == "Item500 ready!",
  "expired authority must permit exactly one ready notification")

print(string.format("[COOLDOWN INTEGRATION LUA] %d renderer, arena, queue, and notification checks passed.",checks))
`, 'cooldown-integration');
