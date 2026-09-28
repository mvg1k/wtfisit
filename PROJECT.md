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

## Implemented milestone: physics playground and held-object manipulation

- Typed GDScript, Godot 4.x (4.3+ APIs), Windows/desktop first.
- Compatibility renderer, Godot Physics, 60 Hz physics. Validated with the locally
  installed Godot 4.7.2; see README for commands. Angular sleep threshold is
  0.25 rad/s so small resting props can sleep despite minor contact jitter.
- One enclosed graybox room, table, impact block, and eight sleeping rigid props
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
  Drop/throw preserve momentum and restore the body's original damping.
- Prop bounds are cached at pickup for conservative clearance. Walls may shorten
  the actual distance; insufficient space or a target inside the player causes
  release instead of pulling through the player.
- Camera release/focus loss drops the held object. Physics continues running.

## Structure and conventions

- `scenes/test_room.tscn`: editable room and prop instances; main scene.
- `scenes/player.tscn`, `scripts/player_controller.gd`: movement and mouse capture.
- `scripts/physics_grabber.gd`: interaction; exported references and tuning.
  As a child of Player, it consumes rotation mouse events before camera look.
  Movement and the existing linear spring/throw tuning remain unchanged.
- `scenes/props/physics_prop.tscn`: reusable ordinary RigidBody3D with primitive
  mesh/collider, grabbable group, CCD, and sleeping enabled. No prop script.
- `scenes/debug_overlay.tscn`, `scripts/debug_overlay.gd`: crosshair, controls,
  optional FPS/held-body/distance statistics refreshed at 5 Hz.
- Collision layers: 1 World, 2 Player, 3 Props. Picking checks World + Props so
  walls block interaction. Eligible props belong to `grabbable`.
- Use unit-scale physics roots; resize shapes/meshes. Keep generated `.gd.uid`
  files in Git, exclude `.godot/` and local build/validation output.

## Performance philosophy

Idle props may sleep; only the held body receives continuous forces. Avoid
per-prop frame callbacks, contact monitoring, and unnecessary scene scans.
Use inexpensive primitive/convex compound colliders. Future destruction must use
bounded debris and inexpensive state changes; benchmark representative physics
loads on Ryzen 7 5700X / Radeon RX 5700 XT before increasing budgets. This small
prototype is not a destruction-performance benchmark.

## Future systems — NOT IMPLEMENTED

Search targets/random hiding spots, containers, hints, dedicated inspection UI,
destruction/material responses, tools, fire, liquids, electricity, inventory,
economy/rewards, challenges, unlocks/progression, procedural rooms, saving,
menus, easter eggs, and polished art. No work on these is part of this milestone.
