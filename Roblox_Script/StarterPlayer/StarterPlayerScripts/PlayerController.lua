-- ============================================================
--  PlayerController.lua  (LocalScript, StarterPlayerScripts)
--
--  STEP 3B: Setup kamera agar mengikuti custom rig
--  Akan dikembangkan di Step 4 untuk movement & skill
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local camera    = workspace.CurrentCamera

local Shared    = ReplicatedStorage:WaitForChild("Shared")
local RigReady  = Shared:WaitForChild("RigReady")

-- ============================================================
--  FUNGSI: setupCamera
--  Dipanggil saat server memberitahu rig sudah siap.
--  Mengatur kamera agar mengikuti HumanoidRootPart rig.
-- ============================================================
local function setupCamera(rig)
	print("[PlayerController] Menerima rig: " .. tostring(rig.Name))

	-- Tunggu HumanoidRootPart tersedia di rig
	local hrp = rig:WaitForChild("HumanoidRootPart", 10)
	if not hrp then
		warn("[PlayerController] HumanoidRootPart tidak ditemukan di rig!")
		return
	end

	-- Set CameraSubject ke Humanoid rig
	-- CameraSubject = objek yang diikuti kamera
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
		print("[PlayerController] ✓ CameraSubject diset ke Humanoid rig")
	else
		-- Fallback: ikuti HumanoidRootPart langsung
		camera.CameraSubject = hrp
		print("[PlayerController] ✓ CameraSubject diset ke HumanoidRootPart (fallback)")
	end

	-- Set mode kamera ke "Custom" (kamera mengikuti karakter, bisa diputar)
	camera.CameraType = Enum.CameraType.Custom

	print("[PlayerController] ✓ Kamera siap mengikuti " .. rig.Name)
end

-- ============================================================
--  LISTENER: Terima sinyal dari server saat rig siap
-- ============================================================
RigReady.OnClientEvent:Connect(function(rig)
	print("[PlayerController] RigReady event diterima!")
	setupCamera(rig)
end)

print("[PlayerController] ✓ PlayerController siap — menunggu rig.")