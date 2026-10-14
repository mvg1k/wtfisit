extends SceneTree

# Focused layout checks; shared mechanics retain their existing suites.
const ROOM: PackedScene = preload("res://scenes/gamers_room.tscn")
var _room: Node3D
var _player: SandboxPlayer
var _grabber: PhysicsGrabber
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_room = ROOM.instantiate()
	root.add_child(_room)
	_player = _room.get_node("Player") as SandboxPlayer
	_grabber = _player.get_node("Grabber") as PhysicsGrabber
	await _steps(120)
	_check(_player.is_on_floor() and _player.position.y < 0.04, "Entrance spawn settles on the floor")
	_check(_player.can_fit_stance(SandboxPlayer.Stance.STANDING), "Entrance has standing clearance")
	_check(get_nodes_in_group("grabbable").size() == 8, "Six props and two movable furniture bodies reuse the grabbable architecture")
	var capsule := _player.body_shape.shape as CapsuleShape3D
	_check(is_equal_approx(capsule.height, 1.8) and is_equal_approx(capsule.radius, 0.3)
		and is_equal_approx(_player.camera.position.y, 1.6), "Adult player and standing eye remain at authored scale")
	_check(is_equal_approx(_player.camera.fov, 75.0) and _player.camera.keep_aspect == Camera3D.KEEP_HEIGHT,
		"Camera retains 75-degree vertical FOV")
	var shell := _room.get_node("Shell")
	_check(is_equal_approx(shell.get_node("EastWallCollision").position.x - 0.1, 2.25)
		and is_equal_approx(shell.get_node("WestWallCollision").position.x + 0.1, -2.25),
		"Room retains 4.5 m interior width")
	_check(is_equal_approx(shell.get_node("CeilingCollision").position.y - 0.075, 2.7), "Ceiling stays at 2.7 m")
	var bed := _room.get_node("Furniture/Bed")
	_check(bed.get_node("Frame").mesh.size.is_equal_approx(Vector3(1.35, 0.12, 2.15)),
		"Visible bed frame retains compact adult-bed dimensions")
	var desk := _room.get_node("Furniture/PCDesk")
	_check(desk.get_node("Top").mesh.size.is_equal_approx(Vector3(1.6, 0.06, 0.72))
		and is_equal_approx(desk.get_node("Top").position.y + 0.03, 0.75), "Visible desk remains 1.6 by 0.72 m at 0.75 m high")
	var table := _room.get_node("Furniture/BedsideTable")
	var gap: float = desk.position.x - 0.8 - (table.position.x + 0.235)
	_check(absf(gap - 0.715) < 0.003 and gap > capsule.radius * 2 + 0.1,
		"Bedside-to-desk pinch point clears the standing capsule with 0.115 m spare")
	# Inset queries by up to 2 cm to ignore resting-contact solver slop.
	for body: PhysicsBody3D in _room.find_children("*", "PhysicsBody3D", true, false):
		if body == _player or body.name == "Shell":
			continue
		_check(not _embedded(body), "%s has no significant settled overlap" % body.name)
	for point: Vector3 in [Vector3(0.1, 0, 0.8), Vector3(-0.1, 0, -0.5),
			Vector3(-0.1, 0, -1.24), Vector3(0.14, 0, -1.50),
			Vector3(0.14, 0, -1.80), Vector3(-0.1, 0, -0.5),
			Vector3(0.65, 0, 0.7), Vector3(1.4, 0, 1.55)]:
		_check(await _walk_to(point), "Walking route reaches %s" % point)
	Input.action_press("crouch")
	await _steps(25)
	_check(_player.stance == SandboxPlayer.Stance.CROUCHING, "Crouch works at the entrance")
	Input.action_release("crouch")
	await _steps(25)
	_player.global_position = Vector3(-0.2, 0.02, -0.65)
	_player.velocity = Vector3.ZERO
	var prone := InputEventAction.new()
	prone.action = "toggle_prone"
	prone.pressed = true
	_player._unhandled_input(prone)
	await _steps(25)
	_check(_player.stance == SandboxPlayer.Stance.PRONE, "Prone uses the existing stance controller")
	_check(await _walk_to(Vector3(-1.4, 0, -0.65)), "Player crawls beneath the bed between its legs")
	_check(not _player.can_fit_stance(SandboxPlayer.Stance.STANDING), "Bed prevents standing through its frame")
	_check(await _walk_to(Vector3(-0.2, 0, -0.65)), "Player crawls back into the aisle")
	_player._unhandled_input(prone)
	await _steps(25)
	_check(_player.stance == SandboxPlayer.Stance.STANDING, "Standing resumes in the aisle")
	# Pick up an authored box from its nook using the camera ray, then throw
	# through the open centre toward the east wall using the unchanged grabber.
	_player.global_position = Vector3(0.25, 0.02, 1.0)
	_player.velocity = Vector3.ZERO
	var box := _room.get_node("MovableProps/MovingBoxB") as RigidBody3D
	_player.camera.look_at(box.global_position, Vector3.UP)
	await _steps(2)
	_grabber.try_pick_up()
	_check(_grabber.held_body == box, "Authored moving box is ray-pickable")
	_player.camera.look_at(Vector3(-1.7, 1.62, 1.0), Vector3.UP)
	await _steps(60)
	# Turn through the open room, keeping the held box away from the wardrobe.
	for frame in 90:
		_player.camera.global_rotation = Vector3(0, lerpf(PI * 0.5, -PI * 0.5, float(frame + 1) / 90.0), 0)
		await physics_frame
		if _grabber.held_body == null:
			break
	_check(_grabber.held_body == box and box.position.y > 0.5, "Box stays held while lifted into clear space")
	_grabber.release(true, 1.0)
	await _steps(30)
	_check(_grabber.held_body == null and box.position.x > 0.4, "Charged throw moves the box across the room")
	_check(box.position.x < 2.3 and not _embedded(box), "Existing sweep keeps the throw inside the room")
	_player.global_position = Vector3(-0.8, 0.02, 0.67)
	_player.velocity = Vector3.ZERO
	var kick_box := _room.get_node("MovableProps/MovingBoxA") as RigidBody3D
	_player.camera.look_at(kick_box.global_position, Vector3.UP)
	await _steps(2)
	_check(_grabber.get_kick_target().get("collider") == kick_box, "Floor box is reachable through the existing kick ray")
	var before_kick := kick_box.global_position
	_grabber._kick()
	await _steps(3)
	_check(kick_box.global_position.distance_to(before_kick) > 0.03, "Kick physically moves the authored box")
	# The monitor variant must retain the original live body and state visuals.
	var monitor := _room.get_node("MovableProps/Monitor") as ImpactBody
	_player.global_position = Vector3(0, 0.02, 0.4)
	_player.velocity = Vector3.ZERO
	_player.camera.look_at(monitor.global_position + Vector3.UP * 0.43, Vector3.UP)
	await _steps(2)
	_grabber.try_pick_up()
	_check(_grabber.held_body == monitor, "Desktop-sized monitor retains pickup behavior")
	_grabber.release()
	# Use a real wall collision to exercise inherited cracked/dead state links.
	monitor.global_position = Vector3(0, 1.25, 0)
	monitor.global_rotation = Vector3.ZERO
	monitor.linear_velocity = Vector3(0, 0, -18)
	await _steps(45)
	_check(monitor.damage_state != ImpactBody.State.INTACT, "Monitor variant responds to a real impact")
	_check(not monitor.intact_visual.visible and
		(monitor.cracked_visual.visible or monitor.broken_visual.visible), "Monitor variant displays its damage state")
	_grabber.release()
	_room.queue_free()
	await process_frame
	print("GAMER'S ROOM: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _embedded(body: PhysicsBody3D) -> bool:
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled:
			continue
		var shape: Shape3D = child.shape.duplicate()
		if shape is BoxShape3D:
			shape.size = (shape.size - Vector3.ONE * 0.04).max(Vector3.ONE * 0.005)
		elif shape is CylinderShape3D:
			shape.radius -= 0.02
			shape.height -= 0.04
		elif shape is ConvexPolygonShape3D:
			var points: PackedVector3Array = shape.points
			for index in points.size():
				points[index] *= 0.95
			shape.points = points
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = child.global_transform
		query.collision_mask = 7
		query.exclude = [body.get_rid()]
		var hits := _room.get_world_3d().direct_space_state.intersect_shape(query, 1)
		if not hits.is_empty():
			print("OVERLAP: %s/%s with %s at %s" % [body.name, child.name, hits[0].collider.name, body.global_position])
			return true
	return false


func _walk_to(point: Vector3) -> bool:
	var reached := false
	for tick in 180:
		var offset := point - _player.global_position
		offset.y = 0
		if offset.length() < 0.1:
			reached = true
			break
		_player.rotation.y = atan2(-offset.x, -offset.z)
		Input.action_press("move_forward")
		await physics_frame
	Input.action_release("move_forward")
	await _steps(18)
	return reached


func _steps(count: int) -> void:
	for frame in count:
		await physics_frame


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)
