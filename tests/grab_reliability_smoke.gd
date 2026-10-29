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
	_check(Engine.physics_ticks_per_second == 60 and not ProjectSettings.get_setting("physics/common/physics_interpolation"),
		"Physics stays 60 Hz with global interpolation disabled")
	for origin: Vector3 in [Vector3(-0.45, 0.02, -0.9), Vector3(0, 0.02, -0.9), Vector3(0, 0.02, -1.2)]:
		for lift_seconds in [0.2, 0.8]:
			await _room_lift("MovableProps/GlassBottle", origin, lift_seconds)
	# Prove the release fix independently of the shorter hold/minimum tuning.
	await _room_lift("MovableProps/GlassBottle", Vector3(-0.45, 0.02, -0.9), 0.2, true)
	await _room_lift("MovableProps/Monitor", Vector3(0, 0.02, -1.2), 0.4)
	await _room_lift("Furniture/Chair", Vector3(0.2, 0.02, -0.3), 0.8)
	await _reach_and_occlusion()
	await _stance_cases()
	await _wheel_and_inputs()
	await _safety_cases()
	await _menu_cycles()
	var file := FileAccess.open("res://.validation/grab_reliability_%s.json" % _label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures, "results": _results}, "\t"))
	print("GRAB RELIABILITY: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _setup(room: bool = false) -> void:
	_world = load("res://scenes/gamers_room.tscn").instantiate() if room else Node3D.new()
	root.add_child(_world)
	if room:
		_player = _world.get_node("Player")
	else:
		_box(Vector3(0, -0.1, 0), Vector3(24, 0.2, 24))
		_player = load("res://scenes/player.tscn").instantiate()
		_world.add_child(_player)
	_grabber = _player.get_node("Grabber")
	_grabber.log_release_reasons = true
	await _seconds(0.3)
	_player.set_physics_process(false)
	_player.camera.rotation = Vector3.ZERO

func _room_lift(path: String, origin: Vector3, duration: float, legacy: bool = false) -> void:
	await _setup(true)
	var body: RigidBody3D = _world.get_node(path)
	_player.position = origin
	var aim := body.to_global(Vector3(0, 0.79, 0.21)) if path.ends_with("Chair") \
		else body.global_position + Vector3.UP * (0.43 if path.ends_with("Monitor") else 0.1)
	_player.camera.look_at(aim)
	_player.visual_camera.reset_interpolation()
	await _clock.frame
	if legacy:
		_grabber.hold_distance = 2
		_grabber.min_hold_distance = 1.1
	var initial := body.global_transform
	_grabber.try_pick_up()
	_check(_grabber.held_body == body, "Accessible room pickup: %s at %s" % [path, origin])
	_check(body.global_transform == initial, "Pickup never snaps the body transform")
	var requested := _grabber.current_hold_distance
	var safe := true
	var held := true
	var depth := 0.0
	var start := _clock.seconds
	var applied := 0.0
	var samples: Array[Dictionary] = []
	while _clock.seconds - start < 1.5 - 0.00001:
		await _clock.tick
		var progress := minf((_clock.seconds - start) / duration, 1)
		var change := progress - applied
		_look(-change * 0.25 if path.ends_with("Monitor") else 0.0, change * 0.65)
		applied = progress
		held = held and _grabber.held_body == body
		if _grabber.held_body == body:
			var state := _grabber.get_hold_diagnostics()
			safe = safe and not state.player_overlap and is_equal_approx(state.requested_distance, requested)
			depth = maxf(depth, _penetration(body))
			samples.append(state)
	_check(held and _grabber.last_release.is_empty(), "Slow/fast lift stays held without a safety release")
	_check(safe and depth < 0.04, "Lift retains player clearance and respects room collisions")
	_check(body.global_position.y > initial.origin.y + 0.2, "Physical body lifts rather than visually falling")
	var final := _grabber.get_hold_diagnostics()
	_check(not final.is_empty() and absf(final.actual_distance - final.visual_distance) < 0.015,
		"Physical and displayed distances agree after the lift")
	_results.append({"case": path, "origin": str(origin), "duration": duration, "legacy": legacy,
		"requested": requested, "max_penetration": depth, "samples": samples, "release": _grabber.last_release})
	if _render and (legacy or not path.ends_with("GlassBottle")):
		var hud: CanvasLayer = _world.get_node("DebugOverlay")
		hud.debug_visible = true
		hud.get_node("Stats").show()
		hud._update_stats()
		await _clock.frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.validation/grab_%s.png" % body.name)
	await _cleanup()

func _reach_and_occlusion() -> void:
	await _setup()
	_check(is_equal_approx(_grabber.reach, 1.6) and is_equal_approx(_grabber.hold_distance, 1.0), "New pickup reach and comfortable distance are 1.6/1.0 m")
	for surface_distance in [1.59, 1.61]:
		var body := _prop("res://scenes/props/physics_prop.tscn", Vector3(0, 1.6, -surface_distance - 0.3))
		body.gravity_scale = 0
		await _clock.frame
		var hit := _grabber.get_aim_hit(_grabber.reach)
		_grabber.try_pick_up()
		_check((_grabber.held_body == body) == (surface_distance < _grabber.reach), "Pickup boundary uses accessible surface at %.2f m" % surface_distance)
		if _grabber.held_body == body:
			_check(_player.camera.global_position.distance_to(body.global_position) > _grabber.reach
				and absf(_player.camera.global_position.distance_to(hit.position) - surface_distance) < 0.002,
				"Surface can be reachable while the body centre is beyond reach")
			await _seconds(0.7)
			_check(absf(_grabber.get_hold_diagnostics().actual_distance - 1.0) < 0.035, "Ordinary prop pulls smoothly to 1 m")
		_grabber.release()
		body.queue_free()
		await _clock.frame
	var hidden := _prop("res://scenes/props/physics_prop.tscn", Vector3(0, 1.6, -1.4))
	hidden.gravity_scale = 0
	var furniture := _box(Vector3(0, 1.4, -0.8), Vector3(2, 2.8, 0.12))
	await _clock.frame
	_grabber.try_pick_up()
	_check(_grabber.held_body == null and _grabber.get_aim_hit(_grabber.reach).get("collider") == furniture,
		"First furniture/wall surface blocks pickup of an occluded prop")
	await _cleanup()

func _stance_cases() -> void:
	await _setup()
	_player.set_physics_process(true)
	for stance in 3:
		if stance == SandboxPlayer.Stance.CROUCHING:
			Input.action_press("crouch")
		elif stance == SandboxPlayer.Stance.PRONE:
			Input.action_release("crouch")
			var prone := InputEventAction.new()
			prone.action = "toggle_prone"
			prone.pressed = true
			_player._unhandled_input(prone)
		await _seconds(0.5)
		_player.camera.rotation = Vector3.ZERO
		var body := _prop("res://scenes/props/glass_prop.tscn", _player.camera.global_position - Vector3(0, 0, 1.4))
		body.gravity_scale = 0
		await _clock.frame
		_grabber.try_pick_up()
		await _seconds(0.5)
		_check(_player.stance == stance and _grabber.held_body == body, "Short-reach pickup/hold works in stance %d" % stance)
		_grabber.release()
		body.queue_free()
		await _clock.frame
	Input.action_release("crouch")
	await _cleanup()

func _wheel_and_inputs() -> void:
	await _setup()
	var body := _prop("res://scenes/props/physics_prop.tscn", Vector3(0, 1.6, -1.4))
	_grabber.try_pick_up()
	await _seconds(0.5)
	var request := _grabber.current_hold_distance
	var constant := true
	for tick in 60:
		_look(cos(tick / 60.0 * 8.0) * 0.03, cos(tick / 60.0 * 11.0) * 0.02)
		await _clock.tick
		constant = constant and is_equal_approx(request, _grabber.current_hold_distance)
	_check(constant and _grabber.held_body == body, "Rapid yaw/pitch retains held body and request")
	var basis := _player.camera.global_basis
	var rotation := body.global_basis.get_rotation_quaternion()
	Input.action_press("rotate_held")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, -15)
	_grabber._unhandled_input(motion)
	Input.action_release("rotate_held")
	await _seconds(0.6)
	_check(basis.is_equal_approx(_player.camera.global_basis) and rotation.angle_to(body.global_basis.get_rotation_quaternion()) > 0.1,
		"R rotation consumes mouse motion and rotates the physical prop")
	for tick in 40:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
	await _seconds(1.0)
	_check(is_equal_approx(_grabber.current_hold_distance, _grabber.max_hold_distance), "Wheel remains clamped at its maximum")
	for tick in 40:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _seconds(1.0)
	_check(is_equal_approx(_grabber.current_hold_distance, _grabber._minimum_distance)
		and _grabber.held_body == body and not _grabber._overlaps_player(body), "Near wheel limit respects size/player safety")
	_action("interact", true)
	await _seconds(0.05)
	_check(_grabber.held_body == null and _grabber.last_release.reason == &"interact_drop", "E drop records its exact intentional release reason")
	_grabber.try_pick_up()
	_action("drop_object", true)
	_check(_grabber.held_body == null and _grabber.last_release.reason == &"rmb_drop", "RMB drop records its exact intentional release reason")
	_grabber.try_pick_up()
	_action("throw_object", true)
	await _seconds(0.4)
	_check(_grabber.is_charging_throw, "Throw charge remains active while holding")
	_action("throw_object", false)
	await _seconds(0.05)
	_check(_grabber.held_body == null and _grabber.last_release.reason == &"throw" and body.linear_velocity.length() > 2,
		"Charged release physically throws and records throw reason")
	await _cleanup()

func _safety_cases() -> void:
	await _setup()
	var body := _prop("res://scenes/props/glass_prop.tscn", Vector3(0, 1.6, -1.4))
	_grabber.try_pick_up()
	await _seconds(0.5)
	_player.rotation.y = PI
	await _seconds(0.05)
	_check(_grabber.held_body == null and _grabber.last_release.reason == &"body_behind_camera", "Unsafe turn still releases instead of dragging the prop through the player")
	body.queue_free()
	await _clock.frame
	_player.rotation = Vector3.ZERO
	body = _prop("res://scenes/props/glass_prop.tscn", Vector3(0, 1.6, -1.4))
	_grabber.try_pick_up()
	await _seconds(0.5)
	_box(Vector3(0, 1.6, -0.6), Vector3(1, 1, 0.1))
	await _seconds(0.5)
	_check(_grabber.held_body == null and _grabber.last_release.reason == &"no_target_clearance",
		"No room between wall and player still triggers a safety release")
	await _cleanup()
	await _setup()
	body = _prop("res://scenes/props/glass_prop.tscn", Vector3(0, 1.6, -1.4))
	_grabber.try_pick_up()
	await _seconds(0.5)
	_box(Vector3(0, 1.6, -0.75), Vector3(1, 1, 0.1))
	await _seconds(0.5)
	_check(_grabber.held_body == null and _grabber.last_release.reason == &"target_overlaps_player",
		"Shape clearance rejects a wall-shortened target inside the player")
	await _cleanup()
	await _setup()
	body = _prop("res://scenes/props/glass_prop.tscn", Vector3(0.6, 1.6, -1.3))
	_player.camera.look_at(body.global_position)
	_player.visual_camera.reset_interpolation()
	_grabber.try_pick_up()
	body.freeze = true # Isolate a genuinely stuck body while the aim target stays clear.
	_player.camera.rotation = Vector3.ZERO
	_box(Vector3(0.3, 1.6, -0.65), Vector3(0.16, 0.8, 0.12))
	await _seconds(0.4)
	_check(_grabber.held_body == null and _grabber.last_release.reason == &"sight_obstructed_timeout",
		"Persistent furniture obstruction retains the existing timed safety release")
	await _cleanup()
	await _setup()
	body = _prop("res://scenes/props/glass_prop.tscn", Vector3(0, 1.6, -1.4))
	_grabber.try_pick_up()
	body.queue_free()
	await _clock.frame
	_check(_grabber.held_body == null and _grabber.last_release.reason == &"body_removed", "Held-body removal records a distinct reason and clears the hold")
	await _cleanup()

func _prop(path: String, position: Vector3) -> RigidBody3D:
	var body: RigidBody3D = load(path).instantiate()
	body.position = position
	_world.add_child(body)
	return body

func _menu_cycles() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _clock.frame
	await _clock.frame
	var menu := current_scene
	menu.play_game()
	for cycle in 2:
		await _seconds(0.3)
		var player: SandboxPlayer = menu.player
		var grabber: PhysicsGrabber = player.get_node("Grabber")
		player.set_physics_process(false)
		player.position = Vector3(-0.45, 0.02, -0.9)
		var bottle: RigidBody3D = menu.room.get_node("MovableProps/GlassBottle")
		player.camera.look_at(bottle.global_position + Vector3.UP * 0.1)
		player.visual_camera.reset_interpolation()
		await _clock.frame
		grabber.try_pick_up()
		_check(grabber.held_body == bottle, "New-reach bottle pickup works before menu restart")
		menu.pause_game()
		_check(paused and grabber.held_body == null and grabber.last_release.reason == &"menu_or_transition",
			"Pause safely drops a held bottle and records the menu release reason")
		await _clock.frame
		menu.resume_game()
		_check(not paused and player.mouse_captured, "Resume restores gameplay and cursor capture")
		menu.pause_game()
		var previous_room: WeakRef = weakref(menu.room)
		menu.play_game()
		await _seconds(0.15)
		_check(previous_room.get_ref() == null and menu.player.get_node("Grabber").held_body == null,
			"Restart clears the old hold and room without stale callbacks")
		menu.pause_game()
		menu.return_to_main()
		await _seconds(0.1)
		_check(menu.room == null and not paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"Returning to Main Menu clears gameplay and releases the cursor")
		menu.play_game()
	await _seconds(0.1)
	menu.return_to_main()
	await _seconds(0.1)

func _look(yaw: float, pitch: float) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(-yaw, -pitch) / _player.mouse_sensitivity
	_player._unhandled_input(motion)

func _wheel(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	_grabber._unhandled_input(event)

func _action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	_grabber._unhandled_input(event)

func _penetration(body: RigidBody3D) -> float:
	var depth := 0.0
	for entry in _grabber._held_shapes:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = entry.shape
		query.transform = body.global_transform * entry.transform
		query.collision_mask = 1 | 4
		query.exclude = [body.get_rid(), _player.get_rid()]
		query.margin = 0
		var contacts := body.get_world_3d().direct_space_state.collide_shape(query, 8)
		for index in range(0, contacts.size(), 2):
			depth = maxf(depth, contacts[index].distance_to(contacts[index + 1]))
	return depth

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
