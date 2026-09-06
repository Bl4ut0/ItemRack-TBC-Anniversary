const fs = require('fs');
const { runLua } = require('./lib/lua_harness');

const events = fs.readFileSync('ItemRack/ItemRackEvents.lua', 'utf8');

runLua(String.raw`
local notices = {}
local popupName,popupText

function UnitClass() return "Shaman","SHAMAN" end
function IsMounted() return false end
function UnitOnTaxi() return false end
function GetUnitSpeed() return 0 end
function IsInInstance() return false,nil end
function GetShapeshiftForm() return 0 end
function GetRealZoneText() return "" end
function GetSubZoneText() return "" end
function InCombatLockdown() return false end
function GetTime() return 0 end
C_AddOns, C_Spell, C_Talent = nil,nil,nil
C_Container = { GetContainerNumSlots=function() return 16 end }
StaticPopupDialogs = {}
function StaticPopup_Show(name,text)
  popupName,popupText = name,text
  return {}
end

ItemRack = {
  Debug=function() end,
  Print=function(message) table.insert(notices,message) end,
  IsAutomaticSwapBlocked=function() return false end,
}
ItemRackUser = {
  EnableEvents="ON",
  Events={
    Enabled={ Trusted=true, Injected=true },
    Set={},
    ScriptApprovals={
      Trusted={
        Event="Trusted",
        Trigger="PLAYER_TARGET_CHANGED",
        Script="TrustedRuns = (TrustedRuns or 0) + 1",
        ApprovedBy="prompt",
      },
    },
  },
  Sets={},
}
ItemRackEvents = {
  Trusted={
    Type="Script",
    Trigger="PLAYER_TARGET_CHANGED",
    Script="TrustedRuns = (TrustedRuns or 0) + 1",
  },
  Injected={
    Type="Script",
    Trigger="PLAYER_TARGET_CHANGED",
    Script="InjectedRuns = (InjectedRuns or 0) + 1",
  },
}

${events}

local checks = 0
local function check(value,message) assert(value,message); checks = checks + 1 end

local approved,source = ItemRack.IsScriptEventApproved("Trusted")
check(approved and source == "prompt", "an exact prompted approval must restore runtime trust")
approved,source = ItemRack.IsScriptEventApproved("Injected")
check(not approved and source == "player approval required", "an injected script must start unapproved")

ItemRack.ProcessingFrameOnEvent(nil,"PLAYER_TARGET_CHANGED")
check(TrustedRuns == 1, "an approved script must execute for its registered trigger")
check(InjectedRuns == nil and ItemRackUser.Events.Enabled.Injected == nil,
  "dispatch must disable an unapproved script without executing it")

ItemRackEvents.Trusted.Script = "TrustedRuns = (TrustedRuns or 0) + 100"
ItemRackUser.Events.Enabled.Trusted = true
ItemRack.ProcessingFrameOnEvent(nil,"PLAYER_TARGET_CHANGED")
check(TrustedRuns == 1 and ItemRackUser.Events.Enabled.Trusted == nil,
  "changing approved source must invalidate approval before compilation")
check(ItemRackUser.Events.ScriptApprovals.Trusted.Script == "TrustedRuns = (TrustedRuns or 0) + 1",
  "a blocked mutation must preserve the last approved source for rollback")
local result,reason = ItemRack.RequestScriptEventApproval("Trusted",true)
check(not result and reason == "approval pending", "an external change must require a prompt")
StaticPopupDialogs.ITEMRACK_APPROVE_SCRIPT_EVENT.OnCancel()
check(ItemRackEvents.Trusted.Script == "TrustedRuns = (TrustedRuns or 0) + 1"
  and ItemRackUser.Events.Enabled.Trusted == nil,
  "rejecting external changes must restore the last approved version disabled")

ItemRackEvents.Race = {
  Type="Script",
  Trigger="PLAYER_TARGET_CHANGED",
  Script="RaceRuns = true",
}
result,reason = ItemRack.RequestScriptEventApproval("Race",true)
check(not result and reason == "approval pending", "a valid script must wait for approval")
ItemRackEvents.Race.Script = "RaceRuns = 'changed'"
StaticPopupDialogs.ITEMRACK_APPROVE_SCRIPT_EVENT.OnAccept()
approved = ItemRack.IsScriptEventApproved("Race")
check(not approved and ItemRackEvents.Race == nil and ItemRackUser.Events.Enabled.Race == nil,
  "a new script changed while its prompt is open must be removed")

ItemRackEvents.Pending = {
  Type="Script",
  Trigger="PLAYER_TARGET_CHANGED",
  Script="PendingRuns = (PendingRuns or 0) + 1",
}
result,reason = ItemRack.RequestScriptEventApproval("Pending",true)
check(not result and reason == "approval pending" and popupName == "ITEMRACK_APPROVE_SCRIPT_EVENT",
  "a valid custom script must require the ItemRack approval prompt")
check(popupText:match("arbitrary Lua") and popupText:match("Pending"),
  "the approval prompt must identify the risk and event")
check(ItemRackUser.Events.Enabled.Pending == nil,
  "a pending approval must not enable the script")
StaticPopupDialogs.ITEMRACK_APPROVE_SCRIPT_EVENT.OnAccept()
approved,source = ItemRack.IsScriptEventApproved("Pending")
check(approved and source == "prompt" and ItemRackUser.Events.Enabled.Pending,
  "explicit approval must trust and enable that exact script")
ItemRack.ProcessingFrameOnEvent(nil,"PLAYER_TARGET_CHANGED")
check(PendingRuns == 1, "an explicitly approved script must execute")

ItemRackEvents.Pending.Script = "PendingRuns = (PendingRuns or 0) + 10"
ItemRackUser.Events.Enabled.Pending = true
ItemRack.ProcessingFrameOnEvent(nil,"PLAYER_TARGET_CHANGED")
check(PendingRuns == 1 and ItemRackUser.Events.Enabled.Pending == nil,
  "post-approval source mutation must be fail-closed")
ItemRack.RemoveUnapprovedScriptEvents()
check(ItemRackEvents.Pending.Script == "PendingRuns = (PendingRuns or 0) + 1",
  "logout cleanup must restore approved source over an unapproved mutation")

ItemRackEvents.Interface = {
  Type="Script",
  Trigger="PLAYER_TARGET_CHANGED",
  Script="InterfaceRuns = (InterfaceRuns or 0) + 1",
}
result,reason = ItemRack.ApproveScriptEventFromInterface("Interface")
approved,source = ItemRack.IsScriptEventApproved("Interface")
check(result and reason == "interface" and approved and source == "interface"
  and ItemRackUser.Events.Enabled.Interface,
  "saving through the ItemRack editor must approve and enable valid source without a prompt")
ItemRack.ProcessingFrameOnEvent(nil,"PLAYER_TARGET_CHANGED")
check(InterfaceRuns == 1, "an interface-approved script must execute")

ItemRackEvents.Rejected = {
  Type="Script",
  Trigger="PLAYER_TARGET_CHANGED",
  Script="RejectedRuns = true",
}
result,reason = ItemRack.RequestScriptEventApproval("Rejected",true)
check(not result and reason == "approval pending", "external source must enter the prompt path")
StaticPopupDialogs.ITEMRACK_APPROVE_SCRIPT_EVENT.OnCancel()
check(ItemRackEvents.Rejected == nil and RejectedRuns == nil,
  "rejecting a new external event must remove it before SavedVariables can persist it")

ItemRackEvents.Swimming = {
  Type="Script",
  Trigger=ItemRack.DefaultEvents.Swimming.Trigger,
  Script=ItemRack.DefaultEvents.Swimming.Script,
}
approved,source = ItemRack.IsScriptEventApproved("Swimming")
check(approved and source == "bundled", "an unchanged packaged script may be trusted")
ItemRackEvents.Swimming.Script = ItemRackEvents.Swimming.Script.."\nInjectedRuns = 99"
ItemRack.DefaultEvents.Swimming.Script = ItemRackEvents.Swimming.Script
approved = ItemRack.IsScriptEventApproved("Swimming")
check(not approved, "changing public packaged definitions must not manufacture bundled trust")
ItemRack.RemoveUnapprovedScriptEvents()
check(ItemRackEvents.Swimming.Script == ItemRack.StackedSwimmingScript,
  "cleanup must restore the private packaged source rather than a changed public default")

ItemRackEvents.Invalid = { Type="Script", Trigger="not an event", Script="InvalidRuns = true" }
ItemRackUser.Events.Enabled.Invalid = true
local blocked = ItemRack.ReconcileScriptEventApprovals()
check(blocked == 1 and ItemRackUser.Events.Enabled.Invalid == nil and InvalidRuns == nil,
  "invalid trigger names must be quarantined without execution")
result,reason = ItemRack.RequestScriptEventApproval("Invalid",true)
check(not result and ItemRackEvents.Invalid == nil,
  "an invalid candidate must be removed when it cannot enter either approval path")

ItemRackEvents.TooLarge = {
  Type="Script",
  Trigger="PLAYER_TARGET_CHANGED",
  Script=string.rep("x",4097),
}
result,reason = ItemRack.RequestScriptEventApproval("TooLarge",true)
check(not result and reason:match("4096") and ItemRackEvents.TooLarge == nil,
  "injected scripts larger than the editor limit must be rejected and removed")

ItemRackEvents.SilentInjection = {
  Type="Script",
  Trigger="PLAYER_TARGET_CHANGED",
  Script="SilentRuns = true",
}
local removed = ItemRack.RemoveUnapprovedScriptEvents()
check(removed == 1 and ItemRackEvents.SilentInjection == nil,
  "an unnoticed unapproved event must be removed at the SavedVariables boundary")

print(string.format("[SCRIPT EVENT APPROVAL LUA] %d trust-boundary checks passed.",checks))
`, 'script-event-approval');
