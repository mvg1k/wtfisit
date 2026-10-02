extends SceneTree

const ROOM: PackedScene = preload("res://scenes/search_room.tscn")
const KEYS: PackedScene = preload("res://scenes/props/keys.tscn")
var _failures: int = 0
var _room: SearchRoom
var _player: SandboxPlayer


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_categories()
	await _test_bedside_table()
	for data: Array in [
		["UnderCoveredBox", "CoveredBox", Vector3(-4.3, 0.02, 5.9)],
		["UnderFloorTray", "FloorTray", Vector3(-0.8, 0.02, 3.0)],
		["UnderDeskCover", "DeskCover", Vector3(-4.5, 0.02, -2.0)],
		["BehindClutterScreen", "ClutterScreen", Vector3(5.6, 0.02, 0.8)],
	]:
		await _test_cover(data[0], data[1], data[2])
	for data: Array in [
		["UnderBedDeep", Vector3(-4.4, 0.02, 3.45), true],
		["UnderCouchDeep", Vector3(4.5, 0.02, 3.65), true],
		["UnderDeskRear", Vector3(-4.6, 0.02, -2.1), false],
	]:
		await _test_low(data[0], data[1], data[2])
	for data: Array in [
		["WardrobeTop", "WardrobeStep", Vector3(4.5, 0.02, -1.7), 0.8],
		["ShelfTop", "ShelfStep", Vector3(0.2, 0.02, -2.95), 1.0],
		["HutchTop", "DeskStep", Vector3(-1.9, 0.02, -1.55), 0.7],
	]:
		await _test_high(data[0], data[1], data[2], data[3])
	print("PHYSICAL SEARCH SMOKE: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _setup(position: Vector3) -> void:
	_room = ROOM.instantiate() as SearchRoom
	root.add_child(_room)
	_player = _room.grabber.player
	_player.position = position
	await _steps(90)


func _keys(spot_name: String) -> TargetItem:
	var keys := KEYS.instantiate() as TargetItem
	_room.add_child(keys)
	keys.global_transform = (_room.spots_root.get_node(NodePath(spot_name)) as SearchSpot).global_transform
	return keys


func _cleanup() -> void:
	Input.action_release("crouch")
	Input.action_release("move_forward")
	Input.action_release("jump")
	_room.queue_free()
	await _steps(3)


func _test_bedside_table() -> void:
	await _setup(Vector3(-2, 0.02, 3.5))
	var table := _room.get_node("BedsideTable") as RigidBody3D
	_check(table != null and table.is_in_group("grabbable"), "Small bedside furniture is one movable, grabbable body")
	if table == null:
		await _cleanup()
		return
	await _steps(120)
	_check(table.sleeping, "Bedside table settles with its existing clutter")
	var start := table.global_position
	_face(start)
	Input.action_press("move_forward")
	await _steps(45)
	Input.action_release("move_forward")
	_check(table.global_position.distance_to(start) > 0.1, "Walking into the bedside table moves it with existing pushing")
	await _cleanup()


func _test_cover(spot_name: String, cover_name: String, position: Vector3) -> void:
	await _setup(position)
	var keys := _keys(spot_name)
	var cover := _room.get_node(NodePath(cover_name)) as RigidBody3D
	await _steps(30)
	_player.camera.look_at(keys.global_position)
	_room.grabber.try_pick_up()
	_check(_room.grabber.held_body == cover, "Cover blocks keys and is actually pickupable: " + spot_name)
	# Lift by looking up, as a player does; continuing to aim at the floor can
	# request a hold target inside the player's clearance sphere and release it.
	_player.camera.rotation.x = 0.0
	await _steps(90)
	_check(cover.global_position.y > 1.0, "Existing spring physically lifts cover: " + spot_name)
	var turn := -1.0 if position.x < 0.0 else 1.0
	for index in 24:
		_player.rotate_y(turn * PI / 48.0)
		await _steps(2)
	_room.grabber.release()
	await _steps(45)
	_player.camera.look_at(keys.global_position)
	_room.grabber.try_pick_up()
	_check(_room.grabber.held_body == keys, "Keys can be acquired after physically moving cover: " + spot_name)
	await _cleanup()


func _test_low(spot_name: String, position: Vector3, prone: bool) -> void:
	await _setup(position)
	var keys := _keys(spot_name)
	await _steps(30)
	_player.camera.look_at(keys.global_position)
	_room.grabber.try_pick_up()
	_check(_room.grabber.held_body != keys, "Standing viewpoint is blocked: " + spot_name)
	Input.action_press("crouch")
	await _steps(25)
	_player.camera.look_at(keys.global_position)
	if prone:
		_room.grabber.try_pick_up()
		_check(_room.grabber.held_body != keys, "Crouching still cannot see deep target: " + spot_name)
		Input.action_release("crouch")
		_prone()
		await _steps(25)
	_player.camera.look_at(keys.global_position)
	_room.grabber.try_pick_up()
	_check(_room.grabber.held_body == keys, "Lower stance exposes retrievable keys: " + spot_name)
	_room.grabber.release()
	if spot_name == "UnderBedDeep":
		_face(Vector3(-4.4, 0, 1.1))
		Input.action_press("move_forward")
		await _steps(70)
		Input.action_release("move_forward")
		await _steps(20)
		_check(_player.position.z < 2.5, "Prone collider can physically crawl underneath bed")
		_prone()
		await _steps(20)
		_check(_player.stance == SandboxPlayer.Stance.PRONE, "Bed blocks standing up while underneath")
	await _cleanup()


func _test_high(spot_name: String, step_name: String, position: Vector3, top: float) -> void:
	await _setup(position)
	var keys := _keys(spot_name)
	await _steps(30)
	await _jump_and_try_keys(keys)
	_check(_room.grabber.held_body != keys, "Floor-level jumping cannot bypass high search: " + spot_name)
	await _steps(60)
	var step := _room.get_node(NodePath(step_name)) as RigidBody3D
	_check(step.is_in_group("grabbable") and not step.freeze, "Climbing support is a movable physics prop: " + step_name)
	await _jump_onto(step.global_position, top)
	_check(_player.is_on_floor() and absf(_player.position.y - top) < 0.07,
		"Normal movement/jump lands on movable box: " + spot_name)
	await _steps(120)
	_check(step.linear_velocity.length() < 0.1 and _player.velocity.length() < 0.1,
		"Standing on physics box remains stable: " + spot_name)
	if spot_name == "HutchTop":
		await _jump_onto(Vector3(-3.8, 1.25, -2.95), 1.25)
		_check(_player.is_on_floor() and absf(_player.position.y - 1.25) < 0.07,
			"Normal jumping climbs from movable box to desktop")
	await _jump_and_try_keys(keys)
	_check(_room.grabber.held_body == keys, "High keys recovered using ordinary jumps and physics support: " + spot_name)
	await _cleanup()


func _jump_onto(destination: Vector3, _top: float) -> void:
	_face(destination)
	Input.action_press("jump")
	await _steps(2)
	Input.action_release("jump")
	await _steps(8)
	Input.action_press("move_forward")
	for frame in 100:
		var distance := Vector2(_player.position.x - destination.x, _player.position.z - destination.z).length()
		# Brake before the destination and steer during diagonal acceleration.
		if distance < 0.3:
			break
		_face(destination)
		await _steps(1)
	Input.action_release("move_forward")
	await _steps(65)


func _jump_and_try_keys(keys: TargetItem) -> void:
	Input.action_press("jump")
	await _steps(2)
	Input.action_release("jump")
	for frame in 40:
		_player.camera.look_at(keys.global_position)
		_room.grabber.try_pick_up()
		if _room.grabber.held_body == keys:
			return
		await _steps(1)


func _face(destination: Vector3) -> void:
	var direction := destination - _player.position
	_player.rotation.y = atan2(-direction.x, -direction.z)
	_player.camera.rotation = Vector3.ZERO


func _test_categories() -> void:
	await _setup(Vector3(0, 0.02, 5.4))
	var counts := [0, 0, 0, 0, 0]
	var actions := [0, 0, 0, 0, 0]
	var valid_actions := true
	var spots: Array[SearchSpot] = []
	for spot: SearchSpot in _room.spots_root.get_children():
		counts[spot.search_category] += 1
		if SearchSpot.Action.values().has(spot.intended_action):
			actions[spot.intended_action] += 1
		else:
			valid_actions = false
		spots.append(spot)
	_check(counts == [3, 4, 4, 3, 3], "Spot distribution is 3 surface, 4 covered, 4 low, 3 behind, 3 high")
	_check(valid_actions and actions == [6, 1, 3, 4, 3], "Valid actions: 6 visual, 1 crouch, 3 prone, 4 move prop, 3 climb")
	var run := SearchRun.new()
	run._rng.seed = 94
	var previous: Array[int] = []
	var seen: Dictionary = {}
	var varied: bool = true
	for index in 100:
		var selected := run._choose_spot(spots)
		varied = varied and not previous.has(selected.search_category)
		seen[selected.search_category] = true
		previous.append(selected.search_category)
		if previous.size() > 2:
			previous.pop_front()
	_check(varied and seen.size() == 5, "Selection cycles behavior categories without either of the last two")
	var pair: Array[SearchSpot] = [spots[0], spots[3]]
	var last: int = -1
	var alternating: bool = true
	for index in 20:
		var selected := run._choose_spot(pair)
		alternating = alternating and selected.search_category != last
		last = selected.search_category
	_check(alternating, "Category avoidance degrades cleanly with only two categories")
	run.free()
	await _cleanup()


func _prone() -> void:
	var event := InputEventAction.new()
	event.action = "toggle_prone"
	event.pressed = true
	root.push_input(event)


func _steps(count: int) -> void:
	for index in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
