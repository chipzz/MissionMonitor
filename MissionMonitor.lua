local addon_name = ...
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

local function MissionMonitor_CheckMission(mission, alert_system, message)
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
	if #mission_wanted_items == 0 then return end

	alert_system:AddAlert(mission)
	local mission_item_links = {}
	local function print_mission_rewards()
		local links = {}
		for _, item in pairs(mission_wanted_items) do
			local link = mission_item_links[item]
			if link then
				links[#links + 1] = LinkAddIcon(link, select(5, GetItemInfoInstant(item)), 14)
			else
				return
			end
		end
		mission_item_links = nil
		local link_count = #links
		local last_link = links[link_count]
		links[link_count] = nil
		print(format(message, C_Garrison.GetMissionLink(mission.missionID), strjoin(", ", unpack(links)) .. (link_count > 1 and " and " or "") .. last_link))
	end
	for i, item in ipairs(mission_wanted_items) do
		local link = select(2, GetItemInfo(item))
		if link then
			mission_item_links[item] = link
		else
			item_info_add_callback(item, function(item, _, link)
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
		"%s is complete with wanted reward %s"
	)
end

local function MissionMonitor_CheckAvailableMission(mission)
	MissionMonitor_CheckMission(mission, GarrisonRandomMissionAlertSystem, "%s is available with wanted reward %s")
end

local mission_seen = {}
local follower_types = {}
local function MissionMonitor_CheckMissions(followerTypeID)
	follower_types[followerTypeID] = 1
	for _, mission in ipairs(C_Garrison.GetCompleteMissions(followerTypeID)) do
		if not mission_seen[mission.missionID] then
			mission_seen[mission.missionID] = 1
			MissionMonitor_CheckCompleteMission(mission)
		end
	end
	for _, mission in ipairs(C_Garrison.GetAvailableMissions(followerTypeID)) do
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
	if (event == "ADDON_LOADED" and addon_name == select(1, ...)) then
		addon_loaded = 1
		MissionMonitor_FlushWanted()
		for _, followerTypeID in ipairs(followerTypeIDs) do
			MissionMonitor_CheckMissions(followerTypeID)
		end
		followerTypeIDs = nil
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
		local item = ...
		if not item_info_callbacks[item] then return end
		for _, callback in ipairs(item_info_callbacks[item]) do
			callback(item, GetItemInfo(item))
		end
		item_info_callbacks[item] = nil
		if not next(item_info_callbacks, nil) then
			self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		end
	end
end)

MissionMonitorOptionsMixin = {}

function MissionMonitorOptionsMixin:OnLoad()
	InterfaceOptions_AddCategory(self)
	MissionMonitorOptionsMixin = nil
	self.OnLoad = nil
end

local function MissionMonitorList_GetVariable(self)
	if not self.variableAffix then return end
	if strsub(self.variableAffix, -5) ~= "Items" then return end
	return _G["MissionMonitor" .. self.variableAffix]
end

local function MissionMonitorList_UpdateItems(self)
	local entries = MissionMonitorList_GetVariable(self)
	if not entries or type(entries) ~= "table" then return end
	local entry_links = {}
	local function set_lines()
		local links = {}
		local deletes = {}
		for e, entry in pairs(entries) do
			local link = entry_links[entry]
			if link then
				links[#links + 1] = LinkAddIcon(link, select(5, GetItemInfoInstant(entry)), 12)
				deletes[#links] = format("|Hd:%i|h[Delete]|h", e)
			else
				return
			end
		end
		entry_links = nil
		self.lines:SetText(strjoin("|n", unpack(links)))
		self.deletes:SetText(strjoin("|n", unpack(deletes)))
		self:SetHeight(self.title:GetStringHeight() + 8 + self.add:GetHeight() + 4 + self.lines:GetStringHeight())
	end
	for i, entry in ipairs(entries) do
		local link = select(2, GetItemInfo(entry))
		if link then
			entry_links[entry] = link
		else
			item_info_add_callback(entry, function(entry, _, link)
				entry_links[entry] = link
				set_lines()
			end)
		end
	end
	set_lines()
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
	MissionMonitorList_UpdateItems(self)
	self.input:SetText("")
end

local function MissionMonitorList_OnHyperlinkClick(self, link, text, button)
	local t, i = strsplit(":", link)
	if t == 'd' then
		local number = tonumber(i)
		if number == nil then return end
		local table = MissionMonitorList_GetVariable(self)
		if not table or type(table) ~= "table" or number > #table then return end
		tremove(table, number)
		MissionMonitor_FlushWanted()
		MissionMonitorList_UpdateItems(self)
	else
		SetItemRef(link, text, button)
	end
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
	self:SetScript("OnHyperlinkClick", MissionMonitorList_OnHyperlinkClick)
end
