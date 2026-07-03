-- ============================================================
--  SkillData.lua (ModuleScript) — VERSI HYBRID (JSON + LUA)
--  ReplicatedStorage > Shared
-- ============================================================

local HttpService = game:GetService("HttpService")
local SkillData = {}

-- ⬇️ MASUKKAN LINK RAW GITHUB KAMU DI SINI ⬇️
local JSON_URL = "https://raw.githubusercontent.com/nauvalryan08/Jujutsu-Wave-Survival/refs/heads/main/skills.json"

-- ============================================================
--  BASIC ATTACK
-- ============================================================
SkillData.BasicAttack = {
	damage    = 15,
	range     = 7,
	cooldown  = 0.5,
	skillType = "melee_single",
	effectColor = Color3.fromRGB(255, 255, 255),
	comboCount    = 4,
	comboDuration = 1.8,
	comboResetGap = 0.7,
	animID = {
		"rbxassetid://71406843055757",
		"rbxassetid://83917752883957",
		"rbxassetid://100202037092309",
		"rbxassetid://77043451646832",
	},
	vfxName = "HitPunch",
	sfxID   = "rbxassetid://101477429954879",
	voiceID = "0",
}

-- ============================================================
--  DATA LOKAL (Sebagai Fallback / Visual Assets)
-- ============================================================
SkillData.Yuji = {
	Q = { name = "Divergent Fist", damage = 35, range = 30, radius = 8, cooldown = 4, 
		skillType = "melee_aoe", knockback = 40, effectColor = Color3.fromRGB(255, 200, 100), 
		animID = "rbxassetid://110353067300637", vfxName = "YujiDivergent", 
		sfxID = "rbxassetid://97819687693023", voiceID = "0" },
	E = { name = "Black Flash", damage = 60, range = 50, cooldown = 8, stunTime = 1.5, 
		skillType = "melee_single", knockback = 20, effectColor = Color3.fromRGB(10, 10, 10), 
		animID = "rbxassetid://129228903802998", vfxName = "YujiBlackFlash", 
		sfxID = "rbxassetid://96508237940950", voiceID = "rbxassetid://114351236092594" },
	R = { name = "Punisher Kick", damage = 45, range = 30, cooldown = 6, 
		skillType = "melee_single", knockback = 50, effectColor = Color3.fromRGB(255, 120, 60), 
		animID = "rbxassetid://73995396694442", vfxName = "YujiKick", 
		sfxID = "rbxassetid://122494961448070", voiceID = "rbxassetid://85245351690271" },
}

SkillData.Gojo = {
	Q = { name = "Lapse Blue", damage = 20, radius = 50, cooldown = 5, 
		skillType = "pull_aoe", pullForce = 80, effectColor = Color3.fromRGB(80, 150, 255), 
		animID = "rbxassetid://83536546891612", vfxName = "GojoBlue", 
		sfxID = "rbxassetid://119871162552831", voiceID = "rbxassetid://107915359628650" },
	E = { name = "Reversal Red", damage = 30, radius = 40, cooldown = 5, 
		skillType = "push_aoe", pushForce = 120, effectColor = Color3.fromRGB(255, 60, 60), 
		animID = "rbxassetid://117887635547299", vfxName = "GojoRed", sfxID = "rbxassetid://88404685614642", 
		sfxExplosion = "rbxassetid://137742555911504", voiceID = "rbxassetid://131267451700580" },
	R = { name = "Hollow Purple", damage = 120, range = 125, cooldown = 15, 
		skillType = "beam", destroyPillars = true, effectColor = Color3.fromRGB(180, 80, 255), 
		animID = "rbxassetid://83367651401286", vfxName = "GojoPurple", sfxID = "rbxassetid://92183164583405", 
		sfxExplosion = "rbxassetid://139316396351592", voiceID = "rbxassetid://140280722011349" },
}

SkillData.Sukuna = {
	Q = { name = "Dismantle", damage = 20, range = 15, cooldown = 5, skillType = "beam", 
		destroyPillars = true, knockback = 30, effectColor = Color3.fromRGB(255, 40, 40), 
		animID = "rbxassetid://112036829844449", vfxName = "SukunaDismantle", 
		sfxID = "rbxassetid://122951695254282", voiceID = "rbxassetid://112401600931306" },
	E = { name = "Cleave", damage = 50, radius = 40, cooldown = 10, skillType = "melee_aoe", 
		destroyPillars = true, knockback = 60, effectColor = Color3.fromRGB(200, 0, 0), 
		animID = "rbxassetid://93433196588711", vfxName = "SukunaCleave", 
		sfxID = "rbxassetid://120117176159409", voiceID = "rbxassetid://98191452727727" },
	R = { name = "Fire Arrow", damage = 100, range = 100, cooldown = 30, skillType = "beam", 
		destroyPillars = true, knockback = 25, effectColor = Color3.fromRGB(255, 100, 0), 
		animID = "rbxassetid://92977197155230", vfxName = "SukunaArrow", sfxCharge = "rbxassetid://114588589169416", 
		sfxShoot = "rbxassetid://131784297102472", voiceID = "rbxassetid://113491080251833" },
}

-- ============================================================
--  INTEGRASI GITHUB JSON (SERVER-TO-CLIENT SYNC)
-- ============================================================
local RunService = game:GetService("RunService")

-- Fungsi khusus untuk menggabungkan data
local function mergeData(gitData)
	for charName, skills in pairs(gitData) do
		if SkillData[charName] then
			for skillKey, skillDataFromGit in pairs(skills) do
				if SkillData[charName][skillKey] then
					for k, v in pairs(skillDataFromGit) do
						SkillData[charName][skillKey][k] = v
					end
				end
			end
		end
	end
end

-- Pisahkan tugas antara Server dan Client
if RunService:IsServer() then
	-- TUGAS SERVER: Download dari internet
	local success, result = pcall(function()
		return HttpService:GetAsync(JSON_URL)
	end)

	if success then
		local gitData = HttpService:JSONDecode(result)
		mergeData(gitData)

		-- Simpan teks JSON murni ke dalam "Attribute" script ini
		-- agar Client bisa mengambilnya tanpa perlu download dari internet
		script:SetAttribute("GitJSON", result)
		print("[SkillData] BERHASIL (Server)! Data Git di-download dan disimpan.")
	else
		warn("[SkillData] Gagal (Server) menarik data dari Git. Error:", result)
	end
else
	-- TUGAS CLIENT (UI): Baca data yang sudah didownload Server
	local cachedJSON = script:GetAttribute("GitJSON")

	-- Jika Client meload terlalu cepat dan Server belum selesai download, tunggu!
	if not cachedJSON then
		script:GetAttributeChangedSignal("GitJSON"):Wait()
		cachedJSON = script:GetAttribute("GitJSON")
	end

	if cachedJSON then
		local gitData = HttpService:JSONDecode(cachedJSON)
		mergeData(gitData)
		print("[SkillData] BERHASIL (Client)! UI sekarang sudah di-update dengan data Git.")
	end
end

return SkillData

-- ================================================================================= --

---- ============================================================
----  SkillData.lua (ModuleScript) — VERSI 4
----  ReplicatedStorage > Shared
----
----  Tambahan v4: setiap skill punya vfxName yang merujuk ke
----  nama Instance di ReplicatedStorage.VFX
---- ============================================================

--local SkillData = {}

---- ============================================================
----  BASIC ATTACK — Combo 4 hit
---- ============================================================
--SkillData.BasicAttack = {
--	damage    = 15,
--	range     = 7,
--	cooldown  = 0.5,
--	skillType = "melee_single",
--	effectColor = Color3.fromRGB(255, 255, 255),

--	comboCount    = 4,
--	comboDuration = 1.8,
--	comboResetGap = 0.7,

--	animID = {
--		"rbxassetid://71406843055757",
--		"rbxassetid://83917752883957",
--		"rbxassetid://100202037092309",
--		"rbxassetid://77043451646832",
--	},
--	vfxName = "HitPunch",
--	sfxID   = "rbxassetid://101477429954879",
--	voiceID = "0",
--}

---- ============================================================
----  YUJI ITADORI
---- ============================================================
--SkillData.Yuji = {
--	Q = {
--		name      = "Divergent Fist",
--		damage    = 35,
--		range     = 30,
--		radius    = 8,
--		cooldown  = 4,
--		skillType = "melee_aoe",
--		knockback = 40,
--		effectColor = Color3.fromRGB(255, 200, 100),

--		animID  = "rbxassetid://110353067300637",
--		vfxName = "YujiDivergent",
--		sfxID   = "rbxassetid://97819687693023",
--		voiceID = "0",
--	},
--	E = {
--		name      = "Black Flash",
--		damage    = 60,
--		range     = 50,
--		cooldown  = 8,
--		stunTime  = 1.5,
--		skillType = "melee_single",
--		knockback = 20,
--		effectColor = Color3.fromRGB(10, 10, 10),

--		animID  = "rbxassetid://129228903802998",
--		vfxName = "YujiBlackFlash",
--		sfxID   = "rbxassetid://96508237940950",
--		voiceID = "rbxassetid://114351236092594",
--	},
--	R = {
--		name      = "Punisher Kick",
--		damage    = 45,
--		range     = 30,
--		cooldown  = 6,
--		skillType = "melee_single",
--		knockback = 50,
--		effectColor = Color3.fromRGB(255, 120, 60),

--		animID  = "rbxassetid://73995396694442",
--		vfxName = "YujiKick",
--		sfxID   = "rbxassetid://122494961448070",
--		voiceID = "rbxassetid://85245351690271",
--	},
--}

---- ============================================================
----  SATORU GOJO
---- ============================================================
--SkillData.Gojo = {
--	Q = {
--		name      = "Lapse Blue",
--		damage    = 20,
--		radius    = 50,
--		cooldown  = 5,
--		skillType = "pull_aoe",
--		pullForce = 80,
--		effectColor = Color3.fromRGB(80, 150, 255),

--		animID  = "rbxassetid://83536546891612",
--		vfxName = "GojoBlue",
--		sfxID   = "rbxassetid://119871162552831",
--		voiceID = "rbxassetid://107915359628650",
--	},
--	E = {
--		name      = "Reversal Red",
--		damage    = 30,
--		radius    = 40,
--		cooldown  = 5,
--		skillType = "push_aoe",
--		pushForce = 120,
--		effectColor = Color3.fromRGB(255, 60, 60),

--		animID  = "rbxassetid://117887635547299",
--		vfxName = "GojoRed",
--		sfxID   = "rbxassetid://88404685614642",
--		sfxExplosion = "rbxassetid://137742555911504",
--		voiceID = "rbxassetid://131267451700580",
--	},
--	R = {
--		name           = "Hollow Purple",
--		damage         = 120,
--		range          = 125,
--		cooldown       = 15,
--		skillType      = "beam",
--		destroyPillars = true,
--		effectColor    = Color3.fromRGB(180, 80, 255),

--		animID  = "rbxassetid://83367651401286",
--		vfxName = "GojoPurple",
--		sfxID   = "rbxassetid://92183164583405",
--		sfxExplosion = "rbxassetid://139316396351592",
--		voiceID = "rbxassetid://140280722011349",
--	},
--}

---- ============================================================
----  RYOMEN SUKUNA
---- ============================================================
--SkillData.Sukuna = {
--	Q = {
--		name           = "Dismantle",
--		damage         = 20,
--		range          = 15,
--		cooldown       = 5,
--		skillType      = "beam",
--		destroyPillars = true,
--		knockback      = 30,
--		effectColor    = Color3.fromRGB(255, 40, 40),

--		animID  = "rbxassetid://112036829844449",
--		vfxName = "SukunaDismantle",
--		sfxID   = "rbxassetid://122951695254282",
--		voiceID = "rbxassetid://112401600931306",
--	},
--	E = {
--		name           = "Cleave",
--		damage         = 50,
--		radius         = 40,
--		cooldown       = 10,
--		skillType      = "melee_aoe",
--		destroyPillars = true,
--		knockback      = 60,
--		effectColor    = Color3.fromRGB(200, 0, 0),

--		animID  = "rbxassetid://93433196588711",
--		vfxName = "SukunaCleave",
--		sfxID   = "rbxassetid://120117176159409",
--		voiceID = "rbxassetid://98191452727727",
--	},
--	R = {
--		name           = "Fire Arrow",
--		damage         = 100,
--		range          = 100,
--		cooldown       = 30,
--		skillType      = "beam",
--		destroyPillars = true,
--		knockback      = 25,
--		effectColor    = Color3.fromRGB(255, 100, 0),

--		animID    = "rbxassetid://92977197155230",
--		vfxName   = "SukunaArrow",
--		sfxCharge = "rbxassetid://114588589169416",
--		sfxShoot  = "rbxassetid://131784297102472",
--		voiceID   = "rbxassetid://113491080251833",
--	},
--}

--return SkillData