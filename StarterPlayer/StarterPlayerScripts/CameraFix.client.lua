local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Karakter her yüklendiğinde (Spawn olduğunda) çalışır
player.CharacterAdded:Connect(function(character)
	-- Humanoid'in yüklenmesini bekle (en fazla 10 saniye)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		camera.CameraSubject = humanoid
	end
end)