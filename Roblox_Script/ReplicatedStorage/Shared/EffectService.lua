-- ============================================================
--  EffectService.lua (ModuleScript) — VERSI 3
--  ReplicatedStorage > Shared
--
--  Tambahan v3: Proyektil yang bergerak (TweenService).
--  VFX proyektil sekarang melesat dari depan karakter
--  sejauh 80-100 studs, bukan diam di tempat.
-- ============================================================

local Debris            = game:GetService("Debris")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXFolder = ReplicatedStorage:WaitForChild("VFX")

local EffectService = {}

-- ============================================================
--  KONFIGURASI: VFX yang harus WELD ke limb tertentu
-- ============================================================
local WELD_TO_LIMB = {
	YujiDivergent = "Right Arm",
}

-- ============================================================
--  KONFIGURASI: VFX proyektil yang MELESAT (pakai Tween)
--  Beda dengan PROJECTILE_VFX lama yang cuma "muncul diam".
--  Ini benar-benar bergerak dari titik A ke titik B.
-- ============================================================
local TWEENING_PROJECTILES = {
	GojoRed     = true,
	GojoPurple  = true,
	SukunaArrow = true,
}

-- VFX yang muncul diam saja di depan karakter (aura, bukan proyektil)
local STATIC_AURA_VFX = {
	GojoBlue = true,   -- Blue tidak melesat, cuma muncul + berputar
}

-- ============================================================
--  FUNGSI: playAnimation
-- ============================================================
function EffectService.playAnimation(character, animID)
	if not animID or animID == "" or animID == "0" then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn("[EffectService] Animator tidak ditemukan!")
		return nil
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = animID

	local success, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)

	if not success or not track then
		warn("[EffectService] Gagal load animasi: " .. tostring(animID))
		return nil
	end

	track.Priority = Enum.AnimationPriority.Action
	track:Play()

	return track
end

-- ============================================================
--  FUNGSI INTERNAL: emitAllParticles
-- ============================================================
local function emitAllParticles(vfxClone)
	for _, descendant in ipairs(vfxClone:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(20)
			if not descendant.Enabled then
				descendant.Enabled = true
				task.delay(0.3, function()
					if descendant and descendant.Parent then
						descendant.Enabled = false
					end
				end)
			end
		end
	end
end

-- ============================================================
--  FUNGSI INTERNAL: getAnchorPart
--  Ambil "part acuan" dari VFX clone, baik Model maupun Part.
-- ============================================================
local function getAnchorPart(vfxClone)
	if vfxClone:IsA("Model") then
		return vfxClone.PrimaryPart
	elseif vfxClone:IsA("BasePart") then
		return vfxClone
	end
	return nil
end

-- ============================================================
--  FUNGSI INTERNAL: positionVFX
-- ============================================================
local function positionVFX(vfxClone, cframe)
	if vfxClone:IsA("Model") then
		vfxClone:PivotTo(cframe)
	elseif vfxClone:IsA("BasePart") then
		vfxClone.CFrame = cframe
	end
end

-- ============================================================
--  FUNGSI INTERNAL: weldVFXToLimb
-- ============================================================
local function weldVFXToLimb(vfxClone, character, limbName)
	local limb = character:FindFirstChild(limbName)
	if not limb then
		warn("[EffectService] Limb tidak ditemukan: " .. limbName)
		return false
	end

	local anchorPart = getAnchorPart(vfxClone)
	if not anchorPart then
		warn("[EffectService] VFX tidak punya anchor part!")
		return false
	end

	positionVFX(vfxClone, limb.CFrame)

	local weld  = Instance.new("WeldConstraint")
	weld.Part0  = limb
	weld.Part1  = anchorPart
	weld.Parent = anchorPart

	return true
end

-- ============================================================
--  FUNGSI INTERNAL: makeVFXTweenable
--  Kalau vfxClone adalah Model TANPA BasePart langsung yang
--  bisa di-Tween (Tween butuh BasePart, bukan Model), kita
--  pastikan kita selalu tween anchorPart-nya, bukan Model itu
--  sendiri. Function ini hanya validasi & return anchor part.
-- ============================================================
local function makeVFXTweenable(vfxClone)
	local anchorPart = getAnchorPart(vfxClone)
	if not anchorPart then
		warn("[EffectService] VFX tidak bisa di-tween, tidak ada anchor part!")
		return nil
	end

	-- Pastikan anchor part tidak collide dengan apapun (murni visual)
	anchorPart.CanCollide = false
	anchorPart.Anchored   = true  -- proyektil dipindah via Tween, bukan physics

	return anchorPart
end

-- ============================================================
--  FUNGSI: fireProjectile
--  Melesatkan VFX proyektil dari posisi awal ke arah depan
--  sejauh distance studs, menggunakan TweenService.
--
--  Parameter:
--  character    : karakter pemilik skill (untuk LookVector)
--  vfxName      : nama VFX di ReplicatedStorage.VFX
--  distance     : jarak tempuh (studs), default 90
--  travelTime   : durasi tempuh (detik), default 0.7
--
--  Return: tidak ada (fire and forget, auto cleanup)
-- ============================================================
function EffectService.fireProjectile(character, vfxName, distance, travelTime)
	distance   = distance or 90
	travelTime = travelTime or 0.7

	local vfxTemplate = VFXFolder:FindFirstChild(vfxName)
	if not vfxTemplate then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local vfxClone = vfxTemplate:Clone()
	vfxClone.Parent = workspace

	-- Posisi awal di depan karakter
	local startCFrame = hrp.CFrame * CFrame.new(0, 0, -5)
	positionVFX(vfxClone, startCFrame)

	-- Pastikan partikel menyala selama proyektil terbang!
	emitAllParticles(vfxClone, travelTime)

	local lookDir = hrp.CFrame.LookVector
	local endPosition = startCFrame.Position + (lookDir * distance)

	-- Sistem pergerakan baru (Anti-Bug / Anti-Tertinggal untuk Model)
	task.spawn(function()
		local RunService = game:GetService("RunService")
		local elapsed = 0

		while elapsed < travelTime and vfxClone.Parent do
			local dt = RunService.Heartbeat:Wait()
			elapsed = elapsed + dt

			-- Hitung pergerakan maju
			local alpha = math.min(elapsed / travelTime, 1)
			local currentPos = startCFrame.Position:Lerp(endPosition, alpha)

			-- Pindahkan keseluruhan model secara paksa
			local currentCFrame = CFrame.new(currentPos, currentPos + lookDir)
			positionVFX(vfxClone, currentCFrame)
		end
	end)

	print("[EffectService] Proyektil melesat: " .. vfxName)
	Debris:AddItem(vfxClone, travelTime + 0.3)
end

-- ============================================================
--  FUNGSI: spawnVFX
--  Untuk VFX statis/impact (BUKAN proyektil melesat).
--  Tetap dipakai untuk: HitPunch, YujiDivergent, YujiBlackFlash,
--  YujiKick, SukunaDismantle, SukunaCleave, GojoBlue (aura diam).
-- ============================================================
local function spawnVFX(character, targetPosition, vfxName, customLifetime)
	if not vfxName or vfxName == "" then return end

	local vfxTemplate = VFXFolder:FindFirstChild(vfxName)
	if not vfxTemplate then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local vfxClone = vfxTemplate:Clone()
	vfxClone.Parent = workspace

	if WELD_TO_LIMB[vfxName] then
		local limbName = WELD_TO_LIMB[vfxName]
		local ok = weldVFXToLimb(vfxClone, character, limbName)
		if not ok then positionVFX(vfxClone, hrp.CFrame) end

	elseif STATIC_AURA_VFX[vfxName] then
		local forwardCFrame = hrp.CFrame * CFrame.new(0, 0, -5)
		positionVFX(vfxClone, forwardCFrame)
	else
		if targetPosition then
			positionVFX(vfxClone, CFrame.new(targetPosition))
		else
			local forwardCFrame = hrp.CFrame * CFrame.new(0, 0, -4)
			positionVFX(vfxClone, forwardCFrame)
		end
	end

	emitAllParticles(vfxClone)

	-- Gunakan customLifetime jika ada, jika tidak default 2 detik
	Debris:AddItem(vfxClone, customLifetime or 2)

	return vfxClone
end

function EffectService.spawnChargeVFX(character, vfxName, lifetime)
	spawnVFX(character, nil, vfxName, lifetime)
end

-- ============================================================
--  FUNGSI: spinAura
--  Khusus GojoBlue — VFX diam tapi BERPUTAR 180 derajat.
--  Dipanggil terpisah dari spawnVFX karena butuh animasi rotasi.
-- ============================================================
function EffectService.spinAura(character, vfxName, spinDegrees, spinDuration)
	spinDegrees  = spinDegrees or 180
	spinDuration = spinDuration or 1

	local vfxClone = spawnVFX(character, nil, vfxName, spinDuration + 0.5)
	if not vfxClone then return end

	-- 1. PAKSA SEMUA PARTIKEL IKUT BERPUTAR (Kunci ke Part)
	for _, desc in ipairs(vfxClone:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			desc.LockedToPart = true
		end
	end

	-- 2. PUTAR OBJEKNYA
	task.spawn(function()
		local RunService = game:GetService("RunService")
		local elapsed = 0
		local degreesPerSecond = spinDegrees / spinDuration

		while elapsed < spinDuration and vfxClone.Parent do
			local dt = RunService.Heartbeat:Wait()
			elapsed = elapsed + dt

			-- Menggunakan sumbu Z (0, 0, Putaran) agar berputar seperti setir/portal
			local spinMath = CFrame.Angles(0, 0, math.rad(degreesPerSecond * dt))
			vfxClone:PivotTo(vfxClone:GetPivot() * spinMath)
		end
	end)

	print("[EffectService] " .. vfxName .. " berputar " .. spinDegrees .. " derajat")
end

-- ============================================================
--  FUNGSI: playSound
-- ============================================================
local function playSound(character, sfxID, voiceID)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- 1. BAGIAN SFX (Efek Suara Jurus)
	if sfxID and sfxID ~= "" and sfxID ~= "0" then
		local sfx = Instance.new("Sound")
		sfx.SoundId = (sfxID:match("^rbxassetid://")) and sfxID or ("rbxassetid://" .. sfxID)

		-- PERBAIKAN VOLUME: Naikkan dari 0.8 menjadi 2.5 (Bisa diganti sampai 10)
		sfx.Volume             = 2.5 
		sfx.RollOffMaxDistance = 100 -- Jangkauan suara diperluas
		sfx.RollOffMinDistance = 10
		sfx.Parent             = hrp

		sfx:Play()
		-- Hapus sistem 'Ended' yang sering bikin bug terpotong
		-- Biarkan Debris yang menghapus otomatis setelah 8 detik
		Debris:AddItem(sfx, 8)
	end

	-- 2. BAGIAN VOICE (Suara Karakter)
	if voiceID and voiceID ~= "" and voiceID ~= "0" then
		task.delay(0.1, function()
			if not hrp or not hrp.Parent then return end

			local voice = Instance.new("Sound")
			voice.SoundId = (voiceID:match("^rbxassetid://")) and voiceID or ("rbxassetid://" .. voiceID)

			-- PERBAIKAN VOLUME VOICE: Naikkan agar teriakan karakter sangat jelas
			voice.Volume             = 3.5 
			voice.RollOffMaxDistance = 150 
			voice.RollOffMinDistance = 15
			voice.Parent             = hrp

			voice:Play()
			-- Hapus sistem 'Ended', gunakan waktu Debris yang panjang (10 detik)
			-- agar kalimat panjang seperti "Ryoiki Tenkai" tidak pernah terpotong!
			Debris:AddItem(voice, 10)
		end)
	end
end

-- ============================================================
--  FUNGSI UTAMA: playSkillEffects
--  Dipakai untuk VFX statis/impact (non-proyektil melesat).
--  Untuk proyektil melesat, CombatService panggil
--  EffectService.fireProjectile() secara terpisah dengan delay.
-- ============================================================
function EffectService.playSkillEffects(character, targetPosition, vfxName, sfxID, voiceID)
	task.spawn(function()
		spawnVFX(character, targetPosition, vfxName)
	end)

	task.spawn(function()
		playSound(character, sfxID, voiceID)
	end)
end

return EffectService