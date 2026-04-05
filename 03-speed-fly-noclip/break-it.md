# Break It: Movement Detection

## Challenge 1: Slow Speedhack

Set WalkSpeed to 25 instead of 200. This is only 56% over the base speed of 16. Does your anticheat catch it, or does the tolerance absorb it?

**Hint:** The tolerance at 50ms ping is about 20 studs/s. A WalkSpeed of 25 is only 9 over base. You might need sustained detection — one sample won't trigger, but 30 seconds of it should accumulate enough points.

## Challenge 2: Teleport Noclip

Instead of flying through a wall continuously, teleport your character 100 studs forward instantly (set HRP.CFrame). Does the noclip check fire? What about the speed check?

**Hint:** A 100-stud teleport in 0.3 seconds = 333 studs/s. The speed check should catch it. But does the noclip check also catch the wall penetration?

## Challenge 3: Gravity Fly

Apply a massive upward VectorForce to your character from the client. You're not "flying" — you're using physics. Does the anticheat distinguish between a client-applied force and a server-applied gravity modifier?

**Hint:** The anticheat checks for the `_sv` attribute on VectorForces. Client-created forces won't have this tag.

## Challenge 4: Dash Abuse

Trigger the OnDash grace period manually by exploiting the skill remote. During the 0.6s grace window, speedhack at 200. Does the anticheat catch the abuse?

**Hint:** 0.6 seconds at 200 speed = 120 studs of undetected movement. Is that acceptable? Should the grace period be shorter?

## Challenge 5: Ground Spoofing

Place an invisible, tiny part under your character so the ground raycast always hits something. Now fly freely — the anticheat thinks you're grounded.

**Hint:** The anticheat excludes the player's character from the raycast. But what about parts the player creates? Should the raycast filter by collision group?

→ [Next: Module 04](../04-hit-validation/README.md)
