# Module 07: Edge Cases That Break Everything

## The Real Work

Modules 02–06 build the detection systems. This module is where 70% of the development time actually goes — making sure legitimate gameplay doesn't trigger any of it.

Every game has mechanics that look exactly like cheating to a naive anticheat. Your job is to teach the system what's normal.

## The Edge Case Catalog

### Dashes and Movement Abilities

**The problem:** A dash ability launches the player at 85 studs/s for 0.15 seconds. The speed check sees 85 studs/s when the WalkSpeed is 16.

**The solution:** Grace periods. The skill system calls a hook when a dash fires:

```lua
-- In your Dash skill logic:
MovementValidator.OnDash(player)  -- grants 0.6s grace period
```

During the grace period, speed checks add extra tolerance instead of flagging.

**Common mistake:** Making the grace period too long. If you give 2 seconds of grace for a 0.15s dash, exploiters can speedhack for 2 seconds every time they dash.

### Knockback

**The problem:** An explosion launches a player 30 studs. The speed and noclip checks both trigger.

**The solution:** The damage system calls a knockback hook:

```lua
-- After applying knockback impulse:
MovementValidator.OnKnockback(victimPlayer, 1.5)  -- 1.5s grace
```

**Important:** Knockback grace only applies to the *victim*, not the attacker. If the attacker is also knocked back (self-damage), they need their own hook call.

### Gamemodes That Modify Stats

**The problem:** A "Glass Cannon" perk sets WalkSpeed to 32. A "Titan" perk sets Scale to 1.35. The anticheat was calibrated for WalkSpeed 16 at scale 1.0.

**The solution:** Read the actual server-side values, don't hardcode expected values.

```lua
-- DON'T do this:
local expectedSpeed = 16  -- hardcoded, breaks with gamemodes

-- DO this:
local expectedSpeed = humanoid.WalkSpeed  -- reads the actual server value
```

Since gamemodes set these properties server-side, the anticheat automatically adapts.

### Low/High Gravity

**The problem:** A "Moon Walker" perk applies 0.5× gravity. The player stays airborne for 6+ seconds on a normal jump. Fly detection triggers at 2.5 seconds.

**The solution:** Detect the gravity modifier and extend the threshold:

```lua
-- Moon Walker applies a VectorForce tagged with _sv:
force:SetAttribute("_sv", true)  -- "server verified"

-- Anticheat checks for this tag:
if HasGravityModifier(character) then
    airborneThreshold *= 5  -- allow 12.5s airborne
end
```

### Admin Commands

**The problem:** An admin teleports a player. The anticheat sees instant position change → noclip flag. Admin sets fly mode → fly flag. Admin changes speed → speed flag.

**The solution:** Listen for admin attribute changes automatically:

```lua
local adminAttrs = { "Admin_Speed", "Admin_Fly", "Admin_Ball", "Admin_Freeze" }
for _, attr in ipairs(adminAttrs) do
    player:GetAttributeChangedSignal(attr):Connect(function()
        MovementValidator.GrantGrace(player, 1.0, "Admin")
    end)
end
```

Admin fly should **completely skip** fly and noclip checks, not just get a grace period:

```lua
if player:GetAttribute("Admin_Fly") == true then
    return  -- skip all movement checks
end
```

### Spawn Protection

**The problem:** Player respawns, gets teleported to a spawn point, receives a ForceField. Noclip check fires because they moved instantly from death position to spawn.

**The solution:** Reset tracking on character spawn:

```lua
player.CharacterAdded:Connect(function()
    state.LastPos = nil         -- no previous position to compare
    state.IsAirborne = false
    GrantGrace(player, 3.0)     -- 3 seconds spawn grace
end)
```

### Platform Stand / Ball Mode

**The problem:** Admin ball mode sets `PlatformStand = true` and lets the player roll around at 80 speed inside a physics ball.

**The solution:** Detect ball mode and raise the speed cap:

```lua
if player:GetAttribute("Admin_Ball") then
    return 110  -- ball mode speed cap
end
```

### Weapon Speed Modifiers

**The problem:** A weapon with `WalkSpeedMultiplier = 0.7` slows the player to 70% speed while equipped. The anticheat doesn't know about this and flags legitimate speed as "too slow" — wait, no. The problem is the reverse: when the player unequips, their speed snaps back to normal. If the anticheat was using the reduced speed as baseline, the speed *increase* looks suspicious.

**The solution:** The anticheat reads `WalkSpeed` directly, which is already being set correctly by the weapon handler's speed enforcer. No special handling needed — the server value is always correct.

### Scale Changes

**The problem:** Player gets shrunk to 0.6× scale. Their stride length changes, hitbox size changes, and speed appears different relative to their body size.

**The solution:** Factor scale into expected speed:

```lua
local scale = character:GetScale()
local effectiveSpeed = walkSpeed * math.max(scale, 0.5)
```

Grant grace when scale changes (the character briefly moves weird during rescaling):

```lua
MovementValidator.OnScaleChange(player)  -- 1.5s grace
```

### Network Ownership

**The problem:** Roblox gives physics authority of a character to the owning client. This means the position the server sees is what the client *claims*. If the client lies about position, the server sees the lie.

**This is a fundamental limitation.** You cannot prevent position spoofing in Roblox's physics model — you can only detect it after the fact by checking if the claimed movement was physically possible.

### Death / Health Zero

**The problem:** Player dies, ragdoll flies across the map, anticheat sees massive speed.

**The solution:** Skip checks when health ≤ 0:

```lua
if hum.Health <= 0 then
    state.LastPos = nil
    return
end
```

## The Checklist

Before deploying your anticheat, verify it handles all of these:

```
[ ] Normal walking
[ ] Running (WalkSpeed boost from gamemode)
[ ] Jumping (including high JumpPower)
[ ] Falling from height
[ ] Dash/dodge abilities
[ ] Updraft/launch abilities
[ ] Knockback from weapons
[ ] Self-knockback from explosions
[ ] Low gravity modifier
[ ] High gravity modifier
[ ] Admin fly
[ ] Admin speed changes
[ ] Admin teleport
[ ] Admin ball mode
[ ] Admin freeze
[ ] Scale up (Titan)
[ ] Scale down (Ant-Man)
[ ] Weapon equip speed change
[ ] Character spawn/respawn
[ ] Character death/ragdoll
[ ] Round transition
[ ] Map change
[ ] High ping player (200ms+)
[ ] Mobile player (lower FPS, different input)
```

If any of these triggers a false flag, you have a bug. Test every single one.

## Key Takeaway

> The anticheat isn't done when it catches cheaters.
> It's done when it stops catching innocent players.
