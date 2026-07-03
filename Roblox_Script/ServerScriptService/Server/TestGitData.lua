local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

-- Memanggil module SkillData (Otomatis mendownload dari Git saat dipanggil)
local SkillData = require(Shared:WaitForChild("SkillData"))

-- Tunggu sebentar untuk memastikan proses sinkronisasi selesai
task.wait(2) 

print("\n====================================")
print("  BUKTI DATA GITHUB (DATA-DRIVEN) ")
print("====================================")
print("Nama Skill Q Gojo :", SkillData.Gojo.Q.name)
print("Damage Q Gojo     :", SkillData.Gojo.Q.damage)
print("Cooldown Q Gojo :", SkillData.Gojo.Q.cooldown)
print("====================================\n")