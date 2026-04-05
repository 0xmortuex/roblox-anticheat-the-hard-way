# Break It: Hit Validation

## Challenge 1: Firerate Creep

Fire a weapon at 95% of its firerate limit — just barely under the threshold. Do this for 100 shots. The time balance system should prevent gaining free shots. Does it? Or do tiny rounding errors add up?

**Hint:** The time balance caps at `requiredCooldown * 4`. This prevents banking more than 4 shots of surplus time. But check: does the 0.05 tolerance in the firerate check compound over many shots?

## Challenge 2: Silent Aim

Fire at position (0, 0, 0) but report the hit at the victim's actual position. The shot origin is legitimate, the hit position is legitimate, but the direction is completely wrong — the bullet would have missed.

**Hint:** The current system checks if the hit position is near the victim's body, but doesn't replay the full trajectory. A trajectory replay (Module 04 README, section on path nodes) catches this, but the basic version doesn't.

## Challenge 3: Lag Compensation Abuse

Intentionally introduce 500ms of artificial latency. Fire at where a target *used to be* half a second ago. The lag compensation system rewinds the target to that position and validates the hit.

**Hint:** This is called "lag switching" and is partially mitigated by the `MAX_PING` check (0.8s). But within that window, legitimate lag and artificial lag are indistinguishable. The statistical module (Module 05) catches players who consistently perform better than their ping should allow.

## Challenge 4: Explosion Spam

Fire a non-explosive weapon but report `IsExplosion = true` in the hit data. The definitive check should catch this. Does it?

**Hint:** This is an instant kick, not a scored violation. Test that your weapon config correctly reports which weapons have explosions.

## Challenge 5: Ghost Target

Report a hit against a character that doesn't exist anymore (player left, character despawned). Does the validator check that the target is still alive and present?

**Hint:** The `humanoid.Health <= 0` check catches dead targets. But what about targets that are in the process of respawning? Their humanoid might exist but be in a transitional state.

## Challenge 6: Backpack Weapon Fire

Unequip a weapon (it goes to Backpack), then fire the remote claiming hits from it. The validator checks both Character and Backpack for the tool. Should it allow hits from an unequipped weapon?

**Hint:** Some games allow throwing weapons that continue dealing damage after being unequipped. If yours doesn't, restrict validation to equipped weapons only.

→ [Next: Module 05](../05-statistical-aim-detection/)
