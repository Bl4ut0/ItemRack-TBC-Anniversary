const fs = require('fs');
const { runLua } = require('./lib/lua_harness');

const moduleSource = fs.readFileSync('ItemRack/ItemRackCooldownState.lua', 'utf8');

runLua(String.raw`
local now = 100
function GetTime() return now end
ItemRack = {}
${moduleSource}

local API = ItemRack.CooldownState
local state = API.New()
local checks = 0
local function check(value,message) assert(value,message); checks = checks + 1 end
local function observe(exactID,baseID,start,duration,enable,source)
  return API.Observe(state,{ exactID=exactID, baseID=baseID, start=start,
    duration=duration, enable=enable, source=source, now=now })
end

local active = observe("100:exact",100,95,30,1,"slot")
check(active.active and active.status == "active", "real cooldown must become authoritative")
check(API.Get(state,"100:exact",100,now) == active.record, "exact lookup must return the observation")
check(API.Get(state,nil,100,now) == active.record, "base lookup must bridge a later popup renderer")

local guarded = observe("100:exact",100,0,0,1,"menu")
check(guarded.active and guarded.status == "guarded" and guarded.start == 95,
  "false zero outside an arena must retain the unexpired authority")
now = 126
local expired = observe("100:exact",100,0,0,1,"slot")
check(not expired.active and expired.status == "clear", "expired authority must accept a zero")
check(API.Get(state,"100:exact",100,now) == nil, "expired record must be removed")

-- A button observation remains available while the menu is closed and after
-- the item leaves its equipment slot.
now = 200
active = observe("200:rune:7",200,199,60,1,"slot")
now = 205
guarded = observe("200:rune:7",200,0,0,0,"menu-first-open")
check(guarded.active and guarded.start == 199,
  "first popup open during control loss must reuse the renderer-independent record")
check(API.Get(state,"200:rune:7",200,now) ~= nil,
  "swapping the item out must not erase its identity-keyed cooldown")

-- Arena entry advances a generation. Pre-entry active samples are hidden and
-- cannot be re-cached no matter how late Blizzard publishes the reset.
now = 300
active = observe("300:exact",300,290,120,1,"slot")
local arenaGeneration = API.BeginArena(state,now)
check(API.Get(state,"300:exact",300,now) == nil,
  "pre-arena authority must be invisible immediately at the reset boundary")
now = 300.2
local stale = observe("300:exact",300,290,120,1,"slot")
check(not stale.active and stale.status == "arena_stale_sample",
  "late stale arena sample must not repopulate the new generation")
now = 302
local reset = observe("300:exact",300,0,0,1,"slot")
check(not reset.active and reset.status == "arena_reset" and reset.generation == arenaGeneration,
  "post-entry zero must authoritatively confirm the arena reset")
check(API.Get(state,"300:exact",300,now) == nil, "arena reset must remove prior identity records")

-- A genuine use after entry has a post-boundary start and is accepted. A
-- control-loss sample cannot overwrite it with a synthetic cooldown.
now = 304
active = observe("300:exact",300,304,90,1,"use")
check(active.active and active.record.generation == arenaGeneration,
  "post-entry use must be accepted in the arena generation")
local lateStale = observe("300:exact",300,290,120,1,"late-stale-slot")
check(lateStale.active and lateStale.status == "arena_stale_guarded"
  and lateStale.start == 304,
  "late pre-entry sample must not mask a genuine post-entry cooldown")
local cc = observe("300:exact",300,304.1,4,0,"loss-of-control")
check(cc.active and cc.status == "guarded" and cc.start == 304 and cc.duration == 90,
	"disabled arena observation must not erase a genuine post-entry cooldown")

local firstReset = observe("301:exact",301,0,0,1,"button")
local laterReset = observe("301:exact",301,0,0,1,"notification")
check(firstReset.status == "arena_reset" and laterReset.status == "arena_reset",
  "arena reset must remain visible to every consumer until a genuine use")
local variantReset = observe("302:rune:b",302,0,0,1,"button")
now = 305
local variantActive = observe("302:rune:a",302,305,90,1,"use")
local variantGuard = observe("302:rune:b",302,0,0,0,"menu")
check(variantReset.status == "arena_reset" and variantActive.active
  and variantGuard.active and variantGuard.record == variantActive.record,
  "one exact variant must not leave a tombstone over a same-base genuine use")

API.EndArena(state)
now = 400
local first = observe("400:a",400,399,30,1,"slot13")
now = 401
local second = observe("400:b",400,400,60,1,"slot14")
check(API.Get(state,"400:a",400,now) == first.record, "exact duplicate identity must remain addressable")
check(API.Get(state,nil,400,now) == second.record, "base fallback must select the newest duplicate observation")

local priorGeneration = state.generation
API.Reset(state)
check(state.generation == priorGeneration + 1 and not next(state.records) and not next(state.byBase),
  "hard reset must advance generation and clear both indexes")

print(string.format("[COOLDOWN STATE LUA] %d authority and arena checks passed.",checks))
`, 'cooldown-state');
