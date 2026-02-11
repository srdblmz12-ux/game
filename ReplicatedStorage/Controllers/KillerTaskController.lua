-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")

local TimerKit = require(Packages:WaitForChild("TimerKit"))
local Net = require(Packages:WaitForChild("Net"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

-- Module
local KillerTaskController = {
	Name = script.Name
}

function KillerTaskController:OnStart()
	-- UI'ın hazır olduğundan emin olalım (Timeout eklemek iyidir)
	local KillerHUD = PlayerGui:WaitForChild("KillerHUD", 10)
	if not KillerHUD then warn("KillerHUD bulunamadı!") return end

	local Container = KillerHUD:WaitForChild("Main")
	local TimerText = Container:FindFirstChild("Timer")

	-- Timer'ı başlangıçta süresiz oluşturuyoruz, sonradan set edeceğiz
	local SpawnTimer = TimerKit.NewTimer(0) 

	SpawnTimer.OnTick:Connect(function(_, Remaining)
		if TimerText then
			TimerText.Text = `Spawning in {math.floor(Remaining)}`
		end
	end)

	-- Timer bittiğinde veya durduğunda
	SpawnTimer.Completed:Connect(function()
		KillerHUD.Enabled = false
	end)

	-- 1. EVENT: Warmup Başladığında (Server veriyi buraya atıyor)
	Net:Connect("WarmupStarted", function(Gamemode, RunningPlayers, Duration)
		local myId = tostring(LocalPlayer.UserId)
		local myRole = RunningPlayers[myId]

		-- Sadece KILLER ise bu ekranı göster
		if myRole == "Killer" then
			KillerHUD.Enabled = true

			-- Server'dan gelen doğru süreyi ayarla ve başlat
			SpawnTimer:AdjustDuration(Duration) 
			SpawnTimer:Start()
		else
			KillerHUD.Enabled = false
			SpawnTimer:Stop()
		end
	end)

	-- 2. EVENT: Oyun Durumu Değiştiğinde (Garanti Kapatma)
	Net:Connect("StateUpdate", function(State, Data)
		if State == "GameStatus" then
			-- Eğer Warmup bittiyse (GameRunning, Intermission vs.) HUD'ı kapat
			if Data ~= "Warmup" then
				KillerHUD.Enabled = false
				SpawnTimer:Stop()
			end
		end
	end)
end

return KillerTaskController
