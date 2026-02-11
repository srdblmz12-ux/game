-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LightingImporter = require(Packages:WaitForChild("LightingImporter")) -- Ismi kontrol et: 'LighingImporter' yazmissin, 'LightingImporter' olabilir.
local Net = require(Packages:WaitForChild("Net"))

local LightingAssets = Shared:WaitForChild("LightingAssets")
local DefaultLighting = require(LightingAssets:WaitForChild("DefaultLighting"))
local FallbackLighting = require(LightingAssets:WaitForChild("FallbackLighing"))

-- Module
local LightingController = {
	Name = script.Name
}

--// Lighting Verisini Isle ve Uygula
function LightingController:ApplyLighting(lightingData)
	if not lightingData then
		LightingImporter.ImportJSON(FallbackLighting, true)
		return
	end

	LightingImporter.ImportJSON(lightingData, true)
end

function LightingController:OnStart()
	-- 1. GameService'den gelen özel Lighting yükleme istegi
	Net:Connect("LoadLighting", function(lightingData)
		self:ApplyLighting(lightingData)
	end)

	-- 2. MapService'den gelen harita yüklenme sinyali (Burada da lighting verisi var)
	Net:Connect("MapLoaded", function(mapName, lightingData)
		self:ApplyLighting(lightingData)
	end)

	-- Opsiyonel: Oyun bittiginde veya harita silindiginde varsayilan lighting'e dönmek istersen:
	Net:Connect("MapUnloaded", function()
		LightingImporter.ImportJSON(DefaultLighting, true)
	end)
end

return LightingController