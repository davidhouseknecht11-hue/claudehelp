-- Underwater visual effects: blue tint, blur, and rising bubbles when submerged
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local WATER_TOP_Y = 0
local WATER_HALF_SIZE = 4096

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Create the effects once, toggle them as needed
local blur = Instance.new("BlurEffect")
blur.Name = "UnderwaterBlur"
blur.Size = 0
blur.Parent = Lighting

local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "UnderwaterTint"
colorCorrection.TintColor = Color3.new(1, 1, 1) -- neutral white when out of water
colorCorrection.Saturation = 0
colorCorrection.Contrast = 0
colorCorrection.Parent = Lighting

local TweenService = game:GetService("TweenService")
local function tweenTo(obj, props, time)
	local tween = TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tween:Play()
end

local isUnderwater = false

local function setUnderwater(active)
	if active == isUnderwater then return end
	isUnderwater = active
	if active then
		tweenTo(blur, {Size = 14}, 0.4)
		tweenTo(colorCorrection, {TintColor = Color3.fromRGB(140, 190, 230), Saturation = -0.35, Contrast = 0.08}, 0.4)
	else
		tweenTo(blur, {Size = 0}, 0.4)
		tweenTo(colorCorrection, {TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0}, 0.4)
	end
end

-- Bubble emitter that follows the character's head while underwater
local function createBubbles(character)
	local head = character:FindFirstChild("Head")
	if not head then return end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "UnderwaterBubbles"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
	emitter.LightEmission = 0.3
	emitter.Lifetime = NumberRange.new(1.2, 2.4)
	emitter.Speed = NumberRange.new(1.5, 3.5)
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.Acceleration = Vector3.new(0, 4, 0) -- bubbles rise
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.8, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rate = 0
	emitter.Parent = head
	return emitter
end

local bubbleEmitter = nil

local function onCharacterAdded(character)
	bubbleEmitter = createBubbles(character)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then onCharacterAdded(player.Character) end

RunService.Heartbeat:Connect(function()
	local camPos = camera.CFrame.Position
	local drained = workspace:GetAttribute("WaterDrained") == true -- the sea has boiled away (Moon Collision)
	local camUnder = not drained and camPos.Y < WATER_TOP_Y
		and math.abs(camPos.X) < WATER_HALF_SIZE
		and math.abs(camPos.Z) < WATER_HALF_SIZE
	setUnderwater(camUnder)

	-- Bubbles rise from the character while their head is submerged
	if bubbleEmitter and bubbleEmitter.Parent then
		local head = bubbleEmitter.Parent
		local headUnder = not drained and head.Position.Y < WATER_TOP_Y - 0.2
		bubbleEmitter.Rate = headUnder and 8 or 0
	else
		bubbleEmitter = nil
	end
end)