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
	for angle in [-0.15, 0.0, 0.15]:
		await _floor_monitor("flat", Vector3(PI / 2, 0, 0), Vector3(angle, 0.02, 1.0))
	await _floor_monitor("back", Vector3(-PI / 2, 0, 0), Vector3(0, 0.02, -1.0))
	await _floor_monitor("side", Vector3(0, 0, PI / 2), Vector3(0, 0.02, 0.7))
	await _floor_monitor("upside_down", Vector3(PI, 0, 0), Vector3(0, 0.02, 1.0))
	await _floor_monitor("near_wall", Vector3(PI / 2, 0, 0), Vector3(0, 0.02, 1.0))
	for stance in [SandboxPlayer.Stance.CROUCHING, SandboxPlayer.Stance.PRONE]:
		await _floor_monitor("low_stance", Vector3(PI / 2, 0, 0), Vector3(0, 0.02, 1.0), stance)
	await _room_case("MovableProps/Monitor", Vector3(0, 0.02, -1.2))
	await _room_case("MovableProps/GlassBottle", Vector3(-0.45, 0.02, -0.9))
	await _room_case("Furniture/Chair", Vector3(0.2, 0.02, -0.3))
	await _room_floor_monitor()
	await _rejections()
	await _parallax_and_boundary()
	_check(Engine.physics_ticks_per_second == 60 and not ProjectSettings.get_setting("physics/common/physics_interpolation"),
		"60 Hz physics and disabled global interpolation remain")
	var file := FileAccess.open("res://.validation/pickup_targeting_%s.json" % _label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures, "results": _results}, "\t"))
	print("PICKUP TARGETING: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _setup(room: bool = false) -> void:
	_world = load("res://scenes/gamers_room.tscn").instantiate() if room else Node3D.new()
	root.add_child(_world)
	if room:
		_player = _world.get_node("Player")
	else:
		_box(Vector3(0, -0.1, 0), Vector3(12, 0.2, 12), "Floor")
		_player = load("res://scenes/player.tscn").instantiate()
		_world.add_child(_player)
		if _render:
			var environment := WorldEnvironment.new()
			environment.environment = Environment.new()
			environment.environment.background_mode = Environment.BG_COLOR
			environment.environment.background_color = Color(0.08, 0.1, 0.13)
			environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.environment.ambient_light_color = Color.WHITE
			_world.add_child(environment)
			var hud: CanvasLayer = load("res://scenes/debug_overlay.tscn").instantiate()
			hud.grabber = _player.get_node("Grabber")
			_world.add_child(hud)
	_grabber = _player.get_node("Grabber")
	await _seconds(0.3)
	_player.set_physics_process(false)
	_player.camera.rotation = Vector3.ZERO

func _floor_monitor(label: String, rotation: Vector3, origin: Vector3, stance: int = 0) -> void:
	await _setup()
	_player.position = origin
	_player.body_shape.shape.height = _player.HEIGHTS[stance]
	_player.body_shape.shape.radius = _player.RADII[stance]
	_player.body_shape.position.y = _player.HEIGHTS[stance] * 0.5
	_player.camera.position.y = _player.EYE_HEIGHTS[stance]
	_player.stance = stance
	# Flush the moved/resized player into physics before spawning a resting prop.
	await _seconds(0.05)
	var body: RigidBody3D = load("res://scenes/props/gamer_monitor.tscn").instantiate()
	body.rotation = rotation
	var bounds := _grabber._get_hold_bounds(body)
	var bottom := INF
	for point: Vector3 in bounds.points:
		bottom = minf(bottom, (body.basis * point).y)
	body.position.y = 0.012 - bottom
	_world.add_child(body)
	if label == "near_wall":
		_box(Vector3(-0.5, 1.3, 0), Vector3(0.1, 2.6, 3), "NearbyWall")
	await _seconds(0.3)
	_player.camera.look_at(body.to_global(Vector3(0, 0.43, 0)))
	_player.visual_camera.reset_interpolation()
	await _clock.frame
	await _pickup_and_motion(body, label + " stance=" + str(stance))
	await _cleanup()

func _room_case(path: String, origin: Vector3) -> void:
	await _setup(true)
	_player.position = origin
	var body: RigidBody3D = _world.get_node(path)
	var point := body.to_global(Vector3(0, 0.79, 0.21)) if path.ends_with("Chair") else body.global_position + Vector3.UP * (0.43 if path.ends_with("Monitor") else 0.1)
	_player.camera.look_at(point)
	_player.visual_camera.reset_interpolation()
	await _clock.frame
	await _pickup_and_motion(body, path)
	await _cleanup()

func _room_floor_monitor() -> void:
	await _setup(true)
	_player.position = Vector3(-0.1, 0.02, 0.2)
	var body: RigidBody3D = _world.get_node("MovableProps/Monitor")
	body.rotation = Vector3(PI / 2, 0, 0)
	body.position = Vector3(0, 0.132, -0.8)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	await _seconds(0.3)
	_player.camera.look_at(body.to_global(Vector3(0, 0.43, 0)))
	_player.visual_camera.reset_interpolation()
	await _clock.frame
	await _pickup_and_motion(body, "flat_near_bed_and_furniture")
	await _cleanup()

func _pickup_and_motion(body: RigidBody3D, label: String) -> void:
	var before := body.global_transform
	var diagnostics := _grabber.get_pickup_diagnostics()
	_check(diagnostics.eligible and diagnostics.body_id == body.get_instance_id()
		and diagnostics.surface_distance <= 1.6001, label + ": sight resolves the reachable parent body")
	var attempts := _grabber.pickup_attempts
	var requested := _grabber.current_hold_distance
	var cache := _grabber._held_points.duplicate()
	var preview := diagnostics.duplicate(true)
	for index in 4:
		_grabber.get_pickup_diagnostics()
	_check(body.global_transform == before and _grabber.held_body == null and _grabber.pickup_attempts == attempts
		and _grabber._held_points == cache and _grabber.current_hold_distance == requested,
		label + ": F3 queries have no gameplay/cache/attempt side effects")
	if _render and label == "MovableProps/Monitor":
		await _capture("desk_eligible")
	await _key(KEY_E)
	await _seconds(0.25)
	_check(_grabber.pickup_attempts == attempts + 1 and _grabber.last_pickup_attempt.eligible
		and _grabber.last_pickup_attempt.outcome == "held", label + ": one E is processed and accepted")
	_check(_grabber.held_body == body and _grabber.last_release.is_empty(), label + ": no immediate pickup release")
	var constrained := _grabber.get_hold_diagnostics()
	_check(not constrained.is_empty() and not constrained.player_overlap
		and _grabber._clear_of_player(_grabber._hold_target), label + ": effective spring target clears the capsule")
	if constrained.is_empty():
		return
	requested = _grabber.current_hold_distance
	for frame in 24:
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(0.5, -4.0)
		root.push_input(motion, true)
		await _clock.tick
	await _seconds(0.35)
	_check(_grabber.held_body == body and is_equal_approx(_grabber.current_hold_distance, requested),
		label + ": lift/look retains physical hold and requested distance")
	_results.append({"case": label, "preview": preview, "constrained": constrained,
		"final": _grabber.get_hold_diagnostics(), "attempt": _grabber.last_pickup_attempt.duplicate(true)})
	if _render and (label.begins_with("flat") or label.ends_with("Monitor")):
		await _capture(label.validate_filename())
	# A fresh E intentionally drops; it must not be needed to complete pickup.
	await _key(KEY_E)
	_check(_grabber.held_body == null and _grabber.last_release.reason == &"interact_drop",
		label + ": E drop remains intentional and diagnosed")
	# Re-aim at the real released body and perform a normal charged throw.
	_player.camera.look_at(body.to_global(_grabber._held_center))
	_player.visual_camera.reset_interpolation()
	await _clock.frame
	await _key(KEY_E)
	if _grabber.held_body == body:
		# Turn into a clear, slightly upward throw lane; throwing into the support
		# or north wall tests collision stopping rather than launch preservation.
		var forward := -_player.camera.global_basis.z
		forward.y = 0.35 * Vector2(forward.x, forward.z).length()
		var start := _player.camera.global_basis.get_rotation_quaternion()
		var raised := Basis.looking_at(forward.normalized(), Vector3.UP).get_rotation_quaternion()
		for tick in 60:
			_player.camera.global_basis = Basis(start.slerp(raised, (tick + 1) / 60.0))
			await _clock.tick
		await _seconds(0.3)
		start = _player.camera.global_basis.get_rotation_quaternion()
		var finish := Basis.looking_at(Vector3(1, 0.35, 0), Vector3.UP).get_rotation_quaternion()
		for tick in 90:
			_player.camera.global_basis = Basis(start.slerp(finish, (tick + 1) / 90.0))
			await _clock.tick
		await _seconds(0.25)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		root.push_input(press, true)
		await _seconds(0.25)
		press.pressed = false
		root.push_input(press, true)
		await _seconds(0.05)
		_check(_grabber.held_body == null and _grabber.last_release.reason == &"throw" and body.linear_velocity.length() > 1,
			label + ": charged throw still launches the original physical body (reason=%s speed=%.2f)" % [
				_grabber.last_release.get("reason", "none"), body.linear_velocity.length()])
	else:
		_check(false, label + ": released body remains pickable for throw")

func _rejections() -> void:
	for mode in ["range", "wall", "player", "frozen"]:
		await _setup()
		var body: RigidBody3D = load("res://scenes/props/physics_prop.tscn").instantiate()
		body.position = Vector3(0, 1.6, -1.4)
		body.gravity_scale = 0
		if mode == "range":
			body.position.z = -1.91 # Its front surface is at 1.61 m.
		elif mode == "player":
			body.position.z = -0.4
		elif mode == "frozen":
			body.freeze = true
		_world.add_child(body)
		if mode == "wall":
			_box(Vector3(0, 1.3, -0.7), Vector3(2, 2.6, 0.1), "FurnitureBarrier")
		elif mode == "player":
			# An overlap with a free outward path is now intentionally recoverable.
			# Keep this fixture unsafe across lateral and upward escape candidates.
			_box(Vector3(0, 1.6, -0.8), Vector3(1, 1, 0.1), "BlockedOverlapExit")
			_box(Vector3(-0.4, 1.6, -0.45), Vector3(0.1, 1, 0.6), "BlockedLeftExit")
			_box(Vector3(0.4, 1.6, -0.45), Vector3(0.1, 1, 0.6), "BlockedRightExit")
			_box(Vector3(0, 2.0, -0.45), Vector3(1, 0.1, 0.7), "BlockedUpExit")
		_player.camera.rotation = Vector3.ZERO
		_player.visual_camera.reset_interpolation()
		await _clock.frame
		var diagnostics := _grabber.get_pickup_diagnostics()
		var expected: String = {"range": "out_of_reach", "wall": "surface_not_grabbable",
			"player": "body_overlaps_player", "frozen": "body_frozen"}[mode]
		await _key(KEY_E)
		_check(not diagnostics.eligible and diagnostics.reason == expected and _grabber.held_body == null
			and _grabber.last_pickup_attempt.reason == expected, mode + ": real rejection is preserved and explained")
		_results.append({"case": mode, "preview": diagnostics, "attempt": _grabber.last_pickup_attempt.duplicate(true)})
		await _cleanup()

func _parallax_and_boundary() -> void:
	await _setup()
	var body: RigidBody3D = load("res://scenes/props/physics_prop.tscn").instantiate()
	body.position = Vector3(0, 1.6, -1.89)
	body.gravity_scale = 0
	_world.add_child(body)
	await _clock.frame
	await _key(KEY_E)
	_check(_grabber.held_body == body and _grabber.last_pickup_attempt.surface_distance > 1.58,
		"The 1.59 m accessible surface is pickable even with its body centre beyond 1.60 m")
	_grabber.release()
	body.position.z = -1.94
	body.linear_velocity = Vector3.ZERO
	await _clock.frame
	_player.visual_camera.global_position = _player.camera.global_position - Vector3(0, 0, 0.1)
	var info := _grabber.get_pickup_diagnostics()
	_grabber.try_pick_up()
	_check(info.reason == "out_of_reach" and _grabber.held_body == null
		and _grabber.last_pickup_attempt.reason == "out_of_reach", "Interpolated eye offset cannot extend physical surface reach")
	_player.visual_camera.reset_interpolation()
	body.position = Vector3(-0.08, 1.6, -1.5)
	_box(Vector3(-0.035, 1.6, -0.5), Vector3(0.02, 1, 0.08), "ThinCorner")
	await _clock.frame
	_player.visual_camera.global_position = _player.camera.global_position - Vector3(0.08, 0, 0)
	info = _grabber.get_pickup_diagnostics()
	_grabber.try_pick_up()
	_check(info.reason == "physical_eye_occluded" and info.occluder == "ThinCorner" and _grabber.held_body == null
		and _grabber.last_pickup_attempt.reason == info.reason, "Visible-eye parallax cannot bypass physical-eye furniture occlusion")
	await _cleanup()

func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	root.push_input(event, true)
	await _clock.tick
	event.pressed = false
	root.push_input(event, true)
	await _clock.tick

func _capture(label: String) -> void:
	var hud: CanvasLayer = _world.get_node("DebugOverlay")
	hud.debug_visible = true
	hud.get_node("Stats").show()
	hud._update_stats()
	await _clock.frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.validation/pickup_%s.png" % label)

func _box(position: Vector3, size: Vector3, title: String) -> void:
	var body := StaticBody3D.new()
	body.name = title
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	if _render:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		body.add_child(mesh)
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
