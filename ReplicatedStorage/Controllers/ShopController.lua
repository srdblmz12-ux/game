-- Controllers
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Interface = Common:WaitForChild("Interface")

-- ShopAssets (UI Prefabları)
local UIShopAssets = Interface:WaitForChild("ShopAssets")
local ShopAssets = Shared:WaitForChild("ShopAssets")

local FormatKit = require(Packages:WaitForChild("FormatKit"))
local Net = require(Packages:WaitForChild("Net"))
local NotificationController = require(ReplicatedStorage.Controllers.NotificationController)

-- Robux Ürünleri (Eksik bakiye tamamlama için)
local ROBUX_PRODUCTS = {
	{Id = 3530798246, Amount = 15000},
	{Id = 3530798247, Amount = 3500},
	{Id = 3530798248, Amount = 1500},
	{Id = 3530798249, Amount = 500},
}

local ShopController = {
	Name = "ShopController",
	Pages = {},
	Buttons = {},
	CardCache = {}, 
	CachedData = nil
}

--// Helper: Viewport Kamera Ayarı (3D Önizleme)
local function SetupViewportCamera(viewportFrame, model)
	local camera = Instance.new("Camera")
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera

	local head = model:FindFirstChild("Head")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChild("Torso")

	if head and root then
		-- Karakter modelleri için kafaya odaklan
		local headPos = head.Position
		local targetPos = headPos - Vector3.new(0, 0.5, 0) 
		local camPos = headPos + (root.CFrame.LookVector * 7) + Vector3.new(0, 0.5, 0)

		camera.CFrame = CFrame.lookAt(camPos, targetPos)
		camera.FieldOfView = 35 
	else
		-- Eşya modelleri için genel odak
		local cf, size = model:GetBoundingBox()
		camera.CFrame = CFrame.lookAt(cf.Position + (cf.LookVector * 9), cf.Position)
		camera.FieldOfView = 40
	end
end

--// Bakiye Yetersizse Paket Önerisi
function ShopController:PromptBestProduct(itemPrice)
	local currentMoney = (self.CachedData and self.CachedData.CurrencyData and self.CachedData.CurrencyData.Value) or 0
	local deficit = itemPrice - currentMoney

	if deficit <= 0 then return end

	-- Ürünleri fiyata göre sırala
	table.sort(ROBUX_PRODUCTS, function(a, b) return a.Amount < b.Amount end)

	local bestProduct = nil
	for _, product in ipairs(ROBUX_PRODUCTS) do
		if product.Amount >= deficit then
			bestProduct = product
			break
		end
	end

	if not bestProduct then
		bestProduct = ROBUX_PRODUCTS[#ROBUX_PRODUCTS]
	end

	if bestProduct then
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, bestProduct.Id)
	end
end

function ShopController:UpdateCardState(card, details)
	local currentData = self.CachedData
	if not currentData then return end

	local isOwned = false
	local catName = details.DataCategory or details.Category

	-- Veriden sahiplik kontrolü
	if currentData[catName] and currentData[catName][details.Id] then
		isOwned = true
	end

	-- Kuşanılmış mı kontrolü
	local isEquipped = false
	if isOwned and details.EquipSlot and currentData.Equippeds then
		if currentData.Equippeds[details.EquipSlot] == details.Id then
			isEquipped = true
		end
	end

	local price = details.Price or 0

	-- Kart Görünümünü Güncelle
	if isOwned then
		card.LayoutOrder = price -- Sahip olunanları da fiyata göre dizebilirsiniz veya en başa alabilirsiniz
		if isEquipped then
			card.PurchaseButton.Title.Text = "Unequip"
			card.PurchaseButton.UIStroke.Color = Color3.fromRGB(255, 170, 0) -- Turuncu
		else
			card.PurchaseButton.Title.Text = "Equip"
			card.PurchaseButton.UIStroke.Color = Color3.fromRGB(255, 255, 255) -- Beyaz
		end
		card.BackgroundColor3 = isEquipped and Color3.fromRGB(45, 45, 45) or Color3.fromRGB(35, 35, 35)
	else
		card.LayoutOrder = 100000000 + price -- Sahip olunmayanlar sonda
		card.PurchaseButton.Title.Text = string.format("Buy for %sT$", FormatKit.FormatComma(details.Price))
		card.PurchaseButton.UIStroke.Color = Color3.fromRGB(0, 255, 100) -- Yeşil
		card.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	end

	return isOwned, isEquipped
end

function ShopController:RefreshAllVisuals()
	if not self.CachedData then return end
	for categoryName, cardsMap in pairs(self.CardCache) do
		for card, details in pairs(cardsMap) do
			self:UpdateCardState(card, details)
		end
	end
end

function ShopController:CreatePage(CategoryName, Enabled, Children)
	local CategoryButton = UIShopAssets.Category:Clone()
	local Page = UIShopAssets.Page:Clone()

	CategoryButton.Title.Text = CategoryName
	CategoryButton.Name = CategoryName
	Page.Name = CategoryName
	Page.Visible = Enabled
	CategoryButton.UIStroke.Color = Enabled and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)

	local layout = Page:FindFirstChildOfClass("UIGridLayout") or Page:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end

	self.Buttons[CategoryName] = CategoryButton
	self.Pages[CategoryName] = Page
	self.CardCache[CategoryName] = {}

	-- Kategori Değiştirme
	CategoryButton.Activated:Connect(function()
		for name, btn in pairs(self.Buttons) do
			btn.UIStroke.Color = (name == CategoryName) and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
		end
		for name, pg in pairs(self.Pages) do
			pg.Visible = (name == CategoryName)
		end
	end)

	-- Eşyaları Listele
	for itemName, Details in pairs(Children or {}) do
		local NewCard = UIShopAssets.Card:Clone()
		NewCard.Parent = Page
		NewCard.Name = Details.Id
		NewCard.Title.Text = Details.Name
		NewCard.PurchaseButton.ZIndex = 10 
		NewCard.PurchaseButton.Active = true

		local Viewport = NewCard:WaitForChild("Render")
		local ModelTemplate = Details.Model or Details.Character
		if ModelTemplate then
			local NewModel = ModelTemplate:Clone()
			NewModel.Parent = Viewport.WorldModel
			SetupViewportCamera(Viewport, NewModel)
		end

		self.CardCache[CategoryName][NewCard] = Details
		self:UpdateCardState(NewCard, Details)

		-- Satın Alma / Kuşanma Butonu
		NewCard.PurchaseButton.Activated:Connect(function()
			local catData = self.CachedData and self.CachedData[Details.DataCategory]
			local isOwned = (catData and catData[Details.Id])

			if isOwned then
				-- Eşya zaten varsa: Kuşan/Çıkar
				local state, response = Net:Invoke("ShopService/EquipItem", Details.Id)
				NotificationController.Signals.SendNotification:Fire(response, state and 2 or 3)

				if state then
					self.CachedData = Net:Invoke("DataService/GetData")
					self:RefreshAllVisuals()
				end
			else
				-- Eşya yoksa: Satın Al
				local state, response = Net:Invoke("ShopService/Purchase", Details.Id)

				if not state then
					if response == "Not enough Token!" then
						NotificationController.Signals.SendNotification:Fire("Insufficient Tokens! Opening package options...", 3)
						self:PromptBestProduct(Details.Price)
					else
						NotificationController.Signals.SendNotification:Fire(response, 3)
					end
				else
					NotificationController.Signals.SendNotification:Fire(response, 2)
					self.CachedData = Net:Invoke("DataService/GetData")
					self:RefreshAllVisuals() 
				end
			end
		end)
	end

	return CategoryButton, Page
end

function ShopController:OnStart()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local IngameHUD = PlayerGui:WaitForChild("IngameHUD")
	local ShopContainer = IngameHUD:WaitForChild("ShopContainer")
	local SidebarContainer = IngameHUD:WaitForChild("SidebarContainer")

	ShopContainer.Interactable = true
	self.CachedData = Net:Invoke("DataService/GetData")

	-- Veri değiştiğinde (örneğin satın alım sonrası) güncelle
	local DataEvents = Net:RemoteEvent("DataUpdate")
	if DataEvents then
		DataEvents.OnClientEvent:Connect(function()
			self.CachedData = Net:Invoke("DataService/GetData")
			self:RefreshAllVisuals()
		end)
	end

	-- ShopAssets içindeki modülleri bulma yardımcısı
	local function FindItemModuleInAssets(assetName)
		for _, child in ipairs(ShopAssets:GetDescendants()) do
			if child.Name == assetName and child:IsA("ModuleScript") then
				return child
			end
		end
		return nil
	end

	local firstCategory = true
	
	-- Kategorileri ve Eşyaları Yükle
	for _, CategoryFolder in ipairs(ShopAssets:GetChildren()) do
		local Cards = {}

		-- Klasördeki tanımlı eşyalar
		for _, Item in ipairs(CategoryFolder:GetChildren()) do
			if Item:IsA("ModuleScript") then
				local success, itemData = pcall(require, Item)
				if success then
					itemData.Id = Item.Name
					itemData.DataCategory = itemData.DataCategory or CategoryFolder.Name
					itemData.Model = itemData.Model or itemData.Character 
					itemData.Price = itemData.Price or 0
					Cards[Item.Name] = itemData
				end
			end
		end

		-- Oyuncunun sahip olduğu ama listede görünmeyen özel eşyalar varsa ekle
		if self.CachedData and self.CachedData[CategoryFolder.Name] then
			for ownedItemId, _ in pairs(self.CachedData[CategoryFolder.Name]) do
				if not Cards[ownedItemId] then
					local foundModule = FindItemModuleInAssets(ownedItemId)
					if foundModule then
						local success, itemData = pcall(require, foundModule)
						if success then
							itemData.Id = foundModule.Name
							itemData.DataCategory = CategoryFolder.Name 
							itemData.Model = itemData.Model or itemData.Character
							itemData.Price = itemData.Price or 0
							Cards[ownedItemId] = itemData
						end
					end
				end
			end
		end

		-- Sayfayı oluştur
		local btn, pg = self:CreatePage(CategoryFolder.Name, firstCategory, Cards)
		btn.Parent = ShopContainer.Categories
		pg.Parent = ShopContainer.Pages
		firstCategory = false
	end

	-- Menü Açma/Kapama Butonu
	if SidebarContainer:FindFirstChild("Shop") then
		SidebarContainer.Shop.ShopButton.Activated:Connect(function()
			ShopContainer.Visible = not ShopContainer.Visible
			if ShopContainer.Visible then
				self.CachedData = Net:Invoke("DataService/GetData")
				self:RefreshAllVisuals() 
			end
		end)
	end
end

return ShopController
