# Module 04: Hit Validation

## The Attack Surface

In most Roblox shooters, the client fires a `RemoteEvent` that says:

> "I hit Player2 in the head at position (X, Y, Z) with weapon M4A1"

An exploiter can fire this remote with anything they want — a fake target, impossible damage, positions across the map. Hit validation is the server verifying every claim in that message.

## What To Validate

Every hit report should be checked against five questions:

### 1. Firerate — "Could they have fired this fast?"

Every weapon has a fire rate. If a weapon fires once per 0.5 seconds, and we receive two shots 0.1 seconds apart, the second shot is invalid.

```lua
local requiredCooldown = settings.FireRate  -- e.g., 0.5
local timeSinceLast = serverTime - state.LastFireTime

if timeSinceLast < (requiredCooldown * 0.75) then
    return  -- reject silently
end
```

**Why 0.75× and not exact?** Network jitter. Two shots fired exactly 0.5s apart on the client might arrive 0.48s apart on the server. The 25% tolerance prevents false flags on legitimate rapid fire.

### Time Balance System

Simple cooldown checks have a problem: if a player's shots arrive slightly fast for 30 shots in a row (just under the threshold), they've effectively gained several free shots.

A **time balance** system tracks surplus time:

```lua
state.TimeBalance += timeSinceLast           -- add real time passed
state.TimeBalance -= requiredCooldown        -- subtract one shot cost

if state.TimeBalance < -0.05 then
    -- They're firing faster than allowed
    return
end

-- Cap the balance so they can't "bank" unlimited shots
state.TimeBalance = math.min(state.TimeBalance, requiredCooldown * 4)
```

This catches slow firerate exploits that individual cooldown checks miss.

### 2. Range — "Could the shot reach that far?"

```lua
local maxRange = weaponConfig.Range * 1.5  -- 50% tolerance
if totalTravelDistance > maxRange then
    return  -- reject
end
```

The 1.5× multiplier accounts for projectile bounces and slight distance miscalculations from ping.

### 3. Hit Position — "Was the hit near the target's body?"

Lag compensation: look up where the target was *when the shot was fired*, not where they are now.

```lua
local ping = player:GetNetworkPing()
local targetTime = hitReport.Timestamp - ping

-- Get historical position from Module 02
local rewoundCFrame = PositionTracker.GetHistoricalCFrame(victimChar, targetTime)
local victimPos = rewoundCFrame.Position

-- How far is the reported hit from the target's actual position?
local distance = (hitReport.HitPosition - victimPos).Magnitude

-- Dynamic tolerance: faster targets and higher latency = bigger window
local combinedVelocity = targetSpeed + shooterSpeed
local latencyWindow = math.min(ping + 0.15, 0.55)
local tolerance = 5.0 + (combinedVelocity * latencyWindow)

if distance > tolerance then
    return  -- hit too far from body, reject
end
```

### 4. Line of Sight — "Was there a wall between them?"

Raycast from the shooter's position to the hit position. If the ray hits solid geometry, the shot should have been blocked.

```lua
local result = workspace:Raycast(shooterOrigin, direction * distance, params)

if result and result.Instance then
    -- Wall in the way
    if weaponConfig.Pierces <= 0 then
        return  -- weapon can't pierce, reject
    end
    -- If it can pierce, check wall thickness
end
```

**Handling piercing weapons:** Track total studs pierced and compare against the weapon's max pierce distance.

**Handling bouncing weapons:** Allow direction changes at reflection points, validate the bounce angle matches the surface normal.

### 5. Target Count — "Did they hit too many targets?"

A single-pellet hitscan weapon should hit at most 1 target (+ pierces + bounces). A shotgun with 8 pellets can hit up to 8.

```lua
local maxAllowed = shotCount * (1 + maxPierces + maxBounces)
if state.HitCount >= maxAllowed then
    return  -- too many hits for this shot
end
```

## Weapon Type Differences

| Type | Validation Strategy |
|------|-------------------|
| Hitscan | Instant raycast replay. Check origin, direction, range, obstacles. |
| Projectile | Validate travel time vs distance. Check if trajectory is physically possible given speed and gravity. |
| Multi-pellet | Each pellet is a separate hit. Cap total hits at pellet count × (1 + pierces). |
| Explosive | Validate explosion center, check if targets are within blast radius. |
| Beam/Energy | Tick-based damage. Validate tick rate, beam lifetime, and total tick count. |

## The Shot Registration Flow

```
Client fires weapon
       │
       ▼
ShotFiredEvent → Server records ShotID + timestamp
       │
Client calculates hits locally
       │
       ▼
ReportHitEvent → Server validates each hit:
       │
       ├─ Firerate check
       ├─ Range check
       ├─ Position check (lag compensated)
       ├─ Line of sight check
       ├─ Target count check
       │
       ▼
  Pass all? → Apply damage
  Fail any? → Reject + add suspicion
```

The `ShotFiredEvent` arrives *before* hit reports. This lets the server know when a shot happened and how many hits to expect. If hits arrive without a matching shot registration, they're held briefly in a queue (network ordering isn't guaranteed) then dropped if no shot arrives.

## Key Takeaway

> Hit validation isn't one check — it's five independent checks that
> each catch a different exploit. Silent aim fails the position check.
> Firerate hacks fail the cooldown check. Wallhacks fail line-of-sight.
> Each layer catches what the others miss.

→ [Next: Module 05 — Statistical Aim Detection](../05-statistical-aim-detection/)
