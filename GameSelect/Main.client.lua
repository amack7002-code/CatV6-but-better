--!strict
--[[
	The Hollow Lobby - "Select a Game" menu
	Apple Liquid Glass style, calm Halloween night theme.
	StarterGui > GameSelectGui > Main (LocalScript)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- CONFIG (everything lives here)
-- ============================================================

type Theme = {
	glassDefault: Color3,
	glassSelected: Color3,
	glassEvent: Color3,
	glassMoss: Color3,
	glassLavender: Color3,
	textPrimary: Color3,
	textSecondary: Color3,
	textStroke: Color3,
	accent: Color3,
	dim: Color3,
	tintWarm: Color3,
}

type ModeConfig = {
	id: string,
	title: string,
	subtitle: string,
	tag: string?,
	glyph: string,
	art: number,
	stacked: boolean?,
	tile: boolean?,
}

type CardRefs = {
	frame: Frame,
	body: Frame,
	sheen: Frame,
	shine: Frame,
	stroke: UIStroke,
	scale: UIScale,
	shadow: Frame,
	art: ImageLabel?,
	glyphLabel: TextLabel?,
	title: TextLabel,
	subtitle: TextLabel,
	pill: Frame?,
	pillText: TextLabel?,
	tint: Color3,
	selected: boolean,
	hovering: boolean,
	parallaxArt: ImageLabel?,
}

type GlassRefs = {
	body: Frame,
	sheen: Frame,
	shine: Frame,
	stroke: UIStroke,
	shadow: Frame,
	scale: UIScale,
}

type SoundSet = {
	hover: number,
	click: number,
	open: number,
	close: number,
	ambient: number,
}

local THEME = {
	effects = true,
	reducedMotion = false,

	theme = {
		glassDefault = Color3.fromRGB(176, 156, 224),
		glassSelected = Color3.fromRGB(240, 150, 70),
		glassEvent = Color3.fromRGB(190, 130, 230),
		glassMoss = Color3.fromRGB(150, 190, 110),
		glassLavender = Color3.fromRGB(170, 180, 240),
		textPrimary = Color3.fromRGB(245, 240, 255),
		textSecondary = Color3.fromRGB(200, 188, 230),
		textStroke = Color3.fromRGB(20, 12, 36),
		accent = Color3.fromRGB(240, 150, 70),
		dim = Color3.fromRGB(18, 12, 30),
		tintWarm = Color3.fromRGB(214, 196, 250),
	} :: Theme,

	modes = {
		{
			id = "classic",
			title = "Classic",
			subtitle = "7 queues",
			tag = "Recommended",
			glyph = "bed",
			art = 0,
		},
		{
			id = "luckyblock",
			title = "Lucky Block",
			subtitle = "Chaos awaits",
			tag = "Fun",
			glyph = "lucky",
			art = 0,
		},
		{
			id = "arcade",
			title = "Arcade",
			subtitle = "Quick matches",
			tag = "Fast",
			glyph = "arcade",
			art = 0,
		},
		{
			id = "duos",
			title = "Duos Event",
			subtitle = "6/6 in party",
			tag = "Event",
			glyph = "key",
			art = 0,
			stacked = true,
		},
		{
			id = "squads",
			title = "Squads Event",
			subtitle = "Ends in 2d 14h",
			glyph = "clock",
			art = 0,
			stacked = true,
		},
		{
			id = "customs",
			title = "Customs",
			subtitle = "Join, host, or browse",
			glyph = "custom",
			art = 0,
			tile = true,
		},
		{
			id = "practice",
			title = "Practice",
			subtitle = "Clutch drills",
			glyph = "practice",
			art = 0,
			tile = true,
		},
		{
			id = "tutorial",
			title = "Tutorial",
			subtitle = "Learn the island",
			glyph = "tutorial",
			art = 0,
			tile = true,
		},
	} :: {ModeConfig},

	assets = {
		artClassic = 0,
		artLucky = 0,
		artArcade = 0,
		artDuos = 0,
		artSquads = 0,
		artCustoms = 0,
		artPractice = 0,
		artTutorial = 0,
		bat = 0,
		cobwebCorner = 0,
		cobwebTop = 0,
	},

	sounds = {
		hover = 0,
		click = 0,
		open = 0,
		close = 0,
		ambient = 0,
	} :: SoundSet,
}

local MODES: {ModeConfig} = THEME.modes

-- ============================================================
-- HELPERS
-- ============================================================

local connections: {RBXScriptConnection} = {}
local tweens: {Tween} = {}
local glassFolder: {Frame} = {}

local function TrackConnection(Connection: RBXScriptConnection)
	table.insert(connections, Connection)
	return Connection
end

local function TrackTween(Tween: Tween)
	table.insert(tweens, Tween)
	return Tween
end

local function PlaySound(Id: number, Volume: number?, Parent: Instance?): Sound?
	if Id == 0 then
		return nil
	end
	local Ok, Result = pcall(function()
		local Sound = Instance.new("Sound")
		Sound.SoundId = "rbxassetid://" .. tostring(Id)
		Sound.Volume = Volume or 0.5
		Sound.PlayOnRemove = true
		Sound.Parent = Parent or SoundService
		Sound:Play()
		return Sound
	end)
	if Ok then
		return Result
	end
	return nil
end

local function PreloadAssets()
	local Ids: {string} = {}
	local function Push(Id: number)
		if Id and Id ~= 0 then
			table.insert(Ids, "rbxassetid://" .. tostring(Id))
		end
	end
	Push(THEME.assets.artClassic)
	Push(THEME.assets.artLucky)
	Push(THEME.assets.artArcade)
	Push(THEME.assets.artDuos)
	Push(THEME.assets.artSquads)
	Push(THEME.assets.artCustoms)
	Push(THEME.assets.artPractice)
	Push(THEME.assets.artTutorial)
	Push(THEME.assets.bat)
	Push(THEME.assets.cobwebCorner)
	Push(THEME.assets.cobwebTop)
	Push(THEME.sounds.hover)
	Push(THEME.sounds.click)
	Push(THEME.sounds.open)
	Push(THEME.sounds.close)
	Push(THEME.sounds.ambient)
	if #Ids > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(Ids)
		end)
	end
end

-- ============================================================
-- BACKGROUND LIGHT + DIM
-- ============================================================

type LightingSnapshot = {
	blurSize: number?,
	dofFar: number?,
	dofNear: number?,
	ccTint: Color3?,
	ccSaturation: number?,
	ccBrightness: number?,
	ccContrast: number?,
}

local function ApplyLighting(Container: Instance): LightingSnapshot
	local Snapshot: LightingSnapshot = {}
	local ExistingBlur = Container:FindFirstChild("HollowBlur")
	local ExistingDof = Container:FindFirstChild("HollowDof")
	local ExistingCC = Container:FindFirstChild("HollowCC")

	local Blur: BlurEffect
	if ExistingBlur and ExistingBlur:IsA("BlurEffect") then
		Blur = ExistingBlur
		Snapshot.blurSize = Blur.Size
	else
		Blur = Instance.new("BlurEffect")
		Blur.Name = "HollowBlur"
		Blur.Size = 0
		Blur.Parent = Container
		Snapshot.blurSize = nil
	end

	local Dof: DepthOfFieldEffect
	if ExistingDof and ExistingDof:IsA("DepthOfFieldEffect") then
		Dof = ExistingDof
		Snapshot.dofFar = Dof.FarIntensity
		Snapshot.dofNear = Dof.NearIntensity
	else
		Dof = Instance.new("DepthOfFieldEffect")
		Dof.Name = "HollowDof"
		Dof.FarIntensity = 0
		Dof.FocusDistance = 0
		Dof.InFocusRadius = 0
		Dof.NearIntensity = 0
		Dof.Parent = Container
	end

	local CC: ColorCorrectionEffect
	if ExistingCC and ExistingCC:IsA("ColorCorrectionEffect") then
		CC = ExistingCC
		Snapshot.ccTint = CC.TintColor
		Snapshot.ccSaturation = CC.Saturation
		Snapshot.ccBrightness = CC.Brightness
		Snapshot.ccContrast = CC.Contrast
	else
		CC = Instance.new("ColorCorrectionEffect")
		CC.Name = "HollowCC"
		CC.TintColor = Color3.new(1, 1, 1)
		CC.Saturation = 0
		CC.Brightness = 0
		CC.Contrast = 0
		CC.Parent = Container
	end

	local Info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TrackTween(TweenService:Create(Blur, Info, {Size = 22}))
	TrackTween(TweenService:Create(Dof, Info, {FarIntensity = 0.6, FocusDistance = 0, InFocusRadius = 0, NearIntensity = 0}))
	TrackTween(TweenService:Create(CC, Info, {TintColor = THEME.theme.tintWarm, Saturation = -0.2, Brightness = -0.06, Contrast = 0.05}))

	return Snapshot
end

local function RestoreLighting(Snapshot: LightingSnapshot)
	local Info = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local Blur = Lighting:FindFirstChild("HollowBlur")
	local Dof = Lighting:FindFirstChild("HollowDof")
	local CC = Lighting:FindFirstChild("HollowCC")

	if Blur and Blur:IsA("BlurEffect") then
		local Goal: {[string]: any} = {Size = Snapshot.blurSize or 0}
		TrackTween(TweenService:Create(Blur, Info, Goal))
	end
	if Dof and Dof:IsA("DepthOfFieldEffect") then
		local Goal: {[string]: any} = {
			FarIntensity = Snapshot.dofFar or 0,
			NearIntensity = Snapshot.dofNear or 0,
		}
		TrackTween(TweenService:Create(Dof, Info, Goal))
	end
	if CC and CC:IsA("ColorCorrectionEffect") then
		local Goal: {[string]: any} = {
			TintColor = Snapshot.ccTint or Color3.new(1, 1, 1),
			Saturation = Snapshot.ccSaturation or 0,
			Brightness = Snapshot.ccBrightness or 0,
			Contrast = Snapshot.ccContrast or 0,
		}
		TrackTween(TweenService:Create(CC, Info, Goal))
	end

	task.delay(0.3, function()
		pcall(function()
			if Snapshot.blurSize == nil and Lighting:FindFirstChild("HollowBlur") then
				Lighting.HollowBlur:Destroy()
			end
			if Snapshot.dofFar == nil and Lighting:FindFirstChild("HollowDof") then
				Lighting.HollowDof:Destroy()
			end
			if Snapshot.ccTint == nil and Lighting:FindFirstChild("HollowCC") then
				Lighting.HollowCC:Destroy()
			end
		end)
	end)
end

-- ============================================================
-- LIQUID GLASS
-- ============================================================

local function createGlass(parent: Instance, config: {
	size: UDim2,
	position: UDim2?,
	tint: Color3,
	cornerRadius: number,
	transparency: number?,
	blurRadius: number?,
}): GlassRefs
	local Shadow = Instance.new("Frame")
	Shadow.Name = "GlassShadow"
	Shadow.Size = UDim2.new(config.size.X.Scale + 0.012, 0, config.size.Y.Scale + 0.03, 0)
	Shadow.Position = config.position or UDim2.new(0, 0, 0.03, 0)
	Shadow.AnchorPoint = Vector2.new(0.5, 0)
	Shadow.BackgroundColor3 = Color3.fromRGB(8, 4, 16)
	Shadow.BackgroundTransparency = 0.78
	Shadow.BorderSizePixel = 0
	Shadow.ZIndex = (parent :: Frame).ZIndex - 1
	local ShadowCorner = Instance.new("UICorner")
	ShadowCorner.CornerRadius = UDim.new(0, config.cornerRadius + 4)
	ShadowCorner.Parent = Shadow
	Shadow.Parent = parent

	local Body = Instance.new("Frame")
	Body.Name = "GlassBody"
	Body.Size = config.size
	Body.Position = config.position or UDim2.new(0, 0, 0, 0)
	Body.AnchorPoint = Vector2.new(0.5, 0)
	Body.BackgroundColor3 = config.tint
	Body.BackgroundTransparency = config.transparency or 0.72
	Body.BorderSizePixel = 0
	Body.ClipsDescendants = true
	Body.ZIndex = (parent :: Frame).ZIndex
	local BodyCorner = Instance.new("UICorner")
	BodyCorner.CornerRadius = UDim.new(0, config.cornerRadius)
	BodyCorner.Parent = Body
	Body.Parent = parent

	-- glassmorphic blur if the module exists; fallback = extra tint layer
	pcall(function()
		local Module = ReplicatedStorage:FindFirstChild("GlassmorphicUI", true)
		if Module and Module:IsA("ModuleScript") then
			local Require = require :: any
			local Glass = Require(Module)
			if type(Glass) == "table" and type(Glass.init) == "function" then
				Body:SetAttribute("GlassBlurRadius", config.blurRadius or 12)
				pcall(function()
					(Glass :: any).init(Body, config.blurRadius or 12)
				end)
			end
		else
			local Frost = Instance.new("Frame")
			Frost.Name = "GlassFrost"
			Frost.Size = UDim2.fromScale(1, 1)
			Frost.BackgroundColor3 = config.tint
			Frost.BackgroundTransparency = 0.9
			Frost.BorderSizePixel = 0
			Frost.ZIndex = Body.ZIndex
			local FrostCorner = Instance.new("UICorner")
			FrostCorner.CornerRadius = UDim.new(0, config.cornerRadius)
			FrostCorner.Parent = Frost
			Frost.Parent = Body
		end
	end)

	-- sheen: soft top highlight
	local Sheen = Instance.new("Frame")
	Sheen.Name = "GlassSheen"
	Sheen.Size = UDim2.fromScale(1, 0.55)
	Sheen.Position = UDim2.fromScale(0, 0)
	Sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	Sheen.BackgroundTransparency = 0.88
	Sheen.BorderSizePixel = 0
	Sheen.ZIndex = Body.ZIndex + 1
	local SheenGradient = Instance.new("UIGradient")
	SheenGradient.Rotation = 90
	SheenGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.78),
		NumberSequenceKeypoint.new(1, 1),
	})
	SheenGradient.Parent = Sheen
	local SheenCorner = Instance.new("UICorner")
	SheenCorner.CornerRadius = UDim.new(0, config.cornerRadius)
	SheenCorner.Parent = Sheen
	Sheen.Parent = Body

	-- specular rim
	local Stroke = Instance.new("UIStroke")
	Stroke.Thickness = 1.5
	Stroke.Color = Color3.new(1, 1, 1)
	Stroke.Transparency = 0.35
	Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	Stroke.Parent = Body
	local StrokeGradient = Instance.new("UIGradient")
	StrokeGradient.Rotation = 45
	StrokeGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, config.tint),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	StrokeGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.85),
		NumberSequenceKeypoint.new(1, 0.5),
	})
	StrokeGradient.Parent = Stroke

	-- inner glow: thick-glass feel
	local Inner = Instance.new("Frame")
	Inner.Name = "GlassInner"
	Inner.Size = UDim2.new(1, -4, 1, -4)
	Inner.Position = UDim2.fromOffset(2, 2)
	Inner.BackgroundColor3 = config.tint
	Inner.BackgroundTransparency = 0.93
	Inner.BorderSizePixel = 0
	Inner.ZIndex = Body.ZIndex + 1
	local InnerCorner = Instance.new("UICorner")
	InnerCorner.CornerRadius = UDim.new(0, config.cornerRadius - 2)
	InnerCorner.Parent = Inner
	Inner.Parent = Body

	-- moving shine: sweeps on hover
	local Shine = Instance.new("Frame")
	Shine.Name = "GlassShine"
	Shine.Size = UDim2.fromScale(0.22, 2)
	Shine.Position = UDim2.fromScale(-0.3, -0.5)
	Shine.Rotation = 20
	Shine.BackgroundColor3 = Color3.new(1, 1, 1)
	Shine.BackgroundTransparency = 0.9
	Shine.BorderSizePixel = 0
	Shine.ZIndex = Body.ZIndex + 2
	local ShineGradient = Instance.new("UIGradient")
	ShineGradient.Rotation = 90
	ShineGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	ShineGradient.Parent = Shine
	Shine.Parent = Body

	local Scale = Instance.new("UIScale")
	Scale.Scale = 1
	Scale.Parent = Body

	table.insert(glassFolder, Body)

	return {
		body = Body,
		sheen = Sheen,
		shine = Shine,
		stroke = Stroke,
		shadow = Shadow,
		scale = Scale,
	}
end

local function SweepShine(Refs: GlassRefs)
	local Shine = Refs.shine
	local Info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Shine.Position = UDim2.fromScale(-0.3, -0.5)
	local Tween = TrackTween(TweenService:Create(Shine, Info, {Position = UDim2.fromScale(1.15, -0.5)}))
	Tween.Completed:Once(function()
		Shine.Position = UDim2.fromScale(-0.3, -0.5)
	end)
end

-- ============================================================
-- STATE
-- ============================================================

local ScreenGui: ScreenGui? = nil
local Main: Frame? = nil
local DimFrame: Frame? = nil
local CardRegistry: {[number]: {CardRefs}} = {}
local selectedIndex = 0
local isOpen = false
local hoveredId: string? = nil
local DescriptionParts: {TextLabel} = {}
local DescriptionTitle: TextLabel? = nil
local renderConnection: RBXScriptConnection? = nil
local CurrentSnapshot: LightingSnapshot? = nil
local AmbientSound: Sound? = nil

local function FindMode(Id: string): ModeConfig?
	for _, Mode in MODES do
		if Mode.id == Id then
			return Mode
		end
	end
	return nil
end

local function FlatList(): {ModeConfig}
	local List: {ModeConfig} = {}
	for _, Mode in MODES do
		table.insert(List, Mode)
	end
	return List
end

-- ============================================================
-- BUILD UI
-- ============================================================

local function MakeTextLabel(parent: Instance, config: {
	text: string,
	size: UDim2,
	position: UDim2?,
	color: Color3,
	bold: boolean?,
	textSize: number,
	maxSize: number?,
	zindex: number?,
}): TextLabel
	local Label = Instance.new("TextLabel")
	Label.BackgroundTransparency = 1
	Label.Size = config.size
	Label.Position = config.position or UDim2.fromScale(0.5, 0)
	Label.AnchorPoint = Vector2.new(0.5, 0)
	Label.Font = config.bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
	Label.Text = config.text
	Label.TextColor3 = config.color
	Label.TextSize = config.textSize
	Label.TextScaled = false
	Label.ZIndex = config.zindex or 10

	local Constraint = Instance.new("UITextSizeConstraint")
	Constraint.MaxTextSize = config.maxSize or config.textSize
	Constraint.Parent = Label

	local Stroke = Instance.new("UIStroke")
	Stroke.Color = THEME.theme.textStroke
	Stroke.Transparency = 0.1
	Stroke.Thickness = 1
	Stroke.Parent = Label

	Label.Parent = parent
	return Label
end

local function MakePill(parent: Instance, Text: string, Color: Color3, Position: UDim2): (Frame, TextLabel)
	local Pill = Instance.new("Frame")
	Pill.Size = UDim2.fromScale(0.62, 0.22)
	Pill.Position = Position
	Pill.AnchorPoint = Vector2.new(0.5, 0)
	Pill.BackgroundColor3 = Color
	Pill.BackgroundTransparency = 0.25
	Pill.BorderSizePixel = 0
	Pill.ZIndex = 12
	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(1, 0)
	Corner.Parent = Pill

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.fromScale(1, 1)
	Label.BackgroundTransparency = 1
	Label.Font = Enum.Font.GothamBold
	Label.Text = Text
	Label.TextColor3 = Color3.fromRGB(30, 18, 8)
	Label.TextSize = 12
	Label.ZIndex = 13
	local TextConstraint = Instance.new("UITextSizeConstraint")
	TextConstraint.MaxTextSize = 12
	TextConstraint.Parent = Label
	Label.Parent = Pill

	Pill.Parent = parent
	return Pill, Label
end

local GLYPHS: {[string]: string} = {
	bed = "🛏",
	lucky = "🍀",
	arcade = "🕹",
	key = "🔑",
	clock = "⏱",
	custom = "🌐",
	practice = "🎯",
	tutorial = "📖",
}

local function BuildCard(parent: Instance, Mode: ModeConfig, Position: UDim2, Size: UDim2, ZBase: number): CardRefs
	local Tint = THEME.theme.glassDefault
	if Mode.id == "classic" then
		Tint = THEME.theme.glassSelected
	elseif Mode.id == "luckyblock" then
		Tint = THEME.theme.glassMoss
	elseif Mode.id == "arcade" then
		Tint = THEME.theme.glassLavender
	elseif Mode.stacked then
		Tint = THEME.theme.glassEvent
	end

	local Holder = Instance.new("Frame")
	Holder.Name = "Card_" .. Mode.id
	Holder.Size = Size
	Holder.Position = Position
	Holder.AnchorPoint = Vector2.new(0.5, 0)
	Holder.BackgroundTransparency = 1
	Holder.ZIndex = ZBase
	Holder.Selectable = true
	Holder.Parent = parent

	local Refs = createGlass(Holder, {
		size = UDim2.fromScale(0.94, 0.92),
		tint = Tint,
		cornerRadius = 22,
		transparency = 0.72,
		blurRadius = 12,
	})

	-- art or glyph
	local Art: ImageLabel? = nil
	local GlyphLabel: TextLabel? = nil
	if Mode.art ~= 0 then
		local Image = Instance.new("ImageLabel")
		Image.Name = "CardArt"
		Image.Size = UDim2.fromScale(1, 0.55)
		Image.BackgroundColor3 = Tint
		Image.BackgroundTransparency = 1
		Image.Image = "rbxassetid://" .. tostring(Mode.art)
		Image.ImageTransparency = 0.1
		Image.ScaleType = Enum.ScaleType.Crop
		Image.ZIndex = Refs.body.ZIndex + 1
		local Corner = Instance.new("UICorner")
		Corner.CornerRadius = UDim.new(0, 22)
		Corner.Parent = Image
		local Fade = Instance.new("UIGradient")
		Fade.Rotation = 90
		Fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.75, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		Fade.Parent = Image
		Image.Parent = Refs.body
		Art = Image
	else
		local Glyph = Instance.new("TextLabel")
		Glyph.Name = "CardGlyph"
		Glyph.Size = UDim2.fromScale(1, 0.55)
		Glyph.BackgroundTransparency = 1
		Glyph.Font = Enum.Font.GothamBold
		Glyph.Text = GLYPHS[Mode.glyph] or "◆"
		Glyph.TextColor3 = Tint
		Glyph.TextTransparency = 0.25
		Glyph.TextSize = 60
		Glyph.ZIndex = Refs.body.ZIndex + 1
		local Constraint = Instance.new("UITextSizeConstraint")
		Constraint.MaxTextSize = 60
		Constraint.Parent = Glyph
		Glyph.Parent = Refs.body
		GlyphLabel = Glyph
	end

	local Title = MakeTextLabel(Refs.body, {
		text = Mode.title,
		size = UDim2.fromScale(0.9, 0.14),
		position = UDim2.fromScale(0.5, 0.58),
		color = THEME.theme.textPrimary,
		bold = true,
		textSize = 20,
		maxSize = 22,
		zindex = Refs.body.ZIndex + 2,
	})

	local Subtitle = MakeTextLabel(Refs.body, {
		text = Mode.subtitle,
		size = UDim2.fromScale(0.9, 0.1),
		position = UDim2.fromScale(0.5, 0.73),
		color = THEME.theme.textSecondary,
		textSize = 13,
		maxSize = 14,
		zindex = Refs.body.ZIndex + 2,
	})

	local Pill: Frame? = nil
	local PillText: TextLabel? = nil
	if Mode.tag then
		Pill, PillText = MakePill(Refs.body, Mode.tag, THEME.theme.accent, UDim2.fromScale(0.5, 0.87))
	end

	local Card: CardRefs = {
		frame = Holder,
		body = Refs.body,
		sheen = Refs.sheen,
		shine = Refs.shine,
		stroke = Refs.stroke,
		scale = Refs.scale,
		shadow = Refs.shadow,
		art = Art,
		glyphLabel = GlyphLabel,
		title = Title,
		subtitle = Subtitle,
		pill = Pill,
		pillText = PillText,
		tint = Tint,
		selected = false,
		hovering = false,
		parallaxArt = Art,
	}
	CardRegistry[ZBase] = Card
	return Card
end

local function SetCardSelected(Card: CardRefs, Selected: boolean)
	Card.selected = Selected
	local GoalTransparency = Selected and 0.6 or 0.72
	local GoalStroke = Selected and 0.15 or 0.35
	local GoalScale = (Selected or Card.hovering) and 1.045 or 1.0
	local Info = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TrackTween(TweenService:Create(Card.body, Info, {BackgroundTransparency = GoalTransparency}))
	TrackTween(TweenService:Create(Card.stroke, Info, {Transparency = GoalStroke}))
	TrackTween(TweenService:Create(Card.scale, Info, {Scale = GoalScale}))
	TrackTween(TweenService:Create(Card.shadow, Info, {
		BackgroundTransparency = Selected and 0.72 or 0.78,
	}))
end

local function UpdateDescription(Mode: ModeConfig)
	local Title = DescriptionTitle
	if not Title then
		return
	end
	Title.TextColor3 = CardRegistry[1] and MODES[1] and THEME.theme.textPrimary or THEME.theme.textPrimary
	local Lines: {[string]: string} = {
		classic = "The island remembers every fall. Seven queues, one bed, no excuses.",
		luckyblock = "Every block is a coin flip. Some flip back.",
		arcade = "Short rounds, loud endings. Warm up or burn out.",
		duos = "The moon is full and the party is full. Bring exactly one friend.",
		squads = "Four candles, four players, one very long night.",
		customs = "Your rules, your lobby, your regrets. Join, host, or browse.",
		practice = "Clutch drills against shadows that never miss. The bed is already gone.",
		tutorial = "Learn the island before it learns you.",
	}
	local Text = Lines[Mode.id] or "A quiet corner of the Hollow."
	for Index, Label in DescriptionParts do
		local Goal = Index == 1 and Text or ""
		TrackTween(TweenService:Create(Label, TweenInfo.new(0.15), {TextTransparency = 1}))
		task.delay(0.15, function()
			if Label.Parent then
				Label.Text = Goal
				TrackTween(TweenService:Create(Label, TweenInfo.new(0.15), {TextTransparency = Goal == "" and 1 or 0.2}))
			end
		end)
	end
	TrackTween(TweenService:Create(Title, TweenInfo.new(0.15), {TextColor3 = THEME.theme.accent}))
end

local function BuildUI()
	local Gui = Instance.new("ScreenGui")
	Gui.Name = "HollowLobby"
	Gui.IgnoreGuiInset = true
	Gui.ResetOnSpawn = false
	Gui.DisplayOrder = 50
	Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	ScreenGui = Gui

	DimFrame = Instance.new("Frame")
	DimFrame.Name = "HollowDim"
	DimFrame.Size = UDim2.fromScale(1, 1)
	DimFrame.BackgroundColor3 = THEME.theme.dim
	DimFrame.BackgroundTransparency = 1
	DimFrame.BorderSizePixel = 0
	DimFrame.ZIndex = 1
	local DimGradient = Instance.new("UIGradient")
	DimGradient.Rotation = 90
	DimGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 8, 26)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(46, 26, 62)),
	})
	DimGradient.Parent = DimFrame
	DimFrame.Parent = Gui
	TrackTween(TweenService:Create(DimFrame, TweenInfo.new(0.45), {BackgroundTransparency = 0.55}))

	local MainFrame = Instance.new("Frame")
	MainFrame.Name = "Main"
	MainFrame.Size = UDim2.fromScale(0.88, 0.74)
	MainFrame.Position = UDim2.fromScale(0.5, 0.5)
	MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	MainFrame.BackgroundTransparency = 1
	MainFrame.ZIndex = 5
	MainFrame.Parent = Gui

	local Ratio = Instance.new("UIAspectRatioConstraint")
	Ratio.AspectRatio = 2.1
	Ratio.Parent = MainFrame

	local SizeConstraint = Instance.new("UISizeConstraint")
	SizeConstraint.MinSize = Vector2.new(640, 340)
	SizeConstraint.MaxSize = Vector2.new(1500, 760)
	SizeConstraint.Parent = MainFrame

	Main = MainFrame

	-- header
	MakeTextLabel(MainFrame, {
		text = "T H E   H O L L O W   L O B B Y",
		size = UDim2.fromScale(0.5, 0.06),
		position = UDim2.fromScale(0.5, 0.02),
		color = THEME.theme.textSecondary,
		textSize = 14,
		maxSize = 14,
		zindex = 6,
	})

	local Title = MakeTextLabel(MainFrame, {
		text = "Select a game",
		size = UDim2.fromScale(0.6, 0.14),
		position = UDim2.fromScale(0.5, 0.06),
		color = THEME.theme.textPrimary,
		bold = true,
		textSize = 54,
		maxSize = 54,
		zindex = 6,
	})
	local TitleGradient = Instance.new("UIGradient")
	TitleGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 244, 230)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(226, 200, 245)),
	})
	TitleGradient.Rotation = 90
	TitleGradient.Parent = Title

	-- featured row
	local Panel = createGlass(MainFrame, {
		size = UDim2.fromScale(0.96, 0.78),
		position = UDim2.fromScale(0.5, 0.22),
		tint = THEME.theme.glassDefault,
		cornerRadius = 28,
		transparency = 0.6,
		blurRadius = 18,
	})
	Panel.body.ZIndex = 5

	BuildCard(Panel.body, MODES[1], UDim2.fromScale(0.11, 0.06), UDim2.fromScale(0.19, 0.55), 100)
	BuildCard(Panel.body, MODES[2], UDim2.fromScale(0.325, 0.06), UDim2.fromScale(0.19, 0.55), 200)
	BuildCard(Panel.body, MODES[3], UDim2.fromScale(0.54, 0.06), UDim2.fromScale(0.19, 0.55), 300)

	-- stacked event cards
	local DuosCard = BuildCard(Panel.body, MODES[4], UDim2.fromScale(0.755, 0.06), UDim2.fromScale(0.19, 0.27), 400)
	if DuosCard.pillText then
		DuosCard.pillText.Text = "Event · 6/6"
	end
	BuildCard(Panel.body, MODES[5], UDim2.fromScale(0.755, 0.35), UDim2.fromScale(0.19, 0.26), 500)

	-- tile column
	BuildCard(Panel.body, MODES[6], UDim2.fromScale(0.905, 0.06), UDim2.fromScale(0.17, 0.17), 600)
	BuildCard(Panel.body, MODES[7], UDim2.fromScale(0.905, 0.25), UDim2.fromScale(0.17, 0.17), 700)
	BuildCard(Panel.body, MODES[8], UDim2.fromScale(0.905, 0.44), UDim2.fromScale(0.17, 0.17), 800)

	-- description panel
	local Desc = createGlass(MainFrame, {
		size = UDim2.fromScale(0.7, 0.14),
		position = UDim2.fromScale(0.5, 0.72),
		tint = THEME.theme.glassDefault,
		cornerRadius = 28,
		transparency = 0.6,
		blurRadius = 18,
	})
	Desc.body.ZIndex = 5

	DescriptionTitle = MakeTextLabel(Desc.body, {
		text = "Hover a mode",
		size = UDim2.fromScale(0.9, 0.34),
		position = UDim2.fromScale(0.5, 0.08),
		color = THEME.theme.textPrimary,
		bold = true,
		textSize = 18,
		maxSize = 18,
		zindex = 7,
	})

	for Index = 1, 3 do
		local Line = MakeTextLabel(Desc.body, {
			text = "",
			size = UDim2.fromScale(0.9, 0.16),
			position = UDim2.fromScale(0.5, 0.42 + (Index - 1) * 0.17),
			color = THEME.theme.textSecondary,
			textSize = 13,
			maxSize = 13,
			zindex = 7,
		})
		table.insert(DescriptionParts, Line)
	end

	-- exit pill
	local Exit = Instance.new("TextButton")
	Exit.Name = "ExitButton"
	Exit.Size = UDim2.fromScale(0.08, 0.07)
	Exit.Position = UDim2.fromScale(0.94, 0.9)
	Exit.AnchorPoint = Vector2.new(0.5, 0.5)
	Exit.BackgroundColor3 = THEME.theme.glassDefault
	Exit.BackgroundTransparency = 0.6
	Exit.Text = ""
	Exit.ZIndex = 20
	local ExitCorner = Instance.new("UICorner")
	ExitCorner.CornerRadius = UDim.new(1, 0)
	ExitCorner.Parent = Exit
	local ExitStroke = Instance.new("UIStroke")
	ExitStroke.Thickness = 1.5
	ExitStroke.Color = Color3.new(1, 1, 1)
	ExitStroke.Transparency = 0.35
	ExitStroke.Parent = Exit

	local XBadge = MakeTextLabel(Exit, {
		text = "X",
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0.5, 0.5),
		color = THEME.theme.textPrimary,
		bold = true,
		textSize = 16,
		maxSize = 16,
		zindex = 21,
	})
	XBadge.AnchorPoint = Vector2.new(0.5, 0.5)
	XBadge.Position = UDim2.fromScale(0.5, 0.5)

	Exit.MouseEnter:Connect(function()
		TrackTween(TweenService:Create(XBadge, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = 90}))
		TrackTween(TweenService:Create(Exit, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(200, 90, 100)}))
	end)
	Exit.MouseLeave:Connect(function()
		TrackTween(TweenService:Create(XBadge, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = 0}))
		TrackTween(TweenService:Create(Exit, TweenInfo.new(0.2), {BackgroundColor3 = THEME.theme.glassDefault}))
	end)
	Exit.Activated:Connect(function()
		PlaySound(THEME.sounds.click, 0.5)
		if CloseMenu then
			CloseMenu()
		end
	end)
end

-- ============================================================
-- ATMOSPHERE
-- ============================================================

local Embers: {Frame} = {}
local EmberSeeds: {number} = {}

local function BuildAtmosphere()
	if not THEME.effects or THEME.reducedMotion then
		return
	end
	if not Main or not ScreenGui then
		return
	end

	-- crescent moon
	local MoonBack = Instance.new("Frame")
	MoonBack.Size = UDim2.fromOffset(56, 56)
	MoonBack.Position = UDim2.fromScale(0.92, 0.06)
	MoonBack.BackgroundColor3 = Color3.fromRGB(240, 236, 250)
	MoonBack.BackgroundTransparency = 0.15
	MoonBack.BorderSizePixel = 0
	MoonBack.ZIndex = 2
	local MoonBackCorner = Instance.new("UICorner")
	MoonBackCorner.CornerRadius = UDim.new(1, 0)
	MoonBackCorner.Parent = MoonBack
	MoonBack.Parent = ScreenGui

	local MoonBite = Instance.new("Frame")
	MoonBite.Size = UDim2.fromOffset(44, 44)
	MoonBite.Position = UDim2.fromOffset(-16, -6)
	MoonBite.BackgroundColor3 = THEME.theme.dim
	MoonBite.BackgroundTransparency = 0.35
	MoonBite.BorderSizePixel = 0
	MoonBite.ZIndex = 3
	local MoonBiteCorner = Instance.new("UICorner")
	MoonBiteCorner.CornerRadius = UDim.new(1, 0)
	MoonBiteCorner.Parent = MoonBite
	MoonBite.Parent = MoonBack

	-- stars
	for Index = 1, 6 do
		local Star = Instance.new("Frame")
		Star.Size = UDim2.fromOffset(3, 3)
		Star.Position = UDim2.fromScale(0.6 + Index * 0.055, 0.04 + (Index % 3) * 0.02)
		Star.BackgroundColor3 = Color3.fromRGB(245, 240, 255)
		Star.BackgroundTransparency = 0.4
		Star.BorderSizePixel = 0
		Star.ZIndex = 2
		local StarCorner = Instance.new("UICorner")
		StarCorner.CornerRadius = UDim.new(1, 0)
		StarCorner.Parent = Star
		Star.Parent = ScreenGui
		local Tween = TrackTween(TweenService:Create(Star, TweenInfo.new(1.2 + Index * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundTransparency = 0.85}))
		table.insert(tweens, Tween)
	end

	-- mist band
	local Mist = Instance.new("Frame")
	Mist.Size = UDim2.fromScale(1.4, 0.12)
	Mist.Position = UDim2.fromScale(-0.2, 0.9)
	Mist.BackgroundColor3 = Color3.fromRGB(190, 130, 230)
	Mist.BackgroundTransparency = 0.85
	Mist.BorderSizePixel = 0
	Mist.ZIndex = 2
	local MistGradient = Instance.new("UIGradient")
	MistGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	MistGradient.Parent = Mist
	Mist.Parent = ScreenGui
	TrackTween(TweenService:Create(Mist, TweenInfo.new(30, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Position = UDim2.fromScale(-0.05, 0.9)}))

	-- embers
	for Index = 1, 14 do
		local Ember = Instance.new("Frame")
		Ember.Size = UDim2.fromOffset(4 + (Index % 5), 4 + (Index % 5))
		Ember.Position = UDim2.fromScale((Index * 0.073) % 1, 1.05)
		Ember.BackgroundColor3 = Index % 3 == 0 and THEME.theme.glassLavender or THEME.theme.accent
		Ember.BackgroundTransparency = 0.4 + (Index % 4) * 0.1
		Ember.BorderSizePixel = 0
		Ember.ZIndex = 2
		local EmberCorner = Instance.new("UICorner")
		EmberCorner.CornerRadius = UDim.new(1, 0)
		EmberCorner.Parent = Ember
		Ember.Parent = ScreenGui
		table.insert(Embers, Ember)
		table.insert(EmberSeeds, Index * 1.7)
	end

	-- bats
	if THEME.assets.bat ~= 0 then
		for Index = 1, 3 do
			task.delay(10 + Index * 12, function()
				if not ScreenGui or not ScreenGui.Parent then
					return
				end
				local Bat = Instance.new("ImageLabel")
				Bat.Size = UDim2.fromOffset(34, 22)
				Bat.Position = UDim2.fromScale(-0.08, 0.08 + Index * 0.05)
				Bat.BackgroundTransparency = 0.3
				Bat.Image = "rbxassetid://" .. tostring(THEME.assets.bat)
				Bat.ImageTransparency = 0.35
				Bat.ZIndex = 2
				Bat.Parent = ScreenGui
				TrackTween(TweenService:Create(Bat, TweenInfo.new(14, Enum.EasingStyle.Linear), {Position = UDim2.fromScale(1.08, 0.12 + Index * 0.05)}))
				task.delay(14.5, function()
					Bat:Destroy()
				end)
			end)
		end
	end
end

local function StartRenderLoop()
	if not THEME.effects or THEME.reducedMotion then
		return
	end
	local Clock = 0
	renderConnection = TrackConnection(RunService.RenderStepped:Connect(function(Delta)
		Clock += Delta
		for Index, Ember in Embers do
			if not Ember.Parent then
				continue
			end
			local Seed = EmberSeeds[Index]
			local Y = 1.05 - ((Clock * (0.02 + Seed % 0.015)) % 1.25)
			local X = 0.08 + (Index * 0.065) + math.sin(Clock * (0.4 + Seed) + Seed) * 0.02
			Ember.Position = UDim2.fromScale(X, Y)
		end
	end))
end

-- ============================================================
-- INTERACTION
-- ============================================================

local function Select(Index: number)
	local List = FlatList()
	if Index < 1 or Index > #List then
		return
	end
	selectedIndex = Index
	for ZBase, Card in CardRegistry do
		local CardMode = MODES[math.floor(ZBase / 100)]
		local _ = CardMode
	end
	for Index2, Mode in List do
		local Card = CardRegistry[(Index2) * 100]
		if Card then
			SetCardSelected(Card, Index2 == selectedIndex)
		end
	end
	local Selected = List[selectedIndex]
	if Selected then
		UpdateDescription(Selected)
		PlaySound(THEME.sounds.hover, 0.3)
	end
end

local function HookCard(Card: CardRefs, Mode: ModeConfig)
	local Body = Card.body
	Body.Active = true

	Body.InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			TrackTween(TweenService:Create(Card.scale, TweenInfo.new(0.07), {Scale = 0.96}))
		end
	end)

	Body.InputEnded:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			local Goal = (Card.selected or Card.hovering) and 1.045 or 1
			TrackTween(TweenService:Create(Card.scale, TweenInfo.new(0.07), {Scale = Goal}))
		end
	end)

	Body.MouseEnter:Connect(function()
		Card.hovering = true
		PlaySound(THEME.sounds.hover, 0.25)
		SweepShine({body = Card.body, sheen = Card.sheen, shine = Card.shine, stroke = Card.stroke, shadow = Card.shadow, scale = Card.scale})
		if Card.selected then
			SetCardSelected(Card, true)
		else
			TrackTween(TweenService:Create(Card.body, TweenInfo.new(0.2), {BackgroundTransparency = 0.64}))
			TrackTween(TweenService:Create(Card.stroke, TweenInfo.new(0.2), {Transparency = 0.15}))
			TrackTween(TweenService:Create(Card.scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.045}))
		end
		UpdateDescription(Mode)
	end)

	Body.MouseLeave:Connect(function()
		Card.hovering = false
		TrackTween(TweenService:Create(Card.body, TweenInfo.new(0.2), {BackgroundTransparency = Card.selected and 0.6 or 0.72}))
		TrackTween(TweenService:Create(Card.stroke, TweenInfo.new(0.2), {Transparency = Card.selected and 0.15 or 0.35}))
		TrackTween(TweenService:Create(Card.scale, TweenInfo.new(0.2), {Scale = Card.selected and 1.045 or 1}))
	end)

	Body.Activated:Connect(function()
		PlaySound(THEME.sounds.click, 0.5)
		onModeSelected(Mode.id)
	end)
end

-- ============================================================
-- NETWORKING
-- ============================================================

local RemoteWarned = false

function onModeSelected(ModeId: string)
	local Ok, Remote = pcall(function()
		return ReplicatedStorage:WaitForChild("SelectMode", 5)
	end)
	if Ok and Remote and Remote:IsA("RemoteEvent") then
		pcall(function()
			Remote:FireServer(ModeId)
		end)
	elseif not RemoteWarned then
		RemoteWarned = true
		warn("[HollowLobby] SelectMode RemoteEvent not found in ReplicatedStorage - selection not sent")
	end
end

-- ============================================================
-- OPEN / CLOSE
-- ============================================================

local function Cleanup()
	for _, Connection in connections do
		pcall(function()
			Connection:Disconnect()
		end)
	end
	table.clear(connections)
	for _, Tween in tweens do
		pcall(function()
			Tween:Cancel()
		end)
	end
	table.clear(tweens)
	table.clear(glassFolder)
	table.clear(Embers)
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if AmbientSound then
		pcall(function()
			AmbientSound:Destroy()
		end)
		AmbientSound = nil
	end
	if ScreenGui then
		pcall(function()
			ScreenGui:Destroy()
		end)
		ScreenGui = nil
	end
end

function CloseMenu()
	if not isOpen then
		return
	end
	isOpen = false
	PlaySound(THEME.sounds.close, 0.5)
	if CurrentSnapshot then
		RestoreLighting(CurrentSnapshot)
		CurrentSnapshot = nil
	end
	if Main then
		TrackTween(TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(0.5, 0.47),
		}))
	end
	if DimFrame then
		TrackTween(TweenService:Create(DimFrame, TweenInfo.new(0.25), {BackgroundTransparency = 1}))
	end
	task.delay(0.3, function()
		Cleanup()
	end)
end

function OpenMenu()
	if isOpen then
		return
	end
	isOpen = true
	PreloadAssets()
	CurrentSnapshot = ApplyLighting(Lighting)
	BuildUI()
	BuildAtmosphere()
	StartRenderLoop()
	PlaySound(THEME.sounds.open, 0.5)

	if THEME.sounds.ambient ~= 0 then
		pcall(function()
			AmbientSound = Instance.new("Sound")
			AmbientSound.SoundId = "rbxassetid://" .. tostring(THEME.sounds.ambient)
			AmbientSound.Volume = 0.12
			AmbientSound.Looped = true
			AmbientSound.Parent = SoundService
			AmbientSound:Play()
		end)
	end

	-- stagger cards in
	for ZBase, Card in CardRegistry do
		Card.scale.Scale = 0.6
		local Body = Card.body
		local Original = Body.Position
		Body.Position = Original + UDim2.fromScale(0, 0.06)
		task.delay(0.05 * (ZBase / 100), function()
			if Body.Parent then
				TrackTween(TweenService:Create(Body, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = Original}))
				TrackTween(TweenService:Create(Card.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}))
			end
		end)
		HookCard(Card, MODES[math.floor(ZBase / 100)])
	end

	Select(1)
end

-- input: keyboard + gamepad
ContextActionService:BindAction("HollowNavigate", function(_, State, Input)
	if not isOpen then
		return Enum.ContextActionResult.Pass
	end
	if State ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local List = FlatList()
	if Input.KeyCode == Enum.KeyCode.Right or Input.KeyCode == Enum.KeyCode.DPadRight then
		Select(math.min(selectedIndex + 1, #List))
	elseif Input.KeyCode == Enum.KeyCode.Left or Input.KeyCode == Enum.KeyCode.DPadLeft then
		Select(math.max(selectedIndex - 1, 1))
	elseif Input.KeyCode == Enum.KeyCode.Up or Input.KeyCode == Enum.KeyCode.DPadUp then
		Select(math.max(selectedIndex - 1, 1))
	elseif Input.KeyCode == Enum.KeyCode.Down or Input.KeyCode == Enum.KeyCode.DPadDown then
		Select(math.min(selectedIndex + 1, #List))
	elseif Input.KeyCode == Enum.KeyCode.Return or Input.KeyCode == Enum.KeyCode.ButtonA then
		local Selected = List[selectedIndex]
		if Selected then
			onModeSelected(Selected.id)
		end
	elseif Input.KeyCode == Enum.KeyCode.Escape or Input.KeyCode == Enum.KeyCode.ButtonB then
		CloseMenu()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Right, Enum.KeyCode.Left, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Return, Enum.KeyCode.Escape, Enum.KeyCode.DPadRight, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB)

-- external toggle
task.spawn(function()
	local Ok, Toggle = pcall(function()
		return ReplicatedStorage:WaitForChild("ToggleGameSelect", 10)
	end)
	if Ok and Toggle and Toggle:IsA("BindableEvent") then
		TrackConnection(Toggle.Event:Connect(function()
			if isOpen then
				CloseMenu()
			else
				OpenMenu()
			end
		end))
	end
end)

-- auto-open for testing
task.spawn(function()
	task.wait(1)
	OpenMenu()
end)
