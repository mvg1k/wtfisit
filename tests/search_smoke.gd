extends SceneTree

const GAME: PackedScene = preload("res://scenes/search_game.tscn")
const ROOM: PackedScene = preload("res://scenes/search_room.tscn")
const KEYS: PackedScene = preload("res://scenes/props/keys.tscn")
const HUD: Script = preload("res://scripts/search_hud.gd")
const APPROACHES: Dictionary = {
	"BedsideSurface": Vector3(-1.0, 0.02, 1.5),
	"DeskSurface": Vector3(-4.5, 0.02, -5.5),
	"ShelfSurface": Vector3(0.95, 0.02, -4.8),
	"UnderCoveredBox": Vector3(-4.3, 0.02, 5.9),
	"UnderFloorTray": Vector3(-0.8, 0.02, 3),
	"UnderDeskCover": Vector3(-4.5, 0.02, -2),
	"BehindClutterScreen": Vector3(5.6, 0.02, 0.8),
	"UnderBedDeep": Vector3(-4.4, 0.02, 3.45),
	"UnderCouchDeep": Vector3(4.5, 0.02, 3.65),
	"UnderDeskRear": Vector3(-4.6, 0.02, -2.1),
	"UnderBedSide": Vector3(-6.5, 0.02, 1.5),
	"BehindWardrobe": Vector3(6.25, 0.02, -5.8),
	"BehindHeadboard": Vector3(-6, 0.02, -0.6),
	"BehindCouch": Vector3(6.35, 0.02, -0.1),
	"WardrobeTop": Vector3(4.5, 0.82, -3.3),
	"ShelfTop": Vector3(0.2, 1.02, -4.55),
	"HutchTop": Vector3(-3.8, 1.27, -3),
}
var _failures: int = 0
var _completed_events: int = 0
var _game: SearchRun


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_visibility()
	await _test_authored_spots()
	_game = GAME.instantiate() as SearchRun
	root.add_child(_game)
	_game.state_changed.connect(_count_completion)
	await _wait_for_start()
	_check(_game.state == SearchRun.State.SEARCHING, "Game starts a search automatically")
	_check(_game.target is TargetItem and _game.target.is_in_group("grabbable"), "Keys are a physical grabbable target")
	_check(_game.target.global_position.distance_to(_game.current_spot.global_position) < 0.08,
		"Target starts at selected authored spot")
	_check(not _game.debug_search_visible and not _game.get_node("SearchHUD/SearchDebug").visible,
		"Normal gameplay does not reveal the hiding spot")
	_check(_game.get_node("SearchHUD/Objective").text.begins_with("FIND YOUR KEYS"), "Objective is displayed")
	var start_room := _game.room
	_key(KEY_ENTER)
	await _steps(3)
	_check(_game.room == start_room, "Enter cannot skip an active search")
	_game.room.grabber.camera.look_at(_game.target.global_position)
	await _steps(5)
	_check(_game.state == SearchRun.State.SEARCHING, "Looking at keys does not complete the run")
	var player := _game.room.grabber.player
	player.position = Vector3(0, 0.02, 5.4)
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	var wrong := _game.room.get_node("Sandbox/MediumBox") as RigidBody3D
	wrong.global_position = player.camera.global_position + Vector3(0, 0, -2)
	await _steps(1)
	_game.room.grabber.try_pick_up()
	_check(_game.room.grabber.held_body == wrong and _game.state == SearchRun.State.SEARCHING,
		"Picking up a non-target prop does not complete the run")
	_game.room.grabber.release()
	wrong.global_position = Vector3(4, 2, 3)
	_game.target.global_position = player.camera.global_position + Vector3(0, 0, -2)
	await _steps(1)
	_game.room.grabber.try_pick_up()
	_check(_game.state == SearchRun.State.COMPLETED and _game.room.grabber.held_body == _game.target,
		"Actual keys pickup completes through the grabber signal")
	var final_time := _game.elapsed_seconds
	await _steps(20)
	_check(final_time > 0.0 and _game.elapsed_seconds == final_time, "Completion time freezes")
	_check(_completed_events == 1, "Completion emits once")
	_check(_game.get_node("SearchHUD/Result").text.contains("[ENTER] SEARCH AGAIN"), "Result names the actual restart control")
	_key(KEY_R)
	await _steps(2)
	_check(_game.room == start_room, "R remains rotation, not restart")
	var old_target := _game.target
	var old_spot := _game.current_spot.name
	_key(KEY_ENTER)
	await _wait_for_start()
	_check(not is_instance_valid(old_target) and not is_instance_valid(start_room), "Restart removes old room and target")
	_check(_game.state == SearchRun.State.SEARCHING and _game.elapsed_seconds < 0.1, "Restart resets timer and starts another run")
	_check(_game.current_spot.name != old_spot, "Restart avoids the previous spot")
	_check(_game.room.get_node("Sandbox/MediumBox").position.distance_to(Vector3(-0.9, 0.4, -0.6)) < 0.08,
		"Restart restores moved clutter")
	_check(_game.room.grabber.player.position.distance_to(Vector3(0, 0.02, 5.4)) < 0.05,
		"Restart resets the player and held state")
	var seen: Dictionary = {}
	_game._rng.seed = 2026
	var repeated: bool = false
	var extra_targets: bool = false
	for index in 25:
		var previous := _game.current_spot.name
		await _game.start_run()
		repeated = repeated or previous == _game.current_spot.name
		seen[_game.current_spot.name] = true
		var target_count: int = 0
		for child in _game.room.get_children():
			if child is TargetItem:
				target_count += 1
		extra_targets = extra_targets or target_count != 1
	_check(not repeated and seen.size() > 5, "Repeated runs vary authored choices without consecutive repeats")
	_check(not extra_targets, "Repeated restarts keep exactly one target")
	_key(KEY_F4)
	_check(_game.debug_search_visible == OS.is_debug_build(), "Search diagnostics require debug build and explicit toggle")
	_check(_game.get_node("SearchHUD/SearchDebug").text.contains("Action:")
		and _game.get_node("SearchHUD/SearchDebug").text.contains("Spawn rejected:"),
		"Opt-in diagnostics explain action and spawn rejections")
	var before_debug_restart := _game.room
	_key(KEY_F7)
	await _wait_for_start()
	_check(_game.room != before_debug_restart, "Debug reroll rebuilds the room")
	_key(KEY_F4)
	var no_debug_restart := _game.room
	_key(KEY_F7)
	await _steps(3)
	_check(_game.room == no_debug_restart, "Debug reroll is inactive while diagnostics are hidden")
	await _test_invalid_spots()
	_check(HUD.format_time(42.37) == "00:42.37" and HUD.format_time(125.05) == "02:05.05",
		"Timer formats minutes, seconds and hundredths")
	_game.queue_free()
	await process_frame
	print("SEARCH SMOKE: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _test_visibility() -> void:
	var room := ROOM.instantiate() as SearchRoom
	root.add_child(room)
	await _steps(3)
	var item := KEYS.instantiate() as TargetItem
	var spot := SearchSpot.new()
	room.add_child(spot)
	spot.position = Vector3(0, 1, 3)
	_check(spot.clearly_visible_from_spawn(item, room.spawn_eye, room.spawn_frustum),
		"Clear target in initial view is exposed")
	room.grabber.player.rotation.y = PI
	_check(spot.clearly_visible_from_spawn(item, room.spawn_eye, room.spawn_frustum),
		"Spawn snapshot is independent of subsequent camera input")
	spot.position.z = 6
	_check(not spot.clearly_visible_from_spawn(item, room.spawn_eye, room.spawn_frustum),
		"Target behind initial camera is not rejected")
	spot.position.z = 3
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.1, 0.5, 0.1)
	collision.shape = shape
	blocker.add_child(collision)
	room.add_child(blocker)
	blocker.position = Vector3(0.075, 1.31, 4.2)
	await _steps(2)
	var ray := PhysicsRayQueryParameters3D.create(room.spawn_eye, spot.global_position, 5)
	_check(room.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
		and not spot.clearly_visible_from_spawn(item, room.spawn_eye, room.spawn_frustum),
		"Partial occlusion remains eligible even with a clear center ray")
	shape.size.x = 0.6
	for layer: int in [1, 4]:
		blocker.collision_layer = layer
		await _steps(2)
		_check(not spot.clearly_visible_from_spawn(item, room.spawn_eye, room.spawn_frustum),
			"World and prop collision layers both occlude: %d" % layer)
	item.free()
	room.queue_free()
	await _steps(2)


func _test_authored_spots() -> void:
	var hidden_count: int = 0
	for spot_name: String in APPROACHES:
		var room := ROOM.instantiate() as SearchRoom
		root.add_child(room)
		await _steps(2)
		var item := KEYS.instantiate() as TargetItem
		if spot_name == "BedsideSurface":
			_check(room.hidden_from_spawn(room.valid_spots(item), item).size() == 17,
				"All seventeen spots eligible at run-start timing")
		await _steps(120)
		var spots := room.valid_spots(item)
		if spot_name == "BedsideSurface":
			_check(spots.size() == 17, "All seventeen authored spots are clear and compatible")
		var spot := room.spots_root.get_node(NodePath(spot_name)) as SearchSpot
		_check(spot.can_place(item), "Clear spawn: " + spot_name)
		_check(not spot.clearly_visible_from_spawn(item, room.spawn_eye, room.spawn_frustum),
			"Authored spot remains sheltered after clutter settles: " + spot_name)
		room.add_child(item)
		item.global_transform = spot.global_transform
		await _steps(120)
		_check(item.global_position.distance_to(spot.global_position) < 0.12 and item.global_position.y > 0,
			"Keys settle safely at " + spot_name)
		var entrance := room.grabber.camera.global_position
		var ray := PhysicsRayQueryParameters3D.create(entrance, item.global_position, 5)
		var hit := room.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit["collider"] != item:
			hidden_count += 1
		var player := room.grabber.player
		player.position = APPROACHES[spot_name]
		if spot.search_category == SearchSpot.Category.OCCLUDED:
			var covers := {"UnderCoveredBox": "CoveredBox", "UnderFloorTray": "FloorTray",
				"UnderDeskCover": "DeskCover", "BehindClutterScreen": "ClutterScreen"}
			room.get_node(covers[spot_name]).position = Vector3(0, 3, 3)
		if spot.search_category == SearchSpot.Category.LOW_UNDER:
			if spot_name == "UnderDeskRear":
				Input.action_press("crouch")
			else:
				var prone := InputEventAction.new()
				prone.action = "toggle_prone"
				prone.pressed = true
				root.push_input(prone)
		await _steps(30)
		player.camera.look_at(item.global_position)
		if spot.search_category == SearchSpot.Category.HIGH:
			Input.action_press("jump")
			await _steps(2)
			Input.action_release("jump")
			for frame in 40:
				player.camera.look_at(item.global_position)
				room.grabber.try_pick_up()
				if room.grabber.held_body == item:
					break
				await _steps(1)
		else:
			room.grabber.try_pick_up()
		Input.action_release("crouch")
		_check(room.grabber.held_body == item, "Existing grabber can acquire keys at " + spot_name)
		room.grabber.release()
		room.queue_free()
		await _steps(2)
	_check(hidden_count == 17, "All seventeen target centers are occluded from the entrance")


func _test_invalid_spots() -> void:
	for mode: String in ["empty", "disabled", "wrong_category", "solid", "one", "exposed", "mixed", "bad_action"]:
		var fixture := ROOM.instantiate() as SearchRoom
		for spot: SearchSpot in fixture.spots_root.get_children():
			match mode:
				"empty":
					spot.free()
				"disabled":
					spot.enabled = false
				"wrong_category":
					spot.accepted_categories = ["large"]
				"solid":
					spot.position = Vector3(0, -0.2, 0)
				"one":
					spot.enabled = spot.name == &"UnderBedDeep"
				"exposed", "mixed":
					spot.enabled = spot.name == &"BedsideSurface" or (mode == "mixed" and spot.name == &"UnderBedDeep")
					if spot.name == &"BedsideSurface":
						spot.position = Vector3(0, 0.06, 3)
				"bad_action":
					spot.set("intended_action", 99)
		var packed := PackedScene.new()
		_check(packed.pack(fixture) == OK, "Build spot fixture: " + mode)
		fixture.free()
		_game.room_scene = packed
		await _game.start_run()
		if mode in ["one", "mixed"]:
			_check(_game.state == SearchRun.State.SEARCHING, "One valid spot starts normally")
			if mode == "mixed":
				_check(_game.current_spot.name == &"UnderBedDeep" and _game.spawn_visibility_rejected == 1
					and _game.spawn_visibility_checked == 2, "Visible candidate rejected; safe alternative selected")
			await _game.start_run()
			_check(_game.state == SearchRun.State.SEARCHING, "One valid spot may repeat without failure")
		else:
			_check(_game.state == SearchRun.State.UNAVAILABLE and _game.target == null and _game.elapsed_seconds == 0,
				"Graceful unavailable state: " + mode)
			if mode == "exposed":
				_check(_game.spawn_visibility_checked == 1 and _game.spawn_visibility_rejected == 1
					and _game.error_message.contains("exposed"), "All-exposed pool terminates safely without reroll loop")
			if mode == "solid":
				_game.room_scene = ROOM
				_key(KEY_ENTER)
				await _wait_for_start()
				_check(_game.state == SearchRun.State.SEARCHING, "Enter retries an unavailable search")
	_game.room_scene = ROOM
	await _game.start_run()
	_check(_game.state == SearchRun.State.SEARCHING, "Valid configuration recovers after invalid spots")


func _wait_for_start() -> void:
	await _steps(3)
	for index in 60:
		if _game.state != SearchRun.State.PREPARING:
			return
		await physics_frame
	_check(false, "Run preparation timed out")


func _count_completion() -> void:
	if _game.state == SearchRun.State.COMPLETED:
		_completed_events += 1


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event, true)


func _steps(count: int) -> void:
	for index in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
