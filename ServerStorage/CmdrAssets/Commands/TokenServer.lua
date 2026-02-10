local ServerStorage = game:GetService("ServerStorage")
local Services = ServerStorage:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))

return function(Context, Players, TokenAmount)
	Players = typeof(Players) == "table" and Players or {Players}
	for _,Player in ipairs(Players) do
		DataService:SetValue(Player, "CurrencyData.Value", TokenAmount)
	end

	return `Added {TokenAmount} to number of {#Players}`
end