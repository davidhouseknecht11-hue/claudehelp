-- KitAnimator  (Script with RunContext = Client, child of the LobbyUpgrade script)
--
-- LobbyUpgrade moves this into ReplicatedStorage when the game starts, so it runs on every
-- player's device. It plays all the kit animations locally (smooth, and free for the server):
--   * pieces with a KitAnim attribute spin / bob around their prop
--   * props with a KitMotion attribute float (bob), circle the lobby (orbit) or ride on a
--     lobby coin (follow)
--   * jump pads launch the local player

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local entries = {} -- [model] = entry

local function parseAnim(text)
	local spin, bob = 0, 0
	for token in string.gmatch(text, "[^_]+") do
		local n = tonumber(string.match(token, "^spin(-?[%d%.]+)$"))
		if n then
			spin = n
		end
		n = tonumber(string.match(token, "^bob(-?[%d%.]+)$"))
		if n then
			bob = n
		end
	end
	return math.rad(spin), bob
end

local function addPiece(entry, part)
	if not part:IsA("BasePart") or part.Name == "KitRoot" then
		return
	end
	local rel = part:GetAttribute("KitRel")
	if typeof(rel) ~= "CFrame" then
		return
	end
	local spin, bob = parseAnim(part:GetAttribute("KitAnim") or "")
	table.insert(entry.pieces, { part = part, rel = rel, spin = spin, bob = bob })
end

local function register(model)
	if entries[model] or not model:IsA("Model") then
		return
	end
	local entry = {
		pieces = {},
		motion = model:GetAttribute("KitMotion"),
		base = model:GetAttribute("KitBase"),
		phase = model:GetAttribute("KitPhase") or 0,
		speed = model:GetAttribute("KitSpeed") or 1,
		amp = model:GetAttribute("KitAmp") or 0,
		center = model:GetAttribute("KitCenter"),
		radius = model:GetAttribute("KitRadius") or 0,
		noCull = model:GetAttribute("KitNoCull") == true,
	}
	entries[model] = entry
	for _, child in ipairs(model:GetChildren()) do
		addPiece(entry, child)
	end
	entry.added = model.ChildAdded:Connect(function(child)
		task.defer(addPiece, entry, child)
	end)
end

local function unregister(model)
	local entry = entries[model]
	if entry then
		entry.added:Disconnect()
		entries[model] = nil
	end
end

CollectionService:GetInstanceAddedSignal("KitModel"):Connect(register)
CollectionService:GetInstanceRemovedSignal("KitModel"):Connect(unregister)
for _, model in ipairs(CollectionService:GetTagged("KitModel")) do
	register(model)
end

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local t = os.clock()
	local parts, cframes, n = {}, {}, 0

	for model, e in pairs(entries) do
		local root = e.root
		if not root or root.Parent ~= model then
			root = model:FindFirstChild("KitRoot")
			e.root = root
		end
		if root then
			local rootCF = root.CFrame
			local hidden = nil
			if e.motion == "bob" and e.base then
				rootCF = e.base * CFrame.new(0, math.sin(t * e.speed + e.phase) * e.amp, 0)
			elseif e.motion == "orbit" and e.center then
				local a = e.phase + t * math.rad(e.speed)
				local pos = e.center + Vector3.new(math.cos(a) * e.radius, math.sin(t * 0.6 + e.phase) * e.amp, math.sin(a) * e.radius)
				rootCF = CFrame.new(pos) * CFrame.Angles(0, -a, 0)
			elseif e.motion == "follow" then
				local holder = model:FindFirstChild("KitTarget")
				local target = holder and holder.Value
				if target and target.Parent then
					rootCF = CFrame.new(target.Position)
					hidden = target.Transparency > 0.9
					target.LocalTransparencyModifier = 1 -- the kit coin replaces the plain one on screen
				else
					hidden = true
				end
			end

			if e.noCull or (rootCF.Position - camPos).Magnitude < 700 then
				local bobT = math.sin(t * 1.6 + e.phase)
				for _, p in ipairs(e.pieces) do
					local part = p.part
					if part.Parent then
						local cf = rootCF
						if p.spin ~= 0 or p.bob ~= 0 then
							cf = cf * CFrame.new(0, bobT * p.bob, 0) * CFrame.Angles(0, t * p.spin, 0)
						end
						n += 1
						parts[n] = part
						cframes[n] = cf * p.rel
						if hidden ~= nil then
							part.LocalTransparencyModifier = hidden and 1 or 0
						end
					end
				end
			end
		end
	end

	if n > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

--------------------------------------------------------------------
-- Jump pads
--------------------------------------------------------------------
local lastBounce = 0
local boing = Instance.new("Sound")
boing.SoundId = "rbxasset://sounds/electronicpingshort.wav"
boing.Volume = 0.7
boing.PlaybackSpeed = 0.55
boing.Parent = SoundService

local function hookPad(pad)
	if not pad:IsA("BasePart") then
		return
	end
	pad.Touched:Connect(function(hit)
		local character = player.Character
		if not character or not hit:IsDescendantOf(character) then
			return
		end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not hrp or not humanoid or humanoid.Health <= 0 then
			return
		end
		local now = os.clock()
		if now - lastBounce < 0.6 then
			return
		end
		lastBounce = now
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		local v = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, pad:GetAttribute("Power") or 95, v.Z)
		SoundService:PlayLocalSound(boing)
	end)
end

CollectionService:GetInstanceAddedSignal("KitJumpPad"):Connect(hookPad)
for _, pad in ipairs(CollectionService:GetTagged("KitJumpPad")) do
	hookPad(pad)
end
