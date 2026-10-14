extends SceneTree

# No Player/PropRest is present during falls: sleep must come from native physics.
# The exact face-down reproduction previously rocked indefinitely without PropRest.
var _checks: int = 0
var _failures: int = 0
var _latest_sleep: float = 0.0
var _largest_quiet_step: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rotations := [Vector3.ZERO, Vector3(PI / 2, 0, 0), Vector3(-PI / 2, 0, 0),
		Vector3(0, 0, PI / 2), Vector3(0, 0, -PI / 2), Vector3(0.7, 1.1, 0.4)]
	for variant: String in ["gamer_monitor", "monitor"]:
		for index in rotations.size():
			for spin: float in [0.0, 2.0, 7.0]:
				await _fall(variant, rotations[index], Vector3(0.7, -0.4, 0.2).normalized() * spin,
					false, spin == 0.0 and index in [1, 3])
		await _fall(variant, Vector3(PI / 2, 0, 0), Vector3(1.7, -0.8, 0.3), true, false)
	print("MONITOR SETTLING: %d checks, %d failure(s); latest native sleep %.2fs, largest final quiet step %.4fmm" %
		[_checks, _failures, _latest_sleep, _largest_quiet_step * 1000])
	quit(0 if _failures == 0 else 1)


func _fall(variant: String, rotation: Vector3, spin: Vector3, reproduction: bool, recover: bool) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(30, 0.2, 30)
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	floor_body.position.y = -0.1
	world.add_child(floor_body)
	var body := load("res://scenes/props/" + variant + ".tscn").instantiate() as ImpactBody
	body.rotation = rotation
	var points := _points(body)
	var bottom := INF
	for point in points:
		bottom = minf(bottom, (body.basis * point).y)
	body.position = Vector3(0, 0.95, 0.2) if reproduction else Vector3(0, 0.6 - bottom, 0)
	world.add_child(body)
	body.angular_velocity = spin
	var previous := body.global_transform
	var quiet_steps: Array[float] = []
	var sleep_frame := -1
	for frame in 600:
		await physics_frame
		var pose := body.global_transform
		var step := 0.0
		for point in points:
			step = maxf(step, (pose * point).distance_to(previous * point))
		quiet_steps.append(step)
		if quiet_steps.size() > 3:
			quiet_steps.pop_front()
		previous = pose
		if body.sleeping:
			sleep_frame = frame
			break
	var label := "%s rotation=%s spin=%s exact=%s" % [variant, rotation, spin, reproduction]
	_check(sleep_frame >= 0 and not body.freeze, "Naturally settles within 10s: " + label)
	var quiet_peak: float = quiet_steps.max()
	_largest_quiet_step = maxf(_largest_quiet_step, quiet_peak)
	_latest_sleep = maxf(_latest_sleep, sleep_frame / 60.0)
	_check(quiet_peak < 0.0005 and body.angular_velocity.length() < 0.01,
		"Final three steps have no visible rocking before sleep: " + label)
	var settled := body.global_transform
	await _steps(120)
	var drift := 0.0
	for point in points:
		drift = maxf(drift, (body.global_transform * point).distance_to(settled * point))
	_check(body.sleeping and drift < 0.0005, "No two-second resting drift: " + label)
	if recover:
		await _recover(world, body, points)
	world.queue_free()
	await _steps(3)


func _recover(world: Node3D, body: ImpactBody, points: PackedVector3Array) -> void:
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	var center := body.to_global(bounds.get_center())
	var player := load("res://scenes/player.tscn").instantiate() as SandboxPlayer
	player.position = Vector3(center.x, 0.02, center.z + 1.5)
	world.add_child(player)
	player.set_physics_process(false)
	var grabber := player.get_node("Grabber") as PhysicsGrabber
	grabber._rest.set_physics_process(false)
	player.camera.look_at(center)
	await _steps(2)
	grabber.try_pick_up()
	await _steps(30)
	_check(grabber.held_body == body, "Fallen monitor remains held while looking down: " + body.name)
	player.camera.rotation = Vector3.ZERO
	await _steps(90)
	_check(grabber.held_body == body and body.position.y > 0.5 and not body.freeze,
		"Monitor lifts clear of the floor while remaining dynamic: " + body.name)
	grabber.release(true, 0.4)
	await _steps(3)
	_check(not body.sleeping and not body.freeze and body.linear_velocity.length() > 1.0,
		"Recovered monitor throws through existing controls: " + body.name)
	await _steps(600)
	_check(body.sleeping and not body.freeze, "Thrown monitor settles again without the rest helper: " + body.name)


func _points(body: RigidBody3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for child in body.get_children():
		if child is CollisionShape3D and not child.disabled:
			if child.shape is ConvexPolygonShape3D:
				for point in child.shape.points:
					points.append(child.transform * point)
			else:
				var bounds: AABB = child.shape.get_debug_mesh().get_aabb()
				for corner in 8:
					points.append(child.transform * bounds.get_endpoint(corner))
	return points


func _steps(count: int) -> void:
	for frame in count:
		await physics_frame


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("FAIL: " + message)
