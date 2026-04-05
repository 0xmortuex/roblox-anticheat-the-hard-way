# Module 01: Why Client Trust Is Broken

## The Problem

In Roblox, every player runs a copy of your game's client scripts on their machine. Exploiters can:

- Read and modify any `LocalScript`
- Fire any `RemoteEvent` with arbitrary data
- Change their character's position, speed, and properties
- Intercept and spoof network traffic between client and server

This means **anything the client tells the server could be a lie.**

## How Exploits Work

An exploiter using a script executor can do this in seconds:

```lua
-- Speedhack: directly set WalkSpeed
local player = game.Players.LocalPlayer
player.Character.Humanoid.WalkSpeed = 200

-- Fly: disable gravity and move freely
local hrp = player.Character.HumanoidRootPart
hrp.Anchored = true  -- or use BodyVelocity/LinearVelocity

-- Noclip: disable collisions
for _, part in pairs(player.Character:GetDescendants()) do
    if part:IsA("BasePart") then
        part.CanCollide = false
    end
end

-- Fake hit: fire the damage remote directly
game.ReplicatedStorage.Remotes.DamageEvent:FireServer(targetPlayer, 999)
```

None of these require advanced tools. Basic executor, copy-paste, done.

## Why Client-Side Checks Fail

You might think: "Just check WalkSpeed on the client!"

```lua
-- BAD: Client-side anticheat
RunService.Heartbeat:Connect(function()
    if humanoid.WalkSpeed > 16 then
        humanoid.WalkSpeed = 16  -- "fixed!"
    end
end)
```

An exploiter can:
1. Delete the LocalScript entirely
2. Hook the function and make it return early
3. Modify `WalkSpeed` after the check runs each frame
4. Use `BodyVelocity` instead of WalkSpeed (bypasses the check completely)

**Client-side checks are speed bumps, not walls.** They stop accidental bugs, not intentional exploits.

## The Solution: Server Authority

The server is the only trusted environment. Exploiters cannot modify server code.

Instead of asking "did the client cheat?", the server asks: **"Is what the client claims physically possible?"**

```
CLIENT says: "I hit Player2 in the head from 50 studs away"

SERVER checks:
  ✓ Was the client's weapon equipped?
  ✓ Was enough time since last shot? (firerate)
  ✓ Was the target within weapon range?
  ✓ Was there line-of-sight? (no walls)
  ✓ Was the hit position near the target's actual body?

If ALL pass → apply damage
If ANY fail → reject silently or add suspicion
```

This is the foundation of everything we build in this course.

## The Trust Boundary

```
┌─────────────────────────────────┐
│         CLIENT (untrusted)      │
│                                 │
│  LocalScripts, UI, Input,      │
│  Camera, Animations, Sound     │
│                                 │
│  Can be: read, modified,       │
│  deleted, spoofed              │
└───────────────┬─────────────────┘
                │ RemoteEvents / RemoteFunctions
                │ (this is the attack surface)
┌───────────────▼─────────────────┐
│         SERVER (trusted)        │
│                                 │
│  ServerScripts, DataStores,    │
│  Physics authority, Damage,     │
│  Anticheat validation          │
│                                 │
│  Cannot be modified by players │
└─────────────────────────────────┘
```

Every `RemoteEvent` your game uses is a potential exploit vector. The anticheat's job is to validate every message that crosses this boundary.

## What You'll Build In This Course

| Module | Detection | Approach |
|--------|-----------|----------|
| 02 | Position spoofing | Server samples HRP position directly |
| 03 | Speed / Fly / Noclip | Velocity checks, airborne tracking, wall raycasts |
| 04 | Fake hits | Firerate, range, trajectory, wallbang validation |
| 05 | Aimbot | Statistical accuracy analysis over time |
| 06 | All of the above | Suspicion scoring, punishment pipeline |
| 07 | False positives | Handling legitimate edge cases |

## Key Takeaway

> The only code you can trust is code running on the server.
> Everything else is a suggestion from an untrusted source.

→ [Next: Module 02 — Server-Authoritative Position Validation](../02-server-authoritative-position/README.md)
