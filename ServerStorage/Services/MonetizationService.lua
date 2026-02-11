-- Services
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Signal = require(Packages:WaitForChild("Signal"))
local Net = require(Packages:WaitForChild("Net"))

-- Module
local MonetizationService = {
	Name = script.Name,
	Client = {},

	-- Kayıt edilen fonksiyonları tutacağımız tablolar
	_productHandlers = {},
	_gamepassHandlers = {},

	-- Enum gibi kullanım için tipler
	Type = {
		Product = "Product",
		Gamepass = "Gamepass"
	},

	Signals = {
		PurchaseCompleted = Signal.new()
	},
	Network = {
		PurchaseCompleted = Net:RemoteEvent("PurchaseCompleted")
	}
}

-- Satın alma işlemi tanımlama fonksiyonu
function MonetizationService:Register(type, id, callback)
	if type == self.Type.Product then
		self._productHandlers[id] = callback
	elseif type == self.Type.Gamepass then
		self._gamepassHandlers[id] = callback
	end
end

-- Developer Product satın aldırma
function MonetizationService:PromptProduct(player, productId)
	MarketplaceService:PromptProductPurchase(player, productId)
end

-- Gamepass satın aldırma
function MonetizationService:PromptGamepass(player, gamePassId)
	MarketplaceService:PromptGamePassPurchase(player, gamePassId)
end

-- Oyuncunun Gamepass'e sahip olup olmadığını kontrol etme
function MonetizationService:UserHas(player, gamePassId)
	local success, hasPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
	end)

	if success then
		return hasPass
	end
	return false
end

function MonetizationService:OnInit()
	-- Developer Product İşlemleri (ProcessReceipt)
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local playerId = receiptInfo.PlayerId
		local productId = receiptInfo.ProductId
		local player = Players:GetPlayerByUserId(playerId)

		local handler = self._productHandlers[productId]

		if handler and player then
			-- Handler fonksiyonunu çalıştır (başarılıysa true dönmeli)
			local success, result = pcall(handler, player)

			if success and result == true then
				self.Signals.PurchaseCompleted:Fire(player, productId, self.Type.Product)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
		end

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Gamepass İşlemleri
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if wasPurchased then
			local handler = self._gamepassHandlers[gamePassId]

			if handler then
				task.spawn(handler, player)
			end

			self.Signals.PurchaseCompleted:Fire(player, gamePassId, self.Type.Gamepass)
		end
	end)
end

function MonetizationService:OnStart()
end

return MonetizationService
