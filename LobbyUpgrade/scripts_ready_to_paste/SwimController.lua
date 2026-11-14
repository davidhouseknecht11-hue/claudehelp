local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Water region configuration
local WATER_TOP_Y = 0
local WATER_BOTTOM_Y = -6
local WATER_HALF_SIZE = 4096 -- water spans X/Z -4096 to 4096

-- Swim thresholds (HumanoidRootPart Y) with hysteresis so floating stays stable
local ENTER_SWIM_Y = -2 -- below this, start swimming
local EXIT_SWIM_Y = -1 -- above this, stop swimming

local SWIM_SPEED = 14
local FLOAT_Y = -2.5 -- HumanoidRootPart floats 2.5 studs below the surface

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local hrp = character:WaitForChild("HumanoidRootPart")

local isSwimming = false
local buoyancyForce = nil
local buoyancyAttachment = nil
local swimTrail = nil
local swimBubbles = nil

local function createSwimEffects()
	-- Trail behind the character while swimming
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailAttachment0"
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = hrp
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailAttachment1"
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = hrp

	swimTrail = Instance.new("Trail")
	swimTrail.Name = "SwimTrail"
	swimTrail.Attachment0 = a0
	swimTrail.Attachment1 = a1
	swimTrail.Color = ColorSequence.new(Color3.fromRGB(140, 200, 255), Color3.fromRGB(200, 235, 255))
	swimTrail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	swimTrail.Lifetime = 0.6
	swimTrail.LightEmission = 0.3
	swimTrail.Parent = hrp

	-- Bubble wake rising behind the swimmer
	swimBubbles = Instance.new("ParticleEmitter")
	swimBubbles.Name = "SwimBubbles"
	swimBubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	swimBubbles.Color = ColorSequence.new(Color3.fromRGB(190, 225, 255))
	swimBubbles.LightEmission = 0.3
	swimBubbles.Lifetime = NumberRange.new(0.8, 1.6)
	swimBubbles.Speed = NumberRange.new(1, 2.5)
	swimBubbles.SpreadAngle = Vector2.new(20, 20)
	swimBubbles.Acceleration = Vector3.new(0, 5, 0)
	swimBubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 0.28),
	})
	swimBubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.8, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	swimBubbles.Rate = 12
	swimBubbles.Parent = hrp
end

local function removeSwimEffects()
	if swimTrail then
		local a0 = swimTrail.Attachment0
		local a1 = swimTrail.Attachment1
		swimTrail.Parent = nil
		if a0 then a0.Parent = nil end
		if a1 then a1.Parent = nil end
		swimTrail = nil
	end
	if swimBubbles then
		swimBubbles.Parent = nil
		swimBubbles = nil
	end
end

local function isInWaterRegion(y)
	if workspace:GetAttribute("WaterDrained") then
		return false -- the sea has boiled away (Moon Collision)
	end
	return y < WATER_TOP_Y and y > WATER_BOTTOM_Y
		and math.abs(hrp.Position.X) < WATER_HALF_SIZE
		and math.abs(hrp.Position.Z) < WATER_HALF_SIZE
end

local function setSwimming(active)
	if active == isSwimming then return end
	isSwimming = active
	character:SetAttribute("Swimming", active)

	if active then
		humanoid.WalkSpeed = SWIM_SPEED
		createSwimEffects()
		-- Gentle damped buoyancy so the character floats calmly at the surface
		buoyancyAttachment = Instance.new("Attachment")
		buoyancyAttachment.Name = "SwimBuoyancyAttachment"
		buoyancyAttachment.Parent = hrp
		buoyancyForce = Instance.new("VectorForce")
		buoyancyForce.Name = "SwimBuoyancyForce"
		buoyancyForce.Attachment0 = buoyancyAttachment
		buoyancyForce.RelativeTo = Enum.ActuatorRelativeTo.World
		buoyancyForce.ApplyAtCenterOfMass = true
		buoyancyForce.Parent = hrp
	else
		if buoyancyForce then buoyancyForce.Parent = nil end
		if buoyancyAttachment then buoyancyAttachment.Parent = nil end
		buoyancyForce = nil
		buoyancyAttachment = nil
		removeSwimEffects()
		-- Let the MovementController restore normal speed
		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	if humanoid.Health <= 0 then
		setSwimming(false)
		return
	end

	local y = hrp.Position.Y

	if not isSwimming then
		if isInWaterRegion(y) and y < ENTER_SWIM_Y then
			setSwimming(true)
		end
		return
	end

	-- Currently swimming
	if not isInWaterRegion(y) or y > EXIT_SWIM_Y then
		setSwimming(false)
		return
	end

	-- Keep the humanoid in the Swimming state so swim controls and animations work
	local state = humanoid:GetState()
	if state ~= Enum.HumanoidStateType.Swimming and state ~= Enum.HumanoidStateType.Dead then
		humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
	end

	-- Damped float: settles at FLOAT_Y without oscillating; LeftControl dives down
	local mass = hrp.AssemblyMass
	local gravity = workspace.Gravity
	if mass > 0 and buoyancyForce then
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			-- Dive downward
			buoyancyForce.Force = Vector3.new(0, -mass * gravity * 0.35, 0)
		else
			-- Spring toward FLOAT_Y with velocity damping so there is no bounce
			local factor = math.clamp(1 + (FLOAT_Y - y) * 0.6, 0, 1.6)
			local damp = hrp.AssemblyLinearVelocity.Y * 2.5
			local fy = mass * gravity * factor - mass * damp
			fy = math.clamp(fy, -mass * gravity * 0.5, mass * gravity * 1.6)
			buoyancyForce.Force = Vector3.new(0, fy, 0)
		end
	end
end)

humanoid.Died:Connect(function()
	setSwimming(false)
end)

-- ============ Oxygen / drowning UI ============
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "OxygenUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local barFrame = Instance.new("Frame")
barFrame.Name = "OxygenBarFrame"
barFrame.AnchorPoint = Vector2.new(0.5, 1)
barFrame.Position = UDim2.new(0.5, 0, 1, -80)
barFrame.Size = UDim2.new(0, 260, 0, 16)
barFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
barFrame.BackgroundTransparency = 0.35
barFrame.BorderSizePixel = 0
barFrame.Visible = false
barFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = barFrame

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.AnchorPoint = Vector2.new(0, 0.5)
barFill.Position = UDim2.new(0, 2, 0.5, 0)
barFill.Size = UDim2.new(1, -4, 1, -4)
barFill.BackgroundColor3 = Color3.fromRGB(80, 170, 255)
barFill.BorderSizePixel = 0
barFill.Parent = barFrame

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = barFill

local MAX_OXYGEN = 100

local function updateOxygenUI()
	local oxygen = character:GetAttribute("Oxygen")
	if oxygen == nil then return end
	local ratio = math.clamp(oxygen / MAX_OXYGEN, 0, 1)
	barFill:TweenSize(UDim2.new(ratio, -4, 1, -4), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.1, true)
	barFill.BackgroundColor3 = (ratio <= 0.25) and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(80, 170, 255)
	barFrame.Visible = ratio < 1
end

character:GetAttributeChangedSignal("Oxygen"):Connect(updateOxygenUI)
updateOxygenUI()

-- Clean up the oxygen UI when the character dies or despawns
humanoid.Died:Connect(function()
	screenGui:Destroy()
end)
script.Destroying:Connect(function()
	screenGui:Destroy()
end)