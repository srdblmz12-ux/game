-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Net = require(Packages:WaitForChild("Net"))

-- MODULE IMPORT
local Services = ServerStorage:WaitForChild("Services")
local GameService = require(Services:WaitForChild("GameService"))

-- Module Definition
local Attack = {}

-- Metadata
Attack.Name = "Attack"
Attack.Cooldown = 3
Attack.Description = "Eats a limb of the target."
Attack.Image = "rbxassetid://0"
Attack.Keybind = Enum.UserInputType.MouseButton1

-- Configs
local LIMB_ORDER = { "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Head" }
local ATTACK_RANGE = 8
local SPHERE_RADIUS = 2.5
local MAX_PENETRATION = 20 

--[[
    GENEL RAYCAST FONKSİYONU
    - Tek bir RaycastParams kullanır (Optimize).
    - CanCollide kapalı objeleri yoksayar (içinden geçer).
    - ANCAK CanCollide kapalı olsa bile bir HUmanoid'e aitse (Target) onu vurur.
    - Takım arkadaşı ve kendisi içinden geçilir.
]]
local function CastAttackRay(Attacker, origin, direction, ignoreList, castType)
	-- 1. Parametreyi döngü dışında oluşturuyoruz.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignoreList

	local castCount = 0

	while castCount < MAX_PENETRATION do
		castCount += 1

		-- Atış Tipi (Sphere veya Normal Ray)
		local result
		if castType == "Sphere" then
			result = workspace:Spherecast(origin, SPHERE_RADIUS, direction, rayParams)
		else
			result = workspace:Raycast(origin, direction, rayParams)
		end

		-- Hiçbir şeye çarpmadıysa bitir
		if not result then return nil end

		local hitPart = result.Instance
		local hitModel = hitPart:FindFirstAncestorOfClass("Model")
		local humanoid = hitModel and hitModel:FindFirstChild("Humanoid")

		local shouldPass = false -- "İçinden geçmeli miyiz?" değişkeni

		-- A) KARAKTER / CANLI KONTROLÜ
		if humanoid and humanoid.Health > 0 then
			-- 1. Kendimiz mi?
			if Attacker.Character and hitModel == Attacker.Character then
				shouldPass = true
			else
				-- 2. Takım Kontrolü (GameService üzerinden)
				local targetPlayer = Players:GetPlayerFromCharacter(hitModel)
				local isTeammate = false

				if targetPlayer then
					local attackerRole = GameService.RunningPlayers[tostring(Attacker.UserId)]
					local targetRole = GameService.RunningPlayers[tostring(targetPlayer.UserId)]

					-- İkisinin de rolü var ve aynıysa -> DOST
					if attackerRole and targetRole and attackerRole == targetRole then
						isTeammate = true
					end
				end

				if isTeammate then
					shouldPass = true -- Dostun içinden geç (arkasındaki düşmanı vurabilmek için)
				else
					-- DÜŞMAN BULUNDU! 
					-- CanCollide kapalı olsa bile Humanoid olduğu için buraya girer ve return eder.
					return hitModel, humanoid, hitPart
				end
			end

			-- B) CANSIZ NESNE KONTROLÜ
		else
			-- Humanoid yoksa burası dekordur, duvardır vs.
			if hitPart.CanCollide == false then
				shouldPass = true -- Fiziksel çarpışması yok, içinden geç.
			elseif hitPart.Transparency >= 1 then 
				shouldPass = true -- Görünmez duvar, içinden geç (isteğe bağlı).
			elseif hitPart.Name == "Handle" then
				shouldPass = true -- Yerdeki eşyalar vs.
			end
		end

		-- KARAR ANI
		if shouldPass then
			-- Listeye ekle ve parametreyi güncelle (Tabloyu yeniden oluşturmuyoruz, sadece refere ediyoruz)
			table.insert(ignoreList, hitPart)
			rayParams.FilterDescendantsInstances = ignoreList
		else
			-- Katı duvar (Canlı değil ve CanCollide açık) -> Raycast biter.
			return nil
		end
	end

	return nil
end

function Attack:Activate(Player, GameServiceRef, MouseHit)
	local Character = Player.Character
	local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")
	local Head = Character and Character:FindFirstChild("Head")
	if not (RootPart and Head) then return end

	-- COOLDOWN
	local now = os.clock()
	local lastAttack = Player:GetAttribute("LastAttackTime") or 0
	if (now - lastAttack) < Attack.Cooldown then return end
	if Player:GetAttribute("IsStunned") then return end

	Player:SetAttribute("LastAttackTime", now)

	-- TARAMA AYARLARI
	local Origin = Head.Position
	local Direction = (MouseHit - Origin).Unit * ATTACK_RANGE
	-- Başlangıçta sadece karakteri yok sayıyoruz
	local IgnoreList = { Character } 

	local HitCharacter, HitHumanoid, HitPart = nil, nil, nil

	-- 1. Adım: Spherecast (Geniş tarama)
	HitCharacter, HitHumanoid, HitPart = CastAttackRay(Player, Origin, Direction, IgnoreList, "Sphere")

	-- 2. Adım: Raycast (Eğer Spherecast bulamazsa, nokta atışı dene)
	if not HitHumanoid then
		-- IgnoreList yukarıda güncellendiği için tekrar kullanabiliriz veya sıfırlayabiliriz.
		-- Genellikle temiz bir Raycast için listeyi sıfırlamak (sadece char kalsın) daha sağlıklıdır:
		HitCharacter, HitHumanoid, HitPart = CastAttackRay(Player, Origin, Direction, {Character}, "Ray")
	end

	-- SONUÇ İŞLEME
	if HitHumanoid then
		-- A) Decoy (Sahte Karakter) Kontrolü
		local isDecoy = HitCharacter:GetAttribute("Decoy") == true
		if isDecoy then
			Net:RemoteEvent("SendNotification"):FireClient(Player, "Fake character eaten! (Stunned)", 10)
			Player:SetAttribute("IsStunned", true)

			local myHum = Character:FindFirstChild("Humanoid")
			if myHum then myHum.WalkSpeed = 2 end

			task.delay(3, function()
				if myHum then myHum.WalkSpeed = 16 end
				if Player then Player:SetAttribute("IsStunned", nil) end
			end)
			return -- Decoy yiyince işlem biter
		end

		-- B) Uzuv Yeme Mantığı
		local limbEaten = false
		for _, limbName in ipairs(LIMB_ORDER) do
			local TargetLimb = HitCharacter:FindFirstChild(limbName)

			-- Uzuv var mı ve daha önce yenmemiş mi?
			if TargetLimb and not TargetLimb:GetAttribute("IsEaten") then

				-- Görsel Efektler
				Net:RemoteEvent("StartFX"):FireAllClients("BloodSplash", TargetLimb)
				Net:RemoteEvent("StartFX"):FireAllClients("Eating", Player, TargetLimb)

				-- Uzuv Özelliklerini Kapat
				TargetLimb.Transparency = 1
				TargetLimb.CanCollide = false
				TargetLimb:SetAttribute("IsEaten", true)

				-- Hasar Verme
				if limbName == "Head" then
					HitHumanoid.Health = 0
					Net:RemoteEvent("SendNotification"):FireClient(Player, "DEVOUR!", 3)
				else
					HitHumanoid:TakeDamage(10)
					Net:RemoteEvent("SendNotification"):FireClient(Player, "Limb Eaten!", 2)
				end

				limbEaten = true

				-- Bacak Kontrolü (Sürünme Modu)
				local leftLeg = HitCharacter:FindFirstChild("Left Leg")
				local rightLeg = HitCharacter:FindFirstChild("Right Leg")
				if leftLeg and rightLeg and leftLeg:GetAttribute("IsEaten") and rightLeg:GetAttribute("IsEaten") then
					HitHumanoid.HipHeight = -2 -- Karakteri yere yapıştır
				end

				break -- Sadece 1 uzuv ye ve döngüden çık
			end
		end

		-- C) Uzuv bulunamadıysa ama gövdeye vurduysa (Düz Hasar)
		if not limbEaten and HitHumanoid.Health > 0 then
			--[[
				somehow this #### happened, this game is garbage dude
			]]
			HitHumanoid:TakeDamage(25)
			Net:RemoteEvent("SendNotification"):FireClient(Player, "Flesh Ripped!", 1)
		end
	end
end

return Attack