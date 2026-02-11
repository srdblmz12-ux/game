-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ServerStorage:WaitForChild("Modules")

local ProfileStore = require(Modules:WaitForChild("ProfileStore"))
local OrderedStore = require(Modules:WaitForChild("OrderedStore"))
local Promise = require(Packages:WaitForChild("Promise"))
local Signal = require(Packages:WaitForChild("Signal"))
local Net = require(Packages:WaitForChild("Net"))

-- Profile Template
local PROFILE_TEMPLATE = {
	CurrencyData = {
		Spent = 0,
		Total = 0,
		Value = 0, -- Token Miktarı
		Name = "Token"
	},
	Wins = 0,
	KillerSkins = {
		["Bloxxer"] = true
	},
	KillerSkills = {},
	Equippeds = {
		KillerSkin = "Bloxxer",
		KillerSkill = "",
	},
	MurdererSkill = "Default"
}

local Store = ProfileStore.New(RunService:IsStudio() and "Test" or "Live1", PROFILE_TEMPLATE)

-- Service Definition
local DataService = {
	Name = "DataService",
	Client = {},
	LoadedProfiles = {},

	-- Dışarıdan erişilebilir Leaderboard nesneleri
	Leaderboards = {
		Token = OrderedStore.new("GlobalTokenLB", "CurrencyData.Value", 10),
		Wins = OrderedStore.new("GlobalWinsB", "Wins", 10)
	},

	Signals = {
		ProfileLoaded = Signal.new(),
		ProfileReleased = Signal.new(),
		DataUpdate = Signal.new() -- [YENİ] Sunucu içi veri değişim sinyali
	},
	Network = {
		DataUpdate = Net:RemoteEvent("DataUpdate") -- Client için
	}
}

--// Helper Functions

local function GetTablePath(root, path)
	local parts = string.split(path, ".")
	local current = root
	for i = 1, #parts - 1 do
		current = current[parts[i]]
		if not current then return nil, nil end
	end
	return current, parts[#parts]
end

--// Client Functions

function DataService.Client:GetData(player)
	return DataService:GetData(player)
end

--// Server Functions

function DataService:SetValue(player, path, value)
	local profile = self.LoadedProfiles[player]
	if not profile then return end

	local dataTable, key = GetTablePath(profile.Data, path)

	if dataTable and key then
		dataTable[key] = value

		-- 1. Client'a bildir (GUI güncellemesi için)
		self.Network.DataUpdate:FireClient(player, path, value)

		-- 2. Server'a bildir (Leaderstats ve diğer sistemler için) [YENİ]
		self.Signals.DataUpdate:Fire(player, path, value)
	end
end

function DataService:UpdateValue(player, path, callbackOrAmount)
	local profile = self.LoadedProfiles[player]
	if not profile then return end

	local dataTable, key = GetTablePath(profile.Data, path)

	if dataTable and key then
		local oldValue = dataTable[key]
		local newValue

		if type(callbackOrAmount) == "number" and type(oldValue) == "number" then
			newValue = oldValue + callbackOrAmount
		elseif type(callbackOrAmount) == "function" then
			newValue = callbackOrAmount(oldValue)
		else
			newValue = callbackOrAmount
		end

		dataTable[key] = newValue

		-- 1. Client'a bildir
		self.Network.DataUpdate:FireClient(player, path, newValue)

		-- 2. Server'a bildir [YENİ]
		self.Signals.DataUpdate:Fire(player, path, newValue)

		return newValue
	end
end

function DataService:SetDictionaryItem(player, path, key, value)
	local profile = self.LoadedProfiles[player]
	if not profile then return end

	local dataTable, pathKey = GetTablePath(profile.Data, path)

	if dataTable and pathKey then
		local targetTable = dataTable[pathKey]
		if targetTable and type(targetTable) == "table" then
			targetTable[key] = value

			-- 1. Client'a bildir
			self.Network.DataUpdate:FireClient(player, path, targetTable)

			-- 2. Server'a bildir (Tüm tabloyu gönderiyoruz) [YENİ]
			self.Signals.DataUpdate:Fire(player, path, targetTable)
		end
	end
end

function DataService:GetData(player)
	local profile = self.LoadedProfiles[player]
	if profile then return profile.Data end

	local maxRetries = 100
	local attempts = 0
	while player:IsDescendantOf(Players) and attempts < maxRetries do
		attempts += 1
		profile = self.LoadedProfiles[player]
		if profile then return profile.Data end
		task.wait(0.1)
	end
	return nil
end

function DataService:GetProfile(player)
	return Promise.new(function(resolve, reject)
		local profile = self.LoadedProfiles[player]
		if profile then
			resolve(profile)
		else
			reject("Profile not loaded for: " .. player.Name)
		end
	end)
end

function DataService:LoadProfile(player)
	local profile = Store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function() return player.Parent ~= Players end,
	})

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile.OnSessionEnd:Connect(function()
			self.LoadedProfiles[player] = nil
			for _, leaderboard in pairs(self.Leaderboards) do
				leaderboard:RemoveProfile(player)
			end
			player:Kick("Session ended.") 
		end)

		if player:IsDescendantOf(Players) then
			self.LoadedProfiles[player] = profile

			for _, leaderboard in pairs(self.Leaderboards) do
				leaderboard:AddProfile(player, profile)
			end

			self.Signals.ProfileLoaded:Fire(player, profile)
		else
			profile:EndSession()
		end
	else
		player:Kick("Profile load failed.")
	end
end

function DataService:ReleaseProfile(player)
	local profile = self.LoadedProfiles[player]
	if profile then
		for _, leaderboard in pairs(self.Leaderboards) do
			leaderboard:RemoveProfile(player)
		end

		profile:EndSession()
		self.LoadedProfiles[player] = nil
		self.Signals.ProfileReleased:Fire(player)
	end
end

function DataService:OnStart()
	Players.PlayerAdded:Connect(function(player) self:LoadProfile(player) end)
	Players.PlayerRemoving:Connect(function(player) self:ReleaseProfile(player) end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function() self:LoadProfile(player) end)
	end

	task.spawn(function()
		while true do
			task.wait(10)
			for key, leaderboard in pairs(self.Leaderboards) do
				leaderboard:Refresh()
			end
		end
	end)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.LoadedProfiles[player]
		if profile then profile:EndSession() end
	end
	task.wait(2)
end)

return DataService
