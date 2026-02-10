--[[
    GameService.lua - BULLETPROOF VERSION (FIXED VOTING BUG)
    
    GÜNCELLEMELER:
    1. Fix: Oylama sırasında oyuncu çıkarsa ekranın takılı kalması sorunu çözüldü (ResetMatch içine Force Clear eklendi).
    2. Fix: OnStart döngüsünde hata anında önce Reset atılıyor, sonra bekleniyor (Anlık UI temizliği).
    3. Genel: Kod yapısı korundu, gereksiz tablolar kaldırıldı.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local AnalyticsService = game:GetService("AnalyticsService") -- Ham API

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Services = ServerStorage:WaitForChild("Services")
local Modules = ServerStorage:WaitForChild("Modules")
local GameModesFolder = Modules:WaitForChild("GameModes")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local WaitingRoom = Shared:WaitForChild("WaitingRoom") -- WaitingRoom modeli burada olmalı

-- Dependencies
local Promise = require(Packages:WaitForChild("Promise"))
local Signal = require(Packages:WaitForChild("Signal"))
local Charm = require(Packages:WaitForChild("Charm"))
local Net = require(Packages:WaitForChild("Net"))

-- Service Dependencies
local DataService = require(Services:WaitForChild("DataService")) 
local PlayerService = require(Services:WaitForChild("PlayerService"))
local MapService = require(Services:WaitForChild("MapService"))
local RewardService = require(Services:WaitForChild("RewardService"))

-- Constants
local CONFIG = {
	VOTING_TIME = 15,
	WARMUP_TIME = 10,
	GAME_TIME = 90,
	INTERMISSION = 5,
	MIN_PLAYERS = 2,
	RESULT_SCREEN_TIME = 10,
	MAX_MAP_LOAD_RETRIES = 3
}

-- Module Definition
local GameService = {
	Name = script.Name,
	Client = {},

	-- Global State
	Gamemode = Charm.atom("Waiting"),
	TimeLeft = Charm.atom(0), 
	GameStatus = Charm.atom("Intermission"), 
	SurvivorCount = Charm.atom(0),

	-- Admin & Voting State
	NextMapOverride = Charm.atom(nil),
	CurrentOptions = Charm.atom({}), 
	Votes = Charm.atom({}),             

	-- Internal Game State
	RunningPlayers = {}, 
	RoundStartSnapshots = {},
	_connections = {}, 
	_gameLoopTask = nil,
	_activeModeModule = nil,
	_activeWaitingRoom = nil,
	_isGameActive = false,
	_votingCancelled = false,       
	_loadingCancelled = false,    

	-- Analytics State
	CurrentMapName = "Unknown",
	GameStartTime = 0,

	Signals = {
		GameEnded = Signal.new(),
		WarmupStarted = Signal.new(), 
		GameStarted = Signal.new(),     
	},

	Network = {
		StateUpdate = Net:RemoteEvent("StateUpdate"),
		VoteOptions = Net:RemoteEvent("VoteOptions"), 
		VoteUpdate = Net:RemoteEvent("VoteUpdate"),         
		WarmupStarted = Net:RemoteEvent("WarmupStarted"),
		GameStarted = Net:RemoteEvent("GameStarted"),
		GameEnded = Net:RemoteEvent("GameEnded"),
		CastVote = Net:RemoteEvent("CastVote"),
		LoadLighting = Net:RemoteEvent("LoadLighting"),
		Results = Net:RemoteEvent("Results"),
		StartFX = Net:RemoteEvent("StartFX")
	}
}

GameService.Client.Server = GameService

---

-- =============================================================================
--  CLIENT API
-- =============================================================================

function GameService.Client:GetPlayersStatus(player)
	local playerStatusList = {}
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		local userIdString = tostring(targetPlayer.UserId)
		local currentRole = self.Server.RunningPlayers[userIdString] or "Lobby"
		playerStatusList[targetPlayer.Name] = currentRole
	end
	return playerStatusList
end

function GameService.Client:GetPlayerData(player, targetPlayerName: string)
	local targetPlayer = Players:FindFirstChild(targetPlayerName)
	if not targetPlayer then return nil end

	local targetIdString = tostring(targetPlayer.UserId)
	local role = self.Server.RunningPlayers[targetIdString] or "Lobby"

	return {
		PlayerName = targetPlayer.Name,
		Role = role,
		UserId = targetPlayer.UserId,
		IsAlive = (targetPlayer.Character and targetPlayer.Character:FindFirstChild("Humanoid") and targetPlayer.Character.Humanoid.Health > 0) or false
	}
end

function GameService.Client:GetGameState()
	return Charm.peek(GameService.GameStatus())
end

---

-- =============================================================================
--  HELPER FUNCTIONS
-- =============================================================================

local function LogMetric(player, eventName, value)
	local safeValue = tonumber(value) or 1
	pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, safeValue)
	end)
end

function GameService:_getValidPlayers()
	local valid = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Parent then 
			table.insert(valid, player)
		end
	end
	return valid
end

function GameService:_calculateVoteCounts()
	local options = self.CurrentOptions()
	local currentVotes = self.Votes()
	local voteCounts = {}

	for _, optionData in ipairs(options) do 
		voteCounts[optionData.Id] = 0 
	end

	for userId, mapId in pairs(currentVotes) do
		if voteCounts[mapId] ~= nil then 
			local voteWeight = 1
			local player = Players:GetPlayerByUserId(userId)
			if player and player:GetAttribute("VIP") then
				voteWeight = 2
			end
			voteCounts[mapId] = voteCounts[mapId] + voteWeight 
		end
	end
	return voteCounts
end

function GameService:_countSurvivors()
	local count = 0
	for _, role in pairs(self.RunningPlayers) do
		if role == "Survivor" then 
			count = count + 1 
		end
	end
	return count
end

function GameService:_countKillers()
	local count = 0
	for _, role in pairs(self.RunningPlayers) do
		if role == "Killer" then 
			count = count + 1 
		end
	end
	return count
end

function GameService:SelectWeightedKiller(playerCandidates)
	local priorityList = {}
	for _, player in ipairs(playerCandidates) do
		if PlayerService:HasPriority(player) then
			table.insert(priorityList, player)
		end
	end

	if #priorityList > 0 then
		local winnerPlayer = priorityList[math.random(1, #priorityList)]
		PlayerService:RemovePriority(winnerPlayer)
		return winnerPlayer
	end

	local totalChance = 0
	local selectionPool = {}

	for _, player in ipairs(playerCandidates) do
		local chance = PlayerService:GetChance(player)
		if chance <= 0 then chance = 1 end
		totalChance = totalChance + chance
		table.insert(selectionPool, {Player = player, Weight = totalChance})
	end

	local randomNumber = math.random(1, totalChance)
	for _, poolEntry in ipairs(selectionPool) do
		if randomNumber <= poolEntry.Weight then
			return poolEntry.Player
		end
	end
	return playerCandidates[1]
end

function GameService:SetNextMap(mapName)
	local mapModule = MapService:FindMapModule(mapName)
	if mapModule then
		self.NextMapOverride(mapModule)
		return true
	end
	return false
end

function GameService:CastVote(player, mapId)
	if self.GameStatus() ~= "OnVoting" then return end
	if self._votingCancelled then return end

	local isValid = false
	for _, option in ipairs(self.CurrentOptions()) do 
		if option.Id == mapId then 
			isValid = true 
			break 
		end 
	end

	if not isValid then return end

	self.Votes(function(currentVotes) 
		local newVotes = table.clone(currentVotes) 
		newVotes[player.UserId] = mapId 
		return newVotes 
	end)
end

function GameService:_spawnWaitingRoom()
	if self._activeWaitingRoom then return end

	if WaitingRoom then
		self._activeWaitingRoom = WaitingRoom:Clone()
		self._activeWaitingRoom.Parent = workspace

		if not self._activeWaitingRoom.PrimaryPart then
			warn("UYARI: WaitingRoom modelinin PrimaryPart'ı ayarlı değil! Işınlanma hatalı olabilir.")
		end
	else
		warn("KRİTİK HATA: Shared/WaitingRoom bulunamadı!")
	end
end

function GameService:ResetMatch()
	-- State Reset
	self.GameStatus("Intermission")
	self.Gamemode("Waiting")
	self._activeModeModule = nil
	self.RunningPlayers = {}
	self.RoundStartSnapshots = {}
	self.Votes({})
	self.CurrentOptions({})
	self.NextMapOverride(nil)
	self.SurvivorCount(0)

	-- [CRITICAL FIX] Client'taki Oylama Ekranını Zorla Kapat
	-- Boş seçenek ve 0 süre göndererek Client UI'ın kapanmasını garanti ediyoruz.
	pcall(function()
		self.Network.VoteOptions:FireAllClients({}, 0)
		self.Network.StateUpdate:FireAllClients("TimeLeft", 0)
	end)

	-- Analytics Reset
	self.CurrentMapName = "Unknown"
	self.GameStartTime = 0

	-- Flags Reset
	self._isGameActive = false
	self._votingCancelled = false
	self._loadingCancelled = false

	if self._gameLoopTask then 
		task.cancel(self._gameLoopTask) 
		self._gameLoopTask = nil 
	end

	-- WaitingRoom Temizliği
	if self._activeWaitingRoom then
		self._activeWaitingRoom:Destroy()
		self._activeWaitingRoom = nil
	end

	MapService:Cleanup()
	PlayerService:DespawnAll()
end

-- =============================================================================
--  GAME PHASES
-- =============================================================================

function GameService:RunVotingPhase()
	self.GameStatus("OnVoting")
	self.TimeLeft(CONFIG.VOTING_TIME)
	self._votingCancelled = false

	local processedOptions = MapService:GetProcessedVoteOptions(3)
	self.CurrentOptions(processedOptions)
	self.Votes({})

	self.Network.VoteOptions:FireAllClients(processedOptions, CONFIG.VOTING_TIME)

	for currentTime = CONFIG.VOTING_TIME, 1, -1 do
		-- Her saniye iptal durumunu kontrol et
		if self._votingCancelled then return nil end
		if #Players:GetPlayers() < CONFIG.MIN_PLAYERS then 
			warn("Voting cancelled: Not enough players")
			self._votingCancelled = true
			return nil 
		end

		self.TimeLeft(currentTime)
		task.wait(1)
	end

	-- Son bir kontrol
	if self._votingCancelled or #Players:GetPlayers() < CONFIG.MIN_PLAYERS then 
		self._votingCancelled = true
		return nil 
	end

	local voteCounts = self:_calculateVoteCounts()
	local maxVotes, candidates = -1, {}

	for mapId, count in pairs(voteCounts) do
		if count > maxVotes then 
			maxVotes = count 
			candidates = {mapId} 
		elseif count == maxVotes then 
			table.insert(candidates, mapId) 
		end
	end

	local winnerId = candidates[math.random(1, #candidates)]
	local winnerModule = MapService:FindMapModule(winnerId)

	if not winnerModule and #processedOptions > 0 then 
		winnerModule = MapService:FindMapModule(processedOptions[1].Id) 
	end

	return winnerModule
end

function GameService:_loadMapSafely(mapModule)
	local retries = 0
	local mapData = nil

	while retries < CONFIG.MAX_MAP_LOAD_RETRIES do
		local success, result = pcall(function() 
			return MapService:LoadMap(mapModule) 
		end)

		if success and result then
			mapData = result
			break
		else
			retries = retries + 1
			warn(string.format("Map load retry %d/%d", retries, CONFIG.MAX_MAP_LOAD_RETRIES))

			if retries < CONFIG.MAX_MAP_LOAD_RETRIES then
				pcall(function() 
					MapService:Cleanup() 
				end)
				task.wait(1)
			end
		end
	end

	if not mapData then warn("Failed to load map") end
	return mapData
end

-- =============================================================================
--  START GAME
-- =============================================================================

function GameService:StartGame()
	if self._isGameActive then return Promise.reject("Game already active") end

	local activePlayers = self:_getValidPlayers()
	if #activePlayers < CONFIG.MIN_PLAYERS then return Promise.reject("Yetersiz Oyuncu (Start)") end

	self._isGameActive = true
	self._loadingCancelled = false

	-- WaitingRoom Oluştur
	self:_spawnWaitingRoom()

	-- 1. Voting
	local mapModule = self.NextMapOverride() or self:RunVotingPhase()
	self.NextMapOverride(nil)

	if self._votingCancelled or not mapModule then 
		self._isGameActive = false
		return Promise.reject("Voting Cancelled") 
	end

	self.CurrentMapName = tostring(mapModule.Name) 
	self.GameStatus("Loading")

	-- 2. Data Loading
	local dataPromises = {}
	activePlayers = self:_getValidPlayers()
	for _, player in ipairs(activePlayers) do 
		table.insert(dataPromises, DataService:GetProfile(player)) 
	end

	return Promise.all(dataPromises):andThen(function()

		-- [CHECKPOINT 1] Data Yükleme Kontrolü
		if not self._isGameActive or self._loadingCancelled or #Players:GetPlayers() < CONFIG.MIN_PLAYERS then
			error("Loading Aborted: State Invalid after Data Load")
		end

		self.RoundStartSnapshots = {}
		activePlayers = self:_getValidPlayers()
		for _, player in ipairs(activePlayers) do
			self.RoundStartSnapshots[player] = self:_getPlayerDataSnapshot(player)
		end

		-- 3. Map Loading
		local mapData = self:_loadMapSafely(mapModule)
		if not mapData then error("Map Load Failed") end

		-- [CHECKPOINT 2] Harita Yükleme Kontrolü
		if not self._isGameActive or self._loadingCancelled or #Players:GetPlayers() < CONFIG.MIN_PLAYERS then
			error("Loading Aborted: State Invalid after Map Load")
		end

		if mapData.Lighting then 
			pcall(function() 
				self.Network.LoadLighting:FireAllClients(mapData.Lighting) 
			end)
		end

		-- 4. Mode Setup
		self:_setupGameMode(activePlayers)

		-- [CHECKPOINT 3] Setup Kontrolü
		if not self._isGameActive then error("Game cancelled during setup") end

		-- KILLER'I WAITING ROOM'A IŞINLA
		if self._activeWaitingRoom and self._activeWaitingRoom.PrimaryPart then
			for userIdString, role in pairs(self.RunningPlayers) do
				if role == "Killer" then
					local killerPlayer = Players:GetPlayerByUserId(tonumber(userIdString))
					if killerPlayer and killerPlayer.Character then
						task.wait(0.1)
						killerPlayer.Character:PivotTo(self._activeWaitingRoom:GetPivot())
					end
				end
			end
		end

		local currentSurvivorCount = 0
		for _, role in pairs(self.RunningPlayers) do 
			if role == "Survivor" then 
				currentSurvivorCount = currentSurvivorCount + 1 
			end 
		end
		self.SurvivorCount(currentSurvivorCount)

		-- 5. Warmup
		self.GameStatus("Warmup")
		self.TimeLeft(CONFIG.WARMUP_TIME)

		self.Network.WarmupStarted:FireAllClients(self.Gamemode(), self.RunningPlayers, CONFIG.WARMUP_TIME)
		self.Signals.WarmupStarted:Fire()

		local activeInstancesRoles = {}
		for userIdString, role in pairs(self.RunningPlayers) do
			local player = Players:GetPlayerByUserId(tonumber(userIdString))
			if player and player.Parent then 
				activeInstancesRoles[player] = role 
			else 
				self.RunningPlayers[userIdString] = nil 
			end
		end

		-- Sadece Survivorları haritaya spawn et
		PlayerService:SpawnSurvivors(activeInstancesRoles, mapData.Spawns)
		self:_setupPlayerMonitoring()

		-- Warmup Döngüsü
		for currentTime = CONFIG.WARMUP_TIME, 1, -1 do
			if not self._isGameActive then 
				warn("StartGame Aborted: Game ended externally during Warmup")
				return 
			end

			if #Players:GetPlayers() < CONFIG.MIN_PLAYERS then 
				self:EndGame(nil) 
				return 
			end

			self.TimeLeft(currentTime)
			task.wait(1)
		end

		-- [CHECKPOINT 4] Son Kontrol
		if not self._isGameActive then 
			warn("StartGame Aborted: Game ended right before start")
			return 
		end

		self.GameStatus("GameRunning")
		self.GameStartTime = os.time()

		-- 6. Killer Spawn & Game Loop
		local currentPlayersForSpawn = {}
		for userIdString, role in pairs(self.RunningPlayers) do
			local player = Players:GetPlayerByUserId(tonumber(userIdString))
			if player and player.Parent then 
				currentPlayersForSpawn[player] = role 
			end
		end

		PlayerService:SpawnKillers(currentPlayersForSpawn, mapData.Spawns)

		local modeDuration = (self._activeModeModule and self._activeModeModule.Time) or CONFIG.GAME_TIME
		self.Network.GameStarted:FireAllClients(modeDuration)
		self.Network.StateUpdate:FireAllClients("TimeLeft", modeDuration) 
		self.Signals.GameStarted:Fire()

		self:_startTimeLoop()

	end):catch(function(err)
		warn("StartGame Error/Abort:", err)
		self._isGameActive = false
		self._loadingCancelled = false
		self:ResetMatch()
	end)
end

function GameService:_setupGameMode(players)
	local connectedPlayers = {}
	for _, player in ipairs(players) do
		if player and player.Parent then 
			table.insert(connectedPlayers, player) 
		end
	end

	if #connectedPlayers < CONFIG.MIN_PLAYERS then 
		error("Not enough players for mode setup") 
	end

	local modes = GameModesFolder:GetChildren()
	local selectedScript = modes[math.random(1, #modes)]
	local modeModule = require(selectedScript)

	if modeModule.MinPlayers and #connectedPlayers < modeModule.MinPlayers then
		modeModule = require(GameModesFolder.Classic)
		selectedScript = GameModesFolder.Classic
	end

	self._activeModeModule = modeModule
	self.Gamemode(selectedScript.Name)

	local rawRoles = modeModule:Start(self, connectedPlayers)
	self.RunningPlayers = {} 

	for playerInstance, roleName in pairs(rawRoles) do
		if playerInstance and playerInstance:IsA("Player") and playerInstance.Parent then
			local userIdString = tostring(playerInstance.UserId)
			self.RunningPlayers[userIdString] = roleName

			if roleName == "Killer" then 
				PlayerService:ResetChance(playerInstance)
			else 
				PlayerService:AddChance(playerInstance, 1) 
			end
		end
	end
end

function GameService:_setupPlayerMonitoring()
	for userIdString, role in pairs(self.RunningPlayers) do
		local userId = tonumber(userIdString)
		local player = Players:GetPlayerByUserId(userId)

		if player and player.Parent then
			local function monitorCharacter(character)
				local humanoid = character:WaitForChild("Humanoid", 10)
				if not humanoid then return end

				local connection = humanoid.Died:Connect(function()
					if not self._isGameActive then return end
					if self.GameStatus() ~= "GameRunning" and self.GameStatus() ~= "Warmup" then return end

					if self._activeModeModule and self._activeModeModule.OnPlayerDied then
						pcall(function() 
							self._activeModeModule:OnPlayerDied(self, player) 
						end)
					end

					if role == "Survivor" then
						local newTime = self.TimeLeft() + 7
						self.TimeLeft(newTime)
						self.Network.StateUpdate:FireAllClients("TimeLeft", newTime)

						self.RunningPlayers[userIdString] = nil 
						self.SurvivorCount(self:_countSurvivors())

						task.delay(3, function()
							if self._isGameActive and player and player.Parent then 
								pcall(function() 
									player:LoadCharacterAsync() 
								end)
							end
						end)

						if self:_countSurvivors() <= 0 then
							self:EndGame("Killer")
						end

					elseif role == "Killer" then
						self:EndGame("Survivors")
					end
				end)
				table.insert(self._connections, connection)
			end

			if player.Character then 
				pcall(function() 
					monitorCharacter(player.Character) 
				end) 
			end

			local conn = player.CharacterAdded:Connect(function(char) 
				pcall(function() 
					monitorCharacter(char) 
				end) 
			end)
			table.insert(self._connections, conn)
		end
	end
end

function GameService:_startTimeLoop()
	if self._gameLoopTask then task.cancel(self._gameLoopTask) end

	local modeDuration = (self._activeModeModule and self._activeModeModule.Time) or CONFIG.GAME_TIME
	self.TimeLeft(modeDuration)

	self._gameLoopTask = task.spawn(function()
		while self.TimeLeft() > 0 do
			task.wait(1)

			if not self._isGameActive then break end

			self.TimeLeft(self.TimeLeft() - 1)

			if self._activeModeModule and self._activeModeModule.CheckWinCondition then
				local success, winner = pcall(function() 
					return self._activeModeModule:CheckWinCondition(self) 
				end)

				if success and winner then 
					self:EndGame(winner) 
					return
				end
			end
		end

		if self._isGameActive and self.TimeLeft() <= 0 then
			-- Time Out: Survivors Win
			for userIdString, role in pairs(self.RunningPlayers) do
				if role == "Killer" then
					local player = Players:GetPlayerByUserId(tonumber(userIdString))
					if player and player.Parent and player.Character then
						local h = player.Character:FindFirstChild("Humanoid")
						if h then 
							pcall(function() h.Health = 0 end) 
						end
					end
				end
			end

			task.wait(1) 

			if self.GameStatus() == "GameRunning" then
				self:EndGame("Survivors")
			end
		end
	end)
end

function GameService:_getPlayerDataSnapshot(player)
	if not player or not player.Parent then return {Token = 0, XP = 0, Level = 1, TargetXP = 100} end

	local success, data = pcall(function() 
		return DataService:GetData(player) 
	end)

	if success and data then
		return {
			Token = data.CurrencyData.Value, 
			XP = data.LevelData.ValueXP,
			Level = data.LevelData.Level, 
			TargetXP = data.LevelData.TargetXP
		}
	end
	return {Token = 0, XP = 0, Level = 1, TargetXP = 100}
end

function GameService:_calculateEarnings(startData, endData)
	if not startData or not endData then return {Token = 0, XP = 0} end

	local earnedToken = math.max(0, endData.Token - startData.Token)
	local earnedXP = 0

	if endData.Level == startData.Level then 
		earnedXP = math.max(0, endData.XP - startData.XP)
	else
		local levelDiff = endData.Level - startData.Level
		earnedXP = (levelDiff * startData.TargetXP) + (endData.XP - startData.XP) 
	end

	return {Token = earnedToken, XP = math.max(0, earnedXP)}
end

-- =============================================================================
--  END GAME LOGIC
-- =============================================================================

function GameService:EndGame(winningTeam)
	if not self._isGameActive then
		warn("EndGame ignored: Game already ended")
		return
	end

	local matchDuration = math.max(0, os.time() - self.GameStartTime)
	local endReason = "Unknown"

	if winningTeam == "Killer" then 
		endReason = "AllSurvivorsDead"
	elseif winningTeam == "Survivors" then
		if self.TimeLeft() <= 0 then 
			endReason = "TimeLimit" 
		else 
			endReason = "KillerDeath" 
		end
	else 
		endReason = "ForcedEnd" 
	end

	local mapName = tostring(self.CurrentMapName or "Unknown")

	for userIdString, role in pairs(self.RunningPlayers) do
		local player = Players:GetPlayerByUserId(tonumber(userIdString))
		if player then
			local isWin = false
			if winningTeam == "Killer" and role == "Killer" then isWin = true end
			if winningTeam == "Survivors" and role == "Survivor" then isWin = true end

			LogMetric(player, "Match_Duration", matchDuration)
			LogMetric(player, "Match_Map_" .. mapName, 1)
			LogMetric(player, "Match_Result_" .. role .. "_" .. (isWin and "Win" or "Loss"), 1)
			LogMetric(player, "Match_EndReason_" .. endReason, 1)
		end
	end

	self._isGameActive = false 

	if self._gameLoopTask then 
		task.cancel(self._gameLoopTask) 
		self._gameLoopTask = nil 
	end

	for _, connection in ipairs(self._connections) do 
		pcall(function() 
			connection:Disconnect() 
		end) 
	end
	self._connections = {}

	-- REWARDS
	for userIdString, role in pairs(self.RunningPlayers) do
		local player = Players:GetPlayerByUserId(tonumber(userIdString))
		if player and player.Parent then
			pcall(function()
				if winningTeam == "Killer" and role == "Killer" then
					RewardService:AddXP(player, 100)
					RewardService:AddCurrency(player, 50, "MatchWin_Killer")
				elseif winningTeam == "Survivors" and role == "Survivor" then
					RewardService:AddXP(player, 25)
					RewardService:AddCurrency(player, 25, "MatchWin_Survivor")
				else
					RewardService:AddXP(player, 10)
					RewardService:AddCurrency(player, 5, "MatchParticipation")
				end
			end)
		end
	end

	local resultsPayload = {
		Winner = winningTeam,
		KillerName = "None",
		KillerId = 0,
		KillerSkin = "Wendigo",
		Survivors = {}, 
	}

	for userIdString, role in pairs(self.RunningPlayers) do
		if role == "Killer" then
			local killerPlayer = Players:GetPlayerByUserId(tonumber(userIdString))
			if killerPlayer and killerPlayer.Parent then
				resultsPayload.KillerName = killerPlayer.Name
				resultsPayload.KillerId = killerPlayer.UserId
				pcall(function()
					local profile = DataService.LoadedProfiles[killerPlayer]
					if profile and profile.Data.Equippeds.KillerSkin then
						resultsPayload.KillerSkin = profile.Data.Equippeds.KillerSkin
					end
				end)
			else 
				resultsPayload.KillerName = "Disconnected" 
			end
			break 
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player and player.Parent then
			local uidString = tostring(player.UserId)
			local role = self.RunningPlayers[uidString]
			local isDead = (role == nil)

			if uidString ~= tostring(resultsPayload.KillerId) then
				table.insert(resultsPayload.Survivors, { 
					Name = player.Name, 
					UserId = player.UserId, 
					IsDead = isDead 
				})
			end
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player and player.Parent then
			pcall(function()
				local startData = self.RoundStartSnapshots[player] or {Token = 0, XP = 0, Level = 1, TargetXP = 100}
				local endData = self:_getPlayerDataSnapshot(player)
				local earned = self:_calculateEarnings(startData, endData)

				local personalizedData = table.clone(resultsPayload)
				personalizedData.MyRewards = earned

				self.Network.Results:FireClient(player, personalizedData)
			end)
		end
	end

	self.TimeLeft(0)
	self.Network.StateUpdate:FireAllClients("TimeLeft", 0)

	if winningTeam == "Killer" then 
		self.GameStatus("MurdererWin")
	elseif winningTeam == "Survivors" then 
		self.GameStatus("SurvivorsWin")
	else 
		self.GameStatus("Intermission") 
	end

	self.Network.GameEnded:FireAllClients()
	self.Signals.GameEnded:Fire()
end

-- =============================================================================
--  INITIALIZATION
-- =============================================================================

function GameService:OnStart()
	local function sync(name, atom)
		Charm.effect(function() 
			pcall(function() 
				self.Network.StateUpdate:FireAllClients(name, atom()) 
			end) 
		end)
	end

	sync("Gamemode", self.Gamemode)
	sync("GameStatus", self.GameStatus)
	sync("SurvivorCount", self.SurvivorCount)

	Charm.effect(function() 
		pcall(function() 
			self.Network.VoteUpdate:FireAllClients(self:_calculateVoteCounts()) 
		end) 
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userIdString = tostring(player.UserId)
		local playerCount = #Players:GetPlayers()

		if self.GameStatus() == "OnVoting" and playerCount < CONFIG.MIN_PLAYERS then 
			self._votingCancelled = true 
		end

		if self.GameStatus() == "Loading" and playerCount < CONFIG.MIN_PLAYERS then 
			self._loadingCancelled = true 
		end

		if self.RunningPlayers[userIdString] then 
			local role = self.RunningPlayers[userIdString]

			if self.GameStatus() == "GameRunning" and self._isGameActive then
				local timePlayed = math.max(0, os.time() - self.GameStartTime)
				local mapName = tostring(self.CurrentMapName or "Unknown")

				LogMetric(player, "Player_Dropout_" .. role, timePlayed)
				LogMetric(player, "Player_Dropout_Map_" .. mapName, 1)
			end

			self.RunningPlayers[userIdString] = nil

			if self.GameStatus() == "GameRunning" or self.GameStatus() == "Warmup" then
				if role == "Survivor" then
					self.SurvivorCount(self:_countSurvivors())
					if self:_countSurvivors() <= 0 then 
						self:EndGame("Killer") 
					end
				elseif role == "Killer" then
					if self:_countKillers() <= 0 then 
						self:EndGame("Survivors") 
					end
				end
			end
		end
	end)

	self.Network.CastVote.OnServerEvent:Connect(function(player, mapId) 
		pcall(function() 
			self:CastVote(player, mapId) 
		end) 
	end)

	Players.PlayerAdded:Connect(function(player)
		pcall(function()
			self.Network.StateUpdate:FireClient(player, "Gamemode", self.Gamemode())
			self.Network.StateUpdate:FireClient(player, "GameStatus", self.GameStatus())
			self.Network.StateUpdate:FireClient(player, "SurvivorCount", self.SurvivorCount())
			self.Network.StateUpdate:FireClient(player, "TimeLeft", self.TimeLeft())

			if self.GameStatus() == "OnVoting" and #self.CurrentOptions() > 0 and not self._votingCancelled then
				self.Network.VoteOptions:FireClient(player, self.CurrentOptions(), self.TimeLeft())
				task.defer(function() 
					if player and player.Parent then 
						self.Network.VoteUpdate:FireClient(player, self:_calculateVoteCounts()) 
					end 
				end)
			end
		end)
	end)

	task.spawn(function()
		while true do
			while #Players:GetPlayers() < CONFIG.MIN_PLAYERS do 
				if self.GameStatus() ~= "Intermission" then 
					self:ResetMatch() 
				end
				task.wait(5) 
			end

			task.wait(CONFIG.INTERMISSION)

			local success, promise = pcall(function() 
				return self:StartGame() 
			end)

			if success and promise then
				local promiseSuccess, promiseResult = pcall(function() 
					return promise:getStatus() ~= Promise.Status.Rejected 
				end)

				if promiseSuccess and promiseResult then
					if self._isGameActive then 
						self.Signals.GameEnded:Wait() 
					end
					task.wait(CONFIG.RESULT_SCREEN_TIME) 
					self:ResetMatch()
				else
					warn("Game failed:", promiseResult)
					-- [CRITICAL FIX] Önce Reset at, sonra bekle. 
					-- Bu sayede oyuncular bozuk ekranda beklemez.
					self:ResetMatch()
					task.wait(3)
				end
			else
				warn("Failed to start game:", promise)
				self:ResetMatch()
				task.wait(3)
			end
		end
	end)
end

return GameService