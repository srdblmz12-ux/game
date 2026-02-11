--Services
local ServerStorage = game:GetService("ServerStorage")

-- Variables
local Services = ServerStorage:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))

-- Module
local Leaderstats = {}

function Leaderstats:OnPlayerAdded(Player : Player)
	local Leaderstats = Instance.new("Folder")
	Leaderstats.Name = "leaderstats"
	Leaderstats.Parent = Player
	
	local function CreateValue(Classname : "StringValue" | "IntValue" | "NumberValue", Name : string, Prevalue : any?)
		local New = Instance.new(Classname) :: Instance
		if (not New:IsA("ValueBase")) then
			warn("Can't create this instance, ValueBase instance is required.")
			New:Destroy()
			return
		end
		
		New.Name = Name
		New.Parent = Leaderstats
		if (Prevalue ~= nil) then
			New.Value = Prevalue
		end
		
		return New
	end
	
	DataService:GetData(Player):andThen(function(Data)
		local Tokens = CreateValue("IntValue", "Tokens", Data.CurrencyData.Value) :: IntValue
		local Wins = CreateValue("IntValue", "Wins", Data.Wins) :: IntValue
		
		DataService.Signals.DataUpdate:Connect(function(UpdatedPlayer : Player, Path : string, NewValue)
			if (UpdatedPlayer ~= Player) then return end
			if (Path == "CurrencyData.Value") then
				Tokens.Value = NewValue
			end
			if (Path == "Wins") then
				Wins.Value = NewValue
			end
		end)
	end)
end

return Leaderstats
