--!nocheck
-- slop build - staff detector (adapted, catvape style, bedwars)
local vape = shared.vape
if not vape then return end

local run = function(func)
	local ok, err = task.spawn(pcall, func)
	if not ok then warn("[catvape] detector error: " .. tostring(err)) end
end

local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local function notif(...)
	return vape:CreateNotification(...)
end

local function getRole(Player: Player, GroupId: number): number
	local Success, Rank
	for _ = 1, 3 do
		Success, Rank = pcall(function()
			return Player:GetRankInGroup(GroupId)
		end)
		if Success then break end
	end
	return Success and Rank or 0
end

local function getLowestStaffRole(Roles): number
	local Highest = math.huge
	for _, v in Roles do
		local Low = v.Name:lower()
		if (Low:find("admin") or Low:find("mod") or Low:find("dev")) and v.Rank < Highest then
			Highest = v.Rank
		end
	end
	return Highest
end

run(function()
	local StaffDetector
	local Mode
	local Users
	local Group
	local Role

	local AutoSetup = function(): boolean
		if Group.Value ~= "" and Role.Value ~= "" then
			return true
		end

		local PlaceInfo = { Creator = { CreatorTargetId = tonumber(Group.Value) } }
		pcall(function()
			PlaceInfo = MarketplaceService:GetProductInfo(game.PlaceId)
			if PlaceInfo.Creator.CreatorType ~= "Group" then
				for _, str in PlaceInfo.Description:split("\n") do
					local _, Begin = str:find("roblox.com/groups/")
					if Begin then
						local End = str:find("/", Begin + 1)
						PlaceInfo = {
							Creator = {
								CreatorType = "Group",
								CreatorTargetId = str:sub(Begin + 1, End - 1),
							},
						}
					end
				end
			end
		end)

		if PlaceInfo.Creator.CreatorType ~= "Group" then
			notif("StaffDetector", "Automatic setup failed (no group detected)", 60, "warning")
			return false
		end

		local Success, GroupInfo = pcall(function()
			return GroupService:GetGroupInfoAsync(PlaceInfo.Creator.CreatorTargetId)
		end)
		if not Success or not GroupInfo then
			notif("StaffDetector", "Could not fetch group info", 60, "warning")
			return false
		end

		Group:SetValue(tostring(PlaceInfo.Creator.CreatorTargetId))
		Role:SetValue(tostring(getLowestStaffRole(GroupInfo.Roles)))
		return true
	end

	local function PlayerAdded(Player: Player)
		if not vape.Loaded then
			repeat task.wait() until vape.Loaded
		end

		local Blacklisted = table.find(Users.ListEnabled, tostring(Player.UserId))
		local IsStaff = getRole(Player, tonumber(Group.Value) or 0) >= (tonumber(Role.Value) or 1)
		if not Blacklisted and not IsStaff then
			return
		end

		notif("StaffDetector", `Staff detected ({Blacklisted and "blacklisted user" or "staff role"}): {Player.Name}`, 60, "alert")

		if Mode.Value == "Uninject" then
			task.spawn(function()
				vape:Uninject()
			end)
			pcall(function()
				StarterGui:SetCore("SendNotification", {
					Title = "StaffDetector",
					Text = "Staff Detected\n" .. Player.Name,
					Duration = 60,
				})
			end)
		end
	end

	StaffDetector = vape.Categories.Utility:CreateModule({
		Name = "Staff Detector",
		Function = function(Callback: boolean)
			if Callback then
				if not AutoSetup() then
					StaffDetector:Toggle()
					return
				end
				StaffDetector:Clean(Players.PlayerAdded:Connect(PlayerAdded))
				for _, v in Players:GetPlayers() do
					if v ~= LocalPlayer then
						task.spawn(PlayerAdded, v)
					end
				end
			end
		end,
		Tooltip = "Detects people with a staff rank in the game group",
	})
	Mode = StaffDetector:CreateDropdown({
		Name = "Mode",
		List = { "Notify", "Uninject" },
	})
	Users = StaffDetector:CreateTextList({
		Name = "Users",
		Placeholder = "player (userid)",
	})
	Group = StaffDetector:CreateTextBox({
		Name = "Group",
		Placeholder = "Group Id",
	})
	Role = StaffDetector:CreateTextBox({
		Name = "Role",
		Placeholder = "Role Rank",
	})
end)
