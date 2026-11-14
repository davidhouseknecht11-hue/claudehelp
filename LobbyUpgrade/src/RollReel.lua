-- RollReel  (Script with RunContext = Client, child of the LobbyUpgrade script)
--
-- LobbyUpgrade moves this into ReplicatedStorage so it runs on every player's device.
-- The disaster roll, for everyone: a reel of disaster cards slides past a centre marker,
-- each card in its rarity's colour (Common white, Rare blue, Mythic purple, Transcendent rainbow).
-- It spins while the roll happens, then glides to a stop on the real result (no jump: the slow-down
-- starts at the speed the reel was already moving), ticking on every card. The landing gets bigger
-- with the rarity. Uses the existing RollStarted / DisasterRevealed / DisasterStarted remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local assets = ReplicatedStorage:WaitForChild("DisasterAssets")
local remotes = assets:WaitForChild("Remotes")
local Config = require(assets:WaitForChild("DisasterConfig"))
local soundsFolder = assets:FindFirstChild("Sounds")

local CARD_W, CARD_H, GAP = 150, 132, 14
local STEP = CARD_W + GAP
local SPIN_SPEED = 1500       -- px per second while rolling
local LAND_TIME = 1.8         -- seconds to glide to the result
local TICK = "rbxasset://sounds/volume_slider.ogg"
local C3 = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local FALLBACK = { -- if DisasterConfig is older than the rarity redesign
	Common = { C3(245, 245, 250), C3(170, 178, 196) },
	Rare = { C3(60, 150, 255), C3(20, 70, 200) },
	Mythic = { C3(190, 90, 255), C3(255, 80, 200) },
	Transcendent = { C3(120, 255, 240), C3(255, 240, 120) },
}
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C3(255, 70, 70)), ColorSequenceKeypoint.new(0.2, C3(255, 200, 60)),
	ColorSequenceKeypoint.new(0.4, C3(90, 255, 120)), ColorSequenceKeypoint.new(0.6, C3(70, 200, 255)),
	ColorSequenceKeypoint.new(0.8, C3(170, 90, 255)), ColorSequenceKeypoint.new(1, C3(255, 70, 70)),
})
local TIER_RANK = { Common = 1, Rare = 2, Mythic = 3, Transcendent = 4 }

local function tierColors(rarity)
	local r = Config.Rarities and Config.Rarities[rarity]
	local fb = FALLBACK[rarity] or FALLBACK.Common
	return (r and r.Glow and r.Color) or fb[1], (r and r.Glow) or fb[2]
end

local function mk(class, p, parent)
	local inst = Instance.new(class)
	for k, v in pairs(p) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end
local function tween(obj, t, goal, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end
local function sound(name, volume, speed)
	local s
	if string.find(name, "://", 1, true) then
		s = mk("Sound", { SoundId = name }, nil)
	else
		local t = soundsFolder and soundsFolder:FindFirstChild(name)
		if not t then
			return
		end
		s = t:Clone()
		s.Looped = false
	end
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 8)
end
local function label(parent, p)
	local base = { BackgroundTransparency = 1, Font = Enum.Font.LuckiestGuy, TextScaled = true, TextColor3 = WHITE }
	for k, v in pairs(p) do
		if k ~= "Stroke" then
			base[k] = v
		end
	end
	local l = mk("TextLabel", base, parent)
	mk("UIStroke", { Color = C3(10, 8, 20), Thickness = p.Stroke or 2.5 }, l)
	return l
end

--------------------------------------------------------------------
-- UI
--------------------------------------------------------------------
local gui = mk("ScreenGui", { Name = "RollReel", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 25, Enabled = false }, player:WaitForChild("PlayerGui"))
local flash = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0 }, gui)
local holder = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(700, 250), BackgroundTransparency = 1 }, gui)
local holderScale = mk("UIScale", {}, holder)
mk("UISizeConstraint", { MaxSize = Vector2.new(700, 250) }, holder)
local title = label(holder, { Text = "🎲 ROLLING...", Size = UDim2.new(1, 0, 0, 40), Stroke = 3 })
local subtitle = label(holder, { Text = "", Font = Enum.Font.GothamBlack, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 22), TextColor3 = C3(200, 210, 240) })

local window = mk("Frame", { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, CARD_H + 30), BackgroundColor3 = C3(16, 14, 30), BackgroundTransparency = 0.15, ClipsDescendants = true }, holder)
mk("UICorner", { CornerRadius = UDim.new(0, 18) }, window)
local windowStroke = mk("UIStroke", { Thickness = 4, Color = C3(90, 90, 140) }, window)
mk("UIGradient", { Transparency = NumberSequence.new({ -- cards fade at the edges
	NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.15, 0), NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 0.6) }) }, window)
local strip = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, window)

-- centre marker: two glowing arrows + a line
local markerTop = label(holder, { Text = "▼", ZIndex = 5, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 78), Size = UDim2.fromOffset(40, 30), TextColor3 = C3(255, 230, 90) })
local markerBot = label(holder, { Text = "▲", ZIndex = 5, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62 + CARD_H + 30), Size = UDim2.fromOffset(40, 30), TextColor3 = C3(255, 230, 90) })
mk("Frame", { ZIndex = 4, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = C3(255, 230, 90), BackgroundTransparency = 0.3, BorderSizePixel = 0 }, window)

local function makeCard(def, i)
	local rarity = def.Rarity or "Common"
	local textColor, glow = tierColors(rarity)
	local card = mk("Frame", { Size = UDim2.fromOffset(CARD_W, CARD_H), Position = UDim2.fromOffset(0, 15), BackgroundColor3 = WHITE }, strip)
	mk("UICorner", { CornerRadius = UDim.new(0, 14) }, card)
	local g = mk("UIGradient", { Rotation = 90, Color = ColorSequence.new(glow:Lerp(WHITE, 0.15), glow:Lerp(C3(0, 0, 0), 0.55)) }, card)
	local stroke = mk("UIStroke", { Thickness = 3, Color = textColor }, card)
	if rarity == "Transcendent" then
		g.Color = RAINBOW
		mk("UIGradient", { Color = RAINBOW }, stroke)
	end
	label(card, { Text = def.Emoji or "?", Font = Enum.Font.GothamBlack, Position = UDim2.fromScale(0.1, 0.06), Size = UDim2.fromScale(0.8, 0.44) })
	label(card, { Text = string.upper(def.Name), TextColor3 = textColor, Position = UDim2.fromScale(0.05, 0.52), Size = UDim2.fromScale(0.9, 0.26), Stroke = 3 })
	label(card, { Text = string.upper(rarity), Font = Enum.Font.GothamBlack, TextColor3 = textColor, Position = UDim2.fromScale(0.1, 0.8), Size = UDim2.fromScale(0.8, 0.14) })
	return { frame = card, def = def, scale = mk("UIScale", {}, card), index = i }
end

--------------------------------------------------------------------
-- spin state
--------------------------------------------------------------------
local cards = {}
local offset = 0          -- px the strip has moved
local mode = "idle"       -- idle | spin | land | done
local land = nil          -- { from, to, t0, T, card }
local lastTickIndex = 0
local token = 0

local function weightedPick()
	-- show every tier now and then (square-root weights so rare ones flash by more often)
	local total = 0
	for _, d in ipairs(Config.Disasters) do
		total += math.sqrt(math.max(d.Weight or 100, 0.0001))
	end
	local roll = math.random() * total
	for _, d in ipairs(Config.Disasters) do
		roll -= math.sqrt(math.max(d.Weight or 100, 0.0001))
		if roll <= 0 then
			return d
		end
	end
	return Config.Disasters[1]
end

local function cardAt(i)
	local c = cards[i]
	if not c then
		c = makeCard(weightedPick(), i)
		cards[i] = c
	end
	return c
end

local function layout()
	local width = window.AbsoluteSize.X
	local centerX = width / 2 - CARD_W / 2
	local first = math.floor((offset - width) / STEP)
	local last = math.ceil((offset + width) / STEP)
	for i = math.max(first, 1), last do
		local c = cardAt(i)
		c.frame.Position = UDim2.fromOffset(centerX + i * STEP - offset, 15)
	end
	for i, c in pairs(cards) do -- drop cards that slid far off the left
		if i < first - 2 then
			c.frame:Destroy()
			cards[i] = nil
		end
	end
end

local function reset()
	for _, c in pairs(cards) do
		c.frame:Destroy()
	end
	cards = {}
	offset = STEP -- card 1 in the middle
	lastTickIndex = 1
	land = nil
end

RunService.RenderStepped:Connect(function(dt)
	if mode == "spin" then
		offset += SPIN_SPEED * dt
	elseif mode == "land" and land then
		local a = math.clamp((os.clock() - land.t0) / land.T, 0, 1)
		-- ease-out quint: starts at exactly SPIN_SPEED (T = 5 * distance / speed), ends at rest
		offset = land.from + (land.to - land.from) * (1 - (1 - a) ^ 5)
		if a >= 1 then
			mode = "done"
			land.onDone()
		end
	else
		return
	end
	layout()
	local idx = math.floor(offset / STEP + 0.5)
	if idx ~= lastTickIndex then
		lastTickIndex = idx
		local speed = mode == "spin" and 1 or math.max(0.25, 1 - (os.clock() - land.t0) / land.T)
		sound(TICK, 0.35 + 0.3 * speed, 0.8 + speed * 0.7)
		markerTop.Position = UDim2.new(0.5, 0, 0, 74)
		tween(markerTop, 0.08, { Position = UDim2.new(0.5, 0, 0, 78) })
	end
end)

local function shake(amount, duration)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			local k = (1 - (os.clock() - t0) / duration) * amount
			holder.Position = UDim2.new(0.5, math.random(-8, 8) * k, 0.36, math.random(-6, 6) * k)
			if camera.CameraType == Enum.CameraType.Custom then
				camera.CFrame *= CFrame.Angles(math.random(-10, 10) * 0.001 * k, math.random(-10, 10) * 0.001 * k, 0)
			end
			RunService.RenderStepped:Wait()
		end
		holder.Position = UDim2.fromScale(0.5, 0.36)
	end)
end

local function celebrate(c, rarity, rollerName)
	local rank = TIER_RANK[rarity] or 1
	local textColor = tierColors(rarity)
	c.scale.Scale = 1
	tween(c.scale, 0.35, { Scale = 1.22 }, Enum.EasingStyle.Back)
	title.Text = (rank >= 3 and "✨ " or "") .. string.upper(rarity) .. "!" .. (rank >= 3 and " ✨" or "")
	title.TextColor3 = textColor
	windowStroke.Color = textColor
	local summoner = ReplicatedStorage:GetAttribute("SummonedBy")
	subtitle.Text = summoner and ("🔮 Summoned by " .. summoner) or (rollerName and (rollerName .. " rolled " .. c.def.Name) or c.def.Name)

	flash.BackgroundColor3 = textColor
	flash.BackgroundTransparency = 1 - 0.15 * rank
	tween(flash, 0.6 + rank * 0.2, { BackgroundTransparency = 1 })
	holderScale.Scale = 1.06
	tween(holderScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)

	if rank == 1 then
		sound("Whoosh", 0.5, 1.4)
		sound(TICK, 0.8, 0.6)
	elseif rank == 2 then
		sound("Fanfare", 0.6, 1)
	elseif rank == 3 then
		sound("Fanfare", 0.8, 0.95)
		sound("Explosion", 0.4, 0.7)
		shake(0.6, 0.5)
	else
		sound("Fanfare", 1, 0.85)
		sound("Thunder", 0.9, 0.6)
		sound("DragonRoar", 0.7, 0.5)
		sound("Explosion", 0.7, 0.5)
		shake(1.4, 1.2)
	end
	if rarity == "Transcendent" then -- rainbow sweep over the title + the card
		local g = mk("UIGradient", { Color = RAINBOW }, title)
		local t0 = os.clock()
		task.spawn(function()
			while g.Parent and os.clock() - t0 < 4 do
				g.Offset = Vector2.new(((os.clock() - t0) * 0.8) % 2 - 1, 0)
				RunService.RenderStepped:Wait()
			end
			g:Destroy()
		end)
	end
end

local function hide()
	if not gui.Enabled then
		return
	end
	local my = token
	tween(holderScale, 0.3, { Scale = 0.6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed:Once(function()
		if token == my then
			gui.Enabled = false
			mode = "idle"
		end
	end)
end

--------------------------------------------------------------------
-- remotes
--------------------------------------------------------------------
remotes:WaitForChild("RollStarted").OnClientEvent:Connect(function()
	token += 1
	reset()
	title.Text = "🎲 ROLLING..."
	title.TextColor3 = WHITE
	subtitle.Text = ""
	windowStroke.Color = C3(90, 90, 140)
	gui.Enabled = true
	holderScale.Scale = 0.6
	tween(holderScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	sound("Whoosh", 0.7, 0.9)
	mode = "spin"
	layout()
end)

remotes:WaitForChild("DisasterRevealed").OnClientEvent:Connect(function(disasterId, rarityName, rollerName)
	local def = Config.GetDisasterById(disasterId)
	if not def then
		return
	end
	if mode ~= "spin" then -- joined mid-roll: start the reel right here
		token += 1
		reset()
		gui.Enabled = true
		holderScale.Scale = 1
		mode = "spin"
		layout()
	end
	local rarity = rarityName or def.Rarity or "Common"
	-- target: the card that is ~LAND_TIME of ease-out away, swapped for the real result
	local distance = SPIN_SPEED * LAND_TIME / 5
	local targetIndex = math.ceil((offset + distance) / STEP)
	local old = cards[targetIndex]
	if old then
		old.frame:Destroy()
	end
	local c = makeCard(def, targetIndex)
	cards[targetIndex] = c
	local to = targetIndex * STEP
	if (TIER_RANK[rarity] or 1) >= 2 then
		sound("DrumRoll", 0.5, 1.3) -- anticipation while it slows down
	end
	mode = "land"
	land = {
		from = offset,
		to = to,
		t0 = os.clock(),
		T = 5 * (to - offset) / SPIN_SPEED,
		card = c,
		onDone = function()
			celebrate(c, rarity, rollerName)
		end,
	}
end)

remotes:WaitForChild("DisasterStarted").OnClientEvent:Connect(function()
	task.delay(0.3, hide)
end)
remotes:WaitForChild("DisasterEnded").OnClientEvent:Connect(hide)
