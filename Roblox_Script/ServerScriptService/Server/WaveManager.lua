-- ============================================================
--  WaveManager.lua  (Script / ServerScript)
--  ServerScriptService > Server
--
--  Bertanggung jawab atas:
--  1. Menerima sinyal SPAWN_WAVE dari GameManager
--  2. Spawn musuh sesuai spesifikasi per wave
--  3. Tracking kematian musuh (fire WAVE_CLEARED ke GameManager)
--  4. Membersihkan semua musuh saat CLEAR_ENEMIES
--
--  Berkomunikasi dengan GameManager lewat BindableEvent WaveControl.
--  Memanggil fungsi spawnEnemy() dari EnemyAI.lua yang sudah ada.
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

-- ============================================================
--  REFERENSI EKSTERNAL
-- ============================================================

-- BindableEvent jembatan ke GameManager
local Shared      = ReplicatedStorage:WaitForChild("Shared")
local WaveControl = Shared:WaitForChild("WaveControl")

-- Template model musuh
local EnemyModels = ReplicatedStorage:WaitForChild("EnemyModels")

-- Titik spawn di Workspace (4 Part transparan)
local SpawnPointsFolder = workspace:WaitForChild("SpawnPoints")

-- ============================================================
--  SETUP FOLDER MUSUH AKTIF
--  Folder ini menampung semua musuh yang sedang hidup.
--  Dibuat di sini agar tidak perlu dibuat manual di Studio.
-- ============================================================
local ActiveEnemies = workspace:FindFirstChild("ActiveEnemies")
if not ActiveEnemies then
	ActiveEnemies = Instance.new("Folder")
	ActiveEnemies.Name = "ActiveEnemies"
	ActiveEnemies.Parent = workspace
	print("[WaveManager] Folder ActiveEnemies dibuat di Workspace.")
end

-- ============================================================
--  TRACKING STATE PER PEMAIN
--  Format: waveState[player.UserId] = {
--      activeCount = number,   -- jumlah musuh yang masih hidup
--      isClearing  = bool,     -- sedang dalam proses CLEAR_ENEMIES
--  }
-- ============================================================
local waveState = {}

local function getState(player)
	if not waveState[player.UserId] then
		waveState[player.UserId] = {
			activeCount = 0,
			isClearing  = false,
		}
	end
	return waveState[player.UserId]
end

-- ============================================================
--  FUNGSI: getSpawnPoints
--  Ambil semua Part dari folder SpawnPoints sebagai tabel.
--  Diurutkan berdasarkan nama agar konsisten (SpawnPoint1, 2, 3, 4).
-- ============================================================
local function getSpawnPoints()
	local points = {}
	for _, part in ipairs(SpawnPointsFolder:GetChildren()) do
		if part:IsA("BasePart") then
			table.insert(points, part)
		end
	end
	-- Urutkan berdasarkan nama agar spawn point 1,2,3,4 konsisten
	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)
	return points
end

-- ============================================================
--  FUNGSI: cloneAndPlace
--  Clone model musuh dari EnemyModels, taruh di ActiveEnemies,
--  dan posisikan di CFrame yang diberikan.
--  Return: instance model yang sudah di-spawn, atau nil jika gagal.
-- ============================================================
local function cloneAndPlace(modelName, spawnCFrame)
	local template = EnemyModels:FindFirstChild(modelName)
	if not template then
		warn("[WaveManager] Model tidak ditemukan di EnemyModels: " .. modelName)
		return nil
	end

	local enemy = template:Clone()
	
	-- ============================================================
	-- [TAMBAHAN BARU]: Paksa Scale & HipHeight lewat Script!
	-- Menghentikan bug Roblox yang mereset ukuran musuh
	-- ============================================================
	local hum = enemy:FindFirstChildOfClass("Humanoid")
	if hum then
		if modelName == "CursedSpirit" then
			enemy:ScaleTo(1.438)      -- Scale up
			hum.HipHeight = -0.75      -- Pasang perhitungan HipHeight-mu
		elseif modelName == "CursedSpirit2" then
			enemy:ScaleTo(1.875)
			hum.HipHeight = -1.20
		elseif modelName == "Mahoraga" then
			enemy:ScaleTo(2.154)
			hum.HipHeight = -2.90
		end
	end
	
	enemy.Parent = ActiveEnemies

	-- Posisikan menggunakan PivotTo (butuh PrimaryPart sudah di-set di Studio)
	local ok, err = pcall(function()
		enemy:PivotTo(spawnCFrame)
	end)

	if not ok then
		warn("[WaveManager] Gagal posisikan " .. modelName .. ": " .. tostring(err))
		enemy:Destroy()
		return nil
	end

	-- Tag owner musuh ini (untuk CLEAR_ENEMIES per pemain)
	enemy:SetAttribute("OwnerUserId", 0)  -- default: milik "semua"
	enemy:SetAttribute("IsEnemy", true)

	return enemy
end

-- ============================================================
--  FUNGSI: trackEnemyDeath
--  Pantau event Died pada Humanoid setiap musuh.
--  Saat semua musuh mati → fire WAVE_CLEARED ke GameManager.
-- ============================================================
local function trackEnemyDeath(enemy, player)
	local humanoid = enemy:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[WaveManager] " .. enemy.Name .. " tidak punya Humanoid, tidak bisa di-track!")
		return
	end

	humanoid.Died:Connect(function()
		local state = getState(player)

		-- Jangan proses kalau sedang dalam CLEAR_ENEMIES (musuh dimusnahkan manual)
		if state.isClearing then return end

		state.activeCount = math.max(0, state.activeCount - 1)
		print("[WaveManager] Musuh mati. Sisa aktif: " .. state.activeCount)

		-- Semua musuh wave ini sudah mati
		if state.activeCount <= 0 then
			print("[WaveManager] Wave selesai! Fire WAVE_CLEARED ke GameManager.")
			-- Jeda singkat agar animasi mati musuh terakhir sempat main
			task.delay(1.5, function()
				-- Double check: pastikan pemain belum disconnect
				if player and player.Parent then
					WaveControl:Fire("WAVE_CLEARED", player)
				end
			end)
		end
	end)
end

-- ============================================================
--  FUNGSI: spawnWave
--  Logika spawning per wave sesuai spesifikasi:
--  Wave 1: 4 CursedSpirit (1 per spawn point)
--  Wave 2: 8 CursedSpirit (2 per spawn point, offset posisi)
--  Wave 3: 4 CursedSpirit2 (1 per spawn point)
--  Wave 4: 8 CursedSpirit2 (2 per spawn point)
--  Wave 5: 1 Mahoraga (di tengah map, dekat pemain)
-- ============================================================
local function spawnWave(player, waveNumber)
	local state = getState(player)
	state.activeCount = 0
	state.isClearing  = false

	-- Tag musuh dengan UserId pemain agar CLEAR_ENEMIES bisa target per pemain
	local ownerUserId = player.UserId

	local spawnPoints = getSpawnPoints()
	if #spawnPoints < 4 then
		warn("[WaveManager] Kurang dari 4 SpawnPoint ditemukan! Ditemukan: " .. #spawnPoints)
	end

	print("[WaveManager] Memulai spawn Wave " .. waveNumber .. " untuk " .. player.Name)

	-- --------------------------------------------------------
	--  HELPER INTERNAL: spawnOne
	--  Spawn satu musuh, tag owner, daftarkan death tracking.
	-- --------------------------------------------------------
	local function spawnOne(modelName, cframe)
		local enemy = cloneAndPlace(modelName, cframe)
		if not enemy then return end

		-- TAMBAHAN: Mainkan Intro Mahoraga jika dia spawn
		--if modelName == "Mahoraga" then
		--	local hrp = enemy:FindFirstChild("HumanoidRootPart")
		--	if hrp then
		--		local intro = hrp:FindFirstChild("Intro")
		--		if intro then 
		--			-- Jeda 0.5 detik untuk menunggu Client selesai merender Mahoraga
		--			task.delay(0.5, function()
		--				intro.Volume = 2 -- Besarkan volume mentah intro
		--				intro.RollOffMaxDistance = 1000 -- Jangkauan suara 1000 studs (satu arena penuh)
		--				intro:Play() 
		--			end)
		--		end
		--	end
		--end

		enemy:SetAttribute("OwnerUserId", ownerUserId)
		state.activeCount = state.activeCount + 1

		trackEnemyDeath(enemy, player)
		enemy:SetAttribute("SpawnPosition", cframe.Position)
	end

	-- --------------------------------------------------------
	--  WAVE 1: 4 CursedSpirit — 1 di tiap spawn point
	-- --------------------------------------------------------
	if waveNumber == 1 then
		for i = 1, math.min(4, #spawnPoints) do
			local cf = spawnPoints[i].CFrame + Vector3.new(0, 3, 0)
			spawnOne("CursedSpirit", cf)
			task.wait(0.3)  -- jeda kecil agar tidak semua spawn bersamaan (mengurangi physics spike)
		end

		-- --------------------------------------------------------
		--  WAVE 2: 8 CursedSpirit — 2 di tiap spawn point
		--  Musuh kedua di-offset agar tidak menyatu dengan yang pertama
		-- --------------------------------------------------------
	elseif waveNumber == 2 then
		for i = 1, math.min(4, #spawnPoints) do
			local basePos = spawnPoints[i].CFrame

			-- Musuh pertama di titik spawn asli
			spawnOne("CursedSpirit", basePos + Vector3.new(0, 3, 0))
			task.wait(0.5)

			-- Musuh kedua di-offset 4 studs ke samping + 2 studs ke depan
			local offset = Vector3.new(4, 3, 2)
			spawnOne("CursedSpirit", basePos + offset)
			task.wait(0.5)
		end

		-- --------------------------------------------------------
		--  WAVE 3: 4 CursedSpirit2 — 1 di tiap spawn point
		-- --------------------------------------------------------
	elseif waveNumber == 3 then
		for i = 1, math.min(4, #spawnPoints) do
			local cf = spawnPoints[i].CFrame + Vector3.new(0, 3, 0)
			spawnOne("CursedSpirit2", cf)
			task.wait(0.3)
		end

		-- --------------------------------------------------------
		--  WAVE 4: 8 CursedSpirit2 — 2 di tiap spawn point
		-- --------------------------------------------------------
	elseif waveNumber == 4 then
		for i = 1, math.min(4, #spawnPoints) do
			local basePos = spawnPoints[i].CFrame

			spawnOne("CursedSpirit2", basePos + Vector3.new(0, 3, 0))
			task.wait(0.5)

			local offset = Vector3.new(-4, 3, 2)   -- offset berlawanan dari wave 2 untuk variasi
			spawnOne("CursedSpirit2", basePos + offset)
			task.wait(0.5)
		end

		-- --------------------------------------------------------
		--  WAVE 5: 1 Mahoraga — Spawn di depan pemain
		--  Tidak pakai 4 spawn point normal.
		--  Posisi: HumanoidRootPart pemain + 20 studs ke depan.
		-- --------------------------------------------------------
	elseif waveNumber == 5 then
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")

		-- Gunakan titik tengah arena (misal SpawnPoint pertama) tapi naikkan 50 meter ke langit
		local baseCenter = spawnPoints[1] and spawnPoints[1].Position or Vector3.new(0, 0, 0)
		local dropPosition = baseCenter + Vector3.new(0, 50, 0)

		local spawnCFrame
		if hrp then
			-- Mahoraga jatuh dari langit dan langsung menatap pemain
			spawnCFrame = CFrame.new(dropPosition, Vector3.new(hrp.Position.X, dropPosition.Y, hrp.Position.Z))
		else
			spawnCFrame = CFrame.new(dropPosition)
		end

		print("[WaveManager] WAVE 5 — Mahoraga jatuh dari langit! 💀")
		spawnOne("Mahoraga", spawnCFrame)

	else
		warn("[WaveManager] Wave number tidak dikenali: " .. tostring(waveNumber))
		-- Kalau wave tidak dikenali, anggap langsung selesai
		WaveControl:Fire("WAVE_CLEARED", player)
		return
	end

	print("[WaveManager] Wave " .. waveNumber .. " spawn selesai. Total musuh aktif: " .. state.activeCount)

	-- Safeguard: kalau karena suatu sebab tidak ada musuh yang berhasil spawn,
	-- langsung fire WAVE_CLEARED agar game tidak macet menunggu selamanya.
	if state.activeCount <= 0 then
		warn("[WaveManager] Tidak ada musuh yang berhasil spawn! Auto-clear wave.")
		task.delay(1, function()
			if player and player.Parent then
				WaveControl:Fire("WAVE_CLEARED", player)
			end
		end)
	end
end

-- ============================================================
--  FUNGSI: clearEnemies
--  Hancurkan semua musuh milik pemain tertentu dari ActiveEnemies.
--  Dipanggil saat pemain mati atau kembali ke lobby.
-- ============================================================
local function clearEnemies(player)
	local state = getState(player)
	state.isClearing = true   -- flag agar trackEnemyDeath tidak fire WAVE_CLEARED saat cleanup

	local ownerUserId = player.UserId
	local cleared = 0

	for _, enemy in ipairs(ActiveEnemies:GetChildren()) do
		if enemy:GetAttribute("OwnerUserId") == ownerUserId then
			-- Destroy langsung tanpa animasi mati (cleanup cepat)
			enemy:Destroy()
			cleared = cleared + 1
		end
	end

	state.activeCount = 0
	print("[WaveManager] CLEAR_ENEMIES: " .. cleared .. " musuh dihapus untuk " .. player.Name)
end

-- ============================================================
--  LISTENER UTAMA: WaveControl.Event
--  Menerima semua sinyal dari GameManager dan server lain.
--
--  Format sinyal yang diterima:
--  ("SPAWN_WAVE", player, waveNumber) → dari GameManager
--  ("CLEAR_ENEMIES", player)          → dari GameManager
-- ============================================================
WaveControl.Event:Connect(function(action, player, waveNumber)

	-- Validasi: pastikan player adalah instance Player yang valid
	if not player or not player:IsA("Player") then
		-- Jika bukan player (mungkin sinyal dengan format berbeda), skip
		return
	end

	print("[WaveManager] Menerima sinyal: " .. tostring(action) .. " dari " .. player.Name)

	if action == "SPAWN_WAVE" then
		-- Spawn musuh sesuai wave, jalankan di thread terpisah
		-- agar tidak blocking listener (penting untuk delay task.wait di spawnWave)
		task.spawn(function()
			spawnWave(player, waveNumber)
		end)

	elseif action == "CLEAR_ENEMIES" then
		clearEnemies(player)

	else
		-- Log sinyal yang tidak dikenali untuk debugging
		-- (misal: "WAVE_CLEARED" yang kita kirim sendiri ke GameManager
		--  akan ter-catch di sini juga, tapi kita ignore saja)
		if action ~= "WAVE_CLEARED" then
			print("[WaveManager] Sinyal tidak dikenali, diabaikan: " .. tostring(action))
		end
	end
end)

-- ============================================================
--  CLEANUP: Bersihkan data saat pemain disconnect
-- ============================================================
Players.PlayerRemoving:Connect(function(player)
	-- Bersihkan musuh pemain yang disconnect
	if waveState[player.UserId] then
		clearEnemies(player)
		waveState[player.UserId] = nil
	end
end)

-- ============================================================
--  CATATAN UNTUK STEP SELANJUTNYA:
--  Jika EnemyAI.lua menggunakan fungsi spawnEnemy(modelName, cframe),
--  cloneAndPlace() di sini TIDAK memanggil fungsi itu.
--  WaveManager melakukan clone sendiri karena lebih mudah tracking
--  ownership per pemain.
--
--  Koordinasi dengan EnemyAI:
--  - Model yang di-clone WaveManager akan di-detect EnemyAI via
--    folder ActiveEnemies atau tag IsEnemy = true
--  - EnemyAI perlu dimodifikasi untuk scan ActiveEnemies
--    bukan hanya workspace.Enemies (sesuaikan nama folder)
-- ============================================================

print("[WaveManager] ✓ Wave system siap — menunggu sinyal dari GameManager.")