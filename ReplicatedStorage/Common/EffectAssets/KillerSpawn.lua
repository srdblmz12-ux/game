-- Services
local Workspace = game:GetService("Workspace")

-- Variables
local FX = script:WaitForChild("FX")
local BloodPart = script:WaitForChild("BloodPart")

-- Module
local BloodSplash = {}

function BloodSplash:Activate(Trove, TargetInstance)
	if not TargetInstance then return end

	-- 1. ANA EFEKT (Ses ve Partikül)
	local NewFX = FX:Clone()

	-- KONUMLANDIRMA MANTIĞI
	if TargetInstance:IsA("Motor6D") then
		-- Motor6D ise Part0'a (Torso tarafına) ekle
		-- C0 ofsetini kullanarak tam eklem noktasına yerleştir
		NewFX.Parent = TargetInstance.Part0
		NewFX.CFrame = TargetInstance.C0
	elseif TargetInstance:IsA("BasePart") or TargetInstance:IsA("Attachment") then
		-- Normal Part veya Attachment ise direkt içine at
		NewFX.Parent = TargetInstance
		-- Rastgele bir açı ver (sadece düz partlar için)
		NewFX.CFrame = CFrame.Angles(math.rad(math.random(0,360)), math.rad(math.random(0,360)), 0)
	else
		-- Geçersiz hedefse temizle ve çık
		NewFX:Destroy()
		return
	end

	Trove:Add(NewFX)

	-- Partikül ve Sesleri Çalıştır
	for _, child in ipairs(NewFX:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			child:Emit(child:GetAttribute("EmitCount") or 20)
		elseif child:IsA("Sound") then
			child.PlaybackSpeed = math.random(90, 110) / 100
			child:Play()
		end
	end

	-- 2. KAN PARÇALARI (Yere Dökülenler)
	if BloodPart then
		-- Referans noktamız artık doğru konumlanmış Attachment'ın dünya konumu
		local originCF = NewFX.WorldCFrame

		task.spawn(function() -- Döngüyü ana akışı kitlememesi için spawn içine alabiliriz
			for i = 1, 15 do
				-- Eğer Trove temizlendiyse döngüyü durdur (oyuncu reset atarsa hata vermesin)
				if not NewFX.Parent then break end 

				local Drop = BloodPart:Clone()
				Drop.Name = "BloodDrop"
				Drop.Parent = Workspace 

				Drop.Anchored = false
				Drop.CanCollide = true
				Drop.Massless = true

				-- Başlangıç Konumu: Attachment'ın olduğu nokta + ufak sapma
				local offset = Vector3.new(math.random(-10, 10)/10, math.random(-10, 10)/10, math.random(-10, 10)/10)
				Drop.CFrame = originCF + offset

				local scale = math.random(50, 120) / 100
				Drop.Size = Drop.Size * scale

				Trove:Add(Drop)
				task.wait(0.08)
			end
		end)
	end

	-- Temizlik (Opsiyonel: Eğer Controller Trove'u temizliyorsa buraya gerek kalmayabilir)
	task.delay(5, function()
		Trove:Destroy()
	end)
end

return BloodSplash