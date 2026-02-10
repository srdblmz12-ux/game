-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")

-- Dependencies
local Net = require(Packages:WaitForChild("Net"))
local Promise = require(Packages:WaitForChild("Promise"))

-- Assets
local GameAmbients = SoundService:WaitForChild("GameAmbients")
local LobbyMusics = SoundService:WaitForChild("LobbyMusic")
local HeartbeatSound = SoundService:FindFirstChild("Heartbeat")

-- Constants
local CONFIG = {
	HEARTBEAT_DIST = 40,
	MAX_HEARTBEAT_VOL = 10,
	LOBBY_MAX_VOL = 0.5,
	AMBIENT_MAX_VOL = 1,
	FADE_TIME = 1.5
}

-- Module
local AmbientSoundController = {
	Name = script.Name,

	_currentTrack = nil,      -- Şu an çalan oyun müziği
	_lastAmbientTrack = nil,  -- En son çalan oyun müziği (tekrarı önlemek için)

	_currentLobbyTrack = nil, -- Şu an çalan lobi müziği
	_lastLobbyTrack = nil,    -- En son çalan lobi müziği (tekrarı önlemek için)

	_musicConnection = nil,   -- Müzik bittiğinde tetiklenen bağlantı (Ended event)
	_heartbeatConnection = nil,
	_targetKiller = nil,
	_isGameRunning = false
}

-- =============================================================================
--  YARDIMCI FONKSİYONLAR (SEÇİM MANTIĞI)
-- =============================================================================

-- Rastgele ama bir öncekiyle aynı olmayan bir şarkı seçer
function AmbientSoundController:_pickNextTrack(folder, lastTrack)
	local tracks = folder:GetChildren()
	local validTracks = {}

	-- Sadece Sound nesnelerini al
	for _, t in ipairs(tracks) do
		if t:IsA("Sound") then
			table.insert(validTracks, t)
		end
	end

	if #validTracks == 0 then return nil end
	if #validTracks == 1 then return validTracks[1] end -- Sadece 1 şarkı varsa mecburen onu seç

	local nextTrack
	repeat
		nextTrack = validTracks[math.random(1, #validTracks)]
	until nextTrack ~= lastTrack -- Bir öncekiyle aynı olmayana kadar tekrar seç

	return nextTrack
end

-- =============================================================================
--  LOBBY MÜZİK SİSTEMİ
-- =============================================================================

function AmbientSoundController:_playLobbyMusic()
	-- Eğer oyun içi müzik bağlantısı varsa kopar (çakışmayı önle)
	if self._musicConnection then 
		self._musicConnection:Disconnect() 
		self._musicConnection = nil
	end

	-- Önceki çalanı durdur
	self:_stopAmbient(true) -- True: Hızlı durdur

	-- Yeni şarkı seç (Öncekisiyle aynı olmayan)
	local track = self:_pickNextTrack(LobbyMusics, self._lastLobbyTrack)
	if not track then return end

	-- Yeni şarkıyı ayarla
	self._currentLobbyTrack = track
	self._lastLobbyTrack = track -- Kaydet ki bir dahaki sefere aynısı gelmesin

	track.Looped = false -- İsteğin üzerine loop kapatıldı
	track.Volume = 0
	track:Play()

	-- Fade In
	TweenService:Create(track, TweenInfo.new(CONFIG.FADE_TIME), {Volume = CONFIG.LOBBY_MAX_VOL}):Play()

	-- Şarkı bittiğinde ne olacağını dinle
	self._musicConnection = track.Ended:Connect(function()
		-- Eğer hala oyun başlamadıysa (lobi durumundaysak) sıradaki şarkıya geç
		if not self._isGameRunning then
			self:_playLobbyMusic()
		end
	end)
end

function AmbientSoundController:_stopLobbyMusic()
	-- Event bağlantısını kopar ki şarkı durunca yenisini başlatmaya çalışmasın
	if self._musicConnection then
		self._musicConnection:Disconnect()
		self._musicConnection = nil
	end

	if self._currentLobbyTrack then
		local track = self._currentLobbyTrack
		local tween = TweenService:Create(track, TweenInfo.new(CONFIG.FADE_TIME), {Volume = 0})
		tween:Play()
		tween.Completed:Connect(function()
			track:Stop()
		end)
		self._currentLobbyTrack = nil
	end
end

-- =============================================================================
--  OYUN İÇİ AMBIENT SİSTEMİ
-- =============================================================================

function AmbientSoundController:_playRandomAmbient()
	-- Eğer lobi müziği bağlantısı varsa kopar
	if self._musicConnection then 
		self._musicConnection:Disconnect() 
		self._musicConnection = nil
	end

	self:_stopLobbyMusic()

	-- Yeni şarkı seç (Öncekisiyle aynı olmayan)
	local track = self:_pickNextTrack(GameAmbients, self._lastAmbientTrack)
	if not track then return end

	-- Yeni şarkıyı ayarla
	self._currentTrack = track
	self._lastAmbientTrack = track

	track.Looped = false -- İsteğin üzerine loop kapatıldı
	track.Volume = 0
	track:Play()

	-- Fade In
	TweenService:Create(track, TweenInfo.new(CONFIG.FADE_TIME), {Volume = CONFIG.AMBIENT_MAX_VOL}):Play()

	-- Şarkı bittiğinde ne olacağını dinle
	self._musicConnection = track.Ended:Connect(function()
		-- Eğer hala oyun devam ediyorsa sıradaki şarkıya geç
		if self._isGameRunning then
			self:_playRandomAmbient()
		end
	end)
end

function AmbientSoundController:_stopAmbient(instant)
	-- Event bağlantısını kopar
	if self._musicConnection then
		self._musicConnection:Disconnect()
		self._musicConnection = nil
	end

	if self._currentTrack then
		local track = self._currentTrack

		if instant then
			track:Stop()
		else
			local tween = TweenService:Create(track, TweenInfo.new(CONFIG.FADE_TIME), {Volume = 0})
			tween:Play()
			tween.Completed:Connect(function()
				track:Stop()
			end)
		end
		self._currentTrack = nil
	end
end

-- =============================================================================
--  HEARTBEAT LOGIC (DEĞİŞİKLİK YOK)
-- =============================================================================

function AmbientSoundController:_updateHeartbeat()
	local localPlayer = Players.LocalPlayer
	local killer = self._targetKiller

	if not self._isGameRunning or not killer or not localPlayer then 
		HeartbeatSound.Volume = 0
		return 
	end

	if localPlayer == killer then
		HeartbeatSound.Volume = 0
		return
	end

	local localChar = localPlayer.Character
	local killerChar = killer.Character

	if not localChar or not killerChar then 
		HeartbeatSound.Volume = 0
		return 
	end

	local localRoot = localChar:FindFirstChild("HumanoidRootPart")
	local killerRoot = killerChar:FindFirstChild("HumanoidRootPart")
	local localHum = localChar:FindFirstChild("Humanoid")

	if not localRoot or not killerRoot or (localHum and localHum.Health <= 0) then
		HeartbeatSound.Volume = 0
		return
	end

	local distance = (localRoot.Position - killerRoot.Position).Magnitude

	if distance <= CONFIG.HEARTBEAT_DIST then
		local alpha = 1 - (distance / CONFIG.HEARTBEAT_DIST)
		local targetVolume = math.clamp(alpha * CONFIG.MAX_HEARTBEAT_VOL, 0, CONFIG.MAX_HEARTBEAT_VOL)

		HeartbeatSound.Volume = targetVolume

		if not HeartbeatSound.IsPlaying then
			HeartbeatSound:Play()
		end
	else
		HeartbeatSound.Volume = 0
	end
end

-- =============================================================================
--  INITIALIZATION & LISTENERS
-- =============================================================================

function AmbientSoundController:OnStart()
	-- GameService'den gelen Eventleri Dinle
	local GameStartedEvent = Net:RemoteEvent("GameStarted")
	local GameEndedEvent = Net:RemoteEvent("GameEnded")

	-- 1. OYUN BAŞLADIĞINDA
	GameStartedEvent.OnClientEvent:Connect(function(duration)
		self._isGameRunning = true

		-- Lobi müziğini durdur, oyun müziğini başlat
		self:_stopLobbyMusic()
		self:_playRandomAmbient()

		local foundKiller = false
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character and player:GetAttribute("Role") == "Killer" then
				self._targetKiller = player
				foundKiller = true
				break
			end
		end

		if self._heartbeatConnection then self._heartbeatConnection:Disconnect() end
		self._heartbeatConnection = RunService.Heartbeat:Connect(function()
			self:_updateHeartbeat()
		end)
	end)

	-- 2. OYUN BİTTİĞİNDE
	GameEndedEvent.OnClientEvent:Connect(function()
		self._isGameRunning = false
		self._targetKiller = nil

		-- Oyun seslerini kapat
		self:_stopAmbient()
		HeartbeatSound:Stop()
		HeartbeatSound.Volume = 0

		if self._heartbeatConnection then
			self._heartbeatConnection:Disconnect()
			self._heartbeatConnection = nil
		end

		-- Lobi müziğini tekrar başlat
		self:_playLobbyMusic()
	end)

	-- 3. STATE UPDATE DİNLEYİCİ
	local StateUpdateEvent = Net:RemoteEvent("StateUpdate")
	StateUpdateEvent.OnClientEvent:Connect(function(stateName, value)
		if stateName == "PlayerRoles" then
			for userId, role in pairs(value) do
				if role == "Killer" then
					self._targetKiller = Players:GetPlayerByUserId(tonumber(userId))
				end
			end
		end
	end)

	-- 4. OYUNA İLK GİRİŞ
	if not self._isGameRunning then
		self:_playLobbyMusic()
	end
end

return AmbientSoundController