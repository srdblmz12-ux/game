-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")

local FormatKit = require(Packages:WaitForChild("FormatKit"))
local TimerKit = require(Packages:WaitForChild("TimerKit"))
local Net = require(Packages:WaitForChild("Net"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

-- Module
local GameController = {
	Name = script.Name,
	_lastStateChange = 0,
	_isParticipating = false,
	_currentStatus = "Intermission",
	_isSpectating = false,
	_currentMapName = "Unknown",
	_currentGamemode = "Classic"
}

local GameStateName = {
	["Intermission"] = "Waiting for players...",
	["OnVoting"] = "Voting for map...",
	["Loading"] = "Loading map...",
	["Warmup"] = "Selecting skills...",
	["GameRunning"] = "Killer spawned, run!",
	["MurdererWin"] = "No survivor is left...",
	["SurvivorsWin"] = "Survivors won!"
}

-- HUD Görünürlüğünü Kontrol Eden Fonksiyon
function GameController:UpdateInterfaceVisibility()
	local LevelHUD = PlayerGui:FindFirstChild("LevelHUD")
	local IngameHUD = PlayerGui:FindFirstChild("IngameHUD") 
	local PopupHUD = PlayerGui:FindFirstChild("PopupHUD")

	-- GameStateHUD elementlerini de duruma göre açıp kapatacağız
	local GameStateHUD = PlayerGui:FindFirstChild("GameStateHUD")

	local isGameActive = (self._currentStatus == "Warmup" or self._currentStatus == "GameRunning")
	local isActiveParticipant = (isGameActive and self._isParticipating)
	local isVoting = (self._currentStatus == "OnVoting")
	local isSpectating = self._isSpectating

	-- Menülerin gizlenmesi gereken durumlar
	local shouldHideMenus = isVoting or isActiveParticipant or isSpectating

	if LevelHUD then LevelHUD.Enabled = not shouldHideMenus end
	if IngameHUD then IngameHUD.Enabled = not shouldHideMenus end
	if PopupHUD then PopupHUD.Enabled = not shouldHideMenus end

	-- GameStateHUD kontrolü
	if GameStateHUD then
		local Timer = GameStateHUD:FindFirstChild("Timer")
		local SurvivorCount = GameStateHUD:FindFirstChild("SurvivorCount")
		local MapGamemode = GameStateHUD:FindFirstChild("MapGamemode")
		local GameState = GameStateHUD:FindFirstChild("GameState")

		-- Genel HUD açık olsun
		GameStateHUD.Enabled = true

		if Timer then 
			-- Sadece oyunla ilgili zamanlarda göster
			Timer.Visible = (self._currentStatus ~= "Intermission" and self._currentStatus ~= "Loading")
		end

		if SurvivorCount then
			-- Sadece oyun aktifken göster
			SurvivorCount.Visible = (self._currentStatus == "GameRunning" or self._currentStatus == "Warmup")
		end

		if MapGamemode then
			-- Intermission hariç göster
			MapGamemode.Visible = (self._currentStatus ~= "Intermission")
		end

		if GameState then
			GameState.Visible = true
		end
	end
end

function GameController:SetSpectating(state: boolean)
	self._isSpectating = state
	self:UpdateInterfaceVisibility()
end

function GameController:UpdateMapModeText(HUD)
	local label = HUD:FindFirstChild("MapGamemode")
	if label then
		label.Text = string.format("%s (%s)", self._currentMapName, self._currentGamemode)
	end
end

function GameController:OnStart()
	-- UI Elementlerini Tanımla (Direct Children olarak)
	local GameStateHUD = PlayerGui:WaitForChild("GameStateHUD")
	local TimerLabel = GameStateHUD:WaitForChild("Timer")
	local GameStateLabel = GameStateHUD:WaitForChild("GameState")
	local SurvivorCountLabel = GameStateHUD:WaitForChild("SurvivorCount")

	-- Zamanlayıcı Ayarları
	local Timer = TimerKit.NewTimer(1)
	Timer.OnTick:Connect(function(_, Remaining : number)
		local displayTime = math.max(0, Remaining)
		if FormatKit then
			TimerLabel.Text = FormatKit.FormatTime(displayTime, "m:ss")
		else
			TimerLabel.Text = tostring(math.floor(displayTime))
		end
	end)

	-- Karakter öldüğünde arayüzü güncelle
	local function MonitorCharacter(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Died:Connect(function()
				self._isParticipating = false
				self:UpdateInterfaceVisibility()
			end)
		end
	end

	if LocalPlayer.Character then MonitorCharacter(LocalPlayer.Character) end
	LocalPlayer.CharacterAdded:Connect(MonitorCharacter)

	-- STATE UPDATE (Genel Durum)
	Net:Connect("StateUpdate", function(State : string, Data)
		if (State == "GameStatus") then
			self._currentStatus = Data
			self:UpdateInterfaceVisibility()

			local NewText = GameStateName[Data] or Data
			GameStateLabel.Text = NewText

			-- Durum değiştiğinde animasyon veya görünürlük ayarı yapılabilir
			GameStateLabel.Visible = true

		elseif (State == "TimeLeft") then
			Timer:Stop()
			if (Data and Data > 0) then
				Timer:AdjustDuration(Data)
				Timer:Start()
			else
				TimerLabel.Text = "0:00"
			end

		elseif (State == "SurvivorCount") then
			SurvivorCountLabel.Text = `Survivors: {Data}`

		elseif (State == "Gamemode") then
			self._currentGamemode = Data
			self:UpdateMapModeText(GameStateHUD)
		end
	end)

	-- Harita Yüklendiğinde İsmi Güncelle
	Net:Connect("MapLoaded", function(mapName)
		self._currentMapName = mapName or "Unknown"
		self:UpdateMapModeText(GameStateHUD)
	end)

	-- WARMUP STARTED
	Net:Connect("WarmupStarted", function(Mode, Roles, Time)
		self._currentStatus = "Warmup"
		self._currentGamemode = Mode -- Mod bilgisini güncelle
		self:UpdateMapModeText(GameStateHUD)

		Timer:Stop()
		Timer:AdjustDuration(Time)
		Timer:Start()

		local myUserId = tostring(LocalPlayer.UserId)
		if Roles[myUserId] then
			self._isParticipating = true
		else
			self._isParticipating = false
		end

		self:UpdateInterfaceVisibility()
	end)

	-- GAME STARTED
	Net:Connect("GameStarted", function(Time)
		self._currentStatus = "GameRunning"

		Timer:Stop()
		Timer:AdjustDuration(Time)
		Timer:Start()

		self:UpdateInterfaceVisibility()
	end)

	-- VOTE OPTIONS
	Net:Connect("VoteOptions", function(_, Time)
		self._currentStatus = "OnVoting"
		self:UpdateInterfaceVisibility()

		Timer:Stop()
		Timer:AdjustDuration(Time)
		Timer:Start()
	end)

	-- GAME ENDED
	Net:Connect("GameEnded", function()
		self._isParticipating = false
		self._currentStatus = "Intermission"
		self._isSpectating = false

		self:UpdateInterfaceVisibility()
	end)

	-- Başlangıçta Görünürlüğü Ayarla
	self:UpdateInterfaceVisibility()
end

return GameController
