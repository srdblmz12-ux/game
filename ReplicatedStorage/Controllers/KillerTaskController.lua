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
	-- UI'in hazir oldugundan emin olalim (Timeout eklemek iyidir)
	local KillerHUD = PlayerGui:WaitForChild("KillerHUD", 10)
	if not KillerHUD then warn("KillerHUD bulunamadi!") return end

	local Container = KillerHUD:WaitForChild("Main")
	local TimerText = Container:FindFirstChild("Timer")

	-- Timer'i baslangiçta süresiz olusturuyoruz, sonradan set edecegiz
	local SpawnTimer = TimerKit.NewTimer(0) 

	SpawnTimer.OnTick:Connect(function(_, Remaining)
		if TimerText then
			TimerText.Text = `Spawning in {math.floor(Remaining)}`
		end
	end)

	-- Timer bittiginde veya durdugunda
	SpawnTimer.Completed:Connect(function()
		KillerHUD.Enabled = false
	end)

	-- 1. EVENT: Warmup Basladiginda (Server veriyi buraya atiyor)
	Net:Connect("WarmupStarted", function(Gamemode, RunningPlayers, Duration)
		local myId = tostring(LocalPlayer.UserId)
		local myRole = RunningPlayers[myId]

		-- Sadece KILLER ise bu ekrani göster
		if myRole == "Killer" then
			KillerHUD.Enabled = true

			-- Server'dan gelen dogru süreyi ayarla ve baslat
			SpawnTimer:AdjustDuration(Duration) 
			SpawnTimer:Start()
		else
			KillerHUD.Enabled = false
			SpawnTimer:Stop()
		end
	end)

	-- 2. EVENT: Oyun Durumu Degistiginde (Garanti Kapatma)
	Net:Connect("StateUpdate", function(State, Data)
		if State == "GameStatus" then
			-- Eger Warmup bittiyse (GameRunning, Intermission vs.) HUD'i kapat
			if Data ~= "Warmup" then
				KillerHUD.Enabled = false
				SpawnTimer:Stop()
			end
		end
	end)
end

return KillerTaskController