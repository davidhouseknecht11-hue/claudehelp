--[[
	DisasterSelectorClient (LocalScript)
	Builds and drives the disaster selector UI: roulette animation, roll button,
	dice spin, disaster banners, screen flashes and sound effects.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local assets = ReplicatedStorage:WaitForChild("DisasterAssets")
local remotes = assets:WaitForChild("Remotes")
local soundsFolder = assets:WaitForChild("Sounds")
local config = require(assets:WaitForChild("DisasterConfig"))

local RoundStatus = remotes:WaitForChild("RoundStatus")
local SelectionStarted = remotes:WaitForChild("SelectionStarted")
local PlayerSelected = remotes:WaitForChild("PlayerSelected")
local RollRequested = remotes:WaitForChild("RollRequested")
local RollStarted = remotes:WaitForChild("RollStarted")
local DisasterRevealed = remotes:WaitForChild("DisasterRevealed")
local DisasterStarted = remotes:WaitForChild("DisasterStarted")
local DisasterEnded = remotes:WaitForChild("DisasterEnded")

-- Progression extras (luck chip + odds line). Optional: the script still works without them.
local ProgressionConfig = ReplicatedStorage:FindFirstChild("ProgressionConfig")
	and require(ReplicatedStorage.ProgressionConfig)
local ProgressionRemotes = ReplicatedStorage:WaitForChild("ProgressionRemotes", 10)
local PromptProduct = ProgressionRemotes and ProgressionRemotes:FindFirstChild("PromptProduct")

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------

local function create(className, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

local function makeSound(name, parent)
	local template = soundsFolder:FindFirstChild(name)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.Volume = 0.8
	if template then
		sound.SoundId = template.SoundId
	end
	sound.Parent = parent
	return sound
end

local GOLD = Color3.fromRGB(255, 200, 80)
local PANEL_COLOR = Color3.fromRGB(22, 22, 34)

--------------------------------------------------------------------
-- UI construction
--------------------------------------------------------------------

local gui = create("ScreenGui", {
	Name = "DisasterSelectorGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 10,
})
gui.Parent = playerGui

-- Sounds
local drumroll = makeSound("DrumRoll", gui)
drumroll.Looped = true
local tickSound = Instance.new("Sound")
tickSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
tickSound.Volume = 0.4
tickSound.Parent = gui
local whoosh = makeSound("Whoosh", gui)
local fanfare = makeSound("Fanfare", gui)

local function playFanfare()
	fanfare:Stop()
	fanfare:Play()
	-- Safety net: never let a long fanfare track keep playing
	-- on top of the background music.
	task.delay(6, function()
		if fanfare.IsPlaying then
			fanfare:Stop()
		end
	end)
end
local diceSound = makeSound("DiceRoll", gui)

-- Background music
local calmMusic = makeSound("CalmMusic", gui)
calmMusic.Looped = true
calmMusic.Volume = 0.35
local disasterMusic = makeSound("DisasterMusic", gui)
disasterMusic.Looped = true
disasterMusic.Volume = 0.6

local CALM_VOLUME = 0.35
local DISASTER_VOLUME = 0.6

-- Track the active volume tween per sound so we can cancel stale ones.
-- A cancelled tween's Completed still fires (with Cancelled state), which
-- previously caused sounds to keep playing and overlap each other.
local activeTweens = {}

local function fadeTo(sound, volume, duration, onDone)
	-- Cancel any tween already running on this sound
	local oldTween = activeTweens[sound]
	if oldTween then
		oldTween:Cancel()
		activeTweens[sound] = nil
	end

	local tween = TweenService:Create(sound, TweenInfo.new(duration), {
		Volume = volume,
	})
	activeTweens[sound] = tween
	tween.Completed:Once(function(state)
		if activeTweens[sound] == tween then
			activeTweens[sound] = nil
			-- Only act if the tween actually finished (not cancelled)
			if state == Enum.PlaybackState.Completed and onDone then
				onDone()
			end
		end
	end)
	tween:Play()
end

local function switchMusic(toSound, targetVolume, fadeOutTime, fadeInTime)
	-- Fade out and stop every other music track
	for _, s in ipairs({ calmMusic, disasterMusic }) do
		if s ~= toSound and s.IsPlaying then
			fadeTo(s, 0, fadeOutTime, function()
				s:Stop()
			end)
		end
	end
	-- Fade in (or continue) the target track
	if not toSound.IsPlaying then
		toSound.Volume = 0
		toSound:Play()
	end
	fadeTo(toSound, targetVolume, fadeInTime)
end

local function playCalmMusic()
	switchMusic(calmMusic, CALM_VOLUME, 0.8, 1.5)
end

local function playDisasterMusic()
	switchMusic(disasterMusic, DISASTER_VOLUME, 0.8, 1)
end

-- Start with the calm island music
playCalmMusic()

-- Fullscreen flash frame
local flash = create("Frame", {
	Name = "Flash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 100,
})
flash.Parent = gui

local function doFlash(color, strength)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - (strength or 0.6)
	TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

-- Top status bar
local topBar = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(440, 44),
	BackgroundColor3 = PANEL_COLOR,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 12) }),
	create("UIStroke", { Thickness = 2, Color = GOLD, Transparency = 0.4 }),
})
topBar.Parent = gui

local statusLabel = create("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "Waiting for the next round...",
})
statusLabel.Parent = topBar

-- Selection panel (roulette)
local selectionPanel = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.fromOffset(500, 240),
	BackgroundColor3 = PANEL_COLOR,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 20) }),
	create("UIStroke", { Thickness = 3, Color = GOLD, Transparency = 0.3 }),
})
selectionPanel.Parent = gui

local selectionScale = create("UIScale", { Scale = 0 })
selectionScale.Parent = selectionPanel

create("TextLabel", {
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = GOLD,
	Text = "🎯 SELECTING THE ROLLER",
}, {}).Parent = selectionPanel

local rouletteName = create("TextLabel", {
	Position = UDim2.new(0, 0, 0, 60),
	Size = UDim2.new(1, 0, 0, 90),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 44,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "???",
}, {})
rouletteName.Parent = selectionPanel

create("TextLabel", {
	Position = UDim2.new(0, 0, 0, 168),
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 17,
	TextColor3 = Color3.fromRGB(180, 180, 200),
	Text = "Who will roll the disaster dice?",
}, {}).Parent = selectionPanel

-- Roll panel (shown only to the chosen player)
local rollPanel = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.fromOffset(500, 300),
	BackgroundColor3 = PANEL_COLOR,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 20) }),
	create("UIStroke", { Thickness = 3, Color = Color3.fromRGB(120, 200, 255), Transparency = 0.3 }),
})
rollPanel.Parent = gui

local rollScale = create("UIScale", { Scale = 0 })
rollScale.Parent = rollPanel

create("TextLabel", {
	Size = UDim2.new(1, 0, 0, 52),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 24,
	TextColor3 = Color3.fromRGB(120, 200, 255),
	Text = "🎲 YOU ROLL THE DISASTER DICE!",
}, {}).Parent = rollPanel

local rollResult = create("TextLabel", {
	Position = UDim2.new(0, 0, 0, 62),
	Size = UDim2.new(1, 0, 0, 80),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 38,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "",
}, {})
rollResult.Parent = rollPanel

local rollButton = create("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 158),
	Size = UDim2.fromOffset(240, 70),
	BackgroundColor3 = Color3.fromRGB(255, 80, 80),
	Font = Enum.Font.GothamBlack,
	TextSize = 32,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "🎲 ROLL!",
	BorderSizePixel = 0,
	AutoButtonColor = true,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 14) }),
	create("UIStroke", { Thickness = 3, Color = Color3.fromRGB(255, 160, 160), Transparency = 0.5 }),
})
rollButton.Parent = rollPanel

local autoRollLabel = create("TextLabel", {
	Position = UDim2.new(0, 0, 0, 244),
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 17,
	TextColor3 = Color3.fromRGB(180, 180, 200),
	Text = "",
}, {})
autoRollLabel.Parent = rollPanel

-- Odds line under the ROLL button (anticipation + honesty about the odds)
local oddsLabel = create("TextLabel", {
	Position = UDim2.new(0, 0, 0, 230),
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(200, 215, 255),
	Text = "",
}, {})
oddsLabel.Parent = rollPanel

local function currentLuck()
	if (ReplicatedStorage:GetAttribute("LuckRounds") or 0) > 0 then
		return ReplicatedStorage:GetAttribute("LuckMultiplier") or 3
	end
	return 1
end

local function oddsText()
	local luck = currentLuck()
	local parts = {}
	for _, tierName in ipairs(config.RarityOrder) do
		local pct = config.GetTierChance(tierName, luck) * 100
		table.insert(parts, (pct < 1 and "%s %.2f%%" or "%s %.1f%%"):format(tierName, pct))
	end
	return (luck > 1 and "🍀 " or "Odds: ") .. table.concat(parts, "  ·  ")
end

-- Luck chip: a single, optional offer shown only during the intermission pause,
-- and never to brand-new players.
local luckChip = create("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 62),
	Size = UDim2.fromOffset(300, 30),
	BackgroundColor3 = Color3.fromRGB(40, 120, 70),
	BackgroundTransparency = 0.15,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "",
	Visible = false,
	BorderSizePixel = 0,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 10) }),
})
luckChip.Parent = gui

local function updateLuckChip(show)
	local luckProduct
	if ProgressionConfig then
		for _, p in ipairs(ProgressionConfig.Products) do
			if p.Key == "ServerLuck" then
				luckProduct = p
			end
		end
	end
	local minRounds = ProgressionConfig and ProgressionConfig.Offers.MinRoundsBeforeOffers or 5
	local ready = show and PromptProduct and luckProduct and luckProduct.Id > 0
		and (player:GetAttribute("Rounds") or 0) >= minRounds
	luckChip.Visible = ready == true
	if ready then
		local left = ReplicatedStorage:GetAttribute("LuckRounds") or 0
		luckChip.Text = left > 0 and ("🍀 Server luck active: " .. left .. " left - tap to extend")
			or "🍀 Boost everyone's luck for 3 rounds"
	end
end

luckChip.Activated:Connect(function()
	if PromptProduct then
		PromptProduct:FireServer("ServerLuck")
	end
end)

-- Disaster banner
local banner = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -140),
	Size = UDim2.new(1, 0, 0, 110),
	BackgroundColor3 = Color3.fromRGB(255, 120, 40),
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	Visible = false,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 18) }),
	create("UIStroke", { Thickness = 3, Color = Color3.new(1, 1, 1), Transparency = 0.5 }),
})
banner.Parent = gui

local bannerEmoji = create("TextLabel", {
	Position = UDim2.new(0, 30, 0, 0),
	Size = UDim2.fromOffset(80, 110),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 54,
	Text = "🌪",
}, {})
bannerEmoji.Parent = banner

local bannerTitle = create("TextLabel", {
	Position = UDim2.new(0, 120, 0, 12),
	Size = UDim2.new(1, -140, 0, 50),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 40,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "DISASTER",
	TextXAlignment = Enum.TextXAlignment.Left,
}, {})
bannerTitle.Parent = banner

local bannerDesc = create("TextLabel", {
	Position = UDim2.new(0, 122, 0, 62),
	Size = UDim2.new(1, -140, 0, 34),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 20,
	TextColor3 = Color3.fromRGB(255, 245, 230),
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
}, {})
bannerDesc.Parent = banner

--------------------------------------------------------------------
-- Animation helpers
--------------------------------------------------------------------

local function popIn(panel, scale)
	panel.Visible = true
	scale.Scale = 0
	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function popOut(panel, scale)
	local tween = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Scale = 0,
	})
	tween:Play()
	tween.Completed:Once(function()
		panel.Visible = false
	end)
end

local function popLabel(label)
	local scale = label:FindFirstChild("PopScale")
	if not scale then
		scale = create("UIScale", { Scale = 1 })
		scale.Name = "PopScale"
		scale.Parent = label
	end
	scale.Scale = 1
	local pop = TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.25,
	})
	pop:Play()
	pop.Completed:Once(function()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end)
end

local function shakeBanner()
	task.spawn(function()
		local basePos = UDim2.new(0.5, 0, 0.22, 0)
		for i = 1, 6 do
			local offset = (i % 2 == 0) and 7 or -7
			banner.Position = UDim2.new(0.5, offset, 0.22, 0)
			task.wait(0.04)
		end
		banner.Position = basePos
	end)
end

local function cameraPunch()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local baseFov = camera.FieldOfView
	local out = TweenService:Create(camera, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = baseFov + 10,
	})
	out:Play()
	out.Completed:Once(function()
		TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = baseFov,
		}):Play()
	end)
end

local function hideAllPanels()
	if selectionPanel.Visible then
		popOut(selectionPanel, selectionScale)
	end
	if rollPanel.Visible then
		popOut(rollPanel, rollScale)
	end
end

--------------------------------------------------------------------
-- Round flow
--------------------------------------------------------------------

local rouletteActive = false
local spinActive = false

RoundStatus.OnClientEvent:Connect(function(phase, timeLeft)
	if phase == "Intermission" then
		statusLabel.Text = "🌀 Next disaster in " .. timeLeft .. "s..."
	end
	updateLuckChip(phase == "Intermission")
end)

SelectionStarted.OnClientEvent:Connect(function(names)
	hideAllPanels()
	luckChip.Visible = false
	statusLabel.Text = "🎯 Selecting the roller..."
	popIn(selectionPanel, selectionScale)
	drumroll:Play()

	rouletteActive = true
	task.spawn(function()
		local i = 1
		while rouletteActive do
			rouletteName.Text = names[((i - 1) % #names) + 1]
			tickSound:Play()
			i += 1
			task.wait(0.14)
		end
	end)
end)

PlayerSelected.OnClientEvent:Connect(function(chosenName)
	rouletteActive = false
	drumroll:Stop()

	rouletteName.Text = "🎉 " .. chosenName .. " 🎉"
	rouletteName.TextColor3 = GOLD
	playFanfare()
	doFlash(Color3.new(1, 1, 1), 0.45)

	statusLabel.Text = chosenName .. " will roll the dice!"

	if chosenName == player.Name then
		popOut(selectionPanel, selectionScale)
		task.wait(0.3)
		rollResult.Text = ""
		oddsLabel.Text = oddsText()
		rollButton.Visible = true
		autoRollLabel.Text = "Auto-roll in " .. config.RollTimeout .. "s"
		popIn(rollPanel, rollScale)

		task.spawn(function()
			for i = config.RollTimeout, 1, -1 do
				autoRollLabel.Text = "Auto-roll in " .. i .. "s"
				task.wait(1)
			end
			autoRollLabel.Text = ""
		end)
	else
		task.delay(3, function()
			if selectionPanel.Visible then
				popOut(selectionPanel, selectionScale)
			end
		end)
	end
end)

rollButton.MouseButton1Click:Connect(function()
	rollButton.Visible = false
	autoRollLabel.Text = ""
	diceSound:Play()
	RollRequested:FireServer()
end)

-- The spin itself is drawn by RollReel (LobbyUpgrade add-on): a sliding reel of rarity-coloured
-- cards for everyone. Here we only tidy away the roll panel when the spin starts.
RollStarted.OnClientEvent:Connect(function()
	spinActive = false
	if rollPanel.Visible then
		popOut(rollPanel, rollScale)
	end
end)

DisasterRevealed.OnClientEvent:Connect(function()
	spinActive = false
end)

DisasterStarted.OnClientEvent:Connect(function(disasterId)
	local disaster = config.GetDisasterById(disasterId)
	if not disaster then
		return
	end

	hideAllPanels()
	statusLabel.Text = "⚠️ " .. disaster.Name .. " incoming! Survive!"

	-- Switch from the calm music to the disaster music
	playDisasterMusic()

	banner.BackgroundColor3 = disaster.Color
	bannerEmoji.Text = disaster.Emoji
	bannerTitle.Text = string.upper(disaster.Name)
	bannerDesc.Text = disaster.Description
	banner.Position = UDim2.new(0.5, 0, 0, -140)
	banner.Visible = true

	whoosh:Play()
	doFlash(disaster.Color, 0.6)
	cameraPunch()

	TweenService:Create(banner, TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.22, 0),
	}):Play()
	shakeBanner()
end)

DisasterEnded.OnClientEvent:Connect(function()
	if banner.Visible then
		local tween = TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -140),
		})
		tween:Play()
		tween.Completed:Once(function()
			banner.Visible = false
		end)
	end
	statusLabel.Text = "🌴 The island is safe... for now."

	-- Back to the calm island music
	playCalmMusic()
end)