--!nocheck
-- ShindoHub.lua | single file | Roblox Luau (executor)
-- Build-dependent data: NONE hardcoded. Game remotes are captured at runtime (REMOTES tab).
-- Executor API used: hookmetamethod, getnamecallmethod (capture only); optional: gethui, newcclosure,
-- sethiddenproperty, writefile/readfile/isfile. Missing optional API => that part degrades, rest runs.

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
}

local SLOT_NAMES = { "Attack", "Spin", "Quest", "Mentor", "Daily", "Dungeon", "EventBoss", "Home" }

-- numeric settings (type of default decides parsing) and their clamps
local S = {
	NameFilter = "",   -- substring, case-insensitive; empty = every non-player Humanoid
	FarmDistance = 4,  -- studs behind target
	FarmHeight = 0,
	AuraRadius = 30,
	AuraRate = 0.1,    -- seconds between aura ticks
	StuckSeconds = 4,  -- no HP drop on current target for this long => skip it 30s
	DungeonIdle = 6,   -- seconds with no target before the Dungeon slot is fired
}
local LIM = {
	FarmDistance = { 0, 100 }, FarmHeight = { -50, 50 }, AuraRadius = { 1, 500 },
	AuraRate = { 0.03, 5 }, StuckSeconds = { 1, 60 }, DungeonIdle = { 1, 300 },
}
-- toggles: nothing active at launch
local T = { Farm = false, Dungeon = false, FullFarm = false, Aura = false, Insta = false, Void = false, Boost = false }

-------------------------------------------------------------------------------- CORE STATE
local running = true
local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

local slots = {}
for _, n in ipairs(SLOT_NAMES) do slots[n] = { auto = false, interval = 1 } end
local locs = {}          -- { {name=, x=, y=, z=}, ... }
local targets = {}
local skipUntil = setmetatable({}, { __mode = "k" })
local lastScan, armed = 0, nil
local setStatus = function(_) end
local refreshSlot = function(_) end

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
				end
			end
		end
	end
	targets = out
	lastScan = os.clock()
end

local function nearestTarget(maxDist)
	local r = myRoot()
	if not r then return nil end
	local best, bd, now = nil, maxDist or math.huge, os.clock()
	for _, m in ipairs(targets) do
		if m.Parent and (skipUntil[m] or 0) < now and isAlive(m) then
			local d = (charRoot(m).Position - r.Position).Magnitude
			if d < bd then best, bd = m, d end
		end
	end
	return best, bd
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
	refreshSlot(name)
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
				if (cn == "RemoteEvent" or cn == "RemoteFunction") and not ignored(self.Name) then
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
	pcall(function() m:PivotTo(CFrame.new(r.Position.X, y - 150, r.Position.Z)) end)
end

local function applyModifiers(m)
	if T.Insta then instaKill(m) end
	if T.Void then voidTarget(m) end
end

-------------------------------------------------------------------------------- LOOPS
local curTarget, curHP, curProgress, noTargetSince, lastAura = nil, 0, 0, nil, 0

local function farmStep(r)
	local m = nearestTarget()
	if not m then
		curTarget = nil
		noTargetSince = noTargetSince or os.clock()
		if T.Dungeon and os.clock() - noTargetSince > S.DungeonIdle then
			fireSlot("Dungeon")
			noTargetSince = os.clock()
		end
		return
	end
	noTargetSince = nil
	local hum = m:FindFirstChildOfClass("Humanoid")
	local tr = charRoot(m)
	if curTarget ~= m then
		curTarget, curHP, curProgress = m, hum.Health, os.clock()
	elseif hum.Health < curHP then
		curHP, curProgress = hum.Health, os.clock()
	elseif os.clock() - curProgress > S.StuckSeconds then
		skipUntil[m] = os.clock() + 30
		curTarget = nil
		return
	end
	local cf = tr.CFrame * CFrame.new(0, S.FarmHeight, S.FarmDistance)
	if finiteVec(cf.Position) then
		r.CFrame = CFrame.lookAt(cf.Position, Vector3.new(tr.Position.X, cf.Position.Y, tr.Position.Z))
		r.AssemblyLinearVelocity = Vector3.zero
	end
	attack()
	applyModifiers(m)
end

task.spawn(function()
	while running do
		task.wait(0.05)
		local farmOn = T.Farm or T.Dungeon or T.FullFarm
		local auraOn = T.Aura or T.FullFarm
		local r, hum = myRoot(), myHum()
		if (farmOn or auraOn) and r and hum and hum.Health > 0 then
			if os.clock() - lastScan > CONFIG.TargetScanInterval then scan() end
			if farmOn then farmStep(r) end
			if auraOn and os.clock() - lastAura >= S.AuraRate then
				lastAura = os.clock()
				local near = nearestTarget(S.AuraRadius)
				if near then
					for _, m in ipairs(targets) do
						if m.Parent and (skipUntil[m] or 0) < os.clock() and isAlive(m) then
							if (charRoot(m).Position - r.Position).Magnitude <= S.AuraRadius then
								applyModifiers(m)
							end
						end
					end
					if not farmOn then
						faceTo(r, charRoot(near))
						attack()
					end
				end
			end
		else
			curTarget, noTargetSince = nil, nil
		end
	end
end)

-- simulation radius boost (helps client-side Health/PivotTo replicate when the server allows)
task.spawn(function()
	while running do
		task.wait(1)
		if T.Boost or T.FullFarm then
			pcall(function() lp.MaximumSimulationRadius = 1e9 end)
			if sethiddenproperty then pcall(sethiddenproperty, lp, "SimulationRadius", 1e9) end
		end
	end
end)

-- slot auto-fire (Spin / Quest / Mentor / Daily / Dungeon / EventBoss / Home)
task.spawn(function()
	while running do
		task.wait(0.1)
		for _, name in ipairs(SLOT_NAMES) do
			local s = slots[name]
			if name ~= "Attack" and s.auto and s.remote and os.clock() - (s.last or 0) >= s.interval then
				s.last = os.clock()
				fireSlot(name)
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

local inputBoxes = {}
local rebuildLocs = function() end

local function save()
	if not writefile then return setStatus("writefile missing - cannot save") end
	local data = { S = S, locs = locs, slots = {} }
	for name, s in pairs(slots) do
		local e = { auto = s.auto, interval = s.interval }
		if s.remote and s.args then
			local ok = true
			for i = 1, s.args.n do
				local t = type(s.args[i])
				if not (t == "string" or t == "number" or t == "boolean") then ok = false end
			end
			if ok then
				e.path, e.method, e.n, e.args = s.path, s.method, s.args.n, {}
				for i = 1, s.args.n do e.args[i] = s.args[i] end
			end
		end
		data.slots[name] = e
	end
	local ok = pcall(writefile, CONFIG.SaveFile, HttpService:JSONEncode(data))
	setStatus(ok and "saved" or "save failed")
end

local function load()
	if not (isfile and readfile) then return setStatus("readfile missing - cannot load") end
	local okF, exists = pcall(isfile, CONFIG.SaveFile)
	if not (okF and exists) then return setStatus("no save file") end
	local okR, raw = pcall(readfile, CONFIG.SaveFile)
	local okD, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not (okR and okD and type(data) == "table") then return setStatus("save file corrupt") end
	for k, v in pairs(data.S or {}) do
		if S[k] ~= nil and type(S[k]) == type(v) then S[k] = v end
	end
	locs = {}
	for _, l in ipairs(data.locs or {}) do
		if type(l) == "table" and type(l.name) == "string" and type(l.x) == "number"
			and type(l.y) == "number" and type(l.z) == "number" then
			locs[#locs + 1] = l
		end
	end
	local unresolved = {}
	for name, e in pairs(data.slots or {}) do
		local s = slots[name]
		if s and type(e) == "table" then
			s.auto = e.auto == true
			s.interval = type(e.interval) == "number" and math.clamp(e.interval, 0.03, 3600) or 1
			s.remote, s.args, s.path, s.method = nil, nil, nil, nil
			if type(e.path) == "string" and type(e.args) == "table" and type(e.n) == "number" then
				local inst = resolvePath(e.path)
				if inst and (inst.ClassName == "RemoteEvent" or inst.ClassName == "RemoteFunction") then
					local a = { n = e.n }
					for i = 1, e.n do a[i] = e.args[i] end
					s.remote, s.args, s.path = inst, a, e.path
					s.method = (e.method == "InvokeServer") and "InvokeServer" or "FireServer"
				else
					unresolved[#unresolved + 1] = name
				end
			end
		end
	end
	for k, tb in pairs(inputBoxes) do tb.Text = tostring(S[k]) end
	for _, n in ipairs(SLOT_NAMES) do refreshSlot(n) end
	rebuildLocs()
	setStatus(#unresolved > 0 and ("loaded; remote not found, recapture: " .. table.concat(unresolved, ",")) or "loaded")
end

-------------------------------------------------------------------------------- UI
local C = {
	bg = Color3.fromRGB(18, 18, 22), row = Color3.fromRGB(34, 34, 42), on = Color3.fromRGB(40, 110, 70),
	text = Color3.fromRGB(225, 225, 230), dim = Color3.fromRGB(140, 140, 150), top = Color3.fromRGB(28, 28, 36),
}
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
if not pcall(function() local f = Instance.new("Folder"); f.Parent = guiParent; f:Destroy() end) then
	guiParent = lp:WaitForChild("PlayerGui")
end

local gui = mk("ScreenGui", { Name = "ShindoHub", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, guiParent)
local win = mk("Frame", { Size = UDim2.new(0, 420, 0, 400), Position = UDim2.new(0.5, -210, 0.5, -200), BackgroundColor3 = C.bg, BorderSizePixel = 0 }, gui)
local verified = table.find(CONFIG.VerifiedPlaceIds, game.PlaceId) ~= nil
local top = mk("TextLabel", {
	Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.top, BorderSizePixel = 0, TextColor3 = C.text,
	Font = Enum.Font.Code, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
	Text = ("  ShindoHub | PlaceId %d | %s | INSERT hide"):format(game.PlaceId, verified and "verified" or "UNVERIFIED place"),
}, win)
local statusLbl = mk("TextLabel", {
	Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = C.top, BorderSizePixel = 0,
	TextColor3 = C.dim, Font = Enum.Font.Code, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
	Text = hookOk and "  ready" or "  hookmetamethod missing: REMOTES capture disabled",
}, win)
setStatus = function(t) statusLbl.Text = "  " .. tostring(t) end

local dragging, dragStart, startPos = false, nil, nil
track(top.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging, dragStart, startPos = true, i.Position, win.Position
	end
end))
track(UIS.InputChanged:Connect(function(i)
	if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		local d = i.Position - dragStart
		win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end))
track(UIS.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
end))
track(UIS.InputBegan:Connect(function(i, gp)
	if i.KeyCode == CONFIG.ToggleKey and not UIS:GetFocusedTextBox() then win.Visible = not win.Visible end
end))

local TABS = { "FARM", "COMBAT", "REMOTES", "TELEPORT", "CONFIG" }
local pages, tabBtns = {}, {}
local function showTab(name)
	for n, p in pairs(pages) do p.Visible = (n == name) end
	for n, b in pairs(tabBtns) do b.BackgroundColor3 = (n == name) and C.on or C.row end
end
for i, n in ipairs(TABS) do
	tabBtns[n] = mk("TextButton", {
		Position = UDim2.new((i - 1) / #TABS, 0, 0, 28), Size = UDim2.new(1 / #TABS, -2, 0, 24), BackgroundColor3 = C.row,
		BorderSizePixel = 0, Text = n, TextColor3 = C.text, Font = Enum.Font.Code, TextSize = 12,
	}, win)
	local page = mk("ScrollingFrame", {
		Position = UDim2.new(0, 6, 0, 58), Size = UDim2.new(1, -12, 1, -84), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Visible = false,
	}, win)
	mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	pages[n] = page
	track(tabBtns[n].MouseButton1Click:Connect(function() showTab(n) end))
end

local function addToggle(page, label, key)
	local b = mk("TextButton", {
		Size = UDim2.new(1, -8, 0, 26), BackgroundColor3 = C.row, BorderSizePixel = 0, TextColor3 = C.text,
		Font = Enum.Font.Code, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, page)
	local function paint()
		b.Text = (T[key] and "  [ ON ]  " or "  [ OFF ] ") .. label
		b.BackgroundColor3 = T[key] and C.on or C.row
	end
	paint()
	track(b.MouseButton1Click:Connect(function() T[key] = not T[key]; paint() end))
end

local function addInput(page, label, key)
	local f = mk("Frame", { Size = UDim2.new(1, -8, 0, 26), BackgroundColor3 = C.row, BorderSizePixel = 0 }, page)
	mk("TextLabel", {
		Size = UDim2.new(0.6, 0, 1, 0), BackgroundTransparency = 1, Text = "  " .. label, TextColor3 = C.text,
		Font = Enum.Font.Code, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, f)
	local tb = mk("TextBox", {
		Position = UDim2.new(0.6, 0, 0, 2), Size = UDim2.new(0.4, -4, 1, -4), BackgroundColor3 = C.bg, BorderSizePixel = 0,
		Text = tostring(S[key]), TextColor3 = C.text, Font = Enum.Font.Code, TextSize = 13, ClearTextOnFocus = false,
	}, f)
	inputBoxes[key] = tb
	track(tb.FocusLost:Connect(function()
		if type(S[key]) == "number" then
			local n = tonumber(tb.Text)
			if n and n == n then
				local lim = LIM[key]
				S[key] = lim and math.clamp(n, lim[1], lim[2]) or n
			end
			tb.Text = tostring(S[key])
		else
			S[key] = tb.Text
		end
	end))
end

local function addButton(page, label, fn)
	local b = mk("TextButton", {
		Size = UDim2.new(1, -8, 0, 26), BackgroundColor3 = C.row, BorderSizePixel = 0, Text = "  " .. label,
		TextColor3 = C.text, Font = Enum.Font.Code, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, page)
	track(b.MouseButton1Click:Connect(fn))
	return b
end

-- FARM
addToggle(pages.FARM, "Auto Farm (nearest target)", "Farm")
addToggle(pages.FARM, "Auto Dungeon (farm all + Dungeon slot when empty)", "Dungeon")
addToggle(pages.FARM, "FULLY FARM (farm + aura + sim-radius boost)", "FullFarm")
addToggle(pages.FARM, "Sim radius boost", "Boost")
addInput(pages.FARM, "Name filter (boss / mob)", "NameFilter")
addInput(pages.FARM, "Farm distance", "FarmDistance")
addInput(pages.FARM, "Farm height", "FarmHeight")
addInput(pages.FARM, "Stuck skip (s)", "StuckSeconds")
addInput(pages.FARM, "Dungeon idle (s)", "DungeonIdle")

-- COMBAT
addToggle(pages.COMBAT, "Kill Aura", "Aura")
addToggle(pages.COMBAT, "Insta Kill  [uncalibrated: needs ownership]", "Insta")
addToggle(pages.COMBAT, "Void  [uncalibrated: PivotTo under map]", "Void")
addInput(pages.COMBAT, "Aura radius", "AuraRadius")
addInput(pages.COMBAT, "Aura rate (s)", "AuraRate")

-- REMOTES
local slotUI = {}
refreshSlot = function(name)
	local u, s = slotUI[name], slots[name]
	if not u then return end
	u.lbl.Text = ("  %s: %s"):format(name, s.remote and (s.path .. " (" .. s.args.n .. " args)") or "UNSET")
	u.auto.Text = s.auto and "AUTO ON" or "AUTO OFF"
	u.auto.BackgroundColor3 = s.auto and C.on or C.row
	u.iv.Text = tostring(s.interval)
end
for _, name in ipairs(SLOT_NAMES) do
	local f = mk("Frame", { Size = UDim2.new(1, -8, 0, 52), BackgroundColor3 = C.row, BorderSizePixel = 0 }, pages.REMOTES)
	local lbl = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, TextColor3 = C.text, Font = 
