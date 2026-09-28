# Where The Fuck Is It?

First playable Godot 4.x physics playground. Open `project.godot` in Godot
(4.3+; validated with 4.7.2) and press **F6** with the test room open, or **F5**
to run the configured main scene. No plugins, assets, or editor setup required.
See [PROJECT.md](PROJECT.md) for scope and persistent design context.

| Control | Action |
| --- | --- |
| WASD | Move |
| Mouse | Look |
| Space | Jump |
| E | Pick up the prop under the crosshair / drop |
| Left click | Throw held prop |
| Escape | Release mouse and drop prop |
| Left click with free cursor | Capture mouse |
| F3 | Toggle FPS / held name / mass statistics |

Walk within 3.2 m of a prop to pick it up. Heavy props accelerate and throw less
readily. Held objects collide with the room and other props; a blocked or
overstretched hold releases. Focus loss releases the cursor and held object.
Stop/restart the scene to reset the room.

Movement tuning is exported on Player. Hold/throw tuning is exported on its
Grabber child. The mug is a solid faceted cylinder with a compound box handle, not a
hollow container. There is no object rotation/inspection control yet.

Validation (substitute the full path to your Godot executable if needed):

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --fixed-fps 60 --script res://tests/physics_smoke.gd
godot --headless --path . --quit-after 180
```

The smoke test exercises movement, jumping, sleeping, ray selection, different
mass holds/throws, wall collision, safe overlapping release, blocked/overstretched
holds, and object lifetime handling. It
exits nonzero on a failed check. Interactive feel still needs a human playtest;
headless checks cannot establish it. A separate rendered
launch on the RX 5700 XT was checked for room/HUD layout; this is not a sustained
performance benchmark.
