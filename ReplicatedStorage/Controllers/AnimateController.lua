local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

-- Klasörler
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")
local AnimatorAssets = Common:WaitForChild("AnimatorAssets")

-- Modüller
local Trove = require(Packages:WaitForChild("Trove"))
local ClassicAnimator = require(AnimatorAssets:WaitForChild("ClassicAnimator"))
local Animator = require(AnimatorAssets:WaitForChild("Animator"))

local LocalPlayer = Players.LocalPlayer

local AnimateController = {
	Name = script.Name,
	NPCTroves = {} -- Tag'li NPC'lerin Trove'larını tutacağımız liste
}

-- [YARDIMCI FONKSİYON] Animasyon Mantığı (Hem Player Hem NPC için ortak)
local function startAnimation(character, parentTrove)
	-- Non-blocking olması için task.spawn içinde yapıyoruz (WaitForChild diğerlerini bekletmesin)
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end

		-- 1. AnimationData Kontrolü
		local customDataModule = character:FindFirstChild("AnimationData")
		local loadedModern = false

		if customDataModule and customDataModule:IsA("ModuleScript") then
			local success, animData = pcall(require, customDataModule)

			if success and type(animData) == "table" then
				-- Modern Animasyon Sistemini Başlat
				local runner = Animator.new(humanoid, animData)
				parentTrove:Add(runner)
				loadedModern = true
				-- print(character.Name .. " için Modern Animator yüklendi.")
			else
				warn(character.Name .. ": AnimationData hatalı, Classic moda geçiliyor.")
			end
		end

		-- 2. Eğer Modern yüklenmediyse Classic Animator'ü Başlat
		if not loadedModern then
			-- ClassicAnimator'e Karakteri ve Trove'u gönderiyoruz
			ClassicAnimator:OnStart(character, parentTrove)
			-- print(character.Name .. " için Classic Animator yüklendi.")
		end
	end)
end

function AnimateController:OnStart()
	-- :: 1. LOCAL PLAYER YÖNETİMİ ::
	local playerTrove = Trove.new()

	local function onLocalCharacterAdded(character)
		playerTrove:Clean() -- Önceki karakterden kalanları temizle
		startAnimation(character, playerTrove)
	end

	if LocalPlayer.Character then
		onLocalCharacterAdded(LocalPlayer.Character)
	end

	LocalPlayer.CharacterAdded:Connect(onLocalCharacterAdded)
	LocalPlayer.CharacterRemoving:Connect(function()
		playerTrove:Clean()
	end)

	-- :: 2. COLLECTION SERVICE (NPC) YÖNETİMİ ::

	local function onInstanceAdded(instance)
		-- Zaten yönetiliyorsa atla
		if self.NPCTroves[instance] then return end

		local npcTrove = Trove.new()
		self.NPCTroves[instance] = npcTrove

		-- Animasyonu başlat
		startAnimation(instance, npcTrove)

		-- Instance silinirse (Workspace'ten düşerse/yok olursa) temizlik yap
		npcTrove:Connect(instance.AncestryChanged, function(_, parent)
			if not parent then
				if self.NPCTroves[instance] then
					self.NPCTroves[instance]:Destroy()
					self.NPCTroves[instance] = nil
				end
			end
		end)
	end

	local function onInstanceRemoved(instance)
		if self.NPCTroves[instance] then
			self.NPCTroves[instance]:Destroy()
			self.NPCTroves[instance] = nil
		end
	end

	-- Var olanları al
	for _, instance in ipairs(CollectionService:GetTagged("Animate")) do
		onInstanceAdded(instance)
	end

	-- Yeni gelenleri dinle
	CollectionService:GetInstanceAddedSignal("Animate"):Connect(onInstanceAdded)

	-- Tag silinenleri dinle
	CollectionService:GetInstanceRemovedSignal("Animate"):Connect(onInstanceRemoved)
end

return AnimateController