extends SceneTree

var _world: Node3D
var _player: SandboxPlayer
var _grabber: PhysicsGrabber
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_distance()
	await _test_floor()
	await _test_surfaces()
	await _test_monitor_recovery()
	await _test_player_clearance()
	print("STABILIZATION SMOKE: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _setup() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_player = load("res://scenes/player.tscn").instantiate() as SandboxPlayer
	# Place before entering the tree so the fixture never collides at the origin.
	_player.position = Vector3(20, -20, 0)
	_world.add_child(_player)
	_player.set_physics_process(false)
	_grabber = _player.get_node("Grabber") as PhysicsGrabber
	await _steps(3)


func _cleanup() -> void:
	_world.queue_free()
	await _steps(3)


func _prop(kind: String, location: Vector3) -> ImpactBody:
	var path := "monitor" if kind == "monitor" else kind + "_prop"
	var body := load("res://scenes/props/" + path + ".tscn").instantiate() as ImpactBody
	body.position = location
	_world.add_child(body)
	return body


func _box(position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	_world.add_child(body)


func _hitter(distance: float, spin: Vector3 = Vector3.ZERO, pivot_offset: float = 0.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# Keep the original failing tumbling-weight geometry independent of artwork.
	shape.size = Vector3(0.4, 0.35, 0.35)
	collision.shape = shape
	collision.position.y = pivot_offset
	body.add_child(collision)
	body.position = Vector3(0, 0.7 - pivot_offset, distance)
	body.mass = 8
	body.gravity_scale = 0
	body.continuous_cd = true
	body.collision_layer = 4
	body.collision_mask = 5
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0
	body.angular_damp = 0.4
	_world.add_child(body)
	body.angular_velocity = spin
	return body


func _hit(monitor: ImpactBody, distance: float, spin: Vector3 = Vector3.ZERO, pivot_offset: float = 0.0) -> void:
	monitor.position = Vector3.ZERO
	monitor.rotation = Vector3.ZERO
	monitor.linear_velocity = Vector3.ZERO
	monitor.angular_velocity = Vector3.ZERO
	monitor.gravity_scale = 0
	monitor.lock_rotation = true
	await _steps(25)
	var hitter := _hitter(distance, spin, pivot_offset)
	await _steps(2)
	hitter.linear_velocity = Vector3(0, 0, -16)
	_grabber._thrown_bodies.append(hitter)
	_grabber._limit_throw_motion(hitter, 1.0 / 60.0)
	await _steps(45)
	hitter.queue_free()
	await _steps(3)


func _test_distance() -> void:
	var measurements: Array[float] = []
	for distance: float in [0.6, 2.0, 5.0]:
		await _setup()
		var monitor := _prop("monitor", Vector3.ZERO)
		await _hit(monitor, distance)
		measurements.append(monitor.last_impact_severity)
		print("DISTANCE d=%.2f closing=%.4f effective_mass=%.4f severity=%.4f source=%s" %
			[distance, monitor.last_closing_speed, monitor.last_effective_mass,
			monitor.last_impact_severity, monitor.last_impact_source])
		_check(monitor.damage_state == ImpactBody.State.CRACKED
			and absf(monitor.last_closing_speed - 16.0) < 0.1
			and absf(monitor.last_effective_mass - 40.0 / 13.0) < 0.01,
			"Equivalent contact uses actual speed/reduced mass at %.1f m" % distance)
		await _cleanup()
	_check(measurements.max() - measurements.min() < measurements.max() * 0.01,
		"Equivalent impacts agree within 1% across close, normal and far distances")
	# Rotation changes real contact-point velocity. Check against the measured
	# condition, not against a distance-specific or time-since-release multiplier.
	for distance: float in [1.0, 3.0, 4.8, 5.0, 5.2]:
		await _setup()
		var monitor := _prop("monitor", Vector3.ZERO)
		await _hit(monitor, distance, Vector3(3, 2, 1))
		print("TUMBLE d=%.2f closing=%.4f severity=%.4f source=%s" %
			[distance, monitor.last_closing_speed, monitor.last_impact_severity, monitor.last_impact_source])
		_check(monitor.damage_state == ImpactBody.State.CRACKED and monitor.last_impact_severity > 300
			and monitor.last_impact_source == "confirmed sweep",
			"Tumbling sweep reaches a real contact before its estimate expires at %.1f m" % distance)
		await _cleanup()
	var pivot_measurements: Array[float] = []
	for pivot_offset: float in [0.0, 0.7]:
		await _setup()
		var monitor := _prop("monitor", Vector3.ZERO)
		await _hit(monitor, 3.0, Vector3(3, 2, 1), pivot_offset)
		pivot_measurements.append(monitor.last_impact_severity)
		await _cleanup()
	_check(pivot_measurements.min() > 300 and pivot_measurements.max() - pivot_measurements.min() < 1.0,
		"Angular contact severity is independent of the scene pivot, using the physical center of mass")


func _lowest_mesh(node: Node, axis: int = 1) -> float:
	var lowest := INF
	if node is MeshInstance3D and node.is_visible_in_tree():
		var bounds: AABB = node.mesh.get_aabb()
		for corner in 8:
			lowest = minf(lowest, (node.global_transform * bounds.get_endpoint(corner))[axis])
	for child in node.get_children():
		lowest = minf(lowest, _lowest_mesh(child, axis))
	return lowest


func _test_floor() -> void:
	await _setup()
	_box(Vector3(0, -0.2, 0), Vector3(80, 0.4, 80))
	var bodies: Array[ImpactBody] = []
	for kind: String in ["ceramic", "glass", "plastic", "wood", "metal", "monitor"]:
		bodies.append(_prop(kind, Vector3(bodies.size() * 3 - 9, 0.9, 8)))
	# Fallen upright, face-down, side-down and tumbling monitors, including fast
	# drops that never entered the grabber's thrown-body list.
	for index in 12:
		var monitor := _prop("monitor", Vector3((index % 4) * 4 - 8, 2, floorf(index / 4.0) * 4 - 8))
		monitor.rotation = Vector3(index * 0.37, index * 0.63, index * 0.21)
		monitor.linear_velocity = Vector3(0, -26 if index >= 6 else 0, 0)
		monitor.angular_velocity = Vector3(2, 5, 3) if index % 2 else Vector3.ZERO
		bodies.append(monitor)
	await _steps(900)
	for body in bodies:
		var bottom := _lowest_mesh(body)
		_check(bottom >= -0.025 and bottom < 0.08,
			"Visible %s stays on the floor (bottom %.4f m, state %d)" % [body.name, bottom, body.damage_state])
	# Fast dead electronics must also retain sweeps despite reporting no damage.
	var dead: ImpactBody = bodies.back()
	dead.damage_state = ImpactBody.State.BROKEN
	dead._commit_state()
	dead.position = Vector3(0, 2, 15)
	dead.rotation = Vector3(PI / 2, 0, 0)
	dead.linear_velocity = Vector3(0, -26, 0)
	await _steps(600)
	_check(_lowest_mesh(dead) >= -0.025 and dead.max_contacts_reported == 4,
		"Broken monitor remains floor-safe with support-only contact reporting")
	await _cleanup()


func _test_surfaces() -> void:
	for tabletop: bool in [false, true]:
		await _setup()
		_box(Vector3(0, -0.2, 0), Vector3(40, 0.4, 40))
		if tabletop:
			_box(Vector3(0, 1.215, 0), Vector3(18, 0.07, 8))
		else:
			_box(Vector3(0, 2, 0), Vector3(18, 4, 0.07))
		var bodies: Array[ImpactBody] = []
		for kind: String in ["plastic", "wood", "metal", "monitor"]:
			var body := _prop(kind, Vector3(bodies.size() * 3 - 4.5, 3 if tabletop else 1, 0 if tabletop else 2))
			body.linear_velocity = Vector3(0, -26, 0) if tabletop else Vector3(0, 0, -26)
			body.angular_velocity = Vector3(2, 5, 3)
			bodies.append(body)
		await _steps(900)
		for body in bodies:
			var bound := _lowest_mesh(body, 1 if tabletop else 2)
			_check(bound >= (1.225 if tabletop else 0.01),
				"Fast tumbling %s stays outside thin %s (bound %.4f m)" %
				[body.name, "tabletop" if tabletop else "wall", bound])
		await _cleanup()


func _test_monitor_recovery() -> void:
	for hits in 3:
		await _setup()
		var monitor := _prop("monitor", Vector3.ZERO)
		monitor.gravity_scale = 0
		var collider := monitor.get_node("ScreenCollision") as CollisionShape3D
		var original_shape := collider.shape
		for hit in hits:
			await _hit(monitor, 2.0)
		_check(monitor.damage_state == hits and collider.shape == original_shape
			and not collider.disabled and monitor.collision_layer == 4 and monitor.continuous_cd,
			"Real damage transition %d preserves monitor collision and CCD" % hits)
		_box(Vector3(0, -0.2, 0), Vector3(20, 0.4, 20))
		monitor.position = Vector3(0, 0.8, 0)
		monitor.rotation = Vector3(PI / 2 if hits % 2 else 0, 0, 0)
		monitor.linear_velocity = Vector3.ZERO
		monitor.gravity_scale = 1
		monitor.lock_rotation = false
		await _steps(600)
		_check(_lowest_mesh(monitor) >= -0.025, "Fallen damage state %d has no embedded screen" % hits)
		_player.position = Vector3(0, 0.02, 2.4)
		_player.camera.look_at(monitor.to_global(Vector3(0, 0.7, 0)))
		await _steps(2)
		_grabber.try_pick_up()
		_check(_grabber.held_body == monitor, "Fallen damage state %d remains ray-grabbable" % hits)
		# Looking up should lift the geometry center, not drag the floor-level pivot.
		_player.camera.rotation = Vector3.ZERO
		await _steps(180)
		_check(_grabber.held_body == monitor and _lowest_mesh(monitor) > 0.6
			and monitor.to_global(_grabber._held_center).distance_to(
				_player.camera.global_position - _player.camera.global_basis.z * _grabber.current_hold_distance) < 0.15,
			"Recovered monitor %d holds stably around its geometry center" % hits)
		_grabber.release()
		await _cleanup()


func _test_player_clearance() -> void:
	await _setup()
	_box(Vector3(0, -0.2, 0), Vector3(20, 0.4, 20))
	_box(Vector3(0, 1.5, -0.5), Vector3(8, 3, 0.15))
	_player.position = Vector3(0, 0.02, 3)
	_player.camera.rotation = Vector3.ZERO
	_player.set_physics_process(true)
	var monitor := _prop("monitor", Vector3(0, 0.9, 1))
	monitor.gravity_scale = 0
	await _steps(2)
	_grabber.try_pick_up()
	_check(_grabber.held_body == monitor, "Wall safety fixture grabs the monitor")
	await _steps(60)
	var peak_y := 0.0
	var peak_step := 0.0
	Input.action_press("move_forward")
	for frame in 55:
		var before := _player.position
		await _steps(1)
		peak_step = maxf(peak_step, before.distance_to(_player.position))
		peak_y = maxf(peak_y, _player.position.y)
	Input.action_release("move_forward")
	_grabber.release()
	await _steps(60)
	_check(peak_step < 0.13 and peak_y < 0.08 and _player.velocity.length() < 0.1,
		"Walking a held monitor into a wall and dropping does not launch the player")
	_check(not is_instance_valid(_grabber.held_body) and _player.position.z > -0.13,
		"Insufficient wall clearance releases the physical hold before trapping")
	monitor.queue_free()
	await _steps(3)
	_player.position = Vector3(0, 0.02, 3)
	await _steps(3)
	var body := _prop("metal", Vector3(0, 1.62, 1))
	body.gravity_scale = 0
	await _steps(2)
	_grabber.try_pick_up()
	_check(_grabber.held_body == body, "Overlap safety fixture grabs a heavy prop")
	# Simulate walking/turning into a lagging held body. The exception already
	# exists; the guard must stop its spring before re-enabling player contacts.
	body.position = _player.position + Vector3(0, 0.9, 0)
	body.linear_velocity = Vector3.ZERO
	await _steps(3)
	_check(not is_instance_valid(_grabber.held_body) and body.get_collision_exceptions().has(_player),
		"Actual player overlap stops the spring and defers collision restoration")
	_player.camera.rotation.x = -PI / 2
	_grabber.try_pick_up()
	_check(not is_instance_valid(_grabber.held_body), "E cannot reattach an overlapping dropped body")
	var player_before := _player.position
	await _steps(30)
	_check(_player.position.distance_to(player_before) < 0.05 and _player.velocity.length() < 0.1,
		"Overlapping drop does not depenetrate or launch the player")
	_player.position.x = 2
	await _steps(4)
	_check(not body.get_collision_exceptions().has(_player),
		"Player collision is restored after genuine separation")
	body.queue_free()
	await _steps(3)
	# Standing on a movable support must not turn that support into a hold.
	var support := load("res://scenes/props/physics_prop.tscn").instantiate() as RigidBody3D
	support.position = Vector3(3, 0.3, 3)
	_world.add_child(support)
	_player.position = Vector3(3, 0.62, 3)
	_player.camera.rotation.x = -PI / 2
	await _steps(90)
	_grabber.try_pick_up()
	_check(not is_instance_valid(_grabber.held_body) and _player.is_on_floor(),
		"Picking the prop underfoot cannot create a player/hold constraint")
	await _cleanup()


func _steps(count: int) -> void:
	for frame in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
