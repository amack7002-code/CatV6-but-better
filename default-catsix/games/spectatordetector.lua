--!nocheck
-- slop build - spectator detector (bedwars)
-- Spectators sit in the Players service but never get a Team attribute,
-- so they never appear on the leaderboard. Notify the username when found.
local vape = shared.vape
if not vape then return end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local run = function(func)
	task.spawn(pcall, func)
end

run(function()
	local SpectatorDetector
	local Announced = {}

	local function Check(Player: Player): boolean
		if Player == LocalPlayer then return false end
		return Player:GetAttribute("Team") == nil
	end

	local function PlayerAdded(Player: Player)
		if not vape.Loaded then
			repeat task.wait() until vape.Loaded
		end
		if Announced[Player] then return end

		-- grace: joining players get their team a moment late
		local Deadline = os.clock() + 6
		repeat task.wait(0.5) until not Player.Parent or os.clock() > Deadline
		if not Player.Parent then return end

		if Check(Player) then
			Announced[Player] = true
			vape:CreateNotification("Spectator Detector", "Spectator: " .. Player.Name, 60, "alert")
		end
	end

	SpectatorDetector = vape.Categories.Utility:CreateModule({
		Name = "Spectator Detector",
		Function = function(Callback: boolean)
			if Callback then
				table.clear(Announced)
				SpectatorDetector:Clean(Players.PlayerAdded:Connect(PlayerAdded))
				for _, v in Players:GetPlayers() do
					task.spawn(PlayerAdded, v)
				end
			else
				table.clear(Announced)
			end
		end,
		Tooltip = "Notifies you when someone is in the server that is not on the leaderboard",
	})
end)
