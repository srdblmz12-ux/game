local CollisionManager = {}

function CollisionManager:OnPlayerAdded(Player : Player)
	local function CharacterAdded(Character : Model)
		for _,Basepart : BasePart in ipairs(Character:GetDescendants()) do
			if (not Basepart:IsA("BasePart")) then continue end
			Basepart.CollisionGroup = "Player"
		end
	end
	
	if (Player.Character) then CharacterAdded(Player.Character) end
	Player.CharacterAdded:Connect(CharacterAdded)
end

return CollisionManager
