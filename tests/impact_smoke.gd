extends SceneTree

const PROP: PackedScene = preload("res://scenes/props/physics_prop.tscn")
var _failures: int = 0
var _world: Node3D
var _grabber: PhysicsGrabber


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(is_equal_approx(ImpactMaterial.severity(2, 0, 8), 4 * ImpactMaterial.severity(2, 0, 4)),
		"Normal impact energy scales with speed squared")
	_check(ImpactMaterial.severity(5, 8, 10) > 15 * ImpactMaterial.severity(5, 0.18, 10)
		and ImpactMaterial.severity(5, 0, 10) > ImpactMaterial.severity(5, 8, 10),
		"Reduced mass distinguishes light, heavy and immovable collisions")
	await _test_gentle()
	await _test_durable()
	for material: String in ["ceramic", "glass"]:
		await _test_fracture(material)
	await _test_electronics()
	await _test_sweep_confirmation()
	await _test_held_break()
	await _test_search_room()
	print("IMPACT SMOKE: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _setup() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(0, -0.2, 0), Vector3(20, 0.4, 20))
	var player := load("res://scenes/player.tscn").instantiate() as SandboxPlayer
	_world.add_child(player)
	player.position = Vector3(15, -20, 0)
	player.set_physics_process(false)
	player.camera.rotation = Vector3.ZERO
	_grabber = player.get_node("Grabber") as PhysicsGrabber
	_grabber._throw_rng.seed = 7
	await _steps(2)


func _cleanup() -> void:
	_world.queue_free()
	await _steps(3)


func _impact_prop(material: String, location: Vector3) -> ImpactBody:
	var path := "monitor" if material == "electronic" else material + "_prop"
	var body := load("res://scenes/props/" + path + ".tscn").instantiate() as ImpactBody
	_world.add_child(body)
	body.position = location
	return body


func _test_gentle() -> void:
	await _setup()
	var ceramic := _impact_prop("ceramic", Vector3(-1, 0.9, 1))
	var glass := _impact_prop("glass", Vector3(1, 0.9, 1))
	await _steps(600)
	_check(is_instance_valid(ceramic) and is_instance_valid(glass), "Gentle brittle drops survive real floor impacts")
	if is_instance_valid(ceramic) and is_instance_valid(glass):
		_check(ceramic.damage_state == ImpactBody.State.INTACT and glass.damage_state == ImpactBody.State.INTACT
			and ceramic.sleeping and glass.sleeping, "Resting contact does not accumulate damage; intact props sleep")
		_check(ceramic.last_impact_severity > 0.5 and glass.last_impact_severity > 0.5,
			"Ordinary contact reporting measures actual drop impacts")
	await _cleanup()


func _test_fracture(material: String) -> void:
	await _setup()
	_box(Vector3(0, 1.5, 0), Vector3(5, 3, 0.07))
	var body := _impact_prop(material, Vector3(0, 1.2, 1.5))
	body.gravity_scale = 0
	var original_mass := body.mass
	await _steps(2)
	_grabber.held_body = body
	_grabber._saved_angular_damp = body.angular_damp
	_grabber.release(true, 1.0)
	await _steps(60)
	var pieces := get_nodes_in_group("impact_debris")
	_check(not is_instance_valid(body) and pieces.size() == ImpactFragments.MAX_PIECES,
		"Maximum swept throw breaks into exactly four pieces: " + material)
	var mass_sum := 0.0
	var ordinary := true
	for piece: RigidBody3D in pieces:
		mass_sum += piece.mass
		ordinary = ordinary and piece is ImpactDebris and not piece is ImpactBody
		ordinary = ordinary and piece.continuous_cd and piece.can_sleep and not piece.freeze
	_check(ordinary and is_equal_approx(mass_sum, original_mass),
		"Debris conserves mass and uses ordinary non-recursive dynamic bodies: " + material)
	await _steps(900)
	var settled := pieces.size() == 4
	for piece: RigidBody3D in pieces:
		settled = settled and piece.sleeping and piece.position.y > 0 and piece.position.z > -0.15
		if not piece.sleeping or piece.position.y <= 0 or piece.position.z <= -0.15:
			print("DEBRIS DETAIL ", material, " position=", piece.position, " sleep=", piece.sleeping,
				" velocity=", piece.linear_velocity, " spin=", piece.angular_velocity)
	_check(settled and get_nodes_in_group("impact_debris").size() == 4,
		"Debris stays bounded, on impact side, settles and sleeps: " + material)
	_check(_grabber._thrown_bodies.is_empty(), "Broken source is removed from sweep tracking: " + material)
	await _cleanup()


func _test_durable() -> void:
	await _setup()
	_box(Vector3(0, 1.5, 0), Vector3(8, 3, 0.2))
	var bodies: Array[ImpactBody] = []
	for material: String in ["plastic", "wood", "metal"]:
		var body := _impact_prop(material, Vector3(-2 + bodies.size() * 2, 1, 1.5))
		body.gravity_scale = 0
		body.lock_rotation = true
		bodies.append(body)
	await _steps(2)
	for body in bodies:
		body.linear_velocity = Vector3(0, 0, -8)
	await _steps(45)
	var survived := true
	for body in bodies:
		survived = survived and body.damage_state == ImpactBody.State.INTACT and body.last_impact_severity > 0.5
	_check(survived, "Plastic, wood and metal tolerate ordinary wall impacts with material-specific thresholds")
	await _cleanup()


func _hit_monitor(monitor: ImpactBody, mass: float, speed: float, swept: bool = false) -> float:
	monitor.position = Vector3.ZERO
	monitor.rotation = Vector3.ZERO
	monitor.linear_velocity = Vector3.ZERO
	monitor.angular_velocity = Vector3.ZERO
	monitor.gravity_scale = 0
	monitor.lock_rotation = true
	await _steps(25)
	var hitter := PROP.instantiate() as RigidBody3D
	hitter.mass = mass
	hitter.gravity_scale = 0
	_world.add_child(hitter)
	hitter.position = Vector3(0, 0.7, 1.5)
	await _steps(2)
	hitter.linear_velocity = Vector3(0, 0, -speed)
	if swept:
		_grabber._thrown_bodies.append(hitter)
	await _steps(35)
	var severity := monitor.last_impact_severity
	hitter.queue_free()
	await _steps(3)
	return severity


func _test_electronics() -> void:
	await _setup()
	var monitor := _impact_prop("electronic", Vector3.ZERO)
	var gentle := await _hit_monitor(monitor, 0.18, 1.5)
	var light := await _hit_monitor(monitor, 0.18, 22.8, true)
	_check(monitor.damage_state == ImpactBody.State.INTACT and light < 70 and light > gentle,
		"A full-speed light prop is measured but does not crack electronics")
	var heavy := await _hit_monitor(monitor, 8.0, 10.0)
	print("IMPACT MEASUREMENTS light=", light, " heavy=", heavy)
	_check(heavy > light * 2 and monitor.damage_state == ImpactBody.State.CRACKED,
		"Unscripted heavy collider cracks monitor through normal contacts; one hit cannot skip states")
	_check(monitor.cracked_visual.visible and not monitor.intact_visual.visible,
		"Cracked monitor displays authored crack geometry")
	await _hit_monitor(monitor, 8.0, 10.0, true)
	_check(monitor.damage_state == ImpactBody.State.BROKEN and monitor.broken_visual.visible
		and not monitor.cracked_visual.visible, "A second meaningful impact leaves a dead screen")
	_check(is_instance_valid(monitor) and not monitor.freeze and get_nodes_in_group("impact_debris").is_empty(),
		"Dead electronics remain one movable body, without fragmentation")
	await _cleanup()


func _test_sweep_confirmation() -> void:
	await _setup()
	var monitor := _impact_prop("electronic", Vector3.ZERO)
	var hitter := PROP.instantiate() as RigidBody3D
	_world.add_child(hitter)
	hitter.position = Vector3(0, 0.7, 2)
	hitter.gravity_scale = 0
	await _steps(2)
	# A real sweep predicts a hit; move the collider away before physics resolves it.
	var query := PhysicsTestMotionParameters3D.new()
	query.from = hitter.global_transform
	query.motion = Vector3(0, 0, -2)
	var result := PhysicsTestMotionResult3D.new()
	_check(PhysicsServer3D.body_test_motion(hitter.get_rid(), query, result), "Near-miss fixture predicts a collision")
	ImpactBody.remember_sweep(hitter, result, Vector3(0, 0, -20))
	hitter.position.x = 4
	await _steps(10)
	_check(monitor.damage_state == ImpactBody.State.INTACT and monitor.last_impact_severity == 0,
		"Predicted contact alone cannot damage a body")
	# Later weak contact from the same RID must not consume an expired strong hint.
	hitter.position = Vector3(0, 0.7, 0.7)
	hitter.linear_velocity = Vector3(0, 0, -1)
	await _steps(40)
	_check(monitor.damage_state == ImpactBody.State.INTACT, "Expired sweep data cannot turn a later weak contact into damage")
	await _cleanup()


func _test_held_break() -> void:
	await _setup()
	_grabber.player.position = Vector3(0, 0.02, 4)
	var ceramic := _impact_prop("ceramic", Vector3(0, 1.62, 2))
	ceramic.gravity_scale = 0
	await _steps(2)
	_grabber.try_pick_up()
	var charge := InputEventMouseButton.new()
	charge.button_index = MOUSE_BUTTON_LEFT
	charge.pressed = true
	root.push_input(charge, true)
	await _steps(8)
	_check(_grabber.held_body == ceramic and _grabber.is_charging_throw, "Break-while-held fixture starts charging")
	var hitter := PROP.instantiate() as RigidBody3D
	hitter.mass = 8
	hitter.gravity_scale = 0
	_world.add_child(hitter)
	hitter.position = Vector3(1.5, 1.62, 2)
	await _steps(2)
	hitter.linear_velocity = Vector3(-12, 0, 0)
	await _steps(30)
	charge.pressed = false
	root.push_input(charge, true)
	await _steps(2)
	_check(not is_instance_valid(ceramic) and not is_instance_valid(_grabber.held_body)
		and not _grabber.is_charging_throw and _grabber.throw_charge == 0 and _grabber._thrown_bodies.is_empty(),
		"Breaking a charged held prop clears safely and cannot cause a delayed throw")
	await _cleanup()


func _test_search_room() -> void:
	var game := load("res://scenes/search_game.tscn").instantiate() as SearchRun
	root.add_child(game)
	await _steps(600)
	var safe := game.state == SearchRun.State.SEARCHING
	var kinds: Dictionary = {}
	for body: ImpactBody in get_nodes_in_group("impact_props"):
		safe = safe and body.damage_state == ImpactBody.State.INTACT and body.sleeping
		kinds[body.impact_material.kind] = true
	_check(safe and kinds.size() == 6, "All six room materials settle intact without idle destruction")
	var keys := game.target
	_check(keys.get_script() == load("res://scripts/target_item.gd") and keys.is_in_group("grabbable"),
		"Keys remain an ordinary, indestructible search target")
	# Make debris inside the actual room, then complete and restart the search.
	var ceramic := game.room.get_node("CeramicVase") as ImpactBody
	ceramic.position = Vector3(0, 2, 3)
	ceramic.linear_velocity = Vector3(0, -15, 0)
	await _steps(60)
	_check(not is_instance_valid(ceramic) and get_nodes_in_group("impact_debris").size() == 4
		and game.state == SearchRun.State.SEARCHING, "Destruction coexists with the active search")
	var grabber := game.room.grabber
	keys.global_position = grabber.camera.global_position - grabber.camera.global_basis.z * 2
	await _steps(2)
	grabber.try_pick_up()
	_check(game.state == SearchRun.State.COMPLETED and grabber.held_body == keys, "Keys can still be picked up with debris present")
	await game.start_run()
	await _steps(3)
	_check(get_nodes_in_group("impact_debris").is_empty() and get_nodes_in_group("impact_props").size() == 6
		and game.state == SearchRun.State.SEARCHING, "Restart clears debris and restores the six intact props")
	game.queue_free()
	await _steps(3)


func _box(location: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_world.add_child(body)
	body.position = location


func _steps(count: int) -> void:
	for frame in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
