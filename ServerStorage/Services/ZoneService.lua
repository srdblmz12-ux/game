-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Zone = require(Packages:WaitForChild("Zone"))
local Net = require(Packages:WaitForChild("Net"))

local ZoneContainer = workspace:WaitForChild("Zone")

-- Module
local ZoneService = {
	Name = script.Name,
	Client = {}
}

function ZoneService:CreateZone(Container, PlayerEntered : (Player) -> (), PlayerExited : (Player) -> ())
	local NewZone = Zone.new(Container)
	NewZone.PlayerEntered:Connect(PlayerEntered)
	NewZone.PlayerExited:Connect(PlayerExited)
	
	return NewZone
end

function ZoneService:OnStart()
	local PopupEvent = Net:RemoteEvent("Popup")
	
	-- VIP
	self:CreateZone(ZoneContainer:WaitForChild("VIP"), function(Player : Player)
		PopupEvent:FireClient(Player, "Show", "VIPPopup")
	end, function(Player : Player)
		PopupEvent:FireClient(Player, "Hide", "VIPPopup")
	end)
	
	-- Group Reward
	self:CreateZone(ZoneContainer:WaitForChild("GroupReward"), function(Player : Player)
		PopupEvent:FireClient(Player, "Show", "GroupPopup")
	end, function(Player : Player)
		PopupEvent:FireClient(Player, "Hide", "GroupPopup")
	end)
end

return ZoneService
