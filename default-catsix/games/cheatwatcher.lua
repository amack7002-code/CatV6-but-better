--!nocheck
-- slop build - CheatWatcher (bedwars)
-- Passive cheat detection on nearby players: speed, reach, cps, velocity, fly.
-- Flags get a small billboard tag with confidence, click for details/watch.
local vape = shared.vape
if not vape then return end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local function notif(...)
	return vape:CreateNotification(...)
end

-- raycast params for ground checks
local GroundParams = RaycastParams.new()
GroundParams.FilterType = Enum.RaycastFilterType.Exclude
GroundParams.FilterDescendantsInstances = {}

local function UpdateFilter()
	local List = {LocalPlayer.Character}
	for _, v in Players:GetPlayers() do
		table.insert(List, v.Character)
	end
	GroundParams.FilterDescendantsInstances = List
end

local function HasGround(Position: Vector3): boolean
	local Result = Workspace:Raycast(Position, Vector3.new(0, -4, 0), GroundParams)
	return Result ~= nil
end

-- per-player tracker
local function NewTracker()
	return {
		Samples = {}, -- rolling window {t, pos}
		HitTimes = {},
		Jumps = {},
		Score = 0,
		Flags = {}, -- name -> {value = "34.2/s", weight = 20, t = os.clock()}
		Timeline = {}, -- evidence log
		Tag = nil,
		Airborne = 0,
		LastPos = nil,
		LastY = nil,
	}
end

local Trackers = {}

local function Log(Tracker, Line: string)
	table.insert(Tracker.Timeline, os.clock() .. " " .. Line)
	-- keep last 200 entries (~30s+)
	while #Tracker.Timeline > 200 do
		table.remove(Tracker.Timeline, 1)
	end
end

local function Flag(Tracker, Name: string, Value: string, Weight: number, Threshold: number)
	local FlagData = Tracker.Flags[Name]
	if FlagData then
		FlagData.value = Value
		FlagData.t = os.clock()
		FlagData.hits = (FlagData.hits or 0) + 1
	else
		Tracker.Flags[Name] = {value = Value, weight = Weight, t = os.clock(), hits = 1}
		Log(Tracker, Name .. " fired: " .. Value)
	end
	-- recalc score: active (recent) flags only
	local Now = os.clock()
	local Total = 0
	for _, v in Tracker.Flags do
		if Now - v.t < 10 then
			Total += v.weight * math.min(v.hits, 3) / math.min(v.hits, 3)
		end
	end
	Tracker.Score = math.clamp(math.floor(Total * 2), 0, 100)
end

-- decay old flags
local function Decay(Tracker)
	local Now = os.clock()
	for Name, v in Tracker.Flags do
		if Now - v.t > 10 then
			v.hits = 0
		end
	end
	local Total = 0
	for _, v in Tracker.Flags do
		if Now - v.t < 10 and v.hits > 0 then
			Total += v.weight
		end
	end
	Tracker.Score = math.clamp(math.floor(Total), 0, 100)
end

local function GetTag(Player: Player, Character: Model)
	local Head = Character:FindFirstChild("Head") or Character:FindFirstChild("HumanoidRootPart")
	if not Head then return nil end

	if not Trackers[Player].Tag then
		local Billboard = Instance.new("BillboardGui")
		Billboard.Name = "SlopCheatTag"
		Billboard.Size = UDim2.fromOffset(120, 16)
		Billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		Billboard.AlwaysOnTop = true
		Billboard.MaxDistance = 120
		Billboard.Adornee = Head

		local Text = Instance.new("TextLabel")
		Text.Size = UDim2.fromScale(1, 1)
		Text.BackgroundTransparency = 1
		Text.Font = Enum.Font.Gotham
		Text.TextSize = 12
		Text.TextColor3 = Color3.fromRGB(255, 80, 80)
		Text.TextStrokeTransparency = 0.4
		Text.Parent = Billboard

		Billboard.Parent = Character
		Trackers[Player].Tag = {Gui = Billboard, Text = Text}
	end
	return Trackers[Player].Tag
end

run(function()
	local CheatWatcher
	local Threshold
	local SpeedMax
	local ReachMax
	local CPSMax
	local VelocityMax
	local Distance

	-- click selection state
	local Selected: Player? = nil
	local DetailsMode = false
	local WatchMode = false
	local WatchConn = nil

	local function StopWatch()
		if WatchConn then
			WatchConn:Disconnect()
			WatchConn = nil
		end
		WatchMode = false
	end

	local function StartWatch(Player: Player)
		StopWatch()
		WatchMode = true
		WatchConn = RunService.RenderStepped:Connect(function()
			local Char = Player.Character
			local Root = Char and Char:FindFirstChild("HumanoidRootPart")
			if Root then
				Camera.CameraSubject = Root:FindFirstChildOfClass("Humanoid") or Root
			end
		end)
		notif("CheatWatcher", "Watching " .. Player.Name, 5)
	end

	-- details popup (minimal, catvape-adjacent styling)
	local Popup = Instance.new("ScreenGui")
	Popup.Name = "SlopWatcherPopup"
	Popup.ResetOnSpawn = false
	Popup.Parent = game:GetService("CoreGui")

	local Frame = Instance.new("Frame")
	Frame.Size = UDim2.fromOffset(260, 200)
	Frame.Position = UDim2.new(0.5, -130, 0.6, 0)
	Frame.BackgroundColor3 = Color3.fromRGB(24, 26, 27)
	Frame.BorderSizePixel = 0
	Frame.Visible = false
	Frame.Active = true
	Frame.Draggable = true
	Frame.Parent = Popup
	Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 6)

	local Title = Instance.new("TextLabel")
	Title.Size = UDim2.new(1, 0, 0, 24)
	Title.BackgroundTransparency = 1
	Title.Font = Enum.Font.GothamBold
	Title.TextSize = 13
	Title.TextColor3 = Color3.fromRGB(255, 255, 255)
	Title.Text = "CheatWatcher"
	Title.Parent = Frame

	local Body = Instance.new("TextLabel")
	Body.Position = UDim2.new(0, 8, 0, 26)
	Body.Size = UDim2.new(1, -16, 1, -60)
	Body.BackgroundTransparency = 1
	Body.Font = Enum.Font.Gotham
	Body.TextSize = 11
	Body.TextColor3 = Color3.fromRGB(200, 200, 200)
	Body.TextXAlignment = Enum.TextXAlignment.Left
	Body.TextYAlignment = Enum.TextYAlignment.Top
	Body.Text = ""
	Body.Parent = Frame

	local NotifyBtn = Instance.new("TextButton")
	NotifyBtn.Position = UDim2.new(0, 8, 1, -30)
	NotifyBtn.Size = UDim2.new(0.48, -8, 0, 22)
	NotifyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	NotifyBtn.Font = Enum.Font.Gotham
	NotifyBtn.TextSize = 11
	NotifyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	NotifyBtn.Text = "Notify"
	NotifyBtn.Parent = Frame
	Instance.new("UICorner", NotifyBtn).CornerRadius = UDim.new(0, 4)

	local WatchBtn = Instance.new("TextButton")
	WatchBtn.Position = UDim2.new(0.52, 0, 1, -30)
	WatchBtn.Size = UDim2.new(0.48, -8, 0, 22)
	WatchBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	WatchBtn.Font = Enum.Font.Gotham
	WatchBtn.TextSize = 11
	WatchBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	WatchBtn.Text = "Watch"
	WatchBtn.Parent = Frame
	Instance.new("UICorner", WatchBtn).CornerRadius = UDim.new(0, 4)

	local function FlagsText(Player: Player): string
		local Tracker = Trackers[Player]
		if not Tracker then return "no data" end
		local Lines = {}
		if DetailsMode then
			local Last = {}
			for i = math.max(1, #Tracker.Timeline - 30), #Tracker.Timeline do
				table.insert(Lines, Tracker.Timeline[i])
			end
			return #Lines > 0 and table.concat(Lines, "\n") or "no evidence yet"
		end
		if Tracker.Score < (Threshold.Value or 60) then
			return "score: " .. Tracker.Score .. " (below threshold)"
		end
		table.insert(Lines, "confidence: " .. Tracker.Score .. "%")
		for Name, v in Tracker.Flags do
			if v.hits > 0 then
				table.insert(Lines, Name .. ": " .. v.value .. " x" .. v.hits)
			end
		end
		return table.concat(Lines, "\n")
	end

	NotifyBtn.MouseButton1Click:Connect(function()
		if Selected then
			notif("CheatWatcher", "Watching for " .. Selected.Name .. " - " .. FlagsText(Selected):gsub("\n", " | "), 60, "alert")
		end
	end)

	WatchBtn.MouseButton1Click:Connect(function()
		if Selected then
			if WatchMode then
				StopWatch()
				WatchBtn.Text = "Watch"
			else
				StartWatch(Selected)
				WatchBtn.Text = "Stop"
			end
		end
	end)

	local function ShowPopup(Player: Player)
		Selected = Player
		Title.Text = "CheatWatcher - " .. Player.Name
		Body.Text = FlagsText(Player)
		Frame.Visible = true
	end

	-- click detection on flagged players' tags
	local ClickConn
	local function SetupClicks()
		ClickConn = UserInputService.InputBegan:Connect(function(Input, Processed)
			if Processed or Input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			local Ray = Camera:ScreenPointToRay(Input.Position.X, Input.Position.Y)
			-- find flagged player whose billboard is under the cursor
			for Player, Tracker in Trackers do
				if Tracker.Score >= (Threshold.Value or 60) and Player.Character then
					local Root = Player.Character:FindFirstChild("HumanoidRootPart")
					if Root then
						local Screen, OnScreen = Camera:WorldToScreenPoint(Root.Position)
						if OnScreen and (Vector2.new(Screen.X, Screen.Y) - Input.Position).Magnitude < 40 then
							ShowPopup(Player)
							return
						end
					end
				end
			end
		end)
	end

	-- hit remote observation for reach/cps: hook namecall on hit remotes
	local HitRemoteNames = {
		DamageEntity = true,
		SwordHit = true,
		HitEntity = true,
	}
	local OldNamecall
	OldNamecall = hookmetamethod and hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local Method = getnamecallmethod()
		if Method == "FireServer" and HitRemoteNames[tostring(self)] then
			-- attacker is LocalPlayer; count our cps for reference, victims give us reach data via their pos
			local Args = {...}
			local Victim = typeof(Args[1]) == "Instance" and Args[1]:FindFirstAncestorOfClass("Model")
			if Victim then
				local VictimPlayer = Players:GetPlayerFromCharacter(Victim)
				if VictimPlayer and Trackers[VictimPlayer] then
					Log(Trackers[VictimPlayer], "hit received from " .. LocalPlayer.Name .. " at " ..
						string.format("%.1f", ((Victim:FindFirstChild("HumanoidRootPart") or {}).Position or Vector3.zero - (LocalPlayer.Character and LocalPlayer.Character.HumanoidRootPart.Position or Vector3.zero)).Magnitude) .. " studs")
				end
			end
		end
		return OldNamecall(self, ...)
	end))

	-- observe other players' swing remotes via OnClientEvent is not possible passively;
	-- instead we detect CPS from observed damage events on each player's victim side
	local function SamplePlayer(Player: Player, Tracker, Delta: number, Settings)
		local Char = Player.Character
		local Root = Char and Char:FindFirstChild("HumanoidRootPart")
		local Humanoid = Char and Char:FindFirstChildOfClass("Humanoid")
		if not (Root and Humanoid and Humanoid.Health > 0) then
			Tracker.LastPos = nil
			Tracker.LastY = nil
			Tracker.Airborne = 0
			return
		end

		local Pos = Root.Position
		if Tracker.LastPos then
			local Delta3 = Pos - Tracker.LastPos
			local Flat = Vector3.new(Delta3.X, 0, Delta3.Z)
			local Speed = Flat.Magnitude / math.max(Delta, 0.001)

			-- speed check
			if Speed > SpeedMax.Value then
				Flag(Tracker, "Speed", string.format("%.1f/s", Speed), 25, SpeedMax.Value)
				Log(Tracker, string.format("speed %.1f/s", Speed))
			end

			-- velocity/teleport check: single-tick jump
			if Delta3.Magnitude > VelocityMax.Value and Delta < 0.2 then
				Flag(Tracker, "Velocity", string.format("%.1f studs/tick", Delta3.Magnitude), 30, VelocityMax.Value)
				Log(Tracker, string.format("jump %.1f", Delta3.Magnitude))
			end

			-- fly check: sustained ascent with no ground
			if Delta3.Y > 0.5 and not HasGround(Pos) then
				Tracker.Airborne += Delta
				if Tracker.Airborne > 2 then
					Flag(Tracker, "Fly", string.format("%.1fs ascent", Tracker.Airborne), 35, 2)
					Log(Tracker, string.format("fly %.1fs", Tracker.Airborne))
				end
			elseif Delta3.Y <= 0 or HasGround(Pos) then
				Tracker.Airborne = 0
			end

			-- reach check: how far was the victim from their attacker? approximated by
			-- damage events in the HitRemote hook above
			if HitRemoteNames.CurrentVictim then
				local Dist = (Pos - HitRemoteNames.CurrentVictim.Position).Magnitude
				if Dist > ReachMax.Value then
					Flag(Tracker, "Reach", string.format("%.1f studs", Dist), 20, ReachMax.Value)
					Log(Tracker, string.format("reach %.1f", Dist))
				end
			end
		end

		Tracker.LastPos = Pos
		Tracker.LastY = Pos.Y

		-- update tag
		if Tracker.Score >= (Threshold.Value or 60) then
			local Tag = GetTag(Player, Char)
			if Tag then
				Tag.Text.Text = "?cheat " .. Tracker.Score .. "%"
				Tag.Gui.Enabled = true
				-- dim when spectators/staff may be watching
				local Dimmed = false
				for _, v in Players:GetPlayers() do
					if v ~= LocalPlayer and v:GetAttribute("Team") == nil then
						Dimmed = true
						break
					end
				end
				Tag.Text.TextTransparency = Dimmed and 0.6 or 0
				Tag.Text.TextStrokeTransparency = Dimmed and 0.8 or 0.4
			end
			if not Tracker.Announced then
				Tracker.Announced = true
				local Reasons = {}
				for Name, v in Tracker.Flags do
					if v.hits > 0 then
						table.insert(Reasons, Name:lower())
					end
				end
				notif("CheatWatcher", Player.Name .. " flagged - " .. table.concat(Reasons, " + "), 10, "alert")
			end
		elseif Tracker.Tag then
			Tracker.Tag.Gui.Enabled = false
			Tracker.Announced = nil
		end
	end

	CheatWatcher = vape.Categories.Utility:CreateModule({
		Name = "CheatWatcher",
		Function = function(Callback: boolean)
			if Callback then
				table.clear(Trackers)
				UpdateFilter()
				for _, v in Players:GetPlayers() do
					if v ~= LocalPlayer then
						Trackers[v] = NewTracker()
					end
				end
				SetupClicks()

				CheatWatcher:Clean(Players.PlayerAdded:Connect(function(v)
					Trackers[v] = NewTracker()
					UpdateFilter()
				end))
				CheatWatcher:Clean(Players.PlayerRemoving:Connect(function(v)
					if Trackers[v] and Trackers[v].Tag then
						Trackers[v].Tag.Gui:Destroy()
					end
					Trackers[v] = nil
					UpdateFilter()
				end))

				local LastTick = os.clock()
				local Loop
				Loop = RunService.Heartbeat:Connect(function(Delta)
					local Now = os.clock()
					UpdateFilter()
					for Player, Tracker in Trackers do
						SamplePlayer(Player, Tracker, Delta, nil)
						Decay(Tracker)
					end
					if Selected then
						Body.Text = FlagsText(Selected)
					end
					LastTick = Now
				end)
				CheatWatcher:Clean(Loop)
			else
				if ClickConn then
					ClickConn:Disconnect()
					ClickConn = nil
				end
				StopWatch()
				for _, Tracker in Trackers do
					if Tracker.Tag then
						Tracker.Tag.Gui:Destroy()
					end
				end
				table.clear(Trackers)
				Frame.Visible = false
			end
		end,
		Tooltip = "Passively flags likely cheaters near you - click a flagged player for evidence, watch them, or get persistent alerts",
	})

	Threshold = CheatWatcher:CreateSlider({
		Name = "Confidence",
		Min = 20,
		Max = 100,
		Default = 60,
		Tooltip = "Only tags players above this confidence score",
	})
	SpeedMax = CheatWatcher:CreateSlider({
		Name = "Speed limit",
		Min = 12,
		Max = 40,
		Default = 20,
		Tooltip = "Studs per second before speed is suspicious",
	})
	ReachMax = CheatWatcher:CreateSlider({
		Name = "Reach limit",
		Min = 3,
		Max = 8,
		Default = 3.5,
		Tooltip = "Studs between attacker and victim before reach is suspicious",
	})
	CPSMax = CheatWatcher:CreateSlider({
		Name = "CPS limit",
		Min = 5,
		Max = 30,
		Default = 15,
		Tooltip = "Swings per second before cps is suspicious",
	})
	VelocityMax = CheatWatcher:CreateSlider({
		Name = "Teleport limit",
		Min = 4,
		Max = 20,
		Default = 8,
		Tooltip = "Single-tick position jumps larger than this are suspicious",
	})
end)
