extends SceneTree

const ROOM := preload("res://scenes/gamers_room.tscn")
var _room: Node3D
var _player: SandboxPlayer
var _view: PlayerViewCamera
var _observer: FrameObserver
var _checks: int = 0
var _failures: int = 0
var _render: bool = false
var _timing: Dictionary = {}
var _output_label: String = ""


class FrameObserver extends Node:
	signal frame_observed(delta: float)
	var player: SandboxPlayer
	var mode: String = ""
	var samples: Array[Dictionary] = []
	var elapsed: float = 0.0

	func _process(delta: float) -> void:
		elapsed += delta
		if mode.is_empty():
			frame_observed.emit(delta)
			return
		var view := player.visual_camera
		var center := player.get_viewport().get_visible_rect().size * 0.5
		var reticle: Label = player.get_parent().get_node("DebugOverlay/Crosshair")
		samples.append({"mode": mode, "elapsed": elapsed, "delta": delta, "physics_frame": Engine.get_physics_frames(),
			"fraction": Engine.get_physics_interpolation_fraction(), "time_usec": Time.get_ticks_usec(),
			"view_x": view.global_position.x, "view_y": view.global_position.y, "view_z": view.global_position.z,
			"logic_x": player.camera.global_position.x, "logic_y": player.camera.global_position.y,
			"logic_z": player.camera.global_position.z, "yaw": view.global_rotation.y,
			"rotation_error": maxf((view.global_basis.x - player.camera.global_basis.x).length(),
				maxf((view.global_basis.y - player.camera.global_basis.y).length(), (view.global_basis.z - player.camera.global_basis.z).length())),
			"aim_offset_x": view.aim_screen_offset.x, "aim_offset_y": view.aim_screen_offset.y,
			"reticle_error": (reticle.position + reticle.size * 0.5 - center).length()})
		frame_observed.emit(delta)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output_label = argument.trim_prefix("--output=").validate_filename()
	_render = OS.get_cmdline_user_args().has("--render")
	if _render and OS.get_cmdline_user_args().has("--fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if not _render:
		root.size = Vector2i(1280, 720)
	_room = ROOM.instantiate()
	root.add_child(_room)
	_player = _room.get_node("Player")
	_view = _player.visual_camera
	_observer = FrameObserver.new()
	_observer.player = _player
	_observer.process_priority = 100
	_observer.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_observer)
	_check(Engine.physics_ticks_per_second == 60 and not ProjectSettings.get_setting("physics/common/physics_interpolation"),
		"Physics remains 60 Hz with global interpolation disabled")
	_check(root.get_camera_3d() == _view and _view.top_level, "An independent visual camera renders the room")
	_check(_player.get_node("Grabber").camera == _player.camera and _view.gameplay_camera == _player.camera,
		"Gameplay/interaction camera references are preserved")
	_check(_view.global_position.is_equal_approx(_player.camera.global_position), "Scene entry initializes the eye without a streak")
	await _seconds(1.5)
	_timing["runtime"] = {"physics_tps": Engine.physics_ticks_per_second,
		"global_interpolation": ProjectSettings.get_setting("physics/common/physics_interpolation"),
		"rendered": _render, "viewport_size": str(root.size),
		"vsync_mode": DisplayServer.window_get_vsync_mode() if _render else -1,
		"refresh_hz": DisplayServer.screen_get_refresh_rate() if _render else -1}
	await _test_timing()
	await _test_stances_and_jump()
	await _test_near_aim()
	await _test_clearance()
	await _test_resets()
	Input.action_release("move_forward")
	Input.action_release("move_right")
	_observer.mode = ""
	var rate: float = _timing.walk.measured_fps
	var label := _output_label if not _output_label.is_empty() else "%s_%d" % ["render" if _render else "headless", roundi(rate)]
	var filename := "res://.validation/camera_matrix_%s.json" % label
	var file := FileAccess.open(filename, FileAccess.WRITE)
	file.store_string(JSON.stringify({"timing": _timing, "samples": _observer.samples}, "\t"))
	print("CAMERA SMOOTHNESS: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_timing() -> void:
	for mode: String in ["walk", "look", "walk_look"]:
		Input.action_release("move_forward")
		_player.global_position = Vector3(0.1, 0.02, 1.5)
		_player.velocity = Vector3.ZERO
		_player.rotation = Vector3.ZERO
		_player.camera.rotation = Vector3(-0.14, 0, 0)
		await _seconds(0.2)
		# Compare the same elapsed-time path at every render rate, in a clear aisle.
		if mode.contains("walk"):
			Input.action_press("move_forward")
		_observer.mode = mode
		var started_at := _observer.elapsed
		var rotation_checked := false
		var expected_yaw := _player.rotation.y
		while _observer.elapsed - started_at < 0.5 - 0.000001:
			var delta: float = await _observer.frame_observed
			if mode.contains("look"):
				var before := _view.global_basis
				var motion := InputEventMouseMotion.new()
				motion.relative = Vector2(144.0, 7.2) * delta
				expected_yaw -= motion.relative.x * _player.mouse_sensitivity
				_player._unhandled_input(motion)
				if not rotation_checked:
					_check(not before.is_equal_approx(_view.global_basis)
						and _view.global_basis.is_equal_approx(_player.camera.global_basis),
						"%s: mouse rotation reaches the view in the same input callback" % mode)
					rotation_checked = true
		_observer.mode = ""
		var rows := _observer.samples.filter(func(row: Dictionary) -> bool:
			return row.mode == mode and row.elapsed - started_at >= 0.3 - 0.000001)
		var repeated_logic := 0
		var repeated_view := 0
		var same_tick_view_moves := 0
		var rotation_errors := 0
		var ui_errors := 0
		var steps: Array[float] = []
		var seconds := 0.0
		var max_step_error := 0.0
		var physics_ticks := 0
		for index in range(1, rows.size()):
			var first: Dictionary = rows[index - 1]
			var next: Dictionary = rows[index]
			var view_step := _eye(next, "view").distance_to(_eye(first, "view"))
			if _eye(next, "logic").is_equal_approx(_eye(first, "logic")):
				repeated_logic += 1
			if view_step < 0.000001:
				repeated_view += 1
			elif next.physics_frame == first.physics_frame:
				same_tick_view_moves += 1
			steps.append(view_step)
			seconds += next.delta
			physics_ticks += next.physics_frame - first.physics_frame
			var expected_step: float = _player.move_speed * next.delta if mode.contains("walk") else 0.0
			max_step_error = maxf(max_step_error, absf(view_step - expected_step))
			if next.rotation_error > 0.00001:
				rotation_errors += 1
			if next.reticle_error > 0.001:
				ui_errors += 1
		var step_sum := 0.0
		for step in steps:
			step_sum += step
		var wall_seconds: float = (rows[-1].time_usec - rows[0].time_usec) / 1000000.0
		_timing[mode] = {"pairs": steps.size(), "seconds": seconds, "measured_fps": steps.size() / seconds,
			"wall_fps": steps.size() / maxf(wall_seconds, 0.000001),
			"physics_ticks": physics_ticks, "repeated_logic": repeated_logic,
			"repeated_view": repeated_view, "same_tick_view_moves": same_tick_view_moves,
			"mean_view_step": step_sum / maxf(steps.size(), 1), "view_speed": step_sum / seconds,
			"max_step_error": max_step_error, "rotation_errors": rotation_errors}
		print("TIMING %s: %s" % [mode, JSON.stringify(_timing[mode])])
		_check(absf(physics_ticks - seconds * Engine.physics_ticks_per_second) <= 1.01,
			"%s: physics ticks follow elapsed time independently of render rate" % mode)
		if mode.contains("walk"):
			_check(repeated_view == 0, "%s: the moving view advances on every render frame" % mode)
			_check(max_step_error < _player.move_speed * (seconds / steps.size()) * 0.02 + 0.0002,
				"%s: view displacement follows speed × render delta" % mode)
			_check(absf(step_sum / seconds - _player.move_speed) < 0.05,
				"%s: rendered walking speed is independent of frame rate" % mode)
			if steps.size() / seconds > Engine.physics_ticks_per_second + 0.1:
				_check(same_tick_view_moves > 0, "%s: the view advances between physics ticks at higher FPS" % mode)
		else:
			_check(repeated_view == steps.size(), "Mouse-only look cannot translate the camera")
		if mode.contains("look"):
			_check(absf(_player.rotation.y - expected_yaw) < 0.00001,
				"%s: total mouse rotation uses the same elapsed-time input path" % mode)
		_check(rotation_errors == 0, "%s: orientation has no smoothing or frame delay" % mode)
		_check(ui_errors == 0, "%s: reticle stays fixed at screen centre" % mode)
		await _capture("camera_9a4_" + mode)
	Input.action_release("move_forward")


func _test_stances_and_jump() -> void:
	_player.global_position = Vector3(0.1, 0.02, 1.0)
	_player.velocity = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	await _seconds(0.333333)
	Input.action_press("crouch")
	var old_height := _view.global_position.y
	await _seconds(0.05)
	_check(_view.global_position.y < old_height and _view.global_position.y > _player.camera.global_position.y,
		"Crouch eye height interpolates while the logical eye follows physics")
	await _seconds(0.416667)
	_check(absf(_view.global_position.y - (_player.global_position.y + 0.82)) < 0.001, "Crouch settles at the existing eye height")
	await _capture("camera_9a4_crouch")
	Input.action_release("crouch")
	await _seconds(0.416667)
	var prone := InputEventAction.new()
	prone.action = "toggle_prone"
	prone.pressed = true
	_player._unhandled_input(prone)
	await _seconds(0.416667)
	_check(absf(_view.global_position.y - (_player.global_position.y + 0.28)) < 0.001, "Prone settles at the existing eye height")
	_player.global_position = Vector3(-0.2, 0.02, -0.65)
	_player.rotation.y = PI * 0.5
	_player.camera.rotation.x = 0
	await _seconds(0.2)
	Input.action_press("move_forward")
	await _seconds(0.916667)
	Input.action_release("move_forward")
	_check(_player.global_position.x < -0.65, "Prone traversal beneath the real bed remains available")
	_check(_view.global_position.y < 0.5 and not _eye_embedded(), "Prone view remains clear below the bed")
	await _capture("camera_9a4_prone_under_bed")
	_player.global_position = Vector3(0.1, 0.02, 1.0)
	_player.velocity = Vector3.ZERO
	_player._unhandled_input(prone)
	await _seconds(0.5)
	Input.action_press("jump")
	await _seconds(0.033333)
	Input.action_release("jump")
	_check(_player.velocity.y > 0 and _view.global_position.y > 1.6, "Jump moves the logical and visual eyes without changing jump tuning")
	await _capture("camera_9a4_jump")
	await _seconds(1.666667)
	_check(_player.is_on_floor() and absf(_view.global_position.y - _player.camera.global_position.y) < 0.01,
		"Landing settles without a stale camera offset")


func _test_near_aim() -> void:
	# Keep the authored floor-box surface inside the current 1.6 m pickup reach.
	_player.global_position = Vector3(-0.45, 0.02, 1.25)
	_player.velocity = Vector3.ZERO
	var box: RigidBody3D = _room.get_node("MovableProps/MovingBoxB")
	_player.camera.look_at(box.global_position, Vector3.UP)
	await _seconds(0.05)
	Input.action_press("move_right")
	await _seconds(0.05)
	Input.action_release("move_right")
	var grabber: PhysicsGrabber = _player.get_node("Grabber")
	var hit := grabber.get_aim_hit(grabber.reach)
	_check(hit.get("collider") == box, "Nearby authored box remains the centred gameplay sight target")
	if not hit.is_empty():
		var reticle: Label = _room.get_node("DebugOverlay/Crosshair")
		_check((_view.unproject_position(hit.position) - (reticle.position + reticle.size * 0.5)).length() < 0.5,
			"Fixed near-object reticle aligns with the actual pickup sight ray")
	await _capture("camera_9a4_near_aim")
	grabber.try_pick_up()
	_check(grabber.held_body == box, "Pickup uses the retained gameplay camera")
	_player.camera.look_at(Vector3(-1.7, 1.62, 1.0), Vector3.UP)
	await _seconds(0.583333)
	_check(grabber.held_body == box, "Near-object hold remains stable through a view update")
	# Launch toward the open aisle; a westward throw immediately contacts the nearby wall.
	_player.camera.look_at(Vector3(1.8, 1.62, 1.0), Vector3.UP)
	grabber.release(true, 0.4)
	await _seconds(0.066667)
	_check(grabber.held_body == null and box.linear_velocity.length() > 1.0, "Existing throw still launches the held prop")
	box.queue_free() # End the throw fixture before teleporting into its flight path.
	await _seconds(0.05)
	_player.global_position = Vector3(-0.8, 0.02, 0.67)
	_player.velocity = Vector3.ZERO
	var kick_box: RigidBody3D = _room.get_node("MovableProps/MovingBoxA")
	_player.camera.look_at(kick_box.global_position, Vector3.UP)
	await _seconds(0.05)
	_check(grabber.get_kick_target().get("collider") == kick_box, "Nearby kick target retains its original ray/reach")
	var kick_position := kick_box.global_position
	grabber._kick()
	await _seconds(0.066667)
	_check(kick_box.global_position.distance_to(kick_position) > 0.03, "Existing kick physically moves the authored prop")


func _test_clearance() -> void:
	for point: Vector3 in [Vector3(1.85, 0.02, 0.85), Vector3(0.95, 0.02, -0.9), Vector3(-0.05, 0.02, -1.15)]:
		_player.global_position = point
		_player.velocity = Vector3.ZERO
		_player.rotation.y = -PI * 0.5
		_player.camera.rotation = Vector3.ZERO
		await _seconds(0.2)
		Input.action_press("move_forward")
		var embedded := false
		var ends_at := _observer.elapsed + 0.25
		while _observer.elapsed < ends_at:
			await _observer.frame_observed
			embedded = embedded or _eye_embedded()
		Input.action_release("move_forward")
		_check(not embedded, "Near-plane clearance holds at wall/furniture route %s" % point)
	await _capture("camera_9a4_wall_clearance")
	# Force a presentation-only segment through a thin fixture; leave player physics alone.
	_player.global_position = Vector3(0.1, 0.02, 1.0)
	_player.velocity = Vector3.ZERO
	await _seconds(0.2)
	var obstacle := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.02, 0.4, 0.4)
	collision.shape = shape
	obstacle.add_child(collision)
	_room.add_child(obstacle)
	obstacle.global_position = _player.camera.global_position + Vector3(0.25, 0, 0)
	await _seconds(0.033333)
	var requested := _player.camera.global_position + Vector3(0.5, 0, 0)
	var safe := _view._clear_eye_path(requested)
	_check(safe.x < obstacle.global_position.x - 0.02 and safe.x > _player.camera.global_position.x,
		"Near-plane sweep clips an unsafe visual path before geometry")
	_player.set_physics_process(false)
	obstacle.global_position = _player.camera.global_position + Vector3(0.05, 0, 0)
	await _seconds(0.033333)
	_check(_view._clear_eye_path(requested).is_equal_approx(_player.camera.global_position),
		"A starting overlap cannot bypass the visual clearance guard")
	_player.set_physics_process(true)
	obstacle.queue_free()
	await _seconds(0.05)


func _test_resets() -> void:
	# Previous real throws randomize prop motion; use the authored clear entrance
	# so a teleport cannot start inside a projectile and trigger depenetration.
	_room.queue_free()
	await _seconds(0.05)
	_room = ROOM.instantiate()
	root.add_child(_room)
	_player = _room.get_node("Player")
	_view = _player.visual_camera
	_observer.player = _player
	await _seconds(1.5)
	_player.global_position = Vector3(0.1, 0.02, 1.2)
	_player.velocity = Vector3.ZERO
	await _seconds(0.2)
	Input.action_press("move_forward")
	await _seconds(0.12)
	Input.action_release("move_forward")
	var moving_view := _view.global_transform
	paused = true
	_check(_view.global_transform.is_equal_approx(moving_view), "Pausing mid-stride does not snap the displayed camera")
	await _seconds(0.083)
	paused = false
	_check(_view.global_transform.is_equal_approx(moving_view), "Resume begins at the frozen pose instead of snapping to the physics eye")
	_check(_view._previous_eye.is_equal_approx(_view._current_eye), "Mid-stride resume resets physics history before its short visual transition")
	await _seconds(0.083)
	_player.global_position = Vector3(1.4, 0.02, 1.55)
	await _seconds(0.04)
	_check(_view.global_position.distance_to(_player.camera.global_position) < 0.1,
		"Direct teleport cannot interpolate across the room (only normal sub-tick movement lag remains)")
	_player.global_position += Vector3(0.01, 0, 0)
	_player.visual_camera.reset_if_eye_changed()
	_check(_view.global_position.is_equal_approx(_player.camera.global_position), "Small teleports also reset immediately")
	_player.velocity = Vector3.ZERO
	await _seconds(0.2)
	paused = true
	var frozen := _view.global_transform
	await _seconds(0.117)
	_check(_view.global_transform.is_equal_approx(frozen), "Pause freezes the view after resetting history")
	paused = false
	_check(_view._previous_eye.is_equal_approx(_view._current_eye), "Resume discards stale interpolation endpoints")
	await _seconds(0.05)
	_check(_view.global_position.distance_to(_player.camera.global_position) < 0.02, "Resume does not reuse a pre-pause camera trail")
	var settings := root.get_node("GameSettings")
	settings.update_setting(&"camera_fov", 91.0)
	_check(is_equal_approx(_view.fov, 91.0), "Settings update visual FOV immediately")
	settings.update_setting(&"camera_fov", 75.0)
	_room.queue_free()
	_observer.player = null
	await _seconds(0.05)
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _seconds(0.067)
	var menu := current_scene
	for cycle in 3:
		menu.play_game()
		await _seconds(0.1)
		var player: SandboxPlayer = menu.player
		_check(root.get_camera_3d() == player.visual_camera and player.visual_camera.gameplay_camera == player.camera,
			"Restart cycle %d activates the new room's independent camera" % (cycle + 1))
		menu.pause_game()
		await _seconds(0.04)
		menu.resume_game()
		await _seconds(0.04)
		_check(player.visual_camera.global_position.distance_to(player.camera.global_position) < 0.02,
			"Pause/resume cycle %d resets the new view cleanly" % (cycle + 1))
		menu.return_to_main()
		await _seconds(0.067)


func _eye(row: Dictionary, prefix: String) -> Vector3:
	return Vector3(row[prefix + "_x"], row[prefix + "_y"], row[prefix + "_z"])


func _eye_embedded() -> bool:
	var shape := SphereShape3D.new()
	var viewport_size := root.get_visible_rect().size
	var half_height := _view.near * tan(deg_to_rad(_view.fov * 0.5))
	shape.radius = Vector3(half_height * viewport_size.x / viewport_size.y, half_height, _view.near).length()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, _view.global_position)
	query.collision_mask = 5
	query.exclude = [_player.get_rid()]
	query.margin = 0.001
	return not _room.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _seconds(duration: float) -> void:
	var ends_at := _observer.elapsed + duration
	while _observer.elapsed < ends_at - 0.000001:
		await _observer.frame_observed


func _capture(title: String) -> void:
	if not _render:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.validation/%s_%d.png" % [title, roundi(_timing.walk.measured_fps)])


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
