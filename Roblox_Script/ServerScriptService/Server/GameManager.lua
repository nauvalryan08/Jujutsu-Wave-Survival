-- ============================================================
--  GameManager.lua  (Script, ServerScriptService > Server)
--  Sistem Pengatur Alur (Lobby -> Pilih Karakter -> Wave 1-5 -> Win/Lose)
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- MODULE & FOLDER
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local CharacterRigs = ReplicatedStorage:WaitForChild("CharacterRigs")
local SpawnPoints = workspace:WaitForChild("SpawnPoints")
local PlayerSpawn = SpawnPoints:WaitForChild("PlayerSpawn")

-- REMOTE EVENTS (Client <-> Server)
local CharacterSelected = Shared:WaitForChild("CharacterSelected")
local RigReady = Shared:WaitForChild("RigReady")
local UpdateGameState = Shared:WaitForChild("UpdateGameState") -- BARU: Mengatur UI & Lagu Client
local UIAction = Shared:WaitForChild("UIAction")               -- BARU: Menerima klik tombol UI Client

-- BINDABLE EVENTS (Server <-> Server)
local WaveControl = Shared:WaitForChild("WaveControl")         -- BARU: Jembatan ke Claude's WaveManager

-- DATABASE PEMAIN (Menyimpan status wave tiap pemain)
local PlayerData = {}

-- ============================================================
--  FUNGSI BANTUAN: Inisialisasi Data
-- ============================================================
local function initPlayerData(player)
	PlayerData[player.UserId] = {
		CurrentWave = 1,
		CharacterName = nil,
		IsPlaying = false
	}
end

-- ============================================================
--  FUNGSI UTAMA: Transisi Wave (Poin 4 & 7)
-- ============================================================
local function startWave(player)
	local data = PlayerData[player.UserId]
	if not data or not data.IsPlaying then return end

	local wave = data.CurrentWave

	-- 1. Beritahu Client untuk menampilkan UI Transisi & Ganti Lagu
	if wave == 5 then
		UpdateGameState:FireClient(player, "BOSS_TRANSITION", wave) -- Poin 7: UI Boss & Lagu Mahoraga
	else
		UpdateGameState:FireClient(player, "WAVE_TRANSITION", wave) -- Poin 4: UI Wave Normal
	end

	print("[GameManager] Menunggu 5 detik sebelum musuh Wave " .. wave .. " muncul...")

	-- 2. Jeda 5 Detik sesuai perencanaanmu
	task.wait(5)

	-- 3. Suruh WaveManager (Claude) untuk men-spawn musuh!
	WaveControl:Fire("SPAWN_WAVE", player, wave)
end

-- ============================================================
--  FUNGSI: Setup Custom Character (Warisan Script Lama)
-- ============================================================
local function setupCustomCharacter(player, charName)
	print("[GameManager] Memulai setup custom rig: " .. charName)

	local rigTemplate = CharacterRigs:FindFirstChild(charName)
	if not rigTemplate then return end

	local newRig = rigTemplate:Clone()
	local hrp = newRig:FindFirstChild("HumanoidRootPart")
	local humanoid = newRig:FindFirstChildOfClass("Humanoid")

	if not hrp or not humanoid then newRig:Destroy() return end

	-- Spawn Karakter
	local spawnCFrame = PlayerSpawn.CFrame
	newRig:PivotTo(spawnCFrame + Vector3.new(0, 5, 0))
	newRig.Parent = workspace
	player.Character = newRig

	humanoid.WalkSpeed = GameConfig.PLAYER_WALK_SPEED
	humanoid.JumpPower = GameConfig.PLAYER_JUMP_POWER
	humanoid.MaxHealth = GameConfig.PLAYER_MAX_HP
	humanoid.Health = GameConfig.PLAYER_MAX_HP

	player:SetAttribute("SelectedCharacter", charName)
	newRig:SetAttribute("CharacterName", charName)

	if not humanoid:FindFirstChildOfClass("Animator") then Instance.new("Animator").Parent = humanoid end

	RigReady:FireClient(player, newRig)

	-- Poin 9: Logika Saat Pemain Mati (Kalah)
	humanoid.Died:Connect(function()
		print("[GameManager] " .. player.Name .. " Gugur!")
		PlayerData[player.UserId].IsPlaying = false
		WaveControl:Fire("CLEAR_ENEMIES", player) -- Suruh Claude hapus sisa musuh
		UpdateGameState:FireClient(player, "GAME_OVER", PlayerData[player.UserId].CurrentWave)
	end)

	-- Mulai Alur Wave Pertama
	PlayerData[player.UserId].IsPlaying = true
	startWave(player)
end

-- ============================================================
--  LISTENER 1: Client Memilih Karakter (Poin 3)
-- ============================================================
CharacterSelected.OnServerEvent:Connect(function(player, charName)
	local validChars = {Yuji = true, Gojo = true, Sukuna = true}
	if not validChars[charName] then return end

	PlayerData[player.UserId].CharacterName = charName
	PlayerData[player.UserId].CurrentWave = 1 -- Reset ke Wave 1
	setupCustomCharacter(player, charName)
end)

-- ============================================================
--  LISTENER 2: Client Menekan Tombol Navigasi UI (Poin 5, 6, 8, 9)
-- ============================================================
UIAction.OnServerEvent:Connect(function(player, actionType)
	local data = PlayerData[player.UserId]
	if not data then return end

	if actionType == "NEXT_WAVE" then
		-- Poin 6: Lanjut ke Wave berikutnya (Respawn & Heal)
		data.CurrentWave = data.CurrentWave + 1
		setupCustomCharacter(player, data.CharacterName) 

	elseif actionType == "RETRY_WAVE" then
		-- Poin 9: Coba lagi di Wave yang sama
		setupCustomCharacter(player, data.CharacterName)

	elseif actionType == "RETRY_FROM_START" then
		-- Poin 9: Coba lagi dari Wave 1
		data.CurrentWave = 1
		setupCustomCharacter(player, data.CharacterName)

	elseif actionType == "EXIT_TO_LOBBY" then
		-- Poin 5 & 8: Kembali ke Lobby
		data.IsPlaying = false
		data.CurrentWave = 1
		if player.Character then player.Character:Destroy() end
		WaveControl:Fire("CLEAR_ENEMIES", player)
		UpdateGameState:FireClient(player, "LOBBY")
		
		-- TAMBAHKAN KODE INI DI BAWAH EXIT_TO_LOBBY:
	elseif actionType == "DEV_INSTANT_CLEAR" then
		print("[GameManager] DEV CHEAT: Wave diselesaikan instan!")
		WaveControl:Fire("CLEAR_ENEMIES", player) -- Hapus musuh fisik

		-- Pura-pura simulasi menang agar logika transisinya jalan
		if data.CurrentWave == 5 then
			data.IsPlaying = false
			UpdateGameState:FireClient(player, "GAME_WON")
		else
			UpdateGameState:FireClient(player, "WAVE_CLEARED", data.CurrentWave)
		end
	end
end)

-- ============================================================
--  LISTENER 3: Menangkap Sinyal dari WaveManager Claude (Poin 5 & 8)
-- ============================================================
WaveControl.Event:Connect(function(action, player)
	local data = PlayerData[player.UserId]
	if not data or not data.IsPlaying then return end

	if action == "WAVE_CLEARED" then
		if data.CurrentWave == 5 then
			-- Poin 8: Mahoraga Mati (Menang)
			data.IsPlaying = false
			UpdateGameState:FireClient(player, "GAME_WON")
		else
			-- Poin 5: Wave Normal Selesai
			UpdateGameState:FireClient(player, "WAVE_CLEARED", data.CurrentWave)
		end
	end
end)

-- ============================================================
--  KONEKSI PEMAIN JOIN & LEAVE (Poin 1 & 2)
-- ============================================================
Players.PlayerAdded:Connect(function(player)
	initPlayerData(player)
	-- Poin 1 & 2: Berikan sinyal ke Client untuk putar lagu JJK dan tampilkan Lobby
	UpdateGameState:FireClient(player, "LOBBY") 
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerData[player.UserId] = nil
	WaveControl:Fire("CLEAR_ENEMIES", player)
end)

print("[GameManager] ✓ Otak Utama 9 Poin Alur Siap Digunakan!")