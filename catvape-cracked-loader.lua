--!nocheck
--[[
    SLOP BUILD - self-contained GitHub loader
    - pulls every file from the public GitHub raw repo, no workspace folder needed
    - installs into catsix/, then runs entirely from local files
    - zero requests to catvape's own API
]]

local Repo = "https://raw.githubusercontent.com/amack7002-code/CatV6-but-better/main"
local Directory = "catsix"

-- Places this build has a game module for. Anywhere else only the universal menus are built, so the
-- game-only modules are not loaded at all instead of sitting there doing nothing.
local SupportedPlaces = {
	[6872274481] = true, -- BedWars
	[6872265039] = true, -- BedWars (second place)
	[8444591321] = true,
	[8560631822] = true,
	[139566161526375] = true,
}
local Supported = SupportedPlaces[game.PlaceId] == true
shared.catvapesupported = Supported

if not game:IsLoaded() then
	game.Loaded:Wait()
end
if shared.vapeloading and coroutine.status(shared.vapeloading) ~= "dead" then
	return
end
shared.vapeloading = coroutine.running()
if shared.vape then
	shared.vape:Uninject()
end

for _, Folder in {Directory, Directory.."/games", Directory.."/profiles", Directory.."/assets", Directory.."/libraries", Directory.."/guis"} do
	if not isfolder(Folder) then
		makefolder(Folder)
	end
end

local Files = {
	"src/assets/new/add.png",
	"src/assets/new/aim.png",
	"src/assets/new/allowedicon.png",
	"src/assets/new/allowediconmini.png",
	"src/assets/new/arrowmodule.png",
	"src/assets/new/back.png",
	"src/assets/new/backmini.png",
	"src/assets/new/bahnschrift.json",
	"src/assets/new/bahnschrift.ttf",
	"src/assets/new/bind.png",
	"src/assets/new/bindbkg.png",
	"src/assets/new/blatant.png",
	"src/assets/new/blockedicon.png",
	"src/assets/new/blockedtab.png",
	"src/assets/new/blur.png",
	"src/assets/new/blurnoti.png",
	"src/assets/new/cheat_switch.png",
	"src/assets/new/close.png",
	"src/assets/new/closemini.png",
	"src/assets/new/closetiny.png",
	"src/assets/new/colorpreview.png",
	"src/assets/new/combat.png",
	"src/assets/new/combo_display.png",
	"src/assets/new/compassarrow.png",
	"src/assets/new/customtheme.png",
	"src/assets/new/discord.png",
	"src/assets/new/dislike.png",
	"src/assets/new/downexpand.png",
	"src/assets/new/downexpandslider.png",
	"src/assets/new/edit.png",
	"src/assets/new/editlarge.png",
	"src/assets/new/empty.png",
	"src/assets/new/expandarrow.png",
	"src/assets/new/expandright.png",
	"src/assets/new/expandup.png",
	"src/assets/new/favoritesicon.png",
	"src/assets/new/friends.png",
	"src/assets/new/hide.png",
	"src/assets/new/inventory.png",
	"src/assets/new/key_down.png",
	"src/assets/new/key_left.png",
	"src/assets/new/key_lmb.png",
	"src/assets/new/key_mmb.png",
	"src/assets/new/key_right.png",
	"src/assets/new/key_rmb.png",
	"src/assets/new/key_up.png",
	"src/assets/new/legit_atmosphere.png",
	"src/assets/new/legit_bedalarm.png",
	"src/assets/new/legit_bedbreakeffect.png",
	"src/assets/new/legit_breadcrumbs.png",
	"src/assets/new/legit_bullettracers.png",
	"src/assets/new/legit_cape.png",
	"src/assets/new/legit_chinahat.png",
	"src/assets/new/legit_cleankit.png",
	"src/assets/new/legit_clock.png",
	"src/assets/new/legit_compass.png",
	"src/assets/new/legit_coords.png",
	"src/assets/new/legit_crosshair.png",
	"src/assets/new/legit_damageindicator.png",
	"src/assets/new/legit_disguise.png",
	"src/assets/new/legit_fflageditor.png",
	"src/assets/new/legit_fixguis.png",
	"src/assets/new/legit_fov.png",
	"src/assets/new/legit_fps.png",
	"src/assets/new/legit_fpsboost.png",
	"src/assets/new/legit_fpsunlocker.png",
	"src/assets/new/legit_hideshield.png",
	"src/assets/new/legit_hitcolor.png",
	"src/assets/new/legit_hitfix.png",
	"src/assets/new/legit_hitsound.png",
	"src/assets/new/legit_interface.png",
	"src/assets/new/legit_keybinds.png",
	"src/assets/new/legit_keystrokes.png",
	"src/assets/new/legit_killeffect.png",
	"src/assets/new/legit_killsound.png",
	"src/assets/new/legit_memory.png",
	"src/assets/new/legit_mode_icon.png",
	"src/assets/new/legit_ping.png",
	"src/assets/new/legit_potionstatus.png",
	"src/assets/new/legit_reachdisplay.png",
	"src/assets/new/legit_songbeats.png",
	"src/assets/new/legit_soundchanger.png",
	"src/assets/new/legit_speedmeter.png",
	"src/assets/new/legit_switch.png",
	"src/assets/new/legit_timechanger.png",
	"src/assets/new/legit_uicleanup.png",
	"src/assets/new/legit_viewmodel.png",
	"src/assets/new/legit_wineffect.png",
	"src/assets/new/like.png",
	"src/assets/new/min.png",
	"src/assets/new/newhide.png",
	"src/assets/new/noti_alert.png",
	"src/assets/new/noti_info.png",
	"src/assets/new/noti_warning.png",
	"src/assets/new/notification.png",
	"src/assets/new/npcs.png",
	"src/assets/new/overlaydots.png",
	"src/assets/new/overlays.png",
	"src/assets/new/overlayslarge.png",
	"src/assets/new/pin.png",
	"src/assets/new/players.png",
	"src/assets/new/profiles.png",
	"src/assets/new/profilesicon.png",
	"src/assets/new/profileworld.png",
	"src/assets/new/proxima.json",
	"src/libraries/entity.lua",
	"src/libraries/hash.lua",
	"src/libraries/prediction.lua",
	"src/libraries/render.lua",
	"src/libraries/drawing.lua",
	"src/libraries/vm.lua",
	"src/libraries/navigation.lua",
	"src/libraries/cheatengine.lua",
	"src/libraries/replayvisuals.lua",
	"src/libraries/swordtiming.lua",
	"src/libraries/communication.lua",
	"src/libraries/assistant.lua",
	"src/assets/new/proxima.ttf",
	"src/assets/new/proximabd.ttf",
	"src/assets/new/radar.png",
	"src/assets/new/radaricon.png",
	"src/assets/new/rainbow_1.png",
	"src/assets/new/rainbow_2.png",
	"src/assets/new/rainbow_3.png",
	"src/assets/new/rainbow_4.png",
	"src/assets/new/range.png",
	"src/assets/new/rangearrow.png",
	"src/assets/new/rangeindicator.png",
	"src/assets/new/render.png",
	"src/assets/new/search.png",
	"src/assets/new/settingdots.png",
	"src/assets/new/settings.png",
	"src/assets/new/settingsmini.png",
	"src/assets/new/show.png",
	"src/assets/new/star.png",
	"src/assets/new/sword_header.png",
	"src/assets/new/targetinfo.png",
	"src/assets/new/targetnpc1.png",
	"src/assets/new/targetplayers1.png",
	"src/assets/new/targetstab.png",
	"src/assets/new/textgui.png",
	"src/assets/new/textguiicon.png",
	"src/assets/new/textguiline.png",
	"src/assets/new/theme.png",
	"src/assets/new/triangle.png",
	"src/assets/new/utility.png",
	"src/assets/new/v4.png",
	"src/assets/new/v4mini.png",
	"src/assets/new/vape.png",
	"src/assets/new/vapelogo.png",
	"src/assets/new/vapelogomini.png",
	"src/assets/new/world.png",
	"src/features.json",
	"src/games/139566161526375.lua",
	"src/games/6872265039.lua",
	"src/games/6872274481.lua",
	"src/games/8444591321.lua",
	"src/games/8560631822.lua",
	"src/games/extras.lua",
	"src/games/staffdetector.lua",
	"src/games/spectatordetector.lua",
	"src/games/cheatwatcher.lua",
	"src/games/ghostfix.lua",
	"src/games/aar.lua",
	"src/games/playui.lua",
	"src/games/syle.lua",
	"src/games/aeroports.lua",
	"src/games/projectileleadsync.lua",
	"src/games/voteviewer.lua",
	"src/guis/new.lua",
	"src/init.lua",
	"src/libraries/assistant.lua",
	"src/libraries/cheatengine.lua",
	"src/libraries/communication.lua",
	"src/libraries/drawing.lua",
	"src/libraries/entity.lua",
	"src/libraries/hash.lua",
	"src/libraries/main.lua",
	"src/libraries/navigation.lua",
	"src/libraries/prediction.lua",
	"src/libraries/render.lua",
	"src/libraries/replayvisuals.lua",
	"src/libraries/swordtiming.lua",
	"src/libraries/vm.lua",
	"src/main.lua",
	"src/packages.json",
	"src/profiles/2619619496.gui.txt",
	"src/profiles/9271746647.gui.txt",
	"src/profiles/blatant26872274481.txt",
	"src/profiles/blatant6872274481.txt",
	"src/profiles/closet6872265039.txt",
	"src/profiles/default123974602339071.txt",
	"src/profiles/default6872265039.txt",
	"src/profiles/default6872274481.txt",
	"src/profiles/legit6872265039.txt",
	"src/profiles/legit6872274481.txt",
	"src/profiles/matchdodge.json",
	"src/profiles/matchdodge.txt",
	"src/profiles/regionlock.json",
	"src/profiles/regionlock.txt",
	"src/profiles/silent6872265039.txt",
	"src/profiles/silent6872274481.txt",
}

-- first run: if no catsix exists in the workspace, restore the bundled default config
-- (profiles, gui settings, everything) before filling code files
if not isfolder(Directory .. "/profiles") then
	for _, Folder in {Directory.."/games", Directory.."/profiles", Directory.."/assets", Directory.."/libraries", Directory.."/guis"} do
		if not isfolder(Folder) then
			makefolder(Folder)
		end
	end
	pcall(function()
		local Ok, List = pcall(listfiles, "default-catsix")
		-- workspace copy of the defaults ships alongside the loader (default-catsix folder in executor workspace)
		if Ok then
			local function Walk(List)
				for _, Item in List do
					if isfolder(Item) then
						Walk(listfiles(Item))
					else
						local Rel = Item:gsub("^default%-catsix/", "")
						local Dest = Directory .. "/" .. Rel
						local Parent = Dest:match("^(.+)/[^/]+$")
						if Parent and not isfolder(Parent) then
							makefolder(Parent)
						end
						if not isfile(Dest) then
							pcall(writefile, Dest, readfile(Item))
						end
					end
				end
			end
			Walk(List)
		end
	end)
end

local Priority = {
	"src/guis/new.lua",
	"src/main.lua",
	"src/games/universal.lua",
	"src/games/6872274481.lua",
	"src/games/8560631822.lua",
	"src/libraries/main.lua",
	"src/libraries/entity.lua",
	"src/libraries/hash.lua",
	"src/libraries/prediction.lua",
	"src/libraries/vm.lua",
	"src/features.json",
	"src/libraries/entity.lua",
	"src/libraries/hash.lua",
	"src/libraries/prediction.lua",
	"src/libraries/render.lua",
	"src/libraries/drawing.lua",
	"src/libraries/vm.lua",
	"src/libraries/navigation.lua",
	"src/libraries/cheatengine.lua",
	"src/libraries/replayvisuals.lua",
	"src/libraries/swordtiming.lua",
	"src/libraries/communication.lua",
	"src/libraries/assistant.lua",
	"src/assets/new/proxima.ttf",
	"src/assets/new/proximabd.ttf",
	"src/assets/new/bahnschrift.ttf",
	"src/assets/new/bahnschrift.json",
}
for _, AssetPath in {
	"src/assets/new/add.png",
	"src/assets/new/aim.png",
	"src/assets/new/allowedicon.png",
	"src/assets/new/allowediconmini.png",
	"src/assets/new/arrowmodule.png",
	"src/assets/new/back.png",
	"src/assets/new/backmini.png",
	"src/assets/new/bahnschrift.json",
	"src/assets/new/bahnschrift.ttf",
	"src/assets/new/bind.png",
	"src/assets/new/bindbkg.png",
	"src/assets/new/blatant.png",
	"src/assets/new/blockedicon.png",
	"src/assets/new/blockedtab.png",
	"src/assets/new/blur.png",
	"src/assets/new/blurnoti.png",
	"src/assets/new/cheat_switch.png",
	"src/assets/new/close.png",
	"src/assets/new/closemini.png",
	"src/assets/new/closetiny.png",
	"src/assets/new/colorpreview.png",
	"src/assets/new/combat.png",
	"src/assets/new/combo_display.png",
	"src/assets/new/compassarrow.png",
	"src/assets/new/customtheme.png",
	"src/assets/new/discord.png",
	"src/assets/new/dislike.png",
	"src/assets/new/downexpand.png",
	"src/assets/new/downexpandslider.png",
	"src/assets/new/edit.png",
	"src/assets/new/editlarge.png",
	"src/assets/new/empty.png",
	"src/assets/new/expandarrow.png",
	"src/assets/new/expandright.png",
	"src/assets/new/expandup.png",
	"src/assets/new/favoritesicon.png",
	"src/assets/new/friends.png",
	"src/assets/new/hide.png",
	"src/assets/new/inventory.png",
	"src/assets/new/key_down.png",
	"src/assets/new/key_left.png",
	"src/assets/new/key_lmb.png",
	"src/assets/new/key_mmb.png",
	"src/assets/new/key_right.png",
	"src/assets/new/key_rmb.png",
	"src/assets/new/key_up.png",
	"src/assets/new/legit_atmosphere.png",
	"src/assets/new/legit_bedalarm.png",
	"src/assets/new/legit_bedbreakeffect.png",
	"src/assets/new/legit_breadcrumbs.png",
	"src/assets/new/legit_bullettracers.png",
	"src/assets/new/legit_cape.png",
	"src/assets/new/legit_chinahat.png",
	"src/assets/new/legit_cleankit.png",
	"src/assets/new/legit_clock.png",
	"src/assets/new/legit_compass.png",
	"src/assets/new/legit_coords.png",
	"src/assets/new/legit_crosshair.png",
	"src/assets/new/legit_damageindicator.png",
	"src/assets/new/legit_disguise.png",
	"src/assets/new/legit_fflageditor.png",
	"src/assets/new/legit_fixguis.png",
	"src/assets/new/legit_fov.png",
	"src/assets/new/legit_fps.png",
	"src/assets/new/legit_fpsboost.png",
	"src/assets/new/legit_fpsunlocker.png",
	"src/assets/new/legit_hideshield.png",
	"src/assets/new/legit_hitcolor.png",
	"src/assets/new/legit_hitfix.png",
	"src/assets/new/legit_hitsound.png",
	"src/assets/new/legit_interface.png",
	"src/assets/new/legit_keybinds.png",
	"src/assets/new/legit_keystrokes.png",
	"src/assets/new/legit_killeffect.png",
	"src/assets/new/legit_killsound.png",
	"src/assets/new/legit_memory.png",
	"src/assets/new/legit_mode_icon.png",
	"src/assets/new/legit_ping.png",
	"src/assets/new/legit_potionstatus.png",
	"src/assets/new/legit_reachdisplay.png",
	"src/assets/new/legit_songbeats.png",
	"src/assets/new/legit_soundchanger.png",
	"src/assets/new/legit_speedmeter.png",
	"src/assets/new/legit_switch.png",
	"src/assets/new/legit_timechanger.png",
	"src/assets/new/legit_uicleanup.png",
	"src/assets/new/legit_viewmodel.png",
	"src/assets/new/legit_wineffect.png",
	"src/assets/new/like.png",
	"src/assets/new/min.png",
	"src/assets/new/newhide.png",
	"src/assets/new/noti_alert.png",
	"src/assets/new/noti_info.png",
	"src/assets/new/noti_warning.png",
	"src/assets/new/notification.png",
	"src/assets/new/npcs.png",
	"src/assets/new/overlaydots.png",
	"src/assets/new/overlays.png",
	"src/assets/new/overlayslarge.png",
	"src/assets/new/pin.png",
	"src/assets/new/players.png",
	"src/assets/new/profiles.png",
	"src/assets/new/profilesicon.png",
	"src/assets/new/profileworld.png",
	"src/assets/new/proxima.json",
	"src/assets/new/proxima.ttf",
	"src/assets/new/proximabd.ttf",
	"src/assets/new/radar.png",
	"src/assets/new/radaricon.png",
	"src/assets/new/rainbow_1.png",
	"src/assets/new/rainbow_2.png",
	"src/assets/new/rainbow_3.png",
	"src/assets/new/rainbow_4.png",
	"src/assets/new/range.png",
	"src/assets/new/rangearrow.png",
	"src/assets/new/rangeindicator.png",
	"src/assets/new/render.png",
	"src/assets/new/search.png",
	"src/assets/new/settingdots.png",
	"src/assets/new/settings.png",
	"src/assets/new/settingsmini.png",
	"src/assets/new/show.png",
	"src/assets/new/star.png",
	"src/assets/new/sword_header.png",
	"src/assets/new/targetinfo.png",
	"src/assets/new/targetnpc1.png",
	"src/assets/new/targetplayers1.png",
	"src/assets/new/targetstab.png",
	"src/assets/new/textgui.png",
	"src/assets/new/textguiicon.png",
	"src/assets/new/textguiline.png",
	"src/assets/new/theme.png",
	"src/assets/new/triangle.png",
	"src/assets/new/utility.png",
	"src/assets/new/v4.png",
	"src/assets/new/v4mini.png",
	"src/assets/new/vape.png",
	"src/assets/new/vapelogo.png",
	"src/assets/new/vapelogomini.png",
	"src/assets/new/world.png",
} do
	table.insert(Priority, AssetPath)
end

local function Fetch(Rel, Force)
	-- normalize: self-fix paths arrive without the src/ prefix and would 404
	if Rel:sub(1, 15) ~= "default-catsix/" and Rel:sub(1, 4) ~= "src/" then
		Rel = "src/" .. Rel
	end
	local Dest
	if Rel:sub(1, 15) == "default-catsix/" then
		Dest = Directory .. "/" .. Rel:sub(16)
	else
		Dest = Directory .. "/" .. Rel:gsub("^src/", "")
	end
	local Parent = Dest:match("^(.+)/[^/]+$")
	if Parent and not isfolder(Parent) then
		makefolder(Parent)
	end
	if isfile(Dest) and not Force then
		return true
	end
	local Data
	local ApiRepo = "https://github.com/amack7002-code/CatV6-but-better/raw/main/" .. Rel
	for Attempt = 1, 6 do
		local Url = (Attempt % 2 == 1) and (Repo .. "/" .. Rel) or ApiRepo
		local Success, Result = pcall(function()
			return game:HttpGet(Url, true)
		end)
		-- only reject html error pages (rate limit / not found); file content may legitimately contain "404"
		if Success and type(Result) == "string" and #Result > 0 then
			local Head = Result:sub(1, 200)
			local LooksClean = not Head:find("<!DOCTYPE", 1, true)
				and not Head:find("<html", 1, true)
				and not Head:find("404", 1, true)
			-- .lua files must actually compile: rate-limit pages and error
			-- bodies can never poison the workspace again
			if LooksClean and Rel:sub(-4) == ".lua" then
				LooksClean = loadstring(Result, "validate") ~= nil
			end
			if LooksClean then
				Data = Result
				break
			end
		end
		task.wait(Attempt * 2)
	end
	if Data then
		writefile(Dest, Data)
		return true
	end
	return false
end

-- default config seed files (only used on first run)
for _, Entry in {
	"default-catsix/init.lua",
	"default-catsix/.DS_Store",
	"default-catsix/features.json",
	"default-catsix/main.lua",
	"default-catsix/packages.json",
	"default-catsix/guis/new.lua",
	"default-catsix/libraries/replayvisuals.lua",
	"default-catsix/libraries/hash.lua",
	"default-catsix/libraries/vm.lua",
	"default-catsix/libraries/main.lua",
	"default-catsix/libraries/prediction.lua",
	"default-catsix/libraries/drawing.lua",
	"default-catsix/libraries/assistant.lua",
	"default-catsix/libraries/communication.lua",
	"default-catsix/libraries/cheatengine.lua",
	"default-catsix/libraries/render.lua",
	"default-catsix/libraries/entity.lua",
	"default-catsix/libraries/swordtiming.lua",
	"default-catsix/libraries/navigation.lua",
	"default-catsix/profiles/gui.txt",
	"default-catsix/profiles/rank6872265039.txt",
	"default-catsix/profiles/closet6872265039.txt",
	"default-catsix/profiles/default6872274481.txt",
	"default-catsix/profiles/rank6872274481.txt",
	"default-catsix/profiles/matchdodge.txt",
	"default-catsix/profiles/9271746647.gui.txt",
	"default-catsix/profiles/commit.txt",
	"default-catsix/profiles/assistantwords.txt",
	"default-catsix/profiles/default6872265039.txt",
	"default-catsix/profiles/whitelist.json",
	"default-catsix/profiles/default123974602339071.txt",
	"default-catsix/profiles/matchdodge.json",
	"default-catsix/profiles/blatant26872274481.txt",
	"default-catsix/profiles/blatant6872274481.txt",
	"default-catsix/profiles/silent6872274481.txt",
	"default-catsix/profiles/regionlock.json",
	"default-catsix/profiles/2619619496.gui.txt",
	"default-catsix/profiles/regionlock.txt",
	"default-catsix/profiles/silent6872265039.txt",
	"default-catsix/profiles/assistantchats.json",
	"default-catsix/profiles/legit6872265039.txt",
	"default-catsix/profiles/notifications.txt",
	"default-catsix/profiles/legit6872274481.txt",
	"default-catsix/assets/new/world.png",
	"default-catsix/assets/new/min.png",
	"default-catsix/assets/new/legit_cleankit.png",
	"default-catsix/assets/new/add.png",
	"default-catsix/assets/new/legit_chinahat.png",
	"default-catsix/assets/new/legit_fpsboost.png",
	"default-catsix/assets/new/sword_header.png",
	"default-catsix/assets/new/targetnpc1.png",
	"default-catsix/assets/new/legit_uicleanup.png",
	"default-catsix/assets/new/legit_atmosphere.png",
	"default-catsix/assets/new/legit_viewmodel.png",
	"default-catsix/assets/new/blatant.png",
	"default-catsix/assets/new/targetplayers1.png",
	"default-catsix/assets/new/pin.png",
	"default-catsix/assets/new/rangearrow.png",
	"default-catsix/assets/new/noti_warning.png",
	"default-catsix/assets/new/legit_hitcolor.png",
	"default-catsix/assets/new/overlays.png",
	"default-catsix/assets/new/overlayslarge.png",
	"default-catsix/assets/new/settings.png",
	"default-catsix/assets/new/targetstab.png",
	"default-catsix/assets/new/profilesicon.png",
	"default-catsix/assets/new/legit_memory.png",
	"default-catsix/assets/new/dislike.png",
	"default-catsix/assets/new/inventory.png",
	"default-catsix/assets/new/expandarrow.png",
	"default-catsix/assets/new/proxima.ttf",
	"default-catsix/assets/new/utility.png",
	"default-catsix/assets/new/closetiny.png",
	"default-catsix/assets/new/legit_fpsunlocker.png",
	"default-catsix/assets/new/noti_info.png",
	"default-catsix/assets/new/key_right.png",
	"default-catsix/assets/new/key_lmb.png",
	"default-catsix/assets/new/empty.png",
	"default-catsix/assets/new/textguiicon.png",
	"default-catsix/assets/new/radar.png",
	"default-catsix/assets/new/vapelogomini.png",
	"default-catsix/assets/new/expandup.png",
	"default-catsix/assets/new/colorpreview.png",
	"default-catsix/assets/new/legit_breadcrumbs.png",
	"default-catsix/assets/new/legit_timechanger.png",
	"default-catsix/assets/new/proxima.json",
	"default-catsix/assets/new/show.png",
	"default-catsix/assets/new/combo_display.png",
	"default-catsix/assets/new/players.png",
	"default-catsix/assets/new/legit_switch.png",
	"default-catsix/assets/new/key_rmb.png",
	"default-catsix/assets/new/legit_mode_icon.png",
	"default-catsix/assets/new/favoritesicon.png",
	"default-catsix/assets/new/blurnoti.png",
	"default-catsix/assets/new/backmini.png",
	"default-catsix/assets/new/blur.png",
	"default-catsix/assets/new/vape.png",
	"default-catsix/assets/new/compassarrow.png",
	"default-catsix/assets/new/theme.png",
	"default-catsix/assets/new/profileworld.png",
	"default-catsix/assets/new/combat.png",
	"default-catsix/assets/new/cheat_switch.png",
	"default-catsix/assets/new/bahnschrift.ttf",
	"default-catsix/assets/new/settingsmini.png",
	"default-catsix/assets/new/key_mmb.png",
	"default-catsix/assets/new/key_left.png",
	"default-catsix/assets/new/newhide.png",
	"default-catsix/assets/new/like.png",
	"default-catsix/assets/new/triangle.png",
	"default-catsix/assets/new/search.png",
	"default-catsix/assets/new/key_up.png",
	"default-catsix/assets/new/settingdots.png",
	"default-catsix/assets/new/closemini.png",
	"default-catsix/assets/new/blockedicon.png",
	"default-catsix/assets/new/legit_killeffect.png",
	"default-catsix/assets/new/rangeindicator.png",
	"default-catsix/assets/new/arrowmodule.png",
	"default-catsix/assets/new/friends.png",
	"default-catsix/assets/new/legit_coords.png",
	"default-catsix/assets/new/legit_reachdisplay.png",
	"default-catsix/assets/new/textguiline.png",
	"default-catsix/assets/new/rainbow_1.png",
	"default-catsix/assets/new/downexpandslider.png",
	"default-catsix/assets/new/rainbow_3.png",
	"default-catsix/assets/new/legit_speedmeter.png",
	"default-catsix/assets/new/legit_killsound.png",
	"default-catsix/assets/new/legit_ping.png",
	"default-catsix/assets/new/legit_fps.png",
	"default-catsix/assets/new/legit_fixguis.png",
	"default-catsix/assets/new/rainbow_2.png",
	"default-catsix/assets/new/expandright.png",
	"default-catsix/assets/new/legit_potionstatus.png",
	"default-catsix/assets/new/discord.png",
	"default-catsix/assets/new/legit_hideshield.png",
	"default-catsix/assets/new/proximabd.ttf",
	"default-catsix/assets/new/key_down.png",
	"default-catsix/assets/new/bahnschrift.json",
	"default-catsix/assets/new/textgui.png",
	"default-catsix/assets/new/v4mini.png",
	"default-catsix/assets/new/legit_keystrokes.png",
	"default-catsix/assets/new/legit_fflageditor.png",
	"default-catsix/assets/new/legit_wineffect.png",
	"default-catsix/assets/new/rainbow_4.png",
	"default-catsix/assets/new/downexpand.png",
	"default-catsix/assets/new/legit_bedbreakeffect.png",
	"default-catsix/assets/new/bindbkg.png",
	"default-catsix/assets/new/allowedicon.png",
	"default-catsix/assets/new/noti_alert.png",
	"default-catsix/assets/new/legit_bedalarm.png",
	"default-catsix/assets/new/legit_interface.png",
	"default-catsix/assets/new/legit_soundchanger.png",
	"default-catsix/assets/new/range.png",
	"default-catsix/assets/new/edit.png",
	"default-catsix/assets/new/radaricon.png",
	"default-catsix/assets/new/targetinfo.png",
	"default-catsix/assets/new/star.png",
	"default-catsix/assets/new/npcs.png",
	"default-catsix/assets/new/render.png",
	"default-catsix/assets/new/legit_hitfix.png",
	"default-catsix/assets/new/legit_disguise.png",
	"default-catsix/assets/new/vapelogo.png",
	"default-catsix/assets/new/blockedtab.png",
	"default-catsix/assets/new/profiles.png",
	"default-catsix/assets/new/legit_compass.png",
	"default-catsix/assets/new/legit_keybinds.png",
	"default-catsix/assets/new/notification.png",
	"default-catsix/assets/new/legit_clock.png",
	"default-catsix/assets/new/bind.png",
	"default-catsix/assets/new/legit_fov.png",
	"default-catsix/assets/new/legit_crosshair.png",
	"default-catsix/assets/new/legit_bullettracers.png",
	"default-catsix/assets/new/legit_songbeats.png",
	"default-catsix/assets/new/aim.png",
	"default-catsix/assets/new/back.png",
	"default-catsix/assets/new/overlaydots.png",
	"default-catsix/assets/new/editlarge.png",
	"default-catsix/assets/new/hide.png",
	"default-catsix/assets/new/legit_damageindicator.png",
	"default-catsix/assets/new/legit_hitsound.png",
	"default-catsix/assets/new/legit_cape.png",
	"default-catsix/assets/new/customtheme.png",
	"default-catsix/assets/new/close.png",
	"default-catsix/assets/new/allowediconmini.png",
	"default-catsix/assets/new/v4.png",
	"default-catsix/games/8560631822.lua",
	"default-catsix/games/139566161526375.lua",
	"default-catsix/games/8444591321.lua",
	"default-catsix/games/6872274481.lua",
	"default-catsix/games/staffdetector.lua",
	"default-catsix/games/universal.lua",
	"default-catsix/games/6872265039.lua",
	"default-catsix/games/extras.lua",
	"default-catsix/games/spectatordetector.lua",
	"default-catsix/games/cheatwatcher.lua",
} do
	table.insert(Files, Entry)
end

-- update check: repo publishes a version file; a changed version means code
-- files in the workspace are stale and get refreshed (profiles/configs untouched)
local RepoVersion = "unknown"
do
	local Ok, Data = pcall(function()
		return game:HttpGet(Repo .. "/src/version.txt", true)
	end)
	if Ok and type(Data) == "string" and #Data > 0 and #Data < 100 and Data:find("^build %d") then
		RepoVersion = Data:gsub("%s+", "")
	end
end

local ForceAll = false
do
	local Marker = Directory .. "/.loaderversion"
	local LocalVersion = isfile(Marker) and readfile(Marker) or nil
	if LocalVersion ~= RepoVersion then
		ForceAll = true
		pcall(function()
			writefile(Marker, RepoVersion)
		end)
		print("[slop] update detected - refreshing code files to " .. RepoVersion)
	end
end

local function NeedsFetch(Rel): boolean
	if Rel:sub(1, 15) == "default-catsix/" then
		return not isfile(Directory .. "/" .. Rel:sub(16))
	end
	local Dest = Directory .. "/" .. Rel:gsub("^src/", "")
	-- profiles and configs belong to the user, never auto-overwritten
	if Dest:find("/profiles/") or Dest:find("/cloudconfigs/") then
		return not isfile(Dest)
	end
	return ForceAll or not isfile(Dest)
end

local Queue = {}
for _, Rel in Files do
	if NeedsFetch(Rel) then
		table.insert(Queue, Rel)
	end
end

local Done = {}
-- batches of 12 concurrent HttpGets, don't hammer the thread
local function Drain(Active)
	local Running = 0
	local Cursor = 1
	while Cursor <= #Queue do
		while Running < Active and Cursor <= #Queue do
			local Rel = Queue[Cursor]
			Cursor = Cursor + 1
			if not Done[Rel] then
				Done[Rel] = true
				Running = Running + 1
				task.spawn(function()
					Fetch(Rel, ForceAll)
					Running = Running - 1
				end)
			end
		end
		task.wait(0.1)
	end
end

local function Install()
	-- critical files first, blocking, must not fail
	for _, Rel in Priority do
		if not isfile(Directory .. "/" .. Rel:gsub("^src/", "")) then
			while not Fetch(Rel) do
				warn("[slop] fetching " .. Rel)
				task.wait(3)
			end
		end
	end
	-- everything else in parallel batches (extras, detectors, assets)
	task.spawn(Drain, 4)
end

Install()

getgenv().catuser = "Slop"
getgenv().catrole = "premium"

local queue_on_teleport = queue_on_teleport or function() end
local isfile = isfile or function(FilePath)
	local Success, Contents = pcall(function()
		return readfile(FilePath)
	end)
	return Success and Contents ~= nil and Contents ~= ""
end
local cloneref = cloneref or function(Reference) return Reference end
local Players = cloneref(game:GetService("Players"))
local HttpService = cloneref(game:GetService("HttpService"))

local License = {
	Key = "slop",
	Callback = function() end
}

-- self-checking + self-fixing runtime:
-- every component load is wrapped; if it fails, the file is force-refetched
-- (assuming local corruption or a stale cached copy) and retried once.
-- if it still fails, the component is skipped with a notification instead of
-- breaking the whole boot - the build keeps working with the rest intact.
getgenv().__sloperrors = getgenv().__sloperrors or {}
local function Capture(Chunk, Name, Rel)
	local Ok, Err = xpcall(Chunk, function(E)
		return debug and debug.traceback and debug.traceback(tostring(E), 2) or tostring(E)
	end)
	if Ok then
		return true
	end

	local Line = tostring(Name) .. ": " .. tostring(Err)
	table.insert(getgenv().__sloperrors, Line)
	warn("[slop] " .. Name .. " failed (" .. tostring(Err) .. ") - refetching and retrying")

	-- self-fix: refetch the file in case the local copy is corrupt/stale
	if Rel then
		pcall(function()
			if isfile(Directory .. "/" .. Rel) and delfile then
				delfile(Directory .. "/" .. Rel)
			end
			Fetch(Rel, true)
		end)
	end

	local Ok2 = xpcall(Chunk, function(E)
		return tostring(E)
	end)
	if Ok2 then
		print("[slop] " .. Name .. " recovered after refetch")
		return true
	end

	-- self-disable: never leave the user sitting on a broken boot
	table.insert(getgenv().__sloperrors, Name .. ": failed after retry - skipped")
	warn("[slop] " .. Name .. " disabled itself (failed after retry)")
	return false
end

-- capability self-check: probe what this executor can actually do, once
shared.SlopCaps = {
	writefile = type(writefile) == "function",
	readfile = type(readfile) == "function",
	getcustomasset = type(getcustomasset) == "function",
	hookmetamethod = type(hookmetamethod) == "function",
	getconnections = type(getconnections) == "function",
	request = type(request) == "function",
}

local vape, RunPremium
local ls = function(...)
	local Chunk, Error = loadstring(...)
	if Error then
		warn("[slop] compile error: " .. tostring(Error))
	end
	if Error and vape then
		vape:CreateNotification("Vape", "Failed to load : " .. tostring(Error), 30, "alert")
	end
	return Chunk
end

if not isfile(Directory .. "/profiles/gui.txt") then
	writefile(Directory .. "/profiles/gui.txt", "new")
end
if not isfolder(Directory .. "/assets/new") then
	makefolder(Directory .. "/assets/new")
end
local GuiChunk = ls(readfile(Directory .. "/guis/new.lua"), "gui")
if not GuiChunk then
	error("[slop] gui failed to compile - run the loader again to refetch it")
end
vape, RunPremium = GuiChunk(License)
shared.vape = vape
_G.vape = vape
getgenv().used_init = true

local function FinishLoading()
	vape.Init = nil
	vape:Load()
	shared.vapeloading = nil

	local TeleportedServers
	vape:Clean(Players.LocalPlayer.OnTeleport:Connect(function()
		if not TeleportedServers then
			TeleportedServers = true
			local TeleportScript = [[
				shared.vapereload = true
				loadstring(game:HttpGet('__REPO__/catvape-cracked-loader.lua', true), 'slop')()
			]]
			TeleportScript = TeleportScript:gsub("__REPO__", Repo)
			vape:Save()
			queue_on_teleport(TeleportScript)
		end
	end))

	vape:CreateNotification("Finished Loading", "Authenticated as Slop with premium", 5)
end

ls(readfile(Directory .. "/games/universal.lua"), "universal")(License)
if isfile(Directory .. "/games/" .. game.PlaceId .. ".lua") then
	ls(readfile(Directory .. "/games/" .. game.PlaceId .. ".lua"), tostring(game.PlaceId))(License)
end
ls(readfile(Directory .. "/libraries/main.lua"), "main")(License)
-- extras/detectors: deferred until after the GUI is up so boot is instant
task.spawn(function()
	for _, Name in {"games/extras.lua", "games/staffdetector.lua", "games/spectatordetector.lua", "games/cheatwatcher.lua", "games/ghostfix.lua", "games/aar.lua", "games/playui.lua"} do
		local Dest = Directory .. "/" .. Name
		local Waited = 0
		while not isfile(Dest) and Waited < 25 do
			task.wait(0.5)
			Waited = Waited + 0.5
		end
	end
	task.wait(1)
	local function LoadDeferred(Name, Rel, ChunkName)
		if isfile(Directory .. "/" .. Rel) then
			Capture(function()
				local Chunk = ls(readfile(Directory .. "/" .. Rel), ChunkName)
				if Chunk then
					Chunk()
				else
					error(ChunkName .. " failed to compile")
				end
			end, ChunkName, Rel)
			task.wait(0.35) -- one heavy chunk per beat: no frame pile-up
		end
	end
	LoadDeferred("extras", "games/extras.lua", "extras")
	LoadDeferred("staff", "games/staffdetector.lua", "staffdetector")
	LoadDeferred("spectator", "games/spectatordetector.lua", "spectator")
	LoadDeferred("cheatwatcher", "games/cheatwatcher.lua", "cheatwatcher")
	if Supported then
		LoadDeferred("ghostfix", "games/ghostfix.lua", "ghostfix")
	end
	LoadDeferred("aar", "games/aar.lua", "aar")
	LoadDeferred("voidprediction", "games/voidprediction.lua", "voidprediction")
	LoadDeferred("ghostpeak", "games/ghostpeak.lua", "ghostpeak")
	LoadDeferred("playui", "games/playui.lua", "playui")
	LoadDeferred("syle", "games/syle.lua", "syle")
	if Supported then
		LoadDeferred("aeroports", "games/aeroports.lua", "aeroports")
		LoadDeferred("leadsync", "games/projectileleadsync.lua", "leadsync")
	end
	--[[

	if isfile(Directory .. "/games/extras.lua") then
		Capture(function() local Chunk = ls(readfile(Directory .. "/games/extras.lua"), "extras") if Chunk then Chunk() else error("extras failed to compile in this executor") end end, "extras", "games/extras.lua")
	end
	if isfile(Directory .. "/games/staffdetector.lua") then
		Capture(function() local Chunk = ls(readfile(Directory .. "/games/staffdetector.lua"), "staffdetector") if Chunk then Chunk() else error("staffdetector failed to compile") end end, "staff", "games/staffdetector.lua")
	end
	if isfile(Directory .. "/games/spectatordetector.lua") then
		Capture(function() local Chunk = ls(readfile(Directory .. "/games/spectatordetector.lua"), "spectator") if Chunk then Chunk() else error("spectator failed to compile") end end, "spectator", "games/spectatordetector.lua")
	end
	if isfile(Directory .. "/games/cheatwatcher.lua") then
		Capture(function() local Chunk = ls(readfile(Directory .. "/games/cheatwatcher.lua"), "cheatwatcher") if Chunk then Chunk() else error("cheatwatcher failed to compile") end end, "cheatwatcher", "games/cheatwatcher.lua")
	end
	if isfile(Directory .. "/games/ghostfix.lua") then
		Capture(function() local Chunk = ls(readfile(Directory .. "/games/ghostfix.lua"), "ghostfix") if Chunk then Chunk() else error("ghostfix failed to compile") end end, "ghostfix", "games/ghostfix.lua")
	end
	if isfile(Directory .. "/games/aar.lua") then
		Capture(function() local Chunk = ls(readfile(Directory .. "/games/aar.lua"), "aar") if Chunk then Chunk() else error("aar failed to compile") end end, "aar", "games/aar.lua")
	end
	if isfile(Directory .. "/games/playui.lua") then
		Capture(function() local Chunk = ls(readfile(Directory .. "/games/playui.lua"), "playui") if Chunk then Chunk() else error("playui failed to compile") end end, "playui", "games/playui.lua")
	end
	if isfile(Directory .. "/games/syle.lua") then
		Capture(function() local Chunk = ls(readfile(Directory .. "/games/syle.lua"), "syle") if Chunk then Chunk() else error("syle failed to compile") end end, "syle", "games/syle.lua")
	end
	if isfile(Directory .. "/games/aeroports.lua") then
		Capture(function() local Chunk = ls(readfile(Directory .. "/games/aeroports.lua"), "aeroports") if Chunk then Chunk() else error("aeroports failed to compile") end end, "aeroports", "games/aeroports.lua")
	end
	if isfile(Directory .. "/games/projectileleadsync.lua") then
		Capture(function() local Chunk = ls(readfile(Directory .. "/games/projectileleadsync.lua"), "leadsync") if Chunk then Chunk() else error("leadsync failed to compile") end end, "leadsync", "games/projectileleadsync.lua")
	end
	if isfile(Directory .. "/games/voteviewer.lua") then
		Capture(function() local Chunk = ls(readfile(Directory .. "/games/voteviewer.lua"), "voteviewer") if Chunk then Chunk() else error("voteviewer failed to compile") end end, "voteviewer", "games/voteviewer.lua")
	end

	--]]

	-- config restore: modules registered after vape:Load never had their saved
	-- state applied - reapply it now so toggles survive rejoins
	task.delay(2, function()
		pcall(function()
			if not vape or not vape.Loaded then return end
			local ProfilePath = Directory .. "/profiles/" .. tostring(vape.Profile or "default") .. tostring(vape.Place or "") .. ".txt"
			if not isfile(ProfilePath) then return end
			local Data = HttpService:JSONDecode(readfile(ProfilePath))
			if type(Data) ~= "table" or type(Data.Modules) ~= "table" then return end
			local Applied = 0
			local Batch = {}
			for _, Module in vape.Modules do
				local Saved = Data.Modules[Module.Name]
				if type(Saved) == "table" and type(Module.Load) == "function" then
					table.insert(Batch, {Module = Module, Saved = Saved})
				end
			end
			-- batches of 8 per frame: mass-toggling 200+ modules in one frame
			-- is what was crashing the boot
			for i, Entry in Batch do
				pcall(function() Entry.Module:Load(Entry.Saved) end)
				Applied = Applied + 1
				if i % 8 == 0 then
					task.wait()
				end
			end
			print("[slop] restored saved state for " .. Applied .. " deferred modules")
		end)
	end)
end)

FinishLoading()
