local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local AutoParry = {}
AutoParry.enabled = false
AutoParry.lastParryTime = 0
AutoParry.incomingAttacks = {}

-- Gets injected from Main.lua
local GameConfig = nil

function AutoParry.init(config)
	GameConfig = config
end

function AutoParry:detectAttack(otherPlayer)
	local char = otherPlayer.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return false end
	
	local root = char.HumanoidRootPart
	local vel = root.AssemblyLinearVelocity.Magnitude
	
	if GameConfig.AttackDetectionMethod == "velocity" then
		return vel > GameConfig.VelocityThreshold
	elseif GameConfig.AttackDetectionMethod == "animation" then
		-- Type Soul uses animation tracking elsewhere, return true if anim detected
		return false -- placeholder
	end
	return false
end

function AutoParry:recordAttack(otherPlayer)
	local char = otherPlayer.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end
	
	table.insert(self.incomingAttacks, {
		attacker = otherPlayer,
		root = char.HumanoidRootPart,
		time = tick(),
	})
end

function AutoParry:executeParry()
	VirtualInputManager:SendKeyEvent(true, GameConfig.ParryInput, false, game)
	wait(0.05)
	VirtualInputManager:SendKeyEvent(false, GameConfig.ParryInput, false, game)
	self.lastParryTime = tick()
end

function AutoParry:update()
	if not self.enabled then return end
	
	local player = Players.LocalPlayer
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end
	
	local playerRoot = char.HumanoidRootPart
	local now = tick()
	
	-- Detect incoming attacks
	for _, otherPlayer in pairs(Players:GetPlayers()) do
		if otherPlayer == player then continue end
		
		local otherChar = otherPlayer.Character
		if not otherChar or not otherChar:FindFirstChild("HumanoidRootPart") then continue end
		
		local otherRoot = otherChar.HumanoidRootPart
		local distance = (playerRoot.Position - otherRoot.Position).Magnitude
		
		if distance > GameConfig.DetectionRange then continue end
		if not self:detectAttack(otherPlayer) then continue end
		
		self:recordAttack(otherPlayer)
	end
	
	-- Clean old attacks
	for i = #self.incomingAttacks, 1, -1 do
		if now - self.incomingAttacks[i].time > 1.0 then
			table.remove(self.incomingAttacks, i)
		end
	end
	
	-- Execute parry if ready
	if (now - self.lastParryTime) 
