-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Services = ServerStorage:WaitForChild("Services")

local FormatKit = require(Packages:WaitForChild("FormatKit"))
local DataService = require(Services:WaitForChild("DataService"))

-- Constants
local GROUP_ID = 683942179
local REQUIRED_TIME = 300 -- 5 Dakika (Saniye cinsinden)

-- Module
local GroupRewardService = {
	Name = script.Name,
	Client = {},
	Players = {} -- Oyuncuların giriş zamanını (os.clock) tutar
}

function GroupRewardService.Client:Verify(player : Player)
	return GroupRewardService:Verify(player)
end

function GroupRewardService:Verify(player)
	local Data = DataService:GetData(player)
	if (Data and Data.GroupRewardCompleted) then
		return false, "You already completed."
	end

	-- 1. Verileri Al
	local joinTime = self.Players[player]

	-- Eğer veri yoksa hata ver (Oyuncu yüklenmemiş olabilir)
	if not joinTime then 
		return false, "An error occurred while checking your data. Please rejoin." 
	end

	-- 2. Kontrolleri Yap
	local isInGroup = player:IsInGroupAsync(GROUP_ID)
	local timePlayed = os.clock() - joinTime
	local hasEnoughTime = timePlayed >= REQUIRED_TIME

	-- 3. Mantık Akışı (Logic Flow)

	-- DURUM A: Grupta Değil (Süreye bakmaksızın öncelik grup)
	if not isInGroup then
		return false, "You must complete steps to claim this reward."
	end

	-- DURUM B: Grupta AMA Süresi Dolmamış
	if isInGroup and not hasEnoughTime then
		local remainingSeconds = REQUIRED_TIME - timePlayed

		-- Kullanıcıya kalan süreyi gösteriyoruz
		return false, `You need to play for {FormatKit.FormatTime(remainingSeconds, "m:ss")} more minutes.`
	end

	-- DURUM C: Her ikisi de Tamam (Success)
	if isInGroup and hasEnoughTime then
		DataService:GetProfile(player):andThen(function(Profile)
			Profile.Data.GroupRewardCompleted = true
			Profile.Data.KillerSkins["Grass"] = true
		end)
		return true, "Success! You have completed all the requirements."
	end

	return false, "Unknown error."
end

function GroupRewardService:OnStart()
	local function PlayerAdded(player : Player)
		-- Oyuncu girdiğinde şu anki zamanı kaydet
		self.Players[player] = os.clock()
	end

	for _, player in ipairs(Players:GetPlayers()) do
		PlayerAdded(player)
	end

	Players.PlayerAdded:Connect(PlayerAdded)

	Players.PlayerRemoving:Connect(function(player : Player)
		self.Players[player] = nil
	end)
end

return GroupRewardService