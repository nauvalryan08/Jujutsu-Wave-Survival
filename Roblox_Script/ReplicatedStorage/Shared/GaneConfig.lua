-- ============================================================
--  GameConfig.lua  (ModuleScript)
--  Satu-satunya tempat untuk mengubah angka balancing game.
--  Ubah di sini, efeknya berlaku ke seluruh sistem.
-- ============================================================

local GameConfig = {}

-- KARAKTER
GameConfig.CHARACTERS = {"Yuji", "Gojo", "Sukuna"}

-- PLAYER
GameConfig.PLAYER_MAX_HP        = 100
GameConfig.PLAYER_WALK_SPEED    = 16
GameConfig.PLAYER_SPRINT_SPEED  = 28
GameConfig.PLAYER_JUMP_POWER    = 50

-- BASIC ATTACK (berlaku semua karakter)
GameConfig.BASIC_DAMAGE         = 15
GameConfig.BASIC_RANGE          = 7      -- studs
GameConfig.BASIC_COOLDOWN       = 0.5   -- detik

-- JURUS YUJI
GameConfig.YUJI_Q_DAMAGE        = 35    -- Divergent Fist
GameConfig.YUJI_Q_RANGE         = 10
GameConfig.YUJI_Q_COOLDOWN      = 4
GameConfig.YUJI_E_DAMAGE        = 60    -- Black Flash
GameConfig.YUJI_E_STUN          = 1.5   -- detik stun
GameConfig.YUJI_E_COOLDOWN      = 8

-- JURUS SUKUNA
GameConfig.SUKUNA_Q_DAMAGE      = 50    -- Dismantle
GameConfig.SUKUNA_Q_RANGE       = 15
GameConfig.SUKUNA_Q_COOLDOWN    = 5
GameConfig.SUKUNA_E_DAMAGE      = 80    -- Cleave (AoE)
GameConfig.SUKUNA_E_RADIUS      = 12
GameConfig.SUKUNA_E_COOLDOWN    = 10

-- JURUS GOJO
GameConfig.GOJO_Q_FORCE         = 80    -- Lapse Blue (tarik)
GameConfig.GOJO_Q_COOLDOWN      = 5
GameConfig.GOJO_E_FORCE         = 100   -- Reversal Red (dorong)
GameConfig.GOJO_E_COOLDOWN      = 5
GameConfig.GOJO_R_DAMAGE        = 120   -- Hollow Purple (beam)
GameConfig.GOJO_R_RANGE         = 60
GameConfig.GOJO_R_COOLDOWN      = 15

-- MUSUH (Cursed Spirits)
GameConfig.ENEMY_MAX_HP         = 60
GameConfig.ENEMY_DAMAGE         = 10
GameConfig.ENEMY_SPEED          = 12
GameConfig.ENEMY_CHASE_RANGE    = 45    -- mulai kejar pemain
GameConfig.ENEMY_ATTACK_RANGE   = 5     -- mulai serang
GameConfig.ENEMY_ATTACK_COOLDOWN = 1.5

-- WAVE SYSTEM
GameConfig.TOTAL_WAVES          = 5
GameConfig.WAVE_BREAK            = 8    -- detik jeda antar wave
-- Jumlah musuh per wave [wave1, wave2, wave3, wave4, wave5]
GameConfig.ENEMIES_PER_WAVE     = {3, 5, 7, 10, 14}

-- DESTRUCTIBLE ENVIRONMENT
GameConfig.PILLAR_HP            = 150
GameConfig.WALL_HP              = 80
GameConfig.DEBRIS_LIFETIME      = 8    -- detik sebelum puing menghilang

return GameConfig