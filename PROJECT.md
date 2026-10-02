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
  The monitor's unchanged compound collider across states now encloses its
  screen/crack geometry; its old screen collider was shallower than the visuals.
  Broken staged props remain movable single bodies; four support contacts remain
  available for settling, while damage processing stops.
- F3 adds held material, state, last meaningful severity, thresholds, closing
  speed, effective mass and contact/confirmed-sweep source in debug
  builds. Normal HUD has no damage numbers. No tools, procedural fracture,
  electricity, audio, economy, or progression were added.

## Structure and conventions

- `scenes/search_game.tscn`: main scene; local SearchRun controller and minimal HUD.
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
  Linear spring/held-rotation tuning remains unchanged; charge is local to the grabber.
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

Additional targets/rooms, containers, hints, dedicated inspection UI, audio,
procedural fracture, further material interactions, tools, fire, liquids, electricity, inventory,
economy/rewards, challenges, unlocks/progression, procedural rooms, saving,
menus, easter eggs, and polished art. No work on these is part of this milestone.
