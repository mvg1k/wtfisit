extends SceneTree

var _world: Node3D
var _player: SandboxPlayer
var _hud: CanvasLayer
var _observer: Observer
var _checks := 0
var _failures := 0
var _render := false
var _baseline := false
var _label := "run"
var _results: Dictionary = {}

class Observer extends Node:
	signal frame(delta: float)
	var elapsed := 0.0
	func _process(delta: float) -> void:
		elapsed += delta
		frame.emit(delta)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_render = OS.get_cmdline_user_args().has("--render")
	_baseline = OS.get_cmdline_user_args().has("--baseline")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_label = arg.trim_prefix("--output=").validate_filename()
	_observer = Observer.new()
	_observer.process_priority = 100
	root.add_child(_observer)
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(0, -0.1, 0), Vector3(30, 0.2, 30), Color(0.15, 0.18, 0.2))
	_box(Vector3(0, 2, -3), Vector3(30, 4, 0.1), Color(0.04, 0.05, 0.06))
	_player = load("res://scenes/player.tscn").instantiate()
	_world.add_child(_player)
	_hud = load("res://scenes/debug_overlay.tscn").instantiate()
	_hud.grabber = _player.get_node("Grabber")
	_hud.debug_visible = false
	_world.add_child(_hud)
	_check(_world.find_children("Crosshair", "Label", true, false).size() == 1,
		"Exactly one crosshair label exists; charge indicator does not draw another plus")
	for mode: String in ["stationary", "forward", "strafe", "walk_look", "blocked"]:
		await _movement(mode)
	if not _baseline:
		await _pickup_and_occlusion()
	var file := FileAccess.open("res://.validation/crosshair_%s.json" % _label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures, "results": _results}, "\t"))
	_world.queue_free()
	await _observer.frame
	print("CROSSHAIR: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _movement(mode: String) -> void:
	Input.action_release("move_forward")
	Input.action_release("move_right")
	_player.position = Vector3(0, 0.02, -2.65 if mode == "blocked" else 0)
	_player.velocity = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	_player.camera.rotation = Vector3(-0.14, 0, 0)
	await _seconds(0.25)
	if mode in ["forward", "walk_look", "blocked"]:
		Input.action_press("move_forward")
	elif mode == "strafe":
		Input.action_press("move_right")
	await _seconds(0.2)
	var crosshair: Label = _hud.get_node("Crosshair")
	var ring: Control = _hud.get_node("ThrowChargeIndicator")
	var positions: Array[Vector2] = []
	var body_positions: Array[Vector3] = []
	var aim_error := 0.0
	var center_error := 0.0
	var ring_error := 0.0
	var rotation_error := 0.0
	var offsets: Array[Vector2] = []
	var elapsed := 0.0
	var image_keys := {}
	var film := Image.create_empty(48 * 8, 48, false, Image.FORMAT_RGBA8)
	var captures := 0
	while elapsed < 0.3 - 0.000001:
		var delta: float = await _observer.frame
		elapsed += delta
		var center := root.get_visible_rect().size * 0.5
		var point := crosshair.position + crosshair.size * 0.5
		positions.append(point)
		body_positions.append(_player.global_position)
		offsets.append(_player.visual_camera.aim_screen_offset)
		center_error = maxf(center_error, point.distance_to(center))
		ring_error = maxf(ring_error, point.distance_to(ring.position + ring.size * 0.5))
		rotation_error = maxf(rotation_error, (_player.camera.global_basis.z - _player.visual_camera.global_basis.z).length())
		if not _baseline:
			var hit: Dictionary = _hud.grabber.call("get_aim_hit", _hud.grabber.reach)
			if not hit.is_empty():
				aim_error = maxf(aim_error, _player.visual_camera.unproject_position(hit.position).distance_to(center))
		if _render and captures < 8:
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			var rect := Rect2i(Vector2i(center) - Vector2i(24, 24), Vector2i(48, 48))
			var crop := screenshot.get_region(rect)
			var white := ""
			for y in 48:
				for x in 48:
					var color := crop.get_pixel(x, y)
					white += "1" if minf(color.r, minf(color.g, color.b)) > 0.85 else "0"
			image_keys[hash(white)] = true
			film.blit_rect(crop, Rect2i(0, 0, 48, 48), Vector2i(captures * 48, 0))
			if captures == 0:
				screenshot.save_png("res://.validation/crosshair_%s_%s.png" % [_label, mode])
			captures += 1
		if mode == "walk_look":
			var motion := InputEventMouseMotion.new()
			motion.relative = Vector2(50, 0) * delta
			_player._unhandled_input(motion)
	var motion_span := 0.0
	var body_span := 0.0
	for point in positions:
		motion_span = maxf(motion_span, point.distance_to(positions[0]))
	for point in body_positions:
		body_span = maxf(body_span, point.distance_to(body_positions[0]))
	_results[mode] = {"hud_motion_px": motion_span, "center_error_px": center_error,
		"body_motion_m": body_span, "aim_error_px": aim_error, "ring_error_px": ring_error,
		"rotation_error": rotation_error, "render_masks": image_keys.size(),
		"positions": str(positions), "legacy_offsets": str(offsets)}
	print("CROSSHAIR TIMING ", mode, " ", _results[mode])
	_check(body_span < 0.001 if mode in ["stationary", "blocked"] else body_span > 0.5,
		mode + " exercises the expected actual player movement")
	if _baseline:
		_check(motion_span < 0.01 if mode in ["stationary", "blocked"] else motion_span > 0.1,
			mode + " reproduces the reported movement-dependent HUD jitter")
	else:
		_check(motion_span < 0.001 and center_error < 0.001, mode + " keeps the crosshair fixed at screen centre")
		_check(aim_error < 0.01 and ring_error < 0.001, mode + " keeps the sight ray and charge ring aligned")
		_check(rotation_error < 0.00001, mode + " preserves immediate camera rotation")
		if _render:
			_check(captures >= 4 and image_keys.size() == 1, mode + " renders an identical crosshair pixel mask every frame")
	if _render:
		film.save_png("res://.validation/crosshair_%s_%s_strip.png" % [_label, mode])
	Input.action_release("move_forward")
	Input.action_release("move_right")

func _pickup_and_occlusion() -> void:
	_player.position = Vector3(0, 0.02, 0)
	_player.velocity = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	_player.camera.rotation = Vector3.ZERO
	await _seconds(0.2)
	var body: RigidBody3D = load("res://scenes/props/physics_prop.tscn").instantiate()
	body.position = Vector3(0, 1.62, -1.5)
	body.gravity_scale = 0
	_world.add_child(body)
	await _seconds(0.05)
	var grabber: PhysicsGrabber = _hud.grabber
	var hit: Dictionary = grabber.call("get_aim_hit", grabber.reach)
	_check(hit.get("collider") == body, "Centred sight ray selects the real nearby prop")
	grabber.try_pick_up()
	_check(grabber.held_body == body and grabber.camera == _player.camera, "Pickup retains the gameplay camera/reference and original dynamic body")
	grabber.is_charging_throw = true
	grabber._charge_seconds = 0.4
	Input.action_press("move_right")
	await _seconds(0.15)
	Input.action_release("move_right")
	var ring: Control = _hud.get_node("ThrowChargeIndicator")
	_check(ring.visible and _player.position.x > 0.05 \
		and (ring.position + ring.size * 0.5).distance_to(root.get_visible_rect().size * 0.5) < 0.001,
		"Charging while walking draws one centred ring around the fixed crosshair")
	grabber.release()
	await _seconds(0.05)
	_check(not ring.visible and not grabber.is_charging_throw, "Drop clears the charge indicator normally")
	_player.position = Vector3(0, 0.02, 0)
	_player.velocity = Vector3.ZERO
	await _seconds(0.1)
	body.position = Vector3(0, 1.62, -1.5)
	body.linear_velocity = Vector3.ZERO
	var wall := _box(Vector3(0, 1.6, -0.7), Vector3(1, 1, 0.07), Color(0.04, 0.05, 0.06))
	await _seconds(0.05)
	grabber.try_pick_up()
	_check(grabber.held_body == null and grabber.call("get_aim_hit", grabber.reach).get("collider") == wall,
		"World occlusion still blocks pickup")
	wall.queue_free()
	await _seconds(0.05)
	# Simulate a valid sub-tick eye offset near a thin corner. The visible sight
	# can clear it while the physical eye cannot reach the exact sight hit.
	body.position = Vector3(-0.08, 1.62, -1.5)
	body.linear_velocity = Vector3.ZERO
	wall = _box(Vector3(-0.035, 1.62, -0.5), Vector3(0.02, 1, 0.08), Color(0.04, 0.05, 0.06))
	await _seconds(0.05)
	_player.visual_camera.global_position = _player.camera.global_position + Vector3(-0.08, 0, 0)
	_check(grabber.get_aim_hit(grabber.reach).is_empty(), "Eye parallax cannot bypass physical-eye wall occlusion")
	wall.queue_free()
	_player.rotation.y = PI / 2
	body.position = Vector3(-3.55, 1.62, 0)
	body.linear_velocity = Vector3.ZERO
	await _seconds(0.05)
	_player.visual_camera.global_position = _player.camera.global_position + Vector3(-0.1, 0, 0)
	_check(grabber.get_aim_hit(grabber.reach).is_empty(), "Eye parallax cannot extend the configured physical grab range")
	body.queue_free()
	_check(Engine.physics_ticks_per_second == 60 and _player.visual_camera == root.get_camera_3d(),
		"60-Hz physics and the independent smoothed camera remain active")

func _box(position: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = size
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	body.position = position
	_world.add_child(body)
	return body

func _seconds(seconds: float) -> void:
	var until := _observer.elapsed + seconds
	while _observer.elapsed < until - 0.000001:
		await _observer.frame

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
