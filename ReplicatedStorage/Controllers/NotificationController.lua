-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")

local Signal = require(Packages:WaitForChild("Signal"))
local Net = require(Packages:WaitForChild("Net"))

local Interface = Common:WaitForChild("Interface")
local NotificationAssets = Interface:WaitForChild("NotificationAssets") -- Doğru klasör yolu

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

-- Module
local NotificationController = {
	Name = script.Name,
	Signals = {
		SendNotification = Signal.new()
	}
}

function NotificationController:CreateNotification(Text : string, Lifetime : number)
	if (typeof(Text) ~= "string") then return end
	if (typeof(Lifetime) ~= "number") then return end

	local NewNotification = NotificationAssets.Notification:Clone()
	NewNotification.Text = Text
	NewNotification.Visible = true -- Görünür olduğundan emin olalım

	task.delay(Lifetime or 5, function()
		if NewNotification and NewNotification.Parent then
			NewNotification:Destroy()
		end
	end)

	return NewNotification
end

function NotificationController:OnStart()
	-- UI'ın yüklendiğinden emin ol
	local NotificationHUD = PlayerGui:WaitForChild("NotificationHUD")

	local function AddNotification(Text : string, Lifetime : number)
		local Notification = self:CreateNotification(Text, Lifetime)
		if (not Notification) then return end


		Notification.Parent = NotificationHUD
	end

	-- Hem Client içi sinyali hem de Sunucu sinyalini dinle
	self.Signals.SendNotification:Connect(AddNotification)

	-- Sunucudan gelen bildirimi dinle (Attack.lua buraya yolluyor)
	Net:Connect("SendNotification", function(Text, Lifetime)
		AddNotification(Text, Lifetime)
	end)
end

return NotificationController