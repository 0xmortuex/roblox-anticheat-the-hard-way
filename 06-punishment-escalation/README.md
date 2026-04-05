# Module 06: Punishment Escalation

## Don't Ban On First Offense

The single biggest mistake in anticheat design: **instant punishment.** A lag spike looks like a speedhack for one sample. A lucky shot looks like aimbot for one frame. If you kick on the first flag, you kick innocent players.

The solution is a **suspicion scoring system** with time decay.

## The Scoring Model

Every check from Modules 03–05 produces points, not punishments.

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Movement AC  │    │ Hit Valid.   │    │ Statistical  │
│  Speed: +3   │    │  Range: +5   │    │  Acc Z: +15  │
│  Fly: +8     │    │  LOS: +10    │    │  HSR Z: +12  │
│  Noclip: +12 │    │  Rate: +5    │    │  Variance:+20│
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           ▼
                  ┌─────────────────┐
                  │ Suspicion Score  │
                  │                 │
                  │  0────15────35──────55
                  │  OK   Flag  Suppress Kick
                  └────────┬────────┘
                           ▼
                  ┌─────────────────┐
                  │   Punishment    │
                  │    Service      │
                  │                 │
                  │ Flag → Kick →   │
                  │    → Ban        │
                  └─────────────────┘
```

## Thresholds

| Score | Action | What Happens |
|-------|--------|-------------|
| 0–14 | Nothing | Normal play |
| 15 | **Flag** | Logged + webhook alert. Player continues playing. |
| 35 | **Suppress** | Damage may be suppressed temporarily. Logged. |
| 55 | **Kick** | Removed from server. |

These are per-module. Each AC module (movement, combat, statistical) maintains its own score independently.

At the **PunishmentService** level, flags from all modules accumulate:

| Flags | Escalation |
|-------|-----------|
| 1–2 | Logged only |
| 3 | Auto-kick |
| 6 | DataStore ban (24h default) |

## Time Decay

Suspicion decays over time. If a player triggered one speed flag but plays clean for the next 30 seconds, their score drops back to zero.

```lua
-- Every 5 seconds, reduce every player's score
task.spawn(function()
    while true do
        task.wait(5)
        for _, data in pairs(PlayerScores) do
            if data.Score > 0 then
                data.Score = math.max(0, data.Score - 3)
            end
        end
    end
end)
```

**Why decay?** Because legitimate players occasionally trigger checks. A single lag spike adds 3-5 points. Without decay, those points accumulate over a long session until the player gets kicked for nothing.

**Why not reset to zero?** A player who triggers checks every 20 seconds is suspicious even though each individual flag decays. The decay rate is tuned so that consistent violations accumulate faster than they decay.

## High-Ping Protection

Players with bad connections look suspicious by default. Their positions jump, shots arrive late, and hit positions seem off. Kicking them is unfair.

```lua
if score >= KICK_THRESHOLD then
    local ping = player:GetNetworkPing()
    if ping > 0.25 then
        -- High ping: demote to flag instead of kick
        PunishmentService.Flag(player, reason, source)
        score = FLAG_THRESHOLD  -- reset to flag level
    else
        PunishmentService.AutoKick(player, reason, source)
    end
end
```

This gives laggy players more chances while still catching exploiters who fake high ping (their actual behavior will still be consistently suspicious).

## Session Separation

When a round ends, partially reset scores:

```lua
function ResetPlayer(player)
    local data = PlayerScores[player.UserId]
    if data then
        data.Score = math.floor(data.Score * 0.5)  -- halve, don't zero
    end
end
```

**Why halve instead of zero?** A player who was at 50/55 (almost kicked) shouldn't start the next round clean. Halving preserves suspicion from the previous round while giving them room to play clean.

## Ban System

Bans are stored in a DataStore and checked on join:

```lua
Players.PlayerAdded:Connect(function(player)
    local banData = BanStore:GetAsync(tostring(player.UserId))
    if banData and os.time() < banData.ExpiresAt then
        player:Kick("Banned: " .. banData.Reason)
    end
end)
```

Bans auto-expire. Default is 24 hours. Repeat offenders get longer bans (you can implement escalating ban durations by tracking ban count in the DataStore).

## Definitive vs Probabilistic

Some violations are **definitive** — they can only happen through exploitation:

- Spoofing tick damage on a weapon that doesn't have tick damage
- Spoofing explosion damage on a weapon that doesn't explode
- Sending malformed data structures

These skip the scoring system entirely and go straight to kick:

```lua
if isDefinitive then
    PunishmentService.AutoKick(player, reason, source)
    return
end
```

Everything else is probabilistic and goes through the scoring system.

## Discord Webhook Integration

Every flag, kick, and ban can be reported to a Discord channel via webhook:

```lua
HttpService:PostAsync(WEBHOOK_URL, HttpService:JSONEncode({
    embeds = {{
        title = "AntiCheat " .. level,
        color = colorByLevel,
        fields = {
            { name = "Player", value = playerName },
            { name = "Reason", value = reason },
            { name = "Source", value = sourceModule },
        }
    }}
}))
```

This gives admins real-time visibility without needing to be in-game.

## Key Takeaway

> A good anticheat doesn't punish mistakes — it punishes patterns.
> Decay separates the laggy player who tripped one check from the
> exploiter who trips checks every 5 seconds.

→ [Next: Module 07 — Edge Cases That Break Everything](../07-edge-cases/README.md)
