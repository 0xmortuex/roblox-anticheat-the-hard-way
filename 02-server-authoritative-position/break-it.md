# Break It: Position Tracking

## Challenge 1: Teleport Between Samples

The server samples every 0.1 seconds. Teleport your character 50 studs, wait 0.05s, then teleport back. You moved 100 studs total but ended up in the same spot. Does the position tracker notice?

**Hint:** If both teleports happen within a single sample interval, the server sees no movement at all. This is a fundamental limitation of sampling-based detection.

## Challenge 2: Stale History

Kill your character, respawn, and immediately fire a weapon. The hit validation uses `GetHistoricalCFrame` to rewind the victim's position — but what if the victim just spawned and has no history?

**Hint:** The function falls back to `GetPrimaryPartCFrame()` when history is empty. Is that safe? What if the character hasn't fully loaded yet?

## Challenge 3: Interpolation Abuse

The interpolation function uses `CFrame:Lerp()` between two samples. If a player was at position A at t=0.0 and position B at t=0.1, the function assumes they moved in a straight line between them. What if they actually moved in a curve?

**Hint:** This is acceptable for most games. The error is small enough (0.1s of movement) that it doesn't matter. But for very fast-moving targets, consider storing more frequent samples.

## Challenge 4: Dummy Spoofing

The tracker samples tagged "Dummy" models for hit validation. Can an exploiter create a model, tag it as "Dummy" with CollectionService, and use it to confuse the system?

**Hint:** Clients can add CollectionService tags. Consider validating that tagged dummies exist in a known container (e.g., a specific folder) rather than trusting the tag alone.

→ [Next: Module 03](../03-speed-fly-noclip/)
