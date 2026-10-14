extends SceneTree

# Use an isolated APPDATA when running: settings probes intentionally write user://.
var _checks: int = 0
var _failures: int = 0
var _menu: Node
var _settings: Node
var _render: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings = root.get_node("GameSettings")
	var args := OS.get_cmdline_user_args()
	_render = args.has("--render")
	if not _render:
		root.size = Vector2i(1280, 720)
	if args.has("--settings-read"):
		_check(is_equal_approx(_settings.mouse_sensitivity, 0.0042), "Sensitivity loaded in a new process")
		_check(is_equal_approx(_settings.camera_fov, 91.0), "FOV loaded in a new process")
		_check(is_equal_approx(_settings.master_volume, 0.37), "Volume loaded in a new process")
		_check(_settings.fullscreen, "Fullscreen loaded in a new process")
		change_scene_to_file("res://scenes/main_menu.tscn")
		await _frames(4)
		_menu = current_scene
		_menu.play_game()
		await _frames(6)
		_check(is_equal_approx(_menu.player.mouse_sensitivity, 0.0042) and is_equal_approx(_menu.player.camera.fov, 91.0),
			"A newly launched room uses persisted controls and FOV")
		_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.37), "Persisted volume applies on launch")
		_finish()
		return
	if args.has("--settings-write"):
		_settings.update_setting(&"mouse_sensitivity", 0.0042)
		_settings.update_setting(&"camera_fov", 91.0)
		_settings.update_setting(&"master_volume", 0.37)
		_settings.update_setting(&"fullscreen", true)
		_check(_settings.save_error == OK, "Settings saved to disk")
		_finish()
		return
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main_menu.tscn",
		"F5 resolves to Main Menu")
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _frames(4)
	_menu = current_scene
	_check(_menu.screen == _menu.Screen.MAIN and not paused, "Launch shows the active Main Menu")
	_check(_menu.room == null and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Main Menu has no gameplay and a free cursor")
	_check(root.gui_get_focus_owner().text == "Play", "Play receives keyboard focus")
	await _capture("main_menu")
	# Native keyboard focus navigation and activation, through the real viewport.
	await _key(KEY_DOWN)
	_check(root.gui_get_focus_owner().text == "Settings", "Down navigates to Settings")
	await _key(KEY_ENTER)
	_check(_menu.screen == _menu.Screen.SETTINGS and not paused, "Enter opens Main Menu settings")
	var sensitivity_before: float = _settings.mouse_sensitivity
	await _key(KEY_RIGHT)
	_check(is_equal_approx(_settings.mouse_sensitivity, sensitivity_before + 0.0001), "Keyboard adjusts and saves the focused settings slider")
	await _key(KEY_ESCAPE)
	_check(_menu.screen == _menu.Screen.MAIN, "Escape returns from settings to Main Menu")
	await _key(KEY_ENTER)
	await _frames(8)
	_check(is_instance_valid(_menu.room) and _menu.room.scene_file_path == "res://scenes/gamers_room.tscn",
		"Play launches The Gamer's Room")
	var player: SandboxPlayer = _menu.player
	var grabber: PhysicsGrabber = player.get_node("Grabber")
	_check(player.mouse_captured and not paused, "Play captures the mouse and runs gameplay")
	await _capture("menu_gameplay")
	await _frames(90)
	player.global_position = Vector3(0.25, 0.02, 1.0)
	player.velocity = Vector3.ZERO
	var held_box: RigidBody3D = _menu.room.get_node("MovableProps/MovingBoxB")
	player.camera.look_at(held_box.global_position, Vector3.UP)
	await _frames(2)
	grabber.try_pick_up()
	_check(grabber.held_body == held_box, "Pause fixture uses a real held room prop")
	# Include actions queued in the same frame as Esc, before a physics tick.
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	Input.parse_input_event(interact)
	grabber._kick_requested = true
	grabber.is_charging_throw = true
	grabber._charge_seconds = 0.6
	await _key(KEY_ESCAPE)
	_check(paused and _menu.screen == _menu.Screen.PAUSE, "Escape pauses gameplay")
	_check(not player.mouse_captured and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Pause releases the cursor")
	_check(not grabber._interact_requested and not grabber._kick_requested and not grabber._throw_requested
		and not grabber.is_charging_throw, "Pause clears queued pickup/kick/throw and charge")
	_check(grabber.held_body == null, "Pause safely drops the held prop before freezing")
	_check(root.gui_get_focus_owner().text == "Resume", "Pause focuses Resume")
	await _capture("pause_menu")
	# Space/Enter activate focused native buttons; remove focus to probe gameplay keys.
	root.gui_release_focus()
	var position := player.global_position
	var rotation := player.rotation
	var camera_rotation := player.camera.rotation
	var body: RigidBody3D = _menu.room.get_node("MovableProps/MovingBoxA")
	var body_position := body.global_position
	for key: Key in [KEY_W, KEY_SPACE, KEY_Z, KEY_E, KEY_F3]:
		await _key(key)
	Input.action_press("move_forward")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(140, 50)
	Input.parse_input_event(motion)
	await _frames(15)
	Input.action_release("move_forward")
	_check(player.global_position.is_equal_approx(position) and body.global_position.is_equal_approx(body_position),
		"Player and physics props stay frozen while paused")
	_check(player.rotation.is_equal_approx(rotation) and player.camera.rotation.is_equal_approx(camera_rotation)
		and player.stance == SandboxPlayer.Stance.STANDING, "Look/jump/stance input is blocked while paused")
	_check(not grabber._interact_requested and not grabber._kick_requested, "Paused interaction cannot queue gameplay")
	_menu.open_settings()
	await _frames(3)
	var settings_page: Node = _menu._pages[_menu.Screen.SETTINGS]
	settings_page._sliders[&"mouse_sensitivity"].value = 0.0042
	settings_page._sliders[&"camera_fov"].value = 91
	settings_page._sliders[&"master_volume"].value = 0.37
	_check(is_equal_approx(player.mouse_sensitivity, 0.0042) and is_equal_approx(player.camera.fov, 91),
		"Settings sliders immediately update the existing player")
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.37), "Master volume applies to AudioServer")
	settings_page._sliders[&"master_volume"].value = 0
	_check(AudioServer.is_bus_mute(0), "Zero volume mutes Master")
	settings_page._sliders[&"master_volume"].value = 0.37
	_check(not AudioServer.is_bus_mute(0), "Raising volume unmutes Master")
	settings_page._fullscreen.button_pressed = true
	_check(_settings.fullscreen, "Fullscreen toggle updates saved settings")
	if _render:
		_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Fullscreen applies to the rendered window")
	settings_page._fullscreen.button_pressed = false
	if _render:
		_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Windowed applies to the rendered window")
	_check(paused, "Settings from Pause keep gameplay paused")
	await _capture("settings_menu")
	await _key(KEY_ESCAPE)
	_check(paused and _menu.screen == _menu.Screen.PAUSE, "Settings Back restores Pause")
	await _key(KEY_ESCAPE)
	_check(not paused and player.mouse_captured and _menu.screen == _menu.Screen.PLAYING, "Escape resumes and recaptures mouse")
	var yaw := player.rotation.y
	motion.relative = Vector2(10, 0)
	Input.parse_input_event(motion)
	await _frames(2)
	_check(is_equal_approx(player.rotation.y - yaw, -0.042), "Mouse look uses the configured sensitivity")
	_menu.pause_game()
	await _frames(3)
	await _click(_named_button(_menu.Screen.PAUSE, "Resume"))
	_check(not paused and player.mouse_captured, "Mouse Resume restores gameplay")
	for cycle in 3:
		_menu.pause_game()
		await _frames(3)
		var old_room_id: int = _menu.room.get_instance_id()
		await _click(_named_button(_menu.Screen.PAUSE, "Restart"))
		if cycle == 0:
			_menu.play_game()
			_menu.play_game() # A double activation must not instantiate two rooms.
		await _frames(5)
		_check(not paused and _menu.player.mouse_captured and _menu.room.get_instance_id() != old_room_id,
			"Restart %d rebuilds the room and resumes" % (cycle + 1))
		_check(_menu.get_node("Gameplay").get_child_count() == 1, "Restart leaves exactly one room")
		_check(is_equal_approx(_menu.player.camera.fov, 91) and is_equal_approx(_menu.player.mouse_sensitivity, 0.0042),
			"Restart retains player settings")
		_menu.pause_game()
		await _frames(3)
		await _click(_named_button(_menu.Screen.PAUSE, "Main Menu"))
		await _frames(5)
		_check(not paused and _menu.room == null and _menu.screen == _menu.Screen.MAIN,
			"Main Menu %d clears gameplay and pause state" % (cycle + 1))
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and root.gui_get_focus_owner().text == "Play",
			"Main Menu restores cursor and focus")
		# Activate Play with native mouse input, ensuring the UI also supports clicking.
		await _click(_menu._first_focus[_menu.Screen.MAIN])
		await _frames(5)
		_check(_menu.screen == _menu.Screen.PLAYING, "Mouse Play works after returning to Main Menu")
	_menu._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(paused and _menu.screen == _menu.Screen.PAUSE, "Focus loss safely pauses gameplay")
	if _render:
		_menu.return_to_main()
		await _frames(5)
		DisplayServer.window_set_size(Vector2i(800, 450))
		await _frames(8)
		await _capture("main_menu_800x450")
		_menu.open_settings()
		DisplayServer.window_set_size(Vector2i(640, 360))
		await _frames(8)
		await _capture("settings_menu_640x360")
	paused = false
	_finish()


func _named_button(page: int, title: String) -> Button:
	for control: Node in _menu._pages[page].get_children():
		if control is Button and control.text == title:
			return control
	return null


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _capture(title: String) -> void:
	if not _render:
		return
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.validation/" + title + ".png")


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("MENU: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
