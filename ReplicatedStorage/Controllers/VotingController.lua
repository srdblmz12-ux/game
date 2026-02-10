-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")
local Interface = Common:WaitForChild("Interface")

local MapVotingAssets = Interface:WaitForChild("MapVotingAssets")

local FormatKit = require(Packages:WaitForChild("FormatKit"))
local TimerKit = require(Packages:WaitForChild("TimerKit"))
local Trove = require(Packages:WaitForChild("Trove"))
local Net = require(Packages:WaitForChild("Net"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

-- Module
local VotingController = {
	Name = script.Name,
	UITrove = Trove.new(),
	Items = {},
}

function VotingController:OnStart()
	local VotingHUD = PlayerGui:WaitForChild("MapVotingHUD")
	local MapPopup = VotingHUD:WaitForChild("MapPopup")
	local CardsPage = MapPopup:WaitForChild("Cards")

	--// UI Temizleme ve Sıfırlama Fonksiyonu
	local function CleanUI()
		-- 1. UI'ı gizle
		CardsPage.Visible = false 

		-- 2. Timer yazısını sıfırla (Görsel temizlik)
		CardsPage.Timer.Description.Text = "Waiting for server..."

		-- 3. Tabloyu sıfırla
		self.Items = {} 

		-- 4. Trove'u güvenli temizle
		local success, err = pcall(function()
			self.UITrove:Clean()
		end)

		if not success then
			warn("VotingController: Trove temizlenirken hata oluştu:", err)
		end
	end

	-- Oyun bittiğinde veya Warmup başladığında ekranı temizle
	Net:Connect("GameEnded", CleanUI)
	Net:Connect("WarmupStarted", CleanUI)

	Net:Connect("VoteOptions", function(Options, ServerTime)
		-- Her durumda önce temizlik yap
		CleanUI() 

		-- [KRİTİK GÜNCELLEME] 
		-- GameService'den gelen "Force Clear" (Boş tablo veya 0 süre) sinyalini yakala.
		-- Eğer süre yoksa veya seçenek yoksa, işlemi burada bitir. Ekran açılmaz.
		if not Options or #Options == 0 or (ServerTime and ServerTime <= 0) then
			return 
		end

		-- Eğer geçerli bir oylama verisi varsa devam et:
		CardsPage.Visible = true

		-- Timer Oluştur
		local NewTimer = TimerKit.NewTimer(ServerTime)
		NewTimer:Start()

		-- Timer'ı Trove'a güvenli ekle
		self.UITrove:Add(function()
			pcall(function()
				NewTimer:Destroy()
			end)
		end)

		self.UITrove:Connect(NewTimer.OnTick, function(_, Remaining)
			local timeLeft = math.max(0, math.floor(Remaining))
			CardsPage.Timer.Description.Text = `Vote a map! {timeLeft}s later voting ends`
		end)

		-- Kartları Oluştur
		for _, Details in ipairs(Options) do
			local NewCard = MapVotingAssets:WaitForChild("VoteCard"):Clone()
			NewCard.Parent = CardsPage.Container
			NewCard.Title.Text = Details.Name
			NewCard.Icon.Image = Details.Image
			NewCard.Description.Text = Details.Description

			-- Başlangıç oyu 0
			NewCard.VoteCount.Text = "0 Vote"

			self.Items[Details.Id] = NewCard
			self.UITrove:Add(NewCard)

			self.UITrove:Connect(NewCard.Activated, function()
				Net:RemoteEvent("CastVote"):FireServer(Details.Id)

				-- Basit Client-Side Görsel Geri Bildirim
				for _, OtherCard in pairs(self.Items) do
					if OtherCard:FindFirstChild("UIStroke") then
						OtherCard.UIStroke.Color = Color3.fromRGB(255, 80, 80) -- Kırmızı (Seçilmeyen)
						OtherCard.UIStroke.Transparency = 0.8
					end
				end

				if NewCard:FindFirstChild("UIStroke") then
					NewCard.UIStroke.Color = Color3.fromRGB(80, 255, 80) -- Yeşil (Seçilen)
					NewCard.UIStroke.Transparency = 0
				end
			end)
		end
	end)

	Net:Connect("VoteUpdate", function(VoteCounts)
		if not CardsPage.Visible then return end -- Ekran kapalıysa işlem yapma

		for MapId, Count in pairs(VoteCounts) do
			local Item = self.Items[MapId]
			if (Item) then
				Item.VoteCount.Text = `{FormatKit.FormatComma(Count)} Vote`
			end
		end
	end)
end

return VotingController