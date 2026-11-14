-- BlenderAnimator  (Script with RunContext = Client, child of the LobbyUpgrade script)
--
-- LobbyUpgrade moves this into ReplicatedStorage so it runs on every player's device.
-- Plays the walk / run / swim cycles keyframed in Blender (blender_animations.py -> BlenderAnims)
-- on every R15 character nearby, by setting each Motor6D.Transform right after Roblox's own
-- animations run - so no animation upload is needed. Animating everyone (not only yourself) is
-- deliberate: Transform changes made on one device are not sent to other players.
--   * walk blends into run as the character speeds up; the cycle speed follows the real speed,
--     so feet don't slide
--   * swim takes over in the water (same water band as SwimController, off while WaterDrained)
--   * idle / jump / fall / climb stay on the normal Roblox animations, with smooth blends in and out

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ENABLED = true
local MAX_DISTANCE = 250   -- don't animate characters further than this from the camera
local WALK_STRIDE = 13     -- studs travelled per walk cycle
local RUN_STRIDE = 18      -- studs travelled per run cycle
local RUN_FROM, RUN_TO = 12, 20 -- speeds where walk blends into run
local WATER_TOP_Y, WATER_BOTTOM_Y = 0, -6 -- must match SwimController
local BLEND_RATE = 10      -- how fast the cycles fade in / out

if not ENABLED then
	return
end

local data = require(ReplicatedStorage:WaitForChild("BlenderAnims"))
local camera = workspace.CurrentCamera
local clips = data.clips
local rigs = {}

local function register(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not hrp or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return -- R6 characters keep their normal animations
	end
	character:WaitForChild("UpperTorso", 10)
	local motors = {}
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	rigs[character] = { humanoid = humanoid, hrp = hrp, motors = motors, phase = 0, swimPhase = 0, wLoco = 0, wSwim = 0, runMix = 0 }
	character.Destroying:Once(function()
		rigs[character] = nil
	end)
end

local function hook(player)
	player.CharacterAdded:Connect(register)
	if player.Character then
		task.spawn(register, player.Character)
	end
end
Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do
	hook(p)
end

-- angle difference the short way round (the swim arms spin continuously)
local function wrap(d)
	if d > math.pi then
		return d - 2 * math.pi
	elseif d < -math.pi then
		return d + 2 * math.pi
	end
	return d
end

local function sample(clip, joint, phase)
	local frames = clip.joints[joint]
	if not frames then
		return 0, 0, 0
	end
	local n = #frames
	local f = phase * n
	local i = math.floor(f) % n + 1
	local j = i % n + 1
	local a = f - math.floor(f)
	local p, q = frames[i], frames[j]
	return p[1] + wrap(q[1] - p[1]) * a, p[2] + wrap(q[2] - p[2]) * a, p[3] + wrap(q[3] - p[3]) * a
end

local function sampleY(clip, phase)
	local ys = clip.rootY
	local n = #ys
	local f = phase * n
	local i = math.floor(f) % n + 1
	return ys[i] + (ys[i % n + 1] - ys[i]) * (f - math.floor(f))
end

local GROUNDED = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Landed] = true,
}

RunService.Stepped:Connect(function(_, dt)
	local camPos = camera.CFrame.Position
	local drained = workspace:GetAttribute("WaterDrained") == true
	for character, r in pairs(rigs) do
		local hrp, humanoid = r.hrp, r.humanoid
		if not character.Parent or not hrp.Parent or humanoid.Health <= 0 then
			continue
		end
		if (hrp.Position - camPos).Magnitude > MAX_DISTANCE then
			continue
		end
		local v = hrp.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local y = hrp.Position.Y
		local swimming = character:GetAttribute("Swimming") == true
			or (not drained and y < WATER_TOP_Y and y > WATER_BOTTOM_Y and humanoid.FloorMaterial == Enum.Material.Air)
		local grounded = GROUNDED[humanoid:GetState()] == true and humanoid.FloorMaterial ~= Enum.Material.Air

		local k = math.min(1, dt * BLEND_RATE)
		r.wLoco += (((not swimming and grounded and speed > 0.8) and 1 or 0) - r.wLoco) * k
		r.wSwim += ((swimming and 1 or 0) - r.wSwim) * k
		r.runMix += (math.clamp((speed - RUN_FROM) / (RUN_TO - RUN_FROM), 0, 1) - r.runMix) * k
		local stride = WALK_STRIDE + (RUN_STRIDE - WALK_STRIDE) * r.runMix
		r.phase = (r.phase + dt * speed / stride) % 1
		r.swimPhase = (r.swimPhase + dt / clips.swim.length * math.clamp(speed / 10, 0.6, 1.4)) % 1
		if r.wLoco < 0.005 and r.wSwim < 0.005 then
			continue
		end

		local ph, sph, mix = r.phase, r.swimPhase, r.runMix
		local locoY = sampleY(clips.walk, ph) * (1 - mix) + sampleY(clips.run, ph) * mix
		local swimY = sampleY(clips.swim, sph)
		for name, motor in pairs(r.motors) do
			if clips.walk.joints[name] or clips.swim.joints[name] then
				local wx, wy, wz = sample(clips.walk, name, ph)
				local rx, ry, rz = sample(clips.run, name, ph)
				local loco = CFrame.Angles(wx + (rx - wx) * mix, wy + (ry - wy) * mix, wz + (rz - wz) * mix)
				local swim = CFrame.Angles(sample(clips.swim, name, sph))
				if name == "Root" then
					loco = CFrame.new(0, locoY, 0) * loco
					swim = CFrame.new(0, swimY, 0) * swim
				end
				local t = motor.Transform
				if r.wLoco > 0.005 then
					t = t:Lerp(loco, r.wLoco)
				end
				if r.wSwim > 0.005 then
					t = t:Lerp(swim, r.wSwim)
				end
				motor.Transform = t
			end
		end
	end
end)
