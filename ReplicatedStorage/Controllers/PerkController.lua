-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")

local MurdererSkills = Common:WaitForChild("MurdererSkills")
local SurvivorSkills = Common:WaitForChild("SurvivorSkills")

local Trove = require(Packages:WaitForChild("Trove"))
local Net = require(Packages:WaitForChild("Net"))

local TagKey = "PerkTool"
local LocalPlayer = Players.LocalPlayer

-- Module
local PerkController = {
	Name = script.Name,

	-- Client Logic Modülleri (Visuals, Inputs)
	CachedPerks = {
		MurdererPerks = {},
		SurvivorPerks = {}
	},

	-- Aktif Yetenekler Listesi
	-- Format: { [PerkName] = { Data = {}, Trove = Trove, Tool = Tool?, Button = Button? } }
	ActivePerks = {},

	Network = {
		PerkList = Net:RemoteEvent("SkillList"),
		PerkAssigned = Net:RemoteEvent("PerkAssigned"),
		PerkActivated = Net:RemoteEvent("PerkActivated"),
	},
}

--// Helper: Modülleri Cache'le
local function CacheModules(Folder, TargetTable)
	for _, Module in ipairs(Folder:GetChildren()) do
		if Module:IsA("ModuleScript") then
			local success, api = pcall(require, Module)
			if success then
				TargetTable[Module.Name] = api
			else
				warn(`[PerkController] Modül yüklenemedi: {Module.Name}`)
			end
		end
	end
end

--// ÇEKIRDEK: Perk Kayit (Hybrid System)
function PerkController:RegisterPerk(PerkName : string, ToolInstance : Tool?)
	-- Eger zaten kayitliysa tekrar islem yapma
	if self.ActivePerks[PerkName] then return end

	-- 1. Ilgili Modülü Bul
	local PerkAPI = self.CachedPerks.SurvivorPerks[PerkName] or self.CachedPerks.MurdererPerks[PerkName]

	-- Client tarafinda modülü yoksa (sadece server datasiysa) bos tablo kullan
	local ClientModule = PerkAPI and table.clone(PerkAPI) or {}

	-- 2. Temizlik ve Yönetim Objeleri
	local PerkTrove = Trove.new()

	local PerkObject = {
		Name = PerkName,
		API = ClientModule,
		Tool = ToolInstance, -- Tool varsa instance, yoksa nil
		Trove = PerkTrove,
		Player = LocalPlayer,
		Button = nil -- Mobil butonu buraya kaydedecegiz
	}

	--// TIP A: FIZIKSEL TOOL (Biçak, Medkit vb.)
	if ToolInstance then
		-- Tool Eventleri
		PerkTrove:Connect(ToolInstance.Activated, function()
			if ClientModule.OnActivate then ClientModule:OnActivate(PerkObject) end
		end)

		PerkTrove:Connect(ToolInstance.Equipped, function()
			if ClientModule.OnEquip then ClientModule:OnEquip(PerkObject) end
		end)

		PerkTrove:Connect(ToolInstance.Unequipped, function()
			if ClientModule.OnUnequip then ClientModule:OnUnequip(PerkObject) end
		end)

		-- Tool Yok Oldugunda Temizle
		PerkTrove:Connect(ToolInstance.Destroying, function()
			self:UnregisterPerk(PerkName)
		end)

		-- Envanterden Düserse Temizle (Parent Degisimi)
		PerkTrove:Connect(ToolInstance.AncestryChanged, function(_, parent)
			if parent ~= LocalPlayer.Backpack and parent ~= LocalPlayer.Character then
				self:UnregisterPerk(PerkName)
			end
		end)

		--// TIP B: SANAL SKILL (Sprint, Dash, Pasif vb.)
	else
		-- Tus Listesini Hazirla (Multi-Key Destegi)
		local keysToBind = {}

		-- Tekil 'Keybind' varsa ekle
		if ClientModule.Keybind and typeof(ClientModule.Keybind) == "EnumItem" then
			table.insert(keysToBind, ClientModule.Keybind)
		end

		-- Çogul 'Keybinds' tablosu varsa hepsini ekle
		if ClientModule.Keybinds and type(ClientModule.Keybinds) == "table" then
			for _, key in ipairs(ClientModule.Keybinds) do
				table.insert(keysToBind, key)
			end
		end

		-- Eger tanimli tus varsa ContextActionService bagla
		if #keysToBind > 0 then
			local ActionName = "PerkAction_" .. PerkName

			-- BindAction (unpack ile çoklu tus destegi)
			ContextActionService:BindAction(ActionName, function(actionName, state, inputObj)
				if state == Enum.UserInputState.Begin then
					-- Server'a bildir
					self.Network.PerkActivated:FireServer(PerkName)

					-- Client Visual/Logic çalistir
					if ClientModule.OnActivate then
						ClientModule:OnActivate(PerkObject)
					end
				end
			end, true, unpack(keysToBind))

			-- Mobil Buton Özellestirmeleri
			local mobileButton = ContextActionService:GetButton(ActionName)
			if mobileButton then
				PerkObject.Button = mobileButton -- Obje içine kaydet (Cooldown görseli vb. için)

				-- Resim veya Baslik
				if ClientModule.MobileImage then
					ContextActionService:SetImage(ActionName, ClientModule.MobileImage)
				elseif ClientModule.MobileTitle then
					ContextActionService:SetTitle(ActionName, ClientModule.MobileTitle)
				end

				-- Pozisyon (UDim2)
				if ClientModule.MobilePosition then
					ContextActionService:SetPosition(ActionName, ClientModule.MobilePosition)
				end

				-- Buton Rengi
				if ClientModule.ButtonColor then
					mobileButton.ImageColor3 = ClientModule.ButtonColor
				end
			end

			-- Perk Silinince Tusu Kaldir
			PerkTrove:Add(function()
				ContextActionService:UnbindAction(ActionName)
			end)
		end

		-- Sanal Skill Eklenince 'Equip' sayilir (Pasif baslaticilar için)
		if ClientModule.OnEquip then
			task.spawn(function() ClientModule:OnEquip(PerkObject) end)
		end
	end

	-- 3. Listeye Kaydet
	self.ActivePerks[PerkName] = PerkObject

	-- 4. Trove Temizlik Garantisi
	-- Trove destroy edildiginde listeden silindiginden emin ol
	PerkTrove:Add(function()
		-- Eger listedeki hala bu objeyse (yenisi gelmediyse) sil
		if self.ActivePerks[PerkName] == PerkObject then
			self.ActivePerks[PerkName] = nil

			-- Sanal skiller için Unequip çagir
			if not ToolInstance and ClientModule.OnUnequip then
				ClientModule:OnUnequip(PerkObject)
			end
		end
	end)
end

--// ÇEKIRDEK: Perk Silme
function PerkController:UnregisterPerk(PerkName : string)
	local perkData = self.ActivePerks[PerkName]

	if perkData then
		-- Trove'u destroy etmek her seyi temizler:
		-- Eventleri koparir, Keybind'lari siler, Listeden kaydi siler.
		if perkData.Trove then
			perkData.Trove:Destroy()
		end
	end
end

--// BASLANGIÇ
function PerkController:OnStart()
	-- 1. Modülleri Yükle
	CacheModules(SurvivorSkills, self.CachedPerks.SurvivorPerks)
	CacheModules(MurdererSkills.Skills, self.CachedPerks.MurdererPerks)

	-- 2. Tool Takibi (CollectionService)
	local function OnToolAdded(Tool)
		if not Tool:IsA("Tool") then return end

		-- Sadece LocalPlayer'a aitse isle
		if Tool.Parent == LocalPlayer.Backpack or Tool.Parent == LocalPlayer.Character then
			self:RegisterPerk(Tool.Name, Tool)
		end
	end

	-- Taglenen Toollari dinle
	CollectionService:GetInstanceAddedSignal(TagKey):Connect(OnToolAdded)

	-- Mevcut Toollari Tara
	for _, tool in ipairs(CollectionService:GetTagged(TagKey)) do
		OnToolAdded(tool)
	end

	-- 3. Server Sinyalleri (Sanal Skiller ve Silme Emirleri)
	self.Network.PerkAssigned.OnClientEvent:Connect(function(Data)
		-- Veri yoksa (nil) tüm perkleri sil (Reset)
		if not Data then
			for name, _ in pairs(self.ActivePerks) do
				self:UnregisterPerk(name)
			end
			return
		end

		-- Server { Name="...", Remove=true } gönderdiyse sil
		if Data.Remove then
			self:UnregisterPerk(Data.Name)
		else
			-- Server { Name="..." } gönderdiyse ekle
			-- Tool parametresi 'nil' oldugu için RegisterPerk bunu sanal skill olarak isler
			self:RegisterPerk(Data.Name, nil)
		end
	end)
end

return PerkController