--[[
	PlayerService.lua
	
	GÜNCELLEME: 
	- Hitbox Sistemi Eklendi: Karakterlerin etrafına 4x6x4 boyutunda görünmez bir kutu oluşturulur.
	  Bu sayede saldırılar (Spherecast/Raycast) karakteri çok daha rahat algılar.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Services = ServerStorage:WaitForChild("Services")

-- Assets
local Characters = Shared:WaitForChild("Characters")
local OverheadGuiAssets = Shared:WaitForChild("OverheadGuiAssets")

-- Libraries
local Charm = require(Packages:WaitForChild("Charm"))
local FormatKit = require(Packages:WaitForChild("FormatKit"))
local Promise = require(Packages:WaitForChild("Promise"))
local Net = require(Packages:WaitForChild("Net"))

-- Game Services
local DataService = require(Services:WaitForChild("DataService"))
local MonetizationService = require(Services:WaitForChild("MonetizationService"))
local RewardService = require(Services:WaitForChild("RewardService"))

-- Constants
local PlayerIcons = {
	[414410946] = { -- serdar
		"rbxasset://textures/ui/PlayerList/developer.png",
		"rbxassetid://4969357404", 
	},
	[4775564686] = { -- mehmet
		"rbxasset://textures/ui/PlayerList/developer.png",
		"rbxassetid://105540078", 
		"rbxassetid://11104447788"
	},
	[1327643007] = { -- hamza
		"rbxassetid://15423490200", 
		"rbxassetid://10664762623", 
	}
}

-- Service Definition
local PlayerService = {
	Name = script.Name,
	Client = {},

	PlayerChances = {}, 
	KillerPriority = {}, 

	Network = {
		ChanceUpdate = Net:RemoteEvent("ChanceUpdate")
	}
}

--// Client Functions

function PlayerService.Client:GetChance(player)
	return PlayerService:GetChance(player)
end

--// PRIORITY SYSTEM (GARANTİ KATİL)

function PlayerService:SetPriority(player)
	self.KillerPriority[player] = true
end

function PlayerService:HasPriority(player)
	return self.KillerPriority[player] == true
end

function PlayerService:RemovePriority(player)
	self.KillerPriority[player] = nil
end

--// CHANCE SYSTEM

function PlayerService:GetChance(player)
	local atom = self.PlayerChances[player]
	if atom then
		local baseValue = atom()
		if player:GetAttribute("VIP") then
			baseValue = baseValue * 1.5
		end
		return math.floor(baseValue) 
	end
	return 0
end

function PlayerService:ResetChance(player)
	local atom = self.PlayerChances[player]
	if atom then
		atom(0)
		self.Network.ChanceUpdate:FireClient(player, 0)
	end
end

function PlayerService:AddChance(player, amount)
	local atom = self.PlayerChances[player]
	if atom then
		local value = amount or 1
		local newValue = atom() + value
		atom(newValue)
		self.Network.ChanceUpdate:FireClient(player, self:GetChance(player))
	end
end

--// HITBOX SYSTEM (YENİ)
-- Bu fonksiyon her karaktere 4x6x4'lük dev bir hedef kutusu ekler.
function PlayerService:CreateHitbox(character)
	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
	if not rootPart then return end

	-- Zaten varsa tekrar ekleme
	if character:FindFirstChild("Hitbox") then return end

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(4.5, 6, 4.5) -- Karakterden daha geniş bir alan
	hitbox.CFrame = rootPart.CFrame
	hitbox.Transparency = 1 -- Görünmez
	hitbox.CanCollide = false -- İçinden geçilebilir (hareketi engellemez)
	hitbox.CanQuery = true -- Raycast/Spherecast buna çarpabilir! (ÖNEMLİ)
	hitbox.CanTouch = true 
	hitbox.Massless = true -- Ağırlık yapmaz
	hitbox.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = hitbox
	weld.Parent = hitbox
end

--// SPAWNER SYSTEM

function PlayerService:SpawnSurvivors(runningPlayers, spawnLocations)
	for player, role in pairs(runningPlayers) do
		if role == "Survivor" then
			self:_spawnPlayer(player, spawnLocations, "Survivor")
		end
	end
end

function PlayerService:SpawnKillers(runningPlayers, spawnLocations)
	for player, role in pairs(runningPlayers) do
		if role == "Killer" then
			self:_spawnPlayer(player, spawnLocations, "Killer")
		end
	end
end

function PlayerService:DespawnAll()
	for _, player in ipairs(Players:GetPlayers()) do
		player.RespawnLocation = nil
		player:LoadCharacterAsync()
		player:SetAttribute("Role", nil)
	end
end

function PlayerService:_spawnPlayer(player, spawnLocations, role)
	if not player then return end
	player:SetAttribute("Role", role)

	DataService:GetProfile(player):andThen(function(profile)
		-- Spawn noktası belirleme
		local randomSpawn = nil
		if spawnLocations and #spawnLocations > 0 then
			randomSpawn = spawnLocations[math.random(1, #spawnLocations)]
			player.RespawnLocation = randomSpawn
		end

		-- Spawn CFrame hesaplama
		local spawnCFrame = randomSpawn and (randomSpawn.CFrame * CFrame.new(0, 3, 0)) or CFrame.new(0, 10, 0)

		-- EĞER OYUNCU KATİL İSE
		if role == "Killer" then
			local equippedSkin = profile.Data.Equippeds and profile.Data.Equippeds.KillerSkin
			local characterModel = nil
			if equippedSkin then 
				characterModel = Characters:FindFirstChild(equippedSkin) 
			end

			if not characterModel then 
				characterModel = Characters:FindFirstChild("Bloxxer") 
			end

			if characterModel then
				local newCharacter = characterModel:Clone()
				newCharacter.Name = player.Name
				newCharacter:PivotTo(spawnCFrame)
				newCharacter.Parent = workspace
				player.Character = newCharacter

				-- [YENİ] Hitbox Ekle
				self:CreateHitbox(newCharacter)

				Net:RemoteEvent("StartFX"):FireAllClients("KillerSpawn", player)

				local rootPart = newCharacter:FindFirstChild("HumanoidRootPart")
				if rootPart then
					rootPart:SetNetworkOwner(player)
				end

				return 
			else
				warn("HATA: Bloxxer/Skin modeli bulunamadı!")
			end
		end

		-- EĞER OYUNCU SURVIVOR İSE
		local connection
		connection = player.CharacterAdded:Connect(function(character)
			local rootPart = character:WaitForChild("HumanoidRootPart", 5)
			if rootPart then
				character:PivotTo(spawnCFrame)
				-- [YENİ] Hitbox Ekle
				self:CreateHitbox(character)
			end
			if connection then connection:Disconnect() end
		end)

		player:LoadCharacterAsync()

	end):catch(function(err)
		warn("Spawn hatası:", err)
		player:LoadCharacterAsync()
	end)
end

--// INITIALIZATION

function PlayerService:OnStart()

	-- 1. Monetization Kaydı
	MonetizationService:Register(MonetizationService.Type.Product, 3530798250, function(Player : Player)
		self:SetPriority(Player)
		Net:RemoteEvent("SendNotification", "You will be next killer this round", 10)
		return true
	end)

	MonetizationService:Register(MonetizationService.Type.Gamepass, 1705481042, function(Player : Player)
		DataService:GetProfile(Player):andThen(function(Profile)
			Profile.Data.KillerSkins["Rich"] = true
		end)
		RewardService:AddCurrency(Player, 2000, "VIP")
		Player:SetAttribute("VIP", true)
	end)

	-- 2. DataService Sinyalini Dinle
	DataService.Signals.DataUpdate:Connect(function(player, path, newValue)
		if not player then return end

		-- A. Leaderstats Güncellemesi
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			if path == "CurrencyData.Value" then
				local tokenVal = leaderstats:FindFirstChild("Tokens")
				if tokenVal then tokenVal.Value = newValue end
			elseif path == "LevelData.Level" then
				local levelVal = leaderstats:FindFirstChild("Level")
				if levelVal then levelVal.Value = newValue end
			end
		end

		-- B. OverheadGui Güncellemesi
		if string.find(path, "LevelData") then
			local character = player.Character
			if character then
				local overhead = character:FindFirstChild("OverheadGui", true)
				if overhead then
					local fullData = DataService:GetData(player)
					if fullData then
						overhead.Level.Value.Text = `Level {FormatKit.FormatComma(fullData.LevelData.Level)}`
						local ratio = math.clamp(fullData.LevelData.ValueXP / fullData.LevelData.TargetXP, 0, 1)
						overhead.Level.FillBar.Size = UDim2.new(ratio, 0, 1, 0)
					end
				end
			end
		end
	end)

	-- 3. Oyuncu Katıldığında
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("VIP", MonetizationService:UserHas(player, 1705481042)) 

		-- A. Leaderstats
		local Data = DataService:GetData(player)
		local Leaderstats = Instance.new("Folder")
		Leaderstats.Name = "leaderstats"
		Leaderstats.Parent = player

		local Tokens = Instance.new("IntValue")
		Tokens.Name = "Tokens"
		Tokens.Value = Data.CurrencyData.Value
		Tokens.Parent = Leaderstats

		local Level = Instance.new("IntValue")
		Level.Name = "Level"
		Level.Value = Data.LevelData.Level
		Level.Parent = Leaderstats

		-- B. Karakter Yüklendiğinde (Overhead Gui + Hitbox)
		local function CharacterAdded(Character : Model)
			-- [YENİ] Lobi veya normal spawn fark etmeksizin Hitbox ekle
			self:CreateHitbox(Character)

			if (not player:GetAttribute("Role")) then
				local OverheadGui = OverheadGuiAssets.OverheadGui:Clone()
				OverheadGui.Parent = Character.PrimaryPart or Character
				OverheadGui.Display.Username.Text = player.DisplayName

				if (player.UserId <= 0) then
					local Icon = OverheadGuiAssets.Icon:Clone()
					Icon.Image = "rbxasset://textures/ui/PlayerList/developer.png"
					Icon.Parent = OverheadGui.Display
				end

				if (player.MembershipType ~= Enum.MembershipType.None) then
					local PremiumIcon = OverheadGuiAssets.Icon:Clone()
					PremiumIcon.Image = "rbxasset://textures/ui/PlayerList/PremiumIcon.png"
					PremiumIcon.Parent = OverheadGui.Display
				end

				local IconTable = PlayerIcons[player.UserId] or {}
				for _,IconId in ipairs(IconTable) do
					local Icon = OverheadGuiAssets.Icon:Clone()
					Icon.Image = IconId
					Icon.Parent = OverheadGui.Display
				end

				OverheadGui.Level.Value.Text = `Level {FormatKit.FormatComma(Data.LevelData.Level)}`
				local ratio = math.clamp(Data.LevelData.ValueXP / Data.LevelData.TargetXP, 0, 1)
				OverheadGui.Level.FillBar.Size = UDim2.new(ratio, 0, 1, 0)
			end

			for _,Basepart in ipairs(Character:GetDescendants()) do
				if (Basepart:IsA("BasePart") and Basepart.Name ~= "Hitbox") then -- Hitbox'ı collision grubuna alma
					Basepart.CollisionGroup = "Player"
				end
			end
		end

		if (player.Character) then 
			CharacterAdded(player.Character) 
		end
		player.CharacterAdded:Connect(CharacterAdded)

		self.PlayerChances[player] = Charm.atom(math.random(4,8))
		self.Network.ChanceUpdate:FireClient(player, self.PlayerChances[player]())
	end)

	-- 4. Oyuncu Ayrıldığında
	Players.PlayerRemoving:Connect(function(player)
		self.PlayerChances[player] = nil
		self.KillerPriority[player] = nil 
	end)

	-- 5. Mevcut Oyuncular İçin Şans Başlatma
	for _, player in ipairs(Players:GetPlayers()) do
		if not self.PlayerChances[player] then
			self.PlayerChances[player] = Charm.atom(0)
		end
	end
end

return PlayerService