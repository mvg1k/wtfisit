# Where The Fuck Is It?

Physical-search graybox in Godot 4.x. Open `project.godot` in Godot
(validated with 4.7.2) and press **F5**, or **F6** with `scenes/search_game.tscn`
open. No plugins, assets, or editor setup required.
See [PROJECT.md](PROJECT.md) for scope and persistent design context.

Search the room for the physical keys, moving clutter and looking under/behind
furniture. Press E while aiming at the keys to complete the run. The result shows
your time; Enter rebuilds the room and starts a new search at a different authored
spot. Looking at the keys or picking up other props does not complete the run.

| Control | Action |
| --- | --- |
| WASD | Move |
| Mouse | Look |
| Space | Jump |
| Hold Ctrl | Crouch; release to stand when overhead space permits |
| Z | Toggle prone; clearance is checked before rising |
| E | Pick up the prop under the crosshair / drop |
| Hold R + mouse | Rotate held prop; temporarily suppress camera look |
| Wheel up / down | Move held prop farther / closer |
| Hold / release Left Mouse Button | Charge / throw held prop; tap for a gentle toss |
| Escape | Release mouse and drop prop |
| Left click with free cursor | Capture mouse |
| Enter after completion | Search again; reset room, player and timer |
| F3 | Toggle FPS / held name / mass / distance / stance stats; debug builds also show active throw charge |
| F4 (debug builds only) | Show/hide search state, target and hiding spot |
| F7 (search diagnostics visible, debug only) | Reset and reroll the search |

Walk within 3.2 m of a prop to pick it up. Heavy props accelerate and throw less
readily. Held objects collide with the room and other props; a blocked or
overstretched hold releases. Focus loss releases the cursor and held object.
The timer continues while the cursor is free or the window loses focus. Completing
a run stops its timer; the sandbox remains active until you press Enter.

Rotation uses the camera's up/right axes and retains the chosen orientation
after releasing R. Props stay dynamic and yield against obstacles. Dropping
preserves both linear motion and spin.

Hold LMB for about **0.4 s** for a normal throw, **0.8 s** for a strong throw,
or **1.2 s** for maximum (holding longer adds no strength). A tap gives a useful
gentle toss. At 2 kg these add 4/9/14/19 m/s. Light props throw faster; heavy
props remain usable through a bounded mass response. Throws inherit half the
player's velocity (up to 3 m/s), retain up to 4 m/s of existing prop motion,
and cap launch speed at 26 m/s. Bounded, slightly varied tumble adds to existing
spin, capped at 7 rad/s. Charge clears on drop, focus loss, Escape and restart.

Standing movement is 5.4 m/s (+20%). Crouch/prone remain 2.475/1.125 m/s;
acceleration, braking and jump settings are unchanged.

Crouching and prone lower both the camera and the actual player capsule, with
slower movement. Prone cannot jump. Look up while lifting a floor cover, then
turn to set it aside. Use ordinary jumps onto broad boxes/stools and furniture
to inspect high surfaces; there is no special climbing or mantling control.

Thrown props keep native CCD and receive an additional full-body sweep while
moving quickly. This protects charged throws against thin-furniture impacts
while retaining the existing physics engine and 60 Hz tick rate.
Slow and sleeping props do not run these sweeps.

Each pickup starts at 2 m. Wheel distance is clamped to 1.1-3 m, with a larger
minimum for large props. Walls can shorten the actual distance; the debug
value is the selected distance. A hold releases if there is insufficient room
or it would pull the prop into/behind the player. Clearance is conservative,
so tightly confined props may release before they visibly touch the player.

Movement tuning is exported on Player. Hold/rotation/distance/throw tuning is exported on its
Grabber child. The mug is a solid faceted cylinder with a compound box handle, not a
hollow container. There is no dedicated inspection UI.

Hiding locations are seventeen editable SearchSpot markers in `scenes/search_room.tscn`:
3 surface, 4 covered/occluded, 4 low/under, 3 behind furniture, and 3 high.
They use category metadata and initial collision checks, never random XYZ
coordinates. Selection avoids the last two categories and three spots when possible.
The room contains a bed, couch, desk/hutch, shelving, wardrobe, bedside table,
movable covers, boxes and stools. All three high spots have broad physical routes:
box-to-jump at the wardrobe/shelf, and box-to-desktop-to-jump at the hutch.
With no usable spots the game displays an unavailable state instead of starting
an unwinnable run. Enter retries after fixing the room configuration.

`scenes/test_room.tscn` remains the original standalone physics playground
and regression-test fixture. Run it with F6 when testing manipulation alone.

Validation (substitute the full path to your Godot executable if needed):

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --fixed-fps 60 --script res://tests/physics_smoke.gd
godot --headless --path . --fixed-fps 60 --script res://tests/manipulation_smoke.gd
godot --headless --path . --fixed-fps 60 --script res://tests/search_smoke.gd
godot --headless --path . --fixed-fps 60 --script res://tests/stance_smoke.gd
godot --headless --path . --fixed-fps 60 --script res://tests/physical_search_smoke.gd
godot --headless --path . --fixed-fps 60 --script res://tests/throw_smoke.gd
godot --headless --path . --fixed-fps 60 --script res://tests/charge_smoke.gd
godot --headless --path . --quit-after 180
```

The physics smoke test exercises movement, jumping, sleeping, ray selection, different
mass holds/throws, wall collision, safe overlapping release, blocked/overstretched
holds, and object lifetime handling. The manipulation test covers mouse input
routing, camera-relative rotation at different masses/orientations, wheel limits,
large-prop/player clearance, rotating against furniture, momentum, focus loss,
and sleeping after release. The search test checks all seventeen placements, settling,
entrance occlusion, pickup from authored approach positions, target-only completion,
timer/result/restart behavior, repeat avoidance, diagnostics, and invalid spots.
The stance test checks real capsule/camera transitions, movement speed and overhead
clearance. The physical-search test lifts and moves all four covers through the
grabber, crawls under the bed, and recovers all three high targets through ordinary
jumps and movable supports. It also checks category distribution and selection.
The throw test covers 60 impacts using five simple/compound props, 7/14/20 cm
obstacles, 12/26 m/s collision-fixture speeds, spin, settling, sleeping, close release and
deleted-body cleanup. Its optional `-- --native-ccd` negative control disables
the added sweeps and reproduces tunneling/embedding failures.
The charge test covers input press/release timing, clamping, mass/momentum/spin
bounds, visible rotation, cancellation, stance changes and restart. Existing
manipulation checks also exercise furniture contact while charging.
All tests exit nonzero on failed checks.

Movement/charged-throw validation with Godot 4.7.2: **478 checks passed** across
seven suites (35 physics, 44 manipulation, 106 search, 18 stance, 41 physical
search, 184 collision/throw, 50 charge). Editor import and a 180-frame main-scene
launch passed. All 60 impact fixtures passed, now including the 26 m/s cap.
Charge feedback and visible rotation were inspected in rendered frames; this
does not replace manual feel-testing. Prompt #4's rendered room/stance/search UI
checks and the reproduced native-CCD failures remain the basis of the sweep fix.
The native CCD limitation is consistent with its
[support-point ray implementation](https://github.com/godotengine/godot/blob/master/modules/godot_physics_3d/godot_body_pair_3d.cpp).

Movement, grabbing, throwing, rotation and hold distance have been successfully
playtested by the user; the original simple room ran around 180 FPS in debug/editor.
The expanded search room has automated physics/gameplay checks and scripted rendered UI
inspection. Stance/throw feel, search pacing, visibility and fun still need the user's manual
playtest. No destruction-load performance benchmark has been performed.
