# Module 02: Server-Authoritative Position Validation

## The Concept

The server can read any player's `HumanoidRootPart.Position` at any time. Exploiters can move their character client-side, but the server sees the *actual* replicated position. This is our ground truth.

By sampling position over time, we can calculate:
- **Speed** — how fast they're actually moving
- **Displacement** — how far they jumped between samples
- **Vertical behavior** — are they grounded, falling, or hovering?

## Why Sampling, Not Per-Frame

You might think: check every `Heartbeat`. Don't. With 60+ players, per-frame position checks waste resources and generate noise from physics jitter.

Instead, sample every **0.2–0.5 seconds**. This is enough to catch any meaningful exploit while staying cheap.

```
Frame-by-frame:  ··········································  (noisy, expensive)
Sampled:         ·────────·────────·────────·────────·       (clean, efficient)
```

## The Position History

For hit validation (Module 04), we need to know where players *were* in the recent past, not just where they are now. This is called **lag compensation** — rewinding time to validate what the shooter saw.

```lua
local HISTORY_DURATION = 1.5  -- seconds of history to keep
local SAMPLE_RATE = 0.1       -- how often to record

local positionHistory = {}  -- [character] = { {Time, CFrame}, ... }
```

Each sample stores the server time and the character's CFrame. Old entries get pruned every tick.

## Interpolation

When we need a position at a specific past timestamp (for lag compensation), the exact time probably falls between two samples. We interpolate:

```lua
local function getHistoricalCFrame(character, targetTime)
    local history = positionHistory[character]
    if not history or #history == 0 then
        return character:GetPivot()
    end

    local newer, older
    for i = #history, 1, -1 do
        if history[i].Time >= targetTime then
            newer = history[i]
        else
            older = history[i]
            break
        end
    end

    if not older then return newer.CFrame end
    if not newer then return older.CFrame end

    local alpha = (targetTime - older.Time) / (newer.Time - older.Time)
    return older.CFrame:Lerp(newer.CFrame, alpha)
end
```

This gives us smooth, accurate historical positions for any point in the recent past.

## What The Server Can Derive

From position samples alone:

| Metric | How | Used For |
|--------|-----|----------|
| Horizontal speed | `delta.XZ / dt` | Speed hack detection |
| Vertical velocity | `delta.Y / dt` | Fly detection |
| Ground contact | `FloorMaterial` + downward raycast | Fly detection |
| Wall penetration | Raycast between samples | Noclip detection |
| Historical position | Interpolated lookup | Hit validation |

No client input needed. No remotes. Pure server observation.

## Design Decisions

**Why CFrame, not Position?**
CFrame includes rotation. We need it for lag compensation — the direction someone was facing matters for hit validation.

**Why weak tables for cleanup?**
`setmetatable({}, {__mode = "k"})` ensures that when a character is destroyed, its history is garbage collected automatically. No memory leaks.

**Why not use NetworkOwnership checks?**
Roblox gives physics authority to the client for their own character. This means the server sees the position the client *claims* to be at. For most games this is fine — we validate the claim rather than fighting the physics system.

## Key Takeaway

> The server doesn't need the client to report its position.
> It already has it. Just read it and compare against what's possible.

→ [Next: Module 03 — Speed, Fly & Noclip Detection](../03-speed-fly-noclip/README.md)
