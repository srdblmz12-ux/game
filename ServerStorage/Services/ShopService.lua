-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Variables
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Services = ServerStorage:WaitForChild("Services")
local ShopAssets = Shared:WaitForChild("ShopAssets")

local DataService = require(Services:WaitForChild("DataService"))
local MonetizationService = require(Services:WaitForChild("MonetizationService"))

-- ZORUNLU SLOTLAR: Bunlar Unequip edilemez, sadece değiştirilebilir.
local MANDATORY_SLOTS = {
	["KillerSkin"] = true,
}

local ShopService = {
	Name = "ShopService",
	Client = {},
	ItemList = {} 
}

--// Helper Functions

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
	local currentMoney = profileData.CurrencyData.Value

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

	local currentEquipped = profileData.Equippeds[equipSlot]
	local isMandatory = MANDATORY_SLOTS[equipSlot]

	-- Mantık: Takılı olanla aynı mı?
	if currentEquipped == itemName then
		-- Zaten takılıysa
		if isMandatory then
			return false, "Cannot unequip base item!" -- Skin çıkarılamaz
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

--// Client Functions

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
	-- 15000 Tokens
	MonetizationService:Register(MonetizationService.Type.Product, 3530798246, function(Player : Player)
		local Amount = 15000
		DataService:UpdateValue(Player, "CurrencyData.Value", Amount)
	end)

	-- 3500 Tokens
	MonetizationService:Register(MonetizationService.Type.Product, 3530798247, function(Player : Player)
		local Amount = 3500
		DataService:UpdateValue(Player, "CurrencyData.Value", Amount)
	end)

	-- 1500 Tokens
	MonetizationService:Register(MonetizationService.Type.Product, 3530798248, function(Player : Player)
		local Amount = 1500
		DataService:UpdateValue(Player, "CurrencyData.Value", Amount)
	end)

	-- 500 Tokens
	MonetizationService:Register(MonetizationService.Type.Product, 3530798249, function(Player : Player)
		local Amount = 500
		DataService:UpdateValue(Player, "CurrencyData.Value", Amount)
	end)
	
	-- Assets Yükleyici
	for _, CategoryFolder in ipairs(ShopAssets:GetChildren()) do
		for _, Item in ipairs(CategoryFolder:GetChildren()) do
			if (Item:IsA("ModuleScript")) then
				local Success, ModuleData = pcall(require, Item)
				if (Success) then
					self.ItemList[Item.Name] = ModuleData

					-- Kategori Yaması (Eğer modülde yoksa klasör adını al)
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