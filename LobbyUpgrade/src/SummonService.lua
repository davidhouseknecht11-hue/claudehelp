-- SummonService  (ModuleScript, child of the LobbyUpgrade script - server only)
--
-- Robux shop items handled by the add-on (ProgressionServer pays them out through its
-- ServerStorage > ExtraProductHandlers hook, only after the receipt is saved):
--   * Summon   - the buyer picks a disaster in the shop; the next roll lands on it.
--                Summons queue up: one per round, in the order they were bought.
--   * RobuxEgg - hatches one egg without spending coins (needs PetService's PetGrantHatch hook).
-- DisasterGameManager takes the next summon through ServerStorage > TakeSummon.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Summon = {}
local queue = {}   -- { { id = disasterId, buyer = display name } }
local pending = {} -- [Player] = disasterId they picked before buying
local remote

local function config()
	local assets = ReplicatedStorage:FindFirstChild("DisasterAssets")
	local mod = assets and assets:FindFirstChild("DisasterConfig")
	return mod and require(mod)
end

local function publishQueue()
	ReplicatedStorage:SetAttribute("SummonQueue", #queue)
end

local function bindable(parent, name, fn)
	local b = parent:FindFirstChild(name) or Instance.new("BindableFunction")
	b.Name = name
	b.OnInvoke = fn
	b.Parent = parent
	return b
end

function Summon.init()
	remote = ReplicatedStorage:FindFirstChild("SummonRemote") or Instance.new("RemoteEvent")
	remote.Name = "SummonRemote"
	remote.Parent = ReplicatedStorage

	-- the client says which disaster it wants right before the Robux prompt
	remote.OnServerEvent:Connect(function(player, action, id)
		local cfg = config()
		if action == "Choose" and type(id) == "string" and cfg and cfg.GetDisasterById(id) then
			pending[player] = id
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)

	local handlers = ServerStorage:FindFirstChild("ExtraProductHandlers") or Instance.new("Folder")
	handlers.Name = "ExtraProductHandlers"
	handlers.Parent = ServerStorage

	bindable(handlers, "Summon", function(player, product)
		local cfg = config()
		if not cfg then
			return nil
		end
		local def = pending[player] and cfg.GetDisasterById(pending[player])
		if not def or def.Rarity ~= product.Rarity then
			-- picked something of another tier (or nothing): a random disaster of the bought tier
			local tier = {}
			for _, d in ipairs(cfg.Disasters) do
				if d.Rarity == product.Rarity then
					table.insert(tier, d)
				end
			end
			def = tier[math.random(1, math.max(#tier, 1))]
		end
		if not def then
			return nil
		end
		pending[player] = nil
		table.insert(queue, { id = def.Id, buyer = player.DisplayName })
		publishQueue()
		remote:FireAllClients("Queued", def.Id, player.DisplayName, #queue)
		return ("🔮 %s summoned! It is #%d in line."):format(def.Name, #queue)
	end)

	bindable(handlers, "RobuxEgg", function(player, product)
		local grant = ServerStorage:FindFirstChild("PetGrantHatch")
		local res = grant and grant:Invoke(player, product.Egg)
		if res and res.ok then
			remote:FireClient(player, "Hatched", product.Egg, res)
			return nil
		end
		-- PetService isn't patched or the hatch failed: never lose a Robux purchase - pay the egg's coin price
		warn("[SummonService] Robux egg could not hatch (" .. tostring(res and res.err or "no PetGrantHatch") .. ") - paying coins instead")
		local api = ServerStorage:FindFirstChild("ProgressionAPI")
		local petConfig = ReplicatedStorage:FindFirstChild("PetConfig")
		local egg = petConfig and require(petConfig).GetEgg(product.Egg)
		if api and egg then
			api:Invoke("AddCoinsRaw", player, egg.Cost)
			return ("Couldn't hatch right now - you got 🪙 %d instead"):format(egg.Cost)
		end
		return nil
	end)

	-- DisasterGameManager asks for the next summoned disaster before rolling
	bindable(ServerStorage, "TakeSummon", function()
		local nextOne = table.remove(queue, 1)
		publishQueue()
		ReplicatedStorage:SetAttribute("SummonedBy", nextOne and nextOne.buyer or nil)
		return nextOne and nextOne.id or nil
	end)
	publishQueue()
end

return Summon
