local Regenerate = {}

Regenerate.Name = "Regenerate"
Regenerate.Cooldown = 60
Regenerate.Duration = 1

-- Description: Kısa ve net İngilizce açıklama.
Regenerate.Description = "Regrow lost limbs and recover health."
Regenerate.Image = "rbxassetid://3236846805" 

local HEAL_AMOUNT = 2 

local function RestoreLimb(part)
	if not part then return end
	part:SetAttribute("IsEaten", nil)
	part.Transparency = 0
	part.CanCollide = false -- R6'da uzuvlar genellikle CanCollide kapalıdır

	-- Texture/Decal varsa onları da görünür yap
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") then 
			child.Transparency = 0 
		end
	end
end

local function updateLegState(humanoid, character)
	local lLeg = character:FindFirstChild("Left Leg")
	local rLeg = character:FindFirstChild("Right Leg")

	-- Eğer en az bir bacak sağlamsa (yenmemişse), ayağa kalk (HipHeight 0)
	local leftOk = lLeg and not lLeg:GetAttribute("IsEaten")
	local rightOk = rLeg and not rLeg:GetAttribute("IsEaten")

	if leftOk or rightOk then
		humanoid.HipHeight = 0
	else
		-- İkisi de yoksa sürünmeye devam et
		humanoid.HipHeight = -2
	end
end

function Regenerate:Activate(player, gameService)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local eatenLegs = {}
	local eatenArms = {}

	-- Yenmiş uzuvları tespit et
	for _, name in ipairs({"Left Leg", "Right Leg", "Left Arm", "Right Arm"}) do
		local part = character:FindFirstChild(name)
		if part and part:GetAttribute("IsEaten") then
			if string.find(name, "Leg") then 
				table.insert(eatenLegs, part)
			else 
				table.insert(eatenArms, part) 
			end
		end
	end

	-- Eğer iyileşecek bir şey yoksa boşa harcama (İsteğe bağlı, şu an harcıyor)
	-- if #eatenLegs == 0 and #eatenArms == 0 and humanoid.Health >= humanoid.MaxHealth then return end

	local healedThisTime = 0

	-- ÖNCELİK 1: Bacaklar (Yürüyebilmek için)
	for i = 1, #eatenLegs do
		if healedThisTime < HEAL_AMOUNT then
			RestoreLimb(eatenLegs[i])
			healedThisTime += 1
		end
	end

	-- ÖNCELİK 2: Kollar (Bacaklardan sonra hak kalırsa)
	if healedThisTime < HEAL_AMOUNT then
		for i = 1, #eatenArms do
			if healedThisTime < HEAL_AMOUNT then
				RestoreLimb(eatenArms[i])
				healedThisTime += 1
			end
		end
	end

	-- Attribute güncelleme
	local currentLimbsEaten = character:GetAttribute("LimbsEaten") or 0
	character:SetAttribute("LimbsEaten", math.max(0, currentLimbsEaten - healedThisTime))

	-- Boy ayarını güncelle
	updateLegState(humanoid, character)

	-- Can yenile (+20 HP)
	humanoid.Health = math.min(humanoid.Health + 20, humanoid.MaxHealth)
end

return Regenerate