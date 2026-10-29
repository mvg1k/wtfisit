# Where The Fuck Is It?

A small first-person household physics sandbox: search for a randomly hidden
everyday object (keys, phone, wallet, etc.). Searching adds mild stress; moving
and throwing household clutter provides play and stress relief.

## Principles

- Destruction must NEVER economically punish the player or block progression.
  Careful or fast play may earn bonuses; destructive play remains valid.
- Prefer systemic material/state interactions over hardcoded object pairings.
- Build small playable increments. No giant GameManager or speculative systems.
- Primitive geometry, no external assets, plugins, or dependencies for now.

## Tight-space pickup recovery — Milestone #9A.12

- Reproduced the reported fields at 1.2469 m using the actual standing capsule
  and full side-fallen monitor hull by the door, with zero player/world depth.
  The original outward target enters `Shell/SouthLeftCollision`; a lateral exit
  is safe. README records comparable poses; original user transforms are unknown.
- Recovery now tries seven bounded straight directions, including lateral and
  upward exits, using the unchanged full-shape sweep/contact-depth checks. F3
  exposes direction/count and `no_safe_recovery_path` rejection. Planning occurs
  only on pickup or visible 5 Hz F3 preview; the held physics loop validates its
  selected path without replanning. Full local previews: 0.08–1.83 ms, 0.77 ms
  average over 20 samples. No reach/LOS, spring, collider, target-clamp, camera,
  interpolation or physics tuning changes. Rotation/curved escapes are outside
  the bounded search; existing prone frontal wall-shortened clearance can still
  reject with `no_target_clearance`, while a side approach passes.
- `pickup_tight_smoke.gd` / strict runner pass 39 checks at 30/120/180 clocks and
  a rendered run, including door geometry, three stances, upward/solid-lid cases,
  native E/drop/throw and look. Nine regression suites pass another 595 checks,
  including monitor/open-floor, bed box, bottle/chair, occlusion/range and restart.
  Rejection fixtures now block all candidate exits; the old one-wall fixture
  correctly recovers laterally. No unexpected engine errors; evidence is ignored
  under `.validation/`.

## Pickup overlap recovery — Milestone #9A.11

- The old `body_overlaps_player` predicate queried current geometry with a 60 mm
  margin. It conflated real capsule penetration and padding-only proximity;
  proposed-target overlap was a separate check. Equivalent authored full-shape
  reproductions: MovingBoxA surface 1.3334 m / 40 mm actual penetration; crouched
  fallen monitor surface 1.1399 m / zero penetration / approximately 51 mm gap.
  Original user transforms cannot be uniquely recovered from surface distance.
  README records the measured capsule/body geometry and deterministic poses.
- A padded overlap is eligible only with a verified horizontal outward exit.
  Full-shape sweeps plus existing contact normals/depths prevent worsening
  World/Props contacts; per-shape player depths must not increase. The existing
  spring performs recovery, revalidated every physics tick with a one-second
  timeout, then resumes ordinary #9A.10 target clamping. Tested exits take 8–19
  ticks. Underfoot, inward-moving and blocked overlaps remain rejected; this is
  deliberately a single-path recovery, not an escape planner. F3 distinguishes
  exact current penetration, padded proximity, preferred/proposed-target overlap,
  recovery status and rejection. No shape shrinking, global collision changes,
  physics tuning, reach/LOS changes or interpolation edits.
- `tests/pickup_overlap_smoke.gd` and strict-log runner pass 51 checks at each
  30/120/180 fixed render clock and in a rendered 30-clock run. They use actual
  room props and stance capsules, one native E press, safe/unsafe overlap,
  partial-bed clearance and bed occlusion. Eight relevant regression suites pass
  another 542 checks, including bottle/chair, drop/throw/look, interpolation,
  kick and restart. The prior targeting rejection fixture now blocks the exit
  instead of assuming every overlap must reject. No unexpected engine errors.

## Reliable pickup targeting — Milestone #9A.10

- Reproduction showed E was processed and the monitor's Props/4 collider resolved
  to the correct parent RigidBody3D. Five of 28 accepted probe pickups released
  immediately with `target_overlaps_player`: the preferred 1 m target entered the
  capsule despite a clear current pose and reachable surface (1.545 m in the flat
  reproduction). Angle changes altered this clearance result. Other misses were
  genuine range/occlusion/overlap rejection, not missing E input or wrong layers.
- A player-overlapping preferred target can now be limited along the segment from
  the clear current centre toward that target, using six exact overlap queries
  and a small endpoint backoff. Only empty/upward-support ray hits permit this;
  horizontal wall-shortening, final shape/path/forward and actual-overlap guards,
  obstruction timeout and spring forces remain. Requested distance stays fixed;
  down-look holds can remain farther out until the aim is safely raised. No
  camera/prop interpolation, collision shape/layer, reach or physics tuning edits.
- Pure bounds/eligibility queries feed both pickup and read-only F3 diagnostics:
  aimed collider/resolved body, surface distance, eligibility/reason, occluder,
  overlap and queued E state. Last attempt count/tick/outcome exposes actual
  acceptance versus release. Holding stats expose player-limited targets. A
  longer preview ray diagnoses out-of-reach surfaces; physical reach remains
  1.60 m with the existing physical-eye visibility gate.
- `tests/pickup_targeting_smoke.gd` and strict-log runner cover 112 checks at
  30/120/180 clocks: native E, all monitor poses/angles/low stances, nearby wall,
  fallen monitor beside real bed/furniture, desk monitor, bottle/chair, hold/look,
  drops/re-pickup/throws, diagnostic purity and real range/occlusion/overlap/frozen
  rejection, including eye-parallax guards. Seven existing suites pass 430 checks.
  Rendered smoke also passes all 112 checks and captures F3 eligibility/holding
  views. Evidence uses `.validation/`;
  disposable probes/intermediate traces are removed. Commands, limits and manual
  steps are in README. Existing unsafe-release rules and unrelated certificate
  store diagnostic remain.

## Grab reliability and reach — Milestone #9A.9

- Diagnostic-only release logging reproduced the bedside bottle issue before
  changing behavior: six of eight slow/fast lifts actually released with
  `wall_clearance_below_minimum` after 0.05–0.43 s. The wall behind the cabinet
  shortened the target to 1.047–1.100 m, below the old preferred 1.1 m minimum,
  despite clear player shapes and sight. This was a physical release, not visual
  interpolation or a weak spring. Removing that rejection alone kept all eight
  lifts held with the old distance settings. Collision-shortened holds now rely
  on existing shape/path/player checks, small-clearance and tracking guards and
  the unchanged 0.25 s sight-obstruction timeout. Physics contacts remain active.
- Pickup reach is 1.6 m to the first accessible surface, with existing physical
  range/visibility checks. Preferred hold is 1.0 m, base wheel minimum 0.75 m;
  actual minimum remains max(base, collision-bounds radius + player radius + 0.1).
  Wheel maximum/step remain 3.0/0.15 m. Size limits keep the chair near 1.05 m.
  Existing pickup-distance cap prevents outward default drift; physical spring
  motion pulls ordinary props smoothly toward 1 m. No transform snapping or
  render-rate logic. Camera/prop interpolation, force/mass/torque/throw/kick and
  impact/destruction tuning are unchanged.
- `last_release` retains exact reason, tick and distance/target/collision/velocity
  snapshot. Optional `log_release_reasons` prints it; F3 shows the last reason.
  Every grabber release path is named, including explicit inputs, menus, focus,
  clearance/path/player checks, tracking and obstruction. A one-shot held-body
  exit callback records removal/destruction and clears the dying hold without
  re-tracking it; explicit releases disconnect that callback.
- `tests/grab_reliability_smoke.gd` and strict-log PowerShell runner: 87 passes at
  each 30/120/180 clock and in one rendered run. Covers real bedside bottle,
  monitor/chair, slow/fast lifts, legacy-distance root regression, boundary surface
  reach/occlusion, three stances, wheel/look/rotation, drops/charge/throw, genuine
  safety releases, removal and pause/restart/menu cycles. Six focused existing
  suites pass 343 checks; two camera/hold-distance fixtures now fit the shorter
  reach. Runtime protected systems remain unchanged. Evidence in `.validation/`;
  commands/manual steps in README. Existing contact tolerance and unrelated
  certificate-store diagnostic remain.

## Held object distance stability — Milestone #9A.8

- Close pickup always seeded the preferred 2 m request, regardless of actual
  camera-to-collision-centre distance. Desk/wall clearance temporarily hid or
  limited that outward spring pull; turning exposed it. Requested distance never
  ratcheted during yaw/pitch. Monitor hold offset remains the collision-bounds
  centre `(0, 0.305, 0)`, not its foot pivot or screen-hit offset. Both old and
  current springs reproduce the bug; stronger tuning only makes it happen sooner.
- Pickup now caps the preferred initial distance at measured centre distance,
  retaining existing size/player safety clamps and farther-pickup preference.
  Wheel remains the only normal request adjustment after pickup. No force,
  damping, torque, throw, collision, camera or visual interpolation changes.
- Opt-in `get_hold_diagnostics()` and F3 show requested/physical/pivot/displayed
  distances, local centre, last physics target/error, clearance collider, cached
  contact count, sight blockage and player overlap. Diagnostics never drive control.
- `tests/held_distance_smoke.gd`: 52 checks pass at 30/120/180 clocks and rendered
  at 30. Real desk pickup stays 1.506 m (previous turn ended around 1.80 m);
  open pickup stays 1.25 m (previously 2 m). Rapid-look radial lag is about 2–4 cm,
  settling without a permanent increase. Obstruction temporarily shortens a 2 m
  target to 1.492 m, then returns to 2 m. Both spring tunings, wheel, R rotation,
  throws, near safety clamp and far preference are covered. Protected systems
  retain their regression checks. Evidence is in ignored `.validation/`.
- Existing restart regression's one-frame impulse assertion needs its documented
  30 clock; a 120 render clock can sample before physics. Extra throw regression
  passes behavior assertions but has a pre-existing shutdown resource leak,
  reproduced with baseline scripts. Neither test issue is changed in this fix.
  Manual steps, diagnostic fields and commands are in README.

## Restart lifecycle — Milestone #9A.7

- The old room is removed, then queued for deletion before the new room enters.
  Its still-live PropVisualInterpolation helper receives global `node_added`
  events and deferred registrations for the replacement room. The old grabber
  is already outside the tree/world; its world comparison caused the native
  `get_world_3d()` registration error. `_register()` now rejects detached helpers,
  invalid/detached owners and invalid deferred nodes before accessing a world.
- No interpolation math, camera/HUD, transition code, interaction or physics
  tuning changes. `tests/restart_lifecycle_smoke.gd` and its PowerShell runner
  exercise four complete restart/menu cycles with moving props and real bottle
  fragments, pause/resume, duplicate activation, fresh registration and deletion.
  78 checks pass headless and rendered. The runner rejects engine errors even
  when Godot exits successfully. Baseline rendered menu: 32 world-registration
  errors; fixed lifecycle: zero. Camera/prop/crosshair regressions: 126 passes.
  Evidence stays in ignored `.validation/`; manual steps and command in README.

## Crosshair stability fix

- The original HUD had one Label, but moved it and the charge ring every render
  frame using `VisualCamera3D.aim_screen_offset`. Projecting a stepped physics-eye
  hit through the interpolated view produced 4.21/6.04 px forward/strafe motion;
  stationary and wall-blocked samples were stable. Native screen-centre anchors
  now position both indicators; the camera offset is diagnostic only.
- `PhysicsGrabber.get_aim_hit()` shares the displayed-eye sight line for pickup
  and kick using the existing gameplay look direction. Original-camera distance
  and visibility checks retain physical reach/occlusion; kick leg/cone/height
  rules remain. Hold/throw/rotation, both interpolation scripts, player physics,
  project settings and HUD scene/style are unchanged.
- `tests/crosshair_smoke.gd`: 29 checks at each 30/60/120/180 clock, plus 34 in
  the rendered movement run. Corrected HUD motion is zero; eight pixel masks per
  scenario match. Sight-hit projection error is below 0.0001 px. Includes charging
  while walking, pickup, obstruction/range and blocked movement. Existing kick,
  manipulation, charge, menu and camera suites pass 320 checks. Logs/strips use
  ignored `.validation/`. Physical monitor persistence remains a hardware check.

## Physics feel polish — Milestone #9A.6

- Only the existing hold spring exports change: strength 45 → 160, damping
  12 → 24. The 50 m/s² acceleration and 240 N force limits preserve inertia and
  heavier-prop resistance. Holding remains force-based at 60 Hz. Distance, torque,
  charge/throw, RMB/drop, kick, movement and both interpolation scripts are unchanged.
- Qualifying ImpactBody contacts snapshot world point/normal, incoming direction
  and severity, including direction from confirmed pre-clamp sweep hints. The
  existing spawner fans its four shards away from the impact point and off the
  struck surface while retaining glancing motion and inherited post-contact motion.
- ImpactMaterial adds `fragment_scatter_speed`, `fragment_scatter_spin`, and
  `fragment_bounce`. Glass defaults are 2.8 m/s, 5 rad/s, 0.16; ceramic 2.1, 4,
  0.10; other resources default to 1.8, 3.5, 0.10. Only existing brittle materials
  fragment. Scatter/spin scale with sqrt(severity/threshold), at most 2×; a 6%
  energy budget also limits the scatter velocity component. Launch caps stay
  6 m/s and 7 rad/s. One impulse pair runs in the first debris physics callback
  after mass/inertia initialization. Native spawn-time inverse mass is stale.
- Debris remembers one imminent sweep collider/speed for at most three ticks.
  A matching actual contact restores modest material restitution (outward speed
  capped at 0.9 m/s), since the safety sweep removes incoming solver speed. Pickup
  clears the hint. Placement, CCD, sweep geometry, four-body budget, supported
  damping and normal sleep remain; no new manager, effects or static conversions.
- `tests/physics_feel_smoke.gd` compares old/new tuning on bottle/monitor/chair,
  rapid aim, thin-wall contact, head-on/glancing fractures, bounce/sleep and menu
  pause/resume/restarts. 72 checks pass at each 30/60/120/180 render clock and in
  the rendered 30-clock smoke. Bottle/monitor 90% response improves 517 → 317 ms;
  chair 533 → 350 ms, without measured step overshoot. Six focused existing suites
  pass 422 checks; menu and prop-smoothing guards pass another 48/37 checks.
  The pre-existing rendered restart registration diagnostic recorded here was
  subsequently fixed in #9A.7 above. See README for tuning and manual playtesting.

## Current tuning: movement and charged throws

- Standing speed is 5.4 m/s (+20%); crouch stays 2.475 m/s and prone 1.125 m/s.
  Acceleration/deceleration and jump settings are unchanged. No sprint.
- Hold LMB while holding a prop to charge; release to throw. Tap is a gentle
  toss, 0.4 s moderate, 0.8 s strong, and 1.0 s maximum (clamped). At 2 kg,
  launch speed additions are 4/10/16/19 m/s respectively. Only the charge duration
  changed in Prompt #7; maximum strength, mass/momentum response and caps remain.
- Mass response is `(2 / mass)^0.25`, clamped to 0.65-1.2. Throwing adds 50%
  of player velocity (capped at 3 m/s), retains up to 4 m/s of prop motion,
  and caps total launch speed at 26 m/s. Drop still preserves momentum.
- Throws add camera-relative tumble with an orientation contribution, a small
  random variation, and mass/size scaling. Existing spin contributes; the result
  is capped at 7 rad/s. Damping is restored, and physics owns flight/contacts.
- A thin ring around the crosshair shows charge, with a subtle pulse at maximum.
  It clears on release/cancel; exact percentages remain in debug-build F3 stats.
  RMB drops without throwing, including during charge or a queued LMB release.
  Drop, Escape, focus loss, forced release, deletion and restart clear it; cursor recapture cannot
  charge. Changing stance continues charging while the hold remains safe.

## Physical kick (Prompt #8)

- RMB with empty hands kicks; while holding it retains drop/charge cancellation.
  One press requests one physics-tick action, with a 0.45 s cooldown including
  misses. Focus/cursor release cancels pending kicks. Debug-build F3 shows the
  current eligible kick target, hit distance and maximum range at the existing 5 Hz.
- The camera ray chooses the first World/Props surface. The nominal 1.35 m
  lower-body bound (origin 0.6 m above feet, lower in low stances) and leg ray
  remain broad gates. Milestone #9A.1 additionally checks distance from an ankle
  origin 0.12 m above feet, contact height [-0.10 m, 65% of actual capsule height],
  a forward cone (dot >= 0.5), exclusion of underfoot contacts and a 0.06 m radius
  swept foot volume against World/Props. Tiny floor contacts raise the sweep end
  just enough for sole clearance. A nearby floor monitor below a bed platform
  fails even when inside the nominal range; same-level platform kicks remain valid.
  F3 and impulse application share this exact eligibility query, with foot distance
  and relative contact height shown for valid targets. No leg animation is added.
- Apply an impulse at the actual hit point, forward with a slight upward component
  (0.18 before normalization). Magnitude is `min(10 N·s, mass * 10 m/s)`:
  light bodies gain at most 10 m/s, 2 kg gains 5 m/s, 5 kg gains 2 m/s,
  12 kg gains 0.83 m/s, and 100 kg gains 0.1 m/s before contact response.
  Off-center hits generate solver-driven rotation; heavy dynamic bodies remain movable.
- Kicks wake supported props, reset rest tracking and restore debris flight damping.
  The existing motion sweep protects kicked props. Subsequent physical collisions
  use the unchanged ImpactBody/material thresholds; kicks add no separate damage
  event or damage model. Ceramic/glass can shatter on kicked wall/floor impacts.
- All movement, pushing, manipulation, throws, settling, search and physics tuning
  remain unchanged. `tests/kick_smoke.gd` covers input precedence, range/occlusion,
  mass, torque, cooldown, waking, room furniture, real fractures and debris kicks.

## Physical search behaviors (Prompt #4)

- Start with FIND YOUR KEYS. One physical keys target spawns at a randomly
  selected authored SearchSpot. Looking at it does not count: pickup completes
  the run, freezes the time, and displays FOUND YOUR KEYS.
- Enter after completion rebuilds the entire room, resets the player/timer,
  and chooses a different spot. The previous spot is excluded when alternatives
  exist; a single valid spot may repeat. No persistence or global singleton.
- Seventeen authored spots: 3 SURFACE, 4 OCCLUDED, 4 LOW_UNDER, 3 BEHIND,
  and 3 HIGH. Category-first selection avoids the last two categories and last
  three spots where possible, with graceful fallback for small candidate pools.
  Each has enabled/category metadata and one primary intended action:
  VISUAL_SEARCH (6), CROUCH (1), PRONE (3), MOVE_PROP (4), CLIMB (3).
  Actions describe authored intent, not requirements enforced on the player.
  Initial overlap checks reject blocked placements. A single bounded pass also
  rejects fully exposed placements using the initial camera frustum and rays to
  collider centers/inset corners, blocked by World or Props. Selection/history
  applies only to survivors; an all-exposed pool uses the unavailable state.
  No available spots yields an explicit unavailable state with Enter to retry.
- Time is monotonic wall-clock time, including cursor release/focus loss.
  The sandbox continues running after completion; only the run timer stops.
- F4 explicitly shows search diagnostics (state/target/spot/category/action and
  spawn rejected/checked counts), hidden by default
  and gated to debug builds. F7 rerolls only while those diagnostics are shown.
  Enter is restart; R remains exclusively held-object rotation.
- Ctrl is hold-to-crouch; Z toggles prone. Camera and capsule ease between actual
  heights of 1.8/1.0/0.5 m. Rising checks full
  capsule clearance. Feet stay fixed; prone cannot jump. F3 also reports stance.
- The room includes a bed, couch, desk/hutch, bedside table, shelving, wardrobe,
  movable covers, boxes and two stools. Low spots use crouch/prone viewpoints;
  covered spots require moving props. High routes use ordinary jumps onto broad
  movable supports, including box-to-desktop access to the hutch. No mantling.
- The three easy surface spots use existing bedside clutter, the desk cover and
  an upright loose book for occlusion; walking/changing angle reveals them.
  UnderBedDeep and BehindHeadboard avoid diagonal sightlines from spawn, including
  after settling. All seventeen placements remain eligible and retrievable.
- Player take-off does not inherit small platform contact velocities, avoiding
  jitter-induced launches when jumping from movable supports.

## Preserved physics prototype

- Typed GDScript, Godot 4.x (4.3+ APIs), Windows/desktop first.
- Compatibility renderer, Godot Physics, 60 Hz physics. Validated with the locally
  installed Godot 4.7.2; see README for commands. Angular sleep threshold is
  0.25 rad/s so small resting props can sleep despite minor contact jitter.
- Original enclosed graybox room, table, impact block, and eight sleeping rigid props
  of different shapes and masses (0.25–12 kg).
- Accelerated first-person movement, jump, mouse look, center-ray pickup,
  force-based hold, drop, mass-sensitive throw, optional debug statistics.
- Hold R + move the mouse to rotate a held prop around camera-relative axes;
  mouse look resumes on R release. Wheel up/down moves it farther/closer.
  Each pickup starts at 2 m; distance is bounded to 1.1-3 m, with a larger
  minimum for large props. Debug statistics include the selected distance.
- Held bodies stay dynamic. Capped spring forces, angular damping, continuous
  collision detection, obstruction release, and delayed player-collision
  restoration limit instability. No transform-following or frozen held props.
- A capped, inertia-aware torque controller maintains the chosen orientation
  while held. Limited angular lag avoids building up rotation against furniture.
  Drop preserves momentum; release restores the body's original damping.
- Prop bounds and their geometry center are cached at pickup for conservative
  clearance. The monitor's floor-level scene pivot is not its hold point.
  Floor/support clearance uses oriented shape bounds and raises the hold target
  off the support; actual shape queries test player clearance and the pull path.
  This permits downward pickups of flat/irregular props and small fragments.
  Existing conservative wall/ceiling release remains in place.
  Walls may shorten the actual distance; insufficient space, actual player
  overlap or a pull path crossing the capsule releases the hold. Underfoot and
  overlapping dropped props cannot be picked up until clear. Player collisions
  are restored only after separation; bodies remain dynamic throughout.
- Native CCD remains enabled. A shared full-body motion sweep supplements it for
  thrown props and all moving ImpactBodies (including dropped/dead monitors)
  above 2 m/s, because native support-point rays can miss thin furniture.
  Only an imminent collision reduces travel to a 1 cm contact overlap;
  the physics engine and 60 Hz rate are unchanged. The charged throw uses the
  same protection, validated up to its 26 m/s launch cap with tumbling.
  The first sweep reads the physics server's updated launch velocity.
  Slow bodies skip the sweep but remain tracked until sleeping (a falling prop can
  accelerate again); re-pickup and deletion also remove them. Ordinary props need no scripts.
- Camera release/focus loss drops the held object. Physics continues running.
- A shared `PropRest` helper watches awake grabbable bodies with bounded support
  contact data. One second of supported, low-speed motion inside a small pose
  envelope permits dynamic sleep despite alternating solver contact corrections.
  Sleep is confirmed across three frames so a contacting neighbour cannot
  repeatedly reset the rest history. Held/player-contacting bodies, substantial
  impacts, moving supports and constant forces are excluded. Release resets
  tracking and wakes the body; impulses/collisions retain normal engine wake-up.
  Global damping, solver settings, sleep thresholds and 60 Hz remain unchanged.
- Walking side contacts push each dynamic prop once per tick using movement
  intent, a shared 100 N force budget and a mass-dependent speed limit. Impulses
  are horizontal/central; supports underfoot are excluded. Sustained opposed
  contacts can trigger a short collision-tested back-out. No movement-speed,
  jump, stance, physics-rate or global solver tuning changed for this fix.

## Impact and materials prototype (Prompt #7)

- Six opt-in ImpactBody examples coexist with the search room: ceramic vase
  (0.6 kg), glass bottle (0.45 kg), plastic block (0.18 kg), metal weight (8 kg),
  wood block (1.5 kg), and monitor (5 kg). Small loose props are near the entrance;
  the monitor sits on the desk. Existing search furniture/supports and keys retain
  their original behavior. All seventeen SearchSpots remain available.
- ImpactMaterial resources describe CERAMIC, GLASS, WOOD, PLASTIC, METAL and
  ELECTRONIC, brittle/staged response, thresholds and a 1 m/s closing-speed floor.
  Materials and current damage state are queryable on the body; no global manager.
- ImpactBody reads at most eight normal physics contacts in `_integrate_forces`.
  Closing speed is `max(0, -(v_self_at_contact - v_other_at_contact).dot(normal))`.
  Severity is `0.5 * effective_mass * closing_speed^2`; effective mass is
  `m1*m2/(m1+m2)` for dynamic bodies, or the receiver's mass against immovable
  bodies. This is a translational energy approximation, not a fracture simulation.
- Process the strongest new contact once, not every manifold point or resting
  frame. No accumulated weak-contact damage. State changes have a 0.3 s cooldown.
  The existing throw sweep records pre-clamp severity for both opted-in receivers;
  it is consumed only on a real contact with the same collider within three ticks.
  The old 1 mm overlap sometimes clipped a tumbling throw to a crawl before
  contact reporting, allowing its estimate to expire. The 1 cm overlap fixes
  that handoff; no distance/release-time multiplier or threshold reduction.
  Angular contact velocity uses the physical center of mass, not the scene pivot.
  Near misses/expired predictions still do no damage.
- Ceramic/glass break at severity 14/10 respectively. Each creates up to four
  angular wall shards from four fixed authored silhouettes, without mesh cutting.
  Each chunk receives one quarter of the mass and post-contact linear/spin motion,
  capped at 6 m/s and 7 rad/s. Ceramic pieces are thick, ceramic-colored chunks;
  glass pieces are thinner translucent shards. Convex colliders include a 1 cm
  skin; bounded overlap/separation queries place pieces clear of furniture and
  siblings before insertion. Axial/diagonal candidates stay within 30 cm; an
  unplaceable piece is omitted in fully confined spaces. Debris uses CCD,
  small-body sweeps, four-times-box inertia and supported residual damping to
  reach sleep without freezing. The shared supported-rest check also applies.
  Picking up debris clears
  settling damping before the grabber caches it. No damage receiver or recursive fragmentation. Pieces are
  grabbable; they collide with world/props but not the player. Two brittle props
  mean at most eight debris bodies per room, cleared by normal room restart.
- Staged damage thresholds (crack / break): wood 120/240, plastic 130/260,
  metal 550/900, electronics 70/100. Each qualifying collision advances at most
  one state: INTACT -> CRACKED -> BROKEN. The monitor shows lit, visibly cracked,
  then dark screens. The cracked display has a branched impact pattern. Durable
  props darken at their authored damage states. Primitive silhouettes distinguish
  the necked vase/bottle, studded plastic toy brick, grained timber and handled
  iron weight marked 8 kg. No final art or containment behavior.
  The monitor's single convex collider, unchanged across damage states, encloses its
  screen/crack geometry; its old screen collider was shallower than the visuals.
  Broken staged props remain movable single bodies; four support contacts remain
  available for settling, while damage processing stops.
- F3 adds held material, state, last meaningful severity, thresholds, closing
  speed, effective mass and contact/confirmed-sweep source in debug
  builds. Normal HUD has no damage numbers. No tools, procedural fracture,
  electricity, audio, economy, or progression were added.

## Structure and conventions

- Milestone #9A.4 adds `scripts/player_view_camera.gd` and `Player/VisualCamera3D`:
  an independent active Camera3D with render-frame position interpolation only.
  The original camera remains the authoritative gameplay orientation/range reference. Player
  hooks capture eye position after movement/stance physics and copy mouse rotation
  immediately; no movement, interaction or physics tuning changes. Global engine
  interpolation stays disabled. Settings copy projection/FOV to the view.
  Scene entry/restarts, direct small/large teleports and pause/resume clear history.
  Pause preserves the displayed pose; resume transitions for at most one tick.
  A presentation-only near-plane sphere sweep clips unsafe eye paths. The HUD
  now stays at screen centre; pickup/kick sight rays use the displayed eye with
  original-camera physical distance/visibility gates (see crosshair fix above).
  Camera position has up to one tick of visual latency; moving rigid props now
  use the separate mesh-only presentation helper. No global interpolation.
- #9A.5 confirms the camera is independent of render FPS and display refresh:
  engine interpolation fraction supplies position, while elapsed seconds supply
  the resume transition. Gameplay has no imposed FPS limit or display assumptions.
- `tests/camera_smoothness_smoke.gd`: elapsed-time scenarios across render rates,
  proximity aiming/interactions, clearance, teleport and menu reset checks.
  Tests/logs use isolated APPDATA and ignored `.validation/` output. A forced
  render clock establishes transform cadence, not physical display pacing.
  `tests/run_camera_frame_rates.ps1` runs 30/60/75/120/144/180 FPS with unchanged
  60-Hz physics. Optional real-time caps exercise the uncoupled engine clock.
  Test motion, waits and expected travel derive from seconds/render delta rather
  than display-specific frame counts. Low FPS processes multiple physics ticks;
  high FPS interpolates between them, retaining authoritative gameplay references.
  #9A.5 validation: 356 checks in each six-rate matrix (headless fixed clock,
  rendered fixed clock and real-time capped headless) pass, plus 58 checks in a
  live variable graphics loop around 32 FPS. Measured walking speed stays 5.4 m/s;
  the view advances on every moving frame, with matching immediate orientation.
  Runtime camera/controller/settings/physics scene files are unchanged in this pass.
  Real-time achieved rates match the 30–144 caps; the requested 180 cap reaches
  about 145 here. Fixed-clock 180 still passes. Requested/achieved FPS are reported
  separately; native graphics pacing is hardware-limited around 32 in this environment.
  #9A.4 validation: 50 headless + 46 fullscreen rendered camera checks and 483
  existing regression checks pass. Both walking modes advance on all 51 measured
  intervals (~0.03 m/frame) while the logical eye repeats 34/51; orientation matches
  immediately. Near aiming, bed/wall/furniture clearance and camera resets pass.
  The existing edited physics fixture is preserved; prior diagnostics remain.
- `scenes/main_menu.tscn`: F5 main scene for Milestone #9A.3. A small native
  Control menu shell launches the Gamer's Room under a pausable Gameplay node;
  the menu layer alone keeps processing while the SceneTree is paused. Main Menu
  has Play/Settings/Quit; Pause has Resume/Restart/Settings/Main Menu. Esc toggles
  pause and settings Back returns to its caller. Focus loss pauses. Room replacement
  is deferred and guarded against repeated activation; no global gameplay manager.
- `scripts/main_menu.gd` and `settings_menu.gd`: dark responsive native Controls,
  keyboard/mouse focus and shared settings view. Pause releases the cursor, drops
  the hold and clears queued input through `PhysicsGrabber.cancel_pending_input()`;
  gameplay callbacks/physics stop until Resume recaptures the cursor. Standalone
  F6 fixtures retain their original Escape/cursor behavior.
- `scripts/game_settings.gd`: the only settings autoload; ConfigFile persistence
  at `user://settings.cfg`. Immediate sensitivity (0.0005–0.01), vertical FOV
  (60–110°), Master volume (0–1, zero mutes) and fullscreen/windowed updates.
  Defaults preserve 0.0025 sensitivity and 75° FOV. The player's ready hook and
  settings signal apply both values without changing movement/interaction physics.
  No previous shared settings architecture existed; no save-game system is added.
- `tests/menu_smoke.gd`: real viewport keyboard/mouse routing, paused physics/input,
  charge/queued-action cancellation, repeated room rebuilds, settings application,
  fresh-process persistence and optional rendered screenshots/window-mode checks.
  #9A.3 validation: 48 headless + 50 rendered menu checks, 7 persistence checks
  and 417 existing gameplay checks passed. Editor import, default rendered launch
  and preserved physics-room launch passed; prior certificate/search shutdown
  diagnostics remain. Settings probes use isolated APPDATA; no physics tuning changes.
- `scenes/gamers_room.tscn`: Milestone #9A standalone layout sandbox, launched
  with F5 → Main Menu → Play, F6 or an explicit scene path.
  Clear interior is 4.5 × 4.5 m (20.25 m²), ceiling 2.7 m. South entrance landing,
  west bed, north window/PC desk, perimeter storage and central circulation.
  Door/window are fixed placeholders; no new search spots or run controller.
  #9A.1 shifts only the desk setup 0.15 m east to widen the bedside pinch point
  from 0.565 to 0.715 m for the 0.60 m player capsule. See README's scale audit.
- `scenes/furniture/*.tscn`: reusable floor-origin, unit-scale furniture
  placeholders (PC desk, chair, bed, wardrobe, dresser, shelves, bedside table).
  Primitive meshes and compound box colliders; temporary shared render palette
  in `resources/layout/`. Bed underside is 0.52 m for prone access between legs.
  #9A.2 makes chair (8 kg, COM 0/0.43/0.035 m) and bedside cabinet (12 kg, COM
  0/0.25/0 m) ordinary grabbable RigidBody3D props with CCD and four contacts;
  shared pushing, kicking, holding and PropRest apply. Larger furniture stays static.
  Support faces have a 1 cm upward collision skin against the default contact
  penetration allowance; their undersides and visible dimensions are unchanged.
  Dynamic furniture soles extend 1 cm below the visible feet. No new damage states.
- `scenes/props/moving_box.tscn` and `gamer_monitor.tscn`: inherited ordinary
  physics box and desktop-sized existing impact monitor. Resize meshes/shapes,
  retain unit-scale physics roots and original interaction/impact behavior.
  Existing glass/plastic/wood props are reused. Only chair and bedside furniture
  become dynamic in #9A.2; the other furniture stays fixed.
- Both monitor sizes use one convex hull around their original collision boxes.
  Separate screen/base contact manifolds caused persistent 3.5–4.4 mm/tick floor
  rocking in an exact spinning face-down fall; it lasted beyond 30 s without
  PropRest. The hull retains outer dimensions but fills stand gaps. Automatic
  COM/inertia use the centred hull; COM y is 0.305/0.525 m (desktop/large).
  Mass, friction, damping, solver settings, margins and interactions are unchanged.
  `tests/monitor_settling_smoke.gd` passes 130 focused checks: 38 falls without
  PropRest, native sleep within 3.22 s, no resting drift, and four pickup/throw
  recoveries. No new freezing, sleep forcing or shared rest changes.
- `tests/gamers_room_smoke.gd`: 46 focused actual-room checks for spawn, scale,
  settled overlaps, walking routes, crouch/prone, bed clearance, pickup/throw,
  kicks and inherited monitor impacts. #9A.1 also extends `kick_smoke.gd` with
  elevated/low/side-obstructed reach and real bed/monitor regressions.
  #9A.1 validation: 87 kick + 46 room/scale + 35 physics checks passed. Editor
  import, rendered room/F3 views and both standalone room launches completed.
  Rendered entrance/desk/storage inspection and direct scene launch passed.
  No movement, grabber, search or physics tuning changed.
- `tests/furniture_surface_smoke.gd`: #9A.2 regression for accepted contact slop
  on authored furniture faces, actual bottle hold/release, loaded moving supports,
  pushing/kicking and real thrown ImpactBody contacts. 84 checks pass alongside
  46 room and 87 kick checks. Thirteen placements leave visible gaps within
  -0.59/+0.88 mm, with sleeping loaded pairs and under 2 mm subsequent drift.
  Only furniture scene data changes; bottle geometry, controllers, kick tuning,
  search scenes and global physics settings stay unchanged.
- `scenes/search_game.tscn`: preserved standalone F6 search scene; local SearchRun controller and minimal HUD.
- `scripts/search_run.gd`: run state, selection, target identity, timer, and reset.
  It listens to the grabber's generic `object_picked_up` signal; no target logic
  lives in the player or grabber.
- `scenes/search_room.tscn`: expanded furniture playground, movable covers/supports
  and seventeen SearchSpot markers. SearchRoom exposes grabber/spot-root references.
- `scripts/search_spot.gd`: lightweight authored marker with spatial category,
  intended action, placement and spawn-exposure checks, queried only at run start.
- `scenes/props/keys.tscn`, `scripts/target_item.gd`: physical TargetItem identity
  and simple keys geometry. Only keys are implemented.
- `scripts/search_hud.gd`: objective, timer, result, opt-in search diagnostics.
- `scenes/test_room.tscn`: preserved standalone physics test room.
- `scenes/player.tscn`, `scripts/player_controller.gd`: movement, stance and mouse capture.
- `scripts/physics_grabber.gd`: interaction; exported references and tuning.
  As a child of Player, it consumes rotation mouse events before camera look.
  #9A.6 tunes only linear spring strength/damping; held rotation remains unchanged.
  Charge is local to the grabber.
- `scenes/props/physics_prop.tscn`: reusable ordinary RigidBody3D with primitive
  mesh/collider, grabbable group, CCD, and sleeping enabled. No prop script.
- `scenes/debug_overlay.tscn`, `scripts/debug_overlay.gd`: crosshair, controls,
  optional FPS/held-body/distance/stance/charge statistics refreshed at 5 Hz.
- `scripts/throw_charge_indicator.gd`: replaceable frame-updated radial HUD view
  of grabber charge, independent of F3 statistics (off by default in search).
- `scripts/impact_material.gd`, `resources/materials/*.tres`: gameplay material
  kinds, response and tunable thresholds, independent of rendering materials.
- `scripts/impact_body.gd`: opt-in physics contact receiver and authored damage
  states; `scripts/impact_fragments.gd`: bounded, fixed-pattern debris creation.
- `scripts/impact_debris.gd`: small-shard collision protection and supported
  settling, suspended while held; at most four contact reports per awake piece.
- `scripts/prop_rest.gd`: shared supported-rest eligibility, confirmed dynamic
  sleep and event-based registration/removal, owned by the room's grabber.
- `scripts/prop_visual_interpolation.gd`: shared mesh-only position/rotation
  interpolation for grabbable bodies at the engine render fraction. No body,
  collider, interaction or camera transform writes; global interpolation stays
  disabled and physics stays 60 Hz. Final placements reset history; physics-tick
  teleports must call `reset(body)`. Spawn/restart/deletion and pause/resume are
  handled, and brittle replacement meshes inherit the source's displayed offset.
  Static World compound-shape clearance permits endpoint solver slop but rejects
  added penetration. Its current-pose fallback can expose a contact step. Dynamic
  contacts retain native solver tolerances and visuals lag at most one tick.
  `tests/prop_smoothing_smoke.gd` / `tests/run_prop_frame_rates.ps1` cover
  30/60/120/180 clocks, real interaction paths, sleep, fragments and pixel readback.
- `scripts/prop_motion_sweep.gd`: shared fast-body protection and impact handoff.
- `scenes/props/{ceramic,glass,wood,plastic,metal}_prop.tscn`, `monitor.tscn`:
  six reusable primitive examples. `tests/impact_smoke.gd` covers real contacts,
  sweep confirmation, state changes, debris, held-object loss and search reset.
- `tests/stabilization_smoke.gd`: distance/pivot invariance, delayed sweep contact,
  floor/wall/tabletop clearance, monitor recovery in every damage state and
  wall/overlap/underfoot grab safety. Includes real 26 m/s tumbling fixtures.
- `tests/contact_settling_smoke.gd`: walking mass response, narrowing-gap passage
  and reversal, six monitor resting/recovery orientations, contacting ordinary
  props, eight ceramic/glass furniture impacts and standing/crouched debris recovery.
- Collision layers: 1 World, 2 Player, 3 Props. Picking checks World + Props so
  walls block interaction. Eligible props belong to `grabbable`.
- Use unit-scale physics roots; resize shapes/meshes. Keep generated `.gd.uid`
  files in Git, exclude `.godot/` and local build/validation output.

## Performance philosophy

Idle props may sleep; only the held body receives continuous forces. Fast thrown
props and moving ImpactBodies receive full-body sweeps until they slow down. Avoid
per-prop frame callbacks, contact monitoring, and unnecessary scene scans.
Use inexpensive primitive/convex compound colliders. Grabbable props request four
support contacts (intact impact receivers use eight). One shared helper checks
only awake props, removes confirmed sleepers, and uses signals for wake/deletion.
No per-prop frame scripts or repeated room scans are needed. Supported rest is
validated on fallen monitors and contacting props without adding damping.
Breakup has a fixed four-body budget per brittle prop. Benchmark representative physics
loads on Ryzen 7 5700X / Radeon RX 5700 XT before increasing budgets. This small
prototype is not a destruction-performance benchmark.

## Future systems — NOT IMPLEMENTED

Additional search targets/rooms, containers, hints, dedicated inspection UI, audio,
procedural fracture, further material interactions, tools, fire, liquids, electricity, inventory,
economy/rewards, challenges, unlocks/progression, procedural rooms, game-state saving,
mission selection, shop, cosmetics, easter eggs, and polished art.
Only main/pause menus and user settings persistence are included in #9A.3.
