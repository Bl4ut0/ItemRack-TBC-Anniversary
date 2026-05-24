local addonName, addon = ...
_G[addonName] = addon

local _

-- Blizzard Keybinding UI localization strings
-- These globals provide the human-readable names displayed in ESC > Keybindings > AddOns > ItemRack
-- CLICK bindings require _G["BINDING_NAME_<full action string>"] format (spaces/colons included)
BINDING_HEADER_ITEMRACK = "ItemRack"
_G["BINDING_NAME_CLICK ItemRackButton0:LeftButton"]  = "Ammo (Slot 0)"
_G["BINDING_NAME_CLICK ItemRackButton1:LeftButton"]  = "Head (Slot 1)"
_G["BINDING_NAME_CLICK ItemRackButton2:LeftButton"]  = "Neck (Slot 2)"
_G["BINDING_NAME_CLICK ItemRackButton3:LeftButton"]  = "Shoulder (Slot 3)"
_G["BINDING_NAME_CLICK ItemRackButton4:LeftButton"]  = "Shirt (Slot 4)"
_G["BINDING_NAME_CLICK ItemRackButton5:LeftButton"]  = "Chest / Robe (Slot 5)"
_G["BINDING_NAME_CLICK ItemRackButton6:LeftButton"]  = "Waist (Slot 6)"
_G["BINDING_NAME_CLICK ItemRackButton7:LeftButton"]  = "Legs (Slot 7)"
_G["BINDING_NAME_CLICK ItemRackButton8:LeftButton"]  = "Feet (Slot 8)"
_G["BINDING_NAME_CLICK ItemRackButton9:LeftButton"]  = "Wrist (Slot 9)"
_G["BINDING_NAME_CLICK ItemRackButton10:LeftButton"] = "Hands (Slot 10)"
_G["BINDING_NAME_CLICK ItemRackButton11:LeftButton"] = "Finger 1 (Slot 11)"
_G["BINDING_NAME_CLICK ItemRackButton12:LeftButton"] = "Finger 2 (Slot 12)"
_G["BINDING_NAME_CLICK ItemRackButton13:LeftButton"] = "Trinket 1 (Slot 13)"
_G["BINDING_NAME_CLICK ItemRackButton14:LeftButton"] = "Trinket 2 (Slot 14)"
_G["BINDING_NAME_CLICK ItemRackButton15:LeftButton"] = "Back / Cloak (Slot 15)"
_G["BINDING_NAME_CLICK ItemRackButton16:LeftButton"] = "Main Hand / Two-Hand (Slot 16)"
_G["BINDING_NAME_CLICK ItemRackButton17:LeftButton"] = "Off Hand / Shield / Held In Off-hand (Slot 17)"
_G["BINDING_NAME_CLICK ItemRackButton18:LeftButton"] = "Ranged / Wand / Thrown / Relic (Slot 18)"
_G["BINDING_NAME_CLICK ItemRackButton19:LeftButton"] = "Tabard (Slot 19)"

-- Compatibility shims for addon management APIs (moved to C_AddOns in TBC 2.5.5+)
local GetAddOnMetadata = GetAddOnMetadata or (C_AddOns and C_AddOns.GetAddOnMetadata)
local EnableAddOn = EnableAddOn or (C_AddOns and C_AddOns.EnableAddOn)
local DisableAddOn = DisableAddOn or (C_AddOns and C_AddOns.DisableAddOn)
local LoadAddOn = LoadAddOn or (C_AddOns and C_AddOns.LoadAddOn)
local IsAddOnLoaded = IsAddOnLoaded or (C_AddOns and C_AddOns.IsAddOnLoaded)
local GetAddOnInfo = GetAddOnInfo or (C_AddOns and C_AddOns.GetAddOnInfo)
local GetNumAddOns = GetNumAddOns or (C_AddOns and C_AddOns.GetNumAddOns)

local wowver, wowbuild, wowbuilddate, wowtoc = GetBuildInfo()
ItemRack.Version = GetAddOnMetadata(addonName, "Version")
ItemRack.BuildID = "Dev"

-- Global Debug System
-- Usage: ItemRack.Debug("Queue", "some message", someVar)
-- Enable:  /script ItemRack.DebugTags.Queue = true
-- Disable: /script ItemRack.DebugTags.Queue = false
-- Enable all: /script ItemRack.DebugAll = true
ItemRack.DebugTags = {} -- per-tag toggles, e.g. { Queue = true, Events = true, UI = true, Combat = true }
ItemRack.DebugAll = false -- master override to enable all tags
ItemRack.DebugChat = false -- whether to print debug messages to the chat frame

function ItemRack.Debug(tag, ...)
	if not ItemRack.DebugAll and not ItemRack.DebugTags[tag] then return end
	if ItemRack.DebugChat then
		local text = "|cff00ff00[IR-" .. tag .. "]|r"
		for i=1, select("#", ...) do
			local val = select(i, ...)
			text = text .. " " .. tostring(val)
		end
		ItemRack.Print(text)
	end
	if ItemRack.DebugAll or ItemRack.DebugTags[tag] then
		if not ItemRack.LogBuffer then ItemRack.LogBuffer = {} end
		local text = "[IR-" .. tag .. "]"
		for i=1, select("#", ...) do
			local val = select(i, ...)
			text = text .. " " .. tostring(val)
		end
		table.insert(ItemRack.LogBuffer, date("[%H:%M:%S] ") .. text)
		if #ItemRack.LogBuffer > 5000 then table.remove(ItemRack.LogBuffer, 1) end
	end
end

function ItemRack.PrintDebugStatus()
	local states = {}
	local sortedTags = { "Events", "Equip", "Queue", "CombatQueue", "API", "UI", "Combat" }
	for _, tag in ipairs(sortedTags) do
		local state = ItemRack.DebugTags[tag] and "|cff00ff00ON|r" or "|cffff0000OFF|r"
		table.insert(states, tag .. "=" .. state)
	end
	ItemRack.Print("Debug Status: MasterAll=" .. (ItemRack.DebugAll and "|cff00ff00ON|r" or "|cffff0000OFF|r") .. ", Chat=" .. (ItemRack.DebugChat and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
	ItemRack.Print("Layers: " .. table.concat(states, ", "))
end

-- by Mikinho - Fix for latest update for Classic Era/SoD v11504
local GetMouseFocus = GetMouseFocus
if not GetMouseFocus and GetMouseFoci then
    local GetMouseFoci = GetMouseFoci
          GetMouseFocus = function()
          return GetMouseFoci()[1]
      end
end


-- Compatibility shim for CastingInfo/ChannelInfo (moved to UnitCastingInfo/UnitChannelInfo in some versions)
local CastingInfo = CastingInfo or function() return UnitCastingInfo("player") end
local ChannelInfo = ChannelInfo or function() return UnitChannelInfo("player") end

-- Compatibility shims for Talent APIs (Modern/Cata+ uses C_SpecializationInfo namespace)
-- These MUST be global (not local) so other ItemRack files can access them
if not GetActiveTalentGroup and C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
	GetActiveTalentGroup = C_SpecializationInfo.GetActiveSpecGroup
end
if not SetActiveTalentGroup and C_SpecializationInfo and C_SpecializationInfo.SetActiveSpecGroup then
	SetActiveTalentGroup = C_SpecializationInfo.SetActiveSpecGroup
end
if not GetNumTalentGroups and C_SpecializationInfo and C_SpecializationInfo.GetNumSpecGroups then
	GetNumTalentGroups = C_SpecializationInfo.GetNumSpecGroups
end

-- Compatibility shim for AuraUtil.FindAuraByName (may not exist in TBC 2.5.5)
if not AuraUtil or not AuraUtil.FindAuraByName then
	AuraUtil = AuraUtil or {}
	AuraUtil.FindAuraByName = function(name, unit, filter)
		for i = 1, 40 do
			local buffName = UnitBuff(unit, i, filter)
			if not buffName then break end
			if buffName == name then return buffName end
		end
		for i = 1, 40 do
			local debuffName = UnitDebuff(unit, i, filter)
			if not debuffName then break end
			if debuffName == name then return debuffName end
		end
		return nil
	end
end

-- Compatibility shims for Item APIs (may not have globals if deprecation fallbacks disabled)
local GetItemInfo = _G.GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemCount = _G.GetItemCount or (C_Item and C_Item.GetItemCount)

function ItemRack.IsClassic()
	-- Classic Era: TOC version 10000-19999 or project ID
	if wowtoc >= 10000 and wowtoc < 20000 then
		return true
	end
	return WOW_PROJECT_CLASSIC and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
end

function ItemRack.IsBCC()
	-- TBC 2.5.5 Anniversary Edition: check TOC version (20000-29999) or project ID
	if wowtoc >= 20000 and wowtoc < 30000 then
		return true
	end
	return WOW_PROJECT_BURNING_CRUSADE_CLASSIC and WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
end

function ItemRack.IsWrath()
	-- WotLK: TOC version 30000-39999
	if wowtoc >= 30000 and wowtoc < 40000 then
		return true
	end
	return WOW_PROJECT_WRATH_CLASSIC and WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC
end

function ItemRack.IsCata()
	return wowtoc >= 40000 and wowtoc < 50000
end

-- [[ Season of Discovery Runes ]]
function ItemRack.IsEngravingActive()
	return C_Engraving and C_Engraving.IsEngravingEnabled()
end

do
	if ItemRack.IsEngravingActive() then
		function ItemRack.AppendRuneID(bag, slot)
			if slot then
				if C_Engraving.IsInventorySlotEngravable(bag, slot) then
					local rune_info = C_Engraving.GetRuneForInventorySlot(bag, slot)
					if rune_info then
						return ":runeid:"..tostring(rune_info.skillLineAbilityID)
					else
						return ":runeid:0"
					end
				else
					return ""
				end
			else
				if C_Engraving.IsEquipmentSlotEngravable(bag) then
					local rune_info = C_Engraving.GetRuneForEquipmentSlot(bag)
					if rune_info then
						return ":runeid:"..tostring(rune_info.skillLineAbilityID)
					else
						return ":runeid:0"
					end
				else
					return ""
				end
			end
		end
	end
end

local GetContainerNumSlots, GetContainerItemLink, GetContainerItemID, GetContainerItemCooldown, GetContainerItemInfo, GetItemCooldown, PickupContainerItem, ContainerIDToInventoryID
if C_Container then
	GetContainerNumSlots = C_Container.GetContainerNumSlots
	GetContainerItemLink = C_Container.GetContainerItemLink
	GetContainerItemID = C_Container.GetContainerItemID
	GetContainerItemCooldown = C_Container.GetContainerItemCooldown
	GetItemCooldown = C_Container.GetItemCooldown
	PickupContainerItem = C_Container.PickupContainerItem
	ContainerIDToInventoryID = C_Container.ContainerIDToInventoryID
	GetContainerItemInfo = function(bag, slot)
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info then
			return info.iconFileID, info.stackCount, info.isLocked, info.quality, info.isReadable, info.hasLoot, info.hyperlink, info.isFiltered, info.hasNoValue, info.itemID, info.isBound
		else
			return
		end
	end
else
	GetContainerNumSlots, GetContainerItemLink, GetContainerItemID, GetContainerItemCooldown, GetContainerItemInfo, GetItemCooldown, PickupContainerItem, ContainerIDToInventoryID =
	_G.GetContainerNumSlots, _G.GetContainerItemLink, _G.GetContainerItemID, _G.GetContainerItemCooldown, _G.GetContainerItemInfo, _G.GetItemCooldown, _G.PickupContainerItem, _G.ContainerIDToInventoryID
end

local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

ItemRackUser = {
	Sets = {}, -- user's sets
	ItemsUsed = {}, -- items that have been used (for notify purposes)
	Hidden = {}, -- items the user chooses to hide in menus
	Queues = {}, -- item auto queue sorts
	QueuesEnabled = {}, -- which queues are enabled
	Locked = "OFF", -- buttons locked
	EnableEvents = "ON", -- whether all events enabled
	EnableQueues = "ON", -- whether all auto queues enabled
	EnablePerSetQueues = "OFF",
	EnableQueueContextCheck = "ON",
	ButtonSpacing = 4, -- padding between docked buttons
	Alpha = 1, -- alpha of buttons
	MainScale = 1, -- scale of the dockable buttons
	MenuScale = .85, -- scale of the menu in relation to docked buttons
	SetMenuWrap = "OFF", -- whether user defines when to wrap the menu
	SetMenuWrapValue = 3, -- when to wrap the menu if user defined
}

ItemRackSettings = {
	MenuOnShift = "OFF", -- open menus on shift only
	MenuOnRight = "OFF", -- open menus on right-click only
	RightClickUse = "OFF", -- use the item on right-click instead of manually advancing the queue
	HideOOC = "OFF", -- hide dockable buttons when out of combat
	HidePetBattle = "ON", -- hide dockable buttons during pet battles
	HideArena = "OFF", -- hide dockable buttons in arena instances
	Notify = "ON", -- notify when a used item comes off cooldown
	NotifyThirty = "OFF", -- notify when a used item reaches 30 seconds cooldown
	NotifyChatAlso = "OFF", -- send cooldown notifications to chat also
	ShowTooltips = "ON", -- show all itemrack tooltips
	TinyTooltips = "OFF", -- whether to condense tooltips to most important info
	TinyTooltipsQuickAccess = "OFF", -- whether to apply tiny tooltips only to quick access (not character sheet menus)
	TinyTooltipsSubMenusOnly = "OFF", -- whether to restrict tiny tooltips to popup sub-menu items only (not the main slot button)
	DisableTooltipsInCombat = "OFF", -- whether to hide item tooltips on ItemRack menus/buttons during combat
	TooltipFollow = "OFF", -- whether tooltip follows pointer
	CooldownCount = "OFF", -- whether cooldowns displayed numerically over buttons
	LargeNumbers = "OFF", -- whether cooldown numbers displayed in large font
	AllowEmpty = "ON", -- allow empty slot as a choice in menus
	HideTradables = "OFF", -- allow non-soulbound gear to appear in menu
	AllowHidden = "ON", -- allow the ability to hide items/sets in the menu with alt+click
	ShowMinimap = "ON", -- whether to show the minimap button
	TrinketMenuMode = "OFF", -- whether to merge top/bottom trinkets to one menu (leftclick=top,rightclick=bottom)
	AnotherOther = "OFF", -- whether to dock the merged trinket menu to bottom trinket
	EquipToggle = "OFF", -- whether to toggle equipping a set when choosing to equip it
	ShowHotKeys = "OFF", -- show key bindings on dockable buttons
	Cooldown90 = "OFF", -- whether to count cooldown in seconds at 90 instead of 60
	EquipOnSetPick = "OFF", -- whether to equip a set when picked in the set tab of options
	MinimapTooltip = "ON", -- whether to display the minimap button tooltip to explain clicks
	CharacterSheetMenus = "ON", -- whether to display slot menus on mouseover of the character sheet
	LeftSlotsGoRight = "OFF", -- whether left-side character slots dock their menus to the RIGHT instead of left
	RightSlotsGoLeft = "OFF", -- whether right-side character slots dock their menus to the LEFT instead of right
	DisableAltClick = "OFF", -- whether to disable Alt+click from toggling auto queue (to allow self cast through)
	TooltipColorUnEquipped = "OFF", -- whether to highlight unequipped set items in orange
	DisableSwapSound = "OFF", -- whether to silence audio when ItemRack automatically swaps gear
}

ItemRack.NoTitansGrip = {
	["Polearms"] = 1, -- reverted in 3.4.1 to block Polearms from Titan's Grip again
	["Fishing Poles"] = 1,
	["Staves"] = 1
}

ItemRack.Menu = {}
ItemRack.LockList = {} -- index -2 to 11, flag whether item is tagged already for swap
if ItemRack.IsClassic() then
	ItemRack.BankSlots = { -1,5,6,7,8,9,10 }
elseif ItemRack.IsBCC() or ItemRack.IsWrath() or ItemRack.IsCata() then
	ItemRack.BankSlots = { -1,5,6,7,8,9,10,11 }
end
ItemRack.KnownItems = {} -- cache of known item locations for fast lookup

ItemRack.SlotInfo = {
	[0] = { name="AmmoSlot", real="Ammo", INVTYPE_AMMO=1 },
	[1] = { name="HeadSlot", real="Head", INVTYPE_HEAD=1 },
	[2] = { name="NeckSlot", real="Neck", INVTYPE_NECK=1 },
	[3] = { name="ShoulderSlot", real="Shoulder", INVTYPE_SHOULDER=1 },
	[4] = { name="ShirtSlot", real="Shirt", INVTYPE_BODY=1 },
	[5] = { name="ChestSlot", real="Chest", INVTYPE_CHEST=1, INVTYPE_ROBE=1 },
	[6] = { name="WaistSlot", real="Waist", INVTYPE_WAIST=1 },
	[7] = { name="LegsSlot", real="Legs", INVTYPE_LEGS=1 },
	[8] = { name="FeetSlot", real="Feet", INVTYPE_FEET=1 },
	[9] = { name="WristSlot", real="Wrist", INVTYPE_WRIST=1 },
	[10] = { name="HandsSlot", real="Hands", INVTYPE_HAND=1 },
	[11] = { name="Finger0Slot", real="Top Finger", INVTYPE_FINGER=1, other=12 },
	[12] = { name="Finger1Slot", real="Bottom Finger", INVTYPE_FINGER=1, other=11 },
	[13] = { name="Trinket0Slot", real="Top Trinket", INVTYPE_TRINKET=1, other=14 },
	[14] = { name="Trinket1Slot", real="Bottom Trinket", INVTYPE_TRINKET=1, other=13 },
	[15] = { name="BackSlot", real="Cloak", INVTYPE_CLOAK=1 },
	[16] = { name="MainHandSlot", real="Main hand", INVTYPE_WEAPONMAINHAND=1, INVTYPE_2HWEAPON=1, INVTYPE_WEAPON=1, other=17},
	[17] = { name="SecondaryHandSlot", real="Off hand", INVTYPE_WEAPON=1, INVTYPE_WEAPONOFFHAND=1, INVTYPE_SHIELD=1, INVTYPE_HOLDABLE=1, other=16},
	[18] = { name="RangedSlot", real="Ranged", INVTYPE_RANGED=1, INVTYPE_RANGEDRIGHT=1, INVTYPE_THROWN=1, INVTYPE_RELIC=1},
	[19] = { name="TabardSlot", real="Tabard", INVTYPE_TABARD=1 },
}

ItemRack.DockInfo = {  -- docking-dependent values
	LEFT = { xoff=1, yoff=0, menuSide="TOP", menuDir="TOP", orient="VERT", xadd=40, yadd=0 },
	RIGHT = { xoff=-1, yoff=0, menuSide="TOP", menuDir="TOP", orient="VERT", xadd=40, yadd=0 },
	TOP = { xoff=0, yoff=-1, menuSide="LEFT", menuDir="LEFT", orient="HORZ", xadd=0, yadd=40 },
	BOTTOM = { xoff=0, yoff=1, menuSide="LEFT", menuDir="LEFT", orient="HORZ", xadd=0, yadd=40 },
	TOPRIGHTTOPLEFT = { xoff=0, yoff=8,  xdir=1,  ydir=-1, xstart=8,   ystart=-8 },
	BOTTOMRIGHTBOTTOMLEFT = { xoff=0, yoff=-8,  xdir=1,  ydir=1,  xstart=8,   ystart=44 },
	TOPLEFTTOPRIGHT = { xoff=0,  yoff=8,  xdir=-1, ydir=-1, xstart=-44, ystart=-8 },
	BOTTOMLEFTBOTTOMRIGHT = { xoff=0,  yoff=-8,  xdir=-1, ydir=1,  xstart=-44, ystart=44 },
	TOPRIGHTBOTTOMRIGHT = { xoff=8,  yoff=0, xdir=-1, ydir=1,  xstart=-44,  ystart=44 },
	BOTTOMRIGHTTOPRIGHT = { xoff=8,  yoff=0, xdir=-1, ydir=-1, xstart=-44,  ystart=-8 },
	TOPLEFTBOTTOMLEFT =	{ xoff=-8,  yoff=0, xdir=1,  ydir=1,  xstart=8,   ystart=44 },
	BOTTOMLEFTTOPLEFT =	{ xoff=-8,  yoff=0,  xdir=1,  ydir=-1, xstart=8,   ystart=-8 },
}
ItemRack.OppositeSide = { LEFT="RIGHT", RIGHT="LEFT", TOP="BOTTOM", BOTTOM="TOP" }

ItemRack.MenuMouseoverFrames = {PaperDollFrame=1,CharacterTrinket1Slot=1} -- frames besides ItemRackMenuFrame that can keep menu open on mouseover

ItemRack.CombatQueue = {} -- items waiting to swap in
ItemRack.RunAfterCombat = {} -- functions to run when player drops out of combat

-- miscellaneous tooltips ElementName, Line1, Line2
ItemRack.TooltipInfo = {
	{"ItemRackButtonMenuLock","Lock Buttons","Toggle locked state to prevent buttons/menus from moving and to hide borders and control buttons.\n\nHold ALT while you open a menu to access these control buttons while locked."},
	{"ItemRackButtonMenuQueue","Auto Queue","Set up the auto queue for this slot.\n\nAlt+click the slot this menu opened from to toggle its auto queue on/off."},
	{"ItemRackButtonMenuOptions","Options","Open Options window to change settings, configure sets or auto queues."},
	{"ItemRackButtonMenuClose","Remove","Remove the slot this menu opened from."},
	{"ItemRackOptSetsHideCheckButton","Hide Set","Check this to make the set hidden in menus."},
	{"ItemRackOptItemStatsPriority","Priority","Check this to make this item auto equip when it comes off cooldown even if the equipped item is off cooldown and waiting to be used."},
	{"ItemRackOptItemStatsKeepEquipped","Pause Queue","Check this to suspend the auto queue for this slot until the item is unequipped. (For instance if you have another mod handling the auto equip of a riding crop."},
	{"ItemRackOptItemStatsSwapOnUse","Burn on Use","Check this to permanently ignore this item in the queue for the rest of the play session once its cooldown is triggered. It will not be equipped again until you manually re-equip the set."},
	{"ItemRackOptItemStatsSwapInEnable","Custom Swap In","Check this to override the default aggressive swap-in cooldown (30s for trinkets, 0s for others) and specify exactly how many seconds remaining on this item's cooldown it should be aggressively swapped back into the slot."},
	{"ItemRackOptQueueEnable","Auto Queue This Slot","Check this to allow this slot to auto queue.  When an item goes on cooldown, it will swap for an item higher on the list that's off cooldown."},
	{"ItemRackOptSetsHideCheckButton","Hide","Hide this set in menus. (Equivalent of Alt+clicking the set in the menu)"},
	{"ItemRackOptSetsSaveButton","Save Set","Save this set. Some settings like key binding, cloak/helm visibility and whether it's hidden can only be changed to a saved set."},
	{"ItemRackOptSetsDeleteButton","Delete Set","Delete this set definition. If you want to remove it from the menu and may want it again in the future, check 'Hide' to the left."},
	{"ItemRackOptSetsBindButton","Bind Key to Set","This will let you bind a key or key combination to equip a set."},
	{"ItemRackOptEventNew","New Event","Create a new event."},
	{"ItemRackOptEventEdit","Edit Event","Edit this event. Note: if you edit the name and save, it will create a copy of the event with the new name."},
	{"ItemRackOptEventDelete","Delete Event","If this event is enabled or has a set associated with it, it will remove the tags and drop it in the list.  If this is an untagged event, it will delete it entirely."},
	{"ItemRackOptEventEditSave","Save Event","Saves changes to this event.  Note: if you edit the name and save, it will create a copy of the event with the new name."},
	{"ItemRackOptEventEditCancel","Cancel Changes","Cancel any changes just made to this event and return to event list."},
	{"ItemRackOptEventEditBuffAnyMount","Any mount","Checking this will check if any mount is active instead of a specific buff."},
	{"ItemRackOptEventEditExpand","Edit in Editor","This will detach the script edit box above to a resizable text editor."},
	{"ItemRackFloatingEditorUndo","Undo","Revert the text to its last saved state."},
	{"ItemRackFloatingEditorTest","Test","Run the text below as a script to make sure there are no syntax errors. (Script Errors in Interface Options should be enabled to see any)\nNote: This test cannot simulate any condition or test for expected behavior other than the ability to run."},
	{"ItemRackFloatingEditorSave","Save Event","Save changes to this event and return to the event list."},
	{"ItemRackOptToggleInvAll","Toggle All","This will toggle between selecting all slots and selecting no slots."}
}

ItemRack.BankOpen = nil -- 1 if bank is open, nil if not

ItemRack.EventHandlers = {}
ItemRack.ExternalEventHandlers = {}

function ItemRack.InitEventHandlers()
	local handler = ItemRack.EventHandlers
	handler.ITEM_LOCK_CHANGED = ItemRack.OnItemLockChanged
	handler.ACTIONBAR_UPDATE_COOLDOWN = ItemRack.UpdateButtonCooldowns
	handler.UNIT_AURA = ItemRack.OnUnitAura
	handler.UNIT_INVENTORY_CHANGED = ItemRack.OnUnitInventoryChanged
	handler.UPDATE_BINDINGS = ItemRack.KeyBindingsChanged
	handler.PLAYER_REGEN_ENABLED = ItemRack.OnLeavingCombatOrDeath
	handler.PLAYER_UNGHOST = ItemRack.OnLeavingCombatOrDeath
	handler.PLAYER_ALIVE = ItemRack.OnLeavingCombatOrDeath
	handler.PLAYER_REGEN_DISABLED = ItemRack.OnEnteringCombat
	handler.BANKFRAME_CLOSED = ItemRack.OnBankClose
	handler.BANKFRAME_OPENED = ItemRack.OnBankOpen
	handler.UNIT_SPELLCAST_START = ItemRack.OnCastingStart
	handler.UNIT_SPELLCAST_STOP = ItemRack.OnCastingStop
	handler.UNIT_SPELLCAST_SUCCEEDED = ItemRack.OnCastingStop
	handler.UNIT_SPELLCAST_INTERRUPTED = ItemRack.OnCastingStop
	handler.UNIT_SPELLCAST_FAILED = ItemRack.OnCastingStop
	handler.UNIT_SPELLCAST_CHANNEL_START = ItemRack.OnCastingStart
	handler.UNIT_SPELLCAST_CHANNEL_STOP = ItemRack.OnCastingStop
	handler.CHARACTER_POINTS_CHANGED = ItemRack.UpdateClassSpecificStuff
	handler.PLAYER_TALENT_UPDATE = ItemRack.UpdateClassSpecificStuff
	handler.PLAYER_ENTERING_WORLD = ItemRack.OnEnterWorld
	handler.ZONE_CHANGED_NEW_AREA = ItemRack.OnZoneChanged
	handler.ZONE_CHANGED_INDOORS = ItemRack.OnZoneChanged
	handler.PLAYER_LOGOUT = ItemRack.OnPlayerLogout
	handler.ACTIVE_TALENT_GROUP_CHANGED = ItemRack.UpdateClassSpecificStuff
--	handler.PET_BATTLE_OPENING_START = ItemRack.OnEnteringPetBattle
--	handler.PET_BATTLE_CLOSE = ItemRack.OnLeavingPetBattle
end

do
	local Masque = LibStub("Masque", true) or (LibMasque and LibMasque("Button"))
	if Masque then
		ItemRack.MasqueGroups = {}
		ItemRack.MasqueGroups[1] = Masque:Group("ItemRack", "On screen panels")
		ItemRack.MasqueGroups[2] = Masque:Group("ItemRack", "On screen menus")
		ItemRack.MasqueGroups[3] = Masque:Group("ItemRack", "Character info menus")
		ItemRack.MasqueGroups[4] = Masque:Group("ItemRack", "Map icon menu")
	end
end

function ItemRack.OnEvent(self,event,...)
	ItemRack.EventHandlers[event](self,event,...)
end

--- Allows third-party addons to listen to ItemRack events, like saving and deleting a set.
function ItemRack.RegisterExternalEventListener(self,event,handler)
	local handlers = ItemRack.ExternalEventHandlers[event]
	if handlers == nil then
		handlers = {}
		ItemRack.ExternalEventHandlers[event] = handlers
	end

	table.insert(handlers, handler)
end

function ItemRack.FireItemRackEvent(self,event,...)
	local handlers = ItemRack.ExternalEventHandlers[event]
	if handlers ~= nil then
		for _, handler in pairs(handlers) do
			handler(event,...)
		end
	end
end

StaticPopupDialogs["ITEMRACK_MISSING_LSI"] = {
	text = "ItemRack: 'Disable swap sounds' is enabled, but the required library (LibSoundIndex) is missing.\n\nItemRack will still function normally but will fall back to modifying the game's SFX CVar, which mutes all sounds during equipment swaps.\n\nPlease install LibSoundIndex for a seamless audio experience.",
	button1 = "OK",
	OnAccept = function()
		ItemRackSettings.LSIWarningSeen = true
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function ItemRack.AuditSavedVariables(printToChat)
	local prefix = "[Audit] "
	local issuesFound = 0
	local fixedCount = 0
	local details = {}

	local function LogIssue(msg, fixed)
		issuesFound = issuesFound + 1
		if fixed then fixedCount = fixedCount + 1 end
		local text = msg .. (fixed and " (AUTO-FIXED)" or " (Requires Manual Fix)")
		table.insert(details, text)
		ItemRack.Debug("API", prefix .. text)
		if printToChat then
			ItemRack.Print("|cffffa500" .. prefix .. "|r" .. text)
		end
	end

	-- 1. Check CurrentSet
	if ItemRackUser.CurrentSet and not ItemRackUser.Sets[ItemRackUser.CurrentSet] then
		LogIssue("CurrentSet '" .. tostring(ItemRackUser.CurrentSet) .. "' does not exist. Resetting.", true)
		ItemRackUser.CurrentSet = nil
	end

	-- 2. Audit Sets
	for setName, setData in pairs(ItemRackUser.Sets) do
		-- Self-referential oldset
		if setData.oldset == setName then
			LogIssue("Set '" .. setName .. "' has self-referential oldset. Cleared.", true)
			setData.oldset = nil
		end
		-- Orphaned oldset
		if setData.oldset and not ItemRackUser.Sets[setData.oldset] then
			LogIssue("Set '" .. setName .. "' references non-existent oldset '" .. setData.oldset .. "'. Cleared.", true)
			setData.oldset = nil
		end
		-- Circular references (A -> B -> A, etc.)
		if setData.oldset then
			local path = { [setName] = true }
			local current = setData.oldset
			local loopDetected = false
			while current do
				if path[current] then
					loopDetected = true
					break
				end
				path[current] = true
				current = ItemRackUser.Sets[current] and ItemRackUser.Sets[current].oldset
			end
			if loopDetected then
				LogIssue("Circular oldset reference detected in set chain starting at '" .. setName .. "'. Broken.", true)
				setData.oldset = nil
			end
		end
	end

	-- 3. Audit Event Stack
	if ItemRackUser.EventStack then
		local uniqueStack = {}
		local seen = {}
		for _, eventName in ipairs(ItemRackUser.EventStack) do
			if not seen[eventName] then
				-- Check if event exists and is active
				local eventData = ItemRackUser.Events and ItemRackUser.Events.Set and ItemRackUser.Events.Set[eventName]
				if eventData then
					table.insert(uniqueStack, eventName)
					seen[eventName] = true
				else
					LogIssue("EventStack contained non-existent event '" .. tostring(eventName) .. "'. Removed.", true)
				end
			else
				LogIssue("EventStack contained duplicate event '" .. tostring(eventName) .. "'. Pruned.", true)
			end
		end
		ItemRackUser.EventStack = uniqueStack
	end

	-- 4. Audit Queues & QueuesEnabled
	if ItemRackUser.Queues then
		for slot in pairs(ItemRackUser.Queues) do
			local numSlot = tonumber(slot)
			if not numSlot or numSlot < 0 or numSlot > 19 then
				LogIssue("Queues contained invalid slot reference '" .. tostring(slot) .. "'. Cleared.", true)
				ItemRackUser.Queues[slot] = nil
			end
		end
	end
	if ItemRackUser.QueuesEnabled then
		for slot in pairs(ItemRackUser.QueuesEnabled) do
			local numSlot = tonumber(slot)
			if not numSlot or numSlot < 0 or numSlot > 19 then
				LogIssue("QueuesEnabled contained invalid slot reference '" .. tostring(slot) .. "'. Cleared.", true)
				ItemRackUser.QueuesEnabled[slot] = nil
			end
		end
	end

	-- 5. Audit Buttons
	if ItemRackUser.Buttons then
		for slot in pairs(ItemRackUser.Buttons) do
			local numSlot = tonumber(slot)
			if not numSlot or numSlot < 0 or numSlot > 20 then
				LogIssue("Buttons list contained invalid slot reference '" .. tostring(slot) .. "'. Cleared.", true)
				ItemRackUser.Buttons[slot] = nil
			end
		end
	end

	-- 6. Audit & Sync ItemRackSettings
	if ItemRack.DefaultSettings then
		-- Merge missing defaults
		for k, v in pairs(ItemRack.DefaultSettings) do
			if ItemRackSettings[k] == nil then
				LogIssue("ItemRackSettings was missing default setting '" .. tostring(k) .. "'. Restored default.", true)
				ItemRackSettings[k] = v
			end
		end
		-- Prune obsolete settings
		for k in pairs(ItemRackSettings) do
			if ItemRack.DefaultSettings[k] == nil then
				LogIssue("ItemRackSettings contained obsolete setting '" .. tostring(k) .. "'. Pruned.", true)
				ItemRackSettings[k] = nil
			end
		end
	end

	-- 7. Audit custom events scripts syntax
	if ItemRackEvents then
		for eventName, eventData in pairs(ItemRackEvents) do
			if eventData.Enabled and eventData.Script then
				local method, err = loadstring("local event,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,arg10 = ...;" .. eventData.Script)
				if not method then
					LogIssue("Event '" .. tostring(eventName) .. "' has syntax error in script: " .. tostring(err), false)
				end
			end
		end
	end

	-- 8. Persist results
	local auditData = {
		Timestamp = date("%Y-%m-%d %H:%M:%S"),
		IssuesFound = issuesFound,
		FixedCount = fixedCount,
		Details = details
	}
	ItemRackUser.LastAudit = auditData
	if issuesFound > 0 then
		ItemRackUser.LastRepair = auditData
	end

	if issuesFound > 0 and not printToChat then
		ItemRack.Print("Automatically repaired " .. issuesFound .. " configuration issue(s). Details saved in ItemRackUser.LastRepair.")
	elseif printToChat then
		ItemRack.Print("Audit completed. Issues found: " .. issuesFound .. ", Auto-fixed: " .. fixedCount)
	end
end

function ItemRack.OnPlayerLogin()
	-- Normally some of these methods cannot be called in combat without causing errors, but since we run these IMMEDIATELY
	-- on PLAYER_LOGIN event we get a grace period where it allows us to run secure code in combat.
	ItemRack.InitBroker()
	ItemRack.InitEventHandlers()
	ItemRack.InitTimers()
	ItemRack.InitCore()
	ItemRack.InitButtons()
	ItemRack.InitEvents()
	
	-- Audit SavedVariables on startup
	ItemRack.AuditSavedVariables(false)
	
	-- Check LibSoundIndex presence
	C_Timer.After(3, function()
		if ItemRackSettings.DisableSwapSound == "ON" and not ItemRackSettings.LSIWarningSeen and not (LibStub and LibStub("LibSoundIndex-1.0", true)) then
			StaticPopup_Show("ITEMRACK_MISSING_LSI")
		end
	end)
end

function ItemRack.OnPlayerLogout()
	-- Override bindings are runtime-only and don't need saving on logout.
	-- Set keybinds are stored in ItemRackUser.Sets[name].key and re-applied
	-- via SetSetBindings() on each login/reload.
end

function ItemRack.OnEnterWorld(self,event,...)
	local isLogin,isReload = ...
	ItemRack.UpdateArenaVisibilityState()
	if isLogin or isReload then
		-- Force a set update shortly after loading to ensure minimap icon/current set is correct
		-- This fixes the issue where the set appears as "Custom" until interaction
		C_Timer.After(2, function() 
			ItemRack.UpdateButtons() 
			ItemRack.UpdateCurrentSet()
		end)

		C_Timer.After(15,function()
			ItemRack.SetSetBindings()
		end)
	end
end

function ItemRack.ResetCooldownCaches()
	ItemRack.CooldownCache = {}
	ItemRack.MenuCooldownCache = {}
	ItemRack.CooldownDebugLast = {}
	if ItemRackUser and ItemRackUser.ItemsUsed then
		for itemID in pairs(ItemRackUser.ItemsUsed) do
			ItemRackUser.ItemsUsed[itemID] = nil
		end
	end
	if ItemRack.UpdateButtonCooldowns then
		ItemRack.UpdateButtonCooldowns()
	end
	if ItemRack.UpdateMenuCooldowns then
		ItemRack.UpdateMenuCooldowns()
	end
end

function ItemRack.UpdateArenaVisibilityState()
	local wasInArena = ItemRack.inArena
	local _, instanceType = IsInInstance()
	ItemRack.inArena = (instanceType == "arena") and 1 or nil
	if not wasInArena and ItemRack.inArena then
		ItemRack.ResetCooldownCaches()
		-- Arena joins can briefly report stale cooldown data during the zone load.
		-- Re-clear one second later so quick access buttons match Blizzard's reset state.
		C_Timer.After(1, function()
			if ItemRack.inArena then
				ItemRack.ResetCooldownCaches()
			end
		end)
	end
	if ItemRack.RefreshButtonVisibility then
		ItemRack.RefreshButtonVisibility()
	end
end

function ItemRack.OnZoneChanged()
	ItemRack.UpdateArenaVisibilityState()
end

local loader = CreateFrame("Frame",nil, self, BackdropTemplateMixin and "BackdropTemplate") -- need a new temp frame here, ItemRackFrame is not created yet

loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", ItemRack.OnPlayerLogin)

function ItemRack.OnCastingStart(self,event,unit,castID)
	if unit=="player" then
		if CastingInfo() or ChannelInfo() then
			ItemRack.NowCasting = castID or true
			--If channeled, let's store the spellName to match it up to the UNIT_SPELLCAST_SUCCEEDED event that immediately gets fired after starting.
			if ChannelInfo() then
				local spellName = UnitChannelInfo("player")
				ItemRack.NowChannelingSpell = spellName
				ItemRack.Debug("Equip", "Casting BLOCKED (channel start): spell=" .. tostring(spellName) .. " castID=" .. tostring(castID) .. " pendingCQ=" .. tostring(next(ItemRack.CombatQueue) ~= nil) .. " setsWaiting=" .. #ItemRack.SetsWaiting)
			else
				ItemRack.NowChannelingSpell = nil
				local spellName = UnitCastingInfo("player")
				ItemRack.Debug("Equip", "Casting BLOCKED (cast start): spell=" .. tostring(spellName) .. " castID=" .. tostring(castID) .. " pendingCQ=" .. tostring(next(ItemRack.CombatQueue) ~= nil) .. " setsWaiting=" .. #ItemRack.SetsWaiting)
			end
		end
	end
end

function ItemRack.OnCastingStop(self,event,unit,castID)
	if unit=="player" then
		-- Use castID to ensure we only clear the current cast. 
		-- If a new cast has already started, its castID will differ.
		if not ItemRack.NowCasting or (castID and ItemRack.NowCasting ~= castID and ItemRack.NowCasting ~= true) then
			return
		else
			if ItemRack.NowChannelingSpell then
				local spellName = UnitChannelInfo("player")
				if spellName and event == "UNIT_SPELLCAST_SUCCEEDED" and spellName == ItemRack.NowChannelingSpell then
					--When channeling, a UNIT_SPELLCAST_SUCCEEDED event will fire immediately after starting.
					--If this comes in for our channeled spell, ignore this event and wait for the UNIT_SPELLCAST_CHANNEL_STOP to fire.
					return
				end
			end
			
			ItemRack.NowCasting = nil
			ItemRack.NowChannelingSpell = nil
			ItemRack.Debug("Equip", "Casting RELEASED: event=" .. tostring(event) .. " castID=" .. tostring(castID) .. " pendingCQ=" .. tostring(next(ItemRack.CombatQueue) ~= nil) .. " setsWaiting=" .. #ItemRack.SetsWaiting)

			-- For weapons, we want to try the swap immediately to hit the window between spamming.
			-- Standard armor swaps can still wait for the 0.1s timer if needed, 
			-- but ProcessCombatQueue handles both.
			ItemRack.ProcessCombatQueue()

			-- Re-evaluate event-based sets (buffs, stances, zone, spec) now that casting has stopped
			if ItemRack.ProcessBuffEvent then
				ItemRack.ProcessBuffEvent()
			end

			-- Start the delayed timer to handle race conditions where combat/casting status blips
			ItemRack.OnSpellSucceed()

			-- Process any sets that were waiting for casting to end
			if #(ItemRack.SetsWaiting)>0 and not ItemRack.AnythingLocked() then
				ItemRack.ProcessSetsWaiting()
			end
		end
	end
end

function ItemRack.OnItemLockChanged()
	ItemRack.StartTimer("LocksChanged")
	ItemRack.LocksHaveChanged = 1
end

function ItemRack.OnSpellSucceed()
	ItemRack.StartTimer("DelayedCombatQueue")
end

function ItemRack.DelayedCombatQueue()
	if ItemRack.NowCasting then
		return
	end
	ItemRack.ProcessCombatQueue()
	-- Also process any sets waiting for a swap
	if #(ItemRack.SetsWaiting)>0 and not ItemRack.AnythingLocked() then
		ItemRack.ProcessSetsWaiting()
	end
end

function ItemRack.OnUnitInventoryChanged(self,event,unit)
	if unit=="player" then
		ItemRack.UpdateButtons()
		-- Clear any CombatQueue entries that have been fulfilled by the swap
		if next(ItemRack.CombatQueue) then
			ItemRack.Debug("CombatQueue", "OnUnitInventoryChanged: checking CombatQueue entries")
			local dirty = false
			for slot, queuedID in pairs(ItemRack.CombatQueue) do
				local equippedID = ItemRack.GetID(slot)
				local match = equippedID and queuedID and ItemRack.SameID(equippedID, queuedID)
				ItemRack.Debug("CombatQueue", "  slot="..tostring(slot).." queued="..tostring(queuedID).." equipped="..tostring(equippedID).." match="..tostring(match))
				if match then
					ItemRack.CombatQueue[slot] = nil
					ItemRack.ClearCombatQueueMetadata(slot)
					dirty = true
				end
			end
			if dirty then
				ItemRack.Debug("CombatQueue", "OnUnitInventoryChanged: cleared fulfilled entries")
				ItemRack.UpdateCombatQueue()
			end
		end
		if ItemRackMenuFrame:IsVisible() then
			ItemRack.BuildMenu()
		end
		if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
			for i=0,19 do
				if not ItemRackOpt.Inv[i].selected then
					ItemRackOpt.Inv[i].id = ItemRack.GetID(i)
				end
			end
			ItemRackOpt.UpdateInv()
		end
	end
end

function ItemRack.OnUnitAura(self,event,unit)
	if unit=="player" and ItemRack.PeriodicQueueCheck then
		ItemRack.PeriodicQueueCheck()
	end
end

function ItemRack.OnLeavingCombatOrDeath()
	ItemRack.inCombat = InCombatLockdown()
	ItemRack.Debug("Combat", "OnLeavingCombatOrDeath: InCombatLockdown="..tostring(InCombatLockdown()))
	if ItemRack.NowCasting then
		return
	end
	
	-- Re-evaluate event-based sets (buffs, stances, zone, spec) now that combat has stopped
	-- This handles "On Movement" sets that might need to swap based on current speed
	if ItemRack.ProcessBuffEvent then
		ItemRack.ProcessBuffEvent()
	end

	ItemRack.ProcessCombatQueue()
	
	-- Also start delayed timer to ensure any race conditions with InCombatLockdown() are caught
	ItemRack.StartTimer("DelayedCombatQueue")

	-- Process any sets waiting for combat/casting to end
	if #(ItemRack.SetsWaiting)>0 and not ItemRack.AnythingLocked() then
		ItemRack.ProcessSetsWaiting()
	end
end

function ItemRack.ProcessCombatQueue()
	-- Safety: clear any items stuck on the cursor from previous partial swaps
	if CursorHasItem() then
		ClearCursor()
	end
	if not ItemRack.IsPlayerReallyDead() and next(ItemRack.CombatQueue) then
		local inCombat = InCombatLockdown()
		local unitCombat = UnitAffectingCombat("player")
		ItemRack.Debug("CombatQueue", "ProcessCombatQueue: InCombatLockdown="..tostring(inCombat).." UnitAffectingCombat="..tostring(unitCombat))
		local combat = ItemRackUser.Sets["~CombatQueue"].equip
		local queue = ItemRack.CombatQueue
		local queuesEnabled = ItemRack.GetQueuesEnabled()
		local queues = ItemRack.GetQueues()
		for i in pairs(combat) do
			combat[i] = nil
		end
		for i in pairs(queue) do
			local canSwap = not inCombat
			ItemRack.Debug("CombatQueue", "  ProcessCQ slot="..tostring(i).." canSwap="..tostring(canSwap))
			if canSwap then
				local discard = false
				if ItemRack.AutoQueueFlag and ItemRack.AutoQueueFlag[i] then
					local sourceOwner = ItemRack.AutoQueueOwner and ItemRack.AutoQueueOwner[i]
					local currentOwner = ItemRack.GetActiveQueueOwner and ItemRack.GetActiveQueueOwner(i) or false
					local queueEnabled = queuesEnabled[i]
					local queueList = queues[i]
					-- Only auto-queued entries are context-sensitive. If the queue owner changed
					-- (for example: mount/flying event dropped, manual set changed, or per-set
					-- queues were reconfigured), discard the stale request instead of applying a
					-- trinket chosen for an older set context after combat ends.
					if not queueEnabled or not queueList or #queueList == 0 or sourceOwner ~= currentOwner then
						discard = true
						ItemRack.Debug("CombatQueue", "  dropping stale auto-queue slot="..tostring(i).." source="..tostring(sourceOwner or "global").." current="..tostring(currentOwner or "global"))
					end
				end
				if discard then
					queue[i] = nil
				else
					combat[i] = queue[i]
					queue[i] = nil
				end
				ItemRack.ClearCombatQueueMetadata(i)
			end
		end
		if next(combat) then
			ItemRackUser.Sets["~CombatQueue"].oldset = ItemRack.CombatSet
			ItemRack.UpdateCombatQueue()
			ItemRack.EquipSet("~CombatQueue")
		end
	end

	-- Always update overlay indicators, even if queue was empty or already processed
	-- by a different path (e.g. PopEvent → EquipSet), to clear stale overlays
	ItemRack.UpdateCombatQueue()

	local inLockdown = InCombatLockdown()
	if not inLockdown then
		if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
			ItemRackOpt.ListScrollFrameUpdate()
			ItemRackOptSetsBindButton:Enable()
		end
		if ItemRack.ReflectHideOOC then
			ItemRack.ReflectHideOOC()
		end
		if next(ItemRack.RunAfterCombat) then
			for i=1,#(ItemRack.RunAfterCombat) do
				ItemRack[ItemRack.RunAfterCombat[i]]()
			end
			wipe(ItemRack.RunAfterCombat)
		end
	end

end

function ItemRack.OnEnteringCombat()
	ItemRack.inCombat = 1
	ItemRack.Debug("Combat", "OnEnteringCombat: InCombatLockdown="..tostring(InCombatLockdown()))
	if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
		ItemRackOpt.ListScrollFrameUpdate()
		ItemRackOptSetsBindButton:Disable()
	end
	if ItemRack.ReflectHideOOC then
		ItemRack.ReflectHideOOC()
	end
end

function ItemRack.OnEnteringPetBattle()
	ItemRack.inPetBattle = 1
	if ItemRack.ReflectHidePetBattle then
		ItemRack.ReflectHidePetBattle()
	end
end

function ItemRack.OnLeavingPetBattle()
	ItemRack.inPetBattle = nil
	if ItemRack.ReflectHidePetBattle then
		ItemRack.ReflectHidePetBattle()
	end
end

function ItemRack.OnBankClose()
	ItemRack.BankOpen = nil
	ItemRackMenuFrame:Hide()
end

function ItemRack.OnBankOpen()
	ItemRack.BankOpen = 1
end

function ItemRack.UpdateClassSpecificStuff()
	local _,class = UnitClass("player")

	if class=="WARRIOR" or class=="ROGUE" or class=="HUNTER" or class=="MAGE" or class=="WARLOCK" or class=="SHAMAN" or class=="DEATHKNIGHT" then
		ItemRack.CanWearOneHandOffHand = 1
	end

	if ItemRack.IsWrath() and class=="WARRIOR" then
		if select(5,GetTalentInfo(2,26))>0 then
			ItemRack.HasTitansGrip = 1
			ItemRack.SlotInfo[17].INVTYPE_2HWEAPON = 1
		else
			ItemRack.HasTitansGrip = nil
			ItemRack.SlotInfo[17].INVTYPE_2HWEAPON = nil
		end
	end

end

function ItemRack.OnSetBagItem(tooltip, bag, slot)
	ItemRack.ListSetsHavingItem(tooltip, ItemRack.GetID(bag, slot))
end

function ItemRack.OnSetInventoryItem(tooltip, unit, inv_slot)
	ItemRack.ListSetsHavingItem(tooltip, ItemRack.GetID(inv_slot))
end

function ItemRack.OnSetHyperlink(tooltip, link)
	ItemRack.ListSetsHavingItem(tooltip, link:match("item:(.+)"))
end

do
	local data = {}

	function ItemRack.ListSetsHavingItem(tooltip, id)
		if ItemRackSettings.ShowTooltips ~= "ON" or ItemRackSettings.ShowSetInTooltip ~= "ON" then
			return
		end
		if not id or id == 0 then return end
		local same_exact = ItemRack.SameExactID
		for name, set in pairs(ItemRackUser.Sets) do
			if not name:match("^~") then
				for _, item in pairs(set.equip) do
					if same_exact(item, id) then
						data[name] = true
					end
				end
			end
		end
		for name in pairs(data) do
			tooltip:AddDoubleLine("ItemRack Set: ", name, 0,.6,1, 0,.6,1)
			data[name] = nil
		end
		tooltip:Show()
	end
end

function ItemRack.InitCore()
	ItemRackUser.Sets["~Unequip"] = { equip={} }
	ItemRackUser.Sets["~CombatQueue"] = { equip={} }

	-- Sterilize SavedVariables: Remove non-numeric keys from .equip and .old tables
	-- This prevents fatal WoW API crashes if string keys like "Queues" were injected by earlier versions
	for setname, set in pairs(ItemRackUser.Sets) do
		if set.equip then
			for k in pairs(set.equip) do
				if type(k) ~= "number" then
					set.equip[k] = nil
				end
			end
		end
		if set.old then
			for k in pairs(set.old) do
				if type(k) ~= "number" then
					set.old[k] = nil
				end
			end
		end
	end

	ItemRack.UpdateClassSpecificStuff()

	ItemRack.DURABILITY_PATTERN = string.match(DURABILITY_TEMPLATE,"(.+) .+/.+") or ""
	ItemRack.REQUIRES_PATTERN = string.gsub(ITEM_MIN_SKILL,"%%.",".+")

	-- pattern splitter by Maldivia http://forums.worldofwarcraft.com/thread.html?topicId=6441208576
	local function split(str, t)
		local start, stop, single, plural = str:find("\1244(.-):(.-);")
		if start then
			split(str:sub(1, start - 1) .. single .. str:sub(stop + 1), t)
			split(str:sub(1, start - 1) .. plural .. str:sub(stop + 1), t)
		else
			tinsert(t, (str:gsub("%%d","%%d+")))
		end
		return t
	end
	ItemRack.CHARGES_PATTERNS = {}
	split(ITEM_SPELL_CHARGES,ItemRack.CHARGES_PATTERNS)
	tinsert(ItemRack.CHARGES_PATTERNS,ITEM_SPELL_CHARGES_NONE)
	-- for enUS, ItemRack.CHARGES_PATTERNS now {"%d+ Charge","%d+ Charges","No Charges"}

	ItemRack.CreateTimer("MenuMouseover",ItemRack.MenuMouseover,.25,1)
	ItemRack.CreateTimer("TooltipUpdate",ItemRack.TooltipUpdate,1,1)
	ItemRack.CreateTimer("CooldownUpdate",ItemRack.CooldownUpdate,1,1)
	ItemRack.CreateTimer("LocksChanged",ItemRack.LocksChanged,.2)
	ItemRack.CreateTimer("DelayedCombatQueue",ItemRack.DelayedCombatQueue,.1)

	for i=-2,11 do
		ItemRack.LockList[i] = {}
	end

	hooksecurefunc("UseInventoryItem",ItemRack.newUseInventoryItem)
	hooksecurefunc("UseAction",ItemRack.newUseAction)
	hooksecurefunc("UseItemByName",ItemRack.newUseItemByName)
	hooksecurefunc("PaperDollFrame_OnShow",ItemRack.newPaperDollFrame_OnShow)
	hooksecurefunc(GameTooltip, "SetBagItem", ItemRack.OnSetBagItem)
	hooksecurefunc(GameTooltip, "SetInventoryItem", ItemRack.OnSetInventoryItem)
	hooksecurefunc(GameTooltip, "SetHyperlink", ItemRack.OnSetHyperlink)

	ItemRackFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	ItemRackFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	ItemRackFrame:RegisterEvent("PLAYER_UNGHOST")
	ItemRackFrame:RegisterEvent("PLAYER_ALIVE")
	ItemRackFrame:RegisterEvent("BANKFRAME_CLOSED")
	ItemRackFrame:RegisterEvent("BANKFRAME_OPENED")
	ItemRackFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
	if ItemRack.IsWrath() then
		ItemRackFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
		ItemRackFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
	end
	-- ItemRackFrame:RegisterEvent("PET_BATTLE_OPENING_START")
	-- ItemRackFrame:RegisterEvent("PET_BATTLE_CLOSE")
	--if not disable_delayed_swaps then
		-- in the event delayed swaps while casting don't work well,
		-- make disable_delayed_swaps=1 at top of this file to disable it
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_START")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
	ItemRackFrame:RegisterEvent("UNIT_AURA")
	ItemRackFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	ItemRackFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	ItemRackFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
	--end
	ItemRack.StartTimer("CooldownUpdate")
	ItemRack.ReflectAlpha()

	SlashCmdList["ItemRack"] = ItemRack.SlashHandler
	SLASH_ItemRack1 = "/itemrack"

	EquipSet = ItemRack.EquipSet -- for convenience in macros/events, shorter names
	ToggleSet = ItemRack.ToggleSet
	UnequipSet = ItemRack.UnequipSet
	IsSetEquipped = ItemRack.IsSetEquipped

	-- new option defaults to pre-existing settings here
	ItemRackSettings.Cooldown90 = ItemRackSettings.Cooldown90 or "OFF" -- 2.14
	ItemRackSettings.EquipOnSetPick = ItemRackSettings.EquipOnSetPick or "OFF" -- 2.21
	ItemRackUser.SetMenuWrap = ItemRackUser.SetMenuWrap or "OFF" -- 2.21
	ItemRackUser.SetMenuWrapValue = ItemRackUser.SetMenuWrapValue or 3 -- 2.21
	ItemRackSettings.MinimapTooltip = ItemRackSettings.MinimapTooltip or "ON" -- 2.21
	ItemRackSettings.CharacterSheetMenus = ItemRackSettings.CharacterSheetMenus or "ON" -- 2.22
	ItemRackSettings.DisableAltClick = ItemRackSettings.DisableAltClick or "OFF" -- 2.23
	ItemRackSettings.HidePetBattle = ItemRackSettings.HidePetBattle or "ON" -- 2.87
	ItemRackSettings.HideArena = ItemRackSettings.HideArena or "OFF"
	ItemRackSettings.LeftSlotsGoRight = ItemRackSettings.LeftSlotsGoRight or "ON" -- 4.28
	ItemRackSettings.RightSlotsGoLeft = ItemRackSettings.RightSlotsGoLeft or "OFF" -- 4.27.3
	ItemRackSettings.TinyTooltipsQuickAccess = ItemRackSettings.TinyTooltipsQuickAccess or "OFF"
	ItemRackSettings.TinyTooltipsSubMenusOnly = ItemRackSettings.TinyTooltipsSubMenusOnly or "OFF"
	ItemRackSettings.DisableTooltipsInCombat = ItemRackSettings.DisableTooltipsInCombat or "OFF"
	ItemRackSettings.CharacterSheetMenusLeft = nil -- removed in 4.27.3, replaced with per-side toggles
	
	-- (Temporary?) function to update all queues to tables for 
	-- the per-set queue settings: delay, priority, and pause.
	if not isAlreadyMigrated() then
		ItemRack.MigrateQueues()
	end
end

-- Check if we've already migrated by looking at the first entry
-- in the first queue we find (global or per-set).  If it's already
-- setup as a table, we assume we already migrated instead of looping through
-- all the tables everytime we init.
function isAlreadyMigrated()
	-- Check global queues
	for slot, q in pairs(ItemRackUser.Queues) do
		if q and type(q) == "table" then
			for _, entry in ipairs(q) do
				if entry ~= 0 and type(entry) == "table" then
					-- Found an entry and it's a table = we're on new format
					return true
				elseif entry ~= 0 then
					-- Found an entry but it's not a table = we're on old format
					return false
				end
			end
		end
	end
	
	-- Check per-set queues
	for _, set in pairs(ItemRackUser.Sets) do
		if set.Queues then
			for slot, q in pairs(set.Queues) do
				if q and type(q) == "table" then
					for _, entry in ipairs(q) do
						if entry ~= 0 and type(entry) == "table" then
							-- Found an entry and it's a table = we're on new format
							return true
						elseif entry ~= 0 then
							-- Found an entry but it's not a table = we're on old format
							return false
						end
					end
				end
			end
		end
	end
	
	-- No queues found at all, or all queues are empty = nothing to migrate, so just mark true
	return true
end

-- Convert the global and per-set queues to the new table
-- format to store the per-set queue settings: delay, priority, and pause. 
function ItemRack.MigrateQueues()
	-- Migrate global queues
	for slot, q in pairs(ItemRackUser.Queues) do
		migrateQueue(q)
	end
	
	-- Migrate per-set queues
	for _, set in pairs(ItemRackUser.Sets) do
		if set.Queues then
			for slot, q in pairs(set.Queues) do
				migrateQueue(q)
			end
		end
	end

	-- Clear ItemRackItems since it should now be redundant with the information being stored in the queues
	ItemRackItems = {}
end

-- Find every queue entry and lookup if there are currently any 
-- ItemRackItems values to transfer, otherwise set to defaults.
function migrateQueue(queue)
	if not queue then 
		return 
	end
	for i, entry in ipairs(queue) do
		if type(entry) ~= "table" then
			local id = entry
			local baseID = ItemRack.GetIRString(id, true)
			local settings = (ItemRackItems and ItemRackItems[baseID]) or {}
			queue[i] = {
				id = id,
				priority = settings.priority or false,
				keep = settings.keep or false,
				delay = settings.delay or 0,
			}
		end
	end
end

function ItemRack.Print(msg)
	if msg then
		DEFAULT_CHAT_FRAME:AddMessage("|cFFCCCCCCItemRack: |cFFFFFFFF"..msg)
	end
end

function ItemRack.UpdateCurrentSet()
	local useSound = GetCVar("Sound_EnableSFX")
	local overrideSound = false
	if ItemRackSettings.DisableActionBarSound == "ON" and useSound == "1" then
		SetCVar("Sound_EnableSFX", "0")
		overrideSound = true
	end

	local texture = "Interface\\AddOns\\ItemRack\\ItemRackIcon"
	local setname = ItemRackUser.CurrentSet or _G.CUSTOM
	if setname and setname ~= _G.CUSTOM then
		local equipped = ItemRack.IsSetEquipped(setname)
		
		if equipped then
			texture = ItemRack.GetTextureBySlot(20)
		else
			setname = _G.CUSTOM
		end
	end
	if ItemRackButton20 and ItemRackUser.Buttons[20] then
		ItemRackButton20ItemRackIcon:SetTexture(texture)
		local nameText = _G["ItemRackButton20Name"]
		if nameText then
			nameText:SetText(setname)
			nameText:Show()
		end
	end
	ItemRack.Broker.icon = texture
	ItemRack.Broker.text = setname

	if overrideSound then SetCVar("Sound_EnableSFX", "1") end
end

--[[ Item info gathering ]]

function ItemRack.GetTextureBySlot(slot)
	if slot==20 then
		if ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet] then
			return ItemRackUser.Sets[ItemRackUser.CurrentSet].icon
		else
			return "Interface\\AddOns\\ItemRack\\ItemRackIcon"
		end
	else
		local texture = GetInventoryItemTexture("player",slot)
		if texture then
			return texture
		else
			_,texture = GetInventorySlotInfo(ItemRack.SlotInfo[slot].name)
			return texture
		end
	end
end

-- itemlink/itemstring converter.
-- give it a regular itemLink/itemString and leave the second AND third parameters blank to receive an ItemRack-style ID: "62384:0:4041:4041:0:0:0:0:85:146"
-- give it an ItemRack-style ID and set the second parameter to true to receive the base itemID (ONLY for ItemRack-style IDs!): "62384"
-- give it a regular itemLink/itemString and set the second AND third parameters to true to receive the base itemID (ONLY for regular itemLinks/itemStrings!): "62384"
-- returns 0 on pattern matching failure (happens if no itemstring found/invalid itemstring format)
ItemRack.iSPatternRegularToIR = "item:(.-)\124h" --example: "62384:0:4041:4041:0:0:0:0:85:146:0:0", where 85 is the player's level when the itemLink/itemString was captured, in other words it's a regular itemString with the "item:" part removed
ItemRack.iSPatternBaseIDFromIR = "^(%-?%d+)" --this must *only* be used on ItemRack-style IDs, and will return the first field (the itemID), allowing us to do loose item matching
ItemRack.iSPatternBaseIDFromRegular = "item:(%-?%d+)" --this must *only* be used regular itemLinks/itemStrings, and will return the first field (the itemID), allowing us to do loose item matching
ItemRack.iSPatternEnhancementsFromIR = "^(%-?%d+):(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*)" --this must *only* be used on ItemRack-style IDs, and will return itemID, enchantID, gem1, gem2, gem3
ItemRack.iSPatternItemFieldsFromIR = "^(%-?%d+:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*)" --extracts the first 8 item-identifying fields (itemID:enchant:gem1:gem2:gem3:gem4:suffix:unique), ignoring level/spec/etc trailing fields
function ItemRack.GetIRString(inputString,baseid,regular)
	return string.match(tostring(inputString or ""), (baseid and (regular and ItemRack.iSPatternBaseIDFromRegular or ItemRack.iSPatternBaseIDFromIR) or ItemRack.iSPatternRegularToIR)) or 0
end

-- itemrack itemstring updater.
-- takes a saved ItemRack-style ID and returns an updated version with the latest player level and spec injected, which helps us update outdated IDs saved when the player was lower level or different spec
function ItemRack.UpdateIRString(itemRackID)
	return (string.gsub(itemRackID or "", "^("..strrep("%d+:", 8)..")%d+:%d+", "%1"..UnitLevel("player")..":".."0")) --note: parenthesis to discard 2nd return value (number of substitutions, which will always be 1)
end

-- returns the provided ItemRack-style ID string with "item:" prepended, which turns it into a normal itemstring which we can then use for item lookups, itemlink generation and so on.
-- sure, it's a simple function right now, but if the itemrack ID format above ever needs changing it'll be very easy to update the IRString to ItemString code in this one place.
function ItemRack.IRStringToItemString(itemRackID)
	local safeID = string.match(itemRackID or "", ItemRack.iSPatternItemFieldsFromIR) or itemRackID
	return "item:"..(safeID or "")
end

-- returns an ItemRack-style ID (62384:0:4041:4041:0:0:0:0:85:146) if an item exists in that slot, or 0 for none
-- bag,nil = inventory slot; bag,slot = container slot
function ItemRack.GetID(bag,slot)
	local _, itemLink
	local runeSuffix = ""
	if slot then
		itemLink = GetContainerItemLink(bag,slot)
	else
		if bag == INVSLOT_AMMO then -- classic workaround for ammo slot API bugs
			local invID = GetInventoryItemID("player",bag)
			if invID then
				_, itemLink = GetItemInfo(invID)
			end
		else
			itemLink = GetInventoryItemLink("player",bag)
		end
	end
	if ItemRack.AppendRuneID then
		runeSuffix = ItemRack.AppendRuneID(bag,slot)
	end
	if runeSuffix ~= ""	then
		return ItemRack.GetIRString(itemLink)..runeSuffix
	else
		return ItemRack.GetIRString(itemLink)
	end
end

-- takes two ItemRack-style IDs (one or both of the parameters can be a baseID instead if needed) and returns true if those items share the same base itemID
function ItemRack.SameID(id1,id2)
	return ItemRack.GetIRString(id1,true) == ItemRack.GetIRString(id2,true)
end

-- takes two ItemRack-style IDs and returns true if they share the same item-identifying fields (itemID, enchant, gems, suffix, unique)
-- this is more precise than SameID (which only compares base itemID) but tolerant of item string format changes (Classic 10 fields vs TBC 14 fields)
function ItemRack.SameExactID(id1,id2)
	if not id1 or not id2 or id1==0 or id2==0 then return false end
	local f1 = tostring(id1):match(ItemRack.iSPatternItemFieldsFromIR) or tostring(id1)
	local f2 = tostring(id2):match(ItemRack.iSPatternItemFieldsFromIR) or tostring(id2)
	return f1 == f2
end

-- takes an ItemRack-style ID and returns the name, texture, equipslot and quality
function ItemRack.GetInfoByID(id)
	local name,texture,equip,quality
	if id and id~=0 then
		name,_,quality,_,_,_,_,_,equip,texture = GetItemInfo(ItemRack.IRStringToItemString(ItemRack.UpdateIRString(id))) --ensure the stored ID is brought up to date, then generate a regular ItemString from it and get the item info
	else
		name,texture,quality = "(empty)","Interface\\Icons\\INV_Misc_QuestionMark",0 --default response on invalid ID
	end
	return name,texture,equip,quality
end

-- takes an iItemRack-style ID and parses out enchant and gem ids
function ItemRack.GetEnhancements(itemRackID)
	local itemID, enchantID, gem1, gem2, gem3 = 0,0,0,0,0
	if itemRackID and itemRackID ~= "" then
		itemID, enchantID, gem1, gem2, gem3 = itemRackID:match(ItemRack.iSPatternEnhancementsFromIR)
	end
	return tonumber(itemID), tonumber(enchantID), tonumber(gem1), tonumber(gem2), tonumber(gem3)
end

-- takes an ItemRack-style ID and returns how many items you own with that particular baseID (will not differentiate between enchanted/unenchanted versions, etc)
function ItemRack.GetCountByID(id)
	return tonumber(GetItemCount(ItemRack.GetIRString(id,true)))
end

-- searches player's inventory&equipment and returns inv,bag,slot of a specific ItemRack-style ID (62384:0:4041:4041:0:0:0:0:85:146) or the first matching item with the same base id (62384) if specific id not found
-- nil,bag,slot = item found in a bag; inv,nil,nil = item found in one of the player's equipment slots; nil,nil,nil = item not found (at least not in equipment/inventory, but it might still exist in bank, we cannot check that though since the player has to be at the bank to read its contents)
-- what it does: it first looks for an EXACT match in the list of "known IDs", which is a cache of the last known location of every item the player has in their equipment and inventory
-- it then looks for an EXACT match in the player's equipment and inventory, and if that fails it looks for a BASEID match in the player's equipment and inventory
function ItemRack.FindItem(id,lock)

	local locklist, getid, sameid = ItemRack.LockList, ItemRack.GetID, ItemRack.SameID --GetID will be used to look up the ItemRack-style ID for each item we pass over while we loop through the player's equipment/inventory

	id = ItemRack.UpdateIRString(id) --we must update the incoming ItemRack-style ID to always match the player's current level no matter what, since all WoW ItemStrings contain the player's current level at the time of query, thus if we don't update the level in our OLD ID it won't match the CURRENT ID even if it is the EXACT same item. this simple update ensures that the exact item can be accurately located even if the player has dinged since last saving the set.

	-- look for item in known items cache first (this cache is frequently rebuilt, such as when clicking the buttons to change a set, AS WELL as when the actual set change takes place, it's a bit overkill in fact, but at least it is up to date -- in fact the entire design is stupid. if the cache is ALWAYS rebuilt EVERY TIME a set change takes place, then the MANUAL search code further down will never take place unless the item is COMPLETELY MISSING. likewise, it means that we're constantly rebuilding a cache of ItemRack-style IDs, and then doing the EXACT same job AGAIN further down, in the "search for..." sections at the bottom of this function... bad design and lots of redundancy, heh. a better design would be to just search through our cache twice, first to look for an exact match, and then to look for a baseID match.)
	local knownID = ItemRack.KnownItems[id]
	if knownID then
		local bag,slot = math.floor(knownID/100),mod(knownID,100)
		if bag < 0 and not slot then
			bag = bag*-1
			if id==getid(bag) and (not lock or not locklist[-2][bag]) then
				if lock then locklist[-2][bag]=1 end
				return bag
			end
		elseif slot and slot > 0 then
			if id==getid(bag,slot) and (not lock or not locklist[bag][slot]) then
				if lock then locklist[bag][slot]=1 end
				return nil,bag,slot
			end
		end
	end

	-- search bags
	for i=4,0,-1 do
		for j=1,GetContainerNumSlots(i) do
			if id==getid(i,j) and (not lock or not locklist[i][j]) then
				if lock then locklist[i][j]=1 end
				return nil,i,j
			end
		end
	end
	-- search worn equipment
	for i=0,19 do
		if id==getid(i) and (not lock or not locklist[-2][i]) then
			if lock then locklist[-2][i]=1 end
			return i
		end
	end
	-- search bags for base id matches
	for i=4,0,-1 do
		for j=1,GetContainerNumSlots(i) do
			if sameid(id,getid(i,j)) and (not lock or not locklist[i][j]) then
				if lock then locklist[i][j]=1 end
				return nil,i,j
			end
		end
	end
	-- search worn equipment for base id matches
	for i=0,19 do
		if sameid(id,getid(i)) and (not lock or not locklist[-2][i]) then
			if lock then locklist[-2][i]=1 end
			return i
		end
	end
	-- if bank is open, search bank
	if ItemRack.BankOpen then
		local b,s = ItemRack.FindInBank(id,lock)
		if b then return nil,b,s end
	end
end

-- searches player's bank and returns bag,slot of a specific ItemRack-style ID (62384:0:4041:4041:0:0:0:0:85:146) or the first matching item with the same base id (62384) if specific id not found
-- bag,slot = item found in a bank bag; nil, nil = item not found in bank
function ItemRack.FindInBank(id,lock)

	local locklist, getid, sameid = ItemRack.LockList, ItemRack.GetID, ItemRack.SameID --GetID will be used to look up the ItemRack-style ID for each item we pass over while we loop through the player's bank

	id = ItemRack.UpdateIRString(id) --just as with the FindItem() patch above, we must ensure that the incoming ID to this function is brought up to date before we start scanning

	if ItemRack.BankOpen then -- only proceed if bank is open
		for _,i in pairs(ItemRack.BankSlots) do -- try to find an exact match at first
			if ItemRack.ValidBag(i) then
				for j=1,GetContainerNumSlots(i) do
					if id==getid(i,j) and (not lock or not locklist[i][j]) then
						if lock then locklist[i][j]=1 end
						return i,j
					end
				end
			end
		end
		for _,i in pairs(ItemRack.BankSlots) do -- otherwise resort to a loose baseID match
			if ItemRack.ValidBag(i) then
				for j=1,GetContainerNumSlots(i) do
					if sameid(id,getid(i,j)) and (not lock or not locklist[i][j]) then
						if lock then locklist[i][j]=1 end
						return i,j
					end
				end
			end
		end
	end
end

-- returns true if the bagid (0-4) is a normal "Container", as opposed to quivers and ammo pouches
function ItemRack.ValidBag(bagid)
	local baseID,bagtype
	if bagid==0 or bagid==-1 then
		return 1
	else
		local invID = ContainerIDToInventoryID(bagid)
		baseID = ItemRack.GetIRString(GetInventoryItemLink("player",invID),true,true) --get the baseID for the container
		if GetItemFamily(baseID)==0 then
			return 1
		end
--		if baseID then
--			_,_,_,_,_,_,bagtype = GetItemInfo(baseID)
--			if bagtype=="Bag" or bagtype=="Conteneur" or bagtype=="Beh\195\164lter" then
--				return 1
--			end
--		end
	end
end

function ItemRack.ClearLockList() -- this function is called very frequently, such as every time you click a set popup button to change the current set, AS WELL as when the actual set change takes place, and will call PopulateKnownItems in order to re-build the cache of current item locations and their itemstrings
	for i=-2,11 do
		for j in pairs(ItemRack.LockList[i]) do
			ItemRack.LockList[i][j] = nil
		end
	end
	if ItemRack.LocksHaveChanged then
		ItemRack.LocksHaveChanged = nil
		ItemRack.PopulateKnownItems()
	end
end

function ItemRack.FindSpace()
	for i=4,0,-1 do
		if ItemRack.ValidBag(i) then
			for j=1,GetContainerNumSlots(i) do
				if not GetContainerItemLink(i,j) and not ItemRack.LockList[i][j] then
					ItemRack.LockList[i][j] = 1
					return i,j
				end
			end
		end
	end
end

function ItemRack.FindBankSpace()
	if not ItemRack.BankOpen then return end
	for _,i in pairs(ItemRack.BankSlots) do
		if ItemRack.ValidBag(i) then
			for j=1,GetContainerNumSlots(i) do
				if not GetContainerItemLink(i,j) and not ItemRack.LockList[i][j] then
					ItemRack.LockList[i][j] = 1
					return i,j
				end
			end
		end
	end
end

function ItemRack.IsRed(which)
	local r,g,b = _G["ItemRackTooltipText"..which]:GetTextColor()
	if r>.9 and g<.2 and b<.2 then
		return 1
	end
end

function ItemRack.PlayerCanWear(invslot,bag,slot)
	local found = false
	local txt = false

	local i=1
	while _G["ItemRackTooltipTextLeft"..i] do
		-- ClearLines doesn't remove colors, manually remove them
		_G["ItemRackTooltipTextLeft"..i]:SetTextColor(0,0,0)
		_G["ItemRackTooltipTextRight"..i]:SetTextColor(0,0,0)
		i=i+1
	end
	ItemRackTooltip:SetBagItem(bag,slot)

	for i=2,ItemRackTooltip:NumLines() do
		txt = _G["ItemRackTooltipTextLeft"..i]:GetText()
		-- if either left or right text is red and this isn't a Durability x/x line, this item can't be worn
		if (ItemRack.IsRed("Left"..i) or ItemRack.IsRed("Right"..i)) and not string.find(txt,ItemRack.DURABILITY_PATTERN) and not string.match(txt,ItemRack.REQUIRES_PATTERN) then
			return nil
		end
	end

	local _,_,itemType = ItemRack.GetInfoByID(ItemRack.GetID(bag,slot))
	if itemType=="INVTYPE_WEAPON" and invslot==17 and not ItemRack.CanWearOneHandOffHand then
		-- if this is a One-Hand going to offhand, and player can't wear one-hand offhands, this item can't be worn
		return nil
	end

	-- the gammut was run, this item can be worn
	return 1
end

function ItemRack.IsSoulbound(bag,slot)
	ItemRackTooltip:SetBagItem(bag,slot)
	for i=2,5 do
		local text = _G["ItemRackTooltipTextLeft"..i]:GetText()
		if text==ITEM_SOULBOUND or text==ITEM_BIND_QUEST or text==ITEM_CONJURED then
			return 1
		end
	end
end

-- function happens .2 seconds after last ITEM_LOCK_CHANGE
function ItemRack.LocksChanged()
	ItemRack.UpdateButtonLocks()
	if ItemRack.SetSwapping then
		ItemRack.LockChangedDuringSetSwap()
	elseif ItemRackMenuFrame:IsVisible() and ItemRack.BankOpen and not ItemRack.AnythingLocked() then
		ItemRackMenuFrame:Hide()
		ItemRack.BuildMenu()
	elseif #(ItemRack.SetsWaiting)>0 and not ItemRack.AnythingLocked() then
		ItemRack.ProcessSetsWaiting()
	end
end

function ItemRack.PopulateKnownItems()
	local known = ItemRack.KnownItems
	for i in pairs(known) do
		known[i] = nil
	end
	local id
	local getid = ItemRack.GetID
	for i=0,19 do
		id = getid(i) --grab ItemRack-style ID for every currently worn equipment piece
		if id~=0 then
			known[id] = i*-1 --we were able to generate a valid ID for this item, so store its location (slot)
		end
	end
	for i=0,4 do
		for j=1,GetContainerNumSlots(i) do
			id = getid(i,j) --grab ItemRack-style ID for every bag item
			if id~=0 then
				if IsEquippableItem(ItemRack.GetIRString(id,true)) then --only proceed if this is an equippable item (test against the baseID of the item)
					known[id] = i*100+j --we were able to generate a valid ID for this item, so store its location (as a bag container offset)
				end
			end
		end
	end
	if ItemRack.BankOpen then
		for _,i in pairs(ItemRack.BankSlots) do
			if ItemRack.ValidBag(i) then
				for j=1,GetContainerNumSlots(i) do
					id = getid(i,j)
					if id~=0 and IsEquippableItem(ItemRack.GetIRString(id,true)) then
						known[id] = i*100+j
					end
				end
			end
		end
	end
	ItemRack.KnownItems = known
end

--[[ Timers ]]

function ItemRack.InitTimers()
	ItemRack.TimerPool = {}
	ItemRack.Timers = {}
end

-- ItemRack.CreateTimer(name,func,delay,rep)

-- name = arbitrary name to identify this timer
-- func = function to run when the delay finishes
-- delay = time (in seconds) after the timer is started before func is run
-- rep = nil or 1, whether to repeat the delay once it's reached
--
-- The standard use is to create a timer, and then ItemRack.StartTimer
-- when you want to run the delayed function.
--
-- You can do /script ItemRack.TimerDebug() anytime to see all timer status

function ItemRack.CreateTimer(name,func,delay,rep)
	ItemRack.TimerPool[name] = { func=func,delay=delay,rep=rep,elapsed=delay }
end

function ItemRack.IsTimerActive(name)
	for i,j in ipairs(ItemRack.Timers) do
		if j==name then
			return i
		end
	end
	return nil
end

function ItemRack.StartTimer(name,delay)
	ItemRack.TimerPool[name].elapsed = delay or ItemRack.TimerPool[name].delay
	if not ItemRack.IsTimerActive(name) then
		table.insert(ItemRack.Timers,name)
		ItemRackFrame:Show()
	end
end

function ItemRack.StopTimer(name)
	local idx = ItemRack.IsTimerActive(name)
	if idx then
		table.remove(ItemRack.Timers,idx)
		if #(ItemRack.Timers)<1 then
			ItemRackFrame:Hide()
		end
	end
end

function ItemRack.OnUpdate(self,elapsed)
	local timerPool
	for _,name in ipairs(ItemRack.Timers) do
		timerPool = ItemRack.TimerPool[name]
		timerPool.elapsed = timerPool.elapsed - elapsed
		if timerPool.elapsed < 0 then
			timerPool.func(elapsed)
			if timerPool.rep then
				timerPool.elapsed = timerPool.delay
			else
				ItemRack.StopTimer(name)
			end
		end
	end
end

function ItemRack.TimerDebug()
	local on = "|cFF00FF00On"
	local off = "|cFFFF0000Off"
	DEFAULT_CHAT_FRAME:AddMessage("|cFF44AAFFItemRackFrame is "..(ItemRackFrame:IsVisible() and on or off))
	for i in pairs(ItemRack.TimerPool) do
		DEFAULT_CHAT_FRAME:AddMessage(i.." is "..(ItemRack.IsTimerActive(i) and on or off))
	end
end

--[[ Menu ]]

function ItemRack.DockWindows(menuDock,relativeTo,mainDock,menuOrient,movable)
	ItemRackMenuFrame:ClearAllPoints()
	ItemRack.currentDock = mainDock..menuDock
	ItemRackMenuFrame:SetPoint(menuDock,relativeTo,mainDock,ItemRack.DockInfo[ItemRack.currentDock].xoff,ItemRack.DockInfo[ItemRack.currentDock].yoff)
	ItemRackMenuFrame:SetParent(relativeTo)
	ItemRackMenuFrame:SetFrameStrata("HIGH")
	ItemRack.mainDock = mainDock
	ItemRack.menuDock = menuDock
	ItemRack.menuOrient = menuOrient
	ItemRack.menuMovable = movable
	ItemRack.menuDockedTo = relativeTo:GetName()
	ItemRack.MenuMouseoverFrames[relativeTo:GetName()] = 1 -- add frame to mouseover candidates
	ItemRack.ReflectLock(not ItemRack.menuMovable)
	ItemRack.ReflectMenuScale()
end

function ItemRack.AlreadyInMenu(id)
	for i=1,#(ItemRack.Menu) do
		if ItemRack.Menu[i]==id then
			return 1
		end
	end
end

function ItemRack.AddToMenu(itemID)
	if ItemRackSettings.AllowHidden=="OFF" or (IsAltKeyDown() or not ItemRack.IsHidden(itemID)) then
		table.insert(ItemRack.Menu,itemID)
	end
end

-- builds a popout menu for slots or set button
-- id = 0-19 for inventory slots, or 20 for set, or nil for last defined slot/set menu (ItemRack.menuOpen)
-- before calling ItemRack.BuildMenu, you should call ItemRack.DockWindows
-- if menuInclude, then also include the worn item(s) in the menu
function ItemRack.BuildMenu(id,menuInclude,masqueGroup)
	if id then
		ItemRack.menuOpen = id
		ItemRack.menuInclude = menuInclude
		ItemRack.menuMasqueGroup = masqueGroup
	else
		id = ItemRack.menuOpen
		menuInclude = ItemRack.menuInclude
		masqueGroup = ItemRack.menuMasqueGroup
	end

	ItemRack.Debug("UI", "BuildMenu called. id:", id, "InCombat:", InCombatLockdown(), "menuOpen:", ItemRack.menuOpen)

	local useSound = GetCVar("Sound_EnableSFX")
	local overrideSound = false
	if ItemRackSettings.DisableActionBarSound == "ON" and useSound == "1" then
		SetCVar("Sound_EnableSFX", "0")
		overrideSound = true
	end

	local showButtonMenu = (ItemRackButtonMenu and ItemRack.menuMovable) and (IsAltKeyDown() or ItemRackUser.Locked=="OFF")

	for i in pairs(ItemRack.Menu) do
		ItemRack.Menu[i] = nil
	end

	local itemLink,itemID,itemName,equipSlot,itemTexture

	if id<20 then
		if menuInclude then
			itemID = ItemRack.GetID(id)
			if itemID~=0 then
				ItemRack.AddToMenu(itemID)
			end
			if ItemRack.SlotInfo[id].other then
				itemID = ItemRack.GetID(ItemRack.SlotInfo[id].other)
				if itemID~=0 then
					ItemRack.AddToMenu(itemID)
				end
			end
		end
		for i=0,4 do
			for j=1,GetContainerNumSlots(i) do
				itemID = ItemRack.GetID(i,j)
				itemName,itemTexture,equipSlot = ItemRack.GetInfoByID(itemID)
				if ItemRack.SlotInfo[id][equipSlot] and ItemRack.PlayerCanWear(id,i,j) and (ItemRackSettings.HideTradables=="OFF" or ItemRack.IsSoulbound(i,j)) then
					if id~=0 or not ItemRack.AlreadyInMenu(itemID) then
						ItemRack.AddToMenu(itemID)
					end
				end
			end
		end
		if ItemRack.BankOpen then
			for _,i in pairs(ItemRack.BankSlots) do
				for j=1,GetContainerNumSlots(i) do
					itemID = ItemRack.GetID(i,j)
					itemName,itemTexture,equipSlot = ItemRack.GetInfoByID(itemID)
					if ItemRack.SlotInfo[id][equipSlot] and ItemRack.PlayerCanWear(id,i,j) and (ItemRackSettings.HideTradables=="OFF" or ItemRack.IsSoulbound(i,j)) then
						if id~=0 or not ItemRack.AlreadyInMenu(itemID) then
							ItemRack.AddToMenu(itemID)
						end
					end
				end
			end
		elseif ItemRack.GetID(id)~=0 and ItemRackSettings.AllowEmpty=="ON" then
			table.insert(ItemRack.Menu,0)
		end
	else
		for i in pairs(ItemRackUser.Sets) do
			if not string.match(i,"^~") then --do not list internal sets, prefixed with ~
				ItemRack.AddToMenu(i)
			end
			table.sort(ItemRack.Menu)
		end
	end
	if showButtonMenu then
		table.insert(ItemRack.Menu,"MENU")
	end

	if #(ItemRack.Menu)<1 then
		ItemRackMenuFrame:Hide()
	else
		-- display outward from docking point
		local col,row,xpos,ypos = 0,0,ItemRack.DockInfo[ItemRack.currentDock].xstart,ItemRack.DockInfo[ItemRack.currentDock].ystart
		local menuCount = #(ItemRack.Menu)
		local max_cols, button, icon
		if ItemRackUser.SetMenuWrap=="ON" then
			max_cols = ItemRackUser.SetMenuWrapValue
		else
			-- Dynamic wrap based on count to keep popups compact but manageable
			if menuCount > 24 then
				max_cols = 6
			elseif menuCount > 12 then
				max_cols = 4
			elseif menuCount > 8 then
				max_cols = 3
			elseif menuCount > 4 then
				max_cols = 2
			else
				max_cols = 1
			end
		end

		-- Screen space awareness: ensure height doesn't exceed screen
		local screenHeight = GetScreenHeight()
		if ItemRack.menuOrient == "HORIZONTAL" then
			-- In horizontal mode, max_cols is the HEIGHT in buttons
			if (max_cols * 40 + 40) > screenHeight then
				max_cols = math.floor((screenHeight - 80) / 40)
			end
		else
			-- In vertical mode, height grows with rows (menuCount / max_cols)
			local rows = math.ceil(menuCount / max_cols)
			if (rows * 40 + 40) > screenHeight then
				max_cols = math.ceil(menuCount / (math.floor((screenHeight - 80) / 40)))
			end
		end

		for i=1,#(ItemRack.Menu) do
			button = ItemRack.CreateMenuButton(i,ItemRack.Menu[i]) or ItemRackButtonMenu
			button:SetPoint("TOPLEFT",ItemRackMenuFrame,ItemRack.menuDock,xpos,ypos)
			button:SetFrameLevel(ItemRackMenuFrame:GetFrameLevel()+1)

			if ItemRack.MasqueGroups then
				for _, group in pairs(ItemRack.MasqueGroups) do
					group:RemoveButton(button)
				end

				if ItemRack.MasqueGroups[masqueGroup] then
					ItemRack.MasqueGroups[masqueGroup]:AddButton(button)
				end
			end

			if ItemRack.menuOrient=="VERTICAL" then
				xpos = xpos + ItemRack.DockInfo[ItemRack.currentDock].xdir*40
				col = col + 1
				if col==max_cols then
					xpos = ItemRack.DockInfo[ItemRack.currentDock].xstart
					col = 0
					ypos = ypos + ItemRack.DockInfo[ItemRack.currentDock].ydir*40
					row = row + 1
				end
				button:Show()
			else
				ypos = ypos + ItemRack.DockInfo[ItemRack.currentDock].ydir*40
				col = col + 1
				if col==max_cols then
					ypos = ItemRack.DockInfo[ItemRack.currentDock].ystart
					col = 0
					xpos = xpos + ItemRack.DockInfo[ItemRack.currentDock].xdir*40
					row = row + 1
				end
				button:Show()
			end
			icon = _G["ItemRackMenu"..i.."Icon"]
			if icon then
				icon:SetDesaturated(false)
				if IsAltKeyDown() and ItemRackSettings.AllowHidden=="ON" and IsAltKeyDown() and ItemRack.IsHidden(ItemRack.Menu[i]) then
					icon:SetDesaturated(true)
				end
			end
		end
		if showButtonMenu then
			table.remove(ItemRack.Menu)
		else
			ItemRackButtonMenu:Hide()
		end
		local i = #(ItemRack.Menu)+1
		while _G["ItemRackMenu"..i] do
			_G["ItemRackMenu"..i]:Hide()
			i=i+1
		end

		if col==0 then
			row = row-1
		end

		if ItemRack.menuOrient=="VERTICAL" then
			ItemRackMenuFrame:SetWidth(12+(max_cols*40))
			ItemRackMenuFrame:SetHeight(12+((row+1)*40))
		else
			ItemRackMenuFrame:SetWidth(12+((row+1)*40))
			ItemRackMenuFrame:SetHeight(12+(max_cols*40))
		end

		ItemRack.StartTimer("MenuMouseover")
		ItemRackMenuFrame:Show()
		ItemRack.UpdateMenuCooldowns()
		local count
		local border
		for i=1,#(ItemRack.Menu) do
			border = _G["ItemRackMenu"..i.."Border"]
			border:Hide()
			if ItemRack.menuOpen==20 then
				_G["ItemRackMenu"..i.."Name"]:SetText(ItemRack.Menu[i])
				local missing = ItemRack.MissingItems(ItemRack.Menu[i])
				if missing==0 then
					border:SetVertexColor(1,.1,.1)
					border:Show()
				elseif missing==1 then
					border:SetVertexColor(.3,.5,1)
					border:Show()
				end
			else
				_G["ItemRackMenu"..i.."Name"]:SetText("")
				if ItemRack.Menu[i]~=0 and ItemRack.GetCountByID(ItemRack.Menu[i])==0 then
					border:SetVertexColor(.3,.5,1)
					border:Show()
				end
			end
			count = ItemRack.GetCountByID(ItemRack.Menu[i])
			if ItemRack.menuOpen==0 then
				_G["ItemRackMenu"..i.."Count"]:SetText(count>0 and count or "")
			else
				_G["ItemRackMenu"..i.."Count"]:SetText(count>1 and count or "")
			end
		end
	end

	if overrideSound then SetCVar("Sound_EnableSFX", "1") end
end

-- Cache for menu item cooldowns (keyed by baseID)
ItemRack.MenuCooldownCache = ItemRack.MenuCooldownCache or {}

function ItemRack.UpdateMenuCooldowns()
	local baseID
	for i=1,#(ItemRack.Menu) do
		baseID = tonumber(ItemRack.GetIRString(ItemRack.Menu[i],true)) --get baseID and convert it to number to be able to use it in numerical comparisons below
		if baseID and baseID>0 and ItemRack.menuOpen<20 then
			local cdFrame = _G["ItemRackMenu"..i.."Cooldown"]
			local start, duration, enable = GetItemCooldown(baseID)

			-- Suppress Blizzard's built-in countdown numbers
			if cdFrame and cdFrame.SetHideCountdownNumbers and not _G["OmniCC"] then
				cdFrame:SetHideCountdownNumbers(true)
			end

			if enable and enable == 1 then
				-- Normal state: cache real CDs
				if start and start > 0 and duration and duration > 1.5 then
					ItemRack.MenuCooldownCache[baseID] = { start = start, duration = duration }
					CooldownFrame_Set(cdFrame, start, duration, enable)
				elseif not start or start == 0 or (duration and duration <= 1.5) then
					-- CC-guard: check cache before clearing
					local cache = ItemRack.MenuCooldownCache[baseID]
					if cache then
						local remaining = cache.duration - (GetTime() - cache.start)
						if remaining > 0.1 then
							CooldownFrame_Set(cdFrame, cache.start, cache.duration, 1)
						else
							ItemRack.MenuCooldownCache[baseID] = nil
							CooldownFrame_Set(cdFrame, start, duration, enable)
						end
					else
						CooldownFrame_Set(cdFrame, start, duration, enable)
					end
				else
					CooldownFrame_Set(cdFrame, start, duration, enable)
				end
			elseif enable == 0 then
				-- Stun/LoC: use cache
				local cache = ItemRack.MenuCooldownCache[baseID]
				if cache then
					local remaining = cache.duration - (GetTime() - cache.start)
					if remaining > 0.1 then
						CooldownFrame_Set(cdFrame, cache.start, cache.duration, 1)
					else
						ItemRack.MenuCooldownCache[baseID] = nil
						CooldownFrame_Clear(cdFrame)
					end
				else
					CooldownFrame_Clear(cdFrame)
				end
			else
				CooldownFrame_Set(cdFrame, start, duration, enable)
			end
		else
			_G["ItemRackMenu"..i.."Cooldown"]:Hide()
		end
	end
	ItemRack.WriteMenuCooldowns()
end

function ItemRack.WriteMenuCooldowns()
	if ItemRackSettings.CooldownCount=="ON" and ItemRackMenuFrame:IsVisible() then
		local baseID
		for i=1,#(ItemRack.Menu) do
			baseID = ItemRack.GetIRString(ItemRack.Menu[i],true)
			if baseID then
				local numID = tonumber(baseID)
				local start, duration, enable = GetItemCooldown(baseID)
				if enable and enable == 1 then
					ItemRack.WriteCooldown(_G["ItemRackMenu"..i.."Time"], start, duration)
				elseif enable == 0 then
					local cache = numID and ItemRack.MenuCooldownCache[numID]
					if cache then
						local remaining = cache.duration - (GetTime() - cache.start)
						if remaining > 0 then
							ItemRack.WriteCooldown(_G["ItemRackMenu"..i.."Time"], cache.start, cache.duration)
						else
							_G["ItemRackMenu"..i.."Time"]:SetText("")
						end
					else
						_G["ItemRackMenu"..i.."Time"]:SetText("")
					end
				else
					ItemRack.WriteCooldown(_G["ItemRackMenu"..i.."Time"], start, duration)
				end
			else
				_G["ItemRackMenu"..i.."Time"]:SetText("")
			end
		end
	end
end

function ItemRack.MenuMouseover()
	local frame = GetMouseFocus()
	local frameName = nil
	local frameVisible = nil
	local IRmouseOverFrame = nil
	
	if frame and type(frame.GetName) == "function" then
		local ok, name = pcall(frame.GetName, frame)
		if ok then frameName = name end
	end
	if frame and type(frame.IsVisible) == "function" then
		local ok, isVis = pcall(frame.IsVisible, frame)
		if ok then frameVisible = isVis end
	end
	
	if frameName then IRmouseOverFrame = ItemRack.MenuMouseoverFrames[frameName] end
	if MouseIsOver(ItemRackMenuFrame) or IsShiftKeyDown() or (frame and frameName and frameVisible and IRmouseOverFrame) then
		return -- keep menu open if mouse over menu, shift is down or mouse is immediately over a mouseover frame
	end
	for i in pairs(ItemRack.MenuMouseoverFrames) do
		frame = _G[i]
		if frame and frame:IsVisible() and MouseIsOver(frame) then
			return -- keep menu open if some frame beneath mouse is a mouseover frame
		end
	end
	ItemRack.StopTimer("MenuMouseover")
	ItemRackMenuFrame:Hide()
end

function ItemRack.MenuOnHide()
	ItemRack.menuDockedTo = nil
end

function ItemRack.CreateMenuButton(idx,itemID)
	if itemID=="MENU" then return end
	local button
	if not _G["ItemRackMenu"..idx] then
		button = CreateFrame("CheckButton","ItemRackMenu"..idx,ItemRackMenuFrame,"ActionButtonTemplate")
		button:SetID(idx)
		button:SetFrameStrata("HIGH")
--		button:SetFrameLevel(ItemRackMenuFrame:GetFrameLevel()+1)
		button:RegisterForClicks("LeftButtonUp","RightButtonUp")
		button:SetScript("OnClick",ItemRack.MenuOnClick)
		button:SetScript("OnEnter",ItemRack.MenuTooltip)
		button:SetScript("OnLeave",ItemRack.ClearTooltip)
		CreateFrame("Frame",nil,button,"ItemRackTimeTemplate")

		ItemRack.SetFont("ItemRackMenu"..idx)
--		local font = button:CreateFontString("ItemRackMenu"..idx.."Time","OVERLAY","NumberFontNormal")
--		font:SetJustifyH("CENTER")
--		font:SetWidth(36)
--		font:SetHeight(12)
--		font:SetPoint("BOTTOMRIGHT","ItemRackMenu"..idx,"BOTTOMRIGHT")
	end
	if itemID~=0 then
		if ItemRackUser.Sets[itemID] then
			_G["ItemRackMenu"..idx.."Icon"]:SetTexture(ItemRackUser.Sets[itemID].icon)
		else
			local _,texture = ItemRack.GetInfoByID(itemID)
			_G["ItemRackMenu"..idx.."Icon"]:SetTexture(texture)
		end
	else
		_G["ItemRackMenu"..idx.."Icon"]:SetTexture(select(2,GetInventorySlotInfo(ItemRack.SlotInfo[ItemRack.menuOpen].name)))
	end
	return _G["ItemRackMenu"..idx]
end

-- takes an ItemRack-style ID, finds the best match in the player's inventory, and puts its ItemLink to the chat editbox.
-- if the item is missing, it uses the ItemRack-style ID as-is to generate a clickable ItemLink from the stored data
function ItemRack.ChatLinkID(itemID)
	local inv,bag,slot = ItemRack.FindItem(itemID)
	if bag then
		ChatFrame1EditBox:Insert(GetContainerItemLink(bag,slot))
	elseif inv then
		ChatFrame1EditBox:Insert(GetInventoryItemLink("player",inv))
	else
		local _,itemLink = GetItemInfo(ItemRack.IRStringToItemString(ItemRack.UpdateIRString(itemID))) --ensure the stored ID is brought up to date, then generate a regular ItemString from it and get the item info
		if itemLink then
			ChatFrame1EditBox:Insert(itemLink)
		end
	end
end

function ItemRack.MenuOnClick(self,button)
	self:SetChecked(false)
	local item = ItemRack.Menu[self:GetID()]
	ItemRack.Debug("UI", "MenuOnClick:", self:GetName(), "button:", button, "item:", item, "InCombat:", InCombatLockdown(), "menuOpen:", ItemRack.menuOpen)
	ItemRack.ClearLockList()
	if IsAltKeyDown() and ItemRackSettings.AllowHidden == "ON" and item ~= "MENU" then
		ItemRack.ToggleHidden(item)
		ItemRack.BuildMenu()
	elseif IsAltKeyDown() and ItemRackSettings.DisableAltClick == "OFF" then
		-- In the Quick Access Menu, Alt-Click toggles the queue for the slot this menu belongs to
		local slot = ItemRack.menuOpen
		if slot and slot < 20 then
			if not ItemRack.GetQueues()[slot] then
				LoadAddOn("ItemRackOptions")
				ItemRackOptFrame:Show()
				ItemRackOpt.TabOnClick(self, 4)
				ItemRackOpt.SetupQueue(slot)
			end
			-- Ensure per-set table exists before writing
			if ItemRackUser.EnablePerSetQueues == "ON" then
				local currentSet = ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet]
				if currentSet and not currentSet.QueuesEnabled then
					currentSet.QueuesEnabled = {}
				end
			end
			ItemRack.GetQueuesEnabled()[slot] = not ItemRack.GetQueuesEnabled()[slot]
			if ItemRackOptSubFrame7 and ItemRackOptSubFrame7:IsVisible() and ItemRackOpt.SelectedSlot == slot then
				ItemRackOpt.UpdateQueueEnable()
			end
			ItemRack.UpdateCombatQueue()
			
			-- Workaround: prevent whatever native secure action was queued by immediately equipping the currently worn item
			if not InCombatLockdown() then
				local currentID = ItemRack.GetID(slot)
				if currentID and currentID ~= 0 then
					ItemRack.EquipItemByID(currentID, slot)
				end
			end
		end
		-- Re-build the menu to reflect the new gear icon on the main button
		ItemRack.BuildMenu()
	elseif IsShiftKeyDown() and ChatFrame1EditBox:IsVisible() then
		ItemRack.ChatLinkID(item)
	elseif ItemRack.menuInclude then
		if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
			ItemRackOpt.Inv[ItemRack.menuOpen].id = item
			ItemRackOpt.Inv[ItemRack.menuOpen].selected = 1
			ItemRackOpt.UpdateInv()
			ItemRackMenuFrame:Hide()
		end
	elseif ItemRack.menuOpen<20 then
		if ItemRack.BankOpen then
			if IsShiftKeyDown() then
				local invSlot = ItemRack.menuOpen
				local bankBag,bankSlot = ItemRack.FindInBank(item)
				if bankBag then
					if not SpellIsTargeting() and not GetCursorInfo() then
						PickupContainerItem(bankBag,bankSlot)
						PickupInventoryItem(invSlot)
						PickupContainerItem(bankBag,bankSlot)
					end
				else
					local _,bag,slot = ItemRack.FindItem(item)
					local spaceBag,spaceSlot = ItemRack.FindBankSpace()
					if bag and spaceBag and not SpellIsTargeting() and not GetCursorInfo() then
						PickupContainerItem(bag,slot)
						PickupInventoryItem(invSlot)
						PickupContainerItem(spaceBag,spaceSlot)
					else
						ItemRack.EquipItemByID(item,invSlot)
					end
				end
				ItemRackMenuFrame:Hide()
			else
				if ItemRack.GetCountByID(item)==0 then
					local bankBag,bankSlot = ItemRack.FindInBank(item)
					if bankBag then
						local freeBag,freeSlot = ItemRack.FindSpace()
						if freeBag and not SpellIsTargeting() and not GetCursorInfo() then
							PickupContainerItem(bankBag,bankSlot)
							PickupContainerItem(freeBag,freeSlot)
						else
							ItemRack.Print("Not enough room in bags to pull this item from bank.")
						end
					end
				else
					local bankBag,bankSlot = ItemRack.FindBankSpace()
					if bankBag then
						local _,bag,slot = ItemRack.FindItem(item)
						if bag and not SpellIsTargeting() and not GetCursorInfo() then
							PickupContainerItem(bag,slot)
							PickupContainerItem(bankBag,bankSlot)
						end
					else
						ItemRack.Print("Not enough room in bank to put this item.")
					end
				end
			end
		else
			if ItemRackSettings.EquipOnSetPick=="ON" and ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
				ItemRackOpt.Inv[ItemRack.menuOpen].id = item
				ItemRackOpt.Inv[ItemRack.menuOpen].selected = 1
				ItemRackOpt.UpdateInv()
			end
			if ItemRack.menuOpen>=13 and ItemRack.menuOpen<=14 and ItemRackSettings.TrinketMenuMode=="ON" and ItemRackUser.Buttons[13] and ItemRackUser.Buttons[14] then
				ItemRack.menuOpen = button=="RightButton" and 14 or 13
			end
			ItemRack.EquipItemByID(item,ItemRack.menuOpen)
			ItemRackMenuFrame:Hide()
		end
	elseif ItemRack.menuOpen==20 then
		if ItemRack.BankOpen then
			if IsShiftKeyDown() then
				ItemRack.EquipSet(item)
			else
				if ItemRack.MissingItems(item)==1 then
					ItemRack.GetBankedSet(item)
				else
					ItemRack.PutBankedSet(item)
				end
			end
		elseif ItemRackSettings.EquipToggle=="ON" then
			ItemRack.ToggleSet(item)
		else
			ItemRack.EquipSet(item)
		end
		if not ItemRack.BankOpen or IsShiftKeyDown() then
			ItemRack.StopTimer("MenuMouseover")
			ItemRackMenuFrame:Hide()
		end
	end
end

-- UI SoundKit constants that fire during gear swaps
ItemRack.SwapUISounds = {
	"IG_BACKPACK_OPEN",          -- Bag opens during item move
	"IG_BACKPACK_CLOSE",         -- Bag closes after item move
	"IG_ABILITY_ICON_DROP",      -- Action bar spell swap
	"IG_CHARACTER_INFO_OPEN",    -- Character panel opens
	"IG_CHARACTER_INFO_CLOSE",   -- Character panel closes
	"PUT_DOWN_GEMS",             -- Gem/item putdown
	"PICK_UP_GEMS",              -- Gem/item pickup
	"PUT_DOWN_SMALL_CHAIN",      -- Chain item putdown
}

-- Mute all swap-related sounds using LibSoundIndex
-- Returns: LSI reference (truthy) if surgical muting was used, nil otherwise
function ItemRack.MuteSwapSounds(duration)
	duration = duration or 1.5
	local LSI = LibStub and LibStub("LibSoundIndex-1.0", true)
	if not LSI then return nil end

	-- Mute equip material sounds (armor foley, weapon sheathe/unsheathe)
	LSI:MuteEquipCategory("ALL_EQUIP")

	-- Mute UI sounds that fire during item moves
	for _, soundKit in ipairs(ItemRack.SwapUISounds) do
		LSI:MuteSoundKit(soundKit)
	end

	-- Auto-unmute after duration
	if ItemRack.SwapMuteTimer then
		ItemRack.SwapMuteTimer:Cancel()
	end
	ItemRack.SwapMuteTimer = C_Timer.NewTimer(duration, function()
		ItemRack.UnmuteSwapSounds()
		ItemRack.SwapMuteTimer = nil
	end)

	return LSI
end

-- Unmute all swap-related sounds
function ItemRack.UnmuteSwapSounds()
	local LSI = LibStub and LibStub("LibSoundIndex-1.0", true)
	if not LSI then return end

	LSI:UnmuteEquipCategory("ALL_EQUIP")
	for _, soundKit in ipairs(ItemRack.SwapUISounds) do
		LSI:UnmuteSoundKit(soundKit)
	end
end

function ItemRack.EquipItemByID(id,slot,isAutoQueue)
	if not id then return end
	if isAutoQueue then
		if ItemRack.ClearManualQueueChoice then
			ItemRack.ClearManualQueueChoice(slot)
		end
	elseif ItemRack.SetManualQueueChoice then
		ItemRack.SetManualQueueChoice(slot, id)
	end
	if ItemRack.NowCasting or InCombatLockdown() or ItemRack.IsPlayerReallyDead() then
		-- If it's already queued, don't toggle it off (which can happen during spamming)
		-- Exception: if id is 0 (empty slot), we allow the toggle to cancel a pending swap.
		if ItemRack.CombatQueue[slot] ~= id or id == 0 then
			ItemRack.AddToCombatQueue(slot,id,isAutoQueue)
		end
	elseif not GetCursorInfo() and not SpellIsTargeting() then
		-- Guard: if a multi-pass set swap is in progress or items are locked,
		-- defer this single-item swap to CombatQueue instead of interfering
		-- with the active swap's lock state (which can cause "Another swap is in progress")
		if ItemRack.SetSwapping or ItemRack.AnythingLocked() then
			ItemRack.Debug("CombatQueue", "EquipItemByID: swap in progress, deferring slot="..tostring(slot).." to queue")
			ItemRack.AddToCombatQueue(slot, id, isAutoQueue)
			return
		end

		local disableSound = ItemRackSettings.DisableSwapSound == "ON"
		local useSound = GetCVar("Sound_EnableSFX")
		local overrideSound = false
		if disableSound and useSound == "1" then
			-- Try surgical muting via LibSoundIndex
			if not ItemRack.MuteSwapSounds(1.5) then
				-- Fallback: blunt CVar mute (silences ALL SFX)
				SetCVar("Sound_EnableSFX", "0")
				overrideSound = true
			end
		end
		
		if id~=0 then -- not an empty slot
			local _,b,s = ItemRack.FindItem(id)
			if b then
				local _,_,isLocked = GetContainerItemInfo(b,s)
				if not isLocked and not IsInventoryItemLocked(slot) then
					-- neither container item nor inventory item locked, perform swap
					local _,_,equipSlot = ItemRack.GetInfoByID(id)
					if equipSlot~="INVTYPE_2HWEAPON" or (ItemRack.HasTitansGrip and not ItemRack.NoTitansGrip[select(7,GetItemInfo(GetContainerItemLink(b,s))) or ""]) or not GetInventoryItemLink("player",17) then
						PickupContainerItem(b,s)
						PickupInventoryItem(slot)
					else
						local bfree,sfree = ItemRack.FindSpace()
						if bfree then
							-- Guard: verify offhand slot isn't locked before the 2H removal sequence
							if IsInventoryItemLocked(17) then
								ItemRack.Debug("CombatQueue", "EquipItemByID: offhand locked during 2H swap, deferring slot="..tostring(slot))
								ItemRack.AddToCombatQueue(slot, id, isAutoQueue)
								return
							end
							PickupInventoryItem(17)
							PickupContainerItem(bfree,sfree)
							PickupContainerItem(b,s)
							PickupInventoryItem(slot)
						else
							ItemRack.Print("Not enough room to perform swap.")
						end
					end
				end
			end
		else
			local b,s = ItemRack.FindSpace()
			if b and not IsInventoryItemLocked(slot) then
				PickupInventoryItem(slot)
				PickupContainerItem(b,s)
			else
				ItemRack.Print("Not enough room to perform swap.")
			end
		end
		
		-- CVar fallback restore
		if overrideSound then
			if ItemRack.CVarMuteTimer then
				ItemRack.CVarMuteTimer:Cancel()
			end
			ItemRack.CVarMuteTimer = C_Timer.NewTimer(1.5, function()
				SetCVar("Sound_EnableSFX", "1")
				ItemRack.CVarMuteTimer = nil
			end)
		end
	end
end

function ItemRack.PollMovement()
	-- If speed is 0, they have landed and lost momentum. Re-evaluate Buffs and stop timer.
	if GetUnitSpeed("player") == 0 then
		ItemRack.ProcessBuffEvent()
		ItemRack.StopTimer("MovementPollingTimer")
	end
end

--[[ Hooks to capture item use outside the mod ]]

function ItemRack.ReflectItemUse(id)
	if ItemRackUser.Buttons[id] then
		local btn = _G["ItemRackButton"..id]
		if btn and btn.OriginalSetChecked then btn:OriginalSetChecked(true) end
		ItemRack.ReflectClicked[id] = 1
		ItemRack.StartTimer("ReflectClickedUpdate")
	end
	local baseID = ItemRack.GetIRString(GetInventoryItemLink("player",id),true,true)
	if baseID then
		ItemRackUser.ItemsUsed[baseID] = 1
		if ItemRack.MarkEquippedQueueItemBurnt and ItemRack.GetQueuesEnabled()[id] then
			ItemRack.MarkEquippedQueueItemBurnt(id, ItemRack.GetID(id), baseID, ItemRack.GetQueues()[id])
		end
	end
end

function ItemRack.newPaperDollFrame_OnShow()
	ItemRack.UpdateCombatQueue()
end

function ItemRack.newUseInventoryItem(slot)
	ItemRack.ReflectItemUse(slot)
end

function ItemRack.newUseAction(slot,cursor,self)
	if IsEquippedAction(slot) then
		local actionType,actionId = GetActionInfo(slot)
		if actionType=="item" then
			for i=0,19 do
				if tonumber(ItemRack.GetIRString(GetInventoryItemLink("player",i),true,true))==actionId then --compare baseID of given item (converted to number) to actionId
					ItemRack.ReflectItemUse(i)
					break
				end
			end
		end
	end
end

function ItemRack.newUseItemByName(name)
	for i=0,19 do
		if name==GetItemInfo(GetInventoryItemLink("player",i) or 0) then
			ItemRack.ReflectItemUse(i)
			break
		end
	end
end

--[[ Combat queue ]]

function ItemRack.IsPlayerReallyDead()
	local dead = UnitIsDeadOrGhost("player")
	if UnitIsFeignDeath("player") then
		dead = false
	end
	return dead
end

function ItemRack.ClearCombatQueueMetadata(slot)
	if ItemRack.AutoQueueFlag then
		ItemRack.AutoQueueFlag[slot] = nil
	end
	if ItemRack.AutoQueueOwner then
		ItemRack.AutoQueueOwner[slot] = nil
	end
end

function ItemRack.AddToCombatQueue(slot,id,isAutoQueue)
	-- Skip if the item is already equipped (prevents oscillation from ID format mismatches
	-- where strict ~= in EquipSet sees a difference but SameID correctly matches)
	if id and id ~= 0 then
		local equippedID = ItemRack.GetID(slot)
		if equippedID and ItemRack.SameID(equippedID, id) then
			return
		end
	end
	local queueOwner = nil
	if isAutoQueue and ItemRack.GetActiveQueueOwner then
		queueOwner = ItemRack.GetActiveQueueOwner(slot)
	end
	ItemRack.AutoQueueFlag = ItemRack.AutoQueueFlag or {}
	ItemRack.AutoQueueOwner = ItemRack.AutoQueueOwner or {}
	if ItemRack.CombatQueue[slot] ~= id or ItemRack.AutoQueueFlag[slot] ~= isAutoQueue or ItemRack.AutoQueueOwner[slot] ~= queueOwner then
		ItemRack.CombatQueue[slot] = id
		ItemRack.AutoQueueFlag[slot] = isAutoQueue
		ItemRack.AutoQueueOwner[slot] = queueOwner
		-- Debug: trace who is adding to CombatQueue
		local itemName = id and id ~= 0 and (ItemRack.GetInfoByID(id) or tostring(id)) or "empty"
		ItemRack.Debug("CombatQueue", "AddToCombatQueue slot="..tostring(slot).." item="..tostring(itemName).." auto="..tostring(isAutoQueue).." owner="..tostring(queueOwner or "global"))
		ItemRack.Debug("CombatQueue", "stack: "..debugstack(2,4,0))
		ItemRack.UpdateCombatQueue()
	end
end

function ItemRack.RemoveFromCombatQueue(slot)
	if ItemRack.CombatQueue[slot] ~= nil then
		ItemRack.CombatQueue[slot] = nil
		ItemRack.ClearCombatQueueMetadata(slot)
		ItemRack.UpdateCombatQueue()
	end
end

function ItemRack.UpdateCombatQueue()
	-- Clean up stale entries: if the queued item is already equipped, remove it
	for slot, queuedID in pairs(ItemRack.CombatQueue) do
		if queuedID and queuedID ~= 0 then
			local equippedID = ItemRack.GetID(slot)
			if equippedID and ItemRack.SameID(equippedID, queuedID) then
				ItemRack.CombatQueue[slot] = nil
				ItemRack.ClearCombatQueueMetadata(slot)
			end
		end
	end
	local queue,id
	for i in pairs(ItemRackUser.Buttons) do
		queue = _G["ItemRackButton"..i.."Queue"]
		if ItemRack.CombatQueue[i] then
			queue:SetTexture(select(2,ItemRack.GetInfoByID(ItemRack.CombatQueue[i])))
			queue:SetAlpha(1)
			queue:Show()
		elseif ItemRack.GetQueuesEnabled()[i] then
			queue:SetTexture("Interface\\AddOns\\ItemRack\\ItemRackGear")
			queue:SetAlpha(ItemRackUser.EnableQueues=="ON" and 1 or .5)
			queue:Show()
		elseif i~=20 then
			queue:Hide()
		end
	end

	for i=1,19 do
		queue = _G["Character"..ItemRack.SlotInfo[i].name.."Queue"]
		if ItemRack.CombatQueue[i] then
			queue:SetTexture(select(2,ItemRack.GetInfoByID(ItemRack.CombatQueue[i])))
			queue:Show()
		else
			queue:Hide()
		end
	end

end

--[[ Tooltip ]]

-- request a tooltip of an inventory slot
function ItemRack.InventoryTooltip(self)
	if ItemRackSettings.ShowTooltips ~= "ON" then return end
	if ItemRackSettings.DisableTooltipsInCombat == "ON" and ItemRack.inCombat then return end
	local id = self:GetID()
	if id==20 then
		ItemRack.SetTooltip(self,ItemRackUser.CurrentSet)
	else
		ItemRack.TooltipOwner = self
		ItemRack.TooltipType = "INVENTORY"
		ItemRack.TooltipSlot = id
		ItemRack.TooltipBag = ItemRack.CombatQueue[id] and ItemRack.GetInfoByID(ItemRack.CombatQueue[id])
		ItemRack.StartTimer("TooltipUpdate",0)
	end
end

-- request a tooltip of a menu item (called when hovering over a button in the popout menu of SET NAMES that comes up when clicking the minimap button or bar addon plugin, this is NOT the "Sets" dropdown INSIDE ItemRack's GUI)
function ItemRack.MenuTooltip(self)
	if ItemRackSettings.ShowTooltips ~= "ON" then return end
	if ItemRackSettings.DisableTooltipsInCombat == "ON" and ItemRack.inCombat then return end
	local id = self:GetID()
	if ItemRack.menuOpen==20 then
		ItemRack.SetTooltip(self,ItemRack.Menu[id])
	else
		ItemRack.TooltipOwner = self
		ItemRack.TooltipType = "BAG"
		local invMaybe
		invMaybe,ItemRack.TooltipBag,ItemRack.TooltipSlot = ItemRack.FindItem(ItemRack.Menu[self:GetID()])
		if ItemRack.TooltipBag and ItemRack.TooltipSlot then
			ItemRack.StartTimer("TooltipUpdate",0)
		else -- if invMaybe then
			ItemRack.IDTooltip(self,ItemRack.Menu[id])
		end
	end
end

-- request a tooltip of a straight item id (called when hovering over items from the currently displayed set inside ItemRack's GUI)
function ItemRack.IDTooltip(self,itemID) --itemID is an ItemRack-style ID
	if ItemRackSettings.ShowTooltips ~= "ON" then return end
	-- Clear any stale character-sheet tooltip anchor so it doesn't interfere
	ItemRack.pendingTooltipAnchor = nil
	ItemRack.pendingTooltipOwner = nil
	ItemRack.AnchorTooltip(self)
	local inv,bag,slot = ItemRack.FindItem(itemID) --try to find the item in the player's equipment and inventory, first tries to find the exact item, then looks for any item with the same baseID
	if inv then -- item found in player's worn equipment
		GameTooltip:SetInventoryItem("player",inv)
	elseif bag then -- item found in player's bags
		GameTooltip:SetBagItem(bag,slot)
	else --cannot find the item in player's inventory or worn equipment!
		bag,slot = ItemRack.FindInBank(itemID) --try to find the item in the player's bank IF they currently have the bank frame open
		if bag then -- item found in player's bank
			if bag == BANK_CONTAINER or bag == -1 then
				GameTooltip:SetInventoryItem("player",BankButtonIDToInvSlotID(slot))
			else
				GameTooltip:SetBagItem(bag,slot)
			end
		else -- item is completely missing (no such strict OR baseID found anywhere): it's not in inventory, bank or worn items
			itemID = ItemRack.IRStringToItemString(ItemRack.UpdateIRString(itemID)) -- ensure the stored ID is brought up to date, then generate a regular ItemString from it which can be used to display the required tooltip
			GameTooltip:SetHyperlink(itemID)
		end
	end
	ItemRack.ShrinkTooltip(self)
	GameTooltip:Show()
	
	-- Suppress WoW's default compare tooltips if MenuOnShift is active
	-- Otherwise holding shift to open the menu covers the screen in 3 tooltips
	if ItemRackSettings.MenuOnShift=="ON" and IsShiftKeyDown() then
		if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
		if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
	end
end

function ItemRack.ClearTooltip(self)
	GameTooltip:Hide()
	ItemRack.StopTimer("TooltipUpdate")
	ItemRack.TooltipType = nil
end

function ItemRack.AnchorTooltip(owner)
	-- Character sheet anchoring: only applies when the menu is docked to a character
	-- sheet slot AND the owner is part of that menu context (a menu popup item or the
	-- character slot itself). This prevents options-panel or quick-access tooltips from
	-- incorrectly snapping to character sheet anchor positions.
	local ownerName = (owner and type(owner.GetName) == "function") and owner:GetName() or ""
	local isCharacterMenuContext = ItemRackMenuFrame and ItemRackMenuFrame:IsVisible()
		and string.match(ItemRack.menuDockedTo or "", "^Character")
		and (string.match(ownerName, "^ItemRackMenu%d") or string.match(ownerName, "^Character"))

	if isCharacterMenuContext then
		local name = ItemRack.menuDockedTo
		local isPopoutButton = string.match(ownerName, "^ItemRackMenu%d")
		local slot
		for i=0,19 do
			if name=="Character"..ItemRack.SlotInfo[i].name then
				slot = i
			end
		end
		
		if slot then
			if isPopoutButton then
				-- Tooltips for items inside the menu:
				-- We measure physical screen space using EffectiveScale for reliable placement on scaled/ultrawide UIs.
				local scale = ItemRackMenuFrame:GetEffectiveScale()
				local right = (ItemRackMenuFrame:GetRight() or 0) * scale
				local left = (ItemRackMenuFrame:GetLeft() or 0) * scale
				
				local spaceRight = GetScreenWidth() - right
				local spaceLeft = left
				
				if spaceRight >= spaceLeft then
					GameTooltip:SetOwner(ItemRackMenuFrame, "ANCHOR_RIGHT")
					ItemRack.pendingTooltipAnchor = "ANCHOR_RIGHT"
				else
					GameTooltip:SetOwner(ItemRackMenuFrame, "ANCHOR_LEFT")
					ItemRack.pendingTooltipAnchor = "ANCHOR_LEFT"
				end

				-- Store vertical owner so ApplyTooltipAnchor can reposition the tooltip
				-- to align with the specific button instead of the top of the menu frame.
				ItemRack.pendingTooltipOwner = ItemRackMenuFrame
				ItemRack.pendingTooltipVerticalOwner = owner
			else
				-- Tooltips for the character sheet slot itself (when hovering the slot while menu is open):
				if slot == 0 or (slot >= 16 and slot <= 18) then
					GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
				elseif slot==1 or slot==2 or slot==3 or slot==15 or slot==5 or slot==4 or slot==19 or slot==9 then
					if ItemRackSettings.LeftSlotsGoRight == "ON" then
						GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
					else
						GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
					end
				else
					if ItemRackSettings.RightSlotsGoLeft == "ON" then
						GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
					else
						GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
					end
				end
			end
		else
			-- Default toolbar buttons: anchor away from nearest screen edge
			if owner:GetCenter() < GetScreenWidth()/2 then
				GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
			else
				GameTooltip:SetOwner(owner,"ANCHOR_LEFT")
			end
		end
	elseif ItemRackSettings.TooltipFollow=="ON" then
		if owner.GetLeft and owner:GetLeft() and owner:GetLeft()<400 then
			GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
		else
			GameTooltip:SetOwner(owner,"ANCHOR_LEFT")
		end
	else
		GameTooltip_SetDefaultAnchor(GameTooltip,owner)
	end
end

-- display the tooltip created in the functions above, once a second if item has a cooldown
function ItemRack.TooltipUpdate()
	if ItemRack.TooltipType then
		local cooldown
		ItemRack.AnchorTooltip(ItemRack.TooltipOwner)
		if ItemRack.TooltipType=="BAG" then
			if ItemRack.TooltipBag == BANK_CONTAINER or ItemRack.TooltipBag == -1 then
				GameTooltip:SetInventoryItem("player",BankButtonIDToInvSlotID(ItemRack.TooltipSlot))
				cooldown = 0
			else
				GameTooltip:SetBagItem(ItemRack.TooltipBag,ItemRack.TooltipSlot)
				cooldown = GetContainerItemCooldown(ItemRack.TooltipBag,ItemRack.TooltipSlot) or 0
			end
		else
			GameTooltip:SetInventoryItem("player",ItemRack.TooltipSlot)
			cooldown = GetInventoryItemCooldown("player",ItemRack.TooltipSlot) or 0
		end
		ItemRack.ShrinkTooltip(ItemRack.TooltipOwner) -- if TinyTooltips on, shrink it
		if ItemRack.TooltipType=="INVENTORY" and ItemRack.TooltipBag then
			GameTooltip:AddLine("Queued: "..ItemRack.TooltipBag)
		end
		GameTooltip:Show()
		
		-- Suppress WoW's default compare tooltips if MenuOnShift is active
		if ItemRackSettings.MenuOnShift=="ON" and IsShiftKeyDown() then
			if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
			if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
		end
		
		if cooldown==0 then
			-- stop updates if this trinket has no cooldown
			ItemRack.StopTimer("TooltipUpdate")
			ItemRack.TooltipType = nil
		end
	end

end

-- normal tooltip for options
function ItemRack.OnTooltip(self,line1,line2)
	if ItemRackSettings.ShowTooltips=="ON" then
		ItemRack.AnchorTooltip(self)
		if line1 then
			GameTooltip:AddLine(line1)
			GameTooltip:AddLine(line2,.8,.8,.8,1)
			GameTooltip:Show()
			return
		else
			local name = self:GetName() or ""
			for i=1,#(ItemRack.TooltipInfo) do
				if ItemRack.TooltipInfo[i][1]==name and ItemRack.TooltipInfo[i][2] then
					GameTooltip:AddLine(ItemRack.TooltipInfo[i][2])
					GameTooltip:AddLine(ItemRack.TooltipInfo[i][3],.8,.8,.8,1)
					GameTooltip:Show()
					return
				end
			end
		end
	end
end

function ItemRack.ShrinkTooltip(owner)
	-- Determine whether this tooltip should be shrunk based on context
	local shouldShrink = false

	if ItemRackSettings.TinyTooltips == "ON" then
		-- Global tiny tooltips: shrink everything
		shouldShrink = true
	else
	-- Check quick-access-only settings
		if ItemRackSettings.TinyTooltipsQuickAccess == "ON" and owner and type(owner.GetName) == "function" then
			local ownerName = owner:GetName() or ""
			-- Only apply tiny tooltips when the menu is docked to a quick access button
			-- (not character sheet popouts, not options panel menus)
			local isQuickAccessContext = ItemRack.menuDockedTo and string.match(ItemRack.menuDockedTo, "^ItemRackButton%d")
			local isMenuPopupItem = string.match(ownerName, "^ItemRackMenu%d")
			local isMainSlotButton = string.match(ownerName, "^ItemRackButton%d")

			if isQuickAccessContext or isMainSlotButton then
				-- Quick access context (docked button or its popup menu)
				if ItemRackSettings.TinyTooltipsSubMenusOnly == "ON" then
					-- Only shrink popup sub-menu items, not the main slot button
					shouldShrink = isMenuPopupItem and true or false
				else
					-- Shrink both main slot buttons and popup items (but not slot 20)
					local ownerID = (type(owner.GetID) == "function") and owner:GetID()
					if isMenuPopupItem then
						shouldShrink = true
					elseif isMainSlotButton and ownerID and ownerID < 20 then
						shouldShrink = true
					end
				end
			end
		end
	end

	if shouldShrink then
		local r,g,b = GameTooltipTextLeft1:GetTextColor()
		local name = GameTooltipTextLeft1:GetText()
		local line,charge,durability,cooldown
		for i=2,GameTooltip:NumLines() do
			line = _G["GameTooltipTextLeft"..i]
			if line:IsVisible() then
				line = line:GetText() or ""
				if string.match(line,ItemRack.DURABILITY_PATTERN) then
					durability = line
				end
				if string.match(line,COOLDOWN_REMAINING) then
					cooldown = line
				end
				for j in pairs(ItemRack.CHARGES_PATTERNS) do
					if string.find(line,ItemRack.CHARGES_PATTERNS[j]) then
						charge = line
					end
				end
			end
		end
		-- Use SetText to clear existing content without re-anchoring
		-- (calling AnchorTooltip here would cause circular anchor errors)
		GameTooltip:SetText(name or "", r, g, b)
		GameTooltip:AddLine(charge,1,1,1)
		GameTooltip:AddLine(durability,1,1,1)
		GameTooltip:AddLine(cooldown,1,1,1)
	end
end

function ItemRack.SetTooltip(self,setname)
	if ItemRackSettings.ShowTooltips ~= "ON" then return end
	local set = setname and ItemRackUser.Sets[setname] and ItemRackUser.Sets[setname].equip
	if set then
		local itemName,itemColor
		ItemRack.AnchorTooltip(self)
		GameTooltip:AddLine(setname)
		if ItemRackSettings.TinyTooltips~="ON" then
			for i=0,19 do
				if set[i] then
					itemName = ItemRack.GetInfoByID(set[i])
					if itemName then
						if itemName~="(empty)" and ItemRack.GetCountByID(set[i])==0 then
							if not ItemRack.FindInBank(set[i]) then
								itemColor = "FFFF1111"
							else
								itemColor = "FF4C80FF"
							end
						elseif itemName~="(empty)" and ItemRackSettings.TooltipColorUnEquipped=="ON" and not ItemRack.SameExactID(ItemRack.GetID(i), set[i]) then
							itemColor = "FFFF8C00"
						else
							itemColor = "FFAAAAAA"
						end
						GameTooltip:AddLine("|cFFFFFFFF"..ItemRack.SlotInfo[i].real..": |c"..itemColor..itemName)
					end
				end
			end
		end
		GameTooltip:Show()
	end
end

--[[ Notify ]]

function ItemRack.Notify(msg)
--	PlaySound("GnomeExploration")
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
	if SCT_Display then -- send via SCT if it exists
		SCT_Display(msg,{r=.2,g=.7,b=.9})
	elseif SHOW_COMBAT_TEXT=="1" then
		CombatText_AddMessage(msg, CombatText_StandardScroll, .2, .7, .9) -- or default UI's SCT
	else
		-- send vis UIErrorsFrame if neither SCT exists
		UIErrorsFrame:AddMessage(msg,.2,.7,.9,1,UIERRORS_HOLD_TIME)
	end
	if ItemRackSettings.NotifyChatAlso=="ON" then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33b2e5"..msg)
	end
end

function ItemRack.CooldownUpdate()
	local inv,bag,slot,start,duration,name,remain
	for i in pairs(ItemRackUser.ItemsUsed) do
		start,duration = GetItemCooldown(i)
		if start and ItemRackUser.ItemsUsed[i]<3 then
			ItemRackUser.ItemsUsed[i] = ItemRackUser.ItemsUsed[i] + 1 -- count for 3 seconds before seeing if this is a real cooldown
		elseif start then
			if start>0 then
				remain = duration - (GetTime()-start)
				if ItemRackUser.ItemsUsed[i]<5 then
					if remain>29 then
						ItemRackUser.ItemsUsed[i] = 30 -- first actual cooldown greater than 30 seconds, tag it for 30+0 notify
					elseif remain>5 then
						ItemRackUser.ItemsUsed[i] = 5 -- first actual cooldown less than 30 but greater than 5, tag for 0 notify
					end
				end
			end
			if ItemRackUser.ItemsUsed[i]==30 and start>0 and remain<30 then
				if ItemRackSettings.NotifyThirty=="ON" then
					name = GetItemInfo(i)
					if name then
						ItemRack.Notify(name.." ready soon!")
					end
				end
				ItemRackUser.ItemsUsed[i]=5 -- tag for just 0 notify now
			elseif ItemRackUser.ItemsUsed[i]==5 and start==0 then
				if ItemRackSettings.Notify=="ON" then
					name = GetItemInfo(i)
					if name then
						ItemRack.Notify(name.." ready!")
					end
				end
			end
			if start==0 then
				ItemRackUser.ItemsUsed[i] = nil
			end
		end
	end

	-- update cooldown numbers
	if ItemRackSettings.CooldownCount=="ON" then
		ItemRack.WriteButtonCooldowns()
		ItemRack.WriteMenuCooldowns()
	end

	if ItemRack.PeriodicQueueCheck then
		ItemRack.PeriodicQueueCheck()
	end
end

--[[ Character sheet menus ]]

ItemRack.oldPaperDollItemSlotButton_OnEnter = PaperDollItemSlotButton_OnEnter
function PaperDollItemSlotButton_OnEnter(self)
	local name = self:GetName()
	local isMenuOpening = ItemRack.menuDockedTo~=name and (ItemRackSettings.MenuOnShift=="OFF" or IsShiftKeyDown()) and ItemRackSettings.CharacterSheetMenus=="ON"
	
	-- We must build the menu BEFORE rendering the tooltip, so ItemRackMenuFrame exists with current dimensions
	if isMenuOpening then
		ItemRack.DockMenuToCharacterSheet(self)
	end

	local isMenuOpen = ItemRackMenuFrame:IsVisible() and ItemRack.menuDockedTo == name
	
	local slot
	for i=0,19 do
		if name=="Character"..ItemRack.SlotInfo[i].name then
			slot = i
			break
		end
	end
	
	-- Hide the tooltip during the Blizzard handler to prevent a visible "snap"
	-- from the default position to our desired position.
	if isMenuOpen and slot then
		GameTooltip:SetAlpha(0)
	end
	
	-- Call the original Blizzard function FIRST, completely untouched.
	-- We MUST NOT modify GameTooltip.SetOwner or any other secure table — doing so
	-- taints the GameTooltip table, which propagates to Blizzard action bar OnEnter
	-- handlers and causes ADDON_ACTION_BLOCKED errors on protected calls like SetShown().
	ItemRack.oldPaperDollItemSlotButton_OnEnter(self)
	
	-- AFTER the secure handler has finished (including any hooksecurefunc hooks like
	-- ListSetsHavingItem which call tooltip:Show()), reposition and reveal the tooltip.
	if isMenuOpen and slot then
		local desiredOwner, desiredAnchor
		
		local menuOnRight = (ItemRackMenuFrame:GetLeft() or 0) >= (self:GetLeft() or 0)
		
		if slot == 0 or (slot >= 16 and slot <= 18) then
			-- Bottom slots: menu goes down. Tooltip to the right is fine.
			desiredOwner = self
			desiredAnchor = "ANCHOR_RIGHT"
		else
			if menuOnRight then
				-- Menu rendered to the right. Tooltip should go left (if room) or chain to the right of the menu.
				if slot==1 or slot==2 or slot==3 or slot==15 or slot==5 or slot==4 or slot==19 or slot==9 then
					-- Left side slots: No room on the left, chain to the right of the menu
					desiredOwner = ItemRackMenuFrame
					desiredAnchor = "ANCHOR_RIGHT"
				else
					-- Right side slots: Abundant room on the left (over character model)
					desiredOwner = self
					desiredAnchor = "ANCHOR_LEFT"
				end
			else
				-- Menu rendered to the left. Tooltip should go right.
				desiredOwner = self
				desiredAnchor = "ANCHOR_RIGHT"
			end
		end
		
		-- Store for re-application after tooltip:Show() in hooks
		ItemRack.pendingTooltipAnchor = desiredAnchor
		ItemRack.pendingTooltipOwner = desiredOwner
		
		-- Apply positioning and reveal
		ItemRack.ApplyTooltipAnchor()
		GameTooltip:SetAlpha(1)
	else
		ItemRack.pendingTooltipAnchor = nil
		ItemRack.pendingTooltipOwner = nil
	end
end

-- Apply the stored tooltip anchor. Called after PaperDollItemSlotButton_OnEnter
-- and again after ListSetsHavingItem's tooltip:Show() which re-snaps the position.
-- Also handles wide tooltips that would overlap the menu by falling back to
-- positioning below or above the menu frame.
function ItemRack.ApplyTooltipAnchor()
	local anchor = ItemRack.pendingTooltipAnchor
	local owner = ItemRack.pendingTooltipOwner
	if not anchor or not owner then return end

	-- Only re-apply if we're still in a character-sheet tooltip context.
	-- If menuDockedTo has changed (e.g. moved to options panel), the pending
	-- anchor is stale and should be discarded.
	if not (ItemRack.menuDockedTo and string.match(ItemRack.menuDockedTo, "^Character")) then
		ItemRack.pendingTooltipAnchor = nil
		ItemRack.pendingTooltipOwner = nil
		return
	end
	
	-- Only apply to ItemRack-related tooltips that aren't the standard action buttons (which handle themselves)
	local tooltipOwner = GameTooltip:GetOwner()
	if not tooltipOwner or not tooltipOwner.GetName then return end
	local ownerName = tooltipOwner:GetName() or ""
	
	-- We want to apply the anchor for Character sheet slots AND for ItemRackMenuFrame / ItemRackOpt menus.
	-- We DO NOT want to apply it for ItemRackButton (the quick access buttons), because they have their own anchoring in ItemRack.InventoryTooltip.
	if ownerName:match("^ItemRackButton") or not (ownerName:match("^Character") or ownerName:match("^ItemRack")) then
		-- Not an ItemRack menu/character tooltip — clear stale pending state
		ItemRack.pendingTooltipAnchor = nil
		ItemRack.pendingTooltipOwner = nil
		return
	end
	
	-- Apply the desired anchor
	GameTooltip:ClearAllPoints()
	local verticalOwner = ItemRack.pendingTooltipVerticalOwner
	if anchor == "ANCHOR_RIGHT" then
		local yOffset = 0
		if verticalOwner and verticalOwner:GetTop() and owner:GetTop() then
			yOffset = verticalOwner:GetTop() - owner:GetTop()
		end
		GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 5, yOffset)
	elseif anchor == "ANCHOR_LEFT" then
		local yOffset = 0
		if verticalOwner and verticalOwner:GetTop() and owner:GetTop() then
			yOffset = verticalOwner:GetTop() - owner:GetTop()
		end
		GameTooltip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -5, yOffset)
	elseif anchor == "ANCHOR_BOTTOMLEFT" then
		GameTooltip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, 0)
	end
end

-- Secure hook to prevent asynchronous addons from ripping the tooltip off our custom Anchor.
-- Every time GameTooltip:Show() natively resets to SetOwner, we instantly snap it back.
hooksecurefunc(GameTooltip, "Show", function(self)
	if ItemRack.pendingTooltipAnchor and ItemRack.pendingTooltipOwner and ItemRackMenuFrame:IsVisible() then
		ItemRack.ApplyTooltipAnchor()
	end
end)

-- Clear the pending anchor immediately when the tooltip natively vanishes,
-- preventing our custom override from randomly hijacking completely unrelated tooltips.
GameTooltip:HookScript("OnHide", function()
	ItemRack.pendingTooltipAnchor = nil
	ItemRack.pendingTooltipOwner = nil
end)

function ItemRack.DockMenuToCharacterSheet(self)
	local name = self:GetName()
	local slot
	for i=0,19 do
		if name=="Character"..ItemRack.SlotInfo[i].name then
			slot = i
		end
	end
	if slot then
		if slot==0 or (slot>=16 and slot<=18) then
			-- Bottom/weapon slots: always dock vertically
			ItemRack.DockWindows("TOPLEFT",self,"BOTTOMLEFT","VERTICAL")
		else
			if slot==14 and ItemRackSettings.TrinketMenuMode=="ON" then
				self = CharacterTrinket0Slot
			end
			-- Left side slots: 1 (Head), 2 (Neck), 3 (Shoulder), 15 (Back), 5 (Chest), 4 (Shirt), 19 (Tabard), 9 (Wrist)
			if slot==1 or slot==2 or slot==3 or slot==15 or slot==5 or slot==4 or slot==19 or slot==9 then
				-- Left-side slots: default LEFT, but can be flipped to RIGHT
				if ItemRackSettings.LeftSlotsGoRight=="ON" then
					ItemRack.DockWindows("TOPLEFT",self,"TOPRIGHT","HORIZONTAL")
				else
					ItemRack.DockWindows("TOPRIGHT",self,"TOPLEFT","HORIZONTAL")
				end
			else
				-- Right-side slots: default RIGHT, but can be flipped to LEFT
				if ItemRackSettings.RightSlotsGoLeft=="ON" then
					ItemRack.DockWindows("TOPRIGHT",self,"TOPLEFT","HORIZONTAL")
				else
					ItemRack.DockWindows("TOPLEFT",self,"TOPRIGHT","HORIZONTAL")
				end
			end
		end
		ItemRack.BuildMenu(slot, nil, 3)
	end
end

--[[ Minimap button ]]

function ItemRack.InitBroker()
	local texture = ItemRack.GetTextureBySlot(20)
	texture = [[Interface\AddOns\ItemRack\ItemRackIcon]]
	ItemRack.Broker = LDB:NewDataObject("ItemRack", {
		type = "launcher",
		text = "ItemRack",
		icon = texture,
		OnClick = ItemRack.MinimapOnClick,
		OnTooltipShow = ItemRack.MinimapOnEnter,
	})
	ItemRackSettings.minimap = ItemRackSettings.minimap or { hide = false }
	LDBIcon:Register("ItemRack", ItemRack.Broker, ItemRackSettings.minimap)
	ItemRack.ShowMinimap()
end

function ItemRack.ShowMinimap()
	if ItemRackSettings.ShowMinimap == "ON" then
		LDBIcon:Show("ItemRack")
	else
		LDBIcon:Hide("ItemRack")
	end
end

function ItemRack.MinimapOnClick(self,button)
	if IsShiftKeyDown() then
		if ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet] then
			ItemRack.UnequipSet(ItemRackUser.CurrentSet)
		end
	elseif IsAltKeyDown() and (button=="RightButton" or ItemRackSettings.AllowHidden=="OFF") then
		ItemRack.ToggleEvents(self)
	elseif button=="LeftButton" then
		if ItemRackMenuFrame:IsVisible() then
			ItemRackMenuFrame:Hide()
		else
			local xpos,ypos = GetCursorPosition()
			if ypos>400 then
				ItemRack.DockWindows("TOPRIGHT",self,"BOTTOMRIGHT","VERTICAL")
			else
				ItemRack.DockWindows("BOTTOMRIGHT",self,"TOPRIGHT","VERTICAL")
			end
			ItemRack.BuildMenu(20, nil, 4)
		end
	elseif (button=="RightButton") then -- Explicitly handle Right Click for options if no modifier
		ItemRack.ToggleOptions(self)
	end
end

function ItemRack.MinimapOnEnter(tooltip)
	if ItemRackSettings.ShowTooltips ~= "ON" or ItemRackSettings.MinimapTooltip ~= "ON" then return end
	
	-- Re-anchor tooltip to avoid covering the menu/frame
	-- We use GetMouseFocus() to find the minimap button frames since LDB doesn't pass the frame
	local owner = GetMouseFocus and GetMouseFocus() or (GetMouseFoci and GetMouseFoci()[1])
	if owner and owner:GetName() and string.find(owner:GetName(), "ItemRack") then 
		tooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
	end

	tooltip:AddLine("ItemRack")
	tooltip:AddLine("Left click: Select a set",.8,.8,.8,1)
	tooltip:AddLine("Right click: Open options",.8,.8,.8,1)
	tooltip:AddLine("Alt left click: Show hidden sets",.8,.8,.8,1)
	tooltip:AddLine("Alt right click: Toggle events",.8,.8,.8,1)
	tooltip:AddLine("Shift click: Unequip this set",.8,.8,.8,1)
end

--[[ Non-LoD options support ]]

function ItemRack.ToggleOptions(self,tab)
	if not ItemRackOptFrame then
		EnableAddOn("ItemRackOptions") -- it's LoD, and required. Enable if disabled
		LoadAddOn("ItemRackOptions")
	end
	if ItemRackOptFrame:IsVisible() then
		ItemRackOptFrame:Hide()
	else
		ItemRackOptFrame:Show()
		if tab then
			ItemRackOpt.TabOnClick(self,tab)
		end
	end
end

function ItemRack.ReflectLock(override)
	if BackdropTemplateMixin then
		Mixin(ItemRackMenuFrame, BackdropTemplateMixin)
	end
	ItemRackMenuFrame:SetBackdrop(
		{
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		}
	);
	if ItemRackUser.Locked=="ON" or override then
		ItemRackMenuFrame:EnableMouse(0)
		ItemRackMenuFrame:SetBackdropBorderColor(0,0,0,0)
		ItemRackMenuFrame:SetBackdropColor(0,0,0,0)
	else
		ItemRackMenuFrame:EnableMouse(1)
		ItemRackMenuFrame:SetBackdropBorderColor(.3,.3,.3,1)
		ItemRackMenuFrame:SetBackdropColor(1,1,1,1)
	end
	if ItemRackOptFrame then
		ItemRackOpt.ListScrollFrameUpdate()
	end
end

function ItemRack.ReflectAlpha()
	if ItemRackButton0 then
		for i=0,20 do
			_G["ItemRackButton"..i]:SetAlpha(ItemRackUser.Alpha)
		end
	end
	ItemRackMenuFrame:SetAlpha(ItemRackUser.Alpha)
end

function ItemRack.ReflectMenuScale(scale)
	scale = scale or ItemRackUser.MenuScale
	ItemRackMenuFrame:SetScale(scale)
end

function ItemRack.SetFont(button)
	local item = _G[button.."Time"]
	if not item then
		return
	end
	if ItemRackSettings.LargeNumbers=="ON" then
		item:SetFont("Fonts\\FRIZQT__.TTF",16,"THICKOUTLINE")
		item:SetTextColor(1,1,1,1)
		item:ClearAllPoints()
		item:SetPoint("CENTER",button,"CENTER")
	else
		item:SetFont("Fonts\\ARIALN.TTF",14,"OUTLINE")
		item:SetTextColor(1,1,1,1)
		item:ClearAllPoints()
		item:SetPoint("BOTTOM",button,"BOTTOM")
	end
end

function ItemRack.ReflectCooldownFont()
	local item
	for i=0,20 do
		ItemRack.SetFont("ItemRackButton"..i)
	end
	local i=1
	while _G["ItemRackMenu"..i] do
		ItemRack.SetFont("ItemRackMenu"..i)
		i=i+1
	end
end

--[[ Hidden menu items ]]

function ItemRack.AddHidden(id)
	if id then
		for i=1,#(ItemRackUser.Hidden) do
			if ItemRackUser.Hidden[i]==id then
				return
			end
		end
		table.insert(ItemRackUser.Hidden,id)
	end
end

function ItemRack.RemoveHidden(id)
	for i=1,#(ItemRackUser.Hidden) do
		if ItemRackUser.Hidden[i]==id then
			table.remove(ItemRackUser.Hidden,i)
			break
		end
	end
end

function ItemRack.IsHidden(id)
	for i=1,#(ItemRackUser.Hidden) do
		if ItemRackUser.Hidden[i]==id then
			return true
		end
	end
	return nil
end

function ItemRack.ToggleHidden(id)
	if ItemRack.IsHidden(id) then
		ItemRack.RemoveHidden(id)
	else
		ItemRack.AddHidden(id)
	end
end

--[[ Key bindings ]]
function ItemRack.SetSetBindings()
	if InCombatLockdown() then
		-- Queue to run after combat ends
		if not ItemRack.RunAfterCombat then ItemRack.RunAfterCombat = {} end
		table.insert(ItemRack.RunAfterCombat, "SetSetBindings")
		return
	end
	local buttonName,button
	local bindingsChanged = false
	for i in pairs(ItemRackUser.Sets) do
		if ItemRackUser.Sets[i].key then
			buttonName = "ItemRack"..UnitName("player")..GetRealmName()..i
			button = _G[buttonName] or CreateFrame("Button",buttonName,nil,"SecureActionButtonTemplate")

			button:SetAttribute("type","macro")
			local macrotext = ""
			for slot = 16, 18 do
				if ItemRackUser.Sets[i].equip[slot] then
					local name,_,_,_,_,_,_,_,_,_ = GetItemInfo("item:"..ItemRackUser.Sets[i].equip[slot])
					if name then
						macrotext = macrotext .. "/equipslot [combat]" .. slot .. " " .. name .. "\n";
					end
				end
			end
			button:SetAttribute("macrotext",macrotext)
			button:SetScript("PostClick", function() ItemRack.RunSetBinding(i) end)
			
			local key = ItemRackUser.Sets[i].key
			
			-- Only import key on first pass if there's no standard binding already. Overwrites game defaults if imported.
			if not ItemRack.BindingsInitialized then
				if not GetBindingKey("CLICK "..buttonName..":LeftButton") then
					SetBindingClick(key, buttonName)
					bindingsChanged = true
				end
			else
				SetBindingClick(key, buttonName)
			end
		end
	end
	
	ItemRack.BindingsInitialized = true
	
	-- Batch-save binding changes once at the end rather than per-key
	if bindingsChanged then
		local bindingSet = GetCurrentBindingSet()
		if bindingSet then
			SaveBindings(bindingSet)
		end
	end
end

function ItemRack.RunSetBinding(setname)
	if ItemRackSettings.EquipToggle=="ON" then
		ItemRack.ToggleSet(setname)
	else
		ItemRack.EquipSet(setname)
	end
end

--[[ Slash Handler ]]

function ItemRack.SlashHandler(arg1)

	if arg1 and string.match(arg1,"equip") then
		local set = string.match(arg1,"equip (.+)")
		if not set then
			ItemRack.Print("Usage: /itemrack equip set name")
			ItemRack.Print("ie: /itemrack equip pvp gear")
		else
			ItemRack.EquipSet(set)
		end
		return
	elseif arg1 and string.match(arg1,"toggle") then
		local sets = string.match(arg1,"toggle (.+)")
		if not sets then
			ItemRack.Print("Usage: /itemrack toggle set name[, second set name]")
			ItemRack.Print("ie: /itemrack toggle pvp gear, tanking set")
		else
			local set1,set2 = string.match(sets,"(.+), ?(.+)")
			if not set1 then
				ItemRack.ToggleSet(sets)
			else
				if ItemRack.IsSetEquipped(set1) then
					ItemRack.EquipSet(set2)
				else
					ItemRack.EquipSet(set1)
				end
			end
		end
		return
	end

	arg1 = string.lower(arg1)

	if arg1=="reset" then
		ItemRack.ResetButtons()
	elseif arg1=="reset everything" then
		ItemRack.ResetEverything()
	elseif arg1=="lock" then
		ItemRackUser.Locked="ON"
		ItemRack.ReflectLock()
	elseif arg1=="unlock" then
		ItemRackUser.Locked="OFF"
		ItemRack.ReflectLock()
	elseif arg1 and string.match(arg1, "^debug") then
		local subcmd = string.match(arg1, "^debug%s+(.+)")
		if subcmd == "chat" then
			ItemRack.DebugChat = not ItemRack.DebugChat
			if ItemRack.DebugChat and not ItemRack.DebugAll then
				ItemRack.DebugAll = true
				ItemRack.DebugTags.Events = true
				ItemRack.DebugTags.Equip = true
				ItemRack.DebugTags.Queue = true
				ItemRack.DebugTags.CombatQueue = true
				ItemRack.DebugTags.API = true
				ItemRack.DebugTags.UI = true
				ItemRack.DebugTags.Combat = true
			end
			ItemRack.Print("Diagnostic debug printing to chat is now "..(ItemRack.DebugChat and "ON" or "OFF"))
		elseif subcmd == "clear" then
			ItemRack.LogBuffer = {}
			ItemRack.Print("Diagnostic log buffer cleared.")
		elseif subcmd == "status" then
			ItemRack.PrintDebugStatus()
		elseif subcmd == "audit" then
			ItemRack.AuditSavedVariables(true)
		elseif subcmd == "help" then
			ItemRack.Print("ItemRack Debug Subcommands:")
			ItemRack.Print("  /itemrack debug : Toggles all debugging (Silent Mode)")
			ItemRack.Print("  /itemrack debug chat : Toggles printing logs directly to chat")
			ItemRack.Print("  /itemrack debug clear : Clears the 5000-line diagnostic log buffer")
			ItemRack.Print("  /itemrack debug status : Shows current status of all debug tags")
			ItemRack.Print("  /itemrack debug audit : Scans and repairs SavedVariables issues")
			ItemRack.Print("  /itemrack debug <tag> : Toggles specific tag (Available: events, equip, queue, combatqueue, api, ui, combat)")
		elseif subcmd then
			-- Toggle specific tag (case insensitive match against known tags)
			local foundTag
			local inputTag = string.lower(subcmd)
			for tag in pairs(ItemRack.DebugTags) do
				if string.lower(tag) == inputTag then
					foundTag = tag
					break
				end
			end
			if not foundTag then
				ItemRack.Print("Invalid debug tag: '" .. tostring(subcmd) .. "'")
				ItemRack.PrintDebugStatus()
			else
				ItemRack.DebugTags[foundTag] = not ItemRack.DebugTags[foundTag]
				ItemRack.Print("Diagnostic tag [|cff00ff00" .. foundTag .. "|r] is now " .. (ItemRack.DebugTags[foundTag] and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
			end
		else
			ItemRack.DebugAll = not ItemRack.DebugAll
			if ItemRack.DebugAll then
				ItemRack.DebugTags.Events = true
				ItemRack.DebugTags.Equip = true
				ItemRack.DebugTags.Queue = true
				ItemRack.DebugTags.CombatQueue = true
				ItemRack.DebugTags.API = true
				ItemRack.DebugTags.UI = true
				ItemRack.DebugTags.Combat = true
				ItemRack.Print("Diagnostic debugging ENABLED for all layers (Silent Mode). Use '/itemrack debug chat' to see traces in chat.")
			else
				ItemRack.DebugTags.Events = false
				ItemRack.DebugTags.Equip = false
				ItemRack.DebugTags.Queue = false
				ItemRack.DebugTags.CombatQueue = false
				ItemRack.DebugTags.API = false
				ItemRack.DebugTags.UI = false
				ItemRack.DebugTags.Combat = false
				ItemRack.Print("Diagnostic debugging DISABLED.")
			end
		end
	elseif arg1=="dump" then
		if not ItemRack.LogBuffer then ItemRack.LogBuffer = {} end
		if not ItemRackLogFrame then
			local f = CreateFrame("Frame", "ItemRackLogFrame", UIParent, "BackdropTemplate")
			f:SetSize(750, 500)
			f:SetPoint("CENTER")
			f:SetFrameStrata("DIALOG")
			f:EnableMouse(true)
			f:SetMovable(true)
			f:RegisterForDrag("LeftButton")
			f:SetScript("OnDragStart", f.StartMoving)
			f:SetScript("OnDragStop", f.StopMovingOrSizing)
			f:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=16, insets={left=4,right=4,top=4,bottom=4}})
			f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
			
			local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
			closeBtn:SetPoint("TOPRIGHT", -5, -5)
			
			local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			title:SetPoint("TOP", 0, -10)
			title:SetText("ItemRack Diagnostic Log & SavedVariables Dump (CTRL+C to Copy)")
			
			local sf = CreateFrame("ScrollFrame", "ItemRackLogScrollFrame", f, "UIPanelScrollFrameTemplate")
			sf:SetPoint("TOPLEFT", 15, -35)
			sf:SetPoint("BOTTOMRIGHT", -35, 15)
			
			local eb = CreateFrame("EditBox", "ItemRackLogEditBox", sf)
			eb:SetMultiLine(true)
			eb:SetFontObject("ChatFontNormal")
			eb:SetWidth(680)
			eb:SetAutoFocus(true)
			eb:SetScript("OnEscapePressed", function(self) ItemRackLogFrame:Hide() end)
			sf:SetScrollChild(eb)
			
			-- Helper function to serialize WoW tables to string
			function f.Serialize(val, indent)
				indent = indent or ""
				if type(val) == "string" then
					return string.format("%q", val)
				elseif type(val) == "number" or type(val) == "boolean" then
					return tostring(val)
				elseif type(val) == "table" then
					local res = "{\n"
					local nextIndent = indent .. "  "
					for k, v in pairs(val) do
						local keyStr
						if type(k) == "number" then
							keyStr = "[" .. k .. "]"
						elseif type(k) == "string" then
							keyStr = "[\"" .. k .. "\"]"
						else
							keyStr = "[" .. tostring(k) .. "]"
						end
						res = res .. nextIndent .. keyStr .. " = " .. f.Serialize(v, nextIndent) .. ",\n"
					end
					res = res .. indent .. "}"
					return res
				else
					return '"' .. tostring(val) .. '"'
				end
			end
		end
		local dumpText = "=== ITEMRACK LOG BUFFER ===\n" .. table.concat(ItemRack.LogBuffer, "\n")
		
		dumpText = dumpText .. "\n\n=== RUNTIME STATE DUMP ===\n"
		dumpText = dumpText .. "ItemRack.Version = " .. tostring(ItemRack.Version) .. "\n"
		dumpText = dumpText .. "ItemRack.BuildID = " .. tostring(ItemRack.BuildID) .. "\n"
		dumpText = dumpText .. "InCombatLockdown() = " .. tostring(InCombatLockdown()) .. "\n"
		dumpText = dumpText .. "ItemRack.menuOpen = " .. tostring(ItemRack.menuOpen) .. "\n"
		dumpText = dumpText .. "ItemRackMenuFrame:IsVisible() = " .. tostring(ItemRackMenuFrame and ItemRackMenuFrame:IsVisible()) .. "\n"
		dumpText = dumpText .. "ItemRack.CombatQueue = " .. ItemRackLogFrame.Serialize(ItemRack.CombatQueue) .. "\n"
		dumpText = dumpText .. "ItemRack.SetSwapping = " .. tostring(ItemRack.SetSwapping) .. "\n"
		dumpText = dumpText .. "ItemRack.DebugAll = " .. tostring(ItemRack.DebugAll) .. "\n"
		dumpText = dumpText .. "ItemRack.DebugChat = " .. tostring(ItemRack.DebugChat) .. "\n"
		dumpText = dumpText .. "ItemRack.DebugTags = " .. ItemRackLogFrame.Serialize(ItemRack.DebugTags) .. "\n"
		dumpText = dumpText .. "ItemRackUser.Locked = " .. tostring(ItemRackUser.Locked) .. "\n"
		dumpText = dumpText .. "ItemRackUser.Buttons = " .. ItemRackLogFrame.Serialize(ItemRackUser.Buttons) .. "\n"
		dumpText = dumpText .. "ItemRackUser.CurrentSet = " .. tostring(ItemRackUser.CurrentSet) .. "\n"
		dumpText = dumpText .. "ItemRackUser.EventStack = " .. ItemRackLogFrame.Serialize(ItemRackUser.EventStack) .. "\n"
		dumpText = dumpText .. "ItemRackUser.QueuesEnabled = " .. ItemRackLogFrame.Serialize(ItemRackUser.QueuesEnabled) .. "\n"
		dumpText = dumpText .. "ItemRackUser.Sets['~Unequip'] = " .. ItemRackLogFrame.Serialize(ItemRackUser.Sets["~Unequip"]) .. "\n"
		if ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet] then
			dumpText = dumpText .. "ItemRackUser.Sets['" .. ItemRackUser.CurrentSet .. "'] = " .. ItemRackLogFrame.Serialize(ItemRackUser.Sets[ItemRackUser.CurrentSet]) .. "\n"
		end

		dumpText = dumpText .. "\n=== LAST AUDIT ===\n"
		dumpText = dumpText .. "ItemRackUser.LastAudit = " .. ItemRackLogFrame.Serialize(ItemRackUser.LastAudit) .. "\n"

		dumpText = dumpText .. "\n=== LAST REPAIR ===\n"
		dumpText = dumpText .. "ItemRackUser.LastRepair = " .. ItemRackLogFrame.Serialize(ItemRackUser.LastRepair) .. "\n"

		dumpText = dumpText .. "\n=== SETTINGS ===\n"
		local optInfoSettings = {
			-- User Settings (ItemRackUser)
			{ name = "ItemRackUser.Locked", val = ItemRackUser.Locked },
			{ name = "ItemRackUser.EnableEvents", val = ItemRackUser.EnableEvents },
			{ name = "ItemRackUser.EnableQueues", val = ItemRackUser.EnableQueues },
			{ name = "ItemRackUser.EnablePerSetQueues", val = ItemRackUser.EnablePerSetQueues },
			{ name = "ItemRackUser.EnableQueueContextCheck", val = ItemRackUser.EnableQueueContextCheck },
			{ name = "ItemRackUser.ButtonSpacing", val = ItemRackUser.ButtonSpacing },
			{ name = "ItemRackUser.Alpha", val = ItemRackUser.Alpha },
			{ name = "ItemRackUser.MainScale", val = ItemRackUser.MainScale },
			{ name = "ItemRackUser.MenuScale", val = ItemRackUser.MenuScale },
			{ name = "ItemRackUser.SetMenuWrap", val = ItemRackUser.SetMenuWrap },
			{ name = "ItemRackUser.SetMenuWrapValue", val = ItemRackUser.SetMenuWrapValue },
			
			-- Global Settings (ItemRackSettings)
			{ name = "ItemRackSettings.MenuOnShift", val = ItemRackSettings.MenuOnShift },
			{ name = "ItemRackSettings.MenuOnRight", val = ItemRackSettings.MenuOnRight },
			{ name = "ItemRackSettings.RightClickUse", val = ItemRackSettings.RightClickUse },
			{ name = "ItemRackSettings.HideOOC", val = ItemRackSettings.HideOOC },
			{ name = "ItemRackSettings.HidePetBattle", val = ItemRackSettings.HidePetBattle },
			{ name = "ItemRackSettings.HideArena", val = ItemRackSettings.HideArena },
			{ name = "ItemRackSettings.AllowEmpty", val = ItemRackSettings.AllowEmpty },
			{ name = "ItemRackSettings.AllowHidden", val = ItemRackSettings.AllowHidden },
			{ name = "ItemRackSettings.HideTradables", val = ItemRackSettings.HideTradables },
			{ name = "ItemRackSettings.DisableAltClick", val = ItemRackSettings.DisableAltClick },
			
			-- Cooldown Settings
			{ name = "ItemRackSettings.Notify", val = ItemRackSettings.Notify },
			{ name = "ItemRackSettings.NotifyThirty", val = ItemRackSettings.NotifyThirty },
			{ name = "ItemRackSettings.NotifyChatAlso", val = ItemRackSettings.NotifyChatAlso },
			{ name = "ItemRackSettings.CooldownCount", val = ItemRackSettings.CooldownCount },
			{ name = "ItemRackSettings.LargeNumbers", val = ItemRackSettings.LargeNumbers },
			{ name = "ItemRackSettings.Cooldown90", val = ItemRackSettings.Cooldown90 },
			
			-- Tooltip Settings
			{ name = "ItemRackSettings.ShowTooltips", val = ItemRackSettings.ShowTooltips },
			{ name = "ItemRackSettings.ShowSetInTooltip", val = ItemRackSettings.ShowSetInTooltip },
			{ name = "ItemRackSettings.TooltipColorUnEquipped", val = ItemRackSettings.TooltipColorUnEquipped },
			{ name = "ItemRackSettings.TinyTooltips", val = ItemRackSettings.TinyTooltips },
			{ name = "ItemRackSettings.TinyTooltipsQuickAccess", val = ItemRackSettings.TinyTooltipsQuickAccess },
			{ name = "ItemRackSettings.TinyTooltipsSubMenusOnly", val = ItemRackSettings.TinyTooltipsSubMenusOnly },
			{ name = "ItemRackSettings.DisableTooltipsInCombat", val = ItemRackSettings.DisableTooltipsInCombat },
			{ name = "ItemRackSettings.TooltipFollow", val = ItemRackSettings.TooltipFollow },
			
			-- Interface & Misc
			{ name = "ItemRackSettings.ShowMinimap", val = ItemRackSettings.ShowMinimap },
			{ name = "ItemRackSettings.MinimapTooltip", val = ItemRackSettings.MinimapTooltip },
			{ name = "ItemRackSettings.TrinketMenuMode", val = ItemRackSettings.TrinketMenuMode },
			{ name = "ItemRackSettings.AnchorOther", val = ItemRackSettings.AnchorOther },
			{ name = "ItemRackSettings.EquipToggle", val = ItemRackSettings.EquipToggle },
			{ name = "ItemRackSettings.ShowHotKeys", val = ItemRackSettings.ShowHotKeys },
			{ name = "ItemRackSettings.EquipOnSetPick", val = ItemRackSettings.EquipOnSetPick },
			{ name = "ItemRackSettings.CharacterSheetMenus", val = ItemRackSettings.CharacterSheetMenus },
			{ name = "ItemRackSettings.LeftSlotsGoRight", val = ItemRackSettings.LeftSlotsGoRight },
			{ name = "ItemRackSettings.RightSlotsGoLeft", val = ItemRackSettings.RightSlotsGoLeft },
		}
		
		local printedKeys = {}
		for _, item in ipairs(optInfoSettings) do
			local cleanKey = item.name:match("^ItemRackSettings%.(.+)$")
			if cleanKey then
				printedKeys[cleanKey] = true
			end
			dumpText = dumpText .. item.name .. " = " .. tostring(item.val) .. "\n"
		end
		
		dumpText = dumpText .. "-- Other Settings:\n"
		local otherKeys = {}
		for k in pairs(ItemRackSettings) do
			if not printedKeys[k] then
				table.insert(otherKeys, k)
			end
		end
		table.sort(otherKeys)
		for _, k in ipairs(otherKeys) do
			dumpText = dumpText .. "ItemRackSettings." .. k .. " = " .. tostring(ItemRackSettings[k]) .. "\n"
		end

		dumpText = dumpText .. "\n=== EVENTS STATE ===\n"
		if ItemRackUser.Events then
			dumpText = dumpText .. "ItemRackUser.Events.Enabled = " .. ItemRackLogFrame.Serialize(ItemRackUser.Events.Enabled) .. "\n"
			dumpText = dumpText .. "ItemRackUser.Events.Set = " .. ItemRackLogFrame.Serialize(ItemRackUser.Events.Set) .. "\n"
		end
		if ItemRackEvents then
			dumpText = dumpText .. "ItemRackEvents = " .. ItemRackLogFrame.Serialize(ItemRackEvents) .. "\n"
		end
		local setNames = {}
		for name in pairs(ItemRackUser.Sets) do
			table.insert(setNames, name)
		end
		table.sort(setNames)
		dumpText = dumpText .. "ConfiguredSets = " .. ItemRackLogFrame.Serialize(setNames) .. "\n"

		dumpText = dumpText .. "\n=== CASTING STATE ===\n"
		dumpText = dumpText .. "ItemRack.NowCasting = " .. tostring(ItemRack.NowCasting) .. "\n"
		dumpText = dumpText .. "ItemRack.NowChannelingSpell = " .. tostring(ItemRack.NowChannelingSpell) .. "\n"
		dumpText = dumpText .. "ItemRack.SetsWaiting = " .. ItemRackLogFrame.Serialize(ItemRack.SetsWaiting) .. "\n"
		
		ItemRackLogFrame:Show()
		ItemRackLogEditBox:SetText(dumpText)
		ItemRackLogEditBox:HighlightText()
		ItemRackLogEditBox:SetFocus()
	elseif arg1=="opt" or arg1=="options" or arg1=="config" then
		ItemRack.ToggleOptions()
	else
		ItemRack.Print("/itemrack opt : summons options window.")
		ItemRack.Print("/itemrack equip set name : equip set 'set name'.")
		ItemRack.Print("/itemrack toggle set name[, second set] : toggles set 'set name'.")
		ItemRack.Print("/itemrack reset : resets buttons and their settings.")
		ItemRack.Print("/itemrack reset everything : wipes ItemRack to default.")
		ItemRack.Print("/itemrack lock/unlock : locks/unlocks the buttons.")
	end

end

--[[ Bank Support ]]

-- returns 1 if the set has a banked item, 0 if there is an item missing entirely, nil if item is on person
function ItemRack.MissingItems(setname)
	local missing
	if not setname or not ItemRackUser.Sets[setname] then return end
	for _,i in pairs(ItemRackUser.Sets[setname].equip) do
		if i~=0 and ItemRack.GetCountByID(i)==0 then
			missing = 0
			if ItemRack.FindInBank(i) then
				return 1
			end
		end
	end
	return missing
end

-- pulls setname from bank to bags
function ItemRack.GetBankedSet(setname)
	if ItemRack.MissingItems(setname)~=1 or SpellIsTargeting() or GetCursorInfo() then return end
	local bag,slot,freeBag,freeSlot
	ItemRack.ClearLockList()
	for _,i in pairs(ItemRackUser.Sets[setname].equip) do
		bag,slot = ItemRack.FindInBank(i)
		if bag then
			freeBag,freeSlot = ItemRack.FindSpace()
			if freeBag then
				PickupContainerItem(bag,slot)
				PickupContainerItem(freeBag,freeSlot)
			else
				ItemRack.Print("Not enough room in bags to pull all items from '"..setname.."'.")
				return
			end
		end
	end
end

-- pushes setname from bags/worn to bank
function ItemRack.PutBankedSet(setname)
	if SpellIsTargeting() or GetCursorInfo() then return end
	local inv,bag,slot,freeBag,freeSlot
	ItemRack.ClearLockList()
	for _,i in pairs(ItemRackUser.Sets[setname].equip) do
		if i~=0 then
			freeBag,freeSlot = ItemRack.FindBankSpace()
			if freeBag then
				inv,bag,slot = ItemRack.FindItem(i)
				if inv then
					PickupInventoryItem(inv)
				elseif bag then
					PickupContainerItem(bag,slot)
				end
				if CursorHasItem() then
					PickupContainerItem(freeBag,freeSlot)
				end
			else
				ItemRack.Print("Not enough room in bank to store all items from '"..setname.."'.")
				return
			end
		end
	end
end

function ItemRack.ResetEverything()
	StaticPopupDialogs["ItemRackCONFIRMRESET"] = {
		text = "This will restore ItemRack to its default state, wiping all sets, buttons, events and settings.\nThe UI will be reloaded. Continue?",
		button1 = "Yes", button2 = "No", timeout = 0, hideOnEscape = 1, showAlert = 1,
		OnAccept = function() ItemRackUser=nil ItemRackSettings=nil ItemRackEvents=nil ReloadUI() end
	}
	StaticPopup_Show("ItemRackCONFIRMRESET")
end

-- if cpu profiling on, this will add a page to TinyPad with each ItemRack.func()'s time
function ItemRack.ProfileFuncs()
	if TinyPadPages then
		UpdateAddOnCPUUsage()
		local total = 0
		local t = {}
		local whole,decimal
		for i in pairs(ItemRack) do
			if type(ItemRack[i])=="function" then
				whole = GetFunctionCPUUsage(ItemRack[i])
				decimal = whole - math.floor(whole)
				whole = math.floor(whole)
				table.insert(t,string.format("%04d.%02d %s",whole,decimal,i))
			end
		end
		table.sort(t)
		local info = "ItemRack profile "..date().." "..UnitName("player").."\n"
		for i=1,#(t) do
			info = info..t[i].."\n"
		end
		table.insert(TinyPadPages,info)
	end
end

-- Per-slot queue inheritance helper.
-- Walks the event stack backwards (most recent event first) to find queue data
-- for a slot that the current set doesn't define.  This ensures that event sets
-- which only touch a few slots (e.g., a mount set with 1 trinket) don't wipe
-- out the auto-queue state for every other slot.
local function resolveSlotFromStack(field, slot)
	local stack = ItemRackUser.EventStack
	if stack then
		for i = #stack, 1, -1 do
			local evtName = stack[i]
			local evtSetName = (ItemRack.GetEventSet and ItemRack.GetEventSet(evtName)) or ItemRackUser.Events.Set[evtName]
			if evtSetName then
				local evtSet = ItemRackUser.Sets[evtSetName]
				if evtSet and evtSet[field] and evtSet[field][slot] ~= nil then
					return evtSet[field][slot]
				end
			end
		end
	end
	return nil
end

local function setOwnsQueueSlot(setData, slot)
	return setData and (
		(setData.QueuesEnabled and setData.QueuesEnabled[slot] ~= nil) or
		(setData.Queues and setData.Queues[slot] ~= nil) or
		(setData.equip and setData.equip[slot] ~= nil)
	)
end

-- Returns the set currently providing queue context for a slot.
-- `false` means the slot is currently using the global queue tables.
function ItemRack.GetActiveQueueOwner(slot, setname)
	if ItemRackUser.EnablePerSetQueues ~= "ON" then
		return false
	end

	local targetSet = setname or ItemRackUser.CurrentSet
	local currentSet = targetSet and ItemRackUser.Sets[targetSet]
	if currentSet and setOwnsQueueSlot(currentSet, slot) then
		return targetSet
	end

	if setname or ItemRackUser.EnableQueueContextCheck ~= "ON" then
		return false
	end

	local stack = ItemRackUser.EventStack
	if stack then
		for i = #stack, 1, -1 do
			local evtName = stack[i]
			local evtSetName = (ItemRack.GetEventSet and ItemRack.GetEventSet(evtName)) or ItemRackUser.Events.Set[evtName]
			if evtSetName and evtSetName ~= targetSet then
				local evtSet = ItemRackUser.Sets[evtSetName]
				if setOwnsQueueSlot(evtSet, slot) then
					return evtSetName
				end
			end
		end
	end

	return false
end

-- returns Queues for the current set if EnablePerSetQueues is enabled, otherwise the global Queues
-- Does NOT lazily create empty tables — that's SetupQueue's job
--
-- When called WITHOUT an explicit setname (active context), returns a per-slot
-- inheritance proxy: current set → event stack sets → global.  This prevents
-- event sets that only define a few slots from clearing the queue state of
-- every other slot.
--
-- When called WITH an explicit setname (editing, saving, checking a specific
-- set), returns that set's raw queue data directly — no inheritance.
function ItemRack.GetQueues(setname)
	if ItemRackUser.EnablePerSetQueues == "ON" then
		local targetSet = setname or ItemRackUser.CurrentSet
		local currentSet = targetSet and ItemRackUser.Sets[targetSet]
		if currentSet and currentSet.Queues then
			-- Explicit setname, or context check disabled: return raw data
			if setname or ItemRackUser.EnableQueueContextCheck ~= "ON" then
				return currentSet.Queues
			end
			-- Active context: per-slot inheritance via metatable
			return setmetatable({}, {
				__index = function(_, slot)
					if currentSet.Queues[slot] ~= nil then
						return currentSet.Queues[slot]
					end
					if currentSet.equip and currentSet.equip[slot] ~= nil then
						return nil
					end
					local inherited = resolveSlotFromStack("Queues", slot)
					if inherited ~= nil then
						return inherited
					end
					return ItemRackUser.Queues[slot]
				end,
				__newindex = function(_, slot, value)
					currentSet.Queues[slot] = value
				end
			})
		end
		return ItemRackUser.Queues -- fallback to global if set has no queues
	else
		return ItemRackUser.Queues
	end
end

-- returns QueuesEnabled for the current set if EnablePerSetQueues is enabled, otherwise the global QueuesEnabled
-- Does NOT lazily create empty tables — that's SetupQueue/SaveSet's job
--
-- Same per-slot inheritance logic as GetQueues (see above).
function ItemRack.GetQueuesEnabled(setname)
	if ItemRackUser.EnablePerSetQueues == "ON" then
		local targetSet = setname or ItemRackUser.CurrentSet
		local currentSet = targetSet and ItemRackUser.Sets[targetSet]
		if currentSet and currentSet.QueuesEnabled then
			-- Explicit setname, or context check disabled: return raw data
			if setname or ItemRackUser.EnableQueueContextCheck ~= "ON" then
				return currentSet.QueuesEnabled
			end
			return setmetatable({}, {
				__index = function(_, slot)
					if currentSet.QueuesEnabled[slot] ~= nil then
						return currentSet.QueuesEnabled[slot]
					end
					if currentSet.equip and currentSet.equip[slot] ~= nil then
						return nil
					end
					local inherited = resolveSlotFromStack("QueuesEnabled", slot)
					if inherited ~= nil then
						return inherited
					end
					return ItemRackUser.QueuesEnabled[slot]
				end,
				__newindex = function(_, slot, value)
					currentSet.QueuesEnabled[slot] = value
				end
			})
		end
		return ItemRackUser.QueuesEnabled -- fallback to global if set has no queuesEnabled
	else
		return ItemRackUser.QueuesEnabled
	end
end

ItemRack.DefaultSettings = {}
for k, v in pairs(ItemRackSettings) do
	ItemRack.DefaultSettings[k] = v
end
