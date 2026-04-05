--[[
	MovementValidator (Server ModuleScript)
	
	Detects: Speedhack, Flyhack, Noclip
	Requires: PunishmentService (Module 06)
	
	USAGE:
	  local MV = require(path.to.MovementValidator)
	  
	  -- Call these hooks from your game systems:
	  MV.OnDash(player)
	  MV.OnKnockback(player, duration)
	  MV.OnTeleport(player)
	  MV.OnScaleChange(player)
	  MV.ResetPlayer(player)
]]

local MovementValidator = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- REPLACE THIS PATH with your actual PunishmentService location
local PunishmentService = require(game.ServerStorage.Anticheat.PunishmentService)

local DEBUG = true

-- ════════════════════════════════════════════════════════════════
-- CONFIGURATION (tune these for your game)
-- ════════════════════════════════════════════════════════════════

local CONFIG = {
	SAMPLE_RATE       = 0.3,   -- seconds between checks

	-- Speed
	SPEED_BUFFER      = 18,    -- flat studs/s tolerance
	BURST_EXTRA       = 45,    -- extra buffer during dash/knockback grace

	-- Fly
	AIRBORNE_THRESHOLD  = 2.5, -- seconds before suspicious
	GRAVITY_MULTIPLIER  = 5.0, -- threshold multiplier if gravity modified
	GROUND_RAY_DIST     = 10,  -- downward raycast length

	-- Noclip
	NOCLIP_MIN_DIST    = 4,    -- minimum travel to check
	NOCLIP_WALL_DEPTH  = 3,    -- studs past wall to flag

	-- Point values
	PTS_SPEED_MINOR    = 3,
	PTS_SPEED_MAJOR    = 7,
	PTS_FLY_HOVER      = 5,
	PTS_FLY_RISING     = 8,
	PTS_NOCLIP         = 12,

	-- Thresholds
	FLAG_AT     = 15,
	SUPPRESS_AT = 35,
	KICK_AT     = 55,

	-- Decay
	DECAY_AMOUNT   = 3,
	DECAY_INTERVAL = 5,

	-- Grace durations
	GRACE_SPAWN      = 3.0,
	GRACE_TELEPORT   = 2.0,
	GRACE_DASH       = 0.6,
	GRACE_KNOCKBACK  = 1.5,
	GRACE_ADMIN      = 1.0,
	GRACE_SCALE      = 1.5,
}

-- ════════════════════════════════════════════════════════════════
-- STATE
-- ════════════════════════════════════════════════════════════════

local States = {}

local function NewState()
	return {
		LastPos = nil, LastTime = 0,
		AirborneStart = 0, IsAirborne = false,
		Score = 0, Flagged = false, Suppressed = false,
		Graces = {}, NoclipCooldown = 0,
	}
end

-- ════════════════════════════════════════════════════════════════
-- GRACE PERIODS
-- ════════════════════════════════════════════════════════════════

function MovementValidator.GrantGrace(player, duration, tag)
	local s = States[player.UserId]
	if not s then return end
	table.insert(s.Graces, { Expires = workspace:GetServerTimeNow() + duration, Tag = tag })
end

local function HasGrace(s, now, tag)
	for i = #s.Graces, 1, -1 do
		if s.Graces[i].Expires < now then
			table.remove(s.Graces, i)
		elseif not tag or s.Graces[i].Tag == tag then
			return true
		end
	end
	return false
end

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

-- Override these if your admin system uses different attribute names
local function IsAdminExempt(player)
	return player:GetAttribute("Admin_Fly") == true
		or player:GetAttribute("Admin_Freeze") == true
end

-- Check for server-applied gravity modifiers
-- Tag your VectorForces with :SetAttribute("_sv", true)
local function HasGravityModifier(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	for _, child in ipairs(hrp:GetChildren()) do
		if child:IsA("VectorForce") and child:GetAttribute("_sv") then
			return true
		end
	end
	return false
end

local function GetExpectedSpeed(player, character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return 50 end
	local speed = hum.WalkSpeed
	local scale = character:GetScale()
	local jump = hum.JumpPower or 50
	local effective = speed * math.max(scale, 0.5)
	return math.max(effective, jump * 0.7)
end

local function IsGrounded(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and hum.FloorMaterial ~= Enum.Material.Air then return true end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return true end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude
	return workspace:Raycast(hrp.Position, Vector3.new(0, -CONFIG.GROUND_RAY_DIST, 0), params) ~= nil
end

-- ════════════════════════════════════════════════════════════════
-- SCORING
-- ════════════════════════════════════════════════════════════════

local function AddScore(player, points, reason, definitive)
	local s = States[player.UserId]
	if not s then return end

	if definitive then
		PunishmentService.AutoKick(player, reason, "Movement AC")
		return
	end

	s.Score += points
	if DEBUG then warn(string.format("[MovementAC] %s +%d (%d/%d): %s", player.Name, points, s.Score, CONFIG.KICK_AT, reason)) end

	if s.Score >= CONFIG.KICK_AT then
		if player:GetNetworkPing() > 0.25 then
			PunishmentService.Flag(player, "Movement (high ping): " .. reason, "Movement AC")
			s.Score = CONFIG.FLAG_AT
		else
			PunishmentService.AutoKick(player, reason, "Movement AC")
			s.Score = 0; s.Flagged = false; s.Suppressed = false
		end
	elseif s.Score >= CONFIG.SUPPRESS_AT and not s.Suppressed then
		s.Suppressed = true
		PunishmentService.Flag(player, "Movement suspicious: " .. reason, "Movement AC")
	elseif s.Score >= CONFIG.FLAG_AT and not s.Flagged then
		s.Flagged = true
		PunishmentService.Flag(player, "Movement watch: " .. reason, "Movement AC")
	end
end

-- ════════════════════════════════════════════════════════════════
-- CHECKS
-- ════════════════════════════════════════════════════════════════

local function CheckSpeed(player, char, s, pos, dt, now)
	if IsAdminExempt(player) then return end
	if HasGrace(s, now) then return end
	if not s.LastPos then return end

	local dx = Vector3.new(pos.X - s.LastPos.X, 0, pos.Z - s.LastPos.Z)
	local speed = dx.Magnitude / dt
	local expected = GetExpectedSpeed(player, char)
	local ping = player:GetNetworkPing()
	local tolerance = CONFIG.SPEED_BUFFER + (ping * 35)

	if HasGrace(s, now, "Dash") or HasGrace(s, now, "Knockback") then
		tolerance += CONFIG.BURST_EXTRA
	end

	local cap = expected + tolerance
	if speed <= cap then return end

	local ratio = speed / math.max(cap, 1)
	if ratio > 3.0 then
		AddScore(player, CONFIG.PTS_SPEED_MAJOR, string.format("Speed %.0f/%.0f (%.1fx)", speed, cap, ratio))
	elseif ratio > 1.5 then
		AddScore(player, CONFIG.PTS_SPEED_MINOR + 2, string.format("Speed %.0f/%.0f", speed, cap))
	else
		AddScore(player, CONFIG.PTS_SPEED_MINOR, string.format("Speed %.0f/%.0f", speed, cap))
	end
end

local function CheckFly(player, char, s, pos, now)
	if IsAdminExempt(player) then return end
	if HasGrace(s, now) then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.PlatformStand then return end

	if IsGrounded(char) then
		s.IsAirborne = false; s.AirborneStart = 0; return
	end

	if not s.IsAirborne then s.IsAirborne = true; s.AirborneStart = now end

	local airTime = now - s.AirborneStart
	local threshold = CONFIG.AIRBORNE_THRESHOLD
	if HasGravityModifier(char) then threshold *= CONFIG.GRAVITY_MULTIPLIER end
	if airTime < threshold then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local vy = hrp.AssemblyLinearVelocity.Y

	if vy < -5 then return end -- falling = legit

	if vy > 8 then
		AddScore(player, CONFIG.PTS_FLY_RISING, string.format("Rising vy=%.0f after %.1fs", vy, airTime))
	elseif airTime > threshold * 2 then
		AddScore(player, CONFIG.PTS_FLY_HOVER, string.format("Hovering %.1fs", airTime))
	end
end

local function CheckNoclip(player, char, s, pos, now)
	if IsAdminExempt(player) then return end
	if HasGrace(s, now) then return end
	if now < s.NoclipCooldown or not s.LastPos then return end

	local delta = pos - s.LastPos
	if delta.Magnitude < CONFIG.NOCLIP_MIN_DIST then return end

	s.NoclipCooldown = now + 0.5

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(s.LastPos, delta.Unit * delta.Magnitude, params)
	if not result or not result.Instance then return end

	local part = result.Instance
	if not part.CanCollide or part.Transparency >= 1 then return end
	if part.CollisionGroup == "VisualEffects" then return end

	local pastWall = delta.Magnitude - (result.Position - s.LastPos).Magnitude
	if pastWall < CONFIG.NOCLIP_WALL_DEPTH then return end

	AddScore(player, CONFIG.PTS_NOCLIP, string.format("Noclip through %s (%.0f studs)", part.Name, pastWall))
end

-- ════════════════════════════════════════════════════════════════
-- MAIN LOOP
-- ════════════════════════════════════════════════════════════════

function MovementValidator.Start()
	-- Decay loop
	task.spawn(function()
		while true do
			task.wait(CONFIG.DECAY_INTERVAL)
			for _, s in pairs(States) do
				if s.Score > 0 then s.Score = math.max(0, s.Score - CONFIG.DECAY_AMOUNT) end
				if s.Score < CONFIG.FLAG_AT then s.Flagged = false end
				if s.Score < CONFIG.SUPPRESS_AT then s.Suppressed = false end
			end
		end
	end)

	-- Validation loop
	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		for _, player in ipairs(Players:GetPlayers()) do
			local s = States[player.UserId]
			if not s then continue end
			local char = player.Character
			if not char then continue end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not hrp or not hum or hum.Health <= 0 then s.LastPos = nil; continue end
			local dt = now - s.LastTime
			if dt < CONFIG.SAMPLE_RATE then continue end

			local pos = hrp.Position
			CheckSpeed(player, char, s, pos, dt, now)
			CheckFly(player, char, s, pos, now)
			CheckNoclip(player, char, s, pos, now)
			s.LastPos = pos; s.LastTime = now
		end
	end)
end

-- ════════════════════════════════════════════════════════════════
-- PUBLIC HOOKS (call from your game systems)
-- ════════════════════════════════════════════════════════════════

function MovementValidator.OnDash(player) MovementValidator.GrantGrace(player, CONFIG.GRACE_DASH, "Dash") end
function MovementValidator.OnUpdraft(player) MovementValidator.GrantGrace(player, 1.2, "Knockback") end
function MovementValidator.OnKnockback(player, dur) MovementValidator.GrantGrace(player, dur or CONFIG.GRACE_KNOCKBACK, "Knockback") end
function MovementValidator.OnTeleport(player) MovementValidator.GrantGrace(player, CONFIG.GRACE_TELEPORT, "Teleport") end
function MovementValidator.OnScaleChange(player) MovementValidator.GrantGrace(player, CONFIG.GRACE_SCALE, "Scale") end

function MovementValidator.ResetPlayer(player)
	local s = States[player.UserId]
	if s then s.Score = math.floor(s.Score * 0.5); s.Flagged = false; s.Suppressed = false end
end

-- ════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════

Players.PlayerAdded:Connect(function(player)
	States[player.UserId] = NewState()
	player.CharacterAdded:Connect(function()
		local s = States[player.UserId]
		if s then s.LastPos = nil; s.IsAirborne = false; s.Graces = {} end
		MovementValidator.GrantGrace(player, CONFIG.GRACE_SPAWN, "Spawn")
	end)
end)

Players.PlayerRemoving:Connect(function(player) States[player.UserId] = nil end)
for _, p in ipairs(Players:GetPlayers()) do States[p.UserId] = NewState() end

MovementValidator.Start()
return MovementValidator
