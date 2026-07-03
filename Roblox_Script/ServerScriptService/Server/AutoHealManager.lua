-- ============================================================
-- AutoHealManager.lua (ServerScriptService)
-- Menangani pemulihan HP otomatis setelah X detik tidak terkena damage
-- ============================================================

local Players = game:GetService("Players")

-- KONFIGURASI
local RECOVERY_DELAY = 5.0      -- Waktu tunggu (detik) setelah damage terakhir
local HEAL_PERCENTAGE = 0.02    -- Sembuh 2% dari MaxHealth setiap detiknya
local HEAL_TICK_RATE = 1.0      -- Interval penyembuhan (1 detik)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid then return end

		local lastHealth = humanoid.Health
		local lastDamageTime = os.clock()

		-- 1. Deteksi kapan pemain terkena damage
		humanoid.HealthChanged:Connect(function(newHealth)
			-- Jika HP turun, berarti terkena damage (atau max HP berubah)
			if newHealth < lastHealth then
				lastDamageTime = os.clock()
			end
			-- Update rekam jejak HP terakhir
			lastHealth = newHealth
		end)

		-- 2. Loop Penyembuhan Independen
		task.spawn(function()
			while character and character.Parent and humanoid.Health > 0 do
				task.wait(HEAL_TICK_RATE)

				-- Pastikan HP belum penuh dan pemain masih hidup
				if humanoid.Health < humanoid.MaxHealth and humanoid.Health > 0 then

					-- Cek apakah sudah aman dari serangan selama RECOVERY_DELAY detik
					if os.clock() - lastDamageTime >= RECOVERY_DELAY then
						local healAmount = humanoid.MaxHealth * HEAL_PERCENTAGE

						-- Tambahkan HP, tapi jangan sampai melebihi MaxHealth
						humanoid.Health = math.clamp(humanoid.Health + healAmount, 0, humanoid.MaxHealth)

						-- Update lastHealth agar penambahan ini tidak dideteksi sebagai "damage" oleh fungsi di atas
						lastHealth = humanoid.Health
					end
				end
			end
		end)
	end)
end)

print("[AutoHealManager] Aktif: Regen HP tertunda 5 detik siap.")