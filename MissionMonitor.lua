local MissionMonitorAddonName = ...
MissionMonitorItems = {}
MissionMonitorCharacterItems = {}

local event_frame = CreateFrame("FRAME")
event_frame:RegisterEvent("ADDON_LOADED")
event_frame:RegisterEvent("GARRISON_MISSION_LIST_UPDATE")

local item_info_callbacks = {}
local function item_info_add_callback(item, callback)
	item_info_callbacks[item] = item_info_callbacks[item] or {}
	item_info_callbacks[item][#item_info_callbacks[item] + 1] = callback
	event_frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

local wanted_items
local function MissionMonitor_FlushWanted()
	wanted_items = {}
	for _, item in ipairs(MissionMonitorItems) do
		wanted_items[item] = 1
	end
	for _, item in ipairs(MissionMonitorCharacterItems) do
		wanted_items[item] = 1
	end
end

local function LinkAddIcon(link, icon, height, width)
	return gsub(link, "|h", format("|h|T%s:%i:%i|t", icon, height, width or height), 1)
end

local function MissionMonitor_MissionGetWantedItems(mission)
	local mission_wanted_items = {}
	for _, reward in ipairs(mission.rewards) do
		if wanted_items[reward.itemID] then
			mission_wanted_items[#mission_wanted_items + 1] = reward.itemID
		end
	end
	for _, reward in ipairs(mission.overmaxRewards) do
		if wanted_items[reward.itemID] then
			mission_wanted_items[#mission_wanted_items + 1] = reward.itemID
		end
	end
	return mission_wanted_items
end

local mission_seen = {}
local function MissionMonitor_CheckMission(mission, alert_system, message)
	local mission_wanted_items = MissionMonitor_MissionGetWantedItems(mission)
	if #mission_wanted_items == 0 then return end

	alert_system:AddAlert(mission)
	local mission_item_links = {}
	local function print_mission_rewards()
		local links = {}
		for _, item in pairs(mission_wanted_items) do
			local link = mission_item_links[item]
			if link then
				links[#links + 1] = LinkAddIcon(link, select(5, C_Item.GetItemInfoInstant(item)), 14)
			else
				return
			end
		end
		local mission_link = C_Garrison.GetMissionLink(mission.missionID)
		if not mission_link then
			mission_seen[mission.missionID] = nil
			return
		end
		mission_item_links = nil
		local link_count = #links
		local last_link = links[link_count]
		links[link_count] = nil
		print(format(message, mission_link, strjoin(", ", unpack(links)) .. (link_count > 1 and " and " or "") .. last_link))
	end
	for _, item in ipairs(mission_wanted_items) do
		local link = select(2, C_Item.GetItemInfo(item))
		if link then
			mission_item_links[item] = link
		else
			item_info_add_callback(item, function(_, item, _, link)
				if not mission_item_links then return end
				mission_item_links[item] = link
				print_mission_rewards()
			end)
		end
	end
	print_mission_rewards()
end

local function MissionMonitor_CheckCompleteMission(mission)
	MissionMonitor_CheckMission(
		mission,
		mission.followerTypeID == Enum.GarrisonFollowerType.FollowerType_6_0_Boat and GarrisonShipMissionAlertSystem or GarrisonMissionAlertSystem,
		"%s is |c0000ff00complete|r with wanted reward %s"
	)
end

local function MissionMonitor_CheckAvailableMission(mission)
	MissionMonitor_CheckMission(mission, GarrisonRandomMissionAlertSystem, "%s is |c00ffff00available|r with wanted reward %s")
end

local follower_types = {}
local function MissionMonitor_CheckMissions(followerTypeID)
	follower_types[followerTypeID] = 1
	for _, mission in ipairs(C_Garrison.GetCompleteMissions(followerTypeID)) do
		if not mission_seen[mission.missionID] then
			mission_seen[mission.missionID] = 1
			MissionMonitor_CheckCompleteMission(mission)
		end
	end
	local available_missions = C_Garrison.GetAvailableMissions(followerTypeID)
	if not available_missions then return end
	for _, mission in ipairs(available_missions) do
		if not mission_seen[mission.missionID] then
			mission_seen[mission.missionID] = 1
			MissionMonitor_CheckAvailableMission(mission)
		end
	end
end

local function MissionMonitor_RecheckMissions()
	mission_seen = {}
	for followerTypeID, _ in pairs(follower_types) do
		MissionMonitor_CheckMissions(followerTypeID)
	end
end

event_frame:RegisterEvent("GARRISON_MISSION_FINISHED")
event_frame:RegisterEvent("GARRISON_RANDOM_MISSION_ADDED")

local addon_loaded
local followerTypeIDs = {}
event_frame:SetScript("OnEvent", function(self, event, ...)
	if (event == "ADDON_LOADED") then
		local addon_name = select(1, ...)
		if addon_name == MissionMonitorAddonName then
			addon_loaded = 1
			MissionMonitor_FlushWanted()
			for _, followerTypeID in ipairs(followerTypeIDs) do
				MissionMonitor_CheckMissions(followerTypeID)
			end
			followerTypeIDs = nil
		else
			local plan_addons = {}
			plan_addons.MasterPlan = plan_addons.MasterPlan or MasterPlan
			local plan_addon_api = plan_addons[addon_name]
			if not plan_addon_api or not plan_addon_api.RegisterMissionPriorityCallback then return end
			plan_addon_api:RegisterMissionPriorityCallback(
				"MissionMonitor",
				"Mission Monitor Wanted Reward",
				function(missionID)
					return #(MissionMonitor_MissionGetWantedItems(C_Garrison.GetBasicMissionInfo(missionID))) > 0 and 1023 or 0
				end
			)
		end
	elseif (event == "GARRISON_MISSION_LIST_UPDATE") then
		local followerTypeID = ...
		if addon_loaded then
			MissionMonitor_CheckMissions(followerTypeID)
		else
			followerTypeIDs[#followerTypeIDs + 1] = followerTypeID
		end
	elseif (event == "GARRISON_MISSION_FINISHED") then
		MissionMonitor_CheckCompleteMission(C_Garrison.GetBasicMissionInfo(select(2, ...)))
	elseif (event == "GARRISON_RANDOM_MISSION_ADDED") then
		MissionMonitor_CheckAvailableMission(C_Garrison.GetBasicMissionInfo(select(2, ...)))
	elseif (event == "GET_ITEM_INFO_RECEIVED") then
		local item, success = ...
		if not item_info_callbacks[item] then return end
		for _, callback in ipairs(item_info_callbacks[item]) do
			callback(success, item, C_Item.GetItemInfo(item))
		end
		item_info_callbacks[item] = nil
		if not next(item_info_callbacks) then
			self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		end
	end
end)

MissionMonitorOptionsMixin = {}

function MissionMonitorOptionsMixin:OnLoad()
	Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(self, self.name))
	MissionMonitorListMixin = nil
	MissionMonitorOptionsMixin = nil
	self.OnLoad = nil
end

local function MissionMonitorListLine_SetText(self, text)
	self.text:SetText(text)
	self:SetHeight(self.text:GetStringHeight() + 3)
end

local function MissionMonitorListLine_SetEntry(self, entry)
	local function set_item_link(link)
		MissionMonitorListLine_SetText(self, LinkAddIcon(link, select(5, C_Item.GetItemInfoInstant(entry)), 12))
		self:Show()
	end
	local link = select(2, C_Item.GetItemInfo(entry))
	if link then
		set_item_link(link)
	else
		item_info_add_callback(entry, function(_, _, _, link)
			set_item_link(link)
		end)
	end
end

local function MissionMonitorListLine_Anchor(self)
	self:SetPoint("LEFT")
	self:SetPoint("RIGHT")
	local parent = self:GetParent()
	if self:GetID() == 1 then
		self:SetPoint("TOP", parent.add, "BOTTOM", 0, -4)
	else
		self:SetPoint("TOP", parent.lines[self:GetID() - 1], "BOTTOM")
	end
end

local line_pool = CreateFramePool("FRAME", nil, "MissionMonitorListLine")

local function MissionMonitorList_GetVariable(self)
	if not self.variableAffix then return end
	if strsub(self.variableAffix, -5) ~= "Items" then return end
	return _G["MissionMonitor" .. self.variableAffix]
end

MissionMonitorListLineMixin = {}

function MissionMonitorListLineMixin:Delete()
	local i = self:GetID()
	local list = self:GetParent()
	local table = MissionMonitorList_GetVariable(list)
	if not table or type(table) ~= "table" or i > #table then return end
	tremove(table, i)
	MissionMonitor_FlushWanted()

	line_pool:Release(self)
	tremove(list.lines, i)
	for l = i, #list.lines do
		list.lines[l]:SetID(l)
	end
	local line = list.lines[i]
	if line then
		MissionMonitorListLine_Anchor(line)
	end
end

local function MissionMonitorList_AppendLine(self)
	local i = #self.lines + 1
	local line = line_pool:Acquire()
	self.lines[i] = line
	line:SetParent(self)
	line:SetID(i)
	MissionMonitorListLine_Anchor(line)
	return line
end

local function MissionMonitorList_UpdateItems(self)
	local entries = MissionMonitorList_GetVariable(self)
	if not entries or type(entries) ~= "table" then return end
	for i, entry in ipairs(entries) do
		MissionMonitorListLine_SetEntry(self.lines[i] or MissionMonitorList_AppendLine(self), entry)
	end
end

local function MissionMonitorList_Add(self, text)
	local number = tonumber(text)
	if number == nil then return end
	local table = MissionMonitorList_GetVariable(self)
	if not table or type(table) ~= "table" or tContains(table, number) then return end
	table[#table + 1] = number

	-- FIXME: Will not work correctly once we handle currencies
	wanted_items = { [number] = 1 }
	MissionMonitor_RecheckMissions()
	MissionMonitor_FlushWanted()
	MissionMonitorListLine_SetEntry(MissionMonitorList_AppendLine(self), number)
	self.input:SetText("")
end

MissionMonitorListMixin = {}
function MissionMonitorListMixin:OnLoad()
	self.OnLoad = nil
	self.title:SetText(self.titleText)
	self.titleText = nil
	self.label:SetText(self.labelText)
	self.labelText = nil
	self.add:SetScript("OnClick", function(self) MissionMonitorList_Add(self:GetParent(), self:GetParent().input:GetText()) end)
	self.input:SetScript("OnEnterPressed", function(self) MissionMonitorList_Add(self:GetParent(), self:GetText()) end)
	self:SetScript("OnShow", MissionMonitorList_UpdateItems)
	self.lines = {}
end
