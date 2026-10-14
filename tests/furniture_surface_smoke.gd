extends SceneTree

const ROOM: PackedScene = preload("res://scenes/gamers_room.tscn")
var _room: Node3D
var _player: SandboxPlayer
var _grabber: PhysicsGrabber
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for fixture: Array in [
		["BedsideTable", "Top", "glass_prop"], ["BedsideTable", "Top", "wood_prop"],
		["BedsideTable", "Top", "plastic_prop"], ["BedsideTable", "Top", "moving_box"],
		["Dresser", "Top", "glass_prop"], ["Dresser", "Top", "wood_prop"],
		["Dresser", "Top", "plastic_prop"], ["PCDesk", "Top", "moving_box"],
		["Chair", "Seat", "glass_prop"], ["Chair", "Seat", "plastic_prop"],
		["Bed", "Blanket", "moving_box"], ["Wardrobe", "Cabinet", "wood_prop"],
		["Shelves", "Shelf2", "plastic_prop"]]:
		await _surface(fixture[0], fixture[1], fixture[2])
	for furniture: String in ["BedsideTable", "Dresser"]:
		await _held_placement(furniture)
	for furniture: String in ["Chair", "BedsideTable"]:
		for action: String in ["push", "kick", "throw"]:
			await _movement(furniture, action)
	print("FURNITURE/SURFACES: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _setup() -> void:
	_room = ROOM.instantiate()
	root.add_child(_room)
	_player = _room.get_node("Player") as SandboxPlayer
	_grabber = _player.get_node("Grabber") as PhysicsGrabber
	# Isolate the authored support from loose clutter, retaining its real mesh,
	# colliders, material, dynamic mass and the room's existing rest helper.
	_room.get_node("MovableProps").queue_free()
	await _steps(3)


func _cleanup() -> void:
	_grabber.release()
	_room.queue_free()
	await _steps(3)


func _prop(file: String) -> RigidBody3D:
	var body := load("res://scenes/props/" + file + ".tscn").instantiate() as RigidBody3D
	body.position = Vector3(0, 2, 0) # Never briefly insert a new collider inside the player/floor.
	_room.add_child(body)
	return body


func _bottom(body: Node3D, reference: Transform3D = Transform3D.IDENTITY) -> float:
	var bottom := INF
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree():
			continue
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				bottom = minf(bottom, (reference * mesh.global_transform * vertex).y)
	return bottom


func _gap(body: Node3D, surface: MeshInstance3D) -> float:
	# Compare visible vertices to the moving/tilting support's actual plane,
	# never the prop pivot or a conservative rotated bounding box.
	return _bottom(body, surface.global_transform.affine_inverse()) - surface.mesh.size.y * 0.5


func _place(body: RigidBody3D, surface: MeshInstance3D, gap: float) -> void:
	var centre := Vector3(0, surface.mesh.size.y * 0.5, 0)
	if surface.name == "Seat":
		centre.z = -0.05 # Clear the backrest rather than intersecting it at spawn.
	elif surface.name.begins_with("Shelf"):
		centre.z = 0.065 # Clear the shelf's back panel.
	body.global_position = surface.global_transform * centre
	if surface.name.begins_with("Shelf"):
		body.global_rotation.y = surface.global_rotation.y
	body.global_position.y += gap - _gap(body, surface)


func _surface(furniture: String, mesh_name: String, file: String) -> void:
	await _setup()
	var support := _room.get_node("Furniture/" + furniture) as PhysicsBody3D
	var surface := support.get_node(mesh_name) as MeshInstance3D
	var body := _prop(file)
	_place(body, surface, 0.04)
	await _steps(600)
	var label := "%s on %s" % [file, furniture]
	_check(is_instance_valid(body), "Gentle placement preserves " + label)
	if is_instance_valid(body):
		var gap := _gap(body, surface)
		print("SURFACE: %s gap=%.3f mm" % [label, gap * 1000])
		_check(gap >= -0.002 and gap <= 0.003, "Visible contact stays within -2/+3 mm: " + label)
		_check(body.sleeping and (not support is RigidBody3D or support.sleeping),
			"Loaded support and prop settle dynamically: " + label)
		var pose := body.global_transform
		var support_pose := support.global_transform
		await _steps(120)
		_check(body.global_position.distance_to(pose.origin) < 0.002
			and support.global_position.distance_to(support_pose.origin) < 0.002,
			"Loaded pair has no persistent drift/jitter: " + label)
	await _cleanup()


func _held_placement(furniture: String) -> void:
	await _setup()
	var surface := _room.get_node("Furniture/" + furniture + "/Top") as MeshInstance3D
	var body := _prop("glass_prop")
	_place(body, surface, 0.06)
	# A two-metre hold reaches the actual tabletop from these clear approaches.
	_player.position = Vector3(-0.1, 0.02, 0) if furniture == "Dresser" else Vector3(-0.45, 0.02, -0.05)
	_player.velocity = Vector3.ZERO
	await _steps(10)
	_player.camera.look_at(body.global_position)
	_grabber.try_pick_up()
	_check(_grabber.held_body == body, "Camera-ray pickup before placement on " + furniture)
	_player.camera.look_at(surface.global_transform * Vector3(0, surface.mesh.size.y * 0.5, 0.08))
	await _steps(120)
	_check(_grabber.held_body == body and _gap(body, surface) > 0.02,
		"Existing hold clearance lifts bottle above " + furniture)
	_grabber.release()
	await _steps(600)
	_check(is_instance_valid(body) and _gap(body, surface) >= -0.002 and _gap(body, surface) <= 0.003,
		"Manual hold/release rests visibly on " + furniture)
	_check(body.sleeping, "Manually placed bottle sleeps on " + furniture)
	await _cleanup()


func _movement(furniture: String, action: String) -> void:
	await _setup()
	var candidate := _room.get_node("Furniture/" + furniture)
	_check(candidate is RigidBody3D and candidate.is_in_group("grabbable"), furniture + " participates in shared dynamic physics")
	if not candidate is RigidBody3D:
		await _cleanup()
		return
	var body := candidate as RigidBody3D
	body.position = Vector3(0, 0.02, -0.4)
	body.rotation = Vector3.ZERO
	_player.position = Vector3(0, 0.02, 0.7 if action != "throw" else 1.25)
	_player.rotation.y = 0
	_player.velocity = Vector3.ZERO
	await _steps(120)
	var before := body.global_position
	var peak_horizontal_travel := 0.0
	var centre := body.global_position + Vector3.UP * (0.48 if furniture == "Chair" else 0.3)
	if action == "throw":
		Input.action_press("crouch")
		await _steps(25)
		centre = body.global_position + Vector3(0, 0.75 if furniture == "Chair" else 0.35, 0)
	_player.camera.look_at(centre)
	match action:
		"push":
			Input.action_press("move_forward")
			await _steps(60)
			Input.action_release("move_forward")
		"kick":
			_check(_grabber.get_kick_target().get("collider") == body, "Existing kick geometry reaches " + furniture)
			_grabber._kick()
			await _steps(6)
		"throw":
			var projectile := _prop("metal_prop") as ImpactBody
			projectile.global_position = _player.camera.global_position - _player.camera.global_basis.z * 0.9
			await _steps(5)
			_grabber.try_pick_up()
			_check(_grabber.held_body == projectile, "Pick up existing thrown prop for " + furniture)
			_grabber._throw_rng.seed = 0x9A2 # Reproducible existing tumble, without changing gameplay tuning.
			_grabber.release(true, 1.0)
			var contact := false
			var dynamic_mass := false
			var expected_mass := projectile.mass * body.mass / (projectile.mass + body.mass)
			for frame in 45:
				await _steps(1)
				var displacement := body.global_position - before
				displacement.y = 0.0
				peak_horizontal_travel = maxf(peak_horizontal_travel, displacement.length())
				contact = contact or projectile._touching.has(body.get_rid())
				dynamic_mass = dynamic_mass or (projectile._touching.has(body.get_rid())
					and absf(projectile.last_effective_mass - expected_mass) < 0.001)
			_check(contact and dynamic_mass,
				"Impact system sees dynamic reduced mass against " + furniture)
	if action == "throw":
		print("THROWN FURNITURE: %s peak travel=%.2f mm" % [furniture, peak_horizontal_travel * 1000])
		_check(peak_horizontal_travel > 0.005, "Thrown contact produces horizontal displacement beyond resting slop: " + furniture)
	else:
		_check(body.global_position.distance_to(before) > 0.015, "%s physically moves %s" % [action, furniture])
	Input.action_release("crouch")
	_player.position = Vector3(1.4, 0.02, 1.55)
	_player.velocity = Vector3.ZERO
	await _steps(600)
	_check(body.sleeping and not body.freeze, furniture + " returns to ordinary dynamic sleep after " + action)
	await _cleanup()


func _steps(count: int) -> void:
	for frame in count:
		await physics_frame


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
