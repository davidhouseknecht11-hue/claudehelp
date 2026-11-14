-- DisasterFX  (Script with RunContext = Client, child of the LobbyUpgrade script)
--
-- LobbyUpgrade moves this into ReplicatedStorage when the game starts, so it runs on every
-- player's device. Everything here is visual/audio on that player's screen; damage, hit-boxes
-- and timings stay exactly as DisasterGameManager runs them. For every disaster:
--   * intro: the disaster's name slams onto the screen in big red letters
--   * extreme wind: flying Blender debris + wind streaks around the camera, gusting wind roar,
--     GlobalWind for grass/particles, and a push on your own character while on the island
--   * weather (rain / acid / snow / ash / embers / dust), colour grading, lightning flashes, rumble
--   * new Blender looks for the hazards: meteors, ice shards, acid drops, lava blobs + pools,
--     quake rings, lightning bolts, the shark and the tsunami wave (the old block looks are hidden
--     on this screen only). The tornado's new funnel is set up on the server by LobbyUpgrade.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

--------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------
local SHOW_INTRO = true
local REPLACE_HAZARD_LOOKS = true
local WIND_PUSH = 0.3          -- 0 = wind is visual only. Push = wind speed x this, in studs/s per second
local DEBRIS_COUNT = 30        -- flying Blender debris pieces around the camera
local STREAK_COUNT = 14        -- wind streaks around the camera
local TITLE_COLOR = Color3.fromRGB(235, 28, 28)

local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local WHITE = Color3.new(1, 1, 1)

-- Per base disaster. Mythic combos merge the profiles of their parts.
--   wind = studs/s, weather = list of weather kinds, shake = constant camera shake,
--   debris = Blender props blown around, flashes = lightning flashes, crackle = fire crackle loop
local C3 = Color3.fromRGB
local PROFILES = {
	MeteorShower = { wind = 40, weather = { "ash", "embers" }, tint = C3(255, 150, 100), shake = 0.25, debris = { "FxRock", "FxMeteorChunk" }, crackle = true },
	RisingFlood = { wind = 55, weather = { "rain" }, tint = C3(150, 195, 255), shake = 0.15, debris = { "FxLeaf", "FxDroplet" }, flashes = true },
	LightningStorm = { wind = 65, weather = { "rain" }, tint = C3(165, 165, 230), shake = 0.15, debris = { "FxLeaf", "FxPlank" }, flashes = true },
	Tsunami = { wind = 70, weather = { "rain" }, tint = C3(140, 200, 255), shake = 0.3, debris = { "FxDroplet", "FxLeaf" } },
	DragonAttack = { wind = 35, weather = { "embers", "ash" }, tint = C3(255, 150, 90), shake = 0.25, debris = { "FxRock" }, crackle = true },
	Tornado = { wind = 100, weather = { "rain", "dust" }, tint = C3(170, 185, 160), shake = 0.35, debris = { "FxPlank", "FxLeaf", "FxRock" }, flashes = true },
	VolcanicEruption = { wind = 35, weather = { "ash", "embers" }, tint = C3(255, 120, 80), shake = 0.35, debris = { "FxMeteorChunk", "FxRock" }, crackle = true },
	Earthquake = { wind = 30, weather = { "dust" }, tint = C3(225, 195, 150), shake = 0.6, debris = { "FxRock" } },
	AcidRain = { wind = 45, weather = { "acid" }, tint = C3(170, 255, 140), shake = 0.1, debris = { "FxLeaf" } },
	SharkAttack = { wind = 45, weather = { "rain" }, tint = C3(140, 220, 210), shake = 0.1, debris = { "FxDroplet" } },
	MoonCollision = { wind = 55, weather = { "dust", "embers" }, tint = C3(255, 170, 130), shake = 0.2, debris = { "FxRock", "FxMeteorChunk" } },
	Blizzard = { wind = 85, weather = { "snow" }, tint = C3(200, 230, 255), shake = 0.15, debris = { "FxIceShard" } },
}

--------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local assets = ReplicatedStorage:WaitForChild("DisasterAssets")
local remotes = assets:WaitForChild("Remotes")
local Config = require(assets:WaitForChild("DisasterConfig"))
local soundsFolder = assets:FindFirstChild("Sounds")
local props = ReplicatedStorage:WaitForChild("LobbyKitProps", 30) -- Blender templates (nil without the kit)

local fxFolder = Instance.new("Folder")
fxFolder.Name = "DisasterFXLocal"
fxFolder.Parent = workspace

local rng = Random.new()

local function mk(class, p, parent)
	local inst = Instance.new(class)
	for k, v in pairs(p) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function ns(...)
	local a, pts = { ... }, {}
	for i = 1, #a, 2 do
		table.insert(pts, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(pts)
end

local function ghost(cf, size)
	return mk("Part", {
		Size = size or Vector3.new(1, 1, 1),
		CFrame = cf,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Transparency = 1,
	}, fxFolder)
end

local function emitter(parent, p)
	local base = { LightInfluence = 0, Rate = 0 }
	for k, v in pairs(p) do
		base[k] = v
	end
	return mk("ParticleEmitter", base, parent)
end

local function cloneProp(name, scale, tint)
	local t = props and props:FindFirstChild(name)
	if not t then
		return nil
	end
	local m = t:Clone()
	if scale and math.abs(scale - 1) > 0.01 then
		m:ScaleTo(scale)
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CastShadow = false
			if tint and d.Material == Enum.Material.Neon then
				d.Color = tint
			end
		end
	end
	m.Parent = fxFolder
	return m
end

local function setModelFade(model, alpha)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = alpha
		end
	end
end

-- sounds come from the game's own DisasterAssets > Sounds (so every id is one the game already uses)
local function sound(name, p, parent)
	local t = soundsFolder and soundsFolder:FindFirstChild(name)
	if not t or not t:IsA("Sound") then
		return nil
	end
	local s = t:Clone()
	s.Looped = false
	for k, v in pairs(p or {}) do
		s[k] = v
	end
	s.Parent = parent or SoundService
	return s
end

local function oneShot(name, volume, speed, position)
	local holder = position and ghost(CFrame.new(position)) or nil
	local s = sound(name, { Volume = volume, PlaybackSpeed = speed, RollOffMaxDistance = 600 }, holder)
	if s then
		s:Play()
		Debris:AddItem(holder or s, 10)
	elseif holder then
		holder:Destroy()
	end
end

--------------------------------------------------------------------
-- Camera shake (constant level + short kicks)
--------------------------------------------------------------------
local shakeBase = 0
local kicks = {}
local function kick(amp, duration)
	table.insert(kicks, { amp = amp, t = os.clock(), dur = duration })
end

RunService:BindToRenderStep("DisasterFXShake", Enum.RenderPriority.Camera.Value + 1, function()
	if camera.CameraType ~= Enum.CameraType.Custom then
		return -- a scripted camera does not reset every frame, so the offsets would add up
	end
	local now = os.clock()
	local amp = shakeBase
	for i = #kicks, 1, -1 do
		local k = kicks[i]
		local a = (now - k.t) / k.dur
		if a >= 1 then
			table.remove(kicks, i)
		else
			amp += k.amp * (1 - a) ^ 2
		end
	end
	if amp > 0.001 then
		local t = now * 26
		camera.CFrame *= CFrame.Angles(math.noise(t, 0.3) * amp * 0.035, math.noise(0.7, t) * amp * 0.035, math.noise(t, t * 0.5) * amp * 0.02)
	end
end)

--------------------------------------------------------------------
-- Intro card: the name in big red letters
--------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
local introGui = mk("ScreenGui", { Name = "DisasterIntro", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, Enabled = false }, playerGui)
local flash = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(255, 40, 40), BackgroundTransparency = 1, BorderSizePixel = 0 }, introGui)
local barTop = mk("Frame", { Size = UDim2.fromScale(1, 0), BackgroundColor3 = C3(0, 0, 0), BorderSizePixel = 0 }, introGui)
local barBottom = mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = C3(0, 0, 0), BorderSizePixel = 0 }, introGui)
local title = mk("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.fromScale(0.92, 0.22),
	BackgroundTransparency = 1,
	Font = Enum.Font.LuckiestGuy,
	TextScaled = true,
	TextColor3 = TITLE_COLOR,
	Text = "",
}, introGui)
mk("UITextSizeConstraint", { MaxTextSize = 150 }, title)
local titleStroke = mk("UIStroke", { Color = C3(20, 0, 0), Thickness = 6, LineJoinMode = Enum.LineJoinMode.Round }, title)
mk("UIGradient", { Rotation = 90, Color = ColorSequence.new(C3(255, 255, 255), C3(160, 150, 150)) }, title)
local titleScale = mk("UIScale", { Scale = 1 }, title)
local subtitle = mk("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.54),
	Size = UDim2.fromScale(0.7, 0.06),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = WHITE,
	Text = "",
}, introGui)
local subStroke = mk("UIStroke", { Color = C3(0, 0, 0), Thickness = 3 }, subtitle)

local introToken = 0
local function tween(obj, t, goal, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function playIntro(def)
	introToken += 1
	local token = introToken
	local rarity = Config.Rarities and Config.Rarities[def.Rarity or "Common"]
	title.Text = string.upper(def.Name)
	subtitle.Text = ("⚠  %s DISASTER  ⚠"):format(string.upper(def.Rarity or "Common"))
	subtitle.TextColor3 = rarity and rarity.Color or WHITE
	titleScale.Scale = 4
	title.Rotation = -10
	title.TextTransparency = 1
	titleStroke.Transparency = 1
	subtitle.TextTransparency = 1
	subStroke.Transparency = 1
	introGui.Enabled = true

	tween(barTop, 0.25, { Size = UDim2.fromScale(1, 0.11) })
	tween(barBottom, 0.25, { Size = UDim2.fromScale(1, 0.11) })
	oneShot("Whoosh", 0.9, 0.7)
	tween(titleScale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(title, 0.32, { Rotation = 0, TextTransparency = 0 }, Enum.EasingStyle.Back)
	tween(titleStroke, 0.2, { Transparency = 0 })

	task.delay(0.3, function()
		if token ~= introToken then
			return
		end
		-- the slam
		flash.BackgroundTransparency = 0.35
		tween(flash, 0.5, { BackgroundTransparency = 1 })
		oneShot("Explosion", 1, 0.75)
		oneShot("Thunder", 0.8, 0.6)
		kick(1.6, 0.6)
		for i = 1, 6 do -- quick rattle of the letters
			title.Position = UDim2.new(0.5, rng:NextInteger(-9, 9), 0.42, rng:NextInteger(-6, 6))
			task.wait(0.035)
		end
		title.Position = UDim2.fromScale(0.5, 0.42)
		tween(subtitle, 0.3, { TextTransparency = 0 })
		tween(subStroke, 0.3, { Transparency = 0 })
		tween(titleScale, 0.8, { Scale = 1.06 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end)

	task.delay(2.4, function()
		if token ~= introToken then
			return
		end
		tween(titleScale, 0.35, { Scale = 1.35 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(title, 0.35, { TextTransparency = 1 })
		tween(titleStroke, 0.3, { Transparency = 1 })
		tween(subtitle, 0.3, { TextTransparency = 1 })
		tween(subStroke, 0.3, { Transparency = 1 })
		tween(barTop, 0.35, { Size = UDim2.fromScale(1, 0) })
		tween(barBottom, 0.35, { Size = UDim2.fromScale(1, 0) }).Completed:Wait()
		if token == introToken then
			introGui.Enabled = false
		end
	end)
end

--------------------------------------------------------------------
-- Impacts (used by the hazard looks)
--------------------------------------------------------------------
local function impact(pos, color, chunkName, big)
	local dist = (camera.CFrame.Position - pos).Magnitude
	kick(math.clamp(1 - dist / 170, 0, 1) * (big and 1.6 or 0.8), 0.45)

	local holder = ghost(CFrame.new(pos), Vector3.new(4, 1, 4))
	emitter(holder, {
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(C3(110, 95, 85)),
		Size = ns(0, 4, 1, big and 18 or 10),
		Transparency = ns(0, 0.3, 1, 1),
		Lifetime = NumberRange.new(1, 2.2),
		Speed = NumberRange.new(10, big and 30 or 18),
		SpreadAngle = Vector2.new(80, 80),
		EmissionDirection = Enum.NormalId.Top,
		Drag = 2.5,
	}):Emit(big and 30 or 14)
	emitter(holder, {
		Texture = TEX_SPARK,
		Color = ColorSequence.new(color, WHITE),
		LightEmission = 1,
		Size = ns(0, 1.2, 1, 0),
		Lifetime = NumberRange.new(0.5, 1.1),
		Speed = NumberRange.new(25, 55),
		SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -60, 0),
	}):Emit(big and 50 or 20)
	local light = mk("PointLight", { Color = color, Range = big and 45 or 25, Brightness = 6 }, holder)
	tween(light, 0.7, { Brightness = 0 })
	Debris:AddItem(holder, 3)

	-- expanding shock ring
	local ring = cloneProp("FxShockRing", 0.3, color)
	if ring then
		local base = CFrame.new(pos + Vector3.new(0, 0.6, 0))
		local grow = big and 3.2 or 1.6
		task.spawn(function()
			local t0 = os.clock()
			while ring.Parent do
				local a = math.min((os.clock() - t0) / 0.55, 1)
				ring:ScaleTo(0.3 + (grow - 0.3) * (1 - (1 - a) ^ 3))
				ring:PivotTo(base)
				setModelFade(ring, a)
				if a >= 1 then
					break
				end
				RunService.RenderStepped:Wait()
			end
			ring:Destroy()
		end)
	end

	-- Blender chunks flung out
	if chunkName then
		for _ = 1, big and 7 or 4 do
			local chunk = cloneProp(chunkName, rng:NextNumber(0.6, 1.2))
			if chunk then
				local vel = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.8, 1.6), rng:NextNumber(-1, 1)) * (big and 38 or 24)
				local spin = CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.3, 0.3))
				task.spawn(function()
					local p, rot, t0 = pos, CFrame.new(), os.clock()
					while chunk.Parent and os.clock() - t0 < 1.4 do
						local dt = RunService.RenderStepped:Wait()
						vel += Vector3.new(0, -110, 0) * dt
						p += vel * dt
						rot *= spin
						chunk:PivotTo(CFrame.new(p) * rot)
						setModelFade(chunk, math.max(0, (os.clock() - t0 - 0.9) / 0.5))
					end
					chunk:Destroy()
				end)
			end
		end
	end
end

--------------------------------------------------------------------
-- New hazard looks (follow the real hazard, hide its old look on this screen)
--------------------------------------------------------------------
local swaps = {} -- [hazard] = { model, host, pose(hostCF, t), fade = bool, onGone(lastCF), extra = {models} }

local function hideLook(inst)
	if inst:IsA("BasePart") then
		inst.LocalTransparencyModifier = 1
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		end
	end
end

local function track(hazard, entry)
	entry.lastCF = entry.host.CFrame
	entry.born = os.clock()
	swaps[hazard] = entry
end

local function yawSpin(speed, phase)
	return function(cf, t)
		return CFrame.new(cf.Position) * CFrame.Angles(0, t * speed + phase, 0)
	end
end

local LOOKS = {}

LOOKS.Meteor = function(part)
	local model = cloneProp("MeteorRock", part.Size.X / 8)
	if not model then
		return
	end
	hideLook(part)
	local rock = model:FindFirstChild("rock")
	if rock then
		emitter(rock, {
			Texture = TEX_FIRE,
			Color = ColorSequence.new(C3(255, 200, 80), C3(255, 70, 20)),
			LightEmission = 1,
			Size = ns(0, 7, 1, 0),
			Transparency = ns(0, 0.1, 1, 1),
			Lifetime = NumberRange.new(0.4, 0.7),
			Speed = NumberRange.new(12, 24),
			EmissionDirection = Enum.NormalId.Top,
			Rate = 70,
		})
	end
	track(part, {
		model = model,
		host = part,
		pose = yawSpin(4, rng:NextNumber(0, 6)),
		onGone = function(cf)
			impact(cf.Position, C3(255, 140, 40), "FxMeteorChunk", true)
			oneShot("Explosion", 0.8, 0.55, cf.Position)
		end,
	})
end

LOOKS.IceShard = function(part)
	local model = cloneProp("IceCrystal", 1.5)
	if not model then
		return
	end
	hideLook(part)
	track(part, {
		model = model,
		host = part,
		pose = yawSpin(3, rng:NextNumber(0, 6)),
		onGone = function(cf)
			impact(cf.Position, C3(170, 225, 255), "FxIceShard", false)
		end,
	})
end

LOOKS.AcidDrop = function(part)
	local model = cloneProp("AcidBlob", part.Size.X / 2.5)
	if not model then
		return
	end
	hideLook(part)
	track(part, {
		model = model,
		host = part,
		pose = yawSpin(2, 0),
		onGone = function(cf)
			impact(cf.Position, C3(140, 255, 60), nil, false)
		end,
	})
end

local function lavaCube(part)
	local model = cloneProp("LavaBlob", part.Size.X / 5)
	if not model then
		return
	end
	hideLook(part)
	local spin = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
	track(part, {
		model = model,
		host = part,
		fade = true,
		pose = function(cf, t)
			return CFrame.new(cf.Position) * spin * CFrame.Angles(t * 3, t * 2, 0)
		end,
	})
end

LOOKS.LavaPool = function(part)
	local model = cloneProp("LavaPool", part.Size.X / 18)
	if not model then
		return
	end
	hideLook(part)
	local lava = model:FindFirstChild("lava")
	if lava then
		emitter(lava, {
			Texture = TEX_SPARK,
			Color = ColorSequence.new(C3(255, 170, 60), C3(255, 60, 20)),
			LightEmission = 1,
			Size = ns(0, 0.6, 1, 0),
			Lifetime = NumberRange.new(1, 2),
			Speed = NumberRange.new(4, 10),
			EmissionDirection = Enum.NormalId.Top,
			Rate = 18,
		})
		mk("PointLight", { Color = C3(255, 120, 40), Range = 22, Brightness = 2 }, lava)
	end
	track(part, {
		model = model,
		host = part,
		fade = true,
		pose = function(cf)
			return CFrame.new(cf.Position)
		end,
	})
end

LOOKS.QuakeRing = function(part)
	if not (props and props:FindFirstChild("QuakeSpike")) then
		return
	end
	hideLook(part)
	local spikes = {}
	for i = 1, 26 do
		local s = cloneProp("QuakeSpike", rng:NextNumber(1.2, 1.9))
		if s then
			table.insert(spikes, { model = s, a = (i / 26) * math.pi * 2, yaw = rng:NextNumber(0, 6), tilt = rng:NextNumber(-0.25, 0.25) })
			if i % 5 == 0 then
				local rockPart = s:FindFirstChild("rock")
				if rockPart then
					emitter(rockPart, {
						Texture = TEX_SMOKE,
						Color = ColorSequence.new(C3(190, 160, 120)),
						Size = ns(0, 3, 1, 8),
						Transparency = ns(0, 0.5, 1, 1),
						Lifetime = NumberRange.new(0.8, 1.6),
						Speed = NumberRange.new(4, 9),
						EmissionDirection = Enum.NormalId.Top,
						Rate = 12,
					})
				end
			end
		end
	end
	track(part, {
		model = nil,
		host = part,
		extra = spikes,
		update = function()
			local r = part.Size.Y / 2
			local base = part.Position - Vector3.new(0, 0.5, 0)
			for _, s in ipairs(spikes) do
				local p = base + Vector3.new(math.cos(s.a) * r, 0, math.sin(s.a) * r)
				s.model:PivotTo(CFrame.new(p) * CFrame.Angles(s.tilt, s.yaw, 0))
			end
		end,
	})
end

LOOKS.LightningBolt = function(model)
	if not (props and props:FindFirstChild("FxBolt")) then
		return
	end
	task.defer(function() -- the segments are parented before the model, but wait one step to be safe
		local top, bottom, first
		for _, seg in ipairs(model:GetChildren()) do
			if seg:IsA("BasePart") then
				first = first or seg
				local hi = seg.Position + Vector3.new(0, seg.Size.Y / 2, 0)
				local lo = seg.Position - Vector3.new(0, seg.Size.Y / 2, 0)
				if not top or hi.Y > top.Y then
					top = hi
				end
				if not bottom or lo.Y < bottom.Y then
					bottom = lo
				end
			end
		end
		if not top then
			return
		end
		hideLook(model)
		local height = math.max(top.Y - bottom.Y, 10)
		local color = C3(255, 245, 170)
		local main = cloneProp("FxBolt", height / 40, color)
		local branches = {}
		for i = 1, 2 do
			local b = cloneProp("FxBolt", height / 40 * rng:NextNumber(0.25, 0.4), C3(170, 220, 255))
			if b then
				table.insert(branches, { model = b, f = rng:NextNumber(0.2, 0.6), cf = CFrame.Angles(rng:NextNumber(-0.7, 0.7), rng:NextNumber(0, 6), rng:NextNumber(0.4, 0.8) * (i == 1 and 1 or -1)) })
			end
		end
		if not main then
			return
		end
		local topCF = CFrame.new(Vector3.new(bottom.X, top.Y, bottom.Z)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
		local mainPart = main:FindFirstChild("bolt")
		if mainPart then
			mk("PointLight", { Color = color, Range = 60, Brightness = 10 }, mainPart)
		end
		impact(bottom, color, "FxRock", false)
		local host = first
		track(model, {
			model = main,
			host = host,
			fade = true,
			extra = branches,
			pose = function()
				return topCF
			end,
			update = function()
				for _, b in ipairs(branches) do
					b.model:PivotTo(topCF * CFrame.new(0, -height * b.f, 0) * b.cf)
					setModelFade(b.model, host.Transparency)
				end
			end,
		})
	end)
end

LOOKS.Shark = function(model)
	task.defer(function()
		local body = model:FindFirstChild("Body")
		local look = body and cloneProp("Shark", 1)
		if not look then
			return
		end
		hideLook(model)
		track(model, {
			model = look,
			host = body,
			pose = function(cf, t)
				return cf * CFrame.Angles(0, math.sin(t * 6) * 0.12, 0) -- tail-wag sway
			end,
		})
	end)
end

LOOKS.TsunamiWave = function(part)
	local look = cloneProp("TsunamiCurl", 1)
	if not look then
		return
	end
	-- stretch only along the wall (X) so the curl keeps the hit-box height
	local sx = part.Size.X / 250
	local pivot = look:GetPivot()
	for _, d in ipairs(look:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d.Size = Vector3.new(d.Size.X * sx, d.Size.Y, d.Size.Z)
			d.CFrame = pivot * (CFrame.new(rel.Position.X * sx, rel.Position.Y, rel.Position.Z) * rel.Rotation)
		end
	end
	local folder = part.Parent
	if folder then
		hideLook(folder)
		local conn = folder.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			end
		end)
		look.Destroying:Once(function()
			conn:Disconnect()
		end)
	end
	local foam = look:FindFirstChild("foam")
	if foam then
		emitter(foam, {
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(C3(235, 248, 255)),
			Size = ns(0, 6, 1, 18),
			Transparency = ns(0, 0.35, 1, 1),
			Lifetime = NumberRange.new(1, 2),
			Speed = NumberRange.new(10, 30),
			SpreadAngle = Vector2.new(40, 40),
			EmissionDirection = Enum.NormalId.Top,
			Rate = 120,
		})
	end
	track(part, {
		model = look,
		host = part,
		pose = function(cf)
			return cf
		end,
	})
end

LOOKS.DisasterFlood = function(part)
	-- keep the water, add mist rolling over its surface
	emitter(part, {
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(C3(220, 240, 255)),
		Size = ns(0, 8, 1, 20),
		Transparency = ns(0, 0.75, 1, 1),
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(2, 6),
		EmissionDirection = Enum.NormalId.Top,
		Rate = 40,
	})
end

local function onHazard(inst)
	if inst:IsDescendantOf(fxFolder) then
		return -- our own Blender copies share names with the hazards (Shark, LavaPool ...)
	end
	local name = inst.Name
	local fn = LOOKS[name]
	if not fn and string.sub(name, 1, 8) == "LavaCube" and inst:IsA("BasePart") then
		fn = lavaCube
	end
	if fn and not swaps[inst] then
		local ok, err = pcall(fn, inst)
		if not ok then
			warn("[DisasterFX] " .. name .. " look failed: " .. tostring(err))
		end
	end
end

local function dropSwap(hazard, entry)
	swaps[hazard] = nil
	if entry.onGone then
		pcall(entry.onGone, entry.lastCF)
	end
	if entry.model then
		entry.model:Destroy()
	end
	for _, e in ipairs(entry.extra or {}) do
		e.model:Destroy()
	end
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for hazard, entry in pairs(swaps) do
		if not hazard.Parent or not entry.host.Parent then
			dropSwap(hazard, entry)
		else
			entry.lastCF = entry.host.CFrame
			if entry.model and entry.pose then
				entry.model:PivotTo(entry.pose(entry.lastCF, now - entry.born))
				if entry.fade then
					setModelFade(entry.model, entry.host.Transparency)
				end
			end
			if entry.update then
				entry.update()
			end
		end
	end
end)

--------------------------------------------------------------------
-- Weather, wind, grading, ambience
--------------------------------------------------------------------
local active = nil -- the running disaster's state

local WEATHER = {
	rain = { Texture = TEX_SPARK, Color = ColorSequence.new(C3(190, 215, 255)), Size = ns(0, 0.22, 1, 0.22), Transparency = ns(0, 0.2, 1, 0.4),
		Lifetime = NumberRange.new(1.1, 1.3), Speed = NumberRange.new(95, 115), Rate = 900, LightEmission = 0.3,
		EmissionDirection = Enum.NormalId.Bottom, Orientation = Enum.ParticleOrientation.VelocityParallel },
	acid = { Texture = TEX_SPARK, Color = ColorSequence.new(C3(150, 255, 70)), Size = ns(0, 0.28, 1, 0.28), Transparency = ns(0, 0.1, 1, 0.3),
		Lifetime = NumberRange.new(1.1, 1.3), Speed = NumberRange.new(85, 105), Rate = 700, LightEmission = 0.8,
		EmissionDirection = Enum.NormalId.Bottom, Orientation = Enum.ParticleOrientation.VelocityParallel },
	snow = { Texture = TEX_SPARK, Color = ColorSequence.new(WHITE), Size = ns(0, 0.5, 1, 0.35), Transparency = ns(0, 0, 1, 0.3),
		Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(14, 22), Rate = 600, RotSpeed = NumberRange.new(-90, 90),
		EmissionDirection = Enum.NormalId.Bottom },
	ash = { Texture = TEX_SMOKE, Color = ColorSequence.new(C3(70, 62, 60)), Size = ns(0, 0.6, 1, 0.3), Transparency = ns(0, 0.2, 1, 0.6),
		Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(6, 12), Rate = 260, RotSpeed = NumberRange.new(-60, 60),
		EmissionDirection = Enum.NormalId.Bottom },
	embers = { Texture = TEX_SPARK, Color = ColorSequence.new(C3(255, 190, 80), C3(255, 70, 20)), Size = ns(0, 0.45, 1, 0), LightEmission = 1,
		Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(4, 10), Rate = 120, EmissionDirection = Enum.NormalId.Bottom },
	dust = { Texture = TEX_SMOKE, Color = ColorSequence.new(C3(200, 170, 130)), Size = ns(0, 6, 1, 14), Transparency = ns(0, 0.75, 0.5, 0.65, 1, 1),
		Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(4, 10), Rate = 30, EmissionDirection = Enum.NormalId.Bottom },
}

local function mergeProfile(def)
	local parts = def.Combo or { def.Id }
	local p = { wind = 0, weather = {}, debris = {}, shake = 0, tint = def.Color or WHITE }
	local seen = {}
	for _, id in ipairs(parts) do
		local base = PROFILES[id]
		if base then
			p.wind = math.max(p.wind, base.wind)
			p.shake = math.max(p.shake, base.shake)
			p.flashes = p.flashes or base.flashes
			p.crackle = p.crackle or base.crackle
			if not def.Combo then
				p.tint = base.tint
			end
			for _, w in ipairs(base.weather) do
				if not seen[w] then
					seen[w] = true
					table.insert(p.weather, w)
				end
			end
			for _, d in ipairs(base.debris) do
				table.insert(p.debris, d)
			end
		end
	end
	if def.Combo then
		p.wind += 15 -- mythic combos blow harder
		p.shake += 0.1
	end
	if p.wind == 0 then
		p.wind, p.weather, p.debris, p.shake = 45, { "dust" }, { "FxLeaf", "FxRock" }, 0.2
	end
	return p
end

local function lobbyCenter()
	local lobby = workspace:FindFirstChild("Lobby")
	local origin = lobby and lobby:GetAttribute("Origin")
	return typeof(origin) == "Vector3" and origin or nil
end

local function stopDisaster()
	local s = active
	active = nil
	if not s then
		return
	end
	s.alive = false
	shakeBase = 0
	workspace.GlobalWind = s.oldWind
	for _, c in ipairs(s.conns) do
		c:Disconnect()
	end
	for _, snd in ipairs(s.loops) do
		tween(snd, 2, { Volume = 0 })
		Debris:AddItem(snd, 2.2)
	end
	for _, e in ipairs(s.emitters) do
		e.Enabled = false
	end
	Debris:AddItem(s.weatherPart, 7)
	for _, d in ipairs(s.debris) do
		d.model:Destroy()
	end
	if s.cc then
		local cc = s.cc
		tween(cc, 2, { TintColor = WHITE, Saturation = 0, Contrast = 0, Brightness = 0 })
		Debris:AddItem(cc, 2.2)
	end
end

local function startDisaster(def)
	stopDisaster()
	local p = mergeProfile(def)
	local s = {
		alive = true,
		profile = p,
		conns = {},
		loops = {},
		emitters = {},
		debris = {},
		oldWind = workspace.GlobalWind,
		angle = rng:NextNumber(0, math.pi * 2),
		dir = Vector3.new(1, 0, 0),
		speed = 0,
	}
	active = s
	shakeBase = p.shake * 0.35

	-- colour grading
	s.cc = mk("ColorCorrectionEffect", { Name = "DisasterFX" }, Lighting)
	tween(s.cc, 1.5, { TintColor = p.tint:Lerp(WHITE, 0.55), Saturation = -0.12, Contrast = 0.14 })

	-- weather around the camera
	s.weatherPart = ghost(CFrame.new(camera.CFrame.Position), Vector3.new(150, 1, 150))
	for _, kind in ipairs(p.weather) do
		local spec = WEATHER[kind]
		if spec then
			table.insert(s.emitters, emitter(s.weatherPart, spec))
		end
	end

	-- ambience: wind roar, low rumble, fire crackle
	local wind = sound("Whoosh", { Looped = true, Volume = 0, PlaybackSpeed = 0.42 })
	local rumble = sound("Thunder", { Looped = true, Volume = 0, PlaybackSpeed = 0.3 })
	local crackle = p.crackle and sound("DragonFire", { Looped = true, Volume = 0, PlaybackSpeed = 0.55 }) or nil
	for _, snd in ipairs({ wind, rumble, crackle }) do
		if snd then
			snd:Play()
			table.insert(s.loops, snd)
		end
	end
	if rumble then
		tween(rumble, 2, { Volume = math.clamp(p.shake, 0.15, 0.6) })
	end
	if crackle then
		tween(crackle, 2, { Volume = 0.3 })
	end

	-- flying Blender debris + wind streaks
	local kinds = p.debris
	for i = 1, DEBRIS_COUNT + STREAK_COUNT do
		local isStreak = i > DEBRIS_COUNT
		local name = isStreak and "FxWindStreak" or kinds[((i - 1) % math.max(#kinds, 1)) + 1]
		local model = name and cloneProp(name, isStreak and rng:NextNumber(1.2, 2.2) or rng:NextNumber(0.7, 1.4))
		if model then
			table.insert(s.debris, {
				model = model,
				streak = isStreak,
				pos = nil, -- placed on the first frame
				speedK = isStreak and rng:NextNumber(1.3, 1.8) or rng:NextNumber(0.55, 1.05),
				spin = CFrame.Angles(rng:NextNumber(-4, 4), rng:NextNumber(-4, 4), rng:NextNumber(-4, 4)),
				rot = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
				wobble = rng:NextNumber(0, 10),
			})
		end
	end

	local function respawn(d, camPos, fresh)
		local side = s.dir:Cross(Vector3.yAxis)
		local back = fresh and rng:NextNumber(-70, 70) or -75
		d.pos = camPos + s.dir * back + side * rng:NextNumber(-70, 70) + Vector3.new(0, rng:NextNumber(-8, 45), 0)
	end

	-- lightning flashes for the stormy ones
	if p.flashes then
		task.spawn(function()
			while s.alive do
				task.wait(rng:NextNumber(2, 6))
				if not s.alive then
					break
				end
				for _ = 1, rng:NextInteger(1, 2) do
					s.cc.Brightness = 0.45
					task.wait(0.06)
					s.cc.Brightness = 0
					task.wait(0.08)
				end
				task.delay(rng:NextNumber(0.3, 1.2), oneShot, "Thunder", rng:NextNumber(0.4, 0.7), rng:NextNumber(0.8, 1.1))
			end
		end)
	end

	local t0 = os.clock()
	local lastAccel = 0
	table.insert(s.conns, RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		local ramp = math.clamp(t / 2.5, 0, 1)
		-- gusting wind that slowly swings around
		local gust = 0.8 + 0.45 * math.noise(t * 0.35, 1.7)
		s.speed = p.wind * gust * ramp
		local a = s.angle + 0.6 * math.noise(t * 0.08, 4.2)
		s.dir = Vector3.new(math.cos(a), 0, math.sin(a))
		workspace.GlobalWind = s.dir * math.min(s.speed, 80) * 0.6
		if wind then
			wind.Volume = math.clamp(s.speed / 110, 0, 1) * 0.9
			wind.PlaybackSpeed = 0.35 + gust * 0.12
		end
		shakeBase = p.shake * 0.35 * (0.6 + 0.6 * gust) * ramp

		local camPos = camera.CFrame.Position
		s.weatherPart.CFrame = CFrame.new(camPos + Vector3.new(0, 48, 0) - s.dir * s.speed * 0.4)
		if os.clock() - lastAccel > 0.2 then
			lastAccel = os.clock()
			local accel = s.dir * s.speed * 0.7
			for _, e in ipairs(s.emitters) do
				e.Acceleration = accel
			end
		end

		for _, d in ipairs(s.debris) do
			if not d.pos then
				respawn(d, camPos, true)
			end
			local rel = d.pos - camPos
			if rel:Dot(s.dir) > 80 or rel.Magnitude > 120 then
				respawn(d, camPos, false)
			end
			local v = s.dir * s.speed * d.speedK + Vector3.new(0, math.sin(t * 2 + d.wobble) * (d.streak and 1.5 or 5), 0)
			d.pos += v * dt
			if d.streak then
				d.model:PivotTo(CFrame.fromMatrix(d.pos, s.dir, Vector3.yAxis))
			else
				d.rot = d.rot:Lerp(d.rot * d.spin, math.min(dt, 0.1))
				d.model:PivotTo(CFrame.new(d.pos) * d.rot)
			end
		end
	end))

	-- extreme wind pushes your own character (not in the lobby)
	if WIND_PUSH > 0 then
		table.insert(s.conns, RunService.Heartbeat:Connect(function(dt)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or root.Anchored then
				return
			end
			local lobby = lobbyCenter()
			if lobby and (root.Position - lobby).Magnitude < 160 then
				return
			end
			root.AssemblyLinearVelocity += s.dir * s.speed * WIND_PUSH * dt
		end))
	end

	-- new hazard looks
	if REPLACE_HAZARD_LOOKS then
		table.insert(s.conns, workspace.DescendantAdded:Connect(onHazard))
		for _, d in ipairs(workspace:GetDescendants()) do -- anything that spawned before we heard about it
			if LOOKS[d.Name] then
				onHazard(d)
			end
		end
	end
end

--------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------
remotes:WaitForChild("DisasterStarted").OnClientEvent:Connect(function(disasterId)
	local def = Config.GetDisasterById(disasterId)
	if not def then
		return
	end
	if SHOW_INTRO then
		task.spawn(playIntro, def)
	end
	local ok, err = pcall(startDisaster, def)
	if not ok then
		warn("[DisasterFX] start failed: " .. tostring(err))
	end
end)

remotes:WaitForChild("DisasterEnded").OnClientEvent:Connect(function()
	local ok, err = pcall(stopDisaster)
	if not ok then
		warn("[DisasterFX] stop failed: " .. tostring(err))
	end
end)
