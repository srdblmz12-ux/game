local DataStoreService = game:GetService("DataStoreService")

local OrderedStore = {}
OrderedStore.__index = OrderedStore

function OrderedStore.new(storeName, dataKey, cooldown)
	local self = setmetatable({}, OrderedStore)

	self.Store = DataStoreService:GetOrderedDataStore(storeName)
	self.DataKey = dataKey
	self.Cooldown = cooldown or 10

	self.LastRefresh = 0
	self.LiveProfiles = {} 

	return self
end

function OrderedStore:AddProfile(player, profile)
	if not player or not profile then return end
	self.LiveProfiles[player] = profile
end

function OrderedStore:RemoveProfile(player)
	self.LiveProfiles[player] = nil
end

function OrderedStore:Refresh()
	local now = os.time()

	if (now - self.LastRefresh) < self.Cooldown then
		return false 
	end

	self.LastRefresh = now

	task.spawn(function()
		for player, profile in pairs(self.LiveProfiles) do
			if player.Parent and profile:IsActive() then
				local rawValue = profile.Data
				for _, keyPart in ipairs(string.split(self.DataKey, ".")) do
					if rawValue then
						rawValue = rawValue[keyPart]
					else
						break
					end
				end

				local cleanValue = math.floor(tonumber(rawValue) or 0)

				pcall(function()
					self.Store:SetAsync(tostring(player.UserId), cleanValue)
				end)
			else
				self.LiveProfiles[player] = nil
			end
		end
	end)

	return true
end

function OrderedStore:GetSortedAsync(ascending, pageSize)
	local pages = nil
	pcall(function()
		pages = self.Store:GetSortedAsync(not ascending, pageSize)
	end)
	return pages
end

return OrderedStore