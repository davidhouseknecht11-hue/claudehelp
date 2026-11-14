-- MoonFX  (Script with RunContext = Client, child of the LobbyUpgrade script)
--
-- LobbyUpgrade moves this into ReplicatedStorage so it runs on every player's device.
-- Everything you SEE and HEAR of the Moon Collision disaster (the server part is MoonCollision):
--   * top of the screen: countdown + how far away the moon is (studs), big final-10 count, bunker markers
--   * the Blender moon falling, heating up and trailing fire; rumble, roar, sky turning red
--   * impact: white-out, shockwave rings, moon debris raining down, dust wall, steam as the sea boils
--   * airless sky: black space, stars and the Blender solar system (Sun, Earth, Saturn ...)
--   * bottom middle: your oxygen tank (seconds left), suffocation effects, tree-harvest animation

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remote = ReplicatedStorage:WaitForChild("MoonCollisionFX")
local props = ReplicatedStorage:WaitForChild("LobbyKitProps", 30)
local assets = ReplicatedStorage:WaitForChild("DisasterAssets")
local soundsFolder = assets:FindFirstChild("Sounds")

local MOON_SCALE = 9          -- Blender moon radius 100 -> 900 studs
local VISUAL_SQUASH = 0.08    -- 100,000 real studs are drawn 8,000 studs away (beyond that Roblox won't draw it)
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TICK_SOUND = "rbxasset://sounds/volume_slider.ogg"
local BOOM_SOUND = "rbxasset://sounds/impact_explosion_03.mp3"
local C3 = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)

--------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------
local fx = Instance.new("Folder")
fx.Name = "MoonFXLocal"
fx.Parent = workspace

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
	return mk("Part", { Size = size or Vector3.one, CFrame = cf, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false, Transparency = 1 }, fx)
end
local function emitter(parent, p)
	local base = { LightInfluence = 0, Rate = 0 }
	for k, v in pairs(p) do
		base[k] = v
	end
	return mk("ParticleEmitter", base, parent)
end
local function tween(obj, t, goal, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end
local function prop(name, scale, tint)
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
	m.Parent = fx
	return m
end
local function sound(name, volume, speed, parent, looped)
	local s
	if string.find(name, "://", 1, true) then
		s = mk("Sound", { SoundId = name }, nil)
	else
		local t = soundsFolder and soundsFolder:FindFirstChild(name)
		if not t then
			return nil
		end
		s = t:Clone()
	end
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.Looped = looped == true
	s.RollOffMaxDistance = 10000
	s.Parent = parent or SoundService
	s:Play()
	if not looped then
		Debris:AddItem(s, 15)
	end
	return s
end
local function fmt(n)
	local s = tostring(math.floor(n))
	while true do
		local k
		s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			return s
		end
	end
end

--------------------------------------------------------------------
-- camera shake
--------------------------------------------------------------------
local shakeBase, kicks = 0, {}
local function kick(amp, dur)
	table.insert(kicks, { amp = amp, t = os.clock(), dur = dur })
end
RunService:BindToRenderStep("MoonFXShake", Enum.RenderPriority.Camera.Value + 2, function()
	if camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local now, amp = os.clock(), shakeBase
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
		local t = now * 24
		camera.CFrame *= CFrame.Angles(math.noise(t, 1.3) * amp * 0.04, math.noise(2.1, t) * amp * 0.04, math.noise(t, t) * amp * 0.025)
	end
end)

--------------------------------------------------------------------
-- UI
--------------------------------------------------------------------
local gui = mk("ScreenGui", { Name = "MoonCollisionUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, Enabled = false }, player:WaitForChild("PlayerGui"))
local whiteout = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 50 }, gui)
local redPulse = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(255, 20, 20), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, gui)

local function label(parent, p)
	local base = { BackgroundTransparency = 1, Font = Enum.Font.LuckiestGuy, TextScaled = true, TextColor3 = WHITE }
	for k, v in pairs(p) do
		base[k] = v
	end
	local l = mk("TextLabel", base, parent)
	mk("UIStroke", { Color = C3(0, 0, 0), Thickness = 3 }, l)
	return l
end

-- top: countdown panel
local top = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(520, 128), BackgroundColor3 = C3(20, 10, 18), BackgroundTransparency = 0.2, ZIndex = 10 }, gui)
mk("UICorner", { CornerRadius = UDim.new(0, 16) }, top)
local topStroke = mk("UIStroke", { Color = C3(255, 60, 40), Thickness = 4 }, top)
mk("UISizeConstraint", { MaxSize = Vector2.new(520, 128) }, top)
local topTitle = label(top, { ZIndex = 11, Text = "🌕 MOON COLLISION", TextColor3 = C3(255, 90, 60), Position = UDim2.new(0.04, 0, 0.05, 0), Size = UDim2.new(0.92, 0, 0.24, 0) })
local topTimer = label(top, { ZIndex = 11, Text = "00.0", Position = UDim2.new(0.04, 0, 0.3, 0), Size = UDim2.new(0.44, 0, 0.36, 0), TextXAlignment = Enum.TextXAlignment.Left })
local topDist = label(top, { ZIndex = 11, Text = "0 studs", TextColor3 = C3(255, 220, 120), Position = UDim2.new(0.5, 0, 0.32, 0), Size = UDim2.new(0.46, 0, 0.3, 0), TextXAlignment = Enum.TextXAlignment.Right })
local barBack = mk("Frame", { ZIndex = 11, Position = UDim2.new(0.04, 0, 0.7, 0), Size = UDim2.new(0.92, 0, 0.1, 0), BackgroundColor3 = C3(60, 40, 50) }, top)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, barBack)
local barFill = mk("Frame", { ZIndex = 12, Size = UDim2.fromScale(0, 1), BackgroundColor3 = C3(255, 70, 40) }, barBack)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, barFill)
local topHint = label(top, { ZIndex = 11, Font = Enum.Font.GothamBlack, Text = "☢ GET INTO A NUCLEAR BUNKER! ☢", TextColor3 = C3(255, 230, 60), Position = UDim2.new(0.04, 0, 0.83, 0), Size = UDim2.new(0.92, 0, 0.15, 0) })

-- centre: final 10 seconds
local bigCount = label(gui, { ZIndex = 20, Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.3, 0.25), TextColor3 = C3(255, 40, 30) })
local bigScale = mk("UIScale", {}, bigCount)

-- bottom middle: oxygen
local o2 = mk("Frame", { Visible = false, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.fromOffset(420, 96), BackgroundColor3 = C3(14, 22, 30), BackgroundTransparency = 0.15, ZIndex = 10 }, gui)
mk("UICorner", { CornerRadius = UDim.new(0, 18) }, o2)
local o2Stroke = mk("UIStroke", { Color = C3(80, 220, 140), Thickness = 4 }, o2)
local tankView = mk("ViewportFrame", { ZIndex = 11, BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(84, 88), Ambient = C3(180, 180, 190), LightDirection = Vector3.new(-1, -1, -1) }, o2)
do
	local tank = prop("OxygenTank", 1)
	if tank then
		tank.Parent = tankView
		local cam = mk("Camera", { FieldOfView = 40 }, tankView)
		tankView.CurrentCamera = cam
		local cf, size = tank:GetBoundingBox()
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(size.Y * 0.9, size.Y * 0.3, size.Y * 1.6), cf.Position)
	end
end
local o2Title = label(o2, { ZIndex = 11, Text = "OXYGEN", TextColor3 = C3(140, 255, 180), Position = UDim2.fromOffset(96, 6), Size = UDim2.new(0.4, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left })
local o2Secs = label(o2, { ZIndex = 11, Text = "15.0 s", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 6), Size = UDim2.new(0.35, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Right })
local o2Back = mk("Frame", { ZIndex = 11, Position = UDim2.fromOffset(96, 38), Size = UDim2.new(1, -110, 0, 22), BackgroundColor3 = C3(40, 50, 60) }, o2)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, o2Back)
local o2Fill = mk("Frame", { ZIndex = 12, Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(80, 230, 140) }, o2Back)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, o2Fill)
mk("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, C3(170, 170, 170)) }, o2Fill)
local o2Hint = label(o2, { ZIndex = 11, Font = Enum.Font.GothamBold, Text = "Harvest palm trees for +8 s", TextColor3 = C3(200, 230, 255), Position = UDim2.fromOffset(96, 66), Size = UDim2.new(1, -110, 0, 20), TextXAlignment = Enum.TextXAlignment.Left })

--------------------------------------------------------------------
-- state
--------------------------------------------------------------------
local state = nil

local function stopAll()
	local s = state
	state = nil
	shakeBase = 0
	gui.Enabled = false
	bigCount.Visible = false
	o2.Visible = false
	redPulse.BackgroundTransparency = 1
	if not s then
		return
	end
	for _, c in ipairs(s.conns) do
		c:Disconnect()
	end
	for _, snd in ipairs(s.loops) do
		tween(snd, 2, { Volume = 0 })
		Debris:AddItem(snd, 2.1)
	end
	for _, m in ipairs(s.models) do
		m:Destroy()
	end
	-- give the sky back
	if s.lighting then
		for k, v in pairs(s.lighting) do
			Lighting[k] = v
		end
		for _, child in ipairs(s.storedSky) do
			child.Parent = Lighting
		end
		if s.space then
			s.space:Destroy()
		end
	end
	if s.cc then
		tween(s.cc, 2, { TintColor = WHITE, Contrast = 0, Saturation = 0, Brightness = 0 })
		Debris:AddItem(s.cc, 2.1)
	end
end

local function track(s, m)
	if m then
		table.insert(s.models, m)
	end
	return m
end

--------------------------------------------------------------------
-- approach
--------------------------------------------------------------------
local function approach(data)
	stopAll()
	local s = { conns = {}, loops = {}, models = {}, data = data }
	state = s
	gui.Enabled = true
	top.Visible = true
	topTitle.Text = "🌕 MOON COLLISION"
	topHint.Text = "☢ GET INTO A NUCLEAR BUNKER! ☢"
	topHint.TextColor3 = C3(255, 230, 60)

	s.cc = mk("ColorCorrectionEffect", { Name = "MoonFX" }, Lighting)

	-- the moon
	local moon = track(s, prop("Moon", MOON_SCALE))
	local heat = moon and moon:FindFirstChild("heat")
	local cracks = moon and moon:FindFirstChild("cracks")
	if heat then
		heat.Color = C3(255, 110, 40)
		heat.Transparency = 1
		emitter(heat, {
			Texture = TEX_FIRE,
			Color = ColorSequence.new(C3(255, 220, 120), C3(255, 60, 20)),
			LightEmission = 1,
			Size = ns(0, 260, 1, 60),
			Transparency = ns(0, 0.2, 1, 1),
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(0, 40),
			Rate = 0,
		})
	end
	if cracks then
		cracks.Transparency = 1
	end

	-- bunker markers
	for _, pos in ipairs(data.bunkers) do
		local anchor = track(s, ghost(CFrame.new(pos + Vector3.new(0, 22, 0))))
		local bb = mk("BillboardGui", { Size = UDim2.fromOffset(170, 60), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 5000 }, anchor)
		local l = label(bb, { Size = UDim2.fromScale(1, 1), Text = "☢ BUNKER", TextColor3 = C3(255, 220, 40) })
		table.insert(s.conns, RunService.RenderStepped:Connect(function()
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				l.Text = ("☢ BUNKER\n%s studs"):format(fmt((root.Position - pos).Magnitude))
			end
		end))
	end

	-- sound bed
	local rumble = sound("Thunder", 0, 0.25, nil, true)
	local roar = sound("Whoosh", 0, 0.3, nil, true)
	for _, snd in ipairs({ rumble, roar }) do
		if snd then
			table.insert(s.loops, snd)
		end
	end

	local lastSecond = nil
	table.insert(s.conns, RunService.RenderStepped:Connect(function()
		local elapsed = workspace:GetServerTimeNow() - data.t0
		local d = math.max(0, data.distance - data.speed * elapsed)
		local left = d / data.speed
		local close = 1 - d / data.distance -- 0 far .. 1 impact

		topTimer.Text = ("T-%04.1f s"):format(left)
		topDist.Text = fmt(d) .. " studs"
		barFill.Size = UDim2.fromScale(close, 1)
		topStroke.Color = C3(255, 60, 40):Lerp(WHITE, (math.sin(os.clock() * (4 + close * 14)) + 1) / 2 * close)

		-- tick each second, slam the last ten
		local sec = math.ceil(left)
		if sec ~= lastSecond and left > 0 then
			lastSecond = sec
			sound(TICK_SOUND, 0.6 + close * 0.4, 0.8 + close * 0.6)
			if sec <= 10 then
				bigCount.Visible = true
				bigCount.Text = tostring(sec)
				bigScale.Scale = 2.2
				bigCount.TextTransparency = 0
				tween(bigScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
				tween(bigCount, 0.9, { TextTransparency = 0.6 })
				kick(0.4 + close, 0.3)
				redPulse.BackgroundTransparency = 0.75
				tween(redPulse, 0.6, { BackgroundTransparency = 1 })
				if sec <= 3 then
					sound("Explosion", 0.4, 0.5)
				end
			end
		end

		-- inside a bunker?
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and s.doorsClosing == nil then
			local safe = false
			for _, pos in ipairs(data.bunkers) do
				local flat = (root.Position - pos) * Vector3.new(1, 0, 1)
				if flat.Magnitude < 13 and math.abs(root.Position.Y - pos.Y) < 14 then
					safe = true
				end
			end
			topHint.Text = safe and "✔ YOU ARE IN THE BUNKER - STAY INSIDE!" or "☢ GET INTO A NUCLEAR BUNKER! ☢"
			topHint.TextColor3 = safe and C3(120, 255, 140) or C3(255, 230, 60)
		end

		-- the moon itself
		if moon then
			local vis = d * VISUAL_SQUASH + 100 * MOON_SCALE * 0.75
			moon:PivotTo(CFrame.new(data.impact + data.fromDir * vis) * CFrame.Angles(elapsed * 0.03, elapsed * 0.05, 0))
			if heat then
				heat.Transparency = 1 - math.clamp((close - 0.55) / 0.45, 0, 1) * 0.55
				heat:FindFirstChildOfClass("ParticleEmitter").Rate = close > 0.5 and (close - 0.5) * 120 or 0
			end
			if cracks then
				cracks.Transparency = 1 - math.clamp((close - 0.3) / 0.6, 0, 1)
			end
		end

		-- the world reacts
		shakeBase = close ^ 2 * 1.2
		s.cc.TintColor = WHITE:Lerp(C3(255, 150, 110), close * 0.7)
		s.cc.Contrast = close * 0.2
		if rumble then
			rumble.Volume = 0.2 + close * 0.8
		end
		if roar then
			roar.Volume = close ^ 2 * 1
			roar.PlaybackSpeed = 0.25 + close * 0.25
		end
	end))

	task.delay(math.max(0, data.distance / data.speed - 8), function()
		if state == s then
			sound("DragonRoar", 1, 0.22) -- the moon tearing through the atmosphere
		end
	end)
end

--------------------------------------------------------------------
-- impact
--------------------------------------------------------------------
local function goAirless(s, data)
	-- strip the atmosphere: black sky, stars, harsh light (all local, put back at the end)
	s.lighting = {}
	for _, k in ipairs({ "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "FogEnd", "FogStart", "ExposureCompensation", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" }) do
		s.lighting[k] = Lighting[k]
	end
	s.storedSky = {}
	s.space = mk("Folder", { Name = "MoonFXStoredSky" }, ReplicatedStorage)
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("Clouds") then
			child.Parent = s.space
			table.insert(s.storedSky, child)
		end
	end
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		local was = clouds.Enabled
		clouds.Enabled = false
		table.insert(s.conns, { Disconnect = function()
			clouds.Enabled = was
		end })
	end
	-- default sky textures at midnight = black space; lots of stars, no Roblox sun/moon (ours are Blender models)
	mk("Sky", { Name = "MoonFXSpace", StarCount = 5000, CelestialBodiesShown = false }, Lighting)
	table.insert(s.conns, { Disconnect = function()
		local sky = Lighting:FindFirstChild("MoonFXSpace")
		if sky then
			sky:Destroy()
		end
	end })
	Lighting.ClockTime = 0
	Lighting.Brightness = 3
	Lighting.Ambient = C3(95, 88, 80)
	Lighting.OutdoorAmbient = C3(170, 160, 140)
	Lighting.FogStart = 100000
	Lighting.FogEnd = 100000
	Lighting.ExposureCompensation = 0.2
	tween(s.cc, 3, { TintColor = C3(255, 238, 200), Contrast = 0.25, Saturation = -0.2 })

	-- the solar system hangs in the black sky
	local c = data.center
	local planets = {
		{ "Sun", 7, Vector3.new(-3800, 900, -2600), 0.02 },
		{ "Mercury", 5, Vector3.new(-2600, 1200, -3200), 0.2 },
		{ "Venus", 5, Vector3.new(-1500, 1500, -3600), 0.1 },
		{ "Earth", 12, Vector3.new(400, 1300, -3200), 0.15 },
		{ "Mars", 6, Vector3.new(1800, 1700, -2800), 0.15 },
		{ "Jupiter", 5, Vector3.new(3200, 1400, -1200), 0.08 },
		{ "Saturn", 5, Vector3.new(3400, 1600, 1200), 0.05 },
		{ "Uranus", 4, Vector3.new(1800, 1900, 3000), 0.07 },
		{ "Neptune", 4, Vector3.new(-600, 2000, 3400), 0.07 },
	}
	for _, p in ipairs(planets) do
		local m = track(s, prop(p[1], p[2]))
		if m then
			local base = CFrame.new(c + p[3])
			m:PivotTo(base)
			table.insert(s.conns, RunService.RenderStepped:Connect(function()
				m:PivotTo(base * CFrame.Angles(0.3, os.clock() * p[4], 0))
			end))
		end
	end
end

local function impact(data)
	local s = state
	if not s then
		return
	end
	s.impacted = true
	top.Visible = true
	bigCount.Visible = false
	shakeBase = 0

	-- white-out + the loudest thing in the game
	whiteout.BackgroundTransparency = 0
	tween(whiteout, 3, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	kick(4.5, 3.5)
	sound("Explosion", 1, 0.35)
	sound("Explosion", 1, 0.6)
	sound(BOOM_SOUND, 1, 0.5)
	sound("Thunder", 1, 0.4)
	task.delay(0.6, sound, "DragonRoar", 0.9, 0.18)
	task.delay(1.2, sound, "Thunder", 0.9, 0.3)
	for _, snd in ipairs(s.loops) do
		tween(snd, 4, { Volume = 0.15 })
	end

	local pos = data.impact
	-- the moon settles into the sea, glowing
	for _, m in ipairs(s.models) do
		if m.Name == "Moon" then
			local cracks = m:FindFirstChild("cracks")
			if cracks then
				cracks.Transparency = 0
			end
			local heat = m:FindFirstChild("heat")
			if heat then
				tween(heat, 6, { Transparency = 1 })
				local e = heat:FindFirstChildOfClass("ParticleEmitter")
				if e then
					e.Rate = 25
				end
			end
		end
	end

	-- shockwave rings sweeping over the island
	for i, color in ipairs({ C3(255, 150, 60), WHITE, C3(255, 90, 40) }) do
		task.delay((i - 1) * 0.35, function()
			local ring = track(s, prop("FxShockRing", 2, color))
			if not ring then
				return
			end
			local t0 = os.clock()
			while ring.Parent do
				local a = math.min((os.clock() - t0) / 4.5, 1)
				ring:ScaleTo(2 + 78 * (1 - (1 - a) ^ 3))
				ring:PivotTo(CFrame.new(pos + Vector3.new(0, 20 + i * 6, 0)))
				for _, d in ipairs(ring:GetDescendants()) do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = a
					end
				end
				if a >= 1 then
					break
				end
				RunService.RenderStepped:Wait()
			end
			ring:Destroy()
		end)
	end

	-- dust wall + fire plume at the impact
	local holder = track(s, ghost(CFrame.new(pos + Vector3.new(0, 40, 0)), Vector3.new(300, 10, 300)))
	emitter(holder, {
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(C3(150, 130, 110), C3(80, 70, 65)),
		Size = ns(0, 80, 1, 260),
		Transparency = ns(0, 0.2, 1, 1),
		Lifetime = NumberRange.new(5, 9),
		Speed = NumberRange.new(60, 160),
		SpreadAngle = Vector2.new(80, 80),
		EmissionDirection = Enum.NormalId.Top,
		Drag = 0.6,
	}):Emit(70)
	local plume = emitter(holder, {
		Texture = TEX_FIRE,
		Color = ColorSequence.new(C3(255, 230, 140), C3(255, 70, 20)),
		LightEmission = 1,
		Size = ns(0, 120, 1, 20),
		Transparency = ns(0, 0, 1, 1),
		Lifetime = NumberRange.new(1.5, 3),
		Speed = NumberRange.new(100, 220),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
		Rate = 60,
	})
	task.delay(6, function()
		plume.Rate = 8
	end)

	-- moon debris raining across the sky
	for i = 1, 26 do
		local chunk = track(s, prop(i % 3 == 0 and "FxRock" or "FxMeteorChunk", math.random(5, 12)))
		if chunk then
			local body = chunk:FindFirstChildWhichIsA("BasePart", true)
			if body then
				emitter(body, {
					Texture = TEX_FIRE,
					Color = ColorSequence.new(C3(255, 200, 90), C3(255, 60, 20)),
					LightEmission = 1,
					Size = ns(0, 18, 1, 0),
					Lifetime = NumberRange.new(0.6, 1),
					Rate = 40,
				})
			end
			local toward = (data.center - pos) * Vector3.new(1, 0, 1)
			toward = toward.Magnitude > 1 and toward.Unit or Vector3.xAxis
			local vel = (toward * math.random(120, 380) + Vector3.new(math.random(-160, 160), math.random(260, 480), math.random(-160, 160)))
			local spin = CFrame.Angles(math.random() * 0.1, math.random() * 0.1, math.random() * 0.1)
			task.spawn(function()
				local p, rot, t0 = pos + Vector3.new(0, 60, 0), CFrame.new(), os.clock()
				while chunk.Parent and os.clock() - t0 < 6 do
					local dt = RunService.RenderStepped:Wait()
					vel += Vector3.new(0, -196, 0) * dt
					p += vel * dt
					rot *= spin
					chunk:PivotTo(CFrame.new(p) * rot)
					if p.Y < data.center.Y - 60 then
						break
					end
				end
				chunk:Destroy()
			end)
		end
	end

	-- the sea boils away: steam rising off the water
	local island = workspace:FindFirstChild("IslandMap")
	local water = island and island:FindFirstChild("Water")
	local parts = {}
	for _, d in ipairs(water and water:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	for i = 1, math.min(24, #parts) do
		local w = parts[math.random(1, #parts)]
		local steam = track(s, ghost(CFrame.new(w.Position + Vector3.new(0, w.Size.Y / 2, 0)), Vector3.new(math.min(w.Size.X, 120), 1, math.min(w.Size.Z, 120))))
		local e = emitter(steam, {
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(C3(240, 245, 250)),
			Size = ns(0, 10, 1, 40),
			Transparency = ns(0, 0.5, 1, 1),
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(10, 25),
			EmissionDirection = Enum.NormalId.Top,
			Rate = 14,
		})
		task.delay(7, function()
			e.Enabled = false
		end)
	end
	sound("WaterSplash", 0.8, 0.5)
	task.delay(0.8, sound, "Whoosh", 0.8, 0.5)

	goAirless(s, data)

	-- aftermath timer + oxygen UI
	topTitle.Text = "🌑 NO ATMOSPHERE"
	topHint.Text = "Harvest palm trees for oxygen!"
	topHint.TextColor3 = C3(140, 255, 180)
	topStroke.Color = C3(120, 200, 255)
	barFill.BackgroundColor3 = C3(120, 200, 255)
	local total = data.endsAt - workspace:GetServerTimeNow()
	local lastLowTick = 0
	table.insert(s.conns, RunService.RenderStepped:Connect(function()
		local left = math.max(0, data.endsAt - workspace:GetServerTimeNow())
		topTimer.Text = ("0:%02d"):format(math.ceil(left))
		topDist.Text = "SURVIVE!"
		barFill.Size = UDim2.fromScale(left / math.max(total, 1), 1)

		local oxygen = player:GetAttribute("Oxygen")
		local maxO2 = player:GetAttribute("OxygenMax") or 15
		o2.Visible = oxygen ~= nil
		if oxygen then
			local f = math.clamp(oxygen / maxO2, 0, 1)
			o2Fill.Size = UDim2.fromScale(f, 1)
			o2Fill.BackgroundColor3 = C3(255, 60, 50):Lerp(C3(80, 230, 140), math.clamp((f - 0.15) / 0.5, 0, 1))
			o2Secs.Text = ("%.1f s"):format(oxygen)
			local full = oxygen >= maxO2 - 0.05
			o2Hint.Text = full and "TANK FULL - wait before harvesting" or "Harvest palm trees: +8 s"
			o2Hint.TextColor3 = full and C3(255, 230, 90) or C3(200, 230, 255)
			local low = oxygen < 5
			o2Stroke.Color = low and C3(255, 60, 50):Lerp(WHITE, (math.sin(os.clock() * 12) + 1) / 2) or C3(80, 220, 140)
			redPulse.BackgroundTransparency = low and (0.7 + 0.25 * (math.sin(os.clock() * 6) + 1) / 2) or 1
			if low and os.clock() - lastLowTick > 1 then
				lastLowTick = os.clock()
				sound(TICK_SOUND, 0.8, 0.6)
			end
		else
			redPulse.BackgroundTransparency = 1
		end
	end))
end

--------------------------------------------------------------------
-- harvest + small events
--------------------------------------------------------------------
local function harvest(data)
	local s = state
	if not s then
		return
	end
	local mine = data.userId == player.UserId
	local who = Players:GetPlayerByUserId(data.userId)
	local target = who and who.Character and who.Character:FindFirstChild("HumanoidRootPart")

	local burst = ghost(CFrame.new(data.pos), Vector3.new(6, 2, 6))
	emitter(burst, {
		Texture = TEX_SPARK,
		Color = ColorSequence.new(C3(120, 255, 160), C3(200, 255, 255)),
		LightEmission = 1,
		Size = ns(0, 1.4, 1, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(10, 26),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2,
	}):Emit(60)
	Debris:AddItem(burst, 2)
	sound("WaterSplash", mine and 0.7 or 0.3, 1.5, burst)
	sound("Whoosh", mine and 0.6 or 0.25, 1.6, burst)

	-- leaves turn into oxygen and fly into the harvester's tank
	if target then
		for i = 1, 8 do
			local leaf = prop("FxLeaf", 1.2)
			if leaf then
				local from = data.pos + Vector3.new(math.random(-4, 4), math.random(-2, 2), math.random(-4, 4))
				local mid = (from + target.Position) / 2 + Vector3.new(0, 14, 0)
				task.delay(i * 0.05, function()
					local t0 = os.clock()
					while leaf.Parent and target.Parent do
						local a = math.min((os.clock() - t0) / 0.8, 1)
						local p = from:Lerp(mid, a):Lerp(mid:Lerp(target.Position, a), a)
						leaf:PivotTo(CFrame.new(p) * CFrame.Angles(a * 9, a * 6, 0))
						if a >= 1 then
							break
						end
						RunService.RenderStepped:Wait()
					end
					leaf:Destroy()
				end)
			end
		end
	end
	if mine then
		local pop = ghost(CFrame.new(data.pos + Vector3.new(0, 4, 0)))
		local bb = mk("BillboardGui", { Size = UDim2.fromOffset(160, 50), AlwaysOnTop = true, LightInfluence = 0 }, pop)
		local l = label(bb, { Size = UDim2.fromScale(1, 1), Text = "+8 s O2", TextColor3 = C3(120, 255, 160) })
		tween(pop, 1.4, { CFrame = pop.CFrame + Vector3.new(0, 10, 0) })
		tween(l, 1.4, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(pop, 1.5)
		o2Fill.Size = UDim2.fromScale(1, 1)
	end
end

remote.OnClientEvent:Connect(function(kind, data)
	local ok, err = pcall(function()
		if kind == "Approach" then
			approach(data)
		elseif kind == "DoorsClosing" and state then
			state.doorsClosing = true
			topHint.Text = "⚠ BLAST DOORS CLOSING! ⚠"
			topHint.TextColor3 = C3(255, 70, 50)
			sound("DrumRoll", 0.8, 1.4)
		elseif kind == "Impact" then
			impact(data)
		elseif kind == "Harvest" then
			harvest(data)
		elseif kind == "Full" then
			o2Hint.Text = "TANK FULL - use some oxygen first!"
			o2Hint.TextColor3 = C3(255, 120, 90)
			sound(TICK_SOUND, 0.8, 0.5)
		elseif kind == "End" then
			stopAll()
		end
	end)
	if not ok then
		warn("[MoonFX] " .. tostring(kind) .. ": " .. tostring(err))
	end
end)
