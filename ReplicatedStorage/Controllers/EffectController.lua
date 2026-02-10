-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")

local EffectAssets = Common:WaitForChild("EffectAssets")

local Signal = require(Packages:WaitForChild("Signal"))
local Trove = require(Packages:WaitForChild("Trove"))
local Net = require(Packages:WaitForChild("Net"))

-- Module
local EffectController = {
	Name = script.Name,
	Signals = {
		StartFX = Signal.new(), -- Client içinden tetiklemek istersen: self.Signals.StartFX:Fire("BloodSplash", ...)
	},
	LoadedEffects = {} -- Efekt modüllerini burada tutacağız
}

-- // YARDIMCI: Efekti Çalıştıran Fonksiyon
function EffectController:_playEffect(effectName, ...)
	local effectModule = self.LoadedEffects[effectName]

	if not effectModule then
		warn("[EffectController] Effect not found:", effectName)
		return
	end

	-- Her efekt için yeni bir Trove oluşturuyoruz.
	-- Efekt modülü işi bitince bu trove'u temizlemeli veya trove içindeki objeler süre bitince silinmeli.
	local effectTrove = Trove.new()

	-- Hata olursa diğer kodları durdurmasın diye task.spawn içinde çalıştırıyoruz
	task.spawn(function(...)
		if effectModule.Activate then
			-- :Activate(Trove, Argumanlar...)
			effectModule:Activate(effectTrove, ...)
		else
			warn("[EffectController] Activate method missing in:", effectName)
			effectTrove:Destroy() -- Hatalıysa hemen temizle
		end
	end, ...)
end

function EffectController:OnStart()
	-- 1. EffectAssets Klasöründeki Modülleri Yükle
	for _, moduleScript in ipairs(EffectAssets:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			local success, result = pcall(require, moduleScript)
			if success then
				self.LoadedEffects[moduleScript.Name] = result
				-- print("[EffectController] Loaded:", moduleScript.Name)
			else
				warn("[EffectController] Failed to load effect:", moduleScript.Name, result)
			end
		end
	end

	-- 2. Server'dan Gelen Efektleri Dinle
	-- Örn: Server "BloodSplash", Motor6D gönderdiğinde burası yakalar
	local startFXEvent = Net:RemoteEvent("StartFX")
	startFXEvent.OnClientEvent:Connect(function(effectName, ...)
		self:_playEffect(effectName, ...)
	end)

	-- 3. Client İçi (Local) Efektleri Dinle
	-- Örn: UI butonuna basınca efekt çıksın istersen
	self.Signals.StartFX:Connect(function(effectName, ...)
		self:_playEffect(effectName, ...)
	end)
end

return EffectController