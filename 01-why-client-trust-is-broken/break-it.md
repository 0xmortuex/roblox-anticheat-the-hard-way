# Break It: Client Trust

These challenges demonstrate why client authority doesn't work. Try each one in a test place.

## Challenge 1: Speed Bypass

Add a client-side speed check to your game. Then bypass it using `BodyVelocity` instead of `WalkSpeed`. Your check doesn't fire because the humanoid property never changed.

## Challenge 2: Remote Spoofing

Create a `RemoteEvent` that deals damage. Fire it from the command bar with fake data:

```lua
-- From client command bar (simulates an exploiter)
game.ReplicatedStorage.Remotes.DamageEvent:FireServer(workspace.SomePlayer, 9999)
```

Does your server validate anything before applying damage?

## Challenge 3: Position Teleport

Set your HumanoidRootPart's CFrame directly from the client. Does the server notice? Does anything prevent it?

```lua
local hrp = game.Players.LocalPlayer.Character.HumanoidRootPart
hrp.CFrame = CFrame.new(0, 1000, 0)
```

## What You Should Learn

If any of these worked in your game, you need the systems built in Modules 02–06. Every exploit here is trivial — the defenses shouldn't be.

→ [Next: Module 02](../02-server-authoritative-position/)
