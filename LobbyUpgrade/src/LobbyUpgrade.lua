-- LobbyUpgrade  (Script)
-- Put in: ServerScriptService   (keep its children: KitLoader, KitAnimator, DisasterFX, ShopUI, ShopItems)
--
-- An ADD-ON. It does not replace any of your scripts:
--   * LobbyService still builds the lobby and runs all the lobby rules. This script waits for it,
--     then dresses the lobby up with the Blender kit and adds new things to do.
--   * DisasterGameManager still runs every disaster. This script listens to the same
--     ServerStorage.RoundEvents signal and adds sirens + a storm vortex over the island.
--   * DisasterFX (each player's screen): red title intro, extreme wind, weather, VFX and new
--     Blender looks for the hazards. The new tornado funnel goes in ServerStorage > TornadoAssets.
--   * ShopUI (each player's screen): the new card-style shop; ShopItems lists what it sells.
-- Delete this script and everything goes back to how it was.
--
-- Needs the Blender models: File > Import 3D > LobbyKit.glb (the model can stay in Workspace or
-- be moved to ServerStorage). Without the kit only the non-model extras appear.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Kit = require(script:WaitForChild("KitLoader"))

--------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------
local BONUS_CHEST_COINS = 20      -- coins for reaching the parkour chest (once per round per player)
local JUMP_PAD_POWER = 95         -- launch speed of the jump pads
local SIREN_COUNT = 4             -- sirens that rise on the island when a disaster starts
local VORTEX_HEIGHT = 95          -- studs above the island's highest ground
local ENABLE_DISASTER_ATMOSPHERE = true

local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local WHITE = Color3.new(1, 1, 1)
local CYAN = Color3.fromRGB(60, 230, 255)
local GOLD = Color3.fromRGB(255, 205, 70)

--------------------------------------------------------------------
-- Shared bits
--------------------------------------------------------------------
local hasKit = Kit.load()
if hasKit then
	print("[LobbyUpgrade] Blender kit loaded")
else
	warn("[LobbyUpgrade] LobbyKit not found - import LobbyKit.glb (File > Import 3D). Running without the models.")
end

-- Blender props the client scripts clone: shop icons, disaster effect pieces, new hazard looks
local CLIENT_PROPS = {
	"EggCommon", "EggRare", "EggMythic", "CoinsS", "CoinsM", "CoinsL", "CoinsXL",
	"Shield", "ReviveHeart", "Clover", "CoinX2", "Crown", "GiftBox", "TrailSwirl",
	"FxPlank", "FxRock", "FxMeteorChunk", "FxLeaf", "FxIceShard", "FxBolt", "FxShockRing", "FxWindStreak", "FxDroplet", "FxCloudPuff",
	"MeteorRock", "IceCrystal", "AcidBlob", "LavaBlob", "LavaPool", "QuakeSpike", "Shark", "TsunamiCurl",
	"Moon", "OxygenTank", "Sun", "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune",
}
local propsFolder = ReplicatedStorage:FindFirstChild("LobbyKitProps")
if not propsFolder then
	propsFolder = Instance.new("Folder")
	propsFolder.Name = "LobbyKitProps"
	propsFolder.Parent = ReplicatedStorage
end
if hasKit then
	-- tell the developer straight away when the imported LobbyKit is older than these scripts
	local missing = {}
	for _, name in ipairs(CLIENT_PROPS) do
		if not Kit.has(name) then
			table.insert(missing, name)
		end
	end
	for _, name in ipairs({ "Tornado", "Bunker" }) do
		if not Kit.has(name) then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		warn("[LobbyUpgrade] Your LobbyKit is missing " .. #missing .. " models (" .. table.concat(missing, ", ")
			.. "). Delete the old LobbyKit and import the latest LobbyKit.glb (File > Import 3D).")
	end
	Kit.publish(CLIENT_PROPS, propsFolder)
	-- New tornado funnel: TornadoDisaster already uses ServerStorage > TornadoAssets > Tornado when it exists
	-- (pieces named layer* spin). A tornado model you put there yourself is kept.
	local tornadoAssets = ServerStorage:FindFirstChild("TornadoAssets")
	if not tornadoAssets then
		tornadoAssets = Instance.new("Folder")
		tornadoAssets.Name = "TornadoAssets"
		tornadoAssets.Parent = ServerStorage
	end
	if not tornadoAssets:FindFirstChild("Tornado") then
		Kit.spawn("Tornado", CFrame.new(), { parent = tornadoAssets, shadows = false })
	end
end

-- client scripts + the shop list run on each player's device
-- Moon Collision (Transcendent): runs through DisasterGameManager's ExtraDisasters hook
do
	local moonModule = script:FindFirstChild("MoonCollision")
	if moonModule and hasKit then
		require(moonModule).init(Kit)
	elseif moonModule then
		warn("[LobbyUpgrade] Moon Collision needs the Blender kit (LobbyKit.glb) - disaster not registered")
	end
end

for _, name in ipairs({ "KitAnimator", "DisasterFX", "ShopUI", "ShopItems", "MoonFX" }) do
	local child = script:FindFirstChild(name)
	if child then
		child.Parent = ReplicatedStorage
	end
end

-- new Robux coin packs: added to ProgressionConfig.Products so ProgressionServer's existing
-- purchase code (ProcessReceipt, Kind = "Coins") pays them out
do
	local itemsModule = ReplicatedStorage:FindFirstChild("ShopItems")
	local configModule = ReplicatedStorage:FindFirstChild("ProgressionConfig")
	if itemsModule and configModule then
		local ok, err = pcall(function()
			require(itemsModule).AddProducts(require(configModule))
		end)
		if not ok then
			warn("[LobbyUpgrade] Could not add the new shop products: " .. tostring(err))
		end
	end
end

local function findOrCreateBindable(name)
	local b = ServerStorage:FindFirstChild(name)
	if not b then
		b = Instance.new("BindableEvent")
		b.Name = name
		b.Parent = ServerStorage
	end
	return b
end
local roundEvents = findOrCreateBindable("RoundEvents")
local awardEvent = findOrCreateBindable("AwardCoins")

local DisasterConfig
do
	local assets = ReplicatedStorage:WaitForChild("DisasterAssets", 10)
	local mod = assets and assets:FindFirstChild("DisasterConfig")
	if mod then
		local ok, result = pcall(require, mod)
		if ok then
			DisasterConfig = result
		end
	end
end

local function mk(class, props, parent)
	local inst = Instance.new(class)
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function ghost(parent, name, size, cf)
	-- invisible, non-solid helper part
	return mk("Part", {
		Name = name,
		Size = size,
		CFrame = cf,
		Anchored = true,
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	}, parent)
end

local function ns(...)
	local args = { ... }
	local points = {}
	for i = 1, #args, 2 do
		table.insert(points, NumberSequenceKeypoint.new(args[i], args[i + 1]))
	end
	return NumberSequence.new(points)
end

local function sparkleBurst(parent, position, color, count, speed)
	local p = ghost(parent, "Burst", Vector3.new(1, 1, 1), CFrame.new(position))
	local e = mk("ParticleEmitter", {
		Texture = TEX_SPARK,
		Color = ColorSequence.new(color, WHITE),
		Size = ns(0, 0.4, 0.2, 2.6, 1, 0),
		Transparency = ns(0, 0, 0.7, 0.2, 1, 1),
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -18, 0),
		Drag = 1.5,
		LightEmission = 1,
		LightInfluence = 0,
		Rate = 0,
		Enabled = false,
	}, p)
	e:Emit(count)
	local light = mk("PointLight", { Color = color, Range = 40, Brightness = 6 }, p)
	TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	Debris:AddItem(p, 3)
end

local function billboard(parent, adornee, sizeStuds, text, color)
	local gui = mk("BillboardGui", {
		Size = UDim2.fromScale(sizeStuds.X, sizeStuds.Y),
		Adornee = adornee,
		AlwaysOnTop = false,
		MaxDistance = 350,
		LightInfluence = 0,
	}, parent)
	local label = mk("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = text,
		TextColor3 = color,
		TextScaled = true,
		RichText = false,
	}, gui)
	mk("UIStroke", { Color = Color3.fromRGB(10, 12, 24), Thickness = 3 }, label)
	return gui, label
end

--------------------------------------------------------------------
-- LOBBY
--------------------------------------------------------------------
local setBanner = nil      -- set once the lobby banner exists
local chestClaimed = {}    -- [Player] = true (reset every round)

local function featuredText()
	if DisasterConfig and DisasterConfig.GetFeaturedId then
		local ok, id = pcall(DisasterConfig.GetFeaturedId)
		local d = ok and DisasterConfig.GetDisasterById(id)
		if d then
			local mult = DisasterConfig.Event and DisasterConfig.Event.WeightMultiplier or 3
			local bonus = DisasterConfig.Event and DisasterConfig.Event.CoinBonus or 0.5
			return ("⭐ FEATURED THIS WEEK ⭐\n%s %s  •  %dx chance  •  +%d%% coins"):format(d.Emoji, string.upper(d.Name), mult, math.floor(bonus * 100 + 0.5)), d.Color
		end
	end
	return "⭐ SURVIVE THE DISASTERS ⭐\nCollect coins while you wait", GOLD
end

local function upgradeLobby()
	local lobby = workspace:WaitForChild("Lobby", 60)
	if not lobby then
		warn("[LobbyUpgrade] workspace.Lobby never appeared (is LobbyService running?) - lobby upgrade skipped")
		return
	end
	local origin = lobby:GetAttribute("Origin")
	local waited = 0
	while typeof(origin) ~= "Vector3" and waited < 10 do
		waited += task.wait(0.2)
		origin = lobby:GetAttribute("Origin")
	end
	if typeof(origin) ~= "Vector3" then
		warn("[LobbyUpgrade] Lobby has no Origin attribute - lobby upgrade skipped")
		return
	end
	lobby:WaitForChild("LobbyCoin", 10)
	task.wait(0.5) -- let LobbyService finish building

	local floorY = origin.Y + 1 -- top of the lobby floor
	local deco = mk("Folder", { Name = "LobbyUpgrade" }, workspace)

	local function P(x, y, z)
		return Vector3.new(origin.X + x, floorY + y, origin.Z + z)
	end
	local function facing(pos) -- stands at pos, looks at the middle of the lobby
		return CFrame.lookAt(pos, Vector3.new(origin.X, pos.Y, origin.Z))
	end
	local function spawn(name, cf, opts)
		opts = opts or {}
		opts.parent = deco
		return Kit.spawn(name, cf, opts)
	end

	-- 1) New deck: floating sky island with glowing rings, fence and crystals underneath.
	--    The old floor and rails stay as (invisible) collision.
	if spawn("Hub", CFrame.new(P(0, 0.05, 0))) then
		for _, c in ipairs(lobby:GetChildren()) do
			if c:IsA("BasePart") and (c.Name == "Floor" or c.Name == "Rail") then
				c.Transparency = 1
			end
		end
	end

	-- 2) Kiosks become real little buildings (the old blocks keep their prompts, just hidden)
	for oldName, propName in pairs({
		ShopKiosk = "KioskShop",
		QuestKiosk = "KioskQuests",
		DailyKiosk = "KioskDaily",
		BoardKiosk = "KioskBoard",
	}) do
		local base = lobby:FindFirstChild(oldName)
		if base and base:IsA("BasePart") then
			local pos = Vector3.new(base.Position.X, floorY, base.Position.Z)
			if spawn(propName, facing(pos)) then
				base.Transparency = 1
				local top = lobby:FindFirstChild(oldName .. "Top")
				if top and top:IsA("BasePart") then
					top.Transparency = 1
				end
				local bb = base:FindFirstChildOfClass("BillboardGui")
				if bb then
					bb.StudsOffset = Vector3.new(0, 18, 0)
					bb.Size = UDim2.fromOffset(240, 64)
					bb.MaxDistance = 220
				end
			end
			mk("PointLight", { Color = base.Color, Range = 26, Brightness = 1.4 }, base)
		end
	end

	-- 3) Frames + lights around the three wall signs
	for _, signName in ipairs({ "WelcomeSign", "StatusBoard", "LeaderboardSign" }) do
		local sign = lobby:FindFirstChild(signName)
		if sign and sign:IsA("BasePart") then
			spawn("SignFrame", facing(Vector3.new(sign.Position.X, floorY, sign.Position.Z)))
			mk("SurfaceLight", { Face = Enum.NormalId.Front, Color = CYAN, Range = 18, Brightness = 1.2, Angle = 120 }, sign)
		end
	end

	-- 4) Crystal lamp pillars around the edge
	for _, xz in ipairs({ { 54, 54 }, { -54, 54 }, { 54, -54 }, { -54, -54 }, { 54, 34 }, { -54, 34 }, { 54, -34 }, { -54, -34 }, { 34, -54 }, { -34, -54 } }) do
		local pillar = spawn("Pillar", CFrame.new(P(xz[1], 0, xz[2])), { motion = nil })
		local crystal = pillar and pillar:FindFirstChild("crystal")
		if crystal then
			mk("PointLight", { Color = CYAN, Range = 26, Brightness = 1.3 }, crystal)
		end
	end

	-- 5) Centrepiece: floating mini island with a spinning tornado, orbit rings and a meteor,
	--    a light beam you can see from the island, and a banner with the featured disaster.
	spawn("Holo", CFrame.new(P(0, 10, 0)))
	mk("Part", {
		Name = "SkyBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(420, 4, 4),
		CFrame = CFrame.new(P(0, 48 + 210, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = CYAN,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	}, deco)

	local bannerPart = ghost(deco, "FeaturedBanner", Vector3.new(1, 1, 1), CFrame.new(P(0, 56, 0)))
	local _, bannerLabel = billboard(bannerPart, bannerPart, Vector2.new(54, 11), "", GOLD)
	local function showFeatured()
		local text, color = featuredText()
		bannerLabel.Text = text
		bannerLabel.TextColor3 = color:Lerp(WHITE, 0.25)
	end
	showFeatured()
	setBanner = function(disasterId)
		local d = disasterId and DisasterConfig and DisasterConfig.GetDisasterById(disasterId)
		if d then
			bannerLabel.Text = ("🔴 HAPPENING NOW 🔴\n%s %s"):format(d.Emoji, string.upper(d.Name))
			bannerLabel.TextColor3 = d.Color:Lerp(WHITE, 0.25)
		else
			showFeatured()
		end
	end

	-- gentle sparkles drifting up from the whole deck
	local sparkPart = ghost(deco, "DeckSparkles", Vector3.new(110, 1, 110), CFrame.new(P(0, 0.5, 0)))
	mk("ParticleEmitter", {
		Texture = TEX_SPARK,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, CYAN),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 210)),
			ColorSequenceKeypoint.new(1, GOLD),
		}),
		Size = ns(0, 0, 0.3, 0.9, 1, 0),
		Transparency = ns(0, 0.2, 1, 1),
		Lifetime = NumberRange.new(3, 6),
		Rate = 14,
		Speed = NumberRange.new(1.5, 4),
		SpreadAngle = Vector2.new(15, 15),
		EmissionDirection = Enum.NormalId.Top,
		LightEmission = 1,
		LightInfluence = 0,
		RotSpeed = NumberRange.new(-60, 60),
	}, sparkPart)

	-- 6) Scenery: bobbing islands and two hot-air balloons circling the lobby
	for i, v in ipairs({ { 105, 6, -70, 1.6 }, { -110, -8, -40, 2.1 }, { -95, 16, 80, 1.3 }, { 100, -4, 75, 1.8 }, { 20, 20, -120, 1.5 }, { -30, -12, 118, 1.2 } }) do
		spawn("FloatIsland", CFrame.new(P(v[1], v[2], v[3])) * CFrame.Angles(0, i * 1.3, 0), {
			scale = v[4],
			motion = { kind = "bob", amp = 2.5, speed = 0.45, phase = i * 1.1 },
		})
	end
	spawn("Balloon", CFrame.new(P(96, 46, 0)), {
		motion = { kind = "orbit", center = P(0, 46, 0), radius = 96, speed = 5, amp = 3, phase = 0 },
	})
	local blue = spawn("Balloon", CFrame.new(P(-122, 62, 0)), {
		scale = 1.25,
		motion = { kind = "orbit", center = P(0, 62, 0), radius = 122, speed = -3.5, amp = 4, phase = 3.1 },
	})
	if blue and blue:FindFirstChild("envelope") then
		blue.envelope.Color = Color3.fromRGB(70, 130, 255)
	end

	-- 7) Parkour: stepping stones up to a floating island with a bonus chest
	local useKitSteps = Kit.has("Step")
	local steps = { { 31, 3.5, -5 }, { 23, 7.5, -8 }, { 16, 11.5, -13 }, { 14, 15.5, -22 }, { 19, 19.5, -30 }, { 26, 23.5, -37 } }
	for i, s in ipairs(steps) do
		local top = P(s[1], s[2], s[3])
		spawn("Step", CFrame.new(top) * CFrame.Angles(0, i * 0.5, 0), { motion = nil })
		mk("Part", {
			Name = "StepCollision",
			Size = Vector3.new(6, 1, 6),
			CFrame = CFrame.new(top - Vector3.new(0, 0.5, 0)),
			Anchored = true,
			Transparency = useKitSteps and 1 or 0,
			Color = CYAN,
			Material = Enum.Material.Neon,
			CastShadow = false,
		}, deco)
	end
	local startLabel = ghost(deco, "ParkourLabel", Vector3.new(1, 1, 1), CFrame.new(P(31, 9, -5)))
	billboard(startLabel, startLabel, Vector2.new(14, 3), "⬆ PARKOUR → BONUS CHEST", GOLD).MaxDistance = 90

	local islandTop = P(40, 26.5, -40)
	local useKitIsland = spawn("FloatIsland", CFrame.new(islandTop), { scale = 1.5, name = "BonusIsland" }) ~= nil
	mk("Part", {
		Name = "BonusIslandCollision",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 23, 23),
		CFrame = CFrame.new(islandTop - Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Anchored = true,
		Transparency = useKitIsland and 1 or 0,
		Color = Color3.fromRGB(96, 200, 84),
		CastShadow = false,
	}, deco)

	local chestPos = P(41, 26.5, -42)
	local chestModel = spawn("Chest", facing(chestPos), { scale = 1.5 })
	local chestTrigger = mk("Part", {
		Name = "BonusChest",
		Size = Vector3.new(9, 6, 7),
		CFrame = facing(chestPos + Vector3.new(0, 3, 0)),
		Anchored = true,
		Transparency = chestModel and 1 or 0,
		Color = GOLD,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = true,
		CanQuery = false,
		CastShadow = false,
	}, deco)
	mk("PointLight", { Color = GOLD, Range = 22, Brightness = 2 }, chestTrigger)
	local chestSparks = mk("ParticleEmitter", {
		Texture = TEX_SPARK,
		Color = ColorSequence.new(GOLD, WHITE),
		Size = ns(0, 0, 0.3, 1.2, 1, 0),
		Lifetime = NumberRange.new(1, 2),
		Rate = 6,
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(40, 40),
		EmissionDirection = Enum.NormalId.Top,
		LightEmission = 1,
		LightInfluence = 0,
	}, chestTrigger)
	local chestLabelPart = ghost(deco, "ChestLabel", Vector3.new(1, 1, 1), CFrame.new(chestPos + Vector3.new(0, 10, 0)))
	billboard(chestLabelPart, chestLabelPart, Vector2.new(13, 3.2), ("🎁 BONUS CHEST  +%d 🪙"):format(BONUS_CHEST_COINS), GOLD).MaxDistance = 160

	chestTrigger.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not player or not humanoid or humanoid.Health <= 0 or chestClaimed[player] then
			return
		end
		chestClaimed[player] = true
		awardEvent:Fire(player, BONUS_CHEST_COINS, "lobby_bonus_chest")
		chestSparks:Emit(60)
		sparkleBurst(deco, chestPos + Vector3.new(0, 5, 0), GOLD, 50, 28)
		local popPart = ghost(deco, "ChestPopup", Vector3.new(1, 1, 1), CFrame.new(chestPos + Vector3.new(0, 6, 0)))
		local popGui, popLabel = billboard(popPart, popPart, Vector2.new(12, 3), ("%s  +%d 🪙"):format(player.DisplayName, BONUS_CHEST_COINS), WHITE)
		popGui.AlwaysOnTop = true
		TweenService:Create(popPart, TweenInfo.new(1.6), { CFrame = popPart.CFrame + Vector3.new(0, 7, 0) }):Play()
		TweenService:Create(popLabel, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
		Debris:AddItem(popPart, 1.8)
	end)

	-- 8) Jump pads
	for _, xz in ipairs({ { -34, -34 }, { -34, 28 } }) do
		local pos = P(xz[1], 0, xz[2])
		local model = spawn("JumpPad", CFrame.new(pos))
		local pad = mk("Part", {
			Name = "JumpPad",
			Shape = model and Enum.PartType.Block or Enum.PartType.Cylinder,
			Size = model and Vector3.new(6.5, 2.4, 6.5) or Vector3.new(0.8, 7, 7),
			CFrame = model and CFrame.new(pos + Vector3.new(0, 1.2, 0)) or (CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))),
			Anchored = true,
			Transparency = model and 1 or 0.1,
			Color = Color3.fromRGB(90, 255, 140),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanTouch = true,
			CanQuery = false,
			CastShadow = false,
		}, deco)
		pad:SetAttribute("Power", JUMP_PAD_POWER)
		mk("PointLight", { Color = pad.Color, Range = 16, Brightness = 1.5 }, pad)
		CollectionService:AddTag(pad, "KitJumpPad")
	end

	-- 9) Star coins: a kit coin rides on every lobby coin (the plain coin is hidden on screen)
	if Kit.has("Coin") then
		for _, coin in ipairs(lobby:GetChildren()) do
			if coin.Name == "LobbyCoin" and coin:IsA("BasePart") then
				spawn("Coin", CFrame.new(coin.Position), { scale = 1.15, motion = { kind = "follow", target = coin } })
			end
		end
	end

	print("[LobbyUpgrade] Lobby upgraded")
end

--------------------------------------------------------------------
-- DISASTER ATMOSPHERE  (sirens + storm vortex + all-clear fireworks)
--------------------------------------------------------------------
local atmo = nil      -- { folder, vortexes = {}, sirens = { {model, upCF, downCF} } }
local atmoToken = 0
local rng = Random.new()

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
	if not lo then
		return nil
	end
	return lo, hi, ground
end

-- moves a prop smoothly between two CFrames (server side, a couple of seconds at most)
local function glide(model, fromCF, toCF, seconds, style, direction)
	local elapsed = 0
	while elapsed < seconds and model.Parent do
		elapsed += RunService.Heartbeat:Wait()
		local a = TweenService:GetValue(math.clamp(elapsed / seconds, 0, 1), style, direction)
		model:PivotTo(fromCF:Lerp(toCF, a))
	end
	if model.Parent then
		model:PivotTo(toCF)
	end
end

local function clearAtmosphere(old, instant)
	if not old then
		return
	end
	if instant then
		old.folder:Destroy()
		return
	end
	for _, vortex in ipairs(old.vortexes) do
		Kit.fade(vortex, false, 2.5)
	end
	for _, siren in ipairs(old.sirens) do
		task.spawn(glide, siren.model, siren.upCF, siren.downCF, 1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	Debris:AddItem(old.folder, 3.5)
end

local function startAtmosphere(disasterId)
	atmoToken += 1
	local token = atmoToken
	clearAtmosphere(atmo, true)
	atmo = nil

	local lo, hi, ground = islandBounds()
	if not lo then
		return
	end
	local d = DisasterConfig and disasterId and DisasterConfig.GetDisasterById(disasterId)
	local color = d and d.Color or Color3.fromRGB(255, 70, 70)
	local mythic = d and d.Rarity == "Mythic"
	local center = (lo + hi) / 2
	local span = math.max(hi.X - lo.X, hi.Z - lo.Z)

	local folder = mk("Folder", { Name = "DisasterAtmosphere" }, workspace)
	local state = { folder = folder, vortexes = {}, sirens = {} }
	atmo = state

	-- storm vortex spinning over the island, glowing in the disaster's colour
	local function addVortex(height, scale, tint, yaw)
		local vortex = Kit.spawn("StormRing", CFrame.new(center.X, hi.Y + height, center.Z) * CFrame.Angles(0, yaw, 0), {
			scale = scale,
			tint = tint,
			parent = folder,
			shadows = false,
			noCull = true,
		})
		if vortex then
			Kit.setTransparency(vortex, 1)
			Kit.fade(vortex, true, 3)
			table.insert(state.vortexes, vortex)
		end
		return vortex
	end
	local baseScale = math.clamp(span * 0.6 / 100, 0.8, 3)
	addVortex(VORTEX_HEIGHT, baseScale, color, 0)
	if mythic then
		addVortex(VORTEX_HEIGHT - 28, baseScale * 0.55, color:Lerp(WHITE, 0.5), 1)
	end

	-- lightning flickers inside the cloud
	task.spawn(function()
		while atmoToken == token and folder.Parent do
			task.wait(rng:NextNumber(1.5, 4.5))
			if atmoToken ~= token or not folder.Parent then
				break
			end
			for _, vortex in ipairs(state.vortexes) do
				local arms = vortex:FindFirstChild("arms" .. rng:NextInteger(0, 1))
				if arms then
					local oldColor, oldMaterial = arms.Color, arms.Material
					for _ = 1, 2 do
						arms.Color = color:Lerp(WHITE, 0.7)
						arms.Material = Enum.Material.Neon
						task.wait(0.07)
						arms.Color = oldColor
						arms.Material = oldMaterial
						task.wait(0.06)
					end
				end
			end
		end
	end)

	-- sirens burst out of the ground with spinning beacons
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ground }
	for i = 1, SIREN_COUNT do
		local angle = (i - 0.5) / SIREN_COUNT * math.pi * 2
		local x = center.X + math.cos(angle) * (hi.X - lo.X) * 0.3
		local z = center.Z + math.sin(angle) * (hi.Z - lo.Z) * 0.3
		local hit = workspace:Raycast(Vector3.new(x, hi.Y + 60, z), Vector3.new(0, -(hi.Y - lo.Y) - 120, 0), params)
		if hit then
			local scale = 1.4
			local upCF = CFrame.new(hit.Position) * CFrame.Angles(0, angle, 0)
			local downCF = upCF - Vector3.new(0, 26 * scale, 0)
			local siren = Kit.spawn("Siren", downCF, { scale = scale, tint = color, parent = folder })
			if siren then
				table.insert(state.sirens, { model = siren, upCF = upCF, downCF = downCF })
				local beacon = siren:FindFirstChild("beacon")
				if beacon then
					mk("PointLight", { Color = color, Range = 30, Brightness = 3 }, beacon)
					for _, face in ipairs({ Enum.NormalId.Right, Enum.NormalId.Left }) do
						mk("SpotLight", { Color = color, Face = face, Range = 60, Angle = 50, Brightness = 8 }, beacon)
					end
				end
				task.delay((i - 1) * 0.25, function()
					if atmoToken ~= token or not siren.Parent then
						return
					end
					local dust = ghost(folder, "SirenDust", Vector3.new(6, 1, 6), CFrame.new(hit.Position))
					mk("ParticleEmitter", {
						Texture = TEX_SMOKE,
						Color = ColorSequence.new(Color3.fromRGB(190, 175, 150)),
						Size = ns(0, 3, 1, 12),
						Transparency = ns(0, 0.4, 1, 1),
						Lifetime = NumberRange.new(1, 2),
						Speed = NumberRange.new(6, 16),
						SpreadAngle = Vector2.new(70, 70),
						EmissionDirection = Enum.NormalId.Top,
						Drag = 2,
						Rate = 0,
						Enabled = false,
					}, dust):Emit(24)
					Debris:AddItem(dust, 3)
					glide(siren, downCF, upCF, 1.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end)
			end
		end
	end
end

local function endAtmosphere()
	atmoToken += 1
	local old = atmo
	atmo = nil
	if not old then
		return
	end
	clearAtmosphere(old, false)

	-- all clear: fireworks over the island for the survivors
	local lo, hi = islandBounds()
	if not lo then
		return
	end
	local center = (lo + hi) / 2
	local colors = { GOLD, CYAN, Color3.fromRGB(255, 110, 210), Color3.fromRGB(120, 255, 140), Color3.fromRGB(255, 150, 60) }
	for i = 1, 7 do
		task.delay(0.4 + i * 0.3, function()
			local pos = Vector3.new(
				center.X + rng:NextNumber(-0.3, 0.3) * (hi.X - lo.X),
				hi.Y + rng:NextNumber(30, 60),
				center.Z + rng:NextNumber(-0.3, 0.3) * (hi.Z - lo.Z)
			)
			sparkleBurst(workspace, pos, colors[((i - 1) % #colors) + 1], 70, 45)
		end)
	end
end

--------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------
roundEvents.Event:Connect(function(kind, disasterId)
	if kind == "Started" then
		chestClaimed = {}
		if setBanner then
			setBanner(disasterId)
		end
		if ENABLE_DISASTER_ATMOSPHERE and hasKit then
			local ok, err = pcall(startAtmosphere, disasterId)
			if not ok then
				warn("[LobbyUpgrade] Disaster atmosphere failed: " .. tostring(err))
			end
		end
	elseif kind == "Ended" then
		if setBanner then
			setBanner(nil)
		end
		local ok, err = pcall(endAtmosphere)
		if not ok then
			warn("[LobbyUpgrade] Disaster atmosphere cleanup failed: " .. tostring(err))
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	chestClaimed[player] = nil
end)

task.spawn(function()
	local ok, err = pcall(upgradeLobby)
	if not ok then
		warn("[LobbyUpgrade] Lobby upgrade failed: " .. tostring(err))
	end
end)
