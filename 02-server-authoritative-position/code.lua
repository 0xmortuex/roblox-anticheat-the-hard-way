--[[
	PositionTracker (Server ModuleScript)
	
	Records player positions at fixed intervals for:
	1. Movement validation (speed/fly/noclip checks)
	2. Lag compensation (historical position lookups for hit validation)
	
	Usage:
	  local PositionTracker = require(path.to.PositionTracker)
	  
	  -- Get where a character was 200ms ago:
	  local pastCFrame = PositionTracker.GetHistoricalCFrame(character, serverTime - 0.2)
]]

local PositionTracker = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- CONFIG
local MAX_HISTORY_SECONDS = 1.5   -- how far back we can look
local SAMPLE_INTERVAL = 0.1       -- seconds between samples

-- STORAGE (weak keys = auto cleanup when character is destroyed)
local positionHistory = setmetatable({}, { __mode = "k" })

local lastSampleTime = 0

-- ════════════════════════════════════════════════════════════════
-- CORE: Record a position sample
-- ════════════════════════════════════════════════════════════════

local function sampleCharacter(character, now)
	if not character or not character.Parent then
		positionHistory[character] = nil
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		positionHistory[character] = nil
		return
	end

	-- Initialize history table if needed
	local history = positionHistory[character]
	if not history then
		history = {}
		positionHistory[character] = history
	end

	-- Record this sample
	table.insert(history, {
		Time = now,
		CFrame = hrp.CFrame,
	})

	-- Prune old entries
	local cutoff = 0
	for i = 1, #history do
		if now - history[i].Time > MAX_HISTORY_SECONDS then
			cutoff = i
		else
			break
		end
	end

	if cutoff > 0 then
		local newLen = #history - cutoff
		for i = 1, newLen do
			history[i] = history[i + cutoff]
		end
		for i = newLen + 1, #history do
			history[i] = nil
		end
	end
end

-- ════════════════════════════════════════════════════════════════
-- PUBLIC: Look up a historical position
-- ════════════════════════════════════════════════════════════════

--- Get the CFrame of a character at a specific past time.
-- Interpolates between the two nearest samples.
-- @param character  Model
-- @param targetTime number (server time)
-- @return CFrame
function PositionTracker.GetHistoricalCFrame(character, targetTime)
	if not targetTime then
		return character.PrimaryPart and character:GetPrimaryPartCFrame()
			or character:GetPivot()
	end

	local history = positionHistory[character]
	if not history or #history == 0 then
		return character.PrimaryPart and character:GetPrimaryPartCFrame()
			or character:GetPivot()
	end

	-- Find the two samples that bracket the target time
	local newer, older
	for i = #history, 1, -1 do
		local record = history[i]
		if record.Time >= targetTime then
			newer = record
		else
			older = record
			break
		end
	end

	-- Edge cases: target is outside our history range
	if not older and not newer then
		return character:GetPrimaryPartCFrame()
	end
	if not older then return newer.CFrame end
	if not newer then return older.CFrame end
	if newer.Time == older.Time then return newer.CFrame end

	-- Interpolate between the two samples
	local alpha = (targetTime - older.Time) / (newer.Time - older.Time)
	return older.CFrame:Lerp(newer.CFrame, alpha)
end

--- Get the latest recorded position for a character.
-- @param character  Model
-- @return Vector3 or nil
function PositionTracker.GetLastPosition(character)
	local history = positionHistory[character]
	if history and #history > 0 then
		return history[#history].CFrame.Position
	end
	return nil
end

--- Get the latest two samples for velocity calculation.
-- @param character  Model
-- @return Vector3 lastPos, Vector3 currentPos, number dt (or nil)
function PositionTracker.GetMovementDelta(character)
	local history = positionHistory[character]
	if not history or #history < 2 then return nil end

	local current = history[#history]
	local previous = history[#history - 1]

	return previous.CFrame.Position, current.CFrame.Position, current.Time - previous.Time
end

--- Clear history for a character (call on death/respawn).
-- @param character  Model
function PositionTracker.ClearHistory(character)
	positionHistory[character] = nil
end

-- ════════════════════════════════════════════════════════════════
-- MAIN LOOP
-- ════════════════════════════════════════════════════════════════

RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	if now - lastSampleTime < SAMPLE_INTERVAL then return end
	lastSampleTime = now

	-- Sample all player characters
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			sampleCharacter(player.Character, now)
		end
	end

	-- Sample tagged dummies (NPCs, training targets)
	for _, dummy in ipairs(CollectionService:GetTagged("Dummy")) do
		sampleCharacter(dummy, now)
	end
end)

-- Cleanup on character removal
Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function(character)
		positionHistory[character] = nil
	end)
end)

return PositionTracker
