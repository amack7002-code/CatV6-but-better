--!nocheck
-- slop build - aero ports (combat modules from open-source sources)
local vape = shared.vape
local playersService = game:GetService("Players")
local collectionService = game:GetService("CollectionService")

-- resolve the game's controller table the same way the host script does
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local bedwars = {}
pcall(function()
	local KnitClient = require(ReplicatedStorage.rbxts_include.node_modules["@easy-games"].knit.src.Knit.KnitClient)
	bedwars.KnitClient = KnitClient
	bedwars.SprintController = KnitClient.Controllers.SprintController
end)
pcall(function()
	setmetatable(bedwars, {
		__index = function(self, Index)
			local Knit = rawget(self, "KnitClient")
			if Knit and Knit.Controllers and Knit.Controllers[Index] then
				rawset(self, Index, Knit.Controllers[Index])
				return Knit.Controllers[Index]
			end
			return nil
		end,
	})
end)
local run = function(func)
	task.spawn(function()
		local Ok, Err = pcall(func)
		if not Ok then
			warn("[slop] aero error: " .. tostring(Err))
		end
	end)
end


run(function()
	vape.Categories.Blatant:CreateModule({
		Name = 'KeepSprint',
		Function = function(callback)
			debug.setconstant(bedwars.SprintController.startSprinting, 5, callback and 'blockSprinting' or 'blockSprint')
			bedwars.SprintController:stopSprinting()
		end,
		Tooltip = 'allows you to sprint with potions'
	})
end)

run(function()
	local NoSlowDown
    local old
    local SophiaCheck
    local FROZEN_THRESHOLD = 10
    local cachedModifier = nil
    local nsHooked = false
    local savedSlow = setmetatable({}, {__mode = 'k'})
    local origPunch = nil
    local origGroveDisable = nil

    local function hookKitNoSlow()
        if bedwars.DragonSlayerController and not origPunch then
            origPunch = bedwars.DragonSlayerController.playPunchAnimation
            bedwars.DragonSlayerController.playPunchAnimation = function(self, arg2)
                local ok, maid = pcall(function()
                    local imp = debug.getupvalue(origPunch, 1)
                    local anim = debug.getupvalue(origPunch, 2)
                    local plrs = debug.getupvalue(origPunch, 3)
                    local atype = debug.getupvalue(origPunch, 4)
                    local rs = debug.getupvalue(origPunch, 6)
                    local m = imp.new()
                    local track = anim:playAnimation(plrs.LocalPlayer, atype.DRAGON_SLAYER_PUNCH)
                    m:GiveTask(function()
                        if track then track:Stop() end
                    end)
                    m:GiveTask(rs.Heartbeat:Connect(function()
                        local char = plrs.LocalPlayer.Character
                        if not char or not char.PrimaryPart then
                            m:DoCleaning()
                            return
                        end
                        char:PivotTo(CFrame.new(char:GetPrimaryPartCFrame().Position) * arg2)
                    end))
                    task.delay(0.46, function() m:DoCleaning() end)
                    return m
                end)
                if ok and maid then return maid end
                return origPunch(self, arg2)
            end
        end

        if bedwars.SpiritGardenerController and not origGroveDisable then
            origGroveDisable = bedwars.SpiritGardenerController.disableActionsOnCharge
            bedwars.SpiritGardenerController.disableActionsOnCharge = function(self, maid, character)
                if character ~= lplr.Character then
                    return origGroveDisable(self, maid, character)
                end
                local ok = pcall(function()
                    local KnitClient = bedwars.KnitClient
                    KnitClient.Controllers.SwordController:toggleSwordSwing(true)
                    KnitClient.Controllers.BlockPlacementController:disableBlockPlacer()
                    local ClientSyncEvents = debug.getupvalue(origGroveDisable, 3)
                    local projConn = ClientSyncEvents.BeginProjectileTargeting:connect(function(event)
                        event:setCancelled(true)
                    end)
                    local jumpMod = KnitClient.Controllers.JumpHeightController:getJumpModifier():addModifier({
                        jumpHeightMultiplier = 0
                    })
                    maid:GiveTask(function()
                        KnitClient.Controllers.SwordController:toggleSwordSwing(false)
                        KnitClient.Controllers.BlockPlacementController:enableBlockPlacer()
                        projConn:Destroy()
                        jumpMod.Destroy()
                    end)
                end)
                if not ok then
                    return origGroveDisable(self, maid, character)
                end
            end
        end
    end

    local function unhookKitNoSlow()
        if origPunch and bedwars.DragonSlayerController then
            bedwars.DragonSlayerController.playPunchAnimation = origPunch
        end
        origPunch = nil
        if origGroveDisable and bedwars.SpiritGardenerController then
            bedwars.SpiritGardenerController.disableActionsOnCharge = origGroveDisable
        end
        origGroveDisable = nil
    end
    NoSlowdown = vape.Categories.Blatant:CreateModule({
        Name = 'NoSlowdown',
        Function = function(callback)
            if not cachedModifier then
                if not bedwars.SprintController then return end
                cachedModifier = bedwars.SprintController:getMovementStatusModifier()
            end
            local modifier = cachedModifier
            if callback then
                if nsHooked then return end
                hookKitNoSlow()
                old = modifier.addModifier
                if not old then return end
                local orig = old

                local function removeSlow(tab)
                    if type(tab) ~= 'table' then
                        return false, false
                    end

                    local changed = false
                    local unblocked = false

                    if not savedSlow[tab] then
                        savedSlow[tab] = {
                            move = tab.moveSpeedMultiplier,
                            constant = tab.constantSpeedMultiplier,
                            blockSprint = tab.blockSprint
                        }
                    end

                    local move = tonumber(tab.moveSpeedMultiplier)
                    local constant = tonumber(tab.constantSpeedMultiplier)

                    if move and move < 1 then
                        tab.moveSpeedMultiplier = 1
                        changed = true
                    end

                    if constant and constant < 1 then
                        tab.constantSpeedMultiplier = 1
                        changed = true
                    end

                    if tab.blockSprint == true and not (constant and constant > 1) then
                        tab.blockSprint = false
                        changed = true
                        unblocked = true
                    end

                    return changed, unblocked
                end

                nsHooked = true
                modifier.addModifier = function(self, tab)
                    if not orig then return end

                    if SophiaCheck and SophiaCheck.Enabled and isFrozen(nil, FROZEN_THRESHOLD) then
                        return orig(self, tab)
                    end

                    removeSlow(tab)
                    return orig(self, tab)
                end

                local changed = false
                local unblocked = false

                for i, v in modifier.modifiers do
                    local mod = type(v) == 'table' and v or (type(i) == 'table' and i or nil)

                    if mod then
                        local didChange, didUnblock = removeSlow(mod)

                        if didChange then
                            changed = true
                        end

                        if didUnblock then
                            unblocked = true
                        end
                    end
                end

                if changed and modifier.updateModifiers then
                    modifier:updateModifiers()
                end

                if unblocked
                    and entitylib.isAlive
                    and entitylib.character.Humanoid.MoveDirection.Magnitude > 0 then

                    pcall(function()
                        bedwars.SprintController:startSprinting()
                    end)
                end

                NoSlowdown:Clean(runService.PreSimulation:Connect(function()
                    if not NoSlowdown.Enabled or not cachedModifier then
                        return
                    end

                    if SophiaCheck and SophiaCheck.Enabled and isFrozen(nil, FROZEN_THRESHOLD) then
                        return
                    end

                    local updated = false
                    local resumeSprint = false

                    for i, v in cachedModifier.modifiers do
                        local mod = type(v) == 'table' and v or (type(i) == 'table' and i or nil)

                        if mod then
                            local didChange, didUnblock = removeSlow(mod)

                            if didChange then
                                updated = true
                            end

                            if didUnblock then
                                resumeSprint = true
                            end
                        end
                    end

                    if updated and cachedModifier.updateModifiers then
                        cachedModifier:updateModifiers()
                    end

                    if resumeSprint
                        and entitylib.isAlive
                        and entitylib.character.Humanoid.MoveDirection.Magnitude > 0 then

                        pcall(function()
                            bedwars.SprintController:startSprinting()
                        end)
                    end
                end))
            else
                unhookKitNoSlow()
                if cachedModifier then
                    cachedModifier.addModifier = old
                    for tab, orig in savedSlow do
                        tab.moveSpeedMultiplier = orig.move
                        tab.constantSpeedMultiplier = orig.constant
                        tab.blockSprint = orig.blockSprint
                    end
                    if cachedModifier.updateModifiers then
                        pcall(cachedModifier.updateModifiers, cachedModifier)
                    end
                    cachedModifier = nil
                end
                table.clear(savedSlow)
                old = nil
                nsHooked = false
            end
        end,
        Tooltip = 'prevents slowing down when using items.'
    })

    SophiaCheck = NoSlowdown:CreateToggle({
        Name = 'Sophia Check',
        Default = false
    })
end)

run(function()
	local DamageBoost
	local stack
	
	DamageBoost = vape.Categories.Blatant:CreateModule({
		Name = 'DamageBoost',
		Function = function(callback)
			if callback then
				DamageBoost:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
					if entitylib.isAlive and tick() > (stack or 0) and damageTable.entityInstance == lplr.Character and not vape.Modules.LongJump.Enabled then
						local horizontal = (damageTable.knockbackMultiplier and damageTable.knockbackMultiplier.horizontal or 0)
						knockbackSpeed = bedwars.KnockbackUtil.calculateKnockbackVelocity(Vector3.one, 1, {
							vertical = 0,
							horizontal = horizontal,
						}).Magnitude * (0.9 + (store.ping and store.ping.total or 0))
						stack = tick() + (knockbackSpeed / 45)
						knockbackBoost = tick() + (horizontal / 3.5)
					end
				end))
			end
		end,
		Tooltip = 'makes you go slightly faster when damaged'
	})
end)

run(function()
	local NoFall
	local Chance
	local voidParams = RaycastParams.new()
	voidParams.FilterType = Enum.RaycastFilterType.Exclude
	voidParams.IgnoreWater = true
	local lastVoidCheck = 0
	local cachedVoid = false

	local voidOffsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(2, 0, 0),
		Vector3.new(-2, 0, 0),
		Vector3.new(0, 0, 2),
		Vector3.new(0, 0, -2)
	}

	local function nearVoid(position)
		if not entitylib.isAlive then return false end
		local now = tick()
		if (now - lastVoidCheck) < 0.1 then
			return cachedVoid
		end
		lastVoidCheck = now
		voidParams.FilterDescendantsInstances = {entitylib.character.Character, gameCamera}

		local down = Vector3.new(0, -600, 0)
		for _, off in voidOffsets do
			if workspace:Raycast(position + off, down, voidParams) then
				cachedVoid = false
				return false
			end
		end

		cachedVoid = true
		return true
	end

	NoFall = vape.Categories.Blatant:CreateModule({
		Name = 'NoFall',
		Function = function(callback)
			if callback then
				NoFall:Clean(runService.Heartbeat:Connect(function(dt)
					if entitylib.isAlive and store.matchState == 1 then
						local root = entitylib.character.RootPart
						local v = root.Velocity

						if root.Velocity.Y < -35 and not nearVoid(root.Position) then
							if math.random(1, 100) <= Chance.Value then
								root.Velocity = Vector3.new(0,2.5,0)
								entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Landed)
								runService.PreRender:Wait()
								root.Velocity = v
							end
						end
					end
				end))

				NoFall:Clean(entitylib.Events.LocalAdded:Connect(function(char)
					local animator = char.Humanoid:WaitForChild('Animator', 1)
					if animator and NoFall.Enabled then
						task.wait(.5)
						NoFall:Toggle()
						NoFall:Toggle()
					end
				end))
			end
		end,
		Tooltip = 'Take no fall damage.'
	})

	Chance = NoFall:CreateSlider({
		Name = 'Chance',
		Min = 1,
		Max = 100,
		Default = 100,
		Suffix = '%'
	})
end)

run(function()
	local FastPickup
	local FastPickupDelay
	local PickupRemote = replicatedStorage:WaitForChild('rbxts_include'):WaitForChild('node_modules'):WaitForChild('@rbxts'):WaitForChild('net'):WaitForChild('out'):WaitForChild('_NetManaged'):WaitForChild('PickupItemDrop')
	local pendingDrops = setmetatable({}, {__mode = 'k'})

	FastPickup = vape.Categories.Blatant:CreateModule({
		Name = 'FastPickup',
		Tooltip = 'picks up items fast asl',
		Function = function(callback)
			if callback then
				cleanThread(FastPickup, task.spawn(function()
					while FastPickup.Enabled do
						if entitylib.isAlive then
							local drops = workspace:WaitForChild('ItemDropsCache')
							for _, drop in pairs(drops:GetChildren()) do
								if not pendingDrops[drop] then
									pendingDrops[drop] = true
									task.spawn(function()
										task.wait(FastPickupDelay.Value)
										if FastPickup.Enabled and entitylib.isAlive and drop.Parent == drops then
											pcall(function()
												PickupRemote:InvokeServer({ itemDrop = drop })
											end)
										end
										pendingDrops[drop] = nil
									end)
								end
							end
						end
						task.wait(0.05)
					end
				end))
			end
		end,
	})

	FastPickupDelay = FastPickup:CreateSlider({
		Name = 'Delay',
		Min = 0,
		Max = 0.5,
		Default = 0,
		Decimal = 100,
		Suffix = 's',
	})
end)



run(function()
	local ShopTierBypass
	local tiered, nexttier = {}, {}
	local originalGetShop
	local originalClientGet
	local originalControllerShop
	local hookedController
	local shopItemsTracked = {}
	local tierChains = {}
	local knownTiers = {
		{'wood_pickaxe', 'stone_pickaxe', 'iron_pickaxe', 'diamond_pickaxe'},
		{'wood_axe', 'stone_axe', 'iron_axe', 'diamond_axe'},
		{'leather_chestplate', 'iron_chestplate', 'diamond_chestplate', 'emerald_chestplate'},
	}
	
	local function applyBypassToItem(item)
		if item and type(item) == "table" then
			if not tiered[item] then 
				tiered[item] = item.tiered 
			end
			if not nexttier[item] then 
				nexttier[item] = item.nextTier 
			end
			item.nextTier = nil
			item.tiered = nil
			shopItemsTracked[item] = true
		end
	end
	
	local function applyBypassToTable(tbl)
		if tbl and type(tbl) == "table" then
			for _, item in pairs(tbl) do
				if type(item) == "table" then
					applyBypassToItem(item)
				end
			end
		end
	end
	
	local function hasItemOwned(itemType)
		if getItem(itemType) then return true end
		local armor = store.inventory.inventory.armor
		if armor then
			for _, a in armor do
				if type(a) == 'table' and a.itemType == itemType then
					return true
				end
			end
		end
		return false
	end

	local function isDowngrade(itemType)
		local chain = tierChains[itemType]
		if not chain then return false end
		local myIndex = chain.index[itemType]
		for i = myIndex + 1, #chain.items do
			if hasItemOwned(chain.items[i]) then return true end
		end
		return false
	end

	local function shouldBlock(itemType)
		if not tierChains[itemType] then return false end
		if hasItemOwned(itemType) then return true end
		if isDowngrade(itemType) then return true end
		return false
	end

	local function getShopController()
		local success, result = pcall(function()
			local RuntimeLib = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
			if RuntimeLib then
				return RuntimeLib.import(script, game:GetService("ReplicatedStorage"), "TS", "games", "bedwars", "shop", "bedwars-shop")
			end
		end)
		
		if success then
			return result
		end
		
		local shopModule = game:GetService("ReplicatedStorage"):FindFirstChild("TS"):FindFirstChild("games"):FindFirstChild("bedwars"):FindFirstChild("shop"):FindFirstChild("bedwars-shop")
		if shopModule and shopModule:IsA("ModuleScript") then
			return require(shopModule)
		end
		
		return nil
	end
	
	ShopTierBypass = vape.Categories.Utility:CreateModule({
		Name = 'ShopTierBypass',
		Function = function(callback)
			if callback then
				local function collectAndBypass()
					local itemsSeen = {}
					if bedwars.Shop and bedwars.Shop.ShopItems then
						for _, v in pairs(bedwars.Shop.ShopItems) do
							itemsSeen[v] = true
						end
					end
					if bedwars.ShopItems then
						for _, v in pairs(bedwars.ShopItems) do
							itemsSeen[v] = true
						end
					end
					
					local shopController = getShopController()
					if shopController and shopController.BedwarsShop and shopController.BedwarsShop.getShop then
						local shopTable = shopController.BedwarsShop.getShop()
						if type(shopTable) == "table" then
							for _, v in pairs(shopTable) do
								itemsSeen[v] = true
							end
						end
					end
					for item, _ in pairs(itemsSeen) do
						applyBypassToItem(item)
					end

					local itemsByType = {}
					for item, _ in pairs(itemsSeen) do
						if item.itemType then
							itemsByType[item.itemType] = item
						end
					end
					for _, group in knownTiers do
						local chain = {items = {}, index = {}}
						for _, it in group do
							if itemsByType[it] then
								table.insert(chain.items, it)
								chain.index[it] = #chain.items
							end
						end
						if #chain.items > 1 then
							for _, it in chain.items do
								tierChains[it] = chain
							end
						end
					end
				end
				collectAndBypass()
				if bedwars.Shop and bedwars.Shop.getShop and not originalGetShop then
					originalGetShop = bedwars.Shop.getShop
					bedwars.Shop.getShop = function(...)
						local result = originalGetShop(...)
						if type(result) == "table" then
							applyBypassToTable(result)
						end
						return result
					end
				end
				
				if not originalClientGet then
					originalClientGet = bedwars.Client.Get
					local wrapperCache = setmetatable({}, {__mode = 'kv'})
					bedwars.Client.Get = function(self, name, ...)
						local remote = originalClientGet(self, name, ...)
						if name == 'BedwarsPurchaseItem' then
							local cached = wrapperCache[remote]
							if cached then return cached end
							local wrapper = {}
							wrapperCache[remote] = wrapper
							setmetatable(wrapper, {
								__index = function(_, key)
									if key == 'CallServerAsync' then
										return function(_, data, ...)
											if data and data.shopItem and data.shopItem.itemType then
												local itemType = data.shopItem.itemType
												if shouldBlock(itemType) then
													local displayName = bedwars.ItemMeta[itemType] and bedwars.ItemMeta[itemType].displayName or itemType
													if isDowngrade(itemType) then
														notif('ShopTierBypass', 'prevented yo ass from downgrading to '..displayName, 3, 'alert')
													else
														notif('ShopTierBypass', 'u alr got this item lmao: ', 3, 'alert')
													end
													return {andThen = function() end}
												end
											end
											return remote:CallServerAsync(data, ...)
										end
									end
									local value = remote[key]
									if type(value) == 'function' then
										return function(_, ...)
											return value(remote, ...)
										end
									end
									return value
								end
							})
							return wrapper
						end
						return remote
					end
				end

				local shopController = getShopController()
				if shopController and shopController.BedwarsShop and shopController.BedwarsShop.getShop then
					if not originalControllerShop then
						hookedController = shopController.BedwarsShop
						originalControllerShop = hookedController.getShop
						local base = originalControllerShop
						hookedController.getShop = function(...)
							local result = base(...)
							if type(result) == "table" then
								applyBypassToTable(result)
							end
							return result
						end
					end
				end
			else
				for item, _ in pairs(shopItemsTracked) do
					if item and type(item) == "table" then
						if tiered[item] ~= nil then
							item.tiered = tiered[item]
						end
						if nexttier[item] ~= nil then
							item.nextTier = nexttier[item]
						end
					end
				end
				
				if hookedController and originalControllerShop then
					hookedController.getShop = originalControllerShop
					originalControllerShop = nil
					hookedController = nil
				end
				
				if originalGetShop then
					bedwars.Shop.getShop = originalGetShop
					originalGetShop = nil
				end

				if originalClientGet then
					bedwars.Client.Get = originalClientGet
					originalClientGet = nil
				end
				
				table.clear(tiered)
				table.clear(nexttier)
				table.clear(shopItemsTracked)
				table.clear(tierChains)
			end
		end,
		Tooltip = 'lets u buy shit without buying the other tiers'
	})

	vape:Clean(function()
		if originalGetShop then
			pcall(function() bedwars.Shop.getShop = originalGetShop end)
			originalGetShop = nil
		end
		if originalClientGet then
			pcall(function() bedwars.Client.Get = originalClientGet end)
			originalClientGet = nil
		end
	end)
end)



run(function()
	local AntiMagma

	AntiMagma = vape.Categories.World:CreateModule({
		Name = "AntiMagma",
		Tooltip = 'allows you not to be instantly killed by magma',
		Function = function(callback)
			if callback then
				local function disableMagmaPart(v)
					if not v:IsA("BasePart") then return end
					if not string.find(string.lower(v.Name), 'magma') then return end
					for _, stuff in v:GetDescendants() do
						if stuff:IsA("TouchTransmitter") then
							pcall(function() stuff:Destroy() end)
						end
					end
				end

				scanDescendants(workspace, disableMagmaPart, AntiMagma)

				AntiMagma:Clean(workspace.DescendantAdded:Connect(function(v)
					disableMagmaPart(v)
				end))
				local worldFolder = getWorldFolder()
				if not worldFolder then return end
				local blocks = worldFolder:WaitForChild("Blocks", 1)
				if not blocks then return end
				AntiMagma:Clean(blocks.ChildAdded:Connect(function(v)
					disableMagmaPart(v)
				end))
			end
		end
	})
end)

run(function()
	local NetworkTP
	NetworkTP = vape.Categories.Utility:CreateModule({
		Name = 'NetworkTP',
		Function = function(callback)
			if callback then
				local items = collection('ItemDrop', NetworkTP)
				repeat
					if entitylib.isAlive then
						local localPosition = entitylib.character.RootPart.Position
						local humanoidHealth = entitylib.character.Humanoid.Health
						local currentTime = tick()

						for _, v in pairs(items) do
							local dropTime = v:GetAttribute('ClientDropTime')
							if not dropTime then continue end
							if (currentTime - dropTime) < 2 then continue end
							if isnetworkowner(v) and humanoidHealth > 0 then
								v.CFrame = CFrame.new(localPosition - Vector3.new(0, 3, 0))
							end
						end
					end
					task.wait(0.1)
				until not NetworkTP.Enabled
			end
		end,
		Tooltip = 'network ownership teleports item drops to you'
	})
end)
