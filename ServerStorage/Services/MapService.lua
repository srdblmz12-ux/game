-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

-- Assets
local MapsFolder = Shared:WaitForChild("MapAssets")

-- Dependencies
local Trove = require(Packages:WaitForChild("Trove"))
local Signal = require(Packages:WaitForChild("Signal"))
local Net = require(Packages:WaitForChild("Net"))

local MapService = {
	Name = "MapService",
	Client = {},

	CurrentMap = nil, 
	_trove = nil,  

	Signals = {
		MapLoaded = Signal.new(),
		MapUnloaded = Signal.new()
	},

	Network = {
		MapLoaded = Net:RemoteEvent("MapLoaded"),
		MapUnloaded = Net:RemoteEvent("MapUnloaded"),
	}
}

-- =============================================================================
--  LOGIC
-- =============================================================================

function MapService:GetInstalledMaps()
	return MapsFolder:GetChildren()
end

function MapService:LoadMap(mapName)
	-- Eğer zaten bir harita yüklüyse kaldır
	if self.CurrentMap then
		self:UnloadMap()
	end

	local mapModule = self:_findMapModule(mapName)
	if not mapModule then
		warn("[MapService] Map Module not found: " .. tostring(mapName))
		return nil
	end

	print("[MapService] Loading Map: " .. mapName)

	-- Trove temizleyici başlat
	self._trove = Trove.new()

	-- [CRITICAL FIX] "Path must begin with" hatası require(string) yapınca olur.
	-- mapModule'ün kesinlikle bir Instance olduğundan emin oluyoruz.
	if typeof(mapModule) ~= "Instance" or not mapModule:IsA("ModuleScript") then
		warn("[MapService] HATA: Harita bir ModuleScript olmalı! Bulunan:", typeof(mapModule), mapModule)
		return nil
	end

	-- Modülü require et (Senin yapında bir tablo dönüyor: { Map = ..., Name = ... })
	local success, mapData = pcall(require, mapModule)

	if not success then
		warn("[MapService] Harita modülü yüklenirken hata oluştu:", mapData)
		return nil
	end

	-- Şimdi harita modelini bulup klonluyoruz
	local mapModelToClone = nil

	-- 1. Durum: Modülün içinde .Map referansı varsa (Senin City modülün böyle)
	if type(mapData) == "table" and mapData.Map then
		mapModelToClone = mapData.Map
		-- 2. Durum: Modül direkt bir Model dönüyorsa
	elseif typeof(mapData) == "Instance" then
		mapModelToClone = mapData
		-- 3. Durum: Modülün altında "Build" veya "Map" diye bir klasör/model varsa
	else
		mapModelToClone = mapModule:FindFirstChild("Build") or mapModule:FindFirstChild("Map")
	end

	if not mapModelToClone then
		warn("[MapService] Harita modeli (Build) bulunamadı! Modül yapısını kontrol et.")
		return nil
	end

	-- Klonlama işlemi
	local clone = mapModelToClone:Clone()
	clone.Name = mapName -- İsmini düzelt
	clone.Parent = workspace
	self._trove:Add(clone)
	self.CurrentMap = clone

	self.Signals.MapLoaded:Fire(mapName)
	self.Network.MapLoaded:FireAllClients(mapName)

	return self.CurrentMap
end

function MapService:UnloadMap()
	if self._trove then
		self._trove:Destroy()
		self._trove = nil
	end
	self.CurrentMap = nil

	self.Signals.MapUnloaded:Fire()
	self.Network.MapUnloaded:FireAllClients()
end

function MapService:GetSpawns(Map: Folder | Model): {SpawnLocation}
	local spawns = {}
	if not Map then
		warn("[MapService] GetSpawns: Harita bulunamadı.")
		return spawns
	end

	-- 1. Öncelik: "Spawns" klasörünü kontrol et
	local spawnsFolder = Map:WaitForChild("Spawns", 5)
	if spawnsFolder then
		-- Klasör varsa içindeki her şeyi spawn olarak kabul edip döndür
		spawns = spawnsFolder:GetChildren()
	else
		-- 2. Öncelik: Klasör yoksa, haritanın ana dizinindeki (GetChildren) SpawnLocation'ları topla
		for _, child in ipairs(Map:GetChildren()) do
			if child:IsA("SpawnLocation") then
				table.insert(spawns, child)
			end
		end
	end

	return spawns
end

-- =============================================================================
--  UTILS
-- =============================================================================

function MapService:_findMapModule(mapName)
	if not mapName then return nil end
	-- İsme göre bul (String değil, Instance döner)
	return MapsFolder:FindFirstChild(mapName)
end

function MapService:OnStart()
	-- Init
end

return MapService
