-- ============================================================
-- BoostManager.lua (ServerScript)
-- TAHAP 3: Logika Durasi (20s), Respawn per Wave, dan Notifikasi UI
-- ============================================================

local workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoostItemsFolder = workspace:WaitForChild("BoostItems")
local ActiveEnemies = workspace:WaitForChild("ActiveEnemies")

-- Setup Jembatan Komunikasi ke Client UI
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WaveControl = Shared:WaitForChild("WaveControl")

local BoostEvent = Shared:FindFirstChild("BoostEvent")
if not BoostEvent then
	BoostEvent = Instance.new("RemoteEvent")
	BoostEvent.Name = "BoostEvent"
	BoostEvent.Parent = Shared
end

local function initializeCharacterStats(character)
	character:SetAttribute("DamageMultiplier", 1.0)
	character:SetAttribute("SpeedMultiplier", 1.0)
	character:SetAttribute("DefenseMultiplier", 1.0) 
	character:SetAttribute("CDMultiplier", 1.0)      
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(initializeCharacterStats)
end)

-- ============================================================
-- FUNGSI: Setup logika sentuh (Touched) & Respawn Item
-- ============================================================
local function setupBoostItem(item)
	if not item:IsA("BasePart") then return end

	local debounce = false

	item.Touched:Connect(function(hit)
		if debounce then return end

		local character = hit.Parent
		local player = Players:GetPlayerFromCharacter(character)
		local humanoid = character:FindFirstChild("Humanoid")

		if player and humanoid and humanoid.Health > 0 then
			debounce = true 

			-- Sembunyikan item (Jangan di-Destroy agar bisa respawn)
			item.Transparency = 1
			item.CanCollide = false

			local duration = 20
			local buffType = ""
			local popUpMessage = ""

			-- BACA NAMA ITEM & TERAPKAN EFEK
			if item.Name == "Boost_Damage" then
				buffType = "Damage"
				popUpMessage = "Damage Buff Acquired!"
				local currentDmg = character:GetAttribute("DamageMultiplier")
				character:SetAttribute("DamageMultiplier", currentDmg + 0.2)

				task.delay(duration, function()
					if character and character.Parent then
						character:SetAttribute("DamageMultiplier", character:GetAttribute("DamageMultiplier") - 0.2)
					end
				end)

			elseif item.Name == "Boost_Speed" then
				buffType = "Speed"
				popUpMessage = "Speed Boost Acquired!"
				local currentSpd = character:GetAttribute("SpeedMultiplier")
				local newSpd = currentSpd + 0.2
				character:SetAttribute("SpeedMultiplier", newSpd)
				humanoid.WalkSpeed = 16 * newSpd

				task.delay(duration, function()
					if character and character.Parent and humanoid.Parent then
						character:SetAttribute("SpeedMultiplier", character:GetAttribute("SpeedMultiplier") - 0.2)
						humanoid.WalkSpeed = 16 * character:GetAttribute("SpeedMultiplier")
					end
				end)

			elseif item.Name == "Boost_Heal" then
				buffType = "Heal"
				popUpMessage = "Heal Boost Acquired!"
				local healAmount = humanoid.MaxHealth * 0.3
				humanoid.Health = math.clamp(humanoid.Health + healAmount, 0, humanoid.MaxHealth)
				duration = 0 -- Heal bersifat instan, tidak ada durasi

			elseif item.Name == "Boost_Shield" then
				buffType = "Shield"
				popUpMessage = "Shield Buff Acquired!"
				local currentDef = character:GetAttribute("DefenseMultiplier")

				-- Turunkan multiplier sebesar 0.2 (Dari 1.0 menjadi 0.8)
				local newDef = math.max(0.2, currentDef - 0.2) 
				character:SetAttribute("DefenseMultiplier", newDef) 

				task.delay(duration, function()
					if character and character.Parent then
						character:SetAttribute("DefenseMultiplier", character:GetAttribute("DefenseMultiplier") + 0.2)
					end
				end)

			elseif item.Name == "Boost_Cooldown" then
				buffType = "Cooldown"
				popUpMessage = "Cooldown Reduction Acquired!"
				local currentCD = character:GetAttribute("CDMultiplier")
				local newCD = math.max(0.4, currentCD - 0.2)
				character:SetAttribute("CDMultiplier", newCD)

				task.delay(duration, function()
					if character and character.Parent then
						character:SetAttribute("CDMultiplier", character:GetAttribute("CDMultiplier") + 0.2)
					end
				end)
			end

			-- Kirim sinyal ke UI Client
			if buffType ~= "" then
				BoostEvent:FireClient(player, buffType, duration, popUpMessage)
			end

			-- ============================================================
			-- LOGIKA RESPAWN ITEM
			-- ============================================================
			local isBossWave = ActiveEnemies:FindFirstChild("Mahoraga") ~= nil

			if isBossWave then
				-- Jika Boss Wave, respawn otomatis setelah 40 detik
				task.delay(40, function()
					if item and item.Parent then
						item.Transparency = 0
						item.CanCollide = true
						debounce = false
					end
				end)
			else
				-- Jika Normal Wave, item menunggu reset dari event SPAWN_WAVE
				-- Debounce tetap true agar tidak bisa diambil lagi di wave yang sama
			end
		end
	end)
end

-- Daftarkan semua item yang ada
for _, item in ipairs(BoostItemsFolder:GetChildren()) do
	setupBoostItem(item)
end

-- Listener untuk reset item di setiap awal Wave Normal
WaveControl.Event:Connect(function(action, player, waveNumber)
	if action == "SPAWN_WAVE" then
		for _, item in ipairs(BoostItemsFolder:GetChildren()) do
			if item:IsA("BasePart") then
				item.Transparency = 0
				item.CanCollide = true
				-- Hapus debounce manual lewat script
				local oldScript = item:FindFirstChildWhichIsA("Script")
				-- Karena debounce bersifat lokal di dalam scope, kita mengandalkan CanCollide untuk mereset sentuhan
				-- Reset fisiknya akan memungkinkan Touch event fire lagi jika kita setup ulang atau biarkan
				-- Cara aman: kita setup logic debouncenya berdasarkan properti CanCollide
			end
		end

		-- RE-SETUP semua item agar debouncenya kembali false murni
		for _, item in ipairs(BoostItemsFolder:GetChildren()) do
			-- Matikan koneksi Touch lama dengan merusak dan membuat ulang part (Teknik refresh memori yang bersih)
			local newItem = item:Clone()
			newItem.Parent = BoostItemsFolder
			setupBoostItem(newItem)
			item:Destroy()
		end
	end
end)

print("[BoostManager] TAHAP 3 Aktif: Logika Durasi & Respawn siap.")