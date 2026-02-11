local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Services = ServerStorage:WaitForChild("Services")
local Modules = ServerStorage:WaitForChild("Modules")

local DataService = require(Services:WaitForChild("DataService"))
local PlayerService = require(Services:WaitForChild("PlayerService"))
local BetterAnalytics = require(Modules:WaitForChild("BetterAnalyticsService"))

local RewardService = {
	Name = script.Name,
	Client = {}
}

function RewardService:AddCurrency(player, amount, reason)
	local safeAmount = tonumber(amount)
	if not safeAmount or safeAmount <= 0 then return end

	reason = reason or "GameplayReward"
	
	local success, PlayerData = PlayerService:GetData(player):await()
	safeAmount = safeAmount * (success and (PlayerData.RewardMultiplier or 1) or 1)


	-- 2. Veriyi DataService üzerinden güncelle
	local newBalance = DataService:UpdateValue(player, "CurrencyData.Value", safeAmount)

	-- Eğer profil yüklü değilse işlem durur
	if not newBalance then return end

	-- Toplam kazanılan parayı da güncelle (İstatistik için)
	DataService:UpdateValue(player, "CurrencyData.Total", safeAmount)

	print("[RewardService] " .. player.Name .. " +" .. safeAmount .. " Token (" .. reason .. ")")

	-- 3. ANALYTICS
	-- Analytics'e X2 uygulanmış gerçek kazanılan değeri gönderiyoruz.
	BetterAnalytics:LogEconomyEvent(
		player,
		"Source",     -- Flow: Gelir
		"Token",      -- Currency
		safeAmount,   -- Miktar (x2 dahil)
		newBalance,   -- Güncel Bakiye
		"Gameplay",   -- TransactionType
		reason,       -- ItemSku
		nil           -- CustomFields
	)
end

function RewardService:OnStart()
	-- Başlangıç işlemleri gerekirse buraya
end

return RewardService
