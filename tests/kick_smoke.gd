extends SceneTree

var _world: Node3D
var _player: SandboxPlayer
var _grabber: PhysicsGrabber
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_mass_and_rotation()
	await _test_targeting()
	await _test_stance_reach()
	await _test_bed_reach()
	await _test_input()
	await _test_furniture()
	for material: String in ["ceramic", "glass", "metal"]:
		await _test_impacts(material)
	await _test_furniture_impacts("ceramic")
	print("KICK SMOKE: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _setup() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(0, -0.2, 0), Vector3(20, 0.4, 20))
	_player = load("res://scenes/player.tscn").instantiate() as SandboxPlayer
	_world.add_child(_player)
	_grabber = _player.get_node("Grabber") as PhysicsGrabber
	await _steps(5)


func _cleanup() -> void:
	_world.queue_free()
	await _steps(3)


func _box(position: Vector3, size: Vector3, mass: float = 0.0) -> PhysicsBody3D:
	var body: PhysicsBody3D = RigidBody3D.new() if mass > 0 else StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	body.position = position
	body.collision_layer = 4 if mass > 0 else 1
	body.collision_mask = 7
	if body is RigidBody3D:
		body.mass = mass
		body.gravity_scale = 0.0
		body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		body.linear_damp = 0.0
		body.continuous_cd = true
		body.add_to_group("grabbable")
	_world.add_child(body)
	return body


func _test_mass_and_rotation() -> void:
	var speeds: Array[float] = []
	for mass: float in [0.15, 2.0, 5.0, 12.0, 100.0]:
		await _setup()
		var body := _box(Vector3(0, 0.7, -1), Vector3.ONE * 0.4, mass) as RigidBody3D
		await _steps(3)
		body.sleeping = true
		_player.camera.look_at(body.global_position + Vector3(0.12, 0.1, 0))
		var target := _grabber.get_kick_target()
		_check(target.get("collider") == body and target.get("distance", INF) <= _grabber.kick_reach
			and body.sleeping, "Kick diagnostics select reachable body without waking it: %.2f kg" % mass)
		_rmb()
		await _steps(2)
		var speed := body.linear_velocity.length()
		speeds.append(speed)
		_check(not body.sleeping and speed > 0.01, "Empty RMB wakes/kicks %.2f kg" % mass)
		_check(absf(speed - minf(10.0, 10.0 / mass)) < 0.1, "Bounded impulse gives mass-aware speed at %.2f kg" % mass)
		_check(body.angular_velocity.length() > 0.01, "Off-center kick generates physical spin at %.2f kg" % mass)
		await _cleanup()
	_check(speeds[0] > speeds[1] and speeds[1] > speeds[2] and speeds[2] > speeds[3]
		and speeds[3] > speeds[4], "Light, box, monitor, heavy and furniture masses respond progressively")
	_check(speeds[3] < 0.9 and speeds[4] < 0.11, "Heavy props resist without becoming immovable or launching")


func _test_targeting() -> void:
	for mode: String in ["far", "wall", "low_obstacle", "toe_obstacle", "toe_side_obstacle", "high_contact", "front_prop", "frozen"]:
		await _setup()
		var body := _box(Vector3(0, 0.7, -1), Vector3.ONE * 0.3, 2.0) as RigidBody3D
		var front: RigidBody3D
		match mode:
			"far": body.position.z = -2.0
			"wall": _box(Vector3(0, 1, -0.6), Vector3(2, 2, 0.06))
			"low_obstacle": _box(Vector3(0, 0.4, -0.6), Vector3(2, 0.8, 0.06))
			"toe_obstacle": _box(Vector3(0, 0.24, -0.4), Vector3(0.2, 0.48, 0.05))
			"toe_side_obstacle": _box(Vector3(0.10, 0.24, -0.4), Vector3(0.12, 0.48, 0.05))
			"high_contact": body.position = Vector3(0, 1.5, -0.4)
			"front_prop": front = _box(Vector3(0, 1.05, -0.65), Vector3.ONE * 0.3, 2.0) as RigidBody3D
			"frozen": body.freeze = true
		await _steps(3)
		_player.camera.look_at(body.global_position)
		var target := _grabber.get_kick_target()
		_check(target.get("collider") == front if front != null else target.is_empty(),
			"Kick diagnostics respect " + mode)
		_rmb()
		await _steps(2)
		_check(body.linear_velocity.length() < 0.01, "Kick cannot bypass " + mode)
		if front != null:
			_check(front.linear_velocity.length() > 1, "Only the first visible prop receives the kick")
		await _cleanup()


func _test_stance_reach() -> void:
	for stance: int in SandboxPlayer.Stance.values():
		await _setup()
		var body := _box(Vector3(0, 0.12, -0.85), Vector3.ONE * 0.18, 2.0) as RigidBody3D
		if stance == SandboxPlayer.Stance.CROUCHING:
			Input.action_press("crouch")
		elif stance == SandboxPlayer.Stance.PRONE:
			_player._prone_requested = true
		await _steps(25)
		_player.camera.look_at(body.global_position)
		_check(_player.stance == stance and _grabber.get_kick_target().get("collider") == body,
			"Floor prop remains reachable in %s" % SandboxPlayer.Stance.keys()[stance])
		_rmb()
		await _steps(2)
		_check(body.linear_velocity.length() > 1.0, "Normal floor kick applies impulse in stance %d" % stance)
		Input.action_release("crouch")
		await _cleanup()


func _test_bed_reach() -> void:
	var room: Node3D = load("res://scenes/gamers_room.tscn").instantiate()
	root.add_child(room)
	_player = room.get_node("Player") as SandboxPlayer
	_grabber = _player.get_node("Grabber") as PhysicsGrabber
	var monitor := room.get_node("MovableProps/Monitor") as ImpactBody
	monitor.position = Vector3(-0.42, 0.09, -0.65)
	monitor.rotation = Vector3(PI * 0.5, 0, 0)
	_player.position = Vector3(-0.85, 0.82, -0.22)
	await _steps(180)
	_player.camera.look_at(monitor.global_position + Vector3(0, 0.055, 0.43))
	_check(_player.is_on_floor() and _player.position.y > 0.75,
		"Regression player really stands on Gamer's Room bed")
	# Reconstruct the former broad distance gate: this fixture must be close
	# enough and visible, otherwise a range miss could conceal the regression.
	var origin := _player.global_position + Vector3.UP * 0.6
	var query := PhysicsRayQueryParameters3D.create(_player.camera.global_position,
		_player.camera.global_position - _player.camera.global_basis.z *
		(_grabber.kick_reach + origin.distance_to(_player.camera.global_position)), 5)
	query.exclude = [_player.get_rid()]
	var visible := room.get_world_3d().direct_space_state.intersect_ray(query)
	print("BED REACH: feet=%s monitor=%s hit=%s distance=%.3f" % [
		_player.global_position, monitor.global_position, visible.get("position"),
		origin.distance_to(visible.get("position", Vector3.INF))])
	_check(visible.get("collider") == monitor and origin.distance_to(visible.get("position", Vector3.INF)) < 1.35,
		"Bed-to-floor monitor is visible and inside the old nominal range")
	_check(_grabber.get_kick_target().is_empty(), "Feet on bed cannot reach the floor monitor")
	var overlay := room.get_node("DebugOverlay")
	overlay._update_stats()
	_check(overlay.get_node("Stats").text.contains("Kick target: none"),
		"F3 rejects the same bed-to-floor target as the kick")
	var before := monitor.global_position
	_rmb()
	await _steps(3)
	_check(monitor.global_position.distance_to(before) < 0.01 and _grabber._kick_remaining > 0,
		"Rejected bed kick adds no impulse and still consumes cooldown")
	_player.position = Vector3(0.3, 0.02, -0.22)
	_player.velocity = Vector3.ZERO
	await _steps(30)
	_player.camera.look_at(monitor.global_position + Vector3(0, 0.055, 0.43))
	_check(_grabber.get_kick_target().get("collider") == monitor,
		"The same floor monitor becomes reachable from the floor")
	overlay._update_stats()
	_check(overlay.get_node("Stats").text.contains("Kick target: Monitor ("),
		"F3 selects the monitor after stepping off the bed")
	before = monitor.global_position
	_rmb()
	await _steps(3)
	_check(monitor.global_position.distance_to(before) > 0.02,
		"Floor-level kick physically moves the same monitor")
	var bed_box := load("res://scenes/props/moving_box.tscn").instantiate() as RigidBody3D
	room.add_child(bed_box)
	bed_box.position = Vector3(-1.45, 1.0, -0.25)
	_player.position = Vector3(-1.45, 0.82, -1.3)
	_player.velocity = Vector3.ZERO
	await _steps(60)
	_player.camera.look_at(bed_box.global_position)
	_check(_grabber.get_kick_target().get("collider") == bed_box,
		"Standing on furniture still permits a reachable same-level kick")
	before = bed_box.global_position
	_rmb()
	await _steps(3)
	_check(bed_box.global_position.distance_to(before) > 0.03,
		"Same-level bed kick retains the normal physical impulse")
	room.queue_free()
	await _steps(3)


func _test_input() -> void:
	await _setup()
	var body := _box(Vector3(0, 0.7, -1), Vector3.ONE * 0.4, 100.0) as RigidBody3D
	await _steps(3)
	_player.camera.look_at(body.global_position)
	var overlay: CanvasLayer = load("res://scenes/debug_overlay.tscn").instantiate()
	overlay.grabber = _grabber
	overlay.debug_visible = false
	_world.add_child(overlay)
	_check(not overlay.get_node("Stats").visible, "Kick diagnostics remain behind F3")
	var toggle := InputEventAction.new()
	toggle.action = "toggle_debug"
	toggle.pressed = true
	root.push_input(toggle)
	var stats := overlay.get_node("Stats") as Label
	_check(stats.visible and stats.text.contains("Kick target: %s (" % body.name)
		and stats.text.contains("Kick range: 1.35 m"), "F3 shows current kick target and reach")
	_player.camera.rotation = Vector3.ZERO
	overlay._update_stats()
	_check(stats.text.contains("Kick target: none"), "F3 clears a stale kick target after aim changes")
	_player.camera.look_at(body.global_position)
	_rmb()
	await _steps(2)
	var first := body.linear_velocity.length()
	_rmb()
	await _steps(2)
	_check(absf(body.linear_velocity.length() - first) < 0.01, "Repeated RMB during cooldown adds no impulse")
	await _steps(30)
	_check(absf(body.linear_velocity.length() - first) < 0.01, "Kick does not automatically repeat")
	_player.camera.look_at(body.global_position)
	_rmb()
	await _steps(2)
	_check(body.linear_velocity.length() > first * 1.8, "A fresh press after cooldown kicks again")
	await _cleanup()
	for mode: String in ["drop", "queued_throw", "free_cursor", "focus_loss"]:
		await _setup()
		body = _box(Vector3(0, 0.9, -1), Vector3.ONE * 0.3, 2.0) as RigidBody3D
		await _steps(3)
		_player.camera.look_at(body.global_position)
		if mode in ["drop", "queued_throw"]:
			_grabber.try_pick_up()
			_check(_grabber.held_body == body, "Pickup fixture before " + mode)
			_check(_grabber.get_kick_target().is_empty(), "Holding leaves no eligible kick target: " + mode)
			if mode == "queued_throw":
				_grabber.is_charging_throw = true
				_grabber._charge_seconds = 0.8
				var event := InputEventMouseButton.new()
				event.button_index = MOUSE_BUTTON_LEFT
				root.push_input(event)
		elif mode == "free_cursor":
			_player.set_mouse_captured(false)
		_rmb()
		if mode == "focus_loss":
			_grabber._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await _steps(2)
		_check(_grabber.held_body == null and not _grabber.is_charging_throw
			and _grabber._kick_remaining == 0 and body.linear_velocity.length() < 0.01,
			"No kick/throw and clean input cancellation: " + mode)
		await _cleanup()


func _test_furniture() -> void:
	var room := load("res://scenes/search_room.tscn").instantiate() as SearchRoom
	root.add_child(room)
	_player = room.grabber.player
	_grabber = room.grabber
	_player.position = Vector3(-2, 0.02, 3.3)
	await _steps(240)
	var table := room.get_node("BedsideTable") as RigidBody3D
	var start := table.position
	_player.camera.look_at(table.global_position)
	_rmb()
	var travel := 0.0
	for frame in 60:
		await _steps(1)
		travel = maxf(travel, table.position.distance_to(start))
	_check(travel > 0.1, "Kick noticeably moves actual stool-like room furniture")
	room.queue_free()
	await _steps(3)


func _test_impacts(material: String) -> void:
	await _setup()
	var wall := _box(Vector3(0, 1.5, -1.8), Vector3(5, 3, 0.07))
	var body := load("res://scenes/props/" + material + "_prop.tscn").instantiate() as ImpactBody
	body.position = Vector3(0, 0.3, -0.95)
	_world.add_child(body)
	var fracture: Dictionary = {}
	body.damage_state_changed.connect(func(changed: ImpactBody) -> void:
		fracture["wall_contact"] = changed._touching.has(wall.get_rid()))
	await _steps(240)
	_check(is_instance_valid(body) and body.sleeping, "Impact fixture rests before kick: " + material)
	_player.camera.look_at(body.global_position)
	var start := body.position
	_rmb()
	await _steps(2)
	var initial_speed := body.linear_velocity.length()
	var initial_travel := body.position.distance_to(start)
	await _steps(120)
	if material == "metal":
		_check(is_instance_valid(body) and body.damage_state == ImpactBody.State.INTACT
			and initial_travel > 0.01 and initial_speed > 0.1 and initial_speed < 1.5,
			"Durable weight moves modestly but keeps its existing damage thresholds")
	else:
		var pieces := get_nodes_in_group("impact_debris")
		_check(not is_instance_valid(body) and pieces.size() == 4,
			"Kick causes real collision fracture through existing ImpactBody: " + material)
		_check(fracture.get("wall_contact", false), "Confirmed wall contact fractures kicked " + material)
		wall.queue_free() # Test subsequent shard kicks on unobstructed floor.
		await _steps(900)
		if not pieces.is_empty():
			var shard := pieces[0] as ImpactDebris
			# Approach the outermost shard diagonally from outside the pile:
			# a route through neighbouring debris is correctly blocked by the foot.
			for candidate: ImpactDebris in pieces:
				if candidate.position.x < shard.position.x:
					shard = candidate
			_check(shard.sleeping, "Spawned shard settles before kick: " + material)
			_player.position = Vector3(shard.position.x + 0.25, 0, shard.position.z + 0.8)
			await _steps(3)
			_player.camera.look_at(shard.global_position)
			_check(_grabber.get_kick_target().get("collider") == shard,
				"Shard approach has real foot clearance: " + material)
			var resting_position := shard.position
			_rmb()
			await _steps(2)
			_check(not shard.sleeping and shard.position.distance_to(resting_position) > 0.1 and not shard._settling,
				"Kick wakes physical debris with flight damping: " + material)
	await _cleanup()


func _test_furniture_impacts(material: String) -> void:
	await _setup()
	# Reuse the actual compound bedside table, including its dynamic mass/material.
	var room := load("res://scenes/search_room.tscn").instantiate() as SearchRoom
	root.add_child(room) # Let node-owned helpers initialize before cleanup.
	var table := room.get_node("BedsideTable") as RigidBody3D
	room.remove_child(table)
	room.queue_free()
	await _steps(3)
	table.position = Vector3(0, 0.385, -1.75)
	_world.add_child(table)
	_player.position.x = 0.3 # Aim squarely into the front table leg.
	var body := load("res://scenes/props/" + material + "_prop.tscn").instantiate() as ImpactBody
	body.position = Vector3(0.3, 0.3, -0.95)
	_world.add_child(body)
	var fracture: Dictionary = {}
	body.damage_state_changed.connect(func(changed: ImpactBody) -> void:
		fracture["table_contact"] = changed._touching.has(table.get_rid())
		fracture["effective_mass"] = changed.last_effective_mass
		fracture["source"] = changed.last_impact_source)
	await _steps(240)
	_player.camera.look_at(body.global_position - Vector3.UP * 0.15)
	_check(_grabber.get_kick_target().get("collider") == body,
		"Fragile prop is kickable in front of actual furniture: " + material)
	_rmb()
	await _steps(120)
	_check(not is_instance_valid(body) and get_nodes_in_group("impact_debris").size() == 4,
		"Kick fractures fragile prop against actual dynamic table: " + material)
	var prop_mass := 0.6 if material == "ceramic" else 0.45
	var expected_mass := prop_mass * table.mass / (prop_mass + table.mass)
	_check(fracture.get("table_contact", false)
		and absf(float(fracture.get("effective_mass", 0.0)) - expected_mass) < 0.001
		and fracture.get("source", "") in ["contact", "confirmed sweep"],
		"Real table contact and reduced mass drive the existing impact system: " + material)
	await _cleanup()


func _rmb() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		root.push_input(event)


func _steps(count: int) -> void:
	for index in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
