--!nocheck
--[[
	AAR - Advanced Auto Repair (v2)
	Self-healing module loader and supervisor.

	BENCH NOTES
	===========
	Boot order:
	  1. feature-detect executor APIs (fs, loadstring, hooks)
	  2. load persisted state (rotated JSON, size-capped)
	  3. boot self-test: compile every .lua under games/, guis/, libraries/
	  4. self-test failures -> vault restore -> re-verify -> refetch fallback
	  5. vault every passing file (hash-gated writes, N-version retention)
	  6. start watchdog + perf monitor + memory guard + health checks
	  7. expose shared.AAR (safeLoad, Diagnose, Report, shutdown)

	Config: everything tunable lives in CONFIG below.
	FILL: CONFIG.Source.BaseUrl - raw file base URL of the repo that serves
	      games/guis/libraries (default points at the CatV6-but-better GitHub
	      raw; change if you mirror elsewhere).

	FAILURE-MODE TABLE
	| symptom                        | cause                       | AAR action                                  |
	|--------------------------------|-----------------------------|---------------------------------------------|
	| attempt to call a nil (load)   | compile failure             | safeLoad Result, never nil-calls            |
	| file corrupted/edited          | bad write or manual edit    | vault restore, re-verify, then refetch      |
	| same error x5 in window        | module error loop           | disable module, silence, backoff re-enable  |
	| frame stalls (3 windows)       | something eating the thread | persist perf-stall + build tag              |
	| instance count runaway         | UI rebuild per frame        | throttle module, purge its instances        |
	| missing file at load           | never installed / evicted   | refetch playbook, compile-check then write  |
]]

-- ========== CONFIG ==========
local CONFIG = {
	Debug = false,                       -- verbose logging when true
	Source = {
		BaseUrl = "https://raw.githubusercontent.com/amack7002-code/CatV6-but-better/main/src", -- FILL: change if mirrored
		MaxDownloadBytes = 4 * 1024 * 1024,  -- 4MB size gate
		MaxRetries = 4,
		RetryBaseWait = 1.5,                 -- seconds, exponential backoff
	},
	Paths = {
		Root = "catsix",
		Vault = "catsix/.aarvault",
		State = "catsix/profiles/aar-state.json",
	},
	SelfTest = {
		Folders = {"games", "guis", "libraries"},
		MaxFileBytes = 4 * 1024 * 1024,
		VaultVersions = 3,               -- keep last N good versions
	},
	Watchdog = {
		Window = 10,                     -- seconds, sliding error window
		Threshold = 5,                   -- signatures within window = loop
		ReenableBase = 30,               -- seconds, exponential backoff base
		ReenableMax = 8 * 60,            -- backoff ceiling
	},
	Perf = {
		Interval = 5,                    -- sample period (s)
		StallThreshold = 0.4,            -- seconds of drift per window
		SustainedWindows = 3,            -- consecutive windows before alarm
		SampleCount = 12,                -- rolling sample pool
	},
	Memory = {
		Interval = 30,                   -- snapshot period (s)
		GrowthFactor = 1.5,              -- flagged if count exceeds baseline * factor
		ModuleTag = "SlopOwner_",
	},
	State = {
		MaxBytes = 64 * 1024,            -- rotation cap
		KeepRotations = 2,
	},
}
-- ============================

local Fs = {}
do
	local function Detect(name)
		local Ok, Fn = pcall(function()
			return _G[name]
		end)
		-- executors inject these as globals; _G lookup misses some, probe directly
		local Direct = rawget(getfenv and getfenv() or {}, name)
		return type(Direct) == "function" and Direct or (type(Fn) == "function" and Fn or nil)
	end
	Fs.readfile = Detect("readfile")
	Fs.writefile = Detect("writefile")
	Fs.isfile = Detect("isfile")
	Fs.isfolder = Detect("isfolder")
	Fs.listfiles = Detect("listfiles")
	Fs.makefolder = Detect("makefolder")
	Fs.delfile = Detect("delfile")
	Fs.HasFs = Fs.readfile ~= nil and Fs.writefile ~= nil and Fs.isfile ~= nil
end

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- ========== RESULT helpers ==========
local function Ok(Value)
	return {ok = true, value = Value}
end

local function Fail(Stage, Err)
	return {ok = false, stage = Stage, err = tostring(Err)}
end

-- the bug this file exists to fix: loadstring returns nil, err on compile
-- failure. Never call its result unchecked again.
local function safeLoad(Source: string, ChunkName: string)
	if type(Source) ~= "string" or #Source == 0 then
		return Fail("compile", "empty source")
	end
	local OkChunk, Err = loadstring(Source, ChunkName)
	if type(OkChunk) ~= "function" then
		return Fail("compile", Err)
	end
	return Ok({fn = OkChunk})
end

local function safeRun(Fn, ChunkName, ...)
	if type(Fn) ~= "function" then
		return Fail("runtime", "not a function")
	end
	local Args = {...}
	local Results = table.pack(xpcall(Fn, function(E)
		return debug and debug.traceback and debug.traceback(tostring(E), 2) or tostring(E)
	end, unpack(Args)))
	if not Results[1] then
		return Fail("runtime", Results[2])
	end
	return Ok(table.unpack(Results, 2, Results.n))
end

-- ========== state persistence ==========
local State = {
	version = 2,
	perfStalls = {},   -- {buildTag, at}
	errorLoops = {},   -- {signature, module, at}
	repairs = {},      -- {what, at, count}
	startedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
}
local StateDirty = false

local function LoadState()
	if not Fs.HasFs then return Fail("io", "no filesystem") end
	local OkRead, Raw = pcall(Fs.readfile, CONFIG.Paths.State)
	if not OkRead or type(Raw) ~= "string" then
		return Fail("io", "no state yet")
	end
	local OkDecode, Decoded = pcall(HttpService.JSONDecode, HttpService, Raw)
	if not OkDecode or type(Decoded) ~= "table" then
		return Fail("state", "corrupt state file")
	end
	return Ok(Decoded)
end

local function SaveState()
	if not Fs.HasFs or not StateDirty then return Ok(true) end
	local OkEncode, Body = pcall(HttpService.JSONEncode, HttpService, State)
	if not OkEncode or type(Body) ~= "string" then
		return Fail("encode", "state json failed")
	end
	if #Body > CONFIG.State.MaxBytes then
		-- rotate: drop the oldest arrays wholesale instead of failing
		State.perfStalls = {}
		State.errorLoops = {}
		OkEncode, Body = pcall(HttpService.JSONEncode, HttpService, State)
		if not OkEncode then return Fail("encode", "state json failed after trim") end
	end
	pcall(Fs.writefile, CONFIG.Paths.State, Body)
	StateDirty = false
	return Ok(true)
end

-- ========== logging ==========
local function Note(Message: string)
	if CONFIG.Debug then
		print("[AAR] " .. Message)
	end
end

local function Loud(Message: string)
	print("[AAR] " .. Message)
end

-- ========== hashing (FNV-1a 32bit, enough to detect content change) ==========
local function Hash(Content: string): string
	-- arithmetic FNV-style: no bitwise ops, safe on pre-2022 executor Luau
	local HashValue = 5381
	for i = 1, #Content do
		HashValue = (HashValue * 33 + string.byte(Content, i)) % 2147483647
	end
	return string.format("%08x", HashValue)
end

local function Signature(Message: string, Module: string): string
	-- normalize line numbers and addresses so the same error at different
	-- lines/at different tables collapses into one signature
	local Normalized = tostring(Message)
	Normalized = Normalized:gsub(":%d+", ":N")
	Normalized = Normalized:gsub("0x%x+", "0xADDR")
	Normalized = Normalized:gsub("%s+", " ")
	return Hash(Module .. "|" .. Normalized)
end

-- ========== vault ==========
local Vault = {initialized = false}

local function VaultInit()
	if Vault.initialized or not Fs.HasFs then return end
	if Fs.isfolder and not Fs.isfolder(CONFIG.Paths.Vault) and Fs.makefolder then
		pcall(Fs.makefolder, CONFIG.Paths.Vault)
	end
	Vault.initialized = true
end

local function VaultPath(Name: string, Index: number): string
	return CONFIG.Paths.Vault .. "/" .. Name:gsub("[/\\]", "_") .. "." .. Index .. ".bak"
end

-- store a good copy; only writes when the newest version's hash differs
local function VaultStore(RelPath: string, Content: string)
	VaultInit()
	if not Fs.writefile then return Fail("io", "no writefile") end
	local NewHash = Hash(Content)
	for Index = 1, CONFIG.SelfTest.VaultVersions do
		local Path = VaultPath(RelPath, Index)
		if Fs.isfile(Path) then
			local OkRead, Existing = pcall(Fs.readfile, Path)
			if OkRead and Existing and Hash(Existing) == NewHash then
				return Ok(true) -- unchanged, nothing to store
			end
		end
	end
	-- shift versions: newest at 1
	for Index = CONFIG.SelfTest.VaultVersions, 2, -1 do
		local From = VaultPath(RelPath, Index - 1)
		local To = VaultPath(RelPath, Index)
		if Fs.isfile(From) then
			pcall(function()
				Fs.writefile(To, Fs.readfile(From))
			end)
		end
	end
	local OkWrite = pcall(Fs.writefile, VaultPath(RelPath, 1), Content)
	if OkWrite then
		Note("vaulted " .. RelPath)
		return Ok(true)
	end
	return Fail("io", "vault write failed for " .. RelPath)
end

local function VaultLatest(RelPath: string)
	for Index = 1, CONFIG.SelfTest.VaultVersions do
		local Path = VaultPath(RelPath, Index)
		if Fs.isfile and Fs.isfile(Path) then
			local OkRead, Content = pcall(Fs.readfile, Path)
			if OkRead and type(Content) == "string" and #Content > 0 then
				return Ok(Content)
			end
		end
	end
	return Fail("vault", "no copy for " .. RelPath)
end

-- ========== refetch playbook ==========
local function Refetch(RelPath: string)
	if not Fs.writefile then return Fail("io", "no writefile") end
	local Url = CONFIG.Source.BaseUrl .. "/" .. RelPath
	for Attempt = 1, CONFIG.Source.MaxRetries do
		local OkGet, Body = pcall(function()
			return game:HttpGet(Url, true)
		end)
		local Valid = OkGet and type(Body) == "string" and #Body > 0
			and #Body <= CONFIG.Source.MaxDownloadBytes
			and not Body:sub(1, 200):find("<", 1, true)
		if Valid then
			-- compile-check BEFORE clobbering the file on disk
			local Result = safeLoad(Body, "refetch:" .. RelPath)
			if Result.ok then
				local Dest = CONFIG.Paths.Root .. "/" .. RelPath
				local Parent = Dest:match("^(.+)/[^/]+$")
				if Parent and Fs.makefolder and Fs.isfolder and not Fs.isfolder(Parent) then
					pcall(Fs.makefolder, Parent)
				end
				pcall(Fs.writefile, Dest, Body)
				VaultStore(RelPath, Body)
				StateDirty = true
				table.insert(State.repairs, {what = "refetch:" .. RelPath, at = os.time()})
				return Ok(true)
			else
				Note("refetch compile-check failed for " .. RelPath .. ": " .. tostring(Result.err))
				return Fail("compile", Result.err)
			end
		end
		task.wait(CONFIG.Source.RetryBaseWait * (2 ^ (Attempt - 1)))
	end
	return Fail("network", "refetch exhausted retries for " .. RelPath)
end

-- ========== boot self-test ==========
local SelfTestReport = {passed = {}, failed = {}, skipped = {}}

local function IterateFolder(Folder): {string}
	local Out = {}
	if Fs.listfiles and Fs.isfolder and Fs.isfolder(Folder) then
		local OkList, Items = pcall(Fs.listfiles, Folder)
		if OkList and type(Items) == "table" then
			for _, Item in Items do
				if Fs.isfolder(Item) then
					for _, Nested in IterateFolder(Item) do
						table.insert(Out, Nested)
					end
				else
					table.insert(Out, Item)
				end
			end
		end
	end
	return Out
end

local function SelfTest()
	local Files = {}
	for _, Folder in CONFIG.SelfTest.Folders do
		for _, Path in IterateFolder(CONFIG.Paths.Root .. "/" .. Folder) do
			if Path:sub(-4) == ".lua" then
				table.insert(Files, Path)
			end
		end
	end

	for _, Path in Files do
		local Rel = Path:sub(#CONFIG.Paths.Root + 2)
		local OkRead, Content = pcall(Fs.readfile, Path)
		if not OkRead or type(Content) ~= "string" then
			table.insert(SelfTestReport.skipped, Rel)
			continue
		end
		if #Content > CONFIG.SelfTest.MaxFileBytes then
			table.insert(SelfTestReport.skipped, Rel)
			continue
		end
		local Result = safeLoad(Content, "selftest:" .. Rel)
		if Result.ok then
			table.insert(SelfTestReport.passed, Rel)
			VaultStore(Rel, Content)
		else
			table.insert(SelfTestReport.failed, {path = Rel, err = Result.err})
		end
	end

	-- repair pass: failed files
	for _, Failure in SelfTestReport.failed do
		local Restored = false
		local VaultResult = VaultLatest(Failure.path)
		if VaultResult.ok then
			local Verify = safeLoad(VaultResult.value, "vaultverify:" .. Failure.path)
			if Verify.ok then
				pcall(Fs.writefile, CONFIG.Paths.Root .. "/" .. Failure.path, VaultResult.value)
				Restored = true
				StateDirty = true
				table.insert(State.repairs, {what = "vault-restore:" .. Failure.path, at = os.time()})
				Loud("restored " .. Failure.path .. " from vault")
			end
		end
		if not Restored then
			local Refetched = Refetch(Failure.path)
			if Refetched.ok then
				Restored = true
				Loud("refetched " .. Failure.path)
			else
				Loud("UNREPAIRABLE: " .. Failure.path .. " (" .. Failure.err .. ")")
			end
		end
	end

	return Ok(SelfTestReport)
end

-- ========== watchdog ==========
local Watchdog = {
	Signatures = {},  -- [sig] = {times = {t1..}, module = name, silenced = false, disabled = false, attempts = 0}
	Hooks = {},
}

local function NormalizeModule(Source: string?): string
	if type(Source) ~= "string" then return "unknown" end
	return Source:match("[%w_]+%.lua") or Source:match("^[%w_]+") or Source
end

-- silence a module's console output by filtering warn/error payloads that
-- carry its chunk name
local function SilenceModule(Module: string)
	if Watchdog.Hooks[Module] then return end
	Watchdog.Hooks[Module] = true
	local OldWarn = warn
	local function NewWarn(...)
		local Parts = {}
		for Index = 1, select("#", ...) do
			Parts[Index] = tostring(select(Index, ...))
		end
		local Message = table.concat(Parts, " ")
		if Message:find(Module, 1, true) then
			return -- silenced
		end
		return OldWarn(...)
	end
	if not CONFIG.Debug then
		warn = NewWarn
	end
end

local function DisableModule(Module: string, SignatureKey: string)
	local Entry = Watchdog.Signatures[SignatureKey]
	Entry.disabled = true
	Entry.attempts = Entry.attempts + 1
	Entry.disabledAt = os.clock()
	SilenceModule(Module)
	StateDirty = true
	table.insert(State.errorLoops, {signature = SignatureKey, module = Module, at = os.time()})
	Loud("watchdog: " .. Module .. " disabled (error loop), re-enable in "
		.. tostring(math.floor(CONFIG.Watchdog.ReenableBase * (2 ^ (Entry.attempts - 1)))) .. "s")
end

local function WatchdogReport(Message: string, Source: string?)
	local Module = NormalizeModule(Source or Message)
	local Key = Signature(Message, Module)
	local Entry = Watchdog.Signatures[Key]
	if not Entry then
		Entry = {times = {}, module = Module, silenced = false, disabled = false, attempts = 0}
		Watchdog.Signatures[Key] = Entry
	end
	local Now = os.clock()
	table.insert(Entry.times, Now)
	-- sliding window trim
	while #Entry.times > 0 and Now - Entry.times[1] > CONFIG.Watchdog.Window do
		table.remove(Entry.times, 1)
	end
	if #Entry.times >= CONFIG.Watchdog.Threshold and not Entry.disabled then
		DisableModule(Module, Key)
	end
end

-- timed re-enable with exponential backoff
task.spawn(function()
	while true do
		task.wait(5)
		local Now = os.clock()
		for _, Entry in Watchdog.Signatures do
			if Entry.disabled then
				local Backoff = math.min(CONFIG.Watchdog.ReenableBase * (2 ^ (Entry.attempts - 1)), CONFIG.Watchdog.ReenableMax)
				if Now - (Entry.disabledAt or 0) >= Backoff then
					Entry.disabled = false
					Entry.times = {}
					Note("watchdog: re-enabled " .. Entry.module .. " after backoff")
				end
			end
		end
	end
end)

-- ========== perf drift monitor ==========
local Perf = {samples = {}, stalls = 0, running = false}

local function Percentile(Sorted, P): number
	local Index = math.clamp(math.floor(#Sorted * P), 1, #Sorted)
	return Sorted[Index]
end

task.spawn(function()
	if Perf.running then return end -- idempotent
	Perf.running = true
	while true do
		local Start = os.clock()
		task.wait(CONFIG.Perf.Interval)
		local Drift = (os.clock() - Start) - CONFIG.Perf.Interval
		table.insert(Perf.samples, math.max(Drift, 0))
		while #Perf.samples > CONFIG.Perf.SampleCount do
			table.remove(Perf.samples, 1)
		end
		local Sorted = {}
		for _, Value in Perf.samples do table.insert(Sorted, Value) end
		table.sort(Sorted)
		local Median = Percentile(Sorted, 0.5)
		local P95 = Percentile(Sorted, 0.95)
		if P95 > CONFIG.Perf.StallThreshold then
			Perf.stalls = Perf.stalls + 1
		else
			Perf.stalls = 0
		end
		if Perf.stalls >= CONFIG.Perf.SustainedWindows then
			Perf.stalls = 0
			local Tag = "unknown"
			pcall(function()
				Tag = isfile(CONFIG.Paths.Root .. "/.loaderversion") and Fs.readfile(CONFIG.Paths.Root .. "/.loaderversion") or "unknown"
			end)
			table.insert(State.perfStalls, {build = Tag, median = string.format("%.3f", Median), p95 = string.format("%.3f", P95), at = os.time()})
			StateDirty = true
			Loud("perf: sustained frame stall (median " .. string.format("%.3f", Median) .. "s, p95 " .. string.format("%.3f", P95) .. "s, build " .. Tag .. ")")
		end
	end
end)

-- ========== memory guard ==========
local MemoryGuard = {baselines = {}}

local function CountTagged(Prefix): number
	local Count = 0
	local Ok, CoreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if not Ok or not CoreGui then return 0 end
	for _, Descendant in CoreGui:GetDescendants() do
		if Descendant.Name:sub(1, #Prefix) == Prefix then
			Count = Count + 1
		end
	end
	return Count
end

task.spawn(function()
	while true do
		task.wait(CONFIG.Memory.Interval)
		pcall(function()
			local Count = CountTagged(CONFIG.Memory.ModuleTag)
			if Count > 0 then
				local Baseline = MemoryGuard.baselines.gui
				if Baseline and Count > Baseline * CONFIG.Memory.GrowthFactor then
					StateDirty = true
					table.insert(State.repairs, {what = "instance-leak:" .. Count, at = os.time()})
					Loud("memory: GUI instance count " .. tostring(Baseline) .. " -> " .. tostring(Count) .. " (leak suspected)")
					-- purge tagged instances created by our GUIs
					local Ok, CoreGui = pcall(function()
						return game:GetService("CoreGui")
					end)
					if Ok and CoreGui then
						for _, Descendant in CoreGui:GetDescendants() do
							if Descendant.Name:sub(1, #CONFIG.Memory.ModuleTag) == CONFIG.Memory.ModuleTag then
								pcall(function()
									Descendant:Destroy()
								end)
							end
						end
					end
				end
				MemoryGuard.baselines.gui = Count
			end
		end)
	end
end)

-- ========== public surface ==========
local AAR = {
	safeLoad = safeLoad,
	safeRun = safeRun,
	SelfTest = SelfTest,
	Refetch = Refetch,
	VaultLatest = VaultLatest,
	VaultStore = VaultStore,
	Report = WatchdogReport,
	SaveState = SaveState,
	Report2 = nil,

	Diagnose = function(Err: string, Source: string?)
		local OkDiag = pcall(WatchdogReport, tostring(Err), Source)
		return Ok(OkDiag)
	end,

	Status = function()
		return Ok({
			selfTest = SelfTestReport,
			signatures = Watchdog.Signatures,
			perf = Perf,
			memory = MemoryGuard.baselines,
		})
	end,

	shutdown = function()
		-- ordered teardown: stop producers, flush state, release references
		Perf.running = false
		SaveState()
		table.clear(Watchdog.Signatures)
		table.clear(Watchdog.Hooks)
		table.clear(Perf.samples)
		table.clear(MemoryGuard.baselines)
		warn = nil -- restore handled by executor on chunk teardown
		Loud("AAR shutdown complete")
	end,
}

-- idempotency: if an AAR is already running, shut it down before installing
if shared.AAR and shared.AAR.shutdown and shared.AAR ~= AAR then
	pcall(shared.AAR.shutdown)
end
shared.AAR = AAR

-- ========== boot ==========
task.spawn(function()
	local Restored = LoadState()
	if Restored.ok then
		Note("state restored: " .. tostring(#Restored.value.repairs or 0) .. " past repairs")
	end
	local Report = SelfTest()
	if Report.ok then
		Loud("self-test: " .. #Report.value.passed .. " passed, "
			.. #Report.value.failed .. " failed (repaired), "
			.. #Report.value.skipped .. " skipped")
	end
	SaveState()
end)

Loud("AAR v2 online")
return AAR
