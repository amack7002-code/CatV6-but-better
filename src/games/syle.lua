--!nocheck
-- slop build - Syle (AutoWin behavior presets)
-- One dropdown configures the whole combat stack per playstyle:
-- Legit / Semi-Rage / Rage / CC / Use mine. Applies reach, killaura geometry,
-- hitreg, click delay, fight triage, velocity - and reads back your own
-- settings in "Use mine" mode.
local vape = shared.vape
if not vape then return end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

run = run or function(func)
	task.spawn(function()
		local Ok, Err = pcall(func)
		if not Ok then
			warn("[slop] syle error: " .. tostring(Err))
		end
	end)
end

local function GetModule(Name: string)
	local Modules = vape.Modules
	return Modules and Modules[Name] or nil
end

local function GetOption(Module, OptionName: string)
	return Module and Module.Options and Module.Options[OptionName] or nil
end

-- presets: every value the Syle engine drives
local PRESETS = {
	Legit = {
		label = "Legit",
		reach = 4,
		killaura = {enabled = false, swing = 14, attack = 4.2, angle = 180, targets = 1},
		hitreg = 40,
		clickDelay = 60,
		triage = true,
		velocity = {horizontal = 92, vertical = 96},
		fov = 130,
	},
	Semi = {
		label = "Semi-Rage",
		reach = 5.5,
		killaura = {enabled = true, swing = 18, attack = 6, angle = 260, targets = 2},
		hitreg = 45,
		clickDelay = 30,
		triage = true,
		velocity = {horizontal = 80, vertical = 90},
		fov = 180,
	},
	Rage = {
		label = "Rage",
		reach = 7,
		killaura = {enabled = true, swing = 24, attack = 9, angle = 360, targets = 3},
		hitreg = 50,
		clickDelay = 0,
		triage = true,
		velocity = {horizontal = 55, vertical = 75},
		fov = 260,
	},
	CC = {
		label = "CC",
		reach = 12.8,
		killaura = {enabled = true, swing = 28, attack = 11.18, angle = 360, targets = 4},
		hitreg = 55,
		clickDelay = 0,
		triage = true,
		velocity = {horizontal = 35, vertical = 60},
		fov = 360,
	},
}

run(function()
	local Syle
	local Mode
	local ShowReadout

	local function Apply(PresetName: string)
		local Preset = PRESETS[PresetName]
		if not Preset then return end
		if not vape.Loaded then return end

		-- reach
		local Reach = GetModule("Reach")
		local SwordRange = GetOption(Reach, "Sword Range")
		if SwordRange then
			pcall(function() SwordRange:SetValue(Preset.reach) end)
		end
		local ReachToggle = GetOption(Reach, "Sword Reach")
		if ReachToggle and not Reach.Enabled then
			pcall(function() Reach:Toggle() end)
		end

		-- killaura geometry
		local Killaura = GetModule("Killaura")
		if Killaura then
			if Preset.killaura.enabled and not Killaura.Enabled then
				pcall(function() Killaura:Toggle() end)
			elseif not Preset.killaura.enabled and Killaura.Enabled then
				pcall(function() Killaura:Toggle() end)
			end
			pcall(function()
				local Swing = GetOption(Killaura, "Swing range")
				if Swing then Swing:SetValue(Preset.killaura.swing) end
				local Attack = GetOption(Killaura, "Attack range")
				if Attack then Attack:SetValue(Preset.killaura.attack) end
				local Angle = GetOption(Killaura, "Max angle")
				if Angle then Angle:SetValue(Preset.killaura.angle) end
				local Targets = GetOption(Killaura, "Max targets")
				if Targets then Targets:SetValue(Preset.killaura.targets) end
			end)
		end

		-- hitreg
		local Hitreg = GetModule("HitregAdjuster")
		if Hitreg then
			if not Hitreg.Enabled then pcall(function() Hitreg:Toggle() end) end
			local Slider = GetOption(Hitreg, "Hitreg")
			if Slider then pcall(function() Slider:SetValue(Preset.hitreg) end) end
		end

		-- click rhythm
		local NoClickDelay = GetModule("NoClickDelay")
		if NoClickDelay then
			if not NoClickDelay.Enabled then pcall(function() NoClickDelay:Toggle() end) end
			local Wheel = GetOption(NoClickDelay, "Click delay")
			if Wheel then pcall(function() Wheel:SetValue(Preset.clickDelay) end) end
		end

		-- triage
		local Triage = GetModule("Fight Triage")
		if Triage and Preset.triage and not Triage.Enabled then
			pcall(function() Triage:Toggle() end)
		end

		-- velocity
		local Velocity = GetModule("Velocity")
		if Velocity then
			if not Velocity.Enabled then pcall(function() Velocity:Toggle() end) end
			pcall(function()
				local Horiz = GetOption(Velocity, "Horizontal")
				if Horiz then Horiz:SetValue(Preset.velocity.horizontal) end
				local Vert = GetOption(Velocity, "Vertical")
				if Vert then Vert:SetValue(Preset.velocity.vertical) end
			end)
		end

		if ShowReadout.Enabled then
			vape:CreateNotification("Syle", Preset.label .. " applied - reach " .. Preset.reach .. ", hitreg " .. Preset.hitreg .. ", KB " .. Preset.velocity.horizontal .. "%", 6, "info")
		end
	end

	Syle = vape.Categories.Utility:CreateModule({
		Name = "Syle",
		Function = function(Callback: boolean)
			if Callback then
				if Mode.Value ~= "Use mine" then
					Apply(Mode.Value)
				end
			end
		end,
		Tooltip = "One switch for your whole combat stack - Legit up to CC presets, or Use mine to keep your own settings",
	})

	Mode = Syle:CreateDropdown({
		Name = "Syle",
		List = {"Use mine", "Legit", "Semi-Rage", "Rage", "CC"},
		Default = "Use mine",
		Function = function(Value)
			if Syle and Syle.Enabled and Value ~= "Use mine" then
				Apply(Value)
			end
		end,
	})
	ShowReadout = Syle:CreateToggle({
		Name = "Readout",
		Default = true,
		Tooltip = "Notification when a preset applies",
	})
end)
