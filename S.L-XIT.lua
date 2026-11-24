--!nocheck
-- ShindoHub.lua | single file | Roblox Luau (executor, Delta-friendly: touch + mobile toggle button)
-- GitHub: no requires, no relative paths. Load with:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/<USER>/<REPO>/<BRANCH>/ShindoHub.lua"))()
-- No key system. Build-dependent data: NONE hardcoded. Game remotes are captured at runtime (SLOTS tab).
-- Executor API used: hookmetamethod, getnamecallmethod (capture only); optional: gethui, newcclosure,
-- checkcaller, sethiddenproperty, writefile/readfile/isfile. Missing optional API => that part degrades, rest runs.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer

local G = (getgenv and getgenv()) or _G
if G.__SHUB then pcall(G.__SHUB.Unload) end

-------------------------------------------------------------------------------- CONFIG
local CONFIG = {
	-- PlaceIds this script was verified on. EMPTY = nothing verified (header shows UNVERIFIED).
	VerifiedPlaceIds = {},
	SaveFile = "ShindoHub_config.json",
	ToggleKey = Enum.KeyCode.Insert,
	-- remotes whose name contains one of these are skipped by CAPTURE (movement/camera spam)
	IgnoreRemoteNames = { "mouse", "camera", "ping", "heartbeat", "move", "position", "look", "cursor" },
	TargetScanInterval = 1.0,
	MaxTargets = 400,
	CaptureTimeout = 20,
}

-- Spirit  = Sand Worm spirit awakening remote   | Bijuu = bijuu summon/start remote (both captured by you)
local SLOT_NAMES = { "Attack", "Spin", "Quest", "Mentor", "Daily", "Dungeon", "EventBoss", "Home", "Spirit", "Bijuu" }
local IDLE_SLOTS = { "Dungeon", "EventBoss", "Bijuu" }                              -- cycled by AUTO ALL when no target
local AUTOALL_SLOTS = { Spin = true, Quest = true, Mentor = true, Daily = true, Spirit = true }

-- numeric/string settings (type of default decides parsing) and their clamps
local S = {
	NameFilter = "",       -- substring, case-insensitive; empty = every non-player Humanoid
	BossKeywords = "boss", -- comma list, UNVERIFIED generic default: replace with the real names
	BijuuKeywords = "",    -- comma list of bijuu names as they appear in workspace (YOU fill, nothing assumed)
	BossMinHP = 0,         -- MaxHealth >= this counts as boss; 0 = off
	FarmDistance = 4,      -- studs from target
	FarmHeight = 0,
	FarmRange = 5000,      -- ignore targets farther than this
	OrbitSpeed = 2,        -- rad/s, Orbit position mode
	AuraRadius = 30,
	AuraRate = 0.1,        -- seconds between aura/pull ticks
	PullRange = 60,        -- mobs within this radius get pulled
	PullZ = 8,             -- studs in front of you where pulled mobs are placed
	PullHeight = 0,
	StuckSeconds = 4,      -- no HP drop on current target for this long => skip it 30s
	DungeonIdle = 6,       -- seconds with no target before an idle slot is fired
	-- SPIRIT VOID (Sand Worm awakening): fire Spirit slot, grab target(s) in front of you, then send to void
	SpiritRange = 40,      -- studs: targets considered for the grab
	SpiritTargets = 1,     -- max targets grabbed per cast
	SpiritGrabDelay = 0.1, -- seconds between grab and void
	SpiritCooldown = 3,    -- seconds between auto casts (SPIRIT VOID toggle)
}
local LIM = {
	BossMinHP = { 0, 1e9 }, FarmDistance = { 0, 100 }, FarmHeight = { -50, 50 }, FarmRange = { 10, 1e5 },
	OrbitSpeed = { 0, 20 }, AuraRadius = { 1, 500 }, AuraRate = { 0.03, 5 }, PullRange = { 1, 1000 },
	PullZ = { 0, 200 }, PullHeight = { -50, 50 }, StuckSeconds = { 1, 60 }, DungeonIdle = { 1, 300 },
	SpiritRange = { 1, 1000 }, SpiritTargets = { 1, 20 }, SpiritGrabDelay = { 0, 2 }, SpiritCooldown = { 0.2, 600 },
}
-- method selectors
local M = { Select = "Nearest", Pos = "Behind" }
local OPT = { Select = { "Nearest", "LowestHP", "HighestHP" }, Pos = { "Behind", "Front", "Above", "Below", "Orbit" } }

-- toggles: nothing active at launch (Master is only a gate, ON by default)
local T = {
	Master = true,
	Farm = false, BossFarm = false, BijuuFarm = false, Dungeon = false, FullFarm = false, AutoAll = false,
	Aura = false, Insta = false, Void = false, Pull = false, VoidFarm = false, Boost = false,
	SpiritVoid = false,
}

-------------------------------------------------------------------------------- CORE STATE
local running = true
local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

local slots = {}
for _, n in ipairs(SLOT_NAMES) do slots[n] = { auto = false, interval = 1 } end
local locs = {}          -- { {name=, x=, y=, z=}, ... }
local targets = {}
local skipUntil = setmetatable({}, { __mode = "k" })
local lastScan, armed, armGen = 0, nil, 0
local setStatus = function(_) end
local refreshSlot = function(_) end
local refreshAllSlots = function() end

local function finiteNum(n) return type(n) == "number" and n == n and math.abs(n) < 1e9 end
local function finiteVec(v)
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e7 and math.abs(v.Y) < 1e7 and math.abs(v.Z) < 1e7
end
local function charRoot(m) return m and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart) end
local function myRoot() local c = lp.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function myHum() local c = lp.Character; return c and c:FindFirstChildOfClass("Humanoid") end
local function isAlive(m)
	local h = m:FindFirstChildOfClass("Humanoid")
	local r = charRoot(m)
	return h ~= nil and r ~= nil and h.Health > 0 and h.Health == h.Health and finiteVec(r.Position)
end
local function safeLook(pos, at)
	if (at - pos).Magnitude < 0.01 then return CFrame.new(pos) end
	return CFrame.lookAt(pos, at)
end

pcall(function() VirtualUser:CaptureController() end)
track(lp.Idled:Connect(function()
	pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
end))

-------------------------------------------------------------------------------- TARGETS
local function scan()
	local out, filter = {}, string.lower(S.NameFilter or "")
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Humanoid") then
			local m = d.Parent
			if m and m:IsA("Model") and m ~= lp.Character and not Players:GetPlayerFromCharacter(m) then
				if filter == "" or string.find(string.lower(m.Name), filter, 1, true) then
					out[#out + 1] = m
					if #out >= CONFIG.MaxTargets then break end
				end
			end
		end
	end
	targets = out
	lastScan = os.clock()
end

local kwCache = {}
local function kw(str)
	local c = kwCache[str]
	if c then return c end
	c = {}
	for w in string.gmatch(string.lower(str), "[^,]+") do
		w = string.match(w, "^%s*(.-)%s*$")
		if w ~= "" then c[#c + 1] = w end
	end
	kwCache[str] = c
	return c
end
local function nameHas(m, str)
	local n = string.lower(m.Name)
	for _, w in ipairs(kw(str)) do
		if string.find(n, w, 1, true) then return true end
	end
	return false
end
local function isBoss(m, hum)
	return nameHas(m, S.BossKeywords) or (S.BossMinHP > 0 and hum ~= nil and hum.MaxHealth >= S.BossMinHP)
end
local function isBijuu(m) return nameHas(m, S.BijuuKeywords) end

-- BossFarm/BijuuFarm alone => farm ONLY those; with any general farm on => everything, bosses first
local function generalFarm() return T.Farm or T.Dungeon or T.FullFarm or T.AutoAll end
local function restrictMode() return (T.BossFarm or T.BijuuFarm) and not generalFarm() end
local function passesRestrict(m, hum)
	return (T.BossFarm and isBoss(m, hum)) or (T.BijuuFarm and isBijuu(m))
end

local function pickTarget(r)
	local restrict = restrictMode()
	local prio = T.AutoAll or T.BossFarm or T.BijuuFarm
	local best, bScore, bPrio, bd
	local now = os.clock()
	for _, m in ipairs(targets) do
		if m.Parent and (skipUntil[m] or 0) < now and isAlive(m) then
			local hum = m:FindFirstChildOfClass("Humanoid")
			local d = (charRoot(m).Position - r.Position).Magnitude
			if d <= S.FarmRange and (not restrict or passesRestrict(m, hum)) then
				local p = (prio and (isBoss(m, hum) or isBijuu(m))) and 0 or 1
				local sc = d
				if M.Select == "LowestHP" then sc = hum.Health
				elseif M.Select == "HighestHP" then sc = -hum.Health end
				if not best or p < bPrio or (p == bPrio and sc < bScore) then
					best, bScore, bPrio, bd = m, sc, p, d
				end
			end
		end
	end
	return best, bd
end

local function eachInRange(r, range, useFilter, fn)
	local now = os.clock()
	local restrict = useFilter and restrictMode()
	for _, m in ipairs(targets) do
		if m.Parent and (skipUntil[m] or 0) < now and isAlive(m) then
			local d = (charRoot(m).Position - r.Position).Magnitude
			if d <= range then
				local hum = m:FindFirstChildOfClass("Humanoid")
				if not restrict or passesRestrict(m, hum) then fn(m, d) end
			end
		end
	end
end

-------------------------------------------------------------------------------- REMOTE CAPTURE / REPLAY
local function ignored(name)
	local n = string.lower(name)
	for _, p in ipairs(CONFIG.IgnoreRemoteNames) do
		if string.find(n, p, 1, true) then return true end
	end
	return false
end

local function bindSlot(name, remote, method, args)
	local s = slots[name]
	s.remote, s.method, s.args, s.path = remote, method, args, remote:GetFullName()
	refreshAllSlots()
	setStatus(("BOUND %s -> %s (%d args)"):format(name, s.path, args.n))
end

local hookOk = false
if hookmetamethod and getnamecallmethod then
	local old
	local function nc(self, ...)
		if armed and running then
			local method = getnamecallmethod()
			if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
				local cn = self.ClassName -- property read, does not re-enter __namecall
				-- checkcaller: ignore our own replays, capture only the game's/your real action
				if (cn == "RemoteEvent" or cn == "RemoteFunction") and not ignored(self.Name)
					and not (checkcaller and checkcaller()) then
					local slotName = armed
					armed = nil
					local args = table.pack(...)
					task.defer(bindSlot, slotName, self, method, args)
				end
			end
		end
		return old(self, ...)
	end
	local ok = pcall(function()
		old = hookmetamethod(game, "__namecall", newcclosure and newcclosure(nc) or nc)
	end)
	hookOk = ok and old ~= nil
end

local function fireSlot(name)
	local s = slots[name]
	if not (s and s.remote and s.remote.Parent and s.args) then return false end
	task.spawn(function()
		pcall(function()
			if s.method == "InvokeServer" then
				s.remote:InvokeServer(unpack(s.args, 1, s.args.n))
			else
				s.remote:FireServer(unpack(s.args, 1, s.args.n))
			end
		end)
	end)
	return true
end

-------------------------------------------------------------------------------- COMBAT PRIMITIVES
local function faceTo(r, tr)
	local p = tr.Position
	local look = Vector3.new(p.X, r.Position.Y, p.Z)
	if (look - r.Position).Magnitude > 0.05 then r.CFrame = CFrame.lookAt(r.Position, look) end
end

local function attack()
	if slots.Attack.remote then
		fireSlot("Attack")
		return
	end
	-- fallback: generic M1 (equipped Tool or simulated click). Game-specific attacks need the Attack slot.
	local c = lp.Character
	local tool = c and c:FindFirstChildOfClass("Tool")
	if tool then pcall(function() tool:Activate() end) end
	pcall(function() VirtualUser:ClickButton1(Vector2.new(0, 0)) end)
end

-- UNCALIBRATED: only replicates if this client has network ownership of the mob / server trusts it.
local function instaKill(m)
	local h = m:FindFirstChildOfClass("Humanoid")
	if h then pcall(function() h.Health = 0 end) end
end

local function voidTarget(m)
	local r = charRoot(m)
	if not r then return end
	local y = workspace.FallenPartsDestroyHeight
	if y ~= y or y < -1e6 then y = -1000 end
	-- y = FallenPartsDestroyHeight (the place's kill plane); fallback -1000 is UNVERIFIED if the place disables it
	pcall(function()
		m:PivotTo(CFrame.new(r.Position.X, y - 150, r.Position.Z))
		r.AssemblyLinearVelocity = Vector3.new(0, -500, 0)
	end)
	local h = m:FindFirstChildOfClass("Humanoid")
	if h then pcall(function() h.Health = 0 end) end
end

local function applyModifiers(m)
	if T.Insta then instaKill(m) end
	if T.Void then voidTarget(m) end
end

-- SPIRIT VOID (Sand Worm awakening). UNCALIBRATED: grab/void only replicates with network ownership of the mob.
-- Sequence: fire captured Spirit slot -> PivotTo target(s) in front of you (grab) -> wait SpiritGrabDelay -> void.
local spiritBusy, lastSpirit = false, 0
local function spiritVoidStrike()
	if spiritBusy then return false end
	local r = myRoot()
	if not r then return false end
	local list = {}
	eachInRange(r, S.SpiritRange, true, function(m, d) list[#list + 1] = { m = m, d = d } end)
	if #list == 0 then return false end
	table.sort(list, function(a, b) return a.d < b.d end)
	local picked = {}
	for i = 1, math.min(S.SpiritTargets, #list) do picked[i] = list[i].m end
	spiritBusy = true
	fireSlot("Spirit") -- no-op if not captured; grab + void still run
	local base = r.CFrame * CFrame.new(0, S.PullHeight, -S.PullZ)
	if finiteVec(base.Position) then
		for _, m in ipairs(picked) do
			pcall(function() m:PivotTo(base) end)
		end
	end
	task.delay(S.SpiritGrabDelay, function()
		for _, m in ipairs(picked) do
			if m.Parent then voidTarget(m) end
		end
		spiritBusy = false
	end)
	return true
end

-- where the player stands relative to the target, per method (M.Pos)
local function farmCFrame(tr)
	local d, h, p = S.FarmDistance, S.FarmHeight, M.Pos
	local tp = tr.Position
	if p == "Behind" or p == "Front" then
		local cf = tr.CFrame * CFrame.new(0, h, p == "Behind" and d or -d)
		return safeLook(cf.Position, Vector3.new(tp.X, cf.Position.Y, tp.Z))
	elseif p == "Above" then
		return safeLook(tp + Vector3.new(0, d + h, 0.5), tp)
	elseif p == "Below" then
		return safeLook(tp + Vector3.new(0, h - d, 0.5), tp)
	end
	local a = os.clock() * S.OrbitSpeed
	local pos = tp + Vector3.new(math.sin(a) * d, h, math.cos(a) * d)
	return safeLook(pos, Vector3.new(tp.X, pos.Y, tp.Z))
end

-------------------------------------------------------------------------------- LOOPS
local curTarget, curHP, curProgress, noTargetSince, lastBulk, idleIdx = nil, 0, 0, nil, 0, 0

local function idleFire()
	if T.AutoAll then
		for _ = 1, #IDLE_SLOTS do
			idleIdx = idleIdx % #IDLE_SLOTS + 1
			if fireSlot(IDLE_SLOTS[idleIdx]) then return end
		end
	elseif T.Dungeon then
		fireSlot("Dungeon")
	end
end

local function farmStep(r)
	local m = pickTarget(r)
	if not m then
		curTarget = nil
		noTargetSince = noTargetSince or os.clock()
		if (T.Dungeon or T.AutoAll) and os.clock() - noTargetSince > S.DungeonIdle then
			idleFire()
			noTargetSince = os.clock()
		end
		return
	end
	noTargetSince = nil
	local hum = m:FindFirstChildOfClass("Humanoid")
	local tr = charRoot(m)
	if not (hum and tr) then return end
	if curTarget ~= m then
		curTarget, curHP, curProgress = m, hum.Health, os.clock()
	elseif hum.Health < curHP then
		curHP, curProgress = hum.Health, os.clock()
	elseif os.clock() - curProgress > S.StuckSeconds then
		skipUntil[m] = os.clock() + 30
		curTarget = nil
		return
	end
	local cf = farmCFrame(tr)
	if finiteVec(cf.Position) then
		r.CFrame = cf
		r.AssemblyLinearVelocity = Vector3.zero
	end
	attack()
	applyModifiers(m)
end

-- pull / void-farm / aura tick (rate = AuraRate)
local function bulkStep(r, pullOn, voidOn, auraOn, farmOn)
	if pullOn or voidOn then
		local base = r.CFrame * CFrame.new(0, S.PullHeight, -S.PullZ)
		if finiteVec(base.Position) then
			eachInRange(r, S.PullRange, true, function(m)
				-- VoidFarm: mobs already gathered at the pull point get sent under the map
				if voidOn and (charRoot(m).Position - base.Position).Magnitude <= 6 then
					voidTarget(m)
				else
					pcall(function() m:PivotTo(base) end)
				end
			end)
		end
	end
	if auraOn then
		local near, nd = nil, math.huge
		eachInRange(r, S.AuraRadius, false, function(m, d)
			applyModifiers(m)
			if d < nd then near, nd = m, d end
		end)
		if near and not farmOn then
			faceTo(r, charRoot(near))
			attack()
		end
	end
end

task.spawn(function()
	while running do
		task.wait(0.05)
		if T.Master then
			local farmOn = generalFarm() or T.BossFarm or T.BijuuFarm
			local auraOn = T.Aura or T.FullFarm or T.AutoAll
			local r, hum = myRoot(), myHum()
			if (farmOn or auraOn or T.Pull or T.VoidFarm or T.SpiritVoid) and r and hum and hum.Health > 0 then
				if os.clock() - lastScan > CONFIG.TargetScanInterval then pcall(scan) end
				if farmOn then pcall(farmStep, r) end
				if os.clock() - lastBulk >= S.AuraRate then
					lastBulk = os.clock()
					pcall(bulkStep, r, T.Pull, T.VoidFarm, auraOn, farmOn)
				end
				if T.SpiritVoid and os.clock() - lastSpirit >= S.SpiritCooldown then
					local ok, fired = pcall(spiritVoidStrike)
					if ok and fired then lastSpirit = os.clock() end
				end
			else
				curTarget, noTargetSince = nil, nil
			end
		end
	end
end)

-- simulation radius boost (helps client-side Health/PivotTo replicate when the server allows)
task.spawn(function()
	while running do
		task.wait(1)
		if T.Master and (T.Boost or T.FullFarm or T.VoidFarm or T.Pull or T.SpiritVoid) then
			pcall(function() lp.MaximumSimulationRadius = 1e9 end)
			if sethiddenproperty then pcall(sethiddenproperty, lp, "SimulationRadius", 1e9) end
		end
	end
end)

-- slot auto-fire: per-slot AUTO, AUTO ALL (Spin/Quest/Mentor/Daily/Spirit), VOID FARM (Spirit)
task.spawn(function()
	while running do
		task.wait(0.1)
		if T.Master then
			for _, name in ipairs(SLOT_NAMES) do
				local s = slots[name]
				local want = s.auto or (T.AutoAll and AUTOALL_SLOTS[name]) or (T.VoidFarm and name == "Spirit")
				if name ~= "Attack" and want and s.remote and os.clock() - (s.last or 0) >= s.interval then
					s.last = os.clock()
					fireSlot(name)
				end
			end
		end
	end
end)

-------------------------------------------------------------------------------- PERSISTENCE
local function resolvePath(path)
	local cur = game
	for _, p in ipairs(string.split(path, ".")) do
		cur = cur and cur:FindFirstChild(p)
		if not cur then return nil end
	end
	return cur
end

local inputBoxes, cyclePainters = {}, {}
local rebuildLocs = function() end

local function saveCfg()
	if not writefile then return setStatus("writefile missing - cannot save") end
	local data = { S = S, M = M, locs = locs, slots = {} }
	for name, s in pairs(slots) do
		local e = { auto = s.auto, interval = s.interval }
		if s.remote and s.args then
			local ok = true
			for i = 1, s.args.n do
				local v = s.args[i]
				local t = type(v)
				if not (t == "string" or t == "boolean" or (t == "number" and finiteNum(v))) then ok = false end
			end
			if ok then
				e.path, e.method, e.n, e.args = s.path, s.method, s.args.n, {}
				for i = 1, s.args.n do e.args[i] = s.args[i] end
			end
		end
		data.slots[name] = e
	end
	local ok = pcall(function() writefile(CONFIG.SaveFile, HttpService:JSONEncode(data)) end)
	setStatus(ok and "saved" or "save failed")
end

local function loadCfg()
	if not (isfile and readfile) then return setStatus("readfile missing - cannot load") end
	local okF, exists = pcall(isfile, CONFIG.SaveFile)
	if not (okF and exists) then return setStatus("no save file") end
	local okR, raw = pcall(readfile, CONFIG.SaveFile)
	local okD, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not (okR and okD and type(data) == "table") then return setStatus("save file corrupt") end
	for k, v in pairs(type(data.S) == "table" and data.S or {}) do
		if S[k] ~= nil and type(S[k]) == type(v) then
			if type(v) == "number" then
				if finiteNum(v) then
					local lim = LIM[k]
					S[k] = lim and math.clamp(v, lim[1], lim[2]) or v
				end
			else
				S[k] = v
			end
		end
	end
	for k, v in pairs(type(data.M) == "table" and data.M or {}) do
		if OPT[k] and table.find(OPT[k], v) then M[k] = v end
	end
	locs = {}
	for _, l in ipairs(type(data.locs) == "table" and data.locs or {}) do
		if type(l) == "table" and type(l.name) == "string" and finiteNum(l.x) and finiteNum(l.y) and finiteNum(l.z) then
			locs[#locs + 1] = { name = l.name, x = l.x, y = l.y, z = l.z }
		en
