# Roblox Anticheat — The Hard Way

Build a production-grade, server-side anticheat system for Roblox from scratch. No plugins. No toolbox models. Every line explained.

This course teaches you how to detect **speedhacks, flyhacks, noclip, aimbot, and firerate exploits** by building each detection system yourself — then trying to break it.

## Why This Exists

Most Roblox anticheats are either copy-pasted from Toolbox (and trivially bypassed), or proprietary systems nobody explains. Developers slap a `LocalScript` check on movement and call it "anticheat" — then wonder why exploiters walk through walls.

This course starts from a single principle: **never trust the client.** Every module builds on that idea, moving from basic position validation to statistical aim analysis with Bayesian smoothing.

By the end, you'll have a working anticheat framework and — more importantly — understand *why* each piece exists.

## Who This Is For

- Roblox developers building competitive/PvP games
- Developers who want to understand server-side security
- Anyone tired of copy-paste anticheats that don't work

**Prerequisites:** Intermediate Lua, basic understanding of Roblox's client-server model, familiarity with `RemoteEvent` / `RemoteFunction`.

## Modules

| # | Module | What You'll Build |
|---|--------|-------------------|
| 01 | [Why Client Trust Is Broken](01-why-client-trust-is-broken/) | Demonstrate how exploits work, why client checks fail |
| 02 | [Server-Authoritative Position Validation](02-server-authoritative-position/) | Position sampling, server-side ground truth |
| 03 | [Speed, Fly & Noclip Detection](03-speed-fly-noclip/) | Three movement validators with grace period system |
| 04 | [Hit Validation](04-hit-validation/) | Firerate checks, range validation, trajectory verification, wallbang detection |
| 05 | [Statistical Aim Detection](05-statistical-aim-detection/) | Bayesian-smoothed accuracy tracking, z-score anomaly detection, bone-lock variance |
| 06 | [Punishment Escalation](06-punishment-escalation/) | Suspicion scoring with decay, flag → kick → ban pipeline |
| 07 | [Edge Cases That Break Everything](07-edge-cases/) | Ping tolerance, gamemodes, admin commands, knockback, abilities |

Each module contains:
- **`README.md`** — concept explanation and design decisions
- **`code.lua`** — working, commented implementation
- **`break-it.md`** — challenges to test and bypass your own system

## How To Use This Course

**Option A: Build along.** Read each module in order, implement the code in your own Roblox game, run the "break it" challenges.

**Option B: Reference.** Jump to the module you need. Each one is self-contained with context.

**Option C: Fork and extend.** Take the framework, adapt it to your game's mechanics, submit a PR if you build something cool.

## Architecture Overview

```
Client                          Server
──────                          ──────
Input → Movement → Position     MovementValidator ← samples HRP position
     → Aim → Fire weapon        HitValidator ← validates every hit report
     → Report hits via Remote → StatisticalAC ← tracks accuracy over time
                                     │
                                     ▼
                                PunishmentService
                                (Flag → Kick → Ban)
```

The server never asks the client "are you cheating?" It independently validates everything the client claims to do.

## Key Design Principles

**1. Validate, don't prevent.** Let the client move freely, but verify server-side. Preventing movement causes rubberbanding and bad UX.

**2. Score, don't ban.** A single suspicious event means nothing. Accumulated suspicion over time with decay separates exploiters from laggy players.

**3. Account for everything legitimate.** Dashes, knockback, abilities, admin commands, gamemodes — all of these cause sudden movement spikes. If your anticheat doesn't know about them, it kicks innocent players.

**4. Ping is not a crime.** High-latency players look suspicious by default. Every tolerance must scale with ping, and kick thresholds should be more lenient for lagging players.

## Tech Stack

- **Language:** Luau (Roblox)
- **Architecture:** Server-authoritative with client-side prediction
- **Dependencies:** None — pure ModuleScripts, no external packages

## Contributing

Found a bypass? Improved a detection method? PRs welcome.

- Fork → Branch → Implement → Test → PR
- Every detection change must include an explanation of *what it catches* and *what it doesn't*
- Breaking changes to the scoring system need updated thresholds

## License

MIT — use it, modify it, ship it. Credit appreciated but not required.

---

Built by [0xmortuex](https://github.com/0xmortuex)
