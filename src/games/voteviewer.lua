--!nocheck
-- slop build - Vote Viewer (bedwars pre-match voting)
-- Transparent overlay on the game's voting UI: live counts + percentage bars
-- per option, voter names when the game exposes them. Dismisses itself the
-- moment the official non-transparent results reveal.
local vape = shared.vape
if not vape then return end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local run = function(func)
	task.spawn(function()
		local Ok, Err = pcall(func)
		if not Ok then
			warn("[slop] voteviewer error: " .. tostring(Err))
		end
	end)
end

run(function()
	local VoteViewer
	local Opacity
	local ShowNames
	local ShowPercent
	local BarHeight
	local Position
	local AutoDismiss

	-- resolve the game's voting state
	local Store, VoteState
	local function Resolve(): boolean
		if VoteState then return true end
		pcall(function()
			if not Store then
				Store = require(ReplicatedStorage.TS.games.bedwars.controllers["voting-controller"])
			end
		end)
		pcall(function()
			if not VoteState then
				VoteState = require(ReplicatedStorage.TS.data["game-voting"])
			end
		end)
		return Store ~= nil or VoteState ~= nil
	end

	-- read votes: returns {options = {{name, count, voters?}}, revealed = bool}
	local function ReadVotes()
		local Result = nil
		pcall(function()
			local State = nil
			-- several storage shapes depending on game version
			pcall(function()
				local ClientStore = require(ReplicatedStorage.TS.controllers["global-store"]).GlobalStore
				State = ClientStore:getState().Game.voting or ClientStore:getState().Voting
			end)
			if not State then
				State = Store and Store.getVotingState and Store:getVotingState()
			end
			if type(State) ~= "table" then return end

			local Options = {}
			local Revealed = State.revealed == true or State.showResults == true
			-- shape 1: options table with votes arrays
			if type(State.options) == "table" then
				for _, Option in State.options do
					if type(Option) == "table" then
						local Count = 0
						local Voters = {}
						if type(Option.votes) == "table" then
							for _, Voter in Option.votes do
								Count = Count + 1
								if typeof(Voter) == "Instance" then
									table.insert(Voters, Voter.Name)
								elseif type(Voter) == "string" then
									table.insert(Voters, Voter)
								end
							end
						elseif type(Option.votes) == "number" then
							Count = Option.votes
						end
						table.insert(Options, {
							name = Option.displayName or Option.name or Option.mapId or "Option",
							count = Count,
							voters = Voters,
						})
					end
				end
			end
			-- shape 2: map votes dictionary {optionName = {userId=true}}
			if type(State.votes) == "table" and #Options == 0 then
				for OptionName, Voters in State.votes do
					local Count = 0
					local Names = {}
					if type(Voters) == "table" then
						for UserId in Voters do
							Count = Count + 1
							local Voter = Players:GetPlayerByUserId(tonumber(UserId) or 0)
							table.insert(Names, Voter and Voter.Name or tostring(UserId))
						end
					end
					table.insert(Options, {name = tostring(OptionName), count = Count, voters = Names})
				end
			end
			if #Options > 0 then
				Result = {options = Options, revealed = Revealed}
			end
		end)
		return Result
	end

	-- fallback: read vote counts from the game's own voting GUI frames when
	-- the store shape is unknown
	local function ReadVotesFromGui()
		local Result = nil
		pcall(function()
			local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
			local VotingGui = PlayerGui and PlayerGui:FindFirstChild("VotingApp")
			if not VotingGui then return end
			local Options = {}
			pcall(function()
				for _, Frame in VotingGui:GetDescendants() do
					if Frame:IsA("Frame") and Frame.Name:find("Option") then
						local CountLabel = Frame:FindFirstChild("VoteCount", true) or Frame:FindFirstChild("Count", true)
						local NameLabel = Frame:FindFirstChild("Title", true) or Frame:FindFirstChild("Name", true)
						table.insert(Options, {
							name = NameLabel and NameLabel.Text or Frame.Name,
							count = CountLabel and (tonumber(CountLabel.Text) or 0) or 0,
							voters = {},
						})
					end
				end
			end)
			if #Options > 0 then
				Result = {options = Options, revealed = false}
			end
		end)
		return Result
	end

	-- ========== overlay ui ==========
	local Overlay, OptionsFrame
	local function BuildOverlay()
		if Overlay then return end
		local GuiParent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		Overlay = Instance.new("ScreenGui")
		Overlay.Name = "SlopVoteViewer"
		Overlay.ResetOnSpawn = false
		Overlay.DisplayOrder = 40
		pcall(function()
			if setthreadidentity and getthreadidentity and getthreadidentity() < 8 then
				setthreadidentity(8)
			end
			Overlay.Parent = GuiParent
		end)
		if not Overlay.Parent then
			Overlay.Parent = GuiParent
		end

		local Panel = Instance.new("Frame")
		Panel.Name = "Panel"
		Panel.Size = UDim2.fromOffset(230, 30)
		Panel.Position = UDim2.new(1, -250, 0.25, 0)
		Panel.BackgroundColor3 = Color3.fromRGB(24, 16, 38)
		Panel.BackgroundTransparency = 1
		Panel.BorderSizePixel = 0
		Panel.AutomaticSize = Enum.AutomaticSize.Y
		Panel.ClipsDescendants = false
		Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 10)
		local Stroke = Instance.new("UIStroke")
		Stroke.Thickness = 1
		Stroke.Color = Color3.fromRGB(176, 156, 224)
		Stroke.Transparency = 0.5
		Stroke.Parent = Panel
		Panel.Parent = Overlay
		OptionsFrame = Panel

		local Header = Instance.new("TextLabel")
		Header.Size = UDim2.new(1, -16, 0, 22)
		Header.Position = UDim2.new(0, 8, 0, 4)
		Header.BackgroundTransparency = 1
		Header.Font = Enum.Font.GothamBold
		Header.TextSize = 12
		Header.TextColor3 = Color3.fromRGB(245, 240, 255)
		Header.TextXAlignment = Enum.TextXAlignment.Left
		Header.Text = "Live votes"
		Header.Parent = Panel
	end

	local function ClearOptions()
		if not OptionsFrame then return end
		for _, Child in OptionsFrame:GetChildren() do
			if Child:IsA("Frame") then
				Child:Destroy()
			end
		end
	end

	local function RenderOptions(Data)
		ClearOptions()
		local Total = 0
		for _, Option in Data.options do
			Total = Total + Option.count
		end
		local Order = 0
		for _, Option in Data.options do
			Order = Order + 1
			local Percent = Total > 0 and (Option.count / Total) or 0

			local Row = Instance.new("Frame")
			Row.Name = "VoteOption" .. Order
			Row.Size = UDim2.new(1, -12, 0, BarHeight.Value + 22)
			Row.Position = UDim2.new(0, 6, 0, 26 + (Order - 1) * (BarHeight.Value + 26))
			Row.BackgroundTransparency = 1
			Row.Parent = OptionsFrame

			local Name = Instance.new("TextLabel")
			Name.Size = UDim2.new(1, 0, 0, 14)
			Name.BackgroundTransparency = 1
			Name.Font = Enum.Font.GothamMedium
			Name.TextSize = 11
			Name.TextColor3 = Color3.fromRGB(220, 210, 240)
			Name.TextXAlignment = Enum.TextXAlignment.Left
			Name.TextTruncate = Enum.TextTruncate.AtEnd
			Name.Text = Option.name .. "  (" .. Option.count .. ")"
			Name.Parent = Row

			local BarBack = Instance.new("Frame")
			BarBack.Size = UDim2.new(1, 0, 0, BarHeight.Value)
			BarBack.Position = UDim2.new(0, 0, 0, 16)
			BarBack.BackgroundColor3 = Color3.fromRGB(60, 45, 90)
			BarBack.BackgroundTransparency = 0.3
			BarBack.BorderSizePixel = 0
			Instance.new("UICorner", BarBack).CornerRadius = UDim.new(1, 0)
			BarBack.Parent = Row

			local BarFill = Instance.new("Frame")
			BarFill.Size = UDim2.fromScale(Percent, 1)
			BarFill.BackgroundColor3 = Color3.fromRGB(240, 150, 70)
			BarFill.BackgroundTransparency = 0.25
			BarFill.BorderSizePixel = 0
			Instance.new("UICorner", BarFill).CornerRadius = UDim.new(1, 0)
			BarFill.Parent = BarBack
			game:GetService("TweenService"):Create(BarFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.fromScale(Percent, 1)}):Play()

			if ShowPercent.Enabled then
				local PercentLabel = Instance.new("TextLabel")
				PercentLabel.Size = UDim2.new(1, 0, 1, 0)
				PercentLabel.BackgroundTransparency = 1
				PercentLabel.Font = Enum.Font.GothamBold
				PercentLabel.TextSize = 10
				PercentLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				PercentLabel.Text = math.floor(Percent * 100 + 0.5) .. "%"
				PercentLabel.Parent = BarBack
			end

			if ShowNames.Enabled and #Option.voters > 0 then
				local Voters = Instance.new("TextLabel")
				Voters.Size = UDim2.new(1, 0, 0, 12)
				Voters.Position = UDim2.new(0, 0, 0, 16 + BarHeight.Value)
				Voters.BackgroundTransparency = 1
				Voters.Font = Enum.Font.Gotham
				Voters.TextSize = 9
				Voters.TextColor3 = Color3.fromRGB(170, 160, 200)
				Voters.TextXAlignment = Enum.TextXAlignment.Left
				Voters.TextTruncate = Enum.TextTruncate.AtEnd
				Voters.Text = table.concat(Option.voters, ", ")
				Voters.Parent = Row
			end
		end
		-- grow panel to fit
		OptionsFrame.Size = UDim2.fromOffset(230, 30 + Order * (BarHeight.Value + 26))
	end

	VoteViewer = vape.Categories.Render:CreateModule({
		Name = "Vote Viewer",
		Function = function(Callback: boolean)
			if Callback then
				BuildOverlay()
				local Missed = 0
				local Loop
				Loop = RunService.Heartbeat:Connect(function()
					-- poll at 4hz: votes change slowly, no need for every frame
					Missed = Missed + 1
					if Missed < 15 then return end
					Missed = 0

					if not Resolve() then return end
					local Data = ReadVotes() or ReadVotesFromGui()
					if not Data then
						if Overlay then Overlay.Enabled = false end
						return
					end

					-- official reveal: the real results show themselves, drop ours
					if Data.revealed then
						if AutoDismiss.Enabled and Overlay then
							Overlay.Enabled = false
						end
						return
					end

					Overlay.Enabled = true
					OptionsFrame.BackgroundTransparency = 1 - Opacity.Value / 100
					RenderOptions(Data)
				end)
				VoteViewer:Clean(Loop)
			else
				if Overlay then
					Overlay:Destroy()
					Overlay = nil
					OptionsFrame = nil
				end
			end
		end,
		Tooltip = "Live vote counts and percentage bars over the voting UI - hides itself when the official results reveal",
	})

	Opacity = VoteViewer:CreateSlider({
		Name = "Opacity",
		Min = 10,
		Max = 90,
		Default = 45,
		Suffix = "%",
		Tooltip = "How solid the overlay panel is - low values keep it see-through",
	})
	ShowNames = VoteViewer:CreateToggle({
		Name = "Show voters",
		Default = true,
		Tooltip = "Lists voter names under each option when the game exposes them (falls back to counts only)",
	})
	ShowPercent = VoteViewer:CreateToggle({
		Name = "Show percent",
		Default = true,
		Tooltip = "Percentage on each bar",
	})
	BarHeight = VoteViewer:CreateSlider({
		Name = "Bar height",
		Min = 6,
		Max = 18,
		Default = 10,
		Suffix = "px",
		Tooltip = "Height of the percentage bars",
	})
	Position = VoteViewer:CreateDropdown({
		Name = "Position",
		List = {"Right", "Left"},
		Default = "Right",
		Tooltip = "Which side of the screen the overlay sits on",
		Function = function(Value)
			if OptionsFrame then
				OptionsFrame.Position = Value == "Left" and UDim2.new(0, 20, 0.25, 0) or UDim2.new(1, -250, 0.25, 0)
			end
		end,
	})
	AutoDismiss = VoteViewer:CreateToggle({
		Name = "Auto dismiss",
		Default = true,
		Tooltip = "Removes the overlay the moment the official results reveal",
	})
end)
