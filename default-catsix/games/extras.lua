--!nocheck
-- slop build - extras: modules merged from open-source sources, rebranded
local vape = shared.vape
if not vape then return end

-- Minigames category (used by MurderMystery); created only if missing
if not vape.Categories.Minigames then
	local GetVapeAsset = vape.Libraries and vape.Libraries.getvapeasset or function(path) return path end
	vape:CreateCategory({
		Name = 'Minigames',
		Icon = GetVapeAsset(`{vape.Directory}/assets/new/star.png`),
		Size = UDim2.fromOffset(14, 14)
	})
end

-- ===================== shared helpers (bedwars core infrastructure) =====================
local function bufferCall(method, event, message, details)
	warn('[catvape] '..tostring(message))
end

local function errorTrace(err)
	local traceback
	pcall(function()
		if debug and type(debug.traceback) == 'function' then
			traceback = debug.traceback(tostring(err), 2)
		end
	end)
	return traceback or tostring(err)
end

--[[ Every module in this file and in bedwars.lua is registered inside one of these -- 60 blocks
here, 59 there, all at top level, and bedwars.lua takes this same function through bw.run.
Unprotected, an error anywhere in any of them aborted the rest of the file: every module
below the failure never registered, and in bedwars.lua the completion signal on the last
line never ran either, so main.lua sat in waitForModules for the full 120s before loading a
profile against a half-built module set. One game update touching one API took the whole
script down that way. Contained here, a bad block costs its own modules and nothing else. ]]
local function callWithThreadFix(func)
	local setIdentity = setthreadidentity
	local oldIdentity
	local switched = false
	if type(setIdentity) == 'function' then
		if type(getthreadidentity) == 'function' then
			local ok, identity = pcall(getthreadidentity)
			if ok then oldIdentity = identity end
		end
		oldIdentity = oldIdentity or 2
		if oldIdentity ~= 8 then
			switched = pcall(setIdentity, 8)
		end
	end

	local ok, err = xpcall(func, errorTrace)
	if switched then
		pcall(setIdentity, oldIdentity)
	end
	return ok, err
end

--[[ Registration yields a frame once it has held the game thread for FRAME_BUDGET. Every
module here and in bedwars.lua used to be built back to back -- the modules, their options
and the GUI objects behind all of it -- in one uninterrupted stretch, which is one long
freeze on every inject and reinject. VapeSmoothBoot already yields between every block and
the whole file is written to survive that, so this is the same yield, taken only when the
frame is actually spent: a boot that fits in a frame is exactly as fast as before. ]]
local FRAME_BUDGET = 0.012
local lastBootYield = os.clock()
-- A reinject replaces shared.vape; the blocks of the boot it superseded then stop building.
local bootVape = shared.vape
local run = function(func)
	if shared.vape ~= bootVape then return end
	if shared.VapeSmoothBoot or os.clock() - lastBootYield > FRAME_BUDGET then
		task.wait()
		lastBootYield = os.clock()
	end
	local ok, err = callWithThreadFix(func)
	if not ok then
		bufferCall('error', 'bedwars.module', err, {traceback = err})
	end
end

local cloneref = cloneref or function(obj)
	return obj
end
local vapeEvents = setmetatable({}, {
	__index = function(self, index)
		local result = rawget(self, index)
		if result == nil then
			result = Instance.new('BindableEvent')
			rawset(self, index, result)
		end
		return result
	end
})

local svc = {}
svc.playersService = cloneref(game:GetService('Players'))
svc.replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
svc.runService = cloneref(game:GetService('RunService'))
svc.inputService = cloneref(game:GetService('UserInputService'))
svc.httpService = cloneref(game:GetService('HttpService'))
svc.collectionService = cloneref(game:GetService('CollectionService'))
svc.tweenService = cloneref(game:GetService('TweenService'))
svc.textChatService = cloneref(game:GetService('TextChatService'))
svc.guiService = cloneref(game:GetService('GuiService'))
svc.coreGui = cloneref(game:GetService('CoreGui'))
svc.lightingService = cloneref(game:GetService('Lighting'))
svc.teleportService = cloneref(game:GetService("TeleportService"))

--[[ identifyexecutor exists but THROWS on several mobile executors, and this runs at the top
level of the file -- so an unguarded call here does not degrade one feature, it kills the
whole game script before a single module registers. main.lua already carries a comment
saying exactly this about its own call; these three never got the same treatment, and this
is the file BedWars users load. ]]
do
local function executorName()
	local ok, name = pcall(function()
		return identifyexecutor and ({identifyexecutor()})[1] or nil
	end)
	return (ok and type(name) == 'string') and name or ''
end

do
local isnetworkowner = table.find({'AWP', 'Nihon'}, executorName()) and isnetworkowner or function()
	return true
end
end
end
local gameCamera = workspace.CurrentCamera
local lplr = svc.playersService.LocalPlayer

local vape = shared.vape
local entitylib = vape.Libraries.entity
local sessioninfo = vape.Libraries.sessioninfo
local uipallet = vape.Libraries.uipallet
local color = vape.Libraries.color
local whitelist = vape.Libraries.whitelist
local getfontsize = vape.Libraries.getfontsize

-- Is Catvape's menu open: newgui's field (safe from any thread), the Instance only as fallback.
local function clickGuiOpen()
	local open = vape.ClickGuiOpen
	if open ~= nil then return open == true end
	if vape.ThreadFix then pcall(setthreadidentity, 8) end
	local ok, visible = pcall(function()
		return vape.gui.ScaledGui.ClickGui.Visible
	end)
	return ok and visible == true
end

do
local function priorityRank(entity, mode)
	local isPlayer = entity and entity.Player ~= nil
	if mode == 'NPCs first' then return isPlayer and 1 or 0 end
	return isPlayer and 0 or 1
end

local priorityTargetOutput = {}
do
local function priorityTarget(options, priority)
	if not priority or priority.Value == 'Closest' then
		return entitylib.EntityPosition(options)
	end
	options.Cache = true
	options.Output = options.Output or priorityTargetOutput
	local targets = entitylib.AllPosition(options)
	--[[ The first target of the best rank, in the order AllPosition returned them. That is
	exactly what the stable sort this replaces put at the front, without the sort, the order
	table and the comparator it allocated on every call -- AimAssist makes one per frame. ]]
	local mode = priority.Value
	local best, bestRank
	for _, entity in targets do
		local rank = priorityRank(entity, mode)
		if best == nil or rank < bestRank then
			best, bestRank = entity, rank
			if rank == 0 then break end
		end
	end
	return best
end
end
end

local store = {
	attackReach = 0,
	attackReachUpdate = os.clock(),
	damageBlockFail = os.clock(),
	hand = {},
	inventory = {
		inventory = {
			items = {},
			armor = {}
		},
		hotbar = {}
	},
	inventories = {},
	matchState = 0,
	queueType = 'bedwars_test',
	tools = {}
}

--[[ Every kit you are playing, not just the first.

Kit Fusion (combined_kit_to4) plays two at once. The game keeps them in the PlayingAsKits
attribute as "kit_a,kit_b" (KitController:getActiveKits), while Bedwars.kit -- what
store.equippedKit mirrors -- only ever holds the first (getPrimaryActiveKit). So every
`store.equippedKit == kit` check was blind to the second kit, and its AutoKit loop, AutoBuy
picks and kit modules never ran. hasKit is the game's own KitController:isUsingKit: any active
kit, or one granted on top of them as an ExtraKit_<kit> attribute. Both functions live on store
so every module reads the same answer. ]]
do
	local listSource, listKits = nil, {}

	function store.activeKits()
		local list = lplr:GetAttribute('PlayingAsKits')
		if type(list) ~= 'string' then
			list = store.equippedKit or ''
		end
		if list ~= listSource then
			listSource = list
			listKits = {}
			for _, kit in list:split(',') do
				if kit ~= '' and kit ~= 'none' then
					table.insert(listKits, kit)
				end
			end
		end
		-- The store has the kit before the attribute arrives (and after it is cleared).
		if store.equippedKit and store.equippedKit ~= '' and not table.find(listKits, store.equippedKit) then
			local kits = table.clone(listKits)
			table.insert(kits, 1, store.equippedKit)
			return kits
		end
		return listKits
	end

	function store.hasKit(kit)
		if type(kit) ~= 'string' or kit == '' then return false end
		return table.find(store.activeKits(), kit) ~= nil or lplr:GetAttribute('ExtraKit_'..kit) == true
	end
end
local Reach = {}
local HitBoxes = {}
local InfiniteFly = {}
local TrapDisabler
-- Which trap reports TrapDisabler drops, keyed by the remote the trap's controller fires.
local TrapToggles = {}
local bedwars, remotes, sides, oldinvrender, oldSwing = {}, {}, {}

--[[ Resolves a player's active enchant to its icon. Enchants replicate as
StatusEffect_<type> attributes on the character (with a matching _stacks
attribute that is skipped), so the type has to be run back through
StatusEffectMeta and stripped of its _1/_2/_3 level suffix before EnchantMeta
will recognise it. Indexed rather than precomputed because the set changes
constantly mid-fight.

Has to sit BELOW the `local bedwars` declaration above, not up with the rest of
`store`. A local is only in scope for code that comes after it, so from up there
these `bedwars` references compiled against the (never-assigned) global instead of
capturing the local as an upvalue -- the file assigns the local later, which this
closure would never have seen. Deferring the call didn't help; it was scope, not
timing. ]]
store.enchants = setmetatable({}, {
	__index = function(self, plr)
		return {
			async = function()
				if plr and plr.Character then
					for i in plr.Character:GetAttributes() do
						if i:find('StatusEffect_') and not i:find('_stacks') then
							local name = bedwars.StatusEffectMeta[({i:gsub('StatusEffect_', '')})[1]]
							if bedwars.StatusEffectMeta[name] then
								name = bedwars.StatusEffectMeta[name]
								for num = 1, 3 do
									name = name:gsub(`_{num}`, '')
								end

								if bedwars.EnchantMeta[name] then
									return bedwars.EnchantMeta[name].image
								end
							end
						end
					end
				end
				return nil
			end,
		}
	end
})

--[[ Fly and TestFly's Heatseeker both stop your balloons popping while they fly. Each used to
save and put back deflateBalloon on its own, so with both on, whichever turned off last put the
other's no-op back and balloons stayed unpoppable until rejoin. They share one counted hold:
the first takes the original, the last gives it back. ]]
do
	local holds, original = 0, nil
	local function noPop() end

	function store.holdBalloons(hold)
		local controller = bedwars.BalloonController
		if not controller then return end
		if hold then
			if holds == 0 then
				original = controller.deflateBalloon
				controller.deflateBalloon = noPop
			end
			holds += 1
		elseif holds > 0 then
			holds -= 1
			if holds == 0 then
				controller.deflateBalloon = original
				original = nil
			end
		end
	end
end

--[[ The loader's look, for what this file draws on the HUD and in the world, as the TP Down bar
and the AutoBank box already are: the loader window's near-black with a tenth of its orange
through it, part see-through, a soft orange border and rounded corners. Text is the menu's Inter
in the loader's light grey, labels in its secondary grey. ]]
local loaderStyle = {
	Orange = Color3.fromRGB(240, 122, 31),
	Text = Color3.fromRGB(230, 230, 230),
	SubText = Color3.fromRGB(163, 161, 157),
	-- What a button or a slot sits on inside a box, and its border: the loader's own buttons.
	Button = Color3.fromRGB(18, 18, 18),
	ButtonBorder = Color3.fromRGB(60, 60, 60),
	Transparency = 0.3
}
loaderStyle.Background = Color3.fromRGB(10, 10, 10):Lerp(loaderStyle.Orange, 0.1)
-- The background as colour-slider defaults, so a box with a colour option starts on it.
loaderStyle.Hue, loaderStyle.Sat, loaderStyle.Value = loaderStyle.Background:ToHSV()
loaderStyle.SubHex = '#'..loaderStyle.SubText:ToHex()

function loaderStyle.corner(obj, radius)
	local corner = Instance.new('UICorner')
	corner.CornerRadius = typeof(radius) == 'UDim' and radius or UDim.new(0, radius or 8)
	corner.Parent = obj
	return corner
end

function loaderStyle.stroke(obj, strokeColor, transparency, thickness)
	local stroke = Instance.new('UIStroke')
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = strokeColor or loaderStyle.Orange
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0.55
	stroke.Parent = obj
	return stroke
end

function loaderStyle.box(obj, radius)
	obj.BackgroundColor3 = loaderStyle.Background
	obj.BackgroundTransparency = loaderStyle.Transparency
	obj.BorderSizePixel = 0
	loaderStyle.corner(obj, radius)
	return loaderStyle.stroke(obj)
end

-- Inter through the font registry, so the label follows it if it finishes loading late.
function loaderStyle.text(label, role, textColor)
	label.TextColor3 = textColor or loaderStyle.Text
	label.TextStrokeTransparency = 1
	local fonts = vape.Libraries.fonts
	if fonts and fonts.track then
		fonts.track(label, role or 'Medium')
	end
	return label
end

local function collection(tags, module, customadd, customremove)
	tags = typeof(tags) ~= 'table' and {tags} or tags
	local objs, connections = {}, {}

	for _, tag in tags do
		table.insert(connections, svc.collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
			if customadd then
				customadd(objs, v, tag)
				return
			end
			table.insert(objs, v)
		end))
		table.insert(connections, svc.collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
			if customremove then
				customremove(objs, v, tag)
				return
			end
			v = table.find(objs, v)
			if v then
				table.remove(objs, v)
			end
		end))

		for _, v in svc.collectionService:GetTagged(tag) do
			if customadd then
				customadd(objs, v, tag)
				continue
			end
			table.insert(objs, v)
		end
	end

	local cleanFunc = function(self)
		for _, v in connections do
			v:Disconnect()
		end
		table.clear(connections)
		table.clear(objs)
		table.clear(self)
	end
	if module then
		module:Clean(cleanFunc)
	end
	return objs, cleanFunc
end

do
local function getBestArmor(slot)
	local closest, mag = nil, 0

	for _, item in store.inventory.inventory.items do
		local meta = item and bedwars.ItemMeta[item.itemType] or {}

		if meta.armor and meta.armor.slot == slot then
			local newmag = (meta.armor.damageReductionMultiplier or 0)

			if newmag > mag then
				closest, mag = item, newmag
			end
		end
	end

	return closest
end
end

do
local function getBow()
	local bestBow, bestSlot, highestDamage = nil, nil, 0
	for slot, item in store.inventory.inventory.items do
		local meta = bedwars.ItemMeta[item.itemType]
		if meta then
			local source = meta.projectileSource
			-- ammoItemTypes is absent on self-fuelled launchers (the frost staffs and most kit
			-- casters -- bedwars.lua's isSelfFuelled is about the same field), and
			-- table.find(nil, ...) throws rather than returning nil. Carrying one of those made
			-- every getBow() call error out, which takes the caller with it.
			if source and source.ammoItemTypes and table.find(source.ammoItemTypes, "arrow") then
				local damage = (bedwars.ProjectileMeta[source.projectileType("arrow")] or {}).combat and bedwars.ProjectileMeta[source.projectileType("arrow")].combat.damage or 0
				if damage > highestDamage then
					bestBow, bestSlot, highestDamage = item, slot, damage
				end
			end
		end
	end
	return bestBow, bestSlot
end
end

local function getItem(itemName, inv)
	for slot, item in (inv or store.inventory.inventory.items) do
		if item and item.itemType == itemName then
			return item, slot
		end
	end
end

do
local function getRoactRender(func)
	return debug.getupvalue(debug.getupvalue(debug.getupvalue(func, 3).render, 2).render, 1)
end
end

local function getSword()
	local best, slot, maxDmg = nil, nil, 0
	for i, item in store.inventory.inventory.items do
		local meta = bedwars.ItemMeta[item.itemType]
		local sword = meta and meta.sword
		if sword then
			local dmg = sword.damage or 0
			if dmg > maxDmg then
				best, slot, maxDmg = item, i, dmg
			end
		end
	end
	return best, slot
end

local function getTool(breakType)
	local best, slot, maxDmg = nil, nil, 0
	for i, item in store.inventory.inventory.items do
		local meta = bedwars.ItemMeta[item.itemType]
		local tool = meta and meta.breakBlock
		if tool then
			local dmg = tool[breakType] or 0
			if dmg > maxDmg then
				best, slot, maxDmg = item, i, dmg
			end
		end
	end
	return best, slot
end

--[[ Fallback for a block type nothing in the inventory is specialised for -- wool while
carrying a pickaxe but no shears, say. getTool only matches a tool declaring the
block's own breakType, so it returns nil there and the swap was skipped entirely,
leaving the sword in hand. A break tool still beats that, so take the strongest one
available judged by its best break value across all types. Only consulted after an
exact type match fails, so shears still win for wool whenever they're carried. ]]
local function getBestBreakTool()
	local best, maxDmg = nil, 0
	for _, item in store.inventory.inventory.items do
		local meta = bedwars.ItemMeta[item.itemType]
		local breakBlock = meta and meta.breakBlock
		if breakBlock then
			for _, dmg in breakBlock do
				if type(dmg) == 'number' and dmg > maxDmg then
					best, maxDmg = item, dmg
				end
			end
		end
	end
	return best
end

local function getWool(inv)
	for _, item in (inv or store.inventory.inventory.items) do
		if item and item.itemType and item.itemType:find("wool") then
			return item.itemType, item.amount
		end
	end
end

do
local function getStrength(plr)
	if not (plr and plr.Player) then return 0 end
	local strength = 0
	local inv = store.inventories[plr.Player]
	if not inv then return 0 end

	for _, v in inv.items do
		local meta = bedwars.ItemMeta[v.itemType]
		if meta and meta.sword and meta.sword.damage > strength then
			strength = meta.sword.damage
		end
	end
	return strength
end
end

local function getPlacedBlock(pos)
	if not pos then return end
	local blockPos = bedwars.BlockController:getBlockPosition(pos)
	return bedwars.BlockController:getStore():getBlockAt(blockPos), blockPos
end

do
local function getBlocksInPoints(s, e)
	local blocks, list = bedwars.BlockController:getStore(), {}
	for x = s.X, e.X do
		for y = s.Y, e.Y do
			for z = s.Z, e.Z do
				local vec = Vector3.new(x, y, z)
				if blocks:getBlockAt(vec) then
					list[#list + 1] = vec * 3
				end
			end
		end
	end
	return list
end
end

--[[ The nearest block with air above it, within `range` cells and under 60 studs.

This used to list every block in the whole cube first and only then look for the nearest,
which is a block store lookup for every cell: 41^3 of them at the range of 20 AutoPearl asks
with, twice per throw, in the one moment a hitch hurts most -- while you are falling.

It now walks outward from your own cell and never looks at a cell, row or slab that is
already further away than the best found so far, so the nearer the ground, the sooner the
search stops; with nothing in range at all it still never looks past 60 studs, which at
AutoPearl's range is half the cube. The answer is the one the full sweep gave: the nearest,
and on an exact tie the cell that comes first in x, then y, then z order, which is the cell
the sweep reached first. ]]
do
local function getNearGround(range)
	range = Vector3.new(3, 3, 3) * (range or 10)
	local localPos = entitylib.character.RootPart.Position
	local closest, bestMag = nil, 60
	local bestX, bestY, bestZ
	local s, e = bedwars.BlockController:getBlockPosition(localPos - range), bedwars.BlockController:getBlockPosition(localPos + range)
	local center = bedwars.BlockController:getBlockPosition(localPos)
	local blocks = bedwars.BlockController:getStore()
	local up = Vector3.new(0, 3, 0)
	local lx, ly = localPos.X, localPos.Y

	-- Squared distance nothing can beat any more, with a little slack for float noise.
	local function limit()
		local bound = bestMag + 0.001
		return bound * bound
	end
	-- The least distance, along one axis, of a cell `step` cells from yours: your cell's
	-- centre is at most 1.5 studs from you.
	local function gap(step)
		return math.max(step * 3 - 1.51, 0)
	end

	for xStep = 0, math.max(center.X - s.X, e.X - center.X) do
		local gx = gap(xStep)
		if gx * gx > limit() then break end
		for xSide = 1, xStep == 0 and 1 or 2 do
			local x = xSide == 1 and center.X + xStep or center.X - xStep
			if x < s.X or x > e.X then continue end
			local dx = x * 3 - lx
			for yStep = 0, math.max(center.Y - s.Y, e.Y - center.Y) do
				local gy = gap(yStep)
				if dx * dx + gy * gy > limit() then break end
				for ySide = 1, yStep == 0 and 1 or 2 do
					local y = ySide == 1 and center.Y + yStep or center.Y - yStep
					if y < s.Y or y > e.Y then continue end
					local dy = y * 3 - ly
					local dxy = dx * dx + dy * dy
					for zStep = 0, math.max(center.Z - s.Z, e.Z - center.Z) do
						local gz = gap(zStep)
						if dxy + gz * gz > limit() then break end
						for zSide = 1, zStep == 0 and 1 or 2 do
							local z = zSide == 1 and center.Z + zStep or center.Z - zStep
							if z < s.Z or z > e.Z then continue end
							local v = Vector3.new(x, y, z) * 3
							local mag = (localPos - v).Magnitude
							local better = mag < bestMag
							if not better and mag == bestMag and closest then
								if x ~= bestX then
									better = x < bestX
								elseif y ~= bestY then
									better = y < bestY
								else
									better = z < bestZ
								end
							end
							if better and blocks:getBlockAt(Vector3.new(x, y, z)) and not getPlacedBlock(v + up) then
								bestMag, closest = mag, v + up
								bestX, bestY, bestZ = x, y, z
							end
						end
					end
				end
			end
		end
	end

	return closest
end
end

do
local function getShieldAttribute(char)
	local total = 0
	for name, val in char:GetAttributes() do
		if type(val) == "number" and val > 0 and name:find("Shield") then
			total += val
		end
	end
	return total
end

local function _baseGetSpeed()
    local multi, increase, modifiers = 0, true, bedwars.SprintController:getMovementStatusModifier():getModifiers()

    for v in modifiers do
        local val = v.constantSpeedMultiplier or 0
        if val > math.max(multi, 1) then
            increase = false
            multi = val - (0.06 * math.round(val))
        end
    end

    for v in modifiers do
        multi += math.max((v.moveSpeedMultiplier or 0) - 1, 0)
    end

    if multi > 0 and increase then
        multi += 0.16 + (0.02 * math.round(multi))
    end

    return 20 * (multi + 1)
end

local function getSpeed()
    --[[ Delegate to shared.bedwars.getSpeed if DamageBoost has wrapped it ]]
    local bw = shared.bedwars
    if bw and type(bw.getSpeed) == "function" then
        return bw.getSpeed()
    end
    return _baseGetSpeed()
end

--[[ The same reading with nothing layered on top -- straight past whatever DamageBoost wrapped
local anim = {}
around it. Speed's Legit mode uses this so the top-up is measured against the speed the server
believes you have rather than one the boost inflated. ]]
do
local function rawGetSpeed()
    return _baseGetSpeed()
end
end
end

local function getTableSize(tab)
	local ind = 0
	for _ in tab do
		ind += 1
	end
	return ind
end

local function ensureSessionInfo()
	sessioninfo = sessioninfo or vape.Libraries.sessioninfo
	if type(sessioninfo) == 'table' and type(sessioninfo.Objects) == 'table' and type(sessioninfo.AddItem) == 'function' then
		return sessioninfo
	end

	local added = 0
	sessioninfo = {
		Objects = {},
		AddItem = function(self, name, startvalue, func, saved)
			added += 1
			self.Objects[name] = {
				Function = func or function(val) return val end,
				Saved = saved == nil or saved,
				Value = startvalue or 0,
				Index = getTableSize(self.Objects) + 2
			}
			return {
				Increment = function(_, val)
					self.Objects[name].Value += (val or 1)
				end,
				Get = function()
					return self.Objects[name].Value
				end
			}
		end
	}
	vape.Libraries.sessioninfo = sessioninfo
	return sessioninfo
end

local function hotbarSwitch(slot)
	if slot and store.inventory.hotbarSlot ~= slot then
		bedwars.Store:dispatch({
			type = 'InventorySelectHotbarSlot',
			slot = slot
		})
		vapeEvents.InventoryChanged.Event:Wait()
		return true
	end
	return false
end

--[[ The kit to SHOW for a player, and the icon for it.

Two separate problems lived in the one line this replaces:

  * PlayingAsKit (singular) is the older attribute. The live one is PlayingAsKits, a comma
    separated LIST -- kit-util's getKitArrayFromCommaSeparatedString is a plain string.split
    on ',' because a player can be on more than one kit at once. Reading only the singular
    meant the nametag icon was blank for anyone the game describes the modern way.
  * BedwarsKitMeta[kit].renderImage was indexed with no nil guard, so any value without a
    meta entry -- an unknown kit, a combined string, a renamed id after an update -- was a
    hard error raised inside the nametag loop rather than a missing icon.

The first non-empty entry is the one to show: KitController:getPrimaryActiveKit is exactly
getActiveKits()[1]. ]]
--[[ Your own input, for the AFK checks on TriggerBot, ProjectileAura and AutoZeno: they
stand down once nothing has been pressed, clicked or moved for AFK_SECONDS. Mouse movement
only counts when the mouse actually moved -- InputChanged also fires with a zero delta. ]]
do
local AFK_SECONDS = 30
store.lastInput = tick()
local function markInput(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement or input.Delta.Magnitude > 0 then
		store.lastInput = tick()
	end
end
vape:Clean(svc.inputService.InputBegan:Connect(markInput))
vape:Clean(svc.inputService.InputChanged:Connect(markInput))

-- `seconds` overrides the default for a module that lets you pick its own threshold.
do
local function isLocalAfk()
	return (tick() - store.lastInput) >= AFK_SECONDS
end
end

end
-- The player's primary kit: the first entry of PlayingAsKits, falling back to the older
-- singular attribute. Shared by everything that asks "what kit is this player on".
do
local function getPrimaryKit(plr)
	if not plr then return nil end

	local kit = plr:GetAttribute('PlayingAsKits')
	if type(kit) == 'string' and kit ~= '' then
		for _, name in string.split(kit, ',') do
			if name ~= '' then
				return name
			end
		end
	end

	kit = plr:GetAttribute('PlayingAsKit')
	if type(kit) == 'string' and kit ~= '' then
		return kit
	end
	return nil
end

do
local function getKitRenderImage(plr)
	if not plr then return '' end

	local kit = getPrimaryKit(plr)
	if not kit or kit == 'none' then return '' end

	local meta = bedwars.BedwarsKitMeta and bedwars.BedwarsKitMeta[kit]
	return (meta and meta.renderImage) or ''
end
end

end
local function isFriend(plr, recolor)
	if vape.Categories.Friends.Options['Use friends'].Enabled then
		local friend = table.find(vape.Categories.Friends.ListEnabled, plr.Name) and true
		if recolor then
			friend = friend and vape.Categories.Friends.Options['Recolor visuals'].Enabled
		end
		return friend
	end
	return nil
end

local function isTarget(plr)
	return table.find(vape.Categories.Targets.ListEnabled, plr.Name) and true
end

local function notif(...)
	return vape:CreateNotification(...)
end

local function removeTags(str)
	str = str:gsub('<br%s*/>', '\n')
	return (str:gsub('<[^<>]->', ''))
end

do
local function roundPos(vec)
	return Vector3.new(math.round(vec.X / 3) * 3, math.round(vec.Y / 3) * 3, math.round(vec.Z / 3) * 3)
end
end

--[[ Developer-only equip trace (shared.CatvapeDeveloper). Swaps have to be caught while
the code that asked for them is still on the stack, so this runs before switchItem spawns
its request. Deduplicated per item and call site over half a second, so a module that
re-requests the same swap every frame logs it once rather than flooding the console. ]]
local equipTraceKey, equipTraceAt = nil, 0
local switchItemRequested = setmetatable({}, {__mode = 'k'})
local function traceEquip(tool, via)
	if not shared.CatvapeDeveloper then return end
	local ok, trace = pcall(debug.traceback, '', 3)
	trace = ok and trace or ''
	local now = os.clock()
	local key = tostring(tool) .. via .. trace
	if key == equipTraceKey and now - equipTraceAt < 0.5 then return end
	equipTraceKey, equipTraceAt = key, now
	local handInv = lplr.Character and lplr.Character:FindFirstChild('HandInvItem')
	local held = handInv and handInv.Value
	local cached = store and store.hand and store.hand.tool
	print(string.format('[catvape equip] t=%.3f %s: holding %s (store.hand %s) -> %s%s',
		now, via,
		held and held.Name or 'nothing',
		cached and cached.Name or 'nothing',
		typeof(tool) == 'Instance' and tool.Name or tostring(tool),
		trace))
end

local function switchItem(tool, delayTime)
	delayTime = delayTime or 0.05
	local check = lplr.Character and lplr.Character:FindFirstChild('HandInvItem') or nil
	if check and check.Value ~= tool and tool.Parent ~= nil then
		if shared.CatvapeDeveloper then
			switchItemRequested[tool] = os.clock()
			traceEquip(tool, 'switchItem')
		end
		task.spawn(function()
			bedwars.Client:Get(remotes.EquipItem):CallServerAsync({hand = tool})
		end)
		check.Value = tool
		if delayTime > 0 then
			task.wait(delayTime)
		end
		return true
	end
end

local function waitForChildOfType(obj, name, timeout, prop)
	local check, returned = os.clock() + timeout
	repeat
		returned = prop and obj[name] or obj:FindFirstChildOfClass(name)
		if returned and returned.Name ~= 'UpperTorso' or check < os.clock() then
			break
		end
		task.wait()
	until false
	return returned
end

--[[ Root part for a non-player entity. Prefers a rig's HumanoidRootPart over whatever
the model names as its PrimaryPart, and settles for either.

Player dummies -- the tutorial ones included -- are character rigs, and a rig is
under no obligation to name a PrimaryPart. Asking for PrimaryPart alone spent the
whole timeout and then handed back nil, and a nil root is why the dummy never
reached the entity list at all. Where a rig does name one it is often UpperTorso,
which is the name the helper above already had to special-case; taking the root part
directly sidesteps that too. Monsters that are not rigs at all -- crates, statues --
have no HumanoidRootPart and still fall back to PrimaryPart. ]]
local function waitForRootPart(char, timeout)
	local check = os.clock() + timeout
	repeat
		local root = char:FindFirstChild('HumanoidRootPart') or char.PrimaryPart
		if root or check < os.clock() then return root end
		task.wait()
	until false
end

local frictionTable, oldfrict = {}, {}
local frictionConnection
local frictionState

local function modifyVelocity(v)
	if v:IsA('BasePart') and v.Name ~= 'HumanoidRootPart' and not oldfrict[v] then
		oldfrict[v] = v.CustomPhysicalProperties or 'none'
		v.CustomPhysicalProperties = PhysicalProperties.new(0.0001, 0.2, 0.5, 1, 1)
	end
end

local function updateVelocity(force)
	-- next(), not a full count: the only question is whether anything is in there, and
	-- getTableSize walks every entry to answer it.
	local newState = next(frictionTable) ~= nil
	if frictionState ~= newState or force then
		if frictionConnection then
			frictionConnection:Disconnect()
		end
		if newState then
			--[[ Parts a previous character left behind. A respawn lands here with the module
			still on, and their entries used to stay until the last friction user turned off,
			holding every dead character of the match. They are put back the way the disable
			below would, then let go. Weak keys are no answer: an Instance's Lua handle can be
			collected while the part is still alive, which would drop a part we still owe a
			restore to. ]]
			for part, props in oldfrict do
				if not part:IsDescendantOf(game) then
					oldfrict[part] = nil
					pcall(function()
						part.CustomPhysicalProperties = props ~= 'none' and props or nil
					end)
				end
			end
			if entitylib.isAlive then
				for _, v in entitylib.character.Character:GetDescendants() do
					modifyVelocity(v)
				end
				frictionConnection = entitylib.character.Character.DescendantAdded:Connect(modifyVelocity)
			end
		else
			for i, v in oldfrict do
				i.CustomPhysicalProperties = v ~= 'none' and v or nil
			end
			table.clear(oldfrict)
		end
	end
	frictionState = newState
end

do
local kitorder = {
	hannah = 5,
	spirit_assassin = 4,
	dasher = 3,
	jade = 2,
	regent = 1
}
end


run(function()
	local oldstart = entitylib.start

	--[[ A Practice room dummy is identified by either of the two markers.
	training-room-entity-controller watches the tag and then reads the attribute off
	the instance; the attribute is the half that actually shows up on a dummy in the
	explorer, so neither is trusted alone. ]]
	local function isTrainingDummy(ent)
		return ent:HasTag('trainingRoomDummy') or ent:GetAttribute('TrainingRoomDummy') ~= nil
	end

	local function customEntity(ent)
		--[[ Inventory entities are the shop keepers and other furniture standing around a
		lobby, which is why they are skipped. But a dummy is one too -- it wears armor
		and holds an item, so it has the same ArmorInvItem/HandInvItem rig a player
		does -- and this guard was throwing away the only thing in the Practice room
		worth hitting, no matter which tag found it. ]]
		if ent:HasTag('inventory-entity') and not (ent:HasTag('Monster') or isTrainingDummy(ent)) then
			return
		end

		--[[ Monsters are watched under their own tag as well as 'entity' (see start
		below), so anything carrying both arrives here twice and would be registered
		twice -- two list entries for one character, counting double against Max
		targets and drawing two of every box. ]]
		if entitylib.EntityThreads[ent] or entitylib.getEntity(ent) then
			return
		end

		entitylib.addEntity(ent, nil, ent:HasTag('Drone') and function(self)
			local droneplr = svc.playersService:GetPlayerByUserId(self.Character:GetAttribute('PlayerUserId'))
			return not droneplr or lplr:GetAttribute('Team') ~= droneplr:GetAttribute('Team')
		end or function(self)
			--[[ Nothing without a team is anybody's teammate. Practice and tutorial
			dummies carry no Team attribute, and in the lobby neither do we, so the
			plain comparison had nil equal to nil and read every dummy as friendly --
			untargetable in exactly the place where they are the only thing to hit.
			In a real match this changes nothing: a team-less monster was already
			targetable there, since our own team is set. ]]
			local theirteam = self.Character:GetAttribute('Team')
			if theirteam == nil then return true end
			return lplr:GetAttribute('Team') ~= theirteam
		end)
	end

	--[[ Dummies are entities the 'entity' tag alone never reaches, and they come in two
	kinds under two different tags:

	  Monster             tutorial dummies. The game's own entity-util resolves these
	                      through its inventory-entity branch, which returns before it
	                      ever asks whether the instance carries 'entity' -- so a
	                      player dummy is a full entity to the game while being
	                      invisible to a watcher that only knows the one tag. Monster
	                      is what the game itself watches for them, in
	                      player-dummy-controller and in the tutorial's kill tasks.
	  trainingRoomDummy   the Practice room's dummies, tagged and driven entirely by
	                      training-room-entity-controller.

	customEntity dedupes, so anything holding more than one of these is still
	registered once. ]]
	local ENTITY_TAGS = {'entity', 'Monster', 'trainingRoomDummy'}

	entitylib.start = function()
		oldstart()
		if entitylib.Running then
			for _, tag in ENTITY_TAGS do
				for _, ent in svc.collectionService:GetTagged(tag) do
					customEntity(ent)
				end
				table.insert(entitylib.Connections, svc.collectionService:GetInstanceAddedSignal(tag):Connect(customEntity))
				table.insert(entitylib.Connections, svc.collectionService:GetInstanceRemovedSignal(tag):Connect(function(ent)
					entitylib.removeEntity(ent)
				end))
			end
		end
	end

	entitylib.addPlayer = function(plr)
		if plr.Character then
			entitylib.refreshEntity(plr.Character, plr)
		end
		entitylib.PlayerConnections[plr] = {
			plr.CharacterAdded:Connect(function(char)
				entitylib.refreshEntity(char, plr)
			end),
			plr.CharacterRemoving:Connect(function(char)
				entitylib.removeEntity(char, plr == lplr)
			end),
			--[[ BedWars keeps the team on an ATTRIBUTE, and it lands AFTER the entity does.
			The game's own controllers sit in `while Attribute == nil do task.wait(1) end`
			loops waiting for it, so every entity is necessarily built with the team still
			unknown and Targetable comes out wrong. This signal is what corrects them, and it
			is the only thing that does -- the library's own refresh watches the Team PROPERTY,
			which bedwars never sets.

			It used to correct them by REBUILDING, and all three ways it did that were wrong.

			refreshEntity removes from entitylib.List with a swap-remove, and this loop was
local sph = {}
			iterating that same list: the entity swapped down into the slot just sph.visited was
			skipped, so an arbitrary subset of players kept a stale Targetable -- a different
			subset every match, which is why anim.Priority Only worked in some games and hid
			everybody in others.

			entitylib.start() tore down and rebuilt the entire library whenever the LOCAL
			player's team landed, which is a thing that happens every single match. start()
			re-registers only its three default connections, so the CollectionService hooks
			this file installs for drones, guardians and training dummies were disconnected
			and never came back: NPC tracking died the moment your own team arrived.

			And every rebuild replaces every entity table, orphaning whatever the modules had
			keyed to the old ones -- nametags included.

local ph = {}
			None of that is needed. The team is the only thing that ph.changed, so re-run the
			check in place and fire EntityUpdated, which is exactly what updateEntity does
			everywhere else in the library. It also keeps Friend/Target and the raycast filter
			in step, which the hand-rolled version above did not. ]]
			plr:GetAttributeChangedSignal('Team'):Connect(function()
				-- your own team flips everybody's standing; anyone else's flips only theirs
				if plr == lplr then
					for _, v in entitylib.List do
						entitylib.updateEntity(v, true)
					end
				else
					local ent = entitylib.getEntity(plr)
					if ent then
						entitylib.updateEntity(ent, true)
					end
				end
			end)
		}
	end

	--[[ WaitForChild, polled. A restart cancels every builder still waiting (entitylib.stop
	does it), and a builder parked in WaitForChild is held by the engine, which still tries to
	resume it when the child turns up -- the likely source of the "cannot resume dead coroutine"
	at boot. Parked on task.wait, a cancel always lands on a yield it owns. Same answer as
	WaitForChild: the child, or nil once the timeout has passed. ]]
	local function waitForNamedChild(parent, name, timeout)
		local check = os.clock() + timeout
		repeat
			local child = parent:FindFirstChild(name)
			if child or check < os.clock() then return child end
			task.wait()
		until false
	end

	--[[ The local character's attribute forwarder. Each local build used to add one to
	entitylib.Connections, where it stayed until the library stopped, so every character you had
	been this match stayed referenced by its listener. Only the newest is kept: the previous one
	goes when the next is connected, never on death, so the live character forwards for exactly
	as long as it did. ]]
	local localForwarder

	--[[ Same thread-tracking rule as the library's own addEntity, for the same reason:
	a build that finishes without yielding -- which is every character that is already
	streamed in -- would otherwise leave a dead thread in EntityThreads, and the next
	removeEntity would throw on the cancel instead of firing EntityRemoved. ]]
	entitylib.addEntity = function(char, plr, teamfunc)
		if not char then return end
		local builder = task.spawn(function()
			local hum, humrootpart, head
			if plr then
				hum = waitForChildOfType(char, 'Humanoid', 10)
				humrootpart = hum and waitForChildOfType(hum, 'RootPart', workspace.StreamingEnabled and 9e9 or 10, true)
				head = waitForNamedChild(char, 'Head', 10) or humrootpart
			else
				hum = {HipHeight = 0.5}
				humrootpart = waitForRootPart(char, 10)
				head = humrootpart
			end
			local updateobjects = plr and plr ~= lplr and {
				waitForNamedChild(char, 'ArmorInvItem_0', 5),
				waitForNamedChild(char, 'ArmorInvItem_1', 5),
				waitForNamedChild(char, 'ArmorInvItem_2', 5),
				waitForNamedChild(char, 'HandInvItem', 5)
			} or {}

			if hum and humrootpart then
				local startHealth, startMaxHealth = entitylib.readHealth(char)
				local entity = {
					Connections = {},
					Character = char,
					Health = startHealth,
					Head = head,
					Humanoid = hum,
					HumanoidRootPart = humrootpart,
					HipHeight = hum.HipHeight + (humrootpart.Size.Y / 2) + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or 0),
					Jumps = 0,
					JumpTick = os.clock(),
					Jumping = false,
					LandTick = os.clock(),
					MaxHealth = startMaxHealth,
					NPC = plr == nil,
					Player = plr,
					RootPart = humrootpart,
					TeamCheck = teamfunc
				}

				if plr == lplr then
					entity.AirTime = os.clock()
					entitylib.character = entity
					entitylib.isAlive = true
					entitylib.Events.LocalAdded:Fire(entity)
					if localForwarder then
						local index = table.find(entitylib.Connections, localForwarder)
						if index then
							table.remove(entitylib.Connections, index)
						end
						localForwarder:Disconnect()
					end
					localForwarder = char.AttributeChanged:Connect(function(attr)
						vapeEvents.AttributeChanged:Fire(attr)
					end)
					table.insert(entitylib.Connections, localForwarder)
				else
					entity.Targetable = entitylib.targetCheck(entity)

					local function refreshHealth()
						entity.Health, entity.MaxHealth = entitylib.readHealth(char)
						entitylib.Events.EntityUpdated:Fire(entity)
					end

					for _, v in entitylib.getUpdateConnections(entity) do
						table.insert(entity.Connections, v:Connect(refreshHealth))
					end

					--[[ An NPC is built around a stand-in humanoid table (see above), so nothing
					here was ever listening to its real Humanoid -- and a dummy or monster that keeps
					its health there, rather than in the Health attribute players carry, never fired
					a single update: its nametag sat on the number it was built with. Watch the real
					one, including a Humanoid that is only parented after the entity is. ]]
					if not plr then
						local function watchHumanoid(humanoid)
							table.insert(entity.Connections, humanoid:GetPropertyChangedSignal('Health'):Connect(refreshHealth))
							table.insert(entity.Connections, humanoid:GetPropertyChangedSignal('MaxHealth'):Connect(refreshHealth))
							refreshHealth()
						end
						local humanoid = char:FindFirstChildOfClass('Humanoid')
						if humanoid then
							watchHumanoid(humanoid)
						else
							local waiting
							waiting = char.ChildAdded:Connect(function(child)
								if child:IsA('Humanoid') then
									waiting:Disconnect()
									watchHumanoid(child)
								end
							end)
							table.insert(entity.Connections, waiting)
						end
					end

					for _, v in updateobjects do
						table.insert(entity.Connections, v:GetPropertyChangedSignal('Value'):Connect(function()
							task.delay(0.1, function()
								if bedwars.getInventory then
									store.inventories[plr] = bedwars.getInventory(plr)
									entitylib.Events.EntityUpdated:Fire(entity)
								end
							end)
						end))
					end

					if plr then
						local anim = char:FindFirstChild('Animate')
						if anim then
							pcall(function()
								anim = anim.jump:FindFirstChildWhichIsA('Animation').AnimationId
								table.insert(entity.Connections, hum.Animator.AnimationPlayed:Connect(function(playedanim)
									if playedanim.Animation.AnimationId == anim then
										entity.JumpTick = os.clock()
										entity.Jumps += 1
										entity.LandTick = os.clock() + 1
										entity.Jumping = entity.Jumps > 1
									end
								end))
							end)
						end

						task.delay(0.1, function()
							if bedwars.getInventory then
								store.inventories[plr] = bedwars.getInventory(plr)
							end
						end)
					end
					--[[ The build above can yield for seconds (the armor slots wait up to 5s each).
					A player who leaves -- or a character destroyed -- in that window was still added
					here, after removeEntity had already run and found nothing to remove, so the
					entity sat in the list for the rest of the server with a nametag nothing would
					ever take down. Drop the build instead. ]]
					if not char.Parent or (plr and plr.Parent == nil) then
						for _, connection in entity.Connections do
							pcall(function() connection:Disconnect() end)
						end
						table.clear(entity.Connections)
						entitylib.EntityThreads[char] = nil
						return
					end

					table.insert(entitylib.List, entity)
					entitylib.Events.EntityAdded:Fire(entity)
				end

				table.insert(entity.Connections, char.ChildRemoved:Connect(function(part)
					if part == humrootpart or part == hum or part == head then
						if part == humrootpart and hum.RootPart then
							humrootpart = hum.RootPart
							entity.RootPart = hum.RootPart
							entity.HumanoidRootPart = hum.RootPart
							return
						end
						entitylib.removeEntity(char, plr == lplr)
					end
				end))
			end
			entitylib.EntityThreads[char] = nil
		end)

		if coroutine.status(builder) ~= 'dead' then
			entitylib.EntityThreads[char] = builder
		end
	end

	--[[ Health and max health for any entity's character, shields folded into health the way
	players have always been read. Players carry both as attributes; dummies and monsters may
	only have them on a Humanoid, so that is the fallback rather than a flat 100. ]]
	entitylib.readHealth = function(char)
		local health = char:GetAttribute('Health')
		local maxHealth = char:GetAttribute('MaxHealth')
		if health == nil or maxHealth == nil then
			local humanoid = char:FindFirstChildOfClass('Humanoid')
			if humanoid then
				health = health or humanoid.Health
				maxHealth = maxHealth or humanoid.MaxHealth
			end
		end
		return (health or 100) + getShieldAttribute(char), maxHealth or 100
	end

	entitylib.getUpdateConnections = function(ent)
		local char = ent.Character
		local tab = {
			char:GetAttributeChangedSignal('Health'),
			char:GetAttributeChangedSignal('MaxHealth'),
			{
				Connect = function()
					ent.Friend = ent.Player and isFriend(ent.Player) or nil
					ent.Target = ent.Player and isTarget(ent.Player) or nil
					return {Disconnect = function() end}
				end
			}
		}

		if ent.Player then
			-- PlayingAsKits is the attribute the game actually updates; the singular one is
			-- kept for anything still on the older form.
			table.insert(tab, ent.Player:GetAttributeChangedSignal('PlayingAsKits'))
			table.insert(tab, ent.Player:GetAttributeChangedSignal('PlayingAsKit'))
		end

		for name, val in char:GetAttributes() do
			if name:find('Shield') and type(val) == 'number' then
				table.insert(tab, char:GetAttributeChangedSignal(name))
			end
		end

		return tab
	end

	entitylib.targetCheck = function(ent)
		if ent.TeamCheck then
			return ent:TeamCheck()
		end
		if ent.NPC then return true end
		if isFriend(ent.Player) then return false end
		return lplr:GetAttribute('Team') ~= ent.Player:GetAttribute('Team')
	end
	vape:Clean(entitylib.Events.LocalAdded:Connect(updateVelocity))
end)
entitylib.start()

--[[ catvape funcs ]]

do
local genv = getgenv()
--[[ Idempotent shared-state defaults: fill a key only if a previous execution
hasn't already set it. Add new flags here instead of another line below.
(== nil, not `or`, so a stored `false` is never clobbered back to default.) ]]
for key, default in pairs({
	IsLongJumping            = false,
	LongJumpFireballThrown   = false,
	ItemOwner                = "none",
	ProjectileAuraFiringLock = false,
}) do
	if genv[key] == nil then
		genv[key] = default
	end
end

local function ensureCharPrimaryPart(char)
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and char.PrimaryPart ~= hrp then
        pcall(function() char.PrimaryPart = hrp end)
    end
end

ensureCharPrimaryPart(lplr.Character)
-- Registered for cleanup: every reinject used to leave its copy of this listener behind.
vape:Clean(lplr.CharacterAdded:Connect(function(c)
    c:WaitForChild("HumanoidRootPart", 5)
    ensureCharPrimaryPart(c)
end))

end
--[[ == shared __namecall guard ==
There is exactly ONE global __namecall hook in the whole product and it lives
here, in the unobfuscated file. Every namecall in the game -- including the
tens of thousands Roact issues while it builds and re-renders the item shop --
passes through this function, so it must stay native-speed Lua. A hook
installed from bedwars.lua costs a Luraph VM re-entry on each of those calls,
which is what turned opening the shop (and every purchase re-render) into a
visible hitch while leaving the unobfuscated build smooth.

Modules that need to see or block a specific remote register the exact
(Instance, method) pair here via shared.bedwars.namecallGuard instead. The hot
path cost is one hash lookup; handlers only ever run for instances somebody
actually asked about. ]]
do
local namecallWatch = {}
local namecallGuard = {}
local namecallObservers = {}

--[[ handler may be `true` to swallow the call outright, or a function. From a function:
  nil / false       -- let the call through unchanged
  a table           -- REPLACEMENT ARGUMENTS, table.pack shape (`n` plus 1..n), forwarded
                       to the same method in place of the originals
  any other truthy  -- swallow the call
Method names are matched exactly as getnamecallmethod() reports them.

The table form exists so a module can rewrite what a remote sends without installing a
second __namecall hook of its own. That is not a style preference: a hook installed from
bedwars.lua charges a Luraph VM re-entry to EVERY namecall in the game, and the item shop
issues tens of thousands of them per Roact render -- enough to take the client down when
the shop opens. Registering here costs one hash lookup on the hot path instead. ]]
function namecallGuard.watch(inst, method, handler)
    if typeof(inst) ~= 'Instance' or type(method) ~= 'string' then return false end
    local entry = namecallWatch[inst]
    if not entry then
        entry = {}
        namecallWatch[inst] = entry
    end
    entry[method] = handler or true
    return true
end

--[[ Marks that the __namecall body below understands a table return as replacement arguments.
bedwars.lua and this file both ship from the repo and are cached independently,
so the two genuinely can run out of step. Against a guard that predates the contract a
returned table reads as plain truthy -- i.e. "swallow" -- so the call the handler meant to
adjust is eaten instead, and the module looks broken rather than absent. Modules test this
before registering a rewriting handler. ]]
namecallGuard.rewrites = true

function namecallGuard.block(inst, method)
    return namecallGuard.watch(inst, method, true)
end

function namecallGuard.unwatch(inst, method)
    local entry = inst and namecallWatch[inst]
    if not entry then return end
    if method then
        entry[method] = nil
        if next(entry) == nil then
            namecallWatch[inst] = nil
        end
    else
        namecallWatch[inst] = nil
    end
end

function namecallGuard.unwatchIf(inst, method, handler)
    local entry = inst and namecallWatch[inst]
    if not entry or entry[method] ~= handler then return false end
    namecallGuard.unwatch(inst, method)
    return true
end

-- Observers never change the result of a watched call. They are separate from the
-- replacement/block table so a diagnostic listener can coexist with a module that
-- rewrites or suppresses the same remote.
function namecallGuard.observe(inst, method, handler)
    if typeof(inst) ~= 'Instance' or type(method) ~= 'string' or type(handler) ~= 'function' then
        return nil
    end
    local byMethod = namecallObservers[inst]
    if not byMethod then
        byMethod = {}
        namecallObservers[inst] = byMethod
    end
    local observers = byMethod[method]
    if not observers then
        observers = {}
        byMethod[method] = observers
    end
    local token = {instance = inst, method = method, handler = handler}
    table.insert(observers, token)
    return token
end

function namecallGuard.unobserve(token)
    if type(token) ~= 'table' then return false end
    local byMethod = namecallObservers[token.instance]
    local observers = byMethod and byMethod[token.method]
    if not observers then return false end
    for index = #observers, 1, -1 do
        if observers[index] == token then
            table.remove(observers, index)
            if #observers == 0 then
                byMethod[token.method] = nil
            end
            if next(byMethod) == nil then
                namecallObservers[token.instance] = nil
            end
            return true
        end
    end
    return false
end

local getnamecallmethod = getnamecallmethod
local mt = getrawmetatable(game)
setreadonly(mt, false)
--[[
	Chain to the FIRST original, never to whatever is installed right now.

	This file is re-executed on every injection, and a reinject in the same server is an
	ordinary thing to do -- the Reinject button, Reset current profile, and the config sync all
	go back through the loader. Reading mt.__namecall straight into oldNamecall meant the new
	hook wrapped the previous hook, which wrapped the one before it: three reinjects and every
	namecall in the game -- the tens of thousands Roact issues per item-shop render included --
	walked three nested Lua closures, with only the newest one's watch table doing anything.
	The stack never came back down, because nothing here restores the metamethod.

	shared is per-session (it does not survive a teleport, and a teleport gives us a fresh
	metatable anyway), so it holds exactly the right thing: the untouched original from the
	first injection of this session. Later injections replace the live hook instead of stacking
	on it, and the chain stays one deep however many times the script is reloaded.
]]
local previousNamecallHook = shared.CatvapeNamecallHook
local oldNamecall = mt.__namecall
if previousNamecallHook and oldNamecall == previousNamecallHook and shared.CatvapeOldNamecall then
    oldNamecall = shared.CatvapeOldNamecall
end
shared.CatvapeOldNamecall = oldNamecall
local namecallHook = function(self, ...)
    local method = getnamecallmethod()
    if method == "GetPrimaryPartCFrame" and self and self:IsA("Model") then
        local pp = self.PrimaryPart
            or self:FindFirstChild("HumanoidRootPart")
            or self:FindFirstChildWhichIsA("BasePart")
        if pp then
            return pp.CFrame
        else
            return CFrame.new()
        end
    end
    local observerMethods = namecallObservers[self]
    local observers = observerMethods and observerMethods[method]
    if observers then
        for _, token in observers do
            pcall(token.handler, self, ...)
        end
    end

    local entry = namecallWatch[self]
    if entry then
        local handler = entry[method]
        if handler == true then
            return
        elseif handler then
            local ok, result = pcall(handler, self, ...)
            --[[ Any truthy non-table result swallows the call, as it always did. ]]
            if ok and result ~= nil and result ~= false and type(result) ~= 'table' then
                return
            end
            local replacement = (ok and type(result) == 'table') and result or nil

            --[[ Forward as a NAMECALL wherever that is still correct, because the
            index-and-call path below is observably different from the outside. It
            turns one `remote:FireServer(x)` into an __index plus a direct call, so
            anything instrumenting the method itself -- a remote spy, another
            executor hook -- sees the call a second time and reports the remote as
            firing twice. Only ever one packet reached the server, but the duplicate
            is indistinguishable from a real double-send when you are debugging one,
            and SwordHit is watched for rate limiting, so every sword swing hit it.

            The concern remains, but it is narrower than it looks:
            getnamecallmethod() reports the LAST namecall made on this thread, so if
            the handler made namecalls of its own, oldNamecall would dispatch off
            whatever it touched last. That is testable rather than assumed -- re-read
            it and compare. Unchanged means no handler namecall clobbered it and
            oldNamecall dispatches exactly what we entered with. ]]
            if not replacement and getnamecallmethod() == method then
                return oldNamecall(self, ...)
            end

            --[[ Fallback for the two cases the above cannot cover: a handler that
            rewrote the arguments (oldNamecall would forward the originals), and a
            handler whose own namecalls moved getnamecallmethod() out from under us.
            Indexing the method off self carries it with the value and cannot be
            clobbered, at the cost of the duplicate observation described above. ]]
            local fn = self[method]
            if type(fn) == 'function' then
                if replacement then
                    return fn(self, table.unpack(replacement, 1, replacement.n or #replacement))
                end
                return fn(self, ...)
            end
        end
    end
    return oldNamecall(self, ...)
end
mt.__namecall = namecallHook
shared.CatvapeNamecallHook = namecallHook
setreadonly(mt, true)

vape:Clean(function()
    table.clear(namecallWatch)
    table.clear(namecallObservers)
    if mt.__namecall == namecallHook then
        setreadonly(mt, false)
        mt.__namecall = oldNamecall
        setreadonly(mt, true)
    end
    if shared.CatvapeNamecallHook == namecallHook then
        shared.CatvapeNamecallHook = nil
    end
    if shared.CatvapeOldNamecall == oldNamecall then
        shared.CatvapeOldNamecall = nil
    end
end)
end

local blankFunction = function(...) return ... end

do
local fpsHooks = {}
do
    local scopes = {}

    local function removeScope(scope)
        for i = #scopes, 1, -1 do
            if scopes[i] == scope then
                table.remove(scopes, i)
                return
            end
        end
    end

    local function newScope()
        local scope = {
            active = true,
            connections = {},
            watches = {},
            patches = {},
            properties = {},
            finalizers = {},
            restoreProperties = true
        }

        function scope:isActive()
            return self.active
        end

        function scope:connect(connection)
            if not self.active then
                pcall(function() connection:Disconnect() end)
                return connection
            end
            table.insert(self.connections, connection)
            return connection
        end

        function scope:watch(instance, method, handler)
            if not self.active then return false end
            local previous = namecallWatch[instance] and namecallWatch[instance][method]
            if not namecallGuard.watch(instance, method, handler) then return false end
            table.insert(self.watches, {
                instance = instance,
                method = method,
                handler = handler,
                previous = previous
            })
            return true
        end

        function scope:patchFunction(target, key, replacement)
            if not self.active or type(target) ~= 'table' or type(replacement) ~= 'function' then
                return false
            end
            local hadOwnValue = rawget(target, key) ~= nil
            local original = target[key]
            if type(original) ~= 'function' then return false end
            local ok = pcall(function()
                target[key] = replacement
            end)
            if not ok then return false end
            table.insert(self.patches, {
                target = target,
                key = key,
                original = original,
                hadOwnValue = hadOwnValue,
                replacement = replacement
            })
            return true
        end

        function scope:remember(instance, property)
            if not self.active or not instance then return false end
            local record = self.properties[instance]
            if not record then
                record = {values = {}, seen = {}}
                self.properties[instance] = record
            end
            if record.seen[property] then return true end
            local ok, value = pcall(function()
                return instance[property]
            end)
            if not ok then return false end
            record.seen[property] = true
            record.values[property] = value
            return true
        end

        function scope:set(instance, property, value)
            if self.restoreProperties and not self:remember(instance, property) then return false end
            return pcall(function()
                instance[property] = value
            end)
        end

        function scope:onStop(callback)
            if type(callback) == 'function' then
                table.insert(self.finalizers, callback)
            end
        end

        function scope:stop()
            if not self.active then return end
            self.active = false

            for i = #self.connections, 1, -1 do
                pcall(function() self.connections[i]:Disconnect() end)
            end

            for i = #self.watches, 1, -1 do
                local watch = self.watches[i]
                local entry = namecallWatch[watch.instance]
                if entry and entry[watch.method] == watch.handler then
                    if watch.previous ~= nil then
                        entry[watch.method] = watch.previous
                    else
                        namecallGuard.unwatch(watch.instance, watch.method)
                    end
                end
            end

            for i = #self.patches, 1, -1 do
                local patch = self.patches[i]
                pcall(function()
                    if patch.target[patch.key] == patch.replacement then
                        patch.target[patch.key] = patch.hadOwnValue and patch.original or nil
                    end
                end)
            end

            for instance, record in next, self.properties do
                for property, value in next, record.values do
                    pcall(function()
                        instance[property] = value
                    end)
                end
                table.clear(record.values)
                table.clear(record.seen)
            end

            for i = #self.finalizers, 1, -1 do
                pcall(self.finalizers[i])
            end

            table.clear(self.connections)
            table.clear(self.watches)
            table.clear(self.patches)
            table.clear(self.properties)
            table.clear(self.finalizers)
            removeScope(self)
        end

        table.insert(scopes, scope)
        return scope
    end

    local function destroyChildren(container, active)
        if not container then return 0 end
        local removed = 0
        local clock = os.clock()
        for _, child in next, (container:GetChildren()) do
            if active and not active() then break end
            pcall(function()
                child:Destroy()
                removed += 1
            end)
            if os.clock() - clock > 0.004 then
                task.wait()
                clock = os.clock()
            end
        end
        return removed
    end

    function fpsHooks.newScope()
        return newScope()
    end

    function fpsHooks.disableClientApply(scope, client)
        if not scope or not scope:isActive() or type(client) ~= 'table' then
            return false
        end
        return scope:patchFunction(client, 'apply', function() end)
    end

    local cleanAssetScope
    local cleanAssetResult

    function fpsHooks.cleanAssets(options)
        options = options or {}
        if cleanAssetScope and cleanAssetScope:isActive() then
            return cleanAssetResult
        end

        local scope = newScope()
        local result = {
            lobbyBoards = 0,
            clientApply = false,
            packetProfiler = false,
            lockerPreview = 0
        }

        if options.clearLobbyBoards then
            local lobby = workspace:FindFirstChild('Lobby')
            local boards = lobby and lobby:FindFirstChild('Boards')
            result.lobbyBoards = destroyChildren(boards, function() return scope:isActive() end)
        end

        if options.disableClientApply then
            result.clientApply = fpsHooks.disableClientApply(scope, options.client)
        end

        if options.removePacketProfiler then
            local playerScripts = lplr and lplr:FindFirstChild('PlayerScripts')
            local profiler = playerScripts and playerScripts:FindFirstChild('packetprofiler')
            local canRemove = true
            local rankOk, rank = pcall(function()
                return lplr:GetRankInGroup(5774246)
            end)
            if not rankOk or rank >= 121 then
                canRemove = false
            end
            if profiler and canRemove then
                pcall(function() profiler:Destroy() end)
                result.packetProfiler = true
            end
        end

        if options.removeLockerPreview then
            local preview = workspace:FindFirstChild('LockerPreview')
            for _, child in next, (workspace:GetChildren()) do
                if child:IsA('Model') and child.Name:find('_LockerPreviewClone$')
                    and (not preview or not child:IsDescendantOf(preview)) then
                    pcall(function()
                        child:Destroy()
                        result.lockerPreview += 1
                    end)
                end
            end
        end

        cleanAssetScope = scope
        cleanAssetResult = result
        return result
    end

    function fpsHooks.startNativeCore(options)
        options = options or {}
        local scope = newScope()
        scope.restoreProperties = options.restoreProperties ~= false
        local renderFidelitySeen = setmetatable({}, {__mode = 'k'})
        local renderFidelityOriginal = setmetatable({}, {__mode = 'k'})

        local function applyRenderFidelity(instance)
            if not options.renderFidelity then return end
            local isMesh = false
            pcall(function()
                isMesh = instance:IsA('MeshPart')
            end)
            if not isMesh then return end
            if not renderFidelitySeen[instance] then
                renderFidelitySeen[instance] = true
                local ok, original = pcall(function() return instance.RenderFidelity end)
                if not ok then return end
                renderFidelityOriginal[instance] = original
            end
            pcall(function()
                instance.RenderFidelity = Enum.RenderFidelity.Performance
            end)
        end

        scope:onStop(function()
            for instance, original in next, renderFidelityOriginal do
                pcall(function() instance.RenderFidelity = original end)
                renderFidelityOriginal[instance] = nil
            end
            table.clear(renderFidelitySeen)
        end)
        local map = workspace:FindFirstChild('Map')
        local camera = workspace.CurrentCamera or gameCamera
        local canEnable = {
            ParticleEmitter = true,
            Smoke = true,
            Fire = true,
            Sparkles = true,
            PostEffect = true,
            SpotLight = true
        }

        local function shouldProcess(instance)
            if not scope:isActive() then return false end
            if camera and instance:IsDescendantOf(camera) then
                local viewmodel = camera:FindFirstChild('Viewmodel')
                if not (viewmodel and instance:IsDescendantOf(viewmodel)) then
                    return false
                end
            end
            local character = lplr.Character
            if not options.cleanSelf and character and instance:IsDescendantOf(character) then
                return false
            end
            if not options.cleanModels and not instance:FindFirstAncestorWhichIsA('Model') then
                return false
            end
            return true
        end

        local function process(instance)
            if not shouldProcess(instance) then return end
            local blockCheck = options.simpleBlocks or not map or not instance:IsDescendantOf(map)

            if instance:IsA('FaceInstance') and blockCheck then
                scope:set(instance, 'Transparency', 1)
                pcall(function() scope:set(instance, 'Shiny', 0) end)
            end

            if options.noImages and (instance:IsA('ImageLabel') or instance:IsA('ImageButton')) then
                scope:set(instance, 'Image', 'rbxassetid://0')
            end

            if options.noAccessories and instance:IsA('Clothing') then
                scope:set(instance, 'Parent', nil)
            end

            if instance:IsA('Explosion') then
                scope:set(instance, 'BlastPressure', 1)
                scope:set(instance, 'BlastRadius', 1)
                scope:set(instance, 'Visible', false)
            end

            if instance:IsA('BasePart') then
                if blockCheck then
                    scope:set(instance, 'Material', Enum.Material.SmoothPlastic)
                end
                scope:set(instance, 'Reflectance', 0)
                if options.beta then
                    scope:set(instance, 'CastShadow', false)
                end
            end

            applyRenderFidelity(instance)

            if instance:IsA('MeshPart') or instance:IsA('Union') then
                scope:set(instance, 'DoubleSided', false)
            end

            if instance:IsA('ParticleEmitter') then
                scope:set(instance, 'Enabled', false)
                scope:set(instance, 'Lifetime', NumberRange.new(0))
            elseif canEnable[instance.ClassName] then
                scope:set(instance, 'Enabled', false)
            end
        end

        task.spawn(function()
            local clock = os.clock()
            for _, instance in next, (workspace:GetDescendants()) do
                if not scope:isActive() then return end
                pcall(process, instance)
                if os.clock() - clock > 0.004 then
                    task.wait()
                    clock = os.clock()
                end
            end

            if options.simpleBlocks and scope:isActive() then
                for _, block in next, (svc.collectionService:GetTagged('block')) do
                    for _, child in next, (block:GetChildren()) do
                        if child:IsA('Texture') then
                            scope:set(child, 'Texture', 'rbxassetid://0')
                            scope:set(child, 'Transparency', 1)
                        end
                    end
                end
            end

            if options.connectWorkspace and scope:isActive() then
                scope:connect(workspace.DescendantAdded:Connect(function(instance)
                    if scope:isActive() then
                        task.defer(function()
                            pcall(process, instance)
                        end)
                    end
                end))
            end

            local terrain = workspace:FindFirstChildWhichIsA('Terrain')
            if terrain and scope:isActive() then
                scope:set(terrain, 'WaterWaveSize', 0)
                scope:set(terrain, 'WaterWaveSpeed', 0)
                scope:set(terrain, 'WaterReflectance', 0)
                scope:set(terrain, 'WaterTransparency', 0)
            end

            if options.simpleLighting and scope:isActive() then
                scope:set(svc.lightingService, 'GlobalShadows', false)
                scope:set(svc.lightingService, 'FogEnd', 9e9)
            end

            if options.beta and scope:isActive() then
                local settingsObject
                pcall(function()
                    if typeof(settings) == 'Instance' then
                        settingsObject = settings
                    elseif type(settings) == 'function' then
                        settingsObject = settings()
                    end
                end)
                if settingsObject then
                    local physics
                    local rendering
                    pcall(function() physics = settingsObject.Physics end)
                    pcall(function() rendering = settingsObject.Rendering end)
                    if physics then
                        scope:set(physics, 'AllowSleep', true)
                        pcall(function()
                            scope:set(physics, 'PhysicsEnvironmentalThrottle', Enum.EnviromentalPhysicsThrottle.Skip2)
                        end)
                    end
                    if rendering then
                        scope:set(rendering, 'EagerBulkExecution', false)
                        pcall(function()
                            scope:set(rendering, 'QualityLevel', Enum.QualityLevel.Level01)
                            scope:set(rendering, 'EditQualityLevel', Enum.QualityLevel.Level01)
                            scope:set(rendering, 'ViewMode', Enum.ViewMode.None)
                            scope:set(rendering, 'EnableFRM', true)
                            scope:set(rendering, 'AutoFRMLevel', 1)
                            scope:set(rendering, 'ShowBoundingBoxes', false)
                            scope:set(rendering, 'RenderCSGTrianglesDebug', false)
                            scope:set(rendering, 'ReloadAssets', false)
                        end)
                    end
                end
            end

        end)

        return scope
    end

    function fpsHooks.startConnectionCleaner(disabledNames)
        local scope = newScope()
        local disabled = {}
        local blocked = {}
        for _, name in next, (disabledNames or {}) do
            blocked[name:gsub('-', '_')] = true
        end

        scope:onStop(function()
            for _, connection in next, disabled do
                pcall(function() connection:Enable() end)
            end
            table.clear(disabled)
        end)

        task.spawn(function()
            if type(getconnections) ~= 'function' then return end
            for _, eventName in {'Heartbeat', 'Stepped', 'RenderStepped'} do
                if not scope:isActive() then return end
                local event = svc.runService[eventName]
                local ok, connections = pcall(getconnections, event)
                if ok and connections then
                    local checked = 0
                    for _, connection in next, connections do
                        if not scope:isActive() then return end
                        local fn = connection.Function
                        if type(fn) == 'function' then
                            local source
                            pcall(function() source = debug.getinfo(fn).source end)
                            if type(source) == 'string' then
                                source = source:gsub('-', '_')
                                for name in next, blocked do
                                    if source:find(name) then
                                        pcall(function() connection:Disable() end)
                                        table.insert(disabled, connection)
                                        break
                                    end
                                end
                            end
                        end
                        checked += 1
                        if checked % 50 == 0 then task.wait() end
                    end
                end
            end
        end)

        return scope
    end

    function fpsHooks.startBlockDemesh(blockController, whitelist)
        local scope = newScope()
        whitelist = whitelist or {}
        scope:onStop(function()
            pcall(function() blockController:remesh() end)
        end)
        task.spawn(function()
            local clock = os.clock()
            for _, block in next, (svc.collectionService:GetTagged('block')) do
                if not scope:isActive() then return end
                pcall(function()
                    if block:GetAttribute('PlacedByUserId') == 0 and not whitelist[block.Name] then
                        block:ClearAllChildren()
                        block.Material = Enum.Material.SmoothPlastic
                        block.Transparency = 0
                        block.BrickColor = BrickColor.new(2)
                        block.Color = Color3.new(0.3, 0.3, 0.3)
                    end
                end)
                if os.clock() - clock > 0.004 then
                    task.wait()
                    clock = os.clock()
                end
            end
            pcall(function() blockController:remesh() end)
        end)
        return scope
    end

    function fpsHooks.startVisualModuleBlocker(options)
        options = options or {}
        local scope = newScope()

        local function noopCleanup()
            return {
                DoCleaning = function() end,
                Destroy = function() end,
                Disconnect = function() end,
                GiveTask = function(self) return self end
            }
        end

        local function setIgnored(instance, includeQuery)
            if typeof(instance) ~= 'Instance' or not instance:IsA('BasePart') then return end
            local queryUtil = options.queryUtil
            if type(queryUtil) == 'table' and type(queryUtil.setQueryIgnored) == 'function' then
                pcall(queryUtil.setQueryIgnored, queryUtil, instance, true)
            end
            pcall(function() instance.CanCollide = false end)
            if includeQuery then
                pcall(function() instance.CanQuery = false end)
            end
        end

        local function setEnabled(instance, value)
            if typeof(instance) ~= 'Instance' then return end
            if not (instance:IsA('ParticleEmitter')
                or instance:IsA('Beam')
                or instance:IsA('Trail')
                or instance:IsA('Light')) then
                return
            end
            scope:set(instance, 'Enabled', value)
        end

        local function protectedRoot(instance, entity)
            if typeof(instance) ~= 'Instance' then return true end
            if typeof(entity) == 'Instance' then
                local character = lplr and lplr.Character
                if character and (entity == character or entity:IsDescendantOf(character)) then
                    return true
                end
            end

            local map = workspace:FindFirstChild('Map')
            local camera = workspace.CurrentCamera or gameCamera
            local playerGui = lplr and lplr:FindFirstChildOfClass('PlayerGui')
            if (map and instance:IsDescendantOf(map))
                or (camera and instance:IsDescendantOf(camera))
                or (playerGui and instance:IsDescendantOf(playerGui))
                or (svc.coreGui and instance:IsDescendantOf(svc.coreGui))
                or instance:IsDescendantOf(svc.replicatedStorage) then
                return true
            end

            local current = instance
            while current do
                if current:IsA('BasePart') and current.CanCollide then
                    return true
                end
                if current:IsA('Model') and current:FindFirstChildOfClass('Humanoid') then
                    return true
                end
                if current:IsA('ScreenGui') then
                    return true
                end
                local name = string.lower(current.Name)
                if name:find('projectile', 1, true)
                    or name:find('shield', 1, true)
                    or name:find('ability', 1, true)
                    or name:find('win_effect', 1, true)
                    or name:find('win-effect', 1, true)
                    or name:find('wineffect', 1, true) then
                    return true
                end
                current = current.Parent
            end

            local ok, descendants = pcall(function()
                return instance:GetDescendants()
            end)
            if ok and descendants then
                for _, descendant in next, descendants do
                    if descendant:IsA('BasePart') and descendant.CanCollide then
                        return true
                    end
                end
            end
            return false
        end

        local function suppress(instance, includeQuery, processParts)
            if typeof(instance) ~= 'Instance' then return end
            local function process(candidate)
                if not scope:isActive() then return end
                if candidate:IsA('BasePart') then
                    if processParts ~= false then
                        setIgnored(candidate, includeQuery)
                    end
                else
                    setEnabled(candidate, false)
                end
            end
            pcall(process, instance)
            local ok, descendants = pcall(function() return instance:GetDescendants() end)
            if ok and descendants then
                for _, descendant in next, descendants do
                    if not scope:isActive() then return end
                    pcall(process, descendant)
                end
            end
        end

        local function blockEffect(original, self, instance, entity, config)
            if protectedRoot(instance, entity) then
                return original(self, instance, entity, config)
            end
            suppress(instance, false)
        end

        local function blockInstanceEffect(original, self, instance, config)
            if protectedRoot(instance) then
                return original(self, instance, config)
            end
            suppress(instance, true)
        end

        local effectUtil = options.effectUtil
        if type(effectUtil) == 'table' then
            local originalPlayEffect = effectUtil.playEffect
            if type(originalPlayEffect) == 'function' then
                scope:patchFunction(effectUtil, 'playEffect', function(self, instance, entity, config)
                    return blockEffect(originalPlayEffect, self, instance, entity, config)
                end)
            end
            local originalPlayInstanceEffect = effectUtil.playInstanceEffect
            if type(originalPlayInstanceEffect) == 'function' then
                scope:patchFunction(effectUtil, 'playInstanceEffect', function(self, instance, config)
                    return blockInstanceEffect(originalPlayInstanceEffect, self, instance, config)
                end)
            end
            local originalEnableInstanceEffect = effectUtil.enableInstanceEffect
            if type(originalEnableInstanceEffect) == 'function' then
                scope:patchFunction(effectUtil, 'enableInstanceEffect', function(self, instance)
                    if protectedRoot(instance) then
                        return originalEnableInstanceEffect(self, instance)
                    end
                    suppress(instance, false, false)
                    return noopCleanup()
                end)
            end
        end

        return scope
    end

    vape:Clean(function()
        for i = #scopes, 1, -1 do
            scopes[i]:stop()
        end
        table.clear(scopes)
        cleanAssetScope = nil
        cleanAssetResult = nil
    end)
end
end

do
local RunLoops = {RenderStepTable = {}, StepTable = {}, HeartTable = {}}
local vapeConnections = {}

--[[ Nothing used to disconnect either table on uninject. A run loop left bound kept running
into the next injection, and bedwars.lua's vapeConnections (lplr attribute and death handlers)
gained another live copy every reinject. ]]
vape:Clean(function()
    for _, loops in {RunLoops.RenderStepTable, RunLoops.StepTable, RunLoops.HeartTable} do
        for name, connection in loops do
            pcall(function() connection:Disconnect() end)
            loops[name] = nil
        end
    end
    for index, connection in vapeConnections do
        pcall(function() connection:Disconnect() end)
        vapeConnections[index] = nil
    end
end)
end

function RunLoops:BindToRenderStep(name, func)
    if RunLoops.RenderStepTable[name] == nil then
        RunLoops.RenderStepTable[name] = svc.runService.RenderStepped:Connect(func)
    end
end

function RunLoops:UnbindFromRenderStep(name)
    if RunLoops.RenderStepTable[name] then
        RunLoops.RenderStepTable[name]:Disconnect()
        RunLoops.RenderStepTable[name] = nil
    end
end

function RunLoops:BindToStepped(name, func)
    if RunLoops.StepTable[name] == nil then
        RunLoops.StepTable[name] = svc.runService.Stepped:Connect(func)
    end
end

function RunLoops:UnbindFromStepped(name)
    if RunLoops.StepTable[name] then
        RunLoops.StepTable[name]:Disconnect()
        RunLoops.StepTable[name] = nil
    end
end

function RunLoops:BindToHeartbeat(name, func)
    if RunLoops.HeartTable[name] == nil then
        RunLoops.HeartTable[name] = svc.runService.Heartbeat:Connect(func)
    end
end

function RunLoops:UnbindFromHeartbeat(name)
    if RunLoops.HeartTable[name] then
        RunLoops.HeartTable[name]:Disconnect()
        RunLoops.HeartTable[name] = nil
    end
end

--[[ Substring match of an instance name against a TextList's switched-on entries.

Reads ListEnabled, not Objects. Objects holds the list window's row BUTTONS, and
every one of them has Text = '' (the visible text lives on a child TextLabel) and
the default Name 'TextButton' -- so the old version compared every name against
the literal string "textbutton" and matched nothing, ever. Objects is also the
wrong set even when read correctly: it holds every entry, including the ones the
user switched off. ListEnabled is the enabled subset and is what the rest of the
script reads.

Plain-text find, since item names carry '-' and '(' which read as pattern syntax
and would either mis-match or throw. ]]
do
local function entryMatches(objName, list)
    if type(objName) ~= "string" or type(list) ~= "table" then return false end
    --[[ A bare array of strings is accepted too, so callers can pass List.ListEnabled. ]]
    local entries = list.ListEnabled or list.List or list
    if type(entries) ~= "table" then return false end
    local lowerName = objName:lower()
    for _, entry in pairs(entries) do
        if type(entry) == "string" then
            local nameString = entry:lower():gsub("^%s*(.-)%s*$", "%1")
            if nameString ~= "" and lowerName:find(nameString, 1, true) then
                return true
            end
        end
    end
    return false
end
end

--[[ The `out` barrel re-exports sound-manager, but each of its re-exports is guarded by
`or {}`, so a build where that submodule fails to resolve silently drops the key and
leaves SoundManager nil -- which is how "attempt to index nil with 'playSound'" reached
both SoundChanger and the projectile launch sound. Handing back a stand-in instead of nil
is what fixes that: a dozen call sites across both files index this directly and none of
them are worth taking down over a missing sound effect.

The current game has no SoundManager at all -- everything plays through AudioManager
(playAudio(asset, config)) -- and while the stand-in was a stub of no-ops, every sound
the script played itself was silent: its own projectile launches, pickups, purchases,
the miner's hammer. So playSound now forwards to AudioManager:playAudio. The props the
call sites pass (position, volumeMultiplier) are AudioManager config keys already, and a
registered GameSound brings its own category and volume. It is pcall'd so a bad id still
costs nothing but the sound.

routesToAudioManager tells SoundChanger these already reach its AudioManager hook, so it
leaves playSound alone rather than scaling them twice. Every other method is still a
no-op, and without an AudioManager this is the plain stub. ]]
local function resolveSoundManager()
    local ok, res = pcall(function()
        return require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).SoundManager
    end)
    if ok and res then return res end

    local stub = setmetatable({}, {__index = function() return blankFunction end})
    local audioOk, audio = pcall(function()
        return require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).AudioManager
    end)
    if not (audioOk and type(audio) == 'table' and type(audio.playAudio) == 'function') then
        return stub
    end

    stub.routesToAudioManager = true
    function stub:playSound(id, props)
        if type(id) ~= 'string' or id == '' then return nil end
        local config = {}
        if type(props) == 'table' then
            for key, value in props do
                config[key] = value
            end
        end
        local played, handle = pcall(audio.playAudio, audio, id, config)
        return played and handle or nil
    end
    return stub
end

--[[ catvape funcs ]]

do
if shared.VapeSmoothBoot then task.wait() end
callWithThreadFix(function()
	local Knit = require(
		svc.replicatedStorage.rbxts_include.node_modules['@easy-games'].knit.src.Knit.KnitClient
	)
	assert(type(Knit) == 'table', 'KnitClient returned no controller table')
	local knitDeadline = os.clock() + 60
	assert(type(Knit.OnStart) == 'function', 'Knit.OnStart is unavailable')
	local knitStarted = false
	local knitStartError
	local startup = Knit.OnStart()
	assert(startup and type(startup.andThen) == 'function',
		'Knit.OnStart returned no startup promise')
	local observer = startup:andThen(function()
		knitStarted = true
	end, function(err)
		knitStartError = tostring(err)
	end)
	local function stopObserving()
		if observer and type(observer.cancel) == 'function' then
			pcall(function() observer:cancel() end)
		end
	end
	while true do
		if vape.Loaded == nil then
			stopObserving()
			error('Knit initialization canceled by unload', 0)
		end
		if knitStartError then
			stopObserving()
			error('Knit startup failed: '..knitStartError, 0)
		end
		local controllers = Knit.Controllers
		if knitStarted and type(controllers) == 'table'
			and controllers.SwordController
			and controllers.ProjectileController
			and controllers.BlockBreakController
			and controllers.MatchController
			and controllers.ItemDropController then
			break
		end
		if os.clock() >= knitDeadline then
			stopObserving()
			error('Knit startup and controllers did not become ready within 60s', 0)
		end
		task.wait(0.1)
	end

	local BowConstantsTable
	for i = 1, 32 do
		local ok, value = pcall(debug.getupvalue, Knit.Controllers.ProjectileController.enableBeam, i)
		if not ok then break end
		if type(value) == 'table' and type(rawget(value, 'RelX')) == 'number' then
			BowConstantsTable = value
			break
		end
	end
	BowConstantsTable = BowConstantsTable or {
		BeamGrowthMultiplier = 0.08,
		CameraMultiplier = 10,
		RelX = 0.8,
		RelY = -0.6,
		RelZ = 0,
		YTargetOffset = 0.05
	}

	local Flamework = require(svc.replicatedStorage['rbxts_include']['node_modules']['@flamework'].core.out).Flamework
	local InventoryUtil = require(svc.replicatedStorage.TS.inventory['inventory-util']).InventoryUtil
	local Client = require(svc.replicatedStorage.TS.remotes).default.Client
	local EffectUtil = require(svc.replicatedStorage.TS.util.effect['effect-util']).EffectUtil
	local OldGet, OldBreak = Client.Get

	bedwars = setmetatable({
		AbilityController = Flamework.resolveDependency('@easy-games/game-core:client/controllers/ability/ability-controller@AbilityController'),
		AdetundeUpgradeMeta = require(svc.replicatedStorage.TS.games.bedwars.items['frosty-hammer']['frosty-hammer-upgrades']).FrostyHammerUpgradeMeta,
		AdetundeUtil = require(svc.replicatedStorage.TS.games.bedwars.items['frosty-hammer']['frosty-hammer-util']).FrostyHammerUtil,
		AnimationType = require(svc.replicatedStorage.TS.animation['animation-type']).AnimationType,
		AnimationUtil = require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out['shared'].util['animation-util']).AnimationUtil,
		AppController = require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.client.controllers['app-controller']).AppController,
		BedBreakEffectMeta = require(svc.replicatedStorage.TS.locker['bed-break-effect']['bed-break-effect-meta']).BedBreakEffectMeta,
		BedwarsKitMeta = require(svc.replicatedStorage.TS.games.bedwars.kit['bedwars-kit-meta']).BedwarsKitMeta,
		BlackMarketeerBalance = require(svc.replicatedStorage.TS.balance['black-marketeer-balance']).BlackMarketeerBalance,
		BuilderUtil = require(svc.replicatedStorage.TS.games.bedwars.kit.kits.builder['builder-util']).BuilderUtil,
		JuggernautUtil = require(svc.replicatedStorage.TS.balance['juggernaut-balance-file']).JuggernautUtil,
		BlockBreaker = Knit.Controllers.BlockBreakController.blockBreaker,
		BlockController = require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out).BlockEngine,
		BlockEngine = require(lplr.PlayerScripts.TS.lib['block-engine']['client-block-engine']).ClientBlockEngine,
		BlockPlacer = require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.client.placement['block-placer']).BlockPlacer,
		BowConstantsTable = BowConstantsTable,
		ClickHold = require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.client.ui.lib.util['click-hold']).ClickHold,
		Client = Client,
		ClientSyncEvents = require(lplr.PlayerScripts.TS['client-sync-events']).ClientSyncEvents,
		ClientConstructor = require(svc.replicatedStorage['rbxts_include']['node_modules']['@rbxts'].net.out.client),
		ClientDamageBlock = require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.shared.remotes).BlockEngineRemotes.Client,
		CombatConstant = require(svc.replicatedStorage.TS.combat['combat-constant']).CombatConstant,
		DamageIndicator = Knit.Controllers.DamageIndicatorController.spawnDamageIndicator,
		DefaultKillEffect = require(lplr.PlayerScripts.TS.controllers.global.locker["kill-effect"].effects['default-kill-effect']),
		EffectUtil = EffectUtil,
		EmoteType = require(svc.replicatedStorage.TS.locker.emote['emote-type']).EmoteType,
		EnchantMeta = require(svc.replicatedStorage.TS.enchant['enchant-meta']).EnchantMeta,
		GameAnimationUtil = require(svc.replicatedStorage.TS.animation['animation-util']).GameAnimationUtil,
		getIcon = function(item, showinv)
			local itemmeta = bedwars.ItemMeta[item.itemType]
			return itemmeta and showinv and itemmeta.image or ''
		end,
		getInventory = function(plr)
			local suc, res = pcall(function()
				return InventoryUtil.getInventory(plr)
			end)
			return suc and res or {
				items = {},
				armor = {}
			}
		end,
		HudAliveCount = require(lplr.PlayerScripts.TS.controllers.global['top-bar'].ui.game['hud-alive-player-counts']).HudAlivePlayerCounts,
		ItemMeta = require(svc.replicatedStorage.TS.item['item-meta']).items,
		-- Wanted by SkinChanger. Paths taken from where the game's own controllers import
		-- them (armor-item-skin-util for the meta, battle-pass-rewards for the id table).
		ItemSkinType = require(svc.replicatedStorage.TS.games.bedwars['item-skin']['item-skin-types']).ItemSkinType,
		BedwarsKitSkin = require(svc.replicatedStorage.TS.games.bedwars['kit-skin']['bedwars-kit-skin']).BedwarsKitSkin,
		BedwarsKitSkinMeta = require(svc.replicatedStorage.TS.games.bedwars['kit-skin']['bedwars-kit-skin-meta']).BedwarsKitSkinMeta,
		getItemSkinMeta = require(svc.replicatedStorage.TS.games.bedwars['item-skin']['item-skin-meta']).getItemSkinMeta,
		KillEffectMeta = require(svc.replicatedStorage.TS.locker['kill-effect']['kill-effect-meta']).KillEffectMeta,
		KillFeedController = Flamework.resolveDependency('client/controllers/game/kill-feed/kill-feed-controller@KillFeedController'),
		Knit = Knit,
		KnockbackUtil = require(svc.replicatedStorage.TS.damage['knockback-util']).KnockbackUtil,
		-- Wanted by the ported kit modules, and by nothing else in this file yet. Paths taken
		-- from where the game's own controllers import them.
		AudioManager = require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).AudioManager,
		BalanceFile = require(svc.replicatedStorage.TS.balance['balance-file']).BalanceFile,
		FrostyGunMode = require(svc.replicatedStorage.TS.games.bedwars.kit.kits['frosty-gun']['frosty-gun-util']).FrostyGunMode,
		SoulBrokerConstants = require(svc.replicatedStorage.TS.games.bedwars.kit.kits['soul-broker']['soul-broker-constants']).SoulBrokerConstants,
		TaliyahUtil = require(svc.replicatedStorage.TS.games.bedwars.kit.kits.taliyah['taliyah-util']).TaliyahUtil,
		MageKitUtil = require(svc.replicatedStorage.TS.games.bedwars.kit.kits.mage['mage-kit-util']).MageKitUtil,
		NametagController = Knit.Controllers.NametagController,
		PartyController = Flamework.resolveDependency('@easy-games/lobby:client/controllers/party-controller@PartyController'),
		ProjectileMeta = require(svc.replicatedStorage.TS.projectile['projectile-meta']).ProjectileMeta,
		PingController = require(lplr.PlayerScripts.TS.controllers.game.ping["ping-controller"]).PingController,
		QueryUtil = require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).GameQueryUtil,
		QueueCard = require(lplr.PlayerScripts.TS.controllers.global.queue.ui['queue-card']).QueueCard,
		QueueMeta = require(svc.replicatedStorage.TS.game['queue-meta']).QueueMeta,
		Roact = require(svc.replicatedStorage['rbxts_include']['node_modules']['@rbxts']['roact'].src),
		RuntimeLib = require(svc.replicatedStorage['rbxts_include'].RuntimeLib),
		SoundList = require(svc.replicatedStorage.TS.sound['game-sound']).GameSound,
		SoundManager = resolveSoundManager(),
		StatusEffectUtil = require(svc.replicatedStorage.TS['status-effect']['status-effect-util']).StatusEffectUtil,
		StatusEffectMeta = require(svc.replicatedStorage.TS['status-effect']['status-effect-type']).StatusEffectType,
		StatusEffectType = require(svc.replicatedStorage.TS['status-effect']['status-effect-type']).StatusEffectType,
		Store = require(lplr.PlayerScripts.TS.ui.store).ClientStore,
		SummonerKitBalance = require(svc.replicatedStorage.TS.games.bedwars.kit.kits.summoner['summoner-kit-balance']).SummonerKitBalance,
		SwordsConstants = require(svc.replicatedStorage.TS.combat['combat-constant']).SwordsConstants,
		SyncEventPriority = require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['sync-event'].out).SyncEventPriority,
		TeamUpgradeMeta = require(svc.replicatedStorage.TS.games.bedwars['team-upgrade']['team-upgrade-meta']).getTeamUpgradeMetaForQueue(),
		UILayers = require(svc.replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).UILayers,
		VisualizerUtils = require(lplr.PlayerScripts.TS.lib.visualizer['visualizer-utils']).VisualizerUtils,
		WeldTable = require(svc.replicatedStorage.TS.util['weld-util']).WeldUtil,
		WinEffectMeta = require(svc.replicatedStorage.TS.locker['win-effect']['win-effect-meta']).WinEffectMeta,
		ZapNetworking = require(lplr.PlayerScripts.TS.lib.network)
	}, {
		__index = function(self, ind)
			rawset(self, ind, Knit.Controllers[ind])
			return rawget(self, ind)
		end
	})

	assert(type(bedwars.ItemMeta) == 'table', 'item-meta.items is unavailable')
	assert(type(bedwars.TeamUpgradeMeta) == 'table', 'queue team upgrades are unavailable')

	for name, remote in {
		AfkStatus = 'AfkInfo',
		AttackEntity = 'SwordHit',
		BeePickup = 'PickUpBee',
		CannonAim = 'AimCannon',
		CannonLaunch = 'LaunchSelfFromCannon',
		ConsumeBattery = 'ConsumeBattery',
		ConsumeItem = 'ConsumeItem',
		ConsumeSoul = 'ConsumeGrimReaperSoul',
		DepositPinata = 'DepositCoins',
		DragonBreath = 'DragonBreath',
		DragonEndFly = 'VoidDragonEndFlying',
		DragonFly = 'DragonFlap',
		DropItem = 'DropItem',
		EquipItem = 'SetInvItem',
		FireProjectile = 'ProjectileFire',
		GroundHit = 'GroundHit',
		GuitarHeal = 'PlayGuitar',
		HannahKill = 'HannahPromptTrigger',
		HarvestCrop = 'CropHarvest',
		KaliyahPunch = 'PlayerDragonPunched',
		MageSelect = 'LearnElementTome',
		MinerDig = 'DestroyPetrifiedPlayer',
		PickupItem = 'PickupItemDrop',
		PickupMetal = 'CollectCollectableEntity',
		ReportPlayer = 'ReportPlayer',
		ResetCharacter = 'ResetCharacter',
		SpawnRaven = 'SpawnRaven',
		SummonerClawAttack = 'SummonerClawAttackRequest',
		WarlockTarget = 'WarlockLinkTarget'
	} do
		remotes[name] = remote
	end

	OldBreak = bedwars.BlockController.isBlockBreakable

	Client.Get = function(self, remoteName)
		local call = OldGet(self, remoteName)

		if remoteName == remotes.AttackEntity then
			return {
				instance = call.instance,
				SendToServer = function(_, attackTable, ...)
					local suc, plr = pcall(function()
						return svc.playersService:GetPlayerFromCharacter(attackTable.entityInstance)
					end)

					local selfpos = attackTable.validate.selfPosition.value
					local targetpos = attackTable.validate.targetPosition.value
					store.attackReach = ((selfpos - targetpos).Magnitude * 100) // 1 / 100
					store.attackReachUpdate = os.clock() + 1

					if Reach.Enabled or HitBoxes.Enabled then
						attackTable.validate.raycast = attackTable.validate.raycast or {}
						attackTable.validate.selfPosition.value += CFrame.lookAt(selfpos, targetpos).LookVector * math.max((selfpos - targetpos).Magnitude - 14.399, 0)
					end

					if suc and plr then
					end

					return call:SendToServer(attackTable, ...)
				end
			}
		-- TrapDisabler is nil until its own run() block registers it, hundreds of lines below
		-- this one, and stays nil for the session if that block fails (which is exactly what
		-- run() is there to survive). Indexing it then threw on every Client:Get for the trap
		-- remote -- inside the hot path every remote in the game goes through.
		elseif TrapDisabler and TrapDisabler.Enabled and TrapToggles[remoteName] and TrapToggles[remoteName].Enabled then
			return {SendToServer = function() end}
		elseif remoteName == 'SwordSwingMiss' and vape.Modules and vape.Modules.NoClickDelay and vape.Modules.NoClickDelay.Enabled then
			return {SendToServer = function() end}
		elseif remoteName == remotes.EquipItem and shared.CatvapeDeveloper then
			-- Developer trace for equips that bypass switchItem. Every method is forwarded
			-- to the real object with the real self; only the three that send are logged,
			-- and a request switchItem has just logged is not logged twice.
			return setmetatable({}, {__index = function(_, key)
				local value = call[key]
				if type(value) ~= 'function' then return value end
				return function(_, ...)
					if key == 'CallServerAsync' or key == 'CallServer' or key == 'SendToServer' then
						local args = ...
						local tool = type(args) == 'table' and args.hand or nil
						local fromSwitch = tool and switchItemRequested[tool]
						if not (fromSwitch and os.clock() - fromSwitch < 0.2) then
							traceEquip(tool, 'EquipItem:' .. key)
						end
					end
					return value(call, ...)
				end
			end})
		end

		return call
	end

	bedwars.BlockController.isBlockBreakable = function(self, breakTable, plr)
		local obj = bedwars.BlockController:getStore():getBlockAt(breakTable.blockPosition)

		if obj and obj.Name == 'bed' then
			for _, plr in svc.playersService:GetPlayers() do
					return false
				end
			end

		return OldBreak(self, breakTable, plr)
	end

	local blockhealthbar = {blockHealth = -1, breakingBlockPosition = Vector3.zero}
	store.blockPlacer = bedwars.BlockPlacer.new(bedwars.BlockEngine, 'wool_white')

	local function getBlockHealth(block, blockpos)
		local blockdata = bedwars.BlockController:getStore():getBlockData(blockpos)
		return (blockdata and (blockdata:GetAttribute('1') or blockdata:GetAttribute('Health')) or block:GetAttribute('Health'))
	end

	local function getBlockHits(block, blockpos)
		if not block then return 0 end
		local breaktype = bedwars.ItemMeta[block.Name].block.breakType
		local tool = store.tools[breaktype]
		tool = tool and bedwars.ItemMeta[tool.itemType].breakBlock[breaktype] or 2
		return getBlockHealth(block, bedwars.BlockController:getBlockPosition(blockpos)) / tool
	end

	--[[ Published for the same reason breakBlock and placeBlock are: Breaker's 'Health' mode
	ranks the blocks around you and has to measure them the way the dig-spot ranking
	inside breakBlock already does, or the two disagree about what is cheapest. ]]
	bedwars.getBlockHits = getBlockHits

	--[[
		Pathfinding using a luau version of dijkstra's algorithm
		Source: https://stackoverflow.com/questions/39355587/speeding-up-dijkstras-algorithm-to-solve-a-3d-maze

		Walks outward through solid blocks from the target and answers with the cheapest cell
		that touches air -- the spot someone could stand at and put a tool on.

		Two things used to make that answer expensive, and together they are the 'the bed is
		wide open and Breaker sits there for three seconds before it starts' delay:

		* The queue was drained in insertion order, so nothing about the search ever knew it
		  was finished. Every call explored the whole mass of blocks connected to the target
		  -- on an island that is thousands of cells, and each one costs six getPlacedBlock
		  lookups plus a getBlockHits that reads block data back out of the game -- and only
		  then picked a winner out of everything it had seen.
		* Popping was table.remove(unvisited, 1), which shifts the entire array down one slot
		  every time. With a queue that long that is the quadratic half of the cost.

		Both go away by popping the cheapest node instead of the oldest. Breaking a block never
		costs a negative number of hits, so once an air-touching cell comes off a min-heap,
		nothing still queued behind it can be cheaper, and the search only has to finish the
		cost it is on rather than everything reachable. An exposed bed is answered on the first
		pop, at zero cost, instead of after a full sweep of everything joined to it.

		The search intentionally finishes that cost band. Ties are the
		normal case here, not an edge case -- every cell of a one-layer cover is the same one
		block from the target -- and which of them the answer names decides where the break
		actually lands. The nearest to the player wins it; see the loop.

		Nothing is cached by design. There used to be a
		table of answers keyed by target cell, from when a call cost a full sweep and paying it
		every pass was unthinkable. It has to go now that the cost is made of block HEALTH:
		health falls with every hit landed, changes nothing about the layout and fires no event
		anybody can listen for, so a cached cost is wrong the moment anyone starts breaking
		anything -- and 'which of these is cheapest' is precisely the question Breaker's Health
		mode is asking. A stale answer there means watching it chew on a full block while a
		one-hit block sits next to it. The invalidation grew a rule per bug (blocks placed,
		blocks broken, the player walking round to the other side) and this was simply the next
		one, so the table went instead. A search that stops at the first cost band is cheap
		enough to run every pass, and Breaker's pass is a quarter of a second long.
	]]
	--[[ A block the break code must treat as solid: never dug through, never struck.

	The generic NoBreak attribute is what calculatePath and frontOf used to test, and the
	Team<id>NoBreak one what breakBlock's last guard tested -- but neither covered our own
	bed in every case. The per-team attribute is not always there (a Team attribute that has
	not replicated yet reads as Team-1 and matches nothing), and breakBlock hits the DIG SPOT,
	which is routinely not the block the caller asked for: the path can route through a cell
	of our own bed, and Block Check redirects onto whatever is first on the eye line. That is
	the rare own-bed break.

	So a bed also asks the game, over its whole footprint, the same question isOwnBed in
	bedwars.lua asks: any cell we are not allowed to break makes it ours. The whole footprint
	because a bed half carrying a scarab hive reads as breakable on its own. Only beds pay for
	that; every other block is two attribute reads. ]]
	local function isProtectedBlock(block, worldpos)
		if not block then return false end
		if block:GetAttribute('NoBreak') then return true end
		if block:GetAttribute('Team'..(lplr:GetAttribute('Team') or -1)..'NoBreak') ~= nil then return true end
		if svc.collectionService:HasTag(block, 'bed') then
			local cells
			pcall(function()
				local handler = bedwars.BlockController:getHandlerRegistry():getHandler(block.Name)
				cells = handler and handler:getContainedPositions(block)
			end)
			cells = cells or {bedwars.BlockController:getBlockPosition(worldpos)}
			for _, cell in cells do
				local ok, breakable = pcall(function()
					return bedwars.BlockController:isBlockBreakable({blockPosition = cell}, lplr)
				end)
				if ok and breakable == false then return true end
			end
		end
		return false
	end

	local function calculatePath(target, blockpos, hitResolver, originOverride)
		local origin = originOverride
			or (entitylib.isAlive and entitylib.character.RootPart.Position or Vector3.zero)
		hitResolver = hitResolver or getBlockHits
		local visited, distances, path = {}, {[blockpos] = 0}, {}
		local heap, heapsize = {{0, blockpos}}, 1

		local function push(cost, node)
			heapsize += 1
			heap[heapsize] = {cost, node}
			local child = heapsize
			while child > 1 do
				local parent = child // 2
				if heap[parent][1] <= heap[child][1] then break end
				heap[parent], heap[child] = heap[child], heap[parent]
				child = parent
			end
		end

		local function pop()
			if heapsize == 0 then return nil end
			local top = heap[1]
			heap[1] = heap[heapsize]
			heap[heapsize] = nil
			heapsize -= 1

			local parent = 1
			while true do
				local left, right = parent * 2, parent * 2 + 1
				local smallest = parent
				if left <= heapsize and heap[left][1] < heap[smallest][1] then smallest = left end
				if right <= heapsize and heap[right][1] < heap[smallest][1] then smallest = right end
				if smallest == parent then break end
				heap[parent], heap[smallest] = heap[smallest], heap[parent]
				parent = smallest
			end

			return top
		end

		--[[ Cheapest wins, and the nearest of the cheapest wins the tie.

		The tie is not an edge case, it is the normal case: every cell of a one-layer cover
		costs the same one block to get through, so the top of the pile, the far side and
		the face you are standing at are all equally cheap, and picking whichever the queue
		happened to reach first is picking at random. Which of them the answer names decides
		where the break lands, and a spot on the wrong side of a structure is one Block Check
		then has to walk all the way back -- when it can, and it could not always. ]]
		local best, bestcost, bestrange
		for _ = 1, 10000 do
			local node = pop()
			if not node then break end

			local cost, current = node[1], node[2]
			--[[ Nodes come off cheapest first, so once one costs more than the answer already
			in hand, nothing still queued can beat it. The slack is for float noise: two
			routes through the same blocks can add up in different orders. ]]
			if best and cost > bestcost + 0.0001 then break end
			--[[ A cell can sit in the heap more than once, from before its distance was
			improved; the first pop is the good one and the rest are stale. ]]
			if sph.visited[current] then continue end
			sph.visited[current] = true

			local touchesair = false
			for _, side in sides do
				side = current + side
				if sph.visited[side] then continue end

				local block = getPlacedBlock(side)
				if not block or block == target or isProtectedBlock(block, side) then
					if not block then
						touchesair = true
					end
					continue
				end

				local curdist = hitResolver(block, side) + cost
				if curdist < (distances[side] or math.huge) then
					distances[side] = curdist
					path[side] = current
					push(curdist, side)
				end
			end

			if touchesair then
				local range = (origin - current).Magnitude
				if not best or range < bestrange then
					best, bestcost, bestrange = current, cost, range
				end
			end
		end

		if best then
			return best, bestcost, path
		end
	end

	bedwars.calculateBreakPath = calculatePath

	--[[ Where does the line from the player to this dig spot first meet a block? That block is
	what someone standing here would actually hit swinging at it, and it is what has to come
	off before anything behind it can be reached. calculatePath calls a cell diggable when
	ANY of its six faces touches air, including the face underneath it or the one on the far
	side, so its answer on its own happily digs a covered bed straight through its cover.

		The code now marches cell by cell along the whole line. It used to hop one cell at a time along
	whichever axis dominated, which is blind in exactly the case that matters: a dig spot up
	on a mound has air beside it on that axis, so the very first hop found nothing, the walk
	stopped, and the spot reported itself as the thing in the way -- Block Check waving
	through a break into the middle of a structure with the wall in front of the player
	untouched. A march cannot miss it: the wall is on the line whether or not it happens to
	lie along the dominant axis.

	Done against the block store rather than with a raycast: blocks render through chunked
	geometry, so a ray reports chunk parts instead of the block the store hands back and
	cannot tell a target apart from whatever covers it.

	The march carries on past that first block to the spot, adding up the hits every block
	on the line will take, so clearShot can tell a line with one wool block left in it from
	one through end stone. The first block is still what gets returned.

	t runs 0 at the player to 1 at the dig spot: next* is the t at which the march crosses
	into the following cell on that axis, delta* is the t one whole cell costs there, and an
	axis the line does not move along never comes up for its turn. ]]
	local function boundary(index, component, delta)
		if delta == 0 then
			return 0, math.huge, math.huge
		end
		local step = delta > 0 and 1 or -1
		return step, ((((index + (step * 0.5)) * 3) - component) / delta), (3 / math.abs(delta))
	end

	local function frontOf(worldpos)
		if not entitylib.isAlive then return worldpos, false, 0 end

		--[[ From the head, not the root: it is the eye line that decides what is reachable, and
		a root at foot height reads a floor block as cover when nothing is in the way. ]]
		local head = entitylib.character.Head
		local origin = (head and head.Position) or entitylib.character.RootPart.Position
		local direction = worldpos - origin
		local start, finish = bedwars.BlockController:getBlockPosition(origin), bedwars.BlockController:getBlockPosition(worldpos)
		local x, y, z = start.X, start.Y, start.Z

		local stepx, nextx, deltax = boundary(x, origin.X, direction.X)
		local stepy, nexty, deltay = boundary(y, origin.Y, direction.Y)
		local stepz, nextz, deltaz = boundary(z, origin.Z, direction.Z)

		--[[ 30 studs of reach is ten cells, and a diagonal line crosses at most one boundary per
		axis per cell, so this cannot run out before the spot does. ]]
		local first, cost = nil, 0
		for _ = 1, 40 do
			--[[ every axis past its last boundary: the spot itself is the next thing on the line ]]
			if nextx > 1 and nexty > 1 and nextz > 1 then break end

			if nextx <= nexty and nextx <= nextz then
				x, nextx = x + stepx, nextx + deltax
			elseif nexty <= nextz then
				y, nexty = y + stepy, nexty + deltay
			else
				z, nextz = z + stepz, nextz + deltaz
			end

			local cell = Vector3.new(x, y, z)
			if cell == finish then break end

			local block = getPlacedBlock(cell * 3)
			if block then
				--[[ Something unbreakable on the line, in front or behind the first block,
				means this line never clears, and naming its first block would only send the
				break at cover with no way past it. Hand the spot back unchanged, and say so:
				'nothing in the way' and 'no way through' arrive as the same spot otherwise,
				and the caller has to tell a clear shot from a sealed one. ]]
				if isProtectedBlock(block, cell * 3) then return worldpos, true, math.huge end
				first = first or cell * 3
				--[[ Guarded: this prices every block on the line now, not only blocks the
				path search reached, and a block with no health to read must cost something
				rather than throw out of the whole break. ]]
				local ok, hits = pcall(getBlockHits, block, cell * 3)
				cost += (ok and type(hits) == 'number') and hits or 1
			end
		end

		return first or worldpos, false, cost
	end

	--[[ The points inside a cell a line from the player is tried against, as clearShot below
	describes. ]]
	local function aimOffsets(origin, pos)
		local toward = origin - pos
		local offsets = {Vector3.zero, Vector3.new(0, 1.4, 0)}
		if math.abs(toward.X) > 0.01 then
			table.insert(offsets, Vector3.new(math.sign(toward.X) * 1.4, 0, 0))
		end
		if math.abs(toward.Z) > 0.01 then
			table.insert(offsets, Vector3.new(0, 0, math.sign(toward.Z) * 1.4))
		end
		if toward.Y < 0 then
			table.insert(offsets, Vector3.new(0, -1.4, 0))
		end
		return offsets
	end

	--[[ Is there a clear line onto this cell from ANY of its visible faces?

	frontOf aims at the cell's centre, and a line to the centre clips whatever sits beside the
	target even when a face of the target is in plain view -- a line down onto a bed grazes the
	ore block next to it, so Block Check sent the break into the ore and the bed waited. That
	is the ores-before-bed report. The centre, the top face and the faces turned toward the
	player are each tried, kept 1.4 studs in so every point still lies inside the same cell;
	any one of them with nothing in the way means the target itself can be hit.

	Returns the spot to strike and whether the way is sealed. When every line is blocked, the
	way in is the line that takes the fewest hits to clear, and its first block is what gets
	struck. The centre line used to decide alone: grazing the end stone over a hole it sent
	six hits there while the line onto the near face had one wool block left in it, and with
	a map wall on it it called the spot sealed though the top was only behind wool. Fewest
	hits also keeps a block that is part-way broken in front, it being the cheaper one. A
	line with anything unbreakable on it never clears and does not count; only when that is
	every line is the way sealed. ]]
	local function clearShot(pos)
		if not entitylib.isAlive then return pos, false end
		local head = entitylib.character.Head
		local origin = (head and head.Position) or entitylib.character.RootPart.Position
		local offsets = aimOffsets(origin, pos)

		local front, sealed, best
		for i, offset in offsets do
			local point = pos + offset
			local first, blocked, cost = frontOf(point)
			if first == point and not blocked then
				return pos, false
			end
			if i == 1 then
				front, sealed = first, blocked
			end
			if not blocked and (not best or cost < best) then
				front, sealed, best = first, false, cost
			end
		end
		return front, sealed
	end

	--[[ Does any of the lines clearShot tries onto pos pass through this cell, or within
	`margin` studs of it? A slab test against the cell's cube grown by the margin; the margin
	is what lets a line that wobbles off the cell's edge with the head still count. ]]
	local AXES = {'X', 'Y', 'Z'}
	local function inTheWay(cell, pos, margin)
		local head = entitylib.character.Head
		local origin = (head and head.Position) or entitylib.character.RootPart.Position
		local center, half = cell * 3, 1.5 + margin
		for _, offset in aimOffsets(origin, pos) do
			local point = pos + offset
			local tmin, tmax = 0, 1
			for _, axis in AXES do
				local from, delta = origin[axis], point[axis] - origin[axis]
				local lo, hi = center[axis] - half, center[axis] + half
				if math.abs(delta) < 1e-6 then
					if from < lo or from > hi then
						tmin = math.huge
						break
					end
				else
					local t1, t2 = (lo - from) / delta, (hi - from) / delta
					if t1 > t2 then t1, t2 = t2, t1 end
					tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
					if tmin > tmax then break end
				end
			end
			if tmin <= tmax then return true end
		end
		return false
	end

	--[[ Suppressing the place-block animation has to be re-entrancy safe.

	It used to save whatever sat in AnimationUtil.playAnimation, stub it, and put the saved
	value back when the placement finished. That is only correct for one placement at a
	time, and placements are never one at a time: blockPlacer:placeBlock ends in
	BlockEngineRemotes.Client:Get('PlaceBlock'):CallServer(...), which yields on the round
	trip, and Scaffold and Nuker both dispatch through task.spawn. So two overlap
	constantly:

	    A: saves the real function, installs the stub, yields in CallServer
	    B: saves THE STUB as "the real function", installs the stub, yields
	    A: resumes, restores the real function
	    B: resumes, restores the stub  <- permanent

	AnimationUtil.playAnimation is game-core's shared animation entry point, not a
	block-placement detail, so from that moment the client plays no animations at all --
	no swing, no place, no break -- until a rejoin. It bites hardest on mobile, where the
	framerate is low enough that a CallServer spans several placement ticks.

	One stored original and a depth count instead: the stub goes in when the first
	placement starts and comes out only when the last one finishes, in whatever order they
	happen to interleave. ]]
	local placeAnimOriginal, placeAnimDepth = nil, 0

	local function suppressPlaceAnimation()
		if not bedwars.AnimationUtil then return false end
		if placeAnimDepth == 0 then
			placeAnimOriginal = bedwars.AnimationUtil.playAnimation
			bedwars.AnimationUtil.playAnimation = function() end
		end
		placeAnimDepth += 1
		return true
	end

	local function restorePlaceAnimation()
		placeAnimDepth -= 1
		if placeAnimDepth > 0 then return end
		placeAnimDepth = 0
		if placeAnimOriginal then
			bedwars.AnimationUtil.playAnimation = placeAnimOriginal
			placeAnimOriginal = nil
		end
	end

	bedwars.placeBlock = function(pos, item, animate)
		if not getItem(item) then return end

		store.blockPlacer.blockType = item
		local suppressed = animate == false and suppressPlaceAnimation()

		local ok, result = pcall(function()
			return store.blockPlacer:placeBlock(bedwars.BlockController:getBlockPosition(pos))
		end)
		-- Inside the pcall's shadow on purpose: an error thrown by placeBlock must still
		-- decrement, or the depth never returns to zero and the stub stays for good.
		if suppressed then restorePlaceAnimation() end
		if not ok then error(result, 0) end
		return result
	end

	--[[ blockcheck: when true, walk the chosen dig spot back to whatever physically stands
	  between it and the player, so cover comes off first instead of being mined through.
	  Anything else (false, or the nil every other caller passes) leaves the original
	  behaviour completely alone -- pathfind and dig, cover or no cover.
	method: 'Distance' ranks candidates by how far the dig spot is from the player;
	  anything else keeps the original ranking, fewest hits to get through. The ranking
	  still decides which cell is aimed at; blockcheck only walks that choice back to
	  whatever is physically in front of it.
	autotool: pick the tool by selecting its hotbar slot (what the AutoTool module does)
	  instead of equipping it directly. The correct tool is equipped either way -- this
	  only decides which route gets used.
	The ranking matters: picking purely by hit count can settle on a spot on the far side
	of the block, and the 30-stud guard below then aborts the break outright.
	pin: a table the caller keeps from one call to the next. The cell a hit lands on is
	  remembered in it and struck again next call while it still stands, can still be hit
	  and the block asked for has not come open itself, so the hits go into one block until
	  it comes out. nil picks afresh each call as before.
	Returns pos, path, target when effects is set, and a fourth value, true, whenever a hit
	  was actually sent, so a caller can tell a swing from a call that found nothing to hit. ]]
	bedwars.breakBlock = function(block, effects, anim, customHealthbar, blockcheck, method, autotool, pin)
		if lplr:GetAttribute('DenyBlockBreak') or not entitylib.isAlive then return end
		local handler = bedwars.BlockController:getHandlerRegistry():getHandler(block.Name)
		local cost, pos, target, path = math.huge
		local selfpos = entitylib.character.RootPart.Position
		local positions = (handler and handler:getContainedPositions(block)) or {block.Position / 3}
		local direct = false
		local open = false

		for _, v in positions do
			local cell = v * 3
			local dpos, dcost, dpath = calculatePath(block, cell)
			if dpos then
				--[[ Does this candidate land on the block itself rather than on something
				covering it? calculatePath answers with the cell it started from when that
				cell already touches air, so dpos == cell IS 'this side of the block is
				open'. Preferred outright, because aiming at the target beats aiming at its
				cover and 'Distance' would otherwise rank a nearer cover cell above an open
				bed. It is only a preference: blockcheck still gets the last word below, and
				sends the break back onto the cover when the open side cannot be reached
				from where the player stands. ]]
				local ddirect = dpos == cell
				local score = method == 'Distance' and (selfpos - dpos).Magnitude or dcost
				--[[ Kept a strict boolean: a single-celled block offers one candidate, so for
				every caller but a bed this collapses to the original `score < cost` ]]
				--[[ With Block Check on, a candidate that can be struck directly beats one that
				would be redirected onto something in front of it -- so a bed with one clear
				cell is hit there rather than through the ore or wall beside the other. ]]
				local dopen = true
				if blockcheck then
					local front, sealed = clearShot(dpos)
					dopen = (not sealed) and front == dpos
				end
				local better
				if pos == nil then
					better = true
				elseif dopen ~= open then
					better = dopen
				elseif ddirect ~= direct then
					better = ddirect
				else
					better = score < cost
				end
				if better then
					cost, pos, target, path, direct, open = score, dpos, cell, dpath, ddirect, dopen
				end
			end
		end

		--[[ Finish what was started. With Block Check the spot is often out of sight, and what
		gets hit is whatever stands in front of it -- which changes with every bob of the head
		and every step, so the hits got spread over the blocks round a hole with none of them
		coming out. So the block last struck stays the target while it is still there, nothing
		protects it, it is in reach, it can be hit directly, and it is still in the way of the
		spot, give or take a stud for the head moving. A spot that can be hit directly is taken
		over it: those hits are never wasted, the spot is on the way in. So is a spot that has
		moved off it altogether -- a cheaper way in through a hole just made, you walking round
		to another side. The block asked for coming open ends it too. ]]
		local pinned = false
		if pin then
			if pin.block == block and pin.cell and pos and not (open and direct) then
				local spot = pin.cell * 3
				local part = getPlacedBlock(spot)
				if part and part == pin.part and not isProtectedBlock(part, spot)
					and (entitylib.character.RootPart.Position - spot).Magnitude <= 30
					and (spot == pos or (not open and inTheWay(pin.cell, pos, 0.75))) then
					local front, sealed = spot, false
					if blockcheck then
						front, sealed = clearShot(spot)
					end
					if not sealed and front == spot then
						pos, path, pinned = spot, nil, true
					end
				end
			end
			if not pinned then
				pin.block, pin.cell, pin.part = nil, nil, nil
			end
		end

		--[[ Block Check. The spot chosen above is picked by the selected metric, but it can sit
		behind the cover (an air face under the bed, or one on its far side, or a cell up on
		top of a mound) and hitting it there is what reads as mining straight through the
		blocks. Take the first cell the eye line actually runs into instead, so the cover
		comes off from the side the player is standing on.

		There are no exceptions. Everything that used to be waved through
		here -- a face pointing your way is open, the target itself is exposed somewhere --
		turned out to mean 'exposed' in a sense that had nothing to do with being reachable
		from where the player is standing, and each one came back as a break going through a
		wall. There is nothing to lose by asking every time: a spot already at the front of
		the line is what the march meets first, so it hands back exactly that spot. An open
		bed you can see is hit; the same bed with wool in front of it gets the wool stripped. ]]
		if blockcheck and pos and not pinned then
			local front, sealed = clearShot(pos)
			--[[ Something that must not be broken -- our own bed, a NoBreak block -- stands in
			every line. There is no shot, and hitting the spot anyway is swinging through it. ]]
			if sealed then return end
			if front ~= pos then
				--[[ path described the old target; drop it so the visualiser stops drawing a
				chain that no longer leads anywhere ]]
				pos, path = front, nil
			end
		end

		if pos then
			if (entitylib.character.RootPart.Position - pos).Magnitude > 30 then return end
			local dblock, dpos = getPlacedBlock(pos)
			--[[ Nothing standing where the path said to dig: the world moved under the answer
			between working it out and acting on it. Next pass works out a fresh one. ]]
			if not dblock then return end

			--[[ Never swing at something the game marks unbreakable for our own team, whatever
			the caller thought it was aiming at. The dig spot is routinely NOT the block that
			was ranked -- Block Check redirects it onto whatever stands in the way -- so a
			caller's own filtering says nothing about what ends up taking the damage, and the
			one thing that must never take damage is our own bed. One attribute read, the
			same one the game marks it with. ]]
			if isProtectedBlock(dblock, dpos * 3) then return end

			--[[ The recent-swing gate keeps the sword in hand mid-fight for callers that
			pass autotool=false. When the caller explicitly asked for AutoTool it has
			to win instead: Breaker runs its loop continuously, so with a killaura or
			autoclicker active lastAttack is refreshed constantly, this window never
			opened and the tool swap simply never happened -- the block got mined with
			whatever was already held. ]]
			local blockmeta = bedwars.ItemMeta[dblock.Name]
			blockmeta = blockmeta and blockmeta.block
			if blockmeta and (autotool or (workspace:GetServerTimeNow() - bedwars.SwordController.lastAttack) > 0.4) then
				local breaktype = blockmeta.breakType
				--[[ store.tools is only rebuilt when the Rodux inventory fires an items
				change, so it can still be empty (or stale) at the moment a break
				starts. Rescan on a miss rather than silently skipping the swap --
				a nil here meant the whole block below was skipped and the block got
				mined with the sword, which looks exactly like AutoTool doing nothing. ]]
				local tool = breaktype and (store.tools[breaktype] or getTool(breaktype))
				--[[ Exact type match first (shears for wool), then the best break tool
				carried (a pickaxe on wool). Gated on autotool so the other callers,
				which pass it nil, keep their previous hold-the-sword behaviour. ]]
				if not tool and autotool then
					tool = getBestBreakTool()
				end
				if tool and tool.tool then
					--[[ autotool: move the hotbar selection onto the tool the way the AutoTool
					module does it -- an InventorySelectHotbarSlot dispatch, i.e. the same
					path as pressing the number key -- so the swap happens through the
					game's own selection instead of a bare EquipItem. ]]
					local slot
					if autotool then
						for i, v in store.inventory.hotbar or {} do
							if v.item and v.item.itemType == tool.itemType then
								slot = i - 1
								break
							end
						end
					end
					--[[ Both, not either. The hotbar dispatch only moves the client's
					selected slot; it is not proof the character actually ended up
					holding the tool. Treating a successful dispatch as "done" and
					skipping the equip is what left the sword in hand while the UI
					showed the pickaxe selected -- and block damage is resolved from
					what is actually held (BlockEngine.calculateBlockDamage takes the
					player), so the block still got mined with the sword. switchItem
					no-ops when the tool is already in hand, so this costs nothing. ]]
					if slot then
						hotbarSwitch(slot)
					end
					switchItem(tool.tool)
				end
			end

			if blockhealthbar.blockHealth == -1 or dpos ~= blockhealthbar.breakingBlockPosition then
				blockhealthbar.blockHealth = getBlockHealth(dblock, dpos)
				blockhealthbar.breakingBlockPosition = dpos
			end

			if pin then
				pin.block, pin.cell, pin.part = block, dpos, dblock
			end

			bedwars.ClientDamageBlock:Get('DamageBlock'):CallServerAsync({
				blockRef = {blockPosition = dpos},
				hitPosition = pos,
				hitNormal = Vector3.FromNormalId(Enum.NormalId.Top)
			}):andThen(function(result)
				-- The answer can land after a reinject tore this session down (bedwars emptied).
				if vape.Loaded == nil or not bedwars.BlockController then return end
				if result then
					--[[ The server would not take a hit there: stop coming back to it. ]]
					if pin and pin.cell == dpos and (result == 'cancelled' or result == 'failed') then
						pin.block, pin.cell, pin.part = nil, nil, nil
					end

					if result == 'cancelled' then
						store.damageBlockFail = os.clock() + 1
						return
					end

					if effects then
						local blockdmg = (blockhealthbar.blockHealth - (result == 'destroyed' and 0 or getBlockHealth(dblock, dpos)))
						customHealthbar = customHealthbar or bedwars.BlockBreaker.updateHealthbar
						customHealthbar(bedwars.BlockBreaker, {blockPosition = dpos}, blockhealthbar.blockHealth, dblock:GetAttribute('MaxHealth'), blockdmg, dblock)
						blockhealthbar.blockHealth = math.max(blockhealthbar.blockHealth - blockdmg, 0)

						if blockhealthbar.blockHealth <= 0 then
							bedwars.BlockBreaker.breakEffect:playBreak(dblock.Name, dpos, lplr)
							if bedwars.BlockBreaker.healthbarMaid then
								bedwars.BlockBreaker.healthbarMaid:DoCleaning()
							end
							blockhealthbar.breakingBlockPosition = Vector3.zero
						else
							bedwars.BlockBreaker.breakEffect:playHit(dblock.Name, dpos, lplr)
						end
					end

					if anim then
						local animation = bedwars.AnimationUtil:playAnimation(lplr, bedwars.BlockController:getAnimationController():getAssetId(1))
						bedwars.ViewmodelController:playAnimation(15)
						task.wait(0.3)
						animation:Stop()
						animation:Destroy()
					end
				end
			end)

			if effects then
				return pos, path, target, true
			end
			return nil, nil, nil, true
		end
	end

	--[[ Tells a caller this breakBlock reports a sent hit as its fourth value; one from before
	that returns nothing there whether it swung or not. ]]
	bedwars.breakBlockReportsHit = true

	for _, v in Enum.NormalId:GetEnumItems() do
		table.insert(sides, Vector3.FromNormalId(v) * 3)
	end

	--[[ Coalesces inventory-change fan-out so a single shop purchase (which causes
	multiple bedwars.Store updates in one frame) only notifies the downstream
	listeners (AutoBuy / AutoConsume / AutoHotbar, each doing full inventory
	scans) once per frame instead of once per store dispatch. The synchronous
	store.tools/store.hand updates are kept inline so nothing reads stale data. ]]
	local invFireQueued = false
	local pendingAmount = false
	local function flushInventoryEvents()
		invFireQueued = false
		local amount = pendingAmount
		pendingAmount = false
		vapeEvents.InventoryChanged:Fire()
		if amount then
			vapeEvents.InventoryAmountChanged:Fire()
		end
	end

	local function updateStore(new, old)
		if new.Bedwars ~= old.Bedwars then
			store.equippedKit = new.Bedwars.kit ~= 'none' and new.Bedwars.kit or ''
		end

		if new.Game ~= old.Game then
			store.matchState = new.Game.matchState
			store.queueType = new.Game.queueType or 'bedwars_test'
		end

		if new.Inventory ~= old.Inventory then
			local newinv = (new.Inventory and new.Inventory.observedInventory or {inventory = {}})
			local oldinv = (old.Inventory and old.Inventory.observedInventory or {inventory = {}})
			store.inventory = newinv

			local invChanged    = newinv ~= oldinv
			local itemsChanged  = newinv.inventory.items ~= oldinv.inventory.items

			if itemsChanged then
				--[[ keep tool cache synchronous (small scans, read elsewhere immediately) ]]
				store.tools.sword = getSword()
				for _, v in {'stone', 'wood', 'wool'} do
					store.tools[v] = getTool(v)
				end
				pendingAmount = true
			end

			if newinv.inventory.hand ~= oldinv.inventory.hand then
				--[[ newinv, not new.Inventory.observedInventory: that is nil in exactly the case
				newinv falls back for, and an item with no meta entry reads as no tool type
				rather than an error. Either one thrown here aborted the store's change
				dispatch, so the game's own listeners still waiting their turn missed that
				update. ]]
				local currentHand, toolType = newinv.inventory.hand, ''
				if currentHand then
					local handData = bedwars.ItemMeta[currentHand.itemType] or {}
					toolType = handData.sword and 'sword' or handData.block and 'block' or currentHand.itemType:find('bow') and 'bow'
				end

				store.hand = {
					tool = currentHand and currentHand.tool,
					amount = currentHand and currentHand.amount or 0,
					toolType = toolType
				}
			end

			--[[ Defer the event fan-out to end-of-frame so multiple dispatches in the
			same frame coalesce into a single notification to each listener. ]]
			if invChanged and not invFireQueued then
				invFireQueued = true
				task.defer(flushInventoryEvents)
			end
		end
	end

	local storeChanged = bedwars.Store.changed:connect(updateStore)

	-- Developer trace: every change to what the character is actually holding, whoever
	-- made it. A swap logged here with no switchItem or EquipItem line just before it did
	-- not come from a request this client sent.
	if shared.CatvapeDeveloper then
		local function watchHand(char)
			local handInv = char:WaitForChild('HandInvItem', 10)
			if not handInv then return end
			vape:Clean(handInv:GetPropertyChangedSignal('Value'):Connect(function()
				local tool = handInv.Value
				print(string.format('[catvape equip] t=%.3f hand changed -> %s',
					os.clock(), tool and tool.Name or 'nothing'))
			end))
		end
		if lplr.Character then task.spawn(watchHand, lplr.Character) end
		vape:Clean(lplr.CharacterAdded:Connect(watchHand))
	end
	updateStore(bedwars.Store:getState(), {})
	
	for _, event in {'MatchEndEvent', 'EntityDeathEvent', 'BedwarsBedBreak', 'BalloonPopped', 'AngelProgress', 'GrapplingHookFunctions'} do
		if not vape.Connections then return end
		bedwars.Client:WaitFor(event):andThen(function(connection)
			vape:Clean(connection:Connect(function(...)
				vapeEvents[event]:Fire(...)
			end))
		end)
	end
	
	-- Named rather than picked out with select, which walks the arguments again for every field.
	vape:Clean(bedwars.ZapNetworking.EntityDamageEventZap.On(function(entityInstance, damage, damageType, fromPosition, fromEntity, knockbackMultiplier, knockbackId, attackData, ...)
		vapeEvents.EntityDamageEvent:Fire({
			entityInstance = entityInstance,
			damage = damage,
			damageType = damageType,
			fromPosition = fromPosition,
			fromEntity = fromEntity,
			knockbackMultiplier = knockbackMultiplier,
			knockbackId = knockbackId,
			attackData = attackData,
			-- the 13th argument: the eight named above, then four this does not use
			disableDamageHighlight = select(5, ...)
		})
	end))

	-- Keep confirmed Killaura telemetry at the normalized damage-event seam. The
	-- universal overlay can be enabled before this adapter finishes loading, so it
	-- must not depend on discovering this event from its own callback.
	vape:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
		if damageTable and damageTable.fromEntity == lplr.Character and damageTable.entityInstance then
			entitylib.Performance:RecordKillauraHit(damageTable.entityInstance, os.clock())
		end
	end))

	--[[ cache projectile names we care about ]]
	local validProjectiles = {
		arrow = true,
		snowball = true,
		telepearl = true,
		pearl = true
	}
	--[[ Remembered per name. The launch handler below asks this of every child of workspace
	for every tracked launch in the server, and lowering each name again every time was a
local tr = {}
	fresh string per child per shot. tr.Names repeat, so the table stays small; the cap is only
	a backstop. ]]
	local trackedNames, trackedNameCount = {}, 0
	local function isTrackedProjectile(name)
		local cached = trackedNames[name]
		if cached ~= nil then return cached end
		local lower = tostring(name):lower()
		local result = validProjectiles[lower] or lower:find('telepearl', 1, true) ~= nil
		if type(name) == 'string' then
			if trackedNameCount >= 1024 then
				table.clear(trackedNames)
				trackedNameCount = 0
			end
			trackedNames[name] = result
			trackedNameCount += 1
		end
		return result
	end

	--[[ optimized ZapNetworking hook ]]
	vape:Clean(bedwars.ZapNetworking.ProjectileLaunchZap.On(function(origin, projectileType, tool, shooter)
		local launchedAt = os.clock()
		local shooterPosition, shooterVelocity
		pcall(function()
			local character = shooter
			if typeof(shooter) == 'Instance' and shooter:IsA('Player') then
				character = shooter.Character
			end
			local root = character and (character.PrimaryPart or character:FindFirstChild('HumanoidRootPart'))
			if root then
				shooterPosition = root.Position
				shooterVelocity = root.AssemblyLinearVelocity
			end
		end)
		task.defer(function()
			local lowerType = tostring(projectileType):lower()
			if isTrackedProjectile(lowerType) then
				--[[ only search nearby objects, not entire workspace ]]
				for _, obj in ipairs(workspace:GetChildren()) do
					if isTrackedProjectile(obj.Name) then
						local root = obj:FindFirstChildWhichIsA("BasePart")
						if root and (root.Position - origin).Magnitude < 25 then
							vapeEvents.ProjectileFired:Fire({
								origin = origin,
								projectile = obj,
								tool = tool,
								shooter = shooter,
								launchedAt = launchedAt,
								shooterPosition = shooterPosition,
								shooterVelocity = shooterVelocity
							})
							break --[[ stop after first match ]]
						end
					end
				end
			end
		end)
	end))

	local projectileNames = {arrow = true, snowball = true}
	vape:Clean(workspace.ChildAdded:Connect(function(child)
		if projectileNames[child.Name:lower()] then
			task.defer(function()
				local root = child:FindFirstChildWhichIsA("BasePart")
				if root then
					vapeEvents.ProjectileFired:Fire({
						origin = root.Position,
						projectile = child,
						tool = nil,
						shooter = lplr.Character,
						launchedAt = os.clock(),
						shooterPosition = root.Position,
						shooterVelocity = root.AssemblyLinearVelocity,
						fallback = true
					})
				end
			end)
		end
	end))
	
	for _, event in {'PlaceBlockEvent', 'BreakBlockEvent'} do
		vape:Clean(bedwars.ZapNetworking[event..'Zap'].On(function(...)
			local data = {
				blockRef = {
					blockPosition = ...,
				},
				player = select(5, ...)
			}
			vapeEvents[event]:Fire(data)
		end))
	end

	--[[
		Second argument is whatever owns the cleanup, and `gui` is not a name that exists in
		this file -- so all three of these passed nil and registered no cleanup at all.

		Each call opens two CollectionService signals per tag. Nothing disconnected them, so an
		uninject left them live and mutating tables the rest of the script had let go of, and a
		reinject in the same server (the Reinject button, a profile reset, a config sync) simply
		added another set on top. Every other collection() call site in this file and in
		bedwars.lua passes the module that owns it; these are file-level, so they belong to vape
		itself, which is what its Clean list is for.
	]]
	--[[ Every block in the map, which is tens of thousands of entries once one has loaded. The
	default removal is a table.find plus a shifting table.remove -- a walk of the whole list for
	each block that breaks, so one explosion taking out fifty blocks paid for fifty of them in a
	single frame. Each block's slot is kept alongside instead and a removal swaps the last entry
	into it. Everything that reads store.blocks only iterates it; none of it relies on the order.
	The same index also keeps a block from being listed twice. ]]
	local blockSlots = {}
	store.blocks = collection('block', vape, function(tab, obj)
		if blockSlots[obj] then return end
		local slot = #tab + 1
		tab[slot] = obj
		blockSlots[obj] = slot
	end, function(tab, obj)
		local slot = blockSlots[obj]
		if not slot then return end
		blockSlots[obj] = nil
		if tab[slot] ~= obj then return end
		local last = #tab
		local moved = tab[last]
		tab[last] = nil
		if slot ~= last and moved ~= nil then
			tab[slot] = moved
			blockSlots[moved] = slot
		end
	end)
	vape:Clean(function()
		table.clear(blockSlots)
	end)
	store.shop = collection({'BedwarsItemShop', 'TeamUpgradeShopkeeper'}, vape, function(tab, obj)
		table.insert(tab, {
			Id = obj.Name,
			RootPart = obj,
			Shop = obj:HasTag('BedwarsItemShop'),
			Upgrades = obj:HasTag('TeamUpgradeShopkeeper')
		})
	end)
	store.enchant = collection({'enchant-table', 'broken-enchant-table'}, vape, nil, function(tab, obj, tag)
		if obj:HasTag('enchant-table') and tag == 'broken-enchant-table' then return end
		obj = table.find(tab, obj)
		if obj then
			table.remove(tab, obj)
		end
	end)

	-- Universal creates this library before the game-specific files. Keep the fallback here
	-- for cached or partial universal copies, and reject incomplete stale tables as well.
	sessioninfo = ensureSessionInfo()

	local kills = sessioninfo:AddItem('Kills')
	local beds = sessioninfo:AddItem('Beds')
	local wins = sessioninfo:AddItem('Wins')
	local games = sessioninfo:AddItem('Games')

	local mapname = 'Unknown'
	sessioninfo:AddItem('Map', 0, function()
		return mapname
	end, false)

	task.delay(1, function()
		games:Increment()
	end)

	task.spawn(function()
		pcall(function()
			repeat task.wait() until store.matchState ~= 0 or vape.Loaded == nil
			if vape.Loaded == nil then return end
			mapname = workspace:WaitForChild('Map', 5):WaitForChild('Worlds', 5):GetChildren()[1].Name
			mapname = string.gsub(string.split(mapname, '_')[2] or mapname, '-', '') or 'Blank'
		end)
	end)

	vape:Clean(vapeEvents.BedwarsBedBreak.Event:Connect(function(bedTable)
		if bedTable.player and bedTable.player.UserId == lplr.UserId then
			beds:Increment()
		end
	end))

	vape:Clean(vapeEvents.MatchEndEvent.Event:Connect(function(winTable)
		if (bedwars.Store:getState().Game.myTeam or {}).id == winTable.winningTeamId or lplr.Neutral then
			wins:Increment()
		end
	end))

	vape:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
		local killer = svc.playersService:GetPlayerFromCharacter(deathTable.fromEntity)
		local killed = svc.playersService:GetPlayerFromCharacter(deathTable.entityInstance)
		if not killed or not killer then return end

		if killed ~= lplr and killer == lplr then
			kills:Increment()
		end
	end))

	task.spawn(function()
		local deadline = os.clock() + 60
		local lastError = 'shop initialization has not completed'
		while vape.Loaded ~= nil do
			local oldIdentity
			local shop
			local canSetIdentity = type(getthreadidentity) == 'function'
				and type(setthreadidentity) == 'function'
			local ok, err = xpcall(function()
				if canSetIdentity then
					oldIdentity = getthreadidentity()
					assert(type(oldIdentity) == 'number', 'thread identity is unavailable')
					setthreadidentity(2)
				else
					assert(bedwars.AppController
						and bedwars.AppController:isAppOpen('BedwarsItemShopApp'),
						'open the item shop to initialize AutoBuy on this executor')
				end

				shop = require(svc.replicatedStorage.TS.games.bedwars.shop['bedwars-shop']).BedwarsShop
				assert(type(shop) == 'table' and type(shop.getShopItem) == 'function'
					and type(shop.ShopItems) == 'table', 'shop data is not ready')
				shop.getShopItem('iron_sword', lplr)
			end, errorTrace)

			if type(oldIdentity) == 'number' then
				local restored, restoreError = pcall(setthreadidentity, oldIdentity)
				if not restored then
					bufferCall('error', 'bedwars.shop.identity', tostring(restoreError))
					if vape.Loaded ~= nil then
						notif('AutoBuy', 'Shop initialization could not restore thread identity.', 10, 'alert')
					end
					return
				end
			end
			if vape.Loaded == nil then return end
			if ok then
				bedwars.Shop = shop
				bedwars.ShopItems = shop.ShopItems
				store.shopLoaded = true
				return
			end

			lastError = tostring(err)
			if os.clock() >= deadline then break end
			task.wait(0.5)
		end
		if vape.Loaded == nil then return end
		bufferCall('error', 'bedwars.shop.initialize', lastError)
		notif('AutoBuy', 'Shop initialization failed. Open the item shop and reinject; see the error log.', 10, 'alert')
	end)

	vape:Clean(function()
		Client.Get = OldGet
		bedwars.BlockController.isBlockBreakable = OldBreak
		store.blockPlacer:disable()
		for _, v in vapeEvents do
			v:Destroy()
		end
		table.clear(store.blockPlacer)
		table.clear(vapeEvents)
		table.clear(bedwars)
		table.clear(store)
		table.clear(sides)
		table.clear(remotes)
		storeChanged:disconnect()
		storeChanged = nil
	end)
end)
-- ===================== bedwars module dependencies =====================
-- >>> dep:clearConnections (bedwars:4436-4441)
	local function clearConnections()
		for _, connection in connections do
			pcall(function() connection:Disconnect() end)
		end
		table.clear(connections)
	end
-- >>> dep:track (bedwars:4431-4431)
	local track
-- >>> dep:stopEmote (bedwars:4443-4458)
	local function stopEmote()
		playing = false
		clearConnections()
		if track then
			pcall(function() track:Stop(0.25) end)
			track = nil
		end
		if sound then
			pcall(function() sound:Destroy() end)
			sound = nil
		end
		if effect then
			pcall(function() effect:Destroy() end)
			effect = nil
		end
	end
-- >>> dep:spin (bedwars:4475-4481)
	local function spin(model, name, degrees, seconds)
		local part = model:FindFirstChild(name)
		if not part then return end
		svc.tweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {
			Orientation = part.Orientation + Vector3.new(0, degrees, 0)
		}):Play()
	end
-- >>> dep:sound (bedwars:4432-4432)
	local sound
-- >>> dep:playing (bedwars:4434-4434)
	local playing = false
-- >>> dep:neutralise (bedwars:4463-4473)
	local function neutralise(model)
		for _, descendant in model:GetDescendants() do
			if descendant:IsA('BasePart') then
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.Anchored = true
				pcall(function() bedwars.QueryUtil:setQueryIgnored(descendant, true) end)
			end
		end
	end
-- >>> dep:effect (bedwars:4430-4430)
	local effect
-- >>> dep:connections (bedwars:4433-4433)
	local connections = {}
-- >>> dep:playEmote (bedwars:4483-4557)
	local function playEmote()
		stopEmote()

		if not entitylib.isAlive then
			notif('Catvape', 'You have to be alive to play an emote.', 3)
			return
		end

		local character = entitylib.character.Character
		local humanoid = character and character:FindFirstChildOfClass('Humanoid')
		local pivot = character and (character:FindFirstChild('LowerTorso') or entitylib.character.RootPart)
		if not (character and humanoid and pivot) then return end

		local template = svc.replicatedStorage:FindFirstChild('Assets')
		template = template and template:FindFirstChild('Effects')
		template = template and template:FindFirstChild('NightmareEmote')
		if not template then
			notif('Catvape', 'This place has no NightmareEmote effect to play.', 5)
			return
		end

		playing = true

		effect = template:Clone()
		neutralise(effect)
		effect.Parent = workspace
		--[[ The controller drops it two studs so the ring sits at your feet rather than
		through your waist. ]]
		pcall(function() effect:PivotTo(pivot.CFrame + Vector3.new(0, -2, 0)) end)
		spin(effect, 'Outer', 360, 1.5)
		spin(effect, 'Middle', -360, 12.5)

		--[[ The emote's own soundsOnBegin entry: locker.emotes.nightmare_1_sounds_on_begin_sound,
		which the meta marks looped -- it is a drone that runs under the whole emote, not a
		one-shot sting, so it has to be stopped with everything else rather than left to
		finish. Parented to the torso so it is positional and dies with the character even if
		stopEmote never gets to run. ]]
		pcall(function()
			sound = Instance.new('Sound')
			sound.Name = 'CatvapeNightmareEmote'
			sound.SoundId = 'rbxassetid://9188182911'
			sound.Looped = true
			sound.Volume = 0.5
			sound.Parent = pivot
			sound:Play()
		end)

		local animator = humanoid:FindFirstChildOfClass('Animator')
		if animator then
			pcall(function()
				local animation = Instance.new('Animation')
				animation.AnimationId = 'rbxassetid://9191822700'
				track = animator:LoadAnimation(animation)
				track.Looped = true
				track.Priority = Enum.AnimationPriority.Action
				track:Play(0.2)
			end)
		end

		--[[ Ends the way a real emote ends: the first step you take, or dying. Both are
		checked rather than only one, because a respawn destroys the character out from
		under the animation but leaves the effect parented to workspace forever. ]]
		connections[#connections + 1] = humanoid:GetPropertyChangedSignal('MoveDirection'):Connect(function()
			if playing and humanoid.MoveDirection.Magnitude > 0 then
				stopEmote()
			end
		end)
		connections[#connections + 1] = humanoid.Died:Connect(stopEmote)
		connections[#connections + 1] = humanoid.Jumping:Connect(function(active)
			if active then stopEmote() end
		end)
		connections[#connections + 1] = character.AncestryChanged:Connect(function(_, parent)
			if not parent then stopEmote() end
		end)
	end
-- >>> dep:NightmareEmote (bedwars:4429-4429)
	local NightmareEmote
-- >>> dep:nametagWatch (bedwars:14700-14700)
	local nametagWatch = {}
-- >>> dep:eachNametag (bedwars:14710-14717)
	local function eachNametag(char, fn)
		if not char then return end
		for _, v in char:GetDescendants() do
			if v:IsA('BillboardGui') and v.Name == 'Nametag' then
				pcall(fn, v)
			end
		end
	end
-- >>> dep:clearNametagWatch (bedwars:14703-14708)
	local function clearNametagWatch()
		for _, c in nametagWatch do
			pcall(function() c:Disconnect() end)
		end
		table.clear(nametagWatch)
	end
-- >>> dep:setNametagEnabled (bedwars:14719-14732)
	local function setNametagEnabled(state, char)
		clearNametagWatch()
		char = char or lplr.Character
		if not char then return end

		eachNametag(char, function(v) v.Enabled = state end)
		if state then return end

		nametagWatch[#nametagWatch + 1] = char.DescendantAdded:Connect(function(v)
			if v:IsA('BillboardGui') and v.Name == 'Nametag' then
				pcall(function() v.Enabled = false end)
			end
		end)
	end
-- >>> dep:charConn (bedwars:14701-14701)
	local charConn
-- >>> dep:HideNametag (bedwars:14699-14699)
	local HideNametag
-- >>> dep:checkAdjacent (bedwars:11316-11321)
	local function checkAdjacent(pos)
		for _, v in poschecklist do
			if getPlacedBlock(pos + v) then return true end
		end
		return false
	end
-- >>> dep:Transparency (bedwars:11302-11302)
	local Transparency
-- >>> dep:point1 (bedwars:11304-11304)
	local point1, point2
-- >>> dep:loadMaterials (bedwars:11339-11379)
	local function loadMaterials()
		for _, v in guidata do 
			v:Destroy() 
		end
		local suc, read = pcall(function() 
			return isfile(File.Value) and svc.httpService:JSONDecode(readfile(File.Value)) 
		end)
	
		if suc and read then
			local items = {}
			for _, v in read do 
				items[v[2]] = (items[v[2]] or 0) + 1 
			end
			
			for i, v in items do
				local holder = Instance.new('Frame')
				holder.Size = UDim2.new(1, 0, 0, 32)
				holder.BackgroundTransparency = 1
				holder.Parent = Schematica.Children
				local icon = Instance.new('ImageLabel')
				icon.Size = UDim2.fromOffset(24, 24)
				icon.Position = UDim2.fromOffset(4, 4)
				icon.BackgroundTransparency = 1
				icon.Image = bedwars.getIcon({itemType = i}, true)
				icon.Parent = holder
				local text = Instance.new('TextLabel')
				text.Size = UDim2.fromOffset(100, 32)
				text.Position = UDim2.fromOffset(32, 0)
				text.BackgroundTransparency = 1
				text.Text = (bedwars.ItemMeta[i] and bedwars.ItemMeta[i].displayName or i)..': '..v
				text.TextXAlignment = Enum.TextXAlignment.Left
				text.TextColor3 = uipallet.Text
				text.TextSize = 14
				text.FontFace = uipallet.Font
				text.Parent = holder
				table.insert(guidata, holder)
			end
			table.clear(read)
			table.clear(items)
		end
	end
-- >>> dep:getPlacedBlocksInPoints (bedwars:11323-11337)
	local function getPlacedBlocksInPoints(s, e)
		local list, blocks = {}, bedwars.BlockController:getStore()
		for x = (e.X > s.X and s.X or e.X), (e.X > s.X and e.X or s.X) do
			for y = (e.Y > s.Y and s.Y or e.Y), (e.Y > s.Y and e.Y or s.Y) do
				for z = (e.Z > s.Z and s.Z or e.Z), (e.Z > s.Z and e.Z or s.Z) do
					local vec = Vector3.new(x, y, z)
					local block = blocks:getBlockAt(vec)
					if block and block:GetAttribute('PlacedByUserId') == lplr.UserId then
						list[vec] = block
					end
				end
			end
		end
		return list
	end
-- >>> dep:save (bedwars:11381-11415)
	local function save()
		if point1 and point2 then
			local tab = getPlacedBlocksInPoints(point1, point2)
			local savetab = {}
			point1 = point1 * 3
			for i, v in tab do
				i = bedwars.BlockController:getBlockPosition(CFrame.lookAlong(point1, entitylib.character.RootPart.CFrame.LookVector):PointToObjectSpace(i * 3)) * 3
				table.insert(savetab, {
					{
						x = i.X, 
						y = i.Y, 
						z = i.Z
					}, 
					v.Name
				})
			end
			point1, point2 = nil, nil
			writefile(File.Value, svc.httpService:JSONEncode(savetab))
			notif('Schematica', 'Saved '..getTableSize(tab)..' blocks', 5)
			loadMaterials()
			table.clear(tab)
			table.clear(savetab)
		else
			local mouseinfo = bedwars.BlockBreaker.clientManager:getBlockSelector():getMouseInfo(0)
			if mouseinfo and mouseinfo.target then
				if point1 then
					point2 = mouseinfo.target.blockRef.blockPosition
					notif('Schematica', 'Selected position 2, toggle again near position 1 to save it', 3)
				else
					point1 = mouseinfo.target.blockRef.blockPosition
					notif('Schematica', 'Selected position 1', 3)
				end
			end
		end
	end
-- >>> dep:parts (bedwars:11303-11303)
	local parts, guidata, poschecklist = {}, {}, {}
-- >>> dep:load (bedwars:11417-11463)
	local function load(read)
		local mouseinfo = bedwars.BlockBreaker.clientManager:getBlockSelector():getMouseInfo(0)
		if mouseinfo and mouseinfo.target then
			local position = CFrame.new(mouseinfo.placementPosition * 3) * CFrame.Angles(0, math.rad(math.round(math.deg(math.atan2(-entitylib.character.RootPart.CFrame.LookVector.X, -entitylib.character.RootPart.CFrame.LookVector.Z)) / 45) * 45), 0)
	
			for _, v in read do
				local blockpos = bedwars.BlockController:getBlockPosition((position * CFrame.new(v[1].x, v[1].y, v[1].z)).p) * 3
				if parts[blockpos] then continue end
				local handler = bedwars.BlockController:getHandlerRegistry():getHandler(v[2]:find('wool') and getWool() or v[2])
				if handler then
					local part = handler:place(blockpos / 3, 0)
					part.Transparency = Transparency.Value
					part.CanCollide = false
					part.Anchored = true
					part.Parent = workspace
					parts[blockpos] = part
				end
			end
			table.clear(read)
	
			repeat
				if entitylib.isAlive then
					local localPosition = entitylib.character.RootPart.Position
					for i, v in parts do
						if (i - localPosition).Magnitude < 60 and checkAdjacent(i) then
							if not Schematica.Enabled then break end
							if not getItem(v.Name) then continue end
							bedwars.placeBlock(i, v.Name, false)
							task.delay(0.1, function()
								local block = getPlacedBlock(i)
								if block then
									v:Destroy()
									parts[i] = nil
								end
							end)
						end
					end
				end
				task.wait(0.1)
			until getTableSize(parts) <= 0
	
			if getTableSize(parts) <= 0 and Schematica.Enabled then
				notif('Schematica', 'Finished building', 5)
				Schematica:Toggle()
			end
		end
	end
-- >>> dep:Schematica (bedwars:11299-11299)
	local Schematica
-- >>> dep:File (bedwars:11300-11300)
	local File
-- >>> dep:targetResults (bedwars:10099-10099)
	local targetResults = {}
-- >>> dep:fixPosition (bedwars:10101-10103)
	local function fixPosition(pos)
		return bedwars.BlockController:getBlockPosition(pos) * 3
	end
-- >>> dep:Range (bedwars:10097-10097)
	local Range
-- >>> dep:LimitItem (bedwars:10098-10098)
	local LimitItem
-- >>> dep:AutoSuffocate (bedwars:10096-10096)
	local AutoSuffocate
-- >>> dep:Modes (bedwars:5552-5552)
	local Modes, ModeList = {}, {}
-- >>> dep:ModeContext (bedwars:5556-5556)
	local ModeContext = {}
-- >>> dep:modeCleanups (bedwars:5551-5551)
	local modeCleanups = {}
-- >>> dep:modeGeneration (bedwars:5550-5550)
	local modeGeneration = 0
-- >>> dep:cleanupModeResources (bedwars:5572-5593)
	local function cleanupModeResources()
		for i = #modeCleanups, 1, -1 do
			local item = modeCleanups[i]
			pcall(function()
				local itemType = typeof(item)
				if itemType == 'RBXScriptConnection' then
					item:Disconnect()
				elseif itemType == 'Instance' then
					item:Destroy()
				elseif type(item) == 'function' then
					item()
				elseif type(item) == 'table' then
					if type(item.Disconnect) == 'function' then
						item:Disconnect()
					elseif type(item.Destroy) == 'function' then
						item:Destroy()
					end
				end
			end)
		end
		table.clear(modeCleanups)
	end
-- >>> dep:testFlySessionTick (bedwars:5553-5553)
	local testFlySessionTick = 0
-- >>> dep:stopMode (bedwars:5606-5615)
	local function stopMode(reason)
		local mode = activeMode
		activeMode = nil
		modeGeneration += 1
		ModeContext.Generation = modeGeneration
		callModeHook(mode, 'End', reason)
		cleanupModeResources()
		callModeHook(mode, 'Cleanup', reason)
		ModeContext.State = nil
	end
-- >>> dep:startMode (bedwars:5617-5658)
	local function startMode(name)
		local mode = Modes[name]
		activeMode = mode
		modeGeneration += 1
		local generation = modeGeneration
		ModeContext.Generation = generation
		ModeContext.State = {}
		waitForLandingGeneration = nil

		if mode and type(mode.Once) == 'function' then
			task.spawn(function()
				callModeHook(mode, 'Once')
				if not (TestFly.Enabled and activeMode == mode and ModeContext.Generation == generation) then return end
				-- AutoWin owns the landing and releases this flight after support returns.
				if store.TestFlyJump and store.TestFlyJump.AutoWinOwned then return end

				if Notifications and Notifications.Enabled then
					-- Give GroundWatcher one frame to observe a ground -> air transition made by
					-- the final Once step before deciding whether a landing is zoom.pending.
					if entitylib.isAlive and entitylib.character.Humanoid.FloorMaterial == Enum.Material.Air then
						task.wait()
					end

					if TestFly.Enabled
						and activeMode == mode
						and ModeContext.Generation == generation
						and GroundWatcher.airborne
						and GroundWatcher.lastGroundTick >= testFlySessionTick then
						waitForLandingGeneration = generation
						return
					end
				end

				if TestFly.Enabled and activeMode == mode and ModeContext.Generation == generation then
					TestFly:Toggle()
				end
			end)
			return
		end

		callModeHook(mode, 'Start')
	end
-- >>> dep:callModeHook (bedwars:5595-5604)
	local function callModeHook(mode, hook, ...)
		local callback = mode and mode[hook]
		if type(callback) ~= 'function' then return end
		local ok, err = pcall(callback, ModeContext, ...)
		if not ok then
			bufferCall('error', 'testfly.mode.'..hook:lower(), tostring(err), {
				mode = Mode and Mode.Value or 'unknown'
			})
		end
	end
-- >>> dep:activeMode (bedwars:5549-5549)
	local activeMode
-- >>> dep:TestFly (bedwars:5138-5138)
local TestFly
-- >>> dep:Notifications (bedwars:5529-5529)
	local Notifications
-- >>> dep:GroundWatcher (bedwars:5153-5164)
local GroundWatcher = {
	grounded = false,
	airborne = false,
	lastGroundTick = 0,
	lastGroundLandTick = 0,
	takeoffPosition = nil,
	landedPosition = nil,
	airTimerTick = 0,
	Takeoff = Instance.new('BindableEvent'),
	Landed = Instance.new('BindableEvent'),
	AirTimerReset = Instance.new('BindableEvent')
}
-- ===================== bedwars modules =====================
-- >>> MODULE:TestFly (bedwars:6086-6145)
	TestFly = vape.Categories.Blatant:CreateModule({
		Name = 'TestFly',
		Function = function(callback)
			frictionTable.TestFly = callback or nil
			updateVelocity()
			if callback then
				testFlySessionTick = tick()
				pendingOnGroundTick = nil
				waitForLandingGeneration = nil
				startMode(Mode.Value)

				TestFly:Clean(svc.runService.PreSimulation:Connect(function(dt)
					callModeHook(activeMode, 'PreSimulation', dt)
				end))

				TestFly:Clean(svc.runService.Heartbeat:Connect(function(dt)
					callModeHook(activeMode, 'Heartbeat', dt)
				end))

				TestFly:Clean(svc.inputService.InputBegan:Connect(function(input)
					if not svc.inputService:GetFocusedTextBox() then
						if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
							up = 1
						elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
							down = -1
						end
					end
				end))

				TestFly:Clean(svc.inputService.InputEnded:Connect(function(input)
					if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
						up = 0
					elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
						down = 0
					end
				end))

				if svc.inputService.TouchEnabled then
					pcall(function()
						local jumpButton = lplr.PlayerGui.TouchGui.TouchControlFrame.JumpButton
						TestFly:Clean(jumpButton:GetPropertyChangedSignal('ImageRectOffset'):Connect(function()
							up = jumpButton.ImageRectOffset.X == 146 and 1 or 0
						end))
					end)
				end
			else
				waitForLandingGeneration = nil
				stopMode('disable')
				-- A manual disable still allows the current flight to report after
				-- landing without forcing TestFly to remain enabled.
				if Notifications and Notifications.Enabled and GroundWatcher.airborne and GroundWatcher.lastGroundTick >= testFlySessionTick then
					pendingOnGroundTick = GroundWatcher.lastGroundTick
				end
			end
		end,
		ExtraText = function()
			return Mode.Value
		end,
		Tooltip = 'Lets you fly using experimental flight modes.\nChoose Heatseeker, bounce, vertical clip or jump flight.'
	})
-- >>> MODULE:SafeWalk (bedwars:6528-6573)
	local SafeWalk
	SafeWalk = vape.Categories.World:CreateModule({
		Name = 'SafeWalk',
		Tab = 'Move',
		Function = function(callback)
			if callback then
				if not module then
					local suc = pcall(function()
						module = require(lplr.PlayerScripts.PlayerModule).controls
					end)
					if not suc then module = {} end
				end

				local old = module.moveFunction
				-- No movement function to wrap (the controls did not load): nothing to hook.
				if type(old) ~= 'function' then return end
				local state = {Active = true, Previous = old}
				current = state
				state.Hook = function(self, vec, face)
					if state.Active and entitylib ~= nil and entitylib.isAlive then
						ph.rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
						local root = entitylib.character.RootPart
						local movedir = root.Position + vec
						local ray = workspace:Raycast(movedir, Vector3.new(0, -15, 0), ph.rayCheck)
						if not ray then
							local check = workspace:Blockcast(root.CFrame, Vector3.new(3, 1, 3), Vector3.new(0, -(entitylib.character.HipHeight + 1), 0), ph.rayCheck)
							if check then
								vec = (check.Instance:GetClosestPointOnSurface(movedir) - root.Position) * Vector3.new(1, 0, 1)
							end
						end
					end

					return old(self, vec, face)
				end
				module.moveFunction = state.Hook
			else
				if current then
					current.Active = false
					if module and module.moveFunction == current.Hook then
						module.moveFunction = current.Previous
					end
					current = nil
				end
			end
		end,
		Tooltip = 'Prevents you from walking off ledges.'
	})
-- >>> MODULE:AutoSuffocate (bedwars:10105-10153)
	AutoSuffocate = vape.Categories.World:CreateModule({
		Name = 'AutoSuffocate',
		Function = function(callback)
			if callback then
				repeat
					local item = store.hand.toolType == 'block' and store.hand.tool.Name or not LimitItem.Enabled and getWool()
	
					if item then
						local plrs = entitylib.AllPosition({
							Part = 'RootPart',
							Range = Range.Value,
							Players = true,
							Cache = true,
							Output = targetResults
						})
	
						for _, ent in plrs do
							local needPlaced = {}
	
							for _, side in Enum.NormalId:GetEnumItems() do
								side = Vector3.fromNormalId(side)
								if side.Y ~= 0 then continue end
	
								side = fixPosition(ent.RootPart.Position + side * 2)
								if not getPlacedBlock(side) then
									table.insert(needPlaced, side)
								end
							end
	
							if #needPlaced < 3 then
								table.insert(needPlaced, fixPosition(ent.Head.Position))
								table.insert(needPlaced, fixPosition(ent.RootPart.Position - Vector3.new(0, 1, 0)))
	
								for _, pos in needPlaced do
									if not getPlacedBlock(pos) then
										task.spawn(bedwars.placeBlock, pos, item)
										break
									end
								end
							end
						end
					end
	
					task.wait(0.09)
				until not AutoSuffocate.Enabled
			end
		end,
		Tooltip = 'Boxes in nearby players who are already half walled in.\nUses the block you hold, or your wool if allowed.'
	})
-- >>> MODULE:Schematica (bedwars:11465-11498)
	Schematica = vape.Categories.World:CreateModule({
		Name = 'Schematica',
		Function = function(callback)
			if callback then
				if not File.Value:find('.json') then
					notif('Schematica', 'Invalid file', 3)
					Schematica:Toggle()
					return
				end
	
				if Mode.Value == 'Save' then
					save()
					Schematica:Toggle(nil, true)
				else
					local suc, read = pcall(function() 
						return isfile(File.Value) and svc.httpService:JSONDecode(readfile(File.Value)) 
					end)
	
					if suc and read then
						load(read)
					else
						notif('Schematica', 'Missing / corrupted file', 3)
						Schematica:Toggle()
					end
				end
			else
				for _, v in parts do 
					v:Destroy() 
				end
				table.clear(parts)
			end
		end,
		Tooltip = 'Saves your builds to a file and rebuilds them for you.\nShows a see-through preview while it places the blocks.'
	})
-- >>> MODULE:HideNametag (bedwars:14734-14754)
	HideNametag = vape.Categories.Utility:CreateModule({
		Name = 'HideNametag',
		Tab = 'Visual',
		Function = function(callback)
			if callback then
				setNametagEnabled(false)
				charConn = lplr.CharacterAdded:Connect(function(char)
					if HideNametag.Enabled then
						setNametagEnabled(false, char)
					end
				end)
			else
				if charConn then
					pcall(function() charConn:Disconnect() end)
					charConn = nil
				end
				setNametagEnabled(true)
			end
		end,
		Tooltip = 'Hides the nametag over your own head.'
	})
-- >>> MODULE:NightmareEmote (bedwars:4559-4578)
	NightmareEmote = vape.Categories.Utility:CreateModule({
		Name = 'NightmareEmote',
		Tab = 'Visual',
		Function = function(callback)
			if not callback then return end

			playEmote()

			--[[ Deferred rather than called straight from here: this IS the enable callback,
			and toggling from inside it would re-enter the module's own state machine
			mid-transition. One step later the enable has settled and the off is a normal
			toggle. ]]
			task.defer(function()
				if NightmareEmote.Enabled then
					NightmareEmote:Toggle(nil, true)
				end
			end)
		end,
		Tooltip = 'Plays the Nightmare emote until you move.'
	})
-- ===================== universal shared helpers =====================
-- universal entity library integration (shared by ESP/esp.Chams/targeting helpers)
run(function()
	entitylib.getUpdateConnections = function(ent)
		local hum = ent.Humanoid
		return {
			hum:GetPropertyChangedSignal('Health'),
			hum:GetPropertyChangedSignal('MaxHealth')
		}
	end

	entitylib.getEntityState = function(ent)
		local friend = ent.Player and isFriend(ent.Player) or nil
		local target = ent.Player and isTarget(ent.Player) or nil
		return entitylib.targetCheck(ent), friend, target
	end

	entitylib.targetCheck = function(ent)
		if ent.TeamCheck then
			return ent:TeamCheck()
		end
		if ent.NPC then return true end
		if isFriend(ent.Player) then return false end
		if vape.Categories.Main.Options['Teams by server'].Enabled then
			if not lplr.Team then return true end
			if not ent.Player.Team then return true end
			if ent.Player.Team ~= lplr.Team then return true end
			return #ent.Player.Team:GetPlayers() == #svc.playersService:GetPlayers()
		end
		return true
	end
	entitylib.refresh()

	entitylib.getEntityColor = function(ent)
		ent = ent.Player
		if not (ent and vape.Categories.Main.Options['Use team color'].Enabled) then return end
		if isFriend(ent, true) then
			return Color3.fromHSV(vape.Categories.Friends.Options['Friends color'].Hue, vape.Categories.Friends.Options['Friends color'].Sat, vape.Categories.Friends.Options['Friends color'].Value)
		end
		return tostring(ent.TeamColor) ~= 'White' and ent.TeamColor.Color or nil
	end

	vape:Clean(function()
		entitylib.kill()
		entitylib = nil
	end)
	vape:Clean(vape.Categories.Friends.Update.Event:Connect(function()
		targetStateCacheDirty = true
		entitylib.refresh()
	end))
	vape:Clean(vape.Categories.Targets.Update.Event:Connect(function()
		targetStateCacheDirty = true
		entitylib.refresh()
	end))
	vape:Clean(entitylib.Events.LocalAdded:Connect(updateVelocity))
	vape:Clean(workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(function()
		gameCamera = workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera')
	end))
end)
-- >>> dep:function loaderStyle.reading(p (universal:212-222)
function loaderStyle.reading(parent, text)
	local label = Instance.new('TextLabel')
	label.Size = UDim2.fromScale(1, 1)
	label.TextSize = 15
	label.RichText = true
	label.Text = text
	loaderStyle.box(label)
	loaderStyle.text(label, 'SemiBold')
	label.Parent = parent
	return label
end
-- >>> dep:function loaderStyle.unit(valu (universal:207-209)
function loaderStyle.unit(value, unit)
	return value..' <font color="'..loaderStyle.SubHex..'">'..unit..'</font>'
end
-- >>> dep:function loaderStyle.text(labe (universal:197-204)
function loaderStyle.text(label, role)
	label.TextColor3 = loaderStyle.Text
	label.TextStrokeTransparency = 1
	local fonts = vape.Libraries.fonts
	if fonts and fonts.track then
		fonts.track(label, role or 'Medium')
	end
end
-- >>> dep:function loaderStyle.border(ob (universal:189-194)
function loaderStyle.border(obj, opacity)
	local stroke = obj:FindFirstChildOfClass('UIStroke')
	if stroke then
		stroke.Enabled = opacity > 0
	end
end
-- >>> dep:function loaderStyle.box(obj,  (universal:172-186)
function loaderStyle.box(obj, radius)
	obj.BackgroundColor3 = loaderStyle.Background
	obj.BackgroundTransparency = loaderStyle.Transparency
	obj.BorderSizePixel = 0
	local corner = Instance.new('UICorner')
	corner.CornerRadius = radius or UDim.new(0, 8)
	corner.Parent = obj
	local stroke = Instance.new('UIStroke')
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = loaderStyle.Orange
	stroke.Thickness = 1
	stroke.Transparency = 0.55
	stroke.Parent = obj
	return stroke, corner
end
-- >>> dep:function loaderStyle.backgroun (universal:166-170)
function loaderStyle.backgroundOption(props)
	props.DefaultHue, props.DefaultSat, props.DefaultValue = loaderStyle.Hue, loaderStyle.Sat, loaderStyle.Value
	props.DefaultOpacity = 0.7
	return props
end
-- >>> dep:targetStateCacheDirty (universal:239-239)
local targetStateCacheDirty = true
-- >>> dep:rebuildTargetStateCaches (universal:241-257)
local function rebuildTargetStateCaches()
	table.clear(friendNames)
	table.clear(targetNames)
	local friends = vape.Categories.Friends
	local targets = vape.Categories.Targets
	if friends and friends.ListEnabled then
		for _, name in friends.ListEnabled do
			friendNames[name] = true
		end
	end
	if targets and targets.ListEnabled then
		for _, name in targets.ListEnabled do
			targetNames[name] = true
		end
	end
	targetStateCacheDirty = false
end
-- >>> dep:friendNames (universal:238-238)
local friendNames, targetNames = {}, {}
-- >>> dep:ensureTargetStateCaches (universal:259-263)
local function ensureTargetStateCaches()
	if targetStateCacheDirty then
		rebuildTargetStateCaches()
	end
end
-- >>> dep:itemAdded (universal:8510-8527)
	local function itemAdded(v, plr)
		if v:IsA('Tool') then
			local check = v:FindFirstChild('IsGun') and 'sheriff' or v:FindFirstChild('KnifeServer') and 'murderer' or nil
			check = check or v.Name:lower():find('knife') and 'murderer' or v.Name:lower():find('gun') and 'sheriff' or nil
	
			if check == 'murderer' and plr ~= murderer then
				murderer = plr
				if plr.Character then
					entitylib.refresh()
				end
			elseif check == 'sheriff' and plr ~= sheriff then
				sheriff = plr
				if plr.Character then
					entitylib.refresh()
				end
			end
		end
	end
-- >>> dep:playerAdded (universal:8529-8546)
	local function playerAdded(plr)
		MurderMystery:Clean(plr.DescendantAdded:Connect(function(v)
			itemAdded(v, plr)
		end))
	
		local pack = plr:FindFirstChildWhichIsA('Backpack')
		if pack then
			for _, v in pack:GetChildren() do
				itemAdded(v, plr)
			end
		end
	
		if plr.Character then
			for _, v in plr.Character:GetChildren() do
				itemAdded(v, plr)
			end
		end
	end
-- >>> dep:murderer (universal:8508-8508)
	local murderer, sheriff, oldtargetable, oldgetcolor
-- >>> dep:isFriend (universal:265-275)
local function isFriend(plr, recolor)
	ensureTargetStateCaches()
	if vape.Categories.Friends.Options['Use friends'].Enabled then
		local friend = friendNames[plr.Name] and true
		if recolor then
			friend = friend and vape.Categories.Friends.Options['Recolor visuals'].Enabled
		end
		return friend
	end
	return nil
end
-- >>> dep:MurderMystery (universal:8507-8507)
	local MurderMystery
-- >>> dep:Modifier (universal:7628-7628)
	local Modifier
-- >>> dep:errorTrace (universal:36-44)
-- >>> dep:originalRanges (universal:7630-7630)
	prompt.originalRanges = {}
-- >>> dep:setPromptRange (universal:7635-7640)
local prompt = {}
	function prompt.setPromptRange(prompt)
		if prompt.originalRanges[prompt] == nil then
			prompt.originalRanges[prompt] = prompt.MaxActivationDistance
		end
		prompt.MaxActivationDistance = Range.Value
	end
-- >>> dep:callWithThreadFix (universal:66-86)
-- >>> dep:updatePrompt (universal:7644-7649)
	function prompt.updatePrompt(prompt)
		if not prompt or not prompt:IsA('ProximityPrompt') then return end
		callWithThreadFix(function()
			prompt.setPromptRange(prompt)
		end)
	end
-- >>> dep:updateAllPrompts (universal:7652-7660)
	function prompt.updateAllPrompts()
		callWithThreadFix(function()
			for _, prompt in workspace:GetDescendants() do
				if prompt:IsA('ProximityPrompt') then
					pcall(prompt.setPromptRange, prompt)
				end
			end
		end)
	end
-- >>> dep:thread (universal:7632-7632)
	local thread
-- >>> dep:restorePrompts (universal:7670-7693)
	function prompt.restorePrompts()
		if thread then
			task.cancel(thread)
			thread = nil
		end

		for prompt, distance in prompt.originalRanges do
			callWithThreadFix(function()
				if prompt.Parent then
					prompt.MaxActivationDistance = distance
				end
			end)
		end
		table.clear(prompt.originalRanges)

		for prompt, duration in modified do
			callWithThreadFix(function()
				if prompt.Parent then
					prompt.HoldDuration = duration
				end
			end)
		end
		table.clear(modified)
	end
-- >>> dep:svc.proxService (universal:118-118)
svc.proxService = cloneref(game:GetService('ProximityPromptService'))
-- >>> dep:applyHoldDuration (universal:7662-7668)
	function prompt.applyHoldDuration(prompt)
		if not prompt or not prompt:IsA('ProximityPrompt') then return end
		if modified[prompt] == nil then
			modified[prompt] = prompt.HoldDuration
		end
		prompt.HoldDuration = modified[prompt] * (Modifier.Value / 100)
	end
-- >>> dep:PromptChanger (universal:7626-7626)
	-- prompt.PromptChanger (dep)
-- >>> dep:svc.textChatService (universal:115-115)
-- >>> dep:chat.spamGeneration (universal:7865-7865)
local chat = {}
chat.spamGeneration = 0
-- >>> dep:chat.oldchat (universal:7862-7862)
-- chat.oldchat
-- >>> dep:svc.coreGui (universal:117-117)
-- >>> dep:chat.RandomList (universal:7861-7861)
chat.RandomList = {}
-- >>> dep:Lines (universal:7857-7857)
local Lines
-- >>> dep:chat.Hide (universal:7860-7860)
-- chat.Hide
-- >>> dep:chat.ChatSpammer (universal:7856-7856)
-- chat.ChatSpammer
-- >>> dep:anim.Speed (universal:7489-7489)
	-- anim.Speed
-- >>> dep:anim.Priority (universal:7488-7488)
	-- anim.Priority
-- >>> dep:playAnimation (universal:7492-7516)
	local function playAnimation(char)
		local animcheck = anim
		if animcheck then
			anim = nil
			animcheck:Stop()
		end
	
		local suc, res = pcall(function()
			anim = char.Humanoid.Animator:LoadAnimation(animobject)
		end)
	
		if suc then
			local currentanim = anim
			anim.Priority = Enum.AnimationPriority[anim.Priority.Value]
			anim:Play()
			anim:AdjustSpeed(anim.Speed.Value)
			anim.AnimationPlayer:Clean(anim.Stopped:Connect(function()
				if currentanim == anim then
					anim:Play()
				end
			end))
		else
			notif('AnimationPlayer', 'failed to load anim : '..(res or 'invalid animation id'), 5, 'warning')
		end
	end
-- >>> dep:anim (universal:7490-7490)
	local anim, animobject
-- >>> dep:anim.IDBox (universal:7487-7487)
	-- anim.IDBox
-- >>> dep:anim.AnimationPlayer (universal:7486-7486)
	-- anim.AnimationPlayer
-- >>> dep:anim.AntiRagdoll (universal:7580-7580)
	-- anim.AntiRagdoll
-- >>> dep:anim.Rejoin (universal:8013-8013)
	-- anim.Rejoin
-- >>> dep:svc.guiService (universal:113-113)
-- >>> dep:anim.AutoRejoin (universal:7600-7600)
	-- anim.AutoRejoin
-- >>> dep:sph.serverPageKey (universal:398-400)
function sph.serverPageKey(pointer, filter)
	return tostring(game.PlaceId)..'|'..tostring(filter or 'Descending')..'|'..tostring(pointer or '')
end
-- >>> dep:sph.serverPageCache (universal:396-396)
sph.serverPageCache, sph.serverPageInflight = {}, {}
-- >>> dep:sph.recordServerCache (universal:402-407)
function sph.recordServerCache(key, state) end
-- >>> dep:svc.teleportService (universal:111-111)
svc.teleportService = cloneref(game:GetService('TeleportService'))
-- >>> dep:sph.getServerPage (universal:409-455)
function sph.getServerPage(pointer, filter)
	local key = sph.serverPageKey(pointer, filter)
	local now = tick()
	local cached = sph.serverPageCache[key]
	if cached and cached.expires > now then
		sph.recordServerCache(key, 'hit')
		return cached.data, cached.body
	end

	local waiting = sph.serverPageInflight[key]
	if waiting then
		local deadline = now + 10
		while not waiting.done and tick() < deadline do
			task.wait(0.05)
		end
		if waiting.done and waiting.data then
			sph.recordServerCache(key, 'joined')
			return waiting.data, waiting.body
		end
		sph.recordServerCache(key, 'timeout')
		return nil, nil
	end

	waiting = {done = false}
	sph.serverPageInflight[key] = waiting
	sph.recordServerCache(key, 'miss')
	local url = 'https://games.roblox.com/v1/games/'..game.PlaceId..'/servers/Public?sortOrder='..(filter == 'Ascending' and 1 or 2)..'&excludeFullGames=true&limit=100'..(pointer and '&cursor='..pointer or '')
	local requestOk, body = pcall(function()
		return game:HttpGet(url)
	end)
	local parseOk, data = false, nil
	if requestOk then
		parseOk, data = pcall(function()
			return svc.httpService:JSONDecode(body)
		end)
	end
	if parseOk and type(data) == 'table' and type(data.data) == 'table' then
		waiting.data, waiting.body = data, body
		sph.serverPageCache[key] = {data = data, body = body, expires = tick() + 60}
	end
	waiting.done = true
	sph.serverPageInflight[key] = nil
	if waiting.data then
		return waiting.data, waiting.body
	end
	return nil, nil
end
-- >>> dep:sph.attempted (universal:395-395)
sph.visited, sph.attempted, sph.tpSwitch = {}, {}, false
-- >>> dep:sph.serverHop (universal:457-486)
function sph.serverHop(pointer, filter)
	sph.visited = shared.vapeserverhoplist and shared.vapeserverhoplist:split('/') or {}
	if not table.find(sph.visited, game.JobId) then
		table.insert(sph.visited, game.JobId)
	end
	if not pointer then
		notif('Catvape', 'Searching for an available server.', 2)
	end

	local data = sph.getServerPage(pointer, filter)
	if data and data.data then
		for _, v in data.data do
			if tonumber(v.playing) < svc.playersService.MaxPlayers and not table.find(sph.visited, v.id) and not table.find(sph.attempted, v.id) then
				table.insert(sph.attempted, v.id)

				notif('Catvape', 'Found! Teleporting.', 5)
				svc.teleportService:TeleportToPlaceInstance(game.PlaceId, v.id)
				return
			end
		end

		if data.nextPageCursor then
			sph.serverHop(data.nextPageCursor, filter)
		else
			notif('Catvape', 'Failed to find an available server.', 5, 'warning')
		end
	else
		notif('Catvape', 'Failed to grab servers. ('..(data and data.errors[1].message or 'no data')..')', 5, 'warning')
	end
end
-- >>> dep:Sort (universal:8035-8035)
	local Sort
-- >>> dep:ServerHop (universal:8034-8034)
	local ServerHop
-- >>> dep:ZoomUnlocker (universal:10237-10237)
	-- zoom.ZoomUnlocker (dep)
-- >>> dep:MaxZoom (universal:10238-10238)
	-- zoom.MaxZoom (dep)
-- >>> dep:FALLBACK_MAX_ZOOM (universal:10245-10245)
	zoom.FALLBACK_MAX_ZOOM = 14
-- >>> dep:pending (universal:10270-10270)
	zoom.pending = false
-- >>> dep:zoomConn (universal:10239-10239)
	-- zoom.zoomConn (dep)
-- >>> dep:queueZoom (universal:10282-10286)
local zoom = {}
	function zoom.queueZoom()
		if zoom.pending then return end
		zoom.pending = true
		task.defer(zoom.applyZoom)
	end
-- >>> dep:defaultMaxZoom (universal:10247-10253)
	function zoom.defaultMaxZoom()
		local ok, val = pcall(function()
			return cloneref(game:GetService('StarterPlayer')).CameraMaxZoomDistance
		end)
		if ok and type(val) == 'number' and val > 0 then return val end
		return zoom.FALLBACK_MAX_ZOOM
	end
-- >>> dep:applyZoom (universal:10272-10280)
	function zoom.applyZoom()
		zoom.pending = false
		if not (zoom.ZoomUnlocker and zoom.ZoomUnlocker.Enabled) then return end
		if lplr.CameraMinZoomDistance >= lplr.CameraMaxZoomDistance then return end
		--[[ Guarded so our own write doesn't re-enter through the changed signal below. ]]
		if lplr.CameraMaxZoomDistance ~= zoom.MaxZoom.Value then
			lplr.CameraMaxZoomDistance = zoom.MaxZoom.Value
		end
	end
-- >>> dep:flag (universal:5477-5477)
	-- light.flag (dep)
-- >>> dep:oldsettings (universal:5476-5476)
	light.oldsettings = {}
-- >>> dep:svc.lightingService (universal:109-109)
-- >>> dep:Fullbright (universal:5474-5474)
	local Fullbright
-- >>> dep:ChangeLighting (universal:5482-5493)
local light = {}
	function light.ChangeLighting(prop)
		if light.flag then
			return
		end
	
		light.flag = true
		svc.lightingService.Ambient = Color3.new(1, 1, 1)
		svc.lightingService.OutdoorAmbient = Color3.new(1, 1, 1)
		svc.lightingService.Brightness = 3
		svc.runService.RenderStepped:Wait()
		light.flag = false
	end
-- >>> dep:wheelpositions (universal:5543-5547)
local chair = {}
	chair.wheelpositions = {
		Vector3.new(-0.8, -0.6, -0.18),
		Vector3.new(0.1, -0.6, -0.88),
		Vector3.new(0, -0.6, 0.7)
	}
-- >>> dep:svc.tweenService (universal:108-108)
-- >>> dep:movingsound (universal:5550-5550)
	-- chair.movingsound (dep)
-- >>> dep:flyingsound (universal:5551-5551)
	-- chair.flyingsound (dep)
-- >>> dep:currenttween (universal:5549-5549)
	-- chair.currenttween (dep)
-- >>> dep:chairanim (universal:5552-5552)
	-- chair.chairanim (dep)
-- >>> dep:chair (universal:5553-5553)
	-- chair.chair (dep)
-- >>> dep:GamingChair (universal:5541-5541)
	chair.GamingChair = {Enabled = false}
-- >>> dep:Texture (universal:6192-6192)
	local Texture
-- >>> dep:Rots (universal:6193-6193)
	chair.Rots = {}
-- >>> dep:Mesh (universal:6191-6191)
	-- chair.Mesh (dep)
-- >>> dep:removeMesh (universal:6229-6234)
	function chair.chair.removeMesh(ent)
		if chair.models[ent.RootPart] then 
			chair.models[ent.RootPart]:Destroy()
			chair.models[ent.RootPart] = nil
		end
	end
-- >>> dep:models (universal:6194-6194)
	chair.models = {}
-- >>> dep:modelGeneration (universal:6195-6195)
	chair.modelGeneration = 0
-- >>> dep:addMesh (universal:6197-6227)
	function chair.chair.addMesh(ent, generation)
		if generation and generation ~= chair.modelGeneration then return end
		if not (tr.PlayerModel and tr.PlayerModel.Enabled) then return end
		if vape.ThreadFix then 
			setthreadidentity(8)
		end
		local root = ent.RootPart
		if not (root and root.Parent) then return end
		local previous = chair.models[root]
		if previous then
			pcall(function() previous:Destroy() end)
			chair.models[root] = nil
		end
		local part = Instance.new('Part')
		part.Size = Vector3.new(3, 3, 3)
		part.CFrame = root.CFrame * CFrame.Angles(math.rad(chair.Rots[1].Value), math.rad(chair.Rots[2].Value), math.rad(chair.Rots[3].Value))
		part.CanCollide = false
		part.CanQuery = false
		part.Massless = true
		part.Parent = workspace
		local meshd = Instance.new('SpecialMesh')
		meshd.MeshId = chair.Mesh.Value
		meshd.TextureId = Texture.Value
		meshd.Scale = Vector3.one * Scale.Value
		meshd.Parent = part
		local weld = Instance.new('WeldConstraint')
		weld.Part0 = part
		weld.Part1 = root
		weld.Parent = part
		chair.models[root] = part
	end
-- >>> dep:PlayerModel (universal:6188-6188)
	-- tr.PlayerModel (dep)
-- >>> dep:Local (universal:6190-6190)
	-- tr.Local (dep)
-- >>> dep:addCandidate (universal:6560-6565)
	local function addCandidate(v)
		if not tr.Names[v.Name] then return end
		if tr.Search and tr.Search.Enabled then
			tr.Add(v)
		end
	end
-- >>> dep:Search (universal:6532-6532)
	-- tr.Search (dep)
-- >>> dep:Names (universal:6538-6538)
	tr.Names = {}
-- >>> dep:Add (universal:6542-6557)
	function tr.Add(v)
		if Reference[v] then return end
		if not table.find(List.ListEnabled, v.Name) then return end
		if v:IsA('BasePart') or v:IsA('Model') then
			local size = v:IsA('Model') and v:GetExtentsSize() or v.Size
			local box = Instance.new('BoxHandleAdornment')
			box.AlwaysOnTop = true
			box.Adornee = v
			box.Size = size.Magnitude > 0.4 and size or Vector3.one
			box.ZIndex = 0
			box.Transparency = FillTransparency.Value
			box.Color3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
local esp = {}
			box.Parent = esp.Folder
			Reference[v] = box
			end
	end
-- >>> dep:Arrows (universal:4104-4104)
	-- tr.Arrows (dep)
-- >>> dep:removeTags (universal:381-384)
-- >>> dep:loaderStyle (universal:151-157)
local loaderStyle = {
	Orange = Color3.fromRGB(240, 122, 31),
	Text = Color3.fromRGB(230, 230, 230),
	SubText = Color3.fromRGB(163, 161, 157),
	Pressed = Color3.fromRGB(20, 20, 20),
	Transparency = 0.3
}
-- >>> dep:getfontsize (universal:140-140)
-- >>> dep:Waypoints (universal:7343-7343)
	-- tr.Waypoints (dep)
-- >>> dep:Scale (universal:7347-7347)
	local Scale
-- >>> dep:FontOption (universal:7344-7344)
	-- tr.FontOption (dep)
-- >>> dep:StartPosition (universal:7139-7139)
	-- tr.StartPosition (dep)
-- >>> dep:EndPosition (universal:7140-7140)
	-- tr.EndPosition (dep)
-- >>> dep:DistanceLimit (universal:7144-7144)
	-- tr.DistanceLimit (dep)
-- >>> dep:DistanceColor (universal:7142-7142)
	-- tr.DistanceColor (dep)
-- >>> dep:Distance (universal:7143-7143)
	-- tr.Distance (dep)
-- >>> dep:Behind (universal:7145-7145)
	-- tr.Behind (dep)
-- >>> dep:Tracers (universal:7135-7135)
	-- tr.Tracers (dep)
-- >>> dep:Loop (universal:7185-7222)
	function tr.Loop()
		-- hidden while the menu is open; the first frame after it closes redraws them
		if clickGuiOpen() then
			for _, EntityTracer in Reference do
				if EntityTracer.Visible then EntityTracer.Visible = false end
			end
			return
		end
		local screenSize = vape.gui.AbsoluteSize
		local startVector = tr.StartPosition.Value == 'Mouse' and svc.inputService:GetMouseLocation() or Vector2.new(screenSize.X / 2, (tr.StartPosition.Value == 'Middle' and screenSize.Y / 2 or screenSize.Y))
	
		for ent, EntityTracer in Reference do
			local distance = entitylib.isAlive and (entitylib.character.RootPart.Position - ent.RootPart.Position).Magnitude
			if tr.Distance.Enabled and distance then
				if distance < tr.DistanceLimit.ValueMin or distance > tr.DistanceLimit.ValueMax then
					EntityTracer.Visible = false
					continue
				end
			end
	
			local pos = ent[tr.EndPosition.Value == 'Torso' and 'RootPart' or 'Head'].Position
			local rootPos, rootVis = gameCamera:WorldToViewportPoint(pos)
			if not rootVis and tr.Behind.Enabled then
				local tempPos = gameCamera.CFrame:PointToObjectSpace(pos)
				tempPos = CFrame.Angles(0, 0, (math.atan2(tempPos.Y, tempPos.X) + math.pi)):VectorToWorldSpace((CFrame.Angles(0, math.rad(89.9), 0):VectorToWorldSpace(Vector3.new(0, 0, -1))))
				rootPos = gameCamera:WorldToViewportPoint(gameCamera.CFrame:pointToWorldSpace(tempPos))
				rootVis = true
			end
	
			local endVector = Vector2.new(rootPos.X, rootPos.Y)
			EntityTracer.Visible = rootVis
			EntityTracer.From = startVector
			EntityTracer.To = endVector
			if tr.DistanceColor.Enabled and distance then
				EntityTracer.Color = Color3.fromHSV(math.min((distance / 128) / 2.8, 0.4), 0.89, 0.75)
			end
		end
	end
-- >>> dep:ColorFunc (universal:7177-7183)
	function tr.ColorFunc(hue, sat, val)
		if tr.DistanceColor.Enabled then return end
		local tracerColor = Color3.fromHSV(hue, sat, val)
		for ent, EntityTracer in Reference do
			EntityTracer.Color = entitylib.getEntityColor(ent) or tracerColor
		end
	end
-- >>> dep:Walls (universal:4634-4634)
	local Walls
-- >>> dep:OutlineTransparency (universal:4632-4632)
	local OutlineTransparency
-- >>> dep:OutlineColor (universal:4630-4630)
	local OutlineColor
-- >>> dep:Folder (universal:4636-4636)
	esp.Folder = Instance.new('Folder')
-- >>> dep:FillTransparency (universal:4631-4631)
	local FillTransparency
-- >>> dep:Removed (universal:4680-4695)
	local function Removed(ent)
		if Reference[ent] then
			if vape.ThreadFix then
				setthreadidentity(8)
			end
			if type(Reference[ent]) == 'table' then
				for _, v in Reference[ent] do
					v:Destroy()
				end
				table.clear(Reference[ent])
			else
				Reference[ent]:Destroy()
			end
			Reference[ent] = nil
		end
	end
-- >>> dep:FillColor (universal:4629-4629)
	local FillColor
-- >>> dep:Chams (universal:4626-4626)
	-- esp.Chams (dep)
-- >>> dep:Added (universal:4639-4678)
	local function Added(ent)
		if not Targets.Players.Enabled and ent.Player then return end
		if not Targets.NPCs.Enabled and ent.NPC then return end
		if esp.Teammates.Enabled and (not ent.Targetable) and (not ent.Friend) then return end
		if vape.ThreadFix then
			setthreadidentity(8)
		end
	
		if Mode.Value == 'Highlight' then
			local cham = Instance.new('Highlight')
			cham.Adornee = ent.Character
			cham.DepthMode = Enum.HighlightDepthMode[Walls.Enabled and 'AlwaysOnTop' or 'Occluded']
			cham.FillColor = entitylib.getEntityColor(ent) or Color3.fromHSV(FillColor.Hue, FillColor.Sat, FillColor.Value)
			cham.OutlineColor = Color3.fromHSV(OutlineColor.Hue, OutlineColor.Sat, OutlineColor.Value)
			cham.FillTransparency = FillTransparency.Value
			cham.OutlineTransparency = OutlineTransparency.Value
			cham.Parent = esp.Folder
			Reference[ent] = cham
		else
			local chams = {}
			for _, v in ent.Character:GetChildren() do
				if v:IsA('BasePart') and (ent.NPC or v.Name:find('Arm') or v.Name:find('Leg') or v.Name:find('Hand') or v.Name:find('Feet') or v.Name:find('Torso') or v.Name == 'Head') then
					local box = Instance.new(v.Name == 'Head' and 'SphereHandleAdornment' or 'BoxHandleAdornment')
					if v.Name == 'Head' then
						box.Radius = 0.75
					else
						box.Size = v.Size
					end
					box.AlwaysOnTop = Walls.Enabled
					box.Adornee = v
					box.ZIndex = 0
					box.Transparency = FillTransparency.Value
					box.Color3 = entitylib.getEntityColor(ent) or Color3.fromHSV(FillColor.Hue, FillColor.Sat, FillColor.Value)
					box.Parent = esp.Folder
					table.insert(chams, box)
				end
			end
			Reference[ent] = chams
		end
	end
-- >>> dep:Teammates (universal:4875-4875)
	-- esp.Teammates (dep)
-- >>> dep:passes (universal:4910-4915)
	local function passes(ent)
		if not Targets.Players.Enabled and ent.Player then return false end
		if not Targets.NPCs.Enabled and ent.NPC then return false end
		if esp.Teammates.Enabled and (not ent.Targetable) and (not ent.Friend) then return false end
		return true
	end
-- >>> dep:newDrawing (universal:4969-4976)
	local function newDrawing(kind, props)
		local obj = Drawing.new(kind)
		for key, value in props do
			obj[key] = value
		end
		esp.Written[obj] = table.clone(props)
		return obj
	end
-- >>> dep:addHealthBar (universal:4979-4982)
	local function addHealthBar(EntityESP)
		EntityESP.HealthBorder = newDrawing('Line', {Thickness = 4, Transparency = 0.5, ZIndex = 1, Color = Color3.new()})
		EntityESP.HealthLine = newDrawing('Line', {Thickness = 2, ZIndex = 2})
	end
-- >>> dep:Name (universal:4872-4872)
	local Name
-- >>> dep:LineWidth (universal:4863-4863)
	-- esp.LineWidth (dep)
-- >>> dep:HealthBar (universal:4869-4869)
	-- esp.HealthBar (dep)
-- >>> dep:Filled (universal:4870-4870)
	local Filled
-- >>> dep:BoundingBox (universal:4868-4868)
	-- esp.BoundingBox (dep)
-- >>> dep:Background (universal:4874-4874)
	local Background
-- >>> dep:healthFraction (universal:4917-4922)
	local function healthFraction(ent)
		local maxHealth = ent.MaxHealth
		if type(maxHealth) ~= 'number' or maxHealth <= 0 then return 1 end
		local fraction = (ent.Health or maxHealth) / maxHealth
		return fraction == fraction and math.clamp(fraction, 0, 1) or 1
	end
-- >>> dep:TargetColor (universal:4877-4877)
	-- esp.TargetColor (dep)
-- >>> dep:FriendColor (universal:4867-4867)
	-- esp.FriendColor (dep)
-- >>> dep:ColorMode (universal:4865-4865)
	-- esp.ColorMode (dep)
-- >>> dep:Color (universal:4866-4866)
	local Color
-- >>> dep:HurtEffect (universal:4871-4871)
	-- esp.HurtEffect (dep)
-- >>> dep:HURT_TIME (universal:4883-4883)
	local HURT_TIME = 0.5
-- >>> dep:HURT_COLOR (universal:4884-4884)
	local HURT_COLOR = Color3.fromRGB(255, 40, 40)
-- >>> dep:hurtTint (universal:4925-4935)
	local function hurtTint(ent, now, color)
		local hurt = esp.HurtEffect.Enabled and esp.HurtAt[ent]
		if hurt then
			local alpha = 1 - (now - hurt) / HURT_TIME
			if alpha > 0 then
				return color:Lerp(HURT_COLOR, alpha)
			end
			esp.HurtAt[ent] = nil
		end
		return color
	end
-- >>> dep:baseColor (universal:4949-4959)
	local function baseColor(ent)
		if esp.OverrideTarget.Enabled then
			return Color3.fromHSV(esp.TargetColor.Hue, esp.TargetColor.Sat, esp.TargetColor.Value)
		end
		if esp.ColorMode.Value == 'Manual' then
			local friendly = ent.Friend or not ent.Targetable
			local option = friendly and esp.FriendColor or Color
			return Color3.fromHSV(option.Hue, option.Sat, option.Value)
		end
		return entitylib.getEntityColor(ent) or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
	end
-- >>> dep:TargetFill (universal:4878-4878)
	-- esp.TargetFill (dep)
-- >>> dep:OverrideTarget (universal:4876-4876)
	-- esp.OverrideTarget (dep)
-- >>> dep:setAll (universal:5110-5120)
	local function setAll(EntityESP, visible)
		for key, obj in EntityESP do
			if key == 'Lines' or key == 'Faces' then
				for _, line in obj do
					set(line, 'Visible', visible)
				end
			else
				set(obj, 'Visible', visible)
			end
		end
	end
-- >>> dep:setLine (universal:4905-4908)
	local function setLine(line, from, to)
		set(line, 'From', from)
		set(line, 'To', to)
	end
-- >>> dep:screenRoot (universal:5123-5142)
	local function screenRoot(ent, EntityESP, origin, menuOpen)
		-- hidden while the menu is open; the first frame after it closes redraws them
		if menuOpen then
			setAll(EntityESP, false)
			return nil
		end
		local root = ent.RootPart
		if not (root and root.Parent) then
			setAll(EntityESP, false)
			return nil
		end
		local position = root.Position
		if origin and (origin - position).Magnitude > Range.Value then
			setAll(EntityESP, false)
			return nil
		end
		local rootPos, rootVis = gameCamera:WorldToViewportPoint(position)
		setAll(EntityESP, rootVis)
		return rootVis and rootPos or nil, position
	end
-- >>> dep:fillFor (universal:4939-4944)
	local function fillFor(ent, now, color, alpha)
		if esp.OverrideTarget.Enabled then
			return Color3.fromHSV(esp.TargetFill.Hue, esp.TargetFill.Sat, esp.TargetFill.Value), esp.TargetFill.Opacity
		end
		return color, alpha
	end
-- >>> dep:entityColor (universal:4962-4967)
	local function entityColor(ent, now)
		if esp.OverrideTarget.Enabled then
			return baseColor(ent)
		end
		return hurtTint(ent, now, baseColor(ent))
	end
-- >>> dep:drawSkeleton (universal:5153-5179)
	local function drawSkeleton(ent, lines)
		local rigcheck = ent.Humanoid.RigType == Enum.HumanoidRigType.R6
		local offset = rigcheck and CFrame.new(0, -0.8, 0) or CFrame.identity
		local torso = ent.Character[(rigcheck and 'Torso' or 'UpperTorso')].CFrame
		local headCFrame = ent.Head.CFrame
		local head = ESPWorldToViewport(headCFrame.p)
		local headfront = ESPWorldToViewport((headCFrame * CFrame.new(0, 0, -0.5)).p)
		local toplefttorso = ESPWorldToViewport((torso * CFrame.new(-1.5, 0.8, 0)).p)
		local toprighttorso = ESPWorldToViewport((torso * CFrame.new(1.5, 0.8, 0)).p)
		local toptorso = ESPWorldToViewport((torso * CFrame.new(0, 0.8, 0)).p)
		local bottomtorso = ESPWorldToViewport((torso * CFrame.new(0, -0.8, 0)).p)
		local bottomlefttorso = ESPWorldToViewport((torso * CFrame.new(-0.5, -0.8, 0)).p)
		local bottomrighttorso = ESPWorldToViewport((torso * CFrame.new(0.5, -0.8, 0)).p)
		local leftarm = ESPWorldToViewport((ent.Character[(rigcheck and 'Left Arm' or 'LeftHand')].CFrame * offset).p)
		local rightarm = ESPWorldToViewport((ent.Character[(rigcheck and 'Right Arm' or 'RightHand')].CFrame * offset).p)
		local leftleg = ESPWorldToViewport((ent.Character[(rigcheck and 'Left Leg' or 'LeftFoot')].CFrame * offset).p)
		local rightleg = ESPWorldToViewport((ent.Character[(rigcheck and 'Right Leg' or 'RightFoot')].CFrame * offset).p)
		setLine(lines.Head, toptorso, head)
		setLine(lines.HeadFacing, head, headfront)
		setLine(lines.UpperTorso, toplefttorso, toprighttorso)
		setLine(lines.Torso, toptorso, bottomtorso)
		setLine(lines.LowerTorso, bottomlefttorso, bottomrighttorso)
		setLine(lines.LeftArm, toplefttorso, leftarm)
		setLine(lines.RightArm, toprighttorso, rightarm)
		setLine(lines.LeftLeg, bottomlefttorso, leftleg)
		setLine(lines.RightLeg, bottomrighttorso, rightleg)
	end
-- >>> dep:drawHealthBar (universal:4984-4991)
	local function drawHealthBar(EntityESP, ent, left, top, bottom)
		local fraction = healthFraction(ent)
		local x = left - 5
		setLine(EntityESP.HealthBorder, Vector2.new(x, top - 1) // 1, Vector2.new(x, bottom + 1) // 1)
		set(EntityESP.HealthLine, 'Visible', fraction > 0)
		setLine(EntityESP.HealthLine, Vector2.new(x, bottom) // 1, Vector2.new(x, bottom - (bottom - top) * fraction) // 1)
		set(EntityESP.HealthLine, 'Color', Color3.fromHSV(fraction / 2.5, 0.89, 0.75))
	end
-- >>> dep:clickGuiOpen (universal:288-296)
local function clickGuiOpen()
	local open = vape.ClickGuiOpen
	if open ~= nil then return open == true end
	if vape.ThreadFix then pcall(setthreadidentity, 8) end
	local ok, visible = pcall(function()
		return vape.gui.ScaledGui.ClickGui.Visible
	end)
	return ok and visible == true
end
-- >>> dep:ESPWorldToViewport (universal:4886-4889)
	local function ESPWorldToViewport(pos)
		local newpos = gameCamera:WorldToViewportPoint(pos)
		return Vector2.new(newpos.X, newpos.Y)
	end
-- >>> dep:BOX_FACES (universal:5145-5145)
	local BOX_FACES = {{1, 3, 4, 2}, {5, 7, 8, 6}, {1, 5, 6, 2}, {3, 7, 8, 4}, {1, 3, 7, 5}, {2, 4, 8, 6}}
-- >>> dep:BOX_EDGES (universal:5144-5144)
	local BOX_EDGES = {{1, 2}, {3, 4}, {5, 6}, {7, 8}, {1, 3}, {1, 5}, {5, 7}, {7, 3}, {2, 4}, {2, 6}, {6, 8}, {8, 4}}
-- >>> dep:BOX_CORNERS (universal:5146-5149)
	local BOX_CORNERS = {
		Vector3.new(1.5, 1, 1.5), Vector3.new(1.5, -1, 1.5), Vector3.new(-1.5, 1, 1.5), Vector3.new(-1.5, -1, 1.5),
		Vector3.new(1.5, 1, -1.5), Vector3.new(1.5, -1, -1.5), Vector3.new(-1.5, 1, -1.5), Vector3.new(-1.5, -1, -1.5)
	}
-- >>> dep:eachDrawing (universal:5059-5069)
	local function eachDrawing(EntityESP, callback)
		for key, obj in EntityESP do
			if key == 'Lines' or key == 'Faces' then
				for _, line in obj do
					callback(line)
				end
			else
				callback(obj)
			end
		end
	end
-- >>> dep:DisplayName (universal:4873-4873)
	local DisplayName
-- >>> dep:Written (universal:4895-4895)
	esp.Written = setmetatable({}, {__mode = 'k'})
-- >>> dep:set (universal:4897-4903)
	local function set(obj, key, value)
		local last = esp.Written[obj]
		if last[key] ~= value then
			obj[key] = value
			last[key] = value
		end
	end
-- >>> dep:nameText (universal:4993-4995)
	local function nameText(ent)
		return ent.Player and whitelist:tag(ent.Player, true)..(DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name) or ent.Character.Name
	end
-- >>> dep:methodused (universal:4882-4882)
	-- esp.methodused (dep)
-- >>> dep:LastHealth (universal:4880-4880)
	esp.LastHealth = {}
-- >>> dep:HurtAt (universal:4881-4881)
	esp.HurtAt = {}
-- >>> dep:ESPUpdated (universal:5090-5108)
	local function ESPUpdated(ent)
		local health = ent.Health
		local last = esp.LastHealth[ent]
		if type(health) == 'number' then
			if last and health < last then
				esp.HurtAt[ent] = os.clock()
			end
			esp.LastHealth[ent] = health
		end
		local EntityESP = Reference[ent]
		if EntityESP and EntityESP.Text then
			if vape.ThreadFix then
				setthreadidentity(8)
			end
			local text = nameText(ent)
			set(EntityESP.Text, 'Text', text)
			set(EntityESP.Drop, 'Text', text)
		end
	end
-- >>> dep:ESPRemoved (universal:5071-5088)
	local function ESPRemoved(ent)
		local EntityESP = Reference[ent]
		esp.LastHealth[ent] = nil
		esp.HurtAt[ent] = nil
		if EntityESP then
			if vape.ThreadFix then
				setthreadidentity(8)
			end
			Reference[ent] = nil
			eachDrawing(EntityESP, function(obj)
				esp.Written[obj] = nil
				pcall(function()
					obj.Visible = false
					obj:Remove()
				end)
			end)
		end
	end
-- >>> dep:ESPLoop (universal:5181-5283)
	esp.ESPLoop = {
		Drawing2D = function()
			local now = os.clock()
			local camera = gameCamera.CFrame
			local origin = entitylib.isAlive and entitylib.character.RootPart.Position or camera.Position
			local menuOpen = clickGuiOpen()
			for ent, EntityESP in Reference do
				local rootPos, position = screenRoot(ent, EntityESP, origin, menuOpen)
				if not rootPos then continue end

				local look = CFrame.lookAlong(position, camera.LookVector)
				local topPos = gameCamera:WorldToViewportPoint((look * CFrame.new(2, ent.HipHeight, 0)).p)
				local bottomPos = gameCamera:WorldToViewportPoint((look * CFrame.new(-2, -ent.HipHeight - 1, 0)).p)
				local sizex, sizey = topPos.X - bottomPos.X, topPos.Y - bottomPos.Y
				local posx, posy = (rootPos.X - sizex / 2), (rootPos.Y - sizey / 2)
				local boxPos, boxSize = Vector2.new(posx, posy) // 1, Vector2.new(sizex, sizey) // 1
				local color = entityColor(ent, now)
				if EntityESP.Main then
					set(EntityESP.Main, 'Position', boxPos)
					set(EntityESP.Main, 'Size', boxSize)
					set(EntityESP.Main, 'Color', color)
					set(EntityESP.Border, 'Position', boxPos)
					set(EntityESP.Border, 'Size', boxSize)
				end
				if EntityESP.Fill then
					local fill, fillAlpha = fillFor(ent, now, color, 0.25)
					set(EntityESP.Fill, 'Position', boxPos)
					set(EntityESP.Fill, 'Size', boxSize)
					set(EntityESP.Fill, 'Color', fill)
					set(EntityESP.Fill, 'Transparency', fillAlpha)
				end
				if EntityESP.HealthLine then
					local top, bottom = math.min(posy, posy + sizey), math.max(posy, posy + sizey)
					drawHealthBar(EntityESP, ent, math.min(posx, posx + sizex), top, bottom)
				end
				if EntityESP.Text then
					local textPos = Vector2.new(posx + (sizex / 2), posy + (sizey - 28)) // 1
					set(EntityESP.Text, 'Color', color)
					set(EntityESP.Text, 'Position', textPos)
					set(EntityESP.Drop, 'Position', textPos + Vector2.new(1, 1))
					if EntityESP.TextBKG then
						local bounds = EntityESP.Text.TextBounds
						set(EntityESP.TextBKG, 'Size', bounds + Vector2.new(8, 4))
						set(EntityESP.TextBKG, 'Position', textPos - Vector2.new(4 + (bounds.X / 2), 0))
					end
				end
			end
		end,
		Drawing3D = function()
			local now = os.clock()
			local origin = entitylib.isAlive and entitylib.character.RootPart.Position or gameCamera.CFrame.Position
			local menuOpen = clickGuiOpen()
			local points = {}
			for ent, EntityESP in Reference do
				local rootPos, position = screenRoot(ent, EntityESP, origin, menuOpen)
				if not rootPos then continue end

				local height = ent.HipHeight
				local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
				for i, corner in BOX_CORNERS do
					local point = ESPWorldToViewport(position + Vector3.new(corner.X, corner.Y * height, corner.Z))
					points[i] = point
					left, right = math.min(left, point.X), math.max(right, point.X)
					top, bottom = math.min(top, point.Y), math.max(bottom, point.Y)
				end
				local color = entityColor(ent, now)
				for i, line in EntityESP.Lines do
					local edge = BOX_EDGES[i]
					setLine(line, points[edge[1]], points[edge[2]])
					set(line, 'Color', color)
				end
				local fill, fillAlpha = fillFor(ent, now, color, 0.15)
				for i, face in EntityESP.Faces do
					local corners = BOX_FACES[i]
					set(face, 'PointA', points[corners[1]])
					set(face, 'PointB', points[corners[2]])
					set(face, 'PointC', points[corners[3]])
					set(face, 'PointD', points[corners[4]])
					set(face, 'Color', fill)
					set(face, 'Transparency', fillAlpha)
				end
				if EntityESP.HealthLine then
					drawHealthBar(EntityESP, ent, left, top, bottom)
				end
			end
		end,
		DrawingSkeleton = function()
			local now = os.clock()
			local origin = entitylib.isAlive and entitylib.character.RootPart.Position or gameCamera.CFrame.Position
			local menuOpen = clickGuiOpen()
			for ent, EntityESP in Reference do
				local rootPos = screenRoot(ent, EntityESP, origin, menuOpen)
				if not rootPos then continue end

				local lines = EntityESP.Lines
				local color = entityColor(ent, now)
				for _, line in lines do
					set(line, 'Color', color)
				end
				pcall(drawSkeleton, ent, lines)
			end
		end
	}
-- >>> dep:ESPAdded (universal:4997-5057)
	esp.ESPAdded = {
		Drawing2D = function(ent)
			if not passes(ent) then return end
			if vape.ThreadFix then
				setthreadidentity(8)
			end
			local EntityESP = {}
			if Filled.Enabled then
				EntityESP.Fill = newDrawing('Square', {Filled = true, Transparency = 0.25, ZIndex = 0, Thickness = 1})
			end
			if esp.BoundingBox.Enabled then
				EntityESP.Border = newDrawing('Square', {Filled = false, Transparency = 0.5, ZIndex = 1, Thickness = esp.LineWidth.Value + 2, Color = Color3.new()})
				EntityESP.Main = newDrawing('Square', {Filled = false, Transparency = 1, ZIndex = 2, Thickness = esp.LineWidth.Value})
			end
			if esp.HealthBar.Enabled then
				addHealthBar(EntityESP)
			end
			if Name.Enabled then
				if Background.Enabled then
					EntityESP.TextBKG = newDrawing('Square', {Transparency = 0.35, ZIndex = 0, Thickness = 1, Filled = true, Color = Color3.new()})
				end
				EntityESP.Drop = newDrawing('Text', {Color = Color3.new(), Text = nameText(ent), ZIndex = 1, Center = true, Size = 20})
				EntityESP.Text = newDrawing('Text', {Text = EntityESP.Drop.Text, ZIndex = 2, Center = true, Size = 20})
			end
			Reference[ent] = EntityESP
		end,
		Drawing3D = function(ent)
			if not passes(ent) then return end
			if vape.ThreadFix then
				setthreadidentity(8)
			end
			local EntityESP = {Lines = {}, Faces = {}}
			if esp.BoundingBox.Enabled then
				for i = 1, 12 do
					EntityESP.Lines[i] = newDrawing('Line', {Thickness = esp.LineWidth.Value, ZIndex = 2})
				end
			end
			if Filled.Enabled then
				for i = 1, 6 do
					local ok, face = pcall(newDrawing, 'Quad', {Filled = true, Transparency = 0.15, Thickness = 1, ZIndex = 1})
					if not ok then break end
					EntityESP.Faces[i] = face
				end
			end
			if esp.HealthBar.Enabled then
				addHealthBar(EntityESP)
			end
			Reference[ent] = EntityESP
		end,
		DrawingSkeleton = function(ent)
			if not passes(ent) then return end
			if vape.ThreadFix then
				setthreadidentity(8)
			end
			local EntityESP = {Lines = {}}
			for _, name in {'Head', 'HeadFacing', 'Torso', 'UpperTorso', 'LowerTorso', 'LeftArm', 'RightArm', 'LeftLeg', 'RightLeg'} do
				EntityESP.Lines[name] = newDrawing('Line', {Thickness = math.max(esp.LineWidth.Value, 2)})
			end
			Reference[ent] = EntityESP
		end
	}
-- >>> dep:ESP (universal:4860-4860)
	-- esp.ESP (dep)
-- >>> dep:List (universal:8457-8457)
	local List
-- >>> dep:modifyPart (universal:8460-8467)
	local function modifyPart(v)
		if v:IsA('BasePart') and not table.find(List.ListEnabled, v.Name) then
			if modified[v] == nil then
				modified[v] = v.LocalTransparencyModifier
			end
			v.LocalTransparencyModifier = 0.5
		end
	end
-- >>> dep:Xray (universal:8456-8456)
	-- mv.Xray (dep)
-- >>> dep:Parkour (universal:8376-8376)
	-- mv.Parkour (dep)
-- >>> dep:svc.contextService (universal:116-116)
svc.contextService = cloneref(game:GetService('ContextActionService'))
-- >>> dep:Freecam (universal:8231-8231)
	-- mv.Freecam (dep)
-- >>> dep:changed (universal:8314-8314)
	ph.changed = false
	local old
-- >>> dep:Gravity (universal:8311-8311)
	local Gravity
-- >>> dep:Timer (universal:4070-4070)
	-- mv.Timer (dep)
-- >>> dep:current (universal:3940-3940)
	local module, current
-- >>> dep:YFactor (universal:3932-3932)
	-- mv.YFactor (dep)
-- >>> dep:Targets (universal:3929-3929)
	local Targets
-- >>> dep:StrafeRange (universal:3931-3931)
	-- mv.StrafeRange (dep)
-- >>> dep:SearchRange (universal:3930-3930)
	-- mv.SearchRange (dep)
-- >>> dep:terrain (universal:3893-3893)
	local terrain = cloneref(workspace:FindFirstChildWhichIsA('Terrain'))
-- >>> dep:lastpos (universal:3894-3894)
	mv.lastpos = Region3.new(Vector3.zero, Vector3.zero)
-- >>> dep:Swim (universal:3892-3892)
	-- mv.Swim (dep)
-- >>> dep:ZToggle (universal:3829-3829)
	-- mv.ZToggle (dep)
-- >>> dep:YToggle (universal:3828-3828)
	-- mv.YToggle (dep)
-- >>> dep:XToggle (universal:3827-3827)
	-- mv.XToggle (dep)
-- >>> dep:SpinBot (universal:3825-3825)
	-- mv.SpinBot (dep)
-- >>> dep:AngularVelocity (universal:3831-3831)
	mv.AngularVelocity = nil
-- >>> dep:trussAt (universal:3688-3688)
	local trussPos
	mv.trussAt = nil
-- >>> dep:placeTruss (universal:3691-3696)
	local function placeTruss(pos)
local mv = {}
		if mv.trussAt ~= mv.Truss or trussPos ~= pos then
			mv.Truss.Position = pos
			mv.trussAt, trussPos = mv.Truss, pos
		end
	end
-- >>> dep:State (universal:3684-3684)
	local State
-- >>> dep:Active (universal:3687-3687)
	local Active
-- >>> dep:appliedFilters (universal:325-325)
local appliedFilters = setmetatable({}, {__mode = 'k'})
-- >>> dep:setFilter (universal:326-340)
local function setFilter(params, list)
	local last = appliedFilters[params]
	if last and #last == #list then
		local same = true
		for i = 1, #list do
			if last[i] ~= list[i] then
				same = false
				break
			end
		end
		if same then return end
	end
	params.FilterDescendantsInstances = list
	appliedFilters[params] = list
end
-- >>> dep:overlapCheck (universal:3317-3317)
	ph.overlapCheck = OverlapParams.new()
-- >>> dep:grabClosestNormal (universal:3360-3371)
	function ph.grabClosestNormal(ray)
		local partCF, mag, closest = ray.Instance.CFrame, 0, Enum.NormalId.Top
	
		for _, normal in Enum.NormalId:GetEnumItems() do
			local dot = partCF:VectorToWorldSpace(Vector3.fromNormalId(normal)):Dot(ray.Normal)
			if dot > mag then
				mag, closest = dot, normal
			end
		end
	
		return Vector3.fromNormalId(closest).X ~= 0 and 'X' or 'Z'
	end
-- >>> dep:characterParts (universal:3338-3358)
	function ph.characterParts(char)
		if char ~= charPartsOf then
			ph.dropCharacterParts()
			charPartsOf = char
			local function markStale()
				charPartsStale = true
			end
			table.insert(charWatch, char.DescendantAdded:Connect(markStale))
			table.insert(charWatch, char.DescendantRemoving:Connect(markStale))
		end
		if charPartsStale then
			charPartsStale = false
			table.clear(charParts)
			for _, part in char:GetDescendants() do
				if part:IsA('BasePart') then
					table.insert(charParts, part)
				end
			end
		end
		return charParts
	end
-- >>> dep:StudLimit (universal:3314-3314)
	ph.StudLimit = {Object = {}}
-- >>> dep:Spider (universal:144-144)
local Spider = {Enabled = false}
-- >>> dep:charWatch (universal:3327-3327)
	local charWatch = {}
-- >>> dep:charParts (universal:3326-3326)
	local charParts, charPartsOf, charPartsStale = {}, nil, true
-- >>> dep:inBox (universal:3322-3322)
	ph.inBox = {}
-- >>> dep:fflag (universal:3319-3319)
	local modified, fflag = {}
-- >>> dep:dropCharacterParts (universal:3329-3336)
	function ph.dropCharacterParts()
		for _, connection in charWatch do
			connection:Disconnect()
		end
		table.clear(charWatch)
		table.clear(charParts)
		charPartsOf, charPartsStale = nil, true
	end
-- >>> dep:releasePhase (universal:3374-3385)
	function ph.releasePhase()
		if fflag then
			setfflag('AssemblyExtentsExpansionStudHundredth', '30')
		end
		for part in modified do
			part.CanCollide = true
		end
		table.clear(modified)
		table.clear(ph.inBox)
		ph.dropCharacterParts()
		fflag = nil
	end
-- >>> dep:heldByAutoWin (universal:3389-3392)
	function ph.heldByAutoWin()
		local autoWin = vape.Modules.AutoWin
		return autoWin ~= nil and autoWin.Enabled == true
	end
-- >>> dep:Phase (universal:145-145)
local Phase = {Enabled = false}
-- >>> dep:Functions (universal:3394-3457)
	ph.Functions = {
		Part = function()
			local chars = {gameCamera, lplr.Character}
			for _, v in entitylib.List do
				table.insert(chars, v.Character)
			end
			setFilter(ph.overlapCheck, chars)

			local parts = workspace:GetPartBoundsInBox(entitylib.character.RootPart.CFrame + Vector3.new(0, 1, 0), entitylib.character.RootPart.Size + Vector3.new(7, entitylib.character.HipHeight, 7), ph.overlapCheck)
			table.clear(ph.inBox)
			for _, part in parts do
				ph.inBox[part] = true
				if part.CanCollide and (not Spider.Enabled or SpiderShift) then
					modified[part] = true
					part.CanCollide = false
				end
			end

			for part in modified do
				if not ph.inBox[part] then
					modified[part] = nil
					part.CanCollide = true
				end
			end
		end,
		Character = function()
			for _, part in ph.characterParts(lplr.Character) do
				if part.CanCollide and (not Spider.Enabled or SpiderShift) then
					modified[part] = true
					part.CanCollide = Spider.Enabled and not SpiderShift
				end
			end
		end,
		CFrame = function()
			local chars = {gameCamera, lplr.Character}
			for _, v in entitylib.List do
				table.insert(chars, v.Character)
			end
			setFilter(ph.rayCheck, chars)
			setFilter(ph.overlapCheck, chars)
	
			local ray = workspace:Raycast(entitylib.character.Head.CFrame.Position, entitylib.character.Humanoid.MoveDirection * 1.1, ph.rayCheck)
			if ray and (not Spider.Enabled or SpiderShift) then
				local phaseDirection = ph.grabClosestNormal(ray)
				if ray.Instance.Size[phaseDirection] <= ph.StudLimit.Value then
					local root = entitylib.character.RootPart
					local dest = root.CFrame + (ray.Normal * (-(ray.Instance.Size[phaseDirection]) - (root.Size.X / 1.5)))
	
					if #workspace:GetPartBoundsInBox(dest, Vector3.one, ph.overlapCheck) <= 0 then
						if Mode.Value == 'Motor' then
							motorMove(root, dest)
						else
							root.CFrame = dest
						end
					end
				end
			end
		end,
		FFlag = function()
			if teleported then return end
			setfflag('AssemblyExtentsExpansionStudHundredth', '-10000')
			fflag = true
		end
	}
-- >>> dep:WaypointFolder (universal:143-143)
local TargetStrafeVector, SpiderShift, WaypointFolder
-- >>> dep:rayCheck (universal:3195-3195)
	ph.rayCheck = RaycastParams.new()
-- >>> dep:position (universal:3202-3202)
			local position, vis = gameCamera:WorldToViewportPoint(v.StudsOffsetWorldSpace)
-- >>> dep:motorMove (universal:519-529)
local function motorMove(target, cf)
	local part = Instance.new('Part')
	part.Anchored = true
	part.Parent = workspace
	local motor = Instance.new('Motor6D')
	motor.Part0 = target
	motor.Part1 = part
	motor.C1 = cf
	motor.Parent = part
	task.delay(0, part.Destroy, part)
end
-- >>> dep:getWaypointInMouse (universal:3198-3212)
	function ph.getWaypointInMouse()
		local obj, dist, location = nil, math.huge, svc.inputService:GetMouseLocation()
	
		for _, v in WaypointFolder:GetChildren() do
			local position, vis = gameCamera:WorldToViewportPoint(v.StudsOffsetWorldSpace)
			if not vis then continue end
	
			local mag = (location - Vector2.new(position.x, position.y)).Magnitude
			if mag < dist then
				obj, dist = v, mag
			end
		end
	
		return obj
	end
-- >>> dep:MovementMode (universal:3192-3192)
	-- mv.MovementMode (dep)
-- >>> dep:MouseTP (universal:3190-3190)
	-- mv.MouseTP (dep)
-- >>> dep:Length (universal:3193-3193)
	-- ph.Length (dep)
-- >>> dep:Delay (universal:3194-3194)
	-- ph.Delay (dep)
-- >>> dep:params (universal:2712-2712)
	local params = RaycastParams.new()
-- >>> dep:gameCamera (universal:133-133)
local gameCamera = workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera')
-- >>> dep:Jesus (universal:2711-2711)
	-- mv.Jesus (dep)
-- >>> dep:oldcf (universal:2637-2637)
	-- mv.oldcf (dep)
-- >>> dep:svc.httpService (universal:112-112)
svc.httpService = cloneref(game:GetService('HttpService'))
-- >>> dep:animtrack (universal:2638-2638)
	-- mv.animtrack (dep)
-- >>> dep:animationTrickery (universal:2641-2655)
	function ph.animationTrickery()
		if entitylib.isAlive then
			local isR15 = entitylib.character.Humanoid.RigType == Enum.HumanoidRigType.R15
			local anim = Instance.new('Animation')
			anim.AnimationId = 'rbxassetid://'..(isR15 and '18537363391' or '215384594')
			mv.animtrack = entitylib.character.Humanoid.Animator:LoadAnimation(anim)
			mv.animtrack.Priority = Enum.AnimationPriority.Action4
			mv.animtrack:Play(0, 0.001, 0)
			anim:Destroy()
	
			task.delay(0, function()
				mv.animtrack.TimePosition = isR15 and 0.77 or 0.38
			end)
		end
	end
-- >>> dep:Invisible (universal:2636-2636)
	-- mv.Invisible (dep)
-- >>> dep:Value (universal:2496-2496)
	local Value
-- >>> dep:svc.runService (universal:106-106)
svc.runService = cloneref(game:GetService('RunService'))
-- >>> dep:jump (universal:2499-2531)
	function ph.jump()
		local state = entitylib.isAlive and entitylib.character.Humanoid:GetState() or nil
	
		if state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Landed then
			local root = entitylib.character.RootPart
	
			if Mode.Value == 'Velocity' then
				entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, Value.Value, root.AssemblyLinearVelocity.Z)
			elseif Mode.Value == 'Impulse' then
				entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				task.delay(0, function()
					root:ApplyImpulse(Vector3.new(0, Value.Value - root.AssemblyLinearVelocity.Y, 0) * root.AssemblyMass)
				end)
			else
				--[[ With no gravity there is no peak to stop at; the step cap covers gravity
				dropping to 0 mid-ph.jump (normal gravity needs under 50 steps). ]]
				if workspace.Gravity <= 0 then return end
				local yLevel = math.max(Value.Value - entitylib.character.Humanoid.JumpHeight, 0)
				local steps = 0
	
				repeat
					root.CFrame += Vector3.new(0, yLevel * 0.016, 0)
					yLevel = yLevel - (workspace.Gravity * 0.016)
					steps += 1
	
					if Mode.Value == 'CFrame' then
						task.wait()
					end
				until yLevel <= 0 or steps >= 600
			end
		end
	end
-- >>> dep:svc.inputService (universal:107-107)
svc.inputService = cloneref(game:GetService('UserInputService'))
-- >>> dep:Mode (universal:2495-2495)
	local Mode
-- >>> dep:HighJump (universal:2494-2494)
	-- mv.HighJump (dep)
-- >>> dep:AutoDisable (universal:2497-2497)
	-- mv.AutoDisable (dep)
-- >>> dep:characterAdded (universal:7971-7979)
	function ph.characterAdded(char)
		for _, v in getconnections(char.RootPart:GetPropertyChangedSignal('CFrame')) do
			hookfunction(v.Function, function() end)
		end
	
		for _, v in getconnections(char.RootPart:GetPropertyChangedSignal('Velocity')) do
			hookfunction(v.Function, function() end)
		end
	end
-- >>> dep:Disabler (universal:7969-7969)
	-- mv.Disabler (dep)
-- >>> dep:notif (universal:377-379)
local function notif(...)
	return vape:CreateNotification(...)
end
-- >>> dep:rakNetCheck (universal:386-393)
local function rakNetCheck(module)
	if not (raknet and raknet.add_send_hook and pcall(raknet.add_send_hook, function() end)) then
		notif(module, 'This feature requires raknet! (risky feature, please do not use on mains.)', 10, 'warning')
		return false
	end

	return true
end
-- >>> dep:hook (universal:2109-2109)
	local hook
-- >>> dep:Desync (universal:2108-2108)
	-- mv.Desync (dep)
-- >>> dep:svc.playersService (universal:104-104)
svc.playersService = cloneref(game:GetService('Players'))
-- >>> dep:teleported (universal:3320-3320)
	local teleported
-- >>> dep:oldphys (universal:7785-7785)
	local oldphys, oldsend
-- >>> dep:lplr (universal:134-134)
local lplr = svc.playersService.LocalPlayer
-- >>> dep:generation (universal:7788-7788)
	local generation = 0
-- >>> dep:Type (universal:7782-7782)
	local Type
-- >>> dep:Blink (universal:7781-7781)
	-- mv.Blink (dep)
-- >>> dep:AutoSendLength (universal:7784-7784)
	-- mv.AutoSendLength (dep)
-- >>> dep:AutoSend (universal:7783-7783)
	-- mv.AutoSend (dep)
-- ===================== universal modules =====================
-- >>> MODULE:Blink (universal:7790-7829)
	mv.Blink = vape.Categories.Utility:CreateModule({
		Name = 'Blink',
		ExtraText = function()
			return Type and (Type.Value == 'All' and 'All' or 'Movement') or nil
		end,
		Function = function(callback)
			generation += 1
			if callback then
				local teleported
				mv.Blink:Clean(lplr.OnTeleport:Connect(function()
					setfflag('PhysicsSenderMaxBandwidthBps', '38760')
					setfflag('DataSenderRate', '60')
					teleported = true
				end))

				local gen = generation
				repeat
					local physicsrate, senderrate = '0', Type.Value == 'All' and '-1' or '60'
					if mv.AutoSend.Enabled and tick() % (mv.AutoSendLength.Value + 0.1) > mv.AutoSendLength.Value then
						physicsrate, senderrate = '38760', '60'
					end
	
					if physicsrate ~= mv.oldphys or senderrate ~= oldsend then
						setfflag('PhysicsSenderMaxBandwidthBps', physicsrate)
						setfflag('DataSenderRate', senderrate)
						mv.oldphys, oldsend = physicsrate, senderrate
					end
	
					task.wait(0.03)
				until not mv.Blink.Enabled or teleported or generation ~= gen
			else
				if setfflag then
					setfflag('PhysicsSenderMaxBandwidthBps', '38760')
					setfflag('DataSenderRate', '60')
				end
				mv.oldphys, oldsend = nil, nil
			end
		end,
		Tooltip = 'Freezes you in place for others, then jumps you ahead.\nCan hold back your actions too, and catch up at set intervals.'
	})
-- >>> MODULE:Desync (universal:2111-2135)
	mv.Desync = vape.Categories.Blatant:CreateModule({
		Name = 'Desync',
		Function = function(callback)
			if callback then
				if not rakNetCheck('Desync') then
					mv.Desync:Toggle()
					return
				end
	
				hook = function(packet)
					if packet.AsArray[1] == 0x1b then
						local data = packet.AsBuffer
						buffer.writeu32(data, 1, 0xFFFFFFFF)
						packet:SetData(data)
					end
				end
	
				raknet.add_send_hook(hook)
			elseif hook then
				raknet.remove_send_hook(hook)
				hook = nil
			end
		end,
		Tooltip = 'Hides your real position from other players.'
	})
-- >>> MODULE:Disabler (universal:7981-7992)
	mv.Disabler = vape.Categories.Utility:CreateModule({
		Name = 'Disabler',
		Function = function(callback)
			if callback then
				mv.Disabler:Clean(entitylib.Events.LocalAdded:Connect(ph.characterAdded))
				if entitylib.isAlive then
					ph.characterAdded(entitylib.character)
				end
			end
		end,
		Tooltip = 'Makes movement modules work more reliably.'
	})
-- >>> MODULE:HighJump (universal:2533-2556)
	mv.HighJump = vape.Categories.Blatant:CreateModule({
		Name = 'HighJump',
		Function = function(callback)
			if callback then
				if mv.AutoDisable.Enabled then
					ph.jump()
					mv.HighJump:Toggle()
				else
					mv.HighJump:Clean(svc.runService.RenderStepped:Connect(function()
						if svc.inputService:GetFocusedTextBox() then return end
						--[[ The touch ph.jump button sets no key; the control module holds Humanoid.Jump instead. ]]
						if svc.inputService:IsKeyDown(Enum.KeyCode.Space)
							or (svc.inputService.TouchEnabled and entitylib.isAlive and entitylib.character.Humanoid.Jump) then
							ph.jump()
						end
					end))
				end
			end
		end,
		ExtraText = function()
			return Mode.Value
		end,
		Tooltip = 'Lets you jump much higher than normal.\nBoosts one jump then turns off, or every jump while you hold Space.'
	})
-- >>> MODULE:Invisible (universal:2657-2707)
	mv.Invisible = vape.Categories.Blatant:CreateModule({
		Name = 'Invisible',
		Function = function(callback)
			if callback then
				ph.animationTrickery()
	
				local bindKey = svc.httpService:GenerateGUID(true)
				svc.runService:BindToRenderStep(bindKey, 0, function()
					if entitylib.isAlive and mv.oldcf then
						entitylib.character.RootPart.CFrame = mv.oldcf
						mv.animtrack:AdjustWeight(0.001)
					end
				end)
	
				mv.Invisible:Clean(function()
					svc.runService:UnbindFromRenderStep(bindKey)
				end)
	
				mv.Invisible:Clean(svc.runService.Heartbeat:Connect(function(dt)
					if entitylib.isAlive then
						local isR15 = entitylib.character.Humanoid.RigType == Enum.HumanoidRigType.R15
						local root = entitylib.character.RootPart
						local cf = root.CFrame - Vector3.new(0, entitylib.character.Humanoid.HipHeight + (root.Size.Y / 2) - 1, 0)
						mv.oldcf = root.CFrame
	
						root.CFrame = cf * CFrame.Angles(math.rad(isR15 and 180 or 90), 0, 0)
						mv.animtrack:AdjustWeight(100)
					end
				end))
	
				mv.Invisible:Clean(entitylib.Events.LocalAdded:Connect(function(char)
					local animator = char.Humanoid:WaitForChild('Animator', 1)
					if animator and mv.Invisible.Enabled then
						mv.oldcf = nil
						mv.Invisible:Toggle()
						mv.Invisible:Toggle()
					end
				end))
			else
				if mv.animtrack then
					mv.animtrack:Stop()
					mv.animtrack:Destroy()
				end
	
				if entitylib.isAlive and mv.oldcf then
					entitylib.character.RootPart.CFrame = mv.oldcf
				end
			end
		end,
		Tooltip = 'Turns you invisible.'
	})
-- >>> MODULE:Jesus (universal:2715-2744)
	mv.Jesus = vape.Categories.Blatant:CreateModule({
		Name = 'Jesus',
		Function = function(callback)
			if callback then
				local terrain = workspace:FindFirstChildWhichIsA('Terrain')
				params.FilterDescendantsInstances = {terrain}
				local Platform = Instance.new('Part')
				Platform.CanQuery = false
				Platform.Anchored = true
				Platform.Size = Vector3.one
				Platform.Transparency = 1
				Platform.Parent = gameCamera
	
				mv.Jesus:Clean(Platform)
				mv.Jesus:Clean(svc.runService.PreSimulation:Connect(function()
					if entitylib.isAlive then
						local root = entitylib.character.RootPart
						local ray = workspace:Raycast(root.Position, Vector3.new(0, -((root.Size.Y / 2) + entitylib.character.HipHeight + math.abs(root.AssemblyLinearVelocity.Y * 0.032)), 0), params)
	
						if ray and ray.Material == Enum.Material.Water then
							Platform.CFrame = CFrame.new(ray.Position)
						else
							Platform.CFrame = CFrame.new(10000, 10000, 10000)
						end
					end
				end))
			end
		end,
		Tooltip = 'Lets you walk on water as if it were solid ground.'
	})
-- >>> MODULE:MouseTP (universal:3214-3276)
	mv.MouseTP = vape.Categories.Blatant:CreateModule({
		Name = 'MouseTP',
		Function = function(callback)
			if callback then
				local position
				if Mode.Value == 'Mouse' then
					local ray = cloneref(lplr:GetMouse()).UnitRay
					ph.rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
					ray = workspace:Raycast(ray.Origin, ray.Direction * 10000, ph.rayCheck)
					position = ray and ray.Position + Vector3.new(0, entitylib.character.HipHeight or 2, 0)
				elseif Mode.Value == 'Waypoint' then
					local waypoint = ph.getWaypointInMouse()
					position = waypoint and waypoint.StudsOffsetWorldSpace
				else
					local ent = entitylib.EntityMouse({
						Range = math.huge,
						Part = 'RootPart',
						Players = true
					})
					position = ent and ent.RootPart.Position
				end
	
				if not position then
					notif('MouseTP', 'No position found.', 5)
					mv.MouseTP:Toggle()
					return
				end
	
				if mv.MovementMode.Value ~= 'Lerp' then
					mv.MouseTP:Toggle()
					if entitylib.isAlive then
						if mv.MovementMode.Value == 'Motor' then
							motorMove(entitylib.character.RootPart, CFrame.lookAlong(position, entitylib.character.RootPart.CFrame.LookVector))
						else
							entitylib.character.RootPart.CFrame = CFrame.lookAlong(position, entitylib.character.RootPart.CFrame.LookVector)
						end
					end
				else
					mv.MouseTP:Clean(svc.runService.Heartbeat:Connect(function()
						if entitylib.isAlive then
							entitylib.character.RootPart.Velocity = Vector3.zero
						end
					end))
	
					repeat
						if entitylib.isAlive then
							local direction = CFrame.lookAt(entitylib.character.RootPart.Position, position).LookVector * math.min((entitylib.character.RootPart.Position - position).Magnitude, ph.Length.Value)
							entitylib.character.RootPart.CFrame += direction
							if (entitylib.character.RootPart.Position - position).Magnitude < 3 and mv.MouseTP.Enabled then
								mv.MouseTP:Toggle()
							end
						elseif mv.MouseTP.Enabled then
							mv.MouseTP:Toggle()
							notif('MouseTP', 'Character missing', 5, 'warning')
						end
	
						task.wait(ph.Delay.Value)
					until not mv.MouseTP.Enabled
				end
			end
		end,
		Tooltip = 'Teleports you to the spot, player or waypoint you point at.\nGo there instantly, or glide over in steps.'
	})
-- >>> MODULE:Phase (universal:3460-3486)
	Phase = vape.Categories.Blatant:CreateModule({
		Name = 'Phase',
		ExtraText = function()
			return Mode and Mode.Value or nil
		end,
		Function = function(callback)
			if callback then
				Phase:Clean(svc.runService.Stepped:Connect(function()
					if ph.heldByAutoWin() then
						ph.releasePhase()
					elseif entitylib.isAlive then
						ph.Functions[Mode.Value]()
					end
				end))
	
				if Mode.Value == 'FFlag' then
					Phase:Clean(lplr.OnTeleport:Connect(function()
						teleported = true
						setfflag('AssemblyExtentsExpansionStudHundredth', '30')
					end))
				end
			else
				ph.releasePhase()
			end
		end,
		Tooltip = 'Lets you walk through walls.\nChoose how it gets you through and the thickest wall it will pass.'
	})
-- >>> MODULE:Spider (universal:3706-3785)
	Spider = vape.Categories.Blatant:CreateModule({
		Name = 'Spider',
		ExtraText = function()
			return Mode and Mode.Value or nil
		end,
		Function = function(callback)
			if callback then
				if mv.Truss then
					mv.Truss.Parent = gameCamera
				end

				--[[ A reinject empties the old vape table; a loop that outlived its session
				(started again by AutoWin mid-unload) stops itself instead of erroring every
				physics step. ]]
				local loop
				loop = svc.runService.PreSimulation:Connect(function(dt)
					if vape.Loaded == nil then
						loop:Disconnect()
						return
					end
					if ph.heldByAutoWin() then
						Active = nil
						if mv.Truss then
							placeTruss(Vector3.zero)
						end
					elseif entitylib.isAlive then
						local root = entitylib.character.RootPart
						local chars = {gameCamera, lplr.Character, mv.Truss}
						for _, v in entitylib.List do
							table.insert(chars, v.Character)
						end

						SpiderShift = svc.inputService:IsKeyDown(Enum.KeyCode.LeftShift)
						setFilter(ph.rayCheck, chars)
						ph.rayCheck.CollisionGroup = root.CollisionGroup
	
						if Mode.Value ~= 'Part' then
							local vec = entitylib.character.Humanoid.MoveDirection * 2.5
							local ray = workspace:Raycast(root.Position - Vector3.new(0, entitylib.character.HipHeight - 0.5, 0), vec, ph.rayCheck)
							if Active and not ray then
								root.Velocity = Vector3.new(root.Velocity.X, 0, root.Velocity.Z)
							end
	
							Active = ray
							if Active and ray.Normal.Y == 0 then
								if not Phase.Enabled or not SpiderShift then
									if State.Enabled then
										entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
									end
	
									root.Velocity *= Vector3.new(1, 0, 1)
									if Mode.Value == 'CFrame' then
										root.CFrame += Vector3.new(0, Value.Value * dt, 0)
									elseif Mode.Value == 'Impulse' then
										root:ApplyImpulse(Vector3.new(0, Value.Value, 0) * root.AssemblyMass)
									else
										root.Velocity += Vector3.new(0, Value.Value, 0)
									end
								end
							end
						else
							local ray = workspace:Raycast(root.Position - Vector3.new(0, entitylib.character.HipHeight - 0.5, 0), entitylib.character.RootPart.CFrame.LookVector * 2, ph.rayCheck)
							if ray and (not Phase.Enabled or not SpiderShift) then
								placeTruss(ray.Position - ray.Normal * 0.9 or Vector3.zero)
							else
								placeTruss(Vector3.zero)
							end
						end
					end
				end)
				Spider:Clean(loop)
			else
				if mv.Truss then
					mv.Truss.Parent = nil
				end
				SpiderShift = false
			end
		end,
		Tooltip = 'Lets you climb straight up walls.\nWalk into a wall to climb it; set the climbing style and speed.'
	})
-- >>> MODULE:SpinBot (universal:3833-3865)
	mv.SpinBot = vape.Categories.Blatant:CreateModule({
		Name = 'SpinBot',
		Function = function(callback)
			if callback then
				mv.SpinBot:Clean(svc.runService.PreSimulation:Connect(function()
					if entitylib.isAlive then
						if Mode.Value == 'RotVelocity' then
							local originalRotVelocity = entitylib.character.RootPart.RotVelocity
							entitylib.character.Humanoid.AutoRotate = false
							entitylib.character.RootPart.RotVelocity = Vector3.new(mv.XToggle.Enabled and Value.Value or originalRotVelocity.X, mv.YToggle.Enabled and Value.Value or originalRotVelocity.Y, mv.ZToggle.Enabled and Value.Value or originalRotVelocity.Z)
						elseif Mode.Value == 'CFrame' then
							local val = math.rad((tick() * (20 * Value.Value)) % 360)
							local x, y, z = entitylib.character.RootPart.CFrame:ToOrientation()
							entitylib.character.RootPart.CFrame = CFrame.new(entitylib.character.RootPart.Position) * CFrame.Angles(mv.XToggle.Enabled and val or x, mv.YToggle.Enabled and val or y, mv.ZToggle.Enabled and val or z)
						elseif AngularVelocity then
							AngularVelocity.Parent = entitylib.isAlive and entitylib.character.RootPart
							AngularVelocity.MaxTorque = Vector3.new(mv.XToggle.Enabled and math.huge or 0, mv.YToggle.Enabled and math.huge or 0, mv.ZToggle.Enabled and math.huge or 0)
							AngularVelocity.AngularVelocity = Vector3.new(Value.Value, Value.Value, Value.Value)
						end
					end
				end))
			else
				if entitylib.isAlive and Mode.Value == 'RotVelocity' then
					entitylib.character.Humanoid.AutoRotate = true
				end
	
				if AngularVelocity then
					AngularVelocity.Parent = nil
				end
			end
		end,
		Tooltip = 'Makes your character spin around in circles.\nSet the spin speed and which ways it turns.'
	})
-- >>> MODULE:Swim (universal:3896-3924)
	mv.Swim = vape.Categories.Blatant:CreateModule({
		Name = 'Swim',
		Function = function(callback)
			if callback then
				mv.Swim:Clean(svc.runService.PreSimulation:Connect(function(dt)
					if entitylib.isAlive then
						local root = entitylib.character.RootPart
						local moving = entitylib.character.Humanoid.MoveDirection ~= Vector3.zero
						local rootvelo = root.Velocity
						local space = svc.inputService:IsKeyDown(Enum.KeyCode.Space)
	
						if terrain then
							local factor = (moving or space) and Vector3.new(6, 6, 6) or Vector3.new(2, 1, 2)
							local pos = root.Position - Vector3.new(0, 1, 0)
							local newpos = Region3.new(pos - factor, pos + factor):ExpandToGrid(4)
							terrain:ReplaceMaterial(mv.lastpos, 4, Enum.Material.Water, Enum.Material.Air)
							terrain:FillRegion(newpos, 4, Enum.Material.Water)
							mv.lastpos = newpos
						end
					end
				end))
			else
				if terrain and mv.lastpos then
					terrain:ReplaceMaterial(mv.lastpos, 4, Enum.Material.Water, Enum.Material.Air)
				end
			end
		end,
		Tooltip = 'Lets you swim through the air as if it were water.'
	})
-- >>> MODULE:TargetStrafe (universal:3942-4037)
	local TargetStrafe
	TargetStrafe = vape.Categories.Blatant:CreateModule({
		Name = 'TargetStrafe',
		ExtraText = function()
			return mv.StrafeRange and tostring(mv.StrafeRange.Value) or nil
		end,
		Function = function(callback)
			if callback then
				if not module then
					local suc = pcall(function() module = require(lplr.PlayerScripts.PlayerModule).controls end)
					if not suc then module = nil end
				end

				local old = module and module.moveFunction
				if type(old) ~= 'function' then
					module = nil
					return
				end
				local state = {Active = true, Previous = old}
				current = state
				local flymod, ang, oldent = vape.Modules.Fly or {Enabled = false}
				state.Hook = function(self, vec, face)
					-- Off, or uninjected (entitylib is cleared then): pass the movement straight on.
					if not state.Active or entitylib == nil then
						return old(self, vec, face)
					end
					local wallcheck = Targets.Walls.Enabled
					local ent = not svc.inputService:IsKeyDown(Enum.KeyCode.S) and entitylib.EntityPosition({
						Range = mv.SearchRange.Value,
						Wallcheck = wallcheck,
						Part = 'RootPart',
						Players = Targets.Players.Enabled,
						NPCs = Targets.NPCs.Enabled
					})
	
					if ent then
						local root, targetPos = entitylib.character.RootPart, ent.RootPart.Position
						ph.rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera, ent.Character}
						ph.rayCheck.CollisionGroup = root.CollisionGroup
	
						if flymod.Enabled or workspace:Raycast(targetPos, Vector3.new(0, -70, 0), ph.rayCheck) then
							local factor, localPosition = 0, root.Position
							if ent ~= oldent then
								ang = math.deg(select(2, CFrame.lookAt(targetPos, localPosition):ToEulerAnglesYXZ()))
							end
	
							local yFactor = math.abs(localPosition.Y - targetPos.Y) * (mv.YFactor.Value / 100)
							local entityPos = Vector3.new(targetPos.X, localPosition.Y, targetPos.Z)
							local newPos = entityPos + (CFrame.Angles(0, math.rad(ang), 0).LookVector * (mv.StrafeRange.Value - yFactor))
							local startRay, endRay = entityPos, newPos
	
							if not wallcheck and workspace:Raycast(targetPos, (localPosition - targetPos), ph.rayCheck) then
								startRay, endRay = entityPos + (CFrame.Angles(0, math.rad(ang), 0).LookVector * (entityPos - localPosition).Magnitude), entityPos
							end
	
							local ray = workspace:Blockcast(CFrame.new(startRay), Vector3.new(1, entitylib.character.HipHeight + (root.Size.Y / 2), 1), (endRay - startRay), ph.rayCheck)
							if (localPosition - newPos).Magnitude < 3 or ray then
								factor = (8 - math.min((localPosition - newPos).Magnitude, 3))
								if ray then
									newPos = ray.Position + (ray.Normal * 1.5)
									factor = (localPosition - newPos).Magnitude > 3 and 0 or factor
								end
							end
	
							if not flymod.Enabled and not workspace:Raycast(newPos, Vector3.new(0, -70, 0), ph.rayCheck) then
								newPos = entityPos
								factor = 40
							end
	
							ang += factor % 360
							vec = ((newPos - localPosition) * Vector3.new(1, 0, 1)).Unit
							vec = vec == vec and vec or Vector3.zero
							TargetStrafeVector = vec
						else
							ent = nil
						end
					end
	
					TargetStrafeVector = ent and vec or nil
					oldent = ent

					return old(self, vec, face)
				end
				module.moveFunction = state.Hook
			else
				if current then
					current.Active = false
					if module and module.moveFunction == current.Hook then
						module.moveFunction = current.Previous
					end
					current = nil
				end
				TargetStrafeVector = nil
			end
		end,
		Tooltip = 'Circles you around the nearest enemy while you move.\nSet how far it looks and how wide it circles. Hold S to stop.'
	})
-- >>> MODULE:Timer (universal:4073-4093)
	mv.Timer = vape.Categories.Blatant:CreateModule({
		Name = 'Timer',
		ExtraText = function()
			return Value and Value.Value..'x' or nil
		end,
		Function = function(callback)
			if callback then
				setfflag('SimEnableStepPhysics', 'True')
				setfflag('SimEnableStepPhysicsSelective', 'True')
	
				mv.Timer:Clean(svc.runService.RenderStepped:Connect(function(dt)
					if Value.Value > 1 then
						svc.runService:Pause()
						workspace:StepPhysics(dt * (Value.Value - 1), {entitylib.character.RootPart})
						svc.runService:Run()
					end
				end))
			end
		end,
		Tooltip = 'Speeds up your character, as if the game ran faster.\nSet how many times faster, up to 3x.'
	})
-- >>> MODULE:Gravity (universal:8316-8354)
	Gravity = vape.Categories.World:CreateModule({
		Name = 'Gravity',
		Tab = 'Move',
		ExtraText = function()
			return Value and tostring(Value.Value) or nil
		end,
		Function = function(callback)
			if callback then
				if Mode.Value == 'Workspace' then
					old = workspace.Gravity
					workspace.Gravity = Value.Value
					Gravity:Clean(workspace:GetPropertyChangedSignal('Gravity'):Connect(function()
						if ph.changed then return end
						ph.changed = true
						old = workspace.Gravity
						workspace.Gravity = Value.Value
						ph.changed = false
					end))
				else
					Gravity:Clean(svc.runService.PreSimulation:Connect(function(dt)
						if entitylib.isAlive and entitylib.character.Humanoid.FloorMaterial == Enum.Material.Air then
							local root = entitylib.character.RootPart
							if Mode.Value == 'Impulse' then
								root:ApplyImpulse(Vector3.new(0, dt * (workspace.Gravity - Value.Value), 0) * root.AssemblyMass)
							else
								root.AssemblyLinearVelocity += Vector3.new(0, dt * (workspace.Gravity - Value.Value), 0)
							end
						end
					end))
				end
			else
				if old then
					workspace.Gravity = old
					old = nil
				end
			end
		end,
		Tooltip = 'Lowers gravity so you fall more slowly.\nApply it to the whole game or just to your own character.'
	})
-- >>> MODULE:Freecam (universal:8235-8298)
	mv.Freecam = vape.Categories.World:CreateModule({
		Name = 'Freecam',
		Tab = 'Visual',
		Function = function(callback)
			if callback then
				--[[ Movement is keyboard only; without one the camera would just be pinned in place. ]]
				if svc.inputService.TouchEnabled and not svc.inputService.KeyboardEnabled then
					notif('Freecam', 'Freecam moves with W, A, S, D, Q and E, so it needs a keyboard.', 5, 'warning')
					mv.Freecam:Toggle(nil, true)
					return
				end

				repeat
					task.wait(0.1)
					for _, v in getconnections(gameCamera:GetPropertyChangedSignal('CameraType')) do
						if v.Function then
							module = debug.getupvalue(v.Function, 1)
						end
					end
				until module or not mv.Freecam.Enabled
	
				if module and module.activeCameraController and mv.Freecam.Enabled then
					old = module.activeCameraController.GetSubjectPosition
					local camPos = old(module.activeCameraController) or Vector3.zero
					module.activeCameraController.GetSubjectPosition = function()
						return camPos
					end
	
					mv.Freecam:Clean(svc.runService.PreSimulation:Connect(function(dt)
						if not svc.inputService:GetFocusedTextBox() then
							local forward = (svc.inputService:IsKeyDown(Enum.KeyCode.W) and -1 or 0) + (svc.inputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
							local side = (svc.inputService:IsKeyDown(Enum.KeyCode.A) and -1 or 0) + (svc.inputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
							local up = (svc.inputService:IsKeyDown(Enum.KeyCode.Q) and -1 or 0) + (svc.inputService:IsKeyDown(Enum.KeyCode.E) and 1 or 0)
							dt = dt * (svc.inputService:IsKeyDown(Enum.KeyCode.LeftShift) and 0.25 or 1)
							camPos = (CFrame.lookAlong(camPos, gameCamera.CFrame.LookVector) * CFrame.new(Vector3.new(side, up, forward) * (Value.Value * dt))).Position
						end
					end))
	
					svc.contextService:BindActionAtPriority('FreecamKeyboard'..randomkey, function()
						return Enum.ContextActionResult.Sink
					end, false, Enum.ContextActionPriority.High.Value,
						Enum.KeyCode.W,
						Enum.KeyCode.A,
						Enum.KeyCode.S,
						Enum.KeyCode.D,
						Enum.KeyCode.E,
						Enum.KeyCode.Q,
						Enum.KeyCode.Up,
						Enum.KeyCode.Down
					)
				end
			else
				pcall(function()
					svc.contextService:UnbindAction('FreecamKeyboard'..randomkey)
				end)
				if module and old then
					module.activeCameraController.GetSubjectPosition = old
					module = nil
					old = nil
				end
			end
		end,
		Tooltip = 'Lets you fly your camera around freely.\nMove with WASD, E and Q, and hold Shift to slow down.'
	})
-- >>> MODULE:Parkour (universal:8378-8396)
	mv.Parkour = vape.Categories.World:CreateModule({
		Name = 'Parkour',
		Tab = 'Move',
		Function = function(callback)
			if callback then 
				local oldfloor
				mv.Parkour:Clean(svc.runService.RenderStepped:Connect(function()
					if entitylib.isAlive then 
						local material = entitylib.character.Humanoid.FloorMaterial
						if material == Enum.Material.Air and oldfloor ~= Enum.Material.Air then 
							entitylib.character.Humanoid.Jump = true
						end
						oldfloor = material
					end
				end))
			end
		end,
		Tooltip = 'Jumps for you automatically as you run off an edge.'
	})
-- >>> MODULE:Xray (universal:8469-8494)
	mv.Xray = vape.Categories.World:CreateModule({
		Name = 'Xray',
		Tab = 'Visual',
		Function = function(callback)
			if callback then
				mv.Xray:Clean(workspace.DescendantAdded:Connect(modifyPart))
				mv.Xray:Clean(workspace.DescendantRemoving:Connect(function(v)
					if modified[v] ~= nil then
						v.LocalTransparencyModifier = modified[v]
					end
					modified[v] = nil
				end))
				for _, v in workspace:GetDescendants() do
					modifyPart(v)
				end
			else
				for i, original in modified do
					if i.Parent then
						i.LocalTransparencyModifier = original
					end
				end
				table.clear(modified)
			end
		end,
		Tooltip = 'Makes the world see-through so you can look past walls.\nParts named in the list stay solid.'
	})
-- >>> MODULE:ESP (universal:5292-5334)
	esp.ESP = vape.Categories.Render:CreateModule({
		Name = 'ESP',
		DisplayName = 'Player ESP',
		Function = function(callback)
			if callback then
				--[[ Every style draws with the Drawing library. Without it the first player threw
				partway through this setup, with EntityRemoved connected and the loop never started,
				and each player who joined threw again. Checked by use, not by type: some executors
				hand Drawing over as userdata. ]]
				if not pcall(function() assert(Drawing.new) end) then
					notif('Player ESP', 'Your executor has no Drawing library to draw with.', 5, 'warning')
					if esp.ESP.Enabled then
						esp.ESP:Toggle(nil, true)
					end
					return
				end
				esp.methodused = 'Drawing'..Method.Value
				esp.ESP:Clean(entitylib.Events.EntityRemoved:Connect(ESPRemoved))
				for _, v in entitylib.List do
					if Reference[v] then
						ESPRemoved(v)
					end
					esp.ESPAdded[esp.methodused](v)
					ESPUpdated(v)
				end
				esp.ESP:Clean(entitylib.Events.EntityAdded:Connect(function(ent)
					if Reference[ent] then
						ESPRemoved(ent)
					end
					esp.ESPAdded[esp.methodused](ent)
				end))
				esp.ESP:Clean(entitylib.Events.EntityUpdated:Connect(ESPUpdated))
				esp.ESP:Clean(svc.runService.RenderStepped:Connect(esp.ESPLoop[esp.methodused]))
			else
				for i in Reference do
					ESPRemoved(i)
				end
				table.clear(esp.LastHealth)
				table.clear(esp.HurtAt)
			end
		end,
		Tooltip = 'Shows boxes around other players, even through walls.\nChoose 2D, 3D or skeleton, with names, health bars and colors.'
	})
-- >>> MODULE:Chams (universal:4697-4751)
	esp.Chams = vape.Categories.Render:CreateModule({
		Name = 'Chams',
		Function = function(callback)
			if callback then
				esp.Chams:Clean(entitylib.Events.EntityRemoved:Connect(Removed))
				esp.Chams:Clean(entitylib.Events.EntityAdded:Connect(function(ent)
					if Reference[ent] then
						Removed(ent)
					end
					Added(ent)
				end))
				esp.Chams:Clean(vape.Categories.Friends.ColorUpdate.Event:Connect(function()
					for i, v in Reference do
						local color = entitylib.getEntityColor(i) or Color3.fromHSV(FillColor.Hue, FillColor.Sat, FillColor.Value)
						if type(v) == 'table' then
							for _, v2 in v do v2.Color3 = color end
						else
							v.FillColor = color
						end
					end
				end))
				-- the folder leaves the gui while the menu is open, so its chams stop drawing
				if vape.ThreadFix then
					setthreadidentity(8)
				end
				local scaled = vape.gui:FindFirstChild('ScaledGui')
				local clickGui = scaled and scaled:FindFirstChild('ClickGui')
				if clickGui then
					esp.Folder.Parent = (not clickGui.Visible) and vape.gui or nil
					esp.Chams:Clean(clickGui:GetPropertyChangedSignal('Visible'):Connect(function()
						if vape.ThreadFix then
							setthreadidentity(8)
						end
						esp.Folder.Parent = (not clickGui.Visible) and vape.gui or nil
					end))
				end
	
				for _, v in entitylib.List do
					if Reference[v] then
						Removed(v)
					end
					Added(v)
				end
			else
				for i in Reference do
					Removed(i)
				end
				if vape.ThreadFix then
					setthreadidentity(8)
				end
				esp.Folder.Parent = vape.gui
			end
		end,
		Tooltip = 'Colors other players so you can see them through walls.\nChoose a glow or box style, its colors and transparency.'
	})
-- >>> MODULE:Tracers (universal:7224-7252)
	tr.Tracers = vape.Categories.Render:CreateModule({
		Name = 'Tracers',
		Function = function(callback)
			if callback then
				tr.Tracers:Clean(entitylib.Events.EntityRemoved:Connect(Removed))
				for _, v in entitylib.List do
					if Reference[v] then
						Removed(v)
					end
					Added(v)
				end
				tr.Tracers:Clean(entitylib.Events.EntityAdded:Connect(function(ent)
					if Reference[ent] then
						Removed(ent)
					end
					Added(ent)
				end))
				tr.Tracers:Clean(vape.Categories.Friends.ColorUpdate.Event:Connect(function()
					tr.ColorFunc(Color.Hue, Color.Sat, Color.Value)
				end))
				tr.Tracers:Clean(svc.runService.RenderStepped:Connect(tr.Loop))
			else
				for i in Reference do
					Removed(i)
				end
			end
		end,
		Tooltip = 'Draws lines from your screen to other players.\nSet where lines start and end, colors, distance limits and off-screen lines.'
	})
-- >>> MODULE:Waypoints (universal:7352-7414)
	tr.Waypoints = vape.Categories.Render:CreateModule({
		Name = 'Waypoints',
		Function = function(callback)
			--[[ The waypoints live in Catvape's GUI (CoreGui or gethui wherever the identity
			can be raised), and this thread does not carry that identity; both ways, since
			switching off clears the folder. Each point is built whole and then parented, so an
			entry that is not 'x, y, z/name' costs itself rather than every point after it. ]]
			-- Guarded: a bare setthreadidentity(8) throws on an executor capped below 8.
			if vape.ThreadFix and not pcall(setthreadidentity, 8) then
				pcall(setthreadidentity, 7)
			end
			if callback then
				-- the folder leaves the gui while the menu is open, so its points stop drawing
				local scaled = vape.gui:FindFirstChild('ScaledGui')
				local clickGui = scaled and scaled:FindFirstChild('ClickGui')
				if clickGui then
					WaypointFolder.Parent = (not clickGui.Visible) and vape.gui or nil
					tr.Waypoints:Clean(clickGui:GetPropertyChangedSignal('Visible'):Connect(function()
						if vape.ThreadFix and not pcall(setthreadidentity, 8) then
							pcall(setthreadidentity, 7)
						end
						WaypointFolder.Parent = (not clickGui.Visible) and vape.gui or nil
					end))
				end
				for _, v in List.ListEnabled do
					local billboard
					local ok = pcall(function()
						local split = v:split('/')
						local tagSize = getfontsize(removeTags(split[2]), 14 * Scale.Value, tr.FontOption.Value, Vector2.new(100000, 100000))
						billboard = Instance.new('BillboardGui')
						billboard.Size = UDim2.fromOffset(tagSize.X + 12, tagSize.Y + 7)
						--[[ Anchored to Terrain, which sits at the world origin, so the offset is the
						point itself. With no Adornee a billboard in the GUI folder has nowhere in
						the world to be drawn, and no waypoint ever showed. ]]
						billboard.Adornee = workspace.Terrain
						billboard.StudsOffsetWorldSpace = Vector3.new(unpack(split[1]:split(',')))
						billboard.AlwaysOnTop = true
						-- A small loader box; its border goes with the background when that is cleared.
						local tag = Instance.new('TextLabel')
						local stroke = loaderStyle.box(tag, UDim.new(0, 6))
						stroke.Enabled = Background.Value < 1
						tag.Visible = true
						tag.RichText = true
						tag.TextSize = 14 * Scale.Value
						tag.BackgroundTransparency = Background.Value
						tag.Size = billboard.Size
						tag.Text = split[2]
						loaderStyle.text(tag, 'Medium')
						tag.TextColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
						tag.Parent = billboard
						billboard.Parent = WaypointFolder
					end)
					if not ok and billboard then
						pcall(function() billboard:Destroy() end)
					end
				end
			else
				WaypointFolder:ClearAllChildren()
				WaypointFolder.Parent = vape.gui
			end
		end,
		Tooltip = 'Shows named markers at spots in the world you save.\nAdd points by position or where you stand, and style their labels.'
	})
-- >>> MODULE:Arrows (universal:4458-4483)
	tr.Arrows = vape.Categories.Render:CreateModule({
		Name = 'Arrows',
		DisplayName = 'Pointers',
		Function = function(callback)
			if callback then
				-- A start queued while a profile loads can arrive after the module was turned off.
				if not tr.Arrows.Enabled then return end
				tr.Arrows:Clean(entitylib.Events.EntityRemoved:Connect(Removed))
				for _, v in entitylib.List do
					if Reference[v] then Removed(v) end
					Added(v)
				end
				tr.Arrows:Clean(entitylib.Events.EntityAdded:Connect(function(ent)
					if Reference[ent] then Removed(ent) end
					Added(ent)
				end))
				tr.Arrows:Clean(svc.runService.RenderStepped:Connect(tr.Loop))
			else
				for i in Reference do
					Removed(i)
				end
				closestEnt = nil
			end
		end,
		Tooltip = 'Draws pointers around your crosshair towards other players.\nThe closest one is red; set range, size, style and colors.'
	})
-- >>> MODULE:Search (universal:6571-6616)
	tr.Search = vape.Categories.Render:CreateModule({
		Name = 'Search',
		Function = function(callback)
			if callback then
				table.clear(tr.Names)
				for _, name in List.ListEnabled do
					tr.Names[name] = true
				end
				tr.Search:Clean(workspace.DescendantAdded:Connect(addCandidate))
				tr.Search:Clean(workspace.DescendantRemoving:Connect(function(v)
					if Reference[v] then
						Reference[v]:Destroy()
						Reference[v] = nil
					end
				end))
				for _, v in workspace:GetDescendants() do
					if tr.Names[v.Name] then
						tr.Add(v)
					end
				end
				-- the folder leaves the gui while the menu is open, so its boxes stop drawing
				if vape.ThreadFix then
					setthreadidentity(8)
				end
				local scaled = vape.gui:FindFirstChild('ScaledGui')
				local clickGui = scaled and scaled:FindFirstChild('ClickGui')
				if clickGui then
					esp.Folder.Parent = (not clickGui.Visible) and vape.gui or nil
					tr.Search:Clean(clickGui:GetPropertyChangedSignal('Visible'):Connect(function()
						if vape.ThreadFix then
							setthreadidentity(8)
						end
						esp.Folder.Parent = (not clickGui.Visible) and vape.gui or nil
					end))
				end
			else
			esp.Folder:ClearAllChildren()
			if vape.ThreadFix then
				setthreadidentity(8)
			end
			esp.Folder.Parent = vape.gui
			table.clear(Reference)
		end
		end,
		Tooltip = 'Shows boxes around parts you name, even through walls.\nAdd part names to the list and pick the box color and transparency.'
	})
-- >>> MODULE:PlayerModel (universal:6236-6275)
	tr.PlayerModel = vape.Categories.Render:CreateModule({
		Name = 'PlayerModel',
		Function = function(callback)
			if callback then 
				chair.modelGeneration += 1
				local generation = chair.modelGeneration
				if tr.Local.Enabled then 
					tr.PlayerModel:Clean(entitylib.Events.LocalAdded:Connect(function(ent)
						chair.addMesh(ent, generation)
					end))
					tr.PlayerModel:Clean(entitylib.Events.LocalRemoved:Connect(chair.removeMesh))
					if entitylib.isAlive then 
						task.spawn(function()
							if generation == chair.modelGeneration and tr.PlayerModel.Enabled then
								chair.addMesh(entitylib.character, generation)
							end
						end)
					end
				end
				tr.PlayerModel:Clean(entitylib.Events.EntityAdded:Connect(function(ent)
					chair.addMesh(ent, generation)
				end))
				tr.PlayerModel:Clean(entitylib.Events.EntityRemoved:Connect(chair.removeMesh))
				for _, ent in entitylib.List do 
					task.spawn(function()
						if generation == chair.modelGeneration and tr.PlayerModel.Enabled then
							chair.addMesh(ent, generation)
						end
					end)
				end
			else
				chair.modelGeneration += 1
				for _, part in chair.models do 
					part:Destroy()
				end
				table.clear(chair.models)
			end
		end,
		Tooltip = 'Puts a custom 3D model on other players.\nSet the mesh, texture, size and rotation; Local adds one to you too.'
	})
-- >>> MODULE:GamingChair (universal:5558-5762)
	chair.GamingChair = vape.Categories.Render:CreateModule({
		Name = 'GamingChair',
		Function = function(callback)
			generation += 1
			if callback then
				if vape.ThreadFix then
					setthreadidentity(8)
				end
				chair.chair = Instance.new('MeshPart')
				chair.chair.Color = Color3.fromRGB(21, 21, 21)
				chair.chair.Size = Vector3.new(2.16, 3.6, 2.3) / Vector3.new(12.37, 20.636, 13.071)
				chair.chair.CanCollide = false
				chair.chair.Massless = true
				chair.chair.MeshId = 'rbxassetid://12972961089'
				chair.chair.Material = Enum.Material.SmoothPlastic
				chair.chair.Parent = workspace
				chair.movingsound = Instance.new('Sound')
				--[[ chair.movingsound.SoundId = downloadVapeAsset('vape/assets/ChairRolling.mp3') ]]
				chair.movingsound.Volume = 0.4
				chair.movingsound.Looped = true
				chair.movingsound.Parent = workspace
				chair.flyingsound = Instance.new('Sound')
				--[[ chair.flyingsound.SoundId = downloadVapeAsset('vape/assets/ChairFlying.mp3') ]]
				chair.flyingsound.Volume = 0.4
				chair.flyingsound.Looped = true
				chair.flyingsound.Parent = workspace
				local chairweld = Instance.new('WeldConstraint')
				chairweld.Part0 = chair.chair
				chairweld.Parent = chair.chair
				if entitylib.isAlive then
					chair.chair.CFrame = entitylib.character.RootPart.CFrame * CFrame.Angles(0, math.rad(-90), 0)
					chairweld.Part1 = entitylib.character.RootPart
				end
				chairhighlight = Instance.new('Highlight')
				chairhighlight.FillTransparency = 1
				chairhighlight.OutlineColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
				chairhighlight.DepthMode = Enum.HighlightDepthMode.Occluded
				chairhighlight.OutlineTransparency = 0.2
				chairhighlight.Parent = chair.chair
				local chairarms = Instance.new('MeshPart')
				chairarms.Color = chair.chair.Color
				chairarms.Size = Vector3.new(1.39, 1.345, 2.75) / Vector3.new(97.13, 136.216, 234.031)
				chairarms.CFrame = chair.chair.CFrame * CFrame.new(-0.169, -1.129, -0.013)
				chairarms.MeshId = 'rbxassetid://12972673898'
				chairarms.CanCollide = false
				chairarms.Parent = chair.chair
				local chairarmsweld = Instance.new('WeldConstraint')
				chairarmsweld.Part0 = chairarms
				chairarmsweld.Part1 = chair.chair
				chairarmsweld.Parent = chair.chair
				local chairlegs = Instance.new('MeshPart')
				chairlegs.Color = chair.chair.Color
				chairlegs.Name = 'Legs'
				chairlegs.Size = Vector3.new(1.8, 1.2, 1.8) / Vector3.new(10.432, 8.105, 9.488)
				chairlegs.CFrame = chair.chair.CFrame * CFrame.new(0.047, -2.324, 0)
				chairlegs.MeshId = 'rbxassetid://13003181606'
				chairlegs.CanCollide = false
				chairlegs.Parent = chair.chair
				local chairfan = Instance.new('MeshPart')
				chairfan.Color = chair.chair.Color
				chairfan.Name = 'Fan'
				chairfan.Size = Vector3.zero
				chairfan.CFrame = chair.chair.CFrame * CFrame.new(0, -1.873, 0)
				chairfan.MeshId = 'rbxassetid://13004977292'
				chairfan.CanCollide = false
				chairfan.Parent = chair.chair
				local trails = {}
				for _, v in chair.wheelpositions do
					local attachment = Instance.new('Attachment')
					attachment.Position = v
					attachment.Parent = chairlegs
					local attachment2 = Instance.new('Attachment')
					attachment2.Position = v + Vector3.new(0, 0, 0.18)
					attachment2.Parent = chairlegs
					local trail = Instance.new('Trail')
					trail.Texture = 'http://www.roblox.com/asset/?id=13005168530'
					trail.TextureMode = Enum.TextureMode.Static
					trail.Transparency = NumberSequence.new(0.5)
					trail.Color = ColorSequence.new(Color3.new(0.5, 0.5, 0.5))
					trail.Attachment0 = attachment
					trail.Attachment1 = attachment2
					trail.Lifetime = 20
					trail.MaxLength = 60
					trail.MinLength = 0.1
					trail.Parent = chairlegs
					table.insert(trails, trail)
				end
				chair.GamingChair:Clean(chair.chair)
				chair.GamingChair:Clean(chair.movingsound)
				chair.GamingChair:Clean(chair.flyingsound)
				chair.chairanim = {Stop = function() end}
				local oldmoving = false
				local oldflying = false
				local gen = generation
				repeat
					if entitylib.isAlive and entitylib.character.Humanoid.Health > 0 then
						if not chair.chairanim.IsPlaying then
							local temp2 = Instance.new('Animation')
							temp2.AnimationId = entitylib.character.Humanoid.RigType == Enum.HumanoidRigType.R15 and 'http://www.roblox.com/asset/?id=2506281703' or 'http://www.roblox.com/asset/?id=178130996'
							chair.chairanim = entitylib.character.Humanoid:LoadAnimation(temp2)
							chair.chairanim.Priority = Enum.AnimationPriority.Movement
							chair.chairanim.Looped = true
							chair.chairanim:Play()
						end
						chair.chair.CFrame = entitylib.character.RootPart.CFrame * CFrame.Angles(0, math.rad(-90), 0)
						chairweld.Part1 = entitylib.character.RootPart
						chairlegs.Velocity = Vector3.zero
						chairlegs.CFrame = chair.chair.CFrame * CFrame.new(0.047, -2.324, 0)
						chairfan.Velocity = Vector3.zero
						chairfan.CFrame = chair.chair.CFrame * CFrame.new(0.047, -1.873, 0) * CFrame.Angles(0, math.rad(tick() * 180 % 360), math.rad(180))
						local moving = entitylib.character.Humanoid:GetState() == Enum.HumanoidStateType.Running and entitylib.character.Humanoid.MoveDirection ~= Vector3.zero
						local flying = vape.Modules.Fly and vape.Modules.Fly.Enabled or vape.Modules.LongJump and vape.Modules.LongJump.Enabled or vape.Modules.InfiniteFly and vape.Modules.InfiniteFly.Enabled
						if chair.movingsound.TimePosition > 1.9 then
							chair.movingsound.TimePosition = 0.2
						end
						chair.movingsound.PlaybackSpeed = (entitylib.character.RootPart.Velocity * Vector3.new(1, 0, 1)).Magnitude / 16
						for _, v in trails do
							v.Enabled = not flying and moving
							v.Color = ColorSequence.new(chair.movingsound.PlaybackSpeed > 1.5 and Color3.new(1, 0.5, 0) or Color3.new())
						end
						if moving ~= oldmoving then
							if chair.movingsound.IsPlaying then
								if not moving then
									chair.movingsound:Stop()
								end
							else
								if not flying and moving then
									chair.movingsound:Play()
								end
							end
							oldmoving = moving
						end
						if flying ~= oldflying then
							if flying then
								if chair.movingsound.IsPlaying then
									chair.movingsound:Stop()
								end
								if not chair.flyingsound.IsPlaying then
									chair.flyingsound:Play()
								end
								if chair.currenttween then
									chair.currenttween:Cancel()
								end
								chair.currenttween = svc.tweenService:Create(chairlegs, TweenInfo.new(0.15), {
									Size = Vector3.zero
								})
								chair.currenttween.Completed:Connect(function(state)
									if state == Enum.PlaybackState.Completed then
										chairfan.Transparency = 0
										chairlegs.Transparency = 1
										chair.currenttween = svc.tweenService:Create(chairfan, TweenInfo.new(0.15), {
											Size = Vector3.new(1.534, 0.328, 1.537) / Vector3.new(791.138, 168.824, 792.027)
										})
										chair.currenttween:Play()
									end
								end)
								chair.currenttween:Play()
							else
								if chair.flyingsound.IsPlaying then
									chair.flyingsound:Stop()
								end
								if not chair.movingsound.IsPlaying and moving then
									chair.movingsound:Play()
								end
								if chair.currenttween then chair.currenttween:Cancel() end
								chair.currenttween = svc.tweenService:Create(chairfan, TweenInfo.new(0.15), {
									Size = Vector3.zero
								})
								chair.currenttween.Completed:Connect(function(state)
									if state == Enum.PlaybackState.Completed then
										chairfan.Transparency = 1
										chairlegs.Transparency = 0
										chair.currenttween = svc.tweenService:Create(chairlegs, TweenInfo.new(0.15), {
											Size = Vector3.new(1.8, 1.2, 1.8) / Vector3.new(10.432, 8.105, 9.488)
										})
										chair.currenttween:Play()
									end
								end)
								chair.currenttween:Play()
							end
							oldflying = flying
						end
					else
						chair.chair.Anchored = true
						chairlegs.Anchored = true
						chairfan.Anchored = true
						--[[ Uninject clears entitylib while this waits for a respawn, and a stale loop must
						not unanchor the new chair.chair, so both stop here; switching off destroys the chair.chair. ]]
						repeat task.wait() until not (chair.GamingChair.Enabled and generation == gen and entitylib) or entitylib.isAlive and entitylib.character.Humanoid.Health > 0
						if not (chair.GamingChair.Enabled and generation == gen and entitylib) then break end
						chair.chair.Anchored = false
						chairlegs.Anchored = false
						chairfan.Anchored = false
						chair.chairanim:Stop()
					end
					task.wait()
				until not chair.GamingChair.Enabled or generation ~= gen
			else
				if chair.chairanim then
					chair.chairanim:Stop()
				end
			end
		end,
		Tooltip = 'Sit in the best gaming chair known to mankind.\nIt rolls along with you and hovers while you fly.'
	})
-- >>> MODULE:Fullbright (universal:5495-5527)
	Fullbright = vape.Categories.Render:CreateModule({
		Name = 'Fullbright',
		Function = function(callback)
			generation += 1
			if callback then
				if Mode.Value == 'Lighting' then
					for _, v in {'Ambient', 'OutdoorAmbient', 'Brightness'} do
						light.oldsettings[v] = svc.lightingService[v]
					end
	
					Fullbright:Clean(svc.lightingService.Changed:Connect(light.ChangeLighting))
					task.spawn(light.ChangeLighting)
				else
					local inst = Instance.new('PointLight')
					inst.Range = 1000
					Fullbright:Clean(inst)

					local gen = generation
					repeat
						inst.Parent = entitylib.isAlive and entitylib.character.RootPart or nil
						task.wait(0.1)
					until not Fullbright.Enabled or generation ~= gen
				end
			else
				light.flag = false
				for i, v in light.oldsettings do
					svc.lightingService[i] = v
				end
				table.clear(light.oldsettings)
			end
		end,
		Tooltip = 'Lights up the world so dark areas are easy to see.\nBrighten the whole map, or carry a light around with you.'
	})
-- >>> MODULE:ZoomUnlocker (universal:10288-10308)
	zoom.ZoomUnlocker = vape.Categories.Utility:CreateModule({
		Name = 'ZoomUnlocker',
		Tab = 'Visual',
		Function = function(callback)
			if callback then
				zoom.applyZoom()
				zoom.zoomConn = lplr:GetPropertyChangedSignal('CameraMaxZoomDistance'):Connect(zoom.queueZoom)
			else
				if zoom.zoomConn then
					pcall(function() zoom.zoomConn:Disconnect() end)
					zoom.zoomConn = nil
				end
				zoom.pending = false
				--[[ Restore the place default, not the value present when the module was
				enabled: enabling mid-scope would otherwise capture 6.5 and restore it as
				the normal value. ]]
				lplr.CameraMaxZoomDistance = zoom.defaultMaxZoom()
			end
		end,
		Tooltip = 'Lets you zoom your camera further out.'
	})
-- >>> MODULE:ServerHop (universal:8037-8046)
	ServerHop = vape.Categories.Utility:CreateModule({
		Name = 'ServerHop',
		Function = function(callback)
			if callback then
				ServerHop:Toggle()
				sph.serverHop(nil, Sort.Value)
			end
		end,
		Tooltip = 'Moves you to a different server of this game.\nPrefer full or empty servers, or go back to the previous one.'
	})
-- >>> MODULE:anim.AutoRejoin (universal:7603-7617)
	anim.AutoRejoin = vape.Categories.Utility:CreateModule({
		Name = 'AutoRejoin',
		Function = function(callback)
			if callback then
				local check
				anim.AutoRejoin:Clean(svc.guiService.ErrorMessageChanged:Connect(function(str)
					if (not check or svc.guiService:GetErrorCode() ~= Enum.ConnectionError.DisconnectLuaKick) and svc.guiService:GetErrorCode() ~= Enum.ConnectionError.DisconnectConnectionLost and not str:lower():find('ban') then
						check = true
						sph.serverHop(nil, Sort.Value)
					end
				end))
			end
		end,
		Tooltip = 'Automatically joins a new server when you get kicked.\nChoose whether it prefers full or empty servers.'
	})
-- >>> MODULE:anim.Rejoin (universal:8015-8030)
	anim.Rejoin = vape.Categories.Utility:CreateModule({
		Name = 'Rejoin',
		Function = function(callback)
			if callback then
				notif('Rejoin', 'Rejoining...', 5)
				anim.Rejoin:Toggle()
	
				if svc.playersService.NumPlayers > 1 then
					svc.teleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId)
				else
					svc.teleportService:Teleport(game.PlaceId)
				end
			end
		end,
		Tooltip = 'Rejoins the server you are in.'
	})
-- >>> MODULE:anim.AntiRagdoll (universal:7582-7596)
	anim.AntiRagdoll = vape.Categories.Utility:CreateModule({
		Name = 'AntiRagdoll',
		Function = function(callback)
			if entitylib.isAlive then
				entitylib.character.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not callback)
			end
	
			if callback then
				anim.AntiRagdoll:Clean(entitylib.Events.LocalAdded:Connect(function(char)
					char.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
				end))
			end
		end,
		Tooltip = 'Stops you from getting knocked into a ragdoll.'
	})
-- >>> MODULE:anim.AnimationPlayer (universal:7518-7540)
	anim.AnimationPlayer = vape.Categories.Utility:CreateModule({
		Name = 'AnimationPlayer',
		Function = function(callback)
			if callback then
				animobject = Instance.new('Animation')
				local suc, id = pcall(function()
					return string.match(game:GetObjects('rbxassetid://'..anim.IDBox.Value)[1].AnimationId, '%?id=(%d+)')
				end)
				animobject.AnimationId = 'rbxassetid://'..(suc and id or anim.IDBox.Value)
	
				if entitylib.isAlive then
					playAnimation(entitylib.character)
				end
				anim.AnimationPlayer:Clean(entitylib.Events.LocalAdded:Connect(playAnimation))
				anim.AnimationPlayer:Clean(animobject)
			else
				if anim then
					anim:Stop()
				end
			end
		end,
		Tooltip = 'Plays an animation of your choosing.\nEnter an animation id, then set its speed and priority.'
	})
-- >>> MODULE:chat.ChatSpammer (universal:7867-7936)
chat.ChatSpammer = vape.Categories.Utility:CreateModule({
	Name = 'ChatSpammer',
	Function = function(callback)
		chat.spamGeneration += 1
		if callback then
			if #Lines.ListEnabled == 0 then
				notif('ChatSpammer', 'Add a line to send first.', 5, 'warning')
				chat.ChatSpammer:Toggle(nil, true)
				return
			end

			if svc.textChatService.ChatVersion == Enum.ChatVersion.TextChatService then
				if chat.Hide.Enabled and svc.coreGui:FindFirstChild('ExperienceChat') then
					chat.ChatSpammer:Clean(svc.coreGui.ExperienceChat.appLayout.chatWindow.contentFrame.scrollingView.bottomLockedScrollView.scrollView.ChildAdded:Connect(function(msg)
						if msg.Name:sub(1, 2) == '0-' and msg.TextMessage.BodyText.Text == '<font color="#d4d4d4">You must wait before sending another message.</font>' then
							msg.Visible = false
						end
					end))
				end
			elseif svc.replicatedStorage:FindFirstChild('DefaultChatSystemChatEvents') then
				if chat.Hide.Enabled then
					chat.oldchat = hookfunction(getconnections(svc.replicatedStorage.DefaultChatSystemChatEvents.OnNewSystemMessage.OnClientEvent)[1].Function, function(data, ...)
						if data.Message:find('ChatFloodDetector') then return end
						return chat.oldchat(data, ...)
					end)
				end
			else
				notif('ChatSpammer', 'unsupported chat', 5, 'warning')
				chat.ChatSpammer:Toggle()
				return
			end

			local index = 1
			local gen = chat.spamGeneration
			repeat
				--[[ Nothing is sent while the list is empty (it can be cleared mid-run). ]]
				local message
				if #Lines.ListEnabled > 0 then
					if Mode.Value == 'Order' then
						message = Lines.ListEnabled[index] or Lines.ListEnabled[1]
						index = (index % #Lines.ListEnabled) + 1
					else
						if #chat.RandomList <= 0 then
							chat.RandomList = table.clone(Lines.ListEnabled)
						end

						local entry = Random.new():NextInteger(1, #chat.RandomList)
						message = chat.RandomList[entry]
						table.remove(chat.RandomList, entry)
					end
				end

				if message then
					if svc.textChatService.ChatVersion == Enum.ChatVersion.TextChatService then
						svc.textChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync(message)
					else
						svc.replicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(message, 'All')
					end
				end

				task.wait(ph.Delay.Value)
			until not chat.ChatSpammer.Enabled or chat.spamGeneration ~= gen
		else
			if chat.oldchat then
				hookfunction(getconnections(svc.replicatedStorage.DefaultChatSystemChatEvents.OnNewSystemMessage.OnClientEvent)[1].Function, chat.oldchat)
			end
		end
	end,
	Tooltip = 'Sends your chosen messages in chat over and over.\nSet the lines, random or in order, the delay, and hide the wait warning.'
})
-- >>> MODULE:PromptChanger (universal:7695-7738)
	prompt.PromptChanger = vape.Categories.Utility:CreateModule({
		Name = 'PromptChanger',
		Function = function(callback)
			if callback then
				prompt.updateAllPrompts()
				prompt.PromptChanger:Clean(svc.proxService.PromptShown:Connect(function(prompt)
					prompt.updatePrompt(prompt)
					if Mode.Value == 'Property' then
						prompt.applyHoldDuration(prompt)
					end
				end))
				prompt.PromptChanger:Clean(workspace.DescendantAdded:Connect(function(instance)
					prompt.updatePrompt(instance)
				end))

				if Mode.Value == 'Signal' then
					prompt.PromptChanger:Clean(svc.proxService.PromptButtonHoldBegan:Connect(function(prompt, plr)
						if plr == lplr then
							thread = task.delay(prompt.HoldDuration * (Modifier.Value / 100), function()
								fireproximityprompt(prompt)
								thread = nil
							end)
						end
					end))
					prompt.PromptChanger:Clean(svc.proxService.PromptButtonHoldEnded:Connect(function(prompt, plr)
						if plr == lplr and thread then
							task.cancel(thread)
							thread = nil
						end
					end))
				else
					prompt.PromptChanger:Clean(svc.proxService.PromptHidden:Connect(function(prompt)
						if modified[prompt] then
							prompt.HoldDuration = modified[prompt]
							modified[prompt] = nil
						end
					end))
				end
			else
				prompt.restorePrompts()
			end
		end,
		Tooltip = 'Lets you use interact prompts from further away and faster.\nSet the reach, and the hold time as a percent of normal.'
	})
-- >>> MODULE:MurderMystery (universal:8548-8583)
	MurderMystery = vape.Categories.Minigames:CreateModule({
		Name = 'MurderMystery',
		Tab = 'Utility',
		Function = function(callback)
			if callback then
				oldtargetable, oldgetcolor = entitylib.targetCheck, entitylib.getEntityColor
	
				entitylib.getEntityColor = function(ent)
					ent = ent.Player
					if not (ent and vape.Categories.Main.Options['Use team color'].Enabled) then return end
					if isFriend(ent, true) then
						return Color3.fromHSV(vape.Categories.Friends.Options['Friends color'].Hue, vape.Categories.Friends.Options['Friends color'].Sat, vape.Categories.Friends.Options['Friends color'].Value)
					end
					return murderer == ent and Color3.new(1, 0.3, 0.3) or sheriff == ent and Color3.new(0, 0.5, 1) or nil
				end
	
				entitylib.targetCheck = function(ent)
					if ent.Player and isFriend(ent.Player) then return false end
					if murderer == lplr then return true end
					return murderer == ent.Player or sheriff == ent.Player
				end
	
				for _, v in svc.playersService:GetPlayers() do
					playerAdded(v)
				end
	
				MurderMystery:Clean(svc.playersService.PlayerAdded:Connect(playerAdded))
				entitylib.refresh()
			else
				entitylib.getEntityColor = oldgetcolor
				entitylib.targetCheck = oldtargetable
				entitylib.refresh()
			end
		end,
		Tooltip = 'Finds the murderer and sheriff from their weapons.\nColors them and makes them your targets, or everyone if you are the murderer.'
	})
end
