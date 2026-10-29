# Where The Fuck Is It?

Physical-search graybox in Godot 4.x. Open `project.godot` in Godot
(validated with 4.7.2) and press **F5** for the Main Menu. Choose **Play** to
enter The Gamer's Room. The original search game is available with **F6** in
`scenes/search_game.tscn`. No plugins, assets, or editor setup required.
See [PROJECT.md](PROJECT.md) for scope and persistent design context.

## Tight-space pickup recovery — Milestone #9A.12

A comparable fallen-monitor pose reproduces every reported F3 field: surface
**1.2469 m**, no occluder, zero current penetration, padded proximity, overlapping
preferred target and the old `escape_blocked` rejection. The full enabled monitor
hull is at (1.4, 0.332, 2.16), rotated 90 degrees around Z; the standing player
origin is (1.5, 0.02, 1.695), aiming at monitor-local (-0.32, 0.05, 0).
The actual capsule has radius 0.30 m and height 1.80 m. Neither body currently
penetrates the other or World geometry. Moving the full hull only 25 mm outward
hits `Shell/SouthLeftCollision`, the wall beside the door. The former single-path
search therefore rejected a safely reachable object. Original user transforms
are unavailable, so this is a matching geometric reproduction.

Recovery now tries at most **seven straight directions**, stopping at the first
safe result: outward, the two outward/lateral diagonals, the two lateral directions,
outward/up and up. Every candidate retains the existing bounded distance search,
full-shape sweeps, contact-depth checks and 80 mm final player clearance. The
monitor uses candidate four, a lateral exit away from the wall; a low-lipped
furniture fixture uses candidate seven, upward. Solid lips plus a lid reject with
`no_safe_recovery_path`. F3 shows the selected direction and candidate count;
underfoot/inward-motion guards and contact-query overflow rejection remain.

The existing spring, inertia, rotation and per-tick chosen-path safety checks are
unchanged. The search runs on E pickup or a visible F3 preview (5 Hz), never on
every render/physics frame during a hold. Local full eligibility previews measured
0.08–1.83 ms across 20 samples, averaging 0.77 ms, including ordinary pickup and
seven-candidate rejection. This is a small local timing sample, not a hardware
benchmark. Camera/prop interpolation, 60 Hz physics, 1.60 m surface reach,
visibility gates, collision shapes, force tuning and #9A.10 target clamping stay
unchanged. No body transform writes or global collision changes were added.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_pickup_tight.ps1 -Godot 'C:\path\to\Godot_console.exe'
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_pickup_tight.ps1 -Godot 'C:\path\to\Godot_console.exe' -FrameRates 30 -Render
```

Validation: **39 checks** at each 30/120/180 fixed frame clock and another 39 in
the rendered run; **595 regression checks** across overlap, targeting, reliability,
held distance, camera, props, crosshair, kick and restart. Coverage includes the
door monitor, all stances, upward/trapped exits, native E/RMB/charged throw and
camera movement. Existing suites cover open-floor monitors, bed proximity,
occlusion/range, bottle/chair and restart cycles. No unexpected engine errors;
logs/geometry/timings/F3 captures stay in ignored `.validation/`.

Manual check: F5 → Play → F3. Drop the monitor on its side near the door, aim at
an exposed surface within 1.60 m and press E once. A safe lateral exit should
clear padding and stay held. Repeat crouched and approach from the side when
prone, then look, E/RMB drop, charge/throw and restart. Try a box near the bed,
bottle/chair, and an object blocked on the sides and above. Occluded/trapped exits
must reject. This bounded search cannot find curved or rotation-dependent escape
paths. A very close prone frontal view still triggers the separate existing
`no_target_clearance` hold guard after wall shortening; the side approach passes.

## Pickup overlap recovery — Milestone #9A.11

`body_overlaps_player` tested the **current** body against the actual player
capsule with a **60 mm query margin**. It was not a proposed-target test. That
single flag rejected both real penetration and nonintersecting shapes inside
the padding, including bodies with a safe outward exit.

Equivalent reproductions use the authored MovingBoxA collider (0.48 × 0.38 ×
0.42 m), the monitor's complete enabled convex hull and the actual stance capsule:

| Reproduction | Surface distance | Exact current penetration | Measured gap | Previous padded flag |
| --- | --- | --- | --- | --- |
| MovingBoxA, standing | 1.3334 m | 40.0 mm | 0 | true |
| MovingBoxA, 5 cm farther sideways | 1.3503 m | 0 | 10.0 mm | true |
| Fallen monitor, crouching | 1.1399 m | 0 | approximately 51.0 mm | true |

The first box pose has its centre at (-1.85, 0.195, 0.67) and the player origin
at (-1.35, 0.02, 0.67), using a radius-0.30 m, height-1.80 m capsule.
The monitor pose is (0, 0.132, -0.8), rotated 90 degrees around X; the crouched
player is at (-0.318198, 0.02, -1.118198), with radius 0.30 m and height 1.00 m.
Original user transforms were unavailable: these reproduce the reported distances
and failure predicate, rather than uniquely reconstructing those original poses.

Pickup can now enter a brief outward recovery when a full-shape escape is clear.
It finds the first outward pose satisfying the existing 80 mm player clearance,
sweeps all enabled shapes against World/Props, and checks existing contact normals
and sampled depths so an initial furniture contact cannot hide a blocked exit.
The unchanged spring moves the body; no transforms, collision shapes, global
collision settings or force coefficients are changed. Per-shape player depth
must decrease or stay within numerical tolerance, and world penetration must not
increase. These conditions and the exit are rechecked each physics tick. Recovery
finishes at normal clearance or aborts with a named reason after blockage,
worsening contact or a one-second timeout. Tested exits clear in 8–19 physics
ticks (0.13–0.32 seconds), then use the existing #9A.10 target clamp.

Read-only F3 now separates exact **current penetration**, the old **padding**
flag, **preferred/proposed target overlap**, and recovery status/rejection.
Underfoot bodies, inward-moving overlaps and blocked outward exits remain
rejected. Recovery intentionally tries one horizontal outward path; stepping
back or changing stance can still be necessary in a tightly trapped arrangement.
Reach remains 1.60 m with both sight-line checks. Ordinary hold/drop/throw/kick,
mass response, camera/prop interpolation and 60 Hz physics remain unchanged.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_pickup_overlap.ps1 -Godot 'C:\path\to\Godot_console.exe'
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_pickup_overlap.ps1 -Godot 'C:\path\to\Godot_console.exe' -FrameRates 30 -Render
```

The focused suite passes **51 checks** at each 30/120/180 fixed render clock and
51 in the rendered run. It covers single native E input, both reported-distance
reproductions, padded-only versus true overlap, blocked and underfoot rejection,
all three stances, a reachable box partly under the real bed and an occluded box.
Another **542 regression checks pass**: targeting 112, grab reliability 87, held
distance 52, camera 60, prop smoothing 37, crosshair 29, kick 87 and restart 78.
The former unconditional-overlap rejection fixture now has a genuinely blocked
exit. No unexpected engine errors were found; logs, contact geometry and rendered
F3 captures are in ignored `.validation/`. Import also preserves script UIDs.

Manual check: F5 → Play → F3. Approach MovingBoxA and a fallen monitor closely,
aim at an exposed surface within 1.60 m, and press E once. With a clear outward
exit, exact penetration should reduce to zero, padding should clear, and the
object should stay held. Repeat crouched/prone and partly under the bed. Block
the exit with furniture/a wall, or stand directly over the body: rejection should
name the unsafe escape. Check a bottle/chair, slow/fast look, E/RMB drop, charged
throw, kick, pause/resume and restart. Occluded surfaces must still reject.

## Reliable pickup targeting — Milestone #9A.10

The fallen monitor's ray hit, collision layer (Props/4), parent RigidBody3D and
E input were working. The reproduced failure accepted pickup, then immediately
released with `target_overlaps_player` on the same physics tick: the preferred
1 m target was inside the capsule while the monitor itself was clear. One flat
monitor surface was 1.545 m away, within the unchanged 1.60 m limit. Five of 28
accepted probe cases immediately dropped; changing the angle changed whether
that unsafe target was produced. Actual overlap, floor occlusion and out-of-reach
surfaces also explain legitimate failures and remain rejected.

When that preferred target overlaps the player, the grabber now finds a clear
point along the segment from the current body centre toward the target. Six
bounded overlap checks use the same shapes and 0.08 m margin as final target
validation, with a small endpoint backoff. It only applies with no wall hit or
an upward support plane; horizontal wall-shortened targets keep their existing
rejection behavior. The final overlap/path/forward-side checks, physical overlap
release and obstruction timeout still apply. The controller continues to apply
spring forces; it never sets body transforms or changes the requested distance.
While looking down, the monitor can stay farther than the preferred 1 m until
the aim is raised enough to lift it safely. Camera/prop interpolation, collision
shapes/layers, reach, wheel, spring, mass, rotation, throw and kick tuning are unchanged.

F3 now shows aimed collider → resolved pickup body, physical surface distance,
eligibility/rejection reason, occluder, player overlap and whether E is queued.
The latest attempt includes its count, physics tick and outcome, distinguishing
an accepted hold from a later release. Holding diagnostics show when the target
is player-limited. Preview queries do not modify transforms, input, hold caches
or attempt state. Pickup and preview share eligibility code and pure bounds
queries. The preview ray looks beyond reach to explain `out_of_reach`; actual
eligibility remains capped at 1.60 m from the physical eye with its visibility check.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_pickup_targeting.ps1 -Godot 'C:\path\to\Godot_console.exe'
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_pickup_targeting.ps1 -Godot 'C:\path\to\Godot_console.exe' -FrameRates 30 -Render
```

The focused suite passes 112 checks at each 30/120/180 FPS clock and another
112 in the rendered smoke run: one actual E press,
flat/front/back/side/upside-down monitors, different angles and stances, a nearby
wall, the fallen monitor beside the real bed/furniture, desk monitor, bottle and
chair, stable holding, look/lift, drop/re-pickup/charged throw, read-only diagnostics,
1.59/1.61 m boundaries, physical overlap/frozen-body rejection and thin-corner
parallax/occlusion. Seven existing suites pass another 430 checks. The rendered
run captures F3 eligibility and held-monitor views. Logs/JSON/images stay in
ignored `.validation/`; disposable probe scripts and intermediate traces are removed.

Manual check: F5 → Play, press F3. Pick up the upright desk monitor, then drop it
flat near the aisle. Aim at an exposed screen/housing surface within 1.60 m and
press E once. It should stay held while looking down; raise the aim to lift it,
then turn, E/RMB drop and charge/throw. Repeat on its side/upside down and near
the bed/wall, then try crouch/prone, a bottle and the chair's solid back/seat.
For a rejected attempt, read the surface distance, collider, reason and outcome.
Standing near a floor object can still put its surface beyond 1.60 m; crouch or
move closer. Genuine occlusion, existing player overlap and unsafe turns still
reject/release. The unrelated certificate-store diagnostic remains.

## Grab reliability and reach — Milestone #9A.9

The bedside bottle was actually released, then fell under gravity. Before any
behavior change, release logging reproduced `wall_clearance_below_minimum` in
six of eight slow/fast lifts. Looking up brought the wall behind the cabinet into
the clearance ray. Its safe shortened target (1.047–1.100 m) fell below the old
1.1 m preferred minimum, triggering release after 0.05–0.43 seconds despite no
player overlap, tracking failure or blocked sight line. Visual interpolation
followed the real body. Removing that preferred-minimum rejection alone kept
all eight original lifts held under the old distance settings.

Collision-shortened holds now use the existing target-shape, swept-path, actual
player-overlap and forward-side checks. Very small clearances still release, as
do excessive tracking error and a sight obstruction lasting over 0.25 seconds.
Normal physics contacts remain active against room geometry and other props.

| Parameter | New value |
| --- | ---: |
| Pickup reach to the accessible surface | 1.60 m |
| Preferred ordinary holding distance | 1.00 m |
| Wheel minimum before size adjustment | 0.75 m |
| Actual per-object minimum | max(0.75, bounds radius + player radius + 0.10) m |
| Wheel maximum / step | 3.00 m / 0.15 m |

Pickup retains the existing first-hit sight ray and physical-eye range/occlusion
checks: a reachable surface can belong to a body whose centre is farther away,
but walls/furniture block it. No camera/prop interpolation changes. The initial
request is capped by pickup distance, then clamped for size; the unchanged spring
pulls the body toward it without setting transforms. Larger props stay farther
out (the chair is about 1.05 m). Mouse-wheel changes are still clamped; collision
correction never writes back into the request. Spring/force/mass, rotation, kick,
charge/throw and impact/destruction tuning remain unchanged.

F3 retains distance/target diagnostics and now displays the last release reason
and tick. `PhysicsGrabber.last_release` stores the full distance/clearance/contact
snapshot plus body, position and velocity. Enable `log_release_reasons` on the
Grabber for `GRAB RELEASE:` console records. Reasons distinguish E/RMB/manual
drop, throw, menu/transition, Escape/focus/cursor release, removal/destruction,
player overlap, unsafe target/path, body behind camera, tracking error and the
obstruction timeout. Logging is opt-in; the last reason remains available in F3.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_grab_reliability.ps1 -Godot 'C:\path\to\Godot_console.exe'
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_grab_reliability.ps1 -Godot 'C:\path\to\Godot_console.exe' -FrameRates 30 -Render
```

Godot 4.7.2: **87 checks pass at 30/120/180 FPS clocks and in one rendered run**.
They cover the original bedside bottle positions at slow/fast lift rates, the
old-distance regression, monitor/chair, 1.59/1.61 m surface boundaries, occlusion,
standing/crouch/prone, rapid look, wheel bounds, rotation, E/RMB, charge/throw,
actual unsafe clearances/obstruction, removal and two pause/restart/menu cycles.
Ordinary bottle/monitor settle near 1 m; tight wall clearance can shorten it
temporarily without release or request drift. Initial support contacts retain
about 1 cm of existing solver tolerance. Six focused suites pass another 343
checks. The camera/hold-distance test fixtures were brought within the new reach;
camera timing assertions and runtime interpolation code are unchanged. The runner
rejects failed assertions and unexpected engine errors. Logs/JSON/screenshots use
ignored `.validation/`; the unrelated certificate-store diagnostic remains.

Manual check: F5 → Play. Approach the bedside bottle from the aisle, about one
metre in front of the cabinet. Aim at the bottle, E, then lift slowly and quickly
without scrolling; also turn beside the bed/wall. F3 should keep `Held: yes`
while space is safe. Repeat with the monitor and chair, using visible solid
surfaces rather than gaps between chair parts. Try just-inside/outside reach and
an object behind furniture, then crouch/prone, wheel in/out, R rotation, E/RMB,
charged throws and pause/restart. Extremely tight space or turning the body behind
the player may still safely release it; inspect the recorded reason.

## Held object distance stability — Milestone #9A.8

Close pickups previously always requested the exported preferred distance (2 m),
even when the monitor's collision centre was much closer. The spring drove it
outward as the view turned and desk/wall clearance changed. Camera rotation did
not change the request; the request was already too far away. The monitor's local
hold centre remains `(0, 0.305, 0)`; its stand/pivot and screen hit point are not
the distance reference. Visual interpolation was following the physical motion.

Pickup now caps the initial preferred distance at the measured camera-to-collision
centre distance. The existing size/player minimum (at least 1.1 m), maximum and
2 m preference for farther pickups remain. After pickup, only wheel input changes
the request. Collision clearance may temporarily shorten/lift the physical target;
it does not write back to the requested distance. Spring, mass/force caps, rotation,
throwing, player safety and both interpolation systems remain unchanged.

F3 adds a read-only snapshot at the existing 5 Hz refresh: requested distance,
physical collision-centre and pivot distances, displayed centre distance, last
physics target position/distance/error, local centre, clearance collider, cached
solver-contact count, blocked sight line and player overlap. Collision point counts
come from existing ImpactBody contact tracking; -1 means unavailable on other bodies.

```powershell
# Use an isolated APPDATA, as with the other settings-writing/gameplay suites.
godot --headless --path . --fixed-fps 120 --script res://tests/held_distance_smoke.gd -- --output=headless_120
godot --path . --fixed-fps 30 --script res://tests/held_distance_smoke.gd -- --render --output=render_30
```

52 checks pass at each 30/120/180 render clock and in one rendered smoke run.
The real desk monitor now retains its 1.506 m pickup distance instead of moving
out to about 1.80 m on the reproduced turn. In open space, a 1.25 m pickup previously
settled at 2 m with both old (45/12) and current (160/24) spring tuning; it now
settles at 1.25 m with both. The stronger spring accelerated the existing error;
it did not introduce it. Rapid yaw/pitch produces about 2–4 cm of temporary radial
lag in the open fixtures, then settles back. A blocked 2 m request temporarily
targets 1.492 m and returns to 2 m when cleared. Wheel, R rotation, throws, minimum
clearance and farther pickups are checked. JSON and a rendered F3 snapshot go to
ignored `.validation/`.

Existing feel/manipulation/charge/camera/prop/crosshair suites pass, as does the
restart suite at its documented 30 clock. Its one-render-frame impulse fixture
is not reliable above 60 FPS. The extra throw suite passes its behavior checks
but reports a shutdown resource leak, reproduced with the pre-fix scripts too.
Those test issues are unchanged. The unrelated certificate-store diagnostic remains.

Manual reproduction: F5 → Play. Approach the desk from its left/front, aim at
the monitor screen and press E with its centre roughly 1.3–1.5 m away. Press F3,
then yaw/pitch rapidly and lift it clear of the desk without scrolling. The
request should remain at pickup distance and actual distance should recover after
contact/lag. Check near walls, then wheel in/out, R + mouse, drop and charged throw.
Very close pickups still move out to the existing safety minimum; unsafe turns
still release. A monitor retains its world orientation, so turning can change its
apparent width even at a constant measured distance.

## Restart lifecycle — Milestone #9A.7

Restart removes the old room before its queued deletion, then immediately adds
the replacement. Until deletion, the old prop-smoothing helper still receives
the SceneTree's `node_added` signal. Its deferred registration previously queried
`get_world_3d()` on the detached old grabber while inspecting a new room prop.
Registration now returns if the helper/owner has left the tree or its deferred
node is no longer valid. Interpolation math, camera/HUD, transitions and physics
behavior are unchanged.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_restart_lifecycle.ps1 -Godot 'C:\path\to\Godot_console.exe'
# Add -Headless for the non-rendered check.
```

The runner isolates settings and fails on engine errors as well as failed
assertions. Godot 4.7.2: 78 checks pass in both rendered and headless runs across
four Play → Pause → Restart → Main Menu → Play cycles. Each teardown includes
moving room props and four tumbling fragments from a real bottle/wall collision.
Checks cover pause/resume, repeated activation, old-node deletion, fresh prop
registration, camera references and centred crosshair. The rendered baseline
logged 32 world-registration errors; the fixed lifecycle run logs none. Camera,
prop-smoothing and crosshair regressions pass another 126 headless checks.
The original rendered menu suite also passes all 50 checks without registration
errors (the same baseline suite previously logged 32).
Logs and a rendered snapshot are in ignored `.validation/`.

Manual check: F5 → Play, throw a bottle against a wall and move another prop.
Esc → Resume, then Esc → Restart while props/fragments are moving. Repeat
Esc → Main Menu → Play several times. Check cursor capture, centred aim and
smooth motion; the debugger should show no world-registration errors.

## Crosshair stability

The crosshair and throw-charge ring stay at their native screen-centre anchors.
There is one crosshair Label, with its original appearance. The HUD no longer
adds `aim_screen_offset` from a projected physics-camera hit. That offset cycled
between the stepped physical eye and interpolated visual eye during movement,
moving the label through fractional pixels. Stationary and wall-blocked movement
had no offset, matching the reported symptom. The old offset remains available
as a camera diagnostic; it does not position the HUD.

Pickup and kick share a sight ray from the displayed eye in the gameplay camera's
immediate look direction. Its hit projects to the fixed crosshair. Physical range
is still measured from the original gameplay camera; a second visibility check
prevents the eye offset reaching around an obstruction. Kick foot/cone/height
checks, hold targets, rotation, throw, input, physics and camera/prop smoothing
are unchanged. No HUD elements, fonts, rendering options or dependencies changed.

```powershell
godot --headless --path . --fixed-fps 180 --script res://tests/crosshair_smoke.gd -- --output=headless_180
godot --path . --fixed-fps 180 --script res://tests/crosshair_smoke.gd -- --render --output=render_180
```

Use isolated APPDATA as with the other suites. 29 focused checks pass at each
30/60/120/180 test clock; the rendered movement run adds five pixel-mask checks
for 34 passes. Forward/strafe/walk+look, idle, pushing against a wall, charging
while walking, pickup, occlusion and physical range are covered. Baseline forward
and strafe HUD motion was 4.21/6.04 pixels; corrected motion is zero. Eight rendered
crosshair masks per scenario are identical, with sight-hit projection error below
0.0001 pixels. Existing kick/manipulation/charge/menu/camera checks pass (320 checks).
Logs, JSON and before/after frame strips are in ignored `.validation/`.

Manual check: F5 → Play, walk/strafe and look around, then hold W into a wall.
The plus should stay still in all cases. Pick up nearby props, charge while
walking, drop and kick them; targeting should follow the centred plus and obey
the existing range/obstruction rules. Native graphics here run around 32 FPS;
the 180-clock renderer test proves stable output pixels, not monitor persistence
or physical display pacing at 180 Hz.

## Physics feel polish — Milestone #9A.6

Small/medium held objects now use spring strength **160** (was 45) and damping
**24** (was 12). The existing 50 m/s² acceleration and 240 N force limits remain;
large masses still accelerate more slowly when force-limited. The controller applies
forces at 60 Hz, retaining physical lag/contact response. Distance, rotation, throw
charge/speeds, drop, kick, input and both interpolation systems are unchanged.

Brittle fragments inherit post-contact motion, then receive one linear and one
angular impulse in their first physics callback, after mass/inertia initialization.
The strongest confirmed contact supplies world position, surface normal, incoming
direction and pre-clamp severity. The fan spreads away from the impact point,
continues glancing travel and rebounds away from the struck surface. Missing impact
context uses source motion/origin and the material threshold as a bounded fallback.

| Tuning | Glass | Ceramic | Other material default |
| --- | ---: | ---: | ---: |
| `fragment_scatter_speed` (base m/s) | 2.8 | 2.1 | 1.8 |
| `fragment_scatter_spin` (base rad/s) | 5.0 | 4.0 | 3.5 |
| `fragment_bounce` | 0.16 | 0.10 | 0.10 |

Edit the existing `resources/materials/*.tres` resources. Base scatter/spin scale
with `sqrt(severity / break_threshold)`, capped at 2×. The scatter component also
has a 6% impact-energy budget. Total launch velocity/spin remain capped at 6 m/s
and 7 rad/s. Four fragments, safe placement, CCD, sweeps and supported settling
are retained. The sweep remembers incoming speed for up to three ticks; only a
matching real contact restores restitution, capped at 0.9 m/s outward speed.
Held shards clear that hint. Durable materials keep their existing staged states;
they do not gain fragmentation. No new managers, effects or room physics objects.

Focused tests (use isolated APPDATA as with the existing suites):

```powershell
godot --headless --path . --fixed-fps 60 --script res://tests/physics_feel_smoke.gd -- --output=headless_60
godot --path . --fixed-fps 30 --script res://tests/physics_feel_smoke.gd -- --render --output=render_30
```

Run the headless case with 30/60/120/180 test clocks to repeat the FPS check.
JSON metrics and rendered screenshots go to ignored `.validation/`.
The fixture compares the old/new spring using the real bottle, 5 kg monitor and
8 kg chair; rapid-look input follows the same 60-Hz path at every render rate.
It includes a 7-cm wall, head-on/glancing glass/ceramic fractures, confirmed contact
data, impulse caps, bounce, sleep, menu pause/resume and three restarts.

Godot 4.7.2 validation: **72 checks pass at each of 30/60/120/180 render clocks**,
plus 72 checks in the rendered 30-clock smoke. Bottle/monitor reach 90% of an aim
step in 317 ms (previously 517 ms); chair takes 350 ms (previously 533 ms). Rapid
aim lag decreases 20–23%, with no measured step overshoot. All four clocks give
the same response timings. Glass/ceramic head-on and glancing fixtures spread
0.84–0.97 m, bounce, stay on the correct wall/floor side and sleep within eight
seconds. Existing impact/kick/manipulation/charge/stabilization/contact suites
pass 422 checks; menu/prop-smoothing guards pass 48/37 more. Both interpolation
files, player movement, project settings and the physics fixture are unchanged.

The rendered restart registration error recorded during #9A.6 is fixed in #9A.7
above. The sandbox certificate-store diagnostic remains unrelated to gameplay.
Native rendering here is around 32 FPS; forced render clocks establish simulation
behavior, not high-refresh display pacing.

Manual playtest: F5 → Play. Grab the bottle, monitor and chair in turn; sweep the
mouse quickly left/right and stop sharply. Expect quicker light/medium following,
a little lag and more resistance from the chair. Try R rotation, wheel distance,
tap/charged throws, RMB drop/cancel and empty-hand kicks. Throw/kick fragile props
head-on and diagonally into a wall and the floor. Watch the fan, tumble and small
bounces, then wait for sleep and re-grab/kick a shard. Repeat near furniture, pause
mid-action and restart several times. Static decorations remain static. Tight
holds can still release conservatively and normal solver contact slop remains.

## Physics prop smoothing — Milestone #9A.5

`PropVisualInterpolation` is a single presentation helper owned by the grabber.
It discovers grabbable rigid bodies and their meshes, captures consecutive physics
poses, and submits interpolated position/rotation directly to RenderingServer before
drawing. Physics stays at 60 Hz; the render fraction comes from Godot. Body transforms,
colliders, mesh node offsets/paths, interaction rays, forces and the camera are unchanged.
No gameplay FPS limit or refresh assumption is introduced. Native project-wide
interpolation remains disabled to preserve the existing camera timing setup.

Spawn history begins after final placement. External transform writes reset history;
future scripted teleports *inside a physics callback* should also call the helper's
`reset(body)` after placement. Restart/deletion discard history. Pause keeps the
displayed pose; resume rebuilds history over at most one physics tick. Brittle fragments
inherit the source's last displayed offset without changing their physical placement
or velocities. Damage-state visibility remains native. Resting props stop submitting
mesh transforms once their final pose is displayed.

A compound-shape clearance check rejects added penetration into static World
surfaces beyond endpoint contact tolerance. That safety fallback can briefly show
the current physics pose during tight rotating contacts. Dynamic contacts retain
the existing solver tolerances; this is visual interpolation, not a new collision
solver. Visuals may lag colliders by up to one physics tick (16.7 ms).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_prop_frame_rates.ps1 -Godot '<Godot executable>'
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_prop_frame_rates.ps1 -Godot '<Godot executable>' -Render
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_prop_frame_rates.ps1 -Godot '<Godot executable>' -RealTime
```

The focused matrix covers 30/60/120/180 render clocks, held/throw/kick actions,
movable furniture, monitor falls/sleep, fragments, teleport, pause/resume and repeated
recreation. Render runs also compare screenshot pixel centres with interpolated and
physical positions. JSON, logs and screenshots go to ignored `.validation/`, using
isolated APPDATA. Fixed clocks test transforms independently of achieved wall FPS;
use `-RealTime -Render` to check presentation on your own hardware.

Godot 4.7.2: all **136 headless / 142 rendered fixed-clock checks** pass, plus
136 real-time headless checks and 32 real-time rendered checks at a 30-FPS cap.
The controlled moving body has zero repeated visual poses at every tested rate;
at 120/180 clocks its physics position repeats on 29/59 sampled frame transitions.
Rendered pixel centres match the smoothed pose within 0.05–0.12 pixels on average.
Physics, kick, manipulation, destruction, camera and rendered menu regressions pass.
Native graphics here run around 32 FPS. Real-time headless caps reach about
30/60/120 FPS; the requested 180 cap reaches about 145. High-clock render checks
prove transform submission, not high-refresh physical display presentation.

Manual playtest: F5 → Play; pick up and walk with a bottle, throw it, kick nearby
props, move the chair, knock over the monitor, and watch objects settle. Repeat near
walls/furniture, pause/resume during motion, then restart several times. Compare at
30/60/120/180 caps supported by your hardware. Watch for contact fallback steps and
check that aiming, object charge/rotation, damage and search still behave normally.

## Camera smoothness across PC frame rates — Milestones #9A.4 / #9A.5

The active `VisualCamera3D` interpolates position between consecutive physics eye
positions on render frames. Physics remains **60 Hz**. The camera uses Godot's
physics interpolation fraction; pause/resume transitions use elapsed seconds and
one physics-tick duration. There is no render FPS target, frame-count multiplier
or display-refresh assumption in gameplay. Mouse-look rotation is copied in the
existing input callback without rotational smoothing. Global physics interpolation
remains disabled, and movement/interaction tuning is unchanged.

The original `Player/Camera3D` supplies gameplay look direction, physical range,
hold/rotation/throw and search references. Pickup/kick sight rays use the displayed
eye so their hits align with the fixed screen-centre crosshair and charge ring;
physical-eye range/occlusion and kick reach rules still apply. A near-plane clearance
sweep restricts unsafe visual eye paths. Scene entry/restart, external teleports
and pause/resume reset history; pausing retains the displayed pose.

The test suite runs the same elapsed-time scenarios at **30, 60, 75, 120, 144 and
180 FPS**, with physics at 60 Hz throughout. Movement and mouse input paths use
elapsed time, and assertions derive expected displacement from movement speed
and render delta. Test durations and settling waits use seconds. At 30 FPS,
multiple physics ticks occur between render frames; above 60 FPS, the view advances
between physics ticks. The game makes no assumption that a PC has a 180-Hz display.

Run the complete matrix (use `-Godot '<executable path>'` if Godot is off PATH):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_camera_frame_rates.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_camera_frame_rates.ps1 -Render
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_camera_frame_rates.ps1 -RealTime
```

The helper uses an isolated APPDATA for every case and restores the caller's
APPDATA afterward. Default runs use `--fixed-fps` for reproducible simulation
clocks; `-RealTime` uses only a frame cap and records actual elapsed frame timing.
Combine `-RealTime -Render` to check real graphics/display pacing on your hardware.
These flags configure test processes only; F5 gameplay has no imposed frame cap.
Logs, timing JSON and per-rate screenshots go to ignored `.validation/`.

Coverage includes walking + looking, immediate mouse rotation, constant movement
speed, physics tick counts, crouch/prone/under-bed traversal, jump/landing, nearby
pickup/hold/throw/kick, centred aiming, near-plane clearance, teleports,
pause/resume, FOV and repeated room recreation. Every moving view sample advances
at all six rates. Standing walking remains approximately 5.4 m/s; measured mean
per-frame travel follows the render interval:

| Render FPS | Mean walking travel per frame |
| ---: | ---: |
| 30 | 18.0 cm |
| 60 | 9.0 cm |
| 75 | 7.2 cm |
| 120 | 4.5 cm |
| 144 | 3.75 cm |
| 180 | 3.0 cm |

Godot 4.7.2 validation: **356 checks pass in each six-rate matrix** for headless
fixed clocks, native rendered fixed clocks and real-time capped headless loops.
The live graphics loop adds **58 passing checks** at about 32 FPS with variable
frame intervals. All rates retain 60-Hz physics, approximately 5.4 m/s walking,
zero repeated moving-view positions and immediate matching mouse orientation.
The original gameplay/aim camera and physics fixture remain unchanged in #9A.5.
Real-time caps at 30/60/75/120/144 achieved approximately those rates headlessly;
the requested 180 cap achieved about 145 in this environment. The fixed-clock
180 case still passed through both the engine loop and renderer. Cap settings and
achieved wall FPS are reported separately so hardware limits remain visible.

Physics correctness and stable interactions remain the priority at low FPS.
Position interpolation has up to one physics tick (~16.7 ms) of visual delay;
moving/held rigid props now use the presentation helper above. Mouse-only doubled
edges and GPU/monitor frame-pacing effects require separate hardware observation.
Fixed-clock graphics checks establish transform behavior, not physical presentation
at their requested rates; this environment's native graphics runs around 32 FPS.

Manual verification: F5 → Play, walk/turn past furniture, crouch/prone under the
bed, jump/land, and handle nearby props using the centred reticle. Pause mid-stride
and repeatedly Restart/Main Menu → Play. Compare different frame caps and window/
fullscreen modes available on the PC; the monitor's own refresh rate can stay fixed.

## Main Menu, Pause & Settings — Milestone #9A.3

F5 starts `scenes/main_menu.tscn`: Play, Settings and Quit. Mouse clicks,
arrow keys, Tab / Shift+Tab and Enter navigate the native Godot Controls.
During menu-launched gameplay, **Esc** pauses and releases the cursor;
Resume or Esc captures it again. Pause offers Resume, Restart, Settings and
Main Menu. Restart rebuilds the Gamer's Room and restores its props; Main Menu
clears the room. Physics and gameplay input stop while paused. Pausing drops a
held prop and cancels queued pickup/kick/throw and active charge. Losing window
focus also pauses; resuming is explicit.

Settings apply immediately and save automatically to `user://settings.cfg`
(on Windows, under `%APPDATA%/Godot/app_userdata/Where The Fuck Is It-/`).
Mouse sensitivity is 0.2–4× the original 0.0025 radians/pixel, vertical camera
FOV is 60–110° (default 75°), Master volume is 0–100% (default 100%), and the
fullscreen switch selects fullscreen/windowed mode. Existing and newly spawned
players use the saved sensitivity/FOV, including standalone fixtures. Master
volume configures the audio bus; the prototype currently has no authored audio.
Esc/Back returns settings to the menu that opened it; gameplay remains paused
when settings were opened from Pause. No game-state saving or mission selection.

Standalone F6 Gamer's Room, search and physics scenes remain available; their
original Esc cursor-release behavior is preserved outside the menu shell.

Focused checks (set an isolated APPDATA so probes do not replace personal settings):

```powershell
$env:APPDATA = Join-Path (Get-Location) '.validation/menu_checks_appdata'
godot --headless --path . --editor --import --quit
godot --headless --path . --fixed-fps 60 --script res://tests/menu_smoke.gd --quit-after 1200
godot --headless --path . --script res://tests/menu_smoke.gd -- --settings-write
godot --headless --path . --script res://tests/menu_smoke.gd -- --settings-read
godot --path . --fixed-fps 60 --script res://tests/menu_smoke.gd --quit-after 1200 -- --render
```

Run the existing physics/room/kick/manipulation/charge/search suites with a
separate, clean APPDATA because their baseline checks expect default FOV.
Rendered proof images are written under ignored `.validation/`.

#9A.3 validation on Godot 4.7.2: **48 headless menu checks, 50 rendered menu
checks and 7 cross-process persistence checks passed**. The six existing suites
also passed **417 checks** (35 physics, 46 room, 87 kick, 81 charge, 44 manipulation,
124 search). Editor import, a normal rendered 180-frame project launch and a
180-frame standalone physics-room launch passed. Rendered UI inspection covered
1280×720, 800×450 and 640×360 views, and actual fullscreen/windowed switching.
Only the previously documented certificate-store message and search-suite
shutdown resource leaks remain. Tests used isolated APPDATA directories and did
not replace personal settings. Prior layout/furniture/monitor edits are preserved.

Manual playtest:

1. F5: navigate Play/Settings/Quit using keyboard and mouse. Choose Play.
2. Move/look/grab a prop and charge a throw; Esc should drop/cancel and freeze
   the room. Try WASD, jump, crouch/prone, E, RMB, wheel and mouse look while
   paused. Resume using Esc and the Resume button.
3. Restart several times, then Main Menu → Play several times. Expect a fresh
   room, working controls and captured cursor each time. Alt+Tab and resume.
4. Change sensitivity/FOV from Pause Settings, return and judge mouse look/FOV.
   Toggle fullscreen/windowed; set volume to zero then restore it. Quit and F5
   again: expect saved values and window mode. Confirm search/physics F6 launches.
5. Resize the game window; check focus outlines, readable menus and access to Back.

## The Gamer's Room — Milestone #9A

Open `scenes/gamers_room.tscn` and press **F6**, or launch it directly:

```powershell
& "C:\Users\Home\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "D:\WTF-is-it\wtfisit" res://scenes/gamers_room.tscn
```

This command uses the currently installed executable and works from any terminal
directory. The shorter `godot --path . ...` commands below assume Godot is on
PATH and the terminal is in the project directory. Administrator privileges
are not required.

This separate layout sandbox has a **4.5 × 4.5 m clear interior (20.25 m²)**
and a **2.7 m ceiling**. Spawn on the clear landing at the south entrance;
the bed occupies the west side, the gaming desk faces the north window, and
wardrobe/dresser/shelves sit around the perimeter. The central aisle connects
the entrance, bed, desk and storage. The raised bed has 0.52 m underside clearance
for prone traversal between its legs.

Major furniture is reusable primitive geometry in `scenes/furniture/`: desk
(including a fixed tower, keyboard and mouse silhouette), chair, bed, wardrobe,
dresser, shelves and bedside table. The bed, desk, wardrobe, dresser and shelves use fixed World colliders; the
chair and bedside cabinet use movable Props colliders. Temporary wood/fabric
colors and solid cabinet fronts remain placeholders. The closed entrance
door and opaque blue window are static geometry, with no opening interaction.
There are no drawers, animations, new search spots or search objective in this
layout scene. F5 now enters it via Main Menu → Play; `scenes/test_room.tscn`
remains the original physics fixture.

Two boxes reuse `physics_prop.tscn`; a desktop-sized inherited monitor reuses
the original monitor's impact script and damage states. The existing bottle,
wood block and plastic brick are also movable. All use the existing player,
grab/drop/rotate/charged throw/kick, collision, impact and settling systems.
Pause → Restart restores this layout when launched through F5; standalone F6
can be relaunched to restore it. Enter/F4/F7 are search-game controls.

Focused validation:

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --fixed-fps 60 --script res://tests/gamers_room_smoke.gd
godot --headless --path . res://scenes/gamers_room.tscn --quit-after 180
```

Milestone #9A baseline, Godot 4.7.2: **37 room checks and 18 stance checks passed**. Editor import,
headless scene launch and rendered entrance/desk/storage inspection passed. The
local sandbox still reports the previously observed certificate-store warning.

### Scale audit and kick reach — Milestone #9A.1

Measurements use unit-scale physics roots and metres. The nominal geometry
below includes the bed headboard and wardrobe fronts. #9A.2 retains those visible
dimensions and adds a 0.01 m collision skin to upward support faces.

| Measurement | Current value |
| --- | --- |
| Player standing height / diameter | 1.80 / 0.60 m |
| Standing eye / crouched eye / prone eye | 1.60 / 0.82 / 0.28 m above feet |
| Camera FOV | 75° vertical; 107.51° horizontal at 16:9 |
| Interior / ceiling | 4.50 × 4.50 m (20.25 m²) / 2.70 m |
| Bed overall W × D × H | 1.39 × 2.165 × 0.92 m |
| Bed frame / mattress / underside | 1.35 × 2.15 m / top 0.78 m / clearance 0.52 m |
| Desk W × D × H | 1.60 × 0.72 × 0.75 m |
| Wardrobe W × D × H | 1.25 × 0.605 × 2.10 m (carcass depth 0.58 m) |
| Bed-to-desk / bed-to-chair lateral clearance | 1.295 / 1.815 m |
| Bed-to-wardrobe foot area, before loose boxes | 1.56 m |
| Wardrobe-to-authored boxes | 0.638–0.715 m; movable clutter, outside the main aisle |
| Bedside-table-to-desk pinch point | 0.565 → 0.715 m |
| Entrance width between jambs | 0.94 m; door remains a closed placeholder |

The player is adult-sized; the 1.60 m eye is a conservative viewpoint for the
1.80 m collision envelope. The ceiling, desktop and wardrobe are plausible
household scale. As comparison examples, IKEA's [MITTZON desktop](https://www.ikea.com/gb/en/p/mittzon-desk-white-s09529087/)
is 1.60 × 0.80 m, and [PAX carcasses](https://www.ikea.com/se/en/p/pax-wardrobe-frame-white-70214564/)
are 0.58 m deep and 2.01 m tall. The bed is compact adult length/width with an
unusually tall raised sleeping surface, intentionally retaining the prone route.
The broad FOV can affect apparent proportions; [Godot documents the vertical-to-horizontal conversion](https://docs.godotengine.org/en/stable/classes/class_camera3d.html#class-camera3d-property-fov).
Room dimensions, bed height, eye height, FOV and movement speed were retained.

The only layout fix moves the desk, chair, monitor and desktop block 0.15 m east.
The formerly 0.565 m passage was smaller than the 0.60 m standing capsule;
it now leaves 0.115 m spare and passes an actual walking-route check.
The 0.15 m desk-to-wall gap and 0.25 m chair-to-desktop gap are furniture gaps,
not walking routes; approach the desk from its open left side.

Kick eligibility now combines the original camera/leg rays and nominal 1.35 m
upper bound with an ankle-distance bound, a contact-height envelope relative to
the current feet, a forward cone and a 0.06 m radius swept foot volume. Contacts
below feet by more than 0.10 m, above 65% of the actual stance capsule height,
underfoot, or behind low/side obstacles are rejected. The foot volume starts
0.12 m above feet; tiny floor contacts lift its endpoint enough to clear the floor.
This is an approximate physical reach envelope, without a leg animation.
F3 uses the same eligibility query as the kick and reports foot distance and
relative contact height only for valid targets. Impulse, cooldown and impacts
retain their existing tuning.

Regression: a fallen monitor beside the bed is visible and 1.317 m from the old
lower-body origin, but its contact is 0.645 m below the standing player's feet.
The kick and F3 both reject it. The same monitor is kickable after stepping onto
the floor; a box on the bed remains kickable from the bed. Low rails, sideways
toe obstructions, high contacts, all three stances, debris, materials and input
precedence are covered by the existing kick suite's focused additions.

Run `tests/kick_smoke.gd`, `tests/gamers_room_smoke.gd` and
`tests/physics_smoke.gd` with the existing headless/fixed-fps commands.

#9A.1 validation on Godot 4.7.2: **168 checks passed** (87 kick, 46 room/scale,
35 preserved physics-room checks). Editor import, a rendered 180-frame Gamer's
Room launch, a 180-frame headless physics-room launch and rendered F3 bed/floor
views completed. Only the existing sandbox certificate-store warning remains.

Manual verification: enable F3, drop the monitor flat beside the bed, jump onto
the bed and aim at it. Expect no kick target and no motion on RMB. Step down,
aim again and kick; expect a valid target and normal impulse. Try a box on the
bed, floor props in standing/crouch/prone, and props behind furniture legs. Walk
the widened gap between the desk and bedside table. Restart F6 to restore props.

### Furniture physics and surface contact — Milestone #9A.2

Gentle drops and actual grabber hold/release placement reproduced approximately
9–11 mm of visible bottle penetration into cabinet tops. The bottle mesh and
colliders matched, the top collider covered the visual surface, and the held
bottle cleared the surface before release. Wood/plastic blocks and ordinary
boxes showed the same resting overlap. This matches Godot Physics's
[default 0.01 m allowed contact penetration](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-physics-3d-solver-contact-max-allowed-penetration).
The shared supported-rest helper then slept the accepted contact pose; there
was no persistent jitter or placement teleport to fix.

Upward support faces now have an explicit 0.01 m collision skin: cabinet tops,
desktop, chair seat, bed layers, shelf boards and wardrobe top. The underside
of each support stays unchanged, preserving prone clearance. The bottle and
other prop scenes, visible geometry, room dimensions, grab/release code and
global solver settings are unchanged. The two dynamic furniture pieces also
have a 0.01 m sole skin to limit visible sinking into the floor.

| Movable furniture scene | Mass | Local centre of mass |
| --- | ---: | --- |
| `scenes/furniture/chair.tscn` | 8 kg | (0, 0.43, 0.035) m |
| `scenes/furniture/bedside_table.tscn` | 12 kg | (0, 0.25, 0) m |

Both are ordinary, unfrozen RigidBody3D bodies on Props, with compound box
colliders, CCD, four support contacts, the grabbable group and the shared rest
helper. Their friction is 0.65, bounce 0, and damping uses the ordinary-prop
values. There is one bedside cabinet instance in the current room; all future
instances of its reusable scene inherit this physics. Bed, desk, wardrobe,
dresser and shelves remain static. No furniture damage states were added;
existing ImpactBody projectiles still use actual dynamic reduced mass on contact.

Focused validation: **217 checks passed** (84 furniture/surface, 46 room,
87 kick). Editor import, a rendered 180-frame Gamer's Room launch, before/after
surface inspection and a 180-frame physics-room launch completed. Only the
existing sandbox certificate-store warning remains.
The new `tests/furniture_surface_smoke.gd` exercises thirteen gentle
placements, bottle hold/release on two cabinets, loaded chair/cabinet rest,
player pushes, kicks and real charged throws using existing impact props.
Measured visible support gaps across those placements were -0.59 to +0.88 mm;
loaded pairs slept and drifted less than 2 mm over the subsequent two seconds.
Thrown impacts were measured with deterministic test-only tumble, and gave small
5–9 mm nudges with the existing collision protection. Push/kick movement is
more noticeable; thrown-hit strength remains a manual feel-testing concern.

Run this focused suite with:

```powershell
godot --headless --path . --fixed-fps 60 --script res://tests/furniture_surface_smoke.gd
```

Manual verification: grab and gently place the bottle on the bedside cabinet
and dresser; inspect the base from the side, wait for settling, then re-grab it.
Try a box, wood block and plastic brick on the same surfaces and the chair seat.
Push and kick the chair/cabinet, including with an object on top; try thrown
impacts and lifting/rotating furniture in the tight aisle. A deliberate shove
can tip furniture or spill its load. Judge moving-stack behavior and the small
thrown-impact response by feel. F6 restores the authored layout.

### Monitor fall settling

An exact spinning face-down fall reproduced persistent 3.5–4.4 mm corner rocking
per physics step. Separate screen/base box contacts alternated between two and
four floor contact points. With the existing supported-rest helper disabled in
the diagnostic fixture, this continued beyond 30 seconds; the helper had been
masking it by sleeping the rocking body.

Both monitor scenes now use one convex hull around the existing collision boxes,
giving one contact manifold. Outer bounds and visuals stay unchanged; the hull
conservatively fills the gaps around the stand. Mass remains 5 kg, friction 0.85,
bounce 0.02, and linear/angular damping 0.15/0.4. Mass moments remain automatic;
the centred hull gives local COM heights of 0.305 m (desktop) and 0.525 m (large),
previously 0.385/0.624 m. Solver settings, margins, impulses, controls, impact code
and the shared sleep helper are unchanged. No freezing or new sleep forcing.

```powershell
godot --headless --path . --fixed-fps 60 --script res://tests/monitor_settling_smoke.gd
```

Godot 4.7.2: **130 monitor checks passed** across 38 falls, including face-down,
face-up, both sides, upright and tilted, with 0/2/7 rad/s spin and the exact bad
fall. No rest helper runs in these falls; native sleep took at most 3.22 seconds,
final three-step corner motion was under 0.01 mm per step, and two-second drift
was zero. Four fallen-monitor pickup/throw cases also passed without the helper.
The existing room suite passed 46 checks; focused existing damage/recovery and
bed kick fixtures passed 12 and 10 checks. Twelve furnished-room diagnostics,
editor import, rendered face-down/sideways falls and physics-room launch passed.
Only the existing sandbox certificate-store warning remains.

Manual check: drop and throw the monitor face-down and sideways, wait for its
brief physical settling, then pick it up and throw again. Repeat beside the bed,
desk legs, chair and wall; judge the conservative hull around the stand when
handling it near other props. Moving supports and crowded piles can still move.

Manual playtest focus: judge the room's scale, chair/desk access and entrance
clearance; crawl under the bed; lift boxes into the aisle before turning/throwing.
The existing conservative hold may release large props when turning toward the
wardrobe, shelves or a nearby wall. Boxes can obstruct a route after being moved.
The chair and bedside cabinet are movable; the larger furniture remains fixed. Automated checks and rendered inspection do not establish feel.

In the original search game, search for the physical keys, moving clutter and
looking under/behind furniture. Press E while aiming at the keys to complete the run. The result shows
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
| Right Mouse Button | Kick when empty-handed; drop held prop and cancel an active/queued throw |
| Escape | Pause in F5 gameplay; release mouse/drop prop in standalone F6 scenes |
| Left click with free cursor | Capture mouse |
| Enter after completion | Search again; reset room, player and timer |
| F3 | Toggle stats; debug builds also show kick target / range, charge and held material / damage state / last impact / thresholds |
| F4 (debug builds only) | Show/hide search state, target, spot, category, action and spawn rejection counts |
| F7 (search diagnostics visible, debug only) | Reset and reroll the search |

With empty hands, aim at a nearby prop and press RMB to kick. Aim down for floor
clutter. The nominal 1.35 m bound also requires a reachable contact height,
forward foot direction and clear camera, leg and swept foot paths. Standing
on furniture cannot reach floor props below the feet. Each press has a 0.45 s
cooldown, including misses.
Kicks apply up to 10 N·s at the hit point, with a slight upward component; very
light props gain at most 10 m/s, 2 kg props 5 m/s, 5 kg props 2 m/s and 12 kg
props about 0.83 m/s before collision response. Off-center hits tumble props.
Kicked ceramic/glass can break on real wall/floor impacts using the existing
material thresholds. There is no direct kick damage or extra damage model.
RMB while holding retains the existing drop/cancel behavior and never kicks.

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
godot --headless --path . --fixed-fps 60 --script res://tests/kick_smoke.gd
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

Prompt #8 kick validation: **784 checks passed** across eleven suites (43 kick
checks plus 741 existing checks, including the bedside furniture regression).
Editor import and a normal rendered 600-frame launch passed. Search and throw
suites report shutdown resource leaks also reproduced in an isolated copy of
the committed pre-kick project; those existing leaks were left outside this pass.
Manually evaluate reach/cooldown feel, stool and monitor response, and kicking
tiny shards beside walls or in piles, where contact braking can stop them quickly.

Resumption finishing pass: **63 kick and 124 search checks passed**. F3 now shows
the eligible kick target, hit distance and maximum reach. Contact checks confirm
ceramic/glass wall fractures and a ceramic fracture against the actual dynamic
bedside table through the existing impact system. All seventeen hiding spots
remain occluded from the entrance after settling and retrievable; no spot edits
were needed. Editor import and a 180-frame headless launch completed. The sandbox
reports a certificate-store warning; the existing search shutdown leaks remain.
Physics tuning, controls and search behavior were preserved.

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
