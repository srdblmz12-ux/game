-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")
local Interface = Common:WaitForChild("Interface")
local MapAssets = Interface:WaitForChild("MapAssets") -- MapCard burada olmalı

local FormatKit = require(Packages:WaitForChild("FormatKit"))
local TimerKit = require(Packages:WaitForChild("TimerKit"))
local Net = require(Packages:WaitForChild("Net"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local VotingController = {
	Name = "VotingController",
	CurrentMaps = {},
	CurrentVotes = {},
	SelectedMap = nil,
	HUD = nil,
	Container = nil,
}

-- UI Animasyonları
local function PlayHoverAnimation(card, isHovering)
	local targetScale = isHovering and 1.05 or 1.0
	TweenService:Create(card.Scale, TweenInfo.new(0.2), {Scale = targetScale}):Play()
end

local function PlaySelectAnimation(card, isSelected)
	local border = card:FindFirstChild("UIStroke")
	if border then
		local targetColor = isSelected and Color3.fromRGB(0, 255, 100) or Color3.fromRGB(255, 255, 255)
		local targetThickness = isSelected and 4 or 2
		TweenService:Create(border, TweenInfo.new(0.3), {Color = targetColor, Thickness = targetThickness}):Play()
	end
end

-- Harita Kartı Oluşturma
function VotingController:CreateMapCard(mapData)
	local cardPrefab = MapAssets:FindFirstChild("MapCard")
	if not cardPrefab then 
		warn("VotingController: MapCard prefab not found in Common/Interface/MapAssets")
		return 
	end

	local card = cardPrefab:Clone()
	card.Name = mapData.Name
	card.LayoutOrder = mapData.Index or 0

	-- Verileri Doldur
	local mapNameLabel = card:FindFirstChild("MapName")
	local voteCountLabel = card:FindFirstChild("VoteCount")
	local mapImage = card:FindFirstChild("Image")
	local button = card:FindFirstChild("Button") -- Tıklanabilir alan

	if mapNameLabel then mapNameLabel.Text = mapData.Name end
	if voteCountLabel then voteCountLabel.Text = "0 Votes" end

	if mapImage and mapData.ImageId then
		mapImage.Image = "rbxassetid://" .. mapData.ImageId
	end

	-- Scale objesi ekle (Animasyon için)
	if not card:FindFirstChild("Scale") then
		local scale = Instance.new("UIScale")
		scale.Name = "Scale"
		scale.Parent = card
	end

	-- Tıklama Olayı
	if button then
		button.Activated:Connect(function()
			self:CastVote(mapData.Name)
		end)

		button.MouseEnter:Connect(function() PlayHoverAnimation(card, true) end)
		button.MouseLeave:Connect(function() PlayHoverAnimation(card, false) end)
	end

	card.Parent = self.Container
	self.CurrentMaps[mapData.Name] = card
end

-- Oy Verme İşlemi
function VotingController:CastVote(mapName)
	if self.SelectedMap == mapName then return end -- Zaten buna oy verdik

	self.SelectedMap = mapName

	-- Sunucuya bildir
	Net:RemoteEvent("SubmitVote"):FireServer(mapName)

	-- Görsel Geri Bildirim
	for name, card in pairs(self.CurrentMaps) do
		PlaySelectAnimation(card, name == mapName)
	end
end

-- Oyları Güncelleme
function VotingController:UpdateVotes(votesData)
	self.CurrentVotes = votesData

	for mapName, count in pairs(votesData) do
		local card = self.CurrentMaps[mapName]
		if card then
			local label = card:FindFirstChild("VoteCount")
			if label then
				label.Text = count .. " Votes"
			end
		end
	end
end

-- Arayüzü Göster/Gizle
function VotingController:SetVisible(state)
	if self.HUD then
		self.HUD.Enabled = state
	end
end

function VotingController:OnStart()
	-- HUD Referansı
	self.HUD = PlayerGui:WaitForChild("MapVotingHUD", 10)
	if not self.HUD then
		warn("VotingController: MapVotingHUD not found in PlayerGui!")
		return
	end

	-- Kartların Konulacağı Alan (Container)
	-- Genelde HUD -> Container veya HUD -> Background -> MapsContainer şeklindedir.
	-- Eğer bulamazsanız burayı UI hiyerarşinize göre düzeltin.
	self.Container = self.HUD:FindFirstChild("Container") or self.HUD:FindFirstChild("Background") and self.HUD.Background:FindFirstChild("Container")

	if not self.Container then
		warn("VotingController: Container not found in MapVotingHUD")
	end

	local TimerLabel = self.HUD:FindFirstChild("Timer")

	-- Zamanlayıcı
	local VoteTimer = TimerKit.NewTimer(1)
	VoteTimer.OnTick:Connect(function(_, remaining)
		if TimerLabel then
			TimerLabel.Text = FormatKit.FormatTime(remaining, "m:ss")
		end
	end)

	-- NETWORK LISTENERS --

	-- 1. Oylama Başladı (Haritalar Geldi)
	Net:Connect("VoteOptions", function(mapsList, duration)
		if not self.Container then return end

		-- Eski kartları temizle
		for _, child in ipairs(self.Container:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		self.CurrentMaps = {}
		self.SelectedMap = nil

		-- Yeni kartları oluştur
		for i, mapData in ipairs(mapsList) do
			mapData.Index = i -- Sıralama için
			self:CreateMapCard(mapData)
		end

		-- Zamanlayıcıyı başlat
		VoteTimer:Stop()
		VoteTimer:AdjustDuration(duration or 15)
		VoteTimer:Start()

		-- UI Aç
		self:SetVisible(true)
	end)

	-- 2. Oylar Güncellendi
	Net:Connect("UpdateVotes", function(newVotes)
		self:UpdateVotes(newVotes)
	end)

	-- 3. Oylama Bitti / Oyun Başladı
	Net:Connect("GameStarted", function()
		VoteTimer:Stop()
		self:SetVisible(false)
	end)

	Net:Connect("WarmupStarted", function()
		VoteTimer:Stop()
		self:SetVisible(false)
	end)

	-- Başlangıçta gizle
	self:SetVisible(false)
end

return VotingController
