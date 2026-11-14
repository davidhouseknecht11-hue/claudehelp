-- MoonCollision  (ModuleScript, child of the LobbyUpgrade script - server only)
--
-- The Transcendent disaster. DisasterGameManager runs it through its ExtraDisasters hook
-- (ServerStorage > ExtraDisasters > MoonCollision, a BindableFunction made here).
--   1. Approach: a huge moon falls at 5,000 studs/s from 100,000 studs away (20 s). Every
--      player's screen shows the countdown + distance (MoonFX). Nuclear bunkers rise out of the island.
--   2. Impact: blast doors slam shut; anyone outside a bunker dies. The island loses its vegetation and
--      turns yellow, the water boils away, the atmosphere is gone.
--   3. Aftermath (45 s): survivors get a 15 s oxygen tank. Harvest palm trees for +8 s each
--      (only while the tank is not full). Out of oxygen = eliminated.
-- Everything the disaster changes on the island is put back when the round ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local START_DISTANCE = 100000 -- studs
local MOON_SPEED = 5000       -- studs per second  (=> 20 s countdown)
local AFTERMATH = 45          -- seconds the round goes on after the crash
local TANK_SECONDS = 15       -- a full oxygen tank
local TREE_OXYGEN = 8         -- seconds of oxygen per harvested palm tree
local DOORS_CLOSE_BEFORE = 2.5
local BUNKER_COUNT = 2
local BARREN_COLOR = Color3.fromRGB(214, 188, 104)

local Moon = {}
local Kit = nil
local remote = nil
local running = false

local function mk(class, p, parent)
	local inst = Instance.new(class)
	for k, v in pairs(p) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function islandBounds()
	local island = workspace:FindFirstChild("IslandMap")
	local ground = island and (island:FindFirstChild("Ground") or island)
	local water = island and island:FindFirstChild("Water")
	local lo, hi
	if ground then
		for _, d in ipairs(ground:GetDescendants()) do
			if d:IsA("BasePart") and not (water and water:IsAncestorOf(d)) then
				local a, b = d.Position - d.Size / 2, d.Position + d.Size / 2
				lo = lo and Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z)) or a
				hi = hi and Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z)) or b
			end
		end
	end
	return lo, hi, island, ground
end

--------------------------------------------------------------------
-- Bunkers
--------------------------------------------------------------------
-- local layout (studs): 34 wide (X), 26 deep (Z), 12 tall inside, door 10 x 9 on the front (-Z)
local WALLS = {
	{ Vector3.new(34, 2, 26), Vector3.new(0, 13, 0) },     -- roof
	{ Vector3.new(2, 12, 26), Vector3.new(-16, 6, 0) },
	{ Vector3.new(2, 12, 26), Vector3.new(16, 6, 0) },
	{ Vector3.new(30, 12, 2), Vector3.new(0, 6, 12) },     -- back
	{ Vector3.new(10, 12, 2), Vector3.new(-10, 6, -12) },  -- front left of the door
	{ Vector3.new(10, 12, 2), Vector3.new(10, 6, -12) },
	{ Vector3.new(10, 3, 2), Vector3.new(0, 10.5, -12) },  -- over the door
	{ Vector3.new(30, 0.4, 22), Vector3.new(0, 0.2, 0) },  -- floor
}
local DOOR_OPEN = CFrame.new(10.5, 0, 0)

local function buildBunker(folder, pos, faceDir)
	local cf = CFrame.lookAt(pos, pos + faceDir)
	local bunker = { cf = cf }
	bunker.model = Kit.spawn("Bunker", cf - Vector3.new(0, 16, 0), { parent = folder, shadows = true })
	for _, w in ipairs(WALLS) do
		mk("Part", {
			Name = "BunkerWall",
			Size = w[1],
			CFrame = cf * CFrame.new(w[2]),
			Anchored = true,
			Transparency = 1,
			CastShadow = false,
		}, folder)
	end
	bunker.doorClosed = cf * CFrame.new(0, 4.5, -13.8)
	bunker.doorBlock = mk("Part", {
		Name = "BlastDoor",
		Size = Vector3.new(10, 9, 1.2),
		CFrame = bunker.doorClosed * DOOR_OPEN,
		Anchored = true,
		Transparency = 1,
	}, folder)
	if bunker.model then
		-- door + wheel positions relative to the model's pivot (the door piece is modelled shut)
		local pivot = bunker.model:GetPivot()
		bunker.doorVisual = bunker.model:FindFirstChild("door")
		bunker.wheel = bunker.model:FindFirstChild("doorWheel")
		bunker.doorRel = bunker.doorVisual and pivot:ToObjectSpace(bunker.doorVisual.CFrame)
		bunker.wheelRel = bunker.wheel and pivot:ToObjectSpace(bunker.wheel.CFrame)
		for _, name in ipairs({ "alarm", "lights" }) do
			local p = bunker.model:FindFirstChild(name)
			if p then
				mk("PointLight", { Color = name == "alarm" and Color3.fromRGB(255, 40, 30) or Color3.fromRGB(255, 240, 210), Range = 26, Brightness = 2 }, p)
			end
		end
	end
	-- the model rises out of the ground (and the door slides open with it)
	task.spawn(function()
		local t0 = os.clock()
		while bunker.model and bunker.model.Parent do
			local a = math.min((os.clock() - t0) / 3, 1)
			local e = TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			bunker.model:PivotTo(cf - Vector3.new(0, 16 * (1 - e), 0))
			if a >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		Moon.setDoor(bunker, 1)
	end)
	return bunker
end

-- open = 1 (slid aside) .. 0 (shut)
function Moon.setDoor(bunker, open)
	local offset = CFrame.new(10.5 * open, 0, 0)
	bunker.doorBlock.CFrame = bunker.doorClosed * offset
	if bunker.model and bunker.model.Parent then
		local pivot = bunker.model:GetPivot()
		if bunker.doorRel then
			bunker.doorVisual.CFrame = pivot * offset * bunker.doorRel
		end
		if bunker.wheelRel then -- the wheel turns as the door rolls
			bunker.wheel.CFrame = pivot * offset * bunker.wheelRel * CFrame.Angles(0, 0, open * math.pi * 2)
		end
	end
end

local function slideDoors(bunkers, toOpen, seconds)
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local a = math.min((os.clock() - t0) / seconds, 1)
			local open = toOpen == 1 and a or 1 - a
			for _, b in ipairs(bunkers) do
				Moon.setDoor(b, TweenService:GetValue(open, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut))
			end
			if a >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function insideBunker(bunkers, pos)
	for _, b in ipairs(bunkers) do
		local p = b.cf:PointToObjectSpace(pos)
		if math.abs(p.X) < 15.5 and math.abs(p.Z) < 11.5 and p.Y > -2 and p.Y < 12.5 then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------
-- World changes (all recorded so they can be undone)
--------------------------------------------------------------------
local undo = {}
local function remember(inst, props)
	local saved = {}
	for _, k in ipairs(props) do
		saved[k] = inst[k]
	end
	table.insert(undo, { inst = inst, saved = saved })
end

local function restoreWorld()
	for i = #undo, 1, -1 do
		local u = undo[i]
		if u.inst.Parent then
			for k, v in pairs(u.saved) do
				pcall(function()
					u.inst[k] = v
				end)
			end
		end
	end
	undo = {}
end

local function palmTrees(island)
	local trees = {}
	local decor = island and island:FindFirstChild("Decor")
	for _, d in ipairs(decor and decor:GetDescendants() or {}) do
		if d:IsA("Model") and d.Name == "PalmTree" then
			table.insert(trees, d)
		end
	end
	return trees
end

local LEAFY = { Leaf = true, Crown = true, Coconut = true }

local function barren(island, ground)
	-- ground: vegetation burnt off, yellowish dust
	for _, d in ipairs(ground and ground:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			remember(d, { "Color", "Material" })
			d.Material = Enum.Material.Sand
			TweenService:Create(d, TweenInfo.new(2.5), { Color = d.Color:Lerp(BARREN_COLOR, 0.8) }):Play()
		end
	end
	-- small plants vanish (palm trunks + rocks stay)
	local decor = island and island:FindFirstChild("Decor")
	for _, d in ipairs(decor and decor:GetDescendants() or {}) do
		if d:IsA("BasePart") and not d:FindFirstAncestor("PalmTree") and not d:FindFirstAncestor("Rocks") then
			remember(d, { "Transparency", "CanCollide" })
			d.CanCollide = false
			TweenService:Create(d, TweenInfo.new(1.5), { Transparency = 1 }):Play()
		end
	end
	-- the sea boils away
	local water = island and island:FindFirstChild("Water")
	for _, d in ipairs(water and water:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			remember(d, { "CFrame", "Transparency", "CanCollide", "CanTouch" })
			d.CanCollide = false
			TweenService:Create(d, TweenInfo.new(6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = d.CFrame - Vector3.new(0, 400, 0),
				Transparency = 1,
			}):Play()
			task.delay(6, function()
				d.CanTouch = false
			end)
		end
	end
	local seafloor = island and island:FindFirstChild("Seafloor")
	for _, d in ipairs(seafloor and seafloor:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			remember(d, { "Color" })
			TweenService:Create(d, TweenInfo.new(6), { Color = d.Color:Lerp(BARREN_COLOR, 0.6) }):Play()
		end
	end
end

local function stripTree(tree)
	for _, p in ipairs(tree:GetDescendants()) do
		if p:IsA("BasePart") and LEAFY[p.Name] then
			remember(p, { "CFrame", "Transparency", "CanCollide", "Anchored" })
			p.CanCollide = false
			p.Anchored = true
			local out = (p.Position - tree:GetPivot().Position) * Vector3.new(1, 0, 1)
			out = out.Magnitude > 0.1 and out.Unit or Vector3.new(1, 0, 0)
			TweenService:Create(p, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = p.CFrame * CFrame.Angles(math.random() * 2, math.random() * 2, 0) + out * 8 - Vector3.new(0, 10, 0),
				Transparency = 1,
			}):Play()
		end
	end
end

--------------------------------------------------------------------
-- Oxygen
--------------------------------------------------------------------
local oxygen = {} -- [Player] = seconds left

local function attachTank(character)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not Kit.has("OxygenTank") then
		return
	end
	local tank = Kit.spawn("OxygenTank", torso.CFrame * CFrame.new(0, 0.1, 0.85), { parent = character, shadows = false, name = "MoonOxygenTank" })
	if not tank then
		return
	end
	for _, p in ipairs(tank:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Massless = true
			p.CanCollide = false
			mk("WeldConstraint", { Part0 = torso, Part1 = p }, p)
			p.Anchored = false
		end
	end
end

local function setOxygen(player, value)
	oxygen[player] = value
	player:SetAttribute("Oxygen", value)
end

local function clearOxygen()
	for player in pairs(oxygen) do
		player:SetAttribute("Oxygen", nil)
		player:SetAttribute("OxygenMax", nil)
		local tank = player.Character and player.Character:FindFirstChild("MoonOxygenTank")
		if tank then
			tank:Destroy()
		end
	end
	oxygen = {}
end

--------------------------------------------------------------------
-- The disaster
--------------------------------------------------------------------
function Moon.run()
	if running then
		return
	end
	running = true
	local folder = mk("Folder", { Name = "MoonCollision" }, workspace)
	local ok, err = pcall(function()
		local lo, hi, island, ground = islandBounds()
		if not lo then
			warn("[MoonCollision] IslandMap.Ground not found")
			return
		end
		local center = (lo + hi) / 2
		local span = math.max(hi.X - lo.X, hi.Z - lo.Z)
		local inArea = function(pos)
			local flat = (pos - center) * Vector3.new(1, 0, 1)
			return flat.Magnitude < span * 0.8 + 80 and pos.Y < hi.Y + 250
		end

		-- where the moon comes from / lands (in the sea next to the island so the island survives)
		local a = math.random() * math.pi * 2
		local side = Vector3.new(math.cos(a), 0, math.sin(a))
		local impact = Vector3.new(center.X, lo.Y, center.Z) + side * (span * 0.5 + 520)
		local fromDir = (side * 0.55 + Vector3.new(0, 1, 0)).Unit -- moon comes down at a steep angle

		-- bunkers: on both sides across the impact line, doors facing the island centre
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { ground }
		local across = side:Cross(Vector3.yAxis)
		local bunkers, spots = {}, {}
		for i = 1, BUNKER_COUNT do
			local s = (i % 2 == 0) and 1 or -1
			for _, reach in ipairs({ 0.24, 0.16, 0.08, 0 }) do
				local xz = center + across * s * span * reach - side * span * 0.05
				local hit = workspace:Raycast(Vector3.new(xz.X, hi.Y + 80, xz.Z), Vector3.new(0, -(hi.Y - lo.Y) - 200, 0), params)
				if hit then
					local face = (center - hit.Position) * Vector3.new(1, 0, 1)
					face = face.Magnitude > 1 and face.Unit or -across * s
					table.insert(bunkers, buildBunker(folder, hit.Position, face))
					table.insert(spots, hit.Position)
					break
				end
			end
		end

		local t0 = workspace:GetServerTimeNow()
		local travel = START_DISTANCE / MOON_SPEED
		remote:FireAllClients("Approach", {
			t0 = t0,
			distance = START_DISTANCE,
			speed = MOON_SPEED,
			impact = impact,
			fromDir = fromDir,
			bunkers = spots,
			center = center,
			span = span,
		})

		task.wait(travel - DOORS_CLOSE_BEFORE)
		remote:FireAllClients("DoorsClosing")
		slideDoors(bunkers, 0, 1.6)
		task.wait(DOORS_CLOSE_BEFORE)

		-- IMPACT
		local survivors = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 and inArea(root.Position) then
				if insideBunker(bunkers, root.Position) then
					table.insert(survivors, player)
				else
					humanoid.Health = 0
					root.AssemblyLinearVelocity = (root.Position - impact).Unit * 180 + Vector3.new(0, 120, 0)
				end
			end
		end
		barren(island, ground)
		local endsAt = workspace:GetServerTimeNow() + AFTERMATH
		remote:FireAllClients("Impact", { impact = impact, endsAt = endsAt, center = center, span = span })
		task.delay(3.5, slideDoors, bunkers, 1, 2)

		-- oxygen tanks for everyone who made it
		for _, player in ipairs(survivors) do
			player:SetAttribute("OxygenMax", TANK_SECONDS)
			setOxygen(player, TANK_SECONDS)
			if player.Character then
				attachTank(player.Character)
			end
		end

		-- harvestable palm trees
		for _, tree in ipairs(palmTrees(island)) do
			local top, topY = nil, -math.huge
			for _, p in ipairs(tree:GetDescendants()) do
				if p:IsA("BasePart") and p.Name == "Trunk" and p.Position.Y > topY then
					top, topY = p, p.Position.Y
				end
			end
			if top then
				local bottom = tree:FindFirstChild("Trunk") or top
				local prompt = mk("ProximityPrompt", {
					Name = "MoonHarvest",
					ActionText = "Harvest Oxygen",
					ObjectText = ("Palm Tree  (+%d s O2)"):format(TREE_OXYGEN),
					HoldDuration = 0.6,
					MaxActivationDistance = 14,
					RequiresLineOfSight = false,
				}, bottom)
				prompt.Triggered:Connect(function(player)
					local left = oxygen[player]
					if not left or not prompt.Enabled then
						return
					end
					if left >= TANK_SECONDS - 0.05 then
						remote:FireClient(player, "Full")
						return
					end
					prompt.Enabled = false
					setOxygen(player, math.min(TANK_SECONDS, left + TREE_OXYGEN))
					stripTree(tree)
					remote:FireAllClients("Harvest", { pos = top.Position, userId = player.UserId })
				end)
				table.insert(undo, { inst = prompt, destroy = true })
			end
		end

		-- breathe
		local last = os.clock()
		while workspace:GetServerTimeNow() < endsAt do
			RunService.Heartbeat:Wait()
			local now = os.clock()
			local dt = now - last
			last = now
			for player, left in pairs(oxygen) do
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if not player.Parent or not humanoid or humanoid.Health <= 0 then
					oxygen[player] = nil
					player:SetAttribute("Oxygen", nil)
				else
					left -= dt
					if left <= 0 then
						oxygen[player] = nil
						player:SetAttribute("Oxygen", 0)
						humanoid.Health = 0
					else
						oxygen[player] = left
						if math.floor(left * 10) ~= math.floor((left + dt) * 10) then
							player:SetAttribute("Oxygen", left)
						end
					end
				end
			end
		end
	end)
	if not ok then
		warn("[MoonCollision] " .. tostring(err))
	end
	-- clean up whatever happened
	remote:FireAllClients("End")
	clearOxygen()
	for _, u in ipairs(undo) do
		if u.destroy and u.inst.Parent then
			u.inst:Destroy()
		end
	end
	restoreWorld()
	folder:Destroy()
	running = false
end

function Moon.init(kit)
	Kit = kit
	remote = ReplicatedStorage:FindFirstChild("MoonCollisionFX") or mk("RemoteEvent", { Name = "MoonCollisionFX" }, ReplicatedStorage)
	local extra = ServerStorage:FindFirstChild("ExtraDisasters") or mk("Folder", { Name = "ExtraDisasters" }, ServerStorage)
	local fn = extra:FindFirstChild("MoonCollision") or mk("BindableFunction", { Name = "MoonCollision" }, extra)
	fn.OnInvoke = function()
		Moon.run()
		return true
	end
	Players.PlayerRemoving:Connect(function(player)
		oxygen[player] = nil
	end)
end

return Moon
