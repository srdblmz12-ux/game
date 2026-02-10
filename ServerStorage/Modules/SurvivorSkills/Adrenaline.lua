local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Adrenaline = {}

--// GENEL AYARLAR
Adrenaline.Name = "Adrenaline"
Adrenaline.Cooldown = 40 

--// SÜRE AYARLARI 
Adrenaline.BoostDuration = 10   
Adrenaline.FatigueDuration = 6  

--// GÖRSEL AYARLAR (İngilizce Açıklama)
Adrenaline.Description = "Sprint faster for a short time, but get tired afterwards."
Adrenaline.Image = "rbxassetid://97754867" 

--// HIZ DEĞERLERİ
local BOOST_AMOUNT = 8      
local FATIGUE_DROP = 12      
local RECOVERY_AMOUNT = 4   

function Adrenaline:Activate(player, gameService)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Eski Zıplama Değerlerini Kaydet
	local oldJumpPower = humanoid.JumpPower
	local oldJumpHeight = humanoid.JumpHeight
	local useJumpPower = humanoid.UseJumpPower

	-- 1. HIZLANMA BAŞLA (+8 Speed)
	humanoid.WalkSpeed = humanoid.WalkSpeed + BOOST_AMOUNT

	-- Zıplamayı %50 Azalt (Koşarken zor zıplasın)
	if useJumpPower then
		humanoid.JumpPower = oldJumpPower * 0.5
	else
		humanoid.JumpHeight = oldJumpHeight * 0.5
	end

	-- 2. HIZLANMA SÜRESİ DOLUNCA (10 Saniye Sonra)
	task.delay(Adrenaline.BoostDuration, function()
		if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then return end

		-- Zıplamayı geri yükle (Koşma bitti)
		if useJumpPower then
			humanoid.JumpPower = oldJumpPower
		else
			humanoid.JumpHeight = oldJumpHeight
		end

		-- Hızlı halden yorgun hale geçiş (-12 Speed)
		humanoid.WalkSpeed = math.max(0, humanoid.WalkSpeed - FATIGUE_DROP)

		-- 3. YORGUNLUK SÜRESİ DOLUNCA (6 Saniye Sonra)
		task.delay(Adrenaline.FatigueDuration, function()
			if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then return end

			-- Normale dönüş (+4 Speed)
			humanoid.WalkSpeed = humanoid.WalkSpeed + RECOVERY_AMOUNT
		end)
	end)
end

return Adrenaline