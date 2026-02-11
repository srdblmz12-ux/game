-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Services = ServerStorage:WaitForChild("Services")
local Modules = ServerStorage:WaitForChild("Modules")

local GameModesFolder = Modules:WaitForChild("GameModes")
local BetterAnalyticsService = require(Modules:WaitForChild("BetterAnalyticsService"))

-- Dependencies
local VotingService = require(Services:WaitForChild("VotingService"))
local PlayerService = require(Services:WaitForChild("PlayerService"))
local RewardService = require(Services:WaitForChild("RewardService"))
local PerksService = require(Services:WaitForChild("PerkService"))
local MapService = require(Services:WaitForChild("MapService"))
local DataService = require(Services:WaitForChild("DataService"))

local Promise = require(Packages:WaitForChild("Promise"))
local Signal = require(Packages:WaitForChild("Signal"))
local Trove = require(Packages:WaitForChild("Trove"))
local Net = require(Packages:WaitForChild("Net"))

-- Constants
local MIN_PLAYERS_TO_START = 2
local INTERMISSION_TIME = 15
local MAP_VOTING_TIME = 15
local PERK_SELECTION_TIME = 20
local POST_GAME_WAIT = 5

-- Module
local GameService = {
	Name = script.Name,
	Client = {},

	-- Game State
	State = "Waiting", -- Waiting, Voting, Loading, PerkSelection, InGame, Ended
	TimeLeft = 0,
	CurrentMode = nil,

	-- Roles (Tablo yapısına geçildi)
	Killers = {}, -- { [Player] = true }
	Survivors = {}, -- { [Player] = true }
	DeadSurvivors = {}, -- { [Player] = true } (Ölenler veya Spectatorlar)

	_gameTrove = nil,

	-- Internal Signals
	Signals = {
		GameStarted = Signal.new(),
		GameEnded = Signal.new(),
		StateChanged = Signal.new(),
		RoleAssigned = Signal.new() -- (KillersTable, SurvivorsTable) gönderir
	},

	-- Network Centers
	Network = {
		StateUpdate = Net:RemoteEvent("StateUpdate"),
		TimeUpdate = Net:RemoteEvent("TimeUpdate"),
		TimeAdded = Net:RemoteEvent("TimeAdded"),
		ModeSelected = Net:RemoteEvent("ModeSelected"),
		RoleAssigned = Net:RemoteEvent("RoleAssigned"),
		SendNotification = Net:RemoteEvent("SendNotification")
	}
}

-- =============================================================================
--  HELPER FUNCTIONS
-- =============================================================================

function GameService:_setState(newState, extraData)
	self.State = newState
	self.Network.StateUpdate:FireAllClients(newState, self.TimeLeft, extraData)
	self.Signals.StateChanged:Fire(newState)
	print(`[GameService] State Changed: {newState}`)
end

function GameService:_updateTimer(seconds)
	self.TimeLeft = seconds
	self.Network.TimeUpdate:FireAllClients(seconds)
end

function GameService:_getAvailableGameModes()
	local availableModes = {}
	local playerCount = #Players:GetPlayers()

	for _, moduleScript in ipairs(GameModesFolder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			local success, modeData = pcall(require, moduleScript)
			if success then
				local minimumRequirement = modeData.MinimumPlayer or 2
				if playerCount >= minimumRequirement then
					table.insert(availableModes, modeData)
				end
			end
		end
	end

	if #availableModes == 0 then
		warn("[GameService] Uygun mod bulunamadı, varsayılan seçiliyor.")
		local firstModule = GameModesFolder:FindFirstChildWhichIsA("ModuleScript")
		if firstModule then 
			table.insert(availableModes, require(firstModule)) 
		end
	end

	return availableModes
end

function GameService:_pickRandomMode()
	local modes = self:_getAvailableGameModes()
	if #modes == 0 then return nil end
	return modes[math.random(1, #modes)]
end

-- Rol Dağıtımı (Çoklu Killer Destekli)
function GameService:_assignRoles()
	local allPlayers = Players:GetPlayers()
	local playerCount = #allPlayers

	-- Listeyi karıştır (Shuffle)
	for i = playerCount, 2, -1 do
		local j = math.random(i)
		allPlayers[i], allPlayers[j] = allPlayers[j], allPlayers[i]
	end

	self.Killers = {}
	self.Survivors = {}
	self.DeadSurvivors = {}

	-- Modun istediği Killer sayısı (Default: 1)
	-- Duo için KillerCount = 2, Classic için = 1, Infection için = 1 (başlangıç)
	local requiredKillerCount = self.CurrentMode.KillerCount or 1

	-- Eğer oyuncu sayısı yetersizse (örn 2 kişi var ama mod 2 killer istiyor), en az 1 survivor bırak
	if requiredKillerCount >= playerCount then
		requiredKillerCount = math.max(1, playerCount - 1)
	end

	-- Rolleri Ata
	for i, Player in ipairs(allPlayers) do
		if i <= requiredKillerCount then
			self.Killers[Player] = true
		else
			self.Survivors[Player] = true
		end
	end

	-- Clientlara Bildir
	-- Not: Client tarafında tabloyu {UserId} veya Player listesi olarak işlemek gerekebilir.
	self.Network.RoleAssigned:FireAllClients({
		Killers = self.Killers,
		Survivors = self.Survivors
	})

	self.Signals.RoleAssigned:Fire(self.Killers, self.Survivors)
end

-- =============================================================================
--  GAME LOOP STEPS
-- =============================================================================

function GameService:_stepIntermission()
	self:_setState("Intermission")

	for seconds = INTERMISSION_TIME, 1, -1 do
		if #Players:GetPlayers() < MIN_PLAYERS_TO_START then 
			return "NotEnoughPlayers"
		end
		self:_updateTimer(seconds)
		task.wait(1)
	end

	return "Next"
end

function GameService:_stepVoting()
	self:_setState("Voting")
	VotingService:StartVoting()

	for seconds = MAP_VOTING_TIME, 1, -1 do
		if #Players:GetPlayers() < MIN_PLAYERS_TO_START then
			VotingService:EndVoting()
			return "NotEnoughPlayers"
		end
		self:_updateTimer(seconds)
		task.wait(1)
	end

	local winnerMapName = VotingService:EndVoting()
	task.wait(3)
	return "Next", winnerMapName
end

function GameService:_stepLoading(mapName)
	self:_setState("Loading")

	self.CurrentMode = self:_pickRandomMode()
	if not self.CurrentMode then return "Error" end

	print(`[GameService] Selected Mode: {self.CurrentMode.Name}`)
	self.Network.ModeSelected:FireAllClients(self.CurrentMode.Name)

	local mapModel = MapService:LoadMap(mapName)
	local spawns = MapService:GetSpawns(mapModel)

	self:_assignRoles()

	-- Survivorları Spawnla
	for Survivor, _ in pairs(self.Survivors) do
		if Survivor.Parent then
			local randomSpawn = spawns[math.random(1, #spawns)]
			PlayerService:SpawnPlayerTo(Survivor, randomSpawn)
		end
	end

	task.wait(1)
	return "Next"
end

function GameService:_stepPerkSelection()
	self:_setState("PerkSelection")

	if not self.CurrentMode.PerkSelectionLimit or self.CurrentMode.PerkSelectionLimit > 0 then
		PerksService:GeneratePerks(3)
		PerksService:PerkSelectionLimit(self.CurrentMode.PerkSelectionLimit or 1)
	end

	for seconds = PERK_SELECTION_TIME, 1, -1 do
		local survivorCount = 0
		for Survivor in pairs(self.Survivors) do
			if Survivor.Parent then survivorCount += 1 end
		end

		-- Aktif Killer var mı kontrolü (Çoklu killer için döngü)
		local activeKillerCount = 0
		for Killer in pairs(self.Killers) do
			if Killer.Parent then activeKillerCount += 1 end
		end

		if survivorCount == 0 then return "AllSurvivorsLeft" end
		if activeKillerCount == 0 then return "KillersLeft" end

		self:_updateTimer(seconds)
		task.wait(1)
	end

	return "Next"
end

function GameService:_stepInGame()
	self:_setState("InGame")
	self.Signals.GameStarted:Fire()
	self._gameTrove = Trove.new()

	local mapModel = MapService.CurrentMap
	local spawns = MapService:GetSpawns(mapModel)

	-- 1. Killerları Sahneye Al (Çoklu Döngü)
	local activeKillers = 0
	for Killer, _ in pairs(self.Killers) do
		if Killer.Parent then
			activeKillers += 1
			local killerSpawn = spawns[math.random(1, #spawns)]
			PlayerService:SpawnPlayerTo(Killer, killerSpawn)

			-- Killer Mod Executive
			if self.CurrentMode.KillerExecutive then
				task.spawn(self.CurrentMode.KillerExecutive, Killer)
			end

			-- Killer Perk
			PerksService:GiveMurdererPerk(Killer)
		else
			-- Başlangıçta çıkmış killerları listeden temizleyebiliriz
			self.Killers[Killer] = nil
		end
	end

	if activeKillers == 0 then return "KillersLeft" end

	-- 2. Survivor Mod Executive
	for Survivor, _ in pairs(self.Survivors) do
		if Survivor.Parent and self.CurrentMode.SurvivorExecutive then
			task.spawn(self.CurrentMode.SurvivorExecutive, Survivor)
		end
	end

	-- 3. Mod OnStart
	if self.CurrentMode.OnStart then
		local currentPlayerList = {}
		for Killer in pairs(self.Killers) do table.insert(currentPlayerList, Killer) end
		for Survivor in pairs(self.Survivors) do table.insert(currentPlayerList, Survivor) end

		task.spawn(self.CurrentMode.OnStart, self._gameTrove, currentPlayerList)
	end

	-- 4. Olay Dinleyicileri

	-- Survivor Ölümü
	self._gameTrove:Connect(PlayerService.Signals.PlayerDied, function(Player)
		if self.Survivors[Player] then
			self.DeadSurvivors[Player] = true

			-- Ekstra Süre
			if self.CurrentMode.ExtraTime then
				self.TimeLeft += self.CurrentMode.ExtraTime
				self:_updateTimer(self.TimeLeft)
				self.Network.TimeAdded:FireAllClients(self.CurrentMode.ExtraTime)
			end
		elseif self.Killers[Player] then
			-- Bir Killer öldüyse (Örn: Survivorlar tuzak kurdu vs.)
			-- Killer'ı tamamen silmiyoruz, belki respawn vardır modda ama şimdilik "Safe" oynuyoruz
			-- Eğer mod "Killer ölünce elenir" diyorsa buradan yönetilir.
			-- Şimdilik spectate moduna atılabilir.
		end
	end)

	-- Oyundan Çıkma
	self._gameTrove:Connect(Players.PlayerRemoving, function(Player)
		if self.Killers[Player] then
			self.Killers[Player] = nil -- Killer tablosundan sil
		elseif self.Survivors[Player] then
			self.Survivors[Player] = nil
			self.DeadSurvivors[Player] = true
		end
	end)

	-- 5. Ana Döngü
	local duration = self.CurrentMode.Duration or 120
	self:_updateTimer(duration)

	local winReason = "TimeUp"

	while self.TimeLeft > 0 do
		task.wait(1)
		self:_updateTimer(self.TimeLeft - 1)

		-- A. Killerlar Çıktı mı?
		local killerCount = 0
		for Killer in pairs(self.Killers) do
			if Killer.Parent then killerCount += 1 end
		end

		if killerCount == 0 then
			winReason = "KillersLeft"
			break
		end

		-- B. Survivorlar Bitti mi?
		local aliveCount = 0
		for Survivor in pairs(self.Survivors) do
			if Survivor.Parent and not self.DeadSurvivors[Survivor] then
				aliveCount += 1
			end
		end

		if aliveCount == 0 then
			winReason = "SurvivorsEliminated"
			break
		end
	end

	return "Next", winReason
end

function GameService:_stepEnded(winReason)
	local winnerRole = "Survivor"

	if winReason == "SurvivorsEliminated" then
		winnerRole = "Killer"
	end

	-- 1. Ödülleri Dağıt
	if winnerRole == "Survivor" then
		local aliveSurvivors = {}
		for Survivor in pairs(self.Survivors) do
			if Survivor.Parent and not self.DeadSurvivors[Survivor] then
				table.insert(aliveSurvivors, Survivor)
			end
		end

		for _, Survivor in ipairs(aliveSurvivors) do
			RewardService:AddCurrency(Survivor, 100, "SurvivorWin")
		end

		if #aliveSurvivors <= 3 then
			for _, Survivor in ipairs(aliveSurvivors) do
				RewardService:AddCurrency(Survivor, 300, "EliteSurvivor")
			end
		end

	elseif winnerRole == "Killer" then
		-- Tüm aktif Killerlara ödül ver
		for Killer in pairs(self.Killers) do
			if Killer.Parent then
				RewardService:AddCurrency(Killer, 100, "KillerWin")
			end
		end
	end

	-- 2. Verileri Hazırla
	-- Killer Verisi (Çoklu Destekli Yapı)
	local killersData = {}
	for Killer in pairs(self.Killers) do
		local skin = "Default"
		local success, data = DataService:GetData(Killer):await()
		if success and data.Equippeds then
			skin = data.Equippeds.KillerSkin or "Default"
		end

		-- Tablo olarak ekle: { [Player] = {Skin = "..."} }
		killersData[Killer] = {
			EquippedSkin = skin
		}
	end

	local survivorsData = {}
	for Survivor in pairs(self.Survivors) do
		survivorsData[Survivor] = {
			IsDead = (self.DeadSurvivors[Survivor] == true)
		}
	end

	local resultData = {
		Winner = winnerRole,
		Killers = killersData, -- Değişti: Artık tüm killerlar burada
		Survivors = survivorsData
	}

	-- 3. Bildir
	self:_setState("Ended", resultData)
	self.Signals.GameEnded:Fire(resultData)

	BetterAnalyticsService:LogGameEnd(winnerRole, self.CurrentMode.Name, self.TimeLeft)

	task.wait(POST_GAME_WAIT)

	-- 4. Temizlik
	if self._gameTrove then
		self._gameTrove:Destroy()
		self._gameTrove = nil
	end

	PlayerService:DespawnAll()
	PerksService:ResetPerks()
	MapService:UnloadMap()

	self.Killers = {}
	self.Survivors = {}
	self.DeadSurvivors = {}
	self.CurrentMode = nil

	return "Next"
end

-- =============================================================================
--  MAIN LOOP
-- =============================================================================

function GameService:GameLoop()
	while true do
		local status, result

		-- 1. Bekleme
		status = self:_stepIntermission()
		if status == "NotEnoughPlayers" then
			self:_setState("Waiting")
			repeat task.wait(1) until #Players:GetPlayers() >= MIN_PLAYERS_TO_START
			continue
		end

		-- 2. Harita
		status, result = self:_stepVoting()
		if status == "NotEnoughPlayers" then
			self:_setState("Waiting")
			repeat task.wait(1) until #Players:GetPlayers() >= MIN_PLAYERS_TO_START
			continue
		end
		local selectedMap = result

		-- 3. Yükleme
		status = self:_stepLoading(selectedMap)
		if status == "Error" then
			warn("[GameService] Game Load Error, restarting loop")
			task.wait(1)
			continue
		end

		-- 4. Perk
		status = self:_stepPerkSelection()
		if status == "AllSurvivorsLeft" or status == "KillersLeft" then
			PlayerService:DespawnAll()
			MapService:UnloadMap()
			PerksService:ResetPerks()
			continue
		end

		-- 5. Oyun
		status, result = self:_stepInGame()
		local winReason = result

		-- 6. Bitiş
		self:_stepEnded(winReason)
	end
end

function GameService:OnStart()
	task.spawn(function()
		self:GameLoop()
	end)
end

return GameService
