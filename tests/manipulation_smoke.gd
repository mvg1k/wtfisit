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
	await _steps(60)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	_check(InputMap.event_is_action(key, "rotate_held"), "R is mapped to held rotation")

	await _test_rotation(0.25, 0.0, 0.0)
	await _test_rotation(12.0, 1.1, 0.25)
	await _test_distance()
	await _test_contact()
	await _test_clearance()

	Input.action_press("rotate_held")
	var before := _player.camera.global_basis
	_motion(Vector2(30, 15))
	_check(not before.is_equal_approx(_player.camera.global_basis), "R with empty hands leaves camera look active")
	Input.action_release("rotate_held")
	var distance := _grabber.current_hold_distance
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_check(is_equal_approx(distance, _grabber.current_hold_distance), "Wheel with empty hands does nothing")
	print("MANIPULATION SMOKE: %d failure(s)" % _failures)
	_room.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)


func _test_rotation(test_mass: float, yaw: float, pitch: float) -> void:
	_reset_player(yaw, pitch)
	var body := _spawn_prop(test_mass)
	await _steps(1)
	_grabber.try_pick_up()
	_check(_grabber.held_body == body, "Rotation pickup at %.2f kg" % test_mass)
	await _steps(30)
	var camera_before := _player.camera.global_basis
	var initial := body.global_basis.get_rotation_quaternion()
	var expected := Quaternion(camera_before.y, 60 * _grabber.rotation_sensitivity) * (
		Quaternion(camera_before.x, -30 * _grabber.rotation_sensitivity)) * initial
	Input.action_press("rotate_held")
	_motion(Vector2(60, -30))
	_check(camera_before.is_equal_approx(_player.camera.global_basis), "R consumes mouse before camera look")
	await _steps(120)
	_check(expected.angle_to(body.global_basis.get_rotation_quaternion()) < 0.03,
		"Camera-relative rotation converges at %.2f kg" % test_mass)
	_check(body.angular_velocity.length() < 0.1, "Rotation stops without oscillation")
	_check(not body.freeze and body.can_sleep, "Rotated body remains dynamic and sleep-capable")
	Input.action_release("rotate_held")
	_motion(Vector2(20, -10))
	_check(not camera_before.is_equal_approx(_player.camera.global_basis), "Releasing R immediately restores camera look")
	await _steps(60)
	_check(expected.angle_to(body.global_basis.get_rotation_quaternion()) < 0.04,
		"Chosen orientation is retained after releasing R")
	Input.action_press("rotate_held")
	_motion(Vector2(30, 20))
	await _steps(3)
	var linear := body.linear_velocity
	var angular := body.angular_velocity
	_grabber.release()
	_check(body.linear_velocity.is_equal_approx(linear) and body.angular_velocity.is_equal_approx(angular),
		"Drop preserves linear and angular momentum")
	_check(is_equal_approx(body.angular_damp, 0.4), "Drop restores original damping")
	Input.action_release("rotate_held")
	await _steps(600)
	_check(body.sleeping, "Rotated and dropped prop returns to sleep")
	body.queue_free()
	await _steps(2)


func _test_distance() -> void:
	_reset_player()
	var body := _spawn_prop(12.0)
	await _steps(1)
	_grabber.try_pick_up()
	var initial := _grabber.current_hold_distance
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_check(is_equal_approx(_grabber.current_hold_distance, initial + _grabber.distance_step), "Wheel up moves farther")
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_check(is_equal_approx(_grabber.current_hold_distance, initial), "Wheel down moves closer")
	_wheel(MOUSE_BUTTON_WHEEL_UP, 0.5)
	_check(is_equal_approx(_grabber.current_hold_distance, initial + _grabber.distance_step * 0.5),
		"Fractional wheel input is respected")
	for index in 40:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
	await _steps(150)
	_check(is_equal_approx(_grabber.current_hold_distance, _grabber.max_hold_distance), "Far distance is clamped")
	_check(absf(body.global_position.distance_to(_player.camera.global_position) - _grabber.max_hold_distance) < 0.15,
		"Heavy prop reaches far hold distance")
	for index in 40:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _steps(150)
	_check(is_equal_approx(_grabber.current_hold_distance, _grabber.min_hold_distance), "Near distance is clamped")
	_check(absf(body.global_position.distance_to(_player.camera.global_position) - _grabber.min_hold_distance) < 0.15,
		"Heavy prop settles at near hold distance")
	_check(_grabber.held_body == body and body.linear_velocity.length() < 0.3, "Distance changes remain stable")
	var stats := _room.get_node("DebugOverlay/Stats") as Label
	_check(stats.text.contains("Hold distance:"), "Debug overlay reports hold distance")
	Input.action_press("rotate_held")
	_motion(Vector2(35, 0))
	await _steps(3)
	var speed_before := body.linear_velocity
	_grabber.release(true)
	await _steps(2)
	_check(body.linear_velocity.z < speed_before.z - 0.5, "Throw still works during rotation at minimum distance")
	Input.action_release("rotate_held")
	body.queue_free()
	await _steps(2)


func _test_contact() -> void:
	_reset_player()
	var body := _spawn_prop(2.0)
	await _steps(1)
	_grabber.try_pick_up()
	await _steps(60)
	var barrier := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 2, 2)
	collision.shape = shape
	barrier.add_child(collision)
	_room.add_child(barrier)
	barrier.global_position = body.global_position + Vector3(0.48, 0, 0)
	var charge_event := InputEventMouseButton.new()
	charge_event.button_index = MOUSE_BUTTON_LEFT
	charge_event.pressed = true
	root.push_input(charge_event, true)
	Input.action_press("rotate_held")
	for index in 60:
		_motion(Vector2(40, 10))
		await _steps(1)
	_check(body.angular_velocity.length() < 8.0, "Repeated rotation into furniture has bounded speed")
	Input.action_release("rotate_held")
	await _steps(150)
	_check(_grabber.held_body == body and body.linear_velocity.length() < 0.3, "Rotating contact settles while held")
	_check(_grabber.is_charging_throw and is_equal_approx(_grabber.throw_charge, 1.0),
		"Furniture contact during charge stays held and clamps charge")
	var bounds := AABB(Vector3.ONE * -0.3, Vector3.ONE * 0.6)
	var furthest_x: float = -INF
	for corner in 8:
		furthest_x = maxf(furthest_x, (body.global_transform * bounds.get_endpoint(corner)).x)
	_check(furthest_x < barrier.position.x - 0.1 + 0.03, "Rotation respects furniture collision")
	_check(_player.velocity.length() < 0.1 and absf(_player.position.y) < 0.05,
		"Held-object contact does not launch player")
	_grabber.release()
	charge_event.pressed = false
	root.push_input(charge_event, true)
	barrier.queue_free()
	body.queue_free()
	await _steps(2)


func _test_clearance() -> void:
	_reset_player()
	var large := _spawn_prop(5.0)
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 1.1
	(large.get_node("Collision") as CollisionShape3D).shape = shape
	await _steps(1)
	_grabber.try_pick_up()
	for index in 40:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _steps(120)
	_check(_grabber.current_hold_distance > _grabber.min_hold_distance + 0.2,
		"Large props have a larger minimum distance")
	_check(_grabber.held_body == large, "Large prop remains usable at safe near distance")
	_player.camera.rotation.x = deg_to_rad(-85)
	await _steps(2)
	_check(not is_instance_valid(_grabber.held_body), "Unsafe downward target releases instead of entering player")
	large.queue_free()
	await _steps(2)
	_reset_player()
	_player.position.z = -3.3
	var cramped := _spawn_prop(2.0, 1.0)
	await _steps(1)
	_grabber.try_pick_up()
	await _steps(3)
	_check(not is_instance_valid(_grabber.held_body), "Close wall releases instead of pulling prop into player")
	cramped.queue_free()
	await _steps(2)
	_reset_player()
	var near := _spawn_prop(2.0)
	await _steps(1)
	_grabber.try_pick_up()
	for index in 40:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _steps(120)
	_player.rotation.y = PI
	await _steps(2)
	_check(not is_instance_valid(_grabber.held_body), "Turning past near prop releases instead of pulling through player")
	near.queue_free()
	await _steps(2)
	_reset_player()
	var focused := _spawn_prop(2.0)
	await _steps(1)
	_grabber.try_pick_up()
	Input.action_press("rotate_held")
	_motion(Vector2(40, 0))
	_player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _steps(2)
	_check(not _player.mouse_captured and not is_instance_valid(_grabber.held_body),
		"Focus loss during rotation releases cursor and object")
	Input.action_release("rotate_held")
	_player.set_mouse_captured(true)
	focused.queue_free()
	await _steps(2)


func _reset_player(yaw: float = 0.0, pitch: float = 0.0) -> void:
	_player.position = Vector3(0, 0.02, 3.25)
	_player.rotation = Vector3(0, yaw, 0)
	_player.camera.rotation = Vector3(pitch, 0, 0)
	_player.velocity = Vector3.ZERO


func _spawn_prop(test_mass: float, distance: float = 2.0) -> RigidBody3D:
	var body := PROP.instantiate() as RigidBody3D
	body.mass = test_mass
	_room.add_child(body)
	body.global_position = _player.camera.global_position - _player.camera.global_basis.z * distance
	return body


func _motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	root.push_input(event, true)


func _wheel(button: MouseButton, factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.factor = factor
	root.push_input(event, true)


func _steps(count: int) -> void:
	for index in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
