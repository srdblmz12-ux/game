-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local UserService = game:GetService("UserService")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")
local Shared = ReplicatedStorage:WaitForChild("Shared")

-- Assets
local MapsFolder = Shared:WaitForChild("MapAssets")

-- Dependencies
local Trove = require(Packages:WaitForChild("Trove"))
local Signal = require(Packages:WaitForChild("Signal"))
local Net = require(Packages:WaitForChild("Net"))
local Promise = require(Packages:WaitForChild("Promise"))

local MapService = {
	Name = "MapService",
	Client = {},

	CurrentMap = nil, -- Yüklenen harita verisi
	_mapTrove = nil,  -- Temizlikten sorumlu Trove

	Signals = {
		MapLoaded = Signal.new(),
		MapUnloaded = Signal.new()
	},

	Network = {
		MapLoaded = Net:RemoteEvent("MapLoaded"),
		MapUnloaded = Net:RemoteEvent("MapUnloaded"),
		MapList = Net:RemoteEvent("MapList"),
	}
}

--// HELPER: Modül Bulucu
function MapService:_findMapModule(mapName)
	if not mapName then return nil end
	-- Hem ServerStorage hem Shared kontrolü (ne olur ne olmaz)
	return MapsFolder:FindFirstChild(mapName)
end

--// HELPER: Spawn Noktalarını Bul
function MapService:_findSpawns(mapModel)
	local spawns = {}
	if not mapModel then return spawns end

	-- Eğer "Spawns" klasörü varsa oradan al
	local folder = mapModel:FindFirstChild("Spawns")
	if folder then
		return folder:GetChildren()
	end

	-- Yoksa tüm haritayı tara
	for _, child in ipairs(mapModel:GetDescendants()) do
		if child:IsA("SpawnLocation") or child.Name == "Spawn" then
			table.insert(spawns, child)
		end
	end

	return spawns
end

--// CLEANUP: Haritayı ve Bağlantıları Temizle
function MapService:Cleanup()
	if self._mapTrove then
		self._mapTrove:Destroy() -- Haritayı workspace'den siler, eventleri koparır
		self._mapTrove = nil
	end

	self.CurrentMap = nil

	-- Client'lara bildir
	self.Signals.MapUnloaded:Fire()
	self.Network.MapUnloaded:FireAllClients()

	print("MapService: Cleanup complete.")
end

--// LOAD MAP: Haritayı Yükle
function MapService:LoadMap(mapName)
	-- 1. Önce eski haritayı temizle
	self:Cleanup()

	-- 2. Modülü bul
	local mapModule = self:_findMapModule(mapName)
	if not mapModule then
		warn("MapService: Map module not found ->", mapName)
		return nil
	end

	local success, mapData = pcall(require, mapModule)
	if not success or not mapData or not mapData.Map then
		warn("MapService: Invalid map module ->", mapName)
		return nil
	end

	-- 3. Yeni Trove oluştur
	self._mapTrove = Trove.new()

	-- 4. Haritayı Kopyala
	local newMapModel = mapData.Map:Clone()
	newMapModel.Name = mapName
	newMapModel.Parent = workspace

	-- Trove'a ekle (Cleanup çağrılınca otomatik silinecek)
	self._mapTrove:Add(newMapModel)

	-- 5. Init Fonksiyonu Varsa Çalıştır
	if type(mapData.Init) == "function" then
		task.spawn(function()
			pcall(mapData.Init, newMapModel)
		end)
	end

	-- 6. Verileri Hazırla
	local finalMapData = {
		Name = mapName,
		Model = newMapModel,
		Lighting = mapData.Lighting, -- Lighting ayarlarını al
		Spawns = self:_findSpawns(newMapModel), -- Spawnları bul
		Authors = mapData.Authors or {}
	}

	self.CurrentMap = finalMapData

	-- 7. Bildirimler
	self.Signals.MapLoaded:Fire(finalMapData)
	self.Network.MapLoaded:FireAllClients(mapName, mapData.Lighting) -- Client'a ismi ve lighting'i at

	print("MapService: Loaded map ->", mapName)

	return finalMapData -- GameService bunu bekliyor
end

--// VOTING: Oylama Seçeneklerini Hazırla
function MapService:GetProcessedVoteOptions(count)
	local availableModules = MapsFolder:GetChildren()
	local selectedOptions = {}
	local usedIndices = {}

	local amountToSelect = math.min(count, #availableModules)

	-- Rastgele Seçim
	while #selectedOptions < amountToSelect do
		local randomIndex = math.random(1, #availableModules)
		if not usedIndices[randomIndex] then
			usedIndices[randomIndex] = true
			local module = availableModules[randomIndex]

			if module:IsA("ModuleScript") then
				table.insert(selectedOptions, module)
			end
		end
	end

	-- Verileri İşle (Promise ile)
	local promises = {}

	for _, mod in ipairs(selectedOptions) do
		table.insert(promises, Promise.new(function(resolve)
			local success, data = pcall(require, mod)

			local info = {
				Id = mod.Name, -- ÖNEMLİ: GameService ID olarak ismi kullanıyor
				Name = (success and data.Name) or mod.Name,
				Image = (success and data.Image) or "",
				Authors = (success and data.Authors) or {}
			}

			-- Eğer Yazar ID'leri varsa isme çevir (Eski kodundaki özellik)
			if #info.Authors > 0 and type(info.Authors[1]) == "number" then
				pcall(function()
					local userInfos = UserService:GetUserInfosByUserIdsAsync(info.Authors)
					local names = {}
					for _, u in ipairs(userInfos) do
						table.insert(names, u.DisplayName)
					end
					info.Authors = names
				end)
			end

			resolve(info)
		end))
	end

	local success, results = Promise.all(promises):await()
	return success and results or {}
end

--// UTILS
function MapService:IsValidMap(mapName)
	return self:_findMapModule(mapName) ~= nil
end

-- GameService uyumluluğu için (Eğer hala eski koddan kalan bir yer varsa)
function MapService:FindMapModule(mapName)
	return self:_findMapModule(mapName)
end

return MapService
