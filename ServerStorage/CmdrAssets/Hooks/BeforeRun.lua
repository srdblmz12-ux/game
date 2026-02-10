local Ranks = {
	User = 0,
	Moderator = 1,
	Admin = 2,
	Owner = 3
}


local GroupRequirements = {
	["DefaultAdmin"] = Ranks.Moderator,
	["SuperAdmin"] = Ranks.Owner,
	["Admin"] = Ranks.Admin,
}

local Admins = {
	[4775564686] = "Owner",
}

local function CanRun(player, commandGroup)
	local requiredLevel = GroupRequirements[commandGroup] or Ranks.User
	if requiredLevel == 0 then return true end
	
	local playerRankName = Admins[player.UserId]
	local playerLevel = 0
	if playerRankName then
		playerLevel = Ranks[playerRankName] or 0
	end
	
	return playerLevel >= requiredLevel
end

return function(Registry)
	Registry:RegisterHook("BeforeRun", function(Context)
		local Player = Context.Executor
		local CommandGroup = Context.Group
		if (CanRun(Player, CommandGroup)) then
			return nil
		else
			return "You do not have permission to use this command! (" .. tostring(CommandGroup) .. ")"
		end
	end)
end