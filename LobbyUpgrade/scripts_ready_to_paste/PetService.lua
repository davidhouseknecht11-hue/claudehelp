--[[
	PetService  (Script)
	Put in: ServerScriptService

	Server side of the pet system. The server decides everything - the client only asks:
	  * Hatching an egg: spends coins, rolls the pet with server RNG, saves it.
	  * Equipping / unequipping (max PetConfig.MaxEquipped).
	  * Health boost: when a disaster starts, every player's equipped pets add max health
	    (and matching current health). It is removed again when the round ends.

	Needs the patched ProgressionServer (it creates ServerStorage > ProgressionAPI, which
	is how this script spends coins and reads/writes the pets save data).

	Remotes created here (ReplicatedStorage > PetRemotes):
	  PetRequest (RemoteFunction)  client -> server: "State" | "Hatch", eggId | "Equip", petId | "Unequip", petId | "SetHidden", bool
	  PetBoost   (RemoteEvent)     server -> client: (hpAdded, disasterId) when a boost is applied
	Player attribute "EquippedPets" = "PetA,PetB,PetC" (replicates, so everyone can see your pets).
	Character attribute "PetHealthBoost" = HP currently added by pets.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PetConfig = require(ReplicatedStorage:WaitForChild("PetConfig"))
local DisasterConfig = require(ReplicatedStorage:WaitForChild("DisasterAssets"):WaitForChild("DisasterConfig"))

local API = ServerStorage:WaitForChild("ProgressionAPI", 20)
if not API then
	warn("[PetService] ServerStorage.ProgressionAPI not found - did you replace ProgressionServer with the patched version?")
	return
end
local roundEvents = ServerStorage:WaitForChild("RoundEvents")

-- Sanity check the config against the real disasters (prints a warning if an id is misspelled)
for petId, pet in pairs(PetConfig.Pets) do
	for disasterId in pairs(pet.Covers) do
		if not DisasterConfig.GetDisasterById(disasterId) then
			warn("[PetService] " .. petId .. " covers unknown disaster '" .. disasterId .. "'")
		end
	end
end

--------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "PetRemotes"
local Request = Instance.new("RemoteFunction")
Request.Name = "PetRequest"
Request.Parent = remotes
local BoostEvent = Instance.new("RemoteEvent")
BoostEvent.Name = "PetBoost"
BoostEvent.Parent = remotes
remotes.Parent = ReplicatedStorage

--------------------------------------------------------------------
-- Pet data (authoritative copy per player, written through to the ProgressionServer save)
--------------------------------------------------------------------
local cache = {}      -- [Player] = { Owned = { [petId] = true }, Equipped = { petId, ... } }
local busy = {}       -- [Player] = true while a hatch is being processed
local lastCall = {}   -- [Player] = os.clock() of the last request (simple rate limit)
local rng = Random.new()

local function sanitize(raw)
	local owned, equipped = {}, {}
	if type(raw) == "table" then
		if type(raw.Owned) == "table" then
			for id, value in pairs(raw.Owned) do
				if value and PetConfig.Pets[id] then
					owned[id] = true
				end
			end
		end
		if type(raw.Equipped) == "table" then
			for _, id in ipairs(raw.Equipped) do
				if type(id) == "string" and owned[id] and not table.find(equipped, id) and #equipped < PetConfig.MaxEquipped then
					table.insert(equipped, id)
				end
			end
		end
	end
	return { Owned = owned, Equipped = equipped, Hidden = type(raw) == "table" and raw.Hidden == true }
end

local function save(player)
	API:Invoke("SetPets", player, cache[player])
end

local function publishEquipped(player)
	local pets = cache[player]
	if pets then
		player:SetAttribute("EquippedPets", table.concat(pets.Equipped, ","))
	end
end

local function stateFor(player)
	local pets = cache[player]
	local owned, equipped = {}, {}
	for id in pairs(pets.Owned) do
		owned[id] = true
	end
	for _, id in ipairs(pets.Equipped) do
		table.insert(equipped, id)
	end
	return { ok = true, owned = owned, equipped = equipped, hidden = pets.Hidden == true }
end

local function loadPlayer(player)
	local raw
	for _ = 1, 120 do -- wait for the ProgressionServer to finish loading this player's save (up to ~60s)
		if not player.Parent then
			return
		end
		raw = API:Invoke("GetPets", player)
		if raw ~= nil then
			break
		end
		task.wait(0.5)
	end
	if raw == nil or not player.Parent then
		return
	end
	cache[player] = sanitize(raw)
	save(player) -- writes back the cleaned-up version
	publishEquipped(player)
end

--------------------------------------------------------------------
-- Hatching
--------------------------------------------------------------------
local function pickPet(egg)
	local total = 0
	for _, petId in ipairs(egg.Pets) do
		total = total + PetConfig.Pets[petId].Weight
	end
	local roll = rng:NextNumber() * total
	for _, petId in ipairs(egg.Pets) do
		roll = roll - PetConfig.Pets[petId].Weight
		if roll <= 0 then
			return petId
		end
	end
	return egg.Pets[#egg.Pets]
end

local function hatch(player, eggId, free)
	local egg = type(eggId) == "string" and PetConfig.GetEgg(eggId) or nil
	if not egg then
		return { ok = false, err = "BadRequest" }
	end
	if busy[player] then
		return { ok = false, err = "Busy" }
	end
	busy[player] = true

	local result
	local pets = cache[player]
	local petId = pickPet(egg) -- roll first, then charge; nothing is granted unless the payment goes through
	if not free and API:Invoke("Spend", player, egg.Cost) ~= true then -- free = already paid in Robux
		result = { ok = false, err = "NotEnoughCoins" }
	else
		local isNew = not pets.Owned[petId]
		local refund = 0
		local autoEquipped = false
		if isNew then
			pets.Owned[petId] = true
			if #pets.Equipped < PetConfig.MaxEquipped then
				table.insert(pets.Equipped, petId)
				autoEquipped = true
			end
		else
			refund = math.floor(egg.Cost * PetConfig.DuplicateRefundPct)
			if refund > 0 then
				API:Invoke("AddCoinsRaw", player, refund)
			end
		end
		save(player)
		publishEquipped(player)
		result = stateFor(player)
		result.petId = petId
		result.isNew = isNew
		result.refund = refund
		result.autoEquipped = autoEquipped
	end

	busy[player] = nil
	return result
end

--------------------------------------------------------------------
-- Equip / unequip
--------------------------------------------------------------------
local function equip(player, petId)
	local pets = cache[player]
	if type(petId) ~= "string" or not pets.Owned[petId] then
		return { ok = false, err = "NotOwned" }
	end
	if table.find(pets.Equipped, petId) then
		return stateFor(player)
	end
	if #pets.Equipped >= PetConfig.MaxEquipped then
		return { ok = false, err = "SlotsFull" }
	end
	table.insert(pets.Equipped, petId)
	save(player)
	publishEquipped(player)
	return stateFor(player)
end

local function unequip(player, petId)
	local pets = cache[player]
	local index = type(petId) == "string" and table.find(pets.Equipped, petId) or nil
	if index then
		table.remove(pets.Equipped, index)
		save(player)
		publishEquipped(player)
	end
	return stateFor(player)
end

-- Robux eggs (LobbyUpgrade shop): hatch without spending coins. Server-only.
do
	local grant = ServerStorage:FindFirstChild("PetGrantHatch") or Instance.new("BindableFunction")
	grant.Name = "PetGrantHatch"
	grant.OnInvoke = function(player, eggId)
		local waited = 0
		while busy[player] and waited < 5 do -- a coin hatch is still running
			waited += task.wait(0.1)
		end
		if not cache[player] then
			return { ok = false, err = "Loading" }
		end
		return hatch(player, eggId, true)
	end
	grant.Parent = ServerStorage
end

Request.OnServerInvoke = function(player, action, arg)
	if type(action) ~= "string" then
		return { ok = false, err = "BadRequest" }
	end
	local now = os.clock()
	if now - (lastCall[player] or 0) < 0.15 then
		return { ok = false, err = "Cooldown" }
	end
	lastCall[player] = now
	if not cache[player] then
		return { ok = false, err = "Loading" }
	end
	if action == "State" then
		return stateFor(player)
	elseif action == "Hatch" then
		return hatch(player, arg)
	elseif action == "Equip" then
		return equip(player, arg)
	elseif action == "Unequip" then
		return unequip(player, arg)
	elseif action == "SetHidden" then
		-- personal display setting: hide my own pets from my own screen (saved)
		cache[player].Hidden = arg == true
		save(player)
		return stateFor(player)
	end
	return { ok = false, err = "BadRequest" }
end

--------------------------------------------------------------------
-- Health boost during disasters
--   The boost is worked out once when the disaster starts (snapshot), so swapping pets
--   mid-round doesn't change anything until the next round.
--------------------------------------------------------------------
local activeDisaster = nil
local snapshot = {}  -- [Player] = HP to add this round
local boosted = {}   -- [Humanoid] = MaxHealth it had before the boost

local function applyBoost(player, announce)
	local total = snapshot[player]
	if not total or total <= 0 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or boosted[humanoid] then
		return
	end
	boosted[humanoid] = humanoid.MaxHealth
	humanoid.MaxHealth = humanoid.MaxHealth + total
	humanoid.Health = humanoid.Health + total
	character:SetAttribute("PetHealthBoost", total)
	if announce then
		BoostEvent:FireClient(player, total, activeDisaster)
	end
end

local function clearBoosts()
	for humanoid, baseMax in pairs(boosted) do
		boosted[humanoid] = nil
		if humanoid.Parent then
			humanoid.MaxHealth = baseMax
			if humanoid.Health > baseMax then
				humanoid.Health = baseMax
			end
			humanoid.Parent:SetAttribute("PetHealthBoost", nil)
		end
	end
	table.clear(snapshot)
	activeDisaster = nil
end

roundEvents.Event:Connect(function(kind, disasterId)
	if kind == "Started" then
		clearBoosts() -- safety: never stack on a round that didn't end cleanly
		activeDisaster = disasterId
		for _, player in ipairs(Players:GetPlayers()) do
			local pets = cache[player]
			if pets and #pets.Equipped > 0 then
				snapshot[player] = PetConfig.TotalHealth(pets.Equipped, disasterId)
				applyBoost(player, true)
			end
		end
	elseif kind == "Ended" then
		clearBoosts()
	end
end)

--------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------
local function onPlayer(player)
	task.spawn(loadPlayer, player)
	player.CharacterAdded:Connect(function(character)
		-- revived / respawned during a disaster: they still get their pets' boost
		if activeDisaster and snapshot[player] then
			character:WaitForChild("Humanoid", 5)
			applyBoost(player, false)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	cache[player] = nil
	busy[player] = nil
	lastCall[player] = nil
	snapshot[player] = nil
end)