-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Services = ServerStorage:WaitForChild("Services")
local ShopAssets = Shared:WaitForChild("ShopAssets")

-- Diğer servislerin doğru yüklendiğinden emin olun
local DataService = require(Services:WaitForChild("DataService"))
local MonetizationService = require(Services:WaitForChild("MonetizationService"))

-- ZORUNLU SLOTLAR (Çıkarılamaz, sadece değiştirilebilir)
local MANDATORY_SLOTS = {
	["KillerSkin"] = true,
}

local ShopService = {
	Name = "ShopService",
	Client = {},
	ItemList = {} 
}

--// Helper Functions (İç Mantık)

function ShopService:ProcessPurchase(player, itemName)
	local itemData = self.ItemList[itemName]
	if not itemData then return false, "Item not found" end

	local profileData = DataService:GetData(player)
	if not profileData then return false, "Data loading..." end

	local categoryName = itemData.DataCategory or itemData.Category

	-- Sahiplik Kontrolü
	if self:UserHas(player, categoryName, itemName) then
		return false, "Already owned"
	end

	-- Para Kontrolü
	local price = itemData.Price or 0
	local currentMoney = 0

	if profileData.CurrencyData then
		currentMoney = profileData.CurrencyData.Value
	end

	if currentMoney >= price then
		-- 1. Parayı Düş
		DataService:UpdateValue(player, "CurrencyData.Value", -price)

		-- 2. Eşyayı Ver
		DataService:SetDictionaryItem(player, categoryName, itemName, true)

		print(player.Name .. " bought: " .. itemName)
		return true, "Successfully purchased!"
	else
		return false, "Not enough Token!"
	end
end

function ShopService:ProcessEquip(player, itemName)
	local itemData = self.ItemList[itemName]
	if not itemData then return false, "Item not found" end

	local profileData = DataService:GetData(player)
	if not profileData then return false, "Data loading..." end

	-- Sahiplik Kontrolü
	local categoryName = itemData.DataCategory or itemData.Category
	if not self:UserHas(player, categoryName, itemName) then
		return false, "You don't own this!"
	end

	local equipSlot = itemData.EquipSlot
	if not equipSlot then return false, "Not equippable" end

	local currentEquipped = ""
	if profileData.Equippeds then
		currentEquipped = profileData.Equippeds[equipSlot]
	end

	local isMandatory = MANDATORY_SLOTS[equipSlot]

	-- Mantık: Takılı olanla aynı mı?
	if currentEquipped == itemName then
		-- Zaten takılıysa
		if isMandatory then
			return false, "Cannot unequip base item!" -- Skin çıkarılamaz, yerine başkası takılmalı
		else
			DataService:SetValue(player, "Equippeds." .. equipSlot, "") 
			return true, "Unequipped"
		end
	else
		-- Farklıysa değiştir
		DataService:SetValue(player, "Equippeds." .. equipSlot, itemName)
		return true, "Equipped"
	end
end

function ShopService:UserHas(player, category, itemName)
	local profileData = DataService:GetData(player)
	if not profileData then return false end

	if profileData[category] and profileData[category][itemName] then
		return true
	end
	return false
end

--// Client Functions (Client'tan Gelen İstekler)

function ShopService.Client:Purchase(player, itemName)
	return ShopService:ProcessPurchase(player, itemName)
end

function ShopService.Client:EquipItem(player, itemName)
	return ShopService:ProcessEquip(player, itemName)
end

function ShopService.Client:GetItemData(player, itemName)
	return ShopService.ItemList[itemName]
end

function ShopService:OnStart()
	-- Robux ile Token Satın Alımları (DevProducts)
	-- ID'lerin MonetizationService veya Developer Dashboard ile eşleştiğinden emin olun.

	-- 15000 Tokens
	MonetizationService:Register(MonetizationService.Type.Product, 3530798246, function(Player)
		DataService:UpdateValue(Player, "CurrencyData.Value", 15000)
	end)

	-- 3500 Tokens
	MonetizationService:Register(MonetizationService.Type.Product, 3530798247, function(Player)
		DataService:UpdateValue(Player, "CurrencyData.Value", 3500)
	end)

	-- 1500 Tokens
	MonetizationService:Register(MonetizationService.Type.Product, 3530798248, function(Player)
		DataService:UpdateValue(Player, "CurrencyData.Value", 1500)
	end)

	-- 500 Tokens
	MonetizationService:Register(MonetizationService.Type.Product, 3530798249, function(Player)
		DataService:UpdateValue(Player, "CurrencyData.Value", 500)
	end)

	-- Eşya Verilerini Yükle
	for _, CategoryFolder in ipairs(ShopAssets:GetChildren()) do
		for _, Item in ipairs(CategoryFolder:GetChildren()) do
			if (Item:IsA("ModuleScript")) then
				local Success, ModuleData = pcall(require, Item)
				if (Success) then
					self.ItemList[Item.Name] = ModuleData

					-- Kategori Ataması (Otomatik)
					if not ModuleData.Category and not ModuleData.DataCategory then
						ModuleData.Category = CategoryFolder.Name
					end
				else
					warn("ShopService Load Fail: " .. Item.Name)
				end
			end
		end
	end
end

return ShopService
