extends SceneTree

var _world: Node3D
var _player: SandboxPlayer
var _grabber: PhysicsGrabber
var _visuals: PropVisualInterpolation
var _observer: Observer
var _checks := 0
var _failures := 0
var _render := false
var _label := ""
var _timing: Dictionary = {}

class Observer extends Node:
	signal frame(delta: float)
	var elapsed := 0.0
	var body: RigidBody3D
	var visuals: PropVisualInterpolation
	var samples: Array[Dictionary] = []
	func _process(delta: float) -> void:
		elapsed += delta
		if is_instance_valid(body):
			var visual := visuals.get_visual_transform(body)
			samples.append({"delta": delta, "elapsed": elapsed, "wall_usec": Time.get_ticks_usec(),
				"tick": Engine.get_physics_frames(), "fraction": Engine.get_physics_interpolation_fraction(),
				"physical": body.global_position.x, "visual": visual.origin.x,
				"physical_y": body.global_position.y, "visual_y": visual.origin.y,
				"angle": visual.basis.get_rotation_quaternion().get_angle()})
		frame.emit(delta)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_render = OS.get_cmdline_user_args().has("--render")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_label = argument.trim_prefix("--output=").validate_filename()
	_observer = Observer.new()
	_observer.process_priority = 200
	_observer.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_observer)
	_check(Engine.physics_ticks_per_second == 60 and not ProjectSettings.get_setting("physics/common/physics_interpolation"),
		"60-Hz physics and existing global interpolation setting preserved")
	_timing.runtime = {"physics_tps": Engine.physics_ticks_per_second,
		"global_interpolation": ProjectSettings.get_setting("physics/common/physics_interpolation"), "rendered": _render}
	await _setup()
	await _test_clock()
	await _cleanup()
	await _setup()
	await _test_interactions()
	await _cleanup()
	await _setup()
	await _test_falls_and_fragments()
	await _cleanup()
	for restart in 3:
		await _setup()
		_check(_visuals._props.size() == 0, "Restart %d starts with fresh prop history" % restart)
		await _cleanup()
	var file := FileAccess.open("res://.validation/prop_matrix_%s.json" % _label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"timing": _timing, "checks": _checks, "failures": _failures}, "\t"))
	print("PROP SMOOTHING: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _setup() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, 0.2, 30)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.1
	_world.add_child(floor_body)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.03, 0.03, 0.04)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	_world.add_child(environment)
	_player = load("res://scenes/player.tscn").instantiate()
	_world.add_child(_player)
	_grabber = _player.get_node("Grabber")
	_visuals = _grabber._visuals
	_observer.visuals = _visuals
	await _seconds(0.15)

func _cleanup() -> void:
	_observer.body = null
	_world.queue_free()
	await _seconds(0.1)

func _prop(path: String, position: Vector3) -> RigidBody3D:
	var body: RigidBody3D = load(path).instantiate()
	body.position = position
	_world.add_child(body)
	return body

func _test_clock() -> void:
	var body := _prop("res://scenes/props/physics_prop.tscn", Vector3(-0.8, 1.6, -3))
	body.gravity_scale = 0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 0
	body.linear_velocity = Vector3.RIGHT
	body.angular_velocity = Vector3(0, 1, 0)
	var local: Transform3D = body.get_node("Mesh").transform
	await _seconds(0.2)
	_observer.body = body
	_observer.samples.clear()
	await _seconds(0.5)
	_observer.body = null
	var samples := _observer.samples.duplicate(true)
	var physical_repeats := 0
	var visual_repeats := 0
	var max_step_error := 0.0
	var max_angle_error := 0.0
	for index in range(1, samples.size()):
		var a: Dictionary = samples[index - 1]
		var b: Dictionary = samples[index]
		if absf(b.physical - a.physical) < 0.000001:
			physical_repeats += 1
		if absf(b.visual - a.visual) < 0.000001:
			visual_repeats += 1
		max_step_error = maxf(max_step_error, absf(b.visual - a.visual - b.delta))
		max_angle_error = maxf(max_angle_error, absf(b.angle - a.angle - b.delta))
	var first: Dictionary = samples.front()
	var last: Dictionary = samples.back()
	var elapsed: float = last.elapsed - first.elapsed
	var fps := (samples.size() - 1) / elapsed
	_timing.clock = {"fps": fps, "wall_fps": (samples.size() - 1) * 1000000.0 / (last.wall_usec - first.wall_usec),
		"physics_hz": (last.tick - first.tick) / elapsed, "physical_repeats": physical_repeats,
		"visual_repeats": visual_repeats, "max_step_error": max_step_error, "max_angle_error": max_angle_error,
		"samples": samples}
	_check(visual_repeats == 0 and max_step_error < 0.0001, "Every moving render pose advances by velocity times render delta")
	_check(max_angle_error < 0.0001, "Rotation advances with elapsed time rather than render-frame count")
	_check(physical_repeats > 0 if fps > Engine.physics_ticks_per_second + 1 else true,
		"High-FPS render updates advance between unchanged physics transforms")
	_check(absf((last.physical - first.physical) / elapsed - 1) < 0.04,
		"Authoritative body retains 1 m/s independent of render FPS")
	_check(body.get_node("Mesh").transform == local, "Authored mesh/node transforms are untouched")
	if _render:
		await _test_render_submission(body)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.validation/prop_clock_%s.png" % _label)
	var before := _visuals.get_visual_transform(body)
	paused = true
	await _seconds(0.1)
	_check(_visuals.get_visual_transform(body) == before, "Pause retains the displayed prop pose")
	paused = false
	await _seconds(0.05)
	_check(_visuals.get_visual_transform(body).origin.distance_to(body.global_position) \
		< body.linear_velocity.length() / Engine.physics_ticks_per_second + 0.001,
		"Resume rebuilds physics history within one tick")
	body.global_position += Vector3(3, 1, 0)
	_visuals._process(0)
	_check(_visuals.get_visual_transform(body) == body.global_transform, "External teleport resets without a trail")
	body.queue_free()
	await _seconds(0.05)
	_check(_visuals._props.is_empty(), "Deleted props release presentation history")

func _test_render_submission(body: RigidBody3D) -> void:
	# Pixel evidence, independent of the helper's calculated transform. A sphere's
	# colour centroid gives a stable projected centre while the body translates.
	var mesh: MeshInstance3D = body.get_node("Mesh")
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 0, 1)
	mesh.material_override = material
	body.linear_velocity = Vector3(4, 0, 0)
	await _seconds(0.05)
	var visual_error := 0.0
	var physical_error := 0.0
	var captures: Array[Dictionary] = []
	for frame in 8:
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var center := Vector2.ZERO
		var pixels := 0
		# Search a small strip around the known projected target, avoiding full-image
		# per-pixel work and imposing no runtime/gameplay dependency.
		var submitted: Transform3D = _visuals._props[body].submitted
		var expected := _player.visual_camera.unproject_position(submitted.origin)
		for y in range(maxi(0, int(expected.y) - 40), mini(image.get_height(), int(expected.y) + 40)):
			for x in range(maxi(0, int(expected.x) - 40), mini(image.get_width(), int(expected.x) + 40)):
				var color := image.get_pixel(x, y)
				if color.r > 0.8 and color.b > 0.8 and color.g < 0.1:
					center += Vector2(x + 0.5, y + 0.5)
					pixels += 1
		if pixels == 0:
			_check(false, "Rendered test sphere remains visible")
			return
		center /= pixels
		var raw := _player.visual_camera.unproject_position(body.global_position)
		visual_error += center.distance_to(expected)
		physical_error += center.distance_to(raw)
		captures.append({"tick": Engine.get_physics_frames(), "fraction": Engine.get_physics_interpolation_fraction(),
			"pixel_x": center.x, "visual_x": expected.x, "physical_x": raw.x})
		await _observer.frame
	_timing.render_readback = {"mean_visual_error_px": visual_error / captures.size(),
		"mean_physical_error_px": physical_error / captures.size(), "captures": captures}
	_check(visual_error / captures.size() < 1.0, "Rendered pixel centroid matches interpolated mesh position")
	if _timing.clock.fps > Engine.physics_ticks_per_second + 1:
		_check(physical_error > visual_error + captures.size(), "Renderer shows interpolation rather than the raw physics pose")

func _test_interactions() -> void:
	var body := _prop("res://scenes/props/glass_prop.tscn", Vector3(0, 1.55, -1.5))
	await _seconds(0.05)
	_player.camera.look_at(body.global_position)
	_grabber.try_pick_up()
	_check(_grabber.held_body == body, "Gameplay ray picks up the original bottle body")
	Input.action_press("move_right")
	await _sample_case("grabbed", body, 0.35)
	Input.action_release("move_right")
	_check(_grabber.held_body == body, "Grab remains stable while walking")
	var pose := body.global_transform
	_grabber.release(true, 0.4)
	_check(body.global_transform == pose and body.linear_velocity.length() > 4, "Throw preserves physical pose and launches bottle")
	await _sample_case("thrown_bottle", body, 0.15)
	body.queue_free()
	await _seconds(0.05)
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	var kicked := _prop("res://scenes/props/physics_prop.tscn", Vector3(0, 0.7, -1))
	kicked.gravity_scale = 0
	await _seconds(0.05)
	_player.camera.look_at(kicked.global_position + Vector3(0.12, 0.1, 0))
	_check(_grabber.get_kick_target().get("collider") == kicked, "Existing kick query selects nearby collider")
	_grabber._kick()
	await _sample_case("kicked", kicked, 0.25)
	_check(kicked.linear_velocity.length() > 1, "Kick still gives physical impulse")
	var chair := _prop("res://scenes/furniture/chair.tscn", Vector3(3, 1, -3))
	chair.apply_central_impulse(Vector3(12, 1, 0))
	await _sample_case("furniture", chair, 0.3)

func _test_falls_and_fragments() -> void:
	var monitor := _prop("res://scenes/props/gamer_monitor.tscn", Vector3(0, 1.4, -2)) as ImpactBody
	monitor.rotation = Vector3(PI / 2, 0.3, 0)
	monitor.angular_velocity = Vector3(1.7, -0.8, 0.3)
	await _sample_case("monitor_fall", monitor, 0.4)
	await _seconds(5)
	_check(monitor.sleeping and not monitor.freeze, "Monitor still settles with normal dynamic sleep")
	var pose := monitor.global_transform
	await _sample_case("resting", monitor, 0.2)
	_check(monitor.global_transform == pose and _visuals.get_visual_transform(monitor) == pose,
		"Resting monitor has no presentation drift")
	if _render:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.validation/prop_rest_%s.png" % _label)
	var bottle := _prop("res://scenes/props/glass_prop.tscn", Vector3(2, 1.5, -2)) as ImpactBody
	bottle.linear_velocity = Vector3(2, 0, 0)
	await _seconds(0.05)
	var correction := _visuals.get_visual_transform(bottle) * bottle.global_transform.affine_inverse()
	bottle.damage_state = ImpactBody.State.BROKEN
	bottle._commit_state()
	var continuity := true
	for fragment in get_nodes_in_group("impact_debris"):
		continuity = continuity and _visuals.get_visual_transform(fragment).is_equal_approx(correction * fragment.global_transform)
	_check(continuity, "Replacement meshes inherit the source's last displayed pose without a forward pop")
	await _seconds(0.05)
	var fragments := get_nodes_in_group("impact_debris")
	_check(not is_instance_valid(bottle) and fragments.size() > 0, "Brittle replacement creates real physics fragments")
	var registered := true
	for fragment in fragments:
		registered = registered and _visuals._props.has(fragment)
	_check(registered, "Replacement fragments start their own history at final placement")
	await _sample_case("fragment", fragments[0], 0.2)
	var previous := Transform3D(Basis.IDENTITY, Vector3(4, 0.35, -2))
	var current := Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(4, 0.35, -2))
	var box := _prop("res://scenes/props/physics_prop.tscn", current.origin)
	var unsafe := previous.interpolate_with(current, 0.5)
	_check(_visuals._clear_pose(box, unsafe, current, previous) == current,
		"Clearance guard rejects extra visual penetration into a static support")

func _sample_case(label: String, body: RigidBody3D, seconds: float) -> void:
	_observer.body = body
	_observer.samples.clear()
	await _seconds(seconds)
	_observer.body = null
	var distinct_ticks := {}
	var within_tick_moves := 0
	var samples := _observer.samples.duplicate(true)
	for index in range(1, samples.size()):
		var a: Dictionary = samples[index - 1]
		var b: Dictionary = samples[index]
		distinct_ticks[b.tick] = true
		if a.tick == b.tick and (absf(a.visual - b.visual) + absf(a.visual_y - b.visual_y) + absf(a.angle - b.angle)) > 0.000001:
			within_tick_moves += 1
	_timing[label] = {"samples": samples, "within_tick_moves": within_tick_moves}
	_check(not samples.is_empty() and distinct_ticks.size() > 1, "Render samples cover " + label)
	if label != "resting" and _timing.clock.fps > Engine.physics_ticks_per_second + 1:
		_check(within_tick_moves > 0, label + " renders motion between physics ticks")

func _seconds(seconds: float) -> void:
	var until := _observer.elapsed + seconds
	while _observer.elapsed < until - 0.000001:
		await _observer.frame

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)
