local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Services = ServerStorage:WaitForChild("Services")
local Modules = ServerStorage:WaitForChild("Modules")

local DataService = require(Services:WaitForChild("DataService"))
local BetterAnalytics = require(Modules:WaitForChild("BetterAnalyticsService"))

local RewardService = {
	Name = script.Name,
	Client = {}
}

--// YARDIMCI FONKSİYON: Çarpan Hesaplayıcı
local function GetMultiplier(player)
	-- Eğer oyuncuda VIP özelliği varsa 2, yoksa 1 döner
	if player:GetAttribute("VIP") then
		return 2
	end
	return 1
end

function RewardService:AddCurrency(player, amount, reason)
	local safeAmount = tonumber(amount)
	if not safeAmount or safeAmount <= 0 then return end

	reason = reason or "GameplayReward"

	-- 1. VIP KONTROLÜ (2x TOKEN)
	-- Normal miktar ile çarpanı çarpıyoruz
	local multiplier = GetMultiplier(player)
	safeAmount = safeAmount * multiplier

	-- Konsola bilgi (Opsiyonel, debug için)
	if multiplier > 1 then
		print("[RewardService] VIP Bonus Aktif: 2x Token kazandı!")
	end

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

function RewardService:AddXP(player, amount)
	-- Veriyi okuyoruz
	local currentData = DataService:GetData(player)
	if not currentData then return end

	local levelData = currentData.LevelData

	-- 1. VIP KONTROLÜ (2x XP)
	-- Kazanılan XP miktarını çarpıyoruz
	local multiplier = GetMultiplier(player)
	local finalAmount = amount * multiplier

	-- Hesaplamaları yapalım
	local newXP = levelData.ValueXP + finalAmount
	local currentLevel = levelData.Level
	local currentTarget = levelData.TargetXP

	local leveledUp = false

	-- Level atlama döngüsü
	while newXP >= currentTarget do
		newXP = newXP - currentTarget
		currentLevel = currentLevel + 1
		currentTarget = math.floor(currentTarget * 1.2) -- Zorluk artışı
		leveledUp = true
	end

	-- 2. Sonuçları DataService'e kaydet
	DataService:SetValue(player, "LevelData.ValueXP", newXP)

	if leveledUp then
		-- Level ve Hedef XP'yi güncelle
		DataService:SetValue(player, "LevelData.Level", currentLevel)
		DataService:SetValue(player, "LevelData.TargetXP", currentTarget)

		-- Bonus ver (Level atlayınca verilen para)
		-- NOT: Buradaki 50 token de AddCurrency içindeki VIP kontrolü sayesinde 
		-- otomatik olarak 100 token olacaktır.
		self:AddCurrency(player, 50, "LevelUpBonus")
	end
end

function RewardService:OnStart()
	-- Başlangıç işlemleri gerekirse buraya
end

return RewardService