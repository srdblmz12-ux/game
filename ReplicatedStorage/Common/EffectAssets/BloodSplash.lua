-- Services
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

-- Variables
local BloodPart = script:WaitForChild("BloodPart")
local BellSound = SoundService:WaitForChild("Bell")

-- Module
local KillerSpawn = {}

function KillerSpawn:Activate(Trove, Killer : Player)
	BellSound:Play()

	local character = Killer.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- 1. Create Explosion Effect
	local explosion = Instance.new("Explosion")
	explosion.Position = hrp.Position
	explosion.BlastPressure = 0 -- Prevents physics knockback
	explosion.DestroyJointRadiusPercent = 0 -- Prevents damage/killing
	explosion.Parent = workspace

	-- 2. Create Blood Parts (13-24)
	local partCount = math.random(13, 24)

	for i = 1, partCount do
		local clone = BloodPart:Clone()
		clone.CFrame = hrp.CFrame
		clone.Parent = workspace

		-- 3. Spew parts using random velocity
		local randomVelocity = Vector3.new(
			math.random(-15, 15), -- Random X spread
			math.random(30, 60),  -- High Upward force
			math.random(-15, 15)  -- Random Z spread
		)
		clone.AssemblyLinearVelocity = randomVelocity

		-- Cleanup part after 5 seconds
		Debris:AddItem(clone, 5)
	end
end

return KillerSpawn