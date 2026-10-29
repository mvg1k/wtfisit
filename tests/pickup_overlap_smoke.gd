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
	await _box_case("reported_box", Vector3(-1.35, 0.02, 0.67), Vector3(-0.08, 0, 0))
	await _box_case("padding_only", Vector3(-1.3, 0.02, 0.67), Vector3(-0.08, 0, 0))
	await _box_case("shallow_contact", Vector3(-1.85, 0.02, 1.17), Vector3(0.08, 0.19, 0))
	await _box_case("outward_blocked", Vector3(-1.35, 0.02, 0.67), Vector3(-0.08, 0, 0), true)
	await _box_case("under_player", Vector3(-1.85, 0.02, 0.67), Vector3(0, 0.19, 0))
	await _monitor_case(0)
	await _monitor_case(1)
	await _monitor_case(2)
	await _furniture_cases()
	_check(Engine.physics_ticks_per_second == 60 and not ProjectSettings.get_setting("physics/common/physics_interpolation"), "60 Hz physics and interpolation configuration preserved")
	var file := FileAccess.open("res://.validation/pickup_overlap_%s.json" % _label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures, "results": _results}, "\t"))
	print("PICKUP OVERLAP: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _setup() -> void:
	_world = load("res://scenes/gamers_room.tscn").instantiate()
	root.add_child(_world)
	_player = _world.get_node("Player")
	_player.set_physics_process(false)
	_grabber = _player.get_node("Grabber")
	for body: RigidBody3D in get_nodes_in_group("grabbable"):
		body.freeze = true # Arrange exact full-shape contacts without scan-induced pushing.
	await _seconds(0.1)

func _box_case(label: String, origin: Vector3, aim: Vector3, blocked: bool = false) -> void:
	await _setup()
	var body: RigidBody3D = _world.get_node("MovableProps/MovingBoxA")
	_player.position = origin
	await _clock.frame
	if blocked:
		_box(Vector3(-2.15, 0.7, 0.67), Vector3(0.05, 1.4, 1), "EscapeWall")
	_player.camera.look_at(body.to_global(aim))
	_player.visual_camera.reset_interpolation()
	body.freeze = false
	var before := _grabber.get_pickup_diagnostics()
	before["measured_gap"] = _gap(body)
	_check(before.padded_overlap and before.body_id == body.get_instance_id(), label + ": reproduces the old padded-overlap rejection")
	if label == "reported_box":
		_check(absf(before.surface_distance - 1.333) < 0.003 and absf(before.current_depth - 0.04) < 0.001,
			"1.333 m surface reproduction has 40 mm exact penetration")
	if label == "padding_only":
		_check(not before.player_overlap and before.current_depth < 0.0001,
			"Padding-only contact has no exact capsule penetration")
	var safe := label != "under_player" # One blocked direction can now recover laterally.
	_check(before.eligible == safe, label + ": preview distinguishes recoverable and unsafe geometry")
	await _exercise(body, before, safe, label)
	await _cleanup()

func _monitor_case(stance: int) -> void:
	await _setup()
	_player.body_shape.shape.radius = _player.RADII[stance]
	_player.body_shape.shape.height = _player.HEIGHTS[stance]
	_player.body_shape.position.y = _player.HEIGHTS[stance] * 0.5
	_player.camera.position.y = _player.EYE_HEIGHTS[stance]
	_player.stance = stance
	var body: RigidBody3D = _world.get_node("MovableProps/Monitor")
	body.rotation = Vector3(PI / 2, 0, 0)
	body.position = Vector3(0, 0.132, -0.8)
	_player.position = Vector3(0.55 if stance == 0 else -0.318198, 0.02, -0.8 if stance == 0 else -1.118198)
	await _clock.frame
	var aim := Vector3(-0.08, 0.43, 0)
	if stance == 1:
		var best := INF
		for sample in 321:
			var point := Vector3(sample / 1000.0, 0.6, 0)
			_player.camera.look_at(body.to_global(point))
			_player.visual_camera.reset_interpolation()
			var hit := _grabber.get_aim_hit(_grabber.reach)
			if hit.get("collider") == body:
				var error := absf(_player.camera.global_position.distance_to(hit.position) - 1.140)
				if error < best:
					best = error
					aim = point
	_player.camera.look_at(body.to_global(aim))
	_player.visual_camera.reset_interpolation()
	body.freeze = false
	var before := _grabber.get_pickup_diagnostics()
	before["measured_gap"] = _gap(body)
	_check(before.eligible and (before.padded_overlap or stance == 2), "Fallen monitor stance %d has a safe full-shape exit" % stance)
	if stance == 1:
		_check(absf(before.surface_distance - 1.140) < 0.002,
			"Crouched fallen-monitor surface matches 1.140 m evidence")
	await _exercise(body, before, true, "monitor_stance_%d" % stance)
	await _cleanup()

func _furniture_cases() -> void:
	await _setup()
	var body: RigidBody3D = _world.get_node("MovableProps/MovingBoxA")
	body.position = Vector3(-0.75, 0.195, -0.5)
	_player.position = Vector3(-0.2, 0.02, -0.5)
	await _clock.frame
	_player.camera.look_at(body.global_position + Vector3.UP * 0.15)
	_player.visual_camera.reset_interpolation()
	body.freeze = false
	var before := _grabber.get_pickup_diagnostics()
	_check(before.eligible and before.body_id == body.get_instance_id(), "Exposed part of a box partly under the bed is eligible")
	await _exercise(body, before, true, "partly_under_bed")
	await _cleanup()
	await _setup()
	body = _world.get_node("MovableProps/MovingBoxA")
	body.position = Vector3(-1.49, 0.195, -0.5)
	_player.position = Vector3(-0.2, 0.02, -0.5)
	await _clock.frame
	_player.camera.look_at(body.global_position + Vector3.UP * 0.15)
	_player.visual_camera.reset_interpolation()
	body.freeze = false
	before = _grabber.get_pickup_diagnostics()
	_check(not before.eligible and before.aimed_collider == "Bed", "Bed occlusion blocks the hidden object before overlap recovery")
	await _cleanup()

func _gap(body: RigidBody3D) -> float:
	var bounds := _grabber._get_hold_bounds(body)
	if _grabber._player_contact(body, bounds.shapes, body.global_transform).count > 0:
		return 0.0
	var low := 0.0
	var high := 0.06
	for sample in 12:
		var margin := (low + high) * 0.5
		if _grabber._player_contact(body, bounds.shapes, body.global_transform, margin).count > 0:
			high = margin
		else:
			low = margin
	return high

func _exercise(body: RigidBody3D, before: Dictionary, safe: bool, label: String) -> void:
	var snapshot := {"case": label, "before": before, "player_pose": str(_player.body_shape.global_transform),
		"capsule_radius": _player.body_shape.shape.radius, "capsule_height": _player.body_shape.shape.height,
		"body_pose": str(body.global_transform), "samples": []}
	if _render and label in ["reported_box", "monitor_stance_1"]:
		await _capture(label + "_before")
		# Read the live pose again after the paused render capture.
		before = _grabber.get_pickup_diagnostics()
	var attempts := _grabber.pickup_attempts
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	root.push_input(event, true)
	await _clock.tick
	event.pressed = false
	root.push_input(event, true)
	var monotonic := true
	var previous: float = before.current_depth
	var held := _grabber.held_body == body
	var start := _clock.seconds
	while _clock.seconds - start < 0.9 - 0.00001:
		await _clock.tick
		held = held and _grabber.held_body == body
		if _grabber.held_body == body:
			var sample := _grabber.get_hold_diagnostics()
			monotonic = monotonic and sample.current_depth <= minf(previous, before.current_depth) + 0.002
			previous = sample.current_depth
			snapshot.samples.append(sample)
	_check(_grabber.pickup_attempts == attempts + 1, label + ": one E is processed once")
	if safe:
		_check(held and _grabber.last_release.is_empty(), label + ": recovery remains physically held")
		_check(monotonic and previous < 0.0001 and _grabber._overlap_recovery.is_empty(), label + ": penetration never grows and recovery clears")
		if _grabber.held_body == body:
			_check(not _grabber.get_hold_diagnostics().target_overlap, label + ": normal target clamping resumes with a clear target")
			if _render and label in ["reported_box", "monitor_stance_1"]:
				await _capture(label + "_after")
	else:
		_check(_grabber.held_body == null and _grabber.last_pickup_attempt.reason == "body_overlaps_player",
			label + ": unsafe geometry remains rejected")
	snapshot["attempt"] = _grabber.last_pickup_attempt.duplicate(true)
	snapshot["release"] = _grabber.last_release.duplicate(true)
	_results.append(snapshot)

func _capture(label: String) -> void:
	var hud: CanvasLayer = _world.get_node("DebugOverlay")
	hud.debug_visible = true
	hud.get_node("Stats").show()
	hud._update_stats()
	var was_paused := paused
	paused = true # Capture geometry and F3 text at the same physics instant.
	await _clock.frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.validation/overlap_%s.png" % label)
	paused = was_paused

func _box(position: Vector3, size: Vector3, title: String) -> void:
	var body := StaticBody3D.new()
	body.name = title
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	_world.add_child(body)

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
