--!nocheck
-- slop build - Projectile Lead Sync (bedwars)
-- Tracks every enemy's network position in a rolling buffer, and when a
-- projectile launches, re-aims it at where the target WILL be - including
-- half-ping compensation so the hit lands the frame you see it.
local vape = shared.vape
if not vape then return end
if shared.catvapesupported == false then return end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

run = run or function(func)
	task.spawn(function()
		local Ok, Err = pcall(func)
		if not Ok then
			warn("[slop] leadsync error: " .. tostring(Err))
		end
	end)
end

run(function()
	local ProjectileLeadSync
	local LeadStrength
	local PingOffset
	local PredictTime
	local TeamCheck
	local BufferSeconds

	-- rolling position buffers per player: {{t, pos}, ...}
	local Buffers = {}

	local function Record(Player: Player, Position: Vector3)
		local Buffer = Buffers[Player]
		if not Buffer then
			Buffer = {{}, {}}
			Buffers[Player] = Buffer
		end
		local Now = os.clock()
		table.insert(Buffer[1], Now)
		table.insert(Buffer[2], Position)
		-- trim older than buffer window
		while #Buffer[1] > 0 and Now - Buffer[1][1] > (BufferSeconds.Value / 1000) do
			table.remove(Buffer[1], 1)
			table.remove(Buffer[2], 1)
		end
	end

	local function GetVelocity(Player: Player): Vector3
		local Buffer = Buffers[Player]
		if not Buffer or #Buffer[1] < 2 then
			return Vector3.zero
		end
		local First, Last = 1, #Buffer[1]
		local Dt = Buffer[1][Last] - Buffer[1][First]
		if Dt < 0.01 then
			return Vector3.zero
		end
		return (Buffer[2][Last] - Buffer[2][First]) / Dt
	end

	local function GetPredictedPosition(Player: Player, ProjectileSpeed: number): Vector3?
		local Char = Player.Character
		local Root = Char and Char:FindFirstChild("HumanoidRootPart")
		if not Root then return nil end
		local Buffer = Buffers[Player]
		if not Buffer or #Buffer[1] < 2 then
			return Root.Position
		end

		local Velocity = GetVelocity(Player)
		local MyRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not MyRoot then return nil end

		local Distance = (Root.Position - MyRoot.Position).Magnitude
		local Speed = math.max(ProjectileSpeed, 1)
		-- travel time + half ping: aim where they are when the arrow ARRIVES
		local TravelTime = Distance / Speed
		local PingSeconds = (PingOffset.Value / 1000) / 2
		local Ahead = (TravelTime + PingSeconds) * (LeadStrength.Value / 100) * PredictTime.Value

		return Root.Position + Velocity * Ahead
	end

	-- track positions at 10hz
	local Acc = 0
	local TrackConn = RunService.Heartbeat:Connect(function(Delta)
		Acc = Acc + Delta
		if Acc < 0.1 then return end
		Acc = 0
		pcall(function()
			for _, Target in Players:GetPlayers() do
				if Target == LocalPlayer then continue end
				local Char = Target.Character
				local Root = Char and Char:FindFirstChild("HumanoidRootPart")
				if Root then
					Record(Target, Root.Position)
				end
			end
		end)
	end)

	-- hook the projectile launch: rewrite the aim toward the predicted point
	local function HookLaunch()
		pcall(function()
			local Launcher = require(ReplicatedStorage.TS.controllers["projectile"]["projectile-launcher-controller"]).ProjectileLauncherController
			if Launcher.__slopLeadHook then return end
			Launcher.__slopLeadHook = true

			local Old = Launcher.launchProjectileWithValues
			Launcher.launchProjectileWithValues = function(self, Data, ...)
				-- Data.container/targetSide logic stays intact; we only retarget
				pcall(function()
					local Projectile = Data and (Data.projectileLink or Data.projectile)
					if not Projectile then return end
					local Speed = 60 -- default arrow speed; bedswords fire ~60-90
					pcall(function()
						Speed = Data.projectileMeta and Data.projectileMeta.speed or Speed
					end)

					local Best, BestDist = nil, math.huge
					local MyRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
					if not MyRoot then return end
					local MyTeam = LocalPlayer:GetAttribute("Team")
					for _, Target in Players:GetPlayers() do
						if Target == LocalPlayer then continue end
						if TeamCheck.Enabled and Target:GetAttribute("Team") == MyTeam then continue end
						local Char = Target.Character
						local Root = Char and Char:FindFirstChild("HumanoidRootPart")
						if Root then
							local D = (Root.Position - MyRoot.Position).Magnitude
							if D < BestDist then
								Best, BestDist = Target, D
							end
						end
					end
					if not Best then return end

					local Predicted = GetPredictedPosition(Best, Speed)
					if not Predicted then return end
					if typeof(Data.aimPart) == "Instance" then
						-- retarget the launch aim
						Data.aimPart = nil
						Data.customAimPosition = Predicted
					elseif Data.mouseHit then
						Data.mouseHit = CFrame.new(Predicted)
					end
				end)
				return Old(self, Data, ...)
			end
		end)
	end

	ProjectileLeadSync = vape.Categories.Combat:CreateModule({
		Name = "Projectile Lead Sync",
		Function = function(Callback: boolean)
			if Callback then
				table.clear(Buffers)
				pcall(HookLaunch)
				-- re-hook periodically: controller rebuilds per match
				local Tick = 0
				local Loop
				Loop = RunService.Heartbeat:Connect(function(Delta)
					Tick = Tick + 1
					if Tick % 120 == 0 then
						pcall(HookLaunch)
					end
				end)
				ProjectileLeadSync:Clean(Loop)
			else
				Buffers = {}
			end
		end,
		Tooltip = "Re-aims projectiles at where enemies will be when the shot arrives - with half-ping compensation so visual and server hits match",
	})

	LeadStrength = ProjectileLeadSync:CreateSlider({
		Name = "Lead strength",
		Min = 0,
		Max = 150,
		Default = 100,
		Suffix = "%",
		Tooltip = "How far ahead of their movement the aim leads. 100 = exact intercept, higher = aggressive over-lead",
	})
	PingOffset = ProjectileLeadSync:CreateSlider({
		Name = "Ping offset",
		Min = 0,
		Max = 400,
		Default = 60,
		Suffix = "ms",
		Tooltip = "Your ping - half of it is added to the intercept so the hit lands the frame you see it",
	})
	PredictTime = ProjectileLeadSync:CreateSlider({
		Name = "Predict time",
		Min = 50,
		Max = 200,
		Default = 100,
		Suffix = "%",
		Tooltip = "Scales the whole lead calculation - lower looks more human, higher snaps harder",
	})
	TeamCheck = ProjectileLeadSync:CreateToggle({
		Name = "Team check",
		Default = true,
		Tooltip = "Never retargets teammates",
	})
	BufferSeconds = ProjectileLeadSync:CreateSlider({
		Name = "Track window",
		Min = 300,
		Max = 2000,
		Default = 800,
		Suffix = "ms",
		Tooltip = "How much movement history feeds the velocity estimate",
	})
end)
