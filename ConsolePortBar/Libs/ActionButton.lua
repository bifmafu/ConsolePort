--[[
This library is a rewrite of LibActionButton-1.0, originally by
Hendrik "nevcairiel" Leppkes (h.leppkes@gmail.com), used in Bartender4. 
https://www.curseforge.com/wow/addons/libactionbutton-1-0

This version is heavily modified for ConsolePort and removes the use of LibStub/CallbackHandler
to make sure ConsolePort is using a separate button registry in case other action bar addons are
simultaneously loaded. Do not copy or use this library for anything else.
]]

local _, ab = ...
local db = ConsolePort:GetData()
local lib = {}
ab.libs = ab.libs or {}
ab.libs.acb = lib

local UIFrameFadeIn = db.UIFrameFadeIn
local UIFrameFadeOut = db.UIFrameFadeOut

-- Lua functions
local type, error, tostring, tonumber, assert, select = type, error, tostring, tonumber, assert, select
local setmetatable, wipe, unpack, pairs, next = setmetatable, wipe, unpack, pairs, next
local str_match, format, tinsert, tremove = string.match, format, tinsert, tremove

-- Libs
local LBG = ab.libs.glow

lib.eventFrame = lib.eventFrame or CreateFrame("Frame")
lib.eventFrame:UnregisterAllEvents()

lib.buttonRegistry = lib.buttonRegistry or {}
lib.activeButtons = lib.activeButtons or {}
lib.actionButtons = lib.actionButtons or {}
lib.nonActionButtons = lib.nonActionButtons or {}

lib.ChargeCooldowns = lib.ChargeCooldowns or {}
lib.NumChargeCooldowns = lib.NumChargeCooldowns or 0

lib.ACTION_HIGHLIGHT_MARKS = lib.ACTION_HIGHLIGHT_MARKS or setmetatable({}, { __index = ACTION_HIGHLIGHT_MARKS })

-- Meta function map
local Generic 	= CreateFrame("CheckButton")
local Action 	= setmetatable({}, {__index = Generic})
local Spell 	= setmetatable({}, {__index = Generic})
local Item 		= setmetatable({}, {__index = Generic})
local Macro 	= setmetatable({}, {__index = Generic})
local Custom 	= setmetatable({}, {__index = Generic})

local Generic_MT = {__index = Generic}
local Action_MT = {__index = Action}
local Spell_MT 	= {__index = Spell}
local Item_MT 	= {__index = Item}
local Macro_MT 	= {__index = Macro}
local Custom_MT = {__index = Custom}

local type_meta_map = {
	empty  = Generic_MT,
	action = Action_MT,
	spell  = Spell_MT,
	item   = Item_MT,
	macro  = Macro_MT,
	custom = Custom_MT
}

local ButtonRegistry, ActiveButtons, ActionButtons, NonActionButtons = lib.buttonRegistry, lib.activeButtons, lib.actionButtons, lib.nonActionButtons

-- Local functions
local Update, UpdateButtonState, UpdateUsable, UpdateCount, UpdateCooldown, UpdateTooltip, UpdateNewAction, UpdatePage
local StartFlash, StopFlash, UpdateFlash, UpdateRangeTimer, UpdateOverlayGlow
local UpdateFlyout, ShowGrid, HideGrid, SetupSecureSnippets, WrapOnClick
local ShowOverlayGlow, HideOverlayGlow
local EndChargeCooldown

local InitializeEventHandler, OnEvent, ForAllButtons, OnUpdate

local DefaultConfig = {
	tooltip = "enabled",
	showGrid = true,
	colors = {
		range = { 0.8, 0.1, 0.1 },
		mana = { 0.5, 0.5, 1.0 }
	},
	hideElements = {
		macro = false,
		equipped = false,
	},
	keyBoundTarget = false,
	clickOnDown = false,
	flyoutDirection = "UP",
}

--- Create a new action button.
-- @param id Internal id of the button
-- @param name Name of the button frame to be created
-- @param header Header that drives these action buttons (if any)
function lib:CreateButton(id, name, header, config)
	local templates = "SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate, CPUIActionButtonTemplate"
	local button = setmetatable(CreateFrame("CheckButton", name, header, templates), Generic_MT)

	button:RegisterForDrag("LeftButton", "RightButton")
	button:RegisterForClicks("AnyUp", "AnyDown")

	-- Frame Scripts
	button:HookScript("OnEnter", Generic.OnEnter)
	button:HookScript("OnLeave", Generic.OnLeave)
	button:HookScript("PreClick", Generic.PreClick)
	button:HookScript("PostClick", Generic.PostClick)

	button.id = id
	button.header = header
	-- Mapping of state -> action
	button.state_types = {}
	button.state_actions = {}

	SetupSecureSnippets(button)
	WrapOnClick(button)

	-- adjust count/stack size
	button.Count:SetFont(button.Count:GetFont(), 16, "OUTLINE")

	-- Store the button in the registry, needed for event and OnUpdate handling
	if not next(ButtonRegistry) then
		InitializeEventHandler()
	end
	ButtonRegistry[button] = true

	button:UpdateConfig(config)

	-- run an initial update
	button:UpdateAction()

	-- somewhat of a hack for the Flyout buttons to not error.
	button.action = 0

	return button
end

function SetupSecureSnippets(button)
	button:Execute([[States = newtable("CTRL-SHIFT-", "CTRL-", "SHIFT-", "")]])
	button:SetAttribute("_custom", Custom.RunCustom)
	-- secure UpdateState(self, state)
	-- update the type and action of the button based on the state
	button:SetAttribute("UpdateState", [[
		local state = ...
		local _type = type

		self:SetAttribute("state", state)
		local type, action = (self:GetAttribute(format("labtype-%s", state)) or "empty"), self:GetAttribute(format("labaction-%s", state))

		self:SetAttribute("type", type)
		if type ~= "empty" and type ~= "custom" then
			local action_field = (type == "pet") and "action" or type
			self:SetAttribute(action_field, action)
			self:SetAttribute("action_field", action_field)
		end
		self:SetID((type == "action" and _type(action) == "number" and action <= 12 and action) or 0)
		if self:GetID() > 0 then
			self:CallMethod("ButtonContentsChanged", state, type, action + ((self:GetAttribute('actionpage') - 1) * 12))
		end
		local onStateChanged = self:GetAttribute("OnStateChanged")
		if onStateChanged then
			self:Run(onStateChanged, state, type, action)
		end
	]])

	button:SetAttribute("actionpage", 1)

	-- this function is invoked by the header when the state changes
	button:SetAttribute("_childupdate-state", [[
		self:RunAttribute("UpdateState", message)
		self:CallMethod("UpdateAction")
	]])

	button:SetAttribute("_childupdate-actionpage", [[
		self:SetAttribute('actionpage', message)
		if self:GetID() > 0 then
			local state = self:GetAttribute("state")
			local kind, value = (self:GetAttribute(format("labtype-%s", state)) or "empty"), self:GetAttribute(format("labaction-%s", state))
			self:CallMethod("ButtonContentsChanged", state, kind, value + ((message - 1) * 12))
		end
	]])

	button:SetAttribute("_childupdate-hover", [[
		self:CallMethod("Hover", message)
	]])

	button:SetAttribute("_onenter", [[
		self:CallMethod("SetClicks", true)
	]])

	button:SetAttribute("_onleave", [[
		self:CallMethod("SetClicks", false)
	]])

	-- secure PickupButton(self, kind, value, ...)
	-- utility function to place a object on the cursor
	button:SetAttribute("PickupButton", [[
		local kind, value = ...
		if kind == "empty" then
			return "clear"
		elseif kind == "action" or kind == "pet" then
			local actionType = (kind == "pet") and "petaction" or kind
			return actionType, value
		elseif kind == "spell" or kind == "item" or kind == "macro" then
			return "clear", kind, value
		else
			print("ActionButton: Unknown type: " .. tostring(kind))
			return false
		end
	]])

	button:SetAttribute("OnDragStart", [[
		if (self:GetAttribute("buttonlock") and not IsModifiedClick("PICKUPACTION")) or self:GetAttribute("disableDragNDrop") then return false end
		local state = self:GetAttribute("state")
		local type = self:GetAttribute("type")
		-- if the button is empty, we can't drag anything off it
		if type == "empty" or type == "custom" then
			return false
		end
		-- Get the value for the action attribute
		local action_field = self:GetAttribute("action_field")
		local action = self:GetAttribute(action_field)

		-- non-action fields need to change their type to empty
		if type ~= "action" and type ~= "pet" then
			self:SetAttribute(format("labtype-%s", state), "empty")
			self:SetAttribute(format("labaction-%s", state), nil)
			-- update internal state
			self:RunAttribute("UpdateState", state)
			-- send a notification to the insecure code
			self:CallMethod("ButtonContentsChanged", state, "empty", nil)
		end			
		if self:GetID() > 0 then
			action = action + ((self:GetAttribute('actionpage') - 1) * 12)
		end
		-- return the button contents for pickup
		return self:RunAttribute("PickupButton", type, action)
	]])

	button:SetAttribute("OnReceiveDrag", [[
		if self:GetAttribute("disableDragNDrop") then return false end
		local kind, value, subtype, extra = ...
		if not kind or not value then return false end
		local state = self:GetAttribute("state")
		local buttonType, buttonAction = self:GetAttribute("type"), nil
		if buttonType == "custom" then return false end
		-- action buttons can do their magic themself
		-- for all other buttons, we'll need to update the content now
		if buttonType ~= "action" and buttonType ~= "pet" then
			-- with "spell" types, the 4th value contains the actual spell id
			if kind == "spell" then
				if extra then
					value = extra
				else
					print("no spell id?", ...)
				end
			elseif kind == "item" and value then
				value = format("item:%d", value)
			end

			-- Get the action that was on the button before
			if buttonType ~= "empty" then
				buttonAction = self:GetAttribute(self:GetAttribute("action_field"))
			end

			-- TODO: validate what kind of action is being fed in here
			-- We can only use a handful of the possible things on the cursor
			-- return false for all those we can't put on buttons

			self:SetAttribute(format("labtype-%s", state), kind)
			self:SetAttribute(format("labaction-%s", state), value)
			-- update internal state
			self:RunAttribute("UpdateState", state)
			-- send a notification to the insecure code
			self:CallMethod("ButtonContentsChanged", state, kind, value)
		else
			-- get the action for (pet-)action buttons
			buttonAction = self:GetAttribute("action")
			if self:GetID() > 0 then
				buttonAction = buttonAction + ((self:GetAttribute('actionpage') - 1) * 12)
			end
		end
		return self:RunAttribute("PickupButton", buttonType, buttonAction)
	]])

	button:SetScript("OnDragStart", nil)
	-- Wrapped OnDragStart(self, button, kind, value, ...)
	button.header:WrapScript(button, "OnDragStart", [[
		return self:RunAttribute("OnDragStart")
	]])
	-- Wrap twice, because the post-script is not run when the pre-script causes a pickup (doh)
	-- we also need some phony message, or it won't work =/
	button.header:WrapScript(button, "OnDragStart", [[
		return "message", "update"
	]], [[
		self:RunAttribute("UpdateState", self:GetAttribute("state"))
	]])

	button:SetScript("OnReceiveDrag", nil)
	-- Wrapped OnReceiveDrag(self, button, kind, value, ...)
	button.header:WrapScript(button, "OnReceiveDrag", [[
		return self:RunAttribute("OnReceiveDrag", kind, value, ...)
	]])
	-- Wrap twice, because the post-script is not run when the pre-script causes a pickup (doh)
	-- we also need some phony message, or it won't work =/
	button.header:WrapScript(button, "OnReceiveDrag", [[
		return "message", "update"
	]], [[
		self:RunAttribute("UpdateState", self:GetAttribute("state"))
	]])
end

function WrapOnClick(button)
	-- Wrap PreClick to get a temporary reticle macro to use on release if the header provides it.
	button.header:WrapScript(button, "PreClick", [[
		local reticleMacro = owner:RunAttribute("GetReticleMacro", self:GetAttribute("action"), self:GetAttribute("plainID"), down)
		if button == 'ControllerInput' and not down then
			if reticleMacro then
				self:SetAttribute("type", "macro")
				self:SetAttribute("macrotext", reticleMacro)
			else
				self:SetAttribute("type", "omit")
			end
		end
	]])
	-- Wrap OnClick, to catch changes to actions that are applied with a click on the button.
	button.header:WrapScript(button, "OnClick", [[
		if down then
			if self:GetAttribute("type") == "action" then
				local type, action = GetActionInfo(self:GetAttribute("action"))
				return nil, format("%s|%s", tostring(type), tostring(action))
			end
		end
	]], [[
		if down then
			local type, action = GetActionInfo(self:GetAttribute("action"))
			if message ~= format("%s|%s", tostring(type), tostring(action)) then
				self:RunAttribute("UpdateState", self:GetAttribute("state"))
			end
		end
	]])
	-- Wrap PostClick to reset the type and state of the button.
	button.header:WrapScript(button, "PostClick", [[
		self:SetAttribute("type", self:GetAttribute("action_field"))
	]])
end

-----------------------------------------------------------
--- utility

function lib:GetAllButtons()
	local buttons = {}
	for button in next, ButtonRegistry do
		buttons[button] = true
	end
	return buttons
end

function Generic:ClearSetPoint(...)
	self:ClearAllPoints()
	self:SetPoint(...)
end

function Generic:NewHeader(header)
	self.header = header
	self:SetParent(header)
	SetupSecureSnippets(self)
	WrapOnClick(self)
end


-----------------------------------------------------------
--- state management

function Generic:ClearStates()
	for state in pairs(self.state_types) do
		self:SetAttribute(format("labtype-%s", state), nil)
		self:SetAttribute(format("labaction-%s", state), nil)
	end
	wipe(self.state_types)
	wipe(self.state_actions)
end

function Generic:SetState(state, kind, action)
	if not state then state = self:GetAttribute("state") end
	state = tostring(state)
	-- we allow a nil kind for setting a empty state
	if not kind then kind = "empty" end
	if not type_meta_map[kind] then
		error("SetStateAction: unknown action type: " .. tostring(kind), 2)
	end
	if kind ~= "empty" and action == nil then
		error("SetStateAction: an action is required for non-empty states", 2)
	end
	if kind ~= "custom" and action ~= nil and type(action) ~= "number" and type(action) ~= "string" or (kind == "custom" and type(action) ~= "table") then
		error("SetStateAction: invalid action data type, only strings and numbers allowed", 2)
	end

	if kind == "item" then
		if tonumber(action) then
			action = format("item:%s", action)
		else
			local itemString = str_match(action, "^|c%x+|H(item[%d:]+)|h%[")
			if itemString then
				action = itemString
			end
		end
	end

	self.state_types[state] = kind
	self.state_actions[state] = action
	self:UpdateState(state)
end

function Generic:UpdateState(state)
	if not state then state = self:GetAttribute("state") end
	state = tostring(state)
	self:SetAttribute(format("labtype-%s", state), self.state_types[state])
	self:SetAttribute(format("labaction-%s", state), self.state_actions[state])
	if state ~= tostring(self:GetAttribute("state")) then return end
	if self.header then
		self.header:SetFrameRef("updateButton", self)
		self.header:Execute([[
			local frame = self:GetFrameRef("updateButton")
			control:RunFor(frame, frame:GetAttribute("UpdateState"), frame:GetAttribute("state"))
		]])
	else
	-- TODO
	end
	self:UpdateAction()
end

function Generic:GetAction(state)
	if not state then state = self:GetAttribute("state") end
	state = tostring(state)
	return self.state_types[state] or "empty", self.state_actions[state]
end

function Generic:UpdateAllStates()
	for state in pairs(self.state_types) do
		self:UpdateState(state)
	end
end

function Generic:ButtonContentsChanged(state, kind, value)
	state = tostring(state)
	self.state_types[state] = kind or "empty"
	self.state_actions[state] = value
	self:UpdateAction(self)
end

function Generic:DisableDragNDrop(flag)
	if InCombatLockdown() then
		error("LibActionButton-CP: You can only toggle DragNDrop out of combat!", 2)
	end
	if flag then
		self:SetAttribute("disableDragNDrop", true)
	else
		self:SetAttribute("disableDragNDrop", nil)
	end
end

function Generic:UpdateAlpha()
	UpdateCooldown(self)
end

-----------------------------------------------------------
--- frame scripts

-- copied (and adjusted) from SecureHandlers.lua
local function PickupAny(kind, target, detail, ...)
	if kind == "clear" then
		ClearCursor()
		kind, target, detail = target, detail, ...
	end

	if kind == 'action' then
		PickupAction(target)
	elseif kind == 'item' then
		PickupItem(target)
	elseif kind == 'macro' then
		PickupMacro(target)
	elseif kind == 'petaction' then
		PickupPetAction(target)
	elseif kind == 'spell' then
		PickupSpell(target)
	elseif kind == 'companion' then
		PickupCompanion(target, detail)
	elseif kind == 'equipmentset' then
		PickupEquipmentSet(target)
	end
end

function Generic:OnEnter()
	self.header:FadeIn(self.header:GetAlpha())
	self:FadeIn()
	if self.config.tooltip ~= "disabled" and (self.config.tooltip ~= "nocombat" or not InCombatLockdown()) then
		UpdateTooltip(self)
	end

	if self._state_type == "action" and self.NewActionTexture then
		lib.ACTION_HIGHLIGHT_MARKS[self._state_action] = false
		UpdateNewAction(self)
	end
end

function Generic:OnLeave()
	if self.header:GetAttribute('hidesafe') and not InCombatLockdown() then
		self.header:FadeOut(self.header:GetAlpha())
	end
	self:FadeOut()
	GameTooltip:Hide()
end

-- Insecure drag handler to allow clicking on the button with an action on the cursor
-- to place it on the button. Like action buttons work.
function Generic:PreClick()
	if self._state_type == "action" or self._state_type == "pet"
	   or InCombatLockdown() or self:GetAttribute("disableDragNDrop")
	then
		return
	end
	-- check if there is actually something on the cursor
	local kind, value = GetCursorInfo()
	if not (kind and value) then return end
	self._old_type = self._state_type
	if self._state_type and self._state_type ~= "empty" then
		self._old_type = self._state_type
		self:SetAttribute("type", "empty")
		--self:SetState(nil, "empty", nil)
	end
	self._receiving_drag = true
end

local function formatHelper(input)
	if type(input) == "string" then
		return format("%q", input)
	else
		return tostring(input)
	end
end

function Generic:PostClick(button)
	UpdateButtonState(self)
	if self._receiving_drag and not InCombatLockdown() then
		if self._old_type then
			self:SetAttribute("type", self._old_type)
			self._old_type = nil
		end
		local oldType, oldAction = self._state_type, self._state_action
		local kind, data, subtype, extra = GetCursorInfo()
		self.header:SetFrameRef("updateButton", self)
		self.header:Execute(format([[
			local frame = self:GetFrameRef("updateButton")
			control:RunFor(frame, frame:GetAttribute("OnReceiveDrag"), %s, %s, %s, %s)
			control:RunFor(frame, frame:GetAttribute("UpdateState"), %s)
		]], formatHelper(kind), formatHelper(data), formatHelper(subtype), formatHelper(extra), formatHelper(self:GetAttribute("state"))))
		PickupAny("clear", oldType, oldAction)
	end
	self._receiving_drag = nil
end

-----------------------------------------------------------
--- configuration

local function merge(target, source, default)
	for k,v in pairs(default) do
		if type(v) ~= "table" then
			if source and source[k] ~= nil then
				target[k] = source[k]
			else
				target[k] = v
			end
		else
			if type(target[k]) ~= "table" then target[k] = {} else wipe(target[k]) end
			merge(target[k], type(source) == "table" and source[k], v)
		end
	end
	return target
end

function Generic:UpdateConfig(config)
	if config and type(config) ~= "table" then
		error("LibActionButton-CP: UpdateConfig requires a valid configuration!", 2)
	end
	if not self.config then self.config = {} end
	-- merge the two configs
	merge(self.config, config, DefaultConfig)

	UpdateUsable(self)

	if self.config.hideElements.macro then
		self.Name:Hide()
	else
		self.Name:Show()
	end

	self:SetAttribute("flyoutDirection", self.config.flyoutDirection)

	Update(self)
end

-----------------------------------------------------------
--- event handler

function ForAllButtons(method, onlyWithAction)
	assert(type(method) == "function")
	for button in next, (onlyWithAction and ActiveButtons or ButtonRegistry) do
		method(button)
	end
end

function InitializeEventHandler()
	local eventFrame = lib.eventFrame
	eventFrame:SetScript("OnEvent", OnEvent)
	--------------------------------
	for _, event in ipairs({
		----------------------------
		"PLAYER_ENTERING_WORLD",
		"ACTIONBAR_SHOWGRID",
		"ACTIONBAR_HIDEGRID",
	--	"ACTIONBAR_PAGE_CHANGED",
	--	"UPDATE_BONUS_ACTIONBAR",
		"ACTIONBAR_SLOT_CHANGED",
		"UPDATE_BINDINGS",
	--	"UPDATE_SHAPESHIFT_FORM",
		"UPDATE_VEHICLE_ACTIONBAR",

		"ACTIONBAR_UPDATE_STATE",
		"ACTIONBAR_UPDATE_USABLE",
		"ACTIONBAR_UPDATE_COOLDOWN",
		"PLAYER_TARGET_CHANGED",
		"TRADE_SKILL_SHOW",
		"TRADE_SKILL_CLOSE",
		"ARCHAEOLOGY_CLOSED",
		"PLAYER_ENTER_COMBAT",
		"PLAYER_LEAVE_COMBAT",
		"START_AUTOREPEAT_SPELL",
		"STOP_AUTOREPEAT_SPELL",
		"UNIT_ENTERED_VEHICLE",
		"UNIT_EXITED_VEHICLE",
		"COMPANION_UPDATE",
		"UNIT_INVENTORY_CHANGED",
		"LEARNED_SPELL_IN_TAB",
		"PET_STABLE_UPDATE",
		"PET_STABLE_SHOW",
		"SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
		"SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
		"SPELL_UPDATE_CHARGES",
		"UPDATE_SUMMONPETS_ACTION",

		-- With those two, do we still need the ACTIONBAR equivalents of them?
		"SPELL_UPDATE_COOLDOWN",
		"SPELL_UPDATE_USABLE",
		"PLAYER_EQUIPMENT_CHANGED",

		"LOSS_OF_CONTROL_ADDED",
		"LOSS_OF_CONTROL_UPDATE",
		----------------------------
	}) do eventFrame:RegisterEvent(event) end
	--------------------------------

	eventFrame:Show()
	eventFrame:SetScript("OnUpdate", OnUpdate)
end

function OnEvent(_, event, arg1, ...)
	if (event == "UNIT_INVENTORY_CHANGED" and arg1 == "player") or event == "LEARNED_SPELL_IN_TAB" then
		local tooltipOwner = GameTooltip:GetOwner()
		if ButtonRegistry[tooltipOwner] then
			tooltipOwner:SetTooltip()
		end
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		for button in next, ButtonRegistry do
			if button._state_type == "action" and (arg1 == 0 or arg1 == tonumber(button._state_action)) then
				Update(button)
			end
		end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_VEHICLE_ACTIONBAR" then
		ForAllButtons(Update)
	elseif event == "ACTIONBAR_SHOWGRID" then
		ShowGrid()
	elseif event == "ACTIONBAR_HIDEGRID" then
		HideGrid()
	elseif event == "PLAYER_TARGET_CHANGED" then
		UpdateRangeTimer()
	elseif (event == "ACTIONBAR_UPDATE_STATE") or
		((event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and (arg1 == "player")) or
		((event == "COMPANION_UPDATE") and (arg1 == "MOUNT")) then
		ForAllButtons(UpdateButtonState, true)
	elseif event == "ACTIONBAR_UPDATE_USABLE" then
		for button in next, ActionButtons do
			UpdateUsable(button)
		end
	elseif event == "SPELL_UPDATE_USABLE" then
		for button in next, NonActionButtons do
			UpdateUsable(button)
		end
	elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
		for button in next, ActionButtons do
			UpdateCooldown(button)
			if GameTooltip:GetOwner() == button then
				UpdateTooltip(button)
			end
		end
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		for button in next, NonActionButtons do
			UpdateCooldown(button)
			if GameTooltip:GetOwner() == button then
				UpdateTooltip(button)
			end
		end
	elseif event == "LOSS_OF_CONTROL_ADDED" then
		for button in next, ActiveButtons do
			UpdateCooldown(button)
			if GameTooltip:GetOwner() == button then
				UpdateTooltip(button)
			end
		end
	elseif event == "LOSS_OF_CONTROL_UPDATE" then
		for button in next, ActiveButtons do
			UpdateCooldown(button)
		end
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_CLOSE"  or event == "ARCHAEOLOGY_CLOSED" then
		ForAllButtons(UpdateButtonState, true)
	elseif event == "PLAYER_ENTER_COMBAT" then
		for button in next, ActiveButtons do
			if button:IsAttack() then
				StartFlash(button)
			end
		end
	elseif event == "PLAYER_LEAVE_COMBAT" then
		for button in next, ActiveButtons do
			if button:IsAttack() then
				StopFlash(button)
			end
		end
	elseif event == "START_AUTOREPEAT_SPELL" then
		for button in next, ActiveButtons do
			if button:IsAutoRepeat() then
				StartFlash(button)
			end
		end
	elseif event == "STOP_AUTOREPEAT_SPELL" then
		for button in next, ActiveButtons do
			if button.flashing == 1 and not button:IsAttack() then
				StopFlash(button)
			end
		end
	elseif event == "PET_STABLE_UPDATE" or event == "PET_STABLE_SHOW" then
		ForAllButtons(Update)
	elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
		for button in next, ActiveButtons do
			local spellId = button:GetSpellId()
			if spellId and spellId == arg1 then
				if not button.isMainButton then
					button:SetGlowing(true, true)
				end
				ShowOverlayGlow(button)
			else
				if button._state_type == "action" then
					local actionType, id = GetActionInfo(button._state_action)
					if actionType == "flyout" and FlyoutHasSpell(id, arg1) then
						button:SetGlowing(true, true)
						ShowOverlayGlow(button)
					end
				end
			end
		end
	elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
		for button in next, ActiveButtons do
			local spellId = button:GetSpellId()
			if spellId and spellId == arg1 then
				HideOverlayGlow(button)
				if not button.isMainButton then
					button:SetGlowing(false)
					UpdateCooldown(button)
				end
			else
				if button._state_type == "action" then
					local actionType, id = GetActionInfo(button._state_action)
					if actionType == "flyout" and FlyoutHasSpell(id, arg1) then
						button:SetGlowing(false)
						HideOverlayGlow(button)
					end
				end
			end
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		for button in next, ActiveButtons do
			if button._state_type == "item" then
				Update(button)
			end
		end
	elseif event == "SPELL_UPDATE_CHARGES" then
		ForAllButtons(UpdateCount, true)
	elseif event == "UPDATE_SUMMONPETS_ACTION" then
		for button in next, ActiveButtons do
			if button._state_type == "action" then
				local actionType, id = GetActionInfo(button._state_action)
				if actionType == "summonpet" then
					local texture = GetActionTexture(button._state_action)
					if texture then
						button.icon:SetTexture(texture)
						if button.mainIcon then
							button.mainIcon:SetTexture(texture)
						end
					end
				end
			end
		end
	end
end

local flashTime = 0
local rangeTimer = -1
function OnUpdate(_, elapsed)
	flashTime = flashTime - elapsed
	rangeTimer = rangeTimer - elapsed
	-- Run the loop only when there is something to update
	if rangeTimer <= 0 or flashTime <= 0 then
		for button in next, ActiveButtons do
			-- Flashing
			if button.flashing == 1 and flashTime <= 0 then
				if button.Flash:IsShown() then
					button.Flash:Hide()
				else
					button.Flash:Show()
				end
			end

			-- Range
			if rangeTimer <= 0 then
				local inRange = button:IsInRange()
				local oldRange = button.outOfRange
				button.outOfRange = (inRange == false)
				if oldRange ~= button.outOfRange then
					UpdateUsable(button)
				end
			end
		end

		-- Update values
		if flashTime <= 0 then
			flashTime = flashTime + ATTACK_BUTTON_FLASH_TIME
		end
		if rangeTimer <= 0 then
			rangeTimer = TOOLTIP_UPDATE_TIME
		end
	end
end

function ShowGrid()
	for button in next, ButtonRegistry do
		if button:IsShown() then
			button:SetShowGrid(true)
		end
	end
end

function HideGrid()
	for button in next, ButtonRegistry do
		button:SetShowGrid(false)
	end
end

-----------------------------------------------------------
--- button management

function Generic:SetClicks(mouseover)
	if mouseover then
		self:RegisterForClicks("AnyUp")
	else
		self:RegisterForClicks("AnyUp", "AnyDown")
	end
end

function Generic:Hover(isEnabled)
	self.forceShow = isEnabled
	if self.isMainButton then return end
	if isEnabled then
		self:FadeIn(1)
	else
		self:FadeOut(0)
	end
end

function Generic:SetShowGrid(isEnabled)
	if self.isMainButton then return end
	self.showGrid = isEnabled
	if isEnabled then
		self:FadeIn(1, 0)
	else
		self:FadeOut(0, 0)
	end
end

function Generic:SetGlowing(isEnabled, instantAlpha)
	self.isGlowing = isEnabled
	if self.isMainButton then return end
	if isEnabled then
		self:FadeIn(1, instantAlpha and 0 or 0.2)
	else
		self:FadeOut(0, instantAlpha and 0 or 0.2) 
	end
end

function Generic:SetOnCooldown(isEnabled, instantAlpha)
	self.isOnCooldown = isEnabled
	if self.isMainButton then return end
	if isEnabled then
		self:FadeIn(1, instantAlpha and 0 or 0.2)
	else
		self:FadeOut(0, instantAlpha and 0 or 0.2) 
	end
end

function Generic:FadeIn(newAlpha, speed)
	UIFrameFadeIn(self, speed or 0.2, self:GetAlpha(), newAlpha or 1)
end

function Generic:FadeOut(newAlpha, speed)
	if not self.isMainButton and not self.isGlowing and not self.isOnCooldown and not self.forceShow and not self.showGrid then
		UIFrameFadeOut(self, speed or 0.2, self:GetAlpha(), newAlpha or 0)
	end
end

function Generic:UpdateAction(force)
	local type, action = self:GetAction()
	if force or type ~= self._state_type or action ~= self._state_action then
		-- type changed, update the metatable
		if force or self._state_type ~= type then
			local meta = type_meta_map[type] or type_meta_map.empty
			setmetatable(self, meta)
			self._state_type = type
		end
		self._state_action = action
		Update(self)
	end
end

function Update(self)
	if self:HasAction() then
		ActiveButtons[self] = true
		if self._state_type == "action" then
			ActionButtons[self] = true
			NonActionButtons[self] = nil
		else
			ActionButtons[self] = nil
			NonActionButtons[self] = true
		end
		UpdateButtonState(self)
		UpdateUsable(self)
		UpdateCooldown(self)
		UpdateFlash(self)
		UpdatePage(self)
	else
		ActiveButtons[self] = nil
		ActionButtons[self] = nil
		NonActionButtons[self] = nil
		self.cooldown:Hide()
		self:SetChecked(false)

		self.isGlowing = false
		self.isOnCooldown = false
		self:FadeOut()
		UpdateUsable(self)
		UpdatePage(self)

		if self.chargeCooldown then
			EndChargeCooldown(self.chargeCooldown)
		end
	end

	-- Add a green border if button is an equipped item
	if self:IsEquipped() and not self.config.hideElements.equipped then
		self.Border:SetVertexColor(0, 1.0, 0, 0.35)
		self.Border:Show()
	else
		self.Border:Hide()
	end

	-- Update Action Text
	if self.isMainButton and not self:IsConsumableOrStackable() then
		self.Name:SetText(self:GetActionText())
	else
		self.Name:SetText("")
	end

	-- Update icon and hotkey
	local texture = self:GetTexture()

	-- Draenor zone button handling
	self.draenorZoneDisabled = false
	if self._state_type == "action" then
		local action_type, id = GetActionInfo(self._state_action)
		if ((action_type == "spell" or action_type == "companion") and DraenorZoneAbilityFrame and DraenorZoneAbilityFrame.baseName and not HasDraenorZoneAbility()) then
			local name = GetSpellInfo(DraenorZoneAbilityFrame.baseName)
			local abilityName = GetSpellInfo(id)
			if name == abilityName then
				texture = GetLastDraenorSpellTexture()
				self.draenorZoneDisabled = true
			end
		end
	end

	if texture then
		self.rangeTimer = - 1
	else
		self.cooldown:Hide()
		self.rangeTimer = nil
	end

	self:SetIcon(texture)

	UpdateCount(self)

	UpdateFlyout(self)

	UpdateOverlayGlow(self)

	UpdateNewAction(self)

	if GameTooltip:GetOwner() == self then
		UpdateTooltip(self)
	end

	-- this could've been a spec change, need to call OnStateChanged for action buttons, if present
	if not InCombatLockdown() and self._state_type == "action" then
		local onStateChanged = self:GetAttribute("OnStateChanged")
		if onStateChanged then
			self.header:SetFrameRef("updateButton", self)
			self.header:Execute(([[
				local frame = self:GetFrameRef("updateButton")
				control:RunFor(frame, frame:GetAttribute("OnStateChanged"), %s, %s, %s)
			]]):format(formatHelper(self:GetAttribute("state")), formatHelper(self._state_type), formatHelper(self._state_action)))
		end
	end
end

function UpdateButtonState(self)
	if self:IsCurrentlyActive() or self:IsAutoRepeat() then
		self:SetChecked(true)
	else
		self:SetChecked(false)
	end
end

function UpdateUsable(self)
	-- TODO: make the colors configurable
	-- TODO: allow disabling of the whole recoloring
	if self.outOfRange then
		self:SetVertexColor(unpack(self.config.colors.range))
	else
		local isUsable, notEnoughMana = self:IsUsable()
		if isUsable then
			self:ClearVertexColor()
			--self.NormalTexture:SetVertexColor(1.0, 1.0, 1.0)
		elseif notEnoughMana then
			self:SetVertexColor(unpack(self.config.colors.mana))
			--self.NormalTexture:SetVertexColor(0.5, 0.5, 1.0)
		else
			self:SetVertexColor(0.4, 0.4, 0.4)
			--self.NormalTexture:SetVertexColor(1.0, 1.0, 1.0)
		end
	end
end

function UpdateCount(self)
	if not self:HasAction() then
		self.Count:SetText("")
		return
	end
	if self:IsConsumableOrStackable() then
		local count = self:GetCount()
		if count > (self.maxDisplayCount or 9999) then
			self.Count:SetText("*")
		else
			self.Count:SetText(count)
		end
	else
		local charges, maxCharges, chargeStart, chargeDuration = self:GetCharges()
		if charges and maxCharges and maxCharges > 0 then
			self.Count:SetText(charges)
		else
			self.Count:SetText("")
		end
	end
end

function UpdatePage(self)
	if self:GetAction() == 'action' then
		local page = self:GetAttribute('actionpage')
		local action = self:GetAttribute('action')
		if (page and action) and (page > 1) and (page < 7) then
			if action <= NUM_ACTIONBAR_BUTTONS then
				self.Page:Show()
				self.Page:SetText(page)
				return
			end
		end
	end
	self.Page:Hide()
end

function EndChargeCooldown(self)
	self:Hide()
	self:SetParent(UIParent)
	self.parent.chargeCooldown = nil
	self.parent = nil
	tinsert(lib.ChargeCooldowns, self)
end

local function StartChargeCooldown(parent, chargeStart, chargeDuration)
	if not parent.chargeCooldown then
		local cooldown = tremove(lib.ChargeCooldowns)
		if not cooldown then
			lib.NumChargeCooldowns = lib.NumChargeCooldowns + 1
			cooldown = CreateFrame("Cooldown", "$parentChargeCooldown", parent, "CooldownFrameTemplate")
			cooldown:SetScript("OnCooldownDone", EndChargeCooldown)
			cooldown:SetHideCountdownNumbers(true)
			cooldown:SetEdgeTexture("Interface\\AddOns\\ConsolePortBar\\Textures\\Cooldown\\Edge")
			cooldown:SetBlingTexture("Interface\\AddOns\\ConsolePort\\Textures\\Button\\Bling")
			cooldown:SetSwipeTexture("Interface\\AddOns\\ConsolePortBar\\Textures\\Cooldown\\Charge")
			cooldown:SetDrawEdge(true)
			cooldown:SetDrawSwipe(true)
		end
		cooldown:SetParent(parent)
		cooldown:SetAllPoints(parent)
		cooldown:Show()
		parent.chargeCooldown = cooldown
		cooldown.parent = parent
	end
	parent.chargeCooldown:SetDrawBling(parent.chargeCooldown:GetEffectiveAlpha() > 0.5)
	parent.chargeCooldown:SetCooldown(chargeStart, chargeDuration)
	if not chargeStart or chargeStart == 0 then
		EndChargeCooldown(parent.chargeCooldown)
	end
end

local function OnCooldownDone(self)
	local button = self:GetParent()
	button:SetOnCooldown(false)
	self:SetScript("OnCooldownDone", nil)
	UpdateCooldown(button)
end

local function OnModifierCooldownDone(self)
	local button = self:GetParent()
	button:SetOnCooldown(false)
	self:SetScript("OnCooldownDone", nil)
end

function UpdateCooldown(self)
	local locStart, locDuration = self:GetLossOfControlCooldown()
	local start, duration, enable = self:GetCooldown()
	local charges, maxCharges, chargeStart, chargeDuration = self:GetCharges()

	self.cooldown:SetDrawBling(self.cooldown:GetEffectiveAlpha() > 0.5)

	if not self.isMainButton and not self.isGlowing then
		if (duration > 2) then
			self:SetOnCooldown(true)
			self.cooldown:SetSwipeColor(0.17, 0, 0)
			self.cooldown:SetScript("OnCooldownDone", OnModifierCooldownDone)
		end
	end

	if (locStart + locDuration) > (start + duration) then
		if self.cooldown.currentCooldownType ~= COOLDOWN_TYPE_LOSS_OF_CONTROL then
			self.cooldown:SetHideCountdownNumbers(true)
			self.cooldown.currentCooldownType = COOLDOWN_TYPE_LOSS_OF_CONTROL
		end
		CooldownFrame_Set(self.cooldown, locStart, locDuration, true, true)
	else
		if self.cooldown.currentCooldownType ~= COOLDOWN_TYPE_NORMAL then
			self.cooldown:SetHideCountdownNumbers(false)
			self.cooldown.currentCooldownType = COOLDOWN_TYPE_NORMAL
		end
		if locStart > 0 then
			self.cooldown:SetScript("OnCooldownDone", OnCooldownDone)
		end

		if charges and maxCharges and maxCharges > 0 and charges > 0 and charges < maxCharges then
			StartChargeCooldown(self, chargeStart, chargeDuration)
		elseif self.chargeCooldown then
			EndChargeCooldown(self.chargeCooldown)
		end
		CooldownFrame_Set(self.cooldown, start, duration, enable)
	end
end

function StartFlash(self)
	self.flashing = 1
	flashTime = 0
	UpdateButtonState(self)
end

function StopFlash(self)
	self.flashing = 0
	self.Flash:Hide()
	UpdateButtonState(self)
end

function UpdateFlash(self)
	if (self:IsAttack() and self:IsCurrentlyActive()) or self:IsAutoRepeat() then
		StartFlash(self)
	else
		StopFlash(self)
	end
end

function UpdateTooltip(self)
	if (GetCVar("UberTooltips") == "1") then
		GameTooltip_SetDefaultAnchor(GameTooltip, self);
	else
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	end
	if self:SetTooltip() then
		self.UpdateTooltip = UpdateTooltip
	else
		self.UpdateTooltip = nil
	end
	local currentModifier = self.isMainButton and ConsolePort:GetCurrentModifier() or self.mod
	local bindingString = ConsolePort:GetFormattedButtonCombination(self.plainID, currentModifier, 20, true)
	if bindingString and GameTooltip:IsVisible() then
		local title = GameTooltipTextRight1
		title:SetText(bindingString)
		title:Show()
		GameTooltip:Show()
	end
end

function ShowOverlayGlow(self)
	if LBG then
		LBG.ShowOverlayGlow(self)
	end
end

function HideOverlayGlow(self)
	if LBG then
		LBG.HideOverlayGlow(self)
	end
end

function UpdateOverlayGlow(self)
	local spellId = self:GetSpellId()
	if spellId and IsSpellOverlayed(spellId) then
		ShowOverlayGlow(self)
	else
		HideOverlayGlow(self)
	end
end

hooksecurefunc("MarkNewActionHighlight", function(action, flag)
	lib.ACTION_HIGHLIGHT_MARKS[action] = flag
	for button in next, ButtonRegistry do
		if button._state_type == "action" and action == tonumber(button._state_action) then
			UpdateNewAction(button)
		end
	end
end)

function UpdateNewAction(self)
	-- special handling for "New Action" markers
	if self.NewActionTexture then
		if self._state_type == "action" and lib.ACTION_HIGHLIGHT_MARKS[self._state_action] then
			self.NewActionTexture:Show()
			UIFrameFadeOut(self.NewActionTexture, 10, 1, 0)
		else
			self.NewActionTexture:Hide()
		end
	end
end

-- Hook UpdateFlyout so we can use the blizzy templates
hooksecurefunc("ActionButton_UpdateFlyout", function(self, ...)
	if ButtonRegistry[self] then
		UpdateFlyout(self)
	end
end)

function UpdateFlyout(self)
	self.FlyoutBorder:Hide()
	self.FlyoutBorderShadow:Hide()
	if self._state_type == "action" then
		-- based on ActionButton_UpdateFlyout in ActionButton.lua
		local actionType = GetActionInfo(self._state_action)
		if actionType == "flyout" then

			self.FlyoutArrow:Show()
			self.FlyoutArrow:ClearAllPoints()
			
			self.FlyoutArrow:SetPoint("CENTER", 0, self.isMainButton and -20 or -10)
			SetClampedTextureRotation(self.FlyoutArrow, 180)
			return
		end
	end
	self.FlyoutArrow:Hide()
end

function UpdateRangeTimer()
	rangeTimer = -1
end

-----------------------------------------------------------
--- WoW API mapping
--- Generic Button
Generic.HasAction               = function(self) return nil end
Generic.GetActionText           = function(self) return "" end
Generic.GetTexture              = function(self) return nil end
Generic.GetCharges              = function(self) return nil end
Generic.GetCount                = function(self) return 0 end
Generic.GetCooldown             = function(self) return 0, 0, 0 end
Generic.IsAttack                = function(self) return nil end
Generic.IsEquipped              = function(self) return nil end
Generic.IsCurrentlyActive       = function(self) return nil end
Generic.IsAutoRepeat            = function(self) return nil end
Generic.IsUsable                = function(self) return nil end
Generic.IsConsumableOrStackable = function(self) return nil end
Generic.IsUnitInRange           = function(self, unit) return nil end
Generic.IsInRange               = function(self)
	local unit = self:GetAttribute("unit")
	if unit == "player" then
		unit = nil
	end
	local val = self:IsUnitInRange(unit)
	-- map 1/0 to true false, since the return values are inconsistent between actions and spells
	if val == 1 then val = true elseif val == 0 then val = false end
	return val
end
Generic.SetTooltip              = function(self) return nil end
Generic.GetSpellId              = function(self) return nil end
Generic.GetLossOfControlCooldown = function(self) return 0, 0 end

-----------------------------------------------------------
--- Action Button
Action.HasAction               = function(self) return HasAction(self._state_action) end
Action.GetActionText           = function(self) return GetActionText(self._state_action) end
Action.GetTexture              = function(self) return GetActionTexture(self._state_action) end
Action.GetCharges              = function(self) return GetActionCharges(self._state_action) end
Action.GetCount                = function(self) return GetActionCount(self._state_action) end
Action.GetCooldown             = function(self) return GetActionCooldown(self._state_action) end
Action.IsAttack                = function(self) return IsAttackAction(self._state_action) end
Action.IsEquipped              = function(self) return IsEquippedAction(self._state_action) end
Action.IsCurrentlyActive       = function(self) return IsCurrentAction(self._state_action) end
Action.IsAutoRepeat            = function(self) return IsAutoRepeatAction(self._state_action) end
Action.IsUsable                = function(self) return IsUsableAction(self._state_action) end
Action.IsConsumableOrStackable = function(self) return IsConsumableAction(self._state_action) or IsStackableAction(self._state_action) or (not IsItemAction(self._state_action) and GetActionCount(self._state_action) > 0) end
Action.IsUnitInRange           = function(self, unit) return IsActionInRange(self._state_action, unit) end
Action.SetTooltip              = function(self) return GameTooltip:SetAction(self._state_action) end
Action.GetSpellId              = function(self)
	local actionType, id, subType = GetActionInfo(self._state_action)
	if actionType == "spell" then
		return id
	elseif actionType == "macro" then
		local _, _, spellId = GetMacroSpell(id)
		return spellId
	end
end
Action.GetLossOfControlCooldown = function(self) return GetActionLossOfControlCooldown(self._state_action) end

-----------------------------------------------------------
--- Spell Button
Spell.HasAction               = function(self) return true end
Spell.GetActionText           = function(self) return "" end
Spell.GetTexture              = function(self) return GetSpellTexture(self._state_action) end
Spell.GetCharges              = function(self) return GetSpellCharges(self._state_action) end
Spell.GetCount                = function(self) return GetSpellCount(self._state_action) end
Spell.GetCooldown             = function(self) return GetSpellCooldown(self._state_action) end
Spell.IsAttack                = function(self) return IsAttackSpell(FindSpellBookSlotBySpellID(self._state_action), "spell") end -- needs spell book id as of 4.0.1.13066
Spell.IsEquipped              = function(self) return nil end
Spell.IsCurrentlyActive       = function(self) return IsCurrentSpell(self._state_action) end
Spell.IsAutoRepeat            = function(self) return IsAutoRepeatSpell(FindSpellBookSlotBySpellID(self._state_action), "spell") end -- needs spell book id as of 4.0.1.13066
Spell.IsUsable                = function(self) return IsUsableSpell(self._state_action) end
Spell.IsConsumableOrStackable = function(self) return IsConsumableSpell(self._state_action) end
Spell.IsUnitInRange           = function(self, unit) return IsSpellInRange(FindSpellBookSlotBySpellID(self._state_action), "spell", unit) end -- needs spell book id as of 4.0.1.13066
Spell.SetTooltip              = function(self) return GameTooltip:SetSpellByID(self._state_action) end
Spell.GetSpellId              = function(self) return self._state_action end

-----------------------------------------------------------
--- Item Button
local function getItemId(input)
	return input:match("^item:(%d+)")
end

Item.HasAction               = function(self) return true end
Item.GetActionText           = function(self) return "" end
Item.GetTexture              = function(self) return GetItemIcon(self._state_action) end
Item.GetCharges              = function(self) return nil end
Item.GetCount                = function(self) return GetItemCount(self._state_action, nil, true) end
Item.GetCooldown             = function(self) return GetItemCooldown(getItemId(self._state_action)) end
Item.IsAttack                = function(self) return nil end
Item.IsEquipped              = function(self) return IsEquippedItem(self._state_action) end
Item.IsCurrentlyActive       = function(self) return IsCurrentItem(self._state_action) end
Item.IsAutoRepeat            = function(self) return nil end
Item.IsUsable                = function(self) return IsUsableItem(self._state_action) end
Item.IsConsumableOrStackable = function(self) return IsConsumableItem(self._state_action) end
Item.IsUnitInRange           = function(self, unit) return IsItemInRange(self._state_action, unit) end
Item.SetTooltip              = function(self) return GameTooltip:SetHyperlink(self._state_action) end
Item.GetSpellId              = function(self) return nil end

-----------------------------------------------------------
--- Macro Button
-- TODO: map results of GetMacroSpell/GetMacroItem to proper results
Macro.HasAction               = function(self) return true end
Macro.GetActionText           = function(self) return (GetMacroInfo(self._state_action)) end
Macro.GetTexture              = function(self) return (select(2, GetMacroInfo(self._state_action))) end
Macro.GetCharges              = function(self) return nil end
Macro.GetCount                = function(self) return 0 end
Macro.GetCooldown             = function(self) return 0, 0, 0 end
Macro.IsAttack                = function(self) return nil end
Macro.IsEquipped              = function(self) return nil end
Macro.IsCurrentlyActive       = function(self) return nil end
Macro.IsAutoRepeat            = function(self) return nil end
Macro.IsUsable                = function(self) return nil end
Macro.IsConsumableOrStackable = function(self) return nil end
Macro.IsUnitInRange           = function(self, unit) return nil end
Macro.SetTooltip              = function(self) return nil end
Macro.GetSpellId              = function(self) return nil end

-----------------------------------------------------------
--- Custom Button
Custom.HasAction               = function(self) return true end
Custom.GetActionText           = function(self) return "" end
Custom.GetTexture              = function(self) return self._state_action.texture end
Custom.GetCharges              = function(self) return nil end
Custom.GetCount                = function(self) return 0 end
Custom.GetCooldown             = function(self) return 0, 0, 0 end
Custom.IsAttack                = function(self) return nil end
Custom.IsEquipped              = function(self) return nil end
Custom.IsCurrentlyActive       = function(self) return nil end
Custom.IsAutoRepeat            = function(self) return nil end
Custom.IsUsable                = function(self) return true end
Custom.IsConsumableOrStackable = function(self) return nil end
Custom.IsUnitInRange           = function(self, unit) return nil end
Custom.SetTooltip              = function(self) return GameTooltip:SetText(self._state_action.tooltip) end
Custom.GetSpellId              = function(self) return nil end
Custom.RunCustom               = function(self, unit, button) return self._state_action.func(self, unit, button) end

-----------------------------------------------------------