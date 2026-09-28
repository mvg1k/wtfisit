extends SceneTree

const ROOM: PackedScene = preload("res://scenes/search_room.tscn")
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
var _failures: int = 0
var _world: Node3D
var _grabber: PhysicsGrabber
var _cases: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var player := PLAYER.instantiate() as SandboxPlayer
	_world.add_child(player)
	player.position = Vector3(0, -30, 0)
	player.set_physics_process(false)
	player.camera.rotation = Vector3.ZERO
	_grabber = player.get_node("Grabber") as PhysicsGrabber
	_grabber._throw_rng.seed = 20260929
	var source := ROOM.instantiate() as SearchRoom
	# Use real simple and compound props, including the thin rectangular book.
	# Separate lanes exercise the same origin-relative impacts without interaction.
	for prop: String in ["LooseBook", "ClutterScreen", "CoveredBox", "Sandbox/MediumBox", "LowStool"]:
		for thickness: float in [0.07, 0.14, 0.2]:
			for spin: bool in [false, true]:
				for speed: float in [12.0, 26.0]:
					var lane := Vector3((_cases.size() % 10) * 8, 0, floorf(_cases.size() / 10.0) * 12)
					_box(lane, Vector3(0.18, 4, thickness))
					_box(lane + Vector3(0, -2.2, 0), Vector3(7, 0.4, 10))
					var body := source.get_node(prop).duplicate() as RigidBody3D
					_world.add_child(body)
					body.position = lane + Vector3(0, 0, 1.5)
					body.rotation = Vector3(0.37, 0.52, 0.23) if spin else Vector3(PI / 2, 0, 0)
					body.sleeping = false
					_cases.append({"body": body, "lane": lane, "spin": spin, "speed": speed,
						"label": "%s / %.2fm / spin=%s / %.0fm/s" % [prop, thickness, spin, speed],
						"crossed": false})
	source.free()
	await _steps(2)
	for data in _cases:
		var body: RigidBody3D = data.body
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3(2, 5, 1) if data.spin else Vector3.ZERO
		_grabber.held_body = body
		_grabber._saved_angular_damp = body.angular_damp
		var before := body.global_transform
		_grabber.release(true, 1.2)
		var velocity: Vector3 = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		_check(body.global_transform == before and is_equal_approx(-velocity.z,
			_grabber.full_throw_speed * _grabber._throw_mass_factor(body.mass)),
			"Maximum throw preserves transform and unobstructed speed: " + data.label)
		# Isolate collision coverage at the old nominal speed and new absolute cap,
		# including deliberately unspun faces that expose native CCD ray gaps.
		body.linear_velocity = Vector3(0, 0, -data.speed)
		if not data.spin:
			body.angular_velocity = Vector3.ZERO
	# Optional negative control: confirms native CCD alone misses the narrow post.
	if OS.get_cmdline_user_args().has("--native-ccd"):
		_grabber._thrown_bodies.clear()
	for frame in 600:
		await physics_frame
		for data in _cases:
			var body: RigidBody3D = data.body
			# A centered, unspun face must hit the post before reaching its far side.
			# Spinning impacts may legitimately deflect around the post.
			if not data.spin and body.position.z < data.lane.z - 0.4 and body.linear_velocity.z < -8.0:
				data.crossed = true
	for data in _cases:
		_check(not data.crossed, "No fast pass-through: " + data.label)
		_check(_penetration(data.body) < 0.035, "No persistent embedding: " + data.label)
	_check(_grabber._thrown_bodies.is_empty(), "Sweep tracking ends when thrown props sleep")
	await _test_close_release()
	# A prop freed in flight must not leave an invalid reference in the update loop.
	var disposable := RigidBody3D.new()
	_world.add_child(disposable)
	_grabber._thrown_bodies.append(disposable)
	disposable.queue_free()
	await _steps(2)
	_check(_grabber._thrown_bodies.is_empty(), "Freed thrown props are removed safely")
	_world.queue_free()
	await process_frame
	print("THROW SMOKE: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _test_close_release() -> void:
	_box(Vector3(-8, 0, 0), Vector3(0.18, 4, 0.07))
	var body := RigidBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.6, 0.1)
	collision.shape = shape
	body.add_child(collision)
	body.mass = 0.25
	body.collision_layer = 4
	body.collision_mask = 7
	body.continuous_cd = true
	body.gravity_scale = 0
	_world.add_child(body)
	body.position = Vector3(-8, 0, 0.11)
	await _steps(2)
	_grabber.held_body = body
	_grabber._saved_angular_damp = body.angular_damp
	var before := body.global_transform
	_grabber.release(true, 1.2)
	var velocity: Vector3 = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	_check(body.global_transform == before and -velocity.z > 0.0 and -velocity.z < 22.8,
		"Close release sweeps the new impulse immediately without teleporting")
	await _steps(60)
	_check(body.position.z > 0.0 and _penetration(body) < 0.035,
		"Close-range throw stays on the impact side without embedding")
	body.queue_free()
	await _steps(2)


func _box(position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_world.add_child(body)
	body.position = position


func _penetration(body: RigidBody3D) -> float:
	var depth := 0.0
	for owner_id: int in body.get_shape_owners():
		for index in body.shape_owner_get_shape_count(owner_id):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = body.shape_owner_get_shape(owner_id, index)
			query.transform = body.global_transform * body.shape_owner_get_transform(owner_id)
			query.collision_mask = 1
			var contacts := _world.get_world_3d().direct_space_state.collide_shape(query, 32)
			for point in range(0, contacts.size(), 2):
				depth = maxf(depth, contacts[point].distance_to(contacts[point + 1]))
	return depth


func _steps(count: int) -> void:
	for frame in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
