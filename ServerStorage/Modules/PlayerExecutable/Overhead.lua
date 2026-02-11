-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Variables
local Services = ServerStorage:WaitForChild("Services")
local PlayerService = require(Services:WaitForChild("PlayerService"))

local Shared = ReplicatedStorage:WaitForChild("Shared")

local OverheadGuiAssets = Shared:WaitForChild("OverheadGuiAssets")
local Gui = OverheadGuiAssets:WaitForChild("OverheadGui")
local Icon = OverheadGuiAssets:WaitForChild("Icon")

local Developer = "rbxasset://textures/ui/PlayerList/developer.png"
local Premium = "rbxasset://textures/ui/PlayerList/PremiumIcon.png"
local Verified = "rbxasset://textures/ui/VerifiedBadgeNameIcon.png"
local PlayerIcons = {
	[414410946] = { -- serdar
		Developer,
		"rbxassetid://4969357404", 
	},
	[4775564686] = { -- mehmet
		Developer,
		"rbxassetid://105540078", 
		"rbxassetid://11104447788"
	},
	[1327643007] = { -- hamza
		"rbxassetid://15423490200", 
		"rbxassetid://10664762623", 
	}
}

-- Module
local OverheadGui = {}

function OverheadGui:OnPlayerAdded(Player : Player)
	local function CreateIcon(Id : string, Display : Frame)
		local Icon = Icon:Clone()
		Icon.Image = Id
		Icon.Parent = Display
	end
	local function CharacterAdded(Character)
		local NewGui = Gui:Clone()
		NewGui.Parent = Character.PrimaryPart or Character
		NewGui.Display.Username.Text = Player.DisplayName
		
		if (Player.UserId <= 0) then
			CreateIcon(Developer, NewGui.Display)
		end

		local IconTable = PlayerIcons[Player.UserId] or {}
		for _,IconId in ipairs(IconTable) do
			CreateIcon(IconId, NewGui.Display)
		end

		if (Player.HasVerifiedBadge) then
			CreateIcon(Verified, NewGui.Display)
		end
		if (Player.MembershipType ~= Enum.MembershipType.None) then
			CreateIcon(Premium, NewGui.Display)
		end
		
		PlayerService:GetData(Player):andThen(function(Data)
			if (Data.Role ~= "Lobby") then
				NewGui:Destroy()
			end
		end)
	end
	
	if (Player.Character) then CharacterAdded(Player.Character) end
	Player.CharacterAdded:Connect(CharacterAdded)
end

return OverheadGui
