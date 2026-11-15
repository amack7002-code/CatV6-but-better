--!nocheck
-- slop build - Fight Triage (bedwars)
-- When you are outnumbered, ranks every nearby attacker by how killable they
-- are right now (health, gear tier, who is actually swinging) and puts their
-- name on your screen so your aim follows the one who dies first.
local vape = shared.vape
if not vape then return end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local run = function(func)
	task.spawn(function()
		local Ok, Err = pcall(func)
		if not Ok then
			warn("[slop] triage error: " .. tostring(Err))
		end
	end)
end

run(function()
	local FightTriage
	local Range
	local ShowHud
	local NotifySwitch
	local TeamCheck

	local GearScores = {
		wool = 1, wood = 2, stone = 3, iron = 5, gold = 6, diamond = 8, emerald = 10,
	}

	local function GearScore(Character): number
		local Score = 0
		pcall(function()
			for _, Part in Character:GetDescendants() do
				if Part:IsA("Accessory") or Part:IsA("BasePart") then
					local Name = Part.Name:lower()
					for Gear, Points in GearScores do
						if Name:find(Gear) then
							Score = math.max(Score, Points)
						end
					end
				end
			end
		end)
		return Score
	end

	local function IsSwinging(Player: Player): boolean
		-- heuristic: swinging players have recent attack animations playing
		local Ok, Result = pcall(function()
			local Character = Player.Character
			local Animator = Character and Character:FindFirstChildOfClass("Humanoid") and Character:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
			if not Animator then return false end
			for _, Track in Animator:GetPlayingAnimationTracks() do
				local Name = Track.Animation and Track.Animation.Name:lower() or ""
				if Name:find("swing") or Name:find("attack") or Name:find("slash") then
					return true
				end
			end
			return false
		end)
		return Ok and Result == true
	end

	local function RankTargets(): {any}
		local MyChar = LocalPlayer.Character
		local MyRoot = MyChar and MyChar:FindFirstChild("HumanoidRootPart")
		local MyTeam = LocalPlayer:GetAttribute("Team")
		if not MyRoot then return {} end

		local Ranked = {}
		for _, Target in Players:GetPlayers() do
			if Target == LocalPlayer then continue end
			if TeamCheck.Enabled and Target:GetAttribute("Team") == MyTeam then continue end
			local Char = Target.Character
			local Root = Char and Char:FindFirstChild("HumanoidRootPart")
			local Humanoid = Char and Char:FindFirstChildOfClass("Humanoid")
			if not (Root and Humanoid and Humanoid.Health > 0) then continue end

			local Distance = (Root.Position - MyRoot.Position).Magnitude
			if Distance > Range.Value then continue end

			-- killability: low health + high proximity beats gear
			local HealthFactor = 1 - (Humanoid.Health / Humanoid.MaxHealth)
			local DistanceFactor = 1 - math.clamp(Distance / Range.Value, 0, 1)
			local Score = HealthFactor * 50 + DistanceFactor * 25 + GearScore(Char) * 2 + (IsSwinging(Target) and 15 or 0)
			table.insert(Ranked, {player = Target, score = Score, health = Humanoid.Health, distance = Distance})
		end
		table.sort(Ranked, function(A, B)
			return A.score > B.score
		end)
		return Ranked
	end

	shared.SlopPriorityTarget = nil

	FightTriage = vape.Categories.Combat:CreateModule({
		Name = "Fight Triage",
		Function = function(Callback: boolean)
			if Callback then
				local Hud = nil
				local Loop
				local Acc = 0
				Loop = RunService.Heartbeat:Connect(function(Delta)
					-- 4hz: ranking every frame burns frames for no reason
					Acc = Acc + Delta
					if Acc < 0.25 then return end
					Acc = 0
					local Ranked = RankTargets()
					shared.SlopPriorityTarget = Ranked[1] and Ranked[1].player or nil

					if ShowHud.Enabled then
						if not Hud then
							local GuiParent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
							local ScreenGui = Instance.new("ScreenGui")
							ScreenGui.Name = "SlopTriage"
							ScreenGui.ResetOnSpawn = false
							pcall(function()
								setthreadidentity(8)
								ScreenGui.Parent = GuiParent
							end)
							local Label = Instance.new("TextLabel")
							Label.Size = UDim2.fromOffset(240, 46)
							Label.Position = UDim2.new(0.5, -120, 0.72, 0)
							Label.BackgroundColor3 = Color3.fromRGB(20, 16, 28)
							Label.BackgroundTransparency = 0.35
							Label.Font = Enum.Font.GothamBold
							Label.TextSize = 14
							Label.TextColor3 = Color3.fromRGB(245, 240, 255)
							Label.ZIndex = 50
							Instance.new("UICorner", Label).CornerRadius = UDim.new(0, 8)
							Label.Parent = ScreenGui
							Hud = ScreenGui
						end
						local Label = Hud:FindFirstChildOfClass("TextLabel")
						if #Ranked > 0 then
							local Lines = {}
							for i = 1, math.min(3, #Ranked) do
								local Entry = Ranked[i]
								local Marker = i == 1 and "KILL FIRST" or (i .. ")")
								table.insert(Lines, Marker .. " " .. Entry.player.Name .. " - " .. math.floor(Entry.health) .. "hp")
							end
							Label.Text = table.concat(Lines, "\n")
						else
							Label.Text = ""
						end
					end

					if NotifySwitch.Enabled and Ranked[1] and shared.__SlopLastPriority ~= Ranked[1].player then
						shared.__SlopLastPriority = Ranked[1].player
						vape:CreateNotification("Fight Triage", "Kill first: " .. Ranked[1].player.Name .. " (" .. math.floor(Ranked[1].health) .. "hp)", 5, "info")
					end
				end)
				FightTriage:Clean(Loop)
			else
				shared.SlopPriorityTarget = nil
				local GuiParent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
				local Hud = GuiParent and GuiParent:FindFirstChild("SlopTriage")
				if Hud then Hud:Destroy() end
			end
		end,
		Tooltip = "Outnumbered? Ranks attackers by killability and points you at the one who dies first",
	})

	Range = FightTriage:CreateSlider({
		Name = "Range",
		Min = 8,
		Max = 40,
		Default = 18,
		Suffix = " studs",
		Tooltip = "Only ranks attackers inside this range",
	})
	ShowHud = FightTriage:CreateToggle({
		Name = "HUD",
		Default = true,
		Tooltip = "Shows the kill-first list on screen",
	})
	NotifySwitch = FightTriage:CreateToggle({
		Name = "Notify target",
		Default = false,
		Tooltip = "Notification when the priority target changes",
	})
	TeamCheck = FightTriage:CreateToggle({
		Name = "Team check",
		Default = true,
		Tooltip = "Ignores teammates",
	})
end)
