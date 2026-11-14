--[[
	PetsClient  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts

	All the pet UI, built from code (nothing to set up in Studio):
	  * Two buttons on the right-center of the screen: EGGS and PETS
	  * EGGS tab:  the 3 eggs with price, "what's inside" previews + odds, and a Hatch button
	  * PETS tab:  3 equip slots, a grid of all 15 pets (unowned ones are silhouettes) and details
	  * Hatch animation: egg pops in, shakes, flashes, then the pet is revealed
	Everything it does goes through the server (PetService) - this script only displays and asks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PetConfig = require(ReplicatedStorage:WaitForChild("PetConfig"))
local Builder = require(ReplicatedStorage:WaitForChild("PetModelBuilder"))
local remotes = ReplicatedStorage:WaitForChild("PetRemotes")
local Request = remotes:WaitForChild("PetRequest")
local BoostEvent = remotes:WaitForChild("PetBoost")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FONT = Enum.Font.GothamBold
local COLORS = {
	Panel = Color3.fromRGB(24, 28, 46),
	Panel2 = Color3.fromRGB(36, 42, 68),
	Text = Color3.fromRGB(255, 255, 255),
	Dim = Color3.fromRGB(160, 170, 200),
	Good = Color3.fromRGB(70, 200, 110),
	Disabled = Color3.fromRGB(88, 94, 120),
	Bad = Color3.fromRGB(230, 80, 80),
	Gold = Color3.fromRGB(255, 205, 70),
}

local ERRORS = {
	NotEnoughCoins = "Not enough coins!",
	SlotsFull = "All slots are full - unequip a pet first.",
	NotOwned = "You don't own that pet yet.",
	Busy = "Hang on, still hatching...",
	Cooldown = "Easy there!",
	Loading = "Your pets are still loading...",
	BadRequest = "Something went wrong, try again.",
}

--------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------
local function make(class, props, parent)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	for key, value in pairs(props) do
		inst[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function round(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

local function outline(parent, color, thickness)
	return make("UIStroke", { Color = color, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

-- TextLabel that scales its text to fit, capped at props.Max
local function text(parent, props)
	local maxSize = props.Max or 20
	props.Max = nil
	local base = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = COLORS.Text,
		TextScaled = true,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local label = make("TextLabel", base, parent)
	make("UITextSizeConstraint", { MinTextSize = 8, MaxTextSize = maxSize }, label)
	return label
end

local function button(parent, props)
	local maxSize = props.Max or 20
	props.Max = nil
	local base = {
		Font = FONT,
		TextColor3 = COLORS.Text,
		TextScaled = true,
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.Good,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local b = make("TextButton", base, parent)
	make("UITextSizeConstraint", { MinTextSize = 8, MaxTextSize = maxSize }, b)
	round(b, 10)
	return b
end

local function tween(inst, seconds, goal, style, direction)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function formatNumber(n)
	local s = tostring(math.floor(n))
	local reversed = string.reverse(s)
	reversed = string.gsub(reversed, "(%d%d%d)", "%1,")
	local result = string.reverse(reversed)
	result = string.gsub(result, "^,", "")
	return result
end

local function formatPercent(p)
	if p == math.floor(p) then
		return string.format("%d%%", p)
	end
	return string.format("%.1f%%", p)
end

local function request(action, arg)
	local ok, result = pcall(function()
		return Request:InvokeServer(action, arg)
	end)
	if ok and type(result) == "table" then
		return result
	end
	return { ok = false, err = "BadRequest" }
end

--------------------------------------------------------------------
-- State
--------------------------------------------------------------------
local state = { owned = {}, equipped = {}, hidden = false }
local selectedPet = nil
local hatching = false
local currentTab = "Eggs"

local function isEquipped(petId)
	return table.find(state.equipped, petId) ~= nil
end

-- forward declarations (assigned further down)
local refreshPets, refreshDetails, updateCoinUI, toast, hatchEgg, playHatch, setTab

--------------------------------------------------------------------
-- Pet previews (ViewportFrames)
--------------------------------------------------------------------
local function setSilhouette(viewport, on)
	if on then
		viewport.Ambient = Color3.new(0, 0, 0)
		viewport.LightColor = Color3.new(0, 0, 0)
	else
		viewport.Ambient = Color3.fromRGB(185, 185, 185)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
	end
end

local function makePetViewport(parent, petId, silhouette)
	local viewport = make("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
	}, parent)
	local info = { viewport = viewport }
	local model = Builder.Build(petId, true)
	if model then
		model.Parent = viewport
		local camera = make("Camera", { FieldOfView = 34 }, viewport)
		viewport.CurrentCamera = camera
		local extents = model:GetExtentsSize()
		local distance = (extents.Magnitude * 0.5) / math.tan(math.rad(camera.FieldOfView / 2)) * 1.1
		info.setAngle = function(angle)
			local dir = Vector3.new(math.sin(angle) * 0.6, 0.42, -math.cos(angle)).Unit
			camera.CFrame = CFrame.lookAt(dir * distance, Vector3.new(0, 0.1, 0))
		end
		info.setAngle(0.5)
	end
	setSilhouette(viewport, silhouette)
	return info
end

-- A cartoon egg built from frames
local function makeEgg(parent, egg)
	local shell = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = egg.Color,
	}, parent)
	make("UIAspectRatioConstraint", { AspectRatio = 0.78, DominantAxis = Enum.DominantAxis.Height }, shell)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shell)
	outline(shell, Color3.fromRGB(40, 30, 34), 3)
	local spots = { { 0.3, 0.32, 0.2 }, { 0.68, 0.5, 0.16 }, { 0.4, 0.72, 0.14 }, { 0.62, 0.22, 0.09 } }
	for _, s in ipairs(spots) do
		local spot = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(s[1], s[2]),
			Size = UDim2.fromScale(s[3], s[3]),
			BackgroundColor3 = egg.SpotColor,
		}, shell)
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, spot)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, spot)
	end
	local shine = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.28, 0.14),
		Size = UDim2.fromScale(0.14, 0.14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
	}, shell)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, shine)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shine)
	return shell
end

--------------------------------------------------------------------
-- GUI skeleton
--------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "PetsUI",
	ResetOnSpawn = false,
	DisplayOrder = 30,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- Toast message at the top
local toastLabel = make("TextLabel", {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(380, 38),
	BackgroundColor3 = COLORS.Panel,
	BackgroundTransparency = 0.05,
	Font = FONT,
	TextSize = 16,
	TextColor3 = COLORS.Text,
	TextWrapped = true,
	Text = "",
	Visible = false,
	ZIndex = 60,
}, gui)
round(toastLabel, 10)
outline(toastLabel, COLORS.Panel2, 2)
local toastToken = 0
function toast(message, color)
	toastToken = toastToken + 1
	local mine = toastToken
	toastLabel.Text = message
	toastLabel.TextColor3 = color or COLORS.Text
	toastLabel.Visible = true
	task.delay(3.2, function()
		if toastToken == mine then
			toastLabel.Visible = false
		end
	end)
end

-- The two buttons (right-center of the screen; change Position here if they overlap something)
local menu = make("Frame", {
	Name = "PetMenu",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(104, 100),
	BackgroundTransparency = 1,
}, gui)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, menu)

local function menuButton(label, order, onClick)
	local b = make("TextButton", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(104, 46),
		BackgroundColor3 = COLORS.Panel,
		Text = label,
		Font = FONT,
		TextSize = 20,
		TextColor3 = COLORS.Text,
	}, menu)
	round(b, 12)
	outline(b, COLORS.Gold, 2)
	b.MouseButton1Click:Connect(onClick)
	return b
end

-- Main window
local window = make("Frame", {
	Name = "PetWindow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.74, 0.8),
	BackgroundColor3 = COLORS.Panel,
	Visible = false,
}, gui)
round(window, 14)
outline(window, COLORS.Panel2, 3)
make("UISizeConstraint", { MaxSize = Vector2.new(860, 560), MinSize = Vector2.new(320, 260) }, window)

local tabEggs = button(window, { Text = "🥚 Eggs", Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(100, 32), Max = 18 })
local tabPets = button(window, { Text = "🐾 Pets", Position = UDim2.fromOffset(118, 8), Size = UDim2.fromOffset(100, 32), Max = 18 })
local coinsLabel = text(window, {
	Text = "🪙 0",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -56, 0, 8),
	Size = UDim2.fromOffset(150, 32),
	Max = 20,
	TextColor3 = COLORS.Gold,
	TextXAlignment = Enum.TextXAlignment.Right,
})
local closeButton = button(window, {
	Text = "X",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 8),
	Size = UDim2.fromOffset(34, 32),
	BackgroundColor3 = COLORS.Bad,
	Max = 18,
})

local content = make("Frame", {
	Name = "Content",
	Position = UDim2.fromOffset(12, 52),
	Size = UDim2.new(1, -24, 1, -64),
	BackgroundTransparency = 1,
}, window)

--------------------------------------------------------------------
-- EGGS tab
--------------------------------------------------------------------
local eggsPage = make("Frame", { Name = "EggsPage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, content)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, eggsPage)

local eggButtons = {} -- [eggId] = { button = TextButton, cost = number }

local function buildEggCard(egg, order)
	local card = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1 / 3, -7, 1, 0),
		BackgroundColor3 = COLORS.Panel2,
	}, eggsPage)
	round(card, 12)
	outline(card, egg.Accent, 3)

	text(card, { Text = egg.Name, Position = UDim2.fromScale(0, 0.01), Size = UDim2.fromScale(1, 0.09), Max = 24, TextColor3 = egg.Accent })

	local eggHolder = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.11),
		Size = UDim2.fromScale(0.5, 0.3),
		BackgroundTransparency = 1,
	}, card)
	makeEgg(eggHolder, egg)

	text(card, { Text = "What's inside", Position = UDim2.fromScale(0, 0.42), Size = UDim2.fromScale(1, 0.05), Max = 14, TextColor3 = COLORS.Dim })
	local row = make("Frame", { Position = UDim2.fromScale(0.03, 0.48), Size = UDim2.fromScale(0.94, 0.25), BackgroundTransparency = 1 }, card)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, row)
	for i, odd in ipairs(PetConfig.EggOdds(egg.Id)) do
		local pet = PetConfig.Pets[odd.PetId]
		local tier = PetConfig.GetTier(pet)
		local slot = make("TextButton", {
			LayoutOrder = i,
			Size = UDim2.new(0.2, -2, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
		}, row)
		local box = make("Frame", { Size = UDim2.new(1, 0, 0.72, 0), BackgroundColor3 = COLORS.Panel }, slot)
		round(box, 8)
		outline(box, tier.Color, 2)
		makePetViewport(box, odd.PetId, false)
		text(slot, { Text = formatPercent(odd.Percent), Position = UDim2.fromScale(0, 0.74), Size = UDim2.fromScale(1, 0.26), Max = 14, TextColor3 = tier.Color })
		slot.MouseButton1Click:Connect(function()
			toast(pet.Name .. " (" .. tier.Name .. "): " .. PetConfig.BoostLines(pet.Id)[1], tier.Color)
		end)
	end

	text(card, {
		Text = "Every pet: +" .. egg.Always .. " HP in any disaster",
		Position = UDim2.fromScale(0, 0.74),
		Size = UDim2.fromScale(1, 0.07),
		Max = 14,
		TextColor3 = COLORS.Dim,
	})

	local buy = button(card, {
		Text = "HATCH  🪙 " .. formatNumber(egg.Cost),
		Position = UDim2.fromScale(0.08, 0.83),
		Size = UDim2.fromScale(0.84, 0.14),
		Max = 22,
	})
	buy.MouseButton1Click:Connect(function()
		hatchEgg(egg)
	end)
	eggButtons[egg.Id] = { button = buy, cost = egg.Cost }
end

for i, egg in ipairs(PetConfig.Eggs) do
	buildEggCard(egg, i)
end

--------------------------------------------------------------------
-- PETS tab
--------------------------------------------------------------------
local petsPage = make("Frame", { Name = "PetsPage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, content)

local left = make("Frame", { Size = UDim2.new(0.36, -6, 1, 0), BackgroundTransparency = 1 }, petsPage)
local equippedTitle = text(left, { Text = "Equipped 0/3", Size = UDim2.new(1, 0, 0, 24), Max = 18, TextXAlignment = Enum.TextXAlignment.Left })

local slotsRow = make("Frame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 86), BackgroundTransparency = 1 }, left)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, slotsRow)

local slots = {}
for i = 1, PetConfig.MaxEquipped do
	local frame = make("Frame", { LayoutOrder = i, Size = UDim2.new(1 / PetConfig.MaxEquipped, -4, 1, 0), BackgroundColor3 = COLORS.Panel2 }, slotsRow)
	round(frame, 10)
	outline(frame, COLORS.Gold, 2)
	local hint = text(frame, { Text = "+", Max = 34, TextColor3 = COLORS.Dim, ZIndex = 2 })
	local click = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 3 }, frame)
	slots[i] = { frame = frame, hint = hint, petId = nil, viewport = nil }
	click.MouseButton1Click:Connect(function()
		local id = slots[i].petId
		if id then
			selectedPet = id
			refreshPets()
		end
	end)
end

local hideButton = button(left, {
	Text = "",
	Position = UDim2.fromOffset(0, 120),
	Size = UDim2.new(1, 0, 0, 28),
	Max = 15,
})

-- Shows whether MY pets are visible on MY screen (other players still see them either way)
local function refreshHide()
	if state.hidden then
		hideButton.Text = "🚫 My pets hidden - tap to show"
		hideButton.BackgroundColor3 = COLORS.Disabled
	else
		hideButton.Text = "👁 My pets shown - tap to hide"
		hideButton.BackgroundColor3 = COLORS.Good
	end
end
refreshHide()

local details = make("Frame", { Position = UDim2.fromOffset(0, 154), Size = UDim2.new(1, 0, 1, -154), BackgroundColor3 = COLORS.Panel2 }, left)
round(details, 10)
local detailName = text(details, { Text = "Select a pet", Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0.16, 0), Max = 24 })
local detailTier = text(details, { Text = "", Position = UDim2.fromScale(0, 0.2), Size = UDim2.new(1, 0, 0.1, 0), Max = 16, TextColor3 = COLORS.Dim })
local detailBoost = text(details, {
	Text = "",
	Position = UDim2.fromOffset(8, 0),
	Size = UDim2.new(1, -16, 0.34, 0),
	Max = 16,
	TextColor3 = COLORS.Good,
	TextYAlignment = Enum.TextYAlignment.Top,
})
detailBoost.Position = UDim2.fromScale(0.03, 0.32)
local actionButton = button(details, {
	Text = "Equip",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.new(0.86, 0, 0.18, 0),
	Max = 20,
	Visible = false,
})

local grid = make("ScrollingFrame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.new(0.64, -6, 1, 0),
	BackgroundColor3 = COLORS.Panel2,
	BackgroundTransparency = 0.4,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, petsPage)
round(grid, 10)
make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, grid)
make("UIGridLayout", { CellSize = UDim2.fromOffset(92, 108), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)

local cells = {} -- [petId] = { viewport, name, badge, stroke }
for i, petId in ipairs(PetConfig.PetOrder) do
	local pet = PetConfig.Pets[petId]
	local tier = PetConfig.GetTier(pet)
	local cell = make("TextButton", { LayoutOrder = i, BackgroundColor3 = COLORS.Panel, Text = "", AutoButtonColor = false }, grid)
	round(cell, 10)
	local stroke = outline(cell, tier.Color, 2)
	local holder = make("Frame", { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 70), BackgroundTransparency = 1 }, cell)
	local viewport = makePetViewport(holder, petId, true)
	local nameLabel = text(cell, { Text = "???", Position = UDim2.new(0, 2, 1, -30), Size = UDim2.new(1, -4, 0, 26), Max = 14, TextColor3 = tier.Color })
	local badge = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = COLORS.Good,
		Visible = false,
		ZIndex = 3,
	}, cell)
	round(badge, 9)
	text(badge, { Text = "E", Max = 12, ZIndex = 4 })
	cell.MouseButton1Click:Connect(function()
		selectedPet = petId
		refreshPets()
	end)
	cells[petId] = { viewport = viewport, name = nameLabel, badge = badge, stroke = stroke }
end

function refreshDetails()
	local id = selectedPet
	if not id then
		detailName.Text = "Select a pet"
		detailName.TextColor3 = COLORS.Text
		detailTier.Text = ""
		detailBoost.Text = "Tap a pet to see what it does. Hatch eggs to collect them all!"
		detailBoost.TextColor3 = COLORS.Dim
		actionButton.Visible = false
		return
	end
	local pet = PetConfig.Pets[id]
	local tier = PetConfig.GetTier(pet)
	local egg = PetConfig.GetEgg(pet.Egg)
	if state.owned[id] ~= true then
		detailName.Text = "???"
		detailName.TextColor3 = COLORS.Dim
		detailTier.Text = "Found in the " .. egg.Name
		detailBoost.Text = "Hatch it to unlock its boosts!"
		detailBoost.TextColor3 = COLORS.Dim
		actionButton.Visible = false
		return
	end
	detailName.Text = pet.Name
	detailName.TextColor3 = tier.Color
	detailTier.Text = tier.Name .. "  |  " .. egg.Name
	detailBoost.Text = table.concat(PetConfig.BoostLines(id), "\n")
	detailBoost.TextColor3 = COLORS.Good
	actionButton.Visible = true
	if isEquipped(id) then
		actionButton.Text = "Unequip"
		actionButton.BackgroundColor3 = COLORS.Bad
	else
		actionButton.Text = "Equip"
		actionButton.BackgroundColor3 = COLORS.Good
	end
end

function refreshPets()
	local always = 0
	for _, id in ipairs(state.equipped) do
		always = always + PetConfig.AlwaysFor(id)
	end
	equippedTitle.Text = "Equipped " .. #state.equipped .. "/" .. PetConfig.MaxEquipped .. "   (+" .. always .. " HP always)"

	for id, cell in pairs(cells) do
		local owned = state.owned[id] == true
		setSilhouette(cell.viewport.viewport, not owned)
		cell.name.Text = owned and PetConfig.Pets[id].Name or "???"
		cell.badge.Visible = isEquipped(id)
		cell.stroke.Thickness = (selectedPet == id) and 4 or 2
	end

	for i = 1, PetConfig.MaxEquipped do
		local slot = slots[i]
		local id = state.equipped[i]
		if slot.petId ~= id then
			if slot.viewport then
				slot.viewport.viewport:Destroy()
				slot.viewport = nil
			end
			slot.petId = id
			if id then
				slot.viewport = makePetViewport(slot.frame, id, false)
			end
		end
		slot.hint.Visible = id == nil
	end
	refreshDetails()
end

local function applyState(res)
	if res and res.ok and res.owned and res.equipped then
		state.owned = res.owned
		state.equipped = res.equipped
		state.hidden = res.hidden == true
		player:SetAttribute("HidePets", state.hidden) -- read by PetFollowClient (local only, never replicates)
		refreshHide()
		refreshPets()
	end
end

hideButton.MouseButton1Click:Connect(function()
	local res = request("SetHidden", not state.hidden)
	if res.ok then
		applyState(res)
	else
		toast(ERRORS[res.err] or "Couldn't change that right now.", COLORS.Bad)
	end
end)

actionButton.MouseButton1Click:Connect(function()
	local id = selectedPet
	if not id or state.owned[id] ~= true then
		return
	end
	local res = request(isEquipped(id) and "Unequip" or "Equip", id)
	if res.ok then
		applyState(res)
	else
		toast(ERRORS[res.err] or "Couldn't do that right now.", COLORS.Bad)
	end
end)

--------------------------------------------------------------------
-- Hatch animation
--------------------------------------------------------------------
local overlay = make("Frame", {
	Name = "HatchOverlay",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	Visible = false,
	Active = true,
	ZIndex = 20,
}, gui)

local eggBox = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.48),
	Size = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	ZIndex = 21,
}, overlay)

local card = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.5, 0.78),
	BackgroundColor3 = COLORS.Panel,
	Visible = false,
	ZIndex = 30,
}, overlay)
round(card, 16)
local cardStroke = outline(card, COLORS.Gold, 4)
make("UISizeConstraint", { MaxSize = Vector2.new(400, 470), MinSize = Vector2.new(250, 300) }, card)

local headline = text(card, { Text = "NEW PET!", Position = UDim2.fromScale(0, 0.02), Size = UDim2.fromScale(1, 0.09), Max = 26, TextColor3 = COLORS.Gold })
local petHolder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.12), Size = UDim2.fromScale(0.8, 0.4), BackgroundTransparency = 1 }, card)
local revealName = text(card, { Text = "", Position = UDim2.fromScale(0, 0.54), Size = UDim2.fromScale(1, 0.09), Max = 28 })
local revealTier = text(card, { Text = "", Position = UDim2.fromScale(0, 0.63), Size = UDim2.fromScale(1, 0.06), Max = 16, TextColor3 = COLORS.Dim })
local revealBoost = text(card, { Text = "", Position = UDim2.fromScale(0.04, 0.7), Size = UDim2.fromScale(0.92, 0.15), Max = 16, TextColor3 = COLORS.Good, TextYAlignment = Enum.TextYAlignment.Top })
local revealEquip = button(card, { Text = "Equip", Position = UDim2.fromScale(0.05, 0.87), Size = UDim2.fromScale(0.43, 0.1), Max = 20 })
local revealClose = button(card, { Text = "Nice!", Position = UDim2.fromScale(0.52, 0.87), Size = UDim2.fromScale(0.43, 0.1), Max = 20, BackgroundColor3 = COLORS.Panel2 })

local flash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 50, Active = false }, overlay)

local revealClosed = false
local revealPetId = nil

revealClose.MouseButton1Click:Connect(function()
	revealClosed = true
end)
revealEquip.MouseButton1Click:Connect(function()
	if not revealPetId then
		return
	end
	local res = request("Equip", revealPetId)
	if res.ok then
		applyState(res)
		revealEquip.Visible = false
		revealClose.Position = UDim2.fromScale(0.25, 0.87)
		revealClose.Size = UDim2.fromScale(0.5, 0.1)
	else
		toast(ERRORS[res.err] or "Couldn't equip it.", COLORS.Bad)
	end
end)

function playHatch(egg, res)
	local pet = PetConfig.Pets[res.petId]
	local tier = PetConfig.GetTier(pet)
	revealPetId = res.petId
	revealClosed = false

	-- reset the stage
	eggBox:ClearAllChildren()
	makeEgg(eggBox, egg)
	eggBox.Visible = true
	eggBox.Rotation = 0
	eggBox.Size = UDim2.fromOffset(0, 0)
	card.Visible = false
	flash.BackgroundTransparency = 1
	overlay.BackgroundTransparency = 1
	overlay.Visible = true

	tween(overlay, 0.25, { BackgroundTransparency = 0.25 })
	tween(eggBox, 0.45, { Size = UDim2.fromOffset(160, 206) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out).Completed:Wait()

	-- the egg shakes harder and faster
	for i = 1, 7 do
		local amplitude = 6 + i * 2.5
		local duration = math.max(0.06, 0.2 - i * 0.02)
		tween(eggBox, duration, { Rotation = amplitude }).Completed:Wait()
		tween(eggBox, duration * 2, { Rotation = -amplitude }).Completed:Wait()
	end
	tween(eggBox, 0.1, { Rotation = 0 }).Completed:Wait()

	-- flash, then reveal
	tween(flash, 0.12, { BackgroundTransparency = 0 }).Completed:Wait()
	eggBox.Visible = false

	petHolder:ClearAllChildren()
	local preview = makePetViewport(petHolder, res.petId, false)
	cardStroke.Color = tier.Color
	revealName.Text = pet.Name
	revealName.TextColor3 = tier.Color
	revealTier.Text = tier.Name .. "  |  " .. egg.Name
	if res.isNew then
		headline.Text = "NEW PET!"
		headline.TextColor3 = COLORS.Gold
		revealBoost.Text = table.concat(PetConfig.BoostLines(res.petId), "\n")
		revealBoost.TextColor3 = COLORS.Good
	else
		headline.Text = "Duplicate!"
		headline.TextColor3 = COLORS.Dim
		revealBoost.Text = "You already own this one.\n+" .. formatNumber(res.refund or 0) .. " 🪙 refunded"
		revealBoost.TextColor3 = COLORS.Gold
	end
	local showEquip = res.isNew and not res.autoEquipped
	revealEquip.Visible = showEquip
	if showEquip then
		revealClose.Position = UDim2.fromScale(0.52, 0.87)
		revealClose.Size = UDim2.fromScale(0.43, 0.1)
	else
		revealClose.Position = UDim2.fromScale(0.25, 0.87)
		revealClose.Size = UDim2.fromScale(0.5, 0.1)
		if res.autoEquipped then
			revealTier.Text = tier.Name .. "  |  " .. egg.Name .. "  |  Equipped!"
		end
	end

	card.Size = UDim2.fromScale(0.2, 0.3)
	card.Visible = true
	tween(flash, 0.45, { BackgroundTransparency = 1 })
	tween(card, 0.5, { Size = UDim2.fromScale(0.5, 0.78) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- slowly spin the new pet until the player closes the card
	local angle = 0.5
	local spin = RunService.RenderStepped:Connect(function(dt)
		angle = angle + dt * 1.2
		if preview.setAngle then
			preview.setAngle(angle)
		end
	end)
	local waited = 0
	while not revealClosed and waited < 60 do
		task.wait(0.1)
		waited = waited + 0.1
	end
	spin:Disconnect()

	petHolder:ClearAllChildren()
	card.Visible = false
	tween(overlay, 0.2, { BackgroundTransparency = 1 }).Completed:Wait()
	overlay.Visible = false
	revealPetId = nil
	selectedPet = res.petId
	refreshPets()
end

function hatchEgg(egg)
	if hatching then
		return
	end
	local coins = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Coins")
	if coins and coins.Value < egg.Cost then
		toast("Not enough coins! The " .. egg.Name .. " costs " .. formatNumber(egg.Cost) .. " 🪙", COLORS.Bad)
		return
	end
	hatching = true
	local res = request("Hatch", egg.Id)
	if not res.ok then
		hatching = false
		toast(ERRORS[res.err] or "Couldn't hatch right now.", COLORS.Bad)
		return
	end
	applyState(res)
	playHatch(egg, res)
	hatching = false
end

--------------------------------------------------------------------
-- Window open/close + tabs
--------------------------------------------------------------------
function setTab(name)
	currentTab = name
	eggsPage.Visible = name == "Eggs"
	petsPage.Visible = name == "Pets"
	tabEggs.BackgroundColor3 = name == "Eggs" and COLORS.Good or COLORS.Disabled
	tabPets.BackgroundColor3 = name == "Pets" and COLORS.Good or COLORS.Disabled
	if name == "Pets" then
		-- re-read from the server: pets hatched from the new shop (ShopUI) are not in our copy yet
		local res = request("State")
		if res.ok then
			applyState(res)
		end
		refreshPets()
	end
end

local function openWindow(name)
	if window.Visible and currentTab == name then
		window.Visible = false
		return
	end
	setTab(name)
	window.Visible = true
	updateCoinUI()
end

tabEggs.MouseButton1Click:Connect(function()
	setTab("Eggs")
end)
tabPets.MouseButton1Click:Connect(function()
	setTab("Pets")
end)
closeButton.MouseButton1Click:Connect(function()
	window.Visible = false
end)

menuButton("🥚 EGGS", 1, function()
	openWindow("Eggs")
end)
menuButton("🐾 PETS", 2, function()
	openWindow("Pets")
end)

--------------------------------------------------------------------
-- Coins
--------------------------------------------------------------------
local coinsValue = nil
function updateCoinUI()
	local coins = coinsValue and coinsValue.Value or 0
	coinsLabel.Text = "🪙 " .. formatNumber(coins)
	for _, entry in pairs(eggButtons) do
		entry.button.BackgroundColor3 = coins >= entry.cost and COLORS.Good or COLORS.Disabled
	end
end

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 30)
	coinsValue = leaderstats and leaderstats:WaitForChild("Coins", 30)
	if coinsValue then
		coinsValue:GetPropertyChangedSignal("Value"):Connect(updateCoinUI)
	end
	updateCoinUI()
end)

--------------------------------------------------------------------
-- Server messages + initial load
--------------------------------------------------------------------
BoostEvent.OnClientEvent:Connect(function(total)
	toast("🐾 Your pets gave you +" .. tostring(total) .. " HP this round!", COLORS.Good)
end)

task.spawn(function()
	for _ = 1, 40 do
		local res = request("State")
		if res.ok then
			applyState(res)
			return
		end
		task.wait(1.5)
	end
end)

setTab("Eggs")