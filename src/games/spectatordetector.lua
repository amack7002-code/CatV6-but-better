--!nocheck
-- slop build - spectator detector (bedwars)
-- Spectators sit in the Players service but never get a Team attribute, so
-- they never appear on the leaderboard. Notifies on joins AND leaves.
-- Both behaviors are individually toggleable.
local vape = shared.vape
if not vape then return end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local run = function(func)
	task.spawn(function()
		local Ok, Err = pcall(func)
		if not Ok then
			warn("[slop] spectator error: " .. tostring(Err))
		end
	end)
end

run(function()
	local SpectatorDetector
	local NotifyJoins
	local NotifyLeaves
	local Announced = {}

	local function Check(Player: Player): boolean
		if Player == LocalPlayer then return false end
		return Player:GetAttribute("Team") == nil
	end

	local function WatchPlayer(Player: Player)
		-- grace: joining players get their team a moment late
		local Deadline = os.clock() + 6
		repeat
			task.wait(0.5)
		until not Player.Parent or os.clock() > Deadline
		if not Player.Parent then return end

		if Check(Player) then
			Announced[Player] = true
			if NotifyJoins.Enabled then
				vape:CreateNotification("Spectator Detector", "Spectator joined: " .. Player.Name, 60, "alert")
			end
			-- watch for the leave
			local Left = Player.AncestryChanged:Connect(function()
				if not Player.Parent and Announced[Player] then
					Announced[Player] = nil
					if NotifyLeaves.Enabled then
						vape:CreateNotification("Spectator Detector", "Spectator left: " .. Player.Name, 60, "alert")
					end
				end
			end)
			SpectatorDetector:Clean(Left)
			-- if they stopped spectating by joining a team, stop tracking
			task.spawn(function()
				while Player.Parent and Announced[Player] do
					if Player:GetAttribute("Team") ~= nil then
						Announced[Player] = nil
						if NotifyLeaves.Enabled then
							vape:CreateNotification("Spectator Detector", "Spectator stopped watching: " .. Player.Name, 60, "alert")
						end
						break
					end
					task.wait(2)
				end
			end)
		end
	end

	SpectatorDetector = vape.Categories.Utility:CreateModule({
		Name = "Spectator Detector",
		Function = function(Callback: boolean)
			if Callback then
				table.clear(Announced)
				SpectatorDetector:Clean(Players.PlayerAdded:Connect(function(Player)
					task.spawn(WatchPlayer, Player)
				end))
				for _, v in Players:GetPlayers() do
					task.spawn(WatchPlayer, v)
				end
			else
				table.clear(Announced)
			end
		end,
		Tooltip = "Notifies when spectators join or leave the server - players in the game that are not on the leaderboard",
	})

	NotifyJoins = SpectatorDetector:CreateToggle({
		Name = "Notify joins",
		Default = true,
		Tooltip = "Notify when a spectator joins the server",
	})
	NotifyLeaves = SpectatorDetector:CreateToggle({
		Name = "Notify leaves",
		Default = true,
		Tooltip = "Notify when a spectator leaves or stops spectating",
	})
end)
