-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ServerStorage:WaitForChild("Modules")

local PlayerExecutable = Modules:WaitForChild("PlayerExecutable")

local Promise = require(Packages:WaitForChild("Promise"))
local Signal = require(Packages:WaitForChild("Signal"))
local Net = require(Packages:WaitForChild("Net"))

-- Helper

local function GetTablePath(root, path)
	local parts = string.split(path, ".")
	local current = root
	for i = 1, #parts - 1 do
		current = current[parts[i]]
		if not current then return nil, nil end
	end
	return current, parts[#parts]
end

-- Module
local PlayerService = {
	Name = script.Name,
	Client = {},

	Signals = {
		PlayerAdded = Signal.new(),
		PlayerRemoving = Signal.new()
	},
	Network = {
		DataUpdated = Net:RemoteEvent("DataUpdated"),
	},
	LoadedPlayers = {
		--[[
		[Player] = {
			VoteCount = 1,
			Chance = 0,
			RewardMultiplier = 1,
			Role = "", -- Survivor / Killer
		}
		]]
	}
}

function PlayerService.Client:GetPlayerData(Player : Player, TargetPlayer : Player?)
	-- TargetPlayer varsa onu, yoksa isteği gönderen Player'ı baz al
	local playerToLookUp = TargetPlayer or Player

	-- Server tarafındaki tabloya erişip veriyi döndür
	local data = PlayerService.LoadedPlayers[playerToLookUp]
	return data
end

--// BUILT IN FUNCTIONS

function PlayerService:GetWeightedPlayer(Key : string)
	local Values = {}
	local ValueToPlayer = {}

	for Player, PlayerData in pairs(self.LoadedPlayers) do
		local TargetValue = PlayerData[Key]
		if (typeof(TargetValue) ~= "number") then continue end

		table.insert(Values, TargetValue)
		ValueToPlayer[TargetValue] = Player
	end

	-- GÜVENLİK KONTROLÜ: Eğer oyuncu yoksa hata verme, nil döndür.
	if #Values == 0 then
		return nil
	end

	return ValueToPlayer[math.max(unpack(Values))]
end

function PlayerService:SpawnPlayerTo(Player : Player, Spawnlocation : SpawnLocation | BasePart)
	-- Eğer hedef spawn noktası hiç yoksa işlemi durdur
	if not Spawnlocation then
		warn("SpawnPlayerTo called with nil Spawnlocation for player: " .. Player.Name)
		return
	end
	
	if Spawnlocation:IsA("SpawnLocation") and Spawnlocation.Enabled then
		Player.RespawnLocation = Spawnlocation
		Player:LoadCharacterAsync()

	else
		Player.RespawnLocation = nil
		Player:LoadCharacterAsync()

		-- Karakterin yüklenmesini bekle (LoadCharacter asenkron çalışabilir)
		local character = Player.Character or Player.CharacterAdded:Wait()
		local HumanoidRootPart = character:WaitForChild("HumanoidRootPart", 5) -- Timeout eklemek güvenlidir

		if HumanoidRootPart then
			HumanoidRootPart.CFrame = Spawnlocation.CFrame + Vector3.new(0, 3, 0)
		else
			warn("HumanoidRootPart not found for player: " .. Player.Name)
		end
	end
end

function PlayerService:DespawnAll()
	for _, player in ipairs(Players:GetPlayers()) do
		player.RespawnLocation = nil
		player:LoadCharacterAsync()
	end
end

function PlayerService:GetRole(Player : Player)
	local data = self.LoadedPlayers[Player]
	if data then
		return data.Role
	end
end

function PlayerService:GetData(Player : Player)
	return Promise.new(function(resolve, reject)
		local data = self.LoadedPlayers[Player]
		if data then
			resolve(data)
		else
			reject("Player data not found for " .. Player.Name)
		end
	end)
end

function PlayerService:SetData(Player : Player, Path : string, NewValue : any)
	local playerData = self.LoadedPlayers[Player]

	if not playerData then
		warn("Cannot set data, player not loaded: " .. Player.Name)
		return
	end

	-- Path'i ayrıştırıp ilgili tabloyu ve anahtarı buluyoruz
	local parentTable, key = GetTablePath(playerData, Path)

	if parentTable and key then
		-- Veriyi güncelle
		parentTable[key] = NewValue

		-- Client'ı bilgilendir
		self.Network.DataUpdated:FireClient(Player, Path, NewValue)
	else
		warn("Invalid data path provided: " .. tostring(Path))
	end
end

function PlayerService:UpdateData(Player : Player, Callback : ({}) -> ({}))
	local playerData = self.LoadedPlayers[Player]
	if not playerData then
		warn("Cannot update data, player not loaded: " .. Player.Name)
		return
	end
	
	local success, result = pcall(Callback, playerData)
	if success then
		if result ~= nil then
			self.LoadedPlayers[Player] = result
			playerData = result
		end
		self.Network.DataUpdated:FireClient(Player, nil, playerData)
	else
		warn("Error in UpdateData callback for " .. Player.Name .. ": " .. tostring(result))
	end
end

function PlayerService:OnStart()
	local function PlayerAdded(Player : Player)
		local Data = {
			VoteCount = 1,
			Chance = math.random(1, 7),
			RewardMultiplier = 1,
			Role = "",
			-- Can be added by other scripts
		}

		self.LoadedPlayers[Player] = Data
		self.Signals.PlayerAdded:Fire(Player)
	end

	for _,Player : Player in ipairs(Players:GetPlayers()) do
		task.spawn(PlayerAdded, Player)
	end

	Players.PlayerAdded:Connect(PlayerAdded)

	Players.PlayerRemoving:Connect(function(Player : Player)
		self.LoadedPlayers[Player] = nil
		self.Signals.PlayerRemoving:Fire(Player)
	end)

	-- Executable (Modüler eklenti sistemi)
	for _,Module : ModuleScript in ipairs(PlayerExecutable:GetChildren()) do
		if (not Module:IsA("ModuleScript")) then continue end

		local Success, Response = pcall(require, Module)
		if (not Success) then
			warn("Error requiring module: " .. Module.Name .. " - " .. tostring(Response))
			continue
		end

		if (typeof(Response) == "table") then
			if (typeof(Response.OnPlayerAdded) == "function") then
				-- Mevcut oyuncular için çalıştır
				for _, player in ipairs(Players:GetPlayers()) do
					task.spawn(function()
						Response:OnPlayerAdded(player)
					end)
				end

				-- Yeni gelenler için bağla
				self.Signals.PlayerAdded:Connect(function(Player : Player)
					Response:OnPlayerAdded(Player)
				end)
			end

			if (typeof(Response.OnPlayerRemoving) == "function") then
				self.Signals.PlayerRemoving:Connect(function(Player : Player)
					Response:OnPlayerRemoving(Player)
				end)
			end
		end
	end
end

return PlayerService
