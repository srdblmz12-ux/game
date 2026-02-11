-- Services
local ServerStorage = game:GetService("ServerStorage")

-- Variables
local Services = ServerStorage:WaitForChild("Services")
local PlayerService = require(Services:WaitForChild("PlayerService"))

-- Module
local LeaveIngame = {}

function LeaveIngame:OnPlayerRemoved(Player : Player)
	--[[
		if PlayerService.ActiveSession.IsActive then
			local pData = PlayerService.ActiveSession.Participants[Player.UserId]
			if pData and not pData.IsDead then
				pData.IsDead = true

				if pData.Role == "Survivor" then PlayerService.ActiveSession.Counts.Survivor -= 1 end
				if pData.Role == "Killer" then PlayerService.ActiveSession.Counts.Killer -= 1 end

				PlayerService.Signals.PlayerDied:Fire(Player, pData.Role, PlayerService.ActiveSession.Counts)
			end
		end
	]]
end

return LeaveIngame