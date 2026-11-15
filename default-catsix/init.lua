-- SLOP: init.lua is now a local reloader, update logic removed
local License = ...
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

local cloneref = cloneref or function(Reference) return Reference end
local Directory = "catsix"
for _, Folder: string in {Directory, `{Directory}/games`, `{Directory}/profiles`, `{Directory}/assets`, `{Directory}/libraries`, `{Directory}/guis`} do
	if not isfolder(Folder) then
		makefolder(Folder)
	end
end

getgenv().catuser = "Slop"
getgenv().catrole = "premium"

local loadstring = loadstring
local queue_on_teleport = queue_on_teleport or function() end
local isfile = isfile or function(FilePath)
	local Success, Contents = pcall(function()
		return readfile(FilePath)
	end)
	return Success and Contents ~= nil and Contents ~= ""
end
local Players = cloneref(game:GetService("Players"))
local HttpService = cloneref(game:GetService("HttpService"))

local vape, RunPremium
local ls = function(...)
	local Chunk, Error = loadstring(...)
	if Error and vape then
		vape:CreateNotification("Vape", `Failed to load : {Error}`, 30, "alert")
	end
	return Chunk
end

if not isfile(`{Directory}/profiles/gui.txt`) then
	writefile(`{Directory}/profiles/gui.txt`, "new")
end
vape, RunPremium = ls(readfile(`{Directory}/guis/new.lua`), "gui")(License)
shared.vape = vape
_G.vape = vape
getgenv().used_init = true

local function FinishLoading()
	vape.Init = nil
	vape:Load()
	shared.vapeloading = nil
	vape:CreateNotification("Finished Loading", "Authenticated as Slop with premium", 5)
end

ls(readfile(`{Directory}/games/universal.lua`), "universal")(License)
if isfile(`{Directory}/games/{game.PlaceId}.lua`) then
	ls(readfile(`{Directory}/games/{game.PlaceId}.lua`), tostring(game.PlaceId))(License)
end
ls(readfile(`{Directory}/libraries/main.lua`), "main")(License)
FinishLoading()
