-- ============================================================
--  EnemyAI.lua (Script / ServerScript)
--  ServerScriptService > Server
--
--  VERSI 2 — Arsitektur ChildAdded Listener
--
--  Perubahan dari v1:
--  - HAPUS: fungsi spawnEnemy() dan semua test spawn manual
--  - TAMBAH: ActiveEnemies.ChildAdded listener
--    Setiap musuh baru yang masuk folder ActiveEnemies
--    langsung disuntik FSM secara otomatis oleh script ini.
--
--  WaveManager bertanggung jawab SPAWN (clone + taruh di folder).
--  EnemyAI bertanggung jawab OTAK (FSM, pathfinding, combat).
--
--  Placeholder functions untuk diisi sendiri:
--  - playAnimation(humanoid, stateName)
--  - playHitReaction(character)
-- ============================================================

local Players            = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Debris             = game:GetService("Debris")

-- ============================================================
--  TUNGGU FOLDER ActiveEnemies
--  WaveManager membuat folder ini saat pertama run.
--  Kita tunggu maksimal 10 detik agar tidak error race condition.
-- ============================================================
local ActiveEnemies = workspace:WaitForChild("ActiveEnemies", 10)

if not ActiveEnemies then
	error("[EnemyAI] FATAL: Folder 'ActiveEnemies' tidak ditemukan di Workspace setelah 10 detik! Pastikan WaveManager sudah jalan.")
end

-- ============================================================
--  FUNGSI: playAnimation
--  Versi final — membaca dari folder Animations di dalam model.
--
--  Struktur yang diharapkan di dalam setiap model musuh:
--  CursedSpirit
--  └── Animations (Folder)
--      ├── Idle    (Animation)
--      ├── Walk    (Animation)  ← diputar saat state CHASE
--      └── Attack  (Animation)  ← diputar saat state ATTACK
--
--  animCache: tabel yang menyimpan AnimationTrack yang sudah
--  di-load agar tidak LoadAnimation() berulang setiap state
--  berubah (LoadAnimation yang berulang boros memory).
-- ============================================================
local animCache = {}  -- format: animCache[humanoid][stateName] = AnimationTrack

local function playAnimation(humanoid, stateName)
	if not humanoid or not humanoid.Parent then return end

	-- Ambil model musuh (parent dari Humanoid)
	local enemyModel = humanoid.Parent

	-- Cari folder Animations di dalam model
	local animFolder = enemyModel:FindFirstChild("Animations")
	if not animFolder then
		-- Tidak warn agar tidak spam kalau memang tidak ada folder
		return
	end

	-- Mapping state FSM → nama objek Animation di folder
	-- "chase" di FSM = animasi "Walk" di folder
	local stateToAnimName = {
		idle    = "Idle",
		chase   = "Walk",
		attack  = "Attack",
		stunned = "Idle",   -- pakai Idle saat stunned (bisa diganti HitReaction nanti)
		dead    = "Idle",   -- Roblox handle ragdoll, Idle sebagai fallback
	}

	local animName = stateToAnimName[stateName]
	if not animName then return end

	-- Cari objek Animation di folder
	local animObject = animFolder:FindFirstChild(animName)
	if not animObject then
		warn("[EnemyAI] Animasi '" .. animName .. "' tidak ditemukan di folder Animations " .. enemyModel.Name)
		return
	end

	-- Ambil Animator dari Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	-- Inisialisasi cache per humanoid kalau belum ada
	if not animCache[humanoid] then
		animCache[humanoid] = {}
	end

	-- Load animasi ke cache kalau belum pernah di-load
	if not animCache[humanoid][stateName] then
		local success, track = pcall(function()
			return animator:LoadAnimation(animObject)
		end)

		if not success or not track then
			warn("[EnemyAI] Gagal load animasi " .. animName .. " untuk " .. enemyModel.Name)
			return
		end

		-- Set looping berdasarkan tipe animasi
		-- Idle dan Walk looping, Attack tidak (satu kali per serangan)
		track.Looped = (stateName == "idle" or stateName == "chase")
		animCache[humanoid][stateName] = track
	end

	local targetTrack = animCache[humanoid][stateName]
	if not targetTrack then return end

	-- Jangan restart kalau animasi yang sama sudah jalan
	if targetTrack.IsPlaying then return end

	-- Stop semua animasi yang sedang jalan dari cache ini
	for _, track in pairs(animCache[humanoid]) do
		if track and track.IsPlaying then
			track:Stop(0.15)  -- fade out 0.15 detik agar transisi halus
		end
	end

	-- Play animasi baru
	targetTrack:Play(0.15)  -- fade in 0.15 detik
end

local function playHitReaction(character)
	-- TODO: Isi dengan animasi hit reaction, VFX, SFX
	-- Contoh: EffectService.spawnVFX(character, nil, "HitSpark")
end

-- ============================================================
--  FUNGSI: findNearestPlayer
--  Cari pemain terdekat dari posisi origin dalam radius agro.
--  Return: (character, distance) atau (nil, math.huge)
-- ============================================================
local function findNearestPlayer(origin, radius)
	local nearestChar = nil
	local nearestDist = radius

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local dist = (hrp.Position - origin).Magnitude
				if dist < nearestDist then
					nearestDist = dist
					nearestChar = char
				end
			end
		end
	end

	return nearestChar, nearestDist
end

-- ============================================================
--  FUNGSI: getAttr
--  Baca attribute dari model dengan fallback value aman.
--  Mencegah error kalau attribute tidak sengaja terhapus.
-- ============================================================
local function getAttr(model, attrName, default)
	local val = model:GetAttribute(attrName)
	if val == nil then
		-- Hanya warn sekali per musuh, tidak spam per frame
		warn("[EnemyAI] Attribute '" .. attrName
			.. "' tidak ada di " .. model.Name
			.. " — pakai default: " .. tostring(default))
		return default
	end
	return val
end

-- ============================================================
--  FUNGSI UTAMA: injectFSM
--  "Menyuntik" otak FSM ke model musuh yang diberikan.
--  Dipanggil oleh ChildAdded listener setiap kali musuh baru
--  masuk ke folder ActiveEnemies.
--
--  Tidak perlu clone model — model sudah ada di Workspace.
--  Fungsi ini hanya menambahkan logika AI ke model yang ada.
-- ============================================================
local function injectFSM(enemy)

	-- --------------------------------------------------------
	--  VALIDASI AWAL
	--  Cek semua komponen wajib sebelum mulai FSM.
	--  Kalau tidak valid, skip tanpa crash.
	-- --------------------------------------------------------
	if not enemy:IsA("Model") then return end

	-- Tunggu sebentar agar WaveManager sempat selesai setup model
	-- (PivotTo, SetAttribute, dll) sebelum FSM mulai jalan
	task.wait(0.1)

	-- Cek apakah ini memang musuh (bukan debris atau objek lain)
	if not enemy:GetAttribute("IsEnemy") then
		return
	end

	local humanoid = enemy:FindFirstChildOfClass("Humanoid")
	local hrp      = enemy:FindFirstChild("HumanoidRootPart")

	if not humanoid or not hrp then
		warn("[EnemyAI] " .. enemy.Name .. " tidak punya Humanoid/HumanoidRootPart — FSM tidak disuntik.")
		return
	end

	-- Pastikan Animator ada (untuk placeholder playAnimation nanti)
	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end

	-- --------------------------------------------------------
	--  BACA STAT DARI ATTRIBUTES MODEL
	--  Semua angka baca dari model, bukan hardcode.
	--  Nilai default sebagai fallback kalau attribute tidak ada.
	-- --------------------------------------------------------
	local maxHP          = getAttr(enemy, "MaxHP",          60)
	local walkSpeed      = getAttr(enemy, "WalkSpeed",      12)
	local damage         = getAttr(enemy, "Damage",         10)
	local agroRadius     = getAttr(enemy, "AgroRadius",    150)
	local attackRange    = getAttr(enemy, "AttackRange",     5)
	local attackCooldown = getAttr(enemy, "AttackCooldown", 1.5)
	local isBoss         = getAttr(enemy, "IsBoss",        false)

	-- Setup Humanoid dari attribute
	humanoid.MaxHealth = maxHP
	humanoid.Health    = maxHP
	humanoid.WalkSpeed = walkSpeed

	-- Update attribute CurrentHP agar bisa dibaca sistem lain
	enemy:SetAttribute("CurrentHP", maxHP)

	print("[EnemyAI] FSM disuntik ke: " .. enemy.Name
		.. " | HP:" .. maxHP
		.. " SPD:" .. walkSpeed
		.. " DMG:" .. damage
		.. " Boss:" .. tostring(isBoss))

	-- --------------------------------------------------------
	--  STATE MACHINE VARIABLES
	--  Semua state tersimpan sebagai local variable per musuh.
	--  Tidak ada global state — setiap musuh benar-benar mandiri.
	-- --------------------------------------------------------
	local currentState     = "IDLE"
	local isStunned        = false
	local attackOnCooldown = false
	local isAlive          = true

	local function setState(newState)
		if currentState == "DEAD" then return end
		currentState = newState
		playAnimation(humanoid, newState:lower())
	end

	-- --------------------------------------------------------
	--  PATHFINDING (UPDATE: Skala Dinamis & Anti-Nyangkut)
	-- --------------------------------------------------------
	-- Sesuaikan radius pathfinding dengan ukuran asli musuh
	local dynamicRadius = isBoss and 5 or (hrp.Size.X * 1.2)
	local dynamicHeight = isBoss and 10 or 6

	local path = PathfindingService:CreatePath({
		AgentHeight     = dynamicHeight,
		AgentRadius     = dynamicRadius,
		AgentCanJump    = true, -- UPDATE: Izinkan musuh melompat jika nyangkut!
		AgentCanClimb   = false,
		WaypointSpacing = 4,
	})

	local function chaseTarget(targetHRP)
		if not isAlive or isStunned then return false end
		if not targetHRP or not targetHRP.Parent then return false end

		local success = pcall(function()
			path:ComputeAsync(hrp.Position, targetHRP.Position)
		end)

		if not success or path.Status ~= Enum.PathStatus.Success then
			-- Jika gagal temukan jalan, lompat sekali untuk coba lepas dari tembok
			humanoid.Jump = true 
			humanoid:MoveTo(targetHRP.Position)
			return false
		end

		local waypoints = path:GetWaypoints()

		-- UPDATE: Jangan jalani semua waypoint! Cukup jalani 3 titik pertama, 
		-- lalu return agar FSM menghitung ulang jalur. Ini membuat musuh sangat responsif!
		local maxWaypoints = math.min(4, #waypoints)

		for i = 2, maxWaypoints do
			if not isAlive or isStunned or currentState ~= "CHASE" then return false end

			-- Cek jarak
			local dist = (hrp.Position - targetHRP.Position).Magnitude
			if dist <= attackRange then
				return true
			end

			-- Jika ada instruksi lompat dari pathfinding
			if waypoints[i].Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end

			humanoid:MoveTo(waypoints[i].Position)

			local reached = false
			local connection
			connection = humanoid.MoveToFinished:Connect(function(didReach)
				reached = didReach
				connection:Disconnect()
			end)

			local waited = 0
			-- Timeout dipersingkat jadi 1 detik agar musuh cepat sadar kalau nyangkut
			while not reached and waited < 1 and isAlive and not isStunned and currentState == "CHASE" do
				task.wait(0.1)
				waited += 0.1
			end

			if connection then pcall(function() connection:Disconnect() end) end
		end

		return true
	end

	-- --------------------------------------------------------
	--  FUNGSI: doAttack
	--  Eksekusi damage ke target dengan cooldown.
	-- --------------------------------------------------------
	local function doAttack(targetChar)
		if attackOnCooldown then return end
		if not targetChar or not targetChar.Parent then return end

		local targetHRP      = targetChar:FindFirstChild("HumanoidRootPart")
		local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
		if not targetHRP or not targetHumanoid then return end

		-- Cek jarak lagi (target bisa sudah kabur sejak cek terakhir)
		local dist = (hrp.Position - targetHRP.Position).Magnitude
		if dist > attackRange * 1.5 then return end

		-- Berhenti bergerak saat menyerang
		humanoid:MoveTo(hrp.Position)

		-- CEK I-FRAMES: Jika target sedang kebal, serangan ditangkis
		-- Musuh tetap ATTACK (tidak kembali IDLE), hanya damage-nya yang dibatalkan
		if targetChar:GetAttribute("IsImmune") == true then
			print("[EnemyAI] " .. enemy.Name
				.. " menyerang " .. targetChar.Name
				.. " — DITANGKIS (IsImmune aktif)!")

			-- Cooldown tetap aktif agar serangan tidak spam saat kebal berakhir
			attackOnCooldown = true
			task.delay(attackCooldown, function()
				attackOnCooldown = false
			end)
			return  -- keluar dari doAttack, tidak kurangi HP, tidak print damage
		end

		-- Target tidak kebal, kurangi HP seperti biasa
		if targetHumanoid.Health > 0 then

			-- ==========================================
			-- [TAMBAHAN BARU]: Kalkulasi Shield Boost
			-- ==========================================
			local defMult = targetChar:GetAttribute("DefenseMultiplier")
			if not defMult then defMult = 1.0 end

			-- Kalikan damage musuh dengan pertahanan pemain (Contoh: 5 * 0.8 = 4)
			local finalDamage = damage * defMult

			targetHumanoid.Health = math.max(0, targetHumanoid.Health - finalDamage)
			print("[EnemyAI] " .. enemy.Name
				.. " menyerang " .. targetChar.Name
				.. " — Final Damage: " .. finalDamage .. " (Asli: " .. damage .. ")"
				.. " | HP target tersisa: " .. math.floor(targetHumanoid.Health))
		end

		-- Aktifkan cooldown serangan
		attackOnCooldown = true
		task.delay(attackCooldown, function()
			attackOnCooldown = false
		end)
	end

	-- --------------------------------------------------------
	--  FUNGSI: applyStun
	--  Dipanggil lewat attribute StunDuration dari CombatService.
	--  stunDuration detik = musuh tidak bisa bergerak.
	-- --------------------------------------------------------
	local function applyStun(stunDuration)
		if not isAlive or currentState == "DEAD" then return end

		isStunned = true
		setState("STUNNED")
		humanoid:MoveTo(hrp.Position)

		playHitReaction(enemy)

		task.delay(stunDuration, function()
			if isAlive and currentState ~= "DEAD" then
				isStunned = false
				setState("CHASE")
			end
		end)
	end

	-- Setup stun trigger via attribute change
	-- CombatService set enemy:SetAttribute("StunDuration", X)
	-- lalu script ini auto-detect dan panggil applyStun(X)
	enemy:SetAttribute("StunDuration", 0)

	enemy:GetAttributeChangedSignal("StunDuration"):Connect(function()
		local dur = enemy:GetAttribute("StunDuration")
		if dur and dur > 0 then
			applyStun(dur)
			task.delay(0.1, function()
				if enemy and enemy.Parent then
					enemy:SetAttribute("StunDuration", 0)
				end
			end)
		end
	end)

	-- --------------------------------------------------------
	--  FUNGSI: handleDeath
	--  Dipanggil saat Humanoid.Health = 0.
	--  Guard double-death dengan flag isAlive.
	-- --------------------------------------------------------
	local function handleDeath()
		if not isAlive then return end
		isAlive = false

		setState("DEAD")
		humanoid:MoveTo(hrp.Position)

		print("[EnemyAI] " .. enemy.Name .. " mati!")

		-- Cleanup animCache untuk humanoid ini
		-- Mencegah memory leak dari track yang tersimpan di cache
		-- tapi model-nya sudah di-destroy
		if animCache[humanoid] then
			for _, track in pairs(animCache[humanoid]) do
				if track and track.IsPlaying then
					track:Stop(0)
				end
			end
			animCache[humanoid] = nil
		end

		Debris:AddItem(enemy, 3)
	end

	humanoid.Died:Connect(handleDeath)

	-- Sync CurrentHP attribute setiap kali health berubah
	humanoid.HealthChanged:Connect(function(newHealth)
		if enemy and enemy.Parent then
			enemy:SetAttribute("CurrentHP", math.floor(newHealth))
		end
	end)

	-- --------------------------------------------------------
	--  MAIN FSM LOOP
	--  Berjalan setiap 0.2 detik (5x per detik).
	--  Lebih efisien dari RunService.Heartbeat untuk 10-15 musuh.
	--  Setiap musuh punya loop independen di thread terpisah.
	-- --------------------------------------------------------
	task.spawn(function()
		setState("IDLE")

		while isAlive and enemy.Parent do
			if currentState == "DEAD" then break end

			if not isStunned then

				local targetChar, targetDist = findNearestPlayer(hrp.Position, agroRadius)

				if targetChar then
					local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")

					if targetDist <= attackRange then
						-- STATE: ATTACK
						if currentState ~= "ATTACK" then
							setState("ATTACK")
						end
						doAttack(targetChar)

					else
						-- STATE: CHASE
						if currentState ~= "CHASE" then
							setState("CHASE")
						end
						if targetHRP then
							chaseTarget(targetHRP)
						end
					end

				else
					-- STATE: IDLE (tidak ada pemain dalam radius agro)
					if currentState ~= "IDLE" then
						setState("IDLE")
						humanoid:MoveTo(hrp.Position)
					end

					-- Wander acak kecil untuk musuh biasa
					-- Boss diam di tempat saat IDLE (lebih intimidating)
					if not isBoss then
						local wanderOffset = Vector3.new(
							math.random(-8, 8),
							0,
							math.random(-8, 8)
						)
						humanoid:MoveTo(hrp.Position + wanderOffset)
					end
				end
			end

			task.wait(0.2)
		end

		-- Guard: kalau loop keluar tapi musuh belum mati secara resmi
		if isAlive then
			handleDeath()
		end
	end)
end

-- ============================================================
--  LISTENER UTAMA: ChildAdded
--
--  Setiap kali WaveManager memasukkan model musuh baru ke
--  folder ActiveEnemies, event ini langsung fire dan memanggil
--  injectFSM() di thread terpisah (task.spawn).
--
--  Kenapa task.spawn di sini?
--  Karena injectFSM() punya task.wait(0.1) di awalnya untuk
--  memberi waktu WaveManager menyelesaikan setup model.
--  Kalau tidak pakai task.spawn, ChildAdded listener akan
--  "macet" 0.1 detik dan bisa miss musuh berikutnya.
-- ============================================================
ActiveEnemies.ChildAdded:Connect(function(newEnemy)
	print("[EnemyAI] Musuh baru terdeteksi di ActiveEnemies: " .. newEnemy.Name)
	task.spawn(function()
		injectFSM(newEnemy)
	end)
end)

-- ============================================================
--  HANDLE MUSUH YANG SUDAH ADA SAAT SCRIPT PERTAMA LOAD
--  Ini handle edge case: kalau ada musuh yang sudah di-spawn
--  sebelum EnemyAI script selesai load (sangat jarang tapi
--  mungkin terjadi di server yang lambat).
-- ============================================================
for _, existingEnemy in ipairs(ActiveEnemies:GetChildren()) do
	if existingEnemy:IsA("Model") then
		print("[EnemyAI] Musuh existing ditemukan saat load: " .. existingEnemy.Name)
		task.spawn(function()
			injectFSM(existingEnemy)
		end)
	end
end

print("[EnemyAI] ✓ FSM Listener aktif — memantau ActiveEnemies secara real-time.")