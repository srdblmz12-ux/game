-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Trove = require(Packages:WaitForChild("Trove"))

local DoorKey = "Door"

-- Module
local DoorService = {
	Name = script.Name,
	Client = {},
	Troves = {}
}

-- Helper
local function GetSortedSteps(StepsFolder: Folder)
	local steps = StepsFolder:GetChildren()
	table.sort(steps, function(a, b)
		return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
	end)
	return steps
end

-- Bir adımın (Step) içindeki tüm parçaları sadece Anchorlar.
-- Görünürlük (Parenting) işlemi CreateDoor içinde yönetilecek.
local function AnchorStepParts(stepInstance: Instance)
	local parts = {}
	if stepInstance:IsA("BasePart") then
		table.insert(parts, stepInstance)
	end
	for _, desc in ipairs(stepInstance:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end

	for _, part in ipairs(parts) do
		part.Anchored = true -- Hepsini çiviliyoruz, düşmesinler
	end
end

local function CreateDoor(Door: Model)
	local Activator = Door:FindFirstChild("_Activator") :: BasePart
	local StepsFolder = Door:FindFirstChild("Steps") :: Folder

	if not (Activator and StepsFolder) then return end

	local sortedSteps = GetSortedSteps(StepsFolder)
	if #sortedSteps < 2 then 
		warn(Door.Name .. " yeterli step yok!") 
		return 
	end

	-- Activator Ayarları
	Activator.Transparency = 1
	Activator.CanCollide = false -- İçinden geçilebilir
	Activator.CanQuery = false -- Raycast görmezden gelir
	Activator.CanTouch = true -- Dokunma algılaması için TRUE olmalı
	Activator.Anchored = true

	local NewTrove = Trove.new()

	-- Attributes
	local CompletionTime = Door:GetAttribute("CompletionTime") or 1
	local Lifetime = Door:GetAttribute("Lifetime") or 2

	NewTrove:Connect(Door:GetAttributeChangedSignal("CompletionTime"), function()
		CompletionTime = Door:GetAttribute("CompletionTime")
	end)
	NewTrove:Connect(Door:GetAttributeChangedSignal("Lifetime"), function()
		Lifetime = Door:GetAttribute("Lifetime")
	end)

	-- Başlangıç Durumu: 
	-- 1. Tüm parçaları Anchorla.
	-- 2. Sadece ilk adım (1. Step) klasörde kalsın, diğerlerinin Parent'i nil olsun.
	for i, step in ipairs(sortedSteps) do
		AnchorStepParts(step) -- Parçaları sabitle

		if i == 1 then
			step.Parent = StepsFolder -- İlk kare görünür
		else
			step.Parent = nil -- Diğerleri yok
		end
	end

	local isBusy = false
	local isOpen = false

	local function Operate()
		if isBusy or isOpen then return end
		isBusy = true

		local stepCount = #sortedSteps
		-- Geçiş süresi hesaplama (Adım sayısı - 1 kadar geçiş vardır)
		local delayPerStep = CompletionTime / (stepCount - 1)

		-- AÇILMA (Forward: 1 -> N)
		for i = 1, stepCount - 1 do
			task.wait(delayPerStep)

			-- Şu anki adımı bellekten silmeden sahneden kaldır (Parent = nil)
			sortedSteps[i].Parent = nil
			-- Bir sonraki adımı sahneye koy (Parent = Folder)
			sortedSteps[i+1].Parent = StepsFolder
		end

		isOpen = true
		task.wait(Lifetime)

		-- KAPANMA (Backward: N -> 1)
		for i = stepCount, 2, -1 do
			task.wait(delayPerStep)

			-- Şu anki adımı kaldır
			sortedSteps[i].Parent = nil
			-- Bir önceki adımı geri getir
			sortedSteps[i-1].Parent = StepsFolder
		end

		isOpen = false
		isBusy = false
	end

	NewTrove:Connect(Activator.Touched, function(hit)
		if isBusy then return end
		if hit.Parent:FindFirstChild("Humanoid") then
			Operate()
		end
	end)

	NewTrove:AttachToInstance(Door)
	DoorService.Troves[Door] = NewTrove
end

local function RemoveDoor(Door: Model)
	if DoorService.Troves[Door] then
		DoorService.Troves[Door]:Destroy()
		DoorService.Troves[Door] = nil
	end
end

-- Server

function DoorService:CreateDoor(Door: Model)
	return CreateDoor(Door)
end

function DoorService:RemoveDoor(Door: Model)
	return RemoveDoor(Door)
end

function DoorService:OnStart()
	CollectionService:GetInstanceAddedSignal(DoorKey):Connect(CreateDoor)
	CollectionService:GetInstanceRemovedSignal(DoorKey):Connect(RemoveDoor)
	for _,Door in ipairs(CollectionService:GetTagged(DoorKey)) do
		CreateDoor(Door)
	end
end

return DoorService