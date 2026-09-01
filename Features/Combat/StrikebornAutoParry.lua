-- Strikeborn-specific auto parry.
-- This module is deliberately isolated from the Type Soul timing database.
local StrikebornAutoParry = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LOCAL_PLAYER = Players.LocalPlayer
local PLACE_ID = 80167904212435

-- Strikeborn's public controls are still subject to change during early access.
-- Change this if your client uses another defensive key.
local PARRY_KEY = Enum.KeyCode.F

-- Tune these values in live testing. They intentionally err toward a small
-- reaction window instead of blindly parrying every animation.
local MAX_DISTANCE = 32
local PARRY_COOLDOWN = 0.18
local PARRY_LEAD = 0.035
local TRACK_MIN_LENGTH = 0.08

-- Put confirmed Strikeborn attack animation IDs here as strings.
-- Example: ["rbxassetid://123456789"] = true,
local ATTACK_ANIMATION_IDS = {}

-- Fallback for clients/builds where the animation asset has a useful name.
local ATTACK_NAME_PATTERNS = {
	"m1",
	"attack",
	"punch",
	"kick",
	"slash",
	"swing",
	"strike",
	"combo",
}

local connection
local characterConnections = {}
local lastParry = 0
local watchedTracks = {}

local function clearConnections()
	for _, c in next, characterConnections do
		c:Disconnect()
	end
	table.clear(characterConnections)
	table.clear(watchedTracks)
end

local function getRoot(character)
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function inRange(character)
	local localCharacter = LOCAL_PLAYER.Character
	local localRoot = getRoot(localCharacter)
	local root = getRoot(character)
	if not localRoot or not root then
		return false
	end

	return (root.Position - localRoot.Position).Magnitude <= MAX_DISTANCE
end

local function containsAttackPattern(value)
	if type(value) ~= "string" then
		return false
	end

	value = value:lower()
	for _, pattern in next, ATTACK_NAME_PATTERNS do
		if value:find(pattern, 1, true) then
			return true
		end
	end

	return false
end

local function isAttackTrack(track)
	if not track or not track.Animation then
		return false
	end

	local animationId = tostring(track.Animation.AnimationId)
	if ATTACK_ANIMATION_IDS[animationId] then
		return true
	end

	return containsAttackPattern(track.Name) or containsAttackPattern(track.Animation.Name)
end

local function parry()
	local now = os.clock()
	if now - lastParry < PARRY_COOLDOWN then
		return
	end

	lastParry = now
	VirtualInputManager:SendKeyEvent(true, PARRY_KEY, false, game)
	VirtualInputManager:SendKeyEvent(false, PARRY_KEY, false, game)
end

local function watchAnimator(character, animator)
	if character == LOCAL_PLAYER.Character then
		return
	end

	local played = animator.AnimationPlayed:Connect(function(track)
		if watchedTracks[track] then
			return
		end
		watchedTracks[track] = true

		if not isAttackTrack(track) or not inRange(character) then
			return
		end

		-- Wait for the track to actually start before calculating its impact point.
		local length = track.Length
		if length <= TRACK_MIN_LENGTH then
			parry()
			return
		end

		local speed = math.max(track.Speed, 0.01)
		local waitTime = math.max((length / speed) - PARRY_LEAD, 0)
		task.delay(waitTime, function()
			if not track.IsPlaying then
				return
			end
			if inRange(character) then
				parry()
			end
		end)
	end)

	table.insert(characterConnections, played)
end

local function watchCharacter(character)
	if character == LOCAL_PLAYER.Character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			watchAnimator(character, animator)
		end

		table.insert(characterConnections, humanoid.ChildAdded:Connect(function(child)
			if child:IsA("Animator") then
				watchAnimator(character, child)
			end
		end))
	end
end

function StrikebornAutoParry.init()
	if game.PlaceId ~= PLACE_ID then
		return
	end

	clearConnections()

	for _, player in next, Players:GetPlayers() do
		if player ~= LOCAL_PLAYER and player.Character then
			watchCharacter(player.Character)
		end

		if player ~= LOCAL_PLAYER then
			table.insert(characterConnections, player.CharacterAdded:Connect(function(character)
				watchCharacter(character)
			end))
		end
	end

	connection = RunService.Heartbeat:Connect(function()
		if game.PlaceId ~= PLACE_ID then
			return
		end
	end)
end

function StrikebornAutoParry.detach()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	clearConnections()
end

return StrikebornAutoParry
