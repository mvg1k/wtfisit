extends SceneTree

var _world: Node3D
var _player: SandboxPlayer
var _failures: int = 0
var _render: bool = false
var _camera: Camera3D


func _initialize() -> void:
	_render = OS.get_cmdline_user_args().has("--render")
	_run.call_deferred()


func _run() -> void:
	await _test_push()
	await _test_gap()
	await _test_resting_contacts()
	await _test_fragments()
	print("CONTACT SETTLING SMOKE: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _setup() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(0, -0.2, 0), Vector3(30, 0.4, 30))
	_player = load("res://scenes/player.tscn").instantiate() as SandboxPlayer
	_player.position = Vector3(0, 0.02, 2)
	_world.add_child(_player)
	if _render:
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.15, 0.19, 0.23)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.6
		_world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-60, -25, 0)
		light.shadow_enabled = true
		_world.add_child(light)
		_camera = Camera3D.new()
		_world.add_child(_camera)
		_camera.position = Vector3(5, 5, 7)
		_camera.look_at(Vector3(0, 0.7, 0))
		_camera.make_current()
		var avatar := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.3
		mesh.height = 1.8
		avatar.mesh = mesh
		avatar.material_override = _material(Color(0.8, 0.24, 0.12))
		avatar.position.y = 0.9
		_player.add_child(avatar)
	await _steps(3)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


func _box(location: Vector3, size: Vector3, mass: float = 0.0) -> PhysicsBody3D:
	var body: PhysicsBody3D = RigidBody3D.new() if mass > 0 else StaticBody3D.new()
	body.collision_layer = 4 if mass > 0 else 1
	body.collision_mask = 7
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(Color(0.7, 0.57, 0.34) if mass > 0 else Color(0.4, 0.47, 0.5))
	body.add_child(visual)
	body.position = location
	if body is RigidBody3D:
		body.mass = mass
		body.continuous_cd = true
		body.linear_damp = 0.15
		body.angular_damp = 0.4
		body.physics_material_override = PhysicsMaterial.new()
		body.physics_material_override.friction = 0.65
		body.add_to_group("grabbable")
	_world.add_child(body)
	return body


func _test_push() -> void:
	var travel: Array[float] = []
	for mass: float in [0.25, 2.0, 12.0, 100.0]:
		await _setup()
		var body := _box(Vector3(0, 0.3, 0), Vector3.ONE * 0.6, mass) as RigidBody3D
		body.lock_rotation = true # Isolate mass resistance from tipping/bypassing.
		await _steps(90)
		_check(body.sleeping, "Walking fixture starts asleep at %.2f kg" % mass)
		var start := body.position
		var peak_speed := 0.0
		var peak_step := 0.0
		var peak_height := 0.0
		await _capture("push_%s_start" % mass)
		Input.action_press("move_forward")
		for frame in 180:
			var before := _player.position
			await _steps(1)
			peak_speed = maxf(peak_speed, body.linear_velocity.length())
			peak_step = maxf(peak_step, before.distance_to(_player.position))
			peak_height = maxf(peak_height, _player.position.y)
		Input.action_release("move_forward")
		await _steps(30)
		travel.append(start.z - body.position.z)
		print("PUSH mass=%.2f travel=%.4f peak_speed=%.3f step=%.4f height=%.4f" %
			[mass, travel.back(), peak_speed, peak_step, peak_height])
		_check(peak_speed < 3.5 and peak_step < 0.13 and peak_height < 0.1,
			"Walking contact stays bounded without launching at %.2f kg" % mass)
		_check(travel.back() > (0.15 if mass >= 12 else 0.8) if mass < 100 else travel.back() < 0.1,
			"Movable props yield; intentionally immovable mass resists at %.2f kg" % mass)
		await _capture("push_%s_end" % mass)
		await _cleanup()
	_check(travel[0] > travel[1] * 1.15 and travel[1] > travel[2] * 1.5,
		"Light, medium and heavy walking resistance is mass-aware")


func _test_gap() -> void:
	await _setup()
	_player.position.z = 2.8
	var left := _box(Vector3(-0.57, 0.5, 0), Vector3(0.65, 1, 2), 2) as RigidBody3D
	var right := _box(Vector3(0.57, 0.5, 0), Vector3(0.65, 1, 2), 5) as RigidBody3D
	left.rotation.y = -0.18
	right.rotation.y = 0.18
	await _steps(90)
	await _capture("gap_start")
	var peak_step := 0.0
	var peak_y := 0.0
	var peak_speed := 0.0
	Input.action_press("move_forward")
	for frame in 300:
		var before := _player.position
		await _steps(1)
		peak_step = maxf(peak_step, before.distance_to(_player.position))
		peak_y = maxf(peak_y, _player.position.y)
		peak_speed = maxf(peak_speed, maxf(left.linear_velocity.length(), right.linear_velocity.length()))
		if _player.position.z < -2:
			break
	Input.action_release("move_forward")
	print("GAP player=", _player.position, " step=", peak_step, " props_speed=", peak_speed)
	_check(_player.position.z < -1.6, "Player opens and passes a narrowing gap between movable props")
	_check(peak_step < 0.13 and peak_y < 0.1 and peak_speed < 3.5,
		"Narrow-gap recovery has no teleport or player/prop launch")
	await _capture("gap_end")
	# Backing out remains ordinary collision-resolved movement, not an E escape.
	Input.action_press("move_back")
	await _steps(180)
	Input.action_release("move_back")
	_check(_player.position.z > 1.5, "Player can back out without grabbing or collision exceptions")
	await _cleanup()


func _test_resting_contacts() -> void:
	for rotation: Vector3 in [Vector3.ZERO, Vector3(PI / 2, 0, 0), Vector3(-PI / 2, 0, 0),
			Vector3(0, 0, PI / 2), Vector3(0.7, 1.1, 0.4), Vector3(1.7, 0.6, 2.3)]:
		await _setup()
		_player.position = Vector3(0, 0.02, 5)
		var monitor := load("res://scenes/props/monitor.tscn").instantiate() as RigidBody3D
		monitor.position = Vector3(0, 1.4, 0)
		monitor.rotation = rotation
		_world.add_child(monitor)
		await _steps(900)
		print("REST monitor rotation=", rotation, " v=", monitor.linear_velocity, " spin=", monitor.angular_velocity)
		_check(monitor.sleeping, "Monitor sleeps on resting orientation " + str(rotation))
		var start := monitor.global_transform
		await _steps(120)
		_check(start.is_equal_approx(monitor.global_transform), "Resting monitor has no persistent motion")
		var center := monitor.to_global(Vector3(0, 0.7, 0))
		_player.position = Vector3(center.x, 0.02, center.z + 1.1)
		_player.camera.look_at(center)
		await _steps(2)
		var grabber := _player.get_node("Grabber") as PhysicsGrabber
		grabber._interact_requested = true
		await _steps(30)
		_check(grabber.held_body == monitor, "E retains fallen monitor while still looking at it")
		_player.camera.rotation = Vector3.ZERO
		await _steps(90)
		grabber.release(true, 0.4)
		await _steps(3)
		_check(not monitor.sleeping and monitor.linear_velocity.length() > 1.0, "Recovered monitor wakes and throws normally")
		await _steps(900)
		_check(monitor.sleeping, "Thrown monitor settles again")
		await _cleanup()
	# Ordinary, script-free bodies: side contact and a leaning body on a support.
	for fixture in 3:
		var leaning := fixture == 1
		await _setup()
		_player.position = Vector3(0, 0.02, 5)
		var first := _box(Vector3(0, 0.3, 0), Vector3.ONE * 0.6, 2) as RigidBody3D
		var second := _box(Vector3(0.6 if not leaning else 0.25, 0.3 if not leaning else 1.0, 0),
			Vector3(0.6, 0.6, 0.6) if not leaning else Vector3(1.0, 0.18, 0.7), 1) as RigidBody3D
		second.rotation.z = 0.5 if leaning else 0.05
		if fixture == 2:
			# Reproduced persistent rocking after two ordinary boxes collide.
			first.position = Vector3(0, 0.35, 0)
			first.rotation = Vector3(0.68, 1.24, 0.44)
			second.queue_free()
			second = _box(Vector3(0.2, 0.95, 0.1), Vector3(0.8, 0.2, 0.5), 0.5) as RigidBody3D
			second.rotation = Vector3(0.92, 1.48, 1.16)
		await _steps(900)
		print("REST pair leaning=", leaning, " v=", first.linear_velocity, second.linear_velocity,
			" spin=", first.angular_velocity, second.angular_velocity)
		_check(first.sleeping and second.sleeping, "Touching ordinary props settle and sleep")
		var first_pose := first.global_transform
		var second_pose := second.global_transform
		await _steps(120)
		_check(first_pose.is_equal_approx(first.global_transform) and second_pose.is_equal_approx(second.global_transform),
			"Settled ordinary pair has no persistent motion")
		var before := first.position
		first.apply_central_impulse(Vector3(0, 0, -2))
		await _steps(12)
		_check(not first.sleeping and before.distance_to(first.position) > 0.03, "Settled prop wakes on impulse")
		await _cleanup()


func _test_fragments() -> void:
	for kind: String in ["ceramic", "glass"]:
		for fixture in 4:
			var beside := fixture == 1
			await _setup()
			_player.position = Vector3(10, 0.02, 10)
			_player.set_physics_process(false)
			_box(Vector3(0, 1.1, 0), Vector3(4, 0.12, 4))
			if beside:
				_box(Vector3(0, 1.6, -0.1), Vector3(4, 1, 0.12))
			var body := load("res://scenes/props/" + kind + "_prop.tscn").instantiate() as ImpactBody
			body.position = Vector3(0, 1.5, 0.4) if beside else Vector3(0, 2, 0)
			body.rotation = Vector3(1.0, 0.5, 0.7)
			if fixture == 2:
				body.position = Vector3(2.7, 1.1, 2.7)
				body.rotation = Vector3.ZERO
				body.gravity_scale = 0
			elif fixture == 3:
				body.position = Vector3(0, 0.55, 0)
			_world.add_child(body)
			await _steps(3)
			body.linear_velocity = Vector3(0, -2, -15) if beside else Vector3(0, -15, 0)
			if fixture == 2:
				body.linear_velocity = Vector3(-12, 0, -12)
			elif fixture == 3:
				body.linear_velocity = Vector3(0, 15, 0)
			body.angular_velocity = Vector3(3, 2, 1)
			var early_overlap := false
			var dynamic_motion := false
			for frame in 90:
				await _steps(1)
				var pieces := get_nodes_in_group("impact_debris")
				if not pieces.is_empty():
					for piece: RigidBody3D in pieces:
						dynamic_motion = dynamic_motion or piece.linear_velocity.length() > 0.2
						early_overlap = early_overlap or _penetrates(piece, 0.025)
			print("FRAGMENT FIXTURE ", kind, " case=", fixture)
			await _capture(kind + "_%d_early" % fixture)
			_check(not is_instance_valid(body) and get_nodes_in_group("impact_debris").size() == 4,
				"Furniture impact creates bounded debris: %s beside=%s" % [kind, beside])
			_check(dynamic_motion, "Fragments move physically after breakage: %s beside=%s" % [kind, beside])
			_check(not early_overlap, "Fragments never enter furniture deeply: %s beside=%s" % [kind, beside])
			await _steps(810)
			var settled := true
			var max_drift := 0.0
			var pieces := get_nodes_in_group("impact_debris")
			var positions: Array[Vector3] = []
			for piece: RigidBody3D in pieces:
				positions.append(piece.position)
				settled = settled and piece.sleeping and not _penetrates(piece, 0.012)
				settled = settled and not piece.freeze and piece.can_sleep and not piece is ImpactBody
				if not piece.sleeping:
					print("DEBRIS AWAKE ", kind, " pos=", piece.position, " v=", piece.linear_velocity, " spin=", piece.angular_velocity)
			await _steps(120)
			for index in pieces.size():
				max_drift = maxf(max_drift, positions[index].distance_to(pieces[index].position))
			_check(settled and max_drift < 0.002, "Debris rests clear and sleeps without persistent jitter: %s beside=%s" % [kind, beside])
			_check(get_nodes_in_group("impact_debris").size() == 4, "Debris remains non-recursive: " + kind)
			await _capture(kind + "_%d_settled" % fixture)
			if (fixture == 0 or fixture == 3) and pieces.size() == 4:
				if fixture == 3:
					_player.set_physics_process(true)
					_player.set_mouse_captured(true)
					Input.action_press("crouch")
					await _steps(20)
				await _test_debris_recovery(pieces[0])
				Input.action_release("crouch")
			await _cleanup()


func _test_debris_recovery(piece: ImpactDebris) -> void:
	# Use the real ray pickup and throw path after the settling mode has engaged.
	var grabber := _player.get_node("Grabber") as PhysicsGrabber
	_player.position = Vector3(piece.position.x, 0.02, piece.position.z + 0.8)
	_player.camera.look_at(piece.global_position)
	_player.set_mouse_captured(true)
	await _steps(2)
	var resting_height := piece.position.y
	grabber.try_pick_up()
	_check(grabber.held_body == piece, "Sleeping debris can be picked up through the normal ray")
	await _steps(30)
	_check(grabber.held_body == piece, "E retains debris while looking down at its resting surface")
	_player.camera.rotation = Vector3.ZERO
	await _steps(90)
	_check(grabber.held_body == piece and piece.position.y > resting_height + 0.2 and not piece._settling,
		"Picking up debris leaves supported settling mode")
	grabber.release()
	await _steps(900)
	_check(piece.sleeping and not piece.freeze, "Dropped debris remains physical and settles")
	_player.position = Vector3(piece.position.x, 0.02, piece.position.z + 0.8)
	_player.camera.look_at(piece.position)
	await _steps(2)
	grabber._interact_requested = true
	await _steps(30)
	_check(grabber.held_body == piece, "Dropped debris can be picked up again with E")
	_player.camera.rotation = Vector3.ZERO
	await _steps(90)
	grabber.release(true, 0.4)
	await _steps(3)
	_check(piece.linear_velocity.length() > 1.0 and is_equal_approx(piece.angular_damp, 2.0),
		"Re-thrown debris restores flight damping instead of saved settling damping")
	await _steps(900)
	_check(piece.sleeping and not piece.freeze, "Re-thrown debris settles again without freezing")


func _penetrates(piece: RigidBody3D, tolerance: float) -> bool:
	# Actual contact-pair depth works for arbitrarily oriented convex shards.
	# A center/AABB or axis-wise shrink can misclassify rotated edge contacts.
	var source := (piece.get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = source
	query.transform = piece.global_transform
	query.collision_mask = 1
	query.margin = 0
	var contacts := _world.get_world_3d().direct_space_state.collide_shape(query, 8)
	for pair in range(0, contacts.size(), 2):
		if contacts[pair].distance_to(contacts[pair + 1]) > tolerance:
			print("PENETRATION depth=", contacts[pair].distance_to(contacts[pair + 1]), " position=", piece.position, " v=", piece.linear_velocity, " spin=", piece.angular_velocity)
			return true
	return false


func _capture(label: String) -> void:
	if not _render:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.validation/contact_" + label + ".png")


func _cleanup() -> void:
	_world.queue_free()
	await _steps(3)


func _steps(count: int) -> void:
	for frame in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
