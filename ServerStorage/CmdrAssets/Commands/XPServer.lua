local ServerStorage = game:GetService("ServerStorage")
local Services = ServerStorage:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))

return function(Context, Players, XPAmount)
	Players = typeof(Players) == "table" and Players or {Players}
	for _,Player in ipairs(Players) do
		DataService:SetValue(Player, "LevelData.ValueXP", XPAmount)
	end
	
	return `Added {XPAmount} to number of {#Players}`
end