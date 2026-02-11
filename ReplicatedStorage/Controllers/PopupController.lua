-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")

local PopupAssets = Common:WaitForChild("PopupAssets")

local Signal = require(Packages:WaitForChild("Signal"))
local Net = require(Packages:WaitForChild("Net"))

-- Module
local PopupController = {
	Name = script.Name,
	Signals = {
		Popup = Signal.new()
	},
	Network = {
		Popup = Net:RemoteEvent("Popup")
	},
	PopupCache = {}
}

function PopupController:OnStart()
	for _,PopupModule : ModuleScript in ipairs(PopupAssets:GetChildren()) do
		if (not PopupModule:IsA("ModuleScript")) then continue end
		
		local Success, Response = pcall(require, PopupModule)
		if (not Success) then continue end
		
		self.PopupCache[PopupModule.Name] = Response
		if (typeof(Response.OnStart) == "function") then
			Response.OnStart(Response)
		end
	end
	
	local function ShowPopup(Name : string, ...)
		local PopupAPI = self.PopupCache[Name]
		if (PopupAPI and typeof(PopupAPI.Show) == "function") then
			PopupAPI.Show(PopupAPI, ...)
		end
	end
	
	local function HidePopup(Name : string, ...)
		local PopupAPI = self.PopupCache[Name]
		if (PopupAPI and typeof(PopupAPI.Hide) == "function") then
			PopupAPI.Hide(PopupAPI, ...)
		end
	end
	
	local function ListenEvent(State : "Show" | "Hide", Name : string, ...)
		if (State == "Show") then
			ShowPopup(Name, ...)
		elseif (State == "Hide") then
			HidePopup(Name, ...)
		end
	end
	
	self.Signals.Popup:Connect(ListenEvent)
	self.Network.Popup.OnClientEvent:Connect(ListenEvent)
end

return PopupController