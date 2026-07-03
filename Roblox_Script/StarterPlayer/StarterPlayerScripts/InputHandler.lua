-- ============================================================
--  InputHandler.lua (LocalScript)
--  TAHAP: FASE 2.1 (Fix Sinkronisasi UI & Animasi Wipe Cooldown)
-- ============================================================

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService") -- Tambahan TweenService

local player = Players.LocalPlayer

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local CombatAction = Shared:WaitForChild("CombatAction")
local SkillData    = require(Shared:WaitForChild("SkillData"))

local PlayerGui = player:WaitForChild("PlayerGui")
local GameHUD = PlayerGui:WaitForChild("GameHUD")
local SkillsContainer = GameHUD:WaitForChild("HUDFrame"):WaitForChild("SkillsContainer")

local keyToUISlot = {
	["Q"] = "Skill1",
	["E"] = "Skill2",
	["R"] = "Skill3"
}

-- ============================================================
-- FUNGSI: Setup Nama Jurus Dinamis
-- ============================================================
local function setupSkillNames(charName)
	if not charName or not SkillData[charName] then return end

	local keys = {"Q", "E", "R"}
	for _, key in ipairs(keys) do
		local slotName = keyToUISlot[key]
		local skillUI = SkillsContainer:FindFirstChild(slotName)

		if skillUI then
			local skillName = SkillData[charName][key].name

			-- Ganti teks utama jika UI berupa tombol/label
			if skillUI:IsA("TextLabel") or skillUI:IsA("TextButton") then
				skillUI.Text = skillName
			end

			-- Ganti teks anak (TextLabel) sesuai hierarki screenshot
			local childLabel = skillUI:FindFirstChild("TextLabel")
			if childLabel then
				childLabel.Text = skillName
			end
		end
	end
end

-- TUNGGU HINGGA KARAKTER DIPILIH (Fix Bug Nama Tidak Berubah)
task.spawn(function()
	local charName = player:GetAttribute("SelectedCharacter")
	while not charName do
		task.wait(0.5)
		charName = player:GetAttribute("SelectedCharacter")
	end
	setupSkillNames(charName)
end)

player:GetAttributeChangedSignal("SelectedCharacter"):Connect(function()
	setupSkillNames(player:GetAttribute("SelectedCharacter"))
end)

-- ============================================================
--  COOLDOWN TRACKER & UI ANIMATION WIPE
-- ============================================================
local clientCooldowns = {}

local function isOnCooldownClient(skillKey)
	local last = clientCooldowns[skillKey]
	if not last then return false end

	local charName = player:GetAttribute("SelectedCharacter")
	local cd = 0.5 

	if skillKey == "M1" then
		cd = SkillData.BasicAttack.cooldown
	elseif charName and SkillData[charName] and SkillData[charName][skillKey] then
		cd = SkillData[charName][skillKey].cooldown
	end

	local character = player.Character
	local cdMultiplier = character and character:GetAttribute("CDMultiplier") or 1.0
	cd = cd * cdMultiplier

	return (tick() - last) < cd
end

local function runUICooldown(skillKey, cdDuration)
	local slotName = keyToUISlot[skillKey]
	if not slotName then return end

	local skillUI = SkillsContainer:FindFirstChild(slotName)
	if not skillUI then return end

	local cooldownOverlay = skillUI:FindFirstChild("CooldownOverlay")

	local cooldownText = skillUI:FindFirstChild("CooldownText")
	if not cooldownText then
		cooldownText = Instance.new("TextLabel")
		cooldownText.Name = "CooldownText"
		cooldownText.Size = UDim2.new(1, 0, 1, 0)
		cooldownText.BackgroundTransparency = 1
		cooldownText.TextColor3 = Color3.fromRGB(255, 255, 255)
		cooldownText.TextStrokeTransparency = 0.3

		-- FIX: Teks lebih rapi dan elegan
		cooldownText.TextScaled = false
		cooldownText.TextSize = 22
		cooldownText.Font = Enum.Font.GothamBold
		cooldownText.ZIndex = 10
		cooldownText.Parent = skillUI
	end

	if cooldownOverlay and cooldownText then
		task.spawn(function()
			cooldownOverlay.Visible = true
			cooldownText.Visible = true

			-- FIX ARAH ANIMASI: Pindahkan titik tumpu ke bawah tengah
			cooldownOverlay.AnchorPoint = Vector2.new(0.5, 1)
			cooldownOverlay.Position = UDim2.new(0.5, 0, 1, 0)

			-- Reset ukuran overlay menjadi penuh
			cooldownOverlay.Size = UDim2.new(1, 0, 1, 0)

			-- Efek Wipe: Overlay menyusut ke BAWAH
			local tweenInfo = TweenInfo.new(cdDuration, Enum.EasingStyle.Linear)
			local tween = TweenService:Create(cooldownOverlay, tweenInfo, {Size = UDim2.new(1, 0, 0, 0)})
			tween:Play()

			local timeLeft = cdDuration
			while timeLeft > 0 do
				cooldownText.Text = string.format("%.1f", timeLeft)
				task.wait(0.1)
				timeLeft = timeLeft - 0.1
			end

			cooldownOverlay.Visible = false
			cooldownText.Visible = false
			cooldownOverlay.Size = UDim2.new(1, 0, 1, 0) -- Kembalikan ukuran untuk next cooldown
		end)
	end
end

local function setClientCooldown(skillKey)
	clientCooldowns[skillKey] = tick()

	local charName = player:GetAttribute("SelectedCharacter")
	local baseCD = 0.5
	if charName and SkillData[charName] and SkillData[charName][skillKey] then
		baseCD = SkillData[charName][skillKey].cooldown
	end

	local character = player.Character
	local cdMultiplier = character and character:GetAttribute("CDMultiplier") or 1.0
	local actualCD = baseCD * cdMultiplier

	runUICooldown(skillKey, actualCD)
end

local function fireSkill(skillKey)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if isOnCooldownClient(skillKey) then return end
	local charName = player:GetAttribute("SelectedCharacter")
	if not charName then return end

	CombatAction:FireServer(skillKey, charName)
	setClientCooldown(skillKey)
end

local mouse = player:GetMouse()
mouse.Button1Down:Connect(function()
	if UserInputService:GetFocusedTextBox() then return end
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local charName = player:GetAttribute("SelectedCharacter")
	if not charName then return end

	CombatAction:FireServer("M1", charName)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Q then fireSkill("Q")
	elseif input.KeyCode == Enum.KeyCode.E then fireSkill("E")
	elseif input.KeyCode == Enum.KeyCode.R then fireSkill("R")
	end
end)