# Break It: Statistical Detection

## Challenge 1: Toggle Aimbot

Turn the aimbot on for 5 seconds, off for 30 seconds, repeat. The short window (10 buckets) catches you during the on phase. But does the long window dilute your stats enough with the off phase to stay clean?

**Hint:** This is the hardest aimbot pattern to catch. The short window might flag, but the long window stays clean. Lowering the short window threshold helps but increases false positives for legitimately skilled players on hot streaks.

## Challenge 2: Body-Only Aimbot

Lock aim to the torso instead of the head. Your accuracy is high but your HSR is normal. Does the system catch you?

**Hint:** The accuracy check catches this if you're above the threshold. But a torso aimbot at 60% accuracy on an SMG might be within normal range. Bone-lock variance is the backup — even torso locks hit the same spot repeatedly.

## Challenge 3: Randomized Aimbot

Add random offset to each aimbot shot so the hit positions spread across the body naturally. This defeats bone-lock variance detection. What catches it now?

**Hint:** Accuracy and HSR are still the primary catches. A randomized aimbot that maintains realistic accuracy and HSR is extremely hard to detect statistically. This is where manual review and behavioral analysis take over.

## Challenge 4: Shotgun Farming

Use a shotgun (8 pellets) to inflate your pellet count while maintaining low accuracy. This dilutes your session accuracy below the threshold. Then switch to a sniper with aimbot — the high sniper accuracy is masked by the overall low average.

**Hint:** Weapon-specific profiling helps. Track accuracy per weapon, not just overall. If the sniper profile shows 95% accuracy over 50 shots while the shotgun shows 40%, that's suspicious.

## Challenge 5: Low Sample Exploit

Join, fire 5 shots, hit all 5 headshots (100% accuracy, 100% HSR), then stop shooting. Does the system flag you?

**Hint:** No — Bayesian smoothing pulls your stats toward the global average at low sample sizes. With only 5 shots: smoothed accuracy = (5 + 12×0.35) / (5 + 12) = 0.54. That's not flagged. You need sustained performance to trigger.

## Challenge 6: Global Poisoning

If many players on your server are bad at aiming, the global average drops. Now a moderately skilled player (50% accuracy) triggers the z-score check because they're far above the lowered baseline.

**Hint:** Hard-clamping the global averages prevents this: `MeanAcc = clamp(MeanAcc, 0.15, 0.50)`. The baseline can't drop below 15% or above 50%. The z-score check is a supplement to the hard limits, not a replacement.

→ [Next: Module 06](../06-punishment-escalation/README.md)
