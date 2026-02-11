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
local MonetizationService = require(Services:WaitForChild("MonetizationService"))
local VotingService = require(Services:WaitForChild("VotingService"))
local PlayerService = require(Services:WaitForChild("PlayerService"))
local RewardService = require(Services:WaitForChild("RewardService"))
local PerksService = require(Services:WaitForChild("PerkService"))
local DataService = require(Services:WaitForChild("DataService"))
local MapService = require(Services:WaitForChild("MapService"))

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

-- Module Definition
local GameService = {
	Name = script.Name,
	Client = {},

	-- Game State Variables
	State = "Waiting", -- Waiting, Voting, Loading, PerkSelection, InGame, Ended
	TimeLeft = 0,
	CurrentMode = nil,

	-- Role Management
	Killers = {},       -- { [Player] = true }
	Survivors = {},     -- { [Player] = true }
	DeadSurvivors = {}, -- { [Player] = true }

	-- Priority Queue for Monetization
	_priorityKillerQueue = {}, -- {Player1, Player2, ...}

	_gameTrove = nil,

	-- Internal Signal System (Server-side triggers)
	Signals = {
		GameStarted = Signal.new(),
		GameEnded = Signal.new(),
		StateChanged = Signal.new(),
		RoleAssigned = Signal.new()
	},

	-- Network Center (Client-Server Remotes)
	Network = {
		StateUpdate = Net:RemoteEvent("StateUpdate"),
		TimeUpdate = Net:RemoteEvent("TimeUpdate"),
		TimeAdded = Net:RemoteEvent("TimeAdded"),
		ModeSelected = Net:RemoteEvent("ModeSelected"),
		RoleAssigned = Net:RemoteEvent("RoleAssigned"),
		SendNotification = Net:RemoteEvent("SendNotification"),

		GameEnded = Net:RemoteEvent("GameEnded"),
		GameStarted = Net:RemoteEvent("GameStarted"),
		WarmupStarted = Net:RemoteEvent("WarmupStarted"),

		StartFX = Net:RemoteEvent("StartFX"),
		LoadLighting = Net:RemoteEvent("LoadLighting"),
		ChanceUpdate = Net:RemoteEvent("ChanceUpdate")
	}
}

-- =============================================================================
--  INTERNAL HELPER METHODS
-- =============================================================================

function GameService:_setState(newState, extraData)
	self.State = newState
	self.Network.StateUpdate:FireAllClients(newState, self.TimeLeft, extraData)
	self.Signals.StateChanged:Fire(newState)

	print(`[GameService] State Transition: {newState}`)
end

function GameService:_updateTimer(seconds)
	self.TimeLeft = seconds
	self.Network.TimeUpdate:FireAllClients(seconds)
end

function GameService:_getAvailableGameModes()
	local availableModes = {}
	local totalPlayerCount = #Players:GetPlayers()

	for _, moduleScript in ipairs(GameModesFolder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			local success, modeData = pcall(require, moduleScript)
			if success then
				local minimumRequirement = modeData.MinimumPlayer or 2
				if totalPlayerCount >= minimumRequirement then
					table.insert(availableModes, modeData)
				end
			end
		end
	end

	if #availableModes == 0 then
		warn("[GameService] No suitable game mode found. Picking fallback.")
		local fallbackModule = GameModesFolder:FindFirstChildWhichIsA("ModuleScript")
		if fallbackModule then 
			table.insert(availableModes, require(fallbackModule)) 
		end
	end

	return availableModes
end

function GameService:_pickRandomMode()
	local modes = self:_getAvailableGameModes()
	if #modes == 0 then return nil end
	return modes[math.random(1, #modes)]
end

function GameService:_assignRoles()
	local allPlayersList = Players:GetPlayers()
	local totalCount = #allPlayersList

	self.Killers = {}
	self.Survivors = {}
	self.DeadSurvivors = {}

	local requiredKillerCount = self.CurrentMode.KillerCount or 1
	if requiredKillerCount >= totalCount then
		requiredKillerCount = math.max(1, totalCount - 1)
	end

	local assignedKillersCount = 0

	-- 1. ADIM: Öncelikli (Satın Alan) Oyuncuları Seç
	for i = #self._priorityKillerQueue, 1, -1 do
		if assignedKillersCount >= requiredKillerCount then break end

		local player = self._priorityKillerQueue[i]
		if player and player.Parent == Players then
			self.Killers[player] = true
			assignedKillersCount += 1
			table.remove(self._priorityKillerQueue, i)
			print(`[GameService] Priority Killer Assigned: {player.Name}`)
		else
			table.remove(self._priorityKillerQueue, i)
		end
	end

	-- 2. ADIM: Geri kalan Katilleri rastgele seç
	if assignedKillersCount < requiredKillerCount then
		local candidates = {}
		for _, player in ipairs(allPlayersList) do
			if not self.Killers[player] then
				table.insert(candidates, player)
			end
		end

		-- Karıştır
		for i = #candidates, 2, -1 do
			local j = math.random(i)
			candidates[i], candidates[j] = candidates[j], candidates[i]
		end

		for i = 1, (requiredKillerCount - assignedKillersCount) do
			local player = candidates[i]
			if player then
				self.Killers[player] = true
				assignedKillersCount += 1
			end
		end
	end

	-- 3. ADIM: Rolleri Veritabanına ve Tablolara İşle
	for _, player in ipairs(allPlayersList) do
		if self.Killers[player] then
			PlayerService:SetData(player, "Role", "Killer")

			-- [ŞANS SIFIRLAMA] Seçilen katillerin şansını 0 yap
			PlayerService:SetData(player, "Chance", 0)
		else
			self.Survivors[player] = true
			PlayerService:SetData(player, "Role", "Survivor")
		end
	end

	-- Client Bilgilendirme
	self.Network.RoleAssigned:FireAllClients({
		Killers = self.Killers,
		Survivors = self.Survivors
	})
	self.Signals.RoleAssigned:Fire(self.Killers, self.Survivors)
end

-- =============================================================================
--  GAME LOOP PHASES
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

	self.Network.ModeSelected:FireAllClients(self.CurrentMode.Name)

	local mapModel = MapService:LoadMap(mapName)
	local spawns = MapService:GetSpawns(mapModel)

	self:_assignRoles()

	-- Survivorları Haritaya Al
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
		for Survivor in pairs(self.Survivors) do if Survivor.Parent then survivorCount += 1 end end

		local killerCount = 0
		for Killer in pairs(self.Killers) do if Killer.Parent then killerCount += 1 end end

		if survivorCount == 0 then return "AllSurvivorsLeft" end
		if killerCount == 0 then return "KillersLeft" end

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

	-- 1. Survivor Sayımı ve Executive
	local initialSurvivorCount = 0
	for Survivor, _ in pairs(self.Survivors) do
		if Survivor.Parent then
			initialSurvivorCount += 1
			if self.CurrentMode.SurvivorExecutive then
				task.spawn(self.CurrentMode.SurvivorExecutive, Survivor)
			end
		end
	end

	-- 2. Killer Hazırlıkları (SKILL VERME)
	for Killer, _ in pairs(self.Killers) do
		if Killer.Parent then
			local killerSpawn = spawns[math.random(1, #spawns)]
			PlayerService:SpawnPlayerTo(Killer, killerSpawn)

			-- Mod Executive
			if self.CurrentMode.KillerExecutive then
				task.spawn(self.CurrentMode.KillerExecutive, Killer)
			end

			-- [SKILL 1] Sanal Tool: Attack
			local attackAPI = PerksService.CachedPerks.MurdererPerks["Attack"]
			if attackAPI then
				PerksService:GivePerk(Killer, attackAPI)
			end

			-- [SKILL 2] Equipped Tool Skill (Boş değilse verilir)
			PerksService:GiveMurdererPerk(Killer)
		else
			self.Killers[Killer] = nil
		end
	end

	-- 3. Mod OnStart
	if self.CurrentMode.OnStart then
		local gamePlayerList = {}
		for Killer in pairs(self.Killers) do table.insert(gamePlayerList, Killer) end
		for Survivor in pairs(self.Survivors) do table.insert(gamePlayerList, Survivor) end
		task.spawn(self.CurrentMode.OnStart, self._gameTrove, gamePlayerList)
	end

	-- 4. Olay Dinleyicileri
	self._gameTrove:Connect(PlayerService.Signals.PlayerDied, function(VictimPlayer)
		if self.Survivors[VictimPlayer] then
			self.DeadSurvivors[VictimPlayer] = true
			if self.CurrentMode.ExtraTime and self.CurrentMode.ExtraTime > 0 then
				self.TimeLeft += self.CurrentMode.ExtraTime
				self:_updateTimer(self.TimeLeft)
				self.Network.TimeAdded:FireAllClients(self.CurrentMode.ExtraTime)
			end
		end
	end)

	self._gameTrove:Connect(Players.PlayerRemoving, function(LeavingPlayer)
		if self.Killers[LeavingPlayer] then
			self.Killers[LeavingPlayer] = nil
		elseif self.Survivors[LeavingPlayer] then
			self.Survivors[LeavingPlayer] = nil
			self.DeadSurvivors[LeavingPlayer] = true
		end
	end)

	-- 5. Dinamik Süre (Base + Survivor*10)
	local baseGameDuration = self.CurrentMode.Duration or 120
	local finalGameDuration = baseGameDuration + (initialSurvivorCount * 10)
	self:_updateTimer(finalGameDuration)

	local winReason = "TimeUp"

	while self.TimeLeft > 0 do
		task.wait(1)
		self:_updateTimer(self.TimeLeft - 1)

		local killersAlive = 0
		for Killer in pairs(self.Killers) do if Killer.Parent then killersAlive += 1 end end
		if killersAlive == 0 then
			winReason = "KillersLeft"
			break
		end

		local survivorsAlive = 0
		for Survivor in pairs(self.Survivors) do
			if Survivor.Parent and not self.DeadSurvivors[Survivor] then
				survivorsAlive += 1
			end
		end
		if survivorsAlive == 0 then
			winReason = "SurvivorsEliminated"
			break
		end
	end

	return "Next", winReason
end

function GameService:_stepEnded(winReason)
	local winnerTeam = (winReason == "SurvivorsEliminated") and "Killer" or "Survivor"

	-- Reward Logic
	if winnerTeam == "Survivor" then
		local survivorsWhoWon = {}
		for Survivor in pairs(self.Survivors) do
			if Survivor.Parent and not self.DeadSurvivors[Survivor] then
				table.insert(survivorsWhoWon, Survivor)
			end
		end
		for _, Survivor in ipairs(survivorsWhoWon) do RewardService:AddCurrency(Survivor, 100, "SurvivorWin") end
		if #survivorsWhoWon <= 3 then
			for _, Survivor in ipairs(survivorsWhoWon) do RewardService:AddCurrency(Survivor, 300, "EliteSurvivor") end
		end
	else
		for Killer in pairs(self.Killers) do
			if Killer.Parent then RewardService:AddCurrency(Killer, 100, "KillerWin") end
		end
	end

	-- Match Results Data
	local killersResultData = {}
	for Killer in pairs(self.Killers) do
		local killerSkin = "Default"
		local success, data = DataService:GetData(Killer):await()
		if success and data.Equippeds then killerSkin = data.Equippeds.KillerSkin or "Default" end
		killersResultData[Killer] = { EquippedSkin = killerSkin }
	end

	local survivorsResultData = {}
	for Survivor in pairs(self.Survivors) do
		survivorsResultData[Survivor] = { IsDead = (self.DeadSurvivors[Survivor] == true) }
	end

	local finalMatchResults = {
		Winner = winnerTeam,
		Killers = killersResultData,
		Survivors = survivorsResultData
	}

	self:_setState("Ended", finalMatchResults)
	self.Signals.GameEnded:Fire(finalMatchResults)
	BetterAnalyticsService:LogGameEnd(winnerTeam, self.CurrentMode.Name, self.TimeLeft)

	task.wait(POST_GAME_WAIT)

	-- Cleanup
	if self._gameTrove then self._gameTrove:Destroy(); self._gameTrove = nil end
	PlayerService:DespawnAll()
	PerksService:ResetPerks()
	MapService:UnloadMap()

	for _, Player in ipairs(Players:GetPlayers()) do
		PlayerService:SetData(Player, "Role", "Lobby")
	end

	self.Killers, self.Survivors, self.DeadSurvivors, self.CurrentMode = {}, {}, {}, nil
	return "Next"
end

-- =============================================================================
--  GAME LOOP ORCHESTRATION
-- =============================================================================

function GameService:GameLoop()
	while true do
		local loopStatus, resultData

		-- 1. Intermission
		loopStatus = self:_stepIntermission()
		if loopStatus == "NotEnoughPlayers" then
			self:_setState("Waiting")
			repeat task.wait(1) until #Players:GetPlayers() >= MIN_PLAYERS_TO_START
			continue
		end

		-- 2. Voting
		loopStatus, resultData = self:_stepVoting()
		if loopStatus == "NotEnoughPlayers" then
			self:_setState("Waiting")
			repeat task.wait(1) until #Players:GetPlayers() >= MIN_PLAYERS_TO_START
			continue
		end
		local mapToLoad = resultData

		-- 3. Loading
		loopStatus = self:_stepLoading(mapToLoad)
		if loopStatus == "Error" then
			warn("[GameService] Loading error. Restarting.")
			task.wait(2)
			continue
		end

		-- 4. Perk Selection
		loopStatus = self:_stepPerkSelection()
		if loopStatus == "AllSurvivorsLeft" or loopStatus == "KillersLeft" then
			PlayerService:DespawnAll(); MapService:UnloadMap(); PerksService:ResetPerks();
			continue
		end

		-- 5. In-Game
		loopStatus, resultData = self:_stepInGame()

		-- 6. Ended
		self:_stepEnded(resultData)
	end
end

-- =============================================================================
--  LIFECYCLE
-- =============================================================================

function GameService:OnStart()
	-- Garantili Katil Monetizasyonu
	MonetizationService:Register(MonetizationService.Type.Product, 3530798250, function(Player : Player)
		table.insert(self._priorityKillerQueue, Player)
		self.Network.SendNotification:FireClient(Player, "You will be next killer this round!", 5)
	end)

	print("[GameService] Loop starting...")
	task.spawn(function()
		self:GameLoop()
	end)
end

return GameService
