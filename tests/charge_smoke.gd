extends SceneTree

const ROOM: PackedScene = preload("res://scenes/test_room.tscn")
const PROP: PackedScene = preload("res://scenes/props/physics_prop.tscn")
var _room: Node3D
var _player: SandboxPlayer
var _grabber: PhysicsGrabber
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_room = ROOM.instantiate()
	root.add_child(_room)
	_player = _room.get_node("Player") as SandboxPlayer
	_grabber = _player.get_node("Grabber") as PhysicsGrabber
	_grabber._throw_rng.seed = 20260929
	await _steps(30)
	Input.action_press("move_forward")
	await _steps(20)
	_check(absf(_player.velocity.z + 5.4) < 0.05, "Standing reaches 5.4 m/s (+20%)")
	Input.action_release("move_forward")
	await _steps(14)
	_check(_player.velocity.length() < 0.05, "Faster standing movement still brakes promptly")
	# Exercise real mouse press/release events, including a tap in one frame.
	for frames: int in [0, 24, 48, 72, 108]:
		var body := await _pickup()
		_mouse(true)
		await _steps(frames)
		_check(_grabber.held_body == body and _grabber.is_charging_throw,
			"Charging keeps the body held: %d frames" % frames)
		var charged := _grabber.throw_charge
		_check(absf(charged - minf(frames / 72.0, 1.0)) < 0.025,
			"Charge timing/clamp: %d frames" % frames)
		_room.get_node("DebugOverlay")._update_stats()
		_check(_room.get_node("DebugOverlay/Stats").text.contains("Throw:"), "Debug overlay reports active charge")
		body.linear_velocity = Vector3.ZERO
		_mouse(false)
		await _steps(2)
		var expected := lerpf(4.0, 19.0, charged)
		_check(_grabber.held_body == null and absf(-body.linear_velocity.z - expected) < 0.5,
			"Release launches the selected strength: %d frames" % frames)
		_check(not _grabber.is_charging_throw and _grabber.throw_charge == 0.0,
			"Throw clears charge")
		var orientation := body.global_basis.get_rotation_quaternion()
		await _steps(8)
		_check(orientation.angle_to(body.global_basis.get_rotation_quaternion()) > 0.15
			and body.angular_velocity.length() <= 7.01, "Flight visibly rotates within the spin cap")
		body.queue_free()
		await _steps(2)
	await _test_launch_response()
	await _test_cancellation()
	_room.queue_free()
	await _steps(2)
	await _test_restart()
	print("CHARGE SMOKE: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _test_launch_response() -> void:
	var speeds: Array[float] = []
	for mass: float in [0.25, 2.0, 12.0]:
		var body := await _pickup(mass)
		body.linear_velocity = Vector3.ZERO
		_grabber.release(true, 1.2)
		speeds.append(-_velocity(body).z)
		body.queue_free()
		await _steps(2)
	_check(speeds[0] > speeds[1] and speeds[1] > speeds[2] and speeds[2] >= 12.0,
		"Mass response keeps light props faster and heavy maximum throws useful")
	_check(is_equal_approx(_grabber._throw_mass_factor(0.001), 1.2)
		and is_equal_approx(_grabber._throw_mass_factor(10000.0), 0.65), "Mass response clamps at both extremes")
	var spins: Array[Vector3] = []
	for motion: Vector3 in [Vector3.ZERO, Vector3(0, 0, -5.4), Vector3(5.4, 4, 0), Vector3(100, 100, -100)]:
		var body := await _pickup()
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		_player.velocity = motion
		_grabber.release(true, 0.4)
		var expected := Vector3(0, 0, -9) + (motion * 0.5).limit_length(3.0)
		_check(_velocity(body).distance_to(expected) < 0.01, "Bounded forward/sideways/jump momentum: " + str(motion))
		spins.append(PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY))
		body.queue_free()
		await _steps(2)
	_check(spins[0].distance_to(spins[1]) > 0.001 and spins[1].distance_to(spins[2]) > 0.001,
		"Repeated throws have small angular variation")
	var fast := await _pickup(0.25)
	fast.linear_velocity = Vector3(0, 0, -100)
	fast.angular_velocity = Vector3(100, 0, 0)
	_player.velocity = Vector3(0, 0, -100)
	_grabber.release(true, 50.0)
	var spin: Vector3 = PhysicsServer3D.body_get_state(fast.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	_check(is_equal_approx(_velocity(fast).length(), 26.0) and spin.length() <= 7.01,
		"Extreme existing motion and overcharge obey total linear/angular caps")
	fast.queue_free()
	await _steps(2)


func _test_cancellation() -> void:
	for reason: String in ["drop", "escape", "focus", "obstruction", "deleted"]:
		var body := await _pickup()
		_mouse(true)
		await _steps(12)
		match reason:
			"drop":
				_key(KEY_E)
			"escape":
				_key(KEY_ESCAPE)
			"focus":
				_player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
				_grabber._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			"obstruction":
				_player.position.z = -4.5
			"deleted":
				body.queue_free()
		await _steps(2)
		_mouse(false)
		await _steps(2)
		_check(_grabber.held_body == null and not _grabber.is_charging_throw and _grabber.throw_charge == 0.0
			and _grabber._thrown_bodies.is_empty(), "Cancellation ignores later LMB release: " + reason)
		if is_instance_valid(body):
			body.queue_free()
		await _steps(2)
	var body := await _pickup()
	_mouse(true)
	Input.action_press("crouch")
	await _steps(25)
	_check(_player.stance == SandboxPlayer.Stance.CROUCHING and _grabber.is_charging_throw
		and _grabber.held_body == body, "Crouching while charging preserves a safe hold")
	Input.action_release("crouch")
	_mouse(false)
	await _steps(2)
	_check(_grabber.held_body == null and _grabber.throw_charge == 0.0, "Stance-change throw resets normally")
	body.queue_free()
	await _steps(2)
	_player.set_mouse_captured(false)
	_mouse(true)
	_mouse(false)
	_check(_player.mouse_captured and not _grabber.is_charging_throw, "Cursor recapture click does not start a charge")


func _test_restart() -> void:
	var game := load("res://scenes/search_game.tscn").instantiate() as SearchRun
	root.add_child(game)
	await _steps(4)
	var grabber := game.room.grabber
	var body := PROP.instantiate() as RigidBody3D
	game.room.add_child(body)
	body.global_position = grabber.camera.global_position - grabber.camera.global_basis.z * 2.0
	await _steps(2)
	grabber.try_pick_up()
	_mouse(true)
	await _steps(12)
	_check(grabber.is_charging_throw, "Restart fixture has an active charge")
	await game.start_run()
	_mouse(false)
	await _steps(2)
	_check(not is_instance_valid(grabber) and game.room.grabber.held_body == null
		and not game.room.grabber.is_charging_throw and game.room.grabber.throw_charge == 0.0,
		"Room restart discards charge and ignores old release")
	game.queue_free()
	await _steps(2)


func _pickup(mass: float = 2.0) -> RigidBody3D:
	_grabber.release()
	_player.set_mouse_captured(true)
	_player.position = Vector3(0, 0.02, 3.25)
	_player.rotation = Vector3.ZERO
	_player.camera.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	var body := PROP.instantiate() as RigidBody3D
	body.mass = mass
	_room.add_child(body)
	body.global_position = _player.camera.global_position + Vector3(0, 0, -2)
	await _steps(2)
	_grabber.try_pick_up()
	await _steps(60)
	return body


func _velocity(body: RigidBody3D) -> Vector3:
	return PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)


func _mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func _steps(count: int) -> void:
	for frame in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
