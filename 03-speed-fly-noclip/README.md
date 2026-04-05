# Module 03: Speed, Fly & Noclip Detection

## Three Checks, One Loop

Using the position samples from Module 02, we run three independent checks every 0.3 seconds per player. Each produces a suspicion score (Module 06), not an instant ban.

## Speed Detection

**What we check:** Horizontal distance traveled between samples, divided by time elapsed.

**Why horizontal only?** Vertical speed is handled by fly detection. Mixing them causes false positives from jumping and falling.

```lua
local dx = Vector3.new(pos.X - lastPos.X, 0, pos.Z - lastPos.Z)
local speed = dx.Magnitude / dt
```

**What's "too fast"?** It depends on the player's current state:

```
Expected speed = WalkSpeed × Scale factor
Tolerance      = base buffer + (ping × multiplier)
Cap            = expected + tolerance
```

The server already knows `WalkSpeed` because it's a server-authoritative property. Gamemodes set it, skills modify it, admin commands override it — all on the server. We just read it.

### The Tolerance Problem

Without tolerance, every player on bad WiFi gets flagged. The buffer needs to account for:

| Source | Extra Tolerance |
|--------|----------------|
| Base physics jitter | +18 studs/s flat |
| Network latency | +ping × 35 studs/s |
| Active dash/knockback | +45 studs/s during grace |

A player with 200ms ping gets about 25 studs/s extra tolerance. An exploiter doing 200+ speed still gets caught easily.

### Severity Scaling

Not all speed violations are equal:

```
1.0x–1.5x over cap → minor (3 pts) — could be lag spike
1.5x–3.0x over cap → moderate (5 pts) — suspicious
3.0x+ over cap     → major (7 pts) — almost certainly hacking
```

## Fly Detection

**What we check:** How long a player has been airborne without a legitimate reason.

**Step 1: Is the player grounded?**

```lua
-- Primary check: Roblox's built-in floor detection
if humanoid.FloorMaterial ~= Enum.Material.Air then
    return true  -- grounded
end

-- Fallback: downward raycast (catches edges, thin platforms)
local result = workspace:Raycast(hrp.Position, Vector3.new(0, -10, 0), params)
return result ~= nil
```

**Step 2: Track airborne duration.**

If they leave the ground, start a timer. If they touch ground again, reset it.

**Step 3: Flag if airborne too long.**

Default threshold: **2.5 seconds.** Beyond that, check vertical velocity:

- `vy < -5` → they're falling. Legit long fall. Skip.
- `vy > 8` → they're rising without any force source. Flag as fly. (+8 pts)
- `vy ≈ 0` for 5+ seconds → hovering. Flag. (+5 pts)

### Gravity Modifiers

Games with low-gravity modes (think "Moon Walker" perk) break this immediately. A player in 0.5× gravity stays airborne 2–3× longer naturally.

**Solution:** Detect VectorForce instances on the HRP that modify gravity. If found, multiply the airborne threshold by 5×.

```lua
local function HasGravityModifier(character)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    for _, child in ipairs(hrp:GetChildren()) do
        if child:IsA("VectorForce") and child:GetAttribute("_sv") then
            return true  -- server-applied gravity modifier exists
        end
    end
    return false
end
```

Tag your gravity forces with `_sv` (server-verified) so the anticheat knows they're legitimate.

## Noclip Detection

**What we check:** Did the player pass through solid geometry between two position samples?

```lua
local delta = currentPos - lastPos
local result = workspace:Raycast(lastPos, delta.Unit * delta.Magnitude, params)
```

If the ray hits a solid, collidable wall, and the player ended up on the other side of it, they clipped through.

### False Positive Prevention

Not everything that blocks a raycast should trigger noclip detection:

```lua
-- Skip non-collidable parts
if not part.CanCollide then return end

-- Skip transparent parts (visual effects)
if part.Transparency >= 1 then return end

-- Skip visual collision groups
if part.CollisionGroup == "VisualEffects" then return end

-- Skip short distances (physics jitter)
if delta.Magnitude < 4 then return end

-- Skip thin walls (player might have squeezed past)
local pastWall = totalDist - distToWall
if pastWall < 3 then return end
```

Noclip is the hardest to detect cleanly because Roblox physics occasionally pushes players through thin geometry. The 3-stud minimum penetration depth prevents most false flags.

## The Grace Period System

This is the most important part of the entire module. Without grace periods, legitimate abilities trigger the anticheat.

A **grace period** is a time window where checks are skipped or softened. Other game systems call hooks to create them:

```lua
-- Skill system calls this when a player dashes:
MovementValidator.OnDash(player)  -- creates 0.6s grace

-- Knockback system calls this when a player is launched:
MovementValidator.OnKnockback(player)  -- creates 1.5s grace

-- Automatic: character spawn
-- Automatic: admin attribute changes
```

During a grace period, the speed check doesn't flag. This prevents:
- Dash → speed flag
- Explosion knockback → speed flag
- Teleport → noclip flag
- Admin fly toggle → fly flag
- Respawn → everything flag

**Grace periods don't disable checks forever.** They expire. If a player is still going 200 speed 2 seconds after a dash, they get caught.

## Key Takeaway

> Movement detection is 30% detection logic and 70% knowing what
> legitimate movement looks like. The grace period system is the
> difference between a working anticheat and a false-flag machine.

→ [Next: Module 04 — Hit Validation](../04-hit-validation/README.md)
