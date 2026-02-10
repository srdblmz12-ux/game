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
	_isSpectating = false
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
	-- NOT: LevelHUD ve IngameHUD senin "Lobby" ekranların varsayılıyor.
	-- Eğer oyun içi can barı vs. varsa onları buraya dahil etme!
	local LevelHUD = PlayerGui:FindFirstChild("LevelHUD")
	local IngameHUD = PlayerGui:FindFirstChild("IngameHUD") 
	local PopupHUD = PlayerGui:FindFirstChild("PopupHUD")

	-- Kural 1: Oyun aktifse (Warmup veya Running) ve katılımcıysa gizle.
	local isGameActive = (self._currentStatus == "Warmup" or self._currentStatus == "GameRunning")
	local isActiveParticipant = (isGameActive and self._isParticipating)

	-- Kural 2: Oylama sırasındaysa gizle.
	local isVoting = (self._currentStatus == "OnVoting")

	-- Kural 3: İzleyici modundaysa gizle.
	local isSpectating = self._isSpectating

	-- Oylama VEYA (Oyun Aktif VE Oynuyor) VEYA İzliyor -> Menüleri Gizle
	local shouldHideMenus = isVoting or isActiveParticipant or isSpectating

	if LevelHUD then 
		LevelHUD.Enabled = not shouldHideMenus 
	end

	if IngameHUD then 
		IngameHUD.Enabled = not shouldHideMenus 
	end
	
	if (PopupHUD) then
		PopupHUD.Enabled = not shouldHideMenus
	end
end

function GameController:SetSpectating(state: boolean)
	self._isSpectating = state
	self:UpdateInterfaceVisibility()
end

function GameController:OnStart()
	local GameStatusHUD = PlayerGui:WaitForChild("GameStatusHUD")
	local StatusContainer = GameStatusHUD:WaitForChild("StatusContainer")

	local Timer = TimerKit.NewTimer(1)
	Timer.OnTick:Connect(function(_, Remaining : number)
		local displayTime = math.max(0, Remaining)
		-- FormatKit yoksa hata vermesin diye pcall veya basit format
		if FormatKit then
			StatusContainer.Timer.Text = FormatKit.FormatTime(displayTime, "m:ss")
		else
			StatusContainer.Timer.Text = tostring(math.floor(displayTime))
		end
	end)

	-- Karakter öldüğünde arayüzü geri getirmek için dinleyici
	local function MonitorCharacter(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Died:Connect(function()
				-- Öldüğünde katılımcı statüsünden çık
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
			self._currentStatus = Data -- Durumu güncelle
			self:UpdateInterfaceVisibility() -- Arayüzü güncelle

			local OldText = StatusContainer.GameState.Text
			local NewText = GameStateName[Data] or Data

			StatusContainer.GameState.Text = NewText

			if (NewText ~= OldText) then
				self._lastStateChange = tick()
				local currentChange = self._lastStateChange

				StatusContainer.GameState.Visible = true

				task.delay(5, function() -- 10 saniye çok uzun, 5 kafi
					if (self._lastStateChange == currentChange) then
						StatusContainer.GameState.Visible = false
					end
				end)
			end

			-- Oylamada üst barı gizle (Oylama ekranı zaten kapatacak)
			StatusContainer.Visible = (Data ~= "OnVoting")

		elseif (State == "TimeLeft") then
			Timer:Stop()
			if (Data and Data > 0) then
				Timer:AdjustDuration(Data)
				Timer:Start()
			else
				StatusContainer.Timer.Text = "0:00"
			end

		elseif (State == "SurvivorCount") then
			StatusContainer.Remaining.Text = `{Data} Survivor Left`
		end
	end)

	-- WARMUP STARTED
	Net:Connect("WarmupStarted", function(Mode, Roles, Time)
		-- [DÜZELTME] Status update gecikirse diye manuel set ediyoruz
		self._currentStatus = "Warmup" 

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
		-- [DÜZELTME] Status update gecikirse diye manuel set ediyoruz
		self._currentStatus = "GameRunning"

		Timer:Stop()
		Timer:AdjustDuration(Time)
		Timer:Start()

		self:UpdateInterfaceVisibility()
	end)

	-- VOTE OPTIONS
	Net:Connect("VoteOptions", function(_, Time)
		self._currentStatus = "OnVoting" -- Güvenlik için
		self:UpdateInterfaceVisibility()

		Timer:Stop()
		Timer:AdjustDuration(Time)
		Timer:Start()
	end)

	-- GAME ENDED
	Net:Connect("GameEnded", function()
		self._isParticipating = false
		self._currentStatus = "Intermission"
		self._isSpectating = false -- Spectate'i de sıfırla

		self:UpdateInterfaceVisibility()
	end)
end

return GameController