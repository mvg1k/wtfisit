extends SceneTree

const ROOM: PackedScene = preload("res://scenes/test_room.tscn")
const PROP: PackedScene = preload("res://scenes/props/physics_prop.tscn")
var _failures: int = 0
var _room: Node3D
var _player: SandboxPlayer
var _grabber: PhysicsGrabber


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_room = ROOM.instantiate()
	root.add_child(_room)
	_player = _room.get_node("Player") as SandboxPlayer
	_grabber = _player.get_node("Grabber") as PhysicsGrabber
	await _steps(480)
	_check(_player.is_on_floor(), "Player settles on the floor")
	var sleeping_count: int = 0
	for body: RigidBody3D in get_nodes_in_group("grabbable"):
		if body.sleeping:
			sleeping_count += 1
		else:
			print("AWAKE: ", body.name, " velocity=", body.linear_velocity, " angular=", body.angular_velocity)
	_check(sleeping_count == 8, "All eight idle room props sleep")

	var start := _player.position
	Input.action_press("move_forward")
	await _steps(20)
	Input.action_release("move_forward")
	await _steps(20)
	_check(_player.position.z < start.z - 0.7, "Forward movement works")
	_check(absf(_player.velocity.z) < 0.01, "Ground movement decelerates")
	Input.action_press("jump")
	await _steps(2)
	Input.action_release("jump")
	await _steps(10)
	_check(_player.position.y > 0.4, "Jump lifts the player")
	await _steps(90)
	_check(_player.is_on_floor(), "Gravity returns the player to the floor")
	_player.position = Vector3(0, 0.02, 3.25)
	_player.camera.rotation = Vector3.ZERO
	await _steps(10)

	var light_speed: float = 0.0
	var heavy_speed: float = 0.0
	for test_mass: float in [0.25, 2.0, 12.0]:
		var body := _spawn_prop(test_mass, _player.camera.global_position + Vector3(0, 0, -2))
		await _steps(1)
		_grabber.try_pick_up()
		_check(_grabber.held_body == body, "Ray pickup at %.2f kg" % test_mass)
		await _steps(120)
		var target := _player.camera.global_position + Vector3(0, 0, -2)
		_check(body.global_position.distance_to(target) < 0.15, "Stable hold at %.2f kg" % test_mass)
		_check(body.linear_velocity.length() < 0.3, "Hold settles at %.2f kg" % test_mass)
		_grabber.release(true)
		await _steps(2)
		var speed := -body.linear_velocity.z
		_check(speed > 0.5, "Throw moves forward at %.2f kg" % test_mass)
		_check(is_equal_approx(body.angular_damp, 0.4), "Original damping restored")
		await _steps(8)
		_check(not body.get_collision_exceptions().has(_player), "Player collision restored after throw")
		if test_mass < 1.0:
			light_speed = speed
		elif test_mass > 10.0:
			heavy_speed = speed
		body.queue_free()
		await _steps(2)
	_check(light_speed > heavy_speed * 1.5 and heavy_speed > light_speed * 0.5,
		"Heavy throws are slower but remain within a usable bounded range")

	# A solid wall must block selection as well as the held body's motion.
	_player.position = Vector3(0, 0.02, -2.7)
	await _steps(3)
	var behind_wall := _spawn_prop(2.0, Vector3(0, 1.6, -5.35))
	await _steps(1)
	_grabber.try_pick_up()
	_check(not is_instance_valid(_grabber.held_body), "Cannot select through a wall")
	behind_wall.queue_free()
	var wall_prop := _spawn_prop(2.0, Vector3(0, 1.6, -4.0))
	await _steps(1)
	_grabber.try_pick_up()
	await _steps(150)
	_check(wall_prop.position.z > -4.6, "Held object cannot tunnel through wall")
	_check(wall_prop.linear_velocity.length() < 1.0, "Wall contact remains stable")
	_grabber.release()
	await _steps(360)
	_check(wall_prop.sleeping, "Dropped object returns to sleep")
	wall_prop.queue_free()

	_player.position = Vector3(0, 0.02, 3.25)
	await _steps(3)
	var dropped := _spawn_prop(2.0, _player.camera.global_position + Vector3(0, 0, -2))
	await _steps(1)
	_grabber.try_pick_up()
	_player.set_mouse_captured(false)
	await _steps(2)
	_check(not is_instance_valid(_grabber.held_body), "Cursor release drops held object")
	_player.set_mouse_captured(true)
	dropped.queue_free()
	await _steps(2)

	var overlapping := _spawn_prop(2.0, _player.camera.global_position + Vector3(0, 0, -2))
	await _steps(1)
	_grabber.try_pick_up()
	overlapping.global_position = _player.global_position + Vector3(0, 0.9, 0)
	await _steps(1)
	_grabber.release()
	await _steps(2)
	_check(overlapping.get_collision_exceptions().has(_player), "Overlapping release keeps collision exception")
	_player.position.x = 2.0
	await _steps(4)
	_check(not overlapping.get_collision_exceptions().has(_player), "Separation restores collision exception")
	overlapping.queue_free()
	_player.position.x = 0.0
	await _steps(2)

	var overstretched := _spawn_prop(2.0, _player.camera.global_position + Vector3(0, 0, -2))
	await _steps(1)
	_grabber.try_pick_up()
	_player.position.x = 4.0
	await _steps(2)
	_check(not is_instance_valid(_grabber.held_body), "Overstretched hold releases")
	overstretched.queue_free()
	_player.position.x = 0.0
	await _steps(2)

	var obstructed := _spawn_prop(2.0, _player.camera.global_position + Vector3(0, 0, -2))
	await _steps(1)
	_grabber.try_pick_up()
	var blocker := StaticBody3D.new()
	var blocker_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 0.25)
	blocker_shape.shape = box
	blocker.add_child(blocker_shape)
	_room.add_child(blocker)
	blocker.global_position = _player.camera.global_position + Vector3(0, 0, -1)
	await _steps(30)
	_check(not is_instance_valid(_grabber.held_body), "Obstructed hold releases")
	blocker.queue_free()
	obstructed.queue_free()
	await _steps(2)

	# Despawn while held must not leave a stale-reference error.
	var removed := _spawn_prop(2.0, _player.camera.global_position + Vector3(0, 0, -2))
	await _steps(1)
	_grabber.try_pick_up()
	removed.queue_free()
	await _steps(3)
	_grabber.release()
	_check(_grabber.held_body == null, "Freed held body is handled safely")
	print("PHYSICS SMOKE: %d failure(s)" % _failures)
	_room.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)


func _spawn_prop(test_mass: float, location: Vector3) -> RigidBody3D:
	var body := PROP.instantiate() as RigidBody3D
	body.mass = test_mass
	_room.add_child(body)
	body.global_position = location
	return body


func _steps(count: int) -> void:
	for index in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
