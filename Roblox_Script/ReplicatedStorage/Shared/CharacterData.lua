-- ============================================================
--  CharacterData.lua  (ModuleScript)
--  Menyimpan HumanoidDescription ID untuk tiap karakter JJK.
--
--  CARA CARI ASSET ID GRATIS:
--  1. Buka https://www.roblox.com/catalog
--  2. Cari nama item (misal "Yuji Itadori shirt")
--  3. Filter: Price = Free, Type = Clothing
--  4. Klik item → lihat angka di URL: roblox.com/catalog/[ANGKA INI]/...
--  5. Angka itu = Asset ID-nya
--
--  ID di bawah adalah PLACEHOLDER — ganti dengan ID asli
--  yang kamu temukan di Marketplace setelah verifikasi.
-- ============================================================

local CharacterData = {}

CharacterData.Characters = {

	-- --------------------------------------------------------
	--  YUJI ITADORI
	--  Tampilan: rambut hitam pendek, hoodie merah muda/putih
	-- --------------------------------------------------------
	Yuji = {
		DisplayName = "Yuji Itadori",
		Description = "Vessel of Ryomen Sukuna.\nSuperhuman strength & Black Flash.",
		ThemeColor  = Color3.fromRGB(220, 80, 80),
		SkillInfo   = "[Q] Divergent Fist    [E] Black Flash",

		-- HumanoidDescription Properties
		-- Ganti angka 0 dengan Asset ID asli dari Marketplace
		Appearance = {
			-- WAJAH: cari "Yuji face" atau gunakan default face
			Face         = 0,

			-- RAMBUT: cari "black spiky hair" free
			-- Contoh pencarian: "anime black hair roblox free"
			HairAccessory = 0,

			-- BAJU ATAS (Shirt): cari "pink hoodie" atau "Yuji shirt"
			-- Harus berupa Shirt asset, bukan T-Shirt
			Shirt        = 0,

			-- CELANA (Pants): cari "dark pants free roblox"
			Pants        = 0,

			-- WARNA KULIT: Yuji berkulit terang
			BodyColors = {
				HeadColor   = Color3.fromRGB(255, 220, 177),
				TorsoColor  = Color3.fromRGB(255, 220, 177),
				LeftArmColor  = Color3.fromRGB(255, 220, 177),
				RightArmColor = Color3.fromRGB(255, 220, 177),
				LeftLegColor  = Color3.fromRGB(255, 220, 177),
				RightLegColor = Color3.fromRGB(255, 220, 177),
			}
		}
	},

	-- --------------------------------------------------------
	--  SATORU GOJO
	--  Tampilan: rambut putih panjang, baju hitam, kacamata
	-- --------------------------------------------------------
	Gojo = {
		DisplayName = "Satoru Gojo",
		Description = "The Strongest Sorcerer.\nSix Eyes & Limitless.",
		ThemeColor  = Color3.fromRGB(100, 160, 255),
		SkillInfo   = "[Q] Lapse Blue    [E] Reversal Red    [R] Hollow Purple",

		Appearance = {
			Face          = 0,       -- cari "calm face" atau "bishounen face"
			HairAccessory = 0,       -- cari "white long hair free"
			Shirt         = 0,       -- cari "black turtleneck shirt"
			Pants         = 0,       -- cari "black pants"
			BodyColors = {
				HeadColor     = Color3.fromRGB(255, 220, 177),
				TorsoColor    = Color3.fromRGB(255, 220, 177),
				LeftArmColor  = Color3.fromRGB(255, 220, 177),
				RightArmColor = Color3.fromRGB(255, 220, 177),
				LeftLegColor  = Color3.fromRGB(255, 220, 177),
				RightLegColor = Color3.fromRGB(255, 220, 177),
			}
		}
	},

	-- --------------------------------------------------------
	--  RYOMEN SUKUNA
	--  Tampilan: tato merah, rambut pink/putih, kimono gelap
	-- --------------------------------------------------------
	Sukuna = {
		DisplayName = "Ryomen Sukuna",
		Description = "King of Curses.\nDismantle & Cleave destroy everything.",
		ThemeColor  = Color3.fromRGB(180, 40, 40),
		SkillInfo   = "[Q] Dismantle    [E] Cleave",

		Appearance = {
			Face          = 0,       -- cari "sinister face" atau "villain face"
			HairAccessory = 0,       -- cari "pink spiky hair free"
			Shirt         = 0,       -- cari "dark kimono shirt" atau "maroon shirt"
			Pants         = 0,       -- cari "dark hakama pants"
			BodyColors = {
				-- Sukuna punya tato merah di tubuhnya
				-- Kita simulasikan dengan warna kulit yang sedikit lebih gelap
				HeadColor     = Color3.fromRGB(240, 200, 160),
				TorsoColor    = Color3.fromRGB(220, 180, 140),
				LeftArmColor  = Color3.fromRGB(220, 180, 140),
				RightArmColor = Color3.fromRGB(220, 180, 140),
				LeftLegColor  = Color3.fromRGB(220, 180, 140),
				RightLegColor = Color3.fromRGB(220, 180, 140),
			}
		}
	},
}

-- Urutan tampil di UI
CharacterData.Order = {"Yuji", "Gojo", "Sukuna"}

return CharacterData