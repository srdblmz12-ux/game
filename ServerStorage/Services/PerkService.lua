-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common") 

local Services = ServerStorage:WaitForChild("Services")

local MurdererSkills = Common:WaitForChild("MurdererSkills")
local SurvivorSkills = Common:WaitForChild("SurvivorSkills")

local Trove = require(Packages:WaitForChild("Trove"))
local Net = require(Packages:WaitForChild("Net"))

local DataService = require(Services:WaitForChild("DataService"))

local TagKey = "PerkTool"

-- Module
local PerkService = {
	Name = script.Name,
	Client = {},

	SelectionLimit = 1,
	SelectedPerks = {},
	CachedPerks = {
		MurdererPerks = {},
		SurvivorPerks = {}
	},
	-- Yapı: { [Player] = { PerkData1, PerkData2, ... } }
	PlayerPerks = {}, 

	Network = {
		PerkList = Net:RemoteEvent("SkillList"),
		PerkAssigned = Net:RemoteEvent("PerkAssigned"),
		PerkActivated = Net:RemoteEvent("PerkActivated"),
		PerkSelectionLimit = Net:RemoteEvent("PerkSelectionLimit"),
	},
}

--// Client Bridge
function PerkService.Client:GetPerks(Player : Player)
	return PerkService:GetPerks()
end

function PerkService.Client:SelectPerk(Player : Player, PerkName : string)
	local foundPerk = nil
	for _, perkData in ipairs(PerkService.SelectedPerks) do
		if perkData.Name == PerkName then
			foundPerk = perkData
			break
		end
	end

	if not foundPerk then return false, "Perk doesn't exist in backend." end

	local currentPerks = PerkService.PlayerPerks[Player] or {}

	-- Limit Kontrolü (SelectedPerks sayısı ile Limit arasındaki en küçük değer)
	local effectiveLimit = math.min(PerkService.SelectionLimit, #PerkService.SelectedPerks)

	if #currentPerks >= effectiveLimit then
		return false, "Perk limit reached."
	end

	-- Duplicate (Aynı perki alma) Kontrolü
	for _, ownedPerk in ipairs(currentPerks) do
		if ownedPerk.Name == PerkName then
			return false, "You already have this perk."
		end
	end

	PerkService:GiveSurvivorPerk(Player, PerkName)
	return true, "Selected perk"
end

--// Main Logic

function PerkService:PerkSelectionLimit(Limit : number?)
	local NewLimit = typeof(Limit) == "number" and Limit or 1
	NewLimit = NewLimit <= 0 and 1
	
	local OldLimit = self.SelectionLimit
	self.SelectionLimit = NewLimit
	
	if (OldLimit ~= self.SelectionLimit) then
		self.Network.PerkSelectionUpdated:FireClients(Limit)
	end
end

function PerkService:GetPerks() : {string}
	return self.SelectedPerks
end

function PerkService:ResetPerks()
	self.SelectedPerks = {}
	self.Network.PerkList:FireAllClients({})
end

function PerkService:GeneratePerks(PerkCount : number?)
	self.SelectedPerks = {}
	local targetCount = PerkCount or 3
	if targetCount <= 0 then targetCount = 3 end

	local availablePerks = {}
	for _, api in pairs(self.CachedPerks.SurvivorPerks) do
		table.insert(availablePerks, api)
	end

	local amountToPick = math.min(targetCount, #availablePerks)

	for i = 1, amountToPick do
		local randomIndex = math.random(1, #availablePerks)
		local pickedPerkAPI = availablePerks[randomIndex]

		table.insert(self.SelectedPerks, {
			Name = pickedPerkAPI.Name,
			Description = pickedPerkAPI.Description,
			Image = pickedPerkAPI.Image or "" 
		})
		table.remove(availablePerks, randomIndex)
	end

	self.Network.PerkList:FireAllClients(self.SelectedPerks)
	return self.SelectedPerks
end

function PerkService:GiveRandomPerk(Player : Player)
	if #self.SelectedPerks == 0 then return end

	local currentPerks = self.PlayerPerks[Player] or {}
	local effectiveLimit = math.min(self.SelectionLimit, #self.SelectedPerks)

	if #currentPerks >= effectiveLimit then return end

	local randomPerkData = self.SelectedPerks[math.random(1, #self.SelectedPerks)]

	-- Zaten varsa vermeyelim
	for _, owned in ipairs(currentPerks) do
		if owned.Name == randomPerkData.Name then return end
	end

	self:GiveSurvivorPerk(Player, randomPerkData.Name)
end

function PerkService:GivePerkTool(Player : Player, API : any)
	local NewAPI = table.clone(API)

	-- Listeyi oluştur veya al
	if not self.PlayerPerks[Player] then
		self.PlayerPerks[Player] = {}
	end

	-- Listeye Ekle
	table.insert(self.PlayerPerks[Player], NewAPI)

	local tool = Instance.new("Tool")
	tool.Name = NewAPI.Name
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:AddTag(TagKey)

	NewAPI.Trove = Trove.new()
	NewAPI.Player = Player
	NewAPI.Tool = tool

	tool.Activated:Connect(function()
		if NewAPI.OnActivate then
			local success, err = pcall(NewAPI.OnActivate, NewAPI)
			if not success then
				warn(`Server activate error {tool.Name}: {err}`)
			end
		end
	end)

	-- Tool Destroying: Listeden ve hafızadan temizle
	tool.Destroying:Once(function()
		NewAPI.Trove:Destroy()

		-- Oyuncunun listesinden bu spesifik perki bul ve sil
		local playerList = self.PlayerPerks[Player]
		if playerList then
			for i, perkData in ipairs(playerList) do
				if perkData == NewAPI then
					table.remove(playerList, i)
					break
				end
			end

			-- Eğer liste tamamen boşaldıysa nil yapabiliriz (Opsiyonel temizlik)
			if #playerList == 0 then
				self.PlayerPerks[Player] = nil
			end
		end
	end)

	NewAPI.Trove:Add(tool)
	tool.Parent = Player.Backpack
	return tool
end

-- Tool Olmayan (Passive/Hotkey) Perk Verme Fonksiyonu
function PerkService:GivePerk(Player : Player, API : any)
	local NewAPI = table.clone(API)

	if not self.PlayerPerks[Player] then
		self.PlayerPerks[Player] = {}
	end

	-- Listeye Ekle
	table.insert(self.PlayerPerks[Player], NewAPI)

	NewAPI.Trove = Trove.new()
	NewAPI.Player = Player
	-- NewAPI.Tool = nil (Zaten nil ama açıkça belirtmek kafa karışıklığını önler)

	-- Client'a bilgi ver (UI vs için)
	self.Network.PerkAssigned:FireClient(Player, {
		Name = NewAPI.Name,
		Id = NewAPI.Id
	})

	-- Eğer bu perkin bir temizlenme/destroy mantığı varsa Trove'a eklenmeli
	-- Şimdilik manuel RemovePerk çağrılana kadar listede kalır.
end

function PerkService:RemovePerk(Player : Player)
	local perkList = self.PlayerPerks[Player]
	if perkList then
		-- Hepsini temizle
		for _, perkData in ipairs(perkList) do
			if perkData.Trove then
				perkData.Trove:Destroy()
			end
		end
		self.PlayerPerks[Player] = nil
		self.Network.PerkAssigned:FireClient(Player, nil)
	end
end

function PerkService:GiveSurvivorPerk(Player : Player, PerkName : string)
	local api = self.CachedPerks.SurvivorPerks[PerkName]
	if api then
		self:GivePerkTool(Player, api)
	else
		warn(`Survivor perk not found: {PerkName}`)
	end
end

function PerkService:GiveMurdererPerk(Player : Player)
	DataService:GetProfile(Player):andThen(function(Profile)
		local Data = Profile.Data
		local Equippeds = Data.Equippeds
		local KillerSkillName = Equippeds.KillerSkill
		if not (KillerSkillName and KillerSkillName ~= "") then return end

		local api = self.CachedPerks.MurdererPerks[KillerSkillName]
		if api then
			-- Eğer Murderer skilli tool ise GivePerkTool, değilse GivePerk kullan
			-- Genelde murderer skilleri tool olur (bıçak/yetenek), ama duruma göre değişir.
			-- Şimdilik Tool varsayıyoruz:
			self:GivePerkTool(Player, api)
		else
			warn(`Murderer perk not found: {KillerSkillName}`)
		end
	end):catch(warn)
end

function PerkService:OnStart()
	-- Perk Manager
	local function CacheSkill(SkillModule : ModuleScript)
		if (not SkillModule:IsA("ModuleScript")) then return end

		local Success, Response = pcall(require, SkillModule)
		if (Success) then
			Response.Id = SkillModule.Name
			return Response
		else
			warn(`Skill req failed: {Response}`)
			return
		end
	end

	local function FetchTableAndSave(Table : {Instance}, ReferenceTable : {})
		for _,Perk in ipairs(Table) do
			ReferenceTable[Perk.Name] = CacheSkill(Perk)
		end
	end

	FetchTableAndSave(MurdererSkills.Skills:GetChildren(), self.CachedPerks.MurdererPerks)
	FetchTableAndSave(SurvivorSkills:GetChildren(), self.CachedPerks.SurvivorPerks)

	-- Perk Controller
	Players.PlayerRemoving:Connect(function(Player : Player)
		self:RemovePerk(Player)
	end)

	-- Tool Olmayan Perkleri Tetikleme (Remote Event ile)
	self.Network.PerkActivated.OnServerEvent:Connect(function(Player : Player, Hit : CFrame, Target : Instance?)
		local perkList = self.PlayerPerks[Player]

		if (perkList) then
			for _, Data in ipairs(perkList) do
				-- Sadece Tool olmayanlar (Tool'lar kendi Activated eventini kullanır)
				if (not Data.Tool) then 
					if Data.OnActivate then
						local success, err = pcall(Data.OnActivate, Data)
						if not success then
							warn(`Server activate error {Data.Id}: {err}`)
						end
					end
				end
			end
		end
	end)

	-- Murderer Perk
	self.CachedPerks.MurdererPerks["Attack"] = CacheSkill(MurdererSkills.Attack)
end

return PerkService
