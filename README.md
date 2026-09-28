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
| Hold R + mouse | Rotate held prop; temporarily suppress camera look |
| Wheel up / down | Move held prop farther / closer |
| Left click | Throw held prop |
| Escape | Release mouse and drop prop |
| Left click with free cursor | Capture mouse |
| F3 | Toggle FPS / held name / mass / selected distance statistics |

Walk within 3.2 m of a prop to pick it up. Heavy props accelerate and throw less
readily. Held objects collide with the room and other props; a blocked or
overstretched hold releases. Focus loss releases the cursor and held object.
Stop/restart the scene to reset the room.

Rotation uses the camera's up/right axes and retains the chosen orientation
after releasing R. Props stay dynamic and yield against obstacles. Dropping
preserves both linear motion and spin.

Each pickup starts at 2 m. Wheel distance is clamped to 1.1-3 m, with a larger
minimum for large props. Walls can shorten the actual distance; the debug
value is the selected distance. A hold releases if there is insufficient room
or it would pull the prop into/behind the player. Clearance is conservative,
so tightly confined props may release before they visibly touch the player.

Movement tuning is exported on Player. Hold/rotation/distance/throw tuning is exported on its
Grabber child. The mug is a solid faceted cylinder with a compound box handle, not a
hollow container. There is no dedicated inspection UI.

Validation (substitute the full path to your Godot executable if needed):

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --fixed-fps 60 --script res://tests/physics_smoke.gd
godot --headless --path . --fixed-fps 60 --script res://tests/manipulation_smoke.gd
godot --headless --path . --quit-after 180
```

The physics smoke test exercises movement, jumping, sleeping, ray selection, different
mass holds/throws, wall collision, safe overlapping release, blocked/overstretched
holds, and object lifetime handling. The manipulation test covers mouse input
routing, camera-relative rotation at different masses/orientations, wheel limits,
large-prop/player clearance, rotating against furniture, momentum, focus loss,
and sleeping after release. Both exit nonzero on failed checks.

The original prototype was successfully playtested by the user at roughly
180 FPS in the simple room's editor/debug run. This manipulation milestone has
automated validation; rotation/distance feel still needs the user's playtest.
Neither result is a destruction-load performance benchmark.
