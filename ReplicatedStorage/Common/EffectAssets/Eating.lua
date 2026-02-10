local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Variables
local BloodPart = script:WaitForChild("BloodPart")
local SkinPart = script:WaitForChild("SkinPart")

-- Module
local Eating = {}

function Eating:Activate(Trove, Killer : Player, BodyPart : BasePart)
	local KillerCharacter = Killer.Character
	if (not KillerCharacter) then return end

	local Head = KillerCharacter:FindFirstChild("Head")
	if not Head then return end

	-- 1. SESİ ÇALMA
	local sound = Head:FindFirstChildOfClass("Sound")
	if sound then
		sound:Play()
	end

	-- 2. YEME GÖRSELLEŞTİRME (WELD İLE)
	local foodLimb = BodyPart:Clone()

	-- Görünürlük ve Fizik Ayarları
	foodLimb.Transparency = 0 
	foodLimb.LocalTransparencyModifier = 0
	foodLimb.CanCollide = false
	foodLimb.Anchored = false -- DİKKAT: Weld çalışması için false olmalı!

	-- Parçayı oluşturuyoruz
	foodLimb.Parent = BodyPart.Parent 

	-- WELD OLUŞTURMA
	-- Weld, iki parçayı birbirine yapıştırır. C0 değeri ile aralarındaki mesafeyi ayarlarız.
	local weld = Instance.new("ManualWeld")
	weld.Name = "EatingWeld"
	weld.Part0 = Head -- Kime yapışacak? (Katil Kafası)
	weld.Part1 = foodLimb -- Kim yapışacak? (Yenen Parça)

	-- Başlangıç Ofseti: Kafanın 2.5 birim önünde ve 90 derece dönmüş
	-- C0, Part1'in Part0'a göre nerede duracağını belirler.
	weld.C0 = CFrame.new(0, 0, -2.5) * CFrame.Angles(math.rad(90), 0, 0)

	weld.Parent = foodLimb

	-- TWEEN İLE WELD'İ HAREKET ETTİRME
	-- Artık parçayı değil, Weld'in C0 değerini (ofsetini) tweenliyoruz.
	-- Hedef: Kafanın merkezi (veya ağız kısmı)
	local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	-- Hedef C0: (0, -0.2, -0.5) diyerek tam ağız içine sokuyoruz ve açıyı değiştiriyoruz
	local targetC0 = CFrame.new(0, -0.2, -0.5) * CFrame.Angles(math.rad(120), 0, 0)

	local tween = TweenService:Create(weld, tweenInfo, {C0 = targetC0})
	tween:Play()

	-- 3. EFEKTLER
	task.spawn(function()
		local startTime = tick()
		local duration = 0.8 

		while tick() - startTime < duration do
			if not Head then break end -- Kafa yoksa döngüyü kır

			-- SkinPart (Deri)
			local skinClone = SkinPart:Clone()
			skinClone.BrickColor = BodyPart.BrickColor
			-- Efektler Head.CFrame'e göre çıkmaya devam etsin (kafadan çıkıyor gibi)
			skinClone.CFrame = Head.CFrame * CFrame.new(0, -0.5, -1.5) 
			skinClone.Anchored = false
			skinClone.CanCollide = true
			skinClone.Parent = workspace 

			local randomVelocity = Vector3.new(math.random(-10, 10), math.random(5, 15), math.random(-10, 10))
			skinClone.AssemblyLinearVelocity = (Head.CFrame.LookVector * 15) + randomVelocity

			Debris:AddItem(skinClone, 3)

			-- BloodPart (Kan)
			local bloodClone = BloodPart:Clone()
			bloodClone.CFrame = Head.CFrame * CFrame.new(0, -0.5, -1.5)
			bloodClone.Anchored = false
			bloodClone.CanCollide = false
			bloodClone.Parent = workspace

			local bloodVelocity = Vector3.new(math.random(-5, 5), math.random(0, 10), math.random(-5, 5))
			bloodClone.AssemblyLinearVelocity = (Head.CFrame.LookVector * 10) + bloodVelocity

			Debris:AddItem(bloodClone, 3)

			task.wait(0.05)
		end

		-- İşlem bitince yenen parçayı sil
		if foodLimb then foodLimb:Destroy() end
	end)
end

return Eating