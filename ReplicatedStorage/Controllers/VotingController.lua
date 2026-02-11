-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = Common:WaitForChild("Interface"):WaitForChild("MapAssets") -- Kart Prefab'i burada

local MapModulesFolder = Shared:WaitForChild("MapAssets") -- Harita modülleri (Resim vs. için)

-- Dependencies
local Net = require(Packages:WaitForChild("Net"))
local Trove = require(Packages:WaitForChild("Trove"))

-- Controller
local VotingController = {
	Name = "VotingController",

	-- State
	CurrentMaps = {}, -- { [MapName] = CardInstance }
	SelectedMap = nil,
	_trove = nil, -- Temizlik için

	-- UI Refs
	HUD = nil,
	Container = nil,

	-- Network Events (Server'daki VotingService ile konuşur)
	Events = {
		SetOptions = Net:RemoteEvent("SetOptions"),
		UpdateVotes = Net:RemoteEvent("UpdateVotes"),
		SubmitVote = Net:RemoteEvent("SubmitVote"),
		GameStarted = Net:RemoteEvent("GameStarted")
	}
}

-- =============================================================================
--  CORE LOGIC
-- =============================================================================

function VotingController:Start()
	print("[VotingController] Başlatılıyor...")

	local Player = Players.LocalPlayer
	local PlayerGui = Player:WaitForChild("PlayerGui")

	-- HUD'u bul (İsmi MapVotingHUD olmalı)
	self.HUD = PlayerGui:WaitForChild("MapVotingHUD", 10)
	if not self.HUD then
		warn("[VotingController] MapVotingHUD bulunamadı! Lütfen StarterGui'yi kontrol et.")
		return
	end

	-- Kartların konulacağı Container'ı bul
	-- Genelde: HUD -> Background -> Container
	self.Container = self.HUD:FindFirstChild("Container", true) -- Recursive arama yapar
	if not self.Container then
		warn("[VotingController] 'Container' isimli Frame bulunamadı!")
		return
	end

	-- Başlangıçta gizle
	self:SetVisible(false)

	-- Eventleri Dinle
	self:ConnectNetwork()
end

function VotingController:ConnectNetwork()
	-- 1. OYLAMA BAŞLADI (Seçenekler Geldi)
	self.Events.SetOptions.OnClientEvent:Connect(function(mapNamesArray)
		self:SetupVotingSession(mapNamesArray)
	end)

	-- 2. OYLAR GÜNCELLENDİ
	self.Events.UpdateVotes.OnClientEvent:Connect(function(votesTable)
		self:UpdateVoteCounts(votesTable)
	end)

	-- 3. OYUN BAŞLADI (Oylama bitti)
	self.Events.GameStarted.OnClientEvent:Connect(function()
		self:SetVisible(false)
		self:ClearCards()
	end)
end

-- =============================================================================
--  UI MANAGEMENT
-- =============================================================================

function VotingController:SetupVotingSession(mapNames)
	self:ClearCards()
	self._trove = Trove.new()
	self.SelectedMap = nil
	self:SetVisible(true)

	print("[VotingController] Seçenekler:", table.concat(mapNames, ", "))

	for index, mapName in ipairs(mapNames) do
		-- Harita Modülünden Veriyi Çek (Resim vs. için)
		local mapInfo = self:GetMapInfo(mapName)

		-- Kartı Oluştur
		self:CreateCard(mapName, mapInfo, index)
	end
end

function VotingController:CreateCard(mapName, mapInfo, layoutOrder)
	local cardPrefab = Assets:FindFirstChild("MapCard")
	if not cardPrefab then return end

	local card = cardPrefab:Clone()
	card.Name = mapName
	card.LayoutOrder = layoutOrder
	card.Parent = self.Container

	-- Trove ile takip et (Otomatik silmek için)
	self._trove:Add(card)
	self.CurrentMaps[mapName] = card

	-- UI Verilerini Doldur
	local nameLabel = card:FindFirstChild("MapName", true) -- Recursive bul
	local imageLabel = card:FindFirstChild("Image", true)
	local voteLabel = card:FindFirstChild("VoteCount", true)
	local button = card:FindFirstChild("Button", true) or card -- Button yoksa kartın kendisi buton olsun

	if nameLabel then nameLabel.Text = mapName end
	if voteLabel then voteLabel.Text = "0" end

	-- Resmi Ayarla
	if imageLabel and mapInfo and mapInfo.Image then
		imageLabel.Image = mapInfo.Image
	elseif imageLabel then
		imageLabel.Image = "" -- Resim yoksa boşalt
	end

	-- Tıklama İşlemi
	if button and button:IsA("GuiButton") then
		self._trove:Connect(button.Activated, function()
			self:CastVote(mapName)
		end)

		-- Hover Efektleri
		self._trove:Connect(button.MouseEnter, function()
			self:PlayHoverAnim(card, true)
		end)
		self._trove:Connect(button.MouseLeave, function()
			self:PlayHoverAnim(card, false)
		end)
	end
end

function VotingController:UpdateVoteCounts(votesTable)
	-- Önce sayaçları sıfırla
	local counts = {}
	for mapName, _ in pairs(self.CurrentMaps) do
		counts[mapName] = 0
	end

	-- Oyları say
	for _, votedMap in pairs(votesTable) do
		if counts[votedMap] then
			counts[votedMap] += 1
		end
	end

	-- Textleri güncelle
	for mapName, count in pairs(counts) do
		local card = self.CurrentMaps[mapName]
		if card then
			local label = card:FindFirstChild("VoteCount", true)
			if label then
				label.Text = tostring(count)
			end
		end
	end
end

function VotingController:CastVote(mapName)
	if self.SelectedMap == mapName then return end

	self.SelectedMap = mapName

	-- Server'a gönder
	self.Events.SubmitVote:FireServer(mapName)

	-- Görsel seçim efekti
	for name, card in pairs(self.CurrentMaps) do
		self:PlaySelectAnim(card, name == mapName)
	end
end

-- =============================================================================
--  HELPERS & ANIMATIONS
-- =============================================================================

function VotingController:GetMapInfo(mapName)
	-- Shared/MapAssets içindeki ModuleScript'i require et
	local module = MapModulesFolder:FindFirstChild(mapName)
	if module and module:IsA("ModuleScript") then
		local success, data = pcall(require, module)
		if success then
			return data
		end
	end
	return nil
end

function VotingController:SetVisible(isVisible)
	if self.HUD then
		self.HUD.Enabled = isVisible
	end
end

function VotingController:ClearCards()
	if self._trove then
		self._trove:Destroy()
		self._trove = nil
	end
	self.CurrentMaps = {}

	-- Container içini manuel de temizle (Trove kaçırırsa diye)
	if self.Container then
		for _, child in ipairs(self.Container:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
	end
end

function VotingController:PlayHoverAnim(card, isHovering)
	local scale = card:FindFirstChild("UIScale")
	if not scale then 
		scale = Instance.new("UIScale")
		scale.Name = "UIScale"
		scale.Parent = card
	end

	local target = isHovering and 1.05 or 1.0
	TweenService:Create(scale, TweenInfo.new(0.2), {Scale = target}):Play()
end

function VotingController:PlaySelectAnim(card, isSelected)
	local stroke = card:FindFirstChild("UIStroke")
	if not stroke then return end -- UIStroke yoksa yapma

	local targetColor = isSelected and Color3.fromRGB(0, 255, 100) or Color3.fromRGB(255, 255, 255)
	local targetThickness = isSelected and 4 or 1

	TweenService:Create(stroke, TweenInfo.new(0.3), {
		Color = targetColor,
		Thickness = targetThickness
	}):Play()
end

return VotingController
