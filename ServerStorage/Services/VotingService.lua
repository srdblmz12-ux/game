-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Services = ServerStorage:WaitForChild("Services")

-- Dependencies
local Signal = require(Packages:WaitForChild("Signal"))
local Net = require(Packages:WaitForChild("Net"))

-- Service Dependencies
local MapService = require(Services:WaitForChild("MapService"))

local VotingService = {
	Name = "VotingService",
	Client = {},

	-- State
	_isVotingActive = false,
	_currentOptions = {}, -- {MapName1, MapName2, MapName3}
	_votes = {}, -- { [UserId] = "MapName" }

	Signals = {
		VotingStarted = Signal.new(),
		VotingEnded = Signal.new(),
		VotesUpdated = Signal.new()
	},

	Network = {
		UpdateVotes = Net:RemoteEvent("UpdateVotes"),
		SetOptions = Net:RemoteEvent("SetOptions"),
		SubmitVote = Net:RemoteEvent("SubmitVote"),-- Client'tan gelen oy isteği
		
		GameStarted = Net:RemoteEvent("GameStarted"), 
		VoteOptions = Net:RemoteEvent("VoteOptions"),
	}
}

-- =============================================================================
--  LOGIC
-- =============================================================================

function VotingService:StartVoting()
	self._isVotingActive = true
	self._votes = {}

	-- 1. Haritaları seç
	local allMaps = MapService:GetInstalledMaps()
	self._currentOptions = self:_pickRandomMaps(allMaps, 3)

	-- 2. Clientlara bildir
	self.Network.SetOptions:FireAllClients(self._currentOptions)
	self.Network.UpdateVotes:FireAllClients({})

	self.Signals.VotingStarted:Fire(self._currentOptions)
	print("[VotingService] Oylama Başladı:", table.concat(self._currentOptions, ", "))
end

function VotingService:EndVoting()
	self._isVotingActive = false

	-- 1. Kazananı belirle
	local winner = self:_calculateWinner()

	-- 2. Sinyal gönder
	self.Signals.VotingEnded:Fire(winner)
	print("[VotingService] Kazanan Harita:", winner)

	return winner
end

function VotingService:CastVote(player, mapName)
	if not self._isVotingActive then return end

	-- Geçerli bir seçenek mi?
	if not table.find(self._currentOptions, mapName) then return end

	-- Oyu kaydet
	self._votes[player.UserId] = mapName

	-- Herkese güncel durumu yolla
	self:_broadcastVotes()
end

-- =============================================================================
--  HELPERS
-- =============================================================================

function VotingService:_calculateWinner()
	local counts = {}

	-- Sayaçları hazırla
	for _, mapName in ipairs(self._currentOptions) do
		counts[mapName] = 0
	end

	-- Oyları say
	for _, votedMap in pairs(self._votes) do
		if counts[votedMap] then
			counts[votedMap] += 1
		end
	end

	-- En yükseği bul
	local winner = nil
	local maxVotes = -1
	local ties = {}

	for mapName, count in pairs(counts) do
		if count > maxVotes then
			maxVotes = count
			winner = mapName
			ties = {mapName}
		elseif count == maxVotes then
			table.insert(ties, mapName)
		end
	end

	-- Eşitlik varsa rastgele seç
	if #ties > 1 then
		winner = ties[math.random(1, #ties)]
	end

	return winner or self._currentOptions[1] or "Unknown"
end

function VotingService:_broadcastVotes()
	self.Network.UpdateVotes:FireAllClients(self._votes)
end

function VotingService:_pickRandomMaps(mapList, count)
	local available = {}
	for _, map in ipairs(mapList) do
		table.insert(available, map.Name)
	end

	-- Karıştır
	for i = #available, 2, -1 do
		local j = math.random(i)
		available[i], available[j] = available[j], available[i]
	end

	-- Seç
	local selected = {}
	for i = 1, math.min(count, #available) do
		table.insert(selected, available[i])
	end

	return selected
end

-- =============================================================================
--  INIT
-- =============================================================================

function VotingService:OnStart()
	-- Client'tan gelen oyları dinle
	self.Network.SubmitVote.OnServerEvent:Connect(function(player, mapName)
		self:CastVote(player, mapName)
	end)
end

return VotingService
