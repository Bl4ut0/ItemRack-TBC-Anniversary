const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

/*
 * Production-Lua contract test for the event-frame reducer.
 *
 * Expected production module: ItemRack/ItemRackEventState.lua
 * Expected API:
 *
 *   ItemRack.EventFrames.NewState() -> state
 *
 *   ItemRack.EventFrames.Activate(state, {
 *     eventName = string,
 *     eventGeneration = number,
 *     setName = string,
 *     slots = { [equipmentSlot] = exactItemIdentity },
 *     observed = { [equipmentSlot] = exactItemIdentity }
 *   }) -> {
 *     changed = boolean,
 *     frameId = number,
 *     targets = { [equipmentSlot] = exactItemIdentity }
 *   }
 *
 *   ItemRack.EventFrames.Pop(state, eventName, eventGeneration) -> {
 *     removed = boolean,
 *     targets = { [equipmentSlot] = exactItemIdentity }
 *   }
 *
 * State is intentionally inspectable and has this minimal canonical shape:
 *
 *   state.revision
 *   state.order = { frameId, ... }
 *   state.byEvent[eventName] = frameId
 *   state.frames[frameId].slots[slot] = { target = id, prior = id }
 *
 * `targets` contains only slots whose effective target changed. A buried pop
 * transfers its prior value to the nearest higher frame that owns the slot;
 * it must not emit a target that overwrites that higher owner.
 */

const repoRoot = path.resolve(__dirname, '..');
const moduleRelativePath = path.join('ItemRack', 'ItemRackEventState.lua');
const modulePath = path.join(repoRoot, moduleRelativePath);

if (!fs.existsSync(modulePath)) {
  console.error(
    `[EVENT FRAME LUA] Missing production reducer: ${moduleRelativePath}. ` +
      'Implement ItemRack.EventFrames.NewState, Activate, and Pop using the API contract documented in this test.'
  );
  process.exit(1);
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function luaError(prefix) {
  const value = lua.lua_tostring(L, -1);
  const message = value ? to_jsstring(value) : 'unknown Lua error';
  lua.lua_pop(L, 1);
  throw new Error(`${prefix}: ${message}`);
}

function runString(source, label) {
  const loadStatus = lauxlib.luaL_loadstring(L, to_luastring(source));
  if (loadStatus !== lua.LUA_OK) {
    luaError(`Unable to compile ${label}`);
  }
  const callStatus = lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0);
  if (callStatus !== lua.LUA_OK) {
    luaError(`Unable to execute ${label}`);
  }
}

runString('ItemRack = ItemRack or {}', 'event-frame prelude');

const loadStatus = lauxlib.luaL_loadfile(L, to_luastring(modulePath));
if (loadStatus !== lua.LUA_OK) {
  luaError(`Unable to load ${moduleRelativePath}`);
}
const moduleStatus = lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0);
if (moduleStatus !== lua.LUA_OK) {
  luaError(`Unable to initialize ${moduleRelativePath}`);
}

const fixtures = String.raw`
local API = ItemRack and ItemRack.EventFrames
assert(type(API) == "table", "ItemRack.EventFrames table is missing")
assert(type(API.NewState) == "function", "ItemRack.EventFrames.NewState is missing")
assert(type(API.Activate) == "function", "ItemRack.EventFrames.Activate is missing")
assert(type(API.Pop) == "function", "ItemRack.EventFrames.Pop is missing")
assert(type(API.MigrateLegacy) == "function", "ItemRack.EventFrames.MigrateLegacy is missing")

local checks = 0

local function check(condition, message)
  if not condition then
    error(message, 2)
  end
  checks = checks + 1
end

local function countEntries(tbl)
  local count = 0
  for _ in pairs(tbl or {}) do
    count = count + 1
  end
  return count
end

local function newState()
  local state = API.NewState()
  check(type(state) == "table", "NewState must return a table")
  check(type(state.order) == "table", "NewState must initialize state.order")
  check(type(state.byEvent) == "table", "NewState must initialize state.byEvent")
  check(type(state.frames) == "table", "NewState must initialize state.frames")
  check(type(state.revision) == "number", "NewState must initialize a numeric revision")
  return state
end

local function activate(state, eventName, generation, setName, slots, observed)
  local result = API.Activate(state, {
    eventName = eventName,
    eventGeneration = generation,
    setName = setName,
    slots = slots,
    observed = observed,
  })
  check(type(result) == "table", "Activate must return a result table for " .. eventName)
  check(result.changed == true, "Activate must report a new frame for " .. eventName)
  check(type(result.frameId) == "number", "Activate must return a numeric frameId for " .. eventName)
  check(state.byEvent[eventName] == result.frameId, "Activate must index the frame by event name")
  check(state.frames[result.frameId] ~= nil, "Activate must store the returned frame")
  check(type(result.targets) == "table", "Activate must return a targets table")
  return result
end

local function pop(state, eventName, generation)
  local result = API.Pop(state, eventName, generation)
  check(type(result) == "table", "Pop must return a result table for " .. eventName)
  check(type(result.targets) == "table", "Pop must always return a targets table")
  return result
end

-- Base -> X -> Y. X owns slots 13 and 14; Y covers only slot 14. Removing
-- buried X must restore unowned slot 13, leave visible Y in slot 14, and make
-- Y restore B14 later instead of the removed X14.
do
  local state = newState()
  local x = activate(state, "XEvent", 1, "XSet", {
    [13] = "X13",
    [14] = "X14",
  }, {
    [13] = "B13",
    [14] = "B14",
  })
  local y = activate(state, "YEvent", 1, "YSet", {
    [14] = "Y14",
  }, {
    [14] = "X14",
  })

  check(state.frames[x.frameId].slots[13].prior == "B13", "X slot 13 must capture its observed prior")
  check(state.frames[y.frameId].slots[14].prior == "X14", "Y slot 14 must inherit X as its logical prior")

  local removeX = pop(state, "XEvent", 1)
  check(removeX.removed == true, "A buried owned X frame must be removed")
  check(removeX.targets[13] == "B13", "Removing buried X must restore its unowned slot 13")
  check(removeX.targets[14] == nil, "Removing buried X must not overwrite Y-owned slot 14")
  check(state.frames[y.frameId].slots[14].prior == "B14", "Y must inherit X's prior for overlapping slot 14")
  check(state.byEvent.XEvent == nil and #state.order == 1, "Only Y may remain after buried X removal")

  local removeY = pop(state, "YEvent", 1)
  check(removeY.removed == true, "The remaining Y frame must be removable")
  check(removeY.targets[14] == "B14", "Removing Y after the splice must restore base B14")
  check(#state.order == 0 and countEntries(state.frames) == 0, "Buried-removal fixture must end with no frames")
end

-- Two logical owners intentionally map to one physical set. Removing either
-- owner must retain the shared target until the final owner leaves.
do
  local state = newState()
  local ghostwolf = activate(state, "Ghostwolf", 1, "ZoomZoom", {
    [13] = "Crop",
  }, {
    [13] = "BaseTrinket",
  })
  local mounted = activate(state, "Mounted", 1, "ZoomZoom", {
    [13] = "Crop",
  }, {
    [13] = "Crop",
  })

  local removeGhostwolf = pop(state, "Ghostwolf", 1)
  check(removeGhostwolf.removed == true, "Ghostwolf must own an independent frame")
  check(removeGhostwolf.targets[13] == nil, "Removing one shared-set owner must not restore gear")
  check(state.frames[mounted.frameId].slots[13].prior == "BaseTrinket", "The remaining shared owner must inherit base history")
  check(state.byEvent.Mounted == mounted.frameId and state.frames[ghostwolf.frameId] == nil, "Mounted must remain the sole owner")

  local removeMounted = pop(state, "Mounted", 1)
  check(removeMounted.removed == true, "The final shared-set owner must be removable")
  check(removeMounted.targets[13] == "BaseTrinket", "The final shared-set owner must restore base gear")
end

-- Repeated physical set names at non-adjacent logical depths must retain
-- independent history: Base -> X(lower) -> Y -> X(upper).
do
  local state = newState()
  local lowerX = activate(state, "LowerX", 1, "XSet", {
    [13] = "X",
  }, {
    [13] = "Base",
  })
  local middleY = activate(state, "MiddleY", 1, "YSet", {
    [13] = "Y",
  }, {
    [13] = "X",
  })
  local upperX = activate(state, "UpperX", 1, "XSet", {
    [13] = "X",
  }, {
    [13] = "Y",
  })

  check(lowerX.frameId ~= upperX.frameId, "Repeated set names must still create distinct logical frames")
  check(state.frames[upperX.frameId].slots[13].prior == "Y", "Upper X must retain Y as its own prior")

  local removeMiddle = pop(state, "MiddleY", 1)
  check(removeMiddle.removed == true, "Buried Y must be removable from X -> Y -> X")
  check(removeMiddle.targets[13] == nil, "Removing buried Y must not overwrite upper X")
  check(state.frames[upperX.frameId].slots[13].prior == "X", "Upper X must inherit lower X after Y is removed")

  local removeUpper = pop(state, "UpperX", 1)
  check(removeUpper.removed == true, "Upper X must be removable")
  check(removeUpper.targets[13] == nil, "Removing upper X must not submit a no-op over identical lower X")
  check(state.byEvent.LowerX == lowerX.frameId, "Lower X must remain independently owned")

  local removeLower = pop(state, "LowerX", 1)
  check(removeLower.removed == true, "Lower X must be removable")
  check(removeLower.targets[13] == "Base", "Final X removal must restore Base")
  check(#state.order == 0, "X -> Y -> X fixture must end with an empty frame order")
end

-- A stale duplicate pop, including a pop after a completed removal, must be a
-- total no-op: no revision, ownership, frame, ordering, or target changes.
do
  local state = newState()
  activate(state, "Ghostwolf", 7, "ZoomZoom", {
    [14] = "Crop",
  }, {
    [14] = "BaseTrinket",
  })
  local first = pop(state, "Ghostwolf", 7)
  check(first.removed == true and first.targets[14] == "BaseTrinket", "The first owned pop must restore normally")

  local revisionBefore = state.revision
  local orderBefore = #state.order
  local frameCountBefore = countEntries(state.frames)
  local ownerBefore = state.byEvent.Ghostwolf
  local second = pop(state, "Ghostwolf", 7)

  check(second.removed == false, "A stale second pop must report that it removed nothing")
  check(countEntries(second.targets) == 0, "A stale second pop must emit no targets")
  check(state.revision == revisionBefore, "A stale second pop must not increment the plan revision")
  check(#state.order == orderBefore, "A stale second pop must not alter frame order")
  check(countEntries(state.frames) == frameCountBefore, "A stale second pop must not alter frames")
  check(state.byEvent.Ghostwolf == ownerBefore, "A stale second pop must not alter ownership lookup")
end

-- Entering a Zone while a mount frame is visible inserts the Zone beneath the
-- mount. Overlapping mount gear stays visible; disjoint Zone slots may apply,
-- and the mount's eventual exit reveals the Zone rather than stale base gear.
do
  local state = newState()
  local mount = activate(state, "Mounted", 1, "MountSet", {
    [13] = "Mount13",
  }, {
    [13] = "Base13",
  })
  local zoneResult = API.Activate(state, {
    eventName = "City",
    eventGeneration = 1,
    setName = "CitySet",
    beforeFrameId = mount.frameId,
    slots = { [13] = "City13", [14] = "City14" },
    observed = { [13] = "Mount13", [14] = "Base14" },
  })
  check(zoneResult.changed == true, "underlying Zone activation must create a frame")
  local zoneFrame = state.frames[zoneResult.frameId]
  check(state.order[1] == zoneResult.frameId and state.order[2] == mount.frameId, "Zone frame must be ordered beneath Mounted")
  check(zoneFrame.slots[13].prior == "Base13", "underlying Zone must inherit the mount frame's base prior")
  check(state.frames[mount.frameId].slots[13].prior == "City13", "mount must restore the newly inserted Zone target")
  check(zoneResult.targets[13] == nil and zoneResult.targets[14] == "City14", "Zone insertion must touch only slots not covered by Mounted")

  local removeMount = pop(state, "Mounted", 1)
  check(removeMount.targets[13] == "City13", "dismount must reveal the underlying Zone target")
  local removeZone = pop(state, "City", 1)
  check(removeZone.targets[13] == "Base13" and removeZone.targets[14] == "Base14", "leaving Zone must restore original base slots")
end

-- A v4.30-v4.42 EventStack plus per-set old history can be translated into
-- independent frames without replaying any equipment. Buried removal must use
-- the preserved legacy base, not the gear observed at reload.
do
  local state,report = API.MigrateLegacy({
    eventStack={ "Lower", "Upper" },
    eventSets={ Lower="LowerSet", Upper="UpperSet" },
    events={ Lower={ Type="Zone", Unequip=1 }, Upper={ Type="Buff", Unequip=1 } },
    enabled={ Lower=1, Upper=1 },
    sets={
      LowerSet={ equip={ [13]="Lower13", [14]="Lower14" }, old={ [13]="Base13", [14]="Base14" } },
      UpperSet={ equip={ [14]="Upper14" }, old={ [14]="Lower14" }, oldset="LowerSet" },
    },
    observed={ [13]="Lower13", [14]="Upper14" },
  })
  check(report.source == "event_stack" and report.framesMigrated == 2,
    "ordered legacy EventStack data must migrate both frames")
  check(report.slotsMigrated == 3 and report.slotsWithoutPrior == 0,
    "all restorable legacy slots must retain explicit ownership")
  check(API.EffectiveTarget(state,13) == "Lower13" and API.EffectiveTarget(state,14) == "Upper14",
    "migration must describe the already-visible effective gear")
  local removeLower = API.Pop(state,"Lower")
  check(removeLower.targets[13] == "Base13" and removeLower.targets[14] == nil,
    "migrated buried removal must not overwrite a higher frame")
  local upper = state.frames[state.byEvent.Upper]
  check(upper.slots[14].prior == "Base14",
    "the higher migrated frame must inherit the removed legacy base")
  local removeUpper = API.Pop(state,"Upper")
  check(removeUpper.targets[14] == "Base14",
    "the final migrated frame must restore the pre-reload base")
end

-- Two event names mapped to one legacy physical set still become independent
-- owners. The shared set's single old snapshot is sufficient because the
-- higher frame inherits the lower target.
do
  local state,report = API.MigrateLegacy({
    eventStack={ "Ghostwolf", "Mounted" },
    eventSets={ Ghostwolf="Travel", Mounted="Travel" },
    events={ Ghostwolf={ Type="Stance", Unequip=1 }, Mounted={ Type="Buff", Unequip=1 } },
    enabled={ Ghostwolf=1, Mounted=1 },
    sets={ Travel={ equip={ [13]="Crop" }, old={ [13]="Base" } } },
    observed={ [13]="Crop" },
  })
  check(report.framesMigrated == 2 and state.byEvent.Ghostwolf ~= state.byEvent.Mounted,
    "shared-set legacy events must receive separate frame identities")
  check(API.Pop(state,"Ghostwolf").targets[13] == nil,
    "removing one migrated shared-set owner must keep shared gear visible")
  check(API.Pop(state,"Mounted").targets[13] == "Base",
    "the final migrated shared-set owner must restore legacy base gear")
end

-- Physical disagreement is evidence of a newer/manual owner. Retain the frame
-- for logical event projection but release the disputed slot everywhere.
do
  local state,report = API.MigrateLegacy({
    eventStack={ "Mounted" },
    eventSets={ Mounted="Travel" },
    events={ Mounted={ Type="Buff", Unequip=1 } },
    enabled={ Mounted=1 },
    sets={ Travel={ equip={ [13]="Crop" }, old={ [13]="Base" } } },
    observed={ [13]="ManualTrinket" },
  })
  local frame = state.frames[state.byEvent.Mounted]
  check(report.slotsReleasedForMismatch == 1 and frame.slots[13] == nil,
    "mismatched visible gear must release stale migrated slot ownership")
  check(API.Pop(state,"Mounted").targets[13] == nil,
    "a mismatched migrated slot must never restore over manual gear")
end


-- Matching worn gear is not a restoration baseline. If legacy history cannot
-- establish a prior value, leave the slot unowned and disclose the limitation.
do
  local state,report = API.MigrateLegacy({
    eventStack={ "Mounted" },
    eventSets={ Mounted="Travel" },
    events={ Mounted={ Type="Buff", Unequip=1 } },
    enabled={ Mounted=1 },
    sets={ Travel={ equip={ [13]="Crop" }, old={} } },
    observed={ [13]="Crop" },
  })
  check(report.slotsWithoutPrior == 1 and
    state.frames[state.byEvent.Mounted].slots[13] == nil,
    "migration must not invent self-restoration history from currently worn gear")
end

-- Before EventStack existed, a single Active flag is unambiguous. Multiple
-- active flags may migrate only when their targets commute or oldset forms one
-- complete chain; conflicting independent owners remain backed up but unowned.
do
  local state,report = API.MigrateLegacy({
    activeEvents={ Mounted=true },
    eventSets={ Mounted="Travel" },
    events={ Mounted={ Type="Buff", Unequip=1 } },
    enabled={ Mounted=1 },
    sets={ Travel={ equip={ [13]="Crop" }, old={ [13]="Base" } } },
    observed={ [13]="Crop" },
  })
  check(report.source == "single_active_flag" and state.byEvent.Mounted ~= nil,
    "one pre-EventStack Active flag must migrate deterministically")

  state,report = API.MigrateLegacy({
    activeEvents={ Alpha=true, Zulu=true },
    eventSets={ Alpha="AlphaSet", Zulu="ZuluSet" },
    events={ Alpha={ Type="Buff", Unequip=1 }, Zulu={ Type="Zone", Unequip=1 } },
    enabled={ Alpha=1, Zulu=1 },
    sets={
      AlphaSet={ equip={ [13]="A" }, old={ [13]="Base13" } },
      ZuluSet={ equip={ [14]="Z" }, old={ [14]="Base14" } },
    },
    observed={ [13]="A", [14]="Z" },
  })
  check(report.source == "commutative_active_flags" and #state.order == 2,
    "disjoint pre-EventStack Active owners may migrate in stable name order")

  state,report = API.MigrateLegacy({
    activeEvents={ Bottom=true, Top=true },
    eventSets={ Bottom="BottomSet", Top="TopSet" },
    events={ Bottom={ Type="Zone", Unequip=1 }, Top={ Type="Buff", Unequip=1 } },
    enabled={ Bottom=1, Top=1 },
    sets={
      BottomSet={ equip={ [13]="Bottom" }, old={ [13]="Base" } },
      TopSet={ equip={ [13]="Top" }, old={ [13]="Bottom" }, oldset="BottomSet" },
    },
    observed={ [13]="Top" },
  })
  check(report.source == "oldset_chain" and
    state.frames[state.order[1]].eventName == "Bottom" and
    state.frames[state.order[2]].eventName == "Top",
    "a complete legacy oldset chain must recover conflicting Active order")

  state,report = API.MigrateLegacy({
    activeEvents={ Alpha=true, Zulu=true },
    eventSets={ Alpha="AlphaSet", Zulu="ZuluSet" },
    events={ Alpha={ Type="Buff", Unequip=1 }, Zulu={ Type="Zone", Unequip=1 } },
    enabled={ Alpha=1, Zulu=1 },
    sets={
      AlphaSet={ equip={ [13]="A" }, old={ [13]="Base" } },
      ZuluSet={ equip={ [13]="Z" }, old={ [13]="Base" } },
    },
    observed={ [13]="Z" },
  })
  check(report.source == "ambiguous_active_flags" and #state.order == 0,
    "conflicting Active flags without order evidence must fail closed")
  check(report.issues[#report.issues].reason == "ambiguous_active_order",
    "ambiguous legacy ordering must remain explicit in the migration report")
end

print(string.format("[EVENT FRAME LUA] %d production-Lua ownership checks passed.", checks))
`;

runString(fixtures, 'event-frame acceptance fixtures');
