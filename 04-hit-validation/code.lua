--[[
	HitValidator (Server ModuleScript)
	
	Validates every hit report from the client against five checks:
	1. Firerate — is the shot too fast?
	2. Range — did the shot travel too far?
	3. Position — was the hit near the target's actual body?
	4. Line of sight — was there a wall in the way?
	5. Target count — did they hit too many things with one shot?
	
	USAGE:
	  local HitValidator = require(path.to.HitValidator)
	  
	  -- In your RemoteEvent handler:
	  ReportHitEvent.OnServerEvent:Connect(function(player, hitReport)
	      HitValidator.Validate(player, hitReport)
	  end)
	
	REQUIRES:
	  - PositionTracker (Module 02) for lag compensation
	  - PunishmentService (Module 06) for scoring
	  - Your weapon config system (adapt GetWeaponConfig)
]]

local HitValidator = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- REPLACE THESE with your actual module paths
local PositionTracker = require(game.ServerStorage.Anticheat.PositionTracker)
local PunishmentService = require(game.ServerStorage.Anticheat.PunishmentService)

local DEBUG = true

-- ════════════════════════════════════════════════════════════════
-- CONFIG
-- ════════════════════════════════════════════════════════════════

local CONFIG = {
	MAX_PING         = 0.8,     -- reject hits from extremely laggy players
	MAX_HIT_AGE      = 1.5,     -- seconds old a hit can be
	STAB_MAX_RANGE   = 12.0,    -- melee range limit

	-- Scoring
	PTS_FIRERATE     = 5,
	PTS_RANGE        = 10,
	PTS_POSITION     = 5,
	PTS_LOS          = 10,
	PTS_IMPOSSIBLE   = 0,       -- 0 = definitive kick (bypasses scoring)

	-- Thresholds (same as MovementValidator)
	FLAG_AT          = 20,
	SUPPRESS_AT      = 40,
	KICK_AT          = 65,
	DECAY_AMOUNT     = 3,
	DECAY_INTERVAL   = 4,
}

-- ════════════════════════════════════════════════════════════════
-- PLAYER STATE
-- ════════════════════════════════════════════════════════════════

local PlayerState = {}  -- [UserId] = { [WeaponName] = weaponState }
local PlayerScores = {} -- [UserId] = { Score, Flagged, Suppressed }

local function GetWeaponState(userId, weaponName)
	if not PlayerState[userId] then PlayerState[userId] = {} end
	if not PlayerState[userId][weaponName] then
		PlayerState[userId][weaponName] = {
			LastFireTime = 0,
			TimeBalance  = 0,
			LastShotID   = "",
			HitCount     = 0,
			ActiveShots  = {},   -- [ShotID] = serverTime
			ShotTargets  = {},   -- [ShotID] = { [character] = true }
		}
	end
	return PlayerState[userId][weaponName]
end

local function GetScoreData(userId)
	if not PlayerScores[userId] then
		PlayerScores[userId] = { Score = 0, Flagged = false, Suppressed = false }
	end
	return PlayerScores[userId]
end

-- ════════════════════════════════════════════════════════════════
-- SCORING
-- ════════════════════════════════════════════════════════════════

local function AddScore(player, points, reason, definitive)
	if definitive then
		PunishmentService.AutoKick(player, reason, "Hit Validation")
		return
	end

	local data = GetScoreData(player.UserId)
	data.Score += points
	if DEBUG then warn(string.format("[HitAC] %s +%d (%d/%d): %s", player.Name, points, data.Score, CONFIG.KICK_AT, reason)) end

	if data.Score >= CONFIG.KICK_AT then
		local ping = player:GetNetworkPing()
		if ping > 0.25 then
			PunishmentService.Flag(player, "Suppressed (lag): " .. reason, "Hit Validation", { Ping = ping })
			data.Score = CONFIG.FLAG_AT
		else
			PunishmentService.AutoKick(player, reason, "Hit Validation")
			data.Score = 0; data.Flagged = false; data.Suppressed = false
		end
	elseif data.Score >= CONFIG.SUPPRESS_AT and not data.Suppressed then
		data.Suppressed = true
		PunishmentService.Flag(player, "Hit suspicious: " .. reason, "Hit Validation")
	elseif data.Score >= CONFIG.FLAG_AT and not data.Flagged then
		data.Flagged = true
		PunishmentService.Flag(player, "Hit watch: " .. reason, "Hit Validation")
	end
end

-- Decay loop
task.spawn(function()
	while true do
		task.wait(CONFIG.DECAY_INTERVAL)
		for _, data in pairs(PlayerScores) do
			if data.Score > 0 then data.Score = math.max(0, data.Score - CONFIG.DECAY_AMOUNT) end
			if data.Score < CONFIG.FLAG_AT then data.Flagged = false end
			if data.Score < CONFIG.SUPPRESS_AT then data.Suppressed = false end
		end
	end
end)

-- ════════════════════════════════════════════════════════════════
-- WEAPON CONFIG (ADAPT THIS TO YOUR GAME)
-- ════════════════════════════════════════════════════════════════

--[[
	You need to provide a function that returns weapon settings
	given a tool instance. This is game-specific.
	
	Expected return format:
	{
	    FireRate       = 0.1,        -- seconds between shots
	    Range          = 500,        -- max range in studs
	    Damage         = 25,         -- base damage
	    ShotCount      = 1,          -- pellets per shot (shotgun = 8)
	    Pierces        = 0,          -- max wall pierces
	    Bounces        = 0,          -- max bounces
	    HeadshotMult   = 1.5,        -- headshot multiplier
	    FireMode       = "Auto",     -- Auto/Semi/Burst/Charge/Energy
	    Mode           = "Hitscan",  -- Hitscan/Projectile
	    
	    -- Optional
	    BurstCount     = 3,
	    BurstRate      = 0.05,
	    ChargeTime     = 0.5,
	    ExplosionRadius = 0,
	    DamagePerTick   = nil,       -- beam weapons
	    MeleeDamage     = nil,       -- knife stab
	}
]]

local function GetWeaponConfig(tool)
	-- REPLACE THIS with your actual weapon config lookup
	-- Example: read from ModuleScript in ReplicatedStorage
	local weaponType = tool:GetAttribute("WeaponType")
	local effectName = tool:GetAttribute("Effect")
	if not weaponType or not effectName then return nil end

	-- Your implementation here
	-- local module = require(path.to.weapon.effects[effectName])
	-- return module.Settings

	return nil -- placeholder
end

-- ════════════════════════════════════════════════════════════════
-- CHECK 1: FIRERATE
-- ════════════════════════════════════════════════════════════════

local function CheckFirerate(player, state, config, shotID, serverTime)
	if shotID == state.LastShotID then return true end -- same shot, multiple hits

	local requiredCooldown = config.FireRate or 0.1
	if config.FireMode == "Burst" then requiredCooldown = config.BurstRate or 0.05 end
	if config.FireMode == "Charge" then requiredCooldown = config.ChargeTime or 0.5 end

	local timePassed = serverTime - state.LastFireTime
	state.LastFireTime = serverTime

	-- Time balance system: tracks surplus time to catch slow firerate exploits
	state.TimeBalance = math.min(
		(state.TimeBalance or 0) + timePassed,
		math.max(1.0, requiredCooldown * 4)
	)

	if state.TimeBalance >= (requiredCooldown - 0.05) then
		state.TimeBalance -= requiredCooldown
		state.LastShotID = shotID
		state.HitCount = 1
		state.ShotTargets[shotID] = {}
		return true
	else
		AddScore(player, CONFIG.PTS_FIRERATE, "Firerate exceeded", false)
		return false
	end
end

-- ════════════════════════════════════════════════════════════════
-- CHECK 2: RANGE
-- ════════════════════════════════════════════════════════════════

local function CheckRange(player, shooterPos, hitPos, config)
	local maxRange = (config.Range or 1500) * 1.5  -- 50% tolerance
	local distance = (hitPos - shooterPos).Magnitude

	if distance <= maxRange then return true end

	if distance > maxRange * 2 then
		AddScore(player, CONFIG.PTS_RANGE, string.format("Impossible range %.0f/%.0f", distance, maxRange), false)
	end
	return false
end

-- ════════════════════════════════════════════════════════════════
-- CHECK 3: HIT POSITION (lag compensated)
-- ════════════════════════════════════════════════════════════════

local function CheckHitPosition(player, hitReport, victimChar, shooterChar, config)
	local ping = math.clamp(player:GetNetworkPing(), 0.05, 0.8)
	local targetTime = hitReport.Timestamp - ping

	-- Rewind victim to where they were when the shooter fired
	local rewoundCFrame = PositionTracker.GetHistoricalCFrame(victimChar, targetTime)
	local victimPos = rewoundCFrame.Position

	-- Calculate dynamic tolerance
	local targetVel = victimChar.PrimaryPart and victimChar.PrimaryPart.AssemblyLinearVelocity.Magnitude or 0
	local shooterVel = shooterChar.PrimaryPart and shooterChar.PrimaryPart.AssemblyLinearVelocity.Magnitude or 0
	local combinedVel = math.min(targetVel + shooterVel, 80)
	local latencyWindow = math.min(ping + 0.15, 0.55)

	local tolerance = 5.0 + (combinedVel * latencyWindow)

	-- Fast-firing weapons get extra tolerance (more network jitter)
	if config.FireRate and config.FireRate < 0.1 then
		tolerance += math.clamp((0.1 - config.FireRate) / 0.1 * 5, 0, 5)
	end

	local distance = (hitReport.HitPosition - victimPos).Magnitude
	if distance <= tolerance then return true end

	-- Only score if clearly outside tolerance on low-speed targets
	if combinedVel < 20 and (distance - tolerance) > 5 then
		AddScore(player, CONFIG.PTS_POSITION, string.format("Hitbox miss by %.1f studs", distance - tolerance), false)
	end

	return false
end

-- ════════════════════════════════════════════════════════════════
-- CHECK 4: LINE OF SIGHT
-- ════════════════════════════════════════════════════════════════

local function CheckLineOfSight(player, shooterPos, hitPos, shooterChar, victimChar, config)
	local direction = (hitPos - shooterPos)
	local distance = direction.Magnitude
	if distance < 0.1 then return true end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { shooterChar, victimChar }
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.CollisionGroup = "Raycast"

	local result = workspace:Raycast(shooterPos, direction.Unit * distance, params)

	if not result then return true end -- clear LOS

	-- Wall in the way — check if weapon can pierce
	local maxPierces = config.Pierces or 0
	if maxPierces <= 0 then
		-- Close to victim? Might be edge of hitbox clipping geometry
		local distToVictim = (result.Position - victimChar.PrimaryPart.Position).Magnitude
		if distToVictim <= 3.5 then return true end

		AddScore(player, CONFIG.PTS_LOS, "Shot blocked by wall", false)
		return false
	end

	return true -- weapon can pierce, allow it (pierce depth checked separately)
end

-- ════════════════════════════════════════════════════════════════
-- CHECK 5: TARGET COUNT
-- ════════════════════════════════════════════════════════════════

local function CheckTargetCount(player, state, shotID, victimChar, config, isExplosion)
	local shotCount = config.ShotCount or 1
	local maxPierces = config.Pierces or 0
	local maxBounces = config.Bounces or 0

	local maxAllowed = shotCount * (1 + maxPierces + maxBounces)
	if isExplosion then maxAllowed += 20 end -- explosions hit many targets

	if state.HitCount >= maxAllowed then return false end
	state.HitCount += 1

	-- Track unique targets per shot (non-explosion only)
	if not isExplosion and state.ShotTargets[shotID] then
		local targets = state.ShotTargets[shotID]
		if not targets[victimChar] then
			local count = 0
			for _ in pairs(targets) do count += 1 end
			local maxTargets = 1 + maxPierces + maxBounces
			if count >= maxTargets then return false end
			targets[victimChar] = true
		end
	end

	return true
end

-- ════════════════════════════════════════════════════════════════
-- MAIN VALIDATION ENTRY POINT
-- ════════════════════════════════════════════════════════════════

--- Register a shot being fired (call from ShotFiredEvent handler).
-- Must be called BEFORE hit reports arrive for this shot.
function HitValidator.RegisterShot(player, weaponName, shotID)
	local state = GetWeaponState(player.UserId, weaponName)
	state.ActiveShots[shotID] = workspace:GetServerTimeNow()

	-- Prune old shots
	local now = workspace:GetServerTimeNow()
	for id, time in pairs(state.ActiveShots) do
		if now - time > 15 then
			state.ActiveShots[id] = nil
			state.ShotTargets[id] = nil
		end
	end
end

--- Validate a hit report from the client.
-- @param player      Player who reported the hit
-- @param hitReport   Table with: Target (Model), HitPosition (Vector3),
--                    HitInstance (BasePart), Timestamp (number),
--                    WeaponName (string), ShotID (string),
--                    IsExplosion (bool), IsStab (bool)
-- @return boolean    true if hit is valid, false if rejected
function HitValidator.Validate(player, hitReport)
	-- Basic sanity
	local ping = player:GetNetworkPing()
	if ping > CONFIG.MAX_PING then return false end

	local serverTime = workspace:GetServerTimeNow()
	local age = serverTime - (hitReport.Timestamp or serverTime)
	if age > CONFIG.MAX_HIT_AGE or age < -0.2 then return false end

	local shooterChar = player.Character
	local victimChar = hitReport.Target
	if not shooterChar or not shooterChar.PrimaryPart then return false end
	if not victimChar or not victimChar.PrimaryPart then return false end

	local hum = victimChar:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end

	-- Get weapon config
	local weaponName = hitReport.WeaponName
	if type(weaponName) ~= "string" then return false end

	local tool = shooterChar:FindFirstChild(weaponName) or player.Backpack:FindFirstChild(weaponName)
	if not tool then return false end

	local config = GetWeaponConfig(tool)
	if not config then return false end

	-- Definitive checks (impossible actions = instant kick)
	if hitReport.IsExplosion and not config.ExplosionRadius then
		AddScore(player, CONFIG.PTS_IMPOSSIBLE, "Spoofed explosion", true)
		return false
	end

	local state = GetWeaponState(player.UserId, weaponName)
	local isExplosion = hitReport.IsExplosion or false
	local isStab = hitReport.IsStab or false

	-- Get positions
	local timeFired = state.ActiveShots[hitReport.ShotID] or hitReport.Timestamp
	local rewoundShooterCFrame = PositionTracker.GetHistoricalCFrame(shooterChar, timeFired)
	local shooterPos = rewoundShooterCFrame.Position

	-- Run all five checks
	-- 1. Firerate
	if not isStab and not CheckFirerate(player, state, config, hitReport.ShotID, serverTime) then
		return false
	end

	-- 2. Range (skip for melee)
	if not isStab and not isExplosion then
		if not CheckRange(player, shooterPos, hitReport.HitPosition, config) then
			return false
		end
	end

	-- 3. Hit position (skip for self-damage)
	if shooterChar ~= victimChar then
		if isExplosion then
			local maxRadius = (config.ExplosionRadius or 5) + 10
			local dist = (hitReport.HitPosition - victimChar.PrimaryPart.Position).Magnitude
			if dist > maxRadius then return false end
		elseif isStab then
			if (hitReport.HitPosition - shooterPos).Magnitude > CONFIG.STAB_MAX_RANGE + 10 then
				AddScore(player, CONFIG.PTS_POSITION, "Melee range bypass", false)
				return false
			end
		else
			if not CheckHitPosition(player, hitReport, victimChar, shooterChar, config) then
				return false
			end
		end
	end

	-- 4. Line of sight (skip for explosions and melee)
	if not isExplosion and not isStab and shooterChar ~= victimChar then
		if not CheckLineOfSight(player, shooterPos, hitReport.HitPosition, shooterChar, victimChar, config) then
			return false
		end
	end

	-- 5. Target count
	if not CheckTargetCount(player, state, hitReport.ShotID, victimChar, config, isExplosion) then
		return false
	end

	return true -- all checks passed
end

-- ════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════

Players.PlayerRemoving:Connect(function(player)
	PlayerState[player.UserId] = nil
	PlayerScores[player.UserId] = nil
end)

return HitValidator
