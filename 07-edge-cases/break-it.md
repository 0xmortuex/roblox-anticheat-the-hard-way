# Break It: Edge Cases

## Challenge 1: Grace Period Chaining

Use Dash, then immediately Updraft, then trigger an explosion on yourself. That's 0.6s + 1.2s + 1.5s = 3.3 seconds of overlapping grace periods where speed checks are softened. Speedhack during the entire window.

**Hint:** Grace periods don't stack duration — they overlap. If a Dash gives 0.6s grace and an Updraft gives 1.2s starting 0.1s later, the total grace is 1.2s from the Updraft start, not 1.8s. But the *extra tolerance* during grace (+45 studs/s) does apply for the full duration of any active grace. Is 45 studs/s too generous?

## Challenge 2: Admin Attribute Spoofing

From the client, try: `player:SetAttribute("Admin_Fly", true)`. If the anticheat reads this attribute to skip checks, you've just given yourself a bypass.

**Hint:** In Roblox, clients CAN set attributes on their own Player object. The fix: don't check the attribute alone — verify through your admin system's whitelist. Or use a server-only table instead of attributes. This is a critical design flaw if not handled.

## Challenge 3: Collision Group Bypass

Create a part with `CollisionGroup = "VisualEffects"` and place it inside a wall. The noclip check skips parts in this collision group. Now noclip through the wall — the check hits your fake part first and skips it.

**Hint:** The raycast uses the default collision group filter. Parts in "VisualEffects" shouldn't block the raycast at all if your collision groups are set up correctly (VisualEffects shouldn't collide with Default). But verify your collision group matrix.

## Challenge 4: Scale Exploit

Rapidly change your character's scale between 0.5 and 2.0 on the client. The anticheat reads `character:GetScale()` — if the client can influence this, the expected speed calculation becomes unreliable.

**Hint:** `ScaleModule.Scale()` should only run on the server. If the client can call it (or modify scale values directly), that's a separate vulnerability. The anticheat should validate that scale changes come from the server.

## Challenge 5: Invisible Platform

Create a tiny transparent part under your feet while flying. The ground raycast hits it, so the fly check thinks you're grounded. The part is yours (in your character), so... wait, the raycast excludes your character.

**Hint:** The raycast filters out the player's character. But what about parts parented to workspace that the client creates? The anticheat doesn't distinguish between world geometry and exploiter-created parts. Consider only counting ground contact with anchored parts, or parts owned by the server.

## Challenge 6: The Moving Platform Problem

Stand on a moving platform (conveyor belt, elevator, train). Your position changes rapidly relative to world coordinates, but you're standing still on the platform. Does the speed check fire?

**Hint:** The speed check uses world-space position delta. A fast-moving platform carries you at its speed + your walk speed. If the platform moves at 40 studs/s, the anticheat sees 56 studs/s (40 + 16 walk). The base tolerance of 18 studs/s isn't enough.

**Fix approaches:**
1. Detect the platform under the player and subtract its velocity
2. Use `Humanoid.MoveDirection` magnitude as a sanity check (standing still = 0)
3. Increase tolerance based on the velocity of the part the player is standing on

## Challenge 7: Network Ownership Flip

When a player enters a vehicle, network ownership of nearby parts changes. During the transition, physics can behave erratically — parts teleport, velocities spike. Does the anticheat handle ownership transitions gracefully?

**Hint:** Grant a brief grace period when the player enters/exits a vehicle seat. Listen for `Humanoid.Seated` changes.

## The Takeaway

Every bypass in this module represents a real class of anticheat evasion. The challenges without clean solutions (like toggle aimbots or moving platforms) are genuinely hard problems that even AAA games struggle with. The goal isn't perfection — it's making exploitation hard enough that most exploiters move on to easier targets.
