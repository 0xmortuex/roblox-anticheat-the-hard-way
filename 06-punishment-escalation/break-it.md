# Break It: Punishment Escalation

## Challenge 1: Decay Racing

Trigger a minor violation (+3 pts) every 6 seconds. Decay removes 3 pts every 5 seconds. Are you accumulating faster than you're decaying?

**Hint:** 3 pts per 6s = 0.5 pts/s gain. 3 pts per 5s = 0.6 pts/s decay. You're actually decaying faster — you'll never hit the threshold. But what if you trigger +5 pts every 6s? Now you gain 0.83 pts/s and decay 0.6 pts/s. You'll eventually reach the flag threshold.

## Challenge 2: Cross-Module Stacking

Get 14 points in the movement AC (just under the 15 flag threshold) and 14 points in the hit validation AC. Neither module flags you independently. But you're clearly exploiting.

**Hint:** Each module has its own score, but flags from all modules accumulate in PunishmentService. If the movement AC flags once and the hit AC flags once, that's 2 flags total — approaching the kick threshold of 3.

## Challenge 3: Session Reset Abuse

Get to 50/55 points (almost kicked), then leave and rejoin. Does your score persist?

**Hint:** Module-level scores reset on rejoin (they're in-memory). But PunishmentService flag counts persist for the session. If you accumulated 2 flags before leaving, you start with 2 flags on rejoin. One more flag = kick.

## Challenge 4: Ping Spoofing

Artificially inflate your ping by delaying responses to the server. When you hit the kick threshold, the high-ping protection kicks in and demotes it to a flag instead.

**Hint:** `GetNetworkPing()` measures the actual connection latency. Artificially delaying responses does increase measured ping. But a player who consistently triggers AC violations AND has high ping will still accumulate flags over time.

## Challenge 5: Webhook Flooding

Trigger thousands of minor violations rapidly to flood the Discord webhook with alerts, making real alerts hard to spot.

**Hint:** Rate-limit webhook calls. Don't send a webhook for every flag — batch them or only send on escalation (first flag, kick, ban).

→ [Next: Module 07](../07-edge-cases/)
