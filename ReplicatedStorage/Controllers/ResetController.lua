-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Controllers = ReplicatedStorage:WaitForChild("Controllers")

local Net = require(Packages:WaitForChild("Net"))
local NotificationController = require(Controllers:WaitForChild("NotificationController"))

local LocalPlayer = Players.LocalPlayer

-- Module
local ResetController = {
	Name = script.Name
}

function ResetController:OnStart()
	local ResetBindable = Instance.new("BindableEvent")
	local function SetupResetCallback()
		local Success, Error = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", ResetBindable)
		end)
		
		if not Success then
			warn("Reset callback setup failed:", Error)
			task.delay(1, SetupResetCallback)
		end
	end
	
	SetupResetCallback()
	
	ResetBindable.Event:Connect(function()
		local State = Net:Invoke("GameService/GetGameState")
		if not (State == "Intermission" or State == "OnVoting") then
			NotificationController.Signals.SendNotification:Fire("Reset disabled during the match", 5)
		else
			local Character = LocalPlayer.Character
			if (Character) then
				local Humanoid = Character:WaitForChild("Humanoid", 5) :: Humanoid?
				if (Humanoid) then
					Humanoid.Health = 0
				end
			end
		end
	end)
end

return ResetController
