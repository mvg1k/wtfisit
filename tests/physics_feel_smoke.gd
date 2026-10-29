extends SceneTree

const CASES := {"bottle": "res://scenes/props/glass_prop.tscn",
	"monitor": "res://scenes/props/gamer_monitor.tscn", "chair": "res://scenes/furniture/chair.tscn"}
var _world: Node3D
var _player: SandboxPlayer
var _grabber: PhysicsGrabber
var _clock: Clock
var _checks := 0
var _failures := 0
var _render := false
var _label := ""
var _results: Dictionary = {"holds": {}, "fractures": []}

class Clock extends Node:
	signal tick
	signal frame
	var seconds := 0.0
	var player: SandboxPlayer
	var turn_seconds := -1.0
	var moving := false
	func _physics_process(delta: float) -> void:
		seconds += delta
		if moving and is_instance_valid(player):
			turn_seconds += delta
			# Same 60-Hz input trajectory at every rendering FPS.
			player.rotation.y = sin(turn_seconds * 7.0) * 0.45
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
	_clock.process_physics_priority = -100
	root.add_child(_clock)
	_check(Engine.physics_ticks_per_second == 60, "Gameplay physics remains 60 Hz")
	for kind: String in CASES:
		var old := await _hold_case(kind, true)
		var current := await _hold_case(kind, false)
		_results.holds[kind] = {"baseline": old, "polished": current}
		_check(current.response_90 < old.response_90 * 0.8, kind + " catches 90% of an aim step at least 20% sooner")
		_check(current.tracking_error < old.tracking_error * 0.8, kind + " has at least 20% less rapid-look lag")
		_check(current.overshoot < 0.04 and current.final_speed < 0.1,
			kind + " retains inertia without oscillation or excessive overshoot")
	_check(_results.holds.chair.polished.response_90 > _results.holds.bottle.polished.response_90,
		"Force-limited chair retains more inertia than the light bottle")
	for kind: String in CASES:
		await _held_collision_case(kind)
	for material: String in ["glass", "ceramic"]:
		await _fracture_case(material, false)
		await _fracture_case(material, true)
	await _menu_case()
	var file := FileAccess.open("res://.validation/physics_feel_%s.json" % _label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures, "results": _results}, "\t"))
	print("PHYSICS FEEL: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _setup() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(0, -0.15, 0), Vector3(24, 0.3, 24))
	_player = load("res://scenes/player.tscn").instantiate()
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.camera.rotation = Vector3.ZERO
	_clock.player = _player
	_grabber = _player.get_node("Grabber")
	if _render:
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.08, 0.10, 0.13)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.7
		_world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-55, -25, 0)
		_world.add_child(light)
	await _seconds(0.05)

func _cleanup() -> void:
	_clock.moving = false
	_clock.player = null
	_world.queue_free()
	await _seconds(0.05)

func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	if _render:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.35, 0.39, 0.45)
		mesh.material_override = material
		body.add_child(mesh)
	_world.add_child(body)
	return body

func _hold_case(kind: String, baseline: bool) -> Dictionary:
	await _setup()
	if baseline:
		_grabber.spring_strength = 45
		_grabber.spring_damping = 12
	var body: RigidBody3D = load(CASES[kind]).instantiate()
	body.position = Vector3(0, 2, -2)
	_world.add_child(body)
	_grabber._cache_hold_bounds(body)
	body.position = _player.camera.global_position - Vector3(0, 0, 2) - _grabber._held_center
	await _seconds(0.05)
	_grabber.try_pick_up()
	_check(_grabber.held_body == body, "%s %s pickup uses normal ray" % [kind, "baseline" if baseline else "polished"])
	await _seconds(0.8)
	var before := body.global_transform
	_player.rotation.y = 0.35
	var target := _target()
	var start := body.to_global(_grabber._held_center)
	var direction := (target - start).normalized()
	var distance := target.distance_to(start)
	# The look event changes no body transform: forces act on following physics ticks.
	_check(body.global_transform == before, kind + " aim change does not teleport the held body")
	var response_90 := INF
	var overshoot := 0.0
	var started := _clock.seconds
	while _clock.seconds - started < 1.4 - 0.000001:
		await _clock.tick
		var center := body.to_global(_grabber._held_center)
		if center.distance_to(target) < distance * 0.1 and is_inf(response_90):
			response_90 = _clock.seconds - started
		overshoot = maxf(overshoot, (center - target).dot(direction))
	var final_speed := body.linear_velocity.length()
	_check(_grabber.held_body == body and not body.freeze, kind + " step remains physically held")
	_clock.turn_seconds = 0
	_clock.moving = true
	var tracking := 0.0
	var count := 0
	started = _clock.seconds
	while _clock.seconds - started < 1.0 - 0.000001:
		await _clock.tick
		if _clock.seconds - started > 0.2:
			tracking += body.to_global(_grabber._held_center).distance_to(_target())
			count += 1
	_clock.moving = false
	_check(_grabber.held_body == body, kind + " remains held during rapid aim sweeps")
	if _render and not baseline:
		await _capture("hold_" + kind)
	var result := {"mass": body.mass, "response_90": response_90,
		"tracking_error": tracking / maxi(count, 1), "overshoot": overshoot, "final_speed": final_speed}
	print("HOLD ", kind, " baseline=", baseline, " ", result)
	_grabber.release()
	await _cleanup()
	return result

func _target() -> Vector3:
	return _player.camera.global_position - _player.camera.global_basis.z * _grabber.current_hold_distance

func _held_collision_case(kind: String) -> void:
	await _setup()
	var body: RigidBody3D = load(CASES[kind]).instantiate()
	body.position = Vector3(0, 2, -2)
	_world.add_child(body)
	_grabber._cache_hold_bounds(body)
	body.position = _player.camera.global_position - Vector3(0, 0, 2) - _grabber._held_center
	await _seconds(0.05)
	_grabber.try_pick_up()
	await _seconds(0.6)
	_box(Vector3(-0.5, 1.5, -2.1), Vector3(0.07, 3, 1.8))
	_player.rotation.y = 0.55
	var crossed := false
	var depth := 0.0
	var started := _clock.seconds
	while _clock.seconds - started < 0.6 - 0.000001 and is_instance_valid(body):
		await _clock.tick
		crossed = crossed or body.to_global(_grabber._held_center).x < -0.55
		for entry in _grabber._held_shapes:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = entry.shape
			query.transform = body.global_transform * entry.transform
			query.collision_mask = 1
			query.margin = 0
			var contacts := body.get_world_3d().direct_space_state.collide_shape(query, 8)
			for index in range(0, contacts.size(), 2):
				depth = maxf(depth, contacts[index].distance_to(contacts[index + 1]))
	_check(is_instance_valid(body) and not crossed and depth < 0.035,
		kind + " rapid held sweep respects a 7-cm wall without tunneling/embedding")
	_results.holds[kind]["wall_penetration"] = depth
	_grabber.release()
	await _cleanup()

func _fracture_case(kind: String, glancing: bool) -> void:
	await _setup()
	# Separate the player while retaining the real grabber/rest/interpolation helpers.
	_player.position = Vector3(5, 0, 4)
	if _render:
		var camera := Camera3D.new()
		_world.add_child(camera)
		camera.position = Vector3(3, 2.7, 4)
		camera.look_at(Vector3(0, 0.5, -0.5))
		camera.make_current()
	var wall := _box(Vector3(0, 1.5, -1), Vector3(12, 3, 0.07))
	var body: ImpactBody = load("res://scenes/props/" + kind + "_prop.tscn").instantiate()
	body.position = Vector3(0, 1.2, 0.5)
	body.gravity_scale = 0
	_world.add_child(body)
	var contact := {}
	body.damage_state_changed.connect(func(changed: ImpactBody) -> void:
		contact.merge(changed._fracture_impact, true)
		contact["confirmed"] = changed._touching.has(wall.get_rid()))
	await _seconds(0.05)
	# Physical throw-speed impact; the existing sweep supplies pre-clamp context.
	body.linear_velocity = Vector3(5 if glancing else 0, 0, -9)
	_grabber._thrown_bodies.append(body)
	var started := _clock.seconds
	while is_instance_valid(body) and _clock.seconds - started < 1:
		await _clock.tick
	await _clock.frame
	var pieces := get_nodes_in_group("impact_debris")
	_check(not is_instance_valid(body) and pieces.size() == ImpactFragments.MAX_PIECES,
		"Real %s impact produces the existing four-piece budget, glancing=%s" % [kind, glancing])
	_check(contact.get("confirmed", false) and contact.get("severity", 0) > 10 \
		and absf(contact.get("position", Vector3.ZERO).z + 0.965) < 0.1,
		"Confirmed contact carries world impact point and pre-clamp severity")
	var initial: Array[Dictionary] = []
	var average := Vector3.ZERO
	var safe := true
	var peak_speed := 0.0
	var minimum_x := INF
	var maximum_x := -INF
	for piece: RigidBody3D in pieces:
		var velocity := piece.linear_velocity
		peak_speed = maxf(peak_speed, velocity.length())
		average += velocity
		initial.append({"position": str(piece.position), "linear_speed": velocity.length(), "spin": piece.angular_velocity.length()})
		safe = safe and velocity.length() <= ImpactFragments.MAX_LINEAR_SPEED + 0.02 \
			and piece.angular_velocity.length() <= ImpactFragments.MAX_ANGULAR_SPEED + 0.001 \
			and piece.angular_velocity.length() > 0.1 and piece.continuous_cd and not piece.freeze \
			and not piece._scatter_pending
		minimum_x = minf(minimum_x, velocity.x)
		maximum_x = maxf(maximum_x, velocity.x)
	average /= maxi(pieces.size(), 1)
	_check(safe and maximum_x - minimum_x > 0.1 and peak_speed > 1.0,
		"First-physics-tick impulses produce visible scatter/tumble with bounded speed and CCD")
	_check(average.z > 0 and (average.x > 0.1 if glancing else true),
		"Fragment fan rebounds off wall and preserves glancing impact direction")
	var crossed := false
	var bounce := false
	var falling: Dictionary = {}
	var max_spread := 0.0
	started = _clock.seconds
	while _clock.seconds - started < 8 - 0.000001:
		await _clock.tick
		var left := INF
		var right := -INF
		for piece: RigidBody3D in pieces:
			crossed = crossed or piece.position.z < -1.04 or piece.position.y < -0.03
			falling[piece] = falling.get(piece, false) or piece.linear_velocity.y < -0.5
			bounce = bounce or (falling[piece] and piece.position.y < 0.25 and piece.linear_velocity.y > 0.15)
			left = minf(left, piece.position.x)
			right = maxf(right, piece.position.x)
		max_spread = maxf(max_spread, right - left)
		if _render and _clock.seconds - started > 0.3 and _clock.seconds - started < 0.32:
			await _capture("scatter_%s_%s" % [kind, glancing])
	var sleeping := true
	for piece: RigidBody3D in pieces:
		sleeping = sleeping and piece.sleeping
	_check(not crossed, "Scattered fragments stay on the correct wall/floor side")
	_check(bounce and max_spread > 0.3, "Fragments visibly spread and rebound after floor contact")
	_check(sleeping, "Scattered fragments settle naturally within eight seconds")
	_results.fractures.append({"kind": kind, "glancing": glancing, "impact": str(contact),
		"initial": initial, "mean_velocity": str(average), "bounce_observed": bounce,
		"max_spread": max_spread, "sleeping": sleeping})
	if _render:
		await _capture("settled_%s_%s" % [kind, glancing])
	await _cleanup()

func _menu_case() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _frames(3)
	var menu := current_scene
	menu.play_game()
	await _frames(5)
	var grabber: PhysicsGrabber = menu.player.get_node("Grabber")
	var bottle: RigidBody3D = menu.room.get_node("MovableProps/GlassBottle")
	menu.player.position = Vector3(-0.45, 0.02, -0.05)
	menu.player.velocity = Vector3.ZERO
	await _seconds(0.1)
	menu.player.camera.look_at(bottle.global_position + Vector3.UP * 0.2)
	grabber.try_pick_up()
	_check(grabber.held_body == bottle, "Actual room bottle is usable through the menu")
	menu.pause_game()
	var pose := bottle.global_transform
	await _frames(5)
	_check(paused and grabber.held_body == null and bottle.global_transform == pose,
		"Pause drops safely and blocks physics")
	menu.resume_game()
	await _frames(3)
	_check(not paused and menu.player.mouse_captured, "Resume restores gameplay capture")
	for restart in 3:
		menu.pause_game()
		menu.play_game() # The actual Pause/Restart button uses this guarded callback.
		await _frames(5)
		_check(is_instance_valid(menu.room) and not paused and menu.player.mouse_captured,
			"Repeated menu restart %d restores normal gameplay" % restart)
	if _render:
		await _capture("gamers_room")
	current_scene.queue_free()
	await _frames(2)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.validation/feel_%s_%s.png" % [_label, label])

func _seconds(seconds: float) -> void:
	var until := _clock.seconds + seconds
	while _clock.seconds < until - 0.000001:
		await _clock.tick

func _frames(count: int) -> void:
	for index in count:
		await _clock.frame

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
