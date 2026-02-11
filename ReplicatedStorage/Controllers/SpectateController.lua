-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Controllers = ReplicatedStorage:WaitForChild("Controllers")

local Trove = require(Packages:WaitForChild("Trove"))
local Net = require(Packages:WaitForChild("Net"))
local GameController = require(Controllers:WaitForChild("GameController"))

-- References
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = Workspace.CurrentCamera

-- Controller
local SpectateController = {
	Name = script.Name,
	IsSpectating = false,
	CurrentTargetIndex = 1,
	ValidTargets = {},
	Trove = Trove.new(),
}

--// YARDIMCI FONKSIYONLAR

function SpectateController:GetValidTargets()
	local targets = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then continue end
		local char = player.Character
		if char and char:FindFirstChild("Humanoid") and char:FindFirstChild("HumanoidRootPart") and char.Humanoid.Health > 0 then
			table.insert(targets, player)
		end
	end
	return targets
end

function SpectateController:UpdateView(Container)
	self.ValidTargets = self:GetValidTargets()

	if #self.ValidTargets == 0 then
		self:StopSpectating(Container)
		return
	end

	if self.CurrentTargetIndex > #self.ValidTargets then self.CurrentTargetIndex = 1 end
	if self.CurrentTargetIndex < 1 then self.CurrentTargetIndex = #self.ValidTargets end

	local targetPlayer = self.ValidTargets[self.CurrentTargetIndex]

	-- UI GÜNCELLEME KISMI
	-- Hiyerarsi: SpectateContainer -> Controllers -> [Username, Role, NextButton, PreviousButton]
	local ControllersUI = Container:FindFirstChild("Controllers")
	if not ControllersUI then return end

	if ControllersUI:FindFirstChild("Username") then
		ControllersUI.Username.Text = targetPlayer.DisplayName .. " (@" .. targetPlayer.Name .. ")"
	end

	if ControllersUI:FindFirstChild("Role") then
		ControllersUI.Role.Text = "Loading..."

		task.spawn(function()
			local success, data = pcall(function() 
				return Net:Invoke("GameService/GetPlayerData", targetPlayer.Name) 
			end)

			if success and data and self.IsSpectating and self.ValidTargets[self.CurrentTargetIndex] == targetPlayer then
				ControllersUI.Role.Text = data.Role or "Unknown"
				if data.Role == "Killer" then
					ControllersUI.Role.TextColor3 = Color3.fromRGB(255, 50, 50)
				elseif data.Role == "Survivor" then
					ControllersUI.Role.TextColor3 = Color3.fromRGB(50, 255, 50)
				else
					ControllersUI.Role.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
			end
		end)
	end
end

function SpectateController:StartSpectating(Container)
	if self.IsSpectating then return end

	self.ValidTargets = self:GetValidTargets()
	if #self.ValidTargets == 0 then return end

	self.IsSpectating = true
	GameController:SetSpectating(true)
	self.CurrentTargetIndex = 1

	-- UI Aç
	Container.Visible = true
	local SpectateButton = Container:FindFirstChild("SpectateButton")
	if SpectateButton and SpectateButton:FindFirstChild("Title") then
		SpectateButton.Title.Text = "Lobby"
	end

	if Container:FindFirstChild("Controllers") then
		Container.Controllers.Visible = true
	end

	self:UpdateView(Container)

	RunService:BindToRenderStep("SpectateCam", Enum.RenderPriority.Camera.Value + 1, function()
		if not self.IsSpectating then 
			RunService:UnbindFromRenderStep("SpectateCam")
			return 
		end

		local targetPlayer = self.ValidTargets[self.CurrentTargetIndex]

		if not targetPlayer or not targetPlayer.Parent or 
			not targetPlayer.Character or 
			not targetPlayer.Character:FindFirstChild("Humanoid") or 
			targetPlayer.Character.Humanoid.Health <= 0 then

			self:NextTarget(Container)
			return
		end

		local hum = targetPlayer.Character:FindFirstChild("Humanoid")
		if hum then
			Camera.CameraType = Enum.CameraType.Custom
			Camera.CameraSubject = hum
		end
	end)
end

function SpectateController:StopSpectating(Container)
	self.IsSpectating = false
	GameController:SetSpectating(false)
	RunService:UnbindFromRenderStep("SpectateCam")

	task.wait(0.1)
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
		Camera.CameraType = Enum.CameraType.Custom
		Camera.CameraSubject = LocalPlayer.Character.Humanoid
	end

	-- UI Kapat / Resetle
	local SpectateButton = Container:FindFirstChild("SpectateButton")
	if SpectateButton and SpectateButton:FindFirstChild("Title") then
		SpectateButton.Title.Text = "Spectate"
	end

	if Container:FindFirstChild("Controllers") then
		Container.Controllers.Visible = false
	end
end

function SpectateController:NextTarget(Container)
	self.CurrentTargetIndex = self.CurrentTargetIndex + 1
	self:UpdateView(Container)
end

function SpectateController:PrevTarget(Container)
	self.CurrentTargetIndex = self.CurrentTargetIndex - 1
	self:UpdateView(Container)
end

function SpectateController:OnStart()
	-- UI Nesnelerini Güvenli Sekilde Bekle
	local HUD = PlayerGui:WaitForChild("SpectateHUD", 10)
	if not HUD then warn("SpectateHUD bulunamadi!") return end

	local Container = HUD:WaitForChild("SpectateContainer", 10)
	if not Container then warn("SpectateContainer bulunamadi!") return end

	local SpectateBtn = Container:WaitForChild("SpectateButton", 5)
	local ControllersUI = Container:WaitForChild("Controllers", 5)

	-- Buton Isimlerini Güncelledik: PreviousButton / NextButton
	local PrevBtn = ControllersUI and ControllersUI:WaitForChild("PreviousButton", 5)
	local NextBtn = ControllersUI and ControllersUI:WaitForChild("NextButton", 5)

	Container.Visible = false
	if ControllersUI then ControllersUI.Visible = false end

	local CurrentGameStatus = "Intermission"

	-- Event Baglantilari
	if SpectateBtn then
		SpectateBtn.Activated:Connect(function()
			if self.IsSpectating then
				self:StopSpectating(Container)
			else
				self:StartSpectating(Container)
			end
		end)
	end

	if PrevBtn then
		PrevBtn.Activated:Connect(function() self:PrevTarget(Container) end)
	end

	if NextBtn then
		NextBtn.Activated:Connect(function() self:NextTarget(Container) end)
	end

	local function CheckVisibility(isDeathEvent)
		if CurrentGameStatus ~= "GameRunning" and CurrentGameStatus ~= "Warmup" then
			Container.Visible = false
			if self.IsSpectating then self:StopSpectating(Container) end
			return
		end

		if isDeathEvent then task.wait(3.5) end

		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChild("Humanoid")

		if not hum or hum.Health <= 0 then
			Container.Visible = true
			return
		end

		task.spawn(function()
			local success, myData = pcall(function()
				return Net:Invoke("GameService/GetPlayerData", LocalPlayer.Name)
			end)
			if success and myData and myData.Role == "Lobby" then
				Container.Visible = true
			else
				Container.Visible = false
				if self.IsSpectating then self:StopSpectating(Container) end
			end
		end)
	end

	Net:Connect("StateUpdate", function(State, Data)
		if State == "GameStatus" then
			CurrentGameStatus = Data
			CheckVisibility(false)
		end
	end)

	LocalPlayer.CharacterAdded:Connect(function(char)
		CheckVisibility(false)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Died:Connect(function() CheckVisibility(true) end)
		end
	end)

	if LocalPlayer.Character then
		CheckVisibility(false)
		local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
		if hum then
			hum.Died:Connect(function() CheckVisibility(true) end)
		end
	else
		CheckVisibility(false)
	end
end

return SpectateController