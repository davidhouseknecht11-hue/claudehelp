-- ShopUI  (Script with RunContext = Client, child of the LobbyUpgrade script)
--
-- LobbyUpgrade moves this into ReplicatedStorage so it runs on every player's device.
-- It replaces the old list-style shop with big colourful cards (3D Blender icons):
--   Eggs (pet odds + Buy x1 / x3 / x10) - Coin Packs - Survival Gear - Boosts (passes) - Trails - Free Item
-- Nothing about buying changes: it uses the same remotes as before
-- (ProgressionRemotes for trails / passes / products / daily, PetRemotes for hatching).
-- Whenever the old Shop panel opens (menu button or lobby kiosk) it is closed and this one opens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Items = require(ReplicatedStorage:WaitForChild("ShopItems"))
local Config = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local PetConfig = require(ReplicatedStorage:WaitForChild("PetConfig"))
local PetModelBuilder = require(ReplicatedStorage:WaitForChild("PetModelBuilder"))
local remotes = ReplicatedStorage:WaitForChild("ProgressionRemotes")
local petRequest = ReplicatedStorage:WaitForChild("PetRemotes"):WaitForChild("PetRequest")
local props = ReplicatedStorage:WaitForChild("LobbyKitProps", 30)

Items.AddProducts(Config) -- so the new coin packs can be looked up here too

local DataUpdate = remotes:WaitForChild("DataUpdate")
local RequestData = remotes:WaitForChild("RequestData")
local BuyCosmetic = remotes:WaitForChild("BuyCosmetic")
local EquipCosmetic = remotes:WaitForChild("EquipCosmetic")
local ClaimDaily = remotes:WaitForChild("ClaimDaily")
local PromptPass = remotes:WaitForChild("PromptPass")
local PromptProduct = remotes:WaitForChild("PromptProduct")
local ShopOpened = remotes:WaitForChild("ShopOpened")
local Notify = remotes:WaitForChild("Notify")

--------------------------------------------------------------------
-- Style
--------------------------------------------------------------------
local C3 = Color3.fromRGB
local WHITE = C3(255, 255, 255)
local INK = C3(20, 18, 30)
local GREEN_TOP, GREEN_BOT = C3(120, 255, 70), C3(40, 200, 20)
local GREY_TOP, GREY_BOT = C3(170, 175, 190), C3(110, 115, 130)
local FONT = Enum.Font.FredokaOne
local TITLE_FONT = Enum.Font.LuckiestGuy
local ROBUX = utf8.char(0xE002) -- Roblox renders this as the Robux icon

local function mk(class, p, parent)
	local inst = Instance.new(class)
	for k, v in pairs(p) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end
local function corner(parent, px)
	return mk("UICorner", { CornerRadius = UDim.new(0, px or 14) }, parent)
end
local function stroke(parent, thickness, color)
	return mk("UIStroke", { Thickness = thickness or 3, Color = color or INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, parent)
end
local function gradient(parent, top, bottom, rotation)
	return mk("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90 }, parent)
end
local function text(parent, p)
	local base = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = WHITE,
		TextScaled = true,
	}
	for k, v in pairs(p) do
		if k ~= "StrokeThickness" then
			base[k] = v
		end
	end
	local l = mk("TextLabel", base, parent)
	stroke(l, p.StrokeThickness or 2.5)
	return l
end
local function fmt(n)
	local s = tostring(math.floor(n))
	while true do
		local k
		s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			return s
		end
	end
end

--------------------------------------------------------------------
-- 3D icons (ViewportFrames that slowly turn while the shop is open)
--------------------------------------------------------------------
local spinners = {}

local function viewport(parent, model, opts)
	opts = opts or {}
	local vp = mk("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = opts.size or UDim2.fromScale(1, 1),
		Position = opts.position or UDim2.new(),
		AnchorPoint = opts.anchor or Vector2.zero,
		Ambient = C3(170, 170, 185),
		LightColor = C3(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		ZIndex = opts.z or 3,
	}, parent)
	if not model then
		return vp
	end
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local cam = mk("Camera", { FieldOfView = 34 }, vp)
	vp.CurrentCamera = cam
	local dist = math.max(size.X, size.Y, size.Z) * (opts.zoom or 1.75)
	local facing = opts.facing or 1 -- 1: model front is +Z (kit props), -1: front is -Z (pets)
	local center = cf.Position
	cam.CFrame = CFrame.lookAt(center + Vector3.new(0, size.Y * 0.18, dist * facing), center)
	if opts.spin ~= false then
		table.insert(spinners, { model = model, base = model:GetPivot(), center = center, phase = math.random() * 6, speed = opts.speed or 0.6 })
	end
	return vp
end

local function kitModel(name, tint)
	local t = props and props:FindFirstChild(name)
	if not t then
		return nil
	end
	local m = t:Clone()
	if tint then
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
				d.Color = tint
			end
		end
	end
	return m
end

--------------------------------------------------------------------
-- Window
--------------------------------------------------------------------
local gui = mk("ScreenGui", { Name = "ShopUI", ResetOnSpawn = false, DisplayOrder = 20, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets }, playerGui)
local dim = mk("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false }, gui)
local window = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.94, 0.9),
	BackgroundColor3 = WHITE, -- the gradient below gives the colour
}, gui)
corner(window, 20)
stroke(window, 4, INK)
gradient(window, C3(58, 52, 110), C3(28, 26, 52))
mk("UISizeConstraint", { MaxSize = Vector2.new(900, 680) }, window)
local windowScale = mk("UIScale", { Scale = 1 }, window)

local header = mk("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1 }, window)
text(header, { Text = "SHOP", Font = TITLE_FONT, Size = UDim2.new(0.4, 0, 0, 46), Position = UDim2.fromOffset(20, 10), TextXAlignment = Enum.TextXAlignment.Left, StrokeThickness = 4 })
local coinsLabel = text(header, { Text = "🪙 0", Size = UDim2.new(0.3, 0, 0, 34), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -80, 0, 16), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C3(255, 220, 80) })
local close = mk("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(48, 44), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = true }, header)
corner(close, 12)
stroke(close, 3)
gradient(close, C3(255, 110, 110), C3(220, 40, 40))
text(close, { Text = "X", Font = TITLE_FONT, Size = UDim2.fromScale(1, 0.8), Position = UDim2.fromScale(0, 0.1) })

local scroll = mk("ScrollingFrame", {
	Position = UDim2.fromOffset(14, 70),
	Size = UDim2.new(1, -28, 1, -82),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	ScrollBarImageColor3 = C3(200, 200, 230),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, window)
mk("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, scroll)
mk("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 14) }, scroll)

--------------------------------------------------------------------
-- Toast + hatch results
--------------------------------------------------------------------
local toastLabel = text(window, { Visible = false, ZIndex = 50, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(0.8, 0, 0, 34), TextColor3 = C3(255, 120, 120) })
local toastToken = 0
local function toast(msg, color)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = msg
	toastLabel.TextColor3 = color or C3(255, 120, 120)
	toastLabel.Visible = true
	task.delay(2.4, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

local results = mk("Frame", { Visible = false, ZIndex = 40, Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(10, 8, 20), BackgroundTransparency = 0.25 }, window)
corner(results, 20)
local resultsTitle = text(results, { ZIndex = 41, Text = "YOU HATCHED", Font = TITLE_FONT, Size = UDim2.new(0.8, 0, 0, 44), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18), StrokeThickness = 4 })
local resultsGrid = mk("Frame", { ZIndex = 41, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 74), Size = UDim2.new(0.92, 0, 1, -150) }, results)
mk("UIGridLayout", { CellSize = UDim2.fromOffset(120, 150), CellPadding = UDim2.fromOffset(10, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }, resultsGrid)
local resultsOk = mk("TextButton", { ZIndex = 41, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(200, 54), BackgroundColor3 = WHITE, Text = "" }, results)
corner(resultsOk, 14)
stroke(resultsOk, 3)
gradient(resultsOk, GREEN_TOP, GREEN_BOT)
text(resultsOk, { ZIndex = 42, Text = "AWESOME!", Font = TITLE_FONT, Size = UDim2.fromScale(0.9, 0.7), Position = UDim2.fromScale(0.05, 0.15) })
resultsOk.Activated:Connect(function()
	results.Visible = false
end)

--------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------
local order = 0
local function nextOrder()
	order += 1
	return order
end

local function sectionTitle(label)
	local row = mk("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, scroll)
	mk("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = C3(120, 120, 160), BorderSizePixel = 0 }, row)
	local pill = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(260, 40), BackgroundColor3 = C3(50, 52, 74) }, row)
	corner(pill, 20)
	stroke(pill, 3)
	text(pill, { Text = label, Size = UDim2.fromScale(0.9, 0.72), Position = UDim2.fromScale(0.05, 0.14) })
end

-- green (or grey) button with a small caption above it, like "Buy x3"
local function buyButton(parent, p)
	local holder = mk("Frame", { BackgroundTransparency = 1, Size = p.size, Position = p.position or UDim2.new(), AnchorPoint = p.anchor or Vector2.zero, LayoutOrder = p.order or 0, ZIndex = 4 }, parent)
	local top = 0
	if p.caption then
		text(holder, { ZIndex = 5, Text = p.caption, Size = UDim2.new(1, 0, 0.3, 0), StrokeThickness = 2 })
		top = 0.32
	end
	local btn = mk("TextButton", { ZIndex = 4, Position = UDim2.fromScale(0, top), Size = UDim2.fromScale(1, 1 - top), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = true }, holder)
	corner(btn, 12)
	stroke(btn, 3)
	local grad = gradient(btn, GREEN_TOP, GREEN_BOT)
	local label = text(btn, { ZIndex = 5, Text = p.label, Font = TITLE_FONT, Size = UDim2.fromScale(0.86, 0.66), Position = UDim2.fromScale(0.07, 0.17), StrokeThickness = 3 })
	if p.onClick then
		btn.Activated:Connect(function()
			local s = mk("UIScale", { Scale = 0.92 }, btn)
			TweenService:Create(s, TweenInfo.new(0.12), { Scale = 1 }):Play()
			game:GetService("Debris"):AddItem(s, 0.2)
			p.onClick()
		end)
	end
	local api = { frame = holder }
	function api.set(labelText, enabled)
		label.Text = labelText
		grad.Color = enabled == false and ColorSequence.new(GREY_TOP, GREY_BOT) or ColorSequence.new(GREEN_TOP, GREEN_BOT)
	end
	return api
end

local function chip(parent, label, color, p)
	local f = mk("Frame", { ZIndex = 6, BackgroundColor3 = color, AnchorPoint = p.anchor or Vector2.new(0.5, 0.5), Position = p.position, Size = p.size }, parent)
	corner(f, 12)
	stroke(f, 3)
	text(f, { ZIndex = 7, Text = label, Size = UDim2.fromScale(0.88, 0.72), Position = UDim2.fromScale(0.06, 0.14) })
	return f
end

-- Robux price: the real one when the item has an id, otherwise the suggested one from ShopItems
local priceCache = {}
local function robuxPrice(id, infoType, fallback, apply)
	apply(ROBUX .. " " .. tostring(fallback))
	if not id or id <= 0 then
		return
	end
	task.spawn(function()
		local key = tostring(infoType) .. id
		if priceCache[key] == nil then
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
			priceCache[key] = ok and info and info.PriceInRobux or false
		end
		if priceCache[key] then
			apply(ROBUX .. " " .. tostring(priceCache[key]))
		end
	end)
end

local function findByKey(list, key)
	for _, v in ipairs(list) do
		if v.Key == key then
			return v
		end
	end
	return nil
end

--------------------------------------------------------------------
-- State
--------------------------------------------------------------------
local state = nil
local refreshers = {} -- functions re-run whenever new data arrives
local function refresh()
	if not state then
		return
	end
	coinsLabel.Text = "🪙 " .. fmt(state.Coins or 0)
	for _, f in ipairs(refreshers) do
		pcall(f)
	end
end

DataUpdate.OnClientEvent:Connect(function(snap)
	state = snap
	refresh()
end)

--------------------------------------------------------------------
-- Eggs
--------------------------------------------------------------------
local hatching = false
local ERRORS = { NotEnoughCoins = "Not enough coins!", Busy = "Hold on, still hatching...", Loading = "Still loading your pets...", Cooldown = "Slow down a little!" }

local function showResults(egg, list)
	for _, c in ipairs(resultsGrid:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	resultsTitle.Text = ("YOU HATCHED %d PET%s!"):format(#list, #list == 1 and "" or "S")
	for _, r in ipairs(list) do
		local pet = PetConfig.GetPet(r.petId)
		local tier = pet and PetConfig.GetTier(pet)
		local cell = mk("Frame", { ZIndex = 42, BackgroundColor3 = tier and tier.Color or GREY_BOT }, resultsGrid)
		corner(cell, 14)
		stroke(cell, 3)
		gradient(cell, WHITE, C3(120, 120, 140))
		local ok, model = pcall(PetModelBuilder.Build, r.petId, true)
		viewport(cell, ok and model or nil, { size = UDim2.new(1, 0, 0.7, 0), facing = -1, z = 43, zoom = 2 })
		text(cell, { ZIndex = 44, Text = pet and pet.Name or r.petId, Size = UDim2.new(0.92, 0, 0.14, 0), Position = UDim2.new(0.04, 0, 0.7, 0) })
		text(cell, { ZIndex = 44, Text = r.isNew and "NEW!" or ("+" .. fmt(r.refund or 0) .. " 🪙"), TextColor3 = r.isNew and C3(255, 230, 80) or C3(200, 220, 255), Size = UDim2.new(0.8, 0, 0.13, 0), Position = UDim2.new(0.1, 0, 0.85, 0) })
	end
	results.Visible = true
end

local function hatch(egg, count)
	if hatching then
		return
	end
	if state and (state.Coins or 0) < egg.Cost * count then
		toast(("You need 🪙 %s for %d %s%s"):format(fmt(egg.Cost * count), count, egg.Name, count > 1 and "s" or ""))
		return
	end
	hatching = true
	local got = {}
	local lastErr
	for _ = 1, count do
		local ok, res = pcall(petRequest.InvokeServer, petRequest, "Hatch", egg.Id)
		if ok and res and not res.ok and res.err == "Cooldown" then
			task.wait(0.25) -- PetService allows one request every 0.15 s
			ok, res = pcall(petRequest.InvokeServer, petRequest, "Hatch", egg.Id)
		end
		if not ok or not res or not res.ok then
			lastErr = ok and res and res.err or "Error"
			break
		end
		table.insert(got, res)
		task.wait(0.18)
	end
	hatching = false
	if #got > 0 then
		showResults(egg, got)
	end
	if lastErr then
		toast(ERRORS[lastErr] or "Couldn't hatch right now.")
	end
	RequestData:FireServer() -- coins changed
end

local function eggCard(egg)
	local colors = Items.EggColors[egg.Id] or { C3(120, 140, 170), C3(70, 82, 110) }
	local card = mk("Frame", { Size = UDim2.new(1, 0, 0, 230), BackgroundColor3 = WHITE, LayoutOrder = nextOrder() }, scroll)
	corner(card, 18)
	stroke(card, 4)
	gradient(card, colors[1], colors[2])

	viewport(card, kitModel(Items.EggIcons[egg.Id] or "EggCommon"), { size = UDim2.new(0.24, 0, 0.92, 0), position = UDim2.new(0.01, 0, 0.04, 0), zoom = 1.45, speed = 0.8 })
	chip(card, string.upper(egg.Name), colors[2]:Lerp(INK, 0.3), { anchor = Vector2.new(0, 0), position = UDim2.fromOffset(12, 10), size = UDim2.fromOffset(170, 32) })

	-- odds row
	local row = mk("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.26, 0, 0, 10), Size = UDim2.new(0.73, 0, 0, 112) }, card)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.015, 0), HorizontalAlignment = Enum.HorizontalAlignment.Right }, row)
	for i, odd in ipairs(PetConfig.EggOdds(egg.Id)) do
		local pet = PetConfig.GetPet(odd.PetId)
		local slot = mk("Frame", { Size = UDim2.new(0.185, 0, 1, 0), BackgroundColor3 = INK, BackgroundTransparency = 0.55, LayoutOrder = i }, row)
		corner(slot, 10)
		local slotStroke = stroke(slot, i == 5 and 4 or 2, i == 5 and WHITE or C3(10, 10, 20))
		if i == 5 then -- the chase pet gets a rainbow frame
			local g = mk("UIGradient", { Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, C3(255, 60, 60)), ColorSequenceKeypoint.new(0.25, C3(255, 220, 60)),
				ColorSequenceKeypoint.new(0.5, C3(60, 255, 120)), ColorSequenceKeypoint.new(0.75, C3(60, 160, 255)),
				ColorSequenceKeypoint.new(1, C3(220, 80, 255)) }) }, slotStroke)
			table.insert(spinners, { gradient = g })
		end
		local ok, model = pcall(PetModelBuilder.Build, odd.PetId, true)
		viewport(slot, ok and model or nil, { size = UDim2.new(1, 0, 0.78, 0), position = UDim2.fromScale(0, 0.06), facing = -1, zoom = 2.1, speed = 0.5 })
		text(slot, { ZIndex = 6, Text = ("%g%%"):format(math.floor(odd.Percent * 10 + 0.5) / 10), TextColor3 = C3(255, 230, 90), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.9, 0, 0.2, 0) })
		local pill = mk("Frame", { ZIndex = 6, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(0.92, 0, 0.24, 0), BackgroundColor3 = C3(30, 30, 40), BackgroundTransparency = 0.2 }, slot)
		corner(pill, 10)
		text(pill, { ZIndex = 7, Text = "❤ +" .. (pet and pet.Boost or 0) .. " HP", TextColor3 = C3(140, 255, 140), Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1) })
	end

	-- buy buttons
	local buttons = mk("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.26, 0, 0, 132), Size = UDim2.new(0.73, 0, 0, 88) }, card)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.02, 0), HorizontalAlignment = Enum.HorizontalAlignment.Right }, buttons)
	local apis = {}
	for i, count in ipairs(Items.HatchCounts) do
		apis[count] = buyButton(buttons, {
			order = i,
			size = UDim2.new(0.32, 0, 1, 0),
			caption = "Buy x" .. count,
			label = "🪙 " .. fmt(egg.Cost * count),
			onClick = function()
				hatch(egg, count)
			end,
		})
	end
	table.insert(refreshers, function()
		for count, api in pairs(apis) do
			api.set("🪙 " .. fmt(egg.Cost * count), (state.Coins or 0) >= egg.Cost * count)
		end
	end)
end

--------------------------------------------------------------------
-- Robux cards
--------------------------------------------------------------------
local function cardRow(height)
	local row = mk("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, scroll)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.015, 0), HorizontalAlignment = Enum.HorizontalAlignment.Center }, row)
	return row
end

local BADGE_COLORS = { C3(40, 140, 255), C3(255, 60, 140), C3(255, 160, 20), C3(170, 60, 255) }

local function productCard(row, count, i, item, top, bottom)
	local def = findByKey(Config.Products, item.Key)
	if not def then
		return
	end
	local card = mk("Frame", { Size = UDim2.new(1 / count - 0.015, 0, 1, 0), BackgroundColor3 = WHITE, LayoutOrder = i }, row)
	corner(card, 16)
	stroke(card, 4)
	gradient(card, top, bottom)
	local hasBadge = item.Badge ~= nil
	if hasBadge then
		chip(card, item.Badge, BADGE_COLORS[i] or BADGE_COLORS[1], { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 8), size = UDim2.new(0.86, 0, 0, 32) })
	end
	viewport(card, kitModel(item.Icon), { size = UDim2.new(0.9, 0, 0.44, 0), position = UDim2.new(0.05, 0, hasBadge and 0.17 or 0.06, 0), zoom = 1.6 })
	local pill = mk("Frame", { ZIndex = 4, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.63, 0), Size = UDim2.new(0.86, 0, 0.12, 0), BackgroundColor3 = INK, BackgroundTransparency = 0.45 }, card)
	corner(pill, 12)
	local line = item.Line or (def.Kind == "Coins" and ("+" .. fmt(def.Coins) .. " Coins") or def.Name)
	text(pill, { ZIndex = 5, Text = line, Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1) })
	local btn = buyButton(card, {
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -10),
		size = UDim2.new(0.86, 0, 0.18, 0),
		label = ROBUX,
		onClick = function()
			PromptProduct:FireServer(item.Key)
		end,
	})
	robuxPrice(def.Id, Enum.InfoType.Product, item.Robux, function(s)
		btn.set(s, true)
	end)
	return card
end

local function passCard(row, i, item)
	local def = findByKey(Config.Passes, item.Key)
	if not def then
		return
	end
	local card = mk("Frame", { Size = UDim2.new(0.485, 0, 1, 0), BackgroundColor3 = WHITE, LayoutOrder = i }, row)
	corner(card, 16)
	stroke(card, 4)
	gradient(card, item.Color:Lerp(WHITE, 0.25), item.Color:Lerp(INK, 0.25))
	local circle = mk("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.04, 0, 0.5, 0), Size = UDim2.fromScale(0.4, 0.85), BackgroundColor3 = WHITE, BackgroundTransparency = 0.7 }, card)
	mk("UIAspectRatioConstraint", { AspectRatio = 1 }, circle)
	corner(circle, 999)
	viewport(circle, kitModel(item.Icon), { zoom = 1.5 })
	chip(circle, item.Badge, C3(50, 52, 74), { anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, 4), size = UDim2.new(0.6, 0, 0.24, 0) })
	text(card, { Text = def.Name, Font = TITLE_FONT, Position = UDim2.new(0.48, 0, 0.1, 0), Size = UDim2.new(0.48, 0, 0.24, 0) })
	text(card, { Text = item.Line, Position = UDim2.new(0.48, 0, 0.36, 0), Size = UDim2.new(0.48, 0, 0.17, 0) })
	local btn = buyButton(card, {
		position = UDim2.new(0.5, 0, 0.6, 0),
		size = UDim2.new(0.44, 0, 0.3, 0),
		label = ROBUX,
		onClick = function()
			if not (state and state.Passes and state.Passes[item.Key]) then
				PromptPass:FireServer(item.Key)
			end
		end,
	})
	local priceText = ROBUX .. " " .. item.Robux
	robuxPrice(def.Id, Enum.InfoType.GamePass, item.Robux, function(s)
		priceText = s
		btn.set(s, not (state and state.Passes and state.Passes[item.Key]))
	end)
	table.insert(refreshers, function()
		local owned = state.Passes and state.Passes[item.Key]
		btn.set(owned and "Owned!" or priceText, not owned)
	end)
end

--------------------------------------------------------------------
-- Trails (coins)
--------------------------------------------------------------------
local function trailCards()
	local grid = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder() }, scroll)
	mk("UIGridLayout", { CellSize = UDim2.new(0.235, 0, 0, 200), CellPadding = UDim2.new(0.018, 0, 0, 12), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, c in ipairs(Config.Cosmetics) do
		local card = mk("Frame", { BackgroundColor3 = WHITE, LayoutOrder = i }, grid)
		corner(card, 16)
		stroke(card, 4)
		gradient(card, c.Color1:Lerp(INK, 0.15), c.Color2:Lerp(INK, 0.55))
		viewport(card, kitModel(Items.TrailIcon, c.Color1), { size = UDim2.new(0.9, 0, 0.5, 0), position = UDim2.new(0.05, 0, 0.04, 0), zoom = 1.5 })
		text(card, { Text = c.Name, Position = UDim2.new(0.05, 0, 0.55, 0), Size = UDim2.new(0.9, 0, 0.14, 0) })
		local btn = buyButton(card, {
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -10),
			size = UDim2.new(0.86, 0, 0.22, 0),
			label = "",
			onClick = function()
				if not state then
					return
				end
				if state.Owned and state.Owned[c.Id] then
					EquipCosmetic:FireServer(state.Equipped == c.Id and "" or c.Id)
				elseif c.RequiresPass then
					PromptPass:FireServer(c.RequiresPass)
				elseif c.IndexReward then
					toast(c.IndexReward, C3(200, 220, 255))
				else
					BuyCosmetic:FireServer(c.Id)
				end
			end,
		})
		table.insert(refreshers, function()
			if state.Owned and state.Owned[c.Id] then
				btn.set(state.Equipped == c.Id and "Equipped" or "Equip", state.Equipped ~= c.Id)
			elseif c.RequiresPass then
				btn.set(c.RequiresPass .. " pass", true)
			elseif c.IndexReward then
				btn.set("🔒 Index", false)
			else
				btn.set("🪙 " .. fmt(c.Price), (state.Coins or 0) >= c.Price)
			end
		end)
	end
end

--------------------------------------------------------------------
-- Free item (the daily reward)
--------------------------------------------------------------------
local function freeCard()
	sectionTitle("Free Item")
	local card = mk("Frame", { Size = UDim2.new(0.7, 0, 0, 170), BackgroundColor3 = WHITE, LayoutOrder = nextOrder() }, scroll)
	corner(card, 18)
	stroke(card, 4)
	gradient(card, C3(80, 190, 255), C3(20, 110, 230))
	local circle = mk("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.03, 0, 0.5, 0), Size = UDim2.fromScale(0.3, 0.85), BackgroundColor3 = WHITE, BackgroundTransparency = 0.6 }, card)
	mk("UIAspectRatioConstraint", { AspectRatio = 1 }, circle)
	corner(circle, 999)
	viewport(circle, kitModel(Items.FreeIcon), { zoom = 1.5 })
	local dayChip = chip(circle, "Day 1", C3(50, 52, 74), { anchor = Vector2.new(0, 1), position = UDim2.new(0.02, 0, 1, 0), size = UDim2.new(0.5, 0, 0.24, 0) })
	text(card, { Text = "Free Coins!", Font = TITLE_FONT, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0.36, 0, 0.08, 0), Size = UDim2.new(0.6, 0, 0.22, 0) })
	text(card, { Text = "Claim your daily reward!", TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0.36, 0, 0.32, 0), Size = UDim2.new(0.6, 0, 0.14, 0) })
	local amount = text(card, { Text = "🪙 0", TextColor3 = C3(140, 255, 120), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0.36, 0, 0.47, 0), Size = UDim2.new(0.4, 0, 0.13, 0) })
	local claimed = text(card, { Text = "Claimed!", Font = TITLE_FONT, TextColor3 = C3(180, 255, 140), Position = UDim2.new(0.5, 0, 0.62, 0), Size = UDim2.new(0.45, 0, 0.3, 0), StrokeThickness = 3 })
	local btn = buyButton(card, {
		position = UDim2.new(0.55, 0, 0.62, 0),
		size = UDim2.new(0.38, 0, 0.3, 0),
		label = "CLAIM!",
		onClick = function()
			ClaimDaily:FireServer()
		end,
	})
	local btnFrame = btn.frame
	table.insert(refreshers, function()
		amount.Text = "🪙 " .. fmt(state.DailyReward or 0)
		dayChip:FindFirstChildOfClass("TextLabel").Text = "Day " .. tostring(state.DailyDay or 1)
		btnFrame.Visible = state.DailyReady == true
		claimed.Visible = state.DailyReady ~= true
		btn.set("CLAIM!", true)
	end)
end

--------------------------------------------------------------------
-- Build the page
--------------------------------------------------------------------
sectionTitle("Eggs")
for _, egg in ipairs(PetConfig.Eggs) do
	eggCard(egg)
end

sectionTitle("Coin Packs")
local coinRow = cardRow(250)
for i, item in ipairs(Items.CoinPacks) do
	productCard(coinRow, #Items.CoinPacks, i, item, C3(255, 200, 60), C3(255, 130, 20))
end

sectionTitle("Survival Gear")
local gearRow = cardRow(230)
for i, item in ipairs(Items.Gear) do
	productCard(gearRow, #Items.Gear, i, item, C3(170, 110, 255), C3(100, 40, 200))
end

sectionTitle("Boosts")
local passRow = cardRow(170)
for i, item in ipairs(Items.Passes) do
	passCard(passRow, i, item)
end

sectionTitle("Trails")
trailCards()

freeCard()

--------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------
local function openShop()
	if gui.Enabled then
		return
	end
	gui.Enabled = true
	results.Visible = false
	windowScale.Scale = 0.85
	TweenService:Create(windowScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	RequestData:FireServer()
	ShopOpened:FireServer()
	refresh()
end

local function closeShop()
	gui.Enabled = false
end
close.Activated:Connect(closeShop)
dim.Activated:Connect(closeShop)

-- shortcut: the old Shop panel is detected by its title text ("🛒 Shop"); if ProgressionClient
-- renames it, this stops redirecting and the old shop shows again.
task.spawn(function()
	local progressionUI = playerGui:WaitForChild("ProgressionUI", 60)
	local panel = progressionUI and progressionUI:WaitForChild("Panel", 30)
	if not panel then
		warn("[ShopUI] ProgressionUI.Panel not found - open the new shop is not hooked up")
		return
	end
	local function check()
		if not panel.Visible then
			return
		end
		for _, c in ipairs(panel:GetChildren()) do
			if c:IsA("TextLabel") and string.find(c.Text, "Shop", 1, true) then
				panel.Visible = false
				openShop()
				return
			end
		end
	end
	panel:GetPropertyChangedSignal("Visible"):Connect(check)
	for _, c in ipairs(panel:GetChildren()) do
		if c:IsA("TextLabel") then
			c:GetPropertyChangedSignal("Text"):Connect(check)
		end
	end
end)

Notify.OnClientEvent:Connect(function(msg, kind)
	if gui.Enabled and kind == "error" then
		toast(msg)
	end
end)

-- turn the icons + rainbow frames while the shop is open
RunService.RenderStepped:Connect(function()
	if not gui.Enabled then
		return
	end
	local t = os.clock()
	for _, s in ipairs(spinners) do
		if s.gradient then
			s.gradient.Rotation = (t * 120) % 360
		else
			s.model:PivotTo(CFrame.new(s.center) * CFrame.Angles(0, math.sin(t * s.speed + s.phase) * 0.6, 0) * CFrame.new(s.center):ToObjectSpace(s.base))
		end
	end
end)
