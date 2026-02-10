-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Variables
local CmdrClient = require(ReplicatedStorage:WaitForChild("CmdrClient"))

-- Runtime
CmdrClient:SetActivationKeys({ Enum.KeyCode.F6 })