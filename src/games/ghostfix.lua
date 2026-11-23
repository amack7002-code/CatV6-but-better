--!nocheck
-- slop build - Ghost Block Fix (bedwars) v2
-- Ghost blocks = placements your client predicted but the server refused.
-- The tell: they have NO block data (server never assigned health attributes).
-- Fast loop: verify ~0.3s after placement, re-send immediately, clear stubborn
-- ghosts locally so they stop blocking movement.
local vape = shared.vape
if not vape then return end
if shared.catvapesupported == false then return end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local run = function(func)
	task.spawn(function()
		local Ok, Err = pcall(func)
		if not Ok then
			warn("[slop] ghostfix error: " .. tostring(Err))
		end
	end)
end

run(function()
	local GhostFix
	local Retries
	local VerifyDelay

	local BlockEngine = nil
	local Placer = nil

	local function Resolve(): boolean
		if BlockEngine and Placer then return true end
		pcall(function()
			if not BlockEngine then
				BlockEngine = require(ReplicatedStorage["rbxts_include"]["node_modules"]["@easy-games"]["block-engine"].out).BlockEngine
			end
		end)
		pcall(function()
			local Controller = require(ReplicatedStorage.TS.games.bedwars.controllers["block-placing"]["block-placement-controller"])
			Placer = Controller.blockPlacer or (Controller.BlockPlacementController and Controller.BlockPlacementController.blockPlacer)
		end)
		return BlockEngine ~= nil and Placer ~= nil
	end

	local Pending = {} -- [key] = {gridPos, item, tries, nextCheck}

	local function Key(GridPos): string
		return math.floor(GridPos.X + 0.5) .. "," .. math.floor(GridPos.Y + 0.5) .. "," .. math.floor(GridPos.Z + 0.5)
	end

	local function IsGhost(GridPos): boolean
		-- ghost = client thinks a block is here but the server never registered
		-- block data (health attributes come from the server only)
		local Ok, HasData = pcall(function()
			local Store = BlockEngine:getStore()
			local Block = Store:getBlockAt(GridPos)
			if not Block then return true end -- no block at all = nothing to fix
			local GetData = (Store :: any).getBlockData
			local Data = GetData and GetData(Store, GridPos)
			return Data == nil
		end)
		return Ok and HasData == true
	end

	local function TrackPlacement(GridPos, Item)
		local KeyName = Key(GridPos)
		local Entry = Pending[KeyName]
		Pending[KeyName] = {
			gridPos = Vector3.new(math.floor(GridPos.X + 0.5), math.floor(GridPos.Y + 0.5), math.floor(GridPos.Z + 0.5)),
			item = Item or (Placer and Placer.blockType) or "wool_white",
			tries = 0,
			nextCheck = os.clock() + (VerifyDelay.Value / 1000),
		}
	end

	local Hooked = nil
	local function HookPlacer()
		pcall(function()
			if not Placer or Hooked == Placer then return end
			Hooked = Placer
			local Old = Placer.placeBlock
			Placer.placeBlock = function(self, BlockPosition, ...)
				local Results = table.pack(Old(self, BlockPosition, ...))
				pcall(TrackPlacement, BlockPosition, self.blockType)
				return unpack(Results, 1, Results.n)
			end
		end)
	end

	GhostFix = vape.Categories.World:CreateModule({
		Name = "Ghost Block Fix",
		Function = function(Callback: boolean)
			if Callback then
				table.clear(Pending)
				if not Resolve() then
					vape:CreateNotification("Ghost Block Fix", "Controllers not ready yet - re-enable in a few seconds", 8, "warning")
					GhostFix:Toggle()
					return
				end
				HookPlacer()

				local HookTick = 0
				local Loop
				Loop = RunService.Heartbeat:Connect(function()
					HookTick = HookTick + 1
					if HookTick % 120 == 0 then
						pcall(HookPlacer) -- placer is rebuilt every match
					end
					local Now = os.clock()
					for KeyName, Entry in Pending do
						if Now < Entry.nextCheck then continue end
						if not IsGhost(Entry.gridPos) then
							Pending[KeyName] = nil -- server confirmed it
						elseif Entry.tries >= Retries.Value then
							Pending[KeyName] = nil
							-- stubborn ghost: remove locally so it stops eating movement
							pcall(function()
								local Store = BlockEngine:getStore()
								if Store.clearBlock then
									Store:clearBlock(Entry.gridPos)
								end
							end)
						else
							Entry.tries = Entry.tries + 1
							Entry.nextCheck = Now + 0.25 -- fast re-verify after retry
							pcall(function()
								Placer.blockType = Entry.item
								Placer:placeBlock(Entry.gridPos)
							end)
						end
					end
				end)
				GhostFix:Clean(Loop)
			else
				table.clear(Pending)
			end
		end,
		Tooltip = "Detects placements the server refused (no block data) and re-sends them fast, so bridge blocks stop being client-side ghosts",
	})

	Retries = GhostFix:CreateSlider({
		Name = "Retries",
		Min = 1,
		Max = 6,
		Default = 3,
		Tooltip = "How many times to re-send before clearing the ghost locally",
	})
	VerifyDelay = GhostFix:CreateSlider({
		Name = "Verify delay",
		Min = 1,
		Max = 10,
		Default = 3,
		Suffix = "00ms",
		Tooltip = "Time between placing and the first server-confirmation check",
	})
end)
