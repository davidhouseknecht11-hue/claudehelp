--[[
	DisasterConfig
	Shared configuration for the disaster selector system. Required by both server and client.
]]

local DisasterConfig = {}

-- Round timings (seconds)
DisasterConfig.IntermissionTime = 15
DisasterConfig.SelectionDuration = 5
DisasterConfig.RollTimeout = 10
DisasterConfig.RollSpinDuration = 3
DisasterConfig.RevealDuration = 2.5
DisasterConfig.DisasterDuration = 25

-- Rarity tiers. Multiplier scales the survival payout; RollerBonus is extra coins for the roller.
DisasterConfig.RarityOrder = { "Common", "Rare", "Mythic", "Transcendent" }
DisasterConfig.Rarities = {
	Common = { Name = "Common", Color = Color3.fromRGB(200, 205, 220), Multiplier = 1,   RollerBonus = 0 },
	Rare   = { Name = "Rare",   Color = Color3.fromRGB(90, 170, 255),  Multiplier = 1.5, RollerBonus = 40 },
	Mythic = { Name = "Mythic", Color = Color3.fromRGB(255, 80, 200),  Multiplier = 3,   RollerBonus = 150 },
	Transcendent = { Name = "Transcendent", Color = Color3.fromRGB(150, 255, 245), Multiplier = 10, RollerBonus = 1000 },
}

-- Transcendent disasters are this rare (1 in N rounds, before Server Luck / the weekly featured boost)
DisasterConfig.TranscendentOneIn = 10000

-- The disasters that can be rolled (Weight = relative chance; Luck boosts only non-Common)
DisasterConfig.Disasters = {
	{
		Id = "MeteorShower",
		Rarity = "Common",
		Weight = 100,
		Name = "Meteor Shower",
		Emoji = "☄️",
		Color = Color3.fromRGB(255, 120, 40),
		Description = "Meteors rain from the sky!",
	},
	{
		Id = "RisingFlood",
		Rarity = "Rare",
		Weight = 40,
		Name = "Rising Flood",
		Emoji = "🌊",
		Color = Color3.fromRGB(70, 150, 255),
		Description = "The water is rising! Get to high ground!",
	},
	{
		Id = "LightningStorm",
		Rarity = "Common",
		Weight = 100,
		Name = "Lightning Storm",
		Emoji = "⚡",
		Color = Color3.fromRGB(255, 230, 80),
		Description = "Lightning strikes the island!",
	},
	{
		Id = "Tsunami",
		Rarity = "Rare",
		Weight = 40,
		Name = "Tsunami",
		Emoji = "🌊",
		Color = Color3.fromRGB(20, 100, 220),
		Description = "A massive wave is coming — run from the shore!",
	},
	{
		Id = "DragonAttack",
		Rarity = "Rare",
		Weight = 40,
		Name = "Dragon Attack",
		Emoji = "🐉",
		Color = Color3.fromRGB(255, 100, 20),
		Description = "A dragon circles the island breathing fire — don't get burned!",
	},
	{
		Id = "Tornado",
		Rarity = "Rare",
		Weight = 40,
		Name = "Tornado",
		Emoji = "🌪️",
		Color = Color3.fromRGB(160, 160, 175),
		Description = "A raging tornado tears across the island!",
	},
	{
		Id = "VolcanicEruption",
		Rarity = "Rare",
		Weight = 40,
		Name = "Volcanic Eruption",
		Emoji = "🌋",
		Color = Color3.fromRGB(255, 80, 30),
		Description = "Lava geysers erupt from the ground — watch for the warning rings!",
	},
	{
		Id = "Earthquake",
		Rarity = "Common",
		Weight = 100,
		Name = "Earthquake",
		Emoji = "💥",
		Color = Color3.fromRGB(185, 135, 85),
		Description = "Shockwaves ripple across the island — jump to dodge them!",
	},
	{
		Id = "AcidRain",
		Rarity = "Common",
		Weight = 100,
		Name = "Acid Rain",
		Emoji = "☣️",
		Color = Color3.fromRGB(140, 255, 60),
		Description = "Corrosive rain falls — find cover!",
	},
	{
		Id = "SharkAttack",
		Rarity = "Rare",
		Weight = 40,
		Name = "Shark Attack",
		Emoji = "🦈",
		Color = Color3.fromRGB(30, 200, 180),
		Description = "A hungry shark hunts the water — stay on land!",
	},
	{
		Id = "Blizzard",
		Rarity = "Common",
		Weight = 100,
		Name = "Blizzard",
		Emoji = "❄️",
		Color = Color3.fromRGB(170, 225, 255),
		Description = "Ice shards rain down and the frost slows you!",
	},
	{
		Id = "Armageddon",
		Rarity = "Mythic",
		Weight = 3.6,
		Combo = { "MeteorShower", "LightningStorm" },
		Name = "Armageddon",
		Emoji = "☄️",
		Color = Color3.fromRGB(255, 60, 90),
		Description = "Meteors AND lightning — the sky is falling!",
	},
	{
		Id = "Hurricane",
		Rarity = "Mythic",
		Weight = 3.6,
		Combo = { "Tornado", "RisingFlood" },
		Name = "Hurricane",
		Emoji = "🌀",
		Color = Color3.fromRGB(110, 90, 255),
		Description = "A tornado and rising floodwater at the same time!",
	},
	{
		Id = "RingOfFire",
		Rarity = "Mythic",
		Weight = 3.6,
		Combo = { "VolcanicEruption", "Earthquake" },
		Name = "Ring of Fire",
		Emoji = "🔥",
		Color = Color3.fromRGB(255, 110, 0),
		Description = "Lava geysers AND shockwaves — keep moving!",
	},
	{
		Id = "Whiteout",
		Rarity = "Mythic",
		Weight = 3.6,
		Combo = { "Blizzard", "LightningStorm" },
		Name = "Whiteout",
		Emoji = "🌨️",
		Color = Color3.fromRGB(190, 230, 255),
		Description = "A blizzard AND a lightning storm — nowhere is safe!",
	},
	{
		Id = "Frostquake",
		Rarity = "Mythic",
		Weight = 3.6,
		Combo = { "Blizzard", "Earthquake" },
		Name = "Frostquake",
		Emoji = "🧊",
		Color = Color3.fromRGB(120, 190, 255),
		Description = "Ice shards AND shockwaves — keep moving!",
	},
	{
		-- Run by the LobbyUpgrade add-on (MoonCollision module) through DisasterGameManager's ExtraDisasters hook.
		-- Weight is set below so it comes up once every TranscendentOneIn rounds.
		Id = "MoonCollision",
		Rarity = "Transcendent",
		Weight = 0,
		Name = "Moon Collision",
		Emoji = "🌕",
		Color = Color3.fromRGB(230, 225, 210),
		Description = "The moon is falling! Get into a nuclear bunker - then harvest palm trees for oxygen!",
	},
}

do -- weight for 1-in-N: w / (others + w) = 1 / N  =>  w = others / (N - 1)
	local others, transcendent = 0, {}
	for _, d in ipairs(DisasterConfig.Disasters) do
		if d.Rarity == "Transcendent" then
			table.insert(transcendent, d)
		else
			others += d.Weight or 100
		end
	end
	for _, d in ipairs(transcendent) do
		d.Weight = others / (DisasterConfig.TranscendentOneIn - 1) / #transcendent
	end
end

function DisasterConfig.GetDisasterById(id)
	for _, disaster in ipairs(DisasterConfig.Disasters) do
		if disaster.Id == id then
			return disaster
		end
	end
	return nil
end

-- Weekly featured disaster. Rotates automatically (same answer on server and client).
-- It is WeightMultiplier times likelier, and pays CoinBonus extra coins when survived.
DisasterConfig.Event = {
	PeriodDays = 7,
	WeightMultiplier = 3,
	CoinBonus = 0.5,
	Rotation = { "Blizzard", "Tornado", "MeteorShower", "SharkAttack", "Earthquake",
		"LightningStorm", "AcidRain", "VolcanicEruption", "RisingFlood", "Tsunami", "DragonAttack" },
}

function DisasterConfig.GetFeaturedId()
	local E = DisasterConfig.Event
	local period = math.floor(os.time() / (86400 * E.PeriodDays))
	return E.Rotation[(period % #E.Rotation) + 1]
end

local function weightOf(d, luck, featuredId)
	local w = d.Weight or 100
	if (d.Rarity or "Common") ~= "Common" then
		w *= luck
	end
	if d.Id == featuredId then
		w *= DisasterConfig.Event.WeightMultiplier
	end
	return w
end

local function totalWeight(luck, featuredId)
	local total = 0
	for _, d in ipairs(DisasterConfig.Disasters) do
		total += weightOf(d, luck, featuredId)
	end
	return total
end

-- Weighted random pick. luck = 1 normally; a Server Luck Boost passes e.g. 3.
function DisasterConfig.PickDisaster(rng, luck)
	luck = luck or 1
	local featuredId = DisasterConfig.GetFeaturedId()
	local roll = rng:NextNumber() * totalWeight(luck, featuredId)
	local last
	for _, d in ipairs(DisasterConfig.Disasters) do
		roll -= weightOf(d, luck, featuredId)
		last = d
		if roll <= 0 then
			return d
		end
	end
	return last
end

-- Chance (0..1) that one specific disaster is rolled
function DisasterConfig.GetChance(id, luck)
	luck = luck or 1
	local d = DisasterConfig.GetDisasterById(id)
	if not d then
		return 0
	end
	local featuredId = DisasterConfig.GetFeaturedId()
	return weightOf(d, luck, featuredId) / totalWeight(luck, featuredId)
end

-- Chance (0..1) that a whole rarity tier is rolled
function DisasterConfig.GetTierChance(rarityName, luck)
	luck = luck or 1
	local sum = 0
	for _, d in ipairs(DisasterConfig.Disasters) do
		if (d.Rarity or "Common") == rarityName then
			sum += DisasterConfig.GetChance(d.Id, luck)
		end
	end
	return sum
end

return DisasterConfig