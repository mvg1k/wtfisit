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
| Right Mouse Button | Drop held prop; cancel an active/queued throw without adding impulse |
| Escape | Release mouse and drop prop |
| Left click with free cursor | Capture mouse |
| Enter after completion | Search again; reset room, player and timer |
| F3 | Toggle stats; debug builds also show charge and held material / damage state / last impact / thresholds |
| F4 (debug builds only) | Show/hide search state, target, spot, category, action and spawn rejection counts |
| F7 (search diagnostics visible, debug only) | Reset and reroll the search |

Walk within 3.2 m of a prop to pick it up. Heavy props accelerate and throw less
readily. Held objects collide with the room and other props; a blocked or
overstretched hold releases. Focus loss releases the cursor and held object.
The timer continues while the cursor is free or the window loses focus. Completing
a run stops its timer; the sandbox remains active until you press Enter.

Rotation uses the camera's up/right axes and retains the chosen orientation
after releasing R. Props stay dynamic and yield against obstacles. Dropping
preserves both linear motion and spin.

Hold LMB for **1.0 s** for maximum (holding longer adds no strength).
A tap gives a gentle toss; 0.4 s and 0.8 s give intermediate strengths.
At 2 kg, tap/0.4 s/0.8 s/1.0 s add 4/10/16/19 m/s. Light props throw faster; heavy
props remain usable through a bounded mass response. Throws inherit half the
player's velocity (up to 3 m/s), retain up to 4 m/s of existing prop motion,
and cap launch speed at 26 m/s. Bounded, slightly varied tumble adds to existing
spin, capped at 7 rad/s. Charge clears on drop, focus loss, Escape and restart.
A thin ring around the crosshair fills while charging and pulses subtly at maximum.
It disappears on throw or cancellation. RMB releases without throwing; releasing
LMB afterward cannot launch the dropped prop. Exact charge percentages remain in
debug-build F3 stats, which start hidden in the search room.

Standing movement is 5.4 m/s (+20%). Crouch/prone remain 2.475/1.125 m/s;
acceleration, braking and jump settings are unchanged.
Walking into movable props now applies bounded, mass-aware horizontal pushes:
light objects yield readily, medium objects resist, and heavy objects move slowly.
Opposed contacts can trigger a short collision-tested back-out to reduce wedging.
Objects pinned by furniture or extremely heavy objects can still block passage.

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
When looking down at a floor prop, its rotated shapes determine support and
player clearance. The target lifts clear of the surface, allowing fallen monitors
and small fragments to stay held; close walls still trigger the existing release.

Supported props whose poses remain within a small bounded range for one second
can now enter dynamic sleep despite residual contact rocking. The check confirms
sleep across subsequent physics steps so contacting props can settle together.
Pickup, release, throws, impacts and player pushes still wake bodies. The helper
does not add damping or change global solver settings or pushing tuning.

Movement tuning is exported on Player. Hold/rotation/distance/throw tuning is exported on its
Grabber child. The mug is a solid faceted cylinder with a compound box handle, not a
hollow container. There is no dedicated inspection UI.

Hiding locations are seventeen editable SearchSpot markers in `scenes/search_room.tscn`:
3 surface, 4 covered/occluded, 4 low/under, 3 behind furniture, and 3 high.
Each also has one primary intended action: VISUAL_SEARCH (6), CROUCH (1), PRONE (3),
MOVE_PROP (4), or CLIMB (3). This describes the design intent, not a required input.
They use authored coordinates and initial collision checks. A single pass rejects
fully exposed targets inside the initial camera frustum using rays to collider
centers and inset corners; World and Props provide occlusion. Partially occluded
or off-screen placements stay eligible. An all-exposed pool becomes unavailable.
Selection avoids the last two categories and three spots among survivors when possible.
The three surface spots now need a view past existing clutter; the deep-bed and
headboard spots avoid diagonal gaps visible from spawn, including after settling.
The room contains a bed, couch, desk/hutch, shelving, wardrobe, bedside table,
movable covers, boxes and stools. All three high spots have broad physical routes:
box-to-jump at the wardrobe/shelf, and box-to-desktop-to-jump at the hutch.
With no usable spots the game displays an unavailable state instead of starting
an unwinnable run. Enter retries after fixing the room configuration.

`scenes/test_room.tscn` remains the original standalone physics playground
and regression-test fixture. Run it with F6 when testing manipulation alone.

## Impact and material examples

The search room now includes a ceramic vase, glass bottle, plastic toy brick, wood
block and metal weight near the entrance, plus a monitor on the desk. They use
the existing grab/rotate/drop/throw controls. Keys and search furniture remain
indestructible. The vase/bottle are solid prototype shapes with no containment.

| Material / example | Mass | Crack / break severity | Response |
| --- | ---: | ---: | --- |
| CERAMIC / vase | 0.6 kg | — / 14 | Four fragments |
| GLASS / bottle | 0.45 kg | — / 10 | Four fragments |
| WOOD / block | 1.5 kg | 120 / 240 | Darker damaged states |
| PLASTIC / block | 0.18 kg | 130 / 260 | Darker damaged states |
| METAL / weight | 8 kg | 550 / 900 | Darker damaged states |
| ELECTRONIC / monitor | 5 kg | 70 / 100 | Lit -> cracked -> dark |

Tune `resources/materials/*.tres`; body mass and visual states are authored in
the prop scenes. Impact severity uses normal relative contact speed and reduced
mass: `0.5 * effective_mass * closing_speed^2`. Dynamic effective mass is
`m1*m2/(m1+m2)`; against immovable geometry it is the prop's mass. Speeds below
1 m/s are ignored. The strongest new contact drives one state transition,
with a 0.3 s cooldown. Tiny contacts never accumulate damage.

The throw sweep preserves pre-clamp severity for a maximum of three physics
ticks, requiring confirmed contact with the same collider before damage occurs.
The contact overlap is 1 cm: the previous 1 mm could stop a tumbling body short
of contact until its saved estimate expired. The shared sweep also protects
dropped/falling/dead impact props. Thresholds and the 60 Hz tick rate are unchanged.
F3 reports closing speed, effective mass and contact/confirmed-sweep source.
Angular contact speed uses the physical center of mass, independent of scene pivot.
Contact data comes from
[Godot's direct body state](https://docs.godotengine.org/en/stable/classes/class_physicsdirectbodystate3d.html).

Each brittle object produces up to four authored angular shards with convex colliders,
one quarter of the source mass each, inherited post-contact motion and capped speed/spin.
Placement checks separate pieces from furniture and siblings before insertion,
searching within 30 cm; a piece is omitted if no safe placement exists. Colliders
have a 1 cm skin because [Godot Physics ignores shape margins](https://docs.godotengine.org/en/stable/classes/class_shape3d.html#class-shape3d-property-margin).
Small-body sweeps, increased rotational inertia and damping of quiet supported
motion prevent persistent edge rocking. Pieces stay dynamic and grabbable, and
sleep without freezing, including the shared supported-rest check. Re-grabbing clears settling
damping so subsequent throws retain their flight response. There is no recursive
fragmentation. The current room can create at most eight debris bodies. Restart
restores props and removes debris. Grabbable props report four support contacts;
intact impact receivers report eight. A shared helper tracks only awake props,
with event-based registration/removal and no material scan or physics-rate change.

Primitive necks/rims distinguish the vase and bottle, studs identify the plastic
toy brick, grain marks identify timber, and a handle/8 kg marking identifies the
iron weight. Ceramic shards are thick and opaque; glass shards are thinner and
translucent. A branched crack pattern marks the monitor's damaged screen.
Its collider now encloses the display and cracks in every state. The grabber
holds its geometry center instead of its floor-level pivot, rejects overlapping
or underfoot pickups and stops a hold whose actual body/pull path crowds the
player. Dropped bodies regain player collision only after separation.

For manual testing, gently drop a vase/bottle, then fully charge a throw into
a wall or floor. Throw the blue plastic block at the monitor, then try the metal
weight: a strong heavy hit should crack it, and another strong hit should kill
the screen. Pick up or move it again if the first hit knocks it off the desk.
Also try RMB cancellation, scattering/re-grabbing debris, finding keys with
debris present, and restarting. These are prototype thresholds and authored shards;
collision energy ignores detailed inertia/contact area, and fun still needs playtesting.

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
godot --headless --path . --fixed-fps 60 --script res://tests/impact_smoke.gd
godot --headless --path . --fixed-fps 60 --script res://tests/stabilization_smoke.gd
godot --headless --path . --fixed-fps 60 --script res://tests/contact_settling_smoke.gd
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
bounds, visible rotation, ring state/reset, RMB cancellation (including queued
inputs), stance changes and restart. Search tests also cover action metadata,
spawn visibility, partial occlusion and bounded all-exposed/mixed candidate pools. Existing
manipulation checks also exercise furniture contact while charging.
The impact test exercises real gentle/hard collisions, reduced-mass response,
material tolerance, bounded non-recursive debris and sleeping, monitor states,
sweep near misses/expiry, breakage while charging, and search completion/restart
with debris present.
The stabilization test compares equivalent impacts from 0.6/2/5 m, exercises
tumbling sweep/contact handoff, scene-pivot invariance, floor drops, thin walls
and tabletops at 26 m/s, monitor recovery in each real damage state, wall drops,
overlapping release/re-grab and underfoot pickup prevention. Floor checks allow
normal solver contact slop (2.5 cm bound), and inspect visible geometry rather
than treating a scene pivot as the bottom of the body.
All tests exit nonzero on failed checks.

The contact/settling test checks four walking masses, narrowing-gap passage and
backing out, eight real ceramic/glass impacts against tabletops, corners, edges
and undersides, physical motion, penetration bounds, sleep/drift and re-grab/throw.
It also covers six monitor resting orientations and subsequent pickup/throw,
three ordinary-prop contact fixtures, wake-up, and standing/crouched pickup,
drop and re-throw of ceramic/glass debris.

Resting/pickup stabilization with Godot 4.7.2: **738 checks passed** across
ten suites (35 physics, 44 manipulation, 124 search, 18 stance, 42 physical
search, 184 collision/throw, 81 charge, 29 impact/material, 58 stabilization,
123 contact/settling). Editor import and a rendered 600-frame main-scene launch
passed without errors. Walking fixtures moved 0.25/2/12 kg props by
2.37/1.90/0.32 m respectively; peak prop speeds stayed below 1.45 m/s.
All eight furniture breakup fixtures retained four pieces and slept within
15 simulated seconds, with less than 2 mm drift over the next two seconds.
All 60 collision fixtures passed, including
the 26 m/s cap. Rendered inspection confirmed the new room props, physics-driven
cracked/dead monitor states and ceramic/glass debris. Prior radial charge,
cancellation and search diagnostics checks remain covered. This does not replace
manual feel-testing. Prompt #4's rendered room/stance/search UI
checks and the reproduced native-CCD failures remain the basis of the sweep fix.
The native CCD limitation is consistent with its
[support-point ray implementation](https://github.com/godotengine/godot/blob/master/modules/godot_physics_3d/godot_body_pair_3d.cpp).

Controlled distance measurements were 393.846 severity at 0.6, 2 and 5 m
(16 m/s closing speed, 3.0769 kg effective mass). Restoring the old 1 mm sweep
overlap reproduced zero-severity tumbling hits at 4.8/5 m; the fix reports
389.156/386.676 respectively. Their difference reflects angular contact speed.
Restoring the old monitor collider reproduced excessive visible floor clipping
in four fall fixtures. No collider replacement occurs during monitor damage;
the floor-level pivot was also making its previous hold needlessly awkward.

Remaining manual checks: repeated recovery of monitors beside the desk/couch,
fast turns and stance changes while holding large props in corners, and tightly
packed multi-prop piles. All tested monitor/contact-pair fixtures now sleep and
remain still. Real ongoing motion or insufficient player/wall clearance still
prevents settling/pickup; no live-body teleport correction was added.

Movement, grabbing, throwing, rotation and hold distance have been successfully
playtested by the user; the original simple room ran around 180 FPS in debug/editor.
The expanded search room has automated physics/gameplay checks and scripted rendered UI
inspection. Stance/throw feel, search pacing, visibility and fun still need the user's manual
playtest. No destruction-load performance benchmark has been performed.
