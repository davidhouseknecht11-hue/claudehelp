-- ShopItems  (ModuleScript, child of the LobbyUpgrade script; moved to ReplicatedStorage at start)
--
-- Everything the new shop shows. Robux items point at ProgressionConfig.Products / Passes by Key,
-- so buying still goes through ProgressionServer exactly as before.
--
-- To sell for real: create the developer products / passes in Creator Hub (Monetization) and paste
-- their ids into ProgressionConfig (existing items) or NewProducts below (the two new coin packs).
-- While an id is 0 the card shows the `Robux` price written here and the server answers
-- "isn't set up yet". Once an id is set, the shop shows the real price from Roblox.

local ShopItems = {}

-- New coin packs. LobbyUpgrade adds these to ProgressionConfig.Products on the server (Kind "Coins"
-- is already paid out by ProgressionServer), and the shop adds them on each client for display.
ShopItems.NewProducts = {
	{ Key = "Coins6000", Id = 0, Kind = "Coins", Coins = 6000, Name = "6,000 Coins", Desc = "Instant coins" },
	{ Key = "Coins15000", Id = 0, Kind = "Coins", Coins = 15000, Name = "15,000 Coins", Desc = "Instant coins" },
}

-- Icon = Blender prop shown in the card (LobbyKitProps). Robux = price shown while the id is 0.
ShopItems.CoinPacks = {
	{ Key = "Coins500", Icon = "CoinsS", Badge = "Good Value", Robux = 25 },
	{ Key = "Coins2500", Icon = "CoinsM", Badge = "Better Value", Robux = 99 },
	{ Key = "Coins6000", Icon = "CoinsL", Badge = "Great Value", Robux = 199 },
	{ Key = "Coins15000", Icon = "CoinsXL", Badge = "Most Value", Robux = 399 },
}

ShopItems.Gear = {
	{ Key = "StreakSaver", Icon = "Shield", Line = "+1 Streak Saver", Robux = 35 },
	{ Key = "Revive", Icon = "ReviveHeart", Line = "+1 Revive", Robux = 25 },
	{ Key = "ServerLuck", Icon = "Clover", Line = "3x Server Luck", Robux = 99 },
}

ShopItems.Passes = {
	{ Key = "DoubleCoins", Icon = "CoinX2", Badge = "x2", Line = "coins from every round!", Robux = 149, Color = Color3.fromRGB(40, 140, 255) },
	{ Key = "VIP", Icon = "Crown", Badge = "VIP", Line = "rainbow trail + VIP perks", Robux = 249, Color = Color3.fromRGB(150, 80, 255) },
}

ShopItems.EggIcons = { CommonEgg = "EggCommon", RareEgg = "EggRare", MythicEgg = "EggMythic" }
ShopItems.EggColors = {
	CommonEgg = { Color3.fromRGB(120, 140, 170), Color3.fromRGB(70, 82, 110) },
	RareEgg = { Color3.fromRGB(60, 150, 255), Color3.fromRGB(30, 70, 190) },
	MythicEgg = { Color3.fromRGB(170, 80, 255), Color3.fromRGB(90, 30, 170) },
}
ShopItems.HatchCounts = { 1, 3, 10 }
ShopItems.TrailIcon = "TrailSwirl"
ShopItems.FreeIcon = "GiftBox"

-- Adds NewProducts to a ProgressionConfig table (skips keys that are already there)
function ShopItems.AddProducts(Config)
	for _, p in ipairs(ShopItems.NewProducts) do
		local found = false
		for _, existing in ipairs(Config.Products) do
			if existing.Key == p.Key then
				found = true
				break
			end
		end
		if not found then
			table.insert(Config.Products, table.clone(p))
		end
	end
end

return ShopItems
