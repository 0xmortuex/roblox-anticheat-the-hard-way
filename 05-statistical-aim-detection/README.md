# Module 05: Statistical Aim Detection

## Why Hit Validation Isn't Enough

Module 04 catches impossible shots — hits through walls, out of range, faster than the firerate allows. But a smart aimbot doesn't do impossible things. It locks onto heads *just within* the valid hit window. Every individual shot looks legitimate.

Statistical detection catches aimbots by looking at **patterns over time**, not individual events.

## The Core Idea

No human hits 70% headshots over 200 shots. No human maintains 90% accuracy with a fast-firing SMG. But an aimbot can — and that's what makes it detectable.

We track three metrics per player:

| Metric | What It Measures | Why It Catches Aimbots |
|--------|-----------------|----------------------|
| **Accuracy** | Hits ÷ Pellets fired | Aimbots rarely miss |
| **Headshot Rate (HSR)** | Headshots ÷ Hits | Aimbots lock to head |
| **Hit Variance** | Spread of hit positions on the body | Aimbots hit the same spot repeatedly |

## Bayesian Smoothing

Raw accuracy is noisy. A player who fires 3 shots and hits 3 has 100% accuracy — but that tells us nothing. We need **more data** before we get suspicious.

Bayesian smoothing mixes the player's stats with the **global average** of all players, weighted by sample size:

```lua
-- Global averages (learned from all players over time)
local globalMeanAcc = 0.35  -- average player hits 35% of shots
local globalMeanHSR = 0.20  -- average headshot rate is 20%

local BAYESIAN_WEIGHT = 12  -- how much we trust the global average

-- Smoothed accuracy = mix of player data and global average
local smoothedHits = playerHits + (BAYESIAN_WEIGHT * globalMeanAcc)
local smoothedPellets = playerPellets + BAYESIAN_WEIGHT
local smoothedAccuracy = smoothedHits / smoothedPellets
```

With 3 shots: `(3 + 12×0.35) / (3 + 12) = 0.48` — barely above average.
With 100 shots at 80%: `(80 + 4.2) / (100 + 12) = 0.75` — clearly suspicious.

The more shots we see, the less the global average matters and the more the player's real stats dominate.

## Z-Score Anomaly Detection

A z-score measures how many standard deviations a value is from the mean. In plain terms: how weird is this player compared to everyone else?

```lua
local function GetZScore(value, mean, stdDev)
    if stdDev <= 0.001 then stdDev = 0.15 end  -- safety floor
    return (value - mean) / stdDev
end

-- Example: player has 65% smoothed accuracy
-- Global mean is 35%, stddev is 15%
-- Z-score = (0.65 - 0.35) / 0.15 = 2.0 → 2 standard deviations above average
```

**Thresholds:**
- z < 2.0 → normal
- z 2.0–2.7 → watch closely
- z > 2.7 → flag for suspicion

These thresholds are deliberately conservative. We'd rather miss a subtle aimbot than ban a legitimately good player.

## Bone-Lock Variance

The most subtle aimbot signature. When a human aims at a head, they hit slightly different spots each time — the nose, the ear, the forehead. When an aimbot locks to a hitbox center, it hits the same coordinate repeatedly.

```lua
-- Collect the offset from hitbox center for each hit
local offsets = {}
for _, hit in ipairs(hitData) do
    local relPos = hit.Part.CFrame:PointToObjectSpace(hit.Position)
    local flatOffset = Vector2.new(relPos.X, relPos.Z).Magnitude
    table.insert(offsets, flatOffset)
end

-- Calculate variance (spread)
local variance = GetVariance(offsets)

-- Suspiciously low variance = hits are clustered in one spot
if variance < 0.02 then
    -- Probable aimbot lock
end
```

A legitimate player typically has variance > 0.1. An aimbot often shows variance < 0.02.

## Time Windows

Checking entire-session stats is too slow to catch toggling aimbots (players who turn the aimbot on for 30 seconds, then off). We use multiple windows:

| Window | Duration | Purpose |
|--------|----------|---------|
| **Short** | Last 10 buckets (~10s) | Catches toggle aimbots |
| **Long** | Last 30 buckets (~30s) | Catches sustained aimbots |
| **Session** | Entire playtime | Catches subtle, low-profile aimbots |

Each window has its own accuracy and HSR thresholds. Short windows tolerate higher spikes (could be a lucky streak), session windows are stricter (luck evens out over time).

## Weapon-Adaptive Limits

A shotgun (8 pellets, wide spread) naturally has higher accuracy than a sniper (1 shot, tiny hitbox). Fixed thresholds don't work.

```lua
-- Adapt accuracy limits to weapon characteristics
local slowBonus = math.clamp((fireRate - 0.1) * 0.25, 0, 0.30)
local shotgunBonus = (shotCount > 3) and 0.35 or 0

local maxAccuracy = 0.60 + slowBonus + shotgunBonus
```

A slow sniper allows up to ~90% accuracy (skilled players can legitimately hit that). A fast SMG caps around 60%. A shotgun caps around 95% (hard to miss at close range with 8 pellets).

## Global Learning

The global average isn't hardcoded — it **learns from your player population**:

```lua
-- Every player's session stats get batch-uploaded to a DataStore
-- On server close, the global means are updated:
GlobalStats.MeanAcc = rollingAverage(oldMean, oldSamples, batchMean, batchCount)
```

As more players play, the baselines become more accurate, and the z-score thresholds become more meaningful.

## Range Anomaly Detection

Advanced aimbots are detectable by *where* headshots happen. Humans land fewer headshots at long range. Aimbots don't care about distance.

Calculate the headshot rate for shots in the top 25% of distance. If it's *higher* than the overall HSR, that's a strong aimbot indicator — humans get worse at range, not better.

## Key Takeaway

> Individual shots can look perfect. Patterns can't.
> A human who hits 80% headshots for 200 consecutive shots
> doesn't exist. Math catches what per-shot validation misses.

→ [Next: Module 06 — Punishment Escalation](../06-punishment-escalation/README.md)
