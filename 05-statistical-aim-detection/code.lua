--[[
	StatisticalAC (Server ModuleScript)
	
	Detects aimbot through statistical analysis of accuracy, headshot rate,
	and hit position variance over time.
	
	Uses Bayesian smoothing to prevent low-sample false positives and
	z-score anomaly detection against a globally-learned player baseline.
	
	USAGE:
	  local StatAC = require(path.to.StatisticalAC)
	  StatAC.Init(player)
	  StatAC.RegisterShot(player, tool, shotConfig, pelletCount)
	  StatAC.RegisterHit(player, hitData)
	  StatAC.Save(player)
	
	REQUIRES:
	  - PunishmentService (Module 06)
	  - DataStoreService for persistent baselines
]]

local StatisticalAC = {}

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local PunishmentService = require(game.ServerStorage.Anticheat.PunishmentService)

local ACStore = DataStoreService:GetDataStore("ACS_History_V1")
local GlobalStore = DataStoreService:GetDataStore("ACS_Global_V1")

local DEBUG = true

-- ════════════════════════════════════════════════════════════════
-- CONFIG
-- ════════════════════════════════════════════════════════════════

local CONFIG = {
	BUCKET_DURATION  = 1.0,      -- seconds per accuracy bucket
	BAYESIAN_WEIGHT  = 12,       -- how much to trust global average

	WINDOWS = { Short = 10, Long = 30 },
	MIN_SHOTS = { Short = 10, Long = 30, Session = 80 },

	-- Hard limits (Bayesian-smoothed accuracy/HSR above these = suspicious)
	HARD_LIMITS = {
		Short_MaxAcc = 0.82, Short_MaxHSR = 0.75,
		Long_MaxAcc  = 0.72, Long_MaxHSR  = 0.65,
		Session_MaxAcc = 0.65, Session_MaxHSR = 0.60,
	},

	-- Z-score triggers
	Z_TRIGGER_ACC = 2.7,
	Z_TRIGGER_HSR = 2.7,
	MIN_VARIANCE  = 0.02,  -- bone-lock detection

	SUSPICION_THRESHOLD = 100,
	STRIKES_BEFORE_FLAG = 1,
}

-- ════════════════════════════════════════════════════════════════
-- GLOBAL BASELINES (learned from all players)
-- ════════════════════════════════════════════════════════════════

local GlobalStats = { MeanAcc = 0.35, MeanHSR = 0.20, StdDev = 0.15, TotalSamples = 100 }

task.spawn(function()
	pcall(function()
		local data = GlobalStore:GetAsync("GlobalAverages")
		if data then GlobalStats = data end
		if DEBUG then
			print(string.format("[StatAC] Global baselines: Acc=%.0f%% HSR=%.0f%%",
				GlobalStats.MeanAcc * 100, GlobalStats.MeanHSR * 100))
		end
	end)
end)

-- ════════════════════════════════════════════════════════════════
-- MATH HELPERS
-- ════════════════════════════════════════════════════════════════

local function GetZScore(val, mean, stdDev)
	if stdDev <= 0.001 then stdDev = 0.15 end
	return (val - mean) / stdDev
end

local function GetVariance(list)
	if #list < 5 then return 1.0 end
	local sum = 0
	for _, v in ipairs(list) do sum += v end
	local mean = sum / #list
	local sumSq = 0
	for _, v in ipairs(list) do sumSq += (v - mean) ^ 2 end
	return sumSq / #list
end

local function BayesianSmooth(hits, pellets, heads, globalMeanAcc, globalMeanHSR, weight)
	local smoothPellets = pellets + weight
	local smoothHits = hits + (weight * globalMeanAcc)
	local smoothHeads = heads + (weight * globalMeanAcc * globalMeanHSR)

	local acc = smoothHits / smoothPellets
	local hsr = smoothHits > 0 and (smoothHeads / smoothHits) or 0
	return acc, hsr
end

local function RollingAverage(currentAvg, currentCount, batchAvg, batchCount)
	local total = currentCount + batchCount
	if total == 0 then return currentAvg, 0 end
	local weighted = ((currentAvg * currentCount) + (batchAvg * batchCount)) / total
	if total > 100000 then total = 100000 end
	return weighted, total
end

-- ════════════════════════════════════════════════════════════════
-- SESSION STATE
-- ════════════════════════════════════════════════════════════════

local Sessions = {}

function StatisticalAC.Init(player)
	local ok, data = pcall(function() return ACStore:GetAsync(tostring(player.UserId)) end)
	Sessions[player] = {
		BucketHistory  = {},
		CurrentBucket  = nil,
		ShotToBucket   = {},
		ShotMaxHits    = {},
		ShotHitCounts  = {},

		SessionPellets = 0, SessionHits = 0, SessionHeads = 0,
		SessionDistances = {},

		LifeHits     = (ok and data and data.Hits) or 0,
		LifePellets  = (ok and data and data.Pellets) or 0,
		LifeHeads    = (ok and data and data.Headshots) or 0,

		Strikes = 0, Suspicion = 0, ActiveFlags = {},
		UnanalyzedBuckets = 0,
	}
end

function StatisticalAC.Save(player)
	local s = Sessions[player]
	if not s then return end

	pcall(function()
		ACStore:SetAsync(tostring(player.UserId), {
			Hits = s.LifeHits, Pellets = s.LifePellets, Headshots = s.LifeHeads
		})
	end)

	-- Contribute session data to global baselines
	if s.SessionPellets >= 50 then
		pcall(function()
			GlobalStore:UpdateAsync("GlobalAverages", function(old)
				local g = old or GlobalStats
				local batchAcc = s.SessionPellets > 0 and (s.SessionHits / s.SessionPellets) or g.MeanAcc
				local batchHSR = s.SessionHits > 0 and (s.SessionHeads / s.SessionHits) or g.MeanHSR
				g.MeanAcc, g.TotalSamples = RollingAverage(g.MeanAcc, g.TotalSamples, batchAcc, 1)
				g.MeanHSR = RollingAverage(g.MeanHSR, g.TotalSamples, batchHSR, 1)
				g.MeanAcc = math.clamp(g.MeanAcc, 0.15, 0.50)
				g.MeanHSR = math.clamp(g.MeanHSR, 0.05, 0.40)
				return g
			end)
		end)
	end

	Sessions[player] = nil
end

-- ════════════════════════════════════════════════════════════════
-- SHOT & HIT REGISTRATION
-- ════════════════════════════════════════════════════════════════

function StatisticalAC.RegisterShot(player, tool, shotConfig, pelletCount)
	local s = Sessions[player]
	if not s then return end

	-- Skip explosion/tick damage (not meaningful for accuracy)
	if shotConfig.ExplodeOnHit or shotConfig.DamagePerTick then return end

	local count = math.max(1, pelletCount or 1)
	local shotID = shotConfig.ShotID
	local now = os.clock()

	-- Bucket management
	if not s.CurrentBucket or (now - s.CurrentBucket.StartTime >= CONFIG.BUCKET_DURATION) then
		if s.CurrentBucket and s.CurrentBucket.Pellets > 0 then
			table.insert(s.BucketHistory, s.CurrentBucket)
			s.UnanalyzedBuckets += 1

			if #s.BucketHistory > CONFIG.WINDOWS.Long then
				table.remove(s.BucketHistory, 1)
			end

			if s.UnanalyzedBuckets >= 3 then
				s.UnanalyzedBuckets = 0
				StatisticalAC.Analyze(player)
			end
		end
		s.CurrentBucket = { StartTime = now, Pellets = 0, Hits = 0, Heads = 0, Distances = {} }
	end

	s.CurrentBucket.Pellets += count
	s.ShotToBucket[shotID] = s.CurrentBucket
	s.ShotMaxHits[shotID] = count
	s.ShotHitCounts[shotID] = 0
	s.SessionPellets += count
	s.LifePellets += count
end

function StatisticalAC.RegisterHit(player, hitData)
	local s = Sessions[player]
	if not s then return end
	if hitData.Explosion or hitData.IsTickDamage then return end

	local bucket = s.ShotToBucket[hitData.ShotID]
	if not bucket then return end

	local isHead = hitData.HitInstance and hitData.HitInstance.Name == "Head"
	local shotID = hitData.ShotID

	-- Enforce max hits per shot (prevents hit spoofing from inflating accuracy)
	local maxHits = s.ShotMaxHits[shotID] or 1
	s.ShotHitCounts[shotID] = (s.ShotHitCounts[shotID] or 0) + 1

	if s.ShotHitCounts[shotID] <= maxHits then
		bucket.Hits += 1
		s.SessionHits += 1
		s.LifeHits += 1

		if isHead then
			bucket.Heads += 1
			s.SessionHeads += 1
			s.LifeHeads += 1
		end
	end

	-- Record hit position offset for variance calculation
	if hitData.HitInstance then
		local relPos = hitData.HitInstance.CFrame:PointToObjectSpace(hitData.HitPosition)
		local flatOffset = Vector2.new(relPos.X, relPos.Z).Magnitude
		table.insert(bucket.Distances, flatOffset)
		table.insert(s.SessionDistances, flatOffset)

		-- Cap distance list
		if #s.SessionDistances > 1000 then
			local new = {}
			for i = #s.SessionDistances - 499, #s.SessionDistances do
				table.insert(new, s.SessionDistances[i])
			end
			s.SessionDistances = new
		end
	end
end

-- ════════════════════════════════════════════════════════════════
-- ANALYSIS
-- ════════════════════════════════════════════════════════════════

local function GetWindowData(history, count)
	local start = math.max(1, #history - count + 1)
	local p, h, hd, d = 0, 0, 0, {}
	for i = start, #history do
		p += history[i].Pellets
		h += history[i].Hits
		hd += history[i].Heads
		for _, dist in ipairs(history[i].Distances) do table.insert(d, dist) end
	end
	return p, h, hd, d
end

function StatisticalAC.Analyze(player)
	local s = Sessions[player]
	if not s or s.SessionPellets < 3 then return end

	local suspicion = 0
	local reasons = {}

	-- Short window
	local p_S, h_S, hd_S, d_S = GetWindowData(s.BucketHistory, CONFIG.WINDOWS.Short)
	if p_S >= CONFIG.MIN_SHOTS.Short then
		local acc, hsr = BayesianSmooth(h_S, p_S, hd_S, GlobalStats.MeanAcc, GlobalStats.MeanHSR, CONFIG.BAYESIAN_WEIGHT)
		if acc > CONFIG.HARD_LIMITS.Short_MaxAcc then suspicion += 50; table.insert(reasons, "Short Acc") end
		if hsr > CONFIG.HARD_LIMITS.Short_MaxHSR and h_S >= 8 then suspicion += 50; table.insert(reasons, "Short HSR") end
	end

	-- Long window
	local p_L, h_L, hd_L, d_L = GetWindowData(s.BucketHistory, CONFIG.WINDOWS.Long)
	if p_L >= CONFIG.MIN_SHOTS.Long then
		local acc, hsr = BayesianSmooth(h_L, p_L, hd_L, GlobalStats.MeanAcc, GlobalStats.MeanHSR, CONFIG.BAYESIAN_WEIGHT)
		if acc > CONFIG.HARD_LIMITS.Long_MaxAcc then suspicion += 40; table.insert(reasons, "Long Acc") end

		local accZ = GetZScore(acc, GlobalStats.MeanAcc, GlobalStats.StdDev)
		local hsrZ = GetZScore(hsr, GlobalStats.MeanHSR, GlobalStats.StdDev)

		if accZ > CONFIG.Z_TRIGGER_ACC then suspicion += math.floor(accZ * 12); table.insert(reasons, string.format("Acc Z=%.1f", accZ)) end
		if hsrZ > CONFIG.Z_TRIGGER_HSR and h_L >= 12 then suspicion += math.floor(hsrZ * 12); table.insert(reasons, string.format("HSR Z=%.1f", hsrZ)) end

		local variance = GetVariance(d_L)
		if variance < CONFIG.MIN_VARIANCE then suspicion += 60; table.insert(reasons, string.format("Bone Lock var=%.4f", variance)) end
	end

	-- Session window
	if s.SessionPellets >= CONFIG.MIN_SHOTS.Session then
		local acc, hsr = BayesianSmooth(s.SessionHits, s.SessionPellets, s.SessionHeads, GlobalStats.MeanAcc, GlobalStats.MeanHSR, CONFIG.BAYESIAN_WEIGHT)
		if acc > CONFIG.HARD_LIMITS.Session_MaxAcc then suspicion += 60; table.insert(reasons, "Session Acc") end
		if hsr > CONFIG.HARD_LIMITS.Session_MaxHSR and s.SessionHits >= 35 then suspicion += 60; table.insert(reasons, "Session HSR") end

		local var = GetVariance(s.SessionDistances)
		if var < CONFIG.MIN_VARIANCE * 1.5 then suspicion += 60; table.insert(reasons, "Session Bone Lock") end
	end

	-- Apply suspicion
	if suspicion > 0 then
		s.Suspicion += suspicion
		for _, r in ipairs(reasons) do
			if not table.find(s.ActiveFlags, r) then table.insert(s.ActiveFlags, r) end
		end
	else
		s.Suspicion = math.max(0, s.Suspicion - 10)
		if s.Suspicion == 0 then s.ActiveFlags = {} end
	end

	-- Strike check
	if s.Suspicion >= CONFIG.SUSPICION_THRESHOLD then
		s.Strikes += 1
		local reason = table.concat(s.ActiveFlags, ", ")

		if s.Strikes >= CONFIG.STRIKES_BEFORE_FLAG then
			PunishmentService.Flag(player, "Statistical triggers (Strike " .. s.Strikes .. "): " .. reason, "Statistical AC", {
				Strikes = s.Strikes, Suspicion = s.Suspicion
			})
		end

		if DEBUG then
			warn(string.format("[StatAC] %s STRIKE #%d: %s", player.Name, s.Strikes, reason))
		end

		s.Suspicion = 0
		s.ActiveFlags = {}
	end
end

-- ════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════

Players.PlayerAdded:Connect(function(player) StatisticalAC.Init(player) end)
Players.PlayerRemoving:Connect(function(player) StatisticalAC.Save(player) end)
for _, p in ipairs(Players:GetPlayers()) do StatisticalAC.Init(p) end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do StatisticalAC.Save(player) end
	pcall(function() GlobalStore:SetAsync("GlobalAverages", GlobalStats) end)
end)

return StatisticalAC
