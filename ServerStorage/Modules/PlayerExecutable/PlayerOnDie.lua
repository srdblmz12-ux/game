-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Services = ServerStorage:WaitForChild("Services")

local PlayerService = require(Services:WaitForChild("PlayerService"))

local Signal = require(Packages:WaitForChild("Signal"))

-- Module
local OnDie = {}

function OnDie:OnPlayerAdded(Player : Player)
	PlayerService.Signals.PlayerDied = PlayerService.Signals.PlayerDied or Signal.new()
	local function CharacterAdded(Character : Model)
		local Humanoid = Character:WaitForChild("Humanoid", 5) :: Humanoid?
		if (not Humanoid) then return end
		
		Humanoid.Died:Once(function()
			PlayerService.Signals.PlayerDied:Fire()
		end)
	end
	
	if (Player.Character) then CharacterAdded(Player.Character) end
	Player.CharacterAdded:Connect(CharacterAdded)
end

return OnDie
