-- Services
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")

local FormatKit = require(Packages:WaitForChild("FormatKit")) 
local spr = require(Packages:WaitForChild("spr"))
local Net = require(Packages:WaitForChild("Net"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local IngameController = {
	Name = script.Name,
	LocalData = nil, -- [YENİ] Yerel Veri Önbelleği (Cache)
}

--// UI UPDATE FUNCTIONS

function IngameController:UpdateCurrency()
	if not self.LocalData or not self.LocalData.CurrencyData then return end

	local amount = self.LocalData.CurrencyData.Value or 0
	local IngameHUD = PlayerGui:WaitForChild("IngameHUD", 5)

	if IngameHUD then
		local Sidebar = IngameHUD:WaitForChild("SidebarContainer")
		local ShopFrame = Sidebar:WaitForChild("Shop")
		local TokenLabel = ShopFrame:WaitForChild("TokenValue")

		-- spr efekti eklenebilir (Token artınca yazı büyüyüp küçülür)
		TokenLabel.Text = "Tokens: " .. FormatKit.FormatComma(amount)
	end
end

function IngameController:UpdateChance(amount)
	local IngameHUD = PlayerGui:WaitForChild("IngameHUD", 5)
	if IngameHUD then
		local Sidebar = IngameHUD:WaitForChild("SidebarContainer")
		local LuckFrame = Sidebar:WaitForChild("LuckRatio")
		local LuckLabel = LuckFrame:FindFirstChild("LuckRatio") or LuckFrame:FindFirstChild("Title")

		if LuckLabel then
			LuckLabel.Text = "Chance to be killer: " .. tostring(amount) .. "%"
		end
	end
end

function IngameController:UpdateLevel()
	if not self.LocalData or not self.LocalData.LevelData then return end

	local levelData = self.LocalData.LevelData
	local LevelHUD = PlayerGui:WaitForChild("LevelHUD", 5)

	if LevelHUD then
		local Container = LevelHUD:WaitForChild("LevelContainer")
		local ValueCont = Container:WaitForChild("ValueContainer")
		local LevelBar = Container:WaitForChild("LevelBar")

		ValueCont.Level.Text = "Level " .. tostring(levelData.Level)
		ValueCont.CurrentXP.Text = string.format("%d/%d", levelData.ValueXP, levelData.TargetXP)

		local fillBar = LevelBar:FindFirstChild("FillBar")
		if fillBar then
			local percent = math.clamp(levelData.ValueXP / levelData.TargetXP, 0, 1)
			-- spr ile yumuşak geçiş
			spr.target(fillBar, 0.8, 2, {Size = UDim2.fromScale(percent, 1)})
		end
	end
end

--// DATA HANDLING

function IngameController:RefreshAllData()
	-- 1. Tüm Veriyi Çek ve Cache'e Yaz
	local Data = Net:Invoke("DataService/GetData") -- DataService.Client:GetData tetiklenir
	if Data then
		self.LocalData = Data

		-- UI'ları Cache'den güncelle
		self:UpdateCurrency()
		self:UpdateLevel()
	end

	-- 2. Şans Verisini Çek
	local success, chance = pcall(function()
		return Net:Invoke("PlayerService/GetChance")
	end)
	if success and chance then
		self:UpdateChance(chance)
	end
end

function IngameController:OnStart()
	-- UI Referansları
	local IngameHUD = PlayerGui:WaitForChild("IngameHUD", 5)
	if IngameHUD then
		local Sidebar = IngameHUD:WaitForChild("SidebarContainer")
		local LuckFrame = Sidebar:WaitForChild("LuckRatio")

		-- Ürün Satın Alma
		local promptBtn = LuckFrame:FindFirstChild("ProductPrompt")
		if promptBtn then
			promptBtn.Activated:Connect(function()
				MarketplaceService:PromptProductPurchase(LocalPlayer, 3530798250)
			end)
		end
	end

	-- [GÜNCELLENMİŞ NETWORK] DataUpdate Sinyali
	-- Sunucudan gelen: (Path, NewValue) -> Örn: ("CurrencyData.Value", 150)
	Net:Connect("DataUpdate", function(Path, NewValue)
		if not self.LocalData then return end

		-- 1. Yerel Datayı Güncelle (Cache Update)
		-- Gelen Path'i parçalayıp yerel tabloyu güncelliyoruz
		if Path == "CurrencyData.Value" then
			self.LocalData.CurrencyData.Value = NewValue
			self:UpdateCurrency()

		elseif Path == "LevelData.ValueXP" then
			self.LocalData.LevelData.ValueXP = NewValue
			self:UpdateLevel()

		elseif Path == "LevelData.Level" then
			self.LocalData.LevelData.Level = NewValue
			self:UpdateLevel()

		elseif Path == "LevelData.TargetXP" then
			self.LocalData.LevelData.TargetXP = NewValue
			self:UpdateLevel()
		end
	end)

	Net:Connect("ChanceUpdate", function(NewChance)
		self:UpdateChance(NewChance)
	end)

	-- İlk Yükleme
	self:RefreshAllData()

	-- Karakter Respawn Olduğunda UI'ı Yenile
	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.5)
		self:RefreshAllData()
	end)
end

return IngameController