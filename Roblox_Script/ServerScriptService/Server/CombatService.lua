-- ============================================================
--  CombatService.lua (Script / ServerScript) — VERSI FINAL
--  ServerScriptService > Server
--
--  Menangani:
--  - Basic Attack (M1) dengan Combo 4-hit
--  - Skill Q/E/R per karakter
--  - VFX, animasi, audio melalui EffectService
--  - Destructible environment trigger
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local Shared         = ReplicatedStorage:WaitForChild("Shared")
local SkillData      = require(Shared:WaitForChild("SkillData"))
local GameConfig     = require(Shared:WaitForChild("GameConfig"))
local EffectService  = require(Shared:WaitForChild("EffectService"))

local CombatAction = Shared:WaitForChild("CombatAction")

local Destructibles = workspace:WaitForChild("Destructibles")

-- ============================================================
-- PETA DAMAGE LINGKUNGAN (ENVIRONMENT DAMAGE)
-- Max HP Objek = 300
-- ============================================================
local ENV_DAMAGE = {
	Yuji   = { Q = 100, E = 150, R = 100 },
	Gojo   = { Q = 150, E = 150, R = 300 },
	Sukuna = { Q = 150, E = 300, R = 300 },
	M1     = 0 -- Basic attack tidak merusak objek
}

-- ============================================================
--  COOLDOWN TRACKER
-- ============================================================
local cooldowns = {}

local function getCooldown(player, skillKey)
	if not cooldowns[player] then cooldowns[player] = {} end
	return cooldowns[player][skillKey] or 0
end

local function setCooldown(player, skillKey)
	if not cooldowns[player] then cooldowns[player] = {} end
	cooldowns[player][skillKey] = tick()
end

local function isOnCooldown(player, skillKey, cooldownTime)
	return (tick() - getCooldown(player, skillKey)) < cooldownTime
end

-- ============================================================
--  COMBO TRACKER — khusus Basic Attack (M1)
-- ============================================================
local comboState = {}

local function getComboState(player)
	if not comboState[player] then
		comboState[player] = {hitIndex = 0, lastHitTime = 0}
	end
	return comboState[player]
end

local function getNextComboHit(player)
	local state    = getComboState(player)
	local resetGap = SkillData.BasicAttack.comboResetGap or 0.7
	local maxHits  = SkillData.BasicAttack.comboCount or 4

	local now = tick()
	local gap = now - state.lastHitTime

	if gap > resetGap then
		state.hitIndex = 1
	else
		state.hitIndex = state.hitIndex + 1
		if state.hitIndex > maxHits then
			state.hitIndex = 1
		end
	end

	state.lastHitTime = now
	return state.hitIndex
end

-- ============================================================
--  FUNGSI: lockCombat (Mengunci Gerakan & Skill Lain)
-- ============================================================
local isCasting = {}

local function lockCombat(player, character, duration)
	isCasting[player] = true

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	-- Lepaskan kunci setelah durasi selesai
	task.delay(duration, function()
		isCasting[player] = false
		if humanoid and humanoid.Parent and humanoid.Health > 0 then
			humanoid.WalkSpeed = 16 -- Kembalikan ke normal (Bisa disesuaikan config)
			humanoid.JumpPower = 50
		end
	end)
end

-- ============================================================
--  FUNGSI: ApplyImmunity
--  Memberikan status kebal sementara kepada karakter pemain.
--
--  Cara kerja:
--  1. Set attribute "IsImmune" = true pada karakter
--  2. EnemyAI baca attribute ini di doAttack() sebelum kurangi HP
--  3. Setelah `duration` detik, attribute dikembalikan ke false
--
--  Dipanggil otomatis saat pemain menggunakan skill Q/E/R.
--  Bisa juga dipanggil manual dari script lain:
--    CombatService.ApplyImmunity(character, 1.5)
--
--  Catatan desain (sesuai permintaan):
--  - Musuh TETAP mengejar dan menyerang (tidak idle)
--  - Hanya kalkulasi pengurangan HP yang dibatalkan
--  - Cooldown serangan musuh tetap aktif saat kebal
-- ============================================================
local CombatService = {}  -- tabel publik agar fungsi bisa diakses script lain

function CombatService.ApplyImmunity(character, duration)
	if not character or not character.Parent then return end
	if not duration or duration <= 0 then return end

	-- Cek apakah sudah kebal (skill sebelumnya belum selesai)
	-- Kalau sudah kebal, perpanjang durasi (ambil yang lebih lama)
	local currentEndTime = character:GetAttribute("ImmunityEndTime") or 0
	local newEndTime     = tick() + duration

	if newEndTime <= currentEndTime then
		-- Immunity yang ada sudah lebih lama, tidak perlu update
		return
	end

	-- Set kebal
	character:SetAttribute("IsImmune", true)
	character:SetAttribute("ImmunityEndTime", newEndTime)

	print("[CombatService] I-Frame aktif untuk " .. character.Name
		.. " selama " .. duration .. " detik")

	task.delay(duration, function()
		if not character or not character.Parent then return end

		-- Cek apakah sudah ada immunity baru yang lebih lama
		-- Kalau iya, jangan hapus (akan dihapus oleh delay yang lebih lama nanti)
		local endTime = character:GetAttribute("ImmunityEndTime") or 0
		if tick() < endTime then return end

		-- Waktu kebal sudah habis, kembalikan ke normal
		character:SetAttribute("IsImmune", false)
		character:SetAttribute("ImmunityEndTime", nil)

		print("[CombatService] I-Frame berakhir untuk " .. character.Name)
	end)
end

-- ============================================================
--  FUNGSI: applyKnockback
-- ============================================================
local function applyKnockback(character, direction, force)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local bv    = Instance.new("BodyVelocity")
	bv.Velocity = direction * force
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.Parent   = hrp

	Debris:AddItem(bv, 0.2)
end

-- ============================================================
--  FUNGSI: damageCharacter
-- ============================================================
local function damageCharacter(character, damage)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	humanoid.Health = math.max(0, humanoid.Health - damage)
	return true
end

-- ============================================================
-- FUNGSI: damageEnvironment (Sistem HP & Retakan Objek)
-- ============================================================
local function damageEnvironment(hitboxPosition, radius, envDamage)
	if envDamage <= 0 then return end -- Abaikan jika M1 (damage 0)

	local destructibles = workspace:FindFirstChild("Destructibles")
	if not destructibles then return end

	for _, object in ipairs(destructibles:GetChildren()) do
		-- Cari titik pusat objek (PrimaryPart)
		local root = object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart")
		if root then
			local distance = (root.Position - hitboxPosition).Magnitude

			-- Jika objek masuk dalam radius ledakan jurus
			if distance <= radius then
				-- 1. Inisialisasi HP jika belum punya
				local currentHP = object:GetAttribute("HP")
				if not currentHP then
					currentHP = 300 -- Max HP bawaan
					object:SetAttribute("MaxHP", 300)
				end

				-- 2. Kurangi HP objek
				currentHP = currentHP - envDamage
				object:SetAttribute("HP", currentHP)

				-- 3. Cek kondisi objek
				if currentHP <= 0 then
					-- HANCUR TOTAL: Lepas anchor agar berjatuhan
					for _, desc in ipairs(object:GetDescendants()) do
						if desc:IsA("BasePart") then
							desc.Anchored = false
							-- Berikan sedikit dorongan fisik agar terlempar berantakan
							desc.AssemblyLinearVelocity = (desc.Position - hitboxPosition).Unit * 40
						end
					end
					-- Bersihkan puing-puing setelah 5 detik agar tidak lag
					task.delay(5, function()
						if object and object.Parent then object:Destroy() end
					end)
				else
					-- RETAK/RUSAK: Ubah warna menjadi lebih gelap dan ubah teksturnya
					for _, desc in ipairs(object:GetDescendants()) do
						if desc:IsA("BasePart") then
							-- Menggunakan material Slate untuk efek kasar/retak
							desc.Material = Enum.Material.Slate 
							-- Menggelapkan warna objek sebesar 30% dari warna aslinya
							desc.Color = Color3.new(desc.Color.R * 0.7, desc.Color.G * 0.7, desc.Color.B * 0.7)
						end
					end
				end
			end
		end
	end
end

-- ============================================================
--  FUNGSI: findEnemiesInRadius
-- ============================================================
local function findEnemiesInRadius(position, radius)
	local found = {}
	local EnemyFolder = workspace:FindFirstChild("ActiveEnemies")
	if not EnemyFolder then return found end

	for _, enemy in ipairs(EnemyFolder:GetChildren()) do
		local hrp = enemy:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = (hrp.Position - position).Magnitude
			if dist <= radius then
				table.insert(found, enemy)
			end
		end
	end
	return found
end

-- ============================================================
--  FUNGSI: executeSkill (REVISI FINAL DESTRUCTIBLE + DEBUG)
-- ============================================================
local function executeSkill(player, character, skillInfo, skillKey)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local origin    = hrp.Position
	local lookDir   = hrp.CFrame.LookVector
	local skillType = skillInfo.skillType
	local firstHitPosition = nil

	-- AMBIL NAMA KARAKTER & HITUNG DAMAGE LINGKUNGAN
	local charName  = character:GetAttribute("CharacterName") or character.Name
	local envDamage = ENV_DAMAGE[charName] and ENV_DAMAGE[charName][skillKey] or 0

	-- --------------------------------------------------------
	--  MELEE SINGLE
	-- --------------------------------------------------------
	if skillType == "melee_single" then
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {character}
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = workspace:Raycast(
			origin,
			lookDir * (skillInfo.range or 7),
			raycastParams
		)

		if result and result.Instance then
			local hitChar = result.Instance.Parent
			local hitHumanoid = hitChar:FindFirstChildOfClass("Humanoid")

			if hitHumanoid and hitChar:GetAttribute("IsEnemy") then
				damageCharacter(hitChar, skillInfo.damage or 15)
				firstHitPosition = result.Instance.Position

				if skillInfo.knockback then
					applyKnockback(hitChar, lookDir, skillInfo.knockback)
				end

				if skillInfo.stunTime then
					local stunDuration = skillInfo.stunTime
					local hitCharModel = result.Instance.Parent

					if hitCharModel:GetAttribute("IsEnemy") then
						-- Set StunDuration → EnemyAI akan mendeteksinya secara otomatis
						hitCharModel:SetAttribute("StunDuration", stunDuration)
						print("[CombatService] Stun trigger dikirim ke " .. hitCharModel.Name .. " selama " .. stunDuration .. "s")
					else
						-- Fallback jika musuhnya bukan FSM
						hitHumanoid.WalkSpeed = 0
						task.delay(stunDuration, function()
							if hitHumanoid and hitHumanoid.Parent then
								hitHumanoid.WalkSpeed = 12
							end
						end)
					end
				end

				print("[CombatService] " .. (skillInfo.name or "Attack") ..
					" hit: " .. hitChar.Name ..
					" damage: " .. (skillInfo.damage or 15))
			end
		end

		-- PERBAIKAN YUJI: Perbesar radius ledakan lingkungan agar Black Flash pasti kena objek!
		local punchCenter = origin + (lookDir * ((skillInfo.range or 7) * 0.5))
		damageEnvironment(punchCenter, 30, envDamage) -- Radius diperlebar dari 6 menjadi 20

		-- --------------------------------------------------------
		--  MELEE AOE
		-- --------------------------------------------------------
	elseif skillType == "melee_aoe" then
		local radius  = skillInfo.radius or 10
		local enemies = findEnemiesInRadius(origin, radius)

		for _, enemy in ipairs(enemies) do
			local hrpEnemy = enemy:FindFirstChild("HumanoidRootPart")
			if hrpEnemy then
				damageCharacter(enemy, skillInfo.damage or 35)

				if not firstHitPosition then
					firstHitPosition = hrpEnemy.Position
				end

				if skillInfo.knockback then
					local dir = (hrpEnemy.Position - origin).Unit
					applyKnockback(enemy, dir, skillInfo.knockback)
				end
			end
		end

		-- PERBAIKAN: Hapus syarat 'if skillInfo.destroyPillars', biarkan ENV_DAMAGE yang memfilter
		damageEnvironment(origin, radius, envDamage)

		print("[CombatService] " .. (skillInfo.name or "AoE") ..
			" hit " .. #enemies .. " musuh")

		-- --------------------------------------------------------
		--  BEAM
		-- --------------------------------------------------------
	elseif skillType == "beam" then
		local range = skillInfo.range or 60
		local EnemyFolder = workspace:FindFirstChild("ActiveEnemies")

		if EnemyFolder then
			for _, enemy in ipairs(EnemyFolder:GetChildren()) do
				local hrpEnemy = enemy:FindFirstChild("HumanoidRootPart")
				if hrpEnemy then
					local toEnemy = hrpEnemy.Position - origin
					local dot     = toEnemy:Dot(lookDir)
					local dist    = toEnemy.Magnitude

					if dot > 0 and dot < range then
						local perpDist = (toEnemy - lookDir * dot).Magnitude
						if perpDist < 15 then -- Radius hantaman beam sudah diperlebar
							damageCharacter(enemy, skillInfo.damage or 50)

							if not firstHitPosition then
								firstHitPosition = hrpEnemy.Position
							end

							if skillInfo.knockback then
								applyKnockback(enemy, lookDir, skillInfo.knockback)
							end
							print("[CombatService] Beam hit: " .. enemy.Name)
						end
					end
				end
			end
		end

		-- PERBAIKAN: Hapus syarat 'if skillInfo.destroyPillars', biarkan ENV_DAMAGE yang memfilter
		local beamCenter = origin + (lookDir * (range * 0.5))
		damageEnvironment(beamCenter, range * 0.5, envDamage)

		-- --------------------------------------------------------
		--  PULL AOE
		-- --------------------------------------------------------
	elseif skillType == "pull_aoe" then
		local radius  = skillInfo.radius or 30
		local enemies = findEnemiesInRadius(origin, radius)

		for _, enemy in ipairs(enemies) do
			local hrpEnemy = enemy:FindFirstChild("HumanoidRootPart")
			if hrpEnemy then
				damageCharacter(enemy, skillInfo.damage or 20)

				local dir = (origin - hrpEnemy.Position).Unit
				applyKnockback(enemy, dir, skillInfo.pullForce or 80)

				if not firstHitPosition then
					firstHitPosition = hrpEnemy.Position
				end
			end
		end

		damageEnvironment(origin, radius, envDamage)
		print("[CombatService] Lapse Blue menarik " .. #enemies .. " musuh")

		-- --------------------------------------------------------
		--  PUSH AOE
		-- --------------------------------------------------------
	elseif skillType == "push_aoe" then
		local radius  = skillInfo.radius or 25
		local enemies = findEnemiesInRadius(origin, radius)

		for _, enemy in ipairs(enemies) do
			local hrpEnemy = enemy:FindFirstChild("HumanoidRootPart")
			if hrpEnemy then
				damageCharacter(enemy, skillInfo.damage or 30)

				if not firstHitPosition then
					firstHitPosition = hrpEnemy.Position
				end

				local dir = (hrpEnemy.Position - origin).Unit
				applyKnockback(enemy, dir, skillInfo.pushForce or 120)
			end
		end

		damageEnvironment(origin, radius, envDamage)
		print("[CombatService] Reversal Red mendorong " .. #enemies .. " musuh")
	end

	return firstHitPosition
end

-- ============================================================
--  LISTENER UTAMA
-- ============================================================
CombatAction.OnServerEvent:Connect(function(player, skillKey, charName)

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- ----------------------------------------------------------
	--  BASIC ATTACK (M1) — Combo System
	-- ----------------------------------------------------------
	if skillKey == "M1" then
		if isCasting[player] then return end
		
		local basicData = SkillData.BasicAttack

		if isOnCooldown(player, "M1_click", basicData.cooldown) then
			return
		end
		setCooldown(player, "M1_click")

		local hitIndex = getNextComboHit(player)
		local animID   = basicData.animID[hitIndex]

		print("[CombatService] " .. player.Name .. " M1 combo hit: " .. hitIndex .. "/" .. #basicData.animID)

		EffectService.playAnimation(character, animID)

		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {character}
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = workspace:Raycast(
			hrp.Position,
			hrp.CFrame.LookVector * (basicData.range or 7),
			raycastParams
		)

		local targetPosition = nil
		local damage = basicData.damage
		if hitIndex == (basicData.comboCount or 4) then
			damage = damage * 1.5
		end

		if result and result.Instance then
			local hitChar = result.Instance.Parent
			local hitHumanoid = hitChar:FindFirstChildOfClass("Humanoid")

			if hitHumanoid and hitChar:GetAttribute("IsEnemy") then
				damageCharacter(hitChar, damage)
				applyKnockback(hitChar, hrp.CFrame.LookVector, 15)

				local hitHrp = hitChar:FindFirstChild("HumanoidRootPart")
				if hitHrp then
					targetPosition = hitHrp.Position
				end

				print("[CombatService] M1 hit " .. hitIndex .. " kena: " .. hitChar.Name .. " dmg: " .. damage)
			end
		end

		EffectService.playSkillEffects(
			character,
			targetPosition,
			basicData.vfxName,
			basicData.sfxID,
			basicData.voiceID
		)

		return
	end

	-- ----------------------------------------------------------
	--  SKILL Q / E / R — dengan Timing & Proyektil
	-- ----------------------------------------------------------
	local validChars = {Yuji = true, Gojo = true, Sukuna = true}
	if not validChars[charName] then
		warn("[CombatService] Karakter tidak valid: " .. tostring(charName))
		return
	end

	local skillInfo = SkillData[charName] and SkillData[charName][skillKey]
	if not skillInfo then
		warn("[CombatService] Skill tidak ditemukan: " .. charName .. "/" .. tostring(skillKey))
		return
	end

	local cdKey = charName .. "_" .. skillKey
	if isOnCooldown(player, cdKey, skillInfo.cooldown) then return end
	if isCasting[player] then return end
	
	setCooldown(player, cdKey)
	
	local lockDuration = 1.0 -- Default durasi kaku untuk skill standar
	if charName == "Gojo" then
		if skillKey == "Q" then lockDuration = 1.0
		elseif skillKey == "E" then lockDuration = 1.5
		elseif skillKey == "R" then lockDuration = 3.5
		end
	elseif charName == "Sukuna" and skillKey == "R" then
		lockDuration = 10.5 -- Mengunci Sukuna selama durasi Fire Arrow
	end

	-- Kunci pergerakan pemain sekarang!
	lockCombat(player, character, lockDuration)

	-- Aktifkan I-Frames selama durasi yang sama dengan lock combat
	-- Pemain kebal terhadap damage musuh selama animasi skill berjalan
	CombatService.ApplyImmunity(character, lockDuration)
	
	-- Putar animasi SEGERA (tidak ada delay untuk animasi)
	EffectService.playAnimation(character, skillInfo.animID)

	-- ------------------------------------------------------
	--  ROUTING TIMING PER SKILL
	--  Setiap skill yang butuh timing khusus dijalankan
	--  di thread terpisah (task.spawn) agar tidak nge-block
	--  listener utama untuk pemain lain.
	-- ------------------------------------------------------

	    -- GOJO Q — Lapse Blue: tanpa delay, aura berputar
	if charName == "Gojo" and skillKey == "Q" then
		task.spawn(function()
			local hitTargetPosition = executeSkill(player, character, skillInfo, skillKey)
			EffectService.spinAura(character, skillInfo.vfxName, 180, 1.5)
			EffectService.playSkillEffects(character, hitTargetPosition, nil, skillInfo.sfxID, skillInfo.voiceID)
		end)

		-- GOJO E — Reversal Red: Charge 1.2 detik, lalu tembak
	elseif charName == "Gojo" and skillKey == "E" then
		task.spawn(function()
			-- 1. MAINKAN SUARA & VOICE SEKARANG JUGA (Sebelum delay)
			EffectService.playSkillEffects(character, nil, nil, skillInfo.sfxID, skillInfo.voiceID)

			-- Munculkan VFX statis selama waktu charge
			EffectService.spawnChargeVFX(character, skillInfo.vfxName, 1.2)

			task.wait(1.2)
			if not character or not character.Parent then return end
			if not character:FindFirstChild("HumanoidRootPart") then return end

			local hitTargetPosition = executeSkill(player, character, skillInfo, skillKey)
			EffectService.fireProjectile(character, skillInfo.vfxName, 90, 0.7)
			-- Suara diposisikan nil agar tidak double play
			EffectService.playSkillEffects(character, hitTargetPosition, nil, skillInfo.sfxExplosion, nil)
		end)

		-- GOJO R — Hollow Purple: Charge 3 detik, lalu tembak
	elseif charName == "Gojo" and skillKey == "R" then
		task.spawn(function()
			-- 1. MAINKAN SUARA & VOICE SEKARANG JUGA (Sebelum delay)
			EffectService.playSkillEffects(character, nil, nil, skillInfo.sfxID, skillInfo.voiceID)

			-- Munculkan VFX statis menahan energi selama 3 detik
			EffectService.spawnChargeVFX(character, skillInfo.vfxName, 3)

			task.wait(3)
			if not character or not character.Parent then return end
			if not character:FindFirstChild("HumanoidRootPart") then return end

			local hitTargetPosition = executeSkill(player, character, skillInfo, skillKey)
			EffectService.fireProjectile(character, skillInfo.vfxName, 100, 0.8)
			-- Suara diposisikan nil agar tidak double play
			EffectService.playSkillEffects(character, hitTargetPosition, nil, skillInfo.sfxExplosion, nil)
		end)
	
		-- SUKUNA E — Cleave: Double VFX tanpa extra damage
	elseif charName == "Sukuna" and skillKey == "E" then
		task.spawn(function()
			-- Kunci posisi Sukuna SEBELUM dia sempat bergerak
			local hrp = character:FindFirstChild("HumanoidRootPart")
			local staticTargetPos = nil

			local hitTargetPosition = executeSkill(player, character, skillInfo, skillKey)

			-- Jika kena musuh, kunci di posisi musuh. 
			-- Jika meleset, kunci titik koordinat tepat 10 stud di depan Sukuna saat ini.
			if hitTargetPosition then
				staticTargetPos = hitTargetPosition
			elseif hrp then
				staticTargetPos = (hrp.CFrame * CFrame.new(0, 0, -10)).Position
			end

			-- 1. Mainkan VFX Pertama di posisi statis yang sudah dikunci
			EffectService.playSkillEffects(character, staticTargetPos, skillInfo.vfxName, skillInfo.sfxID, skillInfo.voiceID)

			-- 2. Beri jeda sejenak (sesuaikan angkanya dengan keinginanmu)
			task.wait(2.0)
			if not character or not character.Parent then return end

			-- 3. Munculkan VFX Cleave KEDUA persis di titik statis yang sama
			EffectService.playSkillEffects(character, staticTargetPos, skillInfo.vfxName, nil, nil)
		end)

		-- SUKUNA R — Fire Arrow: Tunggu 6 detik, Charge 4 detik, Tembak!
	elseif charName == "Sukuna" and skillKey == "R" then
		task.spawn(function()
			-- Detik 0: Mainkan suara Voice saja (contoh: "Fuga!")
			EffectService.playSkillEffects(character, nil, nil, nil, skillInfo.voiceID)

			-- FASE 1: Animasi persiapan awal
			task.wait(6)
			if not character or not character.Parent or not character:FindFirstChild("HumanoidRootPart") then return end

			-- FASE 2: Munculkan VFX api di busur & MAINKAN SFX CHARGE
			EffectService.spawnChargeVFX(character, skillInfo.vfxName, 4)
			EffectService.playSkillEffects(character, nil, nil, skillInfo.sfxCharge, nil)
			print("[CombatService] Sukuna Fire Arrow — Munculkan Api (Detik 6)")

			-- Tunggu masa charge selesai
			task.wait(4)
			if not character or not character.Parent or not character:FindFirstChild("HumanoidRootPart") then return end

			-- FASE 3: Eksekusi damage, lepaskan proyektil, & MAINKAN SFX SHOOT
			local hitTargetPosition = executeSkill(player, character, skillInfo, skillKey)
			EffectService.fireProjectile(character, skillInfo.vfxName, 90, 0.6)
			EffectService.playSkillEffects(character, hitTargetPosition, nil, skillInfo.sfxShoot, nil)
			print("[CombatService] Sukuna Fire Arrow — Ditembakkan! (Detik 10)")
		end)

		-- ------------------------------------------------------
		--  SEMUA SKILL LAIN — tanpa delay khusus, eksekusi normal
		--  (Yuji Q/E/R, Sukuna Q/E, semua skill yang tidak di-list di atas)
		-- ------------------------------------------------------
	else
		local hitTargetPosition = executeSkill(player, character, skillInfo, skillKey)
		EffectService.playSkillEffects(
			character,
			hitTargetPosition,
			skillInfo.vfxName,
			skillInfo.sfxID,
			skillInfo.voiceID
		)
	end
end)

-- ============================================================
--  CLEANUP
-- ============================================================
Players.PlayerRemoving:Connect(function(player)
	cooldowns[player]  = nil
	comboState[player] = nil
	isCasting[player]  = nil
end)

print("[CombatService] ✓ Combat system aktif.")