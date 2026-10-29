extends SceneTree

var _world: Node3D
var _player: SandboxPlayer
var _grabber: PhysicsGrabber
var _clock: Clock
var _checks := 0
var _failures := 0
var _render := false
var _label := "run"
var _results: Array[Dictionary] = []

class Clock extends Node:
	signal tick
	signal frame
	var seconds := 0.0
	func _physics_process(delta: float) -> void:
		seconds += delta
		tick.emit()
	func _process(_delta: float) -> void:
		frame.emit()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_render = OS.get_cmdline_user_args().has("--render")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_label = arg.trim_prefix("--output=").validate_filename()
	_clock = Clock.new()
	_clock.process_mode = Node.PROCESS_MODE_ALWAYS
	_clock.process_physics_priority = 200
	root.add_child(_clock)
	_check(Engine.physics_ticks_per_second == 60, "Physics remains 60 Hz")
	for old_tuning in [false, true]:
		await _desk_case(old_tuning)
	# Keep these stability fixtures accessible under the 1.6 m surface reach.
	for distance in [1.0, 1.25, 1.5]:
		await _open_case(distance)
	await _collision_case()
	var file := FileAccess.open("res://.validation/held_distance_%s.json" % _label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures,
		"physics_hz": Engine.physics_ticks_per_second, "results": _results}, "\t"))
	print("HELD DISTANCE: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _setup(desk: bool) -> RigidBody3D:
	_world = load("res://scenes/gamers_room.tscn").instantiate() if desk else Node3D.new()
	root.add_child(_world)
	if desk:
		_player = _world.get_node("Player")
	else:
		_box(Vector3(0, -0.15, 0), Vector3(24, 0.3, 24))
		_player = load("res://scenes/player.tscn").instantiate()
		_world.add_child(_player)
	_player.set_physics_process(false) # Isolate mouse-look from translation/stance.
	_grabber = _player.get_node("Grabber")
	await _seconds(0.25)
	var monitor: RigidBody3D
	if desk:
		monitor = _world.get_node("MovableProps/Monitor")
		_player.position = Vector3(0, 0.02, -1.2)
	else:
		monitor = load("res://scenes/props/gamer_monitor.tscn").instantiate()
		monitor.position = Vector3(0, 1.295, -1.25)
		_world.add_child(monitor)
		_player.position = Vector3.ZERO
	_grabber._cache_hold_bounds(monitor)
	return monitor

func _pickup(body: RigidBody3D, screen: bool = false) -> float:
	_player.camera.look_at(body.global_position + Vector3.UP * 0.43 if screen else body.to_global(_grabber._held_center))
	_player.visual_camera.reset_interpolation()
	await _clock.frame
	var distance := _player.camera.global_position.distance_to(body.to_global(_grabber._held_center))
	_grabber.try_pick_up()
	_check(_grabber.held_body == body, "Monitor pickup uses the normal sight ray")
	var expected := clampf(minf(_grabber.hold_distance, distance), _grabber._minimum_distance, _grabber.max_hold_distance)
	_check(is_equal_approx(_grabber.current_hold_distance, expected), "Initial request respects pickup distance and existing safety/preferred bounds")
	_check(_grabber._held_center.is_equal_approx(Vector3(0, 0.305, 0)), "Monitor uses its stable collision centre, not its foot pivot or ray-hit point")
	return distance

func _desk_case(old_tuning: bool) -> void:
	var body := await _setup(true)
	if old_tuning:
		_grabber.spring_strength = 45
		_grabber.spring_damping = 12
	var pickup := await _pickup(body, true)
	var requested := _grabber.current_hold_distance
	var sample := {"case": "desk_old" if old_tuning else "desk_current", "pickup": pickup,
		"requested": requested, "frames": []}
	var constant := true
	var contacts := 0
	var max_visual_offset := 0.0
	var start := _clock.seconds
	while _clock.seconds - start < 2.0 - 0.00001:
		await _clock.tick
		var t := _clock.seconds - start
		if t > 0.1 and t < 0.7:
			# Lift and yaw away from the desk, using normal immediate mouse input.
			_look(-0.6 / 60.0, 0.35 / 60.0)
		constant = constant and is_equal_approx(_grabber.current_hold_distance, requested)
		if _grabber.held_body != body:
			continue
		var state := _grabber.get_hold_diagnostics()
		contacts += int(state.solver_contacts > 0)
		max_visual_offset = maxf(max_visual_offset, absf(state.actual_distance - state.visual_distance))
		sample.frames.append(state)
	_check(constant and _grabber.held_body == body, "Desk yaw/pitch retains the original request without wheel input")
	var final := _grabber.get_hold_diagnostics()
	_check(not final.is_empty() and absf(final.get("actual_distance", INF) - requested) < 0.035,
		"Monitor returns to pickup distance after clearing desk under both spring tunings")
	_check(contacts > 0 and not final.is_empty() and final.solver_contacts == 0,
		"Desk fixture starts with physical contact and clears it while held")
	sample["contact_ticks"] = contacts
	sample["max_visual_offset"] = max_visual_offset
	sample["final"] = final
	_results.append(sample)
	print("DESK old=", old_tuning, " pickup=", pickup, " final=", final.get("actual_distance"), " contact_ticks=", contacts)
	if _render and not old_tuning:
		var hud: CanvasLayer = _world.get_node("DebugOverlay")
		hud.debug_visible = true
		hud.get_node("Stats").show()
		hud._update_stats()
		await _clock.frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.validation/held_distance_desk.png")
	await _cleanup()

func _open_case(distance: float) -> void:
	var body := await _setup(false)
	body.position = Vector3(0, 1.295, -distance)
	var pickup := await _pickup(body)
	var requested := _grabber.current_hold_distance
	await _seconds(0.8)
	var constant := true
	var start := _clock.seconds
	var max_error := 0.0
	while _clock.seconds - start < 1.0 - 0.00001:
		await _clock.tick
		var t := _clock.seconds - start
		# Rapid yaw + pitch; same 60-Hz input trajectory at every rendering FPS.
		_look(cos(t * 7.0) * 0.3 * 7.0 / 60.0, cos(t * 9.0) * 0.18 * 9.0 / 60.0)
		constant = constant and is_equal_approx(_grabber.current_hold_distance, requested)
		max_error = maxf(max_error, absf(_player.camera.global_position.distance_to(body.to_global(_grabber._held_center)) - requested))
	await _seconds(1.0)
	var state := _grabber.get_hold_diagnostics()
	_check(constant and _grabber.held_body == body, "Rapid yaw/pitch never changes the requested distance")
	_check(not state.is_empty() and absf(state.actual_distance - requested) < 0.035 and body.linear_velocity.length() < 0.1,
		"Inertial motion settles at the original requested radius")
	_check(not state.is_empty() and absf(state.actual_distance - state.visual_distance) < 0.005,
		"Visual and physical monitor distances agree after settling")
	var before := body.global_transform
	_look(0.03, 0.02)
	_check(body.global_transform == before, "Mouse-look never directly moves a rigid-body transform")
	var camera_basis := _player.camera.global_basis
	var initial_rotation := body.global_basis.get_rotation_quaternion()
	Input.action_press("rotate_held")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, -15)
	_grabber._unhandled_input(motion)
	Input.action_release("rotate_held")
	await _seconds(0.9)
	_check(camera_basis.is_equal_approx(_player.camera.global_basis)
		and initial_rotation.angle_to(body.global_basis.get_rotation_quaternion()) > 0.1
		and is_equal_approx(_grabber.current_hold_distance, requested), "R rotation changes orientation while preserving camera and requested distance")
	_wheel(MOUSE_BUTTON_WHEEL_UP, 0.5)
	_check(is_equal_approx(_grabber.current_hold_distance, requested + _grabber.distance_step * 0.5), "Fractional wheel input increases the request")
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.5)
	_check(is_equal_approx(_grabber.current_hold_distance, requested), "Wheel returns to the prior request")
	_results.append({"case": "open", "pickup": pickup, "requested": requested,
		"max_transient_radial_error": max_error, "settled": state})
	_grabber.release(true, 0.4)
	_check(body.linear_velocity.dot(-_player.camera.global_basis.z) > 1.0 and body.angular_velocity.length() <= _grabber.max_throw_spin + 0.001,
		"Throw retains forward velocity and bounded tumble")
	await _cleanup()

func _collision_case() -> void:
	var body := await _setup(false)
	await _pickup(body)
	await _seconds(0.7)
	var wall := _box(Vector3(0, 1.5, -2.05), Vector3(4, 3, 0.1))
	for step in 5:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
	var requested := _grabber.current_hold_distance
	await _seconds(0.8)
	var blocked := _grabber.get_hold_diagnostics()
	_check(_grabber.held_body == body and not blocked.is_empty() and blocked.clearance_collider != "none"
		and blocked.target_distance < requested - 0.2 and blocked.actual_distance < requested - 0.2,
		"Wall clearance temporarily shortens physical target without changing the request")
	wall.queue_free()
	await _seconds(1.0)
	var clear := _grabber.get_hold_diagnostics()
	_check(_grabber.held_body == body and is_equal_approx(_grabber.current_hold_distance, requested)
		and absf(clear.actual_distance - requested) < 0.035 and clear.clearance_collider == "none",
		"Removing obstruction returns to the same request without a distance ratchet")
	_check(not _grabber._overlaps_player(body), "Close-held monitor stays outside player collision bounds")
	_results.append({"case": "wall", "blocked": blocked, "clear": clear})
	await _cleanup()

func _look(yaw: float, pitch: float) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(-yaw, -pitch) / _player.mouse_sensitivity
	_player._unhandled_input(motion)

func _wheel(button: MouseButton, factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.factor = factor
	event.pressed = true
	_grabber._unhandled_input(event)

func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	_world.add_child(body)
	return body

func _cleanup() -> void:
	_grabber.release()
	_world.queue_free()
	await _clock.frame
	await _clock.frame

func _seconds(duration: float) -> void:
	var start := _clock.seconds
	while _clock.seconds - start < duration - 0.00001:
		await _clock.tick

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
