extends "res://tests/pickup_overlap_smoke.gd"

var _planning_times: Array[int] = []

func _run() -> void:
	_render = OS.get_cmdline_user_args().has("--render")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_label = arg.trim_prefix("--output=").validate_filename()
	_clock = Clock.new()
	_clock.process_mode = Node.PROCESS_MODE_ALWAYS
	_clock.process_physics_priority = 200
	root.add_child(_clock)
	for stance in 3:
		await _door_case(stance)
	await _prone_hold_limit()
	await _vertical_case(false)
	await _vertical_case(true)
	_check(Engine.physics_ticks_per_second == 60, "Physics remains at 60 Hz")
	var file := FileAccess.open("res://.validation/pickup_tight_%s.json" % _label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures,
		"planning_us": _planning_times, "results": _results}, "\t"))
	print("PICKUP TIGHT: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _stance(value: int) -> void:
	_player.stance = value
	_player.body_shape.shape.radius = _player.RADII[value]
	_player.body_shape.shape.height = _player.HEIGHTS[value]
	_player.body_shape.position.y = _player.HEIGHTS[value] * 0.5
	_player.camera.position.y = _player.EYE_HEIGHTS[value]

func _preview() -> Dictionary:
	var start := Time.get_ticks_usec()
	var result := _grabber.get_pickup_diagnostics()
	_planning_times.append(Time.get_ticks_usec() - start)
	return result

func _door_case(stance: int) -> void:
	await _setup()
	_stance(stance)
	var body: RigidBody3D = _world.get_node("MovableProps/Monitor")
	body.rotation = Vector3(0, 0, PI / 2)
	body.position = Vector3(1.4, 0.332, 2.16)
	_player.position = Vector3(1.9, 0.02, 2.04) if stance == 2 else Vector3(1.5, 0.02, 1.695)
	await _clock.tick
	_player.camera.look_at(body.to_global(Vector3(0, 0.305, 0) if stance == 2 else Vector3(-0.32, 0.05, 0)))
	_player.visual_camera.reset_interpolation()
	body.freeze = false
	var before := _preview()
	var bounds := _grabber._get_hold_bounds(body)
	var world := _grabber._world_contact(body, bounds.shapes, body.global_transform)
	_check(before.body_id == body.get_instance_id() and before.eligible, "Door monitor stance %d: reachable full hull is pickable" % stance)
	_check(not before.player_overlap and world.depths.is_empty(), "Door monitor has no actual player or world penetration")
	if stance == 0:
		_check(absf(before.surface_distance - 1.247) < 0.002 and before.padded_overlap and before.target_overlap,
			"Reproduces 1.247 m / zero penetration / padding / unsafe preferred target")
		var outward := body.to_global(bounds.center) - _player.global_position
		outward.y = 0
		var blockers: Array[String] = []
		for entry in bounds.shapes:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = entry.shape
			query.transform = body.global_transform * entry.transform
			query.transform.origin += outward.normalized() * 0.025
			query.margin = 0
			query.collision_mask = 1 | 4
			query.exclude = [body.get_rid(), _player.get_rid()]
			for hit in body.get_world_3d().direct_space_state.intersect_shape(query):
				var owner: int = hit.collider.shape_find_owner(hit.shape)
				blockers.append(String(hit.collider.shape_owner_get_owner(owner).name))
		before["outward_blockers"] = blockers
		_check("SouthLeftCollision" in blockers, "The full hull's outward target enters the wall beside the door")
		_check(before.recovery_direction == "right" and before.recovery_candidates == 4,
			"Door-side wall blocks outward paths; fourth candidate provides a lateral exit")
	if _render and stance == 0:
		await _capture("tight_door_before")
	await _exercise(body, before, true, "door_stance_%d" % stance)
	if _render and stance == 0:
		await _capture("tight_door_after")
	if is_instance_valid(_grabber.held_body):
		await _release_check(body, stance == 0, -0.04 if stance == 2 else 0.04)
	await _cleanup()

func _release_check(body: RigidBody3D, throw_body: bool, yaw: float) -> void:
	var start := _player.camera.global_basis.get_rotation_quaternion()
	var finish := (Basis(Vector3.UP, yaw) * _player.camera.global_basis).get_rotation_quaternion()
	for tick in 12:
		_player.camera.global_basis = Basis(start.slerp(finish, (tick + 1) / 12.0))
		await _clock.tick
	_check(_grabber.held_body == body, "Small camera motion after recovery keeps the original body held")
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT if throw_body else MOUSE_BUTTON_RIGHT
	button.pressed = true
	root.push_input(button, true)
	if throw_body:
		await _seconds(0.25)
	button.pressed = false
	root.push_input(button, true)
	await _clock.tick
	_check(_grabber.held_body == null and _grabber.last_release.reason == (&"throw" if throw_body else &"rmb_drop"),
		"Native charged throw / RMB drop still works after recovery")

func _prone_hold_limit() -> void:
	# At this low, frontal angle the ordinary wall-shortened hold is unsafe.
	# Padding recovery must not bypass the separate existing target guard.
	await _setup()
	_stance(2)
	var body: RigidBody3D = _world.get_node("MovableProps/Monitor")
	body.rotation = Vector3(0, 0, PI / 2)
	body.position = Vector3(1.4, 0.332, 2.16)
	_player.position = Vector3(1.5, 0.02, 1.695)
	await _clock.tick
	_player.camera.look_at(body.to_global(Vector3(0, 0.05, 0)))
	_player.visual_camera.reset_interpolation()
	body.freeze = false
	var press := InputEventKey.new()
	press.physical_keycode = KEY_E
	press.pressed = true
	root.push_input(press, true)
	await _clock.tick
	press.pressed = false
	root.push_input(press, true)
	_check(_grabber.held_body == null and _grabber.last_release.get("reason") == &"no_target_clearance",
		"Prone frontal wall-shortened target still rejects with its actual clearance reason")
	_results.append({"case": "prone_unsafe_hold_target", "release": _grabber.last_release.duplicate(true)})
	await _cleanup()

func _vertical_case(trapped: bool) -> void:
	await _setup()
	_stance(1)
	var body: RigidBody3D = _world.get_node("MovableProps/MovingBoxA")
	body.position = Vector3(0, 0.7, 0)
	_player.position = Vector3(0.56, 0.02, 0)
	_box(Vector3(0, 0.255, 0), Vector3(0.48, 0.51, 0.42), "Support")
	_box(Vector3(-0.28, 0.4, 0), Vector3(0.04, 0.8, 0.5), "BackLip")
	_box(Vector3(0, 0.4, -0.25), Vector3(0.52, 0.8, 0.04), "SideLipA")
	_box(Vector3(0, 0.4, 0.25), Vector3(0.52, 0.8, 0.04), "SideLipB")
	if trapped:
		_box(Vector3(0, 0.95, 0), Vector3(0.6, 0.04, 0.6), "SolidLid")
	await _clock.tick
	_player.camera.look_at(body.to_global(Vector3(0.18, 0.17, 0)))
	_player.visual_camera.reset_interpolation()
	body.freeze = false
	var before := _preview()
	_check(before.body_id == body.get_instance_id() and before.padded_overlap,
		"Elevated box uses full authored shape with padded proximity")
	if trapped:
		_check(not before.eligible and before.recovery_rejection == "no_safe_recovery_path" and before.recovery_candidates == 7,
			"Solid lips and lid reject all seven recovery paths accurately")
	else:
		_check(before.eligible and before.recovery_direction == "up",
			"Low furniture lips permit the seventh, upward recovery path")
	if _render:
		await _capture("tight_trapped" if trapped else "tight_up_before")
	await _exercise(body, before, not trapped, "trapped" if trapped else "upward")
	if _render and not trapped:
		await _capture("tight_up_after")
	await _cleanup()
