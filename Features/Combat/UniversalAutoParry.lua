---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Game.InputClient
local InputClient = require("Game/InputClient")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Utility.Logger
local Logger = require("Utility/Logger")

-- Heuristic fallback auto-parry for attacks that do not have recorded timing data.
-- This is intentionally conservative: it uses animation activity, distance, and
-- closing velocity instead of blindly firing the block remote every frame.
local UniversalAutoParry = {}

-- Services.
local players = game:GetService("Players")
local runService = game:GetService("RunService")

-- State.
local maid = Maid.new()
local animatorMaids = {}
local trackedTracks = {}
local lastParry = 0
local lastCandidate = nil

-- Defaults. These can be overridden by Options when the UI exposes them.
local DEFAULT_RANGE = 12
local DEFAULT_COOLDOWN = 0.22
local DEFAULT_REACTION = 0.10
local DEFAULT_CLOSING_SPEED = 8

local function enabled()
	local toggle = Configuration.expectToggleValue("EnableUniversalAutoParry")
	return toggle == nil or toggle == true
end

local function option(key, default)
	return Configuration.expectOptionValue(key) or default
end

local function localRoot()
	local character = players.LocalPlayer and players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function validEnemy(model)
	local character = players.LocalPlayer and players.LocalPlayer.Character
	if not model or not model:IsA("Model") or model == character then
		return false
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil
end

local function candidateDistance(model)
	local root = localRoot()
	local enemyRoot = model and model:FindFirstChild("HumanoidRootPart")
	if not root or not enemyRoot then
		return nil
	end

	return (enemyRoot.Position - root.Position).Magnitude
end

local function closingSpeed(model)
	local root = localRoot()
	local enemyRoot = model and model:FindFirstChild("HumanoidRootPart")
	if not root or not enemyRoot then
		return 0
	end

	local offset = root.Position - enemyRoot.Position
	if offset.Magnitude <= 0.001 then
		return 0
	end

	local direction = offset.Unit
	return enemyRoot.AssemblyLinearVelocity:Dot(direction)
end

local function shouldParry(model, track)
	if not enabled() or not validEnemy(model) then
		return false
	end

	if not track or not track.IsPlaying or track.Priority == Enum.AnimationPriority.Core then
		return false
	end

	local distance = candidateDistance(model)
	if not distance or distance > option("UniversalParryRange", DEFAULT_RANGE) then
		return false
	end

	-- Require either meaningful closing movement or a very close attacker.
	local speed = closingSpeed(model)
	if distance > 6 and speed < option("UniversalParryClosingSpeed", DEFAULT_CLOSING_SPEED) then
		return false
	end

	-- Avoid treating long idle/emote tracks as attacks.
	local length = track.Length
	if length > 0 and length > 8 then
		return false
	end

	return true
end

local function parry(model, track)
	local now = os.clock()
	local cooldown = option("UniversalParryCooldown", DEFAULT_COOLDOWN)
	if now - lastParry < cooldown then
		return
	end

	if not shouldParry(model, track) then
		return
	end

	lastParry = now
	lastCandidate = model

	-- Delay by a small reaction window so the fallback does not always parry
	-- on the first animation frame of a long wind-up.
	task.delay(option("UniversalParryReaction", DEFAULT_REACTION), function()
		if not enabled() then
			return
		end

		if not validEnemy(model) or not track.IsPlaying then
			return
		end

		local distance = candidateDistance(model)
		if not distance or distance > option("UniversalParryRange", DEFAULT_RANGE) then
			return
		end

		InputClient.deflect()
	end)
end

local function watchAnimator(animator)
	if animatorMaids[animator] then
		return
	end

	local animatorMaid = Maid.new()
	animatorMaids[animator] = animatorMaid

	animatorMaid:add(animator.AnimationPlayed:Connect(function(track)
		local entity = animator:FindFirstAncestorOfClass("Model")
		if not validEnemy(entity) then
			return
		end

		trackedTracks[track] = entity
		parry(entity, track)

		local stopped = track.Stopped:Connect(function()
			trackedTracks[track] = nil
		end)
		animatorMaid:add(stopped)
	end))
end

function UniversalAutoParry.init()
	maid:add(workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Animator") then
			watchAnimator(descendant)
		end
	end))

	for _, descendant in next, workspace:GetDescendants() do
		if descendant:IsA("Animator") then
			watchAnimator(descendant)
		end
	end

	-- A lightweight fallback pass catches attacks whose animation starts before
	-- the animator connection is established and also adapts to closing targets.
	maid:add(runService.Heartbeat:Connect(function()
		if not enabled() then
			return
		end

		for track, entity in next, trackedTracks do
			if shouldParry(entity, track) then
				parry(entity, track)
			end
		end
	end))

	Logger.warn("Universal auto-parry initialized.")
end

function UniversalAutoParry.detach()
	for animator, animatorMaid in next, animatorMaids do
		animatorMaid:clean()
		animatorMaids[animator] = nil
	end

	trackedTracks = {}
	lastCandidate = nil
	maid:clean()

	Logger.warn("Universal auto-parry detached.")
end

return UniversalAutoParry
