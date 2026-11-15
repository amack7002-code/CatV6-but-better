--!nocheck
-- slop build - Revamped Play UI (bedwars lobby)
-- Replaces the native play menu: when the player clicks the game's Play
-- button, the native menu closes and the liquid-glass "Select a game" menu
-- opens instead. Modes come straight from the game's QueueMeta, queueing goes
-- through the game's own QueueController - so it stays working when the game
-- updates its mode list.
local vape = shared.vape
if not vape then return end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local run = function(func)
	task.spawn(function()
		local Ok, Err = pcall(func)
		if not Ok then
			warn("[slop] playui error: " .. tostring(Err))
		end
	end)
end

run(function()
	-- resolve game controllers lazily; retry until Knit is up
	local KnitClient, QueueController, QueueMeta, AppController, UILayers
	local function Resolve(): boolean
		if QueueController and QueueMeta then return true end
		pcall(function()
			if not KnitClient then
				KnitClient = require(ReplicatedStorage.rbxts_include.node_modules["@easy-games"].knit.src.Knit.KnitClient)
			end
			if not QueueController and KnitClient.Controllers and KnitClient.Controllers.QueueController then
				QueueController = KnitClient.Controllers.QueueController
			end
			if not QueueMeta then
				QueueMeta = require(ReplicatedStorage.TS.game["queue-meta"]).QueueMeta
			end
			if not AppController and KnitClient.Controllers and KnitClient.Controllers.AppController then
				AppController = KnitClient.Controllers.AppController
			end
			if not UILayers then
				UILayers = require(ReplicatedStorage["rbxts_include"]["node_modules"]["@easy-games"]["game-core"].out).UILayers
			end
		end)
		return QueueController ~= nil and QueueMeta ~= nil
	end

	-- wait for game setup (flamework line in output)
	ReplicatedStorage:WaitForChild("rbxts_include", 30)

	-- ========== theme ==========
	local THEME = {
		tint = Color3.fromRGB(176, 156, 224),
		tintSelected = Color3.fromRGB(240, 150, 70),
		text = Color3.fromRGB(245, 240, 255),
		textSecondary = Color3.fromRGB(200, 188, 230),
		stroke = Color3.fromRGB(20, 12, 36),
		dim = Color3.fromRGB(18, 12, 30),
	}

	-- ========== screen ==========
	local GuiParent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "SlopPlayUI"
	ScreenGui.IgnoreGuiInset = true
	ScreenGui.ResetOnSpawn = false
	ScreenGui.DisplayOrder = 60
	ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ScreenGui.Parent = GuiParent

	local Dim = Instance.new("Frame")
	Dim.Size = UDim2.fromScale(1, 1)
	Dim.BackgroundColor3 = THEME.dim
	Dim.BackgroundTransparency = 1
	Dim.BorderSizePixel = 0
	Dim.Parent = ScreenGui

	local Root = Instance.new("Frame")
	Root.AnchorPoint = Vector2.new(0.5, 0.5)
	Root.Position = UDim2.fromScale(0.5, 0.5)
	Root.Size = UDim2.fromScale(0.72, 0.68)
	Root.BackgroundTransparency = 1
	Root.Visible = false
	Root.Parent = ScreenGui

	local Title = Instance.new("TextLabel")
	Title.BackgroundTransparency = 1
	Title.Size = UDim2.new(1, 0, 0, 40)
	Title.Position = UDim2.new(0, 0, 0.02, 0)
	Title.Font = Enum.Font.GothamBold
	Title.Text = "Select a game"
	Title.TextColor3 = Color3.fromRGB(245, 238, 220)
	Title.TextSize = 34
	Title.Parent = Root

	local Scroller = Instance.new("ScrollingFrame")
	Scroller.Size = UDim2.new(1, 0, 1, -80)
	Scroller.Position = UDim2.new(0, 0, 0.12, 0)
	Scroller.BackgroundTransparency = 1
	Scroller.BorderSizePixel = 0
	Scroller.ScrollBarThickness = 3
	Scroller.CanvasSize = UDim2.new()
	Scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Scroller.Parent = Root

	local Grid = Instance.new("UIGridLayout")
	Grid.CellSize = UDim2.fromScale(0.185, 0)
	Grid.CellPadding = UDim2.fromScale(0.015, 0.02)
	Grid.SortOrder = Enum.SortOrder.LayoutOrder
	Grid.Parent = Scroller
	local AspectCell = Instance.new("UIAspectRatioConstraint")
	AspectCell.AspectRatio = 1.15
	AspectCell.AspectType = Enum.AspectType.ScaleWithParentSize
	AspectCell.DominantAxis = Enum.DominantAxis.Width
	AspectCell.Parent = Grid

	-- glass card factory (compact 5-layer liquid glass)
	local function CreateCard(Parent, Tint)
		local Body = Instance.new("TextButton")
		Body.Text = ""
		Body.AutoButtonColor = false
		Body.BackgroundColor3 = Tint
		Body.BackgroundTransparency = 0.72
		Body.BorderSizePixel = 0
		Body.ClipsDescendants = true
		Instance.new("UICorner", Body).CornerRadius = UDim.new(0, 22)

		local Stroke = Instance.new("UIStroke")
		Stroke.Thickness = 1.5
		Stroke.Color = Color3.new(1, 1, 1)
		Stroke.Transparency = 0.35
		Stroke.Parent = Body

		local Sheen = Instance.new("Frame")
		Sheen.Size = UDim2.new(1, 0, 0.5, 0)
		Sheen.BackgroundColor3 = Color3.new(1, 1, 1)
		Sheen.BackgroundTransparency = 0.88
		Sheen.BorderSizePixel = 0
		local SheenGradient = Instance.new("UIGradient")
		SheenGradient.Rotation = 90
		SheenGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.78),
			NumberSequenceKeypoint.new(1, 1),
		})
		SheenGradient.Parent = Sheen
		Sheen.Parent = Body

		local Scale = Instance.new("UIScale")
		Scale.Parent = Body

		Body.MouseEnter:Connect(function()
			TweenService:Create(Body, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 0.6}):Play()
			TweenService:Create(Stroke, TweenInfo.new(0.2), {Transparency = 0.15}):Play()
			TweenService:Create(Scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.04}):Play()
		end)
		Body.MouseLeave:Connect(function()
			TweenService:Create(Body, TweenInfo.new(0.2), {BackgroundTransparency = 0.72}):Play()
			TweenService:Create(Stroke, TweenInfo.new(0.2), {Transparency = 0.35}):Play()
			TweenService:Create(Scale, TweenInfo.new(0.2), {Scale = 1}):Play()
		end)

		Body.Parent = Parent
		return Body
	end

	-- forward declarations so card callbacks capture the real functions
	local OpenMenu, CloseMenu

	-- build mode cards from the game's own queue metadata
	local Built = false
	local function BuildCards()
		if Built or not QueueMeta then return end
		for Child in Scroller:GetChildren() do
			if Child:IsA("TextButton") then Child:Destroy() end
		end
		local Order = 0
		local FirstId = nil
		for QueueType, Meta in QueueMeta do
			if type(Meta) == "table" and not Meta.disabled and not Meta.voiceChatOnly then
				Order = Order + 1
				if not FirstId then FirstId = QueueType end
				local Card = CreateCard(Scroller, THEME.tint)
				Card.LayoutOrder = Order

				local Name = Instance.new("TextLabel")
				Name.BackgroundTransparency = 1
				Name.Size = UDim2.new(1, -12, 0, 20)
				Name.Position = UDim2.new(0, 6, 0, 8)
				Name.Font = Enum.Font.GothamBold
				Name.Text = (Meta.displayName and tostring(Meta.displayName)) or QueueType
				Name.TextSize = 14
				Name.TextColor3 = THEME.text
				Name.TextXAlignment = Enum.TextXAlignment.Left
				Name.ZIndex = 3
				Name.Parent = Card

				local Players2 = Instance.new("TextLabel")
				Players2.BackgroundTransparency = 1
				Players2.Size = UDim2.new(1, -12, 0, 14)
				Players2.Position = UDim2.new(0, 6, 0, 28)
				Players2.Font = Enum.Font.GothamMedium
				Players2.Text = Meta.rankCategory and "Ranked" or "Casual"
				Players2.TextSize = 11
				Players2.TextColor3 = THEME.textSecondary
				Players2.TextXAlignment = Enum.TextXAlignment.Left
				Players2.ZIndex = 3
				Players2.Parent = Card

				Card.MouseButton1Click:Connect(function()
					pcall(function()
						QueueController:joinQueue(QueueType)
					end)
					CloseMenu()
				end)
			end
		end
		Built = Order > 0
	end

	-- ========== open / close ==========
	local function BlurIn()
		local Blur = Lighting:FindFirstChild("SlopPlayBlur") :: BlurEffect?
		if not Blur then
			Blur = Instance.new("BlurEffect")
			Blur.Name = "SlopPlayBlur"
			Blur.Size = 0
			Blur.Parent = Lighting
		end
		TweenService:Create(Blur, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = 18}):Play()
		TweenService:Create(Dim, TweenInfo.new(0.3), {BackgroundTransparency = 0.45}):Play()
	end

	local function BlurOut()
		local Blur = Lighting:FindFirstChild("SlopPlayBlur") :: BlurEffect?
		if Blur then
			TweenService:Create(Blur, TweenInfo.new(0.3), {Size = 0}):Play()
		end
		TweenService:Create(Dim, TweenInfo.new(0.25), {BackgroundTransparency = 1}):Play()
	end

	OpenMenu = function()
		BuildCards()
		if not Built then return end
		Root.Visible = true
		BlurIn()
	end

	CloseMenu = function()
		Root.Visible = false
		BlurOut()
	end

	-- ========== hook the native play menu ==========
	-- when the MAIN layer opens (native play menu), close it and show ours
	task.spawn(function()
		while true do
			task.wait(0.25)
			local Ok, IsOpen = pcall(function()
				return AppController ~= nil and UILayers ~= nil and AppController:isLayerOpen(UILayers.MAIN)
			end)
			if Ok and IsOpen and not Root.Visible then
				pcall(function()
					AppController:closeLayer(UILayers.MAIN)
				end)
				OpenMenu()
			end
		end
	end)

	-- close on backslash or when a match starts
	local UserInput = game:GetService("UserInputService")
	UserInput.InputBegan:Connect(function(Input, Processed)
		if Processed then return end
		if Input.KeyCode == Enum.KeyCode.BackSlash and Root.Visible then
			CloseMenu()
		end
	end)

end)
