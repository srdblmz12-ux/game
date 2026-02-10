-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Controllers = ReplicatedStorage:WaitForChild("Controllers")

local Trove = require(Packages:WaitForChild("Trove"))
local spr = require(Packages:WaitForChild("spr"))
local Net = require(Packages:WaitForChild("Net"))

local NotificationController = require(Controllers:WaitForChild("NotificationController"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

local NewTrove = Trove.new()

-- Module
local GroupPopup = {}
local PopupHUD = PlayerGui:WaitForChild("PopupHUD")

function GroupPopup:Show(ShowXButton)
	NewTrove:Clean()
	
end

function GroupPopup:Hide()
	NewTrove:Clean()
end

return GroupPopup