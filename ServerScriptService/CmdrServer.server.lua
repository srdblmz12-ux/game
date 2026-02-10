-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local CmdrAssets = ServerStorage:WaitForChild("CmdrAssets")

local Cmdr = require(Packages:WaitForChild("Cmdr"))
local Commands = CmdrAssets:WaitForChild("Commands")
local Types = CmdrAssets:WaitForChild("Types")
local Hooks = CmdrAssets:WaitForChild("Hooks")

-- Runtime
Cmdr:RegisterDefaultCommands()
Cmdr:RegisterCommandsIn(Commands)
Cmdr:RegisterTypesIn(Types)
Cmdr:RegisterHooksIn(Hooks)