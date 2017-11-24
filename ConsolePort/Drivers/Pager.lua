---------------------------------------------------------------
-- Pager.lua: Action pager and extended secure API
---------------------------------------------------------------
-- Unifies action page changing on all secure headers and
-- extends the secure API to get arbitrary action data.
---------------------------------------------------------------
local Pager = CreateFrame('Button', 'ConsolePortPager', nil, 'SecureHandlerStateTemplate, SecureActionButtonTemplate')
Pager:WrapScript(Pager, 'PreClick', [[ if down then self:SetAttribute('action', tonumber(button) or 1) else self:SetAttribute('action', 1) end ]])
Pager:SetAttribute('type', 'actionbar')
Pager:RegisterForClicks('AnyUp', 'AnyDown')
Pager:Execute('headers = newtable()')

--[[ Functions:
	GetActionID: Returns the correct ID for an action slot
	GetActionInfo: Returns information about an action slot
	GetActionSpellSlot: Returns spell information about an action slot
	IsHarmfulAction: Returns whether the action slot is harmful or not
	IsHelpfulAction: Returns whether the action slot is helpful or not
]]

local PAGER_SECURE_FUNCTIONS = {
	GetActionID = [[
		local id = ...
		if id then
			local page = self:GetAttribute('actionpage') or 1
			if id >= 1 and id <= 12 then
				return ( ( page - 1 ) * 12 ) + id
			else
				return id
			end
		end
	]],
	GetActionInfo = [[
		local id = self:RunAttribute('GetActionID', ...)
		if id then
			return GetActionInfo(id)
		end
	]],
	GetSpellID = [[
		local actionType, spellID, subType = self:RunAttribute('GetActionInfo', ...)
		if actionType == 'spell' and subType == 'spell' then
			return spellID
		end
	]],
	GetActionSpellSlot = [[
		local type, spellID, subType = self:RunAttribute('GetActionInfo', ...)
		if type == 'spell' and spellID and spellID ~= 0 and subType == 'spell' then
			return FindSpellBookSlotBySpellID(spellID)
		end
	]],
	IsHarmfulAction = [[
		local type, id = self:RunAttribute('GetActionInfo', ...)
		if type == 'spell' then
			local slot = self:RunAttribute('GetActionSpellSlot', ...)
			if slot then
				return IsHarmfulSpell(slot, 'spell')
			end
		elseif type == 'item' and id then
			return IsHarmfulItem(id)
		end
	]],
	IsHelpfulAction = [[
		local type, id = self:RunAttribute('GetActionInfo', ...)
		if type == 'spell' then
			local slot = self:RunAttribute('GetActionSpellSlot', ...)
			if slot then
				return IsHelpfulSpell(slot, 'spell')
			end
		elseif type == 'item' and id then
			return IsHelpfulItem(id)
		end
	]],
}

local function ScanLockdownCulprits(header, this, culprits)
	this = this or UIParent
	local __mt = getmetatable(this)
	local __index = __mt and __mt.__index
	if not __index or __index.GetChildren ~= this.GetChildren then
		culprits = culprits or {}
		culprits[this] = true
	end
	for _, frame in ipairs({this:GetChildren()}) do
		ScanLockdownCulprits(header, frame, culprits)
	end
	return culprits
end

function ConsolePort:RegisterSpellHeader(header, omitFromStack)
	if not InCombatLockdown() then

		for name, func in pairs(PAGER_SECURE_FUNCTIONS) do
			header:SetAttribute(name, func)
		end

		if not omitFromStack then
			local _, current = self:GetActionPageDriver()
			header:SetAttribute('actionpage', current)

			header:SetFrameRef('actionBar', MainMenuBarArtFrame)
			header:SetFrameRef('overrideBar', OverrideActionBar)

			Pager:SetFrameRef('header', header)
			Pager:Execute([[ headers[self:GetFrameRef('header')] = true ]])
		end
	end
end

function ConsolePort:GetPager() return Pager end
function ConsolePort:LoadActionPager(pagedriver, pageresponse)
	if not pagedriver then
		pagedriver = self:GetActionPageDriver()
	end
	if not pageresponse then
		pageresponse = 	[[
			if HasVehicleActionBar() then
				newstate = GetVehicleBarIndex()
			elseif HasOverrideActionBar() then
				newstate = GetOverrideBarIndex()
			elseif HasTempShapeshiftActionBar() then
				newstate = GetTempShapeshiftBarIndex()
			elseif GetBonusBarOffset() > 0 then
				newstate = GetBonusBarOffset()+6
			else
				newstate = GetActionBarPage()
			end
			for header in pairs(headers) do
				header:SetAttribute('actionpage', newstate)
				if header:GetAttribute('pageupdate') then
					header:RunAttribute('pageupdate', newstate)
				end
			end
		]]
	else
		pageresponse = pageresponse .. [[
			for header in pairs(headers) do
				header:SetAttribute('actionpage', newstate)
				if header:GetAttribute('pageupdate') then
					header:RunAttribute('pageupdate', newstate)
				end
			end
		]]
	end
	RegisterStateDriver(Pager, 'actionpage', pagedriver)
	Pager:SetAttribute('_onstate-actionpage', pageresponse)
end
